#!/usr/bin/env bash
set -euo pipefail

# 99-install-dependents.sh
# Install Ubuntu packages required by binaries in ${LLAMA_HOME}/bin
# Usage: ./99-install-dependents.sh [-h|--help]
#
# This script is designed for Docker multi-stage builds:
# - Build stage: 0[1-3]*.sh builds llama.cpp with Vulkan support
# - Release stage: Copy ${LLAMA_HOME} and run this script to install runtime dependencies
#
# The script scans binaries in ${LLAMA_HOME}/bin, identifies required Ubuntu packages
# using ldd and dpkg, and installs them along with extra packages from EXTRA env var.
# It filters out llama's own libraries in ${LLAMA_HOME}/lib and cleans up apt
# caches to minimize the final Docker image size.

usage() {
  cat <<'USAGE'
 Usage: 99-install-dependents.sh [-h|--help]

This script scans all binaries in ${LLAMA_HOME}/bin, identifies Ubuntu packages
required to run them, and installs them. It uses ldd to find dependencies,
filters out libraries in ${LLAMA_HOME}/lib, and maps remaining libraries
to their providing packages using dpkg.

After installation, it cleans up apt caches to minimize image size.

This is intended for use in Docker multi-stage builds where the build stage
creates the binaries and this script installs the minimal runtime dependencies
in the release image.

 Options:
   -h, --help      Show this help message
 
 Environment variables (sourced from .toolbox.env):
   LLAMA_HOME      Install prefix (default: /opt/llama)
   EXTRA           Extra packages to install (default: "curl ca-certificates")
   REQUIRED        Required packages always installed (hardcoded: "libgomp1 libvulkan1 mesa-vulkan-drivers")
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

# Source environment overrides if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/../.toolbox.env"
fi

# Set defaults
LLAMA_HOME="${LLAMA_HOME:-/opt/llama}"
BIN_DIR="${LLAMA_HOME}/bin"
LIB_DIR="${LLAMA_HOME}/lib"
EXTRA="${EXTRA:-curl ca-certificates}"
REQUIRED="libgomp1 libvulkan1 mesa-vulkan-drivers libglvnd0 libgl1 libglx0 libegl1 libgles2"

# Determine if sudo is needed
if [ "$(id -u)" -eq 0 ]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

# Check if bin directory exists
if [ ! -d "$BIN_DIR" ]; then
  echo "Error: Binary directory not found: $BIN_DIR" >&2
  echo "Please run 02-build-llamacpp.sh with --install first." >&2
  exit 1
fi

echo "[install-dependents] Scanning binaries in: $BIN_DIR"
echo "[install-dependents] Filtering out libraries in: $LIB_DIR"
echo ""

# Collect unique library paths
declare -A seen_libs
declare -a lib_paths
lib_paths=()

# Find all binaries (files, not symlinks, executable)
for binary in "$BIN_DIR"/*; do
  if [ -f "$binary" ] && [ -x "$binary" ]; then
    binary_name=$(basename "$binary")
    echo "[install-dependents] Analyzing: $binary_name"

    # Run ldd and parse library paths
    while IFS= read -r line; do
      # Parse ldd output lines like:
      # libvulkan.so.1 => /lib/x86_64-linux-gnu/libvulkan.so.1 (0x00007f...)
      # linux-vdso.so.1 (0x00007ffff...)

      if [[ $line =~ (.+)=\>\ (.+)\ \(0x ]]; then
        lib_path="${BASH_REMATCH[2]}"
      elif [[ $line =~ [a-zA-Z0-9_\.-]+\ \(0x ]]; then
        # Virtual libraries like linux-vdso.so.1 - skip
        continue
      else
        continue
      fi

      # Filter out libraries in LLAMA_HOME/lib
      if [[ $lib_path == "${LIB_DIR}"* ]]; then
        continue
      fi

      # Filter out libraries in build directory (RUNPATH)
      if [[ $lib_path == "/workspace/llama.cpp/build/bin"* ]]; then
        continue
      fi

      # Check if it's a valid path
      if [ ! -f "$lib_path" ]; then
        continue
      fi

      # Skip if already seen
      if [ -n "${seen_libs[$lib_path]:-}" ]; then
        continue
      fi

      seen_libs[$lib_path]=1
      lib_paths+=("$lib_path")
    done < <(ldd "$binary" 2>/dev/null || true)
  fi
done

echo ""
echo "[install-dependents] Found ${#lib_paths[@]} unique external libraries"
echo ""

# Map libraries to packages
declare -A packages
packages=()

for lib_path in "${lib_paths[@]}"; do
  # Resolve to canonical path for dpkg -S lookup
  canonical_path=$(readlink -f "$lib_path")

  # Try dpkg -S to find the package
  if package=$(dpkg -S "$canonical_path" 2>/dev/null | cut -d: -f1 | head -1); then
    packages[$package]=1
    echo "[install-dependents] $lib_path -> $package"
  else
    echo "[install-dependents] Warning: No package found for $lib_path (canonical: $canonical_path)" >&2
  fi
done

# Add extra packages from EXTRA environment variable
for pkg in $EXTRA; do
  packages[$pkg]=1
  echo "[install-dependents] Adding extra package: $pkg"
done

# Add required packages that must always be installed
for pkg in $REQUIRED; do
  packages[$pkg]=1
  echo "[install-dependents] Adding required package: $pkg"
done

echo ""
echo "[install-dependents] Summary:"
echo "[install-dependents] --------------"
echo "[install-dependents] Total external libraries: ${#lib_paths[@]}"
echo "[install-dependents] Unique packages to install: ${#packages[@]}"
echo ""

# Output sorted list of packages to install
echo "[install-dependents] Packages to install:"
pkg_list=$(printf '%s\n' "${!packages[@]}" | sort)
echo "$pkg_list" | sed 's/^/  - /'
echo ""

# Update package database and install packages
echo "[install-dependents] Updating package database..."
if ! command -v apt-get >/dev/null 2>&1; then
  echo "Error: apt-get not found" >&2
  exit 1
fi

DEBIAN_FRONTEND=noninteractive $SUDO_CMD apt-get update -qq

echo "[install-dependents] Installing packages..."
DEBIAN_FRONTEND=noninteractive $SUDO_CMD apt-get install -y --no-install-recommends $pkg_list

# Clean up apt caches
echo "[install-dependents] Cleaning up apt caches..."
$SUDO_CMD apt-get clean
$SUDO_CMD rm -rf /var/lib/apt/lists/*

echo ""
echo "[install-dependents] Installation complete."
