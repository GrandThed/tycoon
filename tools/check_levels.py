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

L2 Wave 2, "fire, the cave and the shortcut", and its fix round: the cave sealed behind fire and its
ridge unclimbable (the walk-off grace in the reach, d-m1), no ability that carries a Double Jump owner
(Leap Smash's arc, Impale Dash held in the air) onto the ridge (d-M1), the shortcut route, R8 on both
variants, the chain of keys, and no hop cutting a bend (an ability's travel: a known limit until L3
while no family that carries can be owned without a lever, d-m2).

L2 Wave 3, "ice, the frost hammer, deep water and the island shrine": deep water (no collision, the route
on a bridge over it) and its landings; the island behind ice with the water as built (g: no jump, lift or
air dash reaches it, and it lies ICE_MARGIN beyond the farthest of them) and frozen (h: the island reached,
the swing extends the ice, one chain of cells from a bank to the island); with the ice frozen, the
unclimbable walls, the lookout's rules, R8's pinned lists, the shot-origin chord and killY again; the family
a map node gives (`found`), the shrine's pay under the dearest sold ability, the ice look,
`levels.react.ice`, and the ice pieces in the Part count. Its fix round: every deep water a body falls
into has a landing and `player.rescue.outside` covers a server frame of the dash where a top meets it
(s-M1, Q3); no two ice blocks overlap (s-s2); the pieces and the covers fill every ice block (d-m1); Leap
Smash's fall in (g) (d-m3); a frozen sheet as deep as a floor (d-m6); a dash found through a MECHANICS
alias (s1); and the bend rule, the cave's closed half and the walled camp on the frozen layout (s2).

L4 Wave 2, "the forest and the raiders in the game" (docs/prompts/l4-w2-contract.md section 7, L4W2-14):
the dress walls (Config/LevelDress/<layout>.json `barriers`, the invisible character-only walls a dressed
level adds) only remove moves. Every "cannot" gate below holds without them (a grey level has none);
every wall top is unclimbable; and the "can" claims are proved again with a blocking test (a flat move
fails where it crosses a wall's footprint, grown by a body, below its top): the route and its gap (the
trailhead's designed drop), the owners' reach to every double-jump secret (the lookout's designed drop),
the sneak, the shortcut route and the ice crossing. Camp C's sight gate reads each model kind's posed
reach from Config/RaiderModels.json (the drawn body is the larger of the model and the placeholder).

L3 Wave 1, "tiers per weapon" (docs/prompts/l3-w1-contract.md, L3-25 and L3-28): the families a player
can own without a lever are the starters, every family a secret pays behind a key and every firstClear
family (ownable_families; the bend's known limit holds while none of them carries); R8's reach is the
longest range of their ranged variants (sniper_reach); every non-starter family has a shelf hint (a
`found` entry or the secret that pays it), and a firstClear family's `found` entry names its level's
node; Validate's firstClear lines; the gear presets T1 / T3 / T5 and the three L3 lever attributes.

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
  Layouts/Levels/*.json       the layouts (one that names an `arena` is refused since L4 W1b:
                              ruling 27's adapter went with the Raider Arena)
  Config/LevelDress/*.json    a dressed level's `barriers` (L4 W2; none without the file)
  Config/RaiderModels.json    each model kind's posed reach (L4 W2, camp C's sight gate)

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

Every rule L1c and its fix round added, and every rule of L2 Waves 1 and 2, is shown red on a mutated
copy by tools/check_levels_mutants.py (run_gates below is what it calls).
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sim_range as sr  # noqa: E402  (the config loaders and the level mirrors live there)
import check_parkour  # noqa: E402  (L4 W2: the climbs; it reads this module only when called)

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
        # L4 W2 (MISSIONS_DESIGN 28): the mountain's summit chest, the Castle Key, behind the double jump.
        "secrets": {"lookout": "doubleJump", "cache": "fire", "shrine": "ice", "mountain": "doubleJump"},
        "climbs": 1,
        "gaps": 1,
        # L2 W3 (L2-52, L2-57, L2-60): deep water that a frost swing freezes, and the island it leads to.
        "deepWater": {"ice": ["Creek", "Pond"], "island": "ShrineIsland", "secret": "shrine"},
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
        # L2 W2: the cache moved into the cave, behind fire and walls (L2-37's sight): Secret_cache left.
        # L2 W3: the creek is deep water (L2-57), no surface until it is frozen: Creek left (sniperSpotsFrozen).
        # L4 W1 (MISSIONS_DESIGN 26.1): the lookout moved to the trailhead, 132 studs from the nearest
        # region cell, beyond the Longbow's 110, and LookoutSignPad went with it: LookoutLedge,
        # LookoutSignPad and Secret_lookout left every list below.
        "sniperSpots": ["GatehouseTurn", "GatehouseWalk", "Road2", "Road3", "Road4", "RoadBC5", "RoadBC6",
                        "ShrineSignPad"],
        # L2-37: with the brambles burnt (a leader who found the tunnel) the two mouths' floors join:
        # any open mouth onto the region leaves a floor that sees out and that no rusher reaches (the
        # lead's OK pending; sim_range rates both on Normal and Hard). The long leg, the alcove and
        # the exit leg see nothing (the exit's bend), the cache's top neither.
        "sniperSpotsOpen": ["CaveExit", "CaveMouth", "GatehouseTurn", "GatehouseWalk", "Road2", "Road3", "Road4",
                            "RoadBC5", "RoadBC6", "ShrineSignPad"],
        # L2-60 R8: with the creek and the pond frozen (every ice block standable at its top + lift),
        # the same lists plus the frozen Creek (a sniper spot rated before W3 while the creek was solid;
        # sim_range rates it on Normal and Hard). The pond and the island lie beyond the Longbow's range.
        "sniperSpotsFrozen": ["Creek", "GatehouseTurn", "GatehouseWalk", "Road2", "Road3", "Road4", "RoadBC5",
                              "RoadBC6", "ShrineSignPad"],
        "sniperSpotsOpenFrozen": ["CaveExit", "CaveMouth", "Creek", "GatehouseTurn", "GatehouseWalk", "Road2",
                                  "Road3", "Road4", "RoadBC5", "RoadBC6", "ShrineSignPad"],
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
# L2-60: deep water lies at least this far under the bridge a route sample over it stands on.
WATER_UNDER = 0.5
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
# Blocks a body lands on; "ice" is a frozen sheet (sim_range.frozen_layout: the W3 fix round's d-m6
# holds it to the floor-depth rule in check_ice's frozen run).
GROUND_LOOKS = ("ground", "path", "lobby", "water", "ice")
LOBBY_CLEARANCE = 150.0
DENSITY_AREA = 200.0  # a camp's maxAlive is at most its floor area over this (the C1 arena had 60 on 110 x 110)
BAND_SHARE = 0.45  # a keepAway kind's bandMin is at most this share of the camp's shorter side
RUN_CAP_RATIO = 2.0
REQUIRED_LOOKS = ("ground", "path", "campFloor", "wall", "gate", "checkpoint", "checkpointDone", "secret",
                  "secretOpen", "sign", "water", "lobby", "fire", "tent", "bramble", "ice")
# Each must read at a glance (secretOpen, L2-14: a chest the player has found, tinted gold).
COLOUR_LOOKS = ("gate", "checkpoint", "checkpointDone", "secret", "secretOpen", "fire", "tent", "bramble", "ice")
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
# L2-37: R8 counts a spot only where a bow's line in plan reaches a region cell: walls and brambles
# stop it (sight_blockers). False is W1's rule (every unreachable top within the Longbow's range),
# for the mutant driver.
SIGHT_WALLS = True
SIGHT_LOOKS = ("wall", "bramble")
SIGHT_RASTER = 1.0  # PlanRooms' grid
# The `levels` numbers this tool itself reads to measure a layout.
READ_RULES = ("fenceThickness", "floorThickness", "triggerHeight", "crowdCeiling", "startSpacing", "maxParts")
GEAR_PRESETS = ((1, 1), (3, 3), (5, 5))  # L1b-W2-20, L3-15: the Studio gear presets T1 / T3 / T5 (melee, ranged)
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
WALLED_NEAR = 200.0  # the walled gate's walls lie within this of the camp's floor (eyes stand by its gates)
# L2 Wave 1 (docs/prompts/l2-w1-contract.md): bought abilities, and secrets as chests behind keys.
AIR_JUMP = "doubleJump"  # Unlocks.AIR_JUMP: the ability id the air jump keys on (structural)
SECRET_RULES = ("secretReach", "secretBelow", "secretAbove")  # Combat.json levels: SecretFlow.Triggered (L2-11)
DEBUG_UNLOCK_KEYS = ("grantAbilityAttribute", "removeAbilityAttribute", "resetSecretsAttribute",  # L2-19
                     "grantFamilyAttribute", "removeFamilyAttribute",  # L2-38
                     "setTierAttribute", "grantStarAttribute", "resetArmoryAttribute")  # L3-28
ABILITY_ID_MAX = sr.unlocks_cap("MAX_ID_LENGTH")  # Unlocks.MAX_ID_LENGTH, in bytes: an id the buy remote carries (L2-7)
SECRET_VALOR_MIN = 2  # L2-13: a paying chest gives at least this much Valor, and less than its key's price
BODY_RADIUS = 1.0  # the root's half width on the flat (a body stands this far over an edge)
# The L2 W2 second fix round's m1: the head's centre over the root (R15), where WeaponService's aim rule
# starts its line to a shot origin. A piece whose top a standing head clears is not a wall to shoot past.
HEAD_ABOVE_ROOT = 1.5
# SecretFlow.Triggered's flat reach, a switch like LIFT_MODEL. "footprint" (the L2 W1 fix round, s1):
# levels.secretReach is measured from the chest block's footprint, so a root beside a big chest
# (a body radius off its face) opens it. "centre" is W1 before the fix (from the chest's centre),
# for the mutant driver: under it the 12-wide Raiders' Cache never triggers.
TRIGGER_MODEL = "footprint"
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
LIFT_MODEL = "floor"
# L2 Wave 2 (docs/prompts/l2-w2-contract.md): fire, the cave and the shortcut.
REACT_WORDS = ("fire", "ice")  # a block's `react` and an element key (Types RangeWeaponDef.element)
# L2-37 (e): a chest pays at least this and at most this share of the level's Normal stock in its
# material (every resident, every tent body and the boss at rewardMult: a first clear's whole pay).
SECRET_MATERIAL_SHARE = (0.15, 0.30)
CAVE_MARGIN = 30.0  # the enclosure's flood fills the cave's box grown by this on the flat
CAVE_STEP = 2.0  # (f): a cave floor is proved enclosed on this grid and its edges
# The bend rule (L2-47, Ben's "close it now"): no hop between two walked road blocks that are not
# touching saves more than this much road, measured along the route (a corner may be cut, a bend not).
SKIP_SAVE = 60.0  # the corners of today's road save up to about 35 (Road2 to Road5); the AB bend about 115
SKIP_STEP = 2.0  # the road blocks' edges are sampled this often for the hop's ends
# L2 Wave 3 (docs/prompts/l2-w3-contract.md, L2-52 to L2-60): ice, deep water and the island shrine.
# (g): the island's flat gap to every other standable top is at least the farthest any means carries a
# player onto it (the jumps and a dash with the walk-off grace, an air dash held over its range, a lift
# cast after the jumps and a dash) and this much more: the slack for the reach models (L2-64).
ICE_MARGIN = 15.0
# (h): a swing from the ice's edge freezes at least this many rows ahead (L2-54: the sector reaches
# range + ahead from the origin, a body's radius behind the edge), so the ice can always be extended.
ICE_ROWS = 1.5
# Combat.json levels.react.ice (L2-53; the W3 second fix round's Q6 inset and Q5 sink).
ICE_KEYS = ("cell", "lift", "thickness", "reachDown", "ahead", "inset", "sink")
# Q6: the cells stop `inset` short of their water's own faces (against shimmer). The fill line allows
# that rim and the chain walks across it, so it must stay a seam: at most this, and two touching ice
# blocks leave at most twice it between their sheets.
ICE_INSET_MOST = 0.25
# Q5: a body whose feet lie less than `sink` under a cell's top does not stop its freeze. Under the
# R15 HipHeight (2), the root and torso, which collide, stay over the ice; only the legs, which do not,
# can be in it (the Humanoid then stands up onto it).
ICE_SINK_MOST = 2.0
# The W3 fix round's s-M1: WeaponService.trackAir records where a body last stood once a Heartbeat;
# a body leaving a bank is at most this many frames' flat travel back from its edge when last seen.
SERVER_FRAME_HZ = 60
# The W3 third fix round's fd-m2 (the lead's ruling, which replaces d-m6's): a frozen sheet is not a
# camp floor and is not held to levels.floorThickness. It need only be thicker than the fastest fall
# onto it moves in one physics step (Roblox steps physics at PHYSICS_HZ), so a slam cannot tunnel
# through it, and thinner than the R15 root Part (ROOT_TALL; it is 2 x 2 x 1), so a root never lies
# wholly inside a sheet that freezes round a body the server's copy saw a round trip late.
PHYSICS_HZ = 240.0
ROOT_TALL = 2.0
THEME_PATH = REPO_ROOT / "src" / "client" / "UI" / "Theme.luau"
# The Theme numbers the highest camera is built from (the client's; read from the file, never copied).
THEME_KEYS = ("COMBAT_CAMERA_PIVOT_HEIGHT", "COMBAT_CAMERA_MIN_PITCH_DEGREES", "COMBAT_SHAKE_MAX_STUDS")
# ... and the spherecast's radius, which keeps a camera off a wall (the sight gate's stand-off).
SIGHT_THEME_KEYS = ("COMBAT_CAMERA_COLLISION_RADIUS",)
# m1: the drawn body (CrowdRenderer's torso, in radii), read from the file like Theme.
# The fix round's d-M1: AbilityService's MECHANICS rows whose target is "dash" (the caster is carried).
ABILITY_SERVICE_PATH = REPO_ROOT / "src" / "combat" / "server" / "Services" / "AbilityService.luau"
RENDERER_PATH = REPO_ROOT / "src" / "combat" / "client" / "Controllers" / "CrowdRenderer.luau"
RENDERER_KEYS = ("TORSO_WIDTH", "TORSO_DEPTH")
# L4 W2 (contract 7): a dressed level's invisible walls, and the raider models' drawn reach.
DRESS_DIR = CONFIG_DIR / "LevelDress"
RAIDER_MODELS_PATH = CONFIG_DIR / "RaiderModels.json"
# The "can" claims' blocking test: a flat move that crosses a dress wall's footprint grown by a
# body's half width (BODY_RADIUS, below) while under its top is blocked.
WALLS = True
EPS = 1e-6
SIDES = ("north", "south", "west", "east")
# Where each side lies in a footprint (x0, x1, z0, z1).
SIDES_AT = {"west": 0, "east": 1, "north": 2, "south": 3}


# ---------------------------------------------------------------------------------------------
# Boxes
# ---------------------------------------------------------------------------------------------


class Solid:
    """Something a player can stand on, seen from above: a rectangle with a top and a bottom. Kind
    `barrier` (L4 W2) is a dress wall: never ground, never standable, never a sight blocker, always
    tall (is_tall), counted in the Parts (part_count's `walls`)."""

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


def fence_thickness(camp, default):
    """The L2 W2 second fix round's m1: how thick a camp's fence is built (LevelGeometry.FenceThickness):
    the layout's own fence.thickness when it is a positive finite number, else `default`
    (levels.fenceThickness). Every helper here that takes a fence `thickness` passes it through this,
    so a caller hands it the config's value and each camp gets its own."""
    return sr.fence_thickness(camp, default)


def fence_strips(camp, thickness):
    """The four fence strips, outside the floor (the Village rule): {side: (x0, x1, z0, z1)}.
    `thickness` is the config's; the camp's own fence.thickness wins (fence_thickness)."""
    x0, x1, z0, z1 = camp_rect(camp)
    t = fence_thickness(camp, thickness)
    return {"north": (x0 - t, x1 + t, z0 - t, z0), "south": (x0 - t, x1 + t, z1, z1 + t),
            "west": (x0 - t, x0, z0, z1), "east": (x1, x1 + t, z0, z1)}


def gate_rect(camp, gate, thickness):
    """The opening a gate fills in its side's fence strip: (x0, x1, z0, z1). `thickness` is the
    config's; the camp's own fence.thickness wins (fence_thickness)."""
    thickness = fence_thickness(camp, thickness)
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


def solids_of(layout, thickness, floor_depth=1.0, barriers=None):
    """Every standing surface of a layout: solid blocks, camp floors (`floor_depth` deep under
    their top: levels.floorThickness), fences, obstacles, secrets; and with `barriers` (a dress
    file's list, L4 W2) one Solid of kind `barrier` per wall. Every gate but check_walls asks for
    none: the "cannot" gates hold on the grey level, which has no walls (L4W2-14)."""
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
    for wall in barriers or []:
        hx, hy, hz = wall["sx"] / 2, wall["sy"] / 2, wall["sz"] / 2
        found.append(Solid(wall["name"], "barrier", "barrier", wall["x"] - hx, wall["x"] + hx, wall["z"] - hz,
                           wall["z"] + hz, wall["y"] - hy, wall["y"] + hy))
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
    for camp in layout["camps"]:
        reach = wall_reach(fence_thickness(camp, thickness), barrier)
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


def ice_config(levels):
    """Combat.json levels.react.ice (L2-53), or None: LevelService's `Sizes.ice`."""
    ice = (levels.get("react") or {}).get("ice") if isinstance(levels.get("react"), dict) else None
    return ice if isinstance(ice, dict) else None


def part_count(layout, fire_marker=None, ice=False, walls=0):
    """The Parts LevelService.Build makes (LevelGeometry.Pieces): one per block; per camp the
    floor, the fence cut at its gates (four sides, one more piece per gate), the obstacles, the
    checkpoint marker, one marker per fire spot (only when Combat.json levels.fireMarkerSize
    is given) and one tent marker per layout `tent` block (L1b-W2-9); only a camp that locks
    (L1b-12) also has its gates and the four barrier boxes; per secret the marked block and its
    sign; and one ice piece per open cell of every ice block (L2-53, sim_range.ice_cells, only
    when levels.react.ice is given). `fire_marker` = levels.fireMarkerSize and `ice` =
    levels.react.ice (default: read from Combat.json). `walls`: a dressed level's barriers, one Part
    each (L4 W2: LevelDress.Accept holds #pieces + #barriers to levels.maxParts); the harness asks
    for LevelGeometry.Pieces' count alone (0)."""
    if fire_marker is None or ice is False:
        read = sr.load_config(sr.COMBAT_PATH)["levels"]
        fire_marker = (read.get("fireMarkerSize") or False) if fire_marker is None else fire_marker
        ice = ice_config(read) if ice is False else ice
    parts = len(layout["blocks"]) + len(sr.ice_cells(layout, ice))
    for camp in layout["camps"]:
        gates = len(camp.get("gates") or [])
        locks = camp.get("locks") is True
        obstacles = len(camp.get("obstacles") or []) + int(camp.get("obstacleCount") or 0)
        parts += 1 + (4 + gates if camp.get("fence") else 0) + (gates if locks else 0) + obstacles
        parts += (1 if camp.get("checkpoint") else 0) + (4 if layout.get("barrier") and locks else 0)
        parts += len(fire_spots(camp)) if fire_marker else 0
        parts += 1 if camp.get("tent") else 0
    return parts + 2 * len(layout["secrets"]) + walls


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


def wall_reach_of(move):
    """How far from where he stood a player lands on the flat, the walk-off grace included: a
    jump, a double jump and a dash (stray_reach) after walking movement.coyoteSeconds off an edge,
    falling that long first (BALANCE "L2 W1" c3: 2.4 studs out, 1.4 lower; 49.3 on today's numbers;
    the fix round's d-m1: the reach the unclimbable and walled-camp rules measure)."""
    grace = move.get("coyoteSeconds") or 0
    return stray_reach(move, sr.GRAVITY * grace * grace / 2) + move["walkSpeed"] * grace


def ability_height(proving):
    """The most any weapon ability lifts its caster (Leap Smash's `height`): L1c-1."""
    return max([0.0] + [float(((w.get("ability") or {}).get("height")) or 0) for w in proving["weapons"].values()])


def climb_max(move, ability):
    """L1c-3: the highest top a player gets onto from a surface: jump, double jump, the highest
    ability lift and a step up."""
    return move["jumpHeight"] + move["doubleJumpHeight"] + ability + STEP_UP


def is_tall(solid):
    """What may be an unclimbable wall: a block of look `wall`, a camp's fence, or a dress wall
    (L4 W2: check_walls holds every one of those unclimbable, so a new standable top fails by name)."""
    return solid.kind in ("fence", "barrier") or (solid.kind == "block" and solid.look == "wall")


def unclimbable(solids, move, ability):
    """L1c-3: the names of the walls nobody stands on. A `wall` block or a camp fence is
    unclimbable when its top stands at least climb_max over every standable surface within
    wall_reach_of (stray_reach and the walk-off grace) of it (that is, nobody lands within reach of
    its foot high enough to get on it);
    another unclimbable wall is not such a surface. The largest set that holds: start from every
    candidate and drop the ones a standable surface beats until nothing changes."""
    reach = wall_reach_of(move)
    climb = climb_max(move, ability)
    standable = ("block", "floor", "secret", "fence", "obstacle")
    bare = exposed(solids)
    found = {s.name for s in solids if is_tall(s)}
    changed = True
    while changed:
        changed = False
        for wall in solids:
            if wall.name not in found:
                continue
            for other in solids:
                if other is wall or other.name in found or other.kind not in standable or other.name not in bare:
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


def trigger_gap(secret, x, z, model=None):
    """SecretFlow.Triggered's flat distance from (x, z) to a chest: under TRIGGER_MODEL "footprint"
    to its block's footprint (the axis-aligned sx x sz rectangle round its centre; 0 on or over
    it), under "centre" to its centre."""
    hx, hz = (0.0, 0.0) if (model or TRIGGER_MODEL) == "centre" else (secret["sx"] / 2, secret["sz"] / 2)
    return math.hypot(max(abs(x - secret["x"]) - hx, 0.0), max(abs(z - secret["z"]) - hz, 0.0))


def secret_triggered(secret, x, y, z, rules, model=None):
    """SecretFlow.Triggered, term for term: a root at (x, y, z) opens the chest when it is within
    secretReach of it on the flat (TRIGGER_MODEL, closed) and from secretBelow under to secretAbove
    over the block's bottom (closed). rules = secret_rules(levels); None opens nothing."""
    if rules is None:
        return False
    reach, below, above = rules
    hx, hz = (0.0, 0.0) if (model or TRIGGER_MODEL) == "centre" else (secret["sx"] / 2, secret["sz"] / 2)
    dx = max(abs(x - secret["x"]) - hx, 0.0)
    dz = max(abs(z - secret["z"]) - hz, 0.0)
    rise = y - (secret["y"] - secret["sy"] / 2)
    return dx * dx + dz * dz <= reach * reach and -below <= rise <= above


def footprint_ring(secret, hx, hz, offset, step=0.5):
    """The flat points exactly `offset` from the rectangle of half sizes hx, hz round a secret's
    centre: along each side every `step`, and 16 per corner round its arc."""
    cx, cz = secret["x"], secret["z"]
    ring = []
    for k in range(int(2 * hx / step) + 1):
        x = cx - hx + min(step * k, 2 * hx)
        ring += [(x, cz - hz - offset), (x, cz + hz + offset)]
    for k in range(int(2 * hz / step) + 1):
        z = cz - hz + min(step * k, 2 * hz)
        ring += [(cx - hx - offset, z), (cx + hx + offset, z)]
    for sx, sz in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
        for k in range(17):
            a = math.pi / 2 * k / 16
            ring.append((cx + sx * (hx + offset * math.cos(a)), cz + sz * (hz + offset * math.sin(a))))
    return ring


def standing_roots(secret, solids, chest, solid):
    """Where a root stands on a solid's top near a chest: its standable points (0.5 grid), less
    those where a body on a top under the collidable chest's would overlap its side (nearer its
    footprint than BODY_RADIUS), plus the points exactly BODY_RADIUS off the footprint (a body
    pressed against the chest). A body's overlap is the block's, whatever TRIGGER_MODEL measures."""
    points = standable_points(solids, solid, 0.5)
    if chest is None or solid.top >= chest.top - EPS or chest.bottom >= solid.top + BODY_HEIGHT:
        return points
    hx, hz = secret["sx"] / 2, secret["sz"] / 2
    over = [o for o in solids if o is not solid and o.kind in ("block", "floor", "secret", "fence", "obstacle")
            and o.top > solid.top + EPS]
    pressed = [(x, z) for x, z in footprint_ring(secret, hx, hz, BODY_RADIUS)
               if solid.holds(x, z) and not any(o.holds(x, z) for o in over if o is not chest)]
    return [(x, z) for x, z in points if trigger_gap(secret, x, z, "footprint") >= BODY_RADIUS - EPS] + pressed


def trigger_tops(secret, solids, chest, rules, tall):
    """Every standable top (an unclimbable wall left out) with a point where a standing root opens
    the chest (standing_roots, then secret_triggered at the root's height): [the solid's name]."""
    if rules is None:
        return []
    reach = rules[0]
    foot = (secret["x"] - secret["sx"] / 2, secret["x"] + secret["sx"] / 2,
            secret["z"] - secret["sz"] / 2, secret["z"] + secret["sz"] / 2)
    held = []
    for s in solids:
        if s.name in tall or s.kind not in ("block", "floor", "secret", "fence", "obstacle"):
            continue
        if rect_gap((s.x0, s.x1, s.z0, s.z1), foot) > reach + math.hypot(secret["sx"], secret["sz"]) + EPS:
            continue
        y = s.top + sr.ROOT_HEIGHT
        if any(secret_triggered(secret, x, y, z, rules) for x, z in standing_roots(secret, solids, chest, s)):
            held.append(s.name)
    return held


def trigger_region(secret, reach, step=0.5):
    """The flat points a root opens the chest over (trigger_gap <= reach, closed), on a `step` grid
    of their bounding box plus the boundary: under "footprint" a rounded rectangle, under "centre"
    a disc."""
    hx, hz = (0.0, 0.0) if TRIGGER_MODEL == "centre" else (secret["sx"] / 2, secret["sz"] / 2)
    x0, x1 = secret["x"] - hx - reach, secret["x"] + hx + reach
    z0, z1 = secret["z"] - hz - reach, secret["z"] + hz + reach
    xs = [x0 + step * k for k in range(int((x1 - x0) / step) + 1)] + [x1]
    zs = [z0 + step * k for k in range(int((z1 - z0) / step) + 1)] + [z1]
    return ([(x, z) for x in xs for z in zs if trigger_gap(secret, x, z) <= reach + EPS]
            + footprint_ring(secret, hx, hz, reach))


def ability_ids(expeditions):
    """The ids Expeditions.json `abilities.list` sells (Unlocks.HasKey holds only these)."""
    return [a.get("id") for a in ((expeditions.get("abilities") or {}).get("list") or []) if isinstance(a, dict)]


def lifting_abilities(proving):
    """Every family's ability that lifts its caster, worst case (L2-18 c): [(family, ability)]."""
    return [(family, w["ability"]) for family, w in sorted(proving["weapons"].items())
            if (w.get("ability") or {}).get("height") and (w.get("ability") or {}).get("castRange")]


def fielded_lifts(proving):
    """The lifting abilities a level fields (L2-37): every family in `weapons`, since W2's lobby
    picker and the Studio lever can carry any into a level (L3 will sell more)."""
    return [family for family, _ability in lifting_abilities(proving)]


def dashing_abilities(proving, text=None):
    """Every family's ability that carries its caster along the flat, holding his height in the air
    (AbilityService MECHANICS `target = "dash"`: Impale Dash, MovementController.Lunge over its
    `range`), and every id an alias line `MECHANICS.<id> = MECHANICS.<other>` gives a dash's entry
    (as W2's dragonBreath and W3's frostQuake alias theirs; the W3 fix round's s1): [(family,
    ability)]. `text` stands for AbilityService.luau's (the mutants' copy)."""
    import re

    if text is None:
        text = ABILITY_SERVICE_PATH.read_text(encoding="utf-8") if ABILITY_SERVICE_PATH.exists() else ""
    ids = set(re.findall(r'^\s*(\w+)\s*=\s*\{\s*target\s*=\s*"dash"', text, re.MULTILINE))
    aliases = re.findall(r'^\s*MECHANICS\.(\w+)\s*=\s*MECHANICS\.(\w+)\s*$', text, re.MULTILINE)
    grew = True
    while grew:  # an alias of an alias resolves too
        grew = False
        for alias, base in aliases:
            if base in ids and alias not in ids:
                ids.add(alias)
                grew = True
    return [(family, w["ability"]) for family, w in sorted(proving["weapons"].items())
            if (w.get("ability") or {}).get("id") in ids and is_number(w["ability"].get("range"))]


def air_carry(move, need):
    """How far on the flat an owner of the double jump is from where he left the ground while his
    feet are still `need` or more over it: the walk-off grace, both jumps' climb and the fall down to
    `need`, at walk speed, and a dash (which holds his height); None when his jumps never get there."""
    rise = move["jumpHeight"] + move["doubleJumpHeight"]
    if need > rise + EPS:
        return None
    up = math.sqrt(2 * move["jumpHeight"] / sr.GRAVITY) + math.sqrt(2 * move["doubleJumpHeight"] / sr.GRAVITY)
    down = math.sqrt(2 * max(rise - need, 0.0) / sr.GRAVITY)
    return move["walkSpeed"] * (up + down + (move.get("coyoteSeconds") or 0)) + move["dashDistance"]


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


def lift_rise(move, air):
    """WallClip.Rise: how high a caster's jumps carry him, the double jump on top when he owns it
    (`air`); the most a ground point may stand over his floor, and over a void his floor is his
    feet less this (CasterFloor)."""
    return move["jumpHeight"] + (move["doubleJumpHeight"] if air else 0)


def lift_carry(move, air):
    """How far on the flat a take-off at the top of his jumps is from where he left the ground: walk
    speed over the climb of one jump, and of the double jump after it when he owns it (`air`), plus
    the walk-off grace (movement.coyoteSeconds) for an owner (the fix round's d-M1 and d-m1)."""
    up = math.sqrt(2 * move["jumpHeight"] / sr.GRAVITY)
    if air:
        up += math.sqrt(2 * move["doubleJumpHeight"] / sr.GRAVITY) + (move.get("coyoteSeconds") or 0)
    return move["walkSpeed"] * up


def lift_takeoffs(solids, box, reach, skip, tall, move, model, air=False, low=None, height=0.0):
    """(c)'s take-offs for one cast range: {(x, z, feet): (the caster's floor, how)}. Every
    standable top (not an unclimbable wall, not a key surface) within castRange and a body's radius
    of the key tops, on a LIFT_GRID grid, cast on the ground and at the top of his jumps; and off
    each such top's edge at the top of his jumps, pushed out 1 and 4 studs, as far as the jumps
    carry at walk speed (lift_carry), and that plus half and all of an air dash (which holds its
    height). There the caster's floor is the top under him, or over a void LIFT_MODEL's rule. His
    jumps are one jump, or with `air` the jump and the double jump (lift_rise). With `low` (the
    lowest key top less a step up) and the ability's `height`, a top none of whose take-offs can
    lift the feet that high (lift_routes' bound, his floor at most the highest standable top within
    the pushes that his jumps clear) gives none."""
    jump = lift_rise(move, air)
    standable = ("block", "floor", "secret", "fence", "obstacle")
    top_reach = lift_carry(move, air)
    offs = (1.0, 4.0, top_reach, top_reach + move["dashDistance"] / 2, top_reach + move["dashDistance"])
    takeoffs = {}
    bare = exposed(solids)
    for s in solids:
        if s.kind not in standable or s.name in tall or s.name in skip or s.name not in bare:
            continue
        if rect_gap((s.x0, s.x1, s.z0, s.z1), box) > reach + BODY_RADIUS + offs[-1]:
            continue
        if low is not None:
            floor = max([s.top] + [o.top for o in solids if o.kind in standable and o.top <= s.top + jump + EPS
                                   and o.gap_to(s) <= offs[-1] + EPS])
            bound = (max(s.top + jump, floor + jump) + height if model == "today"
                     else max(s.top + jump, floor + jump + height))
            if bound < low - EPS:
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


def lift_arc_route(x, z, feet, caster, grid, near, keys, box, move, height, model, air=False):
    """One take-off of (c): the first target whose arc puts the feet STEP_UP under a key top or
    higher within BODY_RADIUS of it, as (target x, z, floor, sample x, z, feet, key), or None. A
    target whose line passes no key within BODY_RADIUS is skipped (no sample of it can meet one),
    and an arc is stopped only by the solids its line crosses: the same answer, sooner."""
    jump = lift_rise(move, air)
    low = min(k[4] for k in keys) - STEP_UP
    root = feet + sr.ROOT_HEIGHT
    for dx, dz in grid:
        tx, tz = x + dx, z + dz
        if segment_rect(x, z, tx, tz, box) > BODY_RADIUS + EPS:
            continue
        if all(segment_rect(x, z, tx, tz, kr) > BODY_RADIUS + EPS for kr in keys):
            continue
        floor = max([o.top for o in near if o.holds(tx, tz)], default=None)
        floor = caster if floor is None else floor
        if floor - caster > jump + EPS:
            continue  # GroundPoint refuses it: WallClip.TooHigh with Rise(movement, air)
        to = floor + sr.ROOT_HEIGHT
        apex = (max(root, to) + height if model == "today"
                else max(root, to + height, caster + sr.ROOT_HEIGHT + height))
        if apex - sr.ROOT_HEIGHT < low - EPS:
            continue
        crossed = [o for o in near if segment_rect(x, z, tx, tz, (o.x0, o.x1, o.z0, o.z1)) <= EPS]
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
            if k > 0 and any(o.holds(px, pz) and o.top > f + EPS and o.bottom < f + BODY_HEIGHT - EPS for o in crossed):
                break  # stopped against a solid
    return None


def lift_routes(solids, keys, skip, tall, move, lifts, model=None, air=False):
    """L2-18 (c): every way a player WITHOUT the double jump gets a lifting ability's arc onto a
    secret's ledge (lift_takeoffs, then lift_arc_route); with `air`, a player WITH it onto the given
    tops (the fix round's d-M1: the cave's ridge and roof). Targets as GroundPoint finds them: every
    point within castRange on the flat (a LIFT_GRID grid and LIFT_RIM points on the rim); its floor
    is the highest top under it, or the caster's floor over a void; refused when more than
    WallClip.Rise(movement, air) over the caster's floor. The arc is MovementController.Leap's under
    LIFT_MODEL, sampled every LIFT_STEP and stopped at the first solid over the feet. One route per
    take-off, at most LIFT_ROUTES_MAX: [text]."""
    model = model or LIFT_MODEL
    jump = lift_rise(move, air)
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
        for (x, z, feet), (caster, how) in sorted(lift_takeoffs(solids, box, reach, skip, tall, move, model,
                                                                air, low, height).items()):
            # No target stands more than his rise over his floor, so no arc from here tops this:
            # the bound below without the scan of what is near.
            ceiling = max(feet, caster + jump) + height if model == "today" else max(feet, caster + jump + height)
            if ceiling < low - EPS:
                continue
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
            # Only the keys an arc from here can meet: within castRange and a body of him, and no
            # higher than the bound lifts the feet.
            mine = [kr for kr in keys if point_rect(kr, x, z) <= reach + BODY_RADIUS + EPS
                    and kr[4] - STEP_UP <= bound - sr.ROOT_HEIGHT + EPS]
            if not mine:
                continue
            hit = lift_arc_route(x, z, feet, caster, grid, near, mine, box, move, height, model, air)
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
    abilities.list): only those may pay (e); (a)'s "a standing root opens it from somewhere" runs
    for every secret. (a) with the key: the ledge's band and a standable point inside the trigger;
    (b) without it, no jump, step up and dash gets on the ledge (the old lookout test, unclimbable
    walls left out); (c) nor any lifting ability's arc (lift_routes); (d) the trigger is met from
    nowhere else: no other standable top puts a standing root in it, and all the ground within the
    reach of its footprint lies over the ledge or an unclimbable wall, so an airborne root meets it
    only over the ledge, where (b) and (c) keep him out. Every rule models one body: players do not
    collide with players in the dungeon place (BarrierGroups, the fix round's d1), so nobody stands
    on a partner's head."""
    move, levels = ctx["move"], ctx["levels"]
    tag = f"{name}:"
    jump = jump_facts(move)
    rules = secret_rules(levels)
    sold = ctx.get("abilityIds") or []
    for secret in layout["secrets"]:
        sid, needs = secret["id"], secret["needs"]
        chest = next((s for s in solids if s.name == f"Secret_{sid}"), None)
        # (a), for EVERY secret whatever its key (the fix round, s1 + d2): a standing root opens it
        # from somewhere, so a chest whose key is sold later is never one nobody can open. With a
        # sold key the point must be on the ledge or the chest, which (d) below makes the only ones.
        if rules is not None and chest is not None:
            reach, below, above = rules
            floor = secret["y"] - secret["sy"] / 2
            held = trigger_tops(secret, solids, chest, rules, tall)
            base = secret_base(solids, secret)
            if needs in sold and base is not None:
                held = [h for h in held if h in (base.name, chest.name)]
            measured = (f"its {secret['sx']:g} x {secret['sz']:g} footprint" if TRIGGER_MODEL == "footprint"
                        else "its centre (TRIGGER_MODEL centre)")
            expect(bool(held), f"{tag} the {sid}'s trigger (levels.secretReach {reach:g} from {measured}, a root "
                   f"{below:g} under to {above:g} over its foot at {floor:g}) holds a standable point"
                   + (" on its ledge or the chest, with the key" if needs in sold else f" (its key {needs} is not sold yet)")
                   + ": " + (", ".join(sorted(set(held))) if held else "none") + " (L2-18a)")
        if needs not in sold:
            continue
        if needs != AIR_JUMP:
            expect(False, f"{tag} the {sid} needs {needs}, a sold ability check_levels has no reach rule for (L2-18)")
            continue
        base = secret_base(solids, secret)
        if base is None or chest is None or rules is None:
            expect(False, f"{tag} the {sid} stands on a ledge block, and Combat.json levels has "
                   f"{', '.join(SECRET_RULES)} (L2-18)")
            continue
        reach, below, above = rules
        keys = key_rects(solids, base, chest)
        skip = {base.name, chest.name}
        # (a) The owner's band, and the trigger holds a standable point on a key top.
        # L4 W2: a climb's chest (tools/check_parkour.py CLIMBS) is held to the band over its last ledge.
        road, away = check_parkour.ledge_below(layout, secret) or route_height_near(layout, secret["x"], secret["z"])
        rise = base.top - road
        lo = move["jumpHeight"] + STEP_UP
        hi = move["jumpHeight"] + move["doubleJumpHeight"] - LOOKOUT_UNDER_DOUBLE
        expect(lo < rise <= hi, f"{tag} the {sid} ledge's top is over {lo:g} and at most {hi:g} studs above the "
               f"road under it (over one jump's {move['jumpHeight']:g} and a step up of {STEP_UP:g}, under jump + "
               f"double jump's {move['jumpHeight'] + move['doubleJumpHeight']:g}): {rise:g}, {away:.0f} studs from "
               f"the road (L2-18a)")
        # (b) One jump, a step up and a dash, from every surface but the keys and unclimbable walls.
        ways, closest = [], (math.inf, None)
        bare = exposed(solids)
        for s in solids:
            if s.name in skip or s.name in tall or s.name not in bare:
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
        known = False  # L2-37: the W1 known limit is gone, every family can enter
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
        others = [h for h in trigger_tops(secret, solids, chest, rules, tall) if h not in skip]
        loose = [(x, z) for x, z in trigger_region(secret, reach) if not base.holds(x, z) and not any(
            s.name in tall and s.holds(x, z) for s in solids)]
        expect(not others and not loose,
               f"{tag} the {sid}'s trigger is met only on its ledge: no other standable top puts a standing root in it, "
               f"and the ground within {reach:g} of its {'footprint' if TRIGGER_MODEL == 'footprint' else 'centre'} lies "
               f"over {base.name} or an unclimbable wall (L2-18d)"
               + (f" (a root on {', '.join(others)})" if others else "")
               + (f" (off the ledge at ({loose[0][0]:.1f}, {loose[0][1]:.1f}))" if loose else ""))


def key_chain(file, layout, expeditions, weapons):
    """L2-37 (e): which keys a player can come to hold on this level. A sold ability resolves at
    step 0; a family that a paying secret gives resolves one step after that secret's key; a family
    Expeditions.json `found` names (L2-51: found on a map node, the Castle) resolves at step 1 with
    the root "found:<node>"; an element ("fire", "ice") resolves with the first family that carries
    it. A key in a cycle never resolves. ({key: (step, the root its chain starts from: a sold
    ability or "found:<node>")}, {family: step})."""
    sold = [a.get("id") for a in ((expeditions.get("abilities") or {}).get("list") or []) if isinstance(a, dict)]
    needs = {s["id"]: s["needs"] for s in layout["secrets"]}
    entries = file.get("secrets") or {}
    keys = {aid: (0, aid) for aid in sold}
    families = {family: (1, f"found:{entry.get('node')}") for family, entry in sorted(found_families(expeditions).items())
                if family in weapons}
    changed = True
    while changed:
        changed = False
        for sid, entry in sorted(entries.items()):
            family, key = (entry or {}).get("family"), needs.get(sid)
            if family and key in keys and family not in families:
                families[family] = (keys[key][0] + 1, keys[key][1])
                changed = True
        for element in REACT_WORDS:
            carriers = [families[f] for f in families if (weapons.get(f) or {}).get("element") == element]
            if element not in keys and carriers:
                keys[element] = min(carriers)
                changed = True
    return keys, {f: step for f, (step, _root) in families.items()}


def found_families(expeditions):
    """Expeditions.json `found` (L2-51): {family: {node, text}}, the entries that are tables."""
    found = expeditions.get("found")
    return {f: e for f, e in found.items() if isinstance(e, dict)} if isinstance(found, dict) else {}


def chain_price(sold, root):
    """The Valor a chest behind a chain must stay under: the price of the sold ability the chain
    starts from, and for a chain from a map node (L2-51, "found:<node>") the dearest sold ability's."""
    if root in sold:
        return (sold[root].get("price") or {}).get("valor")
    prices = [(a.get("price") or {}).get("valor") for a in sold.values()]
    prices = [v for v in prices if is_number(v)]
    return max(prices) if prices else None


def level_stock(file, layout, ranks, difficulty="normal"):
    """L2-37 (e): the level's whole stock in its material at a difficulty: every resident and every
    tent body fielded there, and every boss, at its rewardMult (what a first clear pays at most,
    the clear bonuses aside; the simulator measures the run)."""
    rewards = (file.get("crowd") or {}).get("rewards") or {}
    rank = ranks.get(difficulty, 1)
    defs, _residents = sr.groups_of(file, layout, rank, ranks)
    tents, _stocks = sr.tents_of(file, layout, rank, ranks)
    kinds = [u["kind"] for d in defs for u in d["units"] for _ in range(u["count"])]
    kinds += [k for t in tents for k in t["kinds"]]
    kinds += [w["boss"]["kind"] for st in file.get("stages") or [] for w in st.get("waves") or [] if w.get("boss")]
    mult = ((file.get("difficulties") or {}).get(difficulty) or {}).get("rewardMult", 1)
    return sum((rewards.get(k) or {}).get("materials", 0) for k in kinds) * mult


def check_secret_rewards(file, layout, expeditions, expect, weapons=None, ranks=None):
    """L2-18 (e), L2-13's sizing and L2-37's chain: a level file's secret pays (valor, materials or
    family) only behind a key a player can come to hold (key_chain: a sold ability, or an element a
    family another secret pays carries, its own key resolving first; no cycle); then at least
    SECRET_VALOR_MIN Valor and under the price of the ability its chain starts from, and its
    material within SECRET_MATERIAL_SHARE of the level's Normal stock."""
    entries = file.get("secrets") or {}
    sold = {a.get("id"): a for a in ((expeditions.get("abilities") or {}).get("list") or []) if isinstance(a, dict)}
    needs = {s["id"]: s["needs"] for s in layout["secrets"]}
    keys, families = key_chain(file, layout, expeditions, weapons or {})
    stock = level_stock(file, layout, ranks or {}) if ranks is not None else None
    lo_m, hi_m = SECRET_MATERIAL_SHARE
    bad, told = [], []
    for sid, entry in sorted(entries.items()):
        pays = [key for key in ("valor", "materials", "family") if key in (entry or {})]
        if not pays:
            told.append(f"{sid} pays nothing")
            continue
        key = needs.get(sid)
        if key not in keys:
            bad.append(f"{sid} pays {', '.join(pays)} behind {key}, which no ability opens and no family another secret "
                       f"pays carries")
            continue
        step, root = keys[key]
        price = chain_price(sold, root)
        valor = entry.get("valor") or 0
        if not (is_number(price) and is_number(valor) and SECRET_VALOR_MIN <= valor < price):
            bad.append(f"{sid}'s {valor} Valor is not at least {SECRET_VALOR_MIN} and under {root}'s price {price}"
                       + (" (the dearest sold ability's)" if root not in sold else ""))
        amount = entry.get("materials") or 0
        if stock is not None and amount and not (lo_m * stock - EPS <= amount <= hi_m * stock + EPS):
            bad.append(f"{sid}'s {amount} {file.get('material')} is not {lo_m:.0%}-{hi_m:.0%} of the Normal stock {stock:g}")
        chain = f"{root}" + (f" -> ... -> {key} (step {step})" if key != root else "")
        told.append(f"{sid} behind {chain}: {valor} Valor, {amount} {file.get('material')}"
                    + (f" ({amount / stock:.0%} of the Normal stock {stock:g})" if stock and amount else "")
                    + (f", the {entry['family']}" if entry.get("family") else ""))
    expect(not bad, f"{file['id']}: a secret pays only behind a key a player comes to hold (a sold ability, or an "
           f"element a family another secret pays carries, its key first, no cycle), then {SECRET_VALOR_MIN} Valor or "
           f"more and under the price of its chain's ability, its material {lo_m:.0%}-{hi_m:.0%} of the Normal stock "
           f"(L2-18e, L2-13, L2-37): " + ("; ".join(bad) if bad else "; ".join(told) or "no secrets"))


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
        if not (isinstance(aid, str) and 0 < len(aid.encode("utf-8")) <= ABILITY_ID_MAX):
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
           f"{ABILITY_ID_MAX} bytes, a name, a text, a whole price in Valor over 0 and an order, no id twice, and "
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
        # The L2 W2 second fix round's m1: a camp's own fence.thickness is a size above 0
        # (LevelGeometry.Pieces refuses anything else); `own` is what this camp builds.
        given = (fence or {}).get("thickness")
        expect(given is None or (isinstance(given, (int, float)) and not isinstance(given, bool) and 0 < given < math.inf),
               f"{tag} camp {cid}: its fence.thickness, when it names one, is a size above 0: {given}")
        own = fence_thickness(camp, thickness)
        # L1c-3: a fence nobody gets on (every strip unclimbable) is exempt: no root stands on it.
        walled = bool(fence) and all(f"Camp_{cid}_Fence_{side}" in tall for side in SIDES)
        expect(bool(fence) and 0 < fence["height"] and (walled or fence["height"] <= levels["triggerHeight"] - sr.ROOT_HEIGHT),
               f"{tag} camp {cid} has a fence, and a root on its top is inside the trigger's height "
               f"(levels.triggerHeight {levels['triggerHeight']:g})" + (f": {fence['height']:g} high" if fence else "")
               + (f" (an unclimbable wall: its top is at least {climb_max(move, ctx['abilityHeight']):g} over every "
                  f"standable surface within {wall_reach_of(move):.1f}, so nobody stands on it; L1c-3)" if walled else ""))
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
        reach = wall_reach(own, barrier)
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
        lo, hi = (x0 - own, x1 + own) if axis == "x" else (z0 - own, z1 + own)
        drop = camp["y"] + (fence["height"] if fence else 0) - layout["killY"]
        clear = stray_reach(move, 0)
        fenced = (x0 - own, x1 + own, z0 - own, z1 + own)
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
        expect(found == wanted, f"{tag} {len(wanted)} secrets, {', '.join(f'{k} ({v})' for k, v in wanted.items())}: "
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
    # L4 W2 (MISSIONS_DESIGN 28): the climbs tools/check_parkour.py names, on this module's helpers.
    check_parkour.check_climbs(sys.modules[__name__], name, layout, ctx, expect, solids, tall)
    # L2-47: the road's bends cannot be hopped.
    check_route_skips(name, layout, ctx, expect, solids, tall)
    # L4 W2 (contract 7, L4W2-14): a dressed level's walls only remove moves.
    walls = check_walls(name, layout, ctx, expect, solids, tall)
    deep = spec.get("deepWater")
    if deep:
        check_deep_water(name, layout, ctx, expect, solids, deep)

    check_kill_height(tag, layout, solids, levels, expect)
    parts = part_count(layout, levels.get("fireMarkerSize") or False, ice_config(levels), walls)
    tents = sum(1 for c in layout["camps"] if c.get("tent"))
    cells = len(sr.ice_cells(layout, ice_config(levels)))
    expect(parts <= levels["maxParts"], f"{tag} {parts} Parts, {tents} of them tent markers, {cells} ice cells and {walls} "
           f"dress walls (levels.maxParts {levels['maxParts']}; tools/crowd_harness holds the count less the walls to "
           f"LevelGeometry.Pieces', LevelDress.Accept the whole)")
    facts["parts"] = parts
    return facts


def check_deep_water(name, layout, ctx, expect, solids, deep):
    """L2-52, L2-57 and L2-60 "deep water" (it replaces the W1 creek rule): every water block is
    deep (it does not collide, so a fall goes through it to killY and the free rescue); the named ice
    blocks react to ice; every walked route sample over a water footprint stands on a solid top at
    the route's height (the bridge), the water's top at least WATER_UNDER under it; the water's tops
    lie at one height; no two ice blocks overlap (they may touch: the W3 fix round's s-s2, as
    StageFlow.Validate). And L2-58: every landing stands on solid ground at its height, outside every
    camp's fenced rectangle, on a surface a player reaches from the start. And the W3 fix round's s-M1 and Q3: a fall
    through deep water comes back to a landing, judged by where the body last stood (the server's
    frame: WeaponService.LastGround) and by where it is: every deep water block whose footprint lies
    within a dash-off's carry (dashDistance + walkSpeed over the fall from the top to killY + a
    body's radius) of a top a player stands on, the water as built or frozen, has a landing; and
    where such a top meets a landing water's footprint (the bridge over it, the bank beside it, its
    frozen sheets), player.rescue.outside is at least one server frame of the dash, the most a body
    leaving that edge was last seen back from it."""
    tag = f"{name}:"
    waters = [b for b in layout["blocks"] if b["look"] == "water"]
    solid = [b.get("name") for b in waters if b.get("collide") is not False]
    named = {b.get("name"): b for b in waters}
    cold = [n for n in deep.get("ice") or [] if (named.get(n) or {}).get("react") != "ice"]
    tops = {round(b["y"] + b["sy"] / 2, 3) for b in waters}
    samples = walked_samples(layout["route"], SAMPLE * 4)
    under, wet = [], 0
    for x, z, leg in samples:
        over = [b for b in waters if abs(x - b["x"]) <= b["sx"] / 2 + EPS and abs(z - b["z"]) <= b["sz"] / 2 + EPS]
        if not over:
            continue
        wet += 1
        a, b = layout["route"][leg - 1], layout["route"][leg]
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        y = a["y"] + (b["y"] - a["y"]) * (math.hypot(x - a["x"], z - a["z"]) / run if run > EPS else 0.0)
        top, _s = ground(solids, x, z, y + WALK_RISE, kinds=("block", "floor"))
        water = max(w["y"] + w["sy"] / 2 for w in over)
        if top is None or abs(top - y) > EPS or top - water < WATER_UNDER - EPS:
            under.append(f"({x:g}, {z:g}) " + ("over nothing" if top is None else f"on {top:g}, the water {top - water:g} under"))
    expect(bool(waters) and not solid and not cold and len(tops) == 1 and wet > 0 and not under,
           f"{tag} deep water: every water block is deep (no collision: a fall goes through to killY and the free rescue), "
           f"{', '.join(deep.get('ice') or [])} react to ice, the route crosses it only on a bridge at its own height with "
           f"the water at least {WATER_UNDER:g} under, and the water's tops lie at one height (L2-52, L2-57, L2-60): "
           f"{len(waters)} water blocks, {wet} route samples over water"
           + (f"; solid: {', '.join(map(str, solid))}" if solid else "") + (f"; not ice: {', '.join(cold)}" if cold else "")
           + (f"; tops {sorted(tops)}" if len(tops) != 1 else "") + (f"; {'; '.join(under[:3])}" if under else "")
           + ("; the route never crosses it" if not wet else ""))
    # s-s2: ice footprints touch, never overlap (two frozen tops at one height on one ground).
    ices = [b for b in layout["blocks"] if b.get("react") == "ice"]
    crossed = [f"{a.get('name')} and {b.get('name')}" for i, a in enumerate(ices) for b in ices[i + 1:]
               if sr.ice_overlap(a, b)]
    touching = [f"{a.get('name')} and {b.get('name')}" for i, a in enumerate(ices) for b in ices[i + 1:]
                if not sr.ice_overlap(a, b) and rect_gap(*(((x["x"] - x["sx"] / 2, x["x"] + x["sx"] / 2, x["z"] - x["sz"] / 2,
                                                             x["z"] + x["sz"] / 2) for x in (a, b)))) <= EPS]
    expect(not crossed, f"{tag} no two ice blocks overlap, so no two frozen tops lie at one height on the same ground "
           f"(they may touch; the W3 fix round's s-s2, StageFlow.Validate): "
           + (f"overlap: {', '.join(crossed)}" if crossed else f"{len(ices)} ice blocks"
              + (f", touching: {', '.join(touching)}" if touching else "")))
    # L2-58: where a fall into the water comes back.
    levels, move = ctx["levels"], ctx["move"]
    tall = unclimbable(solids, move, ctx["abilityHeight"])
    reached = {s.name for s in reachable_solids(layout, solids, move, ctx["abilityHeight"], (), tall)}
    thickness = levels["fenceThickness"]
    bad, told = [], []
    for b in layout["blocks"]:
        point = b.get("landing")
        if point is None:
            continue
        where = b.get("name") or b["look"]
        if not all(is_number(point.get(k)) for k in ("x", "y", "z")):
            bad.append(f"{where}'s landing is not a point")
            continue
        top, base = ground(solids, point["x"], point["z"], point["y"] + EPS, kinds=("block", "floor"))
        camps = [c["id"] for c in layout["camps"] if point_rect(
            (camp_rect(c)[0] - fence_thickness(c, thickness), camp_rect(c)[1] + fence_thickness(c, thickness),
             camp_rect(c)[2] - fence_thickness(c, thickness), camp_rect(c)[3] + fence_thickness(c, thickness)),
            point["x"], point["z"]) <= EPS]
        if top is None or abs(top - point["y"]) > EPS:
            bad.append(f"{where}'s landing ({point['x']:g}, {point['y']:g}, {point['z']:g}) is not on solid ground at its height")
        elif camps:
            bad.append(f"{where}'s landing is in camp {', '.join(camps)}")
        elif base.name not in reached:
            bad.append(f"{where}'s landing is on {base.name}, which a player does not reach from the start")
        else:
            told.append(f"{where} -> ({point['x']:g}, {point['y']:g}, {point['z']:g}) on {base.name}")
    expect(not bad, f"{tag} every water landing stands on solid ground at its height, outside every camp, on a surface a "
           f"player reaches from the start (L2-58): " + ("; ".join(bad) if bad else "; ".join(told) or "none"))
    # s-M1 and Q3: every deep water a body falls into from where it stood has a landing, and the
    # stood test reaches the edge it left from.
    outside = (ctx.get("rescue") or {}).get("outside")
    ice = ice_config(levels)
    views = [(layout, solids, reached)]
    if ice is not None and any(b.get("react") == "ice" for b in layout["blocks"]):
        frozen = sr.frozen_layout(layout, ice)
        fsolids = solids_of(frozen, thickness, levels["floorThickness"])
        ftall = unclimbable(fsolids, move, ctx["abilityHeight"])
        views.append((frozen, fsolids, {s.name for s in reachable_solids(frozen, fsolids, move, ctx["abilityHeight"], (),
                                                                            ftall)}))
    deep_water = [b for b in waters if b.get("collide") is False]
    frame = (move["dashDistance"] / move["dashSeconds"] / SERVER_FRAME_HZ
             if is_number(move.get("dashSeconds")) and move["dashSeconds"] > 0 else math.inf)
    lacking, edges = {}, {}
    for _view, vsolids, vreached in views:
        for s in vsolids:
            if s.name not in vreached:
                continue
            carry = (move["dashDistance"] + BODY_RADIUS + move["walkSpeed"]
                     * math.sqrt(2 * max(s.top + sr.ROOT_HEIGHT - layout["killY"], 0.0) / sr.GRAVITY))
            for w in deep_water:
                rect = (w["x"] - w["sx"] / 2, w["x"] + w["sx"] / 2, w["z"] - w["sz"] / 2, w["z"] + w["sz"] / 2)
                gap = rect_gap((s.x0, s.x1, s.z0, s.z1), rect)
                if gap > carry + EPS:
                    continue
                wname = w.get("name") or w["look"]
                if w.get("landing") is None:
                    lacking.setdefault(wname, set()).add(f"{s.name} {gap:.1f} off")
                elif gap <= EPS:
                    edges.setdefault(wname, set()).add(s.name)
    short = is_number(outside) and bool(edges) and outside < frame - EPS
    expect(not lacking and is_number(outside) and not short,
           f"{tag} a fall through deep water comes back to a landing, judged by where the body last stood and where it is "
           f"(the W3 fix round's s-M1 and Q3): every deep water block within a dash-off's carry of a top a player stands on, "
           f"the water as built or frozen, has a landing, and player.rescue.outside ({outside}) is at least one server frame "
           f"of the dash ({frame:.2f}) where such a top meets it: "
           + ("; ".join(f"{n} has no landing (from {', '.join(sorted(v)[:3])})" for n, v in sorted(lacking.items()))
              if lacking else "; ".join(f"{n} met by {', '.join(sorted(v))}" for n, v in sorted(edges.items())) or "none"))


def check_kill_height(tag, layout, solids, levels, expect, sheets_apart=False):
    """killY and the depth of the ground (fix round, E5 and part A's item 2). A fall is short and
    a landing holds: killY is at least KILL_UNDER[0] under every standable surface, at most
    KILL_UNDER[1] under the lowest, under every Part's bottom and above KILL_FLOOR; and every
    block a body lands on is at least levels.floorThickness deep, or rests on another solid.
    `sheets_apart` (the frozen layout, the W3 third fix round's fd-m2): a frozen sheet (look "ice")
    is judged by check_ice's sheet line instead (thicker than a slam's step, thinner than a root),
    not by levels.floorThickness."""
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
        if sheets_apart and s.look == "ice":
            continue
        # Thin ground is sound only where another solid lies right under all of it.
        mid_x, mid_z = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
        rests = all(any(o is not s and o.holds(x, z) and o.top >= s.bottom - EPS and o.bottom < s.bottom
                        for o in solids)
                    for x in (s.x0, mid_x, s.x1) for z in (s.z0, mid_z, s.z1))
        if not rests:
            thin.append(f"{s.name} ({s.top - s.bottom:g} deep)")
    expect(not thin, f"{tag} every block a body lands on (looks {', '.join(GROUND_LOOKS)}"
           + ("; the frozen sheets by the sheet line" if sheets_apart else "") + ") is at least "
           f"levels.floorThickness {depth:g} deep, or rests on another solid" + (f" (thin: {', '.join(thin)})" if thin else ""))


def check_origin_chord(name, layout, ctx, expect):
    """The L2 W2 second fix round's m1: ProvingGrounds.json shooting.originWallChord is under the
    thickness of every tall colliding piece a player can stand beside. WeaponService's aim rule
    lets a shot origin's line from the head cross that much solid (an honest shoulder origin clips
    a wall's edge at an inner corner), so a piece no thicker than it lets a forged origin through.
    Every colliding piece the level builds counts: its blocks, every camp's generated fence and
    gates (at the camp's own fence.thickness), cover and secrets. A piece is tall when its top
    stands over the head (root + HEAD_ABOVE_ROOT) of a body on ground beside it: a floor, a secret,
    cover or a ground-look block within BODY_RADIUS of its footprint whose top lies between
    BODY_HEIGHT under the piece's foot and the piece's top. Its thickness is its smallest size: the
    shortest way through it. A low fence, cover or the lobby's rail is shot over, never through."""
    chord = ctx.get("originWallChord")
    if not is_number(chord) or chord < 0:
        expect(False, f"{name}: ProvingGrounds.json shooting.originWallChord is a number of 0 or more ({chord})")
        return
    levels = ctx["levels"]
    solids = solids_of(layout, levels["fenceThickness"], levels["floorThickness"])
    head = sr.ROOT_HEIGHT + HEAD_ABOVE_ROOT
    grounds = [s for s in solids if s.kind in ("floor", "secret", "obstacle")
               or (s.kind == "block" and s.look in GROUND_LOOKS)]
    tall, thin = [], []
    for piece in solids:
        beside = [g for g in grounds if g is not piece and piece.gap_to(g) <= BODY_RADIUS + EPS
                  and piece.bottom - BODY_HEIGHT - EPS <= g.top < piece.top - EPS]
        if not any(piece.top > g.top + head + EPS for g in beside):
            continue
        through = min(piece.x1 - piece.x0, piece.z1 - piece.z0, piece.top - piece.bottom)
        tall.append((through, piece.name))
        if through <= chord + EPS:
            thin.append(f"{piece.name} {through:g}")
    least = min(tall, default=None)
    expect(not thin, f"{name}: shooting.originWallChord {chord:g} is under the thickness of every tall colliding piece "
           f"a player stands beside, generated fences included (top over a standing head, {head:g} over the ground "
           f"beside it)" + (f" (not: {', '.join(sorted(thin))})" if thin else
                            f" ({len(tall)} pieces, the thinnest {least[1]} {least[0]:g})" if least else " (none)"))


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
    expect(level is not None, f"{name}: it resolves to a level (stages, difficulties and a crowd block)")
    if layout is None or level is None:
        return
    kinds = ctx["kinds"]
    # Ruling 6 of the fix round, the reading StageFlow.Validate and the simulator share
    # (sim_range.level_problems): zero and empty mean the same on both sides.
    problems = sr.level_problems(level, layout, ctx["levels"], kinds, ctx["ranks"], ctx["crowdMaxAlive"],
                                 ctx.get("weapons"), set(ctx.get("loadout") or []))
    expect(not problems, f"{name}: maxAlive is an integer of at least 1 wherever it appears, burst is at least 1, "
           f"every camp's targetWaveSeconds is over 0 and its breatherSeconds is not under 0, no camp is without a "
           f"wave, Combat.json has every `levels` number a run reads, and StageFlow.Validate's L1b lines hold"
           + (": " + "; ".join(problems) if problems else ""))
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


# ---------------------------------------------------------------------------------------------
# L4 W2: the dress walls (docs/prompts/l4-w2-contract.md section 7, L4W2-14)
# ---------------------------------------------------------------------------------------------


def dress_barriers(name):
    """Config/LevelDress/<name>.json's `barriers` (the walls LevelDress.Accept arms when the level is
    dressed), or None when the layout has no dress file (it is always grey)."""
    path = DRESS_DIR / f"{name}.json"
    if not path.exists():
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    return list(data.get("barriers") or []) if isinstance(data, dict) else []


def raider_models():
    """Config/RaiderModels.json's kind entries ({} without the file: every kind is a placeholder)."""
    if not RAIDER_MODELS_PATH.exists():
        return {}
    data = json.loads(RAIDER_MODELS_PATH.read_text(encoding="utf-8"))
    return dict((data or {}).get("kinds") or {}) if isinstance(data, dict) else {}


def drawn_body(ctx, kind, factor):
    """How far a body of `kind` is drawn past its centre on the flat, and how high over its feet:
    (out, up, how). The placeholder is its torso box (radius x `factor`, body_reach) and its height;
    a kind whose model counts (Figures: the model's height, radius and headRadius are the kind's, the
    contract's 3.1) is drawn at the model's posedReach over every pose before a hit, with its lit
    cue at its largest where it has one (`withCue`). A model kind falls back to the placeholder when
    its template is missing, so the drawn body is the larger of the two."""
    body = ctx["kinds"].get(kind) or {}
    radius = body.get("radius") or ctx["widest"]
    out, up, how = radius * factor, float(body.get("height") or 0), "placeholder"
    model = (ctx.get("raiders") or {}).get(kind)
    if isinstance(model, dict) and all(is_number(model.get(k)) and is_number(body.get(k))
                                       and abs(model[k] - body[k]) <= 1e-6 for k in ("height", "radius", "headRadius")):
        reach = model.get("posedReach") or {}
        reach = reach.get("withCue") or reach
        if is_number(reach.get("out")) and is_number(reach.get("up")):
            out, up, how = max(out, float(reach["out"])), max(up, float(reach["up"])), "model"
    return out, up, how


def wall_blocks(walls, ax, az, bx, bz, feet):
    """L4W2-14's blocking test: the first dress wall a flat move from a to b with the feet at `feet`
    crosses, its footprint grown by a body's half width, while the feet are under its top (and the
    body over its foot); None when the move is clear."""
    if not WALLS:
        return None
    for w in walls:
        if w.top > feet + EPS and w.bottom < feet + BODY_HEIGHT - EPS and seg_hits_rect(
                ax, az, bx, bz, (w.x0 - BODY_RADIUS, w.x1 + BODY_RADIUS, w.z0 - BODY_RADIUS, w.z1 + BODY_RADIUS)):
            return w
    return None


def path_blocked(walls, solids, points, label):
    """The first blocked leg of a path of route points ({x, z[, y]}): its description, or None. A point
    without a height stands on the ground under it."""
    def feet(p):
        if "y" in p:
            return p["y"]
        top, _s = ground(solids, p["x"], p["z"])
        return top if top is not None else -math.inf

    for index in range(1, len(points)):
        a, b = points[index - 1], points[index]
        hit = wall_blocks(walls, a["x"], a["z"], b["x"], b["z"], max(feet(a), feet(b)))
        if hit is not None:
            return (f"{label} leg {index} ({a['x']:g}, {a['z']:g}) -> ({b['x']:g}, {b['z']:g}) crosses {hit.name} "
                    f"(x {hit.x0:g}..{hit.x1:g}, z {hit.z0:g}..{hit.z1:g}, top {hit.top:g})")
    return None


def clear_takeoff(walls, s, kr, carry, feet, step=2.0):
    """A straight flat line from a point of `s` (a Solid) to a point of the key rectangle `kr` no
    longer than `carry` that crosses no dress wall: ((x, z), (x, z)), or None. Points of `s` on a
    `step` grid and its edges within `carry` of `kr`; the line goes to the nearest point of `kr`,
    else to any rim point of it in reach."""
    x0, x1 = max(s.x0, kr[0] - carry), min(s.x1, kr[1] + carry)
    z0, z1 = max(s.z0, kr[2] - carry), min(s.z1, kr[3] + carry)
    if x1 < x0 - EPS or z1 < z0 - EPS:
        return None
    xs = sorted({x0, x1} | {x0 + step * k for k in range(int((x1 - x0) / step) + 1)})
    zs = sorted({z0, z1} | {z0 + step * k for k in range(int((z1 - z0) / step) + 1)})
    rim = ([(x, z) for x in (kr[0], kr[1]) for z in [kr[2] + step * k for k in range(int((kr[3] - kr[2]) / step) + 1)]]
           + [(x, z) for z in (kr[2], kr[3]) for x in [kr[0] + step * k for k in range(int((kr[1] - kr[0]) / step) + 1)]])
    for x in xs:
        for z in zs:
            if point_rect(kr, x, z) > carry + EPS:
                continue
            nx, nz = min(max(x, kr[0]), kr[1]), min(max(z, kr[2]), kr[3])
            for tx, tz in [(nx, nz)] + rim:
                if math.hypot(tx - x, tz - z) <= carry + EPS and wall_blocks(walls, x, z, tx, tz, feet) is None:
                    return (x, z), (tx, tz)
    return None


def check_walls(name, layout, ctx, expect, solids, tall):
    """L4W2-14 on a layout with a dress file: the walls only remove moves. Every wall a sound box, of
    a name of its own; none reaches into ground a player stands on or into water (the creek, the
    pond and their ice: the crossing); every one unclimbable (is_tall takes `barrier`, so its top
    stands climb_max over every standable surface within wall_reach_of); and the "can" claims hold
    with them up: the route (its gap leg is the trailhead's designed drop), the shortcut route and the
    sneak cross no wall, and every double-jump secret's owner still reaches its key tops from some
    surface in a straight line no wall crosses (the lookout's designed drop). The "cannot" gates
    above ran without them. Returns the number of walls (the Parts gate counts them)."""
    barriers = (ctx.get("dress") or {}).get(name)
    if barriers is None:
        return 0
    tag = f"{name}:"
    move, levels = ctx["move"], ctx["levels"]
    names = [b.get("name") for b in barriers]
    unsound = [str(b.get("name")) for b in barriers
               if not all(is_number(b.get(k)) and math.isfinite(b[k]) for k in ("x", "y", "z", "sx", "sy", "sz"))
               or min(b.get("sx") or 0, b.get("sy") or 0, b.get("sz") or 0) <= 0]
    twins = sorted({str(n) for n in names if names.count(n) > 1 or not isinstance(n, str) or not n})
    expect(bool(barriers) and not unsound and not twins,
           f"{tag} the dress walls (Config/LevelDress/{name}.json barriers) are sound boxes with names of their own: "
           + (f"{len(barriers)} walls" if barriers and not unsound and not twins else
              f"unsound {unsound or 'none'}, repeated or unnamed {twins or 'none'}" if barriers else "none"))
    if unsound or twins or not barriers:
        return len(barriers)
    walls = [s for s in solids_of(layout, levels["fenceThickness"], levels["floorThickness"], barriers)
             if s.kind == "barrier"]
    # No wall in ground a player stands on, nor over water (it would cut the crossing). A bramble is no
    # ground (it burns; the walls end at the mouth it seals, which it overlaps to seal it).
    grounds = [s for s in solids if (s.kind in ("floor", "secret") or (s.kind == "block" and s.look in GROUND_LOOKS))
               and s.name not in tall]
    grounds += [block_solid(b) for b in layout["blocks"] if b.get("collide") is False and b["look"] in ("water", "ice")]
    inside = []
    for w in walls:
        for g in grounds:
            if (min(w.x1, g.x1) - max(w.x0, g.x0) > EPS and min(w.z1, g.z1) - max(w.z0, g.z0) > EPS
                    and w.bottom < g.top + BODY_HEIGHT - EPS and w.top > g.top + EPS):
                inside.append(f"{w.name} over {g.name}")
    expect(not inside, f"{tag} no dress wall reaches into ground a player stands on or water he wades or crosses on ice"
           + (": " + ", ".join(inside[:6]) if inside else f" ({len(walls)} walls, {len(grounds)} grounds)"))
    # Unclimbable: the walls are candidates; another unclimbable wall is no surface.
    every = unclimbable(solids + walls, move, ctx["abilityHeight"])
    climb, reach = climb_max(move, ctx["abilityHeight"]), wall_reach_of(move)
    standable = ("block", "floor", "secret", "fence", "obstacle")
    bare = exposed(solids)
    low = []
    tightest = (math.inf, None)
    for w in walls:
        beats = [(w.top - o.top, o.name) for o in solids if o.kind in standable and o.name not in tall and o.name in bare
                 and w.gap_to(o) <= reach + EPS]
        least = min(beats, default=None)
        if least is not None and least[0] < tightest[0]:
            tightest = (least[0], f"{w.name} over {least[1]}")
        if w.name not in every:
            low.append(f"{w.name} (top {w.top:g}, {least[0]:g} over {least[1]})" if least else w.name)
    expect(not low, f"{tag} every dress wall is unclimbable: its top stands at least {climb:g} (climb_max) over every "
           f"standable surface within {reach:.1f} (wall_reach_of), so none is a new standable top (L4W2-14)"
           + (": not " + ", ".join(low[:6]) if low else
              f" ({len(walls)} walls; the tightest {tightest[1]}, {tightest[0]:g} over)" if tightest[1] else ""))
    # The "can" claims, with the walls up.
    route = path_blocked(walls, solids, layout["route"], "route")
    expect(route is None, f"{tag} with the dress walls up the route (and its gap, the trailhead's designed drop) "
           f"crosses no wall, a body's half width {BODY_RADIUS:g} kept off each (L4W2-14)" + (f": {route}" if route else ""))
    shortcut = path_blocked(walls, solids, layout.get("shortcutRoute") or [], "shortcut route")
    expect(shortcut is None, f"{tag} with the dress walls up the shortcut route crosses no wall (L4W2-14)"
           + (f": {shortcut}" if shortcut else f" ({len(layout.get('shortcutRoute') or [])} points)"))
    sneak = path_blocked(walls, solids, layout.get("sneak") or [], "sneak")
    expect(sneak is None, f"{tag} with the dress walls up the sneak path crosses no wall (L4W2-14)"
           + (f": {sneak}" if sneak else f" ({len(layout.get('sneak') or [])} points)"))
    rules = secret_rules(levels)
    sold = ctx.get("abilityIds") or []
    for secret in layout["secrets"]:
        if secret["needs"] != AIR_JUMP or secret["needs"] not in sold or rules is None:
            continue
        sid = secret["id"]
        chest = next((s for s in solids if s.name == f"Secret_{sid}"), None)
        base = secret_base(solids, secret)
        if chest is None or base is None:
            continue  # check_secret_reach names it
        keys = key_rects(solids, base, chest)
        found, tried = None, []
        for s in sorted(solids, key=lambda o: -o.top):
            if (s.kind not in ("block", "floor", "secret") or s.name in tall or s.name not in bare
                    or s.name in (base.name, chest.name)):
                continue
            for kr in keys:
                need = kr[4] - s.top - STEP_UP
                carry = air_carry(move, need)
                if carry is None or rect_gap((s.x0, s.x1, s.z0, s.z1), kr[:4]) > carry + EPS:
                    continue
                tried.append(s.name)
                line = clear_takeoff(walls, s, kr, carry, s.top)
                if line is not None:
                    found = (s.name, kr[5], line)
                    break
            if found:
                break
        expect(found is not None,
               f"{tag} with the dress walls up the {sid}'s owner still reaches its ledge: a jump, the double jump and a "
               f"dash carry him from a standable surface onto a key top in a straight line no wall crosses (L4W2-14)"
               + (f": from {found[0]} ({found[2][0][0]:g}, {found[2][0][1]:g}) to {found[1]} ({found[2][1][0]:g}, "
                  f"{found[2][1][1]:g})" if found else
                  f": every take-off in reach is walled off ({', '.join(sorted(set(tried))) or 'none in reach'})"))
    return len(walls)


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
    check_cave(name, level, layout, ctx, expect, solids)
    check_ice(name, level, layout, ctx, expect, solids)


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
    """The points of a solid's top a player stands on, on a `step` grid and its edges: nothing
    standable over them there that leaves a body less than BODY_HEIGHT of headroom (L2-37: a
    roofed floor is ground; a top under a solid with room for nobody is not)."""
    kinds = ("block", "floor", "secret", "fence", "obstacle")
    xs = [solid.x0 + step * k for k in range(int((solid.x1 - solid.x0) / step) + 1)] + [solid.x1]
    zs = [solid.z0 + step * k for k in range(int((solid.z1 - solid.z0) / step) + 1)] + [solid.z1]
    near = [o for o in solids if o is not solid and o.kind in kinds and o.top > solid.top + EPS
            and o.bottom < solid.top + BODY_HEIGHT - EPS
            and o.x0 <= solid.x1 and o.x1 >= solid.x0 and o.z0 <= solid.z1 and o.z1 >= solid.z0]
    return [(x, z) for x in xs for z in zs if not any(o.holds(x, z) for o in near)]


_EXPOSED = {}


def exposed(solids):
    """L2-37: the names of the solids a body can stand on at all (standable_points finds a point
    on a 1-stud grid): a top inside a wall or under a roof with no headroom (a bramble that fills a
    mouth up to its roof) is no surface. Kept per solids list."""
    key = id(solids)
    if key not in _EXPOSED or _EXPOSED[key][0] is not solids:
        _EXPOSED[key] = (solids, {s.name for s in solids if standable_points(solids, s, 1.0)})
    return _EXPOSED[key][1]


def region_defn(region, layout):
    """A region group as CampBrain.Melee reads it: its floor's height and its cells."""
    return {"floorY": region["y"], "region": sr.region_cells(layout, region)}


def sight_blockers(solids, stand, floor):
    """L2-37 (R8's sight): what stops a bow's line in plan between a player standing at `stand` and
    a body on a region floor at `floor`: every block of look `wall` or `bramble`, and a camp fence
    taller than a body (the boss room's wall), that rises from under both feet + ROOT_HEIGHT to over
    both heads (a roof over a corridor stops nothing in it), as rectangles (x0, x1, z0, z1)."""
    low, high = min(stand, floor) + sr.ROOT_HEIGHT, max(stand, floor) + BODY_HEIGHT
    return sorted((s.x0, s.x1, s.z0, s.z1) for s in solids
                  if ((s.kind == "block" and s.look in SIGHT_LOOKS) or (s.kind == "fence" and s.top - s.bottom >= BODY_HEIGHT))
                  and s.bottom < low - EPS and s.top > high + EPS)


def ray_entry(px, pz, ux, uz, rect):
    """How far along the ray from (px, pz) in direction (ux, uz) it enters the rectangle (0 from
    on or inside it), or None when it misses."""
    t0, t1 = 0.0, math.inf
    for p, d, lo, hi in ((px, ux, rect[0], rect[1]), (pz, uz, rect[2], rect[3])):
        if abs(d) < 1e-12:
            if p < lo - EPS or p > hi + EPS:
                return None
            continue
        a, c = (lo - p) / d, (hi - p) / d
        t0, t1 = max(t0, min(a, c)), min(t1, max(a, c))
        if t0 > t1 + EPS:
            return None
    return t0


class PlanRooms:
    """L2-37: the plan cut into rooms by the sight blockers, on a SIGHT_RASTER grid (a cell is shut
    only when one blocker covers all of it; neighbours by eight sides): a line of sight never
    leaves its room, so a point whose room holds no region cell sees none, at no cost."""

    def __init__(self, blockers, cells, bounds):
        step = SIGHT_RASTER
        self.x0, self.z0 = math.floor(bounds[0]) - 2 * step, math.floor(bounds[2]) - 2 * step
        self.nx = int(math.ceil((bounds[1] - self.x0) / step)) + 2
        self.nz = int(math.ceil((bounds[3] - self.z0) / step)) + 2
        shut = bytearray(self.nx * self.nz)
        for b in blockers:
            i0, i1 = math.ceil((b[0] - self.x0) / step - EPS), math.floor((b[1] - self.x0) / step + EPS)
            k0, k1 = math.ceil((b[2] - self.z0) / step - EPS), math.floor((b[3] - self.z0) / step + EPS)
            for i in range(max(i0, 0), min(i1, self.nx)):
                for k in range(max(k0, 0), min(k1, self.nz)):
                    shut[i * self.nz + k] = 1
        label = [0] * (self.nx * self.nz)
        rooms = 0
        for start in range(self.nx * self.nz):
            if shut[start] or label[start]:
                continue
            rooms += 1
            label[start] = rooms
            stack = [start]
            while stack:
                here = stack.pop()
                i, k = divmod(here, self.nz)
                for di in (-1, 0, 1):
                    for dk in (-1, 0, 1):
                        ni, nk = i + di, k + dk
                        if 0 <= ni < self.nx and 0 <= nk < self.nz:
                            there = ni * self.nz + nk
                            if not shut[there] and not label[there]:
                                label[there] = rooms
                                stack.append(there)
        self.label = label
        self.lit = set()
        for c in cells:
            for x in (c[0], (c[0] + c[1]) / 2, c[1]):
                for z in (c[2], (c[2] + c[3]) / 2, c[3]):
                    self.lit |= self.rooms_at(x, z)

    def rooms_at(self, x, z):
        """The rooms of the raster cells that touch (x, z)."""
        found = set()
        fx, fz = (x - self.x0) / SIGHT_RASTER, (z - self.z0) / SIGHT_RASTER
        for i in {math.floor(fx - EPS), math.floor(fx + EPS)}:
            for k in {math.floor(fz - EPS), math.floor(fz + EPS)}:
                if 0 <= i < self.nx and 0 <= k < self.nz and self.label[i * self.nz + k]:
                    found.add(self.label[i * self.nz + k])
        return found

    def lit_at(self, x, z):
        return bool(self.rooms_at(x, z) & self.lit)


def sees_region(px, pz, cells, blockers, reach):
    """L2-37 (R8's sight): some line from (px, pz) reaches a region cell within `reach` without a
    blocker in front. Exact in plan: between two critical directions (a corner of the cell or of a
    blocker) the rectangles a ray meets, and their order, do not change, so the middle direction
    of every such interval of each cell's arc is cast."""
    near = []
    for b in blockers:
        if point_rect(b, px, pz) <= reach + EPS:
            corners = ((b[0], b[2]), (b[0], b[3]), (b[1], b[2]), (b[1], b[3]))
            near.append((b, [math.atan2(z - pz, x - px) for x, z in corners], hull_arc(px, pz, corners, 0.0)))
    for c in sorted(cells, key=lambda c: point_rect(c, px, pz)):
        if point_rect(c, px, pz) > reach + EPS:
            break
        corners = ((c[0], c[2]), (c[0], c[3]), (c[1], c[2]), (c[1], c[3]))
        far = max(math.hypot(x - px, z - pz) for x, z in corners)
        for lo, hi in hull_arc(px, pz, corners, 0.0):
            front = [(b, angles) for b, angles, arcs in near if point_rect(b, px, pz) < far + EPS
                     and any(a0 < hi and a1 > lo for a0, a1 in arcs)]
            cuts = sorted({lo, hi} | {a for _b, angles in front for a in angles if lo < a < hi})
            for a, z in zip(cuts, cuts[1:]):
                mid = (a + z) / 2
                ux, uz = math.cos(mid), math.sin(mid)
                into = ray_entry(px, pz, ux, uz, c)
                if into is None or into > reach + EPS:
                    continue
                if all(ray_entry(px, pz, ux, uz, b) is None or ray_entry(px, pz, ux, uz, b) > into + EPS
                       for b, _angles in front):
                    return True
    return False


def sniper_spots(level, layout, ctx, solids):
    """R8: every standable top that no rusher of a region reaches (CampBrain.Melee is false for a
    player standing there: off the region by more than chaseMargin, over meleeAbove, under
    meleeBelow, or out of the height band) and that lies within the Longbow's range of the region
    (its camps' floors and the road its groups chase over). A locking camp's own floor, fence and
    cover are left out (INTERFACES "Open for later": shooting out of the boss room). One spot per
    solid: its name, its region, the open camp of the region whose floor is nearest, how many
    points, the box of those points, the point of them nearest the region that sees it (where a
    straight sniper course stands) and the nearest point of all (`near`, seen or not: where a cone
    no wall stops is cast from, the fix round's d-m4). tools/sim_range.py rates a course from every spot this returns."""
    rules = ctx["camps"]
    reach = ctx["sniperReach"][0]
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
        boxes = [cell_box(c) for c in rects]
        bounds = (min([s.x0 for s in solids] + [b[0] for b in boxes]), max([s.x1 for s in solids] + [b[1] for b in boxes]),
                  min([s.z0 for s in solids] + [b[2] for b in boxes]), max([s.z1 for s in solids] + [b[3] for b in boxes]))
        plans = {}
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
            # L2-37: a spot only where the bow's line reaches a cell: the nearest point that sees one.
            found.sort()
            blockers = tuple(sight_blockers(solids, solid.top, region["y"])) if SIGHT_WALLS else ()
            if blockers and blockers not in plans:
                plans[blockers] = PlanRooms(blockers, boxes, bounds)
            plan = plans.get(blockers)
            seen = next((f for f in found if plan is None or (plan.lit_at(f[1], f[2])
                                                                and sees_region(f[1], f[2], boxes, blockers, reach))), None)
            if seen is None:
                continue
            gap, x, z = seen
            camp = min(open_camps, key=lambda c: rect_distance(x, z, *camp_rect(c)))
            spots.append({"id": solid.name, "region": region["id"], "camp": camp["id"], "top": solid.top,
                          "points": len(found), "at": (x, solid.top, z), "gap": gap,
                          "near": (found[0][1], solid.top, found[0][2]), "nearGap": found[0][0],
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
        bare = exposed(solids)
        for solid in solids:
            if (solid.kind not in ("block", "fence", "obstacle", "secret", "floor") or solid.name in tall
                    or solid.name not in bare):
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
           f"the sniper reach {ctx['sniperReach'][0]:g} of a region, {ctx['sniperReach'][1]}'s, the longest of the "
           f"ownable ranged families (L3-25); each rated by sim_range's straight course) are the pinned "
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


def reachable_solids(layout, solids, move, ability, skip, tall, grace=False):
    """The standable solids a player reaches from the start without entering the camp whose
    pieces start with `skip`: from one to another that lies within stray_reach (falling the drop
    between them) and at most climb_max over it. Walls do not stop a jump here (conservative).
    With `grace` (L2-60 g) the walk-off grace first: movement.coyoteSeconds of walking off the edge,
    falling that long (wall_reach_of's reach, with the drop between the two tops)."""
    coyote = (move.get("coyoteSeconds") or 0) if grace else 0
    sag = sr.GRAVITY * coyote * coyote / 2
    bare = exposed(solids)
    standable = [s for s in solids if s.kind in ("block", "floor", "secret", "fence", "obstacle")
                 and not s.name.startswith(skip) and s.name not in tall and s.name in bare]
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
            if here.gap_to(other) <= stray_reach(move, here.top - other.top + sag) + move["walkSpeed"] * coyote + EPS:
                seen.add(other.name)
                queue.append(other)
    return [s for s in standable if s.name in seen]


def walled_bodies(level, layout, ctx, cid, factor=None):
    """Every resident post of a camp at every difficulty: ({(x, z): (radius, label, kind)}, the plated
    residents, the tallest body of the camp, its boss included). With `factor` (body_reach) the
    tallest is the drawn one (drawn_body: a model kind's posed reach up, L4 W2)."""
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
                    bodies[key] = (radius, f"{difficulty} {defn['id']} {kind}", kind)
                tallest = max(tallest, body.get("height") or 0,
                              drawn_body(ctx, kind, factor)[1] if factor is not None else 0)
                if (body.get("plate") or 0) > 0:
                    plated.append(f"{difficulty} {defn['id']} {kind}")
    for stage in level["stages"]:
        if stage["kind"] == "camp" and stage.get("zone") == cid:
            for wave in stage.get("waves") or []:
                if wave.get("boss") and wave["boss"]["kind"] in kinds:
                    tallest = max(tallest, kinds[wave["boss"]["kind"]].get("height") or 0,
                                  drawn_body(ctx, wave["boss"]["kind"], factor)[1] if factor is not None else 0)
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


def sight_points(layout, solids, ctx, camp, gates, walls, tall, clip, fresh=None):
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
    margin first.

    `fresh` (a set of names; check_ice's run on the frozen layout): eyes stand only on the reached
    tops it names (the ones the frozen sheets add). A sheet is no wall and no keep-out, so every
    other eye's cameras and lines are the dry run's, already judged; a point a sheet covers can only
    drop out."""
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
    if fresh is not None:
        reach = [s for s in reach if s.name in fresh]
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
    for zone in zones if SIGHT_ZONES and booms else []:  # with no boom, reached() proves none
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


def check_walled(name, level, layout, ctx, expect, solids, facts=True, dry=None):
    """L1c-1, L1c-3 and L1c-6: a walled camp hides everything inside it from every place a player
    reaches outside it, at the top of any jump, with the camera at its highest and farthest.
    `facts` False (check_ice's run on the frozen layout) adds no gate-16 rows. `dry` (that run's
    (layout, solids) as built): the sight lines judge only the eye points on the tops the frozen
    layout reaches and the dry one does not (sight_points' `fresh`; exact, given the dry run's own
    lines), and pass when there are none."""
    walled = (EXPECTED.get(level["layout"]) or {}).get("walled") or []
    if not walled:
        return
    move, levels = ctx["move"], ctx["levels"]
    thickness = levels["fenceThickness"]
    rows = ctx["gate16"].setdefault(level["layout"], {}).setdefault("walled", []) if facts else []
    tall = unclimbable(solids, move, ctx["abilityHeight"])
    top_cam, parts = camera_top(ctx)
    reach = wall_reach_of(move)
    for cid in walled:
        camp = next((c for c in layout["camps"] if c["id"] == cid), None)
        tag = f"{name} camp {cid} (walled):"
        if camp is None or camp.get("locks") is not True:
            expect(False, f"{tag} it is a camp of the layout that locks")
            continue
        fence = camp.get("fence") or {}
        wall_top = camp["y"] + (fence.get("height") or 0)
        floor = camp_rect(camp)
        fenced = grown(floor, fence_thickness(camp, thickness))
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
        # Plates (L1c-6). L4 W2: the drawn bodies are the models' where a kind has one.
        bodies, plated, tallest = walled_bodies(level, layout, ctx, cid, body_reach(ctx))
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
        # Only walls near enough to stand between an eye by a gate and a body inside (L2 W2: the
        # cave's ridge, hundreds of studs off, cuts no such line and only slowed the gate).
        walls = [(s.x0, s.x1, s.z0, s.z1) for s in solids
                 if s.kind == "block" and s.look == "wall" and s.top >= wall_top - EPS
                 and rect_gap((s.x0, s.x1, s.z0, s.z1), camp_rect(camp)) <= WALLED_NEAR]
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
        lockers = [grown(camp_rect(c), fence_thickness(c, thickness)) for c in layout["camps"] if c.get("locks") is True]
        clip = {"fenced": fenced, "grown": grown(fenced, clear), "keeps": [grown(r, keep) for r in lockers],
                "standoff": sphere - shake}
        fresh = None
        if dry is not None:
            dry_tall = unclimbable(dry[1], move, ctx["abilityHeight"])
            before = {s.name for s in reachable_solids(dry[0], dry[1], move, ctx["abilityHeight"], f"Camp_{cid}_", dry_tall)}
            fresh = {s.name for s in reachable_solids(layout, solids, move, ctx["abilityHeight"], f"Camp_{cid}_", tall)
                     } - before
        inside, cams, lazy, reached = sight_points(layout, solids, ctx, camp, gates, walls, tall, clip, fresh)
        drawn = {at: (drawn_body(ctx, kind, factor)[0], label) for at, (_radius, label, kind) in bodies.items()}

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
                    f"{clear:g} (a camera {keep:g} off the fence at worst), drawn body {factor:.3f} x radius or a "
                    f"model's posed reach ("
                    + ", ".join(sorted({f"{k} {drawn_body(ctx, k, factor)[0]:.2f}" for _r, _l, k in bodies.values()}))
                    + f"), tallest {tallest:g}")
        for what in ("eye", "camera"):
            if tight[what] is not None:
                t = tight[what]
                rows.append(f"{cid} sight margin ({what}s) {t[0]:+.2f} studs: ({t[1]:g}, {t[2]:g}) to {t[3]} through "
                            f"the {t[4]} gate")
        if glimpse is not None:
            rows.append(f"{cid} doorway (exempt eyes: within {DOORWAY:g} of the fence in a gate's lane): {glimpse[0]:+.2f} "
                        f"at ({glimpse[1]:g}, {glimpse[2]:g}) to {glimpse[3]}")
        least = min((t for t in tight.values() if t is not None), default=None, key=lambda t: t[0])
        added = "" if fresh is None else (f" (the points on the {len(fresh)} top(s) the frozen sheets add: "
                                           f"{', '.join(sorted(fresh)) or 'none'})")
        expect(not seen and (bool(inside) or fresh is not None), f"{tag}{added} from no eye point on an outside top a "
               f"player reaches and no camera "
               f"point its boom reaches (kept {keep:g} off the fence by the clip, levels.cameraClear {clear:g} "
               f"less the shake), is any part of a drawn resident (radius x {factor:.3f}, or a model's posed reach) seen "
               f"through a gate, every "
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
        expect(is_number(want) and want >= 0 and not short and (least is not None or fresh is not None),
               f"{tag}{added} every eye's and every camera's sight margin is at least its sightMargin ({want}): "
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


# ---------------------------------------------------------------------------------------------
# L2 Wave 2: the cave behind fire, the shortcut, and the bends (L2-36, L2-37, L2-47)
# ---------------------------------------------------------------------------------------------


def open_layout(layout, opened=None):
    """L2-36: the layout a leader who has found these shortcuts plays: LevelGeometry.Pieces leaves
    out every block whose `opens` is in the set (default: every shortcut of the layout)."""
    ids = {sc["id"] for sc in layout.get("shortcuts") or []} if opened is None else set(opened)
    return {**layout, "blocks": [b for b in layout["blocks"] if b.get("opens") is None or b["opens"] not in ids]}


class Enclosure:
    """(f): the air of a box of the world cut on every block face (a grid of the blocks' own
    coordinates, so a gap of any width is a row of its own), filled from the box's sides through
    every face no block covers. A point is "solid" inside a block, "out" in air the fill reached,
    "in" in air nothing outside reaches: sealed, whatever a player does (jumps, dashes, lifting
    arcs, sight: no way in exists at all)."""

    def __init__(self, layout, box):
        import bisect

        self.bisect = bisect
        x0, x1, y0, y1, z0, z1 = box
        blocks = []
        for b in layout["blocks"]:
            if b.get("collide") is False:
                continue
            bx0, bx1 = b["x"] - b["sx"] / 2, b["x"] + b["sx"] / 2
            by0, by1 = b["y"] - b["sy"] / 2, b["y"] + b["sy"] / 2
            bz0, bz1 = b["z"] - b["sz"] / 2, b["z"] + b["sz"] / 2
            if bx1 <= x0 or bx0 >= x1 or by1 <= y0 or by0 >= y1 or bz1 <= z0 or bz0 >= z1:
                continue
            blocks.append((max(bx0, x0), min(bx1, x1), max(by0, y0), min(by1, y1), max(bz0, z0), min(bz1, z1),
                           b.get("name") or b["look"], b["look"]))
        self.xs = sorted({x0, x1} | {v for b in blocks for v in b[0:2]})
        self.ys = sorted({y0, y1} | {v for b in blocks for v in b[2:4]})
        self.zs = sorted({z0, z1} | {v for b in blocks for v in b[4:6]})
        nx, ny, nz = len(self.xs) - 1, len(self.ys) - 1, len(self.zs) - 1
        self.n = (nx, ny, nz)
        owner = [None] * (nx * ny * nz)  # the first block over each cell (None = air)
        for b in blocks:
            i0, i1 = bisect.bisect_left(self.xs, b[0]), bisect.bisect_left(self.xs, b[1])
            j0, j1 = bisect.bisect_left(self.ys, b[2]), bisect.bisect_left(self.ys, b[3])
            k0, k1 = bisect.bisect_left(self.zs, b[4]), bisect.bisect_left(self.zs, b[5])
            for i in range(i0, i1):
                for j in range(j0, j1):
                    base = (i * ny + j) * nz
                    for k in range(k0, k1):
                        if owner[base + k] is None:
                            owner[base + k] = b
        self.owner = owner
        reached = bytearray(nx * ny * nz)
        stack = []
        for i in range(nx):
            for j in range(ny):
                for k in range(nz):
                    if (i in (0, nx - 1) or j in (0, ny - 1) or k in (0, nz - 1)) and owner[(i * ny + j) * nz + k] is None:
                        reached[(i * ny + j) * nz + k] = 1
                        stack.append((i, j, k))
        while stack:
            i, j, k = stack.pop()
            for di, dj, dk in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                a, b2, c = i + di, j + dj, k + dk
                if 0 <= a < nx and 0 <= b2 < ny and 0 <= c < nz:
                    cell = (a * ny + b2) * nz + c
                    if not reached[cell] and owner[cell] is None:
                        reached[cell] = 1
                        stack.append((a, b2, c))
        self.reached = reached

    def cell(self, x, y, z):
        nx, ny, nz = self.n
        i = self.bisect.bisect_right(self.xs, x) - 1
        j = self.bisect.bisect_right(self.ys, y) - 1
        k = self.bisect.bisect_right(self.zs, z) - 1
        if not (0 <= i < nx and 0 <= j < ny and 0 <= k < nz):
            return None
        return (i * ny + j) * nz + k

    def at(self, x, y, z):
        """"solid", "out" or "in" (outside the box: "out")."""
        cell = self.cell(x, y, z)
        if cell is None:
            return "out"
        if self.owner[cell] is not None:
            return "solid"
        return "out" if self.reached[cell] else "in"

    def boundary(self):
        """The blocks that face sealed air: (name, look) of every block owning a cell beside an
        "in" cell."""
        nx, ny, nz = self.n
        found = set()
        for i in range(nx):
            for j in range(ny):
                for k in range(nz):
                    cell = (i * ny + j) * nz + k
                    if self.owner[cell] is not None or self.reached[cell]:
                        continue
                    for di, dj, dk in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                        a, b, c = i + di, j + dj, k + dk
                        if 0 <= a < nx and 0 <= b < ny and 0 <= c < nz:
                            other = self.owner[(a * ny + b) * nz + c]
                            if other is not None:
                                found.add((other[6], other[7]))
        return found


def walked_samples(points, step):
    """(x, z, the leg's index) every `step` studs along a route-like polyline of {x, y, z, via}
    points, walked legs only (a climb or a gap is its own leg)."""
    found = []
    for index in range(1, len(points)):
        a, b = points[index - 1], points[index]
        if b.get("via") is not None:
            continue
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        cuts = max(int(math.ceil(run / step)), 1)
        found += [(a["x"] + (b["x"] - a["x"]) * k / cuts, a["z"] + (b["z"] - a["z"]) * k / cuts, index)
                  for k in range(cuts + 1)]
    return found


def on_polyline(points, x, z):
    """Whether (x, z) lies on a leg of a polyline of {x, z} points, and how far along it."""
    walked = 0.0
    for a, b in zip(points, points[1:]):
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        if segment_gap(x, z, (a["x"], a["z"]), (b["x"], b["z"])) < 0.01:
            return True, walked + math.hypot(x - a["x"], z - a["z"])
        walked += run
    return False, None


def floors_under(solids, samples, heights):
    """The path or ground blocks a polyline's samples stand on (at the heights given)."""
    found = {}
    for (x, z, _leg), y in zip(samples, heights):
        top, under = ground(solids, x, z, y + WALK_RISE)
        if under is not None and under.kind == "block" and abs(top - y) <= WALK_RISE + EPS:
            found[under.name] = under
    return found


def clearance(solids, x, z, floor, along):
    """At (x, z) on a floor at `floor`, walking along the unit vector `along`: the free width
    across (to the nearest solid that stands over WALK_RISE above the floor within a body's
    height, each side) and the headroom (to the lowest solid over the floor there)."""
    ax, az = along
    nx, nz = -az, ax
    width = 0.0
    walls = [(o.x0, o.x1, o.z0, o.z1) for o in solids
             if o.top > floor + WALK_RISE + EPS and o.bottom < floor + BODY_HEIGHT - EPS]
    for sign in (1, -1):
        hits = [t for w in walls if (t := ray_entry(x, z, sign * nx, sign * nz, w)) is not None]
        width += min(hits + [40.0])
    over = [o.bottom - floor for o in solids if o.holds(x, z) and o.bottom > floor - EPS and o.top > floor + EPS
            and o.bottom >= floor + WALK_RISE - EPS]
    return width, min(over, default=math.inf)


def check_cave(name, level, layout, ctx, expect, solids, closed_only=False):
    """L2-36 and L2-37 (f), (a) for a fire secret, and R8 on the open variant. Run on a layout with
    `shortcuts` only.
      closed (the brambles stand): every floor the shortcut route crosses off the main route, and
        every point of an element-keyed chest's trigger, is sealed air or solid (Enclosure: the
        brambles, walls and roof leave no way in at any width); every wall-look block that faces
        the sealed air is unclimbable (nobody stands on the ridge); the chest's trigger is met only
        from its alcove floor and its own top;
      open (every block that `opens` a shortcut left out, as LevelGeometry.Pieces builds it for a
        leader who found it): layout.shortcutRoute leaves the main route and rejoins it, walked
        with one jump (the route's climbs and gaps), at least ROAD_MIN_WIDTH between walls and a
        body's headroom (a climb's own rise more), every point farther than every open-camp group's
        sight (the sneak rule); the chest's alcove opens onto a floor the route walks; and the
        unreachable sniper spots are the pinned open list.
    `closed_only` (check_ice's run on the frozen layout, the W3 fix round's s2): the closed half
    alone (the sealed air, the ridge's walls and every carry onto them, the chest's trigger); the
    frozen open variant's sniper spots are check_ice's own list."""
    shortcuts = layout.get("shortcuts") or []
    if not shortcuts:
        return
    move, levels = ctx["move"], ctx["levels"]
    spec = EXPECTED.get(level["layout"]) or {}
    tag = f"{name}:"
    jump = jump_facts(move)
    thickness, depth = levels["fenceThickness"], levels["floorThickness"]
    path = layout.get("shortcutRoute") or []
    # The chests behind a shortcut's brambles: keyed on the element those brambles react to.
    burns = {b.get("react") for b in layout["blocks"] if b.get("react") is not None and b.get("opens") is not None}
    secrets = [x for x in layout["secrets"] if x["needs"] in REACT_WORDS and x["needs"] in burns]
    rules = secret_rules(levels)
    # The box the enclosure is judged in: the shortcut route, its trigger boxes, the reactive blocks
    # and the element-keyed chests, grown on the flat.
    xs = [p["x"] for p in path] + [sc["x"] for sc in shortcuts] + [x["x"] for x in secrets]
    zs = [p["z"] for p in path] + [sc["z"] for sc in shortcuts] + [x["z"] for x in secrets]
    for b in layout["blocks"]:
        if b.get("react") is not None:
            xs.append(b["x"])
            zs.append(b["z"])
    box_xz = (min(xs) - CAVE_MARGIN, max(xs) + CAVE_MARGIN, min(zs) - CAVE_MARGIN, max(zs) + CAVE_MARGIN)
    inside = [b for b in layout["blocks"] if b["x"] + b["sx"] / 2 > box_xz[0] and b["x"] - b["sx"] / 2 < box_xz[1]
              and b["z"] + b["sz"] / 2 > box_xz[2] and b["z"] - b["sz"] / 2 < box_xz[3]]
    box = (box_xz[0], box_xz[1], min(b["y"] - b["sy"] / 2 for b in inside) - 5, max(b["y"] + b["sy"] / 2 for b in inside) + 5,
           box_xz[2], box_xz[3])
    shut = Enclosure(layout, box)
    tall = unclimbable(solids, move, ctx["abilityHeight"])
    # The floors the shortcut route crosses that the main route does not.
    route_samples = walked_samples(layout["route"], SAMPLE * 4)
    route_heights = [route_height_near(layout, x, z)[0] for x, z, _leg in route_samples]
    main_floors = floors_under(solids, route_samples, route_heights)
    opened = open_layout(layout)
    open_solids = solids_of(opened, thickness, depth)
    cave_samples = walked_samples(path, SAMPLE * 4)
    cave_heights = []
    for x, z, leg in cave_samples:
        a, b = path[leg - 1], path[leg]
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        f = math.hypot(x - a["x"], z - a["z"]) / run if run > EPS else 0.0
        cave_heights.append(a["y"] + (b["y"] - a["y"]) * f)
    cave_floors = {n: f for n, f in floors_under(open_solids, cave_samples, cave_heights).items() if n not in main_floors}
    bases = {}
    for secret in secrets:
        base = secret_base(solids, secret)
        if base is not None:
            bases[secret["id"]] = base
            cave_floors.setdefault(base.name, base)
    # (f) closed: sealed.
    leaks = []
    proved = 0
    for fname, floor in sorted(cave_floors.items()):
        for x, z in standable_points(solids, floor, CAVE_STEP):
            proved += 1
            where = shut.at(x, floor.top + 1.0, z)
            if where == "out":
                leaks.append(f"{fname} ({x:g}, {floor.top:g}, {z:g})")
                break
    trigger_open = []
    for secret in secrets:
        if rules is None:
            break
        reach, below, above = rules
        foot = secret["y"] - secret["sy"] / 2
        heights = [foot - below + k for k in range(int(below + above) + 1)] + [foot + above]
        for x, z in trigger_region(secret, reach, 1.0):
            if any(shut.at(x, y, z) == "out" for y in heights):
                trigger_open.append(f"{secret['id']} at ({x:g}, {z:g})")
                break
    expect(bool(cave_floors) and not leaks and not trigger_open,
           f"{tag} behind fire: with every bramble standing, the {len(cave_floors)} floors the shortcut route crosses off "
           f"the main route ({', '.join(sorted(cave_floors)) or 'none'}) and the trigger of every element-keyed chest lie "
           f"in sealed air: no point is reached from outside through any gap, of any width, at any height ({proved} "
           f"floor points; L2-37 f)" + (f": a way in at {', '.join(leaks[:3])}" if leaks else "")
           + (f": the trigger is open at {', '.join(trigger_open[:3])}" if trigger_open else ""))
    facing = shut.boundary()
    loose = sorted(n for n, look in facing if look == "wall" and n not in tall)
    walls = sorted(n for n, look in facing if look == "wall")
    expect(bool(walls) and not loose,
           f"{tag} behind fire: every wall that faces the sealed air is unclimbable (top at least "
           f"{climb_max(move, ctx['abilityHeight']):g} over every surface within {wall_reach_of(move):.1f}), so nobody "
           f"stands on the ridge or its roof (L2-37 f): " + (f"climbable {', '.join(loose)}" if loose else f"{len(walls)} walls"))
    # The fix round's d-M1: nor does any lifting ability's arc put a player WITH the double jump on
    # one of those tops (cast at the top of his jumps from every surface near them, off every edge
    # with the jumps' carry and a dash, over a void his floor his feet less both jumps).
    lifts = ctx.get("lifts") or []
    ridge = [x for x in solids if x.name in set(walls)]
    keys = [(x.x0, x.x1, x.z0, x.z1, x.top, x.name) for x in ridge]
    routes = lift_routes(solids, keys, {x.name for x in ridge}, tall, move, lifts, air=True) if keys and lifts else []
    # And an air dash ability (Impale Dash) cast at any height his jumps carry him to: his feet held
    # there over the ability's range on top of the jumps' and the dash's carry (air_carry), straight
    # over whatever lies between (the worst case).
    bare = exposed(solids)
    standable = ("block", "floor", "secret", "fence", "obstacle")
    for family, a in ctx.get("dashes") or []:
        for o in solids:
            if o.kind not in standable or o.name in tall or o.name not in bare or o.name in set(walls):
                continue
            for kr in keys:
                carry = air_carry(move, kr[4] - STEP_UP - o.top)
                gap = rect_gap((o.x0, o.x1, o.z0, o.z1), kr[:4])
                if carry is not None and gap <= carry + float(a["range"]) + BODY_RADIUS + EPS:
                    routes.append(f"{family}'s {a.get('name')} from {o.name} (top {o.top:g}) onto {kr[5]}'s top {kr[4]:g}, "
                                  f"{gap:.1f} away (carry {carry:.1f} + {float(a['range']):g})")
    count = f"{len(routes)}{'+' if len(routes) >= LIFT_ROUTES_MAX else ''}"
    told = ", ".join([f"{family} ({a.get('name')}, height {a['height']:g}, castRange {a['castRange']:g})"
                      for family, a in lifts] + [f"{family} ({a.get('name')}, range {float(a['range']):g}, held in the air)"
                                                 for family, a in ctx.get("dashes") or []]) or "no family that carries"
    expect(bool(keys) and not routes,
           f"{tag} behind fire: no ability that carries a player with the double jump puts him on a wall that faces the "
           f"sealed air ({told}; take-offs at the top of jump and double jump, {lift_carry(move, True):.1f} studs of carry "
           f"plus a dash of {move['dashDistance']:g}; LIFT_MODEL \"{LIFT_MODEL}\"; the fix round's d-M1): "
           + (f"{count} ways onto one: {'; '.join(routes[:2])}" if routes else f"{len(keys)} tops, none"))
    # (a) for a fire secret: met from its alcove floor and its own top, from nowhere outside.
    for secret in secrets:
        chest = next((x for x in solids if x.name == f"Secret_{secret['id']}"), None)
        base = bases.get(secret["id"])
        held = trigger_tops(secret, solids, chest, rules, tall) if chest is not None else []
        mine = {base.name, chest.name} if base is not None and chest is not None else set()
        expect(base is not None and base.name in held and set(held) <= mine,
               f"{tag} the {secret['id']}'s trigger (needs {secret['needs']}) is met from its alcove floor and its own top "
               f"only (L2-37 a): " + (", ".join(sorted(set(held))) or "none")
               + (f" (its floor: {base.name})" if base is not None else " (it stands on no floor)"))
    if closed_only:
        return
    # (f) open: the shortcut route, walked.
    problems, facts = walk_route({**opened, "route": path, "start": path[0] if path else layout["start"], "camps": []},
                                 open_solids, move)
    starts, at_from = on_polyline(layout["route"], path[0]["x"], path[0]["z"]) if path else (False, None)
    ends, at_to = on_polyline(layout["route"], path[-1]["x"], path[-1]["z"]) if path else (False, None)
    if not (starts and ends and at_to > at_from):
        problems.append("it does not leave the main route and rejoin it further on")
    narrow, low = [], []
    for (x, z, leg), y in zip(cave_samples, cave_heights):
        a, b = path[leg - 1], path[leg]
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        if run <= EPS or (layout_hold := ground(open_solids, x, z, y + WALK_RISE))[0] is None:
            continue
        if layout_hold[1].name in main_floors:
            continue
        width, head = clearance(open_solids, x, z, layout_hold[0], ((b["x"] - a["x"]) / run, (b["z"] - a["z"]) / run))
        if width < ROAD_MIN_WIDTH - 0.25 - EPS:
            narrow.append(f"({x:g}, {z:g}) {width:g}")
        if head < BODY_HEIGHT - EPS:
            low.append(f"({x:g}, {z:g}) {head:g}")
    for leg in facts["legs"]:
        if leg["via"] == "climb":
            a = leg["from"]
            _w, head = clearance(open_solids, a["x"], a["z"], a["y"], (1.0, 0.0))
            if head < leg["rise"] + BODY_HEIGHT - EPS:
                low.append(f"the climb at ({a['x']:g}, {a['z']:g}): {head:g} over its foot, under {leg['rise']:g} + a body")
    climbs = [l for l in facts["legs"] if l["via"] == "climb"]
    length = facts["length"]
    skipped = (at_to - at_from) if starts and ends else None
    camps_skipped = [leg["camp"] for leg in walk_route(layout, solids, move)[1]["legs"]
                     if leg.get("camp") and starts and ends
                     and at_from < on_polyline(layout["route"], leg["from"]["x"], leg["from"]["z"])[1] < at_to]
    ctx["gate16"].setdefault(level["layout"], {}).setdefault("cave", []).append(
        f"shortcut route {length:.0f} studs (replaces {skipped:.0f} of the main route, camp(s) "
        f"{', '.join(camps_skipped) or 'none'} skipped)" if skipped is not None else f"shortcut route {length:.0f} studs")
    expect(not problems and not narrow and not low,
           f"{tag} the shortcut route, with the brambles burnt: it leaves the main route and rejoins it, walked with one "
           f"jump ({len(climbs)} climb(s) of at most {jump['climb']}, gaps of at most {jump['gap']}), at least "
           f"{ROAD_MIN_WIDTH:g} between walls and a body's headroom ({BODY_HEIGHT:g}, a climb's rise more): {length:.0f} "
           f"studs" + (f", in place of {skipped:.0f} of the main route (skipping camp {', '.join(camps_skipped)})"
                       if skipped is not None and camps_skipped else "") + " (L2-37 f)"
           + (": " + "; ".join(problems[:3]) if problems else "")
           + (f": narrow at {', '.join(narrow[:3])}" if narrow else "") + (f": low at {', '.join(low[:3])}" if low else ""))
    # The chest's alcove opens onto a floor the route walks (same top, sides touching).
    walked = [f for n, f in floors_under(open_solids, cave_samples, cave_heights).items()]
    for secret in secrets:
        base = bases.get(secret["id"])
        joined = base is not None and any(base is f or (abs(f.top - base.top) < 0.01 and base.gap_to(f) <= EPS
                                                       and min(base.x1, f.x1) - max(base.x0, f.x0) + min(base.z1, f.z1)
                                                       - max(base.z0, f.z0) >= 2 * BODY_RADIUS) for f in walked)
        expect(joined, f"{tag} with the brambles burnt the {secret['id']}'s floor ({base.name if base else 'none'}) is a "
               f"floor the shortcut route walks or opens onto one at its height (L2-37 f)")
    # The sneak rule along the shortcut route.
    kinds, ranks, camp_rules = ctx["kinds"], ctx["ranks"], ctx["camps"]
    seen, tight = [], None
    points = [(p["x"], p["z"]) for p in path]
    for difficulty in level["difficulties"]:
        defs, _tents = all_defs(level, layout, ranks.get(difficulty, 0), ranks)
        for defn in defs:
            if defn["held"]:
                continue
            sight = sr.cb_posture(defn, camp_rules)["sight"]
            for member in resting_eyes(defn):
                ex, ez = member["at"][0], member["at"][2]
                d = min(segment_gap(ex, ez, a, b) for a, b in zip(points, points[1:])) if len(points) > 1 else math.inf
                if tight is None or d - sight < tight[0]:
                    tight = (d - sight, f"{difficulty} {defn['id']}", sight)
                if d - sight <= EPS:
                    seen.append(f"{difficulty} {defn['id']} at ({ex:g}, {ez:g}): {d:.1f} studs, sight {sight:g}")
    expect(bool(points) and not seen,
           f"{tag} every point of the shortcut route lies farther than its posture's sight from every resting place of "
           f"every open-camp group, tents included, every difficulty (the sneak rule, L2-37 f)"
           + (": " + "; ".join(seen[:3]) if seen else f": the tightest {tight[1]} {tight[0]:+.1f} (sight {tight[2]:g})"
              if tight else ""))
    # R8 on the open variant: the pinned open list.
    spots = sniper_spots(level, opened, ctx, open_solids)
    found = sorted(sp["id"] for sp in spots)
    pinned = spec.get("sniperSpotsOpen")
    ctx["gate16"].setdefault(level["layout"], {}).setdefault("cave", []).append(
        "sniper spots with the brambles burnt: " + ", ".join(
            f"{sp['id']} (camp {sp['camp']}, nearest seen ({sp['at'][0]:g}, {sp['at'][2]:g}) {sp['gap']:.1f} off)"
            for sp in spots if sp["id"] not in (spec.get("sniperSpots") or [])) + " beyond the closed list")
    expect(pinned is None or found == sorted(pinned),
           f"{name}: with the brambles burnt, the unreachable sniper spots (R8 with L2-37's sight) are the pinned open "
           f"list: {', '.join(found) or 'none'}"
           + (f" (pinned: {', '.join(sorted(pinned))})" if pinned is not None and found != sorted(pinned) else ""))


def ice_families(ctx):
    """The families whose element is ice (L2-49: the Frost Hammer), {family: its weapon}."""
    return {f: w for f, w in sorted((ctx.get("weapons") or {}).items()) if w.get("element") == "ice"}


def cells_touch(a, b):
    """Two cells (x0, x1, z0, z1) share a side of positive length (4-connected)."""
    over_x = min(a[1], b[1]) - max(a[0], b[0])
    over_z = min(a[3], b[3]) - max(a[2], b[2])
    return (abs(over_x) <= EPS and over_z > EPS) or (abs(over_z) <= EPS and over_x > EPS)


def island_reach(move, o, kr, lifts, dashes):
    """L2-60 (g)'s worst reach on the flat from a standable top `o` onto a key top `kr`: the jumps,
    a dash and the walk-off grace (falling the drop between them; only when the jumps rise high
    enough); an air dash held over its range after the jumps' carry (air_carry); a lift cast at the
    top of the jumps off an edge, after their carry and a dash, over its castRange (when its height
    on top of the jumps gets the feet that high), and then the fall at walk speed from where it
    lands (WallClip.CasterFloor: over a void, the take-off top) down to the key top less a step up
    (the W3 fix round's d-m3; 3.5 studs from a top at 0, 12.3 from a top at 34, L2's lookout ledge). (studs,
    the means)."""
    coyote = move.get("coyoteSeconds") or 0
    need = kr[4] - STEP_UP - o.top
    best = (0.0, "nothing")
    if need <= move["jumpHeight"] + move["doubleJumpHeight"] + EPS:
        jumps = stray_reach(move, o.top - kr[4] + sr.GRAVITY * coyote * coyote / 2) + move["walkSpeed"] * coyote
        best = max(best, (jumps, "the jumps, a dash and the walk-off grace"))
    for family, a in dashes:
        carry = air_carry(move, need)
        if carry is not None:
            best = max(best, (carry + float(a["range"]) + BODY_RADIUS, f"{family}'s {a.get('name')} held in the air"))
    for family, a in lifts:
        if need <= lift_rise(move, True) + float(a["height"]) + EPS:
            fall = move["walkSpeed"] * math.sqrt(2 * max(o.top - (kr[4] - STEP_UP), 0.0) / sr.GRAVITY)
            span = lift_carry(move, True) + move["dashDistance"] + float(a["castRange"]) + BODY_RADIUS + fall
            best = max(best, (span, f"{family}'s {a.get('name')} after the jumps and a dash, and its fall"))
    return best


def ice_crossing_cells(layout, solids, ice, reached, island):
    """(h)'s chain: the open cells (sim_range.ice_cells), the ones touching a bank a player reaches
    from the start without ice (a reached top at or over the water's top, not the island), and the
    ones touching the island; and the fewest cells of a 4-connected chain joining the two (None
    when none does). Judged by each cell's place in its block's grid (`cell`): the W3 second fix
    round's inset seam (Q6, at most ICE_INSET_MOST) is walked across."""
    cells = sr.ice_cells(layout, ice)
    banks = [s for s in solids if s.name in reached and (island is None or s.name != island.name)]
    starts = [i for i, c in enumerate(cells)
              if any(rect_gap(c["cell"], (s.x0, s.x1, s.z0, s.z1)) <= EPS and s.top >= c["water"] - EPS for s in banks)]
    goals = {i for i, c in enumerate(cells) if island is not None
             and rect_gap(c["cell"], (island.x0, island.x1, island.z0, island.z1)) <= EPS}
    seen = {i: 0 for i in starts}
    queue = list(starts)
    while queue:
        here = queue.pop(0)
        for j, c in enumerate(cells):
            if j not in seen and cells_touch(cells[here]["cell"], c["cell"]):
                seen[j] = seen[here] + 1
                queue.append(j)
    joined = [seen[g] for g in goals if g in seen]
    return cells, starts, goals, (min(joined) + 1 if joined else None)


def ice_side_met(waters, b, side, low, high):
    """The W3 third fix round's fd-s2, check_levels' own statement (not sim_range's): the part `low`
    to `high` of ice block `b`'s `side` face lies against another ice block over its whole length:
    that block's opposite side on the same plane, its top the same. The cells' sides there are
    built whole (no inset), so the sheets meet without a seam."""
    top = b["y"] + b["sy"] / 2
    for w in waters:
        if abs(w["y"] + w["sy"] / 2 - top) > EPS:
            continue
        if side in ("west", "east"):
            mine = b["x"] - b["sx"] / 2 if side == "west" else b["x"] + b["sx"] / 2
            theirs = w["x"] + w["sx"] / 2 if side == "west" else w["x"] - w["sx"] / 2
            lo, hi = w["z"] - w["sz"] / 2, w["z"] + w["sz"] / 2
        else:
            mine = b["z"] - b["sz"] / 2 if side == "north" else b["z"] + b["sz"] / 2
            theirs = w["z"] + w["sz"] / 2 if side == "north" else w["z"] - w["sz"] / 2
            lo, hi = w["x"] - w["sx"] / 2, w["x"] + w["sx"] / 2
        if abs(mine - theirs) <= EPS and lo <= low + EPS and hi >= high - EPS:
            return True
    return False


def ice_holes(layout, ice):
    """The W3 fix round's d-m1: the water of each ice block that neither a built piece
    (sim_range.ice_cells) nor a cover (a colliding block or secret whose top stands over the
    water's top, as LevelGeometry reads them) lies over: {block name: (area in studs², [(x0, x1,
    z0, z1), ...] the holes)}, empty when every block is filled. Exact: the block is cut along
    every edge of every piece and cover that crosses it, and each part's centre is tested. The W3
    second fix round's Q6: a rim levels.react.ice.inset wide inside the block's own faces is the
    inset the cells are built with, and need not be filled; the third fix round's fd-s2: only along
    a cell's side that no other ice block meets whole (ice_side_met), so where the creek meets the
    pond the sheets must meet. A piece inset any further, inset where another ice block meets it,
    or missing, leaves a hole."""
    cells = sr.ice_cells(layout, ice)
    allow = sr.ice_inset(ice) or 0
    blocks = [b for b in layout["blocks"] if b.get("react") == "ice"]
    covers = [(b["x"] - b["sx"] / 2, b["x"] + b["sx"] / 2, b["z"] - b["sz"] / 2, b["z"] + b["sz"] / 2, b["y"] + b["sy"] / 2)
              for b in layout["blocks"] if b.get("collide") is not False]
    covers += [(s["x"] - s["sx"] / 2, s["x"] + s["sx"] / 2, s["z"] - s["sz"] / 2, s["z"] + s["sz"] / 2, s["y"] + s["sy"] / 2)
               for s in layout.get("secrets") or []]
    found = {}
    for b in blocks:
        name = b.get("name") or b["look"]
        water = b["y"] + b["sy"] / 2
        box = (b["x"] - b["sx"] / 2, b["x"] + b["sx"] / 2, b["z"] - b["sz"] / 2, b["z"] + b["sz"] / 2)
        # The rim each built cell's side on the block's own face may leave (none where another ice
        # block meets that side whole).
        rims = []
        for c in cells:
            if c["block"] != name:
                continue
            x0, x1, z0, z1 = c["cell"]
            for side, on, strip in (("west", x0, (x0, x0 + allow, z0, z1)), ("east", x1, (x1 - allow, x1, z0, z1)),
                                    ("north", z0, (x0, x1, z0, z0 + allow)), ("south", z1, (x0, x1, z1 - allow, z1))):
                face = box[SIDES_AT[side]]
                low, high = (z0, z1) if side in ("west", "east") else (x0, x1)
                if abs(on - face) <= EPS and not ice_side_met(blocks, b, side, low, high):
                    rims.append(strip)
        held = ([c["box"] for c in cells if c["block"] == name] + [c[:4] for c in covers if c[4] > water]
                + rims)
        xs = sorted({box[0], box[1]} | {min(max(v, box[0]), box[1]) for r in held for v in r[:2]})
        zs = sorted({box[2], box[3]} | {min(max(v, box[2]), box[3]) for r in held for v in r[2:4]})
        holes, area = [], 0.0
        for i in range(len(xs) - 1):
            for k in range(len(zs) - 1):
                if xs[i + 1] - xs[i] <= EPS or zs[k + 1] - zs[k] <= EPS:
                    continue
                cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[k] + zs[k + 1]) / 2
                if not any(r[0] <= cx <= r[1] and r[2] <= cz <= r[3] for r in held):
                    holes.append((xs[i], xs[i + 1], zs[k], zs[k + 1]))
                    area += (xs[i + 1] - xs[i]) * (zs[k + 1] - zs[k])
        if holes:
            found[name] = (area, holes)
    return found


def box_faces(x0, x1, z0, z1, bottom, top):
    """A box's six faces: (axis, plane, facing, (low, high) on the first other axis, (low, high) on
    the second): x faces run over (y, z), z faces over (y, x), y faces over (x, z)."""
    return (("x", x0, -1, (bottom, top), (z0, z1)), ("x", x1, 1, (bottom, top), (z0, z1)),
            ("z", z0, -1, (bottom, top), (x0, x1)), ("z", z1, 1, (bottom, top), (x0, x1)),
            ("y", bottom, -1, (x0, x1), (z0, z1)), ("y", top, 1, (x0, x1), (z0, z1)))


def ice_coplanar(layout, ice, solids):
    """The W3 third fix round's fd-m1: every face of a built ice piece (sim_range.ice_cells, as frozen:
    ice.thickness deep under its top) that lies closer than levels.react.ice.inset (the seam Q6 set
    against the shimmer; a face on the very plane always counts) to a face of the same facing of
    a solid (`solids`: every colliding block, camp piece and secret), the two overlapping over an
    area: [(piece, its face, the solid, the gap)]. Frozen, the two z-fight: the island's south face
    on a pond row's line put two cells' faces on its own."""
    gap_most = max(sr.ice_inset(ice) or 0, 0)
    deep = ice.get("thickness") or 0
    found = []
    for c in sr.ice_cells(layout, ice):
        x0, x1, z0, z1 = c["box"]
        mine = box_faces(x0, x1, z0, z1, c["top"] - deep, c["top"])
        for s in solids:
            for axis, plane, facing, a, b in box_faces(s.x0, s.x1, s.z0, s.z1, s.bottom, s.top):
                for m_axis, m_plane, m_facing, ma, mb in mine:
                    if m_axis != axis or m_facing != facing:
                        continue
                    gap = abs(m_plane - plane)
                    if gap > EPS and gap >= gap_most - EPS:
                        continue
                    if min(ma[1], a[1]) - max(ma[0], a[0]) > EPS and min(mb[1], b[1]) - max(mb[0], b[0]) > EPS:
                        found.append((f"Ice_{c['block']} ({c['i']}, {c['k']})",
                                      f"{'-+'[facing > 0]}{axis} {m_plane:g}", s.name, gap))
    return found


def sheet_bounds(move, freached, fsolids, ice):
    """The W3 third fix round's fd-m2: (the least a frozen sheet is thick, the most, the fastest fall
    onto it, what that fall is). The least: the fastest fall onto a sheet moved in one physics step
    (PHYSICS_HZ): the slam's dive (movement.slamFallSpeed) or a free fall from the jumps' apex over
    the highest top a player reaches on the frozen layout down to the lowest sheet, whichever is
    faster. The most: the R15 root's height (ROOT_TALL)."""
    sheets = [s for s in fsolids if s.look == "ice" and s.kind == "block"]
    lowest = min((s.top for s in sheets), default=None)
    high = max((s.top for s in fsolids if s.name in freached), default=None)
    slam = float(move.get("slamFallSpeed") or 0)
    fall, what = slam, f"the slam's dive {slam:g}"
    if lowest is not None and high is not None:
        drop = high + move["jumpHeight"] + move["doubleJumpHeight"] - lowest
        free = math.sqrt(2 * sr.GRAVITY * max(drop, 0.0))
        if free > fall:
            fall, what = free, f"a fall of {drop:.1f} from the jumps' apex over the highest top reached ({free:.1f})"
    return fall / PHYSICS_HZ, ROOT_TALL, fall, what


def check_ice(name, level, layout, ctx, expect, solids):
    """L2-60, for every secret whose key is "ice" (the island shrine), and the W2 lessons on the
    frozen layout (sim_range.frozen_layout: every ice block standable at its top + lift).
      (g) behind ice, the water as built: the island and its chest are not reached from the start
        (jump, double jump, dash, the walk-off grace); no lift of any family (lift_routes, a Double
        Jump owner) and no air dash (air_carry + its range) puts a player on them; the island's flat
        gap to every other standable top is the largest of those reaches (island_reach) and
        ICE_MARGIN more; (a) its trigger is met from the island and the chest's top only, and (d) the
        ground within its reach lies over the island;
      (h) frozen: the island is reached from the start and the chest opens from it; every ice
        family's variants extend the ice (cell at most (range + ahead - a body's radius) / ICE_ROWS,
        reachDown at least the highest bank's root over the water's top); the open cells of the ice
        blocks form one 4-connected chain from a cell beside a reached bank to one beside the island;
        the built pieces and the covers fill every ice block (ice_holes: no water is left that no
        swing can close, so the frozen layout's whole block stands for them; the W3 fix round's d-m1)
        but the rim levels.react.ice.inset wide inside its own faces (the second fix round's Q6);
      and with the ice frozen: every unclimbable wall stays so, the secrets' (a) to (d) hold
        (check_secret_reach), R8's lists are the pinned frozen lists (both brambles' variants), the
        shot-origin chord holds (the sheets are floor, not walls), killY is still a short fall and
        every other block a body lands on is levels.floorThickness deep; every sheet is thicker than
        the fastest fall onto it moves in a physics step and thinner than an R15 root (sheet_bounds:
        the W3 third fix round's fd-m2, the lead's ruling in place of d-m6's floorThickness); no face
        of a piece lies on a same-facing face of a solid (ice_coplanar: fd-m1); and the bend rule
        (the sheets walked ground), the cave's closed half and the walled camps hold (s2)."""
    secrets = [x for x in layout["secrets"] if x["needs"] == "ice"]
    if not secrets:
        return
    spec = EXPECTED.get(level["layout"]) or {}
    levels, move = ctx["levels"], ctx["move"]
    ice = ice_config(levels)
    tag = f"{name}:"
    tall = unclimbable(solids, move, ctx["abilityHeight"])
    rules = secret_rules(levels)
    lifts, dashes = ctx.get("lifts") or [], ctx.get("dashes") or []
    reached = {s.name for s in reachable_solids(layout, solids, move, ctx["abilityHeight"], (), tall, grace=True)}
    frozen = sr.frozen_layout(layout, ice)
    thickness, depth = levels["fenceThickness"], levels["floorThickness"]
    fsolids = solids_of(frozen, thickness, depth)
    ftall = unclimbable(fsolids, move, ctx["abilityHeight"])
    freached = {s.name for s in reachable_solids(frozen, fsolids, move, ctx["abilityHeight"], (), ftall, grace=True)}
    facts = ctx["gate16"].setdefault(level["layout"], {}).setdefault("ice", [])
    bare = exposed(solids)
    standable = ("block", "floor", "secret", "fence", "obstacle")
    for secret in secrets:
        sid = secret["id"]
        chest = next((s for s in solids if s.name == f"Secret_{sid}"), None)
        base = secret_base(solids, secret)
        if chest is None or base is None or rules is None:
            expect(False, f"{tag} the {sid} (needs ice) stands on an island block and Combat.json levels has "
                   f"{', '.join(SECRET_RULES)} (L2-60)")
            continue
        keys = key_rects(solids, base, chest)
        skip = {base.name, chest.name}
        # (g) the jumps.
        hit = sorted(skip & reached)
        expect(not hit, f"{tag} behind ice, the water as built: no jump, double jump, dash or walk-off grace from the start "
               f"reaches the {sid}'s island or chest (L2-60 g)" + (f": reached {', '.join(hit)}" if hit else ""))
        # (g) every lift of a Double Jump owner.
        routes = lift_routes(solids, keys, skip, tall, move, lifts, air=True) if lifts else []
        told = ", ".join(f"{family} ({a.get('name')}, height {a['height']:g}, castRange {a['castRange']:g})"
                         for family, a in lifts) or "none"
        expect(not routes, f"{tag} behind ice, the water as built: no lifting ability of a Double Jump owner ends on the "
               f"{sid}'s island or chest ({told}; LIFT_MODEL \"{LIFT_MODEL}\"; L2-60 g)"
               + (f": {len(routes)} take-offs, e.g. {routes[0]}" if routes else ""))
        # (g) every air dash, and the margin.
        dashed, tight = [], None
        for o in solids:
            if o.kind not in standable or o.name in tall or o.name not in bare or o.name in skip:
                continue
            for kr in keys:
                gap = rect_gap((o.x0, o.x1, o.z0, o.z1), kr[:4])
                for family, a in dashes:
                    carry = air_carry(move, kr[4] - STEP_UP - o.top)
                    if carry is not None and gap <= carry + float(a["range"]) + BODY_RADIUS + EPS:
                        dashed.append(f"{family}'s {a.get('name')} from {o.name} (top {o.top:g}) onto {kr[5]}'s top "
                                      f"{kr[4]:g}, {gap:.1f} away (carry {carry:.1f} + {float(a['range']):g})")
                worst, means = island_reach(move, o, kr, lifts, dashes)
                if tight is None or gap - worst < tight[0]:
                    tight = (gap - worst, o.name, kr[5], gap, worst, means)
        told = ", ".join(f"{family} ({a.get('name')}, range {float(a['range']):g})" for family, a in dashes) or "none"
        expect(not dashed, f"{tag} behind ice, the water as built: no air dash of a Double Jump owner ({told}, after the "
               f"jumps' carry and the grace) reaches the {sid}'s island or chest (L2-60 g)"
               + (f": {'; '.join(dashed[:2])}" if dashed else ""))
        expect(tight is not None and tight[0] >= ICE_MARGIN - EPS,
               f"{tag} behind ice: the {sid}'s island lies at least ICE_MARGIN {ICE_MARGIN:g} beyond the farthest any means "
               f"carries a player from every other standable top (L2-60 g, L2-64): "
               + (f"the tightest {tight[1]} to {tight[2]}, {tight[3]:.1f} away against {tight[4]:.1f} ({tight[5]}): "
                  f"{tight[0]:+.1f}" if tight else "no surface"))
        if tight is not None:
            facts.append(f"{sid}, the water as built: the tightest {tight[1]} to {tight[2]} {tight[3]:.1f} studs against "
                         f"{tight[4]:.1f} ({tight[5]}), margin {tight[0]:+.1f} (needs {ICE_MARGIN:g})")
        # (a) and (d) on the island.
        reach = rules[0]
        held = trigger_tops(secret, solids, chest, rules, tall)
        loose = [(x, z) for x, z in trigger_region(secret, reach) if not base.holds(x, z)]
        expect(base.name in held and set(held) <= skip and not loose,
               f"{tag} the {sid}'s trigger (needs ice) is met from its island and its own top only, and the ground within "
               f"{reach:g} of its footprint lies over the island (L2-60 a, d): " + (", ".join(sorted(set(held))) or "none")
               + (f" (off the island at ({loose[0][0]:.1f}, {loose[0][1]:.1f}))" if loose else ""))
        # (h) frozen: the island is reached and the chest opens from it.
        fchest = next((s for s in fsolids if s.name == chest.name), None)
        fheld = trigger_tops(secret, fsolids, fchest, rules, ftall) if fchest is not None else []
        expect(base.name in freached and base.name in fheld,
               f"{tag} with the ice frozen, the {sid}'s island is reached from the start and its chest opens from the island "
               f"(L2-60 h): " + ("reached" if base.name in freached else "not reached")
               + f", trigger from {', '.join(sorted(set(fheld))) or 'nowhere'}")
    # (h) the swing extends the ice.
    families = ice_families(ctx)
    island = next((s for s in solids if s.name == (spec.get("deepWater") or {}).get("island")), None)
    if island is None:
        island = next((b for b in (secret_base(solids, x) for x in secrets) if b is not None), None)
    waters = [b for b in layout["blocks"] if b.get("react") == "ice"]
    rects = [(w["x"] - w["sx"] / 2, w["x"] + w["sx"] / 2, w["z"] - w["sz"] / 2, w["z"] + w["sz"] / 2) for w in waters]
    banks = [s for s in solids if s.name in reached and s.kind in ("block", "floor")
             and any(rect_gap((s.x0, s.x1, s.z0, s.z1), r) <= EPS for r in rects)]
    water_top = min((w["y"] + w["sy"] / 2 for w in waters), default=None)
    bank_top = max((s.top for s in banks), default=None)
    short = []
    if ice is None or not all(is_number(ice.get(k)) for k in ICE_KEYS):
        short.append("Combat.json levels.react.ice is missing a number")
    elif not families:
        short.append("no family's element is ice")
    else:
        for family, w in families.items():
            for vid, v in sorted((w.get("variants") or {}).items()):
                most = (float(v.get("range") or 0) + ice["ahead"] - BODY_RADIUS) / ICE_ROWS
                if v.get("shape") != "arc" or ice["cell"] > most + EPS:
                    short.append(f"{family} {vid}: a {v.get('shape')} of range {v.get('range')} with ahead {ice['ahead']:g} "
                                 f"takes cells of at most {most:.2f}, not {ice['cell']:g}")
        if water_top is not None and bank_top is not None and ice["reachDown"] < bank_top + sr.ROOT_HEIGHT - water_top - EPS:
            short.append(f"reachDown {ice['reachDown']:g} is under the highest bank's root over the water "
                         f"({bank_top:g} + {sr.ROOT_HEIGHT:g} - {water_top:g})")
    expect(not short, f"{tag} with the ice: every ice family's swing (an arc) freezes {ICE_ROWS:g} rows ahead of the ice's edge "
           f"(cell at most (range + ahead - {BODY_RADIUS:g}) / {ICE_ROWS:g}) and reaches down from the highest bank to the "
           f"water (L2-60 h): " + ("; ".join(short) if short else
                                   f"{', '.join(families)}; cell {ice['cell']:g}, reachDown {ice['reachDown']:g}, banks "
                                   f"{', '.join(sorted(s.name for s in banks))}"))
    cells, starts, goals, chain = ice_crossing_cells(layout, solids, ice, reached, island)
    expect(bool(cells) and chain is not None,
           f"{tag} with the ice: the open cells of the ice blocks form one 4-connected chain from a cell beside a bank a player "
           f"reaches to a cell beside the island (L2-60 h): {len(cells)} cells, {len(starts)} by a bank, {len(goals)} by the "
           f"island" + (f", the shortest chain {chain} cells" if chain is not None else ", no chain"))
    facts.append(f"{len(cells)} ice cells in {', '.join(str(w.get('name')) for w in waters)}; the shortest chain from a bank "
                 f"to the island {chain} cells")
    holes = ice_holes(layout, ice) if ice is not None else {}
    expect(bool(cells) and not holes,
           f"{tag} with the ice: the built pieces and the colliding blocks and secrets over the water fill every ice block "
           f"(a cell is left out only where one cover holds it whole: no water is left that no swing can close, and the "
           f"frozen layout's whole block stands for its pieces; the W3 fix round's d-m1), all but the rim of "
           f"levels.react.ice.inset ({sr.ice_inset(ice)}) inside each block's faces (the second fix round's Q6)"
           + ("".join(f"; {n}: {area:.2f} studs² open, e.g. x {h[0][0]:.2f}..{h[0][1]:.2f}, z {h[0][2]:.2f}..{h[0][3]:.2f}"
                      for n, (area, h) in sorted(holes.items())) if holes else f" ({len(cells)} pieces)"))
    # The third fix round's fd-m1: no frozen face on a same-facing face of a solid.
    flush = ice_coplanar(layout, ice, solids) if ice is not None else []
    expect(not flush,
           f"{tag} with the ice: no face of a built ice piece lies within levels.react.ice.inset "
           f"({sr.ice_inset(ice) if ice is not None else None}) of a same-facing face of a solid (frozen, the two would "
           f"z-fight; the W3 third fix round's fd-m1)"
           + (f": {len(flush)} pairs, e.g. " + "; ".join(f"{p} {f} on {s} ({g:.3f} apart)" for p, f, s, g in flush[:3])
              if flush else f" ({len(cells)} pieces against {len(solids)} solids)"))
    # The third fix round's fd-m2: the sheet's thickness, between a slam's step and a root.
    if ice is not None and is_number(ice.get("thickness")):
        least, most, fall, what = sheet_bounds(move, freached, fsolids, ice)
        deep = ice["thickness"]
        expect(least < deep < most - EPS,
               f"{tag} with the ice frozen, every frozen sheet is thicker than the fastest fall onto it moves in one "
               f"physics step ({what}, at {PHYSICS_HZ:g} Hz: {least:.3f}) and thinner than an R15 root ({most:g}: a "
               f"root never lies wholly inside a sheet that freezes round a body a round trip late), not "
               f"levels.floorThickness (the W3 third fix round's fd-m2): ice.thickness {deep:g}")
        facts.append(f"a frozen sheet {deep:g} deep: thicker than {least:.3f} ({what} at {PHYSICS_HZ:g} Hz), "
                     f"thinner than a root {most:g}")
    # The W2 lessons, with the ice frozen: no new ledge route, perch or wall.
    gone = sorted(n for n in tall if n not in ftall)
    expect(not gone, f"{tag} with the ice frozen every unclimbable wall stays unclimbable (L2-60, L1c-3)"
           + (f": climbable {', '.join(gone)}" if gone else f" ({len(tall)} walls)"))
    check_secret_reach(f"{name} (frozen)", frozen, ctx, expect, fsolids, ftall)
    check_origin_chord(f"{name} (frozen)", frozen, ctx, expect)
    check_kill_height(f"{tag} with the ice frozen,", frozen, fsolids, levels, expect, sheets_apart=True)
    # The W3 fix round's s2: the bend rule (the frozen sheets walked ground), the cave's closed half
    # and the walled camps, on the frozen layout too.
    check_route_skips(f"{level['layout']} (frozen)", frozen, ctx, expect, fsolids, ftall, ice=True)
    check_cave(f"{name} (frozen)", level, frozen, ctx, expect, fsolids, closed_only=True)
    check_walled(f"{name} (frozen)", level, frozen, ctx, expect, fsolids, facts=False, dry=(layout, solids))
    views = [("sniperSpotsFrozen", frozen, fsolids, "with the ice frozen")]
    if layout.get("shortcuts"):
        opened = sr.frozen_layout(open_layout(layout), ice)
        views.append(("sniperSpotsOpenFrozen", opened, solids_of(opened, thickness, depth),
                      "with the ice frozen and the brambles burnt"))
    for key, view, vsolids, label in views:
        found = sorted(sp["id"] for sp in sniper_spots(level, view, ctx, vsolids))
        pinned = spec.get(key)
        expect(pinned is None or found == sorted(pinned),
               f"{name}: {label}, the unreachable sniper spots (R8 with L2-37's sight; L2-60) are the pinned list: "
               f"{', '.join(found) or 'none'}"
               + (f" (pinned: {', '.join(sorted(pinned))})" if pinned is not None and found != sorted(pinned) else ""))


def route_blocks(layout, solids, step, ice=False):
    """The route's walked samples and how far along the route each lies, by the path or ground
    block under it: {name: (the Solid, [(along, x, z)])}. `ice` (the frozen layout, the W3 fix
    round's s2): every frozen sheet (look "ice") joined to a walked block, side to side and at most
    a step up or down, or to another sheet so joined, is walked ground too, and carries the samples
    of the walked blocks it joins (a hop from the ice is measured from where the road meets it)."""
    found = {}
    walked = 0.0
    route = layout["route"]
    for index in range(1, len(route)):
        a, b = route[index - 1], route[index]
        run = math.hypot(b["x"] - a["x"], b["z"] - a["z"])
        if b.get("via") is None and run > EPS:
            cuts = max(int(math.ceil(run / step)), 1)
            for k in range(cuts + 1):
                f = k / cuts
                x, z = a["x"] + (b["x"] - a["x"]) * f, a["z"] + (b["z"] - a["z"]) * f
                for sld in solids:
                    if (sld.kind == "block" and sld.look in ("path", "ground") and abs(sld.top - a["y"]) < 0.01
                            and sld.holds(x, z)):
                        found.setdefault(sld.name, (sld, []))[1].append((walked + run * f, x, z))
        walked += run
    sheets = [s for s in solids if ice and s.kind == "block" and s.look == "ice"]
    grew = True
    while grew:
        grew = False
        for sheet in sheets:
            joined = [entry[1] for name, entry in sorted(found.items()) if name != sheet.name
                      and entry[0].gap_to(sheet) <= EPS and abs(entry[0].top - sheet.top) <= STEP_UP + EPS]
            samples = sorted({point for points in joined for point in points})
            if joined and samples != sorted(found.get(sheet.name, (None, []))[1]):
                found[sheet.name] = (sheet, samples)
                grew = True
    return found


def rim_points(solid, step):
    xs = [solid.x0 + step * k for k in range(int((solid.x1 - solid.x0) / step) + 1)] + [solid.x1]
    zs = [solid.z0 + step * k for k in range(int((solid.z1 - solid.z0) / step) + 1)] + [solid.z1]
    return list({(x, solid.z0) for x in xs} | {(x, solid.z1) for x in xs} | {(solid.x0, z) for z in zs}
                | {(solid.x1, z) for z in zs})


def carrying_families(ctx):
    """The families whose ability carries the caster through the air (a lift's castRange, an air
    dash's range): {family: (the ability's name, studs on the flat)}."""
    found = {family: (a.get("name"), float(a["castRange"])) for family, a in ctx.get("lifts") or []}
    for family, a in ctx.get("dashes") or []:
        if float(a["range"]) > found.get(family, (None, 0.0))[1]:
            found[family] = (a.get("name"), float(a["range"]))
    return found


def check_route_skips(name, layout, ctx, expect, solids, tall, ice=False):
    """L2-47 (Ben: "close it now"): no hop cuts a bend of the road. For every two walked road
    blocks that do not touch, the shortest way through the air from the edge of one to the edge
    of the other (round every unclimbable wall: through their corners, in plan) is longer than a
    jump, a double jump, a dash and the walk-off grace carry (falling the drop between them), or it
    saves at most SKIP_SAVE studs of the route (measured from the route's nearest point on each
    block). The fix round's d-m2: the same with the longest flat travel of an ability that carries
    its caster (carrying_families) on top is a KNOWN LIMIT (reported; no camp is skipped)
    while no such family can be owned without a lever (ctx ownedFamilies, ownable_families: the
    starters, every family a level's secret pays and every firstClear family, L3-25); once one can,
    it is red. `ice` (check_ice's run on the
    frozen layout): the frozen sheets are walked ground (route_blocks), and no gate-16 rows."""
    move = ctx["move"]
    blocks = route_blocks(layout, solids, SAMPLE * 4, ice)
    walls = [(s.x0, s.x1, s.z0, s.z1) for s in solids if s.name in tall]
    grace = move["walkSpeed"] * (move.get("coyoteSeconds") or 0)
    carriers = carrying_families(ctx)
    travel = max([0.0] + [studs for _name, studs in carriers.values()])
    names = sorted(blocks)
    worst, cuts, lifted = None, [], []
    for i, an in enumerate(names):
        for bn in names[i + 1:]:
            a, sa = blocks[an]
            b, sb = blocks[bn]
            gap = a.gap_to(b)
            if gap <= EPS or (ice and a.look != "ice" and b.look != "ice"):  # the dry run judged two road blocks
                continue
            lo, hi = (a, b) if a.top >= b.top else (b, a)
            reach = stray_reach(move, lo.top - hi.top) + grace
            far = reach + travel
            if gap > far + EPS or hi.top - lo.top > climb_max(move, ctx["abilityHeight"]) + EPS:
                continue
            box = (min(a.x0, b.x0) - far, max(a.x1, b.x1) + far, min(a.z0, b.z0) - far, max(a.z1, b.z1) + far)
            near = [w for w in walls if rect_gap(w, box[:4]) <= EPS]
            corners = [(w[0] - 0.01, w[2] - 0.01) for w in near] + [(w[0] - 0.01, w[3] + 0.01) for w in near]
            corners += [(w[1] + 0.01, w[2] - 0.01) for w in near] + [(w[1] + 0.01, w[3] + 0.01) for w in near]

            def clear(p, q):
                return not any(seg_hits_rect(p[0], p[1], q[0], q[1], w) for w in near)

            n = len(corners)
            graph = [[math.inf] * n for _ in range(n)]
            for u in range(n):
                graph[u][u] = 0.0
                for v in range(u + 1, n):
                    if clear(corners[u], corners[v]):
                        graph[u][v] = graph[v][u] = math.dist(corners[u], corners[v])
            for k in range(n):
                for u in range(n):
                    for v in range(n):
                        if graph[u][k] + graph[k][v] < graph[u][v]:
                            graph[u][v] = graph[u][k] + graph[k][v]
            pa = [p for p in rim_points(a, SKIP_STEP) if point_rect((b.x0, b.x1, b.z0, b.z1), *p) <= far]
            pb = [p for p in rim_points(b, SKIP_STEP) if point_rect((a.x0, a.x1, a.z0, a.z1), *p) <= far]
            if not pa or not pb:
                continue
            to_b = []
            for q in pb:
                seen = [math.dist(q, corners[v]) if clear(q, corners[v]) else math.inf for v in range(n)]
                to_b.append([min((graph[u][v] + seen[v] for v in range(n)), default=math.inf) for u in range(n)])

            def along(points, p):
                return min(points, key=lambda r: (r[1] - p[0]) ** 2 + (r[2] - p[1]) ** 2)[0]

            known = None
            for p in pa:
                from_a = [math.dist(p, corners[u]) if clear(p, corners[u]) else math.inf for u in range(n)]
                sp = along(sa, p)
                for q, rest in zip(pb, to_b):
                    hop = math.dist(p, q) if clear(p, q) else min((from_a[u] + rest[u] for u in range(n)), default=math.inf)
                    if hop > far + EPS:
                        continue
                    saved = abs(along(sb, q) - sp) - hop
                    if hop > reach + EPS:
                        if saved > SKIP_SAVE + EPS and (known is None or saved > known[0]):
                            known = (saved, f"{an} to {bn}: a hop of {hop:.1f} (over the {reach:.1f} of the jumps and "
                                            f"a dash) from ({p[0]:g}, {p[1]:g}) to ({q[0]:g}, {q[1]:g}) saves "
                                            f"{saved:.0f} studs of road")
                        continue
                    if worst is None or saved > worst[0]:
                        worst = (saved, f"{an} ({p[0]:g}, {p[1]:g}) to {bn} ({q[0]:g}, {q[1]:g}), a hop of {hop:.1f}")
                    if saved > SKIP_SAVE + EPS:
                        cuts.append(f"{an} to {bn}: a hop of {hop:.1f} from ({p[0]:g}, {p[1]:g}) to ({q[0]:g}, {q[1]:g}) "
                                    f"saves {saved:.0f} studs of road")
                        break
                else:
                    continue
                break
            if known is not None:
                lifted.append(known[1])
    expect(not cuts, f"{tag_of(name)} no hop cuts a bend: between two walked road blocks that do not touch, the shortest way "
           f"round the unclimbable walls is beyond a jump, a double jump, a dash and the walk-off grace, or saves at most "
           f"{SKIP_SAVE:g} studs of road (L2-47)" + (": " + "; ".join(cuts[:3]) if cuts else
                                                     f" (the most any hop saves: {worst[0]:.0f}, {worst[1]})" if worst else ""))
    owners = sorted(ctx.get("ownedFamilies") or ctx.get("loadout") or [])
    owned = sorted(set(owners) & set(carriers))
    told = ", ".join(f"{family}'s {ability} {studs:g}" for family, (ability, studs) in sorted(carriers.items())) or "none"
    if lifted and not owned:
        verdict = (f"KNOWN LIMIT until a family that carries can be owned (the fix round's d-m2; L3-25: the Castle's Greataxe "
                   f"at the earliest): {len(lifted)} hop(s) with an ability's travel cut a bend, "
                   f"no camp skipped, and no family that carries can be owned without a lever (owned: "
                   f"{', '.join(owners) or 'none'}): {'; '.join(lifted[:2])}")
        if not ice:
            ctx["gate16"].setdefault(name, {}).setdefault("lifts", []).extend(
                f"bend (known limit while no family that carries can be owned, d-m2): {line}" for line in lifted)
    elif lifted:
        verdict = f"{', '.join(owned)} can be owned without a lever: {'; '.join(lifted[:3])}"
    else:
        verdict = "no hop with an ability's travel cuts one either"
    expect(not lifted or not owned,
           f"{tag_of(name)} no hop with an ability that carries ({told}, on top of the jumps and a dash) cuts a bend by more "
           f"than {SKIP_SAVE:g} studs of road while a family that carries can be owned without a lever (L2-47, the fix "
           f"round's d-m2): {verdict}")


def tag_of(name):
    return f"{name}:"


def three_positive(value):
    """Is `value` a list of exactly three positive numbers (a size in studs)?"""
    return (isinstance(value, list) and len(value) == 3
            and all(isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0 for v in value))


def check_map(expeditions, level_files, layouts, expect, ctx=None):
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
    # L2-51: a family found on a map node (the Frost Hammer in the Castle), not in any level's chest.
    found = expeditions.get("found")
    weapons = (ctx or {}).get("weapons") or {}
    starters = set((ctx or {}).get("loadout") or [])
    paid = {(entry or {}).get("family") for file in level_files for entry in (file.get("secrets") or {}).values()
            if isinstance(entry, dict)}
    bad = [] if found is None or isinstance(found, dict) else [f"found is {type(found).__name__}, not a table"]
    for family, entry in sorted((found if isinstance(found, dict) else {}).items()):
        entry = entry if isinstance(entry, dict) else {}
        text = entry.get("text")
        if family not in weapons:
            bad.append(f"{family} is no family of ProvingGrounds.json weapons")
        if family in starters:
            bad.append(f"{family} is a starter")
        if family in paid:
            bad.append(f"{family} is also paid by a secret")
        if entry.get("node") not in ids:
            bad.append(f"{family}'s node {entry.get('node')} is no map node")
        if not (isinstance(text, str) and 1 <= len(text) <= 40):
            bad.append(f"{family}'s text {text!r} is not 1-40 characters")
    named = ", ".join(f"{f} on {e.get('node')}: {e.get('text')}" for f, e in sorted(found_families(expeditions).items()))
    expect(not bad, "map: every family Expeditions.json `found` names exists, is not a starter, is paid by no secret, "
           "names a map node and has a text of 1-40 characters (L2-51): " + ("; ".join(bad) if bad else named or "none"))
    # L3-25 (the lead's ruling 2): every family that is not a starter has a shelf hint, a `found`
    # entry or the secret that pays it (the Armory screen drops a family with neither).
    hinted = set(found_families(expeditions)) | {f for f in paid if f}
    bare = sorted(f for f in weapons if f not in starters and f not in hinted)
    expect(not bare, f"map: every weapons family that is not a starter has a shelf hint, a `found` entry or a secret "
           f"that pays it (L3-25): " + (f"none for {', '.join(bare)}" if bare else
                                        f"{len(weapons) - len(starters)} families, {len(found_families(expeditions))} "
                                        f"found entries, paid by a secret: {', '.join(sorted(f for f in paid if f)) or 'none'}"))
    # ... and a family a difficulty's firstClear gives, when it has a `found` entry, is found on the
    # map node of that level (its hint names where it really comes from).
    nodes_of = {}
    for node in nodes:
        if node.get("level"):
            nodes_of.setdefault(node["level"], set()).add(node["id"])
    astray = []
    told = []
    for file in level_files:
        for difficulty, scales in sorted((file.get("difficulties") or {}).items()):
            first = scales.get("firstClear") if isinstance(scales, dict) else None
            family = first.get("family") if isinstance(first, dict) else None
            entry = found_families(expeditions).get(family) if isinstance(family, str) else None
            if entry is None:
                continue
            told.append(f"{family} ({file['id']} {difficulty}) on {entry.get('node')}")
            if entry.get("node") not in nodes_of.get(file["id"], set()):
                astray.append(f"{family} is given by {file['id']}'s {difficulty} first clear but found on "
                              f"{entry.get('node')}, not on {', '.join(sorted(nodes_of.get(file['id'], set()))) or 'no node'}")
    expect(not astray, "map: every firstClear family with a `found` entry is found on its level's map node (L3-25): "
           + ("; ".join(astray) if astray else ", ".join(told) or "none"))
    sign = expeditions.get("sign") or {}
    expect(len(sign.get("textColor") or []) == 3 and (sign.get("pixelsPerStud") or 0) > 0,
           "map: the signs have a text colour and a pixel density")
    expect(three_positive(sign.get("size")),
           f"map: sign.size is three positive numbers (a secret's sign block): {sign.get('size')}")


# ---------------------------------------------------------------------------------------------
# The pictures
# ---------------------------------------------------------------------------------------------

LOOK_CHARS = {"path": "=", "ground": "%", "water": "~", "lobby": ":", "wall": "#", "sign": "i", "bramble": "*"}
LEGEND = ("= road   % ledge or ground   ~ water   . camp floor   # fence or wall   * bramble   | - gate   x spawn point   "
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
    layouts = {name: sr.load_level_layout(name) for name in names}
    size = (expeditions.get("sign") or {}).get("size")
    ctx = {"levels": combat["levels"], "move": proving["movement"], "looks": expeditions["looks"], "kinds": kinds,
           "widest": max(k["radius"] for k in kinds.values() if k.get("brain") and not k.get("boss")),
           "spawnClear": proving["crowd"]["threat"]["spawnClear"], "crowdMaxAlive": proving["crowd"]["maxAlive"],
           "campRadius": {}, "signSize": size if three_positive(size) else None,
           "runCap": combat["director"]["runCapSeconds"], "camps": combat.get("camps"),
           "ranks": sr.difficulty_ranks(expeditions), "snapshotHz": proving["crowd"]["snapshotHz"],
           "gate16": {}, "chains": {}, "sniperReach": sniper_reach(proving["weapons"], (proving.get("loadout") or {}).values()),
           "abilityHeight": ability_height(proving), "camera": combat.get("camera"), "theme": theme_numbers(),
           "renderer": renderer_numbers(), "abilityIds": ability_ids(expeditions), "lifts": lifting_abilities(proving),
           "fieldedLifts": fielded_lifts(proving), "loadout": sorted((proving.get("loadout") or {}).values()),
           "dashes": dashing_abilities(proving), "rescue": combat["player"].get("rescue"),
           "weapons": proving["weapons"],
           "originWallChord": (proving.get("shooting") or {}).get("originWallChord"),
           "armory": sr.load_config(sr.ARMORY_PATH),
           "dress": {name: dress_barriers(name) for name in names}, "raiders": raider_models()}
    return combat, expeditions, layouts, sr.load_level_files(), ctx


def sniper_reach(weapons, owned):
    """R8's reach (L3-25): the longest range of any variant of an ownable ranged family (`owned`:
    ownable_families). (studs, "family variant"); (0, "none") when no ranged family can be owned."""
    best = (0.0, "none")
    for family in sorted(set(owned)):
        weapon = weapons.get(family) or {}
        if weapon.get("slot") != "ranged":
            continue
        for key, variant in sorted((weapon.get("variants") or {}).items()):
            if is_number(variant.get("range")) and variant["range"] > best[0]:
                best = (float(variant["range"]), f"{family} {key}")
    return best


def ownable_families(level_files, layouts, expeditions, weapons, loadout):
    """L3-25: the families a player can own without a Studio lever: the starters (`loadout`), every
    family a level's secret pays behind a key he can come to hold (key_chain: a sold ability, or an
    element whose carrier is paid or found on a map node; the fix round's d-m2), and every family a
    difficulty's firstClear gives. An Expeditions.json `found` entry is a shelf hint, not a source:
    the Frost Hammer, found in the Castle, stays lever-only until the Castle exists."""
    owned = set(loadout)
    for file in level_files:
        layout = layouts.get(file.get("layout"))
        if layout is not None and layout.get("secrets") is not None:
            keys, _steps = key_chain(file, layout, expeditions, weapons)
            needs = {s.get("id"): s.get("needs") for s in layout["secrets"]}
            for sid, entry in (file.get("secrets") or {}).items():
                family = entry.get("family") if isinstance(entry, dict) else None
                if family and needs.get(sid) in keys:
                    owned.add(family)
        for scales in (file.get("difficulties") or {}).values():
            first = scales.get("firstClear") if isinstance(scales, dict) else None
            family = first.get("family") if isinstance(first, dict) else None
            if isinstance(family, str) and family:
                owned.add(family)
    return sorted(owned)


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
    react = levels.get("react") or {}
    expect(isinstance(react, dict) and sr.whole(react.get("fireHits")) and is_number(react.get("pad"))
           and react["pad"] >= 0,
           f"Combat.json levels.react (L2-34): fireHits a whole number of at least 1 ({react.get('fireHits')}) and pad 0 "
           f"or more ({react.get('pad')})")
    ice = react.get("ice") if isinstance(react, dict) else None
    odd = [] if isinstance(ice, dict) else ["levels.react.ice is missing"]
    for key in ICE_KEYS if isinstance(ice, dict) else ():
        value = ice.get(key)
        if (not is_number(value) or not math.isfinite(value)
                or (value < 0 if key in ("lift", "ahead", "inset") else value <= 0)):
            odd.append(f"{key} {value}")
    expect(not odd and "iceHits" not in react,
           "Combat.json levels.react.ice (L2-53): cell, thickness, reachDown and sink over 0, lift, ahead and inset 0 or "
           "more; iceHits gone (a swing freezes cells, it does not count hits): " + ("; ".join(odd) if odd else ", ".join(
               f"{key} {ice[key]:g}" for key in ICE_KEYS)) + ("; iceHits is still there" if "iceHits" in react else ""))
    # The W3 second fix round's Q6 and Q5: the inset stays a seam, and the sink keeps a body's
    # colliding root out of the ice it lets freeze.
    inset, sink = (ice.get("inset"), ice.get("sink")) if isinstance(ice, dict) else (None, None)
    expect(is_number(inset) and is_number(sink) and 0 <= inset <= ICE_INSET_MOST and 0 < sink < ICE_SINK_MOST,
           f"Combat.json levels.react.ice's inset and sink (the W3 second fix round's Q6, Q5): inset from 0 to "
           f"ICE_INSET_MOST {ICE_INSET_MOST:g} (a seam a body walks across, not a gap: {inset}), sink over 0 and under "
           f"ICE_SINK_MOST {ICE_SINK_MOST:g} (a standing body's feet ride a hair under the top; deeper than the R15 "
           f"HipHeight its root would be in the ice: {sink})")
    debug = combat.get("debug") or {}
    names = [debug.get(key) for key in DEBUG_UNLOCK_KEYS]
    taken = [v for k, v in debug.items() if k.endswith("Attribute") and k not in DEBUG_UNLOCK_KEYS]
    expect(all(isinstance(v, str) and v for v in names) and len(set(names)) == len(names)
           and not set(names) & set(taken),
           "Combat.json debug (L2-19, L2-38, L3-28): " + ", ".join(f"{k} {debug.get(k)!r}" for k in DEBUG_UNLOCK_KEYS)
           + " are Workspace attribute names of their own")
    presets = [(p.get("melee"), p.get("ranged")) for p in debug.get("gearPresets") or []]
    proving = debug.get("provingGear") or {}
    tiers = sorted({d["recommendedTier"] for file in level_files for d in (file.get("difficulties") or {}).values()})
    reached = all(any(melee == tier for melee, _r in presets) for tier in tiers)
    expect(presets == list(GEAR_PRESETS) and presets[:1] == [(proving.get("melee"), proving.get("ranged"))] and reached,
           f"Combat.json debug.gearPresets are {', '.join(f'{m}/{r}' for m, r in GEAR_PRESETS)} (the G key), the first "
           f"is debug.provingGear, and every difficulty's recommendedTier ({', '.join(map(str, tiers))}) is a preset's "
           f"melee tier: " + ", ".join(f"{m}/{r}" for m, r in presets))


def check_adapters_gone(combat, expeditions, level_files, layouts, expect):
    """L4 W1b section 3 (docs/prompts/l4-w1b-contract.md): the Raider Arena is hidden by deleting its
    data, and ruling 27's two adapters went with it. Tripwires: Combat.json debug.provingLevel (what a
    proving build plays) names a map node with a level file; no level file names a `mission` and no
    layout an `arena` (StageFlow.Resolve and LevelGeometry no longer read either)."""
    proving = (combat.get("debug") or {}).get("provingLevel")
    files = {file["id"] for file in level_files}
    noded = [node["id"] for node in expeditions.get("nodes") or [] if node.get("level") == proving]
    expect(isinstance(proving, str) and proving in files and len(noded) == 1,
           f"Combat.json debug.provingLevel {proving!r} is one map node's level ({', '.join(noded) or 'none'}) with a "
           f"level file")
    named = [file["id"] for file in level_files if "mission" in file]
    arenas = [name for name, layout in layouts.items() if "arena" in layout]
    expect(not named and not arenas, "no level file names a mission and no layout an arena (ruling 27's adapters went "
           "in L4 W1b)" + (f": {', '.join(named + arenas)}" if named or arenas else ""))


def check_trophy(armory, expeditions, expect):
    """R1 (the L3 W1 fix round, review 1-m5): a band's top tier opens with that level's Hard star or a
    harder one (Armory.StarHeld). Armory.Problems holds the shape (a starDifficulty, starAlso a list
    of names); this holds the names to Expeditions.json `difficulties`: starDifficulty is one of them,
    and starAlso lists exactly the difficulties after it, in their order, so no easier star opens a
    band top and none harder is left out."""
    ladder = (armory or {}).get("ladder") or {}
    order = list(expeditions.get("difficulties") or [])
    star, also = ladder.get("starDifficulty"), ladder.get("starAlso")
    harder = order[order.index(star) + 1:] if star in order else None
    expect(harder is not None and also == harder,
           f"Armory.json ladder (R1): starDifficulty {star!r} is a difficulty of Expeditions.json and starAlso lists "
           f"every harder one, in order ({harder}): {also!r}")


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
    check_map(expeditions, level_files, layouts, expect, ctx)
    check_abilities(expeditions, level_files, expect)
    check_rules(combat, level_files, ctx, expect)
    check_adapters_gone(combat, expeditions, level_files, layouts, expect)
    check_trophy(ctx.get("armory"), expeditions, expect)
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
    # The families a player can own without a Studio lever (L3-25): the starters, every family a
    # secret pays behind a key he can come to hold (the fix round's d-m2) and every firstClear family;
    # R8's reach is the longest range among their ranged variants. Before the level files: their
    # region rules (check_wave4) list the sniper spots.
    ctx["ownedFamilies"] = ownable_families(level_files, layouts, expeditions, ctx.get("weapons") or {},
                                            ctx.get("loadout") or [])
    ctx["sniperReach"] = sniper_reach(ctx.get("weapons") or {}, ctx["ownedFamilies"])
    for file in level_files:
        level = sr.resolve_level(file, ctx["runCap"])
        check_level_file(file, level, layouts, ctx, expect)
        if file.get("layout") in layouts:
            check_secret_rewards(file, layouts[file["layout"]], expeditions, expect, ctx.get("weapons"), ctx["ranks"])
    bounds_of = {name: layout_bounds(layout, ctx["levels"]["fenceThickness"], ctx["levels"]["floorThickness"])
                 for name, layout in layouts.items()}
    for name, layout in layouts.items():
        check_origin_chord(name, layout, ctx, expect)
        if name == lobby_name:
            check_lobby(name, layout, ctx, bounds_of, expect)
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
        for line in found.get("ice") or []:
            print(f"    ice         {line}")
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
