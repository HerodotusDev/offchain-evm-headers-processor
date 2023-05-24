from src.libs.bn254.poseidon import BigInt3, hash_two
from src.libs.bn254.fq import BASE, DEGREE
from starkware.cairo.common.registers import get_fp_and_pc

func main{range_check_ptr}() {
    alloc_locals;
    let (__fp__, _) = get_fp_and_pc();

    %{
        from src.libs.bn254.research.poseidon_hash import poseidon_hash
        import random
        p = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001
        def print_bigint3(x, name):
            print(f"{name} = {x.d0 + x.d1*2**86 + x.d2*2**172}")
        def split(x, degree=ids.DEGREE, base=ids.BASE):
            coeffs = []
            for n in range(degree, 0, -1):
                q, r = divmod(x, base ** n)
                coeffs.append(q)
                x = r
            coeffs.append(x)
            return coeffs[::-1]
        def fill_bigint3(x, coeffs):
            x.d0 = coeffs[0]
            x.d1 = coeffs[1]
            x.d2 = coeffs[2]
    %}
    local x: BigInt3;
    local y: BigInt3;
    local true_res: BigInt3;

    %{
        x = random.randint(0, p)
        y = random.randint(0, p)
        true_res = split(poseidon_hash(x, y))
        xs = split(x)
        ys = split(y)
        fill_bigint3(ids.x, xs)
        fill_bigint3(ids.y, ys)
        fill_bigint3(ids.true_res, true_res)
    %}

    let z = hash_two(&x, &y);

    assert z.d0 = true_res.d0;
    assert z.d1 = true_res.d1;
    assert z.d2 = true_res.d2;

    return ();
}
