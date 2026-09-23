"""Custom low-poly walkway tubes for Orbital Colony, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/tube_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/tube-kit/Models/GLB format/, the folder convention
every Kenney kit already uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py discover
the kit with no registration step. assets/ is gitignored, so this script is the committed artifact
and the GLBs regenerate from it. Same pattern as highway_kit.py, metro_kit.py, orbital_kit.py.

Why a custom kit: Ben chose enclosed corridor tubes as the Orbital walkways (INTERFACES "Wave 2b --
Tubes") and space-kit has no corridor that tiles on a 7-stud cell. His Studio verdict on the first
version (a 4 x 4.5 glazed box corridor with junction nodes) was "seems off, make it smaller -- just
a semicircle with supporting rings", then "all white, bright grey rings, no blue glass". So the
section is a white half-pipe of radius 1.5 on a 0.3 grey sill (3 wide, 1.8 tall), girdled by grey
rings every 1.4 studs, and junctions are just the half-pipes intersecting.

Junctions rely on overlapping closed shells: each arm is a closed volume (shell + sill + floor), so
wherever one arm's surface lies inside another's it is hidden and the render is the union, with no
boolean cut. The one gap a bend leaves (the outer corner beyond both arm ends) is filled by a
quarter dome sampled on the same 15-degree grid as the arcs, so its edges coincide with them.

Art rules, matching the other generated kits: flat shading only, chunky toy proportions, plain
colour-factor materials with no texture; merge_stages.py routes those through palette.py.

**Units: 1 glTF unit = 1 stud** (blueprints use `"scale": 1.0`). Each piece's origin is the **bottom
centre of its cell at ground level**. Canonical orientation at rotY 0 is the Metropolis tile one:
straight along X; end open to +X (airlock at -X); bend joins -X <-> +Z; tee open -X / +X / +Z,
closed -Z; cross open on all four. Every open arm stops at exactly +-3.5 and drops its buried end
faces, and the ring at a cell edge is a half-ring, so two neighbours pair into one full ring.

Geometry is authored in glTF space (Y up, front -Z); Blender is Z up, so every vertex converts with
(x, y, z) -> (x, -z, y), a proper rotation. Faces are oriented by an explicit outward direction
(`Part.face(..., out=...)`), so rotated arms stay correct.
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

# SHELL is a notch brighter than space-kit "metal" (HULL, the colour of the shipped Orbital
# modules), so a tube running up to a module still reads as a separate object on the dark plot.
# SLATE and LIT are the same numbers as orbital_kit.py (space-kit "dark" read raw x 255, and
# orbital-kit's lit strip). Written as linear factors like orbital-kit, so palette.py decodes them
# back to these bytes and tube-kit must NOT join palette.SRGB_FACTOR_KITS.
SHELL = (240, 242, 246)
RING = (190, 196, 206)  # bright grey: supports and sill
HULL = (215, 222, 232)  # space-kit "metal": the airlock disc
SLATE = (70, 76, 87)  # space-kit "dark": floor strip, door leaf
LIT = (255, 225, 140)  # orbital-kit lit strip: the airlock lamp

COLOURS = {"shell": SHELL, "ring": RING, "hull": HULL, "slate": SLATE, "lit": LIT}

# --- dimensions, in studs ------------------------------------------------------------------
CELL = 7.0  # INTERFACES: tile pitch, one prop per cell
EDGE = CELL / 2.0
R = 1.5  # half-pipe radius: 3 wide
SILL = 0.3  # vertical sill under the arc; the arc's centre sits on top of it, total 1.8 tall
ARC_SEGS = 12  # 15-degree steps; the bend's quarter dome uses the same grid
FLOOR_HALF = 1.3  # dark floor strip 2.6 wide inside
FLOOR_Y = (0.02, 0.03)  # X-running and Z-running floors, never coplanar where two arms overlap

RING_PITCH = 1.4  # Ben: a support ring every 1.4 studs, one on each cell edge
RING_W = 0.16  # along the run; a cell-edge ring is half of it on each side of the joint
RING_OUT = 1.62  # outer radius at the vertices: 0.12 proud of the shell
RING_IN = 1.42  # inner radius, inside the shell so the side faces start buried
RING_SEGS = 7  # the ring is its own coarser polygon, legs to the ground included (tri budget)
HUB_OUT = 1.74  # the larger collar rings at a junction (centreline ~1.65)
HUB_IN = 1.52
HUB_W = 0.22
JUNCTION_CLEAR = R + 0.1  # arm rings closer than this to a junction centre would cut the crossing
COLLAR_AT = R + HUB_W / 2.0 + 0.01  # a collar hugs the arm root, just outside the other pipe
COLLAR_CLEAR = 2.2  # a lattice ring this close to the centre would crowd a collar, so it goes

CAP_X0 = -3.1  # airlock disc on tube-end, x -3.1 .. -2.92, a touch larger than the pipe
CAP_X1 = -2.92
CAP_R = 1.66
DOOR_HALF = 0.5
DOOR_H = 1.35
LAMP_Y = (1.48, 1.62)
LAMP_HALF = 0.22
PROUD = 0.02  # door and lamp stand this far off the disc instead of z-fighting


def log(msg: str) -> None:
    print(f"[tube-kit] {msg}", flush=True)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def arc(radius: float, segs: int) -> list[tuple[float, float]]:
    """(z, y) points of the semicircle from +z over the top to -z, centred on the sill top."""
    return [
        (radius * math.cos(math.pi * i / segs), SILL + radius * math.sin(math.pi * i / segs))
        for i in range(segs + 1)
    ]


SECTION = [(R, 0.0)] + arc(R, ARC_SEGS) + [(-R, 0.0)]  # sill, arc, sill


def ring_profile(radius: float) -> list[tuple[float, float]]:
    """Ring polygon: ground foot, the interior arc vertices, ground foot. The legs run straight
    from the ground to the first arc vertex, which still clears the shell (asserted in main)."""
    return [(radius, 0.0)] + arc(radius, RING_SEGS)[1:-1] + [(-radius, 0.0)]


# --- mesh building (glTF space) -------------------------------------------------------------


def rot_y(degrees: float):
    """Rotation about +Y in the blueprint convention (+90 turns +X to face -Z)."""
    c = round(math.cos(math.radians(degrees)), 12)
    s = round(math.sin(math.radians(degrees)), 12)
    return lambda v: (v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c)


ARM = {"+X": 0, "-Z": 90, "-X": 180, "+Z": 270}


class Part:
    """Accumulates flat-shaded polygons tagged with a colour name, under a current rotation."""

    def __init__(self, name: str):
        self.name = name
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[list[int], str]] = []
        self.xf = rot_y(0)

    def face(self, points, colour: str, out) -> None:
        """Add a polygon wound counter-clockwise as seen from the `out` direction."""
        pts = [tuple(round(c, 9) + 0.0 for c in self.xf(p)) for p in points]
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

    def bounds(self):
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _ in self.faces)


def outward(za: float, ya: float, zb: float, yb: float) -> tuple[float, float, float]:
    """Outward direction of a section edge: away from a point low on the centreline, which lies
    inside every section here (sill walls, arc facets and the ring legs alike)."""
    return (0.0, (ya + yb) / 2.0 - SILL * 0.5, (za + zb) / 2.0)


# --- pieces (authored along +X, then turned) --------------------------------------------------


def pipe(p: Part, x0: float, x1: float, floor_y: float) -> None:
    """The half-pipe shell and its sill from x0 to x1, plus the dark floor strip. No end faces:
    every end butts a neighbour cell, another arm's volume, the bend dome or the airlock."""
    for (za, ya), (zb, yb) in zip(SECTION, SECTION[1:]):
        colour = "ring" if ya == 0.0 or yb == 0.0 else "shell"
        p.face(
            [(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)],
            colour,
            outward(za, ya, zb, yb),
        )
    p.face(
        [
            (x0, floor_y, -FLOOR_HALF),
            (x1, floor_y, -FLOOR_HALF),
            (x1, floor_y, FLOOR_HALF),
            (x0, floor_y, FLOOR_HALF),
        ],
        "slate",
        (0.0, 1.0, 0.0),
    )


def ring(p: Part, x0, x1, r_out, r_in, keep_nx=True, keep_px=True) -> None:
    """A grey support ring standing proud of the shell, feet on the ground. A cell-edge half-ring
    drops the side lying on the cell boundary (buried in the neighbour's matching half)."""
    outer, inner = ring_profile(r_out), ring_profile(r_in)
    for (za, ya), (zb, yb) in zip(outer, outer[1:]):
        p.face(
            [(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)],
            "ring",
            outward(za, ya, zb, yb),
        )
    for x, keep, sign in ((x0, keep_nx, -1.0), (x1, keep_px, 1.0)):
        if not keep:
            continue
        for i in range(len(outer) - 1):
            a, b, oa, ob = inner[i], inner[i + 1], outer[i], outer[i + 1]
            p.face(
                [(x, a[1], a[0]), (x, b[1], b[0]), (x, ob[1], ob[0]), (x, oa[1], oa[0])],
                "ring",
                (sign, 0.0, 0.0),
            )


def rings(p: Part, x0: float, x1: float, clear: float = 0.0) -> None:
    """Rings on the 1.4 lattice phased on the cell edges (-3.5, -2.1, ... 3.5) within [x0, x1],
    skipping any closer than `clear` to the cell centre (a junction's crossing)."""
    for k in range(6):
        c = round(-EDGE + k * RING_PITCH, 9)
        if abs(c) < clear or c < x0 - 1e-6 or c > x1 + 1e-6:
            continue
        if c == EDGE:
            ring(p, EDGE - RING_W / 2.0, EDGE, RING_OUT, RING_IN, keep_px=False)
        elif c == -EDGE:
            ring(p, -EDGE, -EDGE + RING_W / 2.0, RING_OUT, RING_IN, keep_nx=False)
        elif x0 + RING_W / 2.0 <= c <= x1 - RING_W / 2.0:
            ring(p, c - RING_W / 2.0, c + RING_W / 2.0, RING_OUT, RING_IN)


def arm(p: Part, direction: str, x0: float, floor_y: float) -> None:
    """A junction arm from x0 (in its own frame) out to the cell edge."""
    p.xf = rot_y(ARM[direction])
    pipe(p, x0, EDGE, floor_y)
    rings(p, x0, EDGE, JUNCTION_CLEAR)
    p.xf = rot_y(0)


def hub(p: Part, degrees: float, at: float = 0.0) -> None:
    """A larger ring marking a junction, `at` studs out along its turned X axis.

    A hoop across a crossing's centre is swallowed by the perpendicular pipe (first render: only
    a small tab showed on top), so tees and crosses put a collar on each branch root instead, and
    the bend puts one hoop across the turn's diagonal, where the outer-corner dome leaves it proud.
    """
    p.xf = rot_y(degrees)
    ring(p, at - HUB_W / 2.0, at + HUB_W / 2.0, HUB_OUT, HUB_IN)
    p.xf = rot_y(0)


def quarter_dome(p: Part) -> None:
    """Fills a bend's outer corner (x > 0, z < 0), where neither arm reaches: a quarter sphere on
    a quarter sill, on the arcs' 15-degree grid so both meridian edges coincide with the arms."""
    n = ARC_SEGS // 2
    centre = (0.0, SILL, 0.0)

    def sph(az: int, el: int) -> tuple[float, float, float]:
        a, e = math.pi / 2.0 * az / n, math.pi / 2.0 * el / n
        return (
            R * math.cos(e) * math.sin(a),
            SILL + R * math.sin(e),
            -R * math.cos(e) * math.cos(a),
        )

    for az in range(n):
        for el in range(n):
            quad = [sph(az, el), sph(az + 1, el), sph(az + 1, el + 1), sph(az, el + 1)]
            if el == n - 1:
                quad = quad[:3]  # the pole
            mid = [sum(c) / len(quad) for c in zip(*quad)]
            p.face(quad, "shell", tuple(mid[i] - centre[i] for i in range(3)))
        a0, a1 = sph(az, 0), sph(az + 1, 0)
        mid = ((a0[0] + a1[0]) / 2.0, 0.0, (a0[2] + a1[2]) / 2.0)
        p.face([(a0[0], 0.0, a0[2]), (a1[0], 0.0, a1[2]), a1, a0], "ring", mid)


def make_straight() -> Part:
    p = Part("tube-straight")
    pipe(p, -EDGE, EDGE, FLOOR_Y[0])
    rings(p, -EDGE, EDGE)
    return p


def make_end() -> Part:
    """Dead end: open to +X, closed at -X by a flat semicircular airlock disc with a dark door and
    one lit lamp above it."""
    p = Part("tube-end")
    pipe(p, CAP_X1, EDGE, FLOOR_Y[0])
    rings(p, CAP_X1 + RING_W, EDGE)
    rim = [(CAP_R, 0.0)] + arc(CAP_R, ARC_SEGS) + [(-CAP_R, 0.0)]
    p.face([(CAP_X0, y, z) for z, y in rim], "hull", (-1.0, 0.0, 0.0))
    for (za, ya), (zb, yb) in zip(rim, rim[1:]):
        p.face(
            [(CAP_X0, ya, za), (CAP_X1, ya, za), (CAP_X1, yb, zb), (CAP_X0, yb, zb)],
            "hull",
            outward(za, ya, zb, yb),
        )
    x = CAP_X0 - PROUD
    p.face(
        [(x, 0.0, -DOOR_HALF), (x, 0.0, DOOR_HALF), (x, DOOR_H, DOOR_HALF), (x, DOOR_H, -DOOR_HALF)],
        "slate",
        (-1.0, 0.0, 0.0),
    )
    p.face(
        [
            (x, LAMP_Y[0], -LAMP_HALF),
            (x, LAMP_Y[0], LAMP_HALF),
            (x, LAMP_Y[1], LAMP_HALF),
            (x, LAMP_Y[1], -LAMP_HALF),
        ],
        "lit",
        (-1.0, 0.0, 0.0),
    )
    return p


def make_bend() -> Part:
    p = Part("tube-bend")
    arm(p, "-X", 0.0, FLOOR_Y[0])
    arm(p, "+Z", 0.0, FLOOR_Y[1])
    quarter_dome(p)
    hub(p, -45.0)  # across the turn, from the inner corner (-X, +Z) to the outer one
    return p


def make_tee() -> Part:
    p = Part("tube-tee")
    pipe(p, -EDGE, EDGE, FLOOR_Y[0])
    rings(p, -EDGE, EDGE, JUNCTION_CLEAR)
    p.xf = rot_y(ARM["+Z"])
    pipe(p, 0.0, EDGE, FLOOR_Y[1])
    rings(p, 0.0, EDGE, COLLAR_CLEAR)
    p.xf = rot_y(0)
    hub(p, ARM["+Z"], COLLAR_AT)
    return p


def make_cross() -> Part:
    p = Part("tube-cross")
    pipe(p, -EDGE, EDGE, FLOOR_Y[0])
    rings(p, -EDGE, EDGE, COLLAR_CLEAR)
    p.xf = rot_y(90)
    pipe(p, -EDGE, EDGE, FLOOR_Y[1])
    rings(p, -EDGE, EDGE, COLLAR_CLEAR)
    p.xf = rot_y(0)
    for direction in ("+X", "-Z", "-X", "+Z"):
        hub(p, ARM[direction], COLLAR_AT)
    return p


PIECES = {
    "tube-straight": make_straight,
    "tube-end": make_end,
    "tube-bend": make_bend,
    "tube-tee": make_tee,
    "tube-cross": make_cross,
}
TRI_BUDGET = 400  # INTERFACES: <= 400 tris per piece


def ring_clearance() -> float:
    """Smallest gap between a ring's outer polygon and the shell (must stay > 0)."""
    worst = math.inf
    outer = ring_profile(RING_OUT)
    for (za, ya), (zb, yb) in zip(outer, outer[1:]):
        for t in (i / 20.0 for i in range(21)):
            z, y = za + (zb - za) * t, ya + (yb - ya) * t
            if y >= SILL:
                worst = min(worst, math.hypot(z, y - SILL) - R)
            else:
                worst = min(worst, abs(z) - R)
    return worst


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
    gap = ring_clearance()
    assert gap > 0.02, f"support rings cut into the shell (clearance {gap:.3f})"
    log(f"ring clearance over the shell: {gap:.3f} studs")
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
