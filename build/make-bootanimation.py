#!/usr/bin/env python3
"""Hearth's boot animation (bootanimation.zip): the flame and "Hearth" fade in, then three dots pulse until Android
is ready. The zip is stored (no compression), which Android's boot animation needs.

usage: make-bootanimation.py <out.zip> [accent hex]
"""
import io
import math
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
accent = sys.argv[2] if len(sys.argv) > 2 else "#FF7A3D"
W, H, FPS = 1280, 800, 30
BG = (5, 7, 10)
TEXT = (232, 238, 245)
ACC = tuple(int(accent.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))


def font(size):
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


TITLE = font(64)


def mix(c, a):
    return tuple(int(BG[i] + (c[i] - BG[i]) * a) for i in range(3))


def _bez(p0, p1, p2, p3, n=24):
    return [tuple((1 - t) ** 3 * p0[k] + 3 * (1 - t) ** 2 * t * p1[k] + 3 * (1 - t) * t * t * p2[k] + t ** 3 * p3[k]
                  for k in (0, 1)) for t in (i / n for i in range(1, n + 1))]


# The Hearth flame, the same shape as Hearth's logo (24-unit box):
# M12 2 c1 3 4 5 4 9 a4 4 0 0 1-8 0 c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-5 0-8z, and the hearth line M4 21h16.
FLAME = [(12, 2)]
FLAME += _bez((12, 2), (13, 5), (16, 7), (16, 11))
FLAME += [(12 + 4 * math.cos(math.pi * i / 24), 11 + 4 * math.sin(math.pi * i / 24)) for i in range(1, 25)]
FLAME += _bez((8, 11), (8, 9), (9, 8), (10, 7))
FLAME += _bez((10, 7), (10, 9), (11, 10), (12, 10))
FLAME += _bez((12, 10), (12, 7), (11, 5), (12, 2))


def flame(d, cx, cy, s, color):
    k = s / 12.0
    pts = [(cx + (x - 12) * k, cy + (y - 12) * k) for x, y in FLAME]
    w = max(3, int(k * 1.4))
    d.line(pts, fill=color, width=w, joint="curve")
    d.line([(cx - 8 * k, cy + 9 * k), (cx + 8 * k, cy + 9 * k)], fill=color, width=w)


def frame(logo_a, dots_t):
    im = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(im)
    flame(d, W // 2, 280, 110, mix(ACC, logo_a))
    tw = d.textlength("Hearth", font=TITLE)
    d.text(((W - tw) / 2, 430), "Hearth", font=TITLE, fill=mix(TEXT, logo_a))
    if dots_t is not None:
        for i in range(3):
            a = 0.3 + 0.7 * (0.5 + 0.5 * math.cos(2 * math.pi * (dots_t - i / 3)))
            x = W // 2 - 30 + i * 30
            d.ellipse([x - 6, 556, x + 6, 568], fill=mix(ACC, a))
    b = io.BytesIO()
    im.save(b, "PNG", optimize=True)
    return b.getvalue()


with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as z:
    # Part 0 plays once: the logo fades in. Part 1 loops until Android has started.
    z.writestr("desc.txt", f"{W} {H} {FPS}\np 1 0 part0\np 0 0 part1\n")
    for i in range(30):
        a = (i + 1) / 30
        z.writestr(f"part0/{i:03d}.png", frame(a * a * (3 - 2 * a), None))
    for i in range(30):
        z.writestr(f"part1/{i:03d}.png", frame(1.0, i / 30))

with zipfile.ZipFile(out) as z:
    bad = [i.filename for i in z.infolist() if i.compress_type != zipfile.ZIP_STORED]
    if bad:
        sys.exit("::error title=Boot animation::compressed entries (Android can't play them): " + ", ".join(bad[:5]))
print(f"::notice title=Boot animation::{W}x{H} at {FPS} fps, 60 frames, accent {accent}")
