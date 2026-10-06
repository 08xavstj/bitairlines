#!/usr/bin/env python3
"""Draws the Pixel Props app icon: a pixel-art high-wing turboprop over the sea and a small island at dusk, on a 64x64 grid
scaled up with no smoothing.

    python tools/make_icon.py            # writes BitAirlines/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png

Flat colours only (no gradients); the sky is stepped bands with a checkerboard dither between them, the 8-bit way.
"""
import json
import os
from PIL import Image, ImageColor, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT_DIR = os.path.join(ROOT, 'BitAirlines', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')

NAVY, SKY1, SKY2, SKY3, SKY4 = '#0B1020', '#16224A', '#25407F', '#3F7FC4', '#7FC0EC'
SUN, SUN2, SEA, SEA2, ISLE, ISLE2, SAND, CLOUD = '#FFD166', '#FFB347', '#12356B', '#1F6FA0', '#1E6B3A', '#3FA34D', '#D9B382', '#EEF2FA'
WHITE, SHADE, STRIPE, TAIL, METAL = '#EEF2FA', '#B9C6E4', '#1F6FA0', '#FF9F43', '#6F7FA6'

def rgb(hex_color):
    return ImageColor.getrgb(hex_color)


G = 64
img = Image.new('RGB', (G, G), SKY1)
px = img.load()
d = ImageDraw.Draw(img)

# sky: four flat bands, with a two-row checkerboard dither across each seam
bands = [(0, 16, SKY1), (16, 30, SKY2), (30, 42, SKY3), (42, 64, SKY4)]
for y0, y1, c in bands:
    d.rectangle([0, y0, G - 1, y1 - 1], fill=c)
for i in range(1, len(bands)):
    seam, above, below = bands[i][0], bands[i - 1][2], bands[i][2]
    for x in range(G):
        px[x, seam - 1] = rgb(below if x % 2 == 0 else above)
        px[x, seam] = rgb(above if x % 2 == 0 else below)

# sun on the horizon, half hidden behind the ridge
d.ellipse([43, 38, 57, 52], fill=SUN)
d.pieslice([43, 38, 57, 52], 0, 180, fill=SUN2)


# the sea: two flat bands with a dithered seam, and a light line where the sun meets the water
d.rectangle([0, 47, G - 1, G - 1], fill=SEA2)
d.rectangle([0, 55, G - 1, G - 1], fill=SEA)
for x in range(G):
    px[x, 54] = rgb(SEA if x % 2 == 0 else SEA2)
    px[x, 55] = rgb(SEA2 if x % 2 == 0 else SEA)
for x in range(44, 57, 2):
    px[x, 48] = rgb(SUN)
d.rectangle([47, 50, 53, 50], fill=SUN2)

# a small island on the left: a sand rim and two green hills
d.rectangle([2, 49, 27, 50], fill=SAND)
d.polygon([(4, 49), (10, 42), (15, 46), (19, 41), (26, 49)], fill=ISLE)
d.polygon([(10, 42), (12, 44), (15, 46), (13, 46)], fill=ISLE2)
d.polygon([(19, 41), (22, 45), (24, 47), (21, 47)], fill=ISLE2)

# pixel clouds
for cx, cy, w in ((50, 10, 9), (7, 13, 7), (28, 6, 6)):
    d.rectangle([cx - w // 2, cy, cx + w // 2, cy + 1], fill=CLOUD)
    d.rectangle([cx - w // 2 + 2, cy - 1, cx + w // 2 - 1, cy - 1], fill=CLOUD)


# the plane (facing right, high wing), tapered fuselage
d.polygon([(12, 30), (16, 27), (43, 27), (49, 29), (51, 31), (50, 33), (45, 35), (18, 35), (12, 32)], fill=WHITE)
d.line([(14, 34), (44, 34)], fill=SHADE)                                           # belly shade
d.line([(13, 31), (49, 31)], fill=STRIPE)                                          # cheat line
d.polygon([(13, 29), (10, 18), (15, 18), (21, 27)], fill=TAIL)                     # swept tail fin
d.rectangle([9, 28, 17, 29], fill=SHADE)                                           # stabilizer
d.rectangle([23, 21, 41, 23], fill=WHITE)                                          # high wing
d.rectangle([23, 23, 41, 23], fill=SHADE)
d.rectangle([29, 24, 30, 27], fill=METAL)                                          # wing struts
d.rectangle([36, 24, 37, 27], fill=METAL)
d.rectangle([37, 19, 43, 22], fill=STRIPE)                                         # engine on the wing
d.rectangle([44, 18, 44, 24], fill=METAL)                                          # propeller disc
for x in (38, 41, 44):                                                             # windows
    d.rectangle([x, 28, x + 1, 29], fill=NAVY)
d.rectangle([24, 28, 26, 30], fill=SHADE)                                          # door
d.rectangle([16, 36, 17, 37], fill=METAL)                                          # tail wheel
d.rectangle([34, 36, 35, 38], fill=METAL)                                          # main gear
d.rectangle([33, 38, 36, 39], fill=NAVY)
d.line([(12, 32), (18, 35)], fill=NAVY)                                            # tail outline

os.makedirs(OUT_DIR, exist_ok=True)
img.resize((1024, 1024), Image.NEAREST).save(os.path.join(OUT_DIR, 'icon-1024.png'))
with open(os.path.join(OUT_DIR, 'Contents.json'), 'w', encoding='utf-8') as f:
    json.dump({
        'images': [{'filename': 'icon-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
        'info': {'author': 'xcode', 'version': 1},
    }, f, indent=2)
    f.write('\n')
print('wrote', OUT_DIR)
