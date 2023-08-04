%builtins output range_check bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from src.libs.utils import pow2alloc127, word_reverse_endian_64
from src.libs.block_header import extract_block_number_big

func main{output_ptr: felt*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}() {
    alloc_locals;

    %{
        from tools.py.fetch_block_headers import fetch_blocks_from_rpc_no_async, bytes_to_8_bytes_chunks
        GOERLI = 'goerli'
        MAINNET = 'mainnet'

        NETWORK = MAINNET
        ALCHEMY_RPC = f'https://eth-{NETWORK}.g.alchemy.com/v2/powIIZZbxPDT4bm1SODbzrDH9dE9f_q9'

        if NETWORK == GOERLI:
            RPC_BACKEND_URL = "http://localhost:8545"
        else:
            RPC_BACKEND_URL = ALCHEMY_RPC
    %}
    let (pow2_array: felt*) = pow2alloc127();
    with pow2_array {
        test_batch_block_numbers(from_block_number_high=100, to_block_number_low=0);
        test_batch_block_numbers(from_block_number_high=14173499, to_block_number_low=14173450);
        test_batch_block_numbers(from_block_number_high=17173499, to_block_number_low=17173400);
        test_batch_block_numbers(from_block_number_high=12173499, to_block_number_low=12173400);
        test_batch_block_numbers(from_block_number_high=11173499, to_block_number_low=11173400);
        test_batch_block_numbers(from_block_number_high=10173499, to_block_number_low=10173400);
        test_batch_block_numbers(from_block_number_high=9173499, to_block_number_low=9173400);
    }

    return ();
}

func test_batch_block_numbers{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, pow2_array: felt*}(
    from_block_number_high: felt, to_block_number_low: felt
) {
    alloc_locals;
    let (rlp_arrays: felt**) = alloc();
    let (block_numbers: felt*) = alloc();
    local len: felt;

    %{
        fetch_block_call = fetch_blocks_from_rpc_no_async(ids.from_block_number_high, ids.to_block_number_low-1, ALCHEMY_RPC)
        block_numbers=[block.number for block in fetch_block_call]
        print(f'block_numbers={block_numbers}')
        block_headers_raw_rlp = [block.raw_rlp() for block in fetch_block_call]
        rlp_arrays = [bytes_to_8_bytes_chunks(raw_rlp) for raw_rlp in block_headers_raw_rlp]

        ids.len = len(rlp_arrays)
        segments.write_arg(ids.rlp_arrays, rlp_arrays)
        segments.write_arg(ids.block_numbers, block_numbers)
    %}

    test_batch_block_numbers_inner(
        index=len - 1, rlp_arrays=rlp_arrays, block_numbers=block_numbers
    );
    return ();
}

func test_batch_block_numbers_inner{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, pow2_array: felt*
}(index: felt, rlp_arrays: felt**, block_numbers: felt*) {
    alloc_locals;
    if (index == 0) {
        let bn = extract_block_number_big(rlp_arrays[index]);
        assert bn = block_numbers[index];
        return ();
    } else {
        let bn = extract_block_number_big(rlp_arrays[index]);
        assert bn = block_numbers[index];
        return test_batch_block_numbers_inner(
            index=index - 1, rlp_arrays=rlp_arrays, block_numbers=block_numbers
        );
    }
}
