%builtins output pedersen range_check bitwise keccak

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, HashBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_felts

func main{
    output_ptr: felt*,
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() {
    alloc_locals;
    %{
        def bin_c(u):
            b=bin(u)
            f = b[0:10] + ' ' + b[10:19] + '...' + b[-16:-8] + ' ' + b[-8:]
            return f
        def bin_64(u):
            b=bin(u)
            little = '0b'+b[2:][::-1]
            f='0b'+' '.join([b[2:][i:i+64] for i in range(0, len(b[2:]), 64)])
            return f
        def bin_8(u):
            b=bin(u)
            little = '0b'+b[2:][::-1]
            f="0b"+' '.join([little[2:][i:i+8] for i in range(0, len(little[2:]), 8)])
            return f

        def print_u_256_info(u, un):
            u = u.low + (u.high << 128) 
            print(f" {un}_{u.bit_length()}bits = {bin_c(u)}")
            print(f" {un} = {hex(u)}")
            print(f" {un} = {int.to_bytes(u, 32, 'big')}")

        def print_felt_info(u, un):
            print(f" {un}_{u.bit_length()}bits = {bin_8(u)}")
            print(f" {un} = {u}")
    %}

    // Initalize keccak and validate RLP value for block n-1 :
    let (inputs: felt*) = alloc();
    local inputs_start: felt* = inputs;
    assert inputs[0] = 22482800004818542010000;
    assert inputs[1] = 7375015890835569791;
    assert inputs[2] = 11401577666402859883;
    assert inputs[3] = 11336311909656352177;
    assert inputs[4] = 5605888209646827737;
    assert inputs[5] = 13080049234815213288;
    assert inputs[6] = 4977272650390615655;
    assert inputs[7] = 4801382644103943195;
    assert inputs[8] = 163035143749885;
    assert inputs[9] = 0;
    assert inputs[10] = 0;
    assert inputs[11] = 9643858734092386304;
    assert inputs[12] = 17852884839230749927;
    assert inputs[13] = 9645891743231943554;
    assert inputs[14] = 5417141523214730916;
    assert inputs[15] = 1666305845900095627;
    assert inputs[16] = 16592813536147000347;
    assert inputs[17] = 2008684991348261010;
    assert inputs[18] = 13055761604437437593;
    assert inputs[19] = 2299182855532864483;
    assert inputs[20] = 5009128300435217175;
    assert inputs[21] = 16161267794996925158;
    assert inputs[22] = 3414293394555181339;
    assert inputs[23] = 485029388215221;
    assert inputs[24] = 0;
    assert inputs[25] = 0;
    assert inputs[26] = 0;
    assert inputs[27] = 0;
    assert inputs[28] = 0;
    assert inputs[29] = 0;
    assert inputs[30] = 0;
    assert inputs[31] = 0;
    assert inputs[32] = 0;
    assert inputs[33] = 0;
    assert inputs[34] = 0;
    assert inputs[35] = 0;
    assert inputs[36] = 0;
    assert inputs[37] = 0;
    assert inputs[38] = 0;
    assert inputs[39] = 0;
    assert inputs[40] = 0;
    assert inputs[41] = 0;
    assert inputs[42] = 0;
    assert inputs[43] = 0;
    assert inputs[44] = 0;
    assert inputs[45] = 0;
    assert inputs[46] = 0;
    assert inputs[47] = 0;
    assert inputs[48] = 0;
    assert inputs[49] = 0;
    assert inputs[50] = 0;
    assert inputs[51] = 0;
    assert inputs[52] = 0;
    assert inputs[53] = 0;
    assert inputs[54] = 0;
    assert inputs[55] = 0;
    assert inputs[56] = 9547633239926178050;
    assert inputs[57] = 7012212066963379036;
    assert inputs[58] = 7162223280856000882;
    assert inputs[59] = 8245924292131364968;
    assert inputs[60] = 7959657;
    assert inputs[61] = 13775103885242793984;
    assert inputs[62] = 5110833539423756680;
    assert inputs[63] = 4604120093677386467;
    assert inputs[64] = 12071926577914212588;
    assert inputs[65] = 7517129480367145134;
    assert inputs[66] = 3899449925160273487;
    assert inputs[67] = 2739674484027914802;
    assert inputs[68] = 15289469360717210084;
    assert inputs[69] = 11529578379562769643;
    assert inputs[70] = 0;
    assert inputs[71] = 0;
    assert inputs[72] = 0;
    assert inputs[73] = 0;
    assert inputs[74] = 136;
    assert inputs[75] = 0;
    let (hash: Uint256) = keccak(inputs=inputs, n_bytes=601);

    %{ print_u_256_info(ids.hash,'hash') %}

    return ();
}
