"""Draws a contact sheet of every aircraft family in a livery, to look at the art without a phone.

    python tools/art/preview.py [style]       # style: cheatline belly tailOnly topStripe fullBody splitBody (default: cheatline)

The role-to-colour rule here must stay the same as the app's (BitAirlines/Art/Livery.swift).
"""
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import aircraft  # noqa: E402

PALETTE = [0x000000, 0x0B1020, 0x2B3350, 0x5A6482, 0x9AA7C2, 0xD7DEEE, 0xFFFFFF, 0x7A1F2B, 0xC0392B, 0xF0706A, 0xFF9F43, 0xFFC857, 0xFFE9A8,
           0x1E6B3A, 0x3FA34D, 0x8FD16A, 0x0F5C63, 0x2DB5A8, 0x8DE3D1, 0x12356B, 0x1F6FA0, 0x4FB6F0, 0xA8DCF8, 0x4B2A7B, 0x8A5CC9, 0xCDB4F0,
           0xA23B72, 0xF08CC0, 0x5B3A29, 0x9C6B3F, 0xD9B382, 0x151515]
WHITE, LIGHT, GREY, MID, DARK, INK, GLASS = 6, 5, 4, 3, 2, 1, 19


def role_colours(style, primary, secondary, accent):
    """Palette index for each role character under a livery style."""
    base = {'k': INK, 'g': GLASS, 'd': DARK, 'n': GREY, 'v': GREY, 'w': LIGHT}
    styles = {
        'cheatline': dict(f=WHITE, u=LIGHT, c=secondary, t=primary, m=primary, l=primary),
        'belly': dict(f=WHITE, u=primary, c=secondary, t=primary, m=accent, l=primary),
        'tailOnly': dict(f=WHITE, u=LIGHT, c=LIGHT, t=primary, m=secondary, l=primary),
        'topStripe': dict(f=primary, u=WHITE, c=secondary, t=primary, m=accent, l=primary),
        'fullBody': dict(f=primary, u=primary, c=secondary, t=secondary, m=accent, l=secondary),
        'splitBody': dict(f=primary, u=secondary, c=accent, t=primary, m=secondary, l=primary),
    }
    base.update(styles[style])
    return base


def render(sprite, style, primary, secondary, accent, scale):
    colours = role_colours(style, primary, secondary, accent)
    img = Image.new('RGBA', (sprite.w, sprite.h), (0, 0, 0, 0))
    px = img.load()
    for y in range(sprite.h):
        for x in range(sprite.w):
            ch = sprite.px[y][x]
            if ch != '.':
                rgb = PALETTE[colours[ch if ch != 'l' else 'l']]
                px[x, y] = ((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255)
    return img.resize((sprite.w * scale, sprite.h * scale), Image.NEAREST)


def main():
    style = sys.argv[1] if len(sys.argv) > 1 else 'cheatline'
    scale = 5
    names = list(aircraft.FAMILIES)
    sprites = {n: aircraft.build(n) for n in names}
    cols = 2
    cell_w = max(s.w for s in sprites.values()) * scale + 40
    cell_h = max(s.h for s in sprites.values()) * scale + 40
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGBA', (cell_w * cols, cell_h * rows), (11, 16, 32, 255))
    d = ImageDraw.Draw(sheet)
    liveries = [(8, 21, 11), (21, 6, 10), (10, 2, 6), (17, 6, 11), (20, 11, 6), (24, 12, 6), (14, 6, 11)]
    for i, name in enumerate(names):
        p, s, a = liveries[i % len(liveries)]
        img = render(sprites[name], style, p, s, a, scale)
        ox, oy = (i % cols) * cell_w + 20, (i // cols) * cell_h + 20
        sheet.alpha_composite(img, (ox, oy))
        d.text((ox, oy - 14), f'{name} {sprites[name].w}x{sprites[name].h}', fill=(154, 167, 194, 255))
    out = os.path.join(os.environ.get('TEMP', '.'), f'aircraft_{style}.png')
    sheet.save(out)
    print(out)


if __name__ == '__main__':
    main()
