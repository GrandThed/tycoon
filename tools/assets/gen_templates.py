#!/usr/bin/env python
"""Generate the building templates Rojo builds into ServerStorage.Assets from Assets.json.

    py tools/assets/gen_templates.py           # (re)write templates/<Era>/<ModelName>.rbxmx
    py tools/assets/gen_templates.py --props   # (re)write templates/_props/<Era>/<PropName>.rbxmx
    py tools/assets/gen_templates.py --paths   # (re)write templates/_paths/<Era>/<pieceId>.rbxmx
    py tools/assets/gen_templates.py --check   # regenerate all three trees in memory, diff against disk, exit 1 if stale

Template shape (frozen in INTERFACES.md "M7 contracts"):

    Model "<ModelName>"            PrimaryPart = Base
      Part "Base"                  1 x 0.2 x 1 at the origin, invisible, anchored, no collision/query/touch
      Model "Stage0" .. "Stage4"   one per stage whose every part has been harvested
        MeshPart "<kit>"           MeshId/TextureID from Assets.json, Size = harvested size,
                                   CFrame = the harvested offset put back through the importer's
                                   180 deg Y turn (see `harvested_cframe`), so the template's -Z is
                                   the blueprint's front; anchored, CanCollide, Box collision

A template is only written when stage 0 is fully harvested (mesh ids non-zero); a later stage
that is not yet harvested is left out and PlotService falls back to the highest present stage.
Property names and encodings are exactly what `rojo build -o x.rbxmx` emits for the same
instances (rbx-dom canonical: MeshContent/TextureContent with <uri>, `size`, Color3uint8), so a
round trip through Rojo is byte-stable. MeshId is not scriptable at runtime, which is why these
are files. Output is deterministic; stray .rbxmx files under templates/ that this run would not
produce are removed (or reported by --check).

City-dressing props (Assets.json `props`, INTERFACES.md "M9 contracts") use the same shape with
CanCollide, CanQuery and CanTouch false on every MeshPart, because nothing in the city dressing may
block a player or a prompt. They live under templates/_props/, which Rojo maps to
ReplicatedStorage.Assets.Props so clients can clone them; the building run never looks inside it.

Baked paths (Assets.json `paths`, INTERFACES.md "Wave 1d - baked paths") have their own shape,
under templates/_paths/ -> ReplicatedStorage.Assets.Paths:

    Model "<pieceId>"            WorldPivot identity, so PivotTo(plotFrame) places the piece
      MeshPart "Rim"             at paths.rimHeight above the plot top, rim texture
      MeshPart "Fill"            at paths.fillHeight, fill texture

Both are sealed (anchored, no collide/query/touch, no shadow, Box collision) and placed by the same
`harvested_cframe` as buildings and props. A piece is written only when both its meshes are
harvested and its era has both harvested image ids; otherwise the client falls back to the Parts
renderer.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import assets_config as cfg  # noqa: E402

TEMPLATES_DIR = os.path.join(cfg.REPO_ROOT, "templates")
CITY_DRESSING_PATH = os.path.join(cfg.REPO_ROOT, "src", "shared", "Config", "CityDressing.json")
PROPS_DIRNAME = "_props"
PATHS_DIRNAME = "_paths"
GROUP_DIRNAMES = {"props": PROPS_DIRNAME, "paths": PATHS_DIRNAME}
MATERIAL_SMOOTH_PLASTIC = 272
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


def coordinate_frame(name: str, position, indent: str, turned: bool = False) -> list[str]:
    """`turned` writes R00 = R22 = -1: the 180 deg turn about Y that undoes the importer's own."""
    lines = [f'{indent}<CoordinateFrame name="{name}">']
    lines += [f"{indent}  <X>{num(position[0])}</X>", f"{indent}  <Y>{num(position[1])}</Y>", f"{indent}  <Z>{num(position[2])}</Z>"]
    flip = -1 if turned else 1
    for row in range(3):
        for col in range(3):
            value = 0 if row != col else (flip if row in (0, 2) else 1)
            lines.append(f"{indent}  <R{row}{col}>{value}</R{row}{col}>")
    lines.append(f"{indent}</CoordinateFrame>")
    return lines


def cframe(position, indent: str) -> list[str]:
    return coordinate_frame("CFrame", position, indent)


def harvested_cframe(offset, indent: str, lift: float = 0.0) -> list[str]:
    """The CFrame of one harvested mesh relative to the template's anchor.

    Every model the Open Cloud glTF import produces arrives turned 180 deg about Y, because the
    importer converts the glTF +Z-forward convention to Roblox's -Z-forward one. So a harvested
    `offset` is the blueprint's offset with x and z negated, and the mesh inside points backwards.
    Negating the offset back and turning the part by the same 180 deg undoes both at once: the
    part lands at its blueprint coordinate with the blueprint's -Z front facing the template's -Z,
    which is the front/pad side every consumer assumes (INTERFACES "Template shape"). Buildings,
    props and baked path pieces all go through here; `lift` is the path layers' height above the
    plot top and is 0 for the rest.
    """
    position = (-float(offset[0]), float(offset[1]) + lift, -float(offset[2]))
    return coordinate_frame("CFrame", position, indent, turned=True)


class Referents:
    def __init__(self):
        self.n = 0

    def next(self) -> str:
        ref = f"RBX{self.n}"
        self.n += 1
        return ref


def mesh_part_xml(part: dict, refs: Referents, indent: str, prop: bool) -> list[str]:
    p = indent + "    "
    lines = [f'{indent}<Item class="MeshPart" referent="{refs.next()}">', f"{indent}  <Properties>"]
    lines.append(f'{p}<string name="Name">{escape(str(part["kit"]))}</string>')
    lines.append(f'{p}<bool name="Anchored">true</bool>')
    lines += harvested_cframe(part.get("offset", [0, 0, 0]), p)
    if prop:
        lines.append(f'{p}<bool name="CanCollide">false</bool>')
        lines.append(f'{p}<bool name="CanQuery">false</bool>')
    else:
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


def template_xml(model: str, stages: list[tuple[int, list[dict]]], prop: bool = False) -> str:
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
            lines += mesh_part_xml(part, refs, "      ", prop)
        lines.append("    </Item>")
    lines += ["  </Item>", "</roblox>"]
    return "\n".join(lines) + "\n"


def path_heights() -> tuple[float, float]:
    """The rim and fill heights above the plot top come from CityDressing.json `paths`, so the
    template and the client never keep two copies of them."""
    with open(CITY_DRESSING_PATH, "r", encoding="utf-8") as fh:
        paths = json.load(fh).get("paths") or {}
    return float(paths.get("rimHeight", 0)), float(paths.get("fillHeight", 0))


def path_mesh_xml(name: str, mesh: dict, image_id: int, height: float, refs: Referents, indent: str) -> list[str]:
    """One sealed, textured path MeshPart, placed by `harvested_cframe` like every other harvested
    mesh: undoing the importer's turn puts the piece exactly where it was baked, in plot-local
    studs, which is what keeps the world-planar UVs aligned between overlapping pieces."""
    p = indent + "    "
    lines = [f'{indent}<Item class="MeshPart" referent="{refs.next()}">', f"{indent}  <Properties>"]
    lines.append(f'{p}<string name="Name">{name}</string>')
    lines.append(f'{p}<bool name="Anchored">true</bool>')
    lines += harvested_cframe(mesh.get("offset") or [0, 0, 0], p, height)
    lines.append(f'{p}<bool name="CanCollide">false</bool>')
    lines.append(f'{p}<bool name="CanQuery">false</bool>')
    lines.append(f'{p}<bool name="CanTouch">false</bool>')
    lines.append(f'{p}<bool name="CastShadow">false</bool>')
    lines.append(f'{p}<token name="CollisionFidelity">{COLLISION_FIDELITY_BOX}</token>')
    lines.append(f'{p}<Color3uint8 name="Color3uint8">{COLOR_WHITE}</Color3uint8>')
    lines += vector3("InitialSize", mesh["size"], p)
    lines.append(f'{p}<token name="Material">{MATERIAL_SMOOTH_PLASTIC}</token>')
    lines.append(f'{p}<Content name="MeshContent">')
    lines.append(f"{p}  <uri>rbxassetid://{int(mesh['meshId'])}</uri>")
    lines.append(f"{p}</Content>")
    lines += vector3("size", mesh["size"], p)
    lines.append(f'{p}<Content name="TextureContent">')
    lines.append(f"{p}  <uri>rbxassetid://{int(image_id)}</uri>")
    lines.append(f"{p}</Content>")
    lines += [f"{indent}  </Properties>", f"{indent}</Item>"]
    return lines


def path_template_xml(piece_id: str, piece: dict, images: dict, heights: tuple[float, float]) -> str:
    refs = Referents()
    lines = [
        '<roblox version="4">',
        f'  <Item class="Model" referent="{refs.next()}">',
        "    <Properties>",
        f'      <string name="Name">{escape(piece_id)}</string>',
        '      <bool name="NeedsPivotMigration">false</bool>',
    ]
    # An identity WorldPivot (no PrimaryPart) means the client can clone the piece and PivotTo the
    # plot frame: the MeshPart CFrames are already plot-local.
    lines += coordinate_frame("WorldPivot", (0, 0, 0), "      ")
    lines.append("    </Properties>")
    for name, layer, height in (("Rim", "rim", heights[0]), ("Fill", "fill", heights[1])):
        lines += path_mesh_xml(name, piece[layer], images[layer], height, refs, "    ")
    lines += ["  </Item>", "</roblox>"]
    return "\n".join(lines) + "\n"


def generate_paths(assets: dict) -> tuple[dict[str, str], list[str]]:
    heights = path_heights()
    out: dict[str, str] = {}
    notes: list[str] = []
    for era, entry in (assets.get(cfg.PATHS_KEY) or {}).items():
        images = {layer: int(entry.get(f"{layer}ImageId", 0)) for layer in cfg.PATH_LAYERS}
        missing = [layer for layer, image_id in images.items() if image_id == 0]
        if missing:
            notes.append(f"paths/{era}: no harvested {', '.join(missing)} image id; no templates (the plot uses the Parts renderer)")
            continue
        for piece_id, piece in sorted((entry.get("pieces") or {}).items()):
            if not cfg.path_piece_harvested(piece):
                notes.append(f"paths/{era}/{piece_id}: uploaded but not harvested; piece left out")
                continue
            out[f"{era}/{piece_id}.rbxmx"] = path_template_xml(piece_id, piece, images, heights)
    return out, notes


def generate(assets: dict, group: str = "eras") -> tuple[dict[str, str], list[str]]:
    """relative path -> xml, plus notes about what was skipped and why; group "props" for props."""
    if group == "paths":
        return generate_paths(assets)
    prop = group == "props"
    prefix = f"{group}/" if prop else ""
    out: dict[str, str] = {}
    notes: list[str] = []
    for era, models in assets.get(group, {}).items():
        for model, entry in models.items():
            stages: list[tuple[int, list[dict]]] = []
            for index, stage in enumerate(entry.get("stages") or []):
                if int(stage.get("modelAssetId", 0)) == 0:
                    continue
                if not cfg.stage_harvested(stage):
                    notes.append(f"{prefix}{era}/{model} S{index}: uploaded but not harvested; stage left out")
                    continue
                stages.append((index, stage["parts"]))
            if not stages:
                continue
            if stages[0][0] != 0:
                notes.append(f"{prefix}{era}/{model}: stage 0 is not harvested; no template")
                continue
            out[f"{era}/{model}.rbxmx"] = template_xml(model, stages, prop)
    return out, notes


class Tree:
    """One template root: buildings in templates/, props in templates/_props/, baked path pieces
    in templates/_paths/."""

    def __init__(self, group: str):
        self.group = group
        dirname = GROUP_DIRNAMES.get(group)
        self.root = os.path.join(TEMPLATES_DIR, dirname) if dirname else TEMPLATES_DIR
        self.label = f"templates/{dirname}" if dirname else "templates"


def existing_templates(tree: Tree) -> dict[str, str]:
    found: dict[str, str] = {}
    if not os.path.isdir(tree.root):
        return found
    for era in sorted(os.listdir(tree.root)):
        folder = os.path.join(tree.root, era)
        if not os.path.isdir(folder) or (tree.group == "eras" and era in GROUP_DIRNAMES.values()):
            continue
        for name in sorted(os.listdir(folder)):
            if name.endswith(".rbxmx"):
                with open(os.path.join(folder, name), "r", encoding="utf-8") as fh:
                    found[f"{era}/{name}"] = fh.read()
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="fail if templates/ differs from what Assets.json produces")
    parser.add_argument("--props", action="store_true", help="write city-dressing prop templates to templates/_props/")
    parser.add_argument("--paths", action="store_true", help="write baked path templates to templates/_paths/")
    parser.add_argument("--assets-json", help="read this Assets.json instead of src/shared/Config/Assets.json")
    args = parser.parse_args(argv)
    cfg.use_assets_path(args.assets_json)

    assets = cfg.load_assets() if os.path.isfile(cfg.ASSETS_PATH) else cfg.new_assets()
    if args.check:
        return check(assets)
    if args.props and args.paths:
        print("pass at most one of --props and --paths")
        return 1
    group = "props" if args.props else ("paths" if args.paths else "eras")
    return write(assets, Tree(group))


def check(assets: dict) -> int:
    problems = []
    total = 0
    for tree in (Tree("eras"), Tree("props"), Tree("paths")):
        wanted, notes = generate(assets, tree.group)
        for note in notes:
            log(note)
        on_disk = existing_templates(tree)
        total += len(wanted)
        for rel, xml in wanted.items():
            if rel not in on_disk:
                problems.append(f"{tree.label}/{rel} is missing")
            elif on_disk[rel] != xml:
                problems.append(f"{tree.label}/{rel} is stale")
        for rel in on_disk:
            if rel not in wanted:
                problems.append(f"{tree.label}/{rel} has no harvested entry in Assets.json (stray)")
    for line in problems:
        print(line)
    if problems:
        hints = [
            f" ({flag} for {Tree(group).label})"
            for group, flag in (("props", "--props"), ("paths", "--paths"))
            if any(line.startswith(Tree(group).label + "/") for line in problems)
        ]
        print(f"CHECK: FAIL -- {len(problems)} problem(s); rerun py tools/assets/gen_templates.py{''.join(hints)}")
        return 1
    print(f"CHECK: PASS -- {total} template(s) up to date")
    return 0


def write(assets: dict, tree: Tree) -> int:
    wanted, notes = generate(assets, tree.group)
    for note in notes:
        log(note)
    on_disk = existing_templates(tree)
    written = unchanged = 0
    for rel, xml in wanted.items():
        path = os.path.join(tree.root, rel)
        if on_disk.get(rel) == xml:
            unchanged += 1
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(xml)
        written += 1
        log(f"wrote {tree.label}/{rel}")
    removed = 0
    for rel in on_disk:
        if rel not in wanted:
            os.remove(os.path.join(tree.root, rel))
            removed += 1
            log(f"removed stray {tree.label}/{rel}")
    if os.path.isdir(tree.root):
        for era in os.listdir(tree.root):
            folder = os.path.join(tree.root, era)
            if os.path.isdir(folder) and not os.listdir(folder):
                os.rmdir(folder)  # Rojo maps the folder tree; an empty era folder is just clutter
        if tree.group in GROUP_DIRNAMES and not os.listdir(tree.root):
            os.rmdir(tree.root)
    kind = {"props": "prop ", "paths": "path "}.get(tree.group, "")
    log(f"{len(wanted)} {kind}template(s): {written} written, {unchanged} unchanged, {removed} removed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
