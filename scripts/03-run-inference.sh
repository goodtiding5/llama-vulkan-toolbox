#!/usr/bin/env bash
set -euo pipefail

# 03-run-inference.sh
# Run a short inference using the built llama.cpp binary and a small GGUF model.
# Usage: ./03-run-inference.sh [llama-binary] [model-path]

usage() {
  cat <<'USAGE'
 Usage: 03-run-inference.sh [llama-binary] [model-path]

This script validates the llama.cpp installation by running a simple inference.

Arguments:
  llama-binary   Path to llama binary (default: llama-cli)
  model-path     Path to GGUF model file (default: ./models/gemma-3-1b-it-UD-Q6_K_XL.gguf)

Environment variables (sourced from .toolbox.env):
  LLAMA_HOME      Install prefix (default: /opt/llama)
  NO_INFERENCE     Set to 1 to skip validation (default: 0)
USAGE
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

# Source environment overrides if present
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

# Ensure defaults
NO_INFERENCE=${NO_INFERENCE:-0}

# Default environment variables for Docker/release layout
LLAMA_HOME="${LLAMA_HOME:-/opt/llama}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up paths for Llama
export PATH="$PATH:$LLAMA_HOME/bin"

# If NO_INFERENCE=1, skip validation for Docker builds
if [ "${NO_INFERENCE:-0}" -eq 1 ]; then
  echo "[03] NO_INFERENCE=1: Skipping inference validation for automated builds."
  exit 0
fi

# Export environment variables for model caching and transfer
export LLAMA_CACHE="${LLAMA_CACHE:-/workspace/models}"
export HF_HUB_ENABLE_HF_TRANSFER=1

LLAMA_BIN="${1:-llama-cli}"
MODEL_PATH="${2:-${WORKSPACE_DIR}/models/gemma-3-1b-it-UD-Q6_K_XL.gguf}"

echo "[03] Validating inference"

echo "LLAMA_BIN=${LLAMA_BIN}"
echo "MODEL_PATH=${MODEL_PATH}"

if ! command -v "$LLAMA_BIN" >/dev/null 2>&1; then
  echo "Error: llama binary not found in PATH: $LLAMA_BIN" >&2
  exit 2
fi

echo "Listing available devices with llama-cli..."
"$LLAMA_BIN" --list-devices

if [ ! -f "$MODEL_PATH" ]; then
  echo "Error: model file not found: $MODEL_PATH" >&2
  exit 2
fi

# Example run using llama-cli for non-interactive inference with GPU
echo '/exit' | "$LLAMA_BIN" -m "$MODEL_PATH" -p "What is the capital of France?" -n 32 -ngl 99 2>&1 | tee validation-output.txt

echo "Validation output saved to validation-output.txt"

echo "[03] Validation stub complete. Inspect logs for GPU detection and runtime behavior."
