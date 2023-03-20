%builtins output pedersen range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts

// from starkware.cairo.common.cairo_keccak.keccak import

from src.merkle_mountain.stateless_mmr import (
    append as mmr_append,
    multi_append as mmr_multi_append,
    verify_proof as mmr_verify_proof,
)
from src.types import Keccak256Hash, Address, IntsSequence, slice_arr
from src.blockheader_rlp_extractor import decode_parent_hash, decode_block_number

struct BlockHeaderRLP {
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    block_header_rlp: felt*,
}
func main{
    output_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() {
    alloc_locals;

    fetch_block_headers_rlp(from_block_number_high=2, to_block_number_low=0);
    return ();
}

func fetch_block_headers_rlp(from_block_number_high: felt, to_block_number_low: felt) -> (
    block_headers_rlp_array: BlockHeaderRLP*
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
        # block_header_rlp_array = [rlp.values for rlp in block_header_rlp_array]
        print(f"BLOCK ARRAY\n {block_header_rlp_array}")
    %}
    fetch_block_headers_rlp_loop(
        n_blocks_to_fetch=from_block_number_high - to_block_number_low + 1,
        index=0,
        rlp_array=block_header_rlp_array,
    );
    return (block_header_rlp_array,);
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
            print(f"index : {ids.index}")
            memory[ids.rlp_array.address_ + ids.index*3] = block_header_rlp_array[ids.index].length
            memory[ids.rlp_array.address_ + ids.index*3 + 1] = len(block_header_rlp_array[ids.index].values)
            print(f"TO WRITE {block_header_rlp_array[ids.index].values}")
            segments.write_arg(ids.block_header_rlp, block_header_rlp_array[ids.index].values)
        %}
        assert rlp_array[index].block_header_rlp = block_header_rlp;
        return fetch_block_headers_rlp_loop(
            n_blocks_to_fetch=n_blocks_to_fetch, index=index + 1, rlp_array=rlp_array
        );
    }

    return ();
}
