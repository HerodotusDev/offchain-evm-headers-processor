%builtins output pedersen range_check bitwise keccak

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.builtin_keccak.keccak import keccak

from src.merkle_mountain.stateless_mmr import (
    append as mmr_append,
    multi_append as mmr_multi_append,
    verify_proof as mmr_verify_proof,
)

from src.single_chunk_processor.block_header_rlp import (
    fetch_block_headers_rlp,
    extract_parent_hash_little,
)

func verify_block_headers_until_index_0{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}(rlp_arrays: felt**, byte_len_array: felt*, index: felt, parent_hash: Uint256) -> (
    index_0_parent_hash: Uint256
) {
    alloc_locals;

    let (rlp_hash: Uint256) = keccak(inputs=rlp_arrays[index], n_bytes=byte_len_array[index]);

    assert rlp_hash.low = parent_hash.low;
    assert rlp_hash.high = parent_hash.high;

    let (block_i_parent_hash: Uint256) = extract_parent_hash_little(rlp_arrays[index]);
    %{ print("\n") %}
    %{ print_u256(ids.rlp_hash,f"rlp_hash_{ids.index}") %}
    %{ print_u256(ids.parent_hash,f"prt_hash_{ids.index}") %}

    if (index == 0) {
        return (block_i_parent_hash,);
    } else {
        return verify_block_headers_until_index_0(
            rlp_arrays=rlp_arrays,
            byte_len_array=byte_len_array,
            index=index - 1,
            parent_hash=block_i_parent_hash,
        );
    }
}
func main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    alloc_locals;
    local from_block_number_high: felt;
    local from_block_number_low: felt;
    local mmr_last_pos: felt;
    local mmr_last_root: felt;
    %{
        ids.from_block_number_high=program_input['from_block_number_high']
        ids.from_block_number_low=program_input['from_block_number_low']
        ids.mmr_last_pos=program_input['mmr_last_pos'] 
        ids.mmr_last_root=program_input['mmr_last_root']
    %}
    %{
        def bin_c(u):
            b=bin(u)
            f = b[0:10] + ' ' + b[10:19] + '...' + b[-16:-8] + ' ' + b[-8:]
            return f
        def bin_64(u):
            b=bin(u)
            little = '0b'+b[2:][::-1]
            f='0b'+' '.join([b[2:][i:i+64] for i in range(0, len(b[2:]), 64)])
            return f
        def bin_8(u):
            b=bin(u)
            little = '0b'+b[2:][::-1]
            f="0b"+' '.join([little[2:][i:i+8] for i in range(0, len(little[2:]), 8)])
            return f
        def print_u256(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un} = {hex(u)}")

        def print_u256_info(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un}_{u.bit_length()}bits = {bin_c(u)}")
            print(f" {un} = {hex(u)}")
            print(f" {un} = {int.to_bytes(u, 32, 'big')}")
        def print_felt_info(u, un, n_bytes):
            print(f" {un}_{u.bit_length()}bits = {bin_8(u)}")
            print(f" {un} = {u}")
            print(f" {un} = {int.to_bytes(u, n_bytes, 'big')}")
        def print_block_rlp(rlp_arrays, byte_len_array, index):
            rlp_ptr = memory[rlp_arrays + index]
            n_bytes= memory[byte_len_array + index]
            n_felts = n_bytes // 8 + 1 if n_bytes % 8 != 0 else n_bytes // 8
            rlp_array = [memory[rlp_ptr + i] for i in range(n_felts)]
            rlp_bytes_array=[int.to_bytes(x, 8, "big") for x in rlp_array]
            rlp_bytes_array_little = [int.to_bytes(x, 8, "little") for x in rlp_array]
            rlp_array_little = [int.from_bytes(x, 'little') for x in rlp_bytes_array]
            x=[x.bit_length() for x in rlp_array]

            print(f"\nBLOCK {index} :: bytes_len={n_bytes} || n_felts={n_felts}")
            print(f"RLP_felt ={rlp_array}")
            print(f"bit_big : {[x.bit_length() for x in rlp_array]}")
            print(f"RLP_bytes_arr_big = {rlp_bytes_array}")
            print(f"RLP_bytes_arr_lil = {rlp_bytes_array_little}")
            print(f"bit_lil : {[x.bit_length() for x in rlp_array_little]}")
    %}

    // Compute the number of blocks to be validated:
    tempvar number_of_blocks = from_block_number_high - from_block_number_low + 1;
    let n = number_of_blocks - 1;
    // Ask all the block headers RLPs into Cairo variables from the Prover
    let (rlp_arrays: felt**, bytes_len_array: felt*) = fetch_block_headers_rlp(
        from_block_number_high, from_block_number_low
    );

    %{ print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, ids.n) %}
    %{ print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, 1) %}
    %{ print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, 2) %}

    // Store the first parent hash into a specific Cairo variable to be returned as ouput of the Cairo program:
    let (block_n_parent_hash_little: Uint256) = extract_parent_hash_little(rlp_arrays[n]);

    %{ print_u256(ids.block_n_parent_hash_little,f'parent_hash_{ids.n}') %}

    // Validate RLP value for block n-1 using the parent hash of block n:
    let (hash_rlp_n_minus_one: Uint256) = keccak(
        inputs=rlp_arrays[n - 1], n_bytes=bytes_len_array[n - 1]
    );
    %{ print_u256(ids.hash_rlp_n_minus_one,f'rlp_hash_{ids.n-1}') %}

    assert block_n_parent_hash_little.low = hash_rlp_n_minus_one.low;
    assert block_n_parent_hash_little.high = hash_rlp_n_minus_one.high;

    // Extract the parent hash of block n-1;
    // Validate chain of RLP values for blocks [n-2, n-1, ..., n-r]:

    let (block_n_minus_one_parent_hash: Uint256) = extract_parent_hash_little(rlp_arrays[n - 1]);
    let (block_0_parent_hash: Uint256) = verify_block_headers_until_index_0(
        rlp_arrays=rlp_arrays,
        byte_len_array=bytes_len_array,
        index=n - 2,
        parent_hash=block_n_minus_one_parent_hash,
    );

    // Returns private input as public output, as well as output of interest.
    // NOTE : block_n_parent_hash is critical to be returned and checked against a correct checkpoint on Starknet.
    // Otherwise, the prover could cheat and feed RLP values that are sound together, but not necessearily
    // the exact requested ones from the Ethereum blockchain.

    [ap] = mmr_last_pos;
    [ap] = [output_ptr], ap++;

    [ap] = mmr_last_root;
    [ap] = [output_ptr + 1], ap++;

    [ap] = block_n_parent_hash_little.low;
    [ap] = [output_ptr + 2], ap++;

    [ap] = block_n_parent_hash_little.high;
    [ap] = [output_ptr + 3], ap++;

    [ap] = output_ptr + 4, ap++;
    let output_ptr = output_ptr + 4;

    return ();
}
