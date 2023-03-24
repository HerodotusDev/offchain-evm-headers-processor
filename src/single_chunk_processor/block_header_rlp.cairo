from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from src.utils import pow2, bitwise_divmod
struct BlockHeaderRLP {
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    rlp: felt*,
}

func fetch_block_headers_rlp(from_block_number_high: felt, to_block_number_low: felt) -> (
    block_header_rlp_array: BlockHeaderRLP*, block_header_rlp_array_len: felt
) {
    alloc_locals;
    let (block_header_rlp_array: BlockHeaderRLP*) = alloc();
    local block_n_parent_hash: Uint256;
    %{
        from tools.py.fetch_block_headers import main, build_block_header
        from tools.py.types import Data
        import asyncio
        fetch_block_call = asyncio.run(main(ids.from_block_number_high, ids.to_block_number_low))
        block_headers = [build_block_header(block['result']) for block in fetch_block_call]
        block_header_rlp_array = [Data.from_bytes(block_header.raw_rlp()).to_ints() for block_header in block_headers]
        print(f"BLOCK ARRAY\n {block_header_rlp_array}")
    %}
    fetch_block_headers_rlp_loop(
        n_blocks_to_fetch=from_block_number_high - to_block_number_low + 1,
        index=0,
        rlp_array=block_header_rlp_array,
    );
    return (block_header_rlp_array, from_block_number_high - to_block_number_low + 1);
}

func fetch_block_headers_rlp_loop(
    n_blocks_to_fetch: felt, index: felt, rlp_array: BlockHeaderRLP*
) {
    alloc_locals;
    if (index == n_blocks_to_fetch) {
        return ();
    } else {
        let (block_header_rlp: felt*) = alloc();
        %{
            memory[ids.rlp_array.address_ + ids.index*3] = block_header_rlp_array[ids.index].length
            memory[ids.rlp_array.address_ + ids.index*3 + 1] = len(block_header_rlp_array[ids.index].values)
            segments.write_arg(ids.block_header_rlp, block_header_rlp_array[ids.index].values)
        %}
        assert rlp_array[index].rlp = block_header_rlp;
        return fetch_block_headers_rlp_loop(
            n_blocks_to_fetch=n_blocks_to_fetch, index=index + 1, rlp_array=rlp_array
        );
    }

    return ();
}

// Assumes all words in BlockheaderRLP are 64 bits.
func extract_parent_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(x: BlockHeaderRLP) -> (
    res: Uint256
) {
    alloc_locals;

    let first_192_bits = x.rlp[0] * 2 ** 128 + x.rlp[1] * 2 ** 64 + x.rlp[2];
    %{ print_felt_info(ids.first_192_bits, 'first 192') %}
    let (thrash, requested_first_160_bits) = bitwise_divmod(first_192_bits, 2 ** 160);

    %{ print_felt_info(ids.requested_first_160_bits, 'requested_first_160_bits') %}
    // %{ print_felt_info(ids.next, 'next') %}

    let (requested_first_128_bits, next_32_bits) = bitwise_divmod(
        requested_first_160_bits, 2 ** 32
    );
    %{ print_felt_info(ids.requested_first_128_bits, 'requested_first_128_bits') %}

    let requested_last_128_bits_and_extra_32_bits = next_32_bits * 2 ** 128 + x.rlp[3] * 2 ** 64 +
        x.rlp[4];
    let (requested_last_128_bits, thrash) = bitwise_divmod(
        requested_last_128_bits_and_extra_32_bits, 2 ** 32
    );

    // First and last are when reading from left (first) to right (last).
    // However, in big endian, the first part is the "high" part and the last part is the low part.
    // Hence the potential confusing output:
    return (res=Uint256(low=requested_last_128_bits, high=requested_first_128_bits));
}

// Assumes all words in BlockheaderRLP are 64 bits.
// from_byte_numbers starts at 0.
func extract_32_bytes_from_byte_number{range_check_ptr}(
    from_byte_number: felt, x: BlockHeaderRLP
) -> (res: Uint256) {
    alloc_locals;

    let (from_word_number, from_byte_number) = unsigned_div_rem(from_byte_number, 8);

    let div = pow2(8 * from_byte_number);

    let first_192_bits_from_word_number = x.rlp[from_word_number] * 2 ** 128 + x.rlp[
        from_word_number + 1
    ] * 2 ** 64 + x.rlp[from_word_number + 2];

    let (_, requested_first_160_bits) = unsigned_div_rem(first_192_bits_from_word_number, div);
    let (requested_first_128_bits, next_32_bits) = unsigned_div_rem(requested_first_160_bits, div);

    let requested_last_128_bits_and_extra_32_bits = next_32_bits * 2 ** 128 + x.rlp[
        from_word_number + 3
    ] * 2 ** 64 + x.rlp[from_word_number + 4];
    let (requested_last_128_bits, _) = unsigned_div_rem(
        requested_last_128_bits_and_extra_32_bits, div
    );

    // First and last are when reading from left to right.
    // However, in big endian, the first part is the "high" part and the last part is the low part.
    return (res=Uint256(low=requested_last_128_bits, high=requested_first_128_bits));
}
