"""Street props for Boomtown's four city-changer purchases (M12 wave 2.2), generated as a
Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/boomtown_street_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/boomtown-street-kit/Models/GLB format/, the folder
convention every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. The mesh container and the export plumbing come from
garden_kit.py, the geometry helpers from village_extras_kit.py.

Why a custom kit (INTERFACES "M12 wave 2 -- Boomtown", wave 2.2 "Upgrade layers"): Install Fire
Hydrants, Put Up Billboards, Light the Neon District and Open the Bus Line no longer buy one
building each; they scatter props over the whole town. The four landmarks they replace were
stacks of roads-kit pieces (a hydrant of barrier blocks and stop signs, a billboard of fourteen
highway gantries, a neon arrow of fifty stop-sign discs), 400 to 4100 triangles apiece, which is
fine once and hopeless forty times over. And no kit has a hydrant, a shelter, a bench, a painted
billboard, a neon shape or a bus: car-kit stops at vans and trucks.

Each prop is one piece, so a prop merges to one mesh on one palette texture.

**Units.** City Kit units, **1 unit = 4 studs at blueprint scale 4.0**, like boomtown-extras-kit.
The literals below are studs as they come out at the blueprint's scale and are divided by it once,
at export: 4.0 (STUDS_PER_UNIT) unless PIECE_SCALE names another. The bus is written for 2.5, the
blueprint scale of the car-kit vehicles it drives among (VehicleA-C), and like them it is drawn at
half that size (`vehicles.scale` 0.5): every bus literal is twice what the street shows.

**Frames.** Origin at the bottom centre. Hydrant: nozzle toward -Z. Bus stop: open side and sign
toward -Z, the street. Billboards: the painted face toward -Z. Neon signs: the two neon faces look
along +-X, up and down the street, when the prop stands on a lot whose front is -Z. Neon arch: the
posts stand on the X axis, the faces look along +-Z. Bus: front -Z.

Colours are texels of the City Kits' colormap.png (suburban, industrial and roads share it) plus
three of car-kit's (the brighter red, the gold and the teal; car-kit is a Boomtown kit too), so
the pieces sit in the era palette. Materials are plain colour factors with no texture, written
linear like garden-kit's; merge_stages.py routes them through palette.py (not an sRGB-factor kit).

Art rules, matching the kits: flat shading, axis-aligned boxes, faceted solids of revolution,
chunky toy proportions. Every solid is closed and wound outward (Roblox culls back faces), and
painted or neon shapes are plates standing 0.03 to 0.06 proud of what carries them, never
coplanar with it.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from garden_kit import REPO_ROOT, Part, build_object, export  # noqa: E402
from village_extras_kit import beam, extrude_x, face_out, lathe, prism  # noqa: E402

import bpy  # noqa: E402

KIT = "boomtown-street-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")
STUDS_PER_UNIT = 4.0
VEHICLE_SCALE = 2.5  # the blueprint scale of VehicleA-C

Rgb = tuple[int, int, int]
Vec = tuple[float, float, float]
Point = tuple[float, float]

# Texels of the City Kits' colormap.png.
WHITE = (255, 255, 255)
CREAM = (253, 228, 199)
LAVENDER = (160, 168, 201)
STONE = (142, 149, 179)
STONE_DARK = (134, 139, 161)
SLATE_LIGHT = (102, 107, 128)
SLATE = (81, 85, 102)
CHARCOAL = (56, 56, 61)
GLASS = (208, 232, 255)
BLUE = (103, 148, 217)
GREEN = (97, 203, 139)
YELLOW = (255, 192, 68)
ORANGE = (255, 126, 68)
PINK = (243, 120, 240)
WOOD = (241, 151, 108)
BRICK = (176, 96, 65)
# Texels of car-kit's colormap.png.
RED_BRIGHT = (222, 67, 62)
GOLD = (255, 194, 20)
TEAL = (97, 200, 175)  # the kits' nearest thing to a neon cyan


# --- helpers ------------------------------------------------------------------------------------


def ear_clip(outline: list[Point]) -> list[tuple[int, int, int]]:
    """Triangles (index triples) of a simple polygon, convex or not. Blender would triangulate a
    concave cap itself, but its choice is not ours to pin down, and a star or an arrow is concave."""
    n = len(outline)
    area = sum(outline[i][0] * outline[(i + 1) % n][1] - outline[(i + 1) % n][0] * outline[i][1] for i in range(n))
    order = list(range(n)) if area > 0 else list(range(n - 1, -1, -1))

    def cross(a: Point, b: Point, c: Point) -> float:
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    triangles = []
    guard = 0
    while len(order) > 3 and guard < 10 * n:
        guard += 1
        for k in range(len(order)):
            i, j, m = order[k - 1], order[k], order[(k + 1) % len(order)]
            a, b, c = outline[i], outline[j], outline[m]
            turn = cross(a, b, c)
            if turn < -1e-9:
                continue  # reflex: not an ear
            if turn > 1e-9 and any(
                cross(a, b, outline[q]) > 1e-9 and cross(b, c, outline[q]) > 1e-9 and cross(c, a, outline[q]) > 1e-9
                for q in order
                if q not in (i, j, m)
            ):
                continue  # another vertex inside it
            if turn > 1e-9:
                triangles.append((i, j, m))
            del order[k]  # a straight vertex is dropped with no triangle
            break
    if len(order) == 3:
        triangles.append((order[0], order[1], order[2]))
    return triangles


def plate(p: Part, axis: str, outline: list[Point], w0: float, w1: float, colour: Rgb, edge: Rgb | None = None) -> None:
    """A flat shape of any simple outline, extruded from w0 to w1 along `axis`. With "z" the
    outline is (x, y) and the faces look along +-Z (billboard paint, the arch); with "x" it is
    (z, y) and the faces look along +-X (the neon blades). `edge` colours the rim."""
    w0, w1 = sorted((w0, w1))

    def point(u: float, v: float, w: float) -> Vec:
        return (u, v, w) if axis == "z" else (w, v, u)

    def vector(u: float, v: float, w: float) -> Vec:
        return (u, v, w) if axis == "z" else (w, v, u)

    n = len(outline)
    for tri in ear_clip(outline):
        face_out(p, [point(*outline[i], w0) for i in tri], colour, vector(0.0, 0.0, -1.0))
        face_out(p, [point(*outline[i], w1) for i in tri], colour, vector(0.0, 0.0, 1.0))
    area = sum(outline[i][0] * outline[(i + 1) % n][1] - outline[(i + 1) % n][0] * outline[i][1] for i in range(n))
    sign = 1.0 if area > 0 else -1.0
    for i in range(n):
        (u0, v0), (u1, v1) = outline[i], outline[(i + 1) % n]
        if abs(u1 - u0) + abs(v1 - v0) < 1e-9:
            continue
        outward = vector(sign * (v1 - v0), -sign * (u1 - u0), 0.0)
        quad = [point(u0, v0, w0), point(u1, v1, w0), point(u1, v1, w1), point(u0, v0, w1)]
        face_out(p, quad, edge or colour, outward)


def disc(cx: float, cy: float, r: float, seg: int = 8, a0: float = 0.0, a1: float = 360.0) -> list[Point]:
    """A faceted disc outline, or with a0/a1 (degrees) the arc between them, both ends included."""
    if a1 - a0 >= 360.0:
        return [(cx + r * math.cos(2 * math.pi * (k + 0.5) / seg), cy + r * math.sin(2 * math.pi * (k + 0.5) / seg))
                for k in range(seg)]
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / seg)),
             cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / seg))) for k in range(seg + 1)]


def star(cx: float, cy: float, outer: float, inner: float, points: int, phase: float = 90.0) -> list[Point]:
    out = []
    for k in range(2 * points):
        r = outer if k % 2 == 0 else inner
        a = math.radians(phase + 180.0 * k / points)
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def rect(u0: float, u1: float, v0: float, v1: float) -> list[Point]:
    return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


def loft(p: Part, lower: list[Point], y0: float, upper: list[Point], y1: float, colour: Rgb, top: Rgb | None = None,
         cap: bool = True) -> None:
    """A band between two convex plan outlines [(x, z)] with the same point count, lower at y0 and
    upper at y1 (a vehicle's rounded roof), with the upper outline capped."""
    n = len(lower)
    cx = sum(x for x, _ in lower) / n
    cz = sum(z for _, z in lower) / n
    mid = (cx, (y0 + y1) / 2, cz)
    for i in range(n):
        j = (i + 1) % n
        p.face([(lower[i][0], y0, lower[i][1]), (lower[j][0], y0, lower[j][1]),
                (upper[j][0], y1, upper[j][1]), (upper[i][0], y1, upper[i][1])], colour, mid)
    if cap:
        face_out(p, [(x, y1, z) for x, z in upper], top or colour, (0.0, 1.0, 0.0))
        face_out(p, [(x, y0, z) for x, z in lower], colour, (0.0, -1.0, 0.0))


def footing(p: Part, x: float, z: float, half: float, height: float) -> None:
    """The concrete pad a post stands in: cool grey, so the post's foot stands off the tan ground."""
    p.box(x - half, x + half, 0.0, height, z - half, z + half, STONE_DARK, top=LAVENDER)


# --- hydrant ------------------------------------------------------------------------------------


def make_hydrant() -> Part:
    """A 1950s fire hydrant, 0.84 x 1.3 x 0.84 studs, pumper nozzle toward -Z: a red barrel on a
    flange under a domed bonnet, two hose nozzles and the pumper nozzle with white caps, a white
    operating nut, on a pale concrete pad. The landmark it replaces (FireHydrant: roads-kit barrier
    blocks, a cone and three stop signs) is 0.92 x 1.94 x 1.09 at scale 4 and 432 triangles; this
    keeps its width, drops to kerb height, and stands on a pad because red on the tan plot base is
    a weak pairing and a hydrant on a pale square is not."""
    p = Part("hydrant")
    p.box(-0.42, 0.42, 0.0, 0.06, -0.42, 0.42, STONE_DARK, top=LAVENDER)
    red = RED_BRIGHT
    profile = [(0.31, 0.06), (0.31, 0.17), (0.2, 0.17), (0.2, 0.8), (0.27, 0.8), (0.27, 0.9), (0.22, 0.9),
               (0.19, 1.04), (0.1, 1.15), (0.075, 1.15), (0.075, 1.3)]
    lathe(p, profile, [red, red, red, red, red, red, red, red, WHITE, WHITE], seg=8, phase=math.pi / 8)
    for sx in (-1, 1):  # hose nozzles
        x0, x1 = sorted((sx * 0.15, sx * 0.35))
        extrude_x(p, [(z, y) for z, y in disc(0.0, 0.63, 0.105, 6)], x0, x1, red)
        x0, x1 = sorted((sx * 0.35, sx * 0.4))
        extrude_x(p, [(z, y) for z, y in disc(0.0, 0.63, 0.085, 6)], x0, x1, WHITE)
    plate(p, "z", disc(0.0, 0.52, 0.145, 8), -0.36, -0.15, red)  # the pumper nozzle
    plate(p, "z", disc(0.0, 0.52, 0.12, 8), -0.42, -0.36, WHITE)
    return p


# --- bus stop -----------------------------------------------------------------------------------


def make_bus_stop() -> Part:
    """A kerbside shelter, 4.0 x 2.9 x 1.6 studs, open toward -Z: a pale pad, a glazed back wall
    and two half-depth end screens on slate posts, a blue roof with a white fascia, a wooden bench,
    and at the +X end a pole with a round blue bus-stop sign and a yellow timetable board, both
    dressed on both faces. The roof is the kits' sky blue because the tycoon camera sees roofs
    first: Boomtown's are green (houses) and slate (shops), so a blue one says "not a building"."""
    p = Part("bus-stop")
    p.box(-2.0, 2.0, 0.0, 0.06, -0.8, 0.8, STONE_DARK, top=LAVENDER)
    posts = (-1.86, -0.3, 1.26)
    zb = 0.58  # the back wall's centre line
    roof0, roof1 = 2.28, 2.46
    for x in posts:
        p.box(x - 0.07, x + 0.07, 0.06, roof0, zb - 0.07, zb + 0.07, SLATE)
    for x0, x1 in ((posts[0], posts[1]), (posts[1], posts[2])):
        p.box(x0 + 0.07, x1 - 0.07, 0.2, 0.95, zb - 0.04, zb + 0.04, WHITE)
        p.box(x0 + 0.07, x1 - 0.07, 0.95, 1.05, zb - 0.06, zb + 0.06, SLATE_LIGHT)
        p.box(x0 + 0.07, x1 - 0.07, 1.05, 2.05, zb - 0.03, zb + 0.03, GLASS)
        p.box(x0 + 0.07, x1 - 0.07, 2.05, 2.15, zb - 0.06, zb + 0.06, SLATE_LIGHT)
    for x in (posts[0], posts[2]):  # the end screens, and the front posts they stand between
        p.box(x - 0.07, x + 0.07, 0.06, roof0, -0.25, -0.11, SLATE)
        p.box(x - 0.03, x + 0.03, 0.95, 2.05, -0.11, zb - 0.07, GLASS)
        p.box(x - 0.04, x + 0.04, 0.2, 0.95, -0.11, zb - 0.07, WHITE)
    p.box(-2.0, 1.33, roof0, roof1, -0.76, 0.76, BLUE, bottom=STONE_DARK, front=WHITE, back=WHITE, left=WHITE,
          right=WHITE)
    p.box(-1.86, 1.19, roof1, roof1 + 0.05, -0.62, 0.62, BLUE)  # a raised field, so the roof is not one flat quad
    # the bench: three slats on two slate frames, and a back rest on the wall
    for x in (-1.3, 0.7):
        p.box(x - 0.05, x + 0.05, 0.06, 0.5, 0.05, 0.45, SLATE)
    for k in range(3):
        z0 = 0.02 + k * 0.16
        p.box(-1.6, 1.0, 0.5, 0.57, z0, z0 + 0.13, WOOD, front=BRICK if k == 0 else WOOD)
    p.box(-1.6, 1.0, 0.72, 0.9, zb - 0.11, zb - 0.04, WOOD)
    # the stop sign, on its own pole at the end of the pad
    sx, sz = 1.68, -0.5
    p.box(sx - 0.06, sx + 0.06, 0.06, 2.3, sz - 0.06, sz + 0.06, SLATE)
    plate(p, "z", disc(sx, 2.62, 0.3, 8), sz - 0.05, sz + 0.05, BLUE, WHITE)
    for facing in (-1, 1):
        face = sz + facing * 0.05
        z0, z1 = sorted((face, face + facing * 0.03))
        p.box(sx - 0.18, sx + 0.18, 2.52, 2.74, z0, z1, WHITE)  # the bus, as a white block with a dark window band
        z0, z1 = sorted((face + facing * 0.03, face + facing * 0.05))
        p.box(sx - 0.13, sx + 0.13, 2.63, 2.7, z0, z1, SLATE)
    p.box(sx - 0.24, sx + 0.24, 1.3, 1.9, sz - 0.1, sz - 0.06, YELLOW)
    p.box(sx - 0.24, sx + 0.24, 1.3, 1.9, sz + 0.06, sz + 0.1, YELLOW)
    for y in (1.42, 1.57, 1.72):
        p.box(sx - 0.17, sx + 0.17, y, y + 0.07, sz - 0.12, sz - 0.1, SLATE)
        p.box(sx - 0.17, sx + 0.17, y, y + 0.07, sz + 0.1, sz + 0.12, SLATE)
    return p


# --- billboards ---------------------------------------------------------------------------------
#
# A painted board is a slab whose front face is the background colour; the design is flat plates
# on it, each starting at the face and standing 0.03 per layer proud, so a higher layer covers a
# lower one and nothing is coplanar. Designs are written as the viewer in the street sees them
# (u to the viewer's right, which is -X; v up from the board's centre).


class Board:
    def __init__(self, p: Part, half_w: float, y0: float, y1: float, z_face: float, thick: float, ground: Rgb,
                 frame: Rgb, frame_w: float = 0.1):
        self.p = p
        self.cy = (y0 + y1) / 2
        self.face = z_face
        p.box(-half_w, half_w, y0, y1, z_face, z_face + thick, STONE_DARK, front=ground)
        f = frame_w
        for x0, x1, a, b in ((-half_w - f, half_w + f, y1, y1 + f), (-half_w - f, half_w + f, y0 - f, y0),
                             (-half_w - f, -half_w, y0, y1), (half_w, half_w + f, y0, y1)):
            p.box(x0, x1, a, b, z_face - 0.06, z_face + thick + 0.02, frame)

    def paint(self, outline: list[Point], colour: Rgb, layer: int = 1) -> None:
        pts = [(-u, self.cy + v) for u, v in outline]
        plate(self.p, "z", pts, self.face - 0.03 * layer, self.face, colour)

    def bar(self, u0: float, u1: float, v0: float, v1: float, colour: Rgb, layer: int = 1) -> None:
        self.paint(rect(u0, u1, v0, v1), colour, layer)


def roadside_billboard(name: str, ground: Rgb) -> tuple[Part, Board]:
    """BillboardA and B's structure, 4.0 x 6.45 x 0.6 studs: a 3.8 x 2.8 board in a white frame on
    two slate posts in concrete footings, battens across the back, and a catwalk under the painted
    face with two lamp troughs on it. Everything stays inside z +-0.3."""
    p = Part(name)
    y0, y1 = 3.55, 6.35
    for x in (-1.25, 1.25):
        footing(p, x, 0.13, 0.17, 0.1)
        p.box(x - 0.11, x + 0.11, 0.1, y1 + 0.02, 0.04, 0.26, SLATE)
    board = Board(p, 1.9, y0, y1, -0.08, 0.1, ground, WHITE)
    for y in (y0 + 0.5, y1 - 0.5):
        p.box(-1.9, 1.9, y - 0.07, y + 0.07, 0.04, 0.12, SLATE_LIGHT)
    p.box(-2.0, 2.0, y0 - 0.32, y0 - 0.24, -0.3, -0.02, SLATE_LIGHT, top=STONE)
    for x in (-1.25, 1.25):
        p.box(x - 0.06, x + 0.06, y0 - 0.32, y0 - 0.24, -0.02, 0.04, SLATE)  # the catwalk's brackets
    for x in (-0.95, 0.95):
        p.box(x - 0.28, x + 0.28, y0 - 0.24, y0 - 0.12, -0.3, -0.2, SLATE, top=YELLOW)
    return p, board


def make_billboard_a() -> Part:
    """A soda advertisement on gold: a red sun rising with seven rays, a brown bottle with a white
    label and a red cap, a slate headline bar over a red one."""
    p, b = roadside_billboard("billboard-a", YELLOW)
    sun = (-0.9, -1.4)
    b.paint(disc(sun[0], sun[1], 0.62, 8, 0.0, 180.0), RED_BRIGHT, 2)
    b.paint(disc(sun[0], sun[1], 0.38, 6, 0.0, 180.0), ORANGE, 3)
    for k in range(7):
        a = math.radians(15.0 + 25.0 * k)
        c, s = math.cos(a), math.sin(a)
        r0, r1, w = 0.74, 0.98 if k % 2 else 1.12, 0.11
        if sun[0] + r1 * c < -1.86:  # the outermost ray would cross the frame
            r1 = (-1.86 - sun[0]) / c
        b.paint([(sun[0] + r0 * c + w * s, sun[1] + r0 * s - w * c), (sun[0] + r1 * c, sun[1] + r1 * s),
                 (sun[0] + r0 * c - w * s, sun[1] + r0 * s + w * c)], RED_BRIGHT, 2)
    u = 1.05
    b.paint([(u - 0.3, -1.2), (u + 0.3, -1.2), (u + 0.3, 0.0), (u + 0.15, 0.45), (u + 0.11, 0.92), (u - 0.11, 0.92),
             (u - 0.15, 0.45), (u - 0.3, 0.0)], BRICK, 2)
    b.bar(u - 0.3, u + 0.3, -0.85, -0.3, WHITE, 3)
    b.paint(disc(u, -0.575, 0.17, 8), RED_BRIGHT, 4)
    b.bar(u - 0.14, u + 0.14, 0.92, 1.1, RED_BRIGHT, 2)
    b.bar(-1.65, 0.35, 0.72, 1.08, SLATE, 2)
    b.bar(-1.65, -0.25, 0.3, 0.54, RED_BRIGHT, 2)
    return p


def make_billboard_b() -> Part:
    """A motor-car advertisement on sky blue: a red saloon with pale windows and white-walled
    wheels on a slate road, a white and gold speed stripe behind it, a gold headline over a white
    one."""
    p, b = roadside_billboard("billboard-b", BLUE)
    b.bar(-1.9, 1.9, -1.4, -1.0, SLATE, 2)
    b.paint([(-1.9, -0.42), (1.9, -0.3), (1.9, 0.02), (-1.9, -0.26)], WHITE, 2)
    b.paint([(-1.9, -0.62), (1.9, -0.5), (1.9, -0.38), (-1.9, -0.5)], YELLOW, 2)
    ox, oy = -0.35, 0.0
    body = [(-1.3, -0.95), (1.3, -0.95), (1.36, -0.55), (0.95, -0.38), (-1.25, -0.38), (-1.36, -0.6)]
    cabin = [(-0.8, -0.38), (0.6, -0.38), (0.32, 0.14), (-0.58, 0.14)]
    b.paint([(u + ox, v + oy) for u, v in body], RED_BRIGHT, 3)
    b.paint([(u + ox, v + oy) for u, v in cabin], RED_BRIGHT, 3)
    b.paint([(u + ox, v + oy) for u, v in [(-0.64, -0.34), (-0.1, -0.34), (-0.1, 0.05), (-0.5, 0.05)]], GLASS, 4)
    b.paint([(u + ox, v + oy) for u, v in [(0.02, -0.34), (0.46, -0.34), (0.27, 0.05), (0.02, 0.05)]], GLASS, 4)
    for wx in (-0.78, 0.78):
        b.paint(disc(wx + ox, -0.95 + oy, 0.29, 8), CHARCOAL, 4)
        b.paint(disc(wx + ox, -0.95 + oy, 0.13, 6), WHITE, 5)
    b.bar(0.1, 1.65, 0.78, 1.1, YELLOW, 2)
    b.bar(0.75, 1.65, 0.4, 0.62, WHITE, 2)
    return p


def lattice_leg(p: Part, cx: float, z0: float, z1: float, top: float, half: float = 0.42) -> None:
    """One steel lattice leg: four slate standards, a ring of horizontals at each of four levels
    and one diagonal per face per bay, zig-zagging, which reads as lattice at half the triangles of
    a cross per face."""
    t = 0.11
    corners = [(cx - half, z0), (cx + half, z0), (cx + half, z1), (cx - half, z1)]
    for x, z in corners:
        footing(p, x, z, 0.12, 0.1)
        p.box(x - t / 2, x + t / 2, 0.1, top, z - t / 2, z + t / 2, SLATE)
    levels = [0.3 + (top - 0.4) * k / 3 for k in range(4)]
    for i in range(4):
        (xa, za), (xb, zb) = corners[i], corners[(i + 1) % 4]
        normal = (0.0, 0.0, 1.0) if abs(za - zb) < 1e-6 else (1.0, 0.0, 0.0)
        for y in levels:
            beam(p, (xa, y, za), (xb, y, zb), t * 0.8, t * 0.8, SLATE_LIGHT, up=normal)
        for k in range(3):
            ya, yb = levels[k] + 0.08, levels[k + 1] - 0.08
            if (i + k) % 2:
                ya, yb = yb, ya
            beam(p, (xa, ya, za), (xb, yb, zb), t * 0.8, t * 0.6, SLATE_LIGHT, up=normal)


def make_billboard_c() -> Part:
    """The large billboard, 7.5 x 8.9 x 0.96 studs: a 7.3 x 3.5 board in a red frame, its foot at
    5.3 so the whole painted face clears a row of 4.5-stud shops, on two steel lattice legs, with a
    railed catwalk and three lamp troughs. The design is a diner's: a hamburger on white (cream
    is too near the tan plot base to stand off it) beside a red starburst with a gold centre, over a
    red banner with white lettering blocks."""
    p = Part("billboard-c")
    y0, y1 = 5.3, 8.8
    for cx in (-2.2, 2.2):
        lattice_leg(p, cx, 0.0, 0.34, y1 - 0.3)
    board = Board(p, 3.65, y0, y1, -0.2, 0.12, WHITE, RED_BRIGHT)
    for y in (y0 + 0.6, y1 - 0.6):  # battens on the back, landing on the legs
        p.box(-3.65, 3.65, y - 0.08, y + 0.08, -0.08, 0.0, SLATE_LIGHT)
    p.box(-3.75, 3.75, y0 - 0.36, y0 - 0.26, -0.5, -0.1, SLATE_LIGHT, top=STONE)
    beam(p, (-3.7, y0 + 0.02, -0.46), (3.7, y0 + 0.02, -0.46), 0.06, 0.06, SLATE)  # the catwalk rail
    for k in range(6):
        x = -3.7 + 7.4 * k / 5
        p.box(x - 0.035, x + 0.035, y0 - 0.26, y0 + 0.02, -0.495, -0.425, SLATE)
    for x in (-2.2, 0.0, 2.2):
        p.box(x - 0.32, x + 0.32, y0 - 0.26, y0 - 0.13, -0.42, -0.3, SLATE, top=YELLOW)
    b = board
    b.bar(-3.65, 3.65, -1.75, -1.0, RED_BRIGHT, 1)
    for u0, u1 in ((-3.2, -1.5), (-1.2, 0.3), (0.6, 1.5), (1.8, 3.2)):
        b.bar(u0, u1, -1.53, -1.22, WHITE, 2)
    ox, oy = -1.75, 0.25  # the hamburger

    def at(points: list[Point]) -> list[Point]:
        return [(u + ox, v + oy) for u, v in points]

    b.paint(at([(-1.3, -0.95), (1.3, -0.95), (1.42, -0.8), (1.42, -0.58), (-1.42, -0.58), (-1.42, -0.8)]), WOOD, 1)
    b.paint(at(rect(-1.48, 1.48, -0.58, -0.22)), BRICK, 2)
    b.paint(at([(-1.55, -0.06), (-1.55, -0.22), (-1.0, -0.22), (-0.75, -0.46), (-0.5, -0.22), (0.55, -0.22),
                (0.75, -0.42), (0.95, -0.22), (1.55, -0.22), (1.55, -0.06)]), YELLOW, 3)
    frill = [(1.6 - 3.2 * k / 16, 0.24 if k % 2 else 0.1) for k in range(17)]  # right to left, along the top
    b.paint(at([(-1.6, -0.06), (1.6, -0.06)] + frill), GREEN, 2)
    b.paint(at(rect(-1.4, 1.4, 0.1, 0.3)), RED_BRIGHT, 1)
    dome = [(1.42, 0.3)] + [(1.42 * math.cos(math.radians(a)), 0.42 + 0.78 * math.sin(math.radians(a)))
                             for a in (10, 30, 50, 70, 90, 110, 130, 150, 170)] + [(-1.42, 0.3)]
    b.paint(at(dome), WOOD, 2)
    for u, v in ((-0.75, 0.72), (-0.2, 0.95), (0.4, 0.82), (0.85, 0.55), (-0.1, 0.55)):
        b.bar(u + ox - 0.09, u + ox + 0.09, v + oy - 0.045, v + oy + 0.045, CREAM, 3)
    sx, sy = 1.95, 0.42  # the starburst
    b.paint(star(sx, sy, 1.18, 0.86, 12), RED_BRIGHT, 1)
    b.paint(disc(sx, sy, 0.7, 10), YELLOW, 2)
    b.bar(sx - 0.42, sx + 0.42, sy + 0.08, sy + 0.3, RED_BRIGHT, 3)
    b.bar(sx - 0.3, sx + 0.3, sy - 0.3, sy - 0.1, SLATE, 3)
    return p


# --- neon ---------------------------------------------------------------------------------------
#
# A neon sign is a blade on a pole: a dark backing 0.36 thick whose two faces look along the
# street, the tubes as plates 0.05 proud on both, and a bar of tube colour down each narrow edge:
# the tycoon camera mostly looks across the street, where a blade is edge on, and the bars are
# what it shows there. The blade is that thick for the same reason.
# By day neon reads by saturation against a dark ground, so the backing is the kits' charcoal and
# the tubes their three most saturated lights: pink, gold and teal.

BLADE = 0.18  # half the backing's thickness
TUBE = 0.05


def neon_pole(p: Part, top: float) -> None:
    footing(p, 0.0, 0.0, 0.2, 0.08)
    p.box(-0.075, 0.075, 0.08, top, -0.075, 0.075, SLATE)


def backing(p: Part, outline: list[Point]) -> None:
    plate(p, "x", outline, -BLADE, BLADE, CHARCOAL, SLATE)


def tube(p: Part, outline: list[Point], colour: Rgb, layer: int = 1) -> None:
    """A neon shape on both faces of the blade."""
    reach = BLADE + TUBE * layer
    plate(p, "x", outline, BLADE, reach, colour)
    plate(p, "x", outline, -reach, -BLADE, colour)


def edge_strip(p: Part, z: float, y0: float, y1: float, colour: Rgb) -> None:
    """A bar of tube down a narrow edge of the blade, at z (the edge) reaching 0.04 outward."""
    z0, z1 = sorted((z, z + math.copysign(0.04, z)))
    p.box(-0.11, 0.11, y0, y1, z0, z1, colour)


def make_neon_sign_a() -> Part:
    """The arrow, 0.56 x 4.6 x 0.8 studs: a blade pointed at the foot, a pink arrow pointing down
    at the shop door with five gold bulbs down its shaft, gold edge strips."""
    p = Part("neon-sign-a")
    neon_pole(p, 2.2)
    y0, y1 = 2.5, 4.6
    backing(p, [(-0.36, y0), (0.0, 1.95), (0.36, y0), (0.36, y1), (-0.36, y1)])
    tube(p, [(-0.14, 4.48), (0.14, 4.48), (0.14, 2.85), (0.31, 2.85), (0.0, 2.12), (-0.31, 2.85), (-0.14, 2.85)], PINK)
    for k in range(5):
        y = 3.05 + 0.3 * k
        tube(p, rect(-0.065, 0.065, y, y + 0.13), GOLD, 2)
    for z in (-0.36, 0.36):
        edge_strip(p, z, y0 + 0.05, y1 - 0.05, GOLD)
    return p


def make_neon_sign_b() -> Part:
    """The coffee cup, 0.56 x 4.3 x 0.8 studs: an eight-sided blade with a teal cup on a saucer
    under three pink wisps of steam, over a narrower blade with three gold lettering blocks. (A
    coffee cup, not a cocktail glass: the experience is published for all ages.)"""
    p = Part("neon-sign-b")
    neon_pole(p, 2.0)
    backing(p, rect(-0.26, 0.26, 1.95, 3.1))
    for k in range(3):
        y = 2.08 + 0.32 * k
        tube(p, rect(-0.17, 0.17, y, y + 0.22), GOLD)
    cy = 3.68
    backing(p, [(-0.2, cy - 0.62), (0.2, cy - 0.62), (0.36, cy - 0.3), (0.36, cy + 0.3), (0.2, cy + 0.62),
                (-0.2, cy + 0.62), (-0.36, cy + 0.3), (-0.36, cy - 0.3)])
    tube(p, [(-0.2, cy - 0.3), (0.1, cy - 0.3), (0.15, cy + 0.08), (-0.25, cy + 0.08)], TEAL)  # the cup
    tube(p, rect(0.12, 0.29, cy - 0.2, cy + 0.02), TEAL)  # its handle
    tube(p, rect(0.16, 0.23, cy - 0.14, cy - 0.04), CHARCOAL, 2)
    tube(p, rect(-0.27, 0.2, cy - 0.42, cy - 0.34), TEAL)  # the saucer
    for z in (-0.19, -0.05, 0.09):  # three wisps of steam, each bent once
        w, bend = 0.032, 0.07
        tube(p, [(z - w, cy + 0.16), (z + w, cy + 0.16), (z + w + bend, cy + 0.33), (z + w, cy + 0.5),
                 (z - w, cy + 0.5), (z - w + bend, cy + 0.33)], PINK)
    for z in (-0.36, 0.36):
        edge_strip(p, z, cy - 0.25, cy + 0.25, PINK)
    for z in (-0.26, 0.26):
        edge_strip(p, z, 2.0, 3.0, TEAL)
    return p


def make_neon_sign_c() -> Part:
    """The star, 0.56 x 4.73 x 0.78 studs: a diamond blade with a gold five-pointed star in a teal
    diamond outline, over a blade with four teal lettering blocks."""
    p = Part("neon-sign-c")
    neon_pole(p, 2.0)
    backing(p, rect(-0.24, 0.24, 1.95, 3.5))
    for k in range(4):
        y = 2.08 + 0.34 * k
        tube(p, rect(-0.16, 0.16, y, y + 0.24), TEAL)
    cy = 4.05
    backing(p, [(0.0, cy - 0.68), (0.39, cy), (0.0, cy + 0.68), (-0.39, cy)])
    for sz in (-1, 1):  # the diamond's outline, as four bars set just inside the rim
        for sy in (-1, 1):
            tube(p, [(sz * 0.335, cy), (0.0, cy + sy * 0.585), (0.0, cy + sy * 0.47), (sz * 0.27, cy)], TEAL)
    tube(p, star(0.0, cy - 0.02, 0.31, 0.13, 5), GOLD, 2)
    for z in (-0.24, 0.24):
        edge_strip(p, z, 2.0, 3.4, GOLD)
    return p


def make_neon_arch() -> Part:
    """The arch over Main Street, 9.5 x 6.47 x 0.5 studs: two slate posts 9 studs apart with a pink
    tube up each face, and a dark span that curves from 4.3 at the posts to 5.05 at the crown (its
    lowest point is 4.3, so everything on the road passes under), a pink tube along its top edge
    and a teal one along its foot, eight gold lettering blocks following the curve, and a pink star
    on a dark disc at the crown. Dressed on both faces: the street sees it from either end."""
    p = Part("neon-arch")
    half, t = 4.5, 0.1

    def low(x: float) -> float:
        return 4.3 + 0.75 * (1.0 - (x / half) ** 2)

    band = 0.95
    for sx in (-1, 1):
        x = sx * half
        footing(p, x, 0.0, 0.25, 0.12)
        p.box(x - 0.12, x + 0.12, 0.12, low(half) + band + 0.1, -0.12, 0.12, SLATE)
        for facing in (-1, 1):
            z0, z1 = sorted((facing * 0.12, facing * 0.16))
            p.box(x - 0.045, x + 0.045, 1.3, 4.1, z0, z1, PINK)
    steps = 12
    xs = [-half + 2 * half * k / steps for k in range(steps + 1)]

    def ribbon(off0: float, off1: float) -> list[Point]:
        return [(x, low(x) + off0) for x in xs] + [(x, low(x) + off1) for x in reversed(xs)]

    plate(p, "z", ribbon(0.0, band), -t, t, CHARCOAL, SLATE)
    for facing in (-1, 1):
        z0, z1 = sorted((facing * t, facing * (t + TUBE)))
        plate(p, "z", ribbon(band - 0.13, band - 0.04), z0, z1, PINK)
        plate(p, "z", ribbon(0.04, 0.13), z0, z1, TEAL)
        count, w, h = 9, 0.5, 0.42
        for k in range(count):
            x = -3.6 + 7.2 * k / (count - 1)
            if k == count // 2:
                continue  # the crown takes the star's disc
            slope = -1.5 * x / (half * half)
            n = math.hypot(1.0, slope)
            tx, ty = 1.0 / n, slope / n
            cx, cy = x, low(x) + band / 2
            quad = [(cx - tx * w / 2 + ty * h / 2, cy - ty * w / 2 - tx * h / 2),
                    (cx + tx * w / 2 + ty * h / 2, cy + ty * w / 2 - tx * h / 2),
                    (cx + tx * w / 2 - ty * h / 2, cy + ty * w / 2 + tx * h / 2),
                    (cx - tx * w / 2 - ty * h / 2, cy - ty * w / 2 + tx * h / 2)]
            plate(p, "z", quad, z0, z1, GOLD)
    crown = low(0.0) + band / 2 + 0.28
    plate(p, "z", disc(0.0, crown, 0.66, 10), -t - 0.02, t + 0.02, CHARCOAL, SLATE)
    for facing in (-1, 1):
        z0, z1 = sorted((facing * (t + 0.02), facing * (t + 0.02 + TUBE)))
        plate(p, "z", star(0.0, crown, 0.56, 0.24, 5), z0, z1, PINK)
    return p


# --- the bus (studs at blueprint scale VEHICLE_SCALE; the street shows it at half) ---------------


def rounded_plan(hx: float, z0: float, z1: float, front: float, rear: float) -> list[Point]:
    """A vehicle's plan outline [(x, z)], front toward -Z, with chamfered corners."""
    return [(-hx + front, z0), (hx - front, z0), (hx, z0 + front), (hx, z1 - rear), (hx - rear, z1),
            (-hx + rear, z1), (-hx, z1 - rear), (-hx, z0 + front)]


def inset(outline: list[Point], d: float, dz: float | None = None) -> list[Point]:
    """`outline` pulled toward the Z axis by d and toward its own middle in Z by dz (default d)."""
    dz = d if dz is None else dz
    zc = (min(z for _, z in outline) + max(z for _, z in outline)) / 2
    return [(x - d * math.copysign(1.0, x), z - dz * math.copysign(1.0, z - zc)) for x, z in outline]


def wheel(p: Part, x_out: float, y: float, z: float, r: float, width: float) -> None:
    """A tyre and a pale hub, axle along X; x_out is the outer face."""
    s = math.copysign(1.0, x_out)
    x0, x1 = sorted((x_out, x_out - s * width))
    extrude_x(p, [(z + u, y + v) for u, v in disc(0.0, 0.0, r, 8)], x0, x1, CHARCOAL)
    x0, x1 = sorted((x_out, x_out + s * 0.05))
    extrude_x(p, [(z + u, y + v) for u, v in disc(0.0, 0.0, r * 0.5, 6)], x0, x1, STONE)


def make_bus() -> Part:
    """A 1950s city bus, front -Z, 4.65 x 4.9 x 12.3 studs at blueprint scale 2.5 and so 2.3 x 2.45
    x 6.1 on the street (`vehicles.scale` 0.5), beside a 1.9 x 1.6 x 3.2 sedan: the shelters' sky
    blue below a gold belt line (car-kit's sedan is red and its taxi yellow, so blue is the livery
    nothing else on the road wears), cream above it and over the rounded roof, a dark window band, a split windscreen
    under a gold destination blind, two doors on the kerb side (+X: the traffic keeps right), four
    wheels. Car-kit has no bus (the BusYellow landmark is a stop built of roads-kit pieces), so
    this is the era's only generated vehicle; its glass is the kits' slate, which is what car-kit's
    windows are."""
    p = Part("bus")
    hx, z0, z1 = 2.2, -6.0, 6.0
    floor, belt, sill, head, roof = 0.6, 2.35, 2.65, 4.0, 4.75
    body = rounded_plan(hx, z0, z1, 0.55, 0.45)
    prism(p, body, floor, belt, BLUE)
    prism(p, inset(body, -0.04), belt, sill, GOLD)
    upper = inset(body, 0.12)
    prism(p, upper, sill, head, CREAM)
    loft(p, upper, head, inset(upper, 0.55, 0.9), roof, CREAM)
    ux, uz0, uz1 = hx - 0.12, z0 + 0.12, z1 - 0.12
    glass = SLATE
    # side windows: six a side, the kerb side losing two to its doors
    panes = [(-4.55 + 1.6 * k, -4.55 + 1.6 * k + 1.3) for k in range(6)]
    for sx in (-1, 1):
        x0, x1 = sorted((sx * ux, sx * (ux + 0.1)))
        for k, (a, b) in enumerate(panes):
            if sx > 0 and k in (0, 3):
                continue
            p.box(x0, x1, sill + 0.15, head - 0.15, a, b, glass)
    for a, b in (panes[0], panes[3]):  # the doors: a cream leaf with a tall pane, down to the step
        x0, x1 = hx - 0.01, hx + 0.1
        p.box(x0, x1, floor + 0.25, head - 0.1, a, b, CREAM)
        p.box(x1, x1 + 0.06, floor + 0.6, head - 0.25, a + 0.12, (a + b) / 2 - 0.05, glass)
        p.box(x1, x1 + 0.06, floor + 0.6, head - 0.25, (a + b) / 2 + 0.05, b - 0.12, glass)
    # the front: split windscreen, destination blind, headlamps, grille, bumper
    for a, b in ((-1.5, -0.08), (0.08, 1.5)):
        p.box(a, b, sill + 0.12, head - 0.12, uz0 - 0.1, uz0, glass)
    p.box(-1.0, 1.0, head - 0.02, head + 0.42, uz0 - 0.12, uz0 + 0.5, CHARCOAL, front=GOLD)
    for x in (-1.3, 1.3):
        p.box(x - 0.24, x + 0.24, 1.45, 1.93, z0 - 0.1, z0, WHITE)
    p.box(-0.75, 0.75, 1.3, 2.0, z0 - 0.07, z0, CHARCOAL)
    p.box(-2.05, 2.05, floor, floor + 0.38, z0 - 0.14, z0 + 0.1, STONE, top=LAVENDER)
    # the rear: window, engine louvres, tail lamps, bumper
    p.box(-1.4, 1.4, sill + 0.2, head - 0.2, uz1, uz1 + 0.1, glass)
    p.box(-1.1, 1.1, 1.2, 2.05, z1, z1 + 0.07, CHARCOAL)
    for x in (-1.5, 1.5):
        p.box(x - 0.16, x + 0.16, 1.5, 1.9, z1, z1 + 0.1, GOLD)
    p.box(-2.05, 2.05, floor, floor + 0.38, z1 - 0.1, z1 + 0.14, STONE, top=LAVENDER)
    # two roof vents, so the cream roof is not one blank plane from the tycoon camera
    for z in (-2.2, 2.2):
        p.box(-0.5, 0.5, roof, roof + 0.14, z - 0.7, z + 0.7, STONE, top=LAVENDER)
    for sx in (-1, 1):
        for z in (-3.75, 3.6):
            wheel(p, sx * (hx + 0.04), 0.82 * math.cos(math.pi / 8), z, 0.82, 0.6)  # a flat on the road
    return p


PIECES = {
    "hydrant": make_hydrant,
    "bus-stop": make_bus_stop,
    "billboard-a": make_billboard_a,
    "billboard-b": make_billboard_b,
    "billboard-c": make_billboard_c,
    "neon-sign-a": make_neon_sign_a,
    "neon-sign-b": make_neon_sign_b,
    "neon-sign-c": make_neon_sign_c,
    "neon-arch": make_neon_arch,
    "bus": make_bus,
}

# The blueprint scale each piece is written for, where it is not STUDS_PER_UNIT.
PIECE_SCALE = {"bus": VEHICLE_SCALE}


# --- export -------------------------------------------------------------------------------------


def signed_volume(part: Part) -> float:
    """The volume the faces enclose, positive when they are wound outward. Every piece is a union
    of closed solids, so the sum does not depend on the origin; generate() refuses a piece that
    comes out negative, because Roblox culls back faces and an inside-out solid would vanish."""
    total = 0.0
    for idx, _ in part.faces:
        a = part.verts[idx[0]]
        for i in range(1, len(idx) - 1):
            b, c = part.verts[idx[i]], part.verts[idx[i + 1]]
            total += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0])
                      + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0
    return total


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
        volume = signed_volume(part)
        assert volume > 0, f"{name}: signed volume {volume:.3f}, faces wound inward"
        scale = PIECE_SCALE.get(name, STUDS_PER_UNIT)
        export(build_object(to_kit_units(part, scale), {}), out_dir)
        total += part.tris
        lo, hi = part.bounds()
        print(
            f"[{KIT}] {name}.glb: {part.tris} tris, "
            f"x[{lo[0]:.2f}, {hi[0]:.2f}] y[{lo[1]:.2f}, {hi[1]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}] "
            f"studs at scale {scale:g}, volume {volume:.2f}",
            flush=True,
        )
    print(f"[{KIT}] {len(PIECES)} pieces, {total} tris total -> {os.path.relpath(out_dir, REPO_ROOT)}", flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the boomtown-street-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)
    return generate(args.out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
