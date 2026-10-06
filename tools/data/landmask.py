"""Rasterises Natural Earth 50m land polygons (public domain) into a run-length encoded land/water grid.

Reads the .shp file directly (no GIS library). Output rows run from north (90N) to south, columns from 180W to 180E.
Each row is a space-separated list of run lengths in base 36, alternating water, land, water, ... starting with water.
"""
import struct

from PIL import Image, ImageDraw

WIDTH, HEIGHT = 2880, 1440          # 0.125 degrees per cell


def _read_records(path):
    """Yields one list of rings per polygon record; each ring is a list of (lon, lat)."""
    with open(path, 'rb') as f:
        data = f.read()
    pos = 100
    while pos + 8 <= len(data):
        content_len = struct.unpack('>i', data[pos + 4:pos + 8])[0]
        pos += 8
        end = pos + content_len * 2
        if struct.unpack('<i', data[pos:pos + 4])[0] == 5:
            nparts, npoints = struct.unpack('<ii', data[pos + 36:pos + 44])
            parts = list(struct.unpack('<%di' % nparts, data[pos + 44:pos + 44 + 4 * nparts])) + [npoints]
            off = pos + 44 + 4 * nparts
            flat = struct.unpack('<%dd' % (2 * npoints), data[off:off + 16 * npoints])
            pts = [(flat[2 * i], flat[2 * i + 1]) for i in range(npoints)]
            yield [pts[parts[i]:parts[i + 1]] for i in range(nparts)]
        pos = end


def _signed_area(ring):
    return sum(ring[i][0] * ring[(i + 1) % len(ring)][1] - ring[(i + 1) % len(ring)][0] * ring[i][1] for i in range(len(ring))) / 2


def _to_px(ring):
    return [((lon + 180.0) / 360.0 * WIDTH, (90.0 - lat) / 180.0 * HEIGHT) for lon, lat in ring]


def rasterise(shp_path):
    """Returns a 1-bit image: 1 is land. Exterior rings are clockwise in a shapefile, holes counter-clockwise."""
    land = Image.new('1', (WIDTH, HEIGHT), 0)
    draw = ImageDraw.Draw(land)
    for rings in _read_records(shp_path):
        exteriors = [r for r in rings if _signed_area(r) < 0]
        holes = [r for r in rings if _signed_area(r) >= 0]
        if not holes:
            for r in exteriors:
                draw.polygon(_to_px(r), fill=1)
            continue
        layer = Image.new('1', (WIDTH, HEIGHT), 0)       # holes only erase their own polygon, never a neighbour island
        layer_draw = ImageDraw.Draw(layer)
        for r in exteriors:
            layer_draw.polygon(_to_px(r), fill=1)
        for r in holes:
            layer_draw.polygon(_to_px(r), fill=0)
        land.paste(1, mask=layer)
    return land


def _base36(n):
    digits = '0123456789abcdefghijklmnopqrstuvwxyz'
    if n == 0:
        return '0'
    out = ''
    while n:
        n, r = divmod(n, 36)
        out = digits[r] + out
    return out


def encode(land):
    px = land.load()
    rows = []
    for y in range(HEIGHT):
        runs, current, length = [], 0, 0
        for x in range(WIDTH):
            v = 1 if px[x, y] else 0
            if v == current:
                length += 1
            else:
                runs.append(length)
                current, length = v, 1
        runs.append(length)
        rows.append(' '.join(_base36(n) for n in runs))
    return rows
