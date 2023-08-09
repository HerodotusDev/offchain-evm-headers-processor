%builtins output range_check bitwise keccak

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.math import unsigned_div_rem as felt_divmod
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian

from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_uint256

from src.libs.utils import pow2alloc127, word_reverse_endian_64, bitwise_divmod

func main{
    output_ptr: felt*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
}() {
    alloc_locals;
    local x: Uint256;
    local y: Uint256;
    local keccak_result: Uint256;
    %{
        def bin_c(u):
            b=bin(u)
            f = b[0:10] + ' ' + b[10:19] + '...' + b[-16:-8] + ' ' + b[-8:]
            return f
        def print_u256_info(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un}_{u.bit_length()}bits = {bin_c(u)}")
            print(f" {un} = {hex(u)}")
            print(f" {un} = {int.to_bytes(u, 32, 'big')}")

        import sha3
        import random
        random.seed(1)
        def split_128(a):
            """Takes in value, returns uint256-ish tuple."""
            return [a & ((1 << 128) - 1), a >> 128]

        peaks = [0x0000041324c61b030a99c3a3a53584888d29f1cb1e8925cc23fa78902cfebeb7, 0x0000041324c61b030a99c3a3a53584888d29f1cb1e8925cc23fa78902cfebeb7]

        from web3 import Web3
        kecOutput = Web3.solidityKeccak(["uint256[]"], [peaks]).hex()[2:]
        ids.x.low = split_128(peaks[0])[0];
        ids.x.high = split_128(peaks[0])[1];
        ids.y.low = split_128(peaks[1])[0];
        ids.y.high = split_128(peaks[1])[1];

        k=sha3.keccak_256()
        k.update(peaks[0].to_bytes(32, 'big'))
        k.update(peaks[1].to_bytes(32, 'big'))
        keccak_result = int.from_bytes(k.digest(), 'big')

        assert kecOutput == hex(keccak_result)[2:]

        print(f"keccak_result_{keccak_result.bit_length()}bits = {hex(keccak_result)}")
        print(f"keccak_result = {int.to_bytes(keccak_result, 32, 'big')}")

        keccak_result_split = split_128(keccak_result)

        ids.keccak_result.low = keccak_result_split[0];
        ids.keccak_result.high = keccak_result_split[1];
    %}
    let pow2_array: felt* = pow2alloc127();

    let (keccak_input: felt*) = alloc();
    let inputs_start = keccak_input;
    keccak_add_uint256{inputs=keccak_input}(num=x, bigend=1);
    keccak_add_uint256{inputs=keccak_input}(num=y, bigend=1);

    let (res_keccak: Uint256) = keccak(inputs=inputs_start, n_bytes=2 * 32);
    let (res_keccak) = uint256_reverse_endian(res_keccak);

    %{ print_u256_info(ids.res_keccak, "res_keccak") %}

    assert res_keccak.low = keccak_result.low;
    assert res_keccak.high = keccak_result.high;

    return ();
}
