"""Blender half of the thumbnail renderer (see tools/marketing/thumbs.py).

Runs inside Blender's Python. The scene arrives as a JSON of *groups*, each a list of boxes and
blueprint placements in plotrender's scene format (Y up, front -Z, studs) plus a group offset and
turn, so a whole plotrender plot can be dropped next to another one. Building the boxes and models
is plotscene's code, imported rather than copied, so a piece lands exactly where plotrender (and
therefore the game) puts it. Only the look is ours: a transparent film (thumbs.py paints the sky),
a hazy ground plane, warm sun and a camera that fits the content into a chosen part of the frame.

    blender -b -P tools/marketing/thumb_scene.py -- --scene <scene.json>
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "testfit"))

import plotscene  # noqa: E402
import testfit  # noqa: E402

FIT_PASSES = 30


def log(msg):
    print(f"[thumbs] {msg}", flush=True)


def linear(color):
    """0..255 sRGB -> linear, for lights and the ground: the Standard view transform re-encodes,
    so a colour written this way renders as the number in the scene file."""
    return tuple(plotscene.srgb_to_linear(c / 255.0) for c in color)


def build_groups(spec, plot, materials, cache):
    blueprints, missing = {}, {}
    for group in spec["groups"]:
        before = set(bpy.data.objects)
        for box in group.get("boxes", []):
            plotscene.build_box(box, plot, materials)
        for model in group.get("models", []):
            plotscene.build_model(model, cache, plot, blueprints, missing, materials)
        pivot = bpy.data.objects.new(f"Group_{group['name']}", None)
        plot.objects.link(pivot)
        pivot.location = plotscene.to_blender(group.get("offset", [0.0, 0.0, 0.0]))
        pivot.rotation_euler = (0.0, 0.0, math.radians(group.get("rotY", 0.0)))
        for obj in bpy.data.objects:
            if obj not in before and obj is not pivot and obj.parent is None:
                obj.parent = pivot
        pivot["thumb_group"] = group["name"]
    if missing:
        log("WARNING unusable blueprints: " + ", ".join(f"{k} x{v}" for k, v in sorted(missing.items())))


def build_ground(spec, plot):
    ground = spec.get("ground")
    if not ground:
        return
    size = ground.get("size", 4000.0)
    mesh = bpy.data.meshes.new("Ground")
    h = size / 2
    mesh.from_pydata([(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new("Ground", mesh)
    obj.location = (0.0, 0.0, ground.get("y", -1.0))
    plot.objects.link(obj)

    # Ground colour fades to the sky's horizon colour with distance from the lens, so the far edge
    # melts into the painted sky instead of cutting a hard line across the frame.
    mat = bpy.data.materials.new("GroundMat")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 1.0
    cam = nodes.new("ShaderNodeCameraData")
    ramp = nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = ground.get("hazeStart", 150.0)
    ramp.inputs["From Max"].default_value = ground.get("hazeEnd", 900.0)
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = (*linear(ground["color"]), 1.0)
    mix.inputs[7].default_value = (*linear(ground.get("haze", ground["color"])), 1.0)
    links.new(cam.outputs["View Distance"], ramp.inputs["Value"])
    links.new(ramp.outputs["Result"], mix.inputs["Factor"])
    # The haze is emitted rather than lit, so the far ground matches the sky whatever the sun does.
    emit_mix = nodes.new("ShaderNodeMixShader")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*linear(ground.get("haze", ground["color"])), 1.0)
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    links.new(ramp.outputs["Result"], emit_mix.inputs["Fac"])
    links.new(bsdf.outputs["BSDF"], emit_mix.inputs[1])
    links.new(emission.outputs["Emission"], emit_mix.inputs[2])
    links.new(emit_mix.outputs["Shader"], nodes.get("Material Output").inputs["Surface"])
    obj.data.materials.append(mat)


def direction_from(elevation, azimuth):
    """Unit vector in the scene frame (Y up) from elevation and azimuth in degrees; azimuth 0 is -Z
    (the plot's hub edge, where the tycoon camera stands) and +90 is +X."""
    e, a = math.radians(elevation), math.radians(azimuth)
    return Vector((math.cos(e) * math.sin(a), math.sin(e), -math.cos(e) * math.cos(a)))


def setup_lights(scene, light):
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = light.get("sun", 3.0)
    sun_data.color = linear(light.get("sunColor", [255, 244, 222]))
    sun_data.angle = math.radians(light.get("softness", 6.0))
    sun = bpy.data.objects.new("Sun", sun_data)
    toward_sun = plotscene.to_blender(direction_from(light.get("elevation", 45), light.get("azimuth", 30)))
    sun.rotation_euler = toward_sun.to_track_quat("Z", "Y").to_euler()
    scene.collection.objects.link(sun)

    fill_data = bpy.data.lights.new("Fill", "SUN")
    fill_data.energy = light.get("fill", 0.5)
    fill_data.color = linear(light.get("fillColor", [190, 210, 255]))
    fill = bpy.data.objects.new("Fill", fill_data)
    toward_fill = plotscene.to_blender(direction_from(35, light.get("azimuth", 30) + 170))
    fill.rotation_euler = toward_fill.to_track_quat("Z", "Y").to_euler()
    scene.collection.objects.link(fill)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (*linear(light.get("ambient", [200, 220, 245])), 1.0)
    background.inputs["Strength"].default_value = light.get("ambientStrength", 0.7)
    scene.world = world


def content_points(names):
    """Bounding-box corners of every visible mesh in the named groups (all groups when empty)."""
    points = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.name == "Ground" or not obj.users_collection:
            continue
        if obj.users_collection[0].name != "Plot":
            continue
        root = obj
        while root.parent is not None:
            root = root.parent
        if names and root.get("thumb_group") not in names:
            continue
        for corner in obj.bound_box:
            points.append(obj.matrix_world @ Vector(corner))
    return points


def setup_camera(scene, spec, size):
    cam_spec = spec["camera"]
    data = bpy.data.cameras.new("Camera")
    data.lens = cam_spec.get("lens", 40.0)
    data.sensor_fit = "HORIZONTAL"
    camera = bpy.data.objects.new("Camera", data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    data.clip_start = 0.5
    data.clip_end = 5000.0

    if "eye" in cam_spec:
        eye = plotscene.to_blender(cam_spec["eye"])
        target = plotscene.to_blender(cam_spec["target"])
        camera.location = eye
        camera.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    else:
        fit(camera, data, cam_spec, size)
    if cam_spec.get("dof"):
        dof = cam_spec["dof"]
        data.dof.use_dof = True
        data.dof.aperture_fstop = dof.get("fstop", 2.8)
        focus = plotscene.to_blender(dof["focus"])
        data.dof.focus_distance = (focus - camera.location).length


def fit(camera, data, cam_spec, size):
    """Frame the content from `dir` so its projection fills `window` (u0, u1, v0, v1 in -1..1 frame
    coordinates, v up). The window is how the bottom 15 % is kept for Roblox's tile overlay and the
    top band for a caption, without cropping the render afterwards."""
    direction = plotscene.to_blender(cam_spec["dir"]).normalized()
    rotation = (-direction).to_track_quat("-Z", "Y")
    right = rotation @ Vector((1, 0, 0))
    up = rotation @ Vector((0, 1, 0))
    camera.rotation_euler = rotation.to_euler()
    tan_x = 18.0 / data.lens
    tan_y = tan_x * size[1] / size[0]
    u0, u1, v0, v1 = cam_spec.get("window", (-0.9, 0.9, -0.62, 0.8))
    points = content_points(set(cam_spec.get("groups", [])))
    if not points:
        raise SystemExit("camera fit: nothing to frame")
    centre = sum(points, Vector()) / len(points)
    radius = max((p - centre).length for p in points)
    eye = centre + direction * radius * 3
    for _ in range(FIT_PASSES):
        us, vs = [], []
        for p in points:
            rel = p - eye
            ahead = -rel.dot(direction)
            ahead = max(ahead, 0.1)
            us.append(rel.dot(right) / (ahead * tan_x))
            vs.append(rel.dot(up) / (ahead * tan_y))
        span = max((max(us) - min(us)) / (u1 - u0), (max(vs) - min(vs)) / (v1 - v0))
        du = (min(us) + max(us)) / 2 - (u0 + u1) / 2
        dv = (min(vs) + max(vs)) / 2 - (v0 + v1) / 2
        depth = (centre - eye).dot(-direction)
        eye = eye + right * du * tan_x * depth + up * dv * tan_y * depth
        # Move along the view axis so the widest projected span matches the window.
        eye = eye + direction * depth * (span - 1.0) * 0.8
    camera.location = eye


def render(scene, spec):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    size = spec["size"]
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = spec["out"]
    eevee = scene.eevee
    eevee.taa_render_samples = spec.get("samples", 48)
    for attr, value in (("use_raytracing", True), ("use_shadows", True), ("shadow_ray_count", 2)):
        if hasattr(eevee, attr):
            setattr(eevee, attr, value)
    if hasattr(eevee, "fast_gi_distance"):
        eevee.fast_gi_distance = 6.0
    scene.view_settings.view_transform = "Standard"
    os.makedirs(os.path.dirname(spec["out"]), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="thumb_scene.py")
    parser.add_argument("--scene", required=True)
    args = parser.parse_args(argv)
    with open(args.scene, "r", encoding="utf-8") as handle:
        spec = json.load(handle)

    testfit.clear_scene()
    scene = bpy.context.scene
    library = bpy.data.collections.new("Library")
    plot = bpy.data.collections.new("Plot")
    for collection in (library, plot):
        scene.collection.children.link(collection)
    library.hide_render = True
    library.hide_viewport = True

    build_groups(spec, plot, plotscene.Materials(), plotscene.PlotPieceCache(library))
    bpy.context.view_layer.update()
    build_ground(spec, plot)
    setup_lights(scene, spec.get("light", {}))
    setup_camera(scene, spec, spec["size"])
    bpy.context.view_layer.update()
    render(scene, spec)
    log(f"wrote {spec['out']}")


if __name__ == "__main__":
    main()
