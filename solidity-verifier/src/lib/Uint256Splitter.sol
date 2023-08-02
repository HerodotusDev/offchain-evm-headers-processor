// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Uint256Splitter {
    /// @notice Splits a uint256 into two uint128s (low, high).
    /// @param a The uint256 to split.
    function split128(
        uint256 a
    ) internal pure returns (uint256 lower, uint256 upper) {
        // uint256 mask = (1 << 128) - 1;
        // return (a & mask, a >> 128);
        assembly {
            // sub(exp(2, 128), 1) == 340282366920938463463374607431768211455
            lower := and(a, 340282366920938463463374607431768211455)
            upper := shr(128, a)
        }
    }

    // @notice splits two uint128s (low, high) into one uint256.
    // @param lower The lower uint128.
    // @param upper The upper uint128.
    function merge128(
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256 a) {
        // return (upper << 128) | lower;
        assembly {
            a := or(shl(128, upper), lower)
        }
    }
}
