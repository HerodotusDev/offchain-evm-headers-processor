// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "./interfaces/IFactsRegistry.sol";
import "forge-std/console.sol";

/// @title SharpFactsAggregator
/// @author Herodotus Dev
/// @notice Terminology:
/// `n` is the highest block number within the proving range
/// `r` is the number of blocks processed on a single SHARP job execution
/// ------------------
/// Example:
/// Blocks inside brackets are the ones processed during their SHARP job execution
//  7 [8, 9, 10] 11
/// n = 10
/// r = 3
/// `blockNMinusRPlusOneParentHash` = 8.parentHash (oldestHash)
/// `blockNPlusOneParentHash`       = 11.parentHash (newestHash)
/// ------------------
contract SharpFactsAggregator is Initializable {
    // Sharp Facts Registry
    address public immutable FACTS_REGISTY;

    // Proving program hash
    uint256 public immutable PROGRAM_HASH;

    // Errors
    error AggregationRootMismatch();
    error AggregationSizeMismatch();
    error AggregationErrorParentHashMismatch();
    error InvalidFact();

    // Aggregator state
    struct AggregatorState {
        bytes32 currentMmrRoot;
        uint256 currentMmrSize;
        bytes32 mostRecentParentHash;
        bytes32 oldestParentHash;
    }

    // Cairo program's output
    struct JobOutput {
        bytes32 blockNPlusOneParentHashLow;
        bytes32 blockNPlusOneParentHashHigh;
        bytes32 blockNMinusRPlusOneParentHashLow;
        bytes32 blockNMinusRPlusOneParentHashHigh;
        bytes32 mmrPreviousRoot;
        bytes32 mmrNewRoot;
        uint256 mmrPreviousSize;
        uint256 mmrNewSize;
    }

    // Cairo program's output packed
    struct JobOutputPacked {
        bytes32 blockNPlusOneParentHash;
        bytes32 blockNMinusRPlusOneParentHash;
        bytes32 mmrPreviousRoot;
        bytes32 mmrNewRoot;
        uint256 mmrSizesPacked;
    }

    // poseidon_hash(1, "brave new world")
    bytes32 public constant MMR_INITIAL_ROOT =
        0x02301feaab05d57f9bebc88b0f1c32e754934342a432a1e8a030e634270fcb0e;

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

        aggregatorState.currentMmrRoot = MMR_INITIAL_ROOT;
        aggregatorState.currentMmrSize = 1;
        aggregatorState.mostRecentParentHash = recentBlock;
        aggregatorState.oldestParentHash = recentBlock;
    }

    function aggregateSharpJobs(JobOutputPacked[] calldata outputs) external {
        assert(outputs.length > 0);

        // Ensure the first job is correctly linked with the current state
        JobOutputPacked calldata firstOutput = outputs[0];
        ensureValidFact(firstOutput);
        ensureContinuableFromState(firstOutput);

        uint256 len = outputs.length - 1;
        if (len > 0) {
            // Iterate over the jobs outputs (except first and last)
            // and ensure jobs are correctly linked
            for (uint256 i = 1; i < len; ++i) {
                JobOutputPacked memory curOutput = outputs[i];
                JobOutputPacked memory nextOutput = outputs[i + 1];

                ensureValidFact(curOutput);
                ensureConsecutiveJobs(curOutput, nextOutput);
            }
        }

        JobOutputPacked memory lastOutput = outputs[len - 1];
        ensureValidFact(lastOutput);

        // We save the latest output in the contract state for future calls
        (, uint256 mmrNewSize) = split128(lastOutput.mmrSizesPacked);
        aggregatorState.currentMmrRoot = lastOutput.mmrNewRoot;
        aggregatorState.currentMmrSize = mmrNewSize;
        aggregatorState.oldestParentHash = lastOutput
            .blockNMinusRPlusOneParentHash;
        aggregatorState.mostRecentParentHash = lastOutput
            .blockNPlusOneParentHash;
    }

    function ensureValidFact(JobOutputPacked memory output) internal view {
        (uint256 mmrPreviousSize, uint256 mmrNewSize) = split128(
            output.mmrSizesPacked
        );
        (
            uint256 blockNPlusOneParentHashLow,
            uint256 blockNPlusOneParentHashHigh
        ) = split128(uint256(output.blockNPlusOneParentHash));
        (
            uint256 blockNMinusRPlusOneParentHashLow,
            uint256 blockNMinusRPlusOneParentHashHigh
        ) = split128(uint256(output.blockNMinusRPlusOneParentHash));

        // We verify the fact is valid
        bytes32 outputHash = keccak256(
            abi.encodePacked(
                blockNPlusOneParentHashLow,
                blockNPlusOneParentHashHigh,
                blockNMinusRPlusOneParentHashLow,
                blockNMinusRPlusOneParentHashHigh,
                output.mmrPreviousRoot,
                output.mmrNewRoot,
                mmrPreviousSize,
                mmrNewSize
            )
        );
        bytes32 fact = keccak256(abi.encodePacked(PROGRAM_HASH, outputHash));

        if (!IFactRegistry(FACTS_REGISTY).isValid(fact)) {
            revert InvalidFact();
        }
    }

    // Helper function to verify a fact based on a job output
    function verifyFact(uint256[] memory outputs) public view returns (bool) {
        bytes32 outputHash = keccak256(abi.encodePacked(outputs));
        bytes32 fact = keccak256(abi.encodePacked(PROGRAM_HASH, outputHash));

        bool isValidFact = IFactRegistry(FACTS_REGISTY).isValid(fact);
        return isValidFact;
    }

    function ensureContinuableFromState(
        JobOutputPacked memory output
    ) internal view {
        (uint256 mmrPreviousSize, ) = split128(output.mmrSizesPacked);

        if (output.mmrPreviousRoot != aggregatorState.currentMmrRoot)
            revert AggregationRootMismatch();

        if (mmrPreviousSize != aggregatorState.currentMmrSize)
            revert AggregationSizeMismatch();

        if (
            output.blockNMinusRPlusOneParentHash !=
            aggregatorState.oldestParentHash
        ) revert AggregationErrorParentHashMismatch();

        if (
            output.blockNPlusOneParentHash !=
            aggregatorState.mostRecentParentHash
        ) revert AggregationErrorParentHashMismatch();
    }

    function ensureConsecutiveJobs(
        JobOutputPacked memory output,
        JobOutputPacked memory nextOutput
    ) internal pure {
        (, uint256 outputMmrNewSize) = split128(output.mmrSizesPacked);
        (uint256 nextOutputMmrPreviousSize, ) = split128(
            nextOutput.mmrSizesPacked
        );

        if (output.mmrNewRoot != nextOutput.mmrPreviousRoot)
            revert AggregationRootMismatch();

        if (outputMmrNewSize != nextOutputMmrPreviousSize)
            revert AggregationSizeMismatch();

        if (
            output.blockNPlusOneParentHash !=
            nextOutput.blockNMinusRPlusOneParentHash
        ) revert AggregationErrorParentHashMismatch();
    }

    function split128(
        uint256 a
    ) internal pure returns (uint256 lower, uint256 upper) {
        // uint256 mask = (1 << 128) - 1;
        // return (a & mask, a >> 128);
        assembly {
            // sub(exp(2, 128), 1) == 340282366920938463463374607431768211455
            lower := and(a, 340282366920938463463374607431768211455)
            upper := shr(128, a)
        }
    }
}
