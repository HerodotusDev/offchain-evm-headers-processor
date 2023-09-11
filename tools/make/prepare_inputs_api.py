#!venv/bin/python3
import json
import time
import os
import requests
import sha3
import concurrent.futures
from concurrent.futures import ThreadPoolExecutor
from dotenv import load_dotenv
from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async
from tools.py.utils import (
    split_128,
    from_uint256,
    bytes_to_8_bytes_chunks_little,
    write_to_json,
)
from tools.py.mmr import MMR, get_peaks, PoseidonHasher, KeccakHasher
from tools.py.poseidon.poseidon_hash import poseidon_hash_many, poseidon_hash
from tools.make.db import fetch_block_range_from_db, create_connection


def mkdir_if_not_exists(path: str):
    isExist = os.path.exists(path)
    if not isExist:
        os.makedirs(path)
        print(f"Directory created : {path} ")


load_dotenv()

GOERLI = "goerli"
MAINNET = "mainnet"
LOCAL = "local"
API = "api"

## Set the 3 parameters below :

NETWORK = MAINNET  # MAINNET or GOERLI
PROCESS = LOCAL  # API or LOCAL
USE_DB = True  # True or False
## Get the RPC and backend service URLs from the .env file
RPC_URL = (
    os.getenv("RPC_URL_GOERLI") if NETWORK == GOERLI else os.getenv("RPC_URL_MAINNET")
)
BACKEND_SERVICE_URL = (
    os.getenv("BACKEND_SERVICE_MAINNET")
    if NETWORK == MAINNET
    else os.getenv("BACKEND_SERVICE_GOERLI")
)
RPC_BACKEND_URL = "http://localhost:8545"

print(RPC_URL)
print(BACKEND_SERVICE_URL)


def rpc_request(url, rpc_request):
    headers = {"Content-Type": "application/json"}
    response = requests.post(url=url, headers=headers, data=json.dumps(rpc_request))
    # print(f"Status code: {response.status_code}")
    # print(f"Response content: {response.content}")
    return response.json()


def compute_hashes(block):
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
    process=PROCESS,
    use_db=USE_DB,
    conn=None,
) -> json:
    chunk_input = {}
    chunk_output = {}
    t0_db = time.time()
    if use_db:
        assert conn is not None, "Database connection must be provided for DB mode."
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

    else:
        blocks = fetch_blocks_from_rpc_no_async(
            from_block_number_high + 1, to_block_number_low - 1, RPC_URL
        )

        blocks.reverse()

        block_n_plus_one = blocks[-1]
        assert block_n_plus_one.number == from_block_number_high + 1
        block_n_minus_r_plus_one = blocks[0]
        assert block_n_minus_r_plus_one.number == to_block_number_low

        blocks = [block.raw_rlp() for block in blocks]
        t1_db = time.time()
        print(f"\t\tFetched {len(blocks)} blocks from RPC in {t1_db-t0_db}s")

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

    if process == LOCAL:
        keccak_hashes = []
        poseidon_hashes = []

        with concurrent.futures.ProcessPoolExecutor() as executor:
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
    print(
        f"\t\tPrepared chunk input with {PROCESS} process and {'Local Db' if use_db else 'RPC'} fetching in {t1-t0_db}s"
    )
    if process == LOCAL:
        assert (
            len(poseidon_hashes)
            == len(keccak_hashes)
            == len(blocks)
            == from_block_number_high - to_block_number_low + 1
        )
        return chunk_input, chunk_output, (poseidon_hashes, keccak_hashes)
    else:
        return chunk_input, chunk_output, None


def process_chunk(chunk_input, local_process: tuple, process=PROCESS) -> dict:
    t0 = time.time()
    if process == API:
        res = process_chunk_api(chunk_input)
        t1 = time.time()
        print(f"\t\tProcessed chunk with API process in {t1-t0}s")
        return res
    elif process == LOCAL:
        res = process_chunk_local(chunk_input, *local_process)
        t1 = time.time()
        print(f"\t\tProcessed chunk with Local process in {t1-t0}s")
        return res
    else:
        raise ValueError(f"Unknown process: {process}")


def process_chunk_api(chunk_input) -> dict:
    """Calls the chunk_process_api and processes the returned data."""
    params = {
        "chunk_size": 50,
        "poseidon_last_elements_count": chunk_input["mmr_last_len"],
        "poseidon_last_peaks": [hex(x) for x in chunk_input["poseidon_mmr_last_peaks"]],
        "keccak_last_elements_count": chunk_input["mmr_last_len"],
        "keccak_last_peaks": [
            hex(from_uint256(x)) for x in chunk_input["keccak_mmr_last_peaks"]
        ],
        "start_block": chunk_input["to_block_number_low"],
        "end_block": chunk_input["from_block_number_high"],
        "rpc_url": RPC_BACKEND_URL,
        "max_retries_per_request": 3,
        "append_in_reverse": True,
    }

    response = rpc_request(BACKEND_SERVICE_URL, params)

    return {
        "last_peaks": {
            "poseidon": [int(x, 16) for x in response["poseidon_mmr"]["peaks"]],
            "keccak": [int(x, 16) for x in response["keccak_mmr"]["peaks"]],
        },
        "last_mmr_size": response["poseidon_mmr"]["tree_size"],
        "last_mmr_root": {
            "poseidon": int(response["poseidon_mmr"]["root_hash"], 16),
            "keccak": int(response["keccak_mmr"]["root_hash"], 16),
        },
    }


def extend_mmr(
    mmr: MMR, hashes: list, peaks_positions: list, peaks: list, last_pos: int
):
    for i, pos in enumerate(peaks_positions):
        mmr.pos_hash[pos] = peaks[i]

    mmr.last_pos = last_pos

    for hash_val in reversed(hashes):
        mmr.add(hash_val)

    return mmr


def process_chunk_local(
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


def prepare_full_chain_inputs(
    from_block_number_high,
    to_block_number_low=0,
    batch_size=50,
    initial_peaks=None,
    initial_mmr_size=None,
    initial_mmr_root=None,
):
    t0 = time.time()
    """Main function to prepare the full chain inputs."""
    # Error handling for input
    if from_block_number_high < to_block_number_low:
        raise ValueError("Start block should be higher than end block")

    if batch_size <= 0:
        raise ValueError("Batch size should be greater than 0")

    # Default initialization values
    if initial_peaks is None or initial_mmr_size is None or initial_mmr_root is None:
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
        initial_mmr_root = {
            "poseidon": poseidon_hash(initial_mmr_size, initial_peaks["poseidon"][0]),
            "keccak": k.digest(),
        }
        print("Init root", initial_mmr_root)
    assert set(initial_peaks.keys()) == {
        "poseidon",
        "keccak",
    }, f"Initial peaks should be a dict with keys 'poseidon' and 'keccak', got {initial_peaks.keys()}"
    assert set(initial_mmr_root.keys()) == {
        "poseidon",
        "keccak",
    }, f"Initial mmr root should be a dict with keys 'poseidon' and 'keccak', got {initial_mmr_root.keys()}"
    assert len(initial_peaks["poseidon"]) == len(initial_peaks["keccak"])
    assert type(initial_mmr_size) == int

    last_peaks = initial_peaks
    last_mmr_size = initial_mmr_size
    last_mmr_root = initial_mmr_root

    PATH = "src/single_chunk_processor/data/"
    mkdir_if_not_exists(PATH)

    to_block_number_batch_low = max(
        from_block_number_high - batch_size + 1, to_block_number_low
    )

    print(
        f"Preparing inputs and precomputing outputs for blocks from {from_block_number_high} to {to_block_number_low} with batch size {batch_size}"
    )
    connexion = create_connection() if USE_DB else None

    while from_block_number_high >= to_block_number_low:
        print(
            f"\tPreparing input and pre-computing output for blocks from {from_block_number_high} to {to_block_number_batch_low}"
        )

        chunk_input, chunk_output, local_process = prepare_chunk_input(
            last_peaks,
            last_mmr_size,
            last_mmr_root,
            from_block_number_high,
            to_block_number_batch_low,
            process=PROCESS,
            use_db=USE_DB,
            conn=connexion,
        )

        # Save the chunk input data
        write_to_json(
            f"{PATH}blocks_{from_block_number_high}_{to_block_number_batch_low}_input.json",
            chunk_input,
        )

        try:
            data = process_chunk(chunk_input, local_process)
        except Exception as e:
            print(f"Failed to process chunk: {e}")
            raise

        last_peaks = data["last_peaks"]
        last_mmr_size = data["last_mmr_size"]
        last_mmr_root = data["last_mmr_root"]

        chunk_output["new_mmr_root_poseidon"] = last_mmr_root["poseidon"]
        (
            chunk_output["new_mmr_root_keccak_low"],
            chunk_output["new_mmr_root_keccak_high"],
        ) = split_128(last_mmr_root["keccak"])
        chunk_output["new_mmr_len"] = last_mmr_size

        # Save the chunk output data
        write_to_json(
            f"{PATH}blocks_{from_block_number_high}_{to_block_number_batch_low}_output.json",
            chunk_output,
        )

        time.sleep(0.5)

        from_block_number_high = from_block_number_high - batch_size
        to_block_number_batch_low = max(
            from_block_number_high - batch_size + 1, to_block_number_low
        )

    print(f"Inputs and outputs for requested blocks are ready and saved to {PATH}\n")
    print(f"Time taken : {time.time() - t0}s")

    return last_peaks, last_mmr_size, last_mmr_root


if __name__ == "__main__":
    # Prepare _inputs.json and pre-compute _outputs.json for blocks 20 to 0:
    peaks, size, roots = prepare_full_chain_inputs(
        from_block_number_high=15000, to_block_number_low=0, batch_size=1420
    )
    # Prepare _inputs.json and pre-compute _outputs.json for blocks 30 to 21, using the last peaks, size and roots from the previous run:
    # prepare_full_chain_inputs(
    #     from_block_number_high=30,
    #     to_block_number_low=21,
    #     batch_size=5,
    #     initial_peaks=peaks,
    #     initial_mmr_size=size,
    #     initial_mmr_root=roots,
    # )
