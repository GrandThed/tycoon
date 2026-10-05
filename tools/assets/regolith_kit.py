"""Raw regolith (Orbital Colony's wild land), the colony's building sites, the landing beacon and
the reveal gantry for the growing city (M12 wave 4), generated as a Kenney-style kit.

    py tools/assets/regolith_kit.py                  # the GLBs and the 16 blueprints, then the check
    py tools/assets/regolith_kit.py check            # the check alone: nothing is written
    py tools/assets/regolith_kit.py --only lander    # rebuild some GLBs (blueprints and check as usual)
    blender -b -P tools/assets/regolith_kit.py -- [the same arguments]

The geometry needs Blender's Python, so under the system `py` the script starts Blender on itself
and passes on this kit's lines and the exit status (1 when the check finds a problem). `BLENDER`
overrides the executable.

Writes one GLB per piece into assets/kenney3d/regolith-kit/Models/GLB format/, the folder
convention every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. The 16 blueprints under
tools/testfit/blueprints/_props/OrbitalColony/ are written from blueprints() below: never edit one
by hand, and never edit a clump at all (it is its quarter turned four times). Same pattern as
oldtown_kit.py, whose box, rod and decal helpers this file uses.

Why a custom kit (INTERFACES "M12 wave 4 -- Orbital Colony", docs/CITY_GROWTH.md 2.1):
- The wild land. Orbital's wild is the bare ground the colony spreads over: dust, old and fresh
  craters, boulder fields, a rover's tracks, survey beacons. space-kit has rocks and one crater but
  nothing flat: no dust, no apron, no track. Its rocks are 150 to 200 triangles each, so a plot
  covered in them would cost more than the colony. The rocks here are 13 to 47.
- Building sites. A colony site is deck plates going down on the regolith, cargo off a lander, the
  ribs and first panels of a pod, and a robot gantry placing the next panel. space-kit's open
  orange frames belong to the Launch Tower; nothing here reuses a landmark's piece.

**Units: 1 glTF unit = 1 stud** (blueprints use `"scale": 1.0`), like oldtown-kit and tube-kit.

**The clump contract** (INTERFACES "Fabric data" and "Wave 4.1"): a clump is four copies of one
quarter design turned 0, 90, 180 and 270 degrees about the clump origin. A quarter is authored in
the clump's frame with all of its content inside the local (+X, +Z) quadrant, x and z in 0 .. 6.5,
so a clump is 13 x 13. Unlike the old town, a regolith quarter is not a tile of ground: nothing in
it runs along its edges, its dust is a few lobed patches with the plot showing between and round
them, and every feature is whole inside the quarter, because a quarter also stands alone on a
single 7-stud cell (a planned tube line, the strip under the monorail). So the joins inside a
clump look like the gaps between any two patches of dust.

Every other piece has its origin at its bottom centre and its front on -Z; the lot-sized site
pieces (site-deck-*) are authored in the lot frame (origin at the lot centre on the ground, the
tube on -Z), so a blueprint places them at [0, 0, 0].

**Colours** are space-kit's own material factors read raw x 255 (orbital_kit.py explains why),
written as linear factors like orbital-kit and tube-kit, so palette.py decodes them back to these
bytes: regolith-kit must NOT join palette.SRGB_FACTOR_KITS. The rocks are the kit's three rock
colours. DUST, DUST_LIGHT and RUT are not kit colours: the kit has no ground tone at all, and its
rock salmon laid flat over half the plot would drown the white colony. They are the plot base
(56, 53, 60) mixed toward the kit's dark rock, so dust reads as the same rock, weathered and lying
in shadow. DECK is the contract's decking colour.

Art rules, matching the kits: flat shading, faceted solids, chunky toy proportions.

**Every face belongs to a solid.** Roblox culls back faces, so nothing is a lone sheet. A solid is
closed, or open only where it rests on the ground or on another solid. The one exception is a
ground decal (dust, an ejecta apron, a rut, a scorch mark): a top face only, lifted MIN_GAP above
what it lies on, where nothing can look at it from underneath.

**Two rules from Studio (lead, 2026-10-02), both checked here:**
- Any two parallel faces that face the same way and overlap stand at least 0.05 studs apart
  (MIN_GAP), and so does any flat face over the plot base. So the flat layers have fixed heights:
  dust 0.05, drift and aprons 0.10, ruts 0.15, crater floors 0.20.
- Nothing is thinner than 0.1 studs (MIN_MEMBER).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = "regolith-kit"
# The same default as tools/testfit/plotrender.py.
DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


def relaunch(argv: list[str]) -> int:
    """Run this script inside Blender and pass on its own lines and its exit status."""
    blender = os.environ.get("BLENDER", DEFAULT_BLENDER)
    command = [blender, "-b", "--python-exit-code", "1", "-P", os.path.abspath(__file__), "--", *argv]
    try:
        result = subprocess.run(command, capture_output=True, text=True)
    except FileNotFoundError:
        print(f"[{KIT}] Blender not found at {blender}: set BLENDER to its executable", flush=True)
        return 2
    ours = [line for line in result.stdout.splitlines() if line.startswith(f"[{KIT}]")]
    print("\n".join(ours), flush=True)
    if result.returncode != 0 and not any("PROBLEM" in line for line in ours):
        # Not a failed check: a crash. Show what Blender said.
        print(result.stdout[-4000:], flush=True)
        print(result.stderr[-4000:], file=sys.stderr, flush=True)
    return result.returncode


try:
    import bpy
except ImportError:
    if __name__ == "__main__":
        sys.exit(relaunch(sys.argv[1:]))
    raise

sys.path.insert(0, HERE)
from garden_kit import REPO_ROOT, Part, build_object, export  # noqa: E402
from oldtown_kit import block, decal, rod, signed_volume  # noqa: E402
from village_extras_kit import face_out, lathe, place  # noqa: E402

DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

Rgb = tuple[int, int, int]
Vec = tuple[float, float, float]

# --- palette --------------------------------------------------------------------------------------
# space-kit's material factors, raw x 255.
ROCK = (232, 132, 99)  # "rock"
ROCK_DARK = (178, 95, 67)  # "rockDark"
ROCK_LIGHT = (250, 148, 114)  # "rockTrack": the lit tops of the kit's rocks and meteors
HULL = (215, 222, 232)  # "metal"
PANEL = (172, 181, 197)  # "metalDark"
TRIM = (255, 160, 52)  # "metalRed": the orange trim
LIT = (255, 225, 140)  # orbital-kit's lit strip
DECK = (96, 98, 108)  # the decking colour (`road.tiles.blocks`, INTERFACES "Wave 4.1")
# Not kit colours (see the module docstring): the plot base mixed 40% and 72% toward ROCK_DARK,
# and 16% for ground a wheel has pressed bare.
DUST = (105, 70, 63)
DUST_LIGHT = (144, 83, 65)
RUT = (76, 60, 61)

MIN_GAP = 0.05  # parallel faces that overlap stand at least this far apart
MIN_MEMBER = 0.1  # nothing is thinner
DUST_Y = MIN_GAP  # the flat layers, each MIN_GAP above the one it may lie on
DRIFT_Y = 2 * MIN_GAP
RUT_Y = 3 * MIN_GAP
FLOOR_Y = 4 * MIN_GAP

EDGE = 6.5  # a quarter's outer edges, x = EDGE and z = EDGE; its inner edges are the clump axes
WILD_MAX = 3.0  # INTERFACES "Wave 4.1": wild is at most this tall everywhere

THIN: list[str] = []  # members under MIN_MEMBER, noted as they are built; check() reports them


def log(msg: str) -> None:
    print(f"[{KIT}] {msg}", flush=True)


# --- geometry helpers (glTF space, studs) ---------------------------------------------------------


def newell(points) -> Vec:
    n = [0.0, 0.0, 0.0]
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        n[0] += (a[1] - b[1]) * (a[2] + b[2])
        n[1] += (a[2] - b[2]) * (a[0] + b[0])
        n[2] += (a[0] - b[0]) * (a[1] + b[1])
    return (n[0], n[1], n[2])


def box(p: Part, x0, x1, y0, y1, z0, z1, colour: Rgb, skip=("bottom",), **paint) -> None:
    """oldtown-kit's block, noting any side under MIN_MEMBER."""
    if min(x1 - x0, y1 - y0, z1 - z0) < MIN_MEMBER - 1e-9:
        THIN.append(f"{p.name}: a box {x1 - x0:.3f} x {y1 - y0:.3f} x {z1 - z0:.3f}")
    block(p, x0, x1, y0, y1, z0, z1, colour, skip=skip, **paint)


def bar(p: Part, a: Vec, b: Vec, w: float, colour: Rgb, sides: int = 4, caps: bool = False) -> None:
    """oldtown-kit's rod, noting a width under MIN_MEMBER."""
    if w < MIN_MEMBER - 1e-9:
        THIN.append(f"{p.name}: a bar {w:.3f} across")
    rod(p, a, b, w, colour, sides=sides, caps=caps)


def lobed(seed: int, cx: float, cz: float, rx: float, rz: float, points: int = 9, wobble: float = 0.22,
          turn: float = 0.0):
    """The outline of a patch of dust: an ellipse turned `turn` degrees whose vertices wander in
    angle and radius. Star-shaped about (cx, cz)."""
    rng = random.Random(seed)
    c, s = math.cos(math.radians(turn)), math.sin(math.radians(turn))
    out = []
    for k in range(points):
        a = 2 * math.pi * (k + rng.uniform(-0.25, 0.25)) / points
        j = 1.0 + rng.uniform(-wobble, wobble)
        x, z = rx * j * math.cos(a), rz * j * math.sin(a)
        out.append((cx + x * c - z * s, cz + x * s + z * c))
    return out


def rayed(seed: int, cx: float, cz: float, r_in: float, r_out: float, points: int = 10):
    """The outline of an ejecta apron or a scorch mark: rays out to about r_out between notches at
    about r_in. Star-shaped about (cx, cz)."""
    rng = random.Random(seed)
    phase = rng.uniform(0.0, 2 * math.pi)
    out = []
    for k in range(points):
        a = phase + 2 * math.pi * (k + rng.uniform(-0.2, 0.2)) / points
        r = r_out * rng.uniform(0.78, 1.0) if k % 2 == 0 else r_in * rng.uniform(0.95, 1.15)
        out.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return out


def crater(p: Part, cx: float, cz: float, r_out: float, r_crest: float, r_floor: float, height: float,
           floor_y: float, seed: int, seg: int = 7, crest_w: float = 0.0,
           tones: tuple[Rgb, Rgb, Rgb] = (ROCK, ROCK_DARK, DUST)) -> None:
    """A crater that sits on flat ground: a raised rim round a floor above the plot, never a hole
    in it. The outer slope climbs from the ground at r_out to the crest at r_crest, the inner wall
    drops to the floor at r_floor; with `crest_w` the crest is a flat band that wide in the lit
    rock colour. `tones` are the slope, the wall and the floor: fresh rock by default, dust tones
    for an old crater the dust has half buried. Every vertex of the ring wanders in angle, radius
    and height, so no two craters are the same and a turned copy catches the light differently."""
    slope, wall, floor = tones
    rng = random.Random(seed)
    phase = rng.uniform(0.0, 2 * math.pi)
    ring = [(phase + 2 * math.pi * (k + rng.uniform(-0.18, 0.18)) / seg, 1.0 + rng.uniform(-0.12, 0.12),
             height * (1.0 + rng.uniform(-0.2, 0.2))) for k in range(seg)]

    def pt(k: int, r: float, y: float | None = None) -> Vec:
        a, j, h = ring[k % seg]
        return (cx + r * j * math.cos(a), h if y is None else y, cz + r * j * math.sin(a))

    r_in = r_crest - crest_w
    for k in range(seg):
        n = k + 1
        a, b = pt(k, 1.0, 0.0), pt(n, 1.0, 0.0)
        out = (a[0] + b[0] - 2 * cx, 0.0, a[2] + b[2] - 2 * cz)
        lift = math.hypot(out[0], out[2])
        face_out(p, [pt(k, r_out, 0.0), pt(n, r_out, 0.0), pt(n, r_crest), pt(k, r_crest)], slope,
                 (out[0], lift, out[2]))
        if crest_w > 0:
            face_out(p, [pt(k, r_crest), pt(n, r_crest), pt(n, r_in), pt(k, r_in)], ROCK_LIGHT, (0.0, 1.0, 0.0))
        face_out(p, [pt(k, r_in), pt(n, r_in), pt(n, r_floor, floor_y), pt(k, r_floor, floor_y)], wall,
                 (-out[0], lift, -out[2]))
    face_out(p, [pt(k, r_floor, floor_y) for k in range(seg)], floor, (0.0, 1.0, 0.0))


# A rock's profile: (radius, height) as shares of its size, from the ground up.
BOULDER = ((1.0, 0.0), (1.07, 0.42), (0.62, 1.0))
TALL_BOULDER = ((1.0, 0.0), (1.07, 0.4), (0.86, 0.8), (0.5, 1.0))
STONE = ((1.0, 0.0), (1.12, 0.22), (1.0, 0.7), (0.68, 1.0))
CHUNK = ((1.0, 0.0), (0.66, 1.0))


def rock(name: str, size: Vec, seed: int, seg: int = 6, profile=BOULDER, jitter: float = 0.16,
         lean: tuple[float, float] = (0.0, 0.0), slant: float = 0.0) -> Part:
    """A faceted boulder standing on the ground, about 2 size[0] x 2 size[2] studs and size[1]
    tall: rings of `seg` corners up `profile`, every corner wandering in radius and height, under a
    flat broken top, with no underside. It bulges above its foot and has a face for a top, like
    space-kit's meteors (a first cut, a jittered ball, came out as a cone). Painted by facing as
    the kit paints its rocks: the facets turned to the sky in the lit colour, the undercut ones
    dark. `lean` shears it (studs of x and z per stud of height) and `slant` tips its top (one side
    that share taller, the other that share shorter) into a standing stone with a broken head."""
    rng = random.Random(seed)
    rx, h, rz = size
    phase = rng.uniform(0.0, 2 * math.pi)
    spokes = [phase + 2 * math.pi * (k + rng.uniform(-0.2, 0.2)) / seg for k in range(seg)]
    rings = []
    for r, t in profile:
        ring = []
        # the top wanders less than the waist: a top as uneven as its sides grew horns
        wander = 0.0 if t <= 0.0 else 0.05 if t >= 1.0 else 0.12
        for a in spokes:
            j = 1.0 + rng.uniform(-jitter, jitter)
            y = h * t * (1.0 + rng.uniform(-wander, wander)) * (1.0 + slant * t * math.cos(a - phase))
            ring.append((rx * r * j * math.cos(a) + lean[0] * y, y, rz * r * j * math.sin(a) + lean[1] * y))
        rings.append(ring)
    raw = Part(name)
    for lo, hi in zip(rings, rings[1:]):
        for k in range(seg):
            n = (k + 1) % seg
            out = (lo[k][0] + lo[n][0] + hi[k][0] + hi[n][0], 0.0, lo[k][2] + lo[n][2] + hi[k][2] + hi[n][2])
            face_out(raw, [lo[k], lo[n], hi[n], hi[k]], ROCK, out)
    face_out(raw, rings[-1], ROCK, (0.0, 1.0, 0.0))
    p = Part(name)
    for idx, _ in raw.faces:
        pts = [raw.verts[i] for i in idx]
        n = newell(pts)
        up = n[1] / (math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1.0)
        p.face(pts, ROCK_LIGHT if up > 0.5 else ROCK_DARK if up < -0.05 else ROCK)
    return p


def pebble(p: Part, x: float, z: float, r: float, seed: int) -> None:
    """A stone too small to model, about 2 r across: four triangles to a low point set well off
    its middle, so it reads as a chip of rock lying flat and never as a spike."""
    rng = random.Random(seed)
    phase = rng.uniform(0.0, 2 * math.pi)
    base = []
    for k in range(4):
        a = phase + 2 * math.pi * k / 4
        j = rng.uniform(0.75, 1.2)
        base.append((x + r * j * math.cos(a), 0.0, z + r * j * math.sin(a)))
    lean = rng.uniform(0.0, 2 * math.pi)
    apex = (x + 0.45 * r * math.cos(lean), r * rng.uniform(0.5, 0.65), z + 0.45 * r * math.sin(lean))
    for k in range(4):
        a, b = base[k], base[(k + 1) % 4]
        face_out(p, [a, b, apex], ROCK_LIGHT if k % 2 == 0 else ROCK,
                 ((a[0] + b[0]) / 2 - x, 0.6 * r, (a[2] + b[2]) / 2 - z))


def outcrop(name: str, w: float, d: float, low: float, high: float, seed: int) -> Part:
    """A slab of bedrock tilted out of the dust, w x d studs: its lip `low` above the ground on -Z,
    its broken back edge `high` up on +Z. Ten triangles."""
    rng = random.Random(seed)
    p = Part(name)

    def j(v: float, by: float = 0.12) -> float:
        return v * (1.0 + rng.uniform(-by, by))

    hx, hz = w / 2, d / 2
    foot = [(-j(hx), 0.0, -j(hz)), (j(hx), 0.0, -j(hz)), (j(hx), 0.0, j(hz)), (-j(hx), 0.0, j(hz))]
    inset = 0.82
    top = [(foot[0][0] * inset, j(low), foot[0][2] * inset), (foot[1][0] * inset, j(low), foot[1][2] * inset),
           (foot[2][0] * inset, j(high), foot[2][2] * 0.9), (foot[3][0] * inset, j(high, 0.25), foot[3][2] * 0.9)]
    face_out(p, top, ROCK_LIGHT, (0.0, 1.0, 0.0))
    for k, colour in enumerate((ROCK, ROCK, ROCK_DARK, ROCK)):
        n = (k + 1) % 4
        mid = ((foot[k][0] + foot[n][0]) / 2, 0.0, (foot[k][2] + foot[n][2]) / 2)
        face_out(p, [foot[k], foot[n], top[n], top[k]], colour, mid)
    return p


def ruts(p: Part, path, gauge: float, width: float, y: float, colour: Rgb) -> None:
    """A rover's two wheel tracks along a centreline [(x, z)], `gauge` apart and `width` wide, as
    decals mitred at the bends."""
    if width < MIN_MEMBER - 1e-9:
        THIN.append(f"{p.name}: a rut {width:.3f} wide")
    normals = []
    for i in range(len(path)):
        a, b = path[max(i - 1, 0)], path[min(i + 1, len(path) - 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dz)
        normals.append((-dz / length, dx / length))
    for side in (-1, 1):
        for i in range(len(path) - 1):
            quad = []
            for k, off in ((i, -width / 2), (i + 1, -width / 2), (i + 1, width / 2), (i, width / 2)):
                o = side * gauge / 2 + off
                quad.append((path[k][0] + normals[k][0] * o, path[k][1] + normals[k][1] * o))
            decal(p, quad, y, colour)


def drum(p: Part, profile, colours, seg: int = 8, at: Vec = (0.0, 0.0, 0.0), phase: float = 0.0,
         bottom: bool = False) -> None:
    """village-extras' lathe without the cap a standing solid rests on."""
    lathe(p, profile, colours, seg=seg, at=at, phase=phase)
    if bottom or profile[0][0] <= 0:
        return
    top = None
    if profile[-1][0] > 0:
        top = pop_face(p)
    pop_face(p)
    if top is not None:
        p.face(*top)


def pop_face(p: Part):
    """Takes the last face added and its vertices back out (each face owns the vertices it added)."""
    idx, colour = p.faces.pop()
    points = [p.verts[i] for i in idx]
    del p.verts[idx[0]:]
    return points, colour


def hoop(p: Part, r_in: float, r_out: float, y0: float, y1: float, colour: Rgb, seg: int = 8,
         phase: float = 0.0) -> None:
    """A level ring of square section about the vertical axis: `seg` sides, r_in and r_out to its
    corners, closed all round."""
    def pt(r: float, a: float, y: float) -> Vec:
        return (r * math.cos(a), y, r * math.sin(a))

    for k in range(seg):
        a0, a1 = phase + 2 * math.pi * k / seg, phase + 2 * math.pi * (k + 1) / seg
        out = (math.cos((a0 + a1) / 2), 0.0, math.sin((a0 + a1) / 2))
        face_out(p, [pt(r_out, a0, y0), pt(r_out, a1, y0), pt(r_out, a1, y1), pt(r_out, a0, y1)], colour, out)
        face_out(p, [pt(r_in, a0, y0), pt(r_in, a1, y0), pt(r_in, a1, y1), pt(r_in, a0, y1)], colour,
                 (-out[0], 0.0, -out[2]))
        for y, up in ((y1, 1.0), (y0, -1.0)):
            face_out(p, [pt(r_in, a0, y), pt(r_in, a1, y), pt(r_out, a1, y), pt(r_out, a0, y)], colour, (0.0, up, 0.0))


# --- the wild: three quarters of regolith ---------------------------------------------------------
#
# A crater in the wild is ground, not an object: the fresh rock colours are kept for the boulders
# and for the one fresh crater a plan places as a single (a field of bright rims read as rows of
# rings, not as terrain). WORN is a crater as old as the dust round it, its rim the kit's dark rock;
# BURIED one the dust has half filled.
WORN = (ROCK_DARK, DUST_LIGHT, DUST)
BURIED = (DUST_LIGHT, DUST, DUST_LIGHT)

# Each ground piece holds everything of its quarter that lies flat or is too small to be a piece:
# the dust, the apron, the ruts, the craters and the pebbles. The boulders and slabs are pieces of
# their own, placed by the blueprint. A (impact): a fresh crater with its apron, a pit, one
# boulder. B (boulder field): rocks of three sizes on a drift of dust. C (flats): a wide patch of
# dust a rover has crossed, an old filled crater, a slab of bedrock.


def make_ground_a() -> Part:
    p = Part("ground-a")
    decal(p, lobed(101, 3.85, 3.0, 2.3, 2.05, points=9, wobble=0.18, turn=20), DUST_Y, DUST)
    decal(p, rayed(103, 3.95, 2.85, 1.8, 2.45, points=10), DRIFT_Y, DUST_LIGHT)
    crater(p, 3.95, 2.85, 1.5, 1.08, 0.7, 0.5, FLOOR_Y, seed=105, seg=7, tones=WORN)
    decal(p, lobed(107, 1.4, 5.25, 1.05, 0.9, points=7, wobble=0.16), DUST_Y, DUST)
    crater(p, 1.35, 5.3, 0.62, 0.43, 0.27, 0.26, 2 * MIN_GAP + 0.02, seed=109, seg=5, tones=WORN)
    for k, (x, z, r) in enumerate(((0.75, 3.2, 0.2), (2.2, 0.6, 0.26), (5.75, 5.6, 0.22))):
        pebble(p, x, z, r, 111 + k)
    return p


def make_ground_b() -> Part:
    p = Part("ground-b")
    decal(p, lobed(201, 3.1, 3.5, 2.75, 1.7, points=9, wobble=0.2, turn=35), DUST_Y, DUST)
    decal(p, lobed(203, 3.75, 4.25, 1.3, 0.75, points=7, wobble=0.2, turn=35), DRIFT_Y, DUST_LIGHT)
    decal(p, lobed(205, 5.2, 1.3, 0.9, 0.75, points=6, wobble=0.18), DUST_Y, DUST)
    for k, (x, z, r) in enumerate(((0.7, 1.2, 0.24), (3.7, 1.45, 0.2), (5.9, 3.3, 0.22), (0.9, 5.3, 0.26),
                                   (2.7, 5.9, 0.18))):
        pebble(p, x, z, r, 211 + k)
    return p


def make_ground_c() -> Part:
    p = Part("ground-c")
    decal(p, lobed(301, 3.0, 3.45, 2.6, 2.3, points=10, wobble=0.2, turn=-15), DUST_Y, DUST)
    decal(p, lobed(303, 1.75, 4.4, 1.05, 0.8, points=7, wobble=0.2, turn=40), DRIFT_Y, DUST_LIGHT)
    ruts(p, [(1.1, 1.85), (2.3, 2.75), (3.6, 3.15), (4.9, 4.15)], 0.95, 0.24, RUT_Y, RUT)
    crater(p, 5.05, 1.5, 1.2, 0.92, 0.7, 0.22, 2 * MIN_GAP + 0.02, seed=305, seg=7, tones=BURIED)
    for k, (x, z, r) in enumerate(((0.6, 0.7, 0.22), (5.95, 3.7, 0.2), (4.4, 5.9, 0.24))):
        pebble(p, x, z, r, 311 + k)
    return p


def make_boulder_large() -> Part:
    """1.9 x 1.7 studs, 1.5 tall."""
    return rock("boulder-large", (0.9, 1.45, 0.78), 401, seg=7, profile=TALL_BOULDER)


def make_boulder_medium() -> Part:
    """1.4 x 1.2 studs, 0.95 tall."""
    return rock("boulder-medium", (0.66, 0.92, 0.56), 403, seg=6)


def make_boulder_small() -> Part:
    """0.75 x 0.65 studs, 0.55 tall."""
    return rock("boulder-small", (0.42, 0.52, 0.36), 405, seg=5, profile=CHUNK)


def make_rock_slab() -> Part:
    """1.8 x 1.25 studs, 0.85 tall at its back edge."""
    return outcrop("rock-slab", 1.7, 1.2, 0.14, 0.7, 407)


# --- the wild: singles ---------------------------------------------------------------------------


def make_boulder_pile() -> Part:
    """RegolithBoulder: a standing stone 2.7 tall with a broken head, leaning over two smaller
    rocks, inside 2 x 2."""
    p = rock("boulder-pile", (0.6, 2.35, 0.44), 421, seg=6, profile=STONE, jitter=0.12, lean=(0.07, -0.03),
             slant=0.16)
    place(p, rock("foot", (0.36, 0.62, 0.32), 423, seg=5, profile=CHUNK), 30.0, (0.52, 0.0, 0.52))
    place(p, rock("foot", (0.3, 0.4, 0.26), 425, seg=5, profile=CHUNK), 110.0, (-0.62, 0.0, -0.5))
    return p


def make_crater_fresh() -> Part:
    """RegolithCrater: a fresh crater 2.8 studs across, its crest a lit band 0.42 up round a dark
    floor, and three blocks of ejecta in the corners, inside 3 x 3."""
    p = Part("crater-fresh")
    crater(p, 0.0, 0.0, 1.3, 0.94, 0.6, 0.42, FLOOR_Y, seed=433, seg=8, crest_w=0.16)
    for k, (x, z, r) in enumerate(((1.22, 1.2, 0.2), (-1.2, 1.24, 0.16), (-1.24, -1.18, 0.2))):
        pebble(p, x, z, r, 435 + k)
    return p


def make_survey_beacon() -> Part:
    """SurveyBeacon: a surveyor's tripod 2.45 tall inside 1 x 1: three orange legs, a white
    instrument head, a mast with an orange tag and a lit lamp."""
    p = Part("survey-beacon")
    apex = 1.45
    for k in range(3):
        a = math.radians(90 + 120 * k)
        # from 0.03 up: the leg's slanted end then stops on the ground, not under it
        bar(p, (0.38 * math.cos(a), 0.03, 0.38 * math.sin(a)), (0.03 * math.cos(a), apex, 0.03 * math.sin(a)), 0.11,
            TRIM, sides=3)
    box(p, -0.17, 0.17, apex - 0.1, apex + 0.2, -0.15, 0.15, HULL, skip=(), bottom=PANEL)
    box(p, -0.06, 0.06, apex + 0.2, 2.2, -0.06, 0.06, PANEL, skip=("bottom", "top"))
    box(p, 0.06, 0.44, 1.82, 2.1, -0.05, 0.05, TRIM, skip=("left",))
    box(p, -0.11, 0.11, 2.2, 2.45, -0.11, 0.11, LIT, skip=())
    return p


# --- building sites -------------------------------------------------------------------------------
#
# A colony site is the deck going down on the regolith, row by row from the tube: the laid rows in
# the decking colour with an orange strip on the working edge, bare dust behind them, the ribs and
# first wall panels of a pod on the new deck, plates and cargo waiting. The gantry variants add a
# robot gantry holding the next panel; the medium site has the lander that brought the cargo.
# Everything stays inside its lot.

LOTS = {"narrow": (4.0, 8.0), "small": (6.0, 6.0), "medium": (8.0, 12.0)}
LOT_INSET = 0.05  # what a site keeps off its lot's edges
DECK_TOP = 0.12
ROW = 2.0  # a row of deck plates, with the seam: plates are ROW - SEAM deep
SEAM = 0.1
SITE_MAX = 3.4  # a site without a gantry stays under the pods' heightFloor
GANTRY_MAX = 8.0


def site_deck(name: str, lot: str, rows: int, last: float, seed: int, dust) -> Part:
    """The ground of a site in the lot frame: `rows` whole rows of deck plates from the tube back,
    then one more laid only over the first `last` of the lot's width (from -X), the orange strip on
    the working edge, and patches of dust `dust` = [(cx, cz, rx, rz)] on the ground still bare."""
    p = Part(name)
    w, d = LOTS[lot]
    hx, hz = w / 2 - LOT_INSET, d / 2 - LOT_INSET
    for k in range(rows + 1):
        z0 = -hz + ROW * k
        x1 = hx if k < rows else -hx + last * 2 * hx
        box(p, -hx, x1, 0.0, DECK_TOP, z0, z0 + ROW - SEAM, DECK)
    # the working edge: along the back of the last whole row beyond the part row, and along the
    # back of the part row
    cut = -hx + last * 2 * hx
    whole = -hz + ROW * rows - SEAM
    for x0, x1, z1 in ((cut + 0.1, hx - 0.1, whole), (-hx + 0.1, cut - 0.1, whole + ROW)):
        decal(p, [(x0, z1 - 0.3), (x1, z1 - 0.3), (x1, z1 - 0.08), (x0, z1 - 0.08)], DECK_TOP + MIN_GAP, TRIM)
    for k, (cx, cz, rx, rz) in enumerate(dust):
        decal(p, lobed(seed + k, cx, cz, rx, rz, points=7, wobble=0.14), DUST_Y, DUST)
    return p


def make_site_deck_narrow() -> Part:
    return site_deck("site-deck-narrow", "narrow", 2, 0.5, 501, [(0.95, 1.0, 0.85, 0.8), (-0.1, 3.0, 1.6, 0.8)])


def make_site_deck_small() -> Part:
    return site_deck("site-deck-small", "small", 1, 0.62, 511, [(1.95, 0.0, 0.8, 0.85), (0.2, 1.95, 2.4, 0.85)])


def make_site_deck_medium() -> Part:
    return site_deck("site-deck-medium", "medium", 3, 0.5, 521,
                     [(2.0, 1.0, 1.7, 0.85), (-2.0, 3.9, 1.6, 1.6)])


def make_blast_mark() -> Part:
    """The scorch a lander's engine leaves: a rayed patch of paler dust about 3.5 studs across,
    lying over the site's dust."""
    p = Part("blast-mark")
    decal(p, rayed(531, 0.0, 0.0, 1.3, 1.95, points=12), DRIFT_Y, DUST_LIGHT)
    return p


def make_plate_stack() -> Part:
    """Deck plates waiting to be laid: three 1.5-stud plates stacked a little askew, 0.36 tall,
    with two orange straps painted over the top one."""
    p = Part("plate-stack")
    t = 0.12
    for k, (dx, dz) in enumerate(((0.0, 0.0), (0.07, -0.05), (-0.04, 0.06))):
        box(p, -0.75 + dx, 0.75 + dx, t * k, t * (k + 1), -0.75 + dz, 0.75 + dz, DECK, top=PANEL if k == 2 else DECK)
    for x in (-0.42, 0.34):
        decal(p, [(x, -0.69), (x + 0.16, -0.69), (x + 0.16, 0.81), (x, 0.81)], 3 * t + MIN_GAP, TRIM)
    return p


def crate(name: str, w: float, h: float, d: float) -> Part:
    """A cargo crate: a white hull box under an orange lid that stands a little proud."""
    p = Part(name)
    lid = 0.14
    box(p, -w / 2, w / 2, 0.0, h - lid, -d / 2, d / 2, HULL, skip=("bottom", "top"), back=PANEL, left=PANEL)
    box(p, -w / 2 - 0.03, w / 2 + 0.03, h - lid, h, -d / 2 - 0.03, d / 2 + 0.03, TRIM)
    return p


def make_crate() -> Part:
    """0.96 x 0.96 studs, 0.8 tall."""
    return crate("crate", 0.9, 0.8, 0.9)


def make_crate_long() -> Part:
    """1.66 x 0.76 studs, 0.6 tall."""
    return crate("crate-long", 1.6, 0.6, 0.7)


def pod_frame(name: str, radius: float, rib_top: float, wall_top: float) -> Part:
    """A pod going up, its airlock side on -Z: the eight-sided white floor, `radius` to its
    corners, six orange ribs at its corners (the two on the airlock side not yet set) and the first
    three wall panels up on the far side."""
    p = Part(name)
    floor_y = 0.28
    phase = math.radians(22.5)
    drum(p, [(radius, 0.0), (radius, floor_y)], [HULL, PANEL], seg=8, phase=phase)
    corners = [(math.cos(phase + math.pi / 4 * k), math.sin(phase + math.pi / 4 * k)) for k in range(8)]
    for k, (c, s) in enumerate(corners):
        if k in (5, 6):  # the two corners either side of -Z: the airlock's opening
            continue
        x, z = (radius - 0.12) * c, (radius - 0.12) * s
        box(p, x - 0.09, x + 0.09, floor_y, rib_top, z - 0.09, z + 0.09, TRIM)
    for k in (0, 1, 2):  # the three flats round +Z
        (c0, s0), (c1, s1) = corners[k], corners[k + 1]
        ro, ri = radius - 0.2, radius - 0.34
        p.hexa([(ri * c0, floor_y, ri * s0), (ro * c0, floor_y, ro * s0), (ro * c1, floor_y, ro * s1),
                (ri * c1, floor_y, ri * s1), (ri * c0, wall_top, ri * s0), (ro * c0, wall_top, ro * s0),
                (ro * c1, wall_top, ro * s1), (ri * c1, wall_top, ri * s1)], HULL, left=PANEL, top=PANEL)
        pop_face(p)  # hexa adds the underside last: the panel stands on the floor
    return p


def make_pod_frame() -> Part:
    """The narrow and small sites' pod: 2.7 studs across, 1.95 tall."""
    return pod_frame("pod-frame", 1.45, 1.95, 1.7)


def make_pod_frame_large() -> Part:
    """The medium site's pod: 4.1 studs across, 2.6 tall."""
    return pod_frame("pod-frame-large", 2.2, 2.6, 2.3)


def make_work_light() -> Part:
    """A site light, 1.8 studs tall: an orange post on a grey foot with a lit head."""
    p = Part("work-light")
    box(p, -0.16, 0.16, 0.0, 0.14, -0.16, 0.16, PANEL)
    box(p, -0.07, 0.07, 0.14, 1.5, -0.07, 0.07, TRIM, skip=("bottom", "top"))
    box(p, -0.15, 0.15, 1.5, 1.8, -0.15, 0.15, LIT, skip=(), bottom=PANEL, top=PANEL)
    return p


GANTRY_HALF = 1.65  # the gantry's leg centres
GANTRY_TOP = 7.0  # the top of its beam


def make_robot_gantry() -> Part:
    """A robot gantry, 3.8 studs wide, 0.7 deep at its feet and 7.5 tall, its arm reaching 2.5
    toward -Z: two orange legs on grey feet, the top beam with knee braces, a white trolley under
    the beam, and a two-jointed arm holding a hull panel out in front; a lit warning lamp on a
    stalk over one leg."""
    p = Part("robot-gantry")
    e, top = GANTRY_HALF, GANTRY_TOP
    for sx in (-1, 1):
        x = sx * e
        box(p, x - 0.25, x + 0.25, 0.0, 0.2, -0.35, 0.35, PANEL)
        box(p, x - 0.15, x + 0.15, 0.2, top - 0.36, -0.15, 0.15, TRIM, skip=("bottom", "top"))
        bar(p, (x, top - 1.5, 0.0), (sx * (e - 1.0), top - 0.2, 0.0), 0.16, TRIM)
    box(p, -e - 0.15, e + 0.15, top - 0.36, top, -0.2, 0.2, TRIM, skip=())
    # trolley, shoulder, upper arm, elbow, forearm, wrist and the panel it holds
    tx = 0.35
    box(p, tx - 0.32, tx + 0.32, top - 0.7, top - 0.36, -0.3, 0.3, HULL, skip=("top",), bottom=PANEL)
    shoulder, elbow, wrist = (tx, top - 0.86, 0.0), (tx, top - 2.2, -1.5), (tx, top - 3.5, -2.3)
    # The joints stand MIN_GAP or more proud of the arms on every side, and the forearm is that
    # much slimmer than the upper arm: their side faces are parallel where they cross.
    box(p, tx - 0.19, tx + 0.19, top - 1.08, top - 0.7, -0.19, 0.19, PANEL, skip=("top",))
    bar(p, shoulder, elbow, 0.26, HULL)
    box(p, tx - 0.19, tx + 0.19, elbow[1] - 0.19, elbow[1] + 0.19, elbow[2] - 0.19, elbow[2] + 0.19, PANEL, skip=())
    bar(p, elbow, wrist, 0.16, HULL)
    box(p, tx - 0.3, tx + 0.3, wrist[1] - 0.26, wrist[1] + 0.1, wrist[2] - 0.14, wrist[2] + 0.14, TRIM, skip=())
    box(p, tx - 0.6, tx + 0.6, wrist[1] - 1.2, wrist[1] - 0.26, wrist[2] - 0.07, wrist[2] + 0.07, HULL,
        skip=(), back=PANEL)
    # warning lamp
    box(p, -e - 0.06, -e + 0.06, top, top + 0.26, -0.06, 0.06, PANEL, skip=("bottom", "top"))
    box(p, -e - 0.13, -e + 0.13, top + 0.26, top + 0.5, -0.13, 0.13, LIT, skip=())
    return p


def make_lander() -> Part:
    """A small cargo lander, 2.3 studs square over its feet and 2.6 tall: an eight-sided white body
    with an orange skirt on four splayed orange legs with grey pads, the engine bell under it, a
    cargo box and a mast on its deck."""
    p = Part("lander")
    phase = math.radians(22.5)
    drum(p, [(0.56, 0.72), (0.86, 0.98), (0.86, 1.5), (0.6, 1.74)], [TRIM, HULL, PANEL, HULL], seg=8, phase=phase,
         bottom=True)
    drum(p, [(0.36, 0.3), (0.2, 0.72)], [PANEL, PANEL], seg=6, bottom=True)
    pop_face(p)  # the bell's top is inside the body
    for k in range(4):
        a = math.radians(45 + 90 * k)
        c, s = math.cos(a), math.sin(a)
        bar(p, (0.62 * c, 1.14, 0.62 * s), (1.36 * c, 0.1, 1.36 * s), 0.13, TRIM, sides=3)
        # the pads stand MIN_GAP clear of the scorch mark they land on
        box(p, 1.36 * c - 0.19, 1.36 * c + 0.19, 0.0, DRIFT_Y + MIN_GAP + 0.01, 1.36 * s - 0.19, 1.36 * s + 0.19, PANEL)
    box(p, -0.4, 0.1, 1.74, 2.06, -0.3, 0.2, HULL, top=TRIM)
    box(p, 0.24, 0.36, 1.74, 2.42, 0.1, 0.22, PANEL, skip=("bottom", "top"))
    box(p, 0.19, 0.41, 2.42, 2.6, 0.05, 0.27, LIT, skip=())
    return p


# --- the next-pad marker and the landmark reveal -------------------------------------------------


BEACON_TOP = 4.5


def make_landing_beacon() -> Part:
    """LotBeacon, the next-pad marker: a landing beacon 1.9 studs across and 4.5 tall, the same
    from every side: an eight-sided foot, a white mast with two orange bands, and its head, a level
    ring of light 1.9 across on four orange spokes round a lit lamp under an orange cap. The ring
    is what the tycoon camera sees: a halo over the next pad, lying flat to a view from above. (The
    first beacon, 2.7 tall with a lamp on a crossbar, read as one more of the sites' work lights.)"""
    p = Part("landing-beacon")
    phase = math.radians(22.5)
    corner = 1.0 / math.cos(phase)  # an octagon's corner radius over its flat radius
    drum(p, [(0.5, 0.0), (0.5, 0.14), (0.3, 0.24)], [PANEL, HULL], seg=8, phase=phase)
    mast_top, head_top = 3.42, 3.76
    box(p, -0.12, 0.12, 0.2, mast_top, -0.12, 0.12, HULL, skip=("bottom", "top"))
    for y in (1.1, 2.2):
        box(p, -0.17, 0.17, y, y + 0.3, -0.17, 0.17, TRIM, skip=())
    # the head: a hub on the mast, four spokes, the ring of light, the lamp and its cap. The spokes
    # stand MIN_GAP or more inside the hub's and the ring's top and bottom.
    drum(p, [(0.36, mast_top), (0.36, head_top)], [TRIM, TRIM], seg=8, phase=phase, bottom=True)
    for turn in (0, 90, 180, 270):
        spoke = Part("spoke")
        box(spoke, 0.3, 0.84, 3.53, 3.65, -0.07, 0.07, TRIM, skip=("left", "right"))
        place(p, spoke, turn)
    hoop(p, 0.76 * corner, 0.95 * corner, 3.46, 3.72, LIT, seg=8, phase=phase)
    drum(p, [(0.25, head_top), (0.25, 4.2)], [LIT, LIT], seg=8, phase=phase)
    pop_face(p)  # the lamp's top is under the cap
    drum(p, [(0.33, 4.2), (0.33, 4.3), (0.0, BEACON_TOP)], [TRIM, TRIM], seg=8, phase=phase, bottom=True)
    return p


RING_E = 4.755  # the reveal ring's post centres: wholly outside a 9 x 9 slot
RING_POST = 0.18  # half a post
RING_H = 8.0  # to the top of its lamps
# What INTERFACES "M12 contracts" gives a reveal frame, as Metropolis's has it: no nearer the slot's
# centre than RING_NEAR, no farther than RING_FAR, no taller than REVEAL_MAX.
RING_NEAR, RING_FAR, REVEAL_MAX = 4.54, 4.97, 8.0


def make_gantry_ring() -> Part:
    """RevealScaffold: an orange gantry frame round a 9 x 9 slot, 8.0 studs tall with its lamps:
    four posts, a top beam on every side, and on the three sides away from the street a middle
    beam, two braces and a white barrier with an orange rail. It stands wholly outside the slot
    (nothing nearer the centre than 4.57, nothing beyond 4.94), so a landmark that fills its 9 x 9
    touches none of it; the client scales it by max(footprint) / 9."""
    p = Part("gantry-ring")
    e, h = RING_E, RING_POST
    post_top, beam, mid = RING_H - 0.3, 0.36, 4.0
    for sx in (-1, 1):
        for sz in (-1, 1):
            box(p, sx * e - h, sx * e + h, 0.0, post_top, sz * e - h, sz * e + h, TRIM)
            box(p, sx * e - 0.15, sx * e + 0.15, post_top, RING_H, sz * e - 0.15, sz * e + 0.15, LIT, skip=("bottom",))
    inner = e - h
    for turn in (0, 90, 180, 270):
        side = Part("side")
        box(side, -inner, inner, post_top - 0.5 - beam, post_top - 0.5, -e - 0.15, -e + 0.15, TRIM,
            skip=("left", "right"))
        if turn != 0:
            box(side, -inner, inner, mid, mid + 0.3, -e - 0.13, -e + 0.13, TRIM, skip=("left", "right"))
            # the braces run a tenth into the posts, so their open ends are buried
            bar(side, (-inner - 0.1, mid + 0.3, -e), (inner + 0.1, post_top - 0.5 - beam, -e), 0.16, TRIM)
            bar(side, (inner + 0.1, 1.6, -e), (-inner - 0.1, mid, -e), 0.16, TRIM)
            box(side, -inner, inner, 0.3, 1.2, -e - 0.06, -e + 0.06, HULL, skip=("left", "right"), back=PANEL)
            box(side, -inner, inner, 1.2, 1.46, -e - 0.09, -e + 0.09, TRIM, skip=("left", "right"))
        place(p, side, turn)
    return p


PIECES = {
    "ground-a": make_ground_a,
    "ground-b": make_ground_b,
    "ground-c": make_ground_c,
    "boulder-large": make_boulder_large,
    "boulder-medium": make_boulder_medium,
    "boulder-small": make_boulder_small,
    "rock-slab": make_rock_slab,
    "boulder-pile": make_boulder_pile,
    "crater-fresh": make_crater_fresh,
    "survey-beacon": make_survey_beacon,
    "site-deck-narrow": make_site_deck_narrow,
    "site-deck-small": make_site_deck_small,
    "site-deck-medium": make_site_deck_medium,
    "blast-mark": make_blast_mark,
    "plate-stack": make_plate_stack,
    "crate": make_crate,
    "crate-long": make_crate_long,
    "pod-frame": make_pod_frame,
    "pod-frame-large": make_pod_frame_large,
    "work-light": make_work_light,
    "robot-gantry": make_robot_gantry,
    "lander": make_lander,
    "landing-beacon": make_landing_beacon,
    "gantry-ring": make_gantry_ring,
}


# --- blueprints ----------------------------------------------------------------------------------

BLUEPRINT_DIR = os.path.join(REPO_ROOT, "tools", "testfit", "blueprints", "_props", "OrbitalColony")
ERA = "OrbitalColony"


def placed(model: str, pos: Vec, rot: float = 0) -> dict:
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


# The triangle budgets of the builder's brief (INTERFACES "Wave 4.1"). A clump is four quarters, so
# a quarter in fact has a quarter of CLUMP_TRIS: check() holds it to both.
CLUMP_TRIS, QUARTER_TRIS, SINGLE_TRIS, SITE_TRIS = 600, 250, 120, 500


def blueprints() -> list[dict]:
    """Every blueprint this kit owns, in the schema of tools/testfit/blueprint.py."""
    frame = "in the local (+X, +Z) quadrant, x and z in 0 .. 6.5 (INTERFACES 'Fabric data')"
    quarters = {
        "A": (
            f"one quarter of impact ground {frame}: a fresh crater on its apron, a pit, one boulder, dust; "
            "regolith-kit is 1 unit = 1 stud, so scale is 1.0",
            [
                placed("ground-a", (0, 0, 0)),
                placed("boulder-medium", (1.3, 0, 1.75), 25),
            ],
            "impact ground (four quarters)",
        ),
        "B": (
            f"one quarter of a boulder field {frame}: rocks of three sizes on a drift of dust; scale 1.0",
            [
                placed("ground-b", (0, 0, 0)),
                placed("boulder-large", (4.55, 0, 4.4), 15),
                placed("boulder-medium", (2.25, 0, 2.55), 200),
                placed("boulder-small", (5.2, 0, 1.35), 40),
            ],
            "boulder field (four quarters)",
        ),
        "C": (
            f"one quarter of dust flats {frame}: a wide patch of dust a rover has crossed, an old filled "
            "crater, a slab of bedrock; scale 1.0",
            [
                placed("ground-c", (0, 0, 0)),
                placed("rock-slab", (1.6, 0, 5.3), 160),
                placed("boulder-small", (2.9, 0, 1.2), 80),
            ],
            "dust flats (four quarters)",
        ),
    }
    out = []

    def add(bid: str, footprint: list, note: str, pieces: list[dict]) -> None:
        out.append({"id": bid, "era": ERA, "scale": 1.0, "footprint": footprint, "note": note, "pieces": pieces})

    for key, (note, pieces, title) in quarters.items():
        add(f"RegolithQuarter{key}", [13, 13], note, pieces)
        clump = [quarter_turned(piece, turns) for turns in range(4) for piece in pieces]
        add(f"RegolithClump{key}", [13, 13],
            f"exactly RegolithQuarter{key} at rotY 0, 90, 180 and 270 about the origin: {title}, 13 x 13 on the "
            "14-stud grid", clump)

    add("RegolithBoulder", [2, 2], "a standing stone over two smaller rocks: the wild's tall accent",
        [placed("boulder-pile", (0, 0, 0))])
    add("RegolithCrater", [3, 3], "a fresh crater with a lit crest, its apron and three blocks of ejecta",
        [placed("crater-fresh", (0, 0, 0))])
    add("SurveyBeacon", [1, 1], "a surveyor's tripod with a lit lamp and an orange tag",
        [placed("survey-beacon", (0, 0, 0))])

    narrow = [
        placed("site-deck-narrow", (0, 0, 0)),
        placed("pod-frame", (0, DECK_TOP, -2.05)),
        placed("plate-stack", (0.95, 0, 1.0), 0),
    ]
    add("SiteNarrow", [4, 8],
        "a pod going up on a 4 x 8 lot, in the lot frame (the tube on -Z): two and a half rows of deck laid, the "
        "pod's floor, ribs and first panels on them, plates and crates waiting on the dust behind, a site light",
        narrow + [placed("crate", (-0.85, 0, 2.75), 10), placed("crate-long", (0.75, 0, 3.3), 0),
                  placed("work-light", (-1.6, 0, 3.6))])
    add("SiteNarrowGantry", [4, 8],
        "SiteNarrow with the robot gantry (site variant) standing across the back of the lot, its arm holding the "
        "next panel over the pod; 7.5 tall, all of it inside the lot",
        narrow + [placed("robot-gantry", (0, 0, 2.5)), placed("crate", (-0.7, 0, 3.4), 10),
                  placed("crate-long", (0.85, 0, 3.5), 0)])
    small = [
        placed("site-deck-small", (0, 0, 0)),
        placed("pod-frame", (-1.2, DECK_TOP, -1.2)),
        placed("plate-stack", (2.05, 0, -0.05), 0),
    ]
    add("SiteSmall", [6, 6],
        "a pod going up on a 6 x 6 lot, in the lot frame: a row and a half of deck laid, the pod's floor, ribs and "
        "first panels, plates and crates waiting on the dust, two site lights",
        small + [placed("crate", (2.2, 0, 2.1), 15), placed("crate-long", (0.5, 0, 2.3), 0),
                 placed("crate", (1.3, DECK_TOP, -2.3), 0), placed("work-light", (-2.6, 0, 2.6)),
                 placed("work-light", (2.65, DECK_TOP, -2.65))])
    add("SiteSmallGantry", [6, 6],
        "SiteSmall with the robot gantry (site variant) behind the pod, its arm holding the next panel over it; "
        "7.5 tall, all of it inside the lot",
        small + [placed("robot-gantry", (-1.0, 0, 1.75)), placed("crate", (2.3, 0, 2.25), 15),
                 placed("crate", (1.3, DECK_TOP, -2.3), 0), placed("crate-long", (1.9, 0, 1.2), 0)])
    add("SiteMedium", [8, 12],
        "a pod going up on an 8 x 12 lot, in the lot frame: three and a half rows of deck laid, the pod's floor, "
        "ribs and first panels, and at the back the small lander that brought the cargo, on its scorch mark, with "
        "crates off it and plates waiting",
        [
            placed("site-deck-medium", (0, 0, 0)),
            placed("pod-frame-large", (-1.5, DECK_TOP, -3.3)),
            placed("blast-mark", (1.9, 0, 3.75)),
            placed("lander", (1.9, 0, 3.75), 20),
            placed("plate-stack", (2.4, 0, 0.95), 0),
            placed("crate", (-0.35, 0, 3.0), 10),
            placed("crate", (-1.5, 0, 4.4), 35),
            placed("crate-long", (-2.7, 0, 2.95), 90),
            placed("crate", (2.5, DECK_TOP, -4.6), 0),
            placed("work-light", (3.55, DECK_TOP, -1.2)),
        ])
    add("LotBeacon", [2, 2],
        "the next-pad marker: a landing beacon 4.5 tall, a level ring of light 1.9 across round a lit lamp on a white "
        "mast, the same from every side",
        [placed("landing-beacon", (0, 0, 0))])
    add("RevealScaffold", [10, 10],
        "one generated piece: an orange gantry frame with lit corner lamps and a white barrier on three sides that "
        "stands wholly outside a 9 x 9 slot (nothing nearer the centre than 4.57, nothing beyond 4.94), open at the "
        "street, so a landmark that fills its footprint touches none of it; the client still scales it by "
        "max(footprint) / 9",
        [placed("gantry-ring", (0, 0, 0))])
    return out


def blueprint_text(bp: dict) -> str:
    """A blueprint as the repo keeps it: one key per line, one piece per line, LF."""
    lines = ["{"]
    lines += [f'  "{key}": {json.dumps(value)},' for key, value in bp.items() if key != "pieces"]
    lines.append('  "pieces": [')
    lines.append(",\n".join("    " + json.dumps(piece, separators=(", ", ": ")) for piece in bp["pieces"]))
    lines += ["  ]", "}"]
    return "\n".join(lines) + "\n"


def write_blueprints() -> None:
    os.makedirs(BLUEPRINT_DIR, exist_ok=True)
    for bp in blueprints():
        path = os.path.join(BLUEPRINT_DIR, bp["id"] + ".json")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(blueprint_text(bp))
        log(f"wrote {os.path.relpath(path, REPO_ROOT)}")


# --- the check -----------------------------------------------------------------------------------


def assembled(bp: dict, parts: dict) -> list[tuple[list[Vec], Rgb]]:
    """Every face of a blueprint as it stands: each piece turned by its rotY (Roblox's mapping, as
    place() and testfit.py turn it) and moved to its pos."""
    faces = []
    for piece in bp["pieces"]:
        part = parts[piece["model"]]
        a = math.radians(piece["rotY"])
        c, s = math.cos(a), math.sin(a)
        px, py, pz = piece["pos"]
        for idx, colour in part.faces:
            points = [part.verts[i] for i in idx]
            faces.append(([(x * c + z * s + px, y + py, -x * s + z * c + pz) for x, y, z in points], colour))
    return faces


def triangles_overlap(a, b) -> bool:
    """Whether two triangles in a plane share some area (separating axes; touching does not count)."""
    for tri in (a, b):
        for i in range(3):
            (x0, y0), (x1, y1) = tri[i], tri[(i + 1) % 3]
            nx, ny = y1 - y0, x0 - x1
            scale = math.hypot(nx, ny)
            if scale < 1e-9:
                continue
            pa = [nx * x + ny * y for x, y in a]
            pb = [nx * x + ny * y for x, y in b]
            if (min(max(pa), max(pb)) - max(min(pa), min(pb))) / scale <= 1e-3:
                return False
    return True


def flat_fights(faces, ground: bool) -> list[str]:
    """Pairs of faces that would flicker: parallel, facing the same way, overlapping and closer
    than MIN_GAP (coplanar included). Faces are bucketed by their normal, so tilted and turned
    faces are tested like level ones; opposite-facing pairs never render together (a MeshPart culls
    back faces) and are not reported. With `ground`, any level face under MIN_GAP above the plot
    base is reported too."""
    buckets: dict = {}
    found = []
    for points, _ in faces:
        n = newell(points)
        length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
        if length < 1e-9:
            continue
        n = (n[0] / length, n[1] / length, n[2] / length)
        centre = tuple(sum(q[i] for q in points) / len(points) for i in range(3))
        # the face must be flat to be a plane at all: a crater's warped quads are skipped
        if max(abs(sum(n[i] * (q[i] - centre[i]) for i in range(3))) for q in points) > 1e-4:
            continue
        if ground and n[1] > 0.9999 and centre[1] < MIN_GAP - 1e-6:
            found.append(f"a level face only {centre[1]:.3f} above the plot base near "
                         f"({centre[0]:.2f}, {centre[2]:.2f})")
        key = tuple(round(c, 3) + 0.0 for c in n)
        buckets.setdefault(key, []).append((points, centre))
    for key, members in buckets.items():
        # One frame for the whole bucket, from its key: faces are compared in the same two axes.
        length = math.sqrt(sum(c * c for c in key))
        n = tuple(c / length for c in key)
        axis = min(range(3), key=lambda i: abs(n[i]))
        u = [0.0, 0.0, 0.0]
        u[axis] = 1.0
        d = sum(u[i] * n[i] for i in range(3))
        u = [u[i] - d * n[i] for i in range(3)]
        ul = math.sqrt(sum(c * c for c in u))
        u = [c / ul for c in u]
        v = (n[1] * u[2] - n[2] * u[1], n[2] * u[0] - n[0] * u[2], n[0] * u[1] - n[1] * u[0])
        group = []
        for points, centre in members:
            flat = [(sum(u[i] * q[i] for i in range(3)), sum(v[i] * q[i] for i in range(3))) for q in points]
            mid = (sum(q[0] for q in flat) / len(flat), sum(q[1] for q in flat) / len(flat))
            fan = [(mid, flat[i], flat[(i + 1) % len(flat)]) for i in range(len(flat))]
            group.append((sum(n[i] * centre[i] for i in range(3)), fan, centre))
        group.sort(key=lambda f: f[0])
        for i, (da, fan_a, centre) in enumerate(group):
            for db, fan_b, _ in group[i + 1:]:
                if db - da >= MIN_GAP - 1e-6:
                    break
                if any(triangles_overlap(ta, tb) for ta in fan_a for tb in fan_b):
                    found.append(f"two faces {db - da:.3f} apart near "
                                 f"({centre[0]:.2f}, {centre[1]:.2f}, {centre[2]:.2f})")
    return found


def thin_faces(faces, limit: float = MIN_MEMBER) -> list[str]:
    """Faces narrower than `limit`: the narrowest a face is across (the least, over its edges, of
    how far its corners stand from that edge). A member thinner than the limit has such a face, and
    so does a sliver. For pieces that are not built from box() and bar(), which note their own."""
    found = []
    for points, _ in faces:
        width = math.inf
        for i, a in enumerate(points):
            b = points[(i + 1) % len(points)]
            edge = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            length = math.sqrt(edge[0] ** 2 + edge[1] ** 2 + edge[2] ** 2)
            if length < 1e-9:
                continue
            reach = 0.0
            for q in points:
                d = (q[0] - a[0], q[1] - a[1], q[2] - a[2])
                c = (d[1] * edge[2] - d[2] * edge[1], d[2] * edge[0] - d[0] * edge[2], d[0] * edge[1] - d[1] * edge[0])
                reach = max(reach, math.sqrt(c[0] ** 2 + c[1] ** 2 + c[2] ** 2) / length)
            width = min(width, reach)
        if width < limit - 1e-6:
            centre = tuple(sum(q[i] for q in points) / len(points) for i in range(3))
            found.append(f"a face {width:.3f} across near ({centre[0]:.2f}, {centre[1]:.2f}, {centre[2]:.2f})")
    return found


def limits(bid: str):
    """(x0, x1, z0, z1, tallest, triangles) a prop must keep to."""
    if bid.startswith("RegolithClump"):
        return (-EDGE, EDGE, -EDGE, EDGE, WILD_MAX, CLUMP_TRIS)
    if bid.startswith("RegolithQuarter"):
        return (0.0, EDGE, 0.0, EDGE, WILD_MAX, QUARTER_TRIS)
    if bid in ("RegolithBoulder", "RegolithCrater", "SurveyBeacon"):
        half = {"RegolithBoulder": 1.0, "RegolithCrater": 1.5, "SurveyBeacon": 0.5}[bid]
        return (-half, half, -half, half, WILD_MAX, SINGLE_TRIS)
    if bid.startswith("Site"):
        lot = "narrow" if "Narrow" in bid else "small" if "Small" in bid else "medium"
        w, d = LOTS[lot]
        return (-w / 2, w / 2, -d / 2, d / 2, GANTRY_MAX if bid.endswith("Gantry") else SITE_MAX, SITE_TRIS)
    if bid == "LotBeacon":  # the marker's 2 x 2 footprint (`fabric.py check`); about 4.5 tall (wave 4.1b)
        return (-1.0, 1.0, -1.0, 1.0, BEACON_TOP + 0.1, None)
    if bid == "RevealScaffold":  # Metropolis's RevealScaffold: inside 10 x 10, at most 8 tall
        return (-5.0, 5.0, -5.0, 5.0, REVEAL_MAX, None)
    raise KeyError(bid)


def check(out_dir: str) -> tuple[list[str], list[tuple]]:
    """The contract, prop by prop. Returns the problems and a row per prop: (id, width, depth,
    height, triangles)."""
    THIN.clear()
    parts = {name: make() for name, make in PIECES.items()}
    bad = list(dict.fromkeys(f"a member under {MIN_MEMBER}: {note}" for note in THIN))
    for name, part in parts.items():
        if part.name != name:
            bad.append(f"{name}: Part is named {part.name!r}")
        if signed_volume(part) <= 0:
            bad.append(f"{name}: faces wound inside out (volume {signed_volume(part):.3f})")
        if not os.path.isfile(os.path.join(out_dir, name + ".glb")):
            bad.append(f"{name}.glb is missing from {os.path.relpath(out_dir, REPO_ROOT)}: run without `check`")
    rows = []
    bps = blueprints()
    names = [bp["id"] for bp in bps]
    wanted = [f"Regolith{kind}{key}" for kind in ("Clump", "Quarter") for key in "ABC"] + [
        "RegolithBoulder", "RegolithCrater", "SurveyBeacon", "SiteNarrow", "SiteNarrowGantry", "SiteSmall",
        "SiteSmallGantry", "SiteMedium", "LotBeacon", "RevealScaffold"]
    if sorted(names) != sorted(wanted):
        bad.append(f"the blueprints are {sorted(names)}, not the sixteen of the contract")
    for bp in bps:
        bid = bp["id"]
        faces = assembled(bp, parts)
        verts = [q for points, _ in faces for q in points]
        lo = [min(q[i] for q in verts) for i in range(3)]
        hi = [max(q[i] for q in verts) for i in range(3)]
        tris = sum(len(points) - 2 for points, _ in faces)
        rows.append((bid, hi[0] - lo[0], hi[2] - lo[2], hi[1], tris))
        x0, x1, z0, z1, tallest, budget = limits(bid)
        e = 1e-6
        if lo[0] < x0 - e or hi[0] > x1 + e or lo[2] < z0 - e or hi[2] > z1 + e:
            bad.append(f"{bid} leaves x[{x0:g}, {x1:g}] z[{z0:g}, {z1:g}]: x[{lo[0]:.2f}, {hi[0]:.2f}] "
                       f"z[{lo[2]:.2f}, {hi[2]:.2f}]")
        if lo[1] < -e:
            bad.append(f"{bid} goes {-lo[1]:.2f} under the plot base")
        if hi[1] > tallest + e:
            bad.append(f"{bid} is {hi[1]:.2f} tall, over {tallest:g}")
        if budget is not None and tris > budget:
            bad.append(f"{bid} has {tris} triangles, over {budget}")
        for fight in flat_fights(faces, ground=True)[:4]:
            bad.append(f"{bid}: {fight}")
        if bid == "RevealScaffold":
            near = min(max(abs(q[0]), abs(q[2])) for q in verts)
            far = max(hi[0], hi[2], -lo[0], -lo[2])
            if near < RING_NEAR - e or far > RING_FAR + e:
                bad.append(f"{bid} must stand between {RING_NEAR} and {RING_FAR} from the slot's centre: nearest "
                           f"{near:.3f}, farthest {far:.3f}")
        path = os.path.join(BLUEPRINT_DIR, bid + ".json")
        try:
            with open(path, "r", encoding="utf-8", newline="") as fh:
                on_disk = fh.read()
        except OSError:
            on_disk = None
        if on_disk != blueprint_text(bp):
            state = "is missing" if on_disk is None else "differs from a fresh build"
            bad.append(f"{os.path.relpath(path, REPO_ROOT)} {state}: run without `check`")
    # A clump is its quarter turned four times, so a quarter must leave room for three more.
    for key in "ABC":
        quarter = next(row for row in rows if row[0] == f"RegolithQuarter{key}")
        if 4 * quarter[4] > CLUMP_TRIS:
            bad.append(f"RegolithQuarter{key} has {quarter[4]} triangles: four of them are over {CLUMP_TRIS}")
    return bad, rows


# --- export --------------------------------------------------------------------------------------


def generate(out_dir: str, only: set[str] | None) -> None:
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
        log(f"{name}.glb: {part.tris} tris, {hi[0] - lo[0]:.2f} x {hi[1] - lo[1]:.2f} x {hi[2] - lo[2]:.2f} studs, "
            f"x[{lo[0]:.2f}, {hi[0]:.2f}] y[{lo[1]:.2f}, {hi[1]:.2f}] z[{lo[2]:.2f}, {hi[2]:.2f}]")
    log(f"{total} tris total -> {os.path.relpath(out_dir, REPO_ROOT)}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the regolith-kit GLBs and the 16 blueprints; check them.")
    parser.add_argument("command", nargs="?", choices=("build", "check"), default="build",
                        help="build (the default) writes the GLBs and the blueprints, then checks; check only checks")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    parser.add_argument("--only", default="", help="comma list of pieces to rebuild (default: all)")
    args = parser.parse_args(argv)
    if args.command == "build":
        generate(args.out, {name for name in args.only.split(",") if name} or None)
        write_blueprints()
    problems, rows = check(args.out)
    for bid, width, depth, height, tris in rows:
        log(f"{bid}: {width:.2f} x {depth:.2f} studs, {height:.2f} tall, {tris} tris")
    for problem in problems:
        log(f"PROBLEM {problem}")
    log(f"check: {len(problems)} problem(s) in {len(rows)} props" if problems else f"check: {len(rows)} props pass")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []))
