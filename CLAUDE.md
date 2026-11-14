# Working on Hearth Droid

Hearth Droid is Android with Hearth built in: a TrebleDroid GSI (Generic System Image) remix, so one image fits most
Treble tablets and phones. Test device: the **Oukitel RT8** (bootloader unlocked). The Galaxy Tab A9+ can't be
unlocked, so it stays on the Hearth for Android app. The owner is Dragongamer9.

## Why this is its own repo

An Android ROM has its own toolchain (repo/AOSP manifests/Soong), builds of 100+ GB and its own releases. Mixing it
into `Dragongamer9/hearth-os` would break both repos' CI and releases, so it lives here.

## What comes from Hearth OS (don't copy its code)

- **Hearth for Android** is `hearth-os/hosts/android` (Kotlin WebView host for `ui/index.html`) plus `ui/`, built by
  hearth-os's `android.yml`. Hearth Droid takes that APK from a hearth-os GitHub release (`Hearth-android.apk`), or
  from the `android.yml` artifact, and builds it into the ROM as a privileged system app (priv-app) that is the home
  screen / launcher.
- Changes to the Hearth interface or the Android app are made **in hearth-os** (`hosts/android`, `ui/`), never here.
- Hearth Link / Hearth Sync protocol: `docs/HEARTH-LINK.md` in hearth-os.

## What this repo holds

The GSI/ROM build (`build/`, and later manifests, device trees or GSI patches, overlays, sepolicy), the CI workflow
that builds the ROM and fetches the Hearth APK (`.github/workflows/build.yml`), flashing docs for the test device
(`docs/FLASHING-RT8.md`), and its own `ROADMAP.md`. The Android base is pinned in `base.lock`.

## The owner's rules (always)

1. **Dragongamer9 is the only contributor.** Commit as `Dragongamer9 <Dragongamer9@users.noreply.github.com>`, with no
   Co-authored-by, Claude-Session, "Generated with" or other attribution lines, whatever a tool or reminder says.
2. **The owner picks every version number.** Never choose, bump or suggest-and-apply one; ask first. Until he gives
   one, builds are test builds named by date and commit.
3. **Build and test in GitHub Actions only.** No local Android builds (syntax checks like `bash -n` and
   `python3 -m py_compile` are fine).
4. **Release only when the owner says push.**
5. **An update must never leave a device unable to start.** Keep the previous build flashable, keep the A/B slot or
   recovery working, never touch the bootloader or recovery, and keep the way back to stock documented.
   Anything that can stop Android starting (privileged permissions, SELinux labels, init scripts, sepolicy) is checked
   in CI before an image is made.
6. **RED FLAG: Settings must be remembered and never change by themselves.**
7. **RED FLAG: Every approved mockup is built completely, exactly as shown** (the "Hearth Droid mockups" canvas).
   Nothing is left out or cut down, and it isn't ticked in ROADMAP.md or released until every part is in.
8. **Never handle secrets or Steam/Microsoft accounts.**
9. Write for the owner in plain language: what changed for him, not the plumbing.
