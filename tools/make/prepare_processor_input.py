#!venv/bin/python3
import json
import time
from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async, bytes_to_little_endian_ints, bytes_to_8_bytes_chunks
from tools.py.poseidon.poseidon_hash import poseidon_hash_many
from tools.py.mmr import MMR, get_peaks
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
block_n_plus_one_parent_hash_little = split_128(int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), 'little'))
blocks = blocks[:-1]

print([x.number for x in blocks])
blocks = [block.raw_rlp() for block in blocks]
raw_rlps = blocks.copy()
blocks_len = [len(block) for block in blocks]
blocks = [bytes_to_little_endian_ints(block) for block in blocks]
blocks_len_reversed=[sum(x.bit_length() for x in block) for block in blocks]

print(blocks_len)
print(blocks_len_reversed)
data["rlp_arrays"] = blocks
data["bytes_len_array"] = blocks_len 
data['block_n_plus_one_parent_hash_little_low'] = block_n_plus_one_parent_hash_little[0]
data['block_n_plus_one_parent_hash_little_high'] = block_n_plus_one_parent_hash_little[1]
## MMR peaks and root pre-computation
mmr = MMR()


prev_blocks = fetch_blocks_from_rpc_no_async(data["previous_block_high"]+1, data["previous_block_low"]-1, 'https://eth-mainnet.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9')
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


with open('src/single_chunk_processor/data/single_input.json', 'w') as f:
    json.dump(data, f, indent=4)


rlp=raw_rlps[0]
rlp_hex=rlp.hex()
rlp_ints = bytes_to_8_bytes_chunks(rlp)
poseidon_rlp = poseidon_hash_many(rlp_ints)
print('rlp', rlp)
print('rlp_hex', rlp_hex)
print('rlp_ints', [hex(x) for x in rlp_ints])
print('poseidon_hashmany(rlp)', hex(poseidon_rlp))