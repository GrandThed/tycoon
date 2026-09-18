"""Custom low-poly space pieces for Orbital Colony, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/orbital_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/orbital-kit/Models/GLB format/, which is the folder
convention every Kenney kit already uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it.

Why a custom kit at all: space-kit is the only kit for the Orbital Colony era and it has no solar
panel, no flag, no hologram, no vertical tank and no drill derrick -- the five things a colony
silhouette needs most. Its one dome/glass piece, `hangar_roundGlass`, is near-black and 13 studs
wide, and the Orbital plot base is RGB (56, 53, 60), so that dome disappears into the ground.
Every piece here is therefore bright: white hulls, amber trim, light-blue glass. Ben approved
generating them on 2026-09-18.

Art rules, matching the kit: flat shading only (no smooth normals, no bevels, no subdivision),
chunky toy proportions, round things faceted to 8 sides with the flats squared to the axes (the
same silhouette as `hangar_roundA` and `satelliteDish_large`). Materials are plain colour factors
with no texture, exactly like nature-kit and space-kit; merge_stages.py routes those through
palette.py, which bakes them into one swatch texture at merge time.

Geometry is authored in glTF space -- Y up, front -Z, 1 unit = 4 studs at the blueprint's scale
4.0 -- and every piece is recentred to **bottom-centre origin** (XZ bbox centre at 0, min Y at 0),
unlike space-kit's own pieces, which all sit at roughly (+2.0, +1.5). Blender is Z up, so every
vertex converts with (x, y, z) -> (x, -z, y); that map is a proper rotation, so face winding
carries over unchanged. Every face below is wound counter-clockwise seen from outside.
"""

from __future__ import annotations

import argparse
import contextlib
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "orbital-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# The first seven are space-kit's own material colour factors, read out of the GLB JSON chunks of
# assets/kenney3d/space-kit/Models/GLTF format/*.glb.  Kenney wrote sRGB values straight into those
# factors (raw x 255 matches the kit's own Isometric previews; decoding them as linear, as the glTF
# spec says, gives a washed-out amber and a mid-grey "dark"), so these are raw x 255 and
# palette.py writes space-kit's swatches the same way.  Using the same numbers is what makes these
# pieces sit beside the real space-kit models instead of looking imported.
HULL = (215, 222, 232)  # space-kit "metal"      -- the white hull, on 123 models
PANEL = (172, 181, 197)  # space-kit "metalDark"  -- the slightly darker hull panel
TRIM = (255, 160, 52)  # space-kit "metalRed"   -- the orange trim band
SLATE = (70, 76, 87)  # space-kit "dark"       -- recesses, visors, skirts
ROCK = (232, 132, 99)  # space-kit "rock"       -- salmon terrain
ROCK_DARK = (178, 95, 67)  # space-kit "rockDark"
CRYSTAL = (47, 224, 151)  # space-kit "crystal" -- kept for reference; HOLO below is its sibling

# New accents.  The kit has no glass, no photovoltaic blue, no greenery and no lit window, and every
# one of those has to read against a near-black plot base, so all of them are bright.
GLASS = (150, 215, 255)
GLASS_DEEP = (90, 170, 235)
SOLAR = (40, 90, 200)
SOLAR_LINE = (112, 160, 235)
HOLO = (90, 255, 245)
PLANT = (97, 203, 139)
LIT = (255, 225, 140)
# The only derived colour: metalRed pushed darker and more saturated, because a warning beacon that
# matches the trim band it sits on stops reading as a warning beacon.
WARN = (232, 120, 74)

COLOURS = {
    "hull": HULL,
    "panel": PANEL,
    "trim": TRIM,
    "slate": SLATE,
    "rock": ROCK,
    "rock-dark": ROCK_DARK,
    "crystal": CRYSTAL,
    "glass": GLASS,
    "glass-deep": GLASS_DEEP,
    "solar": SOLAR,
    "solar-line": SOLAR_LINE,
    "holo": HOLO,
    "plant": PLANT,
    "lit": LIT,
    "warn": WARN,
}

SEGMENTS = 8
PHASE = 22.5  # vertex angles at 22.5 + 45k, so the eight flats square up to +-X / +-Z
# An 8-gon of circumradius r measures 2 * r * cos(22.5 deg) across its flats, which is the bbox the
# testfit footprint check and the piece-size contract both use.
FLAT = math.cos(math.radians(PHASE))

# Contract sizes the three Orbital blueprint builders already hold (X x Y x Z in kit units).
# main() prints the measured bbox against these and warns past the agreed +-0.05.
NOMINAL = {
    "dome_small": (1.00, 0.55, 1.00),
    "dome_medium": (1.60, 0.85, 1.60),
    "dome_large": (2.10, 1.10, 2.10),
    "dome_slit": (1.60, 0.85, 1.60),
    "drum_medium": (1.60, 0.40, 1.60),
    "drum_large": (2.10, 0.40, 2.10),
    "telescope": (0.35, 0.80, 0.90),
    "planter_tray": (1.00, 0.22, 0.35),
    "solar_panel": (1.00, 0.60, 0.70),
    "solar_panel_flat": (1.00, 0.05, 0.50),
    "solar_tracker": (1.80, 1.50, 0.50),
    "flag": (0.75, 1.60, 0.06),
    "holo_beacon": (0.70, 1.50, 0.70),
    "mast_segment": (0.24, 1.00, 0.24),
    "mast_tip": (0.60, 0.60, 0.60),
    "tank_vertical": (0.55, 1.25, 0.55),
    "tank_sphere": (0.90, 1.00, 0.90),
    "energy_core": (0.70, 1.10, 0.70),
    "drill_rig": (0.90, 2.00, 0.90),
    "light_panel": (0.80, 0.18, 0.03),
    "pad_marking": (1.60, 0.02, 1.60),
}
TOLERANCE = 0.05


def log(msg: str) -> None:
    print(f"[orbital-kit] {msg}", flush=True)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def radius_for_width(width: float) -> float:
    """Circumradius of an 8-gon whose flat-to-flat width is `width`."""
    return width / 2.0 / FLAT


# --- transforms (3x4 row-major; rotations are proper, so face winding survives) -----------------

IDENTITY = ((1.0, 0.0, 0.0, 0.0), (0.0, 1.0, 0.0, 0.0), (0.0, 0.0, 1.0, 0.0))


def mat_mul(a, b):
    return tuple(
        tuple(sum(a[i][k] * b[k][j] for k in range(3)) + (a[i][3] if j == 3 else 0.0) for j in range(4))
        for i in range(3)
    )


def translate(tx: float, ty: float, tz: float):
    return ((1.0, 0.0, 0.0, tx), (0.0, 1.0, 0.0, ty), (0.0, 0.0, 1.0, tz))


def rot_x(deg: float):
    """Positive angle lifts the -Z end, which is how every tilted piece here is described."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((1.0, 0.0, 0.0, 0.0), (0.0, c, -s, 0.0), (0.0, s, c, 0.0))


def rot_y(deg: float):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((c, 0.0, s, 0.0), (0.0, 1.0, 0.0, 0.0), (-s, 0.0, c, 0.0))


def rot_z(deg: float):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((c, -s, 0.0, 0.0), (s, c, 0.0, 0.0), (0.0, 0.0, 1.0, 0.0))


# --- mesh building (glTF space: X right, Y up, Z back; front of a piece faces -Z) --------------


class Part:
    """Accumulates flat-shaded polygons tagged with a colour name, through a transform stack."""

    def __init__(self, name: str):
        self.name = name
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[list[int], str]] = []
        self._stack = [IDENTITY]

    @contextlib.contextmanager
    def xform(self, *mats):
        m = self._stack[-1]
        for k in mats:
            m = mat_mul(m, k)
        self._stack.append(m)
        try:
            yield
        finally:
            self._stack.pop()

    def face(self, points, colour: str) -> None:
        m = self._stack[-1]
        base = len(self.verts)
        for x, y, z in points:
            self.verts.append(
                (
                    m[0][0] * x + m[0][1] * y + m[0][2] * z + m[0][3],
                    m[1][0] * x + m[1][1] * y + m[1][2] * z + m[1][3],
                    m[2][0] * x + m[2][1] * y + m[2][2] * z + m[2][3],
                )
            )
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

    def plate(self, x0, x1, z0, z1, y, colour) -> None:
        """One upward-facing quad -- pad markings and solar cells, which are only seen from above."""
        self.face([(x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0)], colour)

    def ring(self, r_in, r_out, y, colour, segments=24, cx=0.0, cz=0.0, phase=0.0) -> None:
        """Upward-facing annulus; pass r_in > r_out to face it downward."""
        for i in range(segments):
            a0 = math.radians(phase) + 2 * math.pi * i / segments
            a1 = math.radians(phase) + 2 * math.pi * (i + 1) / segments
            outer = [(cx + r_out * math.sin(a), y, cz + r_out * math.cos(a)) for a in (a0, a1)]
            inner = [(cx + r_in * math.sin(a), y, cz + r_in * math.cos(a)) for a in (a1, a0)]
            self.face(outer + inner, colour)

    # --- lathed solids: every faceted round piece in the kit comes out of this one call ---------

    def lathe(self, profile, colour, cap_top=None, cap_bottom=None, cx=0.0, cz=0.0) -> None:
        """Revolve a (radius, y) profile into an 8-sided solid, bottom to top.

        `colour` is a name, a list indexed by facet (alternating glass panes) or a callable
        (facet, band) -> name.  A profile endpoint with radius 0 closes into a cone, so a
        [(0, y0), (r, ym), (0, y1)] profile is the kit's faceted diamond.  Caps are emitted as a
        triangle fan when the colour varies by facet, so one facet can be recoloured (the
        observatory slit) without a second mesh.
        """

        def hue(k: int, i: int) -> str:
            if callable(colour):
                return colour(k, i)
            if isinstance(colour, (list, tuple)):
                return colour[k % len(colour)]
            return colour

        def pt(k: int, i: int):
            r, y = profile[i]
            a = math.radians(PHASE + 360.0 * k / SEGMENTS)
            return (cx + r * math.sin(a), y, cz + r * math.cos(a))

        for i in range(len(profile) - 1):
            r0, r1 = profile[i][0], profile[i + 1][0]
            for k in range(SEGMENTS):
                a, b = pt(k, i), pt(k + 1, i)
                c, d = pt(k + 1, i + 1), pt(k, i + 1)
                if r0 <= 1e-6:
                    self.face([a, c, d], hue(k, i))
                elif r1 <= 1e-6:
                    self.face([a, b, pt(0, i + 1)], hue(k, i))
                else:
                    self.face([a, b, c, d], hue(k, i))
        if cap_top is not None and profile[-1][0] > 1e-6:
            i = len(profile) - 1
            if callable(cap_top) or isinstance(cap_top, (list, tuple)):
                centre = (cx, profile[-1][1], cz)
                for k in range(SEGMENTS):
                    name = cap_top(k) if callable(cap_top) else cap_top[k % len(cap_top)]
                    self.face([pt(k, i), pt(k + 1, i), centre], name)
            else:
                self.face([pt(k, i) for k in range(SEGMENTS)], cap_top)
        if cap_bottom is not None and profile[0][0] > 1e-6:
            self.face([pt(SEGMENTS - k, 0) for k in range(SEGMENTS)], cap_bottom)

    def facet_panel(self, r, y0, y1, facet, half_width, out, colour) -> None:
        """Outward-facing quad glued to one of the eight flats -- lit windows, dome panes.

        Single-sided on purpose: it always sits on a closed solid, so its back is never visible,
        and a quad costs two triangles where an extruded slab costs twelve.
        """
        c = math.radians(45.0 * facet + 45.0)  # centre of facet k, +Z at facet 7/-1, -Z at facet 3
        n = (math.sin(c), 0.0, math.cos(c))
        t = (math.cos(c), 0.0, -math.sin(c))
        d = r * FLAT + out
        corner = lambda s, y: (n[0] * d + t[0] * s * half_width, y, n[2] * d + t[2] * s * half_width)
        self.face([corner(-1, y0), corner(1, y0), corner(1, y1), corner(-1, y1)], colour)

    def meridian_ribs(self, profile, colour, out=0.012, half_deg=2.6, skip=()) -> None:
        """Thin white strips down the eight meridians of a dome, offset just clear of the surface."""
        for k in range(SEGMENTS):
            if k in skip:
                continue
            a = math.radians(PHASE + 360.0 * k / SEGMENTS)
            for i in range(len(profile) - 1):
                if profile[i][0] <= 1e-6 and profile[i + 1][0] <= 1e-6:
                    continue
                quad = []
                for side, idx in ((-1, i), (1, i), (1, i + 1), (-1, i + 1)):
                    r, y = profile[idx]
                    aa = a + side * math.radians(half_deg)
                    rr = r + out
                    quad.append((rr * math.sin(aa), y, rr * math.cos(aa)))
                self.face(quad, colour)

    def bbox(self):
        xs = [v[0] for v in self.verts]
        ys = [v[1] for v in self.verts]
        zs = [v[2] for v in self.verts]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def recenter(self):
        """Move the piece to bottom-centre origin and report the shift that was applied."""
        (x0, y0, z0), (x1, _, z1) = self.bbox()
        dx, dy, dz = -(x0 + x1) / 2.0, -y0, -(z0 + z1) / 2.0
        self.verts = [(x + dx, y + dy, z + dz) for (x, y, z) in self.verts]
        return dx, dy, dz


def dome_profile(r, y0, y1, bands, a_max=72.0):
    """Faceted hemisphere flattened into `bands` latitude rings, stopping short of the pole so the
    dome closes with a white cap disc rather than a spike."""
    amax = math.radians(a_max)
    return [
        (r * math.cos(amax * i / bands), y0 + (y1 - y0) * math.sin(amax * i / bands) / math.sin(amax))
        for i in range(bands + 1)
    ]


def sphere_profile(r, y0, y1, bands=4, a_max=68.0):
    amax = math.radians(a_max)
    cy, ry = (y0 + y1) / 2.0, (y1 - y0) / 2.0
    return [
        (r * math.cos(-amax + 2 * amax * i / bands), cy + ry * math.sin(-amax + 2 * amax * i / bands) / math.sin(amax))
        for i in range(bands + 1)
    ]


def cell_grid(part: Part, x0, x1, z0, z1, y, cols, rows, colour, gap=0.03) -> None:
    """Photovoltaic cells as upward plates, leaving the panel's own top colour showing as grid lines."""
    for i in range(cols):
        for j in range(rows):
            cx0 = x0 + (x1 - x0) * i / cols + gap / 2
            cx1 = x0 + (x1 - x0) * (i + 1) / cols - gap / 2
            cz0 = z0 + (z1 - z0) * j / rows + gap / 2
            cz1 = z0 + (z1 - z0) * (j + 1) / rows - gap / 2
            part.plate(cx0, cx1, cz0, cz1, y, colour)


# --- domes and drums ----------------------------------------------------------------------------

PANES = ["glass", "glass-deep"]


def _dome(name: str, width: float, height: float, bands: int, base_h: float) -> Part:
    p = Part(name)
    r_base = radius_for_width(width)
    r_dome = radius_for_width(width - 0.06)
    # The base ring closes with its own top disc and the dome's open rim sinks 0.015 into it, so
    # the two never leave coincident horizontal faces to z-fight.
    p.lathe([(r_base, 0.0), (r_base, base_h)], "hull", cap_top="hull", cap_bottom="hull")
    prof = dome_profile(r_dome, base_h - 0.015, height, bands)
    p.lathe(prof, PANES, cap_top="hull")
    p.meridian_ribs(prof, "hull")
    return p


def make_dome_small() -> Part:
    return _dome("dome_small", 1.00, 0.55, 2, 0.08)


def make_dome_medium() -> Part:
    return _dome("dome_medium", 1.60, 0.85, 2, 0.10)


def make_dome_large() -> Part:
    return _dome("dome_large", 2.10, 1.10, 3, 0.12)


def make_dome_slit() -> Part:
    """Observatory: white panels, amber rim, and one dark facet running from the rim over the cap.

    The shutter is facet 3, which `facet_panel`'s numbering puts dead centre on -Z, so a builder
    that places this dome at rotY 0 gets the telescope opening facing the camera and the street.
    """
    p = Part("dome_slit")
    r_base = radius_for_width(1.60)
    r_dome = radius_for_width(1.54)
    p.lathe([(r_base, 0.0), (r_base, 0.05)], "hull", cap_bottom="hull")
    p.lathe([(r_base, 0.05), (r_base, 0.13)], "trim", cap_top="trim")  # rim band
    prof = dome_profile(r_dome, 0.115, 0.85, 2)
    shell = ["hull", "panel", "hull", "slate", "hull", "panel", "hull", "panel"]
    p.lathe(prof, shell, cap_top=lambda k: "slate" if k == 3 else "hull")
    p.meridian_ribs(prof, "panel", skip=())
    return p


def _drum(name: str, width: float) -> Part:
    """Plinth for a dome of the same nominal width: flat top and bottom, amber band, lit windows."""
    p = Part(name)
    r = radius_for_width(width - 0.04)
    r_band = radius_for_width(width)
    p.lathe([(r, 0.0), (r, 0.40)], "hull", cap_top="panel", cap_bottom="hull")
    # Band low and windows high: LIT and TRIM are only 20 sRGB steps apart, so at 1.6 studs tall
    # they merge into one yellow stripe unless the white hull separates them.
    p.lathe([(r_band, 0.02), (r_band, 0.08)], "trim")
    for k in range(SEGMENTS):
        p.facet_panel(r, 0.18, 0.32, k, width * 0.15, 0.010, "lit")
    return p


def make_drum_medium() -> Part:
    return _drum("drum_medium", 1.60)


def make_drum_large() -> Part:
    return _drum("drum_large", 2.10)


# --- the rest of the kit --------------------------------------------------------------------------


def make_telescope() -> Part:
    """Tube tilted 40 degrees up toward -Z on a yoke; the dark lens is the piece's -Z-most point."""
    p = Part("telescope")
    p.box(-0.16, 0.16, 0.00, 0.05, -0.16, 0.16, "slate", top="panel")
    for side in (-1, 1):
        cx = side * 0.145
        p.box(cx - 0.03, cx + 0.03, 0.05, 0.40, -0.06, 0.06, "hull")
    with p.xform(translate(0.0, 0.34, 0.0), rot_x(40.0)):
        # Slim and long: a fat tube at this tilt foreshortens into a cube from the testfit camera.
        p.box(-0.085, 0.085, -0.085, 0.085, -0.66, 0.22, "hull")
        p.box(-0.105, 0.105, -0.105, 0.105, -0.12, 0.00, "trim")  # focuser ring
        p.box(-0.105, 0.105, -0.105, 0.105, -0.44, -0.38, "panel")  # tube collar
        p.box(-0.072, 0.072, -0.072, 0.072, -0.70, -0.66, "slate")  # lens
        p.box(-0.07, 0.07, -0.07, 0.07, 0.22, 0.30, "panel")  # counterweight
    return p


def make_planter_tray() -> Part:
    """Hydroponics trough: five chunky shrubs, the only green in the era."""
    p = Part("planter_tray")
    p.box(-0.50, 0.50, 0.00, 0.13, -0.175, 0.175, "hull", top="panel")
    p.box(-0.44, 0.44, 0.10, 0.15, -0.125, 0.125, "rock-dark")
    p.box(-0.50, 0.50, 0.03, 0.06, -0.18, 0.18, "trim")
    for i in range(5):
        cx = -0.36 + 0.18 * i
        h = 0.22 if i % 2 == 0 else 0.195
        p.box(cx - 0.030, cx + 0.030, 0.13, h - 0.07, -0.030, 0.030, "plant")
        p.lathe([(0.055, h - 0.09), (0.085, h - 0.06), (0.0, h)], "plant", cx=cx)
    return p


def _panel_face(p: Part, hx: float, hz: float, thickness: float, cols: int, rows: int) -> None:
    """A photovoltaic slab centred on the local origin, cells on its +Y face."""
    p.box(-hx, hx, -thickness, thickness, -hz, hz, "hull", top="solar-line")
    cell_grid(p, -hx + 0.03, hx - 0.03, -hz + 0.03, hz - 0.03, thickness + 0.008, cols, rows, "solar")


def make_solar_panel() -> Part:
    """Ground array: the cell face looks up and toward -Z, so the high edge is on +Z."""
    p = Part("solar_panel")
    p.box(-0.16, 0.16, 0.00, 0.05, -0.16, 0.16, "slate", top="panel")
    p.box(-0.07, 0.07, 0.00, 0.34, -0.07, 0.07, "hull")
    p.box(-0.09, 0.09, 0.26, 0.31, -0.09, 0.09, "trim")
    with p.xform(translate(0.0, 0.38, 0.0), rot_x(-30.0)):
        _panel_face(p, 0.50, 0.39, 0.022, 4, 2)
    return p


def make_solar_panel_flat() -> Part:
    """Roof array, same cell look, flat enough to sit on any hull without lifting a silhouette."""
    p = Part("solar_panel_flat")
    p.box(-0.50, 0.50, 0.00, 0.04, -0.25, 0.25, "hull", top="solar-line")
    cell_grid(p, -0.46, 0.46, -0.21, 0.21, 0.045, 4, 2, "solar")
    return p


def make_solar_tracker() -> Part:
    """Mast with two wings; both cell faces look up and toward -Z, like solar_panel."""
    p = Part("solar_tracker")
    p.box(-0.14, 0.14, 0.00, 0.06, -0.14, 0.14, "slate", top="panel")
    p.box(-0.08, 0.08, 0.00, 1.35, -0.08, 0.08, "hull")
    p.box(-0.105, 0.105, 0.70, 0.82, -0.105, 0.105, "trim")
    p.box(-0.13, 0.13, 1.26, 1.33, -0.13, 0.13, "panel")
    for side in (-1, 1):
        with p.xform(translate(side * 0.51, 1.35, 0.0), rot_x(-25.0)):
            _panel_face(p, 0.39, 0.25, 0.022, 3, 2)
    return p


def make_flag() -> Part:
    """Colony flag.  The cloth runs toward +X from the pole, so the pole ends up off-centre once the
    piece is recentred -- main() prints the pole's local x for the builders."""
    p = Part("flag")
    p.box(-0.10, 0.10, 0.00, 0.05, -0.03, 0.03, "slate", top="panel")
    p.box(-0.025, 0.025, 0.00, 1.52, -0.025, 0.025, "hull")
    p.box(-0.030, 0.030, 1.50, 1.56, -0.030, 0.030, "trim")
    p.lathe([(0.0325, 1.56), (0.0, 1.60)], "trim", cap_bottom="trim")
    p.box(0.02, 0.65, 1.10, 1.17, -0.01, 0.01, "trim")
    p.box(0.02, 0.65, 1.17, 1.25, -0.01, 0.01, "hull")
    p.box(0.02, 0.65, 1.25, 1.46, -0.01, 0.01, "trim")
    disc = [
        (0.32 + 0.08 * math.cos(math.radians(a)), 1.355 + 0.08 * math.sin(math.radians(a)))
        for a in range(0, 360, 45)
    ]
    p.face([(x, y, 0.016) for x, y in disc], "hull")  # +Z face: CCW in XY is the outward winding
    p.face([(x, y, -0.016) for x, y in reversed(disc)], "hull")
    return p


def make_holo_beacon() -> Part:
    """Emitter pad, a widening cyan beam and a floating diamond inside two rings."""
    p = Part("holo_beacon")
    r_pad = radius_for_width(0.70)
    p.lathe([(r_pad, 0.0), (r_pad, 0.14)], "hull", cap_bottom="hull")
    p.lathe([(r_pad, 0.14), (r_pad, 0.20)], "trim", cap_top="slate")
    p.lathe([(0.10, 0.22), (0.30, 1.02)], "holo", cap_top="holo", cap_bottom="holo")
    p.lathe([(0.0, 1.10), (0.20, 1.30), (0.0, 1.50)], "holo")
    for y in (1.22, 1.38):
        r_in, r_out = 0.255, 0.30
        p.lathe([(r_out, y - 0.015), (r_out, y + 0.015)], "holo")
        p.lathe([(r_in, y + 0.015), (r_in, y - 0.015)], "holo")  # descending profile = inward faces
        p.ring(r_in, r_out, y + 0.015, "holo", segments=SEGMENTS, phase=PHASE)
        p.ring(r_out, r_in, y - 0.015, "holo", segments=SEGMENTS, phase=PHASE)
    return p


def make_mast_segment() -> Part:
    """Stacks exactly every 1.0.  Four corner posts plus banded collars read as a lattice; true X
    braces across a 0.24-wide bay come out nearly vertical and just add noise."""
    p = Part("mast_segment")
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box(sx * 0.085 - 0.025, sx * 0.085 + 0.025, 0.0, 1.0, sz * 0.085 - 0.025, sz * 0.085 + 0.025, "hull")
    p.box(-0.045, 0.045, 0.0, 1.0, -0.045, 0.045, "panel")  # core, so the mast is never see-through
    for y0, y1, colour in ((0.00, 0.06, "hull"), (0.47, 0.53, "trim"), (0.94, 1.00, "hull")):
        # Collars are 0.01 prouder than the posts so no two outward faces end up coplanar.
        p.box(-0.12, 0.12, y0, y1, -0.09, 0.09, colour)
        p.box(-0.09, 0.09, y0, y1, -0.12, 0.12, colour)
    return p


def make_mast_tip() -> Part:
    """Tapered cap with cross-arms and a warning beacon; sits on a mast_segment."""
    p = Part("mast_tip")
    p.face([(-0.12, 0.0, 0.12), (0.12, 0.0, 0.12), (0.06, 0.40, 0.06), (-0.06, 0.40, 0.06)], "hull")
    p.face([(0.12, 0.0, -0.12), (-0.12, 0.0, -0.12), (-0.06, 0.40, -0.06), (0.06, 0.40, -0.06)], "hull")
    p.face([(0.12, 0.0, 0.12), (0.12, 0.0, -0.12), (0.06, 0.40, -0.06), (0.06, 0.40, 0.06)], "hull")
    p.face([(-0.12, 0.0, -0.12), (-0.12, 0.0, 0.12), (-0.06, 0.40, 0.06), (-0.06, 0.40, -0.06)], "hull")
    p.face([(-0.12, 0.0, -0.12), (0.12, 0.0, -0.12), (0.12, 0.0, 0.12), (-0.12, 0.0, 0.12)], "hull")
    p.box(-0.30, 0.30, 0.26, 0.31, -0.035, 0.035, "panel")
    p.box(-0.035, 0.035, 0.31, 0.36, -0.30, 0.30, "panel")
    p.box(-0.04, 0.04, 0.36, 0.44, -0.04, 0.04, "trim")
    p.lathe([(0.0, 0.40), (0.115, 0.50), (0.0, 0.60)], "warn")
    return p


def make_tank_vertical() -> Part:
    """Capsule tank on a dark skirt, with a feed pipe up the +X side."""
    p = Part("tank_vertical")
    r = radius_for_width(0.50)
    p.lathe([(radius_for_width(0.42), 0.0), (radius_for_width(0.42), 0.12)], "slate", cap_bottom="slate")
    p.lathe([(r, 0.10), (r, 0.98), (r * 0.45, 1.16)], "hull", cap_top="panel", cap_bottom="hull")
    p.lathe([(radius_for_width(0.55), 0.44), (radius_for_width(0.55), 0.58)], "trim")
    p.lathe([(r * 0.22, 1.16), (r * 0.22, 1.25)], "trim", cap_top="trim")
    p.box(0.225, 0.275, 0.12, 1.02, -0.025, 0.025, "panel")
    p.box(0.215, 0.285, 0.86, 0.92, -0.035, 0.035, "trim")
    return p


def make_tank_sphere() -> Part:
    """Faceted sphere tank on four legs, amber equator."""
    p = Part("tank_sphere")
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box(sx * 0.26 - 0.035, sx * 0.26 + 0.035, 0.0, 0.34, sz * 0.26 - 0.035, sz * 0.26 + 0.035, "hull")
    p.box(-0.20, 0.20, 0.0, 0.05, -0.20, 0.20, "slate", top="panel")
    r = radius_for_width(0.90)
    prof = sphere_profile(r, 0.28, 1.00)
    p.lathe(prof, "hull", cap_top="panel", cap_bottom="panel")
    p.lathe([(r + 0.012, 0.60), (r + 0.012, 0.70)], "trim")
    return p


def make_energy_core() -> Part:
    """Glowing column caged between two collars; the struts are on the axes, not the diagonals, so
    the cyan shows through from the front."""
    p = Part("energy_core")
    r = radius_for_width(0.70)
    p.lathe([(r, 0.00), (r, 0.16)], "hull", cap_top="panel", cap_bottom="hull")
    p.lathe([(r, 0.10), (r, 0.14)], "trim")
    p.lathe([(r, 0.94), (r, 1.10)], "hull", cap_top="panel", cap_bottom="panel")
    p.lathe([(r, 0.96), (r, 1.00)], "trim")
    p.lathe([(0.24, 0.14), (0.24, 0.96)], "holo")
    for dx, dz in ((0.30, 0.0), (-0.30, 0.0), (0.0, 0.30), (0.0, -0.30)):
        p.box(dx - 0.045, dx + 0.045, 0.12, 0.98, dz - 0.045, dz + 0.045, "hull")
    return p


def _strut(p: Part, p0, p1, r0, r1, colour) -> None:
    """Slanted square rod between two points, cross-section taken in XZ (legs are near-vertical)."""
    (x0, y0, z0), (x1, y1, z1) = p0, p1
    bot = [(x0 - r0, y0, z0 + r0), (x0 + r0, y0, z0 + r0), (x0 + r0, y0, z0 - r0), (x0 - r0, y0, z0 - r0)]
    top = [(x1 - r1, y1, z1 + r1), (x1 + r1, y1, z1 + r1), (x1 + r1, y1, z1 - r1), (x1 - r1, y1, z1 - r1)]
    p.face([bot[0], bot[1], top[1], top[0]], colour)  # +Z
    p.face([bot[2], bot[3], top[3], top[2]], colour)  # -Z
    p.face([bot[1], bot[2], top[2], top[1]], colour)  # +X
    p.face([bot[3], bot[0], top[0], top[3]], colour)  # -X
    p.face(top, colour)
    p.face(bot[::-1], colour)


def make_drill_rig() -> Part:
    """Derrick: four legs closing into a crown, amber collars, a dark string into a salmon mound."""
    p = Part("drill_rig")
    p.lathe([(radius_for_width(0.74), 0.0), (radius_for_width(0.54), 0.14), (radius_for_width(0.24), 0.22)], "rock")
    p.lathe([(radius_for_width(0.24), 0.22), (0.0, 0.27)], "rock-dark")
    for sx in (-1, 1):
        for sz in (-1, 1):
            _strut(p, (sx * 0.405, 0.0, sz * 0.405), (sx * 0.105, 1.72, sz * 0.105), 0.045, 0.035, "hull")
    for y, half in ((0.58, 0.30), (1.18, 0.19)):
        p.box(-half - 0.09, half + 0.09, y, y + 0.055, -half + 0.02, half - 0.02, "trim")
        p.box(-half + 0.02, half - 0.02, y + 0.055, y + 0.11, -half - 0.09, half + 0.09, "trim")
    p.box(-0.17, 0.17, 1.72, 1.88, -0.17, 0.17, "hull", top="panel")
    p.box(-0.20, 0.20, 1.88, 1.94, -0.20, 0.20, "trim")
    p.box(-0.06, 0.06, 1.94, 2.00, -0.06, 0.06, "panel")
    p.box(-0.055, 0.055, 0.10, 1.76, -0.055, 0.055, "slate")
    p.lathe([(0.0, 0.00), (0.10, 0.10), (0.10, 0.22)], "trim", cap_top="trim")
    return p


def make_light_panel() -> Part:
    """Lit window strip for a blank hull.  The glowing face is on -Z; the frame is 0.03 deep, so a
    builder places it 0.015 clear of the wall it dresses."""
    p = Part("light_panel")
    p.box(-0.40, 0.40, 0.00, 0.18, -0.015, 0.015, "hull")
    p.face([(0.35, 0.030, -0.016), (-0.35, 0.030, -0.016), (-0.35, 0.150, -0.016), (0.35, 0.150, -0.016)], "lit")
    return p


def make_pad_marking() -> Part:
    """Landing-pad decal: a pale disc, an amber ring, a cross and four chevrons, all read from above."""
    p = Part("pad_marking")
    r = radius_for_width(1.60)
    p.lathe([(r, 0.0), (r, 0.014)], "slate", cap_top="slate", cap_bottom="slate")
    p.ring(0.58, 0.70, 0.016, "trim")
    p.plate(-0.40, 0.40, -0.075, 0.075, 0.018, "hull")
    p.plate(-0.075, 0.075, -0.40, 0.40, 0.018, "hull")
    for i in range(4):  # four amber approach bars outside the ring, one per axis
        with p.xform(rot_y(90.0 * i)):
            p.plate(-0.09, 0.09, 0.73, 0.79, 0.020, "trim")
    return p


PIECES = {
    "dome_small": make_dome_small,
    "dome_medium": make_dome_medium,
    "dome_large": make_dome_large,
    "dome_slit": make_dome_slit,
    "drum_medium": make_drum_medium,
    "drum_large": make_drum_large,
    "telescope": make_telescope,
    "planter_tray": make_planter_tray,
    "solar_panel": make_solar_panel,
    "solar_panel_flat": make_solar_panel_flat,
    "solar_tracker": make_solar_tracker,
    "flag": make_flag,
    "holo_beacon": make_holo_beacon,
    "mast_segment": make_mast_segment,
    "mast_tip": make_mast_tip,
    "tank_vertical": make_tank_vertical,
    "tank_sphere": make_tank_sphere,
    "energy_core": make_energy_core,
    "drill_rig": make_drill_rig,
    "light_panel": make_light_panel,
    "pad_marking": make_pad_marking,
}


# --- Blender plumbing ----------------------------------------------------------------------------


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
    parser = argparse.ArgumentParser(description="Generate the orbital-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    total, warnings = 0, []
    for name, make in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        cache: dict = {}
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        shift = part.recenter()
        (x0, y0, z0), (x1, y1, z1) = part.bbox()
        size = (x1 - x0, y1 - y0, z1 - z0)
        obj = build_object(part, cache)
        export(obj, args.out)
        tris = sum(len(idx) - 2 for idx, _ in part.faces)
        total += tris
        log(
            f"{name}.glb: {size[0]:.3f} x {size[1]:.3f} x {size[2]:.3f}  "
            f"{len(part.faces)} faces, {tris} tris, recentred by "
            f"({shift[0]:+.3f}, {shift[1]:+.3f}, {shift[2]:+.3f})"
        )
        want = NOMINAL.get(name)
        if want:
            off = [abs(size[i] - want[i]) for i in range(3)]
            if max(off) > TOLERANCE:
                warnings.append(f"{name}: {size} vs contract {want}")
        if tris > 400:
            warnings.append(f"{name}: {tris} tris over the 400 budget")
    log(f"{len(PIECES)} pieces, {total} tris total -> {os.path.relpath(args.out, REPO_ROOT)}")
    for w in warnings:
        log(f"WARNING {w}")
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
