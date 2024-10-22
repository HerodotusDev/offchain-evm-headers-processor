// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {SharpFactsAggregator} from "../src/SharpFactsAggregator.sol";
import {Uint256Splitter} from "../src/lib/Uint256Splitter.sol";

import {IFactsRegistry} from "../src/interfaces/IFactsRegistry.sol";
import {MockedSharpFactsRegistry} from "../src/mocks/MockFactsRegistry.sol";

contract SharpFactsAggregatorTest is Test {
    using Uint256Splitter for uint256;

    uint256 public latestBlockNumber;

    SharpFactsAggregator public sharpFactsAggregator;

    event Aggregate(
        uint256 fromBlockNumberHigh,
        uint256 toBlockNumberLow,
        bytes32 poseidonMmrRoot,
        bytes32 keccakMmrRoot,
        uint256 mmrSize,
        bytes32 continuableParentHash
    );

    // poseidon_hash(1, "brave new world")
    bytes32 public constant POSEIDON_MMR_INITIAL_ROOT =
        0x06759138078831011e3bc0b4a135af21c008dda64586363531697207fb5a2bae;

    // keccak_hash(1, "brave new world")
    bytes32 public constant KECCAK_MMR_INITIAL_ROOT =
        0x5d8d23518dd388daa16925ff9475c5d1c06430d21e0422520d6a56402f42937b;

    IFactsRegistry public mockFactsRegistry;

    function setUp() public {
        // The config hereunder must be specified in `foundry.toml`:
        // [rpc_endpoints]
        // sepolia="SEPOLIA_RPC_URL"
        vm.createSelectFork(vm.rpcUrl("sepolia"));

        latestBlockNumber = block.number;

        SharpFactsAggregator.AggregatorState
            memory initialAggregatorState = SharpFactsAggregator
                .AggregatorState({
                    poseidonMmrRoot: POSEIDON_MMR_INITIAL_ROOT,
                    keccakMmrRoot: KECCAK_MMR_INITIAL_ROOT,
                    mmrSize: 1,
                    continuableParentHash: bytes32(0)
                });

        mockFactsRegistry = IFactsRegistry(
            address(new MockedSharpFactsRegistry())
        );

        vm.makePersistent(address(mockFactsRegistry));

        sharpFactsAggregator = new SharpFactsAggregator(mockFactsRegistry);

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

        sharpFactsAggregator.initialize(
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

    function testRealAggregateJobsFFI() public {
        vm.makePersistent(address(sharpFactsAggregator));

        vm.createSelectFork(vm.rpcUrl("mainnet"));

        uint256 firstRangeStartChildBlock = 20;
        uint256 secondRangeStartChildBlock = 30;

        uint256 pastBlockStart = firstRangeStartChildBlock + 50;
        // Start at block no. 70
        vm.rollFork(pastBlockStart);

        sharpFactsAggregator.registerNewRange(firstRangeStartChildBlock);

        sharpFactsAggregator.registerNewRange(secondRangeStartChildBlock);

        (
            bytes32 poseidonMmrRoot,
            bytes32 keccakMmrRoot,
            uint256 mmrSize,
            bytes32 continuableParentHash
        ) = sharpFactsAggregator.aggregatorState(); // Get initialized tree state

        string[] memory inputs = new string[](3);
        inputs[0] = "node";
        inputs[1] = "./helpers/compute-outputs.js";
        inputs[2] = "helpers/outputs_batch_mainnet.json";
        bytes memory output = vm.ffi(inputs);

        SharpFactsAggregator.JobOutputPacked[] memory outputs = abi.decode(
            output,
            (SharpFactsAggregator.JobOutputPacked[])
        );

        SharpFactsAggregator.JobOutputPacked memory firstOutput = outputs[0];
        assert(mmrSize == 1); // New tree, with genesis element "brave new world" only
        assert(continuableParentHash == firstOutput.blockNPlusOneParentHash);
        assert(poseidonMmrRoot == firstOutput.mmrPreviousRootPoseidon);
        assert(keccakMmrRoot == firstOutput.mmrPreviousRootKeccak);

        vm.createSelectFork(vm.rpcUrl("sepolia"));

        vm.rollFork(latestBlockNumber);

        sharpFactsAggregator.aggregateSharpJobs(outputs);
        ensureGlobalStateCorrectness(outputs[outputs.length - 1]);

        string[] memory inputsExtended = new string[](3);
        inputsExtended[0] = "node";
        inputsExtended[1] = "./helpers/compute-outputs.js";
        inputsExtended[2] = "helpers/outputs_batch_mainnet_extended.json";
        bytes memory outputExtended = vm.ffi(inputsExtended);

        SharpFactsAggregator.JobOutputPacked[] memory outputsExtended = abi
            .decode(outputExtended, (SharpFactsAggregator.JobOutputPacked[]));

        sharpFactsAggregator.aggregateSharpJobs(outputsExtended);
        ensureGlobalStateCorrectness(
            outputsExtended[outputsExtended.length - 1]
        );
    }
}
