"""Elevated monorail pieces for Orbital Colony, generated as a Kenney-style kit.

Runs inside Blender (headless):

    blender -b -P tools/assets/monorail_kit.py [-- --out <dir>]

Writes one GLB per piece into assets/kenney3d/monorail-kit/Models/GLB format/, the folder convention
every Kenney kit already uses, so tools/testfit/testfit.py and tools/assets/merge_stages.py discover
the kit with no registration step. assets/ is gitignored, so this script is the committed artifact
and the GLBs regenerate from it. Same pattern as highway_kit.py, metro_kit.py, orbital_kit.py.

Why a custom kit at all: space-kit does ship `monorail_track*` and `monorail_train*`, but its track
is on its own 1-unit grid (4 studs at the era's scale 4, 3.6 at 3.6), so it can never land on the
7-stud tile pitch the client's Highway module places one prop per cell on (INTERFACES "Wave 2b --
Monorail"), and its train is sized for that track. Everything here is authored to that pitch.

Art rules, matching the space-kit buildings: flat shading only, axis-aligned boxes, swept prisms
and a lofted faceted capsule; plain colour factors with no texture, which merge_stages.py routes
through palette.py into one swatch. The colours are space-kit's own factors read as sRGB bytes
(orbital_kit.py explains why raw x 255 is the right reading), converted to linear on the way into
Blender because this kit, like orbital-kit, is *not* in palette.SRGB_FACTOR_KITS.

**Units: 1 gltf unit = 1 stud** (as highway-kit), so every literal below is directly checkable
against the contract (7-stud cells, wheel plane 7.07, soffit >= 6) and the blueprints use
`"scale": 1.0`.

Geometry is authored in gltf space -- Y up, +X right, -Z front. Track pieces have their origin at
the bottom centre of the 7-stud cell at ground level; the train's origin is bottom centre at its
own wheel plane, so the client places it at y = deckHeight with no offset. Blender is Z up, so every
vertex converts with (x, y, z) -> (x, -z, y), a proper rotation, so winding carries over. Faces are
not hand-wound: `Part.face` takes an outward hint and orders the loop so its normal agrees, because
Roblox MeshParts are single-sided and one flipped quad is a hole.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KIT = "monorail-kit"
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")

# space-kit material factors as sRGB bytes (see orbital_kit.py for the provenance of each).
COLOURS = {
    "hull": (215, 222, 232),  # "metal": the white hull every Orbital building wears
    "panel": (172, 181, 197),  # "metalDark"
    "trim": (255, 160, 52),  # "metalRed": the orange accent band
    "slate": (70, 76, 87),  # "dark"
    "lit": (255, 225, 140),  # orbital-kit lit window: the headlamps
    "warn": (232, 120, 74),  # orbital-kit warning red: the tail lamps
}

# --- the track, in studs ---------------------------------------------------------------------
CELL = 7.0  # INTERFACES: tile pitch, one prop per cell
HALF = CELL / 2.0
WHEEL = 7.07  # CityDressing highway.deckHeight: the beam top the train rides on
SOFFIT = 6.10  # beam underside, the same walkable clearance as the Metropolis highway (floor 6.0)
BEAM_HALF = 0.80  # 1.6-wide running beam: narrower than the 2.2 train, so the car visibly sits on it
KEEL_HALF = 0.58  # the lower 0.45 of the beam steps in, which is what makes it read as a girder and
KEEL_TOP = 6.55  # not a plank: the ledge throws a shadow line along every run
STRIPE = (6.74, 6.86)  # orange accent band along both beam faces
STRIPE_PROUD = 0.01  # stands proud of the face instead of splitting the sweep into bands
RAIL_HALF = 0.14  # dark guide rail down the beam top, the only thing that says "track" from above
MARK_LIFT = 0.01
JOINT_T = 0.16  # dark joint across the beam at the -X end of every cell: segments a long run

# Corner: the beam centreline is a quarter circle of radius HALF about the cell's (-X, +Z) corner,
# so it leaves the -X edge and the +Z edge exactly on a straight's centreline.
CORNER_CENTRE = (-HALF, HALF)
CORNER_STEPS = 8

# Pier: one slender column. The cap is long across the beam and short along it.
PIER_FOOT_HALF = 0.95
PIER_FOOT_H = 0.30
PIER_BASE_HALF = 0.46  # shaft half-width at the foot
PIER_NECK_HALF = 0.32  # and under the cap
PIER_CAP_Y = 5.45
PIER_CAP_HALF_X = 0.60
PIER_CAP_HALF_Z = 0.92  # wider than the 1.16 keel: at 0.72 the saddle read as a stub, not a support
PIER_COLLAR = (5.20, 5.45)  # orange collar ring under the saddle, echoing the beam stripe

# --- the train, in studs -----------------------------------------------------------------------
CAR_LEN = 3.75
GAP = 0.30  # two cars: 2 * 3.75 + 0.30 = 7.80 long (contract <= 8)
BODY_BASE = 0.34  # the body's underside; the bogie skirts fill 0 .. BODY_BASE
# Cross-section, one side (x >= 0), bottom to roof: (x, y, colour of the edge *above* this point).
SECTION_HALF = [
    (0.80, BODY_BASE, "hull"),
    (1.10, 0.62, "trim"),
    (1.10, 0.78, "hull"),
    (1.10, 1.12, "slate"),  # window band
    (1.02, 1.62, "hull"),
    (0.72, 1.98, "hull"),  # a darker roof sank into the plot base from the tycoon camera
    (0.00, 2.08, None),
]
# Loft stations along a car from its outer (cab) end: (distance from the end, width scale,
# height scale). Height scales about BODY_BASE, so the nose tucks down and in like a capsule.
CAB_STATIONS = [(0.0, 0.46, 0.58), (0.22, 0.74, 0.80), (0.62, 0.93, 0.95), (1.05, 1.0, 1.0)]
INNER_STATIONS = [(0.0, 0.90, 0.94), (0.14, 1.0, 1.0)]  # the coupled end: only a soft chamfer


def log(msg: str) -> None:
    print(f"[monorail-kit] {msg}", flush=True)


def srgb_to_linear(byte: int) -> float:
    s = byte / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


# --- mesh building (gltf space) ---------------------------------------------------------------


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


class Part:
    """Accumulates flat-shaded polygons tagged with a colour name."""

    def __init__(self, name: str):
        self.name = name
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[list[int], str]] = []

    def face(self, points, colour: str, outward) -> None:
        """Planar convex polygon, reordered so its normal points along `outward`."""
        n = (0.0, 0.0, 0.0)
        for i in range(1, len(points) - 1):
            c = _cross(_sub(points[i], points[0]), _sub(points[i + 1], points[0]))
            n = (n[0] + c[0], n[1] + c[1], n[2] + c[2])
        if _dot(n, outward) < 0:
            points = list(reversed(points))
        base = len(self.verts)
        self.verts.extend(points)
        self.faces.append(([base + i for i in range(len(points))], colour))

    def box(self, x0, x1, y0, y1, z0, z1, colour, **sides) -> None:
        """Axis-aligned box; `sides` overrides a face colour, None drops a buried face."""
        c = {k: sides.get(k, colour) for k in ("top", "bottom", "front", "back", "left", "right")}
        quads = (
            ("back", [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
            ("front", [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], (0, 0, -1)),
            ("right", [(x1, y0, z0), (x1, y0, z1), (x1, y1, z1), (x1, y1, z0)], (1, 0, 0)),
            ("left", [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], (-1, 0, 0)),
            ("top", [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
            ("bottom", [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
        )
        for key, pts, out in quads:
            if c[key] is not None:
                self.face(pts, c[key], out)

    def frustum(self, y0, y1, h0, h1, colour, cx=0.0, cz=0.0, hz0=None, hz1=None, **sides):
        """Vertical box tapering from half-extents (h0, hz0) at y0 to (h1, hz1) at y1."""
        hz0 = h0 if hz0 is None else hz0
        hz1 = h1 if hz1 is None else hz1
        a = [(cx - h0, y0, cz - hz0), (cx + h0, y0, cz - hz0), (cx + h0, y0, cz + hz0), (cx - h0, y0, cz + hz0)]
        b = [(cx - h1, y1, cz - hz1), (cx + h1, y1, cz - hz1), (cx + h1, y1, cz + hz1), (cx - h1, y1, cz + hz1)]
        for i, out in enumerate(((0, 0, -1), (1, 0, 0), (0, 0, 1), (-1, 0, 0))):
            j = (i + 1) % 4
            self.face([a[i], a[j], b[j], b[i]], colour, out)
        if sides.get("top", colour) is not None:
            self.face(b, sides.get("top", colour), (0, 1, 0))
        if sides.get("bottom", colour) is not None:
            self.face(a, sides.get("bottom", colour), (0, -1, 0))

    def bounds(self):
        lo = tuple(min(v[i] for v in self.verts) for i in range(3))
        hi = tuple(max(v[i] for v in self.verts) for i in range(3))
        return lo, hi

    @property
    def tris(self) -> int:
        return sum(len(idx) - 2 for idx, _ in self.faces)


# --- the beam cross-section, swept along a centreline ------------------------------------------

# (lateral from, lateral to, y bottom, y top, {face: colour}); lateral is along the path's left normal.
BEAM_STRIPS = [
    (-BEAM_HALF, BEAM_HALF, KEEL_TOP, WHEEL, {"top": "panel", "side": "hull", "bottom": "panel"}),
    (-KEEL_HALF, KEEL_HALF, SOFFIT, KEEL_TOP, {"side": "panel", "bottom": "slate"}),
]


def centreline_straight():
    """Stations (x, z, normal x, normal z) for a straight cell along X."""
    return [(-HALF, 0.0, 0.0, 1.0), (HALF, 0.0, 0.0, 1.0)]


def centreline_corner():
    """Quarter circle from the -X edge to the +Z edge; the normal points away from the centre."""
    cx, cz = CORNER_CENTRE
    out = []
    for i in range(CORNER_STEPS + 1):
        a = (i / CORNER_STEPS) * math.pi / 2.0
        nx, nz = math.sin(a), -math.cos(a)
        out.append((cx + HALF * nx, cz + HALF * nz, nx, nz))
    return out


def sweep(part: Part, line, strips, caps: bool) -> None:
    for lat0, lat1, y0, y1, colours in strips:
        def at(st, lat, y):
            x, z, nx, nz = st
            return (x + nx * lat, y, z + nz * lat)

        for i in range(len(line) - 1):
            a, b = line[i], line[i + 1]
            mid_n = ((a[2] + b[2]) / 2.0, 0.0, (a[3] + b[3]) / 2.0)
            if "top" in colours:
                part.face([at(a, lat0, y1), at(b, lat0, y1), at(b, lat1, y1), at(a, lat1, y1)], colours["top"], (0, 1, 0))
            if "bottom" in colours:
                part.face([at(a, lat0, y0), at(b, lat0, y0), at(b, lat1, y0), at(a, lat1, y0)], colours["bottom"], (0, -1, 0))
            if "side" in colours:
                for lat, sign in ((lat1, 1.0), (lat0, -1.0)):
                    part.face(
                        [at(a, lat, y0), at(b, lat, y0), at(b, lat, y1), at(a, lat, y1)],
                        colours["side"],
                        (mid_n[0] * sign, 0.0, mid_n[2] * sign),
                    )
        if caps:
            for st, sign in ((line[0], -1.0), (line[-1], 1.0)):
                i0, i1 = (0, 1) if sign < 0 else (-2, -1)
                tx, tz = line[i1][0] - line[i0][0], line[i1][1] - line[i0][1]
                part.face(
                    [at(st, lat0, y0), at(st, lat1, y0), at(st, lat1, y1), at(st, lat0, y1)],
                    colours.get("side", "slate"),
                    (tx * sign, 0.0, tz * sign),
                )


def beam_details(part: Part, line) -> None:
    """Orange stripe on both faces, dark guide rail on top, joint at the -X end."""
    for i in range(len(line) - 1):
        a, b = line[i], line[i + 1]
        for sign in (1.0, -1.0):
            lat = sign * (BEAM_HALF + STRIPE_PROUD)
            pa = (a[0] + a[2] * lat, a[1] + a[3] * lat)
            pb = (b[0] + b[2] * lat, b[1] + b[3] * lat)
            out = (sign * (a[2] + b[2]) / 2.0, 0.0, sign * (a[3] + b[3]) / 2.0)
            part.face(
                [(pa[0], STRIPE[0], pa[1]), (pb[0], STRIPE[0], pb[1]), (pb[0], STRIPE[1], pb[1]), (pa[0], STRIPE[1], pa[1])],
                "trim",
                out,
            )
        y = WHEEL + MARK_LIFT
        part.face(
            [
                (a[0] - a[2] * RAIL_HALF, y, a[1] - a[3] * RAIL_HALF),
                (b[0] - b[2] * RAIL_HALF, y, b[1] - b[3] * RAIL_HALF),
                (b[0] + b[2] * RAIL_HALF, y, b[1] + b[3] * RAIL_HALF),
                (a[0] + a[2] * RAIL_HALF, y, a[1] + a[3] * RAIL_HALF),
            ],
            "slate",
            (0, 1, 0),
        )


def joint(part: Part) -> None:
    """Dark band across the beam top and both faces just inside the -X end of a straight."""
    x0, x1 = -HALF, -HALF + JOINT_T
    w, y = BEAM_HALF + STRIPE_PROUD + 0.005, WHEEL + MARK_LIFT + 0.005
    part.face([(x0, y, -w), (x1, y, -w), (x1, y, w), (x0, y, w)], "slate", (0, 1, 0))
    for z, out in ((w, (0, 0, 1)), (-w, (0, 0, -1))):
        part.face([(x0, KEEL_TOP, z), (x1, KEEL_TOP, z), (x1, WHEEL, z), (x0, WHEEL, z)], "slate", out)


# --- the pieces --------------------------------------------------------------------------------


def make_track_straight() -> Part:
    """One 7-stud cell of beam along X. Top (wheel plane) 7.07, soffit 6.10; no pier (see `pier`)."""
    p = Part("track-straight")
    line = centreline_straight()
    sweep(p, line, BEAM_STRIPS, caps=True)
    beam_details(p, line)
    joint(p)
    return p


def make_track_corner() -> Part:
    """Quarter turn joining -X <-> +Z on a 3.5 radius, the same profile as the straight."""
    p = Part("track-corner")
    line = centreline_corner()
    sweep(p, line, BEAM_STRIPS, caps=True)
    beam_details(p, line)
    return p


def make_pier() -> Part:
    """One slender column: foot plinth, tapered shaft, orange collar, saddle up to the soffit.

    The saddle is long across the beam (Z) and short along it (X), so a blueprint rotates the pier
    with the beam; in the corner it stands under the arc's midpoint at rotY -45.
    Under a straight it stands at x = +2.5, off the cell centre, so the ring cell on the plot's
    x = 0 entrance axis keeps its pier clear of the entrance airlock (MonorailTrack.json).
    """
    p = Part("pier")
    p.frustum(0.0, PIER_FOOT_H, PIER_FOOT_HALF, PIER_FOOT_HALF * 0.86, "panel", bottom=None)
    p.frustum(
        PIER_FOOT_H, PIER_COLLAR[0], PIER_BASE_HALF, PIER_NECK_HALF, "slate", top=None, bottom=None
    )
    p.frustum(
        PIER_COLLAR[0], PIER_COLLAR[1], PIER_NECK_HALF + 0.06, PIER_NECK_HALF + 0.06, "trim", bottom="trim"
    )
    p.frustum(
        PIER_CAP_Y, SOFFIT, PIER_NECK_HALF + 0.02, PIER_CAP_HALF_X, "hull",
        hz0=PIER_NECK_HALF + 0.02, hz1=PIER_CAP_HALF_Z, top=None, bottom=None,
    )
    return p


def car(p: Part, z_cab: float, direction: float) -> None:
    """One lofted capsule car. `z_cab` is its cab end, `direction` (+1/-1) points into the car."""
    stations = []
    for d, sw, sh in CAB_STATIONS:
        stations.append((z_cab + direction * d, sw, sh))
    z_inner = z_cab + direction * CAR_LEN
    for d, sw, sh in reversed(INNER_STATIONS):
        stations.append((z_inner - direction * d, sw, sh))

    ring_pts = [(x, y) for x, y, _ in SECTION_HALF] + [(-x, y) for x, y, _ in reversed(SECTION_HALF[:-1])]
    edge_colours = [c for _, _, c in SECTION_HALF[:-1]] + [c for _, _, c in reversed(SECTION_HALF[:-1])]
    # The closing edge from (-0.80, base) back to (0.80, base) is the underside.
    edge_colours.append("slate")
    rc_y = (BODY_BASE + SECTION_HALF[-1][1]) / 2.0

    def ring(z, sw, sh):
        return [(x * sw, BODY_BASE + (y - BODY_BASE) * sh, z) for x, y in ring_pts]

    rings = [ring(*s) for s in stations]
    n = len(ring_pts)
    for i in range(len(rings) - 1):
        ra, rb = rings[i], rings[i + 1]
        for k in range(n):
            k1 = (k + 1) % n
            quad = [ra[k], ra[k1], rb[k1], rb[k]]
            mx = sum(q[0] for q in quad) / 4.0
            my = sum(q[1] for q in quad) / 4.0
            p.face(quad, edge_colours[k], (mx, my - rc_y, 0.0))
    # Cab face: windscreen (slate) -- the nose reads by its dark visor, as space-kit craft do.
    p.face(rings[0], "slate", (0.0, 0.0, -direction))
    p.face(rings[-1], "panel", (0.0, 0.0, direction))
    # Bogie skirts: the dark shoes that sit on the beam, one near each end.
    for d in (0.75, CAR_LEN - 0.95):
        zc = z_cab + direction * d
        p.box(-0.86, 0.86, 0.0, BODY_BASE + 0.02, zc - 0.45, zc + 0.45, "slate", top=None)


def make_train() -> Part:
    """Two-car capsule, nose toward -Z, origin bottom centre at the wheel plane. 7.80 long."""
    p = Part("train")
    total = 2 * CAR_LEN + GAP
    front, back = -total / 2.0, total / 2.0
    car(p, front, 1.0)
    car(p, back, -1.0)
    # Gangway bellows between the cars.
    p.box(-0.72, 0.72, 0.50, 1.78, -GAP / 2.0 - 0.1, GAP / 2.0 + 0.1, "slate", front=None, back=None)
    # Lamps sit on the cab faces: two headlamps at the -Z nose, two tail lamps at +Z.
    nose_sh = CAB_STATIONS[0][2]
    ly = BODY_BASE + (0.70 - BODY_BASE) * nose_sh
    lx = 0.34
    for z, colour, out in ((front, "lit", -1.0), (back, "warn", 1.0)):
        for sx in (-lx, lx):
            z0, z1 = (z - 0.05, z + 0.06) if out < 0 else (z - 0.06, z + 0.05)
            p.box(sx - 0.14, sx + 0.14, ly - 0.08, ly + 0.08, z0, z1, colour)
    return p


PIECES = {
    "track-straight": make_track_straight,
    "track-corner": make_track_corner,
    "pier": make_pier,
    "train": make_train,
}
TRI_BUDGET = {"track-straight": 400, "track-corner": 400, "pier": 400, "train": 1500}


# --- Blender plumbing ---------------------------------------------------------------------------


def material_for(name: str, cache: dict):
    if name in cache:
        return cache[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled")
    r, g, b = COLOURS[name]
    bsdf.inputs["Base Color"].default_value = (srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b), 1.0)
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
    parser = argparse.ArgumentParser(description="Generate the monorail-kit GLBs.")
    parser.add_argument("--out", default=DEFAULT_OUT, help="target Models/GLB format directory")
    args = parser.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    total = 0
    for name, make in PIECES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        part = make()
        assert part.name == name, f"{name}: Part is named {part.name!r}"
        if part.tris > TRI_BUDGET[name]:
            log(f"WARNING {name}: {part.tris} tris exceeds the {TRI_BUDGET[name]} budget")
        export(build_object(part, {}), args.out)
        total += part.tris
        lo, hi = part.bounds()
        size = tuple(round(hi[i] - lo[i], 2) for i in range(3))
        log(
            f"{name}.glb: {part.tris} tris, {size[0]} x {size[1]} x {size[2]} studs, "
            f"x {lo[0]:.2f}..{hi[0]:.2f}, y {lo[1]:.2f}..{hi[1]:.2f}, z {lo[2]:.2f}..{hi[2]:.2f}"
        )
    log(f"{len(PIECES)} pieces, {total} tris total -> {os.path.relpath(args.out, REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sys.exit(main(argv))
