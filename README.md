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
 1) Modify last line of `tools/make/prepare_inputs_api.py` 's to choose the start block number and batch size.  
 2) Run `make prepare-processor-input` to generate all the cairo .json inputs under `src/single_chunk_processor/data`.
 3) Run `make run` and choose `chunk_processor.cairo`. 
 4) Select which input to run. 
