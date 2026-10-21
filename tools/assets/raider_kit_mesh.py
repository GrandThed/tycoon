"""Shared geometry, rig records and export for the generated raider kit (L4): raider_kit.py uses it.

Runs inside Blender (imported by the generator, never run on its own):

    blender -b -P tools/assets/raider_kit.py [-- --only RaiderFodder]

Why a generated kit: no Kenney kit has characters (the city walkers are generated too, people_kit.py),
and Ben chose detailed models over chunky low-poly (2026-09-23) and real models for the seven Forest
looks (MISSIONS_DESIGN section 26). The geometry vocabulary is the weapon kit's (weapon_kit_mesh.Mesh:
grid, lathe, sweep, loop, prism, box, nodule ...); this module adds the body pieces and the rig record.

**The rig** (the study's "piece k in stage k", raiderpose.py has the rules): a raider is one prop with
five stages, each one rigid piece of the body, authored in place in the body frame (feet at the origin,
front -Z, up +Y, right +X, 1 glTF unit = 1 stud, blueprint scale 1.0):

    Stage0 head   Stage1 torso (and the off arm)   Stage2 weapon arm(s)   Stage3 left leg   Stage4 right leg

Each piece is split by **role** into one GLB per kit folder, because merge_stages joins a stage into
one MeshPart per kit (the folder is the kit's registration, as for every generated kit):

    raider-kit    gear: fur, hide, bone, wood, rope, flint, hair, eyes; palette-textured, never painted
    raider-cloth  the kind's cloth: painted by the client with the kind's colour (body) or its leg shade
    raider-skin   skin: painted with the kind's skin colour, tinted half as far (the crit point)
    raider-glow   the Chief's eye sockets: painted by the visor rule (hot through an attack, ember enraged)

so every surface that carries a tell is its own untextured MeshPart the client paints by Color and
Material exactly as today (the lead's ruling), and gear keeps its texture.

**Colours** come only from raider_kit_palette.py, per kit (`RMesh` raises on any other). Every run also
writes one `palette-card.glb` per kit folder, so each kit's palette texture holds every swatch however
many models exist yet.

**Geometry** is authored in glTF space; weapon_kit_mesh converts to Blender with (x, y, z) -> (x, -z, y)
and turns every closed primitive outward by its signed volume (Roblox culls back faces).
"""

from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import raider_kit_palette as rpal  # noqa: E402
import weapon_kit_mesh as wkm  # noqa: E402
from weapon_kit_mesh import add, basis, mul, norm, sub  # noqa: E402,F401

REPO_ROOT = wkm.REPO_ROOT
KITS_ROOT = os.path.join(REPO_ROOT, "assets", "kenney3d")
GLB_DIR = os.path.join("Models", "GLB format")
CONFIG_OUT = os.path.join(REPO_ROOT, "tools", "assets", "out", "RaiderModels.json")
BLUEPRINTS = os.path.join(REPO_ROOT, "tools", "testfit", "blueprints", "_props", "Raiders")
ERA = "Raiders"
PIECES = ("head", "torso", "arm", "legL", "legR")  # piece k is stage k
PIECE_SUFFIX = {"head": "Head", "torso": "Torso", "arm": "Arm", "legL": "LegL", "legR": "LegR"}
ROLE_OF_KIT = {"raider-kit": "gear", "raider-cloth": "cloth", "raider-skin": "skin", "raider-glow": "glow"}
CONFIG_VERSION = 1

Vec = tuple[float, float, float]
Rgb = tuple[int, int, int]


class RMesh(wkm.Mesh):
    """weapon_kit_mesh.Mesh with the raider kit's per-kit colour rule."""

    def __init__(self, name: str, kit: str):
        super().__init__(name)
        self.kit = kit
        self._allowed = rpal.allowed(kit)

    def _colour(self, colour: Rgb) -> Rgb:
        colour = tuple(int(c) for c in colour)
        if colour not in self._allowed:
            raise ValueError(f"{self.name} ({self.kit}): colour {colour} is not a {self.kit} colour in raider_kit_palette.py")
        return colour


class Piece:
    """One rigid body piece: an RMesh per kit, created on first use."""

    def __init__(self, model: str, piece: str):
        self.model = model
        self.piece = piece
        self.meshes: dict[str, RMesh] = {}

    @property
    def name(self) -> str:
        return f"{self.model}_{PIECE_SUFFIX[self.piece]}"

    def kit(self, kit: str) -> RMesh:
        if kit not in self.meshes:
            self.meshes[kit] = RMesh(self.name, kit)
        return self.meshes[kit]

    @property
    def gear(self) -> RMesh:
        return self.kit("raider-kit")

    @property
    def cloth(self) -> RMesh:
        return self.kit("raider-cloth")

    @property
    def skin(self) -> RMesh:
        return self.kit("raider-skin")

    @property
    def glow(self) -> RMesh:
        return self.kit("raider-glow")

    @property
    def tris(self) -> int:
        return sum(m.tris for m in self.meshes.values() if m.faces)


class Body:
    """A raider model: its five pieces, its rig points and what the client needs from config."""

    def __init__(self, model: str, kind: str, height: float, radius: float, head_radius: float, *, skin: Rgb = rpal.PAINT.SKIN):
        self.model = model
        self.kind = kind
        self.height = height
        self.radius = radius
        self.head_radius = head_radius
        self.skin = skin
        self.pieces = {p: Piece(model, p) for p in PIECES}
        self.points: dict[str, Vec] = {}
        self.leg_length = 0.0
        self.lead_leg = "legL"
        self.arm_swing_share = 1.0
        self.arm: dict = {}
        self.hold: dict | None = None
        self.cloth_of: dict[str, str] = {"torso": "cloth", "arm": "cloth", "head": "cloth", "legL": "clothLeg", "legR": "clothLeg"}
        self.notes: dict[str, object] = {}
        self.budget = 0

    def __getitem__(self, piece: str) -> Piece:
        return self.pieces[piece]

    @property
    def tris(self) -> int:
        return sum(p.tris for p in self.pieces.values())

    def meshes(self):
        for piece in PIECES:
            for kit, mesh in sorted(self.pieces[piece].meshes.items()):
                if mesh.faces:
                    yield piece, kit, mesh


# --- the body vocabulary --------------------------------------------------------------------------


def ring(cy: float, cx: float, cz: float, rx: float, rz: float, segments: int, phase: float = 0.0,
         jag=None) -> list[Vec]:
    """A horizontal ellipse at height cy; `jag(s)` may scale each point's radius (fur, ragged hems)."""
    pts = []
    for s in range(segments):
        t = phase + 2 * math.pi * s / segments
        k = jag(s) if jag else 1.0
        pts.append((cx + rx * k * math.sin(t), cy, cz - rz * k * math.cos(t)))
    return pts


def blob(m: RMesh, rings, colour: Rgb, *, segments: int = 8, smooth: bool = True, apex0: Vec | None = None,
         apex1: Vec | None = None, phase: float = 0.0, face_colour=None, cap0: bool = True, cap1: bool = True) -> None:
    """A closed body from horizontal elliptical rings (cy, cx, cz, rx, rz[, jag]), bottom to top, each
    with its own centre (jaws, bellies, hems), closed by flat caps or fans to apex points. `jag(s)`
    scales a ring's points one by one: a ragged hem, a fur edge."""
    rr = [ring(r[0], r[1], r[2], r[3], r[4], segments, phase, r[5] if len(r) > 5 else None) for r in rings]
    m.grid(rr, colour, smooth=smooth, apex0=apex0, apex1=apex1, face_colour=face_colour, cap0=cap0, cap1=cap1)


def band(m: RMesh, y0: float, y1: float, cx: float, cz: float, rx: float, rz: float, colour: Rgb, *,
         segments: int = 8, open_ends: bool = True, smooth: bool = True) -> None:
    """A strap round a body (a belt, a bracer seen from outside). Open-ended by default: its inside is
    always hidden by what it wraps, and it never shows from inside, so it needs no caps."""
    rr = [ring(y0, cx, cz, rx, rz, segments), ring(y1, cx, cz, rx, rz, segments)]
    if open_ends:
        _open_grid(m, rr, colour, smooth)
    else:
        m.grid(rr, colour, smooth=smooth)


def _open_grid(m: RMesh, rings, colour: Rgb, smooth: bool) -> None:
    """Quads between rings wound to face outward (the rings run counter-clockwise seen from above,
    bottom to top), with no caps and no closure check."""
    n = len(rings[0])
    ids = [[m.vert(p) for p in r] for r in rings]
    for i in range(len(rings) - 1):
        a, b = ids[i], ids[i + 1]
        for j in range(n):
            k = (j + 1) % n
            m.poly([a[j], b[j], b[k], a[k]], colour, smooth)
    # Wound by construction; check one face against the outward direction and turn them all if wrong.
    start = len(m.faces) - n * (len(rings) - 1)
    idx = m.faces[start][0]
    pa, pb, pc = (m.verts[i] for i in idx[:3])
    nrm = wkm.cross(sub(pb, pa), sub(pc, pa))
    centre = (sum(p[0] for p in rings[0]) / n, rings[0][0][1], sum(p[2] for p in rings[0]) / n)
    out = sub(pa, centre)
    if wkm.dot(nrm, (out[0], 0.0, out[2])) < 0:
        m.faces[start:] = [(list(reversed(f)), c, s) for f, c, s in m.faces[start:]]


def _open_grid_along(m: RMesh, rings, colour: Rgb, centre: Vec, smooth: bool = True) -> None:
    """An open band between rings round any axis, turned to face away from `centre`."""
    n = len(rings[0])
    ids = [[m.vert(p) for p in r] for r in rings]
    start = len(m.faces)
    for i in range(len(rings) - 1):
        a, b = ids[i], ids[i + 1]
        for j in range(n):
            k = (j + 1) % n
            m.poly([a[j], b[j], b[k], a[k]], colour, smooth)
    idx = m.faces[start][0]
    pa, pb, pc = (m.verts[i] for i in idx[:3])
    if wkm.dot(wkm.cross(sub(pb, pa), sub(pc, pa)), sub(pa, centre)) < 0:
        m.faces[start:] = [(list(reversed(f)), c, s) for f, c, s in m.faces[start:]]


def limb(m: RMesh, path, radii, colour: Rgb, *, segments: int = 6, smooth: bool = True, normal0: Vec | None = None) -> None:
    m.sweep(path, radii, colour, segments=segments, smooth=smooth, normal0=normal0)


def ball(m: RMesh, centre: Vec, radii: Vec, colour: Rgb, *, segments: int = 6, rings: int = 4, jitter: float = 0.0,
         seed: int = 1, smooth: bool = True) -> None:
    """An ellipsoid (radii x, y, z), from weapon_kit_mesh's nodule laid along Y."""
    start = len(m.faces)
    m.nodule(centre, (radii[0], radii[2], radii[1]), colour, axis=(0.0, 1.0, 0.0), ref=(1.0, 0.0, 0.0),
             segments=segments, rings=rings, jitter=jitter, seed=seed)
    if smooth:
        m.faces[start:] = [(f, c, True) for f, c, _ in m.faces[start:]]


def shell(m: RMesh, levels, colour: Rgb, *, thickness: float, points: int = 7, smooth: bool = False,
          jag=None, cap_colour: Rgb | None = None, face_colour=None) -> None:
    """A curved sheet with thickness (a cloak, a mantle, a hood, a kilt flap): levels are
    (cy, cx, cz, rx, rz, a0, a1) arcs of an ellipse from angle a0 to a1 (radians, 0 = front -Z,
    + toward +X), bottom to top. Each level becomes one closed loop (outer arc out, inner arc back),
    so the result is a closed solid that shows from both sides; `jag(level, s)` scales a point's
    radius (fur tufts on the bottom level)."""
    loops = []
    for li, (cy, cx, cz, rx, rz, a0, a1) in enumerate(levels):
        outer, inner = [], []
        for s in range(points):
            t = a0 + (a1 - a0) * s / (points - 1)
            k = jag(li, s) if jag else 1.0
            ox, oz = math.sin(t), -math.cos(t)
            outer.append((cx + rx * k * ox, cy, cz + rz * k * oz))
            inner.append((cx + (rx * k - thickness) * ox, cy, cz + (rz * k - thickness) * oz))
        loops.append(outer + list(reversed(inner)))
    m.grid(loops, colour, smooth=smooth, cap_colour=cap_colour, face_colour=face_colour)


def spike(m: RMesh, base: Vec, tip: Vec, radius: float, colour: Rgb, *, segments: int = 4, ref: Vec | None = None) -> None:
    """A cone from a base point to a tip (horn tips, fangs, fur tufts, flint points)."""
    axis = sub(tip, base)
    m.lathe([(0.0, radius), (wkm.length(axis), 0.0)], colour, axis=axis, centre=base, segments=segments, smooth=False,
            ref=ref)


def horn(m: RMesh, path, r0: float, colour: Rgb, tip_colour: Rgb, *, segments: int = 6, normal0: Vec | None = None) -> None:
    """A tapering curved horn or antler tine along a path, its last segment in `tip_colour`."""
    n = len(path)
    radii = [max(r0 * (1 - i / (n - 1)) ** 0.8, r0 * 0.12) for i in range(n)]
    m.sweep(path[:-1], radii[:-1], colour, segments=segments, smooth=True, normal0=normal0, caps=True)
    spike(m, path[-2], path[-1], radii[-2] * 0.98, tip_colour, segments=segments)


def fang_row(m: RMesh, centre: Vec, rx: float, rz: float, a0: float, a1: float, count: int, length: float,
             radius: float, colour: Rgb, *, down: bool = True) -> None:
    """Teeth or fangs hanging from (or standing on) an arc."""
    for i in range(count):
        t = a0 + (a1 - a0) * (i + 0.5) / count
        base = (centre[0] + rx * math.sin(t), centre[1], centre[2] - rz * math.cos(t))
        tip = add(base, (0.0, -length if down else length, 0.0))
        spike(m, base, tip, radius, colour, segments=3)


# --- export -----------------------------------------------------------------------------------


def kit_dir(kit: str, root: str = KITS_ROOT) -> str:
    return os.path.join(root, kit, GLB_DIR)


def palette_card(kit: str):
    m = RMesh(wkm.PALETTE_CARD, kit)
    for i, colour in enumerate(sorted(rpal.allowed(kit))):
        x = i * 0.02
        m.face([(x, 0.0, 0.0), (x + 0.01, 0.0, 0.0), (x, 0.01, 0.0)], colour)
    return m


def bounds_of(meshes) -> tuple[Vec, Vec]:
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    for m in meshes:
        for v in m.verts:
            for i in range(3):
                lo[i] = min(lo[i], v[i])
                hi[i] = max(hi[i], v[i])
    return tuple(lo), tuple(hi)  # type: ignore[return-value]


def r3(v) -> list[float]:
    return [round(float(c), 3) for c in v]


def rig_record(body: Body) -> dict:
    """The kind's entry in RaiderModels.json: everything the client needs, so it never measures."""
    pieces = []
    for k, piece in enumerate(PIECES):
        p = body[piece]
        parts = {kit: ROLE_OF_KIT[kit] for kit, mesh in sorted(p.meshes.items()) if mesh.faces}
        if "raider-cloth" in parts:
            parts["raider-cloth"] = body.cloth_of[piece]
        lo, hi = bounds_of([m for m in p.meshes.values() if m.faces])
        pieces.append({
            "name": piece,
            "stage": k,
            "pivot": r3(body.points[{"head": "head", "torso": "neck", "arm": "shoulder", "legL": "hipL", "legR": "hipR"}[piece]]),
            "parts": parts,
            "triangles": p.tris,
            "bounds": {"min": r3(lo), "max": r3(hi)},
        })
    all_meshes = [m for _, _, m in body.meshes()]
    lo, hi = bounds_of(all_meshes)
    reach = max(math.hypot(v[0], v[2]) for m in all_meshes for v in m.verts)
    # The drawn head is the skull (the skin), not the mane or a crest hanging off it.
    head_meshes = [m for k, m in body["head"].meshes.items() if m.faces and k == "raider-skin"]
    head_meshes = head_meshes or [m for m in body["head"].meshes.values() if m.faces]
    hlo, hhi = bounds_of(head_meshes)
    record = {
        "model": body.model,
        "height": body.height,
        "radius": body.radius,
        "headRadius": body.head_radius,
        "skin": list(body.skin),
        "pieces": pieces,
        "points": {k: r3(v) for k, v in sorted(body.points.items())},
        "legLength": round(body.leg_length, 3),
        "leadLeg": body.lead_leg,
        "armSwingShare": body.arm_swing_share,
        "arm": body.arm,
        "headMeshCentre": r3(((hlo[0] + hhi[0]) / 2, (hlo[1] + hhi[1]) / 2, (hlo[2] + hhi[2]) / 2)),
        "bounds": {"min": r3(lo), "max": r3(hi), "size": r3(tuple(hi[i] - lo[i] for i in range(3)))},
        "reach": round(reach, 3),
        "reachRadii": round(reach / body.radius, 3),
        "triangles": body.tris,
        "meshParts": sum(len([m for m in p.meshes.values() if m.faces]) for p in body.pieces.values()),
    }
    if body.hold:
        record["hold"] = body.hold
    if body.notes:
        record["notes"] = body.notes
    return record


def export_body(body: Body, root: str = KITS_ROOT) -> dict:
    """One GLB per piece per kit, then the rig record beside the gear GLBs."""
    import bpy

    for piece, kit, mesh in body.meshes():
        for w in mesh.warnings:
            print(f"[raider-kit] WARNING: {mesh.name} ({kit}): {w}", flush=True)
        out = kit_dir(kit, root)
        os.makedirs(out, exist_ok=True)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        wkm.export(wkm.build_object(mesh, {}), out)
    record = rig_record(body)
    out = kit_dir("raider-kit", root)
    with open(os.path.join(out, f"{body.model}.rig.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(record, fh, indent=2)
        fh.write("\n")
    return record


def export_palette_cards(root: str = KITS_ROOT) -> None:
    import bpy

    for kit in rpal.KITS:
        out = kit_dir(kit, root)
        os.makedirs(out, exist_ok=True)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        wkm.export(wkm.build_object(palette_card(kit), {}), out)


def write_blueprint(body: Body) -> str:
    """The prop blueprint: piece k's GLBs (one per kit) join at stage k and leave after it."""
    os.makedirs(BLUEPRINTS, exist_ok=True)
    pieces = []
    for k, piece in enumerate(PIECES):
        for kit, mesh in sorted(body[piece].meshes.items()):
            if mesh.faces:
                pieces.append({"kit": kit, "model": mesh.name, "pos": [0, 0, 0], "rotY": 0, "stage": k, "untilStage": k})
    lo, hi = bounds_of([m for _, _, m in body.meshes()])
    span = 2 * math.ceil(max(abs(lo[0]), abs(hi[0]), abs(lo[2]), abs(hi[2])) + 0.5)
    data = {
        "id": body.model,
        "era": ERA,
        "scale": 1.0,
        "footprint": [span, span],
        "note": ("raider kit (tools/assets/raider_kit.py), 1 unit = 1 stud, authored in the body frame (feet at the "
                 "origin, front -Z). Stage k is rigid piece k (head, torso, arm, legL, legR), one piece per kit: "
                 "raider-kit gear (textured), raider-cloth / raider-skin / raider-glow painted by the client. "
                 "The rig is in tools/assets/out/RaiderModels.json."),
        "pieces": pieces,
    }
    path = os.path.join(BLUEPRINTS, f"{body.model}.json")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("{\n")
        for key in ("id", "era", "scale", "footprint", "note"):
            fh.write(f"  {json.dumps(key)}: {json.dumps(data[key])},\n")
        fh.write('  "pieces": [\n')
        fh.write(",\n".join(f"    {json.dumps(p)}" for p in pieces))
        fh.write("\n  ]\n}\n")
    return path


def write_config(records: dict, rig_numbers: dict) -> str:
    """Merge the kinds just built into tools/assets/out/RaiderModels.json (kinds not rebuilt stay)."""
    data = {"version": CONFIG_VERSION, "folder": ERA, "rig": rig_numbers, "kinds": {}}
    if os.path.isfile(CONFIG_OUT):
        with open(CONFIG_OUT, "r", encoding="utf-8") as fh:
            old = json.load(fh)
        data["kinds"].update(old.get("kinds", {}))
    data["rig"] = rig_numbers
    data["kinds"].update(records)
    data["kinds"] = dict(sorted(data["kinds"].items()))
    os.makedirs(os.path.dirname(CONFIG_OUT), exist_ok=True)
    with open(CONFIG_OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=1)
        fh.write("\n")
    return CONFIG_OUT
