%builtins output range_check bitwise keccak poseidon

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin

from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import unsigned_div_rem as felt_divmod
from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.dict import dict_write

from src.libs.block_header_rlp import (
    fetch_block_headers_rlp,
    extract_parent_hash_little,
    read_block_headers_rlp,
)
from src.libs.utils import pow2alloc127

from src.libs.mmr import (
    compute_height_pre_alloc_pow2 as compute_height,
    compute_peaks_positions,
    bag_peaks,
    get_root,
    get_full_mmr_peak_value,
)

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

func construct_mmr{
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    hash_array: felt*,
    mmr_array: felt*,
    mmr_array_len: felt,
    mmr_offset: felt,
    previous_peaks_dict: DictAccess*,
    pow2_array: felt*,
}(index: felt) {
    alloc_locals;
    // // 2. Compute node
    %{ print(f"Hash index for node : {ids.mmr_array_len+ids.mmr_offset+1}") %}
    let node: felt = poseidon_hash(x=mmr_array_len + mmr_offset + 1, y=hash_array[index]);
    // // 3. Append node to mmr_array
    assert mmr_array[mmr_array_len] = node;
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
    range_check_ptr,
    poseidon_ptr: PoseidonBuiltin*,
    mmr_array: felt*,
    mmr_array_len: felt,
    mmr_offset: felt,
    previous_peaks_dict: DictAccess*,
    pow2_array: felt*,
}(height: felt) {
    alloc_locals;

    local next_pos_is_parent: felt;
    tempvar next_pos: felt = mmr_array_len + mmr_offset + 1;
    let height_next_pos = compute_height{pow2_array=pow2_array}(next_pos);

    %{ ids.next_pos_is_parent = 1 if ids.height_next_pos > ids.height else 0 %}
    if (next_pos_is_parent != 0) {
        // This ensures height_next_pos > height.
        // It means than the last element in the array is a right children.

        assert [range_check_ptr] = height_next_pos - height - 1;
        tempvar range_check_ptr = range_check_ptr + 1;

        local left_pos = next_pos - pow2_array[height + 1];
        local right_pos = left_pos + pow2_array[height + 1] - 1;

        %{ print(f"Merging {ids.left_pos} + {ids.right_pos} at index {ids.next_pos} and height {ids.height_next_pos} ") %}

        let x = get_full_mmr_peak_value(left_pos);
        let y = get_full_mmr_peak_value(right_pos);
        let (hash) = poseidon_hash(x, y);
        let (hash) = poseidon_hash(x=next_pos, y=hash);
        assert mmr_array[mmr_array_len] = hash;

        let mmr_array_len = mmr_array_len + 1;
        return merge_subtrees_if_applicable(height=height + 1);
    } else {
        // We need to assert heigt_next_pos <= height
        assert [range_check_ptr] = height - height_next_pos;
        tempvar range_check_ptr = range_check_ptr + 1;
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
    local to_block_number_low: felt;
    local mmr_offset: felt;
    local mmr_last_root: felt;
    local block_n_plus_one_parent_hash_little: Uint256;
    %{
        ids.from_block_number_high=program_input['from_block_number_high']
        ids.to_block_number_low=program_input['to_block_number_low']
        ids.mmr_offset=program_input['mmr_last_len'] 
        ids.mmr_last_root=program_input['mmr_last_root']
        ids.block_n_plus_one_parent_hash_little.low = program_input['block_n_plus_one_parent_hash_little_low']
        ids.block_n_plus_one_parent_hash_little.high = program_input['block_n_plus_one_parent_hash_little_high']
    %}
    %{
        def print_u256(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un} = {hex(u)}")

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
        def print_mmr(mmr_array, mmr_array_len):
            print(f"\nMMR :: mmr_array_len={mmr_array_len}")
            mmr_values = [hex(memory[mmr_array + i]) for i in range(mmr_array_len)]
            print(f"mmr_values = {mmr_values}")
    %}

    // -----------------------------------------------------
    // -----------------------------------------------------
    // INITIALIZE VARIABLES
    // -----------------------------------------------------
    tempvar number_of_blocks = from_block_number_high - to_block_number_low + 1;
    let n = number_of_blocks - 1;  // index of last block
    let pow2_array: felt* = pow2alloc127();

    // Ask all the block headers RLPs into Cairo variables from the Prover
    let (rlp_arrays: felt**, bytes_len_array: felt*) = read_block_headers_rlp();

    // Write previous peaks values and compute root of previous MMR:
    let (previous_peaks_values: felt*) = alloc();  // From left to right
    %{ segments.write_arg(ids.previous_peaks_values, program_input['mmr_last_peaks']) %}
    // Compute previous_peaks_positions given the previous MMR size (from left to right):
    let (
        previous_peaks_positions: felt*, previous_peaks_positions_len: felt
    ) = compute_peaks_positions{pow2_array=pow2_array}(mmr_offset);
    let expected_previous_root_tmp = bag_peaks(previous_peaks_values, previous_peaks_positions_len);
    let (expected_previous_root) = poseidon_hash(mmr_offset, expected_previous_root_tmp);
    assert expected_previous_root = mmr_last_root;
    // If previous peaks match the previous root, append the peak values to previous_peaks_dict:
    let (local previous_peaks_dict) = default_dict_new(default_value=0);
    tempvar dict_start = previous_peaks_dict;
    initialize_peaks_dict{dict_end=previous_peaks_dict}(
        previous_peaks_positions_len - 1, previous_peaks_positions, previous_peaks_values
    );

    // Initialize MMR:
    let (hash_array: felt*) = alloc();  // Poseidon(rlp_arrays)
    let (mmr_array: felt*) = alloc();
    let mmr_array_len = 0;
    %{
        print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, ids.n)
        print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, ids.n-1)
        print_block_rlp(ids.rlp_arrays, ids.bytes_len_array, 0)
    %}

    // -----------------------------------------------------
    // -----------------------------------------------------
    // MAIN LOOPS : (1) Validate RLPs and prepare hash array, (2) Build MMR array with hash array

    // (1) Validate chain of RLP values for blocks [n, n-1, n-2, n-1, ..., n-r]:
    with hash_array, rlp_arrays, bytes_len_array {
        verify_block_headers_and_hash_them(
            index=n, parent_hash=block_n_plus_one_parent_hash_little
        );
    }
    %{ print(f"RLP successfully validated!") %}
    // (2) Build MMR by adding all poseidon hashes of RLPs:
    %{ print(f"Building MMR...") %}
    with hash_array, mmr_array, mmr_array_len, pow2_array, mmr_offset, previous_peaks_dict {
        construct_mmr(index=n);
    }
    %{
        print('final') 
        print_mmr(ids.mmr_array,ids.mmr_array_len)
    %}

    // -----------------------------------------------------

    // FINALIZATION

    with mmr_array, mmr_array_len, pow2_array, previous_peaks_dict, mmr_offset {
        let new_mmr_root: felt = get_root();
    }
    %{ print("new root", hex(ids.new_mmr_root)) %}
    %{ print("new size", ids.mmr_array_len + ids.mmr_offset) %}
    default_dict_finalize(dict_start, previous_peaks_dict, 0);

    // Returns "private" input as public output, as well as output of interest.
    // NOTE : block_n_plus_one_parent_hash is critical to be returned and checked against a correct checkpoint on Starknet.
    // Otherwise, the prover could cheat and feed RLP values that are sound together, but not necessearily
    // the exact requested ones from the Ethereum blockchain.

    // Output:
    // 0. MMR last root
    // 1. MMR last size (<=> mmr_offset)
    // 2+3. Block n+1 parent hash (little endian)
    // 4. New MMR root
    // 5. New MMR size

    [ap] = mmr_last_root;
    [ap] = [output_ptr], ap++;

    [ap] = mmr_offset;
    [ap] = [output_ptr + 1], ap++;

    [ap] = block_n_plus_one_parent_hash_little.low;
    [ap] = [output_ptr + 2], ap++;

    [ap] = block_n_plus_one_parent_hash_little.high;
    [ap] = [output_ptr + 3], ap++;

    [ap] = new_mmr_root;
    [ap] = [output_ptr + 4], ap++;

    [ap] = mmr_array_len + mmr_offset;  // New MMR len
    [ap] = [output_ptr + 5], ap++;

    [ap] = output_ptr + 6, ap++;
    let output_ptr = output_ptr + 6;

    return ();
}

// Stores the values of the previous peaks in a dictionary.
// The key is the peak position, and the value is the peak value.
func initialize_peaks_dict{dict_end: DictAccess*}(
    index: felt, peaks_positions: felt*, peaks_values: felt*
) {
    if (index == 0) {
        dict_write{dict_ptr=dict_end}(key=peaks_positions[0], new_value=peaks_values[0]);
        return ();
    } else {
        dict_write{dict_ptr=dict_end}(key=peaks_positions[index], new_value=peaks_values[index]);
        return initialize_peaks_dict(
            index=index - 1, peaks_positions=peaks_positions, peaks_values=peaks_values
        );
    }
}
