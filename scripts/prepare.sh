#!/usr/bin/env bash
# Checks out Forza Horizon 1: ReImagined at the commit in upstream.json (or
# REF) and ReIGlue, its SDK, at the commit ReImagined pins in
# tools/build_rexglue_sdk.sh, with ReIGlue's own SDL and FFmpeg patches the way
# that script applies them, then this repository's patches: patches/game/ on
# ReImagined, patches/sdk/ on ReIGlue.
#
#   scripts/prepare.sh WORKDIR [REF]
#
# WORKDIR/reimagined   the patched game project; forza-recomp/generated*,
#                      forza-recomp/out and the game files are left alone
# WORKDIR/reiglue      the patched SDK; its out/ is left alone
#
# Run again, it checks out and patches again; files that end up the same keep
# their times (scripts/keep-times.py), so a later build recompiles only what
# changed. No game files are involved.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mkdir -p "$1" && cd "$1" && pwd)"

field() {
    python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
        "$repo/upstream.json" "$1"
}
ref="${2:-$(field commit)}"
game="$work/reimagined"
sdk="$work/reiglue"
times="$work/.prepare-times.json"
python3 "$repo/scripts/keep-times.py" save "$times" "$game" "$sdk"

if [ ! -d "$game/.git" ]; then
    git clone -q --filter=blob:none -c core.autocrlf=false "$(field repository)" "$game"
fi
git -C "$game" fetch -q origin "$ref" 2>/dev/null || git -C "$game" fetch -q origin
git -C "$game" -c advice.detachedHead=false checkout -q --force "$ref"
# Files an earlier patch added; checkout --force leaves them. Generated code,
# build folders and the game files stay.
git -C "$game" clean -fdq -e generated -e generated_tu4 -e out -e extracted
echo "Forza Horizon 1: ReImagined $(git -C "$game" rev-parse --short HEAD)"

sdk_commit="$(sed -n 's/^REIGLUE_COMMIT=\([0-9a-f]\{40\}\).*/\1/p' "$game/tools/build_rexglue_sdk.sh")"
if [ "${#sdk_commit}" -ne 40 ]; then
    sdk_commit="$(field sdk_commit)"
    echo "note: no ReIGlue commit in tools/build_rexglue_sdk.sh; using upstream.json's"
elif [ "$sdk_commit" != "$(field sdk_commit)" ]; then
    echo "note: ReImagined now pins ReIGlue $sdk_commit (upstream.json: $(field sdk_commit))"
fi
if [ ! -d "$sdk/.git" ]; then
    git init -q "$sdk"
    git -C "$sdk" remote add origin "$(field sdk_repository)"
fi
if [ "$(git -C "$sdk" rev-parse -q --verify HEAD 2>/dev/null)" != "$sdk_commit" ]; then
    git -C "$sdk" fetch -q --depth 1 origin "$sdk_commit"
fi
git -C "$sdk" -c advice.detachedHead=false checkout -q --force "$sdk_commit"
git -C "$sdk" clean -fdq -e out
# Every submodule but MoltenVK (macOS only), reset to its recorded commit.
git -C "$sdk" -c submodule.thirdparty/moltenvk.update=none \
    submodule update --init --recursive --force --depth 1 -q ||
    git -C "$sdk" -c submodule.thirdparty/moltenvk.update=none \
        submodule update --init --recursive --force -q
echo "ReIGlue $(git -C "$sdk" rev-parse --short HEAD)"

apply() {  # apply TREE PATCH...: git apply each patch onto TREE
    local tree="$1" patch
    shift
    for patch in "$@"; do
        [ -e "$patch" ] || continue
        git -C "$tree" apply --whitespace=nowarn "$patch"
        patch="${patch#"$work"/}"
        echo "Applied ${patch#"$repo"/}"
    done
}
# What tools/build_rexglue_sdk.sh does to ReIGlue's SDL and FFmpeg.
apply "$sdk/thirdparty/sdl3" "$sdk"/patches/sdl3/*.patch
apply "$sdk/thirdparty/FFmpeg" "$sdk"/patches/ffmpeg/*.patch
apply "$sdk" "$repo"/patches/sdk/*.patch
apply "$game" "$repo"/patches/game/*.patch

python3 "$repo/scripts/keep-times.py" restore "$times"
