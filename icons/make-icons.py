#!/usr/bin/env python3
"""Generate Nog Schedules icons with PIL."""
from PIL import Image, ImageDraw

def rounded(bg_size, radius):
    m = Image.new("L", (bg_size, bg_size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, bg_size - 1, bg_size - 1], radius=radius, fill=255)
    return m

def gradient(size):
    top = (201, 106, 125)   # #c96a7d
    bot = (233, 160, 139)   # #e9a08b
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        px_r = int(top[0] + (bot[0] - top[0]) * t)
        px_g = int(top[1] + (bot[1] - top[1]) * t)
        px_b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(size):
            px[x, y] = (px_r, px_g, px_b)
    return img

def draw_calendar(d, s):
    # white calendar card
    m = s // 8
    card = [m, int(s * 0.26), s - m, s - m]
    d.rounded_rectangle(card, radius=s // 16, fill="white")
    # top strip
    d.rounded_rectangle([m, int(s * 0.26), s - m, int(s * 0.40)], radius=s // 16, fill=(181, 86, 106))
    d.rectangle([m, int(s * 0.33), s - m, int(s * 0.40)], fill=(181, 86, 106))
    # binder rings
    for cx in (int(s * 0.36), int(s * 0.64)):
        d.rounded_rectangle([cx - s // 48, int(s * 0.18), cx + s // 48, int(s * 0.30)],
                            radius=s // 96, fill="white")
    # grid dots
    for r in range(3):
        for c in range(4):
            x = m + int(s * 0.13) + c * int(s * 0.155)
            y = int(s * 0.50) + r * int(s * 0.13)
            col = (181, 86, 106) if (r == 1 and c == 1) else (230, 214, 208)
            d.ellipse([x, y, x + s // 28, y + s // 28], fill=col)

def make(path, size, maskable=False):
    canvas = size * 2 if maskable else size
    img = gradient(canvas)
    d = ImageDraw.Draw(img)
    if maskable:
        # keep glyph inside safe zone
        off = canvas // 5
        sub = Image.new("RGB", (canvas - 2 * off,) * 2, (0, 0, 0))
        sd = ImageDraw.Draw(sub)
        draw_calendar(sd, canvas - 2 * off)
        img.paste(sub, (off, off))
    else:
        draw_calendar(d, canvas)
        img.putalpha(rounded(canvas, canvas // 5))
    img = img.resize((size, size), Image.LANCZOS)
    if not maskable and img.mode == "RGBA":
        bg = Image.new("RGB", img.size, (250, 246, 241))
        bg.paste(img, mask=img.split()[3])
        img = bg
    img.save(path)
    print("wrote", path, img.size)

import os
os.makedirs("icons", exist_ok=True)
make("icons/icon-512.png", 512)
make("icons/icon-192.png", 192)
make("icons/icon-180.png", 180)
make("icons/icon-maskable.png", 512, maskable=True)
