"""Preview gate for the Valley (M13 wave 2): renders THE BAKED GLBs, not the generator's data.

    blender -b -P tools/world/preview.py -- [--cameras aerial,plot,hub,back,apron,apron2,pond]
                                            [--collision] [--count 6 --root <bake root> --data <Valley.json> --stem V6]

Every `.glb` under <bake root>/Valley/ is imported as the game will get it and given the look the
template gives it: `palette.png` through its UVs with Closest filtering, or the bake record's
flat colour and transparency. World-frame meshes go to the origin with the ground top at the
plots' Y = -plotSize.Y; plot-frame meshes are cloned onto every plot and tinted from World.json
`valley.aprons` by that plot's era. BACK-FACE CULLING IS ON, as in the game, so a face wound the
wrong way shows as a hole. `--collision` adds what the server builds from Valley.json: the wall,
each bridge's deck and ramps, each stepping stone's cylinder.

The plots, cameras, lighting and haze are the mock's (assets/research/2026-10-01-worldmock: the
cached ring of real plots, wm_world.py's cameras, wm_post.py's distance haze), so a render here
lines up with the A2 picture of the same name. Raw renders land in the mock's scratch folder;
`py tools/world/preview_post.py` adds the haze and builds the A2 | V sheets.
"""

import argparse
import json
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MOCK = os.path.join(REPO_ROOT, "assets", "research", "2026-10-01-worldmock")
if not os.path.isfile(os.path.join(MOCK, "wm_world.py")):
    raise SystemExit(f"preview: the mock's scripts are not at {MOCK}")
sys.path.insert(0, MOCK)
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

import wm_geom  # noqa: E402
import wm_valley2  # noqa: E402
import wm_world  # noqa: E402
import worldplan  # noqa: E402
from wm_common import RINGS, SCRATCH, Ring, lin  # noqa: E402

SET_NAME = "Valley"
COLLISION = (236, 40, 200)  # bridges and stones
WALL = (255, 214, 40)


def log(msg):
    print(f"[valley preview] {msg}", flush=True)


def palette_material(image_path):
    mat = bpy.data.materials.new("ValleyPalette")
    mat.use_nodes = True
    tree = mat.node_tree
    bsdf = tree.nodes.get("Principled BSDF")
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path)
    tex.interpolation = "Closest"
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    mat.use_backface_culling = True
    return mat


def flat_material(name, color, transparency):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*lin(color), 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2  # the mock's water: no pale sheen at a grazing angle
    if transparency and transparency > 0:
        bsdf.inputs["Alpha"].default_value = 1.0 - transparency
        mat.surface_render_method = "BLENDED"
    mat.use_backface_culling = True
    return mat


def import_glb(path, collection):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    made = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in made if o.type == "MESH"]
    if len(meshes) != 1:
        raise SystemExit(f"preview: {path} imported as {len(meshes)} mesh objects, expected exactly 1")
    for o in made:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        collection.objects.link(o)
        o.select_set(False)
    return meshes[0]


def build_valley(ring, infos, bake_root, world, collection):
    record_path = os.path.join(bake_root, f"{SET_NAME}.json")
    aside = os.path.join(bake_root, f"{SET_NAME}.bake.json")  # a scratch build whose --data took the name
    if os.path.isfile(aside):
        record_path = aside
    record = json.load(open(record_path, "r", encoding="utf-8"))
    data_meshes = {}
    palette = palette_material(os.path.join(bake_root, record["palette"]["file"]))
    aprons = (world.get("valley") or {}).get("aprons") or {}
    count = 0
    return_frames = {}
    for name, entry in record["meshes"].items():
        obj = import_glb(os.path.join(bake_root, entry["file"]), collection)
        obj.visible_shadow = name[:6] not in ("Clouds", "ApronI", "ApronO") and name != "Water" and not name.startswith("Basin")
        if entry["look"] == "palette":
            obj.data.materials.append(palette)
        else:
            obj.data.materials.append(flat_material(f"Flat_{name}", entry["color"], entry.get("transparency", 0)))
        data_meshes[name] = obj
        count += 1
    return data_meshes, record, aprons, return_frames, count


def place(meshes, plan, ring, infos, aprons, drop, collection):
    """World-frame meshes at the origin, plot-frame meshes once per plot (tinted where asked)."""
    for item in plan["meshes"]:
        obj = meshes.get(item["name"])
        if obj is None:
            log(f"WARNING: Valley.json names {item['name']} but no GLB was baked for it")
            continue
        if item["frame"] == "world":
            obj.location = (0.0, 0.0, -drop)
            continue
        for info in infos:
            index = info["index"]
            holder = bpy.data.objects.new(f"{item['name']}_{index}", None)
            cx, cy = ring.centre(index)
            holder.location = (cx, cy, -drop)
            holder.rotation_euler = (0.0, 0.0, ring.angle(index) + math.pi / 2)
            collection.objects.link(holder)
            clone = obj.copy()
            clone.parent = holder
            collection.objects.link(clone)
            clone.visible_shadow = obj.visible_shadow
            tint = item.get("tint")
            if tint:
                era = aprons.get(info["era"])
                if era is None:
                    clone.hide_render = True
                    continue
                colour = era["inner"] if tint == "apronInner" else era["outer"]
                clone.material_slots[0].link = "OBJECT"
                clone.material_slots[0].material = flat_material(f"Tint_{item['name']}_{index}", colour, 0)
        obj.hide_render = True  # the template itself is not in the world


def build_wave1(ring, world, drop, pad, collection):
    """What is left of wave 1 in mesh mode: the green Ground Part and the stone Hub (and the spawn pad)."""
    b = wm_geom.MeshBuilder()
    side = worldplan.ground_side({"radius": ring.radius}, ring.plot_z, world["ground"].get("side"))
    b.box((0.0, 0.0, -drop - 0.5), (side, side, 1.0), lin(world["ground"]["color"]))
    b.frustum((0.0, 0.0), ring.hub_radius, ring.hub_radius, -drop, 0.0, lin(world["hub"]["color"]), sides=64)
    b.box((0.0, 0.0, pad[1] / 2), (pad[0], pad[2], pad[1]), lin((163, 162, 165)))
    b.build("Wave1", wm_geom.attr_material("WMAttr"), collection)


def build_collision(plan, world, drop, collection):
    """The server's collision, drawn bright and a hair larger than itself so it tints what it lies in."""
    grow = 0.03
    solid = wm_geom.MeshBuilder()
    colour = lin(COLLISION)
    for bridge in plan["bridges"]:
        x, y = bridge["x"], -bridge["z"]
        yaw = -bridge["yaw"]  # Roblox (X, Z) -> Blender (x, -z): the turn changes hand
        ux, uy = math.cos(yaw), math.sin(yaw)
        nx, ny = -uy, ux
        top, thick = bridge["deckTop"], bridge["deckThickness"]
        solid.box((x, y, -drop + top - thick / 2), (bridge["length"] + grow, bridge["width"] + grow, thick + grow), colour, rot=yaw)
        half = bridge["width"] / 2
        for sign in (-1.0, 1.0):
            ex, ey = x + ux * sign * bridge["length"] / 2, y + uy * sign * bridge["length"] / 2
            ox, oy = ex + ux * sign * bridge["rampLength"], ey + uy * sign * bridge["rampLength"]
            z1, z0 = -drop + top + grow, -drop + grow
            a, c = (ex + nx * half, ey + ny * half, z1), (ex - nx * half, ey - ny * half, z1)
            d, e = (ox - nx * half, oy - ny * half, z0), (ox + nx * half, oy + ny * half, z0)
            a0, c0 = (a[0], a[1], z0), (c[0], c[1], z0)
            for quad in ((a, c, d, e), (e, d, c, a)):
                solid.quad(*quad, colour)
            for tri in ((a, e, a0), (a0, e, a), (c, c0, d), (d, c0, c)):
                solid.tri(*tri, colour)
    for stone in plan["stones"]:
        solid.frustum((stone["x"], -stone["z"]), stone["radius"] + grow, stone["radius"] + grow, -drop, -drop + stone["top"] + grow, colour, sides=24)
    obj = solid.build("Collision", wm_geom.flat_material(COLLISION, 0.6, emission=0.6), collection, shadow=False)
    wall = (world.get("valley") or {}).get("wall") or {}
    segments = int(wall.get("segments", 36))
    height, thickness = float(wall.get("height", 160)), float(wall.get("thickness", 4))
    radius = plan["wallRadius"]
    width = 2 * (radius + thickness) * math.tan(math.pi / segments)
    walls = wm_geom.MeshBuilder()
    for k in range(segments):
        a = k / segments * math.tau
        cx, cy = (radius + thickness / 2) * math.cos(a), (radius + thickness / 2) * math.sin(a)
        walls.box((cx, cy, -drop + height / 2), (thickness, width, height), lin(WALL), rot=a)
    mat = flat_material("WallDebug", WALL, 0.72)
    mat.use_backface_culling = False
    wobj = walls.build("WallDebug", mat, collection, shadow=False)
    return obj, wobj


def river_block(plan, margin):
    """The client's skirt rule: a skirt entry within halfWidth + skirtMargin of the river is not drawn."""
    samples = [(x, -z, hw) for x, z, hw in plan["river"]]

    def blocked(px, py):
        for (ax, ay, aw), (bx, by, bw) in zip(samples, samples[1:]):
            dx, dy = bx - ax, by - ay
            ll = dx * dx + dy * dy
            t = 0.0 if ll == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / ll))
            if math.hypot(px - ax - dx * t, py - ay - dy * t) < aw + (bw - aw) * t + margin:
                return True
        return False

    return blocked


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="preview.py")
    parser.add_argument("--count", type=int, default=None)
    parser.add_argument("--root", default=os.path.join(REPO_ROOT, "assets", "build", "world"))
    parser.add_argument("--data", default=os.path.join(REPO_ROOT, "src", "shared", "Config", "Valley.json"))
    parser.add_argument("--cameras", default="aerial,plot,hub,back,apron,apron2,pond")
    parser.add_argument("--stem", default="V")
    parser.add_argument("--collision", action="store_true")
    parser.add_argument("--no-plots", action="store_true", help="plot bases only (quick look)")
    args = parser.parse_args(argv)

    plan = json.load(open(args.data, "r", encoding="utf-8"))
    world = worldplan.load_world()
    count = args.count or plan["plotCount"]
    if plan["plotCount"] != count:
        raise SystemExit(f"preview: Valley.json is baked for {plan['plotCount']} plots, asked for {count}")
    ring = Ring(count)
    if abs(ring.radius - plan["ringRadius"]) > 1e-3:
        raise SystemExit(f"preview: the mock's ring ({ring.radius:.4f}) is not Valley.json's ({plan['ringRadius']})")
    keys = RINGS[count]
    states = wm_world.load_states(keys)
    infos = wm_world.plot_infos(ring, keys, states)
    mode = "bases" if args.no_plots else "full"
    cache = str(SCRATCH / f"ring{count}_{mode}.blend")
    if not os.path.exists(cache):
        raise SystemExit(f"preview: the cached ring {cache} is missing (run the mock's wm_world.py once to build it)")
    bpy.ops.wm.open_mainfile(filepath=cache)
    scene = bpy.context.scene
    log(f"ring of {count} plots loaded: {len(bpy.data.objects)} objects")

    drop = ring.plot_y  # the ground top is plotSize.Y under the plot tops
    common = bpy.data.collections.new("Common")
    scene.collection.children.link(common)
    wm_world.build_signs(ring, infos, common)
    build_wave1(ring, world, drop, infos[0]["padSize"], common)
    valley = bpy.data.collections.new("Valley")
    scene.collection.children.link(valley)
    meshes, record, aprons, _, n = build_valley(ring, infos, args.root, world, valley)
    place(meshes, plan, ring, infos, aprons, drop, valley)
    log(f"{n} baked meshes imported from {args.root}; planHash {record['planHash']} / {plan['planHash']}")
    if record["planHash"] != plan["planHash"]:
        log("WARNING: the bake record and Valley.json have different planHash values")
    if args.collision:
        build_collision(plan, world, drop, valley)
    margin = float((world.get("valley") or {}).get("skirtMargin", 0.0))
    hidden = wm_world.apply_skirt_mask(river_block(plan, margin))
    log(f"{hidden} skirt models stand in the river channel and are hidden (the client's rule)")

    wm_world.setup_light(scene)
    wm_world.configure_render(scene, (1600, 1000))
    look = wm_valley2.Valley2
    wm_world.set_sky(scene, look.sky)
    stats = {"haze": look.haze, "hazeColour": list(look.haze_colour)}
    os.makedirs(str(SCRATCH / "raw"), exist_ok=True)
    stem = args.stem + ("c" if args.collision else "")
    with open(SCRATCH / "raw" / f"{stem}_stats.json", "w", encoding="utf-8") as handle:
        json.dump(stats, handle)
    cameras = wm_world.camera_specs(ring, infos)
    for name in [c for c in args.cameras.split(",") if c]:
        spec = cameras[name]
        camera = wm_world.make_camera(scene, spec["eye"], spec["target"], spec["lens"])
        player = None
        if "player" in spec:
            px, py, _ = spec["player"]
            player = wm_world.build_player((px, py, -drop), ring.angle(0), valley)
        bpy.context.view_layer.update()
        wm_world.render_pair(scene, f"{stem}_{name}", haze=True)
        if player is not None:
            bpy.data.objects.remove(player, do_unlink=True)
        bpy.data.objects.remove(camera, do_unlink=True)
    log("done")


if __name__ == "__main__":
    main()
