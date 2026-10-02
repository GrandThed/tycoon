#!/usr/bin/env python
"""The Valley generator (M13 wave 2, docs/INTERFACES.md "Wave 2 -- the Valley meshes").

    py tools/world/valley.py build            # GLBs, palette, bake record, src/shared/Config/Valley.json
    py tools/world/valley.py check            # exit 0 iff the committed Valley.json equals a fresh build's
    py tools/world/valley.py build --count 6 --out-root <scratch> --data <scratch>/Valley.json

One run derives the whole landscape from the plot ring (tools/worldplan.py, the mirror of
WorldPlan.luau), the Village layout's plotSize, World.json (the road width and the colours wave 1
shares) and the art numbers in tools/world/Valley.plan.json, and writes

  * assets/build/world/Valley/<Mesh>.glb   one primitive each, no material, per-face normals
  * assets/build/world/Valley/palette.png  one opaque RGB swatch sheet for every `palette` mesh
  * assets/build/world/Valley.json         the bake record the uploader and harvest read
  * src/shared/Config/Valley.json          the game's data: mesh list, bridges, stones, river, wall

The server builds its bridge, stone and wall COLLISION from that last file, so every number in it
is the same number the mesh was built from. Stdlib only, seeded, and byte-for-byte repeatable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / "tools" / "assets"))

import glbtools  # noqa: E402
import palette as palette_tool  # noqa: E402  (write_png: the repo's stdlib RGB PNG writer)
import wgeom as G  # noqa: E402
import worldplan  # noqa: E402
import valleyprops as props  # noqa: E402
from valleyland import Land  # noqa: E402

VERSION = 1
SET_NAME = "Valley"
GENERATOR = "EraCityTycoon world"
PLAN_PATH = HERE / "Valley.plan.json"
DATA_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Valley.json"
BAKE_ROOT = REPO_ROOT / "assets" / "build" / "world"
CELL = 16  # palette swatch, pixels (tools/assets/palette.py)

# The contract's hard limits, asserted on every build.
MAX_TRIANGLES = 20000
MAX_BOX_SIDE = 1500.0
MAX_TERRAIN_RADIUS = 1600.0
MAX_MESHES = 32
NAME_PATTERN = re.compile(r"^[A-Za-z0-9_]{1,24}$")


class Mesh:
    def __init__(self, name, builder, frame="world", look="palette", required=False, tint=None, color=None, transparency=None):
        self.name, self.builder, self.frame, self.look = name, builder, frame, look
        self.required, self.tint, self.color, self.transparency = required, tint, color, transparency


def plan_hash(ring, plot_size, hub_radius, plot_margin, world, plan):
    """Everything the output depends on, so a stale upload or a stale Valley.json is detectable."""
    valley = world.get("valley") or {}
    subject = {
        "version": VERSION,
        "ring": [ring["plotCount"], round(ring["radius"], 6), plot_margin, hub_radius],
        "plotSize": list(plot_size),
        "world": {
            "roads": world.get("roads"),
            "hub": world.get("hub"),
            "ground": world.get("ground"),
            "wallSegments": (valley.get("wall") or {}).get("segments"),
        },
        "plan": plan,
    }
    text = json.dumps(subject, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def generate(count=None, log=print):
    game = worldplan.load_game()
    world = worldplan.load_world()
    plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
    size = worldplan.plot_size()
    plot_count = int(game["plotCount"] if count is None else count)
    ring = worldplan.ring(plot_count, float(game["plotMargin"]), float(game["hubRadius"]), size[0], size[2])
    land = Land(ring, size, float(game["hubRadius"]), world, plan)
    started = time.time()

    meshes = []
    ground = land.build_ground()
    for name in sorted(ground):
        meshes.append(Mesh(name, ground[name], required=name.startswith("Basin_")))
    log(f"  ground triangulated in {time.time() - started:.1f}s")

    outside, inside, tree_stats = props.build_trees(land)
    forest = props.split_by_angle(outside, "Forest")
    for name in sorted(forest, key=lambda n: int(n.split("_")[1])):
        meshes.append(Mesh(name, forest[name]))
    grove_stats = props.build_groves(land, inside)
    meshes.append(Mesh("Groves", inside))
    details = G.Builder()
    detail_stats = props.build_details(land, details)
    meshes.append(Mesh("Details", details))
    bed = G.Builder()
    props.build_riverbed(land, bed)
    meshes.append(Mesh("RiverBed", bed))
    fall = G.Builder()
    props.build_waterfall(land, fall)
    meshes.append(Mesh("Waterfall", fall))
    water = G.Builder()
    props.build_water(land, water)
    meshes.append(Mesh("Water", water, look="flat", color=plan["water"]["color"], transparency=plan["water"]["transparency"]))
    for number, bridge in enumerate(land.bridges, start=1):
        builder = G.Builder()
        props.build_bridge(land, bridge, builder)
        meshes.append(Mesh(f"Bridge_{number}", builder))
    clouds = props.build_clouds(land)
    for name in sorted(clouds):
        meshes.append(Mesh(name, clouds[name], look="flat", color=plan["clouds"]["color"], transparency=0))
    inner, outer, _rows = props.build_aprons(land)
    grey = [128, 128, 128]  # the server tints both bands per plot; this is only the template's colour
    meshes.append(Mesh("ApronInner", inner, frame="plot", look="flat", tint="apronInner", color=grey, transparency=0))
    meshes.append(Mesh("ApronOuter", outer, frame="plot", look="flat", tint="apronOuter", color=grey, transparency=0))
    meshes.append(Mesh("Entrance", props.build_entrance(land), frame="plot"))
    meshes = [m for m in meshes if m.builder.count() > 0]

    hash_ = plan_hash(ring, size, float(game["hubRadius"]), float(game["plotMargin"]), world, plan)
    stats = {**tree_stats, **grove_stats, **detail_stats}
    return {"land": land, "ring": ring, "plan": plan, "meshes": meshes, "planHash": hash_, "stats": stats}


# ---------------------------------------------------------------- the game data


def fmt(value, places):
    """A number with a fixed number of decimals and no float noise (and never '-0')."""
    text = f"{round(float(value), places):.{places}f}"
    if "." in text:
        text = text.rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def data_text(result):
    """src/shared/Config/Valley.json, as text. Roblox frame: X = map x, Z = -map y."""
    land, plan, ring = result["land"], result["plan"], result["ring"]
    cfg = plan["bridge"]
    lines = ["{"]
    lines.append('\t"version": 1,')
    lines.append(f'\t"plotCount": {ring["plotCount"]},')
    lines.append(f'\t"ringRadius": {fmt(ring["radius"], 4)},')
    lines.append(f'\t"planHash": "{result["planHash"]}",')
    lines.append(f'\t"overlayLift": {fmt(land.lift, 3)},')
    lines.append(f'\t"wallRadius": {fmt(land.wall_radius, 1)},')
    lines.append('\t"meshes": [')
    rows = []
    for mesh in result["meshes"]:
        row = f'{{ "name": "{mesh.name}", "frame": "{mesh.frame}"'
        if mesh.required:
            row += ', "required": true'
        if mesh.tint:
            row += f', "tint": "{mesh.tint}"'
        rows.append("\t\t" + row + " }")
    lines.append(",\n".join(rows))
    lines.append("\t],")
    lines.append('\t"bridges": [')
    rows = []
    for bridge in land.bridges:
        ux, uy = bridge["dir"]
        yaw = math.atan2(-uy, ux)  # the deck's long axis in X, Z, turning from +X toward +Z
        if yaw > math.pi / 2:
            yaw -= math.pi
        elif yaw <= -math.pi / 2:
            yaw += math.pi
        rows.append(
            "\t\t{ "
            + f'"x": {fmt(bridge["centre"][0], 3)}, "z": {fmt(-bridge["centre"][1], 3)}, "yaw": {fmt(yaw, 4)}, '
            + f'"length": {fmt(bridge["length"], 3)}, "width": {fmt(bridge["width"], 3)}, '
            + f'"deckTop": {fmt(cfg["deckTop"], 3)}, "deckThickness": {fmt(cfg["deckThickness"], 3)}, "rampLength": {fmt(cfg["rampLength"], 3)}'
            + " }"
        )
    lines.append(",\n".join(rows))
    lines.append("\t],")
    lines.append('\t"stones": [')
    pond = plan["pond"]
    rows = [
        f'\t\t{{ "x": {fmt(x, 3)}, "z": {fmt(-y, 3)}, "radius": {fmt(pond["stoneRadius"], 3)}, "top": {fmt(pond["stoneTop"], 3)} }}'
        for x, y in land.stones
    ]
    lines.append(",\n".join(rows))
    lines.append("\t],")
    lines.append('\t"river": [')
    rows = []
    river = land.river_near
    for (x, y), w in zip(river.pts, river.w):
        if math.hypot(x, y) <= land.r0:
            rows.append(f"\t\t[{fmt(x, 2)}, {fmt(-y, 2)}, {fmt(w / 2 + land.bank_out, 2)}]")
    lines.append(",\n".join(rows))
    lines.append("\t]")
    lines.append("}")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------- baking


def bake(result, out_root, data_path, log=print):
    land, plan = result["land"], result["plan"]
    meshes = result["meshes"]
    step = plan["quantise"]
    # one palette for the whole set: every distinct (quantised) face colour gets a swatch
    colours = set()
    faces = {}
    for mesh in meshes:
        rows = []
        for a, b, c, colour in mesh.builder.tris:
            key = G.quantise(colour, step) if mesh.look == "palette" else None
            if key is not None:
                colours.add(key)
            rows.append((a, b, c, key))
        faces[mesh.name] = rows
    ordered = sorted(colours)
    columns = max(1, math.ceil(math.sqrt(len(ordered))))
    rows_n = max(1, math.ceil(len(ordered) / columns))
    width, height = columns * CELL, rows_n * CELL
    pixels = [[(0, 0, 0)] * width for _ in range(height)]
    uv_of = {}
    for index, colour in enumerate(ordered):
        col, row = index % columns, index // columns
        for y in range(row * CELL, (row + 1) * CELL):
            for x in range(col * CELL, (col + 1) * CELL):
                pixels[y][x] = colour
        # glTF UVs: origin top-left, v grows downward; the centre of the swatch never bleeds
        uv_of[colour] = ((col + 0.5) * CELL / width, (row + 0.5) * CELL / height)

    set_dir = Path(out_root) / SET_NAME
    set_dir.mkdir(parents=True, exist_ok=True)
    for stale in sorted(set_dir.glob("*.glb")):
        if stale.stem not in {m.name for m in meshes}:
            stale.unlink()
    png_path = set_dir / "palette.png"
    palette_tool.write_png(str(png_path), width, height, pixels)
    png_bytes = png_path.read_bytes()

    problems = []
    if len(meshes) > MAX_MESHES:
        problems.append(f"{len(meshes)} meshes exceed the limit of {MAX_MESHES}")
    if land.r_out > MAX_TERRAIN_RADIUS:
        problems.append(f"terrain outer radius {land.r_out} exceeds {MAX_TERRAIN_RADIUS}")
    record_meshes = {}
    table = []
    total_tris = total_bytes = 0
    for mesh in meshes:
        positions, normals, uvs = [], [], []
        for a, b, c, key in faces[mesh.name]:
            pa, pb, pc = G.to_gltf(a), G.to_gltf(b), G.to_gltf(c)
            ux, uy, uz = pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]
            vx, vy, vz = pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2]
            nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            if length < 1e-9:
                continue  # a degenerate face has no normal and no area
            normal = (nx / length, ny / length, nz / length)
            uv = uv_of[key] if key is not None else (0.5, 0.5)
            positions.extend((pa, pb, pc))
            normals.extend((normal, normal, normal))
            uvs.extend((uv, uv, uv))
        triangles = len(positions) // 3
        data, lo, hi = G.glb_bytes(mesh.name, positions, normals, uvs, GENERATOR)
        size = [hi[i] - lo[i] for i in range(3)]
        centre = [(hi[i] + lo[i]) / 2 for i in range(3)]
        if not NAME_PATTERN.match(mesh.name):
            problems.append(f"{mesh.name}: name must match {NAME_PATTERN.pattern}")
        if triangles > MAX_TRIANGLES:
            problems.append(f"{mesh.name}: {triangles} triangles exceed {MAX_TRIANGLES}")
        if triangles == 0:
            problems.append(f"{mesh.name}: no triangles")
        if max(size) > MAX_BOX_SIDE:
            problems.append(f"{mesh.name}: bounding box side {max(size):.1f} exceeds {MAX_BOX_SIDE}")
        if min(size) <= 0.0:
            problems.append(f"{mesh.name}: a zero-height bounding box (the importer rejects it)")
        for line in glbtools.roblox_problems(data):
            problems.append(f"{mesh.name}: {line}")
        doc, _ = glbtools.parse_glb(data)
        prims = [p for m in doc["meshes"] for p in m["primitives"]]
        if len(doc["meshes"]) != 1 or len(prims) != 1 or "material" in prims[0] or doc.get("materials") or doc.get("images"):
            problems.append(f"{mesh.name}: must be one mesh, one primitive, no material, no image")
        path = set_dir / f"{mesh.name}.glb"
        path.write_bytes(data)
        entry = {
            "file": f"{SET_NAME}/{mesh.name}.glb",
            "sha256": G.sha256(data),
            "triangles": triangles,
            "vertices": len(positions),
            "centre": [round(v, 6) for v in centre],
            "size": [round(v, 6) for v in size],
            "look": mesh.look,
        }
        if mesh.look == "flat":
            entry["color"] = [int(v) for v in mesh.color]
            entry["transparency"] = mesh.transparency
        record_meshes[mesh.name] = entry
        table.append((mesh.name, mesh.look, mesh.frame, triangles, len(positions), size, len(data)))
        total_tris += triangles
        total_bytes += len(data)
    record = {
        "set": SET_NAME,
        "plotCount": result["ring"]["plotCount"],
        "ringRadius": round(result["ring"]["radius"], 4),
        "planHash": result["planHash"],
        "palette": {"file": f"{SET_NAME}/palette.png", "sha256": G.sha256(png_bytes), "size": [width, height]},
        "meshes": record_meshes,
    }
    record_text = json.dumps(record, indent=2) + "\n"
    record_path = Path(out_root) / f"{SET_NAME}.json"
    if record_path.resolve() == Path(data_path).resolve():
        # `--data <out-root>/Valley.json` names the bake record's own file: the game data wins the
        # name it was asked for, and the record moves aside so neither overwrites the other.
        record_path = Path(out_root) / f"{SET_NAME}.bake.json"
        log(f"note: --data is the bake record's path; the record is written to {record_path.name} instead")
    record_path.write_bytes(record_text.encode("utf-8"))
    text = data_text(result)
    Path(data_path).parent.mkdir(parents=True, exist_ok=True)
    Path(data_path).write_bytes(text.encode("utf-8"))

    log("")
    log(f"{'mesh':<14}{'look':<9}{'frame':<7}{'tris':>7}{'verts':>8}  {'bounding box (X, Y, Z)':<30}{'bytes':>10}")
    for name, look, frame, tris, verts, size, nbytes in table:
        box = f"{size[0]:.1f} x {size[1]:.2f} x {size[2]:.1f}"
        log(f"{name:<14}{look:<9}{frame:<7}{tris:>7}{verts:>8}  {box:<30}{nbytes:>10}")
    log(f"{'TOTAL':<14}{len(table):>3} meshes   {total_tris:>7}{total_tris * 3:>8}  {'':<30}{total_bytes:>10}")
    log(f"palette: {len(ordered)} swatches, {width} x {height} px, {len(png_bytes)} bytes")
    most = max(table, key=lambda row: row[3])
    widest = max(table, key=lambda row: max(row[5]))
    log(f"most triangles: {most[0]} ({most[3]}); largest bounding box: {widest[0]} ({max(widest[5]):.1f} studs)")
    return problems, record


def summary(result, log):
    land = result["land"]
    log(f"ring: {land.count} plots, radius {land.radius:.4f}, front {land.inner:.2f}, back {land.outer:.2f}, far corner {land.corner:.2f}")
    log(f"foothills start r0 = {land.r0:.2f}; wallRadius {land.wall_radius}; terrain outer radius {land.r_out:.1f}; planHash {result['planHash']}")
    sx, sy, sh = land.summit
    log(f"summit: {sh:.1f} studs above the ground top at radius {math.hypot(sx, sy):.1f}, X {sx:.1f}, Z {-sy:.1f} ({math.degrees(math.atan2(-sy, sx)) % 360:.1f} deg)")
    for note in land.notes:
        log(note)
    log("props: " + ", ".join(f"{k} {v}" for k, v in result["stats"].items()))


def main(argv):
    parser = argparse.ArgumentParser(prog="valley.py", description="Build or check the Valley meshes and their game data.")
    parser.add_argument("command", choices=("build", "check"))
    parser.add_argument("--count", type=int, help="plotCount to build for (default: Game.json's)")
    parser.add_argument("--out-root", default=str(BAKE_ROOT), help="bake root (default assets/build/world)")
    parser.add_argument("--data", default=str(DATA_PATH), help="where Valley.json is written, or read by check")
    args = parser.parse_args(argv)
    started = time.time()
    if args.command == "check":
        result = generate(args.count, log=lambda *_: None)
        fresh = data_text(result)
        path = Path(args.data)
        if not path.exists():
            print(f"valley check: {path} is missing (run `py tools/world/valley.py build`)")
            return 1
        committed = path.read_text(encoding="utf-8")
        if committed != fresh:
            print(f"valley check: {path} differs from a fresh build (planHash now {result['planHash']}); run `py tools/world/valley.py build`")
            return 1
        print(f"valley check: ok ({len(result['meshes'])} meshes, planHash {result['planHash']}, {time.time() - started:.1f}s)")
        return 0
    print(f"== Valley build ({'Game.json plotCount' if args.count is None else f'--count {args.count}'})")
    result = generate(args.count)
    summary(result, print)
    problems, _record = bake(result, args.out_root, args.data)
    print(f"wrote {Path(args.out_root) / SET_NAME}, its bake record and {args.data} in {time.time() - started:.1f}s")
    if problems:
        print("HARD LIMITS BROKEN:")
        for line in problems:
            print("  " + line)
        return 1
    print("all hard limits hold")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
