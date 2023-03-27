from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.uint256 import Uint256, uint256_reverse_endian
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from src.utils import pow2, bitwise_divmod

struct BlockHeaderRLP {
    rlp_bytes_len: felt,
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
        from tools.py.fetch_block_headers import main, build_block_header, bytes_to_little_endian_ints as process_bytes
        import pickle, os, asyncio
        print(f"Building block header from block {ids.from_block_number_high} to {ids.to_block_number_low} ...")
        offline_mode = False
        if offline_mode:
            if not os.path.isfile('src/single_chunk_processor/sample_block_header.pickle'):
                fetch_block_call = asyncio.run(main(ids.from_block_number_high, ids.to_block_number_low))
                block_headers = [build_block_header(block['result']) for block in fetch_block_call]
                block_header_rlp_array = [{"felts":process_bytes(block_header.raw_rlp()), "bytes_len":len(block_header.raw_rlp())} for block_header in block_headers]
                file = open('src/single_chunk_processor/sample_block_header.pickle', 'wb')
                pickle.dump(block_header_rlp_array, file)
                file.close()
            file = open('src/single_chunk_processor/sample_block_header.pickle', 'rb')
            block_header_rlp_array = pickle.load(file)
            file.close()
        else:
            fetch_block_call = asyncio.run(main(ids.from_block_number_high, ids.to_block_number_low))
            block_headers = [build_block_header(block['result']) for block in fetch_block_call]
            block_header_rlp_array = [{"felts":process_bytes(block_header.raw_rlp()), "bytes_len":len(block_header.raw_rlp())} for block_header in block_headers]
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
            # print(f"Feeding block {ids.index}, bytes_len : {block_header_rlp_array[ids.index]['bytes_len']}, n_felt : {len(block_header_rlp_array[ids.index]['felts'])}")
            memory[ids.rlp_array.address_ + ids.index*3] = block_header_rlp_array[ids.index]['bytes_len']
            memory[ids.rlp_array.address_ + ids.index*3 + 1] = len(block_header_rlp_array[ids.index]['felts'])
            segments.write_arg(ids.block_header_rlp, block_header_rlp_array[ids.index]['felts'])
        %}
        assert rlp_array[index].rlp = block_header_rlp;
        return fetch_block_headers_rlp_loop(
            n_blocks_to_fetch=n_blocks_to_fetch, index=index + 1, rlp_array=rlp_array
        );
    }

    return ();
}

// Assumes all words in BlockheaderRLP are 8 bytes little endian values.
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
