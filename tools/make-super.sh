#!/usr/bin/env bash
# Hearth Droid bootloader install: builds a full super image from a device's stock super.img, with Hearth Droid as its
# system and everything else (vendor, odm, product, system_ext...) exactly as stock. It's flashed from the normal
# bootloader (fastboot flash super ...), for devices whose fastbootd can't be reached over USB (the Oukitel RT8).
# Nothing is flashed here: it only makes the file, and prints the commands.
#
# usage: make-super.sh <stock super.img> <hearth-droid-arm64-ab.img> <out hearth-super.img>
# Needs: python3, simg2img (sudo apt install android-sdk-libsparse-utils). lpdump/lpunpack/lpmake come in bin/.
set -euo pipefail

stock=$1 hd=$2 out=$3
here=$(cd "$(dirname "$0")" && pwd)
bin=$here/bin
die() { echo "make-super: $*" >&2; exit 1; }

for t in lpdump lpunpack lpmake; do [ -x "$bin/$t" ] || die "$bin/$t is missing (it comes with this kit)"; done
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

# 2. Its layout.
"$bin/lpdump" "$work/super.raw" > "$work/dump.txt" 2>&1 || die "lpdump can't read $stock: $(tail -3 "$work/dump.txt")"
python3 - "$work/dump.txt" "$hd" > "$work/plan.sh" <<'PY'
import os, re, shlex, sys
dump, hd = sys.argv[1], sys.argv[2]
t = open(dump).read()
slot0 = t.split("Slot 1:")[0]
def one(pat, d=None):
    m = re.search(pat, slot0, re.M)
    return m.group(1) if m else d
max_size = int(one(r"^Metadata max size: (\d+) bytes"))
slots = int(one(r"^Metadata slot count: (\d+)"))
flags = one(r"^Header flags: (.*)$", "none")
vab = "virtual_ab_device" in flags

def section(name):
    m = re.search(name + r":\n-+\n(.*?)(?=\n\S[^\n]*:\n-+\n|\Z)", slot0, re.S)
    return m.group(1) if m else ""

parts = []
for blk in section("Partition table").split("------------------------"):
    n = re.search(r"Name: (\S+)", blk)
    if not n: continue
    g = re.search(r"Group: (\S+)", blk).group(1)
    a = re.search(r"Attributes: (\S+)", blk)
    attrs = "readonly" if a and "readonly" in a.group(1) else "none"
    size = 0
    for s, e in re.findall(r"(\d+) \.\. (\d+) linear", blk):
        size += (int(e) - int(s) + 1) * 512
    parts.append({"name": n.group(1), "group": g, "attrs": attrs, "size": size})

devs = []
for blk in section("Block device table").split("------------------------"):
    n = re.search(r"Partition name: (\S+)", blk)
    if n: devs.append((n.group(1), int(re.search(r"Size: (\d+) bytes", blk).group(1))))
groups = []
for blk in section("Group table").split("------------------------"):
    n = re.search(r"Name: (\S+)", blk)
    if n: groups.append((n.group(1), int(re.search(r"Maximum size: (\d+) bytes", blk).group(1))))

if len(devs) != 1: sys.exit(f"make-super: expected one block device in super, found {devs}")
if not parts: sys.exit("make-super: no partitions found in the stock super")
names = {p["name"] for p in parts}

# The slot that holds the stock system (a fresh factory super fills slot a and leaves slot b empty).
filled = [s for s in ("a", "b") if any(p["name"] == f"system_{s}" and p["size"] > 0 for p in parts)]
if "system" in names and not filled: slot = ""
elif filled: slot = filled[0]
else: sys.exit("make-super: no system partition with content in the stock super")
sfx = f"_{slot}" if slot else ""

hd_size = os.path.getsize(hd)
hd_size = (hd_size + 4095) // 4096 * 4096
for p in parts:
    if p["name"] == f"system{sfx}":
        p["size"] = hd_size; p["image"] = hd; p["attrs"] = "readonly"
    elif p["size"] > 0:
        p["image"] = os.path.join(os.path.dirname(dump), "parts", p["name"] + ".img")

gmax = dict(groups)
def used(g): return sum(p["size"] for p in parts if p["group"] == g)
dropped = []
grp = next(p["group"] for p in parts if p["name"] == f"system{sfx}")
dev_room = devs[0][1] - 2 * 1024 * 1024 - 2 * slots * max_size
def fits(): return (gmax.get(grp, 0) == 0 or used(grp) <= gmax[grp]) and sum(p["size"] for p in parts) <= dev_room
# Not enough room: product goes first (only the maker's own apps), as with "fastboot delete-logical-partition".
for victim in (f"product{sfx}",):
    if fits(): break
    for p in parts:
        if p["name"] == victim and p["size"] > 0:
            p["size"] = 0; p.pop("image", None); dropped.append(victim)
if not fits():
    sys.exit(f"make-super: Hearth Droid ({hd_size >> 20} MB) doesn't fit in {grp} ({gmax.get(grp,0) >> 20} MB max, "
             f"{used(grp) >> 20} MB used) even without product")

args = ["--metadata-size", str(max_size), "--super-name", devs[0][0], "--metadata-slots", str(slots),
        "--device", f"{devs[0][0]}:{devs[0][1]}"]
if vab: args.append("--virtual-ab")
for g, m in groups:
    if g != "default": args += ["--group", f"{g}:{m}"]
for p in parts:
    args += ["--partition", f"{p['name']}:{p['attrs']}:{p['size']}:{p['group']}"]
    if "image" in p: args += ["--image", f"{p['name']}={p['image']}"]
print("LP_ARGS=(" + " ".join(shlex.quote(a) for a in args) + ")")
print(f"SLOT={shlex.quote(slot)}")
print(f"DROPPED={shlex.quote(' '.join(dropped))}")
print(f"SUMMARY={shlex.quote(', '.join(f'''{p['name']} {p['size'] >> 20} MB''' for p in parts if p['size']))}")
PY
# shellcheck disable=SC1091
. "$work/plan.sh"

# 3. The stock partitions, then the new super with Hearth Droid as the system.
echo "Taking the stock partitions out of super…"
mkdir -p "$work/parts"
"$bin/lpunpack" "$work/super.raw" "$work/parts" >/dev/null
rm -f "$work/super.raw"
echo "Building the Hearth Droid super image…"
"$bin/lpmake" "${LP_ARGS[@]}" --sparse --output "$out" > "$work/lpmake.log" 2>&1 \
  || die "lpmake failed: $(tail -5 "$work/lpmake.log")"

# 4. Check what came out.
"$bin/lpdump" "$out" > "$work/check.txt" 2>&1 || { simg2img "$out" "$work/check.raw" && "$bin/lpdump" "$work/check.raw" > "$work/check.txt"; }
grep -q "Name: system${SLOT:+_$SLOT}" "$work/check.txt" || die "the new super has no system partition"

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
