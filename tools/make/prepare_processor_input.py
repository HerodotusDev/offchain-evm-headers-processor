#!venv/bin/python3
import json
import time
from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async, bytes_to_little_endian_ints
from tools.py.poseidon.poseidon_hash import poseidon_hash_many
from tools.py.mmr import MMR, get_peaks
file = open("tools/make/processor_input.json", "r")
data = json.load(file)
file.close()

assert data["previous_block_high"] > data["previous_block_low"] > data["from_block_number_high"] > data["to_block_number_low"] 
assert data["previous_block_low"] -1 == data["from_block_number_high"]


blocks = fetch_blocks_from_rpc_no_async(data["from_block_number_high"], data["to_block_number_low"]-1, 'https://eth-mainnet.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9')
blocks.reverse()
print([x.number for x in blocks])
blocks = [block.raw_rlp() for block in blocks]
blocks_len = [len(block) for block in blocks]
blocks = [bytes_to_little_endian_ints(block) for block in blocks]

data["rlp_arrays"] = blocks
data["bytes_len_array"] = blocks_len 

## MMR peaks and root pre-computation
mmr = MMR()


prev_blocks = fetch_blocks_from_rpc_no_async(data["previous_block_high"], data["previous_block_low"]-1, 'https://eth-mainnet.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9')
prev_blocks.reverse()
prev_blocks = [block.raw_rlp() for block in prev_blocks]
prev_blocks = [bytes_to_little_endian_ints(block) for block in prev_blocks]
prev_blocks_poseidon = [poseidon_hash_many(block) for block in prev_blocks]

for hash in prev_blocks_poseidon:
    mmr.add(hash)

mmr_root = mmr.get_root()
print(mmr_root)

data['mmr_last_root'] = mmr_root
data['mmr_last_len'] = len(mmr.pos_hash)
peaks_positions =get_peaks(len(mmr.pos_hash))
peaks_hashes = [mmr.pos_hash[p] for p in peaks_positions]
data['mmr_last_peaks'] = peaks_hashes


with open('src/single_chunk_processor/chunk_processor_input.json', 'w') as f:
    json.dump(data, f)


