from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from src.libs.utils import pow2, bitwise_divmod

func fetch_block_headers_rlp(from_block_number_high: felt, to_block_number_low: felt) -> (
    rlp_array: felt**, rlp_array_bytes_len: felt*
) {
    let (rlp_arrays: felt**) = alloc();
    let (rlp_arrays_bytes_len: felt*) = alloc();
    %{
        from tools.py.fetch_block_headers import main, build_block_header, bytes_to_little_endian_ints as to_keccak_felts
        import pickle, os, asyncio
        print(f"Building block headers from block {ids.from_block_number_high} to {ids.to_block_number_low} ...")
        offline_mode = False

        fetch_block_call = asyncio.run(main(ids.from_block_number_high, ids.to_block_number_low))
        block_headers_raw_rlp = [build_block_header(block['result']).raw_rlp() for block in fetch_block_call]
        rlp_arrays = [to_keccak_felts(raw_rlp) for raw_rlp in block_headers_raw_rlp]
        bytes_len_array= [len(raw_rlp) for raw_rlp in block_headers_raw_rlp]


        segments.write_arg(ids.rlp_arrays, rlp_arrays)
        segments.write_arg(ids.rlp_arrays_bytes_len, bytes_len_array)
    %}
    return (rlp_arrays, rlp_arrays_bytes_len);
}

// Assumes all words in rlp are 8 bytes little endian values.
// Returns the keccak hash in little endian representation, to be asserter directly
// against the hash of cairo keccak.
func extract_parent_hash_little{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(rlp: felt*) -> (
    res: Uint256
) {
    alloc_locals;
    let rlp_0 = rlp[0];
    let (rlp_0, thrash) = bitwise_divmod(rlp_0, 2 ** 32);
    let rlp_1 = rlp[1];
    let rlp_2 = rlp[2];
    let (rlp_2_left, rlp_2_right) = bitwise_divmod(rlp_2, 2 ** 32);
    let rlp_3 = rlp[3];
    let rlp_4 = rlp[4];
    let (thrash, rlp_4) = bitwise_divmod(rlp_4, 2 ** 32);

    let res_low = rlp_2_right * 2 ** 96 + rlp_1 * 2 ** 32 + rlp_0;
    let res_high = rlp_4 * 2 ** 96 + rlp_3 * 2 ** 32 + rlp_2_left;

    // %{ print_felt_info(ids.rlp_0, 'rlp_0',4) %}
    // %{ print_felt_info(ids.rlp_1, 'rlp_1',8) %}
    // %{ print_felt_info(ids.rlp_2, 'rlp_2',8) %}
    // %{ print_felt_info(ids.rlp_2_left, 'rlp_2_left', 4) %}
    // %{ print_felt_info(ids.rlp_2_right, 'rlp_2_right',4) %}
    // %{ print_felt_info(ids.rlp_3, 'rlp_3',8) %}
    // %{ print_felt_info(ids.rlp_4, 'rlp_4',4) %}
    // %{ print_felt_info(ids.res_low, 'res_low', 16) %}
    // %{ print_felt_info(ids.res_high, 'res_high', 16) %}

    return (res=Uint256(low=res_low, high=res_high));
}
