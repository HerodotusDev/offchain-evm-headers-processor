from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from src.libs.utils import pow2, pow2h
from starkware.cairo.common.math import assert_le, assert_nn
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import unsigned_div_rem

// Computes MMR tree height given an index.
// This assumes the first index is 1. See below:
// H    MMR positions
// 2        7
//        /   \
// 1     3     6
//      / \   / \
// 0   1   2 4   5
func compute_height_pre_alloc_pow2{range_check_ptr}(x: felt, pow2_array: felt*) -> felt {
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
        return compute_height_pre_alloc_pow2(x - n + 1, pow2_array);
    }
}
