#!/usr/bin/env bash
set -euo pipefail

# 01-install-toolchain.sh
# Install Vulkan development tools, build toolchain, and basic utilities
# Usage: ./01-install-toolchain.sh [-f|--force] [-h|--help]

# Check if running inside a container or toolbox
check_container_environment() {
  local is_container=0

  # Check for Docker
  if [ -f /.dockerenv ]; then
    is_container=1
  # Check cgroup for container signatures
  elif grep -qE '(docker|lxc|containerd|kubepods|podman)' /proc/1/cgroup 2>/dev/null; then
    is_container=1
  # Check for Distrobox environment
  elif [ -n "${DISTROBOX_ENTER_PATH:-}" ] || [ -n "${CONTAINER_ID:-}" ]; then
    is_container=1
  fi

  if [ "$is_container" -eq 0 ]; then
    echo "Error: This script must be run inside a container or distrobox." >&2
    echo "Please run this inside a distrobox toolbox or Docker container." >&2
    exit 1
  fi
}

check_container_environment

# Source environment overrides if present
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

# Ensure defaults
NON_INTERACTIVE=${NON_INTERACTIVE:-0}

# Determine if sudo is needed
if [ "$(id -u)" -eq 0 ]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

echo "[01] Installing toolchain and Vulkan packages"

usage() {
  cat <<'USAGE'
 Usage: 01-install-toolchain.sh [-f|--force] [-h|--help]

This script installs Vulkan development packages, build toolchain, and basic utilities
from the Ubuntu repository.

Options:
  -f, --force     Reinstall packages even if already installed.
  -h, --help      Show this help message.

 Packages installed:
   Vulkan:
     - libvulkan-dev
     - vulkan-tools
     - vulkan-validationlayers
     - spirv-tools
     - glslang-tools
     - glslc
   XCB/X11:
     - libxcb-xinput0, libxcb-xinerama0, libxcb-cursor-dev
   Toolchain:
     - build-essential, cmake, ninja-build, ccache
     - llvm, clang
     - libssl-dev, pkg-config, libomp-dev, libcurl4-openssl-dev
   Utilities:
     - ca-certificates, wget, curl
     - python3, python3-pip
     - git, unzip, gnupg, xz-utils, jq
     - mesa-vulkan-drivers
USAGE
}

# Parse args
FORCE=0
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
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# Update package list
echo "Updating package list..."
$SUDO_CMD apt-get update -qq

# Install all packages in one step
PACKAGES=(
  # Vulkan development packages
  libvulkan-dev
  vulkan-tools
  vulkan-validationlayers
  spirv-tools
  glslang-tools
  glslc

  # XCB/X11 dependencies for Vulkan
  libxcb-xinput0
  libxcb-xinerama0
  libxcb-cursor-dev

  # Build toolchain
  build-essential
  cmake
  ninja-build
  ccache
  llvm
  clang
  libssl-dev
  pkg-config
  libomp-dev
  libcurl4-openssl-dev

  # Basic utilities
  ca-certificates
  wget
  curl
  python3
  python3-pip
  git
  unzip
  gnupg
  xz-utils
  jq
  mesa-vulkan-drivers
)

echo "Installing packages: ${PACKAGES[*]}"
if [ "$FORCE" -eq 1 ]; then
  $SUDO_CMD apt-get install -y --reinstall "${PACKAGES[@]}"
else
  $SUDO_CMD apt-get install -y "${PACKAGES[@]}"
fi

# Verify Vulkan installation
echo "Verifying Vulkan installation..."
if command -v vulkaninfo >/dev/null 2>&1; then
  VULKAN_VERSION=$(vulkaninfo --summary 2>/dev/null | grep -i "Vulkan API Version" || true)
  echo "Vulkan installed successfully"
  if [ -n "$VULKAN_VERSION" ]; then
    echo "$VULKAN_VERSION"
  fi
else
  echo "Warning: vulkaninfo not found, installation may have issues"
fi

# Verify toolchain installation
echo "Verifying toolchain installation..."
for cmd in cmake ninja clang python3 git curl jq; do
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "  $cmd: $(command -v "$cmd")"
  else
    echo "Warning: $cmd not found in PATH" >&2
  fi
done

# Clean up apt cache to free space
echo "Cleaning up apt cache..."
$SUDO_CMD apt-get clean
$SUDO_CMD rm -rf /var/lib/apt/lists/*

echo "[01] Toolchain installation completed."
