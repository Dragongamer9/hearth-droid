# Putting Hearth Droid on the Oukitel RT8 (and going back)

**Read all of this first.** Flashing Hearth Droid replaces the RT8's Android system and wipes its data, which includes
Hearth OS (Droidian) if it's on the tablet now. Nothing here touches the bootloader or recovery, and the RT8 can
always be put back to stock with Oukitel's firmware and SP Flash Tool (MediaTek's flasher works even when the tablet
won't start).

## Before you start (once)

1. **Stock firmware.** Download the RT8's stock firmware from Oukitel (the version matching your tablet) and keep it.
   It's your way back, whatever happens. Unzip it: you'll need its `vbmeta.img`.
2. **SP Flash Tool** (for the way back) and **platform-tools** (adb and fastboot) on your PC.
3. **Back up** anything on the tablet you want to keep (photos, game saves). Flashing wipes it.
4. Charge the RT8 to over 50%.

## Flash it

1. Download the test build: Actions › **Build Hearth Droid** › newest green run › Artifacts ›
   `hearth-droid-test-…`. Unzip it, check the SHA-256 (`sha256sum -c hearth-droid-arm64-ab.img.xz.sha256`), then
   `xz -d hearth-droid-arm64-ab.img.xz`.
2. Start the RT8 in its bootloader (`adb reboot bootloader`, or power + volume down) and connect it.
3. Turn off verified boot with the stock `vbmeta.img` (Android won't start an unofficial system otherwise):

       fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img

4. Go to fastbootd (the system partitions live there) and flash:

       fastboot reboot fastboot
       fastboot flash system hearth-droid-arm64-ab.img

   If it says there isn't enough space: `fastboot delete-logical-partition product_a` (or `product` on a tablet
   without slots), then flash again. Product only holds the stock apps.

5. Wipe data and start:

       fastboot -w
       fastboot reboot

The first start takes a few minutes (Hearth's boot animation stays on while Android sets itself up). If the RT8 shows
the boot animation for more than 10 minutes, or keeps restarting, see below.

## If it doesn't start

- Hold power + volume down to get back to the bootloader, then flash the stock `system.img` from the firmware the
  same way (step 4), and `fastboot -w`.
- If even the bootloader won't come up: SP Flash Tool with the stock firmware's scatter file, **Download Only**
  (never Format All: that erases the tablet's IMEI and calibration).
- Send what happened (what's on the screen, how long) and, if adb works, `adb logcat -b all -d > logcat.txt`.

## Going back to Hearth OS (Droidian)

Flash the stock firmware with SP Flash Tool (Download Only), then put Hearth OS back with hearth-devices' RT8 guide.

## From the bootloader (when fastbootd isn't seen over USB)

On the RT8, fastbootd (`fastboot reboot fastboot`) may not show up on the PC at all. Then Hearth Droid goes in as a
whole new super partition, flashed from the normal bootloader:

1. Download the kit: Actions › **Bootloader install kit** › newest green run › Artifacts ›
   `hearth-droid-bootloader-kit`. Unzip it next to the Hearth Droid image.
2. `sudo apt install android-sdk-libsparse-utils f2fs-tools` (simg2img, and make_f2fs for `fastboot -w`), then build the image (it only makes a file; it needs
   about 20 GB free):

       ./make-super.sh <stock firmware folder>/super.img hearth-droid-arm64-ab.img hearth-super.img

3. It prints the flash commands at the end (which slot, stock boot files, `fastboot flash super`, wipe, reboot).
   Run them with the tablet on the normal fastboot screen.

Way back: the same commands with the stock firmware's `super.img`.
