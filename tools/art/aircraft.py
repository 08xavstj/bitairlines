"""Procedural side-view aircraft sprites (nose to the right). Each builder returns a Canvas of role characters; see canvas.py for the roles.

The livery colours are applied later (by the app, or by preview.py), so one drawing serves every airline.
"""
from canvas import Canvas


def _logo_rect(c):
    """Marks the largest roughly square block of fin cells as logo cells ('l')."""
    best = None
    for y0 in range(c.h):
        for x0 in range(c.w):
            if c.get(x0, y0) not in 'tm':
                continue
            for size in range(2, 14):
                if all(c.get(x, y) in 'tm' for y in range(y0, y0 + size) for x in range(x0, x0 + size)):
                    if best is None or size > best[0]:
                        best = (size, x0, y0)
                else:
                    break
    if best and best[0] >= 3:
        size, x0, y0 = best
        c.rect(x0, y0, x0 + size - 1, y0 + size - 1, 'l')


def jet(L, H, nose, tail_len, rise, fin_h, fin_len, wing_x, wing_len, wing_drop, engines='wing2', t_tail=False, hump=0, gear=2):
    """An airliner. engines: 'wing2', 'wing4', 'rear2'. hump: extra height of a second deck over the front half (A380)."""
    W, Hc = L + 10, fin_h + H + hump + wing_drop + 12
    c = Canvas(W, Hc)
    x0, x1 = 4, 4 + L - 1
    y_top = fin_h + hump + 4
    y_bot = y_top + H - 1
    belly = y_top + int(H * 0.62)
    cheat = y_top + int(H * 0.45)

    for x in range(x0, x1 + 1):
        t = x - x0
        top, bot = y_top, y_bot
        if t < tail_len:
            bot = y_bot - round(rise * (tail_len - t) / tail_len)
        n = x - (x1 - nose)
        if n > 0:
            top = y_top + round(n * (H * 0.38) / nose)
            bot = y_bot - round(n * (H * 0.12) / nose)
        if hump and x0 + tail_len + 6 < x < x1 - nose - 2:
            top = y_top - hump
            if x > x1 - nose - 8:
                top = y_top - hump + (x - (x1 - nose - 8)) // 2
        for y in range(top, bot + 1):
            c.set(x, y, 'u' if y >= belly else 'f')
    for x in range(x0 + tail_len // 2, x1 - nose):
        if c.get(x, cheat) in 'fu':
            c.set(x, cheat, 'c')
    wy = y_top + max(1, int(H * 0.22))
    for x in range(x0 + tail_len + 3, x1 - nose - 3, 2):
        if c.get(x, wy) in 'fu':
            c.set(x, wy, 'g')
    c.hline(x1 - nose - 1, x1 - nose + 2, y_top + 1 + (0 if not hump else 0), 'g')
    c.hline(x1 - nose, x1 - nose + 3, y_top + 2, 'g')

    # fin
    base_front, base_back = x0 + fin_len + 2, x0 + 1
    tip_front = base_back + max(4, fin_len // 2)
    c.poly([(base_front, y_top), (tip_front, y_top - fin_h), (base_back - 1, y_top - fin_h), (base_back, y_top)], 't')
    c.rect(base_back - 1, y_top - fin_h, tip_front - 1, y_top - fin_h + 1, 'm')
    if t_tail:
        c.rect(base_back - 3, y_top - fin_h - 1, base_back + 6, y_top - fin_h - 1, 'w')
    else:
        c.rect(x0 - 3, y_top, x0 + 6, y_top + 1, 'w')
    _logo_rect(c)

    # wing (a slanted strip toward the viewer) and engines
    wy0 = y_top + int(H * 0.55)
    c.poly([(wing_x + 2, wy0), (wing_x + wing_len, wy0), (wing_x + wing_len - 3, y_bot + wing_drop), (wing_x - 3, y_bot + wing_drop)], 'w')
    c.hline(wing_x - 3, wing_x + wing_len - 3, y_bot + wing_drop, 'v')
    if engines.startswith('wing'):
        spots = [wing_x + wing_len // 2 - 4] if engines == 'wing2' else [wing_x + wing_len // 2 - 10, wing_x + wing_len // 2 + 3]
        for ex in spots:
            c.rect(ex, y_bot + 1, ex + 6, y_bot + 3, 'n')
            c.rect(ex + 6, y_bot + 1, ex + 6, y_bot + 3, 'd')
    else:
        ex = x0 + tail_len - 4
        c.rect(ex, y_top, ex + 8, y_top + 2, 'n')
        c.rect(ex + 8, y_top, ex + 8, y_top + 2, 'd')
    # gear
    for gx in ([x1 - nose - 5, wing_x + wing_len // 2 - 3] if gear == 2 else [x1 - nose - 5, wing_x + wing_len // 2 - 6, wing_x + wing_len // 2]):
        c.rect(gx, y_bot + 1, gx + 1, y_bot + wing_drop + 2, 'd')
    return c


def prop(L, H, wing='high', engines=1, floats=False, taildragger=False, fin_h=6, wing_len=None, big_cowl=True, strut=True, gear_h=3):
    """A propeller aircraft: utility single, twin turboprop, commuter, taildragger. engines is 1 or 2."""
    wing_len = wing_len or max(8, L // 2)
    W, Hc = L + 12, fin_h + H + gear_h + 16
    c = Canvas(W, Hc)
    x0, x1 = 6, 6 + L - 1
    y_top = fin_h + 6
    y_bot = y_top + H - 1
    belly = y_top + int(H * 0.6)
    cow = 4 if big_cowl else 3

    for x in range(x0, x1 + 1):
        t = x - x0
        top, bot = y_top, y_bot
        if t < L // 3:
            bot = y_bot - round((L // 3 - t) * (H * 0.55) / (L // 3))
        if x > x1 - cow:
            top += 1
            bot -= 1
        for y in range(top, bot + 1):
            c.set(x, y, 'u' if y >= belly else 'f')
    cheat = y_top + int(H * 0.5)
    for x in range(x0 + 5, x1 - cow):
        if c.get(x, cheat) in 'fu':
            c.set(x, cheat, 'c')
    wy = y_top + 1
    for x in range(x0 + L // 3 + 1, x1 - cow - 3, 3):
        c.rect(x, wy, x + 1, wy + max(0, min(1, H // 4)), 'g')
    c.rect(x1 - cow - 3, y_top, x1 - cow, y_top + 1, 'g')
    if engines == 1:
        c.rect(x1 - cow + 1, y_top + 1, x1, y_bot - 1, 'n')
        c.rect(x1 + 1, y_top - 2, x1 + 1, y_bot + 2, 'd')
    # fin and stabiliser
    c.poly([(x0 + 6, y_top), (x0 + 3, y_top - fin_h), (x0 - 1, y_top - fin_h), (x0 + 1, y_top)], 't')
    c.rect(x0 - 1, y_top - fin_h, x0 + 3, y_top - fin_h + 1, 'm')
    c.rect(x0 - 3, y_top + 1, x0 + 5, y_top + 1, 'w')
    _logo_rect(c)
    # wing
    wx = x0 + L // 3 + 2
    if wing == 'high':
        c.rect(wx, y_top - 3, wx + wing_len, y_top - 2, 'w')
        c.hline(wx, wx + wing_len, y_top - 1, 'v')
        if strut and engines == 1:
            c.poly([(wx + 3, y_top), (wx + 5, y_top), (wx + 9, y_top - 1), (wx + 7, y_top - 1)], 'v')
    else:
        c.poly([(wx, y_top + H // 2), (wx + wing_len, y_top + H // 2), (wx + wing_len - 4, y_bot + 3), (wx - 6, y_bot + 3)], 'w')
    if engines == 2:
        ex = wx + wing_len - 3
        ey = y_top - 3 if wing == 'high' else y_bot + 1
        c.rect(ex, ey, ex + 6, ey + 3, 'n')
        c.rect(ex + 7, ey - 1, ex + 7, ey + 4, 'd')
    # undercarriage or floats
    if floats:
        c.rect(x0 + 4, y_bot + 4, x1 - 4, y_bot + 6, 'n')
        c.rect(x1 - 4, y_bot + 3, x1 - 2, y_bot + 4, 'n')
        c.rect(wx + 2, y_bot + 1, wx + 3, y_bot + 3, 'v')
        c.rect(x1 - 10, y_bot + 1, x1 - 9, y_bot + 3, 'v')
    else:
        main_x = x1 - L // 3 - (1 if taildragger else 3)
        c.rect(main_x, y_bot + 1, main_x + 2, y_bot + gear_h, 'd')
        if taildragger:
            c.rect(x0 + 2, y_bot - 3, x0 + 3, y_bot, 'd')
        else:
            c.rect(x1 - cow - 2, y_bot + 1, x1 - cow - 1, y_bot + gear_h, 'd')
    return c


# family code -> builder arguments. Sizes are pixel lengths before the outline is added.
FAMILIES = {
    'LS': lambda: prop(20, 5, 'high', 1, fin_h=4, wing_len=11, big_cowl=False, gear_h=2),
    'HS': lambda: prop(26, 6, 'high', 1, fin_h=5, wing_len=14, gear_h=3),
    'FS': lambda: prop(26, 6, 'high', 1, floats=True, fin_h=5, wing_len=14),
    'TT': lambda: prop(34, 7, 'high', 2, fin_h=7, wing_len=18, gear_h=3),
    'FT': lambda: prop(34, 7, 'high', 2, floats=True, fin_h=7, wing_len=18),
    'TD': lambda: prop(40, 8, 'low', 2, taildragger=True, fin_h=8, wing_len=18, gear_h=3),
    'CT': lambda: prop(40, 7, 'low', 2, fin_h=8, wing_len=17, gear_h=3),
    'RT': lambda: prop(46, 8, 'high', 2, fin_h=9, wing_len=20, gear_h=4),
    'RJ': lambda: jet(48, 7, 7, 14, 2, 8, 12, 20, 10, 2, engines='rear2', t_tail=True),
    'MD': lambda: jet(56, 8, 8, 16, 2, 9, 13, 22, 11, 2, engines='rear2', t_tail=True),
    'NB': lambda: jet(60, 9, 8, 16, 2, 10, 13, 24, 12, 2, engines='wing2'),
    'WB': lambda: jet(76, 11, 9, 18, 3, 12, 15, 30, 16, 3, engines='wing2'),
    'JB': lambda: jet(88, 12, 9, 20, 3, 13, 16, 34, 18, 3, engines='wing4', hump=3),
    'SB': lambda: jet(92, 13, 9, 20, 3, 14, 17, 36, 20, 4, engines='wing4', hump=5),
}


def build(family):
    return FAMILIES[family]().outline().trim()
