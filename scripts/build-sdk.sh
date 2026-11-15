#!/usr/bin/env bash
# Builds ReIGlue, the SDK Forza Horizon 1: ReImagined is made with, for
# linux-arm64 and installs it into PREFIX: the recompiler (bin/rexglue), the
# runtime (lib/librexruntime.so), the Xenos GPU plugin
# (lib/librexgpu-xenos.so) and the headers and CMake files the game build
# takes. Natively on aarch64 (the handheld), or cross-compiled on x86-64.
#
#   scripts/build-sdk.sh REIGLUE TOOLCHAIN PREFIX
#
# REIGLUE    the tree prepare.sh made (WORKDIR/reiglue)
# TOOLCHAIN  fetch-toolchain.sh's folder
# PREFIX     where the SDK is installed
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$(cd "$1" && pwd)"
export FS_ARM64_TOOLCHAIN="$(cd "$2" && pwd)"
prefix="$(mkdir -p "$3" && cd "$3" && pwd)"
llvm="$FS_ARM64_TOOLCHAIN/llvm/bin"
export PATH="$FS_ARM64_TOOLCHAIN/bin:$PATH"
. "$repo/scripts/common.sh"
build="$sdk/out/build/linux-arm64"

# The linux-arm64 preset's settings, as one Release build with the pinned
# compiler and sysroot. No tests, no Tracy profiler.
cmake -S "$sdk" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchains/linux-arm64.cmake" \
    "-DCMAKE_C_COMPILER=$llvm/clang" "-DCMAKE_CXX_COMPILER=$llvm/clang++" \
    "-DCMAKE_C_FLAGS=$FS_ARCH_FLAGS" "-DCMAKE_CXX_FLAGS=$FS_ARCH_FLAGS" -DCMAKE_CXX_STANDARD=23 \
    "-DCMAKE_INSTALL_PREFIX=$prefix" \
    -DREXGLUE_BUILD_TESTS=OFF -DREXGLUE_ENABLE_TRACY=OFF -DREXGLUE_USE_VULKAN=ON -DSDL_HIDAPI_LIBUSB=OFF
cmake --build "$build" --target install --parallel "$(build_jobs)"

for f in bin/rexglue lib/librexruntime.so lib/librexgpu-xenos.so; do
    check_aarch64 "$prefix/$f"
done
