#!venv/bin/python3
import json
import time
import os
from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async
from tools.py.utils import split_128, bytes_to_little_endian_ints
import requests
from dotenv import load_dotenv

def mkdir_if_not_exists(path: str):
    isExist = os.path.exists(path)
    if not isExist:
        os.makedirs(path)
        print(f"Directory created : {path} ")

load_dotenv()

GOERLI = 'goerli'
MAINNET = 'mainnet'

NETWORK = GOERLI
RPC_URL = os.getenv("RPC_URL_GOERLI") if NETWORK == GOERLI else os.getenv("RPC_URL_MAINNET")

if NETWORK == GOERLI:
    RPC_BACKEND_URL = "http://localhost:8545"
else:
    RPC_BACKEND_URL = RPC_URL



def rpc_request(url, rpc_request):
    headers = {'Content-Type': 'application/json'}
    response = requests.post(url=url, headers=headers, data=json.dumps(rpc_request))
    # print(f"Status code: {response.status_code}")
    # print(f"Response content: {response.content}")
    return response.json()

def write_to_json(filename, data):
    """Helper function to write data to a json file"""
    with open(filename, 'w') as f:
        json.dump(data, f, indent=4)

def prepare_chunk_input(last_peaks:dict, last_mmr_size:int, last_mmr_root:dict, from_block_number_high:int, to_block_number_low) -> json:
    chunk_input={}
    chunk_output={}
    blocks = fetch_blocks_from_rpc_no_async(from_block_number_high+1, to_block_number_low-1, RPC_URL)
    blocks.reverse()
    block_n_plus_one = blocks[-1]
    block_n_minus_r_plus_one = blocks[0]
    block_n_plus_one_parent_hash_little = split_128(int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), 'little'))
    block_n_plus_one_parent_hash_big = split_128(int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), 'big'))
    block_n_minus_r_plus_one_parent_hash_big = split_128(int.from_bytes(bytes.fromhex(block_n_minus_r_plus_one.parentHash.hex()[2:]), 'big'))


    blocks = blocks[:-1]
    # print([x.number for x in blocks])
    blocks = [block.raw_rlp() for block in blocks]
    blocks_len = [len(block) for block in blocks]
    blocks = [bytes_to_little_endian_ints(block) for block in blocks]

    chunk_input['mmr_last_root_poseidon'] = last_mmr_root['poseidon']
    chunk_input['mmr_last_root_keccak_low'], chunk_input['mmr_last_root_keccak_high']= split_128(last_mmr_root['keccak'])
    chunk_input['mmr_last_len'] = last_mmr_size
    chunk_input['poseidon_mmr_last_peaks'] = last_peaks['poseidon']
    chunk_input['keccak_mmr_last_peaks'] = [split_128(x) for x in last_peaks['keccak']]
    chunk_input['from_block_number_high'] = from_block_number_high
    chunk_input['to_block_number_low'] = to_block_number_low
    chunk_input['block_n_plus_one_parent_hash_little_low'] = block_n_plus_one_parent_hash_little[0]
    chunk_input['block_n_plus_one_parent_hash_little_high'] = block_n_plus_one_parent_hash_little[1]
    chunk_input["block_headers_array"] = blocks
    chunk_input["bytes_len_array"] = blocks_len 

    chunk_output['from_block_number_high'] = from_block_number_high
    chunk_output['to_block_number_low'] = to_block_number_low
    chunk_output['block_n_plus_one_parent_hash_low'], chunk_output['block_n_plus_one_parent_hash_high']=block_n_plus_one_parent_hash_big
    chunk_output['block_n_minus_r_plus_one_parent_hash_low'], chunk_output['block_n_minus_r_plus_one_parent_hash_high']=block_n_minus_r_plus_one_parent_hash_big
    chunk_output['mmr_last_root_poseidon'] = last_mmr_root['poseidon']
    chunk_output['mmr_last_root_keccak_low'], chunk_output['mmr_last_root_keccak_high'] = split_128(last_mmr_root['keccak'])
    chunk_output['mmr_last_len'] = last_mmr_size


                 
    return chunk_input, chunk_output

def process_chunk(last_peaks:dict, last_mmr_size:int, from_block_number_high:int, to_block_number_low) -> dict:
    """Calls the chunk_process_api and processes the returned data."""
    params = {
        "chunk_size":50, 
        "poseidon_last_elements_count":last_mmr_size,
        "poseidon_last_peaks":[hex(x) for x in last_peaks['poseidon']], 
        "keccak_last_elements_count":last_mmr_size,
        "keccak_last_peaks":[hex(x) for x in last_peaks['keccak']],
        "start_block": to_block_number_low, 
        "end_block": from_block_number_high, 
        'rpc_url':RPC_BACKEND_URL, 
        "max_retries_per_request":3, 
        "append_in_reverse":True
    }

    response = rpc_request('http://3.10.105.11:8000/precompute-mmr',  params)
    
    return {
        'last_peaks': {
            'poseidon': [int(x, 16) for x in response['poseidon_mmr']['peaks']],
            'keccak': [int(x, 16) for x in response['keccak_mmr']['peaks']]
        },
        'last_mmr_size': response['poseidon_mmr']['tree_size'],
        'last_mmr_root': {
            'poseidon': int(response['poseidon_mmr']['root_hash'], 16),
            'keccak': int(response['keccak_mmr']['root_hash'], 16)
        }
    }



def prepare_full_chain_inputs(from_block_number_high, to_block_number_low=0, batch_size=50, 
                              initial_peaks=None, initial_mmr_size=None, initial_mmr_root=None):
    """Main function to prepare the full chain inputs."""
    # Error handling for input
    if from_block_number_high < to_block_number_low:
        raise ValueError("Start block should be higher than end block")

    if batch_size <= 0:
        raise ValueError("Batch size should be greater than 0")

    # Default initialization values
    if initial_peaks is None or initial_mmr_size is None or initial_mmr_root is None:
        initial_peaks = {'poseidon': [968420142673072399148736368629862114747721166432438466378474074601992041181], 
                         'keccak': [93435818137180840214006077901347441834554899062844693462640230920378475721064]}
        initial_mmr_size = 1
        initial_mmr_root = {'poseidon': initial_peaks['poseidon'][0], 'keccak': initial_peaks['keccak'][0]}

    assert set(initial_peaks.keys()) == {'poseidon', 'keccak'}, f"Initial peaks should be a dict with keys 'poseidon' and 'keccak', got {initial_peaks.keys()}"
    assert set(initial_mmr_root.keys()) == {'poseidon', 'keccak'}, f"Initial mmr root should be a dict with keys 'poseidon' and 'keccak', got {initial_mmr_root.keys()}"
    assert len(initial_peaks['poseidon']) == len(initial_peaks['keccak'])
    assert type(initial_mmr_size) == int
    
    last_peaks = initial_peaks
    last_mmr_size = initial_mmr_size
    last_mmr_root = initial_mmr_root

    PATH = "src/single_chunk_processor/data/"
    mkdir_if_not_exists(PATH)

    to_block_number_batch_low = max(from_block_number_high - batch_size + 1, to_block_number_low)

    print(f"Preparing inputs and precomputing outputs for blocks from {from_block_number_high} to {to_block_number_low} with batch size {batch_size}")

    while from_block_number_high >= to_block_number_low:
        print(f"\tPreparing input and pre-computing output for blocks from {from_block_number_high} to {to_block_number_batch_low}")

        chunk_input, chunk_output  = prepare_chunk_input(last_peaks, last_mmr_size, last_mmr_root, from_block_number_high, to_block_number_batch_low)

        # Save the chunk input data
        write_to_json(f"{PATH}blocks_{from_block_number_high}_{to_block_number_batch_low}_input.json", chunk_input)

        try:
            data = process_chunk(last_peaks, last_mmr_size, from_block_number_high, to_block_number_batch_low)
        except Exception as e:
            print(f"Failed to process chunk: {e}")
            break

        last_peaks = data['last_peaks']
        last_mmr_size = data['last_mmr_size']
        last_mmr_root = data['last_mmr_root']

        chunk_output['new_mmr_root_poseidon'] = last_mmr_root['poseidon']
        chunk_output['new_mmr_root_keccak_low'], chunk_output['new_mmr_root_keccak_high'] = split_128(last_mmr_root['keccak'])
        chunk_output['new_mmr_len'] = last_mmr_size

        # Save the chunk output data
        write_to_json(f"{PATH}blocks_{from_block_number_high}_{to_block_number_batch_low}_output.json", chunk_output)

        time.sleep(0.5)

        from_block_number_high = from_block_number_high - batch_size
        to_block_number_batch_low = max(from_block_number_high - batch_size + 1, to_block_number_low)

    print(f"Inputs and outputs for requested blocks are ready and saved to {PATH}\n")

    return last_peaks, last_mmr_size, last_mmr_root


if __name__ == "__main__":
    # Prepare _inputs.json and pre-compute _outputs.json for blocks 20 to 0:
    peaks, size, roots = prepare_full_chain_inputs(from_block_number_high=20, to_block_number_low=0, batch_size=5)
    # Prepare _inputs.json and pre-compute _outputs.json for blocks 30 to 21, using the last peaks, size and roots from the previous run:
    prepare_full_chain_inputs(from_block_number_high=30, to_block_number_low=21, batch_size=5, initial_peaks=peaks, initial_mmr_size=size, initial_mmr_root=roots)

