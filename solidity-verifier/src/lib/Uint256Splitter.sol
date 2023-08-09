// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Uint256Splitter {
    uint256 constant _MASK = (1 << 128) - 1;

    /// @notice Splits a uint256 into two uint128s (low, high).
    /// @param a The uint256 to split.
    function split128(
        uint256 a
    ) internal pure returns (uint256 lower, uint256 upper) {
        return (a & _MASK, a >> 128);
    }

    /// @notice Splits two uint128s (low, high) into one uint256.
    /// @param lower The lower uint128.
    /// @param upper The upper uint128.
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
