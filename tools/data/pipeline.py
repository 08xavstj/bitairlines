"""The airport pipeline in one place, so the Swift data build and the economy prototypes always use the same airports.

    airports = pipeline.build_airports(raw_dir)     # curated, with catchment populations and labels
"""
import os

from . import airports, curate, populations


def build_airports(raw_dir):
    cities = os.path.join(raw_dir, 'cities500.txt')
    selected = airports.load(os.path.join(raw_dir, 'airports.csv'), os.path.join(raw_dir, 'runways.csv'))
    populations.assign(selected, cities)            # a first estimate, to tell cities from small towns
    selected = curate.curate(selected, cities)      # communities only, one airport per city or town
    populations.assign(selected, cities)            # again, so each city's people belong to the airport that stays
    curate.add_labels(selected)
    return selected
