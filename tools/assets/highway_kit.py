"""Custom low-poly elevated-highway pieces for Metropolis, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/highway_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/highway-kit/Models/GLB format/, which is the folder
convention every Kenney kit already uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. Same pattern as metro_kit.py, stadium_kit.py, orbital_kit.py.

Why a custom kit at all: city-kit-roads has no viaduct. The kit-assembled props it forced
(`road-bridge` slabs stacked on `bridge-pillar` legs) put a *road tile* -- same asphalt colour,
same kerb, same skirt -- under another road tile, and Ben read the result as exactly that: "just
some street below it to raise it". A viaduct reads as a viaduct because of three things the kit
cannot give: a deck that is visibly a *structure* (a pale box girder hung under a dark
carriageway, the slab cantilevering past it with a shadow line under the overhang), piers that
are columns rather than walls, and a continuous parapet instead of a kerb. The pieces below are
those three things.

Art rules, matching the City Kits: flat shading only (no smooth normals, no bevels, no
subdivision), axis-aligned boxes and swept prisms, chunky toy proportions. Materials are plain
colour factors with no texture, exactly like nature-kit and space-kit; merge_stages.py routes
those through palette.py, which bakes them into one swatch texture at merge time.

**Units: 1 gltf unit = 1 stud**, unlike the Kenney kits (where 1 unit = 4 studs and blueprints use
scale 4.0). Every dimension here is contract-bound (INTERFACES "Elevated highway": 7-stud cells,
deck road surface at 7.07 studs, soffit >= 6), so authoring in studs keeps each literal directly
checkable against that contract. The blueprints therefore use `"scale": 1.0`; anything else
reusing these pieces must do the same.

Geometry is authored in gltf space -- Y up, +X right, -Z front -- with each piece's origin at the
**bottom centre of its first (or only) 7-stud cell at ground level**, which is the origin the
client places a highway prop by. Blender is Z up, so every vertex converts with
(x, y, z) -> (x, -z, y); that map is a proper rotation, so face winding carries over unchanged.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "highway-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# sRGB bytes read straight out of
# assets/kenney3d/city-kit-roads/Models/GLB format/Textures/colormap.png, sampled through the UVs
# of the kit's own road tiles: ASPHALT is the texel road-straight's carriageway lands on and LINE
# the one its centre line lands on, so a deck laid over a tile street carries the same two colours
# as the street. FASCIA is the kit's barrier colour (road-*-barrier); SHADOW and DARK are its two
# darker greys. Keeping to the kit's own texels is what makes the viaduct sit over the 7-stud tile
# streets and beside the 24 Metropolis buildings.
ASPHALT = (102, 107, 128)
LINE = (142, 149, 179)
FASCIA = (160, 168, 201)
RAIL = (189, 198, 238)  # the kit's kerb/pavement tint: the lightest grey road-straight uses
SHADOW = (81, 85, 102)
DARK = (56, 56, 61)

# The whole point of the rebuild is that the viaduct must not read as a second road tile, so the
# five greys are used as a deliberate value ladder stacked in horizontal bands: dark coping, very
# light parapet, light deck fascia, dark drip lip, mid girder, dark soffit.  Flat kit colours have
# no texture to separate them, so this banding is the only thing doing the work at tycoon distance,
# and a first render with the parapet and the fascia both in FASCIA merged them into one tall wall.
COLOURS = {
    "asphalt": ASPHALT,
    "line": LINE,
    "rail": RAIL,  # parapets
    "fascia": FASCIA,  # deck edge and pier caps
    "web": LINE,  # girder web and pier shafts
    "shadow": SHADOW,
    "dark": DARK,
}

# --- the viaduct, in studs ------------------------------------------------------------------
CELL = 7.0  # INTERFACES: tile pitch, one prop per cell
HALF_CELL = CELL / 2.0
DECK_HALF = 3.57  # the deck is 7.14 wide: it cantilevers 0.07 past the cell on every *free*
# edge, so the fascia line of a straight run is unbroken where it meets a corner.  Edges that
# butt a neighbouring cell stop at exactly HALF_CELL, or the two asphalt tops would overlap.

SURFACE = 7.07  # INTERFACES / CityDressing highway.deckHeight -- the one number the client knows
SLAB_T = 0.42  # edge beam: the deck's outer band, and the only part of the structure a low
# camera can see.  0.22 was the first try and the deck read as a sheet of paper: at the tycoon
# camera's ~23 degrees a 0.97-stud cantilever hides anything less than 0.42 deep behind it, so
# the girder's depth has to live in the outer edge, not in the web.
LIP_T = 0.12  # drip lip under the edge beam, in shadow: the dark line that detaches deck from pier
SOFFIT = 6.10  # walkable clearance; the contract floor is 6.0.  A 1.2-deep deck as first
# sketched would have put it at 5.87 and closed the plot entrance, so the girder is 0.97 deep.
WEB_HALF_TOP = 2.75
WEB_HALF_BOT = 2.05  # the box girder tapers: its soffit is narrower than the deck above it

BARRIER_IN = 3.05  # 6.1 studs clear between parapets -- two 2.7-wide Metropolis cars abreast
PARAPET_OUT = DECK_HALF - 0.12  # the parapet stands 0.12 inside the deck edge, so a lit ledge
# separates it from the fascia; flush, the two merged into one 1.1-stud wall and read as a kerb.
BARRIER_H = 0.68
BARRIER_CAP = 0.12  # dark coping; total parapet 0.80 tall, top at 7.87

MARK_LIFT = 0.02  # markings float just above the asphalt rather than z-fighting with it
MARK_HALF = 0.12
EDGE_Z = 2.62  # edge-line centre, half a stud inside the parapet
DASH_LEN = 1.9
DASH_PITCH = CELL / 2.0  # two dashes per cell, so the pattern continues across every joint
JOINT_T = 0.2  # expansion joint at the -X end of every cell

# Ramp: three cells (21 studs), high end at the origin cell's -X edge, descending toward +X.
RAMP_CELLS = 3
RAMP_X0 = -HALF_CELL
RAMP_X1 = RAMP_X0 + RAMP_CELLS * CELL  # 17.5
TOE = 0.07  # the toe sits on the street tile, just clear of it
EASE_LEN = 5.0  # the last stretch is a parabola landing tangent to the street: a straight ramp
# meets the road in a visible crease, and cars never use the ramp anyway (INTERFACES: they loop).
# Constant grade s over (21 - EASE_LEN) plus the parabola's half-drop over EASE_LEN:
RAMP_SLOPE = (SURFACE - TOE) / (RAMP_X1 - RAMP_X0 - EASE_LEN / 2.0)
EASE_X = RAMP_X1 - EASE_LEN
EASE_Y = SURFACE - RAMP_SLOPE * (EASE_X - RAMP_X0)

STRUCT_DEPTH = SURFACE - SOFFIT  # 0.97: slab + lip + girder

# Pier: one central column per cell, well inside the 7.14 band, so the ring reads as a colonnade
# rather than the four corner legs the kit version had.
PIER_PLINTH_HALF = 1.30
PIER_PLINTH_H = 0.35
PIER_FOOT_HALF = 1.15
PIER_NECK_HALF = 0.88
PIER_NECK_Y = 5.35
PIER_CAP_HALF_X = 0.90
PIER_CAP_HALF_Z_BOT = 1.90
PIER_CAP_HALF_Z_TOP = 2.40  # hammerhead: the cap flares out under the girder soffit
PIER_RAMP_BOTTOM = -2.2  # ramp piers are placed by their cap, so their shaft runs below ground


def log(msg: str) -> None:
    print(f"[highway-kit] {msg}", flush=True)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def ramp_surface(x: float) -> float:
    """Road-surface height of the ramp at x. Straight grade, then a parabola tangent at the toe."""
    if x <= EASE_X:
        return SURFACE - RAMP_SLOPE * (x - RAMP_X0)
    d = x - EASE_X
    return EASE_Y - RAMP_SLOPE * d + RAMP_SLOPE * d * d / (2.0 * EASE_LEN)


def ramp_x_at(y: float) -> float:
    """Inverse of ramp_surface on the parabola, used to put a station exactly where a strip
    reaches the ground so the sweep never emits a zero-area quad."""
    inner = 1.0 - 2.0 * (EASE_Y - y) / (RAMP_SLOPE * EASE_LEN)
    return EASE_X + EASE_LEN * (1.0 - math.sqrt(max(0.0, inner)))


# --- mesh building (gltf space) ---------------------------------------------------------------


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
        """Axis-aligned box. `sides` overrides per face: top, bottom, front (-Z), back, left,
        right; a face given None is dropped, because it is buried and would only cost triangles."""
        c = {k: sides.get(k, colour) for k in ("top", "bottom", "front", "back", "left", "right")}
        quads = (
            ("back", [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]),
            ("front", [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)]),
            ("right", [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)]),
            ("left", [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)]),
            ("top", [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)]),
            ("bottom", [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)]),
        )
        for key, pts in quads:
            if c[key] is not None:
                self.face(pts, c[key])

    def frustum(self, y0, y1, hx0, hz0, hx1, hz1, colour, **sides) -> None:
        """Vertical box tapering from (hx0, hz0) half-extents at y0 to (hx1, hz1) at y1."""
        c = {k: sides.get(k, colour) for k in ("top", "bottom", "front", "back", "left", "right")}
        a = [(-hx0, y0, -hz0), (hx0, y0, -hz0), (hx0, y0, hz0), (-hx0, y0, hz0)]
        b = [(-hx1, y1, -hz1), (hx1, y1, -hz1), (hx1, y1, hz1), (-hx1, y1, hz1)]
        quads = (
            ("back", [a[3], a[2], b[2], b[3]]),
            ("front", [a[1], a[0], b[0], b[1]]),
            ("right", [a[2], a[1], b[1], b[2]]),
            ("left", [a[0], a[3], b[3], b[0]]),
            ("top", [b[3], b[2], b[1], b[0]]),
            ("bottom", [a[0], a[1], a[2], a[3]]),
        )
        for key, pts in quads:
            if c[key] is not None:
                self.face(pts, c[key])

    def ribbon(self, path: list[tuple[float, float, float]], half_width: float, colour: str) -> None:
        """A flat, upward-facing strip of quads along `path` ((x, y, z) points): a road marking.

        Single-sided on purpose -- markings are only ever seen from above, and one quad per
        segment keeps a curved lane line inside the triangle budget.
        """
        for i in range(len(path) - 1):
            (x0, y0, z0), (x1, y1, z1) = path[i], path[i + 1]
            dx, dz = x1 - x0, z1 - z0
            length = math.hypot(dx, dz)
            if length < 1e-6:
                continue
            nx, nz = -dz / length * half_width, dx / length * half_width
            self.face(
                [
                    (x0 + nx, y0, z0 + nz),
                    (x1 + nx, y1, z1 + nz),
                    (x1 - nx, y1, z1 - nz),
                    (x0 - nx, y0, z0 - nz),
                ],
                colour,
            )

    def bounds(self) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _ in self.faces)


# --- the deck cross-section, swept along a line of stations -----------------------------------


class Strip:
    """One longitudinal prism of the deck cross-section, offset from the road surface.

    A strip may taper in Z (the girder web) and its Y offsets are clamped at ground level, which
    is what lets one cross-section describe both a level deck and the ramp where it runs into the
    ground.
    """

    def __init__(self, name, z_top, z_bot, dy_top, dy_bot, colours, faces):
        self.name = name
        self.z_top = z_top
        self.z_bot = z_bot
        self.dy_top = dy_top
        self.dy_bot = dy_bot
        self.colours = colours
        self.faces = faces

    def ys(self, surface: float) -> tuple[float, float]:
        bot = max(0.0, surface + self.dy_bot)
        return max(bot, surface + self.dy_top), bot


def deck_strips(z_left: float, z_right: float) -> list[Strip]:
    """The box-girder cross-section between the two deck edges (z_left < z_right)."""
    span = (z_left, z_right)
    return [
        Strip(
            "slab", span, span, 0.0, -SLAB_T,
            {"top": "asphalt", "side": "fascia", "bottom": "shadow"},
            ("top", "side"),  # the lip below has the same outline, so no bottom face
        ),
        Strip(
            "lip", span, span, -SLAB_T, -SLAB_T - LIP_T,
            {"side": "shadow", "bottom": "shadow"},
            ("side", "bottom"),  # its bottom shows outside the girder: the cantilever's shadow
        ),
        Strip(
            "web", (-WEB_HALF_TOP, WEB_HALF_TOP), (-WEB_HALF_BOT, WEB_HALF_BOT),
            -SLAB_T - LIP_T, -STRUCT_DEPTH,
            {"side": "web", "bottom": "shadow"},
            ("side", "bottom"),
        ),
        Strip(
            "parapet-l", (z_left + 0.12, -BARRIER_IN), (z_left + 0.12, -BARRIER_IN),
            BARRIER_H, 0.0, {"side": "rail", "bottom": "rail"}, ("side",),
        ),
        Strip(
            "parapet-r", (BARRIER_IN, z_right - 0.12), (BARRIER_IN, z_right - 0.12),
            BARRIER_H, 0.0, {"side": "rail"}, ("side",),
        ),
        Strip(
            "coping-l", (z_left + 0.12, -BARRIER_IN), (z_left + 0.12, -BARRIER_IN),
            BARRIER_H + BARRIER_CAP, BARRIER_H,
            {"side": "shadow", "top": "shadow"}, ("side", "top"),
        ),
        Strip(
            "coping-r", (BARRIER_IN, z_right - 0.12), (BARRIER_IN, z_right - 0.12),
            BARRIER_H + BARRIER_CAP, BARRIER_H,
            {"side": "shadow", "top": "shadow"}, ("side", "top"),
        ),
    ]


def sweep(part: Part, stations: list[tuple[float, float]], strips: list[Strip]) -> None:
    """Sweep the cross-section along `stations` ((x, road-surface height), in order)."""
    for strip in strips:
        zt0, zt1 = strip.z_top
        zb0, zb1 = strip.z_bot
        live = []  # the segments where the strip still has height, for the end caps
        for i in range(len(stations) - 1):
            (xa, sa), (xb, sb) = stations[i], stations[i + 1]
            ta, ba = strip.ys(sa)
            tb, bb = strip.ys(sb)
            if ta - ba < 1e-6 and tb - bb < 1e-6:
                continue  # the strip has run into the ground
            live.append(((xa, ta, ba), (xb, tb, bb)))
            if "top" in strip.faces:
                part.face(
                    [(xa, ta, zt1), (xb, tb, zt1), (xb, tb, zt0), (xa, ta, zt0)],
                    strip.colours["top"],
                )
            if "bottom" in strip.faces:
                part.face(
                    [(xa, ba, zb0), (xb, bb, zb0), (xb, bb, zb1), (xa, ba, zb1)],
                    strip.colours["bottom"],
                )
            if "side" in strip.faces:
                side = strip.colours["side"]
                part.face([(xa, ba, zb1), (xb, bb, zb1), (xb, tb, zt1), (xa, ta, zt1)], side)
                part.face([(xb, bb, zb0), (xa, ba, zb0), (xa, ta, zt0), (xb, tb, zt0)], side)
        if not live:
            continue
        cap = strip.colours.get("side") or strip.colours.get("top") or "shadow"
        (xa, ta, ba), _ = live[0]
        part.face([(xa, ba, zb0), (xa, ba, zb1), (xa, ta, zt1), (xa, ta, zt0)], cap)
        _, (xb, tb, bb) = live[-1]
        part.face([(xb, bb, zb1), (xb, bb, zb0), (xb, tb, zt0), (xb, tb, zt1)], cap)


def fascia_joint(part: Part, x: float, surface) -> None:
    """A dark notch across the deck edge at a cell boundary, on both fascias.

    Seen from street level the viaduct is one long pale band; the joints are what make it read as
    a segmented structure instead of an endless wall. They stand 0.01 proud of the fascia rather
    than being cut into it, which would need the whole sweep split at every cell.
    """
    y0, y1 = surface(x) - SLAB_T - LIP_T, surface(x + JOINT_T)
    for z, pts in (
        (DECK_HALF + 0.01, [(x, y0), (x + JOINT_T, y0), (x + JOINT_T, y1), (x, y1)]),
        (-DECK_HALF - 0.01, [(x + JOINT_T, y0), (x, y0), (x, y1), (x + JOINT_T, y1)]),
    ):
        part.face([(px, py, z) for px, py in pts], "dark")


def dashes(part: Part, x0: float, x1: float, surface) -> None:
    """Centre-line dashes, two per cell, phased so the pattern runs unbroken across cell joints."""
    k = 0
    while True:
        centre = x0 + DASH_PITCH * (k + 0.5)
        if centre > x1:
            return
        a, b = max(x0, centre - DASH_LEN / 2.0), min(x1, centre + DASH_LEN / 2.0)
        part.ribbon(
            [(a, surface(a) + MARK_LIFT, 0.0), (b, surface(b) + MARK_LIFT, 0.0)], MARK_HALF, "line"
        )
        k += 1


def edge_lines(part: Part, x0: float, x1: float, surface, steps: int = 1) -> None:
    for z in (-EDGE_Z, EDGE_Z):
        path = []
        for i in range(steps + 1):
            x = x0 + (x1 - x0) * i / steps
            path.append((x, surface(x) + MARK_LIFT, z))
        part.ribbon(path, MARK_HALF, "line")


def pier(part: Part, cap_top_x0: float, cap_top_x1: float, bottom: float, plinth: bool) -> None:
    """One column. `cap_top_*` are the cap's top corner heights at -X and +X, so a ramp pier's cap
    top is sloped and meets the sloped soffit flush -- a flat cap under the ramp's grade would
    leave a wedge of daylight on its uphill side."""
    foot = bottom
    if plinth:
        part.box(
            -PIER_PLINTH_HALF, PIER_PLINTH_HALF, bottom, bottom + PIER_PLINTH_H,
            -PIER_PLINTH_HALF, PIER_PLINTH_HALF, "shadow", top=None, bottom=None,
        )
        foot = bottom + PIER_PLINTH_H
    part.frustum(
        foot, PIER_NECK_Y, PIER_FOOT_HALF, PIER_FOOT_HALF, PIER_NECK_HALF, PIER_NECK_HALF,
        "web", top=None, bottom=None,
    )
    # Cap: a hammerhead flaring across the deck, with an explicitly built (possibly sloped) top.
    hx, zb, zt = PIER_CAP_HALF_X, PIER_CAP_HALF_Z_BOT, PIER_CAP_HALF_Z_TOP
    a = [
        (-hx, PIER_NECK_Y, -zb), (hx, PIER_NECK_Y, -zb),
        (hx, PIER_NECK_Y, zb), (-hx, PIER_NECK_Y, zb),
    ]
    b = [
        (-hx, cap_top_x0, -zt), (hx, cap_top_x1, -zt),
        (hx, cap_top_x1, zt), (-hx, cap_top_x0, zt),
    ]
    part.face([a[3], a[2], b[2], b[3]], "fascia")
    part.face([a[1], a[0], b[0], b[1]], "fascia")
    part.face([a[2], a[1], b[1], b[2]], "fascia")
    part.face([a[0], a[3], b[3], b[0]], "fascia")
    part.face([b[3], b[2], b[1], b[0]], "fascia")


# --- the pieces --------------------------------------------------------------------------------


def make_deck_straight() -> Part:
    """One cell of viaduct running along X. 7.0 x 7.14 studs, road surface 7.07, soffit 6.10."""
    p = Part("deck-straight")
    sweep(p, [(-HALF_CELL, SURFACE), (HALF_CELL, SURFACE)], deck_strips(-DECK_HALF, DECK_HALF))
    dashes(p, -HALF_CELL, HALF_CELL, lambda _x: SURFACE)
    edge_lines(p, -HALF_CELL, HALF_CELL, lambda _x: SURFACE)
    # Expansion joint at the -X end only, so a run of cells shows one joint every 7 studs.
    fascia_joint(p, -HALF_CELL, lambda _x: SURFACE)
    p.face(
        [
            (-HALF_CELL, SURFACE + MARK_LIFT, BARRIER_IN),
            (-HALF_CELL + JOINT_T, SURFACE + MARK_LIFT, BARRIER_IN),
            (-HALF_CELL + JOINT_T, SURFACE + MARK_LIFT, -BARRIER_IN),
            (-HALF_CELL, SURFACE + MARK_LIFT, -BARRIER_IN),
        ],
        "dark",
    )
    return p


def square_deck(name: str, x0: float, x1: float, z0: float, z1: float) -> Part:
    """Slab + drip lip + tapered girder block for a junction cell (corner or tee)."""
    p = Part(name)
    p.box(x0, x1, SURFACE - SLAB_T, SURFACE, z0, z1, "fascia", top="asphalt", bottom=None)
    p.box(x0, x1, SURFACE - SLAB_T - LIP_T, SURFACE - SLAB_T, z0, z1, "shadow")
    p.frustum(
        SOFFIT, SURFACE - SLAB_T - LIP_T,
        WEB_HALF_BOT, WEB_HALF_BOT, WEB_HALF_TOP, WEB_HALF_TOP,
        "web", top=None, bottom="shadow",
    )
    return p


def parapet(p: Part, x0: float, x1: float, z0: float, z1: float) -> None:
    p.box(x0, x1, SURFACE, SURFACE + BARRIER_H, z0, z1, "rail", top=None, bottom=None)
    p.box(
        x0, x1, SURFACE + BARRIER_H, SURFACE + BARRIER_H + BARRIER_CAP, z0, z1,
        "shadow", bottom=None,
    )


def arc(radius: float, centre: tuple[float, float], steps: int, t0: float = 0.0, t1: float = 1.0):
    """Quarter turn from the -X edge to the +Z edge, sampled as a polyline at road height."""
    cx, cz = centre
    out = []
    for i in range(steps + 1):
        t = t0 + (t1 - t0) * i / steps
        a = t * math.pi / 2.0
        out.append((cx + radius * math.sin(a), SURFACE + MARK_LIFT, cz - radius * math.cos(a)))
    return out


def make_deck_corner() -> Part:
    """Quarter turn joining -X <-> +Z (the kit's canonical bend orientation).

    The two open edges stop at the cell boundary; the two closed edges carry the parapet and
    cantilever the extra 0.07, so the fascia band continues into the straights either side.
    """
    p = square_deck("deck-corner", -HALF_CELL, DECK_HALF, -DECK_HALF, HALF_CELL)
    parapet(p, BARRIER_IN, PARAPET_OUT, -PARAPET_OUT, HALF_CELL)  # +X side
    parapet(p, -HALF_CELL, BARRIER_IN, -PARAPET_OUT, -BARRIER_IN)  # -Z side
    centre = (-HALF_CELL, HALF_CELL)
    for i in range(3):  # three dashes round the bend, the straight's rhythm carried through
        t0 = (i + 0.12) / 3.0
        p.ribbon(arc(HALF_CELL, centre, 2, t0, t0 + 0.76 / 3.0), MARK_HALF, "line")
    p.ribbon(arc(HALF_CELL - EDGE_Z, centre, 4), MARK_HALF, "line")
    p.ribbon(arc(HALF_CELL + EDGE_Z, centre, 6), MARK_HALF, "line")
    return p


def make_deck_tee() -> Part:
    """Deck T open -X / +X / +Z, closed -Z (the kit's canonical tee orientation)."""
    p = square_deck("deck-tee", -HALF_CELL, HALF_CELL, -DECK_HALF, HALF_CELL)
    parapet(p, -HALF_CELL, HALF_CELL, -PARAPET_OUT, -BARRIER_IN)
    y = SURFACE + MARK_LIFT
    # Through dashes with the junction mouth left clear, as on the ground tiles.
    for a, b in ((-HALF_CELL + 0.1, -1.6), (1.6, HALF_CELL - 0.1)):
        p.ribbon([(a, y, 0.0), (b, y, 0.0)], MARK_HALF, "line")
    p.ribbon([(-HALF_CELL, y, -EDGE_Z), (HALF_CELL, y, -EDGE_Z)], MARK_HALF, "line")
    for x in (-EDGE_Z, EDGE_Z):  # the branch's own edge lines, back to the through carriageway
        p.ribbon([(x, y, 0.9), (x, y, HALF_CELL)], MARK_HALF, "line")
    return p


def ramp_stations() -> list[tuple[float, float]]:
    xs = {RAMP_X0, EASE_X, RAMP_X1}
    for i in range(1, 10):
        xs.add(EASE_X + EASE_LEN * i / 10.0)
    for depth in (STRUCT_DEPTH, SLAB_T + LIP_T, SLAB_T):  # where each strip reaches the ground
        if TOE < depth < EASE_Y:
            xs.add(ramp_x_at(depth))
    return [(x, ramp_surface(x)) for x in sorted(xs)]


def make_deck_ramp() -> Part:
    """The whole three-cell ramp as one piece: deck height at the origin cell's -X edge down to
    the street at +X, the girder thinning into a solid embankment where it meets the ground."""
    p = Part("deck-ramp")
    stations = ramp_stations()
    sweep(p, stations, deck_strips(-DECK_HALF, DECK_HALF))
    for cell in range(RAMP_CELLS):
        fascia_joint(p, RAMP_X0 + cell * CELL, ramp_surface)
    dashes(p, RAMP_X0, RAMP_X1, ramp_surface)
    edge_lines(p, RAMP_X0, RAMP_X1, ramp_surface, steps=len(stations) - 1)
    return p


def make_pier() -> Part:
    """Column under one deck cell: plinth, tapered shaft, hammerhead cap at the 6.10 soffit."""
    p = Part("pier")
    pier(p, SOFFIT, SOFFIT, 0.0, plinth=True)
    return p


def make_pier_ramp() -> Part:
    """Column under the ramp: cap top sloped at the ramp's grade, shaft running below ground so
    the blueprint can drop it to any height without the foot ever showing."""
    p = Part("pier-ramp")
    pier(
        p,
        SOFFIT + RAMP_SLOPE * PIER_CAP_HALF_X,
        SOFFIT - RAMP_SLOPE * PIER_CAP_HALF_X,
        PIER_RAMP_BOTTOM,
        plinth=False,
    )
    return p


PIECES = {
    "deck-straight": make_deck_straight,
    "deck-corner": make_deck_corner,
    "deck-tee": make_deck_tee,
    "deck-ramp": make_deck_ramp,
    "pier": make_pier,
    "pier-ramp": make_pier_ramp,
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
    verts = [(x, -z, y) for (x, y, z) in part.verts]  # gltf -> Blender, a proper rotation
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
    parser = argparse.ArgumentParser(description="Generate the highway-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    log(
        f"grade 1:{1.0 / RAMP_SLOPE:.2f} ({RAMP_SLOPE:.4f}), "
        f"ease from x {EASE_X:.2f} at y {EASE_Y:.3f}"
    )
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
        log(
            f"{name}.glb: {part.tris} tris, {size[0]} x {size[1]} x {size[2]} studs, "
            f"y {lo[1]:.2f}..{hi[1]:.2f}, z {lo[2]:.2f}..{hi[2]:.2f}"
        )
    log(f"{len(PIECES)} pieces, {total} tris total -> {os.path.relpath(args.out, REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
