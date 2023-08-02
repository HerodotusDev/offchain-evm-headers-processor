// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts/contracts/access/AccessControl.sol";

import "./interfaces/IFactsRegistry.sol";
import "./lib/Uint256Splitter.sol";

import "forge-std/console.sol";

///------------------
/// @title SharpFactsAggregator
/// @author Herodotus Dev
/// @notice Terminology:
/// `n` is the highest block number within the proving range
/// `r` is the number of blocks processed on a single SHARP job execution
/// ------------------
/// Example:
/// Blocks inside brackets are the ones processed during their SHARP job execution
//  7 [8 9 10] 11
/// n = 10
/// r = 3
/// `blockNMinusRPlusOneParentHash` = 8.parentHash (oldestHash)
/// `blockNPlusOneParentHash`       = 11.parentHash (newestHash)
/// ------------------
contract SharpFactsAggregator is Initializable, AccessControl {
    // Inline library to pack/unpack uin256 into 2 uint128 and vice versa
    using Uint256Splitter for uint256;

    // Access control
    bytes32 public constant PROVER_ROLE = keccak256("PROVER_ROLE");

    // Sharp Facts Registry
    address public FACTS_REGISTY;

    // Proving program hash
    uint256 public PROGRAM_HASH;

    // Global aggregator state
    struct AggregatorState {
        bytes32 poseidonMmrRoot;
        bytes32 keccakMmrRoot;
        uint256 mmrSize;
        bytes32 oldestParentHash;
        bytes32 mostRecentParentHash;
        uint256 mostRecentBlockNumber;
    }

    // Contract state
    AggregatorState public aggregatorState;

    // Cairo program's output
    struct JobOutput {
        bytes32 blockNPlusOneParentHashLow;
        bytes32 blockNPlusOneParentHashHigh;
        bytes32 blockNMinusRPlusOneParentHashLow;
        bytes32 blockNMinusRPlusOneParentHashHigh;
        bytes32 mmrPreviousRootPoseidon;
        bytes32 mmrPreviousRootKeccakLow;
        bytes32 mmrPreviousRootKeccakHigh;
        uint256 mmrPreviousSize;
        bytes32 mmrNewRootPoseidon;
        bytes32 mmrNewRootKeccakLow;
        bytes32 mmrNewRootKeccakHigh;
        uint256 mmrNewSize;
    }

    // Cairo program's output (packed)
    struct JobOutputPacked {
        bytes32 blockNPlusOneParentHash;
        bytes32 blockNMinusRPlusOneParentHash;
        bytes32 mmrPreviousRootPoseidon;
        bytes32 mmrPreviousRootKeccak;
        bytes32 mmrNewRootPoseidon;
        bytes32 mmrNewRootKeccak;
        uint256 mmrSizesPacked;
    }

    // poseidon_hash("brave new world")
    bytes32 public constant POSEIDON_MMR_INITIAL_ROOT =
        0x02241b3b7f1c4b9cf63e670785891de91f7237b1388f6635c1898ae397ad32dd;

    // keccak_hash("brave new world")
    bytes32 public constant KECCAK_MMR_INITIAL_ROOT =
        0xce92cc894a17c107be8788b58092c22cd0634d1489ca0ce5b4a045a1ce31b168;

    // Block number to parent hash tracker
    mapping(uint256 => bytes32) public blockNumberToParentHash;

    // Aggregator states
    mapping(bytes32 => AggregatorState) public aggregatorStates;

    // Errors
    error AggregationPoseidonRootMismatch();
    error AggregationKeccakRootMismatch();
    error AggregationSizeMismatch();
    error AggregationErrorParentHashMismatch();
    error InvalidFact();
    error UnknownParentHash();
    error NotEnoughJobs();
    error NotEnoughBlockConfirmations();
    error TooMuchBlockConfirmations();

    // Events
    event NewRangeRegistered(
        uint256 targetBlock,
        bytes32 targetBlockParentHash
    );

    /// @notice Initialize the contract
    function initialize(
        address factRegistry,
        uint256 programHash
    ) public initializer {
        // SHARP facts registry
        FACTS_REGISTY = factRegistry;

        // Proving program hash
        PROGRAM_HASH = programHash;

        // Initial aggregator state
        aggregatorState = AggregatorState({
            poseidonMmrRoot: POSEIDON_MMR_INITIAL_ROOT,
            keccakMmrRoot: KECCAK_MMR_INITIAL_ROOT,
            mmrSize: 1,
            oldestParentHash: bytes32(0),
            mostRecentParentHash: bytes32(0),
            mostRecentBlockNumber: 0
        });

        // Grant prover role to the contract deployer
        // to be able to define new aggregate ranges
        _setupRole(PROVER_ROLE, _msgSender());
    }

    modifier ensureProver() {
        require(
            hasRole(PROVER_ROLE, _msgSender()),
            "Caller has no Prover role"
        );
        _;
    }

    /// @notice Extends the proving range to be able to process newer blocks
    function registerNewRange(
        uint256 blocksConfirmations
    ) external ensureProver {
        if (blocksConfirmations < 20) {
            revert NotEnoughBlockConfirmations();
        }
        if (blocksConfirmations > 255) {
            revert TooMuchBlockConfirmations();
        }

        uint256 targetBlock = block.number - blocksConfirmations;
        bytes32 targetBlockParentHash = blockhash(targetBlock - 1);
        if (targetBlockParentHash == bytes32(0)) {
            revert UnknownParentHash();
        }

        blockNumberToParentHash[targetBlock] = targetBlockParentHash;

        if (aggregatorState.mostRecentBlockNumber < targetBlock - 1) {
            aggregatorState.mostRecentParentHash = targetBlockParentHash;
            aggregatorState.mostRecentBlockNumber = targetBlock - 1;
        }

        emit NewRangeRegistered(targetBlock, targetBlockParentHash);
    }

    /// @notice Aggregate SHARP jobs outputs (min. 2) to update the global aggregator state
    function aggregateSharpJobs(
        uint256 rightBoundStartBlock,
        JobOutputPacked[] calldata outputs
    ) external {
        if (outputs.length < 2) {
            revert NotEnoughJobs();
        }

        bytes32 rightBoundStartBlockParentHash = blockNumberToParentHash[
            rightBoundStartBlock
        ];
        if (rightBoundStartBlockParentHash == bytes32(0)) {
            revert UnknownParentHash();
        }

        // Ensure the first job is correctly linked with the current state
        JobOutputPacked calldata firstOutput = outputs[0];
        ensureValidFact(firstOutput);
        ensureContinuableFromState(firstOutput);

        uint256 len = outputs.length - 1;
        // Iterate over the jobs outputs (aside from first and last)
        // and ensure jobs are correctly linked
        for (uint256 i = 1; i < len; ++i) {
            JobOutputPacked calldata curOutput = outputs[i];
            JobOutputPacked calldata nextOutput = outputs[i + 1];

            ensureValidFact(curOutput);
            ensureConsecutiveJobs(curOutput, nextOutput);
        }

        JobOutputPacked calldata lastOutput = outputs[len - 1];
        ensureValidFact(lastOutput);

        // We save the latest output in the contract state for future calls
        (, uint256 mmrNewSize) = lastOutput.mmrSizesPacked.split128();
        aggregatorState.poseidonMmrRoot = lastOutput.mmrNewRootKeccak;
        aggregatorState.keccakMmrRoot = lastOutput.mmrNewRootKeccak;
        aggregatorState.mmrSize = mmrNewSize;
        aggregatorState.oldestParentHash = lastOutput
            .blockNMinusRPlusOneParentHash;
        aggregatorState.mostRecentParentHash = lastOutput
            .blockNPlusOneParentHash;
    }

    /// @notice Ensures the fact is registered on SHARP Facts Registry
    function ensureValidFact(JobOutputPacked memory output) internal view {
        (uint256 mmrPreviousSize, uint256 mmrNewSize) = output
            .mmrSizesPacked
            .split128();
        (
            uint256 blockNPlusOneParentHashLow,
            uint256 blockNPlusOneParentHashHigh
        ) = uint256(output.blockNPlusOneParentHash).split128();
        (
            uint256 blockNMinusRPlusOneParentHashLow,
            uint256 blockNMinusRPlusOneParentHashHigh
        ) = uint256(output.blockNMinusRPlusOneParentHash).split128();

        (
            uint256 mmrPreviousRootKeccakLow,
            uint256 mmrPreviousRootKeccakHigh
        ) = uint256(output.mmrPreviousRootKeccak).split128();
        (uint256 mmrNewRootKeccakLow, uint256 mmrNewRootKeccakHigh) = uint256(
            output.mmrNewRootKeccak
        ).split128();

        // We hash the output
        bytes32 outputHash = keccak256(
            abi.encodePacked(
                blockNPlusOneParentHashLow,
                blockNPlusOneParentHashHigh,
                blockNMinusRPlusOneParentHashLow,
                blockNMinusRPlusOneParentHashHigh,
                output.mmrPreviousRootPoseidon,
                mmrPreviousRootKeccakLow,
                mmrPreviousRootKeccakHigh,
                mmrPreviousSize,
                output.mmrNewRootPoseidon,
                mmrNewRootKeccakLow,
                mmrNewRootKeccakHigh,
                mmrNewSize
            )
        );
        // We compute the deterministic fact bytes32 value
        bytes32 fact = keccak256(abi.encodePacked(PROGRAM_HASH, outputHash));

        console.log("Fact:");
        console.logBytes32(fact);

        // TODO: comment out below
        // if (!IFactRegistry(FACTS_REGISTY).isValid(fact)) {
        //     revert InvalidFact();
        // }
    }

    /// @dev Helper function to verify a fact based on a job output
    function verifyFact(uint256[] memory outputs) public view returns (bool) {
        bytes32 outputHash = keccak256(abi.encodePacked(outputs));
        bytes32 fact = keccak256(abi.encodePacked(PROGRAM_HASH, outputHash));

        bool isValidFact = IFactRegistry(FACTS_REGISTY).isValid(fact);
        return isValidFact;
    }

    /// @notice Ensures the job output is correctly linked with the current state
    function ensureContinuableFromState(
        JobOutputPacked memory output
    ) internal view {
        (uint256 mmrPreviousSize, ) = output.mmrSizesPacked.split128();

        if (output.mmrPreviousRootPoseidon != aggregatorState.poseidonMmrRoot)
            revert AggregationPoseidonRootMismatch();

        if (output.mmrPreviousRootKeccak != aggregatorState.keccakMmrRoot)
            revert AggregationKeccakRootMismatch();

        if (mmrPreviousSize != aggregatorState.mmrSize)
            revert AggregationSizeMismatch();

        if (
            output.blockNPlusOneParentHash !=
            aggregatorState.mostRecentParentHash
        ) revert AggregationErrorParentHashMismatch();
    }

    /// @notice Ensures the job outputs are correctly linked
    function ensureConsecutiveJobs(
        JobOutputPacked memory output,
        JobOutputPacked memory nextOutput
    ) internal pure {
        (, uint256 outputMmrNewSize) = output.mmrSizesPacked.split128();
        (uint256 nextOutputMmrPreviousSize, ) = nextOutput
            .mmrSizesPacked
            .split128();

        if (output.mmrNewRootPoseidon != nextOutput.mmrPreviousRootPoseidon)
            revert AggregationPoseidonRootMismatch();

        if (output.mmrNewRootKeccak != nextOutput.mmrPreviousRootKeccak)
            revert AggregationKeccakRootMismatch();

        if (outputMmrNewSize != nextOutputMmrPreviousSize)
            revert AggregationSizeMismatch();

        if (
            output.blockNPlusOneParentHash !=
            nextOutput.blockNMinusRPlusOneParentHash
        ) revert AggregationErrorParentHashMismatch();
    }
}
