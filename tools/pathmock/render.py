"""Blender headless renderer for the Village path mock.

  blender -b -P tools/pathmock/render.py -- --mesh <mesh.json> --texture <village_path.png>
      --out assets/testfit/out/Village/paths [--views top,persp_front,persp_close,growth]
      [--blend dithered|blended]

Roblox plot-local coordinates (Y up, studs) map to Blender as (x, -z, y). Buildings are the merged
stage GLBs (1 glTF unit = 1 stud, origin bottom-centre, front -Z) placed at the slot position and
turned by rotationY about the vertical axis; stage 4 when present, else stage 0, else skipped.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
STAGES = os.path.join(REPO, "assets", "build", "stages", "Village")
ERA_CONFIG = os.path.join(REPO, "src", "shared", "Config", "Eras", "1_Village.json")
GRASS = (106, 127, 63)


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
    scene.eevee.taa_render_samples = 64
    try:
        scene.eevee.use_shadows = True
    except AttributeError:
        pass
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    return scene


def setup_world(scene):
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.62, 0.72, 0.86, 1.0)
    bg.inputs["Strength"].default_value = 0.85
    scene.world = world
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.6
    sun_data.angle = math.radians(9)
    sun_data.color = (1.0, 0.97, 0.9)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(38), math.radians(0), math.radians(-30))
    scene.collection.objects.link(sun)


def ground(scene):
    mat = bpy.data.materials.new("Grass")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 1.0
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    except KeyError:
        pass
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.06
    noise.inputs["Detail"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = srgb((98, 120, 58))
    ramp.color_ramp.elements[1].color = srgb((114, 134, 68))
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[1].position = 0.65
    coord = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])

    bpy.ops.mesh.primitive_plane_add(size=120, location=(0, 0, 0))
    plot = bpy.context.active_object
    plot.name = "Plot"
    plot.data.materials.append(mat)

    outer = bpy.data.materials.new("Outer")
    outer.use_nodes = True
    outer.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = srgb((150, 152, 140))
    outer.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1.0
    bpy.ops.mesh.primitive_plane_add(size=800, location=(0, 0, -0.5))
    bpy.context.active_object.data.materials.append(outer)


def path_material(texture, blend):
    mat = bpy.data.materials.new("Path")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.95
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.05
    except KeyError:
        pass
    img = nt.nodes.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(texture)
    img.interpolation = "Linear"
    nt.links.new(img.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(img.outputs["Alpha"], bsdf.inputs["Alpha"])
    try:
        mat.surface_render_method = "BLENDED" if blend == "blended" else "DITHERED"
    except (AttributeError, TypeError):
        mat.blend_method = "BLEND" if blend == "blended" else "HASHED"
    try:
        mat.use_transparency_overlap = False
    except AttributeError:
        pass
    return mat


def add_ribbon(m, mat):
    verts = [rb(*v) for v in m["verts"]]
    mesh = bpy.data.meshes.new(m["name"])
    mesh.from_pydata(verts, [], [tuple(t) for t in m["tris"]])
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            vi = mesh.loops[li].vertex_index
            u, v = m["uvs"][vi]
            uv.data[li].uv = (u, 1.0 - v)
    mesh.materials.append(mat)
    mesh.update()
    obj = bpy.data.objects.new(m["name"], mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.visible_shadow = False
    return obj


def add_buildings(slots):
    config = json.load(open(ERA_CONFIG, encoding="utf-8"))
    models = {s["id"]: s["modelName"] for s in config["slots"]}
    placed = 0
    for slot in slots:
        model = models.get(slot["id"])
        path = None
        for stage in (4, 0):
            p = os.path.join(STAGES, f"{model}_S{stage}.glb")
            if os.path.isfile(p):
                path = p
                break
        if path is None:
            continue
        before = set(bpy.data.objects)
        try:
            bpy.ops.import_scene.gltf(filepath=path)
        except Exception:  # a malformed GLB is skipped like a missing one
            continue
        new = [o for o in bpy.data.objects if o not in before]
        holder = bpy.data.objects.new(f"Slot_{slot['id']}", None)
        bpy.context.scene.collection.objects.link(holder)
        for o in new:
            if o.parent is None:
                o.parent = holder
        x, z = slot["position"]
        holder.location = rb(x, 0, z)
        holder.rotation_euler = (0, 0, math.radians(slot["rotation"]))
        placed += 1
    print(f"[pathmock] buildings placed: {placed}")


def camera(scene, name, target, yaw_deg, pitch_deg, dist, fov_deg=70, ortho=None):
    data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, data)
    scene.collection.objects.link(cam)
    t = rb(*target)
    if ortho:
        data.type = "ORTHO"
        data.ortho_scale = ortho
        cam.location = t + Vector((0, 0, 300))
        cam.rotation_euler = (0, 0, 0)
        data.clip_end = 1000
    else:
        data.sensor_fit = "VERTICAL"
        data.angle_y = math.radians(fov_deg)
        yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
        # yaw 0: camera stands on the plot's front (-Z Roblox = +Y Blender) looking back into the plot
        offset = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * dist
        cam.location = t + offset
        cam.rotation_euler = (-offset).to_track_quat("-Z", "Y").to_euler()
        data.clip_start = 0.5
        data.clip_end = 600
    scene.camera = cam
    return cam


def render(scene, path, w, h):
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.resolution_percentage = 100
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"[pathmock] wrote {path}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--mesh", required=True)
    ap.add_argument("--texture", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--views", default="top,persp_front,persp_close,growth")
    ap.add_argument("--blend", default="blended")
    ap.add_argument("--close", default="3,0,-8", help="Roblox x,y,z target of the close-up")
    ap.add_argument("--close-yaw", type=float, default=25)
    args = ap.parse_args(argv)
    views = args.views.split(",")
    data = json.load(open(args.mesh, encoding="utf-8"))
    args.out = os.path.abspath(args.out)
    os.makedirs(args.out, exist_ok=True)

    scene = reset()
    setup_world(scene)
    ground(scene)
    mat = path_material(os.path.abspath(args.texture), args.blend)
    ribbons = {m["name"]: add_ribbon(m, mat) for m in data["meshes"]}
    add_buildings(data["slots"])

    if "top" in views:
        camera(scene, "Top", (0, 0, 0), 0, 90, 0, ortho=122)
        render(scene, os.path.join(args.out, "top.png"), 1600, 1600)
    if "top_detail" in views:
        x, y, z = (float(v) for v in args.close.split(","))
        camera(scene, "TopDetail", (x, 0, z), 0, 90, 0, ortho=float(os.environ.get("PATHMOCK_ORTHO", "30")))
        render(scene, os.path.join(args.out, "top_detail.png"), 1200, 1200)
    if "persp_front" in views:
        camera(scene, "Front", (-4, 0, -6), -18, 42, 58)
        render(scene, os.path.join(args.out, "persp_front.png"), 1600, 900)
    if "persp_close" in views:
        x, y, z = (float(v) for v in args.close.split(","))
        camera(scene, "Close", (x, 0, z), args.close_yaw, 44, 17)
        render(scene, os.path.join(args.out, "persp_close.png"), 1600, 900)
    if "growth" in views and "growth" in data:
        g = data["growth"]
        full = ribbons.get(g["slot"])
        if full:
            full.hide_render = True
        verts = data["growth"]["frames"][-1]["verts"]
        cx = sum(v[0] for v in verts) / len(verts)
        cz = sum(v[2] for v in verts) / len(verts)
        camera(scene, "Grow", (cx, 0, cz), -20, 62, 16)
        previous = None
        for i, frame in enumerate(g["frames"]):
            if previous:
                previous.hide_render = True
            frame = dict(frame, name=f"grow_{i}")
            previous = add_ribbon(frame, mat)
            render(scene, os.path.join(args.out, f"growth_f{i + 1}.png"), 720, 720)


main()
