#!/usr/bin/env bash
# Builds Forza Horizon 1: ReImagined for linux-arm64 from your own Forza
# Horizon (Xbox 360) disc image and, optionally, its Title Update 4, start to
# finish: the toolchain, ReImagined and ReIGlue with this repository's
# patches, the SDK, the recompiled code, the game, and a ready folder to play
# from, added to Steam. Made for the handheld itself (ArmadaOS on the Retroid
# Pocket 6, or any aarch64 Linux). FS_ADD_TO_STEAM=0 leaves Steam alone.
#
#   scripts/build.sh ISO TU [DIR]
#
# ISO  your Forza Horizon (Xbox 360) disc 1 image, or - to keep the one an
#      earlier build used (to update)
# TU   your Title Update 4 package (tu00000001_00000000, or a zip or folder
#      holding it), - to keep the one an earlier build used, or none to build
#      the disc's version
# DIR  where everything goes (default ~/.local/share/FH1ReImagined-arm64);
#      about 35 GB free is needed while building
#
# The disc is extracted once into DIR/files/game (about 8 GB) and the update
# applied into DIR/files/tu4: ReImagined reads the game from a folder. Run it
# again after updating this repository: finished steps are skipped when
# nothing they depend on changed, and the game build recompiles only the
# files a change touches. Nothing made here may be published (it is built
# from your copy of the game).
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
usage() { echo "usage: $0 ISO|- TU|-|none [DIR]" >&2; exit 2; }
[ $# -ge 2 ] || usage
{ [ "$1" = - ] || [ -f "$1" ]; } || usage
{ [ "$2" = - ] || [ "$2" = none ] || [ -e "$2" ]; } || usage
case "$(uname -m)" in
    aarch64|arm64) ;;
    *) echo "error: build on the handheld (aarch64 Linux)" >&2; exit 1 ;;
esac
dir="${3:-$HOME/.local/share/FH1ReImagined-arm64}"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
abs() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
if [ "$1" != - ]; then
    ln -sfn "$(abs "$1")" "$dir/disc.iso"
fi
[ -e "$dir/disc.iso" ] || { echo "error: no disc image yet: give your Forza Horizon ISO instead of -" >&2; exit 1; }
case "$2" in
    -) ;;
    none) rm -f "$dir/title-update" ;;
    *) ln -sfn "$(abs "$2")" "$dir/title-update" ;;
esac
iso="$(readlink -f "$dir/disc.iso")"
tu_pkg=""
[ ! -e "$dir/title-update" ] || tu_pkg="$(readlink -f "$dir/title-update")"
tu=0
[ -z "$tu_pkg" ] || tu=4
tc="$dir/toolchain"
work="$dir/source"
game="$work/reimagined"
sdk="$dir/sdk"
files="$dir/files"
out="$dir/game"
stamps="$dir/.stamps"
mkdir -p "$stamps" "$files"

step() { printf '\n==> [%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
key() { cat "$@" | sha256sum | cut -d' ' -f1; }  # key FILE...: a hash of their contents
done_with() { [ -f "$stamps/$1" ] && [ "$(cat "$stamps/$1")" = "$2" ]; }
mark() { echo "$2" > "$stamps/$1"; }
filekey() { echo "$1 $(stat -L -c '%s %Y' "$1")"; }  # path, size and time
dirkey() { find "$1" -type f -printf '%P %s %T@\n' | sort | sha256sum | cut -d' ' -f1; }

step "Toolchain"
"$repo/scripts/fetch-toolchain.sh" "$tc"
export PATH="$tc/bin:$PATH"

prepare_key="$(key "$repo/upstream.json" "$repo/scripts/prepare.sh" $(ls "$repo"/patches/*/*.patch 2>/dev/null))"
if done_with prepare "$prepare_key" && [ -d "$game/.git" ]; then
    echo "ReImagined already prepared - skipping."
else
    step "Forza Horizon 1: ReImagined and ReIGlue sources"
    "$repo/scripts/prepare.sh" "$work"
    mark prepare "$prepare_key"
fi
# The manifests read the executables from ../extracted/game and ../extracted/tu4.
ln -sfn "$files" "$game/extracted"

iso_key="$(filekey "$iso")"
if done_with extract "$iso_key" && [ -f "$files/game/default.xex" ]; then
    echo "Disc already extracted - skipping."
else
    step "Extracting $iso (a few minutes)"
    rm -rf "$files/game"
    python3 -I "$game/tools/xiso_extract.py" "$iso" info
    python3 -I "$game/tools/xiso_extract.py" "$iso" extract "$files/game"
    rm -rf "$files/game/\$SystemUpdate"  # the console's system update, not used
    for f in default.xex XMediaFacade_default.xex SpeechFacade_default.xex; do
        [ -f "$files/game/$f" ] || { echo "error: $f is not on the disc: is this Forza Horizon (Xbox 360) disc 1?" >&2; exit 1; }
    done
    mark extract "$iso_key"
fi

if [ "$tu" = 4 ]; then
    tu_key="$iso_key $(if [ -d "$tu_pkg" ]; then dirkey "$tu_pkg"; else filekey "$tu_pkg"; fi)"
    if done_with title-update "$tu_key" && [ -f "$files/tu4/default.xex" ]; then
        echo "Title Update 4 already applied - skipping."
    else
        step "Applying Title Update 4 ($tu_pkg)"
        rm -rf "$files/tu4"
        mkdir -p "$files/tu4"
        python3 -I "$game/tools/apply_title_update.py" "$files/game/default.xex" "$tu_pkg" "$files/tu4/default.xex"
        for f in default.xex XMediaFacade_default.xex SpeechFacade_default.xex; do
            [ -f "$files/tu4/$f" ] || { echo "error: the title update did not give $f" >&2; exit 1; }
        done
        mark title-update "$tu_key"
    fi
fi

sdk_key="$prepare_key $(key "$repo/toolchain.json" "$repo/scripts/build-sdk.sh" "$repo/scripts/common.sh" "$repo/cmake/toolchains/linux-arm64.cmake")"
if done_with sdk "$sdk_key" && [ -x "$sdk/bin/rexglue" ]; then
    echo "SDK already built - skipping."
else
    step "Building ReIGlue, the SDK (half an hour or more)"
    "$repo/scripts/build-sdk.sh" "$work/reiglue" "$tc" "$sdk"
    mark sdk "$sdk_key"
fi

if [ "$tu" = 4 ]; then
    manifest=forza_manifest_tu4.toml generated=generated_tu4 xex="$files/tu4"
else
    manifest=forza_manifest.toml generated=generated xex="$files/game"
fi
codegen_key="$sdk_key $tu $(key "$xex"/*.xex)"
if done_with codegen "$codegen_key" && [ -f "$game/forza-recomp/$generated/default/sources.cmake" ]; then
    echo "Recompiled code already generated - skipping."
else
    step "Recompiling the game (PowerPC to C++)"
    (cd "$game/forza-recomp" && "$sdk/bin/rexglue" codegen "$manifest")
    mark codegen "$codegen_key"
fi

step "Building Forza Horizon 1: ReImagined (an hour or more on a handheld)"
"$repo/scripts/build-game.sh" "$game" "$tc" "$sdk" "$tu"

step "Copying the game to $out"
build="$game/forza-recomp/out/build/linux-arm64"
[ "$tu" = 0 ] || build="$build-tu4"
mkdir -p "$out"
for f in forza forza_XMediaFacade_default forza_SpeechFacade_default librexgpu-xenos.so; do
    cp -f "$build/$f" "$out/.$f.new" && mv -f "$out/.$f.new" "$out/$f"
done
cp -f "$(readlink -f "$sdk/lib/librexruntime.so")" "$out/.librexruntime.so.new"
mv -f "$out/.librexruntime.so.new" "$out/librexruntime.so"
for f in forza-telemetry.json LICENSE-Pinyon-Shift; do
    [ ! -f "$build/$f" ] || cp -f "$build/$f" "$out/"
done
[ ! -d "$build/licenses" ] || cp -rf "$build/licenses" "$out/"
cp -f "$repo/LICENSE" "$repo/NOTICE" "$out/"
if [ "$tu" = 4 ]; then touch "$out/.title-update-4"; else rm -f "$out/.title-update-4"; fi
install -m 755 "$repo/config/forza.sh" "$out/forza.sh"
# Your settings stay; the RP6 defaults go in only the first time.
[ -f "$out/forza.toml" ] || cp "$repo/config/forza.toml" "$out/forza.toml"

steam=no
if [ "${FS_ADD_TO_STEAM:-1}" = 1 ]; then
    step "Adding Forza Horizon 1: ReImagined to Steam"
    if python3 -I "$repo/scripts/add-to-steam.py" "$out"; then
        steam=yes
    else
        echo "Warning: the game was not added to Steam; scripts/add-to-steam.py tries again."
    fi
fi

echo
echo "Done at $(date +%H:%M:%S)! Forza Horizon 1: ReImagined is in $out."
if [ "$steam" = yes ]; then
    echo "Play it from Steam (\"Forza Horizon ReImagined\" in the library): the handheld's controls reach it only from there."
else
    echo "Play it from Steam (scripts/add-to-steam.py adds it) so the controls work,"
    echo "or run $out/forza.sh from a terminal."
fi
