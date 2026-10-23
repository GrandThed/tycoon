"""Mesh helpers for the level generators (tools/levels/forest.py): baked level-frame meshes in the
Valley's GLB shape, the level palette texture, rectangle arithmetic, and seeded noise.

Stdlib only and deterministic (no hash() of strings, no unordered iteration, no clock), so two
`forest.py build` runs write byte-identical files.

**Frame.** Everything here is the level frame: Roblox world studs, X and Z on the ground, Y up, the
level built where its layout writes it (LevelService places blocks at their layout coordinates).
A baked GLB is in that frame directly (1 glTF unit = 1 stud, glTF (X, Y, Z) = Roblox (X, Y, Z)),
like the Valley's "world" meshes, so its template is placed with its harvested offset and nothing
else.

**GLB shape** (INTERFACES "Wave 2 — the Valley meshes", unchanged): one scene, one node, one mesh,
one primitive, no material, no image: POSITION, per-face NORMAL, TEXCOORD_0, uint32 indices, three
unshared vertices per triangle. A `palette` mesh maps each face to the centre of its colour's
swatch in the level's palette.png; a `texture` mesh carries world-planar UVs (u = x / tile,
v = z / tile) for a tiling, opaque, two-way seamless ground texture, so two pieces covering the
same ground sample the same texel (the city's C3 recipe).
"""

from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "world"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "assets"))
import forest_palette as fp  # noqa: E402
import palette as kitpalette  # noqa: E402  (read-only use: its stdlib PNG writer)
import wgeom  # noqa: E402  (read-only use: the Valley's noise and GLB writer)

Noise = wgeom.Noise
TRI_LIMIT = 20000  # per mesh (the Valley's hard limit; the importer's comfort zone)
TRI_AIM = 18000
MIN_TRIS = 1500  # a baked piece smaller than this folds into its neighbour (one upload, one Instance less)
SIDE_LIMIT = 1500.0  # every bounding-box side of one mesh
NAME_LIMIT = 24
CELL = 16  # palette swatch, pixels
PALETTE_COLUMNS = 8


# ---------------------------------------------------------------- the level palette


class Palette:
    """Every forest_palette swatch on a grid of CELL-pixel squares, in declaration order. A face's
    UVs all sit at its swatch's centre, so bilinear filtering never bleeds a neighbour in."""

    def __init__(self):
        self.names = list(fp.swatches().keys())
        self.colours = list(fp.swatches().values())
        self.index = {c: i for i, c in enumerate(self.colours)}
        self.columns = PALETTE_COLUMNS
        self.rows = math.ceil(len(self.colours) / self.columns)
        self.width = self.columns * CELL
        self.height = self.rows * CELL

    def uv(self, colour) -> tuple[float, float]:
        i = self.index.get(tuple(colour))
        if i is None:
            raise ValueError(f"colour {colour} is not a forest_palette swatch")
        col, row = i % self.columns, i // self.columns
        return ((col + 0.5) * CELL / self.width, (row + 0.5) * CELL / self.height)

    def write(self, path: str) -> None:
        pixels = [[(0, 0, 0)] * self.width for _ in range(self.height)]
        for i, colour in enumerate(self.colours):
            col, row = i % self.columns, i // self.columns
            for y in range(row * CELL, (row + 1) * CELL):
                for x in range(col * CELL, (col + 1) * CELL):
                    pixels[y][x] = colour
        kitpalette.write_png(path, self.width, self.height, pixels)

    def record(self) -> dict:
        return {
            "cell": CELL,
            "columns": self.columns,
            "rows": self.rows,
            "width": self.width,
            "height": self.height,
            "swatches": [{"name": n, "srgb": list(c), "uv": [round(v, 6) for v in self.uv(c)]} for n, c in zip(self.names, self.colours)],
        }


# ---------------------------------------------------------------- a baked mesh


def tri_normal(a, b, c):
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    return (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)


class Bake:
    """The triangles of one baked mesh. `look` is "palette" (each triangle carries a swatch) or
    "texture" (planar UVs at `tile` studs per repeat; the texture is named, not embedded)."""

    def __init__(self, name: str, look: str, texture: str | None = None, tile: float = 16.0, group: str = ""):
        if look not in ("palette", "texture"):
            raise ValueError(look)
        self.name = name
        self.look = look
        self.texture = texture
        self.tile = tile
        self.group = group
        self.tris: list[tuple] = []  # (a, b, c, colour or None)

    def count(self) -> int:
        return len(self.tris)

    def tri(self, a, b, c, colour=None) -> None:
        """A triangle already wound counter-clockwise seen from its front."""
        if self.look == "palette" and colour is None:
            raise ValueError(f"{self.name}: a palette triangle needs a colour")
        self.tris.append((a, b, c, colour))

    def up(self, a, b, c, colour=None) -> None:
        """A ground face, wound so its normal points up."""
        if tri_normal(a, b, c)[1] < 0:
            b, c = c, b
        self.tri(a, b, c, colour)

    def toward(self, a, b, c, colour, direction) -> None:
        n = tri_normal(a, b, c)
        if n[0] * direction[0] + n[1] * direction[1] + n[2] * direction[2] < 0:
            b, c = c, b
        self.tri(a, b, c, colour)

    def extend(self, tris) -> None:
        for a, b, c, colour in tris:
            self.tri(a, b, c, colour)

    def bounds(self):
        lo = [math.inf] * 3
        hi = [-math.inf] * 3
        for t in self.tris:
            for p in t[:3]:
                for i in range(3):
                    lo[i] = min(lo[i], p[i])
                    hi[i] = max(hi[i], p[i])
        return lo, hi

    def glb(self, palette: Palette, generator: str) -> tuple[bytes, list, list]:
        positions, normals, uvs = [], [], []
        tris = list(self.tris)
        lo, hi = self.bounds()
        if tris and hi[1] - lo[1] < 0.01:
            # A flat sheet gets a hair of height (the importer rejects a zero-height bounding
            # box): one corner of its first triangle rises 0.01, a tilt no eye can see.
            a, b, c, colour = tris[0]
            tris[0] = (a, b, (c[0], c[1] + 0.01, c[2]), colour)
        for a, b, c, colour in tris:
            n = tri_normal(a, b, c)
            length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) or 1.0
            n = (n[0] / length, n[1] / length, n[2] / length)
            for p in (a, b, c):
                positions.append(p)
                normals.append(n)
                if self.look == "palette":
                    uvs.append(palette.uv(colour))
                else:
                    uvs.append((p[0] / self.tile, p[2] / self.tile))
        return wgeom.glb_bytes(self.name, positions, normals, uvs, generator)

    def problems(self) -> list[str]:
        out = []
        if self.count() > TRI_LIMIT:
            out.append(f"{self.name}: {self.count()} triangles over {TRI_LIMIT}")
        if len(self.name) > NAME_LIMIT or not all(ch.isalnum() or ch == "_" for ch in self.name):
            out.append(f"{self.name}: a mesh name is [A-Za-z0-9_], at most {NAME_LIMIT} characters")
        if self.tris:
            lo, hi = self.bounds()
            for i in range(3):
                if hi[i] - lo[i] > SIDE_LIMIT:
                    out.append(f"{self.name}: a bounding box side of {hi[i] - lo[i]:.0f} studs")
                if hi[i] - lo[i] < 1e-3 and i != 1:
                    out.append(f"{self.name}: a zero-width bounding box side (the importer rejects it)")
        return out


def split_by_cells(name: str, look: str, tris, cell: float, texture=None, tile=16.0, group="", aim=TRI_AIM) -> list[Bake]:
    """Triangles into meshes by the cell of their centroid (so a mesh is a compact area the
    engine can cull), each cell split again in halves while it holds more than `aim`."""
    buckets: dict[tuple[int, int], list] = {}
    for t in tris:
        cx = (t[0][0] + t[1][0] + t[2][0]) / 3
        cz = (t[0][2] + t[1][2] + t[2][2]) / 3
        buckets.setdefault((math.floor(cx / cell), math.floor(cz / cell)), []).append(t)
    pieces: list[list] = []
    for key in sorted(buckets):
        stack = [buckets[key]]
        while stack:
            part = stack.pop()
            if len(part) <= aim:
                pieces.append(part)
                continue
            xs = sorted((t[0][0] + t[1][0] + t[2][0]) / 3 for t in part)
            zs = sorted((t[0][2] + t[1][2] + t[2][2]) / 3 for t in part)
            axis = 0 if xs[-1] - xs[0] >= zs[-1] - zs[0] else 2
            part = sorted(part, key=lambda t: (t[0][axis] + t[1][axis] + t[2][axis]) / 3)
            half = len(part) // 2
            stack.append(part[half:])
            stack.append(part[:half])
    # A sliver of a cell is not worth an upload and an Instance: fold every piece under MIN_TRIS
    # into its nearest neighbour while the two stay under `aim`.
    def centre(part):
        n = 3 * len(part)
        return (sum(p[0] for t in part for p in t[:3]) / n, sum(p[2] for t in part for p in t[:3]) / n)

    def span(part):
        xs = [p[0] for t in part for p in t[:3]]
        zs = [p[2] for t in part for p in t[:3]]
        return max(max(xs) - min(xs), max(zs) - min(zs))

    merged = True
    while merged and len(pieces) > 1:
        merged = False
        pieces.sort(key=len)
        small = pieces[0]
        if len(small) >= MIN_TRIS:
            break
        cx, cz = centre(small)
        best = None
        for k in range(1, len(pieces)):
            if len(pieces[k]) + len(small) > aim or span(pieces[k] + small) > SIDE_LIMIT:
                continue
            ox, oz = centre(pieces[k])
            d = (ox - cx) ** 2 + (oz - cz) ** 2
            if best is None or d < best[0]:
                best = (d, k)
        if best is not None:
            pieces[best[1]] = pieces[best[1]] + small
            pieces.pop(0)
            merged = True
    pieces.sort(key=lambda part: centre(part))
    out = []
    for k, part in enumerate(pieces):
        bake = Bake(f"{name}_{k + 1}" if len(pieces) > 1 else name, look, texture, tile, group)
        bake.extend(part)
        out.append(bake)
    return out


# ---------------------------------------------------------------- rectangles


class Rect:
    """An axis-aligned rectangle on the ground, x0 < x1, z0 < z1."""

    __slots__ = ("x0", "x1", "z0", "z1")

    def __init__(self, x0, x1, z0, z1):
        self.x0, self.x1, self.z0, self.z1 = x0, x1, z0, z1

    @staticmethod
    def of(box) -> "Rect":
        return Rect(box["x"] - box["sx"] / 2, box["x"] + box["sx"] / 2, box["z"] - box["sz"] / 2, box["z"] + box["sz"] / 2)

    def grown(self, d) -> "Rect":
        return Rect(self.x0 - d, self.x1 + d, self.z0 - d, self.z1 + d)

    def contains(self, x, z, eps=0.0) -> bool:
        return self.x0 - eps <= x <= self.x1 + eps and self.z0 - eps <= z <= self.z1 + eps

    def overlaps(self, other, eps=0.0) -> bool:
        return self.x0 < other.x1 - eps and other.x0 < self.x1 - eps and self.z0 < other.z1 - eps and other.z0 < self.z1 - eps

    def distance(self, x, z) -> float:
        dx = max(self.x0 - x, 0.0, x - self.x1)
        dz = max(self.z0 - z, 0.0, z - self.z1)
        return math.sqrt(dx * dx + dz * dz)

    def signed(self, x, z) -> float:
        """Negative inside (minus the depth to the nearest edge), positive outside."""
        if self.contains(x, z):
            return -min(x - self.x0, self.x1 - x, z - self.z0, self.z1 - z)
        return self.distance(x, z)

    def area(self) -> float:
        return max(0.0, self.x1 - self.x0) * max(0.0, self.z1 - self.z0)

    def as_list(self):
        return [round(self.x0, 4), round(self.x1, 4), round(self.z0, 4), round(self.z1, 4)]

    def __repr__(self):
        return f"Rect({self.x0}, {self.x1}, {self.z0}, {self.z1})"


def subtract_intervals(lo: float, hi: float, cuts: list[tuple[float, float]], eps: float = 1e-6) -> list[tuple[float, float]]:
    """[lo, hi] minus the union of `cuts`, as sorted disjoint intervals longer than eps."""
    out = []
    cursor = lo
    for a, b in sorted(cuts):
        if b <= cursor + eps:
            continue
        if a > cursor + eps:
            out.append((cursor, min(a, hi)))
        cursor = max(cursor, b)
        if cursor >= hi - eps:
            break
    if cursor < hi - eps:
        out.append((cursor, hi))
    return [(a, b) for a, b in out if b - a > eps]


def subtract_rects(base: tuple[float, float, float, float], cuts: list[tuple[float, float, float, float]]) -> list[tuple[float, float, float, float]]:
    """A rectangle (u0, u1, v0, v1) minus a list of rectangles, as disjoint rectangles."""
    pieces = [base]
    for cu0, cu1, cv0, cv1 in cuts:
        nxt = []
        for u0, u1, v0, v1 in pieces:
            if cu0 >= u1 - 1e-6 or cu1 <= u0 + 1e-6 or cv0 >= v1 - 1e-6 or cv1 <= v0 + 1e-6:
                nxt.append((u0, u1, v0, v1))
                continue
            if cu0 > u0:
                nxt.append((u0, cu0, v0, v1))
            if cu1 < u1:
                nxt.append((cu1, u1, v0, v1))
            iu0, iu1 = max(u0, cu0), min(u1, cu1)
            if cv0 > v0:
                nxt.append((iu0, iu1, v0, cv0))
            if cv1 < v1:
                nxt.append((iu0, iu1, cv1, v1))
        pieces = nxt
    return [p for p in pieces if p[1] - p[0] > 1e-3 and p[3] - p[2] > 1e-3]


# ---------------------------------------------------------------- small maths


def smoothstep(e0, e1, x):
    return wgeom.smoothstep(e0, e1, x)


def lerp(a, b, t):
    return a + (b - a) * t


def hash01(*values) -> float:
    """A deterministic 0..1 from numbers (FNV over rounded values; no hash() of strings)."""
    h = 2166136261
    for v in values:
        q = int(round(v * 1000.0)) & 0xFFFFFFFF
        for shift in (0, 8, 16, 24):
            h ^= (q >> shift) & 0xFF
            h = (h * 16777619) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0x5BD1E995) & 0xFFFFFFFF
    h ^= h >> 15
    return (h & 0xFFFFFF) / float(0x1000000)


def edge_noise(t: float, seed: float) -> float:
    """Smooth 1D noise in about -1..1 along a road's edge: three sines at 3.1-8.3 stud
    wavelengths with seeded phases (the city's recipe, longer waves for a 16-stud road)."""
    total = 0.0
    for k, (wave, amp) in enumerate(((8.3, 0.55), (4.7, 0.3), (3.1, 0.15))):
        phase = hash01(seed, k) * math.tau
        total += amp * math.sin(t * math.tau / wave + phase)
    return total
