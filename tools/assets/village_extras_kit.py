"""Construction and farm pieces for the Village growing city (M12), generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/village_extras_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/village-extras-kit/Models/GLB format/, the folder
convention every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. Mesh helpers and the export plumbing come from
garden_kit.py, like people_kit.py.

Why a custom kit (INTERFACES "M12 contracts", Village props; docs/CITY_GROWTH.md section 4): the
growing city's building sites need crates, a ladder, a hoist and stone and plank piles, and its farm
parcels need haystacks and bales. fantasy-town-kit and nature-kit carry none of them (the testfit
README: "no crate models"), and the retro kits that do were rejected for the project. The rest fill
gaps the site, farm and marker props ran into:
- truss, timber, post: a roof skeleton, plain squared beams, and an upright shorter than pillar-wood;
- sawhorse, site-ground: a trestle, and the bare earth a site stands on;
- notice-board: the next-pad marker (no kit has a board);
- boulder-large, boulder-small: mossy stone for MeadowRock, because fantasy-town's rocks are 4 to 6
  studs at scale 4 and nature-kit's grass vanishes below scale 3, so the two never share a scale;
- scaffold-ring: the landmark-reveal scaffold, one piece so it fits a 9 x 9 slot exactly.

**Units -- read before placing a piece.** These GLBs are in Kenney kit units, **1 unit = 4 studs at
blueprint scale 4.0**, unlike garden-kit, people-kit and metro-kit (1 unit = 1 stud, scale-1.0
blueprints). Every Village prop that uses them also places fantasy-town-kit and nature-kit pieces,
and a blueprint has one scale for all of its pieces, so the kits' own unit is the only one that
mixes. The literals below are written in studs as they come out at scale 4.0 and are divided by
STUDS_PER_UNIT once, at export; a blueprint at another scale resizes these pieces together with the
Kenney pieces around them.

Colours are texels of fantasy-town-kit's colormap.png (its timber gradient, stone ramp and swatches)
and nature-kit material colours as the palette bake shows them (its flower and corn yellows), so the
pieces sit in the Village palette. The one exception is the site earth, which is the approved Village
path dirt (tools/paths/texture.py planar_fill): a building site then reads as the same ground as the
lane in front of it. Materials are plain colour factors with no texture, written linear like
garden-kit's; merge_stages.py routes them through palette.py (not an sRGB-factor kit).

Art rules, matching the kits: flat shading, axis-aligned boxes and square-cut timbers, faceted
solids of revolution, chunky toy proportions. Front is -Z and the origin is the bottom centre of
each piece, except the ladder, whose origin is at its feet (it leans back toward +Z).
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

import bpy  # noqa: E402

KIT = "village-extras-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")
STUDS_PER_UNIT = 4.0

# fantasy-town-kit colormap.png texels. Its planks, poles, fences and carts sample the timber
# gradient (light to dark), rock-* and wall-broken the stone ramp, hedge and hedge-large the green
# used here for moss; the rest are the colormap's flat swatches.
WOOD_LIGHT = (211, 140, 106)
WOOD = (204, 134, 101)
WOOD_MID = (194, 127, 95)
WOOD_SHADE = (184, 119, 88)
WOOD_DARK = (156, 94, 72)
WOOD_DEEP = (133, 80, 62)
STONE_LIGHT = (173, 181, 217)
STONE = (160, 168, 201)
STONE_MID = (141, 147, 177)
STONE_DARK = (126, 132, 159)
MOSS = (78, 181, 131)
CREAM = (253, 228, 199)
WHITE = (255, 255, 255)
SLATE = (79, 82, 96)
RED = (207, 83, 79)
SAND = (238, 186, 136)
YELLOW = (255, 192, 68)
# nature-kit, as palette.py decodes its factors: the flower yellow and the ripe-corn cob.
STRAW_LIGHT = (255, 217, 144)
CORN = (251, 223, 168)
# tools/paths/texture.py planar_fill: the Village dirt's two tones.
EARTH = (176, 137, 91)
EARTH_LIGHT = (194, 155, 106)

Rgb = tuple[int, int, int]
Vec = tuple[float, float, float]


# --- geometry helpers (glTF space, studs at scale 4) --------------------------------------------


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a: Vec, k: float) -> Vec:
    return (a[0] * k, a[1] * k, a[2] * k)


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a: Vec) -> Vec:
    n = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2)
    return (a[0] / n, a[1] / n, a[2] / n)


def face_out(p: Part, points, colour: Rgb, outward: Vec) -> None:
    """A polygon wound so its normal agrees with `outward`: for faces that are not convex about one
    known centre (lathe bands, prism walls, caps)."""
    n = len(points)
    mid = tuple(sum(pt[i] for pt in points) / n for i in range(3))
    p.face(points, colour, sub(mid, outward))


def beam(p: Part, a: Vec, b: Vec, w: float, t: float, colour: Rgb, up: Vec = (0.0, 1.0, 0.0),
         ends: Rgb | None = None) -> None:
    """A square-cut timber from a to b, w across and t thick. The thickness is taken along `up`
    (squared off the axis), so a board lies flat with the default and a brace lies in a wall when
    `up` is that wall's normal. `ends` colours the end grain."""
    d = unit(sub(b, a))
    s = cross(d, up)
    if s[0] ** 2 + s[1] ** 2 + s[2] ** 2 < 1e-12:
        s = cross(d, (0.0, 0.0, 1.0))
    s = unit(s)
    u = cross(s, d)

    def ring(c: Vec):
        return [add(add(c, mul(s, sx * w / 2)), mul(u, su * t / 2)) for sx, su in ((-1, -1), (1, -1), (1, 1), (-1, 1))]

    cap = ends or colour
    p.hexa(ring(a) + ring(b), colour, top=cap, bottom=cap)


def lathe(p: Part, profile, colours, seg: int = 8, at: Vec = (0.0, 0.0, 0.0), phase: float = 0.0) -> None:
    """Faceted solid of revolution about the vertical axis through `at`. `profile` lists
    (radius, height) bottom to top; band i (profile[i] to profile[i + 1]) takes colours[i]. Each
    facet is wound along the profile's own normal, so a waisted profile winds correctly too."""
    cx, cy, cz = at
    angles = [phase + 2 * math.pi * k / seg for k in range(seg)]
    rings = [[(cx + r * math.cos(a), cy + y, cz + r * math.sin(a)) for a in angles] for r, y in profile]
    for i in range(len(profile) - 1):
        (r0, y0), (r1, y1) = profile[i], profile[i + 1]
        nr, ny = y1 - y0, -(r1 - r0)
        lo, hi = rings[i], rings[i + 1]
        for k in range(seg):
            n = (k + 1) % seg
            am = phase + 2 * math.pi * (k + 0.5) / seg
            outward = (nr * math.cos(am), ny, nr * math.sin(am))
            if r1 == 0:
                pts = [lo[k], lo[n], hi[k]]
            elif r0 == 0:
                pts = [lo[k], hi[n], hi[k]]
            else:
                pts = [lo[k], lo[n], hi[n], hi[k]]
            face_out(p, pts, colours[i], outward)
    if profile[0][0] > 0:
        face_out(p, rings[0], colours[0], (0.0, -1.0, 0.0))
    if profile[-1][0] > 0:
        face_out(p, rings[-1], colours[-1], (0.0, 1.0, 0.0))


def prism(p: Part, outline, y0: float, y1: float, colour: Rgb, top: Rgb | None = None) -> None:
    """Vertical prism over a star-shaped outline [(x, z)]."""
    cx = sum(x for x, _ in outline) / len(outline)
    cz = sum(z for _, z in outline) / len(outline)
    lo = [(x, y0, z) for x, z in outline]
    hi = [(x, y1, z) for x, z in outline]
    face_out(p, hi, top or colour, (0.0, 1.0, 0.0))
    face_out(p, lo, colour, (0.0, -1.0, 0.0))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        mx = (outline[i][0] + outline[j][0]) / 2
        mz = (outline[i][1] + outline[j][1]) / 2
        face_out(p, [lo[i], lo[j], hi[j], hi[i]], colour, (mx - cx, 0.0, mz - cz))


def extrude_x(p: Part, outline, x0: float, x1: float, colour: Rgb, ends: Rgb | None = None) -> None:
    """Prism along X over a star-shaped outline [(z, y)]: bales and anything with a shaped end."""
    cz = sum(z for z, _ in outline) / len(outline)
    cy = sum(y for _, y in outline) / len(outline)
    a = [(x0, y, z) for z, y in outline]
    b = [(x1, y, z) for z, y in outline]
    face_out(p, a, ends or colour, (-1.0, 0.0, 0.0))
    face_out(p, b, ends or colour, (1.0, 0.0, 0.0))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        mz = (outline[i][0] + outline[j][0]) / 2
        my = (outline[i][1] + outline[j][1]) / 2
        face_out(p, [a[i], a[j], b[j], b[i]], colour, (0.0, my - cy, mz - cz))


def place(dst: Part, src: Part, rot_y: float = 0.0, at: Vec = (0.0, 0.0, 0.0)) -> None:
    """Merge src into dst, turned rot_y degrees about Y exactly as a blueprint's rotY (Roblox's
    CFrame.Angles(0, a, 0)), then moved to `at`. A proper rotation, so winding carries over."""
    a = math.radians(rot_y)
    c, s = math.cos(a), math.sin(a)
    base = len(dst.verts)
    for x, y, z in src.verts:
        dst.verts.append((x * c + z * s + at[0], y + at[1], -x * s + z * c + at[2]))
    for idx, colour in src.faces:
        dst.faces.append(([base + i for i in idx], colour))


def turned_z(src: Part, rot_z: float, at: Vec) -> Part:
    """src turned rot_z degrees in the XY plane (a sheet pinned askew on a board), then moved."""
    a = math.radians(rot_z)
    c, s = math.cos(a), math.sin(a)
    out = Part(src.name)
    out.verts = [(x * c - y * s + at[0], x * s + y * c + at[1], z + at[2]) for x, y, z in src.verts]
    out.faces = list(src.faces)
    return out


def blotch(rng: random.Random, cx: float, cz: float, rx: float, rz: float, points: int = 9):
    """A jittered ellipse outline, for earth patches."""
    out = []
    for k in range(points):
        a = 2 * math.pi * k / points
        j = 1.0 + rng.uniform(-0.12, 0.12)
        out.append((cx + rx * j * math.cos(a), cz + rz * j * math.sin(a)))
    return out


# --- the pieces (studs at scale 4) --------------------------------------------------------------


def crate_body(size: float) -> Part:
    """Kenney's crate language: dark corner posts and rims standing proud of lighter plank panels,
    a diagonal brace on every side. The brace's outer face sits 0.005 behind the frame's, so where
    it runs under a rim the frame hides it instead of z-fighting with it."""
    p = Part("crate-body")
    h = size / 2
    f = 0.15 * size / 1.3
    inset = 0.035
    p.box(-h + inset, h - inset, 0.0, size - inset, -h + inset, h - inset, WOOD, top=WOOD_LIGHT)
    for sx in (-1, 1):
        for sz in (-1, 1):
            x0, x1 = sorted((sx * h, sx * (h - f)))
            z0, z1 = sorted((sz * h, sz * (h - f)))
            p.box(x0, x1, 0.0, size, z0, z1, WOOD_DARK)
    for y0, y1 in ((0.0, f), (size - f, size)):
        p.box(-h + f, h - f, y0, y1, -h, -h + f, WOOD_DARK)
        p.box(-h + f, h - f, y0, y1, h - f, h, WOOD_DARK)
        p.box(-h, -h + f, y0, y1, -h + f, h - f, WOOD_DARK)
        p.box(h - f, h, y0, y1, -h + f, h - f, WOOD_DARK)
    brace = Part("brace")
    z = -h + 0.03
    beam(brace, (-h + f * 0.7, f * 0.7, z), (h - f * 0.7, size - f * 0.7, z), f * 0.8, 0.05, WOOD_SHADE,
         up=(0.0, 0.0, 1.0))
    for rot in (0, 90, 180, 270):
        place(p, brace, rot)
    return p


def make_crate() -> Part:
    """One crate, 1.3 studs on a side."""
    p = Part("crate")
    place(p, crate_body(1.3))
    return p


def make_crate_pair() -> Part:
    """A 1.0-stud crate set askew on a 1.3-stud one: 2.3 studs tall."""
    p = Part("crate-pair")
    place(p, crate_body(1.3))
    place(p, crate_body(1.0), 17.0, (0.06, 1.3, -0.04))
    return p


def make_ladder() -> Part:
    """A 4.8-stud ladder leaning back 14 degrees: feet at the origin, top 4.66 studs up and 1.16
    toward +Z, so it rests against whatever stands just behind its feet."""
    p = Part("ladder")
    length, tilt = 4.8, math.radians(14.0)
    top_y, top_z = length * math.cos(tilt), length * math.sin(tilt)
    half = 0.38
    for sx in (-1, 1):
        x = sx * half
        beam(p, (x, 0.0, 0.0), (x, top_y, top_z), 0.13, 0.13, WOOD_LIGHT)
    for i in range(7):
        f = (i + 0.75) / 7.4
        y, z = top_y * f, top_z * f
        beam(p, (-half, y, z), (half, y, z), 0.09, 0.09, SAND)
    return p


def make_hoist() -> Part:
    """Timber shear-leg hoist, 3.0 x 5.4 x 2.1 studs: two A-frames under a top beam, a pulley block,
    a rope lowering a dressed stone, and the hauling line down to a windlass on the +X frame."""
    p = Part("hoist")
    apex_y, spread, fx = 5.3, 0.95, 1.15
    for sx in (-1, 1):
        x = sx * fx
        apex = (x, apex_y, 0.0)
        for sz in (-1, 1):
            beam(p, (x, 0.0, sz * spread), apex, 0.18, 0.18, WOOD_SHADE, up=(1.0, 0.0, 0.0))
        yk = 1.7
        zk = spread * (1 - yk / apex_y)
        beam(p, (x, yk, -zk - 0.06), (x, yk, zk + 0.06), 0.14, 0.14, WOOD_MID)
    beam(p, (-fx - 0.35, apex_y - 0.02, 0.0), (fx + 0.35, apex_y - 0.02, 0.0), 0.22, 0.22, WOOD_DARK,
         ends=WOOD_LIGHT)
    px = 0.3
    p.box(px - 0.13, px + 0.13, apex_y - 0.64, apex_y - 0.12, -0.11, 0.11, SLATE)
    load_top = 2.75
    beam(p, (px, apex_y - 0.62, 0.0), (px, load_top, 0.0), 0.07, 0.07, SAND)
    p.box(px - 0.42, px + 0.42, load_top - 0.56, load_top, -0.3, 0.3, STONE, top=STONE_LIGHT)
    drum_y = 1.1
    zd = spread * (1 - drum_y / apex_y) + 0.06
    beam(p, (fx, drum_y, -zd), (fx, drum_y, zd), 0.3, 0.3, WOOD_DARK, ends=WOOD_LIGHT)
    beam(p, (px + 0.1, apex_y - 0.42, 0.0), (fx - 0.12, drum_y + 0.12, 0.0), 0.07, 0.07, SAND)
    return p


def ashlar(p: Part, cx: float, y0: float, cz: float, size: Vec, rot: float, side: Rgb) -> None:
    sx, sy, sz = size
    block = Part("ashlar")
    block.box(-sx / 2, sx / 2, 0.0, sy, -sz / 2, sz / 2, side, top=STONE_LIGHT)
    place(p, block, rot, (cx, y0, cz))


def make_stone_pile() -> Part:
    """Dressed building stone, 2.3 x 1.4 x 1.3 studs: five blocks, two, then one, a little askew."""
    p = Part("stone-pile")
    ashlar(p, -0.74, 0.0, 0.3, (0.7, 0.48, 0.58), 4, STONE)
    ashlar(p, 0.02, 0.0, 0.32, (0.72, 0.48, 0.6), -3, STONE_MID)
    ashlar(p, 0.76, 0.0, 0.28, (0.68, 0.48, 0.58), 6, STONE)
    ashlar(p, -0.36, 0.0, -0.34, (0.7, 0.48, 0.56), -5, STONE_MID)
    ashlar(p, 0.42, 0.0, -0.36, (0.66, 0.48, 0.56), 3, STONE_DARK)
    ashlar(p, -0.36, 0.48, 0.12, (0.7, 0.46, 0.58), 8, STONE_MID)
    ashlar(p, 0.4, 0.48, 0.1, (0.7, 0.46, 0.58), -4, STONE)
    ashlar(p, 0.04, 0.94, 0.12, (0.66, 0.44, 0.56), 12, STONE_DARK)
    return p


def make_plank_stack() -> Part:
    """Sawn boards drying on two bearers, 3.4 x 0.8 x 1.4 studs, ends showing lighter grain."""
    p = Part("plank-stack")
    length, bearer = 3.2, 0.2
    for x in (-1.05, 1.05):
        p.box(x - 0.14, x + 0.14, 0.0, bearer, -0.68, 0.68, WOOD_DEEP)
    tones = (WOOD_LIGHT, WOOD, WOOD_MID, WOOD_SHADE)
    rng = random.Random(61)
    y = bearer
    for layer in range(6):
        count = 3 if layer < 5 else 2
        for i in range(count):
            z0 = -0.64 + i * 0.43 + (0.22 if count == 2 else 0.0)
            dx = rng.uniform(-0.12, 0.12)
            p.box(-length / 2 + dx, length / 2 + dx, y, y + 0.1, z0, z0 + 0.41, tones[(layer + i) % 4],
                  left=SAND, right=SAND)
        y += 0.1
    return p


def make_haystack() -> Part:
    """Round hay rick, 2.4 studs across and 2.5 tall: a straight-sided drum under a steep thatched cone,
    pale straw over a golden foot. Earlier cuts read as an orange (round, deep yellow) and as an egg
    in a belt (a darker band round the middle)."""
    p = Part("haystack")
    profile = [(1.1, 0.0), (1.2, 0.25), (1.2, 0.95), (1.08, 1.35), (0.8, 1.8), (0.45, 2.15), (0.15, 2.42), (0.0, 2.5)]
    lathe(p, profile, [YELLOW, STRAW_LIGHT, STRAW_LIGHT, STRAW_LIGHT, CORN, CORN, CORN], seg=10, phase=0.3)
    return p


def make_hay_bale() -> Part:
    """Square bale, 1.6 x 0.9 x 1.0 studs, chamfered, two twine bands."""
    p = Part("hay-bale")
    length, width, height, c = 1.6, 1.0, 0.9, 0.12
    hw = width / 2

    def outline(grow: float):
        w, h, k = hw + grow, height + grow, c
        return [(-w, k), (-w + k, -grow), (w - k, -grow), (w, k), (w, h - k), (w - k, h), (-w + k, h), (-w, h - k)]

    extrude_x(p, outline(0.0), -length / 2, length / 2, YELLOW, ends=STRAW_LIGHT)
    for x in (-0.42, 0.42):
        extrude_x(p, [(z, max(y, 0.0)) for z, y in outline(0.025)], x - 0.035, x + 0.035, WOOD_DARK)
    return p


def make_notice_board() -> Part:
    """Village notice board, 2.0 x 3.6 x 0.8 studs: a dark board in a lighter frame between two posts,
    sheets pinned askew, a red plank cap. It faces -Z."""
    p = Part("notice-board")
    post_x, post_h, post_w = 0.78, 3.32, 0.2
    for sx in (-1, 1):
        x = sx * post_x
        p.box(x - post_w / 2, x + post_w / 2, 0.0, post_h, -post_w / 2, post_w / 2, WOOD_SHADE)
    bx, by0, by1, f = 0.9, 1.45, 2.8, 0.1
    p.box(-bx, bx, by0, by1, -0.07, 0.07, WOOD_DARK)
    zf0, zf1 = -0.11, -0.05
    p.box(-bx - 0.02, bx + 0.02, by1 - f, by1 + 0.02, zf0, zf1, WOOD_MID)
    p.box(-bx - 0.02, bx + 0.02, by0 - 0.02, by0 + f, zf0, zf1, WOOD_MID)
    p.box(-bx - 0.02, -bx + f, by0 + f, by1 - f, zf0, zf1, WOOD_MID)
    p.box(bx - f, bx + 0.02, by0 + f, by1 - f, zf0, zf1, WOOD_MID)
    # Laid out so no two sheets overlap: coplanar sheets would z-fight.
    sheets = (
        (-0.48, 2.3, 0.4, 0.44, -6, CREAM),
        (0.06, 2.34, 0.36, 0.38, 4, WHITE),
        (0.53, 2.22, 0.34, 0.46, -3, CREAM),
        (-0.42, 1.78, 0.42, 0.36, 5, YELLOW),
        (0.08, 1.8, 0.38, 0.4, -5, CREAM),
    )
    for x, y, w, h, rot, colour in sheets:
        sheet = Part("sheet")
        sheet.box(-w / 2, w / 2, -h / 2, h / 2, -0.015, 0.015, colour)
        place(p, turned_z(sheet, rot, (x, y, -0.085)))
    ridge_y, eave_y, eave_z, cap_x = 3.45, 3.1, 0.36, 0.98
    for sz in (-1, 1):
        normal = (0.0, eave_z, sz * (ridge_y - eave_y))
        mid = (0.0, (ridge_y + eave_y) / 2, sz * eave_z / 2)
        slope = math.hypot(eave_z, ridge_y - eave_y) + 0.06
        beam(p, (-cap_x, mid[1], mid[2]), (cap_x, mid[1], mid[2]), slope, 0.08, RED, up=normal, ends=WOOD_DARK)
    p.box(-cap_x - 0.02, cap_x + 0.02, ridge_y - 0.04, ridge_y + 0.1, -0.07, 0.07, WOOD_DARK)
    return p


def make_truss() -> Part:
    """King-post roof truss, the skeleton of a roof going up: 4.3 studs across, 1.85 tall, 0.18 deep.
    It spans X with its tie beam's underside at the origin; rotY 90 spans Z."""
    p = Part("truss")
    half, rise = 2.0, 1.75
    beam(p, (-half, 0.1, 0.0), (half, 0.1, 0.0), 0.18, 0.2, WOOD_LIGHT, ends=CREAM)
    for sx in (-1, 1):
        beam(p, (sx * (half + 0.08), 0.1, 0.0), (0.0, rise, 0.0), 0.18, 0.2, SAND, ends=CREAM)
        beam(p, (0.0, 0.5, 0.0), (sx * 1.0, 0.93, 0.0), 0.12, 0.12, WOOD_LIGHT)
    beam(p, (0.0, 0.18, 0.0), (0.0, rise - 0.05, 0.0), 0.16, 0.16, WOOD_LIGHT)
    return p


def make_timber() -> Part:
    """A plain squared timber, 4.0 studs along X (one kit unit), 0.26 square: plates, ledgers, ridges."""
    p = Part("timber")
    beam(p, (-2.0, 0.13, 0.0), (2.0, 0.13, 0.0), 0.26, 0.26, SAND, ends=CREAM)
    return p


def make_post() -> Part:
    """A plain upright, 3.2 studs tall and 0.28 square: shorter than fantasy-town's pillar-wood (4.0),
    so an open farm shed under a red gable-top stays below 6 studs, the height at which a farm parcel
    can still show its last stage beside a fully grown FarmPlot."""
    p = Part("post")
    p.box(-0.14, 0.14, 0.0, 3.2, -0.14, 0.14, WOOD_SHADE, top=WOOD_LIGHT)
    return p


def make_sawhorse() -> Part:
    """Trestle with a board across it, 1.8 x 0.9 x 0.7 studs."""
    p = Part("sawhorse")
    length, height = 1.4, 0.72
    p.box(-length / 2, length / 2, height - 0.14, height, -0.08, 0.08, WOOD_MID)
    for x in (-0.5, 0.5):
        for sz in (-1, 1):
            beam(p, (x + math.copysign(0.05, x), 0.0, sz * 0.3), (x, height - 0.08, 0.0), 0.1, 0.1,
                 WOOD_DARK, up=(1.0, 0.0, 0.0))
    board = Part("board")
    board.box(-0.9, 0.9, 0.0, 0.07, -0.2, 0.2, WOOD_LIGHT, left=SAND, right=SAND)
    place(p, board, 8.0, (0.0, height, 0.0))
    return p


def shade_by_normal(p: Part, colours: set, up: Rgb, side: Rgb, threshold: float = 0.55) -> None:
    """Recolour the faces of `colours` by facing, the way fantasy-town's rocks are painted: facets
    turned to the sky take the light stone, the rest the darker one."""
    for i, (idx, colour) in enumerate(p.faces):
        if colour not in colours:
            continue
        pts = [p.verts[k] for k in idx]
        n = [0.0, 0.0, 0.0]
        for j, a in enumerate(pts):
            b = pts[(j + 1) % len(pts)]
            n[0] += (a[1] - b[1]) * (a[2] + b[2])
            n[1] += (a[2] - b[2]) * (a[0] + b[0])
            n[2] += (a[0] - b[0]) * (a[1] + b[1])
        length = math.sqrt(sum(c * c for c in n)) or 1.0
        p.faces[i] = (idx, up if n[1] / length > threshold else side)


def boulder(name: str, radii: Vec, seed: int) -> Part:
    """Faceted field boulder in fantasy-town's stone ramp with a patch of moss on its crown. The
    stone is a coarse jittered blob, light on the facets that face up and darker below; the moss
    is a smaller green blob set back from the front and cut off low, so only a ragged patch of it
    breaks through the top of the stone. (A first cut capped the whole top in a smooth green
    dome and read as a mushroom.)"""
    p = Part(name)
    rx, ry, rz = radii
    p.blob((0.0, ry * 0.3, 0.0), (rx, ry, rz), STONE_MID, seg=6, rings=2, cut=-0.3, jitter=0.2, seed=seed)
    shade_by_normal(p, {STONE_MID}, STONE_LIGHT, STONE_MID)
    p.blob((0.12 * rx, ry * 0.3 + 0.02, 0.2 * rz), (rx * 0.78, ry * 1.03, rz * 0.78), MOSS, seg=6, rings=2,
           cut=0.7, jitter=0.12, seed=seed + 1)
    return p


def make_boulder_large() -> Part:
    """2.2 x 1.4 x 1.8 studs."""
    p = boulder("boulder-large", (1.1, 1.05, 0.9), 81)
    place(p, boulder("lump", (0.55, 0.6, 0.5), 85), 30.0, (0.75, 0.0, -0.3))
    return p


def make_boulder_small() -> Part:
    """1.1 x 0.9 x 0.9 studs."""
    return boulder("boulder-small", (0.6, 0.66, 0.5), 83)


def make_site_ground() -> Part:
    """Bare earth under a building site, 7.4 studs square with ragged edges (5.5 at scale 3). The slab
    is 0.06 tall; lighter trodden patches rise 0.05 above it, enough never to z-fight at distance."""
    p = Part("site-ground")
    rng = random.Random(71)
    half, points, power = 3.62, 32, 5.0
    outline = []
    for k in range(points):
        a = 2 * math.pi * (k + 0.5) / points
        c, s = math.cos(a), math.sin(a)
        r = (abs(c) ** power + abs(s) ** power) ** (-1.0 / power)
        j = 1.0 + rng.uniform(-0.03, 0.03)
        outline.append((half * r * c * j, half * r * s * j))
    prism(p, outline, 0.0, 0.06, EARTH)
    for cx, cz, rx, rz in ((-1.3, 1.0, 1.2, 0.8), (1.5, -1.1, 0.9, 0.7), (0.7, 1.9, 0.7, 0.5), (-1.9, -1.8, 0.6, 0.45)):
        prism(p, blotch(rng, cx, cz, rx, rz), 0.0, 0.11, EARTH_LIGHT)
    return p


def make_scaffold_ring() -> Part:
    """Open timber scaffold round a 9 x 9-stud slot, 7.6 studs tall, hollow in the middle so the
    landmark rising inside stays in view: eight standards, two lifts of ledgers, a board walk on the
    lower lift, and one brace per face on the outside. Nothing crosses the middle, and everything
    stays inside +-4.5, so the client's footprint / 9 scale fits it to any slot."""
    p = Part("scaffold-ring")
    e, height, post = 4.2, 7.6, 0.28
    posts = [(sx * e, sz * e) for sx in (-1, 0, 1) for sz in (-1, 0, 1) if (sx, sz) != (0, 0)]
    for x, z in posts:
        p.box(x - post / 2, x + post / 2, 0.0, height, z - post / 2, z + post / 2, WOOD_LIGHT, top=SAND)
    lifts = (3.5, 7.2)
    walk = lifts[0] + 0.1
    for rot in (0, 90, 180, 270):
        side = Part("side")
        for y in lifts:
            beam(side, (-e - post / 2, y, -e), (e + post / 2, y, -e), 0.18, 0.2, SAND, ends=CREAM)
        # boards stop short of the corner standards, so two faces' boards never overlap
        side.box(-e + 0.32, e - 0.32, walk, walk + 0.08, -e - 0.26, -e + 0.3, WOOD_LIGHT)
        zb = -e - post / 2 - 0.06
        beam(side, (-e + 0.1, 0.25, zb), (-0.1, lifts[0] - 0.15, zb), 0.14, 0.1, WOOD_MID, up=(0.0, 0.0, 1.0))
        beam(side, (0.1, lifts[0] + 0.25, zb), (e - 0.1, lifts[1] - 0.15, zb), 0.14, 0.1, WOOD_MID,
             up=(0.0, 0.0, 1.0))
        place(p, side, rot)
    return p


PIECES = {
    "crate": make_crate,
    "crate-pair": make_crate_pair,
    "ladder": make_ladder,
    "hoist": make_hoist,
    "stone-pile": make_stone_pile,
    "plank-stack": make_plank_stack,
    "haystack": make_haystack,
    "hay-bale": make_hay_bale,
    "notice-board": make_notice_board,
    "truss": make_truss,
    "timber": make_timber,
    "post": make_post,
    "sawhorse": make_sawhorse,
    "boulder-large": make_boulder_large,
    "boulder-small": make_boulder_small,
    "site-ground": make_site_ground,
    "scaffold-ring": make_scaffold_ring,
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
        size = tuple(hi[i] - lo[i] for i in range(3))
        print(
            f"[{KIT}] {name}.glb: {part.tris} tris, "
            f"{size[0] / STUDS_PER_UNIT:.3f} x {size[1] / STUDS_PER_UNIT:.3f} x {size[2] / STUDS_PER_UNIT:.3f} units "
            f"= {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f} studs at scale 4, min y {lo[1]:.2f}",
            flush=True,
        )
    print(f"[{KIT}] {len(PIECES)} pieces, {total} tris total -> {os.path.relpath(out_dir, REPO_ROOT)}", flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the village-extras-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)
    return generate(args.out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
