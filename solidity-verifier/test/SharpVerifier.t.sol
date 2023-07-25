// SPDX-License-Identifier: MIT
pragma solidity ~0.8.16;

import "forge-std/Test.sol";

import "../src/SharpVerifier.sol";

contract SharpVerifierTest is Test {
    SharpVerifier public sharpVerifier;

    function setUp() public {
        sharpVerifier = new SharpVerifier(
            0xAB43bA48c9edF4C2C4bB01237348D1D7B28ef168,
            0x38477aa3daf83ba977d13af8dd288d76da55cfde05ccfc7ee5438f4c56fb0b6
        );
    }

    function testVerifyInvalidFact() public {
        uint256[] memory outputs = new uint256[](24);
        outputs[0] = 31950254;

        assertFalse(sharpVerifier.verifyFact(outputs));
    }
}
