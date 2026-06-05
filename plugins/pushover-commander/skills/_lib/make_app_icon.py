#!/usr/bin/env python3
"""make_app_icon.py — generate an aesthetically-pleasing square PNG app icon for Pushover.

Gradient rounded-square background (category color) + bold monogram + small role label.
Monogram-based (offline, reliable) — no color-emoji font dependency.

Usage:
  make_app_icon.py --out icon.png --mono ODB --label runtime --color "#3b82f6" [--size 256]
"""
import argparse

from PIL import Image, ImageDraw, ImageFont


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Users/terryli/Library/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def darken(rgb: tuple[int, int, int], f: float) -> tuple[int, int, int]:
    return (max(0, int(rgb[0] * f)), max(0, int(rgb[1] * f)), max(0, int(rgb[2] * f)))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--mono", required=True, help="2-4 char monogram")
    ap.add_argument("--label", default="", help="small role label")
    ap.add_argument("--color", default="#3b82f6")
    ap.add_argument("--size", type=int, default=256)
    a = ap.parse_args()

    S = a.size
    top = hex_rgb(a.color)
    bot = darken(top, 0.55)
    # vertical gradient
    base = Image.new("RGB", (S, S), top)
    for y in range(S):
        t = y / (S - 1)
        row = tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3))
        for x in range(S):
            base.putpixel((x, y), row)
    # rounded mask
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=255)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.paste(base, (0, 0), mask)

    d = ImageDraw.Draw(img)
    mono = a.mono[:4].upper()
    mf = load_font(int(S * (0.5 if len(mono) <= 3 else 0.38)))
    mb = d.textbbox((0, 0), mono, font=mf)
    mw, mh = mb[2] - mb[0], mb[3] - mb[1]
    my = (S - mh) // 2 - int(S * 0.06) - mb[1]
    # subtle shadow + white monogram
    d.text(((S - mw) // 2 + 2, my + 2), mono, font=mf, fill=(0, 0, 0, 90))
    d.text(((S - mw) // 2, my), mono, font=mf, fill=(255, 255, 255, 255))
    if a.label:
        lf = load_font(int(S * 0.13))
        lab = a.label[:14]
        lb = d.textbbox((0, 0), lab, font=lf)
        lw = lb[2] - lb[0]
        d.text(((S - lw) // 2 - lb[0], int(S * 0.74)), lab, font=lf, fill=(255, 255, 255, 220))
    img.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
