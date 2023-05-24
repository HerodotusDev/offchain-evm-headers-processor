from src.libs.bn254.research.poseidon_utils import PoseidonParams

DEGREE = 2
BASE = 2 ** 86

def split(x, degree=DEGREE, base=BASE):
    coeffs = []
    for n in range(degree, 0, -1):
        q, r = divmod(x, base ** n)
        coeffs.append(q)
        x = r
    coeffs.append(x)
    return coeffs[::-1]

def write_round_constants():
    p = PoseidonParams.get_default_poseidon_params()
    ark = p.ark
    out="data:\n"
    for i in range(2):
        out += ';\n'.join("dw " + str(x) for x in split(ark[i][0])) + ';\n'
        out += ';\n'.join("dw " + str(x) for x in split(ark[i][1])) + ';\n'
        out += ';\n'.join("dw " + str(x) for x in split(ark[i][2])) + ';\n'
    return out

print(write_round_constants())
out = write_round_constants()
p = PoseidonParams.get_default_poseidon_params()
ark = p.ark