"""Fabric buildings for the Orbital Colony growing city (M12 wave 4), generated as a Kenney-style kit.

    py tools/assets/colony_kit.py            # regenerate the GLBs and the blueprints, then check
    py tools/assets/colony_kit.py check      # check only: the rules, the blueprints and GLBs on disk
    blender -b -P tools/assets/colony_kit.py [-- --out <dir>] [--write-blueprints]

Writes one GLB per piece into assets/kenney3d/colony-kit/Models/GLB format/, the folder convention
every Kenney kit uses, so tools/testfit/testfit.py, plotrender.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. The geometry and every check are plain Python; only the
GLB export needs Blender, so under `py` the script shells out to Blender for that one step
(`BLENDER=<path>` overrides the executable, as for plotrender.py).

Why a custom kit (docs/CITY_GROWTH.md sections 3 and 4, INTERFACES "Wave 4.1" and "Wave 4.1b"):
the fabric is the small buildings the client draws on the lots around a player's landmarks, and
they grow pod -> pod cluster -> dome as the colony develops. space-kit's modules are 4 studs to a
unit at the landmarks' scale and every one of them is already a landmark's signature (the hex
gate, the corridor-end module, the round hangar). So the pieces are generated.

**Round forms only** (Ben at the first gate: box bodies with storey bands of windows read as
Metropolis's towers, whatever stood on the roof). Every building is made of capsules, drums,
spheres, domes and vaults, and it grows by adding a round volume, or by being rebuilt wider and
taller with `untilStage` retiring the smaller one, never by adding floors. Windows are portholes,
one glass band on a drum, or a glazed dome or vault. The only boxes are furniture: containers, a
tug, solar trays, planters. One look per district, different in silhouette and not only in colour:

- habitat: white pods and capsules with blue stripes and glass domes (a pea pod budding domes, a
  rotunda with a greenhouse barrel, bubbles stacked on bubbles, a broad dome ringed by petal pods);
- industry: bullet tanks, silos and spheres, orange pipe runs, refinery columns, stacks;
- science: capsule labs under glazed spines, dishes on instrument drums, an observatory dome with
  a cyan shutter, a radar reflector, slim masts;
- port: a round gatehouse, a pale cargo pad, container stacks, vaulted hangars, a gantry crane, a
  round control tower, and (small and medium lots) a parked space-kit cargo craft.

A row of narrow lots draws one district's props many times over, so each district has two narrow
props, A and B, that differ in silhouette at every stage and keep the district's colours: where
the tall part stands on the 8-deep lot, and the signature piece (habitat A a pea pod with its big
dome behind, B a rotunda in front of a greenhouse barrel; industry A bullet tanks, a column behind
and a flare, B spheres, a fat stack in front and a sphere on a stalk; science A a capsule lab with
its dish and mast behind, B an observatory dome in front; port A a control tower in front,
containers and a gantry, B a vaulted hangar with a cupola behind a fuel apron). Their stage
heights stay within about a stud of each other, so a row that alternates them grows evenly.

**Green twins** ("Green the Domes", INTERFACES "Wave 4.1c"): while Life Support is owned, a lot
showing a habitat prop shows `<prop>Green` at the same stage. A twin is the original's builder run
with GREEN set, so its body is the original's, vertex for vertex: only colours change (the lower
panes of every dome and of the greenhouse barrel turn to two greens, a pod's glass band shows
plants at alternate windows, a glazed spine, the pea pod's ridge and the planters' shrubs turn
green), and a few
low garden pieces join on deck the original leaves bare. The glazing is opaque in this art style
(flat palette colours, like every kit here), so "a garden under the glass" is drawn on the panes
themselves. A piece the flag does not touch is shared with the original by name; `check` proves
that a twin's body has its original's shape at every stage, that nothing it adds stands taller
than GARDEN_MAX, and that it shows more green than the original at every stage.

**Units.** Blueprints use `"scale": 2.0`, so that a space-kit cargo craft comes out at half the
landmarks' size (3.0 x 1.8 x 5.0 studs) and fits a lot. Every literal below is in **studs** in the
lot frame and is divided by SCALE once, at export; `check` works in studs too.

**Frames.** Every piece is authored in the lot frame: origin at the lot's bottom-centre, front -Z
(the tube), so a blueprint places all of a prop's own pieces at [0, 0, 0] and its stages register
exactly (the tower-kit pattern). Only the space-kit craft carries a position, computed here from
its measured bounding box, because space-kit origins are offset.

**Stages.** A piece is `<slug>-<stage>` when it stays for good and `<slug>-<stage>-u<last>` when
the blueprint retires it after stage <last> (a pod a wider one replaces, a dome a larger one
swallows, crates a craft lands on). Every piece is closed apart from faces on the deck or on the
roof it stands on, so retiring one never opens a hole.

**The contract, enforced by `check`** (a run with a problem exits 1): the prop fits its lot; an
airlock collar stands flush with the lot front (it docks 0.13 from a tube's ring); a deck plate in
the decking colour covers the lot at every stage; stage 0 is at most 3.4 studs tall, the last stage
at most 11 (narrow, small) or 12.5 (medium), and the height rises at every stage; parallel faces
that overlap stand at least GAP (0.05) apart; no box is thinner than MIN_MEMBER (0.1) in two
dimensions; no dark face lies on the prop's outline (the plot base is (56, 53, 60)); a stage has at
most TRI_BUDGET triangles; and every piece that leaves is replaced by one that joins.

Colours follow orbital_kit.py: space-kit's own factors read raw x 255, plus that kit's glass, solar,
lit and plant accents, written as linear factors so palette.py decodes them back to these bytes.
colony-kit must NOT join palette.SRGB_FACTOR_KITS. Flat shading, axis-aligned boxes, a few sloped
faces and 8-sided solids of revolution with their flats squared to the axes: chunky toy
proportions, like the kits.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "colony-kit"
KITS_ROOT = os.path.join(REPO_ROOT, "assets", "kenney3d")
DEFAULT_OUT = os.path.join(KITS_ROOT, KIT, "Models", "GLB format")
BLUEPRINT_DIR = os.path.join(REPO_ROOT, "tools", "testfit", "blueprints", "_props", "OrbitalColony")
DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
ERA = "OrbitalColony"
SCALE = 2.0  # blueprint scale: one kit unit is two studs

Rgb = tuple[int, int, int]
Box = tuple[float, float, float, float]  # x0, x1, z0, z1

# --- palette ------------------------------------------------------------------------------------
# space-kit's material factors, raw x 255 (orbital_kit.py explains why raw):
HULL = (215, 222, 232)  # "metal": the white hull
PANEL = (172, 181, 197)  # "metalDark": roofs, pads, plinths
TRIM = (255, 160, 52)  # "metalRed": the orange trim
SLATE = (70, 76, 87)  # "dark": door leaves only, never an outline
# orbital-kit's accents:
GLASS = (150, 215, 255)
GLASS_DEEP = (90, 170, 235)
SOLAR = (40, 90, 200)
SOLAR_LINE = (112, 160, 235)
HOLO = (90, 255, 245)
PLANT = (97, 203, 139)
LEAF = (168, 232, 112)  # not a kit colour: a brighter leaf tone beside PLANT, for the Green twins' gardens
LIT = (255, 225, 140)
WARN = (232, 120, 74)
# tube-kit's shell and ring, so a collar reads as part of the tube it docks to:
SHELL = (240, 242, 246)
RING = (190, 196, 206)
# CityDressing.json eras.OrbitalColony.road.tiles.blocks.color: the decking (contract).
DECK = (96, 98, 108)
DARK = {SLATE}
GREENS = {PLANT, LEAF}

HAB = GLASS_DEEP  # the stripe a district's modules wear
IND = TRIM
SCI = HOLO
PORT = TRIM
CRATES = (TRIM, HULL, SOLAR_LINE, WARN)

# --- dimensions (studs) -------------------------------------------------------------------------
LOTS = {"narrow": (4.0, 8.0), "small": (6.0, 6.0), "medium": (8.0, 12.0)}
FINAL_MAX = {"narrow": 11.0, "small": 11.0, "medium": 12.5}
HEIGHT_FLOOR = 3.4  # CityDressing.json eras.OrbitalColony.fabric.heightFloor
TRI_BUDGET = 900
GAP = 0.05  # parallel faces that overlap stand at least this far apart
MIN_MEMBER = 0.1  # nothing the camera sees is thinner than this in two dimensions
MIN_RISE = 0.3  # a stage is at least this much taller than the one before
D = 0.12  # deck top
GARDEN_MAX = 1.3  # nothing a Green twin adds stands taller: its outline above that is its original's
POD = 1.5  # a ground pod's wall: the collar's opening (1.46 above the deck) closes against it
PAD_H = 0.07  # a cargo pad's slab on the deck
SEG = 8
PHASE = math.pi / SEG  # vertices at 22.5 + 45k degrees: four of the eight flats face the axes

# The airlock collar: an arch ring whose front face is flush with the lot front. (u, height above
# the deck) outlines of the ring and of its opening; it stands AL_OUT clear of the wall behind it.
AL_RING = [(-0.96, 0.0), (-0.96, 1.0), (-0.56, 1.68), (0.56, 1.68), (0.96, 1.0), (0.96, 0.0)]
AL_HOLE = [(-0.74, 0.0), (-0.74, 0.92), (-0.46, 1.46), (0.46, 1.46), (0.74, 0.92), (0.74, 0.0)]
AL_OUT = 0.5
AL_BURY = 0.1
AL_RECESS = 0.14

# space-kit pieces a prop may place: bounding box in kit units (testfit --dump-bounds, 2026-10-05)
# and triangles (the GLB's own count; `check` compares it with the file when the kit is on disk).
KENNEY = {
    "craft_cargoA": {"kit": "space-kit", "lo": (1.20, 0.0, 0.27), "hi": (2.80, 0.80, 2.72), "tris": 264},
    "craft_cargoB": {"kit": "space-kit", "lo": (1.25, 0.0, 0.25), "hi": (2.75, 0.90, 2.75), "tris": 380},
}


GREEN = {"on": False}  # set while a Green twin is built: the same builder, a garden under every glass
CROWNS = {1: LEAF, 4: PLANT, 6: LEAF}  # dome facet -> the tree crown a twin shows in its middle band


def log(msg: str) -> None:
    print(f"[{KIT}] {msg}", flush=True)


def rad(width: float) -> float:
    """Circumradius of an 8-gon that is `width` across its flats."""
    return width / 2.0 / math.cos(PHASE)


# --- mesh building (glTF space: X right, Y up, Z back; the front of a lot faces -Z) --------------


def newell(pts) -> tuple[float, float, float]:
    n = [0.0, 0.0, 0.0]
    for i, a in enumerate(pts):
        b = pts[(i + 1) % len(pts)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return (n[0], n[1], n[2])


class Part:
    """Accumulates flat-shaded polygons, each tagged with its sRGB colour."""

    def __init__(self, name: str):
        self.name = name
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[list[int], Rgb]] = []

    def face(self, points, colour: Rgb, centre=None, out=None) -> None:
        """Add a polygon. With `out` (a direction) or `centre` (a point inside the convex solid it
        belongs to) the winding is flipped if needed so the normal points outward."""
        pts = [(float(x), float(y), float(z)) for x, y, z in points]
        if centre is not None or out is not None:
            n = newell(pts)
            if out is None:
                out = [sum(q[i] for q in pts) / len(pts) - centre[i] for i in range(3)]
            if n[0] * out[0] + n[1] * out[1] + n[2] * out[2] < 0:
                pts.reverse()
        base = len(self.verts)
        self.verts.extend(pts)
        self.faces.append(([base + i for i in range(len(pts))], colour))

    def add(self, other: "Part", turn: float = 0.0, at=(0.0, 0.0, 0.0), tilt: float = 0.0) -> None:
        """Copy `other` in, tilted about X, then turned about Y (0 keeps +X, 90 turns it to +Z),
        then moved. Both are proper rotations, so the winding carries over."""
        ct, st = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
        cy, sy = math.cos(math.radians(turn)), math.sin(math.radians(turn))
        base = len(self.verts)
        for x, y, z in other.verts:
            y, z = y * ct - z * st, y * st + z * ct
            x, z = x * cy - z * sy, x * sy + z * cy
            self.verts.append((x + at[0], y + at[1], z + at[2]))
        self.faces.extend(([base + i for i in idx], c) for idx, c in other.faces)

    def bounds(self):
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _ in self.faces)


RODS: list[tuple[float, float, float]] = []  # boxes thin in two dimensions; check() reads it per prop


def cube(p: Part, x0, x1, y0, y1, z0, z1, c: Rgb, skip=(), **sides) -> None:
    """Axis-aligned box with per-face colours (top, bottom, front = -Z, back, left = -X, right) and
    faces to leave out: a face that lies on the deck or against a wall is never drawn."""
    col = {k: sides.get(k, c) for k in ("top", "bottom", "front", "back", "left", "right")}
    dims = sorted((x1 - x0, y1 - y0, z1 - z0))
    if dims[1] < MIN_MEMBER - 1e-6:
        RODS.append((round(x1 - x0, 3), round(y1 - y0, 3), round(z1 - z0, 3)))
    if "back" not in skip:
        p.face([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], col["back"])
    if "front" not in skip:
        p.face([(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)], col["front"])
    if "right" not in skip:
        p.face([(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)], col["right"])
    if "left" not in skip:
        p.face([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], col["left"])
    if "top" not in skip:
        p.face([(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)], col["top"])
    if "bottom" not in skip:
        p.face([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], col["bottom"])


def extrude(p: Part, sect, axis: str, a0, a1, colours, cap0=None, cap1=None, skip=()) -> None:
    """A prism: the convex (u, y) outline `sect` run from a0 to a1 along `axis` ("z": u is x; "x":
    u is z). `colours` is one colour or one per edge (edge i runs from point i to i + 1); `skip`
    lists edges to leave out (the one on the deck); a cap is drawn when it has a colour."""
    n = len(sect)

    def pt(u, y, a):
        return (u, y, a) if axis == "z" else (a, y, u)

    centre = pt(sum(u for u, _ in sect) / n, sum(y for _, y in sect) / n, (a0 + a1) / 2)
    for i in range(n):
        if i in skip:
            continue
        (ua, ya), (ub, yb) = sect[i], sect[(i + 1) % n]
        c = colours[i] if isinstance(colours, list) else colours
        p.face([pt(ua, ya, a0), pt(ub, yb, a0), pt(ub, yb, a1), pt(ua, ya, a1)], c, centre)
    if cap0 is not None:
        p.face([pt(u, y, a0) for u, y in sect], cap0, centre)
    if cap1 is not None:
        p.face([pt(u, y, a1) for u, y in sect], cap1, centre)


def lathe(p: Part, profile, colour, at=(0.0, 0.0, 0.0), top=None, bottom=None, flip=False) -> None:
    """An 8-sided solid of revolution about the vertical axis through `at`. `profile` lists
    (radius, height) bottom to top; `colour` is one colour, one per band, or f(facet, band).
    `flip` turns every face inward: the hollow of a dish."""
    cx, cy, cz = at
    angles = [PHASE + 2 * math.pi * k / SEG for k in range(SEG)]
    rings = [[(cx + r * math.cos(a), cy + y, cz + r * math.sin(a)) for a in angles] for r, y in profile]
    sign = -1.0 if flip else 1.0
    for i in range(len(profile) - 1):
        (r0, y0), (r1, y1) = profile[i], profile[i + 1]
        nr, ny = y1 - y0, r0 - r1
        lo, hi = rings[i], rings[i + 1]
        for k in range(SEG):
            n = (k + 1) % SEG
            am = PHASE + 2 * math.pi * (k + 0.5) / SEG
            if r1 <= 1e-9:
                pts = [lo[k], lo[n], hi[k]]
            elif r0 <= 1e-9:
                pts = [lo[k], hi[n], hi[k]]
            else:
                pts = [lo[k], lo[n], hi[n], hi[k]]
            c = colour(k, i) if callable(colour) else colour[i] if isinstance(colour, list) else colour
            p.face(pts, c, out=(sign * nr * math.cos(am), sign * ny, sign * nr * math.sin(am)))
    if bottom is not None and profile[0][0] > 1e-9:
        p.face(rings[0], bottom, out=(0.0, -sign, 0.0))
    if top is not None and profile[-1][0] > 1e-9:
        p.face(rings[-1], top, out=(0.0, sign, 0.0))


# --- collars, pods and capsules ---------------------------------------------------------------------


def band(p: Part, b: Box, y0, y1, c: Rgb, butt=()) -> None:
    """A stripe GAP proud all round box b: one box, hidden inside b but for its rim. On a `butt`
    side ("front", "back", "left", "right") the box stops GAP short of that wall instead: where
    the stripe of the module standing against it begins, or behind a door, so the two never overlap."""
    x0, x1, z0, z1 = b
    xa = x0 + GAP if "left" in butt else x0 - GAP
    xb = x1 - GAP if "right" in butt else x1 + GAP
    za = z0 + GAP if "front" in butt else z0 - GAP
    zb = z1 - GAP if "back" in butt else z1 + GAP
    cube(p, xa, xb, y0, y1, za, zb, c, skip=tuple(butt))


def airlock(prop: "Prop", p: Part, cx: float) -> None:
    """The docking collar at the lot front: a grey arch ring like a tube's, a dark door leaf and a
    lit transom set back inside it. It stands AL_OUT in front of the wall it serves and runs
    AL_BURY into it."""
    z0 = -prop.d / 2
    zr, z1 = z0 + AL_RECESS, z0 + AL_OUT + AL_BURY
    o = [(cx + u, D + v) for u, v in AL_RING]
    h = [(cx + u, D + v) for u, v in AL_HOLE]
    mid = (cx, D + 0.7, (z0 + z1) / 2)
    for k in range(5):
        (ax, ay), (bx, by), (hx, hy), (gx, gy) = o[k], o[k + 1], h[k + 1], h[k]
        p.face([(ax, ay, z0), (bx, by, z0), (hx, hy, z0), (gx, gy, z0)], SHELL, out=(0, 0, -1))
        p.face([(ax, ay, z1), (bx, by, z1), (hx, hy, z1), (gx, gy, z1)], RING, out=(0, 0, 1))
        p.face([(ax, ay, z0), (bx, by, z0), (bx, by, z1), (ax, ay, z1)], RING, centre=mid)
        inner = [(gx, gy, z0), (hx, hy, z0), (hx, hy, zr), (gx, gy, zr)]
        p.face(inner, RING, out=(cx - (gx + hx) / 2, D + 0.7 - (gy + hy) / 2, 0.0))
    p.face([(h[0][0], h[0][1], zr), (h[5][0], h[5][1], zr), (h[4][0], h[4][1], zr), (h[1][0], h[1][1], zr)],
           SLATE, out=(0, 0, -1))
    p.face([(h[1][0], h[1][1], zr), (h[4][0], h[4][1], zr), (h[3][0], h[3][1], zr), (h[2][0], h[2][1], zr)],
           LIT, out=(0, 0, -1))
    prop.airlocks.append((cx, z0))


DOCK = 0.25  # a docked pod's front stands this far behind the lot front: its stripes clear the collar's door


def dock(prop: "Prop", w: float) -> float:
    """The z centre of a drum w wide that carries the airlock collar: its front flat stands DOCK
    behind the lot front, so the collar runs 0.35 into the drum and its opening closes against it."""
    return -prop.d / 2 + DOCK + w / 2


ARCH = (35.0, 65.0)  # a pod's arch in two bands; it closes with a flat ridge


def pod_profile(hw, sill, rise):
    """(half width, height) up one side of a pod: a straight wall `sill` tall, then an arch of
    `rise` that stops at a flat ridge. The same profile is the pod's cross-section and, turned
    about the vertical, its rounded end."""
    top = math.sin(math.radians(ARCH[-1]))
    wall = [(hw, 0.0), (hw, sill)] if sill > 0 else [(hw, 0.0)]
    return wall + [(hw * math.cos(math.radians(a)), sill + rise * math.sin(math.radians(a)) / top) for a in ARCH]


def half_dome(p: Part, axis: str, a, s, cu, y0, prof, c: Rgb, top: Rgb) -> None:
    """The rounded end of a pod: half an 8-sided dome on profile `prof`, bulging toward s (-1 or
    +1) along `axis` from the plane at a. Its two outer half-flats continue the pod's walls."""
    k = 1.0 / math.cos(PHASE)
    fan = [(0.0, 1.0)] + [(22.5 + 45.0 * j, k) for j in range(4)] + [(180.0, 1.0)]  # (angle, radius factor)

    def pt(r, y, ang, f):
        u = cu + r * f * math.cos(math.radians(ang))
        v = a + s * r * f * math.sin(math.radians(ang))
        return (u, y0 + y, v) if axis == "z" else (v, y0 + y, u)

    centre = pt(prof[0][0] * 0.2, prof[-1][1] * 0.3, 90.0, 1.0)
    for i in range(len(prof) - 1):
        (r0, ya), (r1, yb) = prof[i], prof[i + 1]
        for (g0, f0), (g1, f1) in zip(fan, fan[1:]):
            p.face([pt(r0, ya, g0, f0), pt(r0, ya, g1, f1), pt(r1, yb, g1, f1), pt(r1, yb, g0, f0)], c, centre=centre)
    r, y = prof[-1]
    p.face([pt(r, y, g, f) for g, f in fan], top, out=(0.0, 1.0, 0.0))


def capsule(p: Part, axis: str, a0, a1, cu, y0, w, sill, rise, c: Rgb = HULL, ridge: Rgb | None = None,
            round0: bool = True, round1: bool = True, bays: int = 0) -> float:
    """A pod lying along `axis` from a0 to a1, w wide: straight walls `sill` tall under an arch of
    `rise`, each end rounded into a half dome (or cut flat, where it runs into something). `ridge`
    colours the flat ridge (a glazed spine); `bays` glazes the arch of the straight part in that
    many bays of two blues (a greenhouse). Open underneath: it stands on the deck. Returns the top."""
    hw = w / 2
    prof = pod_profile(hw, sill, rise)
    m = len(prof) - 1
    sect = [(cu + r, y0 + y) for r, y in prof] + [(cu - r, y0 + y) for r, y in reversed(prof)]
    b0, b1 = a0 + (hw if round0 else 0.0), a1 - (hw if round1 else 0.0)
    n = max(bays, 1)
    cuts = [b0 + (b1 - b0) * i / n for i in range(n + 1)]
    spine = LEAF if GREEN["on"] and ridge == GLASS else ridge or c  # a twin plants its glazed spine
    for i in range(n):
        tones = [(GLASS, GLASS_DEEP)[i % 2] if bays else c] * len(ARCH)
        if bays and GREEN["on"]:
            tones[0] = (PLANT, LEAF)[i % 2]  # a twin's crops stand against the lower panes
        side = ([c] if sill > 0 else []) + tones
        extrude(p, sect, axis, cuts[i], cuts[i + 1], side + [spine] + side[::-1] + [c],
                cap0=c if i == 0 and not round0 else None, cap1=c if i == n - 1 and not round1 else None,
                skip=(2 * m + 1,))
    for a, s, on in ((b0, -1.0, round0), (b1, 1.0, round1)):
        if on:
            half_dome(p, axis, a, s, cu, y0, prof, c, spine)
    return y0 + sill + rise


def belt(p: Part, axis: str, a, cu, y0, w, sill, rise, c: Rgb, width: float = 0.3) -> None:
    """A stripe GAP proud round a capsule of these measures, `width` along it at a."""
    prof = pod_profile(w / 2 + GAP, sill, rise + GAP)
    sect = [(cu + r, y0 + y) for r, y in prof] + [(cu - r, y0 + y) for r, y in reversed(prof)]
    extrude(p, sect, axis, a - width / 2, a + width / 2, c, cap0=c, cap1=c, skip=(len(sect) - 1,))


def porthole(p: Part, axis: str, a, wall, side, y, r: float = 0.3, c: Rgb = LIT) -> None:
    """A round window GAP proud of the straight wall of a capsule that runs along `axis`: the wall
    stands at lateral `wall` and faces `side` (-1 or +1). A grey rim and a lit pane."""
    lo, hi = sorted((wall, wall + side * GAP))
    extrude(p, octagon(a, y, r), "x" if axis == "z" else "z", lo, hi, RING, cap0=c if side < 0 else None,
            cap1=c if side > 0 else None)


# --- round things -------------------------------------------------------------------------------


def drum(p: Part, cx, cz, y0, w, h, c: Rgb = HULL, top: Rgb = PANEL) -> None:
    lathe(p, [(rad(w), 0.0), (rad(w), h)], c, at=(cx, y0, cz), top=top)


def cone(p: Part, cx, cz, y0, w, h, c: Rgb = PANEL) -> None:
    """A shallow roof on a drum of width w."""
    lathe(p, [(rad(w), 0.0), (rad(w) * 0.4, h)], c, at=(cx, y0, cz), top=c)


def hoop(p: Part, cx, cz, y0, y1, w, c, rim: Rgb | None = None) -> None:
    """A stripe GAP proud of a drum of width w: one colour, or f(facet, band) with `rim` for its
    top. Its top is closed; its underside is a 0.05 rim that only shows from straight below, and is
    left out."""
    r = rad(w + 2 * GAP)
    lathe(p, [(r, 0.0), (r, y1 - y0)], c, at=(cx, y0, cz), top=rim or c)


def pod(p: Part, cx, cz, y0, w, h, stripe: Rgb | None, glass=(0.5, 0.95)) -> None:
    """A round pod: a white drum with one glass band (heights above y0) and its district stripe
    under the roof line. Never rows of windows: a pod grows by being rebuilt wider, not by floors."""
    drum(p, cx, cz, y0, w, h)
    if glass and GREEN["on"]:  # a twin's plants show at alternate windows
        hoop(p, cx, cz, y0 + glass[0], y0 + glass[1], w, lambda k, i: (GLASS, PLANT, GLASS, LEAF)[k % 4], rim=GLASS)
    elif glass:
        hoop(p, cx, cz, y0 + glass[0], y0 + glass[1], w, GLASS)
    if stripe:
        hoop(p, cx, cz, y0 + h - 0.36, y0 + h - 0.16, w, stripe)


def dome_profile(r, y0, y1, bands, a_max=70.0):
    """A faceted hemisphere flattened into `bands` rings; it stops short of the pole and closes
    with a flat cap."""
    am = math.radians(a_max)
    return [(r * math.cos(am * i / bands), y0 + (y1 - y0) * math.sin(am * i / bands) / math.sin(am))
            for i in range(bands + 1)]


def dome(p: Part, cx, cz, y0, w, h, bands: int = 3, ring: float = 0.25, ribs: bool = True,
         panes=(GLASS, GLASS_DEEP), slit=None) -> None:
    """A dome w across and h tall on a white base ring: panes in two colours (glass by default), a
    white cap and white ribs GAP proud of the eight meridians (0.14 wide, so they hold at the tycoon
    camera). `slit` = (facet, colour) paints one facet from rim to cap: an observatory's shutter
    (facet 5 faces the lot front)."""
    lathe(p, [(rad(w), 0.0), (rad(w), ring)], HULL, at=(cx, y0, cz), top=HULL)
    prof = dome_profile(rad(w - 0.16), ring, h, bands)
    garden = GREEN["on"] and slit is None and panes == (GLASS, GLASS_DEEP)

    def pane(k, i):
        """A twin's garden stands against the glass: the lowest band in two greens, and in a
        three-band dome three tree crowns reach up the middle one (unevenly spaced, one of them
        on the side the tycoon camera sees), under glass that stays blue."""
        if slit and k == slit[0]:
            return slit[1]
        if garden and i == 0:
            return (PLANT, LEAF)[k % 2]
        if garden and i == 1 and bands >= 3 and k in CROWNS:
            return CROWNS[k]
        return panes[(k + i) % 2]

    lathe(p, prof, pane, at=(cx, y0, cz), top=HULL)
    if not ribs:
        return
    for k in range(SEG):
        a = PHASE + 2 * math.pi * k / SEG
        ca, sa = math.cos(a), math.sin(a)
        for i in range(bands):
            (r0, ya), (r1, yb) = prof[i], prof[i + 1]
            nr, ny = yb - ya, r0 - r1
            ln = math.hypot(nr, ny)
            nr, ny = nr / ln * GAP, ny / ln * GAP
            quad = [(cx + (r + nr) * ca - s * 0.07 * sa, y0 + yy + ny, cz + (r + nr) * sa + s * 0.07 * ca)
                    for r, yy, s in ((r0, ya, -1), (r0, ya, 1), (r1, yb, 1), (r1, yb, -1))]
            p.face(quad, HULL, out=(ca * nr, ny, sa * nr))


def tank_v(p: Part, cx, cz, y0, w, h, stripe: Rgb | None = TRIM, at: float = 0.45) -> None:
    """A silo: a white drum that closes into a shoulder and a grey cap, an orange stripe."""
    r = rad(w)
    lathe(p, [(r, 0.0), (r, h - 0.3 * w), (r * 0.45, h)], HULL, at=(cx, y0, cz), top=PANEL)
    if stripe:
        hoop(p, cx, cz, y0 + h * at, y0 + h * at + 0.22, w, stripe)


def octagon(cu, cy, r):
    return [(cu + r * math.cos(PHASE + k * math.pi / 4), cy + r * math.sin(PHASE + k * math.pi / 4)) for k in range(8)]


def tank_h(p: Part, axis: str, a0, a1, cu, y0, w, stripe: Rgb | None = TRIM, clear: float = 0.22) -> None:
    """A bullet tank lying along `axis` on two saddles, `clear` above y0, with an orange stripe."""
    cy = y0 + clear + w / 2
    extrude(p, octagon(cu, cy, rad(w)), axis, a0, a1, HULL, cap0=PANEL, cap1=PANEL)
    for a in (a0 + 0.4, a1 - 0.7):
        lo, hi, top = cu - w * 0.36, cu + w * 0.36, cy - w * 0.33
        if axis == "x":
            cube(p, a, a + 0.3, y0, top, lo, hi, PANEL, skip=("bottom", "top"))
        else:
            cube(p, lo, hi, y0, top, a, a + 0.3, PANEL, skip=("bottom", "top"))
    if stripe:
        am = (a0 + a1) / 2
        extrude(p, octagon(cu, cy, rad(w + 2 * GAP)), axis, am - 0.15, am + 0.15, stripe, cap0=stripe, cap1=stripe)


def platform(p: Part, cx, cz, y, w, rim: Rgb = TRIM, t: float = 0.14) -> None:
    """A service deck round a column: an 8-sided plate with an orange rim."""
    lathe(p, [(rad(w), 0.0), (rad(w), t)], rim, at=(cx, y, cz), top=PANEL, bottom=PANEL)


def column(p: Part, cx, cz, y0, y1, w, stripes=(), decks=(), deck_w=None) -> None:
    """A refinery column from y0 to y1 with orange stripes and service decks at the given heights."""
    drum(p, cx, cz, y0, w, y1 - y0)
    for yb in stripes:
        hoop(p, cx, cz, yb, yb + 0.25, w, TRIM)
    for yd in decks:
        platform(p, cx, cz, yd, deck_w or w + 0.9)


def stack(p: Part, cx, cz, y0, y1, w0, w1, tip: Rgb | None = WARN, tip_h: float = 0.5) -> None:
    """A tapering flue from y0 to y1; `tip` is the warning band round its mouth."""
    body = y1 - y0 - (tip_h if tip else 0.0)
    lathe(p, [(rad(w0), 0.0), (rad(w1), body)], HULL, at=(cx, y0, cz), top=PANEL)
    if tip:
        r = rad(w1 + 0.14)
        lathe(p, [(r, 0.0), (r, tip_h)], tip, at=(cx, y0 + body, cz), top=PANEL, bottom=tip)


def sphere(p: Part, cx, cz, y0, w, stand: float = 0.5, stalk: Rgb = PANEL, slim: bool = False,
           belt: Rgb = TRIM) -> None:
    """A sphere on a pedestal half its width, with an equator in `belt` (orange: a tank; cyan: a
    radome). A long `stand` makes the pedestal a stalk, and `slim` narrows the equator to a belt on
    a white ball. The top is y0 + stand + 0.88 w."""
    r = w / 2 / math.cos(PHASE)
    cy = y0 + stand + w * 0.44
    drum(p, cx, cz, y0, w * 0.5, stand + w * 0.1, stalk, PANEL)
    prof = [(r * math.cos(math.radians(a)), w * 0.44 / math.sin(math.radians(62)) * math.sin(math.radians(a)))
            for a in ((-62, -22, -8, 8, 22, 62) if slim else (-62, -22, 22, 62))]
    lathe(p, prof, [HULL, HULL, belt, HULL, HULL] if slim else [HULL, belt, HULL], at=(cx, cy, cz), top=PANEL,
          bottom=PANEL)


def pipe(p: Part, pts, c: Rgb = TRIM, r: float = 0.11) -> None:
    """A square pipe through axis-aligned points. Each leg starts where the last one ended, so no
    two legs overlap and no two of their faces share a plane."""
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        axis = max(range(3), key=lambda k: abs(b[k] - a[k]))
        s = 1.0 if b[axis] > a[axis] else -1.0
        lo = [a[k] - r for k in range(3)]
        hi = [a[k] + r for k in range(3)]
        start = a[axis] + (s * r if i > 0 else 0.0)
        end = b[axis] + (s * r if i < len(pts) - 2 else 0.0)
        lo[axis], hi[axis] = min(start, end), max(start, end)
        cube(p, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], c)


# --- instruments --------------------------------------------------------------------------------


def mast(p: Part, x, z, y0, h, arms=(0.62, 0.84), tip: Rgb = WARN, foot: float = 0.0) -> float:
    """A slim mast with cross-arms and a coloured tip; `foot` is a thicker lower length. The arms
    stand GAP proud of the pole on both faces. Returns the top."""
    r = 0.07
    if foot:
        cube(p, x - 0.13, x + 0.13, y0, y0 + foot, z - 0.13, z + 0.13, PANEL, skip=("bottom",))
    cube(p, x - r, x + r, y0 + foot, y0 + h, z - r, z + r, HULL, skip=("bottom",))
    for k in arms:
        yy = y0 + h * k
        half = 0.28 + 0.4 * (1.0 - k)
        cube(p, x - half, x + half, yy, yy + 0.12, z - r - GAP, z + r + GAP, PANEL)
    cube(p, x - 0.13, x + 0.13, y0 + h, y0 + h + 0.26, z - 0.13, z + 0.13, tip, skip=("bottom",))
    return y0 + h + 0.26


def dish(p: Part, x, z, y0, w, turn: float = 270.0, tilt: float = 40.0, stand: float = 0.5) -> float:
    """A dish w across on a short pedestal, looking up and toward `turn` (270 is the lot front).
    Two shells, one facing each way, because a MeshPart culls back faces. Returns the top."""
    cube(p, x - 0.16, x + 0.16, y0, y0 + stand, z - 0.16, z + 0.16, PANEL, skip=("bottom",))
    r, depth = w / 2, 0.28 * w
    sub = Part("")
    lathe(sub, [(0.14, 0.0), (r, depth)], PANEL, bottom=PANEL)
    lathe(sub, [(0.14, 0.06), (r, depth)], SHELL, bottom=SHELL, flip=True)
    cube(sub, -0.06, 0.06, 0.06, depth + 0.2, -0.06, 0.06, PANEL, skip=("bottom",))
    cube(sub, -0.13, 0.13, depth + 0.2, depth + 0.42, -0.13, 0.13, TRIM)
    # tilt about X leans the axis toward +Z; a quarter turn less brings +Z round to `turn`
    t = math.radians(tilt)
    hub = y0 + stand + r * math.sin(t) - depth * math.cos(t) + 0.1  # the low rim clears the pedestal
    p.add(sub, turn - 90.0, (x, hub, z), tilt)
    return max(v[1] for v in p.verts)


def reflector(p: Part, x, z, y0, w, h, stand: float = 0.4) -> float:
    """A radar reflector looking toward the lot front: a white centre panel between two wings
    folded 30 degrees forward (GAP shorter at top and bottom, so their ends never share a plane
    with the centre's where they meet), grey behind, a cyan top edge, and a cyan feed on a boom.
    About 0.97 w across. Returns the top."""
    cube(p, x - 0.16, x + 0.16, y0, y0 + stand, z - 0.16, z + 0.16, PANEL, skip=("bottom",))
    ya, yb = y0 + stand, y0 + stand + h
    c, wing, t = 0.2 * w, 0.33 * w, 0.07
    cube(p, x - c, x + c, ya, yb, z - t, z + t, HULL, front=SHELL, back=PANEL, top=HOLO)
    # a wing is built along +X from the hinge and turned; its face toward the feed is its front on
    # the right wing and its back on the left one
    for side, turn, face, behind in ((1, -30.0, "front", "back"), (-1, 210.0, "back", "front")):
        sub = Part("")
        cube(sub, 0.0, wing, ya + GAP, yb - GAP, -t, t, HULL, skip=("left",), top=HOLO, **{face: SHELL, behind: PANEL})
        p.add(sub, turn, (x + side * c, 0.0, z))
    yf, zf = ya + h * 0.4, z - t - 0.4 * w
    cube(p, x - 0.06, x + 0.06, yf, yf + 0.12, zf, z - t, PANEL, skip=("back",))
    cube(p, x - 0.13, x + 0.13, yf - 0.07, yf + 0.19, zf - 0.26, zf, HOLO)
    return yb


def scope(p: Part, cx, cz, y0, w, dh) -> None:
    """A telescope barrel out through the shutter of an observatory dome w across and dh tall that
    stands on y0: white, a cyan ring and a cyan lens, aimed 62 degrees up over the lot front. It
    starts inside the dome and stands about 0.7 clear of the glass, half a stud above the dome's
    top: aimed any lower it would either hide in the shutter or leave the lot."""
    length = w * 0.5 + 0.6
    sub = Part("")
    lathe(sub, [(0.36, 0.6), (0.36, length)], HULL, top=HOLO)
    lathe(sub, [(0.43, length - 0.45), (0.43, length - 0.2)], HOLO, top=HOLO, bottom=HOLO)
    p.add(sub, 180.0, (cx, y0 + 0.15 * dh, cz), 28.0)


def solar(p: Part, x0, x1, z0, z1, y, cols: int, rows: int) -> None:
    """A flat roof array: a white tray, its floor in the pale cell-line blue, dark blue cells."""
    cube(p, x0, x1, y, y + 0.08, z0, z1, HULL, skip=("bottom",), top=SOLAR_LINE)
    m = 0.1
    for i in range(cols):
        for j in range(rows):
            xa = x0 + (x1 - x0) * i / cols + m
            xb = x0 + (x1 - x0) * (i + 1) / cols - m
            za = z0 + (z1 - z0) * j / rows + m
            zb = z0 + (z1 - z0) * (j + 1) / rows - m
            cube(p, xa, xb, y + 0.08, y + 0.14, za, zb, SOLAR, skip=("bottom",))


def planter(p: Part, x0, x1, z0, z1, y) -> None:
    """A habitat's garden tray: white walls, a green bed, a row of shrubs (leaf green on a twin)."""
    cube(p, x0, x1, y, y + 0.28, z0, z1, HULL, skip=("bottom",), top=PLANT)
    shrub = LEAF if GREEN["on"] else PLANT
    along_x = (x1 - x0) >= (z1 - z0)
    n = max(1, min(4, int(max(x1 - x0, z1 - z0) / 0.48)))
    s = 0.17
    for i in range(n):
        k = (i + 0.5) / n
        cx = x0 + (x1 - x0) * k if along_x else (x0 + x1) / 2
        cz = (z0 + z1) / 2 if along_x else z0 + (z1 - z0) * k
        cube(p, cx - s, cx + s, y + 0.28, y + 0.28 + 2 * s, cz - s, cz + s, shrub, skip=("bottom",))


def mound(p: Part, cx, cz, y, w, h, c: Rgb = LEAF) -> None:
    """A clipped shrub: one faceted green mass, the size a garden needs to read at the tycoon camera."""
    r = rad(w)
    lathe(p, [(r * 0.8, 0.0), (r, h * 0.45), (r * 0.5, h)], c, at=(cx, y, cz), top=c)


def beacon(p: Part, x, z, y, c: Rgb = LIT) -> float:
    """A roof lamp: a grey foot and a lit block. Returns the top."""
    cube(p, x - 0.22, x + 0.22, y, y + 0.12, z - 0.22, z + 0.22, PANEL, skip=("bottom",))
    cube(p, x - 0.14, x + 0.14, y + 0.12, y + 0.42, z - 0.14, z + 0.14, c, skip=("bottom",))
    return y + 0.42


def lamp_mast(p: Part, x, z, y0, h) -> float:
    """A yard floodlight: a white post and a lit head under a grey hood. Returns the top."""
    cube(p, x - 0.08, x + 0.08, y0, y0 + h, z - 0.08, z + 0.08, HULL, skip=("bottom",))
    cube(p, x - 0.3, x + 0.3, y0 + h, y0 + h + 0.24, z - 0.2, z + 0.2, LIT, top=PANEL)
    return y0 + h + 0.24


# --- the port's furniture -----------------------------------------------------------------------


def pad(p: Part, b: Box, mark: Rgb = TRIM) -> float:
    """A cargo pad: a pale slab on the deck with an orange square at each corner. A square is its
    top face alone, 0.06 above the slab: containers stand on it, and a side face would lie GAP or
    less inside theirs. Returns the slab's top."""
    x0, x1, z0, z1 = b
    top = D + PAD_H
    cube(p, x0, x1, D, top, z0, z1, PANEL, skip=("bottom",))
    m = 0.5
    for xa in (x0 + 0.12, x1 - 0.12 - m):
        for za in (z0 + 0.12, z1 - 0.12 - m):
            cube(p, xa, xa + m, top, top + 0.06, za, za + m, mark,
                 skip=("bottom", "front", "back", "left", "right"))
    return top


def crates(p: Part, x, z, y, colours, along: str = "x", length: float = 1.6, width: float = 0.8,
           h: float = 0.75) -> float:
    """A stack of containers, one colour each, bottom to top, lying along `along`. Returns the top."""
    hx, hz = (length / 2, width / 2) if along == "x" else (width / 2, length / 2)
    for k, c in enumerate(colours):
        cube(p, x - hx, x + hx, y + k * h, y + (k + 1) * h, z - hz, z + hz, c, skip=("bottom",),
             top=PANEL if c != PANEL else HULL)
    return y + len(colours) * h


def end_slab(p: Part, axis: str, a, s, d0, d1, u0, u1, y0, y1, c: Rgb) -> None:
    """A slab on the end of a prism that runs along `axis`: it lies between d0 and d1 beyond the
    end plane at `a` on side s (-1 the low end, +1 the high end); its face toward the wall is left
    out."""
    lo, hi = sorted((a + s * d0, a + s * d1))
    if axis == "z":
        cube(p, u0, u1, y0, y1, lo, hi, c, skip=("back" if s < 0 else "front",))
    else:
        cube(p, lo, hi, y0, y1, u0, u1, c, skip=("right" if s < 0 else "left",))


def hangar(p: Part, b: Box, y0, sill, rise, axis: str = "z", door_end: int = 0) -> float:
    """A vaulted cargo hangar over box b: white walls `sill` tall under a grey barrel vault of
    `rise`, and on one end a grey roller door with two orange stripes under a lit strip. An orange
    stripe runs round the foot of the walls, and the far end has two lit portholes. Returns the top."""
    x0, x1, z0, z1 = b
    u0, u1, a0, a1 = (x0, x1, z0, z1) if axis == "z" else (z0, z1, x0, x1)
    hw, cu = (u1 - u0) / 2, (u0 + u1) / 2
    crown = math.sin(math.radians(72))
    arch = [(cu + hw * math.cos(math.radians(a)), y0 + sill + rise * min(1.0, math.sin(math.radians(a)) / crown))
            for a in (0, 36, 72, 108, 144, 180)]
    extrude(p, [(u0, y0), (u1, y0)] + arch, axis, a0, a1, [HULL, HULL] + [PANEL] * 5 + [HULL], cap0=HULL, cap1=HULL,
            skip=(0,))
    a, s = (a0, -1) if door_end == 0 else (a1, 1)
    dw, dh = 0.3 * (u1 - u0), sill + 0.3 * rise
    end_slab(p, axis, a, s, 0.0, GAP, cu - dw, cu + dw, y0, y0 + dh, PANEL)
    for k in (0.22, 0.58):
        end_slab(p, axis, a, s, GAP, 2 * GAP, cu - dw, cu + dw, y0 + dh * k, y0 + dh * k + 0.22, TRIM)
    end_slab(p, axis, a, s, 0.0, GAP, cu - dw, cu + dw, y0 + dh + 0.12, y0 + dh + 0.36, LIT)
    door_side = {("z", 0): "front", ("z", 1): "back", ("x", 0): "left", ("x", 1): "right"}[(axis, door_end)]
    band(p, b, y0 + 0.25, y0 + 0.47, TRIM, butt=(door_side,))
    far, lo, hi = (a1, a1, a1 + GAP) if door_end == 0 else (a0, a0 - GAP, a0)
    for k in (-1, 1):
        extrude(p, octagon(cu + k * dw, y0 + 0.95, 0.28), axis, lo, hi, RING, cap0=LIT if far == a0 else None,
                cap1=LIT if far == a1 else None)
    return y0 + sill + rise


def gantry(p: Part, x0, x1, zc, y0, yb, load_x, load: Rgb | None, drop: float = 1.3) -> float:
    """A portal crane across X at depth zc: white legs, an orange beam at yb, a grey trolley, and a
    container hanging `drop` under the beam. Returns the top."""
    leg = 0.24
    for xa in (x0, x1 - leg):
        cube(p, xa, xa + leg, y0, yb, zc - leg / 2, zc + leg / 2, HULL, skip=("bottom", "top"))
    cube(p, x0, x1, yb, yb + 0.35, zc - 0.2, zc + 0.2, TRIM)
    cube(p, load_x - 0.3, load_x + 0.3, yb + 0.35, yb + 0.6, zc - 0.28, zc + 0.28, PANEL, skip=("bottom",))
    if load:
        cube(p, load_x - 0.06, load_x + 0.06, yb - drop, yb, zc - 0.06, zc + 0.06, PANEL, skip=("top", "bottom"))
        cube(p, load_x - 0.7, load_x + 0.7, yb - drop - 0.7, yb - drop, zc - 0.4, zc + 0.4, load, top=PANEL)
    return yb + 0.6


def tug(p: Part, x, z, y) -> None:
    """A fuel tug parked nose to the hangar (+Z): a grey chassis, an orange cab with a glass
    front, and a white tank behind it."""
    cube(p, x - 0.5, x + 0.5, y, y + 0.3, z - 0.9, z + 0.9, PANEL, skip=("bottom",))
    cube(p, x - 0.45, x + 0.45, y + 0.3, y + 0.85, z + 0.3, z + 0.85, WARN, skip=("bottom",), back=GLASS, top=PANEL)
    extrude(p, octagon(x, y + 0.6, rad(0.6)), "z", z - 0.85, z + 0.2, HULL, cap0=PANEL, cap1=PANEL)


def tower(p: Part, cx, cz, y0, y1, y2, shaft: float = 1.2, cab: float = 2.2) -> float:
    """A control tower: a round white shaft from y0 to y1, then a wider round cab to y2 with a glass
    band all round, a grey roof and a lit beacon. Returns the top."""
    drum(p, cx, cz, y0, shaft, y1 - y0)
    lathe(p, [(rad(cab), 0.0), (rad(cab), y2 - y1)], HULL, at=(cx, y1, cz), top=PANEL, bottom=PANEL)
    hoop(p, cx, cz, y1 + 0.3, y2 - 0.25, cab, GLASS)
    return beacon(p, cx, cz, y2)


# --- props --------------------------------------------------------------------------------------


class Prop:
    """One fabric building: its pieces by (stage, last stage or None) and its space-kit pieces. A
    Green twin also has garden pieces, which only it draws, and knows its original."""

    def __init__(self, pid: str, lot: str, green: bool = False):
        self.id = pid
        self.lot = lot
        self.green = green
        self.original: Prop | None = None
        self.gardens: dict[tuple[int, int | None], Part] = {}
        self.w, self.d = LOTS[lot]
        name = pid[len("Fabric"):]
        self.slug = "".join(("-" + ch.lower()) if ch.isupper() else ch for ch in name).lstrip("-")
        self.parts: dict[tuple[int, int | None], Part] = {}
        self.kenney: list[dict] = []
        self.airlocks: list[tuple[float, float]] = []

    def part(self, stage: int, until: int | None = None) -> Part:
        key = (stage, until)
        if key not in self.parts:
            self.parts[key] = Part(f"{self.slug}-{stage}" + ("" if until is None else f"-u{until}"))
        return self.parts[key]

    def garden(self, stage: int, until: int | None = None) -> Part | None:
        """The piece a Green twin's garden furniture goes on, or None while the original is built."""
        if not self.green:
            return None
        key = (stage, until)
        if key not in self.gardens:
            self.gardens[key] = Part(f"{self.slug}-{stage}" + ("" if until is None else f"-u{until}") + "-garden")
        return self.gardens[key]

    def share(self, original: "Prop") -> None:
        """Name every piece the flag left untouched after the original's: one GLB serves both."""
        self.original = original
        for key, part in self.parts.items():
            same = original.parts.get(key)
            if same is not None and (same.verts, same.faces) == (part.verts, part.faces):
                part.name = same.name

    def craft(self, model: str, x, z, y, turn: int, stage: int, until: int | None = None) -> None:
        """Park a space-kit craft with its bounding box centred on (x, z), standing on y, nose
        toward -Z at turn 0. space-kit origins are offset, so the position is worked out from the
        measured box (tools/testfit/README.md, space-kit notes)."""
        k = KENNEY[model]
        ox, oz = (k["lo"][0] + k["hi"][0]) / 2, (k["lo"][2] + k["hi"][2]) / 2
        t = math.radians(turn)
        pos = [x / SCALE - (ox * math.cos(t) + oz * math.sin(t)), y / SCALE - k["lo"][1],
               z / SCALE - (-ox * math.sin(t) + oz * math.cos(t))]
        hx, hz = (k["hi"][0] - k["lo"][0]) / 2 * SCALE, (k["hi"][2] - k["lo"][2]) / 2 * SCALE
        if turn % 180:
            hx, hz = hz, hx
        self.kenney.append({
            "kit": k["kit"], "model": model, "pos": [round(v, 4) for v in pos], "rotY": turn, "stage": stage,
            "until": until, "tris": k["tris"],
            "lo": (x - hx, y, z - hz), "hi": (x + hx, y + (k["hi"][1] - k["lo"][1]) * SCALE, z + hz),
        })

    def pieces(self):
        """Own pieces in blueprint order: by stage, the staying piece first, a garden after its body."""
        both = [(key, 0, part) for key, part in self.parts.items()]
        both += [(key, 1, part) for key, part in self.gardens.items()]
        both.sort(key=lambda t: (t[0][0], t[1], -1 if t[0][1] is None else t[0][1]))
        return [(key, part) for key, _, part in both]

    def present(self, k: int) -> list[Part]:
        return [part for (stage, until), part in self.pieces() if stage <= k and (until is None or k <= until)]

    def kenney_at(self, k: int) -> list[dict]:
        return [c for c in self.kenney if c["stage"] <= k and (c["until"] is None or k <= c["until"])]


def hab_narrow_a(P: Prop) -> None:
    """A white pea pod along the lot, then rebuilt at full length; glass domes bud through its
    ridge like peas, the one at the back swallowed by a wider one at every stage until it stands on
    its own drum under a lantern. Low in front, tall behind."""
    zf = -P.d / 2
    bed = PLANT if GREEN["on"] else None  # a twin plants the pod's ridge between its domes
    airlock(P, P.part(0), 0.0)
    q = P.part(0, 0)
    capsule(q, "z", zf + DOCK, 1.0, 0.0, D, 3.2, 0.9, 1.1, ridge=bed)
    belt(q, "z", -0.9, 0.0, D, 3.2, 0.9, 1.1, HAB)
    for s in (-1, 1):
        porthole(q, "z", -1.8, s * 1.6, s, D + 0.5)
    planter(q, -1.4, 1.4, 1.9, 2.6, D)
    g = P.garden(0, 0)
    if g:  # the yard behind the first pod, until the long pod covers it
        planter(g, -1.4, 1.4, 3.0, 3.7, D)
        for sx in (-1, 1):
            mound(g, sx * 1.5, 1.45, D, 0.8, 0.9)
    p = P.part(1)
    capsule(p, "z", zf + DOCK, 3.8, 0.0, D, 3.4, 1.0, 1.3, ridge=bed)
    for z in (-1.75, 1.75):
        belt(p, "z", z, 0.0, D, 3.4, 1.0, 1.3, HAB)
    for s in (-1, 1):
        for z in (-0.9, 0.5):
            porthole(p, "z", z, s * 1.7, s, D + 0.55)
    dome(P.part(1, 1), 0.0, 1.5, 2.0, 2.2, 1.25, bands=2)
    dome(P.part(2, 2), 0.0, 1.6, 1.9, 3.0, 1.9)
    dome(P.part(2, 3), 0.0, -1.3, 2.05, 2.0, 1.1, bands=2)
    dome(P.part(3, 3), 0.0, 1.7, 1.8, 3.4, 2.5)
    p = P.part(4)
    pod(p, 0.0, 2.05, D, 3.6, 2.6, HAB, glass=(1.2, 1.7))
    dome(p, 0.0, 2.05, D + 2.6, 3.6, 2.3)
    drum(p, 0.0, 2.05, 4.85, 1.4, 0.5)
    dome(p, 0.0, 2.05, 5.35, 1.4, 0.8, bands=2, ring=0.15, ribs=False)
    dome(p, 0.0, -1.3, 2.0, 2.4, 1.4, bands=2)


def hab_narrow_b(P: Prop) -> None:
    """A round pod in front and a greenhouse barrel behind it; both are rebuilt wider and taller,
    the pod under a glass dome that ends as a rotunda with a spire, and last a dome buds through
    the greenhouse's ridge. Tall in front where A is tall behind."""
    airlock(P, P.part(0), 0.0)
    z0 = dock(P, 3.0)
    pod(P.part(0, 1), 0.0, z0, D, 3.0, POD, HAB)
    q = P.part(0, 0)
    cone(q, 0.0, z0, D + POD, 3.0, 0.5)
    capsule(q, "z", -0.3, 3.8, 0.0, D, 2.6, 0.5, 0.9, bays=2)
    g = P.garden(0, 0)
    if g:  # beds beside the first greenhouse, until the wider one covers them
        for sx in (-1, 1):
            planter(g, sx * 1.7 - 0.25, sx * 1.7 + 0.25, 0.9, 3.3, D)
    dome(P.part(1, 1), 0.0, z0, D + POD, 3.0, 1.6, bands=2)
    capsule(P.part(1, 2), "z", -0.5, 3.8, 0.0, D, 3.4, 0.8, 1.4, bays=2)
    q = P.part(2, 2)
    pod(q, 0.0, dock(P, 3.6), D, 3.6, 1.9, HAB, glass=(0.8, 1.3))
    dome(q, 0.0, dock(P, 3.6), D + 1.9, 3.6, 1.9)
    capsule(P.part(3), "z", -0.3, 3.8, 0.0, D, 3.8, 1.1, 1.6, round0=False, bays=2)
    q = P.part(3, 3)
    pod(q, 0.0, dock(P, 3.8), D, 3.8, 2.4, HAB, glass=(1.0, 1.5))
    dome(q, 0.0, dock(P, 3.8), D + 2.4, 3.8, 2.1)
    p = P.part(4)
    pod(p, 0.0, dock(P, 3.8), D, 3.8, 3.1, HAB, glass=(1.3, 1.9))
    dome(p, 0.0, dock(P, 3.8), D + 3.1, 3.8, 2.1)
    mast(p, 0.0, dock(P, 3.8), D + 5.15, 0.55, arms=(), tip=HAB)
    dome(p, 0.0, 2.0, 2.45, 2.4, 1.5, bands=2)  # a bud through the greenhouse's ridge


def hab_small_a(P: Prop) -> None:
    """A round pod under a glass dome; two more bud beside it; the middle one is rebuilt wider under
    a taller dome, and then domes stand on domes: a bubble on a bubble on a bubble."""
    p = P.part(0)
    airlock(P, p, 0.0)
    planter(p, 1.9, 2.9, -2.9, -2.3, D)
    planter(p, -2.9, -1.9, -2.9, -2.3, D)
    z0 = dock(P, 3.2)
    pod(P.part(0, 1), 0.0, z0, D, 3.2, POD, HAB)
    dome(P.part(0, 0), 0.0, z0, D + POD, 3.2, 1.3, bands=2)
    g = P.garden(0, 0)
    if g:  # the back of the lot, until the side pods stand there
        for sx in (-1, 1):
            planter(g, sx * 1.55 - 1.05, sx * 1.55 + 1.05, 1.6, 2.3, D)
            mound(g, sx * 2.3, 0.2, D, 0.9, 1.0)
        mound(g, 0.0, 1.95, D, 0.9, 1.0, PLANT)
    p = P.part(1)
    for sx in (-1, 1):
        pod(p, sx * 1.85, 1.75, D, 2.2, 1.2, HAB, glass=(0.4, 0.75))
        dome(p, sx * 1.85, 1.75, D + 1.2, 2.2, 1.0, bands=2, ring=0.2)
    g = P.garden(1, 3)
    if g:  # a bed between the side pods, until the largest bubble covers it
        planter(g, -0.6, 0.6, 2.2, 2.85, D)
    dome(P.part(1, 1), 0.0, z0, D + POD, 3.2, 1.85)
    q = P.part(2, 2)
    pod(q, 0.0, dock(P, 4.2), D, 4.2, 1.5, HAB)
    dome(q, 0.0, dock(P, 4.2), D + 1.5, 4.2, 2.6)
    q = P.part(3, 3)
    z3 = dock(P, 4.8)
    pod(q, 0.0, z3, D, 4.8, 1.3, HAB, glass=(0.45, 0.85))
    dome(q, 0.0, z3, D + 1.3, 4.8, 3.0)
    dome(q, 0.0, z3, 4.0, 2.4, 1.5, bands=2, ring=0.3)
    p = P.part(4)
    z4 = dock(P, 5.6)
    pod(p, 0.0, z4, D, 5.6, 1.3, HAB, glass=(0.45, 0.85))
    dome(p, 0.0, z4, D + 1.3, 5.6, 3.3)
    dome(p, 0.0, z4, 4.25, 3.0, 1.9, ring=0.35)
    dome(p, 0.0, z4, 5.9, 1.5, 0.9, bands=2, ring=0.15, ribs=False)


def hab_medium_a(P: Prop) -> None:
    """A long entrance pod with a glazed spine leads to a round pod under a dome; petal pods bud
    round it, and the middle is rebuilt as one broad dome that widens at every stage. A flower,
    spread across the lot, where the small lot stacks its bubbles."""
    zf = -P.d / 2
    cz = 1.7
    petals = [(-2.85, 3.7), (2.85, 3.7), (-2.85, -0.2), (2.85, -0.2)]

    def petal(part, x, z):
        pod(part, x, z, D, 2.0, 1.2, HAB, glass=None)
        dome(part, x, z, D + 1.2, 2.0, 0.95, bands=2, ring=0.2, ribs=False)

    p = P.part(0)
    capsule(p, "z", zf + DOCK, 0.4, 0.0, D, 3.0, 0.9, 1.1, ridge=GLASS)
    belt(p, "z", -1.6, 0.0, D, 3.0, 0.9, 1.1, HAB)
    for s in (-1, 1):
        porthole(p, "z", -2.9, s * 1.5, s, D + 0.5)
    airlock(P, p, 0.0)
    planter(p, -3.7, -2.3, -5.7, -5.0, D)
    planter(p, 2.3, 3.7, -5.7, -5.0, D)
    for x, z in petals[:2]:
        petal(p, x, z)
    pod(P.part(0, 1), 0.0, cz, D, 3.6, 1.4, HAB)
    dome(P.part(0, 0), 0.0, cz, D + 1.4, 3.6, 1.5, bands=2)
    p = P.part(1)
    for x, z in petals[2:]:
        petal(p, x, z)
    dome(P.part(1, 1), 0.0, cz, D + 1.4, 3.6, 2.0)
    q = P.part(2, 2)
    pod(q, 0.0, cz, D, 4.6, 1.5, HAB)
    dome(q, 0.0, cz, D + 1.5, 4.6, 3.0)
    q = P.part(3, 3)
    pod(q, 0.0, cz + 0.1, D, 5.6, 1.5, HAB)
    dome(q, 0.0, cz + 0.1, D + 1.5, 5.6, 3.6)
    p = P.part(4)
    pod(p, 0.0, cz + 0.2, D, 6.4, 1.65, HAB, glass=(0.6, 1.1))
    dome(p, 0.0, cz + 0.2, D + 1.65, 6.4, 4.1)
    mast(p, 0.0, cz + 0.2, D + 5.7, 0.7, arms=(), tip=HAB)


def ind_narrow_a(P: Prop) -> None:
    """A round control pod and bullet tanks across the lot; an orange manifold, a refinery column
    at the back that grows a section, a third tank on a beam, and last a flare stack by the pod."""
    pz = dock(P, 2.6)
    p = P.part(0)
    pod(p, 0.0, pz, D, 2.6, POD, IND)
    cone(p, 0.0, pz, D + POD, 2.6, 0.45)
    airlock(P, p, 0.0)
    tank_h(p, "x", -1.75, 1.75, -0.3, D, 1.5)
    p = P.part(1)
    tank_h(p, "x", -1.75, 1.75, 1.5, D, 1.5)
    pipe(p, [(0.9, 1.84, -0.3), (0.9, 3.2, -0.3), (0.9, 3.2, 1.5), (0.9, 1.84, 1.5)])
    column(P.part(2), 0.0, 3.1, D, 5.8, 1.3, stripes=(2.4, 4.7), decks=(3.5,), deck_w=1.75)
    p = P.part(3)
    column(p, 0.0, 3.1, 5.8, 7.8, 1.0, stripes=(7.1,), decks=(6.2,), deck_w=1.7)
    for x in (-1.95, 1.75):
        cube(p, x, x + 0.2, D, 2.8, 0.5, 0.7, PANEL, skip=("bottom", "top"))
    cube(p, -1.95, 1.95, 2.8, 3.0, 0.3, 0.9, PANEL)
    tank_h(p, "x", -1.6, 1.6, 0.6, 3.0, 1.3, clear=0.0)
    p = P.part(4)
    stack(p, 1.55, -3.4, D, 10.4, 0.8, 0.5)
    hoop(p, 1.55, -3.4, 5.2, 5.45, 0.7, TRIM)


def ind_narrow_b(P: Prop) -> None:
    """A round pump pod to one side and a sphere tank at the back; a second sphere under an orange
    manifold; a fat stack on the deck beside the pod that grows a section; last, the back sphere is
    rebuilt on a tall stalk. Tall in front where A is tall behind, then tall behind where A raises
    its flare in front."""
    px, pz = -0.8, dock(P, 2.3)
    sx, sz = 1.2, -2.6  # the stack
    bx, bz = 0.0, 2.35  # the back sphere
    p = P.part(0)
    pod(p, px, pz, D, 2.3, POD, IND)
    cone(p, px, pz, D + POD, 2.3, 0.45)
    airlock(P, p, px)
    pipe(p, [(-0.9, 0.45, -1.5), (-0.9, 0.45, bz), (-0.4, 0.45, bz)])
    sphere(P.part(0, 3), bx, bz, D, 2.4, slim=True)
    p = P.part(1)
    sphere(p, 0.0, -0.2, D, 2.2, slim=True)
    pipe(p, [(0.0, 2.45, -0.2), (0.0, 3.2, -0.2), (0.0, 3.2, bz), (0.0, 2.55, bz)])
    p = P.part(2)
    stack(p, sx, sz, D, 5.6, 1.3, 1.15, tip=None)
    hoop(p, sx, sz, 2.4, 2.65, 1.3, TRIM)
    p = P.part(3)
    stack(p, sx, sz, 5.6, 7.6, 1.15, 1.0, tip_h=0.4)
    hoop(p, sx, sz, 5.45, 5.7, 1.15, TRIM)
    pipe(p, [(sx, 3.2, sz + 0.3), (sx, 3.2, -0.2), (0.11, 3.2, -0.2)])
    p = P.part(4)
    sphere(p, bx, bz, D, 2.8, stand=7.2, stalk=HULL, slim=True)
    hoop(p, bx, bz, 4.0, 4.25, 1.4, TRIM)
    hoop(p, bx, bz, 6.2, 6.45, 1.4, TRIM)


def ind_small_a(P: Prop) -> None:
    """A round control pod and a silo; a second, taller silo joined by an orange pipe, a column
    that grows a section, a pipe run over the yard, and a flare stack on top of the column."""
    px, pz = -1.6, dock(P, 2.4)
    p = P.part(0)
    pod(p, px, pz, D, 2.4, POD, IND)
    cone(p, px, pz, D + POD, 2.4, 0.45)
    airlock(P, p, px)
    tank_v(p, 1.45, 1.4, D, 2.4, 2.5, at=0.5)
    p = P.part(1)
    tank_v(p, -1.5, 1.6, D, 2.2, 3.4)
    pipe(p, [(0.4, 1.9, 1.5), (-0.5, 1.9, 1.5)])
    column(P.part(2), 1.6, -1.75, D, 5.9, 1.1, stripes=(2.0, 4.4), decks=(3.2,), deck_w=1.9)
    p = P.part(3)
    column(p, 1.6, -1.75, 5.9, 7.8, 0.9, stripes=(7.1,), decks=(6.3,), deck_w=1.7)
    pipe(p, [(-1.5, 3.3, 1.6), (-1.5, 3.9, 1.6), (-1.5, 3.9, -1.75), (1.2, 3.9, -1.75)])
    p = P.part(4)
    stack(p, 1.6, -1.75, 7.8, 10.6, 0.7, 0.5)
    tank_v(p, 0.4, 0.0, D, 1.3, 2.9, at=0.6)


def ind_medium_a(P: Prop) -> None:
    """A small refinery that fills its yard from the start: a round control pod, two bullet tanks,
    a silo, a day tank, a small sphere and ground pipes between them; then a second silo and a pipe
    rack, a column, a round furnace with its stack where the day tank stood, and last the stack and
    the column grow and the sphere is rebuilt large."""
    px, pz = -2.2, dock(P, 2.6)
    p = P.part(0)
    pod(p, px, pz, D, 2.6, POD, IND)
    cone(p, px, pz, D + POD, 2.6, 0.45)
    airlock(P, p, px)
    tank_h(p, "z", -5.5, -2.1, 2.5, D, 1.6)
    tank_v(p, -2.2, -1.3, D, 2.4, 2.6)
    pipe(p, [(-2.2, 0.5, -0.2), (-2.2, 0.5, 2.6), (2.3, 0.5, 2.6), (2.3, 0.5, 3.3)])
    q = P.part(0, 1)
    for x, z, c in ((0.3, -4.9, TRIM), (1.0, -4.9, HULL), (0.3, -4.2, HULL), (1.0, -4.2, TRIM), (0.65, -3.5, TRIM)):
        drum(q, x, z, D, 0.6, 0.8, c, PANEL)
    tank_v(P.part(0, 2), 2.3, 3.9, D, 2.2, 1.9)
    q = P.part(0, 3)
    sphere(q, -2.3, 4.3, D, 1.9, slim=True)
    pipe(q, [(-2.2, 0.5, 2.71), (-2.2, 0.5, 3.9)])
    p = P.part(1)
    tank_v(p, -2.3, 1.2, D, 2.2, 3.7)
    for z in (-1.4, 1.6, 4.6):
        for x in (-0.3, 0.52):
            cube(p, x, x + 0.18, D, 3.0, z - 0.09, z + 0.09, PANEL, skip=("bottom", "top"))
        cube(p, -0.3, 0.7, 3.0, 3.2, z - 0.14, z + 0.14, PANEL)
    cube(p, -0.2, 0.02, 3.2, 3.42, -1.7, 4.9, TRIM)
    cube(p, 0.38, 0.6, 3.2, 3.42, -1.7, 4.9, HULL)
    column(P.part(2), 2.3, 0.6, D, 6.8, 1.6, stripes=(2.2, 5.3), decks=(3.8,), deck_w=2.6)
    p = P.part(3)
    tank_h(p, "z", 2.4, 5.7, 2.3, D, 2.6)
    extrude(p, octagon(2.3, D + 0.22 + 1.3, 0.55), "z", 2.4 - GAP, 2.4, RING, cap0=WARN)
    stack(p, 2.3, 4.3, 2.8, 9.4, 1.3, 1.0, tip=None)
    hoop(P.part(3, 3), 2.3, 4.3, 9.05, 9.3, 1.0, TRIM)
    p = P.part(4)
    stack(p, 2.3, 4.3, 9.4, 12.2, 1.0, 0.75)
    hoop(p, 2.3, 4.3, 9.2, 9.45, 1.0, TRIM)
    column(p, 2.3, 0.6, 6.8, 8.6, 1.25, decks=(7.0,), deck_w=2.3)
    sphere(p, -2.3, 4.4, D, 2.6)


def sci_narrow_a(P: Prop) -> None:
    """A capsule lab under a glazed spine with a dish behind it; the dish climbs onto an instrument
    drum and grows, the lab is rebuilt wider and gains an observation blister, and a mast rises in
    the back corner. Long and low in front, its instruments behind."""
    zf = -P.d / 2
    mx, mz = -1.6, 3.6
    dx, dz = 0.3, 2.45
    airlock(P, P.part(0), 0.0)
    q = P.part(0, 1)
    capsule(q, "z", zf + DOCK, 0.9, 0.0, D, 3.2, 0.9, 1.1, ridge=GLASS)
    belt(q, "z", -1.0, 0.0, D, 3.2, 0.9, 1.1, SCI)
    for s in (-1, 1):
        porthole(q, "z", -1.8, s * 1.6, s, D + 0.5)
    r = P.part(0, 0)
    dish(r, dx, dz, D, 2.0)
    mast(r, mx, mz, D, 2.3, arms=(0.75,))
    p = P.part(1)
    drum(p, dx, dz, D, 2.2, 1.3)
    hoop(p, dx, dz, D + 0.85, D + 1.05, 2.2, SCI)
    r = P.part(1, 1)
    dish(r, dx, dz, D + 1.3, 2.2, stand=0.5)
    mast(r, mx, mz, D, 3.37, arms=(0.75,))
    p = P.part(2)
    capsule(p, "z", zf + DOCK, 1.1, 0.0, D, 3.8, 1.2, 1.5, ridge=GLASS)
    belt(p, "z", -1.0, 0.0, D, 3.8, 1.2, 1.5, SCI)
    for s in (-1, 1):
        porthole(p, "z", -1.55, s * 1.9, s, D + 0.65, r=0.28)
    drum(p, dx, dz, D + 1.3, 1.6, 1.0)
    r = P.part(2, 2)
    dish(r, dx, dz, D + 2.3, 2.6, stand=0.55)
    mast(r, mx, mz, D, 4.92, arms=(0.72, 0.9))
    p = P.part(3)
    dome(p, 0.0, -1.35, 2.45, 2.2, 1.2, bands=2)
    dish(p, dx, dz, D + 2.3, 2.9, stand=0.6)
    mast(P.part(3, 3), mx, mz, D, 6.22, arms=(0.72, 0.9), foot=2.0)
    mast(P.part(4), mx, mz, D, 7.52, arms=(0.72, 0.86, 0.95), tip=HOLO, foot=2.6)


def sci_narrow_b(P: Prop) -> None:
    """An observatory: a round drum under a white dome with a cyan shutter, rebuilt wider and
    taller at every stage, its telescope out through the shutter from stage 2; a capsule annex
    behind it carries a radar reflector, and last a whip mast. Tall and round in front where A is
    long and low with its dish and mast at the back."""
    obs = [(3.2, 1.5, 1.4), (3.4, 1.95, 1.6), (3.6, 2.6, 2.0), (3.8, 3.4, 2.2), (3.8, 3.8, 2.2)]  # drum w, h; dome h
    airlock(P, P.part(0), 0.0)
    for k, (w, h, dh) in enumerate(obs):
        q = P.part(k, k) if k < len(obs) - 1 else P.part(k)
        g = min(0.4 * h, h - 0.91)
        pod(q, 0.0, dock(P, w), D, w, h, SCI, glass=(g, g + 0.45))
        dome(q, 0.0, dock(P, w), D + h, w, dh, bands=2 if k < 2 else 3, ribs=False, panes=(SHELL, HULL),
             slit=(5, HOLO))
        if k >= 2:  # what the Observation Dome landmark does not have: the instrument shows
            scope(q, 0.0, dock(P, w), D + h, w, dh)
    r = P.part(0, 0)
    cube(r, -1.5, 1.5, D, D + 0.35, 1.6, 3.4, PANEL, skip=("bottom",))
    solar(r, -1.5, 1.5, 1.6, 3.4, D + 0.35, 2, 1)
    p = P.part(1)
    capsule(p, "z", 0.4, 3.8, 0.0, D, 3.0, 0.8, 1.0, ridge=GLASS)
    belt(p, "z", 2.1, 0.0, D, 3.0, 0.8, 1.0, SCI)
    reflector(P.part(2), 0.0, 2.3, 1.85, 2.4, 1.3, 0.35)
    mast(P.part(4), 1.75, 0.2, D, 6.82, arms=(), tip=HOLO, foot=2.4)


def sci_small_a(P: Prop) -> None:
    """A round lab with a dish on its roof and a solar tray beside it; a capsule wing with a radome
    on it; the lab is rebuilt wider under a larger dish, and the dish climbs onto an instrument
    drum and grows again. No mast: the Comms Array landmark is the era's mast."""
    lx = -0.8
    p = P.part(0)
    airlock(P, p, lx)
    cube(p, 1.2, 2.8, D, D + 0.35, -2.75, -1.55, PANEL, skip=("bottom",))
    solar(p, 1.2, 2.8, -2.75, -1.55, D + 0.35, 2, 1)
    q = P.part(0, 1)
    pod(q, lx, dock(P, 3.2), D, 3.2, POD, SCI)
    dish(q, lx, dock(P, 3.2), D + POD, 1.8, stand=0.45)
    p = P.part(1)
    capsule(p, "z", -0.9, 2.8, 2.0, D, 1.8, 0.8, 0.8)
    belt(p, "z", 0.95, 2.0, D, 1.8, 0.8, 0.8, SCI)
    sphere(p, 2.0, 1.6, 1.5, 1.6, stand=1.0, stalk=HULL, slim=True, belt=SCI)  # the radome, on the wing
    lz = dock(P, 3.6)
    pod(P.part(2), lx, lz, D, 3.6, 2.2, SCI, glass=(0.9, 1.35))
    dish(P.part(2, 2), lx, lz, D + 2.2, 3.0, stand=0.55)
    p = P.part(3)
    drum(p, lx, lz, D + 2.2, 2.2, 1.4)
    hoop(p, lx, lz, D + 3.1, D + 3.3, 2.2, SCI)
    dish(P.part(3, 3), lx, lz, D + 3.6, 3.0, stand=0.55)
    p = P.part(4)
    dish(p, lx, lz, D + 3.6, 3.4, stand=0.8)


def port_narrow_a(P: Prop) -> None:
    """A round gatehouse and a cargo pad with a few containers; the stacks grow under a floodlight,
    a control tower rises from the gatehouse, a gantry crane spans the pad, and a mast tops the cab."""
    gz = dock(P, 2.6)
    p = P.part(0)
    pod(p, 0.0, gz, D, 2.6, POD, PORT)
    airlock(P, p, 0.0)
    top = pad(p, (-1.85, 1.85, -0.9, 3.8))
    beacon(P.part(0, 1), 0.0, gz, D + POD)
    q = P.part(0, 0)
    crates(q, -0.9, 3.0, top, [CRATES[0]])
    crates(q, 0.9, 3.0, top, [CRATES[1], CRATES[2]])
    p = P.part(1)
    crates(p, -0.9, 3.25, top, [CRATES[0], CRATES[2], CRATES[1]])
    crates(p, 0.9, 3.25, top, [CRATES[1], CRATES[3]])
    crates(p, -0.9, 2.3, top, [CRATES[3]])
    crates(p, 0.9, 2.3, top, [CRATES[2], CRATES[0]])
    lamp_mast(p, 1.67, -0.3, top, 2.9)
    tower(P.part(2), 0.0, gz, D + POD, 2.95, 3.9, 1.3, 2.4)
    gantry(P.part(3), -1.85, 1.85, 0.9, top, 5.0, 0.2, CRATES[0], drop=1.5)
    p = P.part(4)
    mast(p, 0.65, gz, 3.9, 2.8, arms=(0.55, 0.8))
    crates(p, -0.9, 2.3, top + 0.75, [CRATES[1], CRATES[0]])
    crates(p, 0.9, 3.25, top + 1.5, [CRATES[2]])


def port_narrow_b(P: Prop) -> None:
    """A round gate kiosk, a fuel apron with drums and tanks, and a vaulted hangar across the back
    that is rebuilt taller, then gains a round glass cupola and a mast. Tall at the back under a
    vault where A is tall in front."""
    kz = dock(P, 2.0)
    han = (-1.85, 1.85, 0.6, 3.8)
    p = P.part(0)
    pod(p, 0.0, kz, D, 2.0, POD, PORT)
    airlock(P, p, 0.0)
    top = pad(p, (-1.85, 1.85, -1.55, 0.35))
    beacon(p, 0.0, kz, D + POD)
    drum(p, -1.3, -0.3, top, 0.6, 0.8, CRATES[0], PANEL)
    drum(p, -0.55, -0.3, top, 0.6, 0.8, CRATES[2], PANEL)
    hangar(P.part(0, 1), han, D, 1.0, 1.5)
    p = P.part(1)
    tank_v(p, 1.2, -0.75, top, 1.1, 1.9, WARN)
    drum(p, -1.3, -1.05, top, 0.6, 0.8, CRATES[1], PANEL)
    lamp_mast(p, 1.65, 0.1, top, 2.9)
    hangar(P.part(2), han, D, 1.8, 1.9)
    beacon(P.part(2, 2), 0.0, 2.2, D + 3.7)
    p = P.part(3)
    drum(p, 0.0, 2.2, 3.4, 1.6, 1.5)
    hoop(p, 0.0, 2.2, 4.05, 4.55, 1.6, GLASS)
    beacon(p, 0.0, 2.2, 4.9)
    p = P.part(4)
    mast(p, 0.45, 2.2, 4.9, 1.75, arms=(0.55, 0.8))
    tank_v(p, 0.15, -0.8, top, 0.9, 1.5, WARN)
    drum(p, -0.55, -1.05, top, 0.6, 0.8, CRATES[3], PANEL)


def port_small_a(P: Prop) -> None:
    """A round gatehouse and a cargo pad with containers; taller stacks and a floodlight, a vaulted
    hangar facing the pad, a control tower on the gatehouse, and last a cargo craft parked where the
    containers stood."""
    gx, gz = -1.75, dock(P, 2.4)
    shed = (-2.85, -0.6, 0.0, 2.85)
    p = P.part(0)
    pod(p, gx, gz, D, 2.4, POD, PORT)
    airlock(P, p, gx)
    top = pad(p, (-0.3, 2.85, -2.85, 2.85))
    beacon(P.part(0, 2), gx, gz, D + POD)
    q = P.part(0, 3)
    crates(q, 0.35, 1.9, top, [CRATES[0]], along="z")
    crates(q, 1.3, 1.9, top, [CRATES[2], CRATES[1]], along="z")
    q = P.part(1, 3)
    crates(q, 0.35, 1.9, top + 0.75, [CRATES[1], CRATES[3]], along="z")
    crates(q, 2.25, 1.9, top, [CRATES[3], CRATES[0]], along="z")
    crates(q, 0.35, 0.1, top, [CRATES[2]], along="z")
    crates(q, 1.3, 0.1, top, [CRATES[0], CRATES[1]], along="z")
    lamp_mast(P.part(1), 2.6, -2.65, top, 2.93)
    p = P.part(2)
    hangar(p, shed, D, 1.9, 1.4, axis="x", door_end=1)
    beacon(p, -1.7, 1.425, D + 3.3)
    tower(P.part(3), gx, gz, D + POD, 3.5, 4.5, 1.2, 2.2)
    p = P.part(4)
    mast(p, gx + 0.55, gz, 4.5, 2.2, arms=(0.55, 0.8))
    P.craft("craft_cargoB", 1.35, 0.1, top, 0, 4)


def port_medium_a(P: Prop) -> None:
    """A small spaceport with a working yard from the start: a round gatehouse, a wide pad with
    containers and a tug, a container yard, and stores and a fuel tank where the hangar will stand;
    floodlights and taller stacks, a vaulted hangar across the back, a control tower and a parked
    cargo craft, then a gantry crane over the yard."""
    gx, gz = -2.5, dock(P, 2.6)
    han = (-3.8, 3.8, 1.4, 5.8)
    p = P.part(0)
    pod(p, gx, gz, D, 2.6, POD, PORT)
    airlock(P, p, gx)
    top = pad(p, (-0.9, 3.85, -5.85, 0.5))
    crates(p, -2.5, 0.3, D, [CRATES[0], CRATES[1]])
    crates(p, -2.5, -0.65, D, [CRATES[2]])
    q = P.part(0, 2)
    beacon(q, gx, gz, D + POD)
    crates(q, 0.0, -0.4, top, [CRATES[3], CRATES[0]])
    crates(q, 1.8, -0.4, top, [CRATES[1]])
    crates(q, 0.4, -4.6, top, [CRATES[2], CRATES[1]], along="z")
    tug(q, 2.9, -3.2, top)
    q = P.part(0, 1)
    crates(q, -1.6, 3.2, D, [CRATES[1], CRATES[3]])
    crates(q, 1.4, 4.4, D, [CRATES[2]], along="z")
    crates(q, 2.5, 2.6, D, [CRATES[0]])
    tank_v(q, -2.9, 4.7, D, 1.3, 1.8, WARN)
    for x, z, c in ((0.0, 2.4, 0), (0.7, 2.4, 2), (0.35, 3.0, 3)):
        drum(q, x, z, D, 0.6, 0.8, CRATES[c], PANEL)
    p = P.part(1)
    crates(p, -2.5, -0.65, D + 0.75, [CRATES[3], CRATES[0]])
    crates(p, -2.5, -1.6, D, [CRATES[1], CRATES[2]])
    crates(p, -2.5, -2.55, D, [CRATES[0]])
    lamp_mast(p, 3.6, 0.9, D, 3.0)
    lamp_mast(p, -3.7, -3.4, D, 3.0)
    crates(P.part(1, 2), 1.8, -0.4, top + 0.75, [CRATES[2], CRATES[3]])
    p = P.part(2)
    hangar(p, han, D, 1.7, 2.1)
    beacon(p, -0.7, 3.6, D + 3.8)
    beacon(p, 0.7, 3.6, D + 3.8)
    tower(P.part(3), gx, gz, D + POD, 4.2, 5.25, 1.3, 2.4)
    P.craft("craft_cargoA", 1.5, -2.9, top, 0, 3)
    p = P.part(4)
    gantry(p, -3.8, -1.2, -1.15, D, 4.9, -2.5, CRATES[2], drop=1.0)
    mast(p, gx + 0.65, gz, 5.25, 3.2, arms=(0.5, 0.75))
    crates(p, -2.5, -2.55, D + 0.75, [CRATES[3], CRATES[1]])


# Blueprint id -> (lot, builder): INTERFACES "Wave 4.1", and the B props of its narrow districts.
PROPS = {
    "FabricHabNarrowA": ("narrow", hab_narrow_a),
    "FabricHabNarrowB": ("narrow", hab_narrow_b),
    "FabricIndNarrowA": ("narrow", ind_narrow_a),
    "FabricIndNarrowB": ("narrow", ind_narrow_b),
    "FabricSciNarrowA": ("narrow", sci_narrow_a),
    "FabricSciNarrowB": ("narrow", sci_narrow_b),
    "FabricPortNarrowA": ("narrow", port_narrow_a),
    "FabricPortNarrowB": ("narrow", port_narrow_b),
    "FabricHabSmallA": ("small", hab_small_a),
    "FabricIndSmallA": ("small", ind_small_a),
    "FabricSciSmallA": ("small", sci_small_a),
    "FabricPortSmallA": ("small", port_small_a),
    "FabricHabMediumA": ("medium", hab_medium_a),
    "FabricIndMediumA": ("medium", ind_medium_a),
    "FabricPortMediumA": ("medium", port_medium_a),
}
# Green twin -> its original ("Green the Domes"): the original's builder, run with GREEN set.
TWINS = {
    "FabricHabNarrowAGreen": "FabricHabNarrowA",
    "FabricHabNarrowBGreen": "FabricHabNarrowB",
    "FabricHabSmallAGreen": "FabricHabSmallA",
    "FabricHabMediumAGreen": "FabricHabMediumA",
}
EVERY = list(PROPS) + list(TWINS)
STAGES = 5


def deck(lot: str) -> Part:
    """The deck plate that covers a whole lot from stage 0: decking arrives lot by lot."""
    w, d = LOTS[lot]
    p = Part(f"deck-{lot}")
    cube(p, -w / 2, w / 2, 0.0, D, -d / 2, d / 2, DECK, skip=("bottom",))
    return p


def build(pid: str) -> tuple[Prop, list[tuple[float, float, float]]]:
    lot, make = PROPS[TWINS.get(pid, pid)]
    RODS.clear()
    prop = Prop(pid, lot, green=pid in TWINS)
    GREEN["on"] = prop.green
    try:
        make(prop)
    finally:
        GREEN["on"] = False
    rods = list(RODS)
    if prop.green:
        prop.share(build(TWINS[pid])[0])
    return prop, rods


# --- checks -------------------------------------------------------------------------------------


def flat_faces(parts: list[Part]) -> list[tuple]:
    """Every axis-aligned face as (axis, facing, plane, outline on the other two axes, colour)."""
    out = []
    for part in parts:
        for idx, colour in part.faces:
            pts = [part.verts[i] for i in idx]
            n = newell(pts)
            length = math.sqrt(sum(c * c for c in n))
            if length < 1e-9:
                continue
            axis = max(range(3), key=lambda i: abs(n[i]))
            if abs(n[axis]) / length < 0.9999:
                continue
            u, v = [i for i in range(3) if i != axis]
            out.append((axis, 1 if n[axis] > 0 else -1, pts[0][axis], [(q[u], q[v]) for q in pts], colour))
    return out


def convex_overlap(a, b) -> bool:
    """True when two convex polygons share some area (separating axes; touching edges do not count)."""
    for poly in (a, b):
        for i in range(len(poly)):
            (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
            nx, ny = y1 - y0, x0 - x1
            scale = math.hypot(nx, ny)
            if scale < 1e-12:
                continue
            pa = [nx * x + ny * y for x, y in a]
            pb = [nx * x + ny * y for x, y in b]
            if (min(max(pa), max(pb)) - max(min(pa), min(pb))) / scale <= 1e-4:
                return False
    return True


def face_fights(parts: list[Part]) -> list[str]:
    """Pairs of faces that would flicker: parallel, facing the same way, overlapping in their plane
    and closer than GAP (coplanar included). Opposite-facing pairs never render together, because a
    MeshPart culls back faces."""
    by_key: dict = {}
    for f in flat_faces(parts):
        by_key.setdefault((f[0], f[1]), []).append(f)
    found = []
    for (axis, facing), group in sorted(by_key.items()):
        group.sort(key=lambda f: f[2])
        for i, a in enumerate(group):
            for b in group[i + 1:]:
                if b[2] - a[2] >= GAP - 1e-6:
                    break
                if convex_overlap(a[3], b[3]):
                    us, vs = [q[0] for q in a[3]], [q[1] for q in a[3]]
                    found.append(f"{'xyz'[axis]}{'+' if facing > 0 else '-'} faces {b[2] - a[2]:.3f} apart at "
                                 f"{'xyz'[axis]} = {a[2]:.2f} near ({min(us):.2f}..{max(us):.2f}, "
                                 f"{min(vs):.2f}..{max(vs):.2f})")
    return found


def stage_box(prop: Prop, k: int):
    """Bounds of stage k: the deck, the prop's own pieces and its space-kit pieces."""
    boxes = [part.bounds() for part in prop.present(k)] + [(c["lo"], c["hi"]) for c in prop.kenney_at(k)]
    lo = [min(-prop.w / 2, *(b[0][0] for b in boxes)), 0.0, min(-prop.d / 2, *(b[0][2] for b in boxes))]
    hi = [max(prop.w / 2, *(b[1][0] for b in boxes)), max(b[1][1] for b in boxes),
          max(prop.d / 2, *(b[1][2] for b in boxes))]
    return lo, hi


def stage_tris(prop: Prop, k: int) -> int:
    return deck(prop.lot).tris + sum(part.tris for part in prop.present(k)) + sum(c["tris"] for c in prop.kenney_at(k))


def dark_outline(parts: list[Part], lo, hi) -> list[str]:
    """Dark faces on the outline: one that reaches the stage's top, or a side of its bounding box."""
    found = []
    for part in parts:
        for idx, colour in part.faces:
            if colour not in DARK:
                continue
            pts = [part.verts[i] for i in idx]
            if any(q[1] > hi[1] - 0.02 or q[0] < lo[0] + 0.02 or q[0] > hi[0] - 0.02 or q[2] < lo[2] + 0.02
                   or q[2] > hi[2] - 0.02 for q in pts):
                found.append(f"a dark face of {part.name} lies on the outline near "
                             f"({pts[0][0]:.2f}, {pts[0][1]:.2f}, {pts[0][2]:.2f})")
    return found


def green_area(parts: list[Part]) -> float:
    """The area of the faces in a garden green."""
    total = 0.0
    for part in parts:
        for idx, colour in part.faces:
            if colour in GREENS:
                n = newell([part.verts[i] for i in idx])
                total += math.sqrt(sum(c * c for c in n)) / 2
    return total


def twin_problems(prop: Prop) -> list[str]:
    """A Green twin against its original: the same body, piece for piece and vertex for vertex,
    whatever its colours; nothing added above GARDEN_MAX, so the outline is the original's and
    the heights agree at every stage; and more green on show than the original at every stage."""
    orig = prop.original
    bad = []
    if set(prop.parts) != set(orig.parts) or prop.kenney != orig.kenney:
        bad.append(f"its body pieces are not {orig.id}'s: {sorted(set(prop.parts) ^ set(orig.parts), key=str)}")
    for key, part in prop.parts.items():
        same = orig.parts.get(key)
        if same is None:
            continue
        if (part.verts, [idx for idx, _ in part.faces]) != (same.verts, [idx for idx, _ in same.faces]):
            bad.append(f"{part.name} does not have the shape of {same.name}")
    for part in prop.gardens.values():
        top = part.bounds()[1][1]
        if top > GARDEN_MAX + 1e-6:
            bad.append(f"{part.name} stands {top:.2f} tall > {GARDEN_MAX}: a twin adds only low garden pieces")
    for k in range(STAGES):
        mine, theirs = stage_box(prop, k)[1][1], stage_box(orig, k)[1][1]
        if abs(mine - theirs) > GAP:
            bad.append(f"stage {k} is {mine:.2f} tall, {orig.id}'s {theirs:.2f}")
        more = green_area(prop.present(k)) - green_area(orig.present(k))
        if more < 1.0:
            bad.append(f"stage {k} shows {more:.2f} studs2 more green than {orig.id}: the swap would not show")
    return bad


def check(prop: Prop, rods) -> list[str]:
    """The contract for one prop. Returns violations."""
    w, d = prop.w, prop.d
    bad = []
    e = 1e-6
    stages = {stage for stage, _ in prop.parts} | {c["stage"] for c in prop.kenney}
    if stages != set(range(STAGES)):
        bad.append(f"stages {sorted(stages)}: every stage 0 to {STAGES - 1} must add a piece")
    for (stage, until), part in prop.pieces():
        if until is not None and (until < stage or until >= STAGES - 1):
            bad.append(f"{part.name}: leaves after stage {until}, which is before it joins or retires nothing")
        lo, hi = part.bounds()
        if lo[0] < -w / 2 - e or hi[0] > w / 2 + e or lo[2] < -d / 2 - e or hi[2] > d / 2 + e or lo[1] < -e:
            bad.append(f"{part.name} leaves the {w:g} x {d:g} lot: x[{lo[0]:.3f}, {hi[0]:.3f}] "
                       f"z[{lo[2]:.3f}, {hi[2]:.3f}] y from {lo[1]:.3f}")
    for c in prop.kenney:
        if c["lo"][0] < -w / 2 - e or c["hi"][0] > w / 2 + e or c["lo"][2] < -d / 2 - e or c["hi"][2] > d / 2 + e:
            bad.append(f"{c['model']} leaves the lot: x[{c['lo'][0]:.2f}, {c['hi'][0]:.2f}] "
                       f"z[{c['lo'][2]:.2f}, {c['hi'][2]:.2f}]")
    if not prop.airlocks:
        bad.append("no airlock collar")
    for cx, z0 in prop.airlocks:
        if abs(z0 + d / 2) > e or cx - 0.96 < -w / 2 - e or cx + 0.96 > w / 2 + e:
            bad.append(f"the airlock collar at x {cx:g} is not flush with the lot front, or leaves it")
    if (0, None) not in prop.parts or min(v[2] for v in prop.parts[(0, None)].verts) > -d / 2 + e:
        bad.append("the collar is not part of the piece that stays from stage 0")
    tops = [stage_box(prop, k)[1][1] for k in range(STAGES)]
    if tops[0] > HEIGHT_FLOOR + e:
        bad.append(f"stage 0 is {tops[0]:.2f} tall > heightFloor {HEIGHT_FLOOR}")
    if tops[-1] > FINAL_MAX[prop.lot] + e:
        bad.append(f"the last stage is {tops[-1]:.2f} tall > {FINAL_MAX[prop.lot]:g}")
    for k in range(1, STAGES):
        if tops[k] < tops[k - 1] + MIN_RISE - e:
            bad.append(f"stage {k} is {tops[k]:.2f} tall, stage {k - 1} {tops[k - 1]:.2f}: it must rise by {MIN_RISE}")
    dk = deck(prop.lot)
    lo, hi = dk.bounds()
    if (lo[0], hi[0], lo[2], hi[2]) != (-w / 2, w / 2, -d / 2, d / 2) or any(c != DECK for _, c in dk.faces):
        bad.append(f"the deck plate does not cover the {w:g} x {d:g} lot in the decking colour")
    for k in range(STAGES):
        parts = prop.present(k)
        tris = stage_tris(prop, k)
        if tris > TRI_BUDGET:
            bad.append(f"stage {k}: {tris} tris > {TRI_BUDGET}")
        for fight in face_fights([dk] + parts)[:3]:
            bad.append(f"stage {k}: {fight}")
        lo, hi = stage_box(prop, k)
        for msg in dark_outline(parts, lo, hi)[:2]:
            bad.append(f"stage {k}: {msg}")
    for rod in sorted(set(rods))[:5]:
        bad.append(f"a member {rod[0]:g} x {rod[1]:g} x {rod[2]:g} is thinner than {MIN_MEMBER} in two dimensions")
    if prop.original:
        bad += twin_problems(prop)
    return bad


# --- blueprints, GLBs, summary ------------------------------------------------------------------


def blueprint_text(prop: Prop) -> str:
    pieces = [{"kit": KIT, "model": f"deck-{prop.lot}", "pos": [0, 0, 0], "rotY": 0, "stage": 0}]
    entries = [(stage, 0, -1 if until is None else until, {"kit": KIT, "model": part.name, "pos": [0, 0, 0],
                                                         "rotY": 0, "stage": stage}, until)
               for (stage, until), part in prop.pieces()]
    entries += [(c["stage"], 1, i, {"kit": c["kit"], "model": c["model"], "pos": c["pos"], "rotY": c["rotY"],
                                   "stage": c["stage"]}, c["until"]) for i, c in enumerate(prop.kenney)]
    for _, _, _, piece, until in sorted(entries, key=lambda t: t[:3]):
        if until is not None:
            piece["untilStage"] = until
        pieces.append(piece)
    lines = ["{", f'  "id": "{prop.id}",', f'  "era": "{ERA}",', f'  "scale": {SCALE:.1f},',
             f'  "footprint": [{prop.w:g}, {prop.d:g}],', '  "pieces": [']
    lines += ["    " + json.dumps(pc, separators=(", ", ": ")) + ("," if i < len(pieces) - 1 else "")
              for i, pc in enumerate(pieces)]
    lines += ["  ]", "}"]
    return "\n".join(lines) + "\n"


def all_pieces(props: list[Prop]) -> dict[str, Part]:
    pieces = {f"deck-{lot}": deck(lot) for lot in LOTS}
    for prop in props:
        for _, part in prop.pieces():
            shared = pieces.get(part.name)  # a twin's untouched piece is its original's
            assert shared is None or (shared.verts, shared.faces) == (part.verts, part.faces), f"{part.name} differs"
            pieces[part.name] = part
    return pieces


def glb_stats(path: str):
    """(triangles, min, max) of a GLB's meshes, read from its JSON chunk; positions in file units."""
    with open(path, "rb") as fh:
        data = fh.read()
    length = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + length])
    tris, lo, hi = 0, [math.inf] * 3, [-math.inf] * 3
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            pos = doc["accessors"][prim["attributes"]["POSITION"]]
            tris += (doc["accessors"][prim["indices"]]["count"] if "indices" in prim else pos["count"]) // 3
            lo = [min(a, b) for a, b in zip(lo, pos["min"])]
            hi = [max(a, b) for a, b in zip(hi, pos["max"])]
    return tris, lo, hi


def disk_problems(props: list[Prop], out_dir: str) -> list[str]:
    """What on disk no longer matches this script: a blueprint, a GLB, a space-kit triangle count."""
    bad = []
    for prop in props:
        path = os.path.join(BLUEPRINT_DIR, f"{prop.id}.json")
        try:
            with open(path, "r", encoding="utf-8", newline="") as fh:
                if fh.read() != blueprint_text(prop):
                    bad.append(f"{prop.id}.json differs from a fresh build (run the script without `check`)")
        except OSError:
            bad.append(f"{prop.id}.json is missing")
    for name, part in all_pieces(props).items():
        path = os.path.join(out_dir, f"{name}.glb")
        if not os.path.isfile(path):
            bad.append(f"{name}.glb is missing")
            continue
        tris, lo, hi = glb_stats(path)
        plo, phi = part.bounds()
        off = max(abs(lo[i] * SCALE - plo[i]) for i in range(3)) + max(abs(hi[i] * SCALE - phi[i]) for i in range(3))
        if tris != part.tris or off > 1e-3:
            bad.append(f"{name}.glb is stale: {tris} tris against {part.tris}, bounds off by {off:.4f}")
    for model, k in KENNEY.items():
        for sub in ("GLB format", "GLTF format"):
            path = os.path.join(KITS_ROOT, k["kit"], "Models", sub, f"{model}.glb")
            if os.path.isfile(path) and glb_stats(path)[0] != k["tris"]:
                bad.append(f"{k['kit']}/{model}.glb has {glb_stats(path)[0]} tris, KENNEY says {k['tris']}")
    for prop in props:  # whatever a blueprint on disk names must be a GLB on disk, in any kit
        try:
            with open(os.path.join(BLUEPRINT_DIR, f"{prop.id}.json"), "r", encoding="utf-8") as fh:
                named = {(pc["kit"], pc["model"]) for pc in json.load(fh)["pieces"]}
        except (OSError, ValueError, KeyError):
            continue
        for kit, model in sorted(named):
            folder = out_dir if kit == KIT else None
            paths = [os.path.join(folder, f"{model}.glb")] if folder else [
                os.path.join(KITS_ROOT, kit, "Models", sub, f"{model}.glb") for sub in ("GLB format", "GLTF format")]
            if not any(os.path.isfile(p) for p in paths):
                bad.append(f"{prop.id}.json names {kit}/{model}, which is not on disk")
    return bad


def report(props_rods) -> tuple[dict, int]:
    """Log one line per prop and its problems; return the summary and the problem count."""
    summary, failures = {}, 0
    for prop, rods in props_rods:
        rows = []
        for k in range(STAGES):
            lo, hi = stage_box(prop, k)
            body = [part.bounds() for part in prop.present(k)] + [(c["lo"], c["hi"]) for c in prop.kenney_at(k)]
            rows.append({"height": round(hi[1], 3), "tris": stage_tris(prop, k),
                         "pieces": 1 + len(prop.present(k)) + len(prop.kenney_at(k)),
                         "x": [round(min(b[0][0] for b in body), 3), round(max(b[1][0] for b in body), 3)],
                         "z": [round(min(b[0][2] for b in body), 3), round(max(b[1][2] for b in body), 3)]})
        summary[prop.id] = {"lot": prop.lot, "footprint": [prop.w, prop.d], "stages": rows}
        log(f"{prop.id}: top/tris " + "  ".join(f"{row['height']:.2f}/{row['tris']}" for row in rows))
        problems = check(prop, rods)
        for msg in problems:
            log(f"  PROBLEM {prop.id}: {msg}")
        failures += len(problems)
    return summary, failures


def write_blueprints(props: list[Prop]) -> None:
    os.makedirs(BLUEPRINT_DIR, exist_ok=True)
    for prop in props:
        path = os.path.join(BLUEPRINT_DIR, f"{prop.id}.json")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(blueprint_text(prop))
    log(f"wrote {len(props)} blueprints -> {os.path.relpath(BLUEPRINT_DIR, REPO_ROOT)}")


def unused_glbs(props: list[Prop], out_dir: str) -> list[str]:
    """GLBs in the kit folder that no prop uses any more: pieces of earlier designs. They are
    harmless to the blueprints, but palette.py scans every GLB of a kit, so they are worth pruning
    before a merge (`--prune`)."""
    pieces = all_pieces(props)
    if not os.path.isdir(out_dir):
        return []
    return [name for name in sorted(os.listdir(out_dir)) if name.lower().endswith(".glb") and name[:-4] not in pieces]


def export_glbs(props: list[Prop], out_dir: str, prune: bool = False) -> None:
    """Blender only. Each piece is exported in kit units (studs / SCALE)."""
    import bpy  # noqa: PLC0415

    sys.path.insert(0, HERE)
    from garden_kit import build_object, export  # noqa: PLC0415

    os.makedirs(out_dir, exist_ok=True)
    pieces = all_pieces(props)
    if prune:
        for name in unused_glbs(props, out_dir):
            os.remove(os.path.join(out_dir, name))
    total = 0
    for name, part in pieces.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        scaled = Part(name)
        scaled.verts = [(round(x / SCALE, 6), round(y / SCALE, 6), round(z / SCALE, 6)) for x, y, z in part.verts]
        scaled.faces = part.faces
        export(build_object(scaled, {}), out_dir)
        total += part.tris
    colours = {c for part in pieces.values() for _, c in part.faces}
    log(f"{len(pieces)} pieces, {total} tris, {len(colours)} colours -> {os.path.relpath(out_dir, REPO_ROOT)}")


def in_blender() -> bool:
    try:
        import bpy  # noqa: F401, PLC0415
    except ImportError:
        return False
    return True


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the colony-kit GLBs and the Orbital fabric blueprints.")
    parser.add_argument("command", nargs="?", choices=("check",), help="check only: write nothing")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    parser.add_argument("--write-blueprints", action="store_true",
                        help="under Blender: also (re)write the blueprints (`py` always does)")
    parser.add_argument("--summary", help="write per-stage heights, extents and triangles here (JSON)")
    parser.add_argument("--prune", action="store_true", help="delete the kit folder's GLBs that no prop uses")
    parser.add_argument("--blender", default=os.environ.get("BLENDER", DEFAULT_BLENDER))
    args = parser.parse_args(argv)

    built = [build(pid) for pid in EVERY]
    props = [prop for prop, _ in built]
    summary, failures = report(built)
    if args.summary:
        with open(args.summary, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(summary, fh, indent=1)
        log(f"summary -> {args.summary}")

    if args.command == "check":
        stale = disk_problems(props, args.out)
        for msg in stale:
            log(f"  PROBLEM {msg}")
        failures += len(stale)
    elif in_blender():
        export_glbs(props, args.out, args.prune)
        if args.write_blueprints:
            write_blueprints(props)
    else:
        write_blueprints(props)
        done = subprocess.run([args.blender, "-b", "-P", os.path.abspath(__file__), "--", "--out", args.out]
                              + (["--prune"] if args.prune else []), capture_output=True, text=True)
        tail = [line for line in done.stdout.splitlines() if line.startswith(f"[{KIT}]") and "pieces," in line]
        if done.returncode not in (0, 1) or not tail:
            log(f"PROBLEM Blender export failed ({args.blender}): {done.stderr.strip()[-400:]}")
            failures += 1
        else:
            log(tail[-1][len(KIT) + 3:])
            stale = disk_problems(props, args.out)
            for msg in stale:
                log(f"  PROBLEM {msg}")
            failures += len(stale)

    stray = unused_glbs(props, args.out)
    if stray:
        log(f"note: {len(stray)} GLB(s) in the kit folder that no prop uses (--prune deletes them): {', '.join(stray)}")
    if failures:
        log(f"{failures} problem(s)")
        return 1
    log(f"check passed: {len(PROPS)} props and {len(TWINS)} Green twins, every rule")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else
                  ([] if in_blender() else sys.argv[1:])))
