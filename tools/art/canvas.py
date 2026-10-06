"""A tiny character canvas for drawing pixel-art aircraft: rectangles, polygons, lines, plus an automatic outline.

Roles (one character per pixel):
  .  empty          k  outline         f  fuselage upper   u  fuselage lower   c  cheat line / window band
  g  glass          t  tail fin        m  fin cap          l  logo cell (inside the fin)
  w  wing / stabiliser top             v  wing shadow      n  engine metal     d  dark detail (gear, props)
"""


class Canvas:
    def __init__(self, width, height):
        self.w, self.h = width, height
        self.px = [['.'] * width for _ in range(height)]

    def set(self, x, y, ch):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = ch

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else '.'

    def rect(self, x0, y0, x1, y1, ch):
        for y in range(min(y0, y1), max(y0, y1) + 1):
            for x in range(min(x0, x1), max(x0, x1) + 1):
                self.set(x, y, ch)

    def hline(self, x0, x1, y, ch):
        self.rect(x0, y, x1, y, ch)

    def poly(self, points, ch):
        """Fills a polygon (integer vertices) with a scanline: a pixel is inside if its centre is."""
        ys = [p[1] for p in points]
        for y in range(min(ys), max(ys) + 1):
            xs = []
            n = len(points)
            for i in range(n):
                (x0, y0), (x1, y1) = points[i], points[(i + 1) % n]
                if y0 == y1:
                    continue
                if min(y0, y1) <= y + 0.5 < max(y0, y1):
                    xs.append(x0 + (y + 0.5 - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                for x in range(int(round(a)), int(round(b))):
                    self.set(x, y, ch)

    def paste_under(self, other, ox=0, oy=0):
        """Draws `other` into empty cells only (so it sits behind what is already here)."""
        for y in range(other.h):
            for x in range(other.w):
                ch = other.px[y][x]
                if ch != '.' and self.get(x + ox, y + oy) == '.':
                    self.set(x + ox, y + oy, ch)

    def outline(self):
        """Adds a one-pixel outline ('k') around everything, growing the picture by one pixel on every side."""
        out = Canvas(self.w + 2, self.h + 2)
        for y in range(self.h):
            for x in range(self.w):
                out.px[y + 1][x + 1] = self.px[y][x]
        for y in range(out.h):
            for x in range(out.w):
                if out.px[y][x] != '.':
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if 0 <= x + dx < out.w and 0 <= y + dy < out.h and out.px[y + dy][x + dx] not in '.k':
                        out.px[y][x] = 'k'
                        break
        return out

    def trim(self):
        rows = [i for i, r in enumerate(self.px) if any(c != '.' for c in r)]
        cols = [i for i in range(self.w) if any(self.px[y][i] != '.' for y in range(self.h))]
        y0, y1, x0, x1 = rows[0], rows[-1], cols[0], cols[-1]
        out = Canvas(x1 - x0 + 1, y1 - y0 + 1)
        for y in range(out.h):
            out.px[y] = self.px[y0 + y][x0:x1 + 1]
        return out

    def lines(self):
        return [''.join(r) for r in self.px]
