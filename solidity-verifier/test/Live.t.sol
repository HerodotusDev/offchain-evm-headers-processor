// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {SharpFactsAggregator} from "../src/SharpFactsAggregator.sol";
import {IFactsRegistry} from "../src/interfaces/IFactsRegistry.sol";
import {console} from "forge-std/Console.sol";

contract Live is Test {
    SharpFactsAggregator aggregator;
    uint256 privateKey;

    constructor() {
        privateKey = vm.envUint("PRIVATE_KEY");
        string memory SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(SEPOLIA_RPC_URL);

        //? For testing of a fully live contract use this:
        address aggregatorAddress = address(
            0x00d91dd5e6376202f3eaf5336179b5d1c5a136df66
        );
        aggregator = SharpFactsAggregator(aggregatorAddress);

        //? For debugging and changing the contract code, but using the actual facts registry use this:
        // SharpFactsAggregator.AggregatorState
        //     memory initialAggregatorState = SharpFactsAggregator
        //         .AggregatorState({
        //             poseidonMmrRoot: 0x06759138078831011e3bc0b4a135af21c008dda64586363531697207fb5a2bae,
        //             keccakMmrRoot: 0x5d8d23518dd388daa16925ff9475c5d1c06430d21e0422520d6a56402f42937b,
        //             mmrSize: 1,
        //             continuableParentHash: 0xcfc3c668129a2a395dd69132d7ae224de1bceca9f915f1430bf4d3c1b1620510
        //         });
        // IFactsRegistry factsRegistry = IFactsRegistry(
        //     address(0x000ed8c44415e882F3033B4F3AFF916BbB4997f915)
        // );

        // vm.startBroadcast(privateKey);
        // aggregator = new SharpFactsAggregator(factsRegistry);
        // aggregator.initialize(initialAggregatorState);
        // vm.stopBroadcast();
    }

    // ['0x692d88', '0x692d85', '0x1309e6d97353aa7d712bb058dd2abeab', '0x8d38275adfe450dbb8a8961ba1f4c789', '0x8b52978a2d7876cc247ecbbd5900b71', '0x3d557adee5e7064f164bf5918deea805', '0x6759138078831011e3bc0b4a135af21c008dda64586363531697207fb5a2bae', '0xc06430d21e0422520d6a56402f42937b', '0x5d8d23518dd388daa16925ff9475c5d1', '0x1', '0x21274b8cfb5ba2ae9b1e2466122f933d24b9c1f21861878e8498fbcdd0f6141', '0x7630ae2ceb7f932a17d77cb539cfab00', '0x6e2f44b74a42d10a4ea513bab86a5da2', '0x8']
    function test_a() external {
        //? before this sync is requried:
        // registerNewRange(6892936)
        //
        // equivalent to:
        //
        // blockNumberToBlockHash[
        //     6892936
        // ] = 0x8d38275adfe450dbb8a8961ba1f4c7891309e6d97353aa7d712bb058dd2abeab;

        SharpFactsAggregator.JobOutputPacked[]
            memory jobOutputs = new SharpFactsAggregator.JobOutputPacked[](1);

        jobOutputs[0] = SharpFactsAggregator.JobOutputPacked({
            // 692d85 - 6892933
            // 692d88 - 6892936
            blockNumbersPacked: 0x692d8500000000000000000000000000692d88,
            blockNPlusOneParentHash: 0x8d38275adfe450dbb8a8961ba1f4c7891309e6d97353aa7d712bb058dd2abeab,
            blockNMinusRPlusOneParentHash: 0x3d557adee5e7064f164bf5918deea80508b52978a2d7876cc247ecbbd5900b71,
            mmrPreviousRootPoseidon: 0x06759138078831011e3bc0b4a135af21c008dda64586363531697207fb5a2bae,
            mmrPreviousRootKeccak: 0x5d8d23518dd388daa16925ff9475c5d1c06430d21e0422520d6a56402f42937b,
            mmrNewRootPoseidon: 0x021274b8cfb5ba2ae9b1e2466122f933d24b9c1f21861878e8498fbcdd0f6141,
            mmrNewRootKeccak: 0x6e2f44b74a42d10a4ea513bab86a5da27630ae2ceb7f932a17d77cb539cfab00,
            mmrSizesPacked: 0x800000000000000000000000000000001
        });

        vm.startBroadcast(privateKey);
        aggregator.aggregateSharpJobs(
            // dobrze
            6892936,
            jobOutputs
        );
        vm.stopBroadcast();
    }

    function test_c() external view {
        uint256[] memory outputs = new uint256[](14);
        outputs[0] = 0x692d88;
        outputs[1] = 0x692d85;
        outputs[2] = 0x1309e6d97353aa7d712bb058dd2abeab;
        outputs[3] = 0x8d38275adfe450dbb8a8961ba1f4c789;
        outputs[4] = 0x8b52978a2d7876cc247ecbbd5900b71;
        outputs[5] = 0x3d557adee5e7064f164bf5918deea805;
        outputs[
            6
        ] = 0x6759138078831011e3bc0b4a135af21c008dda64586363531697207fb5a2bae;
        outputs[7] = 0xc06430d21e0422520d6a56402f42937b;
        outputs[8] = 0x5d8d23518dd388daa16925ff9475c5d1;
        outputs[9] = 0x1;
        outputs[
            10
        ] = 0x21274b8cfb5ba2ae9b1e2466122f933d24b9c1f21861878e8498fbcdd0f6141;
        outputs[11] = 0x7630ae2ceb7f932a17d77cb539cfab00;
        outputs[12] = 0x6e2f44b74a42d10a4ea513bab86a5da2;
        outputs[13] = 0x8;

        bytes32 outputHash = keccak256(abi.encodePacked(outputs));

        //? OLD: 0x01eca36d586f5356fba096edbf7414017d51cd0ed24b8fde80f78b61a9216ed2
        //? NEW: 0x65b6e7259ea513e896bc97cbc9445fd71eeb71fb8ce92bad1df9676f97df626
        bytes32 programHash = aggregator.PROGRAM_HASH();
        // bytes32 programHash = bytes32(
        //     uint256(
        //         0x65b6e7259ea513e896bc97cbc9445fd71eeb71fb8ce92bad1df9676f97df626
        //     )
        // );

        bytes32 fact = keccak256(abi.encode(programHash, outputHash));

        console.logBytes32(fact);
        console.logBytes32(
            0x46fc208ac02383d058886ff468eb940524ade803f328c38b5d70cd8f013a14c4
        );

        require(
            fact ==
                0x46fc208ac02383d058886ff468eb940524ade803f328c38b5d70cd8f013a14c4,
            "test"
        );
    }
}
