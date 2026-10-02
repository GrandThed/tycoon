"""Helpers for the Valley generator (tools/world/valley.py): seeded noise, polylines, a Delaunay
triangulation, a triangle locator, a coloured-triangle builder and the GLB writer.

Stdlib only and deterministic: no hash() of strings, no unordered iteration, no clock.

Frames. Everything here works in the generator's MAP frame: x, y on the ground and h up, with
(x, y, h) = Roblox (X, -Z, Y) -- the Blender frame of the mock it was written from. `to_gltf`
is the one place that turns it into the glTF/Roblox frame (X, Y, Z) = (x, h, -y). That is a
rotation, not a mirror, so a triangle that is counter-clockwise seen from outside stays so.
"""

from __future__ import annotations

import hashlib
import math
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "assets"))
import glbtools  # noqa: E402  (read-only use: the GLB container writer and the importer checks)

TAU = math.tau


# ---------------------------------------------------------------- small maths


def smoothstep(e0, e1, x):
    if e0 == e1:
        return 0.0 if x < e0 else 1.0
    t = (x - e0) / (e1 - e0)
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c0, c1, t):
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return (c0[0] + (c1[0] - c0[0]) * t, c0[1] + (c1[1] - c0[1]) * t, c0[2] + (c1[2] - c0[2]) * t)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = 0.0 if c < 0.0 else 1.0 if c > 1.0 else c
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def lin(rgb):
    """An sRGB 0..255 colour as linear 0..1 (colours are blended in linear light, as the mock did)."""
    return tuple(srgb_to_linear(v / 255.0) for v in rgb[:3])


def polar(r, a):
    return (r * math.cos(a), r * math.sin(a))


def hash01(*values):
    """A cheap deterministic 0..1 hash of a few numbers (the mock's)."""
    h = 0.0
    for i, v in enumerate(values):
        h += v * (12.9898 + 78.233 * i)
    s = math.sin(h) * 43758.5453
    return s - math.floor(s)


# ---------------------------------------------------------------- noise


class Noise:
    """2D gradient noise from a seeded permutation, about -1..1."""

    def __init__(self, seed):
        rng = random.Random(seed)
        perm = list(range(256))
        rng.shuffle(perm)
        self.perm = perm + perm
        self.grads = [(math.cos(k / 16 * TAU), math.sin(k / 16 * TAU)) for k in range(16)]

    def noise(self, x, y):
        xi, yi = math.floor(x), math.floor(y)
        xf, yf = x - xi, y - yi
        xi &= 255
        yi &= 255
        perm, grads = self.perm, self.grads
        u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
        v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
        a, b = perm[xi] + yi, perm[xi + 1] + yi
        g = grads[perm[a] & 15]
        n00 = g[0] * xf + g[1] * yf
        g = grads[perm[b] & 15]
        n10 = g[0] * (xf - 1) + g[1] * yf
        g = grads[perm[a + 1] & 15]
        n01 = g[0] * xf + g[1] * (yf - 1)
        g = grads[perm[b + 1] & 15]
        n11 = g[0] * (xf - 1) + g[1] * (yf - 1)
        nx0 = n00 + (n10 - n00) * u
        nx1 = n01 + (n11 - n01) * u
        return (nx0 + (nx1 - nx0) * v) * 1.5

    def n2(self, x, y, seed=0.0):
        """One decorrelated field per `seed` (the mock passed it as a third coordinate)."""
        return self.noise(x + seed * 19.19 + 7.3, y - seed * 7.77 + 3.1)

    def fbm(self, x, y, seed=0.0, octaves=3):
        total, amp, freq, norm = 0.0, 1.0, 1.0, 0.0
        for i in range(octaves):
            total += amp * self.n2(x * freq, y * freq, seed + 17.3 * i)
            norm += amp
            amp *= 0.5
            freq *= 2.03
        value = total / norm * 1.6
        return -1.0 if value < -1.0 else 1.0 if value > 1.0 else value

    def ridge(self, x, y, seed=0.0):
        return 1.0 - min(1.0, abs(self.n2(x, y, seed)) * 2.2)


# ---------------------------------------------------------------- polylines


def catmull(points, step=4.0):
    """Catmull-Rom through (x, y, *extra) control points, resampled about every `step` studs."""
    if len(points) < 2:
        return list(points)
    pts = [points[0]] + list(points) + [points[-1]]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[i + 1], pts[i + 2]
        length = math.dist(p1[:2], p2[:2])
        count = max(1, int(round(length / step)))
        for k in range(count):
            t = k / count
            t2, t3 = t * t, t * t * t
            out.append(
                tuple(
                    0.5
                    * (
                        2 * p1[c]
                        + (-p0[c] + p2[c]) * t
                        + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
                        + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3
                    )
                    for c in range(len(p1))
                )
            )
    out.append(tuple(points[-1]))
    return out


class Line:
    """A sampled polyline with a width per sample and fast distance queries."""

    CELL = 48.0

    def __init__(self, samples, reach=None):
        self.pts = [(p[0], p[1]) for p in samples]
        self.w = [p[2] if len(p) > 2 else 0.0 for p in samples]
        self.s = [0.0]
        for i in range(1, len(self.pts)):
            self.s.append(self.s[-1] + math.dist(self.pts[i - 1], self.pts[i]))
        self.length = self.s[-1]
        self.grid = {}
        reach = reach if reach is not None else max(self.w) / 2 + 60.0
        self.reach = reach
        cell = self.CELL
        for i in range(len(self.pts) - 1):
            a, b = self.pts[i], self.pts[i + 1]
            x0, x1 = min(a[0], b[0]) - reach, max(a[0], b[0]) + reach
            y0, y1 = min(a[1], b[1]) - reach, max(a[1], b[1]) + reach
            for gx in range(int(math.floor(x0 / cell)), int(math.floor(x1 / cell)) + 1):
                for gy in range(int(math.floor(y0 / cell)), int(math.floor(y1 / cell)) + 1):
                    self.grid.setdefault((gx, gy), []).append(i)

    def query(self, x, y):
        """(distance, width there, arc length there); distance is huge when beyond `reach`."""
        ids = self.grid.get((int(math.floor(x / self.CELL)), int(math.floor(y / self.CELL))))
        if not ids:
            return 1e9, 0.0, 0.0
        best_d, best_w, best_s = 1e9, 0.0, 0.0
        pts, ws, ss = self.pts, self.w, self.s
        for i in ids:
            ax, ay = pts[i]
            bx, by = pts[i + 1]
            dx, dy = bx - ax, by - ay
            ll = dx * dx + dy * dy
            t = 0.0 if ll == 0 else ((x - ax) * dx + (y - ay) * dy) / ll
            t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
            d = math.hypot(x - ax - dx * t, y - ay - dy * t)
            if d < best_d:
                best_d = d
                best_w = ws[i] + (ws[i + 1] - ws[i]) * t
                best_s = ss[i] + (ss[i + 1] - ss[i]) * t
        return best_d, best_w, best_s

    def dist(self, x, y):
        return self.query(x, y)[0]

    def tangent(self, i):
        a = self.pts[max(i - 1, 0)]
        b = self.pts[min(i + 1, len(self.pts) - 1)]
        length = math.dist(a, b) or 1.0
        return ((b[0] - a[0]) / length, (b[1] - a[1]) / length)

    def at(self, s):
        """Point and tangent at arc length s."""
        s = max(0.0, min(self.length, s))
        for i in range(1, len(self.s)):
            if self.s[i] >= s:
                t = (s - self.s[i - 1]) / ((self.s[i] - self.s[i - 1]) or 1.0)
                a, b = self.pts[i - 1], self.pts[i]
                return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t), self.tangent(i)
        return self.pts[-1], self.tangent(len(self.pts) - 1)


def wobble_widths(samples, amount, wavelength, seed):
    """Widths with the irregular edge of the game's baked paths (three sines along the arc)."""
    out = []
    s = 0.0
    for i, p in enumerate(samples):
        if i:
            s += math.dist(p[:2], samples[i - 1][:2])
        k = (
            math.sin(s / wavelength * TAU + seed)
            + 0.6 * math.sin(s / (wavelength * 0.43) * TAU + seed * 2.1)
            + 0.4 * math.sin(s / (wavelength * 0.19) * TAU + seed * 3.7)
        ) / 2.0
        out.append(p[2] + amount * k)
    return out


# ---------------------------------------------------------------- Delaunay


class Delaunay:
    """Incremental Bowyer-Watson with walking point location.

    Points must be distinct. Feed them in a spatially coherent order (see `spatial_order`) and
    an insertion costs a short walk plus a handful of in-circle tests."""

    def __init__(self, bounds):
        x0, y0, x1, y1 = bounds
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        span = max(x1 - x0, y1 - y0) * 20.0 + 1.0
        self.pts = [(cx - span, cy - span), (cx + span, cy - span), (cx, cy + span)]
        self.tv = [[0, 1, 2]]
        self.tn = [[-1, -1, -1]]
        self.alive = [True]
        self.free = []
        self.last = 0

    def locate(self, x, y):
        pts, tv, tn = self.pts, self.tv, self.tn
        t = self.last
        for _ in range(len(tv) + 8):
            a, b, c = tv[t]
            ax, ay = pts[a]
            bx, by = pts[b]
            cx, cy = pts[c]
            if (bx - ax) * (y - ay) - (by - ay) * (x - ax) < 0:
                t = tn[t][2]
            elif (cx - bx) * (y - by) - (cy - by) * (x - bx) < 0:
                t = tn[t][0]
            elif (ax - cx) * (y - cy) - (ay - cy) * (x - cx) < 0:
                t = tn[t][1]
            else:
                return t
        raise RuntimeError("delaunay: the walk did not end")

    def in_circle(self, t, x, y):
        pts = self.pts
        a, b, c = self.tv[t]
        ax, ay = pts[a][0] - x, pts[a][1] - y
        bx, by = pts[b][0] - x, pts[b][1] - y
        cx, cy = pts[c][0] - x, pts[c][1] - y
        return (
            (ax * ax + ay * ay) * (bx * cy - cx * by)
            - (bx * bx + by * by) * (ax * cy - cx * ay)
            + (cx * cx + cy * cy) * (ax * by - bx * ay)
        ) > 0.0

    def insert(self, x, y):
        pts, tv, tn, alive = self.pts, self.tv, self.tn, self.alive
        p = len(pts)
        pts.append((x, y))
        start = self.locate(x, y)
        cavity = {start}
        stack = [start]
        while stack:
            t = stack.pop()
            for n in tn[t]:
                if n != -1 and n not in cavity and self.in_circle(n, x, y):
                    cavity.add(n)
                    stack.append(n)
        edges = []
        for t in sorted(cavity):
            v, nb = tv[t], tn[t]
            for i in range(3):
                n = nb[i]
                if n == -1 or n not in cavity:
                    edges.append((v[(i + 1) % 3], v[(i + 2) % 3], n, t))
        for t in sorted(cavity):
            alive[t] = False
        by_a, by_b, made = {}, {}, []
        for a, b, n, old in edges:
            if self.free:
                nt = self.free.pop()
                tv[nt] = [p, a, b]
                tn[nt] = [n, -1, -1]
                alive[nt] = True
            else:
                nt = len(tv)
                tv.append([p, a, b])
                tn.append([n, -1, -1])
                alive.append(True)
            if n != -1:
                other = tn[n]
                other[other.index(old)] = nt
            by_a[a] = nt
            by_b[b] = nt
            made.append((nt, a, b))
        for nt, a, b in made:
            tn[nt][1] = by_a[b]
            tn[nt][2] = by_b[a]
        # Only now may the cavity's slots be reused: while the new triangles were being linked, an
        # outside neighbour still named its old cavity triangle by that slot.
        self.free.extend(sorted(cavity))
        self.last = made[0][0]
        return p

    def triangles(self):
        """Counter-clockwise triangles as indices into the points given to `insert` (0-based)."""
        out = []
        for t, v in enumerate(self.tv):
            if self.alive[t] and v[0] > 2 and v[1] > 2 and v[2] > 2:
                out.append((v[0] - 3, v[1] - 3, v[2] - 3))
        return out


def spatial_order(points, cell):
    """Indices of `points` in a boustrophedon sweep of a grid: neighbours in the order are near."""
    keyed = []
    for i, (x, y) in enumerate(points):
        gx, gy = int(math.floor(x / cell)), int(math.floor(y / cell))
        keyed.append((gy, gx if gy % 2 == 0 else -gx, x if gy % 2 == 0 else -x, y, i))
    keyed.sort()
    return [k[-1] for k in keyed]


def triangulate(points, segments=(), rounds=5):
    """Delaunay of distinct 2D points that also contains every constraint `segment` (index pairs)
    that it can: a missing segment is split at its midpoint and tried again. Returns
    (points incl. the added midpoints, triangles, segments still missing)."""
    pts = list(points)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    tri = Delaunay((min(xs), min(ys), max(xs), max(ys)))
    for i in spatial_order(pts, 48.0):
        tri.insert(pts[i][0], pts[i][1])
    # insert() numbered the points in sweep order; map back to the caller's indices
    order = spatial_order(pts, 48.0)
    where = [0] * len(pts)
    for position, i in enumerate(order):
        where[i] = position
    sweep_pts = [pts[i] for i in order]
    segs = [(where[a], where[b]) for a, b in segments]
    missing = []
    for _ in range(rounds):
        edges = set()
        for a, b, c in tri.triangles():
            edges.add((a, b) if a < b else (b, a))
            edges.add((b, c) if b < c else (c, b))
            edges.add((a, c) if a < c else (c, a))
        missing = [s for s in segs if ((s[0], s[1]) if s[0] < s[1] else (s[1], s[0])) not in edges]
        if not missing:
            break
        gone = set(missing)
        segs = [s for s in segs if s not in gone]
        for a, b in missing:
            ax, ay = sweep_pts[a]
            bx, by = sweep_pts[b]
            if (ax - bx) ** 2 + (ay - by) ** 2 < 0.04:
                continue  # a crossing: two constraints cannot both hold, stop splitting
            m = len(sweep_pts)
            sweep_pts.append(((ax + bx) / 2, (ay + by) / 2))
            tri.insert(*sweep_pts[m])
            segs.append((a, m))
            segs.append((m, b))
    # back to the caller's numbering: originals keep their index, midpoints follow
    back = list(order) + list(range(len(pts), len(sweep_pts)))
    out_pts = pts + sweep_pts[len(pts):]
    tris = [(back[a], back[b], back[c]) for a, b, c in tri.triangles()]
    tris.sort()
    return out_pts, tris, len(missing)


# ---------------------------------------------------------------- triangle locator


class Locator:
    """Height and up-ness of a triangulated surface under a map point."""

    def __init__(self, verts, tris, cell=24.0):
        self.verts, self.tris, self.cell = verts, tris, cell
        self.grid = {}
        for index, (a, b, c) in enumerate(tris):
            xs = (verts[a][0], verts[b][0], verts[c][0])
            ys = (verts[a][1], verts[b][1], verts[c][1])
            for gx in range(int(math.floor(min(xs) / cell)), int(math.floor(max(xs) / cell)) + 1):
                for gy in range(int(math.floor(min(ys) / cell)), int(math.floor(max(ys) / cell)) + 1):
                    self.grid.setdefault((gx, gy), []).append(index)

    def sample(self, x, y):
        """(h, nz) of the face under (x, y), or None outside the surface."""
        ids = self.grid.get((int(math.floor(x / self.cell)), int(math.floor(y / self.cell))))
        if not ids:
            return None
        verts = self.verts
        for index in ids:
            a, b, c = self.tris[index]
            ax, ay, ah = verts[a]
            bx, by, bh = verts[b]
            cx, cy, ch = verts[c]
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if det == 0:
                continue
            l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / det
            l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / det
            l3 = 1 - l1 - l2
            if l1 < -1e-9 or l2 < -1e-9 or l3 < -1e-9:
                continue
            ux, uy, uh = bx - ax, by - ay, bh - ah
            vx, vy, vh = cx - ax, cy - ay, ch - ah
            nx, ny, nz = uy * vh - uh * vy, uh * vx - ux * vh, ux * vy - uy * vx
            length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            return l1 * ah + l2 * bh + l3 * ch, abs(nz) / length
        return None


# ---------------------------------------------------------------- coloured triangles

ICO_T = (1 + 5**0.5) / 2
ICO_VERTS = [(-1, ICO_T, 0), (1, ICO_T, 0), (-1, -ICO_T, 0), (1, -ICO_T, 0), (0, -1, ICO_T), (0, 1, ICO_T), (0, -1, -ICO_T), (0, 1, -ICO_T), (ICO_T, 0, -1), (ICO_T, 0, 1), (-ICO_T, 0, -1), (-ICO_T, 0, 1)]
ICO_FACES = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
ICO_NORM = math.sqrt(1 + ICO_T * ICO_T)


class Builder:
    """Triangles in the map frame, each with a linear colour. Faces are single-sided: every
    method here winds its triangles counter-clockwise seen from outside."""

    def __init__(self):
        self.tris = []  # (a, b, c, colour)

    def count(self):
        return len(self.tris)

    def raw(self, a, b, c, colour):
        self.tris.append((a, b, c, colour))

    def up(self, a, b, c, colour):
        """A ground face: wound so its normal points up."""
        if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) < 0:
            b, c = c, b
        self.tris.append((a, b, c, colour))

    def out(self, a, b, c, colour, centre):
        """A face of a convex solid: wound so its normal points away from `centre`."""
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        mx = (a[0] + b[0] + c[0]) / 3 - centre[0]
        my = (a[1] + b[1] + c[1]) / 3 - centre[1]
        mz = (a[2] + b[2] + c[2]) / 3 - centre[2]
        if nx * mx + ny * my + nz * mz < 0:
            b, c = c, b
        self.tris.append((a, b, c, colour))

    def toward(self, a, b, c, colour, direction):
        """A face wound so its normal has a positive component along `direction`."""
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        if nx * direction[0] + ny * direction[1] + nz * direction[2] < 0:
            b, c = c, b
        self.tris.append((a, b, c, colour))

    def quad_out(self, a, b, c, d, colour, centre):
        self.out(a, b, c, colour, centre)
        self.out(a, c, d, colour, centre)

    def box(self, centre, size, colour, rot=0.0, top=None, bottom=True):
        """An upright box turned about the vertical; `top` recolours the top face."""
        cx, cy, cz = centre
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        cr, sr = math.cos(rot), math.sin(rot)

        def p(x, y, z):
            return (cx + x * cr - y * sr, cy + x * sr + y * cr, cz + z)

        c = [p(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        self.quad_out(c[1], c[5], c[7], c[3], top or colour, centre)
        if bottom:
            self.quad_out(c[0], c[2], c[6], c[4], colour, centre)
        self.quad_out(c[0], c[4], c[5], c[1], colour, centre)
        self.quad_out(c[2], c[3], c[7], c[6], colour, centre)
        self.quad_out(c[0], c[1], c[3], c[2], colour, centre)
        self.quad_out(c[4], c[6], c[7], c[5], colour, centre)

    def frustum(self, centre, r0, r1, z0, z1, colour, sides=8, rot=0.0, top=True, bottom=False, top_colour=None):
        """A prism, frustum or cone (r1 == 0) on a regular polygon; caps are optional."""
        cx, cy = centre
        mid = (cx, cy, (z0 + z1) / 2)
        ring0 = [(cx + r0 * math.cos(rot + i * TAU / sides), cy + r0 * math.sin(rot + i * TAU / sides), z0) for i in range(sides)]
        if r1 <= 1e-9:
            apex = (cx, cy, z1)
            for i in range(sides):
                self.out(ring0[i], ring0[(i + 1) % sides], apex, colour, mid)
        else:
            ring1 = [(cx + r1 * math.cos(rot + i * TAU / sides), cy + r1 * math.sin(rot + i * TAU / sides), z1) for i in range(sides)]
            for i in range(sides):
                j = (i + 1) % sides
                self.quad_out(ring0[i], ring0[j], ring1[j], ring1[i], colour, mid)
            if top:
                for i in range(1, sides - 1):
                    self.out(ring1[0], ring1[i], ring1[i + 1], top_colour or colour, mid)
        if bottom:
            for i in range(1, sides - 1):
                self.out(ring0[0], ring0[i], ring0[i + 1], colour, mid)

    def blob(self, centre, radii, colour, rot=0.0, jitter=None):
        """A squashed icosahedron; `jitter(k)` scales vertex k's radius (boulders)."""
        cr, sr = math.cos(rot), math.sin(rot)
        pts = []
        for k, (x, y, z) in enumerate(ICO_VERTS):
            s = jitter(k) if jitter else 1.0
            x, y, z = x / ICO_NORM * radii[0] * s, y / ICO_NORM * radii[1] * s, z / ICO_NORM * radii[2] * s
            pts.append((centre[0] + x * cr - y * sr, centre[1] + x * sr + y * cr, centre[2] + z))
        for a, b, c in ICO_FACES:
            self.out(pts[a], pts[b], pts[c], colour, centre)


# ---------------------------------------------------------------- frames and output


def to_gltf(p):
    """Map frame (x, y, h) -> glTF/Roblox (X, Y, Z) = (x, h, -y)."""
    return (p[0], p[2], -p[1])


def quantise(colour, step):
    """A linear colour as an sRGB 0..255 triple snapped to `step`."""
    out = []
    for c in colour:
        v = linear_to_srgb(c) * 255.0
        q = int(math.floor(v / step + 0.5)) * step
        out.append(0 if q < 0 else 255 if q > 255 else q)
    return tuple(out)


def f32(v):
    """A float as it will read back from a float32, so bounds match the stored positions."""
    return struct.unpack("<f", struct.pack("<f", v))[0]


def glb_bytes(name, positions, normals, uvs, generator):
    """One scene, one node, one mesh, one primitive, no material: POSITION, per-face NORMAL,
    TEXCOORD_0 and uint32 indices (three unshared vertices per triangle)."""
    count = len(positions)
    binary = bytearray()
    views = []

    def add_view(blob, target, stride=None):
        while len(binary) % 4:
            binary.append(0)
        view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(blob), "target": target}
        if stride:
            view["byteStride"] = stride
        views.append(view)
        binary.extend(blob)
        return len(views) - 1

    pos = add_view(b"".join(struct.pack("<fff", *v) for v in positions), 34962, 12)
    nrm = add_view(b"".join(struct.pack("<fff", *v) for v in normals), 34962, 12)
    uv = add_view(b"".join(struct.pack("<ff", *v) for v in uvs), 34962, 8)
    idx = add_view(struct.pack(f"<{count}I", *range(count)), 34963)
    while len(binary) % 4:
        binary.append(0)
    lo = [min(f32(v[i]) for v in positions) for i in range(3)]
    hi = [max(f32(v[i]) for v in positions) for i in range(3)]
    doc = {
        "asset": {"version": "2.0", "generator": generator},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3}]}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": pos, "componentType": glbtools.FLOAT, "count": count, "type": "VEC3", "min": lo, "max": hi},
            {"bufferView": nrm, "componentType": glbtools.FLOAT, "count": count, "type": "VEC3"},
            {"bufferView": uv, "componentType": glbtools.FLOAT, "count": count, "type": "VEC2"},
            {"bufferView": idx, "componentType": glbtools.UNSIGNED_INT, "count": count, "type": "SCALAR"},
        ],
        "buffers": [{"byteLength": len(binary)}],
    }
    data = glbtools.write_glb(doc, bytes(binary))
    return data, lo, hi


def sha256(data):
    return hashlib.sha256(data).hexdigest()
