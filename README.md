# fh1-reimagined-arm64

Play [Forza Horizon 1: ReImagined](https://github.com/FH1-ReImagined/ForzaHorizon1-ReImagined),
the recompiled Xbox 360 *Forza Horizon* with its online play brought back,
natively on Snapdragon handhelds running [ArmadaOS](https://armadaos.dev/), such
as the Retroid Pocket 6.

<p align="center">
  <img src="docs/launcher-setup.png" alt="The launcher before the first build: it found the Forza Horizon disc image and Title Update 4 and offers Build" width="49%">
  <img src="docs/launcher-ready.png" alt="The launcher after the build: Update, Play and Add to Steam" width="49%">
</p>

Upstream ships a Windows installer and x86-64 Linux packages, and its ARM64
Linux build has never been played. This repository makes it a native
linux-arm64 game compiled on the handheld itself, started from Steam, with no
emulation of the CPU.

> **Work in progress.** Stage 1 (now): ReImagined as upstream draws it, on its
> emulated Xbox 360 GPU, which is slow on a handheld. Stage 2: the native
> Vulkan renderer that [fh2-recompiled-arm64](https://github.com/Ken5998/fh2-recompiled-arm64)
> uses for Forza Horizon 2 (30 fps on the RP6), adapted to Forza Horizon.

## Install

You need your own **Forza Horizon for Xbox 360**: disc 1 as an ISO and,
recommended, its **Title Update 4** package (`tu00000001_00000000`, or a zip
holding it). Horizon Rally, the 1000 Club and most online players need TU4.
Keep about 35 GB free.

1. In **Desktop Mode**, download `FH1ReImagined-Launcher-linux-arm64.tar.gz`
   from the [latest release](https://github.com/Ken5998/fh1-reimagined-arm64/releases/latest),
   extract it to your home folder and start `FH1ReImagined/fh1-launcher`.
2. Pick the disc image and the title update (the launcher looks in Downloads,
   ROM folders and SD cards) and press **Build**. Keep the handheld on its
   charger: the first build compiles the SDK and the whole recompiled game
   and takes a couple of hours.
3. Press **Play**, or start **Forza Horizon ReImagined** from Steam: the
   handheld's controls reach the game only when Steam starts it. The launcher
   adds the shortcut without artwork; pick yours with SteamGridDB.

ReImagined reads the game from a folder, so the build extracts the disc once
(about 8 GB, in `~/.local/share/FH1ReImagined-arm64/files`) and applies the
update next to it; after that the ISO isn't needed. **Update** in the
launcher pulls this repository's fixes and rebuilds only what they touch.

## Settings

`~/.local/share/FH1ReImagined-arm64/game/forza.toml` holds the settings, with
the same keys ReImagined's own launcher writes. The RP6 defaults follow
upstream's Steam Deck advice: 30 fps (the game's own rate), the 3D scene at
960x540, scene MSAA off and AMD FSR 1 to scale it to the screen.

The game plays offline until you uncomment `live_server` in that file, which
points it at ReImagined's public Forza Live server (Horizon World free roam,
leaderboards, Rivals, clubs). Your online identity is
`~/.local/share/forza/4D5309C9/live_identity.txt`: keep a copy.

Saves and the log (`forza.log`) are in
`~/.local/share/FH1ReImagined-arm64/user`.

If MangoHud or the Steam overlay flicker, the launcher can turn GPU
preemption off (kernel option `msm.enable_preemption=0`, then restart).

## How it builds

- `scripts/prepare.sh` checks out ReImagined at the commit in `upstream.json`
  and ReIGlue, its fork of the ReXGlue SDK, at the commit ReImagined pins,
  with ReIGlue's SDL and FFmpeg patches, then applies `patches/game` and
  `patches/sdk`.
- `scripts/build.sh ISO TU` does the rest on the handheld: the pinned LLVM
  toolchain and sysroot (`toolchain.json`), the disc extraction and the title
  update (upstream's `tools/xiso_extract.py` and `tools/apply_title_update.py`),
  the SDK (`scripts/build-sdk.sh`), the code generation from your
  executables, the game (`scripts/build-game.sh`, ARMv8.2, tuned for the
  RP6), `game/forza.sh` and the Steam shortcut.
- CI builds the SDK natively on an ARM64 runner in Fedora 44 and
  cross-compiled on x86-64, and compiles every ReImagined host source against
  it (`scripts/check-host.sh`). The recompiled code is never built there: no
  game files are ever involved.

## Legal

This repository contains no game files, no code generated from the game and
no binaries built from it. The game is built on your device from a disc you
own. Forza, Forza Horizon and Xbox 360 are trademarks of the Microsoft group
of companies; this project is not affiliated with or endorsed by them.

## License

GPL-3.0, like ReImagined; the patches to ReIGlue are BSD-3-Clause like
ReIGlue. See [NOTICE](NOTICE).
