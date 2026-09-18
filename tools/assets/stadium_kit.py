"""Custom low-poly stadium pieces for Metropolis, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/stadium_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/stadium-kit/Models/GLB format/, which is the folder
convention every Kenney kit already uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it.

Why a custom kit at all: none of the four City Kits contains a grass, lawn or green ground piece
(green exists only on awnings, planters and signs), so a stadium assembled from them can only put
dark asphalt inside white concrete -- which has no contrast against the Metropolis plot base,
RGB (88, 90, 94). Every colour below is sampled from the commercial kit's own colormap.png so the
pieces still read as part of the same set as the other 23 Metropolis buildings.

Art rules, matching the kit: flat shading only (no smooth normals, no bevels, no subdivision),
axis-aligned boxes with a few inset bands, chunky toy proportions. Materials are plain colour
factors with no texture, exactly like nature-kit and space-kit; merge_stages.py routes those
through palette.py, which bakes them into one swatch texture at merge time.

Geometry is authored in glTF space -- Y up, front -Z, 1 unit = 4 studs at the blueprint's scale
4.0 -- with the origin at bottom-centre, the same convention as the Kenney pieces, so
`--dump-bounds stadium-kit` reads sensibly. Blender is Z up, so every vertex converts with
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
KIT = "stadium-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# sRGB bytes read straight out of
# assets/kenney3d/city-kit-commercial/Models/GLB format/Textures/colormap.png.
# The first five are the kit's wall/trim/shadow ramp, GLASS is its window blue, TURF and
# TURF_DARK are two steps of its one green ramp (the awning/planter green), YELLOW its only
# other accent.  Keeping to the kit's own texels is what makes the stadium sit beside the
# other Metropolis buildings instead of looking imported.
WALL = (255, 255, 255)
SURROUND = (160, 168, 201)
TRIM = (142, 149, 179)
SLATE = (81, 85, 102)
DARK = (56, 56, 61)
GLASS = (208, 232, 255)
TURF = (97, 203, 139)
TURF_DARK = (61, 166, 121)
YELLOW = (255, 192, 68)

COLOURS = {
    "wall": WALL,
    "surround": SURROUND,
    "trim": TRIM,
    "slate": SLATE,
    "dark": DARK,
    "glass": GLASS,
    "turf": TURF,
    "turf-dark": TURF_DARK,
    "yellow": YELLOW,
}

# Seat rows are 0.08 units (0.32 studs) high and deep: shallow enough that three of them read as a
# rake at scale 4.0, deep enough that the risers still catch a shadow.  Every stand keeps its rear
# 0.21 units at full height so the tier stacked on top rests on 42% of its depth and the rest
# cantilevers, which is what a real two-tier stand looks like.
ROW_RISE = 0.08
ROW_RUN = 0.08
REAR = 0.04  # z where the seating stops and the full-height rear block starts


def log(msg: str) -> None:
    print(f"[stadium-kit] {msg}", flush=True)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


# --- mesh building (glTF space: X right, Y up, Z back; front of a piece faces -Z) -------------


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

    def plate(self, x0, x1, z0, z1, y, colour) -> None:
        """One upward-facing quad -- pitch markings, which are seen only from above."""
        self.face([(x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0)], colour)

    def ring(self, cx, cz, r_in, r_out, y, segments, colour) -> None:
        """Upward-facing annulus for the centre circle."""
        for i in range(segments):
            a0 = 2 * math.pi * i / segments
            a1 = 2 * math.pi * (i + 1) / segments
            outer = [(cx + r_out * math.sin(a), y, cz + r_out * math.cos(a)) for a in (a0, a1)]
            inner = [(cx + r_in * math.sin(a), y, cz + r_in * math.cos(a)) for a in (a1, a0)]
            self.face(outer + inner, colour)


def rake(part: Part, base: float, first: float) -> None:
    """Three disjoint seat-row boxes climbing from z = -0.20 to REAR, the lowest topping at `first`.

    Disjoint rather than nested on purpose: nested boxes would put two coincident outward faces on
    the stand's back plane and z-fight there.
    """
    z, top = -0.20, first
    for _ in range(3):
        part.box(-0.5, 0.5, base, top, z, z + ROW_RUN, "wall", top="slate", front="slate")
        z += ROW_RUN
        top += ROW_RISE


# --- the pieces --------------------------------------------------------------------------------


def make_pitch() -> Part:
    """The playing surface: 2.1 x 2.1 units, a pale paved surround, mown turf, white markings."""
    p = Part("pitch")
    half, turf = 1.05, 0.95
    p.box(-half, half, 0.0, 0.04, -half, half, "surround")
    p.box(-turf, turf, 0.0, 0.06, -turf, turf, "turf")
    # Three darker mown bands as solid boxes, kept just inside the turf so no two faces are coplanar.
    for i in (-1, 0, 1):
        cx = i * 0.475
        p.box(cx - 0.155, cx + 0.155, 0.0, 0.07, -0.94, 0.94, "turf-dark")
    y, w = 0.09, 0.025
    edge = turf - 0.12
    p.plate(-edge, edge, edge - w, edge, y, "wall")              # goal line, back
    p.plate(-edge, edge, -edge, -edge + w, y, "wall")            # goal line, front
    p.plate(-edge, -edge + w, -edge, edge, y, "wall")            # touchline
    p.plate(edge - w, edge, -edge, edge, y, "wall")              # touchline
    p.plate(-edge, edge, -w / 2, w / 2, y, "wall")               # halfway line
    p.ring(0.0, 0.0, 0.24, 0.24 + w, y, 16, "wall")              # centre circle
    for side in (-1, 1):                                          # penalty areas
        z_out, z_in = side * edge, side * (edge - 0.26)
        lo, hi = min(z_in, z_out), max(z_in, z_out)
        p.plate(-0.42, 0.42, z_in - w / 2, z_in + w / 2, y, "wall")
        p.plate(-0.42, -0.42 + w, lo, hi, y, "wall")
        p.plate(0.42 - w, 0.42, lo, hi, y, "wall")
    return p


def make_terrace() -> Part:
    """Ground-level seating bank, 1.0 x 0.40 x 0.5 units, rake facing -Z."""
    p = Part("terrace")
    p.box(-0.5, 0.5, 0.0, 0.10, -0.25, -0.20, "wall")            # pitch-side parapet
    rake(p, 0.0, 0.18)
    p.box(-0.5, 0.5, 0.0, 0.40, REAR, 0.19, "wall", top="trim")  # rear walkway
    p.box(-0.5, 0.5, 0.0, 0.06, 0.19, 0.25, "dark")              # plinth band on the outer face
    p.box(-0.5, 0.5, 0.06, 0.40, 0.19, 0.25, "wall", top="trim")
    return p


def make_tier() -> Part:
    """Cantilevered upper deck, 1.0 x 0.50 x 0.5 units, flat bottom so it stacks on a terrace."""
    p = Part("tier")
    p.box(-0.5, 0.5, 0.00, 0.05, -0.25, 0.25, "slate")           # soffit under the cantilever
    p.box(-0.5, 0.5, 0.05, 0.13, -0.25, 0.25, "glass")           # executive boxes
    p.box(-0.5, 0.5, 0.13, 0.16, -0.25, 0.25, "wall")            # sill
    p.box(-0.5, 0.5, 0.16, 0.24, -0.25, -0.20, "wall")           # parapet
    rake(p, 0.16, 0.34)
    p.box(-0.5, 0.5, 0.16, 0.50, REAR, 0.25, "wall", top="trim")
    return p


def make_roof() -> Part:
    """Flat cantilevered roof, 1.0 x 0.18 x 0.75 units; overhangs 0.25 past the stand front."""
    p = Part("roof")
    p.box(-0.5, 0.5, 0.0, 0.10, -0.45, 0.25, "trim", top="wall", bottom="slate")
    p.box(-0.5, 0.5, 0.0, 0.18, -0.50, -0.45, "slate")           # fascia beam
    return p


def make_floodlight() -> Part:
    """Mast with a lamp rack facing -Z, 0.30 x 1.00 x 0.30 units; sits on a stand roof."""
    p = Part("floodlight")
    p.box(-0.09, 0.09, 0.00, 0.06, -0.09, 0.09, "slate")
    p.box(-0.06, 0.06, 0.06, 0.84, -0.06, 0.06, "wall")
    p.box(-0.15, 0.15, 0.84, 1.00, -0.05, 0.07, "slate")
    p.box(-0.13, 0.13, 0.86, 0.98, -0.07, -0.05, "glass")        # lamp faces, toward the pitch
    return p


def make_scoreboard() -> Part:
    """Screen on two legs, 1.0 x 0.52 x 0.14 units, face toward -Z."""
    p = Part("scoreboard")
    for side in (-1, 1):
        cx = side * 0.33
        p.box(cx - 0.04, cx + 0.04, 0.00, 0.24, -0.04, 0.04, "slate")
    p.box(-0.45, 0.45, 0.24, 0.48, -0.05, 0.05, "wall")
    p.box(-0.40, 0.40, 0.26, 0.46, -0.07, -0.05, "dark")
    p.box(-0.45, 0.45, 0.48, 0.52, -0.05, 0.05, "turf")          # kit-green cap band
    return p


def make_hoarding() -> Part:
    """Perimeter advertising board, 1.0 x 0.12 x 0.06 units; face toward -Z."""
    p = Part("hoarding")
    p.box(-0.5, 0.5, 0.00, 0.02, -0.03, 0.03, "slate")
    p.box(-0.5, 0.5, 0.02, 0.12, -0.03, 0.03, "wall", front="turf", back="yellow")
    return p


def make_dugout() -> Part:
    """Team shelter, 0.52 x 0.20 x 0.26 units, opening toward -Z."""
    p = Part("dugout")
    p.box(-0.24, 0.24, 0.00, 0.16, 0.06, 0.12, "wall")
    p.box(-0.22, 0.22, 0.00, 0.05, -0.04, 0.06, "slate")
    p.box(-0.26, 0.26, 0.16, 0.20, -0.14, 0.12, "turf")
    return p


PIECES = {
    "pitch": make_pitch,
    "terrace": make_terrace,
    "tier": make_tier,
    "roof": make_roof,
    "floodlight": make_floodlight,
    "scoreboard": make_scoreboard,
    "hoarding": make_hoarding,
    "dugout": make_dugout,
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
    parser = argparse.ArgumentParser(description="Generate the stadium-kit GLBs.")
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
        tris = sum(len(idx) - 2 for idx, _ in part.faces)
        total += tris
        log(f"{name}.glb: {len(part.faces)} faces, {tris} tris")
    log(f"{len(PIECES)} pieces, {total} tris total -> {os.path.relpath(args.out, REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
