#!/usr/bin/env bash

set -eux

: "${INPUT_TAG:?INPUT_TAG needs to be set}"

# Optional: set INPUT_WAS_CACHED=true when using cache; INPUT_CACHE can be used by caller for cache key
INPUT_CACHE="${INPUT_CACHE:-}"

# Base URL for arkts-vm releases (private repo: ensure token or runner has access when downloading)
URL_BASE="https://github.com/harmony-contrib/arkts-vm/releases/download"

# Determine platform — only Linux x64 and macOS ARM64 are supported
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ $(uname -m) != 'x86_64' ]]; then
        echo "Error: Only x86_64 Linux is supported"
        exit 1
    fi
    OS_FILENAME="arkvm_linux_x64.tar.gz"
    OS="linux-x64"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ $(uname -m) != 'arm64' ]]; then
        echo "Error: Only ARM64 macOS is supported"
        exit 1
    fi
    OS_FILENAME="arkvm_darwin_arm64.tar.gz"
    OS="macos-arm64"
else
    echo "Error: Unsupported OS type. Supported platforms:"
    echo "  - x86_64 Linux (gnu)"
    echo "  - aarch64 macOS (Apple Silicon)"
    exit 1
fi

WORK_DIR="${HOME}/setup-arkvm"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "Working directory: $WORK_DIR"
echo "Platform: $OS"
echo "Tag: $INPUT_TAG"

# Discover all directories that contain .so / .dylib (for LD_LIBRARY_PATH / DYLD_LIBRARY_PATH)
# 动态发现，后续新增目录无需改脚本
build_lib_path() {
    local root="$1"
    find "$root" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \) -exec dirname {} \; 2>/dev/null | sort -u | tr '\n' ':' | sed 's/:$//'
}

# Discover all directories named "bin" under root (for PATH)
# 动态发现，后续新增 bin 目录无需改脚本
collect_bin_dirs() {
    local root="$1"
    find "$root" -type d -name 'bin' 2>/dev/null | sort
}

# Check if cached installation is valid（有 bin 目录且至少有一处 .so，即视为有效）
if [[ "${INPUT_WAS_CACHED:-false}" == "true" ]]; then
    echo "Using cached arkvm installation"
    ARKVM_DIR="${WORK_DIR}/arkvm"

    BIN_DIRS=$(collect_bin_dirs "${ARKVM_DIR}")
    ARKVM_LIB_PATH=$(build_lib_path "$ARKVM_DIR")
    if [[ -n "$BIN_DIRS" ]] && [[ -n "$ARKVM_LIB_PATH" ]]; then
        echo "Cached installation verified"

        for p in $BIN_DIRS; do
            echo "$p" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
        done
        if [[ -n "${GITHUB_ENV:-}" ]]; then
            if [[ "$OS" == "linux-x64" ]]; then
                echo "LD_LIBRARY_PATH=${ARKVM_LIB_PATH}:${LD_LIBRARY_PATH:-}" >> "${GITHUB_ENV}"
            else
                echo "DYLD_LIBRARY_PATH=${ARKVM_LIB_PATH}:${DYLD_LIBRARY_PATH:-}" >> "${GITHUB_ENV}"
            fi
        else
            PATH_PREFIX=$(echo "$BIN_DIRS" | tr '\n' ':' | sed 's/:$//')
            export PATH="${PATH_PREFIX}:${PATH}"
            if [[ "$OS" == "linux-x64" ]]; then
                export LD_LIBRARY_PATH="${ARKVM_LIB_PATH}:${LD_LIBRARY_PATH:-}"
            else
                export DYLD_LIBRARY_PATH="${ARKVM_LIB_PATH}:${DYLD_LIBRARY_PATH:-}"
            fi
        fi

        echo "arkvm-path=${ARKVM_DIR}" >> "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true
        echo "platform=$OS" >> "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true
        echo "Added all bin dirs to PATH, all .so dirs to library path"
        exit 0
    fi
    echo "Cached installation is invalid or incomplete, will re-download"
    rm -rf "${ARKVM_DIR}" 2>/dev/null || true
fi

# URL-encode tag for download URL
ENCODED_TAG=$(echo "$INPUT_TAG" | sed 's/+/%2B/g')
DOWNLOAD_URL="${URL_BASE}/${ENCODED_TAG}/${OS_FILENAME}"

echo "Download URL (private repo — ensure access): ${DOWNLOAD_URL}"

# Skip actual download when repo is private; place release artifact at $WORK_DIR/arkvm-*.tar.gz to test extract/path flow
if [[ "${SKIP_DOWNLOAD:-false}" == "true" ]]; then
    if [[ ! -f "${WORK_DIR}/arkvm-ohos.tar.gz" ]]; then
        echo "SKIP_DOWNLOAD is set but ${WORK_DIR}/arkvm-ohos.tar.gz not found. Place archive there or run without SKIP_DOWNLOAD."
        exit 1
    fi
    echo "Skipping download, using existing archive"
else
    RETRY_COUNT=0
    MAX_RETRIES=3

    while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
        if curl -L --fail --show-error --silent --max-time 300 -o "arkvm-ohos.tar.gz" "$DOWNLOAD_URL"; then
            echo "Download completed successfully"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "Download failed (attempt $RETRY_COUNT/$MAX_RETRIES)"
            if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
                echo "Retrying in 5 seconds..."
                sleep 5
            else
                echo "Error: Failed to download after $MAX_RETRIES attempts"
                echo "If repo is private, set SKIP_DOWNLOAD=true and place ${OS_FILENAME} as arkvm-ohos.tar.gz in $WORK_DIR"
                exit 1
            fi
        fi
    done
fi

# Verify archive exists
if [[ ! -f "arkvm-ohos.tar.gz" ]] || [[ ! -s "arkvm-ohos.tar.gz" ]]; then
    echo "Error: Archive is missing or empty"
    exit 1
fi

# Extract
echo "Extracting arkvm..."
tar -xf "arkvm-ohos.tar.gz"

# Archive layout: 单层目录（内含 bin）或顶层多个目录；不限制具体目录名
TOP_DIRS=$(find . -maxdepth 1 -type d ! -name . | sed 's|^\./||' | sort)
TOP_COUNT=$(echo "$TOP_DIRS" | wc -l | tr -d ' ')
SINGLE_DIR=""
if [[ "$TOP_COUNT" -eq 1 ]]; then
    SINGLE_DIR=$(echo "$TOP_DIRS" | head -n 1)
fi
if [[ -n "$SINGLE_DIR" ]] && [[ -d "${SINGLE_DIR}/bin" ]]; then
    echo "Found single top-level dir with bin: $SINGLE_DIR"
    mv "$SINGLE_DIR" "arkvm"
elif [[ -d "bin" ]]; then
    echo "Archive has top-level bin/ and other dirs; grouping into arkvm/"
    mkdir -p arkvm
    for d in $TOP_DIRS; do
        [[ -n "$d" ]] && mv "$d" arkvm/ 2>/dev/null || true
    done
else
    echo "Error: No top-level bin found. Archive contents:"
    tar -tzf "arkvm-ohos.tar.gz" 2>/dev/null | head -30 || true
    exit 1
fi

ARKVM_DIR="${WORK_DIR}/arkvm"
BIN_DIRS=$(collect_bin_dirs "$ARKVM_DIR")
ARKVM_LIB_PATH=$(build_lib_path "$ARKVM_DIR")

if [[ -z "$BIN_DIRS" ]] || [[ -z "$ARKVM_LIB_PATH" ]]; then
    echo "Error: No bin dirs or no .so dirs found under $ARKVM_DIR"
    exit 1
fi

# Clean up archive
rm -f "arkvm-ohos.tar.gz"

# Make all bin dirs executable
while IFS= read -r d; do
    [[ -d "$d" ]] && chmod -R a+x "$d" 2>/dev/null || true
done <<< "$BIN_DIRS"

# Add all bin dirs to PATH
while IFS= read -r p; do
    echo "$p" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
done <<< "$BIN_DIRS"
if [[ -n "${GITHUB_ENV:-}" ]]; then
    if [[ "$OS" == "linux-x64" ]]; then
        echo "LD_LIBRARY_PATH=${ARKVM_LIB_PATH}:${LD_LIBRARY_PATH:-}" >> "${GITHUB_ENV}"
    else
        echo "DYLD_LIBRARY_PATH=${ARKVM_LIB_PATH}:${DYLD_LIBRARY_PATH:-}" >> "${GITHUB_ENV}"
    fi
else
    PATH_PREFIX=$(echo "$BIN_DIRS" | tr '\n' ':' | sed 's/:$//')
    export PATH="${PATH_PREFIX}:${PATH}"
    if [[ "$OS" == "linux-x64" ]]; then
        export LD_LIBRARY_PATH="${ARKVM_LIB_PATH}:${LD_LIBRARY_PATH:-}"
    else
        export DYLD_LIBRARY_PATH="${ARKVM_LIB_PATH}:${DYLD_LIBRARY_PATH:-}"
    fi
fi

echo "Added bin dirs to PATH: $BIN_DIRS"
echo "Added library path (all dirs with .so): ${ARKVM_LIB_PATH}"

# GitHub Actions outputs
echo "arkvm-path=${ARKVM_DIR}" >> "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true
echo "platform=$OS" >> "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true

echo "arkvm installed successfully"
echo "Platform: $OS"
echo "Path: $ARKVM_DIR (bin dirs + lib path discovered dynamically)"
