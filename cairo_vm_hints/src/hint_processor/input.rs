use super::CustomHintProcessor;
use cairo_vm::hint_processor::builtin_hint_processor::hint_utils::get_ptr_from_var_name;
use cairo_vm::types::relocatable::MaybeRelocatable;
use cairo_vm::{
    hint_processor::builtin_hint_processor::builtin_hint_processor_definition::HintProcessorData,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use eth_essentials_cairo_vm_hints::utils;
use std::collections::HashMap;

pub const HINT_INPUT: &str = "ids.from_block_number_high=program_input['from_block_number_high']\nids.to_block_number_low=program_input['to_block_number_low']\nids.mmr_offset=program_input['mmr_last_len'] \nids.mmr_last_root_poseidon=program_input['mmr_last_root_poseidon']\nids.mmr_last_root_keccak.low=program_input['mmr_last_root_keccak_low']\nids.mmr_last_root_keccak.high=program_input['mmr_last_root_keccak_high']\nids.block_n_plus_one_parent_hash_little.low = program_input['block_n_plus_one_parent_hash_little_low']\nids.block_n_plus_one_parent_hash_little.high = program_input['block_n_plus_one_parent_hash_little_high']";
pub const HINT_INPUT_PREV: &str = "from tools.py.hints import write_uint256_array\nsegments.write_arg(ids.previous_peaks_values_poseidon, program_input['poseidon_mmr_last_peaks']) \nwrite_uint256_array(memory, ids.previous_peaks_values_keccak, program_input['keccak_mmr_last_peaks'])";
pub const HINT_INPUT_BLOCK_HEADERS: &str = "block_headers_array = program_input['block_headers_array']\nbytes_len_array = program_input['bytes_len_array']\nsegments.write_arg(ids.block_headers_array, block_headers_array)\nsegments.write_arg(ids.block_headers_array_bytes_len, bytes_len_array)";

impl CustomHintProcessor {
    pub fn hint_input(
        &mut self,
        vm: &mut VirtualMachine,
        _exec_scope: &mut ExecutionScopes,
        hint_data: &HintProcessorData,
        _constants: &HashMap<String, Felt252>,
    ) -> Result<(), HintError> {
        let from_block_number_high: Felt252 =
            serde_json::from_value(self.private_inputs["from_block_number_high"].clone())
                .unwrap_or_default();
        let to_block_number_low: Felt252 =
            serde_json::from_value(self.private_inputs["to_block_number_low"].clone())
                .unwrap_or_default();
        let mmr_offset: Felt252 =
            serde_json::from_value(self.private_inputs["mmr_last_len"].clone()).unwrap_or_default();
        let mmr_last_root_poseidon: Felt252 =
            serde_json::from_value(self.private_inputs["mmr_last_root_poseidon"].clone())
                .unwrap_or_default();
        let mmr_last_root_keccak_low: Felt252 =
            serde_json::from_value(self.private_inputs["mmr_last_root_keccak_low"].clone())
                .unwrap_or_default();
        let mmr_last_root_keccak_high: Felt252 =
            serde_json::from_value(self.private_inputs["mmr_last_root_keccak_high"].clone())
                .unwrap_or_default();
        let block_n_plus_one_parent_hash_little_low: Felt252 = serde_json::from_value(
            self.private_inputs["block_n_plus_one_parent_hash_little_low"].clone(),
        )
        .unwrap_or_default();
        let block_n_plus_one_parent_hash_little_high: Felt252 = serde_json::from_value(
            self.private_inputs["block_n_plus_one_parent_hash_little_high"].clone(),
        )
        .unwrap_or_default();

        utils::write_value(
            "from_block_number_high",
            MaybeRelocatable::Int(from_block_number_high),
            vm,
            hint_data,
        )?;
        utils::write_value(
            "to_block_number_low",
            MaybeRelocatable::Int(to_block_number_low),
            vm,
            hint_data,
        )?;
        utils::write_value(
            "mmr_offset",
            MaybeRelocatable::Int(mmr_offset),
            vm,
            hint_data,
        )?;
        utils::write_value(
            "mmr_last_root_poseidon",
            MaybeRelocatable::Int(mmr_last_root_poseidon),
            vm,
            hint_data,
        )?;
        utils::write_value(
            "mmr_last_root_poseidon",
            MaybeRelocatable::Int(mmr_last_root_poseidon),
            vm,
            hint_data,
        )?;
        utils::write_struct(
            "mmr_last_root_keccak",
            &[mmr_last_root_keccak_low, mmr_last_root_keccak_high]
                .into_iter()
                .map(MaybeRelocatable::Int)
                .collect::<Vec<_>>(),
            vm,
            hint_data,
        )?;
        utils::write_struct(
            "block_n_plus_one_parent_hash_little",
            &[
                block_n_plus_one_parent_hash_little_low,
                block_n_plus_one_parent_hash_little_high,
            ]
            .into_iter()
            .map(MaybeRelocatable::Int)
            .collect::<Vec<_>>(),
            vm,
            hint_data,
        )?;

        Ok(())
    }

    pub fn hint_input_prev(
        &mut self,
        vm: &mut VirtualMachine,
        _exec_scope: &mut ExecutionScopes,
        hint_data: &HintProcessorData,
        _constants: &HashMap<String, Felt252>,
    ) -> Result<(), HintError> {
        let poseidon_mmr_last_peaks: Vec<Felt252> =
            serde_json::from_value(self.private_inputs["poseidon_mmr_last_peaks"].clone()).unwrap();

        let keccak_mmr_last_peaks: Vec<Vec<Felt252>> =
            serde_json::from_value(self.private_inputs["keccak_mmr_last_peaks"].clone()).unwrap();

        let previous_peaks_values_poseidon_ptr = get_ptr_from_var_name(
            "previous_peaks_values_poseidon",
            vm,
            &hint_data.ids_data,
            &hint_data.ap_tracking,
        )?;

        let previous_peaks_values_keccak_ptr = get_ptr_from_var_name(
            "previous_peaks_values_keccak",
            vm,
            &hint_data.ids_data,
            &hint_data.ap_tracking,
        )?;

        for (j, value) in poseidon_mmr_last_peaks
            .into_iter()
            .map(MaybeRelocatable::Int)
            .enumerate()
        {
            vm.insert_value((previous_peaks_values_poseidon_ptr + j)?, &value)?;
        }

        for (j, array) in keccak_mmr_last_peaks.into_iter().flatten().enumerate() {
            vm.insert_value((previous_peaks_values_keccak_ptr + j)?, array)?;
        }

        Ok(())
    }

    pub fn hint_input_block_headers(
        &mut self,
        vm: &mut VirtualMachine,
        _exec_scope: &mut ExecutionScopes,
        hint_data: &HintProcessorData,
        _constants: &HashMap<String, Felt252>,
    ) -> Result<(), HintError> {
        let block_headers_array: Vec<Vec<Felt252>> =
            serde_json::from_value(self.private_inputs["block_headers_array"].clone()).unwrap();

        let bytes_len_array: Vec<Felt252> =
            serde_json::from_value(self.private_inputs["bytes_len_array"].clone()).unwrap();

        let block_headers_array_ptr = get_ptr_from_var_name(
            "block_headers_array",
            vm,
            &hint_data.ids_data,
            &hint_data.ap_tracking,
        )?;

        let block_headers_array_bytes_len_ptr = get_ptr_from_var_name(
            "block_headers_array_bytes_len",
            vm,
            &hint_data.ids_data,
            &hint_data.ap_tracking,
        )?;

        for (j, array) in block_headers_array.into_iter().enumerate() {
            let segment = vm.segments.add();
            for (k, value) in array.into_iter().map(MaybeRelocatable::Int).enumerate() {
                vm.insert_value((segment + k)?, &value)?;
            }
            vm.insert_value((block_headers_array_ptr + j)?, segment)?;
        }

        for (j, value) in bytes_len_array
            .into_iter()
            .map(MaybeRelocatable::Int)
            .enumerate()
        {
            vm.insert_value((block_headers_array_bytes_len_ptr + j)?, &value)?;
        }

        Ok(())
    }
}
