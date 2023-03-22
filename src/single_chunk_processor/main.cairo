%builtins output pedersen range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.builtin_keccak.keccak import keccak_uint256s_bigend

from src.merkle_mountain.stateless_mmr import (
    append as mmr_append,
    multi_append as mmr_multi_append,
    verify_proof as mmr_verify_proof,
)
from src.types import Keccak256Hash, Address, IntsSequence, slice_arr
from src.blockheader_rlp_extractor import decode_parent_hash, decode_block_number

from src.single_chunk_processor.block_header_rlp import (
    BlockHeaderRLP,
    fetch_block_headers_rlp,
    extract_parent_hash,
)

func main{
    output_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}() {
    alloc_locals;
    local mmr_last_pos: felt;
    local mmr_last_root: felt;
    %{
        ids.mmr_last_pos=program_input['mmr_last_pos'] 
        ids.mmr_last_root=program_input['mmr_last_root']
    %}

    // Load all BlockHeaderRLP structs from API call into a BlockHeaderRLP array:
    let (
        block_header_rlp_array: BlockHeaderRLP*, block_header_rlp_len: felt
    ) = fetch_block_headers_rlp(from_block_number_high=5, to_block_number_low=0);

    // Store the first parent hash into a specific Cairo variable to be returned as ouput of the Cairo program:
    let (block_n_parent_hash: Uint256) = extract_parent_hash(block_header_rlp_array[0]);

    // Initalize keccak and validate RLP value for block n-1 :
    let (local keccak_ptr: felt*) = alloc();
    let keccak_ptr_start = keccak_ptr;

    // Validate chain of RLP values for block [n-2; n-r]:

    // Returns private input as public output, as well as output of interest.
    // NOTE : block_n_parent_hash is critical to be returned and checked against a correct checkpoint on Starknet.
    // Otherwise, the prover could cheat and feed RLP values that are sound together, but not necessearily
    // the exact requested ones from the Ethereum blockchain.

    [ap] = mmr_last_pos;
    [ap] = [output_ptr], ap++;

    [ap] = mmr_last_root;
    [ap] = [output_ptr + 1], ap++;

    [ap] = block_n_parent_hash.low;
    [ap] = [output_ptr + 2], ap++;

    [ap] = block_n_parent_hash.high;
    [ap] = [output_ptr + 3], ap++;

    [ap] = output_ptr + 4, ap++;
    let output_ptr = output_ptr + 4;

    return ();
}
