%builtins output range_check bitwise keccak poseidon

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin, KeccakBuiltin
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin

from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import unsigned_div_rem as felt_divmod
from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many

from src.libs.block_header_rlp import fetch_block_headers_rlp, extract_parent_hash_little
from src.libs.utils import pow2alloc127

from src.libs.mmr import compute_height_pre_alloc_pow2 as compute_height

func verify_block_headers_and_hash_them{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    hash_array: felt*,
    rlp_arrays: felt**,
    bytes_len_array: felt*,
}(index: felt, parent_hash: Uint256) {
    alloc_locals;
    // Keccak Hash RLP of block i and verify it matches the parent hash of block i+1
    let (rlp_keccak_hash: Uint256) = keccak(
        inputs=rlp_arrays[index], n_bytes=bytes_len_array[index]
    );
    assert rlp_keccak_hash.low = parent_hash.low;
    assert rlp_keccak_hash.high = parent_hash.high;
    %{ print("\n") %}
    %{ print_u256(ids.rlp_keccak_hash,f"rlp_keccak_hash_{ids.index}") %}
    %{ print_u256(ids.parent_hash,f"prt_keccak_hash_{ids.index}") %}
    // Poseidon Hash RLP of block i and store it in hash_array[i]:
    local n_felts;
    let (n_felts_temp, rem) = felt_divmod(bytes_len_array[index], 8);
    if (rem != 0) {
        assert n_felts = n_felts_temp + 1;
    } else {
        assert n_felts = n_felts_temp;
    }
    let (poseidon_hash) = poseidon_hash_many(n=n_felts, elements=rlp_arrays[index]);
    assert hash_array[index] = poseidon_hash;
    // Get parent hash of block i
    let (block_i_parent_hash: Uint256) = extract_parent_hash_little(rlp_arrays[index]);

    if (index == 0) {
        return ();
    } else {
        return verify_block_headers_and_hash_them(index=index - 1, parent_hash=block_i_parent_hash);
    }
}

// TODO : complete this function
func construct_mmr{
    range_check_ptr, hash_array: felt*, mmr_array: felt*, mmr_array_len: felt, pow2_array: felt*
}(index: felt) {
    alloc_locals;
    // // 2. Compute node
    // let node: felt = poseidon_hash(x=mmr_array_len + 1, y=block_n_hash);
    // // 3. Append node to mmr_array
    // assert mmr_array[mmr_array_len] = node;

    let mmr_array_len = mmr_array_len + 1;
    merge_subtrees_if_applicable(height=0);
    if (index == 0) {
        return ();
    } else {
        return construct_mmr(index=index - 1);
    }
}
// 3              14
//              /    \
//             /      \
//            /        \
//           /          \
// 2        7            14
//        /   \        /    \
// 1     3     6      10    13     18
//      / \   / \    / \   /  \   /  \
// 0   1   2 4   5  8   9 11  12 16  17 19
func merge_subtrees_if_applicable{
    range_check_ptr, mmr_array: felt*, mmr_array_len: felt, pow2_array: felt*
}(height: felt) {
    alloc_locals;
    local next_pos_height_higher_than_current_pos_height: felt;
    let height_next_pos = compute_height(mmr_array_len, pow2_array);

    %{ ids.next_pos_height_higher_than_current_pos_height = 1 if ids.height_next_pos > ids.height else 0 %}
    if (next_pos_height_higher_than_current_pos_height != 0) {
        // This ensures height_next_pos > height.
        // It means than
        assert [range_check_ptr] = height_next_pos - height - 1;
        tempvar range_check_ptr = range_check_ptr + 1;
        // let parent = poseidon_hash(x=0, y=block_n_hash);
        tempvar left_pos = 0;
        return ();
    } else {
        return ();
    }
}
func main{
    output_ptr: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
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
        def print_block_rlp(rlp_arrays, bytes_len_array, index):
            rlp_ptr = memory[rlp_arrays + index]
            n_bytes= memory[bytes_len_array + index]
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

    // -----------------------------------------------------
    // -----------------------------------------------------
    // INITIALIZE VARIABLES
    // -----------------------------------------------------
    tempvar number_of_blocks = from_block_number_high - from_block_number_low + 1;
    let n = number_of_blocks - 1;
    let pow2_array: felt* = pow2alloc127();
    // Ask all the block headers RLPs into Cairo variables from the Prover
    let (rlp_arrays: felt**, bytes_len_array: felt*) = fetch_block_headers_rlp(
        from_block_number_high, from_block_number_low
    );
    // Initialize MMR:
    let (hash_array: felt*) = alloc();  // Poseidon(rlp_arrays)
    let (mmr_array: felt*) = alloc();
    let mmr_array_len = 0;
    %{
        print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, ids.n)
        print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, 0)
        print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, 1)
    %}
    // Get the parent hash of the last block (to be retuned as output):
    let (block_n_parent_hash_little: Uint256) = extract_parent_hash_little(rlp_arrays[n]);
    %{ print_u256(ids.block_n_parent_hash_little,f'parent_hash_{ids.n}') %}
    // -----------------------------------------------------
    // -----------------------------------------------------

    // Validate chain of RLP values for blocks [n-1, n-2, n-1, ..., n-r]:
    with hash_array, rlp_arrays, bytes_len_array {
        verify_block_headers_and_hash_them(index=n - 1, parent_hash=block_n_parent_hash_little);
    }
    // Build MMR by adding all poseidon hashes of RLPs:
    with hash_array, mmr_array, mmr_array_len, pow2_array {
        construct_mmr(index=n - 1);
    }

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
