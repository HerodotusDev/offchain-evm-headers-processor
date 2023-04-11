from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from src.libs.utils import pow2

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
        return bit_length - 1;
    } else {
        // Jump left on the MMR and continue until it's all ones.
        tempvar bitwise_ptr = bitwise_ptr + 2 * BitwiseBuiltin.SIZE;
        return compute_height(x - (n - 1));
    }
}
