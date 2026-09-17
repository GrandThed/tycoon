"""Blender preview of the Studio path test display: five grass bases (A, B, C, C2, C3) with the
baked lane and spur and the Stables building, from player-like cameras with mipmapped textures.

  "/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/pathtest/render.py --
      [--views junction,near,mid,far,overview,shift]

Reads out/patch.json (round 1: A, B, C), out/planar.json (round 2: C2, C3) and out/tex/*.png;
writes out/renders/<view>_<variant>.png (1280 x 720). Compose with `py tools/pathtest/sheet.py`.

The `junction` view is the one that matters for round 2: it looks straight at the spur mouth, where
Ben could still see the overlap in round 1. The `shift` view renders C2 with its spur deliberately
raised and lowered, to show that with planar UVs and an opaque texture the join is invisible either
way - the two surfaces resolve to the same texel whatever the draw order.

Roblox axes (Y up, studs) map to Blender as (x, -z, y), the glTF importer's convention, so the
building GLB and the path meshes line up exactly as the MeshParts will in Studio. The world is lit
roughly like a default Roblox place and the bases are flat Plastic colour, not noisy grass, which
flattered the earlier mock.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "out")
TEX = os.path.join(OUT, "tex")
STAGES = os.path.join(REPO, "assets", "build", "stages", "Village")
GRASS = (106, 127, 63)
GROUND = (163, 162, 165)  # PlotService's Ground part keeps the default Part colour
BASE_SIZE = 50.0
BASE_GAP = 10.0
VARIANTS = ("A", "B", "C", "C2", "C3")
# Heights above the base top, mirroring gen_display.py: C2's two fills are one plane; C3 hides every
# rim under every fill.
Y_ROUND1_LANE = 0.04
Y_ROUND1_SPUR = 0.064
Y_C2 = 0.05
Y_C3_FILL = 0.07
Y_C3_RIM = 0.02
SHIFT = 0.04  # studs the C2 spur is raised / lowered in the `shift` view (0.05 - 0.04 keeps it
# above the base plane; lowering it further just buries it in the grass)
VIEWS = {
    "junction": {"dist": 11.0, "pitch": 30.0, "yaw": 25.0, "at_junction": True},
    "near": {"dist": 16.0, "pitch": 34.0, "yaw": 20.0, "target": (-2.0, 0.0, 0.0)},
    "mid": {"dist": 30.0, "pitch": 28.0, "yaw": 15.0, "target": (-2.0, 0.0, 0.0)},
    "far": {"dist": 45.0, "pitch": 24.0, "yaw": 10.0, "target": (0.0, 0.0, 0.0)},
}


def srgb(c):
    def one(x):
        x = x / 255.0
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4

    return (one(c[0]), one(c[1]), one(c[2]), 1.0)


def rb(x, y, z):
    return Vector((x, -z, y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.eevee.taa_render_samples = 32
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    try:
        bpy.context.preferences.system.anisotropic_filter = "FILTER_2"
    except (AttributeError, TypeError):
        pass
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.66, 0.82, 1.0)
    bg.inputs["Strength"].default_value = 0.7
    scene.world = world
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.4
    sun_data.angle = math.radians(3)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    scene.collection.objects.link(sun)
    return scene


def flat_material(name, rgb, roughness=0.75):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(rgb)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def box(name, centre, size, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=rb(*centre))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[2], size[1])
    obj.data.materials.append(mat)
    return obj


def image(path, non_color=False):
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def path_material(name, colour_png, alpha=True, normal_png=None, rough_png=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    except KeyError:
        pass
    col = nt.nodes.new("ShaderNodeTexImage")
    col.image = image(os.path.join(TEX, colour_png))
    col.interpolation = "Linear"
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(col.outputs["Alpha"], bsdf.inputs["Alpha"])
        try:
            mat.surface_render_method = "BLENDED"
        except (AttributeError, TypeError):
            mat.blend_method = "BLEND"
    if normal_png:
        nrm = nt.nodes.new("ShaderNodeTexImage")
        nrm.image = image(os.path.join(TEX, normal_png), non_color=True)
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if rough_png:
        rough = nt.nodes.new("ShaderNodeTexImage")
        rough.image = image(os.path.join(TEX, rough_png), non_color=True)
        nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    return mat


def add_mesh(name, m, offset, mat, y=0.0):
    ox, oz = offset
    verts = [rb(v[0] + ox, v[1] + y, v[2] + oz) for v in m["verts"]]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], [tuple(t) for t in m["tris"]])
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.use_smooth = True
        for li in poly.loop_indices:
            u, v = m["uvs"][mesh.loops[li].vertex_index]
            uv.data[li].uv = (u, 1.0 - v)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.visible_shadow = False
    return obj


def add_building(glb, position, rotation_deg):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    holder = bpy.data.objects.new("Building", None)
    bpy.context.scene.collection.objects.link(holder)
    for o in bpy.data.objects:
        if o not in before and o.parent is None and o is not holder:
            o.parent = holder
    holder.location = rb(*position)
    holder.rotation_euler = (0, 0, math.radians(rotation_deg))


def camera(scene, name, target, dist, pitch_deg, yaw_deg, fov_deg=70.0):
    data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, data)
    scene.collection.objects.link(cam)
    data.sensor_fit = "VERTICAL"
    data.angle_y = math.radians(fov_deg)
    data.clip_start = 0.3
    data.clip_end = 2000
    pitch, yaw = math.radians(pitch_deg), math.radians(yaw_deg)
    # Roblox offset: +Z toward the hub, yaw turns it toward +X
    off = (math.sin(yaw) * math.cos(pitch) * dist, math.sin(pitch) * dist, math.cos(yaw) * math.cos(pitch) * dist)
    t = rb(*target)
    cam.location = rb(target[0] + off[0], target[1] + off[1], target[2] + off[2])
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam


def render(scene, path, w=1280, h=720):
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"[pathtest] wrote {path}")


def base_x(variant):
    return (VARIANTS.index(variant) - (len(VARIANTS) - 1) / 2) * (BASE_SIZE + BASE_GAP)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--views", default="junction,near,mid,far,overview,shift")
    args = ap.parse_args(argv)
    views = args.views.split(",")
    patch = json.load(open(os.path.join(OUT, "patch.json"), encoding="utf-8"))
    planar = json.load(open(os.path.join(OUT, "planar.json"), encoding="utf-8"))
    cx, _, cz = patch["patchCentre"]
    jx, jz = planar["junction"][0] - cx, planar["junction"][1] - cz
    out = os.path.join(OUT, "renders")
    os.makedirs(out, exist_ok=True)

    scene = reset()
    box("Ground", (0, -1.5, 0), (900, 1, 900), flat_material("Ground", GROUND))
    grass = flat_material("Grass", GRASS)
    b = patch["building"]
    materials = {
        "A": path_material("PathA", "A_color.png"),
        "B": path_material("PathB", "B_color.png", normal_png="B_normal.png", rough_png="B_rough.png"),
        "C": path_material("PathC", "C_color.png"),
        "fill": path_material("PathFill", "P_fill.png", alpha=False),
        "rim": path_material("PathRim", "P_rim.png", alpha=False),
    }
    spur_objects = {}
    for variant in VARIANTS:
        bx = base_x(variant)
        box(f"Base{variant}", (bx, -0.5, 0), (BASE_SIZE, 1, BASE_SIZE), grass)
        if variant in ("A", "B", "C"):
            for name, y in (("Lane", Y_ROUND1_LANE), ("Spur", Y_ROUND1_SPUR)):
                # round 1 meshes already carry their Y; y here is only for the label
                add_mesh(f"{name}{variant}", patch["meshes"][name], (bx - cx, -cz), materials[variant])
        else:
            layers = (
                [("Rim_Lane", Y_C3_RIM, "rim"), ("Rim_Spur", Y_C3_RIM, "rim"), ("Fill_Lane", Y_C3_FILL, "fill"), ("Fill_Spur", Y_C3_FILL, "fill")]
                if variant == "C3"
                else [("Fill_Lane", Y_C2, "fill"), ("Fill_Spur", Y_C2, "fill")]
            )
            for name, y, kind in layers:
                obj = add_mesh(f"{name}{variant}", planar["meshes"][name], (bx - cx, -cz), materials[kind], y=y)
                if name == "Fill_Spur":
                    spur_objects[variant] = obj
        add_building(os.path.join(STAGES, f"{b['model']}_S4.glb"), (bx + b["position"][0] - cx, 0, b["position"][2] - cz), b["rotationY"])

    for view in views:
        if view == "overview":
            camera(scene, "Overview", (0, 0, -4), 190, 34, 0, fov_deg=70)
            render(scene, os.path.join(out, "overview.png"), 1900, 800)
            continue
        if view == "shift":
            obj = spur_objects.get("C2")
            if obj is None:
                continue
            for label, delta in (("up", SHIFT), ("down", -SHIFT)):
                obj.location.z = delta
                camera(scene, f"Shift{label}", (base_x("C2") + jx, 0, jz), 9.0, 26.0, 25.0)
                render(scene, os.path.join(out, f"shift_{label}_C2.png"))
            obj.location.z = 0.0
            continue
        spec = VIEWS[view]
        for variant in VARIANTS:
            bx = base_x(variant)
            target = (bx + jx, 0.0, jz) if spec.get("at_junction") else (bx + spec["target"][0], 0.0, spec["target"][2])
            camera(scene, f"{view}{variant}", target, spec["dist"], spec["pitch"], spec["yaw"])
            render(scene, os.path.join(out, f"{view}_{variant}.png"))


main()
