"""The Forest Road's generated kit (L4): raider-forest trees, thicket, rocks, the camps' log, rock
and stake edges, hide tents, the Chief's tent, campfires, racks and clutter.

    py tools/assets/forest_kit.py                 # writes every piece + palette-card.glb + pieces.json
    py tools/assets/forest_kit.py --list          # the pieces with triangle counts and sizes, no files
    py tools/assets/forest_kit.py --out <dir>     # somewhere else (a scratch copy)

Writes one GLB per piece into assets/kenney3d/forest-kit/Models/GLB format/, the folder convention
every Kenney kit uses, so testfit, plotscene and merge_stages discover the kit with no registration
step (assets/ is gitignored: this script is the committed artifact). pieces.json beside them lists
each piece's triangles, bounding box and role for tools/levels/forest.py and the contact sheet.

Why generated, and why pure Python. nature-kit has tents, logs and rocks, but in a teal-and-orange
cartoon palette the pipeline cannot recolour, and the Village already wears it; Ben has rejected
every look that resembles another one (MISSIONS_DESIGN section 26: a raider forest, darker and denser,
camps of hide, rope and logs). The level generator bakes most pieces into level-frame meshes, so it
imports the builders below and instances the very triangles this script exports: one geometry,
whether a piece ends up a client prop or part of a baked chunk. No Blender, no numpy: two runs write
byte-identical files.

Art rules: flat shading, faceted low-poly, every closed part a convex primitive wound counter-
clockwise from outside (Roblox culls back faces; a reversed part vanishes from the camera side), and
thin panels (tent hides, banners, fern blades) written twice, once per side, the inner side darker.
Colours only from tools/assets/forest_palette.py (`Mesh` raises on any other).

**Frame** (the blueprint frame of every kit): 1 glTF unit = 1 stud, Y up, a piece's front faces -Z,
origin at its bottom centre. A piece is placed by (x, y, z, yaw, scale) where yaw turns it about +Y
the way CFrame.Angles(0, yaw, 0) does: (x, z) -> (x cos + z sin, -x sin + z cos).

**Heights are rules here** (tools/levels/forest.py checks them again on every placement): a camp
edge piece is at most 4.0 studs tall (Ben's ruling), camp clutter that may stand inside the walking
space at most 4.0, a spawn tent fits its layout marker (10 x 8 x 10), the Chief's tent is walk-through.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import forest_palette as fp  # noqa: E402
import glbtools  # noqa: E402
from forest_palette import BARK, CAMP, FLAME, FOLIAGE, GROUND, HIDE, ROCK  # noqa: E402

KIT = "forest-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")
PALETTE_CARD = "palette-card"
INDEX_NAME = "pieces.json"
GENERATOR = "EraCityTycoon forest-kit"
TAU = math.tau

Vec = tuple[float, float, float]
Rgb = tuple[int, int, int]

# Height rules (see the module docstring); forest.py imports them.
EDGE_MAX = 4.0
CLUTTER_MAX = 4.0
# A piece's flat floor (a tent's fur, a fire's ash) lies this far over its origin, above every
# ground skin tools/levels/forest.py lays (rims +0.03, camp fill +0.06, road fill +0.09), so a
# skin never covers it and no two flat faces share a plane.
FLOOR_LIFT = 0.14


def srgb_to_linear(byte: int) -> float:
    return fp.srgb_to_linear(byte)


# ---------------------------------------------------------------- the mesh


class Mesh:
    """Flat-shaded triangles in the glTF frame, each with an sRGB colour from forest_palette."""

    def __init__(self, name: str = "piece"):
        self.name = name
        self.tris: list[tuple[Vec, Vec, Vec, Rgb]] = []

    def count(self) -> int:
        return len(self.tris)

    def _check(self, colour: Rgb) -> Rgb:
        colour = tuple(colour)  # type: ignore[assignment]
        if colour not in fp.ALL_COLOURS:
            raise ValueError(f"{self.name}: colour {colour} is not a forest_palette swatch")
        return colour  # type: ignore[return-value]

    def raw(self, a: Vec, b: Vec, c: Vec, colour: Rgb) -> None:
        self.tris.append((a, b, c, self._check(colour)))

    def out(self, a: Vec, b: Vec, c: Vec, colour: Rgb, centre: Vec) -> None:
        """A face of a convex solid, wound so its normal points away from `centre`."""
        n = normal(a, b, c)
        m = ((a[0] + b[0] + c[0]) / 3 - centre[0], (a[1] + b[1] + c[1]) / 3 - centre[1], (a[2] + b[2] + c[2]) / 3 - centre[2])
        if n[0] * m[0] + n[1] * m[1] + n[2] * m[2] < 0:
            b, c = c, b
        self.raw(a, b, c, colour)

    def toward(self, a: Vec, b: Vec, c: Vec, colour: Rgb, direction: Vec) -> None:
        n = normal(a, b, c)
        if n[0] * direction[0] + n[1] * direction[1] + n[2] * direction[2] < 0:
            b, c = c, b
        self.raw(a, b, c, colour)

    def panel(self, pts: list[Vec], front: Rgb, back: Rgb, facing: Vec) -> None:
        """A thin flat panel (a hide, a banner, a blade): a fan, written once per side."""
        for i in range(1, len(pts) - 1):
            self.toward(pts[0], pts[i], pts[i + 1], front, facing)
            self.toward(pts[0], pts[i], pts[i + 1], back, (-facing[0], -facing[1], -facing[2]))

    def solid(self, faces: list[tuple[list[Vec], Rgb]]) -> None:
        """A convex solid from polygon faces (fans), wound outward from its vertices' centroid."""
        pts = [p for poly, _ in faces for p in poly]
        centre = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts), sum(p[2] for p in pts) / len(pts))
        for poly, colour in faces:
            for i in range(1, len(poly) - 1):
                self.out(poly[0], poly[i], poly[i + 1], colour, centre)

    # -- primitives -------------------------------------------------------------------------

    def frustum(self, base: Vec, r0: float, r1: float, height: float, colour: Rgb, sides: int = 6, rot: float = 0.0,
                top: bool = True, bottom: bool = False, top_colour: Rgb | None = None, bottom_colour: Rgb | None = None,
                lean: tuple[float, float] = (0.0, 0.0), jitter: list[float] | None = None) -> None:
        """An upright prism, frustum or cone (r1 == 0) on a regular polygon; `lean` shifts the top
        ring by (dx, dz); `jitter` scales each base vertex's radius (rocks, ragged tiers)."""
        bx, by, bz = base
        ring0 = []
        ring1 = []
        for i in range(sides):
            a = rot + i * TAU / sides
            s = jitter[i % len(jitter)] if jitter else 1.0
            ring0.append((bx + r0 * s * math.cos(a), by, bz + r0 * s * math.sin(a)))
            ring1.append((bx + lean[0] + r1 * s * math.cos(a), by + height, bz + lean[1] + r1 * s * math.sin(a)))
        centre = (bx + lean[0] / 2, by + height / 2, bz + lean[1] / 2)
        if r1 <= 1e-9:
            apex = (bx + lean[0], by + height, bz + lean[1])
            for i in range(sides):
                self.out(ring0[i], ring0[(i + 1) % sides], apex, colour, centre)
        else:
            for i in range(sides):
                j = (i + 1) % sides
                self.out(ring0[i], ring0[j], ring1[j], colour, centre)
                self.out(ring0[i], ring1[j], ring1[i], colour, centre)
            if top:
                for i in range(1, sides - 1):
                    self.out(ring1[0], ring1[i], ring1[i + 1], top_colour or colour, centre)
        if bottom:
            for i in range(1, sides - 1):
                self.out(ring0[0], ring0[i], ring0[i + 1], bottom_colour or colour, centre)

    def blob(self, centre: Vec, radii: Vec, colour: Rgb, rot: float = 0.0, seed: float = 0.0, rough: float = 0.0,
             flat_bottom: float | None = None, colour2: Rgb | None = None) -> None:
        """A squashed icosahedron (20 triangles), each vertex pushed by a seeded `rough` share;
        `flat_bottom` clamps vertices to at least that height (a rock that sits on the ground);
        `colour2` paints the lower half (a shaded underside)."""
        cr, sr = math.cos(rot), math.sin(rot)
        pts = []
        for k, (x, y, z) in enumerate(ICO_VERTS):
            s = 1.0 + rough * (hash01(seed, k) * 2 - 1)
            x, y, z = x / ICO_NORM * radii[0] * s, y / ICO_NORM * radii[1] * s, z / ICO_NORM * radii[2] * s
            px, pz = x * cr - z * sr, x * sr + z * cr
            py = centre[1] + y
            if flat_bottom is not None and py < flat_bottom:
                py = flat_bottom
            pts.append((centre[0] + px, py, centre[2] + pz))
        for a, b, c in ICO_FACES:
            col = colour
            if colour2 is not None and (pts[a][1] + pts[b][1] + pts[c][1]) / 3 < centre[1] - radii[1] * 0.15:
                col = colour2
            self.out(pts[a], pts[b], pts[c], col, centre)

    def rod(self, p0: Vec, p1: Vec, radius: float, colour: Rgb, sides: int = 5, caps: bool = True,
            cap_colour: Rgb | None = None, r1: float | None = None, point: float = 0.0) -> None:
        """A prism (a log, a pole, a stake) from p0 to p1; `r1` tapers it, `point` adds a cone tip
        of that length past p1 (a sharpened stake)."""
        ax = sub(p1, p0)
        length = vlen(ax)
        if length < 1e-6:
            return
        u = scale(ax, 1.0 / length)
        side = perpendicular(u)
        other = cross(u, side)
        r_end = radius if r1 is None else r1
        ring0, ring1 = [], []
        for i in range(sides):
            a = i * TAU / sides
            d = add(scale(side, math.cos(a)), scale(other, math.sin(a)))
            ring0.append(add(p0, scale(d, radius)))
            ring1.append(add(p1, scale(d, r_end)))
        centre = scale(add(p0, p1), 0.5)
        for i in range(sides):
            j = (i + 1) % sides
            self.out(ring0[i], ring0[j], ring1[j], colour, centre)
            self.out(ring0[i], ring1[j], ring1[i], colour, centre)
        if caps:
            for i in range(1, sides - 1):
                self.out(ring0[0], ring0[i], ring0[i + 1], cap_colour or colour, centre)
        if point > 0:
            tip = add(p1, scale(u, point))
            for i in range(sides):
                self.out(ring1[i], ring1[(i + 1) % sides], tip, cap_colour or colour, p1)
        elif caps:
            for i in range(1, sides - 1):
                self.out(ring1[0], ring1[i], ring1[i + 1], cap_colour or colour, centre)

    def box(self, centre: Vec, size: Vec, colour: Rgb, yaw: float = 0.0, top: Rgb | None = None) -> None:
        cx, cy, cz = centre
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        c, s = math.cos(yaw), math.sin(yaw)

        def p(x: float, y: float, z: float) -> Vec:
            return (cx + x * c + z * s, cy + y, cz - x * s + z * c)

        v = [p(sx * hx, sy * hy, sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        faces = [
            ([v[2], v[3], v[7], v[6]], top or colour),  # top (+y)
            ([v[0], v[4], v[5], v[1]], colour),
            ([v[0], v[1], v[3], v[2]], colour),
            ([v[4], v[6], v[7], v[5]], colour),
            ([v[0], v[2], v[6], v[4]], colour),
            ([v[1], v[5], v[7], v[3]], colour),
        ]
        for poly, col in faces:
            self.out(poly[0], poly[1], poly[2], col, centre)
            self.out(poly[0], poly[2], poly[3], col, centre)

    # -- output -------------------------------------------------------------------------------

    def bounds(self) -> tuple[Vec, Vec]:
        xs = [p[i] for t in self.tris for p in t[:3] for i in (0,)]
        ys = [p[1] for t in self.tris for p in t[:3]]
        zs = [p[2] for t in self.tris for p in t[:3]]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def transformed(self, x: float, y: float, z: float, yaw_deg: float, s: float) -> list[tuple[Vec, Vec, Vec, Rgb]]:
        """This piece's triangles placed in a level: scaled, turned by yaw about +Y (the
        CFrame.Angles convention), moved to (x, y, z). Uniform scale and a turn keep the winding."""
        c, sn = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
        out = []
        for a, b, cc, colour in self.tris:
            pts = []
            for px, py, pz in (a, b, cc):
                px, py, pz = px * s, py * s, pz * s
                pts.append((x + px * c + pz * sn, y + py, z - px * sn + pz * c))
            out.append((pts[0], pts[1], pts[2], colour))
        return out


# ---------------------------------------------------------------- small maths


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def scale(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s, a[2] * s)


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def vlen(a: Vec) -> float:
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def normal(a: Vec, b: Vec, c: Vec) -> Vec:
    return cross(sub(b, a), sub(c, a))


def unit(a: Vec) -> Vec:
    n = vlen(a)
    return (0.0, 1.0, 0.0) if n < 1e-12 else scale(a, 1.0 / n)


def perpendicular(u: Vec) -> Vec:
    ref = (0.0, 1.0, 0.0) if abs(u[1]) < 0.9 else (1.0, 0.0, 0.0)
    return unit(cross(u, ref))


def hash01(*values: float) -> float:
    """A deterministic 0..1 from numbers (no hash() of strings: stable across runs)."""
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


ICO_T = (1 + 5**0.5) / 2
ICO_VERTS = [(-1, ICO_T, 0), (1, ICO_T, 0), (-1, -ICO_T, 0), (1, -ICO_T, 0), (0, -1, ICO_T), (0, 1, ICO_T), (0, -1, -ICO_T), (0, 1, -ICO_T), (ICO_T, 0, -1), (ICO_T, 0, 1), (-ICO_T, 0, -1), (-ICO_T, 0, 1)]
ICO_FACES = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
ICO_NORM = math.sqrt(1 + ICO_T * ICO_T)


def rng_for(name: str) -> random.Random:
    """A generator seeded from the piece's name (bytes, not hash()), so every run builds the same piece."""
    return random.Random(int.from_bytes(name.encode("utf-8")[:16].ljust(16, b"\0"), "little"))


# ---------------------------------------------------------------- trees


def fir(name: str, height: float, radius: float, tiers: int, sides: int, droop: bool) -> Mesh:
    """A dark fir: a narrow trunk and stacked tiers. The mass version is plain cones (12 triangles
    a tier); the hero version (`droop`) gives each tier a ragged rim and a shaded underside, so a
    fir beside the road reads layered, not as a stack of party hats."""
    m = Mesh(name)
    r = rng_for(name)
    m.frustum((0, -0.3, 0), radius * 0.13, radius * 0.08, height * 0.4, BARK.BARK_DARK, sides=4, rot=0.4, top=False)
    colours = [FOLIAGE.FIR_DARK, FOLIAGE.FIR, FOLIAGE.FIR, FOLIAGE.FIR_TIP, FOLIAGE.FIR_TIP]
    for t in range(tiers):
        f = t / max(1, tiers - 1)
        base = height * (0.16 + 0.68 * f * (tiers - 1) / tiers)
        rr = radius * (1.0 - 0.62 * f)
        tall = height * (0.34 - 0.06 * f) if t < tiers - 1 else height - base
        colour = colours[min(len(colours) - 1, round(f * (len(colours) - 1)))]
        rot = r.uniform(0, TAU)
        if not droop:
            m.frustum((0, base, 0), rr, 0.0, tall, colour, sides=sides, rot=rot, bottom=True, bottom_colour=FOLIAGE.FIR_DARK)
            continue
        # A ragged rim: alternate points reach out and droop, the notches between sit higher.
        rim = []
        for i in range(sides * 2):
            a = rot + i * TAU / (sides * 2)
            out = rr * (1.0 if i % 2 == 0 else 0.72) * r.uniform(0.92, 1.06)
            dy = -rr * 0.16 if i % 2 == 0 else rr * 0.02
            rim.append((out * math.cos(a), base + dy, out * math.sin(a)))
        apex = (0.0, base + tall, 0.0)
        under = (0.0, base + tall * 0.18, 0.0)
        n = len(rim)
        for i in range(n):
            j = (i + 1) % n
            m.toward(rim[i], rim[j], apex, colour, (rim[i][0] + rim[j][0], 0.5 * rr, rim[i][2] + rim[j][2]))
            m.toward(rim[i], rim[j], under, FOLIAGE.FIR_DARK, (0.0, -1.0, 0.0))
    return m


def broadleaf(name: str) -> Mesh:
    """The dark, gnarled broadleaf that stands among the firs near the camps: a leaning trunk in
    three bends, two limbs, a heavy uneven crown."""
    m = Mesh(name)
    r = rng_for(name)
    p0 = (0.0, -0.3, 0.0)
    p1 = (0.6, 4.2, 0.3)
    p2 = (-0.2, 8.0, 0.6)
    p3 = (0.5, 11.0, 0.2)
    m.rod(p0, p1, 1.05, BARK.BARK_DARK, sides=6, caps=False, r1=0.8)
    m.rod(p1, p2, 0.82, BARK.BARK_DARK, sides=6, caps=False, r1=0.62)
    m.rod(p2, p3, 0.64, BARK.BARK, sides=5, caps=False, r1=0.4)
    m.rod(p1, (3.6, 8.4, -0.8), 0.45, BARK.BARK, sides=4, r1=0.22)
    m.rod(p2, (-3.4, 10.6, 1.4), 0.4, BARK.BARK, sides=4, r1=0.2)
    crowns = [((0.4, 12.4, 0.2), (5.2, 3.6, 5.0), FOLIAGE.LEAF_DARK), ((3.4, 10.2, -0.9), (3.4, 2.6, 3.2), FOLIAGE.LEAF),
              ((-3.0, 11.4, 1.6), (3.6, 2.8, 3.4), FOLIAGE.LEAF), ((-0.6, 14.6, -0.4), (3.4, 2.4, 3.2), FOLIAGE.LEAF)]
    for i, (c, rad, col) in enumerate(crowns):
        m.blob(c, rad, col, rot=r.uniform(0, TAU), seed=i + 3.0, rough=0.16, colour2=FOLIAGE.LEAF_DARK)
    # Roots fanned at the foot, so the trunk does not stand like a post.
    for k in range(4):
        a = 0.6 + k * TAU / 4
        m.rod((0.0, 0.6, 0.0), (1.9 * math.cos(a), -0.25, 1.9 * math.sin(a)), 0.42, BARK.BARK_DARK, sides=4, r1=0.12)
    return m


def snag(name: str, height: float) -> Mesh:
    """A dead tree: a bleached trunk snapped at the top, three broken limbs."""
    m = Mesh(name)
    r = rng_for(name)
    m.frustum((0, -0.3, 0), 0.7, 0.42, height * 0.62, BARK.DEADWOOD_DARK, sides=5, rot=0.3, top=False)
    m.frustum((0, height * 0.62 - 0.3, 0), 0.42, 0.18, height * 0.38, BARK.DEADWOOD, sides=5, rot=0.3, top=True,
              lean=(0.35, -0.2), top_colour=BARK.DEADWOOD_DARK)
    for k in range(3):
        a = r.uniform(0, TAU)
        y = height * (0.42 + 0.17 * k)
        reach = 2.4 - 0.5 * k
        m.rod((0.0, y, 0.0), (reach * math.cos(a), y + reach * 0.7, reach * math.sin(a)), 0.22, BARK.DEADWOOD, sides=3, r1=0.06)
    return m


def stump(name: str, mossy: bool) -> Mesh:
    m = Mesh(name)
    m.frustum((0, -0.2, 0), 0.95, 0.8, 1.3, BARK.BARK_DARK, sides=7, rot=0.2, top=True, top_colour=BARK.LOG_END)
    for k in range(3):
        a = 0.9 + k * TAU / 3
        m.rod((0.0, 0.5, 0.0), (1.4 * math.cos(a), -0.2, 1.4 * math.sin(a)), 0.32, BARK.BARK_DARK, sides=4, r1=0.1)
    if mossy:
        m.blob((0.15, 1.15, 0.1), (0.7, 0.22, 0.6), FOLIAGE.MOSS, seed=2.0, rough=0.1)
    return m


# ---------------------------------------------------------------- undergrowth


def bush(name: str, size: float) -> Mesh:
    m = Mesh(name)
    r = rng_for(name)
    for k in range(3):
        a = k * TAU / 3 + r.uniform(-0.3, 0.3)
        d = size * 0.34
        rad = size * r.uniform(0.42, 0.55)
        m.blob((d * math.cos(a), rad * 0.8, d * math.sin(a)), (rad, rad * 0.86, rad), FOLIAGE.BUSH if k else FOLIAGE.BUSH_DARK,
               rot=r.uniform(0, TAU), seed=k + size, rough=0.18, flat_bottom=-0.1, colour2=FOLIAGE.BUSH_DARK)
    return m


def thicket(name: str, length: float, height: float) -> Mesh:
    """A dense clump of bush and bramble canes, `length` along X, centred on the origin."""
    m = Mesh(name)
    r = rng_for(name)
    n = max(2, round(length / 2.1))
    for k in range(n):
        x = -length / 2 + (k + 0.5) * length / n + r.uniform(-0.3, 0.3)
        rad = r.uniform(1.15, 1.45)
        hy = height * r.uniform(0.40, 0.5)
        m.blob((x, hy, r.uniform(-0.3, 0.3)), (rad, hy, rad * 0.95), FOLIAGE.BUSH_DARK if k % 2 else FOLIAGE.BUSH,
               rot=r.uniform(0, TAU), seed=k * 1.7 + length, rough=0.2, flat_bottom=-0.1, colour2=FOLIAGE.BUSH_DARK)
    for k in range(n):
        x = r.uniform(-length / 2, length / 2)
        z = r.uniform(-0.6, 0.6)
        tip = (x + r.uniform(-0.8, 0.8), height * r.uniform(0.8, 0.98), z + r.uniform(-0.9, 0.9))
        m.rod((x, 0.0, z), tip, 0.09, FOLIAGE.BRAMBLE, sides=3, caps=False, r1=0.03)
    return m


def bramble(name: str) -> Mesh:
    m = Mesh(name)
    r = rng_for(name)
    m.blob((0.0, 0.9, 0.0), (1.5, 1.0, 1.4), FOLIAGE.BUSH_DARK, seed=1.0, rough=0.2, flat_bottom=-0.1)
    m.blob((0.8, 1.4, -0.4), (0.9, 0.8, 0.9), FOLIAGE.LEAF_DARK, seed=2.0, rough=0.2)
    m.blob((-0.7, 1.1, 0.6), (1.1, 0.85, 1.0), FOLIAGE.BUSH_DARK, seed=3.0, rough=0.2, flat_bottom=-0.1)
    for k in range(6):
        a = k * TAU / 6 + r.uniform(-0.2, 0.2)
        base = (0.9 * math.cos(a), 1.0, 0.9 * math.sin(a))
        tip = (1.75 * math.cos(a + 0.25), 2.2 + r.uniform(0, 0.5), 1.75 * math.sin(a + 0.25))
        m.rod(base, tip, 0.07, FOLIAGE.BRAMBLE, sides=3, caps=False, r1=0.02)
    for k in range(4):
        a = k * 1.6
        rr = 1.2 + 0.2 * math.sin(k * 2.0)
        m.frustum((rr * math.cos(a), 1.3 + 0.3 * math.sin(k), rr * math.sin(a)), 0.1, 0.0, 0.15, FOLIAGE.BERRY, sides=3,
                  rot=a, bottom=True)
    return m


def fern(name: str) -> Mesh:
    m = Mesh(name)
    r = rng_for(name)
    for k in range(7):
        a = k * TAU / 7 + r.uniform(-0.2, 0.2)
        length = r.uniform(1.4, 1.9)
        ca, sa = math.cos(a), math.sin(a)
        mid = (ca * length * 0.55, 0.85, sa * length * 0.55)
        tip = (ca * length, 0.55, sa * length)
        w = 0.28
        px, pz = -sa * w, ca * w
        base = (0.0, 0.05, 0.0)
        left, right = (mid[0] + px, mid[1], mid[2] + pz), (mid[0] - px, mid[1], mid[2] - pz)
        up = (0.0, 1.0, 0.0)
        m.panel([base, left, right], FOLIAGE.FERN, FOLIAGE.BUSH_DARK, up)
        m.panel([left, tip, right], FOLIAGE.FERN, FOLIAGE.BUSH_DARK, (ca * 0.3, 1.0, sa * 0.3))
    return m


def mushrooms(name: str) -> Mesh:
    m = Mesh(name)
    for k, (x, z, h, rc) in enumerate(((0.0, 0.0, 0.7, 0.45), (0.55, 0.25, 0.45, 0.3), (-0.35, 0.45, 0.35, 0.24))):
        m.frustum((x, 0.0, z), 0.09, 0.07, h, CAMP.BONE_SHADE, sides=4, top=False)
        m.frustum((x, h - 0.05, z), rc, 0.0, rc * 0.7, FOLIAGE.BERRY, sides=6, rot=k, bottom=True, bottom_colour=CAMP.BONE)
    return m


# ---------------------------------------------------------------- rocks


def rock(name: str, radii: Vec, mossy: bool) -> Mesh:
    m = Mesh(name)
    seed = sum(name.encode("utf-8")) * 0.37
    m.blob((0.0, radii[1] * 0.55, 0.0), radii, ROCK.ROCK, rot=0.3, seed=seed, rough=0.22, flat_bottom=-0.15, colour2=ROCK.ROCK_DARK)
    if mossy:
        m.blob((radii[0] * 0.1, radii[1] * 1.28, 0.0), (radii[0] * 0.72, radii[1] * 0.22, radii[2] * 0.66), FOLIAGE.MOSS,
               rot=0.8, seed=seed + 1, rough=0.12)
    return m


def standing_stone(name: str) -> Mesh:
    m = Mesh(name)
    m.frustum((0, -0.3, 0), 1.3, 0.55, 5.6, ROCK.ROCK, sides=5, rot=0.4, top=True, top_colour=ROCK.ROCK_LIGHT,
              lean=(0.4, 0.2), jitter=[1.0, 0.8, 1.1, 0.9, 1.05])
    return m


# ---------------------------------------------------------------- camp edges (<= EDGE_MAX)
# Every edge piece runs `length` along X with its INNER face (the camp side, -Z) on z = 0, so a
# piece turned to face the camp stands entirely outside the floor's edge, on the fence line and
# beyond it, where nobody walks: a player at the fence never stands inside the visual.


def edge_logs(name: str, length: float = 8.0) -> Mesh:
    """Three logs stacked behind pairs of stakes: the raiders' log wall, 3.9 tall."""
    m = Mesh(name)
    r = rng_for(name)
    for k, (y, z) in enumerate(((0.62, 0.75), (1.86, 0.75), (3.1, 0.8))):
        rr = 0.62 - 0.03 * k
        sag = r.uniform(-0.08, 0.08)
        m.rod((-length / 2 - 0.2 * k, y, z + sag), (length / 2 + 0.15 * k, y + sag, z - sag), rr, BARK.BARK, sides=6,
              cap_colour=BARK.LOG_END)
    for x in (-length / 2 + 0.6, length / 2 - 0.6):
        for z in (0.05, 1.5):
            m.rod((x, -0.2, z + 0.12), (x + r.uniform(-0.1, 0.1), 3.55, z + 0.12), 0.18, CAMP.WOOD_DARK, sides=4, point=0.4)
        m.rod((x - 0.2, 2.5, 0.2), (x + 0.2, 2.5, 1.5), 0.08, CAMP.ROPE, sides=3)
    return m


def edge_stakes(name: str, length: float = 8.0) -> Mesh:
    """The Pickets: sharpened stakes leaning outward over a binding log, 3.9 tall."""
    m = Mesh(name)
    r = rng_for(name)
    n = max(3, round(length / 1.25))
    for k in range(n):
        x = -length / 2 + (k + 0.5) * length / n + r.uniform(-0.12, 0.12)
        lean = r.uniform(0.9, 1.3)
        top = r.uniform(3.4, 3.65)
        m.rod((x, -0.3, 0.45), (x + r.uniform(-0.15, 0.15), top, 0.45 + lean), 0.2, CAMP.WOOD, sides=4, point=0.38,
              cap_colour=CAMP.WOOD_LIGHT)
    m.rod((-length / 2, 1.1, 0.95), (length / 2, 1.1, 0.95), 0.32, BARK.BARK, sides=5, cap_colour=BARK.LOG_END)
    m.rod((-length / 2, 0.3, 1.9), (length / 2, 0.3, 1.9), 0.36, BARK.BARK_DARK, sides=5, cap_colour=BARK.LOG_END)
    return m


def edge_rocks(name: str, length: float = 7.0) -> Mesh:
    m = Mesh(name)
    r = rng_for(name)
    n = max(2, round(length / 2.3))
    for k in range(n):
        x = -length / 2 + (k + 0.5) * length / n + r.uniform(-0.3, 0.3)
        rad = r.uniform(1.25, 1.6)
        hy = r.uniform(1.25, 1.75)
        m.blob((x, hy * 0.92, rad * 0.95), (rad, hy, rad), ROCK.ROCK if k % 2 else ROCK.ROCK_LIGHT, rot=r.uniform(0, TAU),
               seed=k + length, rough=0.22, flat_bottom=-0.1, colour2=ROCK.ROCK_DARK)
    for k in range(n - 1):
        x = -length / 2 + (k + 1) * length / n
        m.blob((x, 0.7, 2.3), (0.9, 0.7, 0.8), ROCK.ROCK_DARK, seed=k + 20.0, rough=0.2, flat_bottom=-0.1)
    return m


def edge_thicket(name: str, length: float = 7.0) -> Mesh:
    """A thicket hedge on the fence line, its inner face on z = 0."""
    m = thicket(name, length, 3.8)
    shifted = Mesh(name)
    for a, b, c, col in m.tris:
        shifted.tris.append(((a[0], a[1], a[2] + 1.45), (b[0], b[1], b[2] + 1.45), (c[0], c[1], c[2] + 1.45), col))
    return shifted


def gate_post(name: str) -> Mesh:
    """A totem post that marks a camp's gate, standing outside the fence: carved bands, a skull,
    feathers, 9 tall."""
    m = Mesh(name)
    m.frustum((0, -0.3, 0), 0.62, 0.5, 8.0, CAMP.WOOD_DARK, sides=6, rot=0.2, top=True, top_colour=CAMP.WOOD)
    for y, col in ((2.2, CAMP.OCHRE), (4.4, CAMP.BONE_SHADE), (6.3, CAMP.OCHRE)):
        m.frustum((0, y, 0), 0.72, 0.72, 0.5, col, sides=6, rot=0.2, top=True, bottom=True)
    m.blob((0.0, 8.35, -0.2), (0.62, 0.6, 0.66), CAMP.BONE, seed=4.0, rough=0.08)
    m.box((0.0, 8.2, -0.7), (0.5, 0.3, 0.3), CAMP.BONE_SHADE)
    for k, a in enumerate((-0.6, 0.6)):
        m.rod((0.45 * math.sin(a), 8.6, 0.0), (1.6 * math.sin(a), 9.4, 0.3), 0.14, CAMP.BONE_SHADE, sides=3, r1=0.04)
    for k in range(3):
        a = -0.5 + k * 0.5
        m.panel([(0.15 * k - 0.15, 7.6, 0.45), (0.15 * k - 0.15 + 0.5 * a, 6.4, 0.75), (0.15 * k - 0.15 + 0.5 * a + 0.2, 6.5, 0.8)],
                CAMP.FEATHER, CAMP.BONE_SHADE, (0.0, 0.0, 1.0))
    return m


# ---------------------------------------------------------------- tents


def hide_tent(name: str) -> Mesh:
    """An A-frame hide tent, 6 wide, 8 long, 5.2 tall, its open door toward -Z; crossed poles
    stand out of the ridge at both ends. Stands outside the walking space (taller than 4)."""
    m = Mesh(name)
    w, ln, h = 3.0, 4.0, 5.2
    ridge_f, ridge_b = (0.0, h, -ln), (0.0, h, ln)
    lf, rf, lb, rb = (-w, 0.0, -ln), (w, 0.0, -ln), (-w, 0.0, ln), (w, 0.0, ln)
    for side, (a0, a1) in (("l", (lf, lb)), ("r", (rf, rb))):
        mid_f = ((a0[0] + ridge_f[0]) / 2, h / 2 + 0.1, -ln)
        mid_b = ((a1[0] + ridge_b[0]) / 2, h / 2 + 0.1, ln)
        facing = (-1.0 if side == "l" else 1.0, 0.6, 0.0)
        m.panel([a0, a1, mid_b, mid_f], HIDE.HIDE, HIDE.HIDE_DARK, facing)
        m.panel([mid_f, mid_b, ridge_b, ridge_f], HIDE.HIDE_PALE if side == "l" else HIDE.HIDE, HIDE.HIDE_DARK, facing)
    m.panel([lb, rb, ridge_b], HIDE.HIDE_DARK, HIDE.FUR_DARK, (0.0, 0.0, 1.0))
    # The door flaps, folded back.
    m.panel([lf, (-w * 0.5, h * 0.5, -ln), (-w * 1.25, 0.0, -ln - 1.3)], HIDE.HIDE_PALE, HIDE.HIDE_DARK, (-0.4, 0.0, -1.0))
    m.panel([rf, (w * 0.5, h * 0.5, -ln), (w * 1.25, 0.0, -ln - 1.3)], HIDE.HIDE_PALE, HIDE.HIDE_DARK, (0.4, 0.0, -1.0))
    m.panel([(-w + 0.1, FLOOR_LIFT, -ln + 0.1), (w - 0.1, FLOOR_LIFT, -ln + 0.1), (w - 0.1, FLOOR_LIFT, ln - 0.1), (-w + 0.1, FLOOR_LIFT, ln - 0.1)],
            HIDE.FUR_DARK, HIDE.FUR_DARK, (0.0, 1.0, 0.0))
    for zz in (-ln - 0.05, ln + 0.05):
        m.rod((-w - 0.3, -0.2, zz), (0.9, h + 1.3, zz), 0.13, CAMP.WOOD_DARK, sides=4)
        m.rod((w + 0.3, -0.2, zz), (-0.9, h + 1.3, zz), 0.13, CAMP.WOOD_DARK, sides=4)
    m.rod((0.0, h + 0.05, -ln - 0.6), (0.0, h + 0.05, ln + 0.6), 0.14, CAMP.WOOD, sides=4)
    for z in (-1.4, 1.4):
        m.rod((-w * 0.5 - 0.1, h * 0.5 + 0.1, z), (0.1, h + 0.08, z), 0.07, CAMP.ROPE_DARK, sides=3)
    return m


def lean_to(name: str) -> Mesh:
    """A lean-to of hide on two forked poles, 3.8 tall: low enough to stand inside a camp."""
    m = Mesh(name)
    w = 3.2
    for x in (-w, w):
        m.rod((x, -0.2, -1.3), (x, 3.6, -1.3), 0.15, CAMP.WOOD_DARK, sides=4)
    m.rod((-w - 0.4, 3.55, -1.3), (w + 0.4, 3.55, -1.3), 0.14, CAMP.WOOD, sides=4)
    m.panel([(-w, 3.5, -1.2), (w, 3.5, -1.2), (w, 0.0, 1.8), (-w, 0.0, 1.8)], HIDE.HIDE, HIDE.HIDE_DARK, (0.0, 0.7, 0.6))
    m.panel([(-w + 0.3, FLOOR_LIFT, -1.0), (w - 0.3, FLOOR_LIFT, -1.0), (w - 0.3, FLOOR_LIFT, 1.4), (-w + 0.3, FLOOR_LIFT, 1.4)],
            HIDE.FUR, HIDE.FUR_DARK, (0.0, 1.0, 0.0))
    for x in (-1.8, 0.4, 2.1):
        m.rod((x, 3.45, -1.15), (x + 0.2, 0.05, 1.75), 0.05, CAMP.ROPE_DARK, sides=3, caps=False)
    return m


def spawn_tent(name: str) -> Mesh:
    """The war tent the tent raiders come out of: a hide tipi on a 10 x 10 marker, 8 tall (the
    marker's own height, so it never grows past what the layout already stands there), its door
    toward -Z with the flaps tied back, painted bands, poles crossing out of the smoke hole."""
    m = Mesh(name)
    sides = 10
    r0, h, hole = 4.8, 7.0, 0.55
    ring = [(r0 * math.cos(-math.pi / 2 + (i - 0.5) * TAU / sides), 0.0, r0 * math.sin(-math.pi / 2 + (i - 0.5) * TAU / sides))
            for i in range(sides)]
    top = [(hole * p[0] / r0, h, hole * p[2] / r0) for p in ring]
    band_y = (2.4, 3.0)
    for i in range(sides):
        if i == 0:
            continue  # the door facet (between ring[0] and ring[1], facing -Z) stays open
        j = (i + 1) % sides
        a, b, c, d = ring[i], ring[j], top[j], top[i]
        facing = (a[0] + b[0], 0.6 * r0, a[2] + b[2])
        f0 = band_y[0] / h
        f1 = band_y[1] / h
        a0, b0 = lerp3(a, d, f0), lerp3(b, c, f0)
        a1, b1 = lerp3(a, d, f1), lerp3(b, c, f1)
        col = HIDE.HIDE if i % 2 else HIDE.HIDE_PALE
        m.panel([a, b, b0, a0], col, HIDE.HIDE_DARK, facing)
        m.panel([a0, b0, b1, a1], CAMP.OCHRE, HIDE.HIDE_DARK, facing)
        m.panel([a1, b1, c, d], col, HIDE.HIDE_DARK, facing)
    # The door: two flaps tied back to either side, and the inner floor of fur.
    a, b = ring[0], ring[1]
    m.panel([a, lerp3(a, top[0], 0.62), (a[0] - 1.4, 0.0, a[2] - 0.9)], HIDE.HIDE_PALE, HIDE.HIDE_DARK, (-0.4, 0.2, -1.0))
    m.panel([b, lerp3(b, top[1], 0.62), (b[0] + 1.4, 0.0, b[2] - 0.9)], HIDE.HIDE_PALE, HIDE.HIDE_DARK, (0.4, 0.2, -1.0))
    floor = [(p[0] * 0.95, FLOOR_LIFT, p[2] * 0.95) for p in ring]
    m.panel(floor, HIDE.FUR_DARK, HIDE.FUR_DARK, (0.0, 1.0, 0.0))
    for i in range(0, sides, 2):
        p = ring[i]
        m.rod((p[0] * 1.02, -0.2, p[2] * 1.02), (-p[0] * 0.16, 7.86, -p[2] * 0.16), 0.11, CAMP.WOOD_DARK, sides=4)
    m.blob((-0.1, 7.6, 0.2), (0.45, 0.35, 0.45), FLAME.SOOT, seed=3.0)
    return m


def chief_tent(name: str) -> Mesh:
    """The Camp Chief's hall: a long hide hall on bent poles, 26 wide, 22 deep, 15 tall, its
    porch and door toward -Z (where the Chief steps out), bone arches and red banners at the
    door, a ring of skull poles. Walk-through scenery (MISSIONS_DESIGN section 26 and the camp C
    rules): the floor of the clearing is what players stand on."""
    m = Mesh(name)
    half_w, half_d, h = 13.0, 11.0, 15.0
    arches = 7
    segs = 8
    rings = []
    for k in range(arches):
        z = -half_d + k * (2 * half_d) / (arches - 1)
        bulge = 1.0 if 0 < k < arches - 1 else 0.86
        ring = []
        for s in range(segs + 1):
            t = s / segs
            a = math.pi * (1 - t)
            x = half_w * bulge * math.cos(a)
            y = h * bulge * math.sin(a) ** 0.85
            ring.append((x, y, z))
        rings.append(ring)
    door_lo, door_hi = 3, 5  # the door in the front: the middle segments below the lintel are open
    for k in range(arches - 1):
        for s in range(segs):
            a, b = rings[k][s], rings[k][s + 1]
            c, d = rings[k + 1][s + 1], rings[k + 1][s]
            mid = lerp3(a, c, 0.5)
            facing = (mid[0], mid[1] + 1.0, 0.0)
            # Long stripes front to back: dark skirts, hide flanks, a red band, a pale crown.
            col = (HIDE.HIDE_DARK, HIDE.HIDE, HIDE.DYED_RED, HIDE.HIDE_PALE, HIDE.HIDE_PALE, HIDE.DYED_RED, HIDE.HIDE, HIDE.HIDE_DARK)[s]
            if s in (1, 6) and k % 2:
                col = HIDE.HIDE_PALE
            m.panel([a, b, c, d], col, HIDE.FUR_DARK, facing)
    # The back wall, closed.
    back = rings[-1]
    centre_back = (0.0, h * 0.3, half_d)
    for s in range(segs):
        m.panel([centre_back, back[s], back[s + 1]], HIDE.HIDE_DARK, HIDE.FUR_DARK, (0.0, 0.0, 1.0))
    m.panel([back[0], back[segs], centre_back], HIDE.HIDE_DARK, HIDE.FUR_DARK, (0.0, 0.0, 1.0))
    # The front wall with a tall door opening in its middle.
    front = rings[0]
    lintel = 9.0
    door_half = 4.2
    for s in range(segs):
        a, b = front[s], front[s + 1]
        foot_a = (a[0], 0.0, a[2])
        foot_b = (b[0], 0.0, b[2])
        if door_lo <= s < door_hi:
            # above the door
            la = (a[0], max(lintel, 0.0), a[2])
            lb = (b[0], max(lintel, 0.0), b[2])
            if a[1] > lintel and b[1] > lintel:
                m.panel([la, lb, b, a], HIDE.HIDE_DARK, HIDE.FUR_DARK, (0.0, 0.0, -1.0))
            continue
        if abs(a[0]) < door_half and abs(b[0]) < door_half:
            continue
        m.panel([foot_a, foot_b, b, a], HIDE.HIDE_DARK, HIDE.FUR_DARK, (0.0, 0.0, -1.0))
    # Arched poles over every ring, standing proud of the hides.
    for k in range(arches):
        ring = rings[k]
        for s in range(segs):
            p0 = (ring[s][0] * 1.03, ring[s][1] * 1.03, ring[s][2])
            p1 = (ring[s + 1][0] * 1.03, ring[s + 1][1] * 1.03, ring[s + 1][2])
            m.rod(p0, p1, 0.22, CAMP.WOOD_DARK, sides=4, caps=False)
    m.rod((0.0, h * 1.03 + 0.1, -half_d - 1.0), (0.0, h * 1.03 + 0.1, half_d + 1.0), 0.3, CAMP.WOOD, sides=5)
    # The porch: two bone arches (tusks) and two totem posts with red banners.
    for side in (-1, 1):
        base = (side * 5.2, 0.0, -half_d - 3.2)
        prev = base
        for t in range(1, 6):
            f = t / 5
            p = (side * (5.2 - 3.4 * f ** 1.6), 10.5 * math.sin(f * math.pi * 0.62), -half_d - 3.2 + 0.6 * f)
            m.rod(prev, p, 0.55 - 0.08 * t, CAMP.BONE if t % 2 else CAMP.BONE_SHADE, sides=5, caps=False)
            prev = p
        post = (side * 7.6, 0.0, -half_d - 1.2)
        m.frustum((post[0], -0.3, post[2]), 0.55, 0.45, 13.0, CAMP.WOOD_DARK, sides=6, top=True, top_colour=CAMP.WOOD)
        m.blob((post[0], 13.2, post[2]), (0.75, 0.7, 0.8), CAMP.BONE, seed=side + 5.0, rough=0.06)
        for y in (4.0, 8.0):
            m.frustum((post[0], y, post[2]), 0.66, 0.66, 0.45, CAMP.OCHRE, sides=6, top=True, bottom=True)
        m.rod((post[0], 11.8, post[2]), (post[0] + side * 2.8, 11.8, post[2]), 0.12, CAMP.WOOD, sides=4)
        bx0 = post[0] + side * 0.4
        bx1 = post[0] + side * 2.6
        m.panel([(bx0, 11.7, post[2]), (bx1, 11.7, post[2]), (bx1, 6.6, post[2]), ((bx0 + bx1) / 2, 7.4, post[2]), (bx0, 6.6, post[2])],
                HIDE.DYED_RED, HIDE.HIDE_DARK, (0.0, 0.0, -1.0))
    # A skull row on the lintel, and the floor inside.
    for k in range(5):
        x = -3.2 + k * 1.6
        m.blob((x, lintel + 0.55, -half_d - 0.35), (0.42, 0.4, 0.44), CAMP.BONE, seed=k + 11.0, rough=0.06)
    inner = [(-half_w * 0.95, FLOOR_LIFT, -half_d), (half_w * 0.95, FLOOR_LIFT, -half_d), (half_w * 0.95, FLOOR_LIFT, half_d * 0.95), (-half_w * 0.95, FLOOR_LIFT, half_d * 0.95)]
    m.panel(inner, HIDE.FUR_DARK, HIDE.FUR_DARK, (0.0, 1.0, 0.0))
    # The Chief's seat at the back, a heaped pile of furs and a skull-topped stump.
    m.blob((0.0, 0.9, half_d - 4.0), (3.4, 1.0, 2.2), HIDE.FUR, seed=21.0, rough=0.15, flat_bottom=0.0)
    m.frustum((0.0, 0.0, half_d - 2.4), 1.5, 1.3, 3.2, BARK.BARK_DARK, sides=7, top=True, top_colour=BARK.LOG_END)
    return m


def lerp3(a: Vec, b: Vec, t: float) -> Vec:
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


# ---------------------------------------------------------------- camp life (<= CLUTTER_MAX)


def campfire(name: str) -> Mesh:
    """A ring of stones round a log teepee and its flames, 3.6 across: sits on a fire spot's
    marker (3 x 1 x 3) with the raiders' ring well outside it."""
    m = Mesh(name)
    r = rng_for(name)
    for k in range(9):
        a = k * TAU / 9 + r.uniform(-0.1, 0.1)
        m.blob((1.65 * math.cos(a), 0.22, 1.65 * math.sin(a)), (0.42, 0.3, 0.38), ROCK.ROCK if k % 2 else ROCK.ROCK_DARK,
               rot=a, seed=k + 1.0, rough=0.15, flat_bottom=-0.05)
    m.frustum((0, 0.0, 0), 1.35, 1.2, FLOOR_LIFT + 0.02, FLAME.SOOT, sides=8, top=True)
    for k in range(5):
        a = k * TAU / 5 + 0.3
        m.rod((1.0 * math.cos(a), 0.05, 1.0 * math.sin(a)), (0.12 * math.cos(a), 1.5, 0.12 * math.sin(a)), 0.14,
              BARK.BARK_DARK, sides=4, cap_colour=FLAME.SOOT)
    m.frustum((0, 0.1, 0), 0.8, 0.0, 1.9, FLAME.RED, sides=5, rot=0.2)
    m.frustum((0.05, 0.25, -0.05), 0.55, 0.0, 1.5, FLAME.ORANGE, sides=5, rot=0.9)
    m.frustum((-0.05, 0.4, 0.05), 0.3, 0.0, 1.0, FLAME.YELLOW, sides=4, rot=0.1)
    return m


def hide_rack(name: str) -> Mesh:
    """A drying frame with a stretched hide, 3.6 tall."""
    m = Mesh(name)
    for x in (-1.7, 1.7):
        m.rod((x - 0.5, -0.2, 0.0), (x, 3.5, 0.0), 0.12, CAMP.WOOD_DARK, sides=4)
        m.rod((x + 0.5, -0.2, 0.0), (x, 3.5, 0.0), 0.12, CAMP.WOOD_DARK, sides=4)
    m.rod((-2.0, 3.35, 0.0), (2.0, 3.35, 0.0), 0.11, CAMP.WOOD, sides=4)
    m.rod((-1.4, 0.7, 0.0), (1.4, 0.7, 0.0), 0.09, CAMP.WOOD, sides=4)
    hide = [(-1.3, 3.2, 0.02), (1.25, 3.1, 0.02), (1.15, 0.9, 0.02), (0.1, 0.75, 0.02), (-1.2, 0.95, 0.02)]
    m.panel(hide, HIDE.HIDE_PALE, HIDE.HIDE, (0.0, 0.0, -1.0))
    for x, y in ((-1.3, 3.2), (1.25, 3.1), (1.15, 0.9), (-1.2, 0.95)):
        m.rod((x, y, 0.0), (x * 1.18, y + (0.15 if y > 2 else -0.15), 0.0), 0.04, CAMP.ROPE, sides=3)
    return m


def weapon_rack(name: str) -> Mesh:
    """An A-frame rack of spears and clubs, 3.4 tall."""
    m = Mesh(name)
    for x in (-1.8, 1.8):
        m.rod((x, -0.1, -0.7), (x, 2.4, 0.0), 0.12, CAMP.WOOD_DARK, sides=4)
        m.rod((x, -0.1, 0.7), (x, 2.4, 0.0), 0.12, CAMP.WOOD_DARK, sides=4)
    m.rod((-2.1, 2.3, 0.0), (2.1, 2.3, 0.0), 0.1, CAMP.WOOD, sides=4)
    for k, x in enumerate((-1.2, -0.4, 0.4, 1.2)):
        if k % 2 == 0:
            m.rod((x, 0.0, -0.55), (x + 0.1, 3.0, 0.15), 0.06, CAMP.WOOD, sides=3, point=0.0)
            m.frustum((x + 0.1, 3.0, 0.15), 0.14, 0.0, 0.45, CAMP.FLINT, sides=3)
        else:
            m.rod((x, 0.0, -0.5), (x + 0.05, 2.6, 0.1), 0.08, CAMP.WOOD_DARK, sides=4, r1=0.24, cap_colour=CAMP.WOOD)
    return m


def firewood(name: str) -> Mesh:
    m = Mesh(name)
    r = rng_for(name)
    rows = ((0.3, 4), (0.85, 3), (1.4, 2))
    for y, n in rows:
        for k in range(n):
            x = (k - (n - 1) / 2) * 0.62
            m.rod((x, y, -1.0 + r.uniform(-0.1, 0.1)), (x, y, 1.0 + r.uniform(-0.1, 0.1)), 0.3, BARK.BARK, sides=4,
                  cap_colour=BARK.LOG_END)
    return m


def bedroll(name: str) -> Mesh:
    m = Mesh(name)
    m.blob((0.0, 0.2, 0.0), (1.0, 0.16, 2.0), HIDE.FUR, seed=1.0, rough=0.1, flat_bottom=FLOOR_LIFT)
    m.rod((-0.9, 0.38, -1.9), (0.9, 0.38, -1.9), 0.38, HIDE.FUR_DARK, sides=6, cap_colour=HIDE.HIDE_DARK)
    return m


def sacks(name: str) -> Mesh:
    m = Mesh(name)
    for k, (x, z, s) in enumerate(((0.0, 0.0, 1.0), (1.1, 0.4, 0.8), (0.4, -0.9, 0.75))):
        m.blob((x, 0.75 * s, z), (0.62 * s, 0.8 * s, 0.56 * s), HIDE.HIDE if k % 2 else HIDE.HIDE_PALE, seed=k + 2.0, rough=0.08,
               flat_bottom=0.0)
        m.frustum((x, 1.5 * s, z), 0.18 * s, 0.1 * s, 0.25 * s, CAMP.ROPE, sides=4)
    return m


def bone_pile(name: str) -> Mesh:
    m = Mesh(name)
    r = rng_for(name)
    for k in range(5):
        a = r.uniform(0, TAU)
        p0 = (r.uniform(-0.6, 0.6), 0.12 + 0.1 * k, r.uniform(-0.6, 0.6))
        p1 = (p0[0] + 1.3 * math.cos(a), 0.12 + 0.05 * k, p0[2] + 1.3 * math.sin(a))
        m.rod(p0, p1, 0.08, CAMP.BONE, sides=3)
        m.blob(p1, (0.14, 0.12, 0.14), CAMP.BONE_SHADE, seed=k + 1.0)
    m.blob((0.2, 0.45, 0.1), (0.42, 0.38, 0.46), CAMP.BONE, seed=7.0, rough=0.06)
    return m


def skull_pole(name: str) -> Mesh:
    m = Mesh(name)
    m.rod((0.0, -0.3, 0.0), (0.05, 3.3, 0.0), 0.12, CAMP.WOOD_DARK, sides=4)
    m.blob((0.05, 3.55, -0.05), (0.4, 0.38, 0.44), CAMP.BONE, seed=2.0, rough=0.06)
    m.box((0.05, 3.35, -0.42), (0.36, 0.18, 0.2), CAMP.BONE_SHADE)
    m.rod((0.05, 2.5, 0.0), (0.05, 2.5, 0.6), 0.04, CAMP.ROPE, sides=3)
    m.panel([(0.05, 2.5, 0.12), (0.25, 1.6, 0.2), (-0.15, 1.7, 0.22)], CAMP.FEATHER, CAMP.BONE_SHADE, (1.0, 0.0, 0.0))
    return m


def banner(name: str) -> Mesh:
    """A raider banner: a tall pole and a notched red hide, 9 tall (outside the walking space)."""
    m = Mesh(name)
    m.rod((0.0, -0.3, 0.0), (0.0, 9.0, 0.0), 0.16, CAMP.WOOD_DARK, sides=5, point=0.5, cap_colour=CAMP.FLINT)
    m.rod((-0.2, 8.4, 0.0), (2.6, 8.4, 0.0), 0.1, CAMP.WOOD, sides=4)
    m.panel([(0.15, 8.3, 0.0), (2.5, 8.3, 0.0), (2.5, 4.4, 0.0), (1.35, 5.2, 0.0), (0.15, 4.4, 0.0)], HIDE.DYED_RED, HIDE.HIDE_DARK,
            (0.0, 0.0, -1.0))
    m.blob((0.0, 9.0, 0.0), (0.32, 0.3, 0.34), CAMP.BONE, seed=4.0)
    return m


def log_seat(name: str) -> Mesh:
    m = Mesh(name)
    m.rod((-1.6, 0.5, 0.0), (1.6, 0.52, 0.0), 0.5, BARK.BARK, sides=6, cap_colour=BARK.LOG_END)
    return m


def watchtower(name: str) -> Mesh:
    """A raider watch platform of lashed logs, 13 tall with a hide roof: stands outside the
    walking space, on the forest side of a camp's edge."""
    m = Mesh(name)
    s = 2.0
    for x in (-s, s):
        for z in (-s, s):
            m.rod((x * 1.12, -0.3, z * 1.12), (x, 9.2, z), 0.2, BARK.BARK, sides=5)
    for y in (3.0, 6.2):
        for (a, b) in (((-s, -s), (s, -s)), ((s, -s), (s, s)), ((s, s), (-s, s)), ((-s, s), (-s, -s))):
            m.rod((a[0] * 1.05, y, a[1] * 1.05), (b[0] * 1.05, y + 0.2, b[1] * 1.05), 0.13, CAMP.WOOD_DARK, sides=4)
    m.box((0.0, 9.0, 0.0), (2 * s + 1.0, 0.35, 2 * s + 1.0), CAMP.WOOD, top=CAMP.WOOD_LIGHT)
    for (a, b) in (((-s, -s), (s, -s)), ((s, -s), (s, s)), ((s, s), (-s, s)), ((-s, s), (-s, -s))):
        m.rod((a[0] * 1.1, 10.2, a[1] * 1.1), (b[0] * 1.1, 10.2, b[1] * 1.1), 0.1, CAMP.WOOD_DARK, sides=4)
    for x in (-s, s):
        for z in (-s, s):
            m.rod((x, 9.2, z), (x * 0.95, 12.0, z * 0.95), 0.12, CAMP.WOOD_DARK, sides=4)
    roof = [(-s - 0.6, 11.8, -s - 0.6), (s + 0.6, 11.8, -s - 0.6), (s + 0.6, 11.8, s + 0.6), (-s - 0.6, 11.8, s + 0.6)]
    apex = (0.0, 13.4, 0.0)
    for i in range(4):
        m.panel([roof[i], roof[(i + 1) % 4], apex], HIDE.HIDE, HIDE.HIDE_DARK,
                ((roof[i][0] + roof[(i + 1) % 4][0]) / 2, 1.0, (roof[i][2] + roof[(i + 1) % 4][2]) / 2))
    for k in range(7):
        y = 0.8 + k * 1.2
        m.rod((-0.7, y, -s - 0.35), (0.7, y, -s - 0.35), 0.08, CAMP.WOOD, sides=3)
    m.rod((-0.7, -0.3, -s - 0.4), (-0.7, 9.0, -s - 0.3), 0.1, CAMP.WOOD_DARK, sides=4)
    m.rod((0.7, -0.3, -s - 0.4), (0.7, 9.0, -s - 0.3), 0.1, CAMP.WOOD_DARK, sides=4)
    return m


# ---------------------------------------------------------------- cover skins (baked, parametric)


def cover_skin(name: str, sx: float, sy: float, sz: float, seed: int) -> Mesh:
    """A camp's cover block dressed as a crib of logs with a hide thrown over: its visual fills
    the collision box (sx x sy x sz, origin at the box's bottom centre) to within 0.25 on every
    side and its top lies at sy, so what a player stands on is what he sees. Layer by layer the
    logs cross, like a raider's firewood crib; the top layer is a flat hide on planks."""
    m = Mesh(name)
    r = random.Random(seed)
    layers = 3
    lr = sy / (layers * 2 + 0.2)
    inset = 0.18
    for layer in range(layers):
        y = lr + layer * 2 * lr
        along_x = layer % 2 == 0
        span = (sz if along_x else sx) - 2 * inset
        length = (sx if along_x else sz) - 2 * inset
        n = max(2, int(span / (2 * lr * 1.05)))
        for k in range(n):
            t = -span / 2 + lr + k * (span - 2 * lr) / max(1, n - 1)
            jag = r.uniform(-0.15, 0.1)
            if along_x:
                p0, p1 = (-length / 2 + jag, y, t), (length / 2 - jag, y, t)
            else:
                p0, p1 = (t, y, -length / 2 + jag), (t, y, length / 2 - jag)
            m.rod(p0, p1, lr * 0.98, BARK.BARK if (k + layer) % 2 else BARK.BARK_DARK, sides=5, cap_colour=BARK.LOG_END)
    top = sy - 0.06
    hx, hz = sx / 2 - 0.3, sz / 2 - 0.3
    m.panel([(-hx, top, -hz), (hx, top, -hz), (hx * 0.96, top, hz), (-hx * 0.9, top, hz * 0.94)], HIDE.FUR, HIDE.FUR_DARK, (0, 1, 0))
    for x in (-sx / 2 + inset, sx / 2 - inset):
        for z in (-sz / 2 + inset, sz / 2 - inset):
            m.rod((x, -0.1, z), (x, sy - 0.1, z), 0.16, CAMP.WOOD_DARK, sides=4)
    return m


# ---------------------------------------------------------------- the piece table

# role: "tree" (forest mass), "hero" (near the road), "under" (undergrowth), "rock", "edge"
# (camp fence line, <= EDGE_MAX), "clutter" (may stand inside a camp, <= CLUTTER_MAX), "outside"
# (camp pieces taller than 4: only beyond the barrier), "tent" (fits a layout tent marker), "chief".
PIECES = {
    "FirMassA": ("tree", lambda n: fir(n, 26.0, 5.2, 3, 6, False)),
    "FirMassB": ("tree", lambda n: fir(n, 31.0, 4.6, 4, 5, False)),
    "FirHeroA": ("hero", lambda n: fir(n, 30.0, 5.6, 4, 7, True)),
    "FirHeroB": ("hero", lambda n: fir(n, 23.0, 4.8, 4, 6, True)),
    "Broadleaf": ("hero", broadleaf),
    "SnagA": ("tree", lambda n: snag(n, 16.0)),
    "SnagB": ("tree", lambda n: snag(n, 11.0)),
    "Stump": ("under", lambda n: stump(n, False)),
    "StumpMossy": ("under", lambda n: stump(n, True)),
    "Bush": ("under", lambda n: bush(n, 3.4)),
    "BushLarge": ("under", lambda n: bush(n, 4.6)),
    "Thicket": ("under", lambda n: thicket(n, 6.0, 4.4)),
    "Bramble": ("under", bramble),
    "Fern": ("under", fern),
    "Mushrooms": ("under", mushrooms),
    "RockA": ("rock", lambda n: rock(n, (2.2, 1.6, 1.9), False)),
    "RockB": ("rock", lambda n: rock(n, (3.4, 2.2, 2.8), True)),
    "RockSmall": ("rock", lambda n: rock(n, (1.0, 0.7, 0.9), False)),
    "StandingStone": ("rock", standing_stone),
    "EdgeLogs": ("edge", edge_logs),
    "EdgeStakes": ("edge", edge_stakes),
    "EdgeRocks": ("edge", edge_rocks),
    "EdgeThicket": ("edge", edge_thicket),
    "GatePost": ("outside", gate_post),
    "HideTent": ("outside", hide_tent),
    "LeanTo": ("clutter", lean_to),
    "SpawnTent": ("tent", spawn_tent),
    "ChiefTent": ("chief", chief_tent),
    "Campfire": ("clutter", campfire),
    "HideRack": ("clutter", hide_rack),
    "WeaponRack": ("clutter", weapon_rack),
    "Firewood": ("clutter", firewood),
    "Bedroll": ("clutter", bedroll),
    "Sacks": ("clutter", sacks),
    "BonePile": ("clutter", bone_pile),
    "SkullPole": ("clutter", skull_pole),
    "LogSeat": ("clutter", log_seat),
    "Banner": ("outside", banner),
    "Watchtower": ("outside", watchtower),
}

ROLE_MAX_HEIGHT = {"edge": EDGE_MAX, "clutter": CLUTTER_MAX, "tent": 8.0}
TRI_BUDGET = {"tree": 50, "hero": 200, "under": 160, "rock": 150, "edge": 250, "clutter": 300, "outside": 600, "tent": 800,
              "chief": 4000}

_CACHE: dict[str, Mesh] = {}


def build(name: str) -> Mesh:
    """The piece's mesh (cached: forest.py instances one piece thousands of times)."""
    mesh = _CACHE.get(name)
    if mesh is None:
        role, maker = PIECES[name]
        mesh = maker(name)
        mesh.name = name
        _CACHE[name] = mesh
    return mesh


def role_of(name: str) -> str:
    return PIECES[name][0]


# ---------------------------------------------------------------- GLB output


def glb_bytes(mesh: Mesh) -> bytes:
    """One node, one mesh, one primitive per colour, each with a colour-only material (the
    linear factor of its sRGB swatch, metallic 0, rough 1): palette.py collects them and
    merge_stages bakes them onto one swatch texture. Flat normals, unshared vertices."""
    groups: dict[Rgb, list] = {}
    for a, b, c, colour in mesh.tris:
        groups.setdefault(colour, []).append((a, b, c))
    binary = bytearray()
    views, accessors, primitives, materials = [], [], [], []

    def add_view(blob: bytes, target: int, stride: int | None = None) -> int:
        while len(binary) % 4:
            binary.append(0)
        view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(blob), "target": target}
        if stride:
            view["byteStride"] = stride
        views.append(view)
        binary.extend(blob)
        return len(views) - 1

    for colour in sorted(groups):
        tris = groups[colour]
        pos, nrm = [], []
        for a, b, c in tris:
            n = unit(normal(a, b, c))
            pos.extend((a, b, c))
            nrm.extend((n, n, n))
        count = len(pos)
        pv = add_view(b"".join(struct.pack("<fff", *p) for p in pos), 34962, 12)
        nv = add_view(b"".join(struct.pack("<fff", *p) for p in nrm), 34962, 12)
        iv = add_view(struct.pack(f"<{count}I", *range(count)), 34963)
        lo = [min(f32(p[i]) for p in pos) for i in range(3)]
        hi = [max(f32(p[i]) for p in pos) for i in range(3)]
        accessors.append({"bufferView": pv, "componentType": glbtools.FLOAT, "count": count, "type": "VEC3", "min": lo, "max": hi})
        accessors.append({"bufferView": nv, "componentType": glbtools.FLOAT, "count": count, "type": "VEC3"})
        accessors.append({"bufferView": iv, "componentType": glbtools.UNSIGNED_INT, "count": count, "type": "SCALAR"})
        materials.append({
            "name": "fk_%02x%02x%02x" % colour,
            "pbrMetallicRoughness": {"baseColorFactor": [round(srgb_to_linear(c), 6) for c in colour] + [1.0],
                                     "metallicFactor": 0.0, "roughnessFactor": 1.0},
        })
        primitives.append({"attributes": {"POSITION": len(accessors) - 3, "NORMAL": len(accessors) - 2},
                           "indices": len(accessors) - 1, "material": len(materials) - 1})
    while len(binary) % 4:
        binary.append(0)
    doc = {
        "asset": {"version": "2.0", "generator": GENERATOR},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": mesh.name, "mesh": 0}],
        "meshes": [{"name": mesh.name, "primitives": primitives}],
        "materials": materials,
        "bufferViews": views,
        "accessors": accessors,
        "buffers": [{"byteLength": len(binary)}],
    }
    return glbtools.write_glb(doc, bytes(binary))


def f32(v: float) -> float:
    return struct.unpack("<f", struct.pack("<f", v))[0]


def palette_card() -> Mesh:
    """One tiny triangle per swatch, so the kit's palette texture holds every colour whichever
    pieces exist yet (the weapon kit's trick against the palette cache trap)."""
    m = Mesh(PALETTE_CARD)
    for i, colour in enumerate(fp.swatches().values()):
        x = (i % 8) * 0.1
        z = (i // 8) * 0.1
        m.toward((x, 0.0, z), (x + 0.08, 0.0, z), (x, 0.0, z + 0.08), colour, (0.0, 1.0, 0.0))
    return m


def describe(name: str) -> dict:
    mesh = build(name)
    lo, hi = mesh.bounds()
    return {
        "role": role_of(name),
        "triangles": mesh.count(),
        "min": [round(v, 3) for v in lo],
        "max": [round(v, 3) for v in hi],
        "height": round(hi[1], 3),
    }


def problems() -> list[str]:
    """The kit's own rules: triangle budgets per role, heights per role, nothing below -0.5."""
    out = []
    for name in PIECES:
        d = describe(name)
        budget = TRI_BUDGET[d["role"]]
        if d["triangles"] > budget:
            out.append(f"{name}: {d['triangles']} triangles over the {d['role']} budget {budget}")
        cap = ROLE_MAX_HEIGHT.get(d["role"])
        if cap is not None and d["height"] > cap + 1e-6:
            out.append(f"{name}: {d['height']} tall over the {d['role']} cap {cap}")
        if d["min"][1] < -0.5:
            out.append(f"{name}: reaches {d['min'][1]} under its origin")
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Write the Forest Road's generated kit.")
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--list", action="store_true", help="print the pieces, write nothing")
    args = parser.parse_args(argv)
    index = {name: describe(name) for name in PIECES}
    for name, d in index.items():
        size = [round(d["max"][i] - d["min"][i], 2) for i in range(3)]
        print(f"{name:14s} {d['role']:8s} tris {d['triangles']:5d}  size {size[0]:6.2f} {size[1]:6.2f} {size[2]:6.2f}")
    bad = problems()
    for line in bad:
        print(f"[forest-kit] FAIL {line}")
    if args.list:
        return 1 if bad else 0
    os.makedirs(args.out, exist_ok=True)
    for name in PIECES:
        data = glb_bytes(build(name))
        glbtools.validate(data)
        with open(os.path.join(args.out, name + ".glb"), "wb") as fh:
            fh.write(data)
    with open(os.path.join(args.out, PALETTE_CARD + ".glb"), "wb") as fh:
        fh.write(glb_bytes(palette_card()))
    with open(os.path.join(args.out, INDEX_NAME), "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"kit": KIT, "pieces": index}, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print(f"[forest-kit] wrote {len(PIECES)} pieces + {PALETTE_CARD}.glb into {args.out}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
