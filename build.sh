#!/usr/bin/env bash

set -eux

ARKTS_MINIFEST_URL="https://gitee.com/ark-standalone-build/manifest.git"

# get current os platform and arch
if [[ "$OSTYPE" == "linux"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ $(uname -m) == 'arm64' ]]; then
        OS="macos-arm64"
    else
        echo "Error: Only ARM64 macOS is supported"
        exit 1
    fi
elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
    OS="windows"
else
    echo "Error: Unsupported OS type. Supported platforms:"
    echo "  - aarch64 macOS (Apple Silicon)"
    echo "  - x86_64 Windows"
    echo "  - x86_64 Linux (musl)"
    echo "  - x86_64 Linux (gnu)"
    exit 1
fi