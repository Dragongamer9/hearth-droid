#!/usr/bin/env bash
# Hearth Droid bootloader install: builds a full super image from a device's stock super.img, with Hearth Droid as its
# system and everything else (vendor, odm, product, system_ext...) exactly as stock. It's flashed from the normal
# bootloader (fastboot flash super ...), for devices whose fastbootd can't be reached over USB (the Oukitel RT8).
# Nothing is flashed here: it only makes the file, and prints the commands.
#
# usage: make-super.sh <stock super.img> <hearth-droid-arm64-ab.img> <out hearth-super.img>
# Needs: python3, simg2img (sudo apt install android-sdk-libsparse-utils). lpmake comes in bin/, super.py next to this.
set -euo pipefail

stock=$1 hd=$2 out=$3
here=$(cd "$(dirname "$0")" && pwd)
bin=$here/bin
die() { echo "make-super: $*" >&2; exit 1; }

for t in lpmake; do [ -x "$bin/$t" ] || die "$bin/$t is missing (it comes with this kit)"; done
[ -f "$here/super.py" ] || die "super.py is missing (it comes with this kit)"
command -v simg2img >/dev/null || die "simg2img isn't installed: sudo apt install android-sdk-libsparse-utils"
[ -f "$stock" ] || die "can't find the stock super image: $stock"
[ -f "$hd" ] || die "can't find the Hearth Droid image: $hd"
[ "$(blkid -o value -s TYPE "$hd" 2>/dev/null || true)" = ext4 ] || \
  [ "$(head -c 1084 "$hd" | tail -c 2 | od -An -tx1 | tr -d ' ')" = "53ef" ] || die "$hd isn't a Hearth Droid system image (no ext4 inside)"

work=$(mktemp -d "${TMPDIR:-/var/tmp}/hearth-super.XXXXXX")
trap 'rm -rf "$work"' EXIT
need=$(( ($(stat -c %s "$stock") + $(stat -c %s "$hd")) * 3 ))
free=$(( $(df --output=avail -B1 "$work" | tail -1) ))
[ "$free" -gt "$need" ] || die "not enough free space in $work: need about $((need/1024/1024/1024)) GB"

# 1. The stock super, unsparsed.
if [ "$(head -c4 "$stock" | od -An -tx1 | tr -d ' \n')" = "3aff26ed" ]; then
  command -v simg2img >/dev/null || die "simg2img isn't installed: sudo apt install android-sdk-libsparse-utils"
  echo "Unpacking the stock super image (a few minutes)…"
  simg2img "$stock" "$work/super.raw"
else
  ln -s "$(readlink -f "$stock")" "$work/super.raw"
fi

# 2. Its layout, and the plan for the new one.
python3 "$here/super.py" plan "$work/super.raw" "$hd" "$work/parts" > "$work/plan.sh"
# shellcheck disable=SC1091
. "$work/plan.sh"

# 3. The stock partitions, then the new super with Hearth Droid as the system.
echo "Taking the stock partitions out of super…"
mkdir -p "$work/parts"
python3 "$here/super.py" extract "$work/super.raw" "$work/parts"
rm -f "$work/super.raw"
echo "Building the Hearth Droid super image…"
"$bin/lpmake" "${LP_ARGS[@]}" --sparse --output "$out" > "$work/lpmake.log" 2>&1 \
  || die "lpmake failed: $(tail -5 "$work/lpmake.log")"

# 4. Check what came out.
simg2img "$out" "$work/check.raw" 2>/dev/null || cp --sparse=always "$out" "$work/check.raw"
python3 "$here/super.py" show "$work/check.raw" > "$work/check.txt"
rm -f "$work/check.raw"
grep -qE "^  system${SLOT:+_$SLOT} " "$work/check.txt" || die "the new super has no system partition"
cat "$work/check.txt"

echo
echo "Done: $out ($(du -h "$out" | cut -f1))"
echo "  Partitions: $SUMMARY"
[ -n "$DROPPED" ] && echo "  Left out to make room: $DROPPED (the maker's own apps)"
s=${SLOT:-a}
echo
echo "To flash it, with the tablet on the normal fastboot screen, from the stock firmware folder:"
echo "  sudo fastboot set_active $s"
echo "  for p in boot vendor_boot dtbo; do [ -f \$p.img ] && sudo fastboot flash \${p}_$s \$p.img; done"
echo "  sudo fastboot --disable-verity --disable-verification flash vbmeta_$s vbmeta.img"
echo "  sudo fastboot flash super $(readlink -f "$out")"
echo "  sudo fastboot -w"
echo "  sudo fastboot reboot"
echo
echo "Way back: the same, with the stock super.img in place of $(basename "$out")."
