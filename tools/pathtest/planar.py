"""Round 2 of the path look test: the same Village patch baked with **world-planar UVs**, an
**opaque** texture and a **geometric** irregular edge, plus an optional darker rim ribbon.

    py tools/pathtest/planar.py     # writes out/{Fill,Rim}_{Lane,Spur}.glb and out/planar.json

Why: in round 1 the UVs ran along each ribbon, so the lane and the spur sampled different texels
where they overlap and the spur's alpha rim was drawn over the lane - Ben could still see the
overlap. Here every piece maps u = x / TILE, v = z / TILE in patch coordinates, so two pieces that
cover the same ground sample exactly the same texel. With no alpha anywhere, an overlap (even a
coplanar one, even z-fighting) is invisible: both surfaces resolve to the same colour and the same
up normal. The soft alpha rim is replaced by the mesh outline itself, displaced by smooth
deterministic 1D noise, which is what gives the path a crisp but irregular edge.

Meshes (geometry only; the Y offset is applied by gen_display.py, so C2 and C3 share these uploads):
    Fill_Lane, Fill_Spur   the path surface, edge noise +-EDGE_AMP studs
    Rim_Lane,  Rim_Spur    the same ribbon widened by RIM_BASE (+ its own noise), for C3's dark rim

C2 puts both fills at one height (coplanar). C3 puts the rims below the fills, so a rim is always
covered by any fill above it: the lane's rim across the spur mouth disappears under the spur fill,
and rim-over-rim overlaps are identical texels.

Geometry comes from tools/pathmock/pathgeom.py through tools/pathtest/patch.py (same centrelines,
width jitter, flare and caps), so round 1 and round 2 are the same path.
"""

from __future__ import annotations

import json
import math
import os

import patch as p1

OUT_DIR = p1.OUT_DIR

TILE = 11.0  # studs per texture repeat on both axes (1024 px -> ~93 px per stud)
EDGE_AMP = 0.35  # studs of outline displacement, per side, independent noise
EDGE_WAVELENGTHS = (3.7, 2.6, 1.9)  # studs; the sum stays within +-1 before scaling
EDGE_TAPER = 1.3  # noise fades out this far from a tip, so caps stay round
RIM_BASE = 0.4  # the rim ribbon's outline sits this much outside the fill's...
RIM_JITTER = 0.2  # ...plus its own noise, so the visible rim band is 0.2 - 0.6 studs wide
RIM_CAP_EXTRA = 0.45  # and it runs this much past the fill at every tip
CROWN = 0.005  # a hair of centre lift so no uploaded mesh has a zero-height bounding box

STEP = 0.25  # studs between cross-sections: ~8 per shortest noise wavelength, so the edge is smooth
TURN_DEG = 2.5
CAP_STEP = 0.12
DENSE = 0.05


def samples(cur, lo, hi, dense_ranges):
    """Like patch.samples but at this file's finer spacing, because the outline noise (not the
    curvature) sets how often a cross-section is needed."""
    n = max(2, math.ceil((hi - lo) / DENSE))
    grid = [lo + (hi - lo) * k / n for k in range(n + 1)]
    out = [grid[0]]
    last = cur.tangent(max(0.0, min(cur.total, grid[0])), 0.2)
    for s in grid[1:-1]:
        t = cur.tangent(max(0.0, min(cur.total, s)), 0.2)
        turn = math.degrees(math.acos(max(-1.0, min(1.0, p1.pg.dot(t, last)))))
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
    amps = (0.55, 0.3, 0.15)
    total = 0.0
    for amp, wl, phase in zip(amps, EDGE_WAVELENGTHS, ph):
        total += amp * math.sin(2 * math.pi * s / wl + phase)
    return total


def ribbon(c, lo, hi, seeds, rim=False):
    """One flat ribbon over arc lengths [lo, hi] of chain c, at y = 0.

    Cross-section: left outline, centre, right outline. The texture is planar, so three columns are
    enough - u and v are affine in (x, z) and interpolate exactly across each triangle. Each outline
    is pushed out by its own noise; a rim ribbon adds RIM_BASE plus a second, independent noise, so
    its edge wanders differently from the fill it surrounds but never crosses inside it.
    """
    cur = c["final"]
    total = cur.total
    ext_s, ext_e = c["ext"]
    extra = RIM_CAP_EXTRA if rim else 0.0
    lo_r, hi_r = lo - (extra if lo > 1e-6 or ext_s == 0 else 0.0), hi + (extra if hi < total - 1e-6 or ext_e == 0 else 0.0)
    lo_r, hi_r = max(0.0 - extra, lo_r), min(total + extra, hi_r)
    start_cap = (ext_s if (ext_s > 0 and lo <= 1e-6) else p1.pg.CAP_LENGTH) + extra
    end_cap = (ext_e if (ext_e > 0 and hi >= total - 1e-6) else p1.pg.CAP_LENGTH) + extra
    dense = [(lo_r, lo_r + start_cap), (hi_r - end_cap, hi_r)]
    if c["join_end"]:
        dense.append((total - ext_e - p1.pg.FLARE_LENGTH, hi_r))
    xs = samples(cur, lo_r, hi_r, dense)
    left_ph, right_ph = phases(seeds[0]), phases(seeds[1])

    verts, uvs, tris = [], [], []
    for s in xs:
        point = cur.point(max(0.0, min(total, s)))
        t = cur.tangent(max(0.0, min(total, s)), 0.2)
        nrm = (-t[1], t[0])
        hw = p1.EDGE * c["width_at"](s - ext_s) / 2
        flare = 1.0
        if c["join_start"]:
            flare = max(flare, 1 + p1.pg.FLARE_GAIN * p1.pg.smoothstep(1 - (s - ext_s) / p1.pg.FLARE_LENGTH))
        if c["join_end"]:
            flare = max(flare, 1 + p1.pg.FLARE_GAIN * p1.pg.smoothstep(1 - (total - ext_e - s) / p1.pg.FLARE_LENGTH))
        cap = 1.0
        x0 = (s - lo_r) / start_cap
        if x0 < 1:
            cap = min(cap, math.sqrt(max(0.0, 1 - (1 - x0) ** 2)))
        x1 = (hi_r - s) / end_cap
        if x1 < 1:
            cap = min(cap, math.sqrt(max(0.0, 1 - (1 - x1) ** 2)))
        h = max(hw * flare * cap, 0.004)
        taper = p1.pg.smoothstep(min(s - lo_r, hi_r - s) / EDGE_TAPER)
        base = RIM_BASE + h if rim else h
        jitter = RIM_JITTER if rim else EDGE_AMP
        hl = base + jitter * taper * edge_noise(s, left_ph)
        hr = base + jitter * taper * edge_noise(s, right_ph)
        crown = CROWN * min(1.0, cap)
        for offset, lift in ((hl, 0.0), (0.0, crown), (-hr, 0.0)):
            q = p1.pg.add(point, p1.pg.mul(nrm, offset))
            verts.append((q[0], lift, q[1]))
            uvs.append((q[0] / TILE, q[1] / TILE))
    cols = 3
    for i in range(len(xs) - 1):
        for j in range(cols - 1):
            l0, r0 = cols * i + j, cols * i + j + 1
            l1, r1 = l0 + cols, r0 + cols
            for a, b, cc in ((l0, l1, r0), (r0, l1, r1)):
                va, vb, vc = verts[a], verts[b], verts[cc]
                ny = (vb[2] - va[2]) * (vc[0] - va[0]) - (vb[0] - va[0]) * (vc[2] - va[2])
                if ny < 0:
                    b, cc = cc, b
                tris.append((a, b, cc))
    return {"verts": verts, "uvs": uvs, "tris": tris, "sections": len(xs), "flipped": 0}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    era, chains = p1.pg.build_chains()
    p1.pg.prepare(era, chains)
    for c in chains:
        c["u_offset"] = 0.0  # planar UVs ignore it; kept so pathgeom's ribbon helpers stay usable
    by = {c["id"]: c for c in chains}
    lane, spur = by[p1.LANE_ID], by[p1.SPUR_ID]
    lane_window = p1.LANE_WINDOW
    meshes = {
        "Fill_Lane": ribbon(lane, lane_window[0], lane_window[1], (11, 12)),
        "Fill_Spur": ribbon(spur, 0.0, spur["final"].total, (21, 22)),
        "Rim_Lane": ribbon(lane, lane_window[0], lane_window[1], (31, 32), rim=True),
        "Rim_Spur": ribbon(spur, 0.0, spur["final"].total, (41, 42), rim=True),
    }
    js = lane["final"].project(spur["final"].p[-1])[1]
    jp = lane["final"].point(js)
    info = {"tile": TILE, "junction": [round(jp[0], 3), round(jp[1], 3)], "meshes": {}}
    for name, mesh in meshes.items():
        path = os.path.join(OUT_DIR, f"{name}.glb")
        p1.write_glb(path, f"PathTest{name.replace('_', '')}", mesh)
        lo, hi = p1.bounds(mesh["verts"])
        info["meshes"][name] = {
            "glb": f"tools/pathtest/out/{name}.glb",
            "triangles": len(mesh["tris"]),
            "vertices": len(mesh["verts"]),
            "sections": mesh["sections"],
            "min": [round(v, 4) for v in lo],
            "max": [round(v, 4) for v in hi],
            "centre": [round((a + b) / 2, 4) for a, b in zip(lo, hi)],
            "size": [round(b - a, 4) for a, b in zip(lo, hi)],
            "verts": [[round(v, 4) for v in vert] for vert in mesh["verts"]],
            "uvs": [[round(v, 5) for v in uv] for uv in mesh["uvs"]],
            "tris": mesh["tris"],
        }
        m = info["meshes"][name]
        print(f"{name}: {m['triangles']} tris, {m['vertices']} verts, {m['sections']} sections, size {m['size']}")
    with open(os.path.join(OUT_DIR, "planar.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(info, fh, separators=(",", ":"))
    print(f"tile {TILE} studs, edge noise +-{EDGE_AMP} studs, rim band {RIM_BASE - RIM_JITTER:.2g}-{RIM_BASE + RIM_JITTER:.2g} studs")


if __name__ == "__main__":
    main()
