from src.libs.bn254.fq import fq
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.cairo_secp.bigint import BigInt3
from starkware.cairo.common.alloc import alloc

const r_p = 10;
const r_f = 10;

func hash_two{range_check_ptr}(x: BigInt3, y: BigInt3) -> BigInt3 {
    alloc_locals;

    let (local state: BigInt3*) = alloc();

    assert state[0] = x;
    assert state[1] = y;
    assert state[2] = BigInt3(0, 0, 2);

    // Hades Permutation
    let half_full = hades_round_full(state, 0, 0);
    let partial = hades_round_partial(half_full, r_f, 0);
    let res = hades_round_full(partial, r_f+r_p, 0);

    return res[0];
}

func hades_round_full{range_check_ptr}(state: BigInt3*, round_idx: felt, index: felt) -> BigInt3* {
    alloc_locals; 
    let (__fp__, _) = get_fp_and_pc();

    if (index == r_f) {
        return state;
    }

    // 1. Add round constant
    let (local constant_state: BigInt3*) = alloc();

    // TODO replace with ark constants
    local ark_constant: BigInt3 = BigInt3(0, 0, 1);

    let state0 = fq.add(&state[0], &ark_constant);
    assert constant_state[0] = [state0];

    let state1 = fq.add(&state[1], &ark_constant);
    assert constant_state[1] = [state1];

    let state2 = fq.add(&state[2], &ark_constant);
    assert constant_state[2] = [state2];

    // 2. Apply sbox
    let (local sbox_state: BigInt3*) = alloc();

    let square0 = fq.mul(&constant_state[0], &constant_state[0]);
    let cubic0 = fq.mul(square0, &constant_state[0]);
    assert sbox_state[0] = [cubic0];

    let square1 = fq.mul(&constant_state[1], &constant_state[1]);
    let cubic1 = fq.mul(square1, &constant_state[1]);
    assert sbox_state[1] = [cubic1];

    let square2 = fq.mul(&constant_state[2], &constant_state[2]);
    let cubic2 = fq.mul(square2, &constant_state[2]);
    assert sbox_state[2] = [cubic2];

    // 3. Multiply by MDS matrix
    let (local mds_mul_state: BigInt3*) = alloc();
    // MixLayer using SmallMds =
	// [3, 1, 1]    [r0]    [3* r0 + r1 + r2 ]
	// [1, -1, 1]  *[r1]  = [r0 - r1 + r2    ]
	// [1, 1, -2]   [r2]    [r0 + r1 - 2 * r2]

    let two_r0 = fq.add(&sbox_state[0], &sbox_state[0]);
    let three_r0 = fq.add(two_r0, &sbox_state[0]);
    let r1_plus_r2 = fq.add(&sbox_state[1], &sbox_state[2]);
    let mds_mul_0 = fq.add(three_r0, r1_plus_r2);
    assert mds_mul_state[0] = [mds_mul_0];

    let r0_min_r1 = fq.sub(&sbox_state[0], &sbox_state[1]);
    let mds_mul_1 = fq.add(r0_min_r1, &sbox_state[2]);
    assert mds_mul_state[1] = [mds_mul_1];

    let two_r2 = fq.add(&sbox_state[2], &sbox_state[2]);
    let r0_plus_r1 = fq.add(&sbox_state[0], &sbox_state[1]);
    let mds_mul_2 = fq.sub(r0_plus_r1, two_r2);
    assert mds_mul_state[2] = [mds_mul_2];

    return hades_round_full(mds_mul_state, round_idx + 1, index + 1);
}

func hades_round_partial{range_check_ptr}(state: BigInt3*, round_idx: felt, index: felt) -> BigInt3* {
    alloc_locals; 
    let (__fp__, _) = get_fp_and_pc();

    if (index == r_f) {
        return state;
    }

    // 1. Add round constant
    let (local constant_state: BigInt3*) = alloc();

    // TODO replace with ark constants
    local ark_constant: BigInt3 = BigInt3(0, 0, 1);

    let state0 = fq.add(&state[0], &ark_constant);
    assert constant_state[0] = [state0];

    let state1 = fq.add(&state[1], &ark_constant);
    assert constant_state[1] = [state1];

    let state2 = fq.add(&state[2], &ark_constant);
    assert constant_state[2] = [state2];

    // 2. Apply sbox to last element
    let (local sbox_state: BigInt3*) = alloc();
    let square2 = fq.mul(&constant_state[2], &constant_state[2]);
    let cubic2 = fq.mul(square2, &constant_state[2]);
    assert sbox_state[2] = [cubic2];

    // 3. Multiply by MDS matrix
    let (local mds_mul_state: BigInt3*) = alloc();
    // MixLayer using SmallMds =
	// [3, 1, 1]    [r0]    [3* r0 + r1 + r2 ]
	// [1, -1, 1]  *[r1]  = [r0 - r1 + r2    ]
	// [1, 1, -2]   [r2]    [r0 + r1 - 2 * r2]

    let two_r0 = fq.add(&sbox_state[0], &sbox_state[0]);
    let three_r0 = fq.add(two_r0, &sbox_state[0]);
    let r1_plus_r2 = fq.add(&sbox_state[1], &sbox_state[2]);
    let mds_mul_0 = fq.add(three_r0, r1_plus_r2);
    assert mds_mul_state[0] = [mds_mul_0];

    let r0_min_r1 = fq.sub(&sbox_state[0], &sbox_state[1]);
    let mds_mul_1 = fq.add(r0_min_r1, &sbox_state[2]);
    assert mds_mul_state[1] = [mds_mul_1];

    let two_r2 = fq.add(&sbox_state[2], &sbox_state[2]);
    let r0_plus_r1 = fq.add(&sbox_state[0], &sbox_state[1]);
    let mds_mul_2 = fq.sub(r0_plus_r1, two_r2);
    assert mds_mul_state[2] = [mds_mul_2];

    return hades_round_partial(mds_mul_state, round_idx + 1, index + 1);
}
