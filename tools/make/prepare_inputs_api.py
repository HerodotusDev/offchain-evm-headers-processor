#!venv/bin/python3
import time
import sha3
import math
import sqlite3
from typing import Tuple, List
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
from tools.py.utils import (
    split_128,
    from_uint256,
    bytes_to_8_bytes_chunks_little,
    write_to_json,
    create_directory,
    validate_initial_params,
)
from tools.py.mmr import (
    MMR,
    get_peaks,
    PoseidonHasher,
    KeccakHasher,
    MockedHasher,
)
from tools.py.poseidon.poseidon_hash import poseidon_hash_many, poseidon_hash
from tools.make.db import (
    fetch_block_range_from_db,
    create_connection,
    get_min_max_block_numbers,
)
from tools.make.sharp_submit_params import MAX_RESOURCES_PER_JOB


MAX_KECCAK_ROUNDS = MAX_RESOURCES_PER_JOB["builtin_instance_counter"]["keccak_builtin"]
DYNAMIC_BATCH_SIZE_START = 1700
KECCAK_FULL_RATE_IN_BYTES = 136


def compute_hashes(block: bytes) -> Tuple[int, int]:
    # Compute Keccak hash
    k = sha3.keccak_256()
    k.update(block)
    digest = k.digest()
    keccak_hash = int.from_bytes(digest, "big")

    # Compute Poseidon hash
    poseidon_hash = poseidon_hash_many(bytes_to_8_bytes_chunks_little(block))
    return keccak_hash, poseidon_hash


def prepare_chunk_input(
    last_peaks: dict,
    last_mmr_size: int,
    last_mmr_root: dict,
    from_block_number_high: int,
    to_block_number_low,
    conn=None,
) -> Tuple[dict, dict, Tuple[List[int], List[int]]]:
    chunk_input = {}
    chunk_output = {}
    t0_db = time.time()
    blocks_data = fetch_block_range_from_db(
        end=from_block_number_high + 1, start=to_block_number_low, conn=conn
    )
    assert (
        len(blocks_data) == from_block_number_high - to_block_number_low + 2
    ), f"Db request for blocks {from_block_number_high + 1} to {to_block_number_low} returned {len(blocks_data)} blocks instead of {from_block_number_high + 1 - to_block_number_low + 1}"

    assert type(blocks_data[0][1]) == bytes
    assert blocks_data[0][0] == to_block_number_low
    assert blocks_data[-1][0] == from_block_number_high + 1
    blocks = [block[1] for block in blocks_data]
    t1_db = time.time()
    print(f"\t\tFetched {len(blocks)} blocks from DB in {t1_db-t0_db}s")

    block_n_plus_one_parent_hash_little = split_128(
        int.from_bytes(blocks[-1][4:36], "little")
    )
    block_n_plus_one_parent_hash_big = split_128(
        int.from_bytes(blocks[-1][4:36], "big")
    )
    block_n_minus_r_plus_one_parent_hash_big = split_128(
        int.from_bytes(blocks[0][4:36], "big")
    )
    blocks = blocks[:-1]
    assert len(blocks) == from_block_number_high - to_block_number_low + 1

    keccak_hashes = []
    poseidon_hashes = []

    with ProcessPoolExecutor() as executor:
        for keccak_result, poseidon_result in executor.map(compute_hashes, blocks):
            keccak_hashes.append(keccak_result)
            poseidon_hashes.append(poseidon_result)

    blocks_len = [len(block) for block in blocks]
    blocks = [bytes_to_8_bytes_chunks_little(block) for block in blocks]

    chunk_input = {
        "mmr_last_root_poseidon": last_mmr_root["poseidon"],
        "mmr_last_root_keccak_low": split_128(last_mmr_root["keccak"])[0],
        "mmr_last_root_keccak_high": split_128(last_mmr_root["keccak"])[1],
        "mmr_last_len": last_mmr_size,
        "poseidon_mmr_last_peaks": last_peaks["poseidon"],
        "keccak_mmr_last_peaks": [split_128(x) for x in last_peaks["keccak"]],
        "from_block_number_high": from_block_number_high,
        "to_block_number_low": to_block_number_low,
        "block_n_plus_one_parent_hash_little_low": block_n_plus_one_parent_hash_little[
            0
        ],
        "block_n_plus_one_parent_hash_little_high": block_n_plus_one_parent_hash_little[
            1
        ],
        "block_headers_array": blocks,
        "bytes_len_array": blocks_len,
    }

    chunk_output = {
        "from_block_number_high": from_block_number_high,
        "to_block_number_low": to_block_number_low,
        "block_n_plus_one_parent_hash_low": block_n_plus_one_parent_hash_big[0],
        "block_n_plus_one_parent_hash_high": block_n_plus_one_parent_hash_big[1],
        "block_n_minus_r_plus_one_parent_hash_low": block_n_minus_r_plus_one_parent_hash_big[
            0
        ],
        "block_n_minus_r_plus_one_parent_hash_high": block_n_minus_r_plus_one_parent_hash_big[
            1
        ],
        "mmr_last_root_poseidon": last_mmr_root["poseidon"],
        "mmr_last_root_keccak_low": split_128(last_mmr_root["keccak"])[0],
        "mmr_last_root_keccak_high": split_128(last_mmr_root["keccak"])[1],
        "mmr_last_len": last_mmr_size,
    }

    t1 = time.time()
    print(f"\t\tPrepared chunk input in {t1-t0_db}s")
    return chunk_input, chunk_output, (poseidon_hashes, keccak_hashes)


def extend_mmr(
    mmr: MMR, hashes: list, peaks_positions: list, peaks: list, last_pos: int
):
    for i, pos in enumerate(peaks_positions):
        mmr.pos_hash[pos] = peaks[i]

    mmr.last_pos = last_pos

    for hash_val in reversed(hashes):
        mmr.add(hash_val)

    return mmr


def process_chunk(
    chunk_input, poseidon_block_hashes: list, keccak_block_hashes: list
) -> dict:
    mmr_poseidon = MMR(PoseidonHasher())
    mmr_keccak = MMR(KeccakHasher())
    peaks_positions = get_peaks(chunk_input["mmr_last_len"])
    assert len(poseidon_block_hashes) == len(keccak_block_hashes)
    assert (
        len(peaks_positions)
        == len(chunk_input["poseidon_mmr_last_peaks"])
        == len(chunk_input["keccak_mmr_last_peaks"])
    )

    with ThreadPoolExecutor(max_workers=2) as executor:
        future_poseidon = executor.submit(
            extend_mmr,
            mmr_poseidon,
            poseidon_block_hashes,
            peaks_positions,
            chunk_input["poseidon_mmr_last_peaks"],
            chunk_input["mmr_last_len"] - 1,
        )

        future_keccak = executor.submit(
            extend_mmr,
            mmr_keccak,
            keccak_block_hashes,
            peaks_positions,
            [from_uint256(val) for val in chunk_input["keccak_mmr_last_peaks"]],
            chunk_input["mmr_last_len"] - 1,
        )

        # Wait for both futures to complete
        future_poseidon.result()
        future_keccak.result()

    return {
        "last_peaks": {
            "poseidon": mmr_poseidon.get_peaks(),
            "keccak": mmr_keccak.get_peaks(),
        },
        "last_mmr_size": mmr_poseidon.last_pos + 1,
        "last_mmr_root": {
            "poseidon": mmr_poseidon.get_root(),
            "keccak": mmr_keccak.get_root(),
        },
    }


def compute_dynamic_batch_size(
    from_block_number_high, initial_mmr_size: int, conn: sqlite3.Connection
) -> int:
    keccak_rounds = MAX_KECCAK_ROUNDS + 1
    batch_size = DYNAMIC_BATCH_SIZE_START
    blocks = fetch_block_range_from_db(
        end=from_block_number_high,
        start=from_block_number_high - batch_size + 1,
        conn=conn,
    )
    bytes_lens = [len(block[1]) for block in blocks]
    while keccak_rounds > MAX_KECCAK_ROUNDS:
        keccaks_per_block = [
            math.ceil(bytes_len / KECCAK_FULL_RATE_IN_BYTES) for bytes_len in bytes_lens
        ]

        mocked_mmr = MMR(MockedHasher())
        peaks_positions = get_peaks(initial_mmr_size)
        mocked_mmr.last_pos = initial_mmr_size - 1
        for pos in peaks_positions:
            mocked_mmr.pos_hash[pos] = pos
        mocked_mmr.get_root()  # Initial root verification
        for _ in range(batch_size):
            mocked_mmr.add(0)
        mocked_mmr.get_root()  # New root computation

        keccak_rounds = sum(keccaks_per_block) + mocked_mmr._hasher.hash_count
        if keccak_rounds > MAX_KECCAK_ROUNDS:
            batch_size = batch_size - 1
            bytes_lens = bytes_lens[1:]

    print(f"Computed batch size: {batch_size}")
    print(f"Predicted # keccak rounds: {keccak_rounds}")
    return batch_size


def prepare_full_chain_inputs(
    from_block_number_high: int,
    to_block_number_low: int = 0,
    batch_size: int = 50,
    dynamic: bool = False,
    initial_params: dict = None,
):
    t0 = time.time()
    """Main function to prepare the full chain inputs."""
    # Error handling for input
    if from_block_number_high < to_block_number_low:
        raise ValueError("Start block should be higher than end block")

    if batch_size <= 0:
        raise ValueError("Batch size should be greater than 0")

    # Default initialization values
    if initial_params is None:
        initial_peaks = {
            "poseidon": [
                968420142673072399148736368629862114747721166432438466378474074601992041181
            ],
            "keccak": [
                93435818137180840214006077901347441834554899062844693462640230920378475721064
            ],
        }
        initial_mmr_size = 1
        k = KeccakHasher()
        k.update(initial_mmr_size)
        k.update(initial_peaks["keccak"][0])
        initial_mmr_roots = {
            "poseidon": poseidon_hash(initial_mmr_size, initial_peaks["poseidon"][0]),
            "keccak": k.digest(),
        }
        print("Init roots", initial_mmr_roots)
    else:
        validate_initial_params(initial_params)
        initial_peaks = initial_params["mmr_peaks"]
        initial_mmr_size = initial_params["mmr_size"]
        initial_mmr_roots = initial_params["mmr_roots"]

    last_peaks = initial_peaks
    last_mmr_size = initial_mmr_size
    last_mmr_roots = initial_mmr_roots

    PATH = "src/single_chunk_processor/data/"
    create_directory(PATH)

    with create_connection() as conn:
        (_, max) = get_min_max_block_numbers(conn)
        if from_block_number_high > max - 1:
            raise ValueError(
                f"Start block {from_block_number_high} is not in the database. Max block number supported is {max-1}\n"
                f"Consider updating the database with 'make db-update'",
            )
        if dynamic:
            batch_size = compute_dynamic_batch_size(
                from_block_number_high, initial_mmr_size, conn
            )

        to_block_number_batch_low = max(
            from_block_number_high - batch_size + 1, to_block_number_low
        )

        print(
            f"Preparing inputs and precomputing outputs for blocks from {from_block_number_high} to {to_block_number_low} with batch size {batch_size if not dynamic else 'dynamic'}"
        )

        while from_block_number_high >= to_block_number_low:
            print(
                f"\tPreparing input and pre-computing output for blocks from {from_block_number_high} to {to_block_number_batch_low}"
            )

            (chunk_input, chunk_output, hashes) = prepare_chunk_input(
                last_peaks,
                last_mmr_size,
                last_mmr_roots,
                from_block_number_high,
                to_block_number_batch_low,
                conn=conn,
            )

            # Save the chunk input data
            write_to_json(
                f"{PATH}blocks_{from_block_number_high}_{to_block_number_batch_low}_input.json",
                chunk_input,
            )

            try:
                data = process_chunk(chunk_input, hashes[0], hashes[1])
            except Exception as e:
                print(f"Failed to process chunk: {e}")
                raise

            last_peaks = data["last_peaks"]
            last_mmr_size = data["last_mmr_size"]
            last_mmr_roots = data["last_mmr_root"]

            chunk_output["new_mmr_root_poseidon"] = last_mmr_roots["poseidon"]
            (
                chunk_output["new_mmr_root_keccak_low"],
                chunk_output["new_mmr_root_keccak_high"],
            ) = split_128(last_mmr_roots["keccak"])
            chunk_output["new_mmr_len"] = last_mmr_size

            # Save the chunk output data
            write_to_json(
                f"{PATH}blocks_{from_block_number_high}_{to_block_number_batch_low}_output.json",
                chunk_output,
            )

            from_block_number_high = from_block_number_high - batch_size

            if dynamic:
                batch_size = compute_dynamic_batch_size(
                    from_block_number_high, last_mmr_size, conn
                )

            to_block_number_batch_low = max(
                from_block_number_high - batch_size + 1, to_block_number_low
            )
            print(to_block_number_batch_low)

    print(f"Inputs and outputs for requested blocks are ready and saved to {PATH}\n")
    print(f"Time taken : {time.time() - t0}s")

    return {
        "mmr_peaks": last_peaks,
        "mmr_size": last_mmr_size,
        "mmr_roots": last_mmr_roots,
    }


if __name__ == "__main__":
    output = prepare_full_chain_inputs(
        from_block_number_high=18000000,
        to_block_number_low=0,
        batch_size=1420,
        dynamic=True,
    )

    # Prepare _inputs.json and pre-compute _outputs.json using the last peaks, size and roots from the previous run:
    # prepare_full_chain_inputs(
    #     from_block_number_high=30,
    #     to_block_number_low=21,
    #     batch_size=5,
    #     initial_params=output,
    # )
