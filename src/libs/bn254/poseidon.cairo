from src.libs.bn254.fq import fq
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.cairo_secp.bigint import BigInt3

// TODO :
// Add round constants. Put python script used in gnark mmr in tools/py/poseidon.
// Implement poseidon hash using fq as emulated field.
