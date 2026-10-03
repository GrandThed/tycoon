"""Fabric towers for the Metropolis growing city (M12 wave 3), generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/tower_kit.py [-- --out <dir>] [--write-blueprints]

Writes one GLB per piece into assets/kenney3d/tower-kit/Models/GLB format/, the folder convention
every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py discover the
kit with no registration step. assets/ is gitignored, so this script is the committed artifact and
the GLBs regenerate from it. `--write-blueprints` also (re)writes the 18 fabric blueprints under
tools/testfit/blueprints/_props/Metropolis/ from PROPS, so the pieces and the stages that use them
cannot drift apart; leave it off to keep a hand-edited blueprint.

Why a custom kit (docs/CITY_GROWTH.md sections 3 and 4): every city-kit-commercial `building-*`
is a finished block, already a landmark or reserved for one, and none of them can grow a floor
(their roofs and parapets sit proud of the walls). A Metropolis fabric tower has to **grow floor
by floor**, so its pieces are generated: a street-level base (lobby, shopfront or front door), a
run of floors per growth stage, and a crown. Filler never copies a landmark's silhouette or its
signature pieces: no rounded glass corners, no vertical blue window strips, no green pyramid roof,
no highway-sign gantries on roofs. Offices here read through horizontal ribbon windows, louvred
plant screens and glass crowns; homes through warm walls, punched windows and balconies; shops
through colourful awnings and signs at street level with flats above.

**The final set** (2026-10-03) is the eleven props the approved 85-lot layout can show, on narrow
4 x 8 and small 6 x 6 lots, and the seven Green twins of its homes and shops ("Green the
Rooftops"). The medium towers, the pocket plazas and the finance-district Crown twins of the wave
3.1 drafts are gone: the layout never draws them.

**Units.** 1 glTF unit = 1 stud, like garage-kit and metro-kit; blueprints use `"scale": 1.0`, so
every literal below is directly checkable in studs. A storey is S = 1.6 studs, the commercial
kit's storey at scale 4, so filler floors line up with the landmarks' floors.

**Frames.** Every stage piece is authored in the lot frame: origin at the lot's bottom-centre,
front -Z (the street), so a blueprint places all of a prop's pieces at [0, 0, 0] and its stages
register exactly (the boomtown-extras-kit shop pattern). Small furniture is built into the stage
pieces too.

**Storeys stay, roofs retire.** Each stage is two pieces: its storeys (`<slug>-<k>`), which stay
for good, and its roof (`<slug>-<k>-roof`), which the blueprint gives `untilStage` k, so it leaves
the mesh when stage k + 1 builds over it instead of staying buried in every later one (a stage-4
tower used to carry the roofs of stages 0 to 3). The roof piece holds everything the next stage
covers: the roof deck, the parapet, the plant or the garden, a false front, and the caps that only
show while the stage is the top one (the tops of piers and bays, the heads of the top-floor
windows). The floors of a new stage continue the walls below in the same plane (adjacent, never
overlapping), and its first floor band is laid across the old roof line so the joint reads like
every other floor line. `holes` asserts, per prop, that a retired roof leaves nothing open: the
next storeys stand exactly on the old roof deck and every other cap lies inside a box they add. A
Green twin differs from its original only in its roof pieces, so the two share their storeys.

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
PINK_PALE = (245, 200, 240)  # industrial
CREAM = (253, 228, 199)
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
PARAPET_IN = 0.06  # an interim parapet stands this far inside the wall line (the look Ben approved)
PARAPET_T = 0.16
HEIGHT_FLOOR = 3.4  # CityDressing.json eras.Metropolis.fabric.heightFloor
TRI_BUDGET = 2000  # per stage, per prop (contract)
LOW_PLANT = 0.36  # the tallest roof plant a stage 1 carries (an a/c unit is 0.28)

LOTS = {"narrow": (4.0, 8.0), "small": (6.0, 6.0)}  # the approved layout has no medium lot
# The tower body (x0, x1, z0, z1) on each lot: storey lines (LINE_D proud) stay 0.01 inside the lot
# line, so narrow lots stand shoulder to shoulder as a terrace, and the front leaves a forecourt.
BODIES = {
    "narrow": (-1.83, 1.83, -2.90, 3.75),
    "small": (-2.60, 2.60, -1.90, 2.80),
}
# Floors at each stage. Stage 0 is two storeys (3.2 + parapet <= 3.4); the tops are measured
# against the landmarks: narrow <= 14, small <= 17.5, shops <= 11. Stage 1 is where a level-2
# parcel starts (levelStages [1, 3, 4]) and is three storeys everywhere, so it carries only low
# roof plant (<= LOW_PLANT): it stays at 5.16 or under, below the early landmarks' 5.17, and a
# parcel by one of them shows its stage 1 instead of being capped back to stage 0.
FLOORS = {
    "narrow": (2, 3, 4, 6, 8),
    "small": (2, 3, 5, 7, 10),
    "shop": (2, 3, 4, 5, 6),
}


def log(msg: str) -> None:
    print(f"[{KIT}] {msg}", flush=True)


# --- primitives (glTF space: Y up, front -Z) ----------------------------------------------------


RODS: list[tuple[float, float, float]] = []  # boxes thin in two dimensions; check() reads it per prop


class Stage(Part):
    """One piece of a tower stage: its storeys, or its roof. A storeys piece notes the closed boxes
    it adds (`solids`: body, bands, a bay) and a roof piece the faces with which it closes what
    stands under it (`caps`: the roof deck, the tops of piers, bays and top-floor windows). `holes`
    reads both: when a roof retires, every cap must be covered by a solid of the next stage."""

    def __init__(self, name: str):
        super().__init__(name)
        self.solids: list[tuple[float, float, float, float, float, float]] = []  # x0, x1, y0, y1, z0, z1
        self.caps: list[tuple[float, float, float, float, float]] = []  # x0, x1, y, z0, z1


def cap(r: Stage, x0, x1, y, z0, z1, c: Rgb) -> None:
    """A face looking up at height y that closes a box left open at the top: it belongs to the
    stage's roof piece, because the next stage builds over it. Winding as cube()'s top."""
    r.face([(x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0)], c)
    r.caps.append((x0, x1, y, z0, z1))


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


def wall_box(b, face: str, u0, u1, d) -> tuple[float, float, float, float, str]:
    """The plan (x0, x1, z0, z1) of a slab d proud of one wall of body b, spanning u0..u1 along it
    (x on front and back, z on the sides), and the face of it that lies on the wall."""
    x0, x1, z0, z1 = b
    if face == "front":
        return u0, u1, z0 - d, z0, "back"
    if face == "back":
        return u0, u1, z1, z1 + d, "front"
    if face == "left":
        return x0 - d, x0, u0, u1, "right"
    return x1, x1 + d, u0, u1, "left"


def panel(p: Part, b, face: str, u0, u1, y0, y1, d, c: Rgb, skip=(), **sides) -> None:
    """A slab d proud of one wall of body b, spanning u0..u1 along that wall. Its back face lies
    on the wall and is left out, with any faces in `skip`."""
    xa, xb, za, zb, on_wall = wall_box(b, face, u0, u1, d)
    under = ("bottom",) if y0 <= 0.0 else ()  # on the ground the underside is hidden
    cube(p, xa, xb, y0, y1, za, zb, c, skip=(on_wall,) + tuple(skip) + under, **sides)


def ring(p: Stage, b, y0, y1, d, c: Rgb) -> None:
    """A band d proud all round body b: one box, its top and bottom inside the body but the rim."""
    x0, x1, z0, z1 = b
    cube(p, x0 - d, x1 + d, y0, y1, z0 - d, z1 + d, c)
    p.solids.append((x0 - d, x1 + d, y0, y1, z0 - d, z1 + d))


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


def corner_piers(p: Stage, r: Stage, b, y0, y1, w, c: Rgb, under: bool = False) -> None:
    """A pier PIER_D proud at each corner, `w` along each face: one box per corner, its two inner
    faces left out (they lie inside the body). It stops GAP short of the roof, so its top never
    shares the roof's plane; the next stage's joint band, or the last stage's cornice, covers the
    step, and the tops are caps on the roof piece r. `under` draws the undersides, for piers that
    start above a recessed lobby."""
    x0, x1, z0, z1 = b
    d = PIER_D
    top = y1 - GAP
    if not under:
        boxes = [
            (x0 - d, x0 + w, z0 - d, z0 + w, ("bottom", "back", "right")),
            (x1 - w, x1 + d, z0 - d, z0 + w, ("bottom", "back", "left")),
            (x0 - d, x0 + w, z1 - w, z1 + d, ("bottom", "front", "right")),
            (x1 - w, x1 + d, z1 - w, z1 + d, ("bottom", "front", "left")),
        ]
    else:
        # over a recessed lobby a box's underside would share the soffit's plane: two slabs per
        # corner, both outside the body
        boxes = [
            (x0 - d, x0 + w, z0 - d, z0, ("back",)),
            (x1 - w, x1 + d, z0 - d, z0, ("back",)),
            (x0 - d, x0 + w, z1, z1 + d, ("front",)),
            (x1 - w, x1 + d, z1, z1 + d, ("front",)),
            (x0 - d, x0, z0, z0 + w, ("right", "front")),
            (x0 - d, x0, z1 - w, z1, ("right", "back")),
            (x1, x1 + d, z0, z0 + w, ("left", "front")),
            (x1, x1 + d, z1 - w, z1, ("left", "back")),
        ]
    for xa, xb, za, zb, sk in boxes:
        cube(p, xa, xb, y0, top, za, zb, c, skip=sk + ("top",))
        cap(r, xa, xb, top, za, zb, c)


def blob(p: Part, centre, radii, c: Rgb, seg: int = 6, rings: int = 2, seed: int = 0) -> None:
    p.blob(centre, radii, c, seg=seg, rings=rings, cut=-0.35, jitter=0.08, seed=seed)


# --- a tower's floors ---------------------------------------------------------------------------


class Style(dict):
    """A facade: colours (wall, band, line, glass, roof, cap, cap_top, inner, soffit, pier), window
    heights in a storey (sill, head), window columns per face as (u centre, width, first floor[,
    last floor, exclusive]), and options (corner = pier width)."""

    def __getattr__(self, key):
        return self[key]


def floors(p: Stage, r: Stage, b, st: Style, f0: int, f1: int, body_from: float | None = None) -> None:
    """Floors f0 .. f1-1 of body b, on the storeys piece p: the wall, the window panels and a band
    at every floor line from f0 up (at f0 > 0 that band is laid across the roof line of the stage
    below, so the joint reads as an ordinary floor line). `body_from` starts the wall higher, over
    a lobby. What only shows while these are the top floors goes on the roof piece r as caps: the
    roof deck and the heads of the top-floor windows, which the next stage's first band covers."""
    x0, x1, z0, z1 = b
    y0, y1 = f0 * S, f1 * S
    ya = y0 if body_from is None else body_from
    skip = ("bottom", "top") if (ya == 0.0 or f0 > 0) else ("top",)
    cube(p, x0, x1, ya, y1, z0, z1, st.wall, skip=skip, bottom=st.get("soffit", st.wall))
    p.solids.append((x0, x1, ya, y1, z0, z1))
    cap(r, x0, x1, y1, z0, z1, st.roof)  # the roof deck: always the first cap of a roof piece
    for face, cols in st.cols.items():
        for col in cols:
            u, w, first = col[:3]
            lo, hi = max(f0, first), min(f1, col[3] if len(col) > 3 else f1)
            if lo >= hi:
                continue
            # a panel's end that reaches into a floor band is hidden inside it, so it is left out;
            # a head with no band over it yet is a cap
            ends = (("bottom",) if lo >= 1 else ()) + ("top",)
            head = (hi - 1) * S + st.head + GAP
            panel(p, b, face, u - w / 2, u + w / 2, lo * S + st.sill - GAP, head, GLASS_D, st.glass, skip=ends)
            if hi == f1:
                xa, xb, za, zb, _ = wall_box(b, face, u - w / 2, u + w / 2, GLASS_D)
                cap(r, xa, xb, head, za, zb, st.glass)
    for n in range(max(f0, 1), f1):
        ring(p, b, (n - 1) * S + st.head, n * S + st.sill, BAND_D, st.band)
        if st.get("line"):  # a thin storey line in the trim colour, in front of the band
            ring(p, b, n * S - LINE_H / 2, n * S + LINE_H / 2, LINE_D, st.line)
    if st.get("corner"):
        corner_piers(p, r, b, ya if f0 == 0 else y0, y1, st.corner, st.pier, under=f0 == 0 and ya > 0)


def interim_top(p: Part, b, y: float, st: Style) -> None:
    """The parapet of a stage that a later stage will build over: set back from the wall line."""
    hollow(p, b, y, y + PARAPET_H, -PARAPET_IN, PARAPET_T, st.wall, st.cap, inner=st.get("inner", st.wall))


def final_top(p: Part, b, y: float, st: Style, h: float = 0.3) -> None:
    """The last stage's parapet: a cornice standing proud of everything below."""
    hollow(p, b, y, y + h, BAND_D, BAND_D, st.cap, st.cap_top, inner=st.get("inner", st.wall), under=True)


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


def mast(p: Part, x, z, y, h) -> None:
    """A slim mast with cross-arms (one on a short mast) and a red tip. The arms stand GAP proud of
    the pole on both faces, so no arm face lies close in front of a pole face."""
    pole = MIN_MEMBER / 2
    cube(p, x - pole, x + pole, y, y + h, z - pole, z + pole, SLATE_LIGHT, skip=("bottom",))
    for k in ((0.4, 0.78) if h >= 0.6 else (0.5,)):
        yy = y + h * k - MIN_MEMBER / 2
        arm = 0.32 * (1.2 - k)
        cube(p, x - arm, x + arm, yy, yy + MIN_MEMBER, z - pole - GAP, z + pole + GAP, SLATE)
    cube(p, x - 0.08, x + 0.08, y + h, y + h + 0.12, z - 0.08, z + 0.08, RED, skip=("bottom",))


def tree(p: Part, x, z, y, h=2.0, r=0.62, seed=0, leaf=GREEN, trunk=SLATE, seg: int = 6) -> None:
    """A street tree: a slim trunk and a faceted crown, h tall from y."""
    cube(p, x - 0.07, x + 0.07, y, y + h * 0.42, z - 0.07, z + 0.07, trunk, skip=("bottom", "top"))
    blob(p, (x, y + h * 0.55, z), (r, h * 0.45, r), leaf, seg=seg, seed=seed)


def planter(p: Part, x0, x1, z0, z1, y, h=0.32, edge=STONE, soil=SOIL) -> None:
    cube(p, x0, x1, y, y + h, z0, z1, edge, skip=("bottom",), top=soil)


def shrub(p: Part, x, z, y, r=0.32, seed=0, leaf=GREEN_DARK) -> None:
    """A bush set into a planter or a slab. Its underside is never seen, so it has no bottom cap:
    neighbouring bushes' caps would otherwise lie in one plane inside the planter."""
    first = len(p.faces)
    blob(p, (x, y, z), (r, r * 0.8, r), leaf, seg=5, rings=2, seed=seed)
    del p.faces[first]  # Part.blob lays the bottom cap first


def bench(p: Part, x, z, y, length=1.1) -> None:
    """A park bench facing -Z: seat and back on two slate feet."""
    hl = length / 2
    parts = [
        (-hl, hl, 0.22, 0.32, -0.18, 0.06, WOOD),  # seat
        (-hl, hl, 0.32, 0.62, 0.06, 0.16, WOOD),  # back
        (-hl + 0.06, -hl + 0.16, 0.0, 0.22, -0.13, 0.01, SLATE),  # feet end under the seat
        (hl - 0.16, hl - 0.06, 0.0, 0.22, -0.13, 0.01, SLATE),
    ]
    for ax0, ax1, ay0, ay1, az0, az1, c in parts:
        cube(p, x + ax0, x + ax1, y + ay0, y + ay1, z + az0, z + az1, c, skip=("bottom",))


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
          body=None, fixtures=None) -> list[tuple[Stage, Stage]]:
    """The stages of one tower, each as (storeys piece, roof piece). The storeys stay for good:
    `base(p, r)` draws the street level and the first floors (stage 0) and `facade(p, r, f0, f1)`
    whatever rises with each run of floors (balconies, bays, signs). The roof piece is everything
    the next stage builds over, and the blueprint retires it at that stage: the caps the storeys
    lay on r, the parapet, `crowns[k](r, y)` at roof height y, and `fixtures[k](r, y)`, which stay
    on that roof under a garden too (a false front). While GARDEN holds a style, every crown gives
    way to a roof garden: that is how a Green twin is built."""
    b = body or BODIES[lot]
    stages = []
    f_prev = 0
    for k, f in enumerate(floors_at):
        p, r = Stage(f"{slug}-{k}"), Stage(f"{slug}-{k}-roof")
        if k == 0:
            base(p, r)
        else:
            floors(p, r, b, st, f_prev, f)
        if facade:
            facade(p, r, f_prev, f)
        y = f * S
        if k < len(floors_at) - 1:
            interim_top(r, b, y, st)
        else:
            final_top(r, b, y, st, final_h)
        if GARDEN["style"]:
            green_roof(r, b, y, k, len(floors_at) - 1, GARDEN["style"])
        else:
            crowns[k](r, y)
        if fixtures and k in fixtures:
            fixtures[k](r, y)
        stages.append((p, r))
        f_prev = f
    return stages


def res_cols(lot: str):
    """Punched windows for a home: (u, width, first floor) per face."""
    if lot == "narrow":
        return {
            "front": [(-0.85, 0.9, 0), (0.85, 0.9, 0)],
            "back": [(-0.85, 0.85, 0), (0.85, 0.85, 0)],
            "left": [(-1.3, 0.95, 0), (1.9, 0.95, 0)],
            "right": [(-1.3, 0.95, 0), (1.9, 0.95, 0)],
        }
    return {
        "front": [(-1.55, 1.15, 0), (0.0, 0.8, 1), (1.55, 1.15, 0)],
        "back": [(-1.3, 1.0, 0), (1.3, 1.0, 0)],
        "left": [(-0.75, 1.0, 0), (1.55, 1.0, 0)],
        "right": [(-0.75, 1.0, 0), (1.55, 1.0, 0)],
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

    def base(p, r):
        floors(p, r, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.85, 0.8, leaf=SLATE)
        canopy(p, b, 0.45, 1.35, st.head, 0.5)
        step(p, b, 0.85, 1.0)
        planter(p, -1.75, -0.2, -3.85, -3.35, FC_TOP)
        for i, x in enumerate((-1.4, -0.95, -0.5)):
            shrub(p, x, -3.6, FC_TOP + 0.3, 0.26, seed=11 + i)

    def facade(p, r, f0, f1):
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

    def bay_run(p, r, f0, f1):
        lo = max(f0, 1)
        if lo >= f1:
            return
        y0, y1 = lo * S, f1 * S
        bb = (bay[0], bay[1], z0 - bay_d, z0)
        cube(p, bay[0], bay[1], y0, y1, z0 - bay_d, z0, CREAM,
             skip=("back", "top") + (("bottom",) if lo > 1 else ()), bottom=STONE)
        p.solids.append((bay[0], bay[1], y0, y1, z0 - bay_d, z0))
        cap(r, bay[0], bay[1], y1, z0 - bay_d, z0, CREAM)  # the bay's top, until the next run stands on it
        for n in range(lo, f1):
            panel(p, bb, "front", bay[0] + 0.14, bay[1] - 0.14, n * S + 0.38, n * S + 1.26, GLASS_D, BLUE)
            panel(p, bb, "left", z0 - bay_d + 0.1, z0 - 0.06, n * S + 0.38, n * S + 1.26, GLASS_D, BLUE)
            panel(p, bb, "right", z0 - bay_d + 0.1, z0 - 0.06, n * S + 0.38, n * S + 1.26, GLASS_D, BLUE)

    def base(p, r):
        floors(p, r, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.0, 0.8, leaf=CREAM, frame=CREAM)
        canopy(p, b, bay[0], bay[1], st.head, bay_d + 0.08, c=CREAM, edge=TERRACOTTA)
        step(p, b, 0.0, 1.1)
        for sx in (-1, 1):
            planter(p, sx * 1.35 - 0.4, sx * 1.35 + 0.4, -3.85, -3.4, FC_TOP, edge=TERRACOTTA)
            shrub(p, sx * 1.35, -3.62, FC_TOP + 0.3, 0.28, seed=21 + sx)
        bay_run(p, r, 0, FLOORS[lot][0])

    def facade(p, r, f0, f1):
        if f0 > 0:
            bay_run(p, r, f0, f1)

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

    def base(p, r):
        floors(p, r, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.0, 0.85)
        canopy(p, b, -0.6, 0.6, st.head, 0.6, c=TERRACOTTA, edge=CREAM)
        step(p, b, 0.0, 1.0)
        planter(p, 0.9, 2.75, -2.85, -2.4, FC_TOP, edge=TERRACOTTA)
        for i, x in enumerate((1.3, 1.85, 2.4)):
            shrub(p, x, -2.62, FC_TOP + 0.3, 0.27, seed=31 + i)
        tree(p, -2.3, -2.45, FC_TOP, h=1.9, r=0.5, seed=3)

    def facade(p, r, f0, f1):
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

    def base(p, r):
        floors(p, r, b, st, 0, FLOORS[lot][0])
        door(p, b, "front", 0.0, 0.7, leaf=SLATE)
        canopy(p, b, -0.55, 0.55, st.head, 0.5)
        step(p, b, 0.0, 0.8)
        for sx in (-1, 1):
            tree(p, sx * 2.45, -2.45, FC_TOP, h=1.4, r=0.42, seed=50 + sx)

    def facade(p, r, f0, f1):
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

    def base(p, r):
        lobby(p, b, st, columns=(-1.3, 1.3), canopy_w=0.6)
        floors(p, r, b, st, 0, FLOORS[lot][0], body_from=S)
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

    def base(p, r):
        lobby(p, b, st, inset=0.4, columns=(-1.35, 1.35), glass=BLUE_PALE, canopy_c=STONE, frame=CHARCOAL,
              canopy_w=0.55)
        floors(p, r, b, st, 0, FLOORS[lot][0], body_from=S)
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

    def base(p, r):
        lobby(p, b, st, columns=(-1.7, 1.7), glass=BLUE_PALE, canopy_c=STONE)
        floors(p, r, b, st, 0, FLOORS[lot][0], body_from=S)
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

    def base(p, r):
        lobby(p, b, st, inset=0.5, columns=(-1.3, 1.3), glass=GLASS, canopy_c=WHITE, frame=SLATE)
        floors(p, r, b, st, 0, FLOORS[lot][0], body_from=S)
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


# --- shops --------------------------------------------------------------------------------------


def shop_tower(slug, lot, st, awning, sign, front_frame, crowns, extra_base=None, extra_facade=None,
               door_u=0.0, body=None, awning_d=0.62, fixtures=None) -> list[Part]:
    """A shop with flats above: a colourful shopfront, awning and sign at street level."""
    b = body or BODIES[lot]
    x0, x1, z0, z1 = b

    def base(p, r):
        floors(p, r, b, st, 0, FLOORS["shop"][0])
        # the shop window stands well inside the awning ends
        shopfront(p, b, x0 + 0.18, x1 - 0.18, front_frame, door_u)
        sign_board(p, b, x0 + 0.2, x1 - 0.2, st.head + GAP, SIGN_TOP, sign[0], sign[1])
        stripes = min(9, int((x1 - x0) / 0.62) | 1)
        striped_awning(p, x0 + 0.1, x1 - 0.1, 1.18, 0.92, awning_d, awning, stripes, at=(0.0, 0.0, z0))
        if extra_base:
            extra_base(p)

    return tower(slug, lot, st, FLOORS["shop"], base, extra_facade, crowns, body=b, fixtures=fixtures)


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
            water_tank(p, 0.8, 2.0, y, r=0.4, h=0.8, legs=0.3)
        return draw

    def false_front(p, y):
        stepped_front(p, ((1.5, 0.35), (0.85, 0.65)), y + 0.3, z0 - BAND_D - 0.02, 0.22, WHITE, WHITE)

    return shop_tower("shop-narrow-a", lot, st, (YELLOW, WHITE), (YELLOW, SLATE), CHARCOAL,
                      [crown(k) for k in range(5)], door_u=0.95, fixtures={4: false_front})


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

    def flower_boxes(p, r, f0, f1):
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
            stair_hut(p, 0.95, 2.5, y, h=0.9, wall=BLUE_PALE, cap=NAVY)
        return draw

    def gable(p, y):
        stepped_front(p, ((1.6, 0.3), (1.1, 0.6), (0.6, 0.9)), y + 0.3, z0 - BAND_D - 0.02, 0.24, WHITE, NAVY)

    return shop_tower("shop-narrow-b", lot, st, (GREEN, WHITE), (WHITE, GREEN_DARK), SLATE,
                      [crown(k) for k in range(5)], extra_facade=flower_boxes, door_u=-1.0,
                      fixtures={4: gable})


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


# --- Green twins: the "Green the Rooftops" city-changer ------------------------------------------
#
# While rooftopGarden is owned, a home or shop parcel shows <prop>Green instead of <prop> (a prop
# swap; Ben approved it 2026-10-02). A twin is built by the original's builder with GARDEN set, so
# only the roofs differ: its blueprint uses the original's storeys pieces and its own roof pieces,
# named <slug>-green-<k>-roof.

GARDEN: dict = {"style": None}
GARDEN_IN = 0.32  # a garden keeps this far inside the wall line: clear of every parapet and cornice
GARDEN_H = 1.15  # the tallest thing in a roof garden, above the roof
GREEN_RISE = 1.2  # a twin's stage may stand this much above the original's (lead), checked per stage


def green_twin(make, style: dict):
    """The builder of a prop's Green twin: the original's builder run with a garden on every roof."""

    def build() -> list[tuple[Stage, Stage]]:
        GARDEN["style"] = style
        try:
            stages = make()
        finally:
            GARDEN["style"] = None
        for _, roof in stages:
            slug, n, _ = roof.name.rsplit("-", 2)
            roof.name = f"{slug}-green-{n}-roof"
        return stages

    return build


def low_seat(p: Part, x, z, y, length=0.9) -> None:
    """A backless timber seat, 0.3 tall: the only seating a low roof can take."""
    cube(p, x - length / 2, x + length / 2, y, y + 0.3, z - 0.17, z + 0.17, WOOD, skip=("bottom",))


def pergola(p: Part, x0, x1, z0, z1, y, h=0.95) -> None:
    """A white pergola: four posts, two beams along Z on them and slats across on the beams, every
    member MIN_MEMBER square. Each layer sits on the one below, so no two faces share a plane."""
    m = MIN_MEMBER
    for x in (x0, x1 - m):
        for z in (z0, z1 - m):
            cube(p, x, x + m, y, y + h, z, z + m, WHITE, skip=("bottom", "top"))
        cube(p, x, x + m, y + h, y + h + m, z0, z1, WHITE)
    n = max(2, min(4, int((z1 - z0) / 0.55)))
    for i in range(n):
        z = z0 + (z1 - z0 - m) * (i + 0.5) / n
        cube(p, x0 - 0.06, x1 + 0.06, y + h + m, y + h + 2 * m, z, z + m, WHITE)


def green_roof(p: Part, b, y: float, k: int, last_stage: int, style: dict) -> None:
    """A roof garden for stage k of a tower: two raised lawn beds with a paved path between them,
    and on them what the stage's height allows. Stage 0 (3.38 under the 3.4 floor) takes clipped
    hedges; stage 1 (kept under the early landmarks) takes low shrubs and a seat; any later stage
    takes trees too, and the last stage adds the twin's feature (a pergola or parasols) and a
    bench. Everything stands GARDEN_IN inside the wall line and below GARDEN_H. It is drawn on
    the stage's roof piece, so it leaves when the next stage builds over that roof."""
    x0, x1, z0, z1 = b
    rx0, rx1, rz0, rz1 = x0 + GARDEN_IN, x1 - GARDEN_IN, z0 + GARDEN_IN, z1 - GARDEN_IN
    if k == 0:
        cap = HEIGHT_FLOOR - y - 0.02
    elif k == 1:
        cap = LOW_PLANT
    else:
        cap = GARDEN_H
    last = k == last_stage
    seed = style["seed"] * 10 + k
    bed_h = 0.16
    bed_d = min(1.2, (rz1 - rz0) * 0.36)
    hedge = 0.24 if cap < 0.25 else 0.0  # stage 0's hedges take the outer strip of each bed
    beds = ((rx0, rx1, rz0 + hedge, rz0 + bed_d), (rx0, rx1, rz1 - bed_d, rz1 - hedge))
    for bx0, bx1, bz0, bz1 in beds:
        cube(p, bx0, bx1, y, y + bed_h, bz0, bz1, WOOD, skip=("bottom",), top=GREEN_DARK)
    soil = y + bed_h
    pz0, pz1 = rz0 + bed_d, rz1 - bed_d  # the path: the roof deck shows between the beds
    pzc, xc = (pz0 + pz1) / 2, (rx0 + rx1) / 2
    if cap < 0.25:  # clipped hedges standing on the roof along each bed's outer edge
        cube(p, rx0, rx1, y, y + cap, rz0, rz0 + hedge, GREEN, skip=("bottom",))
        cube(p, rx0, rx1, y, y + cap, rz1 - hedge, rz1, GREEN, skip=("bottom",))
        return
    flip = style["seed"] % 2  # alternate sides, so neighbours in a terrace differ
    for i, (bx0, bx1, bz0, bz1) in enumerate(beds):
        side = (i + flip) % 2
        bzc = (bz0 + bz1) / 2
        tree_x = bx0 + 0.55 if side == 0 else bx1 - 0.55
        shrub_x = bx1 - 0.45 if side == 0 else bx0 + 0.45
        if cap < 1.0:
            shrub(p, tree_x, bzc, soil, r=0.24, seed=seed + i)
            continue
        lean = style.get("lean") and not last
        if i < (1 if lean else style.get("trees", 2)):
            tree(p, tree_x, bzc, soil, h=0.98, r=0.42, seed=seed + i, seg=5)
        if not lean:
            shrub(p, shrub_x, bzc, soil, r=0.3, seed=seed + 5 + i)
    if style.get("trees", 2) > 2 and cap >= 1.0 and (last or not style.get("lean")):
        # a third tree, in the middle of the far bed
        tree(p, xc, (beds[1][2] + beds[1][3]) / 2, soil, h=0.92, r=0.4, seed=seed + 9, seg=5)
    if not last:
        low_seat(p, xc, pzc, y, length=min(0.9, rx1 - rx0 - 0.4))
        return
    if style["feature"] == "pergola":
        pergola(p, rx0 + 0.15, rx1 - 0.15, pz0 + 0.12, pz1 - 0.12, y)
        bench(p, xc, pzc + 0.1, y, length=min(1.1, rx1 - rx0 - 0.5))
    else:
        n = 1 if rx1 - rx0 < 4.0 else 2
        for j in range(n):
            px = xc if n == 1 else rx0 + (rx1 - rx0) * (j + 1) / 3
            parasol(p, px, pzc, y, (YELLOW, WHITE, ORANGE)[(style["seed"] + j) % 3], r=0.5, h=1.1)
            for dz in (-0.42, 0.42):
                cube(p, px - 0.1, px + 0.1, y, y + 0.3, pzc + dz - 0.1, pzc + dz + 0.1, WOOD, skip=("bottom",))


# --- the props and their checks -----------------------------------------------------------------

# Blueprint id -> (lot, builder): the final set, the eleven props the approved 85-lot layout can
# show (56 narrow lots, 29 small) and the Green twins of its homes and shops.
PROPS = {
    "FabricResNarrowA": ("narrow", res_narrow_a),
    "FabricResNarrowB": ("narrow", res_narrow_b),
    "FabricResSmallA": ("small", res_small_a),
    "FabricResSmallB": ("small", res_small_b),
    "FabricOfficeNarrowA": ("narrow", office_narrow_a),
    "FabricOfficeNarrowB": ("narrow", office_narrow_b),
    "FabricOfficeSmallA": ("small", office_small_a),
    "FabricOfficeSmallB": ("small", office_small_b),
    "FabricShopNarrowA": ("narrow", shop_narrow_a),
    "FabricShopNarrowB": ("narrow", shop_narrow_b),
    "FabricShopSmallA": ("small", shop_small_a),
}
# Twin id -> (original, garden style). Neighbours in a terrace get different features and sides;
# "lean" keeps the gardens below the last stage down to beds and one tree (what Ben saw). The
# seeds are the ones Ben saw: they place the trees and pick the parasol colours.
TWINS = {
    "FabricResNarrowAGreen": ("FabricResNarrowA", {"seed": 1, "feature": "pergola", "trees": 2}),
    "FabricResNarrowBGreen": ("FabricResNarrowB", {"seed": 2, "feature": "parasols", "trees": 2}),
    "FabricResSmallAGreen": ("FabricResSmallA", {"seed": 3, "feature": "pergola", "trees": 3, "lean": True}),
    "FabricResSmallBGreen": ("FabricResSmallB", {"seed": 4, "feature": "parasols", "trees": 3}),
    "FabricShopNarrowAGreen": ("FabricShopNarrowA", {"seed": 6, "feature": "parasols", "trees": 1}),
    "FabricShopNarrowBGreen": ("FabricShopNarrowB", {"seed": 7, "feature": "pergola", "trees": 1}),
    "FabricShopSmallAGreen": ("FabricShopSmallA", {"seed": 8, "feature": "parasols", "trees": 2}),
}
for _twin, (_base, _style) in TWINS.items():
    PROPS[_twin] = (PROPS[_base][0], green_twin(PROPS[_base][1], _style))
FORECOURTS = {f"forecourt-{lot}": (lambda lot=lot: forecourt(f"forecourt-{lot}", lot)) for lot in LOTS}


def stage_floors(prop: str) -> tuple[int, ...]:
    return FLOORS["shop"] if prop.startswith("FabricShop") else FLOORS[PROPS[prop][0]]


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


def present(stages, k: int) -> list[Stage]:
    """The pieces stage k is made of: every storeys piece up to k and the roof piece of k alone
    (the blueprint retires each roof when the next stage joins)."""
    return [p for p, _ in stages[: k + 1]] + [stages[k][1]]


def holes(stages) -> list[str]:
    """What retiring a roof would open up. When stage k + 1 joins, the roof piece of stage k
    leaves, and with it the caps that closed the storeys under it. So the next storeys must stand
    exactly on the roof deck (same plan, same height: the walls run on with no step, gap or open
    rim), and every other cap (a pier top, a window head, a bay top) must lie inside one of the
    boxes the next storeys add, where it could not be seen anyway."""
    bad = []
    e = 1e-6
    for k in range(len(stages) - 1):
        roof, nxt = stages[k][1], stages[k + 1][0]
        dx0, dx1, dy, dz0, dz1 = roof.caps[0]
        bx0, bx1, by0, _, bz0, bz1 = nxt.solids[0]
        if max(abs(dx0 - bx0), abs(dx1 - bx1), abs(dz0 - bz0), abs(dz1 - bz1), abs(dy - by0)) > e:
            bad.append(f"stage {k + 1} does not stand on the roof deck of stage {k}: deck x[{dx0:.2f}, {dx1:.2f}] "
                       f"z[{dz0:.2f}, {dz1:.2f}] at {dy:.2f}, body x[{bx0:.2f}, {bx1:.2f}] z[{bz0:.2f}, {bz1:.2f}] "
                       f"from {by0:.2f}")
        for x0, x1, y, z0, z1 in roof.caps:
            if not any(sx0 - e <= x0 and x1 <= sx1 + e and sy0 - e <= y <= sy1 + e and sz0 - e <= z0 and z1 <= sz1 + e
                       for sx0, sx1, sy0, sy1, sz0, sz1 in nxt.solids):
                bad.append(f"retiring the roof of stage {k} leaves a hole at x[{x0:.2f}, {x1:.2f}] "
                           f"z[{z0:.2f}, {z1:.2f}], height {y:.2f}: nothing of stage {k + 1} covers it")
    return bad


def stage_tops(stages) -> list[float]:
    return [max(part.bounds()[1][1] for part in present(stages, k)) for k in range(len(stages))]


def check(prop: str, stages, rods=()) -> list[str]:
    """The contract, the no-hole rule, the face-gap rule and the member rule (`rods`: what cube()
    flagged while the prop was built), per prop. Returns violations."""
    lot = PROPS[prop][0]
    w, d = LOTS[lot]
    bad = []
    fc = forecourt("fc", lot)
    tops = stage_tops(stages)
    for k in range(len(stages)):
        parts = present(stages, k)
        tris = fc.tris + sum(part.tris for part in parts)
        if tris > TRI_BUDGET:
            bad.append(f"stage {k}: {tris} tris > {TRI_BUDGET}")
        for part in stages[k]:
            lo, hi = part.bounds()
            if lo[0] < -w / 2 - 0.01 or hi[0] > w / 2 + 0.01 or lo[2] < -d / 2 - 0.01 or hi[2] > d / 2 + 0.01:
                bad.append(f"stage {k}: {part.name} leaves the {w:g} x {d:g} lot: "
                           f"x[{lo[0]:.2f}, {hi[0]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}]")
        if k == 0 and tops[0] > HEIGHT_FLOOR + 1e-6:
            bad.append(f"stage 0 is {tops[0]:.2f} tall > heightFloor {HEIGHT_FLOOR}")
        if k == 1 and tops[1] > stage_floors(prop)[1] * S + LOW_PLANT + 1e-6:
            bad.append(f"stage 1 is {tops[1]:.2f} tall: only roof plant <= {LOW_PLANT} may stand on it")
        for fight in face_fights([fc] + parts)[:3]:
            bad.append(f"stage {k}: {fight}")
    for rod in sorted(set(rods))[:5]:
        bad.append(f"a member {rod[0]:g} x {rod[1]:g} x {rod[2]:g} is thinner than {MIN_MEMBER} in two dimensions")
    if prop in TWINS:
        for k, (b_top, t_top) in enumerate(zip(stage_tops(PROPS[TWINS[prop][0]][1]()), tops)):
            if t_top > b_top + GREEN_RISE + 1e-6:
                bad.append(f"stage {k}: {t_top:.2f} tall against the original's {b_top:.2f}")
    return bad + holes(stages)


def write_blueprints() -> None:
    os.makedirs(BLUEPRINT_DIR, exist_ok=True)
    for prop, (lot, make) in PROPS.items():
        stages = make()
        pieces = [{"kit": KIT, "model": f"forecourt-{lot}", "pos": [0, 0, 0], "rotY": 0, "stage": 0}]
        for k, (storeys, roof) in enumerate(stages):
            pieces.append({"kit": KIT, "model": storeys.name, "pos": [0, 0, 0], "rotY": 0, "stage": k})
            pieces.append({"kit": KIT, "model": roof.name, "pos": [0, 0, 0], "rotY": 0, "stage": k})
            if k < len(stages) - 1:
                pieces[-1]["untilStage"] = k  # the next stage builds over this roof
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
    parser.add_argument("--write-blueprints", action="store_true", help="also (re)write the 18 fabric blueprints")
    parser.add_argument("--summary", help="write per-stage heights, extents and triangles here (JSON)")
    args = parser.parse_args(argv)
    summary_out: dict = {}

    os.makedirs(args.out, exist_ok=True)
    failures = 0
    pieces: dict = dict(FORECOURTS)
    for prop, (lot, make) in PROPS.items():
        RODS.clear()
        stages = make()
        problems = check(prop, stages, list(RODS))
        fc_tris = forecourt("fc", lot).tris
        tops = stage_tops(stages)
        w, d = LOTS[lot]
        rows = []
        for k in range(len(stages)):
            parts = present(stages, k)
            bounds = [part.bounds() for part in parts]
            rows.append({"height": round(tops[k], 3), "tris": fc_tris + sum(part.tris for part in parts),
                         "x": [round(min(-w / 2, *(lo[0] for lo, _ in bounds)), 3),
                               round(max(w / 2, *(hi[0] for _, hi in bounds)), 3)],
                         "z": [round(min(-d / 2, *(lo[2] for lo, _ in bounds)), 3),
                               round(max(d / 2, *(hi[2] for _, hi in bounds)), 3)]})
        every = [part for pair in stages for part in pair]
        summary_out[prop] = {"lot": lot, "stages": rows,
                             "colours": sorted({"%d,%d,%d" % c for part in every for _, c in part.faces})}
        log(f"{prop}: stage top/tris " + "  ".join(f"{row['height']:.2f}/{row['tris']}" for row in rows))
        for msg in problems:
            log(f"  PROBLEM {prop}: {msg}")
        failures += len(problems)
        for part in every:
            if part.name in pieces:  # a twin's storeys are its original's: one piece, one geometry
                twin_of = pieces[part.name]()
                assert (twin_of.verts, twin_of.faces) == (part.verts, part.faces), f"{part.name} differs in {prop}"
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
