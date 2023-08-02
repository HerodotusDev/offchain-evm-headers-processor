from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from starkware.cairo.common.math import unsigned_div_rem as felt_divmod
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from src.libs.utils import (
    bitwise_divmod,
    felt_divmod_2pow32,
    word_reverse_endian_64,
    word_reverse_endian_64_RC,
    word_reverse_endian_16_RC,
    word_reverse_endian_24_RC,
    word_reverse_endian_32_RC,
    word_reverse_endian_40_RC,
    word_reverse_endian_48_RC,
    word_reverse_endian_56_RC,
)

func read_block_headers() -> (rlp_array: felt**, rlp_array_bytes_len: felt*) {
    let (block_headers_array: felt**) = alloc();
    let (block_headers_array_bytes_len: felt*) = alloc();
    %{
        block_headers_array = program_input['block_headers_array']
        bytes_len_array = program_input['bytes_len_array']
        segments.write_arg(ids.block_headers_array, block_headers_array)
        segments.write_arg(ids.block_headers_array_bytes_len, bytes_len_array)
    %}
    return (block_headers_array, block_headers_array_bytes_len);
}

// Assumes all words in rlp are 8 bytes little endian values.
// Returns the keccak hash in little endian representation, to be asserter directly
// against the hash of cairo keccak.
func extract_parent_hash_little{range_check_ptr}(rlp: felt*) -> (res: Uint256) {
    alloc_locals;
    let rlp_0 = rlp[0];
    let (rlp_0, thrash) = felt_divmod_2pow32(rlp_0);
    let rlp_1 = rlp[1];
    let rlp_2 = rlp[2];
    let (rlp_2_left, rlp_2_right) = felt_divmod_2pow32(rlp_2);
    let rlp_3 = rlp[3];
    let rlp_4 = rlp[4];
    let (thrash, rlp_4) = felt_divmod_2pow32(rlp_4);

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

// This function should only be called after the hash of the block header has been verified against the parent hash.
// seed is used to divide resource allocation between range check and bitwise.
// Returns the reversed block header and the number of felts in it.
func reverse_block_header_chunks{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    n_bytes: felt, block_header: felt*, seed: felt
) -> (reversed: felt*, n_felts: felt) {
    alloc_locals;
    let (reversed_block_header: felt*) = alloc();
    let (number_of_exact_8bytes_chunks, number_of_bytes_in_last_chunk) = felt_divmod(n_bytes, 8);
    let (_, rem) = felt_divmod(seed, 2);

    if (rem == 0) {
        reverse_block_header_chunks_RC_inner(
            index=number_of_exact_8bytes_chunks - 1,
            block_header=block_header,
            reversed_block_header=reversed_block_header,
        );
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
    } else {
        reverse_block_header_chunks_bitwise_inner(
            index=number_of_exact_8bytes_chunks - 1,
            block_header=block_header,
            reversed_block_header=reversed_block_header,
        );
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
    }

    if (number_of_bytes_in_last_chunk == 1) {
        assert reversed_block_header[number_of_exact_8bytes_chunks] = block_header[
            number_of_exact_8bytes_chunks
        ];
        return (reversed_block_header, number_of_exact_8bytes_chunks + 1);
    }

    if (number_of_bytes_in_last_chunk == 2) {
        let last_reversed_chunk: felt = word_reverse_endian_16_RC(
            block_header[number_of_exact_8bytes_chunks]
        );
        assert reversed_block_header[number_of_exact_8bytes_chunks] = last_reversed_chunk;
        return (reversed_block_header, number_of_exact_8bytes_chunks + 1);
    }

    if (number_of_bytes_in_last_chunk == 3) {
        let last_reversed_chunk: felt = word_reverse_endian_24_RC(
            block_header[number_of_exact_8bytes_chunks]
        );
        assert reversed_block_header[number_of_exact_8bytes_chunks] = last_reversed_chunk;
        return (reversed_block_header, number_of_exact_8bytes_chunks + 1);
    }

    if (number_of_bytes_in_last_chunk == 4) {
        let last_reversed_chunk: felt = word_reverse_endian_32_RC(
            block_header[number_of_exact_8bytes_chunks]
        );
        assert reversed_block_header[number_of_exact_8bytes_chunks] = last_reversed_chunk;
        return (reversed_block_header, number_of_exact_8bytes_chunks + 1);
    }

    if (number_of_bytes_in_last_chunk == 5) {
        let last_reversed_chunk: felt = word_reverse_endian_40_RC(
            block_header[number_of_exact_8bytes_chunks]
        );
        assert reversed_block_header[number_of_exact_8bytes_chunks] = last_reversed_chunk;
        return (reversed_block_header, number_of_exact_8bytes_chunks + 1);
    }

    if (number_of_bytes_in_last_chunk == 6) {
        let last_reversed_chunk: felt = word_reverse_endian_48_RC(
            block_header[number_of_exact_8bytes_chunks]
        );
        assert reversed_block_header[number_of_exact_8bytes_chunks] = last_reversed_chunk;
        return (reversed_block_header, number_of_exact_8bytes_chunks + 1);
    }

    if (number_of_bytes_in_last_chunk == 7) {
        let last_reversed_chunk: felt = word_reverse_endian_56_RC(
            block_header[number_of_exact_8bytes_chunks]
        );
        assert reversed_block_header[number_of_exact_8bytes_chunks] = last_reversed_chunk;
        return (reversed_block_header, number_of_exact_8bytes_chunks + 1);
    }

    return (reversed_block_header, number_of_exact_8bytes_chunks);
}

func reverse_block_header_chunks_RC{range_check_ptr}(n_felts: felt, block_header: felt*) -> felt* {
    alloc_locals;
    let (reversed_block_header: felt*) = alloc();
    reverse_block_header_chunks_RC_inner(
        index=n_felts - 1, block_header=block_header, reversed_block_header=reversed_block_header
    );
    return reversed_block_header;
}

func reverse_block_header_chunks_RC_inner{range_check_ptr}(
    index: felt, block_header: felt*, reversed_block_header: felt*
) {
    if (index == 0) {
        let reversed_chunk_i: felt = word_reverse_endian_64_RC(block_header[index]);
        assert reversed_block_header[index] = reversed_chunk_i;
        return ();
    } else {
        let reversed_chunk_i: felt = word_reverse_endian_64_RC(block_header[index]);
        assert reversed_block_header[index] = reversed_chunk_i;
        return reverse_block_header_chunks_RC_inner(
            index=index - 1, block_header=block_header, reversed_block_header=reversed_block_header
        );
    }
}

func reverse_block_header_chunks_bitwise{bitwise_ptr: BitwiseBuiltin*}(
    n_felts: felt, block_header: felt*
) -> felt* {
    alloc_locals;
    let (reversed_block_header: felt*) = alloc();
    reverse_block_header_chunks_bitwise_inner(
        index=n_felts - 1, block_header=block_header, reversed_block_header=reversed_block_header
    );
    return reversed_block_header;
}

func reverse_block_header_chunks_bitwise_inner{bitwise_ptr: BitwiseBuiltin*}(
    index: felt, block_header: felt*, reversed_block_header: felt*
) {
    if (index == 0) {
        let (reversed_chunk_i: felt) = word_reverse_endian_64(block_header[index]);
        assert reversed_block_header[index] = reversed_chunk_i;
        return ();
    } else {
        let (reversed_chunk_i: felt) = word_reverse_endian_64(block_header[index]);
        assert reversed_block_header[index] = reversed_chunk_i;
        return reverse_block_header_chunks_bitwise_inner(
            index=index - 1, block_header=block_header, reversed_block_header=reversed_block_header
        );
    }
}
