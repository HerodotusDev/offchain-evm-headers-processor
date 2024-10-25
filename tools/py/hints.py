def write_word_to_memory(word: int, n: int, memory, ap) -> None:
    assert word < 2 ** (8 * n), f"Word value {word} exceeds {8 * n} bits."
    word_bytes = word.to_bytes(n, byteorder="big")
    for i in range(n):
        memory[ap + i] = word_bytes[i]

def print_u256(x, name):
    value = x.low + (x.high << 128)
    print(f"{name} = {hex(value)}")


def write_uint256_array(memory, ptr, array):
    for i, uint in enumerate(array):
        memory[ptr._reference_value + 2 * i] = uint[0]
        memory[ptr._reference_value + 2 * i + 1] = uint[1]


def print_block_header(memory, block_headers_array, bytes_len_array, index):
    rlp_ptr = memory[block_headers_array + index]
    n_bytes = memory[bytes_len_array + index]
    n_felts = -(-n_bytes // 8)  # Equivalent to ceiling division

    rlp_array = [memory[rlp_ptr + i] for i in range(n_felts)]
    rlp_bytes_big_endian = [x.to_bytes(8, "big") for x in rlp_array]
    rlp_bytes_little_endian = [x.to_bytes(8, "little") for x in rlp_array]
    rlp_array_little = [int.from_bytes(b, 'little') for b in rlp_bytes_big_endian]

    print(f"\nBLOCK {index} :: bytes_len={n_bytes} || n_felts={n_felts}")
    print(f"RLP_felt = {rlp_array}")
    print(f"bit_big : {[x.bit_length() for x in rlp_array]}")
    print(f"RLP_bytes_arr_big = {rlp_bytes_big_endian}")
    print(f"RLP_bytes_arr_lil = {rlp_bytes_little_endian}")
    print(f"bit_lil : {[x.bit_length() for x in rlp_array_little]}")


def print_mmr(memory, mmr_array, mmr_array_len):
    mmr_values = [hex(memory[mmr_array + i]) for i in range(mmr_array_len)]
    print(f"\nMMR :: mmr_array_len={mmr_array_len}")
    print(f"mmr_values = {mmr_values}")
