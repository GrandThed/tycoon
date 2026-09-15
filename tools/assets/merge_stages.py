"""Merge a blueprint's pieces into one mesh per kit per growth stage and export GLBs for upload.

Runs inside Blender (headless):

    blender -b -P tools/assets/merge_stages.py -- --era Village [--model Tavern] [--out assets/build]

For every blueprint in tools/testfit/blueprints/<Era>/ (or just --model) and every stage the slot
has (5 for `building`, 1 otherwise; stages are additive), the pieces present at that stage are
placed exactly as tools/testfit/testfit.py places them, joined into ONE mesh per kit, scaled by
the blueprint's scale about the blueprint origin (bottom-centre of the footprint, front -Z) and
exported to assets/build/stages/<Era>/<ModelName>_S<n>.glb with one node, one material and one
embedded PNG per kit. A bounds sidecar assets/build/stages/<Era>/<ModelName>.json records
per-stage, per-kit extents in studs.

Kits whose materials are plain colour factors (no baseColorTexture) get the deterministic palette
texture from palette.py with their UVs moved onto the right swatch, because Roblox drops colour
factors on import. A textured kit with the odd colour-only primitive (fantasy-town-kit's fountain
water) has that primitive's UVs moved onto the nearest colour in the kit colormap instead.

Blueprint coordinates are glTF/Roblox (Y up, front -Z); Blender is Z up, so positions convert
with (x, y, z) -> (x, -z, y) and every reported bound converts back.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "testfit"))
import glbtools  # noqa: E402
import palette  # noqa: E402
from blueprint import STAGE_COUNT, Blueprint, BlueprintError, Piece, list_blueprints, load_blueprint  # noqa: E402

KITS_ROOT = os.path.join(REPO_ROOT, "assets", "kenney3d")
MODEL_DIRS = ("GLB format", "GLTF format")
ERAS_DIR = os.path.join(REPO_ROOT, "src", "shared", "Config", "Eras")
DEFAULT_OUT = os.path.join(REPO_ROOT, "assets", "build")
SINGLE_STAGE_TYPES = ("unlock", "decor", "monument")
# The rendered footprint frame tolerates this much overhang before it is worth a warning.
FOOTPRINT_EPS_STUDS = 0.05


def log(msg: str) -> None:
    print(f"[merge] {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"[merge] WARNING: {msg}", flush=True)


def gltf_to_blender(v) -> Vector:
    return Vector((v[0], -v[2], v[1]))


def blender_to_gltf(v) -> Vector:
    return Vector((v[0], v[2], -v[1]))


# --- Era config ------------------------------------------------------------------


def load_slot_types(era: str) -> dict[str, str]:
    """modelName -> slot type for the era, from src/shared/Config/Eras/*.json."""
    if not os.path.isdir(ERAS_DIR):
        warn(f"era config folder missing: {ERAS_DIR}")
        return {}
    for name in sorted(os.listdir(ERAS_DIR)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(ERAS_DIR, name), "r", encoding="utf-8") as fh:
            data = json.load(fh)
        if data.get("name") == era:
            return {s["modelName"]: s.get("type", "building") for s in data.get("slots", []) if s.get("modelName")}
    warn(f"no era config named {era!r} in {ERAS_DIR}")
    return {}


def stage_count_for(bp: Blueprint, slot_type: str | None) -> int:
    if slot_type == "building":
        return STAGE_COUNT
    if slot_type in SINGLE_STAGE_TYPES:
        if bp.max_stage > 0:
            warn(f"{bp.id}: {slot_type} slot has pieces at stage {bp.max_stage}; all pieces go into S0")
        return 1
    warn(f"{bp.id}: no slot of that modelName in the {bp.era} era config; guessing from the blueprint")
    return STAGE_COUNT if bp.max_stage > 0 else 1


# --- Kit pieces -------------------------------------------------------------------


def find_glb(kit: str, model: str) -> str | None:
    for sub in MODEL_DIRS:
        path = os.path.join(KITS_ROOT, kit, "Models", sub, f"{model}.glb")
        if os.path.isfile(path):
            return path
    return None


class SlotInfo:
    """What one material slot of an imported piece paints with."""

    def __init__(self, image, colour):
        self.image = image  # bpy.types.Image or None
        self.colour = colour  # linear RGB tuple when image is None


class PieceTemplate:
    def __init__(self):
        self.meshes: list[tuple[bpy.types.Mesh, Matrix, list[SlotInfo]]] = []


def classify_material(mat) -> SlotInfo:
    if mat is None or mat.node_tree is None:
        return SlotInfo(None, (0.8, 0.8, 0.8))
    bsdf = next((n for n in mat.node_tree.nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
    if bsdf is None:
        return SlotInfo(None, (0.8, 0.8, 0.8))
    for link in mat.node_tree.links:
        if link.to_node == bsdf and link.to_socket.name == "Base Color":
            node = link.from_node
            image = getattr(node, "image", None)
            if image is not None:
                return SlotInfo(image, None)
    c = bsdf.inputs["Base Color"].default_value
    return SlotInfo(None, (float(c[0]), float(c[1]), float(c[2])))


class Library:
    """Imports each (kit, model) once and keeps its meshes, world matrices and slot paint."""

    def __init__(self):
        self.templates: dict[tuple[str, str], PieceTemplate | None] = {}
        self.collection = bpy.data.collections.new("Library")
        bpy.context.scene.collection.children.link(self.collection)

    def get(self, kit: str, model: str) -> PieceTemplate | None:
        key = (kit, model)
        if key in self.templates:
            return self.templates[key]
        path = find_glb(kit, model)
        if path is None:
            warn(f"missing GLB: {kit}/{model}.glb (piece skipped)")
            self.templates[key] = None
            return None
        before = set(bpy.data.objects)
        try:
            bpy.ops.import_scene.gltf(filepath=path)
        except Exception as exc:  # the importer raises on malformed files
            warn(f"import failed for {path}: {exc}")
            self.templates[key] = None
            return None
        new = [o for o in bpy.data.objects if o not in before]
        bpy.context.view_layer.update()
        template = PieceTemplate()
        for o in new:
            if o.type == "MESH" and len(o.data.polygons) > 0:
                slots = [classify_material(m) for m in o.data.materials] or [SlotInfo(None, (0.8, 0.8, 0.8))]
                template.meshes.append((o.data, o.matrix_world.copy(), slots))
        for o in new:
            o.select_set(False)
            for c in list(o.users_collection):
                c.objects.unlink(o)
            self.collection.objects.link(o)
        if not template.meshes:
            warn(f"{kit}/{model}.glb has no mesh (piece skipped)")
            self.templates[key] = None
            return None
        self.templates[key] = template
        return template


# --- Kit paint ----------------------------------------------------------------------


class KitPaint:
    """One material + one image per kit, and a UV target for every colour-only face."""

    def __init__(self, kit: str, image, mode: str, pal: dict | None):
        self.kit = kit
        self.image = image
        self.mode = mode  # "texture" or "palette"
        self.palette = pal
        self.material = self._make_material()
        self._colour_uv: dict[tuple[float, float, float], tuple[float, float]] = {}
        self._pixels = None

    def _make_material(self):
        mat = bpy.data.materials.new(self.kit)
        if mat.node_tree is None:
            mat.use_nodes = True
        # Single-sided: Roblox would otherwise mark the MeshPart DoubleSided and render both faces.
        mat.use_backface_culling = True
        nodes = mat.node_tree.nodes
        bsdf = next((n for n in nodes if n.bl_idname == "ShaderNodeBsdfPrincipled"), None)
        if bsdf is None:
            bsdf = nodes.new("ShaderNodeBsdfPrincipled")
            out = next((n for n in nodes if n.bl_idname == "ShaderNodeOutputMaterial"), None) or nodes.new("ShaderNodeOutputMaterial")
            mat.node_tree.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Metallic"].default_value = 0.0
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = self.image
        tex.interpolation = "Closest"
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        return mat

    def uv_for_colour(self, colour: tuple[float, float, float]) -> tuple[float, float]:
        """Blender-convention UV (v up) of the pixel that best matches a linear colour."""
        key = tuple(round(c, 4) for c in colour)
        if key in self._colour_uv:
            return self._colour_uv[key]
        if self.mode == "palette":
            sw = palette.nearest_swatch(self.palette, colour)
            uv = (sw["uv"][0], 1.0 - sw["uv"][1])
        else:
            uv = self._nearest_pixel(colour)
        self._colour_uv[key] = uv
        return uv

    def _nearest_pixel(self, colour):
        # Byte images hand back their stored (sRGB) values, so compare in sRGB.
        target = tuple(palette.linear_to_srgb(c) for c in colour)
        if self._pixels is None:
            w, h = self.image.size
            px = self.image.pixels[:]
            seen: dict[tuple[int, int, int], tuple[int, int]] = {}
            for i in range(0, len(px), 4):
                rgb = (int(round(px[i] * 255)), int(round(px[i + 1] * 255)), int(round(px[i + 2] * 255)))
                if rgb not in seen:
                    n = i // 4
                    seen[rgb] = (n % w, n // w)
            self._pixels = (w, h, seen)
        w, h, seen = self._pixels
        best = min(seen, key=lambda rgb: sum((a - b) ** 2 for a, b in zip(rgb, target)))
        x, y = seen[best]
        return ((x + 0.5) / w, (y + 0.5) / h)


def build_kit_paint(kit: str, pieces: list[tuple[Piece, PieceTemplate]]) -> KitPaint | None:
    images = []
    for _, template in pieces:
        for _, _, slots in template.meshes:
            for s in slots:
                if s.image is not None and s.image not in images:
                    images.append(s.image)
    if images:
        if len(images) > 1:
            warn(f"{kit}: pieces reference {len(images)} different images; using {images[0].name} for all")
        image = images[0]
        if image.packed_file is None:
            try:
                image.pack()
            except RuntimeError as exc:
                warn(f"{kit}: could not pack {image.name}: {exc}")
        return KitPaint(kit, image, "texture", None)
    try:
        pal = palette.ensure_palette(kit)
    except (FileNotFoundError, ValueError, glbtools.GlbError) as exc:
        warn(f"{kit}: no palette ({exc}); its pieces are skipped")
        return None
    png_path = os.path.join(REPO_ROOT, pal["png"])
    image = bpy.data.images.load(png_path, check_existing=True)
    image.name = kit
    image.pack()
    log(f"{kit}: material-colour kit, palette {pal['png']} ({len(pal['swatches'])} swatches)")
    return KitPaint(kit, image, "palette", pal)


# --- Stage assembly --------------------------------------------------------------------


def holder_matrix(piece: Piece) -> Matrix:
    return Matrix.Translation(gltf_to_blender(piece.pos)) @ Matrix.Rotation(math.radians(piece.rot_y), 4, "Z")


def instance_mesh(src: bpy.types.Mesh, matrix: Matrix, slots: list[SlotInfo], paint: KitPaint) -> bpy.types.Mesh:
    mesh = src.copy()
    mesh.transform(matrix)
    uv_layer = mesh.uv_layers.active or (mesh.uv_layers[0] if mesh.uv_layers else mesh.uv_layers.new(name="UVMap"))
    colour_slots = {i: s for i, s in enumerate(slots) if s.image is None}
    if colour_slots:
        uv_targets = {i: paint.uv_for_colour(s.colour) for i, s in colour_slots.items()}
        for poly in mesh.polygons:
            uv = uv_targets.get(poly.material_index)
            if uv is None:
                continue
            for li in poly.loop_indices:
                uv_layer.data[li].uv = uv
    mesh.materials.clear()
    mesh.materials.append(paint.material)
    mesh.polygons.foreach_set("material_index", [0] * len(mesh.polygons))
    return mesh


def join_objects(objs: list) -> bpy.types.Object:
    if len(objs) == 1:
        return objs[0]
    for o in objs:
        o.select_set(True)
    with bpy.context.temp_override(active_object=objs[0], object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    return objs[0]


def mesh_bounds_gltf(obj) -> tuple[Vector, Vector]:
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for v in obj.data.vertices:
        p = blender_to_gltf(obj.matrix_world @ v.co)
        lo = Vector(map(min, lo, p))
        hi = Vector(map(max, hi, p))
    return lo, hi


def export_glb(path: str, objs: list) -> None:
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_image_format="AUTO",
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_vertex_color="NONE",
        export_attributes=False,
        export_extras=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_cameras=False,
        export_lights=False,
    )


def build_stage(bp: Blueprint, stage: int, pieces: list[Piece], library: Library, paints: dict[str, KitPaint], collection) -> dict:
    """Assemble one stage: returns {kit: joined object}; objects live in `collection`."""
    by_kit: dict[str, list] = {}
    for piece in pieces:
        template = library.get(piece.kit, piece.model)
        paint = paints.get(piece.kit)
        if template is None or paint is None:
            continue
        hm = holder_matrix(piece)
        for src_mesh, world, slots in template.meshes:
            mesh = instance_mesh(src_mesh, hm @ world, slots, paint)
            obj = bpy.data.objects.new(f"{piece.kit}_{piece.index:02d}", mesh)
            collection.objects.link(obj)
            by_kit.setdefault(piece.kit, []).append(obj)
    joined: dict[str, bpy.types.Object] = {}
    for kit in sorted(by_kit):
        obj = join_objects(by_kit[kit])
        obj.name = kit
        obj.data.name = kit
        obj.data.transform(Matrix.Scale(bp.scale, 4))
        obj.matrix_world = Matrix.Identity(4)
        joined[kit] = obj
    return joined


def remove_stage_objects(collection) -> None:
    for obj in list(collection.objects):
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh is not None and mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def merge_blueprint(bp: Blueprint, slot_type: str | None, out_root: str) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    library = Library()
    stage_coll = bpy.data.collections.new("Stage")
    bpy.context.scene.collection.children.link(stage_coll)

    stage_count = stage_count_for(bp, slot_type)
    # Kit paint is decided over every piece of the blueprint so all stages share one image.
    per_kit: dict[str, list[tuple[Piece, PieceTemplate]]] = {}
    for piece in bp.pieces:
        template = library.get(piece.kit, piece.model)
        if template is not None:
            per_kit.setdefault(piece.kit, []).append((piece, template))
    paints = {kit: p for kit, p in ((kit, build_kit_paint(kit, items)) for kit, items in sorted(per_kit.items())) if p is not None}

    era_dir = os.path.join(out_root, "stages", bp.era)
    report = {
        "id": bp.id,
        "era": bp.era,
        "slotType": slot_type,
        "scale": bp.scale,
        "footprint": list(bp.footprint),
        "stageCount": stage_count,
        "kits": {kit: {"mode": paint.mode, "image": paint.image.name} for kit, paint in paints.items()},
        "stages": [],
    }
    hx, hz = bp.footprint[0] / 2, bp.footprint[1] / 2
    for stage in range(stage_count):
        pieces = bp.pieces if stage_count == 1 else bp.pieces_at(stage)
        joined = build_stage(bp, stage, pieces, library, paints, stage_coll)
        entry = {"stage": stage, "pieces": len(pieces), "kits": {}, "glb": None}
        if not joined:
            warn(f"{bp.era}/{bp.id} S{stage}: nothing to export (no importable pieces)")
            report["stages"].append(entry)
            remove_stage_objects(stage_coll)
            continue
        glb_path = os.path.join(era_dir, f"{bp.id}_S{stage}.glb")
        export_glb(glb_path, list(joined.values()))
        with open(glb_path, "rb") as fh:
            data = fh.read()
        problems = glbtools.roblox_problems(data)
        for p in problems:
            warn(f"{bp.era}/{bp.id} S{stage}: {p}")
        exported = glbtools.node_bounds(data)
        lo_all = Vector((math.inf,) * 3)
        hi_all = Vector((-math.inf,) * 3)
        for kit, obj in joined.items():
            lo, hi = mesh_bounds_gltf(obj)
            lo_all = Vector(map(min, lo_all, lo))
            hi_all = Vector(map(max, hi_all, hi))
            node = exported.get(kit)
            if node is None:
                warn(f"{bp.era}/{bp.id} S{stage}: exported GLB has no node named {kit!r} (nodes: {sorted(exported)})")
            else:
                drift = max(abs(a - b) for a, b in zip(node["min"] + node["max"], list(lo) + list(hi)))
                if drift > 0.01:
                    warn(f"{bp.era}/{bp.id} S{stage}: {kit} bounds differ between Blender and the GLB by {drift:.3f} studs")
            entry["kits"][kit] = {
                "min": [round(v, 3) for v in lo],
                "max": [round(v, 3) for v in hi],
                "size": [round(hi[i] - lo[i], 3) for i in range(3)],
                "centre": [round((lo[i] + hi[i]) / 2, 3) for i in range(3)],
                "triangles": node["triangles"] if node else len(obj.data.polygons),
                "vertices": len(obj.data.vertices),
            }
        entry["min"] = [round(v, 3) for v in lo_all]
        entry["max"] = [round(v, 3) for v in hi_all]
        entry["size"] = [round(hi_all[i] - lo_all[i], 3) for i in range(3)]
        entry["bytes"] = len(data)
        entry["glb"] = os.path.relpath(glb_path, REPO_ROOT).replace(os.sep, "/")
        entry["problems"] = problems
        if lo_all.x < -hx - FOOTPRINT_EPS_STUDS or hi_all.x > hx + FOOTPRINT_EPS_STUDS or lo_all.z < -hz - FOOTPRINT_EPS_STUDS or hi_all.z > hz + FOOTPRINT_EPS_STUDS:
            warn(
                f"{bp.era}/{bp.id} S{stage}: exceeds the {bp.footprint[0]:g}x{bp.footprint[1]:g} footprint: "
                f"x[{lo_all.x:.2f}, {hi_all.x:.2f}] z[{lo_all.z:.2f}, {hi_all.z:.2f}] studs"
            )
        if lo_all.y < -FOOTPRINT_EPS_STUDS:
            warn(f"{bp.era}/{bp.id} S{stage}: geometry {-lo_all.y:.2f} studs below ground")
        tris = sum(k["triangles"] for k in entry["kits"].values())
        log(
            f"{bp.era}/{bp.id} S{stage}: {len(pieces)} pieces, {len(joined)} kit(s), "
            f"{entry['size'][0]:.2f} x {entry['size'][1]:.2f} x {entry['size'][2]:.2f} studs, "
            f"{tris} tris, {len(data) / 1024:.0f} KB -> {entry['glb']}"
        )
        report["stages"].append(entry)
        remove_stage_objects(stage_coll)

    os.makedirs(era_dir, exist_ok=True)
    sidecar = os.path.join(era_dir, f"{bp.id}.json")
    with open(sidecar, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")
    return report


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(prog="merge_stages.py")
    parser.add_argument("--era", required=True, help="era name, e.g. Village")
    parser.add_argument("--model", action="append", default=[], help="only this modelName (repeatable)")
    parser.add_argument("--out", default=DEFAULT_OUT, help="build root (default assets/build)")
    args = parser.parse_args(argv)

    slot_types = load_slot_types(args.era)
    paths = list_blueprints(args.era)
    if args.model:
        wanted = set(args.model)
        paths = [p for p in paths if os.path.splitext(os.path.basename(p))[0] in wanted]
        for m in sorted(wanted - {os.path.splitext(os.path.basename(p))[0] for p in paths}):
            warn(f"no blueprint tools/testfit/blueprints/{args.era}/{m}.json")
    if not paths:
        warn(f"no blueprints to merge for era {args.era}")
        return 0

    failures = 0
    for path in paths:
        try:
            bp = load_blueprint(path)
        except BlueprintError as exc:
            warn(f"blueprint {path} rejected: {exc}")
            failures += 1
            continue
        for message in bp.warnings:
            warn(f"{bp.id}: {message}")
        report = merge_blueprint(bp, slot_types.get(bp.id), os.path.abspath(args.out))
        if any(s.get("problems") or s.get("glb") is None for s in report["stages"]):
            failures += 1
    log(f"done: {len(paths)} blueprint(s), {failures} with problems")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
