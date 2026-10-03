"""The Metropolis old town (wild land) and Metropolis building sites for the growing city (M12
wave 3), generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/oldtown_kit.py [-- --out <dir>] [--only name,name] [--write-blueprints]

Writes one GLB per piece into assets/kenney3d/oldtown-kit/Models/GLB format/, the folder convention
every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py discover the kit
with no registration step. assets/ is gitignored, so this script is the committed artifact and the
GLBs regenerate from it. The mesh container and the export plumbing come from garden_kit.py, the
geometry helpers from village_extras_kit.py.

`--write-blueprints` also (re)writes the kit's 15 blueprints under
tools/testfit/blueprints/_props/Metropolis/ (OldTownQuarterA-C and their OldTownClumpA-C, the three
old-town singles, the four sites, RevealScaffold and LotHoarding) from blueprints() below. That is
how to regenerate them: never edit a clump by hand, it is its quarter turned four times. Add
`--only <piece>` to skip rebuilding the other GLBs.

Why a custom kit (INTERFACES "M12 wave 3 -- Metropolis", docs/CITY_GROWTH.md sections 2.1 and 4):
- The old town. Metropolis's wild land is the low, worn city the towers replace: surface car parks,
  fenced vacant lots, one- and two-storey brick blocks and billboards. city-kit-commercial is all
  new white offices and glass, and the brick and industrial kits belong to Boomtown (each kit
  belongs to one era), so every old-town piece is generated here.
- Building sites. No City Kit has a tower crane, a concrete frame or pipe scaffold, and Boomtown's
  construction pieces are Boomtown's. Tower cranes on the skyline are the Metropolis frontier's
  signature (CITY_GROWTH 2.3).
- Parked cars. car-kit's cars are 2,000 to 2,500 triangles each (every wheel alone is 332), so a
  car park of a dozen would cost more than a whole district. The cars here are about 60 triangles,
  sized like the street's parked cars as the game shows them (ParkedA-C at scale 1.8, then
  `parked.scale` 0.5 at runtime: about 1.3 x 2.4 studs).

**Units: 1 glTF unit = 1 stud** (blueprints use `"scale": 1.0`), like metro-kit and garden-kit, so
every literal below is directly checkable against the contract sizes.

**The clump contract** (INTERFACES "Fabric data"; geometry fixed by the lead with the tools
engineer, 2026-10-02): a clump is four copies of one quarter design turned 0, 90, 180 and 270
degrees about the clump origin. A quarter piece is authored in the clump's frame with all of its
content inside the local (+X, +Z) quadrant, x and z in 0 .. 6.5 (a 6.5 x 6.5 footprint centred on
(3.25, 3.25)), so the four turned copies meet at the axes with no gap and a clump is 13 x 13: it
fits the 13 studs between the pavements of a pitch-28 city block, and clumps on the 14-stud grid
keep a stud between them. Ground (asphalt, earth, paving) runs to the axes and meets the turned
copy's edge to edge, never overlapping, so the four read as one surface; walls, kerbs and fences
are laid out so that they continue across the joins.

Every other piece has its origin at its bottom centre and its front on -Z; the site pieces that
are lot-sized (site-ground-*, frame-*) are authored in the lot frame (origin at the lot centre on
the ground, the street on -Z), so a blueprint places them at [0, 0, 0].

Colours are texels of the City Kits' colormap.png (commercial unless noted; the four kits share one
palette), so the pieces sit in the Metropolis palette. The exception is the weed and grass greens,
which match the park strips' (104, 146, 92) (`road.tiles.parkStrips` in CityDressing.json) rather
than the kit's mint, so neglected ground and Ben's park strips read as one green. The old town is
the dark, warm half of the palette (brick, asphalt, earth, iron) and the new city the light, cool
half (white walls, blue glass, mint), so redevelopment reads as a change of colour from the tycoon
camera. Materials are plain colour factors with no texture, written linear like garden-kit's;
merge_stages.py routes them through palette.py (not an sRGB-factor kit).

Art rules, matching the kits: flat shading, axis-aligned boxes and square-cut members, faceted
solids of revolution, chunky toy proportions (a storey is 1.6 studs, the kit's at scale 4).

**Every face belongs to a solid.** Roblox culls back faces, so nothing is a lone sheet. A solid is
closed, or open only where it rests on the ground or against another solid (the underside of a
slab, the back of a window box against its wall, the ends of a lattice brace buried in a chord),
where nobody can look in. The one exception is a ground decal (gravel, weeds, a puddle): a top face
only, DECAL_LIFT above what it lies on.

**Two rules from Studio (lead, 2026-10-02):**
- Any two parallel faces that overlap in plan stand at least 0.05 studs apart (MIN_GAP): Boomtown's
  back lanes flickered at a distance with 0.02 to 0.03. So a decal is 0.05 above its ground, a bay
  line 0.05 above the asphalt, a window 0.05 proud of its wall, a bar 0.05 proud of its sign, and
  every ground plate's top is 0.05 above the plot base.
- Nothing seen from the tycoon camera is thinner than 0.1 studs (MIN_MEMBER): wires, braces, rails,
  rungs, ropes and slab edges are all at least that, or they shimmer in game.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from garden_kit import REPO_ROOT, Part, build_object, export  # noqa: E402
from village_extras_kit import blotch, cross, face_out, lathe, place, sub, unit  # noqa: E402

import bpy  # noqa: E402

KIT = "oldtown-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

Rgb = tuple[int, int, int]
Vec = tuple[float, float, float]

# --- palette: sRGB texels of city-kit-commercial's colormap.png unless noted ------------------------
WHITE = (255, 255, 255)
CREAM = (253, 228, 199)
TAN = (242, 191, 153)
PEACH = (250, 174, 138)
APRICOT = (241, 151, 108)
ORANGE = (255, 126, 68)
YELLOW = (255, 192, 68)
YELLOW_DEEP = (255, 171, 66)  # city-kit-roads' yellow ramp: a skip's inside, a crane's shade
RED = (207, 83, 79)
BLUE = (103, 148, 217)
BLUE_PALE = (181, 204, 236)  # city-kit-industrial
GLASS = (208, 232, 255)
MINT = (97, 203, 139)
MINT_DARK = (61, 167, 122)
# Brick. BRICK and BRICK_ROSE are commercial; BRICK_BROWN and BRICK_DARK are suburban (the brick
# and timber ramp's two darkest steps).
BRICK = (176, 96, 65)
BRICK_ROSE = (205, 114, 90)
BRICK_BROWN = (153, 90, 65)
BRICK_DARK = (131, 84, 66)
# Earth. city-kit-industrial's brown swatch reads as terracotta on the dark grey plot, so bare ground
# is BRICK_DARK's value and the industrial brown is only a patch on it.
EARTH_DARK = BRICK_DARK
EARTH = (159, 106, 82)
# Stone, concrete and steel: the kit's grey-blue ramp, light to dark.
PALE = (236, 236, 243)  # city-kit-industrial: the white wall ramp's shaded end
STONE_LIGHT = (179, 188, 225)  # city-kit-suburban
STONE = (160, 168, 201)
TRIM = (142, 149, 179)
STONE_DARK = (134, 139, 161)
SLATE_BLUE = (115, 126, 155)  # city-kit-industrial
GREY = (102, 107, 128)
SLATE = (81, 85, 102)
IRON = (58, 60, 63)
DARK = (56, 56, 61)
# Asphalt: the kit's dark ramp, a step lighter than the streets' (60, 62, 70), worn.
ASPHALT = (70, 70, 80)
# Weeds and patchy grass: NOT colormap texels (see the module docstring).
WEED = (104, 146, 92)
WEED_DARK = (86, 128, 80)


# --- geometry helpers (glTF space, studs) ---------------------------------------------------------

SIDES = ("top", "bottom", "front", "back", "left", "right")


def block(p: Part, x0, x1, y0, y1, z0, z1, colour: Rgb, skip=("bottom",), **paint) -> None:
    """An axis-aligned box. `skip` leaves faces out (by default the underside, which rests on the
    ground or on another piece); `paint` overrides one face's colour: top, bottom, front (-Z),
    back (+Z), left (-X), right (+X)."""
    c = {k: paint.get(k, colour) for k in SIDES}
    faces = {
        "top": ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0.0, 1.0, 0.0)),
        "bottom": ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0.0, -1.0, 0.0)),
        "front": ([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], (0.0, 0.0, -1.0)),
        "back": ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0.0, 0.0, 1.0)),
        "left": ([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1.0, 0.0, 0.0)),
        "right": ([(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)], (1.0, 0.0, 0.0)),
    }
    for side in SIDES:
        if side not in skip:
            points, normal = faces[side]
            face_out(p, points, c[side], normal)


def rod(p: Part, a: Vec, b: Vec, w: float, colour: Rgb, sides: int = 4, caps: bool = False,
        up: Vec = (0.0, 1.0, 0.0)) -> None:
    """A straight member from a to b, `w` across its flats, `sides` faces round. Without `caps` its
    ends are open: for lattice braces, rails and wires whose ends bury in a chord or a post."""
    d = unit(sub(b, a))
    s = cross(d, up)
    if s[0] ** 2 + s[1] ** 2 + s[2] ** 2 < 1e-12:
        s = cross(d, (0.0, 0.0, 1.0))
    s = unit(s)
    u = cross(s, d)
    radius = w / 2 / math.cos(math.pi / sides)
    angles = [math.pi / sides + 2 * math.pi * k / sides for k in range(sides)]

    def ring(c: Vec):
        return [tuple(c[i] + radius * (s[i] * math.cos(t) + u[i] * math.sin(t)) for i in range(3)) for t in angles]

    ra, rb = ring(a), ring(b)
    for k in range(sides):
        n = (k + 1) % sides
        tm = (angles[k] + angles[n]) / 2 + (math.pi if n == 0 else 0.0)
        out = tuple(s[i] * math.cos(tm) + u[i] * math.sin(tm) for i in range(3))
        face_out(p, [ra[k], ra[n], rb[n], rb[k]], colour, out)
    if caps:
        face_out(p, ra, colour, tuple(-c for c in d))
        face_out(p, rb, colour, d)


def plate(p: Part, outline, y0: float, y1: float, colour: Rgb, top: Rgb | None = None) -> None:
    """A flat solid over an outline [(x, z)] that is star-shaped about its centroid: a top and a
    skirt, no underside."""
    cx = sum(x for x, _ in outline) / len(outline)
    cz = sum(z for _, z in outline) / len(outline)
    face_out(p, [(x, y1, z) for x, z in outline], top or colour, (0.0, 1.0, 0.0))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        (xa, za), (xb, zb) = outline[i], outline[j]
        face_out(p, [(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], colour,
                 ((xa + xb) / 2 - cx, 0.0, (za + zb) / 2 - cz))


def chunk(p: Part, centre: Vec, size: Vec, yaw: float, tilt: float, colour: Rgb, top: Rgb | None = None) -> None:
    """A loose box (a brick, a broken slab) tilted `tilt` degrees about its own X, then turned `yaw`
    about Y, with its centre at `centre`."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    ct, st = math.cos(math.radians(tilt)), math.sin(math.radians(tilt))
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    corners = []
    for y in (-hy, hy):
        for x, z in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)):
            y1, z1 = y * ct - z * st, y * st + z * ct
            corners.append((centre[0] + x * cy + z1 * sy, centre[1] + y1, centre[2] - x * sy + z1 * cy))
    p.hexa(corners, colour, top=top or colour)


def on_wall(p: Part, wall, a0: float, a1: float, y0: float, y1: float, proud: float, colour: Rgb,
            edge: Rgb | None = None) -> None:
    """A box standing `proud` out of a wall: a window, a door, a sign. `wall` is (axis, plane,
    facing): ("z", z, -1) is a wall in the plane z facing -Z with a measured along X; ("x", x, 1) a
    wall in the plane x facing +X with a measured along Z. The face against the wall and the
    underside are left out; `edge` colours the box's rim (its top and sides)."""
    axis, plane, facing = wall
    lo, hi = sorted((plane - facing * 0.02, plane + facing * proud))
    rim = edge or colour
    if axis == "z":
        outer, inner = ("front", "back") if facing < 0 else ("back", "front")
        block(p, a0, a1, y0, y1, lo, hi, rim, skip=("bottom", inner), **{outer: colour})
    else:
        outer, inner = ("left", "right") if facing < 0 else ("right", "left")
        block(p, lo, hi, y0, y1, a0, a1, rim, skip=("bottom", inner), **{outer: colour})


def decal(p: Part, outline, y: float, colour: Rgb) -> None:
    """A flat patch (gravel, weeds, a puddle) lying DECAL_LIFT above the ground under it: only its
    top face, because nothing can look at it from underneath and its rim would be under a tenth of a
    stud tall."""
    face_out(p, [(x, y, z) for x, z in outline], colour, (0.0, 1.0, 0.0))


def lattice(p: Part, axis: str, plane: float, a0: float, a1: float, y0: float, y1: float, pitch: float,
            w: float, colour: Rgb) -> None:
    """A diamond lattice of wire in a vertical plane (x = plane for axis "x", z = plane for axis
    "z"), from a0 to a1 along the run and y0 to y1: two families of three-sided rods `w` across at
    45 degrees, `pitch` apart. Line k of each family crosses a = a0 at y0 + k * pitch, so two runs
    that meet at a0 mirror into whole diamonds. The rods are solids that pass through each other,
    so their crossings have no coplanar faces to fight."""
    length, height = a1 - a0, y1 - y0

    def at(u: float, v: float) -> Vec:
        return (plane, y0 + v, a0 + u) if axis == "x" else (a0 + u, y0 + v, plane)

    for k in range(math.floor(-height / pitch) + 1, math.floor(length / pitch) + 1):
        c = k * pitch  # rising: v = u - c
        u0, u1 = max(0.0, c), min(length, c + height)
        if u1 - u0 > 0.05:
            rod(p, at(u0, u0 - c), at(u1, u1 - c), w, colour, sides=3)
    for k in range(1, math.floor((length + height) / pitch) + 1):
        c = k * pitch  # falling: v = c - u
        u0, u1 = max(0.0, c - height), min(length, c)
        if u1 - u0 > 0.05:
            rod(p, at(u0, c - u0), at(u1, c - u1), w, colour, sides=3)


# --- the clump frame -----------------------------------------------------------------------------

MIN_GAP = 0.05  # parallel faces overlapping in plan stand at least this far apart
MIN_MEMBER = 0.1  # nothing seen from the tycoon camera is thinner
DECAL_LIFT = MIN_GAP

EDGE = 6.5  # a quarter's outer edges, x = EDGE and z = EDGE; its inner edges are the clump axes
GROUND_TO = 6.49  # flat ground stops a hair inside the edge, under the kerb or fence that closes it


# --- A: the surface car park ---------------------------------------------------------------------
#
# Plan of one quarter (the clump repeats it four times round its centre): a kerb along both outer
# edges, a row of two bays inside each, a raised corner island with the pay booth and the light,
# and the open aisle toward the clump centre with a painted arrow. The rows stop GAP short of the
# axes, so every side of the clump has one entrance, 2 x GAP wide, at its middle, and the four
# arrows run round the centre as a one-way loop.

LOT_TOP = 0.05
KERB_TOP = 0.14
KERB_IN = 6.3  # the kerb's inner face
BAY_W = 1.55
BAY_D = 2.4
ROW_IN = KERB_IN - BAY_D  # 3.9: the aisle edge of both rows
GAP = 0.8
ISLAND = 4.1
LINE_TOP = LOT_TOP + MIN_GAP
# A bay's centre is BAY_W * (k + 0.5) past GAP along its row and BAY_D / 2 in from ROW_IN: where the
# quarter blueprint parks its cars (along Z in the +Z row, along X in the +X row).


def make_carpark_quarter() -> Part:
    """One quarter of a surface car park, 6.5 studs square from the clump axes: worn asphalt, a
    pale kerb on the two outer edges broken for the entrance, four painted bays, the corner island
    the booth and the light stand on, and a direction arrow in the aisle."""
    p = Part("carpark-quarter")
    block(p, 0.0, GROUND_TO, 0.0, LOT_TOP, 0.0, GROUND_TO, ASPHALT)
    # kerbs, from the entrance to the island
    block(p, GAP, ISLAND, 0.0, KERB_TOP, KERB_IN, EDGE, TRIM, top=STONE)
    block(p, KERB_IN, EDGE, 0.0, KERB_TOP, GAP, ISLAND, TRIM, top=STONE)
    block(p, ISLAND, EDGE, 0.0, KERB_TOP, ISLAND, EDGE, STONE_DARK, top=TRIM)
    # bay lines: the separators of each row and the line along the aisle edge
    half = 0.05
    for k in range(3):
        a = GAP + BAY_W * k
        block(p, a - half, a + half, 0.0, LINE_TOP, ROW_IN, KERB_IN, WHITE)
        # starts a line's width in, so the two rows' last lines never overlap at the inner corner
        block(p, ROW_IN + 2 * half, KERB_IN, 0.0, LINE_TOP, a - half, a + half, WHITE)
    # the arrow, pointing -X along the +Z row's aisle
    block(p, 1.95, 3.05, 0.0, LINE_TOP, 2.7, 3.0, WHITE)
    plate(p, [(1.2, 2.85), (1.95, 2.37), (1.95, 3.33)], 0.0, LINE_TOP, WHITE)
    return p


def car(name: str, body: Rgb, roof: Rgb, kind: str) -> Part:
    """A parked car, 1.28 studs wide (wheels) and 2.22 long, front -Z: a body, a glass cabin with a roof in
    the body colour, and four dark wheels standing a little proud. `kind` sets the cabin: a
    hatchback's runs to the back, a saloon's stops short of a boot, a van's is tall and long."""
    p = Part(name)
    hw, hl = 0.6, 1.1
    for sx in (-1, 1):
        for z in (-0.7, 0.68):
            x0, x1 = sorted((sx * 0.46, sx * 0.64))
            block(p, x0, x1, 0.0, 0.38, z - 0.2, z + 0.2, IRON)
    top = 0.6 if kind != "van" else 0.52
    block(p, -hw, hw, 0.14, top, -hl, hl, body)
    if kind == "hatch":
        z0, z1, y1, inset = -0.35, 0.98, 1.0, 0.07
    elif kind == "saloon":
        z0, z1, y1, inset = -0.42, 0.55, 0.98, 0.08
    else:
        z0, z1, y1, inset = -0.62, 1.08, 1.22, 0.04
    lean = 0.22 if kind != "van" else 0.1
    p.frustum(-hw + 0.04, hw - 0.04, z0, z1, top, -hw + 0.04 + inset, hw - 0.04 - inset, z0 + lean, z1 - 0.06, y1,
              SLATE, top=roof, bottom=body)
    # headlights and the grille band: what tells the front from the back
    block(p, -0.5, 0.5, 0.3, 0.42, -hl - MIN_GAP, -hl + 0.01, PALE, skip=("bottom", "back"))
    return p


def make_car_a() -> Part:
    return car("car-a", RED, RED, "hatch")


def make_car_b() -> Part:
    return car("car-b", PALE, WHITE, "saloon")


def make_car_c() -> Part:
    return car("car-c", BLUE, BLUE, "van")


def make_pay_booth() -> Part:
    """A car-park attendant's booth, 0.96 x 0.86 studs and 1.34 tall, front -Z: a cream base, a
    glass band all round, a dark flat roof with an overhang and a red stripe under the glass."""
    p = Part("pay-booth")
    hx, hz = 0.42, 0.37
    block(p, -hx, hx, 0.0, 0.55, -hz, hz, CREAM)
    block(p, -hx - 0.01, hx + 0.01, 0.55, 0.63, -hz - 0.01, hz + 0.01, RED, skip=("bottom", "top"))
    block(p, -hx, hx, 0.63, 1.12, -hz, hz, BLUE_PALE, skip=("bottom", "top"))
    block(p, -0.48, 0.48, 1.12, 1.34, -0.43, 0.43, SLATE, top=GREY)
    return p


def make_carpark_light() -> Part:
    """A car-park light, 3.42 studs tall and 1.58 across its arm: a concrete foot, a slate pole and a
    crossarm carrying two flat lamp heads with pale undersides."""
    p = Part("carpark-light")
    block(p, -0.17, 0.17, 0.0, 0.22, -0.17, 0.17, STONE_DARK, top=STONE)
    lathe(p, [(0.09, 0.22), (0.07, 3.3)], [GREY], seg=6, phase=math.pi / 6)
    block(p, -0.7, 0.7, 3.28, 3.38, -0.05, 0.05, GREY)
    for sx in (-1, 1):
        block(p, sx * 0.62 - 0.17, sx * 0.62 + 0.17, 3.2, 3.42, -0.13, 0.13, SLATE, skip=(), bottom=CREAM)
    return p


# --- B: the fenced vacant lot --------------------------------------------------------------------
#
# A demolished building's lot. Each quarter's corner of the old ground floor runs to the axes, so
# the four make one concrete slab at the clump centre, ringed by stubs of its brick walls; round it
# is bare earth with weeds and gravel, and a chain-link fence closes the outer edges. The fence's
# end posts stand half a span from the axes, so posts are evenly spaced across the joins too.

FOUND = 3.65  # the slab's outer edge
FENCE_LINE = 6.37
FENCE_H = 1.25
FENCE_POSTS = 2


def fence_posts():
    span = FENCE_LINE / (FENCE_POSTS + 0.5)
    return [span * (k + 0.5) for k in range(FENCE_POSTS)]


def make_lot_quarter() -> Part:
    """The ground of one vacant-lot quarter, to the axes: bare earth with a gravel patch and two
    patches of weeds and a puddle, the corner of the old concrete floor slab with a damp stain and a
    weedy crack on it, the broken brick stubs of its outer walls, a little heap of their bricks,
    and two clumps of weeds by the fence. 1.0 studs at the tallest stub. The slab and the wall
    stubs run to the axes, so the four quarters make one ruined ground floor."""
    p = Part("lot-quarter")
    rng = random.Random(311)
    earth, slab = MIN_GAP, 0.12
    block(p, 0.0, GROUND_TO, 0.0, earth, 0.0, GROUND_TO, EARTH_DARK)
    on_earth, on_slab = earth + DECAL_LIFT, slab + DECAL_LIFT
    decal(p, blotch(rng, 5.05, 2.15, 1.0, 1.55, points=7), on_earth, STONE_DARK)
    decal(p, blotch(rng, 1.75, 5.2, 1.55, 0.8, points=7), on_earth, WEED)
    decal(p, blotch(rng, 5.3, 5.3, 0.95, 0.85, points=6), on_earth, WEED_DARK)
    decal(p, blotch(rng, 4.6, 0.7, 0.72, 0.45, points=8), on_earth, BLUE_PALE)
    block(p, 0.0, FOUND, 0.0, slab, 0.0, FOUND, TRIM, top=STONE)
    decal(p, blotch(rng, 1.5, 1.2, 0.75, 0.5, points=6), on_slab, STONE_DARK)
    decal(p, blotch(rng, 0.45, 2.75, 0.45, 0.3, points=5), on_slab, WEED_DARK)
    # the old walls: stubs of different heights with the breaks between them
    t = 0.24
    for a0, a1, h in ((0.0, 1.0, 0.95), (1.0, 1.65, 0.42), (2.5, FOUND, 0.7)):
        block(p, a0, a1, 0.0, h, FOUND - t, FOUND, BRICK, top=BRICK_ROSE)
    for a0, a1, h in ((0.0, 0.45, 0.3), (1.3, FOUND - t, 1.0)):
        block(p, FOUND - t, FOUND, 0.0, h, a0, a1, BRICK, top=BRICK_ROSE)
    # bricks fallen from the gap in the wall, on the slab
    for centre, size, yaw, tilt, side, top in (
        ((2.05, 0.22, 3.0), (0.55, 0.2, 0.36), 20, 12, BRICK, BRICK_ROSE),
        ((2.5, 0.2, 2.5), (0.5, 0.16, 0.4), 65, -10, STONE, STONE_LIGHT),
        ((1.7, 0.18, 2.5), (0.4, 0.14, 0.28), 140, 8, BRICK_BROWN, BRICK),
    ):
        chunk(p, centre, size, yaw, tilt, side, top)
    # weeds by the fence
    for x, z, r, seed in ((5.85, 3.35, 0.34, 313), (2.95, 5.8, 0.3, 317)):
        p.blob((x, 0.1 * r, z), (r, r * 0.95, r * 0.9), WEED_DARK, seg=5, rings=1, cut=-0.1, jitter=0.15, seed=seed)
    return p


def make_chainlink_quarter() -> Part:
    """The quarter's chain-link fence along its two outer edges, 1.25 studs tall (1.3 at the corner
    post): galvanised posts, a top rail, and the mesh as a coarse diamond lattice of wire a tenth of
    a stud across, so the lot shows through. (A finer lattice of 0.05 wire read better in renders
    but would shimmer in game; see MIN_MEMBER.)
    The lattice's diamonds meet across the clump axes. Origin at the clump centre, like the
    ground."""
    p = Part("chainlink-quarter")
    e = FENCE_LINE
    for a in fence_posts():
        block(p, e - 0.05, e + 0.05, 0.0, FENCE_H, a - 0.05, a + 0.05, GREY, top=STONE)
        block(p, a - 0.05, a + 0.05, 0.0, FENCE_H, e - 0.05, e + 0.05, GREY, top=STONE)
    block(p, e - 0.06, e + 0.06, 0.0, FENCE_H + 0.05, e - 0.06, e + 0.06, GREY, top=STONE)
    rail = FENCE_H - 0.05
    rod(p, (e, rail, 0.0), (e, rail, e), MIN_MEMBER, STONE)
    rod(p, (0.0, rail, e), (e, rail, e), MIN_MEMBER, STONE)
    pitch = 1.0
    lattice(p, "x", e, 0.08, e, 0.1, rail, pitch, MIN_MEMBER, STONE_DARK)
    lattice(p, "z", e, 0.08, e, 0.1, rail, pitch, MIN_MEMBER, STONE_DARK)
    return p


def make_skip() -> Part:
    """An open builder's skip, 1.9 studs long, 1.08 wide and 0.85 tall at its load: a yellow steel
    body with sloped ends, a darker inside, lifting lugs, and a heap of rubble showing over the
    rim."""
    p = Part("skip")
    bx, bz, tx, tz, h, wall = 0.62, 0.42, 0.95, 0.54, 0.76, MIN_MEMBER
    lo = [(-bx, 0.0, -bz), (bx, 0.0, -bz), (bx, 0.0, bz), (-bx, 0.0, bz)]
    hi = [(-tx, h, -tz), (tx, h, -tz), (tx, h, tz), (-tx, h, tz)]
    ix, iz = tx - wall, tz - wall
    ins = [(-ix, h, -iz), (ix, h, -iz), (ix, h, iz), (-ix, h, iz)]
    fill_y = h - 0.2
    fill = [(x * 0.94, fill_y, z * 0.94) for x, _, z in ins]
    for k in range(4):
        n = (k + 1) % 4
        mid = ((lo[k][0] + lo[n][0]) / 2, 0.0, (lo[k][2] + lo[n][2]) / 2)
        face_out(p, [lo[k], lo[n], hi[n], hi[k]], YELLOW, (mid[0], 0.0, mid[2]))
        face_out(p, [hi[k], hi[n], ins[n], ins[k]], ORANGE, (0.0, 1.0, 0.0))
        face_out(p, [ins[k], ins[n], fill[n], fill[k]], YELLOW_DEEP, (-mid[0], 0.0, -mid[2]))
    face_out(p, fill, EARTH, (0.0, 1.0, 0.0))
    for sx in (-1, 1):
        block(p, sx * 0.75 - 0.08, sx * 0.75 + 0.08, 0.32, 0.46, -0.5, 0.5, ORANGE, skip=("bottom",))
    rng = random.Random(331)
    for x, z, s, c in ((-0.45, -0.1, 0.34, BRICK), (0.05, 0.15, 0.42, STONE), (0.5, -0.12, 0.3, BRICK_ROSE)):
        chunk(p, (x, fill_y + s * 0.3, z), (s, s * 0.6, s * 0.8), rng.uniform(0, 90), rng.uniform(-20, 20), c)
    return p


def make_rubble() -> Part:
    """A heap of demolition rubble, 1.75 x 1.74 studs and 0.96 tall: a low dusty mound with broken
    brick and concrete on it and a bent bar of rebar."""
    p = Part("rubble")
    lathe(p, [(0.9, 0.0), (0.6, 0.28), (0.0, 0.5)], [STONE_DARK, TRIM], seg=7, phase=0.3)
    rng = random.Random(337)
    pieces = (
        ((-0.38, 0.32, -0.1), (0.5, 0.18, 0.36), BRICK, BRICK_ROSE),
        ((0.3, 0.3, 0.22), (0.62, 0.12, 0.44), STONE, STONE_LIGHT),
        ((0.1, 0.5, -0.25), (0.34, 0.2, 0.26), BRICK_ROSE, BRICK_ROSE),
        ((-0.15, 0.24, 0.45), (0.42, 0.14, 0.3), BRICK_BROWN, BRICK),
        ((0.55, 0.16, -0.45), (0.36, 0.14, 0.3), STONE_DARK, STONE),
        ((-0.62, 0.12, 0.38), (0.3, 0.14, 0.22), BRICK, BRICK_ROSE),
    )
    for centre, size, side, top in pieces:
        chunk(p, centre, size, rng.uniform(0, 180), rng.uniform(-25, 25), side, top)
    rod(p, (-0.05, 0.3, 0.05), (0.18, 0.95, -0.12), MIN_MEMBER, BRICK_BROWN)
    return p


# --- C: the old brick block ----------------------------------------------------------------------
#
# Plan of one quarter: two buildings along the +Z street and a paved yard behind them toward the
# clump centre. A, on the corner, is two storeys with a shop wrapping the corner and a fire escape on
# its back; B, beside it, is a one-storey shop with a water tank on its flat roof and A's party wall
# rising over it with a ghost sign. Turned four times they make a pinwheel block: on each side of
# the clump a corner building, a shop, a yard wall with its gate and the next corner building's
# flank; the yards meet in the middle as a back court. Everything stays under 3.6 studs, so the
# first landmarks of the era (3.3 to 3.6) stand above the old town (lead's ruling, 2026-10-02).
# Facades stand 0.45 back from the outer edges, so the awnings and cornices stay inside 6.5.

STOREY = 1.6
FACADE = 6.05  # the street faces of both buildings (z) and of A's flank (x)
A_X0, A_Z0 = 3.2, 2.1
B_X0, B_Z0 = 0.07, 2.6  # B's cornice runs to the axis, where the turned copy's yard wall meets it
A_TOP = 2 * STOREY  # 3.2
B_TOP = STOREY  # 1.6
CAP = 0.15  # the cornice slab that carries the roof
PROUD = MIN_GAP  # windows, doors and painted panels stand this far off their wall


def window_row(p: Part, wall, centres, y0: float, y1: float, half: float = 0.27) -> None:
    for a in centres:
        on_wall(p, wall, a - half, a + half, y0, y1, PROUD, DARK, edge=CREAM)


def shop_window(p: Part, wall, a0: float, a1: float) -> None:
    """A dim shop window in two cream-framed panes with a tenth of a stud of wall between them: one
    pane this wide read as a garage door, and a mullion laid over it would sit too close to the
    glass."""
    mid = (a0 + a1) / 2
    for b0, b1 in ((a0, mid - 0.05), (mid + 0.05, a1)):
        on_wall(p, wall, b0, b1, 0.15, 1.0, PROUD, SLATE_BLUE, edge=CREAM)


def shopfront(p: Part, wall, a0: float, a1: float, door: float, awning: Rgb, sign: Rgb) -> None:
    """A faded shopfront on a street wall from a0 to a1: a dim shop window, a door, a sign board
    over them and a flat awning, in muted colours."""
    axis, plane, facing = wall
    if door < (a0 + a1) / 2:
        shop_window(p, wall, door + 0.3, a1)
    else:
        shop_window(p, wall, a0, door - 0.3)
    on_wall(p, wall, door - 0.24, door + 0.24, 0.0, 1.02, 0.07, SLATE)
    on_wall(p, wall, a0 - 0.05, a1 + 0.05, 1.08, 1.4, 0.06, sign, edge=CREAM)
    depth = 0.4
    y0, y1 = 0.98, 1.08
    if axis == "z":
        z0, z1 = sorted((plane, plane + facing * depth))
        block(p, a0, a1, y0, y1, z0, z1, awning, skip=("bottom", "back" if facing < 0 else "front"))
    else:
        x0, x1 = sorted((plane, plane + facing * depth))
        block(p, x0, x1, y0, y1, a0, a1, awning, skip=("bottom", "right" if facing < 0 else "left"))


def make_brick_quarter() -> Part:
    """One quarter of an old brick block, 6.5 studs square and 3.57 tall at its roof hatch: the
    paved yard and footway to the axes, corner building A (two storeys, flat roof, a shop wrapping
    the corner) and B (a one-storey shop), A in rose-red brick and B in dark brown, with cream
    cornices and window surrounds, and a ghost sign painted on A's party wall above B's roof. The
    water tank and the fire escape are their own pieces."""
    p = Part("brick-quarter")
    block(p, 0.0, GROUND_TO, 0.0, MIN_GAP, 0.0, GROUND_TO, STONE_DARK, top=TRIM)
    # A: the corner building
    block(p, A_X0, FACADE, 0.0, A_TOP, A_Z0, FACADE, BRICK_ROSE, skip=("bottom", "top"))
    block(p, A_X0 - 0.05, FACADE + 0.07, A_TOP, A_TOP + CAP, A_Z0 - 0.07, FACADE + 0.07, CREAM, top=SLATE)
    # B: the shop beside it, in the dark brown brick
    block(p, B_X0, A_X0, 0.0, B_TOP, B_Z0, FACADE, BRICK_DARK, skip=("bottom", "top"))
    block(p, 0.0, A_X0, B_TOP, B_TOP + CAP, B_Z0 - 0.07, FACADE + 0.07, CREAM, top=SLATE, skip=("bottom", "right"))
    # A's upper windows: street face, flank and back (behind the fire escape)
    front = ("z", FACADE, 1)
    flank = ("x", FACADE, 1)
    y0 = STOREY + 0.35
    window_row(p, front, (A_X0 + 0.85, FACADE - 0.75), y0, y0 + 0.82)
    window_row(p, flank, (A_Z0 + 0.95, FACADE - 0.8), y0, y0 + 0.82)
    window_row(p, ("z", A_Z0, -1), (A_X0 + 0.7, FACADE - 0.7), y0, y0 + 0.82, half=0.22)
    # shopfronts: A's wraps the corner, B's is plain; B's back door onto the yard
    shopfront(p, front, A_X0 + 0.3, FACADE - 0.25, A_X0 + 0.65, PEACH, BLUE_PALE)
    shop_window(p, flank, A_Z0 + 1.5, FACADE - 0.3)
    shopfront(p, front, B_X0 + 0.35, A_X0 - 0.3, A_X0 - 0.75, TRIM, TAN)
    on_wall(p, ("z", B_Z0, -1), 0.95, 1.45, 0.0, 1.05, PROUD, SLATE, edge=GREY)
    # a ghost sign on A's party wall above B's roof: three painted bands one above another, none
    # laid over another
    party = ("x", A_X0, -1)
    z0, z1 = B_Z0 + 0.6, FACADE - 0.45
    for y_lo, y_hi, colour in ((B_TOP + CAP + 0.15, 2.3, TAN), (2.3, 2.58, RED), (2.58, A_TOP - 0.25, TAN)):
        on_wall(p, party, z0, z1, y_lo, y_hi, PROUD, colour)
    # roof furniture: a hatch on A, a chimney stack on B against the party wall
    block(p, A_X0 + 0.6, A_X0 + 1.2, A_TOP + CAP, A_TOP + CAP + 0.22, A_Z0 + 0.6, A_Z0 + 1.3, GREY, top=STONE)
    block(p, A_X0 - 0.4, A_X0, B_TOP + CAP, B_TOP + CAP + 0.55, B_Z0 + 0.4, B_Z0 + 0.95, BRICK_BROWN,
          top=IRON, skip=("bottom", "right"))
    # the yard wall where the yard meets the street, with its gate
    for z0, z1 in ((0.0, 0.6), (1.5, A_Z0)):
        block(p, FACADE, FACADE + 0.28, 0.0, 0.9, z0, z1, BRICK_BROWN, top=BRICK)
    block(p, FACADE + 0.06, FACADE + 0.22, 0.0, 0.78, 0.6, 1.5, MINT_DARK)
    # a bin in the yard
    block(p, 3.75, 4.3, 0.0, 0.5, A_Z0 - 0.62, A_Z0 - 0.08, MINT_DARK, top=GREY)
    return p


def make_fire_escape() -> Part:
    """An iron fire escape for a two-storey wall, 2.4 studs wide and 0.6 deep, from 0.55 to 2.25 up,
    against the wall at z = 0 with its landing toward -Z: the landing at the first floor with a rail
    on two posts, and the drop ladder down from it. Every member is MIN_MEMBER across."""
    p = Part("fire-escape")
    d, m = -0.6, MIN_MEMBER
    y = STOREY + 0.05
    block(p, -1.2, 1.2, y, y + m, d, 0.0, IRON, skip=("bottom", "back"))
    rod(p, (-1.2, y + 0.55, d + 0.05), (1.2, y + 0.55, d + 0.05), m, IRON, caps=True)
    for x in (-1.15, 1.15):
        rod(p, (x, y + m, d + 0.05), (x, y + 0.55, d + 0.05), m, IRON, sides=3)
    for x in (0.6, 1.0):
        rod(p, (x, 0.55, d + 0.08), (x, y, d + 0.08), m, IRON, sides=3)
    for yr in (0.85, 1.25):
        rod(p, (0.6, yr, d + 0.08), (1.0, yr, d + 0.08), m, IRON, sides=3)
    return p


def make_water_tank() -> Part:
    """A rooftop water tank, 0.92 studs across and 1.48 tall: a timber barrel on four iron legs and
    a platform, under a dark conical lid."""
    p = Part("water-tank")
    for sx in (-1, 1):
        for sz in (-1, 1):
            block(p, sx * 0.28 - 0.05, sx * 0.28 + 0.05, 0.0, 0.46, sz * 0.28 - 0.05, sz * 0.28 + 0.05, IRON,
                  skip=("bottom", "top"))
    block(p, -0.4, 0.4, 0.42, 0.52, -0.4, 0.4, IRON)
    lathe(p, [(0.42, 0.52), (0.42, 1.14), (0.46, 1.17), (0.0, 1.48)], [BRICK_BROWN, IRON, SLATE], seg=6,
          phase=math.pi / 6)
    return p


# --- singles -------------------------------------------------------------------------------------


def make_billboard() -> Part:
    """An old billboard on a steel frame, 1.96 studs wide, 0.8 deep and 5.52 tall, facing -Z: two
    I-section legs with an X brace, a catwalk with a rail under the panel, the panel's steel back
    with its bracing, two lamps on arms, and a faded advert made of colour blocks: a yellow sun on a
    pale blue sky over a red band, a white panel with two dark bars. No lettering, no brand. (A first
    cut with a red octagon read as a stop sign.)"""
    p = Part("billboard")
    leg_z, y0, y1, face = 0.12, 3.75, 5.15, 0.0
    for x in (-0.6, 0.6):
        block(p, x - 0.11, x + 0.11, 0.0, y0, leg_z - 0.08, leg_z + 0.08, SLATE, top=GREY)
        block(p, x - 0.05, x + 0.05, 0.0, y0, leg_z - 0.13, leg_z + 0.13, SLATE, skip=("bottom", "top"))
    for a, b in (((-0.6, 0.5), (0.6, 2.4)), ((0.6, 0.5), (-0.6, 2.4)), ((-0.6, 2.4), (0.6, 3.5))):
        rod(p, (a[0], a[1], leg_z), (b[0], b[1], leg_z), MIN_MEMBER, GREY, sides=3)
    # catwalk and rail
    block(p, -0.98, 0.98, y0 - 0.23, y0 - 0.13, -0.45, 0.04, IRON, skip=())
    rod(p, (-0.95, y0 + 0.18, -0.4), (0.95, y0 + 0.18, -0.4), MIN_MEMBER, IRON, caps=True)
    for x in (-0.86, 0.86):
        rod(p, (x, y0 - 0.13, -0.4), (x, y0 + 0.18, -0.4), MIN_MEMBER, IRON, sides=3)
    # the panel: steel back, then the advert's colour blocks standing proud of its face
    block(p, -0.98, 0.98, y0, y1, face, 0.2, GREY, skip=(), front=BLUE_PALE, top=SLATE)
    for x in (-0.55, 0.55):
        rod(p, (x, y0 - 0.15, 0.2), (x, y1, 0.2), MIN_MEMBER, SLATE)
    wall = ("z", face, -1)
    on_wall(p, wall, -0.96, 0.96, y0 + 0.02, y0 + 0.38, MIN_GAP, RED)
    sun = [(-0.5 + 0.33 * math.cos(a), 4.6 + 0.33 * math.sin(a)) for a in (2 * math.pi * k / 12 for k in range(12))]
    lo = [(x, y, face - MIN_GAP) for x, y in sun]
    hi = [(x, y, face + 0.01) for x, y in sun]
    face_out(p, lo, YELLOW, (0.0, 0.0, -1.0))
    for k in range(12):
        n = (k + 1) % 12
        mx, my = (sun[k][0] + sun[n][0]) / 2 + 0.5, (sun[k][1] + sun[n][1]) / 2 - 4.6
        face_out(p, [hi[k], hi[n], lo[n], lo[k]], YELLOW_DEEP, (mx, my, 0.0))
    on_wall(p, wall, 0.1, 0.9, 4.2, 5.0, MIN_GAP, WHITE)
    on_wall(p, wall, 0.22, 0.78, 4.64, 4.8, 2 * MIN_GAP, SLATE)
    on_wall(p, wall, 0.22, 0.6, 4.38, 4.5, 2 * MIN_GAP, GREY)
    # lamps on arms over the face
    for x in (-0.55, 0.55):
        rod(p, (x, y1 + 0.02, 0.05), (x, y1 + 0.3, -0.4), MIN_MEMBER, IRON, sides=3)
        block(p, x - 0.13, x + 0.13, y1 + 0.22, y1 + 0.35, -0.55, -0.32, IRON, skip=(), bottom=CREAM)
    return p


# --- building sites ------------------------------------------------------------------------------
#
# A Metropolis site is a concrete frame going up behind blue hoardings: a gravel pad, a slab with
# columns and the next floor, a lift core rising highest, pipe scaffold on the street face, stacked
# steel and blocks, a mixer; the crane variants add a slim tower crane. Hoardings are plain,
# painted, with no brands. Everything stays inside its lot except a crane's jibs. The approved
# layout has narrow (4 x 8) and small (6 x 6) lots only, so there is no medium site.

HOARD_H = 1.35
FRAME_SLAB = 0.2  # a frame's ground slab and floor slabs; what stands on the ground slab stands this high


def site_ground(name: str, hx: float, hz: float, seed: int, patches) -> Part:
    """A lot scraped to compacted earth, straight-edged as city lots are, with gravel patches."""
    p = Part(name)
    rng = random.Random(seed)
    block(p, -hx, hx, 0.0, MIN_GAP, -hz, hz, EARTH_DARK)
    for cx, cz, rx, rz, colour in patches:
        decal(p, blotch(rng, cx, cz, rx, rz, points=7), MIN_GAP + DECAL_LIFT, colour)
    return p


def make_site_ground_narrow() -> Part:
    patches = ((-0.8, 2.2, 0.9, 1.1, STONE_DARK), (1.0, -2.9, 0.75, 0.6, EARTH))
    return site_ground("site-ground-narrow", 1.95, 3.95, 401, patches)


def make_site_ground_small() -> Part:
    patches = ((-1.5, 1.6, 1.0, 0.9, STONE_DARK), (1.8, -1.5, 0.8, 0.9, EARTH))
    return site_ground("site-ground-small", 2.95, 2.95, 402, patches)


def concrete_frame(name: str, x0: float, x1: float, z0: float, z1: float, cols_x, cols_z, slab_from: float, upper,
                   core) -> Part:
    """A reinforced-concrete frame going up, in the lot frame: the ground slab; a grid of
    first-storey columns; the first-floor slab cast only from `slab_from` back, so the front row of
    columns stands free with its rebar out, waiting for the next pour; the next storey's columns
    where `upper` lists them, rebar out of their tops; and the lift core, `core` = (x0, x1, z0, z1,
    height), standing above the rest. Fresh concrete is the kit's pale wall grey, so the frame
    reads as the new city arriving. (A slab over the whole grid read as a solid block.)"""
    p = Part(name)
    slab_t = FRAME_SLAB
    block(p, x0, x1, 0.0, slab_t, z0, z1, STONE, top=STONE_LIGHT)
    c = 0.13
    floor1 = STOREY
    sz0 = slab_from - 0.3

    def rebar(x: float, z: float, y: float) -> None:
        block(p, x - MIN_MEMBER / 2, x + MIN_MEMBER / 2, y, y + 0.35, z - MIN_MEMBER / 2, z + MIN_MEMBER / 2,
              BRICK_BROWN)

    for x in cols_x:
        for z in cols_z:
            under = z >= sz0
            block(p, x - c, x + c, slab_t, floor1 if under else floor1 + slab_t, z - c, z + c, PALE,
                  skip=("bottom", "top") if under else ("bottom",), top=STONE_LIGHT)
            if not under:
                rebar(x, z, floor1 + slab_t)
    block(p, x0, x1, floor1, floor1 + slab_t, sz0, z1, STONE, top=STONE_LIGHT)
    top2 = floor1 + slab_t
    for x, z, h in upper:
        block(p, x - c, x + c, top2, top2 + h, z - c, z + c, PALE, top=STONE_LIGHT)
        rebar(x, z, top2 + h)
    cx0, cx1, cz0, cz1, ch = core
    block(p, cx0, cx1, slab_t, ch, cz0, cz1, TRIM, top=STONE)
    mid = (cx0 + cx1) / 2
    for y in (slab_t, floor1 + slab_t):
        on_wall(p, ("z", cz0, -1), mid - 0.22, mid + 0.22, y, y + 0.95, MIN_GAP, SLATE)
    return p


def make_frame_narrow() -> Part:
    """SiteNarrow's frame: a 3.5 x 5.05 slab at the back of the 4 x 8 lot, the first floor over the
    back two bays, the second storey's columns rising to 3.2, and the lift core at 3.5."""
    xs, zs = (-1.6, 0.0, 1.6), (-1.05, 1.35, 3.6)
    upper = [(-1.6, 3.6, 1.4), (0.0, 3.6, 1.4), (1.6, 3.6, 1.4), (-1.6, 1.35, 1.4), (1.6, 1.35, 0.9)]
    return concrete_frame("frame-narrow", -1.75, 1.75, -1.25, 3.8, xs, zs, 1.35, upper, (-1.25, -0.25, 2.2, 3.2, 3.5))


def make_frame_small() -> Part:
    """SiteSmall's frame: a 3.9 x 4.45 slab at the back left of the 6 x 6 lot, columns, the first
    floor over the back two bays, the next storey started at the back, and the lift core at 3.5."""
    xs, zs = (-2.6, -0.85, 0.9), (-1.3, 0.75, 2.75)
    upper = [(-2.6, 2.75, 1.4), (-0.85, 2.75, 1.4), (0.9, 2.75, 1.0), (-2.6, 0.75, 1.4)]
    return concrete_frame("frame-small", -2.8, 1.1, -1.5, 2.95, xs, zs, 0.75, upper, (-2.2, -1.2, 1.2, 2.2, 3.5))


def hoarding(name: str, half: float) -> Part:
    """A run of site hoarding, 2 * half studs long, 0.74 deep with its braces and 1.35 tall, facing
    -Z: plywood panels a stud wide painted the kit's blue under a white top band, on slate posts
    braced behind. Plain, no brands. Runs butt end to end."""
    p = Part(name)
    panels = round(2 * half)
    for i in range(panels):
        x0 = -half + i * 1.0
        block(p, x0, x0 + 1.0, 0.0, HOARD_H - 0.22, -0.04, 0.04, BLUE, skip=("bottom",), back=GREY, top=BLUE)
    block(p, -half, half, HOARD_H - 0.22, HOARD_H, -0.05, 0.05, WHITE, back=PALE)
    for x in (-half + 0.1, half - 0.1):
        block(p, x - 0.06, x + 0.06, 0.0, HOARD_H - 0.05, 0.04, 0.16, SLATE, skip=("bottom", "front"))
        rod(p, (x, HOARD_H - 0.4, 0.1), (x, 0.05, 0.62), MIN_MEMBER, SLATE, sides=3)
    return p


def make_hoarding() -> Part:
    return hoarding("hoarding", 1.0)


def make_hoarding_half() -> Part:
    return hoarding("hoarding-half", 0.5)


def scaffold(name: str, hx: float, bays: int) -> Part:
    """Pipe scaffold along a frame's street face, 2 * hx studs long between standard centres, 0.7
    deep and 3.6 tall, centred on its middle: grey standards in two rows, `bays` bays long, ledgers
    and timber boards at both lifts, a guard rail, braces on the face and a sheet of blue debris
    netting on the upper lift. Every member is MIN_MEMBER across."""
    p = Part(name)
    hz, h, m = 0.3, 3.6, MIN_MEMBER
    xs = [-hx + 2 * hx * k / bays for k in range(bays + 1)]
    for x in xs:
        for z in (-hz, hz):
            block(p, x - m / 2, x + m / 2, 0.0, h, z - m / 2, z + m / 2, GREY, top=STONE)
    for y in (1.65, 3.25):
        for z in (-hz, hz):
            rod(p, (-hx, y, z), (hx, y, z), m, GREY)
        block(p, -hx + 0.05, hx - 0.05, y + 0.05, y + 0.15, -hz + 0.05, hz - 0.05, TAN, skip=(), bottom=APRICOT)
    rod(p, (-hx, 2.4, -hz), (hx, 2.4, -hz), m, STONE)
    zb = -hz - 0.08
    for x0, x1, y0, y1 in ((-hx, 0.0, 0.15, 1.6), (0.0, hx, 0.15, 1.6), (0.0, -hx, 1.75, 3.2)):
        rod(p, (x0, y0, zb), (x1, y1, zb), m, STONE, sides=3)
    block(p, 0.05, hx, 2.35, 3.55, -hz - 0.24, -hz - 0.14, BLUE, skip=("bottom",), back=SLATE_BLUE)
    return p


def make_scaffold() -> Part:
    return scaffold("scaffold", 2.2, 4)


def make_scaffold_narrow() -> Part:
    return scaffold("scaffold-narrow", 1.7, 2)


def make_steel_stack() -> Part:
    """Steel sections in red primer, 2.4 studs long, 0.9 wide and 0.62 tall: two timber bearers,
    three I-beams side by side and two across them."""
    p = Part("steel-stack")
    for x in (-0.8, 0.8):
        block(p, x - 0.1, x + 0.1, 0.0, 0.14, -0.45, 0.45, BRICK_BROWN)
    for z in (-0.3, 0.0, 0.3):
        block(p, -1.2, 1.2, 0.14, 0.38, z - 0.13, z + 0.13, RED, top=APRICOT, left=BRICK, right=BRICK)
    for z in (-0.15, 0.15):
        block(p, -1.0, 1.0, 0.38, 0.62, z - 0.13, z + 0.13, RED, top=APRICOT, left=BRICK, right=BRICK)
    return p


def make_block_pallet() -> Part:
    """Concrete blocks on a pallet, 1.1 x 0.9 studs and 0.85 tall, with a broken top course."""
    p = Part("block-pallet")
    block(p, -0.55, 0.55, 0.0, 0.14, -0.45, 0.45, TAN, top=APRICOT)
    block(p, -0.5, 0.5, 0.14, 0.62, -0.4, 0.4, STONE, top=STONE_LIGHT)
    block(p, -0.5, 0.05, 0.62, 0.85, -0.4, 0.4, STONE, top=STONE_LIGHT)
    return p


def make_mixer() -> Part:
    """A site mixer, 1.0 x 1.46 studs and 1.37 tall, its mouth toward -Z: an orange drum tipped on a
    slate cradle with an engine box behind, on a skid."""
    p = Part("mixer")
    block(p, -0.5, 0.5, 0.0, 0.12, -0.6, 0.6, SLATE)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.36, sx * 0.46))
        block(p, x0, x1, 0.12, 0.95, -0.12, 0.08, SLATE, skip=("bottom",))
    block(p, -0.32, 0.32, 0.12, 0.62, 0.22, 0.62, YELLOW, top=IRON)
    drum = Part("drum")
    lathe(drum, [(0.22, 0.0), (0.42, 0.2), (0.45, 0.42), (0.3, 0.78), (0.3, 0.84)],
          [ORANGE, ORANGE, YELLOW_DEEP, IRON], seg=8, phase=math.pi / 8)
    a = math.radians(-50.0)
    c, s = math.cos(a), math.sin(a)
    base = len(p.verts)
    for x, y, z in drum.verts:
        p.verts.append((x, 0.62 + y * c - z * s, -0.02 + y * s + z * c))
    for idx, colour in drum.faces:
        p.faces.append(([base + i for i in idx], colour))
    return p


def make_tower_crane_slim() -> Part:
    """The crane sites' tower crane, 11.75 studs tall (mast 9.8), its jib out 7.2 studs along -X and
    its counter-jib 1.9 along +X, origin at the mast's foot: a concrete footing, a square lattice
    mast 0.6 across in the kit's yellow, the slewing deck with the white cab facing along the jib, a
    triangular lattice jib with its trolley and hook, the counter-jib with a concrete counterweight
    and a rail, and the cat-head with its ties. Slim because the lots it stands on are 4 and 6 studs
    wide: a blueprint turns it so the jib runs front to back over its own lot, and neighbouring
    jibs stay parallel. Members are never under MIN_MEMBER."""
    p = Part("tower-crane-slim")
    footing, foot, m, chord, top, sections = 0.45, 0.25, 0.3, 0.12, 9.8, 9
    block(p, -footing, footing, 0.0, foot, -footing, footing, STONE_DARK, top=STONE)
    corners = ((-m, -m), (m, -m), (m, m), (-m, m))
    for x, z in corners:
        block(p, x - chord / 2, x + chord / 2, foot, top, z - chord / 2, z + chord / 2, YELLOW, skip=("bottom", "top"))
    step = (top - foot) / sections
    for k in range(sections):
        y0, y1 = foot + k * step, foot + (k + 1) * step
        for i in range(4):
            (xa, za), (xb, zb) = corners[i], corners[(i + 1) % 4]
            if (k + i) % 2:
                (xa, za), (xb, zb) = (xb, zb), (xa, za)
            rod(p, (xa, y0, za), (xb, y1, zb), MIN_MEMBER, YELLOW_DEEP, sides=3)
    # slewing deck and cab
    d = 0.42
    block(p, -d, d, top, top + 0.3, -d, d, YELLOW, top=YELLOW_DEEP, skip=())
    cx0, cx1, cz0, cz1, below, above = -0.95, -0.42, -0.42, 0.0, 0.62, 0.18
    block(p, cx0, cx1, top - below, top + above, cz0, cz1, PALE, top=STONE)
    on_wall(p, ("x", cx0, -1), cz0 + 0.07, cz1 - 0.07, top - below + 0.1, top - 0.15, MIN_GAP, BLUE, edge=GREY)
    on_wall(p, ("z", cz0, -1), cx0 + 0.1, cx1, top - below + 0.1, top - 0.15, MIN_GAP, BLUE, edge=GREY)
    # jib: two bottom chords and a top chord, braced on both flanks, out along -X
    jy, jh, jw, reach = top + 0.3, 0.5, 0.2, -7.2
    rod(p, (d, jy + 0.05, -jw), (reach, jy + 0.05, -jw), MIN_MEMBER, YELLOW, caps=True)
    rod(p, (d, jy + 0.05, jw), (reach, jy + 0.05, jw), MIN_MEMBER, YELLOW, caps=True)
    rod(p, (0.0, jy + jh, 0.0), (reach + 0.4, jy + jh * 0.35, 0.0), MIN_MEMBER, YELLOW, caps=True)
    tip = reach + 0.4

    def chord_y(x: float) -> float:
        return jy + jh - 0.65 * jh * (x / tip)

    bays = 7
    for k in range(bays):
        xa = -0.1 + (tip + 0.1) * k / bays
        xb = -0.1 + (tip + 0.1) * (k + 1) / bays
        for side in (-jw, jw):
            if k % 2 == 0:
                a, b = (xa, chord_y(xa), 0.0), (xb, jy + 0.05, side)
            else:
                a, b = (xa, jy + 0.05, side), (xb, chord_y(xb), 0.0)
            rod(p, a, b, MIN_MEMBER, YELLOW_DEEP, sides=3)
    # trolley, hoist rope and hook block
    tx, hook = -4.2, 6.6
    block(p, tx - 0.25, tx + 0.25, jy - 0.14, jy - 0.02, -jw - 0.06, jw + 0.06, SLATE, skip=())
    rod(p, (tx, jy - 0.14, 0.0), (tx, hook, 0.0), MIN_MEMBER, IRON)
    block(p, tx - 0.17, tx + 0.17, hook - 0.4, hook, -0.14, 0.14, RED, skip=(), top=YELLOW)
    # counter-jib with its counterweight and a rail
    counter, cw = 1.9, 0.25
    block(p, d, counter, jy, jy + 0.16, -cw, cw, YELLOW, skip=(), top=YELLOW_DEEP)
    x, wx, wy, wz = 1.55, 0.3, 0.45, 0.3
    block(p, x - wx, x + wx, jy - wy, jy + wy, -wz, wz, STONE, top=STONE_LIGHT)
    rod(p, (d, jy + 0.6, cw), (1.2, jy + 0.6, cw), MIN_MEMBER, YELLOW, caps=True)
    # cat-head and ties
    apex = (0.0, top + 1.9, 0.0)
    q = 0.25
    for x, z in ((-q, -q), (q, -q), (q, q), (-q, q)):
        rod(p, (x, top + 0.3, z), apex, MIN_MEMBER, YELLOW, sides=3)
    rod(p, apex, (-3.8, chord_y(-3.8), 0.0), MIN_MEMBER, IRON)
    rod(p, apex, (1.75, jy + 0.16, 0.0), MIN_MEMBER, IRON)
    block(p, -0.08, 0.08, apex[1] - 0.05, apex[1] + 0.05, -0.08, 0.08, RED, skip=())
    return p


def make_scaffold_ring() -> Part:
    """The landmark-reveal scaffold round a 9 x 9 slot, 8.0 studs tall: grey pipe standards,
    ledgers at three lifts, timber decks at the lower two, blue debris netting round the top lift,
    and a blue hoarding skirt with a white band at the foot, open at the street. It stands wholly
    outside the slot (nothing nearer the centre than 4.54, nothing beyond 4.97), so a landmark that
    fills its 9 x 9 touches none of it; the client scales it by max(footprint) / 9."""
    p = Part("scaffold-ring")
    e, h, pipe = 4.75, 8.0, 0.18
    lifts = (2.6, 5.2, 7.8)
    gate = 1.6
    for rot in (0, 90, 180, 270):
        side = Part("side")
        xs = (-e, -gate, gate) if rot == 0 else (-e, -e / 2, 0.0, e / 2)
        for x in xs:
            block(side, x - pipe / 2, x + pipe / 2, 0.0, h, -e - pipe / 2, -e + pipe / 2, GREY, top=STONE)
        for y in lifts:
            rod(side, (-e, y, -e), (e, y, -e), pipe * 0.8, GREY)
        for y in lifts[:2]:
            reach = e + 0.19 if rot in (0, 180) else e - 0.21
            block(side, -reach, reach, y + 0.1, y + 0.2, -e - 0.21, -e + 0.21, TAN, skip=(), bottom=APRICOT)
        rod(side, (-e + 0.1, 0.3, -e - 0.12), (-0.1, lifts[0] - 0.1, -e - 0.12), 0.1, STONE)
        rod(side, (0.1, lifts[0] + 0.3, -e - 0.12), (e - 0.1, lifts[1] - 0.1, -e - 0.12), 0.1, STONE)
        reach = e + 0.2 if rot in (0, 180) else e + 0.14
        block(side, -reach, reach, lifts[1] + 0.3, h - 0.05, -e - 0.22, -e - 0.12, BLUE, back=SLATE_BLUE)
        spans = ((-reach, -gate - 0.1), (gate + 0.1, reach)) if rot == 0 else ((-reach, reach),)
        for x0, x1 in spans:
            block(side, x0, x1, 0.0, 1.05, -e - 0.22, -e - 0.12, BLUE, back=SLATE_BLUE)
            block(side, x0, x1, 1.05, 1.3, -e - 0.22, -e - 0.12, WHITE)
        place(p, side, rot)
    return p


def make_lot_hoarding() -> Part:
    """The next-lot marker, 1.96 studs wide, 0.36 deep and 2.7 tall, facing -Z: a white development
    board on two slate posts with concrete feet, under a blue header, painted on both faces with
    the tower that is coming: three blue and glass blocks rising, a mint tree and a pale ground
    line. No lettering."""
    p = Part("lot-hoarding")
    for x in (-0.8, 0.8):
        block(p, x - 0.18, x + 0.18, 0.0, 0.18, -0.18, 0.18, STONE_DARK, top=STONE)
        block(p, x - 0.07, x + 0.07, 0.18, 2.55, -0.07, 0.07, SLATE, top=GREY)
    block(p, -0.95, 0.95, 1.2, 2.45, -0.05, 0.05, WHITE)
    block(p, -0.95, 0.95, 2.45, 2.7, -0.07, 0.07, BLUE, top=SLATE_BLUE)
    for facing in (-1, 1):
        wall = ("z", facing * 0.05, facing)
        a = -facing  # mirror the picture on the back so the tall block is on the same side
        for x0, x1, y1, colour in ((-0.62, -0.22, 1.85, GLASS), (-0.18, 0.28, 2.3, BLUE), (0.32, 0.62, 1.7, BLUE_PALE)):
            lo, hi = sorted((a * x0, a * x1))
            on_wall(p, wall, lo, hi, 1.35, y1, MIN_GAP, colour, edge=colour)
        lo, hi = sorted((a * 0.68, a * 0.86))
        on_wall(p, wall, lo, hi, 1.35, 1.62, MIN_GAP, MINT, edge=MINT_DARK)
        on_wall(p, wall, -0.85, 0.85, 1.25, 1.35, MIN_GAP, STONE)
    return p


PIECES = {
    "carpark-quarter": make_carpark_quarter,
    "car-a": make_car_a,
    "car-b": make_car_b,
    "car-c": make_car_c,
    "pay-booth": make_pay_booth,
    "carpark-light": make_carpark_light,
    "lot-quarter": make_lot_quarter,
    "chainlink-quarter": make_chainlink_quarter,
    "skip": make_skip,
    "rubble": make_rubble,
    "brick-quarter": make_brick_quarter,
    "fire-escape": make_fire_escape,
    "water-tank": make_water_tank,
    "billboard": make_billboard,
    "site-ground-narrow": make_site_ground_narrow,
    "site-ground-small": make_site_ground_small,
    "frame-narrow": make_frame_narrow,
    "frame-small": make_frame_small,
    "hoarding": make_hoarding,
    "hoarding-half": make_hoarding_half,
    "scaffold": make_scaffold,
    "scaffold-narrow": make_scaffold_narrow,
    "steel-stack": make_steel_stack,
    "block-pallet": make_block_pallet,
    "mixer": make_mixer,
    "tower-crane-slim": make_tower_crane_slim,
    "scaffold-ring": make_scaffold_ring,
    "lot-hoarding": make_lot_hoarding,
}


# --- blueprints ----------------------------------------------------------------------------------
#
# The 15 old-town and site blueprints are written from here (--write-blueprints), so a position that
# depends on a piece's geometry (a car in its bay, the tank on the shop's roof, the fire escape on
# the corner building's back, blocks on a frame's slab) uses that piece's own constant, and a clump
# is generated from its quarter and cannot drift from it.

BLUEPRINT_DIR = os.path.join(REPO_ROOT, "tools", "testfit", "blueprints", "_props", "Metropolis")
ERA = "Metropolis"


def placed(model: str, pos: Vec, rot: int = 0) -> dict:
    """One blueprint piece of this kit: `pos` in studs (the kit's unit), `rot` degrees about Y."""
    return {"kit": KIT, "model": model, "pos": [round(v, 4) for v in pos], "rotY": rot, "stage": 0}


def quarter_turned(piece: dict, turns: int) -> dict:
    """A quarter's piece as its clump shows it after `turns` quarter turns about the clump origin,
    by Roblox's CFrame.Angles(0, a, 0) mapping (INTERFACES "Fabric data"): (x, z) -> (x cos a +
    z sin a, -x sin a + z cos a), and the piece's own rotY grows by the same angle."""
    a = math.radians(90 * turns)
    c, s = round(math.cos(a)), round(math.sin(a))
    x, y, z = piece["pos"]
    out = dict(piece)
    # + 0.0: every coordinate of a clump piece is written as a float, and never as -0.0
    out["pos"] = [round(x * c + z * s, 4) + 0.0, y + 0.0, round(-x * s + z * c, 4) + 0.0]
    out["rotY"] = (piece["rotY"] + 90 * turns) % 360
    return out


def blueprints() -> list[dict]:
    """Every blueprint this kit owns, in the schema of tools/testfit/blueprint.py."""
    frame = "in the local (+X, +Z) quadrant, x and z in 0 .. 6.5 (INTERFACES 'Fabric data')"
    bay = ROW_IN + BAY_D / 2
    quarters = {
        "A": (
            f"one quarter of a surface car park {frame}: asphalt to the clump axes, kerbs, four bays, the corner "
            "island with the pay booth and the light, three parked cars; oldtown-kit is 1 unit = 1 stud, so scale "
            "is 1.0",
            [
                placed("carpark-quarter", (0, 0, 0)),
                placed("pay-booth", (4.65, KERB_TOP, 5.85), 0),
                placed("carpark-light", (5.85, KERB_TOP, 4.75), 90),
                placed("car-a", (GAP + BAY_W * 0.5, LOT_TOP, bay), 180),
                placed("car-b", (bay, LOT_TOP, GAP + BAY_W * 0.5), 90),
                placed("car-c", (bay, LOT_TOP, GAP + BAY_W * 1.5), 270),
            ],
            "surface car park (four quarters)",
        ),
        "B": (
            f"one quarter of a fenced vacant lot {frame}: earth, weeds and the corner of a demolished building's "
            "floor slab to the clump axes, chain-link on the two outer edges, fallen bricks and a skip; scale 1.0",
            [
                placed("lot-quarter", (0, 0, 0)),
                placed("chainlink-quarter", (0, 0, 0)),
                placed("skip", (4.95, MIN_GAP, 2.4), 90),
            ],
            "fenced vacant lot (four quarters)",
        ),
        "C": (
            f"one quarter of an old brick block {frame}: paved yard to the clump axes, a two-storey corner building "
            "and a one-storey shop on the +Z street (3.57 tall at most, under the first landmarks), a water tank on "
            "the shop's roof and a fire escape on the corner building's back; scale 1.0",
            [
                placed("brick-quarter", (0, 0, 0)),
                placed("water-tank", (1.5, B_TOP + CAP, 4.45)),
                placed("fire-escape", (4.63, 0, A_Z0)),
            ],
            "old brick block (four quarters)",
        ),
    }
    out = []

    def add(bid: str, footprint: list, note: str, pieces: list[dict]) -> None:
        out.append({"id": bid, "era": ERA, "scale": 1.0, "footprint": footprint, "note": note, "pieces": pieces})

    for key, (note, pieces, title) in quarters.items():
        add(f"OldTownQuarter{key}", [13, 13], note, pieces)
        clump = [quarter_turned(piece, turns) for turns in range(4) for piece in pieces]
        add(f"OldTownClump{key}", [13, 13],
            f"exactly OldTownQuarter{key} at rotY 0, 90, 180 and 270 about the origin: a {title}, 13 x 13 on the "
            "14-stud grid", clump)

    add("OldTownBillboard", [2, 1],
        "an old billboard on a steel frame, facing -Z; colour blocks, no lettering; the piece sits 0.155 back so the "
        "frame and catwalk are centred on the origin", [placed("billboard", (0, 0, 0.155))])
    add("OldTownRubble", [2, 2], "a heap of demolition rubble", [placed("rubble", (0, 0, 0))])
    add("OldTownSkip", [2, 1.2], "an open builder's skip", [placed("skip", (0, 0, 0))])

    narrow = [
        placed("site-ground-narrow", (0, 0, 0)),
        placed("frame-narrow", (0, 0, 0)),
        placed("scaffold-narrow", (0, 0, -1.6)),
        placed("hoarding", (-0.95, 0, -3.85)),
        placed("hoarding-half", (1.45, 0, -3.85)),
        placed("mixer", (0.95, 0, -2.6), 90),
        placed("block-pallet", (-1.3, 0, -2.65)),
    ]
    small = [
        placed("site-ground-small", (0, 0, 0)),
        placed("frame-small", (0, 0, 0)),
        placed("scaffold", (1.45, 0, 0.72), 90),
        placed("hoarding", (-2.0, 0, -2.85)),
        placed("hoarding", (1.95, 0, -2.85)),
        placed("steel-stack", (2.4, 0, -0.35), 90),
    ]
    blocks_on_slab = placed("block-pallet", (0.0, FRAME_SLAB, -0.3))
    add("SiteNarrow", [4, 8],
        "a concrete frame going up on a 4 x 8 terraced lot, in the lot frame: scaffold on its street face, blue "
        "hoarding with a gate, a mixer and blocks in the front yard", narrow)
    add("SiteSmall", [6, 6],
        "a concrete frame going up on a 6 x 6 lot, in the lot frame: scaffold on its +X face, blue hoarding with a "
        "gate, steel, blocks and a mixer", small + [placed("mixer", (2.35, 0, 2.2)), blocks_on_slab])
    add("SiteNarrowCrane", [4, 8],
        "SiteNarrow with the slim tower crane (site variant): the mast stands at the back of the lot through the "
        "frame, the jib runs front to back over the lot (tip 0.25 inside the front), the counter-jib overhangs the "
        "back by 1.35, overhead. Mast 9.8, cat-head 11.75",
        narrow + [placed("tower-crane-slim", (0.8, 0, 3.45), 270)])
    add("SiteSmallCrane", [6, 6],
        "SiteSmall with the slim tower crane (site variant) at its back-right corner, the mixer moved into the gate; "
        "the jib runs front to back and overhangs the front by 1.75, the counter-jib the back by 1.35, overhead. "
        "Mast 9.8, cat-head 11.75",
        small + [placed("mixer", (0.0, 0, -2.4), 90), blocks_on_slab, placed("tower-crane-slim", (2.45, 0, 2.45), 270)])
    add("RevealScaffold", [10, 10],
        "one generated piece: a pipe-scaffold ring with blue netting and a hoarding skirt that stands wholly outside "
        "a 9 x 9 slot (nothing nearer the centre than 4.54, nothing beyond 4.97), so a landmark that fills its "
        "footprint touches none of it; the client still scales it by max(footprint) / 9",
        [placed("scaffold-ring", (0, 0, 0))])
    add("LotHoarding", [2, 2],
        "the next-pad marker: a development board on two posts, facing -Z, painted on both faces",
        [placed("lot-hoarding", (0, 0, 0))])
    return out


def write_blueprints() -> None:
    """Writes every blueprint of blueprints() as the repo keeps them: one key per line, one piece
    per line, LF."""
    for bp in blueprints():
        lines = ["{"]
        lines += [f'  "{key}": {json.dumps(value)},' for key, value in bp.items() if key != "pieces"]
        lines.append('  "pieces": [')
        lines.append(",\n".join("    " + json.dumps(piece, separators=(", ", ": ")) for piece in bp["pieces"]))
        lines += ["  ]", "}"]
        path = os.path.join(BLUEPRINT_DIR, bp["id"] + ".json")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
        print(f"[{KIT}] wrote {os.path.relpath(path, REPO_ROOT)}", flush=True)


# --- export --------------------------------------------------------------------------------------


def signed_volume(part: Part) -> float:
    """Six times nothing clever: the divergence-theorem volume of the faces as wound. Faces open at
    y = 0 add nothing, so for a piece that rests on the ground a positive value means its faces
    point outward; a large negative one means something was wound inside out."""
    total = 0.0
    for idx, _ in part.faces:
        a = part.verts[idx[0]]
        for i in range(1, len(idx) - 1):
            b, c = part.verts[idx[i]], part.verts[idx[i + 1]]
            total += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0])
                      + a[2] * (b[0] * c[1] - b[1] * c[0]))
    return total / 6.0


def generate(out_dir: str, only: set[str] | None) -> int:
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, make in PIECES.items():
        if only and name not in only:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        export(build_object(part, {}), out_dir)
        total += part.tris
        lo, hi = part.bounds()
        print(
            f"[{KIT}] {name}.glb: {part.tris} tris, "
            f"{hi[0] - lo[0]:.2f} x {hi[1] - lo[1]:.2f} x {hi[2] - lo[2]:.2f} studs, "
            f"x[{lo[0]:.2f}, {hi[0]:.2f}] y[{lo[1]:.2f}, {hi[1]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}], "
            f"volume {signed_volume(part):.2f}",
            flush=True,
        )
    print(f"[{KIT}] {total} tris total -> {os.path.relpath(out_dir, REPO_ROOT)}", flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the oldtown-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    parser.add_argument("--only", default="", help="comma list of pieces to build (default: all)")
    parser.add_argument("--write-blueprints", action="store_true", help="also (re)write the kit's 15 blueprints")
    args = parser.parse_args(argv)
    only = {name for name in args.only.split(",") if name} or None
    status = generate(args.out, only)
    if args.write_blueprints:
        write_blueprints()
    return status


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
