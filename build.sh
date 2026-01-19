#!/usr/bin/env bash

set -euo pipefail

ARKTS_MINIFEST_URL="https://gitee.com/ark-standalone-build/manifest.git"

info() { echo -e "\033[32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[33m[WARN]\033[0m $*"; }

OS_TYPE=$(uname -s | tr '[:upper:]' '[:lower:]')

# --- 1. 安装 Repo 工具 ---
install_repo() {
    info "Setting up repo tool..."
    mkdir -p "$HOME/bin"
    # 使用 GitCode 的 repo 镜像
    curl -s https://raw.gitcode.com/gitcode-dev/repo/raw/main/repo-py3 -o "$HOME/bin/repo"
    chmod a+x "$HOME/bin/repo"
    
    # 导出到当前会话的 PATH
    export PATH="$HOME/bin:$PATH"
    
    # 安装 repo 依赖
    pip3 install -i https://repo.huaweicloud.com/repository/pypi/simple requests
}

# --- 2. Windows 环境设置 ---
setup_windows() {
    info "Configuring Windows Native Environment..."
    if command -v choco &> /dev/null; then
        # 安装编译必需工具
        choco install -y cmake ninja python3 nodejs-lts git-lfs wget
    fi
    # Windows 下 Git 必须开启长路径支持，否则 repo sync 会失败
    git config --global core.longpaths true
    git config --global core.symlinks true
}

# --- 3. Linux 环境设置 (Ubuntu) ---
setup_linux() {
    info "Configuring Linux (Ubuntu) Environment..."
    export DEBIAN_FRONTEND=noninteractive
    
    # GitHub Actions 磁盘优化
    if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
        info "Optimizing GitHub Runner disk space..."
        sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc
    fi

    sudo apt-get update
    sudo apt-get install -y \
        git-lfs bison flex gnupg build-essential zip curl \
        zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
        lib32ncurses-dev x11proto-core-dev libx11-dev libc++1 \
        lib32z1-dev ccache libgl1-mesa-dev libxml2-utils xsltproc \
        unzip m4 libtinfo5 bc genext2fs liblz4-tool libssl-dev \
        ruby gdb libelf-dev libxcursor-dev libxrandr-dev libxinerama-dev python3-pip
}

# --- 4. macOS 环境设置 ---
setup_macos() {
    info "Configuring macOS Environment..."
    if command -v brew &> /dev/null; then
        brew install git-lfs ccache ninja node python3
    fi
}

# --- 5. 执行流程 ---
case "$OS_TYPE" in
    linux*)   setup_linux ;;
    darwin*)  setup_macos ;;
    msys*|cygwin*|mingw*|windows*) setup_windows ;;
esac

install_repo

# 设置 Git 基础用户信息 (GitHub Action 环境必需)
git config --global user.name "OpenHarmony-Bot"
git config --global user.email "bot@openharmony.io"
git config --global credential.helper store

init_repo() {
    repo init -u $ARKTS_MINIFEST_URL -b OpenHarmony-6.0-Release
    repo sync -c -j8
    bash ./prebuilt_download.sh
}

apply_patch() {
    pushd build/components/ets_frontend
    git apply ../../patch/openharmony6000.patch
    popd
}

init_repo
apply_patch

# build 
python3 ark.py x64.release