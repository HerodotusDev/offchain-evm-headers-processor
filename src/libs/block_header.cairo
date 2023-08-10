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

// Assumes all words in block header are 8 bytes little endian values.
// Returns the keccak hash in little endian representation, to be asserted directly
// against the cairo keccak hash of block header
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

    return (res=Uint256(low=res_low, high=res_high));
}

// Returns byte size of a Bigint inside a rlp using the first byte to decode
// Assume 0<= byte <= 183 (single byte or 55 byte long max)
func get_bigint_byte_size{range_check_ptr}(byte: felt) -> felt {
    %{ memory[ap]=1 if ids.byte<=127 else 0 %}
    ap += 1;
    let is_single_byte = [ap - 1];

    if (is_single_byte != 0) {
        assert [range_check_ptr] = 127 - byte;
        tempvar range_check_ptr = range_check_ptr + 1;
        return 0;
    } else {
        assert [range_check_ptr] = 183 - byte;
        tempvar range_check_ptr = range_check_ptr + 1;
        return byte - 128;
    }
}

// Returns the block number of a block header
// Assumes the block header is properly RLP encoded, and its words are 64 bit big endian values
// This is guaranteed if the block header has been previously keccak hashed and compared to a parent hash.
func extract_block_number_big{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, pow2_array: felt*}(
    rlp: felt*
) -> felt {
    alloc_locals;
    // Ethereum block header RLP encoding is as follows for the first 7 items:
    // parent hash prefix: \xf9\x02B\xa0 (4 bytes)
    // parent hash: 32 bytes
    // unclesHash prefix: \xa0 (1 byte)
    // unclesHash: 32 bytes
    // coinbase prefix: \x94 (1 byte)
    // coinbase: 20 bytes
    // stateRoot prefix: \xa0 (1 byte)
    // stateRoot: 32 bytes
    // transactionsRoot prefix: \xa0 (1 byte)
    // transactionsRoot: 32 bytes
    // receiptsRoot prefix: \xa0 (1 byte)
    // receiptsRoot: 32 bytes
    // logsBloom prefix: \xb9\x01\x00 (3 bytes)
    // logsBloom: 256 bytes

    // Next items : difficulty (variable length), number (variable length)
    // So we can skip the first 7 items, and start reading the difficulty field, by using the following offset :
    // 4 + 32 + 1 + 32 + 1 + 20 + 1 + 32 + 1 + 32 + 1 + 32 + 3 = 448 bytes
    // Since words are 8 bytes, we can skip 448/8==56 words, and start reading the difficulty field at word 57 (index 56)

    let rlp_difficulty = rlp[56];
    let next_word = rlp[57];

    let (first_byte, remaining_7) = felt_divmod(rlp_difficulty, 2 ** 56);
    let difficulty_offset = get_bigint_byte_size(first_byte);
    // MAX Difficulty recorded is 15911382925018176 so max difficulty offset is 7, and will alway fit in the remaining_7.

    if (difficulty_offset != 7) {
        // It means 0 <= difficulty_offset < 7 and the first byte of block number is inside remaining_7
        let mask = pow2_array[8 * (7 - difficulty_offset)] - 1;
        // The mask is setting '0x'+(7-difficulty_offset)*'ff'
        // For example,
        // If difficulty offset is 0, mask is 0xffffffffffffff (7 bytes)
        // If difficulty offset is 6, mask is 0xff (1 byte)
        assert bitwise_ptr[0].x = remaining_7;
        assert bitwise_ptr[0].y = mask;
        tempvar block_number_item_start = bitwise_ptr[0].x_and_y;
        tempvar bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;

        let block_number_item = block_number_item_start * 2 ** 64 + next_word;

        let (first_byte, remainder) = felt_divmod(
            block_number_item, pow2_array[(7 - difficulty_offset) * 8 + 56]
        );

        let block_number_offset = get_bigint_byte_size(first_byte);

        if (block_number_offset == 0) {
            if (first_byte == 128) {
                return 0;
            } else {
                return first_byte;
            }
        } else {
            let (block_number, _) = felt_divmod(
                remainder, pow2_array[56 + (7 - difficulty_offset) * 8 - block_number_offset * 8]
            );
            return block_number;
        }
    } else {
        // It means difficulty_offset == 7 and the block number item starts at the next word
        let block_number_item = next_word;
        let (first_byte, remaining_7) = felt_divmod(block_number_item, 2 ** 56);
        let block_number_offset = get_bigint_byte_size(first_byte);
        if (block_number_offset == 0) {
            if (first_byte == 128) {
                return 0;
            } else {
                return first_byte;
            }
        } else {
            let (block_number, _) = felt_divmod(
                remaining_7, pow2_array[56 - block_number_offset * 8]
            );
            return block_number;
        }
    }
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
