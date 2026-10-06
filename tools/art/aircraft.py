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


def _paint(c, x, y, ch, over='fuc'):
    """Sets a pixel only where it lands on the listed roles, so details never float outside the body."""
    if c.get(x, y) in over:
        c.set(x, y, ch)


def _line(c, x0, y0, x1, y1, ch):
    """A one-pixel line between two points."""
    steps = max(abs(x1 - x0), abs(y1 - y0), 1)
    for i in range(steps + 1):
        c.set(round(x0 + (x1 - x0) * i / steps), round(y0 + (y1 - y0) * i / steps), ch)


def _swept_wing(c, root_lead, root_trail, root_y, tip_lead, tip_trail, tip_y):
    """A near wing seen sloping down toward the viewer: light top, a dark leading edge so it stands out against the belly, a grey trailing edge."""
    c.poly([(root_trail, root_y), (root_lead, root_y), (tip_lead, tip_y), (tip_trail, tip_y)], 'w')
    _line(c, root_lead, root_y, tip_lead, tip_y, 'k')
    _line(c, root_trail, root_y, tip_trail, tip_y, 'v')
    _line(c, tip_trail, tip_y, tip_lead, tip_y, 'k')


def _gear(c, x, y, length):
    """A landing gear leg: a grey strut ending in a dark wheel."""
    c.rect(x, y, x, y + length - 1, 'v')
    c.rect(x - 1, y + length - 1, x + 1, y + length, 'd')


def _pod(c, x, y, w, h, prop_h):
    """An engine pod seen from the side, pointing right: metal body, dark intake underneath, a spinner and a propeller disc."""
    c.rect(x, y, x + w - 1, y + h - 1, 'n')
    c.rect(x, y + h - 1, x + 1, y + h - 1, 'v')
    c.rect(x + w - 2, y + h - 1, x + w - 1, y + h - 1, 'd')
    c.set(x + w, y + h // 2, 'n')
    top = y + h // 2 - prop_h // 2
    c.rect(x + w + 1, top, x + w + 1, top + prop_h - 1, 'd')


def _jet_pod(c, x, y, w=8, h=4):
    """A turbofan pod hanging under a wing: metal body, dark intake at the front, grey exhaust ring at the back."""
    c.rect(x, y, x + w - 1, y + h - 1, 'n')
    c.rect(x, y, x + w - 1, y, 'k')
    c.rect(x + w - 1, y + 1, x + w - 1, y + h - 1, 'd')
    c.rect(x, y + 1, x, y + h - 2, 'v')


def jet(L, H, nose, tail_len, rise, fin_h, fin_len, wing_x, wing_len, wing_drop, engines='wing2', t_tail=False, hump=0, gear=2):
    """An airliner. engines: 'wing2', 'wing4', 'rear2'. hump: extra height of a second deck over the front half (A380)."""
    W, Hc = L + 14, fin_h + H + hump + wing_drop + 14
    c = Canvas(W, Hc)
    x0, x1 = 6, 6 + L - 1
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

    # cockpit: a dark wedge that follows the slope of the nose
    gy = y_top + (1 if not hump else 1 - hump + hump)
    for dx in range(-2, 5):
        _paint(c, x1 - nose + dx, gy, 'g')
    for dx in range(0, 5):
        _paint(c, x1 - nose + dx, gy + 1, 'g')
    # the front door
    door = x1 - nose - 6
    c.rect(door, gy + 1, door, min(belly - 1, gy + 4), 'v')

    # fin and tail plane
    base_front, base_back = x0 + fin_len + 2, x0 + 1
    tip_front = base_back + max(4, fin_len // 2)
    c.poly([(base_front, y_top), (tip_front, y_top - fin_h), (base_back - 1, y_top - fin_h), (base_back, y_top)], 't')
    c.rect(base_back - 1, y_top - fin_h, tip_front - 1, y_top - fin_h + 1, 'm')
    if t_tail:
        c.rect(base_back - 3, y_top - fin_h - 1, base_back + 7, y_top - fin_h - 1, 'w')
        c.rect(base_back - 2, y_top - fin_h, base_back + 5, y_top - fin_h, 'v')
    else:
        ty = y_top + max(1, H // 4)
        c.rect(x0 - 3, ty, x0 + 7, ty + 1, 'w')
        c.rect(x0 - 3, ty + 2, x0 + 3, ty + 2, 'v')
    _logo_rect(c)

    # wing, with a winglet on the big ones
    root_lead, root_trail = wing_x + wing_len, wing_x + 2
    tip_y = y_bot + wing_drop
    sweep = max(4, wing_len * 2 // 5)
    tip_lead, tip_trail = root_lead - sweep, root_trail - sweep
    _swept_wing(c, root_lead, root_trail, y_bot - 1, tip_lead, tip_trail, tip_y)
    if wing_len >= 12:
        c.rect(tip_trail, tip_y - 2, tip_trail + 1, tip_y - 1, 'w')

    # engines
    if engines.startswith('wing'):
        span = (root_lead - tip_lead)
        fractions = [0.55] if engines == 'wing2' else [0.35, 0.8]
        for f in fractions:
            ex = round(tip_lead + span * f) - 6
            _jet_pod(c, ex, tip_y - 1, 8, 4)
    else:
        ex = x0 + tail_len - 3
        c.rect(ex, y_top, ex + 8, y_top + 2, 'n')
        c.rect(ex + 8, y_top, ex + 8, y_top + 2, 'd')
        c.rect(ex, y_top + 1, ex, y_top + 1, 'v')

    # undercarriage
    nose_leg = x1 - nose - 5
    mains = [wing_x + wing_len // 2 - 3] if gear == 2 else [wing_x + wing_len // 2 - 6, wing_x + wing_len // 2]
    for gx in [nose_leg] + mains:
        _gear(c, gx, y_bot + 1, wing_drop + 2 if gx != nose_leg else wing_drop + 1)
    return c


def prop(L, H, wing='high', engines=1, floats=False, taildragger=False, fin_h=6, wing_len=None, big_cowl=True, strut=True, gear_h=3):
    """A propeller aircraft: utility single, twin turboprop, commuter, taildragger. engines is 1 or 2."""
    wing_len = wing_len or max(8, L // 2)
    W, Hc = L + 14, fin_h + H + gear_h + 18
    c = Canvas(W, Hc)
    x0, x1 = 6, 6 + L - 1
    y_top = fin_h + 7
    y_bot = y_top + H - 1
    belly = y_top + int(H * 0.6)
    cow = 4 if big_cowl else 3

    for x in range(x0, x1 + 1):
        t = x - x0
        top, bot = y_top, y_bot
        if t < L // 3:
            bot = y_bot - round((L // 3 - t) * (H * 0.55) / (L // 3))
        if x > x1 - cow - 3:
            top += 1
        if x > x1 - cow:
            top += 1
            bot -= 1
        for y in range(top, bot + 1):
            c.set(x, y, 'u' if y >= belly else 'f')
    cheat = y_top + int(H * 0.5)
    for x in range(x0 + 5, x1 - cow - 3):
        if c.get(x, cheat) in 'fu':
            c.set(x, cheat, 'c')
    # cabin windows and the windscreen
    wy = y_top + 1
    for x in range(x0 + L // 3 + 1, x1 - cow - 6, 3):
        c.rect(x, wy, x + 1, wy + max(0, min(1, H // 4)), 'g')
    for dx in range(-3, 0):
        _paint(c, x1 - cow + dx + 1, y_top + 1, 'g')
        _paint(c, x1 - cow + dx + 1, y_top + 2, 'g')
    if engines == 1:
        _pod(c, x1 - cow + 1, y_top + 2, cow, H - 3, H + 1)
    # fin and tail plane
    c.poly([(x0 + 6, y_top), (x0 + 3, y_top - fin_h), (x0 - 1, y_top - fin_h), (x0 + 1, y_top)], 't')
    c.rect(x0 - 1, y_top - fin_h, x0 + 3, y_top - fin_h + 1, 'm')
    c.rect(x0 - 3, y_top + 1, x0 + 5, y_top + 1, 'w')
    c.rect(x0 - 2, y_top + 2, x0 + 3, y_top + 2, 'v')
    _logo_rect(c)
    # wing
    wx = x0 + L // 3 + 2
    if wing == 'high':
        c.rect(wx, y_top - 3, wx + wing_len, y_top - 2, 'w')
        c.hline(wx, wx + wing_len, y_top - 1, 'v')
        if strut and engines == 1:
            c.poly([(wx + 3, y_top), (wx + 5, y_top), (wx + 11, y_top - 1), (wx + 9, y_top - 1)], 'v')
            c.rect(wx + 4, y_top + 1, wx + 4, y_top + 1, 'v')
    else:
        _swept_wing(c, wx + wing_len, wx + 2, y_bot - 1, wx + wing_len - 6, wx - 4, y_bot + 4)
    if engines == 2:
        if wing == 'high':
            _pod(c, wx + wing_len - 8, y_top - 4, 7, 4, H)
        else:
            _pod(c, wx + wing_len - 10, y_bot + 2, 8, 5 if taildragger else 4, H)
    # undercarriage or floats
    if floats:
        c.rect(x0 + 5, y_bot + 5, x1 - 5, y_bot + 7, 'n')
        c.rect(x1 - 5, y_bot + 4, x1 - 3, y_bot + 5, 'n')
        c.rect(x0 + 5, y_bot + 7, x1 - 5, y_bot + 7, 'v')
        c.rect(wx + 2, y_bot + 1, wx + 3, y_bot + 4, 'v')
        c.rect(x1 - 11, y_bot + 1, x1 - 10, y_bot + 4, 'v')
    else:
        main_x = x1 - L // 3 - (1 if taildragger else 3)
        _gear(c, main_x, y_bot + 1, gear_h)
        if taildragger:
            _gear(c, x0 + 3, y_bot - 2, 3)
        else:
            _gear(c, x1 - cow - 2, y_bot + 1, gear_h)
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
    'RJ': lambda: jet(48, 7, 7, 14, 2, 8, 12, 20, 10, 3, engines='rear2', t_tail=True),
    'MD': lambda: jet(56, 8, 8, 16, 2, 9, 13, 22, 11, 3, engines='rear2', t_tail=True),
    'NB': lambda: jet(60, 9, 8, 16, 2, 10, 13, 24, 12, 4, engines='wing2'),
    'WB': lambda: jet(76, 11, 9, 18, 3, 12, 15, 30, 16, 5, engines='wing2'),
    'JB': lambda: jet(88, 12, 9, 20, 3, 13, 16, 34, 18, 6, engines='wing4', hump=3),
    'SB': lambda: jet(92, 13, 9, 20, 3, 14, 17, 36, 20, 6, engines='wing4', hump=5),
}


def build(family):
    return FAMILIES[family]().outline().trim()
