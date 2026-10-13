#!/usr/bin/env python
"""Level layout and map gates for Era City Tycoon's Expeditions (L1, "Forest Road in grey").

A level is built in Studio from `src/shared/Layouts/Levels/<Name>.json`, and nobody sees it there
before the owner does. This tool proves the layout on paper instead: it walks the level's `route`
over the layout's boxes the way a player with one jump would, checks every gate of the constraint
table in docs/INTERFACES.md "L1 contracts" -> "Config", and prints a top-down plan and a side
view of each level in plain characters.

What it reads, and copies no number from:
  Config/Combat.json          levels.* (fence thickness, trigger inset, Part budget), player.rescue
  Config/ProvingGrounds.json  movement.* (jump, double jump, walk, dash), the crowd kinds' radii and
                              keepAway bands, threat.spawnClear, crowd.maxAlive
  Config/Expeditions.json     the map's nodes, themes and looks
  Config/Levels/*.json        each level's stages (which kinds stand in which camp, the boss spot)
  Layouts/Levels/*.json       the layouts; a file that names an `arena` is read through
                              sim_range.arena_as_layout, the mirror of LevelGeometry.FromArena

Geometry rules, as LevelService builds them (the Village arena's rule): a camp's fence stands
OUTSIDE its floor rectangle, `levels.fenceThickness` thick; the barrier stands outside the fence,
`barrier.thickness` deep. So a road runs up to the floor's edge and passes under the gate.

The route. `route[i].via` says how the leg that ENDS at point i is travelled: absent = walked,
"climb" = one jump up onto a ledge, "gap" = one jump across a hole, "camp" = through a camp from
its entry point to its exit point. The y of a route point is the height of the ground there.

Usage:
  py tools/check_levels.py                # the gates and the plans; exit 1 when a gate fails
  py tools/check_levels.py --no-plan      # the gates only
  py tools/check_levels.py --plan-only    # the plans only
  py tools/check_levels.py --scale 4 8    # studs per character across and down (default 4 8)
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sim_range as sr  # noqa: E402  (the arena adapter and the config loaders live there)

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = REPO_ROOT / "src" / "shared" / "Config"

# ---------------------------------------------------------------------------------------------
# The constraint table (docs/INTERFACES.md "L1 contracts" -> "Config"). Tool bands, not game
# values: nothing in the game reads them.
# ---------------------------------------------------------------------------------------------

# What a named layout must be. A layout with no entry here is held to the general gates only.
EXPECTED = {
    "ForestRoad": {
        "camps": {"A": (60, 60), "B": (100, 94), "C": (81, 81)},
        "campTolerance": 0.10,
        "routeStuds": (500, 600),
        "secrets": {"lookout": "doubleJump", "cache": "fire", "shrine": "ice"},
        "climbs": 1,
        "gaps": 1,
        "creek": True,
    },
}
# What a sign must say for each key, so a player knows what to bring.
NEED_WORDS = {"doubleJump": "DOUBLE JUMP", "fire": "FIRE", "ice": "ICE"}
ROAD_MIN_WIDTH = 12.0
CLIMB_SHARE = 0.55  # a climb rises at most this share of movement.jumpHeight ...
GAP_SHARE = 0.90  # ... and a gap spans at most this share of one jump's reach at walk speed
WALK_RISE = 1.0  # a walked leg steps up at most this much
GATE_MIN_WIDTH = 12.0
SPAWNS_MIN = 4
SPAWN_ENTRY_MIN = 12.0
BARRIER = {"height": 80.0, "thickness": 8.0}
ORIGIN_LIMIT = 1000.0  # the wire carries +-1,024 studs round the world origin (ruling 12)
LOOKOUT_OVER_JUMP = 2.0  # the ledge is at least this far over one jump ...
LOOKOUT_UNDER_DOUBLE = 4.0  # ... and at least this far under jump + double jump
CREEK_DROP = 1.0
KILL_MARGIN = 20.0
KILL_FLOOR = -450.0
LOBBY_CLEARANCE = 150.0
DENSITY_AREA = 200.0  # a camp's maxAlive is at most its floor area over this (the arena: 60 on 110 x 110)
BAND_SHARE = 0.45  # a keepAway kind's bandMin is at most this share of the camp's shorter side
RUN_CAP_RATIO = 2.0
REQUIRED_LOOKS = ("ground", "path", "campFloor", "wall", "gate", "checkpoint", "checkpointDone", "secret",
                  "sign", "water", "lobby")
COLOUR_LOOKS = ("gate", "checkpoint", "checkpointDone", "secret")  # each must read at a glance
GREY_SPREAD = 40  # a grey's channels lie within this of each other; a colour's do not
# The engine's Enum.Material names. LevelService leaves a Part of an unknown look or material as
# the engine makes it, with one warn, so a look must name one of these, and a layout may name
# only a material that some look of Expeditions.json already uses.
ENGINE_MATERIALS = frozenset((
    "Plastic", "SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Marble", "Basalt", "Slate", "CrackedLava",
    "Concrete", "Limestone", "Granite", "Pavement", "Brick", "Pebble", "Cobblestone", "Rock", "Sandstone",
    "CorrodedMetal", "DiamondPlate", "Foil", "Metal", "Grass", "LeafyGrass", "Sand", "Fabric", "Snow", "Mud",
    "Ground", "Asphalt", "Salt", "Ice", "Glacier", "Glass", "ForceField", "Cardboard", "Carpet", "CeramicTiles",
    "ClayRoofTiles", "RoofShingles", "Leather", "Plaster", "Rubber"))
BODY_HEIGHT = 6.0  # a character, feet to head: what stands this far under a barrier's foot is in it
CLOSE_SPARE = 1.0  # a camp's entry point lies this far inside the close rule's inset rectangle
SIGN_REACH = 6.0  # a secret's sign stands at the level of a block no further from it than this
SAMPLE = 0.25  # studs between two samples of a walked leg
EPS = 1e-6
SIDES = ("north", "south", "west", "east")


# ---------------------------------------------------------------------------------------------
# Boxes
# ---------------------------------------------------------------------------------------------


class Solid:
    """Something a player can stand on, seen from above: a rectangle with a top and a bottom."""

    def __init__(self, name, kind, look, x0, x1, z0, z1, bottom, top):
        self.name, self.kind, self.look = name, kind, look
        self.x0, self.x1, self.z0, self.z1 = min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)
        self.bottom, self.top = bottom, top

    def holds(self, x, z):
        return self.x0 - EPS <= x <= self.x1 + EPS and self.z0 - EPS <= z <= self.z1 + EPS

    def gap_to(self, other):
        """The flat distance between two footprints (0 when they touch or overlap)."""
        dx = max(self.x0 - other.x1, other.x0 - self.x1, 0.0)
        dz = max(self.z0 - other.z1, other.z0 - self.z1, 0.0)
        return math.hypot(dx, dz)


def block_solid(block):
    hx, hy, hz = block["sx"] / 2, block["sy"] / 2, block["sz"] / 2
    return Solid(block.get("name") or block["look"], "block", block["look"], block["x"] - hx, block["x"] + hx,
                 block["z"] - hz, block["z"] + hz, block["y"] - hy, block["y"] + hy)


def camp_rect(camp):
    return camp["x"] - camp["sx"] / 2, camp["x"] + camp["sx"] / 2, camp["z"] - camp["sz"] / 2, camp["z"] + camp["sz"] / 2


def fence_strips(camp, thickness):
    """The four fence strips, outside the floor (the Village rule): {side: (x0, x1, z0, z1)}."""
    x0, x1, z0, z1 = camp_rect(camp)
    t = thickness
    return {"north": (x0 - t, x1 + t, z0 - t, z0), "south": (x0 - t, x1 + t, z1, z1 + t),
            "west": (x0 - t, x0, z0, z1), "east": (x1, x1 + t, z0, z1)}


def gate_rect(camp, gate, thickness):
    """The opening a gate fills in its side's fence strip: (x0, x1, z0, z1)."""
    x0, x1, z0, z1 = camp_rect(camp)
    half = gate["width"] / 2
    if gate["side"] in ("west", "east"):
        mid = camp["z"] + gate["at"]
        return ((x0 - thickness, x0) if gate["side"] == "west" else (x1, x1 + thickness)) + (mid - half, mid + half)
    mid = camp["x"] + gate["at"]
    return (mid - half, mid + half) + ((z0 - thickness, z0) if gate["side"] == "north" else (z1, z1 + thickness))


def solids_of(layout, thickness):
    """Every standing surface of a layout: solid blocks, camp floors, fences, obstacles, secrets."""
    found = [block_solid(b) for b in layout["blocks"] if b.get("collide") is not False]
    for camp in layout["camps"]:
        x0, x1, z0, z1 = camp_rect(camp)
        found.append(Solid(f"Camp_{camp['id']}_Floor", "floor", "campFloor", x0, x1, z0, z1, camp["y"] - 1, camp["y"]))
        fence = camp.get("fence")
        if fence:
            for side, (fx0, fx1, fz0, fz1) in fence_strips(camp, thickness).items():
                found.append(Solid(f"Camp_{camp['id']}_Fence_{side}", "fence", "wall", fx0, fx1, fz0, fz1,
                                   camp["y"], camp["y"] + fence["height"]))
        for index, o in enumerate(camp.get("obstacles") or []):
            found.append(Solid(f"Camp_{camp['id']}_Obstacle_{index + 1}", "obstacle", "wall", o["x"] - o["sx"] / 2,
                               o["x"] + o["sx"] / 2, o["z"] - o["sz"] / 2, o["z"] + o["sz"] / 2, camp["y"],
                               camp["y"] + o["sy"]))
    for secret in layout["secrets"]:
        hx, hy, hz = secret["sx"] / 2, secret["sy"] / 2, secret["sz"] / 2
        found.append(Solid(f"Secret_{secret['id']}", "secret", "secret", secret["x"] - hx, secret["x"] + hx,
                           secret["z"] - hz, secret["z"] + hz, secret["y"] - hy, secret["y"] + hy))
    return found


def ground(solids, x, z, limit=math.inf, kinds=("block", "floor", "secret")):
    """The highest surface under (x, z) whose top is at most `limit`: (top, the Solid), or
    (None, None) over a hole. Fences and obstacles are not ground a route walks on."""
    best = None
    for s in solids:
        if s.kind in kinds and s.top <= limit + EPS and s.holds(x, z) and (best is None or s.top > best.top):
            best = s
    return (best.top, best) if best is not None else (None, None)


def layout_bounds(layout, thickness):
    """LevelGeometry.Bounds as a rectangle and a height span: blocks, camps with their fence and
    barrier, secrets. (minX, maxX, minZ, maxZ, minY, maxY), or None for an empty layout."""
    boxes = [(s.x0, s.x1, s.z0, s.z1, s.bottom, s.top) for s in solids_of(layout, thickness)]
    boxes += [(b.x0, b.x1, b.z0, b.z1, b.bottom, b.top)
              for b in (block_solid(x) for x in layout["blocks"] if x.get("collide") is False)]
    barrier = layout.get("barrier") or {}
    reach = thickness + (barrier.get("thickness") or 0)
    for camp in layout["camps"]:
        x0, x1, z0, z1 = camp_rect(camp)
        boxes.append((x0 - reach, x1 + reach, z0 - reach, z1 + reach, camp["y"] - 1,
                      camp["y"] + (barrier.get("height") or 0)))
    if not boxes:
        return None
    return (min(b[0] for b in boxes), max(b[1] for b in boxes), min(b[2] for b in boxes), max(b[3] for b in boxes),
            min(b[4] for b in boxes), max(b[5] for b in boxes))


def named_materials(layout):
    """Every material a layout names itself (a camp's floor, its fence, its obstacles)."""
    found = set()
    for camp in layout["camps"]:
        for piece in [camp.get("floor") or {}, camp.get("fence") or {}] + list(camp.get("obstacles") or []):
            if piece.get("material"):
                found.add(piece["material"])
    return found


def part_count(layout):
    """The Parts LevelService.Build makes: one per block; per camp the floor, the fence cut at its
    gates (four sides, one more piece per gate), the gates, the obstacles, the checkpoint marker
    and the four barrier boxes; per secret the marked block and its sign."""
    parts = len(layout["blocks"])
    for camp in layout["camps"]:
        gates = len(camp.get("gates") or [])
        obstacles = len(camp.get("obstacles") or []) + int(camp.get("obstacleCount") or 0)
        parts += 1 + (4 + gates if camp.get("fence") else 0) + gates + obstacles
        parts += (1 if camp.get("checkpoint") else 0) + (4 if layout.get("barrier") else 0)
    return parts + 2 * len(layout["secrets"])


# ---------------------------------------------------------------------------------------------
# Jumps (movement.* and the default gravity, as sim_range reads them)
# ---------------------------------------------------------------------------------------------


def jump_facts(move):
    """One jump at walk speed: seconds in the air, studs covered, and the limits the route's
    climbs and gaps are held to."""
    speed = math.sqrt(2 * sr.GRAVITY * move["jumpHeight"])
    air = 2 * speed / sr.GRAVITY
    reach = move["walkSpeed"] * air
    return {"air": air, "reach": reach, "speed": speed,
            "climb": math.ceil(CLIMB_SHARE * move["jumpHeight"]), "gap": math.floor(GAP_SHARE * reach)}


def reach_at_rise(move, rise):
    """How far a single jump at walk speed still carries the feet at `rise` studs above the
    take-off (the last moment it is that high); None when the jump never gets there. A drop
    (rise < 0) is the jump's whole flight down to that height."""
    speed = math.sqrt(2 * sr.GRAVITY * move["jumpHeight"])
    under = speed * speed - 2 * sr.GRAVITY * rise
    if under < 0:
        return None
    return move["walkSpeed"] * (speed + math.sqrt(under)) / sr.GRAVITY


def stray_reach(move, drop):
    """The furthest a player can land from where he stood, with a jump, a double jump and a dash,
    falling `drop` studs below his take-off: what "beside a camp" must be clear of."""
    up = math.sqrt(2 * move["jumpHeight"] / sr.GRAVITY) + math.sqrt(2 * move["doubleJumpHeight"] / sr.GRAVITY)
    down = math.sqrt(2 * (move["jumpHeight"] + move["doubleJumpHeight"] + max(drop, 0)) / sr.GRAVITY)
    return move["walkSpeed"] * (up + down) + move["dashDistance"]


# ---------------------------------------------------------------------------------------------
# The route
# ---------------------------------------------------------------------------------------------


def walk_route(layout, solids, move):
    """Walks the route leg by leg. Returns (problems, facts): facts = the legs with their kind,
    length and what was measured, and the totals."""
    problems = []
    legs = []
    route = layout["route"]
    jump = jump_facts(move)
    camps = {c["id"]: c for c in layout["camps"]}
    order = [c["id"] for c in layout["camps"]]
    seen_camps = []
    if not route:
        return ["no route"], {"legs": [], "length": 0.0, "walked": 0.0, "camps": []}
    first = route[0]
    start = layout["start"]
    if math.hypot(first["x"] - start["x"], first["z"] - start["z"]) > EPS or abs(first["y"] - start["y"]) > EPS:
        problems.append("the route does not begin at `start`")
    for index in range(1, len(route)):
        a, b = route[index - 1], route[index]
        via = b.get("via")
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        tag = f"leg {index} ({a['x']:g}, {a['z']:g}) -> ({b['x']:g}, {b['z']:g})"
        leg = {"index": index, "via": via or "walk", "length": run, "from": a, "to": b, "rise": b["y"] - a["y"]}
        legs.append(leg)
        ga, _sa = ground(solids, a["x"], a["z"], a["y"] + EPS)
        gb, _sb = ground(solids, b["x"], b["z"], b["y"] + EPS)
        if ga is None or abs(ga - a["y"]) > 0.01:
            problems.append(f"{tag}: its first point is not on the ground (ground {ga}, point y {a['y']:g})")
        if gb is None or abs(gb - b["y"]) > 0.01:
            problems.append(f"{tag}: its last point is not on the ground (ground {gb}, point y {b['y']:g})")
        if run <= EPS:
            problems.append(f"{tag}: has no length")
            continue
        ux, uz = (b["x"] - a["x"]) / run, (b["z"] - a["z"]) / run
        if via is None:
            height = a["y"]
            narrowest = math.inf
            steps = max(int(math.ceil(run / SAMPLE)), 1)
            for k in range(steps + 1):
                d = run * k / steps
                x, z = a["x"] + ux * d, a["z"] + uz * d
                top, under = ground(solids, x, z, height + WALK_RISE)
                if top is None:
                    problems.append(f"{tag}: leaves the blocks at ({x:.1f}, {z:.1f})")
                    break
                # Two boxes that meet under a sample: the walker is on the wider one.
                if under.kind == "block" and under.look == "path":
                    widths = []
                    for s in solids:
                        if s.kind == "block" and s.look == "path" and abs(s.top - top) < 0.01 and s.holds(x, z):
                            across = (s.z1 - s.z0) if abs(ux) > 0.999 else (s.x1 - s.x0) if abs(uz) > 0.999 else min(
                                s.x1 - s.x0, s.z1 - s.z0)
                            widths.append(across)
                    narrowest = min(narrowest, max(widths))
                height = top
            else:
                if abs(height - b["y"]) > 0.01:
                    problems.append(f"{tag}: walking it ends at height {height:g}, the point says {b['y']:g}")
            leg["width"] = narrowest
            if narrowest < ROAD_MIN_WIDTH - EPS:
                problems.append(f"{tag}: the road under it is {narrowest:g} wide (needs {ROAD_MIN_WIDTH:g})")
        elif via == "climb":
            rise = b["y"] - a["y"]
            if rise <= WALK_RISE:
                problems.append(f"{tag}: a climb of {rise:g} studs is a step, not a climb")
            if rise > jump["climb"] + EPS:
                problems.append(f"{tag}: climbs {rise:g} studs (one jump allows {jump['climb']})")
            if run > 4 + EPS:
                problems.append(f"{tag}: a climb leg is the ledge's face, at most 4 studs long ({run:g})")
        elif via == "gap":
            if b["y"] > a["y"] + EPS:
                problems.append(f"{tag}: the gap lands {b['y'] - a['y']:g} studs higher than its take-off")
            # The hole itself: from the last ground of the take-off to the first of the landing.
            steps = max(int(math.ceil(run / 0.05)), 1)
            opened = closed = None
            for k in range(steps + 1):
                d = run * k / steps
                top, _s = ground(solids, a["x"] + ux * d, a["z"] + uz * d, a["y"] + WALK_RISE)
                solid_here = top is not None and top > a["y"] - 4
                if opened is None and not solid_here:
                    opened = d
                if opened is not None and closed is None and solid_here:
                    closed = d
            if opened is None:
                problems.append(f"{tag}: there is ground all the way: it is no gap")
                hole = 0.0
            else:
                hole = (closed if closed is not None else run) - opened
            leg["hole"] = hole
            if max(hole, run) > jump["gap"] + EPS:
                problems.append(f"{tag}: the gap is {max(hole, run):g} studs across (one jump allows {jump['gap']})")
        elif via == "camp":
            owner = next((c for c in layout["camps"]
                          if abs(c["entry"]["x"] - a["x"]) < 0.01 and abs(c["entry"]["z"] - a["z"]) < 0.01
                          and abs(c["exit"]["x"] - b["x"]) < 0.01 and abs(c["exit"]["z"] - b["z"]) < 0.01), None)
            if owner is None:
                problems.append(f"{tag}: a camp leg must run from a camp's entry point to its exit point")
            else:
                seen_camps.append(owner["id"])
                leg["camp"] = owner["id"]
                if abs(a["y"] - owner["y"]) > 0.01 or abs(b["y"] - owner["y"]) > 0.01:
                    problems.append(f"{tag}: camp {owner['id']} is at height {owner['y']:g}, the route is not")
        else:
            problems.append(f"{tag}: unknown via '{via}'")
    if seen_camps != order:
        problems.append(f"the route passes the camps as {seen_camps}, the layout lists {order}")
    for cid in order:
        if cid not in camps:
            problems.append(f"camp {cid} is not on the route")
    facts = {"legs": legs, "length": sum(l["length"] for l in legs),
             "walked": sum(l["length"] for l in legs if l["via"] != "camp"), "camps": seen_camps}
    return problems, facts


def route_height_near(layout, x, z):
    """The height of the route at its point nearest to (x, z), seen from above."""
    best, height = math.inf, None
    route = layout["route"]
    for index in range(1, len(route)):
        a, b = route[index - 1], route[index]
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        steps = max(int(run / SAMPLE), 1)
        for k in range(steps + 1):
            f = k / steps
            px, pz = a["x"] + (b["x"] - a["x"]) * f, a["z"] + (b["z"] - a["z"]) * f
            d = math.hypot(px - x, pz - z)
            if d < best:
                best, height = d, a["y"] + (b["y"] - a["y"]) * f
    return height, best


# ---------------------------------------------------------------------------------------------
# The gates of one level layout
# ---------------------------------------------------------------------------------------------


def camp_axis(camp):
    """The axis the route crosses a camp on, from its entry gate's side: 'x' or 'z'."""
    gates = camp.get("gates") or []
    if gates:
        return "x" if gates[0]["side"] in ("west", "east") else "z"
    dx, dz = abs(camp["exit"]["x"] - camp["entry"]["x"]), abs(camp["exit"]["z"] - camp["entry"]["z"])
    return "x" if dx >= dz else "z"


def check_layout(name, layout, ctx, expect):
    """Every gate of a level layout with camps. `expect(ok, text)` records one line."""
    levels, move, looks = ctx["levels"], ctx["move"], ctx["looks"]
    thickness = levels["fenceThickness"]
    spec = EXPECTED.get(name, {})
    solids = solids_of(layout, thickness)
    jump = jump_facts(move)
    tag = f"{name}:"

    unknown = sorted({b["look"] for b in layout["blocks"] if b["look"] not in looks})
    expect(not unknown, f"{tag} every block's look is in Expeditions.json looks"
           + (f" (unknown: {', '.join(unknown)})" if unknown else f" ({len(layout['blocks'])} blocks)"))
    odd = named_materials(layout) - {look["material"] for look in looks.values()}
    expect(not odd, f"{tag} every material a camp's floor, fence or obstacle names is one the looks use"
           + (f" (unknown: {', '.join(sorted(odd))})" if odd else f" ({', '.join(sorted(named_materials(layout))) or 'none named'})"))

    # Camp floors.
    for cid, (sx, sz) in (spec.get("camps") or {}).items():
        camp = next((c for c in layout["camps"] if c["id"] == cid), None)
        tol = spec["campTolerance"]
        ok = camp is not None and abs(camp["sx"] / sx - 1) <= tol + EPS and abs(camp["sz"] / sz - 1) <= tol + EPS
        expect(ok, f"{tag} camp {cid} is about {sx} x {sz} (+-{tol:.0%}): "
               + (f"{camp['sx']:g} x {camp['sz']:g}" if camp else "missing"))
    if spec.get("camps"):
        extra = [c["id"] for c in layout["camps"] if c["id"] not in spec["camps"]]
        expect(not extra, f"{tag} no camp beyond {', '.join(spec['camps'])}" + (f" (found {extra})" if extra else ""))

    # The route.
    problems, facts = walk_route(layout, solids, move)
    climbs = [l for l in facts["legs"] if l["via"] == "climb"]
    gaps = [l for l in facts["legs"] if l["via"] == "gap"]
    walked = [l for l in facts["legs"] if l["via"] == "walk"]
    widths = [l["width"] for l in walked if l.get("width", math.inf) < math.inf]
    expect(not problems, f"{tag} the route is continuous: every walked leg stays on the blocks and steps up at most "
           f"{WALK_RISE:g} stud" + (": " + "; ".join(problems[:6]) if problems
                                    else f" ({len(walked)} walked legs, {facts['walked']:.0f} studs outside the camps)"))
    if "routeStuds" in spec:
        lo, hi = spec["routeStuds"]
        expect(lo <= facts["length"] <= hi, f"{tag} the route is {lo}-{hi} studs long: {facts['length']:.0f}")
    expect(bool(widths) and min(widths) >= ROAD_MIN_WIDTH - EPS,
           f"{tag} the road under every walked leg is at least {ROAD_MIN_WIDTH:g} studs wide: narrowest "
           + (f"{min(widths):g}" if widths else "none"))
    expect(len(climbs) >= spec.get("climbs", 0) and all(WALK_RISE < l["rise"] <= jump["climb"] + EPS for l in climbs),
           f"{tag} at least {spec.get('climbs', 0)} climb, each at most {jump['climb']} studs "
           f"({CLIMB_SHARE:g} x jumpHeight {move['jumpHeight']:g}): "
           + (", ".join(f"{l['rise']:g}" for l in climbs) or "none"))
    expect(len(gaps) >= spec.get("gaps", 0)
           and all(max(l.get("hole", 0), l["length"]) <= jump["gap"] + EPS and l["rise"] <= EPS for l in gaps),
           f"{tag} at least {spec.get('gaps', 0)} gap, each at most {jump['gap']} studs across "
           f"({GAP_SHARE:g} x one jump's {jump['reach']:.1f}) and landing no higher: "
           + (", ".join(f"{l.get('hole', 0):g} (lands {l['rise']:+g})" for l in gaps) or "none"))

    # Each camp.
    barrier = layout.get("barrier") or {}
    expect(barrier.get("height") == BARRIER["height"] and barrier.get("thickness") == BARRIER["thickness"],
           f"{tag} the barrier is {BARRIER['height']:g} high and {BARRIER['thickness']:g} thick: {barrier or 'none'}")
    for camp in layout["camps"]:
        cid = camp["id"]
        x0, x1, z0, z1 = camp_rect(camp)
        gates = camp.get("gates") or []
        fence = camp.get("fence")
        entry, leave = camp["entry"], camp["exit"]
        expect(bool(fence) and fence["height"] > 0, f"{tag} camp {cid} has a fence"
               + (f" ({fence['height']:g} high)" if fence else ""))
        wide = len(gates) == 2 and all(g["width"] >= GATE_MIN_WIDTH - EPS and g["side"] in SIDES for g in gates)
        expect(wide, f"{tag} camp {cid} has two gates (entry, exit) at least {GATE_MIN_WIDTH:g} wide: "
               + ", ".join(f"{g['side']} {g['width']:g}" for g in gates))
        # The gates stand where the route crosses the fence, and their openings hold the road.
        if len(gates) == 2:
            for gate, point, word in ((gates[0], entry, "entry"), (gates[1], leave, "exit")):
                gx0, gx1, gz0, gz1 = gate_rect(camp, gate, thickness)
                if gate["side"] in ("west", "east"):
                    lined = gz0 - EPS <= point["z"] <= gz1 + EPS
                    near = abs(point["x"] - (x0 if gate["side"] == "west" else x1))
                    fits = gz0 >= z0 - EPS and gz1 <= z1 + EPS
                else:
                    lined = gx0 - EPS <= point["x"] <= gx1 + EPS
                    near = abs(point["z"] - (z0 if gate["side"] == "north" else z1))
                    fits = gx0 >= x0 - EPS and gx1 <= x1 + EPS
                expect(lined and fits and near <= levels["triggerInset"] + 8,
                       f"{tag} camp {cid}: the {word} point stands {near:g} studs inside the {gate['side']} gate, in "
                       f"line with its opening")
            expect(gates[0]["side"] != gates[1]["side"], f"{tag} camp {cid}: entry and exit are on different sides")
        inside = all(x0 + 1 <= p["x"] <= x1 - 1 and z0 + 1 <= p["z"] <= z1 - 1 for p in (entry, leave))
        expect(inside, f"{tag} camp {cid}: the entry and exit points are on its floor")
        # At "close" a fighter outside the floor inset by levels.closeInset is put on the entry
        # point, so that point must itself be inside that rectangle. StageFlow.Plan refuses the
        # level otherwise (the start answers "unavailable"), so this gate is strict: a stud to
        # spare.
        keep = (levels.get("closeInset") or 0) + CLOSE_SPARE
        depth_in = min(entry["x"] - x0, x1 - entry["x"], entry["z"] - z0, z1 - entry["z"])
        expect(depth_in >= keep - EPS, f"{tag} camp {cid}: the entry point is {depth_in:g} studs inside the floor, "
               f"clear of the close rule's inset ({levels.get('closeInset')}) with {CLOSE_SPARE:g} to spare")
        spawns = camp.get("spawns") or []
        radius = ctx["campRadius"].get((name, cid), ctx["widest"])
        on_floor = [p for p in spawns if x0 + radius <= p["x"] <= x1 - radius and z0 + radius <= p["z"] <= z1 - radius]
        far = [p for p in spawns if math.hypot(p["x"] - entry["x"], p["z"] - entry["z"]) >= SPAWN_ENTRY_MIN - EPS]
        nearest = min((math.hypot(p["x"] - entry["x"], p["z"] - entry["z"]) for p in spawns), default=0.0)
        expect(len(spawns) >= SPAWNS_MIN and len(on_floor) == len(spawns) and len(far) == len(spawns),
               f"{tag} camp {cid}: {len(spawns)} spawn points (needs {SPAWNS_MIN}), all on the floor less a body's "
               f"{radius:g} studs, the nearest {nearest:.0f} studs from the entry (needs {SPAWN_ENTRY_MIN:g})")
        mark = camp.get("checkpoint")
        expect(mark is not None and x0 <= mark["x"] <= x1 and z0 <= mark["z"] <= z1,
               f"{tag} camp {cid} has a checkpoint on its floor")
        # Flat: nothing but its own obstacles rises from the floor, and they stand on it.
        bumps = [s.name for s in solids if s.kind in ("block", "secret") and s.top > camp["y"] + EPS
                 and s.bottom < camp["y"] + (barrier.get("height") or 0)
                 and s.x1 > x0 + EPS and s.x0 < x1 - EPS and s.z1 > z0 + EPS and s.z0 < z1 - EPS]
        stray = [i + 1 for i, o in enumerate(camp.get("obstacles") or [])
                 if o["x"] - o["sx"] / 2 < x0 - EPS or o["x"] + o["sx"] / 2 > x1 + EPS
                 or o["z"] - o["sz"] / 2 < z0 - EPS or o["z"] + o["sz"] / 2 > z1 + EPS]
        expect(not bumps and not stray, f"{tag} camp {cid} is flat at height {camp['y']:g}: no block rises through "
               f"its floor and its obstacles stand on it" + (f" ({bumps or stray})" if bumps or stray else ""))
        # Within the wire's reach of the world origin, barrier included.
        reach = thickness + (barrier.get("thickness") or 0)
        furthest = max(abs(x0 - reach), abs(x1 + reach), abs(z0 - reach), abs(z1 + reach), abs(camp["y"]))
        expect(furthest <= ORIGIN_LIMIT, f"{tag} camp {cid} lies within {ORIGIN_LIMIT:g} studs of the world origin on "
               f"each axis: furthest {furthest:g}")
        # Nothing beside it: along the axis the route crosses it on, the only thing in its span is itself.
        axis = camp_axis(camp)
        lo, hi = (x0 - thickness, x1 + thickness) if axis == "x" else (z0 - thickness, z1 + thickness)
        drop = camp["y"] + (fence["height"] if fence else 0) - layout["killY"]
        clear = stray_reach(move, 0)
        beside = []
        for s in solids:
            if s.name.startswith(f"Camp_{cid}_"):
                continue
            a0, a1 = (s.x0, s.x1) if axis == "x" else (s.z0, s.z1)
            b0, b1 = (s.z0, s.z1) if axis == "x" else (s.x0, s.x1)
            c0, c1 = (z0, z1) if axis == "x" else (x0, x1)
            overlaps_span = a1 > lo + EPS and a0 < hi - EPS
            off_floor = b1 > c1 + EPS or b0 < c0 - EPS
            if overlaps_span and off_floor:
                beside.append(s.name)
        expect(not beside, f"{tag} camp {cid}: nothing stands beside it between its entry and its exit"
               + (f" (found {', '.join(beside)})" if beside else
                  f" (a jump, a double jump and a dash carry {clear:.0f} studs; a fall from its fence to killY is "
                  f"{drop:g} studs)"))
        # The invisible wall. At "close" it is solid, barrier.thickness deep outside the fence
        # line on all four sides, gate gaps included. Nothing a player should stand on may sit
        # in that band: only the road that leads through one of the camp's own gates crosses it.
        depth = barrier.get("thickness") or 0
        in_band = []
        for s in solids:
            if s.name.startswith(f"Camp_{cid}_") or s.kind not in ("block", "secret"):
                continue
            if s.top <= camp["y"] - BODY_HEIGHT or s.bottom >= camp["y"] + (barrier.get("height") or 0):
                continue
            ix0, ix1 = max(s.x0, x0 - reach), min(s.x1, x1 + reach)
            iz0, iz1 = max(s.z0, z0 - reach), min(s.z1, z1 + reach)
            if ix1 - ix0 <= EPS or iz1 - iz0 <= EPS:
                continue  # clear of the wall's outer face
            if ix0 >= x0 - thickness - EPS and ix1 <= x1 + thickness + EPS and iz0 >= z0 - thickness - EPS \
                    and iz1 <= z1 + thickness + EPS:
                continue  # inside the fence line: not in the band
            through = False
            if s.kind == "block" and s.look == "path":
                for gate in gates:
                    gx0, gx1, gz0, gz1 = gate_rect(camp, gate, thickness)
                    if gate["side"] == "west":
                        through = ix1 <= x0 + EPS and iz0 >= gz0 - EPS and iz1 <= gz1 + EPS
                    elif gate["side"] == "east":
                        through = ix0 >= x1 - EPS and iz0 >= gz0 - EPS and iz1 <= gz1 + EPS
                    elif gate["side"] == "north":
                        through = iz1 <= z0 + EPS and ix0 >= gx0 - EPS and ix1 <= gx1 + EPS
                    else:
                        through = iz0 >= z1 - EPS and ix0 >= gx0 - EPS and ix1 <= gx1 + EPS
                    if through:
                        break
            if not through:
                in_band.append(s.name)
        expect(not in_band, f"{tag} camp {cid}: nothing a player stands on sits in its invisible wall's band "
               f"({depth:g} studs outside the fence line, gate gaps included), but the road through its gates"
               + (f" (found {', '.join(in_band)})" if in_band else ""))

    # The start: on the ground, with room for a party.
    start = layout["start"]
    top, _s = ground(solids, start["x"], start["z"], start["y"] + EPS)
    room = levels["startSpacing"] * 2
    held = all(ground(solids, start["x"] + dx, start["z"] + dz, start["y"] + EPS)[0] is not None
               for dx in (-room, 0, room) for dz in (-room, 0, room))
    expect(top is not None and abs(top - start["y"]) < 0.01 and held,
           f"{tag} the start stands on the ground with {room:g} studs of floor round it for a party")

    # Secrets.
    wanted = spec.get("secrets")
    if wanted is not None:
        found = {s["id"]: s["needs"] for s in layout["secrets"]}
        expect(found == wanted, f"{tag} three secrets, {', '.join(f'{k} ({v})' for k, v in wanted.items())}: "
               + ", ".join(f"{k} ({v})" for k, v in found.items()))
    for secret in layout["secrets"]:
        word = NEED_WORDS.get(secret["needs"], "?")
        sign = secret.get("sign") or {}
        text = sign.get("text") or ""
        expect(word in text.upper(), f"{tag} the {secret['id']} sign names what it needs ({word}): \"{text}\"")
        # LevelService stands the sign on its point, so the point is the ground beside the road.
        road, away = route_height_near(layout, sign.get("x", 0), sign.get("z", 0))
        near = min((s.gap_to(Solid("sign", "sign", "sign", sign.get("x", 0), sign.get("x", 0), sign.get("z", 0),
                                   sign.get("z", 0), 0, 0)) for s in solids if s.kind == "block"
                    and abs(s.top - sign.get("y", 0)) < 0.01), default=math.inf)
        expect(near <= SIGN_REACH, f"{tag} the {secret['id']} sign stands at the height of a block within "
               f"{SIGN_REACH:g} studs of it ({near:.1f} away, {away:.0f} from the route)")
    lookout = next((s for s in layout["secrets"] if s["id"] == "lookout"), None)
    if lookout is not None:
        bottom = lookout["y"] - lookout["sy"] / 2
        ledge = next((s for s in solids if s.kind == "block" and abs(s.top - bottom) < 0.01
                      and s.holds(lookout["x"], lookout["z"])), None)
        if ledge is None:
            expect(False, f"{tag} the lookout stands on a ledge block")
        else:
            road, away = route_height_near(layout, lookout["x"], lookout["z"])
            rise = ledge.top - road
            lo = move["jumpHeight"] + LOOKOUT_OVER_JUMP
            hi = move["jumpHeight"] + move["doubleJumpHeight"] - LOOKOUT_UNDER_DOUBLE
            expect(lo <= rise <= hi, f"{tag} the lookout ledge's top is {lo:g}-{hi:g} studs above the road under it "
                   f"(over one jump's {move['jumpHeight']:g}, under jump + double jump's "
                   f"{move['jumpHeight'] + move['doubleJumpHeight']:g}): {rise:g}, {away:.0f} studs from the road")
            # No other surface gives a single jump (with a dash) the ledge.
            ways = []
            for s in solids:
                if s is ledge or s.name == "Secret_lookout":
                    continue
                need = ledge.top - s.top
                carry = reach_at_rise(move, need)
                if carry is None:
                    continue
                if s.gap_to(ledge) <= carry + move["dashDistance"] + EPS:
                    ways.append(f"{s.name} ({need:g} up, {s.gap_to(ledge):.0f} away)")
            expect(not ways, f"{tag} the lookout needs the double jump: no surface is within one jump and a dash of "
                   f"its ledge" + (f" (reachable from {', '.join(ways)})" if ways else ""))
    if spec.get("creek"):
        waters = [s for s in solids if s.look == "water"]
        loose = [b.get("name") for b in layout["blocks"] if b["look"] == "water" and b.get("collide") is False]
        crossings = []
        for water in waters:
            road, away = route_height_near(layout, (water.x0 + water.x1) / 2, (water.z0 + water.z1) / 2)
            crossings.append((water, road, away))
        crossed = [c for c in crossings if any(
            c[0].holds(a["x"] + (b["x"] - a["x"]) * k / 200, a["z"] + (b["z"] - a["z"]) * k / 200)
            for a, b in zip(layout["route"], layout["route"][1:]) for k in range(201))]
        level = {round(w.top, 3) for w in waters}
        good = bool(crossed) and not loose and len(level) == 1 and all(
            0 <= road - water.top <= CREEK_DROP + EPS for water, road, _a in crossed)
        expect(good, f"{tag} the creek is solid water the route crosses, its top at most {CREEK_DROP:g} stud under "
               f"the road: " + (", ".join(f"{w.name} {road - w.top:g} under" for w, road, _a in crossed) or "not crossed")
               + (f"; {len(waters)} water blocks at one height" if len(level) == 1 else "; water at several heights"))

    lowest = min(s.bottom for s in solids) if solids else 0.0
    expect(KILL_FLOOR < layout["killY"] <= lowest - KILL_MARGIN + EPS,
           f"{tag} killY {layout['killY']:g} is at least {KILL_MARGIN:g} under the lowest block ({lowest:g}) and above "
           f"{KILL_FLOOR:g}")
    parts = part_count(layout)
    expect(parts <= levels["maxParts"], f"{tag} {parts} Parts (levels.maxParts {levels['maxParts']})")
    return facts


def check_arena_layout(name, layout, ctx, expect):
    """A layout that names an arena (ruling 27): the gates that still apply to its one camp."""
    levels = ctx["levels"]
    camp = layout["camps"][0]
    x0, x1, z0, z1 = camp_rect(camp)
    barrier = layout.get("barrier") or {}
    reach = levels["fenceThickness"] + (barrier.get("thickness") or 0)
    expect(barrier.get("height") == BARRIER["height"] and barrier.get("thickness") == BARRIER["thickness"],
           f"{name}: the arena {layout['arena']} has the barrier ({BARRIER['height']:g} high, "
           f"{BARRIER['thickness']:g} thick)")
    expect(max(abs(x0 - reach), abs(x1 + reach), abs(z0 - reach), abs(z1 + reach)) <= ORIGIN_LIMIT,
           f"{name}: its camp lies within {ORIGIN_LIMIT:g} studs of the world origin")
    spawns = camp["spawns"]
    entry = camp["entry"]
    nearest = min(math.hypot(p["x"] - entry["x"], p["z"] - entry["z"]) for p in spawns)
    expect(len(spawns) >= SPAWNS_MIN and nearest >= SPAWN_ENTRY_MIN
           and all(x0 <= p["x"] <= x1 and z0 <= p["z"] <= z1 for p in spawns),
           f"{name}: {len(spawns)} spawn points on its floor, the nearest {nearest:.0f} studs from the entry")
    keep = (levels.get("closeInset") or 0) + CLOSE_SPARE
    depth_in = min(entry["x"] - x0, x1 - entry["x"], entry["z"] - z0, z1 - entry["z"])
    expect(depth_in >= keep, f"{name}: the entry point is {depth_in:g} studs inside the floor, clear of the close "
           f"rule's inset ({levels.get('closeInset')}) with {CLOSE_SPARE:g} to spare")
    expect(part_count(layout) <= levels["maxParts"],
           f"{name}: {part_count(layout)} Parts (levels.maxParts {levels['maxParts']})")


def check_lobby(name, layout, ctx, bounds_of, expect):
    levels = ctx["levels"]
    solids = solids_of(layout, levels["fenceThickness"])
    expect(not layout["camps"] and not layout["route"] and not layout["secrets"],
           f"{name}: the lobby has no camp, no route and no secret")
    floors = [s for s in solids if s.look == "lobby"]
    walls = [s for s in solids if s.look == "wall"]
    signs = [b for b in layout["blocks"] if b.get("text")]
    expect(bool(floors) and bool(walls) and any("MAP" in b["text"].upper() for b in signs),
           f"{name}: a floor of look `lobby`, a low wall and a sign that says MAP"
           + (f" (\"{signs[0]['text']}\")" if signs else ""))
    points = [layout["start"]] + (layout.get("spawns") or [])
    standing = [p for p in points if any(abs(f.top - p["y"]) < 0.01 and f.holds(p["x"], p["z"]) for f in floors)]
    expect(len(layout.get("spawns") or []) >= 4 and len(standing) == len(points),
           f"{name}: the start and {len(layout.get('spawns') or [])} spawn points (needs 4) stand on the floor")
    lowest = min(s.bottom for s in solids)
    expect(KILL_FLOOR < layout["killY"] <= lowest - KILL_MARGIN + EPS,
           f"{name}: killY {layout['killY']:g} is at least {KILL_MARGIN:g} under the lowest block ({lowest:g})")
    mine = layout_bounds(layout, levels["fenceThickness"])
    for other, theirs in bounds_of.items():
        if other == name or theirs is None:
            continue
        dx = max(mine[0] - theirs[1], theirs[0] - mine[1], 0.0)
        dz = max(mine[2] - theirs[3], theirs[2] - mine[3], 0.0)
        gap = math.hypot(dx, dz)
        expect(gap >= LOBBY_CLEARANCE, f"{name}: at least {LOBBY_CLEARANCE:g} studs from {other}'s bounds: {gap:.0f}")
    unknown = sorted({b["look"] for b in layout["blocks"] if b["look"] not in ctx["looks"]})
    expect(not unknown, f"{name}: every block's look is in Expeditions.json looks"
           + (f" (unknown: {', '.join(unknown)})" if unknown else ""))


# ---------------------------------------------------------------------------------------------
# The level files against their layouts, and the map
# ---------------------------------------------------------------------------------------------


def stage_kinds(stage):
    """Every kind a camp stage names, at any difficulty: [(kind, boss?)]."""
    found = []
    for wave in stage.get("waves") or []:
        for group in wave["groups"]:
            if (group["kind"], False) not in found:
                found.append((group["kind"], False))
        if wave.get("boss") and (wave["boss"]["kind"], True) not in found:
            found.append((wave["boss"]["kind"], True))
    return found


def check_level_file(level, layouts, ctx, expect):
    name = level["id"]
    layout = layouts.get(level["layout"])
    expect(layout is not None, f"{name}: its layout {level['layout']} exists")
    if layout is None:
        return
    kinds = ctx["kinds"]
    if level.get("mission"):
        expect(bool(layout.get("arena")), f"{name}: a level that names a mission ({level['mission']}) names an arena "
               f"layout ({layout.get('arena')})")
        return
    stages = level["stages"]
    turn = all(s["kind"] == ("camp" if (i % 2 == 1 or len(stages) == 1) else "travel") for i, s in enumerate(stages))
    expect((turn or all(s["kind"] == "camp" for s in stages[:1]) and len(stages) == 1) and stages[-1]["kind"] == "camp",
           f"{name}: its stages are travel and camp in turn and end in a camp: "
           + ", ".join(s["kind"] for s in stages))
    camps = {c["id"]: c for c in layout["camps"]}
    zones = [s.get("zone") for s in stages if s["kind"] == "camp"]
    expect(zones == [c["id"] for c in layout["camps"]],
           f"{name}: its camp stages name the layout's camps in the route's order: {', '.join(map(str, zones))}")
    cap = level.get("runCapSeconds") or 0
    expect(cap >= RUN_CAP_RATIO * level["targetMinutes"] * 60,
           f"{name}: runCapSeconds {cap:g} is at least {RUN_CAP_RATIO:g} x targetMinutes {level['targetMinutes']:g}")
    for stage in stages:
        if stage["kind"] != "camp" or stage.get("zone") not in camps:
            continue
        camp = camps[stage["zone"]]
        x0, x1, z0, z1 = camp_rect(camp)
        short = min(camp["sx"], camp["sz"])
        tag = f"{name} camp {camp['id']} ({stage['name']}):"
        named = stage_kinds(stage)
        missing = [k for k, _b in named if k not in kinds]
        expect(not missing, f"{tag} every kind is a crowd kind" + (f" (unknown {missing})" if missing else ""))
        tight = [f"{k} (bandMin {kinds[k]['bandMin']:g})" for k, _b in named
                 if k in kinds and kinds[k].get("brain") == "keepAway" and kinds[k].get("bandMin", 0) > BAND_SHARE * short]
        roomy = [f"{k} {kinds[k]['bandMin']:g}" for k, _b in named if k in kinds and kinds[k].get("brain") == "keepAway"]
        expect(not tight, f"{tag} every keepAway kind's bandMin is at most {BAND_SHARE:g} x its shorter side "
               f"({BAND_SHARE * short:.1f}): " + (", ".join(tight) + " do not fit" if tight else ", ".join(roomy) or "none"))
        alive = stage.get("maxAlive") or level["crowd"]["maxAlive"]
        area = camp["sx"] * camp["sz"]
        expect(alive <= area / DENSITY_AREA + EPS and alive <= ctx["crowdMaxAlive"],
               f"{tag} maxAlive {alive:g} is at most its floor area / {DENSITY_AREA:g} ({area / DENSITY_AREA:.1f}) and "
               f"the crowd's {ctx['crowdMaxAlive']}")
        widest = max((kinds[k]["radius"] for k, boss in named if k in kinds and not boss), default=ctx["widest"])
        ctx["campRadius"][(level["layout"], camp["id"])] = widest
        for wave in stage.get("waves") or []:
            boss = wave.get("boss")
            if not boss or boss["kind"] not in kinds:
                continue
            radius = kinds[boss["kind"]]["radius"]
            bx, bz = camp["x"] + boss["at"][0], camp["z"] + boss["at"][1]
            from_entry = math.hypot(bx - camp["entry"]["x"], bz - camp["entry"]["z"])
            expect(x0 + radius <= bx <= x1 - radius and z0 + radius <= bz <= z1 - radius
                   and from_entry >= ctx["spawnClear"],
                   f"{tag} the {boss['kind']} rises on the floor less its radius {radius:g}, {from_entry:.0f} studs "
                   f"from the entry (threat.spawnClear {ctx['spawnClear']:g})")


def three_positive(value):
    """Is `value` a list of exactly three positive numbers (a size in studs)?"""
    return (isinstance(value, list) and len(value) == 3
            and all(isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0 for v in value))


def check_map(expeditions, level_files, layouts, expect):
    nodes = expeditions["nodes"]
    ids = [n["id"] for n in nodes]
    difficulties = expeditions["difficulties"]
    expect(len(ids) == len(set(ids)), f"map: {len(ids)} nodes with ids of their own: {', '.join(ids)}")
    expect(len(difficulties) == 3 and all(d in expeditions["difficultyNames"] for d in difficulties),
           f"map: three difficulties, each with a name: {', '.join(difficulties)}")
    by_id = {level["id"]: level for level in level_files}
    bad = [n["id"] for n in nodes if n.get("level") and n["level"] not in by_id]
    expect(not bad, "map: every node with a `level` names a level file"
           + (f" (no file for {bad})" if bad else f" ({', '.join(n['id'] for n in nodes if n.get('level'))})"))
    loose = [n["id"] for n in nodes if (n.get("from") and n["from"] not in ids)
             or ((n.get("requires") or {}).get("node") and n["requires"]["node"] not in ids)]
    expect(not loose, "map: every `from` and `requires.node` names a node" + (f" ({loose})" if loose else ""))
    themed = [n["id"] for n in nodes if n["theme"] not in expeditions["themes"]]
    expect(not themed, "map: every node's theme has a colour" + (f" (missing for {themed})" if themed else ""))
    placed = all(0 <= n["x"] <= 1 and 0 <= n["y"] <= 1 for n in nodes)
    nearest = min((math.hypot(a["x"] - b["x"], a["y"] - b["y"]) for i, a in enumerate(nodes) for b in nodes[i + 1:]),
                  default=1.0)
    expect(placed and nearest >= 0.12, f"map: every node stands on the map (0..1), the two nearest {nearest:.2f} apart "
           f"(needs 0.12: a 48 px node on a 400 px map)")
    kinds = {n["kind"] for n in nodes}
    expect(kinds <= {"level", "bonus"}, f"map: node kinds are level or bonus: {', '.join(sorted(kinds))}")
    looks = expeditions["looks"]
    missing = [k for k in REQUIRED_LOOKS if k not in looks]
    expect(not missing, "map: the eleven looks are there" + (f" (missing {missing})" if missing else ""))
    spread = {k: max(v["color"]) - min(v["color"]) for k, v in looks.items()}
    greys = [k for k in REQUIRED_LOOKS if k in looks and k not in COLOUR_LOOKS and spread[k] > GREY_SPREAD]
    dull = [k for k in COLOUR_LOOKS if k in looks and spread[k] <= GREY_SPREAD * 2]
    expect(not greys and not dull, "map: the looks are greys, except gate, checkpoint, checkpointDone and secret, "
           "each a colour" + (f" (not grey: {greys}; not a colour: {dull})" if greys or dull else ""))
    lobby = (expeditions.get("lobby") or {}).get("layout")
    expect(lobby in layouts, f"map: the lobby's layout {lobby} exists")
    alien = sorted(f"{k} ({v.get('material')})" for k, v in looks.items() if v.get("material") not in ENGINE_MATERIALS)
    expect(not alien, "map: every look's material is one of the engine's" + (f" (not: {', '.join(alien)})" if alien else
                                                                              f" ({', '.join(sorted({v['material'] for v in looks.values()}))})"))
    sign = expeditions.get("sign") or {}
    expect(len(sign.get("textColor") or []) == 3 and (sign.get("pixelsPerStud") or 0) > 0,
           "map: the signs have a text colour and a pixel density")
    expect(three_positive(sign.get("size")),
           f"map: sign.size is three positive numbers (a secret's sign block): {sign.get('size')}")


# ---------------------------------------------------------------------------------------------
# The pictures
# ---------------------------------------------------------------------------------------------

LOOK_CHARS = {"path": "=", "ground": "%", "water": "~", "lobby": ":", "wall": "#", "sign": "i"}
LEGEND = ("= road   % ledge or ground   ~ water   . camp floor   # fence or wall   | gate   x spawn point   "
          "o obstacle   c checkpoint   ? secret site   i sign   S start   B boss   A B C the camp's middle")


def overlap(a0, a1, b0, b1):
    return max(min(a1, b1) - max(a0, b0), 0.0)


def plan_lines(layout, level, ctx, scale_x, scale_z):
    """The level from above, one character per scale_x x scale_z studs, north at the top."""
    thickness = ctx["levels"]["fenceThickness"]
    bounds = layout_bounds({**layout, "barrier": None}, thickness)
    if bounds is None:
        return ["(empty)"]
    x_lo = math.floor(bounds[0] / scale_x) * scale_x
    z_lo = math.floor(bounds[2] / scale_z) * scale_z
    cols = int(math.ceil((bounds[1] - x_lo) / scale_x))
    rows = int(math.ceil((bounds[3] - z_lo) / scale_z))
    grid = [[" "] * cols for _ in range(rows)]

    def cells(x0, x1, z0, z1):
        for r in range(max(int((z0 - z_lo) // scale_z), 0), min(int((z1 - z_lo - EPS) // scale_z) + 1, rows)):
            for c in range(max(int((x0 - x_lo) // scale_x), 0), min(int((x1 - x_lo - EPS) // scale_x) + 1, cols)):
                cx0, cz0 = x_lo + c * scale_x, z_lo + r * scale_z
                share = overlap(x0, x1, cx0, cx0 + scale_x) * overlap(z0, z1, cz0, cz0 + scale_z) / (scale_x * scale_z)
                yield r, c, share

    def paint(char, x0, x1, z0, z1, least=0.25):
        for r, c, share in cells(x0, x1, z0, z1):
            if share >= least:
                grid[r][c] = char

    def dot(char, x, z):
        r, c = int((z - z_lo) // scale_z), int((x - x_lo) // scale_x)
        if 0 <= r < rows and 0 <= c < cols:
            grid[r][c] = char

    # Low things first, so what stands on them shows.
    for block in sorted(layout["blocks"], key=lambda b: b["y"] + b["sy"] / 2):
        s = block_solid(block)
        thin = min(s.x1 - s.x0, s.z1 - s.z0) < min(scale_x, scale_z)
        paint(LOOK_CHARS.get(block["look"], "+"), s.x0, s.x1, s.z0, s.z1, 0.0 if thin else 0.25)
    for camp in layout["camps"]:
        x0, x1, z0, z1 = camp_rect(camp)
        paint(".", x0, x1, z0, z1)
        for o in camp.get("obstacles") or []:
            paint("o", o["x"] - o["sx"] / 2, o["x"] + o["sx"] / 2, o["z"] - o["sz"] / 2, o["z"] + o["sz"] / 2, 0.15)
        if camp.get("fence"):
            for fx0, fx1, fz0, fz1 in fence_strips(camp, thickness).values():
                paint("#", fx0, fx1, fz0, fz1, 0.0)
        for gate in camp.get("gates") or []:
            gx0, gx1, gz0, gz1 = gate_rect(camp, gate, thickness)
            paint("|" if gate["side"] in ("west", "east") else "-", gx0, gx1, gz0, gz1, 0.0)
    for secret in layout["secrets"]:
        paint("?", secret["x"] - secret["sx"] / 2, secret["x"] + secret["sx"] / 2, secret["z"] - secret["sz"] / 2,
              secret["z"] + secret["sz"] / 2, 0.0)
        if secret.get("sign"):
            dot("i", secret["sign"]["x"], secret["sign"]["z"])
    for camp in layout["camps"]:
        for p in camp.get("spawns") or []:
            dot("x", p["x"], p["z"])
        if camp.get("checkpoint"):
            dot("c", camp["checkpoint"]["x"], camp["checkpoint"]["z"])
        dot(camp["id"][:1], camp["x"], camp["z"])
    if level is not None:
        camps = {c["id"]: c for c in layout["camps"]}
        for stage in level.get("stages") or []:
            camp = camps.get(stage.get("zone"))
            for wave in (stage.get("waves") or []) if camp else []:
                if wave.get("boss"):
                    dot("B", camp["x"] + wave["boss"]["at"][0], camp["z"] + wave["boss"]["at"][1])
    for p in layout.get("spawns") or []:
        dot("x", p["x"], p["z"])
    dot("S", layout["start"]["x"], layout["start"]["z"])
    ruler = "".join(f"{x_lo + c * scale_x:<{10}g}" if c % 10 == 0 else "" for c in range(cols))
    lines = [f"  x {ruler[:cols]}"]
    for r in range(rows):
        lines.append(f"{z_lo + r * scale_z:>4g} " + "".join(grid[r]).rstrip())
    return lines


def profile_lines(layout, solids, step=4.0, rise=4.0):
    """The route from the side: one column per `step` studs walked, one row per `rise` studs."""
    route = layout["route"]
    if len(route) < 2:
        return []
    heights, marks = [], []
    for a, b in zip(route, route[1:]):
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        via = b.get("via")
        count = max(int(round(run / step)), 1)
        for k in range(count):
            f = (k + 0.5) / count
            x, z = a["x"] + (b["x"] - a["x"]) * f, a["z"] + (b["z"] - a["z"]) * f
            top, _s = ground(solids, x, z, max(a["y"], b["y"]) + WALK_RISE)
            heights.append(top)
            marks.append("_" if via == "gap" else "^" if via == "climb" else "." if via == "camp" else "=")
    known = [h for h in heights if h is not None]
    low, high = min(known), max(known)
    lines = []
    level = math.ceil(high / rise) * rise
    while level >= math.floor(low / rise) * rise:
        row = "".join(" " if h is None or h < level - EPS else ("#" if h >= level + rise - EPS else m)
                      for h, m in zip(heights, marks))
        lines.append(f"{level:>4g} {row.rstrip()}")
        level -= rise
    return lines


# ---------------------------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------------------------


def load_all():
    combat = sr.load_config(sr.COMBAT_PATH)
    proving = sr.load_config(sr.CONFIG_PATH)
    expeditions = sr.load_config(sr.EXPEDITIONS_PATH)
    kinds = proving["crowd"]["kinds"]
    names = sorted(p.stem for p in sr.LEVEL_LAYOUT_DIR.glob("*.json"))
    layouts = {name: sr.load_level_layout(name, combat["player"]["rescue"]["below"]) for name in names}
    ctx = {"levels": combat["levels"], "move": proving["movement"], "looks": expeditions["looks"], "kinds": kinds,
           "widest": max(k["radius"] for k in kinds.values() if k.get("brain") and not k.get("boss")),
           "spawnClear": proving["crowd"]["threat"]["spawnClear"], "crowdMaxAlive": proving["crowd"]["maxAlive"],
           "campRadius": {}}
    return combat, expeditions, layouts, sr.load_level_files(), ctx


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-plan", action="store_true", help="the gates only")
    parser.add_argument("--plan-only", action="store_true", help="the plans only")
    parser.add_argument("--scale", type=float, nargs=2, default=(4.0, 8.0), metavar=("X", "Z"),
                        help="studs per character across and down (default 4 8)")
    args = parser.parse_args()
    combat, expeditions, layouts, level_files, ctx = load_all()
    lobby_name = (expeditions.get("lobby") or {}).get("layout")
    by_layout = {level["layout"]: level for level in level_files}
    failures = []

    def expect(ok, text):
        print(f"  {'PASS' if ok else 'FAIL'}  {text}")
        if not ok:
            failures.append(text)

    facts = {}
    if not args.plan_only:
        move = ctx["move"]
        jump = jump_facts(move)
        print("check_levels (docs/INTERFACES.md \"L1 contracts\" -> \"Config\")")
        print(f"  one jump: {move['jumpHeight']:g} studs high, {jump['air']:.3f} s in the air, {jump['reach']:.1f} studs "
              f"at walk speed {move['walkSpeed']:g}; a climb may rise {jump['climb']}, a gap may span {jump['gap']}; "
              f"jump + double jump {move['jumpHeight'] + move['doubleJumpHeight']:g}")
        print()
        check_map(expeditions, level_files, layouts, expect)
        size = ctx["levels"].get("checkpointSize")
        expect(three_positive(size),
               f"Combat.json levels.checkpointSize is three positive numbers (the checkpoint marker): {size}")
        close_inset, trigger_inset = ctx["levels"].get("closeInset"), ctx["levels"]["triggerInset"]
        expect(isinstance(close_inset, (int, float)) and 0 <= close_inset <= trigger_inset,
               f"Combat.json levels.closeInset {close_inset} is at most triggerInset {trigger_inset}: whoever "
               f"triggered a camp is inside the rectangle its close keeps")
        expect(ctx["levels"]["gateSeconds"] >= 1, f"Combat.json levels.gateSeconds {ctx['levels']['gateSeconds']:g} "
               f"is at least 1 (the client learns the floor that long before the first body)")
        # The level files first: they say which kinds stand in which camp.
        for level in level_files:
            check_level_file(level, layouts, ctx, expect)
        bounds_of = {name: layout_bounds(layout, ctx["levels"]["fenceThickness"]) for name, layout in layouts.items()}
        for name, layout in layouts.items():
            if name == lobby_name:
                check_lobby(name, layout, ctx, bounds_of, expect)
            elif layout.get("arena"):
                check_arena_layout(name, layout, ctx, expect)
            else:
                facts[name] = check_layout(name, layout, ctx, expect)
        orphan = [name for name in layouts if name != lobby_name and name not in by_layout]
        expect(not orphan, "every layout but the lobby's belongs to a level file" + (f" ({orphan})" if orphan else ""))
    if not args.no_plan:
        scale_x, scale_z = args.scale
        for name, layout in layouts.items():
            if layout.get("arena"):
                continue
            solids = solids_of(layout, ctx["levels"]["fenceThickness"])
            print()
            print(f"PLAN of {name}, from above (north at the top; one character = {scale_x:g} studs across, "
                  f"{scale_z:g} down; z at the left)")
            for line in plan_lines(layout, by_layout.get(name), ctx, scale_x, scale_z):
                print(line)
            side = profile_lines(layout, solids)
            if side:
                print()
                print(f"SIDE VIEW of {name}'s route (one column = 4 studs walked, one row = 4 studs of height; "
                      f"= walked, _ the gap, ^ a climb, . inside a camp)")
                for line in side:
                    print(line)
                if name in facts:
                    legs = facts[name]["legs"]
                    print("  legs: " + "; ".join(
                        f"{l['via']} {l['length']:.0f}" + (f" ({l['camp']})" if l.get("camp") else "")
                        + (f" (+{l['rise']:g})" if l["via"] == "climb" else "") for l in legs))
        print()
        print("  " + LEGEND)
        # A note for L2, not a gate (INTERFACES "Open for later steps").
        ability = combat and sr.load_config(sr.CONFIG_PATH)["weapons"].get("greataxe", {}).get("ability") or {}
        if ability.get("height"):
            move = ctx["move"]
            print(f"  note for L2: Leap Smash rises {ability['height']:g} studs, so one jump and a Leap Smash reach "
                  f"{move['jumpHeight'] + ability['height']:g}: a ledge under that is open without the double jump.")
    if not args.plan_only:
        print()
        print(f"CHECK: {'PASS' if not failures else 'FAIL (' + str(len(failures)) + ')'}")
        sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
