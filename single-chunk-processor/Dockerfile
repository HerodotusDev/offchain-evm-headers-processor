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



CMD ["cairo-compile --version"]