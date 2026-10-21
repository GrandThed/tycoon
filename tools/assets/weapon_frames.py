#!/usr/bin/env python
"""Write src/shared/Config/WeaponModels.json from the weapon kit's frame files, and prove that a
point of the generator's frame is the same point of the template (docs/prompts/l3-w2-contract.md
L3-46 and L3-47).

    py tools/assets/weapon_frames.py                      # (re)write src/shared/Config/WeaponModels.json
    py tools/assets/weapon_frames.py --check              # regenerate in memory, diff, run the turn proof
    py tools/assets/weapon_frames.py --check --require-harvest   # after the paste: all 15 must be proven

The client hangs a weapon by its `grip`, holsters it by its `holster` and draws shots from its `tip`
(L3-51, L3-52), and the Armory stage frames it by its `bounds` (L3-56). Those points come from this
config, never from a mesh: the generators (tools/assets/weapon_kit_*.py) write one
`assets/kenney3d/weapon-kit/Models/GLB format/<Model>.frame.json` per weapon, and this script copies
every point of each into one committed file, one family per ProvingGrounds.json `weapons` entry.

It refuses to write anything when a weapons family has no frame file; a model breaks the name rule
(the family id with its first letter capitalised: frostHammer -> FrostHammer, smg -> Smg); `grip` is
not the origin; `tip` or `holster` is missing; a point lies outside `bounds` by more than 0.01; a
blueprint is not one piece at pos [0, 0, 0], rotY 0, scale 1; or a merge sidecar exists and its
bounds differ from the frame file's by more than 0.002 or its triangles differ.

The turn proof (L3-47). The template of a weapon must have the generator's frame, with its pivot
(`Base`) on the grip, or every point above lands somewhere else in the hand. The chain is: the glTF
import turns the model 180 deg about Y; Roblox centres the mesh on its bounding box; the harvest
records that centre from the glTF origin as `offset`; gen_templates.py puts the MeshPart back with
`template_placement(offset)`. The proof sends points through that same chain, through the very
function the templates are written with, and they must come back to themselves within 0.01:
  - always, on real Studio data: tools/assets/fixtures/turn_proof.json (props whose merge sidecar
    and harvested offset are both known), every corner of each one's bounds; plus a guard that an
    import with no turn, or a placement that does not undo it, FAILS the same proof, so it can never
    pass by construction;
  - on every weapon whose stage 0 is harvested in Assets.json (or --assets-json): every point of
    WeaponModels.json goes through it, plus harvested size = config size within 0.01. The chain is a
    rigid move, so a weapon's points pass or fail together: per weapon this is one check of the
    harvested offset and one of the size. Where a point sits on the mesh (a `tip` at the right end)
    is vouched for by the generator and the sidecar bounds check, not by this proof.

--check on a checkout without the frame files (assets/ is gitignored) checks the committed file's
shape and families against ProvingGrounds.json, says "frame files absent: shape checked only", and
still runs the turn proof.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "testfit"))
import assets_config as cfg  # noqa: E402
from blueprint import BlueprintError, load_blueprint  # noqa: E402
from gen_templates import IDENTITY, template_placement  # noqa: E402

CONFIG_DIR = os.path.join(cfg.REPO_ROOT, "src", "shared", "Config")
OUT_PATH = os.path.join(CONFIG_DIR, "WeaponModels.json")
PROVING_PATH = os.path.join(CONFIG_DIR, "ProvingGrounds.json")
KIT = "weapon-kit"
FOLDER = "Weapons"
FRAMES_DIR = os.path.join(cfg.REPO_ROOT, "assets", "kenney3d", KIT, "Models", "GLB format")
BLUEPRINTS_DIR = os.path.join(cfg.REPO_ROOT, "tools", "testfit", "blueprints", "_props", FOLDER)
TURN_FIXTURE = os.path.join(HERE, "fixtures", "turn_proof.json")
VERSION = 1
REQUIRED_POINTS = ("grip", "tip", "holster")
# A model name is an Instance name, a file stem and part of an Open Cloud display name.
MODEL_NAME = re.compile(r"^[A-Z][A-Za-z0-9]*$")
# src/shared/WeaponLook.luau's BOUNDS_SLACK is this number on the reading side: change the two
# together, or one writes what the other warns of.
POINT_SLACK = 0.01
SIDECAR_SLACK = 0.002
PROOF_SLACK = 0.01
DECIMALS = 4


def log(msg: str) -> None:
    print(f"[weapon-frames] {msg}", flush=True)


def rel(path: str) -> str:
    try:
        return os.path.relpath(path, cfg.REPO_ROOT).replace("\\", "/")
    except ValueError:  # another drive has no relative form
        return path


def model_name(family: str) -> str:
    return family[:1].upper() + family[1:]


def finite_vector(value: object) -> list[float] | None:
    if not isinstance(value, list) or len(value) != 3:
        return None
    out = []
    for v in value:
        if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):
            return None
        out.append(float(v))
    return out


def clean(v: float) -> float:
    v = round(float(v), DECIMALS)
    return 0.0 if v == 0 else v  # never "-0.0"


def read_json(path: str) -> object:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def load_weapons() -> dict:
    data = read_json(PROVING_PATH)
    weapons = data.get("weapons") if isinstance(data, dict) else None
    if not isinstance(weapons, dict) or not weapons:
        raise SystemExit(f"[weapon-frames] {rel(PROVING_PATH)} has no `weapons` table")
    return weapons


def frames_present(frames_dir: str) -> bool:
    return os.path.isdir(frames_dir) and any(n.endswith(".frame.json") for n in os.listdir(frames_dir))


# ---------------------------------------------------------------- one entry's rules


def entry_problems(family: str, entry: object) -> list[str]:
    """The rules a committed entry must keep (the shape the client's WeaponLook.Def accepts, plus
    the grip on the origin and every point inside its bounds)."""
    if not isinstance(entry, dict):
        return [f"{family}: entry is not an object"]
    problems = []
    if entry.get("model") != model_name(family):
        problems.append(f"{family}: model {entry.get('model')!r} is not {model_name(family)!r} (the family id, first letter capitalised)")
    elif not MODEL_NAME.match(entry["model"]):
        problems.append(f"{family}: model {entry['model']!r} is not a plain name ([A-Z][A-Za-z0-9]*)")
    points = entry.get("points")
    bounds = entry.get("bounds")
    if not isinstance(points, dict):
        return problems + [f"{family}: no points table"]
    lo = finite_vector(bounds.get("min")) if isinstance(bounds, dict) else None
    hi = finite_vector(bounds.get("max")) if isinstance(bounds, dict) else None
    if lo is None or hi is None:
        problems.append(f"{family}: bounds need min and max, three finite numbers each")
    elif any(lo[i] > hi[i] for i in range(3)):
        problems.append(f"{family}: bounds min {lo} exceeds max {hi}")
    for name in REQUIRED_POINTS:
        if name not in points:
            problems.append(f"{family}: no `{name}` point")
    for name in sorted(points):
        p = finite_vector(points[name])
        if p is None:
            problems.append(f"{family}: point {name} is not three finite numbers: {points[name]!r}")
            continue
        if name == "grip" and any(v != 0 for v in p):
            problems.append(f"{family}: grip {p} is not [0, 0, 0] (the template's pivot is the grip)")
        if lo is not None and hi is not None:
            out = max(max(lo[i] - p[i], p[i] - hi[i]) for i in range(3))
            if out > POINT_SLACK:
                problems.append(f"{family}: point {name} {p} lies {out:.3f} outside its bounds")
    return problems


def blueprint_problems(model: str, path: str) -> list[str]:
    """L3-47's precondition: one piece of this model at the origin, unturned, at scale 1, so the
    blueprint's frame is the generator's frame."""
    if not os.path.isfile(path):
        return [f"{model}: no blueprint {rel(path)}"]
    try:
        bp = load_blueprint(path)
    except BlueprintError as exc:
        return [f"{model}: blueprint {rel(path)}: {exc}"]
    problems = []
    if bp.id != model:
        problems.append(f"{model}: blueprint id is {bp.id!r}")
    if bp.scale != 1.0:
        problems.append(f"{model}: blueprint scale is {bp.scale}, not 1")
    if len(bp.pieces) != 1:
        return problems + [f"{model}: blueprint has {len(bp.pieces)} pieces, not 1"]
    piece = bp.pieces[0]
    if piece.kit != KIT or piece.model != model:
        problems.append(f"{model}: blueprint piece is {piece.kit}/{piece.model}, not {KIT}/{model}")
    if any(v != 0 for v in piece.pos) or piece.rot_y != 0 or piece.stage != 0 or piece.until is not None:
        problems.append(f"{model}: blueprint piece is at pos {list(piece.pos)} rotY {piece.rot_y} stage {piece.stage}, not the origin, unturned, stage 0 for good")
    return problems


def sidecar_problems(model: str, frame_bounds: tuple[list[float], list[float]], triangles: object, build_root: str | None) -> list[str]:
    """A merged GLB must be the geometry the frame file describes: same bounds (to the merge's
    rounding), same triangle count. Absent sidecars are fine (nothing merged on this machine)."""
    sidecar = cfg.load_sidecar(FOLDER, model, props=True, build_root=build_root)
    if sidecar is None:
        return []
    stages = sidecar.get("stages") or []
    if len(stages) != 1:
        return [f"{model}: merge sidecar has {len(stages)} stages, not 1"]
    stage = stages[0]
    lo, hi = finite_vector(stage.get("min")), finite_vector(stage.get("max"))
    if lo is None or hi is None:
        return [f"{model}: merge sidecar has no bounds"]
    problems = []
    gap = max(abs(a - b) for a, b in zip(lo + hi, frame_bounds[0] + frame_bounds[1]))
    if gap > SIDECAR_SLACK:
        problems.append(f"{model}: merged bounds {lo}..{hi} differ from the frame file's {frame_bounds[0]}..{frame_bounds[1]} by {gap:.4f} (re-merge, or regenerate the kit)")
    kits = stage.get("kits") or {}
    if sorted(kits) != [KIT]:
        problems.append(f"{model}: merge sidecar kits are {sorted(kits)}, not [{KIT!r}]")
    merged_triangles = sum(int((k or {}).get("triangles", 0)) for k in kits.values())
    if merged_triangles != triangles:
        problems.append(f"{model}: merged triangles {merged_triangles} differ from the frame file's {triangles}")
    return problems


# ---------------------------------------------------------------- build and render


def build(weapons: dict, frames_dir: str, blueprints_dir: str, build_root: str | None) -> tuple[dict | None, list[str]]:
    problems: list[str] = []
    families: dict = {}
    for family in sorted(weapons):
        model = model_name(family)
        if not MODEL_NAME.match(model):
            problems.append(f"{family}: {model!r} is not a plain model name ([A-Z][A-Za-z0-9]*)")
            continue
        path = os.path.join(frames_dir, f"{model}.frame.json")
        if not os.path.isfile(path):
            problems.append(f"{family}: no frame file {rel(path)}")
            continue
        frame = read_json(path)
        if not isinstance(frame, dict):
            problems.append(f"{family}: {rel(path)} is not an object")
            continue
        if frame.get("model") != model:
            problems.append(f"{family}: {rel(path)} names model {frame.get('model')!r}, not {model!r}")
        raw_points = frame.get("frame")
        raw_bounds = frame.get("bounds")
        if not isinstance(raw_points, dict) or not isinstance(raw_bounds, dict):
            problems.append(f"{family}: {rel(path)} needs `frame` and `bounds` objects")
            continue
        points = {}
        for name in sorted(raw_points):
            p = finite_vector(raw_points[name])
            points[name] = [clean(v) for v in p] if p is not None else raw_points[name]
        lo, hi = finite_vector(raw_bounds.get("min")), finite_vector(raw_bounds.get("max"))
        entry = {
            "model": model,
            "points": points,
            "bounds": {
                "min": [clean(v) for v in lo] if lo else raw_bounds.get("min"),
                "max": [clean(v) for v in hi] if hi else raw_bounds.get("max"),
            },
        }
        found = entry_problems(family, entry)
        problems += found
        problems += blueprint_problems(model, os.path.join(blueprints_dir, f"{model}.json"))
        if lo is not None and hi is not None:
            problems += sidecar_problems(model, (lo, hi), frame.get("triangles"), build_root)
        families[family] = entry
    wanted = {model_name(f) + ".json" for f in weapons}
    if os.path.isdir(blueprints_dir):
        for name in sorted(os.listdir(blueprints_dir)):
            if name.endswith(".json") and name not in wanted:
                problems.append(f"blueprint {rel(os.path.join(blueprints_dir, name))} is no weapons family (the folder holds the {len(weapons)} exactly; the upload would send it)")
    if problems:
        return None, problems
    return {"version": VERSION, "folder": FOLDER, "families": families}, []


def vec(values) -> str:
    return "[" + ", ".join(json.dumps(clean(v)) for v in values) + "]"


def render(doc: dict) -> str:
    """Two-space indent, every list of numbers on one line, families and points sorted, LF."""
    lines = ["{", f'  "version": {int(doc["version"])},', f'  "folder": {json.dumps(doc["folder"])},', '  "families": {']
    families = sorted(doc["families"])
    for i, family in enumerate(families):
        entry = doc["families"][family]
        lines.append(f"    {json.dumps(family)}: {{")
        lines.append(f'      "model": {json.dumps(entry["model"])},')
        lines.append('      "points": {')
        names = sorted(entry["points"])
        for j, name in enumerate(names):
            lines.append(f"        {json.dumps(name)}: {vec(entry['points'][name])}{',' if j < len(names) - 1 else ''}")
        lines.append("      },")
        bounds = entry["bounds"]
        lines.append(f'      "bounds": {{ "min": {vec(bounds["min"])}, "max": {vec(bounds["max"])} }}')
        lines.append("    }" + ("," if i < len(families) - 1 else ""))
    lines += ["  }", "}"]
    text = "\n".join(lines) + "\n"
    if json.loads(text) != doc:
        raise AssertionError("render does not round-trip")  # never write what does not read back
    return text


def shape_problems(doc: object, weapons: dict) -> list[str]:
    """The committed file on its own: what a checkout without the frame files can still prove."""
    if not isinstance(doc, dict):
        return ["WeaponModels.json is not an object"]
    problems = []
    if doc.get("version") != VERSION:
        problems.append(f"version is {doc.get('version')!r}, not {VERSION}")
    if doc.get("folder") != FOLDER:
        problems.append(f"folder is {doc.get('folder')!r}, not {FOLDER!r}")
    families = doc.get("families")
    if not isinstance(families, dict):
        return problems + ["no families table"]
    for family in sorted(set(weapons) - set(families)):
        problems.append(f"{family}: a weapons family with no entry")
    for family in sorted(set(families) - set(weapons)):
        problems.append(f"{family}: an entry that names no weapons family")
    for family in sorted(families):
        problems += entry_problems(family, families[family])
    return problems


# ---------------------------------------------------------------- the turn proof (L3-47)


def imported_local(p, centre) -> tuple[float, float, float]:
    """Where a generator-frame point sits in the imported MeshPart's own frame: the importer turns
    the model 180 deg about Y at the glTF origin, and Roblox centres the mesh on its bounding box,
    whose centre the import turned too."""
    turned_p = (-p[0], p[1], -p[2])
    turned_c = (-centre[0], centre[1], -centre[2])
    return (turned_p[0] - turned_c[0], turned_p[1] - turned_c[1], turned_p[2] - turned_c[2])


def apply(rotation, v) -> tuple[float, float, float]:
    return tuple(sum(rotation[row][col] * v[col] for col in range(3)) for row in range(3))


def prove(label: str, points: dict, centre, size, harvested_offset, harvested_size, placement=template_placement) -> list[str]:
    """Every point, through the import, the harvested offset and the template placement, must come
    back to itself; and the harvested size must be the merged one (the turn keeps each axis)."""
    problems = []
    position, rotation = placement(harvested_offset)
    for name in sorted(points):
        p = points[name]
        local = imported_local(p, centre)
        turned = apply(rotation, local)
        back = (position[0] + turned[0], position[1] + turned[1], position[2] + turned[2])
        miss = max(abs(back[i] - p[i]) for i in range(3))
        if miss > PROOF_SLACK:
            problems.append(f"{label}: point {name} {list(p)} comes back at {[round(v, 4) for v in back]} ({miss:.4f} off)")
    gap = max(abs(float(harvested_size[i]) - float(size[i])) for i in range(3))
    if gap > PROOF_SLACK:
        problems.append(f"{label}: harvested size {list(harvested_size)} is not the merged size {list(size)} ({gap:.4f} off)")
    return problems


def corners(centre, size) -> dict:
    out = {}
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                key = f"corner{'+' if sx > 0 else '-'}{'+' if sy > 0 else '-'}{'+' if sz > 0 else '-'}"
                out[key] = (centre[0] + sx * size[0] / 2, centre[1] + sy * size[1] / 2, centre[2] + sz * size[2] / 2)
    return out


def unturned_placement(offset, lift: float = 0.0):
    """A placement that forgets the importer's turn: the guard's mutant."""
    return (float(offset[0]), float(offset[1]) + lift, float(offset[2])), IDENTITY


def fixture_proof(path: str) -> tuple[list[str], list[str]]:
    """(problems, notes) for the committed real-data fixture, and the guard that the proof can fail."""
    if not os.path.isfile(path):
        return [f"turn proof fixture {rel(path)} is missing"], []
    data = read_json(path)
    records = data.get("records") if isinstance(data, dict) else None
    if not isinstance(records, list) or not records:
        return [f"turn proof fixture {rel(path)} has no records"], []
    problems: list[str] = []
    guard_failures = {"unturned import": 0, "unturned placement": 0}
    count = 0
    for rec in records:
        label = f"fixture {rec.get('era')}/{rec.get('model')}"
        sidecar, harvested = rec.get("sidecar") or {}, rec.get("harvested") or {}
        centre, size = finite_vector(sidecar.get("centre")), finite_vector(sidecar.get("size"))
        offset, hsize = finite_vector(harvested.get("offset")), finite_vector(harvested.get("size"))
        if None in (centre, size, offset, hsize):
            problems.append(f"{label}: needs sidecar centre/size and harvested offset/size, three numbers each")
            continue
        points = corners(centre, size)
        count += len(points)
        problems += prove(label, points, centre, size, offset, hsize)
        # Had the importer not turned the model, Studio would have reported the centre itself.
        if prove(label, points, centre, size, centre, hsize):
            guard_failures["unturned import"] += 1
        if prove(label, points, centre, size, offset, hsize, unturned_placement):
            guard_failures["unturned placement"] += 1
    for what, failed in guard_failures.items():
        if failed == 0:
            problems.append(f"turn proof guard: an {what} passes the proof on every fixture record, so the proof could not catch it (add a record off the axes)")
    notes = [f"fixture: {len(records)} record(s), {count} corner(s) come back; an unturned import fails {guard_failures['unturned import']} of {len(records)}, an unturned placement {guard_failures['unturned placement']} of {len(records)}"]
    return problems, notes


def weapon_proof(doc: dict, assets: dict, require_harvest: bool) -> tuple[list[str], list[str]]:
    """Every point of every harvested weapon, against its real harvested offset and size."""
    problems: list[str] = []
    props = (assets.get(cfg.PROPS_KEY) or {}).get(doc["folder"]) or {}
    proven, waiting = [], []
    count = 0
    for family in sorted(doc["families"]):
        entry = doc["families"][family]
        model = entry["model"]
        stages = (props.get(model) or {}).get("stages") or []
        stage = stages[0] if stages else None
        if stage is None or not cfg.stage_harvested(stage):
            waiting.append(model)
            continue
        label = f"{doc['folder']}/{model}"
        parts = stage.get("parts") or []
        if len(stages) != 1 or len(parts) != 1 or parts[0].get("kit") != KIT:
            problems.append(f"{label}: harvested as {len(stages)} stage(s) with parts {[p.get('kit') for p in parts]}, not one {KIT} MeshPart in one stage")
            continue
        lo, hi = entry["bounds"]["min"], entry["bounds"]["max"]
        centre = [(lo[i] + hi[i]) / 2 for i in range(3)]
        size = [hi[i] - lo[i] for i in range(3)]
        offset, hsize = finite_vector(parts[0].get("offset")), finite_vector(parts[0].get("size"))
        if offset is None or hsize is None:
            problems.append(f"{label}: harvested offset or size is not three numbers")
            continue
        found = prove(label, entry["points"], centre, size, offset, hsize)
        problems += found
        if not found:
            proven.append(model)
            count += len(entry["points"])
    total = len(doc["families"])
    notes = [
        f"weapons ({rel(cfg.ASSETS_PATH)}): {len(proven)} of {total} harvested and proven"
        f" (per weapon one offset check and one size check; that offset carries their {count} point(s))"
    ]
    if waiting:
        notes.append(f"not harvested yet ({len(waiting)}): {', '.join(waiting)}")
        if require_harvest:
            problems.append(f"--require-harvest: {len(waiting)} of {total} weapon(s) are not harvested: {', '.join(waiting)}")
    return problems, notes


# ---------------------------------------------------------------- main


def check(args, weapons: dict) -> int:
    problems: list[str] = []
    notes: list[str] = []
    out_path = os.path.abspath(args.out) if args.out else OUT_PATH
    committed_text = None
    if os.path.isfile(out_path):
        with open(out_path, "r", encoding="utf-8", newline="") as fh:
            committed_text = fh.read()
    if committed_text is None:
        problems.append(f"{rel(out_path)} does not exist; run py tools/assets/weapon_frames.py")
        doc = None
    else:
        doc = json.loads(committed_text)
        problems += shape_problems(doc, weapons)
        if frames_present(args.frames_dir):
            fresh, build_problems = build(weapons, args.frames_dir, args.blueprints_dir, args.build_root)
            problems += build_problems
            if fresh is not None and render(fresh) != committed_text:
                problems.append(f"{rel(out_path)} differs from a fresh build of the frame files; run py tools/assets/weapon_frames.py")
            notes.append(f"frame files: {len(weapons)} family(ies) rebuilt from {rel(args.frames_dir)}")
        else:
            notes.append("frame files absent: shape checked only")
    fixture_problems, fixture_notes = fixture_proof(args.turn_fixture)
    problems += fixture_problems
    notes += fixture_notes
    if doc is not None and not shape_problems(doc, weapons):
        weapon_problems, weapon_notes = weapon_proof(doc, cfg.load_assets(), args.require_harvest)
        problems += weapon_problems
        notes += weapon_notes
    for note in notes:
        log(note)
    if problems:
        for line in problems:
            print(f"  - {line}")
        print(f"CHECK: FAIL -- {len(problems)} problem(s)")
        return 1
    print(f"CHECK: PASS -- {rel(out_path)} up to date; turn proof holds")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="regenerate in memory, diff against the committed file, run the turn proof")
    parser.add_argument("--require-harvest", action="store_true", help="with --check: fail unless every weapon is harvested and proven")
    parser.add_argument("--assets-json", help="the Assets.json the turn proof reads instead of src/shared/Config/Assets.json")
    parser.add_argument("--out", help="write (or check) this file instead of src/shared/Config/WeaponModels.json")
    parser.add_argument("--frames-dir", default=FRAMES_DIR, help="the frame files' folder")
    parser.add_argument("--blueprints-dir", default=BLUEPRINTS_DIR, help="the weapon blueprints' folder")
    parser.add_argument("--build-root", help="merge output root to read the sidecars from instead of assets/build")
    parser.add_argument("--turn-fixture", default=TURN_FIXTURE, help="the real-data turn proof fixture")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    weapons = load_weapons()
    if args.check:
        return check(args, weapons)
    doc, problems = build(weapons, args.frames_dir, args.blueprints_dir, args.build_root)
    if doc is None:
        for line in problems:
            print(f"  - {line}")
        print(f"[weapon-frames] FAIL -- {len(problems)} problem(s); nothing written")
        return 1
    out_path = os.path.abspath(args.out) if args.out else OUT_PATH
    text = render(doc)
    temp = out_path + ".tmp"
    with open(temp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    os.replace(temp, out_path)
    log(f"wrote {rel(out_path)}: {len(doc['families'])} families, {sum(len(e['points']) for e in doc['families'].values())} points")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
