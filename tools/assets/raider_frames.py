#!/usr/bin/env python
"""Write src/shared/Config/RaiderModels.json from the raider kit's generated config, and prove that
the templates the client clones carry the generator's frame (docs/prompts/l4-w2-contract.md 3.1;
the route of tools/assets/weapon_frames.py, L3-46 and L3-47).

    py tools/assets/raider_frames.py                      # (re)write src/shared/Config/RaiderModels.json
    py tools/assets/raider_frames.py --check              # rebuild in memory, diff, run the turn proof
    py tools/assets/raider_frames.py --check --require-harvest   # after the paste: all seven proven

The client poses a raider model from this config alone (Controllers/Raiders/Figures and RaiderPose):
each piece turns about its `pivot` in the body frame (feet at the origin, front -Z), the head is
anchored at `points.head`, the lit cue rides `points[cue.point]`, the Chief's hammer hangs at `hold`.
Those numbers come from the generator (tools/assets/raider_kit.py writes
tools/assets/out/RaiderModels.json); this script copies that file unchanged in content, one entry per
crowd kind that has a model, after these rules:

  * every key of `kinds` is a ProvingGrounds.json crowd kind, and its `height`, `radius` and
    `headRadius` are the kind's (the contract's "an entry counts only when ...": a stale model
    would place the head off the scored head);
  * `model` is a plain name (Raider + PascalCase); the five pieces head, torso, arm, legL, legR on
    stages 0..4 once each, each with a finite pivot and `parts` = { MeshPart name: role }, roles
    gear, cloth, clothLeg, skin, glow, plate (raiders.md 3: gear is never painted);
  * the points the rig reads (head, neck, hipL, hipR, shoulder) and the cue's point exist; `cue`
    names a piece and a point (size and charged both or neither); `hold` names a weapon model of
    WeaponModels.json, a piece, a grip and an orthonormal right / up;
  * the arm's keys are three angles each, every `arm.shapes` entry is a shape of one of the kind's
    attacks and every attack shape has its keys (an arm with no key for a shape would hang at the
    carry through the blow); `whirl` = {turns > 0, sin, cos}, `steady` = true;
  * `posedReach` = {out, outRadii = out / radius, up}, with `withCue` exactly when the kind has a
    lit cue (camp C's sight gate reads it, tools/check_levels.py);
  * every model has its blueprint (tools/testfit/blueprints/_props/Raiders/<Model>.json) and the
    folder holds nothing else (the upload would send it);
  * a merge sidecar, where one exists, has the five stages with the piece's kits, its triangles and
    its bounds (to the merge's rounding).

The turn proof (L3-47's, per MeshPart). A raider template is Base plus Stage0..Stage4, each stage one
MeshPart per kit folder placed by gen_templates.template_placement(harvested offset). For the client
to pose the pieces about pivots of the generator's frame, that placement must undo the import's turn
for every MeshPart:
  - always: tools/assets/fixtures/turn_proof.json and its guard (weapon_frames.fixture_proof);
  - per harvested stage of Assets.json props.Raiders: the stage's MeshParts are the piece's kits; each
    one's box, placed as the template places it, lies inside the piece's `bounds` and together they
    fill it (0.01); where the merge sidecar exists, each kit's own corners come back to themselves
    through weapon_frames.prove (the very chain the weapon frames are proven with). A guard: the same
    boxes placed WITHOUT the turn must fail somewhere, or the proof could not see a missing turn.
--require-harvest fails unless all 35 stages are harvested and proven.
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
import weapon_frames as wf  # noqa: E402  (the turn proof and the fixture guard, shared)
from gen_templates import template_placement  # noqa: E402
from raiderpose import PIECES, RIG_DEFAULTS  # noqa: E402

CONFIG_DIR = os.path.join(cfg.REPO_ROOT, "src", "shared", "Config")
OUT_PATH = os.path.join(CONFIG_DIR, "RaiderModels.json")
SOURCE_PATH = os.path.join(HERE, "out", "RaiderModels.json")
PROVING_PATH = os.path.join(CONFIG_DIR, "ProvingGrounds.json")
WEAPON_MODELS_PATH = os.path.join(CONFIG_DIR, "WeaponModels.json")
FOLDER = "Raiders"
BLUEPRINTS_DIR = os.path.join(cfg.REPO_ROOT, "tools", "testfit", "blueprints", "_props", FOLDER)
VERSION = 2
STAGES = len(PIECES)
ROLES = ("gear", "cloth", "clothLeg", "skin", "glow", "plate")
RIG_POINTS = ("head", "neck", "hipL", "hipR", "shoulder")
ARM_KEYS = ("carry", "seat", "slump")
SHAPE_KEYS = ("coil", "strike", "follow")
MODEL_NAME = re.compile(r"^Raider[A-Z][A-Za-z0-9]*$")
KIT_NAME = re.compile(r"^raider-[a-z]+$")
BODY_SLACK = 1e-6  # the contract's "equal": the model's height / radius / headRadius against the kind's
REACH_SLACK = 0.01  # posedReach.outRadii against out / radius (the generator rounds each to 2-3 places)
BOX_SLACK = 0.01  # a harvested MeshPart's placed box against the piece's bounds (Assets.json keeps 4 places)
SIDECAR_SLACK = 0.002  # a sidecar's bounds against the config's (both rounded to 3 places)
UNIT_SLACK = 0.01  # hold.right / hold.up: unit length and square to each other


def log(msg: str) -> None:
    print(f"[raider-frames] {msg}", flush=True)


rel = wf.rel
finite_vector = wf.finite_vector


def read_json(path: str) -> object:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def load_crowd_kinds(path: str = PROVING_PATH) -> dict:
    data = read_json(path)
    kinds = ((data or {}).get("crowd") or {}).get("kinds") if isinstance(data, dict) else None
    if not isinstance(kinds, dict) or not kinds:
        raise SystemExit(f"[raider-frames] {rel(path)} has no crowd.kinds table")
    return kinds


def load_weapon_models(path: str = WEAPON_MODELS_PATH) -> tuple[str, set[str]]:
    """(folder, the weapon model names) the Chief's `hold` may name."""
    if not os.path.isfile(path):
        return "", set()
    data = read_json(path)
    families = (data or {}).get("families") or {}
    return str((data or {}).get("folder") or ""), {str((e or {}).get("model")) for e in families.values()}


# ---------------------------------------------------------------- one entry's rules


def vector_problems(label: str, value: object, size: int = 3) -> list[str]:
    if not isinstance(value, list) or len(value) != size or not all(is_number(v) for v in value):
        return [f"{label} is not {size} finite numbers: {value!r}"]
    return []


def attack_shapes(kind: dict) -> list[str]:
    return [str((a or {}).get("shape")) for a in kind.get("attacks") or []]


def entry_problems(kind_id: str, entry: object, kinds: dict, weapons: tuple[str, set[str]]) -> list[str]:
    """The rules a RaiderModels.json kind entry keeps (the shape the client's figure reads)."""
    tag = f"{kind_id}"
    if not isinstance(entry, dict):
        return [f"{tag}: entry is not an object"]
    problems: list[str] = []
    kind = kinds.get(kind_id)
    if not isinstance(kind, dict):
        problems.append(f"{tag}: no crowd kind of that name in ProvingGrounds.json (the client would never use it)")
        kind = {}
    model = entry.get("model")
    if not isinstance(model, str) or not MODEL_NAME.match(model):
        problems.append(f"{tag}: model {model!r} is not a plain name (Raider + PascalCase)")
    for key in ("height", "radius", "headRadius"):
        value = entry.get(key)
        if not is_number(value) or value <= 0:
            problems.append(f"{tag}: {key} {value!r} is not a positive number")
        elif kind and (not is_number(kind.get(key)) or abs(value - kind[key]) > BODY_SLACK):
            problems.append(f"{tag}: model built for {key} {value}, the crowd kind has {kind.get(key)} (re-run the generator)")
    skin = entry.get("skin")
    if not isinstance(skin, list) or len(skin) != 3 or not all(isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= 255 for v in skin):
        problems.append(f"{tag}: skin {skin!r} is not three whole numbers 0..255")
    # The pieces: the five, on stages 0..4 once each.
    pieces = entry.get("pieces")
    names: list[str] = []
    if not isinstance(pieces, list):
        problems.append(f"{tag}: no pieces list")
        pieces = []
    stages = []
    for index, piece in enumerate(pieces):
        if not isinstance(piece, dict):
            problems.append(f"{tag}: piece {index + 1} is not an object")
            continue
        name = piece.get("name")
        names.append(str(name))
        ptag = f"{tag}: piece {name!r}"
        stage = piece.get("stage")
        if not isinstance(stage, int) or isinstance(stage, bool):
            problems.append(f"{ptag}: stage {stage!r} is not a whole number")
        else:
            stages.append(stage)
        problems += vector_problems(f"{ptag}: pivot", piece.get("pivot"))
        parts = piece.get("parts")
        if not isinstance(parts, dict) or not parts:
            problems.append(f"{ptag}: parts is not a table of MeshPart name -> role")
        else:
            for part, role in parts.items():
                if not KIT_NAME.match(str(part)):
                    problems.append(f"{ptag}: MeshPart {part!r} is not a raider kit folder (raider-<name>)")
                if role not in ROLES:
                    problems.append(f"{ptag}: MeshPart {part!r} has role {role!r} (roles: {', '.join(ROLES)})")
        bounds = piece.get("bounds")
        lo = finite_vector((bounds or {}).get("min")) if isinstance(bounds, dict) else None
        hi = finite_vector((bounds or {}).get("max")) if isinstance(bounds, dict) else None
        if lo is None or hi is None or any(lo[i] > hi[i] for i in range(3)):
            problems.append(f"{ptag}: bounds need min <= max, three finite numbers each")
    if sorted(names) != sorted(PIECES):
        problems.append(f"{tag}: pieces are {names}, not the five {list(PIECES)}")
    if sorted(stages) != list(range(STAGES)):
        problems.append(f"{tag}: piece stages are {sorted(stages)}, not 0..{STAGES - 1} once each")
    # The points.
    points = entry.get("points")
    if not isinstance(points, dict):
        problems.append(f"{tag}: no points table")
        points = {}
    for name in RIG_POINTS:
        if name not in points:
            problems.append(f"{tag}: no `{name}` point (the rig poses from it)")
    for name in sorted(points):
        problems += vector_problems(f"{tag}: point {name}", points[name])
    # The rig's per-kind numbers.
    leg = entry.get("legLength")
    if not is_number(leg) or leg <= 0:
        problems.append(f"{tag}: legLength {leg!r} is not a positive number")
    if entry.get("leadLeg") not in ("legL", "legR"):
        problems.append(f"{tag}: leadLeg {entry.get('leadLeg')!r} is not legL or legR")
    share = entry.get("armSwingShare")
    if not is_number(share) or share < 0:
        problems.append(f"{tag}: armSwingShare {share!r} is not a number >= 0")
    # The arm's keys.
    arm = entry.get("arm")
    if not isinstance(arm, dict):
        problems.append(f"{tag}: no arm table")
    else:
        for key in ARM_KEYS:
            problems += vector_problems(f"{tag}: arm.{key}", arm.get(key))
        shapes = arm.get("shapes")
        if not isinstance(shapes, dict):
            problems.append(f"{tag}: arm.shapes is not a table")
            shapes = {}
        own = attack_shapes(kind) if kind else []
        for shape in sorted(shapes):
            keys = shapes[shape]
            stag = f"{tag}: arm.shapes.{shape}"
            if kind and shape not in own:
                problems.append(f"{stag}: the kind has no attack of that shape (its attacks: {own})")
            if not isinstance(keys, dict):
                problems.append(f"{stag} is not a table")
                continue
            for key in SHAPE_KEYS:
                if key in keys:
                    problems += vector_problems(f"{stag}.{key}", keys[key])
            if "coil" not in keys or "strike" not in keys:
                problems.append(f"{stag}: needs coil and strike")
            whirl = keys.get("whirl")
            if whirl is not None:
                if not isinstance(whirl, dict) or not is_number(whirl.get("turns")) or whirl["turns"] <= 0:
                    problems.append(f"{stag}.whirl: turns must be a positive number")
                else:
                    problems += vector_problems(f"{stag}.whirl.sin", whirl.get("sin"))
                    problems += vector_problems(f"{stag}.whirl.cos", whirl.get("cos"))
            if "steady" in keys and keys["steady"] is not True:
                problems.append(f"{stag}.steady is {keys['steady']!r}: true or absent")
            unknown = sorted(set(keys) - set(SHAPE_KEYS) - {"whirl", "steady"})
            if unknown:
                problems.append(f"{stag}: unknown keys {unknown} (the client reads none of them)")
        for shape in own:
            if shape not in shapes:
                problems.append(f"{tag}: attack shape {shape!r} has no arm keys (the arm would hang at its carry through the blow)")
    # The lit cue.
    cue = entry.get("cue")
    if cue is not None:
        if not isinstance(cue, dict):
            problems.append(f"{tag}: cue is not a table")
        else:
            if cue.get("piece") not in PIECES:
                problems.append(f"{tag}: cue.piece {cue.get('piece')!r} is no piece")
            if cue.get("point") not in points:
                problems.append(f"{tag}: cue.point {cue.get('point')!r} is no point of the model")
            sized = [key for key in ("size", "charged") if key in cue]
            if len(sized) == 1:
                problems.append(f"{tag}: cue has {sized[0]} without its pair (size and charged go together)")
            for key in sized:
                if not is_number(cue[key]) or cue[key] <= 0:
                    problems.append(f"{tag}: cue.{key} {cue[key]!r} is not a positive number")
            if len(sized) == 2 and is_number(cue["size"]) and is_number(cue["charged"]) and cue["charged"] < cue["size"]:
                problems.append(f"{tag}: cue.charged {cue['charged']} is under its rest size {cue['size']}")
    # The held weapon.
    hold = entry.get("hold")
    if hold is not None:
        folder, models = weapons
        if not isinstance(hold, dict):
            problems.append(f"{tag}: hold is not a table")
        else:
            if hold.get("model") not in models:
                problems.append(f"{tag}: hold.model {hold.get('model')!r} is no WeaponModels.json model")
            if hold.get("folder") != folder:
                problems.append(f"{tag}: hold.folder {hold.get('folder')!r} is not WeaponModels.json's {folder!r}")
            if hold.get("piece", "arm") not in PIECES:
                problems.append(f"{tag}: hold.piece {hold.get('piece')!r} is no piece")
            if not is_number(hold.get("scale")) or hold["scale"] <= 0:
                problems.append(f"{tag}: hold.scale {hold.get('scale')!r} is not a positive number")
            for key in ("grip", "right", "up"):
                problems += vector_problems(f"{tag}: hold.{key}", hold.get(key))
            right, up = finite_vector(hold.get("right")), finite_vector(hold.get("up"))
            if right is not None and up is not None:
                lr, lu = math.sqrt(sum(v * v for v in right)), math.sqrt(sum(v * v for v in up))
                dot = sum(a * b for a, b in zip(right, up))
                if abs(lr - 1) > UNIT_SLACK or abs(lu - 1) > UNIT_SLACK or abs(dot) > UNIT_SLACK:
                    problems.append(f"{tag}: hold.right / hold.up are not unit and square (|right| {lr:.3f}, |up| {lu:.3f}, dot {dot:.3f}): CFrame.fromMatrix would shear")
    # The posed reach.
    reach = entry.get("posedReach")
    if not isinstance(reach, dict):
        problems.append(f"{tag}: no posedReach (camp C's sight gate reads it)")
    else:
        for key in ("out", "outRadii", "up"):
            if not is_number(reach.get(key)) or reach[key] <= 0:
                problems.append(f"{tag}: posedReach.{key} {reach.get(key)!r} is not a positive number")
        radius = entry.get("radius")
        if is_number(reach.get("out")) and is_number(reach.get("outRadii")) and is_number(radius) and radius > 0:
            if abs(reach["out"] / radius - reach["outRadii"]) > REACH_SLACK:
                problems.append(f"{tag}: posedReach.outRadii {reach['outRadii']} is not out / radius ({reach['out'] / radius:.3f})")
        with_cue = reach.get("withCue")
        if (with_cue is not None) != (cue is not None):
            problems.append(f"{tag}: posedReach.withCue {'present' if with_cue is not None else 'absent'} but the kind {'has no' if cue is None else 'has a'} lit cue")
        elif with_cue is not None:
            for key in ("out", "up"):
                if not is_number(with_cue.get(key)) or not is_number(reach.get(key)) or with_cue[key] < reach[key] - REACH_SLACK:
                    problems.append(f"{tag}: posedReach.withCue.{key} {with_cue.get(key)!r} is under the model's own {reach.get(key)!r}")
    return problems


def blueprint_problems(models: list[str], blueprints_dir: str) -> list[str]:
    problems = []
    for model in models:
        if not os.path.isfile(os.path.join(blueprints_dir, f"{model}.json")):
            problems.append(f"{model}: no blueprint {rel(os.path.join(blueprints_dir, model + '.json'))}")
    if os.path.isdir(blueprints_dir):
        wanted = {f"{m}.json" for m in models}
        for name in sorted(os.listdir(blueprints_dir)):
            if name.endswith(".json") and name not in wanted:
                problems.append(f"blueprint {rel(os.path.join(blueprints_dir, name))} is no raider model (the folder holds the models exactly; the upload would send it)")
    return problems


def piece_by_stage(entry: dict) -> dict[int, dict]:
    return {p["stage"]: p for p in entry.get("pieces") or [] if isinstance(p, dict) and isinstance(p.get("stage"), int)}


def sidecar_problems(model: str, entry: dict, build_root: str | None) -> tuple[list[str], dict | None]:
    """(problems, the sidecar or None): the merge must be the geometry the config describes, stage by
    stage: the piece's kits, its triangles, its bounds to the merge's rounding."""
    sidecar = cfg.load_sidecar(FOLDER, model, props=True, build_root=build_root)
    if sidecar is None:
        return [], None
    stages = sidecar.get("stages") or []
    if len(stages) != STAGES:
        return [f"{model}: merge sidecar has {len(stages)} stages, not {STAGES}"], sidecar
    problems = []
    by_stage = piece_by_stage(entry)
    for stage in stages:
        index = stage.get("stage")
        piece = by_stage.get(index)
        if piece is None:
            problems.append(f"{model}: merge sidecar stage {index} matches no piece")
            continue
        tag = f"{model}: stage {index} ({piece['name']})"
        kits = stage.get("kits") or {}
        if sorted(kits) != sorted(piece.get("parts") or {}):
            problems.append(f"{tag}: merged kits {sorted(kits)} are not the piece's MeshParts {sorted(piece.get('parts') or {})}")
        merged = sum(int((k or {}).get("triangles", 0)) for k in kits.values())
        if piece.get("triangles") is not None and merged != piece["triangles"]:
            problems.append(f"{tag}: merged triangles {merged} differ from the config's {piece['triangles']} (re-merge, or regenerate the kit)")
        lo, hi = finite_vector(stage.get("min")), finite_vector(stage.get("max"))
        blo, bhi = finite_vector((piece.get("bounds") or {}).get("min")), finite_vector((piece.get("bounds") or {}).get("max"))
        if None not in (lo, hi, blo, bhi):
            gap = max(abs(a - b) for a, b in zip(lo + hi, blo + bhi))
            if gap > SIDECAR_SLACK:
                problems.append(f"{tag}: merged bounds {lo}..{hi} differ from the config's {blo}..{bhi} by {gap:.4f}")
    return problems, sidecar


# ---------------------------------------------------------------- build and render


def build(source_path: str, kinds: dict, weapons: tuple[str, set[str]], blueprints_dir: str,
          build_root: str | None) -> tuple[dict | None, list[str], dict]:
    """(the config, problems, sidecars by model). The config is the source's content unchanged."""
    if not os.path.isfile(source_path):
        return None, [f"{rel(source_path)} is missing: run the generator (py tools/assets/raider_kit.py)"], {}
    doc = read_json(source_path)
    problems = shape_problems(doc, kinds, weapons)
    sidecars: dict = {}
    if not problems:
        models = [doc["kinds"][k]["model"] for k in sorted(doc["kinds"])]
        problems += blueprint_problems(models, blueprints_dir)
        for kind_id in sorted(doc["kinds"]):
            entry = doc["kinds"][kind_id]
            found, sidecar = sidecar_problems(entry["model"], entry, build_root)
            problems += found
            if sidecar is not None:
                sidecars[entry["model"]] = sidecar
    return (None if problems else doc), problems, sidecars


def shape_problems(doc: object, kinds: dict, weapons: tuple[str, set[str]]) -> list[str]:
    """The file on its own: what a checkout without the generator's output can still prove."""
    if not isinstance(doc, dict):
        return ["RaiderModels.json is not an object"]
    problems = []
    if doc.get("version") != VERSION:
        problems.append(f"version is {doc.get('version')!r}, not {VERSION}")
    if doc.get("folder") != FOLDER:
        problems.append(f"folder is {doc.get('folder')!r}, not {FOLDER!r}")
    rig = doc.get("rig")
    if not isinstance(rig, dict):
        problems.append("no rig table")
    else:
        for key in RIG_DEFAULTS:
            if not is_number(rig.get(key)):
                problems.append(f"rig.{key} {rig.get(key)!r} is not a number (the rig reads it)")
        for key in sorted(set(rig) - set(RIG_DEFAULTS)):
            problems.append(f"rig.{key}: unknown key (raiderpose.RIG_DEFAULTS has no such rule)")
    entries = doc.get("kinds")
    if not isinstance(entries, dict) or not entries:
        return problems + ["no kinds table"]
    seen: dict[str, str] = {}
    for kind_id in sorted(entries):
        problems += entry_problems(kind_id, entries[kind_id], kinds, weapons)
        model = (entries[kind_id] or {}).get("model") if isinstance(entries[kind_id], dict) else None
        if isinstance(model, str):
            if model in seen:
                problems.append(f"{kind_id}: model {model} is also {seen[model]}'s (one template per kind)")
            seen[model] = kind_id
    return problems


def compact(value: object) -> str:
    return json.dumps(value, separators=(", ", ": "), ensure_ascii=False)


INLINE = 100  # a list or table whose one-line form is this short goes on one line


def render_value(value: object, indent: int) -> str:
    one = compact(value)
    if not isinstance(value, (dict, list)) or len(one) + indent <= INLINE or not value:
        return one
    pad = "  " * (indent // 2 + 1)
    close = "  " * (indent // 2)
    if isinstance(value, list):
        if all(not isinstance(v, (dict, list)) for v in value):
            return one  # a list of numbers or names stays on one line, however long
        items = [pad + render_value(v, indent + 2) for v in value]
        return "[\n" + ",\n".join(items) + "\n" + close + "]"
    items = [f"{pad}{json.dumps(k, ensure_ascii=False)}: {render_value(v, indent + 2)}" for k, v in value.items()]
    return "{\n" + ",\n".join(items) + "\n" + close + "}"


def render(doc: dict) -> str:
    """Two-space indent, short tables and every list of numbers on one line, the source's key order, LF."""
    text = render_value(doc, 0) + "\n"
    if json.loads(text) != doc:
        raise AssertionError("render does not round-trip")  # never write what does not read back
    return text


# ---------------------------------------------------------------- the turn proof, per MeshPart


def placed_box(part: dict, placement=template_placement) -> tuple[list[float], list[float]] | None:
    """A harvested MeshPart's box in the template frame, as gen_templates places it: the placement's
    position, the part's size turned by the placement (a turn about Y keeps each axis' extent)."""
    offset, size = finite_vector(part.get("offset")), finite_vector(part.get("size"))
    if offset is None or size is None:
        return None
    position, rotation = placement(offset)
    half = [sum(abs(rotation[row][col]) * size[col] for col in range(3)) / 2 for row in range(3)]
    return [position[i] - half[i] for i in range(3)], [position[i] + half[i] for i in range(3)]


def stage_box_problems(label: str, parts: list[dict], piece: dict, placement=template_placement) -> list[str]:
    """Every MeshPart's placed box inside the piece's bounds, and together they fill them."""
    blo, bhi = piece["bounds"]["min"], piece["bounds"]["max"]
    problems = []
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    for part in parts:
        box = placed_box(part, placement)
        if box is None:
            problems.append(f"{label}/{part.get('kit')}: harvested offset or size is not three numbers")
            continue
        out = max(max(blo[i] - box[0][i], box[1][i] - bhi[i]) for i in range(3))
        if out > BOX_SLACK:
            problems.append(f"{label}/{part.get('kit')}: placed box {[round(v, 4) for v in box[0]]}..{[round(v, 4) for v in box[1]]} lies {out:.4f} outside the piece's bounds {blo}..{bhi}")
        lo = [min(lo[i], box[0][i]) for i in range(3)]
        hi = [max(hi[i], box[1][i]) for i in range(3)]
    if parts and all(math.isfinite(v) for v in lo + hi):
        gap = max(abs(a - b) for a, b in zip(lo + hi, blo + bhi))
        if gap > BOX_SLACK:
            problems.append(f"{label}: the placed MeshParts span {[round(v, 4) for v in lo]}..{[round(v, 4) for v in hi]}, not the piece's bounds {blo}..{bhi} ({gap:.4f} off)")
    return problems


def harvest_proof(doc: dict, assets: dict, sidecars: dict, require_harvest: bool) -> tuple[list[str], list[str]]:
    """Every harvested stage of every raider model, against the config and (where present) its sidecar."""
    problems: list[str] = []
    props = (assets.get(cfg.PROPS_KEY) or {}).get(doc["folder"]) or {}
    proven, waiting = [], []
    parts_proven = corners_proven = 0
    guard_caught = 0
    for kind_id in sorted(doc["kinds"]):
        entry = doc["kinds"][kind_id]
        model = entry["model"]
        record = props.get(model) or {}
        stages = record.get("stages") or []
        by_stage = piece_by_stage(entry)
        sidecar = sidecars.get(model)
        side_stages = {s.get("stage"): s for s in (sidecar or {}).get("stages") or []}
        missing = [k for k in range(STAGES) if k >= len(stages) or not cfg.stage_harvested(stages[k])]
        if missing:
            waiting.append(f"{model} (stage{'s' if len(missing) > 1 else ''} {', '.join(str(k) for k in missing)})")
        if len(stages) > STAGES:
            problems.append(f"{FOLDER}/{model}: harvested with {len(stages)} stages, not {STAGES}")
        model_ok = not missing
        for index, stage in enumerate(stages[:STAGES]):
            if not cfg.stage_harvested(stage):
                continue
            piece = by_stage.get(index)
            label = f"{FOLDER}/{model} stage {index}"
            if piece is None:
                problems.append(f"{label}: no piece of the config is on this stage")
                model_ok = False
                continue
            parts = stage.get("parts") or []
            kits = sorted(str(p.get("kit")) for p in parts)
            if kits != sorted(piece["parts"]):
                problems.append(f"{label} ({piece['name']}): harvested MeshParts {kits} are not the piece's {sorted(piece['parts'])} (the client would fall back to the placeholder)")
                model_ok = False
                continue
            found = stage_box_problems(label, parts, piece)
            if stage_box_problems(label, parts, piece, wf.unturned_placement):
                guard_caught += 1
            side = side_stages.get(index)
            for part in parts:
                kit = (side or {}).get("kits", {}).get(part["kit"]) if side else None
                if kit is None:
                    continue
                centre, size = finite_vector(kit.get("centre")), finite_vector(kit.get("size"))
                offset, hsize = finite_vector(part.get("offset")), finite_vector(part.get("size"))
                if None in (centre, size, offset, hsize):
                    found.append(f"{label}/{part['kit']}: sidecar or harvest record lacks a centre / size / offset")
                    continue
                points = wf.corners(centre, size)
                found += wf.prove(f"{label}/{part['kit']}", points, centre, size, offset, hsize)
                corners_proven += len(points)
            problems += found
            if found:
                model_ok = False
            else:
                parts_proven += len(parts)
        if model_ok:
            proven.append(model)
    total = len(doc["kinds"])
    notes = [f"raiders ({rel(cfg.ASSETS_PATH)}): {len(proven)} of {total} models harvested and proven: "
             f"{parts_proven} MeshPart(s) placed inside and filling their piece's bounds, {corners_proven} sidecar corner(s) come back"]
    harvested_stages = sum(1 for k in sorted(doc["kinds"]) for s in ((props.get(doc["kinds"][k]["model"]) or {}).get("stages") or [])
                           if cfg.stage_harvested(s))
    if harvested_stages:
        notes.append(f"guard: placed without the turn, {guard_caught} of {harvested_stages} harvested stage(s) fail the box proof")
        if guard_caught == 0:
            problems.append("turn proof guard: an unturned placement passes the box proof on every harvested stage, so the proof could not catch it")
    if waiting:
        notes.append(f"not harvested yet ({len(waiting)}): {', '.join(waiting)}")
        if require_harvest:
            problems.append(f"--require-harvest: {len(waiting)} of {total} raider model(s) are not wholly harvested: {', '.join(waiting)}")
    return problems, notes


# ---------------------------------------------------------------- main


def check(args, kinds: dict, weapons: tuple[str, set[str]]) -> int:
    problems: list[str] = []
    notes: list[str] = []
    out_path = os.path.abspath(args.out) if args.out else OUT_PATH
    committed_text = None
    if os.path.isfile(out_path):
        with open(out_path, "r", encoding="utf-8", newline="") as fh:
            committed_text = fh.read()
    sidecars: dict = {}
    doc = None
    if committed_text is None:
        problems.append(f"{rel(out_path)} does not exist; run py tools/assets/raider_frames.py")
    else:
        doc = json.loads(committed_text)
        problems += shape_problems(doc, kinds, weapons)
        if os.path.isfile(args.source):
            fresh, build_problems, sidecars = build(args.source, kinds, weapons, args.blueprints_dir, args.build_root)
            problems += [p for p in build_problems if p not in problems]
            if fresh is not None and render(fresh) != committed_text:
                problems.append(f"{rel(out_path)} differs from {rel(args.source)}; run py tools/assets/raider_frames.py")
            notes.append(f"source: {rel(args.source)} rebuilt ({len(sidecars)} merge sidecar(s) read)")
        else:
            notes.append("generator output absent: shape checked only")
    fixture_problems, fixture_notes = wf.fixture_proof(args.turn_fixture)
    problems += fixture_problems
    notes += fixture_notes
    if doc is not None and not shape_problems(doc, kinds, weapons):
        harvest_problems, harvest_notes = harvest_proof(doc, cfg.load_assets(), sidecars, args.require_harvest)
        problems += harvest_problems
        notes += harvest_notes
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
    parser.add_argument("--check", action="store_true", help="rebuild in memory, diff against the committed file, run the turn proof")
    parser.add_argument("--require-harvest", action="store_true", help="with --check: fail unless every stage of every raider is harvested and proven")
    parser.add_argument("--assets-json", help="the Assets.json the turn proof reads instead of src/shared/Config/Assets.json")
    parser.add_argument("--out", help="write (or check) this file instead of src/shared/Config/RaiderModels.json")
    parser.add_argument("--source", default=SOURCE_PATH, help="the generator's RaiderModels.json")
    parser.add_argument("--proving", default=PROVING_PATH, help="the ProvingGrounds.json whose crowd kinds the entries must match")
    parser.add_argument("--blueprints-dir", default=BLUEPRINTS_DIR, help="the raider blueprints' folder")
    parser.add_argument("--build-root", help="merge output root to read the sidecars from instead of assets/build")
    parser.add_argument("--turn-fixture", default=wf.TURN_FIXTURE, help="the real-data turn proof fixture")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)
    kinds = load_crowd_kinds(args.proving)
    weapons = load_weapon_models()
    if args.check:
        return check(args, kinds, weapons)
    doc, problems, _sidecars = build(args.source, kinds, weapons, args.blueprints_dir, args.build_root)
    if doc is None:
        for line in problems:
            print(f"  - {line}")
        print(f"[raider-frames] FAIL -- {len(problems)} problem(s); nothing written")
        return 1
    out_path = os.path.abspath(args.out) if args.out else OUT_PATH
    text = render(doc)
    temp = out_path + ".tmp"
    with open(temp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    os.replace(temp, out_path)
    log(f"wrote {rel(out_path)}: {len(doc['kinds'])} kinds ({', '.join(sorted(doc['kinds']))})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
