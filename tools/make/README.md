# Utility Scripts


## `setup.sh`
### Usage : `make setup`

This script sets up a virtual environment within the venv/ directory and installs all the necessary Python packages. Additionally, it updates the environment variable PYTHONPATH to ensure Python scripts within the tools/ directory can be executed from any location.


## `build.sh`

### Usage : `make build`

This script compiles all Cairo files located in:
- `src/`
- `tests/cairo_programs/`

The compiled outputs are stored in `build/compiled_cairo_files/`.

## `launch_cairo_files.py`

### Usage : `make run` or `make run-profile`

This script provides an option to choose a Cairo file for execution from:
- `src/single_chunk_processor/chunk_processor.cairo`  
- All the Cairo files within  `tests/cairo_programs/`

After selection, the script compiles the chosen file and runs it, using input from a corresponding file located in the same directory. The input file should have the same name as the Cairo file but with the `_input.json` extension in place of `.cairo.`

For the `chunk_processor.cairo` file, an additional prompt allows selection from input files ending in `_input.json` within the `src/single_chunk_processor/data` directory.


If `make-run-profile` is chosen, the Cairo file is executed with profiling enabled. The resultant profile graph is saved to `build/profiling/`.

## `prepare_inputs_api.py`

### Usage : `make prepare-processor-input`

This Python script prepares inputs for the chunk processor and precomputes the expected outputs. To specify which inputs to prepare, modify the main function at the end of this file.

The `prepare_full_chain_inputs` function parameters include:

 - `from_block_number_high` : Highest block number to include in the input  
 - `to_block_number_low` : Lowest block number to include in the input
 - `batch_size` : Number of blocks to include in each batch
 - (Optional) `initial_peaks` : A dictionary containing the lists of initial peaks (from left to right) for both the Poseidon and Keccak MMR. If not specified, the initial peaks are the following :
```JSON
{
    "poseidon": [968420142673072399148736368629862114747721166432438466378474074601992041181],
    "keccak": [93435818137180840214006077901347441834554899062844693462640230920378475721064]
}
```  
 These values correspond to the Poseidon and Keccak hashes of the string `b'brave new world'`. They are the initial peaks of the MMRs used by the chunk processor.

 - (Optional) `initial_mmr_size` : The initial size of the MMR. If not specified, the initial size is 1.

  - (Optional) `initial_mmr_root` : The initial root of both the Poseidon and Keccak MMR. If not specified, they correspond to the initial peaks : 
```JSON
{
    "poseidon": 968420142673072399148736368629862114747721166432438466378474074601992041181, 
    "keccak": 93435818137180840214006077901347441834554899062844693462640230920378475721064
}
```

The primary operations of this function are: 
 1. Splitting blocks to process into batches of size `batch_size`, except for the last batch which can be smaller.
 2. Fetching the block data for each chunk from the RPC node provided in the .env file at the root of the repository.
 3. Using an internal Rust API to compute the expected output for each chunk, which simulates the chunk processor's actions.
 4. Writing the inputs and expected outputs to src/single_chunk_processor/data/. Those can be used later by the chunk processor and the script `sharp_submit.py`.





## `sharp_submit.py`

### Usages :
1) `make batch-cairo-pie`:  
    Runs the chunk processor on all the inputs files under `src/single_chunk_processor/data/` and create PIE objects for each of them in the same directory.
    It also checks that the output of each run matches the precomputed output in the same directory.
2) `make batch-sharp-submit`:  
    Submits all the PIE objects under `src/single_chunk_processor/data/` to SHARP. Results, including job keys and facts, are saved to  `src/single_chunk_processor/data/sharp_submit_results.json`.
3) `make batch-run-and-submit`:  
    Combines the processes of 1) and 2) into a single command.



