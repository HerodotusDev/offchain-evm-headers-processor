// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "../src/SharpFactsAggregator.sol";
import "../src/lib/Uint256Splitter.sol";

contract SharpFactsAggregatorTest is Test {
    using Uint256Splitter for uint256;

    uint256 latestBlockNumber;

    SharpFactsAggregator public sharpFactsAggregator;

    event Aggregate(
        uint256 rightBoundStartBlock,
        bytes32 poseidonMmrRoot,
        bytes32 keccakMmrRoot,
        uint256 mmrSize,
        bytes32 continuableParentHash
    );

    // poseidon_hash("brave new world")
    bytes32 public constant POSEIDON_MMR_INITIAL_ROOT =
        0x02241b3b7f1c4b9cf63e670785891de91f7237b1388f6635c1898ae397ad32dd;

    // keccak_hash("brave new world")
    bytes32 public constant KECCAK_MMR_INITIAL_ROOT =
        0xce92cc894a17c107be8788b58092c22cd0634d1489ca0ce5b4a045a1ce31b168;

    function setUp() public {
        // The config hereunder must be specified in `foundry.toml`:
        // [rpc_endpoints]
        // goerli="GOERLI_RPC_URL"
        vm.createSelectFork(vm.rpcUrl("goerli"));

        latestBlockNumber = block.number;

        SharpFactsAggregator.AggregatorState
            memory initialAggregatorState = SharpFactsAggregator
                .AggregatorState({
                    poseidonMmrRoot: POSEIDON_MMR_INITIAL_ROOT,
                    keccakMmrRoot: KECCAK_MMR_INITIAL_ROOT,
                    mmrSize: 1,
                    continuableParentHash: bytes32(0)
                });

        sharpFactsAggregator = new SharpFactsAggregator();

        // Ensure roles were not granted
        assertFalse(
            sharpFactsAggregator.hasRole(
                keccak256("OPERATOR_ROLE"),
                address(this)
            )
        );
        assertFalse(
            sharpFactsAggregator.hasRole(
                keccak256("UNLOCKER_ROLE"),
                address(this)
            )
        );
        assertFalse(
            sharpFactsAggregator.hasRole(
                keccak256("UPGRADER_ROLE"),
                address(this)
            )
        );

        sharpFactsAggregator.initialize(
            // Sharp Facts Registry (Goërli)
            0xAB43bA48c9edF4C2C4bB01237348D1D7B28ef168,
            // Program hash (prover)
            bytes32(
                uint(
                    0x273de4c1c69594e2234858d9cb39ccf107a5754d3dc98f0760c82efaa919891
                )
            ),
            // Initial aggregator state (empty trees)
            initialAggregatorState
        );

        // Ensure roles were successfuly granted
        assertTrue(
            sharpFactsAggregator.hasRole(
                keccak256("OPERATOR_ROLE"),
                address(this)
            )
        );
        assertTrue(
            sharpFactsAggregator.hasRole(
                keccak256("UNLOCKER_ROLE"),
                address(this)
            )
        );
        assertTrue(
            sharpFactsAggregator.hasRole(
                keccak256("UPGRADER_ROLE"),
                address(this)
            )
        );
    }

    function testVerifyInvalidFact() public {
        // Fake output
        uint256[] memory outputs = new uint256[](1);
        outputs[0] = 4242424242;

        assertFalse(sharpFactsAggregator.verifyFact(outputs));
    }

    function testRealAggregateSingleJobManual() public {
        vm.makePersistent(address(sharpFactsAggregator));

        vm.rollFork(9433325);

        uint256 startChildBlock = block.number; // Rightmost block's child block number
        uint256 blocksConfirmations = 20;

        uint256 blockRightBound = startChildBlock - blocksConfirmations - 1; // Rightmost block included in the proving range

        sharpFactsAggregator.registerNewRange(blocksConfirmations);

        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            bytes32 continuableParentHash
        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        assert(mmrSize == 1); // New tree, with genesis element "brave new world" only
        assert(continuableParentHash == blockhash(blockRightBound));

        bytes32 output0BlockNPlusOneParentHash = bytes32(
            Uint256Splitter.merge128(
                136280817012297242619553763422457190740,
                230845892776573197306270179585336099707
            )
        );
        assert(continuableParentHash == output0BlockNPlusOneParentHash);

        SharpFactsAggregator.JobOutputPacked[]
            memory outputs = new SharpFactsAggregator.JobOutputPacked[](1);

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
                        3481649350075648672177608527441112449, // 0x9719E13049B52D81
                        105863212581884754852829743559155307897 // 0x985F8F1F3A2ED579
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

        vm.rollFork(latestBlockNumber);

        SharpFactsAggregator.JobOutputPacked memory lastOutput = outputs[
            outputs.length - 1
        ];
        (, uint256 mmrNewSize) = lastOutput.mmrSizesPacked.split128();

        vm.expectEmit(true, true, true, true);
        emit SharpFactsAggregator.Aggregate(
            0,
            lastOutput.mmrNewRootPoseidon,
            lastOutput.mmrNewRootKeccak,
            mmrNewSize,
            lastOutput.blockNMinusRPlusOneParentHash
        );
        sharpFactsAggregator.aggregateSharpJobs(0, outputs);

        ensureGlobalStateCorrectness(lastOutput);
    }

    function ensureGlobalStateCorrectness(
        SharpFactsAggregator.JobOutputPacked memory output
    ) internal view {
        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            bytes32 continuableParentHash
        ) = sharpFactsAggregator.aggregatorState();

        (, uint256 mmrNewSize) = output.mmrSizesPacked.split128();

        assert(poseidonMmrRoot == output.mmrNewRootPoseidon);
        assert(keccakMmrRoot == output.mmrNewRootKeccak);
        assert(mmrSize == mmrNewSize);
        assert(continuableParentHash == output.blockNMinusRPlusOneParentHash);
    }

    function testRealAggregateTwoJobsManual() public {
        vm.makePersistent(address(sharpFactsAggregator));

        vm.rollFork(9433325);

        uint256 startChildBlock = block.number; // Rightmost block's child block number
        uint256 blocksConfirmations = 20;

        uint256 blockRightBound = startChildBlock - blocksConfirmations - 1; // Rightmost block included in the proving range

        sharpFactsAggregator.registerNewRange(blocksConfirmations);

        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            bytes32 continuableParentHash
        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        assert(mmrSize == 1); // New tree, with genesis element "brave new world" only
        assert(continuableParentHash == blockhash(blockRightBound));

        bytes32 output0BlockNPlusOneParentHash = bytes32(
            Uint256Splitter.merge128(
                136280817012297242619553763422457190740,
                230845892776573197306270179585336099707
            )
        );
        assert(continuableParentHash == output0BlockNPlusOneParentHash);

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
                        3481649350075648672177608527441112449, // 0x9719E13049B52D81
                        105863212581884754852829743559155307897 // 0x985F8F1F3A2ED579
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

        vm.rollFork(latestBlockNumber);

        sharpFactsAggregator.aggregateSharpJobs(0, outputs);

        ensureGlobalStateCorrectness(outputs[outputs.length - 1]);
    }

    function testRealAggregateThreeJobsManual() public {
        vm.makePersistent(address(sharpFactsAggregator));

        vm.rollFork(9433325);

        uint256 startChildBlock = block.number; // Rightmost block's child block number
        uint256 blocksConfirmations = 20;

        uint256 blockRightBound = startChildBlock - blocksConfirmations - 1; // Rightmost block included in the proving range

        sharpFactsAggregator.registerNewRange(blocksConfirmations);

        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            bytes32 continuableParentHash
        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        assert(mmrSize == 1); // New tree, with genesis element "brave new world" only
        assert(continuableParentHash == blockhash(blockRightBound));

        bytes32 output0BlockNPlusOneParentHash = bytes32(
            Uint256Splitter.merge128(
                136280817012297242619553763422457190740,
                230845892776573197306270179585336099707
            )
        );
        assert(continuableParentHash == output0BlockNPlusOneParentHash);

        SharpFactsAggregator.JobOutputPacked[]
            memory outputs = new SharpFactsAggregator.JobOutputPacked[](3);

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
                        3481649350075648672177608527441112449, // 0x9719E13049B52D81
                        105863212581884754852829743559155307897 // 0x985F8F1F3A2ED579
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

        // output[2]:
        // "block_n_plus_one_parent_hash_low": 274298540468991391430554661646020544970,
        // "block_n_plus_one_parent_hash_high": 286982477857871647409769742511439137417,
        // "block_n_minus_r_plus_one_parent_hash_low": 206986813976871303461777369348889547392,
        // "block_n_minus_r_plus_one_parent_hash_high": 66865458019671824747396540064787864825,
        // "mmr_last_root_poseidon": 2418312068954869939220187443633296486051191769970568671588388800357714279873,
        // "mmr_last_root_keccak_low": 130944412037395013456457343600993038804,
        // "mmr_last_root_keccak_high": 251692698179650461557630012690185398638,
        // "mmr_last_len": 19,
        // "new_mmr_root_poseidon": 1456411510471052639938384680864592768502957753429545344994021785081034100373,
        // "new_mmr_root_keccak_low": 212130709501091129069348499388830765594,
        // "new_mmr_root_keccak_high": 267631127283734364091518886213837951565,
        // "new_mmr_len": 31
        outputs[2] = (
            SharpFactsAggregator.JobOutputPacked({
                blockNPlusOneParentHash: bytes32(
                    Uint256Splitter.merge128(
                        274298540468991391430554661646020544970,
                        286982477857871647409769742511439137417
                    )
                ),
                blockNMinusRPlusOneParentHash: bytes32(
                    Uint256Splitter.merge128(
                        206986813976871303461777369348889547392,
                        66865458019671824747396540064787864825
                    )
                ),
                mmrPreviousRootPoseidon: bytes32(
                    uint256(
                        2418312068954869939220187443633296486051191769970568671588388800357714279873
                    )
                ),
                mmrPreviousRootKeccak: bytes32(
                    Uint256Splitter.merge128(
                        130944412037395013456457343600993038804,
                        251692698179650461557630012690185398638
                    )
                ),
                mmrNewRootPoseidon: bytes32(
                    uint256(
                        1456411510471052639938384680864592768502957753429545344994021785081034100373
                    )
                ),
                mmrNewRootKeccak: bytes32(
                    Uint256Splitter.merge128(
                        212130709501091129069348499388830765594,
                        267631127283734364091518886213837951565
                    )
                ),
                mmrSizesPacked: Uint256Splitter.merge128(19, 31)
            })
        );

        vm.rollFork(latestBlockNumber);
        sharpFactsAggregator.aggregateSharpJobs(0, outputs);
        ensureGlobalStateCorrectness(outputs[outputs.length - 1]);
    }

    function testRealAggregateJobsFFI() public {
        vm.makePersistent(address(sharpFactsAggregator));

        vm.rollFork(9433325);

        uint256 startChildBlock = block.number; // Rightmost block's child block number
        uint256 blocksConfirmations = 20;

        uint256 blockRightBound = startChildBlock - blocksConfirmations - 1; // Rightmost block included in the proving range

        sharpFactsAggregator.registerNewRange(blocksConfirmations);

        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            bytes32 continuableParentHash
        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "./helpers/compute-outputs.js";
        inputs[2] = "helpers/outputs_batch_1.json";
        bytes memory output = vm.ffi(inputs);

        SharpFactsAggregator.JobOutputPacked[] memory outputs = abi.decode(
            output,
            (SharpFactsAggregator.JobOutputPacked[])
        );

        SharpFactsAggregator.JobOutputPacked memory firstOutput = outputs[0];
        assert(mmrSize == 1); // New tree, with genesis element "brave new world" only
        assert(continuableParentHash == blockhash(blockRightBound));
        assert(continuableParentHash == firstOutput.blockNPlusOneParentHash);
        assert(poseidonMmrRoot == firstOutput.mmrPreviousRootPoseidon);
        assert(keccakMmrRoot == firstOutput.mmrPreviousRootKeccak);

        vm.rollFork(latestBlockNumber);
        sharpFactsAggregator.aggregateSharpJobs(0, outputs);
        ensureGlobalStateCorrectness(outputs[outputs.length - 1]);
    }
}
