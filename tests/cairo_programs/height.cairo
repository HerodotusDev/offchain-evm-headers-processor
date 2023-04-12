%builtins output range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_felts
from src.libs.mmr import compute_height, compute_height_range_check, compute_height_pre_alloc_pow2
from src.libs.utils import pow2alloc127

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
