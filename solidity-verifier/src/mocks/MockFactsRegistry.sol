// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFactsRegistry} from "../interfaces/IFactsRegistry.sol";

contract MockedSharpFactsRegistry is IFactsRegistry {
    mapping(bytes32 => bool) public isValid;

    function setValid(bytes32 fact) external {
        isValid[fact] = true;
    }
}
