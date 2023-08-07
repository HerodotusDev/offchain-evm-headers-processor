#!venv/bin/python3
import os, time
import subprocess
import argparse
import json

def write_to_json(filename, data):
    """Helper function to write data to a json file"""
    with open(filename, 'w') as f:
        json.dump(data, f, indent=4)


# Create an ArgumentParser object
parser = argparse.ArgumentParser(description="A simple script to demonstrate argparse")

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

def run_cairo_program(input_file_path):
    """Run cairo program and return the output."""
    input_name = input_file_path.split('/')[-1].split('.')[0].removesuffix('_input')
    cmd=f"cairo-run --program={COMPILED_CAIRO_FILE_PATH} --program_input={input_file_path} --layout=starknet_with_keccak"
    cmd+=f" --cairo_pie_output {INPUT_PATH}{input_name}_pie.zip"
    os.system(cmd)

def submit_pie_to_sharp(filename):
    result = subprocess.run(
        ["cairo-sharp", "submit", "--cairo_pie", f"{INPUT_PATH}{filename.removesuffix('_input.json')}_pie.zip"], 
        text=True,
        capture_output=True
    )
    # Extract Job Key and Fact from stdout
    job_key = None
    fact = None
    for line in result.stdout.splitlines():
        if 'Job key:' in line:
            job_key = line.split(':')[-1].strip()
        if 'Fact:' in line:
            fact = line.split(':')[-1].strip()

    if job_key is None or fact is None:
        raise Exception(f"Failed to submit pie to SHARP: {result.stdout}")
    
    return job_key, fact



results = {}
for filename, filepath in zip(input_files, input_files_paths):

    if args.pie:
        print('Running program and preparing cairo PIE object...')
        print(filename)
        run_cairo_program(filepath)
        print('Done.')


    if args.sharp:
        print(f"Submitting job for {filename} to SHARP")

        job_key, fact = submit_pie_to_sharp(filename)
        results[filename] = {'job_key': job_key, 'fact': fact}
        
        write_to_json(f"{INPUT_PATH}sharp_submit_results.json", results)


