#!/usr/bin/env python
"""Generate the building templates Rojo builds into ServerStorage.Assets from Assets.json.

    py tools/assets/gen_templates.py           # (re)write templates/<Era>/<ModelName>.rbxmx
    py tools/assets/gen_templates.py --check   # regenerate in memory, diff against disk, exit 1 if stale

Template shape (frozen in INTERFACES.md "M7 contracts"):

    Model "<ModelName>"            PrimaryPart = Base
      Part "Base"                  1 x 0.2 x 1 at the origin, invisible, anchored, no collision/query/touch
      Model "Stage0" .. "Stage4"   one per stage whose every part has been harvested
        MeshPart "<kit>"           MeshId/TextureID from Assets.json, Size = harvested size,
                                   CFrame = harvested offset, anchored, CanCollide, Box collision

A template is only written when stage 0 is fully harvested (mesh ids non-zero); a later stage
that is not yet harvested is left out and PlotService falls back to the highest present stage.
Property names and encodings are exactly what `rojo build -o x.rbxmx` emits for the same
instances (rbx-dom canonical: MeshContent/TextureContent with <uri>, `size`, Color3uint8), so a
round trip through Rojo is byte-stable. MeshId is not scriptable at runtime, which is why these
are files. Output is deterministic; stray .rbxmx files under templates/ that this run would not
produce are removed (or reported by --check).
"""

from __future__ import annotations

import argparse
import os
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import assets_config as cfg  # noqa: E402

TEMPLATES_DIR = os.path.join(cfg.REPO_ROOT, "templates")
BASE_SIZE = (1.0, 0.2, 1.0)
COLLISION_FIDELITY_BOX = 2
MATERIAL_PLASTIC = 256
COLOR_WHITE = 16777215  # Color3uint8 packing of (255, 255, 255)


def log(msg: str) -> None:
    print(f"[templates] {msg}", flush=True)


def num(v: float) -> str:
    v = round(float(v), 4)
    if v == 0:
        return "0"
    text = f"{v:.4f}".rstrip("0").rstrip(".")
    return text


def vector3(name: str, v, indent: str) -> list[str]:
    return [
        f'{indent}<Vector3 name="{name}">',
        f"{indent}  <X>{num(v[0])}</X>",
        f"{indent}  <Y>{num(v[1])}</Y>",
        f"{indent}  <Z>{num(v[2])}</Z>",
        f"{indent}</Vector3>",
    ]


def cframe(position, indent: str) -> list[str]:
    lines = [f'{indent}<CoordinateFrame name="CFrame">']
    lines += [f"{indent}  <X>{num(position[0])}</X>", f"{indent}  <Y>{num(position[1])}</Y>", f"{indent}  <Z>{num(position[2])}</Z>"]
    for row in range(3):
        for col in range(3):
            lines.append(f"{indent}  <R{row}{col}>{1 if row == col else 0}</R{row}{col}>")
    lines.append(f"{indent}</CoordinateFrame>")
    return lines


class Referents:
    def __init__(self):
        self.n = 0

    def next(self) -> str:
        ref = f"RBX{self.n}"
        self.n += 1
        return ref


def mesh_part_xml(part: dict, refs: Referents, indent: str) -> list[str]:
    p = indent + "    "
    lines = [f'{indent}<Item class="MeshPart" referent="{refs.next()}">', f"{indent}  <Properties>"]
    lines.append(f'{p}<string name="Name">{escape(str(part["kit"]))}</string>')
    lines.append(f'{p}<bool name="Anchored">true</bool>')
    lines += cframe(part.get("offset", [0, 0, 0]), p)
    lines.append(f'{p}<bool name="CanCollide">true</bool>')
    lines.append(f'{p}<bool name="CanTouch">false</bool>')
    lines.append(f'{p}<token name="CollisionFidelity">{COLLISION_FIDELITY_BOX}</token>')
    lines.append(f'{p}<Color3uint8 name="Color3uint8">{COLOR_WHITE}</Color3uint8>')
    # InitialSize = Size = the mesh's native size (the scale is baked into the GLB), so the
    # engine's Size/InitialSize scale factor is 1 whichever of the two it trusts on load.
    lines += vector3("InitialSize", part["size"], p)
    lines.append(f'{p}<token name="Material">{MATERIAL_PLASTIC}</token>')
    lines.append(f'{p}<Content name="MeshContent">')
    lines.append(f"{p}  <uri>rbxassetid://{int(part['meshId'])}</uri>")
    lines.append(f"{p}</Content>")
    lines += vector3("size", part["size"], p)
    if int(part.get("imageId", 0)) != 0:
        lines.append(f'{p}<Content name="TextureContent">')
        lines.append(f"{p}  <uri>rbxassetid://{int(part['imageId'])}</uri>")
        lines.append(f"{p}</Content>")
    lines += [f"{indent}  </Properties>", f"{indent}</Item>"]
    return lines


def template_xml(model: str, stages: list[tuple[int, list[dict]]]) -> str:
    refs = Referents()
    root_ref = refs.next()
    base_ref = refs.next()
    lines = [
        '<roblox version="4">',
        f'  <Item class="Model" referent="{root_ref}">',
        "    <Properties>",
        f'      <string name="Name">{escape(model)}</string>',
        '      <bool name="NeedsPivotMigration">false</bool>',
        f'      <Ref name="PrimaryPart">{base_ref}</Ref>',
        "    </Properties>",
        f'    <Item class="Part" referent="{base_ref}">',
        "      <Properties>",
        '        <string name="Name">Base</string>',
        '        <bool name="Anchored">true</bool>',
    ]
    lines += cframe((0, 0, 0), "        ")
    lines += [
        '        <bool name="CanCollide">false</bool>',
        '        <bool name="CanQuery">false</bool>',
        '        <bool name="CanTouch">false</bool>',
    ]
    lines += vector3("size", BASE_SIZE, "        ")
    lines += ['        <float name="Transparency">1</float>', "      </Properties>", "    </Item>"]
    for index, parts in stages:
        lines += [
            f'    <Item class="Model" referent="{refs.next()}">',
            "      <Properties>",
            f'        <string name="Name">Stage{index}</string>',
            '        <bool name="NeedsPivotMigration">false</bool>',
            "      </Properties>",
        ]
        for part in parts:
            lines += mesh_part_xml(part, refs, "      ")
        lines.append("    </Item>")
    lines += ["  </Item>", "</roblox>"]
    return "\n".join(lines) + "\n"


def generate(assets: dict) -> tuple[dict[str, str], list[str]]:
    """relative path -> xml, plus notes about what was skipped and why."""
    out: dict[str, str] = {}
    notes: list[str] = []
    for era, models in assets.get("eras", {}).items():
        for model, entry in models.items():
            stages: list[tuple[int, list[dict]]] = []
            for index, stage in enumerate(entry.get("stages") or []):
                if int(stage.get("modelAssetId", 0)) == 0:
                    continue
                if not cfg.stage_harvested(stage):
                    notes.append(f"{era}/{model} S{index}: uploaded but not harvested; stage left out")
                    continue
                stages.append((index, stage["parts"]))
            if not stages:
                continue
            if stages[0][0] != 0:
                notes.append(f"{era}/{model}: stage 0 is not harvested; no template")
                continue
            out[f"{era}/{model}.rbxmx"] = template_xml(model, stages)
    return out, notes


def existing_templates() -> dict[str, str]:
    found: dict[str, str] = {}
    if not os.path.isdir(TEMPLATES_DIR):
        return found
    for era in sorted(os.listdir(TEMPLATES_DIR)):
        folder = os.path.join(TEMPLATES_DIR, era)
        if not os.path.isdir(folder):
            continue
        for name in sorted(os.listdir(folder)):
            if name.endswith(".rbxmx"):
                with open(os.path.join(folder, name), "r", encoding="utf-8") as fh:
                    found[f"{era}/{name}"] = fh.read()
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if templates/ differs from what Assets.json produces")
    args = parser.parse_args(argv)

    assets = cfg.load_assets() if os.path.isfile(cfg.ASSETS_PATH) else cfg.new_assets()
    wanted, notes = generate(assets)
    for note in notes:
        log(note)
    on_disk = existing_templates()

    if args.check:
        problems = []
        for rel, xml in wanted.items():
            if rel not in on_disk:
                problems.append(f"templates/{rel} is missing")
            elif on_disk[rel] != xml:
                problems.append(f"templates/{rel} is stale")
        for rel in on_disk:
            if rel not in wanted:
                problems.append(f"templates/{rel} has no harvested entry in Assets.json (stray)")
        for line in problems:
            print(line)
        if problems:
            print(f"CHECK: FAIL -- {len(problems)} problem(s); rerun py tools/assets/gen_templates.py")
            return 1
        print(f"CHECK: PASS -- {len(wanted)} template(s) up to date")
        return 0

    written = unchanged = 0
    for rel, xml in wanted.items():
        path = os.path.join(TEMPLATES_DIR, rel)
        if on_disk.get(rel) == xml:
            unchanged += 1
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(xml)
        written += 1
        log(f"wrote templates/{rel}")
    removed = 0
    for rel in on_disk:
        if rel not in wanted:
            os.remove(os.path.join(TEMPLATES_DIR, rel))
            removed += 1
            log(f"removed stray templates/{rel}")
    if os.path.isdir(TEMPLATES_DIR):
        for era in os.listdir(TEMPLATES_DIR):
            folder = os.path.join(TEMPLATES_DIR, era)
            if os.path.isdir(folder) and not os.listdir(folder):
                os.rmdir(folder)  # Rojo maps the folder tree; an empty era folder is just clutter
    log(f"{len(wanted)} template(s): {written} written, {unchanged} unchanged, {removed} removed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
