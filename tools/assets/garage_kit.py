"""Custom low-poly parking-deck pieces for the Metropolis Parking Garage, as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/garage_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/garage-kit/Models/GLB format/, the folder convention
every Kenney kit already uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py discover
the kit with no registration step. assets/ is gitignored, so this script is the committed artifact
and the GLBs regenerate from it. Same pattern as stadium_kit.py, orbital_kit.py and metro_kit.py.

Why a custom kit at all: city-kit-commercial has no open parking deck, no column, no ramp and no
barrier, and every `building-*` is a finished, walled block. The first ParkingGarage blueprint
therefore stacked city-kit-roads `road-bridge` tiles as floors, and Ben read it for exactly what it
was -- "just some streets stacked up". A parking garage reads from three things a road tile cannot
give: open floor plates with a shadow gap between them, short perpendicular bay stripes (never a
road centre line), and a visible ramp. Those are the pieces below.

Art rules, matching the City Kits: flat shading only (no smooth normals, no bevels, no
subdivision), axis-aligned boxes plus a few sloped slabs, chunky toy proportions. Materials are
plain colour factors with no texture, exactly like nature-kit and space-kit; merge_stages.py routes
those through palette.py, which bakes them into one swatch texture at merge time.

**Units: 1 glTF unit = 1 stud**, like metro-kit and unlike the Kenney kits (where 1 unit = 4 studs
and blueprints use scale 4.0). The blueprint therefore uses `"scale": 1.0` and every literal below
is directly checkable against the 9 x 9 stud footprint and the 12-14 stud height target. Anything
else reusing these pieces must do the same.

Geometry is authored in glTF space -- Y up, front -Z (the street side, where the buy pad sits).
Blender is Z up, so every vertex converts with (x, y, z) -> (x, -z, y); that map is a proper
rotation, so face winding carries over unchanged.

**Origins.** The five pieces that exist once per level (`lot`, `deck`, `ramp`) are authored *in
place*: their X/Z is already the plot-local position, so the blueprint places them at x = z = 0 and
only y varies. Everything that repeats (`column`, `core`, `corehead`, `booth`, `barrier`, `sign`,
`floodlight`, `car_*`) is bottom-centre so it can be placed anywhere. `ramp` is the one exception in
Y: its origin sits on the *top surface of its low end*, so the blueprint's y literal is the deck
level it leaves from; its body hangs below that.
"""

from __future__ import annotations

import argparse
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "garage-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# sRGB bytes read straight out of
# assets/kenney3d/city-kit-commercial/Models/GLB format/Textures/colormap.png (verified by texel
# count: WALL/TRIM/MID/SLATE/DARK are the kit's own wall-to-shadow ramp, GLASS its window blue,
# BLUE its one saturated blue, YELLOW its warning amber, GREEN its awning green, RED its stop red).
# Keeping to the kit's own texels is what makes this building sit beside the other 23 Metropolis
# slots without a palette seam.
WALL = (255, 255, 255)
TRIM = (142, 149, 179)
MID = (102, 107, 128)
SLATE = (81, 85, 102)
DARK = (56, 56, 61)
GLASS = (208, 232, 255)
BLUE = (103, 148, 217)
YELLOW = (255, 192, 68)
GREEN = (97, 203, 139)
RED = (207, 83, 79)

COLOURS = {
    "wall": WALL,
    "trim": TRIM,
    "mid": MID,
    "slate": SLATE,
    "dark": DARK,
    "glass": GLASS,
    "blue": BLUE,
    "yellow": YELLOW,
    "green": GREEN,
    "red": RED,
}

# --- the garage, in studs -----------------------------------------------------------------------
# Everything is driven off this block, so the blueprint's y literals can be read straight out of
# the LEVELS list printed at the end of a run.

HALF = 4.49  # half the 9 x 9 footprint, 0.01 inside it (testfit's warning tolerance is 0.01)
BLOCK_X1 = 1.45  # +X edge of the parking block; the ramp strip is BLOCK_X1 .. HALF
LOT_TOP = 0.20  # top of the ground apron
LEVEL = 2.75  # floor to floor: 0.35 slab + 2.40 clear, and a car is 1.75 tall
SLAB = 0.35
PARAPET_H = 0.60  # above the slab top.  Deliberately low: at the ~30 degree testfit/tycoon camera
# a parapet of height h hides about 1.73h of the deck behind it, and the parked cars ARE the
# subject (era-kits memory, the Stadium lesson).  At 0.75 the render showed only the car roofs, as
# flat coloured slabs; 0.60 leaves 1.12 of the 1.72-stud car standing above the rail.
PARAPET_T = 0.25
CAP = 0.12  # trim band on top of each parapet

LANDING = 1.50  # depth of the ramp-strip landing at each end of a deck
RAMP_X0, RAMP_X1 = BLOCK_X1 + 0.10, HALF - 0.10
RAMP_Z = HALF - LANDING + 0.20  # the ramp runs -RAMP_Z .. +RAMP_Z, overlapping each landing by 0.20
RAMP_T = 0.32
RAMP_KERB_H = 0.30
RAMP_KERB_T = 0.24

# Bays run *across* the front (-Z) edge, so a parked car's nose points at the camera and the top
# 0.97 studs of it stand above the 0.75-stud parapet.  The first layout parked them along the -X
# wall, where the render showed nothing but their glass ends: on a 9 x 9 plot the only deck edge a
# car can be read over is the one the camera faces.
BAY_STRIPES = (-4.22, -1.90, 0.42)  # two 2.32-stud bays; the car is 2.06 wide
BAY_LINE_W = 0.15
BAY_Z0, BAY_Z1 = -HALF + 0.23, 0.55

CORE_X0, CORE_X1 = -4.15, -2.05  # stair / lift core, back-left: the front row is the shop window,
CORE_Z0, CORE_Z1 = 1.35, 4.15  # so the core takes the half of the plate the camera cannot see into
CORE_H = LEVEL - 0.13  # one storey, topping out *inside* the slab above so no face is coplanar
COREHEAD_H = 2.45  # roof stair house; embeds 0.05 into the next slab if a deck is added above

LEVELS = [LOT_TOP + LEVEL * i for i in range(5)]  # 0.20, 2.95, 5.70, 8.45, 11.20


def log(msg: str) -> None:
    print(f"[garage-kit] {msg}", flush=True)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


# --- mesh building (glTF space: X right, Y up, Z back; front of a piece faces -Z) ----------------

# Right-handed (U, V, W) frames with W pointing out of the named face, so a counter-clockwise
# (u, v) polygon extruded along +W comes out facing the viewer with correct winding.
FRAMES = {
    "front": ((-1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, -1.0)),
    "back": ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)),
    "right": ((0.0, 0.0, -1.0), (0.0, 1.0, 0.0), (1.0, 0.0, 0.0)),
    "left": ((0.0, 0.0, 1.0), (0.0, 1.0, 0.0), (-1.0, 0.0, 0.0)),
}


class Part:
    """Accumulates flat-shaded polygons tagged with a colour name."""

    def __init__(self, name: str):
        self.name = name
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[list[int], str]] = []

    def face(self, points: list[tuple[float, float, float]], colour: str) -> None:
        base = len(self.verts)
        self.verts.extend(points)
        self.faces.append(([base + i for i in range(len(points))], colour))

    def box(self, x0, x1, y0, y1, z0, z1, colour, **sides) -> None:
        """Axis-aligned box.  `sides` overrides per face: top, bottom, front (-Z), back, left, right."""
        c = {k: sides.get(k, colour) for k in ("top", "bottom", "front", "back", "left", "right")}
        self.face([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], c["back"])
        self.face([(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)], c["front"])
        self.face([(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)], c["right"])
        self.face([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], c["left"])
        self.face([(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)], c["top"])
        self.face([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], c["bottom"])

    def slope(self, x0, x1, z0, z1, ytop0, ytop1, thick, colour, **sides) -> None:
        """Slab whose top surface runs linearly from ytop0 at z0 to ytop1 at z1, `thick` deep.

        Same face names and winding as box(), so the two mix freely.
        """
        c = {k: sides.get(k, colour) for k in ("top", "bottom", "front", "back", "left", "right")}
        a0, a1 = ytop0, ytop1  # top surface at z0 / z1
        b0, b1 = ytop0 - thick, ytop1 - thick  # underside
        self.face([(x0, b1, z1), (x1, b1, z1), (x1, a1, z1), (x0, a1, z1)], c["back"])
        self.face([(x1, b0, z0), (x0, b0, z0), (x0, a0, z0), (x1, a0, z0)], c["front"])
        self.face([(x1, b1, z1), (x1, b0, z0), (x1, a0, z0), (x1, a1, z1)], c["right"])
        self.face([(x0, b0, z0), (x0, b1, z1), (x0, a1, z1), (x0, a0, z0)], c["left"])
        self.face([(x0, a1, z1), (x1, a1, z1), (x1, a0, z0), (x0, a0, z0)], c["top"])
        self.face([(x0, b0, z0), (x1, b0, z0), (x1, b1, z1), (x0, b1, z1)], c["bottom"])

    def extrude(self, poly, centre, frame: str, w0: float, w1: float, colour: str) -> None:
        """Extrude a counter-clockwise (u, v) polygon on one face of a box, `centre` being the
        point on that face the polygon is centred on and w the outward depth."""
        area = sum(
            poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
            for i in range(len(poly))
        )
        assert area > 0, f"{self.name}: polygon must be counter-clockwise, area {area}"
        u_axis, v_axis, w_axis = FRAMES[frame]

        def at(u: float, v: float, w: float) -> tuple[float, float, float]:
            return tuple(centre[i] + u_axis[i] * u + v_axis[i] * v + w_axis[i] * w for i in range(3))

        self.face([at(u, v, w1) for u, v in poly], colour)
        self.face([at(u, v, w0) for u, v in reversed(poly)], colour)
        for i, (u0, v0) in enumerate(poly):
            u1, v1 = poly[(i + 1) % len(poly)]
            self.face([at(u0, v0, w0), at(u1, v1, w0), at(u1, v1, w1), at(u0, v0, w1)], colour)

    def bounds(self) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _ in self.faces)


def letter_p(width: float, height: float) -> list[list[tuple[float, float]]]:
    """A blocky "P" as four *disjoint* rectangles (stem, head, bowl side, bowl bar).

    Disjoint on purpose: a stroked letter built from overlapping bars puts coincident coplanar
    faces on the sign and z-fights there (the metro-kit "M" lesson).
    """
    hw, hh = width / 2.0, height / 2.0
    s = width * 0.30  # stroke
    return [
        [(-hw, -hh), (-hw + s, -hh), (-hw + s, hh), (-hw, hh)],
        [(-hw + s, hh - s), (hw, hh - s), (hw, hh), (-hw + s, hh)],
        [(hw - s, -0.04 * height), (hw, -0.04 * height), (hw, hh - s), (hw - s, hh - s)],
        [(-hw + s, -0.04 * height - s), (hw, -0.04 * height - s), (hw, -0.04 * height), (-hw + s, -0.04 * height)],
    ]


# --- the pieces ---------------------------------------------------------------------------------


def _bay_lines(p: Part, y: float) -> None:
    """The short perpendicular stripes that say "parking" rather than "road".

    Short stripes perpendicular to the front edge, over the -Z half of the plate only, which is
    where the cars park; behind them is the aisle and the core.  No stripe ever runs the length of
    the plate: a continuous centre line is what made the rejected blueprint read as a street.
    """
    for x in BAY_STRIPES:
        p.box(x - BAY_LINE_W / 2, x + BAY_LINE_W / 2, y, y + 0.02, BAY_Z0, BAY_Z1, "wall")


def make_lot() -> Part:
    """Stage 0: the surface car park -- an asphalt apron with a kerb, bay stripes and an entry gap.

    Authored in place: 8.98 x 8.98 studs, 0.20 tall, placed at the blueprint origin.
    """
    p = Part("lot")
    p.box(-HALF, HALF, 0.0, LOT_TOP, -HALF, HALF, "dark", top="slate")
    kerb_t, kerb_h = 0.22, LOT_TOP + 0.14
    p.box(-HALF, -HALF + kerb_t, 0.0, kerb_h, -HALF, HALF, "trim", top="wall")
    p.box(HALF - kerb_t, HALF, 0.0, kerb_h, -HALF, HALF, "trim", top="wall")
    p.box(-HALF, HALF, 0.0, kerb_h, HALF - kerb_t, HALF, "trim", top="wall")
    # The -Z kerb stops short of x = 1.10 so the entry lane (and, from stage 1, the ramp) is open.
    p.box(-HALF, 1.10, 0.0, kerb_h, -HALF, -HALF + kerb_t, "trim", top="wall")
    _bay_lines(p, LOT_TOP)
    return p


def make_deck() -> Part:
    """One open parking floor: 5.94-stud plate down the -X side, a landing at each end of the ramp
    strip, and a low parapet with a trim cap.  The gap between the landings is the ramp well, left
    open on +X so the ramp below is visible from the camera.

    Authored in place; origin y = 0 is the *underside* of the slab, so the blueprint places it at
    (deck top - SLAB).  8.98 x 8.98 x 1.10 studs.
    """
    p = Part("deck")
    top = SLAB
    p.box(-HALF, BLOCK_X1, 0.0, top, -HALF, HALF, "wall", top="mid", bottom="slate")
    p.box(BLOCK_X1, HALF, 0.0, top, -HALF, -HALF + LANDING, "wall", top="mid", bottom="slate")
    p.box(BLOCK_X1, HALF, 0.0, top, HALF - LANDING, HALF, "wall", top="mid", bottom="slate")

    def parapet(x0, x1, z0, z1) -> None:
        p.box(x0, x1, top, top + PARAPET_H - CAP, z0, z1, "wall")
        p.box(x0, x1, top + PARAPET_H - CAP, top + PARAPET_H, z0, z1, "trim")

    parapet(-HALF, -HALF + PARAPET_T, -HALF, HALF)  # -X, the long street face
    parapet(-HALF, HALF, -HALF, -HALF + PARAPET_T)  # -Z front, full width
    parapet(-HALF, HALF, HALF - PARAPET_T, HALF)  # +Z back, full width
    parapet(HALF - PARAPET_T, HALF, -HALF, -HALF + LANDING)  # +X, near landing only
    parapet(HALF - PARAPET_T, HALF, HALF - LANDING, HALF)  # +X, far landing only
    _bay_lines(p, top)
    return p


def make_ramp() -> Part:
    """The sloped slab between two decks, with a kerb up both edges.

    Origin is on the top surface of the LOW end, so the blueprint's y literal is the level the ramp
    leaves from (plus 0.02, to keep it strictly above the landing it starts on and avoid a
    coplanar overlap there).  Rises +LEVEL toward +Z; 2.84 x 6.68 studs, slope 2.75 / 6.38 = 23 deg,
    which is about the camera elevation -- steeper and the deck surface goes edge-on, shallower and
    the landings get too short to support it.
    """
    p = Part("ramp")
    # The ramp deck is a shade lighter than both the "mid" parking floors and the "slate" ground
    # apron: at the low end it lies flush on them, and when all three were the same value only the
    # kerbs showed and the ramp read as a pair of floating rails.
    p.slope(RAMP_X0, RAMP_X1, -RAMP_Z, RAMP_Z, 0.0, LEVEL, RAMP_T, "slate", top="trim", bottom="slate")
    for x0 in (RAMP_X0, RAMP_X1 - RAMP_KERB_T):
        p.slope(
            x0,
            x0 + RAMP_KERB_T,
            -RAMP_Z,
            RAMP_Z,
            RAMP_KERB_H,
            LEVEL + RAMP_KERB_H,
            RAMP_T + RAMP_KERB_H,
            "wall",
            top="trim",
        )
    return p


def make_column() -> Part:
    """Square column, bottom-centre origin.  0.70 x 0.70 x 2.50 studs.

    2.50 = LEVEL - SLAB + 0.10, so placed 0.05 below a deck top it buries both its end faces
    0.05 inside the slabs above and below and never shows a coplanar joint.
    """
    p = Part("column")
    h = LEVEL - SLAB + 0.10
    p.box(-0.35, 0.35, 0.0, h, -0.35, 0.35, "wall")
    p.box(-0.38, 0.38, 0.30, 0.46, -0.38, 0.38, "trim")  # kerb collar, reads as a storey line
    return p


def make_core() -> Part:
    """One storey of the stair / lift core, bottom-centre origin.  2.10 x 2.00 x 2.62 studs.

    Stacks a storey at a time at each deck top; CORE_H stops 0.13 short of the next deck top, so
    the top face finishes inside that slab instead of coplanar with its surface.
    """
    p = Part("core")
    hx, hz = (CORE_X1 - CORE_X0) / 2, (CORE_Z1 - CORE_Z0) / 2
    p.box(-hx, hx, 0.0, CORE_H, -hz, hz, "wall")
    # Glazed stair slit on the two faces the camera can see (-Z and +X), 0.03 proud of the wall.
    p.box(-0.45, 0.45, 0.22, CORE_H - 0.30, -hz - 0.03, -hz, "glass")
    p.box(hx, hx + 0.03, 0.22, CORE_H - 0.30, -0.42, 0.42, "glass")
    return p


def make_corehead() -> Part:
    """Roof stair house that crowns the core, bottom-centre origin.  2.10 x 2.00 x 2.45 studs.

    Sits on a deck top.  If a further deck is later added above it (stage 3 -> 4), 2.45 puts its
    roof 0.05 inside that slab, so it simply becomes another enclosed storey.
    """
    p = Part("corehead")
    hx, hz = (CORE_X1 - CORE_X0) / 2, (CORE_Z1 - CORE_Z0) / 2
    body = COREHEAD_H - 0.35
    p.box(-hx, hx, 0.0, body, -hz, hz, "wall")
    p.box(-0.42, 0.42, 0.0, 1.30, -hz - 0.04, -hz, "dark")  # door
    p.box(-0.50, 0.50, 1.30, 1.46, -hz - 0.06, -hz, "trim")  # door hood
    p.box(hx, hx + 0.03, 0.30, body - 0.30, -0.42, 0.42, "glass")
    p.box(-hx - 0.10, hx + 0.10, body, body + 0.16, -hz - 0.10, hz + 0.10, "trim")  # roof lip
    p.box(-0.55, 0.55, body + 0.16, COREHEAD_H, -0.55, 0.55, "slate")  # lift overrun
    return p


def make_booth() -> Part:
    """Attendant's booth, bottom-centre origin.  1.44 x 1.44 x 2.15 studs (roof lip included)."""
    p = Part("booth")
    h = 0.60
    p.box(-h, h, 0.0, 0.25, -h, h, "slate")
    p.box(-h, h, 0.25, 1.00, -h, h, "wall")
    p.box(-h, h, 1.00, 1.72, -h, h, "glass", top="wall", bottom="wall")
    p.box(-h, h, 1.72, 1.92, -h, h, "wall")
    p.box(-h - 0.12, h + 0.12, 1.92, 2.15, -h - 0.12, h + 0.12, "trim")
    return p


def make_barrier() -> Part:
    """Boom gate.  Origin is the post; the boom reaches 3.35 studs toward +X, 1.22 studs up.

    Striped in the kit's own amber and white -- the City Kits have no red except the stop sign, and
    an amber/white boom is the one unambiguous "this is a car park entrance" prop in the model.
    """
    p = Part("barrier")
    p.box(-0.16, 0.16, 0.0, 1.25, -0.16, 0.16, "slate")
    p.box(-0.20, 0.20, 1.25, 1.38, -0.20, 0.20, "wall")
    segments = 5
    x0, x1 = 0.16, 3.35
    step = (x1 - x0) / segments
    for i in range(segments):
        colour = "yellow" if i % 2 == 0 else "wall"
        p.box(x0 + i * step, x0 + (i + 1) * step, 1.00, 1.22, -0.11, 0.11, colour)
    return p


def make_sign() -> Part:
    """Rooftop "P" pylon, bottom-centre origin.  2.30 x 0.32 x 2.60 studs, "P" on both Z faces."""
    p = Part("sign")
    p.box(-0.18, 0.18, 0.0, 0.95, -0.18, 0.18, "slate")
    p.box(-1.15, 1.15, 0.95, 2.60, -0.16, 0.16, "blue", top="trim")
    for frame, centre in (("front", (0.0, 1.80, -0.16)), ("back", (0.0, 1.80, 0.16))):
        for poly in letter_p(0.80, 1.10):
            p.extrude(poly, centre, frame, 0.0, 0.05, "wall")
    return p


def make_floodlight() -> Part:
    """Roof-deck mast light, bottom-centre origin.  0.56 x 0.36 x 2.20 studs, lit face down."""
    p = Part("floodlight")
    p.box(-0.09, 0.09, 0.0, 1.90, -0.09, 0.09, "slate")
    p.box(-0.28, 0.28, 1.90, 2.20, -0.18, 0.18, "wall", bottom="yellow")
    return p


def make_car(name: str, colour: str) -> Part:
    """A parked toy car, bottom-centre origin, nose toward -Z.  2.00 x 1.75 x 4.40 studs.

    2.06 studs wide so two park side by side in the 5.94-stud plate with a 0.34 gap, and 4.42 long
    so the nose sits against the front parapet with the tail clear of the aisle.

    The cabin roof is slate while the bonnet and boot carry the car's colour.  A one-colour car is
    what the first render produced, and seen from the tycoon camera -- which looks down on the roof
    -- it was a flat coloured rectangle with no car in it; the dark band puts the three-box shape
    back.
    """
    p = Part(name)
    p.box(-0.92, 0.92, 0.40, 1.15, -2.21, 2.21, colour, bottom="dark")
    p.box(-0.84, 0.84, 1.15, 1.72, -0.55, 1.35, colour, top="slate", front="glass", back="glass", left="glass", right="glass")
    for sx in (-1.0, 1.0):
        for cz in (-1.35, 1.35):
            p.box(sx * 0.95 - 0.08, sx * 0.95 + 0.08, 0.0, 0.62, cz - 0.45, cz + 0.45, "dark")
    for sx in (-1.0, 1.0):
        p.box(sx * 0.58 - 0.22, sx * 0.58 + 0.22, 0.78, 0.98, -2.23, -2.19, "wall")  # headlights
    return p


PIECES = {
    "lot": make_lot,
    "deck": make_deck,
    "ramp": make_ramp,
    "column": make_column,
    "core": make_core,
    "corehead": make_corehead,
    "booth": make_booth,
    "barrier": make_barrier,
    "sign": make_sign,
    "floodlight": make_floodlight,
    "car_blue": lambda: make_car("car_blue", "blue"),
    "car_amber": lambda: make_car("car_amber", "yellow"),
    "car_green": lambda: make_car("car_green", "green"),
    "car_red": lambda: make_car("car_red", "red"),
}


# --- Blender plumbing ---------------------------------------------------------------------------


def material_for(name: str, cache: dict):
    if name in cache:
        return cache[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    r, g, b = COLOURS[name]
    bsdf.inputs["Base Color"].default_value = (
        srgb_to_linear(r),
        srgb_to_linear(g),
        srgb_to_linear(b),
        1.0,
    )
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    cache[name] = mat
    return mat


def build_object(part: Part, cache: dict):
    used = sorted({c for _, c in part.faces})
    mesh = bpy.data.meshes.new(part.name)
    verts = [(x, -z, y) for (x, y, z) in part.verts]  # glTF -> Blender, a proper rotation
    mesh.from_pydata(verts, [], [idx for idx, _ in part.faces])
    mesh.update()
    for name in used:
        mesh.materials.append(material_for(name, cache))
    slot = {name: i for i, name in enumerate(used)}
    for poly, (_, colour) in zip(mesh.polygons, part.faces):
        poly.material_index = slot[colour]
        poly.use_smooth = False
    mesh.uv_layers.new(name="UVMap")  # merge_stages moves these onto the palette swatch
    obj = bpy.data.objects.new(part.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj, out_dir: str) -> None:
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(out_dir, f"{obj.name}.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_vertex_color="NONE",
        export_attributes=False,
        export_extras=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_cameras=False,
        export_lights=False,
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the garage-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    total = 0
    for name, make in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        cache: dict = {}
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        obj = build_object(part, cache)
        export(obj, args.out)
        total += part.tris
        lo, hi = part.bounds()
        size = tuple(round(hi[i] - lo[i], 2) for i in range(3))
        log(f"{name}.glb: {part.tris} tris, {size[0]} x {size[1]} x {size[2]} studs, min y {lo[1]:.2f}")
    log("deck tops: " + ", ".join(f"{y:.2f}" for y in LEVELS))
    log(f"{len(PIECES)} pieces, {total} tris total -> {os.path.relpath(args.out, REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
