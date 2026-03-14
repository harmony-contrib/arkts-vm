#!/usr/bin/env bash

set -eux

FIXED_TAG="6.0.0"
FIXED_OS="linux-x64"
FIXED_ASSET_NAME="arkvm_static_linux_x64.tar.gz"
FIXED_DOWNLOAD_URL="https://github.com/harmony-contrib/arkts-vm/releases/download/${FIXED_TAG}/${FIXED_ASSET_NAME}"

INPUT_TAG="${INPUT_TAG:-$FIXED_TAG}"

# Optional: set INPUT_WAS_CACHED=true when using cache; INPUT_CACHE can be used by caller for cache key
INPUT_CACHE="${INPUT_CACHE:-}"

# Determine platform — only Linux x64 is supported
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [[ $(uname -m) != 'x86_64' ]]; then
        echo "Error: Only x86_64 Linux is supported"
        exit 1
    fi
    OS_FILENAME="$FIXED_ASSET_NAME"
    OS="$FIXED_OS"
else
    echo "Error: Unsupported OS type. Supported platform:"
    echo "  - x86_64 Linux (gnu)"
    exit 1
fi

WORK_DIR="${HOME}/setup-arkvm"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "Working directory: $WORK_DIR"
echo "Platform: $OS"
echo "Tag: $INPUT_TAG"
if [[ "$INPUT_TAG" != "$FIXED_TAG" ]]; then
    echo "Warning: tag '$INPUT_TAG' was requested, but this script always downloads ${FIXED_TAG}/${FIXED_ASSET_NAME}"
fi

build_lib_path() {
    local root="$1"
    find "$root" -type f \( -name '*.so' -o -name '*.so.*' -o -name '*.dylib' \) -exec dirname {} \; 2>/dev/null | sort -u | tr '\n' ':' | sed 's/:$//'
}

collect_path_dirs() {
    local root="$1"
    {
        find "$root" -type d -name 'bin' 2>/dev/null
        find "$root" -type f -perm -111 \
            ! -name '*.so' \
            ! -name '*.so.*' \
            ! -name '*.dylib' \
            ! -name '*.a' \
            ! -name '*.abc' \
            ! -name '*.json' \
            ! -name '*.rsp' \
            ! -name '*.ets' \
            ! -name '*.ts' \
            -exec dirname {} \; 2>/dev/null
    } | sort -u
}

emit_runtime_env() {
    local path_dirs="$1"
    local lib_path="$2"

    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        echo "$p" >> "${GITHUB_PATH:-/dev/null}" 2>/dev/null || true
    done <<< "$path_dirs"

    if [[ -n "${GITHUB_ENV:-}" ]]; then
        echo "LD_LIBRARY_PATH=${lib_path}:${LD_LIBRARY_PATH:-}" >> "${GITHUB_ENV}"
    else
        local path_prefix
        path_prefix=$(echo "$path_dirs" | tr '\n' ':' | sed 's/:$//')
        export PATH="${path_prefix}:${PATH}"
        export LD_LIBRARY_PATH="${lib_path}:${LD_LIBRARY_PATH:-}"
    fi
}

# Check if cached installation is valid（有可执行目录且至少有一处 .so，即视为有效）
if [[ "${INPUT_WAS_CACHED:-false}" == "true" ]]; then
    echo "Using cached arkvm installation"
    ARKVM_DIR="${WORK_DIR}/arkvm"

    PATH_DIRS=$(collect_path_dirs "${ARKVM_DIR}")
    ARKVM_LIB_PATH=$(build_lib_path "$ARKVM_DIR")
    if [[ -n "$PATH_DIRS" ]] && [[ -n "$ARKVM_LIB_PATH" ]]; then
        echo "Cached installation verified"
        emit_runtime_env "$PATH_DIRS" "$ARKVM_LIB_PATH"
        echo "arkvm-path=${ARKVM_DIR}" >> "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true
        echo "platform=$OS" >> "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true
        echo "Added executable dirs to PATH, all .so dirs to library path"
        exit 0
    fi
    echo "Cached installation is invalid or incomplete, will re-download"
    rm -rf "${ARKVM_DIR}" 2>/dev/null || true
fi

DOWNLOAD_URL="$FIXED_DOWNLOAD_URL"

echo "Download URL: ${DOWNLOAD_URL}"

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
                echo "Set SKIP_DOWNLOAD=true and place ${OS_FILENAME} as arkvm-ohos.tar.gz in $WORK_DIR"
                exit 1
            fi
        fi
    done
fi

if [[ ! -f "arkvm-ohos.tar.gz" ]] || [[ ! -s "arkvm-ohos.tar.gz" ]]; then
    echo "Error: Archive is missing or empty"
    exit 1
fi

echo "Extracting arkvm..."
tar -xzvf "arkvm-ohos.tar.gz"

TOP_DIRS=$(find . -maxdepth 1 -type d ! -name . ! -name arkvm | sed 's|^\./||' | sort)
TOP_COUNT=$(echo "$TOP_DIRS" | sed '/^$/d' | wc -l | tr -d ' ')
SINGLE_DIR=""
if [[ "$TOP_COUNT" -eq 1 ]]; then
    SINGLE_DIR=$(echo "$TOP_DIRS" | head -n 1)
fi

if [[ -n "$SINGLE_DIR" ]]; then
    echo "Found single top-level dir: $SINGLE_DIR"
    if [[ "$SINGLE_DIR" != "arkvm" ]]; then
        mv "$SINGLE_DIR" "arkvm"
    fi
else
    echo "Grouping archive contents into arkvm/"
    mkdir -p arkvm
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        [[ "$entry" == "arkvm" ]] && continue
        [[ "$entry" == "arkvm-ohos.tar.gz" ]] && continue
        mv "$entry" arkvm/ 2>/dev/null || true
    done < <(find . -maxdepth 1 -mindepth 1 ! -name . -printf '%P\n' | sort)
fi

ARKVM_DIR="${WORK_DIR}/arkvm"
PATH_DIRS=$(collect_path_dirs "$ARKVM_DIR")
ARKVM_LIB_PATH=$(build_lib_path "$ARKVM_DIR")

if [[ -z "$PATH_DIRS" ]] || [[ -z "$ARKVM_LIB_PATH" ]]; then
    echo "Error: No executable dirs or no .so dirs found under $ARKVM_DIR"
    exit 1
fi

rm -f "arkvm-ohos.tar.gz"

while IFS= read -r d; do
    [[ -d "$d" ]] && chmod -R a+x "$d" 2>/dev/null || true
done <<< "$PATH_DIRS"

emit_runtime_env "$PATH_DIRS" "$ARKVM_LIB_PATH"

echo "Added executable dirs to PATH: $PATH_DIRS"
echo "Added library path (all dirs with .so): ${ARKVM_LIB_PATH}"

echo "arkvm-path=${ARKVM_DIR}" >> "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true
echo "platform=$OS" >> "${GITHUB_OUTPUT:-/dev/null}" 2>/dev/null || true

echo "arkvm installed successfully"
echo "Platform: $OS"
echo "Path: $ARKVM_DIR (executable dirs + lib path discovered dynamically)"
