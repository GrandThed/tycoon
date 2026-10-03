"""Fabric towers for the Metropolis growing city (M12 wave 3.1), generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/tower_kit.py [-- --out <dir>] [--write-blueprints]

Writes one GLB per piece into assets/kenney3d/tower-kit/Models/GLB format/, the folder convention
every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py discover the
kit with no registration step. assets/ is gitignored, so this script is the committed artifact and
the GLBs regenerate from it. `--write-blueprints` also (re)writes the 17 fabric blueprints under
tools/testfit/blueprints/_props/Metropolis/ from PROPS, so the pieces and the stages that use them
cannot drift apart; leave it off to keep a hand-edited blueprint.

Why a custom kit (docs/CITY_GROWTH.md sections 3 and 4): every city-kit-commercial `building-*`
is a finished block, already a landmark or reserved for one, and none of them can grow a floor
(their roofs and parapets sit proud of the walls). A Metropolis fabric tower has to **grow floor
by floor**, so its pieces are generated: a street-level base (lobby, shopfront or front door), a
run of floors per growth stage, and a crown. Filler never copies a landmark's silhouette or its
signature pieces: no rounded glass corners, no vertical blue window strips, no green pyramid roof,
no highway-sign gantries on roofs. Offices here read through horizontal ribbon windows, louvred
plant screens and setback crowns; homes through warm walls, punched windows and balconies; shops
through colourful awnings and signs at street level with flats above.

**Units.** 1 glTF unit = 1 stud, like garage-kit and metro-kit; blueprints use `"scale": 1.0`, so
every literal below is directly checkable in studs. A storey is S = 1.6 studs, the commercial
kit's storey at scale 4, so filler floors line up with the landmarks' floors.

**Frames.** Every stage piece is authored in the lot frame: origin at the lot's bottom-centre,
front -Z (the street), so a blueprint places all of a prop's pieces at [0, 0, 0] and its stages
register exactly (the boomtown-extras-kit shop pattern). Small furniture is built into the stage
pieces too, so a prop is one forecourt piece plus one piece per stage.

**Stages are additive** (blueprint.py: a stage shows every piece with stage <= it; nothing is ever
removed). So every stage below the last is designed to be swallowed by the next one: its parapet is
set PARAPET_IN back from the wall line and everything on its roof stays inside the body and below
the next stage's roof (`check` asserts both, per prop, at generation time). The floors of a new
stage continue the walls below in the same plane (adjacent, never overlapping), its first floor band
is laid across the old roof line so the joint reads like every other floor line, and a body's
bottom face is dropped wherever it would lie on the roof below.

**Two rendering rules** (lead, 2026-10-02): parallel faces that overlap stand at least GAP (0.05)
apart, or they flicker at distance in Roblox, and no member the camera sees is thinner than
MIN_MEMBER (0.1). Window panels, piers, bands, storey lines and signs are therefore stacked GAP
apart, and `check` enforces both on every stage: `face_fights` finds same-facing parallel faces
that overlap closer than GAP (opposite-facing pairs never render together, since a MeshPart culls
back faces), and `cube` flags any box thinner than MIN_MEMBER in two dimensions. A run with a
problem exits 1.

Colours are texels of the City Kits' shared colormap.png (sampled 2026-10-02), plus the street
pavement's own (176, 180, 196) for the forecourts, which the contract asks to match. Materials are
plain colour factors written linear, routed by merge_stages.py through palette.py (not an
sRGB-factor kit). Flat shading, axis-aligned boxes, a few sloped faces and faceted solids of
revolution: chunky toy proportions, like the kits.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from garden_kit import REPO_ROOT, Part, build_object, export  # noqa: E402
from village_extras_kit import beam, lathe, place  # noqa: E402

import bpy  # noqa: E402

KIT = "tower-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")
BLUEPRINT_DIR = os.path.join(REPO_ROOT, "tools", "testfit", "blueprints", "_props", "Metropolis")

Rgb = tuple[int, int, int]

# --- palette: texels of the City Kits' colormap.png --------------------------------------------
WHITE = (255, 255, 255)
WALL_SHADE = (220, 220, 233)  # industrial: the white ramp, halfway down
TIN = (205, 205, 224)  # and lower still
LAVENDER = (160, 168, 201)
STONE = (142, 149, 179)
SLATE_BLUE = (115, 126, 155)  # industrial
SLATE_LIGHT = (102, 107, 128)
SLATE = (81, 85, 102)
SOIL = (79, 82, 96)
CHARCOAL = (56, 56, 61)
GLASS = (208, 232, 255)
BLUE_PALE = (181, 204, 236)  # industrial
BLUE = (103, 148, 217)
NAVY = (71, 74, 172)  # industrial
GREEN = (97, 203, 139)
GREEN_DARK = (61, 167, 122)
YELLOW = (255, 192, 68)
ORANGE = (255, 126, 68)
RED = (207, 83, 79)
PINK = (243, 120, 240)
PINK_PALE = (245, 200, 240)  # industrial
PURPLE = (168, 120, 232)
CREAM = (253, 228, 199)
SAND = (242, 191, 153)
PEACH = (250, 174, 138)
WOOD = (241, 151, 108)
TERRACOTTA = (207, 115, 91)
ROSE = (202, 112, 123)  # roads
# Not a colormap texel: the Metropolis street pavement's own colour (CityDressing.json
# eras.Metropolis.road.tiles.pavement), so a forecourt reads as the pavement carried up to the door.
PAVE = (176, 180, 196)

# --- dimensions (studs) -------------------------------------------------------------------------
S = 1.6  # a storey: the commercial kit's 0.4 units at scale 4
FC_TOP = 0.10  # forecourt top (contract: <= 0.12)
# Two rules hold for every piece (lead, from the old-town builder's findings): any two parallel faces
# that overlap in plan or in elevation stand at least GAP apart, or they flicker at distance in
# Roblox; and no member the tycoon camera sees is thinner than MIN_MEMBER (thin rails shimmer). The
# depths below are therefore GAP apart wherever two of them cross.
GAP = 0.05
MIN_MEMBER = 0.1
GLASS_D = 0.05  # window panels, proud of the wall
PIER_D = 0.06  # corner piers and fins (they never overlap the glass, only the bands)
BAND_D = 0.11  # floor bands: GAP in front of the piers and more in front of the glass
LINE_D = 0.16  # storey lines, GAP in front of the bands
LINE_H = 0.1
SIGN_D = 0.22  # fascia signs, GAP in front of the storey line they cross
SIGN_TOP = 1.6 + LINE_H / 2 + GAP + 0.02  # a fascia sign rises past the first storey line, not into it
PARAPET_H = 0.18  # stage-0 total = 2 storeys + 0.18 = 3.38 <= heightFloor 3.4
PARAPET_IN = 0.06  # an interim parapet stands this far inside the wall line, so the next stage's
# walls bury it with a clear gap instead of sharing its plane
PARAPET_T = 0.16
BURY_MARGIN = GAP  # what check demands between a buried piece and the walls around it
HEIGHT_FLOOR = 3.4  # CityDressing.json eras.Metropolis.fabric.heightFloor
TRI_BUDGET = 2000  # per stage, per prop (contract)
LOW_PLANT = 0.36  # the tallest roof plant a three-storey stage 1 carries (an a/c unit is 0.28)

LOTS = {"narrow": (4.0, 8.0), "small": (6.0, 6.0), "medium": (8.0, 8.0)}
# The tower body (x0, x1, z0, z1) on each lot: storey lines (LINE_D proud) stay 0.01 inside the lot
# line, so narrow lots stand shoulder to shoulder as a terrace, and the front leaves a forecourt.
BODIES = {
    "narrow": (-1.83, 1.83, -2.90, 3.75),
    "small": (-2.60, 2.60, -1.90, 2.80),
    "medium": (-3.50, 3.50, -2.90, 3.75),
}
# Floors at each stage. Stage 0 is two storeys (3.2 + parapet <= 3.4); the tops are measured
# against the landmarks: narrow <= 14, small <= 17.5, medium <= 21, shops <= 11. Stage 1 is where a
# level-2 parcel starts (levelStages [1, 3, 4]), so wherever it is three storeys (narrow, small,
# shops) it carries only low roof plant (<= LOW_PLANT): three storeys stay at 5.16, under the early
# landmarks' 5.17, and a parcel by one of them shows its stage 1 instead of being capped back to
# stage 0.
FLOORS = {
    "narrow": (2, 3, 4, 6, 8),
    "small": (2, 3, 5, 7, 10),
    "medium": (2, 4, 6, 9, 12),
    "shop": (2, 3, 4, 5, 6),
}


def log(msg: str) -> None:
    print(f"[{KIT}] {msg}", flush=True)


# --- primitives (glTF space: Y up, front -Z) ----------------------------------------------------


RODS: list[tuple[float, float, float]] = []  # boxes thin in two dimensions; check() reads it per prop


def cube(p: Part, x0, x1, y0, y1, z0, z1, c: Rgb, skip=(), **sides) -> None:
    """Axis-aligned box with per-face colours (top, bottom, front = -Z, back, left = -X, right)
    and faces to leave out: a face that lies against a wall or on a roof below is never drawn,
    which keeps both the triangle count and the coplanar pairs down. Winding as garage_kit's box."""
    col = {k: sides.get(k, c) for k in ("top", "bottom", "front", "back", "left", "right")}
    dims = sorted((x1 - x0, y1 - y0, z1 - z0))
    if dims[1] < MIN_MEMBER - 1e-6:  # a rod or a wire, which would shimmer at the tycoon camera
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


def panel(p: Part, b, face: str, u0, u1, y0, y1, d, c: Rgb, **sides) -> None:
    """A slab d proud of one wall of body b, spanning u0..u1 along that wall (x on front and back,
    z on the sides). Its back face lies on the wall and is left out."""
    x0, x1, z0, z1 = b
    under = ("bottom",) if y0 <= 0.0 else ()  # a panel standing on the ground hides its underside
    if face == "front":
        cube(p, u0, u1, y0, y1, z0 - d, z0, c, skip=("back",) + under, **sides)
    elif face == "back":
        cube(p, u0, u1, y0, y1, z1, z1 + d, c, skip=("front",) + under, **sides)
    elif face == "left":
        cube(p, x0 - d, x0, y0, y1, u0, u1, c, skip=("right",) + under, **sides)
    else:
        cube(p, x1, x1 + d, y0, y1, u0, u1, c, skip=("left",) + under, **sides)


def ring(p: Part, b, y0, y1, d, c: Rgb, **sides) -> None:
    """A band d proud all round body b: one box, its top and bottom inside the body but the rim."""
    x0, x1, z0, z1 = b
    cube(p, x0 - d, x1 + d, y0, y1, z0 - d, z1 + d, c, **sides)


def hollow(p: Part, b, y0, y1, out, t, c: Rgb, top: Rgb, inner: Rgb | None = None, under: bool = False) -> None:
    """Four walls round body b with no lid: a parapet. `out` is how far the outer face stands
    beyond the wall line (negative = set back), `t` the wall thickness. `under` draws the
    underside, for a cornice that overhangs the wall and is seen from the street."""
    x0, x1, z0, z1 = b
    X0, X1, Z0, Z1 = x0 - out, x1 + out, z0 - out, z1 + out
    inner = inner or c
    sk = () if under else ("bottom",)
    cube(p, X0, X1, y0, y1, Z0, Z0 + t, c, skip=sk, top=top, back=inner)
    cube(p, X0, X1, y0, y1, Z1 - t, Z1, c, skip=sk, top=top, front=inner)
    cube(p, X0, X0 + t, y0, y1, Z0 + t, Z1 - t, c, skip=sk + ("front", "back"), top=top, right=inner)
    cube(p, X1 - t, X1, y0, y1, Z0 + t, Z1 - t, c, skip=sk + ("front", "back"), top=top, left=inner)


def corner_piers(p: Part, b, y0, y1, w, c: Rgb, under: bool = False) -> None:
    """An L-shaped pier PIER_D proud at each corner, `w` along each face. Two slabs per corner
    rather than one box, so no pier top ever lies in the plane of the roof. `under` draws the
    undersides, for piers that start above a recessed lobby."""
    x0, x1, z0, z1 = b
    d = PIER_D
    sk = () if under else ("bottom",)
    cube(p, x0 - d, x0 + w, y0, y1, z0 - d, z0, c, skip=sk + ("back",))
    cube(p, x1 - w, x1 + d, y0, y1, z0 - d, z0, c, skip=sk + ("back",))
    cube(p, x0 - d, x0 + w, y0, y1, z1, z1 + d, c, skip=sk + ("front",))
    cube(p, x1 - w, x1 + d, y0, y1, z1, z1 + d, c, skip=sk + ("front",))
    cube(p, x0 - d, x0, y0, y1, z0, z0 + w, c, skip=sk + ("right", "front"))
    cube(p, x0 - d, x0, y0, y1, z1 - w, z1, c, skip=sk + ("right", "back"))
    cube(p, x1, x1 + d, y0, y1, z0, z0 + w, c, skip=sk + ("left", "front"))
    cube(p, x1, x1 + d, y0, y1, z1 - w, z1, c, skip=sk + ("left", "back"))


def blob(p: Part, centre, radii, c: Rgb, seg: int = 6, rings: int = 2, seed: int = 0) -> None:
    p.blob(centre, radii, c, seg=seg, rings=rings, cut=-0.35, jitter=0.08, seed=seed)


# --- a tower's floors ---------------------------------------------------------------------------


class Style(dict):
    """A facade: colours (wall, band, line, glass, roof, cap, cap_top, inner, soffit, pier), window
    heights in a storey (sill, head), window columns per face as (u centre, width, first floor[,
    last floor, exclusive]), and options (corner = pier width)."""

    def __getattr__(self, key):
        return self[key]


def floors(p: Part, b, st: Style, f0: int, f1: int, body_from: float | None = None) -> None:
    """Floors f0 .. f1-1 of body b: the wall, the window panels and a band at every floor line
    from f0 up (at f0 > 0 that band is laid across the roof line of the stage below, so the joint
    reads as an ordinary floor line). `body_from` starts the wall higher, over a lobby."""
    x0, x1, z0, z1 = b
    y0, y1 = f0 * S, f1 * S
    ya = y0 if body_from is None else body_from
    skip = ("bottom",) if (ya == 0.0 or f0 > 0) else ()
    cube(p, x0, x1, ya, y1, z0, z1, st.wall, skip=skip, top=st.roof, bottom=st.get("soffit", st.wall))
    for face, cols in st.cols.items():
        for col in cols:
            u, w, first = col[:3]
            lo, hi = max(f0, first), min(f1, col[3] if len(col) > 3 else f1)
            if lo >= hi:
                continue
            panel(p, b, face, u - w / 2, u + w / 2, lo * S + st.sill - GAP, (hi - 1) * S + st.head + GAP,
                  GLASS_D, st.glass)
    for n in range(max(f0, 1), f1):
        ring(p, b, (n - 1) * S + st.head, n * S + st.sill, BAND_D, st.band)
        if st.get("line"):  # a thin storey line in the trim colour, in front of the band
            ring(p, b, n * S - LINE_H / 2, n * S + LINE_H / 2, LINE_D, st.line)
    if st.get("corner"):
        corner_piers(p, b, ya if f0 == 0 else y0, y1, st.corner, st.pier, under=f0 == 0 and ya > 0)


def interim_top(p: Part, b, y: float, st: Style) -> None:
    """The parapet of a stage that a later stage will build over: set back, buried next stage."""
    hollow(p, b, y, y + PARAPET_H, -PARAPET_IN, PARAPET_T, st.wall, st.cap, inner=st.get("inner", st.wall))


def final_top(p: Part, b, y: float, st: Style, h: float = 0.3) -> float:
    """The last stage's parapet: a cornice standing proud of everything below. Returns its top."""
    hollow(p, b, y, y + h, BAND_D, BAND_D, st.cap, st.cap_top, inner=st.get("inner", st.wall), under=True)
    return y + h


# --- small furniture ----------------------------------------------------------------------------


def stair_hut(p: Part, x, z, y, w=1.1, d=0.9, h=0.95, wall=WHITE, door=SLATE, cap=SLATE_LIGHT) -> None:
    cube(p, x - w / 2, x + w / 2, y, y + h, z - d / 2, z + d / 2, wall, skip=("bottom",), top=cap)
    panel(p, (x - w / 2, x + w / 2, z - d / 2, z + d / 2), "front", x - 0.22, x + 0.22, y, y + 0.7, GAP, door)


def water_tank(p: Part, x, z, y, r=0.42, h=0.9, legs=0.28) -> None:
    """A timber water tank on four legs under a slate cone, (2r) wide, legs + h tall."""
    for sx in (-1, 1):
        for sz in (-1, 1):
            cx, cz = x + sx * r * 0.62, z + sz * r * 0.62
            cube(p, cx - 0.05, cx + 0.05, y, y + legs + 0.02, cz - 0.05, cz + 0.05, SLATE, skip=("bottom", "top"))
    body = h * 0.72
    lathe(p, [(r, legs), (r * 1.04, legs + 0.06), (r * 1.04, legs + body), (0.0, legs + h)],
          [WOOD, WOOD, SLATE_LIGHT], seg=8, at=(x, y, z), phase=math.pi / 8)


def plant_box(p: Part, x0, x1, z0, z1, y, h, c=SLATE_LIGHT, slat=SLATE) -> None:
    """A louvred rooftop plant enclosure: a box with two darker slat lines."""
    cube(p, x0, x1, y, y + h, z0, z1, c, skip=("bottom",), top=SLATE)
    for k in (0.5, 0.8):  # high up, so a slat never lies near the band the next stage lays here
        yy = y + h * k
        cube(p, x0 - GAP, x1 + GAP, yy - 0.05, yy + 0.05, z0 - GAP, z1 + GAP, slat)


def hatch(p: Part, x, z, y) -> None:
    """A roof hatch with a skylight, 0.2 tall: low roof plant for a stage that must stay short."""
    cube(p, x - 0.32, x + 0.32, y, y + 0.16, z - 0.32, z + 0.32, TIN, skip=("bottom",), top=STONE)
    cube(p, x - 0.22, x + 0.22, y + 0.16, y + 0.16 + 0.06, z - 0.22, z + 0.22, GLASS, skip=("bottom",))


def ac_unit(p: Part, x, z, y) -> None:
    """A rooftop a/c unit, 0.28 tall: low enough to stay GAP under the floor band that the next
    stage lays across this roof."""
    cube(p, x - 0.3, x + 0.3, y, y + 0.22, z - 0.25, z + 0.25, TIN, skip=("bottom",), top=STONE)
    cube(p, x - 0.16, x + 0.16, y + 0.22, y + 0.22 + 0.06, z - 0.16, z + 0.16, SLATE, skip=("bottom",))


def mast(p: Part, x, z, y, h, tip=RED) -> None:
    """A slim mast with cross-arms (one on a short mast) and a red tip. The arms stand GAP proud of
    the pole on both faces, so no arm face lies close in front of a pole face."""
    pole = MIN_MEMBER / 2
    cube(p, x - pole, x + pole, y, y + h, z - pole, z + pole, SLATE_LIGHT, skip=("bottom",))
    for k in ((0.4, 0.78) if h >= 0.6 else (0.5,)):
        yy = y + h * k - MIN_MEMBER / 2
        arm = 0.32 * (1.2 - k)
        cube(p, x - arm, x + arm, yy, yy + MIN_MEMBER, z - pole - GAP, z + pole + GAP, SLATE)
    cube(p, x - 0.08, x + 0.08, y + h, y + h + 0.12, z - 0.08, z + 0.08, tip, skip=("bottom",))


def tree(p: Part, x, z, y, h=2.0, r=0.62, seed=0, leaf=GREEN, trunk=SLATE) -> None:
    """A street tree: a slim trunk and a faceted crown, h tall from y."""
    cube(p, x - 0.07, x + 0.07, y, y + h * 0.42, z - 0.07, z + 0.07, trunk, skip=("bottom", "top"))
    blob(p, (x, y + h * 0.55, z), (r, h * 0.45, r), leaf, seed=seed)


def planter(p: Part, x0, x1, z0, z1, y, h=0.32, edge=STONE, soil=SOIL) -> None:
    cube(p, x0, x1, y, y + h, z0, z1, edge, skip=("bottom",), top=soil)


def shrub(p: Part, x, z, y, r=0.32, seed=0, leaf=GREEN_DARK) -> None:
    """A bush set into a planter or a slab. Its underside is never seen, so it has no bottom cap:
    neighbouring bushes' caps would otherwise lie in one plane inside the planter."""
    first = len(p.faces)
    blob(p, (x, y, z), (r, r * 0.8, r), leaf, seg=5, rings=2, seed=seed)
    del p.faces[first]  # Part.blob lays the bottom cap first


def bench(p: Part, x, z, y, length=1.1, rot=0) -> None:
    """A park bench: seat and back on two slate feet. rot 0 faces -Z, 90 faces -X... (back on +Z)."""
    hl = length / 2
    parts = [
        (-hl, hl, 0.22, 0.32, -0.18, 0.06, WOOD),  # seat
        (-hl, hl, 0.32, 0.62, 0.06, 0.16, WOOD),  # back
        (-hl + 0.06, -hl + 0.16, 0.0, 0.22, -0.13, 0.01, SLATE),  # feet end under the seat
        (hl - 0.16, hl - 0.06, 0.0, 0.22, -0.13, 0.01, SLATE),
    ]
    for ax0, ax1, ay0, ay1, az0, az1, c in parts:
        if rot == 0:
            cube(p, x + ax0, x + ax1, y + ay0, y + ay1, z + az0, z + az1, c, skip=("bottom",))
        elif rot == 180:
            cube(p, x - ax1, x - ax0, y + ay0, y + ay1, z - az1, z - az0, c, skip=("bottom",))
        elif rot == 90:  # back toward +X, faces -X
            cube(p, x + az0, x + az1, y + ay0, y + ay1, z - ax1, z - ax0, c, skip=("bottom",))
        else:  # 270: back toward -X, faces +X
            cube(p, x - az1, x - az0, y + ay0, y + ay1, z + ax0, z + ax1, c, skip=("bottom",))


def canopy(p: Part, b, u0, u1, head, depth, c=WHITE, edge=SLATE) -> None:
    """A flat entrance canopy over the front wall: a slab with a darker fascia. It hangs from inside
    the floor band whose underside is at `head`, GAP above that underside, so the two never share
    a plane."""
    x0, x1, z0, z1 = b
    y = head + GAP
    cube(p, u0, u1, y, y + 0.1, z0 - depth, z0, c, skip=("back",))
    cube(p, u0 - 0.02, u1 + 0.02, y - 0.06, y + 0.16, z0 - depth - 0.06, z0 - depth, edge, skip=("back",))


def door(p: Part, b, face: str, u, w, h=1.2, frame=SLATE, leaf=CHARCOAL, glass=GLASS) -> None:
    panel(p, b, face, u - w / 2, u + w / 2, 0.0, h, GAP, frame)
    panel(p, b, face, u - w / 2 + 0.1, u + w / 2 - 0.1, 0.0, h - 0.1, 2 * GAP, leaf)
    panel(p, b, face, u - w / 2 + 0.2, u + w / 2 - 0.2, 0.25, h - 0.2, 3 * GAP, glass)


def step(p: Part, b, u, w, depth=0.35) -> None:
    """A doorstep on the forecourt, 0.08 above it."""
    x0, x1, z0, z1 = b
    cube(p, u - w / 2, u + w / 2, 0.0, FC_TOP + 0.08, z0 - depth, z0, STONE, skip=("back", "bottom"), top=TIN)


def balcony(p: Part, b, face, u, w, y, depth=0.5, rail=WHITE, floor=TIN, h=0.42) -> None:
    """A balcony tub: a slab with a solid rail, depth out from the wall."""
    panel(p, b, face, u - w / 2, u + w / 2, y, y + h, depth, rail, top=floor, bottom=STONE)


def striped_awning(p: Part, u0, u1, y_wall, y_edge, depth, colours, stripes, rot=0.0, at=(0.0, 0.0, 0.0)) -> None:
    """A canvas awning sloping from y_wall at the wall to y_edge, `depth` out, with a valance and
    closed cheeks. Built against a wall at z = 0 facing -Z, spanning u0..u1 along x, then turned
    `rot` about Y and moved to `at` (rot -90 hangs it on a +X wall). Stripes share their ends, so
    only the two outer cheeks are drawn: no stripe end lies in the plane of its neighbour's."""
    a = Part("awning")
    t, drop = 0.05, 0.2
    zf = -depth
    w = (u1 - u0) / stripes
    for i in range(stripes):
        xa, xb = u0 + i * w, u0 + (i + 1) * w
        c = colours[i % 2]
        mid = ((xa + xb) / 2, (y_wall + y_edge) / 2 - t / 2, zf / 2)
        a.face([(xa, y_wall, 0.0), (xb, y_wall, 0.0), (xb, y_edge, zf), (xa, y_edge, zf)], c, mid)
        a.face([(xa, y_wall - t, 0.0), (xb, y_wall - t, 0.0), (xb, y_edge - t, zf), (xa, y_edge - t, zf)], c, mid)
        a.face([(xa, y_edge - t, zf), (xb, y_edge - t, zf), (xb, y_edge, zf), (xa, y_edge, zf)], c, mid)
        for x, outer in ((xa, i == 0), (xb, i == stripes - 1)):
            if outer:
                a.face([(x, y_wall - t, 0.0), (x, y_wall, 0.0), (x, y_edge, zf), (x, y_edge - t, zf)], c, mid)
        ends = (() if i == 0 else ("left",)) + (() if i == stripes - 1 else ("right",))
        cube(a, xa, xb, y_edge - drop, y_edge - t, zf, zf + MIN_MEMBER, c, skip=("top",) + ends)
    place(p, a, rot, at)


def sign_board(p: Part, b, u0, u1, y0, y1, board: Rgb, band: Rgb, d=SIGN_D) -> None:
    """A fascia sign with a lettering band (no letters: the band is the read)."""
    x0, x1, z0, z1 = b
    cube(p, u0, u1, y0, y1, z0 - d, z0, board, skip=("back",))
    m = (y1 - y0) * 0.28
    cube(p, u0 + 0.18, u1 - 0.18, y0 + m, y1 - m, z0 - d - GAP, z0 - d, band, skip=("back",))


def shopfront(p: Part, b, u0, u1, frame: Rgb, door_u: float, door_w=0.7) -> None:
    """A ground-floor shop window across the front: a dark frame, glass, mullions and a door."""
    panel(p, b, "front", u0, u1, 0.0, 1.18, GAP, frame)
    segs = [(u0 + 0.1, door_u - door_w / 2 - 0.06), (door_u + door_w / 2 + 0.06, u1 - 0.1)]
    for a0, a1 in segs:
        if a1 - a0 < 0.3:
            continue
        panel(p, b, "front", a0, a1, 0.0, 0.16, 2 * GAP, frame)  # the stall riser
        panel(p, b, "front", a0, a1, 0.2, 1.08, 2 * GAP, GLASS)
        n = max(0, int((a1 - a0) / 1.0))
        for k in range(1, n + 1):
            u = a0 + (a1 - a0) * k / (n + 1)
            panel(p, b, "front", u - MIN_MEMBER / 2, u + MIN_MEMBER / 2, 0.2 - GAP, 1.08 + GAP, 3 * GAP, frame)
    panel(p, b, "front", door_u - door_w / 2, door_u + door_w / 2, 0.0, 1.08, 2 * GAP, CHARCOAL)
    panel(p, b, "front", door_u - door_w / 2 + 0.1, door_u + door_w / 2 - 0.1, 0.28, 0.98, 3 * GAP, GLASS)


def parasol(p: Part, x, z, y, c: Rgb, r=0.6, h=1.45) -> None:
    """A café table under a parasol: a pole, a shallow faceted cone, a round table."""
    cube(p, x - 0.05, x + 0.05, y, y + h - 0.12, z - 0.05, z + 0.05, WHITE, skip=("bottom",))
    lathe(p, [(r, h - 0.22), (0.0, h)], [c], seg=8, at=(x, y, z), phase=math.pi / 8)
    lathe(p, [(0.26, 0.4), (0.26, 0.5)], [WHITE], seg=6, at=(x, y, z))


def stepped_front(p: Part, steps, y: float, zf: float, depth: float, c: Rgb, top: Rgb) -> None:
    """A stepped false front on the cornice: `steps` lists (half width, height) from the widest,
    lowest step to the narrowest, tallest. Built as a centre block plus a pair of side blocks per
    step, each meeting the next only at a shared side (left out), so no two faces overlap."""
    inner = 0.0
    for i, (hw, h) in enumerate(reversed(steps)):
        if i == 0:
            cube(p, -hw, hw, y, y + h, zf, zf + depth, c, skip=("bottom",), top=top)
        else:
            cube(p, -hw, -inner, y, y + h, zf, zf + depth, c, skip=("bottom", "right"), top=top)
            cube(p, inner, hw, y, y + h, zf, zf + depth, c, skip=("bottom", "left"), top=top)
        inner = hw


def forecourt(name: str, lot: str) -> Part:
    """The paved forecourt that covers a whole lot from stage 0: paving now arrives lot by lot."""
    w, d = LOTS[lot]
    p = Part(name)
    cube(p, -w / 2, w / 2, 0.0, FC_TOP, -d / 2, d / 2, PAVE, skip=("bottom",))
    return p


# --- homes --------------------------------------------------------------------------------------


def tower(slug: str, lot: str, st: Style, floors_at, base, facade, crowns, final_h: float = 0.3,
          body=None) -> list[Part]:
    """Five stage pieces of one tower. `base(p)` draws the street level (stage 0), `facade(p, f0, f1)`
    whatever rises with each run of floors (balconies, bays, signs), `crowns[k](p, y)` the roof of
    stage k at roof height y (every crown but the last is buried by the next stage)."""
    b = body or BODIES[lot]
    parts = []
    f_prev = 0
    for k, f in enumerate(floors_at):
        p = Part(f"{slug}-{k}")
        if k == 0:
            base(p)
        else:
            floors(p, b, st, f_prev, f)
        if facade:
            facade(p, f_prev, f)
        y = f * S
        if k < len(floors_at) - 1:
            interim_top(p, b, y, st)
        else:
            final_top(p, b, y, st, final_h)
        crowns[k](p, y)
        parts.append(p)
        f_prev = f
    return parts


def res_cols(lot: str):
    """Punched windows for a home: (u, width, first floor) per face."""
    if lot == "narrow":
        return {
            "front": [(-0.85, 0.9, 0), (0.85, 0.9, 0)],
            "back": [(-0.85, 0.85, 0), (0.85, 0.85, 0)],
            "left": [(-1.3, 0.95, 0), (1.9, 0.95, 0)],
            "right": [(-1.3, 0.95, 0), (1.9, 0.95, 0)],
        }
    if lot == "small":
        return {
            "front": [(-1.55, 1.15, 0), (0.0, 0.8, 1), (1.55, 1.15, 0)],
            "back": [(-1.3, 1.0, 0), (1.3, 1.0, 0)],
            "left": [(-0.75, 1.0, 0), (1.55, 1.0, 0)],
            "right": [(-0.75, 1.0, 0), (1.55, 1.0, 0)],
        }
    return {
        "front": [(-2.35, 1.3, 0), (0.0, 1.3, 1), (2.35, 1.3, 0)],
        "back": [(-2.2, 1.2, 0), (0.0, 1.2, 0), (2.2, 1.2, 0)],
        "left": [(-1.55, 1.1, 0), (1.95, 1.1, 0)],
        "right": [(-1.55, 1.1, 0), (1.95, 1.1, 0)],
    }


def res_narrow_a() -> list[Part]:
    """Peach-walled terrace house with white storey lines, a stack of white balconies down the left
    window column and a timber water tank and stair hut on the roof."""
    lot = "narrow"
    b = BODIES[lot]
    cols = res_cols(lot)
    cols["front"] = [(-0.85, 0.9, 0), (0.85, 0.8, 1)]  # the door takes the right bay at ground level
    st = Style(wall=PEACH, band=PEACH, line=WHITE, glass=BLUE, roof=SLATE_LIGHT, cap=WHITE, cap_top=WHITE,
               sill=0.36, head=1.26, cols=cols, inner=PEACH)

    def base(p):
        floors(p, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.85, 0.8, leaf=SLATE)
        canopy(p, b, 0.45, 1.35, st.head, 0.5)
        step(p, b, 0.85, 1.0)
        planter(p, -1.75, -0.2, -3.85, -3.35, FC_TOP)
        for i, x in enumerate((-1.4, -0.95, -0.5)):
            shrub(p, x, -3.6, FC_TOP + 0.3, 0.26, seed=11 + i)

    def facade(p, f0, f1):
        for n in range(max(f0, 1), f1):
            balcony(p, b, "front", -0.85, 1.2, n * S, 0.5)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return  # stage 0 is 3.38 tall: nothing may rise above the parapet
            if k == 1:
                hatch(p, 1.0, 2.4, y)
                ac_unit(p, -0.95, -1.6, y)
                return
            stair_hut(p, 1.0, 2.4, y, h=0.95 if k == 4 else 0.9, wall=PEACH, cap=WHITE)
            if k >= 2:
                water_tank(p, -0.95, 1.6, y, r=0.42 if k == 4 else 0.36, h=0.85 if k == 4 else 0.7,
                           legs=0.32 if k == 4 else 0.16)
            ac_unit(p, -0.95, -1.6, y)
        return draw

    return tower("res-narrow-a", lot, st, FLOORS[lot], base, facade, [crown(k) for k in range(5)])


def res_narrow_b() -> list[Part]:
    """Terracotta terrace house with cream storey lines and a cream bay window rising up the middle
    of the front; the last stage puts a slate mansard roof with two dormers on it."""
    lot = "narrow"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cols = res_cols(lot)
    cols["front"] = [(-1.33, 0.56, 0), (1.33, 0.56, 0)]
    st = Style(wall=TERRACOTTA, band=TERRACOTTA, line=CREAM, glass=BLUE, roof=SLATE, cap=CREAM, cap_top=CREAM,
               sill=0.36, head=1.26, cols=cols, inner=TERRACOTTA)
    bay = (-0.68, 0.68)
    bay_d = 0.42

    def bay_run(p, f0, f1):
        lo = max(f0, 1)
        if lo >= f1:
            return
        y0, y1 = lo * S, f1 * S
        bb = (bay[0], bay[1], z0 - bay_d, z0)
        cube(p, bay[0], bay[1], y0, y1, z0 - bay_d, z0, CREAM, skip=("back",) + (("bottom",) if lo > 1 else ()),
             top=CREAM, bottom=STONE)
        for n in range(lo, f1):
            panel(p, bb, "front", bay[0] + 0.14, bay[1] - 0.14, n * S + 0.38, n * S + 1.26, GLASS_D, BLUE)
            panel(p, bb, "left", z0 - bay_d + 0.1, z0 - 0.06, n * S + 0.38, n * S + 1.26, GLASS_D, BLUE)
            panel(p, bb, "right", z0 - bay_d + 0.1, z0 - 0.06, n * S + 0.38, n * S + 1.26, GLASS_D, BLUE)

    def base(p):
        floors(p, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.0, 0.8, leaf=CREAM, frame=CREAM)
        canopy(p, b, bay[0], bay[1], st.head, bay_d + 0.08, c=CREAM, edge=TERRACOTTA)
        step(p, b, 0.0, 1.1)
        for sx in (-1, 1):
            planter(p, sx * 1.35 - 0.4, sx * 1.35 + 0.4, -3.85, -3.4, FC_TOP, edge=TERRACOTTA)
            shrub(p, sx * 1.35, -3.62, FC_TOP + 0.3, 0.28, seed=21 + sx)
        bay_run(p, 0, FLOORS[lot][0])

    def facade(p, f0, f1):
        if f0 > 0:
            bay_run(p, f0, f1)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                if k == 1:
                    hatch(p, -1.0, 2.5, y)
                else:
                    stair_hut(p, -1.0, 2.5, y, h=0.85, wall=TERRACOTTA, cap=CREAM)
                ac_unit(p, 1.1, 1.0, y)
                return
            # the mansard: a slate hip roof rising from inside the cornice (its base sunk GAP into
            # the roof, so no face of it lies on the roof or the cornice top), two dormers facing
            # the street and a chimney
            yb = y + 0.22
            m = 0.12
            p.frustum(x0 + m, x1 - m, z0 + m, z1 - m, y - GAP, x0 + 0.95, x1 - 0.95, z0 + 1.15, z1 - 1.15,
                      yb + 0.85, SLATE, top=SLATE_LIGHT, bottom=SLATE)
            for u in (-0.62, 0.62):
                zf = z0 + 0.45
                cube(p, u - 0.3, u + 0.3, yb + 0.05, yb + 0.72, zf, zf + 0.7, CREAM, skip=("bottom", "back"),
                     top=SLATE_LIGHT)
                cube(p, u - 0.18, u + 0.18, yb + 0.16, yb + 0.6, zf - GAP, zf, BLUE, skip=("back",))
            cube(p, 0.75, 1.1, yb + 0.5, yb + 1.05, 2.0, 2.35, TERRACOTTA, skip=("bottom",), top=SLATE)
        return draw

    return tower("res-narrow-b", lot, st, FLOORS[lot], base, facade, [crown(k) for k in range(5)], final_h=0.22)


def res_small_a() -> list[Part]:
    """Cream block with terracotta storey lines and wrap-round corner balconies at the front right;
    its last stage plants a roof garden with two trees under a white pergola."""
    lot = "small"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cols = res_cols(lot)
    st = Style(wall=CREAM, band=CREAM, line=TERRACOTTA, glass=BLUE, roof=SLATE_LIGHT, cap=TERRACOTTA, cap_top=CREAM,
               sill=0.36, head=1.26, cols=cols, inner=CREAM)

    def base(p):
        floors(p, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.0, 0.85)
        canopy(p, b, -0.6, 0.6, st.head, 0.6, c=TERRACOTTA, edge=CREAM)
        step(p, b, 0.0, 1.0)
        planter(p, 0.9, 2.75, -2.85, -2.4, FC_TOP, edge=TERRACOTTA)
        for i, x in enumerate((1.3, 1.85, 2.4)):
            shrub(p, x, -2.62, FC_TOP + 0.3, 0.27, seed=31 + i)
        tree(p, -2.3, -2.45, FC_TOP, h=1.9, r=0.5, seed=3)

    def facade(p, f0, f1):
        for n in range(max(f0, 1), f1):
            y = n * S
            # front-right corner: one slab wrapping the corner, rail on both open sides
            cube(p, 0.88, x1 + 0.35, y, y + 0.1, z0 - 0.55, z0 + 1.6, TIN, bottom=STONE)
            cube(p, 0.88, x1 + 0.35, y + 0.1, y + 0.44, z0 - 0.55, z0 - 0.45, WHITE, skip=("bottom",))
            cube(p, x1 + 0.25, x1 + 0.35, y + 0.1, y + 0.44, z0 - 0.45, z0 + 1.6, WHITE, skip=("bottom",))
            if n % 2 == 1:
                shrub(p, x1 + 0.1, z0 - 0.2, y + 0.12, 0.22, seed=40 + n)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                if k == 1:
                    hatch(p, -1.4, 1.9, y)
                else:
                    stair_hut(p, -1.4, 1.9, y, h=0.9, wall=CREAM, cap=TERRACOTTA)
                ac_unit(p, 1.3, 1.8, y)
                return
            yb = y + 0.3
            planter(p, -2.3, 2.3, 1.4, 2.6, y, h=0.4, edge=TERRACOTTA)
            tree(p, -1.4, 2.0, y + 0.4, h=1.05, r=0.45, seed=5)
            tree(p, 1.2, 2.0, y + 0.4, h=0.95, r=0.42, seed=6)
            for x in (-2.0, 0.0, 2.0):
                cube(p, x - 0.06, x + 0.06, y, yb + 0.85, -1.2 - 0.06, -1.2 + 0.06, WHITE, skip=("bottom",))
                cube(p, x - 0.06, x + 0.06, y, yb + 0.85, 0.6 - 0.06, 0.6 + 0.06, WHITE, skip=("bottom",))
            for z in (-1.2, 0.6):
                cube(p, -2.15, 2.15, yb + 0.85, yb + 0.97, z - 0.07, z + 0.07, WHITE)
            for x in (-1.6, -0.8, 0.0, 0.8, 1.6):
                cube(p, x - 0.06, x + 0.06, yb + 0.97, yb + 1.07, -1.4, 0.8, WHITE, skip=("bottom",))
            bench(p, -1.0, -0.6, y, 1.0)
        return draw

    return tower("res-small-a", lot, st, FLOORS[lot], base, facade, [crown(k) for k in range(5)])


def res_small_b() -> list[Part]:
    """Dusty-rose block with white storey lines, paired windows and two balconies per floor on the
    front; its last stage adds a glazed penthouse set back on the roof with a slim mast."""
    lot = "small"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cols = {
        "front": [(-1.45, 1.5, 0), (1.45, 1.5, 0)],
        "back": [(-1.3, 1.1, 0), (1.3, 1.1, 0)],
        "left": [(0.45, 2.2, 0)],
        "right": [(0.45, 2.2, 0)],
    }
    st = Style(wall=ROSE, band=ROSE, line=WHITE, glass=BLUE, roof=STONE, cap=WHITE, cap_top=WHITE,
               sill=0.36, head=1.26, cols=cols, inner=ROSE)

    def base(p):
        floors(p, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.0, 0.7, leaf=SLATE)
        canopy(p, b, -0.55, 0.55, st.head, 0.5)
        step(p, b, 0.0, 0.8)
        for sx in (-1, 1):
            tree(p, sx * 2.45, -2.45, FC_TOP, h=1.4, r=0.42, seed=50 + sx)

    def facade(p, f0, f1):
        for n in range(max(f0, 1), f1):
            for u in (-1.45, 1.45):
                balcony(p, b, "front", u, 1.6, n * S, 0.45, rail=WHITE)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                if k == 1:
                    hatch(p, 1.4, 1.9, y)
                else:
                    stair_hut(p, 1.4, 1.9, y, h=0.9, wall=ROSE, cap=WHITE)
                if k >= 2:
                    water_tank(p, -1.3, 1.6, y, r=0.34, h=0.6, legs=0.12)
                else:
                    ac_unit(p, -1.2, 1.6, y)
                return
            # a glazed penthouse set back from the cornice on every side, under a white roof
            px0, px1, pz0, pz1 = x0 + 0.75, x1 - 0.75, z0 + 0.75, z1 - 0.55
            cube(p, px0, px1, y, y + 1.0 + GAP, pz0, pz1, BLUE_PALE, skip=("bottom",), top=WHITE)
            for u in (px0 + 0.9, 0.0, px1 - 0.9):
                panel(p, (px0, px1, pz0, pz1), "front", u - 0.05, u + 0.05, y, y + 1.0, GAP, WHITE)
            cube(p, px0 - 0.25, px1 + 0.25, y + 1.0, y + 1.1, pz0 - 0.35, pz1 + 0.15, WHITE)
            mast(p, px1 - 0.4, pz1 - 0.4, y + 1.1, 0.28)
        return draw

    return tower("res-small-b", lot, st, FLOORS[lot], base, facade, [crown(k) for k in range(5)])


def res_medium_a() -> list[Part]:
    """A medium apartment tower in sand with white storey lines, terracotta corner piers, two stacks of
    balconies at the front corners, a canopied lobby door; the last stage crowns it with a roof
    terrace (parasols), a lift overrun and a water tank."""
    lot = "medium"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cols = res_cols(lot)
    cols["back"] = [(-1.6, 1.4, 0), (1.6, 1.4, 0)]
    st = Style(wall=SAND, band=SAND, line=WHITE, glass=BLUE, roof=SLATE_LIGHT, cap=TERRACOTTA, cap_top=WHITE,
               sill=0.36, head=1.26, cols=cols, inner=SAND, corner=0.42, pier=TERRACOTTA)

    def base(p):
        floors(p, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.0, 1.0, leaf=SLATE)
        canopy(p, b, -0.9, 0.9, st.head, 0.75, c=WHITE, edge=TERRACOTTA)
        step(p, b, 0.0, 1.3, depth=0.4)
        for sx in (-1, 1):
            planter(p, sx * 2.6 - 0.8, sx * 2.6 + 0.8, -3.75, -3.25, FC_TOP)
            tree(p, sx * 2.6, -3.5, FC_TOP + 0.32, h=1.8, r=0.44, seed=60 + sx)

    def facade(p, f0, f1):
        for n in range(max(f0, 1), f1):
            for u in (-2.35, 2.35):
                balcony(p, b, "front", u, 1.5, n * S, 0.5)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            stair_hut(p, -2.2, 2.6, y, w=1.4, d=1.2, h=1.2 if k < 4 else 1.3, wall=SAND, cap=TERRACOTTA)
            if k < 4:
                return
            water_tank(p, 2.3, 2.4, y, r=0.45, h=0.95, legs=0.45)
            cube(p, -2.9, 1.4, y, y + 0.11, -2.3, 1.2, TIN, skip=("bottom",))  # terrace paving
            for i, (x, z) in enumerate(((-1.8, -1.2), (0.4, -1.2), (-0.7, 0.4))):
                parasol(p, x, z, y + 0.11, (YELLOW, WHITE, YELLOW)[i], r=0.55, h=1.3)
            for x in (-2.6, 1.1):
                planter(p, x - 0.25, x + 0.25, -2.25, 1.15, y + 0.11, h=0.3)
        return draw

    return tower("res-medium-a", lot, st, FLOORS[lot], base, facade, [crown(k) for k in range(5)], final_h=0.34)


# --- offices ------------------------------------------------------------------------------------


def ribbon_cols(lot: str, cw: float, ground_front: int = 1):
    """One glass ribbon per face, between the corner piers; the front starts above the lobby."""
    x0, x1, z0, z1 = BODIES[lot]
    wx = (x1 - x0) - 2 * cw - 0.1
    wz = (z1 - z0) - 2 * cw - 0.1
    zc = (z0 + z1) / 2
    return {
        "front": [(0.0, wx, ground_front)],
        "back": [(0.0, wx, 0)],
        "left": [(zc, wz, 0)],
        "right": [(zc, wz, 0)],
    }


def lobby(p: Part, b, st: Style, inset=0.45, glass=GLASS, columns=(), canopy_c=WHITE, frame=CHARCOAL,
          canopy_w=0.75) -> None:
    """A glazed lobby recessed under the floors above, carried on columns at the wall line."""
    x0, x1, z0, z1 = b
    zi = z0 + inset
    cube(p, x0, x1, 0.0, S, zi, z1, st.wall, skip=("bottom", "top"))
    lb = (x0 + 0.05, x1 - 0.05, zi, z1)
    panel(p, lb, "front", x0 + 0.05, x1 - 0.05, 0.0, S, GAP, frame)
    panel(p, lb, "front", x0 + 0.15, x1 - 0.15, 0.08, S - 0.12, 2 * GAP, glass)
    for u in columns:
        cube(p, u - 0.14, u + 0.14, 0.0, S, z0 - 0.02, z0 + 0.26, st.pier if st.get("pier") else st.wall,
             skip=("bottom", "top", "back"))
    door(p, (x0, x1, zi - 2 * GAP, z1), "front", 0.0, 0.9, h=1.2, frame=frame, leaf=CHARCOAL)
    canopy(p, b, -canopy_w, canopy_w, st.head, 0.55, c=canopy_c, edge=frame)


def office_narrow_a() -> list[Part]:
    """A slim office with slate spandrels between pale glass ribbons and white corner piers; a
    glazed lobby on two columns; the last stage puts a louvred plant room and a mast on top."""
    lot = "narrow"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cw = 0.3
    st = Style(wall=SLATE_LIGHT, band=SLATE_LIGHT, glass=GLASS, roof=SLATE, cap=WHITE, cap_top=WHITE,
               sill=0.34, head=1.3, cols=ribbon_cols(lot, cw), corner=cw, pier=WHITE, soffit=CHARCOAL,
               inner=SLATE_LIGHT)

    def base(p):
        lobby(p, b, st, columns=(-1.3, 1.3), canopy_w=0.6)
        floors(p, b, st, 0, FLOORS[lot][0], body_from=S)
        for sx in (-1, 1):
            planter(p, sx * 1.35 - 0.45, sx * 1.35 + 0.45, -3.85, -3.45, FC_TOP, edge=SLATE_LIGHT)
            shrub(p, sx * 1.35, -3.65, FC_TOP + 0.3, 0.28, seed=70 + sx)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                ac_unit(p, -0.9, 1.6, y)
                ac_unit(p, 0.9, 2.6, y)
                return
            plant_box(p, -1.25, 1.25, 0.2, 3.1, y, 0.95, c=WHITE, slat=SLATE_LIGHT)
            mast(p, -0.9, -1.6, y, 1.05)
        return draw

    return tower("office-narrow-a", lot, st, FLOORS[lot], base, None, [crown(k) for k in range(5)])


def office_narrow_b() -> list[Part]:
    """A slim office in pale grey with tall blue windows in two stacks, stone storey lines and a
    charcoal-framed lobby; the last stage tops it with a glass roof raked up to the back, so a
    terrace of offices alternates a flat plant-room roofline (A) with a sloping glass one."""
    lot = "narrow"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    zc = (z0 + z1) / 2
    cols = {
        "front": [(-0.8, 0.9, 1), (0.8, 0.9, 1)],
        "back": [(-0.8, 0.9, 0), (0.8, 0.9, 0)],
        "left": [(zc - 2.0, 0.9, 0), (zc, 0.9, 0), (zc + 2.0, 0.9, 0)],
        "right": [(zc - 2.0, 0.9, 0), (zc, 0.9, 0), (zc + 2.0, 0.9, 0)],
    }
    st = Style(wall=WALL_SHADE, band=WALL_SHADE, line=STONE, glass=BLUE, roof=SLATE_LIGHT, cap=STONE,
               cap_top=WHITE, sill=0.36, head=1.34, cols=cols, soffit=SLATE, inner=WALL_SHADE)

    def base(p):
        lobby(p, b, st, inset=0.4, columns=(-1.35, 1.35), glass=BLUE_PALE, canopy_c=STONE, frame=CHARCOAL,
              canopy_w=0.55)
        floors(p, b, st, 0, FLOORS[lot][0], body_from=S)
        planter(p, -1.75, -0.35, -3.85, -3.45, FC_TOP, edge=STONE)
        for i, x in enumerate((-1.45, -1.05, -0.65)):
            shrub(p, x, -3.65, FC_TOP + 0.3, 0.26, seed=76 + i)
        tree(p, 1.4, -3.5, FC_TOP, h=1.6, r=0.42, seed=75)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k == 1:
                ac_unit(p, -0.8, 1.4, y)
                ac_unit(p, 0.8, 2.6, y)
                return
            if k < 4:
                plant_box(p, -1.2, 1.2, 1.2, 3.0, y, 0.85, c=WALL_SHADE)
                ac_unit(p, -0.8, -1.4, y)
                return
            # a glass roof raked from 0.4 at the street to 1.05 at the back, white ribs on it; its
            # base is sunk GAP into the roof inside the cornice
            xa, xb, za, zb = x0 + 0.12, x1 - 0.12, z0 + 0.12, z1 - 0.12
            lo, front, back = y - GAP, y + 0.4, y + 1.05
            p.hexa([(xa, lo, za), (xb, lo, za), (xb, lo, zb), (xa, lo, zb),
                    (xa, front, za), (xb, front, za), (xb, back, zb), (xa, back, zb)], BLUE_PALE, bottom=SLATE)
            lift = GAP + MIN_MEMBER / 2 + 0.01  # the rib's underside clears the glass by GAP
            for x in (-0.75, 0.0, 0.75):
                beam(p, (x, front + lift, za + 0.05), (x, back + lift, zb - 0.05), MIN_MEMBER, MIN_MEMBER, WHITE)
        return draw

    return tower("office-narrow-b", lot, st, FLOORS[lot], base, None, [crown(k) for k in range(5)])


def office_small_a() -> list[Part]:
    """A white office with blue glass ribbons and stone corner piers on a pale glazed lobby;
    the last stage tops it with a long louvred plant screen."""
    lot = "small"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cw = 0.38
    st = Style(wall=WHITE, band=WHITE, glass=BLUE, roof=STONE, cap=STONE, cap_top=WALL_SHADE,
               sill=0.34, head=1.3, cols=ribbon_cols(lot, cw), corner=cw, pier=STONE, soffit=STONE,
               inner=WALL_SHADE)

    def base(p):
        lobby(p, b, st, columns=(-1.7, 1.7), glass=BLUE_PALE, canopy_c=STONE)
        floors(p, b, st, 0, FLOORS[lot][0], body_from=S)
        tree(p, -2.35, -2.42, FC_TOP, h=1.8, r=0.46, seed=80)
        tree(p, 2.35, -2.42, FC_TOP, h=1.6, r=0.44, seed=81)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                ac_unit(p, -1.3, 1.6, y)
                ac_unit(p, 0.0, 1.6, y)
                if k == 1:
                    hatch(p, 1.6, 1.6, y)
                else:
                    stair_hut(p, 1.6, 1.6, y, w=1.0, d=1.0, h=0.95, wall=WHITE, cap=STONE)
                return
            plant_box(p, -2.25, 2.25, -0.6, 2.45, y, 1.15, c=STONE, slat=SLATE_LIGHT)
            for x in (-1.5, 0.0, 1.5):
                cube(p, x - 0.32, x + 0.32, y + 1.15, y + 1.32, 0.6, 1.4, TIN, skip=("bottom",), top=SLATE)
        return draw

    return tower("office-small-a", lot, st, FLOORS[lot], base, None, [crown(k) for k in range(5)])


def office_small_b() -> list[Part]:
    """A curtain-wall office: pale-blue glass all round, thin slate floor lines, white fins at the
    corners; the last stage adds a chamfered glass crown with a white rim."""
    lot = "small"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cw = 0.22
    cols = ribbon_cols(lot, cw)
    st = Style(wall=SLATE_BLUE, band=SLATE, glass=BLUE_PALE, roof=SLATE, cap=WHITE, cap_top=WHITE,
               sill=0.08, head=1.45, cols=cols, corner=cw, pier=WHITE, soffit=SLATE, inner=SLATE_BLUE)

    def base(p):
        lobby(p, b, st, inset=0.5, columns=(-1.3, 1.3), glass=GLASS, canopy_c=WHITE, frame=SLATE)
        floors(p, b, st, 0, FLOORS[lot][0], body_from=S)
        for sx in (-1, 1):
            planter(p, sx * 2.2 - 0.55, sx * 2.2 + 0.55, -2.85, -2.35, FC_TOP, edge=WHITE)
            shrub(p, sx * 2.2, -2.6, FC_TOP + 0.3, 0.3, seed=90 + sx)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k == 1:
                for x in (-0.8, 0.4):
                    ac_unit(p, x, 1.3, y)
                return
            if k < 4:
                plant_box(p, -1.0, 1.0, 0.5, 2.1, y, 0.9, c=WALL_SHADE)
                return
            # glass crown: walls lean in from inside the cornice to a flat white cap, 1.42 tall; the
            # base is sunk GAP into the roof so none of its faces lies on the roof
            yb = y
            p.frustum(x0 + 0.12, x1 - 0.12, z0 + 0.12, z1 - 0.12, yb - GAP, x0 + 0.95, x1 - 0.95, z0 + 0.95,
                      z1 - 0.95, yb + 1.3 + GAP, BLUE_PALE, top=WHITE, bottom=SLATE)
            cube(p, x0 + 0.85, x1 - 0.85, yb + 1.3, yb + 1.42, z0 + 0.85, z1 - 0.85, WHITE)
        return draw

    return tower("office-small-b", lot, st, FLOORS[lot], base, None, [crown(k) for k in range(5)], final_h=0.12)


def office_medium_a() -> list[Part]:
    """A medium office in white spandrels and pale glass ribbons with slate corner piers and a
    slate-framed lobby; the last stage sets a glazed penthouse back on the roof under a thin white
    lid."""
    lot = "medium"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cw = 0.45
    st = Style(wall=WHITE, band=WHITE, glass=GLASS, roof=SLATE_LIGHT, cap=SLATE_LIGHT, cap_top=SLATE_LIGHT,
               sill=0.34, head=1.3, cols=ribbon_cols(lot, cw), corner=cw, pier=SLATE_LIGHT, soffit=SLATE,
               inner=WALL_SHADE)

    def base(p):
        lobby(p, b, st, inset=0.6, columns=(-2.6, -0.95, 0.95, 2.6), glass=BLUE_PALE, canopy_c=WHITE, frame=SLATE)
        floors(p, b, st, 0, FLOORS[lot][0], body_from=S)
        for sx in (-1, 1):
            planter(p, sx * 2.8 - 0.7, sx * 2.8 + 0.7, -3.75, -3.25, FC_TOP, edge=SLATE_LIGHT)
            tree(p, sx * 2.8, -3.5, FC_TOP + 0.32, h=1.7, r=0.44, seed=100 + sx)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                plant_box(p, -1.6, 1.6, 0.8, 2.8, y, 1.0, c=WALL_SHADE)
                ac_unit(p, -2.4, -1.5, y)
                return
            px0, px1, pz0, pz1 = x0 + 0.85, x1 - 0.85, z0 + 0.85, z1 - 0.85
            cube(p, px0, px1, y, y + 1.3 + GAP, pz0, pz1, BLUE_PALE, skip=("bottom",), top=SLATE)
            for u in (-1.6, 0.0, 1.6):
                panel(p, (px0, px1, pz0, pz1), "front", u - 0.05, u + 0.05, y, y + 1.3, GAP, WHITE)
            pzc = (pz0 + pz1) / 2
            for u in (pzc - 1.4, pzc, pzc + 1.4):
                panel(p, (px0, px1, pz0, pz1), "right", u - 0.05, u + 0.05, y, y + 1.3, GAP, WHITE)
            cube(p, px0 - 0.3, px1 + 0.3, y + 1.3, y + 1.4, pz0 - 0.3, pz1 + 0.3, WHITE)
            mast(p, px1 - 0.5, pz1 - 0.5, y + 1.4, 0.28)
        return draw

    return tower("office-medium-a", lot, st, FLOORS[lot], base, None, [crown(k) for k in range(5)])


def office_medium_b() -> list[Part]:
    """A stone-framed office: a regular grid of square windows in stone with lavender floor bands,
    an arcaded lobby; the last stage steps the top in twice, Art Deco fashion, to a flagpole."""
    lot = "medium"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    zc = (z0 + z1) / 2
    cols = {
        "front": [(u, 0.95, 1) for u in (-2.55, -1.28, 0.0, 1.28, 2.55)],
        "back": [(u, 0.95, 0) for u in (-2.55, -1.28, 0.0, 1.28, 2.55)],
        "left": [(zc + u, 0.95, 0) for u in (-2.4, -0.8, 0.8, 2.4)],
        "right": [(zc + u, 0.95, 0) for u in (-2.4, -0.8, 0.8, 2.4)],
    }
    st = Style(wall=STONE, band=LAVENDER, glass=BLUE, roof=SLATE_LIGHT, cap=LAVENDER, cap_top=WHITE,
               sill=0.36, head=1.3, cols=cols, soffit=SLATE, inner=STONE, pier=LAVENDER)

    def base(p):
        lobby(p, b, st, inset=0.55, columns=(-3.2, -1.9, -0.64, 0.64, 1.9, 3.2), glass=BLUE, canopy_c=LAVENDER,
              frame=SLATE, canopy_w=0.42)
        floors(p, b, st, 0, FLOORS[lot][0], body_from=S)
        for sx in (-1, 1):
            planter(p, sx * 2.9 - 0.6, sx * 2.9 + 0.6, -3.85, -3.4, FC_TOP, edge=LAVENDER)
            shrub(p, sx * 2.9 - 0.25, -3.62, FC_TOP + 0.3, 0.3, seed=110 + sx)
            shrub(p, sx * 2.9 + 0.3, -3.62, FC_TOP + 0.3, 0.26, seed=112 + sx)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                stair_hut(p, -2.3, 2.5, y, w=1.4, d=1.2, h=1.1, wall=STONE, cap=LAVENDER)
                plant_box(p, 0.4, 2.6, 1.5, 3.1, y, 0.8, c=WALL_SHADE)
                return
            yb = y + 0.3
            s1 = (x0 + 0.7, x1 - 0.7, z0 + 0.7, z1 - 0.7)
            cube(p, s1[0], s1[1], y, yb + 0.75, s1[2], s1[3], STONE, skip=("bottom",), top=SLATE_LIGHT)
            hollow(p, s1, yb + 0.75, yb + 0.9, 0.06, 0.18, LAVENDER, WHITE)
            for u in (-1.6, 0.0, 1.6):
                panel(p, s1, "front", u - 0.35, u + 0.35, yb + 0.15, yb + 0.6, GAP, BLUE)
            for u in (zc - 1.4, zc + 1.4):
                panel(p, s1, "right", u - 0.35, u + 0.35, yb + 0.15, yb + 0.6, GAP, BLUE)
            s2 = (x0 + 1.9, x1 - 1.9, z0 + 1.9, z1 - 1.9)
            cube(p, s2[0], s2[1], yb + 0.75, yb + 1.25, s2[2], s2[3], LAVENDER, skip=("bottom",), top=WHITE)
            cube(p, -0.05, 0.05, yb + 1.25, yb + 1.5, zc - 0.05, zc + 0.05, WHITE, skip=("bottom",))
        return draw

    return tower("office-medium-b", lot, st, FLOORS[lot], base, None, [crown(k) for k in range(5)])


# --- shops --------------------------------------------------------------------------------------


def shop_tower(slug, lot, st, awning, sign, front_frame, crowns, extra_base=None, extra_facade=None,
               door_u=0.0, body=None, awning_d=0.62) -> list[Part]:
    """A shop with flats above: a colourful shopfront, awning and sign at street level."""
    b = body or BODIES[lot]
    x0, x1, z0, z1 = b

    def base(p):
        floors(p, b, st, 0, FLOORS["shop"][0])
        # the shop window stands between the corner piers, if any, and well inside the awning ends
        inset = st.corner + GAP if st.get("corner") else 0.18
        shopfront(p, b, x0 + inset, x1 - inset, front_frame, door_u)
        sign_board(p, b, x0 + 0.2, x1 - 0.2, st.head + GAP, SIGN_TOP, sign[0], sign[1])
        stripes = min(9, int((x1 - x0) / 0.62) | 1)
        striped_awning(p, x0 + 0.1, x1 - 0.1, 1.18, 0.92, awning_d, awning, stripes, at=(0.0, 0.0, z0))
        if extra_base:
            extra_base(p)

    return tower(slug, lot, st, FLOORS["shop"], base, extra_facade, crowns, body=b)


def shop_narrow_a() -> list[Part]:
    """Pale pink flats over a yellow-and-white awning, a yellow sign and a charcoal shopfront;
    the last stage tops the flats with a stepped white false front and a water tank."""
    lot = "narrow"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cols = res_cols(lot)
    cols["front"] = [(-0.85, 0.9, 1), (0.85, 0.9, 1)]
    st = Style(wall=PINK_PALE, band=PINK_PALE, line=WHITE, glass=BLUE, roof=SLATE_LIGHT, cap=WHITE, cap_top=WHITE,
               sill=0.36, head=1.26, cols=cols, inner=PINK_PALE)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                ac_unit(p, -0.9, 2.2, y)
                return
            yb = y + 0.3
            zf = z0 - BAND_D - 0.02
            stepped_front(p, ((1.5, 0.35), (0.85, 0.65)), yb, zf, 0.22, WHITE, WHITE)
            water_tank(p, 0.8, 2.0, y, r=0.4, h=0.8, legs=0.3)
        return draw

    return shop_tower("shop-narrow-a", lot, st, (YELLOW, WHITE), (YELLOW, SLATE), CHARCOAL,
                      [crown(k) for k in range(5)], door_u=0.95)


def shop_narrow_b() -> list[Part]:
    """Pale blue flats with white storey lines over a green-and-white awning and a white sign with a
    green band; flower boxes under the windows; the last stage raises a stepped gable front."""
    lot = "narrow"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    cols = res_cols(lot)
    cols["front"] = [(-1.15, 0.56, 1), (0.0, 0.56, 1), (1.15, 0.56, 1)]
    st = Style(wall=BLUE_PALE, band=BLUE_PALE, line=WHITE, glass=SLATE_BLUE, roof=SLATE, cap=NAVY, cap_top=WHITE,
               sill=0.36, head=1.26, cols=cols, inner=BLUE_PALE)

    def flower_boxes(p, f0, f1):
        for n in range(max(f0, 1), f1):
            for u in (-1.15, 0.0, 1.15):
                panel(p, b, "front", u - 0.34, u + 0.34, n * S + 0.24, n * S + 0.5, LINE_D + 0.12, GREEN_DARK,
                      top=GREEN)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k == 1:
                hatch(p, 0.9, 2.5, y)
                ac_unit(p, -0.9, 2.2, y)
                return
            if k < 4:
                stair_hut(p, 0.95, 2.5, y, h=0.9, wall=BLUE_PALE, cap=NAVY)
                return
            yb = y + 0.3
            zf = z0 - BAND_D - 0.02
            stepped_front(p, ((1.6, 0.3), (1.1, 0.6), (0.6, 0.9)), yb, zf, 0.24, WHITE, NAVY)
            stair_hut(p, 0.95, 2.5, y, h=0.9, wall=BLUE_PALE, cap=NAVY)
        return draw

    return shop_tower("shop-narrow-b", lot, st, (GREEN, WHITE), (WHITE, GREEN_DARK), SLATE,
                      [crown(k) for k in range(5)], extra_facade=flower_boxes, door_u=-1.0)


CAFE_BODY = (-2.60, 2.60, -1.25, 2.80)  # set back from the street, so the café tables fit outside


def shop_small_a() -> list[Part]:
    """A corner café: cream flats with orange bands, an orange-and-white awning round the front and
    the right side, café parasols on its deeper forecourt; the last stage adds a roof garden and a
    water tank."""
    lot = "small"
    b = CAFE_BODY
    x0, x1, z0, z1 = b
    zc = (z0 + z1) / 2
    cols = {
        "front": [(-1.55, 1.1, 1), (0.0, 0.8, 1), (1.55, 1.1, 1)],
        "back": [(-1.3, 1.0, 0), (1.3, 1.0, 0)],
        "left": [(zc - 1.0, 1.0, 0), (zc + 1.0, 1.0, 0)],
        "right": [(zc - 1.0, 1.0, 1), (zc + 1.0, 1.0, 1)],
    }
    st = Style(wall=CREAM, band=CREAM, line=ORANGE, glass=BLUE, roof=SLATE_LIGHT, cap=ORANGE, cap_top=CREAM,
               sill=0.36, head=1.26, cols=cols, inner=CREAM)

    def side_shop(p):
        # the shop window carries round the corner on the right side, under its own awning
        za, zb = z0 + 0.12, z1 - 0.9
        panel(p, b, "right", za, zb, 0.0, 1.18, GAP, CHARCOAL)
        panel(p, b, "right", za + 0.1, zb - 0.1, 0.2, 1.08, 2 * GAP, GLASS)
        cube(p, x1, x1 + SIGN_D, st.head + GAP, SIGN_TOP, za, zb, ORANGE, skip=("left",))
        cube(p, x1 + SIGN_D, x1 + SIGN_D + GAP, 1.39, 1.53, za + 0.18, zb - 0.18, CREAM, skip=("left",))
        # its own awning, GAP longer than the window at each end so their ends never align
        striped_awning(p, za - 0.08, zb + 0.08, 1.18, 0.92, 0.36, (ORANGE, WHITE), 5, rot=-90.0, at=(x1, 0.0, 0.0))
        for i, x in enumerate((-1.75, 0.95)):
            parasol(p, x, -2.42, FC_TOP, (ORANGE, WHITE)[i], r=0.5, h=1.3)
            for dx in (-0.42, 0.42):
                cube(p, x + dx - 0.1, x + dx + 0.1, FC_TOP, FC_TOP + 0.3, -2.52, -2.32, WOOD, skip=("bottom",))

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k < 4:
                ac_unit(p, -1.4, 1.9, y)
                ac_unit(p, 0.0, 1.9, y)
                return
            water_tank(p, 1.5, 1.7, y, r=0.42, h=0.85, legs=0.3)
            planter(p, -2.3, 0.2, 1.3, 2.5, y, h=0.36)
            for i, x in enumerate((-1.8, -1.0, -0.3)):
                shrub(p, x, 1.9, y + 0.36, 0.36, seed=120 + i, leaf=(GREEN, GREEN_DARK, GREEN)[i])
            tree(p, -1.4, -0.3, y, h=1.0, r=0.42, seed=125)
        return draw

    return shop_tower("shop-small-a", lot, st, (ORANGE, WHITE), (ORANGE, CREAM), CHARCOAL,
                      [crown(k) for k in range(5)], extra_base=side_shop, door_u=-0.5, body=b, awning_d=0.55)


def shop_medium_a() -> list[Part]:
    """A small department store: a two-storey podium (a glazed shop floor under a white first floor
    with one long window) with a purple sign band and a purple-and-white awning, flats above in pale
    pink, a pink blade sign at the corner from stage 2, and a roof terrace of parasols at the last
    stage."""
    lot = "medium"
    b = BODIES[lot]
    x0, x1, z0, z1 = b
    zc = (z0 + z1) / 2
    cols = {
        "front": [(u, 1.2, 2) for u in (-2.4, -0.8, 0.8, 2.4)],
        "back": [(-1.6, 1.4, 0), (1.6, 1.4, 0)],
        "left": [(zc - 1.6, 1.2, 0), (zc + 1.6, 1.2, 0)],
        "right": [(zc - 1.6, 1.2, 2), (zc + 1.6, 1.2, 2)],
    }
    st = Style(wall=PINK_PALE, band=PINK_PALE, line=WHITE, glass=BLUE, roof=SLATE_LIGHT, cap=PURPLE, cap_top=WHITE,
               sill=0.36, head=1.26, cols=cols, inner=PINK_PALE, corner=0.4, pier=WHITE)

    def podium(p):
        # the store's first floor: white, with one long window on the front and on the right
        # the long window sits between the two floor bands, never under one
        ga, gb = S + st.sill + GAP, 2 * S - (S - st.head) - GAP
        panel(p, b, "front", x0 + 0.4, x1 - 0.4, S, 2 * S, GAP, WHITE)
        panel(p, b, "right", z0 + 0.4, z1 - 0.4, S, 2 * S, GAP, WHITE)
        panel(p, b, "front", x0 + 0.7, x1 - 0.7, ga, gb, 2 * GAP, BLUE_PALE)
        panel(p, b, "right", z0 + 0.7, z1 - 0.7, ga, gb, 2 * GAP, BLUE_PALE)
        for u in (-1.75, 0.0, 1.75):
            panel(p, b, "front", u - MIN_MEMBER / 2, u + MIN_MEMBER / 2, ga - GAP, gb + GAP, 3 * GAP, WHITE)
        for sx in (-1, 1):
            cube(p, sx * 3.0 - 0.5, sx * 3.0 + 0.5, 0.0, FC_TOP + 0.36, -3.92, -3.55, STONE, skip=("bottom",),
                 top=SOIL)
            shrub(p, sx * 3.0 - 0.2, -3.74, FC_TOP + 0.36, 0.22, seed=130 + sx)
            shrub(p, sx * 3.0 + 0.25, -3.74, FC_TOP + 0.36, 0.2, seed=133 + sx)

    def blade(p, f0, f1):
        if f1 == 4:  # the stage-2 piece (floors 3 to 4): the sign hangs across floors 2 and 3
            y0 = 2 * S + 0.3
            zf, zb = z0 - 1.0, z0 - LINE_D - GAP  # the board hangs clear of the bands and lines
            cube(p, x1 + 0.06, x1 + 0.2, y0, y0 + 2.5, zf, zb, PINK, top=WHITE, bottom=PURPLE)
            for xa, xb in ((x1 + 0.06 - GAP, x1 + 0.06), (x1 + 0.2, x1 + 0.2 + GAP)):
                cube(p, xa, xb, y0 + 0.3, y0 + 2.2, zf + 0.2, zb - 0.2, WHITE)
            for yy in (y0 + 0.35, y0 + 2.05):
                cube(p, x1 + 0.08, x1 + 0.18, yy, yy + 0.1, zb, z0, SLATE)

    def crown(k):
        def draw(p, y):
            if k == 0:
                return
            if k == 1:  # three storeys, like a narrow stage 1: keep under the early landmarks
                for x in (-0.6, 0.6):
                    ac_unit(p, x, 2.4, y)
                hatch(p, 2.2, 2.4, y)
                return
            if k < 4:
                plant_box(p, -1.0, 1.4, 1.6, 3.1, y, 0.8, c=WALL_SHADE)
                return
            stair_hut(p, 2.3, 2.5, y, w=1.3, d=1.2, h=1.2, wall=PINK_PALE, cap=PURPLE)
            cube(p, -3.0, 1.2, y, y + 0.11, -2.4, 1.6, TIN, skip=("bottom",))  # terrace paving
            for i, (x, z) in enumerate(((-2.2, -1.5), (-0.2, -1.5), (-1.2, 0.5))):
                parasol(p, x, z, y + 0.11, (PURPLE, PINK, PURPLE)[i], r=0.55, h=1.3)
            planter(p, -3.0, 1.2, 1.7, 2.2, y + 0.11, h=0.3)
        return draw

    return shop_tower("shop-medium-a", lot, st, (PURPLE, WHITE), (PURPLE, WHITE), SLATE,
                      [crown(k) for k in range(5)], extra_base=podium, extra_facade=blade, door_u=0.0)


# --- civic plazas -------------------------------------------------------------------------------


def paving(p: Part, lot: str, border: Rgb, field: Rgb, cross: Rgb, bw=0.55, cw=0.6) -> None:
    """Paving laid as a mosaic of slabs that only meet edge to edge (never stacked): a border, a
    cross through the middle and four fields."""
    w, d = LOTS[lot]
    hx, hz = w / 2, d / 2
    t = FC_TOP
    cube(p, -hx, hx, 0, t, -hz, -hz + bw, border, skip=("bottom",))
    cube(p, -hx, hx, 0, t, hz - bw, hz, border, skip=("bottom",))
    cube(p, -hx, -hx + bw, 0, t, -hz + bw, hz - bw, border, skip=("bottom",))
    cube(p, hx - bw, hx, 0, t, -hz + bw, hz - bw, border, skip=("bottom",))
    ix, iz = hx - bw, hz - bw
    cube(p, -cw / 2, cw / 2, 0, t, -iz, iz, cross, skip=("bottom",))
    cube(p, -ix, -cw / 2, 0, t, -cw / 2, cw / 2, cross, skip=("bottom",))
    cube(p, cw / 2, ix, 0, t, -cw / 2, cw / 2, cross, skip=("bottom",))
    for sx in (-1, 1):
        for sz in (-1, 1):
            xa, xb = sorted((sx * cw / 2, sx * ix))
            za, zb = sorted((sz * cw / 2, sz * iz))
            cube(p, xa, xb, 0, t, za, zb, field, skip=("bottom",))


def tilted_block(p: Part, y0: float, size: float, h: float, ang: float, c: Rgb) -> None:
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for yy in (y0, y0 + h):
        for lx, lz in ((-size / 2, -size / 2), (size / 2, -size / 2), (size / 2, size / 2), (-size / 2, size / 2)):
            pts.append((lx * ca - lz * sa, yy, lx * sa + lz * ca))
    p.hexa(pts, c)


def plaza_small() -> list[Part]:
    """A pocket square, 6 x 6: paving, two benches and two shrub planters; then trees in the four
    corners; then a sculpture of three stacked, turned blocks on a plinth (the feature, 2.6 tall)."""
    p0 = Part("plaza-small-0")
    paving(p0, "small", STONE, PAVE, LAVENDER)
    bench(p0, -1.45, 1.0, FC_TOP, 1.1, rot=180)
    bench(p0, 1.45, -1.0, FC_TOP, 1.1, rot=0)
    for sx in (-1, 1):
        planter(p0, sx * 2.35 - 0.3, sx * 2.35 + 0.3, -0.85, 0.85, FC_TOP, h=0.3)
        for i, z in enumerate((-0.45, 0.45)):
            shrub(p0, sx * 2.35, z, FC_TOP + 0.3, 0.28, seed=140 + i + sx)
    p1 = Part("plaza-small-1")
    for i, (sx, sz) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        x, z = sx * 2.25, sz * 2.25
        planter(p1, x - 0.45, x + 0.45, z - 0.45, z + 0.45, FC_TOP, h=0.34)
        tree(p1, x, z, FC_TOP + 0.34, h=1.9, r=0.52, seed=150 + i)
    p2 = Part("plaza-small-2")
    cube(p2, -0.5, 0.5, FC_TOP, FC_TOP + 0.5, -0.5, 0.5, LAVENDER, skip=("bottom",), top=WHITE)
    y = FC_TOP + 0.5
    for ang, c, size, h in ((10, ORANGE, 0.62, 0.72), (-22, YELLOW, 0.52, 0.66), (34, RED, 0.42, 0.6)):
        tilted_block(p2, y - 0.06, size, h, ang, c)
        y += h - 0.06
    return [p0, p1, p2]


def plaza_medium() -> list[Part]:
    """A civic square, 8 x 8: paving, four benches and low hedges; then four trees in planters;
    then an octagonal fountain with a bowl and a jet at the centre (the feature, 2.65 tall)."""
    p0 = Part("plaza-medium-0")
    paving(p0, "medium", STONE, PAVE, LAVENDER, bw=0.6, cw=0.8)
    for x, z, r in ((-2.2, -0.85, 0), (2.2, -0.85, 0), (-2.2, 0.85, 180), (2.2, 0.85, 180)):
        bench(p0, x, z, FC_TOP, 1.2, rot=r)
    for sz in (-1, 1):
        for sx in (-1, 1):
            xa, xb = sorted((sx * 0.9, sx * 2.9))
            cube(p0, xa, xb, FC_TOP, FC_TOP + 0.36, sz * 3.0 - 0.2, sz * 3.0 + 0.2, GREEN_DARK, skip=("bottom",),
                 top=GREEN)
    p1 = Part("plaza-medium-1")
    for i, (sx, sz) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        x, z = sx * 2.85, sz * 2.0
        planter(p1, x - 0.42, x + 0.42, z - 0.42, z + 0.42, FC_TOP, h=0.34)
        tree(p1, x, z, FC_TOP + 0.34, h=2.0, r=0.55, seed=160 + i)
    p2 = Part("plaza-medium-2")
    # basin: outer wall, rim, inner wall down to a floor that sits under the water
    lathe(p2, [(1.35, FC_TOP), (1.35, FC_TOP + 0.36), (1.12, FC_TOP + 0.36), (1.12, FC_TOP + 0.12)],
          [STONE, WHITE, STONE], seg=8, phase=math.pi / 8)
    lathe(p2, [(1.14, FC_TOP + 0.26), (0.0, FC_TOP + 0.26)], [BLUE], seg=8, phase=math.pi / 8)
    lathe(p2, [(0.4, FC_TOP + 0.12), (0.34, FC_TOP + 0.8), (0.62, FC_TOP + 0.86), (0.62, FC_TOP + 0.96),
               (0.0, FC_TOP + 0.96)], [STONE, STONE, WHITE, BLUE], seg=8, phase=math.pi / 8)
    lathe(p2, [(0.15, FC_TOP + 0.96), (0.05, FC_TOP + 2.5), (0.0, FC_TOP + 2.55)], [GLASS, GLASS], seg=6)
    for k in range(6):
        a = 2 * math.pi * (k + 0.5) / 6
        beam(p2, (0.12 * math.cos(a), FC_TOP + 2.0, 0.12 * math.sin(a)),
             (0.9 * math.cos(a), FC_TOP + 0.32, 0.9 * math.sin(a)), MIN_MEMBER, MIN_MEMBER, GLASS)
    return [p0, p1, p2]


# --- the props and their checks -----------------------------------------------------------------

# Blueprint id -> (lot, builder, uses the generic forecourt); BODY_OF names a non-standard body
PROPS = {
    "FabricResNarrowA": ("narrow", res_narrow_a, True),
    "FabricResNarrowB": ("narrow", res_narrow_b, True),
    "FabricResSmallA": ("small", res_small_a, True),
    "FabricResSmallB": ("small", res_small_b, True),
    "FabricResMediumA": ("medium", res_medium_a, True),
    "FabricOfficeNarrowA": ("narrow", office_narrow_a, True),
    "FabricOfficeNarrowB": ("narrow", office_narrow_b, True),
    "FabricOfficeSmallA": ("small", office_small_a, True),
    "FabricOfficeSmallB": ("small", office_small_b, True),
    "FabricOfficeMediumA": ("medium", office_medium_a, True),
    "FabricOfficeMediumB": ("medium", office_medium_b, True),
    "FabricShopNarrowA": ("narrow", shop_narrow_a, True),
    "FabricShopNarrowB": ("narrow", shop_narrow_b, True),
    "FabricShopSmallA": ("small", shop_small_a, True),
    "FabricShopMediumA": ("medium", shop_medium_a, True),
    "FabricPlazaSmall": ("small", plaza_small, False),
    "FabricPlazaMedium": ("medium", plaza_medium, False),
}
BODY_OF = {"FabricShopSmallA": CAFE_BODY}
FORECOURTS = {f"forecourt-{lot}": (lambda lot=lot: forecourt(f"forecourt-{lot}", lot)) for lot in LOTS}


def stage_floors(prop: str) -> tuple[int, ...] | None:
    lot, _, generic = PROPS[prop]
    if not generic:
        return None
    return FLOORS["shop"] if prop.startswith("FabricShop") else FLOORS[lot]


def flat_faces(parts: list[Part]) -> list[tuple]:
    """Every axis-aligned face of the parts as (axis, facing, plane, (a0, a1, b0, b1)): the axis
    its normal lies on, +1 or -1, the plane's coordinate on that axis, and its extent on the other
    two axes."""
    out = []
    for part in parts:
        for idx, _ in part.faces:
            pts = [part.verts[i] for i in idx]
            n = [0.0, 0.0, 0.0]
            for i, a in enumerate(pts):  # Newell normal
                b = pts[(i + 1) % len(pts)]
                n[0] += (a[1] - b[1]) * (a[2] + b[2])
                n[1] += (a[2] - b[2]) * (a[0] + b[0])
                n[2] += (a[0] - b[0]) * (a[1] + b[1])
            length = math.sqrt(sum(c * c for c in n))
            if length < 1e-9:
                continue
            axis = max(range(3), key=lambda i: abs(n[i]))
            if abs(n[axis]) / length < 0.9999:
                continue
            u, v = [i for i in range(3) if i != axis]
            out.append((axis, 1 if n[axis] > 0 else -1, pts[0][axis], [(q[u], q[v]) for q in pts]))
    return out


def convex_overlap(a, b) -> bool:
    """True when two convex polygons share some area (separating-axis test, touching edges do not
    count)."""
    for poly in (a, b):
        for i in range(len(poly)):
            (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
            nx, ny = y1 - y0, x0 - x1
            if abs(nx) + abs(ny) < 1e-12:
                continue
            pa = [nx * x + ny * y for x, y in a]
            pb = [nx * x + ny * y for x, y in b]
            scale = math.hypot(nx, ny)
            if (min(max(pa), max(pb)) - max(min(pa), min(pb))) / scale <= 1e-4:
                return False
    return True


def face_fights(parts: list[Part]) -> list[str]:
    """Pairs of faces that would flicker: parallel, facing the same way, overlapping in their plane
    and closer than GAP (coplanar included). Opposite-facing pairs never render together, because
    a MeshPart culls back faces, so they are not reported."""
    faces = flat_faces(parts)
    found = []
    by_key: dict = {}
    for f in faces:
        by_key.setdefault((f[0], f[1]), []).append(f)
    for (axis, facing), group in by_key.items():
        group.sort(key=lambda f: f[2])
        for i, a in enumerate(group):
            for b in group[i + 1:]:
                if b[2] - a[2] >= GAP - 1e-6:
                    break
                if convex_overlap(a[3], b[3]):
                    us = [q[0] for q in a[3]]
                    vs = [q[1] for q in a[3]]
                    found.append(f"{'xyz'[axis]}{'+' if facing > 0 else '-'} faces {b[2] - a[2]:.3f} apart at "
                                 f"{'xyz'[axis]} = {a[2]:.2f} near ({min(us):.2f}..{max(us):.2f}, "
                                 f"{min(vs):.2f}..{max(vs):.2f})")
    return found


def check(prop: str, parts: list[Part], rods=()) -> list[str]:
    """The contract, the burial rule, the face-gap rule and the member rule (`rods`: what cube()
    flagged while the prop was built), per prop. Returns violations."""
    lot, _, generic = PROPS[prop]
    w, d = LOTS[lot]
    bad = []
    fc = forecourt("fc", lot) if generic else None
    tris = fc.tris if fc else 0
    top = 0.0
    for k, part in enumerate(parts):
        tris += part.tris
        lo, hi = part.bounds()
        top = max(top, hi[1])
        if tris > TRI_BUDGET:
            bad.append(f"stage {k}: {tris} tris > {TRI_BUDGET}")
        if lo[0] < -w / 2 - 0.01 or hi[0] > w / 2 + 0.01 or lo[2] < -d / 2 - 0.01 or hi[2] > d / 2 + 0.01:
            bad.append(f"stage {k}: leaves the {w:g} x {d:g} lot: "
                       f"x[{lo[0]:.2f}, {hi[0]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}]")
        if k == 0 and top > HEIGHT_FLOOR + 1e-6:
            bad.append(f"stage 0 is {top:.2f} tall > heightFloor {HEIGHT_FLOOR}")
        fl = stage_floors(prop)
        if k == 1 and fl and fl[1] == 3 and top > fl[1] * S + LOW_PLANT + 1e-6:
            bad.append(f"stage 1 is {top:.2f} tall: only roof plant <= {LOW_PLANT} may stand on it")
        for fight in face_fights(([fc] if fc else []) + parts[: k + 1])[:3]:
            bad.append(f"stage {k}: {fight}")
    for rod in sorted(set(rods))[:5]:
        bad.append(f"a member {rod[0]:g} x {rod[1]:g} x {rod[2]:g} is thinner than {MIN_MEMBER} in two dimensions")
    fl = stage_floors(prop)
    if fl:
        x0, x1, z0, z1 = BODY_OF.get(prop, BODIES[lot])
        m = BURY_MARGIN
        for k in range(len(parts) - 1):
            roof, nxt = fl[k] * S, fl[k + 1] * S
            for x, y, z in parts[k].verts:
                if y <= roof + 1e-6:
                    continue
                if not (x0 + m <= x <= x1 - m and z0 + m <= z <= z1 - m and y <= nxt - m):
                    bad.append(f"stage {k}: ({x:.2f}, {y:.2f}, {z:.2f}) above the roof {roof:.2f} "
                               f"is not buried by stage {k + 1}")
                    break
    return bad


def write_blueprints() -> None:
    os.makedirs(BLUEPRINT_DIR, exist_ok=True)
    for prop, (lot, make, generic) in PROPS.items():
        parts = make()
        pieces = []
        if generic:
            pieces.append({"kit": KIT, "model": f"forecourt-{lot}", "pos": [0, 0, 0], "rotY": 0, "stage": 0})
        for k, part in enumerate(parts):
            pieces.append({"kit": KIT, "model": part.name, "pos": [0, 0, 0], "rotY": 0, "stage": k})
        w, d = LOTS[lot]
        lines = [
            "{",
            f'  "id": "{prop}",',
            '  "era": "Metropolis",',
            '  "scale": 1.0,',
            f'  "footprint": [{w:g}, {d:g}],',
            '  "pieces": [',
        ]
        lines += ["    " + json.dumps(pc, separators=(", ", ": ")) + ("," if i < len(pieces) - 1 else "")
                  for i, pc in enumerate(pieces)]
        lines += ["  ]", "}"]
        path = os.path.join(BLUEPRINT_DIR, f"{prop}.json")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
        log(f"wrote {os.path.relpath(path, REPO_ROOT)}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the tower-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    parser.add_argument("--write-blueprints", action="store_true", help="also (re)write the 17 fabric blueprints")
    parser.add_argument("--summary", help="write per-stage heights, extents and triangles here (JSON)")
    args = parser.parse_args(argv)
    summary_out: dict = {}

    os.makedirs(args.out, exist_ok=True)
    failures = 0
    pieces: dict = dict(FORECOURTS)
    for prop, (lot, make, generic) in PROPS.items():
        RODS.clear()
        parts = make()
        problems = check(prop, parts, list(RODS))
        fc = forecourt("fc", lot).tris if generic else 0
        running = fc
        summary = []
        lo_all, hi_all = [9e9] * 3, [-9e9] * 3
        if generic:
            w, d = LOTS[lot]
            lo_all, hi_all = [-w / 2, 0.0, -d / 2], [w / 2, FC_TOP, d / 2]
        stages = []
        for part in parts:
            running += part.tris
            lo, hi = part.bounds()
            lo_all = [min(a, b) for a, b in zip(lo_all, lo)]
            hi_all = [max(a, b) for a, b in zip(hi_all, hi)]
            summary.append(f"{part.bounds()[1][1]:.2f}/{running}")
            stages.append({"height": round(hi_all[1] - min(0.0, lo_all[1]), 3), "tris": running,
                           "x": [round(lo_all[0], 3), round(hi_all[0], 3)],
                           "z": [round(lo_all[2], 3), round(hi_all[2], 3)]})
        summary_out[prop] = {"lot": lot, "stages": stages,
                             "colours": sorted({"%d,%d,%d" % c for part in parts for _, c in part.faces})}
        log(f"{prop}: stage top/tris " + "  ".join(summary))
        for msg in problems:
            log(f"  PROBLEM {prop}: {msg}")
        failures += len(problems)
        for part in parts:
            pieces[part.name] = (lambda part=part: part)

    total = 0
    for name, make in pieces.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        export(build_object(part, {}), args.out)
        total += part.tris
    colours = set()
    for make in pieces.values():
        colours.update(c for _, c in make().faces)
    log(f"{len(pieces)} pieces, {total} tris, {len(colours)} colours -> {os.path.relpath(args.out, REPO_ROOT)}")
    if args.write_blueprints:
        write_blueprints()
    if args.summary:
        with open(args.summary, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(summary_out, fh, indent=1)
        log(f"summary -> {args.summary}")
    if failures:
        log(f"{failures} problem(s)")
        return 1
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
