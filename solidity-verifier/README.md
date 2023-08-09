### solidity-verifier

This Solidity verifier aggregates jobs (i.e., outputs from our Cairo program that serves as an EVM header off-chain accumulator) sent to the SHARP prover.

When the results are correctly verified, the global state of the contract is updated and reflects the new state.

The latest state of such a contract gives access to two Merkle Mountain Range (MMR) trees comprising the same elements but hashed with a different hash function (i.e., Poseidon and Keccak).

Considering that the two MMRs contain the same elements, the global `mmrSize` grows at the same rate for both trees.

Pre-requisites:

-   Solidity (with solc >= 0.8.0)
-   Foundry
-   Yarn
-   Node.js (>= v18.16.1)

[Here](src/SharpFactsAggregator.sol) is the main contract.

Note: the aggregation state is stored in the `SharpFactsAggregator` contract and can be retrieved by calling `getAggregatorState()`.

## Add RPC

In `foundry.toml`, please define:

```toml
[rpc_endpoints]
goerli=GOERLI_URL
```

## Getting Started

```sh
# Navigate to solidity-verifier
cd solidity-verifier

# Install node_modules
yarn install

# Install submodules
forge install

# Build contracts
forge build

# Test
forge test
```

Herodotus Dev - 2023
