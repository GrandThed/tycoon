"""Construction pieces and Main Street shop parts for the Boomtown growing city (M12 wave 2),
generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/boomtown_extras_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/boomtown-extras-kit/Models/GLB format/, the folder
convention every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. The mesh container and the export plumbing come from
garden_kit.py, the geometry helpers from village_extras_kit.py.

Why a custom kit (docs/CITY_GROWTH.md section 4, INTERFACES "M12 wave 2 -- Boomtown"):
- Building sites. city-kit-roads has a cone (0.38 studs at scale 4), a grey barrier block and a
  hoop fence, and nothing else that says "under construction": no framing, scaffold, mixer, lumber
  or hoarding. A Boomtown site is 1950s house-building, so those are generated here.
- Main Street filler shops. city-kit-suburban and city-kit-industrial are finished buildings with
  no wall, door, window or awning pieces; every one of them is already a landmark or a filler
  house, and the suburban roofs leave a lip when anything is stacked on them, so a kit house
  cannot grow in place. The shops are therefore flat-roofed generated bodies that take a second
  storey cleanly: each variant is three pieces, one per additive stage.
- The next-lot sign and the landmark-reveal scaffold, which no kit has.

**Units.** These GLBs are in City Kit units, **1 unit = 4 studs at blueprint scale 4.0**, because
every prop that uses them also places suburban, industrial or roads pieces and a blueprint has one
scale for all of its pieces. The literals below are studs as they come out at scale 4.0 and are
divided by STUDS_PER_UNIT once, at export.

**Frames.** Small props (mixer, stacks, barrier, hoarding, signs) have their origin at the bottom
centre and face -Z. The lot-sized pieces (site-ground-*, frame-*, shop-*, scaffold-ring) are
authored in the lot frame: origin at the lot centre on the ground, front -Z, so a blueprint places
them at [0, 0, 0] and the stages of one shop register exactly.

Colours are texels of the City Kits' colormap.png (suburban, industrial and roads share it), so
the pieces sit in the Boomtown palette. Lumber is the kits' orange wood rather than pale pine: the
Boomtown plot base is a dusty tan (173, 138, 93), which the plot renderer shows paler still, and
cream timber disappears on it. Materials are plain colour factors with no texture, written linear
like garden-kit's; merge_stages.py routes them through palette.py (not an sRGB-factor kit).

Art rules, matching the kits: flat shading, axis-aligned boxes and square-cut timbers, faceted
solids of revolution, chunky toy proportions.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from garden_kit import REPO_ROOT, Part, build_object, export  # noqa: E402
from village_extras_kit import beam, blotch, extrude_x, extrude_z, lathe, place, prism  # noqa: E402

import bpy  # noqa: E402

KIT = "boomtown-extras-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")
STUDS_PER_UNIT = 4.0

Rgb = tuple[int, int, int]
Vec = tuple[float, float, float]

# Texels of the City Kits' colormap.png (suburban unless noted).
WHITE = (255, 255, 255)
WALL = (245, 245, 249)  # the white wall ramp, near its lit end
WALL_SHADE = (220, 220, 233)  # the same ramp, halfway down
LAVENDER = (160, 168, 201)
STONE = (142, 149, 179)
STONE_DARK = (134, 139, 161)
SLATE_LIGHT = (102, 107, 128)
SLATE = (81, 85, 102)
CHARCOAL = (56, 56, 61)
GLASS = (208, 232, 255)
BLUE_PALE = (181, 204, 236)  # industrial
NAVY = (71, 74, 172)  # industrial
GREEN = (97, 203, 139)
GREEN_DARK = (61, 167, 122)
YELLOW = (255, 192, 68)
ORANGE = (255, 126, 68)
RED = (207, 83, 79)
CREAM = (253, 228, 199)
SAND = (242, 191, 153)
PEACH = (250, 174, 138)
WOOD = (241, 151, 108)
TERRACOTTA = (212, 116, 93)
BRICK = (176, 96, 65)
EARTH = (159, 106, 82)  # industrial
EARTH_LIGHT = (193, 135, 113)  # industrial: the lit end of the same ramp

# Lot sizes this kit is built for (width along the street x depth), in studs.
NARROW = (5.0, 8.0)


# --- helpers ------------------------------------------------------------------------------------


def tilted_x(src: Part, rot_x: float, at: Vec) -> Part:
    """src turned rot_x degrees about the X axis (a drum leaning toward the street), then moved."""
    a = math.radians(rot_x)
    c, s = math.cos(a), math.sin(a)
    out = Part(src.name)
    out.verts = [(x + at[0], y * c - z * s + at[1], y * s + z * c + at[2]) for x, y, z in src.verts]
    out.faces = list(src.faces)
    return out


def disc_x(p: Part, x0: float, x1: float, y: float, z: float, r: float, colour: Rgb, seg: int = 8) -> None:
    """A wheel: a faceted disc whose axle runs along X."""
    outline = [(z + r * math.cos(2 * math.pi * (k + 0.5) / seg), y + r * math.sin(2 * math.pi * (k + 0.5) / seg))
               for k in range(seg)]
    extrude_x(p, outline, x0, x1, colour)


def ragged_ground(name: str, hx: float, hz: float, seed: int, patches, straight_sides: bool = False) -> Part:
    """Disturbed earth under a site: a 0.06-stud slab with ragged edges and lighter trodden patches
    0.05 above it. `straight_sides` keeps the X edges from bulging, for lots that stand in a terrace."""
    p = Part(name)
    rng = random.Random(seed)
    points, power = 32, 6.0
    outline = []
    for k in range(points):
        a = 2 * math.pi * (k + 0.5) / points
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** power + abs(s) ** power) ** (-1.0 / power)
        j = 1.0 + rng.uniform(-0.03, 0.03)
        outline.append((hx * r * c * (min(j, 1.0) if straight_sides else j), hz * r * s * j))
    prism(p, outline, 0.0, 0.06, EARTH)
    for cx, cz, rx, rz in patches:
        prism(p, blotch(rng, cx, cz, rx, rz), 0.0, 0.11, EARTH_LIGHT)
    return p


# --- stud framing -------------------------------------------------------------------------------

STUD = 0.2  # every framing timber is 0.2 studs square: thinner ones vanish at the tycoon camera
PLATE = 0.26  # a doubled top plate
SLAB = 0.25  # the concrete slab a frame stands on
# Studs are the kits' orange wood and plates their terracotta: both stand off the plot renderer's
# pale ground (it shows the plot base near (214, 197, 171)). Rafters and roof joists are the paler
# peach, which stands off the base as authored, (173, 138, 93), where orange on tan is the weak
# pairing. Between them a frame reads on either ground.
RAFTER = PEACH


def stud_wall(p: Part, a, b, base: float, height: float, openings=(), spacing: float = 0.62,
              top_plate: bool = True) -> None:
    """An open stud wall from a to b ((x, z), axis-aligned): sole plate, studs, doubled top plate.
    `openings` are (start, end, sill, head) along the wall from a, in studs: no stud stands inside
    one, king studs flank it, a header spans it, and a window (sill > 0) gets a sill on a cripple."""
    ax, az = a
    bx, bz = b
    along_x = abs(bx - ax) >= abs(bz - az)
    length = abs(bx - ax) if along_x else abs(bz - az)
    sign = 1.0 if (bx - ax if along_x else bz - az) >= 0 else -1.0
    h = STUD / 2

    def wbox(t0: float, t1: float, y0: float, y1: float, colour: Rgb, **sides) -> None:
        if along_x:
            x0, x1 = sorted((ax + sign * t0, ax + sign * t1))
            p.box(x0, x1, y0, y1, az - h, az + h, colour, **sides)
        else:
            z0, z1 = sorted((az + sign * t0, az + sign * t1))
            p.box(ax - h, ax + h, y0, y1, z0, z1, colour, **sides)

    top = base + height
    doors = [o for o in openings if o[2] <= 0.0]
    # sole plate, broken at every doorway
    cuts = sorted((o[0], o[1]) for o in doors)
    t = 0.0
    for c0, c1 in cuts + [(length, length)]:
        if c0 - t > 0.01:
            wbox(t, c0, base, base + STUD, TERRACOTTA)
        t = max(t, c1)
    if top_plate:
        wbox(0.0, length, top - PLATE, top, TERRACOTTA, top=SAND)
    stud_top = top - PLATE if top_plate else top
    count = max(1, round((length - STUD) / spacing))
    marks = [h + (length - STUD) * k / count for k in range(count + 1)]
    for o0, o1, _, _ in openings:
        marks = [m for m in marks if not (o0 - h - 0.02 < m < o1 + h + 0.02)]
        marks += [o0 - h, o1 + h]
    for m in sorted(set(round(m, 4) for m in marks)):
        wbox(m - h, m + h, base + STUD, stud_top, WOOD, top=SAND)
    for o0, o1, sill, head in openings:
        wbox(o0, o1, base + head, base + head + PLATE, TERRACOTTA)
        if sill > 0.0:
            wbox(o0, o1, base + sill - STUD, base + sill, TERRACOTTA)
            mid = (o0 + o1) / 2
            wbox(mid - h, mid + h, base + STUD, base + sill - STUD, WOOD)


def slab(p: Part, x0: float, x1: float, z0: float, z1: float) -> None:
    """The concrete slab under a frame: cool grey, so the lumber on it stands off the tan ground."""
    p.box(x0, x1, 0.0, SLAB, z0, z1, STONE_DARK, top=LAVENDER)


def house_frame(name: str, width: float, depth: float, wall: float, rise: float, rafters: int, bays: int,
                door: tuple[float, float], window: tuple[float, float]) -> Part:
    """A house going up, in its own frame (origin at the slab's centre): slab, four stud walls with
    a doorway and a window toward the street, ceiling joists, and a roof that is only part framed:
    `rafters` of the `bays + 1` rafter pairs stand, from the -X end, under a ridge board that runs
    the whole length and rests on a prop at the unfinished end. The ridge runs along X, so the
    street and the camera both see the rafters in a row."""
    p = Part(name)
    hx, hz = width / 2, depth / 2
    slab(p, -hx, hx, -hz, hz)
    wx, wz = hx - 0.25, hz - 0.25  # wall lines
    lx = 2 * wx
    d0, d1 = door
    w0, w1 = window
    ex = wx + STUD / 2  # the street and back walls run corner to corner; the side walls fit between
    stud_wall(p, (-ex, -wz), (ex, -wz), SLAB, wall, openings=((d0, d1, 0.0, 2.05), (w0, w1, 0.85, 2.05)))
    stud_wall(p, (-ex, wz), (ex, wz), SLAB, wall, openings=((lx * 0.3, lx * 0.3 + 1.0, 0.85, 2.05),))
    for x in (-wx, wx):
        stud_wall(p, (x, -wz + STUD / 2), (x, wz - STUD / 2), SLAB, wall)
    eave = SLAB + wall
    ridge = eave + rise
    for k in range(bays + 1):
        x = -wx + lx * k / bays
        if k < rafters:
            beam(p, (x, eave + 0.02, -wz - 0.02), (x, eave + 0.02, wz + 0.02), 0.16, 0.2, WOOD)  # ceiling joist
            for sz in (-1, 1):
                beam(p, (x, eave + 0.05, sz * (wz + 0.3)), (x, ridge, 0.0), 0.16, 0.22, RAFTER, ends=SAND)
    beam(p, (-wx - 0.15, ridge - 0.02, 0.0), (wx + 0.15, ridge - 0.02, 0.0), 0.16, 0.26, TERRACOTTA, ends=SAND)
    p.box(wx - 0.09, wx + 0.09, eave, ridge - 0.14, -0.09, 0.09, WOOD)  # the prop under the free end
    return p


def make_frame_house_small() -> Part:
    """SiteSmall's house: a 3.4 x 3.0 slab, 2.45-stud walls, ridge at 4.15; 3 of 5 rafter pairs up."""
    return house_frame("frame-house-small", 3.4, 3.0, 2.45, 1.45, 3, 4, (0.45, 1.3), (1.75, 2.6))


def make_frame_house_medium() -> Part:
    """SiteMedium's house: a 5.6 x 4.4 slab, 2.75-stud walls, ridge at 5.0; 4 of 7 rafter pairs up."""
    return house_frame("frame-house-medium", 5.6, 4.4, 2.75, 2.0, 4, 6, (0.6, 1.6), (2.4, 4.3))


# The narrow lot's building line, shared by the shop shell and the three shops: the body stands
# 0.9 studs back from the street edge (room for an awning or a scaffold) and leaves a 2.1-stud yard.
SHOP_HX = 2.45
SHOP_FRONT = -3.1
SHOP_BACK = 1.9
SHOP_H1 = 3.5  # ground-floor roof deck
SHOP_H2 = 6.8  # upper-floor roof deck
CHIMNEY_RISE = (0.95, 1.15)  # a chimney's height above the ground-floor and the upper-floor deck
STACK_A = (-1.5, 1.0)  # chimney centres (x, z) in the lot frame; shop b has a roof ventilator instead
STACK_C = (1.4, 0.9)


def make_frame_shop() -> Part:
    """SiteNarrow's shop shell, in the lot frame: a slab on the shops' own building line, a framed
    front with the shop window and doorway already cut and the false front's cripples above it, stud
    side and back walls and the flat roof's joists. Everything stays inside x +-2.35, so two shells,
    or a shell and a finished shop, stand shoulder to shoulder."""
    p = Part("frame-shop")
    hx = 2.35
    slab(p, -hx, hx, SHOP_FRONT, SHOP_BACK)
    wx, zf, zb = hx - 0.15, SHOP_FRONT + 0.15, SHOP_BACK - 0.15
    wall = SHOP_H1 - SLAB
    ex = wx + STUD / 2
    stud_wall(p, (-ex, zf), (ex, zf), SLAB, wall, openings=((0.4, 1.4, 0.0, 2.2), (1.8, 4.2, 0.6, 2.2)))
    stud_wall(p, (-ex, zb), (ex, zb), SLAB, wall, openings=((3.0, 3.9, 0.0, 2.2),), spacing=0.8)
    for x in (-wx, wx):
        stud_wall(p, (x, zf + STUD / 2), (x, zb - STUD / 2), SLAB, wall, spacing=0.75)
    for k in range(5):  # roof joists, front to back
        z = zf + 0.55 + (zb - zf - 1.1) * k / 4
        beam(p, (-wx - 0.02, SHOP_H1 + 0.1, z), (wx + 0.02, SHOP_H1 + 0.1, z), 0.16, 0.2, RAFTER, ends=SAND)
    stud_wall(p, (-ex, zf), (ex, zf), SHOP_H1, 1.1, spacing=0.75)  # the false front's cripples, to 4.6
    return p


# --- site props ---------------------------------------------------------------------------------


def make_cement_mixer() -> Part:
    """A towed drum mixer, 1.45 x 1.9 x 2.2 studs: a yellow drum with an orange band, tipped 40
    degrees toward -Z, in a slate yoke on two wheels, with the engine box behind. Oversized against
    the kits' 1-stud doors on purpose: it is the one object that says "building site" at a glance."""
    p = Part("cement-mixer")
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.56, sx * 0.7))
        disc_x(p, x0, x1, 0.36, 0.15, 0.36, CHARCOAL)
        x0, x1 = sorted((sx * 0.69, sx * 0.73))
        disc_x(p, x0, x1, 0.36, 0.15, 0.14, SLATE_LIGHT, seg=6)
        x0, x1 = sorted((sx * 0.44, sx * 0.54))
        p.box(x0, x1, 0.5, 1.3, 0.02, 0.2, SLATE)
    p.box(-0.56, 0.56, 0.3, 0.42, 0.09, 0.21, SLATE)
    p.box(-0.4, 0.4, 0.4, 0.55, -0.45, 0.9, SLATE)
    p.box(-0.07, 0.07, 0.0, 0.4, -0.42, -0.3, SLATE)
    beam(p, (0.0, 0.5, 0.88), (0.0, 0.16, 1.4), 0.1, 0.1, SLATE_LIGHT)
    p.box(-0.3, 0.3, 0.55, 1.0, 0.42, 0.88, ORANGE, top=CHARCOAL)
    drum = Part("drum")
    profile = [(0.28, 0.0), (0.56, 0.2), (0.6, 0.46), (0.6, 0.62), (0.4, 1.08), (0.4, 1.16), (0.3, 1.1)]
    lathe(drum, profile, [YELLOW, YELLOW, ORANGE, YELLOW, SLATE, CHARCOAL], seg=8, phase=math.pi / 8)
    place(p, tilted_x(drum, -40.0, (0.0, 0.78, 0.26)))
    return p


def make_lumber_stack() -> Part:
    """Framing lumber on two bearers, 3.0 x 0.7 x 1.15 studs along X, end grain pale."""
    p = Part("lumber-stack")
    length, bearer = 2.9, 0.16
    for x in (-0.95, 0.95):
        p.box(x - 0.12, x + 0.12, 0.0, bearer, -0.58, 0.58, BRICK)
    tones = (WOOD, PEACH, WOOD, TERRACOTTA)
    rng = random.Random(27)
    y = bearer
    for layer in range(4):
        count = 3 if layer < 3 else 2
        for i in range(count):
            z0 = -0.57 + i * 0.385 + (0.19 if count == 2 else 0.0)
            dx = rng.uniform(-0.05, 0.05)
            p.box(-length / 2 + dx, length / 2 + dx, y, y + 0.14, z0, z0 + 0.37, tones[(layer + i) % 4],
                  left=CREAM, right=CREAM, top=SAND if layer == 3 else tones[(layer + i) % 4])
        y += 0.14
    return p


def make_brick_stack() -> Part:
    """Bricks on a pallet, 1.4 x 1.0 x 1.0 studs: two courses and a broken third, in two reds that
    swap between a course's sides and its top, so the stack reads as stacked, not as one block."""
    p = Part("brick-stack")
    for z in (-0.38, 0.38):
        p.box(-0.7, 0.7, 0.0, 0.1, z - 0.09, z + 0.09, BRICK)
    p.box(-0.7, 0.7, 0.1, 0.18, -0.5, 0.5, SAND)
    p.box(-0.62, 0.62, 0.18, 0.5, -0.44, 0.44, RED, top=TERRACOTTA)
    p.box(-0.6, 0.6, 0.5, 0.8, -0.42, 0.42, TERRACOTTA, top=RED)
    p.box(-0.6, 0.02, 0.8, 1.0, -0.42, 0.1, RED, top=TERRACOTTA)
    return p


def make_sawhorse() -> Part:
    """A trestle with a board lying across it, 1.95 x 0.9 x 0.85 studs."""
    p = Part("sawhorse")
    length, height = 1.5, 0.84
    p.box(-length / 2, length / 2, height - 0.16, height, -0.09, 0.09, TERRACOTTA)
    for x in (-0.55, 0.55):
        for sz in (-1, 1):
            beam(p, (x + math.copysign(0.06, x), 0.04, sz * 0.36), (x, height - 0.1, 0.0), 0.12, 0.12, BRICK,
                 up=(1.0, 0.0, 0.0))
    board = Part("board")
    board.box(-0.95, 0.95, 0.0, 0.08, -0.2, 0.2, WOOD, left=CREAM, right=CREAM, top=SAND)
    place(p, board, 7.0, (0.0, height, 0.0))
    return p


def make_barrier() -> Part:
    """A 1950s street barrier, 2.6 x 1.15 x 0.8 studs: a red and white striped plank and a white
    lower rail on two A-frame trestles. It stands along X, across a site's street side."""
    p = Part("barrier")
    for sx in (-1, 1):
        x = sx * 1.0
        for sz in (-1, 1):
            beam(p, (x, 0.03, sz * 0.33), (x, 1.12, sz * 0.03), 0.12, 0.12, SLATE, up=(1.0, 0.0, 0.0))
    stripes = 6
    w = 2.6 / stripes
    for i in range(stripes):
        x0 = -1.3 + i * w
        p.box(x0, x0 + w, 0.78, 1.06, -0.12, -0.04, RED if i % 2 == 0 else WHITE)
    p.box(-1.2, 1.2, 0.36, 0.5, -0.2, -0.13, WHITE)
    return p


def make_hoarding() -> Part:
    """One hoarding panel, 2.4 x 1.75 x 0.26 studs: white boards between slate posts under a red
    top band, the white-and-red of every Boomtown site and sale board. Panels butt end to end."""
    p = Part("hoarding")
    half, height = 1.2, 1.6
    boards = 6
    w = 2 * half / boards
    for i in range(boards):
        x0 = -half + i * w
        face = WHITE if i % 2 == 0 else WALL_SHADE  # alternate boards a shade darker, so it reads as boards
        p.box(x0, x0 + w, 0.08, height - 0.3, -0.05, 0.05, WALL, front=face, back=face)
    p.box(-half, half, height - 0.3, height, -0.07, 0.07, RED)
    for x in (-half + 0.1, half - 0.1):
        p.box(x - 0.09, x + 0.09, 0.0, height + 0.15, 0.05, 0.19, SLATE)
    return p


def make_sold_stake() -> Part:
    """A stake with a red SOLD board and a white band, 1.0 x 1.6 x 0.23 studs, facing -Z."""
    p = Part("sold-stake")
    p.box(-0.07, 0.07, 0.0, 1.6, 0.0, 0.14, BRICK)
    p.box(-0.5, 0.5, 0.9, 1.5, -0.06, 0.0, RED)
    p.box(-0.36, 0.36, 1.12, 1.28, -0.09, -0.06, WHITE)
    return p


def make_scaffold_bay() -> Part:
    """Steel-pipe scaffold across a shop front, 4.6 x 4.4 x 0.9 studs, centred on its own middle:
    six slate standards in two rows, ledgers at two lifts, a plank deck on the lower lift with a
    guard rail above it, one diagonal brace per bay toward the street."""
    p = Part("scaffold-bay")
    hx, hz, height, pipe = 2.2, 0.32, 4.4, 0.16
    for x in (-hx, 0.0, hx):
        for z in (-hz, hz):
            p.box(x - pipe / 2, x + pipe / 2, 0.0, height, z - pipe / 2, z + pipe / 2, SLATE, top=SLATE_LIGHT)
    lifts = (2.1, 4.0)
    for y in lifts:
        for z in (-hz, hz):
            beam(p, (-hx - 0.1, y, z), (hx + 0.1, y, z), pipe, pipe, SLATE)
        for x in (-hx, 0.0, hx):
            beam(p, (x, y - 0.14, -hz - 0.08), (x, y - 0.14, hz + 0.08), pipe * 0.8, pipe * 0.8, SLATE_LIGHT)
    beam(p, (-hx - 0.1, 3.1, -hz), (hx + 0.1, 3.1, -hz), pipe * 0.8, pipe * 0.8, SLATE_LIGHT)  # guard rail
    deck = lifts[0] + 0.08
    p.box(-hx - 0.08, hx + 0.08, deck, deck + 0.1, -hz - 0.06, hz + 0.06, WOOD, front=SAND, left=CREAM, right=CREAM)
    zb = -hz - pipe / 2 - 0.05
    beam(p, (-hx + 0.08, 0.15, zb), (-0.08, lifts[0] - 0.12, zb), 0.12, 0.1, SLATE_LIGHT, up=(0.0, 0.0, 1.0))
    beam(p, (0.08, lifts[0] + 0.3, zb), (hx - 0.08, lifts[1] - 0.12, zb), 0.12, 0.1, SLATE_LIGHT, up=(0.0, 0.0, 1.0))
    return p


def make_ladder() -> Part:
    """A 4.1-stud ladder leaning back 15 degrees: feet at the origin, top 3.96 up and 1.06 toward +Z."""
    p = Part("ladder")
    length, tilt = 4.1, math.radians(15.0)
    top_y, top_z = length * math.cos(tilt), length * math.sin(tilt)
    half = 0.36
    for sx in (-1, 1):
        beam(p, (sx * half, 0.02, 0.0), (sx * half, top_y, top_z), 0.13, 0.13, BRICK)
    for i in range(6):
        f = (i + 0.7) / 6.3
        beam(p, (-half, top_y * f, top_z * f), (half, top_y * f, top_z * f), 0.09, 0.09, TERRACOTTA)
    return p


def make_wheelbarrow() -> Part:
    """A green steel barrow, 0.85 x 0.8 x 1.95 studs, wheel toward -Z, handles toward +Z."""
    p = Part("wheelbarrow")
    p.frustum(-0.26, 0.26, -0.45, 0.3, 0.34, -0.42, 0.42, -0.62, 0.42, 0.82, GREEN_DARK, top=CHARCOAL)
    disc_x(p, -0.07, 0.07, 0.24, -0.62, 0.24, CHARCOAL)
    for sx in (-1, 1):
        beam(p, (sx * 0.1, 0.24, -0.62), (sx * 0.34, 0.6, 1.1), 0.08, 0.08, BRICK)
        p.box(sx * 0.3 - 0.04, sx * 0.3 + 0.04, 0.0, 0.42, 0.22, 0.3, SLATE)
    return p


def make_gravel_pile() -> Part:
    """A heap of aggregate by the mixer, 1.6 studs across and 0.62 tall: cool grey on the tan."""
    p = Part("gravel-pile")
    lathe(p, [(0.8, 0.0), (0.52, 0.3), (0.2, 0.55), (0.0, 0.62)], [STONE_DARK, STONE, LAVENDER], seg=7, phase=0.4)
    return p


def make_cone() -> Part:
    """A traffic cone, 0.5 x 0.9 x 0.5 studs: orange with a white band on a square foot. The
    roads-kit cone is 0.38 studs at scale 4 and cannot be seen from the tycoon camera."""
    p = Part("cone")
    p.box(-0.25, 0.25, 0.0, 0.07, -0.25, 0.25, ORANGE)
    lathe(p, [(0.19, 0.07), (0.14, 0.38), (0.1, 0.6), (0.04, 0.9)], [ORANGE, WHITE, ORANGE], seg=6)
    return p


def make_site_ground_small() -> Part:
    """Disturbed earth under a 6 x 6 site, 5.8 studs square."""
    return ragged_ground("site-ground-small", 2.84, 2.84, 171,
                         ((-1.0, 0.9, 1.0, 0.7), (1.2, -1.0, 0.8, 0.6), (0.6, 1.6, 0.6, 0.45)))


def make_site_ground_medium() -> Part:
    """Disturbed earth under a 9 x 9 site, 8.8 studs square."""
    return ragged_ground("site-ground-medium", 4.3, 4.3, 172,
                         ((-1.8, 1.4, 1.5, 1.0), (2.0, -1.6, 1.2, 0.9), (1.0, 2.6, 0.9, 0.6), (-2.6, -2.4, 0.8, 0.6)))


def make_site_ground_narrow() -> Part:
    """Disturbed earth under a 5 x 8 terraced site, 4.85 x 7.7 studs with straight sides."""
    return ragged_ground("site-ground-narrow", 2.42, 3.82, 173,
                         ((-0.8, 3.0, 0.9, 0.6), (0.9, 2.7, 0.7, 0.5), (0.2, -3.5, 1.2, 0.3)), straight_sides=True)


def make_scaffold_ring() -> Part:
    """Pipe scaffold round a 9 x 9-stud slot, 7.6 studs tall, hollow in the middle so the landmark
    rising inside stays in view: eight slate standards, ledgers and plank decks at two lifts, guard
    rails on top, braces on the outside, and a white hoarding skirt with a red band round the foot,
    open at the street. Nothing crosses the middle (the decks' inner edge is at 3.85), and all of it
    stays inside +-4.5, so the client's footprint / 9 scale fits it to any slot. Steel and hoarding,
    where the Village reveal is all timber."""
    p = Part("scaffold-ring")
    e, height, pipe = 4.2, 7.6, 0.2
    for sx in (-1, 0, 1):
        for sz in (-1, 0, 1):
            if (sx, sz) != (0, 0):
                x, z = sx * e, sz * e
                p.box(x - pipe / 2, x + pipe / 2, 0.0, height, z - pipe / 2, z + pipe / 2, SLATE, top=SLATE_LIGHT)
    lifts = (2.7, 5.4)
    for rot in (0, 90, 180, 270):
        side = Part("side")
        for y in lifts:
            beam(side, (-e - pipe / 2, y, -e), (e + pipe / 2, y, -e), pipe * 0.9, pipe * 0.9, SLATE)
            # boards stop short of the corner standards, so two faces' boards never overlap
            side.box(-e + 0.36, e - 0.36, y + 0.1, y + 0.2, -e - 0.2, -e + 0.35, WOOD, front=SAND, top=PEACH)
        for y in (6.5, 7.45):
            beam(side, (-e - pipe / 2, y, -e), (e + pipe / 2, y, -e), pipe * 0.7, pipe * 0.7, SLATE_LIGHT)
        zb = -e - pipe / 2 - 0.05
        beam(side, (-e + 0.1, 1.75, zb), (-0.12, lifts[0] - 0.12, zb), 0.13, 0.1, SLATE_LIGHT, up=(0.0, 0.0, 1.0))
        beam(side, (0.12, lifts[0] + 0.3, zb), (e - 0.1, lifts[1] - 0.12, zb), 0.13, 0.1, SLATE_LIGHT,
             up=(0.0, 0.0, 1.0))
        # the hoarding skirt: the front (rot 0) leaves a gateway in the middle bay
        z0, z1 = -e - 0.26, -e - 0.16
        reach = e + 0.26 if rot in (0, 180) else e + 0.16
        spans = ((-reach, -1.1), (1.1, reach)) if rot == 0 else ((-reach, reach),)
        for x0, x1 in spans:
            side.box(x0, x1, 0.06, 1.25, z0, z1, WHITE, back=WALL)
            side.box(x0, x1, 1.25, 1.6, z0 - 0.02, z1 + 0.02, RED)
        place(p, side, rot)
    return p


def make_lot_sign() -> Part:
    """A "LOT FOR SALE" board, 1.9 x 3.4 x 0.3 studs: a white board with a red header between two
    brown posts, two dark rules where the lettering would be, and a yellow rider hung below. Both
    faces are dressed, because the next lot can lie on either side of a street."""
    p = Part("lot-sign")
    for sx in (-1, 1):
        x = sx * 0.84
        p.box(x - 0.1, x + 0.1, 0.0, 3.3, -0.1, 0.1, BRICK)
        p.box(x - 0.13, x + 0.13, 3.3, 3.4, -0.13, 0.13, TERRACOTTA)
    p.box(-0.74, 0.74, 1.75, 2.8, -0.06, 0.06, WHITE)
    p.box(-0.78, 0.78, 2.8, 3.22, -0.09, 0.09, RED)
    p.box(-0.6, 0.6, 1.2, 1.6, -0.05, 0.05, YELLOW)
    for x in (-0.45, 0.45):
        p.box(x - 0.03, x + 0.03, 1.6, 1.75, -0.02, 0.02, SLATE)
    for facing in (-1, 1):

        def rule(x0: float, x1: float, y0: float, y1: float, face: float, colour: Rgb) -> None:
            z0, z1 = sorted((facing * face, facing * (face + 0.025)))
            p.box(x0, x1, y0, y1, z0, z1, colour)

        rule(-0.55, 0.55, 2.38, 2.56, 0.06, SLATE)
        rule(-0.55, 0.2, 2.02, 2.17, 0.06, SLATE_LIGHT)
        rule(-0.42, 0.42, 2.93, 3.08, 0.09, WHITE)
        rule(-0.4, 0.4, 1.33, 1.47, 0.05, RED)
    return p


# --- Main Street shops ----------------------------------------------------------------------------
#
# Three anonymous shops for the 5 x 8 narrow lot, each built from one piece per stage, all in the
# lot frame. Stages are additive, so each later piece is made to swallow the earlier ones:
# - stage 0, shop-<v>-ground: a one-storey flat-roofed body with a plain front (3.75 studs);
# - stage 1, shop-<v>-front: a false-front parapet standing on the front wall, a sign board on it
#   and an awning over the window (5.2 to 5.7);
# - stage 2, shop-<v>-upper: a second storey 0.03 proud of the body on every side, so the roof
#   kerb and the false front end up inside it. The sign board is 0.14 proud, so it stays in view
#   as the fascia between the floors; a taller sign goes on top (8.55 to 8.7).
# Side walls are blank and stand 0.05 inside the lot line: shops meet in a terrace. All colour is
# on the front: brick red (a), pale blue (b) and cream (c).


def window(p: Part, x0: float, x1: float, y0: float, y1: float, z: float, facing: int, frame: Rgb = SLATE,
           mullions: int = 0, bar: bool = False) -> None:
    """A framed pane on a wall whose outer face is at z and faces `facing` (-1 = -Z, 1 = +Z)."""

    def zbox(a0, a1, b0, b1, proud, colour):
        za, zb = sorted((z, z + facing * proud))
        p.box(a0, a1, b0, b1, za, zb, colour)

    m = 0.11
    zbox(x0, x1, y0, y1, 0.06, frame)
    zbox(x0 + m, x1 - m, y0 + m, y1 - m, 0.085, GLASS)
    for k in range(mullions):
        x = x0 + (x1 - x0) * (k + 1) / (mullions + 1)
        zbox(x - 0.045, x + 0.045, y0 + m, y1 - m, 0.11, frame)
    if bar:
        y = y0 + (y1 - y0) * 0.68
        zbox(x0 + m, x1 - m, y - 0.045, y + 0.045, 0.11, frame)


def door(p: Part, x0: float, x1: float, y1: float, z: float, facing: int, leaf: Rgb, frame: Rgb = SLATE,
         glazed: bool = True) -> None:
    def zbox(a0, a1, b0, b1, proud, colour):
        za, zb = sorted((z, z + facing * proud))
        p.box(a0, a1, b0, b1, za, zb, colour)

    zbox(x0, x1, 0.0, y1, 0.06, frame)
    zbox(x0 + 0.1, x1 - 0.1, 0.0, y1 - 0.1, 0.085, leaf)
    if glazed:
        zbox(x0 + 0.24, x1 - 0.24, y1 * 0.5, y1 - 0.26, 0.11, GLASS)


def chimney(p: Part, x: float, z: float, deck: float, rise: float) -> None:
    """A brick stack with a slab cap and a flue pot, standing `rise` above the roof deck. Its top
    centre is where the smoke config puts a plume."""
    top = deck + rise
    p.box(x - 0.32, x + 0.32, deck, top - 0.2, z - 0.32, z + 0.32, BRICK)
    p.box(x - 0.38, x + 0.38, top - 0.2, top - 0.1, z - 0.38, z + 0.38, STONE_DARK, top=LAVENDER)
    p.box(x - 0.16, x + 0.16, top - 0.1, top, z - 0.16, z + 0.16, SLATE, top=CHARCOAL)


def shop_ground(name: str, facade: Rgb, trim: Rgb, leaf: Rgb, layout: str, stack=None) -> Part:
    p = Part(name)
    hx, zf, zb = SHOP_HX, SHOP_FRONT, SHOP_BACK
    # the pavement apron runs the full lot width, so a terrace's aprons join into one sidewalk
    p.box(-NARROW[0] / 2, NARROW[0] / 2, 0.0, 0.06, -NARROW[1] / 2, zf, LAVENDER)
    p.box(-hx, hx, 0.0, SHOP_H1, zf, zb, WALL, front=facade, top=SLATE)
    kerb, k = SHOP_H1 + 0.25, 0.18
    p.box(-hx, hx, SHOP_H1, kerb, zf, zf + k, trim)
    p.box(-hx, hx, SHOP_H1, kerb, zb - k, zb, LAVENDER)
    for x0, x1 in ((-hx, -hx + k), (hx - k, hx)):
        p.box(x0, x1, SHOP_H1, kerb, zf + k, zb - k, LAVENDER)
    riser = 0.5

    def shop_window(x0: float, x1: float, mullions: int, bar: bool = False) -> None:
        p.box(x0, x1, 0.0, riser, zf - 0.07, zf, trim)
        window(p, x0, x1, riser, 2.4, zf, -1, mullions=mullions, bar=bar)

    if layout == "centre":
        door(p, -0.5, 0.5, 2.4, zf, -1, leaf)
        shop_window(-2.15, -0.72, 0)
        shop_window(0.72, 2.15, 0)
    elif layout == "left":
        door(p, -2.1, -1.1, 2.4, zf, -1, leaf)
        shop_window(-0.8, 2.15, 2)
    else:
        door(p, 1.1, 2.1, 2.4, zf, -1, leaf)
        shop_window(-2.15, 0.8, 1, bar=True)
    # the back: a plain service door and a small window, for anyone who walks round
    door(p, 0.9, 1.8, 2.2, zb, 1, SLATE_LIGHT, glazed=False)
    window(p, -1.6, -0.5, 1.2, 2.2, zb, 1)
    if stack:
        chimney(p, stack[0], stack[1], SHOP_H1, CHIMNEY_RISE[0])
    return p


def striped_awning(p: Part, x0: float, x1: float, colours, stripes: int) -> None:
    """A canvas awning over the shop window: a striped slope from the wall at 3.1 down to 2.45 at
    0.82 out, a valance along its front edge and a closed cheek at each end."""
    zw = SHOP_FRONT
    zf = zw - 0.82
    yt, yf, t = 3.1, 2.45, 0.08
    w = (x1 - x0) / stripes
    for i in range(stripes):
        xa, xb = x0 + i * w, x0 + (i + 1) * w
        c = colours[i % 2]
        p.hexa([(xa, yf - t, zf), (xb, yf - t, zf), (xb, yt - t, zw), (xa, yt - t, zw),
                (xa, yf, zf), (xb, yf, zf), (xb, yt, zw), (xa, yt, zw)], c)
        p.box(xa, xb, yf - 0.34, yf - t, zf, zf + 0.06, c)
    for xa, xb in ((x0 - 0.05, x0), (x1, x1 + 0.05)):
        extrude_x(p, [(zw, yt), (zf, yf), (zf, yf - t), (zw, yf - t)], xa, xb, colours[1])


def flat_canopy(p: Part, x0: float, x1: float, colour: Rgb, edge: Rgb) -> None:
    """A rigid 1950s canopy: a slab hung 0.85 out from the wall on two tie rods."""
    zw = SHOP_FRONT
    zf = zw - 0.85
    p.box(x0, x1, 2.72, 2.9, zf, zw, colour)
    p.box(x0 - 0.03, x1 + 0.03, 2.66, 2.96, zf - 0.04, zf + 0.04, edge)
    for x in (x0 + 0.5, x1 - 0.5):
        beam(p, (x, 2.92, zf + 0.12), (x, 3.42, zw), 0.06, 0.06, SLATE)


def sign_board(p: Part, x0: float, x1: float, board: Rgb, band: Rgb) -> None:
    """The fascia sign, 0.14 proud of the front wall: a board with a lettering band across it."""
    zw = SHOP_FRONT
    p.box(x0, x1, 3.72, 4.82, zw - 0.14, zw, board)
    p.box(x0 + 0.22, x1 - 0.22, 4.0, 4.54, zw - 0.18, zw - 0.14, band)


def parapet(p: Part, x0: float, x1: float, top: float, facade: Rgb, cap: Rgb) -> None:
    """One block of the false front: 0.3 thick on the front wall, with a cap."""
    zw = SHOP_FRONT
    p.box(x0, x1, SHOP_H1, top, zw, zw + 0.3, facade, back=WALL)
    p.box(x0, x1, top, top + 0.13, zw, zw + 0.34, cap)


def upper(p: Part, facade: Rgb, trim: Rgb, windows, stack=None) -> None:
    """The second storey: 0.03 proud of the ground floor all round, front windows above the fascia
    sign, one window at the back, a cornice at the street and a kerb round the rest of the roof.
    `stack` continues the ground floor's chimney above the new roof."""
    e = 0.03
    hx, zf, zb = SHOP_HX + e, SHOP_FRONT - e, SHOP_BACK + e
    p.box(-hx, hx, SHOP_H1, SHOP_H2, zf, zb, WALL, front=facade, top=SLATE)
    for x0, x1, mullions in windows:
        window(p, x0, x1, 5.15, 6.35, zf, -1, mullions=mullions)
        p.box(x0 - 0.06, x1 + 0.06, 5.02, 5.15, zf - 0.1, zf, trim)
    window(p, -0.7, 0.7, 5.1, 6.2, zb, 1, mullions=1)
    kerb, k = SHOP_H2 + 0.25, 0.18
    p.box(-hx, hx, SHOP_H2 - 0.08, kerb + 0.05, zf - 0.09, zf + 0.22, trim)
    p.box(-hx, hx, SHOP_H2, kerb, zb - k, zb, LAVENDER)
    for x0, x1 in ((-hx, -hx + k), (hx - k, hx)):
        p.box(x0, x1, SHOP_H2, kerb, zf + 0.22, zb - k, LAVENDER)
    if stack:
        chimney(p, stack[0], stack[1], SHOP_H2, CHIMNEY_RISE[1])


def make_shop_a_ground() -> Part:
    """Shop a, stage 0: brick-red front, white trim, a centre door between two windows."""
    return shop_ground("shop-a-ground", TERRACOTTA, WHITE, GREEN_DARK, "centre", stack=STACK_A)


def make_shop_a_front() -> Part:
    """Shop a, stage 1: a level false front to 5.23, a green and white striped awning, a yellow sign."""
    p = Part("shop-a-front")
    parapet(p, -SHOP_HX, SHOP_HX, 5.1, TERRACOTTA, WHITE)
    striped_awning(p, -2.25, 2.25, (GREEN, WHITE), 9)
    sign_board(p, -1.9, 1.9, YELLOW, SLATE)
    return p


def make_shop_a_upper() -> Part:
    """Shop a, stage 2: a second storey with two windows and a yellow roof sign with a dark band, 8.7."""
    p = Part("shop-a-upper")
    upper(p, TERRACOTTA, WHITE, ((-1.9, -0.5, 1), (0.5, 1.9, 1)), stack=STACK_A)
    z = SHOP_FRONT + 0.3
    for x in (-1.2, 1.2):
        p.box(x - 0.08, x + 0.08, SHOP_H2 + 0.25, 7.6, z - 0.08, z + 0.08, SLATE)
    p.box(-1.7, 1.7, 7.5, 8.7, z - 0.2, z - 0.08, YELLOW, back=SLATE_LIGHT)
    p.box(-1.45, 1.45, 7.84, 8.36, z - 0.24, z - 0.2, SLATE)
    return p


def ventilator(p: Part, deck: float) -> None:
    """Shop b's roof ventilator: a louvred box under a slate lid, 0.62 above the deck."""
    p.box(0.6, 1.5, deck, deck + 0.5, 0.2, 1.1, LAVENDER, top=SLATE_LIGHT)
    p.box(0.5, 1.6, deck + 0.5, deck + 0.62, 0.1, 1.2, SLATE)


def make_shop_b_ground() -> Part:
    """Shop b, stage 0: pale blue front, navy trim, the door at the left of one wide window, and a
    roof ventilator instead of a chimney."""
    p = shop_ground("shop-b-ground", BLUE_PALE, NAVY, NAVY, "left")
    ventilator(p, SHOP_H1)
    return p


def make_shop_b_front() -> Part:
    """Shop b, stage 1: a stepped false front to 5.73, a yellow flat canopy, a yellow sign."""
    p = Part("shop-b-front")
    for x0, x1 in ((-SHOP_HX, -1.15), (1.15, SHOP_HX)):
        parapet(p, x0, x1, 4.95, BLUE_PALE, NAVY)
    parapet(p, -1.15, 1.15, 5.6, BLUE_PALE, NAVY)
    flat_canopy(p, -2.3, 2.3, YELLOW, WHITE)
    sign_board(p, -1.9, 1.9, WHITE, NAVY)
    return p


def make_shop_b_upper() -> Part:
    """Shop b, stage 2: a second storey with three windows and a yellow blade sign at the corner, 8.55."""
    p = Part("shop-b-upper")
    upper(p, BLUE_PALE, NAVY, ((-2.0, -1.0, 0), (-0.5, 0.5, 0), (1.0, 1.65, 0)))
    ventilator(p, SHOP_H2)
    zw = SHOP_FRONT - 0.03
    x0, x1 = 1.82, 2.0
    p.box(x0, x1, 4.95, 8.4, zw - 0.82, zw - 0.12, YELLOW, front=NAVY)
    p.box(x0 - 0.03, x1 + 0.03, 8.4, 8.55, zw - 0.86, zw - 0.08, NAVY)
    for xa, xb in ((x0 - 0.03, x0), (x1, x1 + 0.03)):  # the lettering band, on both faces
        p.box(xa, xb, 5.4, 7.95, zw - 0.56, zw - 0.38, NAVY)
    for y in (5.2, 6.45):
        p.box(x0 + 0.03, x1 - 0.03, y, y + 0.12, zw - 0.12, zw, SLATE)
    return p


def make_shop_c_ground() -> Part:
    """Shop c, stage 0: cream front, red trim, the door at the right of a barred window."""
    return shop_ground("shop-c-ground", CREAM, RED, RED, "right", stack=STACK_C)


def make_shop_c_front() -> Part:
    """Shop c, stage 1: a false front with end piers to 5.58, a red and white awning, a red sign."""
    p = Part("shop-c-front")
    parapet(p, -1.95, 1.95, 4.9, CREAM, RED)
    for x0, x1 in ((-SHOP_HX, -1.95), (1.95, SHOP_HX)):
        parapet(p, x0, x1, 5.45, CREAM, RED)
    striped_awning(p, -2.25, 2.25, (RED, WHITE), 9)
    sign_board(p, -1.75, 1.75, RED, WHITE)
    return p


def make_shop_c_upper() -> Part:
    """Shop c, stage 2: a second storey with two windows under a stepped pediment that carries a red
    roundel, 8.6."""
    p = Part("shop-c-upper")
    upper(p, CREAM, RED, ((-1.9, -0.6, 1), (0.6, 1.9, 1)), stack=STACK_C)
    zf = SHOP_FRONT - 0.03
    top = SHOP_H2 + 0.3
    p.box(-1.5, 1.5, top, top + 0.8, zf, zf + 0.3, CREAM, back=WALL)
    p.box(-1.5, 1.5, top + 0.8, top + 0.93, zf - 0.03, zf + 0.33, RED)
    p.box(-0.7, 0.7, top + 0.93, top + 1.37, zf, zf + 0.3, CREAM, back=WALL)
    p.box(-0.7, 0.7, top + 1.37, top + 1.5, zf - 0.03, zf + 0.33, RED)
    for r, z0, colour in ((0.4, zf - 0.07, RED), (0.19, zf - 0.1, WHITE)):
        ring = [(r * math.cos(2 * math.pi * (k + 0.5) / 8), top + 0.42 + r * math.sin(2 * math.pi * (k + 0.5) / 8))
                for k in range(8)]
        extrude_z(p, ring, z0, zf, colour)
    return p


PIECES = {
    "site-ground-small": make_site_ground_small,
    "site-ground-medium": make_site_ground_medium,
    "site-ground-narrow": make_site_ground_narrow,
    "frame-house-small": make_frame_house_small,
    "frame-house-medium": make_frame_house_medium,
    "frame-shop": make_frame_shop,
    "cement-mixer": make_cement_mixer,
    "lumber-stack": make_lumber_stack,
    "brick-stack": make_brick_stack,
    "sawhorse": make_sawhorse,
    "barrier": make_barrier,
    "hoarding": make_hoarding,
    "sold-stake": make_sold_stake,
    "scaffold-bay": make_scaffold_bay,
    "ladder": make_ladder,
    "wheelbarrow": make_wheelbarrow,
    "gravel-pile": make_gravel_pile,
    "cone": make_cone,
    "scaffold-ring": make_scaffold_ring,
    "lot-sign": make_lot_sign,
    "shop-a-ground": make_shop_a_ground,
    "shop-a-front": make_shop_a_front,
    "shop-a-upper": make_shop_a_upper,
    "shop-b-ground": make_shop_b_ground,
    "shop-b-front": make_shop_b_front,
    "shop-b-upper": make_shop_b_upper,
    "shop-c-ground": make_shop_c_ground,
    "shop-c-front": make_shop_c_front,
    "shop-c-upper": make_shop_c_upper,
}


# --- export -------------------------------------------------------------------------------------


def to_kit_units(part: Part) -> Part:
    out = Part(part.name)
    k = 1.0 / STUDS_PER_UNIT
    out.verts = [(x * k, y * k, z * k) for x, y, z in part.verts]
    out.faces = list(part.faces)
    return out


def generate(out_dir: str) -> int:
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, make in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        export(build_object(to_kit_units(part), {}), out_dir)
        total += part.tris
        lo, hi = part.bounds()
        print(
            f"[{KIT}] {name}.glb: {part.tris} tris, "
            f"x[{lo[0]:.2f}, {hi[0]:.2f}] y[{lo[1]:.2f}, {hi[1]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}] studs at scale 4",
            flush=True,
        )
    print(f"[{KIT}] {len(PIECES)} pieces, {total} tris total -> {os.path.relpath(out_dir, REPO_ROOT)}", flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the boomtown-extras-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)
    return generate(args.out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
