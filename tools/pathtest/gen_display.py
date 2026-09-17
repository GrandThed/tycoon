#!/usr/bin/env python
"""Write the Studio display for the path look test: tools/pathtest/out/PathTest.rbxmx.

    py tools/pathtest/gen_display.py [--assets-json <ids.json>] [--out <file.rbxmx>]

default.project.json maps the file (optionally) to Workspace.PathTest, so `rojo build` puts it in
the world. A variant whose assets are not harvested yet is left out (a MeshPart with MeshId 0 is an
invisible box and would waste Ben's look); if no variant is complete the file is not written at all.

Shape:
    Model PathTest
      Model Variant_A / _B / _C / _C2 / _C3      one per candidate, 50-stud bases 10 studs apart
        Part Base        50 x 0.2 x 50 grass base on the Ground part (top at Y -0.8), collidable
        Part Sign        invisible anchor at the hub-side edge holding a BillboardGui label
        MeshPart Lane, Spur (A, B, C)             round 1: UVs along the ribbon, alpha rim
          A, C: TextureContent; B: a SurfaceAppearance child (ColorMap/NormalMap/RoughnessMap,
          AlphaMode Transparency)
        MeshPart Fill_Lane, Fill_Spur (C2)        round 2: world-planar UVs, opaque texture, and
        MeshPart Rim_* + Fill_* (C3)              the irregular edge cut into the mesh outline
    every path MeshPart: anchored, no collide/query/touch, no shadow

Heights above the base top: C2 puts both fills on ONE plane (Y_C2), which is the point of C2 - with
planar UVs and an opaque texture, a coplanar overlap is invisible because both surfaces resolve to
the same texel and the same up normal, whatever the depth test does. C3 puts every rim at Y_C3_RIM
and every fill Y_C3_FILL - Y_C3_RIM = 0.05 studs above it, so the lane's rim across the spur mouth
is hidden under the spur fill. 0.05 studs is roughly 40x Roblox's depth resolution at 45 studs
(about 0.0012 studs with a 24-bit buffer and a 0.1 stud near plane), so it cannot z-fight, while
staying far below what a player could read as a step.

The row sits on the -Z side of spawn: five bases centred on X = 0 span X -145..145 at Z -61, so the
farthest corner is 168 studs out - clear of the hub (radius 30) and of the plot ring, whose inner
corners are about 217 studs out (nearest one at about (211, -79)). Property names and encodings
match tools/assets/gen_templates.py and what `rojo build` itself emits (MeshContent/TextureContent,
ColorMapContent/NormalMapContent/RoughnessMapContent, FontFace).

Mesh placement: a MeshPart's Position is the centre of its mesh's bounding box, so each part goes at
(bbox centre from patch.json / planar.json - patch centre) on its base, with the variant's Y added
for the planar meshes (the round 1 meshes carry their own Y). The harvested offset must agree; a
disagreement is printed, because it would mean Roblox re-origined the upload.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import os
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "assets"))
from gen_templates import cframe, num, vector3  # noqa: E402

ASSETS_JSON = os.path.join(HERE, "pathtest_assets.json")
PATCH_JSON = os.path.join(HERE, "out", "patch.json")
PLANAR_JSON = os.path.join(HERE, "out", "planar.json")
OUT_FILE = os.path.join(HERE, "out", "PathTest.rbxmx")
TEMPLATE = os.path.join(REPO, "templates", "Village", "{model}.rbxmx")
BUILDING_STAGE = "Stage4"

DISPLAY_Z = -61.0  # base centres; the hub-side edge is 36 studs from spawn
BASE_SIZE = 50.0
BASE_GAP = 10.0
BASE_THICKNESS = 0.2
GROUND_TOP = -1.0  # PlotService Ground part top
BASE_TOP = GROUND_TOP + BASE_THICKNESS
GRASS = (106, 127, 63)
MATERIAL_SMOOTH_PLASTIC = 272
COLLISION_FIDELITY_BOX = 2
ALPHA_MODE_TRANSPARENCY = 1
Y_C2 = 0.05  # C2: both fills, one plane
Y_C3_RIM = 0.02
Y_C3_FILL = 0.07

# layers: (mesh name in the ids JSON, mesh name in the geometry JSON, texture key, Y above the base)
VARIANTS = {
    "A": {
        "label": "A  solid core (TextureID)",
        "geometry": "patch",
        "layers": [("Lane", "Lane", "A_color", None), ("Spur", "Spur", "A_color", None)],
    },
    "B": {
        "label": "B  SurfaceAppearance (colour + normal + roughness)",
        "geometry": "patch",
        "layers": [("Lane", "Lane", None, None), ("Spur", "Spur", None, None)],
        "surface": ("B_color", "B_normal", "B_rough"),
    },
    "C": {
        "label": "C  stylised (TextureID)",
        "geometry": "patch",
        "layers": [("Lane", "Lane", "C_color", None), ("Spur", "Spur", "C_color", None)],
    },
    "C2": {
        "label": "C2 planar",
        "geometry": "planar",
        "layers": [("Fill_Lane", "Fill_Lane", "P_fill", Y_C2), ("Fill_Spur", "Fill_Spur", "P_fill", Y_C2)],
    },
    "C3": {
        "label": "C3 planar + rim",
        "geometry": "planar",
        "layers": [
            ("Rim_Lane", "Rim_Lane", "P_rim", Y_C3_RIM),
            ("Rim_Spur", "Rim_Spur", "P_rim", Y_C3_RIM),
            ("Fill_Lane", "Fill_Lane", "P_fill", Y_C3_FILL),
            ("Fill_Spur", "Fill_Spur", "P_fill", Y_C3_FILL),
        ],
    },
}


class Refs:
    def __init__(self):
        self.n = 0

    def next(self) -> str:
        self.n += 1
        return f"PT{self.n}"


def color3uint8(rgb) -> int:
    return (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]


def content(name: str, asset_id: int, indent: str) -> list[str]:
    return [f'{indent}<Content name="{name}">', f"{indent}  <uri>rbxassetid://{int(asset_id)}</uri>", f"{indent}</Content>"]


def part_xml(refs, name, position, size, indent, collide, transparency=0.0, rgb=None, children=()):
    p = indent + "    "
    lines = [f'{indent}<Item class="Part" referent="{refs.next()}">', f"{indent}  <Properties>"]
    lines.append(f'{p}<string name="Name">{escape(name)}</string>')
    lines.append(f'{p}<bool name="Anchored">true</bool>')
    lines += cframe(position, p)
    lines.append(f'{p}<bool name="CanCollide">{"true" if collide else "false"}</bool>')
    if not collide:
        lines.append(f'{p}<bool name="CanQuery">false</bool>')
    lines.append(f'{p}<bool name="CanTouch">false</bool>')
    if rgb is not None:
        lines.append(f'{p}<Color3uint8 name="Color3uint8">{color3uint8(rgb)}</Color3uint8>')
    lines += vector3("size", size, p)
    lines.append(f'{p}<token name="Material">{MATERIAL_SMOOTH_PLASTIC}</token>')
    if transparency:
        lines.append(f'{p}<float name="Transparency">{num(transparency)}</float>')
    lines.append(f"{indent}  </Properties>")
    for child in children:
        lines += child
    lines.append(f"{indent}</Item>")
    return lines


def billboard_xml(refs, text, indent):
    p = indent + "    "
    q = indent + "      "
    return [
        f'{indent}<Item class="BillboardGui" referent="{refs.next()}">',
        f"{indent}  <Properties>",
        f'{p}<string name="Name">Label</string>',
        f'{p}<float name="LightInfluence">0</float>',
        f'{p}<float name="MaxDistance">500</float>',
        f'{p}<UDim2 name="Size">',
        f"{p}  <XS>24</XS>",
        f"{p}  <XO>0</XO>",
        f"{p}  <YS>3</YS>",
        f"{p}  <YO>0</YO>",
        f"{p}</UDim2>",
        f'{p}<Vector3 name="StudsOffset">',
        f"{p}  <X>0</X>",
        f"{p}  <Y>5</Y>",
        f"{p}  <Z>0</Z>",
        f"{p}</Vector3>",
        f"{indent}  </Properties>",
        f'{indent}  <Item class="TextLabel" referent="{refs.next()}">',
        f"{indent}    <Properties>",
        f'{q}<string name="Name">Text</string>',
        f'{q}<float name="BackgroundTransparency">1</float>',
        f'{q}<Font name="FontFace">',
        f"{q}  <Family>",
        f"{q}    <url>rbxasset://fonts/families/GothamSSm.json</url>",
        f"{q}  </Family>",
        f"{q}  <Weight>700</Weight>",
        f"{q}  <Style>Normal</Style>",
        f"{q}</Font>",
        f'{q}<UDim2 name="Size">',
        f"{q}  <XS>1</XS>",
        f"{q}  <XO>0</XO>",
        f"{q}  <YS>1</YS>",
        f"{q}  <YO>0</YO>",
        f"{q}</UDim2>",
        f'{q}<string name="Text">{escape(text)}</string>',
        f'{q}<Color3 name="TextColor3">',
        f"{q}  <R>1</R>",
        f"{q}  <G>1</G>",
        f"{q}  <B>1</B>",
        f"{q}</Color3>",
        f'{q}<bool name="TextScaled">true</bool>',
        f'{q}<float name="TextStrokeTransparency">0</float>',
        f"{indent}    </Properties>",
        f"{indent}  </Item>",
        f"{indent}</Item>",
    ]


def surface_appearance_xml(refs, images, keys, indent):
    p = indent + "    "
    colour, normal, rough = keys
    lines = [f'{indent}<Item class="SurfaceAppearance" referent="{refs.next()}">', f"{indent}  <Properties>"]
    lines.append(f'{p}<string name="Name">SurfaceAppearance</string>')
    lines.append(f'{p}<token name="AlphaMode">{ALPHA_MODE_TRANSPARENCY}</token>')
    lines += content("ColorMapContent", images[colour]["imageId"], p)
    lines += content("NormalMapContent", images[normal]["imageId"], p)
    lines += content("RoughnessMapContent", images[rough]["imageId"], p)
    lines += [f"{indent}  </Properties>", f"{indent}</Item>"]
    return lines


def path_mesh_xml(refs, name, model, position, indent, image_id=None, surface=None, images=None):
    p = indent + "    "
    lines = [f'{indent}<Item class="MeshPart" referent="{refs.next()}">', f"{indent}  <Properties>"]
    lines.append(f'{p}<string name="Name">{name}</string>')
    lines.append(f'{p}<bool name="Anchored">true</bool>')
    # The harvest reports each mesh's offset as (-x, y, -z) of its glTF bbox centre: the Open Cloud
    # import turns the geometry 180° about Y. Turning the part back by 180° puts every vertex at its
    # patch coordinate, so the spur's flared end lands on the lane. It also keeps the planar UVs
    # aligned between pieces, because every piece is turned the same way.
    for line in cframe(position, p):
        if "<R00>" in line or "<R22>" in line:
            line = line.replace(">1<", ">-1<")
        lines.append(line)
    lines.append(f'{p}<bool name="CanCollide">false</bool>')
    lines.append(f'{p}<bool name="CanQuery">false</bool>')
    lines.append(f'{p}<bool name="CanTouch">false</bool>')
    lines.append(f'{p}<bool name="CastShadow">false</bool>')
    lines.append(f'{p}<token name="CollisionFidelity">{COLLISION_FIDELITY_BOX}</token>')
    lines.append(f'{p}<Color3uint8 name="Color3uint8">{color3uint8((255, 255, 255))}</Color3uint8>')
    # InitialSize = Size = the native mesh size, so the engine's scale factor is 1 (gen_templates.py)
    lines += vector3("InitialSize", model["size"], p)
    lines.append(f'{p}<token name="Material">{MATERIAL_SMOOTH_PLASTIC}</token>')
    lines += content("MeshContent", model["meshId"], p)
    lines += vector3("size", model["size"], p)
    if image_id:
        lines += content("TextureContent", image_id, p)
    lines.append(f"{indent}  </Properties>")
    if surface:
        lines += surface_appearance_xml(refs, images, surface, indent + "  ")
    lines.append(f"{indent}</Item>")
    return lines


def building_xml(refs, model_name, position, rotation_deg, indent):
    """Stage4 of the building template, posed like PlotService poses a slot: pivot at the slot
    position, turned by CFrame.Angles(0, rad(rotationY), 0). Only CFrame and referents change."""
    tree = ET.parse(TEMPLATE.format(model=model_name))
    stage = next((i for i in tree.getroot().iter("Item") if i.get("class") == "Model" and i.find("Properties/string[@name='Name']").text == BUILDING_STAGE), None)
    if stage is None:
        raise SystemExit(f"{model_name} template has no {BUILDING_STAGE}")
    a = math.radians(rotation_deg)
    ca, sa = math.cos(a), math.sin(a)
    rot = [[ca, 0.0, sa], [0.0, 1.0, 0.0], [-sa, 0.0, ca]]
    body = []
    for mesh in stage.findall("Item"):
        mesh = copy.deepcopy(mesh)
        mesh.set("referent", refs.next())
        cf = mesh.find("Properties/CoordinateFrame[@name='CFrame']")
        local = [float(cf.find(k).text) for k in ("X", "Y", "Z")]
        r = [[float(cf.find(f"R{i}{j}").text) for j in range(3)] for i in range(3)]
        world = [position[i] + sum(rot[i][k] * local[k] for k in range(3)) for i in range(3)]
        rr = [[sum(rot[i][k] * r[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
        for key, value in zip(("X", "Y", "Z"), world):
            cf.find(key).text = num(value)
        for i in range(3):
            for j in range(3):
                cf.find(f"R{i}{j}").text = num(rr[i][j])
        ET.indent(mesh, space="  ", level=len(indent) // 2 + 1)
        body.append(indent + "  " + ET.tostring(mesh, encoding="unicode").rstrip())
    return [
        f'{indent}<Item class="Model" referent="{refs.next()}">',
        f"{indent}  <Properties>",
        f'{indent}    <string name="Name">{escape(model_name)}</string>',
        f'{indent}    <bool name="NeedsPivotMigration">false</bool>',
        f"{indent}  </Properties>",
        *body,
        f"{indent}</Item>",
    ]


def variant_missing(ids: dict, spec: dict) -> list[str]:
    """What this variant still needs before it can be drawn."""
    missing = []
    for mesh_key, _, texture, _ in spec["layers"]:
        entry = ids["models"].get(mesh_key)
        if entry is None or not entry.get("meshId") or not entry.get("size"):
            missing.append(f"model {mesh_key}")
        if texture:
            image = ids["images"].get(texture)
            if image is None or not image.get("imageId"):
                missing.append(f"image {texture}")
    for key in spec.get("surface") or ():
        image = ids["images"].get(key)
        if image is None or not image.get("imageId"):
            missing.append(f"image {key}")
    return sorted(set(missing))


def base_x(variant: str) -> float:
    index = list(VARIANTS).index(variant)
    return (index - (len(VARIANTS) - 1) / 2) * (BASE_SIZE + BASE_GAP)


def build(ids: dict, geometry: dict, ready: list[str]) -> str:
    refs = Refs()
    patch = geometry["patch"]
    cx, _, cz = patch["patchCentre"]
    b = patch["building"]
    lines = ['<roblox version="4">', f'  <Item class="Model" referent="{refs.next()}">', "    <Properties>"]
    lines += ['      <string name="Name">PathTest</string>', '      <bool name="NeedsPivotMigration">false</bool>', "    </Properties>"]
    for variant in ready:
        spec = VARIANTS[variant]
        bx = base_x(variant)
        ind = "      "
        lines += [f'    <Item class="Model" referent="{refs.next()}">', "      <Properties>"]
        lines += [f'        <string name="Name">Variant_{variant}</string>', '        <bool name="NeedsPivotMigration">false</bool>', "      </Properties>"]
        lines += part_xml(refs, "Base", (bx, GROUND_TOP + BASE_THICKNESS / 2, DISPLAY_Z), (BASE_SIZE, BASE_THICKNESS, BASE_SIZE), ind, True, rgb=GRASS)
        sign = billboard_xml(refs, spec["label"], ind + "  ")
        lines += part_xml(refs, "Sign", (bx, BASE_TOP + 0.5, DISPLAY_Z + BASE_SIZE / 2 - 3), (1, 1, 1), ind, False, transparency=1, children=[sign])
        meshes = geometry[spec["geometry"]]["meshes"]
        for mesh_key, geom_key, texture, y in spec["layers"]:
            centre = meshes[geom_key]["centre"]
            pos = (bx + centre[0] - cx, BASE_TOP + centre[1] + (y or 0.0), DISPLAY_Z + centre[2] - cz)
            image_id = ids["images"][texture]["imageId"] if texture else None
            lines += path_mesh_xml(refs, mesh_key, ids["models"][mesh_key], pos, ind, image_id, spec.get("surface"), ids["images"])
        bpos = (bx + b["position"][0] - cx, BASE_TOP, DISPLAY_Z + b["position"][2] - cz)
        lines += building_xml(refs, b["model"], bpos, b["rotationY"], ind)
        lines.append("    </Item>")
    lines += ["  </Item>", "</roblox>"]
    return "\n".join(lines) + "\n"


def check_placement(ids: dict, geometry: dict) -> None:
    for variant, spec in VARIANTS.items():
        meshes = geometry[spec["geometry"]]["meshes"]
        for mesh_key, geom_key, _, _ in spec["layers"]:
            entry = ids["models"].get(mesh_key) or {}
            if not entry.get("meshId"):
                continue
            centre, got = meshes[geom_key]["centre"], entry.get("offset")
            # the importer's 180° turn negates x and z; the display part is turned back
            if got and max(abs(a + b) for a, b in zip(centre[0::2], got[0::2])) > 0.05:
                print(f"[pathtest] WARNING: {mesh_key} harvested offset {got} is not -(bbox centre) {centre}; placed by the bbox centre")
            size, got_size = meshes[geom_key]["size"], entry.get("size") or [0, 0, 0]
            if max(abs(a - b) for a, b in zip(size[::2], got_size[::2])) > 0.05:
                print(f"[pathtest] WARNING: {mesh_key} harvested size {got_size} != mesh bbox size {size}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--assets-json", default=ASSETS_JSON)
    parser.add_argument("--out", default=OUT_FILE)
    args = parser.parse_args(argv)
    with open(args.assets_json, encoding="utf-8") as fh:
        ids = json.load(fh)
    geometry = {}
    with open(PATCH_JSON, encoding="utf-8") as fh:
        geometry["patch"] = json.load(fh)
    with open(PLANAR_JSON, encoding="utf-8") as fh:
        geometry["planar"] = json.load(fh)

    ready = []
    for variant, spec in VARIANTS.items():
        missing = variant_missing(ids, spec)
        if missing:
            print(f"[pathtest] {variant} left out: not harvested yet: {', '.join(missing)}")
        else:
            ready.append(variant)
    if not ready:
        print("[pathtest] REFUSING to write PathTest.rbxmx: nothing is harvested")
        print("[pathtest] paste tools/pathtest/harvest_pathtest.luau in Studio, then run harvest_pathtest.py --file <output>")
        return 1
    check_placement(ids, geometry)
    xml = build(ids, geometry, ready)
    ET.fromstring(xml)  # never hand Rojo malformed XML
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(xml)
    places = ", ".join(f"{v} at X {base_x(v):g}" for v in ready)
    print(f"[pathtest] wrote {os.path.relpath(args.out, REPO)}: {places}, all at Z {DISPLAY_Z:g} (walk -Z from spawn)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
