import os
import math
import json
import aiohttp
import asyncio

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
        return results
    

async def main():
    # from_block = int(os.environ.get('FROM_BLOCK'))
    # till_block = int(os.environ.get('TILL_BLOCK'))
    from_block=1
    till_block=-1
    # rpc_url = os.environ.get('https://eth-goerli.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9')
    rpc_url='https://eth-goerli.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9'

    results = await fetch_blocks_from_rpc(from_block, till_block, rpc_url)
    print(results)
    return results

r=asyncio.run(main())
