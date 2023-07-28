%builtins output range_check bitwise keccak poseidon

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, KeccakBuiltin
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.hash_state import hash_felts
from starkware.cairo.common.uint256 import Uint256

from starkware.cairo.common.builtin_keccak.keccak import keccak
from starkware.cairo.common.keccak_utils.keccak_utils import keccak_add_felts
from src.libs.mmr import (
    compute_height_pre_alloc_pow2,
    compute_first_peak_pos,
    compute_peaks_positions,
    bag_peaks,
)
from src.libs.utils import pow2alloc127

func main{
    output_ptr: felt*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}() {
    alloc_locals;
    local n;
    let (true_pos: felt*) = alloc();
    local true_first_pos: felt;
    %{
        import random
        from tools.py.mmr import get_peaks

        n=random.randint(1, 20000000)
        n=3
        ids.n=n;
        peak_pos = [x+1 for x in get_peaks(n)]
        print("peak_pos", peak_pos)
        print("mmr_size", n)
        ids.true_first_pos = peak_pos[0]
        segments.write_arg(ids.true_pos, peak_pos)
    %}
    let pow2_array: felt* = pow2alloc127();
    with pow2_array {
        let first_peak_pos = compute_first_peak_pos(n);
        %{ print(f"first peak pos cairo : {ids.first_peak_pos}") %}
        let (peaks: felt*, peaks_len: felt) = compute_peaks_positions(n);
    }
    %{ print(f"peaks_len cairo : {ids.peaks_len}") %}

    assert first_peak_pos = true_first_pos;
    assert_array_rec(true_pos, peaks, peaks_len - 1);

    test_bag_peaks();
    return ();
}

func assert_array_rec(x: felt*, y: felt*, index: felt) {
    if (index == 0) {
        assert x[0] = y[0];
        return ();
    } else {
        assert x[index] = y[index];
        return assert_array_rec(x, y, index - 1);
    }
}

func test_bag_peaks{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}() {
    alloc_locals;
    let (peaks_poseidon: felt*) = alloc();
    let (local peaks_keccak: Uint256*) = alloc();

    local expected_bagged_poseidon: felt;
    local expected_bagged_keccak: Uint256;
    local peaks_len: felt;

    %{
        import sha3
        import random
        from tools.py.poseidon.poseidon_hash import poseidon_hash
        # random.seed(1)
        p = 3618502788666131213697322783095070105623107215331596699973092056135872020481
        n_peaks = 2 
        def split_128(a):
            """Takes in value, returns uint256-ish tuple."""
            return [a & ((1 << 128) - 1), a >> 128]
        def bag_peaks_poseidon(peaks:list):
            bags = peaks[-1]
            for peak in reversed(peaks[:-1]):
                bags = poseidon_hash(peak, bags)
            return bags
        def bag_peaks_keccak(peaks:list):
            k = sha3.keccak_256()
            bags = peaks[-1]
            for peak in reversed(peaks[:-1]):
                k = sha3.keccak_256()
                k.update(peak.to_bytes(32, "big") + bags.to_bytes(32, "big"))
                bags = int.from_bytes(k.digest(), "big")
            return bags

        def write_uint256_array(ptr, array):
            counter = 0
            for uint in array:
                memory[ptr._reference_value+counter] = uint[0]
                memory[ptr._reference_value+counter+1] = uint[1]
                counter += 2
        peaks_poseidon = [random.randint(0, p-1) for _ in range(n_peaks)]
        peaks_keccak = [random.randint(0, 2**256-1) for _ in range(n_peaks)]
        peaks_keccak_split = [split_128(x) for x in peaks_keccak]

        print(peaks_keccak_split)
        segments.write_arg(ids.peaks_poseidon, peaks_poseidon)

        write_uint256_array(ids.peaks_keccak, peaks_keccak_split)


        ids.peaks_len = n_peaks
        ids.expected_bagged_poseidon = bag_peaks_poseidon(peaks_poseidon)
        bagged_peak_keccak_split= split_128(bag_peaks_keccak(peaks_keccak))
        ids.expected_bagged_keccak.low = bagged_peak_keccak_split[0]
        ids.expected_bagged_keccak.high = bagged_peak_keccak_split[1]
    %}

    tempvar a = peaks_keccak[0].low;
    tempvar b = peaks_keccak[0].high;

    %{ print("a", ids.a) %}
    %{ print("b", ids.b) %}

    let (bag_peaks_poseidon, bag_peaks_keccak) = bag_peaks(peaks_poseidon, peaks_keccak, peaks_len);

    assert bag_peaks_poseidon = expected_bagged_poseidon;
    assert bag_peaks_keccak.low = expected_bagged_keccak.low;
    assert bag_peaks_keccak.high = expected_bagged_keccak.high;

    return ();
}
