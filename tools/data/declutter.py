"""Thins the map to a clean, even spread: one airport per area, wherever in the world.

Airports are taken most important first (the protected list, then the biggest metro area, then international airports, then
the longest runway). Each kept airport claims a circle around it; an airport inside a kept one's circle is cut. Big cities
claim a smaller circle, so neighbouring big cities can both stay. A remote town stays because nothing else is near it.

The cut airports are not thrown away: they go to a retired list, so an older save that flies there still loads.

    kept, retired = declutter.split(airports)    # each airport needs code, lat, lon, pop, kind, rwy, surf
"""
import collections
import math

# The circle each kept airport claims, in km: about one airport per 200,000 square km away from big cities.
SPACING_KM = 250
# A metro area of this many people claims only this much, so big neighbouring cities both stay.
BIG_CITY_POP = 5_000_000
BIG_CITY_SPACING_KM = 180
# Around the start regions' headquarters a new airline needs places to fly to, so airports there only need to be this far apart.
START_AREA_KM = 300
START_AREA_SPACING_KM = 130
# Only small places get the closer spacing there; cities follow the normal rules.
START_AREA_MAX_POP = 300_000
START_HQ = set("""
SXM ANU SKB VLI HIR SUV ASP ISA BME TBT RBR BVB HGU GKA MAG PUQ USH FTE LUA JMO PHH BET OTZ DLG YEV YCB YRT JAV GOH
""".split())
# People within this distance count as one metro area when ranking a city's airports (so a city's main hub wins).
METRO_KM = 80
# Used by the start regions, scenarios, tests and the demo, or a city's main hub the ranking would miss: always kept.
PROTECTED = set("""
ANU ASP BET BIT BME BOM BVB DLG FAI FTE GKA GOH HGU HIR HND ISA JAV JFK JMO LCY LGA LGW LHR LTN LUA MAG MEL NAN OTZ PHH
PUQ RBR SKB SUV SXM SYD TBT USH VLI YCB YCO YEG YEV YFB YHI YPC YRT YSY YUB YVR YYZ YZF
""".split())


def km(a, b):
    p1, p2 = math.radians(a['lat']), math.radians(b['lat'])
    dl = math.radians(b['lon'] - a['lon'])
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371 * 2 * math.asin(min(1.0, math.sqrt(h)))


def _cells(airports, size):
    grid = collections.defaultdict(list)
    for a in airports:
        grid[(int(a['lat'] // size), int(a['lon'] // size))].append(a)
    return grid


def _near(grid, size, a, radius):
    ci, cj = int(a['lat'] // size), int(a['lon'] // size)
    rows = int(radius / (111 * size)) + 1
    cols = int(radius / (111 * size * max(0.1, math.cos(math.radians(a['lat']))))) + 1
    for i in range(ci - rows, ci + rows + 1):
        for j in range(cj - cols, cj + cols + 1):
            for o in grid.get((i, j), []):
                if o is not a and km(a, o) <= radius:
                    yield o


def metro_population(airports):
    """People within METRO_KM of each airport (its own catchment included), keyed by code."""
    grid = _cells(airports, 1)
    return {a['code']: a['pop'] + sum(o['pop'] for o in _near(grid, 1, a, METRO_KM)) for a in airports}


def spacing(a, metro, start_areas=()):
    if metro[a['code']] >= BIG_CITY_POP:
        return BIG_CITY_SPACING_KM
    if a['pop'] <= START_AREA_MAX_POP and any(km(a, hq) <= START_AREA_KM for hq in start_areas):
        return START_AREA_SPACING_KM
    return SPACING_KM


def split(airports):
    metro = metro_population(airports)
    start_areas = [a for a in airports if a['code'] in START_HQ]

    def rank(a):
        return (a['code'] in PROTECTED, round(math.log10(max(10, metro[a['code']])) * 3), a['kind'] == 'L', a['rwy'], a['pop'], a['code'])

    kept, retired = [], []
    grid = collections.defaultdict(list)
    for a in sorted(airports, key=rank, reverse=True):
        radius = spacing(a, metro, start_areas)
        # Seaplane bases are few (floatplanes need them) and are only spaced from each other.
        if a.get('surf') == 'W' or a['kind'] == 'W':
            crowded = any(o.get('surf') == 'W' or o['kind'] == 'W' for o in _near(grid, 2, a, radius))
        else:
            crowded = a['code'] not in PROTECTED and any(True for _ in _near(grid, 2, a, radius))
        if crowded:
            retired.append(a)
        else:
            kept.append(a)
            grid[(int(a['lat'] // 2), int(a['lon'] // 2))].append(a)
    order = {a['code']: i for i, a in enumerate(airports)}
    kept.sort(key=lambda a: order[a['code']])
    retired.sort(key=lambda a: order[a['code']])
    return kept, retired
