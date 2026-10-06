"""Catchment population per airport from GeoNames places (CC BY 4.0, credit in the app).

Every place with people is split between the airports within REACH_KM, weighted by airport size and nearness, so a metro with five
airports shares its people between them instead of counting them five times, and a village near a bush strip belongs to the strip.
"""
import math

REACH_KM = 150.0
# How far people will travel to an airport of each kind (km): a bush strip serves its own community, a big hub a whole region.
REACH_BY_KIND = {'L': 150.0, 'M': 90.0, 'S': 40.0, 'W': 40.0}
SOFTEN_KM = 15.0
SIZE = {'L': 8.0, 'M': 3.0, 'S': 1.0, 'W': 0.7}
UNSCHEDULED_FACTOR = 0.4
MIN_POP = 150
CELL = 2.0


def _km(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(min(1.0, math.sqrt(a)))


def assign(airports, places_path):
    grid = {}
    for i, a in enumerate(airports):
        grid.setdefault((int(a['lat'] // CELL), int(a['lon'] // CELL)), []).append(i)
    weight = [SIZE[a['kind']] * (1.0 if a['sched'] else UNSCHEDULED_FACTOR) for a in airports]
    totals = [0.0] * len(airports)

    with open(places_path, encoding='utf-8') as f:
        for line in f:
            cols = line.split('\t')
            try:
                pop = int(cols[14])
            except (ValueError, IndexError):
                continue
            if pop <= 0:
                continue
            lat, lon = float(cols[4]), float(cols[5])
            span_lat = int(math.ceil(REACH_KM / 111.0 / CELL))
            span_lon = int(math.ceil(REACH_KM / (111.0 * max(0.2, math.cos(math.radians(lat)))) / CELL))
            gy, gx = int(lat // CELL), int(lon // CELL)
            near = []
            for dy in range(-span_lat, span_lat + 1):
                for dx in range(-span_lon, span_lon + 1):
                    for i in grid.get((gy + dy, gx + dx), ()):
                        a = airports[i]
                        d = _km(lat, lon, a['lat'], a['lon'])
                        if d <= REACH_BY_KIND[a['kind']]:
                            near.append((i, weight[i] / (d + SOFTEN_KM) ** 2))
            if not near:
                continue
            s = sum(w for _, w in near)
            for i, w in near:
                totals[i] += pop * w / s

    for a, t in zip(airports, totals):
        a['pop'] = max(MIN_POP, int(round(t)))
