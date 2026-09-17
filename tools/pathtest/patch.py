"""Path look test (third attempt): bake one Village test patch -- a curved stretch of the main lane
plus the Stables spur that joins it -- into two GLB meshes for upload as Roblox Model assets.

    py tools/pathtest/patch.py            # writes tools/pathtest/out/{Lane,Spur}.glb and patch.json

The centrelines, width jitter, flare and caps are tools/pathmock/pathgeom.py's (imported, not
copied), so the patch is exactly what the full network would draw there. Only the cross-section
differs from the mock's ribbon: the textures here are solid across most of the width, so the rim
band (where alpha ramps to 0) is pinned to a constant world width at each outline, and the
sampling is adaptive so the bends stay smooth up close.

Coordinates are plot-local studs (Roblox axes: Y up, 1 glTF unit = 1 stud), so a later bake of
all 28 paths can reuse them unchanged. patch.json carries what the Blender preview and the Studio
display generator need: triangles for the preview, per-mesh bounding boxes, the patch centre and
the Stables slot.
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "pathmock"))
sys.path.insert(0, os.path.join(REPO, "tools", "assets"))
import glbtools  # noqa: E402
import pathgeom as pg  # noqa: E402

OUT_DIR = os.path.join(HERE, "out")

LANE_ID = "lane1"
SPUR_ID = "stables"
BUILDING_MODEL = "Stables"
# Arc-length window on lane1's final curve: east->south bend, the Stables T-junction, south->west bend.
LANE_WINDOW = (86.0, 119.0)

EDGE = 1.2  # mesh width / nominal path width: the rim lives in the extra 20%
RIM_WORLD = 0.36  # studs from the outline to where the texture is fully opaque
RIM_V = 0.1  # texture rows v in [0, RIM_V] (and mirrored) hold the rim; see textures.py
TEXTURE_LENGTH = 7.2  # studs per texture repeat along u: 1024 px, matching ~142 px/stud across
CROWN = 0.01  # centre lift, so the mesh bounding box is never zero-height
LAYER_LIFT = 0.024  # spur above lane (the mock's main lane layer 0 -> spur layer 2)
Y_BASE = 0.04  # lane bottom above the grass top

MAX_STEP = 0.5  # studs between cross-sections on straight parts
MAX_TURN_DEG = 2.5  # ...and at most this much heading change between cross-sections
CAP_STEP = 0.15  # inside the rounded caps and the flare
DENSE = 0.05


def samples(cur, lo, hi, dense_ranges):
    """Adaptive cross-section positions: every MAX_STEP studs, or sooner when the heading turns by
    MAX_TURN_DEG or inside a cap / flare range."""
    n = max(2, math.ceil((hi - lo) / DENSE))
    grid = [lo + (hi - lo) * k / n for k in range(n + 1)]
    out = [grid[0]]
    last_t = cur.tangent(grid[0], 0.2)
    for s in grid[1:-1]:
        t = cur.tangent(s, 0.2)
        turn = math.degrees(math.acos(max(-1.0, min(1.0, pg.dot(t, last_t)))))
        step = CAP_STEP if any(a <= s <= b for a, b in dense_ranges) else MAX_STEP
        if s - out[-1] >= step - 1e-9 or turn >= MAX_TURN_DEG:
            out.append(s)
            last_t = t
    out.append(grid[-1])
    return out


def ribbon(c, lo, hi, y0):
    cur = c["final"]
    total = cur.total
    ext_s, ext_e = c["ext"]
    start_cap = ext_s if (ext_s > 0 and lo <= 1e-6) else pg.CAP_LENGTH
    end_cap = ext_e if (ext_e > 0 and hi >= total - 1e-6) else pg.CAP_LENGTH
    join_lo, join_hi = ext_s, total - ext_e
    dense = [(lo, lo + start_cap), (hi - end_cap, hi)]
    if c["join_end"]:
        dense.append((join_hi - pg.FLARE_LENGTH, hi))
    xs = samples(cur, lo, hi, dense)

    verts, uvs, tris = [], [], []
    for s in xs:
        p = cur.point(s)
        t = cur.tangent(s, 0.2)
        nrm = (-t[1], t[0])
        hw = EDGE * c["width_at"](s - ext_s) / 2
        flare = 1.0
        if c["join_start"]:
            flare = max(flare, 1 + pg.FLARE_GAIN * pg.smoothstep(1 - (s - join_lo) / pg.FLARE_LENGTH))
        if c["join_end"]:
            flare = max(flare, 1 + pg.FLARE_GAIN * pg.smoothstep(1 - (join_hi - s) / pg.FLARE_LENGTH))
        cap = 1.0
        x0 = (s - lo) / start_cap
        if x0 < 1:
            cap = min(cap, math.sqrt(max(0.0, 1 - (1 - x0) ** 2)))
        x1 = (hi - s) / end_cap
        if x1 < 1:
            cap = min(cap, math.sqrt(max(0.0, 1 - (1 - x1) ** 2)))
        h = max(hw * flare * cap, 0.004)
        # The rim keeps its world width along the whole outline; near a tip it may take at most half
        # the section, so the tip stays a rounded solid end with a soft rim instead of a smear.
        inner = max(h - RIM_WORLD, h * 0.5)
        u = s / TEXTURE_LENGTH + c["u_offset"]
        crown = CROWN * min(1.0, h / (EDGE * 1.5))
        # Sliding v into the rim to dissolve the joining end over the lane was tried: it smears the
        # pebbles into streaks, which look worse than the spur's soft round end sitting on the lane.
        columns = ((h, 0.0, 0.0), (inner, RIM_V, crown * 0.5), (0.0, 0.5, crown), (-inner, 1 - RIM_V, crown * 0.5), (-h, 1.0, 0.0))
        for offset, v, lift in columns:
            q = pg.add(p, pg.mul(nrm, offset))
            verts.append((q[0], y0 + lift, q[1]))
            uvs.append((u, v))
    cols = 5
    flipped = 0
    for i in range(len(xs) - 1):
        for j in range(cols - 1):
            l0, r0 = cols * i + j, cols * i + j + 1
            l1, r1 = l0 + cols, r0 + cols
            for a, b, cc in ((l0, l1, r0), (r0, l1, r1)):
                va, vb, vc = verts[a], verts[b], verts[cc]
                ny = (vb[2] - va[2]) * (vc[0] - va[0]) - (vb[0] - va[0]) * (vc[2] - va[2])
                if ny < 0:  # glTF front faces are counter-clockwise seen from +Y
                    b, cc = cc, b
                    flipped += 1
                tris.append((a, b, cc))
    return {"verts": verts, "uvs": uvs, "tris": tris, "sections": len(xs), "flipped": flipped}


def build():
    era, chains = pg.build_chains()
    pg.prepare(era, chains)
    for c in chains:
        c["u_offset"] = (c["phase_key"] * 0.618034) % 1.0
    by = {c["id"]: c for c in chains}
    lane, spur = by[LANE_ID], by[SPUR_ID]
    meshes = {
        "Lane": ribbon(lane, LANE_WINDOW[0], LANE_WINDOW[1], Y_BASE),
        "Spur": ribbon(spur, 0.0, spur["final"].total, Y_BASE + LAYER_LIFT),
    }
    slot = next(s for s in era.slots if s["id"] == SPUR_ID)
    return meshes, slot


def bounds(verts):
    lo = [min(v[i] for v in verts) for i in range(3)]
    hi = [max(v[i] for v in verts) for i in range(3)]
    return lo, hi


def write_glb(path, name, mesh):
    """Positions, up normals, TEXCOORD_0 and uint32 indices; no material, so Roblox makes exactly one
    untextured MeshPart and the texture is applied by the display template."""
    verts, uvs, tris = mesh["verts"], mesh["uvs"], mesh["tris"]
    binary = bytearray()
    views = []

    def add_view(blob, target, stride=None):
        while len(binary) % 4:
            binary.append(0)
        view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(blob), "target": target}
        if stride:
            view["byteStride"] = stride
        views.append(view)
        binary.extend(blob)
        return len(views) - 1

    pos = add_view(b"".join(struct.pack("<fff", *v) for v in verts), 34962, 12)
    nrm = add_view(struct.pack("<fff", 0.0, 1.0, 0.0) * len(verts), 34962, 12)
    uv = add_view(b"".join(struct.pack("<ff", *t) for t in uvs), 34962, 8)
    idx = add_view(b"".join(struct.pack("<III", *t) for t in tris), 34963)
    while len(binary) % 4:
        binary.append(0)
    lo, hi = bounds(verts)
    doc = {
        "asset": {"version": "2.0", "generator": "EraCityTycoon pathtest"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3}]}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": pos, "componentType": glbtools.FLOAT, "count": len(verts), "type": "VEC3", "min": lo, "max": hi},
            {"bufferView": nrm, "componentType": glbtools.FLOAT, "count": len(verts), "type": "VEC3"},
            {"bufferView": uv, "componentType": glbtools.FLOAT, "count": len(uvs), "type": "VEC2"},
            {"bufferView": idx, "componentType": glbtools.UNSIGNED_INT, "count": len(tris) * 3, "type": "SCALAR"},
        ],
        "buffers": [{"byteLength": len(binary)}],
    }
    data = glbtools.write_glb(doc, bytes(binary))
    problems = glbtools.roblox_problems(data)
    if problems:
        raise SystemExit(f"{path}: not importable: {problems}")
    with open(path, "wb") as fh:
        fh.write(data)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    meshes, slot = build()
    info = {"textureLength": TEXTURE_LENGTH, "rimV": RIM_V, "meshes": {}}
    all_lo, all_hi = [1e9] * 3, [-1e9] * 3
    for name, mesh in meshes.items():
        path = os.path.join(OUT_DIR, f"{name}.glb")
        write_glb(path, f"PathTest{name}", mesh)
        lo, hi = bounds(mesh["verts"])
        all_lo = [min(a, b) for a, b in zip(all_lo, lo)]
        all_hi = [max(a, b) for a, b in zip(all_hi, hi)]
        info["meshes"][name] = {
            "glb": os.path.relpath(path, REPO).replace(os.sep, "/"),
            "triangles": len(mesh["tris"]),
            "vertices": len(mesh["verts"]),
            "sections": mesh["sections"],
            "min": [round(v, 4) for v in lo],
            "max": [round(v, 4) for v in hi],
            "centre": [round((a + b) / 2, 4) for a, b in zip(lo, hi)],
            "size": [round(b - a, 4) for a, b in zip(lo, hi)],
            "verts": [[round(c, 4) for c in v] for v in mesh["verts"]],
            "uvs": [[round(c, 5) for c in t] for t in mesh["uvs"]],
            "tris": mesh["tris"],
        }
        m = info["meshes"][name]
        print(f"{name}: {m['triangles']} tris, {m['vertices']} verts, {m['sections']} sections, {mesh['flipped']} rewound, size {m['size']}")
    info["patchCentre"] = [round((all_lo[0] + all_hi[0]) / 2, 3), 0.0, round((all_lo[2] + all_hi[2]) / 2, 3)]
    info["building"] = {"model": BUILDING_MODEL, "slot": SPUR_ID, "position": [slot["position"][0], 0.0, slot["position"][1]], "rotationY": slot["rotation"]}
    with open(os.path.join(OUT_DIR, "patch.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(info, fh, separators=(",", ":"))
    print("patch centre", info["patchCentre"], "bbox", [round(v, 2) for v in all_lo], [round(v, 2) for v in all_hi])


if __name__ == "__main__":
    main()
