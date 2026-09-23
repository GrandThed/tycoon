"""Custom low-poly garden pieces for Boomtown and Metropolis, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/garden_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/garden-kit/Models/GLB format/, the folder convention
every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py discover the kit
with no registration step. assets/ is gitignored, so this script is the committed artifact and the
GLBs regenerate from it. Same pattern as metro_kit.py and stadium_kit.py.

Why a custom kit at all (INTERFACES "Wave 2c -- living city", Greenery): the four City Kits have
no bush, hedge or flower piece -- their green is only lollipop trees, awnings and one planter -- so
a street verge assembled from them stays bare. Every colour below is a texel of the City Kits'
shared colormap.png, so the pieces sit in the same palette as the buildings.

Art rules, matching the kits: flat shading only, faceted low-poly blobs and axis-aligned boxes,
chunky toy proportions. Materials are plain colour factors with no texture; merge_stages.py routes
them through palette.py, which bakes them into one swatch texture at merge time.

**Units: 1 glTF unit = 1 stud** (blueprints use `"scale": 1.0`), so every literal is directly
checkable against the contract sizes. Scale reference at the kits' blueprint scale 4: a suburban
tree-small is 0.84 wide and 2.27 tall, a building-type-a house 3.3 tall, so bushes stay around a
stud and never out-bulk the trees.

Geometry is authored in glTF space -- Y up, front -Z -- with each piece's origin at its bottom
centre. Blender is Z up, so every vertex converts with (x, y, z) -> (x, -z, y); that map is a
proper rotation, so face winding carries over unchanged. people_kit.py imports the mesh helpers
from here rather than keeping a third copy of them.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "garden-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

Rgb = tuple[int, int, int]

# sRGB bytes read out of assets/kenney3d/city-kit-suburban/Models/GLB format/Textures/colormap.png
# (the commercial kit's colormap carries the same swatches). LEAF/LEAF_DARK are the kit's only two
# greens: the awning/planter green and the shaded step of its ramp.
LEAF = (97, 203, 139)
LEAF_DARK = (61, 167, 122)
BRICK = (176, 96, 65)
TERRACOTTA = (212, 116, 93)
STONE = (160, 168, 201)
STONE_DARK = (134, 139, 161)
SOIL = (79, 82, 96)
PINK = (243, 120, 240)
YELLOW = (255, 192, 68)
RED = (207, 83, 79)
WHITE = (255, 255, 255)
PURPLE = (168, 120, 232)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


# --- mesh building (glTF space: X right, Y up, Z back; front of a piece faces -Z) ----------------


class Part:
    """Accumulates flat-shaded polygons, each tagged with its sRGB colour."""

    def __init__(self, name: str):
        self.name = name
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[list[int], Rgb]] = []

    def face(self, points, colour: Rgb, centre=None) -> None:
        """Add a polygon. With `centre` (a point inside the convex primitive it belongs to), the
        winding is flipped if needed so the normal points away from it -- the blob's staggered
        fans and hand-listed hexahedron corners are too easy to wind backwards by hand."""
        points = [tuple(p) for p in points]
        if centre is not None:
            n = [0.0, 0.0, 0.0]
            for i, a in enumerate(points):  # Newell normal: robust for non-planar quads
                b = points[(i + 1) % len(points)]
                n[0] += (a[1] - b[1]) * (a[2] + b[2])
                n[1] += (a[2] - b[2]) * (a[0] + b[0])
                n[2] += (a[0] - b[0]) * (a[1] + b[1])
            mid = [sum(p[i] for p in points) / len(points) for i in range(3)]
            if sum(n[i] * (mid[i] - centre[i]) for i in range(3)) < 0:
                points.reverse()
        base = len(self.verts)
        self.verts.extend(points)
        self.faces.append(([base + i for i in range(len(points))], colour))

    def hexa(self, corners, colour: Rgb, **sides) -> None:
        """Any convex hexahedron from its 8 corners, ordered bottom (y0) then top (y1), each ring
        as (-x,-z), (+x,-z), (+x,+z), (-x,+z). `sides` overrides one face's colour: top, bottom,
        front (-Z), back, left, right."""
        c = {k: sides.get(k, colour) for k in ("top", "bottom", "front", "back", "left", "right")}
        b0, b1, b2, b3, t0, t1, t2, t3 = corners
        mid = tuple(sum(p[i] for p in corners) / 8.0 for i in range(3))
        self.face([b3, b2, t2, t3], c["back"], mid)
        self.face([b1, b0, t0, t1], c["front"], mid)
        self.face([b2, b1, t1, t2], c["right"], mid)
        self.face([b0, b3, t3, t0], c["left"], mid)
        self.face([t3, t2, t1, t0], c["top"], mid)
        self.face([b0, b1, b2, b3], c["bottom"], mid)

    def box(self, x0, x1, y0, y1, z0, z1, colour: Rgb, **sides) -> None:
        self.frustum(x0, x1, z0, z1, y0, x0, x1, z0, z1, y1, colour, **sides)

    def frustum(self, bx0, bx1, bz0, bz1, y0, tx0, tx1, tz0, tz1, y1, colour: Rgb, **sides) -> None:
        """A box whose top rectangle differs from its bottom one: skirts, smocks, tapered torsos."""
        self.hexa(
            [
                (bx0, y0, bz0), (bx1, y0, bz0), (bx1, y0, bz1), (bx0, y0, bz1),
                (tx0, y1, tz0), (tx1, y1, tz0), (tx1, y1, tz1), (tx0, y1, tz1),
            ],
            colour,
            **sides,
        )

    def blob(self, centre, radii, colour: Rgb, seg: int = 7, rings: int = 3, cut: float = -0.35,
             jitter: float = 0.0, seed: int = 0) -> None:
        """Faceted ellipsoid, the Kenney bush/canopy look: `rings` latitude bands between the flat
        bottom cap (at sin(latitude) = `cut`) and a pole. `jitter` nudges each ring vertex's radius
        (seeded, so the GLB is byte-stable) so clusters of blobs stop looking machined."""
        cx, cy, cz = centre
        rx, ry, rz = radii
        rng = random.Random(seed)
        lat0 = math.asin(cut)
        ring_pts = []
        for r in range(rings + 1):
            lat = lat0 + (math.pi / 2 * 0.82 - lat0) * r / rings
            twist = (r % 2) * math.pi / seg  # stagger alternate rings: more facets, same tri count
            pts = []
            for s in range(seg):
                a = 2 * math.pi * s / seg + twist
                k = 1.0 + (rng.uniform(-jitter, jitter) if jitter else 0.0)
                pts.append((
                    cx + rx * math.cos(lat) * math.cos(a) * k,
                    cy + ry * math.sin(lat),
                    cz + rz * math.cos(lat) * math.sin(a) * k,
                ))
            ring_pts.append(pts)
        mid = (cx, cy + ry * (cut + 1.0) / 2.0, cz)
        self.face(list(ring_pts[0]), colour, mid)
        for r in range(rings):
            lo, hi = ring_pts[r], ring_pts[r + 1]
            for s in range(seg):
                n = (s + 1) % seg
                if r % 2 == 0:
                    self.face([lo[s], hi[s], lo[n]], colour, mid)
                    self.face([lo[n], hi[s], hi[n]], colour, mid)
                else:
                    self.face([hi[s], lo[s], hi[n]], colour, mid)
                    self.face([lo[s], lo[n], hi[n]], colour, mid)
        top = ring_pts[-1]
        pole = (cx, cy + ry, cz)
        for s in range(seg):
            self.face([top[s], pole, top[(s + 1) % seg]], colour, mid)

    def bounds(self):
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _ in self.faces)


# --- the pieces ---------------------------------------------------------------------------------


def make_bush_a() -> Part:
    """Round leafy clump: one big blob flanked by two smaller, darker ones.

    1.5 x 0.95 x 1.2 studs -- a little wider than a suburban tree canopy, half its height.
    """
    p = Part("bush-a")
    p.blob((0.0, 0.217, 0.0), (0.58, 0.62, 0.52), LEAF, seg=8, rings=3, jitter=0.08, seed=11)
    p.blob((0.46, 0.147, 0.18), (0.36, 0.42, 0.34), LEAF_DARK, seg=7, rings=2, jitter=0.1, seed=12)
    p.blob((-0.42, 0.14, -0.16), (0.34, 0.4, 0.32), LEAF_DARK, seg=7, rings=2, jitter=0.1, seed=13)
    return p


def make_bush_b() -> Part:
    """Flowering shrub: a dark-green dome studded with pink and white blooms.

    Blooms are chunky cubes pushed half out of the surface; anything finer vanishes at the tycoon
    camera. 1.1 x 1.0 x 1.05 studs.
    """
    p = Part("bush-b")
    rx, ry, rz = 0.56, 0.72, 0.52
    cy = ry * 0.35  # the default cut puts the flat bottom cap on the ground
    p.blob((0.0, cy, 0.0), (rx, ry, rz), LEAF_DARK, seg=8, rings=3, jitter=0.06, seed=21)
    rng = random.Random(22)
    s = 0.055
    for i in range(18):
        a = 2 * math.pi * i / 18 + rng.uniform(-0.2, 0.2)
        lat = math.radians(rng.uniform(5, 62))
        x = rx * 0.94 * math.cos(lat) * math.cos(a)
        y = cy + ry * 0.94 * math.sin(lat)
        z = rz * 0.94 * math.cos(lat) * math.sin(a)
        p.box(x - s, x + s, y - s, y + s, z - s, z + s, PINK if i % 3 else WHITE)
    return p


def make_flower_bed() -> Part:
    """Raised bed: a stone kerb round dark soil, three rows of leaf tufts carrying bright blooms.

    3.0 x 2.0 studs, kerb 0.32 tall, blooms top out at 0.72.
    """
    p = Part("flower-bed")
    hx, hz, kerb, wall = 1.5, 1.0, 0.32, 0.16
    # Four kerb walls rather than one slab under the soil, so the soil face is the only top inside.
    p.box(-hx, hx, 0.0, kerb, -hz, -hz + wall, STONE, top=STONE_DARK)
    p.box(-hx, hx, 0.0, kerb, hz - wall, hz, STONE, top=STONE_DARK)
    p.box(-hx, -hx + wall, 0.0, kerb, -hz + wall, hz - wall, STONE, top=STONE_DARK)
    p.box(hx - wall, hx, 0.0, kerb, -hz + wall, hz - wall, STONE, top=STONE_DARK)
    soil_y = kerb - 0.06
    p.box(-hx + wall, hx - wall, 0.0, soil_y, -hz + wall, hz - wall, SOIL)
    blooms = (RED, YELLOW, PINK, WHITE, PURPLE)
    rng = random.Random(31)
    for row, z in enumerate((-0.5, 0.0, 0.5)):
        for col in range(5):
            x = -1.0 + col * 0.5 + (0.12 if row % 2 else -0.05)
            leaf = LEAF if (row + col) % 2 else LEAF_DARK
            p.blob((x, soil_y, z), (0.2, 0.26, 0.2), leaf, seg=6, rings=2, cut=0.0, seed=100 + row * 5 + col)
            bloom = blooms[(row * 2 + col) % len(blooms)]
            by = soil_y + 0.26 + rng.uniform(0.0, 0.04)
            s = 0.09
            p.box(x - s, x + s, by - 0.04, by + 0.08, z - s, z + s, bloom)
    return p


def make_hedge() -> Part:
    """Clipped hedge segment, 4.0 x 0.9 x 1.0 studs: a dark shaded core under a row of lighter
    rounded crowns. The first render was a chamfered box and read as a green wall beside the
    3.3-stud suburban houses; the scalloped crown is what says "hedge". Crowns stop inside the ends
    so segments butt into a run without doubling up. Each crown's widest ring sits exactly on the
    core's top edge: set any lower and it pokes specks through the core's side faces."""
    p = Part("hedge")
    hx, hz = 2.0, 0.45
    p.box(-hx, hx, 0.0, 0.62, -hz, hz, LEAF_DARK)
    for i in range(5):
        x = -1.56 + i * 0.78
        p.blob((x, 0.62, 0.0), (0.41, 0.4, hz + 0.02), LEAF, seg=7, rings=2, cut=0.0, jitter=0.06, seed=41 + i)
    return p


def make_planter() -> Part:
    """Square concrete street planter with a round clipped shrub: 1.6 x 1.6 studs, 1.5 tall."""
    p = Part("planter")
    hx, h, wall = 0.8, 0.62, 0.14
    p.box(-hx, hx, 0.0, 0.08, -hx, hx, STONE_DARK)
    p.box(-hx, hx, 0.08, h, -hx, -hx + wall, STONE, top=WHITE)
    p.box(-hx, hx, 0.08, h, hx - wall, hx, STONE, top=WHITE)
    p.box(-hx, -hx + wall, 0.08, h, -hx + wall, hx - wall, STONE, top=WHITE)
    p.box(hx - wall, hx, 0.08, h, -hx + wall, hx - wall, STONE, top=WHITE)
    p.box(-hx + wall, hx - wall, 0.08, h - 0.08, -hx + wall, hx - wall, SOIL)
    p.blob((0.0, h + 0.12, 0.0), (0.52, 0.5, 0.52), LEAF, seg=8, rings=3, cut=-0.3, jitter=0.05, seed=51)
    return p


PIECES = {
    "bush-a": make_bush_a,
    "bush-b": make_bush_b,
    "flower-bed": make_flower_bed,
    "hedge": make_hedge,
    "planter": make_planter,
}


# --- Blender plumbing ---------------------------------------------------------------------------


def material_for(colour: Rgb, cache: dict):
    if colour in cache:
        return cache[colour]
    mat = bpy.data.materials.new("c_%02x%02x%02x" % colour)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    r, g, b = colour
    bsdf.inputs["Base Color"].default_value = (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    cache[colour] = mat
    return mat


def build_object(part: Part, cache: dict):
    used = sorted({c for _, c in part.faces})
    mesh = bpy.data.meshes.new(part.name)
    verts = [(x, -z, y) for (x, y, z) in part.verts]  # glTF -> Blender, a proper rotation
    mesh.from_pydata(verts, [], [idx for idx, _ in part.faces])
    mesh.update()
    for colour in used:
        mesh.materials.append(material_for(colour, cache))
    slot = {colour: i for i, colour in enumerate(used)}
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


def generate(kit: str, pieces: dict, out_dir: str) -> int:
    """Build, export and measure every piece; shared with people_kit.py."""
    os.makedirs(out_dir, exist_ok=True)
    total = 0
    for name, make in pieces.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        export(build_object(part, {}), out_dir)
        total += part.tris
        lo, hi = part.bounds()
        size = tuple(round(hi[i] - lo[i], 2) for i in range(3))
        print(
            f"[{kit}] {name}.glb: {part.tris} tris, {size[0]} x {size[1]} x {size[2]} studs, "
            f"min y {lo[1]:.2f}",
            flush=True,
        )
    print(f"[{kit}] {len(pieces)} pieces, {total} tris total -> {os.path.relpath(out_dir, REPO_ROOT)}", flush=True)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the garden-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)
    return generate(KIT, PIECES, args.out)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
