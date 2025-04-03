import json
import argparse


def convert_numbers_to_hex_strings(data):
    """
    Recursively converts integers in data to hexadecimal strings.
    Handles dictionaries, lists, integers, floats, and other types.
    """
    if isinstance(data, dict):
        return {
            key: convert_numbers_to_hex_strings(value) for key, value in data.items()
        }
    elif isinstance(data, list):
        return [convert_numbers_to_hex_strings(item) for item in data]
    elif isinstance(data, int):
        return hex(data)
    elif isinstance(data, float):
        return str(data)
    else:
        return data


def main(input_file, output_file):
    # Load JSON data from input file
    with open(input_file, "r") as f:
        json_data = json.load(f)

    # Convert integers in JSON to hexadecimal strings
    converted_data = convert_numbers_to_hex_strings(json_data)

    # Save the converted JSON data to output file
    with open(output_file, "w") as f:
        json.dump(converted_data, f, indent=4)

    print(f"Converted numbers to hexadecimal strings in '{output_file}'")


if __name__ == "__main__":
    # Set up argument parsing for input and output file paths
    parser = argparse.ArgumentParser(
        description="Convert integers in JSON to hexadecimal strings."
    )
    parser.add_argument("input_file", help="Path to the input JSON file")
    parser.add_argument("output_file", help="Path to save the output JSON file")

    # Parse arguments and run the main function
    args = parser.parse_args()
    main(args.input_file, args.output_file)
