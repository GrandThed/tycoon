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
- Suburb homes and the works. The fabric's house lots are 6 x 6 and 8 x 8, so the kit houses go in
  at a reduced blueprint scale; what tells one white, green-roofed kit house from the next (a roof
  in another colour, a coloured door, shutters, a bay), what makes a home lived-in or lets it grow
  (picket fence, mailbox, porch, carport, lawn, hedge, flower bed, a garage or side wing, a second
  storey) and the works themselves (two small ones outright; a yard, dock and tank for the kit
  shed and warehouse) are generated here. A roof skin is cut from the kit house's own roof, so
  generating the kit needs city-kit-suburban on disk.

**Units.** These GLBs are in City Kit units, **1 unit = 4 studs at blueprint scale 4.0**, because
every prop that uses them also places suburban, industrial or roads pieces and a blueprint has one
scale for all of its pieces. The literals below are studs as they come out at the blueprint's scale
and are divided by it once, at export: 4.0 (STUDS_PER_UNIT) unless PIECE_SCALE names another, which
it does for the home and works pieces (2.8). A piece is only right in a blueprint of its own scale.

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
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import glbtools  # noqa: E402
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
TIN_SHADE = (205, 205, 224)  # and lower still
LAVENDER = (160, 168, 201)
STONE = (142, 149, 179)
STONE_DARK = (134, 139, 161)
SLATE_BLUE = (115, 126, 155)  # industrial
SLATE_LIGHT = (102, 107, 128)
SLATE = (81, 85, 102)
CHARCOAL = (56, 56, 61)
GLASS = (208, 232, 255)
BLUE = (103, 148, 217)  # the kit houses' window glass
BLUE_PALE = (181, 204, 236)  # industrial
NAVY = (71, 74, 172)  # industrial
GREEN = (97, 203, 139)
GREEN_DARK = (61, 167, 122)
HEDGE_DARK = (44, 149, 113)  # industrial: deep in the same green ramp
LAWN = (76, 181, 129)  # the leafiest step of that ramp below the roofs' green
LAWN_LIGHT = (87, 193, 134)  # industrial
YELLOW = (255, 192, 68)
ORANGE = (255, 126, 68)
RED = (207, 83, 79)
PINK = (243, 120, 240)
PINK_PALE = (245, 200, 240)  # industrial
CREAM = (253, 228, 199)
SAND = (242, 191, 153)
SAND_PALE = (244, 202, 153)
PEACH = (250, 174, 138)
WOOD = (241, 151, 108)
TERRACOTTA = (212, 116, 93)
BRICK = (176, 96, 65)
EARTH = (159, 106, 82)  # industrial
EARTH_LIGHT = (193, 135, 113)  # industrial: the lit end of the same ramp
EARTH_DARK = (131, 84, 66)
BRICK_SOFT = (188, 132, 108)  # industrial: a dusty brick for big wall areas
BRICK_SHADE = (183, 128, 102)  # industrial

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


def scaled(src: Part, k: float) -> Part:
    """src shrunk or grown about its origin."""
    out = Part(src.name)
    out.verts = [(x * k, y * k, z * k) for x, y, z in src.verts]
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
        if sill > 2 * STUD + 0.05:  # room for a cripple between the sole plate and the sill
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
    head, sill = wall - 0.6, 0.5  # openings at the kits' door height, not a full-size one
    stud_wall(p, (-ex, -wz), (ex, -wz), SLAB, wall, openings=((d0, d1, 0.0, head), (w0, w1, sill, head)))
    stud_wall(p, (-ex, wz), (ex, wz), SLAB, wall, openings=((lx * 0.3, lx * 0.3 + 1.0, sill, head),))
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
    """SiteSmall's house: a 3.4 x 3.0 slab, 1.9-stud walls, ridge at 3.25; 3 of 5 rafter pairs up.
    No taller than the small homes that replace it (2.9 to 3.2)."""
    return house_frame("frame-house-small", 3.4, 3.0, 1.9, 1.1, 3, 4, (0.45, 1.3), (1.75, 2.6))


def make_frame_house_medium() -> Part:
    """SiteMedium's house: a 5.0 x 4.0 slab, 2.2-stud walls, ridge at 3.85; 4 of 7 rafter pairs up."""
    return house_frame("frame-house-medium", 5.0, 4.0, 2.2, 1.4, 4, 6, (0.6, 1.6), (2.2, 3.9))


# The narrow lot's building line, shared by the shop shell and the three shops: the body stands
# 0.9 studs back from the street edge (room for an awning or a scaffold) and leaves a 2.1-stud yard.
# The roof decks are the City Kits' own: their storey is 0.4 units, 1.6 studs at the landmarks'
# scale 4, and a one-storey flat kit building's deck stands near 2.0 with its kerb. (A first cut used
# 3.5-stud storeys; beside the Barber Shop its doors were twice the landmark's.)
SHOP_HX = 2.45
SHOP_FRONT = -3.1
SHOP_BACK = 1.9
SHOP_H1 = 1.85  # ground-floor roof deck
SHOP_H2 = 3.45  # upper-floor roof deck
CHIMNEY_RISE = (0.4, 0.55)  # a chimney's height above the ground-floor and the upper-floor deck


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
    stud_wall(p, (-ex, zf), (ex, zf), SLAB, wall, openings=((0.4, 1.1, 0.0, 1.15), (1.5, 4.2, 0.35, 1.15)))
    stud_wall(p, (-ex, zb), (ex, zb), SLAB, wall, openings=((3.0, 3.7, 0.0, 1.15),), spacing=0.8)
    for x in (-wx, wx):
        stud_wall(p, (x, zf + STUD / 2), (x, zb - STUD / 2), SLAB, wall, spacing=0.75)
    for k in range(5):  # roof joists, front to back
        z = zf + 0.55 + (zb - zf - 1.1) * k / 4
        beam(p, (-wx - 0.02, SHOP_H1 + 0.1, z), (wx + 0.02, SHOP_H1 + 0.1, z), 0.16, 0.2, RAFTER, ends=SAND)
    stud_wall(p, (-ex, zf), (ex, zf), SHOP_H1, 1.1, spacing=0.75)  # the false front's cripples, to 2.95
    return p


# --- site props ---------------------------------------------------------------------------------


def make_cement_mixer() -> Part:
    """A towed drum mixer, 1.1 x 1.45 x 1.65 studs: a yellow drum with an orange band, tipped 40
    degrees toward -Z, in a slate yoke on two wheels, with the engine box behind. Still a little
    oversized against the kits' 1-stud doors, on purpose: it is the one object that says "building
    site" at a glance. (Modelled at 1.9 tall, where it dwarfed a 3.4-stud frame, then shrunk.)"""
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
    return scaled(p, 0.75)


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
    """One hoarding panel, 2.4 x 1.45 x 0.26 studs: white boards between slate posts under a red
    top band, the white-and-red of every Boomtown site and sale board. Panels butt end to end."""
    p = Part("hoarding")
    half, height = 1.2, 1.3
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
    """A SOLD stake, 0.85 x 1.3 x 0.2 studs, facing -Z: a pointed wooden stake with a small white
    board nailed to it and a red sash across the board. (A red board with a white bar read as a
    no-entry sign.) It stands under the lower lift of scaffold-bay."""
    p = Part("sold-stake")
    p.box(-0.06, 0.06, 0.0, 1.12, 0.0, 0.12, BRICK)
    p.frustum(-0.06, 0.06, 0.0, 0.12, 1.12, -0.01, 0.01, 0.05, 0.07, 1.3, BRICK)
    p.box(-0.42, 0.42, 0.62, 1.06, -0.05, 0.0, WHITE)
    beam(p, (-0.34, 0.71, -0.065), (0.34, 0.97, -0.065), 0.14, 0.03, RED, up=(0.0, 0.0, 1.0))
    return p


def make_scaffold_bay() -> Part:
    """Steel-pipe scaffold across a shop front, 4.6 x 3.4 x 0.9 studs, centred on its own middle:
    six slate standards in two rows, ledgers at two lifts, a plank deck on the lower lift with a
    guard rail above it, one diagonal brace per bay toward the street. It stands a little over the
    shell's false front (2.95)."""
    p = Part("scaffold-bay")
    hx, hz, height, pipe = 2.2, 0.32, 3.4, 0.16
    for x in (-hx, 0.0, hx):
        for z in (-hz, hz):
            p.box(x - pipe / 2, x + pipe / 2, 0.0, height, z - pipe / 2, z + pipe / 2, SLATE, top=SLATE_LIGHT)
    lifts = (1.5, 3.0)
    for y in lifts:
        for z in (-hz, hz):
            beam(p, (-hx - 0.1, y, z), (hx + 0.1, y, z), pipe, pipe, SLATE)
        for x in (-hx, 0.0, hx):
            beam(p, (x, y - 0.14, -hz - 0.08), (x, y - 0.14, hz + 0.08), pipe * 0.8, pipe * 0.8, SLATE_LIGHT)
    beam(p, (-hx - 0.1, 2.3, -hz), (hx + 0.1, 2.3, -hz), pipe * 0.8, pipe * 0.8, SLATE_LIGHT)  # guard rail
    deck = lifts[0] + 0.08
    p.box(-hx - 0.08, hx + 0.08, deck, deck + 0.1, -hz - 0.06, hz + 0.06, WOOD, front=SAND, left=CREAM, right=CREAM)
    zb = -hz - pipe / 2 - 0.05
    beam(p, (-hx + 0.08, 0.15, zb), (-0.08, lifts[0] - 0.12, zb), 0.12, 0.1, SLATE_LIGHT, up=(0.0, 0.0, 1.0))
    beam(p, (0.08, lifts[0] + 0.3, zb), (hx - 0.08, lifts[1] - 0.12, zb), 0.12, 0.1, SLATE_LIGHT, up=(0.0, 0.0, 1.0))
    return p


def make_ladder() -> Part:
    """A 2.6-stud ladder leaning back 15 degrees: feet at the origin, top 2.51 up and 0.67 toward +Z."""
    p = Part("ladder")
    length, tilt = 2.6, math.radians(15.0)
    top_y, top_z = length * math.cos(tilt), length * math.sin(tilt)
    half = 0.36
    for sx in (-1, 1):
        beam(p, (sx * half, 0.02, 0.0), (sx * half, top_y, top_z), 0.13, 0.13, BRICK)
    for i in range(5):
        f = (i + 0.7) / 5.3
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
    """Disturbed earth under an 8 x 8 site, 7.8 studs square."""
    return ragged_ground("site-ground-medium", 3.82, 3.82, 172,
                         ((-1.6, 1.2, 1.3, 0.9), (1.8, -1.4, 1.1, 0.8), (0.9, 2.3, 0.8, 0.55), (-2.3, -2.1, 0.7, 0.55)))


def make_site_ground_narrow() -> Part:
    """Disturbed earth under a 5 x 8 terraced site, 4.85 x 7.7 studs with straight sides."""
    return ragged_ground("site-ground-narrow", 2.42, 3.82, 173,
                         ((-0.8, 3.0, 0.9, 0.6), (0.9, 2.7, 0.7, 0.5), (0.2, -3.5, 1.2, 0.3)), straight_sides=True)


def make_scaffold_ring() -> Part:
    """Pipe scaffold round a 9 x 9-stud slot, 7.6 studs tall: slate standards, ledgers and plank
    decks at two lifts, guard rails on top, braces on the outside, and a white hoarding skirt with a
    red band round the foot, open at the street. The whole ring stands outside the slot: nothing
    is nearer the centre than 4.52, so a landmark that fills its 9 x 9 touches none of it, and it
    reaches out to 4.97, so the blueprint's footprint is 10 x 10. The client's footprint / 9 scale
    still fits it to any slot. No standard stands in the gateway: the street side has two, either
    side of it. Steel and hoarding, where the Village reveal is all timber."""
    p = Part("scaffold-ring")
    e, height, pipe = 4.75, 7.6, 0.2
    lifts = (2.7, 5.4)
    gateway = 1.6
    for rot in (0, 90, 180, 270):
        side = Part("side")
        for x in (-e, -gateway, gateway) if rot == 0 else (-e, 0.0):  # each side brings its left corner
            side.box(x - pipe / 2, x + pipe / 2, 0.0, height, -e - pipe / 2, -e + pipe / 2, SLATE, top=SLATE_LIGHT)
        for y in lifts:
            beam(side, (-e - pipe / 2, y, -e), (e + pipe / 2, y, -e), pipe * 0.9, pipe * 0.9, SLATE)
            # the street and back decks run corner to corner; the side decks fit between them
            reach = e + 0.2 if rot in (0, 180) else e - 0.23
            side.box(-reach, reach, y + 0.1, y + 0.2, -e - 0.2, -e + 0.23, WOOD, front=SAND, top=PEACH)
        for y in (6.5, 7.45):
            beam(side, (-e - pipe / 2, y, -e), (e + pipe / 2, y, -e), pipe * 0.7, pipe * 0.7, SLATE_LIGHT)
        zb = -e - pipe / 2 - 0.05
        beam(side, (-e + 0.1, 1.75, zb), (-0.12, lifts[0] - 0.12, zb), 0.13, 0.1, SLATE_LIGHT, up=(0.0, 0.0, 1.0))
        beam(side, (0.12, lifts[0] + 0.3, zb), (e - 0.1, lifts[1] - 0.12, zb), 0.13, 0.1, SLATE_LIGHT,
             up=(0.0, 0.0, 1.0))
        # the hoarding skirt: the street side (rot 0) leaves the gateway open
        z0, z1 = -e - 0.2, -e - 0.13
        reach = e + 0.2 if rot in (0, 180) else e + 0.13
        spans = ((-reach, -gateway), (gateway, reach)) if rot == 0 else ((-reach, reach),)
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
# Four anonymous shops for the 5 x 8 narrow lot, each built from one piece per stage, all in the
# lot frame, at the City Kits' storey height (see SHOP_H1). Stages are additive, so each later piece
# is made to swallow the earlier ones:
# - stage 0, shop-<v>-ground: a one-storey flat-roofed body with a plain front (kerb at 2.0, roof
#   furniture to about 2.25);
# - stage 1, shop-<v>-front: a false-front parapet standing on the front wall, a sign board on it
#   and an awning over the window (3.1 to 3.4);
# - stage 2, shop-<v>-upper: a second storey 0.03 proud of the body on every side, so the roof
#   kerb, the roof furniture and the false front end up inside it. The sign board is 0.12 proud, so
#   it stays in view as the fascia between the floors; a taller sign goes on top (4.45, under the
#   Barber Shop's 4.6).
# The tycoon camera looks down on a terrace, so the roofs are half of what it sees: each shop has
# its own lighter roof tone, a kerb in its trim colour and roof furniture. Side walls stand 0.05
# inside the lot line, so shops meet in a terrace; where a terrace steps in height they show: each
# carries the front's colour round its corner, a plinth, a small window, and a painted
# advertisement on the upper storey. Walls are the muted tones; awnings and signs carry the colour.

SHOP_STYLE = {
    # brick with white trim, a green and white awning, a yellow sign: a general store
    "a": {"facade": BRICK_SOFT, "side": BRICK_SHADE, "trim": WHITE, "leaf": GREEN_DARK, "roof": STONE,
          "ad": CREAM, "ad_band": RED, "layout": "centre", "stack": (-1.5, 1.0)},
    # pale blue with navy trim, a yellow canopy and a yellow blade sign: an appliance store
    "b": {"facade": BLUE_PALE, "side": TIN_SHADE, "trim": NAVY, "leaf": NAVY, "roof": SLATE_BLUE,
          "ad": NAVY, "ad_band": YELLOW, "layout": "left", "stack": None},
    # cream with red trim, a red and white awning: a barber-pole kind of shop without the pole
    "c": {"facade": CREAM, "side": SAND_PALE, "trim": RED, "leaf": RED, "roof": EARTH,
          "ad": RED, "ad_band": CREAM, "layout": "right", "stack": (1.4, 0.9)},
    # pale pink with white trim, a blue and white awning, a pink roof sign: a soda fountain
    "d": {"facade": PINK_PALE, "side": WALL_SHADE, "trim": WHITE, "leaf": BLUE, "roof": TIN_SHADE,
          "ad": BLUE, "ad_band": WHITE, "layout": "corner", "stack": (1.5, 1.1)},
}


def window(p: Part, x0: float, x1: float, y0: float, y1: float, z: float, facing: int, frame: Rgb = SLATE,
           mullions: int = 0) -> None:
    """A framed pane on a wall whose outer face is at z and faces `facing` (-1 = -Z, 1 = +Z)."""

    def zbox(a0, a1, b0, b1, proud, colour):
        za, zb = sorted((z, z + facing * proud))
        p.box(a0, a1, b0, b1, za, zb, colour)

    m = 0.08
    zbox(x0, x1, y0, y1, 0.05, frame)
    zbox(x0 + m, x1 - m, y0 + m, y1 - m, 0.07, GLASS)
    for k in range(mullions):
        x = x0 + (x1 - x0) * (k + 1) / (mullions + 1)
        zbox(x - 0.035, x + 0.035, y0 + m, y1 - m, 0.09, frame)


def door(p: Part, x0: float, x1: float, y1: float, z: float, facing: int, leaf: Rgb, frame: Rgb = SLATE,
         glazed: bool = True) -> None:
    def zbox(a0, a1, b0, b1, proud, colour):
        za, zb = sorted((z, z + facing * proud))
        p.box(a0, a1, b0, b1, za, zb, colour)

    zbox(x0, x1, 0.0, y1, 0.05, frame)
    zbox(x0 + 0.07, x1 - 0.07, 0.0, y1 - 0.07, 0.07, leaf)
    if glazed:
        zbox(x0 + 0.17, x1 - 0.17, y1 * 0.5, y1 - 0.2, 0.09, GLASS)


def side_pane(p: Part, sx: int, face: float, z0: float, z1: float, y0: float, y1: float) -> None:
    """A small window on a side wall (outer face at x = face, looking toward sx), 0.045 proud."""
    xa, xb = sorted((face, face + sx * 0.03))
    p.box(xa, xb, y0, y1, z0, z1, SLATE)
    xa, xb = sorted((face, face + sx * 0.045))
    p.box(xa, xb, y0 + 0.08, y1 - 0.08, z0 + 0.08, z1 - 0.08, GLASS)


def chimney(p: Part, x: float, z: float, deck: float, rise: float) -> None:
    """A brick stack with a slab cap and a flue pot, standing `rise` above the roof deck. Its top
    centre is where the smoke config puts a plume."""
    top = deck + rise
    p.box(x - 0.22, x + 0.22, deck, top - 0.14, z - 0.22, z + 0.22, BRICK)
    p.box(x - 0.27, x + 0.27, top - 0.14, top - 0.07, z - 0.27, z + 0.27, STONE_DARK, top=LAVENDER)
    p.box(x - 0.11, x + 0.11, top - 0.07, top, z - 0.11, z + 0.11, SLATE, top=CHARCOAL)


def roof_light(p: Part, x: float, z: float, deck: float) -> None:
    """A roof-light like the industrial kit's: a white upstand under a glass lid, 0.23 tall."""
    p.box(x - 0.45, x + 0.45, deck, deck + 0.2, z - 0.35, z + 0.35, WALL)
    p.box(x - 0.37, x + 0.37, deck + 0.2, deck + 0.23, z - 0.27, z + 0.27, GLASS)


def vent_pot(p: Part, x: float, z: float, deck: float) -> None:
    """A roof vent, 0.32 tall."""
    p.box(x - 0.09, x + 0.09, deck, deck + 0.26, z - 0.09, z + 0.09, SLATE_LIGHT)
    p.box(x - 0.13, x + 0.13, deck + 0.26, deck + 0.32, z - 0.13, z + 0.13, SLATE)


def ventilator(p: Part, x: float, z: float, deck: float) -> None:
    """A louvred roof ventilator under a slate lid, 0.36 tall."""
    p.box(x - 0.35, x + 0.35, deck, deck + 0.28, z - 0.35, z + 0.35, WALL_SHADE, top=SLATE_LIGHT)
    p.box(x - 0.42, x + 0.42, deck + 0.28, deck + 0.36, z - 0.42, z + 0.42, SLATE)


def water_tank(p: Part, x: float, z: float, deck: float) -> None:
    """A rooftop water tank, 0.95 tall: a wooden barrel under a slate cone on four legs."""
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box(x + sx * 0.26 - 0.04, x + sx * 0.26 + 0.04, deck, deck + 0.32, z + sz * 0.26 - 0.04,
                  z + sz * 0.26 + 0.04, SLATE)
    lathe(p, [(0.4, 0.3), (0.42, 0.36), (0.42, 0.72), (0.0, 0.95)], [BRICK, WOOD, SLATE_LIGHT], seg=8,
          at=(x, deck, z), phase=math.pi / 8)


def roof_kerb(p: Part, deck: float, hx: float, zf: float, zb: float, colour: Rgb, front: float = 0.14) -> None:
    """The parapet cap round a flat roof, in the shop's trim colour: 0.15 tall, 0.14 wide."""
    kerb, k = deck + 0.15, 0.14
    p.box(-hx, hx, deck, kerb, zf, zf + front, colour)
    p.box(-hx, hx, deck, kerb, zb - k, zb, colour)
    for x0, x1 in ((-hx, -hx + k), (hx - k, hx)):
        p.box(x0, x1, deck, kerb, zf + front, zb - k, colour)


def shop_ground(name: str, key: str) -> Part:
    s = SHOP_STYLE[key]
    p = Part(name)
    hx, zf, zb = SHOP_HX, SHOP_FRONT, SHOP_BACK
    facade, trim, leaf = s["facade"], s["trim"], s["leaf"]
    # the pavement apron runs the full lot width, so a terrace's aprons join into one sidewalk
    p.box(-NARROW[0] / 2, NARROW[0] / 2, 0.0, 0.06, -NARROW[1] / 2, zf, LAVENDER)
    p.box(-hx, hx, 0.0, SHOP_H1, zf, zb, s["side"], front=facade, top=s["roof"])
    roof_kerb(p, SHOP_H1, hx, zf, zb, trim)
    riser, head = 0.3, 1.3

    def shop_window(x0: float, x1: float, mullions: int) -> None:
        p.box(x0, x1, 0.0, riser, zf - 0.06, zf, trim)
        window(p, x0, x1, riser, head, zf, -1, mullions=mullions)

    layout = s["layout"]
    if layout == "centre":
        door(p, -0.32, 0.32, head, zf, -1, leaf)
        shop_window(-2.15, -0.55, 1)
        shop_window(0.55, 2.15, 1)
    elif layout == "left":
        door(p, -2.1, -1.46, head, zf, -1, leaf)
        shop_window(-1.2, 2.15, 3)
    elif layout == "right":
        door(p, 1.46, 2.1, head, zf, -1, leaf)
        shop_window(-2.15, 1.2, 2)
    else:  # "corner": a door set in from the left between a narrow and a wide window
        door(p, -1.3, -0.66, head, zf, -1, leaf)
        shop_window(-2.15, -1.5, 0)
        shop_window(-0.45, 2.15, 2)
    # the back: a plain service door and a small window, for anyone who walks round
    door(p, 0.9, 1.5, 1.2, zb, 1, SLATE_LIGHT, glazed=False)
    window(p, -1.6, -0.6, 0.55, 1.15, zb, 1)
    # the sides: the front's colour carried round the corner, a slate plinth and a small window
    for sx in (-1, 1):
        face = sx * hx
        xa, xb = sorted((face, face + sx * 0.02))
        p.box(xa, xb, 0.0, SHOP_H1, zf, zf + 0.45, facade)
        xa, xb = sorted((face, face + sx * 0.03))
        p.box(xa, xb, 0.0, 0.22, zf + 0.45, zb, SLATE)
        side_pane(p, sx, face, 0.4, 1.3, 0.62, 1.2)
    if s["stack"]:
        chimney(p, s["stack"][0], s["stack"][1], SHOP_H1, CHIMNEY_RISE[0])
    return p


def striped_awning(p: Part, x0: float, x1: float, colours, stripes: int) -> None:
    """A canvas awning over the shop window: a striped slope from the wall at 1.74 down to 1.44 at
    0.45 out, a valance along its front edge and a closed cheek at each end. Shallow, so the
    camera still sees glass under it."""
    zw = SHOP_FRONT
    zf = zw - 0.45
    yt, yf, t = 1.74, 1.44, 0.06
    w = (x1 - x0) / stripes
    for i in range(stripes):
        xa, xb = x0 + i * w, x0 + (i + 1) * w
        c = colours[i % 2]
        p.hexa([(xa, yf - t, zf), (xb, yf - t, zf), (xb, yt - t, zw), (xa, yt - t, zw),
                (xa, yf, zf), (xb, yf, zf), (xb, yt, zw), (xa, yt, zw)], c)
        p.box(xa, xb, yf - 0.2, yf - t, zf, zf + 0.05, c)
    for xa, xb in ((x0 - 0.04, x0), (x1, x1 + 0.04)):
        extrude_x(p, [(zw, yt), (zf, yf), (zf, yf - t), (zw, yf - t)], xa, xb, colours[1])


def flat_canopy(p: Part, x0: float, x1: float, colour: Rgb, edge: Rgb) -> None:
    """A rigid 1950s canopy: a slab hung 0.5 out from the wall on two tie rods."""
    zw = SHOP_FRONT
    zf = zw - 0.5
    p.box(x0, x1, 1.5, 1.6, zf, zw, colour)
    p.box(x0 - 0.03, x1 + 0.03, 1.46, 1.64, zf - 0.03, zf + 0.03, edge)
    for x in (x0 + 0.5, x1 - 0.5):
        beam(p, (x, 1.61, zf + 0.1), (x, 1.82, zw), 0.05, 0.05, SLATE)


def sign_board(p: Part, x0: float, x1: float, board: Rgb, band: Rgb) -> None:
    """The fascia sign, 0.12 proud of the front wall: a board with a lettering band across it."""
    zw = SHOP_FRONT
    p.box(x0, x1, 2.1, 2.65, zw - 0.12, zw, board)
    p.box(x0 + 0.2, x1 - 0.2, 2.23, 2.52, zw - 0.15, zw - 0.12, band)


def parapet(p: Part, x0: float, x1: float, top: float, facade: Rgb, cap: Rgb, side: Rgb) -> None:
    """One block of the false front: 0.25 thick on the front wall, with a cap."""
    zw = SHOP_FRONT
    p.box(x0, x1, SHOP_H1, top, zw, zw + 0.25, facade, back=side)
    p.box(x0, x1, top, top + 0.1, zw, zw + 0.29, cap)


def upper(p: Part, key: str, windows) -> None:
    """The second storey: 0.03 proud of the ground floor all round, front windows above the fascia
    sign, one window at the back, a cornice at the street and the trim-colour kerb round the rest
    of the roof. Each side carries the front's colour round the corner and a painted advertisement,
    0.02 proud: the wall a lower neighbour leaves in view. The chimney, if the shop has one,
    continues above the new roof."""
    s = SHOP_STYLE[key]
    facade, trim = s["facade"], s["trim"]
    e = 0.03
    hx, zf, zb = SHOP_HX + e, SHOP_FRONT - e, SHOP_BACK + e
    p.box(-hx, hx, SHOP_H1, SHOP_H2, zf, zb, s["side"], front=facade, top=s["roof"])
    for x0, x1, mullions in windows:
        window(p, x0, x1, 2.78, 3.3, zf, -1, mullions=mullions)
        p.box(x0 - 0.05, x1 + 0.05, 2.7, 2.78, zf - 0.08, zf, trim)
    window(p, -0.6, 0.6, 2.6, 3.15, zb, 1, mullions=1)
    roof_kerb(p, SHOP_H2, hx, zf, zb, trim, front=0.18)
    p.box(-hx, hx, SHOP_H2 - 0.06, SHOP_H2 + 0.2, zf - 0.07, zf + 0.18, trim)  # the cornice
    for sx in (-1, 1):
        face = sx * hx
        xa, xb = sorted((face, face + sx * 0.02))
        p.box(xa, xb, SHOP_H1, SHOP_H2, zf, zf + 0.45, facade)
        for y0, y1, colour in ((2.3, 2.52, s["ad"]), (2.52, 2.98, s["ad_band"]), (2.98, 3.2, s["ad"])):
            p.box(xa, xb, y0, y1, -1.7, 1.1, colour)  # three stripes at one depth
    if s["stack"]:
        chimney(p, s["stack"][0], s["stack"][1], SHOP_H2, CHIMNEY_RISE[1])


def make_shop_a_ground() -> Part:
    """Shop a, stage 0: muted brick front, white trim, a centre door between two windows; a
    roof-light and a chimney on a pale grey roof."""
    p = shop_ground("shop-a-ground", "a")
    roof_light(p, 0.9, -1.0, SHOP_H1)
    return p


def make_shop_a_front() -> Part:
    """Shop a, stage 1: a level false front to 3.1, a green and white striped awning, a yellow sign."""
    s = SHOP_STYLE["a"]
    p = Part("shop-a-front")
    parapet(p, -SHOP_HX, SHOP_HX, 3.0, s["facade"], WHITE, s["side"])
    striped_awning(p, -2.25, 2.25, (GREEN, WHITE), 9)
    sign_board(p, -1.9, 1.9, YELLOW, SLATE)
    return p


def make_shop_a_upper() -> Part:
    """Shop a, stage 2: a second storey with two windows, a roof-light, and a yellow roof sign with
    a dark band, 4.45."""
    p = Part("shop-a-upper")
    upper(p, "a", ((-1.9, -0.6, 1), (0.6, 1.9, 1)))
    roof_light(p, 0.9, 0.4, SHOP_H2)
    z = SHOP_FRONT + 0.25
    for x in (-1.1, 1.1):
        p.box(x - 0.06, x + 0.06, SHOP_H2 + 0.15, 3.85, z - 0.06, z + 0.06, SLATE)
    p.box(-1.6, 1.6, 3.8, 4.45, z - 0.16, z - 0.06, YELLOW, back=SLATE_LIGHT)
    p.box(-1.38, 1.38, 3.98, 4.27, z - 0.19, z - 0.16, SLATE)
    return p


def make_shop_b_ground() -> Part:
    """Shop b, stage 0: pale blue front, navy trim, the door at the left of one wide window; a
    ventilator and two vents on a blue-slate roof instead of a chimney."""
    p = shop_ground("shop-b-ground", "b")
    ventilator(p, 1.05, 0.65, SHOP_H1)
    for x in (-1.5, -1.05):
        vent_pot(p, x, 1.2, SHOP_H1)
    return p


def make_shop_b_front() -> Part:
    """Shop b, stage 1: a stepped false front to 3.4, a yellow flat canopy, a white sign."""
    s = SHOP_STYLE["b"]
    p = Part("shop-b-front")
    for x0, x1 in ((-SHOP_HX, -1.15), (1.15, SHOP_HX)):
        parapet(p, x0, x1, 2.9, s["facade"], NAVY, s["side"])
    parapet(p, -1.15, 1.15, 3.3, s["facade"], NAVY, s["side"])
    flat_canopy(p, -2.3, 2.3, YELLOW, WHITE)
    sign_board(p, -1.9, 1.9, WHITE, NAVY)
    return p


def make_shop_b_upper() -> Part:
    """Shop b, stage 2: a second storey with three windows, a rooftop water tank and a yellow blade
    sign at the corner, 4.45."""
    p = Part("shop-b-upper")
    upper(p, "b", ((-2.0, -1.1, 0), (-0.45, 0.45, 0), (1.0, 1.62, 0)))
    ventilator(p, 1.05, 0.65, SHOP_H2)
    water_tank(p, -1.2, 0.5, SHOP_H2)
    zw = SHOP_FRONT - 0.03
    x0, x1 = 1.84, 2.0
    p.box(x0, x1, 2.75, 4.35, zw - 0.6, zw - 0.1, YELLOW, front=NAVY)
    p.box(x0 - 0.03, x1 + 0.03, 4.35, 4.45, zw - 0.63, zw - 0.07, NAVY)
    for xa, xb in ((x0 - 0.03, x0), (x1, x1 + 0.03)):  # the lettering band, on both faces
        p.box(xa, xb, 2.95, 4.15, zw - 0.42, zw - 0.28, NAVY)
    for y in (2.86, 3.25):
        p.box(x0 + 0.03, x1 - 0.03, y, y + 0.08, zw - 0.1, zw, SLATE)
    return p


def make_shop_c_ground() -> Part:
    """Shop c, stage 0: cream front, red trim, the door at the right of one wide window; a
    roof-light and a chimney on a warm brown roof."""
    p = shop_ground("shop-c-ground", "c")
    roof_light(p, -0.9, -0.8, SHOP_H1)
    return p


def make_shop_c_front() -> Part:
    """Shop c, stage 1: a false front with end piers to 3.25, a red and white awning, a red sign."""
    s = SHOP_STYLE["c"]
    p = Part("shop-c-front")
    parapet(p, -1.95, 1.95, 2.9, s["facade"], RED, s["side"])
    for x0, x1 in ((-SHOP_HX, -1.95), (1.95, SHOP_HX)):
        parapet(p, x0, x1, 3.15, s["facade"], RED, s["side"])
    striped_awning(p, -2.25, 2.25, (RED, WHITE), 9)
    sign_board(p, -1.75, 1.75, RED, WHITE)
    return p


def make_shop_c_upper() -> Part:
    """Shop c, stage 2: a second storey with two windows under a stepped pediment that carries a red
    roundel, 4.45; a roof-light behind it."""
    s = SHOP_STYLE["c"]
    p = Part("shop-c-upper")
    upper(p, "c", ((-1.9, -0.6, 1), (0.6, 1.9, 1)))
    roof_light(p, -0.9, 0.5, SHOP_H2)
    zf = SHOP_FRONT - 0.03
    top = SHOP_H2 + 0.2
    p.box(-1.5, 1.5, top, top + 0.4, zf, zf + 0.25, s["facade"], back=s["side"])
    p.box(-1.5, 1.5, top + 0.4, top + 0.5, zf - 0.03, zf + 0.28, RED)
    p.box(-0.7, 0.7, top + 0.5, top + 0.7, zf, zf + 0.25, s["facade"], back=s["side"])
    p.box(-0.7, 0.7, top + 0.7, top + 0.8, zf - 0.03, zf + 0.28, RED)
    for r, z0, colour in ((0.2, zf - 0.06, RED), (0.1, zf - 0.09, WHITE)):
        ring = [(r * math.cos(2 * math.pi * (k + 0.5) / 8), top + 0.2 + r * math.sin(2 * math.pi * (k + 0.5) / 8))
                for k in range(8)]
        extrude_z(p, ring, z0, zf, colour)
    return p


def make_shop_d_ground() -> Part:
    """Shop d, stage 0: pale pink front, white trim, a blue door set in from the left; a hatch, a
    vent and a chimney on a pale tin roof."""
    p = shop_ground("shop-d-ground", "d")
    vent_pot(p, -1.5, -1.0, SHOP_H1)
    p.box(-0.9, -0.2, SHOP_H1, SHOP_H1 + 0.12, 0.2, 0.9, WALL_SHADE, top=SLATE_LIGHT)  # the roof hatch
    return p


def make_shop_d_front() -> Part:
    """Shop d, stage 1: a false front stepped up twice to 3.4, a blue and white awning, a blue sign
    with a red cherry of a roundel over it."""
    s = SHOP_STYLE["d"]
    p = Part("shop-d-front")
    for x0, x1 in ((-SHOP_HX, -1.6), (1.6, SHOP_HX)):
        parapet(p, x0, x1, 2.8, s["facade"], WHITE, s["side"])
    for x0, x1 in ((-1.6, -0.75), (0.75, 1.6)):
        parapet(p, x0, x1, 3.05, s["facade"], WHITE, s["side"])
    parapet(p, -0.75, 0.75, 3.3, s["facade"], WHITE, s["side"])
    striped_awning(p, -2.25, 2.25, (BLUE, WHITE), 9)
    sign_board(p, -1.5, 1.5, BLUE, WHITE)
    zw = SHOP_FRONT
    ring = [(0.17 * math.cos(2 * math.pi * (k + 0.5) / 8), 2.98 + 0.17 * math.sin(2 * math.pi * (k + 0.5) / 8))
            for k in range(8)]
    extrude_z(p, ring, zw - 0.06, zw, RED)
    return p


def make_shop_d_upper() -> Part:
    """Shop d, stage 2: a second storey with one wide and one narrow window, and a pink sign in an
    open frame on the roof, 4.45; two vents behind it."""
    p = Part("shop-d-upper")
    upper(p, "d", ((-2.0, -1.3, 0), (-0.6, 1.9, 2)))
    for x in (-1.5, -1.05):
        vent_pot(p, x, 0.2, SHOP_H2)
    z = SHOP_FRONT + 0.3
    for x in (-1.25, 1.25):  # the frame: two legs, each braced back to the roof
        p.box(x - 0.05, x + 0.05, SHOP_H2 + 0.15, 4.45, z - 0.05, z + 0.05, SLATE)
        beam(p, (x, 4.2, z), (x, SHOP_H2 + 0.05, z + 0.7), 0.06, 0.06, SLATE_LIGHT)
    for y in (3.82, 4.4):
        p.box(-1.3, 1.3, y - 0.035, y + 0.035, z - 0.05, z + 0.05, SLATE)
    p.box(-1.15, 1.15, 3.9, 4.32, z - 0.12, z - 0.05, PINK, back=SLATE_LIGHT)
    p.box(-0.95, 0.95, 4.02, 4.2, z - 0.15, z - 0.12, WHITE)
    return p


# --- reading the Kenney kits ----------------------------------------------------------------------
#
# A roof skin is the one generated piece here that is derived from a kit model: the kit house's own
# roof triangles (found by their colormap colour), pushed outward a little and recoloured, so a
# kit house can wear a red, brown, grey or blue roof without a second copy of the house. It needs
# the kit's GLB and colormap on disk, as merge_stages.py does.

KITS_ROOT = os.path.join(REPO_ROOT, "assets", "kenney3d")
INDEX_FORMAT = {5121: "B", 5123: "H", 5125: "I"}
_colormaps: dict = {}
_kit_triangles: dict = {}


def read_png(path: str):
    """(width, height, rows of (r, g, b)) of an 8-bit non-interlaced RGB, RGBA or palette PNG.
    Blender's Python has no Pillow, and reading the texture through bpy would depend on its colour
    management."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    pos, chunks, palette = 8, [], []
    width = height = channels = 0
    while pos < len(data):
        length, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace != 0 or ctype not in (2, 3, 6):
                raise ValueError(f"{path}: unsupported PNG (depth {depth}, colour type {ctype}, interlace {interlace})")
            channels = {2: 3, 3: 1, 6: 4}[ctype]
        elif kind == b"PLTE":
            palette = [(body[i], body[i + 1], body[i + 2]) for i in range(0, len(body), 3)]
        elif kind == b"IDAT":
            chunks.append(body)
        pos += 12 + length
    raw = zlib.decompress(b"".join(chunks))
    stride = width * channels
    rows, prev = [], bytearray(stride)
    for y in range(height):
        base = y * (stride + 1)
        ftype = raw[base]
        line = bytearray(raw[base + 1:base + 1 + stride])
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ftype == 1:
                line[i] = (line[i] + a) & 255
            elif ftype == 2:
                line[i] = (line[i] + b) & 255
            elif ftype == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif ftype == 4:
                est = a + b - c
                da, db, dc = abs(est - a), abs(est - b), abs(est - c)
                line[i] = (line[i] + (a if da <= db and da <= dc else (b if db <= dc else c))) & 255
        prev = line
        if channels == 1:
            rows.append([palette[v] for v in line])
        else:
            rows.append([(line[i], line[i + 1], line[i + 2]) for i in range(0, stride, channels)])
    return width, height, rows


def kit_triangles(kit: str, model: str):
    """A kit model as [(p0, p1, p2, (r, g, b))]: positions in kit units, the colour sampled from the
    kit's colormap at the triangle's UV centre."""
    key = (kit, model)
    if key in _kit_triangles:
        return _kit_triangles[key]
    folder = os.path.join(KITS_ROOT, kit, "Models", "GLB format")
    if kit not in _colormaps:
        _colormaps[kit] = read_png(os.path.join(folder, "Textures", "colormap.png"))
    width, height, rows = _colormaps[kit]
    with open(os.path.join(folder, f"{model}.glb"), "rb") as fh:
        doc, binary = glbtools.parse_glb(fh.read())
    out = []

    def read(accessor: int, fmt: str):
        acc = doc["accessors"][accessor]
        view = doc["bufferViews"][acc["bufferView"]]
        stride = view.get("byteStride", struct.calcsize(fmt))
        base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        return [struct.unpack_from(fmt, binary, base + i * stride) for i in range(acc["count"])]

    def visit(index: int, parent) -> None:
        node = doc["nodes"][index]
        world = glbtools.mat_mul(parent, glbtools.trs_matrix(node))
        if "mesh" in node:
            for prim in doc["meshes"][node["mesh"]]["primitives"]:
                pos = [glbtools.apply(world, v) for v in read(prim["attributes"]["POSITION"], "<fff")]
                uvs = read(prim["attributes"]["TEXCOORD_0"], "<ff")
                fmt = INDEX_FORMAT[doc["accessors"][prim["indices"]]["componentType"]]
                idx = [i[0] for i in read(prim["indices"], "<" + fmt)]
                for t in range(0, len(idx), 3):
                    a, b, c = idx[t], idx[t + 1], idx[t + 2]
                    u = (uvs[a][0] + uvs[b][0] + uvs[c][0]) / 3
                    v = (uvs[a][1] + uvs[b][1] + uvs[c][1]) / 3
                    px = min(width - 1, max(0, int(u * width)))
                    py = min(height - 1, max(0, int(v * height)))
                    out.append((pos[a], pos[b], pos[c], rows[py][px]))
        for child in node.get("children", []):
            visit(child, world)

    for root in doc["scenes"][doc.get("scene", 0)]["nodes"]:
        visit(root, glbtools.trs_matrix({}))
    _kit_triangles[key] = out
    return out


def tri_normal(a, b, c) -> Vec:
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    n = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
    length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1.0
    return (n[0] / length, n[1] / length, n[2] / length)


def roof_skin(p: Part, model: str, colour: Rgb, edge: Rgb, scale: float, offset: float = 0.035) -> None:
    """A suburban kit house's roof, recoloured: every green triangle above the ground-floor windows
    (0.3 units: the planters' bushes are green too), each vertex pushed `offset` kit units along
    the mean of the planes that meet there, so the skin closes round ridges, eaves and verges.
    Faces that look up take `colour`, the roof's edges and undersides `edge`."""
    tris = [t for t in kit_triangles("city-kit-suburban", model)
            if t[3][1] > t[3][0] + 40 and t[3][1] > t[3][2] + 15 and min(t[0][1], t[1][1], t[2][1]) > 0.3]
    planes: dict = {}
    for a, b, c, _ in tris:
        n = tri_normal(a, b, c)
        for v in (a, b, c):
            seen = planes.setdefault((round(v[0], 4), round(v[1], 4), round(v[2], 4)), [])
            if not any(n[0] * m[0] + n[1] * m[1] + n[2] * m[2] > 0.999 for m in seen):
                seen.append(n)
    for a, b, c, _ in tris:
        n = tri_normal(a, b, c)
        pts = []
        for v in (a, b, c):
            seen = planes[(round(v[0], 4), round(v[1], 4), round(v[2], 4))]
            sx, sy, sz = (sum(m[i] for m in seen) for i in range(3))
            length = math.sqrt(sx * sx + sy * sy + sz * sz) or 1.0
            k = offset / length
            pts.append(((v[0] + sx * k) * scale, (v[1] + sy * k) * scale, (v[2] + sz * k) * scale))
        p.face(pts, colour if n[1] > 0.5 else edge)


# --- suburb homes (studs at blueprint scale HOME) -------------------------------------------------
#
# Boomtown's house lots are small (6 x 6 and 8 x 8), so its fabric homes place the suburban kit
# houses at blueprint scale 2.8 where the landmarks use 4.0, the way Village's fabric homes are
# built at 2.5. A blueprint has one scale for all of its pieces, so the pieces below are written in
# studs as they come out at 2.8 and exported in kit units for that scale (PIECE_SCALE).
#
# Every kit house is white under a green roof, so each home wears a generated "dress" in its kit
# house's own frame (place it at the house's position): a roof skin in another colour on some, a
# coloured front door on all, shutters or a bay window on a few. The garnish pieces (fence,
# mailbox, porch, carport, hedge, flower bed) have their origin at the bottom centre.
#
# The two bungalows can grow, and their growth pieces are in the house's frame too:
# - building-type-h is a plain gable bungalow: walls at x +-0.62, z +-0.42 units, eaves from
#   y 0.37, verges at x +-0.65, ridge 0.7375 along X. Its roof carries solar panels, an anachronism
#   in a 1950s town, so it always wears a cap (h_roof_cap). A storey as wide as that cap, started
#   just under the eaves, swallows the whole roof, so this one house can take a real second
#   storey: no lip, because nothing of the kit roof is left outside.
# - building-type-m is the L-shaped bungalow with a cross gable and a garage door in its notch.
#   Its west gable end (x -0.564) takes a side wing, and its second stage goes up over that
#   wing's flat roof, not over the kit roof.

HOME = 2.8
H_CAP_X = 0.684 * HOME  # building-type-h under its cap: the verge boards' outer face
H_CAP_Z = 0.49 * HOME  # and the eave fascia's
H_WALL_X = 0.62 * HOME
WING_H = 1.2  # a generated wing's roof deck: just above the kit eaves (1.04), below the ridge
STOREY_H = 1.2  # a generated storey: the kits' 0.4-unit storey at this scale, and a little

ROOF_RED = (TERRACOTTA, BRICK)  # (the slope, its edges)
ROOF_BROWN = (BRICK, EARTH_DARK)
ROOF_GREY = (STONE, SLATE_LIGHT)
ROOF_BLUE = (SLATE_BLUE, SLATE_LIGHT)
ROOF_GREEN = (GREEN, GREEN_DARK)


def pane(p: Part, axis: str, face: float, facing: int, a0: float, a1: float, y0: float, y1: float,
         mullion: bool = False) -> None:
    """A window in the kit houses' dress, a slate frame round blue glass, on the generated wall whose
    outer face is at `face` on `axis` ("x" or "z") and looks toward `facing` (-1 or 1)."""

    def slab(b0: float, b1: float, c0: float, c1: float, proud: float, colour: Rgb) -> None:
        f0, f1 = sorted((face, face + facing * proud))
        if axis == "z":
            p.box(b0, b1, c0, c1, f0, f1, colour)
        else:
            p.box(f0, f1, c0, c1, b0, b1, colour)

    m = 0.08
    slab(a0, a1, y0, y1, 0.04, SLATE)
    slab(a0 + m, a1 - m, y0 + m, y1 - m, 0.06, BLUE)
    if mullion:
        mid = (a0 + a1) / 2
        slab(mid - 0.03, mid + 0.03, y0 + m, y1 - m, 0.075, SLATE)


def home_storey(p: Part, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float) -> None:
    """A generated storey dressed like the kit houses: white walls over a slate band 0.02 proud,
    the string course the two-storey kit houses carry between their floors."""
    p.box(x0, x1, y0, y1, z0, z1, WALL)
    e = 0.02
    p.box(x0 - e, x1 + e, y0, y0 + 0.12, z0 - e, z1 + e, SLATE)


def gable_roof(p: Part, cx: float, cz: float, half_ridge: float, half_span: float, eave: float, rise: float,
               roof=ROOF_GREEN, rot: float = 0.0, overhang: float = 0.1, gable: Rgb = WALL) -> None:
    """A gable roof over an attic gable in the wall colour, centred on (cx, cz): the ridge runs
    along X at rot 0 and along Z at rot 90. The roof plates are 0.1 thick and overhang the walls
    all round."""
    colour, edge = roof
    r = Part("roof")
    extrude_x(r, [(-half_span, eave), (half_span, eave), (0.0, eave + rise)], -half_ridge, half_ridge, gable)
    t = 0.1
    xa, xb = -half_ridge - overhang, half_ridge + overhang
    low = eave - overhang * rise / half_span
    ridge = eave + rise
    for sz in (-1, 1):
        side = sz * (half_span + overhang)
        ring = [(xa, low, side), (xb, low, side), (xb, ridge, 0.0), (xa, ridge, 0.0)]
        if sz > 0:
            ring = [ring[3], ring[2], ring[1], ring[0]]
        r.hexa(ring + [(x, y + t, z) for x, y, z in ring], colour, front=edge, back=edge, left=edge, right=edge,
               bottom=WALL_SHADE)
    place(p, r, rot, (cx, 0.0, cz))


def home_chimney(p: Part, x: float, z: float, y0: float, top: float) -> None:
    """A small brick stack under a slate cap; (x, top, z) is where its smoke starts."""
    p.box(x - 0.2, x + 0.2, y0, top - 0.1, z - 0.2, z + 0.2, BRICK)
    p.box(x - 0.25, x + 0.25, top - 0.1, top, z - 0.25, z + 0.25, SLATE, top=CHARCOAL)


def flat_wing(p: Part, x0: float, x1: float, z0: float, z1: float) -> None:
    """A one-storey generated wing in the kit houses' dress: white walls on a slate plinth, a flat
    slate roof inside a kerb. Openings are added by the caller."""
    p.box(x0, x1, 0.0, WING_H, z0, z1, WALL, top=SLATE)
    e = 0.02
    p.box(x0 - e, x1 + e, 0.0, 0.14, z0 - e, z1 + e, SLATE)
    k, kerb = 0.12, WING_H + 0.12
    p.box(x0, x1, WING_H, kerb, z0, z0 + k, SLATE_LIGHT)
    p.box(x0, x1, WING_H, kerb, z1 - k, z1, SLATE_LIGHT)
    for xa, xb in ((x0, x0 + k), (x1 - k, x1)):
        p.box(xa, xb, WING_H, kerb, z0 + k, z1 - k, SLATE_LIGHT)


def garage_door(p: Part, cx: float, z: float) -> None:
    """A dark up-and-over door on a wall facing -Z at z, like building-type-n's."""
    p.box(cx - 0.82, cx + 0.82, 0.14, 1.0, z - 0.03, z, STONE)
    p.box(cx - 0.72, cx + 0.72, 0.14, 0.92, z - 0.05, z, SLATE)
    p.box(cx - 0.72, cx + 0.72, 0.5, 0.56, z - 0.065, z, SLATE_LIGHT)


def door_slab(p: Part, x0: float, x1: float, z: float, colour: Rgb) -> None:
    """A coloured leaf over a kit front door: the door's rectangle on a wall facing -Z, all in kit
    units (x0..x1 wide, 0.27 tall, wall face at z). 0.012 units proud, with a pale light in it."""
    u = HOME
    p.box((x0 + 0.012) * u, (x1 - 0.012) * u, 0.02 * u, 0.255 * u, (z - 0.012) * u, z * u, colour)
    mid = (x0 + x1) / 2
    p.box((mid - 0.022) * u, (mid + 0.022) * u, 0.165 * u, 0.225 * u, (z - 0.016) * u, z * u, WALL)


def shutters(p: Part, x0: float, x1: float, y0: float, y1: float, glass_z: float, colour: Rgb) -> None:
    """A pair of shutters beside a kit window on a wall facing -Z: the glass rectangle in kit
    units. The kits set their glass 0.02 behind the wall face, inside a frame 0.03 wide."""
    u = HOME
    wall = glass_z - 0.02
    for xa, xb in ((x0 - 0.09, x0 - 0.035), (x1 + 0.035, x1 + 0.09)):
        p.box(xa * u, xb * u, (y0 - 0.02) * u, (y1 + 0.02) * u, (wall - 0.012) * u, wall * u, colour)


def bay_window(p: Part, cx: float, wall_z: float, roof) -> None:
    """A square bay over a kit window on a wall facing -Z (kit units for cx and wall_z): 0.9 studs
    wide, 0.28 out, glazed on three sides under a little roof."""
    u = HOME
    x0, x1, z1 = cx * u - 0.45, cx * u + 0.45, wall_z * u
    z0 = z1 - 0.28
    p.box(x0, x1, 0.12, 0.82, z0, z1, WALL)
    p.box(x0 - 0.02, x1 + 0.02, 0.12, 0.26, z0 - 0.02, z1, SLATE)
    pane(p, "z", z0, -1, x0 + 0.06, x1 - 0.06, 0.32, 0.76, mullion=True)
    for sx, face in ((-1, x0), (1, x1)):
        pane(p, "x", face, sx, z0 + 0.03, z1 - 0.03, 0.32, 0.76)
    colour, edge = roof
    ring = [(x0 - 0.05, 0.82, z0 - 0.06), (x1 + 0.05, 0.82, z0 - 0.06), (x1 + 0.05, 0.98, z1), (x0 - 0.05, 0.98, z1)]
    p.hexa(ring + [(x, y + 0.07, z) for x, y, z in ring], colour, front=edge, left=edge, right=edge, bottom=WALL_SHADE)


def h_roof_cap(p: Part, roof) -> None:
    """A new roof over building-type-h's, in the house's frame: two plates 0.03 units above the kit
    slope (so the solar panels, 0.02 proud, are under them) and 0.018 thick, an eave fascia and
    verge boards over the green edges. The kit roof falls 0.75 per unit from its ridge at 0.7375;
    the cap's ridge comes to 2.2 studs."""
    colour, edge = roof
    u = HOME
    xr, zr = 0.672 * u, 0.48 * u
    ridge, lift, t = 0.7375 * u, 0.03 * u, 0.018 * u
    low = ridge - 0.75 * zr
    for sz in (-1, 1):
        y0, y1 = low + lift, ridge + lift
        ring = [(-xr, y0, sz * zr), (xr, y0, sz * zr), (xr, y1, 0.0), (-xr, y1, 0.0)]
        if sz > 0:
            ring = [ring[3], ring[2], ring[1], ring[0]]
        p.hexa(ring + [(x, y + t, z) for x, y, z in ring], colour, front=edge, back=edge, left=edge, right=edge,
               bottom=edge)
        z0, z1 = sorted((sz * 0.452 * u, sz * H_CAP_Z))
        p.box(-xr, xr, 0.35 * u, low + lift + 0.02, z0, z1, edge)  # the eave fascia
        for sx in (-1, 1):  # a verge board along each slope of each gable
            x = sx * 0.664 * u
            beam(p, (x, low + lift - 0.06, sz * zr), (x, ridge + lift - 0.06, 0.0), 0.2, 0.035 * u, edge,
                 up=(1.0, 0.0, 0.0))


def make_picket_fence() -> Part:
    """One white picket panel, 1.4 x 0.6 studs along X: five pickets on two rails. Panels set 1.4
    apart carry the pickets on at one even pitch."""
    p = Part("picket-fence")
    for i in range(5):
        x = -0.56 + i * 0.28
        p.box(x - 0.08, x + 0.08, 0.05, 0.6, -0.03, 0.03, WHITE)
    for y in (0.18, 0.44):
        p.box(-0.7, 0.7, y - 0.035, y + 0.035, 0.03, 0.07, WALL_SHADE)
    return p


def make_mailbox() -> Part:
    """A kerbside mailbox, 0.35 x 0.9 x 0.45 studs: a pale box on a post with its red flag up. As
    tall as a kit door at this scale, on purpose: any smaller and it is not there."""
    p = Part("mailbox")
    p.box(-0.05, 0.05, 0.0, 0.58, -0.05, 0.05, BRICK)
    p.box(-0.14, 0.14, 0.56, 0.8, -0.24, 0.2, LAVENDER, front=WALL, top=WALL)
    p.box(0.14, 0.18, 0.62, 0.9, -0.04, 0.05, RED)
    return p


def porch(name: str, roof) -> Part:
    """A front porch, 1.8 x 1.35 x 0.95 studs: a step, two white posts and a lean-to roof. Its origin
    is on the wall line; it reaches 0.95 toward -Z."""
    colour, edge = roof
    p = Part(name)
    p.box(-0.8, 0.8, 0.0, 0.1, -0.85, 0.0, LAVENDER, top=WALL_SHADE)
    for x in (-0.7, 0.7):
        p.box(x - 0.05, x + 0.05, 0.1, 1.08, -0.8, -0.7, WHITE)
    ring = [(-0.9, 1.0, -0.95), (0.9, 1.0, -0.95), (0.9, 1.25, 0.0), (-0.9, 1.25, 0.0)]
    p.hexa(ring + [(x, y + 0.1, z) for x, y, z in ring], colour, front=edge, left=edge, right=edge,
           bottom=WALL_SHADE)
    return p


def make_porch_green() -> Part:
    """The porch under the kits' green roof."""
    return porch("porch-green", ROOF_GREEN)


def make_porch_grey() -> Part:
    """The porch under a grey roof, for a house whose roof skin is grey."""
    return porch("porch-grey", ROOF_GREY)


def make_carport() -> Part:
    """A carport, 1.9 x 1.32 x 2.6 studs: four white posts under a flat slate roof with a white
    fascia. Origin at the bottom centre; cars drive in from -Z."""
    p = Part("carport")
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * 0.85, sz * 1.2
            p.box(x - 0.05, x + 0.05, 0.0, 1.2, z - 0.05, z + 0.05, WHITE)
    p.box(-0.95, 0.95, 1.2, 1.32, -1.3, 1.3, WALL, top=SLATE)
    return p


def lawn(name: str, half: float, seed: int, patches) -> Part:
    """A lawn for a lived-in lot: a 0.05-stud turf with rounded, slightly ragged corners and a few
    lighter patches 0.03 above it. It stops short of the lot line, and a home's path, hedge and
    flower bed break it up, so it reads as a garden, not as a green mat."""
    p = Part(name)
    rng = random.Random(seed)
    points, power = 28, 5.0
    outline = []
    for k in range(points):
        a = 2 * math.pi * (k + 0.5) / points
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** power + abs(s) ** power) ** (-1.0 / power)
        j = min(1.0, 1.0 + rng.uniform(-0.035, 0.02))
        outline.append((half * r * c * j, half * r * s * j))
    prism(p, outline, 0.0, 0.05, LAWN)
    for cx, cz, rx, rz in patches:
        prism(p, blotch(rng, cx, cz, rx, rz), 0.0, 0.08, LAWN_LIGHT)
    return p


def make_lawn_small() -> Part:
    """The lawn of a 6 x 6 lot, 5.6 studs across."""
    return lawn("lawn-small", 2.8, 181, ((-1.6, -1.5, 0.8, 0.55), (1.5, 1.7, 0.7, 0.5), (1.7, -1.9, 0.6, 0.4)))


def make_lawn_medium() -> Part:
    """The lawn of an 8 x 8 lot, 7.6 studs across."""
    return lawn("lawn-medium", 3.8, 182,
                ((-2.3, -2.2, 1.1, 0.7), (2.4, 2.5, 0.9, 0.6), (2.5, -2.6, 0.8, 0.5), (-2.6, 2.4, 0.7, 0.5)))


def make_hedge() -> Part:
    """A clipped garden hedge, 1.4 x 0.5 x 0.4 studs along X: a dark core under three rounded crowns.
    Lengths butt end to end."""
    p = Part("hedge")
    p.box(-0.7, 0.7, 0.0, 0.3, -0.2, 0.2, HEDGE_DARK)
    for i in range(3):
        x = -0.46 + i * 0.46
        p.blob((x, 0.3, 0.0), (0.25, 0.2, 0.21), GREEN_DARK, seg=5, rings=2, cut=0.0, jitter=0.05, seed=191 + i)
    return p


def make_flower_bed() -> Part:
    """A flower bed, 1.4 x 0.35 x 0.5 studs along X: dark earth on a stone kerb, six leaf tufts
    under red, yellow, pink and white blooms."""
    p = Part("flower-bed")
    p.box(-0.7, 0.7, 0.0, 0.1, -0.25, 0.25, STONE, top=EARTH_DARK)
    blooms = (RED, YELLOW, PINK, WHITE, YELLOW, RED)
    for i, bloom in enumerate(blooms):
        x = -0.55 + i * 0.22
        z = 0.07 if i % 2 else -0.07
        p.box(x - 0.09, x + 0.09, 0.1, 0.24, z - 0.09, z + 0.09, GREEN_DARK)
        p.box(x - 0.055, x + 0.055, 0.24, 0.35, z - 0.055, z + 0.055, bloom)
    return p


def make_home_a_dress() -> Part:
    """FabricHomeSmallA (building-type-l): a red roof on the mono-pitch and a yellow front door."""
    p = Part("home-a-dress")
    roof_skin(p, "building-type-l", *ROOF_RED, HOME)
    door_slab(p, -0.323, -0.183, -0.340, YELLOW)
    return p


def make_home_b_dress() -> Part:
    """FabricHomeSmallB (building-type-u): the kit's green roof, a red front door, navy shutters."""
    p = Part("home-b-dress")
    door_slab(p, -0.014, 0.126, -0.307, RED)
    shutters(p, -0.444, -0.244, 0.15, 0.25, -0.287, NAVY)
    shutters(p, -0.044, 0.156, 0.55, 0.65, -0.287, NAVY)
    shutters(p, 0.356, 0.556, 0.55, 0.65, -0.287, NAVY)
    return p


def make_home_c_dress() -> Part:
    """FabricHomeSmallC (building-type-f): a blue-slate roof, porch roofs and dormer too, and a
    yellow front door."""
    p = Part("home-c-dress")
    roof_skin(p, "building-type-f", *ROOF_BLUE, HOME)
    door_slab(p, -0.014, 0.126, -0.555, YELLOW)
    return p


def make_home_d_dress() -> Part:
    """FabricHomeSmallD (building-type-n): the kit's green roof, a navy front door, red shutters."""
    p = Part("home-d-dress")
    door_slab(p, -0.214, -0.074, -0.259, NAVY)
    shutters(p, -0.644, -0.444, 0.15, 0.25, -0.239, RED)
    shutters(p, -0.644, -0.444, 0.55, 0.65, -0.239, RED)
    shutters(p, -0.244, -0.044, 0.55, 0.65, -0.239, RED)
    return p


def make_home_e_dress() -> Part:
    """FabricHomeSmallE (building-type-h): a brown roof cap over the solar panels, a green front
    door and a bay window in place of the right-hand window."""
    p = Part("home-e-dress")
    h_roof_cap(p, ROOF_BROWN)
    door_slab(p, -0.07, 0.07, -0.400, GREEN_DARK)
    bay_window(p, 0.4, -0.400, ROOF_BROWN)
    return p


def make_home_f_dress() -> Part:
    """FabricHomeSmallF (building-type-m): a grey roof and a red front door."""
    p = Part("home-f-dress")
    roof_skin(p, "building-type-m", *ROOF_GREY, HOME)
    door_slab(p, -0.014, 0.126, -0.544, RED)
    return p


def make_home_ma_dress() -> Part:
    """FabricHomeMediumA (building-type-h), stage 0: a blue-slate roof cap over the solar panels and
    a red front door."""
    p = Part("home-ma-dress")
    h_roof_cap(p, ROOF_BLUE)
    door_slab(p, -0.07, 0.07, -0.400, RED)
    return p


def make_home_ma_garage() -> Part:
    """FabricHomeMediumA, stage 1: a garage against the west gable end, in the house's frame. It
    overlaps the wall by 0.04, so the verge of the roof ends inside it."""
    p = Part("home-ma-garage")
    x0, x1 = -H_WALL_X - 2.16, -H_WALL_X + 0.04
    flat_wing(p, x0, x1, -1.05, 1.45)
    garage_door(p, (x0 + x1) / 2, -1.05)
    return p


def make_home_ma_upper() -> Part:
    """FabricHomeMediumA, stage 2: a second storey, in the house's frame. It is as wide as the roof
    cap plus 0.02 and starts at 0.95, under the eave fascia (0.98), so the kit roof and its cap end
    up inside it; its blue-slate gable repeats the kit's pitch. Ridge 3.25, chimney top 3.6."""
    p = Part("home-ma-upper")
    hx, hz = H_CAP_X + 0.02, H_CAP_Z + 0.02
    y0, y1 = 0.95, 0.95 + STOREY_H + 0.05
    home_storey(p, -hx, hx, -hz, hz, y0, y1)
    for x in (-1.15, 0.0, 1.15):
        pane(p, "z", -hz, -1, x - 0.35, x + 0.35, y0 + 0.5, y0 + 1.0, mullion=True)
    for x in (-0.8, 0.8):
        pane(p, "z", hz, 1, x - 0.35, x + 0.35, y0 + 0.5, y0 + 1.0)
    for facing in (-1, 1):
        pane(p, "x", facing * hx, facing, -0.35, 0.35, y0 + 0.5, y0 + 1.0)
    gable_roof(p, 0.0, 0.0, hx, hz, y1, 0.95, roof=ROOF_BLUE)
    home_chimney(p, 1.0, 0.5, y1 + 0.4, 3.6)
    return p


def make_home_mb_dress() -> Part:
    """FabricHomeMediumB (building-type-m), stage 0: the kit's green roof, a yellow front door and
    navy shutters on the front window."""
    p = Part("home-mb-dress")
    door_slab(p, -0.014, 0.126, -0.544, YELLOW)
    shutters(p, 0.356, 0.556, 0.15, 0.25, -0.524, NAVY)
    return p


def make_home_mb_wing() -> Part:
    """FabricHomeMediumB, stage 1: a side wing against the west gable end (x -1.58), in the house's
    frame: a sun room with a wide window to the street and one to the side, and a carport over the
    drive of the kit house's own garage, which is in the notch beside it. (A first cut put a
    second garage here.) The wing stands 0.35 forward of the wall behind it and takes in the two
    kit bushes there; the carport's roof rests at the notch's eaves."""
    p = Part("home-mb-wing")
    x0, x1, z0, z1 = -3.7, -1.5, -0.75, 1.85
    flat_wing(p, x0, x1, z0, z1)
    pane(p, "z", z0, -1, x0 + 0.35, x1 - 0.35, 0.36, 0.98, mullion=True)
    pane(p, "x", x0, -1, 0.1, 1.0, 0.4, 0.95, mullion=True)
    pane(p, "z", z1, 1, x0 + 0.6, x1 - 0.6, 0.4, 0.95)
    # the carport: the notch is x -1.58..-0.12, its wall at z -0.40; two posts out front
    cx0, cx1, cz0, cz1 = -1.46, -0.16, -2.7, -0.5
    p.box(cx0, cx1, 1.1, 1.2, cz0, cz1, WALL, top=SLATE)
    for x in (cx0 + 0.06, cx1 - 0.06):
        p.box(x - 0.05, x + 0.05, 0.0, 1.1, cz0 + 0.06, cz0 + 0.16, WHITE)
    return p


def make_home_mb_upper() -> Part:
    """FabricHomeMediumB, stage 2: a room over the side wing, 0.03 proud of it all round so the
    wing's kerb ends up inside, under a green gable that faces the street. The L-shaped cross-gable
    roof of the kit house cannot take a storey, so the house grows beside its roof, not on it.
    Ridge 3.3."""
    p = Part("home-mb-upper")
    e = 0.03
    x0, x1, z0, z1 = -3.7 - e, -1.5 + e, -0.75 - e, 1.85 + e
    y0, y1 = WING_H, WING_H + STOREY_H - 0.05
    home_storey(p, x0, x1, z0, z1, y0, y1)
    cx = (x0 + x1) / 2
    pane(p, "z", z0, -1, cx - 0.55, cx + 0.55, y0 + 0.42, y0 + 0.92, mullion=True)
    pane(p, "z", z1, 1, cx - 0.4, cx + 0.4, y0 + 0.42, y0 + 0.92)
    for z in (-0.05, 1.15):
        pane(p, "x", x0, -1, z - 0.33, z + 0.33, y0 + 0.42, y0 + 0.92)
    gable_roof(p, cx, (z0 + z1) / 2, (z1 - z0) / 2, (x1 - x0) / 2, y1, 0.85, rot=90.0)
    return p


# --- the works (studs at blueprint scale WORKS) ---------------------------------------------------
#
# The industry district's lots. The small works (6 x 6) are generated outright, one piece per stage
# in the lot frame, each with its own wall and roof tones so an industrial block is not a field of
# identical dark roofs: A is a white workshop under rust-red roofs, B a grey warehouse under pale
# tin. The medium works (8 x 8) is the industrial kit's shed and warehouse at blueprint scale 2.8
# with a generated yard, dock and tank; its roofs are the kit's dark slate.

WORKS = 2.8
ROOF_RUST = (TERRACOTTA, BRICK)
ROOF_TIN = (WALL_SHADE, STONE)
ROOF_STEEL = (LAVENDER, STONE_DARK)


def disc_z(p: Part, z0: float, z1: float, x: float, y: float, r: float, colour: Rgb, seg: int = 8) -> None:
    """A drum lying down: a faceted disc whose axis runs along Z."""
    outline = [(x + r * math.cos(2 * math.pi * (k + 0.5) / seg), y + r * math.sin(2 * math.pi * (k + 0.5) / seg))
               for k in range(seg)]
    extrude_z(p, outline, z0, z1, colour)


def fence_run(p: Part, a, b) -> None:
    """A yard fence from a to b ((x, z), axis-aligned): three slate rails on posts no more than
    2 studs apart, 0.9 tall. Open rails, not boards: a run can stand between the camera and the
    yard, and a boarded fence there hides everything in it."""
    ax, az = a
    bx, bz = b
    length = math.hypot(bx - ax, bz - az)
    count = max(1, math.ceil(length / 2.0))
    for k in range(count + 1):
        x, z = ax + (bx - ax) * k / count, az + (bz - az) * k / count
        p.box(x - 0.07, x + 0.07, 0.0, 0.9, z - 0.07, z + 0.07, SLATE)
    x0, x1 = sorted((ax, bx))
    z0, z1 = sorted((az, bz))
    for y in (0.3, 0.55, 0.8):
        p.box(x0 - 0.03, x1 + 0.03, y - 0.035, y + 0.035, z0 - 0.03, z1 + 0.03, SLATE_LIGHT)


def gate(p: Part, x0: float, x1: float, z: float, leaf_from: float) -> None:
    """A works gateway on the street side: two taller posts with orange caps, and a sliding gate
    leaf drawn half open from `leaf_from` to x1."""
    for x in (x0, x1):
        p.box(x - 0.1, x + 0.1, 0.0, 1.3, z - 0.1, z + 0.1, SLATE, top=ORANGE)
    for y in (0.2, 0.9):
        p.box(leaf_from, x1, y - 0.04, y + 0.04, z + 0.11, z + 0.17, SLATE_LIGHT)
    count = max(2, round((x1 - leaf_from) / 0.35))
    for k in range(count + 1):
        x = leaf_from + (x1 - leaf_from) * k / count
        p.box(x - 0.035, x + 0.035, 0.2, 0.9, z + 0.11, z + 0.17, SLATE_LIGHT)


def yard_ground(p: Part, hx: float, hz: float, seed: int, patches) -> None:
    """A works yard: packed grey hardcore with ragged edges and paler worn patches."""
    rng = random.Random(seed)
    points, power = 28, 6.0
    outline = []
    for k in range(points):
        a = 2 * math.pi * (k + 0.5) / points
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** power + abs(s) ** power) ** (-1.0 / power)
        j = min(1.0, 1.0 + rng.uniform(-0.03, 0.02))
        outline.append((hx * r * c * j, hz * r * s * j))
    prism(p, outline, 0.0, 0.05, STONE_DARK)
    for cx, cz, rx, rz in patches:
        prism(p, blotch(rng, cx, cz, rx, rz), 0.0, 0.08, STONE)


def shed_walls(p: Part, x0: float, x1: float, z0: float, z1: float, height: float, wall: Rgb, top: Rgb) -> None:
    """Plain works walls on a slate plinth; the caller roofs them."""
    p.box(x0, x1, 0.0, height, z0, z1, wall, top=top)
    e = 0.02
    p.box(x0 - e, x1 + e, 0.0, 0.16, z0 - e, z1 + e, SLATE)


def roller_door(p: Part, x0: float, x1: float, y1: float, z: float, colour: Rgb, rib: Rgb) -> None:
    """A roller door on a wall facing -Z at z: a slate frame, a coloured shutter, two ribs."""
    p.box(x0 - 0.08, x1 + 0.08, 0.0, y1 + 0.08, z - 0.04, z, SLATE)
    p.box(x0, x1, 0.0, y1, z - 0.06, z, colour)
    for k in (1, 2):
        y = y1 * k / 3
        p.box(x0, x1, y - 0.025, y + 0.025, z - 0.075, z, rib)


def pallets(p: Part, x: float, z: float, count: int, rot: float = 0.0) -> None:
    """A stack of `count` pallets, 1.1 x 0.9 across, the top one askew."""
    pallet = Part("pallet")
    for dz in (-0.38, 0.38):
        pallet.box(-0.55, 0.55, 0.0, 0.08, dz - 0.07, dz + 0.07, BRICK)
    pallet.box(-0.55, 0.55, 0.08, 0.15, -0.45, 0.45, WOOD, top=SAND)
    for i in range(count):
        place(p, pallet, rot + (9.0 if i == count - 1 and count > 1 else 0.0), (x, 0.05 + 0.16 * i, z))


def make_works_a_yard() -> Part:
    """FabricWorksSmallA, stage 0, in the lot frame: a lean-to shed under a rust-red roof at the
    back left, a fenced yard with a gateway, a rack of fuel drums and a hand truck. 1.75 tall."""
    p = Part("works-a-yard")
    yard_ground(p, 2.85, 2.85, 211, ((-1.2, -1.2, 0.9, 0.6), (1.4, 0.2, 0.8, 0.5)))
    fence_run(p, (-2.8, -2.8), (-0.9, -2.8))
    gate(p, -0.9, 1.3, -2.8, 0.2)
    fence_run(p, (1.3, -2.8), (2.8, -2.8))
    fence_run(p, (2.8, -2.8), (2.8, 0.1))
    # the lean-to: 2.4 x 1.8, the roof falling to the back
    x0, x1, z0, z1 = -2.7, -0.3, 0.9, 2.7
    front, back = 1.6, 1.25  # wall heights: one wedge, so no gap is left under the slope
    p.hexa([(x0, 0.0, z0), (x1, 0.0, z0), (x1, 0.0, z1), (x0, 0.0, z1),
            (x0, front, z0), (x1, front, z0), (x1, back, z1), (x0, back, z1)], WALL, top=SLATE)
    p.box(x0 - 0.02, x1 + 0.02, 0.0, 0.16, z0 - 0.02, z1 + 0.02, SLATE)
    colour, edge = ROOF_RUST
    fall = (front - back) / (z1 - z0)
    ring = [(x0 - 0.1, front + 0.15 * fall, z0 - 0.15), (x1 + 0.1, front + 0.15 * fall, z0 - 0.15),
            (x1 + 0.1, back - 0.1 * fall, z1 + 0.1), (x0 - 0.1, back - 0.1 * fall, z1 + 0.1)]
    p.hexa(ring + [(x, y + 0.1, z) for x, y, z in ring], colour, front=edge, back=edge, left=edge, right=edge,
           bottom=WALL_SHADE)
    roller_door(p, -2.3, -1.3, 1.0, z0, ORANGE, TERRACOTTA)
    pane(p, "z", z0, -1, -1.0, -0.5, 0.55, 0.95)
    # the drum rack: two tiers of two drums on a slate frame, ends to the street
    rx, rz = -1.9, -1.1
    for x in (rx - 0.52, rx + 0.52):
        p.box(x - 0.04, x + 0.04, 0.05, 1.05, rz - 0.4, rz + 0.4, SLATE)
    for y in (0.14, 0.6):
        p.box(rx - 0.52, rx + 0.52, y - 0.04, y, rz - 0.4, rz + 0.4, SLATE_LIGHT)
    for (dx, y), colour in (((-0.25, 0.35), NAVY), ((0.25, 0.35), ORANGE), ((-0.25, 0.81), RED), ((0.25, 0.81), NAVY)):
        disc_z(p, rz - 0.36, rz + 0.36, rx + dx, y, 0.2, colour)
    # the hand truck, parked by the gate
    hx, hz = 1.9, -1.9
    for sx in (-1, 1):
        beam(p, (hx + sx * 0.16, 0.12, hz), (hx + sx * 0.16, 1.0, hz + 0.3), 0.05, 0.05, RED)
        disc_x(p, hx + sx * 0.2 - 0.03, hx + sx * 0.2 + 0.03, 0.13, hz + 0.02, 0.13, CHARCOAL, seg=6)
    p.box(hx - 0.2, hx + 0.2, 0.05, 0.09, hz - 0.3, hz, RED)
    beam(p, (hx - 0.16, 0.6, hz + 0.165), (hx + 0.16, 0.6, hz + 0.165), 0.05, 0.05, RED)
    return p


def make_works_a_shop() -> Part:
    """FabricWorksSmallA, stage 1, in the lot frame: the workshop beside the lean-to, white walls
    under a rust-red gable that faces the street, a big orange sliding door, a flue. 3.1 tall."""
    p = Part("works-a-shop")
    x0, x1, z0, z1 = 0.0, 2.75, 0.3, 2.75
    shed_walls(p, x0, x1, z0, z1, 1.8, WALL, SLATE)
    gable_roof(p, (x0 + x1) / 2, (z0 + z1) / 2, (z1 - z0) / 2, (x1 - x0) / 2, 1.8, 0.85, roof=ROOF_RUST, rot=90.0)
    roller_door(p, 0.45, 1.75, 1.35, z0, ORANGE, TERRACOTTA)
    pane(p, "z", z0, -1, 2.0, 2.5, 0.7, 1.2)
    pane(p, "x", x1, 1, 0.9, 1.9, 0.7, 1.25, mullion=True)
    pane(p, "z", z1, 1, 0.8, 1.9, 0.7, 1.25, mullion=True)
    ring = [(0.35 * math.cos(2 * math.pi * (k + 0.5) / 8) + (x0 + x1) / 2,
             2.25 + 0.2 * math.sin(2 * math.pi * (k + 0.5) / 8)) for k in range(8)]
    extrude_z(p, ring, z0 - 0.05, z0, SLATE)  # the gable vent
    p.box(2.15, 2.35, 2.1, 3.1, 1.9, 2.1, SLATE_LIGHT, top=CHARCOAL)  # the flue
    return p


def make_works_b_store() -> Part:
    """FabricWorksSmallB, stage 0, in the lot frame: a flat-roofed grey store with a blue loading
    door under a pale tin roof, a fenced yard with a gateway and two stacks of pallets. 1.75 tall."""
    p = Part("works-b-store")
    yard_ground(p, 2.85, 2.85, 221, ((1.3, -1.3, 0.9, 0.6), (-1.5, 0.0, 0.7, 0.5)))
    fence_run(p, (-2.8, -2.8), (-1.9, -2.8))
    gate(p, -1.9, 0.3, -2.8, -0.8)
    fence_run(p, (0.3, -2.8), (2.8, -2.8))
    fence_run(p, (-2.8, -2.8), (-2.8, 0.3))
    x0, x1, z0, z1 = -2.7, 0.5, 0.6, 2.7
    shed_walls(p, x0, x1, z0, z1, 1.6, STONE, ROOF_TIN[0])
    k = 0.12
    p.box(x0, x1, 1.6, 1.75, z0, z0 + k, WALL_SHADE)
    p.box(x0, x1, 1.6, 1.75, z1 - k, z1, WALL_SHADE)
    for xa, xb in ((x0, x0 + k), (x1 - k, x1)):
        p.box(xa, xb, 1.6, 1.75, z0 + k, z1 - k, WALL_SHADE)
    roller_door(p, -2.2, -0.9, 1.2, z0, BLUE, NAVY)
    door(p, -0.4, 0.1, 1.0, z0, -1, SLATE_LIGHT, glazed=False)
    pane(p, "z", z1, 1, -1.6, -0.6, 0.6, 1.1, mullion=True)
    pallets(p, 1.5, -0.9, 3)
    pallets(p, -1.9, -1.3, 2, rot=90.0)
    return p


def make_works_b_bay() -> Part:
    """FabricWorksSmallB, stage 1, in the lot frame: a taller warehouse bay beside the store, grey
    walls under a pale steel gable, a loading door with a canopy and a yellow sign on the gable.
    2.95 tall."""
    p = Part("works-b-bay")
    x0, x1, z0, z1 = 0.7, 2.75, -0.2, 2.75
    shed_walls(p, x0, x1, z0, z1, 2.1, STONE, SLATE)
    gable_roof(p, (x0 + x1) / 2, (z0 + z1) / 2, (z1 - z0) / 2, (x1 - x0) / 2, 2.1, 0.75, roof=ROOF_STEEL, rot=90.0,
               gable=STONE)
    roller_door(p, 1.05, 2.4, 1.3, z0, BLUE, NAVY)
    p.box(0.95, 2.5, 1.5, 1.58, z0 - 0.45, z0, WALL_SHADE, top=SLATE_LIGHT)  # the canopy
    p.box(1.15, 2.3, 1.75, 2.15, z0 - 0.06, z0, YELLOW)  # the sign
    p.box(1.3, 2.15, 1.87, 2.03, z0 - 0.08, z0 - 0.06, SLATE)
    pane(p, "x", x1, 1, 0.6, 1.8, 1.0, 1.5, mullion=True)
    pane(p, "z", z1, 1, 1.2, 2.2, 1.0, 1.5, mullion=True)
    return p


# The medium works, in the lot frame at scale 2.8: building-p (the shed) at the street on the left,
# x -3.9..0.81, z -3.3..-0.53; building-t (the warehouse) behind and to the right, x -1.01..3.81,
# z -0.05..3.85, its sawtooth front (x 0.28..3.64, wall at z 0.43) looking over the yard to the
# street. (A first cut stood the shed in front of the warehouse and hid that front.)
T_FRONT = 0.43


def make_works_yard() -> Part:
    """FabricWorksMediumA, stage 0, in the lot frame: the yard in front of where the warehouse will
    stand, fenced on the street and the east side with a gateway, an apron in front of the shed,
    a stack of pallets and a few drums."""
    p = Part("works-yard")
    p.box(0.95, 3.95, 0.0, 0.05, -3.95, 0.4, STONE_DARK)
    p.box(-3.95, 0.95, 0.0, 0.05, -3.95, -3.3, STONE_DARK)
    gate(p, 1.1, 2.9, -3.8, 2.0)
    fence_run(p, (2.9, -3.8), (3.85, -3.8))
    fence_run(p, (3.85, -3.8), (3.85, -0.2))
    pallets(p, 3.1, -2.6, 3)
    for (x, z), colour in (((1.5, -0.5), NAVY), ((1.95, -0.42), ORANGE), ((1.7, -0.95), SLATE_LIGHT)):
        lathe(p, [(0.22, 0.05), (0.22, 0.8)], [colour], seg=8, at=(x, 0.0, z))
        lathe(p, [(0.15, 0.8), (0.15, 0.82)], [SLATE], seg=6, at=(x, 0.0, z))
    return p


def make_works_dock() -> Part:
    """FabricWorksMediumA, stage 2, in the lot frame: the loading dock on the warehouse's street
    front (wall at z 0.43), at its east end where the camera sees it: a concrete platform with a
    step, an orange roller door, a flat canopy on two posts and two crates on the deck. 1.9 tall."""
    p = Part("works-dock")
    x0, x1, z1 = 2.45, 3.6, T_FRONT + 0.02
    z0 = z1 - 0.95
    p.box(x0, x1, 0.0, 0.45, z0, z1, STONE, top=LAVENDER)
    p.box(x0, x1, 0.25, 0.45, z0 - 0.04, z0, SLATE)
    p.box(x0 - 0.4, x0, 0.0, 0.22, z0, z1, STONE_DARK, top=STONE)
    p.box(x0 + 0.1, x1 - 0.1, 0.45, 1.5, z1 - 0.12, z1, SLATE)
    p.box(x0 + 0.17, x1 - 0.17, 0.45, 1.43, z1 - 0.15, z1, ORANGE)
    for y in (0.78, 1.1):
        p.box(x0 + 0.17, x1 - 0.17, y - 0.025, y + 0.025, z1 - 0.17, z1, TERRACOTTA)
    for x in (x0 + 0.07, x1 - 0.07):
        p.box(x - 0.05, x + 0.05, 0.45, 1.78, z0 + 0.03, z0 + 0.13, SLATE)
    p.box(x0 - 0.05, x1 + 0.05, 1.78, 1.9, z0 - 0.08, z1, SLATE_LIGHT, top=SLATE)
    p.box(x0 + 0.1, x0 + 0.5, 0.45, 0.82, z0 + 0.15, z0 + 0.55, WOOD, top=SAND)
    return p


def make_works_tank() -> Part:
    """A vertical process tank on four legs, 1.15 studs across and 2.45 tall: white, with the
    industrial kit's orange band and a slate vent."""
    p = Part("works-tank")
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * 0.36, sz * 0.36
            p.box(x - 0.05, x + 0.05, 0.0, 0.75, z - 0.05, z + 0.05, SLATE)
    profile = [(0.3, 0.5), (0.62, 0.72), (0.62, 1.2), (0.62, 1.45), (0.62, 2.05), (0.3, 2.3), (0.0, 2.33)]
    lathe(p, profile, [LAVENDER, WALL, ORANGE, WALL, WALL_SHADE, WALL_SHADE], seg=8, phase=math.pi / 8)
    p.box(-0.06, 0.06, 2.3, 2.45, -0.06, 0.06, SLATE)
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
    "shop-d-ground": make_shop_d_ground,
    "shop-d-front": make_shop_d_front,
    "shop-d-upper": make_shop_d_upper,
    "picket-fence": make_picket_fence,
    "mailbox": make_mailbox,
    "porch-green": make_porch_green,
    "porch-grey": make_porch_grey,
    "carport": make_carport,
    "lawn-small": make_lawn_small,
    "lawn-medium": make_lawn_medium,
    "hedge": make_hedge,
    "flower-bed": make_flower_bed,
    "home-a-dress": make_home_a_dress,
    "home-b-dress": make_home_b_dress,
    "home-c-dress": make_home_c_dress,
    "home-d-dress": make_home_d_dress,
    "home-e-dress": make_home_e_dress,
    "home-f-dress": make_home_f_dress,
    "home-ma-dress": make_home_ma_dress,
    "home-ma-garage": make_home_ma_garage,
    "home-ma-upper": make_home_ma_upper,
    "home-mb-dress": make_home_mb_dress,
    "home-mb-wing": make_home_mb_wing,
    "home-mb-upper": make_home_mb_upper,
    "works-a-yard": make_works_a_yard,
    "works-a-shop": make_works_a_shop,
    "works-b-store": make_works_b_store,
    "works-b-bay": make_works_b_bay,
    "works-yard": make_works_yard,
    "works-dock": make_works_dock,
    "works-tank": make_works_tank,
}

# The blueprint scale each piece is written for, where it is not STUDS_PER_UNIT.
PIECE_SCALE = {
    "picket-fence": HOME,
    "mailbox": HOME,
    "porch-green": HOME,
    "porch-grey": HOME,
    "carport": HOME,
    "lawn-small": HOME,
    "lawn-medium": HOME,
    "hedge": HOME,
    "flower-bed": HOME,
    "home-a-dress": HOME,
    "home-b-dress": HOME,
    "home-c-dress": HOME,
    "home-d-dress": HOME,
    "home-e-dress": HOME,
    "home-f-dress": HOME,
    "home-ma-dress": HOME,
    "home-ma-garage": HOME,
    "home-ma-upper": HOME,
    "home-mb-dress": HOME,
    "home-mb-wing": HOME,
    "home-mb-upper": HOME,
    "works-a-yard": WORKS,
    "works-a-shop": WORKS,
    "works-b-store": WORKS,
    "works-b-bay": WORKS,
    "works-yard": WORKS,
    "works-dock": WORKS,
    "works-tank": WORKS,
}


# --- export -------------------------------------------------------------------------------------


def to_kit_units(part: Part, studs_per_unit: float) -> Part:
    out = Part(part.name)
    k = 1.0 / studs_per_unit
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
        scale = PIECE_SCALE.get(name, STUDS_PER_UNIT)
        export(build_object(to_kit_units(part, scale), {}), out_dir)
        total += part.tris
        lo, hi = part.bounds()
        print(
            f"[{KIT}] {name}.glb: {part.tris} tris, "
            f"x[{lo[0]:.2f}, {hi[0]:.2f}] y[{lo[1]:.2f}, {hi[1]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}] "
            f"studs at scale {scale:g}",
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
