# llama.cpp Vulkan Toolbox

A reproducible development environment for building `llama.cpp` with native **Vulkan backend support** optimized for AMD GPUs (and other Vulkan-capable GPUs).

## Overview

This project provides a complete pipeline from container provisioning through building and testing an inference-ready llama.cpp binary. The workflow is orchestrated by bash scripts that can be executed sequentially or individually.

### Key Features

- **GPU Passthrough**: Distrobox toolbox containers expose host GPU hardware for direct Vulkan access
- **Reproducible Builds**: Build from specific release tags or latest releases
- **Multi-stage Docker Image**: Optimized for production deployment with minimal runtime footprint
- **Vulkan Backend**: Full GPU acceleration support via Vulkan

## Project Structure

```
.
├── scripts/
│   ├── 00-provision-toolbox.sh    # Provision distrobox with GPU passthrough
│   ├── 01-install-toolchain.sh    # Install build tools and Vulkan dependencies
│   ├── 02-build-llamacpp.sh      # Download and build llama.cpp
│   ├── 03-run-inference.sh        # Run inference validation
│   └── 99-install-dependents.sh  # Install runtime dependencies
├── Dockerfile                     # Multi-stage Docker build
├── docker-compose.yml             # Docker Compose orchestration
├── .toolbox.env                  # Build environment configuration
├── .env                          # Environment variables (HF_TOKEN, etc.)
└── README.md                     # This file
```

### Script Reference

| Script | Purpose |
|--------|---------|
| `00-provision-toolbox.sh` | Create distrobox toolbox with GPU passthrough support. Use `-f` to force recreation. |
| `01-install-toolchain.sh` | Install Vulkan dev packages, build toolchain (cmake, ninja-build), and XCB dependencies. |
| `02-build-llamacpp.sh` | Download llama.cpp release and build with Vulkan backend. Supports specific release tags. |
| `03-run-inference.sh` | Run inference validation using built llama.cpp binary. |
| `99-install-dependents.sh` | Post-build dependency installation for runtime. |

### Utility Scripts

| Script | Purpose |
|--------|---------|
| `check_config.sh` | Validate environment variables, GPU detection, and required tools. |
| `test_inference.sh` | Execute sample prompts against the built llama.cpp binary. |
| `benchmark.sh` | Run performance benchmarks. |
| `list_models.sh` | List available GGUF models. |
| `hf_download.sh` | Download models from HuggingFace. |

## Quick Start

### Prerequisites (Host System)

```bash
# Install distrobox on Ubuntu:
sudo apt update && sudo apt install -y curl git fuse
curl https://raw.githubusercontent.com/ublue-os/distrobox/main/install.sh | bash
```

**GPU Requirements**: Any Vulkan-capable GPU (AMD, NVIDIA with Mesa, Intel, etc.)

### Option 1: Distrobox Toolbox Setup

```bash
# Provision container (use -f to force recreate):
./scripts/00-provision-toolbox.sh

# Enter container:
distrobox enter llama-toolbox

# Inside container, run build sequence:
cd /workspace
./scripts/01-install-toolchain.sh
./scripts/02-build-llamacpp.sh --checkout --build --install --config
./scripts/03-run-inference.sh
```

### Option 2: Docker Deployment

```bash
# Build production image with latest release:
docker build --build-arg LLAMA_REL_TAG=latest -t llama-vulkan:latest .

# Build with specific release tag:
docker build --build-arg LLAMA_REL_TAG=b0 -t llama-vulkan:b0 .

# Run with GPU passthrough:
docker run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  --group-add video \
  --security-opt seccomp=unconfined \
  -v /path/to/models:/workspace/models \
  llama-vulkan:latest
```

### Docker Compose

```bash
# Build and run:
docker compose up --build

# Run inference:
docker compose exec app llama-cli -m /workspace/models/model.gguf -p "Your prompt"
```

## Usage Examples

### Build Specific Release

```bash
# In distrobox container:
./scripts/02-build-llamacpp.sh --checkout --build --install

# Or build a specific tag:
LLAMA_REL_TAG=b0 ./scripts/02-build-llamacpp.sh --checkout --build --install
```

### Run Inference

```bash
# Validate installation:
./scripts/03-run-inference.sh

# Run with custom model:
./scripts/03-run-inference.sh llama-cli /workspace/models/my-model.gguf

# Docker example:
docker run --rm \
  --device=/dev/dri \
  -v /tmp/model.gguf:/workspace/models/model.gguf:ro \
  llama-vulkan:latest \
  llama-cli -m /workspace/models/model.gguf -p "What is the capital of France?"
```

### List GPU Devices

```bash
# Docker:
docker run --rm --device=/dev/dri llama-vulkan:latest llama-cli --list-devices

# Distrobox:
llama-cli --list-devices
```

## Configuration

### Environment Variables (.toolbox.env)

```bash
# Base image for toolbox or build
BASE_IMAGE=docker.io/library/ubuntu:26.04

# Build platform
BUILD_PLATFORM=linux

# Llama.cpp install directory
LLAMA_HOME=/opt/llama

# Workspace directory
WORKSPACE_DIR=/workspace

# Toolbox name (for distrobox)
TOOLBOX_NAME=llama-toolbox

# Llama.CPP release tag (or 'latest')
LLAMA_REL_TAG=latest
```

### Build Configuration

The `02-build-llamacpp.sh` script supports the following flags:

| Flag | Description |
|------|-------------|
| `--checkout` | Download llama.cpp source from GitHub |
| `--build` | Compile llama.cpp with CMake |
| `--install` | Install binaries and libraries |
| `--config` | Configure system loader and shell profile |
| `-h, --help` | Show help message |

### Dockerfile Build Args

```bash
docker build \
  --build-arg BASE_IMAGE=docker.io/library/ubuntu:26.04 \
  --build-arg LLAMA_REL_TAG=latest \
  --build-arg LLAMA_HOME=/opt/llama \
  -t llama-vulkan:latest .
```

## Validation & Testing

### Verify GPU Detection

```bash
# Check Vulkan devices in container:
docker run --rm --device=/dev/dri llama-vulkan:latest llama-cli --list-devices

# Expected output:
# ggml_vulkan: Found 1 Vulkan devices:
# 0 = Your GPU Name | uma: 1 | fp16: 1 | bf16: 0 | ...
```

### Run Test Inference

```bash
# Download a small model:
curl -L -o /tmp/tinyllama.gguf https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q5_K_M.gguf

# Run inference:
docker run --rm \
  --device=/dev/dri \
  -v /tmp/tinyllama.gguf:/workspace/models/model.gguf:ro \
  llama-vulkan:latest \
  bash -c "echo '/exit' | llama-cli -m /workspace/models/model.gguf -p 'Hello world'"
```

## Docker Build Details

### Multi-stage Build

The Dockerfile uses a multi-stage build:

1. **Builder stage**: Full toolchain + compilation (~1GB)
2. **Release stage**: Runtime-only image (~200MB)

### Release Image Contents

- **Binaries**: `/opt/llama/bin/` (llama-cli, convert-hf-to-gguf, etc.)
- **Libraries**: `/opt/llama/lib/` (libggml-vulkan.so, libggml-cpu-*.so)
- **Backend**: Vulkan backend libraries in bin directory for dynamic loading

## Troubleshooting

### Vulkan device not detected

```bash
# Verify host GPU:
ls -l /dev/dri

# Check Vulkan installation:
vulkaninfo --summary

# Ensure proper device passthrough:
docker run --rm --device=/dev/dri --device=/dev/kfd ...
```

### Build fails

```bash
# Check build logs in container:
# /workspace/llama.cpp/build-cmake.log
# /workspace/llama.cpp/build-make.log

# Verify toolchain installation:
./scripts/01-install-toolchain.sh
```

### Inference issues

```bash
# Validate model file:
file /path/to/model.gguf

# Check for Vulkan backend load:
llama-cli --list-devices

# Run with verbose output:
llama-cli -m model.gguf -p "test" -v
```

## Architecture

```
Host System
├── AMD/Intel/NVIDIA GPU (/dev/dri, /dev/kfd)
│   └── Vulkan driver passthrough
│       ├─ Distrobox Container
│       │   ├── Toolchain: cmake, ninja-build, clang, vulkan-dev
│       │   ├── llama.cpp source (downloaded from GitHub)
│       │   └── Build artifacts (/opt/llama)
│       └─ Docker Container
│           ├── Runtime image (~200MB)
│           └── llama-cli with Vulkan backend
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly with both distrobox and Docker
5. Submit a pull request

## License

MIT License for project infrastructure. llama.cpp source code follows its own repository licensing terms.

---

**Version**: 1.0 | **Last Updated**: January 2026
