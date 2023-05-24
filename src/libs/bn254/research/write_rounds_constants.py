from poseidon_utils import PoseidonParams
from starkware.cairo.common.cairo_secp.secp_utils import split

def write_round_constants():
    p = PoseidonParams.get_default_poseidon_params()
    ark = p.ark
    out="data:\n"
    for i in range(len(ark)):
        out += ';\n'.join("dw " + str(x) for x in split(ark[i][0])) + ';\n'
        out += ';\n'.join("dw " + str(x) for x in split(ark[i][1])) + ';\n'
        out += ';\n'.join("dw " + str(x) for x in split(ark[i][2])) + ';\n'
    return out

print(write_round_constants())
