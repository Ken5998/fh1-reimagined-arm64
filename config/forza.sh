#!/usr/bin/env bash
# Starts Forza Horizon 1: ReImagined (linux-arm64). Installed beside the game
# as forza.sh by scripts/build.sh; Steam starts this.
#
# The game files are the ones build.sh extracted from your disc image
# (../files/game) and, with Title Update 4, the update it applied
# (../files/tu4). Settings are in forza.toml beside this script; arguments
# given to this script are passed on to the game and win over forza.toml.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
data="$(cd "$here/.." && pwd)"
mkdir -p "$data/user"

game_files="$data/files/game"
[ -f "$game_files/default.xex" ] ||
    { echo "error: no game files in $game_files: run the launcher's Build again" >&2; exit 1; }
update=()
if [ -f "$here/.title-update-4" ]; then
    [ -f "$data/files/tu4/default.xex" ] ||
        { echo "error: Title Update 4 is missing from $data/files/tu4: run the launcher's Build again" >&2; exit 1; }
    update=(--update_data_root="$data/files/tu4")
fi

# One session per log, like ReImagined's launcher: the last one stays as
# forza.previous.log.
log="$data/user/forza.log"
[ ! -f "$log" ] || mv -f "$log" "$data/user/forza.previous.log"

# The native renderer (FH2 Recompiled's, experimental) instead of the
# emulated Xenos GPU: FH1_RENDERER=native %command% in the game's Steam launch
# options. It needs the shader library build.sh makes from your game files
# (fh1_shaders.nfsp beside this). Shaders the library lacks (the D3D
# library's own, loose in the executable) are written to ../shader-dump as you
# play; the next build adds them to the library.
# What was chosen, and why, goes to ../user/renderer.txt beside the log.
renderer=()
library="$here/fh1_shaders.nfsp"
if [ -f "$library" ]; then
    library_note="$library, $(stat -c '%s bytes, %y' "$library")"
else
    library_note="missing ($library): the launcher's Build/Update makes it"
fi
chosen="emulated GPU"
if [ "${FH1_RENDERER:-emulated}" = native ]; then
    if [ -f "$library" ]; then
        mkdir -p "$data/shader-dump"
        renderer=(--nfsmw_renderizador=nativo
            --fh2_nativo_vertices_sin_espera=true --fh2_nativo_destinos_exactos=true
            --fh2_nativo_volcar_sueltos="$data/shader-dump")
        chosen="native renderer"
    else
        chosen="emulated GPU (no shader library)"
        echo "warning: no $library (run the launcher's Build again): using the emulated GPU" >&2
    fi
fi
printf '%s\nFH1_RENDERER=%s\nshader library: %s\nrenderer: %s\n' "$(date '+%F %T')" \
    "${FH1_RENDERER-<not set>}" "$library_note" "$chosen" > "$data/user/renderer.txt" || true

export LD_LIBRARY_PATH="$here${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/forza" "${renderer[@]}" --game_data_root="$game_files" "${update[@]}" \
    --user_data_root="$data/user" --log_file="$log" \
    "$@"
