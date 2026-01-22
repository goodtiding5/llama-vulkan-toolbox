#!/usr/bin/env bash
set -euo pipefail

# 02-build-llamacpp.sh
# Download llama.cpp release and build with Vulkan support
# Usage: ./02-build-llamacpp.sh [--checkout] [--build] [--install] [--config] [-h|--help]

print_usage() {
  cat <<EOF
  Usage: $0 [--checkout] [--build] [--install] [--config] [-h|--help]

  Options:
    --checkout            Download llama.cpp release source tarball from GitHub
    --build               Build llama.cpp with CMake for Vulkan backend
    --install             Install binaries and libs to \${LLAMA_HOME}/bin and \${LLAMA_HOME}/lib
    --config              Configure system loader and shell profile for Llama (creates /etc/ld.so.conf.d/llama.conf and /etc/profile.d/llama.sh)
    -h, --help            Show this help
EOF
}

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

# Parse arguments
CHECKOUT_CODE=0
DO_BUILD=0
DO_INSTALL=0
CONFIG=0
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
TARGET_DIR="${WORKSPACE_DIR}/llama.cpp"
LLAMA_HOME="${LLAMA_HOME:-/opt/llama}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --checkout) CHECKOUT_CODE=1; shift;;
    --build) DO_BUILD=1; shift;;
    --install) DO_INSTALL=1; shift;;
    --config) CONFIG=1; shift;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; print_usage; exit 2;;
  esac
done

echo "[03] Workspace dir: ${WORKSPACE_DIR}"
echo "[03] Target clone dir: ${TARGET_DIR}"
echo "[03] Install prefix: ${LLAMA_HOME}"

download_release_tarball() {
  local repo="$1"
  local tag="$2"
  local output="$3"

  local download_tag="$tag"

  if [[ "$tag" == "latest" ]]; then
    echo "[03] Fetching latest release tag for $repo..."
    download_tag=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$download_tag" ]]; then
      echo "Error: Could not fetch latest release tag" >&2
      exit 3
    fi

    echo "[03] Latest release tag: $download_tag"
  fi

  local url="https://github.com/$repo/archive/refs/tags/$download_tag.tar.gz"

  echo "[03] Downloading from: $url"
  echo "[03] Saving to: $output"

  curl -L "$url" -o "$output"

  echo "$download_tag"
}

# Task 1: Checkout code
checkout_code() {
  echo "[03] Downloading llama.cpp release source tarball"

  # Ensure curl is available
  if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl not found in PATH. Install curl and retry." >&2
    exit 3
  fi

  # Create workspace if needed
  mkdir -p "$WORKSPACE_DIR"

  # Get release tag from env or default to latest
  RELEASE_TAG="${LLAMA_REL_TAG:-latest}"
  REPO="ggml-org/llama.cpp"
  DOWNLOAD_OUTPUT="${WORKSPACE_DIR}/llama.cpp.tar.gz"

  echo "[03] Downloading llama.cpp release: $RELEASE_TAG"
  ACTUAL_TAG=$(download_release_tarball "$REPO" "$RELEASE_TAG" "$DOWNLOAD_OUTPUT")

  # Remove old source directory if exists
  rm -rf "$TARGET_DIR"

  # Create target directory and extract tarball, skipping first dir
  echo "[03] Extracting source tarball to $TARGET_DIR"
  mkdir -p "$TARGET_DIR"
  tar -xzf "$DOWNLOAD_OUTPUT" -C "$TARGET_DIR" --strip-components=1

  echo "$ACTUAL_TAG" > "$TARGET_DIR/build-tag.txt"
  echo "[03] Release tag recorded: $ACTUAL_TAG -> $TARGET_DIR/build-tag.txt"

  # Clean up tarball
  rm -f "$DOWNLOAD_OUTPUT"

  echo "[03] Code checkout complete."
}

# Task 2: Build
build_llama() {
  echo "[03] Building llama.cpp with Vulkan backend"

  BUILD_DIR="$TARGET_DIR/build"
  INSTALL_PREFIX="${LLAMA_HOME}"

  # Check for toolchain
  MISSING=()
  for cmd in cmake ninja; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      MISSING+=("$cmd")
    fi
  done

  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[03] Warning: Missing required tools: ${MISSING[*]}" >&2
    echo "[03] Please run 01-install-toolchain.sh first to install toolchain" >&2
    exit 4
  fi

  # Check for code checkout
  if [ ! -d "$TARGET_DIR" ]; then
    echo "[03] Warning: Code not checked out at $TARGET_DIR" >&2
    echo "[03] Please run with --checkout first" >&2
    exit 7
  fi

  mkdir -p "$BUILD_DIR"

  # Get build identifier
  if [ -f "$TARGET_DIR/build-tag.txt" ]; then
    BUILD_ID=$(cat "$TARGET_DIR/build-tag.txt")
    echo "[03] Configuring and building llama.cpp (tag: $BUILD_ID)"
  elif [ -f "$TARGET_DIR/build-commit.txt" ]; then
    BUILD_ID=$(cat "$TARGET_DIR/build-commit.txt")
    echo "[03] Configuring and building llama.cpp (commit: $BUILD_ID)"
  else
    BUILD_ID="unknown"
    echo "[03] Configuring and building llama.cpp"
  fi

  # Configure the build
  echo "[03] Running cmake configure (source: $TARGET_DIR, build: $BUILD_DIR)"
  cmake -S "$TARGET_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DGGML_NATIVE=OFF \
    -DGGML_VULKAN=ON \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DGGML_VULKAN_VALIDATE=OFF \
    -DBUILD_SHARED_LIBS=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_CURL=ON \
    -DGGML_CCACHE=ON 2>&1 | tee "$TARGET_DIR/build-cmake.log"

  # Build
  echo "[03] Running build: cmake --build $BUILD_DIR --config Release -j$(nproc)"
  cmake --build "$BUILD_DIR" --config Release -j"$(nproc)" 2>&1 | tee "$TARGET_DIR/build-make.log"
  echo "[03] Build completed. Logs: $TARGET_DIR/build-cmake.log, $TARGET_DIR/build-make.log"
  echo "[03] Build task complete."
}

# Task 3: Install
install_llama() {
  echo "[03] Installing llama.cpp binaries and libs to ${LLAMA_HOME}"

  BUILD_DIR="$TARGET_DIR/build"
  BUILD_BIN_DIR="$BUILD_DIR/bin"

  # Check if build directory exists
  if [ ! -d "$BUILD_BIN_DIR" ]; then
    echo "[03] Warning: Build bin dir $BUILD_BIN_DIR not found" >&2
    echo "[03] Please run with --build first" >&2
    exit 8
  fi

  # Create install directories
  ${SUDO_CMD} mkdir -p "${LLAMA_HOME}/bin" "${LLAMA_HOME}/lib"

  # Step 1: Copy everything from build/bin to LLAMA_HOME/lib (preserves symlinks)
  echo "[03] Copying all files from ${BUILD_BIN_DIR} to ${LLAMA_HOME}/lib"
  ${SUDO_CMD} cp -r "${BUILD_BIN_DIR}/"* "${LLAMA_HOME}/lib/"

  # Step 2: Move all llama-* binaries (not .so files) to LLAMA_HOME/bin
  echo "[03] Moving llama-* binaries to ${LLAMA_HOME}/bin"
  for file in "${LLAMA_HOME}/lib"/llama-*; do
    if [ -f "$file" ] && [ ! -L "$file" ]; then
      basename_file=$(basename "$file")
      ${SUDO_CMD} mv "$file" "${LLAMA_HOME}/bin/"
      echo "[03] Moved ${basename_file} to bin/"
    fi
  done

  # Also move other key binaries if they exist
  for binary in convert-hf-to-gguf gguf-split gguf-new-metadata eval-callback infill quantize; do
    file="${LLAMA_HOME}/lib/${binary}"
    if [ -f "$file" ] && [ ! -L "$file" ]; then
      ${SUDO_CMD} mv "$file" "${LLAMA_HOME}/bin/"
      echo "[03] Moved ${binary} to bin/"
    fi
  done

  # Step 3: Copy backend libraries to bin directory for dynamic loading
  # Note: llama.cpp backend loading requires backends to be in same directory as binaries
  echo "[03] Copying backend libraries to ${LLAMA_HOME}/bin for dynamic loading"
  for backend in "${LLAMA_HOME}/lib"/libggml-*.so; do
    if [ -f "$backend" ] && [ ! -L "$backend" ]; then
      backend_name=$(basename "$backend")
      ${SUDO_CMD} cp "$backend" "${LLAMA_HOME}/bin/"
      echo "[03] Copied ${backend_name} to bin/"
    fi
  done

  echo "[03] Installation complete."
  echo "[03] Binaries installed to: ${LLAMA_HOME}/bin"
  echo "[03] Libraries installed to: ${LLAMA_HOME}/lib"
  echo "[03] Backend libraries copied to: ${LLAMA_HOME}/bin (for dynamic loading)"
}

# Task 4: Configure
configure_llama() {
  INSTALL_PREFIX="${LLAMA_HOME}"
  echo "[03] Configuring system for Llama at ${INSTALL_PREFIX}"

  # If NON_INTERACTIVE=1, skip config files and use ENV vars instead
  if [ "${NON_INTERACTIVE:-0}" -eq 1 ]; then
    echo "[03] NON_INTERACTIVE=1: Skipping /etc/profile.d and /etc/ld.so.conf.d setup, using ENV vars for PATH and LD_LIBRARY_PATH."
    ${SUDO_CMD} ldconfig || true
    return
  fi

  # Create ld.so.conf.d entry
  ${SUDO_CMD} mkdir -p /etc/ld.so.conf.d
  ${SUDO_CMD} tee /etc/ld.so.conf.d/llama.conf >/dev/null <<EOF
${INSTALL_PREFIX}/lib
EOF
  echo "[03] Wrote /etc/ld.so.conf.d/llama.conf"

  # Run ldconfig to refresh cache
  echo "[03] Running ldconfig..."
  ${SUDO_CMD} ldconfig

  # Create /etc/profile.d entry for interactive shells
  ${SUDO_CMD} tee /etc/profile.d/llama.sh >/dev/null <<'PROFILE'
export PATH="${LLAMA_HOME:-/opt/llama}/bin:$PATH"
export LD_LIBRARY_PATH="${LLAMA_HOME:-/opt/llama}/lib:$LD_LIBRARY_PATH"
PROFILE
  ${SUDO_CMD} chmod 0644 /etc/profile.d/llama.sh
  echo "[03] Wrote /etc/profile.d/llama.sh"

  echo "[03] Configuration complete."
}

# Main execution
if [ "$CHECKOUT_CODE" -eq 1 ]; then
  checkout_code
fi

if [ "$DO_BUILD" -eq 1 ]; then
  build_llama
fi

if [ "$DO_INSTALL" -eq 1 ]; then
  install_llama
fi

if [ "$CONFIG" -eq 1 ]; then
  configure_llama
fi

# If no specific task was requested, run all tasks in order
if [ "$CHECKOUT_CODE" -eq 0 ] && [ "$DO_BUILD" -eq 0 ] && [ "$DO_INSTALL" -eq 0 ] && [ "$CONFIG" -eq 0 ]; then
  echo "[03] No specific task requested, running all tasks in order..."
  checkout_code
  build_llama
  install_llama
  configure_llama
  echo "[03] All tasks completed successfully."
fi
