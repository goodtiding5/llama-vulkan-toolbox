# Dockerfile for llama.cpp with Vulkan backend
# Multi-stage build: Builder image compiles llama.cpp, Release image contains only runtime

# Build arguments from .toolbox.env
ARG BASE_IMAGE=docker.io/library/ubuntu:26.04
ARG BUILD_PLATFORM=linux
ARG LLAMA_HOME=/opt/llama
ARG WORKSPACE_DIR=/workspace
ARG LLAMA_REL_TAG=latest

# ========================================
# Stage 1: Builder
# ========================================
FROM ${BASE_IMAGE} AS builder

ARG BUILD_PLATFORM
ARG LLAMA_HOME
ARG WORKSPACE_DIR
ARG LLAMA_REL_TAG

ENV DEBIAN_FRONTEND=noninteractive

# Create workspace
RUN mkdir -p ${WORKSPACE_DIR}

# Set working directory
WORKDIR ${WORKSPACE_DIR}

# Copy scripts
COPY scripts/ scripts/
COPY .toolbox.env ./

# Create llama user and set up workspace
RUN useradd -m -d ${WORKSPACE_DIR} -s /bin/bash llama && \
    rm -rf /home/ubuntu && \
    chown -R llama:llama ${WORKSPACE_DIR} && \
    usermod -aG sudo llama || true

# Create /.dockerenv to pass container checks
RUN touch /.dockerenv

# Run build scripts sequentially as root (with container env)
RUN CONTAINER_ID=docker bash ./scripts/01-install-toolchain.sh && \
    bash ./scripts/02-build-llamacpp.sh --checkout --build --install

# ========================================
# Stage 2: Release
# ========================================
FROM ${BASE_IMAGE} AS release

ARG LLAMA_HOME
ARG WORKSPACE_DIR

ENV DEBIAN_FRONTEND=noninteractive \
    LLAMA_HOME=/opt/llama

# Create llama user with /workspace as home and remove default ubuntu user
RUN useradd -m -d ${WORKSPACE_DIR} -s /bin/bash llama && \
    rm -rf /home/ubuntu && \
    chown -R llama:llama ${WORKSPACE_DIR}

# Copy llama.cpp build from builder
COPY --from=builder --chown=llama:llama ${LLAMA_HOME} ${LLAMA_HOME}

# Copy inference script
COPY scripts/03-run-inference.sh ${WORKSPACE_DIR}/

# Copy dependency installation script
COPY scripts/99-install-dependents.sh ${WORKSPACE_DIR}/

# Install runtime dependencies
WORKDIR ${WORKSPACE_DIR}
RUN bash ./99-install-dependents.sh

# Set up environment
ENV PATH=/opt/llama/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/llama/lib:${LD_LIBRARY_PATH} \
    HF_HOME=/models \
    LLAMA_ARG_MODELS_DIR=/models

# Create models directory and set ownership
RUN mkdir -p /models && chown llama:llama /models

# Set user and working directory
USER llama
WORKDIR ${WORKSPACE_DIR}

# Volume for models (mount from host at runtime)
VOLUME ["/models"]
