pub mod input;

use crate::hints;
use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::builtin_hint_processor_definition::{
            BuiltinHintProcessor, HintFunc, HintProcessorData,
        },
        hint_processor_definition::HintExtension,
        hint_processor_definition::HintProcessorLogic,
    },
    types::exec_scope::ExecutionScopes,
    vm::{
        errors::hint_errors::HintError, runners::cairo_runner::ResourceTracker,
        vm_core::VirtualMachine,
    },
    Felt252,
};
use starknet_types_core::felt::Felt;
use std::collections::HashMap;
use std::{any::Any, rc::Rc};

use num_bigint::BigUint;
use serde_json::Value;
use std::str::FromStr;

#[derive(Default)]
pub struct CustomHintProcessor {
    pub private_inputs: serde_json::Value,
}

impl CustomHintProcessor {
    pub fn new(private_inputs: serde_json::Value) -> Self {
        Self { private_inputs }
    }

    pub fn run_hint(
        &mut self,
        vm: &mut VirtualMachine,
        exec_scope: &mut ExecutionScopes,
        hint_data: &HintProcessorData,
        constants: &HashMap<String, Felt252>,
    ) -> Result<(), HintError> {
        match hint_data.code.as_str() {
            input::HINT_INPUT_BLOCK_HEADERS => {
                self.hint_input_block_headers(vm, exec_scope, hint_data, constants)
            }
            input::HINT_INPUT => self.hint_input(vm, exec_scope, hint_data, constants),
            input::HINT_INPUT_PREV => self.hint_input_prev(vm, exec_scope, hint_data, constants),
            _ => Err(HintError::UnknownHint(
                hint_data.code.to_string().into_boxed_str(),
            )),
        }
    }
}

impl HintProcessorLogic for CustomHintProcessor {
    fn execute_hint(
        &mut self,
        vm: &mut VirtualMachine,
        exec_scopes: &mut ExecutionScopes,
        hint_data: &Box<dyn Any>,
        constants: &HashMap<String, Felt252>,
    ) -> Result<(), HintError> {
        let hint_data = hint_data
            .downcast_ref::<HintProcessorData>()
            .ok_or(HintError::WrongHintData)?;

        let res =
            eth_essentials_cairo_vm_hints::hints::run_hint(vm, exec_scopes, hint_data, constants);
        if !matches!(res, Err(HintError::UnknownHint(_))) {
            return res;
        }

        let res = hints::run_hint(vm, exec_scopes, hint_data, constants);
        if !matches!(res, Err(HintError::UnknownHint(_))) {
            return res;
        }

        self.run_hint(vm, exec_scopes, hint_data, constants)
    }
}

impl ResourceTracker for CustomHintProcessor {}

pub struct ExtendedHintProcessor {
    custom_hint_processor: CustomHintProcessor,
    builtin_hint_processor: BuiltinHintProcessor,
}

impl Default for ExtendedHintProcessor {
    fn default() -> Self {
        Self::new(serde_json::Value::default())
    }
}

impl ExtendedHintProcessor {
    fn prepare_inputs(value: Value) -> Value {
        match value.clone() {
            Value::Number(n) => {
                // Check if it's a valid number and if it's a big number
                if let Ok(big_num) = BigUint::from_str(n.as_str()) {
                    // Convert the big number to hexadecimal with '0x' prefix
                    Value::String(format!("0x{:X}", big_num))
                } else {
                    value // If it can't be converted to BigUint, return as is
                }
            }
            Value::Array(arr) => {
                // Recursively convert all items in the array
                Value::Array(arr.into_iter().map(Self::prepare_inputs).collect())
            }
            Value::Object(map) => {
                // Recursively convert all key-value pairs in the object
                Value::Object(
                    map.into_iter()
                        .map(|(k, v)| (k, Self::prepare_inputs(v)))
                        .collect(),
                )
            }
            _ => value, // Return other types (like String, Bool) as is
        }
    }

    pub fn new(private_inputs: serde_json::Value) -> Self {
        // Convert all decimal numbers to hexadecimal - support for python inputs format
        let private_inputs = Self::prepare_inputs(private_inputs);
        Self {
            custom_hint_processor: CustomHintProcessor { private_inputs },
            builtin_hint_processor: BuiltinHintProcessor::new_empty(),
        }
    }

    pub fn add_hint(&mut self, hint_code: String, hint_func: Rc<HintFunc>) {
        self.builtin_hint_processor
            .extra_hints
            .insert(hint_code, hint_func);
    }
}

impl HintProcessorLogic for ExtendedHintProcessor {
    fn execute_hint(
        &mut self,
        _vm: &mut VirtualMachine,
        _exec_scopes: &mut ExecutionScopes,
        _hint_data: &Box<dyn Any>,
        _constants: &HashMap<String, Felt>,
    ) -> Result<(), HintError> {
        unreachable!();
    }

    fn execute_hint_extensive(
        &mut self,
        vm: &mut VirtualMachine,
        exec_scopes: &mut ExecutionScopes,
        hint_data: &Box<dyn Any>,
        constants: &HashMap<String, Felt>,
    ) -> Result<HintExtension, HintError> {
        match self.custom_hint_processor.execute_hint_extensive(
            vm,
            exec_scopes,
            hint_data,
            constants,
        ) {
            Err(HintError::UnknownHint(_)) => {}
            result => {
                return result;
            }
        }

        self.builtin_hint_processor
            .execute_hint_extensive(vm, exec_scopes, hint_data, constants)
    }
}

impl ResourceTracker for ExtendedHintProcessor {}
