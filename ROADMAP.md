# Hearth Droid roadmap

Hearth Droid is Android with Hearth built in: a TrebleDroid GSI (Generic System Image) with Hearth for Android as the
system's own app, so one image fits most Treble tablets and phones. Test device: the Oukitel RT8 (its bootloader is
unlocked). The Galaxy Tab A9+ can't be unlocked, so it stays on the Hearth for Android app.

Versions: the owner picks every version number. Until he does, builds are test builds (Actions › Build Hearth Droid ›
Artifacts), named by date and commit.

Every screen in the mockups (the "Hearth Droid mockups" canvas) is on this list, built completely as shown before
it's ticked.

## Stage 1: Hearth built in (GitHub's free runners, no Android build)

- [x] Build pipeline: TrebleDroid Android 15 arm64 A/B vanilla, pinned in `base.lock`
- [x] Hearth for Android built in as a system (priv-app) app, with its native libraries; its privileged permissions
      allowed from Android's own list, so a missing one can't stop Android starting
- [x] Hearth boot animation (flame, "Hearth", pulsing dots) (needs testing on a device)
- [x] Flashing and going-back guide for the RT8 (`docs/FLASHING-RT8.md`)
- [ ] Hearth as the home screen from the first start, with no chooser
- [ ] **Boot screen** mockup: the version line ("Hearth Droid [VERSION] · Android 15 base · running from slot A")
- [ ] **Setup** mockup: Hearth's setup (Language, Wi-Fi, Controller, Google apps, Hearth Link, Pick your look), with
      the controller found by itself
- [ ] **Home** mockup: tabs (Home, Library, Store, Apps, Theater), Continue playing with Stream from PC, Recent row,
      button hints
- [ ] **Quick menu** mockup: Wi-Fi, Bluetooth, rotation lock, Do not disturb, brightness, volume, Battery / Balanced /
      Max (CPU/GPU governors), Hearth Link devices, Settings and Power
- [ ] **Apps** mockup: Hearth apps and Android apps sections, Google Play choice (full Google apps, microG, none)
- [ ] **Settings › System updates** mockup: update ready / Install, slot A and slot B cards, start-up safety (switch
      back after two failed starts, recovery never touched, settings kept), Start previous version, What's new
- [ ] Hearth Droid updates (over the air, from GitHub Releases)
- [ ] Hearth's colours and icons across Android (theme overlays)
- [ ] **Mode switch** mockup: Game Mode / Desktop picker, Start in, keyboard or mouse connects, monitor or TV plugged in
- [ ] **Linux apps** mockup: Debian inside, Linux apps as windows next to Android apps, LINUX tags

## Stage 2: changes inside Android (needs a real Android build, on a rented build machine)

- [ ] **Mantel desktop** mockup: Android's desktop windows restyled as Mantel (top bar, Hearth title bars,
      minimize/maximize/close, dock with running dots and Game Mode button)
- [ ] All of Android's settings inside Hearth: Android's Settings app reskinned for the deep pages
- [ ] Anything in Stage 1 that turns out to need it
