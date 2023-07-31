%builtins output range_check bitwise keccak poseidon

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin

from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from starkware.cairo.common.math import unsigned_div_rem as felt_divmod
from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_uint256
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash, poseidon_hash_many
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.dict import dict_write
from starkware.cairo.common.registers import get_fp_and_pc

from src.libs.block_header import (
    extract_parent_hash_little,
    read_block_headers,
    reverse_block_header_chunks,
)
from src.libs.utils import pow2alloc127

from src.libs.mmr import (
    compute_height_pre_alloc_pow2 as compute_height,
    compute_peaks_positions,
    bag_peaks,
    get_roots,
    get_full_mmr_peak_values,
)

func verify_block_headers_and_hash_them{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    poseidon_hash_array: felt*,
    keccak_hash_array: Uint256*,
    block_headers_array: felt**,
    bytes_len_array: felt*,
}(index: felt, parent_hash: Uint256) -> Uint256 {
    alloc_locals;
    // Keccak Hash RLP of block i and verify it matches the parent hash of block i+1
    let (rlp_keccak_hash: Uint256) = keccak(
        inputs=block_headers_array[index], n_bytes=bytes_len_array[index]
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

    let reversed_block_header: felt* = reverse_block_header_chunks(
        n_felts, block_headers_array[index], index
    );
    let (block_header_hash_big) = uint256_reverse_endian(rlp_keccak_hash);
    let (poseidon_hash) = poseidon_hash_many(n=n_felts, elements=reversed_block_header);
    assert poseidon_hash_array[index] = poseidon_hash;
    assert keccak_hash_array[index].low = block_header_hash_big.low;
    assert keccak_hash_array[index].high = block_header_hash_big.high;
    // Get parent hash of block i
    let (block_i_parent_hash: Uint256) = extract_parent_hash_little(block_headers_array[index]);

    if (index == 0) {
        return block_i_parent_hash;
    } else {
        return verify_block_headers_and_hash_them(index=index - 1, parent_hash=block_i_parent_hash);
    }
}

func construct_mmr{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_hash_array: felt*,
    mmr_array_poseidon: felt*,
    keccak_hash_array: Uint256*,
    mmr_array_keccak: Uint256*,
    mmr_array_len: felt,
    mmr_offset: felt,
    previous_peaks_dict_poseidon: DictAccess*,
    previous_peaks_dict_keccak: DictAccess*,
    pow2_array: felt*,
}(index: felt) {
    alloc_locals;
    // // 2. Compute node
    // %{ print(f"Hash index for node : {ids.mmr_array_len+ids.mmr_offset+1}") %}

    // let node_poseidon: felt = poseidon_hash(
    //     x=mmr_array_len + mmr_offset + 1, y=poseidon_hash_array[index]
    // );

    // // 3. Append nodes to mmr_array

    assert mmr_array_poseidon[mmr_array_len] = poseidon_hash_array[index];
    assert mmr_array_keccak[mmr_array_len].low = keccak_hash_array[index].low;
    assert mmr_array_keccak[mmr_array_len].high = keccak_hash_array[index].high;

    let mmr_array_len = mmr_array_len + 1;
    merge_subtrees_if_applicable(height=0);
    if (index == 0) {
        return ();
    } else {
        return construct_mmr(index=index - 1);
    }
}
// 3              15
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
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    mmr_array_poseidon: felt*,
    mmr_array_keccak: Uint256*,
    mmr_array_len: felt,
    mmr_offset: felt,
    previous_peaks_dict_poseidon: DictAccess*,
    previous_peaks_dict_keccak: DictAccess*,
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

        let (x_poseidon: felt, x_keccak: Uint256) = get_full_mmr_peak_values(left_pos);
        let (y_poseidon: felt, y_keccak: Uint256) = get_full_mmr_peak_values(right_pos);
        let (hash_poseidon) = poseidon_hash(x_poseidon, y_poseidon);
        let (keccak_input: felt*) = alloc();
        let inputs_start = keccak_input;
        keccak_add_uint256{inputs=keccak_input}(num=x_keccak, bigend=1);
        keccak_add_uint256{inputs=keccak_input}(num=y_keccak, bigend=1);
        let (res_keccak_little: Uint256) = keccak(inputs=inputs_start, n_bytes=2 * 32);
        let (res_keccak) = uint256_reverse_endian(res_keccak_little);

        assert mmr_array_poseidon[mmr_array_len] = hash_poseidon;
        assert mmr_array_keccak[mmr_array_len].low = res_keccak.low;
        assert mmr_array_keccak[mmr_array_len].high = res_keccak.high;

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
    local mmr_last_root_poseidon: felt;
    local mmr_last_root_keccak: Uint256;
    local block_n_plus_one_parent_hash_little: Uint256;
    %{
        ids.from_block_number_high=program_input['from_block_number_high']
        ids.to_block_number_low=program_input['to_block_number_low']
        ids.mmr_offset=program_input['mmr_last_len'] 
        ids.mmr_last_root_poseidon=program_input['mmr_last_root_poseidon']
        ids.mmr_last_root_keccak.low=program_input['mmr_last_root_keccak_low']
        ids.mmr_last_root_keccak.high=program_input['mmr_last_root_keccak_high']
        ids.block_n_plus_one_parent_hash_little.low = program_input['block_n_plus_one_parent_hash_little_low']
        ids.block_n_plus_one_parent_hash_little.high = program_input['block_n_plus_one_parent_hash_little_high']
    %}
    %{
        def print_u256(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un} = {hex(u)}")
        def write_uint256_array(ptr, array):
            counter = 0
            for uint in array:
                memory[ptr._reference_value+counter] = uint[0]
                memory[ptr._reference_value+counter+1] = uint[1]
                counter += 2
        def print_block_header(block_headers_array, bytes_len_array, index):
            rlp_ptr = memory[block_headers_array + index]
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
    let (block_headers_array: felt**, bytes_len_array: felt*) = read_block_headers();

    // Write previous peaks values and compute root of previous MMR:
    let (previous_peaks_values_poseidon: felt*) = alloc();  // From left to right
    let (previous_peaks_values_keccak: Uint256*) = alloc();  // From left to right

    %{
        segments.write_arg(ids.previous_peaks_values_poseidon, program_input['poseidon_mmr_last_peaks']) 
        write_uint256_array(ids.previous_peaks_values_keccak, program_input['keccak_mmr_last_peaks'])
    %}

    // Compute previous_peaks_positions given the previous MMR size (from left to right):
    let (
        previous_peaks_positions: felt*, previous_peaks_positions_len: felt
    ) = compute_peaks_positions{pow2_array=pow2_array}(mmr_offset);
    let (expected_previous_root_poseidon, expected_previous_root_keccak) = bag_peaks(
        previous_peaks_values_poseidon, previous_peaks_values_keccak, previous_peaks_positions_len
    );

    assert expected_previous_root_poseidon = mmr_last_root_poseidon;
    assert expected_previous_root_keccak.low = mmr_last_root_keccak.low;
    assert expected_previous_root_keccak.high = mmr_last_root_keccak.high;

    // If previous peaks match the previous root, append the peak values to previous_peaks_dict:
    let (local previous_peaks_dict_poseidon) = default_dict_new(default_value=0);
    let (local previous_peaks_dict_keccak) = default_dict_new(default_value=0);
    tempvar dict_start_poseidon = previous_peaks_dict_poseidon;
    tempvar dict_start_keccak = previous_peaks_dict_keccak;
    initialize_peaks_dicts{
        dict_end_poseidon=previous_peaks_dict_poseidon, dict_end_keccak=previous_peaks_dict_keccak
    }(
        previous_peaks_positions_len - 1,
        previous_peaks_positions,
        previous_peaks_values_poseidon,
        previous_peaks_values_keccak,
    );

    // Initialize Poseidon MMR:
    let (poseidon_hash_array: felt*) = alloc();  // Poseidon(block_header)
    let (mmr_array_poseidon: felt*) = alloc();
    // Initialize Keccak MMR :
    let (keccak_hash_array: Uint256*) = alloc();
    let (mmr_array_keccak: Uint256*) = alloc();
    // Common variable for both MMR :
    let mmr_array_len = 0;
    %{
        #print_block_header(ids.block_headers_array, ids.bytes_len_array, ids.n)
        # print_block_header(ids.block_headers_array, ids.bytes_len_array, ids.n-1)
        #print_block_header(ids.block_headers_array, ids.bytes_len_array, 0)
    %}

    // -----------------------------------------------------
    // -----------------------------------------------------
    // MAIN LOOPS : (1) Validate RLPs and prepare hash arrays, (2) Build MMR arrays with hash array

    // (1) Validate chain of block headers for blocks [n, n-1, n-2, n-1, ..., n-r]:
    with poseidon_hash_array, keccak_hash_array, block_headers_array, bytes_len_array {
        let block_n_minus_r_plus_one_parent_hash_little: Uint256 = verify_block_headers_and_hash_them(
            index=n, parent_hash=block_n_plus_one_parent_hash_little);
    }
    %{ print(f"RLP successfully validated!") %}
    // (2) Build Poseidon/Keccak MMR by appending all poseidon/keccak hashes of block headers stored in poseidon_hash_array/keccak_hash_array:
    %{ print(f"Building MMR...") %}
    with poseidon_hash_array, keccak_hash_array, mmr_array_poseidon, mmr_array_keccak, mmr_array_len, pow2_array, mmr_offset, previous_peaks_dict_poseidon, previous_peaks_dict_keccak {
        construct_mmr(index=n);
    }
    %{
        print('Final Poseidon MMR') 
        print_mmr(ids.mmr_array_poseidon,ids.mmr_array_len)
    %}

    // -----------------------------------------------------

    // FINALIZATION

    with mmr_array_poseidon, mmr_array_keccak, mmr_array_len, pow2_array, previous_peaks_dict_poseidon, previous_peaks_dict_keccak, mmr_offset {
        let (new_mmr_root_poseidon: felt, new_mmr_root_keccak: Uint256) = get_roots();
    }

    %{ print("new root poseidon", ids.new_mmr_root_poseidon) %}
    %{ print_u256(ids.new_mmr_root_keccak, "new root keccak") %}
    %{ print("new size", ids.mmr_array_len + ids.mmr_offset) %}

    default_dict_finalize(dict_start_poseidon, previous_peaks_dict_poseidon, 0);
    default_dict_finalize(dict_start_keccak, previous_peaks_dict_keccak, 0);

    let (block_n_plus_one_parent_hash) = uint256_reverse_endian(
        block_n_plus_one_parent_hash_little
    );
    let (block_n_minus_r_plus_one_parent_hash) = uint256_reverse_endian(
        block_n_minus_r_plus_one_parent_hash_little
    );

    // Returns "private" input as public output, as well as output of interest.

    // Output :
    // 0+1 : block_n_plus_one_parent_hash
    // 2+3 : block_n_minus_r_plus_one_parent_hash
    // 4 : MMR last root poseidon
    // 5 : New MMR root poseidon
    // 6+7 : MMR last root keccak
    // 8+9 : New MMR root keccak
    // 10 : MMR last size (<=> mmr_offset)
    // 11 : New MMR size (<=> mmr_array_len + mmr_offset)

    [ap] = block_n_plus_one_parent_hash.low;
    [ap] = [output_ptr], ap++;

    [ap] = block_n_plus_one_parent_hash.high;
    [ap] = [output_ptr + 1], ap++;

    [ap] = block_n_minus_r_plus_one_parent_hash.low;
    [ap] = [output_ptr + 2], ap++;

    [ap] = block_n_minus_r_plus_one_parent_hash.high;
    [ap] = [output_ptr + 3], ap++;

    [ap] = mmr_last_root_poseidon;
    [ap] = [output_ptr + 4], ap++;

    [ap] = new_mmr_root_poseidon;
    [ap] = [output_ptr + 5], ap++;

    [ap] = mmr_last_root_keccak.low;
    [ap] = [output_ptr + 6], ap++;

    [ap] = mmr_last_root_keccak.high;
    [ap] = [output_ptr + 7], ap++;

    [ap] = new_mmr_root_keccak.low;
    [ap] = [output_ptr + 8], ap++;

    [ap] = new_mmr_root_keccak.high;
    [ap] = [output_ptr + 9], ap++;

    [ap] = mmr_offset;
    [ap] = [output_ptr + 10], ap++;

    [ap] = mmr_array_len + mmr_offset;
    [ap] = [output_ptr + 11], ap++;

    [ap] = output_ptr + 12, ap++;
    let output_ptr = output_ptr + 12;

    return ();
}

// Stores the values of the previous peaks in a dictionary.
// The key is the peak position, and the value is the peak value.
func initialize_peaks_dicts{dict_end_poseidon: DictAccess*, dict_end_keccak: DictAccess*}(
    index: felt, peaks_positions: felt*, peaks_values_poseidon: felt*, peaks_values_keccak: Uint256*
) {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();
    local keccak_peak_value: Uint256;
    assert keccak_peak_value.low = peaks_values_keccak[index].low;
    assert keccak_peak_value.high = peaks_values_keccak[index].high;

    if (index == 0) {
        dict_write{dict_ptr=dict_end_poseidon}(
            key=peaks_positions[0], new_value=peaks_values_poseidon[0]
        );
        dict_write{dict_ptr=dict_end_keccak}(
            key=peaks_positions[0], new_value=cast(&keccak_peak_value, felt)
        );

        return ();
    } else {
        dict_write{dict_ptr=dict_end_poseidon}(
            key=peaks_positions[index], new_value=peaks_values_poseidon[index]
        );
        dict_write{dict_ptr=dict_end_keccak}(
            key=peaks_positions[index], new_value=cast(&keccak_peak_value, felt)
        );
        return initialize_peaks_dicts(
            index=index - 1,
            peaks_positions=peaks_positions,
            peaks_values_poseidon=peaks_values_poseidon,
            peaks_values_keccak=peaks_values_keccak,
        );
    }
}
