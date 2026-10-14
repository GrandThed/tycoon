#!/usr/bin/env python
"""Checks, measures and draws the Wave 2 layout drafts (L1b Wave 2, "the long road").

Reads the drafts make_drafts.py wrote (<name>.level.json, <name>.layout.json) and:
  1. runs tools/check_levels.py's own gates on each draft, as if it were Forest Road (imported
     read-only; the Wave 2 sizes are put in its EXPECTED table in memory only);
  2. computes the arithmetic of the brief (population with tents, Parts, the wire, the route,
     the sneak path against every resting eye, the wake chains of the 2 x sight rule, the pay,
     and an estimated first Normal clear);
  3. writes long-road.html (two to-scale SVG maps with camp close-ups, the tables), ascii.txt
     (both maps in at most 60 x 30 characters) and numbers.json (everything measured).

Nothing in src/ or tools/ is written: bytecode is off, and every output goes next to this file.

Usage: py build_page.py
"""

from __future__ import annotations

import html
import json
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO / "tools"))
import check_levels as cl  # noqa: E402
import sim_range as sr  # noqa: E402

DESIGNS = [("winding", "The winding road (recommended)"), ("switchback", "The switchback (alternative)")]

# ---------------------------------------------------------------------------------------------
# Estimates (named, never measured for this layout). Each comes from docs/BALANCE.md "L1b".
# ---------------------------------------------------------------------------------------------
# The reacting player of sim_range.py at gear 2/1 takes off ~100 effective HP a second from a
# camp's mix: Wave 1's A (855 HP in ~9 s), B (3,428 HP in ~35 s of fighting) and C's wave and
# residents (4,200 HP in ~37 s) give 95, 97 and 113. The Colossus in the run: 73.7-75.6 s.
HP_PER_SECOND = 100.0
COLOSSUS_SECONDS = 75.0
# Ben's own Wave 1 clear took "about four minutes" against the simulator's 3.05: the walking is
# the same, so his fighting took ~1.36 x the simulator's (216 s against 159 s).
HUMAN_FIGHT_FACTOR = 1.36
COUNTDOWN_SECONDS = 3.0  # levels.gateSeconds, the boss room's countdown
# The Colossus's calls in a 75 s fight on Normal (BALANCE L1: 48 fodder, 4,800 cash).
COLOSSUS_CALLS = 48
BOSS_RESERVE = 13  # the boss and its 12 summons: L1b-11's reserve without Wave 1's 8 for tents
WAVE1 = {"cashPerMinute": 19800, "timberPerMinute": 42, "clearCash": 60800, "clearTimber": 129}
L1 = {"cashPerMinute": 13400, "timberPerMinute": 24, "clearCash": 88200, "clearTimber": 155}
WAVE2_EXPECTED = {
    "camps": {"A": (85, 85), "B": (141, 133), "C": (115, 115)},
    "campTolerance": 0.10,
    "routeStuds": (900, 1100),
    "secrets": {"lookout": "doubleJump", "cache": "fire", "shrine": "ice"},
    "climbs": 1, "gaps": 1, "creek": True,
    "locks": ["C"],
    "residents": {"A": (30, 36), "B": (40, 50)},
    "lockedResidentsMin": 4,
}


def load(name):
    level = json.loads((HERE / f"{name}.level.json").read_text(encoding="utf-8"))
    layout = json.loads((HERE / f"{name}.layout.json").read_text(encoding="utf-8"))
    return level, layout


# ---------------------------------------------------------------------------------------------
# The gates of check_levels.py on a draft
# ---------------------------------------------------------------------------------------------


def run_gates(level_file, layout, ctx, real_layouts):
    lines = []

    def expect(ok, text):
        lines.append((bool(ok), text))

    cl.EXPECTED["ForestRoad"] = WAVE2_EXPECTED
    layouts = dict(real_layouts)
    layouts["ForestRoad"] = layout
    ctx = dict(ctx, campRadius={})
    level = sr.resolve_level(level_file, None, ctx["runCap"])
    cl.check_level_file(level_file, level, layouts, ctx, expect)
    facts = cl.check_layout("ForestRoad", layout, ctx, expect)
    bounds_of = {n: cl.layout_bounds(l, ctx["levels"]["fenceThickness"], ctx["levels"]["floorThickness"])
                 for n, l in layouts.items()}
    cl.check_lobby("Lobby", layouts["Lobby"], ctx, bounds_of, expect)
    return lines, facts, level


# ---------------------------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------------------------


def seg_samples(points, step=0.5):
    out = []
    for a, b in zip(points, points[1:]):
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        n = max(int(run / step), 1)
        for k in range(n + (1 if b is points[-1] else 0)):
            f = k / n
            out.append((a["x"] + (b["x"] - a["x"]) * f, a["z"] + (b["z"] - a["z"]) * f))
    return out


def polyline_length(points):
    return sum(math.hypot(b["x"] - a["x"], b["z"] - a["z"]) for a, b in zip(points, points[1:]))


def group_eyes(defn):
    """Every place a resting member can stand (posts, a patrol's whole loop)."""
    return cl.resting_eyes(defn)


def group_points(defn):
    return [(e["at"][0], e["at"][2]) for e in group_eyes(defn)]


def min_dist(points_a, points_b):
    best = math.inf
    for ax, az in points_a:
        for bx, bz in points_b:
            d = (ax - bx) ** 2 + (az - bz) ** 2
            if d < best:
                best = d
    return math.sqrt(best)


# ---------------------------------------------------------------------------------------------
# The arithmetic
# ---------------------------------------------------------------------------------------------


def body_hp(kind, kinds, diff):
    k = kinds[kind]
    return k["hp"] * diff["hpScale"] + k.get("plate", 0) * diff.get("plateScale", 1)


def measure(name, level_file, layout, level, facts, ctx):
    kinds, ranks, rules = ctx["kinds"], ctx["ranks"], ctx["camps"]
    move = ctx["move"]
    rewards = level_file["crowd"]["rewards"]
    share = level_file["crowd"]["clearBonus"].get("share", 0)
    diffs = level_file["difficulties"]
    camps = layout["camps"]
    lcamps = {c["id"]: c for c in level_file["camps"]}
    stage_c = next(s for s in level_file["stages"] if s["kind"] == "camp")
    cap_c = stage_c["maxAlive"]
    out = {"name": name}

    # Residents, tents and the population at each difficulty.
    pop = {}
    for d in diffs:
        defs, res = sr.groups_of(level, layout, ranks[d], ranks)
        tents = {cid: sum(u["count"] for u in (lcamps[cid].get("tent") or {}).get("units", [])) for cid in lcamps}
        room = max(cap_c - res.get("C", 0), 0)
        worst = sum(res.values()) + sum(tents.values()) + room + BOSS_RESERVE
        validate = sr.population_of(res, {"C": cap_c}, ctx["levels"]["populationReserve"])
        pop[d] = {"residents": res, "total": sum(res.values()), "tents": tents, "tentTotal": sum(tents.values()),
                  "room": room, "worst": worst, "validate21": validate, "cap": ctx["crowdMaxAlive"],
                  "groups": len(defs)}
    out["population"] = pop

    # Parts: check_levels' count (LevelGeometry.Pieces) plus one walk-through marker per tent.
    parts = cl.part_count(layout, ctx["levels"].get("fireMarkerSize") or False)
    tents = sum(1 for c in camps if c.get("tent"))
    out["parts"] = {"checkLevels": parts, "tents": tents, "total": parts + tents, "max": ctx["levels"]["maxParts"]}

    # The wire: the furthest a camp's floor and its wall reach from the origin, and the furthest Part.
    reach = cl.wall_reach(ctx["levels"]["fenceThickness"], layout.get("barrier"))
    far_camp = max(max(abs(c["x"] - c["sx"] / 2 - reach), abs(c["x"] + c["sx"] / 2 + reach),
                       abs(c["z"] - c["sz"] / 2 - reach), abs(c["z"] + c["sz"] / 2 + reach)) for c in camps)
    bounds = cl.layout_bounds(layout, ctx["levels"]["fenceThickness"], ctx["levels"]["floorThickness"])
    far_any = max(abs(bounds[0]), abs(bounds[1]), abs(bounds[2]), abs(bounds[3]))
    out["wire"] = {"campFurthest": far_camp, "anyFurthest": far_any, "gate": cl.ORIGIN_LIMIT, "codec": 1024,
                   "bounds": bounds}

    # The route.
    out["route"] = {"length": facts["length"], "walked": facts["walked"],
                    "camps": {l["camp"]: l["length"] for l in facts["legs"] if l.get("camp")}}

    # Groups at the highest difficulty, with sight, the road's and the sneak path's closest pass.
    top = max(ranks[d] for d in diffs)
    defs, _res = sr.groups_of(level, layout, top, ranks)
    solids = cl.solids_of(layout, ctx["levels"]["fenceThickness"], ctx["levels"]["floorThickness"])
    sneak = layout.get("sneak") or []
    sneak_pts = seg_samples(sneak)
    road_pts = seg_samples([{"x": p["x"], "z": p["z"]} for p in layout["route"]])
    # A sample over the route's gap is jumped, not walked: it needs no ground under it.
    gaps = [(a, b) for a, b in zip(layout["route"], layout["route"][1:]) if b.get("via") == "gap"]

    def over_gap(x, z):
        for a, b in gaps:
            lo_x, hi_x = sorted((a["x"], b["x"]))
            lo_z, hi_z = sorted((a["z"], b["z"]))
            if lo_x - 0.01 <= x <= hi_x + 0.01 and lo_z - 0.01 <= z <= hi_z + 0.01:
                return True
        return False

    off_ground = [(x, z) for x, z in sneak_pts if cl.ground(solids, x, z)[0] is None and not over_gap(x, z)]
    groups = []
    for defn in defs:
        posture = sr.cb_posture(defn, rules)
        pts = group_points(defn)
        eyes = group_eyes(defn)
        sneak_d = min_dist(sneak_pts, pts)
        road_d = min_dist(road_pts, pts)
        # Cone-aware: would CampBrain.Sees see a root anywhere on the sneak path / the road?
        def seen_by(samples):
            for x, z in samples:
                if min((x - e["at"][0]) ** 2 + (z - e["at"][2]) ** 2 for e in eyes) > posture["sight"] ** 2:
                    continue
                top_y, _s = cl.ground(solids, x, z)
                y = (top_y if top_y is not None else defn["floorY"]) + sr.ROOT_HEIGHT
                root = {"userId": 1, "root": (x, y, z)}
                if any(sr.cb_sees(defn, e, root, rules) for e in eyes):
                    return True
            return False
        count = sum(u["count"] for u in defn["units"])
        cx = sum(p[0] for p in pts) / len(pts)
        cz = sum(p[1] for p in pts) / len(pts)
        groups.append({"id": defn["id"], "camp": defn["camp"], "posture": defn["posture"], "sight": posture["sight"],
                       "cone": posture["cone"], "bodies": count, "held": defn["held"],
                       "sneakDistance": sneak_d, "sneakSeen": seen_by(sneak_pts) if sneak_d <= posture["sight"] else False,
                       "roadDistance": road_d, "roadSeen": seen_by(road_pts) if road_d <= posture["sight"] else False,
                       "centre": (cx, cz), "points": pts,
                       "units": defn["units"]})
    out["groups"] = groups
    # Post spacing (BALANCE "L1b: open, carried to Wave 2"): every pair of resting posts of one
    # camp at least r_a + r_b + 0.5 apart, at every difficulty (a patrol: its starting posts).
    worst = None
    for d in diffs:
        dd, _r = sr.groups_of(level, layout, ranks[d], ranks)
        for camp in camps:
            placed = []
            for defn in dd:
                if defn["camp"] != camp["id"]:
                    continue
                count = sum(u_["count"] for u_ in defn["units"])
                posts = sr.cb_posts(defn, count)
                k = 0
                for unit in defn["units"]:
                    for _n in range(unit["count"]):
                        placed.append((posts[k]["at"][0], posts[k]["at"][2], kinds[unit["kind"]]["radius"], defn["id"]))
                        k += 1
            for i, a_ in enumerate(placed):
                for b_ in placed[i + 1:]:
                    spare = math.hypot(a_[0] - b_[0], a_[1] - b_[1]) - (a_[2] + b_[2] + 0.5)
                    if worst is None or spare < worst[0]:
                        worst = (spare, d, a_[3], b_[3])
    out["postSpacing"] = {"spare": worst[0], "difficulty": worst[1], "between": [worst[2], worst[3]]}
    out["sneak"] = {"length": polyline_length(sneak), "offGround": len(off_ground), "samples": len(sneak_pts),
                    "firstOff": off_ground[:3]}

    # The 2 x sight rule: a group that wakes wakes every resting group of its camp whose nearest
    # resting place lies within 2 x the WAKING group's sight of the waking group's nearest one.
    by_id = {g["id"]: g for g in groups}
    edges = {}
    for g in groups:
        edges[g["id"]] = [h["id"] for h in groups if h is not g and h["camp"] == g["camp"]
                          and min_dist(g["points"], h["points"]) <= 2 * g["sight"]]
    chains = {}
    for g in groups:
        seen, stack = {g["id"]}, [g["id"]]
        while stack:
            for nxt in edges[stack.pop()]:
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        chains[g["id"]] = sorted(seen)
    out["chains"] = {gid: {"wakes": ids, "bodies": sum(by_id[i]["bodies"] for i in ids)} for gid, ids in chains.items()}
    out["edges"] = edges

    # Time: walking the route, a tour of each open camp's groups, the fights by effective HP.
    normal = diffs["normal"]
    nd, nres = sr.groups_of(level, layout, ranks["normal"], ranks)
    camp_hp = {}
    for defn in nd:
        camp_hp[defn["camp"]] = camp_hp.get(defn["camp"], 0) + sum(
            body_hp(u["kind"], kinds, normal) * u["count"] for u in defn["units"])
    tent_hp = {cid: sum(body_hp(u["kind"], kinds, normal) * u["count"] for u in (lc.get("tent") or {}).get("units", []))
               for cid, lc in lcamps.items()}
    wave_hp = sum(body_hp(g["kind"], kinds, normal) * g["count"] for w in stage_c["waves"] for g in w["groups"]
                  if not g.get("minDifficulty"))
    wave_bodies = sum(g["count"] for w in stage_c["waves"] for g in w["groups"] if not g.get("minDifficulty"))
    tours = {}
    for camp in camps:
        if camp.get("locks"):
            continue
        centres = [g["centre"] for g in groups if g["camp"] == camp["id"]]
        here = (camp["entry"]["x"], camp["entry"]["z"])
        left = list(centres)
        walked = 0.0
        while left:
            nxt = min(left, key=lambda c: math.hypot(c[0] - here[0], c[1] - here[1]))
            walked += math.hypot(nxt[0] - here[0], nxt[1] - here[1])
            here = nxt
            left.remove(nxt)
        walked += math.hypot(camp["exit"]["x"] - here[0], camp["exit"]["z"] - here[1])
        leg = math.hypot(camp["exit"]["x"] - camp["entry"]["x"], camp["exit"]["z"] - camp["entry"]["z"])
        tours[camp["id"]] = max(walked - leg, 0.0)
    walk_s = facts["length"] / move["walkSpeed"]
    tour_s = sum(tours.values()) / move["walkSpeed"]
    fights = {cid: (camp_hp.get(cid, 0) + tent_hp.get(cid, 0)) / HP_PER_SECOND for cid in ("A", "B")}
    fights["C"] = (camp_hp.get("C", 0) + wave_hp) / HP_PER_SECOND
    fight_s = sum(fights.values()) + COLOSSUS_SECONDS
    sim_s = walk_s + tour_s + COUNTDOWN_SECONDS + fight_s
    human_s = walk_s + tour_s + COUNTDOWN_SECONDS + fight_s * HUMAN_FIGHT_FACTOR
    out["time"] = {"walk": walk_s, "tour": tour_s, "tours": tours, "fights": fights, "colossus": COLOSSUS_SECONDS,
                   "countdown": COUNTDOWN_SECONDS, "sim": sim_s, "human": human_s,
                   "hp": {"camps": camp_hp, "tents": tent_hp, "cWaves": wave_hp, "cWaveBodies": wave_bodies}}

    # Pay on each difficulty: per kill, the clear bonus (share x the camp's stock at full price,
    # its tent's and, in the boss room, its waves' included), the boss and its calls.
    pay = {}
    for d, diff in diffs.items():
        mult = diff["rewardMult"]
        dd, _r = sr.groups_of(level, layout, ranks[d], ranks)
        rows = {}
        for cid in ("A", "B", "C"):
            kills = {}
            for defn in dd:
                if defn["camp"] == cid:
                    for unit in defn["units"]:
                        kills[unit["kind"]] = kills.get(unit["kind"], 0) + unit["count"]
            for unit in (lcamps[cid].get("tent") or {}).get("units", []):
                kills[unit["kind"]] = kills.get(unit["kind"], 0) + unit["count"]
            if cid == "C":
                for wave in stage_c["waves"]:
                    for g in wave["groups"]:
                        need = g.get("minDifficulty")
                        if need is None or ranks[need] <= ranks[d]:
                            n = g["count"]
                            if not need:
                                n = math.floor(n * diff["countMult"])
                            kills[g["kind"]] = kills.get(g["kind"], 0) + n
            cash = sum(rewards[k]["cash"] * n for k, n in kills.items()) * mult
            mats = sum(rewards[k]["materials"] * n for k, n in kills.items()) * mult
            bonus_cash, bonus_mats = math.floor(cash * share), math.floor(mats * share)
            row = {"kills": kills, "cash": cash, "materials": mats, "bonusCash": bonus_cash, "bonusMaterials": bonus_mats}
            if cid == "C":
                row["bossCash"] = (rewards["colossus"]["cash"] + COLOSSUS_CALLS * rewards["fodder"]["cash"]) * mult
                row["bossMaterials"] = rewards["colossus"]["materials"] * mult
                row["valor"] = 10 * mult
            rows[cid] = row
        total_cash = sum(r["cash"] + r["bonusCash"] + r.get("bossCash", 0) for r in rows.values())
        total_mats = sum(r["materials"] + r["bonusMaterials"] + r.get("bossMaterials", 0) for r in rows.values())
        pay[d] = {"camps": rows, "cash": total_cash, "materials": total_mats, "valor": rows["C"]["valor"]}
    out["pay"] = pay
    out["pay"]["perMinute"] = {
        "simCash": pay["normal"]["cash"] / (sim_s / 60), "simTimber": pay["normal"]["materials"] / (sim_s / 60),
        "humanCash": pay["normal"]["cash"] / (human_s / 60), "humanTimber": pay["normal"]["materials"] / (human_s / 60)}

    # The gap between camps (dormancy reads it: a group is dormant with nobody within dormantRadius).
    def rect(c):
        return c["x"] - c["sx"] / 2, c["x"] + c["sx"] / 2, c["z"] - c["sz"] / 2, c["z"] + c["sz"] / 2

    gaps = {}
    for i, a in enumerate(camps):
        for b in camps[i + 1:]:
            ax0, ax1, az0, az1 = rect(a)
            bx0, bx1, bz0, bz1 = rect(b)
            gaps[f"{a['id']}-{b['id']}"] = math.hypot(max(bx0 - ax1, ax0 - bx1, 0), max(bz0 - az1, az0 - bz1, 0))
    out["campGaps"] = gaps
    return out


# ---------------------------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------------------------

POSTURE_CLASS = {"guard": "guard", "fire": "fire", "patrol": "patrol"}


def svg_map(layout, level_file, numbers, box, width_px, grid=100, label=True, title=""):
    """An SVG of the layout inside `box` = (x0, x1, z0, z1), to scale, north up."""
    x0, x1, z0, z1 = box
    w, h = x1 - x0, z1 - z0
    parts = [f'<svg viewBox="{x0:g} {z0:g} {w:g} {h:g}" role="img" aria-label="{html.escape(title)}" '
             f'preserveAspectRatio="xMidYMid meet" class="map" style="aspect-ratio:{w:g}/{h:g}">']
    s = w / width_px  # studs per pixel at the nominal width: strokes and text scale with it
    parts.append(f'<rect x="{x0:g}" y="{z0:g}" width="{w:g}" height="{h:g}" class="bg"/>')
    gx = math.ceil(x0 / grid) * grid
    while gx <= x1:
        parts.append(f'<line x1="{gx:g}" y1="{z0:g}" x2="{gx:g}" y2="{z1:g}" class="grid" stroke-width="{s:g}"/>')
        if label:
            parts.append(f'<text x="{gx + 2 * s:g}" y="{z0 + 10 * s:g}" class="gridlabel" font-size="{9 * s:g}">x {gx:g}</text>')
        gx += grid
    gz = math.ceil(z0 / grid) * grid
    while gz <= z1:
        parts.append(f'<line x1="{x0:g}" y1="{gz:g}" x2="{x1:g}" y2="{gz:g}" class="grid" stroke-width="{s:g}"/>')
        if label:
            parts.append(f'<text x="{x0 + 2 * s:g}" y="{gz - 2 * s:g}" class="gridlabel" font-size="{9 * s:g}">z {gz:g}</text>')
        gz += grid
    looks = {"path": "road", "ground": "ledge", "water": "water", "sign": "sign"}
    for b in layout["blocks"]:
        cls = looks.get(b["look"], "road")
        if b.get("collide") is False and b["look"] == "sign":
            continue
        parts.append(f'<rect x="{b["x"] - b["sx"] / 2:g}" y="{b["z"] - b["sz"] / 2:g}" width="{b["sx"]:g}" '
                     f'height="{b["sz"]:g}" class="{cls}"><title>{html.escape(b.get("name", ""))} top '
                     f'{b["y"] + b["sy"] / 2:g}</title></rect>')
    for c in layout["camps"]:
        cx0, cz0 = c["x"] - c["sx"] / 2, c["z"] - c["sz"] / 2
        cls = "floor locked" if c.get("locks") else "floor"
        parts.append(f'<rect x="{cx0:g}" y="{cz0:g}" width="{c["sx"]:g}" height="{c["sz"]:g}" class="{cls}" '
                     f'stroke-width="{2.2 * s:g}"><title>Camp {c["id"]} floor top {c["y"]:g}</title></rect>')
        for g in c.get("gates") or []:
            gx0, gx1, gz0, gz1 = cl.gate_rect(c, g, 1.0)
            pad = 1.5 * s
            parts.append(f'<rect x="{gx0 - pad:g}" y="{gz0 - pad:g}" width="{gx1 - gx0 + 2 * pad:g}" '
                         f'height="{gz1 - gz0 + 2 * pad:g}" class="{"gate" if c.get("locks") else "opening"}"/>')
        for o in c.get("obstacles") or []:
            parts.append(f'<rect x="{o["x"] - o["sx"] / 2:g}" y="{o["z"] - o["sz"] / 2:g}" width="{o["sx"]:g}" '
                         f'height="{o["sz"]:g}" class="cover"/>')
        if c.get("tent"):
            t = c["tent"]
            parts.append(f'<rect x="{t["x"] - t["sx"] / 2:g}" y="{t["z"] - t["sz"] / 2:g}" width="{t["sx"]:g}" '
                         f'height="{t["sz"]:g}" class="tent" stroke-width="{1.5 * s:g}"><title>Tent of camp '
                         f'{c["id"]}</title></rect>')
            parts.append(f'<text x="{t["x"]:g}" y="{t["z"] + 3.5 * s:g}" class="tentlabel" font-size="{10 * s:g}" '
                         f'text-anchor="middle">T</text>')
        if label:
            parts.append(f'<text x="{cx0 + 3 * s:g}" y="{cz0 + c["sz"] - 4 * s:g}" class="camplabel" '
                         f'font-size="{12 * s:g}">{c["id"]}{" (locks)" if c.get("locks") else ""}</text>')
    # Route and sneak.
    pts = " ".join(f'{p["x"]:g},{p["z"]:g}' for p in layout["route"])
    parts.append(f'<polyline points="{pts}" class="route" stroke-width="{1.6 * s:g}"/>')
    sneak = layout.get("sneak") or []
    pts = " ".join(f'{p["x"]:g},{p["z"]:g}' for p in sneak)
    parts.append(f'<polyline points="{pts}" class="sneak" stroke-width="{3 * s:g}" '
                 f'stroke-dasharray="{6 * s:g} {4 * s:g}"/>')
    # Groups: sight per resting place (a guard's cone drawn over it), the 2 x sight reach dashed.
    for g in numbers["groups"]:
        cls = POSTURE_CLASS[g["posture"]]
        camp = next(c for c in layout["camps"] if c["id"] == g["camp"])
        spot = next(sp for sp in camp["spots"] if f'{camp["id"]}.{sp["id"]}' == g["id"])
        # 2 x sight: one dashed circle round every resting place, so the group's reach reads as
        # their envelope (a patrol: every eighth stud of its loop).
        posts = sr.cb_posts({"posture": spot["posture"], "points": [(p["x"], camp["y"], p["z"]) for p in spot["points"]],
                             "floorY": camp["y"], "radius": spot.get("radius") or 0,
                             "yaw": (spot.get("facing") or 0) * math.pi / 180,
                             "rect": {"x": camp["x"], "z": camp["z"]}}, g["bodies"])
        hull = [(p["at"][0], p["at"][2]) for p in posts]
        if g["posture"] == "patrol":
            hull = g["points"][::8]
        # Each area is a union: solid circles inside one translucent group, so overlaps do not
        # stack. A held group (the boss room) never wakes by sight, so it gets no 2 x reach.
        if not g["held"]:
            parts.append(f'<g class="reachgrp {cls}">' + "".join(
                f'<circle cx="{x:g}" cy="{z:g}" r="{2 * g["sight"]:g}"/>' for x, z in hull) + "</g>")
        parts.append(f'<g class="sightgrp {cls}">' + "".join(
            f'<circle cx="{x:g}" cy="{z:g}" r="{g["sight"]:g}"/>' for x, z in hull) + "</g>")
        if g["posture"] == "guard":
            yaw = (spot.get("facing") or 0) * math.pi / 180
            half = g["cone"] / 2 * math.pi / 180
            wedges = []
            for x, z in hull:
                ax, az = x - math.sin(yaw - half) * g["sight"], z - math.cos(yaw - half) * g["sight"]
                bx, bz = x - math.sin(yaw + half) * g["sight"], z - math.cos(yaw + half) * g["sight"]
                wedges.append(f'<path d="M{x:g},{z:g} L{ax:g},{az:g} A{g["sight"]:g},{g["sight"]:g} 0 0 0 {bx:g},{bz:g} Z"/>')
            parts.append('<g class="conegrp">' + "".join(wedges) + "</g>")
        if g["posture"] == "patrol":
            loop = " ".join(f'{p["x"]:g},{p["z"]:g}' for p in spot["points"])
            parts.append(f'<polygon points="{loop}" class="loop" stroke-width="{1.4 * s:g}" '
                         f'stroke-dasharray="{4 * s:g} {2 * s:g}"/>')
        if g["posture"] == "fire":
            fx, fz = spot["points"][0]["x"], spot["points"][0]["z"]
            parts.append(f'<rect x="{fx - 1.5:g}" y="{fz - 1.5:g}" width="3" height="3" class="firemark"/>')
        for x, z in [(p["at"][0], p["at"][2]) for p in posts]:
            parts.append(f'<circle cx="{x:g}" cy="{z:g}" r="{max(1.4, 2.6 * s):g}" class="dot {cls}">'
                         f'<title>{html.escape(g["id"])} ({g["posture"]}, {g["bodies"]} bodies)</title></circle>')
        if label:
            cx, cz = g["centre"]
            parts.append(f'<text x="{cx:g}" y="{cz - 3 * s:g}" class="grouplabel" font-size="{8.5 * s:g}" '
                         f'text-anchor="middle">{html.escape(g["id"].split(".")[1])}</text>')
    # Checkpoints, secrets, start, the boss.
    for c in layout["camps"]:
        cp = c.get("checkpoint")
        if cp:
            r = max(2.5, 4 * s)
            parts.append(f'<path d="M{cp["x"]:g},{cp["z"] - r:g} L{cp["x"] + r:g},{cp["z"]:g} L{cp["x"]:g},'
                         f'{cp["z"] + r:g} L{cp["x"] - r:g},{cp["z"]:g} Z" class="checkpoint"><title>Checkpoint '
                         f'{c["id"]}</title></path>')
    for sc in layout["secrets"]:
        parts.append(f'<rect x="{sc["x"] - sc["sx"] / 2:g}" y="{sc["z"] - sc["sz"] / 2:g}" width="{sc["sx"]:g}" '
                     f'height="{sc["sz"]:g}" class="secret"><title>Secret {sc["id"]} (needs {sc["needs"]})</title></rect>')
    st = layout["start"]
    parts.append(f'<circle cx="{st["x"]:g}" cy="{st["z"]:g}" r="{max(3, 5 * s):g}" class="start"><title>Start</title></circle>')
    stage = next(x for x in level_file["stages"] if x["kind"] == "camp")
    boss = next(w["boss"] for w in stage["waves"] if w.get("boss"))
    camp_c = next(c for c in layout["camps"] if c["id"] == stage["zone"])
    bx, bz = camp_c["x"] + boss["at"][0], camp_c["z"] + boss["at"][1]
    parts.append(f'<circle cx="{bx:g}" cy="{bz:g}" r="4" class="boss"><title>The Colossus rises here</title></circle>')
    parts.append("</svg>")
    return "".join(p for p in parts if p)


def legend_svg():
    items = [("road", "rect", "Road"), ("floor", "rect", "Camp floor"), ("locked", "rect", "Boss room (locks)"),
             ("water", "rect", "Water"), ("ledge", "rect", "Ledge"), ("cover", "rect", "Cover (3.5 tall)"),
             ("tent", "rect", "Reinforcement tent"), ("secret", "rect", "Secret site"),
             ("route", "line", "Route"), ("sneak", "line", "Sneak path"), ("loop", "line", "Patrol loop"),
             ("dot guard", "dot", "Guard post"), ("dot fire", "dot", "Fire seat"), ("dot patrol", "dot", "Patrol post"),
             ("sight guard", "circle", "Sight radius"), ("reach guard", "ring", "2 x sight: wakes resting neighbours"),
             ("cone", "cone", "Guard's 140 degree cone"), ("checkpoint", "diamond", "Checkpoint"),
             ("boss", "dot", "Colossus spot"), ("start", "dot", "Start")]
    out = ['<div class="legend">']
    for cls, shape, text in items:
        if shape == "rect":
            sym = f'<rect x="1" y="3" width="16" height="10" class="{cls}" stroke-width="1.2"/>'
        elif shape == "line":
            dash = ' stroke-dasharray="4 3"' if cls in ("sneak", "loop") else ""
            sym = f'<line x1="1" y1="8" x2="17" y2="8" class="{cls}" stroke-width="{3 if cls == "sneak" else 2}"{dash}/>'
        elif shape == "dot":
            sym = f'<circle cx="9" cy="8" r="4" class="{cls}"/>'
        elif shape == "circle":
            sym = f'<circle cx="9" cy="8" r="7" class="{cls}"/>'
        elif shape == "ring":
            sym = '<g class="reachgrp guard" style="opacity:.3"><circle cx="9" cy="8" r="7"/></g>'
        elif shape == "cone":
            sym = '<path d="M9,14 L2,3 A9,9 0 0 1 16,3 Z" class="cone"/>'
        else:
            sym = '<path d="M9,2 L15,8 L9,14 L3,8 Z" class="checkpoint"/>'
        out.append(f'<span class="item"><svg viewBox="0 0 18 16" width="18" height="16" aria-hidden="true">{sym}</svg>'
                   f'{html.escape(text)}</span>')
    out.append("</div>")
    return "".join(out)


# ---------------------------------------------------------------------------------------------
# ASCII
# ---------------------------------------------------------------------------------------------

ASCII_LEGEND = "=road s sneak g/f/p guard/fire/patrol T tent c chk *boss"


def ascii_map(layout, numbers, box, cols=60, rows=30, boss=None):
    x0, x1, z0, z1 = box
    sx, sz = (x1 - x0) / cols, (z1 - z0) / rows
    grid = [[" "] * cols for _ in range(rows)]

    def put(x, z, ch, force=True):
        c, r = int((x - x0) / sx), int((z - z0) / sz)
        if 0 <= c < cols and 0 <= r < rows and (force or grid[r][c] == " "):
            grid[r][c] = ch

    def fill(bx0, bx1, bz0, bz1, ch):
        for r in range(rows):
            for c in range(cols):
                x, z = x0 + (c + 0.5) * sx, z0 + (r + 0.5) * sz
                if bx0 <= x <= bx1 and bz0 <= z <= bz1:
                    grid[r][c] = ch

    for b in layout["blocks"]:
        if b.get("collide") is False:
            continue
        ch = {"path": "=", "ground": "%", "water": "~"}.get(b["look"], "=")
        fill(b["x"] - b["sx"] / 2, b["x"] + b["sx"] / 2, b["z"] - b["sz"] / 2, b["z"] + b["sz"] / 2, ch)
    for c in layout["camps"]:
        cx0, cx1, cz0, cz1 = c["x"] - c["sx"] / 2, c["x"] + c["sx"] / 2, c["z"] - c["sz"] / 2, c["z"] + c["sz"] / 2
        fill(cx0 - sx * 0.5, cx1 + sx * 0.5, cz0 - sz * 0.5, cz1 + sz * 0.5, "#")
        fill(cx0 + sx * 0.5, cx1 - sx * 0.5, cz0 + sz * 0.5, cz1 - sz * 0.5, ".")
        for g in c.get("gates") or []:
            gx0, gx1, gz0, gz1 = cl.gate_rect(c, g, 1.0)
            fill(gx0 - sx, gx1 + sx, gz0 - sz * 0.6, gz1 + sz * 0.6, "=" if not c.get("locks") else "|")
    for x, z in seg_samples(layout.get("sneak") or [], step=min(sx, sz) / 2):
        c_, r_ = int((x - x0) / sx), int((z - z0) / sz)
        if 0 <= c_ < cols and 0 <= r_ < rows and grid[r_][c_] in (".", " ", "#"):
            grid[r_][c_] = "s"
    for g in numbers["groups"]:
        ch = {"guard": "g", "fire": "f", "patrol": "p"}[g["posture"]]
        for x, z in g["points"][::4] if g["posture"] == "patrol" else g["points"]:
            put(x, z, ch)
    for c in layout["camps"]:
        if c.get("checkpoint"):
            put(c["checkpoint"]["x"], c["checkpoint"]["z"], "c")
    for s_ in layout["secrets"]:
        put(s_["x"], s_["z"], "?")
    for c in layout["camps"]:
        if c.get("tent"):
            put(c["tent"]["x"], c["tent"]["z"], "T")
        put(c["x"] - c["sx"] / 2 + sx, c["z"] + c["sz"] / 2 - sz, c["id"])
    put(layout["start"]["x"], layout["start"]["z"], "S")
    if boss is not None:
        put(boss[0], boss[1], "*")
    return ["".join(row).rstrip() for row in grid], sx, sz


# ---------------------------------------------------------------------------------------------
# The page
# ---------------------------------------------------------------------------------------------

CSS = """
:root{--bg:#f6f5f1;--fg:#1d1f22;--muted:#5d636b;--card:#ffffff;--line:#d9d6cf;--grid:#e3e0d8;
--road:#c9b58f;--ledge:#a7b48c;--water:#8fc1e3;--floor:#e9e1cf;--fence:#6c5a43;--locked:#b8322b;
--cover:#8a8d93;--tent:#8b5a2b;--route:#3b3f46;--sneak:#d1209a;--guard:#c0392b;--fire:#e67e22;
--patrol:#7d3cb5;--checkpoint:#138d90;--secret:#d4a017;--start:#1f6feb;--boss:#5a1830;--pass:#1b7f3b;--fail:#b8322b;
--sightfill:0.13;--cone:#c0392b33}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#15171a;--fg:#e8e6e1;--muted:#a0a6ad;
--card:#1e2126;--line:#353a41;--grid:#2a2e34;--road:#7d6c4e;--ledge:#5e6b47;--water:#2f5f80;--floor:#34302a;
--fence:#b59a72;--locked:#ff6b5e;--cover:#6d7178;--tent:#c68645;--route:#c9ccd1;--sneak:#ff5fc8;--guard:#ff6b5e;
--fire:#ffa94d;--patrol:#b98cf0;--checkpoint:#3fd0d3;--secret:#f2c94c;--start:#5aa2ff;--boss:#ff8fb1;
--pass:#5fd38a;--fail:#ff6b5e;--sightfill:0.18;--cone:#ff6b5e40}}
:root[data-theme="dark"]{--bg:#15171a;--fg:#e8e6e1;--muted:#a0a6ad;--card:#1e2126;--line:#353a41;--grid:#2a2e34;
--road:#7d6c4e;--ledge:#5e6b47;--water:#2f5f80;--floor:#34302a;--fence:#b59a72;--locked:#ff6b5e;--cover:#6d7178;
--tent:#c68645;--route:#c9ccd1;--sneak:#ff5fc8;--guard:#ff6b5e;--fire:#ffa94d;--patrol:#b98cf0;--checkpoint:#3fd0d3;
--secret:#f2c94c;--start:#5aa2ff;--boss:#ff8fb1;--pass:#5fd38a;--fail:#ff6b5e;--sightfill:0.18;--cone:#ff6b5e40}
*{box-sizing:border-box}
html,body{margin:0;padding:0}
body{background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
overflow-x:hidden}
main{max-width:1100px;width:100%;margin:0 auto;padding:16px;overflow-wrap:anywhere}
h1{font-size:1.5rem;margin:.2rem 0 .3rem}
h2{font-size:1.2rem;margin:1.6rem 0 .4rem;border-top:1px solid var(--line);padding-top:1rem}
h3{font-size:1rem;margin:1rem 0 .3rem}
p,li{color:var(--fg)}
.muted{color:var(--muted)}
.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px;margin:.6rem 0}
svg.map{display:block;width:100%;height:auto;max-width:100%}
.insets{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:10px}
.insets figure{margin:0}.insets>*{min-width:0}
.card{min-width:0;max-width:100%}
figcaption{font-size:.85rem;color:var(--muted);margin-top:.2rem}
.tablewrap{overflow-x:auto;max-width:100%}
table{border-collapse:collapse;font-size:.85rem;margin:.3rem 0}
th,td{border:1px solid var(--line);padding:3px 6px;text-align:right;white-space:nowrap;overflow-wrap:normal}
th:first-child,td:first-child{text-align:left}
th{background:var(--grid)}
.ok{color:var(--pass);font-weight:600}.bad{color:var(--fail);font-weight:600}
pre{background:var(--card);border:1px solid var(--line);border-radius:6px;padding:8px;font-size:11px;line-height:1.2;
overflow-x:auto;max-width:100%}
.legend{display:flex;flex-wrap:wrap;gap:4px 12px;font-size:.8rem;margin:.4rem 0}
.legend .item{display:inline-flex;align-items:center;gap:4px}
.bg{fill:var(--bg)}.grid{stroke:var(--grid)}.gridlabel{fill:var(--muted)}
.road{fill:var(--road)}.ledge{fill:var(--ledge)}.water{fill:var(--water)}.sign{fill:var(--road)}
.floor{fill:var(--floor);stroke:var(--fence)}.floor.locked,rect.locked{stroke:var(--locked);fill:var(--floor)}
.legend rect.locked{stroke:var(--locked)}.legend rect.floor{stroke:var(--fence)}
.opening{fill:var(--road)}.gate{fill:var(--locked)}
.cover{fill:var(--cover)}.tent{fill:var(--tent);fill-opacity:.85;stroke:var(--fg)}.tentlabel{fill:var(--bg);font-weight:700}
.camplabel{fill:var(--fence);font-weight:700}.grouplabel{fill:var(--fg)}
.route{fill:none;stroke:var(--route);stroke-linejoin:round}.legend line.route{stroke:var(--route)}
.sneak{fill:none;stroke:var(--sneak);stroke-linejoin:round}
.loop{fill:none;stroke:var(--patrol)}
.dot.guard{fill:var(--guard)}.dot.fire{fill:var(--fire)}.dot.patrol{fill:var(--patrol)}
.sight{stroke:none;fill-opacity:var(--sightfill)}.sight.guard{fill:var(--guard)}.sight.fire{fill:var(--fire)}
.sight.patrol{fill:var(--patrol)}
.reach{fill:none;stroke-opacity:.45}.reach.guard{stroke:var(--guard)}.reach.fire{stroke:var(--fire)}
.reach.patrol{stroke:var(--patrol)}
.cone{fill:var(--cone)}.conegrp{fill:var(--guard);opacity:.3}
a{color:var(--checkpoint)}
.reachgrp{opacity:.07}.sightgrp{opacity:.22}
.reachgrp.guard,.sightgrp.guard{fill:var(--guard)}.reachgrp.fire,.sightgrp.fire{fill:var(--fire)}
.reachgrp.patrol,.sightgrp.patrol{fill:var(--patrol)}
.firemark{fill:var(--fire)}
.checkpoint{fill:var(--checkpoint)}.secret{fill:var(--secret)}.start{fill:var(--start)}.boss{fill:var(--boss)}
"""


def fmt(n, d=0):
    if isinstance(n, float):
        return f"{n:,.{d}f}"
    return f"{n:,}"


def table(head, rows, cls=""):
    out = [f'<div class="tablewrap"><table class="{cls}"><thead><tr>']
    out += [f"<th>{html.escape(str(h))}</th>" for h in head]
    out.append("</tr></thead><tbody>")
    for row in rows:
        out.append("<tr>" + "".join(f"<td>{c}</td>" for c in row) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


def okmark(ok):
    return '<span class="ok">yes</span>' if ok else '<span class="bad">NO</span>'


def section(name, title, level_file, layout, numbers, gates, blurb):
    n = numbers
    b = n["wire"]["bounds"]
    pad = 20
    box = (b[0] - pad, b[1] + pad, b[2] - pad, b[3] + pad)
    out = [f'<h2 id="{name}">{html.escape(title)}</h2>', f"<p>{blurb}</p>"]
    out.append('<div class="card">' + svg_map(layout, level_file, n, box, 1060, title=title) +
               '<figcaption>Whole level, to scale, north up. Grid: 100 studs.</figcaption></div>')
    out.append('<div class="insets">')
    for c in layout["camps"]:
        m = 34
        cbox = (c["x"] - c["sx"] / 2 - m, c["x"] + c["sx"] / 2 + m, c["z"] - c["sz"] / 2 - m, c["z"] + c["sz"] / 2 + m)
        out.append('<figure class="card">' + svg_map(layout, level_file, n, cbox, 360, grid=25,
                                                    label=True, title=f"Camp {c['id']}") +
                   f'<figcaption>Camp {c["id"]} close up ({c["sx"]:g} x {c["sz"]:g}, floor top {c["y"]:g}). '
                   f'Grid: 25 studs.</figcaption></figure>')
    out.append("</div>")

    # Population.
    pop = n["population"]
    rows = []
    for d, p in pop.items():
        r = p["residents"]
        rows.append([d.title(), r.get("A", 0), r.get("B", 0), r.get("C", 0), p["total"], p["tentTotal"], p["room"],
                     BOSS_RESERVE, f"<b>{p['worst']}</b>", p["cap"], okmark(p["worst"] <= p["cap"]), p["validate21"]])
    out.append("<h3>Bodies against the 160 cap (computed)</h3>")
    out.append(table(["Difficulty", "A", "B", "C", "Residents", "Tents' stock", "Boss room's room", "Boss + 12 calls",
                      "Worst case, every camp awake", "Cap", "Fits", "Wave 1 rule (reserve 21)"], rows))
    out.append('<p class="muted">Worst case = every resident alive + every tent\'s whole stock out and alive + the boss '
               'room\'s cap over its residents (stage maxAlive ' + str(next(s for s in level_file["stages"]
                                                                            if s["kind"] == "camp")["maxAlive"]) +
               ') + the Colossus and 12 calls. Residents never scale with countMult (L1b-10).</p>')
    # Parts, wire, route, time.
    t = n["time"]
    rows = [
        ["Parts (check_levels' count + 1 per tent)", f"{n['parts']['checkLevels']} + {n['parts']['tents']} = "
                                                     f"<b>{n['parts']['total']}</b>", f"&le; {n['parts']['max']}",
         okmark(n["parts"]["total"] <= n["parts"]["max"]), "computed"],
        ["Furthest camp edge + wall from the origin", fmt(n["wire"]["campFurthest"], 1), "&le; 1,000 (codec 1,024)",
         okmark(n["wire"]["campFurthest"] <= 1000), "computed"],
        ["Furthest Part from the origin", fmt(n["wire"]["anyFurthest"], 1), "(bodies never leave a floor)", "", "computed"],
        ["Route length", fmt(n["route"]["length"], 0), "about 1,000", okmark(900 <= n["route"]["length"] <= 1100),
         "computed"],
        ["Through the camps (A / B / C)", " / ".join(fmt(v, 0) for v in n["route"]["camps"].values()), "", "", "computed"],
        ["Sneak path length", fmt(n["sneak"]["length"], 0), "", "", "computed"],
        ["Sneak path on solid ground", f"{n['sneak']['samples'] - n['sneak']['offGround']} of {n['sneak']['samples']} "
                                       f"samples", "all", okmark(n["sneak"]["offGround"] == 0), "computed"],
        ["Closest two resting posts, less r_a + r_b + 0.5", f"{n['postSpacing']['spare']:.2f} "
         f"({html.escape(' / '.join(n['postSpacing']['between']))}, {n['postSpacing']['difficulty']})", "&ge; 0",
         okmark(n["postSpacing"]["spare"] >= -1e-9), "computed"],
        ["Gaps between camp floors", ", ".join(f"{k} {v:.0f}" for k, v in n["campGaps"].items()),
         "dormancy: over dormantRadius 100-150", "", "computed"],
    ]
    out.append("<h3>Parts, the wire, the route</h3>")
    out.append(table(["What", "Value", "Limit", "Inside", "Kind"], rows))
    rows = [
        ["Walking the route at 20 studs/s", fmt(t["walk"], 0), "computed from the route"],
        ["Walking from group to group inside A and B", fmt(t["tour"], 0),
         "computed: a nearest-first tour of the groups' centres, less the camp leg"],
        ["Camp A: residents + tent", fmt(t["fights"]["A"], 0), "estimate: effective HP / 100 per s"],
        ["Camp B: residents + tent", fmt(t["fights"]["B"], 0), "estimate: effective HP / 100 per s"],
        ["Camp C: residents + its waves", fmt(t["fights"]["C"], 0), "estimate: effective HP / 100 per s"],
        ["The Colossus", fmt(t["colossus"], 0), "measured in Wave 1 (73.7-75.6 s)"],
        ["The countdown", fmt(t["countdown"], 0), "levels.gateSeconds"],
        ["<b>First Normal clear, the simulator's reacting player</b>",
         f"<b>{fmt(t['sim'], 0)} s = {t['sim'] / 60:.1f} min</b>", "estimate"],
        ["<b>First Normal clear, Ben</b> (his fights x 1.36, as Wave 1)",
         f"<b>{fmt(t['human'], 0)} s = {t['human'] / 60:.1f} min</b>", "estimate"],
    ]
    out.append("<h3>Estimated first Normal clear at gear 2 / 2</h3>")
    out.append(table(["Part", "Seconds", "How"], rows))
    # Pay.
    pay = n["pay"]
    rows = []
    for d in ("normal", "hard", "brutal"):
        p = pay[d]
        cs = p["camps"]
        rows.append([d.title(),
                     f"{fmt(cs['A']['cash'])} + {fmt(cs['A']['bonusCash'])}",
                     f"{fmt(cs['B']['cash'])} + {fmt(cs['B']['bonusCash'])}",
                     f"{fmt(cs['C']['cash'])} + {fmt(cs['C']['bonusCash'])}",
                     fmt(cs["C"]["bossCash"]), f"<b>{fmt(p['cash'])}</b>", fmt(p["materials"]), p["valor"]])
    out.append("<h3>What a full clear pays (computed from the files)</h3>")
    out.append(table(["Difficulty", "A kills + bonus", "B kills + bonus", "C kills + bonus", "Colossus + 48 calls",
                      "Cash", "Timber", "Valor"], rows))
    pm = pay["perMinute"]
    out.append(f'<p>Per minute on Normal: <b>{fmt(pm["simCash"])}</b> cash and {pm["simTimber"]:.0f} Timber at the '
               f'simulator\'s clear, <b>{fmt(pm["humanCash"])}</b> and {pm["humanTimber"]:.0f} at Ben\'s. Wave 1: '
               f'{fmt(WAVE1["cashPerMinute"])} and {WAVE1["timberPerMinute"]}; L1: {fmt(L1["cashPerMinute"])} and '
               f'{L1["timberPerMinute"]}. The clear bonus is 10% of the camp\'s whole stock at the difficulty\'s price '
               f'(residents, tent and, in C, its waves), so sneaking costs nothing extra.</p>')
    # Groups and the sneak path.
    rows = []
    for g in n["groups"]:
        ch = n["chains"][g["id"]]
        mix = ", ".join(f"{u['count']} {u['kind']}" for u in g["units"])
        held = " (held)" if g["held"] else ""
        rows.append([html.escape(g["id"]) + held, g["posture"], g["bodies"], html.escape(mix), fmt(g["sight"]),
                     f"{g['sneakDistance']:.1f}", okmark(g["sneakDistance"] > g["sight"]) if not g["held"] else "n/a",
                     f"{g['roadDistance']:.1f}", "yes" if g["roadSeen"] else "no",
                     f"{len(ch['wakes'])} groups, {ch['bodies']} bodies"])
    out.append("<h3>Every resting group (Hard and Brutal; Normal drops the Hard units)</h3>")
    out.append(table(["Group", "Rest", "Bodies", "Mix", "Sight", "Sneak path's closest", "Beyond sight",
                      "Road's closest", "Road seen", "A wake here wakes (2 x sight chain)"], rows))
    out.append('<p class="muted">Closest = the flat distance from the path to the nearest place a member rests (a '
               'patrol: anywhere on its loop). "Road seen" asks CampBrain.Sees with the cone, so a careless walker on '
               'the route wakes that group. Held groups (the boss room) cannot wake before the close.</p>')
    # Gates.
    fails = [t_ for ok, t_ in gates if not ok]
    out.append(f"<h3>check_levels.py's own gates on this draft: {len(gates) - len(fails)} of {len(gates)} pass</h3>")
    if fails:
        out.append("<ul>" + "".join(f'<li class="bad">{html.escape(f_)}</li>' for f_ in fails) + "</ul>")
    else:
        out.append('<p class="ok">Every gate passes (the Wave 2 sizes put in its table in memory: camps 85 x 85, '
                   '141 x 133, 115 x 115; route 900-1,100; A 30-36 and B 40-50 residents).</p>')
    return "".join(out)


def tent_section():
    return """
<h2 id="tents">The tent question, costed</h2>
<p>Every option below is in the report with its cost; the recommendation is marked.</p>
<div class="tablewrap"><table>
<thead><tr><th>Question</th><th>Option</th><th>Bodies on the cap</th><th>Code</th><th>Risk</th></tr></thead><tbody>
<tr><td>(a) Stock per tent</td><td>4</td><td>+8 for A and B</td><td>none beyond the tent</td><td>barely felt</td></tr>
<tr><td></td><td><b>8 (recommended)</b></td><td>+16 (Hard worst case 157 of 160)</td><td>none beyond the tent</td><td>one more group per camp</td></tr>
<tr><td></td><td>12</td><td>+24: Hard worst case 165, 5 over the cap</td><td>none beyond the tent</td><td>a long tail at the end of every camp</td></tr>
<tr><td>(b) Pace</td><td><b>one every 6 s (recommended)</b></td><td>same</td><td>a number</td><td>8 out in 42 s, about the length of a camp's fight</td></tr>
<tr><td></td><td>one every 10 s</td><td>same</td><td>a number</td><td>8 out in 70 s: A's tent outlasts A's residents, the end is waiting</td></tr>
<tr><td></td><td>one every 15 s</td><td>same</td><td>a number</td><td>most of the stock comes after the camp is clear</td></tr>
<tr><td>(c) Stopping it</td><td><b>stops when its stock is spent (recommended)</b></td><td>0</td><td>CampBrain rule + WaveService</td><td>none new</td></tr>
<tr><td></td><td>destroyable, a crowd body with no brain</td><td>+1 per tent</td><td>a `tent` kind; CrowdRenderer model; HitShapes as is</td><td>separation round a radius-5 body; a new look</td></tr>
<tr><td></td><td>destroyable, a Part the server tests</td><td>0</td><td>a new hit path in WeaponService for Parts</td><td>a second damage path to review</td></tr>
<tr><td>(d) Where they go</td><td><b>join their camp's fight (recommended)</b></td><td>0</td><td>tent group goes straight to fight, its post the tent</td><td>none new</td></tr>
<tr><td></td><td>to wherever the fight is, past the fence</td><td>0</td><td>a body may leave its floor: breaks L1b-1</td><td>large</td></tr>
</tbody></table></div>
"""


def page(sections, ascii_blocks):
    head = ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            "<title>The Long Road</title><style>" + CSS + "</style></head><body><main>")
    intro = ("<h1>The Long Road</h1><p class=\"muted\">L1b Wave 2 layout plan for Forest Road. Two layouts, drawn to "
             "scale from the draft JSON with the game's own rules: posts as CampBrain.Posts places them, sight and "
             "cones as CampBrain.Sees reads them, Parts as LevelGeometry builds them. North is up. Nothing in the "
             "game has changed yet.</p>" + legend_svg() +
             "<p><a href=\"#winding\">The winding road (recommended)</a> &middot; <a href=\"#switchback\">The "
             "switchback (alternative)</a> &middot; <a href=\"#tents\">The tents</a> &middot; <a href=\"#ascii\">ASCII "
             "maps</a></p>")
    asc = ["<h2 id=\"ascii\">ASCII maps (for a click question)</h2>"]
    for title, lines, legend in ascii_blocks:
        asc.append(f"<h3>{html.escape(title)}</h3><pre>" + html.escape("\n".join(lines + [legend])) + "</pre>")
    return head + intro + "".join(sections) + tent_section() + "".join(asc) + "</main></body></html>\n"


BLURBS = {
    "winding": ("West to east, the road zigzags through the forest: the gap and the creek, the climb by the lookout, "
                "then the three camps, each crossed along its north side so the camp sprawls south of the road. A "
                "careless walker on the road is seen by each camp's watch; a careful one hugs the inside of the north "
                "fence (the pink line) and passes every resting eye beyond its sight. Each open camp wakes in two or "
                "three chunks, not all at once."),
    "switchback": ("The road folds back on itself up a hillside in three terraces (0, 8, 18, 28): east along the "
                   "valley through the Pickets, a hairpin up and west to the Main Camp, a second hairpin up and east "
                   "along the high road, which overlooks the Main Camp, to the Chief at the top. The camps are crossed "
                   "corner to corner. Past the Main Camp the sneak path is a goat track outside its fence."),
}


def main():
    combat, expeditions, real_layouts, _files, ctx = cl.load_all()
    sections, ascii_blocks, all_numbers, ascii_txt = [], [], {}, []
    for name, title in DESIGNS:
        level_file, layout = load(name)
        gates, facts, level = run_gates(level_file, layout, ctx, real_layouts)
        numbers = measure(name, level_file, layout, level, facts, ctx)
        numbers["gates"] = {"pass": sum(1 for ok, _t in gates if ok), "total": len(gates),
                            "failures": [t for ok, t in gates if not ok]}
        all_numbers[name] = numbers
        sections.append(section(name, title, level_file, layout, numbers, gates, BLURBS[name]))
        b = numbers["wire"]["bounds"]
        width, depth = b[1] - b[0], b[3] - b[2]
        cols = 60
        rows = min(30, max(8, int(round(depth / (width / cols)))))
        stage = next(x for x in level_file["stages"] if x["kind"] == "camp")
        boss = next(w["boss"] for w in stage["waves"] if w.get("boss"))
        room = next(c for c in layout["camps"] if c["id"] == stage["zone"])
        lines, sx, sz = ascii_map(layout, numbers, (b[0], b[1], b[2], b[3]), cols, rows,
                                  boss=(room["x"] + boss["at"][0], room["z"] + boss["at"][1]))
        legend = ASCII_LEGEND
        heading = f"{title}, 1 char = {sx:.0f} x {sz:.0f} studs, north up"
        ascii_blocks.append((heading, lines, legend))
        ascii_txt += [heading, *lines, legend, ""]
        print(f"{name}: gates {numbers['gates']['pass']}/{numbers['gates']['total']}")
        for f in numbers["gates"]["failures"]:
            print("   FAIL", f)
    (HERE / "long-road.html").write_text(page(sections, ascii_blocks), encoding="utf-8", newline="\n")
    (HERE / "ascii.txt").write_text("\n".join(ascii_txt), encoding="utf-8", newline="\n")
    clean = json.loads(json.dumps(all_numbers, default=lambda o: list(o) if isinstance(o, tuple) else str(o)))
    for n in clean.values():
        for g in n["groups"]:
            g.pop("points", None)
    (HERE / "numbers.json").write_text(json.dumps(clean, indent=1) + "\n", encoding="utf-8", newline="\n")
    print("wrote long-road.html, ascii.txt, numbers.json")


if __name__ == "__main__":
    main()
