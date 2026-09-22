"""Custom classical pieces for the Metropolis City Hall, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/cityhall_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/cityhall-kit/Models/GLB format/, the folder
convention every Kenney kit uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py
discover the kit with no registration step. assets/ is gitignored, so this script is the committed
artifact and the GLBs regenerate from it. Same pattern as metro_kit.py / stadium_kit.py.

Why a custom kit: city-kit-commercial has no dome, no drum, no column and no classical cornice,
and the stand-ins the first City Hall used (`tile-high` slabs, `bridge-pillar-wide` posts) are the
kit's *lavender* trim colour -- Ben judged the result in a full-plot render as a dull grey-violet
mass beside the white-and-glass towers, and 16.5 studs left it shorter than its six-storey
neighbours. These pieces are the fix: the same silhouette in the kit's own WHITE (the colour the
towers are made of) with one saturated accent, plus the dome that lifts it to 22 studs.

Art rules, matching the City Kits: flat shading only (no smooth normals, no bevels, no
subdivision), chunky toy proportions, low segment counts (16 around the dome and drum, 12 on a
column shaft, 8 on the lantern) so the facets stay visible. Materials are plain colour factors
with no texture, exactly like nature-kit and space-kit; merge_stages.py routes those through
palette.py, which bakes them into one swatch texture at merge time.

**Units: 1 glTF unit = 4 studs**, the Kenney City Kit convention -- NOT metro-kit's 1 unit = 1 stud.
These pieces share one blueprint with city-kit-commercial's white `low-detail-building-*` boxes,
and a blueprint's `scale` applies to the whole assembly, so a custom piece mixed into a City Kit
building has to be authored in that kit's units. CityHall.json therefore stays at `"scale": 4.0`.

Geometry is authored in glTF space -- Y up, front -Z (the plot entrance), each piece recentred on
its own bottom-centre origin so blueprint positions read as offsets from the slot anchor. Blender
is Z up, so every vertex converts with (x, y, z) -> (x, -z, y); that map is a proper rotation, so
face winding carries over unchanged.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "cityhall-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# sRGB bytes read straight out of
# assets/kenney3d/city-kit-commercial/Models/GLB format/Textures/colormap.png, so this kit cannot
# drift from the 24 buildings it stands among. WHITE is the towers' wall colour (the whole point of
# the recolour), GREEN the kit's one saturated accent (its awnings and building-m's roof) which
# here reads as a verdigris copper dome, GOLD its amber, SLATE/DARK its shadow ramp.
WHITE = (255, 255, 255)
SLATE = (81, 85, 102)
DARK = (56, 56, 61)
GREEN = (97, 203, 139)
GOLD = (255, 192, 68)

COLOURS = {"white": WHITE, "slate": SLATE, "dark": DARK, "green": GREEN, "gold": GOLD}

# --- dimensions, in kit units (x4 = studs) ------------------------------------------------------
# The vertical stack the blueprint builds, bottom to top:
#   0.00 podium (2 slab courses)  0.50 hall body (city-kit-commercial)  2.05 cornice
#   0.75 hall body   2.30 cornice   2.50 attic   2.75 drum   3.85 dome   4.55 lantern -> 5.17
# 5.17 units = 20.7 studs: above the six-storey neighbours and well under BroadcastTower's
# 28.6, as the brief requires. The dome is deliberately shallower than a hemisphere (0.70 tall
# on a 1.20 base): the first pass at 1.05 stepped up like a beehive rather than a dome.
SEG = 16  # dome and drum segments: enough to read round at 4x, few enough to stay faceted
LANTERN_SEG = 8
SHAFT_SEG = 12

SLAB_H = 0.25  # slabs tile edge to edge; never overlap two, their top faces would z-fight
CORNICE_W, CORNICE_H, CORNICE_D = 2.10, 0.20, 1.10
COLUMN_H = 1.00
PEDIMENT_W, PEDIMENT_H, PEDIMENT_D = 2.10, 0.34, 0.55
DRUM_H, DRUM_R = 1.10, 0.52
DOME_H, DOME_R = 0.70, 0.60
LANTERN_H = 0.62
CLOCK_R = 0.13

# A facet of the drum must face -Z so the clock lands flat on it rather than across a corner.
# Vertices sit at phase + k*2pi/SEG, so a facet centre falls on -Z when phase is half a segment
# short of -90 degrees.
DRUM_PHASE = -math.pi / 2.0 - math.pi / SEG


def log(msg: str) -> None:
    print("[cityhall-kit] " + msg, flush=True)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


# --- mesh building (glTF space: X right, Y up, Z back; front of a piece faces -Z) ----------------


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
        """Axis-aligned box. `sides` overrides per face: top, bottom, front (-Z), back, left, right."""
        c = {k: sides.get(k, colour) for k in ("top", "bottom", "front", "back", "left", "right")}
        self.face([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], c["back"])
        self.face([(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)], c["front"])
        self.face([(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)], c["right"])
        self.face([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], c["left"])
        self.face([(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)], c["top"])
        self.face([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], c["bottom"])

    # -- bodies of revolution ----------------------------------------------------------------
    @staticmethod
    def _ring(r: float, n: int, phase: float) -> list[tuple[float, float]]:
        return [
            (r * math.cos(phase + 2.0 * math.pi * k / n), r * math.sin(phase + 2.0 * math.pi * k / n))
            for k in range(n)
        ]

    def frustum(self, r0, r1, y0, y1, colour, n=SEG, phase=0.0) -> None:
        """Side wall of a cone or cylinder band: radius r0 at y0, r1 at y1."""
        lo, hi = self._ring(r0, n, phase), self._ring(r1, n, phase)
        for k in range(n):
            j = (k + 1) % n
            self.face(
                [
                    (lo[k][0], y0, lo[k][1]),
                    (hi[k][0], y1, hi[k][1]),
                    (hi[j][0], y1, hi[j][1]),
                    (lo[j][0], y0, lo[j][1]),
                ],
                colour,
            )

    def cap(self, r, y, colour, up=True, n=SEG, phase=0.0) -> None:
        pts = [(p[0], y, p[1]) for p in self._ring(r, n, phase)]
        self.face(list(reversed(pts)) if up else pts, colour)

    def ledge(self, r_in, r_out, y, colour, up=True, n=SEG, phase=0.0) -> None:
        """Horizontal annulus: the visible step between two bands of a stepped dome."""
        a, b = self._ring(r_in, n, phase), self._ring(r_out, n, phase)
        for k in range(n):
            j = (k + 1) % n
            quad = [
                (a[k][0], y, a[k][1]),
                (a[j][0], y, a[j][1]),
                (b[j][0], y, b[j][1]),
                (b[k][0], y, b[k][1]),
            ]
            self.face(quad if up else list(reversed(quad)), colour)

    def xy_prism(self, poly: list[tuple[float, float]], z0: float, z1: float, colour: str) -> None:
        """Counter-clockwise (x, y) polygon extruded from z0 (front) to z1 (back)."""
        area = sum(
            poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
            for i in range(len(poly))
        )
        assert area > 0, self.name + ": polygon must be counter-clockwise"
        self.face([(x, y, z1) for x, y in poly], colour)
        self.face([(x, y, z0) for x, y in reversed(poly)], colour)
        for i, (x0, y0) in enumerate(poly):
            x1, y1 = poly[(i + 1) % len(poly)]
            self.face([(x0, y0, z0), (x1, y1, z0), (x1, y1, z1), (x0, y0, z1)], colour)

    def bounds(self):
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _ in self.faces)


# --- the pieces ---------------------------------------------------------------------------------


def make_slab() -> Part:
    """1 x 1 x 0.25 plain white stone course: the podium steps and the attic storey.

    Deliberately featureless so copies laid edge to edge merge into one block. It is the same size
    as the lavender `tile-high` it replaces, so the blueprint keeps its grid.
    """
    p = Part("slab")
    p.box(-0.5, 0.5, 0.0, SLAB_H, -0.5, 0.5, "white", bottom="slate")
    return p


def make_cornice() -> Part:
    """Projecting white cornice, 2.10 x 0.20 x 1.10: the entablature over the colonnade and the
    hall's roof band. Three courses (fascia, corona, cyma) so the shadow line reads at 4x."""
    p = Part("cornice")
    hw, hd = CORNICE_W / 2.0, CORNICE_D / 2.0
    p.box(-hw + 0.05, hw - 0.05, 0.00, 0.06, -hd + 0.05, hd - 0.05, "slate")
    p.box(-hw, hw, 0.06, 0.16, -hd, hd, "white")
    p.box(-hw + 0.04, hw - 0.04, 0.16, CORNICE_H, -hd + 0.04, hd - 0.04, "white")
    return p


def make_column() -> Part:
    """Plain classical column, 1.00 tall: square plinth, 12-sided tapered shaft, square capital.

    Replaces `bridge-pillar-wide`, whose dark joint bands read as an industrial pipe rather than a
    colonnade. The taper is not decoration: a shaft of constant width reads as fatter at the top.
    """
    p = Part("column")
    p.box(-0.09, 0.09, 0.00, 0.06, -0.09, 0.09, "white", bottom="slate")
    p.cap(0.066, 0.06, "white", up=True, n=SHAFT_SEG)
    p.frustum(0.066, 0.058, 0.06, 0.88, "white", n=SHAFT_SEG)
    p.cap(0.058, 0.88, "white", up=True, n=SHAFT_SEG)
    p.box(-0.085, 0.085, 0.88, 0.96, -0.085, 0.085, "white")
    p.box(-0.095, 0.095, 0.96, COLUMN_H, -0.095, 0.095, "white")
    return p


def make_pediment() -> Part:
    """Low classical pediment, 2.10 x 0.34 x 0.55, over the portico: a real triangular prism where
    the first version had a pair of road wedges meeting at a ridge."""
    p = Part("pediment")
    hw, hd = PEDIMENT_W / 2.0, PEDIMENT_D / 2.0
    p.xy_prism([(-hw, 0.0), (hw, 0.0), (0.0, PEDIMENT_H)], -hd, hd, "white")
    inset, lift = 0.22, 0.055  # tympanum: the recessed panel inside the raking cornice
    p.xy_prism(
        [(-hw + inset, lift), (hw - inset, lift), (0.0, PEDIMENT_H - lift * 1.6)],
        -hd - 0.012,
        -hd,
        "slate",
    )
    return p


def make_drum() -> Part:
    """The dome's drum, 16-sided, 1.05 tall, with a slate window band and a cornice ring."""
    p = Part("drum")
    kw = dict(n=SEG, phase=DRUM_PHASE)
    p.cap(0.58, 0.0, "slate", up=False, **kw)
    p.frustum(0.58, 0.58, 0.00, 0.11, "white", **kw)
    p.ledge(0.52, 0.58, 0.11, "white", up=True, **kw)
    p.frustum(0.52, 0.52, 0.11, 0.38, "white", **kw)
    # One continuous window band, not 16 windows: at 4x each facet is under a stud wide.
    p.frustum(0.515, 0.515, 0.38, 0.66, "slate", **kw)
    p.frustum(0.52, 0.52, 0.66, 0.93, "white", **kw)
    p.ledge(0.52, 0.60, 0.93, "white", up=True, **kw)
    p.frustum(0.60, 0.60, 0.93, 1.03, "white", **kw)
    p.ledge(0.55, 0.60, 1.03, "white", up=True, **kw)
    p.frustum(0.55, 0.55, 1.03, DRUM_H, "white", **kw)
    p.cap(0.55, DRUM_H, "white", up=True, **kw)
    return p


def dome_rings(radius: float, height: float, count: int) -> list[tuple[float, float]]:
    """(radius, y) along a quarter ellipse, truncated below the pole so a lantern can sit on it."""
    top = math.radians(70.0)
    return [
        (radius * math.cos(top * i / count), height * math.sin(top * i / count) / math.sin(top))
        for i in range(count + 1)
    ]


def make_dome() -> Part:
    """Stepped verdigris dome, 16 segments by 5 bands, 1.05 tall on a 1.20 base.

    Each band is a frustum capped by a horizontal annulus, so the profile steps like a ribbed
    copper dome instead of reading as one flat green shell.
    """
    p = Part("dome")
    rings = dome_rings(DOME_R, DOME_H * 0.90, 5)
    p.cap(rings[0][0], 0.0, "slate", up=False)
    for i in range(len(rings) - 1):
        (r0, y0), (r1, y1) = rings[i], rings[i + 1]
        step = 0.02
        p.frustum(r0, r1 + step, y0, y1, "green")
        # The ledge stays green: a white annulus here striped the dome like a beach ball in the
        # first pass. Flat shading alone makes the step read, because the horizontal face catches
        # a different amount of light than the slope above it.
        p.ledge(r1, r1 + step, y1, "green", up=True)
    r_top, y_top = rings[-1]
    p.frustum(r_top, r_top, y_top, DOME_H, "white")  # collar the lantern stands on
    p.cap(r_top, DOME_H, "white", up=True)
    return p


def make_lantern() -> Part:
    """Cupola: an octagonal open lantern under a small green cap and a gold finial, 0.90 tall."""
    p = Part("lantern")
    kw = dict(n=LANTERN_SEG, phase=math.pi / LANTERN_SEG)
    p.cap(0.24, 0.0, "slate", up=False, **kw)
    p.frustum(0.24, 0.24, 0.00, 0.06, "white", **kw)
    p.ledge(0.19, 0.24, 0.06, "white", up=True, **kw)
    p.frustum(0.19, 0.19, 0.06, 0.26, "slate", **kw)  # the openings between the posts
    p.ledge(0.19, 0.25, 0.26, "white", up=True, **kw)
    p.frustum(0.25, 0.25, 0.26, 0.32, "white", **kw)
    p.ledge(0.21, 0.25, 0.32, "white", up=True, **kw)
    cap_rings = dome_rings(0.21, 0.15, 3)
    for i in range(len(cap_rings) - 1):
        (r0, y0), (r1, y1) = cap_rings[i], cap_rings[i + 1]
        p.frustum(r0, r1, 0.32 + y0, 0.32 + y1, "green", **kw)
    p.frustum(cap_rings[-1][0], 0.05, 0.32 + cap_rings[-1][1], 0.50, "gold", **kw)
    p.frustum(0.05, 0.05, 0.50, 0.54, "gold", **kw)
    p.frustum(0.03, 0.075, 0.54, 0.58, "gold", **kw)
    p.frustum(0.075, 0.0, 0.58, LANTERN_H, "gold", **kw)
    return p


def make_clock() -> Part:
    """Clock face for the drum: gold rim, white dial, slate hands at 10:10, 0.26 across.

    Authored in the XY plane facing -Z with its origin at the back of the disc, so the blueprint
    places it by the drum facet it sits against.
    """
    p = Part("clock")
    ring = [
        (CLOCK_R * math.cos(2.0 * math.pi * k / SEG), CLOCK_R * math.sin(2.0 * math.pi * k / SEG))
        for k in range(SEG)
    ]
    p.xy_prism(ring, -0.05, 0.0, "gold")
    p.xy_prism([(x * 0.82, y * 0.82) for x, y in ring], -0.058, -0.05, "white")

    def hand(length: float, width: float, degrees: float) -> None:
        ca, sa = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
        pts = [(-width, -width), (length, -width), (length, width), (-width, width)]
        p.xy_prism([(x * ca - y * sa, x * sa + y * ca) for x, y in pts], -0.068, -0.058, "slate")

    hand(0.062, 0.013, 60.0)  # 10:10, the pose a clock is always drawn in
    hand(0.088, 0.010, 120.0)
    return p


PIECES = {
    "slab": make_slab,
    "cornice": make_cornice,
    "column": make_column,
    "pediment": make_pediment,
    "drum": make_drum,
    "dome": make_dome,
    "lantern": make_lantern,
    "clock": make_clock,
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
        filepath=os.path.join(out_dir, obj.name + ".glb"),
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
    parser = argparse.ArgumentParser(description="Generate the cityhall-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    total = 0
    for name, make in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        cache: dict = {}
        part = make()
        assert part.name == name, name + ": Part is misnamed"
        obj = build_object(part, cache)
        export(obj, args.out)
        total += part.tris
        lo, hi = part.bounds()
        size = tuple(round((hi[i] - lo[i]) * 4.0, 2) for i in range(3))
        log(
            "%s.glb: %d tris, %.2f x %.2f x %.2f studs, min y %.2f"
            % (name, part.tris, size[0], size[1], size[2], lo[1])
        )
    log("%d pieces, %d tris total -> %s" % (len(PIECES), total, os.path.relpath(args.out, REPO_ROOT)))
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
