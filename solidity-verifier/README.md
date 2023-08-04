### solidity-verifier

This Solidity verifier aggregates jobs sent to SHARP and verifies the correctness of the results.

Pre-requisites:

-   Foundry
-   Solidity

## Add RPC

In `foundry.toml`, please define:

```toml
[rpc_endpoints]
goerli=GOERLI_URL
```

## Getting Started

```sh
#Navigate to solidity-verifier
cd solidity-verifier

#Install node_modules
yarn install

#Install submodules
forge install

#Build contracts
forge build

#Test
forge test
```

Herodotus Dev - 2023
