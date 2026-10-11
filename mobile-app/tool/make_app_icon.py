"""Generates the WSF app icon (the guardian orb) for iOS and Android.

Run from mobile-app/:  python3 tool/make_app_icon.py

Draws the same ordered-dither sphere as lib/ui/guardian_orb.dart, with a
coarser dot grid so the texture still reads at home-screen size. Needs
Pillow and numpy.
"""

import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

INK = (0x0B, 0x0C, 0x0A)
VOLT = (0xD4, 0xFF, 0x3A)
BONE = (0xF3, 0xF1, 0xE7)

BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

# Dots across the orb. The app uses 34; an icon needs fewer, larger dots.
CELLS = 20
SS = 4  # supersampling factor


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def glow_layer(size, radius, strength):
    """Volt halo behind the orb, as an RGBA image."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.hypot(xx - size / 2, yy - size / 2) / radius
    alpha = np.clip(1 - (d - 0.55) / 0.45, 0, 1) ** 2 * strength
    out = np.zeros((size, size, 4), dtype=np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = VOLT
    out[..., 3] = (alpha * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def draw_orb(size, orb_fraction, background):
    """Renders the orb centred on a square canvas.

    orb_fraction: orb diameter as a fraction of the canvas.
    background: an RGB tuple for an opaque icon, or None for transparent.
    """
    w = size * SS
    c = w / 2
    radius = w * orb_fraction / 2

    img = Image.new("RGBA", (w, w), (*background, 255) if background else (0, 0, 0, 0))
    glow = glow_layer(size, size * orb_fraction * 0.80, 0.34).resize((w, w), Image.BICUBIC)
    img.alpha_composite(glow)

    draw = ImageDraw.Draw(img)
    draw.ellipse([c - radius, c - radius, c + radius, c + radius], fill=(*INK, 255))

    # Eyes, in units of the orb radius.
    # Slightly larger than in the app so they survive at 58 px.
    eye_w, eye_h = 0.20, 0.40
    eyes = [(-0.235, -0.04), (0.235, -0.04)]
    socket_x, socket_y = eye_w / 2 + 0.08, eye_h / 2 + 0.08

    # Light from the upper left, as in the app.
    lx, ly, lz = -0.52, -0.60, 0.62
    n = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / n, ly / n, lz / n

    cell = 2 * radius / CELLS
    half = CELLS // 2 + 1
    sizes = {1: 0.17, 2: 0.25, 3: 0.33}
    alphas = {1: 0.50, 2: 0.80, 3: 1.0}
    for j in range(-half, half + 1):
        for i in range(-half, half + 1):
            px, py = (i + 0.5) * cell, (j + 0.5) * cell
            nx, ny = px / radius, py / radius
            d = math.hypot(nx, ny)
            if d > 0.97:
                continue
            nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
            lum = 0.09 + 0.98 * max(0.0, nx * lx + ny * ly + nz * lz)
            rim = 1 - nz
            lum += 0.42 * rim * rim * math.sqrt(rim)

            q = min(
                math.hypot((nx - ex) / socket_x, (ny - ey) / socket_y) for ex, ey in eyes
            )
            lum *= smooth(1.0, 1.75, q)

            threshold = (BAYER4[((j + half) & 3) * 4 + ((i + half) & 3)] + 0.5) / 16
            level = int(min(1.0, max(0.0, lum)) * 3 + threshold)
            if level <= 0:
                continue
            r = cell * sizes[level]
            draw.ellipse(
                [c + px - r, c + py - r, c + px + r, c + py + r],
                fill=(*mix(INK, VOLT, alphas[level]), 255),
            )

    for ex, ey in eyes:
        ew, eh = eye_w * radius, eye_h * radius
        x, y = c + ex * radius, c + ey * radius
        draw.rounded_rectangle(
            [x - ew / 2, y - eh / 2, x + ew / 2, y + eh / 2], radius=ew / 2, fill=(*BONE, 255)
        )

    return img.resize((size, size), Image.LANCZOS)


def rounded(img, fraction):
    """Clips a square image to a rounded square (for legacy Android icons)."""
    size = img.size[0] * SS
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size, size], radius=size * fraction, fill=255)
    out = img.copy()
    out.putalpha(mask.resize(img.size, Image.LANCZOS))
    return out


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # ── iOS: opaque, square; the system applies the corner mask ───────────────
    master = draw_orb(1024, 0.70, INK).convert("RGB")
    icon_dir = os.path.join(root, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    with open(os.path.join(icon_dir, "Contents.json")) as f:
        contents = json.load(f)
    for entry in contents["images"]:
        points = float(entry["size"].split("x")[0])
        pixels = round(points * int(entry["scale"].rstrip("x")))
        master.resize((pixels, pixels), Image.LANCZOS).save(
            os.path.join(icon_dir, entry["filename"]), "PNG"
        )

    # ── Android ──────────────────────────────────────────────────────────────
    res = os.path.join(root, "android/app/src/main/res")
    legacy = rounded(draw_orb(432, 0.72, INK), 0.22)
    # Adaptive foreground: the orb must sit inside the central 66/108 safe zone.
    foreground = draw_orb(432, 0.52, None)
    densities = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
    for name, scale in densities.items():
        folder = os.path.join(res, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        s = round(48 * scale)
        legacy.resize((s, s), Image.LANCZOS).save(os.path.join(folder, "ic_launcher.png"), "PNG")
        s = round(108 * scale)
        foreground.resize((s, s), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher_foreground.png"), "PNG"
        )

    adaptive = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(adaptive, exist_ok=True)
    with open(os.path.join(adaptive, "ic_launcher.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            "</adaptive-icon>\n"
        )
    with open(os.path.join(res, "values/ic_launcher_background.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            '    <color name="ic_launcher_background">#0B0C0A</color>\n'
            "</resources>\n"
        )

    print("icons written:", len(contents["images"]), "iOS,", len(densities) * 2, "Android")


if __name__ == "__main__":
    main()
