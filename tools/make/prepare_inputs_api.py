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


def prepare_chunk_input(last_peaks:dict, last_mmr_size:int, last_mmr_root:dict, from_block_number_high:int, to_block_number_low) -> json:
    chunk_input={}
    chunk_output={}
    blocks = fetch_blocks_from_rpc_no_async(from_block_number_high+1, to_block_number_low-1, ALCHEMY_RPC)
    blocks.reverse()
    block_n_plus_one = blocks[-1]
    block_n_minus_r_plus_one = blocks[0]
    block_n_plus_one_parent_hash_little = split_128(int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), 'little'))
    block_n_plus_one_parent_hash_big = split_128(int.from_bytes(bytes.fromhex(block_n_plus_one.parentHash.hex()[2:]), 'big'))
    block_n_minus_r_plus_one_parent_hash_big = split_128(int.from_bytes(bytes.fromhex(block_n_minus_r_plus_one.parentHash.hex()[2:]), 'big'))


    blocks = blocks[:-1]
    # print([x.number for x in blocks])
    blocks = [block.raw_rlp() for block in blocks]
    blocks_len = [len(block) for block in blocks]
    blocks = [bytes_to_little_endian_ints(block) for block in blocks]

    chunk_input['mmr_last_root_poseidon'] = last_mmr_root['poseidon']
    chunk_input['mmr_last_root_keccak_low'], chunk_input['mmr_last_root_keccak_high']= split_128(last_mmr_root['keccak'])
    chunk_input['mmr_last_len'] = last_mmr_size
    chunk_input['poseidon_mmr_last_peaks'] = last_peaks['poseidon']
    chunk_input['keccak_mmr_last_peaks'] = [split_128(x) for x in last_peaks['keccak']]
    chunk_input['from_block_number_high'] = from_block_number_high
    chunk_input['to_block_number_low'] = to_block_number_low
    chunk_input['block_n_plus_one_parent_hash_little_low'] = block_n_plus_one_parent_hash_little[0]
    chunk_input['block_n_plus_one_parent_hash_little_high'] = block_n_plus_one_parent_hash_little[1]
    chunk_input["block_headers_array"] = blocks
    chunk_input["bytes_len_array"] = blocks_len 

    chunk_output['block_n_plus_one_parent_hash_low'], chunk_output['block_n_plus_one_parent_hash_high']=block_n_plus_one_parent_hash_big
    chunk_output['block_n_minus_r_plus_one_parent_hash_low'], chunk_output['block_n_minus_r_plus_one_parent_hash_high']=block_n_minus_r_plus_one_parent_hash_big
    chunk_output['mmr_last_root_poseidon'] = last_mmr_root['poseidon']
    chunk_output['mmr_last_root_keccak_low'], chunk_output['mmr_last_root_keccak_high'] = split_128(last_mmr_root['keccak'])
    chunk_output['mmr_last_len'] = last_mmr_size


                 
    return chunk_input, chunk_output

def chunk_process_api(last_peaks:dict, last_mmr_size:int, from_block_number_high:int, to_block_number_low) -> json:
    data={}

    params = {"chunk_size":50, 
          "poseidon_last_elements_count":last_mmr_size,
          "poseidon_last_peaks":[hex(x) for x in last_peaks['poseidon']], 
          "keccak_last_elements_count":last_mmr_size,
          "keccak_last_peaks":[hex(x) for x in last_peaks['keccak']],
          "start_block": to_block_number_low, 
          "end_block": from_block_number_high, 
          'rpc_url':RPC_BACKEND_URL, 
          "max_retries_per_request":3, 
          "append_in_reverse":True}


    test = rpc_request('http://3.10.105.11:8000/precompute-mmr',  params)
    data['mmr_last_root_poseidon'] = int(test['poseidon_mmr']['root_hash'],16)
    data['mmr_last_root_keccak'] = int(test['keccak_mmr']['root_hash'],16)
    data['mmr_last_len'] = test['poseidon_mmr']['tree_size']
    peaks_hashes_poseidon = [int(x, 16) for x in test['poseidon_mmr']['peaks']]
    peaks_hashes_keccak = [int(x, 16) for x in test['keccak_mmr']['peaks']]
    data['poseidon_mmr_last_peaks'] = peaks_hashes_poseidon
    data['keccak_mmr_last_peaks'] = peaks_hashes_keccak

    return data

def prepare_full_chain_inputs(from_block_number_high, batch_size=50):
    PATH = "src/single_chunk_processor/data/"
    mkdir_if_not_exists(PATH)
    from_block_number_high = from_block_number_high
    to_block_number_low = from_block_number_high - batch_size + 1

    # 'brave new world' in Cairo, keccak(hex(511165008604479100545509010942618724))
    last_peaks = {'poseidon':[511165008604479100545509010942618724], 'keccak':[93435818137180840214006077901347441834554899062844693462640230920378475721064]} 
    last_mmr_size = 1
    last_mmr_root = {'poseidon':last_peaks['poseidon'][0], 'keccak':last_peaks['keccak'][0]}

    print(f"Preparing input for blocks from {from_block_number_high} to {to_block_number_low}")

    chunk_input, chunk_output  = prepare_chunk_input(last_peaks, last_mmr_size, last_mmr_root, from_block_number_high, to_block_number_low)
    with open(f"{PATH}blocks_{from_block_number_high}_{to_block_number_low}_input.json", 'w') as f:
        json.dump(chunk_input, f, indent=4)

    previous_block_high = from_block_number_high
    previous_block_low = to_block_number_low
    from_block_number_high = to_block_number_low - 1

    to_block_number_low = from_block_number_high - batch_size + 1 if from_block_number_high - batch_size + 1 >= 0 else 0


    while to_block_number_low >= 0:
        print("start while", to_block_number_low)
        print(f"Preparing input for blocks from {from_block_number_high} to {to_block_number_low}")
        previous_chunk_data = chunk_process_api(last_peaks, last_mmr_size, previous_block_high, previous_block_low)
        last_peaks = {'poseidon':previous_chunk_data['poseidon_mmr_last_peaks'],
                        'keccak':previous_chunk_data['keccak_mmr_last_peaks']}
        
        last_mmr_size = previous_chunk_data['mmr_last_len']
        last_mmr_root = {'poseidon':previous_chunk_data['mmr_last_root_poseidon'],
                        'keccak':previous_chunk_data['mmr_last_root_keccak']}
        

        chunk_output['new_mmr_root_poseidon'] = last_mmr_root['poseidon']
        chunk_output['new_mmr_root_keccak_low'], chunk_output['new_mmr_root_keccak_high'] = split_128(last_mmr_root['keccak'])
        chunk_output['new_mmr_len'] = last_mmr_size

        print(f"Writing output for blocks from {previous_block_high} to {previous_block_low}")
        with open(f"{PATH}blocks_{previous_block_high}_{previous_block_low}_output.json", 'w') as f:
            json.dump(chunk_output, f, indent=4)

        
        time.sleep(0.5)
        chunk_input, chunk_output = prepare_chunk_input(last_peaks, last_mmr_size, last_mmr_root, from_block_number_high, to_block_number_low)
        with open(f"{PATH}blocks_{from_block_number_high}_{to_block_number_low}_input.json", 'w') as f:
            json.dump(chunk_input, f, indent=4)
        
        if to_block_number_low==0:
            previous_chunk_data = chunk_process_api(last_peaks, last_mmr_size, from_block_number_high, to_block_number_low)
            last_mmr_size = previous_chunk_data['mmr_last_len']
            last_mmr_root = {'poseidon':previous_chunk_data['mmr_last_root_poseidon'],
                        'keccak':previous_chunk_data['mmr_last_root_keccak']}
            

            chunk_output['new_mmr_root_poseidon'] = last_mmr_root['poseidon']
            chunk_output['new_mmr_root_keccak_low'], chunk_output['new_mmr_root_keccak_high'] = split_128(last_mmr_root['keccak'])
            chunk_output['new_mmr_len'] = last_mmr_size
            
            print(f"Writing output for blocks from {from_block_number_high} to {to_block_number_low}")
            with open(f"{PATH}blocks_{from_block_number_high}_{to_block_number_low}_output.json", 'w') as f:
                json.dump(chunk_output, f, indent=4)
            break

        previous_block_high = from_block_number_high
        previous_block_low = to_block_number_low
        from_block_number_high = to_block_number_low - 1

        to_block_number_low = from_block_number_high - batch_size + 1 if from_block_number_high - batch_size + 1 >= 0 else 0    


        

prepare_full_chain_inputs(100,20)

# chunk_process_api(last_peaks=[511165008604479100545509010942618724], 
#                   last_mmr_size=1, 
#                   from_block_number_high=100, 
#                   to_block_number_low=80)


