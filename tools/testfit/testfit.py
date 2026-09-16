"""Offline test-fit renderer for modular Kenney buildings.

Run inside Blender (headless):

    blender -b -P tools/testfit/testfit.py -- --blueprint <file.json> --out <dir> [--stage N]
    blender -b -P tools/testfit/testfit.py -- --dump-bounds <kit-slug>

A city-dressing prop blueprint (blueprints/_props/<Era>/, or any blueprint with --props) renders
only the stages it defines, and without --out lands in assets/testfit/out/<Era>/props/.

Blueprint coordinates use the glTF/Roblox convention (Y up, front faces -Z) in kit
units before scaling.  Blender is Z up, so every position is converted with
(x, y, z) -> (x, -z, y) and every reported bound is converted back.
"""

import argparse
import math
import os
import subprocess
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blueprint import STAGE_COUNT, BlueprintError, is_prop_blueprint, load_blueprint  # noqa: E402

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
KITS_ROOT = os.path.join(REPO_ROOT, "assets", "kenney3d")
OUT_ROOT = os.path.join(REPO_ROOT, "assets", "testfit", "out")
MODEL_DIRS = ("GLB format", "GLTF format")
PLAYER_HEIGHT_STUDS = 5.0
RENDER_SIZE = (1280, 960)
# Three-quarter view from the front-right; the front of a building faces -Z in glTF space.
CAMERA_DIR_GLTF = Vector((1.0, 0.72, -1.35))


def log(msg):
    print(f"[testfit] {msg}", flush=True)


def warn(msg):
    print(f"[testfit] WARNING: {msg}", flush=True)


def gltf_to_blender(v):
    return Vector((v[0], -v[2], v[1]))


def blender_to_gltf(v):
    return Vector((v[0], v[2], -v[1]))


# --- Scene helpers ----------------------------------------------------------


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def find_glb(kit, model):
    kit_dir = os.path.join(KITS_ROOT, kit, "Models")
    for sub in MODEL_DIRS:
        path = os.path.join(kit_dir, sub, f"{model}.glb")
        if os.path.isfile(path):
            return path
    return None


def list_kit_glbs(kit):
    kit_dir = os.path.join(KITS_ROOT, kit, "Models")
    for sub in MODEL_DIRS:
        folder = os.path.join(kit_dir, sub)
        if os.path.isdir(folder):
            return folder, sorted(f for f in os.listdir(folder) if f.lower().endswith(".glb"))
    return None, []


def import_glb(path):
    """Import one GLB and return its top-level objects (empties or meshes)."""
    before = set(bpy.data.objects)
    try:
        bpy.ops.import_scene.gltf(filepath=path)
    except Exception as exc:  # the importer raises on malformed files
        warn(f"import failed for {path}: {exc}")
        return []
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        o.select_set(False)
    return [o for o in new if o.parent not in new]


def all_descendants(objs):
    out = []
    stack = list(objs)
    while stack:
        o = stack.pop()
        out.append(o)
        stack.extend(o.children)
    return out


def world_bounds(objs):
    """Axis-aligned bounds in Blender space of every mesh in objs and their children."""
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    found = False
    for o in all_descendants(objs):
        if o.type != "MESH":
            continue
        for corner in o.bound_box:
            p = o.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
            found = True
    return (lo, hi) if found else None


def gltf_bounds(objs):
    b = world_bounds(objs)
    if b is None:
        return None
    lo, hi = b
    g1 = blender_to_gltf(lo)
    g2 = blender_to_gltf(hi)
    return Vector(map(min, g1, g2)), Vector(map(max, g1, g2))


def make_box(name, size, center, material, collection):
    mesh = bpy.data.meshes.new(name)
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    verts = [(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = center
    obj.data.materials.append(material)
    collection.objects.link(obj)
    return obj


def flat_material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def setup_render(scene, out_path):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = out_path
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 16
    # Standard keeps the kit's flat colours readable; AgX/Filmic would grey them out.
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass


def setup_lights(scene):
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.0
    sun_data.angle = math.radians(4)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    scene.collection.objects.link(sun)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.82, 0.85, 0.9, 1.0)
        bg.inputs["Strength"].default_value = 0.9
    scene.world = world


def setup_camera(scene, lo, hi):
    """Perspective camera on the front-right three-quarter, pulled back just enough to fit the bounds."""
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 45.0
    cam_data.sensor_fit = "HORIZONTAL"
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam

    center = (lo + hi) / 2
    direction = gltf_to_blender(CAMERA_DIR_GLTF).normalized()
    rot = (-direction).to_track_quat("-Z", "Y")
    right = rot @ Vector((1, 0, 0))
    up = rot @ Vector((0, 1, 0))
    aspect = RENDER_SIZE[0] / RENDER_SIZE[1]
    tan_x = math.tan(cam_data.angle_x / 2)
    tan_y = tan_x / aspect
    distance = 1.0
    for corner in ((x, y, z) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)):
        rel = Vector(corner) - center
        depth = rel.dot(direction)  # positive = toward the camera
        distance = max(distance, depth + abs(rel.dot(right)) / tan_x, depth + abs(rel.dot(up)) / tan_y)
    distance *= 1.08
    cam.location = center + direction * distance
    cam.rotation_euler = rot.to_euler()
    cam_data.clip_end = distance * 4


# --- Blueprint rendering ------------------------------------------------------


class PieceCache:
    def __init__(self, library_collection):
        self.library = library_collection
        self.templates = {}

    def get(self, kit, model):
        key = (kit, model)
        if key in self.templates:
            return self.templates[key]
        path = find_glb(kit, model)
        if path is None:
            warn(f"missing GLB: {kit}/{model}.glb (piece skipped)")
            self.templates[key] = None
            return None
        roots = import_glb(path)
        if not roots:
            self.templates[key] = None
            return None
        for o in all_descendants(roots):
            for c in list(o.users_collection):
                c.objects.unlink(o)
            self.library.objects.link(o)
        self.templates[key] = roots
        return roots

    def instantiate(self, roots, parent, collection):
        def copy_tree(src, new_parent):
            dup = src.copy()  # linked duplicate: shares mesh data
            dup.parent = new_parent
            dup.matrix_parent_inverse = src.matrix_parent_inverse.copy()
            collection.objects.link(dup)
            for child in src.children:
                copy_tree(child, dup)
            return dup

        return [copy_tree(r, parent) for r in roots]


def render_blueprint(bp_path, out_dir, only_stage, prop=False):
    try:
        bp = load_blueprint(bp_path)
    except BlueprintError as exc:
        warn(f"blueprint {bp_path} rejected: {exc}")
        return
    for message in bp.warnings:
        warn(message)
    bid = bp.id
    scale = bp.scale
    os.makedirs(out_dir, exist_ok=True)

    clear_scene()
    scene = bpy.context.scene
    library = bpy.data.collections.new("Library")
    building = bpy.data.collections.new("Building")
    props = bpy.data.collections.new("Props")
    for c in (library, building, props):
        scene.collection.children.link(c)
    library.hide_render = True
    library.hide_viewport = True

    cache = PieceCache(library)
    placed = []  # (stage, root_empty, name)
    for piece in bp.pieces:
        roots = cache.get(piece.kit, piece.model)
        if roots is None:
            continue
        holder = bpy.data.objects.new(f"p{piece.index:02d}_{piece.model}", None)
        holder.location = gltf_to_blender(piece.pos)
        holder.rotation_euler = (0.0, 0.0, math.radians(piece.rot_y))
        building.objects.link(holder)
        cache.instantiate(roots, holder, building)
        placed.append((piece.stage, holder, piece.label))

    bpy.context.view_layer.update()

    # Footprint in kit units: fx along X, fz along glTF Z (Blender -Y); the frame is drawn to fit it.
    fx = bp.footprint[0] / scale
    fz = bp.footprint[1] / scale
    ground_mat = flat_material("Ground", (0.62, 0.62, 0.60))
    frame_mat = flat_material("Frame", (0.85, 0.25, 0.2))
    player_mat = flat_material("Player", (0.2, 0.45, 0.85))
    fp = max(fx, fz)
    make_box("Ground", (fp * 60, fp * 60, 0.02), (0, 0, -0.011), ground_mat, props)
    t = 0.16 / scale  # frame thickness: 0.16 studs
    hx = fx / 2
    hz = fz / 2
    make_box("FrameN", (fx + t, t, t), (0, hz, t / 2), frame_mat, props)
    make_box("FrameS", (fx + t, t, t), (0, -hz, t / 2), frame_mat, props)
    make_box("FrameE", (t, fz + t, t), (hx, 0, t / 2), frame_mat, props)
    make_box("FrameW", (t, fz + t, t), (-hx, 0, t / 2), frame_mat, props)
    ph = PLAYER_HEIGHT_STUDS / scale
    pw = ph * 0.4
    player_pos = gltf_to_blender((hx + pw * 1.2, ph / 2, -hz + pw))
    make_box("Player", (pw, pw, ph), player_pos, player_mat, props)

    setup_lights(scene)
    bpy.context.view_layer.update()

    # Frame the camera on the full assembly plus the footprint so every stage shares one view.
    full = world_bounds([p[1] for p in placed] + [o for o in props.objects if o.name != "Ground"])
    if full is None:
        full = (Vector((-hx, -hz, 0)), Vector((hx, hz, ph)))
    setup_camera(scene, *full)

    # Props are not slots: they have exactly the stages their pieces use (TreeGrowing 4, most 1).
    stage_total = bp.stage_count if prop else STAGE_COUNT
    stages = [only_stage] if only_stage is not None else list(range(stage_total))
    outputs = {}
    for stage in stages:
        visible = []
        for pstage, holder, _ in placed:
            show = pstage <= stage
            for o in all_descendants([holder]):
                o.hide_render = not show
            if show:
                visible.append(holder)
        bounds = gltf_bounds(visible)
        if bounds is None:
            log(f"stage {stage}: 0 pieces")
        else:
            lo, hi = bounds
            size = (hi - lo) * scale
            log(
                f"stage {stage}: {len(visible)} pieces, bounds studs "
                f"x[{lo.x * scale:.2f}, {hi.x * scale:.2f}] "
                f"y[{lo.y * scale:.2f}, {hi.y * scale:.2f}] "
                f"z[{lo.z * scale:.2f}, {hi.z * scale:.2f}] "
                f"size {size.x:.2f} x {size.y:.2f} x {size.z:.2f}"
            )
        for pstage, holder, name in placed:
            if pstage != stage:
                continue
            b = gltf_bounds([holder])
            if b is None:
                continue
            lo, hi = b
            eps = 0.01
            if lo.x < -hx - eps or hi.x > hx + eps or lo.z < -hz - eps or hi.z > hz + eps:
                warn(
                    f"stage {stage}: piece {name} exceeds the {bp.footprint[0]:g}x{bp.footprint[1]:g} footprint: "
                    f"x[{lo.x * scale:.2f}, {hi.x * scale:.2f}] z[{lo.z * scale:.2f}, {hi.z * scale:.2f}] studs"
                )
        out_path = os.path.join(out_dir, f"{bid}_stage{stage}.png")
        setup_render(scene, out_path)
        bpy.ops.render.render(write_still=True)
        outputs[stage] = out_path
        log(f"wrote {out_path}")

    if only_stage is None:
        strip_path = os.path.join(out_dir, f"{bid}_strip.png")
        compose_strip([outputs[s] for s in range(stage_total)], strip_path)


def compose_strip(stage_paths, strip_path):
    """Blender's Python has no Pillow, so the strip is composed by strip.py under the system `py`."""
    helper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "strip.py")
    args = [helper, "--out", strip_path, *stage_paths]
    try:
        import PIL  # noqa: F401

        result = subprocess.run([sys.executable, *args], capture_output=True, text=True)
    except ImportError:
        try:
            result = subprocess.run(["py", *args], capture_output=True, text=True)
        except FileNotFoundError:
            result = None
    if result is None or result.returncode != 0:
        detail = result.stderr.strip() if result else "py launcher not found"
        warn(f"strip composition failed: {detail}")
    else:
        log(f"wrote {strip_path}")


# --- Kit inspection -------------------------------------------------------------


def dump_bounds(kit):
    folder, files = list_kit_glbs(kit)
    if folder is None:
        warn(f"kit not found: {kit} (looked under {KITS_ROOT})")
        return
    clear_scene()
    log(f"{kit}: {len(files)} GLBs in {folder}")
    print(f"{'model':40s} {'size x':>7s} {'size y':>7s} {'size z':>7s} | {'min':>22s} | {'max':>22s} | origin")
    for f in files:
        roots = import_glb(os.path.join(folder, f))
        name = f[:-4]
        b = gltf_bounds(roots) if roots else None
        if b is None:
            print(f"{name:40s} (no mesh)")
        else:
            lo, hi = b
            size = hi - lo
            cx, cz = (lo.x + hi.x) / 2, (lo.z + hi.z) / 2
            if abs(cx) < 0.01 and abs(cz) < 0.01 and abs(lo.y) < 0.01:
                origin = "bottom-centre"
            elif abs(lo.y) < 0.01:
                origin = f"bottom, centre off by ({cx:+.2f}, {cz:+.2f})"
            else:
                origin = f"centre off by ({cx:+.2f}, {(lo.y + hi.y) / 2:+.2f}, {cz:+.2f})"
            print(
                f"{name:40s} {size.x:7.3f} {size.y:7.3f} {size.z:7.3f} | "
                f"[{lo.x:6.2f} {lo.y:6.2f} {lo.z:6.2f}] | [{hi.x:6.2f} {hi.y:6.2f} {hi.z:6.2f}] | {origin}"
            )
        for o in all_descendants(roots):
            bpy.data.objects.remove(o, do_unlink=True)
    # Drop orphan meshes/images so a 300-piece kit does not balloon memory.
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="testfit.py")
    parser.add_argument("--blueprint", help="blueprint JSON to render")
    parser.add_argument("--out", help="output folder (default assets/testfit/out, or assets/testfit/out/<Era>/props for a prop)")
    parser.add_argument("--stage", type=int, help="render only this stage (0-4)")
    parser.add_argument("--props", action="store_true", help="treat the blueprint as a city-dressing prop wherever it lives")
    parser.add_argument("--dump-bounds", metavar="KIT", help="print size and origin of every GLB in a kit")
    args = parser.parse_args(argv)

    if args.dump_bounds:
        dump_bounds(args.dump_bounds)
    elif args.blueprint:
        bp_path = os.path.abspath(args.blueprint)
        prop = args.props or is_prop_blueprint(bp_path)
        if args.out:
            out_dir = args.out
        elif prop:
            out_dir = os.path.join(OUT_ROOT, os.path.basename(os.path.dirname(bp_path)), "props")
        else:
            out_dir = OUT_ROOT
        render_blueprint(bp_path, os.path.abspath(out_dir), args.stage, prop)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
