"""Utility functions."""

def split_128(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def bytes_to_8_bytes_chunks_little(input_bytes):
    # Split the input_bytes into 8-byte chunks
    byte_chunks = [input_bytes[i:i + 8] for i in range(0, len(input_bytes), 8)]

    # Convert each chunk to little-endian integers
    little_endian_ints = [int.from_bytes(chunk, byteorder='little') for chunk in byte_chunks]

    return little_endian_ints

def bytes_to_8_bytes_chunks(input_bytes):
    # Split the input_bytes into 8-byte chunks
    byte_chunks = [input_bytes[i:i + 8] for i in range(0, len(input_bytes), 8)]

    # Convert each chunk to big-endian integers
    big_endian_ints = [int.from_bytes(chunk, byteorder='big') for chunk in byte_chunks]

    return big_endian_ints