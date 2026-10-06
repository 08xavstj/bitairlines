#!/usr/bin/env python3
"""Builds the generated Swift data files in AirlineCore/Sources/CoreCatalog/Data from the raw downloads in data/raw.

    python tools/build_data.py

Inputs (see tools/README.md for where to download them): data/raw/airports.csv, runways.csv (OurAirports),
cities500.txt (GeoNames), ne_50m_land.shp (Natural Earth). Output files are committed; the raw inputs are not.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from data import countries, emit_swift, landmask, pipeline  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RAW = os.path.join(ROOT, 'data', 'raw')
OUT = os.path.join(ROOT, 'AirlineCore', 'Sources', 'CoreCatalog')


def main():
    table = countries.load()
    selected = pipeline.build_airports(RAW)
    unknown = sorted({a['cc'] for a in selected} - set(table))
    if unknown:
        sys.exit(f'countries missing from tools/data/countries.py: {unknown}')
    mask_rows = landmask.encode(landmask.rasterise(os.path.join(RAW, 'ne_50m_land.shp')))
    counts = emit_swift.emit(OUT, selected, table, mask_rows, (landmask.WIDTH, landmask.HEIGHT))
    print(f'{len(selected)} airports in {len({a["cc"] for a in selected})} countries; per group: {counts}')
    print(f'land mask {landmask.WIDTH}x{landmask.HEIGHT}, {sum(len(r) for r in mask_rows)} bytes')


if __name__ == '__main__':
    main()
