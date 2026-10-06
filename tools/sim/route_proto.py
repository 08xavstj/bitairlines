"""Prototype of fares and operating costs: how much does an aircraft earn on a route? Used to balance the economy before the Swift port.

    python tools/sim/route_proto.py
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import demand_proto as dp  # noqa: E402
from data import countries  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SIZE_EIGHTHS, K_CONST = 7, 2.0

FARE_TABLE = [(0, 25), (50, 45), (100, 70), (200, 105), (400, 150), (800, 210), (1500, 290), (3000, 420), (6000, 640), (10000, 860), (16000, 1150)]
FUEL_JET, FUEL_AVGAS = 1.00, 1.90                 # USD per kg
FARE_SCALE = 0.85                                 # the table above is a full-service average; this brings it to a blend of full-service and discount
ISOLATION_PREMIUM = 1.1                           # fly-in communities pay up to this much more
CARGO_K = 0.18                                    # kg per day per person^(7/8) (see cargo_per_day)
CARGO_RATE_TABLE = [(0, 1.2), (100, 2.0), (400, 2.6), (1000, 3.2), (3000, 3.5), (10000, 3.8)]   # USD per kg by distance
PILOT_H, CABIN_H = 110.0, 45.0                    # loaded crew cost per block hour, per person
HANDLING_PER_PAX = 14.0                           # ground handling, catering, passenger service, distribution
SALES_SHARE = 0.05                                # commissions and card fees as a share of ticket revenue
LOAD_CAP = 0.88                                   # peak-day spill: a flight is never perfectly full on average
LANDING_RATE = {'L': 14.0, 'M': 8.0, 'S': 4.0, 'W': 3.0}   # USD per tonne of max takeoff weight
LANDING_MIN = 40.0
PAX_FEE = {'L': 5.0, 'M': 3.0, 'S': 2.0, 'W': 1.5}
FUEL_PREMIUM = {'L': 0.0, 'M': 0.10, 'S': 0.35, 'W': 0.40}
TURNAROUND_H = {'P': 0.4, 'T': 0.5, 'J': 0.75}
MAX_HOURS_PER_DAY = {1: 9.0, 2: 10.0, 3: 10.0, 4: 11.0, 5: 12.0, 6: 14.0, 7: 14.0}


def load_types():
    text = open(os.path.join(ROOT, 'AirlineCore/Sources/CoreCatalog/AircraftRows.swift'), encoding='utf-8').read()
    body = text.split('#"""')[1].split('"""#')[0].strip().splitlines()
    types = {}
    for line in body:
        f = line.split('|')
        types[f[0]] = dict(id=f[0], name=f[2], engine=f[4], seats=int(f[5]), cargo=int(f[6]), range=int(f[7]), cruise=int(f[8]), burn=int(f[9]),
                           runway=int(f[10]), ops=f[11], price=int(f[12]) * 1000, mtow=int(f[13]), maint=int(f[14]), pilots=int(f[15]), level=int(f[16]))
    return types


def fare(a, b):
    base = dp.interpolate(FARE_TABLE, dp.km(a, b))
    return FARE_SCALE * base * (1.0 + ISOLATION_PREMIUM * (dp.isolation(a) + dp.isolation(b)) / 2.0)


def cargo_per_day(a, b):
    """Freight kg per day from a to b: what the people at b need, far more for a fly-in community that has no road."""
    return CARGO_K * dp.power_eighths(min(b['pop'], dp.POP_CAP), 7) * (0.1 + 3.0 * dp.isolation(b))


def leg_cost(t, a, b, age_factor=1.0):
    d = dp.km(a, b)
    block = (0.45 if t['engine'] == 'J' else 0.30) + d / t['cruise']
    fuel_price = FUEL_AVGAS if t['engine'] == 'P' else FUEL_JET
    premium = 1.0 + (FUEL_PREMIUM[a['kind']] + FUEL_PREMIUM[b['kind']]) / 2.0
    fuel = t['burn'] * block * fuel_price * premium
    cabin = 0 if t['seats'] <= 19 else (t['seats'] + 49) // 50
    crew = (t['pilots'] * PILOT_H + cabin * CABIN_H) * block
    maint = t['maint'] * block * age_factor
    tonnes = t['mtow'] / 1000.0
    landing = max(LANDING_MIN, LANDING_RATE[b['kind']] * tonnes)
    nav = 0.9 * math.sqrt(tonnes / 50.0) * d
    return dict(block=block, fuel=fuel, crew=crew, maint=maint, landing=landing, nav=nav, total=fuel + crew + maint + landing + nav)


def can_use(t, a):
    if a['surf'] == 'W':
        return 'W' in t['ops']
    if a['surf'] == 'G':
        return 'G' in t['ops'] and a['rwy'] >= t['runway']
    return ('P' in t['ops'] or 'G' in t['ops']) and a['rwy'] >= t['runway']


def evaluate(t, a, b, wealth, round_trips):
    """Profit per day for one aircraft flying `round_trips` round trips a day between a and b (None if it cannot)."""
    d = dp.km(a, b)
    if not (can_use(t, a) and can_use(t, b)) or d > t['range']:
        return None
    cost = leg_cost(t, a, b)
    per_day = dp.demand_per_day(a, b, wealth, K_CONST, SIZE_EIGHTHS) + dp.demand_per_day(b, a, wealth, K_CONST, SIZE_EIGHTHS)
    legs = 2 * round_trips
    pax_each = min(t['seats'] * LOAD_CAP, per_day / 2 / round_trips)
    cargo_each = min(t['cargo'] * 0.7, (cargo_per_day(a, b) + cargo_per_day(b, a)) / 2 / round_trips)
    cargo_rate = dp.interpolate(CARGO_RATE_TABLE, d)
    gross = legs * pax_each * fare(a, b) + legs * cargo_each * cargo_rate
    revenue = gross * (1 - SALES_SHARE)
    handling = legs * pax_each * (HANDLING_PER_PAX + (PAX_FEE[a['kind']] + PAX_FEE[b['kind']]) / 2)
    daily_cost = legs * cost['total'] + handling + 120 + 0.0025 * t['price'] / 365
    hours = legs * (cost['block'] + TURNAROUND_H[t['engine']])
    return dict(profit=revenue - daily_cost, revenue=revenue, cost=daily_cost, lf=pax_each / t['seats'], hours=hours, fare=fare(a, b), demand=per_day, feasible=hours <= MAX_HOURS_PER_DAY[t['level']])


if __name__ == '__main__':
    airports = dp.load_airports()
    by = {a['code']: a for a in airports}
    wealth = {iso: w for iso, (_, _, w) in countries.load().items()}
    types = load_types()
    routes = [('YEV', 'YUB', ['c208', 'dhc6', 'dc3', 'dh8c']), ('YEV', 'YZF', ['dhc6', 'dc3', 'dh8c', 'at72', 'b732', 'b738']),
              ('YZF', 'YEG', ['dh8c', 'at72', 'e175', 'b738']), ('YYZ', 'YUL', ['dh8d', 'e175', 'a320', 'b738']),
              ('LHR', 'JFK', ['b763', 'b789', 'a359', 'b77w', 'a388']), ('SYD', 'LAX', ['b789', 'a359', 'b77w', 'b744'])]
    for f, t, ids in routes:
        a, b = by[f], by[t]
        print(f'\n{f}-{t}  {dp.km(a, b):.0f} km  demand {evaluate(types[ids[0]], a, b, wealth, 1)["demand"] if evaluate(types[ids[0]], a, b, wealth, 1) else "n/a"} pax/day both ways  fare ${fare(a, b):.0f}')
        for tid in ids:
            ty = types[tid]
            best = None
            for rt in (0.25, 0.5, 1, 2, 3, 4, 5, 6):
                r = evaluate(ty, a, b, wealth, rt)
                if r and r['feasible'] and (best is None or r['profit'] > best[1]['profit']):
                    best = (rt, r)
            if best:
                rt, r = best
                payback = ty['price'] * 0.4 / (r['profit'] * 365) if r['profit'] > 0 else float('inf')
                print(f"  {ty['name']:34s} {rt:>4} rt/day  LF {r['lf']*100:4.0f}%  profit ${r['profit']:>9,.0f}/day  payback(used) {payback:5.1f} yr")
            else:
                print(f"  {ty['name']:34s} cannot fly this route")
