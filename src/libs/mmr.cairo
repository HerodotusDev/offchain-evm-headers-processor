from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from src.libs.utils import pow2, pow2h
from starkware.cairo.common.math import assert_le, assert_nn
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.math import unsigned_div_rem
// Computes the height of a MMR index.
// inputs:
//   x: the index of the MMR.

func compute_height{bitwise_ptr: BitwiseBuiltin*}(x: felt) -> felt {
    alloc_locals;
    local bit_length;
    %{
        x = ids.x
        ids.bit_length = x.bit_length()
    %}
    // Computes N=2^bit_length and n=2^(bit_length-1)
    // x is supposed to verify n <= x < N
    let N = pow2(bit_length);
    let n = pow2(bit_length - 1);

    // Computes bitwise x AND (N-1)
    // (N-1) in binary representation is 111...1111 with bit_length 1's.
    assert bitwise_ptr[0].x = x;
    assert bitwise_ptr[0].y = N - 1;
    tempvar word = bitwise_ptr[0].x_and_y;

    // This ensures x < N:
    assert word = x;

    // Computes bitwise x AND (n-1)
    // (n-1) in binary representation is 111...111 with (bit_length-1) 1's.
    assert bitwise_ptr[1].x = x;
    assert bitwise_ptr[1].y = n - 1;
    tempvar word = bitwise_ptr[1].x_and_y;

    // This ensures x >= n:
    assert word = x - n;

    // We have proven that 2^(bit_length-1) <= x < 2^bit_length
    // Therefore, x has bit_length bits.

    if (x == N - 1) {
        // x has bit_length bit they are all ones.
        // We return the height which is bit_length - 1.
        tempvar bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;
        %{ print(f" compute_ height : {ids.bit_length - 1} ") %}
        return bit_length - 1;
    } else {
        // Jump left on the MMR and continue until it's all ones.
        tempvar bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;
        return compute_height(x - (n - 1));
    }
}

func compute_height_range_check{range_check_ptr}(x: felt) -> felt {
    alloc_locals;
    local bit_length;
    %{
        x = ids.x
        ids.bit_length = x.bit_length()
    %}
    // Computes N=2^bit_length and n=2^(bit_length-1)
    // x is supposed to verify n <= x < N

    // This function should fail if 0 <= bit_length <= 127
    let (N, n) = pow2h(bit_length);

    if (x == N - 1) {
        // x has bit_length bits and they are all ones.
        // We return the height which is bit_length - 1.
        %{ print(f" compute_ height : {ids.bit_length - 1} ") %}
        return bit_length - 1;
    } else {
        // Ensure 2^(bit_length-1) <= x < 2^bit_length so that x has indeed bit_length bits.
        assert [range_check_ptr] = N - x;
        assert [range_check_ptr + 1] = x - n;
        tempvar range_check_ptr = range_check_ptr + 2;
        // Jump left on the MMR and continue until it's all ones.
        return compute_height_range_check(x - n + 1);
    }
}

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
        assert [range_check_ptr] = N - x -1;
        assert [range_check_ptr + 1] = x - n;
        tempvar range_check_ptr = range_check_ptr + 2;
        // Jump left on the MMR and continue until it's all ones.
        return compute_height_pre_alloc_pow2(x - n + 1, pow2_array);
    }
}
