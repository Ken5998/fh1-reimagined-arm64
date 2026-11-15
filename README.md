# fh1-reimagined-arm64

Work in progress: play [Forza Horizon 1: ReImagined](https://github.com/FH1-ReImagined/ForzaHorizon1-ReImagined),
the recompiled Xbox 360 *Forza Horizon*, natively on Snapdragon handhelds running
[ArmadaOS](https://armadaos.dev/), such as the Retroid Pocket 6.

The plan, in two steps:

1. A native linux-arm64 build compiled on the handheld itself from your own copy of the
   game, with ReImagined's emulated Xbox 360 GPU.
2. The native Vulkan renderer that [fh2-recompiled-arm64](https://github.com/Ken5998/fh2-recompiled-arm64)
   uses for Forza Horizon 2, adapted to Forza Horizon 1.

No game code or data is in this repository, and nothing built from your copy of the game
may be published.

## License

GPL-3.0, like the projects it builds. See [NOTICE](NOTICE).
