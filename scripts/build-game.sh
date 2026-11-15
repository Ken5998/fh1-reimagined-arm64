#!/usr/bin/env bash
# Builds Forza Horizon 1: ReImagined for linux-arm64 (the forza program and
# its two recompiled guest modules) against the SDK build-sdk.sh installed:
# natively on aarch64, or cross-compiled on x86-64.
#
#   scripts/build-game.sh REIMAGINED TOOLCHAIN SDK [TU]
#
# REIMAGINED  the tree prepare.sh made (WORKDIR/reimagined), whose
#             forza-recomp/generated (or generated_tu4) holds what codegen
#             made from the game
# TOOLCHAIN   fetch-toolchain.sh's folder
# SDK         build-sdk.sh's PREFIX
# TU          4 for the Title Update 4 build (the default), 0 for the disc's
#
# The build goes to REIMAGINED/forza-recomp/out/build/linux-arm64[-tu4]. The
# toolchain file makes CMake treat every build as a cross build, so the game
# build never runs codegen itself: build.sh runs it first.
#
# Parallel jobs: FS_JOBS, else one per logical CPU but at most one per 2 GB of
# memory (the recompiled files are huge).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
game="$(cd "$1" && pwd)"
export FS_ARM64_TOOLCHAIN="$(cd "$2" && pwd)"
sdk="$(cd "$3" && pwd)"
tu="${4:-4}"
llvm="$FS_ARM64_TOOLCHAIN/llvm/bin"
export PATH="$FS_ARM64_TOOLCHAIN/bin:$PATH"
. "$repo/scripts/common.sh"
jobs="$(build_jobs)"
echo "Building with $jobs parallel jobs ($(nproc) CPU threads)"

src="$game/forza-recomp"
case "$tu" in
    4) generated="$src/generated_tu4"; build="$src/out/build/linux-arm64-tu4" ;;
    0) generated="$src/generated"; build="$src/out/build/linux-arm64" ;;
    *) echo "error: TU must be 4 or 0" >&2; exit 2 ;;
esac
[ -f "$generated/default/sources.cmake" ] || { echo "error: no generated code in $generated" >&2; exit 1; }

cmake -S "$src" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    "-DCMAKE_TOOLCHAIN_FILE=$repo/cmake/toolchains/linux-arm64.cmake" \
    "-DCMAKE_C_COMPILER=$llvm/clang" "-DCMAKE_CXX_COMPILER=$llvm/clang++" \
    "-DCMAKE_C_FLAGS=$FS_ARCH_FLAGS" "-DCMAKE_CXX_FLAGS=$FS_ARCH_FLAGS" \
    "-DCMAKE_PREFIX_PATH=$sdk" "-Drexglue_DIR=$sdk/lib/cmake/rexglue" \
    "-DFORZA_REXGLUE=$sdk/bin/rexglue" "-DFORZA_XENOS_PLUGIN=$sdk/lib/librexgpu-xenos.so" \
    "-DFORZA_TITLE_UPDATE=$tu" "-DFORZA_BUILD_ID=arm64-$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo dev)"
# Twice, like upstream's tools/build.sh: ninja sees the guest modules'
# sources only on its second run.
cmake --build "$build" --parallel "$jobs"
cmake --build "$build" --parallel "$jobs"

for f in forza forza_XMediaFacade_default forza_SpeechFacade_default librexgpu-xenos.so; do
    check_aarch64 "$build/$f"
done
