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
    BlockHeaderRLP,
    fetch_block_headers_rlp,
    extract_parent_hash_little,
)

// struct BlockHeaderRLP {
//     block_header_rlp_bytes_len: felt,
//     block_header_rlp_len: felt,
//     rlp: felt*,
// }

func main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    alloc_locals;
    local mmr_last_pos: felt;
    local mmr_last_root: felt;
    %{
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
        def print_u_256_info(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un}_{u.bit_length()}bits = {bin_c(u)}")
            print(f" {un} = {hex(u)}")
            print(f" {un} = {int.to_bytes(u, 32, 'big')}")
        def print_felt_info(u, un, n_bytes):
            print(f" {un}_{u.bit_length()}bits = {bin_8(u)}")
            print(f" {un} = {u}")
            print(f" {un} = {int.to_bytes(u, n_bytes, 'big')}")
        def print_block_rlp(brlp_array, index):
            (bytes_len, n_felts, rlp_ptr) = [memory[brlp_array._reference_value + 3 * index + k] for k in range(3)]
            rlp_array = [memory[rlp_ptr + i] for i in range(n_felts)]
            rlp_bytes_array=[int.to_bytes(x, 8, "big") for x in rlp_array]
            rlp_bytes_array_little = [int.to_bytes(x, 8, "little") for x in rlp_array]
            rlp_array_little = [int.from_bytes(x, 'little') for x in rlp_bytes_array]
            x=[x.bit_length() for x in rlp_array]
            assert len(rlp_bytes_array) == len(rlp_array)

            print(f"\nBLOCK n-{index} :: bytes_len={bytes_len} || n_felts={n_felts}")
            print(f"RLP_felt ={rlp_array}")
            print(f"bit_big : {[x.bit_length() for x in rlp_array]}")
            print(f"RLP_bytes_arr_big = {rlp_bytes_array}")
            print(f"RLP_bytes_arr_lil = {rlp_bytes_array_little}")
            print(f"bit_lil : {[x.bit_length() for x in rlp_array_little]}")
    %}
    // Load all BlockHeaderRLP structs from API call into a BlockHeaderRLP array:
    let (
        local block_header_rlp_array: BlockHeaderRLP*, block_header_rlp_len: felt
    ) = fetch_block_headers_rlp(from_block_number_high=2, to_block_number_low=0);

    %{ print_block_rlp(ids.block_header_rlp_array, 0) %}
    %{ print_block_rlp(ids.block_header_rlp_array, 1) %}
    %{ print_block_rlp(ids.block_header_rlp_array, 2) %}

    // Store the first parent hash into a specific Cairo variable to be returned as ouput of the Cairo program:
    let (block_n_parent_hash_little: Uint256) = extract_parent_hash_little(
        block_header_rlp_array[0].rlp
    );

    %{ print_u_256_info(ids.block_n_parent_hash_little,'parent_hash_n') %}

    // Validate RLP value for block n-1 using the parent hash of block n:

    let (hash_rlp_n_minus_one: Uint256) = keccak(
        inputs=block_header_rlp_array[1].rlp, n_bytes=block_header_rlp_array[1].rlp_bytes_len
    );
    %{ print_u_256_info(ids.hash_rlp_n_minus_one,'hash_rlp n-1') %}

    assert block_n_parent_hash_little.low = hash_rlp_n_minus_one.low;
    assert block_n_parent_hash_little.high = hash_rlp_n_minus_one.high;

    // Validate chain of RLP values for block [n-2; n-r]:

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
