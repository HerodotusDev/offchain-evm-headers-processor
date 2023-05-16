from src.libs.bn254.fq import fq
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.cairo_secp.bigint import BigInt3
from starkware.cairo.common.alloc import alloc

struct PoseidonState {
    s0: BigInt3*,
    s1: BigInt3*,
    s2: BigInt3*,
}

const r_p = 10;
const r_f = 10;

func hash_two{range_check_ptr}(x: BigInt3*, y: BigInt3*) -> BigInt3* {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    local two: BigInt3 = BigInt3(2, 0, 0);
    local state: PoseidonState = PoseidonState(s0=x, s1=y, s2=&two);

    // Hades Permutation
    let half_full: PoseidonState* = hades_round_full(&state, 0, 0);
    let partial: PoseidonState* = hades_round_partial(half_full, r_f, 0);
    let final_state: PoseidonState* = hades_round_full(partial, r_f + r_p, 0);
    let res = final_state.s0;
    return res;
}

func hades_round_full{range_check_ptr}(
    state: PoseidonState*, round_idx: felt, index: felt
) -> PoseidonState* {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    if (index == r_f) {
        return state;
    }

    // 1. Add round constants

    // TODO replace with ark constants
    local ark_constant: BigInt3 = BigInt3(1, 0, 0);

    let state0 = fq.add(state.s0, &ark_constant);
    let state1 = fq.add(state.s1, &ark_constant);
    let state2 = fq.add(state.s2, &ark_constant);

    // 2. Apply sbox
    let square0 = fq.mul(state0, state0);
    let r0 = fq.mul(square0, state0);

    let square1 = fq.mul(state1, state1);
    let r1 = fq.mul(square1, state1);

    let square2 = fq.mul(state2, state2);
    let r2 = fq.mul(square2, state2);

    // 3. Multiply by MDS matrix

    // MixLayer using SmallMds =
    // [3, 1, 1]    [r0]    [3* r0 + r1 + r2 ]
    // [1, -1, 1]  *[r1]  = [r0 - r1 + r2    ]
    // [1, 1, -2]   [r2]    [r0 + r1 - 2 * r2]

    let two_r0 = fq.add(r0, r0);
    let three_r0 = fq.add(two_r0, r0);
    let r1_plus_r2 = fq.add(r1, r2);
    let mds_mul_0 = fq.add(three_r0, r1_plus_r2);

    let r0_min_r1 = fq.sub(r0, r1);
    let mds_mul_1 = fq.add(r0_min_r1, r2);

    let two_r2 = fq.add(r2, r2);
    let r0_plus_r1 = fq.add(r0, r1);
    let mds_mul_2 = fq.sub(r0_plus_r1, two_r2);

    local mds_mul_state: PoseidonState = PoseidonState(s0=mds_mul_0, s1=mds_mul_1, s2=mds_mul_2);
    return hades_round_full(&mds_mul_state, round_idx + 1, index + 1);
}

func hades_round_partial{range_check_ptr}(
    state: PoseidonState*, round_idx: felt, index: felt
) -> PoseidonState* {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    if (index == r_f) {
        return state;
    }

    // 1. Add round constant
    local ark_constant: BigInt3 = BigInt3(1, 0, 0);

    let r0 = fq.add(state.s0, &ark_constant);
    let r1 = fq.add(state.s1, &ark_constant);
    let state2 = fq.add(state.s2, &ark_constant);

    // 2. Apply sbox to last element
    let square2 = fq.mul(state2, state2);
    let r2 = fq.mul(square2, state2);

    // 3. Multiply by MDS matrix
    // MixLayer using SmallMds =
    // [3, 1, 1]    [r0]    [3* r0 + r1 + r2 ]
    // [1, -1, 1]  *[r1]  = [r0 - r1 + r2    ]
    // [1, 1, -2]   [r2]    [r0 + r1 - 2 * r2]

    let two_r0 = fq.add(r0, r0);
    let three_r0 = fq.add(two_r0, r0);
    let r1_plus_r2 = fq.add(r1, r2);
    let mds_mul_0 = fq.add(three_r0, r1_plus_r2);

    let r0_min_r1 = fq.sub(r0, r1);
    let mds_mul_1 = fq.add(r0_min_r1, r2);

    let two_r2 = fq.add(r2, r2);
    let r0_plus_r1 = fq.add(r0, r1);
    let mds_mul_2 = fq.sub(r0_plus_r1, two_r2);

    local mds_mul_state: PoseidonState = PoseidonState(s0=mds_mul_0, s1=mds_mul_1, s2=mds_mul_2);

    return hades_round_partial(&mds_mul_state, round_idx + 1, index + 1);
}
