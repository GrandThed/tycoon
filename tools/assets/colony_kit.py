"""Fabric buildings for the Orbital Colony growing city (M12 wave 4), generated as a Kenney-style kit.

    py tools/assets/colony_kit.py            # regenerate the GLBs and the twelve blueprints, then check
    py tools/assets/colony_kit.py check      # check only: the rules, the blueprints and GLBs on disk
    blender -b -P tools/assets/colony_kit.py [-- --out <dir>] [--write-blueprints]

Writes one GLB per piece into assets/kenney3d/colony-kit/Models/GLB format/, the folder convention
every Kenney kit uses, so tools/testfit/testfit.py, plotrender.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. The geometry and every check are plain Python; only the
GLB export needs Blender, so under `py` the script shells out to Blender for that one step
(`BLENDER=<path>` overrides the executable, as for plotrender.py).

Why a custom kit (docs/CITY_GROWTH.md sections 3 and 4, INTERFACES "Wave 4.1"): the fabric is the
small buildings the client draws on the lots around a player's landmarks, and they grow pod ->
pod cluster -> dome as the colony develops. space-kit's modules are 4 studs to a unit at the
landmarks' scale and every one of them is already a landmark's signature (the hex gate, the
corridor-end module, the round hangar), and none can grow a floor. So the pieces are generated,
one look per district, different in silhouette and not only in colour:

- habitat: white vaulted pods with blue stripes, then pods in a cluster, then glass domes that
  replace each other as they grow (the smaller one leaves with `untilStage`);
- industry: bullet tanks and silos, orange pipe runs, a refinery column and a flare stack;
- science: lab modules under long lit strips and solar roofs, dishes, and one slim mast;
- port: a gatehouse, a pale cargo pad, container stacks, a striped hangar, a gantry crane, a
  control cab, and (small and medium lots) a parked space-kit cargo craft at the last stages.

**Units.** Blueprints use `"scale": 2.0`, so that a space-kit cargo craft comes out at half the
landmarks' size (3.0 x 1.8 x 5.0 studs) and fits a lot. Every literal below is in **studs** in the
lot frame and is divided by SCALE once, at export; `check` works in studs too.

**Frames.** Every piece is authored in the lot frame: origin at the lot's bottom-centre, front -Z
(the tube), so a blueprint places all of a prop's own pieces at [0, 0, 0] and its stages register
exactly (the tower-kit pattern). Only the space-kit craft carries a position, computed here from
its measured bounding box, because space-kit origins are offset.

**Stages.** A piece is `<slug>-<stage>` when it stays for good and `<slug>-<stage>-u<last>` when
the blueprint retires it after stage <last> (a roof the next storey covers, a dome a larger one
replaces, crates a craft lands on). Staying pieces are closed boxes and lathes apart from faces on
the deck or on the roof they stand on, so retiring a piece never opens a hole.

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
LIT = (255, 225, 140)
WARN = (232, 120, 74)
# tube-kit's shell and ring, so a collar reads as part of the tube it docks to:
SHELL = (240, 242, 246)
RING = (190, 196, 206)
# CityDressing.json eras.OrbitalColony.road.tiles.blocks.color: the decking (contract).
DECK = (96, 98, 108)
DARK = {SLATE}

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
STOREY = 1.5
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


def wall_box(b: Box, face: str, u0, u1, d):
    """The plan (x0, x1, z0, z1) of a slab d proud of one wall of box b, spanning u0..u1 along it
    (x on front and back, z on the sides), and the face of it that lies on the wall."""
    x0, x1, z0, z1 = b
    if face == "front":
        return u0, u1, z0 - d, z0, "back"
    if face == "back":
        return u0, u1, z1, z1 + d, "front"
    if face == "left":
        return x0 - d, x0, u0, u1, "right"
    return x1, x1 + d, u0, u1, "left"


def panel(p: Part, b: Box, face: str, u0, u1, y0, y1, c: Rgb, d: float = GAP, **sides) -> None:
    """A slab d proud of one wall of box b; the face on the wall is left out."""
    xa, xb, za, zb, on_wall = wall_box(b, face, u0, u1, d)
    cube(p, xa, xb, y0, y1, za, zb, c, skip=(on_wall,), **sides)


# --- modules ------------------------------------------------------------------------------------


def module(p: Part, b: Box, y0, y1, wall: Rgb = HULL, roof: Rgb = PANEL) -> None:
    """A storey: a closed box standing on the deck or on the roof below."""
    x0, x1, z0, z1 = b
    cube(p, x0, x1, y0, y1, z0, z1, wall, skip=("bottom",), top=roof)


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


def lights(p: Part, b: Box, face: str, y0, y1, spans, c: Rgb = LIT) -> None:
    for u0, u1 in spans:
        panel(p, b, face, u0, u1, y0, y1, c)


def storey(p: Part, b: Box, y0, y1, stripe: Rgb | None, front=(), back=(), left=(), right=(),
           strip: bool = False, butt=()) -> None:
    """A module with its district stripe under the roof line and lit windows on each wall (spans
    along the wall). `strip` makes the windows one low band: the lab look."""
    module(p, b, y0, y1)
    if stripe:
        band(p, b, y1 - 0.34, y1 - 0.16, stripe, butt)
    wy = (y0 + 0.62, y0 + 0.9) if strip else (y0 + 0.5, y0 + 0.95)
    for face, spans in (("front", front), ("back", back), ("left", left), ("right", right)):
        lights(p, b, face, wy[0], wy[1], spans)


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


def vault_section(u0, u1, y0, rise):
    hw, cu = (u1 - u0) / 2, (u0 + u1) / 2
    return [(cu - hw, y0), (cu + hw, y0), (cu + hw * 0.8, y0 + rise * 0.62), (cu + hw * 0.42, y0 + rise),
            (cu - hw * 0.42, y0 + rise), (cu - hw * 0.8, y0 + rise * 0.62)]


def vault(p: Part, b: Box, y0, rise, c: Rgb = HULL, ridge: Rgb | None = PANEL, axis: str = "z") -> None:
    """A pod's arched roof over box b: closed at both ends, open underneath (it stands on a roof)."""
    x0, x1, z0, z1 = b
    u0, u1, a0, a1 = (x0, x1, z0, z1) if axis == "z" else (z0, z1, x0, x1)
    extrude(p, vault_section(u0, u1, y0, rise), axis, a0, a1, [c, c, c, ridge or c, c, c], cap0=c, cap1=c,
            skip=(0,))


def glass_vault(p: Part, b: Box, y0, rise, bays: int) -> None:
    """A greenhouse barrel along Z: glass bays in two blues between white end frames, a white spine."""
    x0, x1, z0, z1 = b
    sect = vault_section(x0, x1, y0, rise)
    end = 0.3
    cuts = [z0, z0 + end] + [z0 + end + (z1 - z0 - 2 * end) * i / bays for i in range(1, bays)] + [z1 - end, z1]
    for i in range(len(cuts) - 1):
        frame = i in (0, len(cuts) - 2)
        g = HULL if frame else (GLASS, GLASS_DEEP)[i % 2]
        extrude(p, sect, "z", cuts[i], cuts[i + 1], [g, g, g, HULL, g, g],
                cap0=HULL if i == 0 else None, cap1=HULL if i == len(cuts) - 2 else None, skip=(0,))


# --- round things -------------------------------------------------------------------------------


def drum(p: Part, cx, cz, y0, w, h, c: Rgb = HULL, top: Rgb = PANEL) -> None:
    lathe(p, [(rad(w), 0.0), (rad(w), h)], c, at=(cx, y0, cz), top=top)


def cone(p: Part, cx, cz, y0, w, h, c: Rgb = PANEL) -> None:
    """A shallow roof on a drum of width w."""
    lathe(p, [(rad(w), 0.0), (rad(w) * 0.4, h)], c, at=(cx, y0, cz), top=c)


def hoop(p: Part, cx, cz, y0, y1, w, c: Rgb) -> None:
    """A stripe GAP proud of a drum of width w. Its top is closed; its underside is a 0.05 rim that
    only shows from straight below, and is left out."""
    r = rad(w + 2 * GAP)
    lathe(p, [(r, 0.0), (r, y1 - y0)], c, at=(cx, y0, cz), top=c)


def facet_panel(p: Part, cx, cz, w, y0, y1, turn: float, half: float, c: Rgb = LIT) -> None:
    """A slab GAP proud of one flat of a drum of width w: `turn` 0 is the +X flat, 90 +Z, 270 -Z."""
    sub = Part("")
    cube(sub, w / 2, w / 2 + GAP, y0, y1, -half, half, c, skip=("left",))
    p.add(sub, turn, (cx, 0.0, cz))


def pod(p: Part, cx, cz, y0, w, h, stripe: Rgb | None, windows=(0, 90, 180, 270), half=None) -> None:
    """A round pod: a white drum with its district stripe and a lit window on the named flats."""
    drum(p, cx, cz, y0, w, h)
    if stripe:
        hoop(p, cx, cz, y0 + h - 0.36, y0 + h - 0.16, w, stripe)
    for turn in windows:
        facet_panel(p, cx, cz, w, y0 + 0.45, y0 + min(0.9, h - 0.42), turn, half or w * 0.14)


def dome_profile(r, y0, y1, bands, a_max=70.0):
    """A faceted hemisphere flattened into `bands` rings; it stops short of the pole and closes
    with a flat cap."""
    am = math.radians(a_max)
    return [(r * math.cos(am * i / bands), y0 + (y1 - y0) * math.sin(am * i / bands) / math.sin(am))
            for i in range(bands + 1)]


def dome(p: Part, cx, cz, y0, w, h, bands: int = 3, ring: float = 0.25, ribs: bool = True) -> None:
    """A glass dome w across and h tall on a white base ring: panes in two blues, a white cap and
    white ribs GAP proud of the eight meridians (0.14 wide, so they hold at the tycoon camera)."""
    lathe(p, [(rad(w), 0.0), (rad(w), ring)], HULL, at=(cx, y0, cz), top=HULL)
    prof = dome_profile(rad(w - 0.16), ring, h, bands)
    lathe(p, prof, lambda k, i: (GLASS, GLASS_DEEP)[(k + i) % 2], at=(cx, y0, cz), top=HULL)
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


def core(p: Part, cx, cz, y0, y1, w, rows, stripe: Rgb = HAB) -> None:
    """The white tower that rises through a bubble: lit windows in rows, a stripe, a glass cap."""
    drum(p, cx, cz, y0, w, y1 - y0)
    hoop(p, cx, cz, y1 - 0.36, y1 - 0.16, w, stripe)
    for yy in rows:
        for turn in (0, 90, 180, 270):
            facet_panel(p, cx, cz, w, yy, yy + 0.45, turn, w * 0.2)
    dome(p, cx, cz, y1, w, w * 0.52, bands=2, ring=0.15, ribs=False)


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


def sphere(p: Part, cx, cz, y0, w, stand: float = 0.5) -> None:
    """A sphere tank on a grey pedestal, with an orange equator."""
    r = w / 2 / math.cos(PHASE)
    cy = y0 + stand + w * 0.44
    drum(p, cx, cz, y0, w * 0.5, stand + w * 0.1, PANEL, PANEL)
    prof = [(r * math.cos(math.radians(a)), w * 0.44 / math.sin(math.radians(62)) * math.sin(math.radians(a)))
            for a in (-62, -22, 22, 62)]
    lathe(p, prof, [HULL, TRIM, HULL], at=(cx, cy, cz), top=PANEL, bottom=PANEL)


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
    """A habitat's garden tray: white walls, a green bed, a row of shrubs."""
    cube(p, x0, x1, y, y + 0.28, z0, z1, HULL, skip=("bottom",), top=PLANT)
    along_x = (x1 - x0) >= (z1 - z0)
    n = max(1, min(4, int(max(x1 - x0, z1 - z0) / 0.48)))
    s = 0.17
    for i in range(n):
        k = (i + 0.5) / n
        cx = x0 + (x1 - x0) * k if along_x else (x0 + x1) / 2
        cz = (z0 + z1) / 2 if along_x else z0 + (z1 - z0) * k
        cube(p, cx - s, cx + s, y + 0.28, y + 0.28 + 2 * s, cz - s, cz + s, PLANT, skip=("bottom",))


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


def hangar(p: Part, b: Box, y0, hs, h, axis: str = "z", door_end: int = 0) -> None:
    """A cargo hangar: white walls to hs, a grey roof that folds up to a flat top at h, and on one
    end a grey roller door with two orange stripes under a lit strip. The upper stripe runs on
    round the walls, and the far end has two lit windows."""
    x0, x1, z0, z1 = b
    u0, u1, a0, a1 = (x0, x1, z0, z1) if axis == "z" else (z0, z1, x0, x1)
    ch = 0.26 * (u1 - u0)
    sect = [(u0, y0), (u1, y0), (u1, y0 + hs), (u1 - ch, y0 + h), (u0 + ch, y0 + h), (u0, y0 + hs)]
    extrude(p, sect, axis, a0, a1, [HULL, HULL, PANEL, PANEL, PANEL, HULL], cap0=HULL, cap1=HULL, skip=(0,))
    a, s = (a0, -1) if door_end == 0 else (a1, 1)
    cu, dw, dh = (u0 + u1) / 2, 0.3 * (u1 - u0), hs * 0.9
    end_slab(p, axis, a, s, 0.0, GAP, cu - dw, cu + dw, y0, y0 + dh, PANEL)
    for k in (0.22, 0.58):
        end_slab(p, axis, a, s, GAP, 2 * GAP, cu - dw, cu + dw, y0 + dh * k, y0 + dh * k + 0.22, TRIM)
    end_slab(p, axis, a, s, 0.0, GAP, cu - dw, cu + dw, y0 + dh + 0.12, y0 + dh + 0.36, LIT)
    door_side = {("z", 0): "front", ("z", 1): "back", ("x", 0): "left", ("x", 1): "right"}[(axis, door_end)]
    band(p, b, y0 + dh * 0.58, y0 + dh * 0.58 + 0.22, TRIM, butt=(door_side,))
    far = a1 if door_end == 0 else a0
    for k in (-0.5, 0.5):
        end_slab(p, axis, far, -s, 0.0, GAP, cu + k * dw * 2 - 0.4, cu + k * dw * 2 + 0.4, y0 + 0.5, y0 + 0.95, LIT)


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


def control_cab(p: Part, shaft: Box, cab: Box, y0, y1, y2) -> float:
    """A control tower on a roof: a white shaft from y0 to y1, then a wider cab to y2 with a glass
    band all round, a grey roof and a lit beacon. Returns the top."""
    module(p, shaft, y0, y1)
    x0, x1, z0, z1 = cab
    cube(p, x0, x1, y1, y2, z0, z1, HULL, top=PANEL)
    band(p, cab, y1 + 0.3, y2 - 0.25, GLASS)
    return beacon(p, (x0 + x1) / 2, (z0 + z1) / 2, y2)


# --- props --------------------------------------------------------------------------------------


class Prop:
    """One fabric building: its pieces by (stage, last stage or None) and its space-kit pieces."""

    def __init__(self, pid: str, lot: str):
        self.id = pid
        self.lot = lot
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
        """Own pieces in blueprint order: by stage, the staying piece first."""
        return sorted(self.parts.items(), key=lambda kv: (kv[0][0], -1 if kv[0][1] is None else kv[0][1]))

    def present(self, k: int) -> list[Part]:
        return [part for (stage, until), part in self.pieces() if stage <= k and (until is None or k <= until)]

    def kenney_at(self, k: int) -> list[dict]:
        return [c for c in self.kenney if c["stage"] <= k and (c["until"] is None or k <= c["until"])]


def floors() -> list[float]:
    """Floor lines from the deck up."""
    return [D + STOREY * k for k in range(6)]


def hab_narrow_a(P: Prop) -> None:
    """A terrace pod under a vault; the back half gains a storey and a roof garden, then carries
    a dome that is replaced by a larger one at each stage, and the low front keeps its garden."""
    body = (-1.95, 1.95, -3.5, 3.6)
    front = (-1.95, 1.95, -3.5, -0.6)
    rear = (-1.95, 1.95, -0.6, 3.6)
    y = floors()
    fs, rs = [(-2.9, -1.9)], [(0.4, 1.4), (2.0, 3.0)]
    p = P.part(0)
    bk = [(-1.3, -0.3), (0.3, 1.3)]
    storey(p, body, y[0], y[1], HAB, front=[(-1.7, -1.15), (1.15, 1.7)], left=fs + rs, right=fs + rs, back=bk)
    airlock(P, p, 0.0)
    vault(P.part(0, 0), body, y[1], 0.9)
    storey(P.part(1), rear, y[1], y[2], HAB, front=[(-1.5, -0.4), (0.4, 1.5)], left=rs, right=rs, back=bk)
    planter(P.part(1, 1), -1.5, 1.5, 0.2, 0.9, y[2])
    tank_v(P.part(1, 1), 0.9, 2.6, y[2], 1.0, 0.6, None)
    planter(P.part(1, 2), -1.6, 1.6, -3.2, -2.5, y[1])
    dome(P.part(2, 2), 0.0, 1.5, y[2], 3.3, 1.7, bands=2)
    p = P.part(3)
    storey(p, rear, y[2], y[3], HAB, front=[(-1.5, -0.4), (0.4, 1.5)], left=rs, right=rs, back=bk)
    storey(p, front, y[1], y[2], HAB, front=[(-1.5, -0.4), (0.4, 1.5)], left=fs, right=fs, butt=("back",))
    dome(P.part(3, 3), 0.0, 1.5, y[3], 3.5, 1.85)
    planter(P.part(3, 3), -1.6, 1.6, -3.2, -2.5, y[2])
    p = P.part(4)
    storey(p, rear, y[3], y[4], HAB, front=[(-1.5, -0.4), (0.4, 1.5)], left=rs, right=rs, back=bk)
    dome(p, 0.0, 1.5, y[4], 3.7, 1.9)
    dome(p, 0.0, -2.05, y[2], 2.6, 1.35, bands=2)


def hab_narrow_b(P: Prop) -> None:
    """A terrace pod with a greenhouse behind it: the front climbs under a white vault and ends in
    a small dome, the back grows from a store into a long glass barrel."""
    front = (-1.95, 1.95, -3.5, -0.4)
    rear = (-1.95, 1.95, -0.4, 3.6)
    y = floors()
    fs, rs = [(-2.9, -1.9), (-1.6, -0.7)], [(0.3, 1.3), (1.9, 2.9)]
    win = [(-1.5, -0.4), (0.4, 1.5)]
    p = P.part(0)
    storey(p, front, y[0], y[1], HAB, front=[(-1.7, -1.15), (1.15, 1.7)], left=fs, right=fs)
    airlock(P, p, 0.0)
    module(p, rear, D, D + 1.0)
    vault(P.part(0, 1), front, y[1], 0.9)
    r = P.part(0, 0)
    planter(r, -1.6, 0.2, 0.3, 1.1, D + 1.0)
    tank_v(r, 1.0, 2.5, D + 1.0, 1.1, 1.15, HAB)
    p = P.part(1)
    module(p, rear, D + 1.0, y[1])
    lights(p, rear, "left", D + 0.5, D + 0.95, rs)
    lights(p, rear, "right", D + 0.5, D + 0.95, rs)
    glass_vault(P.part(1, 2), rear, y[1], 1.5, 3)
    storey(P.part(2), front, y[1], y[2], HAB, front=win, left=fs, right=fs)
    vault(P.part(2, 2), front, y[2], 0.9)
    p = P.part(3)
    storey(p, front, y[2], y[3], HAB, front=win, left=fs, right=fs)
    storey(p, rear, y[1], y[2], HAB, left=rs, right=rs, back=[(-1.3, -0.3), (0.3, 1.3)], butt=("front",))
    glass_vault(p, rear, y[2], 1.5, 3)
    vault(P.part(3, 3), front, y[3], 0.9)
    p = P.part(4)
    storey(p, front, y[3], y[4], HAB, front=win, left=fs, right=fs)
    dome(p, 0.0, -1.95, y[4], 2.9, 1.45, bands=2)


def hab_small_a(P: Prop) -> None:
    """A round pod, then a cluster of three with an upper pod, a first dome on it, and at last a
    bubble over the whole cluster with a white core rising through it."""
    cx, cz = 0.0, 0.55
    vest = (-0.85, 0.85, -2.5, cz - 1.6)  # up to the pod's front flat
    y1 = D + STOREY
    p = P.part(0)
    module(p, vest, D, y1)
    band(p, vest, y1 - 0.34, y1 - 0.16, HAB, butt=("back",))
    airlock(P, p, 0.0)
    planter(p, 1.9, 2.9, -2.9, -2.3, D)
    planter(p, -2.9, -1.9, -2.9, -2.3, D)
    pod(P.part(0, 2), cx, cz, D, 3.2, STOREY, HAB, windows=(0, 90, 180), half=0.45)
    cone(P.part(0, 0), cx, cz, y1, 3.2, 0.6)
    q = P.part(1, 3)
    for sx in (-1, 1):
        pod(q, sx * 1.9, 1.9, D, 2.0, 1.2, HAB, windows=(90, 0 if sx > 0 else 180), half=0.3)
        cone(q, sx * 1.9, 1.9, D + 1.2, 2.0, 0.4)
    pod(P.part(1, 2), cx, cz, y1, 2.6, 1.3, HAB, half=0.35)
    cone(P.part(1, 1), cx, cz, y1 + 1.3, 2.6, 0.55)
    dome(P.part(2, 2), cx, cz, y1 + 1.3, 2.6, 1.45, bands=2)
    b = P.part(3, 3)
    dome(b, cx, cz, D, 4.8, 2.9, ring=0.6)
    core(b, cx, cz, 2.5, 5.0, 1.5, rows=(3.4, 4.1))
    p = P.part(4)
    dome(p, 0.0, 0.15, D, 5.6, 3.5, ring=0.7)
    core(p, 0.0, 0.15, 3.0, 6.4, 1.8, rows=(3.9, 4.6, 5.5))
    platform(p, 0.0, 0.15, 5.2, 3.0, HAB)


def hab_medium_a(P: Prop) -> None:
    """A long entrance pod and a round pod behind it; pods gather round, a dome rises on the middle
    one, then a bubble covers the cluster and grows to fill the lot, a white core through its top."""
    fp = (-1.75, 1.75, -5.5, -1.7)
    cx, cz = 0.0, 2.15
    y = floors()
    side = [(-5.0, -4.0), (-3.2, -2.2)]
    p = P.part(0)
    storey(p, fp, y[0], y[1], HAB, front=[(-1.55, -1.1), (1.1, 1.55)], left=side, right=side)
    airlock(P, p, 0.0)
    planter(p, -3.7, -2.3, -5.7, -5.0, D)
    planter(p, 2.3, 3.7, -5.7, -5.0, D)
    vault(P.part(0, 3), fp, y[1], 0.9)
    pod(P.part(0, 2), cx, cz, D, 3.6, STOREY, HAB, windows=(0, 90, 180), half=0.5)
    r = P.part(0, 0)
    cone(r, cx, cz, y[1], 3.6, 0.65)
    pod(r, -2.75, 3.4, D, 1.9, 1.2, HAB, windows=(90, 180, 270), half=0.3)
    cone(r, -2.75, 3.4, D + 1.2, 1.9, 0.4)
    planter(r, 2.4, 3.2, 1.0, 4.4, D)
    q = P.part(1, 3)
    for sx in (-1, 1):
        pod(q, sx * 2.75, 3.4, D, 2.4, 1.4, HAB, windows=(90, 0 if sx > 0 else 180, 270), half=0.35)
        cone(q, sx * 2.75, 3.4, D + 1.4, 2.4, 0.45)
    pod(q, 0.0, 4.95, D, 1.9, 1.3, HAB, windows=(90,), half=0.3)
    cone(q, 0.0, 4.95, D + 1.3, 1.9, 0.4)
    pod(P.part(1, 2), cx, cz, y[1], 3.0, 1.4, HAB, half=0.4)
    cone(P.part(1, 1), cx, cz, y[1] + 1.4, 3.0, 0.6)
    dome(P.part(2, 2), cx, cz, y[1] + 1.4, 3.0, 1.6, bands=2)
    b = P.part(3, 3)
    dome(b, cx, cz, D, 6.0, 3.5, ring=0.65)
    core(b, cx, cz, 3.0, 6.0, 1.9, rows=(4.1, 4.9))
    p = P.part(4)
    dome(p, cx, cz, D, 7.6, 4.3, ring=0.75)
    core(p, cx, cz, 3.7, 8.2, 2.3, rows=(4.9, 5.7, 6.9))
    platform(p, cx, cz, 6.4, 3.6, HAB)
    storey(p, fp, y[1], y[2], HAB, front=[(-1.4, -0.3), (0.3, 1.4)], left=side, right=side)
    vault(p, fp, y[2], 0.9)


def ind_narrow_a(P: Prop) -> None:
    """A control hut and bullet tanks across the lot; an orange manifold and a flue, a refinery
    column at the back that grows a section, a third tank on a beam, and last a flare stack."""
    hut = (-1.6, 1.6, -3.5, -1.5)
    y1 = D + STOREY
    p = P.part(0)
    storey(p, hut, D, y1, IND, front=[(-1.45, -1.1), (1.1, 1.45)], left=[(-3.0, -2.0)], right=[(-3.0, -2.0)])
    airlock(P, p, 0.0)
    tank_h(p, "x", -1.75, 1.75, -0.45, D, 1.5)
    cube(p, -0.35, 0.35, y1, y1 + 0.5, -2.9, -2.2, PANEL, skip=("bottom",), top=TRIM)
    p = P.part(1)
    tank_h(p, "x", -1.75, 1.75, 1.35, D, 1.5)
    pipe(p, [(0.9, 1.84, -0.45), (0.9, 2.6, -0.45), (0.9, 2.6, 1.35), (0.9, 1.84, 1.35)])
    stack(p, -1.0, -2.5, y1, y1 + 1.75, 0.6, 0.45, tip=TRIM, tip_h=0.3)
    column(P.part(2), 0.0, 3.05, D, 5.8, 1.3, stripes=(2.4, 4.7), decks=(3.5,), deck_w=1.85)
    p = P.part(3)
    column(p, 0.0, 3.05, 5.8, 7.8, 1.0, stripes=(7.1,), decks=(6.2,), deck_w=1.8)
    for x in (-1.95, 1.75):
        cube(p, x, x + 0.2, D, 2.8, 0.35, 0.55, PANEL, skip=("bottom", "top"))
    cube(p, -1.95, 1.95, 2.8, 3.0, 0.15, 0.75, PANEL)
    tank_h(p, "x", -1.6, 1.6, 0.45, 3.0, 1.3, clear=0.0)
    p = P.part(4)
    stack(p, 1.0, -2.5, y1, 10.4, 0.8, 0.5)
    hoop(p, 1.0, -2.5, 5.2, 5.45, 0.7, TRIM)


def ind_small_a(P: Prop) -> None:
    """A control hut and a silo; a second, taller silo joined by an orange pipe, a column that
    grows a section, a pipe run over the yard, and a flare stack on top of the column."""
    hut = (-2.7, -0.5, -2.5, -0.9)
    y1 = D + STOREY
    p = P.part(0)
    storey(p, hut, D, y1, IND, left=[(-2.2, -1.2)], right=[(-2.2, -1.2)], back=[(-2.2, -1.0)])
    airlock(P, p, -1.6)
    tank_v(p, 1.45, 1.4, D, 2.4, 2.5, at=0.5)
    p = P.part(1)
    tank_v(p, -1.5, 1.5, D, 2.2, 3.4)
    pipe(p, [(0.4, 1.9, 1.45), (-0.5, 1.9, 1.45)])
    column(P.part(2), 1.6, -1.75, D, 5.9, 1.1, stripes=(2.0, 4.4), decks=(3.2,), deck_w=1.9)
    p = P.part(3)
    column(p, 1.6, -1.75, 5.9, 7.8, 0.9, stripes=(7.1,), decks=(6.3,), deck_w=1.7)
    pipe(p, [(-1.5, 3.3, 1.5), (-1.5, 3.9, 1.5), (-1.5, 3.9, -1.75), (1.2, 3.9, -1.75)])
    p = P.part(4)
    stack(p, 1.6, -1.75, 7.8, 10.6, 0.7, 0.5)
    tank_v(p, 0.3, -0.1, D, 1.3, 2.9, at=0.6)


def ind_medium_a(P: Prop) -> None:
    """A small refinery: a control hut, a bullet tank and a silo; a second silo and a pipe rack
    down the yard; a column; a furnace with its stack; then the stack and the column grow and a
    sphere tank arrives."""
    hut = (-3.6, -0.8, -5.5, -3.3)
    fur = (0.9, 3.7, 2.6, 5.7)
    y1 = D + STOREY
    p = P.part(0)
    storey(p, hut, D, y1, IND, front=[(-1.15, -0.9)], left=[(-5.0, -4.0)], right=[(-5.0, -4.0)],
           back=[(-3.2, -1.2)])
    airlock(P, p, -2.2)
    tank_h(p, "z", -5.5, -2.1, 2.5, D, 1.6)
    tank_h(p, "z", -5.5, -2.1, 0.6, D, 1.6)
    tank_v(p, -2.2, -1.2, D, 2.4, 2.6)
    q = P.part(0, 2)
    crates(q, 2.4, 3.4, D, [TRIM, HULL], along="z")
    crates(q, 1.6, 4.9, D, [HULL])
    p = P.part(1)
    tank_v(p, -2.3, 1.7, D, 2.2, 3.7)
    for z in (-1.4, 1.6, 4.6):
        for x in (-0.3, 0.52):
            cube(p, x, x + 0.18, D, 3.0, z - 0.09, z + 0.09, PANEL, skip=("bottom", "top"))
        cube(p, -0.3, 0.7, 3.0, 3.2, z - 0.14, z + 0.14, PANEL)
    cube(p, -0.2, 0.02, 3.2, 3.42, -1.7, 4.9, TRIM)
    cube(p, 0.38, 0.6, 3.2, 3.42, -1.7, 4.9, HULL)
    column(P.part(2), 2.3, 0.6, D, 6.8, 1.6, stripes=(2.2, 5.3), decks=(3.8,), deck_w=2.6)
    p = P.part(3)
    module(p, fur, D, D + 3.0)
    band(p, fur, D + 2.5, D + 2.75, TRIM)
    lights(p, fur, "front", D + 0.4, D + 0.8, [(1.3, 2.0), (2.6, 3.3)], WARN)
    lights(p, fur, "right", D + 0.4, D + 0.8, [(3.0, 3.7), (4.5, 5.2)], WARN)
    stack(p, 2.3, 4.15, D + 3.0, 9.4, 1.3, 1.0, tip=None)
    hoop(P.part(3, 3), 2.3, 4.15, 9.05, 9.3, 1.0, TRIM)
    p = P.part(4)
    stack(p, 2.3, 4.15, 9.4, 12.2, 1.0, 0.75)
    hoop(p, 2.3, 4.15, 9.2, 9.45, 1.0, TRIM)
    column(p, 2.3, 0.6, 6.8, 8.6, 1.25, stripes=(7.9,), decks=(7.0,), deck_w=2.3)
    sphere(p, -2.3, 4.4, D, 2.6)


def sci_narrow_a(P: Prop) -> None:
    """A lab under a long lit strip and a solar roof, a dish behind it; a rear module takes the
    dish on its roof, the lab gains a floor and a glass cab, and the mast climbs at every stage."""
    lab = (-1.95, 1.95, -3.5, 0.4)
    rear = (-1.95, 1.95, 0.4, 3.6)
    cab = (-1.5, 1.5, -3.1, -0.3)
    y = floors()
    long, short = [(-3.1, 0.0)], [(0.8, 3.2)]
    p = P.part(0)
    storey(p, lab, y[0], y[1], SCI, front=[(-1.7, -1.15), (1.15, 1.7)], left=long, right=long, strip=True)
    airlock(P, p, 0.0)
    solar(P.part(0, 1), -1.5, 1.5, -3.0, -0.2, y[1], 2, 2)
    r = P.part(0, 0)
    dish(r, 0.3, 2.0, D, 2.0)
    mast(r, -1.3, 3.2, D, 2.3, arms=(0.7,))
    p = P.part(1)
    storey(p, rear, y[0], y[1], SCI, left=short, right=short, back=[(-1.4, 1.4)], strip=True, butt=("front",))
    dish(P.part(1, 2), 0.3, 2.0, y[1], 2.2, stand=0.55)
    mast(P.part(1, 1), -1.3, 3.2, y[1], 1.87, arms=(0.7,))
    p = P.part(2)
    storey(p, lab, y[1], y[2], SCI, front=[(-1.6, 1.6)], left=long, right=long, strip=True)
    solar(P.part(2, 2), -1.5, 1.5, -3.0, -0.2, y[2], 2, 2)
    mast(P.part(2, 2), -1.3, 3.2, y[1], 3.9)
    p = P.part(3)
    cube(p, cab[0], cab[1], y[2], y[2] + 1.3, cab[2], cab[3], HULL, skip=("bottom",), top=PANEL)
    band(p, cab, y[2] + 0.4, y[2] + 0.95, GLASS)
    storey(p, rear, y[1], y[2], SCI, left=short, right=short, back=[(-1.4, 1.4)], strip=True, butt=("front",))
    dish(p, 0.3, 2.0, y[2], 2.8, stand=0.6)
    mast(P.part(3, 3), -1.3, 3.2, y[2], 4.0, foot=1.4)
    p = P.part(4)
    mast(p, -1.3, 3.2, y[2], 6.4, arms=(0.5, 0.72, 0.9), tip=HOLO, foot=2.4)
    solar(p, -1.2, 1.2, -2.8, -0.6, y[2] + 1.3, 2, 1)


def sci_small_a(P: Prop) -> None:
    """A round lab with a dish on its roof and a solar array beside it; a wing with its own array,
    a second and third floor that lift a larger dish, and a mast in the back corner."""
    cx, cz = -0.8, 0.6
    vest = (-1.6, 0.0, -2.5, cz - 1.7)  # up to the lab's front flat
    wing = (1.1, 2.8, -1.2, 2.7)
    y = floors()
    mx, mz = -2.3, 2.6
    p = P.part(0)
    module(p, vest, D, y[1])
    band(p, vest, y[1] - 0.34, y[1] - 0.16, SCI, butt=("back",))
    airlock(P, p, -0.8)
    pod(p, cx, cz, D, 3.4, STOREY, SCI, windows=(0, 90, 180), half=0.6)
    cube(p, 1.2, 2.8, D, D + 0.35, -2.75, -1.55, PANEL, skip=("bottom",))
    solar(p, 1.2, 2.8, -2.75, -1.55, D + 0.35, 2, 1)
    dish(P.part(0, 1), cx, cz, y[1], 1.8, stand=0.45)
    p = P.part(1)
    storey(p, wing, D, y[1], SCI, front=[(1.3, 2.6)], right=[(-0.9, 2.4)], back=[(1.4, 2.5)], strip=True)
    solar(P.part(1, 2), 1.3, 2.6, -0.9, 2.4, y[1], 1, 2)
    mast(P.part(1, 1), mx, mz, D, 3.35, foot=1.2)
    p = P.part(2)
    pod(p, cx, cz, y[1], 3.0, STOREY, SCI, half=0.5)
    dish(P.part(2, 3), cx, cz, y[2], 3.0, stand=0.55)
    mast(P.part(2, 2), mx, mz, D, 4.6, foot=1.6)
    p = P.part(3)
    storey(p, wing, y[1], y[2], SCI, front=[(1.3, 2.6)], right=[(-0.9, 2.4)], back=[(1.4, 2.5)], strip=True)
    solar(p, 1.3, 2.6, -0.9, 2.4, y[2], 1, 2)
    mast(P.part(3, 3), mx, mz, D, 7.0, foot=2.6)
    p = P.part(4)
    pod(p, cx, cz, y[2], 2.6, STOREY, SCI, half=0.42)
    dish(p, cx, cz, y[3], 3.0, stand=0.55)
    mast(p, mx, mz, D, 9.4, arms=(0.5, 0.72, 0.9), tip=HOLO, foot=3.4)


def port_narrow_a(P: Prop) -> None:
    """A gatehouse and a cargo pad with a few containers; the stacks grow under a floodlight, a
    control cab rises on the gatehouse, a gantry crane spans the pad, and a mast tops the cab."""
    gate = (-1.5, 1.5, -3.5, -2.0)
    y1 = D + STOREY
    p = P.part(0)
    storey(p, gate, D, y1, PORT, left=[(-3.2, -2.3)], right=[(-3.2, -2.3)], back=[(-1.2, 1.2)])
    airlock(P, p, 0.0)
    top = pad(p, (-1.85, 1.85, -1.75, 3.8))
    beacon(p, 0.85, -2.75, y1)
    q = P.part(0, 0)
    crates(q, -0.9, 3.0, top, [CRATES[0]])
    crates(q, 0.9, 3.0, top, [CRATES[1], CRATES[2]])
    p = P.part(1)
    crates(p, -0.9, 3.25, top, [CRATES[0], CRATES[2], CRATES[1]])
    crates(p, 0.9, 3.25, top, [CRATES[1], CRATES[3]])
    crates(p, -0.9, 2.3, top, [CRATES[3]])
    crates(p, 0.9, 2.3, top, [CRATES[2], CRATES[0]])
    lamp_mast(p, 1.67, -1.0, top, 2.9)
    control_cab(P.part(2), (-1.5, 0.1, -3.5, -2.0), (-1.75, 0.35, -3.75, -1.75), y1, 2.95, 3.9)
    gantry(P.part(3), -1.85, 1.85, 0.75, top, 5.0, 0.2, CRATES[0], drop=1.5)
    p = P.part(4)
    mast(p, -0.7, -3.2, 3.9, 2.8, arms=(0.55, 0.8))
    crates(p, -0.9, 2.3, top + 0.75, [CRATES[1], CRATES[0]])
    crates(p, 0.9, 3.25, top + 1.5, [CRATES[2]])


def port_small_a(P: Prop) -> None:
    """A gatehouse and a cargo pad with containers; taller stacks and a floodlight, a striped
    hangar facing the pad, a control cab, and last a cargo craft parked where the containers stood."""
    gate = (-2.8, -0.75, -2.5, -1.0)
    shed = (-2.85, -0.6, -0.35, 2.85)
    y1 = D + STOREY
    p = P.part(0)
    storey(p, gate, D, y1, PORT, left=[(-2.2, -1.3)], right=[(-2.2, -1.3)], back=[(-2.5, -1.1)])
    airlock(P, p, -1.775)
    top = pad(p, (-0.3, 2.85, -2.85, 2.85))
    beacon(p, -1.2, -1.75, y1)
    q = P.part(0, 3)
    crates(q, 0.35, 1.9, top, [CRATES[0]], along="z")
    crates(q, 1.3, 1.9, top, [CRATES[2], CRATES[1]], along="z")
    q = P.part(1, 3)
    crates(q, 0.35, 1.9, top + 0.75, [CRATES[1], CRATES[3]], along="z")
    crates(q, 2.25, 1.9, top, [CRATES[3], CRATES[0]], along="z")
    crates(q, 0.35, 0.1, top, [CRATES[2]], along="z")
    crates(q, 1.3, 0.1, top, [CRATES[0], CRATES[1]], along="z")
    lamp_mast(P.part(1), -2.55, -0.68, D, 3.0)
    p = P.part(2)
    hangar(p, shed, D, 2.0, 3.3, axis="x", door_end=1)
    beacon(p, -1.7, 1.25, D + 3.3)
    control_cab(P.part(3), (-2.8, -1.4, -2.5, -1.0), (-2.95, -1.15, -2.75, -0.85), y1, 3.5, 4.5)
    p = P.part(4)
    mast(p, -2.4, -1.8, 4.5, 2.2, arms=(0.55, 0.8))
    P.craft("craft_cargoB", 1.35, 0.1, top, 0, 4)
    crates(p, -0.9, -0.68, D, [CRATES[0], CRATES[2]], along="x", length=1.0, width=0.5, h=0.6)


def port_medium_a(P: Prop) -> None:
    """A small spaceport: a gatehouse, a wide pad and a container yard; floodlights, a hangar across
    the back, a control tower and a parked cargo craft, then a gantry crane over the yard."""
    gate = (-3.6, -1.4, -5.5, -3.9)
    han = (-3.8, 3.8, 1.4, 5.8)
    y1 = D + STOREY
    p = P.part(0)
    storey(p, gate, D, y1, PORT, left=[(-5.2, -4.2)], right=[(-5.2, -4.2)], back=[(-3.3, -1.7)])
    airlock(P, p, -2.5)
    top = pad(p, (-0.9, 3.85, -5.85, 0.5))
    beacon(p, -1.85, -4.7, y1)
    crates(p, -2.5, 0.3, D, [CRATES[0], CRATES[1]])
    crates(p, -2.5, -0.65, D, [CRATES[2]])
    q = P.part(0, 2)
    crates(q, 0.0, -0.4, top, [CRATES[3], CRATES[0]])
    crates(q, 1.8, -0.4, top, [CRATES[1]])
    q = P.part(0, 1)
    crates(q, -1.6, 3.2, D, [CRATES[1], CRATES[3]])
    crates(q, 1.4, 4.4, D, [CRATES[2]], along="z")
    crates(q, 2.5, 2.6, D, [CRATES[0]])
    p = P.part(1)
    crates(p, -2.5, -0.65, D + 0.75, [CRATES[3], CRATES[0]])
    crates(p, -2.5, -1.6, D, [CRATES[1], CRATES[2]])
    crates(p, -2.5, -2.55, D, [CRATES[0]])
    lamp_mast(p, 3.6, 0.9, D, 3.0)
    lamp_mast(p, -3.7, -3.4, D, 3.0)
    crates(P.part(1, 2), 1.8, -0.4, top + 0.75, [CRATES[2], CRATES[3]])
    p = P.part(2)
    hangar(p, han, D, 2.4, 3.8, axis="z", door_end=0)
    beacon(p, -1.6, 3.6, D + 3.8)
    beacon(p, 1.6, 3.6, D + 3.8)
    control_cab(P.part(3), (-3.6, -2.2, -5.5, -3.9), (-3.85, -1.95, -5.75, -3.65), y1, 4.2, 5.25)
    P.craft("craft_cargoA", 1.5, -2.9, top, 0, 3)
    p = P.part(4)
    gantry(p, -3.8, -1.2, -1.15, D, 4.9, -2.5, CRATES[2], drop=1.0)
    mast(p, -2.9, -4.7, 5.25, 3.2, arms=(0.5, 0.75))
    crates(p, -2.5, -2.55, D + 0.75, [CRATES[3], CRATES[1]])


# Blueprint id -> (lot, builder), in the order of INTERFACES "Wave 4.1".
PROPS = {
    "FabricHabNarrowA": ("narrow", hab_narrow_a),
    "FabricHabNarrowB": ("narrow", hab_narrow_b),
    "FabricIndNarrowA": ("narrow", ind_narrow_a),
    "FabricSciNarrowA": ("narrow", sci_narrow_a),
    "FabricPortNarrowA": ("narrow", port_narrow_a),
    "FabricHabSmallA": ("small", hab_small_a),
    "FabricIndSmallA": ("small", ind_small_a),
    "FabricSciSmallA": ("small", sci_small_a),
    "FabricPortSmallA": ("small", port_small_a),
    "FabricHabMediumA": ("medium", hab_medium_a),
    "FabricIndMediumA": ("medium", ind_medium_a),
    "FabricPortMediumA": ("medium", port_medium_a),
}
STAGES = 5


def deck(lot: str) -> Part:
    """The deck plate that covers a whole lot from stage 0: decking arrives lot by lot."""
    w, d = LOTS[lot]
    p = Part(f"deck-{lot}")
    cube(p, -w / 2, w / 2, 0.0, D, -d / 2, d / 2, DECK, skip=("bottom",))
    return p


def build(pid: str) -> tuple[Prop, list[tuple[float, float, float]]]:
    lot, make = PROPS[pid]
    RODS.clear()
    prop = Prop(pid, lot)
    make(prop)
    return prop, list(RODS)


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
            assert part.name not in pieces, f"two pieces are named {part.name}"
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


def export_glbs(props: list[Prop], out_dir: str) -> None:
    """Blender only. Each piece is exported in kit units (studs / SCALE)."""
    import bpy  # noqa: PLC0415

    sys.path.insert(0, HERE)
    from garden_kit import build_object, export  # noqa: PLC0415

    os.makedirs(out_dir, exist_ok=True)
    pieces = all_pieces(props)
    for name in sorted(os.listdir(out_dir)):  # the folder is this kit's own: a GLB no prop uses is stale
        if name.lower().endswith(".glb") and name[:-4] not in pieces:
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
    parser.add_argument("--blender", default=os.environ.get("BLENDER", DEFAULT_BLENDER))
    args = parser.parse_args(argv)

    built = [build(pid) for pid in PROPS]
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
        export_glbs(props, args.out)
        if args.write_blueprints:
            write_blueprints(props)
    else:
        write_blueprints(props)
        done = subprocess.run([args.blender, "-b", "-P", os.path.abspath(__file__), "--", "--out", args.out],
                              capture_output=True, text=True)
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

    if failures:
        log(f"{failures} problem(s)")
        return 1
    log("check passed: 12 props, every rule")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else
                  ([] if in_blender() else sys.argv[1:])))
