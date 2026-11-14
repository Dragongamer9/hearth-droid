#!/usr/bin/env python3
"""Reads an Android super partition image (raw, not sparse): its layout and partitions. Read-only.

Follows AOSP's liblp metadata format (system/core/fs_mgr/liblp/include/liblp/metadata_format.h): geometry at 4096
(and its backup at 8192), then metadata slot 0 at 12288, with the header's and tables' SHA-256 checked.

  super.py show    <super.raw>                        the layout, readable
  super.py plan    <super.raw> <system.img> <partsdir> shell variables for make-super.sh (LP_ARGS, SLOT, ...)
  super.py extract <super.raw> <partsdir>             every partition with content, as <name>.img
"""
import hashlib
import os
import shlex
import struct
import sys

GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030
RESERVED = 4096
GEOMETRY_SIZE = 4096
ATTR_READONLY = 1
FLAG_VIRTUAL_AB = 1
TARGET_LINEAR = 0


def die(msg):
    sys.exit(f"make-super: {msg}")


def cstr(b):
    return b.split(b"\0", 1)[0].decode()


def read_super(path):
    with open(path, "rb") as f:
        f.seek(RESERVED)
        geo = f.read(GEOMETRY_SIZE)
        magic, struct_size = struct.unpack_from("<II", geo, 0)
        if magic != GEOMETRY_MAGIC:
            die(f"{path} isn't a super image (no liblp geometry at 4096; is it still sparse?)")
        max_size, slot_count, block_size = struct.unpack_from("<III", geo, 40)
        g = bytearray(geo[:struct_size]); g[8:40] = b"\0" * 32
        if hashlib.sha256(g).digest() != geo[8:40]:
            die("the super image's geometry checksum is wrong")

        f.seek(RESERVED + 2 * GEOMETRY_SIZE)  # metadata slot 0
        raw = f.read(max_size)
    magic, major, minor, header_size = struct.unpack_from("<IHHI", raw, 0)
    if magic != HEADER_MAGIC:
        die("no metadata header in slot 0 of the super image")
    hdr = bytearray(raw[:header_size]); hdr[12:44] = b"\0" * 32
    if hashlib.sha256(hdr).digest() != raw[12:44]:
        die("the super image's metadata header checksum is wrong")
    tables_size = struct.unpack_from("<I", raw, 44)[0]
    tables = raw[header_size:header_size + tables_size]
    if hashlib.sha256(tables).digest() != raw[48:80]:
        die("the super image's metadata tables checksum is wrong")
    descs = [struct.unpack_from("<III", raw, 80 + 12 * i) for i in range(4)]  # partitions, extents, groups, devices
    flags = struct.unpack_from("<I", raw, 128)[0] if header_size >= 132 else 0

    def entries(i):
        off, n, size = descs[i]
        return [tables[off + k * size: off + (k + 1) * size] for k in range(n)]

    extents = []
    for e in entries(1):
        num_sectors, ttype, tdata, tsrc = struct.unpack_from("<QIQI", e, 0)
        extents.append((num_sectors, ttype, tdata, tsrc))
    groups = []
    for e in entries(2):
        groups.append({"name": cstr(e[:36]), "flags": struct.unpack_from("<I", e, 36)[0],
                       "max": struct.unpack_from("<Q", e, 40)[0]})
    devices = []
    for e in entries(3):
        first, align, align_off, size = struct.unpack_from("<QIIQ", e, 0)
        devices.append({"first": first, "align": align, "align_off": align_off, "size": size,
                        "name": cstr(e[24:60]), "flags": struct.unpack_from("<I", e, 60)[0]})
    parts = []
    for e in entries(0):
        name = cstr(e[:36])
        attrs, first_ext, n_ext, gidx = struct.unpack_from("<IIII", e, 36)
        exts = extents[first_ext:first_ext + n_ext]
        parts.append({"name": name, "attrs": attrs, "group": groups[gidx]["name"], "extents": exts,
                      "size": sum(x[0] for x in exts) * 512})
    return {"version": f"{major}.{minor}", "max_size": max_size, "slots": slot_count, "block_size": block_size,
            "flags": flags, "groups": groups, "devices": devices, "parts": parts}


def show(path):
    s = read_super(path)
    print(f"metadata {s['version']}, {s['slots']} slots of {s['max_size']} bytes, "
          f"{'virtual A/B' if s['flags'] & FLAG_VIRTUAL_AB else 'no virtual A/B'}")
    for d in s["devices"]:
        print(f"device {d['name']}: {d['size']} bytes ({d['size'] >> 20} MB), alignment {d['align']}")
    for g in s["groups"]:
        print(f"group {g['name']}: max {g['max'] >> 20} MB")
    for p in s["parts"]:
        print(f"  {p['name']:<20} {p['group']:<12} {p['size'] >> 20:>6} MB {'readonly' if p['attrs'] & ATTR_READONLY else ''}")


def extract(path, outdir):
    s = read_super(path)
    os.makedirs(outdir, exist_ok=True)
    with open(path, "rb") as f:
        for p in s["parts"]:
            if not p["size"]:
                continue
            with open(os.path.join(outdir, p["name"] + ".img"), "wb") as o:
                for num, ttype, tdata, _src in p["extents"]:
                    if ttype != TARGET_LINEAR:  # a zero extent: holes
                        o.seek(num * 512, 1); continue
                    f.seek(tdata * 512)
                    left = num * 512
                    while left:
                        b = f.read(min(left, 8 << 20))
                        if not b:
                            die(f"{p['name']} runs past the end of the super image")
                        o.write(b); left -= len(b)
                o.truncate()


def plan(path, system_img, partsdir):
    s = read_super(path)
    if len(s["devices"]) != 1:
        die(f"expected one block device in super, found {[d['name'] for d in s['devices']]}")
    dev = s["devices"][0]
    parts = s["parts"]
    names = {p["name"] for p in parts}

    filled = [x for x in ("a", "b") if any(p["name"] == f"system_{x}" and p["size"] for p in parts)]
    if filled:
        slot = filled[0]
    elif "system" in names:
        slot = ""
    else:
        die("no system partition with content in the stock super")
    sfx = f"_{slot}" if slot else ""

    hd_size = (os.path.getsize(system_img) + 4095) // 4096 * 4096
    plan = []
    for p in parts:
        q = {"name": p["name"], "group": p["group"], "size": p["size"],
             "attrs": "readonly" if p["attrs"] & ATTR_READONLY else "none"}
        if p["name"] == f"system{sfx}":
            q.update(size=hd_size, image=os.path.abspath(system_img), attrs="readonly")
        elif p["size"]:
            q["image"] = os.path.join(partsdir, p["name"] + ".img")
        plan.append(q)

    gmax = {g["name"]: g["max"] for g in s["groups"]}
    grp = next(q["group"] for q in plan if q["name"] == f"system{sfx}")
    room = dev["size"] - dev["first"] * 512 - 1024 * 1024

    def used(g):
        return sum(q["size"] for q in plan if q["group"] == g)

    def fits():
        return (not gmax.get(grp) or used(grp) <= gmax[grp]) and sum(q["size"] for q in plan) <= room

    dropped = []
    if not fits():  # product first (the maker's own apps), as with "fastboot delete-logical-partition product"
        for q in plan:
            if q["name"] == f"product{sfx}" and q["size"]:
                q["size"] = 0; q.pop("image", None); dropped.append(q["name"])
    if not fits():
        die(f"Hearth Droid ({hd_size >> 20} MB) doesn't fit in {grp} ({gmax.get(grp, 0) >> 20} MB max, "
            f"{used(grp) >> 20} MB used) even without product")

    args = ["--metadata-size", str(s["max_size"]), "--super-name", dev["name"], "--metadata-slots", str(s["slots"]),
            # lpmake takes the alignment inside --device (separate --alignment flags mean "no --device")
            "--device", f"{dev['name']}:{dev['size']}:{dev['align'] or 1048576}:{dev['align_off']}"]
    if s["flags"] & FLAG_VIRTUAL_AB:
        args.append("--virtual-ab")
    for g in s["groups"]:
        if g["name"] != "default":
            args += ["--group", f"{g['name']}:{g['max']}"]
    for q in plan:
        args += ["--partition", f"{q['name']}:{q['attrs']}:{q['size']}:{q['group']}"]
        if "image" in q:
            args += ["--image", f"{q['name']}={q['image']}"]
    print("LP_ARGS=(" + " ".join(shlex.quote(a) for a in args) + ")")
    print(f"SLOT={shlex.quote(slot)}")
    print(f"DROPPED={shlex.quote(' '.join(dropped))}")
    print(f"SUMMARY={shlex.quote(', '.join(f'''{q['name']} {q['size'] >> 20} MB''' for q in plan if q['size']))}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "show" and len(sys.argv) == 3:
        show(sys.argv[2])
    elif cmd == "extract" and len(sys.argv) == 4:
        extract(sys.argv[2], sys.argv[3])
    elif cmd == "plan" and len(sys.argv) == 5:
        plan(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        sys.exit(__doc__)
