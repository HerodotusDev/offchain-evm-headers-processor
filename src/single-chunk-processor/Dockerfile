FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /usr/src

RUN apt update
RUN apt -y install software-properties-common
RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt -y install python3.9
RUN apt -y install python3-pip
RUN apt -y install libgmp3-dev
RUN apt -y install wget

ENTRYPOINT [ "python3.9" ]

RUN pip3 install ecdsa fastecdsa sympy
RUN wget https://github.com/starkware-libs/cairo-lang/releases/download/v0.10.3/cairo-lang-0.10.3.zip
RUN pip3 install cairo-lang-0.10.3.zip
RUN rm cairo-lang-0.10.3.zip

# Prepare output dir
RUN mkdir -p output/single-chunk-processor

# Prepare compilation output dir
RUN touch output/single-chunk-processor/compiled.json

# Compile cairo files
RUN cairo-compile src/main.cairo --output=output/single-chunk-processor/compiled.json

# Prepare compilation output dir
RUN touch output/single-chunk-processor/trace.bin
RUN touch output/single-chunk-processor/memory.bin

# Run the compiled program
RUN cairo-run --program=output/single-chunk-processor/compiled.json --layout=all --print_output --trace_file=./output/single-chunk-processor/trace.bin --memory_file=./output/single-chunk-processor/memory.bin

CMD ["cairo-compile --version"]