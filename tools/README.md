# Tools

| Script | What |
|---|---|
| `build_data.py` | Rebuilds the generated Swift data files in `AirlineCore/Sources/CoreCatalog/Data/` (airports, countries, land mask) from `data/raw/`. |
| `data/*.py` | The pieces `build_data.py` uses: `airports.py` (which airports are playable), `populations.py` (catchment people), `countries.py` (names, region groups, wealth), `landmask.py` (coastlines), `emit_swift.py` (writes the files). |
| `make_icon.py` | Draws the app icon (needs Pillow). |
| `generate_xcodeproj.rb` | Generates `BitAirlines.xcodeproj` (the project is not committed). |
| `check-core-purity.sh` | Fails if `AirlineCore` uses UI frameworks, system randomness, wall-clock time, libm or similar. |
| `ci_publish_logs.sh` | Used by CI to publish trimmed logs to a branch. |

## Raw data (not committed, re-download into `data/raw/`)

| File | Source | Licence |
|---|---|---|
| `airports.csv`, `runways.csv` | https://davidmegginson.github.io/ourairports-data/ | Public domain (OurAirports) |
| `cities500.txt` (from `cities500.zip`) | https://download.geonames.org/export/dump/cities500.zip | CC BY 4.0, credit GeoNames in the app |
| `ne_50m_land.shp` and friends (from the zip) | https://naciscdn.org/naturalearth/50m/physical/ne_50m_land.zip | Public domain (Natural Earth) |

```bash
python tools/build_data.py     # needs Python 3 and Pillow
```

The generated files are committed, so nobody needs the raw downloads just to build the game.
