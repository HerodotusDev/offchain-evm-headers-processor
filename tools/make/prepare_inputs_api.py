#!venv/bin/python3
import json
import time
import os
from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async, bytes_to_little_endian_ints
import requests
from tools.py.poseidon.poseidon_hash import poseidon_hash_many, poseidon_hash
import sha3

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


def prepare_chunk_input(last_peaks:list, last_mmr_size:int, last_mmr_root:int, from_block_number_high:int, to_block_number_low) -> json:
    data={}
    blocks = fetch_blocks_from_rpc_no_async(from_block_number_high+1, to_block_number_low-1, ALCHEMY_RPC)
    blocks.reverse()
    block_n_plus_one = blocks[-1]
    parent_hash_input = split_128(int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), 'little'))

    blocks = blocks[:-1]
    # print([x.number for x in blocks])
    blocks = [block.raw_rlp() for block in blocks]
    blocks_len = [len(block) for block in blocks]
    blocks = [bytes_to_little_endian_ints(block) for block in blocks]

    data['mmr_last_root'] = last_mmr_root
    data['mmr_last_len'] = last_mmr_size
    data['mmr_last_peaks'] = last_peaks
    data['from_block_number_high'] = from_block_number_high
    data['to_block_number_low'] = to_block_number_low
    data['block_n_plus_one_parent_hash_little_low'] = parent_hash_input[0]
    data['block_n_plus_one_parent_hash_little_high'] = parent_hash_input[1]
    data["rlp_arrays"] = blocks
    data["bytes_len_array"] = blocks_len 

    return data

def chunk_process_api(last_peaks:list, last_mmr_size:int, from_block_number_high:int, to_block_number_low) -> json:
    data={}

    params = {"chunk_size":50, 
          "last_elements_count":last_mmr_size, 
          "last_peaks":[hex(x) for x in last_peaks], 
          "start_block": to_block_number_low, 
          "end_block": from_block_number_high, 
          'rpc_url':RPC_BACKEND_URL, 
          "max_retries_per_request":3, 
          "append_in_reverse":True}


    test = rpc_request('http://3.10.105.11:8000/precompute-mmr',  params)
    data['mmr_last_root'] = int(test['root_hash'],16)
    data['mmr_last_len'] = test['tree_size']
    peaks_hashes = [int(x, 16) for x in test['peaks']]
    data['mmr_last_peaks'] = peaks_hashes

    return data

def prepare_full_chain_inputs(from_block_number_high, batch_size=50):
    PATH = "src/single_chunk_processor/data/"
    mkdir_if_not_exists(PATH)
    from_block_number_high = from_block_number_high
    to_block_number_low = from_block_number_high - batch_size + 1

    last_peaks = [511165008604479100545509010942618724] # 'brave new world' in Cairo
    last_mmr_size = 1
    last_mmr_root = poseidon_hash(last_mmr_size, last_peaks[0])

    print(f"Preparing input for blocks from {from_block_number_high} to {to_block_number_low}")
    
    chunk_input = prepare_chunk_input(last_peaks, last_mmr_size, last_mmr_root, from_block_number_high, to_block_number_low)
    with open(f"{PATH}blocks_{from_block_number_high}_{to_block_number_low}_input.json", 'w') as f:
        json.dump(chunk_input, f, indent=4)

    previous_block_high = from_block_number_high
    previous_block_low = to_block_number_low
    from_block_number_high = to_block_number_low - 1


    to_block_number_low = from_block_number_high - batch_size + 1 if from_block_number_high - batch_size + 1 >= 0 else 0

    if to_block_number_low==0:
        return


    while to_block_number_low >= 0:
        print(f"Preparing input for blocks from {from_block_number_high} to {to_block_number_low}")
        previous_chunk_data = chunk_process_api(last_peaks, last_mmr_size, previous_block_high, previous_block_low)
        last_peaks = previous_chunk_data['mmr_last_peaks']
        last_mmr_size = previous_chunk_data['mmr_last_len']
        last_mmr_root = previous_chunk_data['mmr_last_root']
        
        time.sleep(0.5)
        chunk_input = prepare_chunk_input(last_peaks, last_mmr_size, last_mmr_root, from_block_number_high, to_block_number_low)
        with open(f"{PATH}blocks_{from_block_number_high}_{to_block_number_low}_input.json", 'w') as f:
            json.dump(chunk_input, f, indent=4)
        
        if to_block_number_low==0:
            break

        previous_block_high = from_block_number_high
        previous_block_low = to_block_number_low
        from_block_number_high = to_block_number_low - 1


        to_block_number_low = from_block_number_high - batch_size + 1 if from_block_number_high - batch_size + 1 >= 0 else 0


        

prepare_full_chain_inputs(100,20)


