#!/usr/bin/env python3
"""Draws the starter emblems for the logo editor on a 24 x 24 grid and writes BitAirlines/Art/LogoTemplates.swift.

    python tools/art/logo_templates.py            # writes the Swift file
    python tools/art/logo_templates.py --png out  # also saves a preview sheet (needs Pillow)

Letters: a = the airline's main colour, b = stripe colour, c = detail colour, w = white, . = clear.
Each emblem is drawn from simple shapes (circles, polygons, lines) so it stays clean and symmetric.
"""
import math
import os
import sys

N = 24
C = (N - 1) / 2  # centre of the grid


def blank():
    return [['.'] * N for _ in range(N)]


def inside_poly(x, y, pts):
    """Even-odd test for the centre of cell (x, y)."""
    px, py = x + 0.5, y + 0.5
    hit = False
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[i - 1]
        if (y1 > py) != (y2 > py) and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def poly(g, pts, ch):
    for y in range(N):
        for x in range(N):
            if inside_poly(x, y, pts):
                g[y][x] = ch


def disc(g, cx, cy, r, ch, r_in=0.0):
    for y in range(N):
        for x in range(N):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if r_in <= d <= r:
                g[y][x] = ch


def rect(g, x0, y0, x1, y1, ch):
    for y in range(max(0, y0), min(N, y1)):
        for x in range(max(0, x0), min(N, x1)):
            g[y][x] = ch


def star(cx, cy, r_out, r_in, points, turn=-90):
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(turn + i * 180 / points)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def wing():
    g = blank()
    poly(g, [(1, 17), (23, 3), (23, 7), (8, 17)], 'a')
    poly(g, [(3, 20), (21, 11), (21, 14), (10, 20)], 'b')
    return g


def five_star():
    g = blank()
    disc(g, 12, 12.5, 12, 'a', 10.5)
    poly(g, star(12, 12.8, 9.5, 3.9, 5), 'c')
    return g


def peak():
    g = blank()
    disc(g, 17, 6, 3.6, 'c')
    poly(g, [(0, 20), (8, 7), (13, 15), (16, 11), (24, 20)], 'a')
    poly(g, [(6.2, 10), (8, 7), (9.8, 10), (8, 9)], 'w')
    rect(g, 0, 20, 24, 22, 'b')
    return g


def sun():
    g = blank()
    for i in range(12):
        a = math.radians(i * 30)
        ca, sa = math.cos(a), math.sin(a)
        poly(g, [(12 + 5 * ca - 1.8 * sa, 12 + 5 * sa + 1.8 * ca), (12 + 11.8 * ca, 12 + 11.8 * sa), (12 + 5 * ca + 1.8 * sa, 12 + 5 * sa - 1.8 * ca)], 'a')
    disc(g, 12, 12, 6.2, 'b')
    disc(g, 12, 12, 4.2, 'c')
    return g


def target():
    g = blank()
    disc(g, 12, 12, 11.5, 'a', 8.5)
    disc(g, 12, 12, 6.5, 'b', 4)
    disc(g, 12, 12, 2.2, 'c')
    return g


def chevron():
    g = blank()
    poly(g, [(12, 2), (23, 13), (19, 13), (12, 6.5), (5, 13), (1, 13)], 'a')
    poly(g, [(12, 10), (23, 21), (19, 21), (12, 14.5), (5, 21), (1, 21)], 'b')
    return g


def propeller():
    g = blank()
    for turn in (-90, 30, 150):
        a = math.radians(turn)
        ca, sa = math.cos(a), math.sin(a)
        # a blade: narrow at the hub, wide near the tip, round end
        pts = [(12 - 2.0 * sa, 12 + 2.0 * ca), (12 + 8 * ca - 3.6 * sa, 12 + 8 * sa + 3.6 * ca),
               (12 + 11.5 * ca - 1.5 * sa, 12 + 11.5 * sa + 1.5 * ca), (12 + 11.5 * ca + 1.5 * sa, 12 + 11.5 * sa - 1.5 * ca),
               (12 + 8 * ca + 3.6 * sa, 12 + 8 * sa - 3.6 * ca), (12 + 2.0 * sa, 12 - 2.0 * ca)]
        poly(g, pts, 'a')
    disc(g, 12, 12, 3.4, 'b')
    disc(g, 12, 12, 1.4, 'c')
    return g


def compass():
    g = blank()
    disc(g, 12, 12, 11.5, 'b', 10)
    poly(g, star(12, 12, 10, 3.6, 4, turn=-90), 'a')
    poly(g, star(12, 12, 6.5, 2.6, 4, turn=-45), 'c')
    return g


def aurora():
    g = blank()
    for row, ch, phase in ((5, 'a', 0.0), (11, 'b', 0.9), (17, 'c', 1.8)):
        for x in range(N):
            y = row + 2.4 * math.sin(x / 3.6 + phase)
            for t in range(-2, 2):
                yy = int(round(y + t))
                if 0 <= yy < N:
                    g[yy][x] = ch
    return g


def plane():
    """An aircraft seen from above, nose up."""
    g = blank()
    disc(g, 12, 12, 11.5, 'b')
    poly(g, [(10.5, 4), (12, 1.5), (13.5, 4), (13.5, 19), (12, 21), (10.5, 19)], 'w')   # fuselage
    poly(g, [(2, 13), (10.5, 8), (13.5, 8), (22, 13), (22, 15), (13.5, 12.5), (10.5, 12.5), (2, 15)], 'w')  # wings
    poly(g, [(7.5, 20), (10.5, 17), (13.5, 17), (16.5, 20), (16.5, 21), (7.5, 21)], 'w')  # tailplane
    return g


def globe():
    g = blank()
    disc(g, 12, 12, 11.5, 'a')
    for y in range(N):
        for x in range(N):
            if g[y][x] != 'a':
                continue
            dx, dy = x + 0.5 - 12, y + 0.5 - 12
            if abs(dy) < 0.8 or abs(dy - 6) < 0.6 or abs(dy + 6) < 0.6:
                g[y][x] = 'w'
            r = math.sqrt(max(0.0, 11.5 ** 2 - dy ** 2))
            if abs(dx) < 0.8 or (r > 0 and abs(abs(dx) - r * 0.55) < 0.7):
                g[y][x] = 'w'
    return g


def shield():
    g = blank()
    outline = [(3, 2), (21, 2), (21, 12), (12, 23), (3, 12)]
    poly(g, outline, 'a')
    poly(g, [(5.5, 4.5), (18.5, 4.5), (18.5, 11.3), (12, 19.5), (5.5, 11.3)], 'b')
    poly(g, star(12, 10.5, 5.5, 2.3, 5), 'c')
    return g


TEMPLATES = [
    ('wing', 'Wing', wing), ('propeller', 'Propeller', propeller), ('plane', 'Plane', plane), ('peak', 'Peak', peak),
    ('sun', 'Sun', sun), ('aurora', 'Aurora', aurora), ('compass', 'Compass', compass), ('star', 'Star', five_star),
    ('chevron', 'Chevron', chevron), ('target', 'Target', target), ('globe', 'Globe', globe), ('shield', 'Shield', shield),
]

HEADER = '''// GENERATED by tools/art/logo_templates.py. Do not edit by hand; change the script and run it again.
import CoreCatalog
import CoreWorld

/// Starter emblems for the logo editor. Letters stand for the airline's colours: a main, b stripe, c detail, w white.
struct LogoTemplate: Identifiable {
    let id: String
    let name: String
    let rows: [String]

    func logo(for b: Branding) -> [UInt8] {
        let map: [Character: Int] = ["a": b.primary, "b": b.secondary, "c": b.accent, "w": PixelPalette.white]
        var out = Branding.blankLogo()
        for (y, row) in rows.prefix(Branding.logoSize).enumerated() {
            for (x, ch) in row.prefix(Branding.logoSize).enumerated() {
                if let colour = map[ch] { out[y * Branding.logoSize + x] = UInt8(colour) }
            }
        }
        return out
    }
}

enum LogoTemplates {
    static let all: [LogoTemplate] = [
'''


def swift():
    out = [HEADER]
    for key, name, draw in TEMPLATES:
        rows = [''.join(r) for r in draw()]
        out.append(f'        LogoTemplate(id: "{key}", name: "{name}", rows: [\n')
        for i in range(0, N, 4):
            out.append('            ' + ', '.join(f'"{r}"' for r in rows[i:i + 4]) + ',\n')
        out.append('        ]),\n')
    out.append('    ]\n}\n')
    return ''.join(out)


def png(path):
    from PIL import Image
    colours = {'a': (230, 120, 40), 'b': (60, 150, 230), 'c': (250, 220, 90), 'w': (245, 245, 245), '.': (30, 34, 52)}
    s = 8
    sheet = Image.new('RGB', (len(TEMPLATES) * (N * s + 8), N * s), (10, 10, 20))
    for i, (_, _, draw) in enumerate(TEMPLATES):
        for y, row in enumerate(draw()):
            for x, ch in enumerate(row):
                for dy in range(s):
                    for dx in range(s):
                        sheet.putpixel((i * (N * s + 8) + x * s + dx, y * s + dy), colours[ch])
    sheet.save(path)


if __name__ == '__main__':
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    with open(os.path.join(root, 'BitAirlines', 'Art', 'LogoTemplates.swift'), 'w', newline='\n') as f:
        f.write(swift())
    if len(sys.argv) > 2 and sys.argv[1] == '--png':
        png(sys.argv[2])
