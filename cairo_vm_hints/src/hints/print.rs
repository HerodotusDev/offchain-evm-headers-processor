use cairo_vm::hint_processor::builtin_hint_processor::builtin_hint_processor_definition::HintProcessorData;
use cairo_vm::hint_processor::builtin_hint_processor::hint_utils::{
    get_integer_from_var_name, get_relocatable_from_var_name,
};
use cairo_vm::types::exec_scope::ExecutionScopes;
use cairo_vm::vm::{errors::hint_errors::HintError, vm_core::VirtualMachine};
use cairo_vm::Felt252;
use std::collections::HashMap;

const HINT_PRINT_HASH: &str = "print(\"\\n\")\nprint_u256(ids.block_header_hash_little,f\"block_header_keccak_hash_{ids.index}\")\nprint_u256(ids.expected_block_hash,f\"expected_keccak_hash_{ids.index}\")";
const HINT_PRINT_FINAL: &str = "print(\"new root poseidon\", ids.new_mmr_root_poseidon)\nprint(\"new root keccak\", ids.new_mmr_root_keccak.low, ids.new_mmr_root_keccak.high)\nprint(\"new size\", ids.mmr_array_len + ids.mmr_offset)";

fn hint_print_hash(
    vm: &mut VirtualMachine,
    _exec_scope: &mut ExecutionScopes,
    hint_data: &HintProcessorData,
    _constants: &HashMap<String, Felt252>,
) -> Result<(), HintError> {
    let index =
        get_integer_from_var_name("index", vm, &hint_data.ids_data, &hint_data.ap_tracking)?;

    let block_header_hash_little = get_relocatable_from_var_name(
        "block_header_hash_little",
        vm,
        &hint_data.ids_data,
        &hint_data.ap_tracking,
    )?;

    let expected_block_hash = get_relocatable_from_var_name(
        "expected_block_hash",
        vm,
        &hint_data.ids_data,
        &hint_data.ap_tracking,
    )?;

    let block_header_hash_little = vm
        .get_continuous_range(block_header_hash_little, 2)?
        .into_iter()
        .map(|v| v.get_int())
        .collect::<Option<Vec<Felt252>>>()
        .unwrap();
    println!(
        "block_header_hash_little_{}, {} {}",
        index, block_header_hash_little[0], block_header_hash_little[1]
    );

    let expected_block_hash = vm
        .get_continuous_range(expected_block_hash, 2)?
        .into_iter()
        .map(|v| v.get_int())
        .collect::<Option<Vec<Felt252>>>()
        .unwrap();
    println!(
        "expected_block_hash_{}, {} {}",
        index, expected_block_hash[0], expected_block_hash[1]
    );

    Ok(())
}

fn hint_print_final(
    vm: &mut VirtualMachine,
    _exec_scope: &mut ExecutionScopes,
    hint_data: &HintProcessorData,
    _constants: &HashMap<String, Felt252>,
) -> Result<(), HintError> {
    let new_mmr_root_poseidon = get_integer_from_var_name(
        "new_mmr_root_poseidon",
        vm,
        &hint_data.ids_data,
        &hint_data.ap_tracking,
    )?;

    let new_mmr_root_keccak = get_relocatable_from_var_name(
        "new_mmr_root_keccak",
        vm,
        &hint_data.ids_data,
        &hint_data.ap_tracking,
    )?;

    let mmr_array_len = get_integer_from_var_name(
        "mmr_array_len",
        vm,
        &hint_data.ids_data,
        &hint_data.ap_tracking,
    )?;

    let mmr_offset = get_integer_from_var_name(
        "mmr_offset",
        vm,
        &hint_data.ids_data,
        &hint_data.ap_tracking,
    )?;

    println!("new root poseidon: {}", new_mmr_root_poseidon);

    let new_mmr_root_keccak = vm
        .get_continuous_range(new_mmr_root_keccak, 2)?
        .into_iter()
        .map(|v| v.get_int())
        .collect::<Option<Vec<Felt252>>>()
        .unwrap();
    println!(
        "new root keccak: {} {}",
        new_mmr_root_keccak[0], new_mmr_root_keccak[1]
    );

    println!("new size: {}", mmr_array_len + mmr_offset);

    Ok(())
}

pub fn run_hint(
    vm: &mut VirtualMachine,
    exec_scope: &mut ExecutionScopes,
    hint_data: &HintProcessorData,
    constants: &HashMap<String, Felt252>,
) -> Result<(), HintError> {
    match hint_data.code.as_str() {
        HINT_PRINT_HASH => hint_print_hash(vm, exec_scope, hint_data, constants),
        HINT_PRINT_FINAL => hint_print_final(vm, exec_scope, hint_data, constants),
        _ => Err(HintError::UnknownHint(
            hint_data.code.to_string().into_boxed_str(),
        )),
    }
}
