# Off-chain EVM Headers Processor

This repository implements the logic of building and maintaining two Merkle Mountain Ranges (MMRs) containing only provably valid Ethereum block headers.

Visualization of an MMR
![merkle mountain range tree](.github/mmr.png)

Building the MMRs happens off-chain and is proven using a Cairo program in the `src` directory.
The CAIRO program takes as an input a blockhash passed by the verifier to then provide preimages to the given blockhash or a decoded parent hash that must be valid block headers.

Visualization of the linkage between blocks.
![linked blocks](.github/blocks-linkage.png?raw=true)

The 2 MMRs store the same data and have the same size however are built with two different hash functions:

- Poseidon over the stark field
- Keccak256
  The values at the bottom of the MMR are keccak/poseidon hashes of the RLP encoded block headers.

The Starkware SHARP generates the proofs, and the proof verification happens on-chain. The resulting facts are then aggregated by the contracts implemented in the directory `solidity-verifier`.

## Make commands

### Create a virtual environment and install the dependencies (one-time setup)

```bash
make setup
```
After that and every time you get back to the repo, you will need to activate the virtual environment by doing:

```bash
source venv/bin/activate
```

The repository uses RPC providers to fetch block data.  
You will need to store the RPC urls for Mainnet and Goerli by creating a `.env` file in the root directory of the repository and adding the following lines to it:

```plaintext
RPC_URL_MAINNET=<RPC_URL_MAINNET>
RPC_URL_GOERLI=<RPC_URL_GOERLI>
```

### Compile all Cairo programs

```bash
make build
```

### Run and profile cairo programs of interest (interactive script)

_Profiling graphs will be stored under `build/profiling/`_

```bash
make run-profile
```

### Run cairo programs of interest (interactive script)

```bash
make run
```

### Prepare inputs / Precompute outputs for SHARP

_Data will be stored under `src/single_chunk_processor/data`_

```bash
make prepare-processor-input
```

### SHARP preparation/submission

_Reads/Writes the data from `src/single_chunk_processor/data`_

```bash
make batch-cairo-pie # Run all chunks and create PIE objects for SHARP
make batch-sharp-submit # Send PIE objects to SHARP
make batch-run-and-submit # Both
```

### Get the main program hash

_Returns the program hash of the main program (chunk_processor.cairo)_

```bash
make get-program-hash
```

#### One chunk simulated usage :

1. Modify the last line of `tools/make/prepare_inputs_api.py` to choose the start block number and batch size.
2. Run `make prepare-processor-input` to generate all the cairo .json inputs under `src/single_chunk_processor/data`.
3. Run `make run` and choose `chunk_processor.cairo`.
4. Select which input to run.

See [src/single_chunk_processor/README.md](src/single_chunk_processor/README.md) for more details about the single-chunk processor.

## Solidity verifier (SHARP verifier)

See [solidity-verifier/README.md](solidity-verifier/README.md) for more details.

### Additional data

#### Max Resources Per SHARP Job:

| Resource | Value      |
| -------- | ---------- |
| Steps    | 16,777,216 |
| RC       | 1,048,576  |
| Bitwise  | 262,144    |
| Keccaks  | 8,192      |
| Poseidon | 524,288    |

#### Current processor program hash :

`0x21876b34efae7a9a59580c4fb0bfc7971aecebce6669a475171fe0423c0a784`

Herodotus Dev - 2023.
