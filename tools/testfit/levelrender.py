"""Renders a dressed level from its generator's data file: a verbatim mirror of what the game will
place (the plotrender pattern), for Ben's look before anything is uploaded.

    py tools/testfit/levelrender.py                       # every view, both moods where asked
    py tools/testfit/levelrender.py --views top,campA     # some views
    py tools/testfit/levelrender.py --sheet               # the kit's contact sheet
    py tools/testfit/levelrender.py --barriers            # the plan with the invisible walls drawn

Run it with the system `py` (3.14 has Pillow; no shebang on purpose: a `#!/usr/bin/env python`
first line makes `py` pick 3.12, which has none). It writes one scene file per view, runs Blender
on this same file (`blender -b -P levelrender.py -- --blender --scene <file>`), then adds the
haze of mood B and the labels in Pillow. Output: assets/testfit/out/Levels/<Layout>/.

What it draws, and from where:
  * the baked meshes and the palette and ground textures, from assets/build/levels/<Layout>/
    (tools/levels/forest.py build) as the data file lists them;
  * the props, from the data file's `props`, as the forest-kit GLBs;
  * the layout Parts the data file does not hide (water, chests, signs, checkpoints, brambles),
    as boxes in their Expeditions.json looks: what the game keeps visible;
  * stand-ins the game does not place: the raiders at their Normal posts (boxes in each kind's
    colour and size, ProvingGrounds.json crowd.kinds) and a 5-stud player figure.

Cameras: the plan is orthographic from above. A player-eye view is the game's shoulder camera:
the player stands at a point facing a target; the camera sits Combat.json `camera.defaultZoom`
behind his head, `shoulderOffset` to the side and up, with the game's vertical field of view.

Moods: A is the palette under default Roblox lighting (plotscene's calibrated sun, fill and
sky: every look Ben approved was judged under it). B is darker with Atmosphere-style haze: a
dimmer, cooler light and a distance haze laid over the render from a depth pass, the way an
Atmosphere's density and haze colour fade the far forest.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
KIT_DIR = os.path.join(REPO_ROOT, "assets", "kenney3d", "forest-kit", "Models", "GLB format")
DIST_MAX = 900.0  # the distance pass encodes sqrt(distance / DIST_MAX)

# Mood B: a dimmer, cooler light (the forest under its canopy) and the haze laid on afterwards.
# The haze numbers stand for a Roblox Atmosphere of about Density 0.38, Offset 0, Haze 1.6,
# Colour (110, 124, 120): half the light gone at about 220 studs, the far hills a grey-green wall.
MOODS = {
    "A": {"sun": 2.3, "fill": 0.55, "sky": [196, 214, 226], "skyStrength": 0.6, "haze": None},
    "B": {"sun": 1.45, "fill": 0.32, "sky": [128, 142, 140], "skyStrength": 0.42,
          "haze": {"colour": [104, 118, 112], "start": 25.0, "fold": 230.0, "ceiling": 0.86, "sky": 0.55}},
}

KIND_LOOK = {}  # filled from ProvingGrounds.json


def in_blender() -> bool:
    return "--blender" in sys.argv


# ================================================================ the py half


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def paths(layout):
    build = os.path.join(REPO_ROOT, "assets", "build", "levels", layout)
    out = os.path.join(REPO_ROOT, "assets", "testfit", "out", "Levels", layout)
    return build, out


def raider_boxes(layout, config, kinds):
    """The Normal residents at their posts: fire rings round the fire, guards on their points,
    patrols spread along their loop, the ambushers on theirs."""
    boxes = []
    camps = {c["id"]: c for c in layout.get("camps") or []}
    for cfg in config.get("camps") or []:
        camp = camps.get(cfg["id"])
        if camp is None:
            continue
        spots = {s["id"]: s for s in camp.get("spots") or []}
        for group in cfg.get("residents") or []:
            spot = spots.get(group["spot"])
            if spot is None:
                continue
            units = []
            for u in group["units"]:
                if "minDifficulty" in u:
                    continue
                units += [u["kind"]] * u["count"]
            pts = spot["points"]
            n = len(units)
            for k, kind in enumerate(units):
                look = kinds.get(kind, {"radius": 1.3, "height": 5, "color": [200, 80, 60]})
                if spot["posture"] == "fire":
                    a = math.tau * k / max(1, n)
                    px = pts[0]["x"] + math.sin(a) * spot.get("radius", 5)
                    pz = pts[0]["z"] + math.cos(a) * spot.get("radius", 5)
                elif spot["posture"] == "patrol":
                    t = k / max(1, n) * len(pts)
                    i = int(t) % len(pts)
                    j = (i + 1) % len(pts)
                    f = t - int(t)
                    px = pts[i]["x"] + (pts[j]["x"] - pts[i]["x"]) * f
                    pz = pts[i]["z"] + (pts[j]["z"] - pts[i]["z"]) * f
                else:
                    p = pts[k % len(pts)]
                    px, pz = p["x"], p["z"]
                r, h = look["radius"], look["height"]
                boxes.append({"name": f"Raider_{kind}", "pos": [px, camp["y"] + h / 2, pz], "size": [r * 1.5, h, r * 1.0], "color": look["color"], "rotY": 0})
    return boxes


def player_boxes(feet, yaw_deg):
    """A 5-stud blocky player: legs, torso, arms, head, in the game's default blue."""
    x, y, z = feet
    parts = [
        ((-0.5, 1.0, 0.0), (0.95, 2.0, 1.0), [40, 92, 196]),
        ((0.5, 1.0, 0.0), (0.95, 2.0, 1.0), [40, 92, 196]),
        ((0.0, 3.0, 0.0), (2.0, 2.0, 1.0), [52, 110, 220]),
        ((-1.45, 3.0, 0.0), (0.9, 2.0, 0.9), [236, 196, 160]),
        ((1.45, 3.0, 0.0), (0.9, 2.0, 0.9), [236, 196, 160]),
        ((0.0, 4.5, 0.0), (1.0, 1.0, 1.0), [236, 196, 160]),
    ]
    c, s = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    out = []
    for (ox, oy, oz), size, colour in parts:
        out.append({"name": "Player", "pos": [x + ox * c + oz * s, y + oy, z - ox * s + oz * c], "size": list(size), "color": colour, "rotY": yaw_deg})
    return out


def layout_boxes(layout, looks, hide, sign_size):
    """The layout Parts the data file leaves visible, in their looks (sRGB, decoded by plotscene)."""
    hidden_blocks = set(hide.get("blocks", []))
    out = []
    for b in layout["blocks"]:
        if b["name"] in hidden_blocks:
            continue
        look = looks.get(b["look"], {"color": [128, 128, 128]})
        if b["look"] == "water":
            continue  # drawn as a translucent sheet by the Blender half
        out.append({"name": b["name"], "pos": [b["x"], b["y"], b["z"]], "size": [b["sx"], b["sy"], b["sz"]], "color": look["color"], "rotY": 0})
    for s in layout.get("secrets") or []:
        out.append({"name": "Secret_" + s["id"], "pos": [s["x"], s["y"], s["z"]], "size": [s["sx"], s["sy"], s["sz"]], "color": looks["secret"]["color"], "rotY": 0})
        sign = s.get("sign")
        if sign:
            size = sign_size
            out.append({"name": "Sign_" + s["id"], "pos": [sign["x"], sign["y"] + size[1] / 2, sign["z"]], "size": list(size), "color": looks["sign"]["color"], "rotY": 0})
    for c in layout.get("camps") or []:
        cp = c.get("checkpoint")
        if cp:
            out.append({"name": "Checkpoint_" + c["id"], "pos": [cp["x"], c["y"] + 5, cp["z"]], "size": [2, 10, 2], "color": looks["checkpoint"]["color"], "rotY": 0})
    return out


def water_sheets(layout, looks):
    out = []
    for b in layout["blocks"]:
        if b["look"] == "water":
            top = b["y"] + b["sy"] / 2
            out.append({"pos": [b["x"], top - 0.05, b["z"]], "size": [b["sx"], 0.1, b["sz"]], "color": looks["water"]["color"], "alpha": 1.0 - looks["water"].get("transparency", 0.0)})
    return out


def shoulder_camera(feet, target, combat_camera, pitch_deg=-9.0, size=(1600, 900)):
    """The game's camera behind a player standing at `feet` and facing `target`."""
    fx, fy, fz = feet
    dx, dz = target[0] - fx, target[2] - fz
    d = math.hypot(dx, dz) or 1.0
    ux, uz = dx / d, dz / d
    rx, rz = -uz, ux  # right of the facing (Y up, looking along +ux,+uz): (x, z) -> (-z, x)
    off = combat_camera["shoulderOffset"]
    zoom = combat_camera["defaultZoom"]
    head = (fx + rx * off[0], fy + 4.5 + off[1], fz + rz * off[0])
    p = math.radians(pitch_deg)
    look = (ux * math.cos(p), math.sin(p), uz * math.cos(p))
    eye = (head[0] - look[0] * zoom, head[1] - look[1] * zoom, head[2] - look[2] * zoom)
    tgt = (head[0] + look[0] * 60, head[1] + look[1] * 60, head[2] + look[2] * 60)
    vfov = math.radians(combat_camera["fieldOfView"])
    aspect = size[0] / size[1]
    hfov = 2 * math.atan(math.tan(vfov / 2) * aspect)
    lens = 18.0 / math.tan(hfov / 2)  # plotscene's sensor is 36 mm wide, fitted horizontally
    yaw = math.degrees(math.atan2(-ux, -uz))
    return {"eye": list(eye), "target": list(tgt), "lens": lens}, yaw


# The views Ben asked for (brief "Pictures Ben needs"): feet, facing target, moods.
VIEWS = {
    "trailhead": {"feet": (-476, 0, 5), "target": (-430, 6, -22), "moods": "AB", "label": "The trailhead and the new lookout"},
    "lookoutLedge": {"feet": (-450, 26, -31), "target": (-380, 0, 10), "moods": "A", "label": "From the lookout ledge", "pitch": -16},
    "campA": {"feet": (-294, 8, -44), "target": (-225, 8, -18), "moods": "A", "label": "Camp A, the Pickets, from Road5"},
    "mainCamp": {"feet": (-82, 8, -44), "target": (0, 8, 4), "moods": "AB", "label": "The Main Camp from its west gate"},
    "caveMouth": {"feet": (-352, 0, -40), "target": (-334, 8, -62), "moods": "A", "label": "The cave mouth (brambles) from Road4"},
    "pond": {"feet": (-397, 0, 3), "target": (-400, 0, 128), "moods": "A", "label": "The creek, the pond and the island shrine, from the bridge"},
    "shrine": {"feet": (-398, -1, 88), "target": (-400, 0, 128), "moods": "A", "label": "The island shrine from the frozen creek (ice not drawn)", "pitch": -7},
    "gap": {"feet": (-446, 0, 2), "target": (-410, -4, -8), "moods": "A", "label": "The trailhead gap and the lookout's gully"},
    "gatehouse": {"feet": (214, 8, -44), "target": (290, 14, -44), "moods": "A", "label": "The gatehouse from the road"},
    "clearing": {"feet": (304, 12, -6), "target": (313.5, 12, 70), "moods": "AB", "label": "The Chief's Clearing from inside, his hall"},
}


def build_scenes(args):
    layout_cfg = load_json(os.path.join(REPO_ROOT, "src", "shared", "Config", "Levels", "1_ForestRoad.json"))
    layout_name = layout_cfg["layout"]
    layout = load_json(os.path.join(REPO_ROOT, "src", "shared", "Layouts", "Levels", layout_name + ".json"))
    data = load_json(args.data)
    expeditions = load_json(os.path.join(REPO_ROOT, "src", "shared", "Config", "Expeditions.json"))
    looks = dict(expeditions["looks"])
    looks.update(data.get("looks") or {})  # the looks the data file proposes for W2
    combat = load_json(os.path.join(REPO_ROOT, "src", "shared", "Config", "Combat.json"))
    kinds = load_json(os.path.join(REPO_ROOT, "src", "shared", "Config", "ProvingGrounds.json"))["crowd"]["kinds"]
    build_dir, out_dir = paths(layout_name)
    scene_dir = os.path.join(out_dir, "_scenes")
    os.makedirs(scene_dir, exist_ok=True)
    meshes = []
    tex_dir = os.path.join(build_dir, "textures")
    for m in data["meshes"]:
        glb = os.path.join(build_dir, m["name"] + ".glb")
        if m["look"] == "palette":
            image, interp = os.path.join(build_dir, "palette.png"), "Closest"
        else:
            image, interp = os.path.join(tex_dir, data["textures"][m["texture"]]["file"]), "Linear"
            if not os.path.isfile(image):
                image = None
        meshes.append({"glb": glb, "image": image, "interp": interp, "group": m["group"]})
    props = [[p["piece"], p["x"], p["y"], p["z"], p["yaw"], p["scale"]] for p in data["props"]]
    base = {
        "kitDir": KIT_DIR,
        "boxes": layout_boxes(layout, looks, data["hide"], expeditions["sign"]["size"]) + raider_boxes(layout, layout_cfg, kinds),
        "water": water_sheets(layout, looks),
        "meshes": meshes,
        "props": props,
    }
    scenes = []
    wanted = args.views.split(",") if args.views else ["top"] + list(VIEWS)
    for name in wanted:
        if name == "top":
            spec = dict(base)
            xs = [m["min"][0] for m in data["meshes"] if m["group"] == "ground"] + [m["max"][0] for m in data["meshes"] if m["group"] == "ground"]
            zs = [m["min"][2] for m in data["meshes"] if m["group"] == "ground"] + [m["max"][2] for m in data["meshes"] if m["group"] == "ground"]
            cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
            width = max(xs) - min(xs)
            spec.update({"camera": {"ortho": True, "eye": [cx, 900, cz], "target": [cx, 0, cz], "scale": width}, "size": [2400, int(2400 * (max(zs) - min(zs)) / width)],
                         "mood": "A", "out": os.path.join(out_dir, "plan_top.png"), "label": "Forest Road from above (north at the top)"})
            if args.barriers:
                spec = dict(spec)
                spec["boxes"] = spec["boxes"] + [{"name": b["name"], "pos": [b["x"], 160.0, b["z"]], "size": [b["sx"], 1.0, b["sz"]], "color": [235, 40, 40], "rotY": 0} for b in data["barriers"]]
                spec["out"] = os.path.join(out_dir, "plan_barriers.png")
                spec["label"] = "The invisible tree-line walls (red), from above"
            scenes.append(spec)
            continue
        view = VIEWS[name]
        cam, yaw = shoulder_camera(view["feet"], view["target"], combat["camera"], view.get("pitch", -9.0))
        for mood in (args.moods or view["moods"]):
            if mood not in view["moods"] and not args.moods:
                continue
            spec = dict(base)
            spec["boxes"] = base["boxes"] + player_boxes(view["feet"], yaw)
            spec.update({"camera": cam, "size": [1600, 900], "mood": mood, "label": f"{view['label']}  (mood {mood})",
                         "out": os.path.join(out_dir, f"{name}_{mood}.png")})
            scenes.append(spec)
    paths_written = []
    for spec in scenes:
        stem = os.path.splitext(os.path.basename(spec["out"]))[0]
        path = os.path.join(scene_dir, stem + ".json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(spec, fh)
        paths_written.append((path, spec))
    return paths_written


def sheet_scene(args):
    """Every kit piece on a dark forest-floor card, seen from the front: rows by role, the small
    pieces nearest the camera, each in a cell at least 10 studs wide so its label never runs into
    the next one."""
    index = load_json(os.path.join(KIT_DIR, "pieces.json"))["pieces"]
    rows = [("clutter",), ("edge", "rock"), ("under",), ("outside", "tent"), ("tree", "hero", "chief")]
    props, labels = [], []
    z = 0.0
    width = 0.0
    for roles in rows:
        names = sorted((n for n, d in index.items() if d["role"] in roles), key=lambda n: (roles.index(index[n]["role"]), n))
        x = 0.0
        depth = 0.0
        for name in names:
            d = index[name]
            w = d["max"][0] - d["min"][0]
            cell = max(w, 11.0) + 2.0
            px = x + cell / 2 - (d["min"][0] + d["max"][0]) / 2
            pz = z - d["min"][2]  # the piece's front edge on the row's line
            props.append([name, px, 0.0, pz, 0.0, 1.0])
            labels.append({"text": f"{name} {d['triangles']}", "pos": [x + cell / 2, 0.0, z - 1.2]})
            x += cell
            depth = max(depth, d["max"][2] - d["min"][2])
        width = max(width, x)
        z += depth + 7.0
    _, out_dir = paths("ForestRoad")
    spec = {
        "kitDir": KIT_DIR,
        "boxes": [{"name": "Card", "pos": [width / 2, -0.55, z / 2 - 4], "size": [width + 16, 1.0, z + 16], "color": [62, 70, 42], "rotY": 0}],
        "meshes": [], "props": props, "water": [], "labels": labels,
        "camera": {"eye": [width / 2, 95.0, -95.0], "target": [width / 2, 0.0, z * 0.42], "lens": 32.0},
        "size": [2600, 1700], "mood": "A", "out": os.path.join(out_dir, "kit_sheet.png"), "label": "forest-kit: every piece (name, triangles), front view",
    }
    scene_dir = os.path.join(out_dir, "_scenes")
    os.makedirs(scene_dir, exist_ok=True)
    path = os.path.join(scene_dir, "kit_sheet.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(spec, fh)
    return [(path, spec)]


def run_blender(scene_path):
    cmd = [BLENDER, "-b", "--factory-startup", "-P", os.path.abspath(__file__), "--", "--blender", "--scene", scene_path]
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    tail = "\n".join(line for line in proc.stdout.splitlines() if line.startswith("[levelrender]") or "Error" in line or "Traceback" in line)
    if proc.returncode != 0:
        print(proc.stdout[-4000:])
        print(proc.stderr[-4000:])
        raise SystemExit(f"blender failed on {scene_path}")
    print(tail)


def finish(spec):
    """Mood B's haze from the distance pass, then the caption and any labels."""
    from PIL import Image, ImageDraw, ImageFont

    out = spec["out"]
    image = Image.open(out).convert("RGB")
    haze = MOODS[spec["mood"]]["haze"]
    dist_path = out[:-4] + "_dist.png"
    if haze and os.path.isfile(dist_path):
        lut = []
        for level in range(256):
            distance = (level / 255.0) ** 2 * DIST_MAX
            lut.append(int(round(255 * haze["ceiling"] * (1 - math.exp(-max(0.0, distance - haze["start"]) / haze["fold"])))))
        lut[0] = int(round(255 * haze["sky"]))  # the sky takes the haze colour too, part way
        mask = Image.open(dist_path).convert("L").point(lut)
        image = Image.composite(Image.new("RGB", image.size, tuple(haze["colour"])), image, mask)
        os.remove(dist_path)
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype("arial.ttf", 26)
        small = ImageFont.truetype("arial.ttf", 18)
    except OSError:
        font = small = ImageFont.load_default()
    label_path = out[:-4] + "_labels.json"
    if os.path.isfile(label_path):
        for lab in load_json(label_path):
            x, y = lab["px"], lab["py"]
            box = draw.textbbox((x, y), lab["text"], font=small, anchor="mt")
            draw.rectangle((box[0] - 3, box[1] - 2, box[2] + 3, box[3] + 2), fill=(20, 20, 22))
            draw.text((x, y), lab["text"], fill=(235, 235, 235), font=small, anchor="mt")
        os.remove(label_path)
    caption = spec.get("label", "")
    if caption:
        box = draw.textbbox((16, 12), caption, font=font)
        draw.rectangle((box[0] - 8, box[1] - 6, box[2] + 8, box[3] + 6), fill=(18, 20, 22))
        draw.text((16, 12), caption, fill=(240, 240, 236), font=font)
    image.save(out)
    print(f"wrote {out}")


def frustum_planes(cam, size):
    """The four side planes of a shoulder camera (inward normals), as (normal, point)."""
    eye = cam["eye"]
    fwd = [cam["target"][i] - eye[i] for i in range(3)]
    n = math.sqrt(sum(v * v for v in fwd))
    fwd = [v / n for v in fwd]
    right = [fwd[2], 0.0, -fwd[0]]
    rn = math.sqrt(right[0] ** 2 + right[2] ** 2) or 1.0
    right = [right[0] / rn, 0.0, right[2] / rn]
    upv = [right[1] * fwd[2] - right[2] * fwd[1], right[2] * fwd[0] - right[0] * fwd[2], right[0] * fwd[1] - right[1] * fwd[0]]
    if upv[1] < 0:
        upv = [-v for v in upv]
        right = [-v for v in right]
    th = 18.0 / cam["lens"]
    tv = th * size[1] / size[0]
    planes = []
    for side, t in ((right, th), ([-v for v in right], th), (upv, tv), ([-v for v in upv], tv)):
        normal = [fwd[i] * t - side[i] for i in range(3)]
        planes.append((normal, eye))
    planes.append((fwd, [eye[i] + fwd[i] * 0.5 for i in range(3)]))
    return planes


def box_visible(lo, hi, planes):
    for normal, point in planes:
        best = -math.inf
        for x in (lo[0], hi[0]):
            for y in (lo[1], hi[1]):
                for z in (lo[2], hi[2]):
                    best = max(best, sum(normal[i] * ((x, y, z)[i] - point[i]) for i in range(3)))
        if best < 0:
            return False
    return True


def counts(args):
    """What the engine draws from a spot: every MeshPart whose box meets the view (Roblox culls
    per part, so a mesh draws all its triangles or none), plus the props in view."""
    data = load_json(args.data)
    combat = load_json(os.path.join(REPO_ROOT, "src", "shared", "Config", "Combat.json"))
    layout_cfg = load_json(os.path.join(REPO_ROOT, "src", "shared", "Config", "Levels", "1_ForestRoad.json"))
    layout = load_json(os.path.join(REPO_ROOT, "src", "shared", "Layouts", "Levels", layout_cfg["layout"] + ".json"))
    index = load_json(os.path.join(KIT_DIR, "pieces.json"))["pieces"]
    items = [(m["min"], m["max"], m["triangles"]) for m in data["meshes"]]
    for p in data["props"]:
        d = index[p["piece"]]
        r = max(abs(d["min"][0]), abs(d["max"][0]), abs(d["min"][2]), abs(d["max"][2])) * p["scale"]
        items.append(([p["x"] - r, p["y"], p["z"] - r], [p["x"] + r, p["y"] + d["max"][1] * p["scale"], p["z"] + r], d["triangles"]))
    total = sum(t for _, _, t in items)

    near = 250.0  # past this a MeshPart drops to its coarser automatic LODs (not measurable offline)

    def drawn(feet, target, pitch=-9.0, reach=None):
        cam, _yaw = shoulder_camera(feet, target, combat["camera"], pitch)
        planes = frustum_planes(cam, (1600, 900))
        eye = cam["eye"]
        out = 0
        for lo, hi, t in items:
            if not box_visible(lo, hi, planes):
                continue
            if reach is not None:
                d = math.sqrt(sum(max(lo[i] - eye[i], 0.0, eye[i] - hi[i]) ** 2 for i in range(3)))
                if d > reach:
                    continue
            out += t
        return out

    print(f"whole level: {total} triangles, {len(data['meshes'])} baked meshes, {len(data['props'])} props")
    print(f"  {'view':13s} {'in view':>8s} {'within ' + str(int(near)):>11s}")
    for name, view in VIEWS.items():
        pitch = view.get("pitch", -9.0)
        print(f"  {name:13s} {drawn(view['feet'], view['target'], pitch):8d} {drawn(view['feet'], view['target'], pitch, near):11d}")
    route = [(p["x"], p.get("y", 0.0), p["z"]) for p in layout["route"]]
    worst = (0, None)
    for a, b in zip(route, route[1:]):
        length = math.hypot(b[0] - a[0], b[2] - a[2])
        steps = max(1, int(length / 12.0))
        for k in range(steps + 1):
            t = k / steps
            feet = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)
            for ang in range(0, 360, 45):
                target = (feet[0] + 50 * math.cos(math.radians(ang)), feet[1], feet[2] + 50 * math.sin(math.radians(ang)))
                n = drawn(feet, target, reach=near)
                if n > worst[0]:
                    worst = (n, (feet, ang, drawn(feet, target)))
    feet, ang, whole = worst[1]
    print(f"  worst spot on the route (most within {near:.0f}): {worst[0]} within, {whole} in view, at feet ({feet[0]:.0f}, {feet[1]:.0f}, {feet[2]:.0f}) facing {ang} degrees")
    return 0


def main_py():
    parser = argparse.ArgumentParser(description="Render a dressed level.")
    parser.add_argument("--data", default=os.path.join(REPO_ROOT, "tools", "levels", "out", "ForestRoad.dress.json"))
    parser.add_argument("--views", default="")
    parser.add_argument("--moods", default="")
    parser.add_argument("--sheet", action="store_true")
    parser.add_argument("--barriers", action="store_true", help="the plan view with the invisible walls drawn")
    parser.add_argument("--counts", action="store_true", help="triangles drawn from each view and from spots along the route")
    args = parser.parse_args()
    if args.counts:
        return counts(args)
    if args.barriers and not args.views:
        args.views = "top"
    scenes = sheet_scene(args) if args.sheet else build_scenes(args)
    for path, spec in scenes:
        run_blender(path)
        finish(spec)
    return 0


# ================================================================ the Blender half


def main_blender():
    import bpy
    from mathutils import Vector

    sys.path.insert(0, HERE)
    import plotscene  # noqa: E402  (its lights, camera, boxes and render settings)
    import testfit  # noqa: E402

    argv = sys.argv[sys.argv.index("--") + 1:]
    scene_path = argv[argv.index("--scene") + 1]
    spec = load_json(scene_path)
    mood = MOODS[spec.get("mood", "A")]
    plotscene.decode_scene_colours(spec)
    for w in spec.get("water", []):
        w["color"] = plotscene.linear(w["color"])

    testfit.clear_scene()
    scene = bpy.context.scene
    library = bpy.data.collections.new("Library")
    level = bpy.data.collections.new("Level")
    for col in (library, level):
        scene.collection.children.link(col)
    library.hide_render = True
    library.hide_viewport = True

    materials = plotscene.Materials()
    for box in spec.get("boxes", []):
        plotscene.build_box(box, level, materials)
    for w in spec.get("water", []):
        obj = testfit.make_box("Water", (w["size"][0], w["size"][2], w["size"][1]), plotscene.to_blender(w["pos"]),
                               water_material(w["color"], w["alpha"]), level)
        obj.visible_shadow = False

    images = {}

    def image_material(path, interp):
        key = (path, interp)
        mat = images.get(key)
        if mat is not None:
            return mat
        mat = bpy.data.materials.new(f"Img{len(images)}")
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        bsdf.inputs["Roughness"].default_value = 0.95
        bsdf.inputs["Metallic"].default_value = 0.0
        if path and os.path.isfile(path):
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(path)
            tex.interpolation = interp
            tex.extension = "REPEAT"
            mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        else:
            bsdf.inputs["Base Color"].default_value = (0.25, 0.22, 0.16, 1.0)
        images[key] = mat
        return mat

    tris = 0
    for m in spec.get("meshes", []):
        for obj in testfit.import_glb(m["glb"]):
            for child in testfit.all_descendants([obj]):
                for owner in list(child.users_collection):
                    owner.objects.unlink(child)
                level.objects.link(child)
                if child.type == "MESH":
                    child.data.materials.clear()
                    child.data.materials.append(image_material(m["image"], m["interp"]))
                    tris += sum(len(p.vertices) - 2 for p in child.data.polygons)

    cache = {}

    def piece_objects(name):
        objs = cache.get(name)
        if objs is None:
            roots = testfit.import_glb(os.path.join(spec["kitDir"], name + ".glb"))
            objs = [o for o in testfit.all_descendants(roots) if o.type == "MESH"]
            for o in testfit.all_descendants(roots):
                for owner in list(o.users_collection):
                    owner.objects.unlink(o)
                library.objects.link(o)
                if o.type == "MESH":
                    for slot in o.material_slots:
                        if slot.material and slot.material.use_nodes:
                            bsdf = slot.material.node_tree.nodes.get("Principled BSDF")
                            if bsdf:
                                bsdf.inputs["Metallic"].default_value = 0.0
                                bsdf.inputs["Roughness"].default_value = 0.95
            cache[name] = objs
        return objs

    for k, (name, x, y, z, yaw, scale) in enumerate(spec.get("props", [])):
        holder = bpy.data.objects.new(f"P{k}_{name}", None)
        holder.location = plotscene.to_blender((x, y, z))
        holder.rotation_euler = (0.0, 0.0, math.radians(yaw))
        holder.scale = (scale, scale, scale)
        level.objects.link(holder)
        for src in piece_objects(name):
            obj = bpy.data.objects.new(f"{holder.name}_m", src.data)
            obj.matrix_world = src.matrix_world.copy()
            obj.parent = holder
            obj.matrix_parent_inverse.identity()
            obj.matrix_basis = src.matrix_world.copy()
            level.objects.link(obj)
            tris += sum(len(p.vertices) - 2 for p in src.data.polygons)

    plotscene.setup_lights(scene, mood["sky"])
    for obj in scene.collection.objects:
        if obj.type == "LIGHT":
            obj.data.energy = mood["sun"] if obj.name == "Sun" else mood["fill"]
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs["Strength"].default_value = mood["skyStrength"]
    cam_spec = spec["camera"]
    if cam_spec.get("ortho"):
        data = bpy.data.cameras.new("Camera")
        data.type = "ORTHO"
        data.ortho_scale = cam_spec["scale"]
        cam = bpy.data.objects.new("Camera", data)
        scene.collection.objects.link(cam)
        scene.camera = cam
        cam.location = plotscene.to_blender(cam_spec["eye"])
        cam.rotation_euler = (0.0, 0.0, 0.0)
        data.clip_start = 1.0
        data.clip_end = 3000.0
    else:
        plotscene.setup_camera(scene, cam_spec)
        scene.camera.data.clip_end = 4000.0
    bpy.context.view_layer.update()
    print(f"[levelrender] {len(spec.get('boxes', []))} boxes, {len(spec.get('meshes', []))} meshes, {len(spec.get('props', []))} props, {tris} triangles loaded", flush=True)
    plotscene.render(scene, spec["out"], spec.get("size", [1600, 900]))

    labels = spec.get("labels")
    if labels:
        from bpy_extras.object_utils import world_to_camera_view

        w, h = spec["size"]
        out = []
        for lab in labels:
            co = world_to_camera_view(scene, scene.camera, Vector(plotscene.to_blender(lab["pos"])))
            out.append({"text": lab["text"], "px": co.x * w, "py": (1.0 - co.y) * h})
        with open(spec["out"][:-4] + "_labels.json", "w", encoding="utf-8") as fh:
            json.dump(out, fh)

    if mood["haze"]:
        distance_pass(scene, spec["out"][:-4] + "_dist.png")
    print(f"[levelrender] wrote {spec['out']}", flush=True)


def water_material(colour, alpha):
    import bpy

    mat = bpy.data.materials.new("Water")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (colour[0] / 255.0, colour[1] / 255.0, colour[2] / 255.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6  # Roblox's SmoothPlastic water shows no sun-spot
    bsdf.inputs["Alpha"].default_value = alpha
    mat.surface_render_method = "BLENDED"
    return mat


def distance_pass(scene, path):
    """Every surface emits sqrt(distance / DIST_MAX) on a black world: the haze's mask."""
    import bpy

    mat = bpy.data.materials.new("Distance")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    for n in list(nodes):
        nodes.remove(n)
    cam = nodes.new("ShaderNodeCameraData")
    div = nodes.new("ShaderNodeMath")
    div.operation = "DIVIDE"
    div.inputs[1].default_value = DIST_MAX
    root = nodes.new("ShaderNodeMath")
    root.operation = "SQRT"
    emit = nodes.new("ShaderNodeEmission")
    out = nodes.new("ShaderNodeOutputMaterial")
    links.new(cam.outputs["View Distance"], div.inputs[0])
    links.new(div.outputs[0], root.inputs[0])
    links.new(root.outputs[0], emit.inputs["Strength"])
    emit.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    links.new(emit.outputs[0], out.inputs["Surface"])
    world = bpy.data.worlds.new("Black")
    world.use_nodes = True
    world.node_tree.nodes.get("Background").inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    scene.world = world
    layer = bpy.context.view_layer
    layer.material_override = mat
    scene.view_settings.view_transform = "Raw"
    scene.render.image_settings.color_mode = "BW"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    layer.material_override = None


if __name__ == "__main__":
    if in_blender():
        main_blender()
    else:
        sys.exit(main_py())
