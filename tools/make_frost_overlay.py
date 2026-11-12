"""Generate original Frostbite-style card overlay masks.

Run with Pillow installed:
    python tools/make_frost_overlay.py

The two outputs are white RGBA masks with alpha-only detail:
    assets/effects/frost/frost_outline.png
    assets/effects/frost/frost_cracks.png

They are sampled by shaders/frozen_overlay.gdshader and tinted at runtime.
The crack mask is deliberately dense and high-contrast: the real Frostbite
overlay is a heavy frozen-window frame, not a faint vignette.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "effects" / "frost"
SIZE = 1024
FINAL = 512
INSET = 18
RADIUS = 62
SEED = 0xF20F7


def _noise(size: int, cells: int, seed: int) -> Image.Image:
    """Deterministic low-frequency grayscale noise, resized to `size`."""
    rng = random.Random(seed)
    small = Image.new("L", (cells, cells))
    small.putdata([rng.randrange(256) for _ in range(cells * cells)])
    return small.resize((size, size), Image.Resampling.BICUBIC)


def _outer_mask() -> Image.Image:
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (INSET, INSET, SIZE - 1 - INSET, SIZE - 1 - INSET),
        radius=RADIUS,
        fill=255,
    )
    return mask.filter(ImageFilter.GaussianBlur(2.0))


def _irregular_inner_window(rng: random.Random) -> list[tuple[float, float]]:
    """A jagged clear window inside the card edge.

    Left and right are symmetric (the same inset on both sides); the band is
    heavier along the bottom than the top.
    """
    left = INSET + 190
    right = SIZE - INSET - 190
    top = INSET + 150
    bottom = SIZE - INSET - 205
    jitter = 30
    pts: list[tuple[float, float]] = []
    steps = 22
    for i in range(steps + 1):
        x = left + (right - left) * i / steps
        pts.append((x, top + rng.uniform(-jitter, jitter)))
    for i in range(steps + 1):
        y = top + (bottom - top) * i / steps
        pts.append((right + rng.uniform(-jitter, jitter), y))
    for i in range(steps + 1):
        x = right - (right - left) * i / steps
        pts.append((x, bottom + rng.uniform(-jitter, jitter)))
    for i in range(steps + 1):
        y = bottom - (bottom - top) * i / steps
        pts.append((left + rng.uniform(-jitter, jitter), y))
    return pts


def _crack_layer(rng: random.Random) -> Image.Image:
    """Long, high-contrast fissures growing inward from the edge."""
    layer = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(layer)

    def edge_point() -> tuple[float, float]:
        side = rng.randrange(4)
        t = rng.uniform(0.06, 0.94)
        lo = INSET + 8
        hi = SIZE - INSET - 8
        if side == 0:
            return lo + (hi - lo) * t, lo
        if side == 1:
            return hi, lo + (hi - lo) * t
        if side == 2:
            return lo + (hi - lo) * t, hi
        return lo, lo + (hi - lo) * t

    def branch(x: float, y: float, dx: float, dy: float, length: int, width: int, depth: int) -> None:
        if depth > 3 or width <= 0:
            return
        for i in range(length):
            px, py = x, y
            dx += rng.uniform(-0.20, 0.20)
            dy += rng.uniform(-0.20, 0.20)
            mag = math.hypot(dx, dy)
            if mag < 0.001:
                return
            dx /= mag
            dy /= mag
            x += dx * rng.uniform(6.0, 14.0)
            y += dy * rng.uniform(6.0, 14.0)
            if x <= INSET or x >= SIZE - INSET or y <= INSET or y >= SIZE - INSET:
                return
            cx, cy = SIZE * 0.5, SIZE * 0.5
            if math.hypot(x - cx, y - cy) < SIZE * 0.235:
                return
            alpha = max(90, int(255 * (1.0 - i / max(length, 1)) ** 0.45))
            draw.line((px, py, x, y), fill=alpha, width=max(2, width))
            r = max(1, width // 2)
            draw.ellipse((x - r, y - r, x + r, y + r), fill=alpha)
            if rng.random() < 0.20:
                branch(
                    x + rng.uniform(-4, 4),
                    y + rng.uniform(-4, 4),
                    dx + rng.uniform(-0.9, 0.9),
                    dy + rng.uniform(-0.9, 0.9),
                    max(6, int(length * rng.uniform(0.25, 0.55))),
                    max(1, width - 1),
                    depth + 1,
                )

    # Main fissures: some run deep, some stay near the rim.
    for _ in range(95):
        x, y = edge_point()
        cx, cy = SIZE * 0.5, SIZE * 0.5
        tx, ty = cx - x, cy - y
        mag = math.hypot(tx, ty)
        tx /= mag
        ty /= mag
        branch(
            x,
            y,
            tx + rng.uniform(-0.85, 0.85),
            ty + rng.uniform(-0.85, 0.85),
            rng.randint(16, 55),
            rng.randint(2, 7),
            0,
        )

    # A second pass of short chips along the rim gives the broken, granular edge.
    for _ in range(90):
        x, y = edge_point()
        branch(x, y, rng.uniform(-1, 1), rng.uniform(-1, 1),
               rng.randint(4, 13), rng.randint(2, 5), 3)
    return layer


def frost_outline() -> Image.Image:
    size = SIZE
    border = 24
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (INSET, INSET, size - 1 - INSET, size - 1 - INSET),
        radius=RADIUS,
        outline=190,
        width=border,
    )
    noise = _noise(size, 32, SEED + 1)
    mask = ImageChops.multiply(mask, noise.point(lambda v: 185 + v // 4))
    mask = mask.filter(ImageFilter.GaussianBlur(11))

    wisps = Image.new("L", (size, size), 0)
    wd = ImageDraw.Draw(wisps)
    rng = random.Random(SEED + 2)
    for cx, cy in [(INSET, INSET), (size - INSET, INSET),
                   (INSET, size - INSET), (size - INSET, size - INSET)]:
        for _ in range(16):
            x = cx + rng.uniform(-110, 110)
            y = cy + rng.uniform(-110, 110)
            r = rng.uniform(20, 64)
            wd.ellipse((x - r, y - r * 1.5, x + r, y + r * 1.5), fill=rng.randint(20, 62))
    wisps = wisps.filter(ImageFilter.GaussianBlur(15))
    return ImageChops.lighter(mask, wisps)


def frost_cracks() -> Image.Image:
    rng = random.Random(SEED + 10)
    outer = _outer_mask()
    inner_pts = _irregular_inner_window(rng)

    # Broad frost sheet = card minus clear centre.
    band = outer.copy()
    ImageDraw.Draw(band).polygon(inner_pts, fill=0)
    band = band.filter(ImageFilter.GaussianBlur(7))

    # Bays and inlets where the clear window bites into the frost.
    bays = Image.new("L", (SIZE, SIZE), 0)
    bd = ImageDraw.Draw(bays)
    for _ in range(130):
        p = inner_pts[rng.randrange(len(inner_pts))]
        x = p[0] + rng.uniform(-80, 80)
        y = p[1] + rng.uniform(-80, 80)
        r = rng.uniform(8, 48)
        bd.ellipse((x - r, y - r, x + r, y + r), fill=rng.randint(80, 255))
    bays = bays.filter(ImageFilter.GaussianBlur(16))
    band = ImageChops.subtract(band, bays)

    # Rime clusters: dense little ice grains, strongest near the outside.
    rime = Image.new("L", (SIZE, SIZE), 0)
    rd = ImageDraw.Draw(rime)
    for _ in range(2600):
        x = rng.uniform(INSET, SIZE - INSET)
        y = rng.uniform(INSET, SIZE - INSET)
        edge_dist = min(x - INSET, SIZE - INSET - x, y - INSET, SIZE - INSET - y)
        if edge_dist > 260:
            continue
        if rng.random() > (1.0 - edge_dist / 290.0):
            continue
        r = rng.uniform(1.0, 7.0)
        a = rng.randint(50, 210)
        rd.ellipse((x - r, y - r * rng.uniform(0.7, 1.4),
                    x + r, y + r * rng.uniform(0.7, 1.4)), fill=a)
    rime = rime.filter(ImageFilter.GaussianBlur(1.2))
    band = ImageChops.lighter(band, ImageChops.multiply(rime, outer))

    # Long structural cracks sit on top of the granular band.
    band = ImageChops.lighter(band, _crack_layer(rng))

    # Push the low end to black and the high end to near-opaque white, so the
    # result is a fractured frame rather than a grey haze.
    band = band.point(lambda v: 0 if v < 38 else min(255, int((v - 38) * 1.55)))
    band = band.filter(ImageFilter.GaussianBlur(0.8))

    # The very centre must stay clear for the illustration.
    clear = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(clear).polygon(inner_pts, fill=255)
    clear = clear.filter(ImageFilter.GaussianBlur(22))
    band = ImageChops.multiply(band, ImageChops.invert(clear))
    return band


def save_mask(mask: Image.Image, name: str) -> None:
    mask = mask.resize((FINAL, FINAL), Image.Resampling.LANCZOS)
    rgba = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    rgba.putalpha(mask)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / name
    rgba.save(path)
    print("wrote", path)


def main() -> None:
    save_mask(frost_outline(), "frost_outline.png")
    save_mask(frost_cracks(), "frost_cracks.png")


if __name__ == "__main__":
    main()
