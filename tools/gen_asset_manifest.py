#!/usr/bin/env python
"""Asset coverage manifest for Era City Tycoon (spec section 8, amended M7).

Reads every era config in src/shared/Config/Eras/*.json and writes
docs/ASSET_MANIFEST.md: one section per era in eraIndex order with a row per
modelName in purchase order showing how far that model has travelled through
the asset pipeline -- blueprint, stage GLBs, upload, harvest, template.

Inputs (all optional except the era configs; a missing input reads as "not yet"):
  tools/testfit/blueprints/<Era>/<ModelName>.json   blueprint (kits, stages)
  assets/build/stages/<Era>/<ModelName>_S<n>.glb    merged stage meshes (gitignored)
  src/shared/Config/Assets.json                     uploaded ids / harvested mesh ids
  templates/<Era>/<ModelName>.rbxmx                 Rojo-mapped template

City-dressing props (M9) get their own table per era, listed only when the era has any: the same
facts from tools/testfit/blueprints/_props/<Era>/, assets/build/stages/_props/<Era>/,
Assets.json `props` (optional key) and templates/_props/<Era>/.

Output is deterministic (stable ordering, no timestamps) so --check can diff
it. The GLB column is the one local-only fact (assets/build is gitignored), so
--check masks that column on both sides before comparing.

Usage:
  py tools/gen_asset_manifest.py           # (re)write docs/ASSET_MANIFEST.md
  py tools/gen_asset_manifest.py --check   # validate configs + blueprints and
                                           # compare the committed manifest;
                                           # exit 1 and print one line per problem
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ERAS_DIR = REPO_ROOT / "src" / "shared" / "Config" / "Eras"
ASSETS_CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Assets.json"
BLUEPRINTS_DIR = REPO_ROOT / "tools" / "testfit" / "blueprints"
STAGES_DIR = REPO_ROOT / "assets" / "build" / "stages"
TEMPLATES_DIR = REPO_ROOT / "templates"
PROPS_DIRNAME = "_props"
PROP_TYPE = "prop"
MANIFEST_PATH = REPO_ROOT / "docs" / "ASSET_MANIFEST.md"

# Era config schema v1.1 (INTERFACES.md): modelName must be PascalCase.
MODEL_NAME_RE = re.compile(r"^[A-Z][A-Za-z0-9]*$")
REQUIRED_SLOT_FIELDS = ("modelName", "description", "kit")
# INTERFACES "Blueprints": building slots use stages 0-4, everything else stage 0 only.
STAGE_COUNT_BY_TYPE = {"building": 5}
DEFAULT_STAGE_COUNT = 1
NONE = "—"
NOT_AVAILABLE = "n/a"
WARNING_PREFIX = "warning:"

TABLE_HEADER = (
    "| # | modelName | Slot | Type | Blueprint | Kits | Stages | GLBs "
    "| Uploaded | Harvested | Template |"
)
TABLE_RULE = (
    "|---|-----------|------|------|-----------|------|--------|------"
    "|----------|-----------|----------|"
)
# 0-based index of the GLBs cell once a row is split on "|" (leading empty cell first).
GLB_CELL_INDEX = 8
ROW_CELL_COUNT = TABLE_HEADER.count("|") + 1


@dataclass
class Blueprint:
    kits: list[str]
    stage_count: int
    problems: list[str] = field(default_factory=list)


@dataclass
class Coverage:
    blueprint: Blueprint | None
    expected_stages: int
    glb_count: int | None  # None = assets/build tree absent on this machine
    assets_stage_count: int | None  # None = no Assets.json entry
    uploaded_stages: int
    harvested_stages: int
    template: bool

    @property
    def is_uploaded(self) -> bool:
        return bool(self.assets_stage_count) and self.uploaded_stages == self.assets_stage_count

    @property
    def is_harvested(self) -> bool:
        return bool(self.assets_stage_count) and self.harvested_stages == self.assets_stage_count


def load_eras() -> list[dict]:
    eras = []
    for path in sorted(ERAS_DIR.glob("*.json")):
        with open(path, encoding="utf-8") as handle:
            era = json.load(handle)
        era["_file"] = path.name
        eras.append(era)
    eras.sort(key=lambda era: era.get("eraIndex", 0))
    return eras


def validate(eras: list[dict]) -> list[str]:
    """Return one human-readable line per era config schema problem (empty = clean)."""
    problems: list[str] = []
    for era in eras:
        label = era["_file"]
        if not str(era.get("displayName", "")).strip():
            problems.append(f"{label}: missing displayName")
        seen: dict[str, str] = {}
        for index, slot in enumerate(era.get("slots", []), start=1):
            slot_label = f"{label} slot #{index} ({slot.get('id', '?')})"
            for field_name in REQUIRED_SLOT_FIELDS:
                if not str(slot.get(field_name, "")).strip():
                    problems.append(f"{slot_label}: missing or empty {field_name}")
            model = slot.get("modelName")
            if not model:
                continue
            if not MODEL_NAME_RE.match(model):
                problems.append(f"{slot_label}: modelName '{model}' is not PascalCase")
            if model in seen:
                problems.append(
                    f"{slot_label}: duplicate modelName '{model}' (also slot {seen[model]})"
                )
            seen.setdefault(model, slot.get("id", "?"))
    return problems


def load_blueprint(era_name: str, model: str, root: Path = BLUEPRINTS_DIR) -> Blueprint | None:
    """Read a blueprint if present. Hard schema errors (unparseable, id or era
    mismatch, bad pieces) land in .problems and fail --check, because the
    merge/upload tools key on exactly those fields."""
    path = root / era_name / f"{model}.json"
    if not path.exists():
        return None
    label = path.relative_to(REPO_ROOT).as_posix()
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as error:
        return Blueprint(kits=[], stage_count=0, problems=[f"{label}: unreadable ({error})"])
    problems: list[str] = []
    if not isinstance(data, dict):
        return Blueprint(kits=[], stage_count=0, problems=[f"{label}: top level is not an object"])
    if data.get("id") != model:
        problems.append(f"{label}: id '{data.get('id')}' does not equal the file stem '{model}'")
    if data.get("era") != era_name:
        problems.append(f"{label}: era '{data.get('era')}' does not equal '{era_name}'")
    pieces = data.get("pieces")
    if not isinstance(pieces, list) or not pieces:
        problems.append(f"{label}: no pieces")
        pieces = []
    kits: set[str] = set()
    max_stage = -1
    for index, piece in enumerate(pieces, start=1):
        if not isinstance(piece, dict):
            problems.append(f"{label}: piece #{index} is not an object")
            continue
        kit = str(piece.get("kit", "")).strip()
        if kit:
            kits.add(kit)
        else:
            problems.append(f"{label}: piece #{index} has no kit")
        stage = piece.get("stage", 0)
        if isinstance(stage, int) and not isinstance(stage, bool) and 0 <= stage <= 4:
            max_stage = max(max_stage, stage)
        else:
            problems.append(f"{label}: piece #{index} stage {stage!r} is not an integer 0-4")
    stage_count = max_stage + 1 if max_stage >= 0 else 0
    return Blueprint(kits=sorted(kits), stage_count=stage_count, problems=problems)


def load_assets_config() -> dict | None:
    if not ASSETS_CONFIG_PATH.exists():
        return None
    try:
        with open(ASSETS_CONFIG_PATH, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def stage_id_counts(entry: object) -> tuple[int | None, int, int]:
    """(stage count, stages with a modelAssetId, stages whose every part has a meshId)."""
    if not isinstance(entry, dict):
        return None, 0, 0
    stages = entry.get("stages")
    if not isinstance(stages, list):
        return None, 0, 0
    uploaded = 0
    harvested = 0
    for stage in stages:
        if not isinstance(stage, dict):
            continue
        if stage.get("modelAssetId"):
            uploaded += 1
        parts = stage.get("parts")
        if (
            isinstance(parts, list)
            and parts
            and all(isinstance(part, dict) and part.get("meshId") for part in parts)
        ):
            harvested += 1
    return len(stages), uploaded, harvested


def count_glbs(era_name: str, model: str, props: bool = False) -> int | None:
    if not STAGES_DIR.is_dir():
        return None
    folder = STAGES_DIR / PROPS_DIRNAME / era_name if props else STAGES_DIR / era_name
    return len(list(folder.glob(f"{model}_S[0-9].glb")))


def collect_props(era_name: str, assets: dict | None) -> tuple[list[tuple[str, Coverage]], list[str]]:
    """(prop name, Coverage) sorted by name for every prop with a blueprint or an Assets.json entry.
    A prop's expected stage count is its own blueprint's (props are not slots)."""
    era_assets: object = None
    if assets is not None:
        props_block = assets.get("props")
        if isinstance(props_block, dict):
            era_assets = props_block.get(era_name)
    names: set[str] = set()
    blueprint_dir = BLUEPRINTS_DIR / PROPS_DIRNAME / era_name
    if blueprint_dir.is_dir():
        names.update(path.stem for path in blueprint_dir.glob("*.json"))
    if isinstance(era_assets, dict):
        names.update(str(name) for name in era_assets)
    rows: list[tuple[str, Coverage]] = []
    notes: list[str] = []
    for name in sorted(names):
        blueprint = load_blueprint(era_name, name, BLUEPRINTS_DIR / PROPS_DIRNAME)
        if blueprint is not None:
            notes.extend(blueprint.problems)
        entry = era_assets.get(name) if isinstance(era_assets, dict) else None
        stage_count, uploaded, harvested = stage_id_counts(entry)
        if blueprint is not None and not blueprint.problems:
            expected = blueprint.stage_count
        else:
            expected = stage_count or DEFAULT_STAGE_COUNT
        rows.append(
            (
                name,
                Coverage(
                    blueprint=blueprint,
                    expected_stages=expected,
                    glb_count=count_glbs(era_name, name, props=True),
                    assets_stage_count=stage_count,
                    uploaded_stages=uploaded,
                    harvested_stages=harvested,
                    template=(TEMPLATES_DIR / PROPS_DIRNAME / era_name / f"{name}.rbxmx").exists(),
                ),
            )
        )
    return rows, notes


def collect(era: dict, assets: dict | None) -> tuple[list[Coverage], list[str]]:
    """One Coverage per slot in config order plus every blueprint problem/warning found."""
    era_name = era.get("name", "?")
    era_assets: object = None
    if assets is not None:
        eras_block = assets.get("eras")
        if isinstance(eras_block, dict):
            era_assets = eras_block.get(era_name)
    rows: list[Coverage] = []
    notes: list[str] = []
    for slot in era.get("slots", []):
        model = slot.get("modelName", "")
        slot_type = slot.get("type", "")
        expected = STAGE_COUNT_BY_TYPE.get(slot_type, DEFAULT_STAGE_COUNT)
        blueprint = load_blueprint(era_name, model) if model else None
        if blueprint is not None:
            notes.extend(blueprint.problems)
            if not blueprint.problems and blueprint.stage_count != expected:
                notes.append(
                    f"{WARNING_PREFIX} {era_name}/{model}.json defines "
                    f"{blueprint.stage_count} stage(s); a '{slot_type}' slot expects {expected}"
                )
        entry = era_assets.get(model) if isinstance(era_assets, dict) else None
        stage_count, uploaded, harvested = stage_id_counts(entry)
        rows.append(
            Coverage(
                blueprint=blueprint,
                expected_stages=expected,
                glb_count=count_glbs(era_name, model) if model else None,
                assets_stage_count=stage_count,
                uploaded_stages=uploaded,
                harvested_stages=harvested,
                template=bool(model) and (TEMPLATES_DIR / era_name / f"{model}.rbxmx").exists(),
            )
        )
    return rows, notes


def md_cell(text: object) -> str:
    return str(text).replace("|", r"\|").replace("\n", " ")


def fraction(count: int, total: int | None) -> str:
    return NONE if total is None else f"{count}/{total}"


def render_row(index: int, slot: dict, cov: Coverage) -> str:
    bp = cov.blueprint
    if bp is None:
        blueprint_cell, kits_cell, stages_cell = NONE, NONE, NONE
    elif bp.problems:
        blueprint_cell, kits_cell, stages_cell = "invalid", md_cell(", ".join(bp.kits)) or NONE, NONE
    else:
        blueprint_cell, kits_cell, stages_cell = "yes", md_cell(", ".join(bp.kits)), str(bp.stage_count)
    glb_cell = NOT_AVAILABLE if cov.glb_count is None else fraction(cov.glb_count, cov.expected_stages)
    return "| {} | `{}` | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
        index,
        md_cell(slot.get("modelName", "")),
        md_cell(slot.get("name", "")),
        md_cell(slot.get("type", "")),
        blueprint_cell,
        kits_cell,
        stages_cell,
        glb_cell,
        fraction(cov.uploaded_stages, cov.assets_stage_count),
        fraction(cov.harvested_stages, cov.assets_stage_count),
        "yes" if cov.template else NONE,
    )


def summarize(rows: list[Coverage]) -> dict[str, int]:
    return {
        "slots": len(rows),
        "blueprints": sum(1 for r in rows if r.blueprint is not None and not r.blueprint.problems),
        "uploaded": sum(1 for r in rows if r.is_uploaded),
        "harvested": sum(1 for r in rows if r.is_harvested),
        "templates": sum(1 for r in rows if r.template),
    }


def summary_line(s: dict[str, int]) -> str:
    n = s["slots"]
    return (
        f"{s['blueprints']}/{n} blueprints, {s['uploaded']}/{n} uploaded, "
        f"{s['harvested']}/{n} harvested, {s['templates']}/{n} templated"
    )


def render(eras: list[dict], assets: dict | None) -> tuple[str, list[str]]:
    per_era = [collect(era, assets) for era in eras]
    per_era_props = [collect_props(era.get("name", "?"), assets) for era in eras]
    notes = [note for _, era_notes in per_era for note in era_notes]
    notes += [note for _, era_notes in per_era_props for note in era_notes]
    lines: list[str] = [
        "# Asset manifest",
        "",
        "Generated by `py tools/gen_asset_manifest.py` from `src/shared/Config/Eras/*.json`,",
        "`tools/testfit/blueprints/`, `assets/build/stages/`, `src/shared/Config/Assets.json` and",
        "`templates/`. Do not edit by hand -- rerun the script; `py tools/gen_asset_manifest.py --check`",
        "fails when this file is stale.",
        "",
        "## Pipeline and naming rule",
        "",
        "- Nothing is imported by hand (spec section 8). Each `modelName` travels blueprint -> merged",
        "  stage GLBs -> Open Cloud upload -> Studio harvest -> `templates/<Era>/<ModelName>.rbxmx`,",
        "  which Rojo maps to `ServerStorage/Assets/<Era>/<ModelName>`.",
        "- `<Era>` is the era config `name` (e.g. `OrbitalColony`); `<ModelName>` must equal the config",
        "  `modelName` **exactly** (PascalCase, no spaces) at every step.",
        "- `building` slots have five stages (0 on purchase, then L10 / L25 / L50 / L100); `unlock`,",
        "  `decor` and `monument` slots have one. VIP is a per-kit texture swap, not a second model.",
        "- A missing template, stage or id falls back to a placeholder part -- never an error.",
        "",
        "Columns: **Blueprint** -- `tools/testfit/blueprints/<Era>/<ModelName>.json` exists and parses",
        "(`invalid` = present but broken; `--check` prints why). **Kits** -- distinct kits the blueprint",
        "uses. **Stages** -- stages the blueprint defines (max `stage` + 1). **GLBs** -- merged stage",
        "meshes present under `assets/build/stages/` over the count the slot type expects (`n/a` when",
        "that gitignored tree is absent; `--check` ignores this column). **Uploaded** -- stages in",
        "`Assets.json` with a non-zero `modelAssetId`. **Harvested** -- stages whose every part has a",
        "non-zero `meshId`. **Template** -- `templates/<Era>/<ModelName>.rbxmx` exists.",
        "",
        "## Coverage",
        "",
        "| Era | Blueprints | Uploaded | Harvested | Templates |",
        "|-----|------------|----------|-----------|-----------|",
    ]
    totals = {"slots": 0, "blueprints": 0, "uploaded": 0, "harvested": 0, "templates": 0}
    for era, (rows, _) in zip(eras, per_era):
        s = summarize(rows)
        for key in totals:
            totals[key] += s[key]
        lines.append(
            "| {} — {} | {}/{} | {}/{} | {}/{} | {}/{} |".format(
                era.get("eraIndex", "?"),
                md_cell(era.get("displayName") or era.get("name", "?")),
                s["blueprints"],
                s["slots"],
                s["uploaded"],
                s["slots"],
                s["harvested"],
                s["slots"],
                s["templates"],
                s["slots"],
            )
        )
    lines += [
        "| **Total** | {}/{} | {}/{} | {}/{} | {}/{} |".format(
            totals["blueprints"],
            totals["slots"],
            totals["uploaded"],
            totals["slots"],
            totals["harvested"],
            totals["slots"],
            totals["templates"],
            totals["slots"],
        ),
        "",
    ]
    for era, (rows, _), (prop_rows, _) in zip(eras, per_era, per_era_props):
        display = era.get("displayName") or era.get("name", "?")
        name = era.get("name", "?")
        slots = era.get("slots", [])
        lines += [
            f"## Era {era.get('eraIndex', '?')} — {display}",
            "",
            f"Blueprints: `tools/testfit/blueprints/{name}/` -- templates: `templates/{name}/` -- "
            f"in game: `ServerStorage/Assets/{name}/`",
            "",
            f"Summary: {summary_line(summarize(rows))}",
            "",
            TABLE_HEADER,
            TABLE_RULE,
        ]
        for index, (slot, cov) in enumerate(zip(slots, rows), start=1):
            lines.append(render_row(index, slot, cov))
        lines.append("")
        if prop_rows:
            lines += [
                f"### Props — {display}",
                "",
                f"Blueprints: `tools/testfit/blueprints/{PROPS_DIRNAME}/{name}/` -- templates: "
                f"`templates/{PROPS_DIRNAME}/{name}/` -- in game: `ReplicatedStorage/Assets/Props/{name}/`",
                "",
                f"Summary: {summary_line(summarize([cov for _, cov in prop_rows]))}",
                "",
                TABLE_HEADER,
                TABLE_RULE,
            ]
            for index, (prop_name, cov) in enumerate(prop_rows, start=1):
                lines.append(render_row(index, {"modelName": prop_name, "name": NONE, "type": PROP_TYPE}, cov))
            lines.append("")
    lines += ["## Totals", "", f"{totals['slots']} models: {summary_line(totals)}", ""]
    return "\n".join(lines), notes


def mask_volatile(text: str) -> str:
    """Blank the GLBs cell of every table row so --check does not depend on the
    gitignored assets/build tree being present on this machine."""
    masked: list[str] = []
    for line in text.split("\n"):
        cells = line.split("|")
        if line.startswith("| ") and len(cells) == ROW_CELL_COUNT and cells[1].strip().isdigit():
            cells[GLB_CELL_INDEX] = " * "
            line = "|".join(cells)
        masked.append(line)
    return "\n".join(masked)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Generate docs/ASSET_MANIFEST.md (asset coverage per era) from the era configs.",
        epilog="Run from anywhere; paths resolve relative to the repo root.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate the era configs and blueprints and fail if the committed manifest is stale",
    )
    args = parser.parse_args(argv)

    eras = load_eras()
    if not eras:
        print(f"no era configs found in {ERAS_DIR}")
        return 1
    text, notes = render(eras, load_assets_config())
    blueprint_problems = [note for note in notes if not note.startswith(WARNING_PREFIX)]
    warnings = [note for note in notes if note.startswith(WARNING_PREFIX)]

    if args.check:
        problems = validate(eras) + blueprint_problems
        if MANIFEST_PATH.exists():
            committed = MANIFEST_PATH.read_text(encoding="utf-8")
            if mask_volatile(committed) != mask_volatile(text):
                problems.append(
                    f"{MANIFEST_PATH.relative_to(REPO_ROOT)} is stale -- "
                    "rerun py tools/gen_asset_manifest.py"
                )
        else:
            problems.append(f"{MANIFEST_PATH.relative_to(REPO_ROOT)} is missing")
        for line in warnings:
            print(line)
        for line in problems:
            print(line)
        if problems:
            print(f"CHECK: FAIL -- {len(problems)} problem(s)")
            return 1
        print("CHECK: PASS -- configs valid, manifest up to date")
        return 0

    with open(MANIFEST_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    total = sum(len(era.get("slots", [])) for era in eras)
    print(f"wrote {MANIFEST_PATH.relative_to(REPO_ROOT)}: {len(eras)} eras, {total} models")
    for line in validate(eras) + blueprint_problems:
        print(WARNING_PREFIX, line)
    for line in warnings:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
