// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ClonesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/ClonesUpgradeable.sol";
import {AccessControlUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

import {SharpFactsAggregator} from "../src/SharpFactsAggregator.sol";

contract AggregatorsFactory is AccessControlUpgradeable {
    // Blank contract template
    address public _template;

    // Timelock mechanism
    struct Timelock {
        uint256 timestamp;
        address newTemplate;
    }

    // Timelock
    mapping(uint256 => Timelock) public upgradeTimelock;

    uint256 updatesCount;

    // Delay before an upgrade can be performed
    uint256 public immutable DELAY;

    // Aggregators indexing
    uint256 public aggregatorsCount;

    // Aggregators by index
    mapping(uint256 => address) public aggregatorsById;

    // Access control
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Default roots for new aggregators:
    // poseidon_hash("brave new world")
    bytes32 public constant POSEIDON_MMR_INITIAL_ROOT =
        0x02241b3b7f1c4b9cf63e670785891de91f7237b1388f6635c1898ae397ad32dd;

    // keccak_hash("brave new world")
    bytes32 public constant KECCAK_MMR_INITIAL_ROOT =
        0xce92cc894a17c107be8788b58092c22cd0634d1489ca0ce5b4a045a1ce31b168;

    // Events
    event TemplateProposal(address newTemplate);
    event TemplateUpdate(address oldTemplate, address newTemplate);
    event AggregatorCreation(address aggregator, uint256 aggregatorId);

    constructor(address template, uint256 delay) {
        _template = template;

        DELAY = delay;

        _setRoleAdmin(OPERATOR_ROLE, OPERATOR_ROLE);
        _grantRole(OPERATOR_ROLE, _msgSender());
    }

    modifier onlyOperator() {
        require(
            hasRole(OPERATOR_ROLE, _msgSender()),
            "Caller is not an operator"
        );
        _;
    }

    function createAggregator(
        address sharpFactsRegistry,
        bytes32 programHash,
        uint256 aggregatorId
    ) external onlyOperator returns (address) {
        SharpFactsAggregator.AggregatorState memory initialAggregatorState;

        if (aggregatorId != 0) {
            require(aggregatorId <= aggregatorsCount, "Invalid aggregator ID");

            address existingAggregatorAddr = aggregatorsById[aggregatorId];
            require(
                existingAggregatorAddr != address(0),
                "Aggregator not found"
            );

            // Attach from existing aggregator
            SharpFactsAggregator existingAggregator = SharpFactsAggregator(
                existingAggregatorAddr
            );
            initialAggregatorState = existingAggregator.getAggregatorState();
        } else {
            // Create a new aggregator (detach from existing ones)
            initialAggregatorState = SharpFactsAggregator.AggregatorState({
                poseidonMmrRoot: POSEIDON_MMR_INITIAL_ROOT,
                keccakMmrRoot: KECCAK_MMR_INITIAL_ROOT,
                mmrSize: 1,
                continuableParentHash: bytes32(0)
            });
        }

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,bytes32,(bytes32,bytes32,uint256,bytes32))",
            sharpFactsRegistry,
            programHash,
            initialAggregatorState
        );

        address clone = ClonesUpgradeable.clone(_template);

        // The data is the encoded initialize function (with any initial parameters)
        (bool success, ) = clone.call(data);

        require(success, "Aggregator initialization failed");

        aggregatorsById[++aggregatorsCount] = clone;

        emit AggregatorCreation(clone, aggregatorsCount);

        return clone;
    }

    function proposeUpgrade(address newTemplate) external onlyOperator {
        upgradeTimelock[++updatesCount] = Timelock(
            block.timestamp + DELAY,
            newTemplate
        );

        emit TemplateProposal(newTemplate);
    }

    function upgrade(uint256 updateId) external onlyOperator {
        require(updateId <= updatesCount, "Invalid updateId");

        uint256 timeLockTimestamp = upgradeTimelock[updateId].timestamp;
        require(timeLockTimestamp != 0, "TimeLock not set");
        require(block.timestamp >= timeLockTimestamp, "TimeLock not expired");

        address oldTemplate = _template;
        _template = upgradeTimelock[updateId].newTemplate;

        // Clear timelock
        upgradeTimelock[updateId] = Timelock(0, address(0));

        emit TemplateUpdate(oldTemplate, _template);
    }
}
