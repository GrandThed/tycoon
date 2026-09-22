"""Custom low-poly subway-entrance pieces for Metropolis, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/metro_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/metro-kit/Models/GLB format/, which is the folder
convention every Kenney kit already uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. Same pattern as stadium_kit.py and orbital_kit.py.

Why a custom kit at all: a subway entrance needs stairs that visibly go *down*, and the plot base
has no hole to dig into. city-kit-commercial and city-kit-roads have no stair, no pit, no ramp and
no letter pieces, so the kit-assembled attempts (drafts panel 3/3b) came out as a pair of railing
arches on a slab -- Ben read it as a bike rack. The pieces below are therefore a **raised kiosk**:
a podium whose top surface steps down from the street edge into a dark well, with the descent also
traced by a blue coping on both side walls, and a tall pylon carrying a blue sign with a white "M".

Art rules, matching the City Kits: flat shading only (no smooth normals, no bevels, no
subdivision), axis-aligned boxes plus a few extruded flat shapes, chunky toy proportions.
Materials are plain colour factors with no texture, exactly like nature-kit and space-kit;
merge_stages.py routes those through palette.py, which bakes them into one swatch texture at
merge time.

**Units: 1 glTF unit = 1 stud**, unlike the Kenney kits (where 1 unit = 4 studs and blueprints use
scale 4.0). The prop's size is contract-bound (<= 5 x 6 studs, INTERFACES "Subway entrances"), so
authoring in studs keeps every literal below directly checkable against that contract. Its
blueprint therefore uses `"scale": 1.0`; anything else reusing these pieces must do the same.

Geometry is authored in glTF space -- Y up, front -Z (the street side, where the stair mouth is),
each piece recentred on its own bottom-centre origin so the blueprint positions read as studs.
Blender is Z up, so every vertex converts with (x, y, z) -> (x, -z, y); that map is a proper
rotation, so face winding carries over unchanged.
"""

from __future__ import annotations

import argparse
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "metro-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# sRGB bytes read straight out of
# assets/kenney3d/city-kit-commercial/Models/GLB format/Textures/colormap.png (the texel counts in
# that image make these the kit's own ramp, not eyeballed approximations).  WALL/TRIM/SLATE/DARK
# are its wall-to-shadow ramp, BLUE is the kit's one saturated blue and YELLOW its warning amber.
# Keeping to the kit's own texels is what makes this prop sit beside the 24 Metropolis buildings.
WALL = (255, 255, 255)
TRIM = (142, 149, 179)
SLATE = (81, 85, 102)
DARK = (56, 56, 61)
BLUE = (103, 148, 217)
YELLOW = (255, 192, 68)

COLOURS = {
    "wall": WALL,
    "trim": TRIM,
    "slate": SLATE,
    "dark": DARK,
    "blue": BLUE,
    "yellow": YELLOW,
}

# --- the entrance, in studs ---------------------------------------------------------------------
# Footprint 4.6 x 5.2 for the podium; the canopy overhangs to 4.9 wide and the pylon sign to
# z = -2.99, so the whole prop is 4.90 x 5.79 studs and 5.98 tall -- inside the contract's 5 x 6.
OUTER_HALF_X = 2.3
WELL_HALF_X = 1.5  # 3 studs clear: the podium is deliberately thin, because every stud of
# side wall is a stud of the well the oblique camera cannot see into.
FRONT_Z = -2.6
BACK_Z = 2.6
APRON = 0.22  # dark kerb band the whole kiosk stands on
HEADHOUSE_FRONT_Z = 1.3

# The stair slope is the one number the whole design turns on.  testfit's camera (and the tycoon
# camera) sits about 23 degrees above the horizon, so treads are only visible while
# rise/run < tan(23 deg) ~= 0.43.  0.26 / 0.72 = 0.36 keeps every tread in view; anything close to
# a real staircase's 0.6 would show only risers.  Three chunky steps beat five thin ones: at this
# size a 0.72-stud tread is still a visible band once foreshortened, a 0.4-stud one is not.
STEP_COUNT = 3
STEP_RISE = 0.26
STEP_RUN = 0.72
TOP_TREAD = 1.03  # y of the highest tread == height of the podium's street edge
LANDING_Y = TOP_TREAD - STEP_COUNT * STEP_RISE  # 0.25
COPING_RISE = 0.20  # podium top above the tread beside it: a kerb, not a parapet.  A parapet tall
# enough to read as a wall would hide the well from the camera -- the Stadium lesson (memory,
# era-kits-2026-09-16): keep both the +X and the -Z sides low when the interior must be seen.
COPING = 0.14  # thickness of the blue cap band on that kerb

PORTAL_HALF_X = 1.2  # narrower than the well, so white jambs frame the tunnel mouth
HEADHOUSE_TOP = 2.55
CANOPY_FRONT_Z = 0.6
CANOPY_BACK_Z = 2.8
CANOPY_HALF_X = 2.45
CANOPY_TOP = 2.85


def sections() -> list[tuple[float, float, float]]:
    """(z0, z1, tread y) for each stair step, then the landing -- shared by the podium and stairs.

    The podium's top follows this table so that its coping steps down in lockstep with the treads:
    that descending line is what reads as "stairs going down" from far away, where the treads
    themselves are only a few pixels.
    """
    out = []
    for i in range(STEP_COUNT):
        z0 = FRONT_Z + i * STEP_RUN
        out.append((z0, z0 + STEP_RUN, TOP_TREAD - i * STEP_RISE))
    out.append((FRONT_Z + STEP_COUNT * STEP_RUN, HEADHOUSE_FRONT_Z, LANDING_Y))
    return out


def log(msg: str) -> None:
    print(f"[metro-kit] {msg}", flush=True)


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


def letter_m(width: float, height: float) -> list[list[tuple[float, float]]]:
    """The "M" as three convex polygons: two upright bars and the downward wedge between them.

    Three pieces that only ever touch along an edge, never overlap -- a stroked M built from
    overlapping bars would put coincident coplanar faces on the sign and z-fight there.
    """
    hw, hh = width / 2.0, height / 2.0
    stroke = width * 0.26
    return [
        [(-hw, -hh), (-hw + stroke, -hh), (-hw + stroke, hh), (-hw, hh)],
        [(hw - stroke, -hh), (hw, -hh), (hw, hh), (hw - stroke, hh)],
        [(0.0, -height * 0.28), (hw - stroke, hh), (-hw + stroke, hh)],
    ]


def add_m(part: Part, centre, frame: str, width: float, height: float, depth: float) -> None:
    for poly in letter_m(width, height):
        part.extrude(poly, centre, frame, 0.0, depth, "wall")


# --- the pieces ---------------------------------------------------------------------------------


def make_plinth() -> Part:
    """The podium: a dark kerb apron and the two side walls whose tops step down with the stairs.

    Placed at the prop origin. 4.6 x 5.2 studs, 1.23 tall at the street edge, 0.45 at the back.
    """
    p = Part("plinth")
    p.box(-OUTER_HALF_X, OUTER_HALF_X, 0.0, APRON, FRONT_Z, BACK_Z, "slate")
    for z0, z1, tread in sections():
        top = tread + COPING_RISE
        for sign in (-1, 1):
            x0, x1 = (WELL_HALF_X, OUTER_HALF_X) if sign > 0 else (-OUTER_HALF_X, -WELL_HALF_X)
            inner = "right" if sign < 0 else "left"  # the face looking into the well stays dark
            p.box(x0, x1, APRON, top - COPING, z0, z1, "wall", **{inner: "slate"})
            p.box(x0, x1, top - COPING, top, z0, z1, "blue")
    return p


def make_stairs() -> Part:
    """Three treads descending from the street edge into a long dark landing.

    Origin is bottom-centre of its own extent, so it drops into the plinth's well at
    (0, APRON, -0.65). 3.0 x 3.9 studs, 0.81 tall.
    """
    p = Part("stairs")
    offset_z = -(FRONT_Z + HEADHOUSE_FRONT_Z) / 2.0  # recentre on the piece's own z extent
    nose = 0.15  # the yellow tactile strip along the top step, as on a real platform edge
    for i, (z0, z1, tread) in enumerate(sections()):
        y = tread - APRON
        z0, z1 = z0 + offset_z, z1 + offset_z
        last = i == len(sections()) - 1
        if i == 0:
            p.box(-WELL_HALF_X, WELL_HALF_X, 0.0, y, z0, z0 + nose, "slate", top="yellow")
            z0 += nose
        if not last:
            # Every riser faces away from a viewer standing above the stair, so the treads alone
            # render as one unbroken white slab.  A dark band along each tread's *trailing* edge
            # puts the step lines back: the leading edge is no good, it sits in the occlusion
            # shadow of the step above and never shows.
            p.box(-WELL_HALF_X, WELL_HALF_X, 0.0, y, z1 - nose * 0.8, z1, "dark", top="dark")
            z1 -= nose * 0.8
        p.box(-WELL_HALF_X, WELL_HALF_X, 0.0, y, z0, z1, "dark", top="dark" if last else "wall")
    return p


def make_headhouse() -> Part:
    """The back wall the stairs run into: a dark portal under a blue "M" band.

    Origin bottom-centre; sits at (0, APRON, 1.95). 4.6 x 1.4 studs, 2.33 tall.
    """
    p = Part("headhouse")
    half_z = (BACK_Z - HEADHOUSE_FRONT_Z) / 2.0
    top = HEADHOUSE_TOP - APRON
    p.box(-OUTER_HALF_X, OUTER_HALF_X, 0.0, 0.18, -half_z, half_z, "slate")
    p.box(-OUTER_HALF_X, OUTER_HALF_X, 0.18, top, -half_z, half_z, "wall")
    # Portal and sign band stand 0.04 proud of the facade rather than being cut into it: a recess
    # would need the facade split into columns and a lintel for no gain at this size.
    # A white threshold line under the portal keeps it from merging with the dark landing floor
    # into one shapeless black mass, which is what the first render did.
    p.box(-PORTAL_HALF_X, PORTAL_HALF_X, LANDING_Y - APRON, LANDING_Y - APRON + 0.14, -half_z - 0.04, -half_z, "wall")
    p.box(-PORTAL_HALF_X, PORTAL_HALF_X, LANDING_Y - APRON + 0.14, 1.32, -half_z - 0.04, -half_z, "dark")
    p.box(-1.7, 1.7, 1.42, 2.12, -half_z - 0.04, -half_z, "blue")
    add_m(p, (0.0, 1.77, -half_z - 0.04), "front", 0.56, 0.56, 0.05)
    return p


def make_canopy() -> Part:
    """Flat roof cantilevered forward off the headhouse, with a blue fascia along its front edge.

    Origin bottom-centre; sits at (0, 2.55, 1.7). 4.9 x 2.2 studs, 0.3 tall. No posts on purpose:
    the first render put two of them beside the pylon mast and the mouth read as a thicket of
    verticals.
    """
    p = Part("canopy")
    half_z = (CANOPY_BACK_Z - CANOPY_FRONT_Z) / 2.0
    p.box(-CANOPY_HALF_X, CANOPY_HALF_X, 0.0, CANOPY_TOP - HEADHOUSE_TOP, -half_z, half_z, "wall", top="trim", bottom="slate")
    p.box(-CANOPY_HALF_X, CANOPY_HALF_X, 0.0, 0.14, -half_z - 0.04, -half_z, "blue")
    return p


def make_pylon() -> Part:
    """Sign mast: a square blue sign box with a white "M" on all four faces, on a slim post.

    Origin bottom-centre; stands on the podium's street edge at (1.65, 1.25, -2.25) and tops out
    4.75 studs above it. The sign carries every face because the tycoon camera can orbit.
    """
    p = Part("pylon")
    p.box(-0.32, 0.32, 0.0, 0.30, -0.32, 0.32, "slate")
    p.box(-0.16, 0.16, 0.30, 3.20, -0.16, 0.16, "trim")
    p.box(-0.70, 0.70, 3.20, 4.60, -0.70, 0.70, "blue")
    p.box(-0.78, 0.78, 4.60, 4.75, -0.78, 0.78, "wall")
    for frame, centre in (
        ("front", (0.0, 3.90, -0.70)),
        ("back", (0.0, 3.90, 0.70)),
        ("right", (0.70, 3.90, 0.0)),
        ("left", (-0.70, 3.90, 0.0)),
    ):
        add_m(p, centre, frame, 1.0, 1.0, 0.06)
    return p


PIECES = {
    "plinth": make_plinth,
    "stairs": make_stairs,
    "headhouse": make_headhouse,
    "canopy": make_canopy,
    "pylon": make_pylon,
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
    parser = argparse.ArgumentParser(description="Generate the metro-kit GLBs.")
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
    log(f"{len(PIECES)} pieces, {total} tris total -> {os.path.relpath(args.out, REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
