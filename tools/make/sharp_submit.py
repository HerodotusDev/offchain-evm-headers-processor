#!venv/bin/python3
import os, time
import subprocess
import argparse
import json

STARK_PRIME = 3618502788666131213697322783095070105623107215331596699973092056135872020481
def write_to_json(filename, data):
    """Helper function to write data to a json file"""
    with open(filename, 'w') as f:
        json.dump(data, f, indent=4)


# Create an ArgumentParser object
parser = argparse.ArgumentParser(description="A tool for submitting pie objects to SHARP.")

# Define command-line arguments
parser.add_argument("-pie", action="store_true", help="create pie objects")
parser.add_argument("-sharp", action="store_true", help="sends pie objects to SHARP")

# Parse the command-line arguments
args = parser.parse_args()

INPUT_PATH = "src/single_chunk_processor/data/"
FILENAME_DOT_CAIRO = "chunk_processor.cairo"
FILENAME = FILENAME_DOT_CAIRO.removesuffix('.cairo')
FILENAME_DOT_CAIRO_PATH = "src/single_chunk_processor/chunk_processor.cairo"
COMPILED_CAIRO_FILE_PATH = f"build/compiled_cairo_files/{FILENAME}.json"

print(f"Compiling {FILENAME_DOT_CAIRO} ... ")

return_code=os.system(f"cairo-compile {FILENAME_DOT_CAIRO_PATH} --output build/compiled_cairo_files/{FILENAME}.json")
if return_code==0:
    print(f"### Compilation successful.")    
else:
    print(f"### Compilation failed. Please fix the errors and try again.")
    exit(1)


PROGRAM_HASH = int(subprocess.check_output(["cairo-hash-program", "--program", f"build/compiled_cairo_files/{FILENAME}.json"]).decode(),16)


input_files=[f for f in os.listdir(INPUT_PATH) if f.endswith("_input.json")]
input_files_paths=[INPUT_PATH+f for f in input_files]

CAIROUT_OUTPUT_KEYS = [
        "from_block_number_high",
        "to_block_number_low",
        "block_n_plus_one_parent_hash_low",
        "block_n_plus_one_parent_hash_high",
        "block_n_minus_r_plus_one_parent_hash_low",
        "block_n_minus_r_plus_one_parent_hash_high",
        "mmr_last_root_poseidon",
        "mmr_last_root_keccak_low",
        "mmr_last_root_keccak_high",
        "mmr_last_len",
        "new_mmr_root_poseidon",
        "new_mmr_root_keccak_low",
        "new_mmr_root_keccak_high",
        "new_mmr_len"
    ]


def run_cairo_program(input_file_path) -> dict:
    """
    Run the cairo program on the given input file and return the program's output
    as a dictionary.
    Write the pie object to a file named <input_filename>_pie.zip to the same directory as the input file.
    """
    input_name = input_file_path.split('/')[-1].split('.')[0].removesuffix('_input')
    cmd=f"cairo-run --program={COMPILED_CAIRO_FILE_PATH} --program_input={input_file_path} --layout=starknet_with_keccak --print_output"
    cmd+=f" --cairo_pie_output {INPUT_PATH}{input_name}_pie.zip"
    stream = os.popen(cmd)
    output = stream.read()

    return parse_cairo_output(output)

def parse_cairo_output(output: str) -> dict:
    """
    Parse the output of the cairo program from stdout and return it as a dictionary.
    """
    lines = output.split("\n")
    program_output_index = lines.index("Program output:")
    # Extract field elements from the lines after 'Program output:'
    
    felts = []
    for line in lines[program_output_index + 1:]:
        line = line.strip()
        try:
            num = int(line)
            felts.append(num % STARK_PRIME)
        except ValueError:
            # If a line cannot be converted to an integer, skip it.
            continue

    assert len(felts) == len(CAIROUT_OUTPUT_KEYS), f"Expected {len(CAIROUT_OUTPUT_KEYS)} numbers in output, got {len(felts)}"
    return dict(zip(CAIROUT_OUTPUT_KEYS, felts))


def submit_pie_to_sharp(filename):
    """Submit a pie object to SHARP and return the job key and fact"""
    result = subprocess.run(
        ["cairo-sharp", "submit", "--cairo_pie", f"{INPUT_PATH}{filename.removesuffix('_input.json')}_pie.zip"], 
        text=True,
        capture_output=True
    )
    if result.returncode != 0:
        raise Exception(f"Failed to submit pie to SHARP: {result.stderr}")
    
    # Extract Job Key and Fact from stdout
    job_key, fact = None, None
    for line in result.stdout.splitlines():
        if 'Job key:' in line:
            job_key = line.split(':')[-1].strip()
        if 'Fact:' in line:
            fact = line.split(':')[-1].strip()

    if job_key is None or fact is None:
        raise Exception(f"Failed to parse job key and fact from SHARP output: {result.stdout}")
    
    return job_key, fact


if __name__ == "__main__":
    sharp_results = {}
    for input_filename, input_filepath in zip(input_files, input_files_paths):

        if args.pie:
            print(f'Running chunk processor for {input_filename} ...') 
            t0=time.time()
            output = run_cairo_program(input_filepath)
            t1=time.time()
            print(f"\t ==> Run successful. Time taken: {t1-t0} seconds.")
            expected_output = json.load(open(input_filepath.replace('_input', '_output')))
            assert output == expected_output, f"Output mismatch for {input_filename}.Expected: \n {expected_output}\n got: \n{output}"
            print(f"\t ==> Run is correct. Output matches precomputed output.")
            print(f"\t ==> PIE Object written to {INPUT_PATH}{input_filename.removesuffix('_input.json')}_pie.zip \n")


        if args.sharp:
            print(f"Submitting job for {input_filename} to SHARP ...")
            
            job_key, fact = submit_pie_to_sharp(input_filename)
            print(f"\t ==> Job submitted successfully to SHARP.")
            print(f"\t ==> Job key: {job_key}, Fact: {fact} \n")

            sharp_results[input_filename] = {'job_key': job_key, 'fact': fact}
            
            write_to_json(f"{INPUT_PATH}sharp_submit_results.json", sharp_results)
    

    if args.pie:
        print(f"All runs successful. PIE objects written to {INPUT_PATH}")
    if args.sharp:
        print(f"All jobs submitted successfully. Results written to {INPUT_PATH}sharp_submit_results.json")


