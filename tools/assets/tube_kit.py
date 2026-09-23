"""Custom low-poly walkway tubes for Orbital Colony, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/tube_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/tube-kit/Models/GLB format/, the folder convention
every Kenney kit already uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py discover
the kit with no registration step. assets/ is gitignored, so this script is the committed artifact
and the GLBs regenerate from it. Same pattern as highway_kit.py, metro_kit.py, orbital_kit.py.

Why a custom kit at all: Ben chose "enclosed corridor tubes" as the Orbital walkways (INTERFACES
"Wave 2b -- Tubes"), and space-kit has no corridor piece that tiles on a 7-stud cell -- its only
glass is near-black and would vanish on the (56, 53, 60) plot base. So everything that has to read
from the tycoon camera is light: white ribs, light-blue glass, a pale deck; only the base skirt is
dark, which is what lifts the tube off the regolith.

Art rules, matching the other generated kits: flat shading only, chunky toy proportions, an
octagon-derived corridor section (vertical walls, 45-ish chamfers, flat roof), plain colour-factor
materials with no texture; merge_stages.py routes those through palette.py into one swatch.

**Units: 1 glTF unit = 1 stud** (blueprints use `"scale": 1.0`), because every dimension is
contract-bound (7-stud cells, 4-wide corridor). Each piece's origin is the **bottom centre of its
cell at ground level**. Canonical orientation at rotY 0 is the Metropolis tile one: straight along
X; end open to +X (airlock at -X); bend joins -X <-> +Z; tee open -X / +X / +Z, closed -Z; cross
open on all four. Every open arm stops at exactly +-3.5 and drops its buried end faces, so two
neighbouring cells meet with no gap, no overlap and no seam; the ribs at a cell edge are half-ribs
that pair up into one full rib across the joint, keeping the 1.75-stud rhythm unbroken.

Geometry is authored in glTF space (Y up, front -Z); Blender is Z up, so every vertex converts with
(x, y, z) -> (x, -z, y), a proper rotation. Faces are oriented by an explicit outward direction
(`Part.face(..., out=...)`) rather than by hand-ordered winding, so rotated arms stay correct.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "tube-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# Same numbers as orbital_kit.py, so the tubes sit beside the shipped Orbital buildings. HULL,
# PANEL, TRIM and SLATE are space-kit's own material colour factors read raw x 255 (the kit wrote
# sRGB into its factors -- see palette.SRGB_FACTOR_KITS); GLASS and LIT are orbital-kit's accents.
# This kit writes them as proper linear factors (srgb_to_linear below), exactly like orbital-kit,
# so palette.py decodes them back to these bytes and tube-kit must NOT join SRGB_FACTOR_KITS.
HULL = (215, 222, 232)  # space-kit "metal": ribs, airlock, junction node
PANEL = (172, 181, 197)  # space-kit "metalDark": decking, node roof
TRIM = (255, 160, 52)  # space-kit "metalRed": airlock door frame, node band
SLATE = (70, 76, 87)  # space-kit "dark": base skirt, door leaf
GLASS = (150, 215, 255)  # orbital-kit glass
LIT = (255, 225, 140)  # orbital-kit lit strip: the airlock lamp

COLOURS = {
    "hull": HULL,
    "panel": PANEL,
    "trim": TRIM,
    "slate": SLATE,
    "glass": GLASS,
    "lit": LIT,
}

# --- dimensions, in studs ------------------------------------------------------------------
CELL = 7.0  # INTERFACES: tile pitch, one prop per cell
EDGE = CELL / 2.0
HALF_W = 2.0  # corridor is 4 wide (INTERFACES road.width 4)
DECK_T = 0.2  # decking strip 7 x 4 x 0.2
SKIRT_TOP = 0.65  # dark base band above the deck: the line that lifts the tube off the ground
WALL_TOP = 3.0  # vertical glass wall, then the chamfer
ROOF_HALF = 1.2  # flat roof 2.4 wide
ROOF_Y = 4.5  # corridor height (contract ~4.5)
RIB_PITCH = 1.75  # INTERFACES: a frame rib every 1.75 studs, phased on the cell centre
RIB_W = 0.3  # full rib width along the run; a cell-edge rib is half of it on each side
SILL_H = 0.22  # white sill band under the wall/chamfer crease
SILL_OUT = 0.04
RIB_OUT = 0.1  # ribs stand proud of the glass so they catch light on both faces

NODE_HALF = 2.4  # junction node: 4.8 square, 0.4 wider than the corridor each side
NODE_H = 5.0
NODE_BAND = 0.45  # orange band under the node roof
HATCH_HALF = 0.7
HATCH_H = 0.3

CAP_X0 = -3.15  # airlock block on tube-end spans x -3.15 .. -2.55
CAP_X1 = -2.55
CAP_HALF = 2.35
CAP_H = 5.0
DOOR_HALF = 0.8
DOOR_H = 3.2
DOOR_FRAME = 0.18
PROUD = 0.02  # decals (door, windows) stand this far off their wall instead of z-fighting

# The corridor section, (z, y) from the -Z foot over the roof to the +Z foot. Clockwise with z to
# the right, so the outward normal of a segment (dz, dy) is (-dy, dz).
PROFILE = [
    ((-HALF_W, DECK_T), "slate"),
    ((-HALF_W, SKIRT_TOP), "glass"),
    ((-HALF_W, WALL_TOP), "glass"),
    ((-ROOF_HALF, ROOF_Y), "hull"),
    ((ROOF_HALF, ROOF_Y), "glass"),
    ((HALF_W, WALL_TOP), "glass"),
    ((HALF_W, SKIRT_TOP), "slate"),
    ((HALF_W, DECK_T), None),
]
# Each entry's colour is the colour of the segment that *starts* at that point: skirt, wall,
# chamfer, roof, chamfer, wall, skirt. The roof strip is white so a run reads as a lit spine.


def log(msg: str) -> None:
    print(f"[tube-kit] {msg}", flush=True)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def offset_polyline(points: list[tuple[float, float]], d: float) -> list[tuple[float, float]]:
    """Offset an open (z, y) polyline outward by d, mitred; the end points move along their
    segment's normal only, so a rib's feet stay on the ground."""
    normals = []
    for (z0, y0), (z1, y1) in zip(points, points[1:]):
        length = math.hypot(z1 - z0, y1 - y0)
        normals.append((-(y1 - y0) / length, (z1 - z0) / length))
    out = []
    for i, (z, y) in enumerate(points):
        if i == 0:
            nz, ny, k = normals[0][0], normals[0][1], 1.0
        elif i == len(points) - 1:
            nz, ny, k = normals[-1][0], normals[-1][1], 1.0
        else:
            az, ay = normals[i - 1]
            bz, by = normals[i]
            mz, my = az + bz, ay + by
            m = math.hypot(mz, my)
            nz, ny = mz / m, my / m
            k = 1.0 / (nz * az + ny * ay)
        out.append((z + nz * d * k, y + ny * d * k))
    return out


# --- mesh building (glTF space) -------------------------------------------------------------


def rot_y(quarter_turns: int):
    """Rotation about +Y in the blueprint convention (+90 turns +X to face -Z)."""
    c = round(math.cos(quarter_turns * math.pi / 2))
    s = round(math.sin(quarter_turns * math.pi / 2))
    return lambda v: (v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c)


# The arm builders author an arm running from the cell centre toward +X; these turn it onto its
# real direction.
ARM = {"+X": 0, "-Z": 1, "-X": 2, "+Z": 3}


class Part:
    """Accumulates flat-shaded polygons tagged with a colour name, under a current rotation."""

    def __init__(self, name: str):
        self.name = name
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[list[int], str]] = []
        self.xf = rot_y(0)

    def face(self, points, colour: str, out) -> None:
        """Add a polygon wound counter-clockwise as seen from the `out` direction."""
        pts = [self.xf(p) for p in points]
        o = self.xf(out)
        nx = ny = nz = 0.0  # Newell normal
        for i, (x0, y0, z0) in enumerate(pts):
            x1, y1, z1 = pts[(i + 1) % len(pts)]
            nx += (y0 - y1) * (z0 + z1)
            ny += (z0 - z1) * (x0 + x1)
            nz += (x0 - x1) * (y0 + y1)
        if nx * o[0] + ny * o[1] + nz * o[2] < 0:
            pts.reverse()
        base = len(self.verts)
        self.verts.extend(pts)
        self.faces.append(([base + i for i in range(len(pts))], colour))

    def box(self, x0, x1, y0, y1, z0, z1, colour, **sides) -> None:
        """Axis-aligned box; `sides` overrides a face's colour (top, bottom, nx, px, nz, pz) and
        None drops a buried face."""
        c = {k: sides.get(k, colour) for k in ("top", "bottom", "nx", "px", "nz", "pz")}
        quads = (
            ("pz", [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
            ("nz", [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], (0, 0, -1)),
            ("px", [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)], (1, 0, 0)),
            ("nx", [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1, 0, 0)),
            ("top", [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
            ("bottom", [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
        )
        for key, pts, out in quads:
            if c[key] is not None:
                self.face(pts, c[key], out)

    def bounds(self):
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _ in self.faces)


# --- corridor pieces (authored along +X) ------------------------------------------------------


def corridor(p: Part, x0: float, x1: float) -> None:
    """Deck strip plus the glass section swept from x0 to x1. No end faces: every end either
    butts a neighbour cell, a junction node or an airlock."""
    # Deck: long sides and the walkable top; the underside rests on the ground.
    p.box(x0, x1, 0.0, DECK_T, -HALF_W, HALF_W, "panel", nx=None, px=None, bottom=None)
    for i in range(len(PROFILE) - 1):
        (za, ya), colour = PROFILE[i]
        zb, yb = PROFILE[i + 1][0]
        out = (0.0, -(yb - ya), zb - za)
        p.face([(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)], colour, out)
    # A white sill along the wall/chamfer crease: without it a run is one flat blue slab between
    # ribs and loses its "glazed corridor" read. It stands inside the ribs' 0.1, so ribs cover it.
    for side in (-1.0, 1.0):
        z = side * (HALF_W + SILL_OUT)
        p.face(
            [(x0, WALL_TOP - SILL_H, z), (x1, WALL_TOP - SILL_H, z), (x1, WALL_TOP, z), (x0, WALL_TOP, z)],
            "hull",
            (0.0, 0.0, side),
        )


RIB_INNER = [(-HALF_W, 0.0)] + [pt for pt, _ in PROFILE[2:6]] + [(HALF_W, 0.0)]
RIB_OUTER = offset_polyline(RIB_INNER, RIB_OUT)


def rib(p: Part, x0: float, x1: float, faces_nx: bool = True, faces_px: bool = True) -> None:
    """A white frame ring standing RIB_OUT proud of the glass, from the ground over the roof.
    A cell-edge half-rib drops the side that lies on the cell boundary (it is buried in the
    neighbour's matching half-rib)."""
    for i in range(len(RIB_OUTER) - 1):
        (za, ya), (zb, yb) = RIB_OUTER[i], RIB_OUTER[i + 1]
        out = (0.0, -(yb - ya), zb - za)
        p.face([(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)], "hull", out)
    for x, keep, sign in ((x0, faces_nx, -1.0), (x1, faces_px, 1.0)):
        if not keep:
            continue
        for i in range(len(RIB_INNER) - 1):
            a, b = RIB_INNER[i], RIB_INNER[i + 1]
            oa, ob = RIB_OUTER[i], RIB_OUTER[i + 1]
            p.face(
                [(x, a[1], a[0]), (x, b[1], b[0]), (x, ob[1], ob[0]), (x, oa[1], oa[0])],
                "hull",
                (sign, 0.0, 0.0),
            )


def ribs(p: Part, x0: float, x1: float) -> None:
    """Ribs on the 1.75 lattice (phased on the cell centre) that fall within [x0, x1]."""
    k = math.ceil((x0 - 1e-6) / RIB_PITCH)
    while k * RIB_PITCH <= x1 + 1e-6:
        c = k * RIB_PITCH
        if abs(c - EDGE) < 1e-6:
            rib(p, EDGE - RIB_W / 2.0, EDGE, faces_px=False)
        elif abs(c + EDGE) < 1e-6:
            rib(p, -EDGE, -EDGE + RIB_W / 2.0, faces_nx=False)
        elif x0 + RIB_W / 2.0 <= c <= x1 - RIB_W / 2.0:
            rib(p, c - RIB_W / 2.0, c + RIB_W / 2.0)
        k += 1


def arm(p: Part, direction: str) -> None:
    """One corridor arm from the junction node's face out to the cell edge."""
    p.xf = rot_y(ARM[direction])
    corridor(p, NODE_HALF, EDGE)
    ribs(p, NODE_HALF, EDGE)
    p.xf = rot_y(0)


def node(p: Part, open_dirs: set[str]) -> None:
    """The square junction node the arms plug into: dark skirt, white walls, an orange band under
    a pale roof with a lit hatch, and a window on every closed side."""
    n = NODE_HALF
    p.box(-n, n, 0.0, SKIRT_TOP, -n, n, "slate", bottom=None, top=None)
    p.box(-n, n, SKIRT_TOP, NODE_H - NODE_BAND, -n, n, "hull", bottom=None, top=None)
    p.box(-n, n, NODE_H - NODE_BAND, NODE_H, -n, n, "trim", bottom=None, top="panel")
    p.box(-HATCH_HALF, HATCH_HALF, NODE_H, NODE_H + HATCH_H, -HATCH_HALF, HATCH_HALF, "hull",
          bottom=None, top="lit")
    for direction in ("+X", "-Z", "-X", "+Z"):
        if direction in open_dirs:
            continue
        p.xf = rot_y(ARM[direction])
        x = n + PROUD
        p.face(
            [(x, 1.1, -1.5), (x, 1.1, 1.5), (x, 3.7, 1.5), (x, 3.7, -1.5)], "glass", (1.0, 0.0, 0.0)
        )
        p.xf = rot_y(0)


def make_straight() -> Part:
    p = Part("tube-straight")
    corridor(p, -EDGE, EDGE)
    ribs(p, -EDGE, EDGE)
    return p


def make_end() -> Part:
    """Dead end: open to +X, closed at -X by an airlock block with a framed door and a lamp.
    The deck runs on to the cell edge as a landing in front of the door."""
    p = Part("tube-end")
    corridor(p, CAP_X1, EDGE)
    ribs(p, CAP_X1, EDGE)
    p.box(-EDGE, CAP_X0, 0.0, DECK_T, -HALF_W, HALF_W, "panel", px=None, bottom=None)
    p.box(CAP_X0, CAP_X1, 0.0, SKIRT_TOP, -CAP_HALF, CAP_HALF, "slate", bottom=None, top=None)
    p.box(CAP_X0, CAP_X1, SKIRT_TOP, CAP_H - NODE_BAND, -CAP_HALF, CAP_HALF, "hull",
          bottom=None, top=None)
    p.box(CAP_X0, CAP_X1, CAP_H - NODE_BAND, CAP_H, -CAP_HALF, CAP_HALF, "trim",
          bottom=None, top="panel")
    # Door on the -X face: an orange frame around a dark leaf, a lamp strip above.
    x = CAP_X0 - PROUD
    f = DOOR_FRAME
    p.face([(x, DECK_T, -DOOR_HALF - f), (x, DECK_T, DOOR_HALF + f),
            (x, DOOR_H + f, DOOR_HALF + f), (x, DOOR_H + f, -DOOR_HALF - f)], "trim", (-1, 0, 0))
    x2 = x - PROUD
    p.face([(x2, DECK_T, -DOOR_HALF), (x2, DECK_T, DOOR_HALF),
            (x2, DOOR_H, DOOR_HALF), (x2, DOOR_H, -DOOR_HALF)], "slate", (-1, 0, 0))
    p.face([(x, DOOR_H + 0.35, -1.0), (x, DOOR_H + 0.35, 1.0),
            (x, DOOR_H + 0.65, 1.0), (x, DOOR_H + 0.65, -1.0)], "lit", (-1, 0, 0))
    return p


def make_junction(name: str, open_dirs: list[str]) -> Part:
    p = Part(name)
    node(p, set(open_dirs))
    for d in open_dirs:
        arm(p, d)
    return p


PIECES = {
    "tube-straight": make_straight,
    "tube-end": make_end,
    "tube-bend": lambda: make_junction("tube-bend", ["-X", "+Z"]),
    "tube-tee": lambda: make_junction("tube-tee", ["-X", "+X", "+Z"]),
    "tube-cross": lambda: make_junction("tube-cross", ["-X", "+X", "-Z", "+Z"]),
}
TRI_BUDGET = 400  # INTERFACES: <= 400 tris per piece


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
    parser = argparse.ArgumentParser(description="Generate the tube-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    total = 0
    for name, make in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        assert part.tris <= TRI_BUDGET, f"{name}: {part.tris} tris > {TRI_BUDGET}"
        obj = build_object(part, {})
        export(obj, args.out)
        total += part.tris
        lo, hi = part.bounds()
        log(
            f"{name}.glb: {part.tris} tris, "
            f"x {lo[0]:.2f}..{hi[0]:.2f}, y {lo[1]:.2f}..{hi[1]:.2f}, z {lo[2]:.2f}..{hi[2]:.2f}"
        )
    log(f"{len(PIECES)} pieces, {total} tris total -> {os.path.relpath(args.out, REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
