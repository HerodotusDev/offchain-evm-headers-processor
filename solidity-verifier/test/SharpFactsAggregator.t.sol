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
            0x273de4c1c69594e2234858d9cb39ccf107a5754d3dc98f0760c82efaa919891
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

    // Test to be ran on Goërli fork with option --fork-block-number 9433325
    function testRealAggregate() public {
        uint256 startChildBlock = block.number; // Rightmost block's child block number
        uint256 blocksConfirmations = 20;

        uint256 blockRightBound = startChildBlock - blocksConfirmations - 1; // Rightmost block included in the proving range

        sharpFactsAggregator.registerNewRange(blocksConfirmations);

        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            ,
            bytes32 mostRecentParentHash,

        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        assert(mmrSize == 1); // New tree, with genesis element "brave new world" only
        assert(mostRecentParentHash == blockhash(blockRightBound));

        bytes32 output0BlockNPlusOneParentHash = bytes32(
            Uint256Splitter.merge128(
                136280817012297242619553763422457190740,
                230845892776573197306270179585336099707
            )
        );
        assert(mostRecentParentHash == output0BlockNPlusOneParentHash);

        SharpFactsAggregator.JobOutputPacked[]
            memory outputs = new SharpFactsAggregator.JobOutputPacked[](2);

        // output[0]:
        // {
        //     "block_n_plus_one_parent_hash_low": 136280817012297242619553763422457190740,
        //     "block_n_plus_one_parent_hash_high": 230845892776573197306270179585336099707,
        //     "block_n_minus_r_plus_one_parent_hash_low": 3481649350075648672177608527441112449,
        //     "block_n_minus_r_plus_one_parent_hash_high": 105863212581884754852829743559155307897,
        //     "mmr_last_root_poseidon": 968420142673072399148736368629862114747721166432438466378474074601992041181,
        //     "mmr_last_root_keccak_low": 276995023885003891229929879792300175720,
        //     "mmr_last_root_keccak_high": 274583190961786771627148608652935610924,
        //     "mmr_last_len": 1,
        //     "new_mmr_root_poseidon": 2979921579743029844311702091292349139366985913887733325731342704997480991156,
        //     "new_mmr_root_keccak_low": 35156908954301055531592827141631060830,
        //     "new_mmr_root_keccak_high": 164501793725413761694418296230187300434,
        //     "new_mmr_len": 10
        // }
        outputs[0] = (
            SharpFactsAggregator.JobOutputPacked({
                blockNPlusOneParentHash: output0BlockNPlusOneParentHash,
                blockNMinusRPlusOneParentHash: bytes32(
                    Uint256Splitter.merge128(
                        3481649350075648672177608527441112449,
                        105863212581884754852829743559155307897
                    )
                ),
                mmrPreviousRootPoseidon: poseidonMmrRoot,
                mmrPreviousRootKeccak: keccakMmrRoot,
                mmrNewRootPoseidon: bytes32(
                    uint256(
                        2979921579743029844311702091292349139366985913887733325731342704997480991156
                    )
                ),
                mmrNewRootKeccak: bytes32(
                    Uint256Splitter.merge128(
                        35156908954301055531592827141631060830,
                        164501793725413761694418296230187300434
                    )
                ),
                mmrSizesPacked: Uint256Splitter.merge128(mmrSize, 10)
            })
        );

        // output[1]:
        // {
        //     "block_n_plus_one_parent_hash_low": 3481649350075648672177608527441112449,
        //     "block_n_plus_one_parent_hash_high": 105863212581884754852829743559155307897,
        //     "block_n_minus_r_plus_one_parent_hash_low": 274298540468991391430554661646020544970,
        //     "block_n_minus_r_plus_one_parent_hash_high": 286982477857871647409769742511439137417,
        //     "mmr_last_root_poseidon": 2979921579743029844311702091292349139366985913887733325731342704997480991156,
        //     "mmr_last_root_keccak_low": 35156908954301055531592827141631060830,
        //     "mmr_last_root_keccak_high": 164501793725413761694418296230187300434,
        //     "mmr_last_len": 10,
        //     "new_mmr_root_poseidon": 2418312068954869939220187443633296486051191769970568671588388800357714279873,
        //     "new_mmr_root_keccak_low": 130944412037395013456457343600993038804,
        //     "new_mmr_root_keccak_high": 251692698179650461557630012690185398638,
        //     "new_mmr_len": 19
        // }
        outputs[1] = (
            SharpFactsAggregator.JobOutputPacked({
                blockNPlusOneParentHash: bytes32(
                    Uint256Splitter.merge128(
                        3481649350075648672177608527441112449,
                        105863212581884754852829743559155307897
                    )
                ),
                blockNMinusRPlusOneParentHash: bytes32(
                    Uint256Splitter.merge128(
                        274298540468991391430554661646020544970,
                        286982477857871647409769742511439137417
                    )
                ),
                mmrPreviousRootPoseidon: bytes32(
                    uint256(
                        2979921579743029844311702091292349139366985913887733325731342704997480991156
                    )
                ),
                mmrPreviousRootKeccak: bytes32(
                    Uint256Splitter.merge128(
                        35156908954301055531592827141631060830,
                        164501793725413761694418296230187300434
                    )
                ),
                mmrNewRootPoseidon: bytes32(
                    uint256(
                        2418312068954869939220187443633296486051191769970568671588388800357714279873
                    )
                ),
                mmrNewRootKeccak: bytes32(
                    Uint256Splitter.merge128(
                        130944412037395013456457343600993038804,
                        251692698179650461557630012690185398638
                    )
                ),
                mmrSizesPacked: Uint256Splitter.merge128(10, 19)
            })
        );

        sharpFactsAggregator.aggregateSharpJobs(
            block.number - blocksConfirmations,
            outputs
        );
    }
}
