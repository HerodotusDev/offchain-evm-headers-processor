%builtins output range_check bitwise keccak poseidon

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_felts
from src.libs.mmr import compute_first_peak_pos, compute_peaks_positions, bag_peaks
from src.libs.utils import pow2alloc127

func main{
    output_ptr: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}() {
    alloc_locals;

    let pow2_array: felt* = pow2alloc127();

    compute_height_pre_alloc_pow2{pow2_array=pow2_array}(17);
    return ();
}

func compute_height_pre_alloc_pow2{range_check_ptr, pow2_array: felt*}(x: felt) -> felt {
    alloc_locals;
    local bit_length;
    %{
        x = ids.x
        ids.bit_length = 2500
    %}
    // Computes N=2^bit_length and n=2^(bit_length-1)
    // x is supposed to verify n = 2^(b-1) <= x < N = 2^bit_length <=> x has bit_length bits

    let N = pow2_array[bit_length];
    tempvar protect_malicious_prover = -1;
    let n = pow2_array[bit_length - 1];

    %{ print("N", ids.N, "n", ids.n) %}

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
