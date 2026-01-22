# Project Objective

Objective
- Use distrobox toolbox to build llama.cpp with Vulkan support for AMD Strix Halo GPU.

Scope
- High-level goals: provision a reproducible distrobox container that exposes the host GPU, install and validate a Vulkan-enabled `llama.cpp` build for the Strix Halo GPU, and run an inference on a small GGUF model.
- Artifact sources: `https://github.com/ggml-org/llama.cpp.git`.
- Outcomes, not implementation details: this document specifies what we want to accomplish; implementation steps are contained in `PLAN.md`.
- Environment: scripts source a common `.toolbox.env` file for toolbox configuration (see repository root). `.toolbox.env` includes `BASE_IMAGE` to configure the toolbox base image. It was renamed from `.build.env` to clarify its primary role in toolbox setup, analogous to ARG declarations used in Dockerfile/Podman builds. For Dockerfile builds, use ARGS declarations for configuration.
- Note: The provisioning script `01-provision-toolbox.sh` supports a `-f|--force` flag to allow destructive recreation of an existing toolbox; by default it will not overwrite an existing toolbox.

Milestones
1. Provision a distrobox toolbox container that exposes the host GPU.
2. Install and configure Vulkan inside the toolbox.
3. Build a Vulkan-enabled `llama.cpp`.
4. Validate GPU detection and run a sample inference using a small GGUF model.

Deliverables
- A reproducible distrobox toolbox definition and setup instructions/scripts for provisioning the container with GPU passthrough.
- Build artifacts and concise build logs demonstrating a successful Vulkan build of `llama.cpp`.
- Validation logs and a short verification report showing GPU detection and a completed inference on the selected model.

Assumptions & Constraints
- Host: Ubuntu 24.04 with a Strix Halo GPU.
- Model: tests use a small GGUF model to keep inference resource requirements modest.

Success Criteria
- The distrobox toolbox container detects the Strix Halo GPU and exposes it inside the container.
- `llama.cpp` builds with Vulkan support and the produced binary runs without fatal errors.
- A test inference using `unsloth/gemma-3-1b-it-GGUF` (or equivalent small model) completes successfully and produces reasonable output.

Notes
- Use the `https://github.com/ggml-org/llama.cpp.git` repository.
- Record versions and exact commits used for reproducibility.
