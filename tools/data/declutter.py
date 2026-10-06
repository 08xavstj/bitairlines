"""Thins the map: keeps big cities and the places that are far from one, drops the towns in between.

A town on the road network (Abbotsford, Quesnel) is cut. A fly-in community (Inuvik, Ulukhaktok, Cambridge Bay) stays.
The cut airports are not thrown away: they go to a retired list, so an older save that flies there still loads.

    kept, retired = declutter.split(airports)    # each airport needs code, lat, lon, pop, kind, surf
"""
import collections
import math

# A city: an international airport or this many people in its catchment.
CITY_POP = 250_000
# Two cities closer than this are one metro area; the bigger one stays (Vancouver, not Abbotsford).
METRO_KM = 100
# A place is remote when no town of TOWN_POP people is within ROAD_KM (no big neighbour to drive to).
TOWN_POP = 20_000
ROAD_KM = 250
# A gravel strip or a lake also stays when no city of BUSH_CITY_POP is within BUSH_KM (bush flying).
BUSH_CITY_POP = 100_000
BUSH_KM = 150
# Used by the start regions, scenarios, tests and the demo: always kept.
PROTECTED = set("""
ANU ASP BET BIT BME BVB DLG FAI FTE GKA GOH HGU HIR HND ISA JAV JFK JMO LCY LGA LGW LHR LTN LUA MAG MEL NAN OTZ PHH
PUQ RBR SKB SUV SXM SYD TBT USH VLI YCB YCO YEG YEV YFB YHI YPC YRT YSY YUB YVR YYZ YZF
""".split())


def km(a, b):
    p1, p2 = math.radians(a['lat']), math.radians(b['lat'])
    dl = math.radians(b['lon'] - a['lon'])
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371 * 2 * math.asin(min(1.0, math.sqrt(h)))


def _grid(airports):
    grid = collections.defaultdict(list)
    for a in airports:
        grid[(int(a['lat'] // 2), int(a['lon'] // 2))].append(a)
    return grid


def _near(grid, a, radius):
    ci, cj = int(a['lat'] // 2), int(a['lon'] // 2)
    span = int(radius / (222 * max(0.15, math.cos(math.radians(a['lat']))))) + 2
    for i in range(ci - 2, ci + 3):
        for j in range(cj - span, cj + span + 1):
            for o in grid.get((i, j), []):
                if o is not a and km(a, o) <= radius:
                    yield o


def is_city(a):
    return a['kind'] == 'L' or a['pop'] >= CITY_POP


def reason(a, grid):
    """Why the airport stays ('protected', 'city', 'remote', 'bush'), or None when it is cut."""
    if a['code'] in PROTECTED:
        return 'protected'
    if is_city(a):
        bigger = any(is_city(o) and o['pop'] > a['pop'] for o in _near(grid, a, METRO_KM))
        return None if bigger else 'city'
    if not any(o['pop'] >= TOWN_POP for o in _near(grid, a, ROAD_KM)):
        return 'remote'
    if a['surf'] in ('G', 'W') and not any(o['pop'] >= BUSH_CITY_POP for o in _near(grid, a, BUSH_KM)):
        return 'bush'
    return None


def split(airports):
    grid = _grid(airports)
    kept, retired = [], []
    for a in airports:
        (kept if reason(a, grid) else retired).append(a)
    return kept, retired
