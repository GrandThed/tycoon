"""Raw regolith (Orbital Colony's wild land), the colony's building sites, the landing beacon, the
reveal gantry and the city-changer props for the growing city (M12 wave 4), generated as a
Kenney-style kit.

    py tools/assets/regolith_kit.py                  # the GLBs and the 28 blueprints, then the check
    py tools/assets/regolith_kit.py check            # the check alone: nothing is written
    py tools/assets/regolith_kit.py --only lander    # rebuild some GLBs (blueprints and check as usual)
    py tools/assets/regolith_kit.py --out <dir> --blueprints <dir>   # a trial build that touches nothing shared
    blender -b -P tools/assets/regolith_kit.py -- [the same arguments]

The geometry needs Blender's Python, so under the system `py` the script starts Blender on itself
and passes on this kit's lines and the exit status (1 when the check finds a problem). `BLENDER`
overrides the executable.

Writes one GLB per piece into assets/kenney3d/regolith-kit/Models/GLB format/, the folder
convention every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. The 28 blueprints under
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
quarter design turned 0, 90, 180 and 270 degrees about the clump origin, because the game breaks a
clump into its quarters. A quarter is authored in the clump's frame with all of its content inside
the local (+X, +Z) quadrant, x and z in 0 .. 6.5, so a clump is 13 x 13.

**The symmetry is the subject.** Four turns of anything is a rosette, so each quarter is one
quadrant of a single round thing centred on the clump's centre, its own origin corner, and the
clump reads as that one thing: a large crater, a ring of boulders round a dust basin, a low mound
with a rover's track round it. (The first set scattered small features over each quarter; on open
ground every clump then showed four craters in a square or a pinwheel of ruts.) Three rules follow:
- What crosses a clump axis is the same on both of the quarter's inner edges (the rim's section,
  the plates' radii, the ruts), so the four copies join with no step. `check` compares the edges.
- Inside the quadrant nothing is even: the rim's height and radius wander, it has a slump, the
  rocks stand off the circle, and the outline is a ragged round, never the 13 x 13 square.
- A quarter can stand alone when its clump has broken up, so the solids that are cut by the axes
  (the rim, the central peak, the mound) are capped there, and a lone quarter reads as an arc of
  rim with its rubble or a crescent of boulders.

Every other piece has its origin at its bottom centre and its front on -Z; the lot-sized site
pieces (site-deck-*) are authored in the lot frame (origin at the lot centre on the ground, the
tube on -Z), so a blueprint places them at [0, 0, 0].

**Colours** are space-kit's own material factors read raw x 255 (orbital_kit.py explains why),
written as linear factors like orbital-kit and tube-kit, so palette.py decodes them back to these
bytes: regolith-kit must NOT join palette.SRGB_FACTOR_KITS. The rocks are the kit's three rock
colours. DUST, DUST_LIGHT and RUT are not kit colours: the kit has no ground tone at all, and its
rock salmon laid flat over half the plot would drown the white colony. They are the plot base
(56, 53, 60) mixed toward the kit's dark rock, so dust reads as the same rock, weathered and lying
in shadow. DECK is the contract's decking colour. SAND and RAKE, the tended ground of the gardens,
are the kit's rock mixed toward its hull white: the same ground, raked clean. MOSS is orbital-kit's
plant green and MOSS_DARK a step under it; HOLO is orbital-kit's hologram cyan and CRYSTAL the
kit's own crystal green.

**The city-changers** (INTERFACES "Wave 4.1c"): what one purchase does to the whole colony.
- "Tend the Rock Gardens" swaps every piece of regolith still standing for its **Garden twin**:
  the same round feature in the same frame, tended. The crater is a raked bowl round a crystal,
  the boulder ring a circle of standing stones on raked sand, the mound a moss mound with a
  stepping path where the rover's track ran; the singles become a standing stone on a raked disc,
  a raked ring round crystals, and a garden lantern. Every twin is pale sand inside a white kerb,
  so from the whole-plot camera the rust ground turns light and ordered. A twin keeps its
  original's footprint and reach, a clump twin is its quarter twin at four turns, and a tended bed
  is a true round: nothing in it wanders. `check` holds all three.
- ColonyFlagMast stands beside a tube between two pods, and PierBanner hangs four banners round
  one pier of the monorail, clear of the pier's faces.
- HubBeacon floats a hologram over a tube hub.
None but the pier banner has a front: a layer turns them any way, and the tycoon camera sees them
from every side.
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
CRYSTAL = (47, 224, 151)  # "crystal"
HOLO = (90, 255, 245)  # orbital-kit's hologram
DECK = (96, 98, 108)  # the decking colour (`road.tiles.blocks`, INTERFACES "Wave 4.1")
# Not kit colours (see the module docstring): the plot base mixed 40% and 72% toward ROCK_DARK,
# and 16% for ground a wheel has pressed bare.
DUST = (105, 70, 63)
DUST_LIGHT = (144, 83, 65)
RUT = (76, 60, 61)
# Not kit colours either: ROCK mixed 60% toward HULL, and ROCK_DARK mixed 45% toward it for the
# lines a rake leaves; HOLO mixed half toward white, so a hologram's ring parts from its planet.
SAND = (222, 186, 179)
RAKE = (195, 152, 141)
HOLO_PALE = (172, 255, 250)
MOSS = (97, 203, 139)  # orbital-kit's "plant"
MOSS_DARK = (72, 168, 118)  # not a kit colour: MOSS a step darker, for a mound's foot

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
           floor_y: float, seed: int, seg: int = 7, crest_w: float = 0.0) -> None:
    """A small crater that sits on flat ground: a raised rim round a floor above the plot, never a
    hole in it. The outer slope climbs from the ground at r_out to the crest at r_crest, the inner
    wall drops to the floor at r_floor; with `crest_w` the crest is a flat band that wide in the lit
    rock colour. Every vertex of the ring wanders in angle, radius and height."""
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
        face_out(p, [pt(k, r_out, 0.0), pt(n, r_out, 0.0), pt(n, r_crest), pt(k, r_crest)], ROCK,
                 (out[0], lift, out[2]))
        if crest_w > 0:
            face_out(p, [pt(k, r_crest), pt(n, r_crest), pt(n, r_in), pt(k, r_in)], ROCK_LIGHT, (0.0, 1.0, 0.0))
        face_out(p, [pt(k, r_in), pt(n, r_in), pt(n, r_floor, floor_y), pt(k, r_floor, floor_y)], ROCK_DARK,
                 (-out[0], lift, -out[2]))
    face_out(p, [pt(k, r_floor, floor_y) for k in range(seg)], DUST, (0.0, 1.0, 0.0))


# A rock's profile: (radius, height) as shares of its size, from the ground up.
BOULDER = ((1.0, 0.0), (1.07, 0.42), (0.62, 1.0))
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


def polar(r: float, degrees: float) -> tuple[float, float]:
    """(x, z) at radius r from the clump's centre, `degrees` from +X toward +Z: 0 and 90 are the
    quarter's two inner edges."""
    a = math.radians(degrees)
    return (r * math.cos(a), r * math.sin(a))


def sector(p: Part, angles, inner, outer, y: float, colour: Rgb) -> None:
    """A level plate round the clump's centre, as a decal: between the radii inner[k] and outer[k]
    at angles[k], one flat piece from each station to the next, so both of its ends lie on radii.
    `inner` None runs it from the centre itself."""
    for k in range(len(angles) - 1):
        a0, a1 = angles[k], angles[k + 1]
        if inner is None:
            outline = [(0.0, 0.0), polar(outer[k], a0), polar(outer[k + 1], a1)]
        else:
            outline = [polar(inner[k], a0), polar(outer[k], a0), polar(outer[k + 1], a1),
                       polar(inner[k + 1], a1)]
        decal(p, outline, y, colour)


def ray(p: Part, degrees: float, r0: float, r1: float, w0: float, w1: float, y: float, colour: Rgb) -> None:
    """A streak of dust thrown out from the clump's centre, as a decal: along the radius at
    `degrees` from r0 to r1, w0 wide at its root and w1 at its blunt end."""
    if min(w0, w1) < MIN_MEMBER - 1e-9:
        THIN.append(f"{p.name}: a ray {min(w0, w1):.3f} wide")
    a = math.radians(degrees)
    dx, dz = math.cos(a), math.sin(a)
    h0, h1 = w0 / 2, w1 / 2
    decal(p, [(r0 * dx + h0 * dz, r0 * dz - h0 * dx), (r1 * dx + h1 * dz, r1 * dz - h1 * dx),
              (r1 * dx - h1 * dz, r1 * dz + h1 * dx), (r0 * dx - h0 * dz, r0 * dz + h0 * dx)], y, colour)


def lofted(p: Part, angles, profiles, colours, cap: Rgb | None) -> None:
    """A solid swept round the clump's centre: profiles[k] is its section at angles[k], (radius,
    height) points from its outer foot over its top to its inner foot (or to the centre, radius
    0), and colours[j] paints the band from point j to point j + 1. Both ends are closed with the
    section in `cap`, facing out of the sweep: inside a clump the next quarter's end lies against
    it, and on a quarter that stands alone it is the cut face. A section that ends above the
    ground closes straight down from its last point. `cap` None leaves the ends open, for a sweep
    that runs the whole way round and meets itself."""
    def pt(k: int, j: int) -> Vec:
        r, y = profiles[k][j]
        x, z = polar(r, angles[k])
        return (x, y, z)

    for k in range(len(angles) - 1):
        mid = math.radians((angles[k] + angles[k + 1]) / 2)
        for j, colour in enumerate(colours):
            (r0, y0), (r1, y1) = profiles[k][j], profiles[k][j + 1]
            face = [pt(k, j), pt(k + 1, j), pt(k + 1, j + 1), pt(k, j + 1)]
            if profiles[k][j + 1][0] <= 0 and profiles[k + 1][j + 1][0] <= 0:
                face = face[:3]  # the band closes on the centre
            face_out(p, face, colour, ((y1 - y0) * math.cos(mid), r0 - r1, (y1 - y0) * math.sin(mid)))
    if cap is None:
        return
    for k, sign in ((0, -1.0), (len(angles) - 1, 1.0)):
        a = math.radians(angles[k])
        section = [pt(k, j) for j in range(len(profiles[k]))]
        last_r, last_y = profiles[k][-1]
        if last_y > 0:
            foot = polar(last_r, angles[k]) if last_r > 0 else (0.0, 0.0)  # on the centre line: down it
            section.append((foot[0], 0.0, foot[1]))
        face_out(p, section, cap, (-sign * math.sin(a), 0.0, sign * math.cos(a)))


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


# --- the wild: three quarters, each a quadrant of one round feature --------------------------------
#
# Each quarter piece holds what lies flat or is cut by the clump's axes: the plates of dust, the
# rays, the ruts, and the rim, peak or mound swept round the centre. Stations are degrees from +X;
# the first (0) and the last (90) are the quarter's inner edges, and every list has the same value
# at both, so four copies meet. The boulders and slabs are pieces of their own, placed by the
# blueprint. The rock colours are for the rocks: a rim is ground, in the dust tones with only its
# crest in rock (a field of bright rims read as rings lying on the plot, not as terrain).
WILD_LOW = 1.5  # a clump stays this low: the wild's tall accent is the RegolithBoulder single


def make_crater_quarter() -> Part:
    """A: a quadrant of one impact crater 10 studs across its rim's foot: the floor, the rim with
    its lit crest wandering between 0.6 and 1.1 up and slumped once, the central peak, the apron
    of ejecta with three rays thrown past its ragged edge, chips."""
    p = Part("crater-quarter")
    angles = (0.0, 13.0, 31.0, 44.0, 62.0, 76.0, 90.0)
    foot = (5.0, 5.1, 4.92, 5.12, 5.02, 4.9, 5.0)
    crest = (4.15, 4.2, 4.1, 4.22, 4.16, 4.08, 4.15)
    height = (0.95, 1.1, 0.85, 0.62, 0.98, 1.12, 0.95)
    floor = (3.3, 3.35, 3.2, 3.45, 3.3, 3.15, 3.3)
    apron = (5.9, 6.3, 5.7, 6.4, 6.0, 5.6, 5.9)
    # The plates run a little under the rim on both sides, so no ground shows along its feet.
    sector(p, angles, None, [r + 0.2 for r in floor], DUST_Y, DUST)
    sector(p, angles, [r - 0.45 for r in foot], apron, DUST_Y, DUST)
    for degrees, reach, width in ((21.0, 6.4, 0.75), (52.0, 6.45, 0.6), (70.0, 6.2, 0.7)):
        ray(p, degrees, 4.7, reach, width, 0.2, DRIFT_Y, DUST_LIGHT)
    rim = [[(foot[k], 0.0), (crest[k], height[k]), (crest[k] - 0.4, height[k] * 0.94), (floor[k], 0.0)]
           for k in range(len(angles))]
    lofted(p, angles, rim, (ROCK_DARK, ROCK, DUST_LIGHT), cap=ROCK_DARK)
    peak = [[(1.15, 0.0), (0.5, 0.46), (0.0, 0.6)], [(1.32, 0.0), (0.58, 0.4), (0.0, 0.6)],
            [(1.15, 0.0), (0.5, 0.46), (0.0, 0.6)]]
    lofted(p, (0.0, 48.0, 90.0), peak, (ROCK_DARK, DUST_LIGHT), cap=ROCK_DARK)
    for k, (r, degrees, size) in enumerate(((5.75, 38.0, 0.22), (2.3, 25.0, 0.2), (6.0, 82.0, 0.18))):
        pebble(p, *polar(r, degrees), size, 111 + k)
    return p


def make_basin_quarter() -> Part:
    """B: a quadrant of a dust basin 6.5 studs across inside a ring of boulders: the darker floor,
    the paler dust the boulders stand on out to a ragged edge, chips."""
    p = Part("basin-quarter")
    angles = (0.0, 16.0, 33.0, 47.0, 63.0, 78.0, 90.0)
    floor = (3.2, 3.4, 3.05, 3.3, 3.5, 3.1, 3.2)
    edge = (5.6, 6.1, 5.3, 6.3, 5.8, 5.4, 5.6)
    sector(p, angles, None, floor, DUST_Y, DUST)
    sector(p, angles, floor, edge, DUST_Y, DUST_LIGHT)
    for k, (r, degrees, size) in enumerate(((2.3, 28.0, 0.2), (1.3, 66.0, 0.18), (2.9, 80.0, 0.22),
                                            (5.95, 52.0, 0.2))):
        pebble(p, *polar(r, degrees), size, 211 + k)
    return p


def make_mound_quarter() -> Part:
    """C: a quadrant of a low mound 6 studs across and 0.72 tall on its apron of dust: two fans of
    paler dust, one long and one short, and a rover's two ruts wandering round it, the track a full
    loop in a clump."""
    p = Part("mound-quarter")
    angles = (0.0, 14.0, 30.0, 45.0, 61.0, 77.0, 90.0)
    apron = (5.7, 6.3, 5.2, 6.4, 5.75, 5.1, 5.7)
    sector(p, angles, [2.6] * len(angles), apron, DUST_Y, DUST)
    for degrees, reach, root, tip in ((24.0, 6.4, 1.3, 0.3), (63.0, 5.3, 0.9, 0.45)):
        ray(p, degrees, 2.8, reach, root, tip, DRIFT_Y, DUST_LIGHT)
    track = (4.45, 4.7, 4.3, 4.2, 4.6, 4.8, 4.45)
    for side in (-0.475, 0.475):  # half the rover's gauge
        sector(p, angles, [r + side - 0.12 for r in track], [r + side + 0.12 for r in track], RUT_Y, RUT)
    wide = (1.0, 1.07, 0.94, 1.06, 1.0)
    high = (1.0, 1.12, 0.88, 1.08, 1.0)
    mound = [[(3.0 * w, 0.0), (2.0 * w, 0.36 * h), (0.95 * w, 0.6 * h), (0.0, 0.72)] for w, h in zip(wide, high)]
    lofted(p, (0.0, 24.0, 45.0, 68.0, 90.0), mound, (ROCK_DARK, DUST_LIGHT, ROCK_DARK), cap=ROCK_DARK)
    for k, (r, degrees, size) in enumerate(((5.9, 9.0, 0.2), (3.55, 55.0, 0.18))):
        pebble(p, *polar(r, degrees), size, 311 + k)
    return p


def make_boulder_broad() -> Part:
    """2.0 x 1.7 studs, 1.15 tall."""
    return rock("boulder-broad", (1.0, 1.1, 0.82), 409, seg=7)


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


# --- the city-changers ---------------------------------------------------------------------------

FLAG_TOP = 5.0
FLAG_MAX = 5.2  # "about 5 tall" (INTERFACES "Wave 4.1c")


def banner(p: Part, turn: float, half: float, top: float, shoulder: float, tip: float, colour: Rgb,
           out: float = 0.38, band: tuple[float, float, Rgb] | None = None) -> None:
    """A banner hanging from a yard arm: a cloth MIN_MEMBER thick and 2 * half wide, square down to
    `shoulder` and cut to a point at `tip`, from `out` to out + MIN_MEMBER from the mast or pier on
    the side `turn` degrees round it. Its top edge is against the yard, so it has no top face.
    `band` = (y0, y1, colour) paints a stripe across both of its faces, MIN_GAP off the cloth."""
    cloth = Part("banner")
    x0, x1 = out, out + MIN_MEMBER
    if band is not None:
        for x, facing in ((x1 + MIN_GAP, 1.0), (x0 - MIN_GAP, -1.0)):
            face_out(cloth, [(x, band[0], -half), (x, band[0], half), (x, band[1], half), (x, band[1], -half)], band[2],
                     (facing, 0.0, 0.0))
    outline = [(-half, top), (half, top), (half, shoulder), (0.0, tip), (-half, shoulder)]  # (z, y)
    face_out(cloth, [(x1, y, z) for z, y in outline], colour, (1.0, 0.0, 0.0))
    face_out(cloth, [(x0, y, z) for z, y in outline], colour, (-1.0, 0.0, 0.0))
    for (za, ya), (zb, yb) in zip(outline[1:], outline[2:] + outline[:1]):
        face_out(cloth, [(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)], colour,
                 (0.0, (ya + yb) / 2 - (top + shoulder) / 2, (za + zb) / 2))
    place(p, cloth, turn)


def make_flag_mast() -> Part:
    """ColonyFlagMast: a standard 1 stud across and 5 tall, the same from every side: a white mast
    on a grey foot, two orange yards crossed near its top, and four banners hanging from their
    ends, two long orange ones and, a little higher, two shorter white ones, each cut to a point.
    Hanging banners on crossed yards, not one flag flying: whichever way a layer turns the mast,
    two cloths face the camera, and it cannot be taken for the Colony Flag landmark's flag."""
    p = Part("flag-mast")
    box(p, -0.2, 0.2, 0.0, 0.16, -0.2, 0.2, PANEL)
    box(p, -0.07, 0.07, 0.16, 4.72, -0.07, 0.07, HULL, skip=("bottom", "top"))
    # The yards: flat bars MIN_GAP wider than the mast on each side, the higher one MIN_GAP over
    # the lower where they cross.
    low, high = 4.4, 4.55
    box(p, -0.5, 0.5, low, low + MIN_MEMBER, -0.12, 0.12, TRIM, skip=())
    box(p, -0.12, 0.12, high, high + MIN_MEMBER, -0.5, 0.5, TRIM, skip=())
    for turn in (0, 180):
        banner(p, turn, 0.28, low, 2.95, 2.55, TRIM)
    for turn in (90, 270):
        banner(p, turn, 0.28, high, 3.6, 3.25, HULL)
    drum(p, [(0.13, 4.72), (0.0, FLAG_TOP)], [TRIM, TRIM], seg=4, bottom=True)
    return p


def crystal(p: Part, x: float, y: float, z: float, r: float, h: float, lean: float, turn: float) -> None:
    """A crystal standing at (x, y, z): a four-sided shard r to its corners and h tall, leaning
    `lean` degrees toward `turn` (degrees from +X toward +Z), cut to a point over its last quarter."""
    a = math.radians(turn)
    slope = math.tan(math.radians(lean))

    def at(k: int, radius: float, up: float) -> Vec:
        corner = a + math.pi / 4 + k * math.pi / 2
        return (x + radius * math.cos(corner) + up * slope * math.cos(a), y + up,
                z + radius * math.sin(corner) + up * slope * math.sin(a))

    tip = at(0, 0.0, h)
    for k in range(4):
        mid = a + math.pi / 4 + (k + 0.5) * math.pi / 2
        out = (math.cos(mid), 0.0, math.sin(mid))
        face_out(p, [at(k, r, 0.0), at(k + 1, r, 0.0), at(k + 1, r, 0.74 * h), at(k, r, 0.74 * h)], CRYSTAL, out)
        face_out(p, [at(k, r, 0.74 * h), at(k + 1, r, 0.74 * h), tip], CRYSTAL, (out[0], 0.8, out[2]))


def centre_crystal(p: Part, r: float, shoulder: float, tip: float) -> None:
    """A quadrant of the crystal at a clump's centre: a four-sided shard r to its corners, square
    to `shoulder` and cut to a point at `tip`, its corners on the clump's diagonals. Four copies
    make the whole crystal; one alone is a shard with two cut faces."""
    flat = r * math.cos(math.pi / 4)
    lofted(p, (0.0, 45.0, 90.0), [[(flat, 0.0), (flat, shoulder), (0.0, tip)], [(r, 0.0), (r, shoulder), (0.0, tip)],
                                  [(flat, 0.0), (flat, shoulder), (0.0, tip)]], (CRYSTAL, CRYSTAL), cap=CRYSTAL)


# --- the tended twins: "Tend the Rock Gardens" ------------------------------------------------------
#
# A garden is the wild feature raked and edged: pale sand inside a white kerb, with rings a rake
# left round its centre. Its layers are the wild's: sand at the dust's height, raked rings and
# stepping stones at the drift's. Its stations are even (a 20-sided round for a clump, 8 for a
# single), and every list is constant: tended ground does not wander.

GARDEN_R = 6.1  # a garden clump's kerb, to its outer face: inside every wild clump's reach
GARDEN_STATIONS = (0.0, 18.0, 36.0, 54.0, 72.0, 90.0)
WHOLE_ROUND = tuple(45.0 * k for k in range(9))  # a single's stations, all the way round
SAND_Y = DUST_Y
RAKE_Y = DRIFT_Y
RAKE_WIDE = 0.14


def kerb(p: Part, radius: float, angles=GARDEN_STATIONS, wide: float = 0.34, tall: float = 0.22,
         cap: Rgb | None = HULL) -> None:
    """A garden's white kerb: an outer wall `tall` high at `radius` and a top that slopes down
    inward over `wide` to just above the sand, so it needs no inner wall."""
    section = [(radius, 0.0), (radius, tall), (radius - wide, SAND_Y + 0.01)]
    lofted(p, angles, [section] * len(angles), (HULL, HULL), cap=cap)


def sand(p: Part, inner: float | None, outer: float, angles=GARDEN_STATIONS) -> None:
    """Raked sand from `inner` (None: from the centre) out to `outer`."""
    sector(p, angles, None if inner is None else [inner] * len(angles), [outer] * len(angles), SAND_Y, SAND)


def rake_ring(p: Part, radius: float, angles=GARDEN_STATIONS) -> None:
    """One ring a rake left round the centre."""
    sector(p, angles, [radius - RAKE_WIDE / 2] * len(angles), [radius + RAKE_WIDE / 2] * len(angles), RAKE_Y, RAKE)


def polar_at(r: float, degrees: float, y: float = 0.0) -> Vec:
    """polar() as a point at height y."""
    x, z = polar(r, degrees)
    return (x, y, z)


def make_garden_bowl_quarter() -> Part:
    """A's twin: a quadrant of the crater as a raked bowl: the kerb, sand on the apron and the
    floor, the rim rebuilt as an even berm with a white crest, three raked rings, a quarter of the
    tall crystal at the centre and a small one on the apron."""
    p = Part("garden-bowl-quarter")
    kerb(p, GARDEN_R)
    sand(p, None, 3.5)
    sand(p, 4.6, GARDEN_R - 0.2)
    berm = [(4.9, 0.0), (4.25, 0.7), (3.95, 0.7), (3.3, 0.0)]
    lofted(p, GARDEN_STATIONS, [berm] * len(GARDEN_STATIONS), (SAND, HULL, SAND), cap=SAND)
    for radius in (1.5, 2.5, 5.3):
        rake_ring(p, radius)
    centre_crystal(p, 0.42, 1.0, 1.4)
    crystal(p, *polar_at(5.35, 63.0), 0.16, 0.62, 10.0, 63.0)
    return p


def make_garden_stones_quarter() -> Part:
    """B's twin: a quadrant of the boulder ring as a stone circle: the kerb, sand to it, three
    raked rings, a quarter of the low island stone at the centre and a crystal by the circle. The
    standing stones are pieces of their own."""
    p = Part("garden-stones-quarter")
    kerb(p, GARDEN_R)
    sand(p, None, GARDEN_R - 0.2)
    for radius in (1.7, 2.7, 5.15):
        rake_ring(p, radius)
    island = [(0.75, 0.0), (0.62, 0.26), (0.0, 0.34)]
    lofted(p, (0.0, 45.0, 90.0), [island] * 3, (ROCK, ROCK_LIGHT), cap=ROCK_DARK)
    crystal(p, *polar_at(4.55, 58.0), 0.15, 0.6, 12.0, 58.0)
    return p


def make_garden_moss_quarter() -> Part:
    """C's twin: a quadrant of the mound as a moss garden: the kerb, sand round the mound, the
    mound itself even and green, two raked rings, five stepping stones where the rover's track
    ran (evenly spaced, so a clump's twenty make one path) and two crystals on the moss."""
    p = Part("garden-moss-quarter")
    kerb(p, GARDEN_R)
    sand(p, 2.8, GARDEN_R - 0.2)
    mound = [(3.0, 0.0), (2.1, 0.4), (1.0, 0.64), (0.0, 0.75)]
    lofted(p, (0.0, 22.5, 45.0, 67.5, 90.0), [mound] * 5, (MOSS_DARK, MOSS, MOSS), cap=MOSS_DARK)
    for radius in (3.45, 5.35):
        rake_ring(p, radius)
    for degrees in (9.0, 27.0, 45.0, 63.0, 81.0):
        x, z = polar(4.4, degrees)
        corners = [math.radians(60.0 * k + degrees) for k in range(6)]
        decal(p, [(x + 0.34 * math.cos(a), z + 0.34 * math.sin(a)) for a in corners], RAKE_Y, PANEL)
    crystal(p, *polar_at(1.7, 35.0, 0.3), 0.2, 0.95, 8.0, 35.0)
    crystal(p, *polar_at(2.05, 60.0, 0.25), 0.14, 0.55, 15.0, 110.0)
    return p


def make_standing_stone() -> Part:
    """0.8 x 0.7 studs, 1.4 tall: the tall stone of a stone circle."""
    return rock("standing-stone", (0.4, 1.22, 0.32), 701, seg=4, profile=STONE, jitter=0.1, lean=(0.03, 0.0), slant=0.1)


def make_standing_stone_low() -> Part:
    """0.75 x 0.6 studs, 0.85 tall."""
    return rock("standing-stone-low", (0.38, 0.8, 0.3), 703, seg=4, jitter=0.1)


def make_stone_garden() -> Part:
    """RegolithBoulder's twin: a standing stone 2.7 tall on a raked disc 1.96 across inside a low
    white kerb, a small crystal at its foot."""
    p = rock("stone-garden", (0.36, 2.3, 0.3), 711, seg=5, profile=STONE, jitter=0.1, lean=(0.04, -0.02), slant=0.12)
    kerb(p, 0.98, WHOLE_ROUND, wide=0.2, tall=0.18, cap=None)
    sand(p, None, 0.86, WHOLE_ROUND)
    rake_ring(p, 0.62, WHOLE_ROUND)
    crystal(p, 0.42, 0.0, 0.38, 0.11, 0.42, 12.0, 40.0)
    return p


def make_ring_garden() -> Part:
    """RegolithCrater's twin: a raked ring 2.9 across: a low white kerb, sand, two raked rings and
    two crystals at the centre, the taller 1.15."""
    p = Part("ring-garden")
    kerb(p, 1.45, WHOLE_ROUND, wide=0.24, tall=0.2, cap=None)
    sand(p, None, 1.3, WHOLE_ROUND)
    for radius in (0.72, 1.05):
        rake_ring(p, radius, WHOLE_ROUND)
    crystal(p, -0.05, 0.0, 0.03, 0.2, 1.15, 5.0, 40.0)
    crystal(p, 0.27, 0.0, -0.14, 0.13, 0.6, 16.0, 320.0)
    return p


def make_garden_lantern() -> Part:
    """SurveyBeacon's twin: a stone lantern 2.1 tall on a pad of sand: a grey foot, a white post
    and shelf, the lit box, a white roof with an orange finial."""
    p = Part("garden-lantern")
    sand(p, None, 0.5, WHOLE_ROUND)
    box(p, -0.3, 0.3, 0.0, 0.16, -0.3, 0.3, PANEL)
    box(p, -0.11, 0.11, 0.16, 1.0, -0.11, 0.11, HULL, skip=("bottom", "top"))
    box(p, -0.3, 0.3, 1.0, 1.12, -0.3, 0.3, HULL, skip=())
    box(p, -0.19, 0.19, 1.12, 1.5, -0.19, 0.19, LIT, skip=("bottom", "top"))
    drum(p, [(0.5, 1.5), (0.0, 1.95)], [HULL, HULL], seg=4, phase=math.pi / 4, bottom=True)
    box(p, -0.07, 0.07, 1.86, 2.1, -0.07, 0.07, TRIM)
    return p


# --- the pier banner: "Raise the Colony Flags" on the monorail ------------------------------------

PIER_BANNER_MAX = 6.0  # under the beam's soffit (6.10)
PIER_BANNER_HALF = 1.2  # at most 2.4 across


def make_pier_banner() -> Part:
    """PierBanner: four banners round one pier of the monorail, 2.1 x 1.7 across, from 1.1 to 4.86
    up. Its origin is the pier foot's centre and its front is -Z, outward from the loop. A square
    orange collar round the shaft under the pier's own collar, a yard on each of its faces, and a
    banner hanging from each: orange with a white band to the front and the back, 2 studs wide,
    and white with an orange band along the track, 1 wide. Nothing touches the pier: the collar
    stands 0.09 off the shaft and the cloths 0.3 or more."""
    p = Part("pier-banner")
    low, high = 4.72, 4.86
    square = 1.0 / math.cos(math.pi / 4)  # a square's corner radius over its flat radius
    hoop(p, 0.42 * square, 0.56 * square, low, high, TRIM, seg=4, phase=math.pi / 4)
    for turn, half, shoulder, tip, colour, stripe in ((90, 1.0, 1.6, 1.1, TRIM, HULL), (270, 1.0, 1.6, 1.1, TRIM, HULL),
                                                      (0, 0.5, 2.5, 2.1, HULL, TRIM), (180, 0.5, 2.5, 2.1, HULL, TRIM)):
        yard = Part("yard")
        box(yard, 0.56, 0.86, low, high, -half - 0.04, half + 0.04, TRIM, skip=("left",))
        place(p, yard, turn)
        banner(p, turn, half, low, shoulder, tip, colour, out=0.66, band=(3.7, 4.2, stripe))
    return p


# --- the hub beacon: "Light the Holo Beacons" ----------------------------------------------------

HUB_CAP = 2.65  # a TubeHub's top is 2.6: all of a hub beacon is at this height or above
BEACON_MAX = 8.6  # "between about 5 and 8.5 up"
BEACON_HALF = 1.85  # "about 3.6 across", well inside a hub's 4.6


def make_hub_hologram() -> Part:
    """HubBeacon: a hologram over a tube hub, 3.6 across, from 2.65 to 8.1 up, the same from every
    side. Its origin is the hub's centre on the ground and nothing of it is lower than the hub's
    cap, where its foot rests: a white mast 2 studs tall with a lit orange dish, and floating clear
    of it a ringed planet in holo cyan 2.5 across, its ring level and paler. A planet, not the Holo
    Beacon landmark's diamond in two rings on a beam. (The first, 2.3 across and 5.75 at its top,
    could not be seen from the whole-plot camera.)"""
    p = Part("hub-hologram")
    phase = math.radians(22.5)
    drum(p, [(0.62, HUB_CAP), (0.4, HUB_CAP + 0.25)], [PANEL, HULL], seg=8, phase=phase, bottom=True)
    box(p, -0.12, 0.12, HUB_CAP + 0.25, 4.6, -0.12, 0.12, HULL, skip=("bottom", "top"))
    drum(p, [(0.2, 4.6), (0.5, 4.85)], [TRIM, LIT], seg=8, phase=phase, bottom=True)
    centre = 6.85
    planet = [(0.0, centre - 1.25), (0.9, centre - 0.75), (1.25, centre), (0.9, centre + 0.75), (0.0, centre + 1.25)]
    lathe(p, planet, [HOLO] * 4, seg=8, phase=phase)
    # The ring lies level: a tilted one is edge-on from one side, and the tycoon camera looks at
    # every hub from the same side.
    hoop(p, 1.5, 1.948, centre - 0.06, centre + 0.06, HOLO_PALE, seg=8, phase=phase)
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
    "crater-quarter": make_crater_quarter,
    "basin-quarter": make_basin_quarter,
    "mound-quarter": make_mound_quarter,
    "boulder-broad": make_boulder_broad,
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
    "flag-mast": make_flag_mast,
    "garden-bowl-quarter": make_garden_bowl_quarter,
    "garden-stones-quarter": make_garden_stones_quarter,
    "garden-moss-quarter": make_garden_moss_quarter,
    "standing-stone": make_standing_stone,
    "standing-stone-low": make_standing_stone_low,
    "stone-garden": make_stone_garden,
    "ring-garden": make_ring_garden,
    "garden-lantern": make_garden_lantern,
    "pier-banner": make_pier_banner,
    "hub-hologram": make_hub_hologram,
}


# --- blueprints ----------------------------------------------------------------------------------

BLUEPRINT_DIR = os.path.join(REPO_ROOT, "tools", "testfit", "blueprints", "_props", "OrbitalColony")
ERA = "OrbitalColony"


def placed(model: str, pos: Vec, rot: float = 0) -> dict:
    """One blueprint piece of this kit: `pos` in studs (the kit's unit), `rot` degrees about Y."""
    return {"kit": KIT, "model": model, "pos": [round(v, 4) for v in pos], "rotY": rot, "stage": 0}


def ringed(model: str, r: float, degrees: float, rot: float = 0) -> dict:
    """A piece on the ground at radius r from the clump's centre, `degrees` from +X toward +Z."""
    x, z = polar(r, degrees)
    return placed(model, (x, 0, z), rot)


TWIN = "Garden"  # a tended twin's name is its original's with this added


def four_turns(pieces: list[dict]) -> list[dict]:
    """A clump's pieces: its quarter's at four quarter turns."""
    return [quarter_turned(piece, turns) for turns in range(4) for piece in pieces]


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
    frame = ("in the local (+X, +Z) quadrant, x and z in 0 .. 6.5 (INTERFACES 'Fabric data'), the feature's centre at "
             "the origin corner")
    quarters = {
        "A": (
            f"one quadrant of a large impact crater {frame}: a quarter of its floor, of its rim with the lit crest "
            "and of its central peak, its share of the ejecta apron and rays, and the rubble: a boulder on the "
            "apron, two blocks; regolith-kit is 1 unit = 1 stud, so scale is 1.0",
            [
                placed("crater-quarter", (0, 0, 0)),
                ringed("boulder-medium", 5.6, 60, 25),
                ringed("boulder-small", 2.2, 68, 110),
                ringed("boulder-small", 5.85, 12, 200),
            ],
            "one impact crater 10 studs across its rim, with its apron (four quadrants)",
        ),
        "B": (
            f"one quadrant of a boulder ring round a dust basin {frame}: four boulders of three sizes along a "
            "rough circle of radius 4, one thrown outside it, a darker floor inside; scale 1.0",
            [
                placed("basin-quarter", (0, 0, 0)),
                ringed("boulder-medium", 4.0, 13, 25),
                ringed("boulder-broad", 4.5, 40, 100),
                ringed("boulder-small", 3.7, 63, 40),
                ringed("boulder-small", 4.2, 82, 160),
                ringed("boulder-small", 5.65, 26, 290),
            ],
            "one ring of boulders round a dust basin (four quadrants)",
        ),
        "C": (
            f"one quadrant of a low mound {frame}: a quarter of the mound, its apron with two fans of paler dust "
            "and a rover's ruts wandering round it, a slab of bedrock tilted up toward it, two blocks; scale 1.0",
            [
                placed("mound-quarter", (0, 0, 0)),
                # a slab's tall broken edge is its +Z: turned -(90 + its angle), that edge faces the mound
                ringed("rock-slab", 3.0, 40, 230),
                ringed("boulder-small", 3.3, 78, 15),
                ringed("boulder-small", 5.75, 12, 70),
            ],
            "one low mound with a rover's track round it (four quadrants)",
        ),
    }
    twin = "the twin 'Tend the Rock Gardens' swaps in for"
    gardens = {
        "A": (
            f"{twin} RegolithQuarterA, in its frame: one quadrant of the crater as a raked bowl: a white kerb, sand, "
            "the rim as an even berm with a white crest, three raked rings, a quarter of the crystal at the centre, "
            "one placed stone",
            [
                placed("garden-bowl-quarter", (0, 0, 0)),
                ringed("boulder-small", 5.3, 24, 40),
            ],
            "a raked bowl round a crystal",
        ),
        "B": (
            f"{twin} RegolithQuarterB, in its frame: one quadrant of the boulder ring as a stone circle: a white "
            "kerb, raked sand, three standing stones on the circle of radius 4 (twelve round a clump, evenly), a "
            "quarter of the island stone at the centre, a crystal",
            [
                placed("garden-stones-quarter", (0, 0, 0)),
                ringed("standing-stone-low", 4.0, 15, 20),
                ringed("standing-stone", 4.0, 45, 135),
                ringed("standing-stone-low", 4.0, 75, 250),
            ],
            "a circle of standing stones on raked sand",
        ),
        "C": (
            f"{twin} RegolithQuarterC, in its frame: one quadrant of the mound as a moss garden: a white kerb, "
            "raked sand, the mound in moss with two crystals, five stepping stones where the rover's track ran, one "
            "placed stone",
            [
                placed("garden-moss-quarter", (0, 0, 0)),
                ringed("boulder-small", 5.3, 70, 200),
            ],
            "a moss mound with a stepping path round it",
        ),
    }
    out = []

    def add(bid: str, footprint: list, note: str, pieces: list[dict]) -> None:
        out.append({"id": bid, "era": ERA, "scale": 1.0, "footprint": footprint, "note": note, "pieces": pieces})

    for suffix, designs, outline in (("", quarters, "a ragged round"), (TWIN, gardens, "a true round")):
        for key, (note, pieces, title) in designs.items():
            add(f"RegolithQuarter{key}{suffix}", [13, 13], note, pieces)
            add(f"RegolithClump{key}{suffix}", [13, 13],
                f"exactly RegolithQuarter{key}{suffix} at rotY 0, 90, 180 and 270 about the origin: {title}, {outline} "
                "inside 13 x 13", four_turns(pieces))

    add("RegolithBoulder", [2, 2], "a standing stone over two smaller rocks: the wild's tall accent",
        [placed("boulder-pile", (0, 0, 0))])
    add("RegolithCrater", [3, 3], "a fresh crater with a lit crest, its apron and three blocks of ejecta",
        [placed("crater-fresh", (0, 0, 0))])
    add("SurveyBeacon", [1, 1], "a surveyor's tripod with a lit lamp and an orange tag",
        [placed("survey-beacon", (0, 0, 0))])
    add("RegolithBoulder" + TWIN, [2, 2], f"{twin} RegolithBoulder: a standing stone on a raked disc inside a kerb",
        [placed("stone-garden", (0, 0, 0))])
    add("RegolithCrater" + TWIN, [3, 3],
        f"{twin} RegolithCrater: a raked ring inside a kerb, two crystals at its centre",
        [placed("ring-garden", (0, 0, 0))])
    add("SurveyBeacon" + TWIN, [1, 1], f"{twin} SurveyBeacon: a stone garden lantern on a pad of sand",
        [placed("garden-lantern", (0, 0, 0))])

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
    add("ColonyFlagMast", [1, 1],
        "city-changer 'Raise the Colony Flags': a standard beside a tube between two pods, 5 tall, four pointed "
        "banners (two long orange, two shorter white) hanging from crossed yards; no front",
        [placed("flag-mast", (0, 0, 0))])
    add("PierBanner", [2.4, 2.4],
        "city-changer 'Raise the Colony Flags' on the monorail: origin = a pier foot's centre on the ground, front -Z "
        "(outward from the loop), the kit's pier (monorail-kit) inside it untouched: an orange collar round the shaft "
        "at 4.72 to 4.86 and four banners hanging from it, orange with a white band to the front and back, white "
        "with an orange band along the track",
        [placed("pier-banner", (0, 0, 0))])
    add("HubBeacon", [3.6, 3.6],
        "city-changer 'Light the Holo Beacons': origin = a TubeHub's centre on the ground; everything is at 2.65 or "
        "higher, so it stands on the hub's cap (2.6) without touching it: a mast with a lit dish and a ringed planet "
        "in holo cyan floating over it, 3.6 across its ring, 8.1 at its top; no front",
        [placed("hub-hologram", (0, 0, 0))])
    return out


def blueprint_text(bp: dict) -> str:
    """A blueprint as the repo keeps it: one key per line, one piece per line, LF."""
    lines = ["{"]
    lines += [f'  "{key}": {json.dumps(value)},' for key, value in bp.items() if key != "pieces"]
    lines.append('  "pieces": [')
    lines.append(",\n".join("    " + json.dumps(piece, separators=(", ", ": ")) for piece in bp["pieces"]))
    lines += ["  ]", "}"]
    return "\n".join(lines) + "\n"


def write_blueprints(blueprint_dir: str) -> None:
    os.makedirs(blueprint_dir, exist_ok=True)
    for bp in blueprints():
        path = os.path.join(blueprint_dir, bp["id"] + ".json")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(blueprint_text(bp))
        log(f"wrote {os.path.relpath(path, REPO_ROOT)}")


def seams(faces) -> list[str]:
    """Where a quarter's two inner edges differ. Turned a quarter turn, the edge on x = 0 lies on
    the next copy's z = 0 edge, so what the quarter has at (0, y, t) it must have at (t, y, 0): the
    same corners of the same rim, plates and ruts, or the clump shows a step along its axes."""
    on_x = {(round(q[0], 4), round(q[1], 4)) for points, _ in faces for q in points if abs(q[2]) < 1e-6}
    on_z = {(round(q[2], 4), round(q[1], 4)) for points, _ in faces for q in points if abs(q[0]) < 1e-6}
    return [f"its inner edges differ at {t:g} out, {y:g} up" for t, y in sorted(on_x ^ on_z)[:4]]


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
    """(x0, x1, z0, z1, tallest, triangles) a prop must keep to. A twin keeps to its original's."""
    if bid.endswith(TWIN):
        return limits(bid[:-len(TWIN)])
    if bid.startswith("RegolithClump"):
        return (-EDGE, EDGE, -EDGE, EDGE, WILD_LOW, CLUMP_TRIS)
    if bid.startswith("RegolithQuarter"):
        return (0.0, EDGE, 0.0, EDGE, WILD_LOW, QUARTER_TRIS)
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
    # The city-changers: INTERFACES "Wave 4.1c" and the builder's brief.
    if bid == "ColonyFlagMast":
        return (-0.5, 0.5, -0.5, 0.5, FLAG_MAX, 120)
    if bid == "PierBanner":
        return (-PIER_BANNER_HALF, PIER_BANNER_HALF, -PIER_BANNER_HALF, PIER_BANNER_HALF, PIER_BANNER_MAX, 200)
    if bid == "HubBeacon":
        return (-BEACON_HALF, BEACON_HALF, -BEACON_HALF, BEACON_HALF, BEACON_MAX, 200)
    raise KeyError(bid)


def pier_half(y: float) -> float:
    """How far a face of monorail-kit's pier stands from its axis at height y, at most: the foot,
    the tapering shaft, its collar, the saddle."""
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    import monorail_kit as mk

    if y <= mk.PIER_FOOT_H:
        return mk.PIER_FOOT_HALF
    if y <= mk.PIER_COLLAR[0]:
        share = (y - mk.PIER_FOOT_H) / (mk.PIER_COLLAR[0] - mk.PIER_FOOT_H)
        return mk.PIER_BASE_HALF + (mk.PIER_NECK_HALF - mk.PIER_BASE_HALF) * share
    if y <= mk.PIER_COLLAR[1]:
        return mk.PIER_NECK_HALF + 0.06
    return mk.PIER_CAP_HALF_Z


def check(out_dir: str, blueprint_dir: str) -> tuple[list[str], list[tuple]]:
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
        "SiteSmallGantry", "SiteMedium", "LotBeacon", "RevealScaffold", "ColonyFlagMast", "PierBanner", "HubBeacon"]
    wild = wanted[:9]
    wanted += [name + TWIN for name in wild]
    if sorted(names) != sorted(wanted):
        bad.append(f"the blueprints are {sorted(names)}, not the {len(wanted)} of the contract")
    by_id = {bp["id"]: bp for bp in bps}
    reach = {}
    for bp in bps:
        bid = bp["id"]
        faces = assembled(bp, parts)
        verts = [q for points, _ in faces for q in points]
        lo = [min(q[i] for q in verts) for i in range(3)]
        hi = [max(q[i] for q in verts) for i in range(3)]
        tris = sum(len(points) - 2 for points, _ in faces)
        rows.append((bid, hi[0] - lo[0], hi[2] - lo[2], hi[1], tris))
        reach[bid] = max(math.hypot(q[0], q[2]) for q in verts)
        x0, x1, z0, z1, tallest, budget = limits(bid)
        e = 1e-6
        if lo[0] < x0 - e or hi[0] > x1 + e or lo[2] < z0 - e or hi[2] > z1 + e:
            bad.append(f"{bid} leaves x[{x0:g}, {x1:g}] z[{z0:g}, {z1:g}]: x[{lo[0]:.2f}, {hi[0]:.2f}] "
                       f"z[{lo[2]:.2f}, {hi[2]:.2f}]")
        if lo[1] < -e:
            bad.append(f"{bid} goes {-lo[1]:.2f} under the plot base")
        if bid == "HubBeacon" and lo[1] < HUB_CAP - e:
            bad.append(f"{bid} starts at {lo[1]:.2f}: under {HUB_CAP}, it would stand in the hub it rests on")
        if hi[1] > tallest + e:
            bad.append(f"{bid} is {hi[1]:.2f} tall, over {tallest:g}")
        if budget is not None and tris > budget:
            bad.append(f"{bid} has {tris} triangles, over {budget}")
        for fight in flat_fights(faces, ground=True)[:4]:
            bad.append(f"{bid}: {fight}")
        if bid.startswith("RegolithQuarter"):
            bad += [f"{bid}: {seam}" for seam in seams(faces)]
        if bid == "PierBanner":
            tight = min(max(abs(q[0]), abs(q[2])) - pier_half(q[1]) for q in verts)
            if tight < MIN_GAP - e:
                bad.append(f"{bid} comes {tight:.3f} from the pier's faces, under {MIN_GAP}")
        if bid == "RevealScaffold":
            near = min(max(abs(q[0]), abs(q[2])) for q in verts)
            far = max(hi[0], hi[2], -lo[0], -lo[2])
            if near < RING_NEAR - e or far > RING_FAR + e:
                bad.append(f"{bid} must stand between {RING_NEAR} and {RING_FAR} from the slot's centre: nearest "
                           f"{near:.3f}, farthest {far:.3f}")
        path = os.path.join(blueprint_dir, bid + ".json")
        try:
            with open(path, "r", encoding="utf-8", newline="") as fh:
                on_disk = fh.read()
        except OSError:
            on_disk = None
        if on_disk != blueprint_text(bp):
            state = "is missing" if on_disk is None else "differs from a fresh build"
            bad.append(f"{os.path.relpath(path, REPO_ROOT)} {state}: run without `check`")
    for suffix in ("", TWIN):
        for key in "ABC":
            quarter, clump = f"RegolithQuarter{key}{suffix}", f"RegolithClump{key}{suffix}"
            if quarter not in by_id or clump not in by_id:
                continue
            # A clump is its quarter turned four times: the game breaks it into them.
            if by_id[clump]["pieces"] != four_turns(by_id[quarter]["pieces"]):
                bad.append(f"{clump} is not {quarter} at four quarter turns")
            # So a quarter must leave room for three more.
            tris = next(row[4] for row in rows if row[0] == quarter)
            if 4 * tris > CLUMP_TRIS:
                bad.append(f"{quarter} has {tris} triangles: four of them are over {CLUMP_TRIS}")
    # A twin stands in its original's place: the same footprint, and for a clump or a quarter no
    # farther from its origin, so the swap moves no plate onto a neighbour's.
    for name in wild:
        twin = name + TWIN
        if name not in by_id or twin not in by_id:
            continue
        if by_id[twin]["footprint"] != by_id[name]["footprint"]:
            bad.append(f"{twin} has footprint {by_id[twin]['footprint']}, {name} {by_id[name]['footprint']}")
        if name.startswith(("RegolithClump", "RegolithQuarter")) and reach[twin] > reach[name] + 1e-6:
            bad.append(f"{twin} reaches {reach[twin]:.3f} from its origin, past {name}'s {reach[name]:.3f}")
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
    parser = argparse.ArgumentParser(description="Generate the regolith-kit GLBs and the 28 blueprints; check them.")
    parser.add_argument("command", nargs="?", choices=("build", "check"), default="build",
                        help="build (the default) writes the GLBs and the blueprints, then checks; check only checks")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    parser.add_argument("--only", default="", help="comma list of pieces to rebuild (default: all)")
    parser.add_argument("--blueprints", default=BLUEPRINT_DIR, help="where the 28 blueprints are written and checked")
    args = parser.parse_args(argv)
    if args.command == "build":
        generate(args.out, {name for name in args.only.split(",") if name} or None)
        write_blueprints(args.blueprints)
    problems, rows = check(args.out, args.blueprints)
    for bid, width, depth, height, tris in rows:
        log(f"{bid}: {width:.2f} x {depth:.2f} studs, {height:.2f} tall, {tris} tris")
    for problem in problems:
        log(f"PROBLEM {problem}")
    log(f"check: {len(problems)} problem(s) in {len(rows)} props" if problems else f"check: {len(rows)} props pass")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []))
