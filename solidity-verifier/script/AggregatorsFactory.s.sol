// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {SharpFactsAggregator} from "../src/SharpFactsAggregator.sol";
import {AggregatorsFactory} from "../src/AggregatorsFactory.sol";

contract AggregatorsFactoryDeployer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the template
        SharpFactsAggregator aggregatorTemplate = new SharpFactsAggregator();

        console.log(
            "Aggregator TEMPLATE deployed at: ",
            address(aggregatorTemplate)
        );

        // Deploy the factory
        AggregatorsFactory factory = new AggregatorsFactory(
            address(aggregatorTemplate)
        );

        console.log("AggregatorsFactory deployed at: ", address(factory));

        // Create a new aggregator
        SharpFactsAggregator aggregator = SharpFactsAggregator(
            factory.createAggregator(
                // Create a new one (past aggregator ID = 0 for non-existing)
                0
            )
        );

        console.log("SharpFactsAggregator deployed at: ", address(aggregator));

        vm.stopBroadcast();
    }
}
