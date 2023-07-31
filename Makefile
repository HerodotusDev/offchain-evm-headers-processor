.PHONY: build test coverage
cairo_files = $(shell find ./tests/cairo_programs -name "*.cairo")

build:
	$(MAKE) clean
	./tools/make/build.sh

setup:
	./tools/make/setup.sh

# test:
# 	protostar test

run-profile:
	@echo "A script to select, compile, run & profile one Cairo file"
	./tools/make/launch_cairo_files.py -profile

run:
	@echo "A script to select, compile & run one Cairo file"
	@echo "Total number of steps will be shown at the end of the run." 
	./tools/make/launch_cairo_files.py

prepare-processor-input:
	@echo "Prepare chunk_processor_input.json data with the parameters in tools/make/processor_input.json"
	./tools/make/prepare_inputs_api.py

clean:
	rm -rf build/compiled_cairo_files
	mkdir -p build
	mkdir build/compiled_cairo_files


Max resources per job : 

Steps = 16777216
RC = 1048576
Bitwise = 262144
Keccaks = 8192
Poseidon = 524288

