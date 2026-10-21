"""testfit's raider view (L4): raider models posed with the client's own maths, for Ben's looks.

Blender renders, `py` composes (Pillow is not in Blender's Python, so this one file runs both ways):

    blender -b -P tools/testfit/raiderview.py -- --model RaiderFodder              # the pose strip
    blender -b -P tools/testfit/raiderview.py -- --model RaiderChief --front       # one front view
    blender -b -P tools/testfit/raiderview.py -- --model RaiderChiefB --front --pieces assets/build/raider-lookb/kenney3d \\
        --rig "assets/build/raider-lookb/kenney3d/raider-kit/Models/GLB format/RaiderChiefB.rig.json"
    blender -b -P tools/testfit/raiderview.py -- --lineup RaiderFodder,RaiderBrute,RaiderChief
    py tools/testfit/raiderview.py --compose <spec.json>                           # (called by the Blender run)

What a strip shows, per frame (raiderpose.frames_for: rest, two walk frames, the windup and the blow of
the kind's first attack, seated, spent; a kind with a sweep also its windup and swing; a boss with a
second phase its enraged look):
  * the model as the client will draw it: the merged stage GLBs (assets/build/stages/_props/Raiders/,
    exactly what would be uploaded), each stage one rigid piece placed by raiderpose.rig, each
    painted MeshPart (raider-cloth / -skin / -glow) in the colour and material raiderpose.paint gives
    for that frame (the kind's colour from ProvingGrounds.json, the windup's heat, the neon blow, the
    dull spent body, the enraged base), gear in its palette texture; a boss's charging core (a client
    cue kept as it is) at the model's `core` point;
  * the scored head (HitShapes: the sphere of headRadius at the feet + height - headRadius, lowered
    by the seat) as a wire circle, the drawn head's centre as a cross and their distance in head
    radii: the head rule says it stays under 0.5 before a hit lands;
  * a 5-stud R15 silhouette beside it for scale, on a dark forest-floor ground.
The Chief (a kind with a `hold`) carries the L3 Warhammer from the weapon kit, scaled as the client
will scale it. The lineup stands several models side by side at one scale, at rest and at the end of
their first windup, and again at the size a phone draws them 50 studs away.

Outputs in assets/testfit/out/Raiders/: <Model>_strip.png, <Model>_front.png, _lineup.png; raw renders
and specs in _raw/. --pieces <root> poses the generator's per-piece GLBs from a kenney3d-style root
instead of merged stages (the Chief's look B, which is never merged or uploaded).
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
sys.path.insert(0, HERE)
OUT_DIR = os.path.join(REPO_ROOT, "assets", "testfit", "out", "Raiders")
STAGES_DIR = os.path.join(REPO_ROOT, "assets", "build", "stages", "_props", "Raiders")
WEAPONS_DIR = os.path.join(REPO_ROOT, "assets", "kenney3d", "weapon-kit", "Models", "GLB format")
PIECES = ("head", "torso", "arm", "legL", "legR")
SUFFIX = {"head": "Head", "torso": "Torso", "arm": "Arm", "legL": "LegL", "legR": "LegR"}
ROLE_OF_KIT = {"raider-kit": "gear", "raider-cloth": "cloth", "raider-skin": "skin", "raider-glow": "glow"}

FRAME_W = 600  # a strip frame's width (800 for a body over 10 studs); its height follows the poses
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "assets"))
from forest_palette import GROUND as _FOREST_GROUND  # noqa: E402  (the forest track's floor, never redefined)

GROUND_RGB = _FOREST_GROUND.FLOOR
BACKDROP_TOP, BACKDROP_BOTTOM = (34, 40, 46), (22, 26, 24)
SILHOUETTE_RGB = (92, 104, 118)
CIRCLE_RGB = (120, 236, 255)
CROSS_RGB = (255, 236, 90)
# A vertex of another piece this deep in the scored head sphere is "in the head": a hit there crits
# though it lands on the body or the weapon. The neck reaching up under the skull stays outside it.
INTRUDE_SHARE = 0.8
# Cameras: orthographic, glTF directions toward the camera. The strips look from the front-right
# three-quarter a little above; the lineup nearly level, as a player's camera sees a camp.
VIEW_DIR = (1.0, 0.38, -1.45)
FRONT_DIR = (0.0, 0.12, -1.0)
LINEUP_DIR = (1.0, 0.16, -1.45)
# 50 studs away on a phone: Roblox's 70 degree vertical field of view over a landscape phone 390
# points tall draws 390 / (2 x 50 x tan 35) = 5.6 points a stud; at the 3x pixel density most phones
# have, 16.7 pixels a stud. The lineup is rendered at that density and shown at it and at point size.
PHONE_PX_PER_STUD = 3 * 390 / (2 * 50 * math.tan(math.radians(35)))
PHONE_DENSITY = 3


# --- Pillow side (py) -------------------------------------------------------------------------------


def _fonts():
    from PIL import ImageFont

    try:
        return (ImageFont.truetype("arial.ttf", 17), ImageFont.truetype("arial.ttf", 14),
                ImageFont.truetype("arialbd.ttf", 22))
    except OSError:
        f = ImageFont.load_default()
        return f, f, f


def _backdrop(size):
    from PIL import Image, ImageDraw

    w, h = size
    back = Image.new("RGB", (w, h))
    bd = ImageDraw.Draw(back)
    for y in range(h):
        t = y / max(h - 1, 1)
        bd.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BACKDROP_TOP, BACKDROP_BOTTOM)))
    return back


def compose(spec_path: str) -> int:
    from PIL import Image, ImageDraw

    with open(spec_path, "r", encoding="utf-8") as fh:
        spec = json.load(fh)
    if spec.get("kind") == "lineup":
        return compose_lineup(spec)
    frames = spec["frames"]
    fw, fh_ = spec["size"]
    header, footer, pad = 92, 74, 10
    width = pad + len(frames) * (fw + pad)
    height = header + fh_ + footer
    img = Image.new("RGB", (width, height), (16, 18, 20))
    draw = ImageDraw.Draw(img)
    font, small, big = _fonts()
    draw.text((pad, 10), spec["title"], fill=(240, 240, 240), font=big)
    for i, line in enumerate(spec.get("lines", [])):
        draw.text((pad, 40 + i * 18), line, fill=(190, 196, 204), font=small)
    for i, fr in enumerate(frames):
        x0 = pad + i * (fw + pad)
        back = _backdrop((fw, fh_))
        render = Image.open(fr["png"]).convert("RGBA")
        back.paste(render, (0, 0), render)
        d = ImageDraw.Draw(back)
        if fr.get("circle"):
            cx, cy, r = fr["circle"]
            d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=CIRCLE_RGB, width=2)
            hx, hy = fr["cross"]
            d.line([(hx - 7, hy), (hx + 7, hy)], fill=CROSS_RGB, width=2)
            d.line([(hx, hy - 7), (hx, hy + 7)], fill=CROSS_RGB, width=2)
        img.paste(back, (x0, header))
        draw.text((x0 + 4, header + fh_ + 6), fr["label"], fill=(236, 236, 236), font=font)
        for j, note in enumerate(fr.get("notes", [])):
            draw.text((x0 + 4, header + fh_ + 28 + j * 17), note, fill=(170, 200, 210) if j == 0 else (200, 180, 150), font=small)
    return _save(img, spec["out"])


def compose_lineup(spec: dict) -> int:
    """Rows: rest and windup at full size; then both at a phone's 50-stud size, at its pixel density
    and at point size (what the eye gets on a ~6 inch phone)."""
    from PIL import Image, ImageDraw

    font, small, big = _fonts()
    big_rows = [Image.open(p).convert("RGBA") for p in spec["big"]]
    phone_rows = [Image.open(p).convert("RGBA") for p in spec["phone"]]
    pad = 12
    width = max(r.size[0] for r in big_rows) + 2 * pad
    blocks = []
    for label, row in zip(spec["bigLabels"], big_rows):
        back = _backdrop(row.size)
        back.paste(row, (0, 0), row)
        blocks.append((label, back))
    for label, row in zip(spec["phoneLabels"], phone_rows):
        back = _backdrop(row.size)
        back.paste(row, (0, 0), row)
        point = back.resize((max(row.size[0] // PHONE_DENSITY, 1), max(row.size[1] // PHONE_DENSITY, 1)), Image.LANCZOS)
        both = Image.new("RGB", (back.size[0] + point.size[0] + pad, back.size[1]), (16, 18, 20))
        both.paste(back, (0, 0))
        both.paste(point, (back.size[0] + pad, back.size[1] - point.size[1]))
        blocks.append((label, both))
    height = 70 + sum(b.size[1] + 34 for _, b in blocks) + pad
    width = max(width, max(b.size[0] for _, b in blocks) + 2 * pad)
    img = Image.new("RGB", (width, height), (16, 18, 20))
    draw = ImageDraw.Draw(img)
    draw.text((pad, 10), spec["title"], fill=(240, 240, 240), font=big)
    for i, line in enumerate(spec.get("lines", [])):
        draw.text((pad, 38 + i * 17), line, fill=(190, 196, 204), font=small)
    y = 70
    for label, block in blocks:
        draw.text((pad, y + 6), label, fill=(236, 236, 236), font=font)
        img.paste(block, (pad, y + 30))
        y += block.size[1] + 34
    return _save(img, spec["out"])


def _save(img, out: str) -> int:
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print(f"[raiderview] wrote {os.path.relpath(out, REPO_ROOT)} ({img.size[0]} x {img.size[1]})")
    return 0


def _run_compose(spec: dict, spec_path: str) -> int:
    with open(spec_path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(spec, fh, indent=2)
    # No `#!` line in this file: `py` then starts the Python that has Pillow (see the memory note).
    result = subprocess.run(["py", os.path.abspath(__file__), "--compose", spec_path], capture_output=True, text=True)
    print(result.stdout.strip(), flush=True)
    if result.returncode != 0:
        print(f"[raiderview] WARNING: compose failed: {result.stderr.strip()}", flush=True)
        return 1
    return 0


# --- Blender side ------------------------------------------------------------------------------------


def lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


class Viewer:
    """The scene every view shares: ground, light, an orthographic camera, materials."""

    def __init__(self):
        import bpy

        self.bpy = bpy
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.scene = bpy.context.scene
        self._box("Ground", (600.0, 0.2, 600.0), (0.0, -0.1, 0.0), self.flat("Ground", GROUND_RGB))
        sun_data = bpy.data.lights.new("Sun", "SUN")
        sun_data.energy = 3.0
        sun_data.angle = math.radians(4)
        sun = bpy.data.objects.new("Sun", sun_data)
        sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
        self.scene.collection.objects.link(sun)
        world = bpy.data.worlds.new("World")
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs["Color"].default_value = (0.82, 0.85, 0.9, 1.0)
        bg.inputs["Strength"].default_value = 0.9
        self.scene.world = world
        for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
            try:
                self.scene.render.engine = engine
                break
            except TypeError:
                continue
        self.scene.render.resolution_percentage = 100
        self.scene.render.film_transparent = True
        self.scene.render.image_settings.file_format = "PNG"
        self.scene.render.image_settings.color_mode = "RGBA"
        if hasattr(self.scene, "eevee"):
            self.scene.eevee.taa_render_samples = 24
        try:
            self.scene.view_settings.view_transform = "Standard"
        except TypeError:
            pass
        self.cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        self.scene.collection.objects.link(self.cam)
        self.scene.camera = self.cam
        self.cam.data.type = "ORTHO"
        self.cam.data.clip_end = 900.0

    # glTF (Y up, front -Z) <-> Blender (Z up)
    @staticmethod
    def g2b(v):
        from mathutils import Vector

        return Vector((v[0], -v[2], v[1]))

    @staticmethod
    def b2g(v):
        return (v.x, v.z, -v.y)

    @staticmethod
    def g2b_matrix(cf):
        from mathutils import Matrix

        m = Matrix(cf.matrix())
        c = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
        return c @ m @ c.inverted()

    def flat(self, name, rgb, emit=False):
        mat = self.bpy.data.materials.new(name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        col = (*(lin(c / 255) for c in rgb), 1.0)
        if emit:
            for n in list(nodes):
                nodes.remove(n)
            out = nodes.new("ShaderNodeOutputMaterial")
            em = nodes.new("ShaderNodeEmission")
            em.inputs["Color"].default_value = col
            mat.node_tree.links.new(em.outputs["Emission"], out.inputs["Surface"])
        else:
            bsdf = nodes.get("Principled BSDF")
            bsdf.inputs["Base Color"].default_value = col
            bsdf.inputs["Roughness"].default_value = 1.0
        return mat

    def lit_material(self, name):
        mat = self.bpy.data.materials.new(name)
        mat.use_nodes = True
        mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 0.85
        return mat

    def neon_material(self, name):
        mat = self.bpy.data.materials.new(name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        for n in list(nodes):
            nodes.remove(n)
        out = nodes.new("ShaderNodeOutputMaterial")
        em = nodes.new("ShaderNodeEmission")
        mat.node_tree.links.new(em.outputs["Emission"], out.inputs["Surface"])
        return mat

    def _box(self, name, size_g, centre_g, mat, yaw=0.0):
        from mathutils import Matrix

        mesh = self.bpy.data.meshes.new(name)
        sx, sy, sz = size_g[0] / 2, size_g[2] / 2, size_g[1] / 2
        verts = [(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        obj = self.bpy.data.objects.new(name, mesh)
        obj.data.materials.append(mat)
        obj.matrix_world = Matrix.Translation(self.g2b(centre_g)) @ Matrix.Rotation(yaw, 4, "Z")
        self.scene.collection.objects.link(obj)
        return obj

    def silhouette(self, at_g, yaw):
        """A blocky 5-stud R15, its front (-Z) turned by `yaw` (toward the camera)."""
        import raiderpose as rp

        mat = self.flat("Silhouette", SILHOUETTE_RGB, emit=True)
        parts = []
        for size, centre in (((0.96, 2.0, 1.0), (-0.5, 1.0, 0.0)), ((0.96, 2.0, 1.0), (0.5, 1.0, 0.0)),
                             ((2.0, 2.0, 1.0), (0.0, 3.0, 0.0)), ((0.96, 1.95, 1.0), (-1.5, 2.98, 0.0)),
                             ((0.96, 1.95, 1.0), (1.5, 2.98, 0.0)), ((1.15, 1.0, 1.1), (0.0, 4.5, 0.0))):
            parts.append(self._box("R15", size, rp.v_add(at_g, rp.ry(yaw).rotate(centre)), mat, yaw=yaw))
        return parts

    def aim(self, view_dir_g):
        """Point the camera along -view_dir; returns its right and up (Blender vectors)."""
        from mathutils import Vector

        vb = self.g2b(view_dir_g).normalized()
        rot = (-vb).to_track_quat("-Z", "Y")
        self.cam.rotation_euler = rot.to_euler()
        self.view = vb
        self.right = rot @ Vector((1, 0, 0))
        self.up = rot @ Vector((0, 1, 0))
        return self.right, self.up

    def fit(self, points, width, height=None, margin=1.08, px_per_stud=None):
        """Frame `points` (Blender vectors). With px_per_stud the scale is fixed and the size follows."""
        xs = [p.dot(self.right) for p in points]
        ys = [p.dot(self.up) for p in points]
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
        if px_per_stud:
            width = int(math.ceil(w * margin * px_per_stud))
            height = int(math.ceil(h * margin * px_per_stud))
        elif height is None:
            height = int(min(max(width * h / max(w, 1e-6), 520), 1100))
        aspect = width / height
        self.scene.render.resolution_x, self.scene.render.resolution_y = width, height
        self.cam.data.ortho_scale = (max(w, h * aspect) if aspect >= 1 else max(w / aspect, h)) * margin
        self.cam.location = self.right * cx + self.up * cy + self.view * 400.0
        self.size = (width, height)
        self.px_per_stud = max(width, height) / self.cam.data.ortho_scale
        return self.size

    def project(self, p_g):
        from bpy_extras.object_utils import world_to_camera_view

        v = world_to_camera_view(self.scene, self.cam, self.g2b(p_g))
        return [v.x * self.size[0], (1 - v.y) * self.size[1]]

    def render(self, path):
        self.scene.render.filepath = path
        self.bpy.ops.render.render(write_still=True)


class Body3D:
    """One raider model in the scene: its five pieces (and a held weapon and a boss's core), posed
    by raiderpose.rig at a feet position, painted by raiderpose.paint."""

    def __init__(self, viewer: Viewer, model_name: str, model: dict, kind: dict, rig_numbers: dict, consts, pieces_root=None):
        import raiderpose as rp

        self.v, self.rp = viewer, rp
        self.name, self.model, self.kind = model_name, model, kind
        self.rig_numbers, self.consts = rig_numbers, consts
        self.skin = tuple(c / 255.0 for c in model["skin"])
        bpy = viewer.bpy
        self.loaded: dict[str, list] = {}
        for k, piece in enumerate(PIECES):
            objs = []
            if pieces_root:
                for kit in ROLE_OF_KIT:
                    path = os.path.join(os.path.abspath(pieces_root), kit, "Models", "GLB format", f"{model_name}_{SUFFIX[piece]}.glb")
                    if os.path.isfile(path):
                        objs += [(o, kit) for o in self._import(path)]
            else:
                path = os.path.join(STAGES_DIR, f"{model_name}_S{k}.glb")
                if not os.path.isfile(path):
                    raise SystemExit(f"[raiderview] missing {os.path.relpath(path, REPO_ROOT)}: run merge_stages.py --props --era Raiders")
                objs = [(o, self._kit_of(o)) for o in self._import(path)]
            self.loaded[piece] = [(o, kit, o.matrix_world.copy()) for o, kit in objs]
        self.roles = {}
        for piece in PIECES:
            parts = next(p for p in model["pieces"] if p["name"] == piece)["parts"]
            for o, kit, _ in self.loaded[piece]:
                self.roles[o.name] = parts.get(kit, ROLE_OF_KIT[kit])
        self.paint_mats = {role: (viewer.lit_material(f"{model_name}_{role}"), viewer.neon_material(f"{model_name}_{role}_neon"))
                           for role in ("cloth", "clothLeg", "skin", "glow")}
        self.hold = model.get("hold")
        self.held = []
        if self.hold:
            path = os.path.join(WEAPONS_DIR, f"{self.hold['model']}.glb")
            if os.path.isfile(path):
                self.held = [(o, o.matrix_world.copy()) for o in self._import(path)]
            else:
                print(f"[raiderview] WARNING: no {self.hold['model']}.glb in the weapon kit; the hold is left empty", flush=True)
        self.core = None
        if kind.get("boss") and "core" in model["points"]:
            import bmesh

            self.core_size = max(model["radius"] * 0.6, 0.8)
            self.core_swell = max(model["height"] * 0.3 / self.core_size, 1.0)
            mesh = bpy.data.meshes.new(f"{model_name}_Core")
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.5)
            bm.to_mesh(mesh)
            bm.free()
            self.core = bpy.data.objects.new(f"{model_name}_Core", mesh)
            viewer.scene.collection.objects.link(self.core)
            self.core.data.materials.append(viewer.neon_material(f"{model_name}_core"))

    def _import(self, path):
        bpy = self.v.bpy
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
        for o in new:
            o.select_set(False)
        return [o for o in new if o.type == "MESH"]

    @staticmethod
    def _kit_of(obj) -> str:
        name = obj.name.split(".")[0]
        return name if name in ROLE_OF_KIT else "raider-kit"

    def _set_paint(self, role, rgb, material):
        lit, neon = self.paint_mats[role]
        col = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0)
        lit.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = col
        em = next(n for n in neon.node_tree.nodes if n.bl_idname == "ShaderNodeEmission")
        em.inputs["Color"].default_value = col
        em.inputs["Strength"].default_value = 1.6
        return neon if material == "Neon" else lit

    def _hold_frame(self):
        rp = self.rp
        right, up = tuple(self.hold["right"]), tuple(self.hold["up"])
        back = rp.v_cross(right, up)
        rot = ((right[0], up[0], back[0]), (right[1], up[1], back[1]), (right[2], up[2], back[2]))
        return rp.CFrame(rot, tuple(self.hold["grip"]))

    def apply(self, frame, feet=(0.0, 0.0, 0.0)):
        """Pose and paint for one frame, the body's feet at `feet` (glTF); returns the rig."""
        from mathutils import Matrix

        rp, v = self.rp, self.v
        r = rp.rig(self.model, self.rig_numbers, self.consts, frame.pose)
        place = rp.cf_at(feet)
        for piece in PIECES:
            mb = v.g2b_matrix(place * r.pieces[piece])
            for o, _, base in self.loaded[piece]:
                o.matrix_world = mb @ base
        if self.held:
            mb = v.g2b_matrix(place * r.pieces[self.hold.get("piece", "arm")] * self._hold_frame()) @ Matrix.Scale(self.hold["scale"], 4)
            for o, base in self.held:
                o.matrix_world = mb @ base
        paint = rp.paint(self.consts, self.kind, self.skin, frame.threat, enraged=frame.enraged)
        for piece in PIECES:
            for o, _, _ in self.loaded[piece]:
                role = self.roles[o.name]
                if role != "gear":
                    rgb, material = paint[role]
                    o.data.materials.clear()
                    o.data.materials.append(self._set_paint(role, rgb, material))
        if self.core is not None:
            base = tuple(c / 255.0 for c in self.kind["color"])
            lit = rp.c3_lerp(base, (1.0, 1.0, 1.0), 0.45)
            if frame.enraged:
                lit = self.consts.COMBAT_RANGE_ENRAGE_GLOW_COLOR
            charge = frame.threat.charge
            colour = rp.c3_lerp(lit, self.consts.COMBAT_RANGE_TELL_COLOR, min(round(charge * 8) / 8 * 2, 1.0))
            size = self.core_size * (1 + (self.core_swell - 1) * charge) * (1.35 if frame.enraged else 1.0)
            at = rp.v_add(feet, r.pieces["torso"].point(tuple(self.model["points"]["core"])))
            self.core.matrix_world = Matrix.Translation(v.g2b(at)) @ Matrix.Scale(size, 4)
            em = next(n for n in self.core.data.materials[0].node_tree.nodes if n.bl_idname == "ShaderNodeEmission")
            em.inputs["Color"].default_value = (lin(colour[0]), lin(colour[1]), lin(colour[2]), 1.0)
            em.inputs["Strength"].default_value = 1.6
        v.bpy.context.view_layer.update()
        return r

    def objects(self):
        out = [o for piece in PIECES for o, _, _ in self.loaded[piece]] + [o for o, _ in self.held]
        return out + ([self.core] if self.core is not None else [])

    def points(self):
        return [o.matrix_world @ vert.co for o in self.objects() for vert in o.data.vertices]

    def intrusions(self, anchor, feet=(0.0, 0.0, 0.0)):
        """Vertices of every piece but the head (and the held weapon) deep in the scored head sphere."""
        rp, hr = self.rp, self.model["headRadius"]
        centre = rp.v_add(anchor, feet)
        objs = [o for piece in PIECES[1:] for o, _, _ in self.loaded[piece]] + [o for o, _ in self.held]
        count = 0
        for o in objs:
            mw = o.matrix_world
            for vert in o.data.vertices:
                if rp.v_len(rp.v_sub(self.v.b2g(mw @ vert.co), centre)) < hr * INTRUDE_SHARE:
                    count += 1
        return count


def load_entry(rp, models_path, model_name, rig_path=None):
    """(model entry, kind id, rig numbers) from the config, or from a .rig.json (look B)."""
    cfg = rp.load_models(models_path)
    if rig_path:
        with open(rig_path, "r", encoding="utf-8") as fh:
            model = json.load(fh)
        kind_id = next((k for k, v in cfg["kinds"].items() if v["model"] == model["model"]), None) or "chief"
        return model, kind_id, cfg.get("rig", dict(rp.RIG_DEFAULTS))
    kind_id = next((k for k, v in cfg["kinds"].items() if v["model"] == model_name), None)
    if kind_id is None:
        raise SystemExit(f"[raiderview] {model_name} is not in {models_path}")
    return cfg["kinds"][kind_id], kind_id, cfg.get("rig", {})


def strip_or_front(args) -> int:
    import raiderpose as rp

    consts = rp.Constants()
    kinds, threat_cfg, kind_notes = rp.load_kinds()
    model, kind_id, rig_numbers = load_entry(rp, args.models, args.model, args.rig)
    kind = kinds[kind_id]
    v = Viewer()
    body = Body3D(v, args.model, model, kind, rig_numbers, consts, args.pieces)
    right, _ = v.aim(FRONT_DIR if args.front else VIEW_DIR)
    right_g = v.b2g(right)
    sil_at = rp.v_mul(right_g, model["reach"] + 2.4)
    vd = FRONT_DIR if args.front else VIEW_DIR
    sil = v.silhouette(sil_at, math.atan2(-vd[0], -vd[2]) + math.pi)

    if args.front:
        frames = [rp.Frame("front", "front, rest", rp.Pose(arm=tuple(model["arm"]["carry"])), rp.Threat())]
    else:
        frames = rp.frames_for(kind_id, kinds, threat_cfg, consts, model, rig_numbers)
    pts = []
    from mathutils import Vector

    for fr in frames:
        body.apply(fr)
        pts += body.points()
    pts += [s.matrix_world @ Vector(c) for s in sil for c in s.bound_box]
    pts.append(Vector((0.0, 0.0, min(p.z for p in pts) - 0.6)))
    width = FRAME_W if model["height"] < 10 else 800
    v.fit(pts, width)
    print(f"[raiderview] {args.model}: frames {v.size[0]} x {v.size[1]} px, {v.px_per_stud:.1f} px a stud", flush=True)

    raw = os.path.join(OUT_DIR, "_raw")
    os.makedirs(raw, exist_ok=True)
    hr = model["headRadius"]
    head_mesh_centre = tuple(model.get("headMeshCentre", model["points"]["head"]))
    spec_frames = []
    for fr in frames:
        r = body.apply(fr)
        png = os.path.join(raw, f"{args.model}_{fr.name}.png")
        v.render(png)
        drawn = r.pieces["head"].point(head_mesh_centre)
        off = rp.v_len(rp.v_sub(drawn, r.anchor)) / hr
        inside = body.intrusions(r.anchor)
        notes = [f"head {off:.2f} hr off the scored head" + ("" if off <= 0.5 else "  (RULE BROKEN)")]
        t = fr.threat
        if t.glow:
            notes.append("blow: neon")
        elif t.tint > 0:
            notes.append(f"tint {t.tint:.2f} toward {'heat' if t.phase == 'windup' else 'spent'}")
        if fr.enraged:
            notes.append("enraged: base toward red, eyes ember")
        if inside:
            notes.append(f"{inside} body vertices deep in the head sphere")
        if max(r.foot_float.values()) > 0.05:
            notes.append(f"a foot floats {max(r.foot_float.values()):.2f}")
        centre = v.project(r.anchor)
        spec_frames.append({"name": fr.name, "label": fr.label, "png": png, "notes": notes,
                            "circle": [centre[0], centre[1], hr * v.px_per_stud], "cross": v.project(drawn),
                            "headOffset": round(off, 3), "inHead": inside})
        print(f"[raiderview] {args.model} {fr.name}: head {off:.3f} hr, body vertices in the head sphere {inside}", flush=True)

    note = f"{model['triangles']} triangles, {model['meshParts']} MeshParts"
    if body.hold:
        note += f" + the {body.hold['model']} at x{body.hold['scale']}"
    lines = [
        f"kind {kind_id} ({kind.get('name', kind_id)}): height {model['height']}, radius {model['radius']}, head radius "
        f"{model['headRadius']}; {note}; cloth {tuple(kind['color'])} from ProvingGrounds.json, skin {tuple(model['skin'])}",
        "posed by raiderpose.py (CrowdRenderer's maths + the model rig); cyan circle = the scored head, yellow cross = the drawn head"
        + ("" if args.front else "; seated: the scored head lowered by the seat (planned server fix)"),
    ]
    if kind_id in kind_notes:
        lines.append(f"{kind_id}: {kind_notes[kind_id]}")
    which = "front" if args.front else "strip"
    spec = {"title": args.model + (" - front" if args.front else " - pose strip"), "lines": lines, "size": list(v.size),
            "frames": spec_frames, "out": os.path.join(OUT_DIR, f"{args.model}_{which}.png")}
    return _run_compose(spec, os.path.join(raw, f"{args.model}_{which}_spec.json"))


def lineup(args) -> int:
    """Several models side by side at one scale: at rest and at the end of their first windup's coil,
    then the same at a phone's size 50 studs away."""
    import raiderpose as rp
    from mathutils import Vector

    consts = rp.Constants()
    kinds, threat_cfg, _ = rp.load_kinds()
    v = Viewer()
    right, _ = v.aim(LINEUP_DIR)
    right_g = v.b2g(right)
    names = [n.strip() for n in args.lineup.split(",") if n.strip()]
    bodies = []
    cursor = 0.0
    sil_yaw = math.atan2(-LINEUP_DIR[0], -LINEUP_DIR[2]) + math.pi
    sil = v.silhouette(rp.v_mul(right_g, cursor), sil_yaw)
    cursor += 2.0
    for name in names:
        model, kind_id, rig_numbers = load_entry(rp, args.models, name)
        body = Body3D(v, name, model, kinds[kind_id], rig_numbers, consts)
        half = model["reach"] + (3.0 if model.get("hold") else 0.6)
        cursor += half + 1.2
        frames = rp.frames_for(kind_id, kinds, threat_cfg, consts, model, rig_numbers)
        rest = next(f for f in frames if f.name == "rest")
        windup = next(f for f in frames if f.name == "windup")
        bodies.append((body, rp.v_mul(right_g, cursor), rest, windup))
        cursor += half
    raw = os.path.join(OUT_DIR, "_raw")
    os.makedirs(raw, exist_ok=True)

    def pose(which):
        for body, feet, rest, windup in bodies:
            body.apply(rest if which == "rest" else windup, feet)

    pts = []
    for which in ("rest", "windup"):
        pose(which)
        for body, _, _, _ in bodies:
            pts += body.points()
    pts += [s.matrix_world @ Vector(c) for s in sil for c in s.bound_box]
    pts.append(Vector((0.0, 0.0, -0.4)))
    out = {"big": [], "phone": []}
    v.fit(pts, 2400, None, margin=1.04)
    big_px = v.px_per_stud
    for which in ("rest", "windup"):
        pose(which)
        path = os.path.join(raw, f"_lineup_{which}.png")
        v.render(path)
        out["big"].append(path)
    v.fit(pts, 0, 0, margin=1.04, px_per_stud=PHONE_PX_PER_STUD)
    for which in ("rest", "windup"):
        pose(which)
        path = os.path.join(raw, f"_lineup_{which}_phone.png")
        v.render(path)
        out["phone"].append(path)
    spec = {
        "kind": "lineup",
        "title": "Raider prototypes - lineup (fodder 5, brute 7.5, the Camp Chief 14; the R15 silhouette is a 5-stud player)",
        "lines": [f"{n}: posed and painted by raiderpose.py; the cloth is each kind's colour from ProvingGrounds.json" for n in [", ".join(names)]]
        + [f"top rows {big_px:.0f} px a stud; bottom rows: 50 studs away on a phone (70 degree view, 390 points tall): "
           f"{PHONE_PX_PER_STUD:.1f} px a stud at its 3x density, and at point size (right)"],
        "bigLabels": ["at rest", "at the end of each one's first windup coil (the heat tint)"],
        "phoneLabels": ["at rest, 50 studs on a phone", "first windup, 50 studs on a phone"],
        "big": out["big"],
        "phone": out["phone"],
        "out": os.path.join(OUT_DIR, "_lineup.png"),
    }
    return _run_compose(spec, os.path.join(raw, "_lineup_spec.json"))


def blender_main(argv: list[str]) -> int:
    import raiderpose as rp

    parser = argparse.ArgumentParser(prog="raiderview.py")
    parser.add_argument("--model", help="one model: its pose strip (or --front)")
    parser.add_argument("--front", action="store_true", help="one front view at rest instead of the strip")
    parser.add_argument("--lineup", help="comma-separated models side by side, plus the 50-stud phone check")
    parser.add_argument("--pieces", help="pose per-piece GLBs from this kenney3d-style root instead of merged stages")
    parser.add_argument("--models", default=rp.MODELS_PATH)
    parser.add_argument("--rig", help="read the model's rig record from this .rig.json instead of the config")
    args = parser.parse_args(argv)
    if args.lineup:
        return lineup(args)
    if not args.model:
        parser.error("--model or --lineup")
    return strip_or_front(args)


def main() -> int:
    if "--compose" in sys.argv:
        return compose(sys.argv[sys.argv.index("--compose") + 1])
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return blender_main(argv)


if __name__ == "__main__":
    sys.exit(main())
