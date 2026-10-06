"""Selects the playable airports from OurAirports (public domain) and turns each into a plain record.

Rule: every airport with scheduled service, plus unscheduled airports that have an IATA code and are real bush or
regional destinations (remote-flying countries, Alaska, or medium and large fields).
"""
import csv
import re
import unicodedata

from . import countries

BASE_TYPES = {'small_airport', 'medium_airport', 'large_airport', 'seaplane_base'}
KIND = {'large_airport': 'L', 'medium_airport': 'M', 'small_airport': 'S', 'seaplane_base': 'W'}
# Countries where bush strips without scheduled service still make good destinations (Twin Otter country).
BUSH_COUNTRIES = {'CA', 'GL', 'PG', 'NO', 'SE', 'FI', 'IS', 'FO', 'AU', 'RU', 'BR', 'ID', 'CL', 'AR', 'NZ', 'MN', 'KZ', 'NP', 'BT', 'PE', 'CO'}
MILITARY = re.compile(r'air force base|air base|naval|army|marine corps|air station|afb\b|\bnas\b|military', re.I)
JUNK = re.compile(r'duplicate|closed|unused|decommission|abandoned|deleted', re.I)
PAVED = ('ASP', 'CON', 'PEM', 'BIT', 'TAR', 'PAV', 'MAC', 'COP')
WATER = ('WATER', 'WTR')
MIN_BUSH_RUNWAY_FT = 1500
DEFAULT_RUNWAY_FT = {'L': 9000, 'M': 6000, 'S': 3000, 'W': 0}


def ascii_text(text):
    """The pixel font is ASCII only: strip accents, drop anything left, and keep the field separator out of names."""
    folded = unicodedata.normalize('NFKD', text or '')
    plain = ''.join(c for c in folded if ord(c) < 128).replace('|', '-').replace('"', "'").replace(chr(92), '/').strip()
    return re.sub(r'\s+', ' ', plain)


def load_runways(path):
    """Longest open runway per airport: {ident: (length_ft, surface_class)} with surface P (paved), G (gravel or grass) or W (water)."""
    best = {}
    with open(path, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if r['closed'] == '1':
                continue
            try:
                length = int(float(r['length_ft'] or 0))
            except ValueError:
                length = 0
            surface = (r['surface'] or '').upper()
            if any(w in surface for w in WATER):
                cls = 'W'
            elif any(p in surface for p in PAVED):
                cls = 'P'
            elif surface:
                cls = 'G'
            else:
                cls = '?'
            if length > best.get(r['airport_ident'], (0, '?'))[0]:
                best[r['airport_ident']] = (length, cls)
    return best


def wanted(r):
    if r['type'] not in BASE_TYPES or r['iso_country'] in countries.EXCLUDED:
        return False
    if JUNK.search(r['name']) or not (r['iata_code'] or r['icao_code']):
        return False                      # marked duplicate or closed, or no real airport code (local identifiers like CA-0732)
    if r['scheduled_service'] == 'yes':
        return True
    if not r['iata_code'] or not r['municipality'] or MILITARY.search(r['name']):
        return False
    bush = r['iso_country'] in BUSH_COUNTRIES or r['iso_region'] == 'US-AK'
    return bush or r['type'] in ('medium_airport', 'large_airport')


def load(airports_csv, runways_csv):
    runways = load_runways(runways_csv)
    out, seen = [], set()
    with open(airports_csv, encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if not wanted(r):
                continue
            kind = KIND[r['type']]
            length, surface = runways.get(r['ident'], (0, '?'))
            if kind == 'W':
                surface = 'W'
            if surface == '?':
                surface = 'P' if kind in ('L', 'M') and length >= 4000 else 'G' if kind != 'W' else 'W'
            if length == 0 and kind != 'W':
                length = DEFAULT_RUNWAY_FT[kind]
            if r['scheduled_service'] != 'yes' and kind != 'W' and length < MIN_BUSH_RUNWAY_FT:
                continue
            code = r['iata_code'] or r['ident']
            if code in seen:
                continue
            seen.add(code)
            name = ascii_text(r['name']) or code
            city = ascii_text(r['municipality']) or name
            out.append({
                'code': code, 'icao': r['icao_code'] or r['ident'], 'name': name, 'city': city,
                'cc': r['iso_country'], 'region': r['iso_region'].split('-')[-1],
                'lat': float(r['latitude_deg']), 'lon': float(r['longitude_deg']),
                'elev': int(float(r['elevation_ft'])) if r['elevation_ft'] else 0,
                'rwy': length, 'surf': surface, 'kind': kind,
                'sched': 1 if r['scheduled_service'] == 'yes' else 0, 'pop': 0,
            })
    return out
