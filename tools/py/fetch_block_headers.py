import os
import requests
import json
import time
import math
import json
import aiohttp
import asyncio
from hexbytes.main import HexBytes
from rlp import Serializable, encode
from web3.types import BlockData, HexBytes
from rlp.sedes import (
    BigEndianInt,
    big_endian_int,
    Binary,
    binary,
)
from eth_utils import keccak
from web3 import Web3
from typing import Union
address = Binary.fixed_length(20, allow_empty=True)
hash32 = Binary.fixed_length(32)
int256 = BigEndianInt(256)
trie_root = Binary.fixed_length(32, allow_empty=True)

class BlockHeader(Serializable):
    fields = (
        ('parentHash', hash32),
        ('unclesHash', hash32),
        ('coinbase', address),
        ('stateRoot', trie_root),
        ('transactionsRoot', trie_root),
        ('receiptsRoot', trie_root),
        ('logsBloom', int256),
        ('difficulty', big_endian_int),
        ('number', big_endian_int),
        ('gasLimit', big_endian_int),
        ('gasUsed', big_endian_int),
        ('timestamp', big_endian_int),
        ('extraData', binary),
        ('mixHash', binary),
        ('nonce', Binary(8, allow_empty=True)),
    )

    def hash(self) -> HexBytes:
        _rlp = encode(self)
        return Web3.keccak(_rlp)
    
    def raw_rlp(self) -> bytes:
        return encode(self)
    
class BlockHeaderEIP1559(Serializable):
    fields = (
        ('parentHash', hash32),
        ('unclesHash', hash32),
        ('coinbase', address),
        ('stateRoot', trie_root),
        ('transactionsRoot', trie_root),
        ('receiptsRoot', trie_root),
        ('logsBloom', int256),
        ('difficulty', big_endian_int),
        ('number', big_endian_int),
        ('gasLimit', big_endian_int),
        ('gasUsed', big_endian_int),
        ('timestamp', big_endian_int),
        ('extraData', binary),
        ('mixHash', binary),
        ('nonce', Binary(8, allow_empty=True)),
        ('baseFeePerGas', big_endian_int), 

    )
    def hash(self) -> HexBytes:
        _rlp = encode(self)
        return Web3.keccak(_rlp)
    
    def raw_rlp(self) -> bytes:
        return encode(self)

class BlockHeaderShangai(Serializable):
    fields = (
        ('parentHash', hash32),
        ('unclesHash', hash32),
        ('coinbase', address),
        ('stateRoot', trie_root),
        ('transactionsRoot', trie_root),
        ('receiptsRoot', trie_root),
        ('logsBloom', int256),
        ('difficulty', big_endian_int),
        ('number', big_endian_int),
        ('gasLimit', big_endian_int),
        ('gasUsed', big_endian_int),
        ('timestamp', big_endian_int),
        ('extraData', binary),
        ('mixHash', binary),
        ('nonce', Binary(8, allow_empty=True)),
        ('baseFeePerGas', big_endian_int), 
        ('withdrawalsRoot', trie_root)

    )
    def hash(self) -> HexBytes:
        _rlp = encode(self)
        return Web3.keccak(_rlp)
    
    def raw_rlp(self) -> bytes:
        return encode(self)
    
def hash(self) -> HexBytes:
    _rlp = encode(self)
    return Web3.keccak(_rlp)

def raw_rlp(self) -> bytes:
    return encode(self)
    
def build_block_header(block: BlockData) -> Union[BlockHeader, BlockHeaderEIP1559]:

    if 'withdrawalsRoot' in block.keys():
        header = BlockHeaderShangai(
        HexBytes(block["parentHash"]),
        HexBytes(block["sha3Uncles"]),
        bytearray.fromhex(block['miner'][2:]),
        HexBytes(block["stateRoot"]),
        HexBytes(block['transactionsRoot']),
        HexBytes(block["receiptsRoot"]),
        int.from_bytes(HexBytes(block["logsBloom"]), 'big'),
        int(block["difficulty"],16),
        int(block["number"], 16),
        int(block["gasLimit"],16),
        int(block["gasUsed"],16),
        int(block["timestamp"],16),
        HexBytes(block["extraData"]),
        HexBytes(block["mixHash"]),
        HexBytes(block["nonce"]),
        int(block["baseFeePerGas"],16), 
        HexBytes(block["withdrawalsRoot"])
    )
    elif 'baseFeePerGas' in block.keys():
        header = BlockHeaderEIP1559(
        HexBytes(block["parentHash"]),
        HexBytes(block["sha3Uncles"]),
        bytearray.fromhex(block['miner'][2:]),
        HexBytes(block["stateRoot"]),
        HexBytes(block['transactionsRoot']),
        HexBytes(block["receiptsRoot"]),
        int.from_bytes(HexBytes(block["logsBloom"]), 'big'),
        int(block["difficulty"],16),
        int(block["number"], 16),
        int(block["gasLimit"],16),
        int(block["gasUsed"],16),
        int(block["timestamp"],16),
        HexBytes(block["extraData"]),
        HexBytes(block["mixHash"]),
        HexBytes(block["nonce"]),
        int(block["baseFeePerGas"],16), 
    )
        
    else:
        header = BlockHeader(
        HexBytes(block["parentHash"]),
        HexBytes(block["sha3Uncles"]),
        bytearray.fromhex(block['miner'][2:]),
        HexBytes(block["stateRoot"]),
        HexBytes(block['transactionsRoot']),
        HexBytes(block["receiptsRoot"]),
        int.from_bytes(HexBytes(block["logsBloom"]), 'big'),
        int(block["difficulty"],16),
        int(block["number"], 16),
        int(block["gasLimit"],16),
        int(block["gasUsed"],16),
        int(block["timestamp"],16),
        HexBytes(block["extraData"]),
        HexBytes(block["mixHash"]),
        HexBytes(block["nonce"]),
    )
        

    return header


RPC_BATCH_MAX_SIZE = 50

async def send_rpc_request(session: aiohttp.ClientSession, url, rpc_request):
    async with session.post(url=url, data=json.dumps(rpc_request)) as response:
        return await response.json()

async def fetch_blocks_from_rpc(range_from: int, range_till: int, rpc_url: str):
    assert range_from > range_till, "Invalid range"
    number_of_blocks = range_from - range_till
    rpc_batches_amount = math.ceil(number_of_blocks / RPC_BATCH_MAX_SIZE)
    last_batch_size = number_of_blocks % RPC_BATCH_MAX_SIZE

    for i in range(1, rpc_batches_amount + 1):
        current_batch_size = last_batch_size if (i == rpc_batches_amount and last_batch_size) else RPC_BATCH_MAX_SIZE
        requests = map(lambda j: {
            "jsonrpc": '2.0',
            "method": 'eth_getBlockByNumber',
            "params": [hex(range_from - (i - 1) * RPC_BATCH_MAX_SIZE - j), False],
            "id": str(j)
        }, range(0, current_batch_size))
    
    async with aiohttp.ClientSession() as session:
        tasks = [asyncio.ensure_future(send_rpc_request(session, rpc_url, request)) for request in requests]
        results = await asyncio.gather(*tasks)
        return list(reversed(results))

async def main(from_block:int=2, till_block:int=0):
    from_block=from_block
    till_block=till_block - 1

    rpc_url='https://eth-mainnet.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9'

    results = await fetch_blocks_from_rpc(from_block, till_block, rpc_url)
    return results

def bytes_to_little_endian_ints(input_bytes):
    # Split the input_bytes into 8-byte chunks
    byte_chunks = [input_bytes[i:i + 8] for i in range(0, len(input_bytes), 8)]

    # Convert each chunk to little-endian integers
    little_endian_ints = [int.from_bytes(chunk, byteorder='little') for chunk in byte_chunks]

    return little_endian_ints

def reverse_endian(input_int, byte_length):
    # Convert the input integer to bytes with the given byte length
    byte_representation = input_int.to_bytes(byte_length, byteorder='little')
    # Convert the bytes back to an integer with reversed endianness
    reversed_endian_int = int.from_bytes(byte_representation, byteorder='big')

    return reversed_endian_int

def split_128(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def rpc_request(url, rpc_request):
    response = requests.post(url=url, data=json.dumps(rpc_request))
    return response.json()

def fetch_blocks_from_rpc_no_async(range_from: int, range_till: int, rpc_url: str, delay=0.1): # delay is in seconds
    assert range_from > range_till, "Invalid range"
    number_of_blocks = range_from - range_till
    rpc_batches_amount = math.ceil(number_of_blocks / RPC_BATCH_MAX_SIZE)
    last_batch_size = number_of_blocks % RPC_BATCH_MAX_SIZE

    all_results = []

    for i in range(1, rpc_batches_amount + 1):
        current_batch_size = last_batch_size if (i == rpc_batches_amount and last_batch_size) else RPC_BATCH_MAX_SIZE
        requests = list(map(lambda j: {
            "jsonrpc": '2.0',
            "method": 'eth_getBlockByNumber',
            "params": [hex(range_from - (i - 1) * RPC_BATCH_MAX_SIZE - j), False],
            "id": str(j)
        }, range(0, current_batch_size)))

        # Send all requests in the current batch in a single HTTP request
        results = rpc_request(rpc_url, requests)

        for result in results:
            raw_rlp = build_block_header(result['result'])
            all_results.append(raw_rlp)


        time.sleep(delay)  # Add delay
    time.sleep(delay)  # Add delay
    return all_results
