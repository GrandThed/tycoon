"""Prairie farmland and town greens for the Boomtown growing city (M12 wave 2), generated as a
Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/farmland_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/farmland-kit/Models/GLB format/, the folder
convention every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. Mesh helpers and the export plumbing come from
garden_kit.py and village_extras_kit.py.

Why a custom kit (INTERFACES "M12 wave 2 -- Boomtown"; docs/CITY_GROWTH.md sections 2.1 and 4):
Boomtown's wild land is 1950s prairie farmland that the town replaces field by field, and neither
city-kit-suburban nor city-kit-industrial has a crop, a bale, a rail fence, a cow, a barn, a silo
or a wind pump, nor a broadleaf tree. Their only farm-like pieces are two conifer-shaped trees and a
brick-brown board fence. The civic lots round the Clock Tower, the Fire Station and the Radio
Station need the same grass and the same tree, a bench, a flower bed and a bandstand, so their
pieces live here too.

**Units -- read before placing a piece.** These GLBs are in Kenney kit units, **1 unit = 4 studs at
blueprint scale 4.0**, the village-extras-kit convention: a blueprint has one scale for all of its
pieces, and Boomtown props mix these with suburban and industrial pieces, which are scale 4. The
literals below are written in studs as they come out at scale 4.0 and are divided by
STUDS_PER_UNIT once, at export.

**The field contract** (INTERFACES "Fabric data"): a field is a fabric clump, four copies of one
quarter. A quarter holds one 6 x 6-stud patch in the local (+X, +Z) quadrant with its inner corner
at the clump origin, so:
- field-wheat, field-rowcrop, field-plough and pasture-grass are patches PATCH studs square,
  bottom-centre origin, rows along X. A quarter blueprint places one at (PATCH_CENTRE,
  PATCH_CENTRE): the patch stops PATCH_INSET short of the two inner edges, which leaves a strip of
  bare ground between the quarters of a field, and the row direction then alternates from quarter
  to quarter.
- field-fence is the quarter's post-and-rail fence along its two OUTER edges. Its origin is the
  quarter's inner corner, NOT its bottom centre: placed at the clump origin at the quarter's turn,
  four of them close into one fence round the field. The posts are spaced so that the gap across
  two quarters' meeting point equals the gap everywhere else, and the rails run to the axis, so
  the join does not show; a lone quarter keeps an L of fence with a short rail overhang.
- Nothing reaches past 6.0 studs from the origin on either axis (the fence's outer face is at
  5.96), so fields at a 13-stud pitch keep a stud of bare ground between their fences.

Every other piece has its origin at its bottom centre, and fronts face -Z. green-small and
green-medium are whole lot floors (6 x 6 and 8 x 8), with the lot's street side on -Z.

Colours are texels of city-kit-suburban's colormap.png (the four City Kits share one palette), and
the turned soil of city-kit-industrial's, so the pieces sit in Boomtown's palette. They are tuned
against the Boomtown plot base (173, 138, 93), a dusty tan that is not in the colormap: wheat takes
the kit's saturated yellows over a darker stubble so it cannot sink into the ground, ploughed earth
brown ridges over the dark end of the brick ramp, and the fence the kit's cream, because the
suburban fence's brick brown is nearly the ground's own value. Materials are plain colour factors
with no texture, written linear like garden-kit's; merge_stages.py routes them through palette.py
(not an sRGB-factor kit).

Art rules, matching the kits: flat shading, axis-aligned boxes and square-cut timbers, faceted
solids of revolution, chunky toy proportions. Crops are extruded ridges and four-sided tufts, not
blades: a field is instanced dozens of times per plot, so triangles per prop are what count.

**Every face belongs to a solid.** Roblox culls back faces, so nothing here is a lone sheet: thin
things (a sail, a worn patch of ground, the heart of a bale) are thin solids or rings in their
solid's own skin. A solid is either closed or open only at its underside, where it rests on the
ground or on the piece it stands on and nobody can look in: a patch's, a crop row's and a fence
post's bottoms are left out to save triangles. That rim is always one flat loop, which is what the
signed-volume check of the wave 2.3 report measures from.
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
from village_extras_kit import beam, blotch, crown, extrude_x, extrude_z, face_out, lathe, lit  # noqa: E402

import bpy  # noqa: E402

KIT = "farmland-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")
STUDS_PER_UNIT = 4.0

# The field contract, in studs (see the module docstring).
QUARTER = 6.0  # a quarter's side
PATCH_INSET = 0.2  # bare ground between a patch and the quarter's inner edges
FENCE_LINE = 5.85  # the fence's centre line, measured from the inner corner
PATCH = 5.35  # crop patch side: from the inset to just inside the fence posts
PATCH_CENTRE = PATCH_INSET + PATCH / 2  # 2.875: where a quarter blueprint puts its patch

Rgb = tuple[int, int, int]

# sRGB texels of assets/kenney3d/city-kit-suburban/Models/GLB format/Textures/colormap.png.
# The yellow ramp (awnings, shopfronts): ripe wheat and straw.
WHEAT_LIGHT = (255, 211, 99)
WHEAT_PALE = (255, 203, 92)
WHEAT_GOLD = (255, 194, 85)
WHEAT = (255, 192, 68)
WHEAT_DEEP = (255, 171, 66)
# The brick and timber ramp: stubble, the dark of a furrow, poles and the farmyard.
STUBBLE = (201, 131, 91)
SOIL_DARK = (131, 84, 66)
# Turned soil. These three are texels of city-kit-industrial's colormap.png (its brown swatch and
# the ramp above it), not the suburban one: the brick ramp is the only brown the suburban colormap
# has, and soil in it read as terracotta. These are the same value with a third less red.
SOIL = (159, 106, 82)
SOIL_LIGHT = (183, 128, 102)
SOIL_PALE = (188, 132, 108)
POLE = (153, 90, 65)
POLE_DARK = (131, 84, 66)
YARD = (212, 147, 108)
YARD_LIGHT = (220, 158, 119)
# The kit's green ramp (roofs, trees, planters): the only green in any City Kit colormap, hue 144
# to 165. LEAF is its lightest and yellowest step, so it is the grass.
LEAF = (97, 203, 139)
LEAF_MID = (76, 181, 129)
LEAF_DARK = (61, 167, 122)
# Fence timber: the cream wall swatch and the step under it.
CREAM = (253, 228, 199)
TIMBER = (242, 191, 153)
PEACH = (250, 174, 138)
# Barn red (doors, signs), its shaded step, and the terracotta swatch.
RED = (207, 83, 79)
RED_DARK = (196, 95, 79)
TERRACOTTA = (212, 116, 93)
WHITE = (255, 255, 255)
# The pale end of the wall ramp: tin roofs, concrete staves, sails, paving.
TIN_LIGHT = (236, 236, 243)
TIN = (220, 220, 233)
TIN_SHADE = (205, 205, 224)
# The stone and slate swatches: hoops, steelwork, glazing, a cow's markings.
STEEL_LIGHT = (179, 188, 225)
STEEL = (160, 168, 201)
STEEL_MID = (142, 149, 179)
STEEL_DARK = (102, 107, 128)
SLATE = (79, 82, 96)
CHARCOAL = (58, 60, 63)
GLASS = (208, 232, 255)
WATER = (165, 198, 240)
# Flowers: the kit's pink and purple sign swatches, with the red, yellow and white above.
PINK = (243, 120, 240)
PURPLE = (168, 120, 232)


# --- geometry helpers (glTF space, studs at scale 4) --------------------------------------------


def slab(p: Part, x0, x1, y0, y1, z0, z1, colour: Rgb, top: Rgb | None = None) -> None:
    """A box without its underside: for anything that stands on the ground or on another piece."""
    corners = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    lo = [(x, y0, z) for x, z in corners]
    hi = [(x, y1, z) for x, z in corners]
    face_out(p, hi, top or colour, (0.0, 1.0, 0.0))
    for i in range(4):
        j = (i + 1) % 4
        mx, mz = (corners[i][0] + corners[j][0]) / 2, (corners[i][1] + corners[j][1]) / 2
        face_out(p, [lo[i], lo[j], hi[j], hi[i]], colour, (mx - cx, 0.0, mz - cz))


def plate(p: Part, outline, y0: float, y1: float, colour: Rgb, top: Rgb | None = None) -> None:
    """slab() over any outline [(x, z)] that is star-shaped about its centroid: a top and a skirt,
    no underside."""
    cx = sum(x for x, _ in outline) / len(outline)
    cz = sum(z for _, z in outline) / len(outline)
    face_out(p, [(x, y1, z) for x, z in outline], top or colour, (0.0, 1.0, 0.0))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        (xa, za), (xb, zb) = outline[i], outline[j]
        face_out(p, [(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)], colour,
                 ((xa + xb) / 2 - cx, 0.0, (za + zb) / 2 - cz))


def rounded_square(rng: random.Random, half: float, points: int, power: float, wobble: float):
    """A square outline [(x, z)] with rounded corners and an edge that wanders inward by up to
    `wobble` of its radius: ground that was never drawn with a ruler."""
    out = []
    for k in range(points):
        a = 2 * math.pi * (k + 0.5) / points
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** power + abs(s) ** power) ** (-1.0 / power)
        j = 1.0 - rng.uniform(0.0, wobble)
        out.append((half * r * c * j, half * r * s * j))
    return out


def ridge(p: Part, outline, x0: float, x1: float, colours, ends: Rgb, lean: float = 0.0) -> None:
    """A crop row or furrow: a prism along X over the open polyline outline [(z, y)], which starts
    and ends on the ground. Face i (outline[i] to outline[i + 1]) takes colours[i]; there is no
    underside. `lean` slopes both ends inward by that much at the crest, so a row ends as a mound
    and not as a sawn bar."""
    cz = sum(z for z, _ in outline) / len(outline)
    cy = sum(y for _, y in outline) / len(outline)
    top = max(y for _, y in outline)
    a = [(x0 + lean * y / top, y, z) for z, y in outline]
    b = [(x1 - lean * y / top, y, z) for z, y in outline]
    face_out(p, a, ends, (-1.0, 0.0, 0.0))
    face_out(p, b, ends, (1.0, 0.0, 0.0))
    for i in range(len(outline) - 1):
        mz = (outline[i][0] + outline[i + 1][0]) / 2
        my = (outline[i][1] + outline[i + 1][1]) / 2
        face_out(p, [a[i], a[i + 1], b[i + 1], b[i]], colours[i], (0.0, my - cy, mz - cz))


def tuft(p: Part, x: float, z: float, y0: float, y1: float, r0: float, r1: float, turn: float,
         side: Rgb, top: Rgb) -> None:
    """A row-crop plant: a four-sided frustum with a lighter crown, turned about its axis. Ten
    triangles; at the tycoon camera a rounder head reads no differently."""
    angles = [turn + math.pi / 2 * k for k in range(4)]
    lo = [(x + r0 * math.cos(a), y0, z + r0 * math.sin(a)) for a in angles]
    hi = [(x + r1 * math.cos(a), y1, z + r1 * math.sin(a)) for a in angles]
    face_out(p, hi, top, (0.0, 1.0, 0.0))
    for k in range(4):
        n = (k + 1) % 4
        am = angles[k] + math.pi / 4
        face_out(p, [lo[k], lo[n], hi[n], hi[k]], side, (math.cos(am), 0.3, math.sin(am)))


def row_centres(count: int) -> list[float]:
    """Centre lines of `count` rows spread evenly across a patch."""
    pitch = PATCH / count
    return [-PATCH / 2 + pitch * (i + 0.5) for i in range(count)]


def fence_post(p: Part, x: float, z: float, height: float = 1.1) -> None:
    slab(p, x - 0.11, x + 0.11, 0.0, height, z - 0.11, z + 0.11, TIMBER, top=CREAM)


RAIL_HEIGHTS = (0.42, 0.82)


def fence_rail(p: Part, a, b) -> None:
    """The two rails between ground points a and b [(x, z)], set on the posts' centre line."""
    for y in RAIL_HEIGHTS:
        beam(p, (a[0], y, a[1]), (b[0], y, b[1]), 0.08, 0.16, CREAM)


def scaled(part: Part, k: float) -> Part:
    out = Part(part.name)
    out.verts = [(x * k, y * k, z * k) for x, y, z in part.verts]
    out.faces = list(part.faces)
    return out


# --- fields --------------------------------------------------------------------------------------


def make_field_wheat() -> Part:
    """Ripe wheat, 5.35 studs square and 1.0 tall: nine golden rows over darker stubble. Each row is
    one ridge, gold on its flanks and pale on its crown, so the rows read by their own shading at
    any sun angle and the stubble shows between them as the furrow lines. The rows differ: each
    takes its own height between 0.72 and 1.0, one of two crown golds, and ends that slope in, so
    the field is a stand of grain with wind in it and not a sheet of corrugated tin, which nine
    equal bars were. (A first cut of seven wider rows with orange flanks read as a stack of loaves.)"""
    p = Part("field-wheat")
    half = PATCH / 2
    slab(p, -half, half, 0.0, 0.1, -half, half, STUBBLE)
    rng = random.Random(211)
    crowns = (WHEAT_LIGHT, WHEAT_LIGHT, WHEAT_PALE)
    for z in row_centres(9):
        h = rng.uniform(0.72, 1.0)
        w = 0.19 + 0.05 * (1.0 - h) / 0.28  # a shorter row is a little broader: grain lying over
        x0 = -half + 0.06 + rng.uniform(0.0, 0.2)
        x1 = half - 0.06 - rng.uniform(0.0, 0.2)
        crest = 0.45 * w
        outline = [(z - w, 0.0), (z - w, 0.62 * h), (z - crest, h), (z + crest, h), (z + w, 0.62 * h), (z + w, 0.0)]
        ridge(p, outline, x0, x1, [WHEAT, WHEAT_GOLD, rng.choice(crowns), WHEAT_GOLD, WHEAT], WHEAT_DEEP, lean=0.22)
    return p


def make_field_rowcrop() -> Part:
    """A green row crop (cabbages), 5.35 studs square and 0.7 tall: four earthed-up rows of five
    heads on dark soil. The rows stand further apart than the heads do along them, and the heads
    are low, so the soil shows between the rows as stripes even from the tycoon camera; that tells
    the crop from the wheat at a distance as much as its colour does. (Five rows of five, and four
    rows of larger heads, both read as an even carpet, and the first took a field past 1,700
    triangles.)"""
    p = Part("field-rowcrop")
    half = PATCH / 2
    slab(p, -half, half, 0.0, 0.1, -half, half, SOIL_DARK)
    rng = random.Random(223)
    for z in row_centres(4):
        outline = [(z - 0.42, 0.0), (z - 0.18, 0.3), (z + 0.18, 0.3), (z + 0.42, 0.0)]
        ridge(p, outline, -half + 0.08, half - 0.08, [SOIL, SOIL_LIGHT, SOIL], SOIL)
        for x in row_centres(5):
            tuft(p, x + rng.uniform(-0.06, 0.06), z + rng.uniform(-0.04, 0.04), 0.24, 0.7 + rng.uniform(-0.08, 0.0),
                 0.45, 0.31, rng.uniform(0.0, math.pi / 2), LEAF_DARK, LEAF)
    return p


def make_field_plough() -> Part:
    """Ploughed earth, 5.35 studs square and 0.34 tall: eight furrow ridges on darker soil. The
    ridges are narrower than their pitch and lighter than the soil, one flank lighter still (the
    kits' painted-light look), so the furrows show as stripes from above. (Ridges that touched,
    in two near tones, read as one flat brown slab.)"""
    p = Part("field-plough")
    half = PATCH / 2
    slab(p, -half, half, 0.0, 0.08, -half, half, SOIL_DARK)
    rng = random.Random(227)
    for z in row_centres(8):
        x0 = -half + 0.06 + rng.uniform(0.0, 0.1)
        x1 = half - 0.06 - rng.uniform(0.0, 0.1)
        ridge(p, [(z - 0.23, 0.0), (z, 0.34), (z + 0.23, 0.0)], x0, x1, [SOIL_PALE, SOIL], SOIL_LIGHT)
    return p


def make_field_fence() -> Part:
    """The quarter's fence: post-and-rail, 1.1 studs tall, along the two outer edges of the 6 x 6
    quarter. Origin at the quarter's INNER corner (see the module docstring). Seven posts: three
    along each edge at 0.5, 1.5 and 2.5 spans and one at the corner, a span being a 3.5th of the
    line, so two quarters' end posts stand exactly one span apart across their join."""
    p = Part("field-fence")
    e = FENCE_LINE
    assert e + 0.11 <= QUARTER, "the fence must stay inside the quarter"
    span = e / 3.5
    along = [span * (k + 0.5) for k in range(3)]
    for a in along:
        fence_post(p, e, a)
        fence_post(p, a, e)
    fence_post(p, e, e)
    fence_rail(p, (e, 0.0), (e, e))
    fence_rail(p, (0.0, e), (e, e))
    return p


def make_fence_run() -> Part:
    """A straight 4-stud run of the same fence along X, for yards: three posts a third of the run
    apart, rails to both ends, so runs butt into one fence with even posts."""
    p = Part("fence-run")
    for x in (-4.0 / 3, 0.0, 4.0 / 3):
        fence_post(p, x, 0.0)
    fence_rail(p, (-2.0, 0.0), (2.0, 0.0))
    return p


# --- pasture ------------------------------------------------------------------------------------

# Where a pasture quarter's trough stands, in the patch's own frame (the patch is centred on its
# origin): the grass piece wears the ground there, and the PastureQuarter blueprint puts the
# trough at PATCH_CENTRE + this.
TROUGH_AT = (0.75, 1.9)


def make_pasture_grass() -> Part:
    """Grazed grass, 5.35 studs square and 0.4 tall: a ragged-edged sward in the kit's lightest
    green (the only green any City Kit colormap has is one mint-to-emerald ramp; this is its
    yellowest step), three darker tussocks the cattle left, and a patch worn to earth round the
    trough. A fallow cell then reads as pasture and not as bare plot."""
    p = Part("pasture-grass")
    rng = random.Random(277)
    plate(p, rounded_square(rng, PATCH / 2, 12, 12.0, 0.04), 0.0, 0.1, LEAF)
    plate(p, blotch(rng, TROUGH_AT[0], TROUGH_AT[1] - 0.25, 1.3, 0.62, points=6), 0.02, 0.15, YARD)
    for x, z in ((-1.75, 1.3), (1.55, -1.5), (-0.7, -1.95)):
        top = 0.4 + rng.uniform(-0.06, 0.0)
        tuft(p, x, z, 0.05, top, 0.3, 0.17, rng.uniform(0.0, math.pi / 2), LEAF_DARK, LEAF_MID)
    return p


def make_cow() -> Part:
    """A dairy cow, boxy: 0.8 studs wide, 2.3 long and 1.3 tall, facing -Z. White with charcoal
    markings (a saddle over the back, a shoulder patch on one flank, a cap between the ears) and a
    peach muzzle: black-and-white is what says "cow" at a stud and a half."""
    p = Part("cow")
    for sx in (-1, 1):
        for z in (-0.6, 0.6):
            x = sx * 0.24
            p.box(x - 0.09, x + 0.09, 0.0, 0.5, z - 0.09, z + 0.09, WHITE)
    p.box(-0.38, 0.38, 0.45, 1.15, -0.85, 0.85, WHITE)
    p.box(-0.24, 0.24, 0.72, 1.28, -1.32, -0.8, WHITE)
    p.box(-0.2, 0.2, 0.72, 0.98, -1.44, -1.3, PEACH)
    # markings stand 0.02 proud of the hide, open where they sit on it
    slab(p, -0.4, 0.4, 0.78, 1.17, 0.1, 0.62, CHARCOAL)
    slab(p, 0.1, 0.4, 0.6, 1.17, -0.62, -0.2, CHARCOAL)
    slab(p, -0.26, 0.26, 1.08, 1.3, -1.2, -0.84, CHARCOAL)
    return p


def make_trough() -> Part:
    """A galvanised water trough, 1.5 x 0.42 x 0.56 studs, brim-full."""
    p = Part("trough")
    slab(p, -0.75, 0.75, 0.0, 0.42, -0.28, 0.28, STEEL_MID, top=WATER)
    return p


# --- hay ----------------------------------------------------------------------------------------


def make_bale_round() -> Part:
    """A round bale lying along X, 1.36 studs long, 1.5 across and 1.43 tall, resting on a flat
    facet: straw yellow, paler on its ends, with the deeper heart of the roll in the middle of each
    end. The heart is a ring and a disc in the end's own plane, not a sheet laid on it. (A small
    orange hexagon there read as the hole in a nut.)"""
    p = Part("bale-round")
    r, half, seg = 0.75, 0.68, 10
    cy = r * math.cos(math.pi / seg)
    angles = [-math.pi / 2 + math.pi / seg + 2 * math.pi * k / seg for k in range(seg)]

    def ring(radius: float, x: float):
        return [(x, cy + radius * math.sin(a), radius * math.cos(a)) for a in angles]

    for sx in (-1, 1):
        x = sx * half
        outer, inner = ring(r, x), ring(0.42, x)
        out = (float(sx), 0.0, 0.0)
        face_out(p, inner, WHEAT_DEEP, out)
        for k in range(seg):
            n = (k + 1) % seg
            face_out(p, [outer[k], outer[n], inner[n], inner[k]], WHEAT_LIGHT, out)
    lo, hi = ring(r, -half), ring(r, half)
    for k in range(seg):
        n = (k + 1) % seg
        am = (angles[k] + angles[n]) / 2 + (math.pi if n == 0 else 0.0)
        face_out(p, [lo[k], lo[n], hi[n], hi[k]], WHEAT, (0.0, math.sin(am), math.cos(am)))
    return p


def make_haycock() -> Part:
    """A small cock of loose hay, 1.2 studs across and 1.2 tall: a steep six-sided mound, paler
    toward its top. (A stook tied at the waist under a flared head read as an egg timer.)"""
    p = Part("haycock")
    lathe(p, [(0.62, 0.0), (0.5, 0.5), (0.0, 1.2)], [WHEAT, WHEAT_LIGHT], seg=6, phase=0.4)
    return p


# --- singles and landmarks ----------------------------------------------------------------------


def make_telegraph_pole() -> Part:
    """Timber telegraph pole, 6.6 studs tall, 1.0 x 0.4 on the ground plan: two cross-arms along X
    with glass insulators, braced to the pole. The pole is 0.4 across at its foot, as thick as the
    1 x 1 footprint allows a pole to look: thinner, it was a hairline at the tycoon camera."""
    p = Part("telegraph-pole")
    lathe(p, [(0.2, 0.0), (0.16, 0.5), (0.11, 6.6)], [POLE_DARK, POLE], seg=6)
    for y, reach, pins in ((5.95, 0.5, (0.42, 0.18)), (5.3, 0.38, (0.3,))):
        beam(p, (-reach, y, 0.0), (reach, y, 0.0), 0.16, 0.16, POLE_DARK, ends=POLE)
        for x in pins:
            for sx in (-1, 1):
                slab(p, sx * x - 0.06, sx * x + 0.06, y + 0.08, y + 0.32, -0.06, 0.06, GLASS, top=WHITE)
    for sx in (-1, 1):
        beam(p, (sx * 0.05, 5.5, -0.13), (sx * 0.36, 5.9, -0.13), 0.06, 0.06, POLE, up=(0.0, 0.0, 1.0))
    return p


def cottonwood(name: str, size: float, fine: bool) -> Part:
    """A cottonwood at `size` times the full tree. `fine` spends more facets on the crown."""
    p = Part(name)
    lathe(p, [(0.44, 0.0), (0.32, 0.35), (0.22, 2.6)], [POLE_DARK, POLE], seg=5, phase=0.3)
    if fine:
        crown(p, 1.9, 2.8, 2.2, 2.05, 251, colour=LEAF_MID, cut=-0.45, seg=8, rings=3, jitter=0.06)
        crown(p, 3.3, 2.4, 1.45, 1.4, 257, at=(0.55, -0.35), colour=LEAF_MID, seg=6, rings=3, jitter=0.06)
        crown(p, 2.5, 2.1, 1.2, 1.16, 263, at=(-1.15, 0.75), colour=LEAF_MID, seg=6, rings=3, jitter=0.06)
        crown(p, 2.25, 1.9, 1.15, 1.1, 269, at=(-0.6, -1.15), colour=LEAF_MID, seg=6, rings=2, jitter=0.06)
    else:
        crown(p, 1.9, 2.8, 2.3, 2.15, 251, colour=LEAF_MID, cut=-0.45, seg=7, rings=2, jitter=0.06)
        crown(p, 3.3, 2.4, 1.55, 1.5, 257, at=(0.55, -0.35), colour=LEAF_MID, seg=5, rings=2, jitter=0.06)
        crown(p, 2.5, 2.1, 1.3, 1.25, 263, at=(-1.15, 0.75), colour=LEAF_MID, seg=5, rings=2, jitter=0.06)
    lit(p, LEAF_MID, LEAF)
    return scaled(p, size)


def make_tree_cottonwood() -> Part:
    """Prairie cottonwood, about 4.5 studs across and 5.7 tall: a short thick trunk under a wide,
    low, lumpy crown: one broad mass wider than it is tall, one tall dome set a little off its
    centre, and two lower lobes of different sizes on other sides, so the outline is a cloud's and
    no two sides share it. (One tall dome with both lumps sunk into it read as an egg; a dome
    centred on top read as a second tier; two domes of a height on opposite shoulders read as a
    heart, or a pair of ears, from the side that shows both.) Each dome has three rings of facets, which is what
    keeps its top from coming to a gem's point. The City Kits have no broadleaf tree (both suburban
    trees are teardrop conifers, which read as cypress, not prairie) and no green outside the one
    mint-to-emerald ramp, so the crown takes that ramp's two lightest steps: the lightest on the
    facets turned to the sky, the kits' painted-light look."""
    return cottonwood("tree-cottonwood", 1.0, True)


def make_tree_cottonwood_young() -> Part:
    """A young cottonwood for a town green, 0.58 of the full tree: about 2.6 studs across and 3.3
    tall, so it stays under a small lot's 3.4-stud height and inside its 6 studs, with a plainer
    crown (a filler lot is drawn many times, the prairie tree a few)."""
    return cottonwood("tree-cottonwood-young", 0.58, False)


def roof_slab(p: Part, lo, hi, half_length: float, colour: Rgb, drop: float = 0.0) -> None:
    """One plane of a roof whose ridge runs along Z: a 0.16-stud sheet from (x, y) `lo` up to `hi`,
    `half_length` each way along Z, its underside on that line. `drop` carries it past `lo` down the
    slope as the eave."""
    t = 0.16
    dx, dy = hi[0] - lo[0], hi[1] - lo[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    nx, ny = (-uy, ux) if ux > 0 else (uy, -ux)  # the perpendicular that points up
    a = (lo[0] - ux * drop + nx * t / 2, lo[1] - uy * drop + ny * t / 2, 0.0)
    b = (hi[0] + nx * t / 2, hi[1] + ny * t / 2, 0.0)
    beam(p, a, b, 2 * half_length, t, colour, up=(nx, ny, 0.0), ends=TIN_SHADE)


def make_barn() -> Part:
    """Red gambrel barn, 7.7 studs wide, 8.6 long and 8.6 tall, doors on -Z: red boarding with white
    corner boards, a white-framed double door with cross braces under a hayloft hatch, two windows
    a side, a pale tin roof and a cupola on the ridge."""
    p = Part("barn")
    hw, hl = 3.5, 4.0
    wall, knee_x, knee_y, ridge_y = 3.4, 2.25, 5.5, 6.9
    gable = [(-hw, 0.0), (hw, 0.0), (hw, wall), (knee_x, knee_y), (0.0, ridge_y), (-knee_x, knee_y), (-hw, wall)]
    extrude_z(p, gable, -hl, hl, RED)
    over = hl + 0.3
    for sx in (-1, 1):
        roof_slab(p, (sx * hw, wall), (sx * knee_x, knee_y), over, TIN, drop=0.4)
        # carried 0.3 past the knee: the lip of a gambrel roof, which also closes the gap the two
        # sheets would leave on the outside of the bend
        roof_slab(p, (sx * knee_x, knee_y), (0.0, ridge_y), over, TIN_LIGHT, drop=0.3)
    # the ridge cap closes the two upper sheets' meeting edge
    slab(p, -0.2, 0.2, ridge_y, ridge_y + 0.2, -over, over, TIN_SHADE)
    # corner boards, proud of both walls
    for sx in (-1, 1):
        for sz in (-1, 1):
            x0, x1 = sorted((sx * (hw + 0.06), sx * (hw - 0.26)))
            z0, z1 = sorted((sz * (hl + 0.06), sz * (hl - 0.26)))
            slab(p, x0, x1, 0.0, wall, z0, z1, WHITE)
    front = -hl
    # double door: a darker leaf pair in a white frame, each leaf cross-braced
    door_w, door_h = 1.5, 3.0
    p.box(-door_w, door_w, 0.0, door_h, front - 0.05, front + 0.02, RED_DARK)
    zf = front - 0.09
    for x in (-door_w, 0.0, door_w):
        p.box(x - 0.11, x + 0.11, 0.0, door_h, zf - 0.03, zf + 0.05, WHITE)
    p.box(-door_w - 0.11, door_w + 0.11, door_h - 0.02, door_h + 0.2, zf - 0.03, zf + 0.05, WHITE)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.11, sx * (door_w - 0.11)))
        for ya, yb in ((0.1, door_h - 0.1), (door_h - 0.1, 0.1)):
            beam(p, (x0, ya, zf + 0.01), (x1, yb, zf + 0.01), 0.16, 0.05, WHITE, up=(0.0, 0.0, 1.0))
    # hayloft hatch
    p.box(-0.7, 0.7, 3.9, 5.2, front - 0.08, front + 0.02, WHITE)
    p.box(-0.5, 0.5, 4.1, 5.0, front - 0.12, front - 0.06, RED_DARK)
    # windows down both sides
    for sx in (-1, 1):
        for z in (-1.9, 1.9):
            x0, x1 = sorted((sx * (hw - 0.02), sx * (hw + 0.07)))
            p.box(x0, x1, 1.4, 2.6, z - 0.6, z + 0.6, WHITE)
            x0, x1 = sorted((sx * (hw + 0.05), sx * (hw + 0.11)))
            p.box(x0, x1, 1.6, 2.4, z - 0.4, z + 0.4, SLATE)
    # cupola
    slab(p, -0.5, 0.5, ridge_y - 0.3, ridge_y + 0.85, -0.5, 0.5, RED, top=RED_DARK)
    lathe(p, [(0.82, ridge_y + 0.85), (0.0, ridge_y + 1.7)], [TIN], seg=4, phase=math.pi / 4)
    return p


def make_silo() -> Part:
    """Concrete stave silo, 2.8 studs across (3.1 with its chute) and 10.0 tall: pale staves, three
    steel hoops, a domed tin cap, and the unloading chute up the -Z side."""
    p = Part("silo")
    r, h = 1.42, 0.07
    profile = [
        (r + h, 0.0), (r + h, 0.3), (r, 0.3), (r, 3.9), (r + h, 3.9), (r + h, 4.15), (r, 4.15),
        (r, 7.7), (r + h, 7.7), (r + h, 8.0), (r * 0.9, 8.8), (r * 0.56, 9.55), (0.0, 10.0),
    ]
    colours = [STEEL, STEEL, TIN_LIGHT, STEEL, STEEL, STEEL, TIN_LIGHT, STEEL, STEEL, STEEL_MID, STEEL, STEEL_LIGHT]
    lathe(p, profile, colours, seg=10, phase=math.pi / 10)
    slab(p, -0.24, 0.24, 0.0, 8.2, -r - 0.2, -r + 0.2, STEEL_DARK, top=STEEL_MID)
    return p


def make_windpump() -> Part:
    """Prairie wind pump, 2.6 studs across, 2.6 deep and 9.4 tall: a tapering four-legged steel
    lattice tower, a twelve-sail wheel facing -Z, a red tail vane behind it, the pump rod down the
    middle to a well head. Each sail is a 0.06-stud plate, a solid with two faces and four edges:
    a single sheet would vanish from behind, where Roblox culls it."""
    p = Part("windpump")
    base, top, height = 1.05, 0.2, 7.6

    def corner(f: float, sx: int, sz: int):
        e = base + (top - base) * f
        return (sx * e, height * f, sz * e)

    signs = ((-1, -1), (1, -1), (1, 1), (-1, 1))
    for sx, sz in signs:
        # a raked leg's square-cut foot dips below its centre line: start it that much up the leg
        beam(p, corner(0.004, sx, sz), corner(1.0, sx, sz), 0.14, 0.14, STEEL_MID, up=(1.0, 0.0, 0.0))
    levels = (0.0, 0.32, 0.62, 0.9)
    for f in levels[1:]:
        for k in range(4):
            beam(p, corner(f, *signs[k]), corner(f, *signs[(k + 1) % 4]), 0.1, 0.1, STEEL)
    for bay in range(2):
        f0, f1 = max(levels[bay], 0.012), levels[bay + 1]  # a brace's foot must not dip below the ground
        for k in range(4):
            a, b = signs[k], signs[(k + 1) % 4]
            if (bay + k) % 2:
                a, b = b, a
            beam(p, corner(f0, *a), corner(f1, *b), 0.08, 0.08, STEEL)
    p.box(-0.4, 0.4, height - 0.06, height + 0.06, -0.4, 0.4, STEEL_DARK)
    beam(p, (0.0, 0.3, 0.0), (0.0, height, 0.0), 0.07, 0.07, STEEL_DARK)
    slab(p, -0.45, 0.45, 0.0, 0.45, -0.3, 0.3, STEEL, top=STEEL_LIGHT)
    # head: gearbox, hub and wheel
    hub_y, wheel_z = height + 0.5, -0.62
    p.box(-0.18, 0.18, height + 0.06, hub_y + 0.24, -0.34, 0.3, STEEL_DARK)
    beam(p, (0.0, hub_y, -0.34), (0.0, hub_y, wheel_z - 0.1), 0.2, 0.2, SLATE)
    sails, r0, r1 = 12, 0.3, 1.3
    for k in range(sails):
        a = 2 * math.pi * k / sails
        c, s = math.cos(a), math.sin(a)

        def at(r: float, w: float, z: float):
            return (r * c - w * s, hub_y + r * s + w * c, z)

        def sail(z: float):
            return [at(r0, -0.07, z), at(r1, -0.27, z), at(r1, 0.27, z), at(r0, 0.07, z)]

        p.hexa(sail(wheel_z - 0.03) + sail(wheel_z + 0.03), TIN_LIGHT if k % 2 else TIN_SHADE)
    # tail: boom and vane
    beam(p, (0.0, hub_y, 0.3), (0.0, hub_y, 1.05), 0.08, 0.08, STEEL_DARK)
    vane = [(0.75, hub_y - 0.22), (1.45, hub_y - 0.5), (1.45, hub_y + 0.5), (0.75, hub_y + 0.22)]
    extrude_x(p, vane, -0.03, 0.03, RED)
    return p


def make_yard_ground() -> Part:
    """The farmyard's trodden earth, 11.6 studs square with rounded corners, 0.06 tall, with paler
    worn patches that rise 0.05 above it, enough never to z-fight at a distance. It gives the
    farmstead its own ground in the landscape band, where it does not stand on the plot base."""
    p = Part("yard-ground")
    rng = random.Random(239)
    plate(p, rounded_square(rng, 5.8, 20, 6.0, 0.03), 0.0, 0.06, YARD)
    for cx, cz, rx, rz in ((2.6, -2.6, 2.0, 1.5), (-1.6, -4.6, 1.8, 0.8), (3.6, 0.9, 1.1, 1.4)):
        plate(p, blotch(rng, cx, cz, rx, rz, points=8), 0.02, 0.11, YARD_LIGHT)
    return p


# --- town greens (the civic lots) ---------------------------------------------------------------


def striped_lawn(p: Part, hx: float, hz: float, stripes: int, y: float) -> None:
    """A mown lawn 2 hx by 2 hz: `stripes` bands along Z in two greens, the roller's stripes, as
    one open-bottomed slab (the bands share their edges, so nothing overlaps)."""
    width = 2 * hx / stripes
    for i in range(stripes):
        x0, x1 = -hx + width * i, -hx + width * (i + 1)
        green = LEAF if i % 2 else LEAF_MID
        face_out(p, [(x0, y, -hz), (x1, y, -hz), (x1, y, hz), (x0, y, hz)], green, (0.0, 1.0, 0.0))
        for z, out in ((-hz, -1.0), (hz, 1.0)):
            face_out(p, [(x0, 0.0, z), (x1, 0.0, z), (x1, y, z), (x0, y, z)], LEAF_DARK, (0.0, 0.0, out))
    for x, out in ((-hx, -1.0), (hx, 1.0)):
        face_out(p, [(x, 0.0, -hz), (x, 0.0, hz), (x, y, hz), (x, y, -hz)], LEAF_DARK, (out, 0.0, 0.0))


def kerb(p: Part, x0: float, x1: float, z0: float, z1: float) -> None:
    slab(p, x0, x1, 0.0, 0.17, z0, z1, TIN_SHADE, top=TIN_LIGHT)


PATH_TOP = 0.14  # paving stands this far above the ground: 0.04 above the grass


def make_green_small() -> Part:
    """The floor of a 6 x 6 civic lot, 5.9 studs square: a mown lawn inside a low pale kerb, a
    paved path in from the street (-Z) to a small paved stand at the middle, where a bench goes."""
    p = Part("green-small")
    lawn, edge = 2.8, 2.94
    striped_lawn(p, lawn, lawn, 4, 0.1)
    kerb(p, -edge, edge, lawn, edge)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * lawn, sx * edge))
        kerb(p, x0, x1, -edge, lawn)
        x0, x1 = sorted((sx * 0.45, sx * lawn))
        kerb(p, x0, x1, -edge, -lawn)
    slab(p, -0.45, 0.45, 0.0, PATH_TOP, -edge, 0.45, TIN_SHADE, top=TIN)
    slab(p, -1.0, 1.0, 0.0, PATH_TOP, 0.45, 1.65, TIN_SHADE, top=TIN)
    return p


# green-medium's plan, shared with its paths: the paved octagon's centre and the two gaps in the kerb
MEDIUM_HEART = (0.0, 0.2)
MEDIUM_GATE = 0.55  # half the width of a gap in the kerb, and of the path that later fills it


def make_green_medium() -> Part:
    """The floor of an 8 x 8 civic lot, 7.9 studs square: a mown green inside a low pale kerb, the
    kerb left open at the middle of the street side (-Z) and of the +X side, where the paths come
    in at the next stage."""
    p = Part("green-medium")
    lawn, edge, gate = 3.8, 3.94, MEDIUM_GATE
    striped_lawn(p, lawn, lawn, 6, 0.1)
    kerb(p, -edge, edge, lawn, edge)
    kerb(p, -edge, -lawn, -lawn, lawn)
    for sx in (-1, 1):
        x0, x1 = sorted((sx * gate, sx * edge))
        kerb(p, x0, x1, -edge, -lawn)
    kerb(p, lawn, edge, -lawn, MEDIUM_HEART[1] - gate)
    kerb(p, lawn, edge, MEDIUM_HEART[1] + gate, lawn)
    return p


def make_green_medium_paths() -> Part:
    """The paving an 8 x 8 green gains: a path in from the street and one in from the +X side, to
    an octagon 4 studs across at the heart of the green, where the bandstand goes."""
    p = Part("green-medium-paths")
    cx, cz = MEDIUM_HEART
    gate, edge, corner = MEDIUM_GATE, 3.94, 2.05
    flat = corner * math.cos(math.pi / 8)  # the octagon's flat sides face the two paths
    slab(p, -gate, gate, 0.0, PATH_TOP, -edge, cz - flat, TIN_SHADE, top=TIN)
    slab(p, cx + flat, edge, 0.0, PATH_TOP, cz - gate, cz + gate, TIN_SHADE, top=TIN)
    ring = [(cx + corner * math.cos(a), cz + corner * math.sin(a)) for a in
            (math.pi / 8 + math.pi / 4 * k for k in range(8))]
    plate(p, ring, 0.0, PATH_TOP, TIN_SHADE, top=TIN)
    return p


def make_bench() -> Part:
    """A park bench, 1.5 studs long, 0.5 deep and 0.9 tall, facing -Z: timber slats on dark ends."""
    p = Part("bench")
    for sx in (-1, 1):
        x0, x1 = sorted((sx * 0.6, sx * 0.7))
        p.box(x0, x1, 0.0, 0.4, -0.22, 0.24, STEEL_DARK)
    p.box(-0.75, 0.75, 0.38, 0.47, -0.25, 0.25, POLE)
    p.box(-0.75, 0.75, 0.45, 0.9, 0.18, 0.26, POLE)
    return p


def make_flower_bed() -> Part:
    """A flower bed, 2.2 x 1.2 studs and 0.5 tall: an oval of dark soil with six clumps of flowers
    in the kit's sign colours."""
    p = Part("flower-bed")
    rng = random.Random(283)
    plate(p, blotch(rng, 0.0, 0.0, 1.1, 0.6, points=8), 0.0, 0.2, SOIL, top=SOIL_DARK)
    blooms = (RED, WHEAT, PINK, WHITE, PURPLE, WHEAT_LIGHT)
    for i, bloom in enumerate(blooms):
        x = -0.68 + 0.68 * (i % 3) + rng.uniform(-0.05, 0.05)
        z = (-0.24 if i < 3 else 0.24) + rng.uniform(-0.03, 0.03)
        tuft(p, x, z, 0.15, 0.5 - rng.uniform(0.0, 0.06), 0.24, 0.17, rng.uniform(0.0, math.pi / 2), LEAF_DARK, bloom)
    return p


def make_shrub() -> Part:
    """A clipped shrub, 1.1 studs across and 0.8 tall: one dark faceted dome, lighter on top."""
    p = Part("shrub")
    p.blob((0.0, 0.21, 0.0), (0.56, 0.6, 0.52), LEAF_DARK, seg=6, rings=2, jitter=0.08, seed=293)
    lit(p, LEAF_DARK, LEAF_MID)
    return p


def make_bandstand() -> Part:
    """A town bandstand, 3.7 studs across and 4.3 tall, its step on -Z: an octagonal plinth with a
    timber floor, eight white posts with a low white rail between them (open at the step), and an
    eight-sided terracotta roof with a white fascia and a finial. It stays under the 4.5 studs a
    medium civic lot may reach, and is no landmark's shape."""
    p = Part("bandstand")
    turn = math.pi / 8  # a flat side, not a corner, faces the street
    lathe(p, [(1.62, 0.0), (1.62, 0.34), (1.52, 0.4)], [TIN_SHADE, TIMBER], seg=8, phase=turn)
    slab(p, -0.5, 0.5, 0.0, 0.2, -2.0, -1.4, TIN_SHADE, top=TIN)
    posts = [(1.38 * math.cos(turn + math.pi / 4 * k), 1.38 * math.sin(turn + math.pi / 4 * k)) for k in range(8)]
    for x, z in posts:
        slab(p, x - 0.07, x + 0.07, 0.4, 2.56, z - 0.07, z + 0.07, WHITE)
    for k in range(8):
        (xa, za), (xb, zb) = posts[k], posts[(k + 1) % 8]
        if (za + zb) / 2 < -1.2:
            continue  # the side the step leads up to
        beam(p, (xa, 0.72, za), (xb, 0.72, zb), 0.07, 0.5, WHITE)
    lathe(p, [(1.85, 2.55), (1.85, 2.7), (0.3, 3.8), (0.0, 3.95)], [WHITE, TERRACOTTA, TERRACOTTA], seg=8, phase=turn)
    lathe(p, [(0.0, 3.86), (0.13, 4.08), (0.0, 4.3)], [WHITE, WHITE], seg=4)
    return p


PIECES = {
    "field-wheat": make_field_wheat,
    "field-rowcrop": make_field_rowcrop,
    "field-plough": make_field_plough,
    "field-fence": make_field_fence,
    "fence-run": make_fence_run,
    "pasture-grass": make_pasture_grass,
    "cow": make_cow,
    "trough": make_trough,
    "bale-round": make_bale_round,
    "haycock": make_haycock,
    "telegraph-pole": make_telegraph_pole,
    "tree-cottonwood": make_tree_cottonwood,
    "tree-cottonwood-young": make_tree_cottonwood_young,
    "barn": make_barn,
    "silo": make_silo,
    "windpump": make_windpump,
    "yard-ground": make_yard_ground,
    "green-small": make_green_small,
    "green-medium": make_green_medium,
    "green-medium-paths": make_green_medium_paths,
    "bench": make_bench,
    "flower-bed": make_flower_bed,
    "shrub": make_shrub,
    "bandstand": make_bandstand,
}


# --- export -------------------------------------------------------------------------------------


def generate(out_dir: str) -> int:
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, make in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        export(build_object(scaled(part, 1.0 / STUDS_PER_UNIT), {}), out_dir)
        total += part.tris
        lo, hi = part.bounds()
        size = tuple(hi[i] - lo[i] for i in range(3))
        print(
            f"[{KIT}] {name}.glb: {part.tris} tris, {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} studs at scale 4, "
            f"x[{lo[0]:.2f}, {hi[0]:.2f}] y[{lo[1]:.2f}, {hi[1]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}]",
            flush=True,
        )
    print(f"[{KIT}] {len(PIECES)} pieces, {total} tris total -> {os.path.relpath(out_dir, REPO_ROOT)}", flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the farmland-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)
    return generate(args.out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
