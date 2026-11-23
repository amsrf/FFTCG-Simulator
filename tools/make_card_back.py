#!/usr/bin/env python3
"""Build assets/card_back/crystal_card_back.png from the source art.

  python3 tools/make_card_back.py [source.png]     (default ~/Downloads/crystal_card_back.png)

1. Crop to the printed frame's outer edge and resize to the card mesh's 0.715 ratio (858 x 1200, 1 px = 0.5 mm).
2. Optionally (RECOLOUR) recolour the frame: the source's silver/white band becomes dark brown, and the silver lattice lines bronze. Its shading is kept (each pixel's
   brightness picks a point on a brown ramp) and the bright bevel lines become a warm bronze, so it still reads as
   a moulded frame. Only light, low-saturation pixels inside the outer band are touched; the art inside is unchanged.
"""
import os
import sys
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Downloads/crystal_card_back.png")
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "card_back", "crystal_card_back.png")

CROP = (29, 23, 995, 1512)      # the frame's outer edge in the 1024 x 1536 source
SIZE = (858, 1200)              # 0.429 x 0.6 m
# The ORIGINAL silver frame and lattice are used (user's call: the brown blended into the wooden board). Set True to
# recolour them brown/bronze with the constants below; card_glass_edge.gdshader's card-stock colour must then follow.
RECOLOUR = False
BAND = 52                       # px from the edge (output size) that may be frame; the frame is ~35-46 px wide
# The LATTICE and the frame's inner silver bevel (a chamfer across each inner corner) are silver too, and read as white
# marks against the dark field, worst where they meet the frame. Every silver pixel outside the frame band is turned
# bronze (darker than the frame's lines), except inside CRYSTAL_BOX: the crystal and its glow keep their own light.
LINE_MIN_LUM = 55               # darker than this is the black field, left alone
LINE_MAX_TEAL = 9               # green over red: the starry top field is TEAL (its stars too); the silver lines are not
CRYSTAL_BOX = (250, 300, 610, 810)

# Brightness -> colour ramp for the frame: the source frame is ~200-225 in its flat parts, ~250 on its bevel lines.
# Darkened by about a third (was 28/62/138): in game the frame read tan/gold, and each stacked card's bevel line
# striped a deck's side. card_glass_edge.gdshader paints the side wall from DARK and MID: keep them in step.
DARK = (18, 12, 7)              # the frame's darkest crease
MID = (40, 26, 16)              # the frame's flat face: dark brown
BRONZE = (92, 64, 38)           # the bevel lines


def _lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _ramp(lum):
    if lum <= 210:
        return _lerp(DARK, MID, max(0.0, (lum - 150) / 60.0))
    return _lerp(MID, BRONZE, min(1.0, (lum - 210) / 42.0))


def main():
    im = Image.open(SRC).convert("RGB").crop(CROP).resize(SIZE, Image.LANCZOS)
    w, h = im.size
    px = im.load()
    for y in (range(h) if RECOLOUR else ()):
        for x in range(w):
            edge = min(x, y, w - 1 - x, h - 1 - y)
            r, g, b = px[x, y]
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            sat = max(r, g, b) - min(r, g, b)
            if sat > 60:
                continue
            if edge < BAND:
                # The frame: fades in over 60..140 brightness so the antialiased inner edge blends.
                t = min(1.0, max(0.0, (lum - 60.0) / 80.0))
                if t > 0.0:
                    px[x, y] = _lerp((r, g, b), _ramp(lum), t)
                continue
            if CRYSTAL_BOX[0] <= x < CRYSTAL_BOX[2] and CRYSTAL_BOX[1] <= y < CRYSTAL_BOX[3]:
                continue
            if g - r > LINE_MAX_TEAL:
                continue
            # A silver line: onto the dark half of the bronze ramp, fading in over 40 brightness so its soft edge blends.
            t = min(1.0, max(0.0, (lum - LINE_MIN_LUM) / 40.0))
            if t > 0.0:
                px[x, y] = _lerp((r, g, b), _lerp(DARK, BRONZE, min(1.0, lum / 200.0)), t)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    im.save(OUT)
    print("wrote", os.path.normpath(OUT), im.size)


if __name__ == "__main__":
    main()
