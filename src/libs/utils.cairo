from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.registers import get_label_location
from starkware.cairo.common.math import unsigned_div_rem as felt_divmod
from starkware.cairo.common.alloc import alloc

const DIV_32 = 2 ** 32;
const DIV_32_MINUS_1 = DIV_32 - 1;

// Returns the number of bits in x.
// Implicits arguments:
// - pow2_array: felt* - A pointer such that pow2_array[i] = 2^i for i in [0, 127].
// Params:
// - x: felt - Input value.
// Assumptions for the caller:
// - 1 <= x < 2^127
// Returns:
// - bit_length: felt - Number of bits in x.
func get_felt_bitlength{range_check_ptr, pow2_array: felt*}(x: felt) -> felt {
    alloc_locals;
    local bit_length;
    %{ ids.bit_length = ids.x.bit_length() %}
    // Computes N=2^bit_length and n=2^(bit_length-1)
    // x is supposed to verify n = 2^(b-1) <= x < N = 2^bit_length <=> x has bit_length bits
    tempvar N = pow2_array[bit_length];
    tempvar n = pow2_array[bit_length - 1];
    assert [range_check_ptr] = bit_length;
    assert [range_check_ptr + 1] = 127 - bit_length;
    assert [range_check_ptr + 2] = N - x - 1;
    assert [range_check_ptr + 3] = x - n;
    tempvar range_check_ptr = range_check_ptr + 4;
    return bit_length;
}

// Computes x//y and x%y.
// Assumption: y must be a power of 2
// params:
//   x: the dividend.
//   y: the divisor.
// returns:
//   q: the quotient.
//   r: the remainder.
func bitwise_divmod{bitwise_ptr: BitwiseBuiltin*}(x: felt, y: felt) -> (q: felt, r: felt) {
    assert bitwise_ptr.x = x;
    assert bitwise_ptr.y = y - 1;
    let x_and_y = bitwise_ptr.x_and_y;

    let bitwise_ptr = bitwise_ptr + BitwiseBuiltin.SIZE;
    return (q=(x - x_and_y) / y, r=x_and_y);
}

// Computes x//(2**32) and x%(2**32) using range checks operations.
// Adapted version of starkware.common.math.unsigned_div_rem with a fixed divisor of 2**32.
// Assumption : value / 2**32 < RC_BOUND
// params:
//   x: the dividend.
// returns:
//   q: the quotient .
//   r: the remainder.
func felt_divmod_2pow32{range_check_ptr}(value: felt) -> (q: felt, r: felt) {
    let r = [range_check_ptr];
    let q = [range_check_ptr + 1];
    %{
        from starkware.cairo.common.math_utils import assert_integer
        assert_integer(ids.DIV_32)
        if not (0 < ids.DIV_32 <= PRIME):
            raise ValueError(f'div={hex(ids.DIV_32)} is out of the valid range.')
    %}
    %{ ids.q, ids.r = divmod(ids.value, ids.DIV_32) %}
    assert [range_check_ptr + 2] = DIV_32_MINUS_1 - r;
    let range_check_ptr = range_check_ptr + 3;

    assert value = q * DIV_32 + r;
    return (q, r);
}

// A function to reverse the endianness of a 8 bytes (64 bits) integer.
// The result will not make sense if word >= 2^64.
// The implementation is directly inspired by the function word_reverse_endian
// from the common library starkware.cairo.common.uint256 with three steps instead of four.
// params:
//   word: the 64 bits integer to reverse.
// returns:
//   res: the reversed integer.
func word_reverse_endian_64{bitwise_ptr: BitwiseBuiltin*}(word: felt) -> (res: felt) {
    // Step 1.
    assert bitwise_ptr[0].x = word;
    assert bitwise_ptr[0].y = 0x00ff00ff00ff00ff;
    tempvar word = word + (2 ** 16 - 1) * bitwise_ptr[0].x_and_y;
    // Step 2.
    assert bitwise_ptr[1].x = word;
    assert bitwise_ptr[1].y = 0x0000ffff0000ffff00;
    tempvar word = word + (2 ** 32 - 1) * bitwise_ptr[1].x_and_y;
    // Step 3.
    assert bitwise_ptr[2].x = word;
    assert bitwise_ptr[2].y = 0x00000000ffffffff000000;
    tempvar word = word + (2 ** 64 - 1) * bitwise_ptr[2].x_and_y;

    let bitwise_ptr = bitwise_ptr + 3 * BitwiseBuiltin.SIZE;
    return (res=word / 2 ** (8 + 16 + 32));
}

// A function to reverse the endianness of a 2 bytes (16 bits) integer using range checks operations.
// Asuumes 0 <= word < 2^16.
// params:
//   word: the 16 bits integer to reverse.
// returns:
//   res: the reversed integer.
func word_reverse_endian_16_RC{range_check_ptr}(word: felt) -> felt {
    %{
        from tools.py.hints import write_word_to_memory
        write_word_to_memory(ids.word, 2, memory, ap)
    %}
    ap += 2;

    let b0 = [ap - 2];
    let b1 = [ap - 1];

    assert [range_check_ptr] = 255 - b0;
    assert [range_check_ptr + 1] = 255 - b1;
    assert [range_check_ptr + 2] = b0;
    assert [range_check_ptr + 3] = b1;

    assert word = b0 * 256 + b1;

    tempvar range_check_ptr = range_check_ptr + 4;
    return b0 + b1 * 256;
}

// A function to reverse the endianness of a 3 bytes (24 bits) integer using range checks operations.
// Asuumes 0 <= word < 2^24.
// params:
//   word: the 24 bits integer to reverse.
// returns:
//   res: the reversed integer.
func word_reverse_endian_24_RC{range_check_ptr}(word: felt) -> felt {
    %{
        from tools.py.hints import write_word_to_memory
        write_word_to_memory(ids.word, 3, memory, ap)
    %}
    ap += 3;

    let b0 = [ap - 3];
    let b1 = [ap - 2];
    let b2 = [ap - 1];

    assert [range_check_ptr] = 255 - b0;
    assert [range_check_ptr + 1] = 255 - b1;
    assert [range_check_ptr + 2] = 255 - b2;
    assert [range_check_ptr + 3] = b0;
    assert [range_check_ptr + 4] = b1;
    assert [range_check_ptr + 5] = b2;

    assert word = b0 * 256 ** 2 + b1 * 256 + b2;

    tempvar range_check_ptr = range_check_ptr + 6;
    return b0 + b1 * 256 + b2 * 256 ** 2;
}

// A function to reverse the endianness of a 4 bytes (32 bits) integer using range checks operations.
// Asuumes 0 <= word < 2^32.
// params:
//   word: the 32 bits integer to reverse.
// returns:
//   res: the reversed integer.
func word_reverse_endian_32_RC{range_check_ptr}(word: felt) -> felt {
    %{
        from tools.py.hints import write_word_to_memory
        write_word_to_memory(ids.word, 4, memory, ap)
    %}
    ap += 4;

    let b0 = [ap - 4];
    let b1 = [ap - 3];
    let b2 = [ap - 2];
    let b3 = [ap - 1];

    assert [range_check_ptr] = 255 - b0;
    assert [range_check_ptr + 1] = 255 - b1;
    assert [range_check_ptr + 2] = 255 - b2;
    assert [range_check_ptr + 3] = 255 - b3;
    assert [range_check_ptr + 4] = b0;
    assert [range_check_ptr + 5] = b1;
    assert [range_check_ptr + 6] = b2;
    assert [range_check_ptr + 7] = b3;

    assert word = b0 * 256 ** 3 + b1 * 256 ** 2 + b2 * 256 + b3;

    tempvar range_check_ptr = range_check_ptr + 8;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3;
}

// A function to reverse the endianness of a 5 bytes (40 bits) integer using range checks operations.
// Asuumes 0 <= word < 2^40.
// params:
//   word: the 40 bits integer to reverse.
// returns:
//   res: the reversed integer.
func word_reverse_endian_40_RC{range_check_ptr}(word: felt) -> felt {
    %{
        from tools.py.hints import write_word_to_memory
        write_word_to_memory(ids.word, 5, memory, ap)
    %}
    ap += 5;

    let b0 = [ap - 5];
    let b1 = [ap - 4];
    let b2 = [ap - 3];
    let b3 = [ap - 2];
    let b4 = [ap - 1];

    assert [range_check_ptr] = 255 - b0;
    assert [range_check_ptr + 1] = 255 - b1;
    assert [range_check_ptr + 2] = 255 - b2;
    assert [range_check_ptr + 3] = 255 - b3;
    assert [range_check_ptr + 4] = 255 - b4;
    assert [range_check_ptr + 5] = b0;
    assert [range_check_ptr + 6] = b1;
    assert [range_check_ptr + 7] = b2;
    assert [range_check_ptr + 8] = b3;
    assert [range_check_ptr + 9] = b4;

    assert word = b0 * 256 ** 4 + b1 * 256 ** 3 + b2 * 256 ** 2 + b3 * 256 + b4;

    tempvar range_check_ptr = range_check_ptr + 10;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3 + b4 * 256 ** 4;
}

// A function to reverse the endianness of a 6 bytes (48 bits) integer using range checks operations.
// Asuumes 0 <= word < 2^48.
// params:
//   word: the 48 bits integer to reverse.
// returns:
//   res: the reversed integer.
func word_reverse_endian_48_RC{range_check_ptr}(word: felt) -> felt {
    %{
        from tools.py.hints import write_word_to_memory
        write_word_to_memory(ids.word, 6, memory, ap)
    %}
    ap += 6;

    let b0 = [ap - 6];
    let b1 = [ap - 5];
    let b2 = [ap - 4];
    let b3 = [ap - 3];
    let b4 = [ap - 2];
    let b5 = [ap - 1];

    assert [range_check_ptr] = 255 - b0;
    assert [range_check_ptr + 1] = 255 - b1;
    assert [range_check_ptr + 2] = 255 - b2;
    assert [range_check_ptr + 3] = 255 - b3;
    assert [range_check_ptr + 4] = 255 - b4;
    assert [range_check_ptr + 5] = 255 - b5;
    assert [range_check_ptr + 6] = b0;
    assert [range_check_ptr + 7] = b1;
    assert [range_check_ptr + 8] = b2;
    assert [range_check_ptr + 9] = b3;
    assert [range_check_ptr + 10] = b4;
    assert [range_check_ptr + 11] = b5;

    assert word = b0 * 256 ** 5 + b1 * 256 ** 4 + b2 * 256 ** 3 + b3 * 256 ** 2 + b4 * 256 + b5;

    tempvar range_check_ptr = range_check_ptr + 12;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3 + b4 * 256 ** 4 + b5 * 256 ** 5;
}

// A function to reverse the endianness of a 7 bytes (56 bits) integer using range checks operations.
// Asuumes 0 <= word < 2^56.
// params:
//   word: the 56 bits integer to reverse.
// returns:
//   res: the reversed integer.
func word_reverse_endian_56_RC{range_check_ptr}(word: felt) -> felt {
    %{
        from tools.py.hints import write_word_to_memory
        write_word_to_memory(ids.word, 7, memory, ap)
    %}
    ap += 7;

    let b0 = [ap - 7];
    let b1 = [ap - 6];
    let b2 = [ap - 5];
    let b3 = [ap - 4];
    let b4 = [ap - 3];
    let b5 = [ap - 2];
    let b6 = [ap - 1];

    assert [range_check_ptr] = 255 - b0;
    assert [range_check_ptr + 1] = 255 - b1;
    assert [range_check_ptr + 2] = 255 - b2;
    assert [range_check_ptr + 3] = 255 - b3;
    assert [range_check_ptr + 4] = 255 - b4;
    assert [range_check_ptr + 5] = 255 - b5;
    assert [range_check_ptr + 6] = 255 - b6;
    assert [range_check_ptr + 7] = b0;
    assert [range_check_ptr + 8] = b1;
    assert [range_check_ptr + 9] = b2;
    assert [range_check_ptr + 10] = b3;
    assert [range_check_ptr + 11] = b4;
    assert [range_check_ptr + 12] = b5;
    assert [range_check_ptr + 13] = b6;

    assert word = b0 * 256 ** 6 + b1 * 256 ** 5 + b2 * 256 ** 4 + b3 * 256 ** 3 + b4 * 256 ** 2 +
        b5 * 256 + b6;

    tempvar range_check_ptr = range_check_ptr + 14;
    return b0 + b1 * 256 + b2 * 256 ** 2 + b3 * 256 ** 3 + b4 * 256 ** 4 + b5 * 256 ** 5 + b6 *
        256 ** 6;
}

// Utility to get a pointer on an array of 2^i from i = 0 to 127.
func pow2alloc127() -> (array: felt*) {
    let (data_address) = get_label_location(data);
    return (data_address,);

    data:
    dw 0x1;
    dw 0x2;
    dw 0x4;
    dw 0x8;
    dw 0x10;
    dw 0x20;
    dw 0x40;
    dw 0x80;
    dw 0x100;
    dw 0x200;
    dw 0x400;
    dw 0x800;
    dw 0x1000;
    dw 0x2000;
    dw 0x4000;
    dw 0x8000;
    dw 0x10000;
    dw 0x20000;
    dw 0x40000;
    dw 0x80000;
    dw 0x100000;
    dw 0x200000;
    dw 0x400000;
    dw 0x800000;
    dw 0x1000000;
    dw 0x2000000;
    dw 0x4000000;
    dw 0x8000000;
    dw 0x10000000;
    dw 0x20000000;
    dw 0x40000000;
    dw 0x80000000;
    dw 0x100000000;
    dw 0x200000000;
    dw 0x400000000;
    dw 0x800000000;
    dw 0x1000000000;
    dw 0x2000000000;
    dw 0x4000000000;
    dw 0x8000000000;
    dw 0x10000000000;
    dw 0x20000000000;
    dw 0x40000000000;
    dw 0x80000000000;
    dw 0x100000000000;
    dw 0x200000000000;
    dw 0x400000000000;
    dw 0x800000000000;
    dw 0x1000000000000;
    dw 0x2000000000000;
    dw 0x4000000000000;
    dw 0x8000000000000;
    dw 0x10000000000000;
    dw 0x20000000000000;
    dw 0x40000000000000;
    dw 0x80000000000000;
    dw 0x100000000000000;
    dw 0x200000000000000;
    dw 0x400000000000000;
    dw 0x800000000000000;
    dw 0x1000000000000000;
    dw 0x2000000000000000;
    dw 0x4000000000000000;
    dw 0x8000000000000000;
    dw 0x10000000000000000;
    dw 0x20000000000000000;
    dw 0x40000000000000000;
    dw 0x80000000000000000;
    dw 0x100000000000000000;
    dw 0x200000000000000000;
    dw 0x400000000000000000;
    dw 0x800000000000000000;
    dw 0x1000000000000000000;
    dw 0x2000000000000000000;
    dw 0x4000000000000000000;
    dw 0x8000000000000000000;
    dw 0x10000000000000000000;
    dw 0x20000000000000000000;
    dw 0x40000000000000000000;
    dw 0x80000000000000000000;
    dw 0x100000000000000000000;
    dw 0x200000000000000000000;
    dw 0x400000000000000000000;
    dw 0x800000000000000000000;
    dw 0x1000000000000000000000;
    dw 0x2000000000000000000000;
    dw 0x4000000000000000000000;
    dw 0x8000000000000000000000;
    dw 0x10000000000000000000000;
    dw 0x20000000000000000000000;
    dw 0x40000000000000000000000;
    dw 0x80000000000000000000000;
    dw 0x100000000000000000000000;
    dw 0x200000000000000000000000;
    dw 0x400000000000000000000000;
    dw 0x800000000000000000000000;
    dw 0x1000000000000000000000000;
    dw 0x2000000000000000000000000;
    dw 0x4000000000000000000000000;
    dw 0x8000000000000000000000000;
    dw 0x10000000000000000000000000;
    dw 0x20000000000000000000000000;
    dw 0x40000000000000000000000000;
    dw 0x80000000000000000000000000;
    dw 0x100000000000000000000000000;
    dw 0x200000000000000000000000000;
    dw 0x400000000000000000000000000;
    dw 0x800000000000000000000000000;
    dw 0x1000000000000000000000000000;
    dw 0x2000000000000000000000000000;
    dw 0x4000000000000000000000000000;
    dw 0x8000000000000000000000000000;
    dw 0x10000000000000000000000000000;
    dw 0x20000000000000000000000000000;
    dw 0x40000000000000000000000000000;
    dw 0x80000000000000000000000000000;
    dw 0x100000000000000000000000000000;
    dw 0x200000000000000000000000000000;
    dw 0x400000000000000000000000000000;
    dw 0x800000000000000000000000000000;
    dw 0x1000000000000000000000000000000;
    dw 0x2000000000000000000000000000000;
    dw 0x4000000000000000000000000000000;
    dw 0x8000000000000000000000000000000;
    dw 0x10000000000000000000000000000000;
    dw 0x20000000000000000000000000000000;
    dw 0x40000000000000000000000000000000;
    dw 0x80000000000000000000000000000000;
}
