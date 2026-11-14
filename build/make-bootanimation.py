#!/usr/bin/env python3
"""Hearth Droid's boot animation (bootanimation.zip), made from one of Hearth OS's startup animations
(hearth-os: os/system_files/usr/share/hearth/startup-movies/hearth-<id>-16x10.webm, fetched at build time, never
copied into this repo). Like on Hearth OS:

  part0  plays once: the animation up to the lit Hearth mark
  part1  loops while Android finishes starting: the lit mark, gently breathing
  part2  plays to the end once Android is ready: the animation's own fade-out

Android needs the zip stored (no compression); frames are JPEG to keep /system small.

usage: make-bootanimation.py <movie.webm> <out.zip>      (ffmpeg, Pillow)
"""
import glob
import io
import os
import subprocess
import sys
import tempfile
import zipfile

from PIL import Image, ImageStat

movie, out = sys.argv[1], sys.argv[2]
FPS = 30


def die(msg):
    sys.exit(f"::error title=Boot animation::{msg}")


with tempfile.TemporaryDirectory() as tmp:
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", movie, "-vsync", "0", os.path.join(tmp, "%04d.png")],
                       capture_output=True, text=True)
    if r.returncode:
        die(f"ffmpeg couldn't read {movie}: {r.stderr[-500:]}")
    frames = sorted(glob.glob(os.path.join(tmp, "*.png")))
    if len(frames) < 60:
        die(f"{movie} has only {len(frames)} frames")
    W, H = Image.open(frames[0]).size

    # Where the fade-out starts: the last frame still near the movie's brightest, before it drops for good.
    lum = [ImageStat.Stat(Image.open(f).convert("L").resize((160, 100))).mean[0] for f in frames]
    peak = max(lum[len(lum) // 2:])
    fade = len(frames)
    for i in range(len(frames) - 1, len(frames) // 2, -1):
        if lum[i] >= peak * 0.95:
            fade = i + 1
            break
    if fade >= len(frames) - 2:
        fade = len(frames)  # no fade-out in this one: part2 stays empty
    intro = frames[:fade]
    # The loop: the last second of the lit mark, forwards then backwards, so it breathes without a jump.
    hold = intro[-FPS:] if len(intro) > FPS else intro
    loop = hold + hold[-2:0:-1]
    outro = frames[fade:]

    def jpg(path):
        b = io.BytesIO()
        Image.open(path).convert("RGB").save(b, "JPEG", quality=90, optimize=True)
        return b.getvalue()

    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
        desc = f"{W} {H} {FPS}\np 1 0 part0\np 0 0 part1\n"
        if outro:
            desc += "c 1 0 part2\n"
        z.writestr("desc.txt", desc)
        for name, part in (("part0", intro), ("part1", loop), ("part2", outro)):
            for i, f in enumerate(part):
                z.writestr(f"{name}/{i:04d}.jpg", jpg(f))

with zipfile.ZipFile(out) as z:
    bad = [i.filename for i in z.infolist() if i.compress_type != zipfile.ZIP_STORED]
    if bad:
        die("compressed entries (Android can't play them): " + ", ".join(bad[:5]))
size = os.path.getsize(out)
print(f"::notice title=Boot animation::{os.path.basename(movie)}: {W}x{H} at {FPS} fps, intro {len(intro)} frames, "
      f"loop {len(loop)}, fade-out {len(outro)}, {size >> 20} MB")
