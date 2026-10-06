"""Prototype of the first route at every start home: the forecast the game shows for a new airline's best suggested route, with
the starter that suits the home best. Reads the generated Swift rows, so it needs no raw downloads.

    python tools/sim/start_homes_proto.py            (the table with the rules as they are in Tuning.swift)
    python tools/sim/start_homes_proto.py --old      (the same with the rules before the lifeline and the honest forecast)

It mirrors CoreWorld: Demand (isolation by wealth tier, the lifeline floor), Forecast (the starter's own wear, heavy checks spread
over the days, the schedule sized on the share of a contested market the airline can win) and RouteIdeas (60 nearest airports,
50 to 800 km, level 1, permits). With --old it reproduces the 'PLAYTEST first route' lines of the CI log before the change.
"""
import math
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'AirlineCore', 'Sources', 'CoreCatalog')
OLD = '--old' in sys.argv

# Demand (Tuning.swift)
PROPENSITY = [0.02, 0.08, 0.30, 1.00, 2.00]
ISOLATION_POPULATION = [20000] * 5 if OLD else [80000, 80000, 35000, 20000, 20000]
LIFELINE = 0.0 if OLD else 0.5
DISTANCE = [(0, 0.0), (50, 0.10), (150, 0.38), (300, 0.62), (600, 1.0), (1200, 0.85), (2500, 0.55), (5000, 0.38), (9000, 0.28), (15000, 0.2), (20100, 0.15)]
FARES = [(0, 25), (50, 45), (100, 70), (200, 105), (400, 150), (800, 210), (1500, 290), (3000, 420), (6000, 640), (10000, 860), (16000, 1150)]
CARGO_RATE = [(0, 1.2), (100, 2.0), (400, 2.6), (1000, 3.2), (3000, 3.5), (10000, 3.8)]
LANDING = {'L': 14, 'M': 8, 'S': 4, 'W': 3}
PAX_FEE = {'L': 5, 'M': 3, 'S': 2, 'W': 1.5}
FUEL_PREMIUM = {'L': 0, 'M': 0.10, 'S': 0.35, 'W': 0.40}
TIER = {'LS': 1, 'HS': 1, 'FS': 1, 'TT': 2, 'FT': 2, 'CT': 2, 'RT': 2, 'TD': 2, 'RJ': 3, 'MD': 3, 'NB': 3, 'WB': 4, 'JB': 4, 'SB': 4}
STEPS = [0.25, 0.5, 1, 1.5, 2, 3, 4, 5, 6, 8, 10, 12, 16, 24]
HOMES = "SXM ANU SKB VLI HIR SUV ASP ISA BME TBT RBR BVB HGU GKA MAG PUQ USH FTE LUA JMO PHH BET OTZ DLG YEV YCB YRT JAV GOH".split()


def rows(path):
    text = open(path, encoding='utf-8').read()
    return text.split('#"""')[1].split('"""#')[0].strip().splitlines()


AIRPORTS, WEALTH, TYPES = {}, {}, {}
for name in sorted(os.listdir(os.path.join(SRC, 'Data'))):
    if name.startswith('AirportRows_') and 'Retired' not in name:
        for line in rows(os.path.join(SRC, 'Data', name)):
            f = line.split('|')
            if len(f) == 15:
                AIRPORTS[f[0]] = dict(code=f[0], cc=f[5], lat=float(f[7]), lon=float(f[8]), rwy=int(f[10]), surf=f[11], kind=f[12], pop=int(f[14]))
for line in rows(os.path.join(SRC, 'Data', 'CountryRows.swift')):
    f = line.split('|')
    WEALTH[f[0]] = int(f[3])
for line in rows(os.path.join(SRC, 'AircraftRows.swift')):
    f = line.split('|')
    TYPES[f[0]] = dict(id=f[0], fam=f[3], engine=f[4], seats=int(f[5]), cargo=int(f[6]), range=int(f[7]), cruise=int(f[8]), burn=int(f[9]), runway=int(f[10]),
                       ops=f[11], price=int(f[12]) * 1000, mtow=int(f[13]), maint=int(f[14]), pilots=int(f[15]), level=int(f[16]), inprod=f[19] == '1')


def interp(table, x):
    if x <= table[0][0]:
        return table[0][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return table[-1][1]


def km(a, b):
    p1, p2 = math.radians(a['lat']), math.radians(b['lat'])
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(b['lon'] - a['lon']) / 2) ** 2
    return 6371.0088 * 2 * math.asin(min(1.0, math.sqrt(h)))


def wealth(a):
    return min(max(WEALTH.get(a['cc'], 3), 1), 5)


def isolation(a):
    remote = max(0.0, 1.0 - a['pop'] / ISOLATION_POPULATION[wealth(a) - 1])
    return remote * (0.6 if a['surf'] == 'P' else 1.0)


def propensity(a):
    iso = isolation(a)
    return max(PROPENSITY[wealth(a) - 1], LIFELINE * iso) * (1 + 3.0 * iso)


def eighths(x, k):
    return x ** (k / 8.0)


def pax(a, b, d):
    size = math.sqrt(eighths(min(a['pop'], 9e6), 7) * eighths(min(b['pop'], 9e6), 7))
    return 2.0 * math.sqrt(propensity(a) * propensity(b)) * size * interp(DISTANCE, d) / 365.0


def cargo(b):
    return 0.18 * eighths(min(b['pop'], 9e6), 7) * (0.1 + 3.0 * isolation(b))


def fare(a, b, d):
    return 0.85 * interp(FARES, d) * (1 + 0.9 * (isolation(a) + isolation(b)) / 2)


def block(t, d):
    return (0.45 if t['engine'] == 'J' else 0.30) + d / t['cruise']


def leg_cost(t, a, b, d, wear):
    bh = block(t, d)
    fuel = t['burn'] * bh * (1.9 if t['engine'] == 'P' else 1.0) * (1 + (FUEL_PREMIUM[a['kind']] + FUEL_PREMIUM[b['kind']]) / 2)
    cabin = 0 if t['seats'] <= 19 else (t['seats'] + 49) // 50
    tonnes = t['mtow'] / 1000.0
    total = fuel + (t['pilots'] * 80 + cabin * 45) * bh + t['maint'] * bh * wear + max(40, LANDING[b['kind']] * tonnes) + 0.9 * math.sqrt(tonnes / 50) * d
    return total, bh


def wear_factor(age, condition):
    return min(2.2, 1 + 0.02 * age) * (1 + (100 - condition) / 250.0)


def check_cost(t, age):
    return t['price'] * 0.03 * min(2.5, 1 + 0.03 * age)


def own_share(perday, rep=10):
    return min(0.5, max(0.05, 0.05 + 0.004 * rep + 0.03 * perday))


def contested(a, b, perday):
    intensity = min(1.0, math.sqrt(min(a['pop'], b['pop']) / 1.5e6))
    return (1 - intensity) + intensity * own_share(perday)


def cycles(t, dists):
    bh = sum(block(t, d) for d in dists)
    cycle = bh + {'P': 0.4, 'T': 0.5, 'J': 0.75}[t['engine']] * len(dists)
    max_hours = {1: 9, 2: 10, 3: 10, 4: 11, 5: 12}.get(t['level'], 14)
    return min(24 / max(0.5, cycle), max_hours * 0.9 / max(0.25, bh))


def forecast(stops, t, age, condition):
    """World.forecast(on:) for one aircraft with the airline's own wear (the starter's age and condition)."""
    pts = [AIRPORTS[s] for s in stops]
    legs = [(pts[i], pts[(i + 1) % len(pts)]) for i in range(len(pts))]
    dists = [km(a, b) for a, b in legs]
    markets = [pax(a, b, d) for (a, b), d in zip(legs, dists)]
    seats = max(1.0, t['seats'] * 0.8)
    f = min(m * 0.75 for m in markets) / seats
    if not OLD:
        for _ in range(2):
            f = min(m * 0.75 * contested(a, b, f) for m, (a, b) in zip(markets, legs)) / seats
    per = max(0.05, cycles(t, dists))
    f = max(0.25, min(min(STEPS, key=lambda s: abs(s - min(f, per))), per))
    wear = wear_factor(age, condition) if not OLD else wear_factor(12, 80)
    revenue = cost = hours = 0.0
    for (a, b), d, market in zip(legs, dists, markets):
        quality = 0.9 + 0.001 * 10
        share = contested(a, b, max(1, round(f * 7)) / 7.0) * quality
        carried = min(market * share, f * (2 * market * share + 4), f * t['seats'] * 0.88)
        freight = min(cargo(b) * share, f * (2 * cargo(b) * share + 40), f * t['cargo'] * 0.7)
        revenue += carried * fare(a, b, d) * 0.95 + freight * interp(CARGO_RATE, d)
        flight, bh = leg_cost(t, a, b, d, wear)
        cost += f * flight + carried * (14 + (PAX_FEE[a['kind']] + PAX_FEE[b['kind']]) / 2) + freight * 0.06
        hours += f * bh
    cost += 120 + 0.0025 * t['price'] / 365 + t['pilots'] * 2000 * TIER[t['fam']] * 12 / 365
    if not OLD:
        cost += max(check_cost(t, age) / 1461.0, check_cost(t, age) * hours / 6000.0)
    return revenue - cost, f


def can_use(t, a):
    if a['surf'] == 'W':
        return 'W' in t['ops']
    fits = a['rwy'] >= t['runway']
    return (('P' in t['ops'] or 'G' in t['ops']) and fits) if a['surf'] == 'P' else ('G' in t['ops'] and fits)


def required_level(a):
    p = a['pop']
    base = 6 if p >= 12e6 else 5 if p >= 5e6 else 4 if p >= 1.5e6 else 3 if p >= 4e5 else 2 if p >= 8e4 else 1
    return max(base, 2) if a['kind'] == 'L' else base


def permits(home):
    if sum(1 for a in AIRPORTS.values() if a['cc'] == home['cc']) - 1 >= 3:
        return {home['cc']}
    return {home['cc']} | {a['cc'] for a in AIRPORTS.values() if a['cc'] != home['cc'] and km(a, home) <= 250}


def best_first_route(code):
    home = AIRPORTS[code]
    allowed = permits(home)
    near = sorted((a for a in AIRPORTS.values() if a['code'] != code), key=lambda a: km(home, a))[:60]
    best = None
    for t in TYPES.values():
        if t['level'] != 1 or not can_use(t, home):
            continue
        age = 12.0 if t['inprod'] else 45.0
        if t['price'] * max(0.12 if t['inprod'] else 0.25, 1 - (0.05 if t['engine'] == 'J' else 0.035) * age) * (0.7 + 0.3 * 0.78) > 3_400_000:
            continue
        for b in near:
            d = km(home, b)
            if d < 50 or d > min(t['range'], 800) or required_level(b) > 1 or b['cc'] not in allowed or not can_use(t, b):
                continue
            profit, f = forecast([code, b['code']], t, age, 78.0)
            if profit > 0 and (best is None or profit > best[0]):
                best = (profit, b['code'], t['id'], f)
    return best


if __name__ == '__main__':
    print('rules:', 'before the lifeline' if OLD else 'lifeline, honest forecast')
    for code in HOMES:
        best = best_first_route(code)
        line = f'{best[1]} {best[2]} {best[0]:6.0f}/day at {round(best[3], 2)} a day' if best else 'none'
        print(f'{code} wealth {WEALTH.get(AIRPORTS[code]["cc"])}: {line}')
