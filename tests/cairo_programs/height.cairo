%builtins output range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_felts
from src.libs.mmr import compute_height_pre_alloc_pow2
from src.libs.utils import pow2alloc127, pow2, pow2h

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

func main{output_ptr: felt*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;
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

        def print_felt_info(u, un):
            print(f" {un}_{u.bit_length()}bits = {bin_8(u)}")
            print(f" {un} = {u}")
    %}

    local n = 1234567;
    let h1 = compute_height(n);
    let h2 = compute_height_range_check(n);
    let pow2_array: felt* = pow2alloc127();
    let h3 = compute_height_pre_alloc_pow2(n, pow2_array);
    assert h1 = h2;
    assert h2 = h3;

    local n = 100;
    with pow2_array {
        assert_recurse(n);
    }
    return ();
}

func assert_recurse{
    output_ptr: felt*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*, pow2_array: felt*
}(n: felt) {
    alloc_locals;
    if (n == 0) {
        return ();
    }
    let h1 = compute_height(n);
    let h2 = compute_height_range_check(n);
    let h3 = compute_height_pre_alloc_pow2(n, pow2_array);
    assert h1 = h2;
    assert h2 = h3;

    assert_recurse(n - 1);
    return ();
}
