"""Shared geometry and export for the generated weapon kit (L3): every weapon_kit_<level>.py uses it.

Runs inside Blender (it is imported by the level generators, never run on its own):

    blender -b -P tools/assets/weapon_kit_forest.py [-- --out <dir>] [--only Broadsword]

Why a generated kit: no Kenney kit carries weapons, and Ben chose detailed models over chunky
low-poly (2026-09-23), one look per family, dressed by the level where it is found (MISSIONS_DESIGN
section 24). The GLBs go into assets/kenney3d/weapon-kit/Models/GLB format/ (the folder is the
kit's registration, as for every generated kit), are judged with
`testfit.py --blueprint tools/testfit/blueprints/_props/Weapons/<Name>.json` and merged with
`merge_stages.py --props --era Weapons`. assets/ is gitignored: the generators are the record.

**The frame contract** (one merged MeshPart per weapon, so the client reads these points from
config and never measures them):
  * 1 glTF unit = 1 stud; blueprints use `"scale": 1.0`, `pos` [0, 0, 0], `rotY` 0.
  * The grip centre is the origin. The blade tip, the point or the muzzle lies along -Z. Up (the
    top of a gun, the upper limb of a bow, the back edge of an axe) is +Y. Right is +X.
  * Every weapon names its points in `Mesh.frame` (at least `grip`, `tip` and `holster`; bows add
    `nock`), and the generator writes them beside the GLB as `<model>.frame.json`. testfit's weapon
    view reads that file and draws the points, so a number that drifts from the model shows.

**Colours** come only from weapon_kit_palette.py: `Mesh` raises on any other colour. Every
generator run also writes `palette-card.glb`, one tiny triangle per swatch, so the kit's palette
texture (palette.py scans every GLB in the folder) holds every swatch whichever weapons exist yet.
The cache trap then only bites when weapon_kit_palette.py itself changes: delete
assets/build/palettes/weapon-kit.* after that, before the next merge.

**Geometry** is authored in glTF space (Y up, front -Z). Blender is Z up, so every vertex converts
with (x, y, z) -> (x, -z, y), a proper rotation that keeps the winding. Every closed primitive is
checked by its signed volume as it is added and turned outward if it came out inside out, because
Roblox culls back faces and a reversed part simply vanishes from the camera side. Round parts may
be smooth-shaded (`smooth=True`, shared vertices inside the one primitive); everything else is flat.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import weapon_kit_palette as palette  # noqa: E402

KIT = "weapon-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")
PALETTE_CARD = "palette-card"
FRAME_SUFFIX = ".frame.json"
# Budget per weapon (study report section 5): detailed, yet eight on screen stay under a city plot.
TRI_TARGET = (1500, 3500)
TRI_CAP = 5000

Vec = tuple[float, float, float]
Rgb = tuple[int, int, int]


# --- small vector maths ---------------------------------------------------------------------------


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(a: Vec) -> float:
    return math.sqrt(dot(a, a))


def norm(a: Vec) -> Vec:
    n = length(a)
    return (a[0] / n, a[1] / n, a[2] / n) if n > 1e-12 else (0.0, 0.0, 0.0)


def newell(points) -> Vec:
    n = [0.0, 0.0, 0.0]
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return (n[0], n[1], n[2])


def basis(axis: Vec, ref: Vec | None = None) -> tuple[Vec, Vec]:
    """Two unit vectors perpendicular to `axis` (and to each other); `ref` picks the first one."""
    axis = norm(axis)
    if ref is None:
        ref = (1.0, 0.0, 0.0) if abs(axis[0]) < 0.9 else (0.0, 1.0, 0.0)
    u = norm(sub(ref, mul(axis, dot(ref, axis))))
    v = cross(axis, u)
    return u, v


def rotate(p: Vec, axis: Vec, angle: float) -> Vec:
    """Rodrigues rotation of p about a unit axis through the origin."""
    k = norm(axis)
    c, s = math.cos(angle), math.sin(angle)
    return add(add(mul(p, c), mul(cross(k, p), s)), mul(k, dot(k, p) * (1 - c)))


def ear_clip(points2d) -> list[tuple[int, int, int]]:
    """Triangulate a simple polygon (either winding) by ear clipping; returns index triples."""
    n = len(points2d)
    if n < 3:
        return []
    area = sum(points2d[i][0] * points2d[(i + 1) % n][1] - points2d[(i + 1) % n][0] * points2d[i][1] for i in range(n))
    order = list(range(n)) if area > 0 else list(range(n - 1, -1, -1))

    def is_convex(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) > 1e-12

    def inside(p, a, b, c):
        d1 = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
        d2 = (c[0] - b[0]) * (p[1] - b[1]) - (c[1] - b[1]) * (p[0] - b[0])
        d3 = (a[0] - c[0]) * (p[1] - c[1]) - (a[1] - c[1]) * (p[0] - c[0])
        return d1 >= -1e-12 and d2 >= -1e-12 and d3 >= -1e-12

    tris = []
    guard = 0
    while len(order) > 3 and guard < 10000:
        guard += 1
        m = len(order)
        for k in range(m):
            i0, i1, i2 = order[(k - 1) % m], order[k], order[(k + 1) % m]
            a, b, c = points2d[i0], points2d[i1], points2d[i2]
            if not is_convex(a, b, c):
                continue
            if any(inside(points2d[j], a, b, c) for j in order if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            order.pop(k)
            break
        else:  # degenerate leftovers: fan the rest
            for k in range(1, len(order) - 1):
                tris.append((order[0], order[k], order[k + 1]))
            return tris
    tris.append((order[0], order[1], order[2]))
    return tris


# --- the mesh -----------------------------------------------------------------------------------


class Mesh:
    """Polygons in glTF space, each tagged with a palette colour and a smooth flag.

    A primitive's faces may share vertices (that is what lets a smooth-shaded tube shade round); two
    primitives never share one, so a smooth surface never bends its normals into a neighbour.
    """

    def __init__(self, name: str):
        self.name = name
        self.verts: list[Vec] = []
        self.faces: list[tuple[list[int], Rgb, bool]] = []
        self.frame: dict[str, Vec] = {}
        self.notes: dict[str, object] = {}
        self.warnings: list[str] = []

    # -- low level

    def _colour(self, colour: Rgb) -> Rgb:
        colour = tuple(int(c) for c in colour)
        if colour not in palette.ALL_COLOURS:
            raise ValueError(f"{self.name}: colour {colour} is not in weapon_kit_palette.py; add it there, never inline")
        return colour

    def vert(self, p: Vec) -> int:
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.verts) - 1

    def poly(self, indices, colour: Rgb, smooth: bool = False) -> None:
        self.faces.append((list(indices), self._colour(colour), smooth))

    def _begin(self) -> int:
        return len(self.faces)

    def _close(self, start: int, closed: bool = True) -> None:
        """A closed primitive whose signed volume is negative came out inside out: turn it round.
        Its edges must also pair up (each one walked once each way), or some face is wound against
        its neighbours and the volume test cannot save it."""
        if not closed:
            return
        vol = 0.0
        edges: dict[tuple, int] = {}
        for idx, _, _ in self.faces[start:]:
            a = self.verts[idx[0]]
            for k in range(1, len(idx) - 1):
                vol += dot(a, cross(self.verts[idx[k]], self.verts[idx[k + 1]]))
            keys = [tuple(round(c, 6) for c in self.verts[i]) for i in idx]
            for k, key in enumerate(keys):
                nxt = keys[(k + 1) % len(keys)]
                if key != nxt:
                    edges[(key, nxt)] = edges.get((key, nxt), 0) + 1
        bad = sum(1 for (a, b), c in edges.items() if c != 1 or edges.get((b, a), 0) != 1)
        if bad:
            self.warnings.append(f"primitive at face {start}: {bad} edges are not paired (inconsistent winding or an open seam)")
        if vol < 0:
            self.faces[start:] = [(list(reversed(idx)), c, s) for idx, c, s in self.faces[start:]]

    def face(self, points, colour: Rgb, smooth: bool = False) -> None:
        """One polygon with its own vertices, wound as given."""
        self.poly([self.vert(p) for p in points], colour, smooth)

    def cap(self, points, colour: Rgb) -> None:
        """A flat polygon (convex or not) through `points`, triangulated, keeping their winding.
        Its own vertices: a cap is always flat-shaded."""
        n = norm(newell(points))
        u, v = basis(n)
        p2 = [(dot(p, u), dot(p, v)) for p in points]
        idx = [self.vert(p) for p in points]
        for a, b, c in ear_clip(p2):
            tri = [idx[a], idx[b], idx[c]]
            if dot(newell([self.verts[i] for i in tri]), n) < 0:
                tri.reverse()
            self.poly(tri, colour)

    # -- primitives

    def grid(self, rings, colour: Rgb, *, smooth: bool = False, wrap: bool = True, loop: bool = False,
             cap0: bool = True, cap1: bool = True, apex0: Vec | None = None, apex1: Vec | None = None,
             cap_colour: Rgb | None = None, cap0_colour: Rgb | None = None, cap1_colour: Rgb | None = None,
             face_colour=None) -> None:
        """Quads between consecutive rings (lists of points of equal length).

        `wrap` closes each ring on itself (a tube); `loop` joins the last ring to the first (a
        torus). Ends are closed by a flat cap or, given `apex0` / `apex1`, by a fan to that point.
        `face_colour(i, j)` may colour the quad between ring i and i+1, segment j. Caps and fans are
        wound to agree with the quads, and the closed result is turned outward by its signed volume,
        so rings may run either way round.
        """
        start = self._begin()
        n = len(rings[0])
        ids = [[self.vert(p) for p in ring] for ring in rings]
        seg = n if wrap else n - 1
        count = len(rings) if loop else len(rings) - 1
        for i in range(count):
            a, b = ids[i], ids[(i + 1) % len(rings)]
            for j in range(seg):
                k = (j + 1) % n
                c = face_colour(i, j) if face_colour else colour
                self.poly([a[j], a[k], b[k], b[j]], c, smooth)
        closed = wrap and loop
        if wrap and not loop:
            first, last = ids[0], ids[-1]
            c0 = cap0_colour or cap_colour or colour
            c1 = cap1_colour or cap_colour or colour
            if apex0 is not None:
                t = self.vert(apex0)
                for j in range(n):
                    self.poly([first[(j + 1) % n], first[j], t], c0, smooth)
            elif cap0:
                self.cap([self.verts[i] for i in reversed(first)], c0)
            if apex1 is not None:
                t = self.vert(apex1)
                for j in range(n):
                    self.poly([last[j], last[(j + 1) % n], t], c1, smooth)
            elif cap1:
                self.cap([self.verts[i] for i in last], c1)
            closed = (apex0 is not None or cap0) and (apex1 is not None or cap1)
        self._close(start, closed)

    def lathe(self, profile, colour: Rgb, *, axis: Vec = (0.0, 0.0, 1.0), centre: Vec = (0.0, 0.0, 0.0),
              segments: int = 12, smooth: bool = True, ref: Vec | None = None, phase: float = 0.0,
              cap_colour: Rgb | None = None, face_colour=None) -> None:
        """A solid of revolution. `profile` is a list of (along, radius) or (along, rx, ry) pairs
        along `axis` from `centre`; a radius of 0 at either end closes it to a point."""
        u, v = basis(axis, ref)
        ax = norm(axis)
        rings, apex0, apex1 = [], None, None
        for k, entry in enumerate(profile):
            along = entry[0]
            rx = entry[1]
            ry = entry[2] if len(entry) > 2 else rx
            c = add(centre, mul(ax, along))
            if rx <= 1e-9 and ry <= 1e-9:
                if k == 0:
                    apex0 = c
                elif k == len(profile) - 1:
                    apex1 = c
                continue
            ring = []
            for s in range(segments):
                t = phase + 2 * math.pi * s / segments
                ring.append(add(c, add(mul(u, rx * math.cos(t)), mul(v, ry * math.sin(t)))))
            rings.append(ring)
        if len(rings) == 1:
            rings.append([add(p, mul(ax, 1e-4)) for p in rings[0]])
        self.grid(rings, colour, smooth=smooth, apex0=apex0, apex1=apex1, cap_colour=cap_colour, face_colour=face_colour)

    def sweep(self, path, radius, colour: Rgb, *, segments: int = 8, smooth: bool = True,
              normal0: Vec | None = None, loop: bool = False, caps: bool = True, twist: float = 0.0,
              cap_colour: Rgb | None = None, face_colour=None) -> None:
        """A tube along a polyline. `radius` is a number or an (a, b) pair for the whole tube, or a
        list with one of those per point: a along the frame normal, b along the binormal. The frame is parallel-transported
        from `normal0` (for a path in the YZ plane, normal0 (1, 0, 0) keeps a along X all the way)."""
        n_pts = len(path)
        if isinstance(radius, list):
            if len(radius) != n_pts:
                raise ValueError(f"{self.name}: sweep has {n_pts} points but {len(radius)} radii")
            radii = radius
        else:
            radii = [radius] * n_pts
        tangents = []
        for k in range(n_pts):
            if loop:
                t = sub(path[(k + 1) % n_pts], path[(k - 1) % n_pts])
            elif k == 0:
                t = sub(path[1], path[0])
            elif k == n_pts - 1:
                t = sub(path[-1], path[-2])
            else:
                t = add(norm(sub(path[k + 1], path[k])), norm(sub(path[k], path[k - 1])))
            tangents.append(norm(t))
        nrm, _ = basis(tangents[0], normal0)
        rings = []
        for k in range(n_pts):
            if k > 0:  # parallel transport: remove the tangent component, keep the rest
                t = tangents[k]
                nrm = norm(sub(nrm, mul(t, dot(nrm, t))))
            bi = cross(tangents[k], nrm)
            r = radii[k]
            a, b = (r, r) if isinstance(r, (int, float)) else r
            ring = []
            for s in range(segments):
                ang = 2 * math.pi * s / segments + twist * k
                ring.append(add(path[k], add(mul(nrm, a * math.cos(ang)), mul(bi, b * math.sin(ang)))))
            rings.append(ring)
        self.grid(rings, colour, smooth=smooth, loop=loop, cap0=caps, cap1=caps, cap_colour=cap_colour, face_colour=face_colour)

    def loop(self, centre: Vec, axis: Vec, rx: float, ry: float, tube, colour: Rgb, *, segments: int = 14,
             tube_segments: int = 5, smooth: bool = False, ref: Vec | None = None, tilt: float = 0.0) -> None:
        """A closed ring round `axis`, elliptical (rx along the first basis vector, which `ref`
        picks, ry along the second): a rope turn, a binding round a flat blade, a rim, a string
        loop. `tube` is a number or an (a, b) pair: a outward, b along the axis. `tilt` leans the
        ring about its first basis vector, so stacked turns can read as a winding."""
        u, v = basis(axis, ref)
        ax = norm(axis)
        if tilt:
            v = rotate(v, u, tilt)
            ax = rotate(ax, u, tilt)
        a, b = (tube, tube) if isinstance(tube, (int, float)) else tube
        rings = []
        for s in range(segments):
            t = 2 * math.pi * s / segments
            p = add(centre, add(mul(u, rx * math.cos(t)), mul(v, ry * math.sin(t))))
            out = norm(add(mul(u, math.cos(t) / rx), mul(v, math.sin(t) / ry)))  # the ellipse's normal
            ring = [add(p, add(mul(out, a * math.cos(w)), mul(ax, b * math.sin(w))))
                    for w in (2 * math.pi * k / tube_segments for k in range(tube_segments))]
            rings.append(ring)
        self.grid(rings, colour, smooth=smooth, loop=True)

    def prism(self, outline, depth0: float, depth1: float, colour: Rgb, *, origin: Vec = (0.0, 0.0, 0.0),
              u: Vec = (0.0, 0.0, -1.0), v: Vec = (0.0, 1.0, 0.0), side_colour: Rgb | None = None,
              face1_colour: Rgb | None = None) -> None:
        """A flat outline (2D points in the u, v plane at `origin`, convex or not) extruded along
        u x v from depth0 to depth1: guards, feathers, flat blades. Sides are flat quads."""
        w = norm(cross(u, v))

        def at(p, d):
            return add(origin, add(add(mul(u, p[0]), mul(v, p[1])), mul(w, d)))

        lo = [at(p, depth0) for p in outline]
        hi = [at(p, depth1) for p in outline]
        self.grid([lo, hi], side_colour or colour, cap0_colour=colour, cap1_colour=face1_colour or colour)

    def box(self, x0, x1, y0, y1, z0, z1, colour: Rgb) -> None:
        bottom = [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)]
        top = [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]
        self.grid([bottom, top], colour)

    # -- detail vocabulary: what makes a flat-palette weapon read as "detailed"

    def binding(self, centre: Vec, axis: Vec, rx: float, ry: float, turns: int, cord: float,
                colours: tuple[Rgb, ...], *, ref: Vec | None = None, segments: int = 12, tube_segments: int = 5,
                tilt: float = 0.0) -> None:
        """Turns of cord laid side by side round a core of half-sizes rx, ry, centred on `centre`
        along `axis`. Alternate colours from `colours` make each turn read at a distance; `tilt`
        alternates its sign turn by turn, which is what makes a lashing look wound, not stacked."""
        ax = norm(axis)
        pitch = cord * 1.8
        for k in range(turns):
            off = (k - (turns - 1) / 2) * pitch
            self.loop(add(centre, mul(ax, off)), ax, rx + cord * 0.75, ry + cord * 0.75, (cord, cord * 0.95),
                      colours[k % len(colours)], segments=segments, tube_segments=tube_segments, ref=ref,
                      tilt=tilt * (1 if k % 2 else -1))

    def wrap(self, centre: Vec, axis: Vec, length: float, rx: float, ry: float, colour: Rgb, groove: Rgb, *,
             turns: float, ridge: float = 0.14, ref: Vec | None = None, segments: int = 12, per_turn: int = 6) -> None:
        """A strap wound in a spiral over a core (rx, ry): one surface whose radius swells along a
        helix, the groove between turns in `groove`. A grip, a haft, a riser."""
        u, v = basis(axis, ref)
        ax = norm(axis)
        count = max(2, int(round(turns * per_turn)) + 1)

        def bump(t, th):
            f = (turns * t - th / (2 * math.pi)) % 1.0
            return 0.5 + 0.5 * math.cos(2 * math.pi * f)

        rings = []
        for i in range(count):
            t = i / (count - 1)
            c = add(centre, mul(ax, -length / 2 + t * length))
            ring = []
            for s in range(segments):
                th = 2 * math.pi * s / segments
                k = 1.0 + ridge * bump(t, th)
                ring.append(add(c, add(mul(u, rx * k * math.cos(th)), mul(v, ry * k * math.sin(th)))))
            rings.append(ring)

        def face_colour(i, j):
            t = (i + 0.5) / (count - 1)
            th = 2 * math.pi * (j + 0.5) / segments
            return groove if bump(t, th) < 0.22 else colour

        self.grid(rings, colour, face_colour=face_colour)

    def nodule(self, centre: Vec, radii: Vec, colour: Rgb, *, axis: Vec = (0.0, 0.0, 1.0), ref: Vec | None = None,
               segments: int = 7, rings: int = 5, jitter: float = 0.12, seed: int = 1, face_colour=None) -> None:
        """A knapped stone or a knuckle: a faceted ellipsoid with seeded jitter, flat-shaded.
        radii = (along u, along v, along the axis)."""
        rng = random.Random(seed)
        u, v = basis(axis, ref)
        ax = norm(axis)
        pts = []
        for r in range(1, rings):
            lat = -math.pi / 2 + math.pi * r / rings
            ring = []
            for s in range(segments):
                th = 2 * math.pi * s / segments + (r % 2) * math.pi / segments
                k = 1.0 + rng.uniform(-jitter, jitter)
                ring.append(add(centre, add(add(mul(u, radii[0] * k * math.cos(lat) * math.cos(th)),
                                                mul(v, radii[1] * k * math.cos(lat) * math.sin(th))),
                                            mul(ax, radii[2] * math.sin(lat)))))
            pts.append(ring)
        self.grid(pts, colour, apex0=add(centre, mul(ax, -radii[2])), apex1=add(centre, mul(ax, radii[2])),
                  face_colour=face_colour)

    def rivet(self, centre: Vec, normal: Vec, radius: float, height: float, colour: Rgb, *, segments: int = 8) -> None:
        """A domed stud standing on a surface (rivets, nail heads, inlaid beads)."""
        n = norm(normal)
        self.lathe([(-height * 0.4, radius * 0.9), (0.0, radius), (height * 0.45, radius * 0.85),
                    (height * 0.8, radius * 0.5), (height, 0.0)], colour, axis=n, centre=centre,
                   segments=segments, smooth=True)

    def feather(self, base: Vec, direction: Vec, side: Vec, length: float, width: float, colour: Rgb,
                tip_colour: Rgb | None = None, quill: Rgb | None = None, thickness: float = 0.012) -> None:
        """A flat vane from `base` along `direction`, widest just past halfway, `side` spanning its
        width; with `tip_colour` the last fifth is a separate barred tip; a quill down the middle."""
        d = norm(direction)
        sd = norm(sub(side, mul(d, dot(side, d))))
        cut = 0.8 if tip_colour else 1.0

        def half(t):  # the vane's half width along its length, 0 at both ends
            return width / 2 * math.sin(math.pi * min(1.0, t) ** 0.8)

        inner = [t for t in (0.15, 0.35, 0.55, 0.7) if t < cut]
        end = [(cut * length, half(cut)), (cut * length, -half(cut))] if cut < 1 else [(length, 0.0)]
        outline = ([(0.0, 0.0)] + [(t * length, half(t)) for t in inner] + end
                   + [(t * length, -half(t)) for t in reversed(inner)])
        self.prism(outline, -thickness / 2, thickness / 2, colour, origin=base, u=d, v=sd)
        if tip_colour:
            wc = half(cut)
            tip = [(cut * length, wc), (length, 0.0), (cut * length, -wc)]
            self.prism(tip, -thickness / 2, thickness / 2, tip_colour, origin=add(base, mul(d, 0.002)), u=d, v=sd)
        if quill:
            w = norm(cross(d, sd))
            q0 = add(base, mul(w, thickness * 0.6))
            self.sweep([add(q0, mul(d, -length * 0.08)), add(q0, mul(d, length * 0.9))],
                       [thickness * 0.9, thickness * 0.35], quill, segments=4, smooth=False)

    def blade(self, z_base: float, z_tip: float, half_width, half_thick, edge: Rgb, face: Rgb, *,
              bevel: float = 0.6, knap: float = 0.0, knap_pitch: float = 0.2, seed: int = 3,
              tip_length: float | None = None, rings_per_unit: float = 6.0, ridge: Rgb | None = None) -> None:
        """A straight double-edged blade from z_base toward -Z to a point at z_tip: width along Y,
        thickness along X, a median ridge on both flats and a bevel band along both edges.

        `half_width(t)` and `half_thick(t)` take t = 0 at the base .. 1 at the tip. `tip_length`
        (studs) is the pointed run, its width eased by cos(pi/2 * s) so the point is sharp but the
        sides stay convex. `knap` > 0 cuts conchoidal scallops into both edges, half a pitch apart,
        and wobbles the bevel line flake by flake: knapped flint. Keep it under a hundredth of a stud
        on a sword: deeper scallops read as a wavy or saw-toothed blade, not a broadsword. Steel
        blades leave it 0. (Flake scars painted dark on the flats were tried and read as square
        dirt patches: the flaking shows through the wobbling bevel line instead.) `ridge`, if given,
        colours the upper half of each flat: a lit and a shaded side of the ridge.
        """
        rng = random.Random(seed)
        total = z_base - z_tip
        tip_length = tip_length if tip_length is not None else total * 0.22
        z_tip0 = z_tip + tip_length
        zs: list[float] = []
        if knap > 0:
            n = max(1, int(round((z_base - z_tip0) / knap_pitch)))
            pitch = (z_base - z_tip0) / n
            for k in range(n):
                for q in range(4):
                    zs.append(z_base - (k + q / 4) * pitch)
        else:
            n = max(2, int(math.ceil((z_base - z_tip0) * rings_per_unit)))
            zs = [z_base - (z_base - z_tip0) * i / n for i in range(n)]
        straight = len(zs)
        tip_rings = 7
        zs += [z_tip0 - tip_length * i / tip_rings for i in range(tip_rings)]
        flake = [rng.uniform(-0.13, 0.13) for _ in range(len(zs) // 4 + 2)]
        deep = [rng.uniform(0.45, 1.3) for _ in range(len(zs) // 4 + 2)]
        rings = []
        for i, z in enumerate(zs):
            t = (z_base - z) / total
            hw, ht = half_width(t), half_thick(t)
            if i >= straight:
                s = (z_tip0 - z) / tip_length
                ease = math.cos(math.pi / 2 * s)
                hw *= ease
                ht *= 0.35 + 0.65 * ease
            up = dn = 0.0
            bw_up = bw_dn = bevel
            if knap > 0 and i < straight:
                q = i % 4
                depth = (0.0, 0.75, 1.0, 0.75)
                up = knap * depth[q] * deep[i // 4]
                dn = knap * depth[(q + 2) % 4] * deep[(i + 2) // 4]
                bw_up += flake[i // 4]
                bw_dn -= flake[i // 4 + 1]
            tb = ht * 0.5
            rings.append([
                (0.0, hw - up, z),
                (tb, (hw - up) * bw_up, z),
                (ht, 0.0, z),
                (tb, -(hw - dn) * bw_dn, z),
                (0.0, -(hw - dn), z),
                (-tb, -(hw - dn) * bw_dn, z),
                (-ht, 0.0, z),
                (-tb, (hw - up) * bw_up, z),
            ])

        def face_colour(i, j):
            if j in (0, 3, 4, 7):
                return edge
            return ridge if (ridge and j in (1, 6)) else face

        self.grid(rings, face, apex1=(0.0, 0.0, z_tip), face_colour=face_colour, cap_colour=face)

    # -- measurement

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _, _ in self.faces)

    def bounds(self) -> tuple[Vec, Vec]:
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi  # type: ignore[return-value]


# --- Blender plumbing -----------------------------------------------------------------------------


def material_for(colour: Rgb, cache: dict):
    if colour in cache:
        return cache[colour]
    mat = bpy.data.materials.new("c_%02x%02x%02x" % colour)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*(palette.srgb_to_linear(c) for c in colour), 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    cache[colour] = mat
    return mat


def build_object(mesh: Mesh, cache: dict):
    used = sorted({c for _, c, _ in mesh.faces})
    data = bpy.data.meshes.new(mesh.name)
    data.from_pydata([(x, -z, y) for (x, y, z) in mesh.verts], [], [idx for idx, _, _ in mesh.faces])
    data.update()
    for colour in used:
        data.materials.append(material_for(colour, cache))
    slot = {colour: i for i, colour in enumerate(used)}
    for poly, (_, colour, smooth) in zip(data.polygons, mesh.faces):
        poly.material_index = slot[colour]
        poly.use_smooth = smooth
    data.uv_layers.new(name="UVMap")  # merge_stages moves these onto the palette swatch
    obj = bpy.data.objects.new(mesh.name, data)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj, out_dir: str) -> None:
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out_dir, f"{obj.name}.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_vertex_color="NONE",
        export_attributes=False,
        export_extras=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_cameras=False,
        export_lights=False,
    )


def palette_card() -> Mesh:
    """One small triangle per swatch, in a row: never a weapon, only the palette's guarantee."""
    m = Mesh(PALETTE_CARD)
    for i, colour in enumerate(palette.swatches().values()):
        x = i * 0.02
        m.face([(x, 0.0, 0.0), (x + 0.01, 0.0, 0.0), (x, 0.01, 0.0)], colour)
    return m


def write_frame(mesh: Mesh, out_dir: str) -> dict:
    lo, hi = mesh.bounds()
    size = [round(hi[i] - lo[i], 3) for i in range(3)]
    record = {
        "model": mesh.name,
        "units": "studs; grip at the origin, tip/muzzle along -Z, top +Y",
        "frame": {k: [round(c, 3) for c in v] for k, v in mesh.frame.items()},
        "bounds": {"min": [round(c, 3) for c in lo], "max": [round(c, 3) for c in hi], "size": size},
        "length": max(size),
        "triangles": mesh.tris,
        "notes": mesh.notes,
    }
    with open(os.path.join(out_dir, mesh.name + FRAME_SUFFIX), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")
    return record


def generate(level: str, pieces: dict, out_dir: str, only: list[str] | None = None) -> int:
    """Build, export and measure every weapon of one level generator, then the palette card."""
    os.makedirs(out_dir, exist_ok=True)
    failures = 0
    for name, make in pieces.items():
        if only and name not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        mesh = make()
        assert mesh.name == name, f"{name}: Mesh is named {mesh.name!r}"
        for key in ("grip", "tip", "holster"):
            if key not in mesh.frame:
                print(f"[{KIT}] WARNING: {name} has no frame point {key!r}", flush=True)
                failures += 1
        for w in mesh.warnings:
            print(f"[{KIT}] WARNING: {name}: {w}", flush=True)
        export(build_object(mesh, {}), out_dir)
        rec = write_frame(mesh, out_dir)
        budget = "" if TRI_TARGET[0] <= mesh.tris <= TRI_TARGET[1] else f" (target {TRI_TARGET[0]}-{TRI_TARGET[1]})"
        if mesh.tris > TRI_CAP:
            print(f"[{KIT}] WARNING: {name} has {mesh.tris} triangles, over the cap of {TRI_CAP}", flush=True)
            failures += 1
        s = rec["bounds"]["size"]
        print(f"[{KIT}] {level}/{name}.glb: {mesh.tris} tris{budget}, {s[0]} x {s[1]} x {s[2]} studs, "
              f"frame {rec['frame']}", flush=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    export(build_object(palette_card(), {}), out_dir)
    print(f"[{KIT}] {PALETTE_CARD}.glb: {len(palette.swatches())} swatches -> {os.path.relpath(out_dir, REPO_ROOT)}", flush=True)
    return 1 if failures else 0


def cli(level: str, pieces: dict, argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=f"Generate the {level} weapons of the weapon kit.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    parser.add_argument("--only", action="append", help="only this model (repeatable)")
    args = parser.parse_args(argv)
    return generate(level, pieces, args.out, args.only)
