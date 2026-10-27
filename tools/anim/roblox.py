"""The Studio test of one animated character: `py tools/anim/animate.py studio <name> [--upload]`.

Reads assets/anim/<name>/ (a finished `build`), uploads <name>_rig.glb as a Model through Open Cloud
when asked, and writes assets/anim/_studio/AnimTestData.luau: the asset id, the height to stand at
(the role's crowd kind `height`) and every slot's clip as per-frame Bone.Transform values. Then
`rojo build animtest.project.json -o build/animtest.rbxl` makes the hub with the character standing
in front of the spawn (tools/anim/studio/).

Why Bone.Transform and not Animation assets: an Animation id needs Studio's Animation Editor and a
publish per clip, while bones driven from data need nothing past the model upload. A Bone's Transform
is applied after its rest CFrame in its own frame, so each value is the glTF delta rest^-1 * pose of
that joint's local transform: true whatever turn or offset the importer gives the joint's parent.
Transform does not replicate, so a client script plays it.
"""

import hashlib
import json
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
STUDIO_DATA = os.path.join(ROOT, "assets", "anim", "_studio")
ROLES = os.path.join(ROOT, "tools", "anim", "roles.json")
COMBAT = os.path.join(ROOT, "src", "shared", "Config", "ProvingGrounds.json")
# A deviation below this is rounding: the bone is left out of the clip (or its translation is).
STILL = 1e-4
DIGITS = 4


def read_glb(path):
    data = open(path, "rb").read()
    json_len = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + json_len])
    rest = data[20 + json_len:]
    bin_chunk = rest[8:8 + struct.unpack_from("<I", rest, 0)[0]] if rest else b""
    return doc, bin_chunk


def accessor(doc, binary, index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[acc["type"]]
    if acc["componentType"] != 5126:
        raise SystemExit(f"accessor {index}: only float animation data is read")
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride", 4 * width)
    return [struct.unpack_from(f"<{width}f", binary, start + i * stride) for i in range(acc["count"])]


def q_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def q_conj(q):
    return (-q[0], -q[1], -q[2], q[3])


def q_rotate(q, v):
    x, y, z, _ = q_mul(q_mul(q, (v[0], v[1], v[2], 0.0)), q_conj(q))
    return (x, y, z)


def q_norm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def sample(times, values, t, step, is_rot):
    if t <= times[0] or len(times) == 1:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    hi = next(i for i, x in enumerate(times) if x >= t)
    lo = hi - 1
    if step:
        return values[lo]
    a = (t - times[lo]) / (times[hi] - times[lo])
    p, q = values[lo], values[hi]
    if is_rot:
        if sum(x * y for x, y in zip(p, q)) < 0:
            q = tuple(-c for c in q)
        return q_norm(tuple(x + (y - x) * a for x, y in zip(p, q)))
    return tuple(x + (y - x) * a for x, y in zip(p, q))


def rest_pose(rig_path):
    doc, _ = read_glb(rig_path)
    joints = {doc["nodes"][i]["name"] for i in doc["skins"][0]["joints"]}
    rest = {}
    for node in doc["nodes"]:
        if node.get("name") in joints:
            rest[node["name"]] = (tuple(node.get("translation", (0, 0, 0))), tuple(node.get("rotation", (0, 0, 0, 1))))
    return rest


def clip_frames(doc, binary, anim, rest, fps, frames):
    """Per joint: rotation deltas (x, y, z, w per frame) and, if it moves, translation deltas."""
    channels = {}
    for ch in anim["channels"]:
        node = doc["nodes"][ch["target"]["node"]].get("name")
        if node in rest and ch["target"]["path"] in ("rotation", "translation"):
            s = anim["samplers"][ch["sampler"]]
            times = [v[0] for v in accessor(doc, binary, s["input"])]
            channels[(node, ch["target"]["path"])] = (times, accessor(doc, binary, s["output"]),
                                                      s.get("interpolation") == "STEP")
    start = min((c[0][0] for c in channels.values()), default=0.0)
    bones = {}
    for name, (t_rest, q_rest) in rest.items():
        inv = q_conj(q_rest)
        rot, pos, moves = [], [], False
        for i in range(frames):
            t = start + i / fps
            q = q_rest
            if (name, "rotation") in channels:
                times, values, step = channels[(name, "rotation")]
                q = sample(times, values, t, step, True)
            p = t_rest
            if (name, "translation") in channels:
                times, values, step = channels[(name, "translation")]
                p = sample(times, values, t, step, False)
            d = q_norm(q_mul(inv, q))
            if d[3] < 0:
                d = tuple(-c for c in d)
            rot.extend(d)
            off = q_rotate(inv, tuple(a - b for a, b in zip(p, t_rest)))
            pos.extend(off)
            moves = moves or max(abs(c) for c in off) > STILL
        if moves or any(abs(rot[i]) > STILL for i in range(len(rot)) if i % 4 != 3):
            bones[name] = {"r": rot, **({"t": pos} if moves else {})}
    return bones


def luau_value(v, indent=""):
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "nil"
    if isinstance(v, (int, float)):
        r = round(float(v), DIGITS)
        s = f"{r:.{DIGITS}f}".rstrip("0").rstrip(".")
        return "0" if s in ("-0", "") else s
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        if all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v):
            return "{" + ",".join(luau_value(x) for x in v) + "}"
        inner = indent + "\t"
        return "{\n" + "".join(f"{inner}{luau_value(x, inner)},\n" for x in v) + indent + "}"
    if isinstance(v, dict):
        inner = indent + "\t"
        parts = []
        for k, x in v.items():
            key = k if k.isidentifier() else f"[{json.dumps(k)}]"
            parts.append(f"{inner}{key} = {luau_value(x, inner)},\n")
        return "{\n" + "".join(parts) + indent + "}"
    raise TypeError(type(v))


def upload(rig, name, record_path):
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    sys.path.insert(0, os.path.join(ROOT, "tools", "assets"))
    from upload_audio import load_env, require_credentials
    from upload_models import model_display_name, upload_glb

    digest = hashlib.sha256(open(rig, "rb").read()).hexdigest()
    record = json.load(open(record_path, encoding="utf-8")) if os.path.exists(record_path) else {}
    if record.get("sha256") == digest and record.get("assetId"):
        print(f"[studio] {os.path.basename(rig)} unchanged since its upload: asset {record['assetId']}")
        return record["assetId"]
    creds = require_credentials(load_env())
    print(f"[studio] uploading {os.path.basename(rig)} ...", flush=True)
    asset_id = upload_glb(rig, model_display_name(f"Anim_{name}"), f"Animated rig test: {name}", creds)
    json.dump({"assetId": asset_id, "sha256": digest}, open(record_path, "w", encoding="utf-8"), indent=1)
    print(f"[studio] uploaded: asset {asset_id}")
    return asset_id


def studio(args):
    folder = os.path.join(ROOT, "assets", "anim", args.name)
    report_path = os.path.join(folder, "report.json")
    if not os.path.exists(report_path):
        sys.exit(f"no build at {folder}: run `animate.py build` first")
    report = json.load(open(report_path, encoding="utf-8"))
    rig = os.path.join(folder, f"{args.name}_rig.glb")
    record_path = os.path.join(folder, "upload.json")
    if args.upload:
        asset_id = upload(rig, args.name, record_path)
    elif os.path.exists(record_path):
        asset_id = json.load(open(record_path, encoding="utf-8"))["assetId"]
    else:
        sys.exit("the rig was never uploaded: add --upload")

    height = args.height
    if height is None and report.get("role"):
        kind = json.load(open(ROLES, encoding="utf-8"))["roles"][report["role"]]["kind"]
        height = json.load(open(COMBAT, encoding="utf-8"))["crowd"]["kinds"][kind]["height"]
    height = height or 6.0

    rest = rest_pose(rig)
    doc, binary = read_glb(os.path.join(folder, f"{args.name}_all.glb"))
    anims = {a["name"]: a for a in doc.get("animations", [])}
    clips = []
    for row in report["clips"]:
        if row["slot"] not in anims:
            sys.exit(f"{args.name}_all.glb has no animation {row['slot']}: rebuild with the current animate.py")
        clips.append({"slot": row["slot"], "clip": row["clip"], "fps": report["fps"], "frames": row["frames"],
                      "loop": row["loop"], "windup": row.get("windup"),
                      "bones": clip_frames(doc, binary, anims[row["slot"]], rest, report["fps"], row["frames"])})
    data = {"name": args.name, "assetId": asset_id, "height": height, "clips": clips}
    os.makedirs(STUDIO_DATA, exist_ok=True)
    out = os.path.join(STUDIO_DATA, "AnimTestData.luau")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(f"--!strict\n-- Generated by `py tools/anim/animate.py studio {args.name}`; never edit by hand.\n")
        fh.write("return " + luau_value(data) + "\n")
    print(f"[studio] {len(clips)} clips, {height} studs tall, asset {asset_id} -> {out}")
    print("[studio] next: rojo build animtest.project.json -o build/animtest.rbxl")
