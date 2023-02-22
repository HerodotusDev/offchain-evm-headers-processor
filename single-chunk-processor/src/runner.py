import os
import math
import aiohttp
import asyncio

RPC_BATCH_MAX_SIZE = 50
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
            "params": ['0x' + hex(range_from - (i - 1) * RPC_BATCH_MAX_SIZE - j), False],
            "id": str(j)
        }, range(0, current_batch_size))
    
        # Print the requests as a list
        print(len(list(requests)))


async def main():
    from_block = int(os.environ.get('FROM_BLOCK'))
    till_block = int(os.environ.get('TILL_BLOCK'))
    rpc_url = os.environ.get('RPC_URL')

    print(from_block)
    print(till_block)
    print(rpc_url)

    await fetch_blocks_from_rpc(from_block, till_block, rpc_url)

    # async with aiohttp.ClientSession() as session:
    #     pokemon_url = 'https://pokeapi.co/api/v2/pokemon/151'
    #     async with session.get(pokemon_url) as resp:
    #         pokemon = await resp.json()
    #         print(pokemon['name'])

asyncio.run(main())
