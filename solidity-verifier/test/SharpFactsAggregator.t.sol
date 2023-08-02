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
        sharpFactsAggregator = new SharpFactsAggregator();

        sharpFactsAggregator.initialize(
            0xAB43bA48c9edF4C2C4bB01237348D1D7B28ef168,
            0x38477aa3daf83ba977d13af8dd288d76da55cfde05ccfc7ee5438f4c56fb0b6
        );
    }

    function testVerifyInvalidFact() public {
        uint256[] memory outputs = new uint256[](24);
        outputs[0] = 31950254;

        assertFalse(sharpFactsAggregator.verifyFact(outputs));
    }

    function testSimpleAggregateThreeBlocks() public {
        uint256 startChildBlock = block.number; // Rightmost block's child block number
        uint256 blocksConfirmations = 100;

        uint256 r = 3; // Range size (mmr elements to include)
        uint256 blockRightBound = startChildBlock - blocksConfirmations - 1; // Rightmost block included in the proving range
        uint256 blockLeftBound = blockRightBound - r + 1; // Leftmost block included in the proving range

        sharpFactsAggregator.registerNewRange(blocksConfirmations);

        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            ,
            bytes32 mostRecentParentHash,

        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        assert(mostRecentParentHash == blockhash(blockRightBound));

        SharpFactsAggregator.JobOutputPacked[]
            memory outputs = new SharpFactsAggregator.JobOutputPacked[](2);

        uint256 mmrSizesPacked = Uint256Splitter.merge128(mmrSize, mmrSize + 7);
        // Highest range (first job)
        outputs[0] = (
            SharpFactsAggregator.JobOutputPacked({
                blockNPlusOneParentHash: mostRecentParentHash,
                blockNMinusRPlusOneParentHash: blockhash(blockLeftBound - 1),
                mmrPreviousRootPoseidon: poseidonMmrRoot,
                mmrPreviousRootKeccak: keccakMmrRoot,
                mmrNewRootPoseidon: bytes32(uint256(101010)), // Fake
                mmrNewRootKeccak: bytes32(uint256(11111)), // Fake
                mmrSizesPacked: mmrSizesPacked // Previous and next tree sizes (packed)
            })
        );

        mmrSizesPacked = Uint256Splitter.merge128(mmrSize + 7, mmrSize + 7 + 7);
        // Lowest range (second job)
        outputs[1] = (
            SharpFactsAggregator.JobOutputPacked({
                blockNPlusOneParentHash: outputs[0]
                    .blockNMinusRPlusOneParentHash,
                blockNMinusRPlusOneParentHash: blockhash(
                    blockLeftBound - r - 1
                ),
                mmrPreviousRootPoseidon: outputs[0].mmrNewRootPoseidon,
                mmrPreviousRootKeccak: outputs[0].mmrNewRootKeccak,
                mmrNewRootPoseidon: bytes32(uint256(101010)), // Fake
                mmrNewRootKeccak: bytes32(uint256(11111)), // Fake
                mmrSizesPacked: mmrSizesPacked // Previous and next tree sizes (packed)
            })
        );

        sharpFactsAggregator.aggregateSharpJobs(
            block.number - blocksConfirmations,
            outputs
        );
    }
}
