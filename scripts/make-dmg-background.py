#!/usr/bin/env python3
"""Render Packaging/dmg-background.png and its @2x variant (requires Pillow).

Coordinates are in 1x points and must stay in sync with scripts/dmg-settings.py.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

WIDTH, HEIGHT = 660, 420
APP_CENTER = (170, 220)
APPLICATIONS_CENTER = (490, 220)
SUPERSAMPLE = 4

INK = (29, 29, 31)
MUTED = (110, 110, 115)
CORAL = (241, 115, 87)
TOP = (253, 252, 249)
BOTTOM = (243, 241, 235)

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
OUT_DIR = Path(__file__).resolve().parent.parent / "Packaging"


def font(size, weight):
    f = ImageFont.truetype(FONT_PATH, size * SUPERSAMPLE)
    f.set_variation_by_axes([100, min(max(size, 17), 96), 400, weight])
    return f


def s(value):
    return value * SUPERSAMPLE


def vertical_gradient(size, top, bottom):
    w, h = size
    column = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize((w, h))


def glow(canvas, center, radius, color, alpha):
    layer = Image.new("RGBA", canvas.size, color + (0,))
    mask = Image.new("L", canvas.size, 0)
    cx, cy = s(center[0]), s(center[1])
    r = s(radius)
    ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=alpha)
    mask = mask.filter(ImageFilter.GaussianBlur(s(radius) * 0.55))
    layer.putalpha(mask)
    canvas.alpha_composite(layer)


def bezier(p0, p1, p2, steps=160):
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t**2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t**2 * p2[1]
        yield x, y


def stroke(draw, points, width, color):
    points = [(s(x), s(y)) for x, y in points]
    w = s(width)
    draw.line(points, fill=color, width=round(w), joint="curve")
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=color)


def arrow(canvas):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    start = (APP_CENTER[0] + 92, APP_CENTER[1] - 4)
    end = (APPLICATIONS_CENTER[0] - 96, APPLICATIONS_CENTER[1] - 4)
    control = ((start[0] + end[0]) / 2, APP_CENTER[1] - 46)
    curve = list(bezier(start, control, end))

    dash, gap = 7, 6
    run, drawing, segment = 0.0, True, [curve[0]]
    for a, b in zip(curve, curve[1:]):
        run += math.dist(a, b)
        segment.append(b)
        if run >= (dash if drawing else gap):
            if drawing:
                stroke(draw, segment, 3, CORAL + (235,))
            run, drawing, segment = 0.0, not drawing, [b]
    if drawing and len(segment) > 1:
        stroke(draw, segment, 3, CORAL + (235,))

    tx, ty = end[0] - control[0], end[1] - control[1]
    angle = math.atan2(ty, tx)
    for side in (1, -1):
        a = angle + math.pi - side * math.radians(38)
        tip = (end[0] + 2.0 * math.cos(angle), end[1] + 2.0 * math.sin(angle))
        stroke(draw, [tip, (tip[0] + 13 * math.cos(a), tip[1] + 13 * math.sin(a))], 3, CORAL + (255,))

    canvas.alpha_composite(layer)


def centered_text(draw, y, text, f, color):
    left, top, right, bottom = draw.textbbox((0, 0), text, font=f)
    draw.text(((s(WIDTH) - (right - left)) / 2 - left, s(y)), text, font=f, fill=color)


def render():
    size = (s(WIDTH), s(HEIGHT))
    canvas = vertical_gradient(size, TOP, BOTTOM).convert("RGBA")
    glow(canvas, (WIDTH / 2, APP_CENTER[1] - 10), 230, (248, 196, 176), 120)
    glow(canvas, APP_CENTER, 95, (255, 255, 255), 255)
    glow(canvas, APPLICATIONS_CENTER, 95, (255, 255, 255), 255)
    arrow(canvas)

    draw = ImageDraw.Draw(canvas)
    centered_text(draw, 40, "Install Mochi", font(24, 680), INK + (255,))
    centered_text(draw, 76, "Drag Mochi into your Applications folder.", font(13, 420), MUTED + (255,))
    return canvas.convert("RGB")


def main():
    master = render()
    master.resize((WIDTH * 2, HEIGHT * 2), Image.LANCZOS).save(OUT_DIR / "dmg-background@2x.png", dpi=(144, 144))
    master.resize((WIDTH, HEIGHT), Image.LANCZOS).save(OUT_DIR / "dmg-background.png", dpi=(72, 72))


if __name__ == "__main__":
    main()
