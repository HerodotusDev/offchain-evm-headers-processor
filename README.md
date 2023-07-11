#### Create a virtual environment and install the dependencies

```bash
make setup
```
#### Compile all Cairo or Starknet programs

```bash
make build
```

#### Run and profile cairo programs of interest (interactive script) 

```bash
make run-profile
```


## Processor simulated usage : 
 1)  Modify `tools/make/processor_input.json` with the relevant block numbers if needed. Make sure `previous_block_high > previous_block_low > from_block_number_high > to_block_number_low` and `previous_block_low - 1 = from_block_number_high`.
 2) Run `make prepare-processor-input` to generate the `src/single_chunk_processor/chunk_processor_input.json` file.
 3) Run `make run` and choose `chunk_processor.cairo`
