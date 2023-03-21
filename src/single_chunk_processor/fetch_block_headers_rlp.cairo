from starkware.cairo.common.alloc import alloc

struct BlockHeaderRLP {
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    block_header_rlp: felt*,
}

func fetch_block_headers_rlp(from_block_number_high: felt, to_block_number_low: felt) -> (
    block_header_rlp_array: BlockHeaderRLP*, block_header_rlp_array_len
) {
    alloc_locals;
    let (block_header_rlp_array: BlockHeaderRLP*) = alloc();
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
        assert rlp_array[index].block_header_rlp = block_header_rlp;
        return fetch_block_headers_rlp_loop(
            n_blocks_to_fetch=n_blocks_to_fetch, index=index + 1, rlp_array=rlp_array
        );
    }

    return ();
}
