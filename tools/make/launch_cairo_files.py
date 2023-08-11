#!venv/bin/python3
import os
from os import listdir
from os.path import isfile, join
import readline
import argparse
import inquirer

# Create an ArgumentParser object
parser = argparse.ArgumentParser(description="A tool for running cairo programs.")

# Define command-line arguments
parser.add_argument("-profile", action="store_true", help="force pprof profile")
parser.add_argument("-pie", action="store_true", help="create PIE object")

# Parse the command-line arguments
args = parser.parse_args()

if args.profile:
    print("Profiling is enabled")
else:
    print("Profiling is disabled")



CAIRO_PROGRAMS_FOLDERS = ["tests/cairo_programs/","src/single_chunk_processor"]
DEP_FOLDERS = ["src/"]

CAIRO_PROGRAMS = []
for folder in CAIRO_PROGRAMS_FOLDERS:
    CAIRO_PROGRAMS+= [join(folder, f) for f in listdir(folder) if isfile(join(folder, f)) if f.endswith('.cairo')]

# Get all dependency files
DEP_FILES = []
for dep_folder in DEP_FOLDERS:
    DEP_FILES += [join(dep_folder, f) for f in listdir(dep_folder) if isfile(join(dep_folder, f)) if f.endswith('.cairo')]

def mkdir_if_not_exists(path: str):
    isExist = os.path.exists(path)
    if not isExist:
        os.makedirs(path)
        print(f"Directory created : {path} ")

mkdir_if_not_exists("build")
mkdir_if_not_exists("build/compiled_cairo_files")
mkdir_if_not_exists("build/profiling")

def complete(text, state):
    volcab = [x.split('/')[-1] for x in CAIRO_PROGRAMS]
    results = [x for x in volcab if x.startswith(text)] + [None]
    return results[state]

readline.parse_and_bind("tab: complete")
readline.set_completer(complete)


def find_file_recurse():
    not_found=True
    global JSON_INPUT_PATH
    while not_found:
        global FILENAME_DOT_CAIRO_PATH
        global FILENAME_DOT_CAIRO
        FILENAME_DOT_CAIRO = input('\n>>> Enter .cairo file name to run or double press <TAB> for autocompleted suggestions : \n\n')
        for cairo_path in CAIRO_PROGRAMS:
            if cairo_path.endswith(FILENAME_DOT_CAIRO):
                FILENAME_DOT_CAIRO_PATH = cairo_path
                not_found=False
                break
        if not_found:
            print(f"### File '{FILENAME_DOT_CAIRO}' not found in the Cairo programs folders.")
        else:
            FILENAME = FILENAME_DOT_CAIRO.removesuffix('.cairo')
            JSON_INPUT_PATH = FILENAME_DOT_CAIRO_PATH.replace('.cairo', '_input.json')

        if FILENAME_DOT_CAIRO == "chunk_processor.cairo":
            json_files = [f for f in listdir("src/single_chunk_processor/data") if f.endswith('_input.json')]
            if not json_files:
                print("### No JSON files found in the directory 'src/single_chunk_processor/data'.")
                return
            print("\n>>> Select the input JSON file:")
            questions = [
                inquirer.List('file',
                              message="Choose a file",
                              choices=json_files,
                              ),
            ]
            answers = inquirer.prompt(questions)
            JSON_INPUT_PATH = join("src/single_chunk_processor/data", answers['file'])
            print(f"Selected JSON file: {JSON_INPUT_PATH}")


find_file_recurse()

print(f"Selected Cairo file: {FILENAME_DOT_CAIRO_PATH}")

FILENAME = FILENAME_DOT_CAIRO.removesuffix('.cairo')

input_exists = os.path.exists(JSON_INPUT_PATH)
if input_exists:
    print(f"Input file found! : {JSON_INPUT_PATH} ")

mkdir_if_not_exists(f"build/profiling/{FILENAME}")

# Combine main and dependency files
ALL_FILES = CAIRO_PROGRAMS + DEP_FILES


compile_success = False
while not compile_success:

    print(f"Compiling {FILENAME_DOT_CAIRO} ... ")

    return_code=os.system(f"cairo-compile {FILENAME_DOT_CAIRO_PATH} --output build/compiled_cairo_files/{FILENAME}.json")
    if return_code==0:
        compile_success=True
    else:
        print(f"### Compilation failed. Please fix the errors and try again.")
        find_file_recurse()


profile_arg = f" --profile_output ./build/profiling/{FILENAME}/profile.pb.gz"
pie_arg = f" --cairo_pie_output ./build/profiling/{FILENAME}/{FILENAME}_pie.zip"
if input_exists:
    print(f"Running {FILENAME_DOT_CAIRO} with input {JSON_INPUT_PATH} ... ")

    cmd=f"cairo-run --program=build/compiled_cairo_files/{FILENAME}.json --program_input={JSON_INPUT_PATH} --layout=starknet_with_keccak --print_output"
    if args.profile:
        cmd+=profile_arg
    else:
        cmd+=" --print_info"
    if args.pie:
        cmd+=pie_arg

    os.system(cmd)

else:
    print(f"Running {FILENAME_DOT_CAIRO} ... ")

    cmd=f"cairo-run --program=build/compiled_cairo_files/{FILENAME}.json --layout=starknet_with_keccak"
    if args.profile:
        cmd+=profile_arg
    else:
        cmd+=" --print_info"
    if args.pie:
        cmd+=pie_arg

    os.system(cmd)


if args.profile:
    print(f"Running profiling tool for {FILENAME_DOT_CAIRO} ... ")
    os.system(f"cd ./build/profiling/{FILENAME} && go tool pprof -png profile.pb.gz ")

