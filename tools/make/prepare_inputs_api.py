#!venv/bin/python3
import json
import time
from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async, bytes_to_little_endian_ints
import requests
from tools.py.poseidon.poseidon_hash import poseidon_hash_many, poseidon_hash
import sha3

file = open("tools/make/processor_input.json", "r")
data = json.load(file)
file.close()

assert data["previous_block_high"] > data["previous_block_low"] > data["from_block_number_high"] > data["to_block_number_low"] 
assert data["previous_block_low"] -1 == data["from_block_number_high"]

def split_128(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


blocks = fetch_blocks_from_rpc_no_async(data["from_block_number_high"]+1, data["to_block_number_low"]-1, 'https://eth-mainnet.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9')
blocks.reverse()
block_n_plus_one = blocks[-1]
parent_hash_input = split_128(int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), 'little'))

blocks = blocks[:-1]
print([x.number for x in blocks])
blocks = [block.raw_rlp() for block in blocks]
blocks_len = [len(block) for block in blocks]
blocks = [bytes_to_little_endian_ints(block) for block in blocks]

data["rlp_arrays"] = blocks
data["bytes_len_array"] = blocks_len 


def rpc_request(url, rpc_request):
    headers = {'Content-Type': 'application/json'}
    response = requests.post(url=url, headers=headers, data=json.dumps(rpc_request))
    print(f"Status code: {response.status_code}")
    print(f"Response content: {response.content}")
    return response.json()


params0 = {"chunk_size":10, 
          "last_elements_count":0, 
          "last_peaks":[], 
          "start_block": data["previous_block_low"], 
          "end_block": data['previous_block_high'], 
          'rpc_url':"https://eth-mainnet.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9", 
          "max_retries_per_request":3, 
          "append_in_reverse":True}


test = rpc_request('http://3.10.105.11:8000/precompute-mmr',  params0)

params1 = {"chunk_size":10, 
          "last_elements_count":test['tree_size'], 
          "last_peaks":test['peaks'], 
          "start_block": data["to_block_number_low"],
          "end_block": data['from_block_number_high'], 
          'rpc_url':"https://eth-mainnet.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9", 
          "max_retries_per_request":3, 
          "append_in_reverse":True}


test1 = rpc_request('http://3.10.105.11:8000/precompute-mmr',  params1)


data['mmr_last_root'] = int(test['root_hash'],16)
data['mmr_last_len'] = test['tree_size']
peaks_hashes = [int(x, 16) for x in test['peaks']]
data['mmr_last_peaks'] = peaks_hashes
data['block_n_plus_one_parent_hash_little_low'] = parent_hash_input[0]
data['block_n_plus_one_parent_hash_little_high'] = parent_hash_input[1]



with open('src/single_chunk_processor/chunk_processor_input.json', 'w') as f:
    json.dump(data, f)


