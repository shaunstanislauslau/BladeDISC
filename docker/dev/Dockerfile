ARG BASEIMAGE=nvidia/cuda:10.0-cudnn7-devel-ubuntu18.04
FROM ${BASEIMAGE}

COPY docker/scripts /install/scripts

RUN bash /install/scripts/find-fastest-apt.sh && \
    apt-get install -y python3 python3-pip git curl vim libssl-dev wget unzip openjdk-11-jdk && \
    pip3 install --upgrade pip && \
    ln -s /usr/bin/python3 /usr/bin/python && \
    bash /install/scripts/install-cmake.sh && \
    bash /install/scripts/install-bazel.sh && \
    bash /install/scripts/install-python.sh

ENV PATH="/opt/cmake/bin:${PATH}"