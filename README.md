#### Create a virtual environment and install the dependencies (one time setup)

```bash
make setup
```
#### Compile all Cairo or Starknet programs

```bash
make build
```

#### Run and profile cairo programs of interest (interactive script) 
_Profiling graphs will be stored under `build/profiling/`_
```bash
make run-profile
```
#### Run cairo programs of interest (interactive script) 

```bash
make run
```
#### Prepare inputs / Precompute outputs for SHARP 
_Data will be stored under `src/single_chunk_processor/data`_
```bash
make prepare-processor-input
```
#### Get main program hash
_Returns the program hash of the main program (chunk_processor.cairo)_
```bash
make get-program-hash
```



## Processor simulated usage : 
 1) Modify last line of `tools/make/prepare_inputs_api.py` 's to choose the start block number and batch size.  
 2) Run `make prepare-processor-input` to generate all the cairo .json inputs under `src/single_chunk_processor/data`.
 3) Run `make run` and choose `chunk_processor.cairo`. 
 4) Select which input to run. 


Max resources per job : 

Steps = 16777216  
RC = 1048576  
Bitwise = 262144  
Keccaks = 8192  
Poseidon = 524288  


Current processor program hash : 0x258fbe9cbf11c87d1dd0ded5f70d494c6a2977076b672738cbdffddcab80581