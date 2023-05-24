from starkware.cairo.common.uint256 import SHIFT
from starkware.cairo.common.cairo_secp.bigint import (
    BigInt3,
    bigint_mul,
    UnreducedBigInt5,
    UnreducedBigInt3,
    nondet_bigint3 as nd,
)
from starkware.cairo.common.registers import get_fp_and_pc

// Operations under BN254 Curve Order (Fr)
const N_LIMBS = 3;
const DEGREE = 2;
const BASE = 2 ** 86;

const P0 = 69440356433466637143769089;
const P1 = 27625954992971143715037670;
const P2 = 3656382694611191768777988;

const SHIFT_MIN_BASE = SHIFT - BASE;
const SHIFT_MIN_P2 = SHIFT - P2 - 1;

func fq_zero() -> BigInt3 {
    let res = BigInt3(0, 0, 0);
    return res;
}
func fq_eq_zero(x: BigInt3*) -> felt {
    if (x.d0 != 0) {
        return 0;
    }
    if (x.d1 != 0) {
        return 0;
    }
    if (x.d2 != 0) {
        return 0;
    }
    return 1;
}

namespace fq {
    func add{range_check_ptr}(a: BigInt3*, b: BigInt3*) -> BigInt3* {
        alloc_locals;
        local add_mod_p: BigInt3*;
        %{
            from starkware.cairo.common.cairo_secp.secp_utils import pack, split
            p = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
            a = pack(ids.a, p)
            b = pack(ids.b, p)
            add_mod_p = value = (a+b)%p

            ids.add_mod_p = segments.gen_arg(split(value))
        %}
        return add_mod_p;
    }
    func sub{range_check_ptr}(a: BigInt3*, b: BigInt3*) -> BigInt3* {
        alloc_locals;
        local sub_mod_p: BigInt3*;
        %{
            from starkware.cairo.common.cairo_secp.secp_utils import pack, split
            p = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
            a = pack(ids.a, p)
            b = pack(ids.b, p)
            sub_mod_p = value = (a-b)%p

            ids.sub_mod_p = segments.gen_arg(split(value))
        %}
        return sub_mod_p;
    }
    func mul{range_check_ptr}(a: BigInt3*, b: BigInt3*) -> BigInt3* {
        alloc_locals;
        local result: BigInt3*;
        %{
            from starkware.cairo.common.cairo_secp.secp_utils import split
            p = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
            mul = (ids.a.d0 + ids.a.d1*2**86 + ids.a.d2*2**172) * (ids.b.d0 + ids.b.d1*2**86 + ids.b.d2*2**172)
            value = mul%p

            ids.result = segments.gen_arg(split(value))
        %}

        return result;
    }
    func inv{range_check_ptr}(a: BigInt3*) -> BigInt3* {
        alloc_locals;
        let (__fp__, _) = get_fp_and_pc();
        local inv: BigInt3;
        %{
            from starkware.cairo.common.math_utils import as_int    
            assert 1 < ids.N_LIMBS <= 12
            assert ids.DEGREE == ids.N_LIMBS-1
            a,p=0,0

            def split(x, degree=ids.DEGREE, base=ids.BASE):
                coeffs = []
                for n in range(degree, 0, -1):
                    q, r = divmod(x, base ** n)
                    coeffs.append(q)
                    x = r
                coeffs.append(x)
                return coeffs[::-1]

            for i in range(ids.N_LIMBS):
                a+=as_int(getattr(ids.a, 'd'+str(i)), PRIME) * ids.BASE**i
                p+=getattr(ids, 'P'+str(i)) * ids.BASE**i

            inv = pow(a, -1, p)
            invs = split(inv)
            for i in range(ids.N_LIMBS):
                setattr(ids.inv, 'd'+str(i), invs[i])
        %}
        // let (inv) = nondet_bigint3();
        assert [range_check_ptr] = inv.d0 + (SHIFT_MIN_BASE);
        assert [range_check_ptr + 1] = inv.d1 + (SHIFT_MIN_BASE);
        assert [range_check_ptr + 2] = inv.d2 + (SHIFT_MIN_P2);
        tempvar range_check_ptr = range_check_ptr + 3;
        let x_x_inv = mul(a, &inv);

        assert x_x_inv.d0 = 1;
        assert x_x_inv.d1 = 0;
        assert x_x_inv.d2 = 0;
        return &inv;
    }
}
