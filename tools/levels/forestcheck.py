"""The Forest Road dresser's QA gate: `py tools/levels/forest.py check`.

A fresh build in memory is compared with the committed data file, then every rule of
tools/levels/forest.py's docstring is proved on that build. One line per failure, nothing written.

  1. The data file equals a fresh build, and its planHash is the current inputs' (a layout, art
     or kit change since the last bake is a re-bake and a paste: "stale").
  2. No collidable dressing: no prop, mesh or placement carries collision; the only new collidable
     pieces are the tree-line walls, each in the character-only ArenaBarrier group.
  3. No new standable top: every wall's top stands UNCLIMB over every walkable top within
     UNCLIMB_REACH, no wall reaches into walkable ground or a designed drop, every wall is at
     least a stud thick and lies inside the wire's +-1,000 studs.
  4. The region's walking space: inside any plateau cell, from its floor up to REACH_ABOVE, no
     dressing geometry stands more than 4 studs over the floor (0.3 of slack at a cell's edge),
     except a spawn tent inside its own layout marker.
  5. Camp C: nothing inside the walled rectangle rises over its wall's top, and no placed piece
     there over the top less the camp's sightMargin.
  6. Coplanar faces of two different looks never overlap (texture meshes, palette colours, props
     and the layout Parts the dressing keeps visible), down-facing bottoms under the ground aside.
  7. The kit's own rules (forest_kit.problems), every mesh within the importer's limits, the
     triangle budget within 10 per cent, every prop a kit piece, every `with` a real block.
"""

from __future__ import annotations

import json
import math
import os

import forest as F
import forest_kit as kit
import levelmesh as lm
from levelmesh import Rect

EDGE_SLACK = 0.3


def run(build, data_path) -> list[str]:
    out: list[str] = []
    level = build.level
    fresh = build.data()
    fresh["paletteSwatches"] = lm.Palette().record()
    if not os.path.isfile(data_path):
        out.append(f"no data file at {data_path}: run `py tools/levels/forest.py build`")
    else:
        with open(data_path, encoding="utf-8") as fh:
            committed = json.load(fh)
        if committed.get("planHash") != fresh["planHash"]:
            out.append(f"stale: the data file's planHash {committed.get('planHash')} is not the inputs' {fresh['planHash']} (re-bake, re-upload, one paste)")
        elif json.dumps(committed, sort_keys=True) != json.dumps(json.loads(json.dumps(fresh)), sort_keys=True):
            out.append("the data file differs from a fresh build of the same inputs (run build; never hand-edit it)")
    out += collision_rules(fresh)
    out += barrier_rules(build, fresh)
    out += region_rule(build)
    out += clearing_rule(build)
    out += coplanar_rule(build)
    out += kit.problems()
    for m in build.meshes:
        out += m.problems()
    total = build.triangles()
    if total > F.TRI_BUDGET * 1.1:
        out.append(f"{total} triangles, over the budget {F.TRI_BUDGET} by more than 10 per cent")
    blocks = {b["name"] for b in level.layout["blocks"]}
    for p in fresh["props"]:
        if p["piece"] not in kit.PIECES:
            out.append(f"prop {p['piece']} is not a forest-kit piece")
        if p.get("with") and p["with"] not in blocks:
            out.append(f"prop {p['piece']} goes with block {p['with']}, which the layout does not have")
    fires = {(e["x"], e["z"]) for e in fresh["effects"]}
    for p in fresh["props"]:
        if p.get("effect") == "fire" and (p["x"], p["z"]) not in fires:
            out.append(f"campfire at ({p['x']}, {p['z']}) has no fire effect entry")
    return out


def collision_rules(data) -> list[str]:
    out = []
    for p in data["props"]:
        if p.get("collide"):
            out.append(f"prop {p['piece']} at ({p['x']}, {p['z']}) is collidable: dressing never collides")
    for m in data["meshes"]:
        if m.get("collide"):
            out.append(f"mesh {m['name']} is collidable: dressing never collides")
    for b in data["barriers"]:
        if b.get("group") != "ArenaBarrier":
            out.append(f"{b['name']}: a tree-line wall must be character-only (ArenaBarrier), not {b.get('group')}")
    return out


def barrier_rules(build, data) -> list[str]:
    out = []
    level = build.level
    parts = level.union_parts()
    walks = [(w.rect, w.top) for w in level.walks]
    for b in data["barriers"]:
        r = Rect.of(b)
        top = b["y"] + b["sy"] / 2
        for wr, wtop in walks:
            dx = max(0.0, wr.x0 - r.x1, r.x0 - wr.x1)
            dz = max(0.0, wr.z0 - r.z1, r.z0 - wr.z1)
            if math.hypot(dx, dz) <= F.UNCLIMB_REACH and top - wtop < F.UNCLIMB - 1e-6:
                out.append(f"{b['name']}: its top {top:.1f} is only {top - wtop:.1f} over a walkable top within {F.UNCLIMB_REACH}: a new perch")
                break
        for rect, _top, kind, name in parts:
            ix = min(r.x1, rect.x1) - max(r.x0, rect.x0)
            iz = min(r.z1, rect.z1) - max(r.z0, rect.z0)
            if ix > 1e-3 and iz > 1e-3:
                out.append(f"{b['name']} reaches {min(ix, iz):.2f} into {kind} {name}")
        if max(abs(r.x0), abs(r.x1), abs(r.z0), abs(r.z1)) > F.ORIGIN_LIMIT:
            out.append(f"{b['name']} lies outside the wire's +-{F.ORIGIN_LIMIT:.0f} studs")
        if b["sx"] < 0.99 or b["sz"] < 0.99:
            out.append(f"{b['name']} is thinner than a stud: a dash steps through it")
    return out


def placed_tris(item):
    return kit.build(item["piece"]).transformed(item["x"], item["y"], item["z"], item["yaw"], item["scale"])


def region_rule(build) -> list[str]:
    """Rule 4, on every placement and on every baked triangle that is not a placement."""
    out = []
    level = build.level
    cells = level.region_cells
    tents = {}
    for cid, camp in level.camps.items():
        if camp.get("tent"):
            t = camp["tent"]
            tents[cid] = (Rect.of(t).grown(0.5), t["y"] + t["sy"] / 2)

    def offending(tri, near):
        for p in tri[:3]:
            for name, rect, y in near:
                if rect.x0 + EDGE_SLACK < p[0] < rect.x1 - EDGE_SLACK and rect.z0 + EDGE_SLACK < p[2] < rect.z1 - EDGE_SLACK:
                    if y + F.REGION_PIECE_MAX < p[1] < y + F.REACH_ABOVE:
                        return name, y, p
        return None

    for item in build.P.items:
        foot, top = F.footprint(item)
        near = [(n, r, y) for n, r, y in cells if foot.overlaps(r)]
        if not near:
            continue
        if item["piece"] == "SpawnTent":
            marker = tents.get(item.get("camp"))
            if marker and marker[0].contains(foot.x0, foot.z0) and marker[0].contains(foot.x1, foot.z1) and top <= marker[1] + 1e-6:
                continue
        for tri in placed_tris(item):
            hit = offending(tri, near)
            if hit:
                out.append(f"{item['piece']} at ({item['x']}, {item['z']}) stands {hit[2][1] - hit[1]:.1f} over {hit[0]}'s floor")
                break
    for m in build.meshes:
        if m.name.split("_")[0] == "Dress":
            continue  # its triangles are the placements above
        lo, hi = m.bounds()
        box = Rect(lo[0], hi[0], lo[2], hi[2])
        near = [(n, r, y) for n, r, y in cells if box.overlaps(r)]
        if not near:
            continue
        for tri in m.tris:
            hit = offending(tri, near)
            if hit:
                p = hit[2]
                out.append(f"mesh {m.name} reaches into {hit[0]}'s walking space at ({p[0]:.1f}, {p[1]:.1f}, {p[2]:.1f})")
                break
    return out


def clearing_rule(build) -> list[str]:
    out = []
    level = build.level
    for cid, camp in level.camps.items():
        if not camp.get("locks"):
            continue
        floor = Rect(camp["x"] - camp["sx"] / 2, camp["x"] + camp["sx"] / 2, camp["z"] - camp["sz"] / 2, camp["z"] + camp["sz"] / 2)
        top = float(camp["y"]) + float((camp.get("fence") or {}).get("height") or 0)
        margin = float(camp.get("sightMargin") or 0)
        for item in build.P.items:
            if not floor.contains(item["x"], item["z"]):
                continue
            _foot, piece_top = F.footprint(item)
            if piece_top > top - margin:
                out.append(f"camp {cid}: {item['piece']} rises to {piece_top:.1f}, over its wall's top less the sight margin ({top - margin:.1f})")
        for m in build.meshes:
            lo, hi = m.bounds()
            if hi[1] <= top + 1e-6 or not Rect(lo[0], hi[0], lo[2], hi[2]).overlaps(floor):
                continue
            bad = None
            for tri in m.tris:
                for p in tri[:3]:
                    if floor.contains(p[0], p[2], -0.05) and p[1] > top + 1e-6:
                        bad = p
                        break
                if bad:
                    break
            if bad:
                out.append(f"camp {cid}: mesh {m.name} rises to {bad[1]:.2f} inside the walled rectangle, over its wall's top {top:.1f}")
    return out


# ---------------------------------------------------------------- coplanar overlaps


def coplanar_rule(build) -> list[str]:
    level = build.level
    ground = build.ground
    groups: dict[tuple, list] = {}

    def add(tri, key):
        a, b, c = tri[:3]
        n = lm.tri_normal(a, b, c)
        length = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
        if length < 1e-9:
            return
        n = (n[0] / length, n[1] / length, n[2] / length)
        if n[1] < -0.9 and a[1] <= ground.at(a[0], a[2]) + 0.2:
            return  # a buried bottom: nobody can see it
        # Axis-aligned faces key on their exact coordinate; a near-flat tilt would otherwise drift
        # its rounded plane key with position and pair unrelated heights.
        for i in range(3):
            if abs(a[i] - b[i]) < 1e-4 and abs(a[i] - c[i]) < 1e-4:
                plane = ("axis", i, 1 if n[i] > 0 else -1, round(a[i], 3))
                break
        else:
            d = n[0] * a[0] + n[1] * a[1] + n[2] * a[2]
            plane = (round(n[0], 3), round(n[1], 3), round(n[2], 3), round(d, 3))
        groups.setdefault(plane, []).append((a, b, c, key, n))

    for m in build.meshes:
        for t in m.tris:
            add(t, ("tex", m.texture) if m.look == "texture" else ("pal", t[3]))
    for item in build.props:
        for t in placed_tris(item):
            add(t, ("pal", t[3]))
    hidden = set(F.hide_list(level)["blocks"])
    for b in level.layout["blocks"]:
        if b["name"] in hidden:
            continue
        for t in box_tris(b["x"], b["y"], b["z"], b["sx"], b["sy"], b["sz"]):
            add(t, ("part", b["name"]))
    out = []
    for plane, tris in sorted(groups.items(), key=lambda kv: str(kv[0])):
        if len({t[3] for t in tris}) < 2:
            continue
        n = tris[0][4]
        drop = max(range(3), key=lambda i: abs(n[i]))
        ax = [i for i in range(3) if i != drop]
        found = overlap_pair(tris, ax)
        if found:
            a, b = found
            out.append(f"coplanar overlap on plane {plane}: {a[3]} against {b[3]} near ({a[0][0]:.1f}, {a[0][1]:.2f}, {a[0][2]:.1f})")
    return out


def box_tris(x, y, z, sx, sy, sz):
    """A layout Part's six faces as triangles (no palette colour: it keeps its own look)."""
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = [(x + a * hx, y + b * hy, z + c * hz) for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]
    out = []
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        a, b, c, d = (v[i] for i in f)
        mid = ((a[0] + c[0]) / 2 - x, (a[1] + c[1]) / 2 - y, (a[2] + c[2]) / 2 - z)
        for t in ((a, b, c), (a, c, d)):
            n = lm.tri_normal(*t)
            if n[0] * mid[0] + n[1] * mid[1] + n[2] * mid[2] < 0:
                t = (t[0], t[2], t[1])
            out.append(t)
    return out


def overlap_pair(tris, ax):
    """The first two triangles of different keys whose projections overlap with real area."""
    cell = 8.0
    grid: dict[tuple, list] = {}
    for idx, t in enumerate(tris):
        us = [p[ax[0]] for p in t[:3]]
        vs = [p[ax[1]] for p in t[:3]]
        for gu in range(int(math.floor(min(us) / cell)), int(math.floor(max(us) / cell)) + 1):
            for gv in range(int(math.floor(min(vs) / cell)), int(math.floor(max(vs) / cell)) + 1):
                grid.setdefault((gu, gv), []).append(idx)
    seen = set()
    for key in sorted(grid):
        bucket = grid[key]
        for i in range(len(bucket)):
            for j in range(i + 1, len(bucket)):
                a, b = tris[bucket[i]], tris[bucket[j]]
                if a[3] == b[3]:
                    continue
                pair = (bucket[i], bucket[j])
                if pair in seen:
                    continue
                seen.add(pair)
                if tri_overlap([(p[ax[0]], p[ax[1]]) for p in a[:3]], [(p[ax[0]], p[ax[1]]) for p in b[:3]]):
                    return a, b
    return None


def tri_overlap(p, q, eps=1e-3):
    """Separating-axis test for two 2D triangles; touching edges (within eps) do not count."""
    for tri in (p, q):
        for i in range(3):
            x1, y1 = tri[i]
            x2, y2 = tri[(i + 1) % 3]
            nx, ny = y2 - y1, x1 - x2
            length = math.hypot(nx, ny)
            if length < 1e-12:
                continue
            nx, ny = nx / length, ny / length
            pa = [nx * x + ny * y for x, y in p]
            pb = [nx * x + ny * y for x, y in q]
            if max(pa) <= min(pb) + eps or max(pb) <= min(pa) + eps:
                return False
    return True
