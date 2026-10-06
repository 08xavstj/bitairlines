"""Curates the playable airports: communities only, one airport per city or town, each listed by its town name.

Kept: a place people live. That means a real town within LOCAL_KM (GeoNames), or scheduled service with a named municipality (remote hamlets
such as Sachs Harbour have no GeoNames entry but are exactly where bush planes fly). Dropped: lodges, mines, ranches and private strips.
Merged: two airports of one city keep the busier one, and a small town's airfield close to a bigger city's airport is dropped
(the closer to a bigger city, the more is dropped; remote towns are never merged).
"""
import collections
import math
import re

LOCAL_KM = 15.0
JUNK = re.compile(r'\b(lodge|camp|mine|mining|resort|ranch|plantation|oil|gas|rig|offshore|platform|quarry|farm|estate|private|club|aeroclub|glider|gliding|skydiv\w*|heliport|base)\b', re.I)
KIND_RANK = {'L': 3, 'M': 2, 'S': 1, 'W': 0}
# The main airport of a city where the runway count alone would pick a newer or quieter sibling.
PREFERRED = {'MEX', 'DXB', 'PEK', 'CTU', 'IST', 'LHR', 'JFK', 'CDG', 'ORD', 'DFW', 'BKK', 'ICN', 'HND', 'KIX', 'PVG', 'SVO', 'FRA'}


def km(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(min(1.0, math.sqrt(h)))


def load_places(path):
    grid = collections.defaultdict(list)
    with open(path, encoding='utf-8') as f:
        for line in f:
            c = line.split('\t')
            try:
                grid[(int(float(c[4]) // 1), int(float(c[5]) // 1))].append((float(c[4]), float(c[5]), int(c[14] or 0), c[2]))
            except (ValueError, IndexError):
                continue
    return grid


def local_town(grid, lat, lon):
    """The biggest GeoNames place within LOCAL_KM: (population, name), or (0, '')."""
    best = (0, '')
    span_lat = 1
    span_lon = int(math.ceil(LOCAL_KM / (111.0 * max(0.2, math.cos(math.radians(lat)))))) + 1
    for dy in range(-span_lat, span_lat + 1):
        for dx in range(-span_lon, span_lon + 1):
            for plat, plon, pop, name in grid.get((int(lat // 1) + dy, int(lon // 1) + dx), ()):
                if pop > best[0] and km(lat, lon, plat, plon) <= LOCAL_KM:
                    best = (pop, name)
    return best


def clean_city(text):
    """'London, Essex' -> 'London', 'Sydney (Mascot)' -> 'Sydney'."""
    text = re.sub(r'\s*\(.*?\)', '', text or '')
    return text.split(',')[0].split('/')[0].strip()


def rank(a):
    """Which of two airports serving one city stays: scheduled, then bigger kind, then more long runways, then the longest runway."""
    return (a['code'] in PREFERRED, a['sched'], KIND_RANK[a['kind']], a['nrw'], a['rwy'], a['pop'])


def small_town_limit(pop):
    """A town this small, next to a city of this catchment, is a suburb: its airfield is not worth a place of its own."""
    if pop >= 5_000_000:
        return 250_000
    if pop >= 2_000_000:
        return 120_000
    if pop >= 500_000:
        return 60_000
    if pop >= 150_000:
        return 30_000
    return 15_000


def merge_radius_km(pop):
    """How far a small town's airfield counts as part of a city's airport, by the size of the city's catchment."""
    if pop >= 2_000_000:
        return 100.0
    if pop >= 500_000:
        return 70.0
    if pop >= 150_000:
        return 45.0
    if pop >= 40_000:
        return 25.0
    return 0.0


def is_community(a):
    if a['town_pop'] >= 100:
        return True
    return bool(a['sched'] and a['muni'] and not JUNK.search(a['name']))


def is_redundant(a, cells):
    """True if a kept airport already covers this one: the same city, or a small town's airfield near a bigger city."""
    for dy in range(-2, 3):
        for dx in range(-3, 4):
            for k in cells.get((int(a['lat'] // 1) + dy, int(a['lon'] // 1) + dx), ()):
                d = km(a['lat'], a['lon'], k['lat'], k['lon'])
                if d < 100 and k['cc'] == a['cc'] and k['city'].lower() == a['city'].lower():
                    return True
                if d < merge_radius_km(k['pop']) and a['town_pop'] < small_town_limit(k['pop']):
                    return True
    return False


def curate(airports, places_path):
    grid = load_places(places_path)
    for a in airports:
        a['town_pop'], a['town'] = local_town(grid, a['lat'], a['lon'])
        a['city'] = clean_city(a['muni']) or a['town'] or clean_city(a['name'])
    kept = []
    cells = collections.defaultdict(list)
    for a in sorted((x for x in airports if is_community(x)), key=rank, reverse=True):
        if not is_redundant(a, cells):
            kept.append(a)
            cells[(int(a['lat'] // 1), int(a['lon'] // 1))].append(a)
    return kept


def shorten(text, limit=24):
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(' ', 1)[0]
    return cut if len(cut) >= 6 else text[:limit]


def add_labels(airports):
    """label = the city or town name. Where several places share a name, the biggest keeps it plain and the rest add their country,
    or their region when they are in the same country."""
    groups = collections.defaultdict(list)
    for a in airports:
        a['city'] = shorten(a['city'])
        groups[a['city'].lower()].append(a)
    for same in groups.values():
        same.sort(key=lambda a: a['pop'], reverse=True)
        same[0]['label'] = same[0]['city']
        for a in same[1:]:
            countries = {b['cc'] for b in same}
            tag = a['cc'] if len(countries) > 1 and sum(1 for b in same if b['cc'] == a['cc']) == 1 else (a['region'] if a['region'] else a['cc'])
            a['label'] = f"{a['city']}, {tag}"
    seen = collections.Counter(a['label'].lower() for a in airports)
    for a in airports:
        if seen[a['label'].lower()] > 1:
            a['label'] = f"{a['city']}, {a['cc']} {a['code']}"
