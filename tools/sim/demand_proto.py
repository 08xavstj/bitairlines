"""Prototype of the passenger demand model, to calibrate against real route traffic before porting to Swift (CoreWorld/Demand.swift).

    python tools/sim/demand_proto.py

Only operations that the Swift port can repeat exactly (+ - * / sqrt, tables with linear interpolation) are used for the model itself.
The error report at the bottom uses math.log for judging only.
"""
import math
import os
import pickle
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from data import pipeline  # noqa: E402

# trips per person per year by wealth tier 1..5
PROPENSITY = [0.02, 0.08, 0.30, 1.00, 2.00]
# distance (km) -> share of the base flow that is still flown at that distance
DISTANCE_TABLE = [(0, 0.0), (50, 0.10), (150, 0.38), (300, 0.62), (600, 1.0), (1200, 0.85), (2500, 0.55), (5000, 0.38), (9000, 0.28), (15000, 0.2), (20100, 0.15)]


def interpolate(table, x):
    if x <= table[0][0]:
        return table[0][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return table[-1][1]


def power_eighths(x, k):
    """x ** (k / 8) for k in 0...16 using only multiplications and square roots."""
    r1 = math.sqrt(x)
    r2 = math.sqrt(r1)
    r3 = math.sqrt(r2)
    out = 1.0
    whole, frac = divmod(k, 8)
    for _ in range(whole):
        out *= x
    if frac & 4:
        out *= r1
    if frac & 2:
        out *= r2
    if frac & 1:
        out *= r3
    return out


def isolation(a):
    """0 for a town with roads and alternatives, up to 1 for a fly-in community on a gravel strip or a lake."""
    remote = max(0.0, 1.0 - a['pop'] / 20000.0)
    return remote * (1.0 if a['surf'] != 'P' else 0.6)


def km(a, b):
    p1, p2 = math.radians(a['lat']), math.radians(b['lat'])
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(b['lon'] - a['lon']) / 2) ** 2
    return 6371.0088 * 2 * math.asin(min(1.0, math.sqrt(h)))


POP_CAP = 9_000_000          # people beyond this do not add demand: a megacity's far suburbs fly from its other airports, drive or take trains


def demand_per_day(a, b, wealth, k_const, size_eighths, isolation_boost=3.0):
    """Passengers per day in one direction, all airlines together."""
    pa = PROPENSITY[wealth[a['cc']] - 1] * (1 + isolation_boost * isolation(a))
    pb = PROPENSITY[wealth[b['cc']] - 1] * (1 + isolation_boost * isolation(b))
    size = math.sqrt(power_eighths(min(a['pop'], POP_CAP), size_eighths) * power_eighths(min(b['pop'], POP_CAP), size_eighths))
    return k_const * math.sqrt(pa * pb) * size * interpolate(DISTANCE_TABLE, km(a, b)) / 365.0


# (from, to, real one-way passengers per year, rough)
ANCHORS = [
    ('SYD', 'MEL', 4_300_000), ('HND', 'CTS', 4_400_000), ('LAX', 'SFO', 1_800_000), ('JFK', 'LAX', 1_500_000),
    ('LHR', 'JFK', 1_400_000), ('YVR', 'YYZ', 1_200_000), ('YEG', 'YYC', 450_000), ('YZF', 'YEG', 120_000),
    ('YEV', 'YZF', 12_000), ('YEV', 'YUB', 4_000), ('SIN', 'KUL', 1_500_000), ('SIN', 'LHR', 750_000), ('DXB', 'LHR', 1_000_000),
]


def load_airports():
    cache = os.path.join(os.environ.get('TEMP', '.'), 'airports_cache.pkl')
    if os.path.exists(cache):
        return pickle.load(open(cache, 'rb'))
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    data, _ = pipeline.build_airports(os.path.join(root, "data", "raw"))
    pickle.dump(data, open(cache, 'wb'))
    return data


def report(size_eighths, k_const, wealth, boost=3.0, verbose=True):
    by = {a['code']: a for a in AIRPORTS}
    total = 0.0
    for f, t, real in ANCHORS:
        a, b = by[f], by[t]
        d = demand_per_day(a, b, wealth, k_const, size_eighths, boost) * 365
        err = math.log(d / real)
        total += err * err
        if verbose:
            print(f'  {f}-{t:4s} {km(a, b):7.0f} km  model {d:>10,.0f}  real {real:>10,.0f}  x{d / real:5.2f}')
    return math.sqrt(total / len(ANCHORS))


if __name__ == '__main__':
    AIRPORTS = load_airports()
    from data import countries
    WEALTH = {iso: w for iso, (_, _, w) in countries.load().items()}
    best = None
    for eighths in (4, 5, 6, 7, 8):
        for k in [x / 4 for x in range(1, 400)]:
            e = report(eighths, k, WEALTH, verbose=False)
            if best is None or e < best[0]:
                best = (e, eighths, k)
        e, _, k = min(((report(eighths, kk / 4, WEALTH, verbose=False), eighths, kk / 4) for kk in range(1, 400)), key=lambda t: t[0])
        print(f'pop^{eighths}/8: best K={k:.2f}  rms log error {e:.2f}')
    print('best overall:', best)
    e, eighths, k = best
    print(f'\nanchors at pop^{eighths}/8, K={k}:')
    report(eighths, k, WEALTH)
