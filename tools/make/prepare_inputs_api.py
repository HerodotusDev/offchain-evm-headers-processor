#!venv/bin/python3
import json
import time
import os
import requests
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

## Set the two parameters below :

NETWORK = MAINNET  # MAINNET or GOERLI
PROCESS = API  # API or LOCAL

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


def prepare_chunk_input(
    last_peaks: dict,
    last_mmr_size: int,
    last_mmr_root: dict,
    from_block_number_high: int,
    to_block_number_low,
    process=PROCESS,
) -> json:
    chunk_input = {}
    chunk_output = {}
    t0 = time.time()
    blocks = fetch_blocks_from_rpc_no_async(
        from_block_number_high + 1, to_block_number_low - 1, RPC_URL
    )
    t1 = time.time()
    print(
        f"\tFetched {from_block_number_high+1 - to_block_number_low} blocs in {t1-t0}s"
    )
    t0 = time.time()
    blocks.reverse()
    block_n_plus_one = blocks[-1]
    block_n_minus_r_plus_one = blocks[0]
    block_n_plus_one_parent_hash_little = split_128(
        int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), "little")
    )
    block_n_plus_one_parent_hash_big = split_128(
        int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), "big")
    )
    block_n_minus_r_plus_one_parent_hash_big = split_128(
        int.from_bytes(
            bytes.fromhex(block_n_minus_r_plus_one.parentHash.hex()[2:]), "big"
        )
    )

    blocks = blocks[:-1]
    # print([x.number for x in blocks])

    if process == LOCAL:
        keccak_hashes = [
            int.from_bytes(bytes.fromhex(block.hash().hex()[2:]), "big")
            for block in blocks
        ]
    blocks = [block.raw_rlp() for block in blocks]
    if process == LOCAL:
        poseidon_hashes = [
            poseidon_hash_many(bytes_to_8_bytes_chunks_little(block))
            for block in blocks
        ]

    blocks_len = [len(block) for block in blocks]
    blocks = [bytes_to_8_bytes_chunks_little(block) for block in blocks]

    chunk_input["mmr_last_root_poseidon"] = last_mmr_root["poseidon"]
    (
        chunk_input["mmr_last_root_keccak_low"],
        chunk_input["mmr_last_root_keccak_high"],
    ) = split_128(last_mmr_root["keccak"])
    chunk_input["mmr_last_len"] = last_mmr_size
    chunk_input["poseidon_mmr_last_peaks"] = last_peaks["poseidon"]
    chunk_input["keccak_mmr_last_peaks"] = [split_128(x) for x in last_peaks["keccak"]]
    chunk_input["from_block_number_high"] = from_block_number_high
    chunk_input["to_block_number_low"] = to_block_number_low
    chunk_input[
        "block_n_plus_one_parent_hash_little_low"
    ] = block_n_plus_one_parent_hash_little[0]
    chunk_input[
        "block_n_plus_one_parent_hash_little_high"
    ] = block_n_plus_one_parent_hash_little[1]
    chunk_input["block_headers_array"] = blocks
    chunk_input["bytes_len_array"] = blocks_len

    chunk_output["from_block_number_high"] = from_block_number_high
    chunk_output["to_block_number_low"] = to_block_number_low
    (
        chunk_output["block_n_plus_one_parent_hash_low"],
        chunk_output["block_n_plus_one_parent_hash_high"],
    ) = block_n_plus_one_parent_hash_big
    (
        chunk_output["block_n_minus_r_plus_one_parent_hash_low"],
        chunk_output["block_n_minus_r_plus_one_parent_hash_high"],
    ) = block_n_minus_r_plus_one_parent_hash_big
    chunk_output["mmr_last_root_poseidon"] = last_mmr_root["poseidon"]
    (
        chunk_output["mmr_last_root_keccak_low"],
        chunk_output["mmr_last_root_keccak_high"],
    ) = split_128(last_mmr_root["keccak"])
    chunk_output["mmr_last_len"] = last_mmr_size

    t1 = time.time()
    print(f"\tPrepared chunk input with {PROCESS} process in {t1-t0}s")
    if process == LOCAL:
        assert len(poseidon_hashes) == len(keccak_hashes) == len(blocks)
        return chunk_input, chunk_output, (poseidon_hashes, keccak_hashes)
    else:
        return chunk_input, chunk_output, None


def process_chunk(chunk_input, local_process: tuple, process=PROCESS) -> dict:
    if process == API:
        return process_chunk_api(chunk_input)
    elif process == LOCAL:
        return process_chunk_local(chunk_input, *local_process)
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

    for i, pos in enumerate(peaks_positions):
        # print(f"i: {i}, pos: {pos}")
        # print(f"Adding peak at position {pos} with hash {chunk_input['poseidon_mmr_last_peaks'][i]} and {from_uint256(chunk_input['keccak_mmr_last_peaks'][i])}")
        mmr_poseidon.pos_hash[pos] = chunk_input["poseidon_mmr_last_peaks"][i]
        mmr_keccak.pos_hash[pos] = from_uint256(chunk_input["keccak_mmr_last_peaks"][i])

    mmr_poseidon.last_pos = chunk_input["mmr_last_len"] - 1
    mmr_keccak.last_pos = chunk_input["mmr_last_len"] - 1

    print(f"last pos: {mmr_poseidon.last_pos}, last len: {mmr_poseidon.last_pos + 1}")
    for hash_pos, hash_keccak in zip(
        reversed(poseidon_block_hashes), reversed(keccak_block_hashes)
    ):
        mmr_poseidon.add(hash_pos)
        mmr_keccak.add(hash_keccak)

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
            break

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
        from_block_number_high=17800000, to_block_number_low=17000000 - 3, batch_size=4
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
