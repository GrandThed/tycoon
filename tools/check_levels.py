#!/usr/bin/env python
"""Level layout and map gates for Era City Tycoon's Expeditions (L1, "Forest Road in grey"; L1b
Wave 1, "the camp is alive": only a camp that locks has gates and a wall, residents, checkpoints
off the open camps' floors and out of every resting member's sight; L1b Wave 2, "the long road":
the winding road's sizes, tents and their rings, the sneak path, post spacing, the population
rule with tents and the boss reserve, dormancy and the join-in's chain table).

L1b Wave 4, "no waits, no walls": the chase regions (their data, standable cells, doors and tree,
fences crossed only at gates, the lock clearance), camps.meleeAbove's range, the sniper perches,
N's approaches and the tents' pace keys.

L2 Wave 1, "the bought double jump and the lookout": Expeditions.json `abilities` and the price of
Double Jump, SecretFlow's trigger numbers and the Studio levers, and "a secret is out of reach
without its key, within reach with it" (L2-18): the owner's band, one jump with a dash, every
lifting ability's arc worst case (LIFT_MODEL), the trigger met only on the ledge, and rewards only
behind a sold key.

A level is built in Studio from `src/shared/Layouts/Levels/<Name>.json`, and nobody sees it there
before the owner does. This tool proves the layout on paper instead: it walks the level's `route`
over the layout's boxes the way a player with one jump would, checks every gate of the constraint
table in docs/INTERFACES.md "L1 contracts" -> "Config", and prints a top-down plan and a side
view of each level in plain characters.

What it reads, and copies no number from:
  Config/Combat.json          levels.* (fence and floor thickness, the trigger's and the close's
                              numbers, the crowd ceiling, Part budget), player.rescue, the gear
                              presets
  Config/ProvingGrounds.json  movement.* (jump, double jump, walk, dash), the crowd kinds' radii,
                              keepAway bands and ground attacks' heights, threat.spawnClear,
                              crowd.maxAlive
  Config/Expeditions.json     the map's nodes, themes, looks and abilities
  Config/Levels/*.json        each level's stages (which kinds stand in which camp, the boss spot)
  Layouts/Levels/*.json       the layouts; a file that names an `arena` is read through
                              sim_range.arena_as_layout, the mirror of LevelGeometry.FromArena

Geometry rules, as LevelService builds them: a camp's fence stands OUTSIDE its floor rectangle,
`levels.fenceThickness` thick, so a road runs up to the floor's edge and passes under the gate.
The invisible wall's inner face is the floor's edge (fix round, ruling 2): it is
`barrier.thickness` deep outward from there (never thinner than the fence), so in a closed camp
nobody stands on a fence. A camp triggers on its whole fenced rectangle (ruling 1): the floor
grown by the fence's thickness. A camp's floor is `levels.floorThickness` deep under its top.

The route. `route[i].via` says how the leg that ENDS at point i is travelled: absent = walked,
"climb" = one jump up onto a ledge, "gap" = one jump across a hole, "camp" = through a camp from
its entry point to its exit point. The y of a route point is the height of the ground there.

Importable with no side effect: tools/crowd_harness/run_harness.py asks `load_all` and
`part_count` for this tool's reading of the layouts, and tools/check_stage_mirror.py for the
level files in Catalog's order.

Usage:
  py tools/check_levels.py                # the gates and the plans; exit 1 when a gate fails
  py tools/check_levels.py --no-plan      # the gates only
  py tools/check_levels.py --plan-only    # the plans only
  py tools/check_levels.py --scale 4 8    # studs per character across and down (default 4 8)

Every rule L1c and its fix round added, and every rule of L2 Wave 1, is shown red on a mutated copy
by tools/check_levels_mutants.py (run_gates below is what it calls).
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
        # L1b Wave 2 (INTERFACES "Wave 2 — the long road", the gates table): the winding road.
        "camps": {"A": (85, 85), "B": (141, 133), "C": (115, 115)},
        "campTolerance": 0.10,
        "routeStuds": (900, 1100),
        "secrets": {"lookout": "doubleJump", "cache": "fire", "shrine": "ice"},
        "climbs": 1,
        "gaps": 1,
        "creek": True,
        # The camps that lock, residents per camp at the highest difficulty (C: at least 4 and
        # under its stage's maxAlive), and a sneak path past the open camps (L1b-W2-3).
        "locks": ["C"],
        "residents": {"A": (30, 36), "B": (40, 50)},
        # L1c-4: the boss room's ambush per difficulty (8 to 10 on Normal by Ben's word, 12 on Hard
        # and Brutal), under its stage's maxAlive. A difficulty this lacks is held to nothing.
        "lockedResidents": {"normal": (8, 10), "hard": (8, 12), "brutal": (8, 12)},
        # L1c-3: the camps that are walled: nothing inside is seen from outside before the close.
        "walled": ["C"],
        "sneak": True,
        # L1b Wave 4: one chase region on the plateau (ruling 1), an approach before each open camp.
        "regions": 1,
        "approaches": 2,
        # The fix round's R8: the spots no rusher reaches within the Longbow's range of the region.
        # L1c: the gatehouse's two floors are new tops by the region (sim_range rates them).
        "sniperSpots": ["Creek", "GatehouseTurn", "GatehouseWalk", "LookoutLedge", "LookoutSignPad", "Road2", "Road3",
                        "Road4", "RoadBC5", "RoadBC6", "Secret_cache", "Secret_lookout", "ShrineSignPad"],
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
ENTRY_GATE_REACH = 12.0  # a camp's entry and exit points stand at most this far inside their gates
BARRIER = {"height": 80.0, "thickness": 8.0}
ORIGIN_LIMIT = 1000.0  # the wire carries +-1,024 studs round the world origin (ruling 12)
# A body steps up about 2 studs onto a ledge and the air dash holds its altitude, so a jump that
# ends this far under a ledge still gets on it: every "needs the double jump" test allows it.
STEP_UP = 3.0
# The lookout's ledge is over one jump and that step up, and at least this far under jump +
# double jump.
LOOKOUT_UNDER_DOUBLE = 4.0
CREEK_DROP = 1.0
# killY: a fall is short. At least KILL_UNDER[0] under every standable surface (a body on the
# lowest ground is never "fallen"), at most KILL_UNDER[1] under the lowest one (about 12), and
# under every Part's bottom.
KILL_UNDER = (8.0, 16.0)
KILL_FLOOR = -450.0
# Cover (fix round, ruling 3): a standable top inside a camp is at most COVER_MAX studs over its
# floor, and at least COVER_MARGIN under the lowest ground attack that camp fields (ThreatField:
# a shape with a `height` misses feet more than that far above the floor).
COVER_MAX = 3.5
COVER_MARGIN = 0.5
GROUND_LOOKS = ("ground", "path", "lobby", "water")  # blocks a body lands on
LOBBY_CLEARANCE = 150.0
DENSITY_AREA = 200.0  # a camp's maxAlive is at most its floor area over this (the arena: 60 on 110 x 110)
BAND_SHARE = 0.45  # a keepAway kind's bandMin is at most this share of the camp's shorter side
RUN_CAP_RATIO = 2.0
REQUIRED_LOOKS = ("ground", "path", "campFloor", "wall", "gate", "checkpoint", "checkpointDone", "secret",
                  "secretOpen", "sign", "water", "lobby", "fire", "tent")
# Each must read at a glance (secretOpen, L2-14: a chest the player has found, tinted gold).
COLOUR_LOOKS = ("gate", "checkpoint", "checkpointDone", "secret", "secretOpen", "fire", "tent")
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
# The `levels` numbers of L1b, held by their own gate in check_rules.
L1B_RULES = ("checkpointReach", "walletSendSeconds", "regionLockMargin", "doorSpare")
REGION_LOCK_MARGIN = 8.0  # L1b-W4-16 (ruling 1), fixed: Combat.json levels.regionLockMargin
DOOR_SPARE = 0.5  # L1b-W4-15, fixed: Combat.json levels.doorSpare
CELL_STEP = 2.0  # L1b-W4-15: a cell is proved standable on this grid and at its corners
PERCH_STEP = 1.0  # a perch's top is sampled this often for its distance to the region
# L1b Wave 4 fix round (docs/prompts/l1b-w4-fix-round.md).
# R6: VitalsService's and ThreatField's height rule gives every ground shape an under side. The
# cliff gate reads the rule from here; set it False to see the gate fail on the shipped layout.
UNDER_SIDE = True
SPOT_STEP = 1.0  # R8: a standable top is sampled this often for the unreachable sniper spots
# The `levels` numbers this tool itself reads to measure a layout.
READ_RULES = ("fenceThickness", "floorThickness", "triggerHeight", "crowdCeiling", "startSpacing", "maxParts")
GEAR_PRESETS = ((2, 2), (4, 4), (6, 6))  # L1b-W2-20: the Studio gear presets (melee, ranged)
# L1b Wave 1 (docs/INTERFACES.md "L1b contracts" -> "Config", the gates table).
POST_SPARE = 1.0  # a post stands its group's widest radius and this much inside its floor and off cover
FIRE_SPARE = 0.5  # neighbours round a fire stand two widest radii and this much apart
CHECKPOINT_RISE = 1.0  # an open camp's checkpoint stands on ground within this of its floor's height
WALLET_SEND_SECONDS = 1.0  # L1b-16, fixed
PATROL_SAMPLE = 1.0  # studs between two samples of a patrol's loop
# L1b Wave 2.
SPACING_SPARE = 0.5  # L1b-W2-4: two posts of a camp stand r_a + r_b + this apart
SNEAK_STEP = 2.0  # L1b-W2-3: the sneak path is sampled this often
CONE_SAMPLE = 0.5  # studs between two samples of the sneak path for the cone-aware margins
JOIN_FACTOR_FIXED = 2  # L1b-W2-12 / Ben's "at least double": Combat.json camps.joinFactor
BODY_HEIGHT = 6.0  # a character, feet to head: what stands this far under a barrier's foot is in it
CLOSE_SPARE = 1.0  # a camp's entry point lies this far inside the close rule's inset rectangle
# The L1c third fix round's m2 and m3: a locking camp's entry, and its cover, stand this far inside
# the close rule's inset rectangle, whose edge is where every nudge of the close lands.
NUDGE_CLEAR = 3.0
SAMPLE = 0.25  # studs between two samples of a walked leg
GATE_FLOOR = 1.0  # levels.gateSeconds' least, and a stage's own (L1c fix round M3) where the close brings a body
# L1c (docs/prompts/l1c-contract.md, L1c-1 and L1c-3): the walled boss room.
WALL_SPARE = 3.0  # a walled camp's fence stands this much over the highest camera (L1c-1)
SIGHT_STEP = 2.0  # eye and camera points are sampled on this grid
CAMERA_SPARE = 2.0  # camera points lie within camera.maxZoom + this of an eye point
DOORWAY = 2.5  # the doorway exemption: an eye this close to the fenced rectangle, inside a gate's lane
# The L1c fix round's m1: near each gate (within camera.maxZoom + CAMERA_SPARE of its opening) eye
# and camera points are also taken on this finer grid, along every edge of the regions they are
# allowed in at SIGHT_EDGE, and at every corner exactly; a point on an edge is taken EDGE_IN on its
# allowed side.
SIGHT_FINE = 0.25
SIGHT_EDGE = 0.05
EDGE_IN = 0.01
# Switches tools/check_levels_mutants.py turns to show what each fix-round rule catches (like
# UNDER_SIDE): SIGHT_ZONES False is the 2-stud grid alone (m1); EXEMPT_CAMERAS True exempts camera
# points in the doorway as 2a58134's gate did (C1); FLOOR_WALLS False measures Floors to the fence
# alone (m4); WALLED_CEILING False (below).
SIGHT_ZONES = True
EXEMPT_CAMERAS = False
FLOOR_WALLS = True
# The L1c second fix round's F1 and F3: a walled camp triggers up to its fence's top
# (sim_range.trigger_ceiling, StageFlow.Ceiling). False judges it at levels.triggerHeight, the
# first fix round's rule, for the mutant driver.
WALLED_CEILING = True
# L2 Wave 1 (docs/prompts/l2-w1-contract.md): bought abilities, and secrets as chests behind keys.
AIR_JUMP = "doubleJump"  # Unlocks.AIR_JUMP: the ability id the air jump keys on (structural)
SECRET_RULES = ("secretReach", "secretBelow", "secretAbove")  # Combat.json levels: SecretFlow.Triggered (L2-11)
DEBUG_UNLOCK_KEYS = ("grantAbilityAttribute", "removeAbilityAttribute", "resetSecretsAttribute")  # L2-19
ABILITY_ID_MAX = 32  # CombatRemotes.MAX_ABILITY_ID_LENGTH: an id the buy remote carries (L2-7)
SECRET_VALOR_MIN = 2  # L2-13: a paying chest gives at least this much Valor, and less than its key's price
BODY_RADIUS = 1.0  # the root's half width on the flat (a body stands this far over an edge)
# L2-18 (c), every lifting ability against a secret's ledge: arcs sampled this often, take-offs and
# targets on this grid, plus this many targets on the castRange circle.
LIFT_STEP = 0.5
LIFT_GRID = 2.0
LIFT_RIM = 64
LIFT_ROUTES_MAX = 40  # (c) stops after this many take-offs with a route (enough to report)
# (c)'s model of an aimed lift, a switch like UNDER_SIDE, and the code as it stands:
# * "today": MovementController.Leap's apex is the lift's `height` over the higher of the root and
#   the target, so a Leap Smash cast at the top of a jump rises jumpHeight + height over the floor;
#   and GroundPoint's caster floor over a void is the caster's feet (L1c).
# * "floor": the apex is `height` over the higher of the target and the caster's floor, never over an
#   airborne root; and the caster's floor over a void is the feet less WallClip.Rise(movement, false).
#   The change docs/prompts/l2-w1-reports/economy-designer.md asks for: it closes every lift route.
LIFT_MODEL = "today"
# Every mission is played with ProvingGrounds.json `loadout` (L2-5), whose families lift nobody, so a
# route (c) finds under LIFT_MODEL is a known limit until W2's loadout picker: reported, not gated,
# while no family with a lifting ability can enter a level. False gates it outright (the mutants).
LIFT_KNOWN_LIMIT_W2 = True
THEME_PATH = REPO_ROOT / "src" / "client" / "UI" / "Theme.luau"
# The Theme numbers the highest camera is built from (the client's; read from the file, never copied).
THEME_KEYS = ("COMBAT_CAMERA_PIVOT_HEIGHT", "COMBAT_CAMERA_MIN_PITCH_DEGREES", "COMBAT_SHAKE_MAX_STUDS")
# ... and the spherecast's radius, which keeps a camera off a wall (the sight gate's stand-off).
SIGHT_THEME_KEYS = ("COMBAT_CAMERA_COLLISION_RADIUS",)
# m1: the drawn body (CrowdRenderer's torso, in radii), read from the file like Theme.
RENDERER_PATH = REPO_ROOT / "src" / "combat" / "client" / "Controllers" / "CrowdRenderer.luau"
RENDERER_KEYS = ("TORSO_WIDTH", "TORSO_DEPTH")
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


def wall_reach(thickness, barrier):
    """How far past a camp's floor edge its Parts reach: the invisible wall stands with its inner
    face on the floor's edge, barrier.thickness deep and never thinner than the fence (fix round,
    ruling 2; LevelGeometry.BarrierBoxes). Without a barrier it is the fence's thickness."""
    return max((barrier or {}).get("thickness") or 0, thickness)


def solids_of(layout, thickness, floor_depth=1.0):
    """Every standing surface of a layout: solid blocks, camp floors (`floor_depth` deep under
    their top: levels.floorThickness), fences, obstacles, secrets."""
    found = [block_solid(b) for b in layout["blocks"] if b.get("collide") is not False]
    for camp in layout["camps"]:
        x0, x1, z0, z1 = camp_rect(camp)
        found.append(Solid(f"Camp_{camp['id']}_Floor", "floor", "campFloor", x0, x1, z0, z1, camp["y"] - floor_depth,
                           camp["y"]))
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


def layout_bounds(layout, thickness, floor_depth=1.0):
    """Everything a layout builds, as a rectangle and a height span: blocks, camps with their
    fence and invisible wall, secrets. (minX, maxX, minZ, maxZ, minY, maxY), or None for an empty
    layout. (Wider than LevelGeometry.Bounds, which counts a camp as its floor.)"""
    boxes = [(s.x0, s.x1, s.z0, s.z1, s.bottom, s.top) for s in solids_of(layout, thickness, floor_depth)]
    boxes += [(b.x0, b.x1, b.z0, b.z1, b.bottom, b.top)
              for b in (block_solid(x) for x in layout["blocks"] if x.get("collide") is False)]
    barrier = layout.get("barrier") or {}
    reach = wall_reach(thickness, barrier)
    for camp in layout["camps"]:
        x0, x1, z0, z1 = camp_rect(camp)
        boxes.append((x0 - reach, x1 + reach, z0 - reach, z1 + reach, camp["y"] - floor_depth,
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


def fire_spots(camp):
    """A camp's fire spots that LevelGeometry.FireBox marks: posture fire with a point."""
    return [spot for spot in camp.get("spots") or [] if spot.get("posture") == "fire" and spot.get("points")]


def part_count(layout, fire_marker=None):
    """The Parts LevelService.Build makes (LevelGeometry.Pieces): one per block; per camp the
    floor, the fence cut at its gates (four sides, one more piece per gate), the obstacles, the
    checkpoint marker, one marker per fire spot (only when Combat.json levels.fireMarkerSize
    is given) and one tent marker per layout `tent` block (L1b-W2-9); only a camp that locks
    (L1b-12) also has its gates and the four barrier boxes; per secret the marked block and its
    sign. `fire_marker` = levels.fireMarkerSize (default: read from Combat.json)."""
    if fire_marker is None:
        fire_marker = sr.load_config(sr.COMBAT_PATH)["levels"].get("fireMarkerSize") or False
    parts = len(layout["blocks"])
    for camp in layout["camps"]:
        gates = len(camp.get("gates") or [])
        locks = camp.get("locks") is True
        obstacles = len(camp.get("obstacles") or []) + int(camp.get("obstacleCount") or 0)
        parts += 1 + (4 + gates if camp.get("fence") else 0) + (gates if locks else 0) + obstacles
        parts += (1 if camp.get("checkpoint") else 0) + (4 if layout.get("barrier") and locks else 0)
        parts += len(fire_spots(camp)) if fire_marker else 0
        parts += 1 if camp.get("tent") else 0
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


def ability_height(proving):
    """The most any weapon ability lifts its caster (Leap Smash's `height`): L1c-1."""
    return max([0.0] + [float(((w.get("ability") or {}).get("height")) or 0) for w in proving["weapons"].values()])


def climb_max(move, ability):
    """L1c-3: the highest top a player gets onto from a surface: jump, double jump, the highest
    ability lift and a step up."""
    return move["jumpHeight"] + move["doubleJumpHeight"] + ability + STEP_UP


def is_tall(solid):
    """What may be an unclimbable wall: a block of look `wall`, or a camp's fence."""
    return solid.kind == "fence" or (solid.kind == "block" and solid.look == "wall")


def unclimbable(solids, move, ability):
    """L1c-3: the names of the walls nobody stands on. A `wall` block or a camp fence is
    unclimbable when its top stands at least climb_max over every standable surface within
    stray_reach of it (that is, nobody lands within reach of its foot high enough to get on it);
    another unclimbable wall is not such a surface. The largest set that holds: start from every
    candidate and drop the ones a standable surface beats until nothing changes."""
    reach = stray_reach(move, 0)
    climb = climb_max(move, ability)
    standable = ("block", "floor", "secret", "fence", "obstacle")
    found = {s.name for s in solids if is_tall(s)}
    changed = True
    while changed:
        changed = False
        for wall in solids:
            if wall.name not in found:
                continue
            for other in solids:
                if other is wall or other.name in found or other.kind not in standable:
                    continue
                if wall.gap_to(other) <= reach + EPS and wall.top - other.top < climb - EPS:
                    found.discard(wall.name)
                    changed = True
                    break
    return found


def theme_numbers():
    """THEME_KEYS and SIGHT_THEME_KEYS as Theme.luau sets them: {key: number}; a key it lacks is
    left out."""
    import re

    text = THEME_PATH.read_text(encoding="utf-8") if THEME_PATH.exists() else ""
    found = {}
    for key in THEME_KEYS + SIGHT_THEME_KEYS:
        match = re.search(rf"^\s*{key}\s*=\s*(-?[0-9.]+)\s*,", text, re.MULTILINE)
        if match:
            found[key] = float(match.group(1))
    return found


def renderer_numbers():
    """RENDERER_KEYS as CrowdRenderer.luau sets them (`local KEY = number`): {key: number}."""
    import re

    text = RENDERER_PATH.read_text(encoding="utf-8") if RENDERER_PATH.exists() else ""
    found = {}
    for key in RENDERER_KEYS:
        match = re.search(rf"^local\s+{key}\s*=\s*([0-9.]+)\s*$", text, re.MULTILINE)
        if match:
            found[key] = float(match.group(1))
    return found


def camera_top(ctx):
    """L1c-1: the highest a camera stands over the surface its player took off from: the double
    jump's peak, the root, the highest ability lift cast there, the pivot and shoulder, the boom
    at camera.maxZoom and the lowest pitch, and the shake. (number, the parts as text), or
    (None, what is missing)."""
    move, camera, theme = ctx["move"], ctx.get("camera") or {}, ctx.get("theme") or {}
    lost = [key for key in THEME_KEYS if key not in theme]
    shoulder = camera.get("shoulderOffset")
    if lost or not is_number(camera.get("maxZoom")) or not (isinstance(shoulder, list) and len(shoulder) == 3):
        return None, "Theme.luau lacks " + ", ".join(lost) if lost else "Combat.json camera lacks maxZoom or shoulderOffset"
    boom = camera["maxZoom"] * math.sin(math.radians(-theme["COMBAT_CAMERA_MIN_PITCH_DEGREES"]))
    parts = [("feet at the double jump's peak", move["jumpHeight"] + move["doubleJumpHeight"]),
             ("root", sr.ROOT_HEIGHT), ("ability lift", ctx["abilityHeight"]),
             ("pivot", theme["COMBAT_CAMERA_PIVOT_HEIGHT"]), ("shoulder", shoulder[1]),
             (f"boom {camera['maxZoom']:g} at {theme['COMBAT_CAMERA_MIN_PITCH_DEGREES']:g} deg", boom),
             ("shake", theme["COMBAT_SHAKE_MAX_STUDS"])]
    return sum(v for _k, v in parts), " + ".join(f"{k} {v:g}" if v == round(v, 2) else f"{k} {v:.2f}"
                                                 for k, v in parts)


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
# L2 Wave 1: a secret is out of reach without its key, within reach with it (L2-11, L2-18)
# ---------------------------------------------------------------------------------------------


def secret_rules(levels):
    """SecretFlow.Triggered's numbers (Combat.json levels, L2-11): (reach, below, above), or None
    when one is not a number."""
    values = [levels.get(key) for key in SECRET_RULES]
    return tuple(float(v) for v in values) if all(is_number(v) for v in values) else None


def ability_ids(expeditions):
    """The ids Expeditions.json `abilities.list` sells (Unlocks.HasKey holds only these)."""
    return [a.get("id") for a in ((expeditions.get("abilities") or {}).get("list") or []) if isinstance(a, dict)]


def lifting_abilities(proving):
    """Every family's ability that lifts its caster, worst case (L2-18 c): [(family, ability)]."""
    return [(family, w["ability"]) for family, w in sorted(proving["weapons"].items())
            if (w.get("ability") or {}).get("height") and (w.get("ability") or {}).get("castRange")]


def fielded_lifts(proving):
    """The lifting abilities a level fields today: every mission is played with `loadout` (L2-5)."""
    loadout = proving.get("loadout") or {}
    return [family for family, _ability in lifting_abilities(proving) if family in loadout.values()]


def point_rect(rect, x, z):
    """The flat distance from (x, z) to a rectangle (x0, x1, z0, z1, ...)."""
    return math.hypot(max(rect[0] - x, x - rect[1], 0.0), max(rect[2] - z, z - rect[3], 0.0))


def segment_point(ax, az, bx, bz, px, pz):
    """The flat distance from (px, pz) to the segment a-b."""
    dx, dz = bx - ax, bz - az
    run = dx * dx + dz * dz
    f = 0.0 if run <= EPS else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / run))
    return math.hypot(ax + dx * f - px, az + dz * f - pz)


def segment_rect(ax, az, bx, bz, rect):
    """The flat distance from the segment a-b to a rectangle (0 when it crosses or enters it)."""
    if point_rect(rect, ax, az) <= EPS or point_rect(rect, bx, bz) <= EPS or seg_hits_rect(ax, az, bx, bz, rect[:4]):
        return 0.0
    corners = ((rect[0], rect[2]), (rect[0], rect[3]), (rect[1], rect[2]), (rect[1], rect[3]))
    return min([point_rect(rect, ax, az), point_rect(rect, bx, bz)]
               + [segment_point(ax, az, bx, bz, cx, cz) for cx, cz in corners])


def secret_base(solids, secret):
    """The block or floor a secret stands on: its top is the secret's bottom and it holds the
    secret's centre; None when it floats."""
    bottom = secret["y"] - secret["sy"] / 2
    return next((s for s in solids if s.kind in ("block", "floor") and abs(s.top - bottom) < 0.01
                 and s.holds(secret["x"], secret["z"])), None)


def key_rects(solids, base, chest):
    """The tops a secret's key opens: the base's top less whatever stands on it (an unclimbable
    wall, the chest), and the chest's own top. [(x0, x1, z0, z1, top, name)]."""
    covers = [s for s in solids if s is not base and s.top > base.top + EPS and s.bottom < base.top + BODY_HEIGHT
              and s.x1 > base.x0 + EPS and s.x0 < base.x1 - EPS and s.z1 > base.z0 + EPS and s.z0 < base.z1 - EPS]
    xs = sorted({base.x0, base.x1} | {min(max(v, base.x0), base.x1) for s in covers for v in (s.x0, s.x1)})
    zs = sorted({base.z0, base.z1} | {min(max(v, base.z0), base.z1) for s in covers for v in (s.z0, s.z1)})
    rects = []
    for i in range(len(xs) - 1):
        for k in range(len(zs) - 1):
            if xs[i + 1] - xs[i] <= EPS or zs[k + 1] - zs[k] <= EPS:
                continue
            cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[k] + zs[k + 1]) / 2
            if not any(c.holds(cx, cz) for c in covers):
                rects.append((xs[i], xs[i + 1], zs[k], zs[k + 1], base.top, base.name))
    rects.append((chest.x0, chest.x1, chest.z0, chest.z1, chest.top, chest.name))
    return rects


def lift_takeoffs(solids, box, reach, skip, tall, move, model):
    """(c)'s take-offs for one cast range: {(x, z, feet): (the caster's floor, how)}. Every
    standable top (not an unclimbable wall, not a key surface) within castRange and a body's radius
    of the key tops, on a LIFT_GRID grid, cast on the ground and at the top of one jump; and off
    each such top's edge at the top of a jump, pushed out 1 and 4 studs, as far as the jump carries
    at walk speed, and that plus half and all of an air dash (which holds its height). There the
    caster's floor is the top under him, or over a void LIFT_MODEL's rule."""
    jump = move["jumpHeight"]
    standable = ("block", "floor", "secret", "fence", "obstacle")
    top_reach = move["walkSpeed"] * math.sqrt(2 * jump / sr.GRAVITY)
    offs = (1.0, 4.0, top_reach, top_reach + move["dashDistance"] / 2, top_reach + move["dashDistance"])
    takeoffs = {}
    for s in solids:
        if s.kind not in standable or s.name in tall or s.name in skip:
            continue
        if rect_gap((s.x0, s.x1, s.z0, s.z1), box) > reach + BODY_RADIUS + offs[-1]:
            continue
        for x, z in standable_points(solids, s, LIFT_GRID):
            if point_rect(box, x, z) <= reach + BODY_RADIUS:
                takeoffs.setdefault((round(x, 2), round(z, 2), s.top), (s.top, f"{s.name} (on the ground)"))
                takeoffs.setdefault((round(x, 2), round(z, 2), s.top + jump), (s.top, f"{s.name} (at a jump's top)"))
        feet = s.top + jump
        xs = [s.x0 + LIFT_GRID * k for k in range(int((s.x1 - s.x0) / LIFT_GRID) + 1)] + [s.x1]
        zs = [s.z0 + LIFT_GRID * k for k in range(int((s.z1 - s.z0) / LIFT_GRID) + 1)] + [s.z1]
        rim = ([(x, s.z0, 0.0, -1.0) for x in xs] + [(x, s.z1, 0.0, 1.0) for x in xs]
               + [(s.x0, z, -1.0, 0.0) for z in zs] + [(s.x1, z, 1.0, 0.0) for z in zs])
        for ex, ez, nx, nz in rim:
            for d in offs:
                x, z = ex + nx * d, ez + nz * d
                if point_rect(box, x, z) > reach + BODY_RADIUS:
                    continue
                if any(o.holds(x, z) and o.top > feet + EPS and o.bottom < feet + BODY_HEIGHT for o in solids):
                    continue  # inside something: no body there
                under, _o = ground(solids, x, z, feet, kinds=standable)
                if under is None:
                    floor, how = (feet if model == "today" else feet - jump), "a void"
                else:
                    floor, how = under, f"a top at {under:g}"
                takeoffs.setdefault((round(x, 2), round(z, 2), feet), (floor, f"off {s.name}'s edge, over {how}"))
    return takeoffs


def lift_arc_route(x, z, feet, caster, grid, near, keys, box, move, height, model):
    """One take-off of (c): the first target whose arc puts the feet STEP_UP under a key top or
    higher within BODY_RADIUS of it, as (target x, z, floor, sample x, z, feet, key), or None."""
    jump = move["jumpHeight"]
    low = min(k[4] for k in keys) - STEP_UP
    root = feet + sr.ROOT_HEIGHT
    for dx, dz in grid:
        tx, tz = x + dx, z + dz
        if segment_rect(x, z, tx, tz, box) > BODY_RADIUS + EPS:
            continue
        floor = max([o.top for o in near if o.holds(tx, tz)], default=None)
        floor = caster if floor is None else floor
        if floor - caster > jump + EPS:
            continue  # GroundPoint refuses it: WallClip.TooHigh with Rise(movement, false)
        to = floor + sr.ROOT_HEIGHT
        apex = (max(root, to) + height if model == "today"
                else max(root, to + height, caster + sr.ROOT_HEIGHT + height))
        if apex - sr.ROOT_HEIGHT < low - EPS:
            continue
        up, down = math.sqrt(max(apex - root, 0.0)), math.sqrt(max(apex - to, 0.0))
        share = up / (up + down) if up + down > EPS else 0.5
        steps = max(int(math.ceil(math.hypot(dx, dz) / LIFT_STEP)), 1)
        for k in range(steps + 1):
            u = k / steps
            if u <= share and share > EPS:
                y = apex - (apex - root) * ((share - u) / share) ** 2
            elif share < 1 - EPS:
                y = apex - (apex - to) * ((u - share) / (1 - share)) ** 2
            else:
                y = apex
            px, pz, f = x + dx * u, z + dz * u, y - sr.ROOT_HEIGHT
            hit = next((kr for kr in keys if point_rect(kr, px, pz) <= BODY_RADIUS + EPS and f >= kr[4] - STEP_UP - EPS),
                       None)
            if hit is not None:
                return tx, tz, floor, px, pz, f, hit
            if k > 0 and any(o.holds(px, pz) and o.top > f + EPS and o.bottom < f + BODY_HEIGHT - EPS for o in near):
                break  # stopped against a solid
    return None


def lift_routes(solids, keys, skip, tall, move, lifts, model=None):
    """L2-18 (c): every way a player WITHOUT the double jump gets a lifting ability's arc onto a
    secret's ledge (lift_takeoffs, then lift_arc_route). Targets as GroundPoint finds them: every
    point within castRange on the flat (a LIFT_GRID grid and LIFT_RIM points on the rim); its floor
    is the highest top under it, or the caster's floor over a void; refused when more than
    WallClip.Rise(movement, false) = jumpHeight over the caster's floor. The arc is
    MovementController.Leap's under LIFT_MODEL, sampled every LIFT_STEP and stopped at the first
    solid over the feet. One route per take-off, at most LIFT_ROUTES_MAX: [text]."""
    model = model or LIFT_MODEL
    jump = move["jumpHeight"]
    low = min(k[4] for k in keys) - STEP_UP
    box = (min(k[0] for k in keys), max(k[1] for k in keys), min(k[2] for k in keys), max(k[3] for k in keys))
    standable = ("block", "floor", "secret", "fence", "obstacle")
    found = []
    for family, ability in lifts:
        height, reach = float(ability["height"]), float(ability["castRange"])
        cells = int(reach // LIFT_GRID)
        grid = [(dx * LIFT_GRID, dz * LIFT_GRID) for dx in range(-cells, cells + 1) for dz in range(-cells, cells + 1)
                if math.hypot(dx * LIFT_GRID, dz * LIFT_GRID) <= reach + EPS]
        grid += [(reach * math.cos(2 * math.pi * k / LIFT_RIM), reach * math.sin(2 * math.pi * k / LIFT_RIM))
                 for k in range(LIFT_RIM)]
        for (x, z, feet), (caster, how) in sorted(lift_takeoffs(solids, box, reach, skip, tall, move, model).items()):
            near = [o for o in solids if rect_gap((o.x0, o.x1, o.z0, o.z1), (x - reach, x + reach, z - reach, z + reach))
                    <= EPS]
            # The highest arc any legal target gives from here: none reaches a key's step-up height.
            best = max([caster] + [o.top for o in near if (o.kind in standable or o.look == "wall")
                                   and o.top - caster <= jump + EPS])
            root = feet + sr.ROOT_HEIGHT
            bound = (max(root, best + sr.ROOT_HEIGHT) + height if model == "today"
                     else max(root, best + sr.ROOT_HEIGHT + height, caster + sr.ROOT_HEIGHT + height))
            if bound - sr.ROOT_HEIGHT < low - EPS:
                continue
            hit = lift_arc_route(x, z, feet, caster, grid, near, keys, box, move, height, model)
            if hit is not None:
                tx, tz, floor, px, pz, f, key = hit
                found.append(f"{family}'s {ability.get('name') or ability.get('id')} from {how} at ({x:g}, {feet:g}, "
                             f"{z:g}) aimed at ({tx:.1f}, {floor:g}, {tz:.1f}): feet {f:.1f} at ({px:.1f}, {pz:.1f}) "
                             f"over {key[5]}'s top {key[4]:g}")
                if len(found) >= LIFT_ROUTES_MAX:
                    return found
    return found


def check_secret_reach(name, layout, ctx, expect, solids, tall):
    """L2-18 (a) to (d) for every secret whose key is a bought ability (Expeditions.json
    abilities.list): only those may pay (e). (a) with the key: the ledge's band and a standable
    point inside the trigger; (b) without it, no jump, step up and dash gets on the ledge (the old
    lookout test, unclimbable walls left out); (c) nor any lifting ability's arc (lift_routes);
    (d) the trigger is met from nowhere else: no other standable top puts a standing root in it,
    and every point of its circle lies over the ledge or an unclimbable wall, so an airborne root
    meets it only over the ledge, where (b) and (c) keep him out."""
    move, levels = ctx["move"], ctx["levels"]
    tag = f"{name}:"
    jump = jump_facts(move)
    rules = secret_rules(levels)
    sold = ctx.get("abilityIds") or []
    for secret in layout["secrets"]:
        sid, needs = secret["id"], secret["needs"]
        if needs not in sold:
            continue
        if needs != AIR_JUMP:
            expect(False, f"{tag} the {sid} needs {needs}, a sold ability check_levels has no reach rule for (L2-18)")
            continue
        chest = next((s for s in solids if s.name == f"Secret_{sid}"), None)
        base = secret_base(solids, secret)
        if base is None or chest is None or rules is None:
            expect(False, f"{tag} the {sid} stands on a ledge block, and Combat.json levels has "
                   f"{', '.join(SECRET_RULES)} (L2-18)")
            continue
        reach, below, above = rules
        keys = key_rects(solids, base, chest)
        skip = {base.name, chest.name}
        # (a) The owner's band, and the trigger holds a standable point on a key top.
        road, away = route_height_near(layout, secret["x"], secret["z"])
        rise = base.top - road
        lo = move["jumpHeight"] + STEP_UP
        hi = move["jumpHeight"] + move["doubleJumpHeight"] - LOOKOUT_UNDER_DOUBLE
        expect(lo < rise <= hi, f"{tag} the {sid} ledge's top is over {lo:g} and at most {hi:g} studs above the "
               f"road under it (over one jump's {move['jumpHeight']:g} and a step up of {STEP_UP:g}, under jump + "
               f"double jump's {move['jumpHeight'] + move['doubleJumpHeight']:g}): {rise:g}, {away:.0f} studs from "
               f"the road (L2-18a)")
        held = [kr[5] for kr in keys if point_rect(kr, secret["x"], secret["z"]) <= reach + EPS
                and -below - EPS <= kr[4] + sr.ROOT_HEIGHT - base.top <= above + EPS]
        expect(bool(held), f"{tag} the {sid}'s trigger (levels.secretReach {reach:g}, a root {below:g} under to "
               f"{above:g} over the chest's foot at {base.top:g}) holds a standable point with the key: "
               + (", ".join(sorted(set(held))) if held else "none") + " (L2-18a)")
        # (b) One jump, a step up and a dash, from every surface but the keys and unclimbable walls.
        ways, closest = [], (math.inf, None)
        for s in solids:
            if s.name in skip or s.name in tall:
                continue
            need = base.top - s.top - STEP_UP
            gap = min(rect_gap((s.x0, s.x1, s.z0, s.z1), kr[:4]) for kr in keys)
            spare = need - move["jumpHeight"]
            if gap <= move["walkSpeed"] * jump["air"] + move["dashDistance"] and spare < closest[0]:
                closest = (spare, s.name)
            carry = reach_at_rise(move, need)
            if carry is not None and gap <= carry + move["dashDistance"] + EPS:
                ways.append(f"{s.name} ({base.top - s.top:g} up, {gap:.0f} away)")
        expect(not ways, f"{tag} the {sid} needs the double jump: no surface is within one jump, a step up of "
               f"{STEP_UP:g} studs and a dash of its ledge, unclimbable walls left out (L2-18b)"
               + (f" (reachable from {', '.join(ways)})" if ways else
                  f" (the closest call: {closest[1]}, {closest[0]:g} studs short)" if closest[1] else ""))
        # (c) Every lifting ability, worst case.
        lifts = ctx.get("lifts") or []
        routes = lift_routes(solids, keys, skip, tall, move, lifts)
        fielded = ctx.get("fieldedLifts") or []
        known = bool(routes) and LIFT_KNOWN_LIMIT_W2 and not fielded
        count = f"{len(routes)}{'+' if len(routes) >= LIFT_ROUTES_MAX else ''}"
        told = ", ".join(f"{family} ({a.get('name')}, height {a['height']:g}, castRange {a['castRange']:g})"
                         for family, a in lifts) or "none"
        if not routes:
            verdict = "no arc of a player without it ends on its ledge"
        elif known:
            verdict = (f"KNOWN LIMIT until W2 (LIFT_KNOWN_LIMIT_W2): {count} take-offs reach it, and no family with a "
                       f"lift can enter a level (ProvingGrounds.json loadout {', '.join(ctx.get('loadout') or [])}); "
                       f"e.g. {routes[0]}")
        else:
            verdict = (f"{count} take-offs reach it" + (f", and {', '.join(fielded)} can enter a level" if fielded else "")
                       + f": {'; '.join(routes[:2])}")
        expect(not routes or known, f"{tag} the {sid} needs the double jump against every lifting ability ({told}; "
               f"LIFT_MODEL \"{LIFT_MODEL}\"): {verdict} (L2-18c)")
        if routes:
            ctx["gate16"].setdefault(name, {}).setdefault("lifts", []).append(
                f"{sid}: {count} take-offs under LIFT_MODEL \"{LIFT_MODEL}\"" + (" (known limit until W2)" if known else "")
                + f", e.g. {routes[0]}")
        # (d) Nothing else meets the trigger.
        others = []
        for s in solids:
            if s.name in skip or s.name in tall or s.kind not in ("block", "floor", "secret", "fence", "obstacle"):
                continue
            if point_rect((s.x0, s.x1, s.z0, s.z1), secret["x"], secret["z"]) > reach + EPS:
                continue
            if not (-below - EPS <= s.top + sr.ROOT_HEIGHT - base.top <= above + EPS):
                continue
            if any(math.hypot(x - secret["x"], z - secret["z"]) <= reach + EPS
                   for x, z in standable_points(solids, s, 0.5)):
                others.append(s.name)
        circle = [(secret["x"] + reach * i / 8 * math.cos(2 * math.pi * k / 32),
                   secret["z"] + reach * i / 8 * math.sin(2 * math.pi * k / 32)) for i in range(9) for k in range(32)]
        loose = [(x, z) for x, z in circle if not base.holds(x, z) and not any(
            s.name in tall and s.holds(x, z) for s in solids)]
        expect(not others and not loose,
               f"{tag} the {sid}'s trigger is met only on its ledge: no other standable top puts a standing root in it, "
               f"and its {reach:g}-stud circle lies over {base.name} or an unclimbable wall (L2-18d)"
               + (f" (a root on {', '.join(others)})" if others else "")
               + (f" (off the ledge at ({loose[0][0]:.1f}, {loose[0][1]:.1f}))" if loose else ""))


def check_secret_rewards(file, layout, expeditions, expect):
    """L2-18 (e) and L2-13's sizing: a level file's secret pays (valor, materials or family) only
    when its key is an ability Expeditions.json sells, and then at least SECRET_VALOR_MIN Valor and
    less than that ability's price."""
    entries = file.get("secrets") or {}
    sold = {a.get("id"): a for a in ((expeditions.get("abilities") or {}).get("list") or []) if isinstance(a, dict)}
    needs = {s["id"]: s["needs"] for s in layout["secrets"]}
    bad, told = [], []
    for sid, entry in sorted(entries.items()):
        pays = [key for key in ("valor", "materials", "family") if key in (entry or {})]
        if not pays:
            told.append(f"{sid} pays nothing")
            continue
        key = needs.get(sid)
        if key not in sold:
            bad.append(f"{sid} pays {', '.join(pays)} behind {key}, which no ability opens")
            continue
        price = (sold[key].get("price") or {}).get("valor")
        valor = entry.get("valor") or 0
        if not (is_number(price) and is_number(valor) and SECRET_VALOR_MIN <= valor < price):
            bad.append(f"{sid}'s {valor} Valor is not at least {SECRET_VALOR_MIN} and under {key}'s price {price}")
        told.append(f"{sid} behind {key}: {valor} Valor, {entry.get('materials') or 0} {file.get('material')}"
                    + (f", the {entry['family']}" if entry.get("family") else ""))
    expect(not bad, f"{file['id']}: a secret pays only behind a sold key, and then {SECRET_VALOR_MIN} Valor or more and "
           f"under that key's price (L2-18e, L2-13): " + ("; ".join(bad) if bad else "; ".join(told) or "no secrets"))


def check_abilities(expeditions, level_files, expect):
    """L2-6: Expeditions.json `abilities.list` as UnlockService.Init reads it (an id, a name, a
    text, a whole price in Valor over 0, an order), the air jump among them; and Double Jump costs
    no more than one solo Normal clear of the first level pays (the boss's Valor x rewardMult)."""
    listed = (expeditions.get("abilities") or {}).get("list")
    if not isinstance(listed, list) or not listed:
        expect(False, "Expeditions.json abilities.list: a list of abilities (L2-6)")
        return
    bad, ids = [], []
    for index, a in enumerate(listed, 1):
        a = a if isinstance(a, dict) else {}
        aid = a.get("id")
        ids.append(aid)
        price = (a.get("price") or {}).get("valor") if isinstance(a.get("price"), dict) else None
        if not (isinstance(aid, str) and 0 < len(aid) <= ABILITY_ID_MAX):
            bad.append(f"entry {index}: id {aid!r}")
        if not (isinstance(a.get("name"), str) and a["name"] and isinstance(a.get("text"), str) and a["text"]):
            bad.append(f"{aid}: a name and a text")
        if not sr.whole(price):
            bad.append(f"{aid}: price.valor {price} is not a whole number over 0")
        if not is_number(a.get("order")):
            bad.append(f"{aid}: order {a.get('order')}")
    if len(set(ids)) != len(ids):
        bad.append("an id twice")
    expect(not bad and AIR_JUMP in ids, f"Expeditions.json abilities.list: every entry has an id of at most "
           f"{ABILITY_ID_MAX} characters, a name, a text, a whole price in Valor over 0 and an order, no id twice, and "
           f"{AIR_JUMP} is one (L2-6): " + ("; ".join(bad) if bad else ", ".join(
               f"{a['id']} {a['price']['valor']} Valor" for a in listed)) + ("" if AIR_JUMP in ids else f"; no {AIR_JUMP}"))
    # The first level on the map (the first node of kind "level" with a built file).
    by_id = {f["id"]: f for f in level_files}
    first = next((by_id[n["level"]] for n in expeditions["nodes"] if n.get("kind") == "level" and n.get("level") in by_id
                  and by_id[n["level"]].get("stages")), None)
    air = next((a for a in listed if isinstance(a, dict) and a.get("id") == AIR_JUMP), None)
    if first is None or air is None or bad:
        return
    boss = next((w["boss"] for st in first["stages"] for w in st.get("waves") or [] if w.get("boss")), None) or {}
    normal = (first.get("difficulties") or {}).get("normal") or {}
    clear = sr.luau_round(boss.get("valor", 0) * normal.get("rewardMult", 0))
    price = air["price"]["valor"]
    expect(0 < price <= clear, f"Expeditions.json: {air['name']} costs {price} Valor, at most one solo Normal clear of "
           f"{first['name']} ({clear} Valor: the boss's {boss.get('valor')} x rewardMult {normal.get('rewardMult')}; "
           f"MISSIONS_DESIGN 22)")


# ---------------------------------------------------------------------------------------------
# The gates of one level layout
# ---------------------------------------------------------------------------------------------


def gate_road(camp, solid, thickness):
    """L1c-3: a path block that runs through one of the camp's own gates: it meets the floor's
    edge on the gate's side and its footprint across that side lies within the gate's opening."""
    if solid.kind != "block" or solid.look != "path":
        return False
    x0, x1, z0, z1 = camp_rect(camp)
    for gate in camp.get("gates") or []:
        gx0, gx1, gz0, gz1 = gate_rect(camp, gate, thickness)
        side = gate["side"]
        if side in ("west", "east"):
            meets = solid.x1 >= x0 - EPS and solid.x0 <= x0 + EPS if side == "west" else (
                solid.x0 <= x1 + EPS and solid.x1 >= x1 - EPS)
            if meets and solid.z0 >= gz0 - EPS and solid.z1 <= gz1 + EPS:
                return True
        else:
            meets = solid.z1 >= z0 - EPS and solid.z0 <= z0 + EPS if side == "north" else (
                solid.z0 <= z1 + EPS and solid.z1 >= z1 - EPS)
            if meets and solid.x0 >= gx0 - EPS and solid.x1 <= gx1 + EPS:
                return True
    return False


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
    solids = solids_of(layout, thickness, levels["floorThickness"])
    jump = jump_facts(move)
    tag = f"{name}:"
    # L1c-3: walls nobody gets on are not standable ground (the fence rule, the band, beside).
    tall = unclimbable(solids, move, ctx["abilityHeight"])

    # Ruling 6 of the fix round: a size of 0 or less is no Part (LevelGeometry.Pieces refuses it).
    flat = [b.get("name") or b["look"] for b in layout["blocks"] if min(b["sx"], b["sy"], b["sz"]) <= 0]
    flat += [f"camp {c['id']} obstacle {i + 1}" for c in layout["camps"] for i, o in enumerate(c.get("obstacles") or [])
             if min(o["sx"], o["sy"], o["sz"]) <= 0]
    flat += [f"secret {x['id']}" for x in layout["secrets"] if min(x["sx"], x["sy"], x["sz"]) <= 0]
    flat += [f"camp {c['id']}" for c in layout["camps"] if min(c["sx"], c["sz"]) <= 0]
    expect(not flat, f"{tag} every block, obstacle, secret and camp has a size over 0 on each axis"
           + (f" (not: {', '.join(flat)})" if flat else ""))

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
        # L1c-3: a fence nobody gets on (every strip unclimbable) is exempt: no root stands on it.
        walled = bool(fence) and all(f"Camp_{cid}_Fence_{side}" in tall for side in SIDES)
        expect(bool(fence) and 0 < fence["height"] and (walled or fence["height"] <= levels["triggerHeight"] - sr.ROOT_HEIGHT),
               f"{tag} camp {cid} has a fence, and a root on its top is inside the trigger's height "
               f"(levels.triggerHeight {levels['triggerHeight']:g})" + (f": {fence['height']:g} high" if fence else "")
               + (f" (an unclimbable wall: its top is at least {climb_max(move, ctx['abilityHeight']):g} over every "
                  f"standable surface within {stray_reach(move, 0):.1f}, so nobody stands on it; L1c-3)" if walled else ""))
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
                expect(lined and fits and near <= ENTRY_GATE_REACH,
                       f"{tag} camp {cid}: the {word} point stands {near:g} studs inside the {gate['side']} gate (at "
                       f"most {ENTRY_GATE_REACH:g}), in line with its opening")
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
        # Only a camp that locks has a stage, so spawn points and a checkpoint on its floor (L1b-12);
        # an open camp's checkpoint is held off its floor by check_residents (L1b-18).
        locks = camp.get("locks") is True
        if locks:
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
                   f"{tag} camp {cid} (locks) has a checkpoint on its floor")
            # The L1c third fix round's m2 and m3: at the close a root in the fenced rectangle is
            # nudged onto the nearest point of the inset rectangle (StageFlow.GateNudge), so onto
            # its edge, anywhere along a gate's width or past it; a road player is placed on the
            # entry in the same close (feet up, speed zeroed). The entry stands NUDGE_CLEAR inside
            # that edge, so a road player never lands on a nudged one, and so does every solid on
            # the floor, so a nudge never lands in cover.
            inset = levels.get("closeInset") or 0
            ix0, ix1, iz0, iz1 = x0 + inset, x1 - inset, z0 + inset, z1 - inset
            entry_clear = min(entry["x"] - ix0, ix1 - entry["x"], entry["z"] - iz0, iz1 - entry["z"])
            boxes = list(camp.get("obstacles") or []) + ([camp["tent"]] if camp.get("tent") else [])
            covered = [round(min(o["x"] - o["sx"] / 2 - ix0, ix1 - o["x"] - o["sx"] / 2,
                                 o["z"] - o["sz"] / 2 - iz0, iz1 - o["z"] - o["sz"] / 2), 2) for o in boxes]
            near_cover = min(covered, default=math.inf)
            expect(entry_clear >= NUDGE_CLEAR - EPS and near_cover >= NUDGE_CLEAR - EPS,
                   f"{tag} camp {cid}: the close's nudge lands clear: the entry stands {entry_clear:g} studs and its "
                   f"nearest cover {near_cover:g} inside the inset rectangle's edge, where every nudge lands (needs "
                   f"{NUDGE_CLEAR:g})")
        # Flat: nothing but its own obstacles rises from the floor, and they stand on it.
        bumps = [s.name for s in solids if s.kind in ("block", "secret") and s.top > camp["y"] + EPS
                 and s.bottom < camp["y"] + (barrier.get("height") or 0)
                 and s.x1 > x0 + EPS and s.x0 < x1 - EPS and s.z1 > z0 + EPS and s.z0 < z1 - EPS]
        stray = [i + 1 for i, o in enumerate(camp.get("obstacles") or [])
                 if o["x"] - o["sx"] / 2 < x0 - EPS or o["x"] + o["sx"] / 2 > x1 + EPS
                 or o["z"] - o["sz"] / 2 < z0 - EPS or o["z"] + o["sz"] / 2 > z1 + EPS]
        expect(not bumps and not stray, f"{tag} camp {cid} is flat at height {camp['y']:g}: no block rises through "
               f"its floor and its obstacles stand on it" + (f" ({bumps or stray})" if bumps or stray else ""))
        # Within the wire's reach of the world origin, the invisible wall included; and in height
        # with the highest a launch may carry a crowd body (levels.crowdCeiling) on top.
        reach = wall_reach(thickness, barrier)
        ceiling = levels["crowdCeiling"]
        furthest = max(abs(x0 - reach), abs(x1 + reach), abs(z0 - reach), abs(z1 + reach), abs(camp["y"]) + ceiling)
        expect(furthest <= ORIGIN_LIMIT, f"{tag} camp {cid} lies within {ORIGIN_LIMIT:g} studs of the world origin on "
               f"each axis, its floor's height with levels.crowdCeiling {ceiling:g} on top: furthest {furthest:g}")
        if not locks:
            # An open camp builds no gate and no barrier box (L1b-12), and sneaking past it is
            # allowed: the ground beside it and the wall's band are a locking camp's gates only.
            continue
        # Nothing beside it: along the axis the route crosses it on, the only thing in its span is
        # itself. L1c-3: what counts is within a jump, a double jump and a dash of its fenced
        # rectangle (what this rule measures), less unclimbable walls and the roads through its own
        # gates (as the band rule below).
        axis = camp_axis(camp)
        lo, hi = (x0 - thickness, x1 + thickness) if axis == "x" else (z0 - thickness, z1 + thickness)
        drop = camp["y"] + (fence["height"] if fence else 0) - layout["killY"]
        clear = stray_reach(move, 0)
        fenced = (x0 - thickness, x1 + thickness, z0 - thickness, z1 + thickness)
        beside = []
        for s in solids:
            if s.name.startswith(f"Camp_{cid}_") or s.name in tall:
                continue
            if rect_gap((s.x0, s.x1, s.z0, s.z1), fenced) > clear + EPS or gate_road(camp, s, thickness):
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
        # The invisible wall. At "close" it is solid from the floor's edge outward (fix round,
        # ruling 2), `reach` deep on all four sides, gate gaps included. Nothing a player should
        # stand on may sit in that band: only the road that leads through one of the camp's own
        # gates crosses it.
        in_band = []
        nearest_ground = (math.inf, None)
        for s in solids:
            if s.name.startswith(f"Camp_{cid}_") or s.kind not in ("block", "secret") or s.name in tall:
                continue  # L1c-3: an unclimbable wall is not ground
            if s.top <= camp["y"] - BODY_HEIGHT or s.bottom >= camp["y"] + (barrier.get("height") or 0):
                continue
            ix0, ix1 = max(s.x0, x0 - reach), min(s.x1, x1 + reach)
            iz0, iz1 = max(s.z0, z0 - reach), min(s.z1, z1 + reach)
            if ix1 - ix0 <= EPS or iz1 - iz0 <= EPS:
                # Clear of the wall's outer face: by how much?
                away = math.hypot(max(x0 - reach - s.x1, s.x0 - x1 - reach, 0.0),
                                  max(z0 - reach - s.z1, s.z0 - z1 - reach, 0.0))
                if away < nearest_ground[0]:
                    nearest_ground = (away, s.name)
                continue
            if ix0 >= x0 - EPS and ix1 <= x1 + EPS and iz0 >= z0 - EPS and iz1 <= z1 + EPS:
                continue  # inside the floor's edge: not in the band
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
               f"({reach:g} studs outward from the floor's edge, gate gaps included), but the road through its gates"
               + (f" (found {', '.join(in_band)})" if in_band else
                  f" (the nearest other ground: {nearest_ground[1]}, {nearest_ground[0]:g} studs past the wall's "
                  f"outer face)" if nearest_ground[1] else ""))

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
        # LevelService stands the sign's block (Expeditions.json sign.size) on its point: the
        # whole footprint is on solid ground at that height, not over the void beside the road.
        road, away = route_height_near(layout, sign.get("x", 0), sign.get("z", 0))
        wide, deep = (ctx["signSize"][0], ctx["signSize"][2]) if ctx.get("signSize") else (0.0, 0.0)
        cells = max(int(math.ceil(max(wide, deep) / 0.5)), 1)
        held = 0
        for i in range(cells + 1):
            for k in range(cells + 1):
                px = sign.get("x", 0) - wide / 2 + wide * i / cells
                pz = sign.get("z", 0) - deep / 2 + deep * k / cells
                top, _under = ground(solids, px, pz, sign.get("y", 0) + EPS, kinds=("block", "floor"))
                held += 1 if top is not None and abs(top - sign.get("y", 0)) < 0.01 else 0
        expect(wide > 0 and held == (cells + 1) ** 2,
               f"{tag} the {secret['id']} sign's {wide:g} x {deep:g} foot stands on solid ground at its height "
               f"{sign.get('y', 0):g} ({held} of {(cells + 1) ** 2} samples), {away:.0f} studs from the route")
    # L2-18 (a) to (d): the secrets a bought ability opens.
    check_secret_reach(name, layout, ctx, expect, solids, tall)
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

    check_kill_height(tag, layout, solids, levels, expect)
    parts = part_count(layout, levels.get("fireMarkerSize") or False)
    tents = sum(1 for c in layout["camps"] if c.get("tent"))
    expect(parts <= levels["maxParts"], f"{tag} {parts} Parts, {tents} of them tent markers (levels.maxParts "
           f"{levels['maxParts']}; tools/crowd_harness holds the count to LevelGeometry.Pieces')")
    facts["parts"] = parts
    return facts


def check_kill_height(tag, layout, solids, levels, expect):
    """killY and the depth of the ground (fix round, E5 and part A's item 2). A fall is short and
    a landing holds: killY is at least KILL_UNDER[0] under every standable surface, at most
    KILL_UNDER[1] under the lowest, under every Part's bottom and above KILL_FLOOR; and every
    block a body lands on is at least levels.floorThickness deep, or rests on another solid."""
    kill = layout["killY"]
    tops = [s for s in solids if s.kind in ("block", "floor", "secret", "obstacle", "fence")]
    lowest = min(tops, key=lambda s: s.top) if tops else None
    bottom = min((s.bottom for s in solids), default=0.0)
    under = (lowest.top - kill) if lowest is not None else math.inf
    expect(lowest is not None and KILL_FLOOR < kill < bottom and KILL_UNDER[0] <= under <= KILL_UNDER[1],
           f"{tag} killY {kill:g} is {KILL_UNDER[0]:g}-{KILL_UNDER[1]:g} studs under the lowest standable surface "
           + (f"({lowest.name}, top {lowest.top:g}: {under:g} under)" if lowest is not None else "(none)")
           + f", under every Part's bottom ({bottom:g}) and above {KILL_FLOOR:g}")
    depth = levels["floorThickness"]
    thin = []
    for s in solids:
        if s.kind != "block" or s.look not in GROUND_LOOKS or s.top - s.bottom >= depth - EPS:
            continue
        # Thin ground is sound only where another solid lies right under all of it.
        mid_x, mid_z = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
        rests = all(any(o is not s and o.holds(x, z) and o.top >= s.bottom - EPS and o.bottom < s.bottom
                        for o in solids)
                    for x in (s.x0, mid_x, s.x1) for z in (s.z0, mid_z, s.z1))
        if not rests:
            thin.append(f"{s.name} ({s.top - s.bottom:g} deep)")
    expect(not thin, f"{tag} every block a body lands on (looks {', '.join(GROUND_LOOKS)}) is at least "
           f"levels.floorThickness {depth:g} deep, or rests on another solid" + (f" (thin: {', '.join(thin)})" if thin else ""))


def check_arena_layout(name, layout, ctx, expect):
    """A layout that names an arena (ruling 27): the gates that still apply to its one camp."""
    levels = ctx["levels"]
    camp = layout["camps"][0]
    x0, x1, z0, z1 = camp_rect(camp)
    barrier = layout.get("barrier") or {}
    reach = wall_reach(levels["fenceThickness"], barrier)
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
    solids = solids_of(layout, levels["fenceThickness"], levels["floorThickness"])
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
    flat = [b.get("name") or b["look"] for b in layout["blocks"] if min(b["sx"], b["sy"], b["sz"]) <= 0]
    expect(not flat, f"{name}: every block has a size over 0 on each axis" + (f" (not: {', '.join(flat)})" if flat else ""))
    check_kill_height(f"{name}:", layout, solids, levels, expect)
    mine = layout_bounds(layout, levels["fenceThickness"], levels["floorThickness"])
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


def fielded(stage, kinds):
    """Every kind that can stand in a camp stage at any difficulty: its groups, its bosses, and
    what those call (a summon's kind)."""
    names = [k for k, _boss in stage_kinds(stage)]
    for name in list(names):
        for attack in (kinds.get(name) or {}).get("attacks") or []:
            called = attack.get("summon")
            if called and called not in names:
                names.append(called)
    return names


def ground_reach(names, kinds):
    """The lowest `height` of the ground attacks those kinds have: (height, kind, shape), or None
    when none of them has one. ThreatField: a shape with a `height` misses feet more than that
    far above the crowd's floor; a shot and a line have none and reach any height."""
    found = [(attack["height"], name, attack["shape"]) for name in names
             for attack in (kinds.get(name) or {}).get("attacks") or [] if attack.get("height") is not None]
    return min(found) if found else None


def check_level_file(file, level, layouts, ctx, expect):
    """`file` is the level file as it stands, `level` what StageFlow.Resolve makes of it (None when
    it cannot be resolved)."""
    name = file["id"]
    layout = layouts.get(file["layout"])
    expect(layout is not None, f"{name}: its layout {file['layout']} exists")
    expect(level is not None, f"{name}: it resolves to a level (stages, difficulties and a crowd block, or a mission "
           f"that has a crowd block)")
    if layout is None or level is None:
        return
    kinds = ctx["kinds"]
    # Ruling 6 of the fix round, the reading StageFlow.Validate and the simulator share
    # (sim_range.level_problems): zero and empty mean the same on both sides.
    problems = sr.level_problems(level, layout, ctx["levels"], kinds, ctx["ranks"], ctx["crowdMaxAlive"])
    expect(not problems, f"{name}: maxAlive is an integer of at least 1 wherever it appears, burst is at least 1, "
           f"every camp's targetWaveSeconds is over 0 and its breatherSeconds is not under 0, no camp is without a "
           f"wave, Combat.json has every `levels` number a run reads, and StageFlow.Validate's L1b lines hold"
           + (": " + "; ".join(problems) if problems else ""))
    if file.get("mission"):
        expect(bool(layout.get("arena")), f"{name}: a level that names a mission ({file['mission']}) names an arena "
               f"layout ({layout.get('arena')})")
        # Not a gate: the arena's numbers stay where they are (ruling 27). Its cover is held to
        # no height here; this says how it stands against the fix round's ruling 3.
        tops = [top for camp in layout["camps"] for top in camp.get("obstacleTops") or []]
        names = [kind for stage in level["stages"] if stage["kind"] == "camp" for kind in fielded(stage, kinds)]
        low = ground_reach(names, kinds)
        if tops and low is not None:
            print(f"  note  {name}: the arena's cover is not gated (its numbers are frozen): {len(tops)} obstacles, the "
                  f"tallest {max(tops):g} studs, against its lowest ground attack, the {low[1]}'s {low[2]} at {low[0]:g} "
                  f"({'a body on it is still hit, with no margin' if max(tops) <= low[0] else 'a body on it is out of reach'}"
                  f"; a level's own camps keep {COVER_MARGIN:g} under)")
        return
    # The simulator does not mirror the director's elite (WaveService picks it per wave): a level
    # file that names one would be played with bodies no band has measured.
    expect("eliteKind" not in (file.get("crowd") or {}),
           f"{name}: its crowd block names no eliteKind (the simulators do not mirror the director's elite)")
    stages = level["stages"]
    turn = all(s["kind"] == ("camp" if (i % 2 == 1 or len(stages) == 1) else "travel") for i, s in enumerate(stages))
    expect((turn or all(s["kind"] == "camp" for s in stages[:1]) and len(stages) == 1) and stages[-1]["kind"] == "camp",
           f"{name}: its stages are travel and camp in turn and end in a camp: "
           + ", ".join(s["kind"] for s in stages))
    camps = {c["id"]: c for c in layout["camps"]}
    zones = [s.get("zone") for s in stages if s["kind"] == "camp"]
    locking = [c["id"] for c in layout["camps"] if c.get("locks") is True]
    wanted = (EXPECTED.get(level["layout"]) or {}).get("locks")
    expect(zones == locking and (wanted is None or locking == wanted),
           f"{name}: its camp stages name exactly the layout's camps that lock (L1b-12), in the route's order, each "
           f"once: stages {', '.join(map(str, zones)) or 'none'}, locking {', '.join(locking) or 'none'}"
           + (f" (wanted {', '.join(wanted)})" if wanted is not None else ""))
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
        # The L1c fix round's M3: a camp's own countdown. Under levels.gateSeconds' floor (which
        # lets the client learn the floor before the first body) only where the close brings no
        # body: a first wave with no group and no boss, in a camp whose residents stand there
        # (drawn, floor and all, from the run's start).
        countdown = stage.get("gateSeconds")
        if countdown is not None:
            first = (stage.get("waves") or [{}])[0]
            empty = not first.get("groups") and not first.get("boss")
            held = camp.get("locks") is True and any(
                c.get("id") == camp["id"] and c.get("residents") for c in level.get("camps") or [])
            expect(is_number(countdown) and countdown >= 0 and (countdown >= GATE_FLOOR or (empty and held)),
                   f"{tag} its own gateSeconds {countdown} is 0 or more, and under {GATE_FLOOR:g} only when its first "
                   f"wave brings no body (no group, no boss) and its residents already stand on its floor: first wave "
                   f"{'empty' if empty else 'not empty'}, residents {'held there' if held else 'none'}")
        alive = stage["maxAlive"] if stage.get("maxAlive") is not None else level["crowd"]["maxAlive"]
        area = camp["sx"] * camp["sz"]
        expect(alive <= area / DENSITY_AREA + EPS and alive <= ctx["crowdMaxAlive"],
               f"{tag} maxAlive {alive:g} is at most its floor area / {DENSITY_AREA:g} ({area / DENSITY_AREA:.1f}) and "
               f"the crowd's {ctx['crowdMaxAlive']}")
        widest = max((kinds[k]["radius"] for k, boss in named if k in kinds and not boss), default=ctx["widest"])
        ctx["campRadius"][(level["layout"], camp["id"])] = widest
        # Cover is low (fix round, ruling 3): whoever stands on it is still in reach of every
        # ground attack this camp fields. A fence is not cover: the closed camp's invisible wall
        # stands on the floor's edge, so nobody is on a fence while anything is alive.
        low = ground_reach(fielded(stage, kinds), kinds)
        limit = min(COVER_MAX, low[0] - COVER_MARGIN) if low is not None else COVER_MAX
        tops = [o["sy"] for o in camp.get("obstacles") or []]
        expect(all(top <= limit + EPS for top in tops),
               f"{tag} every standable top on its floor is at most {limit:g} studs up ({COVER_MAX:g}, and "
               f"{COVER_MARGIN:g} under its lowest ground attack"
               + (f", the {low[1]}'s {low[2]} at {low[0]:g}" if low is not None else ": none")
               + f"): {len(tops)} obstacles, the tallest {max(tops, default=0):g}")
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
    check_residents(name, level, layout, ctx, expect)


def rect_distance(x, z, x0, x1, z0, z1):
    """The flat distance from (x, z) to a rectangle (0 inside it)."""
    return math.hypot(max(x0 - x, 0.0, x - x1), max(z0 - z, 0.0, z - z1))


def obstacle_rects(camp):
    return [(o["x"] - o["sx"] / 2, o["x"] + o["sx"] / 2, o["z"] - o["sz"] / 2, o["z"] + o["sz"] / 2, i + 1)
            for i, o in enumerate(camp.get("obstacles") or [])]


def loop_samples(points, step=PATROL_SAMPLE):
    """Points every `step` studs round a closed loop of (x, y, z) points: [(x, z, the leg's yaw)]."""
    found = []
    for index, a in enumerate(points):
        b = points[(index + 1) % len(points)]
        run = math.hypot(b[0] - a[0], b[2] - a[2])
        yaw = sr.cb_yaw_toward(b[0] - a[0], b[2] - a[2]) if run > EPS else 0.0
        cuts = max(int(run / step), 1)
        for k in range(cuts + 1):
            found.append((a[0] + (b[0] - a[0]) * k / cuts, a[2] + (b[2] - a[2]) * k / cuts, yaw))
    return found


def resting_eyes(defn):
    """Every place a member of a group can stand while it rests, as a CampBrain.Sees member: its
    posts, and for a patrol every point of its loop, facing along the leg."""
    count = sum(unit["count"] for unit in defn["units"])
    eyes = [{"at": post["at"], "post": post} for post in sr.cb_posts(defn, count)]
    if defn["posture"] == "patrol":
        for x, z, yaw in loop_samples(defn["points"]):
            post = {"at": (x, defn["floorY"], z), "yaw": yaw, "leg": 0}
            eyes.append({"at": post["at"], "post": post})
    return eyes


def check_residents(name, level, layout, ctx, expect):
    """The L1b Wave 1 gates on a level's residents (docs/INTERFACES.md "L1b contracts" -> "Config",
    the gates table): residents per camp, postures, posts, patrols, fires, guard spots, the open
    camps' checkpoints, camps.chaseMargin, keepAway bands and cover in the open camps, and the
    population at every difficulty (L1b-11)."""
    kinds, ranks, rules = ctx["kinds"], ctx["ranks"], ctx["camps"]
    if rules is None or sr.cb_problems(rules):
        return  # check_rules names what is wrong with Combat.json camps
    spec = EXPECTED.get(level["layout"]) or {}
    camps = layout["camps"]
    difficulties = list(level["difficulties"])
    top = max((ranks.get(d, 0) for d in difficulties), default=0)
    groups, residents = sr.groups_of(level, layout, top, ranks)
    caps = {}
    for stage in level["stages"]:
        if stage["kind"] == "camp":
            caps[stage.get("zone")] = stage["maxAlive"] if stage.get("maxAlive") is not None else level["crowd"]["maxAlive"]
    solids = solids_of(layout, ctx["levels"]["fenceThickness"], ctx["levels"]["floorThickness"])

    def widest(defn):
        return max((kinds[u["kind"]]["radius"] for u in defn["units"] if u["kind"] in kinds), default=ctx["widest"])

    # Residents per camp, at the highest difficulty; a camp that locks at every difficulty (L1c-4).
    for camp in camps:
        cid = camp["id"]
        n = residents.get(cid, 0)
        area = camp["sx"] * camp["sz"]
        dense = n <= area / DENSITY_AREA + EPS
        if camp.get("locks") is True:
            bands = spec.get("lockedResidents") or {}
            cap = caps.get(cid)
            each = {d: sr.groups_of(level, layout, ranks.get(d, 0), ranks)[1].get(cid, 0) for d in difficulties}
            ok = dense and cap is not None and all(
                bands.get(d, (0, math.inf))[0] <= m <= bands.get(d, (0, math.inf))[1] and m < cap for d, m in each.items())
            band = (f"under its stage's maxAlive {cap}, per difficulty: "
                    + ", ".join(f"{d} {m} (band {bands[d][0]}-{bands[d][1]})" if d in bands else f"{d} {m} (any)"
                                for d, m in each.items()))
        elif cid in (spec.get("residents") or {}):
            lo, hi = spec["residents"][cid]
            ok = dense and lo <= n <= hi
            band = f"{lo}-{hi}"
        else:
            ok, band = dense, "any"
        expect(ok, f"{name} camp {cid}: {n} residents at the highest difficulty ({band}; at most its floor area / "
               f"{DENSITY_AREA:g} = {area / DENSITY_AREA:.0f})")

    # Postures: every open camp a fire and a guard group, the level a patrol, on every difficulty.
    for difficulty in difficulties:
        defs, _res = sr.groups_of(level, layout, ranks.get(difficulty, 0), ranks)
        for camp in camps:
            if camp.get("locks") is True:
                continue
            held = {d["posture"] for d in defs if d["camp"] == camp["id"]}
            if not {"fire", "guard"} <= held:
                expect(False, f"{name} camp {camp['id']} (open) on {difficulty} holds a fire group and a guard group: "
                       f"{', '.join(sorted(held)) or 'none'}")
        if not any(d["posture"] == "patrol" for d in defs):
            expect(False, f"{name} on {difficulty}: at least one patrol group")
    expect(True, f"{name}: every open camp holds a fire group and a guard group, and the level a patrol, on every "
           f"difficulty (" + ", ".join(f"{d['id']} {d['posture']}" for d in groups) + ")")

    # Posts, patrols, fires and guard spots, at every difficulty (a fire's bearings move with its count).
    bad = []
    for difficulty in difficulties:
        defs, _res = sr.groups_of(level, layout, ranks.get(difficulty, 0), ranks)
        for defn in defs:
            camp = next(c for c in camps if c["id"] == defn["camp"])
            x0, x1, z0, z1 = camp_rect(camp)
            r = widest(defn)
            spare = r + POST_SPARE
            members = sum(u["count"] for u in defn["units"])
            covers = obstacle_rects(camp)
            where = f"{difficulty} {defn['id']}"
            if defn["posture"] == "guard" and members > len(defn["points"]):
                bad.append(f"{where}: {members} guards on {len(defn['points'])} points")
                continue

            def placed(x, z, what):
                inside = min(x - x0, x1 - x, z - z0, z1 - z)
                if inside < spare - EPS:
                    bad.append(f"{where}: {what} at ({x:g}, {z:g}) is {inside:.2f} inside its floor (needs {spare:g})")
                for cx0, cx1, cz0, cz1, k in covers:
                    away = rect_distance(x, z, cx0, cx1, cz0, cz1)
                    if away < spare - EPS:
                        bad.append(f"{where}: {what} at ({x:g}, {z:g}) is {away:.2f} from obstacle {k} (needs {spare:g})")

            posts = sr.cb_posts(defn, members)
            for k, post in enumerate(posts, 1):
                placed(post["at"][0], post["at"][2], f"post {k}")
            if defn["posture"] == "patrol":
                for x, z, _yaw in loop_samples(defn["points"]):
                    placed(x, z, "its loop")
            if defn["posture"] == "fire" and len(posts) > 1:
                gap = min(math.hypot(posts[k]["at"][0] - posts[k - 1]["at"][0], posts[k]["at"][2] - posts[k - 1]["at"][2])
                          for k in range(len(posts)))
                if gap < 2 * r + FIRE_SPARE - EPS:
                    bad.append(f"{where}: neighbours round the fire {gap:.2f} apart (needs {2 * r + FIRE_SPARE:g})")
                cx, _cy, cz = defn["points"][0]
                for k in range(72):
                    a = 2 * math.pi * k / 72
                    px, pz = cx - math.sin(a) * defn["radius"], cz - math.cos(a) * defn["radius"]
                    if any(rect_distance(px, pz, cx0, cx1, cz0, cz1) < r - EPS for cx0, cx1, cz0, cz1, _k in covers):
                        bad.append(f"{where}: the fire's circle runs into cover")
                        break
    expect(not bad, f"{name}: every post is its group's widest radius + {POST_SPARE:g} inside its floor and off every "
           f"obstacle, every patrol leg too; neighbours round a fire are 2 radii + {FIRE_SPARE:g} apart and its circle "
           f"is clear of cover; a guard spot has a point per member (every difficulty)"
           + (": " + "; ".join(bad[:4]) if bad else f" ({len(groups)} groups at the highest difficulty)"))

    # The open camps' checkpoints: off the floor, on the road's ground, seen by no resting member.
    for camp in camps:
        if camp.get("locks") is True:
            continue
        mark = camp.get("checkpoint")
        x0, x1, z0, z1 = camp_rect(camp)
        if mark is None:
            expect(False, f"{name} camp {camp['id']} (open) has a checkpoint")
            continue
        off = not (x0 - EPS <= mark["x"] <= x1 + EPS and z0 - EPS <= mark["z"] <= z1 + EPS)
        top, under = ground(solids, mark["x"], mark["z"], camp["y"] + CHECKPOINT_RISE, kinds=("block",))
        held = top is not None and abs(top - camp["y"]) <= CHECKPOINT_RISE + EPS
        root = {"userId": 1, "root": (mark["x"], (top if top is not None else camp["y"]) + sr.ROOT_HEIGHT, mark["z"])}
        seen = []
        closest = (math.inf, None)
        for difficulty in difficulties:
            defs, _tents = all_defs(level, layout, ranks.get(difficulty, 0), ranks)  # tents included
            for defn in defs:
                sight = sr.cb_posture(defn, rules)["sight"]
                for member in resting_eyes(defn):
                    d = math.hypot(member["at"][0] - mark["x"], member["at"][2] - mark["z"])
                    if sr.cb_sees(defn, member, root, rules):
                        seen.append(f"{difficulty} {defn['id']} at ({member['at'][0]:g}, {member['at'][2]:g})")
                    elif d - sight < closest[0]:
                        closest = (d - sight, defn["id"], d, sight)
        expect(off and held, f"{name} camp {camp['id']} (open): its checkpoint ({mark['x']:g}, {mark['z']:g}) is off "
               f"its floor, on a ground block whose top is within {CHECKPOINT_RISE:g} of the floor's {camp['y']:g}"
               + (f" ({under.name}, top {top:g})" if held else f" (off the floor: {off}; ground top {top})"))
        expect(not seen, f"{name} camp {camp['id']} (open): no resting member of any group sees its checkpoint "
               f"(CampBrain.Sees, cone included, a patrol anywhere on its loop, every difficulty)"
               + (": " + "; ".join(seen[:3]) if seen else
                  (f" (the nearest eye: {closest[1]} at {closest[2]:.1f} studs, "
                   + (f"inside its sight {closest[3]:g} but outside its cone)" if closest[0] <= 0
                      else f"{closest[0]:.1f} past its sight {closest[3]:g})") if closest[1] else "")))

    # The open camps' checkpoints out of every resident shooter's reach (fix round, data Minor 1):
    # a checkpoint a keepAway resident reaches from its post (a patrol: anywhere on its loop) is in
    # play for that group, so the safe point would put a fallen player under fire with no i-frames.
    # Where a fighting shooter has walked to is StageFlow.SafePoint's business (it skips a
    # checkpoint a busy group's living shooter reaches); this gate holds the resting layout.
    for camp in camps:
        mark = camp.get("checkpoint")
        if camp.get("locks") is True or mark is None:
            continue
        hits, nearest = [], None
        for difficulty in difficulties:
            defs, _tents = all_defs(level, layout, ranks.get(difficulty, 0), ranks)  # tents included
            for defn in defs:
                count = sum(u["count"] for u in defn["units"])
                posts = sr.cb_posts(defn, count)
                k = 0
                for unit in defn["units"]:
                    for _n in range(unit["count"]):
                        post = posts[k]
                        k += 1
                        kind = kinds.get(unit["kind"]) or {}
                        if kind.get("brain") != "keepAway":
                            continue
                        far = max((a["reach"] for a in kind.get("attacks") or [] if a.get("reach") is not None),
                                  default=0.0)
                        spots = [(post["at"][0], post["at"][2])]
                        if defn["posture"] == "patrol":
                            spots += [(x, z) for x, z, _yaw in loop_samples(defn["points"])]
                        d = min(math.hypot(x - mark["x"], z - mark["z"]) for x, z in spots)
                        spare = d - far
                        if spare <= EPS:
                            hits.append(f"{difficulty} {defn['id']} {unit['kind']} ({far:g}) {d:.1f} away")
                        elif nearest is None or spare < nearest[0]:
                            nearest = (spare, f"{difficulty} {defn['id']} {unit['kind']}", d, far)
        expect(not hits, f"{name} camp {camp['id']} (open): its checkpoint ({mark['x']:g}, {mark['z']:g}) lies beyond "
               f"every resident shooter's attack reach from its post (a patrol's: its loop), every difficulty"
               + (": " + "; ".join(hits[:4]) if hits else
                  (f" (the nearest: {nearest[1]} {nearest[2]:.1f} away, reach {nearest[3]:g})" if nearest else " (none)")))

    # camps.chaseMargin against the rushers of the open camps (L1b-7's farm). In-play has rounded
    # corners (fix round, crowd Major 1): a rusher clamped radius inside both edges of a corner is
    # sqrt(2) x radius from it, so it reaches a player chaseMargin off the corner only when
    # chaseMargin <= reach - sqrt(2) x radius (an edge needs reach - radius, which this covers).
    locking = {c["id"] for c in camps if c.get("locks") is True}
    reach = []
    for difficulty in difficulties:
        defs, _tents = all_defs(level, layout, ranks.get(difficulty, 0), ranks)  # tents included
        rushers = sorted({u["kind"] for d in defs if d["camp"] not in locking for u in d["units"]
                          if u["kind"] in kinds and kinds[u["kind"]].get("brain") != "keepAway"})
        for kind in rushers:
            attacks = [a for a in kinds[kind].get("attacks") or [] if a.get("reach") is not None]
            if attacks:
                shortest = min(attacks, key=lambda a: a["reach"])
                reach.append((shortest["reach"] - math.sqrt(2) * kinds[kind]["radius"], kind, shortest["shape"],
                              difficulty))
    limit = min(reach) if reach else None
    margin = rules["chaseMargin"]
    expect(limit is None or margin <= limit[0] + EPS,
           f"{name}: camps.chaseMargin {margin:g} is at most the smallest reach - sqrt(2) x radius of the shortest "
           f"attack of every rusher resident in an open camp, every difficulty (a body clamped in a floor's corner)"
           + (f" (the {limit[1]}'s {limit[2]} on {limit[3]}: {limit[0]:.2f})" if limit else " (none)"))

    # Perches by an open camp: a standable top (a block, a fence, an obstacle, a secret, another
    # floor) within chaseMargin of the floor on the flat whose standing root is in the height
    # band is in play, so the camp's rushers' ground shapes must reach feet on it.
    in_region = {cid for region in layout.get("regions") or [] for cid in region.get("camps") or []}
    for camp in camps:
        if camp.get("locks") is True or camp["id"] in in_region:
            continue  # L1b-W4-19: a region camp has the meleeAbove and sniper-perch gates instead
        cx0, cx1, cz0, cz1 = camp_rect(camp)
        names = sorted({u["kind"] for difficulty in difficulties
                        for d in all_defs(level, layout, ranks.get(difficulty, 0), ranks)[0]
                        if d["camp"] == camp["id"] for u in d["units"]
                        if u["kind"] in kinds and kinds[u["kind"]].get("brain") != "keepAway"})
        low = ground_reach(names, kinds)
        if low is None:
            continue
        highest = low[0] - COVER_MARGIN
        floor_name = f"Camp_{camp['id']}_Floor"
        perches = []
        for solid in solids:
            if solid.name == floor_name:
                continue
            gap = math.hypot(max(cx0 - solid.x1, solid.x0 - cx1, 0.0), max(cz0 - solid.z1, solid.z0 - cz1, 0.0))
            if gap > margin + EPS:
                continue
            rise = solid.top - camp["y"]
            in_band = -rules["sightBelow"] - EPS <= rise + sr.ROOT_HEIGHT <= rules["sightAbove"] + EPS
            if in_band and rise > highest + EPS:
                perches.append(f"{solid.name} top {rise:g} up, {gap:.2f} off the floor")
        expect(not perches, f"{name} camp {camp['id']} (open): every standable top within chaseMargin {margin:g} of its "
               f"floor whose root is in the height band stands at most {highest:g} over the floor (the {low[1]}'s "
               f"{low[2]} height {low[0]:g} - {COVER_MARGIN:g}; fences and obstacles included)"
               + (": " + "; ".join(perches[:4]) if perches else ""))

    # keepAway bands and cover in the open camps (the locking camp keeps its stage's gates).
    for camp in camps:
        if camp.get("locks") is True:
            continue
        names = sorted({u["kind"] for d in groups if d["camp"] == camp["id"] for u in d["units"] if u["kind"] in kinds})
        short = min(camp["sx"], camp["sz"])
        tight = [f"{k} (bandMin {kinds[k]['bandMin']:g})" for k in names
                 if kinds[k].get("brain") == "keepAway" and kinds[k].get("bandMin", 0) > BAND_SHARE * short]
        expect(not tight, f"{name} camp {camp['id']} (open): every resident keepAway kind's bandMin is at most "
               f"{BAND_SHARE:g} x its shorter side ({BAND_SHARE * short:.1f})" + (": " + ", ".join(tight) if tight else ""))
        low = ground_reach(names, kinds)
        highest = min(COVER_MAX, low[0] - COVER_MARGIN) if low is not None else COVER_MAX
        tops = [o["sy"] for o in camp.get("obstacles") or []]
        expect(all(t <= highest + EPS for t in tops),
               f"{name} camp {camp['id']} (open): every standable top on its floor is at most {highest:g} studs up: "
               f"{len(tops)} obstacles, the tallest {max(tops, default=0):g}")

    # L1b-W2-5 at every difficulty, as StageFlow.Validate reads it.
    reserve = sr.boss_reserve(level, kinds)
    rows = []
    over = []
    for difficulty in difficulties:
        _defs, res = sr.groups_of(level, layout, ranks.get(difficulty, 0), ranks)
        _tents, stocks = sr.tents_of(level, layout, ranks.get(difficulty, 0), ranks)
        population = sr.population_of(res, sum(stocks.values()), caps, reserve)
        room = max([0] + [cap - res.get(cid, 0) for cid, cap in caps.items()])
        if population > ctx["crowdMaxAlive"]:
            over.append(f"{difficulty}: {population} > {ctx['crowdMaxAlive']}")
        rows.append(f"{difficulty} {population} = residents {sum(res.values())} ("
                    + ", ".join(f"{c['id']} {res.get(c['id'], 0)}" for c in camps) + f") + tents {sum(stocks.values())} ("
                    + ", ".join(f"{k} {v}" for k, v in stocks.items()) + f") + room {room} + boss reserve {reserve}")
    ctx["gate16"].setdefault(level["layout"], {})["population"] = rows
    expect(not over, f"{name}: the population (every resident, every tent's stock, the boss room's cap over its "
           f"residents, the boss reserve {reserve} = 1 + its largest summon) is at most crowd.maxAlive "
           f"{ctx['crowdMaxAlive']} at every difficulty (L1b-W2-5): " + "; ".join(over or rows))
    check_wave2(name, level, layout, ctx, expect, caps, solids)
    check_wave4(name, level, layout, ctx, expect, solids)
    check_walled(name, level, layout, ctx, expect, solids)


def rect_gap(a, b):
    """The flat distance between two rectangles (x0, x1, z0, z1): 0 when they touch or overlap."""
    return math.hypot(max(a[0] - b[1], b[0] - a[1], 0.0), max(a[2] - b[3], b[2] - a[3], 0.0))


def cell_box(cell):
    return cell["x"] - cell["hx"], cell["x"] + cell["hx"], cell["z"] - cell["hz"], cell["z"] + cell["hz"]


def shape_extent(attack):
    """How far a ground shape reaches on the flat from its body's centre (CrowdBrain's shapes): a
    lunge's box `range` long and `width` wide, an arc's `range`, a lane's half width off the line
    the body runs (the run itself stays on the region), a ring's `radius`."""
    shape = attack["shape"]
    if shape == "lunge":
        return math.hypot(attack.get("range") or 0, (attack.get("width") or 0) / 2)
    if shape == "arc":
        return attack.get("range") or 0
    if shape == "lane":
        return (attack.get("width") or 0) / 2
    if shape == "ring":
        return attack.get("radius") or 0
    return 0.0


def shape_holds(above, height):
    """VitalsService / ThreatField's height rule, feet `above` the crowd's floor (R6, R15)."""
    return above <= height + EPS and (not UNDER_SIDE or above >= -height - EPS)


def standable_points(solids, solid, step):
    """The points of a solid's top a player stands on (nothing standable over them there), on a
    `step` grid and its edges."""
    kinds = ("block", "floor", "secret", "fence", "obstacle")
    xs = [solid.x0 + step * k for k in range(int((solid.x1 - solid.x0) / step) + 1)] + [solid.x1]
    zs = [solid.z0 + step * k for k in range(int((solid.z1 - solid.z0) / step) + 1)] + [solid.z1]
    near = [o for o in solids if o is not solid and o.kind in kinds and o.top > solid.top + EPS
            and o.x0 <= solid.x1 and o.x1 >= solid.x0 and o.z0 <= solid.z1 and o.z1 >= solid.z0]
    return [(x, z) for x in xs for z in zs if not any(o.holds(x, z) for o in near)]


def region_defn(region, layout):
    """A region group as CampBrain.Melee reads it: its floor's height and its cells."""
    return {"floorY": region["y"], "region": sr.region_cells(layout, region)}


def sniper_spots(level, layout, ctx, solids):
    """R8: every standable top that no rusher of a region reaches (CampBrain.Melee is false for a
    player standing there: off the region by more than chaseMargin, over meleeAbove, under
    meleeBelow, or out of the height band) and that lies within the Longbow's range of the region
    (its camps' floors and the road its groups chase over). A locking camp's own floor, fence and
    cover are left out (INTERFACES "Open for later": shooting out of the boss room). One spot per
    solid: its name, its region, the open camp of the region whose floor is nearest, how many
    points, the box of those points, and the point of them nearest the region (where a straight
    sniper course stands). tools/sim_range.py rates a course from every spot this returns."""
    rules = ctx["camps"]
    reach = ctx["longbow"]
    rooms = tuple(f"Camp_{c['id']}_" for c in layout["camps"] if c.get("locks") is True)
    camps = {c["id"]: c for c in layout["camps"]}
    if "move" not in ctx or "abilityHeight" not in ctx:
        proving = sr.load_config(sr.CONFIG_PATH)
        ctx = dict(ctx, move=proving["movement"], abilityHeight=ability_height(proving))
    tall = unclimbable(solids, ctx["move"], ctx["abilityHeight"])  # L1c-3: nobody stands on these
    spots = []
    for region in layout.get("regions") or []:
        defn = region_defn(region, layout)
        rects = defn["region"]
        open_camps = [camps[cid] for cid in region.get("camps") or [] if cid in camps and not camps[cid].get("locks")]
        if not open_camps:
            continue
        for solid in solids:
            if (solid.kind not in ("block", "floor", "secret", "fence", "obstacle") or solid.name.startswith(rooms)
                    or solid.name in tall):
                continue
            box = (solid.x0, solid.x1, solid.z0, solid.z1)
            if min(rect_gap(box, cell_box(c)) for c in rects) > reach + EPS:
                continue
            found = []
            for x, z in standable_points(solids, solid, SPOT_STEP):
                gap = sr.rg_distance(rects, x, z)
                if gap > reach + EPS:
                    continue
                stood = solid.top + sr.ROOT_HEIGHT  # standing on it: rests where his root is (R16)
                if sr.cb_melee(defn, {"userId": 1, "root": (x, stood, z), "rest": stood}, rules):
                    continue
                found.append((gap, x, z))
            if not found:
                continue
            gap, x, z = min(found)
            camp = min(open_camps, key=lambda c: rect_distance(x, z, *camp_rect(c)))
            spots.append({"id": solid.name, "region": region["id"], "camp": camp["id"], "top": solid.top,
                          "points": len(found), "at": (x, solid.top, z), "gap": gap,
                          "box": (min(f[1] for f in found), max(f[1] for f in found),
                                  min(f[2] for f in found), max(f[2] for f in found))})
    return spots


def check_wave4(name, level, layout, ctx, expect, solids):
    """The L1b Wave 4 gates (INTERFACES "L1b Wave 4" -> "Config", the gates table): the regions'
    data as StageFlow.Validate reads it, standable cells, doors and the tree, fences crossed only at
    a gate, the lock clearance, camps.meleeAbove's range, the region's corners, the sniper perches,
    N's approaches and the tents' pace keys."""
    kinds, ranks, rules = ctx["kinds"], ctx["ranks"], ctx["camps"]
    levels = ctx["levels"]
    facts = ctx["gate16"].setdefault(level["layout"], {})
    difficulties = list(level["difficulties"])
    camps = {c["id"]: c for c in layout["camps"]}
    locking = [c for c in layout["camps"] if c.get("locks") is True]
    regions = layout.get("regions") or []
    spec = EXPECTED.get(level["layout"]) or {}
    lines = []
    sr.region_problems(level, layout, levels, kinds, lines.append)
    expect(not lines, f"{name}: the regions and approaches as StageFlow.Validate reads them (L1b-W4-14 to -16, -31; "
           f"sim_range.region_problems)" + (": " + "; ".join(lines[:4]) if lines else f" ({len(regions)} region(s))"))
    if spec.get("regions") and len(regions) != spec["regions"]:
        expect(False, f"{name}: {spec['regions']} chase region(s) (ruling 1): {len(regions)}")
    rows = facts.setdefault("regions", [])
    for region in regions:
        rid = region.get("id")
        y = region["y"]
        rects = sr.region_cells(layout, region)
        ids = [f"{cid} floor" for cid in [c["id"] for c in layout["camps"] if c["id"] in (region.get("camps") or [])]]
        ids += [cell["id"] for cell in region.get("cells") or []]
        widest = sr.region_widest(level, region, kinds)
        min_door = 2 * widest + levels["doorSpare"]
        # Standable: every point of every cell on a ground or path block or a camp floor whose top is
        # the region's height (and nothing standable over it at that height).
        bad = []
        for cid, cell in zip(ids, rects):
            x0, x1, z0, z1 = cell_box(cell)
            xs = [x0 + CELL_STEP * k for k in range(int((x1 - x0) / CELL_STEP) + 1)] + [x1]
            zs = [z0 + CELL_STEP * k for k in range(int((z1 - z0) / CELL_STEP) + 1)] + [z1]
            for x in xs:
                for z in zs:
                    top, under = ground(solids, x, z, y + EPS, kinds=("block", "floor"))
                    if top is None or abs(top - y) > EPS or (under.kind == "block" and under.look not in ("ground", "path")):
                        bad.append(f"{cid} at ({x:g}, {z:g}): ground {top}")
                        break
                else:
                    continue
                break
        rows.append(f"{rid}: y {y:g}, {len(rects)} cells: " + ", ".join(
            f"{cid} x {c['x'] - c['hx']:g}..{c['x'] + c['hx']:g} z {c['z'] - c['hz']:g}..{c['z'] + c['hz']:g}"
            for cid, c in zip(ids, rects)))
        expect(not bad, f"{name} region {rid}: every point of every cell (a {CELL_STEP:g}-stud grid and the corners) "
               f"lies on a ground or path block or a camp floor whose top is the region's {y:g}"
               + (": " + "; ".join(bad[:4]) if bad else f" ({len(rects)} cells)"))
        # Doors and the tree.
        doors, odd = [], []
        pairs = 0
        for i in range(len(rects)):
            for j in range(i + 1, len(rects)):
                wx, wz, _c = sr.rg_overlap(rects[i], rects[j])
                touch = abs(wx) <= EPS or abs(wz) <= EPS
                if wx > EPS and wz > EPS:
                    pairs += 1
                    doors.append(f"{ids[i]}/{ids[j]} {wx:g} x {wz:g}")
                    if wx < min_door - EPS or wz < min_door - EPS:
                        odd.append(f"{ids[i]}/{ids[j]} {wx:g} x {wz:g}")
                elif touch and wx >= -EPS and wz >= -EPS:
                    doors.append(f"{ids[i]}/{ids[j]} touch (no door)")
        graph = sr.rg_build(rects)
        loose = [ids[j - 1] for j in range(1, len(rects) + 1) if graph["hops"][1][j] == math.inf]
        tree = not loose and pairs == len(rects) - 1
        rows.append(f"{rid} doors (at least {min_door:g} on both axes = 2 x {widest:g} + {levels['doorSpare']:g}): "
                    + ", ".join(doors))
        expect(tree and not odd, f"{name} region {rid}: neighbours by positive overlap form a tree ({pairs} doors for "
               f"{len(rects)} cells) and every door is at least 2 x the widest body {widest:g} + doorSpare "
               f"{levels['doorSpare']:g} = {min_door:g} on both axes (L1b-W4-15)"
               + (f": not connected {', '.join(loose)}" if loose else "")
               + (f": a cycle ({pairs} doors)" if not loose and not tree else "")
               + (f": narrow {'; '.join(odd)}" if odd else ""))
        # Fences: a cell crosses a camp's fence line only within one of its gate spans.
        crossings, bad = [], []
        thickness = levels["fenceThickness"]
        for cid, cell in zip(ids, rects):
            box = cell_box(cell)
            for camp in layout["camps"]:
                if not camp.get("fence"):
                    continue
                for side, strip in fence_strips(camp, thickness).items():
                    ox0, ox1 = max(box[0], strip[0]), min(box[1], strip[1])
                    oz0, oz1 = max(box[2], strip[2]), min(box[3], strip[3])
                    if ox1 - ox0 <= EPS or oz1 - oz0 <= EPS:
                        continue
                    lo, hi = (oz0, oz1) if side in ("west", "east") else (ox0, ox1)
                    spans = [gate_rect(camp, g, thickness) for g in camp.get("gates") or [] if g["side"] == side]
                    spans = [(g[2], g[3]) if side in ("west", "east") else (g[0], g[1]) for g in spans]
                    ok = any(g0 - EPS <= lo and hi <= g1 + EPS for g0, g1 in spans)
                    crossings.append(f"{cid} through camp {camp['id']}'s {side} gate {lo:g}..{hi:g}")
                    if not ok:
                        bad.append(f"{cid} crosses camp {camp['id']}'s {side} fence at {lo:g}..{hi:g}, outside every "
                                   f"gate ({', '.join(f'{a:g}..{b:g}' for a, b in spans) or 'none'})")
        expect(not bad, f"{name} region {rid}: a cell crosses a camp's fence line only within one of its gate spans, so "
               f"a body of radius up to {widest:g} walks a gate, never the palisade (ruling 3)"
               + (": " + "; ".join(bad[:3]) if bad else f": {'; '.join(crossings)}"))
        # The lock clearance (L1b-W4-16).
        reach = sr.region_reach(level, region, kinds)
        least = reach + levels["regionLockMargin"]
        tightest, bad = None, []
        for cid, cell in zip(ids, rects):
            for camp in locking:
                gap = rect_gap(cell_box(cell), camp_rect(camp))
                if tightest is None or gap < tightest[0]:
                    tightest = (gap, cid, camp["id"])
                if gap < least - EPS:
                    bad.append(f"{cid} {gap:g} from camp {camp['id']}")
        if tightest is not None:
            rows.append(f"{rid} lock clearance: the tightest {tightest[1]} {tightest[0]:g} studs from camp {tightest[2]}'s "
                        f"floor (needs {least:g} = the longest reach {reach:g} + {levels['regionLockMargin']:g})")
        expect(not bad, f"{name} region {rid}: every cell is at least the region's longest reach {reach:g} + "
               f"regionLockMargin {levels['regionLockMargin']:g} = {least:g} from every locking camp's floor (L1b-W4-16)"
               + (": " + "; ".join(bad[:3]) if bad else
                  f" (the tightest: {tightest[1]}, {tightest[0]:g} from camp {tightest[2]})" if tightest else " (none locks)"))
        # camps.meleeAbove in its range (L1b-W4-19).
        names = sorted({u for u in sr.region_units(level, region)
                        if u in kinds and kinds[u].get("brain") != "keepAway"})
        low = ground_reach(names, kinds)
        fences = [(camps[cid].get("fence") or {}).get("height") or 0 for cid in region.get("camps") or [] if cid in camps]
        lo = max([COVER_MAX] + fences) + sr.ROOT_HEIGHT
        hi = (low[0] - COVER_MARGIN + sr.ROOT_HEIGHT) if low is not None else math.inf
        melee = rules["meleeAbove"]
        expect(lo - EPS <= melee <= hi + EPS,
               f"{name} region {rid}: camps.meleeAbove {melee:g} lies in [max(COVER_MAX {COVER_MAX:g}, fence "
               f"{max(fences, default=0):g}) + ROOT_HEIGHT {sr.ROOT_HEIGHT:g}, the lowest rusher ground height "
               + (f"({low[1]}'s {low[2]} {low[0]:g})" if low else "(none)")
               + f" - COVER_MARGIN {COVER_MARGIN:g} + ROOT_HEIGHT] = [{lo:g}, {hi:g}]: a melee-reachable player can be hit")
        # The fix round's R14: camps.meleeBelow in [0, min(sightBelow, the lowest rusher ground height
        # - ROOT_HEIGHT - COVER_MARGIN)]: past the band's floor the band refuses first, and every
        # melee-reachable player under the floor stands within every rusher shape's under side (R6).
        below = rules["meleeBelow"]
        top = min(rules["sightBelow"], (low[0] - sr.ROOT_HEIGHT - COVER_MARGIN) if low is not None else math.inf)
        expect(-EPS <= below <= top + EPS,
               f"{name} region {rid}: camps.meleeBelow {below:g} lies in [0, min(sightBelow {rules['sightBelow']:g}, the "
               f"lowest rusher ground height " + (f"({low[1]}'s {low[2]} {low[0]:g})" if low else "(none)")
               + f" - ROOT_HEIGHT {sr.ROOT_HEIGHT:g} - COVER_MARGIN {COVER_MARGIN:g})] = [0, {top:g}] (R14)")
        # The fix round's R6: no standable ground under the region that a rusher's ground shape can
        # still hit (its under side, UNDER_SIDE) while the player there is out of melee reach (his
        # root more than meleeBelow under the floor), within the shape's flat reach less the body's
        # radius of a cell's edge (a body is clamped that far inside its cell).
        cliff, told = [], []
        for kind in names:
            for attack in kinds[kind].get("attacks") or []:
                height = attack.get("height")
                if height is None or attack["shape"] not in ("lunge", "arc", "lane", "ring"):
                    continue
                out = shape_extent(attack) - kinds[kind]["radius"]
                told.append(f"{kind} {attack['shape']} {out:.1f}")
                if out <= 0:
                    continue
                for solid in solids:
                    if solid.kind not in ("block", "floor", "secret", "fence", "obstacle") or solid.top >= y - EPS:
                        continue
                    if min(rect_gap((solid.x0, solid.x1, solid.z0, solid.z1), cell_box(c)) for c in rects) > out + EPS:
                        continue
                    for x, z in standable_points(solids, solid, SPOT_STEP):
                        feet = solid.top - y
                        if feet + sr.ROOT_HEIGHT >= -below - EPS or not shape_holds(feet, height):
                            continue
                        if sr.rg_distance(rects, x, z) <= out + EPS:
                            cliff.append(f"{solid.name} ({x:g}, {solid.top:g}, {z:g}) under {kind}'s {attack['shape']}")
                            break
        expect(not cliff, f"{name} region {rid}: no standable ground under the region, out of melee reach (root more "
               f"than meleeBelow {below:g} under the floor), lies within a rusher ground shape's flat reach less its "
               f"radius of a cell's edge where its height rule (under side {'on' if UNDER_SIDE else 'OFF'}) still holds "
               f"(R6; {', '.join(told)})" + (": " + "; ".join(cliff[:4]) if cliff else ""))
        # The sniper perches (L1b-W4-19): every standable top near the region, in the band and over
        # meleeAbove, lies within the shortest keepAway reach of some region point.
        shooters = [longest for longest in (min((a["reach"] for a in kinds[u].get("attacks") or []
                                                 if a.get("reach") is not None), default=None)
                                            for u in set(sr.region_units(level, region))
                                            if u in kinds and kinds[u].get("brain") == "keepAway") if longest is not None]
        shortest = min(shooters) if shooters else None
        found, bad, boss = [], [], []
        boxes = [cell_box(c) for c in rects]
        # A locking camp's own floor, fence and cover are the boss room: the lock clearance keeps
        # the region out of its residents' reach, and a player standing in it (or on its fence)
        # shooting out is INTERFACES "Open for later" ("Shooting out of the boss room"), listed
        # below, not gated here.
        rooms = tuple(f"Camp_{c['id']}_" for c in locking)
        tall = unclimbable(solids, ctx["move"], ctx["abilityHeight"])  # L1c-3: nobody perches on these
        for solid in solids:
            if solid.kind not in ("block", "fence", "obstacle", "secret", "floor") or solid.name in tall:
                continue
            mine = (solid.x0, solid.x1, solid.z0, solid.z1)
            gap = min(rect_gap(mine, b) for b in boxes)
            if gap > rules["dormantRadius"] + EPS:
                continue
            if solid.name.startswith(rooms):
                root = solid.top - y + sr.ROOT_HEIGHT
                if -rules["sightBelow"] - EPS <= root <= rules["sightAbove"] + EPS and root > melee + EPS:
                    boss.append(f"{solid.name} {gap:.0f} off")
                continue
            root = solid.top - y + sr.ROOT_HEIGHT
            if not (-rules["sightBelow"] - EPS <= root <= rules["sightAbove"] + EPS) or root <= melee + EPS:
                continue
            xs = [solid.x0 + PERCH_STEP * k for k in range(int((solid.x1 - solid.x0) / PERCH_STEP) + 1)] + [solid.x1]
            zs = [solid.z0 + PERCH_STEP * k for k in range(int((solid.z1 - solid.z0) / PERCH_STEP) + 1)] + [solid.z1]
            far = max(sr.rg_distance(rects, x, z) for x in xs for z in zs)
            found.append(f"{solid.name} (top {solid.top:g}, root {root:g} over the floor, {gap:g} off the region, its "
                         f"farthest point {far:.1f} from it)")
            if shortest is None or far > shortest + EPS:
                bad.append(f"{solid.name}: {far:.1f} > {shortest}")
        rows.append(f"{rid} sniper perches (in the band, over meleeAbove {melee:g}, within dormantRadius "
                    f"{rules['dormantRadius']:g}): " + ("; ".join(found) or "none")
                    + (f"; in the boss room, not gated: {', '.join(boss)}" if boss else ""))
        expect(not bad, f"{name} region {rid}: every standable top within dormantRadius {rules['dormantRadius']:g} of the "
               f"region whose standing root is in the band and over meleeAbove lies within the shortest keepAway reach "
               f"{shortest} of the region's kinds of some region point (shooters answer high ground)"
               + (": " + "; ".join(bad[:3]) if bad else f": {'; '.join(found) or 'none'}"))
    # R8: the unreachable sniper spots, every one rated by tools/sim_range.py's straight course;
    # the list is pinned in EXPECTED so a layout change that opens a new spot is seen.
    spots = sniper_spots(level, layout, ctx, solids)
    facts["spots"] = [f"{sp['id']} (camp {sp['camp']}, top {sp['top']:g}, {sp['points']} points, nearest "
                      f"({sp['at'][0]:g}, {sp['at'][2]:g}) {sp['gap']:.1f} off the region)" for sp in spots]
    pinned = spec.get("sniperSpots")
    found = sorted(sp["id"] for sp in spots)
    expect(pinned is None or found == sorted(pinned),
           f"{name}: the unreachable sniper spots (R8: a standable top no rusher reaches, CampBrain.Melee false, within "
           f"the Longbow's {ctx['longbow']:g} of a region; each rated by sim_range's straight course) are the pinned "
           f"list: {', '.join(found) or 'none'}"
           + (f" (pinned: {', '.join(sorted(pinned))})" if pinned is not None and found != sorted(pinned) else ""))
    # N's approaches (L1b-W4-31): only on open camps; standable at their y; farther than sight
    # from every resting place of every open-camp group at every difficulty (cones ignored).
    stops, bad = [], []
    for camp in layout["camps"]:
        approach = camp.get("approach")
        if approach is None:
            continue
        if camp.get("locks") is True:
            bad.append(f"camp {camp['id']} locks and has an approach")
            continue
        top, _under = ground(solids, approach["x"], approach["z"], approach["y"] + EPS, kinds=("block", "floor"))
        if top is None or abs(top - approach["y"]) > EPS:
            bad.append(f"camp {camp['id']}'s approach ({approach['x']:g}, {approach['y']:g}, {approach['z']:g}) stands "
                       f"on ground {top}")
        tightest = None
        for difficulty in difficulties:
            defs, _tents = all_defs(level, layout, ranks.get(difficulty, 0), ranks)
            for defn in defs:
                if defn["held"]:
                    continue
                sight = sr.cb_posture(defn, rules)["sight"]
                for member in resting_eyes(defn):
                    d = math.hypot(member["at"][0] - approach["x"], member["at"][2] - approach["z"]) - sight
                    if tightest is None or d < tightest[0]:
                        tightest = (d, f"{difficulty} {defn['id']}")
                    if d <= EPS:
                        bad.append(f"camp {camp['id']}'s approach is {d + sight:.1f} from {difficulty} {defn['id']} "
                                   f"(sight {sight:g})")
        stops.append(f"{camp['id']} ({approach['x']:g}, {approach['y']:g}, {approach['z']:g})"
                     + (f", {tightest[0]:+.1f} past {tightest[1]}'s sight" if tightest else ""))
    stops += [f"{c['id']} (the countdown)" for c in locking]
    facts["approaches"] = ["N steps to " + ", then ".join(stops)]
    spec_stops = spec.get("approaches")
    expect(not bad and (spec_stops is None or len(stops) - len(locking) == spec_stops),
           f"{name}: N's approaches stand only before open camps, on ground at their height, farther than every "
           f"open-camp group's sight from all its resting places, every difficulty, cones ignored (L1b-W4-31); N steps "
           f"to " + ", then ".join(stops) + (": " + "; ".join(bad[:3]) if bad else ""))
    # The tents' pace (L1b-W4-28).
    bad = []
    told = []
    for config in level.get("camps") or []:
        tent = config.get("tent")
        camp = camps.get(config.get("id"))
        if tent is None or camp is None or camp.get("locks") is True:
            continue
        pace = tent.get("pace")
        if not (isinstance(pace, dict) and sr.finite(pace.get("seconds")) and pace["seconds"] > 0
                and sr.finite(pace.get("lead")) and 0 <= pace["lead"] <= 1):
            bad.append(f"camp {config['id']}: pace {pace}")
        else:
            told.append(f"{config['id']} {pace['seconds']:g} s, lead {pace['lead']:g}")
    expect(not bad, f"{name}: every open camp's tent has a pace with seconds over 0 and lead in [0, 1] (L1b-W4-28)"
           + (": " + "; ".join(bad) if bad else f" ({'; '.join(told) or 'no tent'})"))


# ---------------------------------------------------------------------------------------------
# L1c: the walled boss room (docs/prompts/l1c-contract.md, L1c-1, L1c-3, L1c-6)
# ---------------------------------------------------------------------------------------------


def seg_hits_rect(ax, az, bx, bz, rect):
    """Does the segment a-b pass through the open rectangle (x0, x1, z0, z1)? (Liang-Barsky; a
    segment that only grazes an edge does not.)"""
    x0, x1, z0, z1 = rect
    f0, f1 = 0.0, 1.0
    for p, d, lo, hi in ((ax, bx - ax, x0, x1), (az, bz - az, z0, z1)):
        if abs(d) < EPS:
            if p <= lo + EPS or p >= hi - EPS:
                return False
            continue
        a, c = (lo - p) / d, (hi - p) / d
        f0, f1 = max(f0, min(a, c)), min(f1, max(a, c))
        if f1 - f0 <= EPS:
            return False
    return f1 - f0 > EPS


def wrap(angle):
    """An angle in (-pi, pi]."""
    while angle > math.pi:
        angle -= 2 * math.pi
    while angle <= -math.pi:
        angle += 2 * math.pi
    return angle


def hull_arc(px, pz, corners, ref):
    """The directions from (px, pz) that meet a convex polygon (its corners), as angles relative
    to `ref`: [(lo, hi)] within (-pi, pi], one arc split where it crosses the cut."""
    angles = sorted(wrap(math.atan2(z - pz, x - px) - ref) for x, z in corners)
    gaps = [(angles[(k + 1) % len(angles)] - angles[k]) % (2 * math.pi) for k in range(len(angles))]
    widest = max(range(len(gaps)), key=lambda k: gaps[k])
    lo = angles[(widest + 1) % len(angles)]
    hi = lo + 2 * math.pi - gaps[widest]
    return [(lo, hi)] if hi <= math.pi else [(lo, math.pi), (-math.pi, hi - 2 * math.pi)]


def cut_arcs(arcs, gone):
    """`arcs` less every arc of `gone` (both lists of (lo, hi))."""
    for g0, g1 in gone:
        left = []
        for a0, a1 in arcs:
            if g1 <= a0 or g0 >= a1:
                left.append((a0, a1))
                continue
            if g0 > a0:
                left.append((a0, g0))
            if g1 < a1:
                left.append((g1, a1))
        arcs = left
    return arcs


def gate_faces(camp, gate, thickness):
    """A gate's opening as a sight line crosses it: its outer face, its inner face (segments) and
    the test for a point on the outer side of that face."""
    gx0, gx1, gz0, gz1 = gate_rect(camp, gate, thickness)
    side = gate["side"]
    if side == "north":
        return ((gx0, gz0), (gx1, gz0)), ((gx0, gz1), (gx1, gz1)), (lambda x, z: z < gz0 - EPS)
    if side == "south":
        return ((gx0, gz1), (gx1, gz1)), ((gx0, gz0), (gx1, gz0)), (lambda x, z: z > gz1 + EPS)
    if side == "west":
        return ((gx0, gz0), (gx0, gz1)), ((gx1, gz0), (gx1, gz1)), (lambda x, z: x < gx0 - EPS)
    return ((gx1, gz0), (gx1, gz1)), ((gx0, gz0), (gx0, gz1)), (lambda x, z: x > gx1 + EPS)


def clip_outward(rect, side, face):
    """A wall's footprint less what lies inward of a gate's outer face (a sight line through that
    gate is inside the fenced rectangle past the face): None when nothing is left."""
    x0, x1, z0, z1 = rect
    if side == "north":
        z1 = min(z1, face)
    elif side == "south":
        z0 = max(z0, face)
    elif side == "west":
        x1 = min(x1, face)
    else:
        x0 = max(x0, face)
    return (x0, x1, z0, z1) if x1 - x0 > EPS and z1 - z0 > EPS else None


def visible_arcs(px, pz, camp, gate, thickness, walls):
    """The directions from (px, pz) a sight line takes through a gate's opening into the camp
    without meeting a wall: ([(lo, hi)], ref), angles relative to ref (the direction to the
    opening's middle). The walls are taller than any camera (L1c-1), so this is exact in plan: a
    line into the camp crosses the opening's outer and inner face within the gate; before the
    outer face it must miss every wall's footprint; past it, it is inside the fenced rectangle,
    where no wall stands."""
    outer, inner, outside = gate_faces(camp, gate, thickness)
    if not outside(px, pz):
        return [], 0.0
    mx, mz = (outer[0][0] + outer[1][0]) / 2, (outer[0][1] + outer[1][1]) / 2
    ref = math.atan2(mz - pz, mx - px)
    a = [wrap(math.atan2(z - pz, x - px) - ref) for x, z in outer]
    b = [wrap(math.atan2(z - pz, x - px) - ref) for x, z in inner]
    lo, hi = max(min(a), min(b)), min(max(a), max(b))
    if hi <= lo:
        return [], ref
    face = outer[0][1] if gate["side"] in ("north", "south") else outer[0][0]
    gone = []
    for rect in walls:
        part = clip_outward(rect, gate["side"], face)
        if part is None:
            continue
        corners = ((part[0], part[2]), (part[1], part[2]), (part[1], part[3]), (part[0], part[3]))
        gone += hull_arc(px, pz, corners, ref)
    return cut_arcs([(lo, hi)], gone), ref


def reachable_solids(layout, solids, move, ability, skip, tall):
    """The standable solids a player reaches from the start without entering the camp whose
    pieces start with `skip`: from one to another that lies within stray_reach (falling the drop
    between them) and at most climb_max over it. Walls do not stop a jump here (conservative)."""
    standable = [s for s in solids if s.kind in ("block", "floor", "secret", "fence", "obstacle")
                 and not s.name.startswith(skip) and s.name not in tall]
    start = layout["start"]
    _top, first = ground(solids, start["x"], start["z"], start["y"] + EPS)
    if first is None or first not in standable:
        return []
    climb = climb_max(move, ability)
    seen = {first.name}
    queue = [first]
    while queue:
        here = queue.pop()
        for other in standable:
            if other.name in seen or other.top - here.top > climb + EPS:
                continue
            if here.gap_to(other) <= stray_reach(move, here.top - other.top) + EPS:
                seen.add(other.name)
                queue.append(other)
    return [s for s in standable if s.name in seen]


def walled_bodies(level, layout, ctx, cid):
    """Every resident post of a camp at every difficulty: ({(x, z): (radius, label)}, the plated
    residents, the tallest body of the camp, its boss included)."""
    kinds, ranks = ctx["kinds"], ctx["ranks"]
    bodies, plated, tallest = {}, [], 0.0
    for difficulty in level["difficulties"]:
        defs, _res = sr.groups_of(level, layout, ranks.get(difficulty, 0), ranks)
        for defn in defs:
            if defn["camp"] != cid:
                continue
            for post, kind in zip(sr.group_posts(defn), member_kinds(defn)):
                body = kinds.get(kind) or {}
                key = (round(post["at"][0], 3), round(post["at"][2], 3))
                radius = body.get("radius") or ctx["widest"]
                if radius >= bodies.get(key, (0.0, ""))[0]:
                    bodies[key] = (radius, f"{difficulty} {defn['id']} {kind}")
                tallest = max(tallest, body.get("height") or 0)
                if (body.get("plate") or 0) > 0:
                    plated.append(f"{difficulty} {defn['id']} {kind}")
    for stage in level["stages"]:
        if stage["kind"] == "camp" and stage.get("zone") == cid:
            for wave in stage.get("waves") or []:
                if wave.get("boss") and wave["boss"]["kind"] in kinds:
                    tallest = max(tallest, kinds[wave["boss"]["kind"]].get("height") or 0)
    return bodies, sorted(set(plated)), tallest


def body_reach(ctx):
    """m1: how far a drawn body reaches past its centre, per stud of radius. CrowdRenderer draws a
    torso TORSO_WIDTH x TORSO_DEPTH radii across, so at any facing its corner stands half that
    diagonal out (1.151 at 1.9 x 1.3). None when the renderer lacks a key."""
    found = ctx.get("renderer") or {}
    if any(key not in found for key in RENDERER_KEYS):
        return None
    return math.hypot(found["TORSO_WIDTH"], found["TORSO_DEPTH"]) / 2


def grown(rect, by):
    return rect[0] - by, rect[1] + by, rect[2] - by, rect[3] + by


def strictly_in(rect, x, z):
    return rect[0] + EPS < x < rect[1] - EPS and rect[2] + EPS < z < rect[3] - EPS


def gate_zone(camp, gate, thickness, reach):
    """The ground outside a gate a point may look through it from: its lane widened by `reach`
    each way, `reach` deep outward from the gate's outer face (x0, x1, z0, z1)."""
    gx0, gx1, gz0, gz1 = gate_rect(camp, gate, thickness)
    side = gate["side"]
    if side == "north":
        return gx0 - reach, gx1 + reach, gz0 - reach, gz0
    if side == "south":
        return gx0 - reach, gx1 + reach, gz1, gz1 + reach
    if side == "west":
        return gx0 - reach, gx0, gz0 - reach, gz1 + reach
    return gx1, gx1 + reach, gz0 - reach, gz1 + reach


def zone_points(zone, xs, zs):
    """m1: the points of `zone` where a gate's sight is judged: a SIGHT_FINE grid, every line
    x = c (c in xs) and z = c (c in zs) at SIGHT_EDGE, and every crossing of two such lines exactly
    (the corners of the regions the lines bound, where a margin is least)."""
    x0, x1, z0, z1 = zone

    def run(a, b, step):
        return [a + step * k for k in range(int((b - a) / step + EPS) + 1)] + [b]

    lx = [x for x in xs if x0 - EPS <= x <= x1 + EPS]
    lz = [z for z in zs if z0 - EPS <= z <= z1 + EPS]
    found = {(x, z) for x in run(x0, x1, SIGHT_FINE) for z in run(z0, z1, SIGHT_FINE)}
    found |= {(x, z) for x in lx for z in run(z0, z1, SIGHT_EDGE)}
    found |= {(x, z) for z in lz for x in run(x0, x1, SIGHT_EDGE)}
    found |= {(x, z) for x in lx for z in lz}
    return {(round(x, 4), round(z, 4)) for x, z in found}


def edge_lines(rects, by):
    """The x lines and the z lines of every rectangle's edges, moved `by` outward (negative:
    inward)."""
    xs, zs = set(), set()
    for x0, x1, z0, z1 in rects:
        xs |= {x0 - by, x1 + by}
        zs |= {z0 - by, z1 + by}
    return xs, zs


def sight_points(layout, solids, ctx, camp, gates, walls, tall, clip):
    """The plan-view points a walled camp is looked at from (the L1c fix round's C1 and m1):
    ({eye: it stands inside the clip}, {camera}, {camera whose reach is unproved}, reached).

    Eyes: every outside top a player reaches, on a SIGHT_STEP grid; in each gate's zone also on
    SIGHT_FINE, and along the tops' edges, the doorways' edges and the clip's edge at SIGHT_EDGE
    with every corner. An eye inside `clip["grown"]` (the fenced rectangle grown by
    levels.cameraClear) has its boom start inside the clipped rectangle, so the boom comes to the
    head (WallClip.Reach answers 0): that eye's camera is the eye itself, judged with it.

    Cameras: only from an eye outside the clip. A point within camera.maxZoom + CAMERA_SPARE of
    such an eye, whose segment from it no tall wall and no clip keep-out cuts, and that stands in
    no keep-out: `clip["keeps"]` (every locking camp's fenced rectangle grown by cameraClear less
    the shake, which moves a clipped camera that far in) and every tall wall grown by the
    spherecast's radius less the shake. SIGHT_STEP everywhere; in a gate's zone also SIGHT_FINE,
    every keep-out edge at SIGHT_EDGE and their corners. Those zone points come back unproved
    (`lazy`); `reached(x, z)` proves one, and check_walled asks only for the ones it needs, least
    margin first."""
    thickness = ctx["levels"]["fenceThickness"]
    boom = (ctx.get("camera") or {}).get("maxZoom", 0) + CAMERA_SPARE
    outsides = [gate_faces(camp, g, thickness)[2] for g in gates]
    rects = [gate_rect(camp, g, thickness) for g in gates]
    zones = [gate_zone(camp, g, thickness, boom) for g in gates]

    def near_outside(x, z):
        for g, (gx0, gx1, gz0, gz1) in zip(gates, rects):
            side = g["side"]
            if ((side == "north" and z < gz0 + boom) or (side == "south" and z > gz1 - boom)
                    or (side == "west" and x < gx0 + boom) or (side == "east" and x > gx1 - boom)):
                return True
        return False

    reach = reachable_solids(layout, solids, ctx["move"], ctx["abilityHeight"], f"Camp_{camp['id']}_", tall)
    standable = [o for o in solids if o.kind in ("block", "floor", "secret", "fence", "obstacle")]

    def stands(x, z):
        """On a reached top, with nothing standable over it there."""
        for s in reach:
            if s.holds(x, z) and not any(o is not s and o.top > s.top + EPS and o.holds(x, z) for o in standable):
                return True
        return False

    eyes = set()
    for s in reach:
        for x, z in standable_points(solids, s, SIGHT_STEP):
            if near_outside(x, z):
                eyes.add((round(x, 4), round(z, 4)))
    fenced = clip["fenced"]
    doorways = [(gx0, gx1, fenced[2] - DOORWAY, fenced[3] + DOORWAY) if g["side"] in ("north", "south")
                else (fenced[0] - DOORWAY, fenced[1] + DOORWAY, gz0, gz1)
                for g, (gx0, gx1, gz0, gz1) in zip(gates, rects)]
    txs, tzs = edge_lines([(s.x0, s.x1, s.z0, s.z1) for s in reach], -EDGE_IN)
    dxs, dzs = edge_lines(doorways + [clip["grown"]], EDGE_IN)
    for zone in zones if SIGHT_ZONES else []:
        for x, z in zone_points(zone, txs | dxs, tzs | dzs):
            if stands(x, z):
                eyes.add((x, z))
    inside = {p: strictly_in(clip["grown"], *p) for p in eyes}
    keeps = clip["keeps"] + [grown(w, clip["standoff"]) for w in walls]
    cuts = walls + clip["keeps"]

    def kept_out(x, z):
        return any(strictly_in(r, x, z) for r in keeps)

    booms = [p for p in eyes if not inside[p]]
    cams = set()
    for ex, ez in booms:
        for i in range(int(math.floor((ex - boom) / SIGHT_STEP)), int(math.ceil((ex + boom) / SIGHT_STEP)) + 1):
            for k in range(int(math.floor((ez - boom) / SIGHT_STEP)), int(math.ceil((ez + boom) / SIGHT_STEP)) + 1):
                cx, cz = i * SIGHT_STEP, k * SIGHT_STEP
                if (cx, cz) in cams or math.hypot(cx - ex, cz - ez) > boom + EPS:
                    continue
                if not any(out(cx, cz) for out in outsides) or kept_out(cx, cz):
                    continue
                if any(seg_hits_rect(ex, ez, cx, cz, r) for r in cuts):
                    continue
                cams.add((cx, cz))
    lazy = set()
    kxs, kzs = edge_lines(keeps, EDGE_IN)
    for zone in zones if SIGHT_ZONES else []:
        for x, z in zone_points(zone, kxs, kzs):
            if (x, z) not in cams and any(out(x, z) for out in outsides) and not kept_out(x, z):
                lazy.add((x, z))
    bucket = {}
    for ex, ez in booms:
        bucket.setdefault((math.floor(ex / boom), math.floor(ez / boom)), []).append((ex, ez))

    def reached(cx, cz):
        """Some eye outside the clip swings its boom to (cx, cz) with nothing cutting it."""
        bx, bz = math.floor(cx / boom), math.floor(cz / boom)
        for i in (bx - 1, bx, bx + 1):
            for k in (bz - 1, bz, bz + 1):
                for ex, ez in bucket.get((i, k), ()):
                    if math.hypot(cx - ex, cz - ez) <= boom + EPS and not any(
                            seg_hits_rect(ex, ez, cx, cz, r) for r in cuts):
                        return True
        return False

    return inside, cams, lazy - cams, reached


def camera_lead(ctx):
    """m4: how much nearer a wall than the surface it stands over the highest camera may be: the
    boom's flat reach at the lowest pitch, the shoulder's sideways offset and the shake."""
    camera, theme = ctx.get("camera") or {}, ctx.get("theme") or {}
    pitch = math.radians(-theme["COMBAT_CAMERA_MIN_PITCH_DEGREES"])
    return camera["maxZoom"] * math.cos(pitch) + abs(camera["shoulderOffset"][0]) + theme["COMBAT_SHAKE_MAX_STUDS"]


def far_reach(rect, floor):
    """How far the farthest corner of a camp's floor stands from a wall's footprint."""
    return max(rect_gap(rect, (x, x, z, z)) for x in floor[:2] for z in floor[2:])


def check_walled(name, level, layout, ctx, expect, solids):
    """L1c-1, L1c-3 and L1c-6: a walled camp hides everything inside it from every place a player
    reaches outside it, at the top of any jump, with the camera at its highest and farthest."""
    walled = (EXPECTED.get(level["layout"]) or {}).get("walled") or []
    if not walled:
        return
    move, levels = ctx["move"], ctx["levels"]
    thickness = levels["fenceThickness"]
    rows = ctx["gate16"].setdefault(level["layout"], {}).setdefault("walled", [])
    tall = unclimbable(solids, move, ctx["abilityHeight"])
    top_cam, parts = camera_top(ctx)
    reach = stray_reach(move, 0)
    for cid in walled:
        camp = next((c for c in layout["camps"] if c["id"] == cid), None)
        tag = f"{name} camp {cid} (walled):"
        if camp is None or camp.get("locks") is not True:
            expect(False, f"{tag} it is a camp of the layout that locks")
            continue
        fence = camp.get("fence") or {}
        wall_top = camp["y"] + (fence.get("height") or 0)
        floor = camp_rect(camp)
        fenced = grown(floor, thickness)
        # Height (L1c-1): over the highest camera, WALL_SPARE to spare.
        expect(top_cam is not None and (fence.get("height") or 0) >= top_cam + WALL_SPARE - EPS,
               f"{tag} its fence ({fence.get('height')}) stands at least the highest camera + {WALL_SPARE:g} over its "
               f"floor: " + (f"{top_cam:.2f} + {WALL_SPARE:g} = {top_cam + WALL_SPARE:.2f} ({parts})"
                             if top_cam is not None else parts))
        # The trigger's ceiling (the L1c second fix round's F1 and F3): the camp triggers, and the
        # client's clip lets the boom go, for a root anywhere in its fenced rectangle up to that
        # ceiling over its floor. It must stand over the highest root a player gets there: from any
        # surface within stray_reach of the rectangle (its floor, its cover, the road in a gate; the
        # unclimbable walls are no surface), a jump, a double jump and the highest ability lift, plus
        # the root. Then a root inside the rectangle has always triggered the camp, a fighter inside
        # keeps his boom at the top of any jump, and the doorway exemption below ("one more step
        # triggers") holds at every height a player reaches.
        ceiling = sr.trigger_ceiling(camp, levels["triggerHeight"]) if WALLED_CEILING else levels["triggerHeight"]
        lift = move["jumpHeight"] + move["doubleJumpHeight"] + ctx["abilityHeight"] + sr.ROOT_HEIGHT
        launch = [s for s in solids if s.kind in ("block", "floor", "secret", "fence", "obstacle") and s.name not in tall
                  and rect_gap((s.x0, s.x1, s.z0, s.z1), fenced) <= reach + EPS]
        high = max(launch, key=lambda s: s.top, default=None)
        root_top = (high.top - camp["y"] + lift) if high is not None else None
        expect(root_top is not None and ceiling >= root_top - EPS,
               f"{tag} it triggers up to {ceiling:g} over its floor (StageFlow.Ceiling: its fence's top), over the "
               f"highest root a player gets in its fenced rectangle: "
               + (f"{root_top:g} ({high.name} top {high.top - camp['y']:+g} over the floor, + jump "
                  f"{move['jumpHeight']:g} + double jump {move['doubleJumpHeight']:g} + ability lift "
                  f"{ctx['abilityHeight']:g} + root {sr.ROOT_HEIGHT:g}), {ceiling - root_top:+g} to spare"
                  if root_top is not None else "no surface within reach"))
        rows.append(f"{cid} trigger ceiling {ceiling:g} over the floor; the highest root in the fenced rectangle "
                    + (f"{root_top:g} (from {high.name})" if root_top is not None else "none"))
        if top_cam is None:
            continue
        # The gatehouse: every wall block within stray_reach of the fenced rectangle is as tall.
        near = [s for s in solids if s.kind == "block" and s.look == "wall"
                and rect_gap((s.x0, s.x1, s.z0, s.z1), fenced) <= reach + EPS]
        low = [f"{s.name} top {s.top:g}" for s in near if s.top < wall_top - EPS]
        expect(not low, f"{tag} every wall block within {reach:.1f} of its fenced rectangle stands at least as high as "
               f"its fence's top {wall_top:g}" + (": " + ", ".join(low) if low else
                                                  f" ({len(near)}: {', '.join(s.name for s in near) or 'none'})"))
        # Plates (L1c-6).
        bodies, plated, tallest = walled_bodies(level, layout, ctx, cid)
        expect(not plated, f"{tag} no resident carries a plate at any difficulty (L1c-6: the plate bar is drawn "
               f"through walls)" + (f": {', '.join(plated)}" if plated else f" ({len(bodies)} posts)"))
        # Floors (the fix round's m4): a camera that tops a tall wall from an outside surface
        # sees nothing. Past that wall's top its line stays over the tallest body's head as far as
        # the floor's farthest corner from that wall. The wall is the fence itself, or any wall
        # block as tall within stray_reach + the boom of the fenced rectangle (a gatehouse wall: a
        # line over it falls through an open gate, not over the fence). The camera may stand
        # camera_lead nearer the wall than its surface. At or under every top the plan view below
        # decides.
        head = camp["y"] + tallest
        lead = camera_lead(ctx)
        boom = (ctx.get("camera") or {}).get("maxZoom", 0) + CAMERA_SPARE
        tops = [("the fence", fenced, wall_top, math.hypot(camp["sx"], camp["sz"]))]
        tops += [(s.name, (s.x0, s.x1, s.z0, s.z1), s.top, far_reach((s.x0, s.x1, s.z0, s.z1), floor))
                 for s in solids if FLOOR_WALLS and s.kind == "block" and s.look == "wall" and s.top >= wall_top - EPS
                 and rect_gap((s.x0, s.x1, s.z0, s.z1), fenced) <= reach + boom + EPS]
        under, topped, over = None, None, []
        for s in solids:
            if (s.kind not in ("block", "floor", "secret", "fence", "obstacle") or s.name.startswith(f"Camp_{cid}_")
                    or s.name in tall):
                continue
            cam = s.top + top_cam
            for wall, rect, top, far in tops:
                if cam <= top + EPS:
                    if under is None or top - cam < under[0]:
                        under = (top - cam, s.name)
                    continue
                d = max(rect_gap((s.x0, s.x1, s.z0, s.z1), rect) - lead, 0.0)
                inward = (top - head) * d / (cam - top)
                if topped is None or inward - far < topped[0]:
                    topped = (inward - far, s.name, d, cam, wall)
                if inward < far - EPS:
                    over.append(f"{s.name} (top {s.top:g}, camera {cam:.1f}) over {wall} ({d:.1f} off less the "
                                f"camera's lead {lead:.2f}): its line falls to a {tallest:g}-stud head {inward:.1f} "
                                f"studs past it; the floor's far corner is {far:.0f} past it")
        told = []
        if under is not None:
            told.append(f"the highest camera under a top: {under[1]}, {under[0]:.2f} under")
        if topped is not None:
            told.append(f"the tightest over one: {topped[1]} (camera {topped[3]:.1f}) over {topped[4]}, {topped[2]:.0f} "
                        f"off less the lead, its line meets a head {topped[0]:+.0f} past the floor's far corner")
        expect(not over, f"{tag} from every outside surface the highest camera ({top_cam:.2f} over it, up to "
               f"{lead:.2f} nearer) stays under the fence's and every gatehouse wall's top, or its line over that top "
               f"passes over the tallest body ({tallest:g}) to the floor's far corner"
               + (": " + "; ".join(over[:3]) if over else f" ({'; '.join(told)})"))
        # Sight in plan (the walls are over every camera, so plan is exact), with the camera clip
        # of the fix round's C1: the client keeps the boom out of every locking camp's fenced
        # rectangle grown by levels.cameraClear unless the root is inside the true rectangle.
        gates = camp.get("gates") or []
        walls = [(s.x0, s.x1, s.z0, s.z1) for s in solids
                 if s.kind == "block" and s.look == "wall" and s.top >= wall_top - EPS]
        theme = ctx.get("theme") or {}
        clear, factor = levels.get("cameraClear"), body_reach(ctx)
        shake, sphere = theme.get("COMBAT_SHAKE_MAX_STUDS"), theme.get("COMBAT_CAMERA_COLLISION_RADIUS")
        if not is_number(clear) or clear < 0 or factor is None or not is_number(sphere):
            expect(False, f"{tag} the sight gate reads Combat.json levels.cameraClear ({clear}, 0 or more), "
                   f"CrowdRenderer's {' and '.join(RENDERER_KEYS)} and Theme's COMBAT_CAMERA_COLLISION_RADIUS ({sphere})")
            continue
        # Under the shake, a clipped camera could be shaken into a gate's opening, where no view
        # is judged below; the plan then keeps it on the fence's face (and says so).
        expect(clear >= shake - EPS, f"{tag} levels.cameraClear {clear:g} is at least the camera's shake {shake:g} (a "
               f"clipped camera never enters the fence)")
        keep = max(clear - shake, 0.0)
        lockers = [grown(camp_rect(c), thickness) for c in layout["camps"] if c.get("locks") is True]
        clip = {"fenced": fenced, "grown": grown(fenced, clear), "keeps": [grown(r, keep) for r in lockers],
                "standoff": sphere - shake}
        inside, cams, lazy, reached = sight_points(layout, solids, ctx, camp, gates, walls, tall, clip)
        drawn = {at: (radius * factor, label) for at, (radius, label) in bodies.items()}

        def judge(px, pz):
            """The least margin from (px, pz) to any drawn body through any gate, or None when no
            line from there goes through one: (margin, label, side, bx, bz)."""
            least = None
            for gate in gates:
                arcs, ref = visible_arcs(px, pz, camp, gate, thickness, walls)
                if not arcs:
                    continue
                for (bx, bz), (out, label) in drawn.items():
                    d = math.hypot(bx - px, bz - pz)
                    theta = wrap(math.atan2(bz - pz, bx - px) - ref)
                    gap = min(0.0 if a0 <= theta <= a1 else min(abs(theta - a0), abs(theta - a1)) for a0, a1 in arcs)
                    margin = d * math.sin(min(gap, math.pi / 2)) - out
                    if least is None or margin < least[0]:
                        least = (margin, label, gate["side"], bx, bz)
            return least

        def doorway(x, z):
            for g in gates:
                gx0, gx1, gz0, gz1 = gate_rect(camp, g, thickness)
                lane = gx0 - EPS <= x <= gx1 + EPS if g["side"] in ("north", "south") else gz0 - EPS <= z <= gz1 + EPS
                if lane and rect_gap((x, x, z, z), fenced) <= DOORWAY + EPS:
                    return True
            return False

        tight = {"eye": None, "camera": None}
        seen, glimpse = [], None

        def note(what, px, pz, found):
            if tight[what] is None or found[0] < tight[what][0]:
                tight[what] = (found[0], px, pz) + found[1:]
            if found[0] < -EPS:
                seen.append(f"{what} ({px:g}, {pz:g}) sees {found[1]} at ({found[3]:g}, {found[4]:g}) through the "
                            f"{found[2]} gate ({found[0]:+.2f})")

        # Eyes: only the doorway's are exempt (its camera, inside the clip, is the eye itself).
        for px, pz in sorted(inside):
            found = judge(px, pz)
            if found is None:
                continue
            if doorway(px, pz):
                if glimpse is None or found[0] < glimpse[0]:
                    glimpse = (found[0], px, pz, found[1])
                continue
            note("eye", px, pz, found)
        for px, pz in sorted(cams):
            found = judge(px, pz)
            if found is not None and not (EXEMPT_CAMERAS and doorway(px, pz)):
                note("camera", px, pz, found)
        # The zone's fine camera points, least margin first: prove each one's reach until one with
        # nothing under it is proved (nothing after it can be tighter).
        queue = sorted((found[0], px, pz, found) for px, pz in lazy for found in [judge(px, pz)] if found is not None)
        proved = 0
        for margin, px, pz, found in queue:
            if margin >= -EPS and tight["camera"] is not None and margin >= tight["camera"][0]:
                break
            proved += 1
            if EXEMPT_CAMERAS and doorway(px, pz):
                continue
            if reached(px, pz):
                note("camera", px, pz, found)
                if margin >= -EPS:
                    break
        held = sum(1 for p in inside.values() if p)
        rows.append(f"{cid}: wall top {wall_top:g} (fence {fence.get('height')}, the highest camera {top_cam:.2f} over its "
                    f"surface); {len(inside)} eye points ({held} inside the camera clip), {len(cams)} camera points and "
                    f"{len(lazy)} fine ones near the gates ({proved} proved), {len(bodies)} posts; clip cameraClear "
                    f"{clear:g} (a camera {keep:g} off the fence at worst), drawn body {factor:.3f} x radius")
        for what in ("eye", "camera"):
            if tight[what] is not None:
                t = tight[what]
                rows.append(f"{cid} sight margin ({what}s) {t[0]:+.2f} studs: ({t[1]:g}, {t[2]:g}) to {t[3]} through "
                            f"the {t[4]} gate")
        if glimpse is not None:
            rows.append(f"{cid} doorway (exempt eyes: within {DOORWAY:g} of the fence in a gate's lane): {glimpse[0]:+.2f} "
                        f"at ({glimpse[1]:g}, {glimpse[2]:g}) to {glimpse[3]}")
        least = min((t for t in tight.values() if t is not None), default=None, key=lambda t: t[0])
        expect(not seen and bool(inside), f"{tag} from no eye point on an outside top a player reaches and no camera "
               f"point its boom reaches (kept {keep:g} off the fence by the clip, levels.cameraClear {clear:g} "
               f"less the shake), is any part of a drawn resident (radius x {factor:.3f}) seen through a gate, every "
               f"difficulty (in plan: the walls are over every camera; only eyes in the doorway, {DOORWAY:g} from the "
               f"fence in a gate's lane, are exempt)"
               + (": " + "; ".join(seen[:3]) if seen else
                  f" ({len(inside)} eye and {len(cams) + proved} camera points, {len(bodies)} posts; the tightest "
                  + (f"{least[0]:+.2f} studs at ({least[1]:g}, {least[2]:g}) to {least[3]})" if least else
                     "none: no line reaches a gate)")))
        # The margin ruling (2026-10-16, after the fix round): a body drawn as its torso box is not
        # all there is (animation, swinging arms, a held weapon), so every eye's and every camera's
        # margin must be at least the camp's own `sightMargin` (the layout's number, never typed here).
        want = camp.get("sightMargin")
        short = [f"{what} {t[0]:+.2f} at ({t[1]:g}, {t[2]:g}) to {t[3]}" for what, t in tight.items()
                 if t is not None and is_number(want) and t[0] < want - EPS]
        expect(is_number(want) and want >= 0 and not short and least is not None,
               f"{tag} every eye's and every camera's sight margin is at least its sightMargin ({want}): "
               + ("; ".join(short) if short else
                  ", ".join(f"{what}s {t[0]:+.2f}" for what, t in tight.items() if t is not None) or "none measured"))


def member_kinds(defn):
    """The kind of each member of a group, in post order (units expanded in the file's order)."""
    return [unit["kind"] for unit in defn["units"] for _ in range(unit["count"])]


def all_defs(level, layout, rank, ranks):
    """Every group a run places at `rank`, in AddGroup order: the residents', then the tents'
    (a tent's def carries its whole stock as its units: every body it will send)."""
    defs, _res = sr.groups_of(level, layout, rank, ranks)
    tents, _stocks = sr.tents_of(level, layout, rank, ranks)
    return defs + [tent["def"] for tent in tents], tents


def segment_gap(px, pz, a, b):
    """The flat distance from (px, pz) to the segment a-b (points (x, z))."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    run = dx * dx + dz * dz
    f = 0.0 if run <= EPS else max(0.0, min(1.0, ((px - a[0]) * dx + (pz - a[1]) * dz) / run))
    return math.hypot(px - (a[0] + dx * f), pz - (a[1] + dz * f))


def polyline_samples(points, step):
    """(x, z) every `step` studs along a polyline of (x, z) points, every vertex included."""
    found = [points[0]]
    for a, b in zip(points, points[1:]):
        run = math.hypot(b[0] - a[0], b[1] - a[1])
        cuts = max(int(math.ceil(run / step)), 1)
        found += [(a[0] + (b[0] - a[0]) * k / cuts, a[1] + (b[1] - a[1]) * k / cuts) for k in range(1, cuts + 1)]
    return found


def check_wave2(name, level, layout, ctx, expect, caps, solids):
    """The L1b Wave 2 gates on a level's camps (INTERFACES "Wave 2 — the long road", the gates
    table): tents and their rings, post spacing (L1b-W2-4), the sneak path (L1b-W2-3) and the
    join-in's chain table (L1b-W2-12), at every difficulty."""
    kinds, ranks, rules = ctx["kinds"], ctx["ranks"], ctx["camps"]
    spec = EXPECTED.get(level["layout"]) or {}
    difficulties = list(level["difficulties"])
    camps = {c["id"]: c for c in layout["camps"]}
    locking = {c["id"] for c in layout["camps"] if c.get("locks") is True}
    configs = {c["id"]: c for c in level.get("camps") or []}
    facts = ctx["gate16"].setdefault(level["layout"], {})

    def radius(kind):
        return kinds[kind]["radius"] if kind in kinds else ctx["widest"]

    # Tents: a stock only on an open camp with residents and a layout tent block; the block's
    # centre on its floor; `every` above 0; the ring on the floor less the widest radius + 1, off
    # every obstacle by as much, and clear of its own marker.
    bad = []
    told = []
    for cid, config in configs.items():
        tent = config.get("tent")
        camp = camps.get(cid)
        if tent is None or camp is None:
            continue
        block = camp.get("tent")
        if cid in locking:
            bad.append(f"camp {cid} locks and has a tent stock")
        if block is None:
            bad.append(f"camp {cid} has a tent stock and no layout tent block")
        if not (sr.is_num(tent.get("every")) and tent["every"] > 0):
            bad.append(f"camp {cid}: every {tent.get('every')}")
    for camp in layout["camps"]:
        block = camp.get("tent")
        if block is None:
            continue
        x0, x1, z0, z1 = camp_rect(camp)
        if not (x0 <= block["x"] <= x1 and z0 <= block["z"] <= z1):
            bad.append(f"camp {camp['id']}: its tent's centre ({block['x']:g}, {block['z']:g}) is off its floor")
        if not (sr.is_num(block.get("radius")) and block["radius"] > 0):
            bad.append(f"camp {camp['id']}: its tent's radius {block.get('radius')}")
    for difficulty in difficulties:
        _defs, tents = all_defs(level, layout, ranks.get(difficulty, 0), ranks)
        _d, residents = sr.groups_of(level, layout, ranks.get(difficulty, 0), ranks)
        for tent in tents:
            defn = tent["def"]
            camp = camps[defn["camp"]]
            if residents.get(defn["camp"], 0) <= 0:
                bad.append(f"{difficulty} {defn['id']}: a stock on a camp with no residents")
            x0, x1, z0, z1 = camp_rect(camp)
            block = camp["tent"]
            mark = (block["x"] - block["sx"] / 2, block["x"] + block["sx"] / 2,
                    block["z"] - block["sz"] / 2, block["z"] + block["sz"] / 2)
            widest = max(radius(k) for k in tent["kinds"])
            spare = widest + POST_SPARE
            for k, (post, kind) in enumerate(zip(tent["posts"], tent["kinds"]), 1):
                x, _y, z = post["at"]
                inside = min(x - x0, x1 - x, z - z0, z1 - z)
                if inside < spare - EPS:
                    bad.append(f"{difficulty} {defn['id']} ring post {k} is {inside:.2f} inside its floor (needs {spare:g})")
                for cx0, cx1, cz0, cz1, n in obstacle_rects(camp):
                    away = rect_distance(x, z, cx0, cx1, cz0, cz1)
                    if away < spare - EPS:
                        bad.append(f"{difficulty} {defn['id']} ring post {k} is {away:.2f} from obstacle {n}")
                clear = rect_distance(x, z, *mark)
                if clear < radius(kind) - EPS:
                    bad.append(f"{difficulty} {defn['id']} ring post {k} ({kind}) stands in its marker ({clear:.2f})")
            if difficulty == difficulties[-1]:
                told.append(f"{defn['id']} {len(tent['kinds'])} bodies every {tent['every']:g} s on a ring of "
                            f"{defn['radius']:g} round ({defn['points'][0][0]:g}, {defn['points'][0][2]:g})")
    expect(not bad, f"{name}: tents: a stock only on an open camp with residents and a tent block, its centre on the "
           f"floor, every above 0, its ring {POST_SPARE:g} + the widest radius inside the floor and off cover, clear "
           f"of its marker (every difficulty)" + (": " + "; ".join(bad[:4]) if bad else f" ({'; '.join(told)})"))
    # Every resident post of a camp with a tent block (the boss room's marker included), and every
    # point of a patrol's loop, clear of that marker by its body's radius, so no resting body stands
    # half inside the opaque tent (data m1). The marker being walk-through is LevelGeometry's to
    # build, and the harness guards it (mutation "l1b w2: the tent marker built colliding"); the
    # layout carries no collide key for it, so nothing here could test it.
    bad = []
    tightest = (math.inf, "")
    for difficulty in difficulties:
        residents, _res = sr.groups_of(level, layout, ranks.get(difficulty, 0), ranks)
        for defn in residents:
            block = camps[defn["camp"]].get("tent")
            if block is None:
                continue
            mark = (block["x"] - block["sx"] / 2, block["x"] + block["sx"] / 2,
                    block["z"] - block["sz"] / 2, block["z"] + block["sz"] / 2)
            kinds_of = member_kinds(defn)
            if defn["posture"] == "patrol":
                widest = max(radius(k) for k in kinds_of)
                spots = [(x, z, widest, f"loop at ({x:g}, {z:g})") for x, z, _yaw in loop_samples(defn["points"])]
            else:
                spots = [(post["at"][0], post["at"][2], radius(kind), f"post {k} ({kind})")
                         for k, (post, kind) in enumerate(zip(sr.group_posts(defn), kinds_of), 1)]
            for x, z, r, what in spots:
                spare = rect_distance(x, z, *mark) - r
                if spare < tightest[0]:
                    tightest = (spare, f"{difficulty} {defn['id']} {what}")
                if spare < -EPS:
                    bad.append(f"{difficulty} {defn['id']} {what} stands {-spare:.2f} inside camp {defn['camp']}'s tent "
                               f"marker")
    expect(not bad, f"{name}: every resident post and patrol loop of a camp with a tent block stands clear of its "
           f"marker by its body's radius, every difficulty (the marker's walk-through build is the harness's)"
           + (": " + "; ".join(bad[:4]) if bad else
              f" (the tightest: {tightest[1]}, {tightest[0]:+.2f} to spare)" if tightest[1] else " (no post near one)"))

    # Post spacing (L1b-W2-4): any two posts of a camp, any groups, the tent's ring included, at
    # least r_a + r_b + SPACING_SPARE apart; a patrol's loop as far from every other group's post.
    bad = []
    tightest = (math.inf, "")
    for difficulty in difficulties:
        defs, _tents = all_defs(level, layout, ranks.get(difficulty, 0), ranks)
        by_camp = {}
        for defn in defs:
            posts = sr.group_posts(defn)
            for post, kind in zip(posts, member_kinds(defn)):
                by_camp.setdefault(defn["camp"], []).append((defn["id"], post["at"][0], post["at"][2], radius(kind)))
        for cid, posts in by_camp.items():
            for i in range(len(posts)):
                for j in range(i + 1, len(posts)):
                    a, b = posts[i], posts[j]
                    gap = math.hypot(a[1] - b[1], a[2] - b[2]) - (a[3] + b[3] + SPACING_SPARE)
                    if gap < tightest[0]:
                        tightest = (gap, f"{difficulty} {a[0]} and {b[0]}")
                    if gap < -EPS:
                        bad.append(f"{difficulty} {a[0]} / {b[0]} at ({a[1]:g}, {a[2]:g}) and ({b[1]:g}, {b[2]:g}): "
                                   f"{gap + a[3] + b[3] + SPACING_SPARE:.2f} apart, needs {a[3] + b[3] + SPACING_SPARE:g}")
        for defn in defs:
            if defn["posture"] != "patrol":
                continue
            mine = max(radius(k) for k in member_kinds(defn))
            for x, z, _yaw in loop_samples(defn["points"]):
                for other_id, px, pz, r in by_camp.get(defn["camp"], []):
                    if other_id == defn["id"]:
                        continue
                    gap = math.hypot(x - px, z - pz) - (mine + r + SPACING_SPARE)
                    if gap < tightest[0]:
                        tightest = (gap, f"{difficulty} {defn['id']}'s loop and {other_id}")
                    if gap < -EPS:
                        bad.append(f"{difficulty} {defn['id']}'s loop at ({x:g}, {z:g}) is {gap:+.2f} from a post of "
                                   f"{other_id}")
                        break
    expect(not bad, f"{name}: post spacing (L1b-W2-4): any two posts of a camp, tent rings included, at least r_a + r_b "
           f"+ {SPACING_SPARE:g} apart, a patrol's loop as far from every other group's post, every difficulty"
           + (": " + "; ".join(bad[:4]) if bad else f" (the tightest: {tightest[1]}, {tightest[0]:+.2f} to spare)"))

    # The sneak path (L1b-W2-3).
    sneak = layout.get("sneak")
    if spec.get("sneak") and not sneak:
        expect(False, f"{name}: the layout has a sneak path (layout.sneak)")
    if sneak:
        check_sneak(name, level, layout, ctx, expect, solids, sneak, facts)

    # The join-in (L1b-W2-12): the chain each group's wake brings in, from rest, on Normal (a
    # tent's group has sent nobody yet, so it joins nothing at the first wake).
    first = difficulties[0]
    defs, tents = all_defs(level, layout, ranks.get(first, 0), ranks)
    empty = {i: 0 for i, d in enumerate(defs, 1) if d["posture"] == "tent"}
    living = {i: sum(u["count"] for u in d["units"]) for i, d in enumerate(defs, 1)}
    living.update(empty)
    table = sr.chain_table(defs, rules, living)
    rows = []
    for defn in defs:
        if defn["camp"] in locking:
            continue
        reach = rules["joinFactor"] * sr.cb_posture(defn, rules)["sight"]
        rows.append(f"{defn['id']} ({defn['posture']}, reach {reach:g}) -> "
                    + (", ".join(table[defn["id"]]) or "nobody")
                    + f" [{sum(living[j] for j, d in enumerate(defs, 1) if d['id'] in table[defn['id']]) + living[defs.index(defn) + 1]} bodies]")
    facts["chain"] = rows
    ctx["chains"][level["id"]] = table
    expect(sr.finite(rules.get("joinFactor")) and rules["joinFactor"] > 0,
           f"{name}: camps.joinFactor {rules.get('joinFactor')} is above 0; the chain each wake brings in on {first} "
           f"(from rest; tents not out yet): " + "; ".join(rows))


def check_sneak(name, level, layout, ctx, expect, solids, sneak, facts):
    """L1b-W2-3: the sneak path runs from the start to the locking camp's entry on standable tops
    (the route's rules for its climbs and its gap), and lies farther than every open-camp group's
    sight from every one of its resting places, every difficulty, cones ignored; the cone-aware
    margins are reported."""
    move = ctx["move"]
    jump = jump_facts(move)
    kinds, ranks, rules = ctx["kinds"], ctx["ranks"], ctx["camps"]
    start = layout["start"]
    locking = [c for c in layout["camps"] if c.get("locks") is True]
    entry = locking[0]["entry"] if locking else None
    points = [(p["x"], p["z"]) for p in sneak]
    ends = (math.hypot(points[0][0] - start["x"], points[0][1] - start["z"]) < 0.01 and entry is not None
            and math.hypot(points[-1][0] - entry["x"], points[-1][1] - entry["z"]) < 0.01)
    # Standable: walked at WALK_RISE a sample, a climb at most the route's, a hole no wider than
    # the route's gap that lands no higher.
    problems = []
    height = start["y"]
    hole_from = None
    last = points[0]
    climbs = gaps = 0
    length = 0.0
    samples = polyline_samples(points, SNEAK_STEP)
    for prev, here in zip(samples, samples[1:]):
        length += math.hypot(here[0] - prev[0], here[1] - prev[1])
        top, _solid = ground(solids, here[0], here[1], height + jump["climb"] + EPS)
        if top is None:
            if hole_from is None:
                hole_from = (last, height)
            continue
        if hole_from is not None:
            (hx, hz), took = hole_from
            span = math.hypot(here[0] - hx, here[1] - hz)
            if span > jump["gap"] + EPS or top > took + EPS:
                problems.append(f"a hole from ({hx:g}, {hz:g}) to ({here[0]:g}, {here[1]:g}) of {span:.1f} studs "
                                f"(the gap may span {jump['gap']}), landing {top - took:+g}")
            gaps += 1
            hole_from = None
        rise = top - height
        if rise > WALK_RISE + EPS:
            climbs += 1
        height = top
        last = here
    if hole_from is not None:
        problems.append(f"it ends over a hole after ({hole_from[0][0]:g}, {hole_from[0][1]:g})")
    expect(ends and not problems, f"{name}: the sneak path runs from the start to the boss room's entry on standable "
           f"ground at every {SNEAK_STEP:g} studs (walked, {climbs} climb(s) of at most {jump['climb']}, {gaps} gap(s) of "
           f"at most {jump['gap']}): {length:.0f} studs" + ("" if ends else " (it does not start at the start and end at "
                                                            "the entry)") + (": " + "; ".join(problems[:3]) if problems else ""))
    # Every resting place of every open-camp group farther than its sight (flat, cones ignored).
    seen = []
    margins = {}
    cones = {}
    fine = polyline_samples(points, CONE_SAMPLE)
    for difficulty in level["difficulties"]:
        defs, _tents = all_defs(level, layout, ranks.get(difficulty, 0), ranks)
        for defn in defs:
            if defn["held"]:
                continue
            sight = sr.cb_posture(defn, rules)["sight"]
            for member in resting_eyes(defn):
                ex, ez = member["at"][0], member["at"][2]
                d = min(segment_gap(ex, ez, a, b) for a, b in zip(points, points[1:]))
                spare = d - sight
                if spare < margins.get(defn["id"], (math.inf,))[0]:
                    margins[defn["id"]] = (spare, difficulty, sight)
                if spare <= EPS:
                    seen.append(f"{difficulty} {defn['id']} at ({ex:g}, {ez:g}): {d:.1f} studs, sight {sight:g}")
                # Cone-aware: the nearest sample its cone holds.
                posture = sr.cb_posture(defn, rules)
                for x, z in fine:
                    dx, dz = x - ex, z - ez
                    dist = math.hypot(dx, dz)
                    if dist - sight >= cones.get(defn["id"], (math.inf,))[0]:
                        continue
                    if posture["cone"] < 360 and dist >= sr.CB_CONE_NEAR:
                        yaw = member["post"]["yaw"]
                        cosine = (-math.sin(yaw) * dx - math.cos(yaw) * dz) / dist
                        if math.degrees(math.acos(min(max(cosine, -1.0), 1.0))) > posture["cone"] / 2:
                            continue
                    cones[defn["id"]] = (dist - sight, difficulty, sight)
    ordered = sorted(margins.items(), key=lambda kv: kv[1][0])
    told = [f"{gid} {m[0]:+.1f} (sight {m[2]:g}; in its cone {cones[gid][0]:+.1f})" if gid in cones
            else f"{gid} {m[0]:+.1f} (sight {m[2]:g})" for gid, m in ordered]
    facts["sneak"] = [f"{length:.0f} studs; tightest margins (flat distance less sight, every difficulty): "
                      + ", ".join(told[:6])]
    expect(not seen, f"{name}: the sneak path lies farther than its posture's sight from every resting place of every "
           f"open-camp group, tents included, every difficulty, cones ignored (L1b-W2-3)"
           + (": " + "; ".join(seen[:4]) if seen else f": the tightest {', '.join(told[:4])}"))


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
    # `level_files` are the files Catalog reads (<n>_<Name>.json). A node with no `level` is one
    # that is meant to be unbuilt ("Not built yet"); a node that names a level must find its file.
    by_id = {level["id"]: level for level in level_files}
    bad = [f"{n['id']} -> {n['level']}" for n in nodes if n.get("level") and n["level"] not in by_id]
    unbuilt = [n["id"] for n in nodes if not n.get("level")]
    expect(not bad, "map: every node with a `level` names a level file that Catalog reads"
           + (f" (no file for {', '.join(bad)})" if bad else f" ({', '.join(n['id'] for n in nodes if n.get('level'))}; "
                                                              f"unbuilt, with no `level`: {', '.join(unbuilt) or 'none'})"))
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
    expect(not missing, f"map: the {len(REQUIRED_LOOKS)} looks are there" + (f" (missing {missing})" if missing else ""))
    spread = {k: max(v["color"]) - min(v["color"]) for k, v in looks.items()}
    greys = [k for k in REQUIRED_LOOKS if k in looks and k not in COLOUR_LOOKS and spread[k] > GREY_SPREAD]
    dull = [k for k in COLOUR_LOOKS if k in looks and spread[k] <= GREY_SPREAD * 2]
    expect(not greys and not dull, "map: the looks are greys, except " + ", ".join(COLOUR_LOOKS) + " (L1b, L1b-W2-9), "
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
LEGEND = ("= road   % ledge or ground   ~ water   . camp floor   # fence or wall   | - gate   x spawn point   "
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
    size = (expeditions.get("sign") or {}).get("size")
    ctx = {"levels": combat["levels"], "move": proving["movement"], "looks": expeditions["looks"], "kinds": kinds,
           "widest": max(k["radius"] for k in kinds.values() if k.get("brain") and not k.get("boss")),
           "spawnClear": proving["crowd"]["threat"]["spawnClear"], "crowdMaxAlive": proving["crowd"]["maxAlive"],
           "campRadius": {}, "signSize": size if three_positive(size) else None,
           "missions": {m["id"]: m for m in (sr.load_config(path) for path in sorted(sr.MISSIONS_DIR.glob("*.json")))},
           "runCap": combat["director"]["runCapSeconds"], "camps": combat.get("camps"),
           "ranks": sr.difficulty_ranks(expeditions), "snapshotHz": proving["crowd"]["snapshotHz"],
           "gate16": {}, "chains": {}, "longbow": longbow_range(proving),
           "abilityHeight": ability_height(proving), "camera": combat.get("camera"), "theme": theme_numbers(),
           "renderer": renderer_numbers(), "abilityIds": ability_ids(expeditions), "lifts": lifting_abilities(proving),
           "fieldedLifts": fielded_lifts(proving), "loadout": sorted((proving.get("loadout") or {}).values())}
    return combat, expeditions, layouts, sr.load_level_files(), ctx


def longbow_range(proving):
    """The range of the default ranged family's default variant (the Longbow, R8's sniper)."""
    weapon = proving["weapons"][proving["loadout"]["ranged"]]
    return weapon["variants"][weapon["default"]]["range"]


def stray_level_files():
    """The *.json files of Config/Levels that Catalog does not read: it takes <n>_<Name> only."""
    return sorted(path.name for path in sr.LEVELS_DIR.glob("*.json") if not sr.is_catalog_name(path.stem))


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def check_rules(combat, level_files, ctx, expect):
    """Combat.json: the `levels` keys of the fix round (ruling 4) and the Studio gear presets
    (ruling 8)."""
    levels = ctx["levels"]
    size = levels.get("checkpointSize")
    expect(three_positive(size),
           f"Combat.json levels.checkpointSize is three positive numbers (the checkpoint marker): {size}")
    # The least each may be; None = over 0. All but floorThickness and maxParts are the numbers
    # StageFlow.Validate asks for by name (sim_range.LEVEL_RULES_NEEDED): without one, a start
    # answers "unavailable".
    wanted = {"triggerBelow": 0, "triggerHeight": None, "closeInset": 0, "closeGraceSeconds": 0, "crowdCeiling": None,
              "floorThickness": None, "fenceThickness": None, "startSpacing": None, "boxMargin": 0}
    odd = [f"{key} {levels.get(key)}" for key, least in wanted.items()
           if not is_number(levels.get(key)) or (levels[key] <= 0 if least is None else levels[key] < least)]
    odd += [f"{key} (StageFlow.Validate needs it)" for key in sr.LEVEL_RULES_NEEDED
            if key not in wanted and key not in L1B_RULES and key != "gateSeconds" and not is_number(levels.get(key))]
    expect(not odd and "triggerInset" not in levels,
           "Combat.json levels: triggerBelow, closeInset, closeGraceSeconds and boxMargin are 0 or more; triggerHeight, "
           "crowdCeiling, floorThickness, fenceThickness and startSpacing are over 0; triggerInset is gone (a camp "
           "triggers on its whole fenced rectangle)" + (f" (not: {', '.join(odd)})" if odd else "")
           + (" (triggerInset is still there)" if "triggerInset" in levels else ""))
    # L1b: the checkpoint's reach, the wallet's pace and the fire marker (L1b-W2-5 derives the
    # boss reserve from ProvingGrounds.json: Combat.json holds no reserve).
    reach, wallet = levels.get("checkpointReach"), levels.get("walletSendSeconds")
    fire = levels.get("fireMarkerSize")
    expect(is_number(reach) and reach > 0 and is_number(wallet) and wallet == WALLET_SEND_SECONDS
           and three_positive(fire),
           f"Combat.json levels (L1b): checkpointReach over 0 ({reach}), walletSendSeconds exactly "
           f"{WALLET_SEND_SECONDS:g} ({wallet}), fireMarkerSize three positive numbers ({fire})")
    lock, spare = levels.get("regionLockMargin"), levels.get("doorSpare")
    expect(lock == REGION_LOCK_MARGIN and spare == DOOR_SPARE,
           f"Combat.json levels (L1b Wave 4): regionLockMargin exactly {REGION_LOCK_MARGIN:g} ({lock}) and doorSpare "
           f"exactly {DOOR_SPARE:g} ({spare}), both fixed by the contract")
    camps = combat.get("camps")
    problems = sr.cb_problems(camps)
    expect(not problems, "Combat.json camps: every key CampBrain.Problems reads is there, finite and in range"
           + (": " + "; ".join(problems) if problems else
              f" (sight guard {camps['guard']['sight']:g}/{camps['guard']['cone']:g} deg, patrol "
              f"{camps['patrol']['sight']:g}, fire {camps['fire']['sight']:g}; rise fire {camps['fire']['rise']:g} s; "
              f"leash {camps['leashSeconds']:g} s; chaseMargin {camps['chaseMargin']:g}; chaseSight "
              f"{camps['chaseSight']:g}, hitMemorySeconds {camps['hitMemorySeconds']:g}, meleeAbove "
              f"{camps['meleeAbove']:g})"))
    if not problems:
        # L1b-W2-10: a group sleeps only where no member could see a player, nor see one arrive
        # within one snapshot of the fastest legal move.
        move = ctx["move"]
        dash = move["dashDistance"] / move["dashSeconds"] if move.get("dashSeconds", 0) > 0 else 0
        fastest = max(move["walkSpeed"], move["slamFallSpeed"], dash, 0)
        need = max(camps[p]["sight"] for p in sr.CB_POSTURES) + fastest / ctx["snapshotHz"]
        expect(camps["dormantRadius"] >= need - EPS,
               f"Combat.json camps.dormantRadius {camps['dormantRadius']:g} is at least every posture's sight + "
               f"Tuning.FastestMove / crowd.snapshotHz ({max(camps[p]['sight'] for p in sr.CB_POSTURES):g} + "
               f"{fastest:g} / {ctx['snapshotHz']:g} = {need:.2f})")
        expect(camps["joinFactor"] == JOIN_FACTOR_FIXED,
               f"Combat.json camps.joinFactor is {JOIN_FACTOR_FIXED} (fixed: Ben's \"at least double\"): {camps['joinFactor']}")
    expect(is_number(levels.get("gateSeconds")) and levels["gateSeconds"] >= GATE_FLOOR,
           f"Combat.json levels.gateSeconds {levels.get('gateSeconds')} is at least {GATE_FLOOR:g} (the client learns the "
           f"floor that long before the first body)")
    # L2-11: SecretFlow.Triggered's numbers, and L2-19's three Studio levers.
    rules = secret_rules(levels)
    expect(rules is not None and rules[0] > 0 and rules[1] >= 0 and rules[2] > 0,
           "Combat.json levels (L2-11): secretReach and secretAbove over 0, secretBelow 0 or more: "
           + ", ".join(f"{key} {levels.get(key)}" for key in SECRET_RULES))
    debug = combat.get("debug") or {}
    names = [debug.get(key) for key in DEBUG_UNLOCK_KEYS]
    taken = [v for k, v in debug.items() if k.endswith("Attribute") and k not in DEBUG_UNLOCK_KEYS]
    expect(all(isinstance(v, str) and v for v in names) and len(set(names)) == len(names)
           and not set(names) & set(taken),
           "Combat.json debug (L2-19): " + ", ".join(f"{k} {debug.get(k)!r}" for k in DEBUG_UNLOCK_KEYS)
           + " are Workspace attribute names of their own")
    presets = [(p.get("melee"), p.get("ranged")) for p in debug.get("gearPresets") or []]
    proving = debug.get("provingGear") or {}
    tiers = sorted({d["recommendedTier"] for file in level_files for d in (file.get("difficulties") or {}).values()}
                   | {file["recommendedTier"] for file in level_files if file.get("recommendedTier") is not None})
    reached = all(any(melee == tier for melee, _r in presets) for tier in tiers)
    expect(presets == list(GEAR_PRESETS) and presets[:1] == [(proving.get("melee"), proving.get("ranged"))] and reached,
           f"Combat.json debug.gearPresets are {', '.join(f'{m}/{r}' for m, r in GEAR_PRESETS)} (the G key), the first "
           f"is debug.provingGear, and every difficulty's recommendedTier ({', '.join(map(str, tiers))}) is a preset's "
           f"melee tier: " + ", ".join(f"{m}/{r}" for m, r in presets))


def run_gates(combat, expeditions, layouts, level_files, ctx, expect):
    """Every gate, as main runs them on the loaded files: `expect(ok, text)` is told each one. The
    route facts per layout, or None when Combat.json lacks a number the layouts are measured
    with. tools/check_levels_mutants.py runs this on mutated copies."""
    lobby_name = (expeditions.get("lobby") or {}).get("layout")
    by_layout = {level["layout"]: level for level in level_files}
    facts = {}
    move = ctx["move"]
    jump = jump_facts(move)
    print("check_levels (docs/INTERFACES.md \"L1 contracts\" -> \"Config\", and \"L1b contracts\" -> \"Config\")")
    print(f"  one jump: {move['jumpHeight']:g} studs high, {jump['air']:.3f} s in the air, {jump['reach']:.1f} studs "
          f"at walk speed {move['walkSpeed']:g}; a climb may rise {jump['climb']}, a gap may span {jump['gap']}; "
          f"jump + double jump {move['jumpHeight'] + move['doubleJumpHeight']:g}")
    print()
    check_map(expeditions, level_files, layouts, expect)
    check_abilities(expeditions, level_files, expect)
    check_rules(combat, level_files, ctx, expect)
    # The layouts are measured with these: without one of them nothing below can be said.
    lost = [key for key in READ_RULES if not is_number(ctx["levels"].get(key))]
    if lost:
        expect(False, f"Combat.json levels lacks {', '.join(lost)}; the layouts were not checked")
        return None
    stray = stray_level_files()
    ids = [file["id"] for file in level_files]
    expect(not stray and len(ids) == len(set(ids)),
           "Config/Levels: every file is named <n>_<Name>.json, the only name Catalog reads, and no two share an id"
           + (f" (Catalog would not read {', '.join(stray)})" if stray else f" ({len(ids)} files: {', '.join(ids)})"))
    # The level files first: they say which kinds stand in which camp.
    for file in level_files:
        level = sr.resolve_level(file, ctx["missions"].get(file.get("mission")), ctx["runCap"])
        check_level_file(file, level, layouts, ctx, expect)
        if file.get("layout") in layouts:
            check_secret_rewards(file, layouts[file["layout"]], expeditions, expect)
    bounds_of = {name: layout_bounds(layout, ctx["levels"]["fenceThickness"], ctx["levels"]["floorThickness"])
                 for name, layout in layouts.items()}
    for name, layout in layouts.items():
        if name == lobby_name:
            check_lobby(name, layout, ctx, bounds_of, expect)
        elif layout.get("arena"):
            check_arena_layout(name, layout, ctx, expect)
        else:
            facts[name] = check_layout(name, layout, ctx, expect)
    orphan = [name for name in layouts if name != lobby_name and name not in by_layout]
    expect(not orphan, "every layout but the lobby's belongs to a level file" + (f" ({orphan})" if orphan else ""))
    # Gate 16 (INTERFACES "Wave 2 — the long road" -> "Gates"): the numbers QA copies.
    print()
    print("GATE 16 (the numbers QA copies into its report)")
    for name, found in ctx["gate16"].items():
        print(f"  {name}:")
        for line in found.get("population") or []:
            print(f"    population  {line}")
        if name in facts:
            print(f"    parts       {facts[name].get('parts')}")
            print(f"    route       {facts[name]['length']:.0f} studs ({facts[name]['walked']:.0f} outside the camps)")
        for line in found.get("sneak") or []:
            print(f"    sneak       {line}")
        for line in found.get("chain") or []:
            print(f"    chain       {line}")
        for line in found.get("regions") or []:
            print(f"    region      {line}")
        for line in found.get("approaches") or []:
            print(f"    N           {line}")
        for line in found.get("spots") or []:
            print(f"    sniper      {line}")
        for line in found.get("walled") or []:
            print(f"    walled      {line}")
        for line in found.get("lifts") or []:
            print(f"    lifts       {line}")
    return facts


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
        facts = run_gates(combat, expeditions, layouts, level_files, ctx, expect)
        if facts is None:
            print()
            print(f"CHECK: FAIL ({len(failures)}): the layouts were not checked")
            sys.exit(1)
    if not args.no_plan:
        scale_x, scale_z = args.scale
        for name, layout in layouts.items():
            if layout.get("arena"):
                continue
            solids = solids_of(layout, ctx["levels"]["fenceThickness"], ctx["levels"]["floorThickness"])
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
    if not args.plan_only:
        print()
        print(f"CHECK: {'PASS' if not failures else 'FAIL (' + str(len(failures)) + ')'}")
        sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
