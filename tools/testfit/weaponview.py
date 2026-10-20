"""testfit's weapon view (L3): how a weapon looks on the Armory screen, how big it is, and its icon.

Used by testfit.py for any blueprint under blueprints/_props/Weapons/ (or with `--weapon`):

    blender -b -P tools/testfit/testfit.py -- --blueprint tools/testfit/blueprints/_props/Weapons/Longbow.json

Renders three pictures with a transparent background, then hands them to weaponstrip.py (system
`py`, Pillow) which lays them on the Armory panel colour (30, 41, 70) with the L0 mock's lighter
radial behind:
  * side  -- orthographic from +X (the weapon's right side, the point toward screen-right), beside
    a 5-stud R15 silhouette whose hand height the grip sits at, with the frame points marked;
  * stage -- a perspective three-quarter from the front-right, framed like the Armory stage;
  * icon  -- a square orthographic shot with the weapon's long axis turned to the diagonal (point
    or upper limb to the upper right), kept with its alpha for the shelf.
Outputs land in assets/testfit/out/Weapons/: <id>_strip.png, <id>_icon.png (512 px RGBA) and
<id>_icon_check.png (the icon at shelf sizes on the dark card, the panel and as the unowned
silhouette). Raw renders go to _raw/.

Lighting copies a ViewportFrame's two terms, one directional light and an ambient: AMBIENT plus
SUN_GAIN x cos(angle) of the authored colour, so a face turned to the light renders near its
palette colour and the shaded side at about half. Roblox's own constants are unknown until Ben
looks in Studio (study report section 3); this rig is for judging the model, not the final light.

The weapon's frame points come from the `<model>.frame.json` the generator writes beside the GLB
(weapon_kit_mesh.py). A weapon blueprint must place its one piece at the origin, unturned, at scale
1.0, or those points no longer describe the merged model: the view warns when it does not.
"""

from __future__ import annotations

import json
import math
import os
import subprocess

import bmesh
import bpy
from mathutils import Quaternion, Vector

import testfit as tf  # the running testfit module (testfit.py registers itself before importing this)

SIDE_SIZE = (1024, 768)
STAGE_SIZE = (1024, 768)
ICON_SIZE = 512
STAGE_LENS = 50.0
# The flat (unlit) colours of the scale card, sRGB 0..255, chosen to sit behind the weapon on the panel.
SILHOUETTE_RGB = (70, 88, 136)
GROUND_RGB = (92, 112, 164)
MARKER_RGB = {"grip": (110, 232, 120), "tip": (255, 92, 80), "holster": (255, 212, 72), "nock": (90, 220, 255)}
MARKER_OTHER = (235, 235, 235)
R15_HAND_Y = 2.2  # where a relaxed R15's right hand is, in studs above its feet
AMBIENT = 0.5
SUN_GAIN = 0.62
# Camera directions in glTF space (+X right, +Y up, -Z front).
SIDE_DIR = (1.0, 0.0, 0.0)
STAGE_YAW, STAGE_PITCH = 35.0, 20.0  # degrees from the side toward the front, and up
ICON_YAW, ICON_PITCH = 22.0, 16.0


def emission_material(name, rgb):
    """An unlit flat colour: the silhouette, the ground line, the markers."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*(tf.srgb_to_linear(c / 255.0) for c in rgb), 1.0)
    em.inputs["Strength"].default_value = 1.0
    mat.node_tree.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return mat


def direction(yaw_deg: float, pitch_deg: float) -> Vector:
    """A glTF direction from the weapon's right side (+X), turned toward its front and up."""
    y, p = math.radians(yaw_deg), math.radians(pitch_deg)
    return Vector((math.cos(p) * math.cos(y), math.sin(p), -math.cos(p) * math.sin(y)))


def mesh_points(objs):
    pts = []
    for o in tf.all_descendants(objs):
        if o.type == "MESH" and not o.hide_render:
            mw = o.matrix_world
            pts.extend(mw @ v.co for v in o.data.vertices)
    return pts


def aim(cam, view_dir_blender: Vector, roll: float = 0.0):
    rot = (-view_dir_blender).to_track_quat("-Z", "Y")
    if roll:
        rot = rot @ Quaternion((0.0, 0.0, 1.0), roll)
    cam.rotation_euler = rot.to_euler()
    right = rot @ Vector((1.0, 0.0, 0.0))
    up = rot @ Vector((0.0, 1.0, 0.0))
    return rot, right, up


def fit_ortho(cam, pts, view_dir_blender: Vector, size, margin=1.1, roll=0.0):
    _, right, up = aim(cam, view_dir_blender, roll)
    xs = [p.dot(right) for p in pts]
    ys = [p.dot(up) for p in pts]
    ds = [p.dot(view_dir_blender) for p in pts]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    aspect = size[0] / size[1]
    cam.data.type = "ORTHO"
    # Blender's ortho_scale spans the render's larger side.
    cam.data.ortho_scale = (max(w, h * aspect) if aspect >= 1 else max(w / aspect, h)) * margin
    depth = max(ds) + 5.0
    cam.location = right * cx + up * cy + view_dir_blender * depth
    cam.data.clip_end = depth + (max(ds) - min(ds)) + 10.0


def fit_perspective(cam, pts, view_dir_blender: Vector, size, margin=1.12):
    _, right, up = aim(cam, view_dir_blender)
    cam.data.type = "PERSP"
    cam.data.lens = STAGE_LENS
    cam.data.sensor_fit = "HORIZONTAL"
    xs, ys, zs = [p.x for p in pts], [p.y for p in pts], [p.z for p in pts]
    centre = Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(zs) + min(zs)) / 2))
    tan_x = math.tan(cam.data.angle_x / 2)
    tan_y = tan_x / (size[0] / size[1])
    distance = 0.5
    for p in pts:
        rel = p - centre
        depth = rel.dot(view_dir_blender)
        distance = max(distance, depth + abs(rel.dot(right)) / tan_x, depth + abs(rel.dot(up)) / tan_y)
    distance *= margin
    cam.location = centre + view_dir_blender * distance
    cam.data.clip_start = 0.01
    cam.data.clip_end = distance * 4


def light_for(sun, view_dir_blender: Vector, right: Vector, up: Vector):
    """The key light from the camera's upper left: what a stage light would do."""
    toward_light = (view_dir_blender + up * 0.8 - right * 0.4).normalized()
    sun.rotation_euler = toward_light.to_track_quat("Z", "Y").to_euler()


def setup_render(scene, size, samples):
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
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = samples
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass


def r15_silhouette(collection, mat, centre_z: float):
    """A blocky R15 seen from the front (facing +X, the camera), 5 studs tall, as flat boxes."""
    gap = 0.04
    boxes = [
        ((1.0, 2.0, 1.0 - gap), (0.0, 1.0, centre_z - 0.5 - gap / 2)),  # legs
        ((1.0, 2.0, 1.0 - gap), (0.0, 1.0, centre_z + 0.5 + gap / 2)),
        ((1.0, 2.0, 2.0), (0.0, 3.0, centre_z)),  # lower + upper torso
        ((1.0, 1.95, 1.0 - gap), (0.0, 3.0 - 0.025, centre_z - 1.5 - gap)),  # arms
        ((1.0, 1.95, 1.0 - gap), (0.0, 3.0 - 0.025, centre_z + 1.5 + gap)),
        ((1.1, 0.95, 1.15), (0.0, 4.525, centre_z)),  # head
    ]
    objs = []
    for i, (size, centre) in enumerate(boxes):
        # Sizes and centres are glTF (x depth, y up, z width); make_box takes Blender axes.
        obj = tf.make_box(f"R15_{i}", (size[0], size[2], size[1]), tf.gltf_to_blender(centre), mat, collection)
        objs.append(obj)
    return objs


def read_frame(piece) -> dict | None:
    glb = tf.find_glb(piece.kit, piece.model)
    if glb is None:
        return None
    path = glb[: -len(".glb")] + ".frame.json"
    if not os.path.isfile(path):
        tf.warn(f"no frame file beside {os.path.basename(glb)}: regenerate the kit (weapon_kit_<level>.py)")
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def render_weapon(bp, out_dir: str) -> None:
    """Render one weapon blueprint (already loaded) to out_dir."""
    if bp.scale != 1.0 or len(bp.pieces) != 1 or any(abs(c) > 1e-6 for c in bp.pieces[0].pos) or bp.pieces[0].rot_y:
        tf.warn(f"{bp.id}: a weapon blueprint is one piece at the origin, unturned, scale 1.0; the frame points "
                f"below describe the GLB, not this placement")
    raw_dir = os.path.join(out_dir, "_raw")
    os.makedirs(raw_dir, exist_ok=True)
    tf.clear_scene()
    scene = bpy.context.scene
    library = bpy.data.collections.new("Library")
    weapon = bpy.data.collections.new("Weapon")
    card = bpy.data.collections.new("Card")
    for c in (library, weapon, card):
        scene.collection.children.link(c)
    library.hide_render = True
    library.hide_viewport = True

    cache = tf.PieceCache(library)
    holders = []
    for piece in bp.pieces:
        roots = cache.get(piece.kit, piece.model)
        if roots is None:
            continue
        holder = bpy.data.objects.new(f"p{piece.index:02d}_{piece.model}", None)
        holder.location = tf.gltf_to_blender(piece.pos)
        holder.rotation_euler = (0.0, 0.0, math.radians(piece.rot_y))
        holder.scale = (bp.scale,) * 3
        weapon.objects.link(holder)
        cache.instantiate(roots, holder, weapon)
        holders.append(holder)
    if not holders:
        tf.warn(f"{bp.id}: no piece could be loaded; nothing rendered")
        return
    frame_rec = read_frame(bp.pieces[0]) or {}
    frame = frame_rec.get("frame", {})
    bpy.context.view_layer.update()

    # The weapon's own bounds, in glTF studs.
    pts = mesh_points(holders)
    lo = Vector(map(min, *[tf.blender_to_gltf(p) for p in pts]))
    hi = Vector(map(max, *[tf.blender_to_gltf(p) for p in pts]))
    size = hi - lo
    tf.log(f"{bp.id}: {size.x:.2f} x {size.y:.2f} x {size.z:.2f} studs (x[{lo.x:.2f}, {hi.x:.2f}] "
           f"y[{lo.y:.2f}, {hi.y:.2f}] z[{lo.z:.2f}, {hi.z:.2f}])")

    # --- the scale card: the weapon lifted to hand height beside the silhouette, the points marked
    lift = max(R15_HAND_Y, 0.25 - lo.y)
    sil_mat = emission_material("Silhouette", SILHOUETTE_RGB)
    ground_mat = emission_material("GroundLine", GROUND_RGB)
    figure_z = hi.z + 0.7 + 2.0
    figure = r15_silhouette(card, sil_mat, figure_z)
    z0, z1 = min(lo.z, figure_z - 2.6), max(hi.z, figure_z + 2.6)
    ground_line = tf.make_box("GroundLine", (0.6, z1 - z0, 0.05), tf.gltf_to_blender((-0.5, -0.025, (z0 + z1) / 2)),
                              ground_mat, card)
    markers = []
    for name, p in frame.items():
        mat = emission_material(f"Marker_{name}", MARKER_RGB.get(name, MARKER_OTHER))
        mesh = bpy.data.meshes.new(f"Marker_{name}")
        obj = bpy.data.objects.new(f"Marker_{name}", mesh)
        card.objects.link(obj)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.055)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(mat)
        obj.location = tf.gltf_to_blender((hi.x + 0.2, p[1] + lift, p[2]))
        # A marker is an annotation: its shadow on the model read as a dark patch (Warhammer head).
        obj.visible_shadow = False
        markers.append(obj)

    # --- lights and camera
    sun_data = bpy.data.lights.new("Key", "SUN")
    sun_data.energy = SUN_GAIN * math.pi
    sun_data.angle = math.radians(3)
    sun = bpy.data.objects.new("Key", sun_data)
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("Ambient")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bg.inputs["Strength"].default_value = AMBIENT
    scene.world = world
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    scene.collection.objects.link(cam)
    scene.camera = cam

    def show(objs, visible):
        for o in tf.all_descendants(objs):
            o.hide_render = not visible

    raws = {}

    # Side: the weapon at hand height, the card visible.
    for h in holders:
        h.location = tf.gltf_to_blender(Vector(bp.pieces[0].pos) + Vector((0.0, lift, 0.0)))
    bpy.context.view_layer.update()
    show(figure + [ground_line] + markers, True)
    view = tf.gltf_to_blender(SIDE_DIR).normalized()
    fit_ortho(cam, mesh_points(holders) + mesh_points(figure) + mesh_points([ground_line]), view, SIDE_SIZE, margin=1.12)
    _, right, up = aim(cam, view)
    light_for(sun, view, right, up)
    setup_render(scene, SIDE_SIZE, 16)
    raws["side"] = os.path.join(raw_dir, f"{bp.id}_side.png")
    scene.render.filepath = raws["side"]
    bpy.ops.render.render(write_still=True)

    # Stage and icon: the weapon alone, back at its own origin.
    show(figure + [ground_line] + markers, False)
    for h in holders:
        h.location = tf.gltf_to_blender(bp.pieces[0].pos)
    bpy.context.view_layer.update()
    pts = mesh_points(holders)

    view = tf.gltf_to_blender(direction(STAGE_YAW, STAGE_PITCH)).normalized()
    fit_perspective(cam, pts, view, STAGE_SIZE)
    _, right, up = aim(cam, view)
    light_for(sun, view, right, up)
    setup_render(scene, STAGE_SIZE, 24)
    raws["stage"] = os.path.join(raw_dir, f"{bp.id}_stage.png")
    scene.render.filepath = raws["stage"]
    bpy.ops.render.render(write_still=True)

    # Icon: the long axis (the point for a blade or gun, the upper limb for a bow) to the diagonal.
    axis_index = max(range(3), key=lambda i: size[i])
    long_axis = [Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)), Vector((0.0, 0.0, -1.0))][axis_index]
    view = tf.gltf_to_blender(direction(ICON_YAW, ICON_PITCH)).normalized()
    _, right, up = aim(cam, view)
    a = tf.gltf_to_blender(long_axis)
    phi = math.atan2(a.dot(up), a.dot(right))
    roll = phi - math.pi / 4
    fit_ortho(cam, pts, view, (ICON_SIZE, ICON_SIZE), margin=1.08, roll=roll)
    _, right, up = aim(cam, view, roll)
    got = math.degrees(math.atan2(a.dot(up), a.dot(right)))
    if abs(got - 45.0) > 1.0:
        tf.warn(f"{bp.id}: icon roll landed the long axis at {got:.1f} degrees, not 45")
    light_for(sun, view, right, up)
    setup_render(scene, (ICON_SIZE, ICON_SIZE), 32)
    raws["icon"] = os.path.join(raw_dir, f"{bp.id}_icon_raw.png")
    scene.render.filepath = raws["icon"]
    bpy.ops.render.render(write_still=True)

    info = {
        "id": bp.id,
        "size": [round(size.x, 2), round(size.y, 2), round(size.z, 2)],
        "length": round(max(size), 2),
        "triangles": frame_rec.get("triangles"),
        "frame": frame,
        "markers": {k: list(MARKER_RGB.get(k, MARKER_OTHER)) for k in frame},
        "raws": raws,
        "out": out_dir,
    }
    compose(info)


def compose(info: dict) -> None:
    """Pillow is not in Blender's Python: weaponstrip.py runs under the system `py`."""
    helper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "weaponstrip.py")
    spec = os.path.join(info["out"], "_raw", f"{info['id']}_spec.json")
    with open(spec, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(info, fh, indent=2)
    try:
        result = subprocess.run(["py", helper, "--spec", spec], capture_output=True, text=True)
    except FileNotFoundError:
        tf.warn("weapon strip composition failed: py launcher not found")
        return
    if result.returncode != 0:
        tf.warn(f"weapon strip composition failed: {result.stderr.strip()}")
    else:
        for line in result.stdout.strip().splitlines():
            tf.log(line)
