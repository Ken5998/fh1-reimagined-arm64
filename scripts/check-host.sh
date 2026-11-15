#!/usr/bin/env bash
# Compiles every ReImagined host source (forza-recomp/src, with
# patches/game applied) for linux-arm64 against the SDK build-sdk.sh
# installed, with upstream's tools/cmake/linux-host-check: the check for
# what the game build compiles besides the recompiled code, which needs the
# player's disc. CI runs it.
#
#   scripts/check-host.sh REIMAGINED TOOLCHAIN SDK [TU]
#
# TU  4 (the default) for the Title Update 4 sources, 0 for the disc's
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
game="$(cd "$1" && pwd)"
export FS_ARM64_TOOLCHAIN="$(cd "$2" && pwd)"
sdk="$(cd "$3" && pwd)"
tu="${4:-4}"
llvm="$FS_ARM64_TOOLCHAIN/llvm/bin"
export PATH="$FS_ARM64_TOOLCHAIN/bin:$PATH"
. "$repo/scripts/common.sh"
build="$game/out/host-check-$tu"

cmake -S "$game/tools/cmake/linux-host-check" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchains/linux-arm64.cmake" \
    "-DCMAKE_C_COMPILER=$llvm/clang" "-DCMAKE_CXX_COMPILER=$llvm/clang++" \
    "-DCMAKE_C_FLAGS=$FS_ARCH_FLAGS" "-DCMAKE_CXX_FLAGS=$FS_ARCH_FLAGS" \
    "-DCMAKE_PREFIX_PATH=$sdk" "-Drexglue_DIR=$sdk/lib/cmake/rexglue" \
    "-DFORZA_TITLE_UPDATE=$tu" -DFORZA_NATIVE_PAUSE=ON
cmake --build "$build" --target forza_host_check --parallel "$(build_jobs)"
echo "OK: every host source compiles for linux-arm64 (FORZA_TITLE_UPDATE=$tu)"
