#!/usr/bin/env python3
"""Generate Gnog Schedules icons with PIL: a wizard hat on a twilight sky."""
from PIL import Image, ImageDraw

GOLD = (255, 215, 106)
HAT = (61, 44, 116)
HAT_HI = (84, 64, 143)
BRIM = (46, 35, 88)

def rounded(bg_size, radius):
    m = Image.new("L", (bg_size, bg_size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, bg_size - 1, bg_size - 1], radius=radius, fill=255)
    return m

TOP = (37, 43, 99)     # deep indigo
BOT = (122, 75, 179)   # violet

def sky_at(t):
    return tuple(int(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3))

def gradient(size):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        c = sky_at(y / (size - 1))
        for x in range(size):
            px[x, y] = c
    return img

def sparkle(d, cx, cy, r):
    k = 0.28
    d.polygon([(cx, cy - r), (cx + r * k, cy - r * k), (cx + r, cy),
               (cx + r * k, cy + r * k), (cx, cy + r),
               (cx - r * k, cy + r * k), (cx - r, cy),
               (cx - r * k, cy - r * k)], fill=GOLD)

def draw_hat(d, s):
    u = s / 100.0
    # stars
    for cx, cy, r in [(20, 22, 4.2), (81, 28, 3.2), (79, 79, 3.8),
                      (15, 79, 2.8), (88, 55, 2.4), (62, 84, 2.2)]:
        sparkle(d, cx * u, cy * u, r * u)
    for cx, cy in [(34, 12), (48, 30), (70, 44), (28, 48), (90, 70), (42, 90)]:
        d.ellipse([cx * u - u, cy * u - u, cx * u + u, cy * u + u], fill=(255, 255, 255))
    # brim (behind cone)
    d.ellipse([16 * u, 56 * u, 84 * u, 72 * u], fill=BRIM,
              outline=GOLD, width=max(2, int(s / 160)))
    # cone
    d.polygon([(60 * u, 15 * u), (34 * u, 62 * u), (70 * u, 60 * u)], fill=HAT)
    # bent tip
    d.polygon([(60 * u, 15 * u), (71 * u, 9 * u), (68 * u, 20 * u)], fill=HAT)
    # highlight along left edge
    d.polygon([(60 * u, 15 * u), (34 * u, 62 * u),
               (42 * u, 60 * u), (58 * u, 22 * u)], fill=HAT_HI)
    # gold band
    d.polygon([(38 * u, 51 * u), (66 * u, 49 * u),
               (68 * u, 56 * u), (36 * u, 58 * u)], fill=GOLD)

def make(path, size, maskable=False):
    canvas = size * 2 if maskable else size
    img = gradient(canvas)
    d = ImageDraw.Draw(img)
    if maskable:
        # keep glyph inside safe zone
        off = canvas // 5
        sub = Image.new("RGB", (canvas - 2 * off,) * 2, (0, 0, 0))
        sd = ImageDraw.Draw(sub)
        # repaint a matching gradient patch behind the glyph
        for y in range(sub.size[1]):
            sd.line([(0, y), (sub.size[0], y)], fill=sky_at((y + off) / (canvas - 1)))
        draw_hat(sd, canvas - 2 * off)
        img.paste(sub, (off, off))
    else:
        draw_hat(d, canvas)
        img.putalpha(rounded(canvas, canvas // 5))
    img = img.resize((size, size), Image.LANCZOS)
    if not maskable and img.mode == "RGBA":
        bg = Image.new("RGB", img.size, (37, 43, 99))
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
