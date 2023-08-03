#!venv/bin/python3
import json
import time
import os
from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async, bytes_to_little_endian_ints
import requests
from tools.py.poseidon.poseidon_hash import poseidon_hash_many, poseidon_hash

def mkdir_if_not_exists(path: str):
    isExist = os.path.exists(path)
    if not isExist:
        os.makedirs(path)
        print(f"Directory created : {path} ")

GOERLI = 'goerli'
MAINNET = 'mainnet'

NETWORK = GOERLI
ALCHEMY_RPC = f'https://eth-{NETWORK}.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9'

if NETWORK == GOERLI:
    RPC_BACKEND_URL = "http://localhost:8545"
else:
    RPC_BACKEND_URL = ALCHEMY_RPC


def split_128(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)

def rpc_request(url, rpc_request):
    headers = {'Content-Type': 'application/json'}
    response = requests.post(url=url, headers=headers, data=json.dumps(rpc_request))
    print(f"Status code: {response.status_code}")
    print(f"Response content: {response.content}")
    return response.json()

def write_to_json(filename, data):
    """Helper function to write data to a json file"""
    with open(filename, 'w') as f:
        json.dump(data, f, indent=4)

def prepare_chunk_input(last_peaks:dict, last_mmr_size:int, last_mmr_root:dict, from_block_number_high:int, to_block_number_low) -> json:
    chunk_input={}
    chunk_output={}
    blocks = fetch_blocks_from_rpc_no_async(from_block_number_high+1, to_block_number_low-1, ALCHEMY_RPC)
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



def prepare_full_chain_inputs(from_block_number_high, to_block_number_low = 0, batch_size=50):
    """Main function to prepare the full chain inputs."""
    # Error handling for input
    if from_block_number_high < to_block_number_low:
        raise ValueError("Start block should be higher than end block")
    
    if batch_size <= 0:
        raise ValueError("Batch size should be greater than 0")

    PATH = "src/single_chunk_processor/data/"
    mkdir_if_not_exists(PATH)

    to_block_number_batch_low = max(from_block_number_high - batch_size + 1, to_block_number_low)

    last_peaks = {'poseidon':[968420142673072399148736368629862114747721166432438466378474074601992041181], 'keccak':[93435818137180840214006077901347441834554899062844693462640230920378475721064]} 
    last_mmr_size = 1
    last_mmr_root = {'poseidon':last_peaks['poseidon'][0], 'keccak':last_peaks['keccak'][0]}

    while from_block_number_high >= to_block_number_low:
        print(f"Preparing input for blocks from {from_block_number_high} to {to_block_number_batch_low}")

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

        from_block_number_high -= batch_size
        to_block_number_batch_low = max(from_block_number_high - batch_size + 1, to_block_number_low)

    print("Full chain inputs prepared successfully")


prepare_full_chain_inputs(from_block_number_high=100, to_block_number_low=0, batch_size=20)

