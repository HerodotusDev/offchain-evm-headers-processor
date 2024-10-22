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
        // address aggregatorAddress = address(
        //     0xF92800e310a44e2cb3301e45e99Febf997A093fE
        // );
        // aggregator = SharpFactsAggregator(aggregatorAddress);

        //? For debugging and changing the contract code, but using the actual facts registry use this:
        SharpFactsAggregator.AggregatorState
            memory initialAggregatorState = SharpFactsAggregator
                .AggregatorState({
                    poseidonMmrRoot: 0x06759138078831011e3bc0b4a135af21c008dda64586363531697207fb5a2bae,
                    keccakMmrRoot: 0x5d8d23518dd388daa16925ff9475c5d1c06430d21e0422520d6a56402f42937b,
                    mmrSize: 1,
                    continuableParentHash: 0xcfc3c668129a2a395dd69132d7ae224de1bceca9f915f1430bf4d3c1b1620510
                });
        IFactsRegistry factsRegistry = IFactsRegistry(
            vm.envAddress("FACTS_REGISTRY_ADDRESS")
        );

        vm.startBroadcast(privateKey);
        aggregator = new SharpFactsAggregator(factsRegistry);
        aggregator.initialize(initialAggregatorState);
        vm.stopBroadcast();
    }

    function test_a() external {
        //? before this sync is requried:
        // registerNewRange(6892937)
        //
        // equivalent to putting this in SharpFactsAggregator's constructor:
        //
        // blockNumberToParentHash[
        //     6892937
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
        aggregator.aggregateSharpJobs(6892936, jobOutputs);
    }
}
