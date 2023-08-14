// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {SharpFactsAggregator} from "../src/SharpFactsAggregator.sol";
import {AggregatorsFactory} from "../src/AggregatorsFactory.sol";

contract AggregatorsFactoryTest is Test {
    AggregatorsFactory public factory;

    SharpFactsAggregator public aggregator;

    SharpFactsAggregator private aggregatorTemplate;

    uint256 constant PROPOSAL_DELAY = 3 days;

    // Important events
    event UpgradeProposal(address newTemplate);
    event Upgrade(address oldTemplate, address newTemplate);
    event AggregatorCreation(address aggregator, uint256 aggregatorId);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("goerli"));

        aggregatorTemplate = new SharpFactsAggregator();

        factory = new AggregatorsFactory(address(aggregatorTemplate));

        vm.expectEmit(false, true, false, false);
        emit AggregatorCreation(address(aggregator), 0);
        aggregator = SharpFactsAggregator(
            factory.createAggregator(
                // Create a new one (past aggregator ID = 0 for non-existing)
                0
            )
        );
        assertEq(factory.aggregatorsById(1), address(aggregator));

        assertTrue(factory.hasRole(keccak256("OPERATOR_ROLE"), address(this)));
    }

    function testDeployment() public {
        // Factory checks
        assertTrue(factory.aggregatorsById(1) == address(aggregator));
        assertEq(factory.DELAY(), PROPOSAL_DELAY);
        assertTrue(
            aggregator.hasRole(keccak256("OPERATOR_ROLE"), address(factory))
        );

        // Aggregator roles checks
        assertTrue(
            aggregator.hasRole(keccak256("OPERATOR_ROLE"), address(this))
        );
        assertTrue(
            aggregator.hasRole(keccak256("UNLOCKER_ROLE"), address(this))
        );

        aggregator.registerNewRange(42);

        aggregator.revokeRole(keccak256("UNLOCKER_ROLE"), address(this));
        aggregator.revokeRole(keccak256("OPERATOR_ROLE"), address(this));

        assertFalse(
            aggregator.hasRole(keccak256("OPERATOR_ROLE"), address(this))
        );
        assertFalse(
            aggregator.hasRole(keccak256("UNLOCKER_ROLE"), address(this))
        );

        vm.expectRevert("Caller is not an operator");
        aggregator.registerNewRange(50);
    }

    function testUpgrade() public {
        vm.expectEmit(false, true, false, false);
        emit AggregatorCreation(address(aggregator), 1);
        SharpFactsAggregator newAggregator = SharpFactsAggregator(
            factory.createAggregator(
                // Attach to existing aggregator (id = 1)
                1
            )
        );
        assertEq(factory.aggregatorsById(2), address(newAggregator));

        vm.expectEmit(true, false, false, true);
        emit UpgradeProposal(address(newAggregator));
        factory.proposeUpgrade(address(newAggregator));

        vm.expectRevert("Invalid updateId");
        factory.upgrade(42);

        vm.expectRevert("TimeLock not expired");
        factory.upgrade(1);

        vm.warp(block.timestamp + PROPOSAL_DELAY);

        vm.startPrank(address(42));
        vm.expectRevert("Caller is not an operator");
        factory.upgrade(1);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit Upgrade(address(aggregatorTemplate), address(newAggregator));
        factory.upgrade(1);

        vm.expectRevert("TimeLock not set");
        factory.upgrade(1);
    }
}
