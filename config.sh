#!/usr/bin/env bash

# Kernel name
KERNEL_NAME="QuartiX"

# GKI Version
GKI_VERSION="android12-5.10"

# Build variables
TZ="Asia/Makassar"
KBUILD_BUILD_USER="eraselk"
KBUILD_BUILD_HOST="$KERNEL_NAME"
KBUILD_BUILD_TIMESTAMP=$(date)

# AnyKernel variables
ANYKERNEL_REPO="https://github.com/hazepynut/anykernel"
ANYKERNEL_BRANCH="gki"

# Kernel
KERNEL_REPO="https://github.com/hazepynut/kernel_new"
KERNEL_BRANCH="android12-5.10"
KERNEL_DEFCONFIG="gki_defconfig"
# Defconfigs would be merge in the compiling processes
DEFCONFIGS= # Leave this empty if you don't need to merge any configs

# Manual Hook
KSU_USE_MANUAL_HOOK=false

# Releases repository
GKI_RELEASES_REPO="https://github.com/hazepynut/quartix-releases"

# AOSP Clang
USE_AOSP_CLANG="false"
AOSP_CLANG_VERSION="r547379"

# Custom clang
USE_CUSTOM_CLANG="true"
CUSTOM_CLANG_SOURCE="https://gitlab.com/rvproject27/RvClang"
CUSTOM_CLANG_BRANCH="release/19.x"

# Zip name
BUILD_DATE=$(date -d "$KBUILD_BUILD_TIMESTAMP" +"%y%m%d%H%M")
ZIP_NAME="$KERNEL_NAME-KVER-VARIANT-$BUILD_DATE.zip"
# Note: KVER and VARIANT are dummy.
# it means they will be changed in the build.sh script.

# Export variable that will be used not only locally (variable in make, variable that will be used by scripts in the kernel source)
export BUILD_DATE
export KBUILD_BUILD_USER
export KBUILD_BUILD_HOST
export KBUILD_BUILD_TIMESTAMP
