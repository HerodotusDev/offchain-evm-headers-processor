"""Utility functions."""

import json
import os
import shutil
import requests
from tools.py.mmr import is_valid_mmr_size


def split_128(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def from_uint256(a):
    """Takes in uint256-ish tuple, returns value."""
    return a[0] + (a[1] << 128)


def rpc_request(url, rpc_request):
    headers = {"Content-Type": "application/json"}
    response = requests.post(url=url, headers=headers, data=json.dumps(rpc_request))
    # print(f"Status code: {response.status_code}")
    # print(f"Response content: {response.content}")
    return response.json()


def bytes_to_8_bytes_chunks_little(input_bytes):
    # Split the input_bytes into 8-byte chunks
    byte_chunks = [input_bytes[i : i + 8] for i in range(0, len(input_bytes), 8)]
    # Convert each chunk to little-endian integers
    little_endian_ints = [
        int.from_bytes(chunk, byteorder="little") for chunk in byte_chunks
    ]
    return little_endian_ints


def bytes_to_8_bytes_chunks(input_bytes):
    # Split the input_bytes into 8-byte chunks
    byte_chunks = [input_bytes[i : i + 8] for i in range(0, len(input_bytes), 8)]
    # Convert each chunk to big-endian integers
    big_endian_ints = [int.from_bytes(chunk, byteorder="big") for chunk in byte_chunks]
    return big_endian_ints


def write_to_json(filename, data):
    """Helper function to write data to a json file"""
    with open(filename, "w") as f:
        json.dump(data, f, indent=4)


def create_directory(path: str):
    if not os.path.exists(path):
        os.makedirs(path)
        print(f"Directory created: {path}")


def clear_directory(path):
    """Delete all files and sub-directories in a directory without deleting the directory itself."""
    for filename in os.listdir(path):
        file_path = os.path.join(path, filename)
        try:
            if os.path.isfile(file_path) or os.path.islink(file_path):
                os.unlink(file_path)
            elif os.path.isdir(file_path):
                shutil.rmtree(file_path)
        except Exception as e:
            print(f"Failed to delete {file_path}. Reason: {e}")


def get_files_from_folders(folders, ext=".cairo"):
    return [
        os.path.join(folder, f)
        for folder in folders
        for f in os.listdir(folder)
        if os.path.isfile(os.path.join(folder, f)) and f.endswith(ext)
    ]


def validate_initial_params(initial_params: dict):
    assert (
        type(initial_params) == dict
    ), f"initial_params should be a dictionary. Got {type(initial_params)} instead"
    assert set(initial_params) == {
        "mmr_peaks",
        "mmr_size",
        "mmr_roots",
    }, f"initial_params should have keys 'mmr_peaks', 'mmr_size' and 'mmr_roots'. Got {initial_params.keys()} instead"
    assert (
        type(initial_params["mmr_peaks"]) == dict
        and type(initial_params["mmr_roots"]) == dict
        and type(initial_params["mmr_size"]) == int
    ), f"mmr_peaks and mmr_roots should be dictionaries and mmr_size should be an integer. Got {type(initial_params['mmr_peaks'])}, {type(initial_params['mmr_roots'])} and {type(initial_params['mmr_size'])} instead"
    assert set(initial_params["mmr_peaks"].keys()) & set(
        initial_params["mmr_roots"].keys()
    ) == {
        "poseidon",
        "keccak",
    }, f"peaks and mmr_roots should have keys 'poseidon' and 'keccak'. Got {initial_params['mmr_peaks'].keys()} and {initial_params['mmr_roots'].keys()} instead"
    assert type(initial_params["mmr_peaks"]["poseidon"]) == list and type(
        initial_params["mmr_peaks"]["keccak"] == list
    ), f"mmr_peaks['poseidon'] and mmr_peaks['keccak'] should be lists. Got {type(initial_params['mmr_peaks']['poseidon'])} and {type(initial_params['mmr_peaks']['keccak'])} instead"
    assert len(initial_params["mmr_peaks"]["poseidon"]) == len(
        initial_params["mmr_peaks"]["keccak"]
    ), f"mmr_peaks['poseidon'] and mmr_peaks['keccak'] should have the same length. Got {len(initial_params['mmr_peaks']['poseidon'])} and {len(initial_params['mmr_peaks']['keccak'])} instead"
    assert is_valid_mmr_size(
        initial_params["mmr_size"]
    ), f"Invalid MMR size: {initial_params['mmr_size']}"
