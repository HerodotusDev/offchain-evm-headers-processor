import os
import requests
import json
import time
import math
import json

from tools.py.block_header import build_block_header

RPC_BATCH_MAX_SIZE = 50

def bytes_to_little_endian_ints(input_bytes):
    # Split the input_bytes into 8-byte chunks
    byte_chunks = [input_bytes[i:i + 8] for i in range(0, len(input_bytes), 8)]

    # Convert each chunk to little-endian integers
    little_endian_ints = [int.from_bytes(chunk, byteorder='little') for chunk in byte_chunks]

    return little_endian_ints

def bytes_to_8_bytes_chunks(input_bytes):
    # Split the input_bytes into 8-byte chunks
    byte_chunks = [input_bytes[i:i + 8] for i in range(0, len(input_bytes), 8)]

    # Convert each chunk to little-endian integers
    little_endian_ints = [int.from_bytes(chunk, byteorder='big') for chunk in byte_chunks]

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

def fetch_blocks_from_rpc_no_async(range_from: int, range_till: int, rpc_url: str, delay=0.5): # delay is in seconds
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
