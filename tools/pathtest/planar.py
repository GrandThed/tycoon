"""Round 2 of the path look test: the same Village patch baked with **world-planar UVs**, an
**opaque** texture and a **geometric** irregular edge, plus a darker rim ribbon. Ben approved this
variant (C3), so the geometry itself moved to tools/paths/planargeom.py and the real bake
(tools/paths/bake.py) runs the same functions; this file is now just the look test's two-piece
patch on top of them, kept so the approved GLBs can be reproduced byte for byte.

    py tools/pathtest/planar.py     # writes out/{Fill,Rim}_{Lane,Spur}.glb and out/planar.json

Meshes (geometry only; the Y offset is applied by gen_display.py, so C2 and C3 share these uploads):
    Fill_Lane, Fill_Spur   the path surface, edge noise +-EDGE_AMP studs
    Rim_Lane,  Rim_Spur    the same ribbon widened by RIM_BASE (+ its own noise), for C3's dark rim
"""

from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "paths"))
import patch as p1
import planargeom as geom  # noqa: E402

OUT_DIR = p1.OUT_DIR

TILE = 11.0  # studs per texture repeat on both axes (1024 px -> ~93 px per stud)


def ribbon(c, lo, hi, seeds, rim=False):
    return geom.ribbon(c, geom.chain_window(c, lo, hi), seeds, rim=rim, tile=TILE)


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
        geom.write_glb(path, f"PathTest{name.replace('_', '')}", mesh, generator="EraCityTycoon pathtest")
        lo, hi = geom.bounds(mesh["verts"])
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
    print(
        f"tile {TILE} studs, edge noise +-{geom.EDGE_AMP} studs, "
        f"rim band {geom.RIM_BASE - geom.RIM_JITTER:.2g}-{geom.RIM_BASE + geom.RIM_JITTER:.2g} studs"
    )


if __name__ == "__main__":
    main()
