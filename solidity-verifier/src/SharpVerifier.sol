// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IFactsRegistry.sol";
import "forge-std/console.sol";

contract SharpVerifier is Initializable {
    // Sharp Facts Registry
    address public immutable FACTS_REGISTY;

    // Proving program hash
    uint256 public immutable PROGRAM_HASH;

    string constant MMR_INIT_ELEMENT = "brave new world";

    // Errors
    error AggregationRootMismatch();
    error AggregationSizeMismatch();
    error AggregationErrorParentHashLowMismatch();
    error AggregationErrorParentHashHighMismatch();
    error InvalidFact();

    // Aggregator state
    struct AggregatorState {
        bytes32 currentMmrRoot;
        uint256 currentMmrSize;
        bytes32 mostRecentBlockHash;
        bytes32 oldestBlockHash;
    }

    // Cairo program's output
    struct JobOutput {
        bytes32 mmrPreviousRoot;
        uint256 mmrPreviousSize;
        bytes32 childBlockParentHashLow;
        bytes32 childBlockParentHashHigh;
        bytes32 newMmrRoot;
        uint256 newMmrSize;
        bytes32 blockNMinusRParentHashLow;
        bytes32 blockNMinusRParentHashHigh;
    }

    // Contract state
    AggregatorState public aggregatorState;

    constructor(address factRegistry, uint256 programHash) {
        FACTS_REGISTY = factRegistry;
        PROGRAM_HASH = programHash;
    }

    // Initialize the aggregator state
    function initialize(uint256 blocksConfirmations) public initializer {
        assert(blocksConfirmations <= 255);

        bytes32 recentBlock = blockhash(block.number - blocksConfirmations);

        // TODO: add proper initialization values:
        aggregatorState.currentMmrRoot = 0x0000000;
        aggregatorState.currentMmrSize = 1;
        aggregatorState.mostRecentBlockHash = recentBlock;
        aggregatorState.oldestBlockHash = recentBlock;
    }

    // Helper function to verify a fact based on a job output
    function verifyFact(uint256[] memory outputs) public view returns (bool) {
        bytes32 outputHash = keccak256(abi.encodePacked(outputs));
        bytes32 fact = keccak256(abi.encodePacked(PROGRAM_HASH, outputHash));

        bool isValidFact = IFactRegistry(FACTS_REGISTY).isValid(fact);
        return isValidFact;
    }

    function aggregateSharpJobs(JobOutput[] calldata outputs) external {
        // Ensure the first job is correctly linked with the current state
        JobOutput calldata firstOutput = outputs[0];
        if (firstOutput.mmrPreviousRoot != aggregatorState.currentMmrRoot)
            revert AggregationRootMismatch();
        if (firstOutput.mmrPreviousSize != aggregatorState.currentMmrSize)
            revert AggregationSizeMismatch();
        if (
            firstOutput.childBlockParentHashLow !=
            aggregatorState.oldestBlockHash
        ) revert AggregationErrorParentHashLowMismatch();
        if (
            firstOutput.childBlockParentHashHigh !=
            aggregatorState.mostRecentBlockHash
        ) revert AggregationErrorParentHashHighMismatch();

        // Iterate over the jobs outputs and ensure that jobs are correctly linked with the next ones
        uint256 len = outputs.length;
        for (uint256 i = 1; i < len - 1; ++i) {
            JobOutput calldata curOutput = outputs[i];
            JobOutput calldata nextOutput = outputs[i + 1];

            if (curOutput.mmrPreviousRoot != nextOutput.newMmrRoot)
                revert AggregationRootMismatch();

            if (curOutput.mmrPreviousSize != nextOutput.newMmrSize)
                revert AggregationSizeMismatch();

            if (
                curOutput.childBlockParentHashLow !=
                nextOutput.blockNMinusRParentHashLow
            ) revert AggregationErrorParentHashLowMismatch();

            if (
                curOutput.childBlockParentHashHigh !=
                nextOutput.blockNMinusRParentHashHigh
            ) revert AggregationErrorParentHashHighMismatch();

            // We verify the fact is valid
            bytes32 outputHash = keccak256(
                abi.encodePacked(
                    curOutput.mmrPreviousRoot,
                    curOutput.mmrPreviousSize,
                    curOutput.childBlockParentHashLow,
                    curOutput.childBlockParentHashHigh,
                    curOutput.newMmrRoot,
                    curOutput.newMmrSize,
                    curOutput.blockNMinusRParentHashLow,
                    curOutput.blockNMinusRParentHashHigh
                )
            );
            bytes32 fact = keccak256(
                abi.encodePacked(PROGRAM_HASH, outputHash)
            );
            if (!IFactRegistry(FACTS_REGISTY).isValid(fact)) {
                revert InvalidFact();
            }
        }

        // We save the latest output in the contract state for future calls
        JobOutput memory lastOutput = outputs[len - 1];
        aggregatorState.currentMmrRoot = lastOutput.newMmrRoot;
        aggregatorState.currentMmrSize = lastOutput.newMmrSize;
        aggregatorState.mostRecentBlockHash = lastOutput
            .childBlockParentHashHigh;
        aggregatorState.oldestBlockHash = outputs[0].childBlockParentHashLow;
    }
}
