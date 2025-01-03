#!/bin/bash

set -euo pipefail

printlog() {
    echo "[INFO] $1"
}

error_exit() {
    echo "[ERROR] $1"
    exit 1
}

pkg_check() {
    if ! command -v "$1" &>/dev/null; then
        error_exit "$1 is not installed. Please install it and try again."
    fi
}

fetch_and_uncompress() {
    local url="$1"
    local dest="$2"
    local temp_file
    temp_file=$(mktemp)

    wget -qO "${temp_file}" "${url}" || error_exit "Failed to download ${url}"
    bsdtar -C "${dest}" -xf "${temp_file}" || error_exit "Failed to extract ${url} to ${dest}"
    rm -f "${temp_file}"
}

# Check input
if [ "$#" -lt 1 ]; then
    error_exit "Usage: $0 <target-directory>"
fi

TARGET="$1"
HOME_DIR="$(pwd)/.gacorprjkt-tc"
PATCHELF_TEMP="${HOME_DIR}/patchelf-temp"
PATCHELF="${HOME_DIR}/patchelf"
GLIBC="${HOME_DIR}/glibc"

printlog "Checking for system requirements..."
pkg_check "wget"
pkg_check "bsdtar"

mkdir -p "${HOME_DIR}"

printlog "Downloading patchelf binary from NixOS repos..."
PATCHELF_VER="0.18.0"
mkdir -p "${PATCHELF_TEMP}"
fetch_and_uncompress "https://github.com/NixOS/patchelf/releases/download/${PATCHELF_VER}/patchelf-${PATCHELF_VER}-x86_64.tar.gz" "${PATCHELF_TEMP}"
mv "${PATCHELF_TEMP}/bin/patchelf" "${PATCHELF}"
rm -rf "${PATCHELF_TEMP}"

printlog "Downloading latest libs from ArchLinux repos..."
mkdir -p "${GLIBC}"
fetch_and_uncompress "https://archlinux.org/packages/core/x86_64/glibc/download" "${GLIBC}"
fetch_and_uncompress "https://archlinux.org/packages/core/x86_64/lib32-glibc/download" "${GLIBC}"
fetch_and_uncompress "https://archlinux.org/packages/core/x86_64/gcc-libs/download" "${GLIBC}"
fetch_and_uncompress "https://archlinux.org/packages/core/x86_64/lib32-gcc-libs/download" "${GLIBC}"
ln -sf "${GLIBC}/usr/lib" "${GLIBC}/usr/lib64"

printlog "Patching libs..."
find "${GLIBC}" -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}' | while read -r bin; do
    bin="${bin::-1}"
    printlog "Patching: ${bin}"
    "${PATCHELF}" --set-rpath "${GLIBC}/usr/lib" --force-rpath --set-interpreter "${GLIBC}/usr/lib/ld-linux-x86-64.so.2" "${bin}"
done

printlog "Patching Toolchain..."
find "${TARGET}" -type f -exec file {} \; | grep 'ELF .* interpreter' | awk '{print $1}' | while read -r bin; do
    bin="${bin::-1}"
    printlog "Patching: ${bin}"
    "${PATCHELF}" --add-rpath "${GLIBC}/usr/lib" --force-rpath --set-interpreter "${GLIBC}/usr/lib/ld-linux-x86-64.so.2" "${bin}"
done

printlog "Done"
