# Loop on all inputs under src/single_chunk_processor/data and submit all jobs to SHARP.
import os, time

PATH = "src/single_chunk_processor/data/"

for filename in os.listdir(PATH):
    if filename.endswith("_input.json"):
        print('Running program and preparing cairo PIE object...')
        time.sleep(0.5)

        print(f"Submitting job for {filename} to SHARP")
        # os.system(f"python3 tools/make/sharp_submit.py {PATH}{filename}")
        time.sleep(0.5)
    else:
        continue