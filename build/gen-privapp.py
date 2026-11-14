#!/usr/bin/env python3
"""Writes privapp-permissions-hearth.xml for Hearth's APK.

Android refuses to finish starting (with ro.control_privapp_permissions=enforce) when an app in priv-app asks for a
privileged permission that no privapp-permissions file allows. So this lists exactly the privileged permissions the APK
asks for, read from this GSI's own framework-res.apk, and the build never guesses.

usage: gen-privapp.py <aapt2> <hearth.apk> <framework-res.apk> <out.xml>
"""
import re
import subprocess
import sys

aapt2, apk, framework, out = sys.argv[1:5]


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


# The package name and the permissions the APK asks for.
perm_dump = run(aapt2, "dump", "permissions", apk)
pkg = re.search(r"^package: (\S+)", perm_dump, re.M).group(1)
wanted = set(re.findall(r"uses-permission: name='([^']+)'", perm_dump))

# Every permission the framework defines, with its protection level.
tree = run(aapt2, "dump", "xmltree", "--file", "AndroidManifest.xml", framework)
privileged = set()
name, level, in_perm = None, None, False
for line in tree.splitlines() + ["E: end"]:
    s = line.strip()
    if s.startswith("E: "):
        if name and level is not None and level & 0x10:  # PROTECTION_FLAG_PRIVILEGED
            privileged.add(name)
        name, level = None, None
        in_perm = s.startswith("E: permission ")
        continue
    if not in_perm:
        continue
    m = re.search(r'android:name\(0x01010003\)="([^"]+)"', s)
    if m:
        name = m.group(1)
    m = re.search(r"android:protectionLevel\(0x01010009\)=(?:\(type 0x1[01]\))?0x([0-9a-fA-F]+)", s)
    if m:
        level = int(m.group(1), 16)

if not privileged:
    sys.exit("::error title=privapp::read no privileged permissions from framework-res.apk; aapt2's output changed?")

need = sorted(wanted & privileged)
with open(out, "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n')
    f.write("<!-- Made by hearth-droid's build/gen-privapp.py: the privileged permissions Hearth asks for. -->\n")
    f.write("<permissions>\n")
    f.write(f'    <privapp-permissions package="{pkg}">\n')
    for p in need:
        f.write(f'        <permission name="{p}"/>\n')
    f.write("    </privapp-permissions>\n</permissions>\n")

print(f"::notice title=privapp::{pkg}: {len(wanted)} permissions asked for, {len(need)} privileged "
      f"({', '.join(need) or 'none'}); {len(privileged)} privileged permissions in this Android")
