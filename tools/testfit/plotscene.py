"""Blender half of the plot renderer (see tools/testfit/plotrender.py).

Runs inside Blender's Python, which has no Pillow and cannot import tools/streetplan.py, so the
scene is handed over as a plain JSON file: boxes (plot base, pads, pavements, footpaths, roads on
a non-tile era) and models (a blueprint path, a stage, a plot-local position in studs and a
rotation about Y). Everything in that file is in the glTF/Roblox convention -- Y up, a model's
front faces -Z -- exactly like a blueprint, and is converted to Blender's Z-up here.

    blender -b -P tools/testfit/plotscene.py -- --scene <scene.json>
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# testfit owns the GLB lookup, the linked-duplicate piece cache and the flat-colour material, so a
# piece placed here lands exactly where the single-building render puts it.
import testfit  # noqa: E402
from blueprint import BlueprintError, load_blueprint  # noqa: E402

# Calibrated, not copied from testfit: sun + fill + a uniform sky add up to about pi of
# irradiance, so a Lambertian surface renders at roughly its own authored colour. testfit's
# brighter rig blew the Metropolis plot base (88, 90, 94) out to near-white, which is exactly the
# "white card" this render exists to avoid.
SUN_ENERGY = 2.3
FILL_ENERGY = 0.55

# tools/assets/palette.py SRGB_FACTOR_KITS, restated (Blender's Python cannot import it): kits whose
# authors wrote sRGB values straight into baseColorFactor. The game bakes those factors x 255 into
# the palette texture as sRGB; Blender's importer reads them as linear and would wash space-kit's
# orange out to pale amber and its dark slate to mid-grey, so they are decoded once here.
SRGB_FACTOR_KITS = frozenset({"space-kit"})


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


class PlotPieceCache(testfit.PieceCache):
    """testfit's cache, with each kit's colour-only materials made to render as the game shows
    them. merge_stages routes every colour-only material through palette.py into a flat texture,
    so in game it is neither metallic nor shiny: metallic goes to 0 (space-kit is authored
    metallic 1, which renders near-black under this sky). A material is fixed exactly once, the
    first time its kit piece is imported, so nothing is converted twice."""

    def __init__(self, library_collection):
        super().__init__(library_collection)
        self.fixed = set()

    def get(self, kit, model):
        fresh = (kit, model) not in self.templates
        roots = super().get(kit, model)
        if fresh and roots:
            for obj in testfit.all_descendants(roots):
                if obj.type != "MESH":
                    continue
                for slot in obj.material_slots:
                    self.fix(kit, slot.material)
        return roots

    def fix(self, kit, material):
        if material is None or material.name in self.fixed or not material.use_nodes:
            return
        self.fixed.add(material.name)
        bsdf = material.node_tree.nodes.get("Principled BSDF")
        if bsdf is None or bsdf.inputs["Base Color"].is_linked:
            return  # textured: the colormap is already sRGB and imported as such
        if kit in SRGB_FACTOR_KITS:
            colour = bsdf.inputs["Base Color"].default_value
            bsdf.inputs["Base Color"].default_value = (
                srgb_to_linear(colour[0]),
                srgb_to_linear(colour[1]),
                srgb_to_linear(colour[2]),
                colour[3],
            )
        if not bsdf.inputs["Metallic"].is_linked:
            bsdf.inputs["Metallic"].default_value = 0.0


def log(msg):
    print(f"[plotrender] {msg}", flush=True)


def to_blender(v):
    return Vector((v[0], -v[2], v[1]))


def rgb(color):
    """A 0..255 colour from the scene file as a Blender base colour.

    testfit renders with the Standard view transform and writes kit colours straight through, so
    the plain slabs are written the same way or they would read darker than the kit pieces beside
    them."""
    return tuple(c / 255.0 for c in color)


class Materials:
    def __init__(self):
        self.cache = {}

    def get(self, color, roughness=0.9):
        key = (tuple(color), roughness)
        material = self.cache.get(key)
        if material is None:
            material = testfit.flat_material(f"C{len(self.cache)}", rgb(color))
            bsdf = material.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Roughness"].default_value = roughness
            self.cache[key] = material
        return material


def build_box(spec, collection, materials):
    size = spec["size"]
    obj = testfit.make_box(
        spec.get("name", "Box"),
        (size[0], size[2], size[1]),  # glTF (x, y, z) -> Blender (x, z, y)
        to_blender(spec["pos"]),
        materials.get(spec["color"], spec.get("roughness", 0.9)),
        collection,
    )
    obj.rotation_euler = (0.0, 0.0, math.radians(spec.get("rotY", 0.0)))
    return obj


def build_placeholder(spec, collection, materials):
    """The boxes plotrender asked for in place of a model it could not draw, in the model's own
    frame (offset = a box's bottom-centre), turned with it and unscaled -- they are in studs."""
    root = bpy.data.objects.new(spec.get("name", "Placeholder"), None)
    root.location = to_blender(spec["pos"])
    root.rotation_euler = (0.0, 0.0, math.radians(spec.get("rotY", 0.0)))
    collection.objects.link(root)
    for index, box in enumerate(spec["placeholder"]):
        size, offset = box["size"], box["offset"]
        obj = testfit.make_box(
            f"{root.name}_ph{index}",
            (size[0], size[2], size[1]),
            to_blender((offset[0], offset[1] + size[1] / 2, offset[2])),
            materials.get(box["color"], 0.6),
            collection,
        )
        obj.parent = root


def build_model(spec, cache, collection, blueprints, missing, materials):
    path = spec["blueprint"]
    if path is None:
        build_placeholder(spec, collection, materials)
        return 0
    entry = blueprints.get(path, False)
    if entry is False:
        try:
            entry = load_blueprint(path)
        except (BlueprintError, OSError) as exc:
            log(f"WARNING: blueprint {os.path.basename(path)} unusable: {exc}")
            entry = None
        blueprints[path] = entry
    if entry is None:
        missing[os.path.basename(path)] = missing.get(os.path.basename(path), 0) + 1
        if spec.get("placeholder"):
            build_placeholder(spec, collection, materials)
        return 0
    stage = spec.get("stage")
    if stage is None:
        stage = entry.max_stage
    root = bpy.data.objects.new(spec.get("name", entry.id), None)
    root.location = to_blender(spec["pos"])
    root.rotation_euler = (0.0, 0.0, math.radians(spec.get("rotY", 0.0)))
    # The blueprint's own scale turns kit units into studs; every other number here is studs.
    root.scale = (entry.scale * float(spec.get("scale", 1.0)),) * 3
    collection.objects.link(root)
    placed = 0
    for piece in entry.pieces:
        if piece.stage > stage:
            continue
        roots = cache.get(piece.kit, piece.model)
        if roots is None:
            continue
        holder = bpy.data.objects.new(f"{entry.id}_{piece.index:02d}", None)
        holder.parent = root
        holder.location = to_blender(piece.pos)
        holder.rotation_euler = (0.0, 0.0, math.radians(piece.rot_y))
        collection.objects.link(holder)
        cache.instantiate(roots, holder, collection)
        placed += 1
    if placed == 0:
        # A blueprint whose kit GLBs are not generated yet: stand the placeholder in for it.
        name = os.path.basename(path)
        missing[name + " (no GLBs)"] = missing.get(name + " (no GLBs)", 0) + 1
        if spec.get("placeholder"):
            build_placeholder(spec, collection, materials)
    return placed


def setup_lights(scene, sky):
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = SUN_ENERGY
    sun_data.angle = math.radians(3)
    sun = bpy.data.objects.new("Sun", sun_data)
    # Down from the camera's own quadrant, so facades toward the viewer stay lit and the shadows
    # fall away from the lens instead of across the fronts being judged.
    sun.rotation_euler = (math.radians(52), math.radians(8), math.radians(-40))
    scene.collection.objects.link(sun)

    fill_data = bpy.data.lights.new("Fill", "SUN")
    fill_data.energy = FILL_ENERGY
    fill = bpy.data.objects.new("Fill", fill_data)
    fill.rotation_euler = (math.radians(62), 0.0, math.radians(150))
    scene.collection.objects.link(fill)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background:
        background.inputs["Color"].default_value = (*rgb(sky), 1.0)
        background.inputs["Strength"].default_value = 0.6
    scene.world = world


def setup_camera(scene, camera_spec):
    data = bpy.data.cameras.new("Camera")
    data.lens = camera_spec.get("lens", 40.0)
    data.sensor_fit = "HORIZONTAL"
    camera = bpy.data.objects.new("Camera", data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    eye = to_blender(camera_spec["eye"])
    target = to_blender(camera_spec["target"])
    camera.location = eye
    camera.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    data.clip_start = 0.1
    data.clip_end = max(600.0, (target - eye).length * 6)


def render(scene, out_path, size):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = out_path
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 24
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="plotscene.py")
    parser.add_argument("--scene", required=True)
    args = parser.parse_args(argv)

    with open(args.scene, "r", encoding="utf-8") as handle:
        scene_spec = json.load(handle)

    testfit.clear_scene()
    scene = bpy.context.scene
    library = bpy.data.collections.new("Library")
    plot = bpy.data.collections.new("Plot")
    for collection in (library, plot):
        scene.collection.children.link(collection)
    library.hide_render = True
    library.hide_viewport = True

    materials = Materials()
    for box in scene_spec.get("boxes", []):
        build_box(box, plot, materials)

    cache = PlotPieceCache(library)
    blueprints = {}
    missing = {}
    pieces = 0
    for model in scene_spec.get("models", []):
        pieces += build_model(model, cache, plot, blueprints, missing, materials)

    setup_lights(scene, scene_spec.get("sky", [200, 214, 232]))
    setup_camera(scene, scene_spec["camera"])
    bpy.context.view_layer.update()

    log(
        f"{len(scene_spec.get('boxes', []))} boxes, {len(scene_spec.get('models', []))} models, "
        f"{pieces} kit pieces"
    )
    if missing:
        listed = ", ".join(f"{name} x{count}" for name, count in sorted(missing.items()))
        log(f"WARNING: {len(missing)} blueprint(s) unusable, placeholder where one was given: {listed}")
    render(scene, scene_spec["out"], scene_spec.get("size", [1600, 1000]))
    log(f"wrote {scene_spec['out']}")


if __name__ == "__main__":
    main()
