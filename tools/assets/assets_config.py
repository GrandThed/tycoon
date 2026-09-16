"""Read, shape and write src/shared/Config/Assets.json (schema v1, INTERFACES.md "M7 contracts";
v2 adds the city-dressing `props` block, "M9 contracts").

Shared by upload_models.py (writes modelAssetId / vipSwatchAssetId), harvest.py (writes meshId,
imageId, size, offset, vipImageId) and gen_templates.py (reads everything). Every writer goes
through save_assets so the file is always deterministic: fixed key order, 2-space indent, number
lists on one line, LF, written atomically so an interrupted run cannot lose an id that has
already been paid for with an upload.
"""

from __future__ import annotations

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "testfit"))
from blueprint import PROPS_DIRNAME, STAGE_COUNT  # noqa: E402

REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS_PATH = os.path.join(REPO_ROOT, "src", "shared", "Config", "Assets.json")
ERAS_DIR = os.path.join(REPO_ROOT, "src", "shared", "Config", "Eras")
BUILD_ROOT = os.path.join(REPO_ROOT, "assets", "build")
SCHEMA_VERSION = 1
# A file only becomes v2 once it carries props, so building-only runs keep writing v1 byte for byte.
PROPS_SCHEMA_VERSION = 2
PROPS_KEY = "props"
SINGLE_STAGE_TYPES = ("unlock", "decor", "monument")

_NUMBER_LIST = re.compile(r"\[\s*((?:-?\d+(?:\.\d+)?(?:e-?\d+)?\s*,\s*)*-?\d+(?:\.\d+)?(?:e-?\d+)?)\s*\]")


def use_assets_path(path: str | None) -> None:
    """Point every reader and writer at another Assets.json (dry runs and fixtures)."""
    global ASSETS_PATH
    if path:
        ASSETS_PATH = os.path.abspath(path)


def stages_dir(era: str, props: bool = False, build_root: str | None = None) -> str:
    """Props merge into stages/_props/<Era> so a prop can share a name with a slot (TreeOak)."""
    root = os.path.join(build_root or BUILD_ROOT, "stages")
    return os.path.join(root, PROPS_DIRNAME, era) if props else os.path.join(root, era)


def load_era_config(era: str) -> dict | None:
    if not os.path.isdir(ERAS_DIR):
        return None
    for name in sorted(os.listdir(ERAS_DIR)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(ERAS_DIR, name), "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if data.get("name") == era:
            return data
    return None


def stage_count_for_type(slot_type: str | None) -> int:
    return STAGE_COUNT if slot_type == "building" else 1


def empty_stage() -> dict:
    return {"modelAssetId": 0, "parts": []}


def empty_texture() -> dict:
    return {"vipSwatchAssetId": 0, "vipImageId": 0}


def new_assets() -> dict:
    return {"version": SCHEMA_VERSION, "textures": {}, "eras": {}}


def load_assets() -> dict:
    if not os.path.isfile(ASSETS_PATH):
        return new_assets()
    with open(ASSETS_PATH, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError(f"{ASSETS_PATH} is not a JSON object")
    data.setdefault("version", SCHEMA_VERSION)
    data.setdefault("textures", {})
    data.setdefault("eras", {})
    return data


def ensure_era(assets: dict, era_cfg: dict) -> dict:
    """Pre-list every slot of an era (5 stages for building, 1 otherwise) without touching ids."""
    era_name = era_cfg["name"]
    era = assets["eras"].setdefault(era_name, {})
    ordered: dict = {}
    for slot in era_cfg.get("slots", []):
        model = slot.get("modelName")
        if not model:
            continue
        entry = era.get(model) or {}
        stages = list(entry.get("stages") or [])
        want = stage_count_for_type(slot.get("type"))
        while len(stages) < want:
            stages.append(empty_stage())
        for st in stages:
            st.setdefault("modelAssetId", 0)
            st.setdefault("parts", [])
        ordered[model] = {"stages": stages}
    for model, entry in era.items():  # keep entries for models no longer in the config, at the end
        ordered.setdefault(model, entry)
    assets["eras"][era_name] = ordered
    return ordered


def ensure_prop(assets: dict, era: str, prop: str, stage_count: int) -> dict:
    """Pre-list a prop's stages (count from its blueprint) without touching ids; marks the file v2."""
    assets["version"] = max(int(assets.get("version", SCHEMA_VERSION)), PROPS_SCHEMA_VERSION)
    era_props = assets.setdefault(PROPS_KEY, {}).setdefault(era, {})
    entry = era_props.get(prop) or {}
    stages = list(entry.get("stages") or [])
    while len(stages) < stage_count:
        stages.append(empty_stage())
    for st in stages:
        st.setdefault("modelAssetId", 0)
        st.setdefault("parts", [])
    era_props[prop] = {"stages": stages}
    return era_props[prop]


def ensure_texture(assets: dict, kit: str) -> dict:
    tex = assets["textures"].setdefault(kit, empty_texture())
    tex.setdefault("vipSwatchAssetId", 0)
    tex.setdefault("vipImageId", 0)
    return tex


def stage_harvested(stage: dict) -> bool:
    parts = stage.get("parts") or []
    return bool(parts) and all(int(p.get("meshId", 0)) != 0 for p in parts)


def prefill_parts(stage: dict, sidecar_stage: dict | None) -> None:
    """Seed parts from the merge sidecar (kit list, Blender size and centre) until harvest replaces them."""
    if sidecar_stage is None or stage_harvested(stage):
        return
    kits = sidecar_stage.get("kits") or {}
    if not kits:
        return
    existing = {p.get("kit"): p for p in stage.get("parts") or []}
    parts = []
    for kit in sorted(kits):
        old = existing.get(kit) or {}
        parts.append(
            {
                "kit": kit,
                "meshId": int(old.get("meshId", 0)),
                "imageId": int(old.get("imageId", 0)),
                "size": list(kits[kit]["size"]),
                "offset": list(kits[kit]["centre"]),
            }
        )
    stage["parts"] = parts


def load_sidecar(era: str, model: str, props: bool = False, build_root: str | None = None) -> dict | None:
    path = os.path.join(stages_dir(era, props, build_root), f"{model}.json")
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def render_assets(assets: dict) -> str:
    ordered = {"version": assets.get("version", SCHEMA_VERSION)}
    ordered["textures"] = {k: assets["textures"][k] for k in sorted(assets["textures"])}
    ordered["eras"] = assets["eras"]
    if PROPS_KEY in assets:
        props = assets[PROPS_KEY]
        ordered[PROPS_KEY] = {era: {name: props[era][name] for name in sorted(props[era])} for era in sorted(props)}
    text = json.dumps(ordered, indent=2, ensure_ascii=False)
    text = _NUMBER_LIST.sub(lambda m: "[" + ", ".join(v.strip() for v in m.group(1).split(",")) + "]", text)
    return text + "\n"


def save_assets(assets: dict) -> None:
    text = render_assets(assets)
    json.loads(text)  # never leave the config unparseable
    os.makedirs(os.path.dirname(ASSETS_PATH), exist_ok=True)
    temp = ASSETS_PATH + ".tmp"
    with open(temp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    os.replace(temp, ASSETS_PATH)


def iter_stages(assets: dict, group: str = "eras"):
    """Yield (era, model, stage_index, stage_dict) in file order; group "props" walks the props block."""
    for era, models in assets.get(group, {}).items():
        for model, entry in models.items():
            for index, stage in enumerate(entry.get("stages") or []):
                yield era, model, index, stage
