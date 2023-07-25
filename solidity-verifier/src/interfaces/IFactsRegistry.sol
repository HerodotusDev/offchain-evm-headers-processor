// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFactRegistry {
    function isValid(bytes32 fact) external view returns (bool);
}
