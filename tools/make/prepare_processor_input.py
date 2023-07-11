#!venv/bin/python3
import json
from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async, bytes_to_little_endian_ints
from tools.py.poseidon.poseidon_hash import poseidon_hash_many
from tools.py.mmr import MMR
file = open("tools/make/processor_input.json", "r")
data = json.load(file)
file.close()
print(data)


blocks = fetch_blocks_from_rpc_no_async(data["from_block_number_high"], data["to_block_number_low"]-1, 'https://eth-mainnet.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9')
blocks.reverse()
print([x.number for x in blocks])
blocks = [block.raw_rlp() for block in blocks]
blocks_len = [len(block) for block in blocks]
blocks = [bytes_to_little_endian_ints(block) for block in blocks]
blocks_poseidon = [poseidon_hash_many(block) for block in blocks]

data["rlp_arrays"] = blocks
data["bytes_len_array"] = blocks_len 

with open('src/single_chunk_processor/chunk_processor_input.json', 'w') as f:
    json.dump(data, f)

file.close()
# mmr = MMR()


# for hash in blocks_poseidon:
#     mmr.add(hash)

# mmr_root = mmr.get_root()
# print(mmr_root)
