from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from src.libs.utils import pow2, pow2h
from starkware.cairo.common.math import assert_le, assert_nn
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash

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

    let N = pow2_array[bit_length];
    let n = pow2_array[bit_length - 1];

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

// func compute_first_peak_pos{range_check_ptr, pow2_array: felt*}(mmr_len: felt) -> felt {
//     alloc_locals;
//     local bit_length;
//     %{
//         mmr_len = ids.mmr_len
//         ids.bit_length = mmr_len.bit_length()
//     %}
//     // Computes N=2^bit_length and n=2^(bit_length-1)
//     // x is supposed to verify n = 2^(b-1) <= x < N = 2^bit_length <=> x has bit_length bits

// let N = pow2_array[bit_length];
//     let n = pow2_array[bit_length - 1];

// assert [range_check_ptr] = N - mmr_len - 1;
//     assert [range_check_ptr + 1] = mmr_len - n;
//     tempvar range_check_ptr = range_check_ptr + 2;

// let peak_pos = pow2_array[bit_length - 1] - 1;
//     return peak_pos;
// }

// // returns peaks position from left to right
// func compute_peaks_positions{range_check_ptr, pow2_array: felt*}(mmr_len: felt) -> (
//     peaks: felt*, peaks_len: felt
// ) {
//     alloc_locals;
//     let (peaks: felt*) = alloc();
//     with mmr_len {
//         let first_peak_pos = compute_first_peak_pos(mmr_len);
//         assert peaks[0] = first_peak_pos;
//         let peaks_len = compute_peaks_inner(peaks, 1, first_peak_pos);
//     }

// return (peaks, peaks_len);
// }

// func compute_peaks_inner{range_check_ptr, pow2_array: felt*, mmr_len: felt}(
//     peaks: felt*, peaks_len: felt, mmr_pos: felt
// ) -> felt {
//     alloc_locals;
//     if (mmr_pos == mmr_len) {
//         return peaks_len;
//     } else {
//         let height = compute_height_pre_alloc_pow2(mmr_pos);
//         let right_sibling = mmr_pos + pow2_array[height + 1] - 1;
//         let left_child = left_child_jump_until_inside_mmr(right_sibling);
//         assert peaks[peaks_len] = left_child;
//         return compute_peaks_inner(peaks, peaks_len + 1, left_child);
//     }
// }

// func left_child_jump_until_inside_mmr{range_check_ptr, pow2_array: felt*, mmr_len}(
//     left_child: felt
// ) -> felt {
//     alloc_locals;
//     local in_mmr;

// %{ ids.in_mmr = 1 if ids.left_child<=ids.mmr_len else 0 %}
//     if (in_mmr != 0) {
//         return left_child;
//     } else {
//         let height = compute_height_pre_alloc_pow2(left_child);
//         let left_child = left_child - pow2_array[height];
//         return left_child_jump_until_inside_mmr(left_child);
//     }
// }

// func get_root{range_check_ptr, pow2_array: felt*}(mmr_array: felt*, mmr_len: felt) -> felt {
//     alloc_locals;
//     let (peaks_positions: felt*, peaks_len: felt) = compute_peaks_positions(mmr_len);
//     let bagged_peaks = bag_peaks(mmr_array, peaks, peaks_len);
//     let root = poseidon_hash(mmr_len, bagged_peaks);
//     return root;
// }

// func bag_peaks{range_check_ptr, poseidon_ptr: PoseidonBuiltin*}(peaks_len: felt, peaks: felt*) -> (
//     res: felt
// ) {
//     assert_le(1, peaks_len);

// if (peaks_len == 1) {
//         return (res=peaks[0]);
//     }

// let last_peak = peaks[0];
//     let (rec) = bag_peaks(peaks_len - 1, peaks + 1);

// let (res) = poseidon_hash(last_peak, rec);

// return (res=res);
// }
