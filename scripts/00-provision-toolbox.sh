#!/usr/bin/env bash
set -euo pipefail

# 00-provision-toolbox.sh
# Create and provision a distrobox/toolbox container for the experiment.
# Usage: ./00-provision-toolbox.sh [container-name]

# Source environment overrides if present
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

# Ensure defaults
NON_INTERACTIVE=${NON_INTERACTIVE:-0}

# Default BASE_IMAGE if not set in .toolbox.env
BASE_IMAGE="${BASE_IMAGE:-docker.io/library/ubuntu:26.04}"

CONTAINER_NAME_DEFAULT="${TOOLBOX_NAME:-llama-toolbox}"
FORCE=0

usage() {
  cat <<'USAGE'
Usage: 00-provision-toolbox.sh [-f|--force] [container-name]

Options:
  -f, --force    Destroy existing toolbox with the same name and recreate
  -h, --help     Show this help and exit

If no container-name is provided, the script uses TOOLBOX_NAME from .toolbox.env or 'llama-toolbox'.
USAGE
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      CONTAINER_NAME="$1"
      shift
      ;;
  esac
done

CONTAINER_NAME="${CONTAINER_NAME:-$CONTAINER_NAME_DEFAULT}"

echo "[00] Provisioning toolbox container: ${CONTAINER_NAME} (image: ${BASE_IMAGE})"

echo "NOTE: By default this script will not overwrite an existing toolbox. Use -f to force recreation."

# Ensure distrobox is available
if ! command -v distrobox >/dev/null 2>&1; then
  echo "Error: 'distrobox' is required but not found in PATH. Install distrobox and retry." >&2
  exit 1
fi

# Check if toolbox exists
container_exists=0
if distrobox list 2>/dev/null | grep -qw "${CONTAINER_NAME}"; then
  container_exists=1
fi

if [ "$container_exists" -eq 1 ]; then
  if [ "$FORCE" -eq 1 ]; then
    echo "Stopping existing toolbox '${CONTAINER_NAME}'..."
    DBX_NON_INTERACTIVE=1 distrobox stop "$CONTAINER_NAME" 2>/dev/null || true
    echo "Removing existing toolbox '${CONTAINER_NAME}'..."
    DBX_NON_INTERACTIVE=1 distrobox rm --force "$CONTAINER_NAME" 2>/dev/null || true
  else
    echo "Toolbox '${CONTAINER_NAME}' already exists. Use -f to force recreate." >&2
    exit 1
  fi
fi

echo "Creating distrobox toolbox '${CONTAINER_NAME}' with GPU passthrough..."
distrobox create --pull --image "${BASE_IMAGE}" --name "${CONTAINER_NAME}" \
  --volume "$(pwd)/llm/models:/workspace/models:rw" \
  --additional-flags "--privileged --device /dev/kfd --device /dev/dri"

echo "Setting up workspace directory in toolbox..."
distrobox enter "$CONTAINER_NAME" -- bash -lc 'if [ $(id -u) -ne 0 ]; then sudo mkdir -p /workspace; sudo chown -R $(id -u):$(id -g) /workspace; else mkdir -p /workspace; chown -R $(id -u):$(id -g) /workspace; fi'

echo "[00] Provisioning complete."
