"""The approved baked-path geometry (INTERFACES "Wave 1d - baked paths": the C3 bake-off winner).

Moved here from tools/pathtest/planar.py so the real bake (tools/paths/bake.py) and the look test
that Ben approved run the *same* code. tools/pathtest/planar.py now imports this module and still
writes byte-identical GLBs, which is the regression test for the move.

The recipe, unchanged from the approved test:
  * world-planar UVs (u = x / TILE, v = z / TILE in plot-local studs) on every piece, so two
    pieces covering the same ground sample exactly the same texel and their overlap is invisible;
  * fully opaque textures, no alpha anywhere, so even a coplanar overlap resolves to one colour;
  * the irregular edge cut into the mesh outline by smooth deterministic 1D noise (three sines at
    1.9-3.7 stud wavelengths, +-EDGE_AMP studs, independent per side, tapering out at tips);
  * a rim ribbon per piece: the same outline widened by RIM_BASE plus its own smaller noise, run
    RIM_CAP_EXTRA past every tip, drawn in a darker copy of the same texture below the fill.

Geometry is plot-local, y = 0 apart from the CROWN hair of centre lift (so no uploaded mesh has a
zero-height bounding box, which the importer rejects). The Y heights of rim and fill come from
CityDressing.json `paths` and are applied by the template, not baked in.
"""

from __future__ import annotations

import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "assets"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "pathmock"))
import glbtools  # noqa: E402
import pathgeom as pg  # noqa: E402

# Look constants. Every one of these was in the bake Ben approved; INTERFACES "Wave 1d" freezes
# them, so they are code, not config.
EDGE_AMP = 0.35  # studs of outline displacement, per side, independent noise
EDGE_WAVELENGTHS = (3.7, 2.6, 1.9)  # studs; the amplitude sum stays within +-1 before scaling
EDGE_AMPS = (0.55, 0.3, 0.15)
EDGE_TAPER = 1.3  # noise fades out this far from a tip, so caps stay round
RIM_BASE = 0.4  # the rim ribbon's outline sits this much outside the fill's...
RIM_JITTER = 0.2  # ...plus its own noise, so the visible rim band is 0.2 - 0.6 studs wide
RIM_CAP_EXTRA = 0.45  # and it runs this much past the fill at every tip
CROWN = 0.005  # a hair of centre lift so no uploaded mesh has a zero-height bounding box
MESH_WIDTH_FACTOR = 1.2  # mesh width / nominal path width (pathtest's EDGE)
MIN_HALF_WIDTH = 0.004  # a cap never collapses a cross-section to exactly zero width

STEP = 0.25  # studs between cross-sections: ~8 per shortest noise wavelength, so the edge is smooth
TURN_DEG = 2.5  # ...or sooner when the heading turns this much
CAP_STEP = 0.12  # inside a cap or a flare
DENSE = 0.05  # the candidate grid the two rules above pick from

COLUMNS = 3  # left outline, centre, right outline: u and v are affine in (x, z), so 3 is exact


def samples(cur, lo, hi, dense_ranges):
    """Cross-section positions: every STEP studs, sooner on a bend or inside a dense range.

    The outline noise (not the curvature) sets how often a cross-section is needed, which is why
    STEP is so much finer than the ribbon renderer's sample spacing."""
    n = max(2, math.ceil((hi - lo) / DENSE))
    grid = [lo + (hi - lo) * k / n for k in range(n + 1)]
    out = [grid[0]]
    last = cur.tangent(max(0.0, min(cur.total, grid[0])), 0.2)
    for s in grid[1:-1]:
        t = cur.tangent(max(0.0, min(cur.total, s)), 0.2)
        turn = math.degrees(math.acos(max(-1.0, min(1.0, pg.dot(t, last)))))
        step = CAP_STEP if any(a <= s <= b for a, b in dense_ranges) else STEP
        if s - out[-1] >= step - 1e-9 or turn >= TURN_DEG:
            out.append(s)
            last = t
    out.append(grid[-1])
    return out


def phases(seed: int) -> list[float]:
    """Deterministic phases; plain float maths so this ports to Luau unchanged."""
    out = []
    for k in range(len(EDGE_WAVELENGTHS)):
        x = math.sin((seed + 1) * 12.9898 + k * 78.233) * 43758.5453
        out.append((x - math.floor(x)) * 2 * math.pi)
    return out


def edge_noise(s: float, ph: list[float]) -> float:
    """Smooth 1D noise in [-1, 1]: three sines at 1.9 - 3.7 stud wavelengths."""
    total = 0.0
    for amp, wl, phase in zip(EDGE_AMPS, EDGE_WAVELENGTHS, ph):
        total += amp * math.sin(2 * math.pi * s / wl + phase)
    return total


def window(lo: float, hi: float, start_cap: float, end_cap: float, extend_start: bool, extend_end: bool) -> dict:
    """One piece's arc range on its chain's final curve, with how each end is finished.

    `start_cap` / `end_cap` are the lengths over which the half-width runs out to 0 on the
    elliptical cap profile; 0 means an open full-width end (only the plot entrance). `extend_*`
    says whether the rim runs RIM_CAP_EXTRA past that tip: it does at a free or interior tip, and
    does not where the fill already ends in a join extension or stays open, because there the
    extra rim would show across a path mouth."""
    return {
        "lo": lo,
        "hi": hi,
        "start_cap": start_cap,
        "end_cap": end_cap,
        "extend_start": extend_start,
        "extend_end": extend_end,
    }


def chain_window(c: dict, lo: float, hi: float, cap_length: float = pg.CAP_LENGTH) -> dict:
    """The window for an arc range cut straight out of one chain: an end that sits on the chain's
    own end keeps its join / round extension, any other end gets a `cap_length` round tip.

    tools/pathtest/planar.py's rule, kept here so the look test and the bake share it. The real
    bake calls `window` directly, because a piece's interior ends must cap over exactly the
    overlap its neighbour covers (tools/paths/network.py)."""
    total = c["final"].total
    ext_s, ext_e = c["ext"]
    at_start, at_end = lo <= 1e-6, hi >= total - 1e-6
    return window(
        lo,
        hi,
        ext_s if (ext_s > 0 and at_start) else cap_length,
        ext_e if (ext_e > 0 and at_end) else cap_length,
        not at_start or ext_s == 0,
        not at_end or ext_e == 0,
    )


def ribbon(c: dict, win: dict, seeds: tuple[int, int], rim: bool = False, tile: float = 11.0) -> dict:
    """One flat ribbon over `win` of chain `c`'s final curve, at y = 0 (plus the crown).

    Cross-section: left outline, centre, right outline. Each outline is pushed out by its own
    noise; a rim adds RIM_BASE plus a second, independent noise, so its edge wanders differently
    from the fill it surrounds but never crosses inside it.

    The noise seeds come from the *chain*, not the piece (tools/paths/network.py), so two pieces
    that meet at a node carry the same outline function of arc length: each tapers its copy to 0
    only inside its own cap, which the neighbour covers at full width.
    """
    cur = c["final"]
    total = cur.total
    ext_s, ext_e = c["ext"]
    lo, hi = win["lo"], win["hi"]
    start_cap, end_cap = win["start_cap"], win["end_cap"]
    extra = RIM_CAP_EXTRA if rim else 0.0
    lo_r = max(-extra, lo - (extra if win["extend_start"] else 0.0))
    hi_r = min(total + extra, hi + (extra if win["extend_end"] else 0.0))
    # The cap grows by `extra` at both ends whether or not that tip was extended: where it was
    # not (a join extension), the rim then runs out a little before the fill does, which is what
    # keeps a rim from showing past a joiner's tip on its host.
    start_cap, end_cap = start_cap + extra, end_cap + extra
    dense = [(lo_r, lo_r + start_cap), (hi_r - end_cap, hi_r)]
    if c["join_end"]:
        dense.append((total - ext_e - pg.FLARE_LENGTH, hi_r))
    xs = samples(cur, lo_r, hi_r, dense)
    left_ph, right_ph = phases(seeds[0]), phases(seeds[1])

    verts, uvs, tris = [], [], []
    for s in xs:
        point = cur.point(max(0.0, min(total, s)))
        t = cur.tangent(max(0.0, min(total, s)), 0.2)
        nrm = (-t[1], t[0])
        hw = MESH_WIDTH_FACTOR * c["width_at"](s - ext_s) / 2
        flare = 1.0
        if c["join_start"]:
            flare = max(flare, 1 + pg.FLARE_GAIN * pg.smoothstep(1 - (s - ext_s) / pg.FLARE_LENGTH))
        if c["join_end"]:
            flare = max(flare, 1 + pg.FLARE_GAIN * pg.smoothstep(1 - (total - ext_e - s) / pg.FLARE_LENGTH))
        cap = 1.0
        if start_cap > 0:
            x0 = (s - lo_r) / start_cap
            if x0 < 1:
                cap = min(cap, math.sqrt(max(0.0, 1 - (1 - x0) ** 2)))
        if end_cap > 0:
            x1 = (hi_r - s) / end_cap
            if x1 < 1:
                cap = min(cap, math.sqrt(max(0.0, 1 - (1 - x1) ** 2)))
        h = max(hw * flare * cap, MIN_HALF_WIDTH)
        taper = pg.smoothstep(min(s - lo_r, hi_r - s) / EDGE_TAPER)
        base = RIM_BASE + h if rim else h
        jitter = RIM_JITTER if rim else EDGE_AMP
        hl = base + jitter * taper * edge_noise(s, left_ph)
        hr = base + jitter * taper * edge_noise(s, right_ph)
        crown = CROWN * min(1.0, cap)
        for offset, lift in ((hl, 0.0), (0.0, crown), (-hr, 0.0)):
            q = pg.add(point, pg.mul(nrm, offset))
            verts.append((q[0], lift, q[1]))
            uvs.append((q[0] / tile, q[1] / tile))
    for i in range(len(xs) - 1):
        for j in range(COLUMNS - 1):
            l0, r0 = COLUMNS * i + j, COLUMNS * i + j + 1
            l1, r1 = l0 + COLUMNS, r0 + COLUMNS
            for a, b, cc in ((l0, l1, r0), (r0, l1, r1)):
                va, vb, vc = verts[a], verts[b], verts[cc]
                ny = (vb[2] - va[2]) * (vc[0] - va[0]) - (vb[0] - va[0]) * (vc[2] - va[2])
                if ny < 0:  # glTF front faces are counter-clockwise seen from +Y
                    b, cc = cc, b
                tris.append((a, b, cc))
    return {"verts": verts, "uvs": uvs, "tris": tris, "sections": len(xs), "flipped": 0}


def bounds(verts):
    lo = [min(v[i] for v in verts) for i in range(3)]
    hi = [max(v[i] for v in verts) for i in range(3)]
    return lo, hi


def write_glb(path, name, mesh, generator: str = "EraCityTycoon paths"):
    """Positions, up normals, TEXCOORD_0 and uint32 indices; no material, so Roblox makes exactly
    one untextured MeshPart and the texture is applied by the template."""
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
        "asset": {"version": "2.0", "generator": generator},
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
    return len(data)
