"""The Forest Road dresser's QA gate: `py tools/levels/forest.py check`.

A fresh build in memory is compared with the committed data file, then every rule of
tools/levels/forest.py's docstring is proved on that build. One line per failure, nothing written.
`py tools/levels/forest.py mutants` breaks each rule once (`mutants` below) and proves it is caught.

  1. The data file equals a fresh build, and its planHash is the current inputs' (a layout, art
     or kit change since the last bake is a re-bake and a paste: "stale").
  2. No collidable dressing: no prop, mesh or placement carries collision; the only new collidable
     pieces are the tree-line walls, each in the character-only ArenaBarrier group.
  3. No new standable top: every wall's top stands UNCLIMB over every walkable top within
     UNCLIMB_REACH, no wall reaches into walkable ground or a designed drop, every wall is at
     least a stud thick and lies inside the wire's +-1,000 studs; no designed drop runs longer
     than forest.DROP_MAX (a long one is a hole in the walls: the climb's summit once opened one
     378 studs long through the forest).
  4. The region's walking space: inside any plateau cell, from its floor up to REACH_ABOVE, no
     dressing geometry stands more than 4 studs over the floor (0.3 of slack at a cell's edge),
     except a spawn tent inside its own layout marker.
     4b. Rock in walking space (the rocks redone, 2026-10-21): over any walkable ground, from its
     floor up to REACH_ABOVE, every vertex of the rock meshes lies on a collision solid's skin
     (within ROCK_SKIN): the thin faces' blocks stand at most forest.THIN_OUT out of their wall,
     and no column, cap or gully block reaches over a walker.
     4c. No stone of the kit stands on walkable ground or water (the island shrine's ring aside).
  5. Camp C: nothing inside the walled rectangle rises over its wall's top, and no placed piece
     there over the top less the camp's sightMargin.
  6. Coplanar faces of two different looks never overlap (texture meshes, palette colours, props
     and the layout Parts the dressing keeps visible), down-facing bottoms under the ground aside.
  7. The kit's own rules (forest_kit.problems), every mesh within the importer's limits, the
     triangle budget within 10 per cent, every prop a kit piece, every `with` a real block.
  8. The climb (MISSIONS_DESIGN 28, tools/check_parkour.py CLIMBS): every tree-line wall along the
     climb's yard, trail and path stands to the climb's wallTop (over every flight off the
     summit); no tree on a ledge or the summit; no placed piece on a hop's take-off or landing
     (HOP_CLEAR either side of the face the hop rises over); the summit's ring of standing stones
     (the one place a stone may stand on walkable ground beside the island shrine's ring) keeps
     every stone under REGION_PIECE_MAX, outside the chest's trigger (Combat.json
     levels.secretReach from its footprint, and a margin) and on the summit's top.
"""

from __future__ import annotations

import json
import math
import os
import struct

import forest as F
import forest_kit as kit
import levelmesh as lm
from levelmesh import Rect

EDGE_SLACK = 0.3
ROCK_SKIN = 0.3  # a rock block over walkable ground lies within this of a collision solid (forest.THIN_OUT 0.12)
HOP_CLEAR = 6.0  # a hop's take-off and landing: this far either side of the face it rises over (mountain.md 5)
TRIGGER_MARGIN = 1.0  # a summit stone stands this much farther from the chest than its trigger reaches


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
    out += walking_space_rule(build)
    out += stone_ground_rule(build)
    out += clearing_rule(build)
    out += climb_rule(build, fresh)
    out += coplanar_rule(build)
    out += hash_rules()
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


def hash_rules() -> list[str]:
    """Rule 1's hash on every Python (L5): a corner that is 6e-18 on one Python and 0.0 on the
    other, or -0.0, packs like 0.0; a corner on a float32 rounding edge (within the other Python's
    reach at the piece's scale) or on KIT_SNAP's own edge is refused, never packed."""
    out = []
    colour = next(iter(kit.fp.ALL_COLOURS))

    def tri(*values):
        mesh = kit.Mesh("HashProbe")
        mesh.tris.append(((values[0], 1.0, 2.0), (3.0, values[1], 4.0), (5.0, 6.0, values[2]), colour))
        return mesh

    def packed(*values):
        try:
            return F.kit_geometry(tri(*values))
        except ValueError:
            return None

    zero = packed(0.0, 0.0, 0.0)
    if zero is None:
        out.append("plan hash: a corner of 0.0 is refused")
    for label, value in (("a 6e-18 corner (cos(pi/2) x 0.1)", math.cos(math.pi / 2) * 0.1), ("a -0.0 corner", -0.0)):
        got = packed(value, value, value)
        if got is None or got != zero:
            out.append(f"plan hash: {label} does not pack like 0.0, so the hash depends on the Python")
    # A float32 rounding edge near 0.1 and 5e-16 past it: within the other Python's 2-ulp reach at the
    # piece's scale (1.8e-15 studs), far outside 16 ulps of 0.1 itself (2.2e-16).
    below = kit.f32(0.1)
    above = struct.unpack("<f", struct.pack("<I", struct.unpack("<I", struct.pack("<f", below))[0] + 1))[0]
    edge = (below + above) / 2
    for label, value in (("a corner 5e-16 past a float32 rounding edge", edge + 5e-16), ("a corner on KIT_SNAP's edge", F.KIT_SNAP)):
        if packed(value, 0.0, 0.0) is not None:
            out.append(f"plan hash: {label} is packed, not refused, so the hash could depend on the Python")
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
    for k, d in enumerate(level.drops):
        if max(d.x1 - d.x0, d.z1 - d.z0) > F.DROP_MAX + 1e-6:
            out.append(f"designed drop {k + 1} ({d.x0:.0f}..{d.x1:.0f}, {d.z0:.0f}..{d.z1:.0f}) runs {max(d.x1 - d.x0, d.z1 - d.z0):.0f} studs, over DROP_MAX {F.DROP_MAX:g}: a hole in the walls")
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


def walking_space_rule(build) -> list[str]:
    """Rule 4b: no rock in walking space. Every vertex of the rock meshes (the cliffs' blocks, the
    massif's and the lips' columns, the gully's walls) that lies over walkable ground, more than
    EDGE_SLACK in from its edge and from its floor up to REACH_ABOVE, must sit on a collision
    solid's skin (within ROCK_SKIN of a wall, roof, fence or pillar): a block over a walker's head
    or beside his shoulder is a block he can walk into."""
    out = []
    level = build.level
    walks = [(w.name, w.rect, w.top) for w in level.walks]
    solids = [(s.lo, s.hi) for s in level.solids]
    for m in build.meshes:
        if m.group != "rock":
            continue
        lo, hi = m.bounds()
        box = Rect(lo[0], hi[0], lo[2], hi[2])
        near = [(n, r, t) for n, r, t in walks if box.overlaps(r)]
        if not near:
            continue
        bad = None
        for tri in m.tris:
            for p in tri[:3]:
                for name, r, top in near:
                    if not (r.x0 + EDGE_SLACK < p[0] < r.x1 - EDGE_SLACK and r.z0 + EDGE_SLACK < p[2] < r.z1 - EDGE_SLACK):
                        continue
                    if not (top + 0.2 < p[1] < top + F.REACH_ABOVE):
                        continue
                    if any(all(sl[i] - ROCK_SKIN <= p[i] <= sh[i] + ROCK_SKIN for i in range(3)) for sl, sh in solids):
                        continue
                    bad = (name, p)
                    break
                if bad:
                    break
            if bad:
                break
        if bad:
            name, p = bad
            out.append(f"mesh {m.name} has rock in {name}'s walking space at ({p[0]:.2f}, {p[1]:.2f}, {p[2]:.2f}), off every wall's skin")
    return out


def stone_ground_rule(build) -> list[str]:
    """Rule 4c: no stone of the kit (a rock-role piece) stands on walkable ground or water, the
    island shrine's ring aside (it stands on the island's rim, as approved)."""
    out = []
    level = build.level
    ground = [(w.name, w.rect) for w in level.walks] + [(w.name, w.rect) for w in level.water]
    for item in build.P.items:
        if kit.role_of(item["piece"]) != "rock" or item.get("island") or item.get("summit"):
            continue  # the shrine's ring and the summit's (rule 8 holds the summit's)
        foot, _top = F.footprint(item)
        for name, r in ground:
            if foot.overlaps(r.grown(-EDGE_SLACK)):
                out.append(f"{item['piece']} at ({item['x']}, {item['z']}) stands on {name}")
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


# ---------------------------------------------------------------- the climb


def hop_zones(level) -> list[tuple[str, Rect]]:
    """Every hop's take-off and landing on the climb: the strip HOP_CLEAR deep of the lower top and
    of the upper one along the face where the two meet (the yard's hop onto the first ledge: the
    first ledge's sides over the yard)."""
    boxes = F.climb_boxes(level)
    out = []
    for (na, a, _ta), (nb, b, _tb) in zip(boxes, boxes[1:]):
        ox = min(a.x1, b.x1) - max(a.x0, b.x0)
        oz = min(a.z1, b.z1) - max(a.z0, b.z0)
        if abs(ox) < 1e-6 and oz > 1e-6:
            x = a.x1 if abs(a.x1 - b.x0) < 1e-6 else a.x0
            z0, z1 = max(a.z0, b.z0), min(a.z1, b.z1)
            out.append((f"{na} -> {nb}", Rect(x - HOP_CLEAR, x + HOP_CLEAR, z0, z1)))
        elif abs(oz) < 1e-6 and ox > 1e-6:
            z = a.z1 if abs(a.z1 - b.z0) < 1e-6 else a.z0
            x0, x1 = max(a.x0, b.x0), min(a.x1, b.x1)
            out.append((f"{na} -> {nb}", Rect(x0, x1, z - HOP_CLEAR, z + HOP_CLEAR)))
    if boxes:
        name, first, _top = boxes[0]
        others = [r for _n, r, _t in boxes[1:]]
        for side, (nx, nz) in F.SIDES.items():
            edge = (first.x1 if nx > 0 else first.x0) if nx else (first.z1 if nz > 0 else first.z0)
            probe = (edge + nx * 0.5, (first.z0 + first.z1) / 2) if nx else ((first.x0 + first.x1) / 2, edge + nz * 0.5)
            if any(r.contains(*probe) for r in others):
                continue  # that side stands against the mountain, not over the yard
            zone = Rect(edge - HOP_CLEAR, edge + HOP_CLEAR, first.z0, first.z1) if nx else Rect(first.x0, first.x1, edge - HOP_CLEAR, edge + HOP_CLEAR)
            out.append((f"the yard -> {name}", zone))
    return out


def climb_rule(build, data) -> list[str]:
    """Rule 8 (see the docstring)."""
    out = []
    level = build.level
    if not level.climb:
        return out
    wall_top = float(level.climb["wallTop"])
    for b in data["barriers"]:
        c, lo, hi = b["edge"]
        if F.on_climb(level, b["side"], c, lo, hi) and b["y"] + b["sy"] / 2 < wall_top - 1e-6:
            out.append(f"{b['name']} walls the climb's foot to {b['y'] + b['sy'] / 2:.1f}, under its wallTop {wall_top:.0f}: a flight off the summit clears it")
    boxes = F.climb_boxes(level)
    tops = {n: (r, t) for n, r, t in boxes}
    zones = hop_zones(level)
    summit_name = level.climb["summit"]
    chest = next((s for s in level.layout.get("secrets") or [] if s.get("id") == level.climb["secret"]), None)
    with open(F.COMBAT_JSON, encoding="utf-8") as fh:
        reach = float(json.load(fh)["levels"]["secretReach"])
    for item in build.P.items:
        foot, top = F.footprint(item)
        on = [n for n, (r, t) in tops.items() if r.contains(item["x"], item["z"]) and abs(item["y"] - t) < 1.0]
        role = kit.role_of(item["piece"])
        if on and role in ("tree", "hero"):
            out.append(f"{item['piece']} at ({item['x']}, {item['z']}) stands on {on[0]}: no tree on the climb's ledges")
        for label, zone in zones:
            if foot.overlaps(zone) and top > zone_floor(item, tops) + 0.5:
                out.append(f"{item['piece']} at ({item['x']}, {item['z']}) stands on the hop {label}'s take-off or landing")
                break
        if item.get("summit"):
            sr, stop = tops.get(summit_name, (None, None))
            if item["summit"] != summit_name or sr is None:
                out.append(f"{item['piece']} at ({item['x']}, {item['z']}) is tagged for a summit the climb does not have")
                continue
            if top - stop > F.REGION_PIECE_MAX + 1e-6:
                out.append(f"summit stone {item['piece']} at ({item['x']}, {item['z']}) stands {top - stop:.2f} tall, over {F.REGION_PIECE_MAX}")
            if not (sr.contains(foot.x0, foot.z0) and sr.contains(foot.x1, foot.z1)):
                out.append(f"summit stone {item['piece']} at ({item['x']}, {item['z']}) reaches past the summit's top")
            if chest:
                cr = Rect.of(chest)
                gap = math.hypot(max(0.0, cr.x0 - foot.x1, foot.x0 - cr.x1), max(0.0, cr.z0 - foot.z1, foot.z0 - cr.z1))
                if gap < reach + TRIGGER_MARGIN:
                    out.append(f"summit stone {item['piece']} at ({item['x']}, {item['z']}) stands {gap:.2f} from the chest, inside its trigger and margin ({reach + TRIGGER_MARGIN:g})")
    return out


def zone_floor(item, tops) -> float:
    """The floor under a placement (a ledge's top or the yard's 0), for the hop-zone test: a
    piece wholly under it (a stone of the yard's scree) is no obstacle."""
    best = 0.0
    for r, t in tops.values():
        if r.contains(item["x"], item["z"]):
            best = max(best, t)
    return min(best, item["y"])


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


# ---------------------------------------------------------------- mutants


def mutants(build, data_path) -> list[tuple[str, bool, str]]:
    """Prove no rule is vacuous: each mutant breaks one rule on a copy of the build (or of the data
    file, in a temporary file beside it) and the rule must catch it. `py tools/levels/forest.py
    mutants`; every line must read CAUGHT. The build is restored after each mutant."""
    import copy

    results = []

    def expect(name, lines):
        results.append((name, bool(lines), lines[0] if lines else "NOT CAUGHT"))

    data = build.data()
    d = copy.deepcopy(data)
    d["props"][0]["collide"] = True
    expect("collidable prop", collision_rules(d))
    d = copy.deepcopy(data)
    d["barriers"][0]["group"] = "Default"
    expect("barrier not character-only", collision_rules(d))
    d = copy.deepcopy(data)
    d["barriers"][3]["sy"] -= 60.0
    d["barriers"][3]["y"] -= 30.0
    expect("barrier top within reach", barrier_rules(build, d))
    d = copy.deepcopy(data)
    b = d["barriers"][5]
    b["x"] += -b["sx"] / 2 if b["side"] == "east" else b["sx"] / 2 if b["side"] == "west" else 0.0
    b["z"] += -b["sz"] / 2 if b["side"] == "south" else b["sz"] / 2 if b["side"] == "north" else 0.0
    expect("barrier into walkable ground", barrier_rules(build, d))
    d = copy.deepcopy(data)
    d["barriers"][7]["sx"] = 0.5
    d["barriers"][7]["sz"] = 0.5
    expect("barrier thinner than a stud", barrier_rules(build, d))

    # rule 4: the region's walking space
    saved = [dict(i) for i in build.P.items]
    build.P.items.append({"piece": "FirHeroA", "x": -150.0, "y": 8.0, "z": -44.0, "yaw": 0.0, "scale": 1.0})
    expect("tall piece in a region cell", region_rule(build))
    build.P.items = [dict(i) for i in saved]
    build.P.items.append({"piece": "StoneMonolith", "x": -130.0, "y": 8.0, "z": -22.0, "yaw": 0.0, "scale": 1.0})
    expect("monolith in a region cell", region_rule(build))
    build.P.items = [dict(i) for i in saved]
    for it in build.P.items:
        if it["piece"] == "SpawnTent":
            it["scale"] = 1.3
            break
    expect("spawn tent past its marker", region_rule(build))
    build.P.items = [dict(i) for i in saved]
    m = lm.Bake("Mutant", "palette", group="dress")
    m.tri((-150.0, 9.0, -46.0), (-148.0, 9.0, -44.0), (-150.0, 30.0, -44.0), F.ROCK.ROCK)
    build.meshes.append(m)
    expect("baked mesh in a region cell", region_rule(build))
    build.meshes.pop()

    # rule 4b: rock in walking space. A block a stud out of BendWall over RoadAB2, a massif column
    # on the gatehouse walk, a ceiling block hanging into the cave tunnel.
    for label, tri in (
        ("thin block out of its wall", ((-123.2, 20.0, -30.0), (-123.2, 26.0, -30.0), (-123.2, 20.0, -24.0))),
        ("column on the gatehouse walk", ((280.0, 14.0, -44.0), (283.0, 14.0, -44.0), (280.0, 22.0, -42.0))),
        ("block hanging into the tunnel", ((-260.0, 20.5, -92.0), (-258.0, 20.5, -92.0), (-260.0, 20.5, -90.0))),
    ):
        m = lm.Bake("RockMutant", "palette", group="rock")
        m.tri(*tri, F.ROCK.ROCK)
        build.meshes.append(m)
        expect(label, walking_space_rule(build))
        build.meshes.pop()
    # The same rule against the generator itself: BendWall's west face laid with the thin style
    # pushed out of the wall must be caught.
    rk = F.ART["cliff"]["thin"]
    thin_out = F.THIN_OUT
    try:
        F.THIN_OUT = 1.5
        F.ART["cliff"]["thin"] = dict(rk, front=[0.5, 1.0], lift=0.6)
        rocks = F.Bake("RockFaces", "palette", group="rock")
        for axis, sign, plane, (u0, u1, v0, v1), s in F.exposed_faces(build.level):
            if s.name == "BendWall" and axis == 0 and sign < 0:
                F.block_face(rocks, axis, sign, plane, (u0, u1, v0, v1), "thin", 1.0, reach=44.0, back=1.5)
        build.meshes.append(rocks)
        expect("thin face's blocks standing out", walking_space_rule(build))
        build.meshes.pop()
    finally:
        F.THIN_OUT = thin_out
        F.ART["cliff"]["thin"] = rk

    # rule 4c: a stone on the road, a stone in the pond
    for label, item in (("stone on the road", {"piece": "RockB", "x": -382.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "scale": 1.0}),
                        ("stone in the pond", {"piece": "RockA", "x": -400.0, "y": -1.0, "z": 110.0, "yaw": 0.0, "scale": 1.0})):
        build.P.items.append(item)
        expect(label, stone_ground_rule(build))
        build.P.items = [dict(i) for i in saved]

    # rule 5: the clearing
    for it in build.P.items:
        if it["piece"] == "ChiefTent":
            it["scale"] = 4.0
    expect("clearing piece over the wall", clearing_rule(build))
    build.P.items = [dict(i) for i in saved]
    m = lm.Bake("Mutant", "palette", group="rock")
    m.tri((300.0, 70.0, 30.0), (302.0, 70.0, 30.0), (300.0, 80.0, 32.0), F.ROCK.ROCK)
    build.meshes.append(m)
    expect("clearing mesh over the wall", clearing_rule(build))
    build.meshes.pop()

    # rule 6: coplanar faces of two looks (a palette quad on the road's plane over RoadAB1)
    m = lm.Bake("Mutant", "palette")
    y = 8.0 + F.ART["lifts"]["road"]
    m.up((-160.0, y, -48.0), (-150.0, y, -48.0), (-150.0, y, -40.0), F.ROCK.ROCK)
    build.meshes.append(m)
    expect("coplanar overlap", coplanar_rule(build))
    build.meshes.pop()

    # rule 1: stale or hand-edited data
    with open(data_path, encoding="utf-8") as fh:
        committed = json.load(fh)
    tmp = data_path + ".mutant.json"
    try:
        committed["planHash"] = "0000000000000000"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(committed, fh)
        expect("stale plan hash", [x for x in run(build, tmp) if "stale" in x])
        committed["planHash"] = data["planHash"]
        committed["barriers"] = committed["barriers"][1:]
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(committed, fh)
        expect("hand-edited data", [x for x in run(build, tmp) if "differs" in x])
    finally:
        if os.path.isfile(tmp):
            os.remove(tmp)

    # rule 1's hash on every Python (L5): no snap at all, -0.0 kept, the guard's slack taken at the
    # corner's own scale (the fix round's guard), no guard
    for label, attr, mutant, needle in (
        ("plan hash: no corner snapped", "KIT_SNAP", 0.0, "6e-18"),
        ("plan hash: -0.0 packed as itself", "kit_corner", lambda v: v if v == 0.0 else (0.0 if abs(v) < F.KIT_SNAP else v), "-0.0"),
        ("plan hash: slack at the corner's scale", "kit_slack", lambda v: F.KIT_ULP_SLACK * math.ulp(v), "5e-16 past"),
        ("plan hash: no guard", "kit_slack", lambda v: 0.0, "KIT_SNAP's edge"),
    ):
        orig = getattr(F, attr)
        setattr(F, attr, mutant)
        try:
            expect(label, [x for x in hash_rules() if needle in x])
        finally:
            setattr(F, attr, orig)

    # rule 3 again: the summit's bogus drop (the generator before F2) through the forest
    build.level.drops.append(Rect(-596.0, -218.0, -110.0, -98.0))
    expect("a designed drop through the forest", [x for x in barrier_rules(build, data) if "DROP_MAX" in x])
    build.level.drops.pop()

    # rule 4b on the mountain: its thin faces' blocks pushed out over the yard
    if build.level.climb:
        mount = F.ART["cliff"]["mount"]
        try:
            F.ART["cliff"]["mount"] = dict(mount, front=[0.6, 1.4], lift=0.4)
            rocks = F.Bake("RockFaces", "palette", group="rock")
            F.mountain_faces(build.level, rocks)
            build.meshes.append(rocks)
            expect("mountain face standing out", [x for x in walking_space_rule(build) if "RockFaces" in x])
            build.meshes.pop()
        finally:
            F.ART["cliff"]["mount"] = mount

    # rule 8: the climb (a wall under its wallTop, a fir on a hop's landing, a summit stone over
    # 4 studs, one inside the chest's trigger)
    if build.level.climb:
        d = copy.deepcopy(data)
        for b in d["barriers"]:
            c, lo, hi = b["edge"]
            if F.on_climb(build.level, b["side"], c, lo, hi):
                b["sy"] -= 60.0
                b["y"] -= 30.0
                break
        expect("climb wall under its wallTop", [x for x in climb_rule(build, d) if "walls the climb" in x])
        boxes = F.climb_boxes(build.level)
        _n, r3, t3 = boxes[2]
        _n, r4, _t4 = boxes[3]
        x = (r3.x0 + r3.x1) / 2
        z = r3.z0 + 2.0 if abs(r3.z0 - r4.z1) < 1e-6 else r3.z1 - 2.0
        build.P.items.append({"piece": "FirHeroB", "x": x, "y": t3, "z": z, "yaw": 0.0, "scale": 0.7})
        expect("fir on a hop's take-off", [x for x in climb_rule(build, data) if x.startswith("FirHeroB")])
        build.P.items = [dict(i) for i in saved]
        for it in build.P.items:
            if it.get("summit"):
                it["scale"] *= 2.0
                break
        expect("summit stone over 4 studs", [x for x in climb_rule(build, data) if "tall, over" in x])
        build.P.items = [dict(i) for i in saved]
        chest = next(s for s in build.level.layout["secrets"] if s["id"] == build.level.climb["secret"])
        for it in build.P.items:
            if it.get("summit"):
                it["x"], it["z"] = chest["x"] + 4.5, chest["z"]
                break
        expect("summit stone in the chest's trigger", [x for x in climb_rule(build, data) if "inside its trigger" in x])
        build.P.items = [dict(i) for i in saved]

    # rule 7: the kit and the mesh limits
    for piece, role, maker, label in (
        ("EdgeLogs", "edge", lambda n: kit.fir(n, 6.0, 1.0, 2, 5, False), "edge piece over 4 studs"),
        ("StoneMonolith", "rock", lambda n: kit.standing_piece(n, 8.6, 1.55, 1.2, 40, 0.28, (0.35, 0.1), 0.72, 0.35), "stone over the rock budget"),
    ):
        orig = kit.PIECES[piece]
        kit.PIECES[piece] = (role, maker)
        kit._CACHE.pop(piece, None)
        try:
            expect(label, [x for x in kit.problems() if piece in x])
        finally:
            kit.PIECES[piece] = orig
            kit._CACHE.pop(piece, None)
    big = lm.Bake("Big", "palette")
    for k in range(lm.TRI_LIMIT + 1):
        big.tri((k * 0.01, 0.0, 0.0), (k * 0.01 + 0.005, 0.0, 0.0), (k * 0.01, 1.0, 1.0), F.ROCK.ROCK)
    expect("mesh over 20k triangles", big.problems())
    return results
