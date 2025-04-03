use cairo_vm::hint_processor::builtin_hint_processor::builtin_hint_processor_definition::HintProcessorData;
use cairo_vm::types::exec_scope::ExecutionScopes;
use cairo_vm::vm::{errors::hint_errors::HintError, vm_core::VirtualMachine};
use cairo_vm::Felt252;
use eth_essentials_cairo_vm_hints::hints::lib::utils::write::{
    hint_write_2, hint_write_3, hint_write_4, hint_write_5, hint_write_6, hint_write_7,
};
use std::collections::HashMap;

pub const HINT_WRITE_2: &str = "word = ids.word\nassert word < 2**16\nword_bytes=word.to_bytes(2, byteorder='big')\nfor i in range(2):\n    memory[ap+i] = word_bytes[i]";
pub const HINT_WRITE_3: &str = "word = ids.word\nassert word < 2**24\nword_bytes=word.to_bytes(3, byteorder='big')\nfor i in range(3):\n    memory[ap+i] = word_bytes[i]";
pub const HINT_WRITE_4: &str = "word = ids.word\nassert word < 2**32\nword_bytes=word.to_bytes(4, byteorder='big')\nfor i in range(4):\n    memory[ap+i] = word_bytes[i]";
pub const HINT_WRITE_5: &str = "word = ids.word\nassert word < 2**40\nword_bytes=word.to_bytes(5, byteorder='big')\nfor i in range(5):\n    memory[ap+i] = word_bytes[i]";
pub const HINT_WRITE_6: &str = "word = ids.word\nassert word < 2**48\nword_bytes=word.to_bytes(6, byteorder='big')\nfor i in range(6):\n    memory[ap+i] = word_bytes[i]";
pub const HINT_WRITE_7: &str = "word = ids.word\nassert word < 2**56\nword_bytes=word.to_bytes(7, byteorder='big')\nfor i in range(7):\n    memory[ap+i] = word_bytes[i]";

pub fn run_hint(
    vm: &mut VirtualMachine,
    exec_scope: &mut ExecutionScopes,
    hint_data: &HintProcessorData,
    constants: &HashMap<String, Felt252>,
) -> Result<(), HintError> {
    match hint_data.code.as_str() {
        HINT_WRITE_2 => hint_write_2(vm, exec_scope, hint_data, constants),
        HINT_WRITE_3 => hint_write_3(vm, exec_scope, hint_data, constants),
        HINT_WRITE_4 => hint_write_4(vm, exec_scope, hint_data, constants),
        HINT_WRITE_5 => hint_write_5(vm, exec_scope, hint_data, constants),
        HINT_WRITE_6 => hint_write_6(vm, exec_scope, hint_data, constants),
        HINT_WRITE_7 => hint_write_7(vm, exec_scope, hint_data, constants),
        _ => Err(HintError::UnknownHint(
            hint_data.code.to_string().into_boxed_str(),
        )),
    }
}
