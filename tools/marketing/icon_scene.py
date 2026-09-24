"""Blender half of the experience-icon renderer (see tools/marketing/icon.py).

Renders one candidate's 3D layer -- blueprints at a stage, optional floating-island ground -- on a
transparent film. The sky, glow and vignette are painted by icon.py under the system `py`, because
Blender's Python has no Pillow and a painted sky is easier to art-direct than a world shader.

    blender -b -P tools/marketing/icon_scene.py -- --scene <scene.json>

Scene coordinates follow the blueprint convention (studs, Y up, a model's front faces -Z) and are
converted to Blender's Z-up here, exactly as tools/testfit/plotscene.py does.
"""

import argparse
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "testfit"))

# plotscene already turns a blueprint placement into kit pieces with the game's colour handling
# (space-kit sRGB factors decoded, colour-only materials non-metallic); reusing it keeps the icon
# faithful to what the game shows.
import plotscene  # noqa: E402
import testfit  # noqa: E402


def log(msg):
    print(f"[icon] {msg}", flush=True)


def to_blender(v):
    return Vector((v[0], -v[2], v[1]))


def authored(colour):
    """Ground colours are written as the sRGB value wanted on screen; plotscene's materials take
    linear values (its slabs are judged against the kit), so decode once or the grass renders pastel."""
    return [round(plotscene.srgb_to_linear(c / 255.0) * 255.0, 3) for c in colour]


def build_island(spec, collection, materials):
    """A low-poly floating rock with a grass cap: the cap is a flat prism so buildings sit on a
    level top, the rock is a jittered cone so the silhouette reads as hand-made rather than CAD."""
    rng = random.Random(spec.get("seed", 7))
    radius = spec["radius"]
    depth = spec.get("depth", radius * 0.9)
    top = to_blender(spec["pos"])
    sides = spec.get("sides", 11)
    cap = spec.get("cap", 1.2)

    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=cap, location=top - Vector((0, 0, cap / 2)))
    grass = bpy.context.active_object
    grass.data.materials.append(materials.get(authored(spec["top"]), 0.85))

    bpy.ops.mesh.primitive_cone_add(
        vertices=sides, radius1=radius * 0.97, radius2=radius * 0.18, depth=depth,
        location=top - Vector((0, 0, cap + depth / 2 - 0.01)),
    )
    rock = bpy.context.active_object
    for v in rock.data.vertices:
        if v.co.z < depth / 2 - 0.01:
            v.co.x += rng.uniform(-0.12, 0.12) * radius
            v.co.y += rng.uniform(-0.12, 0.12) * radius
            v.co.z += rng.uniform(-0.1, 0.1) * depth
    rock.data.materials.append(materials.get(authored(spec["side"]), 0.95))

    for obj in (grass, rock):
        obj.rotation_euler = (0.0, 0.0, math.radians(spec.get("rotY", 0.0)))
        # [x, z] stretch, so one island can carry a row of buildings.
        stretch = spec.get("stretch", [1.0, 1.0])
        obj.scale = (stretch[0], stretch[1], 1.0)
        for polygon in obj.data.polygons:
            polygon.use_smooth = False
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        collection.objects.link(obj)
    return [grass, rock]


def add_sun(scene, name, spec):
    data = bpy.data.lights.new(name, "SUN")
    data.energy = spec["energy"]
    data.angle = math.radians(spec.get("softness", 3))
    if "color" in spec:
        data.color = tuple(c / 255.0 for c in spec["color"])
    light = bpy.data.objects.new(name, data)
    # "from" is the direction the light arrives from, in scene (glTF) axes.
    light.rotation_euler = (-to_blender(spec["from"])).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(light)


def setup_world(scene, spec):
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (*(c / 255.0 for c in spec["ambient"]), 1.0)
    background.inputs["Strength"].default_value = spec.get("ambientStrength", 0.6)
    scene.world = world


def fit_camera(scene, spec, bounds, size):
    """Aim along a fixed direction and pull back until the bounds fill the frame, then nudge the
    aim point; icons are composed by direction and fill, not by hand-typed eye positions."""
    data = bpy.data.cameras.new("Camera")
    data.lens = spec.get("lens", 40.0)
    data.sensor_fit = "HORIZONTAL"
    camera = bpy.data.objects.new("Camera", data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    data.clip_start = 0.1

    if "eye" in spec:
        # A hero shot from street level is composed by eye, not by fit: the fit keeps every
        # corner in frame, and a low-angle hero wants the base cropped and the tower overhead.
        eye, target = to_blender(spec["eye"]), to_blender(spec["target"])
        camera.location = eye
        camera.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
        data.clip_end = 2000.0
        return

    lo, hi = bounds
    direction = to_blender(spec["dir"]).normalized()
    rotation = (-direction).to_track_quat("-Z", "Y")
    right = rotation @ Vector((1, 0, 0))
    up = rotation @ Vector((0, 1, 0))
    tan_x = math.tan(data.angle_x / 2)
    tan_y = tan_x * size[1] / size[0]
    center = (lo + hi) / 2
    # Recentre on the projected extents a few times: a perspective view of a tall model puts its
    # base far off the centre ray, and a centre-aimed camera wastes half the frame.
    for _ in range(4):
        distance = 1.0
        for corner in ((x, y, z) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)):
            rel = Vector(corner) - center
            depth = rel.dot(direction)
            distance = max(distance, depth + abs(rel.dot(right)) / tan_x, depth + abs(rel.dot(up)) / tan_y)
        distance *= spec.get("margin", 1.05)
        eye = center + direction * distance
        xs, ys = [], []
        for corner in ((x, y, z) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)):
            rel = Vector(corner) - eye
            forward = -rel.dot(direction)
            xs.append(rel.dot(right) / forward)
            ys.append(rel.dot(up) / forward)
        mid_x = (min(xs) + max(xs)) / 2
        mid_y = (min(ys) + max(ys)) / 2
        center = center + right * mid_x * distance + up * mid_y * distance
    offset = spec.get("offset", [0.0, 0.0])  # fraction of the half-frame, +x right, +y up
    eye = center + direction * distance
    camera.location = eye - right * offset[0] * tan_x * distance - up * offset[1] * tan_y * distance
    camera.rotation_euler = rotation.to_euler()
    data.clip_end = distance * 8


def render(scene, out_path, size, samples):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = out_path
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = samples
    # Standard keeps the kit's flat colours saturated; AgX would grey them, which an icon cannot afford.
    scene.view_settings.view_transform = "Standard"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="icon_scene.py")
    parser.add_argument("--scene", required=True)
    args = parser.parse_args(argv)
    with open(args.scene, "r", encoding="utf-8") as handle:
        spec = json.load(handle)

    testfit.clear_scene()
    scene = bpy.context.scene
    library = bpy.data.collections.new("Library")
    subject = bpy.data.collections.new("Subject")
    ground = bpy.data.collections.new("Ground")
    for collection in (library, subject, ground):
        scene.collection.children.link(collection)
    library.hide_render = True
    library.hide_viewport = True

    materials = plotscene.Materials()
    cache = plotscene.PlotPieceCache(library)
    blueprints, missing = {}, {}
    pieces = 0
    for model in spec.get("models", []):
        pieces += plotscene.build_model(model, cache, subject, blueprints, missing, materials)
    for island in spec.get("islands", []):
        build_island(island, ground, materials)
    for box in spec.get("boxes", []):
        plotscene.build_box(dict(box, color=authored(box["color"])), ground, materials)
    if missing:
        log(f"WARNING: unusable blueprints: {', '.join(sorted(missing))}")

    setup_world(scene, spec["world"])
    for index, light in enumerate(spec["lights"]):
        add_sun(scene, f"Sun{index}", light)
    bpy.context.view_layer.update()

    fit = [o for o in subject.objects if o.parent is None]
    if spec["camera"].get("fitGround"):
        fit += list(ground.objects)
    bounds = testfit.world_bounds(fit)
    lo, hi = bounds
    log(f"subject bounds studs x[{lo.x:.1f},{hi.x:.1f}] y[{-hi.y:.1f},{-lo.y:.1f}] height[{lo.z:.1f},{hi.z:.1f}], {pieces} pieces")
    size = spec.get("size", [1024, 1024])
    fit_camera(scene, spec["camera"], bounds, size)
    render(scene, spec["out"], size, spec.get("samples", 32))
    log(f"wrote {spec['out']}")


if __name__ == "__main__":
    main()
