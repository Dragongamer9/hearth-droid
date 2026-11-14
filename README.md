# Hearth Droid

> **Archived (paused, November 2026).** Hearth Droid is on a full pause: no builds, no work. Everything here is kept as it
> is so it can be picked up again; the last test build is 20261114-999eed6 (planned as 1.12, never released).

Android with [Hearth](https://hearthos.fun) built in. It's a remix of a
[TrebleDroid](https://github.com/TrebleDroid/treble_experimentations) Generic System Image (GSI), so one image fits
most Android tablets and phones that support Project Treble and have an unlockable bootloader.

**Status: early test builds.** Only flash it on a device you can put back to stock.

## What's in it

- Hearth for Android (from [Hearth OS](https://github.com/Dragongamer9/hearth-os)) built in as part of the system
- Hearth's boot animation
- Android 15 (TrebleDroid vanilla arm64 A/B, no Google apps)

What's coming, screen by screen: [ROADMAP.md](ROADMAP.md).

## Get it

Test builds: **Actions › Build Hearth Droid**, newest green run, **Artifacts**. Each build is kept for 14 days.

Flashing (and going back): [docs/FLASHING-RT8.md](docs/FLASHING-RT8.md) for the Oukitel RT8.

## How it's built

`build/remix.sh` unpacks the GSI, adds Hearth (app, native libraries, permissions, boot animation), gives every
added file the right SELinux label, checks the filesystem and packs it again. It all runs on GitHub's free runners:
no Android source build is needed for this stage. The base GSI is set in `base.lock`.

## License

GPL-3.0, like Hearth OS. TrebleDroid and Android (AOSP) keep their own licenses.
