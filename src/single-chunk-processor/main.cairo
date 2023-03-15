%builtins output pedersen range_check ecdsa bitwise ec_op

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts

// from starkware.cairo.common.cairo_keccak.keccak import

from src.cairo_mmr.stateless_mmr import (
    append as mmr_append,
    multi_append as mmr_multi_append,
    verify_proof as mmr_verify_proof,
)
from src.types import Keccak256Hash, Address, IntsSequence, slice_arr
from src.blockheader_rlp_extractor import decode_parent_hash, decode_block_number

func main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    ecdsa_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    ec_op_ptr,
}() {
    alloc_locals;
    local mmr_last_pos: felt;
    local mmr_last_root: felt;
    %{
        ids.mmr_last_pos=program_input['mmr_last_pos'] 
        ids.mmr_last_root=program_input['mmr_last_root']
        print(ids.mmr_last_pos)
        print(ids.mmr_last_root)
    %}

    // Returns private input as public output
    [ap] = mmr_last_pos;
    [ap] = [output_ptr], ap++;

    [ap] = mmr_last_root;
    [ap] = [output_ptr + 1], ap++;

    [ap] = output_ptr + 2, ap++;
    let output_ptr = output_ptr + 2;

    // Return the new value of output_ptr, which was advanced
    // by 3.

    return ();
}

func process_block{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, bitwise_ptr: BitwiseBuiltin*, range_check_ptr
}(
    reference_block_number: felt,
    reference_proof_leaf_index: felt,
    reference_proof_leaf_value: felt,
    reference_proof_len: felt,
    reference_proof: felt*,
    reference_header_rlp_bytes_len: felt,
    reference_header_rlp_len: felt,
    reference_header_rlp: felt*,
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    block_header_rlp: felt*,
    mmr_peaks_len: felt,
    mmr_peaks: felt*,
    mmr_last_pos: felt,
    mmr_last_root: felt,
) {
    alloc_locals;
    validate_parent_block_and_proof_integrity(
        reference_proof_leaf_index,
        reference_proof_leaf_value,
        reference_proof_len,
        reference_proof,
        mmr_peaks_len,
        mmr_peaks,
        reference_header_rlp_bytes_len,
        reference_header_rlp_len,
        reference_header_rlp,
        block_header_rlp_bytes_len,
        block_header_rlp_len,
        block_header_rlp,
        mmr_last_pos,
        mmr_last_root,
    );

    update_mmr(
        block_header_rlp_bytes_len,
        block_header_rlp_len,
        block_header_rlp,
        mmr_peaks_len,
        mmr_peaks,
        mmr_last_pos,
        mmr_last_root,
    );
    return ();
}

func validate_parent_block_and_proof_integrity{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, bitwise_ptr: BitwiseBuiltin*, range_check_ptr
}(
    reference_proof_leaf_index: felt,
    reference_proof_leaf_value: felt,
    reference_proof_len: felt,
    reference_proof: felt*,
    mmr_peaks_len: felt,
    mmr_peaks: felt*,
    reference_header_rlp_bytes_len: felt,
    reference_header_rlp_len: felt,
    reference_header_rlp: felt*,
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    block_header_rlp: felt*,
    mmr_pos: felt,
    mmr_root: felt,
) {
    alloc_locals;

    mmr_verify_proof(
        index=reference_proof_leaf_index,
        value=reference_proof_leaf_value,
        proof_len=reference_proof_len,
        proof=reference_proof,
        peaks_len=mmr_peaks_len,
        peaks=mmr_peaks,
        pos=mmr_pos,
        root=mmr_root,
    );

    local rlp: IntsSequence = IntsSequence(
        reference_header_rlp, reference_header_rlp_len, reference_header_rlp_bytes_len
        );
    let (local child_block_parent_hash: Keccak256Hash) = decode_parent_hash(rlp);
    validate_provided_header_rlp(
        child_block_parent_hash, block_header_rlp_bytes_len, block_header_rlp_len, block_header_rlp
    );

    let (pedersen_hash_reference_block) = hash_felts{hash_ptr=pedersen_ptr}(
        data=reference_header_rlp, length=reference_header_rlp_len
    );

    assert pedersen_hash_reference_block = reference_proof_leaf_value;
    return ();
}

func update_mmr{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, bitwise_ptr: BitwiseBuiltin*, range_check_ptr
}(
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    block_header_rlp: felt*,
    mmr_peaks_len: felt,
    mmr_peaks: felt*,
    mmr_last_pos: felt,
    mmr_last_root: felt,
) -> (last_pos: felt, last_root: felt) {
    alloc_locals;

    let (pedersen_hash) = hash_felts{hash_ptr=pedersen_ptr}(
        data=block_header_rlp, length=block_header_rlp_len
    );
    let (new_pos, new_root) = mmr_append(
        elem=pedersen_hash,
        peaks_len=mmr_peaks_len,
        peaks=mmr_peaks,
        last_pos=mmr_last_pos,
        last_root=mmr_last_root,
    );

    emit_mmr_update_event(
        block_header_rlp_bytes_len, block_header_rlp_len, block_header_rlp, pedersen_hash
    );
    // Update contract storage

    // _mmr_last_pos.write(new_pos);
    // _mmr_root.write(new_root);
    // _tree_size_to_root.write(new_pos, new_root);

    return (last_pos=new_pos, last_root=new_root);
}
func emit_mmr_update_event{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, bitwise_ptr: BitwiseBuiltin*, range_check_ptr
}(
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    block_header_rlp: felt*,
    pedersen_hash: felt,
) {
    alloc_locals;

    // let (local keccak_ptr: felt*) = alloc();
    // let keccak_ptr_start = keccak_ptr;

    // local header_ints_sequence: IntsSequence = IntsSequence(
    //     block_header_rlp, block_header_rlp_len, block_header_rlp_bytes_len
    //     );
    // let (local processed_block_number: felt) = decode_block_number(header_ints_sequence);

    // let (local keccak_hash) = keccak256{keccak_ptr=keccak_ptr}(header_ints_sequence);

    // local word_1 = keccak_hash[0];
    // local word_2 = keccak_hash[1];
    // local word_3 = keccak_hash[2];
    // local word_4 = keccak_hash[3];

    // let (local update_id) = _latest_accumulator_update_id.read();
    // _latest_accumulator_update_id.write(update_id + 1);
    // // Emit the update event
    // accumulator_update.emit(
    //     pedersen_hash, processed_block_number, word_1, word_2, word_3, word_4, update_id
    // );
    return ();
}
func validate_provided_header_rlp{
    pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, bitwise_ptr: BitwiseBuiltin*, range_check_ptr
}(
    child_block_parent_hash: Keccak256Hash,
    block_header_rlp_bytes_len: felt,
    block_header_rlp_len: felt,
    block_header_rlp: felt*,
) {
    alloc_locals;
    local bitwise_ptr: BitwiseBuiltin* = bitwise_ptr;
    let (local keccak_ptr: felt*) = alloc();
    local keccak_ptr_start: felt* = keccak_ptr;

    local header_ints_sequence: IntsSequence = IntsSequence(
        block_header_rlp, block_header_rlp_len, block_header_rlp_bytes_len
        );

    // let (provided_rlp_hash) = keccak256{keccak_ptr=keccak_ptr}(header_ints_sequence);
    // finalize_keccak(keccak_ptr_start, keccak_ptr)

    // Ensure child block parenthash matches provided rlp hash
    // assert child_block_parent_hash.word_1 = provided_rlp_hash[0];
    // assert child_block_parent_hash.word_2 = provided_rlp_hash[1];
    // assert child_block_parent_hash.word_3 = provided_rlp_hash[2];
    // assert child_block_parent_hash.word_4 = provided_rlp_hash[3];
    return ();
}
