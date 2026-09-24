"""Blender side of the store icons: builds each candidate's subject from generated geometry and
renders it on a transparent film. Run by store_icons.py, never by hand:

    blender -b -P tools/marketing/store_scene.py -- --spec <specs.json> --out <dir> [--only id,id]

The spec file lists candidates; each has `elements` (typed shapes with loc/rot/scale) and a
`camera` (elevation, azimuth, lens). Backgrounds, labels and the circle fit are Pillow's job in
store_icons.py, so every render here is the subject alone with alpha.

No Kenney piece fits a glossy store icon (the only coins are low-poly platformer pickups), so all
geometry is generated: lathe profiles for coins, bags, bells and crowns, bevelled boxes for the
chest and the sign, and extruded Titan One text for the glyphs.
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Euler, Vector
from bpy_extras.object_utils import world_to_camera_view

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
FONT_PATH = os.path.join(REPO, "assets", "marketing", "fonts", "TitanOne-Regular.ttf")
RENDER_PX = 1024

# Linear RGB. Chosen saturated because Standard view keeps them as they are; the gold is lifted
# above real gold so it stays yellow on the dark backgrounds instead of going bronze.
PALETTE = {
    "gold": {"rgb": (1.0, 0.66, 0.06), "metal": 0.85, "rough": 0.25, "coat": 0.6},
    "goldPale": {"rgb": (1.0, 0.80, 0.30), "metal": 1.0, "rough": 0.18, "coat": 0.6},
    "green": {"rgb": (0.10, 0.75, 0.18), "metal": 0.0, "rough": 0.25, "coat": 1.0},
    "greenDark": {"rgb": (0.02, 0.28, 0.06), "metal": 0.0, "rough": 0.4, "coat": 0.5},
    "bill": {"rgb": (0.30, 0.72, 0.30), "metal": 0.0, "rough": 0.55, "coat": 0.2},
    "billBand": {"rgb": (0.95, 0.93, 0.85), "metal": 0.0, "rough": 0.5, "coat": 0.2},
    "white": {"rgb": (0.95, 0.95, 0.97), "metal": 0.0, "rough": 0.3, "coat": 0.8, "glow": 0.25},
    "ink": {"rgb": (0.03, 0.03, 0.05), "metal": 0.0, "rough": 0.4, "coat": 0.5},
    "red": {"rgb": (0.85, 0.05, 0.05), "metal": 0.0, "rough": 0.25, "coat": 1.0},
    "blue": {"rgb": (0.05, 0.30, 0.95), "metal": 0.0, "rough": 0.25, "coat": 1.0},
    "purple": {"rgb": (0.40, 0.08, 0.85), "metal": 0.0, "rough": 0.25, "coat": 1.0},
    "gemRed": {"rgb": (0.90, 0.02, 0.10), "metal": 0.0, "rough": 0.05, "coat": 1.0},
    "gemBlue": {"rgb": (0.02, 0.35, 1.0), "metal": 0.0, "rough": 0.05, "coat": 1.0},
    "gemGreen": {"rgb": (0.02, 0.85, 0.25), "metal": 0.0, "rough": 0.05, "coat": 1.0},
    "wood": {"rgb": (0.20, 0.06, 0.015), "metal": 0.0, "rough": 0.6, "coat": 0.3},
    "woodDark": {"rgb": (0.07, 0.02, 0.005), "metal": 0.0, "rough": 0.6, "coat": 0.2},
    "burlap": {"rgb": (0.62, 0.36, 0.13), "metal": 0.0, "rough": 0.7, "coat": 0.2},
    "rope": {"rgb": (0.30, 0.13, 0.04), "metal": 0.0, "rough": 0.7, "coat": 0.1},
    "moon": {"rgb": (1.0, 0.85, 0.35), "metal": 0.0, "rough": 0.35, "coat": 0.6, "glow": 0.35},
    "star": {"rgb": (1.0, 0.90, 0.40), "metal": 0.0, "rough": 0.3, "coat": 0.5, "glow": 1.2},
    "roof": {"rgb": (0.70, 0.08, 0.10), "metal": 0.0, "rough": 0.35, "coat": 0.8},
    "wall": {"rgb": (0.95, 0.80, 0.55), "metal": 0.0, "rough": 0.5, "coat": 0.3},
    "window": {"rgb": (0.04, 0.05, 0.16), "metal": 0.0, "rough": 0.1, "coat": 1.0},
    "zzz": {"rgb": (0.75, 0.85, 1.0), "metal": 0.0, "rough": 0.3, "coat": 0.8, "glow": 0.25},
}

_materials = {}
_font = None


def material(name):
    if name in _materials:
        return _materials[name]
    spec = PALETTE[name]
    mat = bpy.data.materials.new("store_" + name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*spec["rgb"], 1.0)
    bsdf.inputs["Metallic"].default_value = spec["metal"]
    bsdf.inputs["Roughness"].default_value = spec["rough"]
    bsdf.inputs["Coat Weight"].default_value = spec["coat"]
    bsdf.inputs["Coat Roughness"].default_value = 0.08
    if spec.get("glow"):
        bsdf.inputs["Emission Color"].default_value = (*spec["rgb"], 1.0)
        bsdf.inputs["Emission Strength"].default_value = spec["glow"]
    _materials[name] = mat
    return mat


def font():
    global _font
    if _font is None:
        _font = bpy.data.fonts.load(FONT_PATH)
    return _font


def link(obj, parent):
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def mesh_object(name, bm, mat, parent, smooth_angle=35.0):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    mesh.set_sharp_from_angle(angle=math.radians(smooth_angle))
    mesh.materials.append(material(mat))
    return link(bpy.data.objects.new(name, mesh), parent)


def group(parent, loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0):
    empty = bpy.data.objects.new("store_group", None)
    empty.location = loc
    empty.rotation_euler = Euler([math.radians(a) for a in rot])
    empty.scale = (scale, scale, scale)
    return link(empty, parent)


def lathe(name, profile, mat, parent, segments=48, smooth_angle=35.0):
    """Revolves (radius, z) points about Z. A zero radius collapses to a pole via remove_doubles."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            quad = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
            try:
                bm.faces.new(quad)
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return mesh_object(name, bm, mat, parent, smooth_angle)


def rounded_box(name, size, mat, parent, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.08):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=3, affect="EDGES", profile=0.5)
    obj = mesh_object(name, bm, mat, parent, smooth_angle=40)
    obj.location = loc
    obj.rotation_euler = Euler([math.radians(a) for a in rot])
    return obj


def sphere(name, radius, mat, parent, loc=(0, 0, 0), scale=(1, 1, 1), subdiv=3):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    obj = mesh_object(name, bm, mat, parent, smooth_angle=180 if subdiv > 1 else 1)
    obj.location = loc
    obj.scale = scale
    return obj


def text(parent, body, size, mat, loc=(0, 0, 0), rot=(90, 0, 0), extrude=0.12, outline=None, outline_width=0.06):
    """Extruded Titan One text, standing to face -Y by default. `outline` adds a fatter copy
    behind in a dark material: the sticker edge that keeps glyphs readable at 150 px."""
    holder = group(parent, loc, rot)

    def make(material_name, offset, z, depth):
        curve = bpy.data.curves.new("store_text", type="FONT")
        curve.body = body
        curve.font = font()
        curve.size = size
        curve.align_x = "CENTER"
        curve.align_y = "CENTER"
        curve.extrude = depth
        curve.bevel_depth = min(0.035 * size, depth * 0.6)
        curve.bevel_resolution = 3
        curve.offset = offset
        curve.materials.append(material(material_name))
        obj = link(bpy.data.objects.new("store_text", curve), holder)
        obj.location = (0, 0, z)
        return obj

    make(mat, 0.0, 0.0, extrude * size)
    if outline:
        make(outline, outline_width * size, -0.3 * extrude * size, extrude * size)
    return holder


# ---------------------------------------------------------------------------------------------
# Subjects. Every builder takes (parent, element-dict) and builds around its own origin, Z up,
# front facing -Y.


def coin_profile(r, t):
    h = t / 2
    return [
        (0.0, h - 0.035 * r),
        (0.74 * r, h - 0.035 * r),
        (0.80 * r, h),
        (0.95 * r, h),
        (r, h - 0.05 * r),
        (r, -h + 0.05 * r),
        (0.95 * r, -h),
        (0.80 * r, -h),
        (0.74 * r, -h + 0.035 * r),
        (0.0, -h + 0.035 * r),
    ]


def coin(parent, e):
    r = e.get("r", 1.0)
    t = e.get("t", 0.24) * r
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    lathe("store_coin", coin_profile(r, t), e.get("mat", "gold"), g, segments=40)
    if e.get("emboss", False):
        glyph = e.get("glyph", "$")
        text(g, glyph, 1.05 * r, e.get("mat", "gold"), loc=(0, 0, t / 2 - 0.04 * r), rot=(0, 0, 0), extrude=0.07)
        if e.get("both", False):
            text(g, glyph, 1.05 * r, e.get("mat", "gold"), loc=(0, 0, -t / 2 + 0.04 * r), rot=(180, 0, 0), extrude=0.07)
    return g


def stack(parent, e):
    rng = random.Random(e.get("seed", 1))
    r = e.get("r", 1.0)
    t = 0.24 * r
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    n = e.get("n", 6)
    jitter = e.get("jitter", 0.06) * r
    for i in range(n):
        top = i == n - 1
        coin(g, {
            "r": r,
            "loc": (rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter), t / 2 + i * t * 0.98),
            "rot": (rng.uniform(-2, 2), rng.uniform(-2, 2), rng.uniform(0, 360) if not top else e.get("topYaw", 0)),
            "emboss": top and e.get("emboss", True),
        })
    return g


def pile(parent, e):
    """A dome of coins lying on its surface, tilted with the slope, plus a skirt at the base so
    the silhouette ends in coins rather than a hard edge."""
    rng = random.Random(e.get("seed", 3))
    R = e.get("radius", 2.5)
    H = e.get("height", 1.4)
    r = e.get("r", 0.55)
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    area = math.pi * (R * R + H * H)
    count = e.get("count", int(area / (math.pi * r * r) * 2.6))
    emboss_share = e.get("embossShare", 0.2)
    for _ in range(count):
        d = R * math.sqrt(rng.random())
        a = rng.uniform(0, 2 * math.pi)
        z = H * (1 - (d / R) ** 2)
        slope = math.degrees(math.atan(2 * H * d / (R * R)))
        tilt = slope + rng.uniform(-18, 18)
        facing = rng.random() < 0.03
        # Euler XYZ applies the tilt about Y before the yaw, so each coin leans out along the slope.
        coin(g, {
            "r": r,
            "loc": (d * math.cos(a), d * math.sin(a), max(z, 0.0) + 0.08 * r),
            "rot": (0, 70 if facing else tilt, math.degrees(a) + rng.uniform(-30, 30)),
            "emboss": rng.random() < emboss_share,
        })
    for i in range(e.get("skirt", 10)):
        a = 2 * math.pi * i / e.get("skirt", 10) + rng.uniform(-0.2, 0.2)
        d = R * rng.uniform(0.95, 1.12)
        coin(g, {
            "r": r,
            "loc": (d * math.cos(a), d * math.sin(a), 0.12 * r),
            "rot": (rng.uniform(-8, 8), rng.uniform(-8, 8), rng.uniform(0, 360)),
            "emboss": rng.random() < 0.5,
        })
    return g


def bills(parent, e):
    rng = random.Random(e.get("seed", 5))
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    n = e.get("n", 5)
    w, d, t = 2.4, 1.15, 0.12
    for i in range(n):
        yaw = rng.uniform(-6, 6)
        rounded_box("store_bill", (w, d, t * 0.92), "bill", g, loc=(rng.uniform(-0.05, 0.05), 0, t / 2 + i * t), rot=(0, 0, yaw), bevel=0.02)
    rounded_box("store_band", (0.45, d + 0.04, n * t + 0.04), "billBand", g, loc=(0, 0, n * t / 2), bevel=0.02)
    text(g, "$", 0.75, "greenDark", loc=(-0.75, 0, n * t + 0.005), rot=(0, 0, 0), extrude=0.04)
    text(g, "$", 0.75, "greenDark", loc=(0.75, 0, n * t + 0.005), rot=(0, 0, 0), extrude=0.04)
    return g


def bag(parent, e):
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    # Sack silhouette: a squat belly, a pinched neck and a flared ruffle above the tie.
    profile = [(0.0, 0.0), (0.9, 0.05), (1.35, 0.35), (1.55, 0.9), (1.5, 1.45), (1.2, 1.95), (0.72, 2.3),
               (0.42, 2.48), (0.40, 2.56), (0.62, 2.78), (0.85, 3.02), (0.7, 3.1), (0.35, 2.95), (0.0, 2.9)]
    lathe("store_bag", profile, e.get("mat", "burlap"), g, segments=56, smooth_angle=80)
    tie = lathe("store_tie", [(0.40, 2.44), (0.50, 2.47), (0.52, 2.55), (0.50, 2.62), (0.40, 2.64)], "rope", g, smooth_angle=80)
    tie.scale = (1.02, 1.02, 1)
    text(g, "$", 1.35, e.get("glyphMat", "gold"), loc=(0, -1.43, 1.15), rot=(83, 0, 0), extrude=0.14, outline="woodDark", outline_width=0.05)
    return g


def chest(parent, e):
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    W, D, H = 4.0, 2.6, 1.9
    rounded_box("store_chest", (W, D, H), "wood", g, loc=(0, 0, H / 2), bevel=0.1)
    for x in (-W / 2 + 0.35, W / 2 - 0.35):
        rounded_box("store_band", (0.34, D + 0.08, H + 0.06), "gold", g, loc=(x, 0, H / 2), bevel=0.05)
    rounded_box("store_rim", (W + 0.08, D + 0.08, 0.26), "gold", g, loc=(0, 0, H - 0.1), bevel=0.05)
    rounded_box("store_lock", (0.6, 0.2, 0.75), "gold", g, loc=(0, -D / 2 - 0.05, H - 0.45), bevel=0.06)
    rounded_box("store_hole", (0.14, 0.1, 0.26), "ink", g, loc=(0, -D / 2 - 0.15, H - 0.5), bevel=0.03)
    # Lid: a half barrel hinged at the back edge, thrown open past vertical so it frames the gold.
    hinge = group(g, (0, D / 2, H), (-112, 0, 0))
    lid = group(hinge, (0, -D / 2, 0), (0, 90, 0))
    bm = bmesh.new()
    seg = 24
    rows = []
    for x in (-W / 2, W / 2):
        ring = []
        for i in range(seg + 1):
            a = math.pi * i / seg
            ring.append(bm.verts.new((-(D / 2) * math.sin(a), (D / 2) * math.cos(a), x)))
        rows.append(ring)
    for i in range(seg):
        bm.faces.new([rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]])
    bm.faces.new(rows[0])
    bm.faces.new(list(reversed(rows[1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.12)
    mesh_object("store_lid", bm, "wood", lid, smooth_angle=40)
    for x in (-W / 2 + 0.35, W / 2 - 0.35):
        band = lathe("store_lidband", [(D / 2 + 0.02, -0.17), (D / 2 + 0.07, -0.15), (D / 2 + 0.07, 0.15), (D / 2 + 0.02, 0.17)], "gold", lid, segments=48)
        band.location = (0, 0, x)
    if e.get("full", True):
        pile(g, {"loc": (0, 0, H - 0.2), "radius": 1.75, "height": 1.3, "r": 0.5, "seed": 11, "skirt": 0,
                 "rot": (0, 0, 0), "scale": 1.0})
        g.children[-1].scale = (1.12, 0.72, 1.0)
    return g


def crown(parent, e):
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    R = 1.5
    lathe("store_crownband", [(R - 0.15, 0.0), (R + 0.05, 0.0), (R + 0.12, 0.12), (R + 0.12, 0.62), (R + 0.02, 0.75),
                              (R - 0.15, 0.75)], "gold", g, segments=64)
    lathe("store_crownbase", [(R - 0.2, 0.0), (R - 0.2, 0.1), (R - 0.05, 0.1), (R - 0.05, 0.0)], "gold", g, segments=64)
    spikes = e.get("spikes", 5)
    gems = ["gemRed", "gemBlue", "gemGreen", "gemBlue", "gemRed"]
    for i in range(spikes):
        a = -math.pi / 2 + 2 * math.pi * i / spikes
        x, y = R * math.cos(a), R * math.sin(a)
        spike = lathe("store_spike", [(0.62, 0.0), (0.52, 0.45), (0.2, 1.2), (0.0, 1.32)], "gold", g, segments=24)
        spike.location = (x, y, 0.55)
        spike.scale = (1.0, 0.4, 1.0)
        spike.rotation_euler = (0, 0, a + math.pi / 2)
        sphere("store_ball", 0.2, "goldPale", g, loc=(1.02 * x, 1.02 * y, 2.0))
        gem = sphere("store_gem", 0.3, gems[i % len(gems)], g, loc=(1.1 * math.cos(a) * (R + 0.05), 1.1 * math.sin(a) * (R + 0.05), 0.38),
                     scale=(1, 1, 1.25), subdiv=1)
        gem.rotation_euler = (0, 0, a)
    return g


def moon(parent, e):
    """Crescent as an extruded outline (outer arc minus an offset inner arc): a boolean-cut
    sphere reads as an egg from the front because the cut faces sideways."""
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    R, r, off = 1.5, 1.25, (0.75, 0.35)
    # Where the two circles cross, found numerically so the outline closes cleanly.
    crossings = []
    for i in range(3600):
        a = 2 * math.pi * i / 3600
        x, y = R * math.cos(a), R * math.sin(a)
        if abs(math.hypot(x - off[0], y - off[1]) - r) < 0.004:
            crossings.append(a)
    a_lo, a_hi = min(crossings), max(crossings)
    # The lit rim is the outer arc that lies outside the inner (cutting) circle.
    start, end = a_lo, a_hi
    mid = (start + end) / 2
    if math.hypot(R * math.cos(mid) - off[0], R * math.sin(mid) - off[1]) < r:
        start, end = a_hi, a_lo + 2 * math.pi
    outer = [(R * math.cos(t), R * math.sin(t)) for t in [start + (end - start) * k / 40 for k in range(41)]]
    b0 = math.atan2(outer[-1][1] - off[1], outer[-1][0] - off[0])
    b1 = math.atan2(outer[0][1] - off[1], outer[0][0] - off[0])
    if b1 < b0:
        b1 += 2 * math.pi
    # Of the two inner arcs between the crossings, the crescent's hollow is the one inside the disc.
    mid = (b0 + b1) / 2
    if math.hypot(off[0] + r * math.cos(mid), off[1] + r * math.sin(mid)) > R:
        b1 -= 2 * math.pi
    inner = [(off[0] + r * math.cos(t), off[1] + r * math.sin(t)) for t in
             [b0 + (b1 - b0) * k / 30 for k in range(1, 30)]]
    # A filled 2D curve handles the concave outline and bevels it evenly, which bmesh
    # triangulate + edge bevel did not.
    curve = bpy.data.curves.new("store_moon", type="CURVE")
    curve.dimensions = "2D"
    curve.fill_mode = "BOTH"
    curve.extrude = 0.22
    curve.bevel_depth = 0.14
    curve.bevel_resolution = 4
    spline = curve.splines.new("POLY")
    pts = outer + inner
    spline.points.add(len(pts) - 1)
    for point, (x, y) in zip(spline.points, pts):
        point.co = (x, y, 0.0, 1.0)
    spline.use_cyclic_u = True
    curve.materials.append(material("moon"))
    obj = link(bpy.data.objects.new("store_moon", curve), g)
    obj.rotation_euler = (math.pi / 2, 0, 0)
    obj.location = (0, 0.25, 0)
    return g


def clock(parent, e):
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    face = group(g, (0, 0, 0), (90, 0, 0))
    lathe("store_clockbody", [(0.0, -0.35), (1.3, -0.35), (1.45, -0.2), (1.5, 0.1), (1.45, 0.4), (1.35, 0.45), (1.2, 0.38),
                              (0.0, 0.38)], e.get("mat", "red"), face, segments=64)
    dial = lathe("store_dial", [(0.0, 0.0), (1.18, 0.0), (1.18, 0.03), (0.0, 0.03)], "white", face, segments=64)
    dial.location = (0, 0, 0.37)
    for i in range(12):
        a = 2 * math.pi * i / 12
        big = i % 3 == 0
        rounded_box("store_tick", (0.1 if big else 0.07, 0.24 if big else 0.14, 0.05), "ink", face,
                    loc=(0.95 * math.sin(a), 0.95 * math.cos(a), 0.42), rot=(0, 0, -math.degrees(a)), bevel=0.01)
    hour, minute = e.get("time", (10, 10))
    for length, width, ang in ((0.62, 0.14, (hour % 12 + minute / 60) / 12), (0.9, 0.1, minute / 60)):
        a = 2 * math.pi * ang
        rounded_box("store_hand", (width, length, 0.05), "ink", face,
                    loc=(0.5 * length * math.sin(a), 0.5 * length * math.cos(a), 0.47), rot=(0, 0, -math.degrees(a)), bevel=0.02)
    sphere("store_pin", 0.1, "gold", face, loc=(0, 0, 0.5))
    for side in (-1, 1):
        bell = group(g, (side * 0.95, 0.0, 1.35), (0, side * 35, 0))
        lathe("store_bell", [(0.0, 0.0), (0.62, 0.0), (0.6, 0.22), (0.45, 0.48), (0.2, 0.58), (0.0, 0.6)], "gold", bell, segments=40)
        leg = group(g, (side * 0.9, 0.0, -1.3), (0, side * 30, 0))
        lathe("store_leg", [(0.0, -0.35), (0.16, -0.35), (0.12, 0.2), (0.0, 0.2)], "gold", leg, segments=20)
    rounded_box("store_hammer", (0.12, 0.12, 0.5), "gold", g, loc=(0, 0, 1.65), bevel=0.03)
    sphere("store_knob", 0.14, "gold", g, loc=(0, 0, 1.92))
    return g


def house(parent, e):
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    rounded_box("store_walls", (2.6, 2.2, 1.9), "wall", g, loc=(0, 0, 0.95), bevel=0.08)
    bm = bmesh.new()
    verts = []
    for y in (-1.3, 1.3):
        verts.append([bm.verts.new((-1.65, y, 1.8)), bm.verts.new((1.65, y, 1.8)), bm.verts.new((0.0, y, 3.25))])
    bm.faces.new(verts[0])
    bm.faces.new(list(reversed(verts[1])))
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new([verts[0][i], verts[1][i], verts[1][j], verts[0][j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.06, segments=2, affect="EDGES", profile=0.5)
    mesh_object("store_roof", bm, "roof", g, smooth_angle=40)
    rounded_box("store_chimney", (0.4, 0.4, 0.9), "roof", g, loc=(0.8, 0.3, 2.9), bevel=0.04)
    rounded_box("store_door", (0.6, 0.1, 1.0), "woodDark", g, loc=(0, -1.12, 0.5), bevel=0.04)
    for x in (-0.8, 0.8):
        rounded_box("store_window", (0.55, 0.1, 0.55), "window", g, loc=(x, -1.12, 1.15), bevel=0.04)
    return g


def sign(parent, e):
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (0, 0, 0)), e.get("scale", 1.0))
    for x in (-1.5, 1.5):
        rounded_box("store_post", (0.28, 0.28, 3.2), "gold", g, loc=(x, 0.1, 1.6), bevel=0.06)
        sphere("store_postcap", 0.22, "goldPale", g, loc=(x, 0.1, 3.3))
    rounded_box("store_board", (3.8, 0.35, 1.7), e.get("board", "purple"), g, loc=(0, 0, 2.15), bevel=0.12)
    rounded_box("store_frame", (4.1, 0.28, 2.0), "gold", g, loc=(0, 0.08, 2.15), bevel=0.12)
    text(g, e.get("text", "VIP"), 1.3, "star", loc=(0, -0.2, 2.1), rot=(90, 0, 0), extrude=0.14, outline="ink", outline_width=0.04)
    return g


def star(parent, e):
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (90, 0, 0)), e.get("scale", 1.0))
    bm = bmesh.new()
    outer, inner, depth = 1.0, 0.45, 0.25
    top = []
    for i in range(10):
        a = math.pi / 2 + math.pi * i / 5
        rad = outer if i % 2 == 0 else inner
        top.append(bm.verts.new((rad * math.cos(a), rad * math.sin(a), 0.0)))
    c_front = bm.verts.new((0, 0, depth))
    c_back = bm.verts.new((0, 0, -depth))
    for i in range(10):
        j = (i + 1) % 10
        bm.faces.new([top[i], top[j], c_front])
        bm.faces.new([top[j], top[i], c_back])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh_object("store_star", bm, e.get("mat", "star"), g, smooth_angle=20)
    return g


def label(parent, e):
    return text(parent, e["text"], e.get("size", 1.5), e.get("mat", "green"), loc=e.get("loc", (0, 0, 0)),
                rot=e.get("rot", (90, 0, 0)), extrude=e.get("extrude", 0.22), outline=e.get("outline", "ink"),
                outline_width=e.get("outlineWidth", 0.06))


def arrow(parent, e):
    g = group(parent, e.get("loc", (0, 0, 0)), e.get("rot", (90, 0, 0)), e.get("scale", 1.0))
    bm = bmesh.new()
    outline = [(-0.35, -1.0), (0.35, -1.0), (0.35, 0.1), (0.8, 0.1), (0.0, 1.0), (-0.8, 0.1), (-0.35, 0.1)]
    face = bm.faces.new([bm.verts.new((x, y, 0.0)) for x, y in outline])
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, 0.35), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.05, segments=2, affect="EDGES", profile=0.5)
    mesh_object("store_arrow", bm, e.get("mat", "green"), g, smooth_angle=40)
    return g


BUILDERS = {
    "coin": coin, "stack": stack, "pile": pile, "bills": bills, "bag": bag, "chest": chest, "crown": crown,
    "moon": moon, "clock": clock, "house": house, "sign": sign, "star": star, "label": label, "arrow": arrow,
}


# ---------------------------------------------------------------------------------------------


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _materials.clear()
    global _font
    _font = None


def setup_scene(scene):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = scene.render.resolution_y = RENDER_PX
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.eevee.taa_render_samples = 64
    if hasattr(scene.eevee, "use_raytracing"):
        scene.eevee.use_raytracing = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    # The studio HDRI gives metals something to reflect; film is transparent so it never shows.
    world = bpy.data.worlds.new("store_world")
    world.use_nodes = True
    nodes = world.node_tree.nodes
    env = nodes.new("ShaderNodeTexEnvironment")
    hdri = os.path.join(os.path.dirname(bpy.app.binary_path), f"{bpy.app.version[0]}.{bpy.app.version[1]}",
                        "datafiles", "studiolights", "world", "studio.exr")
    if os.path.exists(hdri):
        env.image = bpy.data.images.load(hdri)
        world.node_tree.links.new(env.outputs["Color"], nodes["Background"].inputs["Color"])
    nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world

    def area(name, energy, size, loc, color=(1, 1, 1)):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        direction = -Vector(loc)
        obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(obj)

    # Key top-left front, cool fill right, strong rim from behind: the glossy edge light that
    # separates a gold subject from a gold-adjacent background.
    area("store_key", 1900, 6, (-7, -8, 10), (1.0, 0.96, 0.9))
    area("store_fill", 700, 8, (9, -6, 3), (0.85, 0.9, 1.0))
    area("store_rim", 2200, 5, (2, 9, 8), (1.0, 0.95, 0.85))


def bounds_points(root):
    pts = []
    for obj in root.children_recursive:
        if obj.type in ("MESH", "FONT") and not obj.hide_render:
            for corner in obj.bound_box:
                pts.append(obj.matrix_world @ Vector(corner))
    return pts


def setup_camera(scene, root, cam_spec):
    """Aims along the spec's elevation/azimuth and pulls back until the subject fills ~85 % of
    the frame; the final circle fit happens in Pillow, so this only buys resolution."""
    bpy.context.view_layer.update()
    pts = bounds_points(root)
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    centre = (lo + hi) / 2
    elev = math.radians(cam_spec.get("elev", 22))
    azim = math.radians(cam_spec.get("azim", 0))
    direction = Vector((math.sin(azim) * math.cos(elev), -math.cos(azim) * math.cos(elev), math.sin(elev)))
    data = bpy.data.cameras.new("store_cam")
    data.lens = cam_spec.get("lens", 50)
    cam = bpy.data.objects.new("store_cam", data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    fixed = cam_spec.get("fixed")
    if fixed:
        target = Vector(fixed["target"])
        cam.location = target + direction * fixed["dist"]
        cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        return
    dist = (hi - lo).length * 2.0
    for _ in range(6):
        cam.location = centre + direction * dist
        cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        bpy.context.view_layer.update()
        proj = [world_to_camera_view(scene, cam, p) for p in pts]
        xs = [p.x for p in proj]
        ys = [p.y for p in proj]
        extent = max(max(xs) - min(xs), max(ys) - min(ys))
        shift = Vector(((min(xs) + max(xs)) / 2 - 0.5, (min(ys) + max(ys)) / 2 - 0.5))
        data.shift_x += shift.x
        data.shift_y += shift.y
        dist *= extent / 0.85
    cam.location = centre + direction * dist


def render(candidate, out_dir):
    reset()
    scene = bpy.context.scene
    setup_scene(scene)
    root = bpy.data.objects.new("store_root", None)
    scene.collection.objects.link(root)
    for e in candidate["elements"]:
        BUILDERS[e["type"]](root, e)
    setup_camera(scene, root, candidate.get("camera", {}))
    scene.render.filepath = os.path.join(out_dir, f"store_raw_{candidate['id']}.png")
    bpy.ops.render.render(write_still=True)
    print(f"[store] rendered {candidate['id']}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    spec_path = argv[argv.index("--spec") + 1]
    out_dir = argv[argv.index("--out") + 1]
    only = set(argv[argv.index("--only") + 1].split(",")) if "--only" in argv else None
    with open(spec_path, encoding="utf-8") as f:
        candidates = json.load(f)
    for c in candidates:
        if only is None or c["id"] in only:
            render(c, out_dir)


main()
