from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256

struct BlockHeaderRLP {
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    rlp: felt*,
}

func fetch_block_headers_rlp(from_block_number_high: felt, to_block_number_low: felt) -> (
    block_header_rlp_array: BlockHeaderRLP*, block_header_rlp_array_len
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
    return (block_header_rlp_array, block, from_block_number_high - to_block_number_low + 1);
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

//
// This internal function calculates the Keccak256 hash of the provided RLP-encoded bytes
// and compares this hash to the parent hash of the child block provided as input.
// @notice If the two hashes do not match, the function raises an error.
// @dev Otherwise, it returns without producing any output.
//
func validate_provided_header_rlp{
    pedersen_ptr: HashBuiltin*, bitwise_ptr: BitwiseBuiltin*, range_check_ptr
}(
    child_block_parent_hash: Keccak256Hash,
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    block_header_rlp: felt*,
) {
    alloc_locals;
    local bitwise_ptr: BitwiseBuiltin* = bitwise_ptr;
    let (local keccak_ptr: felt*) = alloc();
    let keccak_ptr_start = keccak_ptr;

    local header_ints_sequence: IntsSequence = IntsSequence(
        block_header_rlp, block_header_rlp_len, block_header_rlp_bytes_len
    );

    let (provided_rlp_hash) = keccak256{keccak_ptr=keccak_ptr}(header_ints_sequence);
    // finalize_keccak(keccak_ptr_start, keccak_ptr)

    // Ensure child block parenthash matches provided rlp hash
    assert child_block_parent_hash.word_1 = provided_rlp_hash[0];
    assert child_block_parent_hash.word_2 = provided_rlp_hash[1];
    assert child_block_parent_hash.word_3 = provided_rlp_hash[2];
    assert child_block_parent_hash.word_4 = provided_rlp_hash[3];
    return ();
}

struct IntsSequence {
    element: felt*,
    element_size_words: felt,
    element_size_bytes: felt,
}

func decode_parent_hash{range_check_ptr}(block_rlp: BlockHeaderRLP) -> (res: Keccak256Hash) {
    alloc_locals;
    let (local data: IntsSequence) = extract_data(4, 32, block_rlp);
    let parent_hash = data.element;
    local hash: Keccak256Hash = Keccak256Hash(
        word_1=parent_hash[0], word_2=parent_hash[1], word_3=parent_hash[2], word_4=parent_hash[3]
    );
    return (hash,);
}

// Assumes all words in BlockheaderRLP are 64 bits.
func extract_parent_hash{range_check_ptr}(x: BlockHeaderRLP) -> (res: Uint256) {
    alloc_locals;

    let first_192_bits_from_word_number = x.rlp[0] * 2 ** 128 + x.rlp[1] * 2 ** 64 + x.rlp[2];

    let (_, requested_first_160_bits) = unsigned_div_rem(first_192_bits_from_word_number, 2 ** 32);
    let (requested_first_128_bits, next_32_bits) = unsigned_div_rem(
        requested_first_160_bits, 2 ** 32
    );

    let requested_last_128_bits_and_extra_32_bits = next_32_bits * 2 ** 128 + x.rlp[3] * 2 ** 64 +
        x.rlp[4];
    let (requested_last_128_bits, _) = unsigned_div_rem(
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
    from_byte_number: felt, rlp: BlockHeaderRLP
) -> (res: Uint256) {
    alloc_locals;

    let (from_word_number, from_byte_number) = unsigned_div_rem(from_byte_number, 8);

    let first_192_bits_from_word_number = rlp.block_header_rlp[from_word_number] * 2 ** 128 +
        rlp.block_header_rlp[from_word_number + 1] * 2 ** 64 + rlp.block_header_rlp[
            from_word_number + 2
        ];

    let (_, requested_first_160_bits) = unsigned_div_rem(first_192_bits_from_word_number, 2 ** 32);
    let (requested_first_128_bits, next_32_bits) = unsigned_div_rem(
        requested_first_160_bits, 2 ** 32
    );

    let requested_last_128_bits_and_extra_32_bits = next_32_bits * 2 ** 128 + rlp.block_header_rlp[
        from_word_number + 3
    ] * 2 ** 64 + rlp.block_header_rlp[from_word_number + 4];
    let (requested_last_128_bits, _) = unsigned_div_rem(
        requested_last_128_bits_and_extra_32_bits, 2 ** 32
    );

    // First and last are when reading from left to right.
    // However, in big endian, the first part is the "high" part and the last part is the low part.
    return (res=Uint256(low=requested_last_128_bits, high=requested_first_128_bits));
}

func extract_data_rec{range_check_ptr}(
    start_word: felt,
    full_words: felt,
    left_shift: felt,
    right_shift: felt,
    last_word_right_shift: felt,
    rlp: IntsSequence,
    acc: felt*,
    acc_len: felt,
    current_index: felt,
) -> (new_acc_size: felt) {
    alloc_locals;

    if (current_index == full_words + start_word) {
        return (acc_len,);
    }

    let (local left_part) = bitshift_left(rlp.element[current_index], left_shift * 8);
    local right_part;
    if (current_index == rlp.element_size_words - 2) {
        local is_last_word_right_shift_negative = is_le(last_word_right_shift, -1);
        if (is_last_word_right_shift_negative == 1) {
            let (local right_part_tmp) = bitshift_left(
                rlp.element[current_index + 1], (-8) * last_word_right_shift
            );
            right_part = right_part_tmp;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (local right_part_tmp) = bitshift_right(
                rlp.element[current_index + 1], 8 * last_word_right_shift
            );
            right_part = right_part_tmp;
            tempvar range_check_ptr = range_check_ptr;
        }
        tempvar range_check_ptr = range_check_ptr;
    } else {
        if (current_index == rlp.element_size_words - 1) {
            right_part = 0;
            tempvar range_check_ptr = range_check_ptr;
        } else {
            let (local right_part_tmp) = bitshift_right(
                rlp.element[current_index + 1], 8 * right_shift
            );
            right_part = right_part_tmp;
            tempvar range_check_ptr = range_check_ptr;
        }
        tempvar range_check_ptr = range_check_ptr;
    }

    local new_word = left_part + right_part;

    local range_check_ptr = range_check_ptr;

    let (_, new_word_masked) = unsigned_div_rem(new_word, 2 ** 64);

    local range_check_ptr = range_check_ptr;

    assert acc[current_index - start_word] = new_word_masked;

    return extract_data_rec(
        start_word=start_word,
        full_words=full_words,
        left_shift=left_shift,
        right_shift=right_shift,
        last_word_right_shift=last_word_right_shift,
        rlp=rlp,
        acc=acc,
        acc_len=acc_len + 1,
        current_index=current_index + 1,
    );
}
