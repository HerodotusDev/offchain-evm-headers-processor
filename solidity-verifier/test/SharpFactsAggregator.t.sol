// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/SharpFactsAggregator.sol";
import "../src/lib/Uint256Splitter.sol";

contract SharpFactsAggregatorTest is Test {
    using Uint256Splitter for uint256;

    SharpFactsAggregator public sharpFactsAggregator;

    function setUp() public {
        sharpFactsAggregator = new SharpFactsAggregator(
            0xAB43bA48c9edF4C2C4bB01237348D1D7B28ef168,
            0x38477aa3daf83ba977d13af8dd288d76da55cfde05ccfc7ee5438f4c56fb0b6
        );
    }

    function testVerifyInvalidFact() public {
        uint256[] memory outputs = new uint256[](24);
        outputs[0] = 31950254;

        assertFalse(sharpFactsAggregator.verifyFact(outputs));
    }

    function testInitialize() public {
        sharpFactsAggregator.initialize(100); // Start from past 100th block

        (
            bytes32 currentMmrRoot,
            uint256 currentMmrSize,
            bytes32 mostRecentParentHash,
            bytes32 oldestParentHash
        ) = sharpFactsAggregator.aggregatorState();

        console.logBytes32(currentMmrRoot);
        console.logUint(currentMmrSize);
        console.logBytes32(mostRecentParentHash);
        console.logBytes32(oldestParentHash);

        bytes32 expectedHash = blockhash(block.number - 100);
        assertEq(mostRecentParentHash, expectedHash);
        assertEq(oldestParentHash, expectedHash);
    }

    function testSimpleAggregateThreeBlocks() public {
        uint256 startChildBlock = block.number; // Rightmost block's child block number

        uint256 r = 3; // Range size (mmr elements to include)
        uint256 blockRightBound = startChildBlock - 1; // Rightmost block included in the proving range
        uint256 blockLeftBound = blockRightBound - r + 1; // Leftmost block included in the proving range

        sharpFactsAggregator.initialize(1); // Start from startChildBlock.parentHash

        (
            bytes32 currentMmrRoot,
            uint256 currentMmrSize,
            bytes32 mostRecentParentHash,

        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        assert(mostRecentParentHash == blockhash(blockRightBound));

        SharpFactsAggregator.JobOutputPacked[]
            memory outputs = new SharpFactsAggregator.JobOutputPacked[](2);

        uint256 mmrSizesPacked = Uint256Splitter.merge128(
            currentMmrSize,
            currentMmrSize + 7
        );
        // Highest range (first job)
        outputs[0] = (
            SharpFactsAggregator.JobOutputPacked({
                blockNPlusOneParentHash: mostRecentParentHash,
                blockNMinusRPlusOneParentHash: blockhash(blockLeftBound - 1),
                mmrPreviousRoot: currentMmrRoot,
                mmrNewRoot: bytes32(uint256(101010)), // Fake root,
                mmrSizesPacked: mmrSizesPacked // Previous and next tree sizes (packed)
            })
        );

        mmrSizesPacked = Uint256Splitter.merge128(
            currentMmrSize + 7,
            currentMmrSize + 7 + 7
        );
        // Lowest range (second job)
        outputs[1] = (
            SharpFactsAggregator.JobOutputPacked({
                blockNPlusOneParentHash: outputs[0]
                    .blockNMinusRPlusOneParentHash,
                blockNMinusRPlusOneParentHash: blockhash(
                    blockLeftBound - r - 1
                ),
                mmrPreviousRoot: outputs[0].mmrNewRoot,
                mmrNewRoot: bytes32(uint256(202020)), // Fake root,
                mmrSizesPacked: mmrSizesPacked // Previous and next tree sizes (packed)
            })
        );

        sharpFactsAggregator.aggregateSharpJobs(outputs);
    }
}
