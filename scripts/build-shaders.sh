#!/usr/bin/env bash
# Makes the native renderer's shader library (fh1_shaders.nfsp) from your
# Forza Horizon game files on the handheld, the way FH2 Recompiled's
# tools/xenos/biblioteca.sh does for FH2 on a PC:
#   1. finds the Xbox 360 shader containers in the extracted game, the title
#      update, the installed DLC and the executables as loaded
#      (scripts/extract-shader-containers.py);
#   2. translates them to HLSL (FH2 Recompiled's XenosRecomp, built here with
#      the pinned clang);
#   3. compiles them to SPIR-V with DXC, strips and validates them (the
#      shader-tools release fh2-recompiled-arm64 builds for linux-arm64);
#   4. packs the library.
# The D3D library's own shaders, loose in the executable, are added from
# DIR/shader-dump, where forza.sh has the game write the ones the library
# lacks while you play.
#
#   scripts/build-shaders.sh SOURCE TOOLCHAIN DIR TU OUT_FILE
#   FH1_SHADERS_CHECK=1 scripts/build-shaders.sh SOURCE TOOLCHAIN - - -   (tools only)
#
# SOURCE  scripts/prepare.sh's folder (reimagined with the renderer copied in,
#         reiglue, fh2-recompiled)
# DIR     build.sh's folder (files/game, files/tu4, user/, shader-dump/)
# TU      4 to read Title Update 4's executables, 0 for the disc's
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
src="$(cd "$1" && pwd)"
tc="$(cd "$2" && pwd)"
dir="$3"
tu="$4"
outfile="$5"
. "$repo/scripts/common.sh"

fh2="$src/fh2-recompiled"
tools="$src/reimagined/tools"
tp="$src/reiglue/thirdparty"
rec="$fh2/tools/xenos/recomp"
mspack="$tp/libmspack/libmspack/mspack"
work="$src/shaders"
bin="$work/bin"
dxc="$tc/shader-tools/bin/dxc"
opt="$tc/shader-tools/bin/spirv-opt"
val="$tc/shader-tools/bin/spirv-val"
for tool in "$dxc" "$opt" "$val"; do
    [ -x "$tool" ] || { echo "error: $tool is missing" >&2; exit 1; }
done
cc=("$tc/llvm/bin/clang" --sysroot="$tc/sysroot" --ld-path="$tc/bin/ld.lld" $FS_ARCH_FLAGS)
cxx=("$tc/llvm/bin/clang++" --sysroot="$tc/sysroot" --ld-path="$tc/bin/ld.lld" -static-libstdc++ $FS_ARCH_FLAGS)

rm -rf "$work"
mkdir -p "$work/spirv" "$bin"

echo "Shader tools"
"${cc[@]}" -O1 -I"$mspack" "$fh2/tools/xenos/lzx_xmem.c" "$mspack/lzxd.c" "$mspack/system.c" -o "$bin/lzx_xmem"
"${cxx[@]}" -std=c++23 -O1 -I"$rec" -I"$rec/XenosRecomp" -I"$tp/fmt/include" -I"$tp/xxHash" \
    -include "$rec/pch_min.h" -DFMT_HEADER_ONLY -DXXH_INLINE_ALL -DNFSMW_RECOMP -DFH2_RECOMP \
    "$rec/nfsmw_hlsl.cpp" "$rec/XenosRecomp/shader_recompiler.cpp" -o "$bin/xenos_hlsl"
# The packer uses the game's copy of the library code (patches/game: FH1's limits), as the game's loader does.
nativo="$src/reimagined/forza-recomp/src/nativo"
"${cxx[@]}" -std=c++23 -O1 -DFH2_RECOMP -DFH1_RECOMP -I"$nativo" -I"$tp/xxHash" -I"$tp/fmt/include" \
    -DFMT_HEADER_ONLY "$fh2/tools/xenos/empaquetar.cpp" "$nativo/nfsmw_shader_library.cpp" \
    -o "$bin/empaquetar"

if [ "${FH1_SHADERS_CHECK:-0}" = 1 ]; then  # CI: the tools only, no game files
    printf 'float4 main(float4 p : SV_Position) : SV_Target { return p; }\n' > "$bin/check.hlsl"
    "$dxc" -spirv -T ps_6_6 -E main -HV 2021 -fspv-target-env=vulkan1.2 -Fo "$bin/check.spv" "$bin/check.hlsl"
    "$opt" --strip-debug "$bin/check.spv" -o "$bin/check.spv"
    "$val" --target-env vulkan1.2 "$bin/check.spv"
    mkdir -p "$bin/empty"
    "$bin/xenos_hlsl" "$bin/empty" "$bin/hlsl" "$rec/XenosRecomp/shader_common.h" || [ $? -eq 2 ]
    found="$(python3 -I "$repo/scripts/extract-shader-containers.py" "$bin/none" "$bin/lzx_xmem" "$tools" \
        "$bin/empty" 2>&1 || true)"
    grep -q "no shader container found" <<< "$found"
    echo "Shader tools OK"
    exit 0
fi

dir="$(cd "$dir" && pwd)"
xexdir="$dir/files/game"
[ "$tu" = 0 ] || xexdir="$dir/files/tu4"
echo "Shader containers"
python3 -I "$repo/scripts/extract-shader-containers.py" "$work/contenedores" "$bin/lzx_xmem" "$tools" \
    "$dir/files/game/media" "$dir/files/tu4" "$dir/user/0000000000000000/4D5309C9" \
    --xex "$xexdir"/*.xex
dump="$dir/shader-dump"
if compgen -G "$dump/*.bin" > /dev/null; then
    echo "With the $(ls "$dump" | grep -c '\.bin$') shaders the game found missing ($dump)"
    python3 -I "$fh2/tools/xenos/d3d_internos.py" "$dump" "$work/contenedores"
fi

echo "Translating to HLSL"
rc=0
"$bin/xenos_hlsl" "$work/contenedores" "$work/hlsl" "$rec/XenosRecomp/shader_common.h" \
    > "$work/traduccion.log" 2>&1 || rc=$?
tail -1 "$work/traduccion.log"
# 2 means some shaders were skipped, which is normal.
[ $rc -eq 0 ] || [ $rc -eq 2 ] || { echo "error: translation failed (see $work/traduccion.log)" >&2; exit 1; }

echo "Compiling to SPIR-V ($(find "$work/hlsl" -name '*.hlsl' | wc -l) shaders)"
export DXC="$dxc" OPT="$opt" VAL="$val" SPV="$work/spirv"
compile_one() {
    local f="$1" b t e=()
    b="$(basename "$f" .hlsl)"
    if [[ $b == p_* ]]; then t=ps_6_6; else t=vs_6_6; e=(-fvk-invert-y); fi
    if "$DXC" -spirv -T "$t" -E main -HV 2021 -fspv-target-env=vulkan1.2 -fvk-use-dx-layout "${e[@]}" \
           -Fo "$SPV/$b.spv" "$f" > "$SPV/$b.log" 2>&1 &&
       "$OPT" --strip-debug --strip-nonsemantic "$SPV/$b.spv" -o "$SPV/$b.spv" >> "$SPV/$b.log" 2>&1 &&
       "$VAL" --target-env vulkan1.2 --scalar-block-layout "$SPV/$b.spv" >> "$SPV/$b.log" 2>&1; then
        rm -f "$SPV/$b.log"
    else
        rm -f "$SPV/$b.spv"
    fi
}
export -f compile_one
find "$work/hlsl" -name '*.hlsl' -print0 | xargs -0 -n 16 -P "$(nproc)" bash -c 'for f; do compile_one "$f"; done' _
ok="$(find "$work/spirv" -name '*.spv' | wc -l)"
failed="$(find "$work/spirv" -name '*.log' | wc -l)"
cat "$work/spirv"/*.log > "$work/dxc.log" 2>/dev/null || true
rm -f "$work/spirv"/*.log
echo "SPIR-V: $ok compiled, $failed failed"
[ "$ok" -gt 0 ] || { echo "error: no shader compiled (see $work/dxc.log)" >&2; exit 1; }

echo "Packing the library"
"$bin/empaquetar" "$work/contenedores" "$work/spirv" "$work/fh1_shaders.nfsp"
mkdir -p "$(dirname "$outfile")"
cp -f "$work/fh1_shaders.nfsp" "$outfile"
ls -l "$outfile"
# The containers and their translations are only needed while building (the
# logs stay for a look).
rm -rf "$work/contenedores" "$work/hlsl" "$work/spirv"
