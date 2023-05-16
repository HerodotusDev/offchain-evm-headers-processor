from src.libs.bn254.fq import fq
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.cairo_secp.bigint import BigInt3
from starkware.cairo.common.alloc import alloc

// TODO :
// Add round constants. Put python script used in gnark mmr in tools/py/poseidon.
// Implement poseidon hash using fq as emulated field.

struct Params {
    r: felt,
    c: felt,
    m: felt,
    r_f: felt,
    r_p: felt,
    n_rounds: felt,
    output_size: felt,
    mds: BigInt3**,
    ark: BigInt3**,
}

func hash_two{range_check_ptr}(x: BigInt3, y: BigInt3, params: Params) -> BigInt3 {
    alloc_locals;

    let (local state: BigInt3*) = alloc();

    assert state[0] = x;
    assert state[1] = y;
    assert state[2] = BigInt3(0, 0, 2);

    let res = hades_permutation(3, state, params);

    return res[0];
}

func hades_permutation{range_check_ptr}(state_len: felt, state: BigInt3*, params: Params) -> BigInt3* {
    alloc_locals;

    let half_full = apply_full_rounds(state_len, state, params, 0, params.r_f / 2);
    let partial = apply_partial_rounds(state_len, half_full, params, params.r_f / 2, params.r_p);
    let res = apply_full_rounds(state_len, partial, params, params.r_f / 2 + params.r_p, params.r_f / 2);

    return res;
}

func apply_full_rounds{range_check_ptr}(state_len: felt, state: BigInt3*, params: Params, round_idx: felt, rounds: felt) -> BigInt3* {
    alloc_locals;

    if (round_idx == rounds) {
        return state;
    }

    let full_round_state = hades_round_full(state_len, state, params, round_idx);

    return apply_full_rounds(state_len, full_round_state, params, round_idx + 1, rounds);
}

func apply_partial_rounds{range_check_ptr}(state_len: felt, state: BigInt3*, params: Params, round_idx: felt, rounds: felt) -> BigInt3* {
    alloc_locals;

    if (round_idx == rounds) {
        return state;
    }

    let full_round_state = hades_round_full(state_len, state, params, round_idx);

    return apply_partial_rounds(state_len, full_round_state, params, round_idx + 1, rounds);
}

func hades_round_full{range_check_ptr}(state_len: felt, state: BigInt3*, params: Params, round_idx: felt) -> BigInt3* {
    alloc_locals;

    let constant_add_state = add_round_constant(state_len, state, params.ark, round_idx);

    let sbox_state = apply_sbox(state_len, constant_add_state);

    let mds_state = multiply_mds(state_len, state, params.mds);

    return mds_state;
}

func hades_round_partial{range_check_ptr}(state_len: felt, state: BigInt3*, params: Params, round_idx: felt) -> BigInt3* {
    alloc_locals;

    // todo : add round constants

    let sbox_state = apply_sbox_last(state_len, state);

    let mds_state = multiply_mds(state_len, state, params.mds);

    return mds_state;
}

func add_round_constant{range_check_ptr}(state_len: felt, state: BigInt3*, ark: BigInt3**, round_idx: felt) -> BigInt3* {
    alloc_locals;

    let (local new_state: BigInt3*) = alloc();

    return add_round_constant_rec(state_len, state, new_state, ark, round_idx, 0);
}

func add_round_constant_rec{range_check_ptr}(state_len: felt, state: BigInt3*, new_state: BigInt3*, ark: BigInt3**, round_idx: felt, index: felt) -> BigInt3* {
    alloc_locals;

    if (index == state_len) {
        return new_state;
    }

    let addition = fq.add(&state[index], &ark[round_idx][index]);
    assert new_state[index] = [addition];

    return add_round_constant_rec(state_len, state, new_state, ark, round_idx, index + 1);
}

// Cubic function
func apply_sbox{range_check_ptr}(state_len: felt, state: BigInt3*) -> BigInt3* {
    alloc_locals;

    let (local new_state: BigInt3*) = alloc();

    return apply_sbox_rec(state_len, state, 0, new_state);
}

func apply_sbox_rec{range_check_ptr}(state_len: felt, state: BigInt3*, index: felt, new_state: BigInt3*) -> BigInt3* {

    if (index == state_len) {
        return new_state;
    }

    let square = fq.mul(&state[index], &state[index]);
    let cubic = fq.mul(square, &state[index]);
    assert new_state[index] = [cubic];

    return apply_sbox_rec(state_len, state, index + 1, new_state);
}

func apply_sbox_last{range_check_ptr}(state_len: felt, state: BigInt3*) -> BigInt3* {
    alloc_locals;

    let (local new_state: BigInt3*) = alloc();

    return apply_sbox_last_rec(state_len, state, 0, new_state);
}

func apply_sbox_last_rec{range_check_ptr}(state_len: felt, state: BigInt3*, index: felt, new_state: BigInt3*) -> BigInt3* {

    if (index == state_len - 1) {
        let square = fq.mul(&state[index], &state[index]);
        let cubic = fq.mul(square, &state[index]);
        assert new_state[index] = [cubic];

        return new_state;
    } else {
        return apply_sbox_last_rec(state_len, state, index + 1, new_state);
    }
}

func multiply_mds{range_check_ptr}(state_len: felt, state: BigInt3*, mds: BigInt3**) -> BigInt3* {
    alloc_locals;

    let (local new_state: BigInt3*) = alloc();

    return multiply_mds_rec(state_len, state, new_state, mds, 0, 0);
}

func multiply_mds_rec{range_check_ptr}(state_len: felt, state: BigInt3*, new_state: BigInt3*, mds: BigInt3**, i: felt, j: felt) -> BigInt3* {
    alloc_locals;
    if (i == state_len) {
        return new_state;
    }

    let product = fq.mul(&mds[i][j], &state[j]);
    let addition = fq.add(&new_state[i], product);
    assert new_state[i] = [addition];

    if (j+1 == state_len) {
        return multiply_mds_rec(state_len, state, new_state, mds, i + 1, 0);
    } else {
        return multiply_mds_rec(state_len, state, new_state, mds, i, j + 1);
    }
}
