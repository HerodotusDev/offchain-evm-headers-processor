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
            0xF92800e310a44e2cb3301e45e99Febf997A093fE
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
        //     vm.envAddress("FACTS_REGISTRY_ADDRESS")
        // );

        // vm.startBroadcast(privateKey);
        // aggregator = new SharpFactsAggregator(factsRegistry);
        // aggregator.initialize(initialAggregatorState);
        // vm.stopBroadcast();
    }

    function test_a() external {
        //? before this sync is requried:
        // registerNewRange(6892937)
        //
        // equivalent to:
        //
        // blockNumberToParentHash[
        //     6892937
        // ] = 0x8d38275adfe450dbb8a8961ba1f4c7891309e6d97353aa7d712bb058dd2abeab;

        SharpFactsAggregator.JobOutputPacked[]
            memory jobOutputs = new SharpFactsAggregator.JobOutputPacked[](1);

        // {
        //     block_numbers_packed: 0x6987380000000000000000000000000069873c,
        //     block_n_plus_one_parent_hash: "0x7072cb7db65415f8cab13857708f896bd6833196ee5f0c40ed92c1e9f5eb42a3",
        //     block_n_minus_r_plus_one_parent_hash: "0x7ab32a98a986e18bd7d2dccdace1abf4226b2b3d50ce47551d73cd1d185a2a92",
        //     mmr_previous_root_poseidon: "0x06759138078831011e3bc0b4a135af21c008dda64586363531697207fb5a2bae",
        //     mmr_previous_root_keccak: "0x5d8d23518dd388daa16925ff9475c5d1c06430d21e0422520d6a56402f42937b",
        //     mmr_new_root_poseidon: "0x007971912f38d8496f2f00e124d2b8201206950453eaa6587e245fe94b0b1d1a",
        //     mmr_new_root_keccak: "0xc6ebf0887a1c00417db5c931e8dff20e92410f972223d43bd2877b4045c1786a",
        //     mmr_sizes_packed: 0xa00000000000000000000000000000001,
        // }
        // 69873c - 6915900
        // 698738 - 6915896
        jobOutputs[0] = SharpFactsAggregator.JobOutputPacked({
            blockNumbersPacked: 0x6987380000000000000000000000000069873c,
            blockNPlusOneParentHash: 0x7072cb7db65415f8cab13857708f896bd6833196ee5f0c40ed92c1e9f5eb42a3,
            blockNMinusRPlusOneParentHash: 0x7ab32a98a986e18bd7d2dccdace1abf4226b2b3d50ce47551d73cd1d185a2a92,
            mmrPreviousRootPoseidon: 0x06759138078831011e3bc0b4a135af21c008dda64586363531697207fb5a2bae,
            mmrPreviousRootKeccak: 0x5d8d23518dd388daa16925ff9475c5d1c06430d21e0422520d6a56402f42937b,
            mmrNewRootPoseidon: 0x007971912f38d8496f2f00e124d2b8201206950453eaa6587e245fe94b0b1d1a,
            mmrNewRootKeccak: 0xc6ebf0887a1c00417db5c931e8dff20e92410f972223d43bd2877b4045c1786a,
            mmrSizesPacked: 0xa00000000000000000000000000000001
        });

        vm.startBroadcast(privateKey);
        aggregator.aggregateSharpJobs(6915900, jobOutputs);
        vm.stopBroadcast();
    }
}
