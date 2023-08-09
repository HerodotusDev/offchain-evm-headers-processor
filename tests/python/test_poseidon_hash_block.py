from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async, bytes_to_8_bytes_chunks
from tools.py.poseidon.poseidon_hash import poseidon_hash_many, poseidon_hash
from dotenv import load_dotenv
import os


GOERLI = 'goerli'
MAINNET = 'mainnet'

NETWORK = GOERLI

RPC_URL = os.getenv("RPC_URL_GOERLI") if NETWORK == GOERLI else os.getenv("RPC_URL_MAINNET")

block_n = 9433302

def get_block_header(number:int):
    blocks = fetch_blocks_from_rpc_no_async(number+1, number-1, RPC_URL)
    block = blocks[1]
    assert block.number == number, f"Block number mismatch {block.number} != {number}"
    return block


def get_block_header_raw(number:int):
    block = get_block_header(number)
    print(block)
    return block.raw_rlp()

def get_poseidon_hash_block(block_header_raw:bytes):
    chunks = bytes_to_8_bytes_chunks(block_header_raw)
    print(chunks, len(chunks))
    return poseidon_hash_many(chunks)

test= get_block_header_raw(block_n)
test_poseidon = get_poseidon_hash_block(test)
print(hex(test_poseidon))