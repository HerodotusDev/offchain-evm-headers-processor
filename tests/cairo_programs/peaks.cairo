%builtins output range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_felts
from src.libs.mmr import (
    compute_height_pre_alloc_pow2,
    compute_first_peak_pos,
    compute_peaks_positions,
)
from src.libs.utils import pow2alloc127

func main{output_ptr: felt*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;
    %{
        from typing import List, Tuple, Optional
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

    local n;
    let (true_pos: felt*) = alloc();
    local true_first_pos: felt;
    %{
        import random
        from tools.py.mmr import get_peaks

        n=random.randint(1, 20000000)
        #n=19
        ids.n=n;
        peak_pos = [x+1 for x in get_peaks(n)]
        print("peak_pos", peak_pos)
        print("mmr_size", n)
        ids.true_first_pos = peak_pos[0]
        segments.write_arg(ids.true_pos, peak_pos)
    %}
    let pow2_array: felt* = pow2alloc127();
    with pow2_array {
        let first_peak_pos = compute_first_peak_pos(n);
        let (peaks: felt*, peaks_len: felt) = compute_peaks_positions(n);
    }
    assert first_peak_pos = true_first_pos;
    assert_array_rec(true_pos, peaks, peaks_len - 1);
    return ();
}

func assert_array_rec(x: felt*, y: felt*, index: felt) {
    if (index == 0) {
        assert x[0] = y[0];
        return ();
    } else {
        assert x[index] = y[index];
        return assert_array_rec(x, y, index - 1);
    }
}
