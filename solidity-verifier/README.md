### solidity-verifier

This Solidity verifier aggregates jobs sent to SHARP and verifies the correctness of the results.

Pre-requisites:

-   Foundry
-   Solidity

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
forge test --match-test testVerifyInvalidFact -vvv --rpc-url="http://GOERLI_RPC"
```

Herodotus Dev - 2023
