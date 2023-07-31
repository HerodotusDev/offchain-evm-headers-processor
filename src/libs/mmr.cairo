from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, KeccakBuiltin
from starkware.cairo.common.math import assert_le, assert_nn
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.dict import dict_write, dict_read
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_uint256

// Computes MMR tree height given an index.
// This assumes the first index is 1. See below:
// H    MMR positions
// 2        7
//        /   \
// 1     3     6
//      / \   / \
// 0   1   2 4   5
func compute_height_pre_alloc_pow2{range_check_ptr, pow2_array: felt*}(x: felt) -> felt {
    alloc_locals;
    local bit_length;
    %{
        x = ids.x
        ids.bit_length = x.bit_length()
    %}
    // Computes N=2^bit_length and n=2^(bit_length-1)
    // x is supposed to verify n = 2^(b-1) <= x < N = 2^bit_length <=> x has bit_length bits

    tempvar N = pow2_array[bit_length];
    tempvar n = pow2_array[bit_length - 1];

    if (x == N - 1) {
        // x has bit_length bits and they are all ones.
        // We return the height which is bit_length - 1.
        // %{ print(f" compute_height : {ids.bit_length - 1} ") %}
        return bit_length - 1;
    } else {
        // Ensure 2^(bit_length-1) <= x < 2^bit_length so that x has indeed bit_length bits.
        assert [range_check_ptr] = N - x - 1;
        assert [range_check_ptr + 1] = x - n;
        tempvar range_check_ptr = range_check_ptr + 2;
        // Jump left on the MMR and continue until it's all ones.
        return compute_height_pre_alloc_pow2(x - n + 1);
    }
}

func compute_first_peak_pos{range_check_ptr, pow2_array: felt*}(mmr_len: felt) -> felt {
    alloc_locals;
    local bit_length;
    %{
        mmr_len = ids.mmr_len
        ids.bit_length = mmr_len.bit_length()
    %}
    // Computes N=2^bit_length and n=2^(bit_length-1)
    // x is supposed to verify n = 2^(b-1) <= x < N = 2^bit_length <=> x has bit_length bits

    let N = pow2_array[bit_length];
    let n = pow2_array[bit_length - 1];

    assert [range_check_ptr] = N - mmr_len - 1;
    assert [range_check_ptr + 1] = mmr_len - n;
    tempvar range_check_ptr = range_check_ptr + 2;

    let all_ones = pow2_array[bit_length] - 1;
    if (mmr_len == all_ones) {
        return mmr_len;
    } else {
        let peak_pos = pow2_array[bit_length - 1] - 1;
        return peak_pos;
    }
}

// returns peaks position from left to right
func compute_peaks_positions{range_check_ptr, pow2_array: felt*}(mmr_len: felt) -> (
    peaks: felt*, peaks_len: felt
) {
    alloc_locals;
    let (peaks: felt*) = alloc();
    with mmr_len {
        let first_peak_pos = compute_first_peak_pos(mmr_len);
        assert peaks[0] = first_peak_pos;
        let peaks_len = compute_peaks_inner(peaks, 1, first_peak_pos);
    }

    return (peaks, peaks_len);
}

func compute_peaks_inner{range_check_ptr, pow2_array: felt*, mmr_len: felt}(
    peaks: felt*, peaks_len: felt, mmr_pos: felt
) -> felt {
    alloc_locals;
    if (mmr_pos == mmr_len) {
        return peaks_len;
    } else {
        let height = compute_height_pre_alloc_pow2(mmr_pos);
        let right_sibling = mmr_pos + pow2_array[height + 1] - 1;
        let left_child = left_child_jump_until_inside_mmr(right_sibling);
        assert peaks[peaks_len] = left_child;
        return compute_peaks_inner(peaks, peaks_len + 1, left_child);
    }
}

func left_child_jump_until_inside_mmr{range_check_ptr, pow2_array: felt*, mmr_len}(
    left_child: felt
) -> felt {
    alloc_locals;
    local in_mmr;

    %{ ids.in_mmr = 1 if ids.left_child<=ids.mmr_len else 0 %}
    if (in_mmr != 0) {
        // Ensure left_child <= mmr_len
        assert [range_check_ptr] = mmr_len - left_child;
        tempvar range_check_ptr = range_check_ptr + 1;
        return left_child;
    } else {
        // Ensure mmr_len < left_child
        assert [range_check_ptr] = left_child - mmr_len - 1;
        tempvar range_check_ptr = range_check_ptr + 1;

        let height = compute_height_pre_alloc_pow2(left_child);
        let left_child = left_child - pow2_array[height];
        return left_child_jump_until_inside_mmr(left_child);
    }
}
// Position must be a peak position
func get_full_mmr_peak_values{
    range_check_ptr,
    mmr_array_poseidon: felt*,
    mmr_array_keccak: Uint256*,
    mmr_offset: felt,
    previous_peaks_dict_poseidon: DictAccess*,
    previous_peaks_dict_keccak: DictAccess*,
}(position: felt) -> (peak_poseidon: felt, peak_keccak: Uint256) {
    alloc_locals;
    %{ print(f"Asked position : {ids.position}, mmr_offset : {ids.mmr_offset}") %}
    local is_position_in_mmr_array: felt;
    %{ ids.is_position_in_mmr_array= 1 if ids.position > ids.mmr_offset else 0 %}
    if (is_position_in_mmr_array != 0) {
        %{ print(f'getting from mmr_array at index {ids.position-ids.mmr_offset -1}') %}
        // ensure position > mmr_offset
        assert [range_check_ptr] = position - mmr_offset - 1;
        tempvar range_check_ptr = range_check_ptr + 1;
        let peak_poseidon = mmr_array_poseidon[position - mmr_offset - 1];
        let peak_keccak = mmr_array_keccak[position - mmr_offset - 1];
        return (peak_poseidon, peak_keccak);
    } else {
        %{ print('getting from dict') %}
        // ensure position <= mmr_offset

        assert [range_check_ptr] = mmr_offset - position;
        tempvar range_check_ptr = range_check_ptr + 1;
        let (peak_poseidon: felt) = dict_read{dict_ptr=previous_peaks_dict_poseidon}(key=position);
        // Treat the felt value from dict back to a Uint256 ptr:
        let (peak_keccak_ptr: Uint256*) = dict_read{dict_ptr=previous_peaks_dict_keccak}(
            key=position
        );
        local peak_keccak: Uint256;
        assert peak_keccak.low = peak_keccak_ptr.low;
        assert peak_keccak.high = peak_keccak_ptr.high;
        %{
            print(f"dict_peak poseidon value at {ids.position} = {ids.peak_poseidon}") 
            print(f"dict_peak keccak value at {ids.position} = {ids.peak_keccak.low} {ids.peak_keccak.high}")
        %}
        return (peak_poseidon, peak_keccak);
    }
}

func get_roots{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    mmr_array_poseidon: felt*,
    mmr_array_keccak: Uint256*,
    mmr_array_len: felt,
    pow2_array: felt*,
    previous_peaks_dict_poseidon: DictAccess*,
    previous_peaks_dict_keccak: DictAccess*,
    mmr_offset: felt,
}() -> (root_poseidon: felt, root_keccak: Uint256) {
    alloc_locals;
    let (peaks_positions: felt*, peaks_len: felt) = compute_peaks_positions(
        mmr_array_len + mmr_offset
    );
    let (peaks_poseidon: felt*, peaks_keccak: Uint256*) = get_peaks_from_positions{
        peaks_positions=peaks_positions
    }(peaks_len);
    let (bagged_peaks_poseidon, bagged_peaks_keccak) = bag_peaks(
        peaks_poseidon, peaks_keccak, peaks_len
    );

    return (bagged_peaks_poseidon, bagged_peaks_keccak);
}

func get_peaks_from_positions{
    range_check_ptr,
    mmr_array_poseidon: felt*,
    mmr_array_keccak: Uint256*,
    mmr_offset: felt,
    previous_peaks_dict_poseidon: DictAccess*,
    previous_peaks_dict_keccak: DictAccess*,
    peaks_positions: felt*,
}(peaks_len: felt) -> (peaks_poseidon: felt*, peaks_keccak: Uint256*) {
    alloc_locals;
    let (peaks_poseidon: felt*) = alloc();
    let (peaks_keccak: Uint256*) = alloc();
    get_peaks_from_positions_inner(peaks_poseidon, peaks_keccak, peaks_len - 1);
    return (peaks_poseidon, peaks_keccak);
}

func get_peaks_from_positions_inner{
    range_check_ptr,
    mmr_array_poseidon: felt*,
    mmr_array_keccak: Uint256*,
    mmr_offset: felt,
    previous_peaks_dict_poseidon: DictAccess*,
    previous_peaks_dict_keccak: DictAccess*,
    peaks_positions: felt*,
}(peaks_poseidon: felt*, peaks_keccak: Uint256*, index: felt) {
    alloc_locals;
    if (index == 0) {
        let (value_poseidon: felt, value_keccak: Uint256) = get_full_mmr_peak_values(
            peaks_positions[0]
        );
        assert peaks_poseidon[0] = value_poseidon;
        assert peaks_keccak[0].low = value_keccak.low;
        assert peaks_keccak[0].high = value_keccak.high;

        return ();
    } else {
        let (value_poseidon, value_keccak) = get_full_mmr_peak_values(peaks_positions[index]);
        assert peaks_poseidon[index] = value_poseidon;
        assert peaks_keccak[index].low = value_keccak.low;
        assert peaks_keccak[index].high = value_keccak.high;
        return get_peaks_from_positions_inner(peaks_poseidon, peaks_keccak, index - 1);
    }
}

func bag_peaks{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}(peaks_poseidon: felt*, peaks_keccak: Uint256*, peaks_len: felt) -> (
    bag_peaks_poseidon: felt, bag_peaks_keccak: Uint256
) {
    alloc_locals;

    assert_le(1, peaks_len);
    if (peaks_len == 1) {
        return ([peaks_poseidon], [peaks_keccak]);
    }

    let last_peak_poseidon = [peaks_poseidon];
    let last_peak_keccak = [peaks_keccak];
    let (rec_poseidon, rec_keccak) = bag_peaks(peaks_poseidon + 1, peaks_keccak + 2, peaks_len - 1);

    let (res_poseidon) = poseidon_hash(last_peak_poseidon, rec_poseidon);
    let (keccak_input: felt*) = alloc();
    let inputs_start = keccak_input;
    keccak_add_uint256{inputs=keccak_input}(num=last_peak_keccak, bigend=1);
    keccak_add_uint256{inputs=keccak_input}(num=rec_keccak, bigend=1);
    let (res_keccak: Uint256) = keccak(inputs=inputs_start, n_bytes=2 * 32);
    let (res_keccak) = uint256_reverse_endian(res_keccak);
    return (res_poseidon, res_keccak);
}
