#!/usr/bin/env python
"""Proving Grounds range simulator for Era City Tycoon (P2 method, made permanent in P3).

Reads `src/shared/Config/ProvingGrounds.json` and measures every weapon family and every ability
the way the server resolves them, so a value changed in the JSON is measured here with no edit:

  * geometry mirrors `src/shared/HitShapes.luau` in 3D: the padded sector (the arc as a vertical
    slab), sphere, capsule, cone, the ray's entry distance, and the Pellets/Fan/Scatter patterns.
    Enemies are a body sphere (centre height/2) plus an unpadded head sphere (the crit point),
    sized by `crowd.kinds`;
  * hits mirror `src/combat/server/Services/RangeService.luau`: gather, then nearest-first, then
    `cap` (0 = all); pierce = TOTAL enemies per ray or arrow; split volleys share one hit set and
    one cap; flat armour `max(amount - armor, amount * armorFloor)`;
  * P3 (docs/INTERFACES.md "P3 contracts"): Chain Gun chains (their hits skip cap and pierce),
    the Mag Dump buff, and every ability row of the ability table: timelines, zones as vertical
    capsules, Earthquake rings, Overload slices with one shared exclude, and cluster bomblets on
    the Scatter ring. Blade Storm's pull and all knockback are ignored (dummies do not move here).

Crowds are square grids of `crowd.stressCount` fodder (floor(sqrt) per side) at 3 and 6 stud
spacing. Positions and aim follow the P2 method (docs/BALANCE.md "P2"): melee stands 2.6-3.6 studs
from the crowd's front edge; ranged fires from 20 studs (8 for cone guns) plus 0-3; the crowd's
lateral phase and a +-1.5 stud aim offset are random. Ranged rays travel level at fodder chest
height, so thin rays never crit (the P2 tables assumed no crits) while a ray wide enough to reach
the heads does, exactly as the server's head test would.

Three measurements:
  crowd DPS      damage per attack on immortal fodder x attack rate (the WEAPONS.md basis);
  damage / cast  one cast's whole timeline on immortal fodder (same basis), plus hits and kills
                 on real 40-HP fodder;
  effective CD   a 90 s fight against a respawning crowd: normal attacks whenever the busy lock
                 allows, the ability cast the moment it is ready, every kill refunding it
                 (INTERFACES P3 ruling 2). Reported as the mean interval between casts.

P4 (docs/INTERFACES.md "P4 contracts") adds the threat: one player against a dummy set whose
groups fight, under a few player policies (stands still, walks away, fights; wave 2: hops,
strafes one way, reacts to every tell). Here the crowd moves: the section mirrors the rush and
keepAway brains, the attacker cap, windup -> attack -> recover, the six attack shapes (lunge,
arc, shot, line, lob, lane), the commit rule, i-frames, knocks, going down, regen and the
plate, and checks the contract's balance targets. It also reads Armory.json (the player's
health), Combat.json (the server's timing tolerance) and the arena's layout module (floor,
fence, lobby pad).

P4 Stop 2 adds the boss: a kind with several attacks and the choice among them, the ring, the
summon, the barrage, the enraged phase and its chains. Its fights run until it falls: a player
who stands, one who only jumps the ring and sidesteps the charge, and one who reacts to every
tell and attacks, with every weapon family, without abilities and with them.

P4 Stop 3 adds the boss with a guard: `calm` attacks, `uses`, the `guarded` plate, the brain an
enraged body takes (enrage.brain). Its players: one who stands, two who ignore the guard and
chase the boss (one of them reacting to every tell), and the one who reacts, kills the guard,
breaks the plate (with the ground slam when no hit of his weapon is heavy) and then duels.

P5 Wave 1 adds the mission: the same crowd and player seen through a mission's `crowd` block
(HP, plate, damage and regen scales; the player's hits scaled by his Armory tier, the plate and
heavy-hit rules on the tier-1 amount; his health from his gear), in the mission's arena, at
Combat.json debug.provingGear. It measures the hits against that bar, a still player in the first
fodder wave, both bosses alone at their `boss.at`, and whole runs of all ten waves through
WaveService's queue, director and breathers: the player who reacts to every tell and, for
information, the one who never dodges. With no mission view every range number is as before.

L1 ("Forest Road in grey") makes a mission a level: an ordered list of stages, `travel` and
`camp`, run by the rules of StageFlow (the trigger, the countdown, the close, the waves).

L1b ("the living road", Wave 1) puts residents in every camp: groups at posts, on patrol and at
fires, on each camp's own floor, under a mirror of CampBrain (cb_*: they rest, wake on sight or a
hit, rise, fight only a player in play, leash, walk home, heal). Only the boss room is a stage and
locks; every kill is paid as it falls (SplitCarry). New players: `still` (stands where a group
first wakes), `kite` (runs out and comes back), `edge` (stands just past chaseMargin and hits),
and the first-strike approach on every fire group. The run is `LevelRun`, which mirrors StageFlow.Advance row for row and
fights each camp on that camp's own floor. The ten-wave Village arena is the level "Raider
Arena", read through mirrors of the two adapters (StageFlow.Resolve and
LevelGeometry.FromArena), and keeps its P5 bands. Forest Road is read from
Config/Levels/1_ForestRoad.json and Layouts/Levels/ForestRoad.json and has bands of its own, at
each of its three difficulties.

The L1 fix round (docs/prompts/l1-fix-round.md, part E) adds the bands that can see a
difficulty's damageScale. The player who reacts to every tell takes no hit, so his runs say how
long a level is and nothing about how hard it hits. Two more players are hit: one with a human's
reaction (HUMAN_REACTION_SECONDS), who must clear at the recommended gear without going down;
and the one who never dodges, who must not clear at all. The recommended gear of a difficulty
is the Studio gear preset of its recommendedTier (Combat.json debug.gearPresets). "Clearly
beyond the gear below" is asked one preset under it: the human goes down there or is much
slower, and the boss alone outlasts a time. The human in this simulator is hit by nothing but
slingers' shots at close range, so his gates measure slingers times damageScale and no more: a
better human is owed before the real balance pass. The default ranged family is reported for
information.

The fix round's last step (E4) mirrors what engineer B landed in StageFlow and WaveService: the
director keeps its tempo through a camp's breathers as well as its fights (directs); a
countdown that ends with nobody on his feet arms the camp again (rearm); the close is judged
again for levels.closeGraceSeconds (still_closing); State.closedAt and State.fought, and who
earns the star (earns_star); and the Studio levers Skip and Force, which the simulator's own
runs never use and tools/check_stage_mirror.py holds to the Luau.

WHICH PYTHON. The gate is `py tools/sim_range.py --check`, and the launcher follows the first
line of this file to the 64-bit Python 3.12. `py -`, a script with no such line, and whatever
imports this file from one run on the machine's other Python (3.14, a 32-bit build). A level
run is chaotic, and the two builds can differ by up to 0.08 min on one seed (interpreter_note).
Every number in docs/BALANCE.md is the gate's; `--check` prints the interpreter it ran on.

Usage:
  py tools/sim_range.py                 # all tables
  py tools/sim_range.py --check         # exit 1 if a shipped value leaves the design bands
  py tools/sim_range.py --config PATH   # measure another ProvingGrounds.json
  py tools/sim_range.py --trials 60     # fewer random trials (faster, noisier)
  py tools/sim_range.py --levels-only   # only the level sections (with --check: their bands)
  py tools/sim_range.py --levels-only --level forest   # only Forest Road (or: arena)
  py tools/sim_range.py --mission PATH  # play another Missions/*.json as the Raider Arena
"""

from __future__ import annotations

import argparse
import heapq
import json
import math
import random
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "ProvingGrounds.json"
# P4 threat: where the player's health, the server's timing tolerance and the arena come from.
ARMORY_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Armory.json"
COMBAT_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Combat.json"
LAYOUT_DIR = REPO_ROOT / "src" / "shared" / "Layouts" / "Arenas"

# ---------------------------------------------------------------------------------------------
# Design bands (--check). Sources: docs/WEAPONS.md section 2 (family targets) and the P3 brief in
# docs/BALANCE.md "P3". Every band is a target for the SHIPPED values, measured at 6-stud spacing.

# New P3 families: DPS within this share of the WEAPONS.md figure. Keys: single, crowd6 (6-stud
# grid), crowd3 (3-stud grid). The SMG's "crowd = single" (one enemy per bullet) is read on the
# packed grid, where every bullet finds a body; on the 6-stud grid the level ray also slips
# between aligned columns, which is a property of the grid, not of the gun.
FAMILY_TOLERANCE = 0.15
FAMILY_TARGETS = {
    "smg": {"single": 108, "crowd3": 108},  # the boss and elite shredder
    "beam": {"crowd6": 250},  # paint the crowd
    "chaingun": {"crowd6": 240},  # lightning through a pack
}
# A and B of one family sit at similar crowd DPS: |A - B| / mean at most this.
AB_SPREAD = 0.20
# One cast = this many seconds of the family's own crowd DPS (default variant) as a burst.
BURST_SECONDS = (3.0, 5.0)
# Abilities allowed to lean single-target: their burst band is measured on the boss against the
# family's single DPS instead, and their crowd burst only has the ceiling below.
SINGLE_TARGET_ABILITIES = ("overchargedShot", "magDump")
SINGLE_TARGET_CROWD_CEILING = 8.0
# A busy-locking ability must beat the normal attacks it locks out by at least this much.
NET_AFTER_BUSY_SECONDS = 1.0
# In a busy crowd, kill refunds bring the cooldown to this share of its base...
EFFECTIVE_COOLDOWN_SHARE = (0.40, 0.60)
# ...and the floor (minCooldownSeconds) sits here, so it is a backstop, not the usual outcome,
# and never short enough to spam.
FLOOR_SHARE = (0.30, 0.45)
FLOOR_MIN_SECONDS = 3.0

# P4 threat bands. Sources: docs/INTERFACES.md "P4 contracts" -> "Balance targets", and
# docs/BALANCE.md "P4". Health is tier-1 health: Armory.MaxHp with both slots at THREAT_TIER,
# where the range pins every player whatever their profile holds (ruling 17).
THREAT_TIER = 1
# No single hit, and no volley landing inside one dash i-frame window, takes more than this
# share of health.
HIT_SHARE_MAX = 0.25
# A player who stands still from the moment the set loads goes down within these seconds.
STAND_DOWN_SECONDS = {"fodderRush": (6.0, 12.0), "fight": (4.0, 8.0)}
# The sets whose still player is hit by lunges and knocking arcs only. Wave 1's rhythm, floor,
# burst and kiting-distance bands are read there; a set with shooters lands unlike hits together
# by design, and reaches further than a walker keeps off.
BURST_SETS = ("fodderRush", "elites")
# The players who answer what they see: no telegraphed hit may land on them once they act.
DODGING_POLICIES = ("walk", "break", "fight", "turn", "react", "duel")
# Lunges landing per second on a still, swarmed player: slow enough that every hurt flash reads
# (a rhythm, not a drain), fast enough that standing in a rush is never safe.
SWARM_HITS_PER_SECOND = (1.5, 3.5)
# A tell lasts at least this much longer than one crowd step (a lost snapshot) + the reaction
# time + the walk out of the shape, so stepping out, dashing and jumping all work.
TELL_MARGIN_SECONDS = 0.05
# Dash spam keeps a player invulnerable this share of the time (the server accepts a dash every
# dashCooldown x the timing tolerance): enough to dodge with, never enough to stand in a rush.
DASH_UPTIME = (0.20, 0.50)
# An i-frame dodge leaves at least this wide a window to press in (dashIframes + lag).
DASH_WINDOW_SECONDS = 0.20
# A knock carries the player out of the shape of a second enemy of the same kind standing up to
# this many degrees round him from the attacker: enemies that came from one side cannot chain.
KNOCK_CLEARS_DEGREES = 90
# A kiting player (fodder are slower than the walk) never lets an enemy closer than this share
# of its reach once he is moving: a walker is never even wound up at.
WALK_CLEAR_SHARE = 1.0

# P4 wave 2 bands (docs/INTERFACES.md "Wave 2 — roles" -> "Balance"; docs/BALANCE.md "P4").
# Blind movement is not a free pass. Against a slinger alone, a player who hops on the spot, or
# strafes one way, is hit by at least this share of its shots (a player who reacts takes none
# and one who stands takes all). And it matters: at that rate the slingers of COUNT_SET alone
# land on him more often than his regen can answer, that is, with less than player.regenDelay +
# one shot's damage / player.regenPerSecond between hits.
BLIND_SHOT_SHARE = {"hop": 0.20, "strafe": 0.50}
# A line is a wall: a player hopping on the spot is hit by at least this share of them.
LINE_HOP_SHARE = 0.90
# One shooter of each kind is measured alone, from this set, against these players
# (THREAT_POLICIES); the seconds between hits are then counted for as many as COUNT_SET fields.
ROLE_SET = "shooters"
COUNT_SET = "fight"
ROLE_PLAYERS = ("stand", "hop", "strafe")
# Enemies of one kind take turns (CrowdKindDef.perPlayer), so the worst quarter second (one
# dash i-frame window) a still player takes in COUNT_SET stays under this share of the bar:
# half of it, with the weight of one lunge to spare so the band does not hang on one point of
# damage. A kind that lands two at once fails it.
FIGHT_BURST_SHARE = 0.55
# And by the rules alone, in any fighting set: one turn of every kind that does not knock, plus
# the hardest knock, leaves more than a third of the bar. One more hit of any size
# HIT_SHARE_MAX allows then does not finish a bar that was full.
INSTANT_SHARE_MAX = 2 / 3
# The slinger still lands on a one-way strafer at these pings (lag = ping +
# shooting.originLagSeconds): its aim is led over the flight plus that lag.
PING_CHECKS = (0.1, 0.15)
# P4 Stop 2 bands (docs/INTERFACES.md "Stop 2 - the Colossus" -> "Balance targets";
# docs/BALANCE.md "P4"). Solo, at THREAT_TIER health.
# A player who reacts to every tell kills the boss within these seconds with any melee family
# (per boss kind; Stop 3: docs/INTERFACES.md "Stop 3 - the Warlord and his guard").
BOSS_KILL_SECONDS = {"colossus": (60.0, 90.0), "warlord": (75.0, 115.0)}
# The stop a boss kind was built in, for the report's headings (no entry = Stop 2).
BOSS_STOP = {"warlord": 3}
# A player who stands still from the set's load is down within this.
BOSS_STAND_DOWN_SECONDS = 10.0
# After each attack, in each phase, the boss does nothing for at least this long.
BOSS_WINDOW_SECONDS = 1.0
# The phone thumb: every tell must still clear this reaction, with this much to spare.
BOSS_THUMB_SECONDS = 0.35
BOSS_THUMB_MARGIN_SECONDS = 0.12
# What the boss calls matters and does not decide: with the call, the default melee's kill takes
# this much longer than without it.
BOSS_CALL_SHARE = (0.03, 0.30)
# P4 Stop 3 bands (the lead's retarget after the first round). The siege (from the set's load to
# the plate's break) is this share of the kill for every melee family.
SIEGE_SHARE = (0.35, 0.55)
# The plate phase (the guard dead, the plate not yet broken) lasts at most this long, and the
# boss gives at most this much ground in it, for the default melee family and for every family
# that needs the ground slam; in every seed.
PLATE_PHASE_SECONDS = 20.0
PLATE_PHASE_STUDS = 60.0
# Every ranged family but the bows (a known weapon question) wins inside this, without its ability.
RANGED_KILL_SECONDS = 150.0
# A player who ignores the guard and only chases the boss is watched this long; by then the
# plate is whole, the guard lives, he has been down, and it has cost him this many health bars.
CHASE_SECONDS = 90.0
CHASE_COST_BARS = 3.0
# The plate: every melee family breaks it within this many combos; once it is broken this
# family kills the elite within these seconds; the reel lasts at least a reaction (the slot
# switch) plus PLATE_FOLLOW_SECONDS of that kill, and at most PLATE_REEL_MAX_SECONDS, so the
# elite fights again unless the player is quick; the ground slam breaks it in PLATE_SLAMS.
PLATE_KIND = "armoured"
PLATE_COMBOS = 2
PLATE_FINISHER = "smg"
PLATE_FINISH_SECONDS = 2.0
PLATE_FOLLOW_SECONDS = 1.0
PLATE_REEL_MAX_SECONDS = 2.0
PLATE_SLAMS = 2

# ---------------------------------------------------------------------------------------------
# Modelling constants (the sim's stand-ins for Roblox and player facts, not game tunables).

ROOT_HEIGHT = 3.0  # R15 root centre when standing: HipHeight 2 + half the 2-stud root
FRAME = 1 / 60  # Heartbeat: projectiles and the fight loop step at this rate
MELEE_FRONT = (2.6, 3.6)  # P2: distance from the root to the crowd's first row
RANGED_FRONT = 20.0  # P2: ranged fire from here...
CONE_FRONT = 8.0  # ...and cone guns from here
FRONT_JITTER = 3.0  # P2: + uniform(0, 3) on the ranged distance
AIM_JITTER = 1.5  # P2: lateral aim offset +-1.5 studs
SURROUND_CLEAR = 2.6  # P2: nobody stands inside the player when surrounded
BOW_SLACK = 0.05  # P2: release / redraw slack per full-charge shot
FIGHT_SECONDS = 90.0
FIGHT_WARMUP_CASTS = 1  # the first cast hits a fresh crowd; intervals are measured after it
FIGHT_SEEDS = (11, 23)
EPSILON = 1e-6

# AbilityService's clamps and slack.
MIN_TICK_SECONDS = 0.05
TICK_EPSILON = 1e-6
MAX_STRIKES_PER_CAST = 120
BUSY_EARLY_SECONDS = 0.05

# HitShapes' Park-Miller generator and clamps.
PM_MODULUS = 2147483647
PM_MULTIPLIER = 48271
MAX_PELLETS = 64
MAX_FAN = 16

# P4 threat: the sim's player, and the engine facts the crowd and a knocked player share.
REACTION_SECONDS = 0.25  # from a tell showing on screen to the player moving
PLAYER_PING = 0.0  # the sim's player has no network, so lag = shooting.originLagSeconds alone
GRAVITY = 196.2  # Workspace.Gravity's default (CrowdService reads the live value)
THREAT_SECONDS = 60.0
THREAT_SEEDS = (11, 23, 37)
START_JITTER = 1.5  # studs around the lobby pad, per seed
DASH_LEAD = 0.10  # a practised player presses dash this long before the impact
FENCE_CLEARANCE = 1.0  # the root stays half a body inside the fence
LAP_FENCE = 15.0  # a walker laps the arena this far inside the fence...
LAP_MIN = 30.0  # ...and never tighter than this radius...
LAP_EASE = 5.0  # ...steering back onto the lap over this many studs
ROW_MAX_COUNT = 10  # RangeService.groupPositions: up to this many stand in one row
GOLDEN_RATIO_FRACTION = 0.6180339887  # CrowdService.separate's split angle for stacked bodies
TIMING_TOLERANCE_DEFAULT = 0.8  # RangeService.DEFAULT_TIMING_TOLERANCE (no Combat.json)
THREAT_EPS = 1e-9
# P4 wave 2: the sim's three new players, and the server's own constants.
THREAT_SET_SECONDS = {"fight": 30.0}  # the big set is watched for less long
HOP_GROUND_SECONDS = 0.1  # a held jump leaves the floor again this long after landing
# A one-way strafer turns back this many studs from where he started, each run in turn (three
# lengths, so his turns never fall in step with a shooter's cycle).
STRAFE_LEGS = (22.0, 30.0, 38.0)
PLAN_MARGIN = 0.4  # studs the reacting player keeps between himself and a shape's edge
PLAN_TICK = 1 / 30  # how finely he follows a shot or a charge when he weighs a move
PLAN_HORIZON = 1.5  # seconds ahead he follows a shot
# A shooter alone is watched this long: a hopper's hits come in runs, as the slinger's cycle
# drifts against the hop, and a shorter watch misreads the rate by a third either way.
ROLE_SECONDS = 300.0
ROLE_SEEDS = (11, 23, 37)
PLATE_GIVE_UP_SECONDS = 30.0  # a weapon that has not broken a plate by then never will
STILL_SPEED = 2.0  # CrowdBrain.STILL_SPEED: a root slower than this, up or down, is still
TRACK_GAP_SECONDS = 0.25  # CrowdBrain.TRACK_GAP_SECONDS: unseen this long, no motion to lead
REACH_EPSILON = 1e-3  # CrowdBrain.REACH_EPSILON
SHOT_AIM_PASSES = 6  # CrowdBrain.ledAim: the flight time is refined this many times
# P4 Stop 2: the player of a boss fight.
BOSS_SECONDS = 240.0  # a boss fight is watched until the boss falls, and no longer than this
CHASE_MARGIN = 1.5  # he closes to this far inside his weapon's reach of the boss
RANGED_STAND = 24.0  # with a ranged weapon he stands no further from the boss than this
ADDS_RANGE = 20.0  # with a ranged weapon he turns to what the boss called once it is this near
HOLD_STEP_SECONDS = 0.45  # holding his ground, he tries steps up to this long before a jump
PLAN_DELAYS = tuple(k / 10 for k in range(1, 16))  # a jump he times: seconds he waits first
MELEE_CAST_FRONT = 10.0  # a melee ability is measured on a boss this far ahead
SLAM_SECONDS = 0.4  # a ground slam (the jump and the dive) keeps his weapon still this long
BOSS_RANGED_SEEDS = (11, 23)  # the ranged rows are information, not bands: two seeds each
BOSS_STAND_SECONDS = 30.0  # the still player is watched this long: his first down is what counts
FACING_STEP = 2 * math.pi / 256  # a locked facing is snapped to the snapshot's yaw byte
HP_STEPS = 255  # CrowdCodec.SnapHp: the health share as the snapshot carries it, rounded up


# ---------------------------------------------------------------------------------------------
# Vector helpers (tuples; y is up, +x is the player's forward).


def v_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def v_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_len(a):
    return math.sqrt(v_dot(a, a))


def v_cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def v_unit(a):
    length = v_len(a)
    return None if length < EPSILON else v_scale(a, 1 / length)


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


# ---------------------------------------------------------------------------------------------
# HitShapes mirror.


def sector_overlap(x, y, reach, rng, half_angle):
    side = abs(y)
    distance = math.sqrt(x * x + side * side)
    if distance > rng + reach:
        return False
    if distance <= reach or half_angle >= math.pi:
        return True
    if math.atan2(side, x) <= half_angle:
        return True
    edge_x, edge_y = math.cos(half_angle), math.sin(half_angle)
    along = clamp(x * edge_x + side * edge_y, 0, rng)
    dx, dy = x - edge_x * along, side - edge_y * along
    return dx * dx + dy * dy <= reach * reach


def hs_arc(origin, forward, rng, arc_degrees, pad, c, r, reach_down=0.0):
    hx, hz = forward[0], forward[2]
    flat = math.hypot(hx, hz)
    if flat < EPSILON:
        return False
    hx, hz = hx / flat, hz / flat
    ox, oy, oz = c[0] - origin[0], c[1] - origin[1], c[2] - origin[2]
    down = max(reach_down, 0)
    if oy > pad + r or oy < -(down + pad + r):
        return False
    along = ox * hx + oz * hz
    across = oz * hx - ox * hz
    return sector_overlap(along, across, r + pad, rng, math.radians(arc_degrees / 2))


def hs_capsule(a, b, radius, pad, c, r):
    segment = v_sub(b, a)
    length_sq = v_dot(segment, segment)
    along = 0 if length_sq < EPSILON else clamp(v_dot(v_sub(c, a), segment) / length_sq, 0, 1)
    closest = v_add(a, v_scale(segment, along))
    return v_len(v_sub(c, closest)) <= radius + pad + r


def hs_cone(origin, forward, rng, half_angle_degrees, pad, c, r):
    axis = v_unit(forward)
    if axis is None:
        return False
    offset = v_sub(c, origin)
    along = v_dot(offset, axis)
    across = v_len(v_sub(offset, v_scale(axis, along)))
    return sector_overlap(along, across, r + pad, rng, math.radians(half_angle_degrees))


def hs_ray(origin, direction, rng, width, pad, c, r):
    """Entry distance along the padded ray, or None for a miss (HitShapes.Ray)."""
    unit = v_unit(direction)
    if unit is None or rng <= 0:
        return None
    reach = width / 2 + pad + r
    offset = v_sub(c, origin)
    along = v_dot(offset, unit)
    nearest = clamp(along, 0, rng)
    miss = v_sub(offset, v_scale(unit, nearest))
    if v_dot(miss, miss) > reach * reach:
        return None
    perpendicular_sq = max(0, v_dot(offset, offset) - along * along)
    entry = along - math.sqrt(max(0, reach * reach - perpendicular_sq))
    return clamp(entry, 0, rng)


def ray_entry(origin, unit, rng, reach, c):
    """hs_ray with the direction already a unit vector and reach = width / 2 + pad + r (the hot
    path: same arithmetic, no allocation)."""
    ox, oy, oz = c[0] - origin[0], c[1] - origin[1], c[2] - origin[2]
    along = ox * unit[0] + oy * unit[1] + oz * unit[2]
    nearest = 0 if along < 0 else rng if along > rng else along
    mx, my, mz = ox - unit[0] * nearest, oy - unit[1] * nearest, oz - unit[2] * nearest
    reach_sq = reach * reach
    if mx * mx + my * my + mz * mz > reach_sq:
        return None
    perpendicular_sq = max(0, ox * ox + oy * oy + oz * oz - along * along)
    entry = along - math.sqrt(max(0, reach_sq - perpendicular_sq))
    return 0 if entry < 0 else rng if entry > rng else entry


def hs_sphere_span(offset, unit, reach):
    """HitShapes' sphereSpan: the span of t inside a sphere of radius `reach` round `offset`
    (centre - origin) along a unit ray, (None, 0) for a miss."""
    along = v_dot(offset, unit)
    perpendicular_sq = max(0, v_dot(offset, offset) - along * along)
    reach_sq = reach * reach
    if perpendicular_sq > reach_sq:
        return None, 0
    half = math.sqrt(reach_sq - perpendicular_sq)
    return along - half, along + half


def hs_first_in(enter, leave, rng):
    """HitShapes' firstIn: the earliest t in [0, rng] of the span, or None."""
    if enter is None or leave < 0 or enter > rng or enter > leave:
        return None
    return max(enter, 0)


def hs_earlier(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return min(a, b)


def hs_ray_upright(origin, direction, rng, width, pad, feet, low, high, radius):
    """HitShapes.RayUpright (L1b-W2-16): the padded ray against every point within `radius` of the
    vertical segment feet + (0, low, 0) .. feet + (0, high, 0); low == high is HitShapes.Ray."""
    if high - low <= 0:
        return hs_ray(origin, direction, rng, width, pad, (feet[0], feet[1] + low, feet[2]), radius)
    unit = v_unit(direction)
    if unit is None or rng <= 0:
        return None
    grown = width / 2 + pad + radius
    bottom = (feet[0], feet[1] + low, feet[2])
    top = (feet[0], feet[1] + high, feet[2])
    best = hs_earlier(hs_first_in(*hs_sphere_span(v_sub(bottom, origin), unit, grown), rng),
                      hs_first_in(*hs_sphere_span(v_sub(top, origin), unit, grown), rng))
    ox, oz = origin[0] - feet[0], origin[2] - feet[2]
    flat_sq = unit[0] * unit[0] + unit[2] * unit[2]
    if flat_sq < EPSILON * EPSILON:
        if ox * ox + oz * oz > grown * grown:
            return best
        round_enter, round_exit = -math.inf, math.inf
    else:
        b = ox * unit[0] + oz * unit[2]
        c = ox * ox + oz * oz - grown * grown
        disc = b * b - flat_sq * c
        if disc < 0:
            return best
        root = math.sqrt(disc)
        round_enter, round_exit = (-b - root) / flat_sq, (-b + root) / flat_sq
    if abs(unit[1]) < EPSILON:
        if origin[1] < bottom[1] or origin[1] > top[1]:
            return best
        slab_enter, slab_exit = -math.inf, math.inf
    else:
        slab_enter = (bottom[1] - origin[1]) / unit[1]
        slab_exit = (top[1] - origin[1]) / unit[1]
        if slab_enter > slab_exit:
            slab_enter, slab_exit = slab_exit, slab_enter
    return hs_earlier(best, hs_first_in(max(round_enter, slab_enter), min(round_exit, slab_exit), rng))


# The crowd's ray rule. "capsule" = HitShapes.CrowdRay (L1b-W2-15/16, the game's since Wave 2);
# "sphere" = the rule before it (the body sphere must be touched, the head counts only for a
# crit), kept so the bow report can set the two side by side. Nothing but that report sets it.
RAY_RULE = "capsule"


def hs_crowd_ray(origin, direction, rng, width, pad, feet, radius, height, head_radius):
    """HitShapes.CrowdRay: (entry, crit). The padded ray hits the body capsule (ground to the
    head's base, or to the old sphere's top when that is higher) or the head sphere; the entry is
    the nearer; it crits when the unpadded ray touches the head. (None, False) for a miss."""
    head = (feet[0], feet[1] + height - head_radius, feet[2])
    if RAY_RULE == "sphere":
        entry = hs_ray(origin, direction, rng, width, pad, (feet[0], feet[1] + height / 2, feet[2]), radius)
        if entry is None:
            return None, False
        return entry, hs_ray(origin, direction, rng, width, 0, head, head_radius) is not None
    top = max(height - 2 * head_radius, height / 2 + radius)
    body = hs_ray_upright(origin, direction, rng, width, pad, feet, radius, top - radius, radius)
    entry = hs_earlier(body, hs_ray(origin, direction, rng, width, pad, head, head_radius))
    if entry is None:
        return None, False
    return entry, hs_ray(origin, direction, rng, width, 0, head, head_radius) is not None


def hs_flat_to_rect(x, z, cx, cz, hx, hz):
    """HitShapes.FlatToRect (L1b-W2-24): the flat distance to a rectangle, 0 inside or on it."""
    dx = max(abs(x - cx) - hx, 0)
    dz = max(abs(z - cz) - hz, 0)
    return math.sqrt(dx * dx + dz * dz)


def distance(a, b):
    dx, dy, dz = a[0] - b[0], a[1] - b[1], a[2] - b[2]
    return math.sqrt(dx * dx + dy * dy + dz * dz)


def pm_seed(seed):
    return math.floor(abs(seed)) % (PM_MODULUS - 1) + 1


def hs_pellets(direction, count, spread_degrees, seed):
    axis = v_unit(direction)
    if axis is None or count <= 0:
        return []
    reference = (0, 1, 0) if abs(axis[1]) < 0.99 else (1, 0, 0)
    right = v_unit(v_cross(axis, reference))
    up = v_cross(right, axis)
    state = pm_seed(seed)
    spread = math.radians(max(0, spread_degrees))
    out = []
    for _ in range(min(math.floor(count), MAX_PELLETS)):
        state = state * PM_MULTIPLIER % PM_MODULUS
        tilt = spread * math.sqrt((state - 1) / (PM_MODULUS - 1))
        state = state * PM_MULTIPLIER % PM_MODULUS
        turn = 2 * math.pi * (state - 1) / (PM_MODULUS - 1)
        sideways = v_add(v_scale(right, math.cos(turn)), v_scale(up, math.sin(turn)))
        out.append(v_unit(v_add(v_scale(axis, math.cos(tilt)), v_scale(sideways, math.sin(tilt)))))
    return out


def hs_fan(direction, count, arc_degrees, seed, jitter_share):
    axis = v_unit(direction)
    total = min(math.floor(count), MAX_FAN)
    if axis is None or total <= 0:
        return []
    reference = (0, 1, 0) if abs(axis[1]) < 0.99 else (1, 0, 0)
    right = v_unit(v_cross(axis, reference))
    arc = math.radians(max(arc_degrees, 0))
    gap = arc / (total - 1) if total > 1 else 0
    jitter_degrees = math.degrees(gap) * max(jitter_share or 0, 0)
    arrows = []
    for index in range(1, total + 1):
        angle = -arc / 2 + gap * (index - 1) if total > 1 else 0
        base = v_unit(v_add(v_scale(axis, math.cos(angle)), v_scale(right, math.sin(angle))))
        nudged = hs_pellets(base, 1, jitter_degrees, seed + index)
        arrows.append(nudged[0] if nudged else base)
    return arrows


def hs_scatter(center, count, spacing, seed):
    """INTERFACES P3: count points evenly spaced on a flat circle of radius spacing, the whole
    ring turned by one Park-Miller angle from seed, no other jitter."""
    total = min(math.floor(count), MAX_FAN)
    if total <= 0:
        return []
    state = pm_seed(seed) * PM_MULTIPLIER % PM_MODULUS
    turn = 2 * math.pi * (state - 1) / (PM_MODULUS - 1)
    return [
        (
            center[0] + math.cos(turn + 2 * math.pi * k / total) * spacing,
            center[1],
            center[2] + math.sin(turn + 2 * math.pi * k / total) * spacing,
        )
        for k in range(total)
    ]


# ---------------------------------------------------------------------------------------------
# Crowd.


class Enemy:
    """A dummy that never moves: body sphere centred height/2 up, head sphere at the top."""

    __slots__ = ("id", "r", "hr", "height", "body_y", "body", "head", "hp", "max_hp", "armor", "alive", "back_at")

    def __init__(self, ident, kind, x, z):
        self.id = ident
        self.r = kind["radius"]
        self.hr = kind["headRadius"]
        self.height = kind["height"]
        self.body_y = kind["height"] / 2
        self.body = (x, self.body_y, z)
        self.head = (x, kind["height"] - kind["headRadius"], z)
        self.max_hp = self.hp = kind["hp"]
        self.armor = max(kind["armor"], 0)
        self.alive = True
        self.back_at = 0.0


class World:
    """A static crowd. mortal = real HP and deaths; otherwise every hit counts in full (the crowd
    DPS basis). respawn = seconds a dead dummy takes to come back (None = never)."""

    def __init__(self, cfg, enemies, mortal, respawn=None):
        self.enemies = enemies
        self.mortal = mortal
        self.respawn = respawn
        self.floor_share = clamp(cfg["crowd"]["armorFloor"], 0, 1)
        self.now = 0.0
        self.on_kill = None
        self.kills = 0
        self.front = None  # distance to the first row (front placements)
        self.dead = []
        # P5 ruling 9: only the HP loss follows the attacker's Armory tier (Armory.DamageScale);
        # armour, heavy hits, plates and interrupts read the tier-1 amount. 1 in the range.
        self.scale = 1.0

    def live(self):
        return [e for e in self.enemies if e.alive]

    def damage(self, enemy, amount):
        """CrowdService.Damage: flat armour with a floor; returns (dealt, killed). P5 ruling 9:
        hpLoss = max(amount - armor, amount * armorFloor) * scale."""
        if not enemy.alive or amount <= 0:
            return 0.0, False
        dealt = max(amount - enemy.armor, amount * self.floor_share) * self.scale
        if not self.mortal:
            return dealt, False
        enemy.hp -= dealt
        if enemy.hp <= 0:
            enemy.hp = 0
            enemy.alive = False
            enemy.back_at = self.now + self.respawn if self.respawn is not None else math.inf
            self.dead.append(enemy)
            self.kills += 1
            if self.on_kill is not None:
                self.on_kill(self.now)
            return dealt, True
        return dealt, False

    def tick(self, now):
        self.now = now
        if self.respawn is None or not self.dead:
            return
        waiting = []
        for e in self.dead:
            if now >= e.back_at:
                e.alive = True
                e.hp = e.max_hp
            else:
                waiting.append(e)
        self.dead = waiting


def pack_positions(side, spacing):
    offset = (side - 1) / 2
    return [(i * spacing, (j - offset) * spacing) for i in range(side) for j in range(side)]


def crowd_side(cfg):
    return max(1, math.floor(math.sqrt(cfg["crowd"]["stressCount"])))


def make_front_world(cfg, spacing, front, rng, mortal=False, respawn=None, kind="fodder"):
    """The crowd's first row `front` studs ahead (+x), lateral phase random. Returns (world, the
    crowd's centre on the floor)."""
    side = crowd_side(cfg)
    lateral = rng.uniform(0, spacing)
    k = cfg["crowd"]["kinds"][kind]
    enemies = [Enemy(n, k, front + x, z + lateral) for n, (x, z) in enumerate(pack_positions(side, spacing))]
    centre = (front + (side - 1) / 2 * spacing, 0.0, lateral)
    world = World(cfg, enemies, mortal, respawn)
    world.front = front
    return world, centre


def make_surround_world(cfg, spacing, rng, mortal=False):
    side = crowd_side(cfg)
    k = cfg["crowd"]["kinds"]["fodder"]
    ox, oz = rng.uniform(0, spacing), rng.uniform(0, spacing)
    half = (side - 1) / 2 * spacing
    enemies = []
    for n, (x, z) in enumerate(pack_positions(side, spacing)):
        px, pz = x - half + ox, z + oz
        if math.hypot(px, pz) >= SURROUND_CLEAR:
            enemies.append(Enemy(n, k, px, pz))
    return World(cfg, enemies, mortal)


def make_single_world(cfg, kind, distance):
    k = cfg["crowd"]["kinds"][kind]
    return World(cfg, [Enemy(0, k, distance, 0.0)], mortal=False)


def chest_height(cfg):
    return cfg["crowd"]["kinds"]["fodder"]["height"] / 2


# ---------------------------------------------------------------------------------------------
# Strikes (RangeService gather -> nearest-first -> cap -> damage), plus P3 chains.


class Tally:
    __slots__ = ("dealt", "hits", "kills")

    def __init__(self):
        self.dealt = 0.0
        self.hits = 0
        self.kills = 0

    def add(self, other):
        self.dealt += other.dealt
        self.hits += other.hits
        self.kills += other.kills


def gather(world, test):
    found = []
    for e in world.enemies:
        if not e.alive:
            continue
        res = test(e)
        if res is not None:
            found.append((res[0], e.id, e, res[1]))
    found.sort(key=lambda f: (f[0], f[1]))
    return found


def cap_of(cap, count):
    return min(int(cap), count) if cap and cap > 0 else count


def hit(world, tally, enemy, amount, seen=None):
    dealt, killed = world.damage(enemy, amount)
    tally.dealt += dealt
    if seen is None or enemy.id not in seen:
        tally.hits += 1
        if seen is not None:
            seen.add(enemy.id)
    if killed:
        tally.kills += 1


def run_chains(world, tally, starts, damage, count, radius, falloff, seen):
    """INTERFACES P3 ruling 8 / Types chainCount: every enemy the strike hit starts a chain that
    jumps `count` times to the nearest live enemy within `radius` (body centre to body centre)
    that this strike has not hit yet, each jump dealing `falloff` times the one before. Chain
    hits never count against cap or pierce."""
    for start in starts:
        current = start
        amount = damage
        for _ in range(max(0, math.floor(count))):
            amount *= falloff
            best, best_d = None, None
            cb = current.body
            for e in world.enemies:
                if not e.alive or e.id in seen:
                    continue
                d = distance(e.body, cb)
                if d <= radius and (best_d is None or d < best_d or (d == best_d and e.id < best.id)):
                    best, best_d = e, d
            if best is None:
                break
            hit(world, tally, best, amount, seen)
            current = best


def strike(world, cfg, spec):
    """RangeService.Strike (AbilityStrikeSpec) and the normal-attack shapes. Returns a Tally."""
    shape = spec["shape"]
    origin = spec["origin"]
    direction = spec["direction"]
    size = spec["size"]
    pad = spec["pad"]
    exclude = spec.get("exclude")
    crit_mult = cfg["shooting"]["critMult"]
    want_crit = spec.get("crit", False)

    if shape == "sphere":
        def test(e):
            d = distance(e.body, origin)
            return (d, False) if d <= size + pad + e.r else None
    elif shape == "arc":
        arc = spec.get("arcDegrees", 360)
        down = spec.get("reachDown", 0.0)

        def test(e):
            ok = hs_arc(origin, direction, size, arc, pad, e.body, e.r, down)
            return (v_len(v_sub(e.body, origin)), False) if ok else None
    elif shape == "capsule":
        tip = spec.get("endPoint") or v_add(origin, v_scale(v_unit(direction), size))
        radius = spec.get("width", 0) / 2

        def test(e):
            ok = hs_capsule(origin, tip, radius, pad, e.body, e.r)
            return (v_len(v_sub(e.body, origin)), False) if ok else None
    elif shape == "cone":
        half = spec.get("arcDegrees", 0) / 2
        width = spec.get("width", 0)
        unit = v_unit(direction)

        def test(e):
            if not hs_cone(origin, unit, size, half, pad, e.body, e.r):
                return None
            crit = want_crit and hs_ray(origin, unit, size, width, 0, e.head, e.hr) is not None
            return (v_len(v_sub(e.body, origin)), crit)
    elif shape == "ray":
        width = spec.get("width", 0)
        unit = v_unit(direction)
        if unit is None or size <= 0:
            return Tally()

        def test(e):
            # WeaponService.rayCandidates: one HitShapes.CrowdRay per body (L1b-W2-15).
            entry, crit = hs_crowd_ray(origin, unit, size, width, pad, (e.body[0], e.body[1] - e.body_y, e.body[2]),
                                       e.r, e.height, e.hr)
            if entry is None:
                return None
            return (entry, want_crit and crit)
    else:
        raise ValueError(f"unknown shape {shape}")

    found = gather(world, test)
    if exclude is not None:
        found = [f for f in found if f[2].id not in exclude]
    limit = cap_of(spec.get("cap", 0), len(found))
    if shape == "ray" and spec.get("pierce") is not None:
        limit = min(limit, max(1, math.floor(spec["pierce"])))
    tally = Tally()
    seen = set()
    starts = []
    for _order, _id, enemy, crit in found[:limit]:
        amount = spec["damage"] * (crit_mult if crit else 1)
        hit(world, tally, enemy, amount, seen)
        starts.append(enemy)
        if exclude is not None:
            exclude.add(enemy.id)
    chain = spec.get("chain")
    if chain is not None and chain["count"] > 0:
        run_chains(world, tally, starts, spec["damage"], chain["count"], chain["radius"], chain["falloff"], seen)
        if exclude is not None:
            exclude.update(seen)
    return tally


# ---------------------------------------------------------------------------------------------
# Projectiles (RangeService stepProjectile for straight flights; gravity drop over these
# distances is under the pad, so flights are straight lines).


def path_candidates(world, origin, direction, reach, width, pad):
    """WeaponService.rayCandidates for a projectile's path: (entry, id, enemy, crit), entry order.
    A projectile crits as a bullet does (its hit carries the candidate's crit)."""
    found = []
    unit = v_unit(direction)
    if unit is None or reach <= 0:
        return found
    for e in world.enemies:
        if not e.alive:
            continue
        entry, crit = hs_crowd_ray(origin, unit, reach, width, pad, (e.body[0], e.body[1] - e.body_y, e.body[2]),
                                   e.r, e.height, e.hr)
        if entry is not None:
            found.append((entry, e.id, e, crit))
    found.sort(key=lambda f: (f[0], f[1]))
    return found


def explode(world, cfg, center, radius, pad, cap, damage):
    return strike(world, cfg, {"shape": "sphere", "origin": center, "direction": (1, 0, 0), "size": radius,
                               "pad": pad, "cap": cap, "damage": damage})


def fly(world, cfg, v, origin, direction, damage, full=False, seed=1):
    """One shot of a projectile variant: a shell bursts at its first contact, an arrow hits along
    its path up to pierce (TOTAL) and the volley cap, a split parent fans after splitDistance or at
    its first contact, and a full charge bursts where the arrow stops. Returns (Tally, impact).

    A shell that touches no body before the crowd's first row bursts on the floor there: the real
    aim ray falls from the camera into the crowd, where the sim's level ray could slip between
    two aligned columns and fly on (the P2 method's fallback, kept)."""
    tally = Tally()
    width = v.get("width", 0) or 0
    pad = v["pad"]
    rng_total = v["range"]
    speed = v.get("projectileSpeed", 0) or 0
    step_len = max(speed * FRAME, EPSILON)

    if v["shape"] == "sphere":
        ground = min(world.front, rng_total) if world.front is not None else rng_total
        cands = path_candidates(world, origin, direction, ground, width, pad)
        if cands:
            impact = v_add(origin, v_scale(direction, cands[0][0]))
        else:
            impact = v_add((origin[0], 0.0, origin[2]), v_scale(direction, ground))
        tally.add(explode(world, cfg, impact, v.get("splashRadius", 0) or 0, pad, v["cap"], damage))
        return tally, impact

    pierce = max(1, math.floor(v.get("pierce", 0) or 0))
    split_count = max(1, min(math.floor(v.get("splitCount", 0) or 0), MAX_FAN))
    volley_hit = set()
    volley_cap = v["cap"]

    def capped():
        return volley_cap > 0 and len(volley_hit) >= volley_cap

    arrows = []  # (start point, direction, path already travelled, first-frame length)
    if split_count > 1:
        split_at = v.get("splitDistance", 0) or 0
        cands = path_candidates(world, origin, direction, min(split_at, rng_total), width, pad)
        contact = cands[0][0] if cands else min(split_at, rng_total)
        point = v_add(origin, v_scale(direction, contact))
        carry = (math.floor(contact / step_len) + 1) * step_len - contact
        for d in hs_fan(direction, split_count, v.get("splitArcDegrees", 0) or 0, seed,
                        cfg["shooting"]["fanJitterShare"]):
            arrows.append((point, d, contact, carry))
    else:
        arrows.append((origin, direction, 0.0, step_len))

    # Every arrow's candidates along its whole remaining path, then claims in server order:
    # frame by frame, arrows in list order, each in entry order.
    claims = []
    for index, (start, d, travelled, first) in enumerate(arrows):
        budget = max(0, rng_total - travelled)
        for entry, eid, enemy, crit in path_candidates(world, start, d, budget, width, pad):
            frame = 0 if entry <= first else 1 + math.floor((entry - first) / step_len)
            claims.append((frame, index, entry, eid, enemy, crit))
    claims.sort(key=lambda c: (c[0], c[1], c[2], c[3]))
    hits_left = [pierce] * len(arrows)
    stop = [None] * len(arrows)
    crit_mult = cfg["shooting"]["critMult"]
    for _frame, index, entry, _eid, enemy, crit in claims:
        if stop[index] is not None or enemy.id in volley_hit:
            continue
        if capped():
            stop[index] = 0.0
            continue
        hit(world, tally, enemy, damage * (crit_mult if crit else 1))
        volley_hit.add(enemy.id)
        hits_left[index] -= 1
        if hits_left[index] <= 0 or capped():
            stop[index] = entry
    blast = v.get("blastRadius", 0) or 0
    if full and blast > 0:
        mult = max(v.get("blastDamageMult", 0) or 0, 0)
        for index, (start, d, travelled, _first) in enumerate(arrows):
            end = stop[index] if stop[index] is not None else max(0, rng_total - travelled)
            tally.add(explode(world, cfg, v_add(start, v_scale(d, end)), blast, pad, 0, damage * mult))
    return tally, None


# ---------------------------------------------------------------------------------------------
# Normal attacks.


def variant_of(cfg, family, key=None):
    fam = cfg["weapons"][family]
    return fam["variants"][key or fam["default"]]


def is_charge(v):
    return (v.get("chargeSeconds", 0) or 0) > 0


def attack_interval(v, rate_mult=1.0):
    if is_charge(v):
        return max(v["chargeSeconds"], 1 / v["rate"]) + BOW_SLACK
    return 1 / (v["rate"] * rate_mult)


def melee_attack(world, cfg, v, step, origin=None, direction=None):
    """resolveMelee from the root, facing +x unless `direction` is given. step is the combo index
    (0-based)."""
    origin = origin or (0.0, ROOT_HEIGHT, 0.0)
    chain = v.get("chain") or [1.0]
    k = step % len(chain)
    arc = v.get("arcDegrees")
    if k == len(chain) - 1 and v.get("finisherArcDegrees") is not None:
        arc = v["finisherArcDegrees"]
    spec = {"shape": v["shape"], "origin": origin, "direction": direction or (1, 0, 0), "size": v["range"],
            "pad": v["pad"],
            "cap": v["cap"], "damage": v["damage"] * chain[k], "arcDegrees": arc if arc is not None else 360,
            "width": v.get("width", 0)}
    return strike(world, cfg, spec)


def ranged_attack(world, cfg, v, aim_z, pierce_override=None, full=True, seed=1, aim_y=None, origin=None,
                  direction=None):
    """resolveRanged: camera ray level at chest height (aim_y), aimed along +x, offset aim_z.
    `origin` and `direction` replace that ray (the threat section aims at a body that moves)."""
    if origin is None:
        origin = (0.0, chest_height(cfg) if aim_y is None else aim_y, aim_z)
    if direction is None:
        direction = (1.0, 0.0, 0.0)
    damage = v["damage"]
    if is_charge(v):
        damage *= 1.0 if full else clamp(v.get("minChargeFraction", 0) or 0, 0, 1)
    if (v.get("projectileSpeed", 0) or 0) > 0:
        return fly(world, cfg, v, origin, direction, damage, full and is_charge(v), seed)[0]
    spec = {"shape": v["shape"], "origin": origin, "direction": direction, "size": v["range"], "pad": v["pad"],
            "cap": v["cap"], "damage": damage, "width": v.get("width", 0) or 0, "crit": True,
            "arcDegrees": v.get("arcDegrees", 0) or 0}
    if v["shape"] == "ray":
        spec["pierce"] = pierce_override if pierce_override is not None else (v.get("pierce", 0) or 0)
        if pierce_override is not None:
            spec["cap"] = 0  # a buffed bullet hits the buff's pierce whatever the variant's cap
        if (v.get("chainCount", 0) or 0) > 0:
            spec["chain"] = {"count": v["chainCount"], "radius": v.get("chainRadius", 0) or 0,
                             "falloff": v.get("chainFalloff", 1) if v.get("chainFalloff") is not None else 1}
    elif v["shape"] == "sphere":
        # A hitscan blast lands where the aim ray stops (only world geometry stops it).
        impact = v_add(origin, v_scale(direction, v["range"]))
        return explode(world, cfg, impact, v.get("splashRadius", 0) or 0, v["pad"], v["cap"], damage)
    return strike(world, cfg, spec)


def single_dps(v, full=True):
    if v["kind"] == "melee":
        chain = v.get("chain") or [1.0]
        return v["damage"] * sum(chain) / len(chain) * v["rate"]
    if is_charge(v):
        if full:
            return v["damage"] / attack_interval(v)
        return v["damage"] * v.get("minChargeFraction", 0) * v["rate"]
    return v["damage"] * v["rate"]


def standard_front(v):
    return CONE_FRONT if v["shape"] == "cone" else RANGED_FRONT


def crowd_dps(cfg, v, spacing, trials, rng, surround=False, full=True):
    """Damage per attack on an immortal crowd x attack rate (the WEAPONS.md crowd DPS)."""
    total = 0.0
    hits = 0.0
    if v["kind"] == "melee":
        chain = v.get("chain") or [1.0]
        for t in range(trials):
            step = t % len(chain)
            if surround:
                world = make_surround_world(cfg, spacing, rng)
            else:
                world, _ = make_front_world(cfg, spacing, rng.uniform(*MELEE_FRONT), rng)
            tally = melee_attack(world, cfg, v, step)
            total += tally.dealt
            hits += tally.hits
        return total / trials * v["rate"], hits / trials
    for _ in range(trials):
        world, _ = make_front_world(cfg, spacing, standard_front(v) + rng.uniform(0, FRONT_JITTER), rng)
        tally = ranged_attack(world, cfg, v, rng.uniform(-AIM_JITTER, AIM_JITTER), full=full,
                              seed=rng.randrange(1, PM_MODULUS))
        total += tally.dealt
        hits += tally.hits
    return total / trials / attack_interval(v) if (full or not is_charge(v)) else total / trials * v["rate"], hits / trials


# ---------------------------------------------------------------------------------------------
# Abilities (INTERFACES "P3 contracts" ability table, as AbilityService builds them).
# plan_ability() returns a Cast: its busy seconds, an optional attack buff (Mag Dump), and its
# strikes as (seconds after the cast, callable(world) -> Tally).


def tick_times(delay, duration, tick):
    """AbilityService.repeatTimes: every tick (at least MIN_TICK_SECONDS) from `delay`, half-open
    over `duration`: ceil(duration / tick - 1e-6) ticks, clamped to 1 .. MAX_STRIKES_PER_CAST."""
    interval = max(tick, MIN_TICK_SECONDS)
    count = int(clamp(math.ceil(duration / interval - TICK_EPSILON), 1, MAX_STRIKES_PER_CAST))
    return [delay + k * interval for k in range(count)]


def count_of(value, minimum):
    """AbilityService.countOf: floor, clamped to minimum .. MAX_STRIKES_PER_CAST."""
    return int(clamp(math.floor(max(value or 0, 0)), minimum, MAX_STRIKES_PER_CAST))


def ground_point(target, cast_range):
    """Ruling 4 on flat ground: the aim point, pulled back to castRange from the root."""
    d = math.hypot(target[0], target[2])
    if d > cast_range and d > EPSILON:
        return (target[0] * cast_range / d, 0.0, target[2] * cast_range / d)
    return (target[0], 0.0, target[2])


class Cast:
    """One planned cast: busy lock, optional buff, and timed strikes."""

    def __init__(self, busy=0.0, buff=None):
        self.busy = busy
        self.buff = buff
        self.events = []

    def at(self, dt, fn):
        self.events.append((dt, fn))


def zone_target(centre, rng, spacing):
    """Where an aimed ability is pointed: inside the crowd, within half a cell of its centre."""
    return (centre[0] + rng.uniform(-spacing / 2, spacing / 2), 0.0, centre[2] + rng.uniform(-spacing / 2, spacing / 2))


def plan_ability(cfg, family, ab, ctx):
    """ctx: centre (the crowd's centre on the floor), aim_z (lateral aim offset), spacing, rng,
    seed (the scatter/fan seed) and, for the boss measurement, ray_origin. The caster stands at
    the origin facing +x: melee abilities from the root, ranged ones from the chest-height aim."""
    aid = ab["id"]
    g = lambda key, default=0: ab.get(key, default) if ab.get(key) is not None else default  # noqa: E731
    rng = ctx["rng"]
    pad, cap, damage = g("pad"), g("cap"), g("damage")
    root = (0.0, ROOT_HEIGHT, 0.0)
    fwd = (1.0, 0.0, 0.0)
    ranged_origin = (0.0, chest_height(cfg), ctx["aim_z"])

    if aid == "whirlwind":
        cast = Cast(busy=g("durationSeconds"))
        speed = cfg["movement"]["walkSpeed"] * g("moveSpeedMult", 1)
        for t in tick_times(0.0, g("durationSeconds"), g("tickSeconds")):
            here = (speed * t, ROOT_HEIGHT, 0.0)  # steered straight into the crowd
            cast.at(t, lambda w, here=here: strike(w, cfg, {"shape": "arc", "origin": here, "direction": fwd,
                                                             "size": g("range"), "arcDegrees": 360, "pad": pad,
                                                             "cap": cap, "damage": damage}))
        return cast
    if aid == "earthquake":
        cast = Cast(busy=g("delaySeconds"))
        floor_point = (0.0, 0.0, 0.0)
        for k in range(1, count_of(g("count"), 0) + 1):
            radius = g("radius") + (k - 1) * g("spacing")
            amount = damage * g("falloff", 1) ** (k - 1)
            cast.at(g("delaySeconds") + (k - 1) * g("tickSeconds"),
                    lambda w, radius=radius, amount=amount: explode(w, cfg, floor_point, radius, pad, cap, amount))
        return cast
    if aid in ("bladeStorm", "arrowRain"):
        cast = Cast()
        point = ground_point(zone_target(ctx["centre"], rng, ctx["spacing"]), g("castRange"))
        radius = g("radius")
        top = (point[0], radius, point[2])
        for t in tick_times(g("delaySeconds"), g("durationSeconds"), g("tickSeconds")):
            cast.at(t, lambda w: strike(w, cfg, {"shape": "capsule", "origin": point, "endPoint": top,
                                                 "direction": (0, 1, 0), "size": radius, "width": 2 * radius,
                                                 "pad": pad, "cap": cap, "damage": damage}))
        return cast
    if aid == "leapSmash":
        cast = Cast(busy=g("delaySeconds"))
        point = ground_point(zone_target(ctx["centre"], rng, ctx["spacing"]), g("castRange"))
        cast.at(g("delaySeconds"), lambda w: explode(w, cfg, point, g("radius"), pad, cap, damage))
        return cast
    if aid == "impaleDash":
        cast = Cast(busy=g("delaySeconds"))
        end = v_add(root, v_scale(fwd, g("range")))
        cast.at(0.0, lambda w: strike(w, cfg, {"shape": "capsule", "origin": root, "endPoint": end, "direction": fwd,
                                               "size": g("range"), "width": g("width"), "pad": pad, "cap": cap,
                                               "damage": damage}))
        return cast
    if aid == "volley":
        cast = Cast()
        v = {"shape": "ray", "range": g("range"), "width": g("width"), "pad": pad, "cap": cap, "damage": damage,
             "pierce": g("pierce"), "projectileSpeed": g("speed"), "gravity": g("gravity"),
             "splitCount": g("count"), "splitDistance": g("spacing"), "splitArcDegrees": g("arcDegrees")}
        seed = ctx["seed"]
        cast.at(RANGED_FRONT / max(g("speed"), EPSILON),
                lambda w: fly(w, cfg, v, ranged_origin, fwd, damage, False, seed)[0])
        return cast
    if aid == "slugBurst":
        cast = Cast(busy=count_of(g("count"), 0) * g("tickSeconds"))
        for k in range(count_of(g("count"), 0)):
            cast.at(k * g("tickSeconds"), lambda w: strike(w, cfg, {"shape": "cone", "origin": ranged_origin,
                                                                    "direction": fwd, "size": g("range"),
                                                                    "arcDegrees": g("arcDegrees"), "pad": pad,
                                                                    "cap": cap, "damage": damage}))
        return cast
    if aid == "overchargedShot":
        cast = Cast(busy=g("delaySeconds"))
        origin = ctx.get("ray_origin", ranged_origin)
        cast.at(g("delaySeconds"), lambda w: strike(w, cfg, {"shape": "ray", "origin": origin, "direction": fwd,
                                                             "size": g("range"), "width": g("width"), "pad": pad,
                                                             "cap": 0, "damage": damage, "crit": True}))
        return cast
    if aid == "magDump":
        # A buff, not strikes: the fight loop and dump_damage() fire the SMG through it.
        return Cast(busy=g("durationSeconds"),
                    buff={"rateMult": g("rateMult", 1), "pierce": g("pierce", 1), "seconds": g("durationSeconds")})
    if aid == "clusterShell":
        cast = Cast()
        seed = ctx["seed"]
        shell = {"shape": "sphere", "range": g("range"), "pad": pad, "cap": cap, "splashRadius": g("radius"),
                 "projectileSpeed": g("speed")}
        state = {}

        def shell_hits(w):
            tally, impact = fly(w, cfg, shell, ranged_origin, fwd, damage, False, seed)
            state["impact"] = impact
            return tally

        flight = RANGED_FRONT / max(g("speed"), EPSILON)
        cast.at(flight, shell_hits)
        for k in range(min(count_of(g("count"), 0), MAX_FAN)):
            def bomblet(w, k=k):
                point = hs_scatter(state["impact"], g("count"), g("spacing"), seed)[k]
                return explode(w, cfg, point, g("blastRadius"), pad, cap, damage * g("blastDamageMult"))
            cast.at(flight + g("delaySeconds"), bomblet)
        return cast
    if aid == "overloadSweep":
        cast = Cast(busy=g("durationSeconds"))
        count = count_of(g("count"), 1)
        arc = g("arcDegrees")
        exclude = set()
        for i in range(count):
            angle = math.radians(-arc / 2 + (i + 0.5) * arc / count)
            direction = (math.cos(angle), 0.0, math.sin(angle))
            cast.at(i * g("durationSeconds") / count,
                    lambda w, direction=direction: strike(w, cfg, {"shape": "arc", "origin": root,
                                                                   "direction": direction, "size": g("range"),
                                                                   "arcDegrees": arc / count, "pad": pad,
                                                                   "cap": cap, "damage": damage,
                                                                   "exclude": exclude}))
        return cast
    if aid == "stormCoil":
        cast = Cast()
        point = ground_point(zone_target(ctx["centre"], rng, ctx["spacing"]), g("castRange"))
        chain = {"count": g("count"), "radius": g("spacing"), "falloff": g("falloff", 1)}
        for t in tick_times(g("delaySeconds"), g("durationSeconds"), g("tickSeconds")):
            cast.at(t, lambda w: strike(w, cfg, {"shape": "sphere", "origin": point, "direction": fwd,
                                                 "size": g("radius"), "pad": pad, "cap": g("targets"),
                                                 "damage": damage, "chain": chain}))
        return cast
    raise ValueError(f"no mechanic for ability {aid}")


def cast_world(cfg, family, spacing, rng, mortal, respawn=None):
    """The crowd a family's ability is cast at, from the family's standard position."""
    v = variant_of(cfg, family)
    if cfg["weapons"][family]["slot"] == "melee":
        front = rng.uniform(*MELEE_FRONT)
    else:
        front = standard_front(v) + rng.uniform(0, FRONT_JITTER)
    return make_front_world(cfg, spacing, front, rng, mortal, respawn)


def run_cast(cfg, family, centre, spacing, rng):
    """Plan one cast at a crowd centred on `centre`, with a random aim offset and scatter seed."""
    ab = cfg["weapons"][family]["ability"]
    ctx = {"centre": centre, "aim_z": rng.uniform(-AIM_JITTER, AIM_JITTER), "spacing": spacing, "rng": rng,
           "seed": rng.randrange(1, PM_MODULUS)}
    return plan_ability(cfg, family, ab, ctx)


def dump_damage(cfg, family, world, rng, buffed=True):
    """Mag Dump: the SMG's own fire for durationSeconds at rate x rateMult, pierce = the buff's,
    no bloom. buffed=False is the same seconds of normal fire (for the net gain)."""
    v = variant_of(cfg, family)
    ab = cfg["weapons"][family]["ability"]
    rate_mult = ab.get("rateMult", 1) if buffed else 1
    pierce = ab.get("pierce", 1) if buffed else None
    shots = math.floor(ab["durationSeconds"] * v["rate"] * rate_mult + 1e-9)
    tally = Tally()
    for _ in range(shots):
        aim_y = world.enemies[0].body_y if len(world.enemies) == 1 else None
        tally.add(ranged_attack(world, cfg, v, rng.uniform(-AIM_JITTER, AIM_JITTER), pierce_override=pierce,
                                aim_y=aim_y))
    return tally


def measure_cast(cfg, family, spacing, trials, seed):
    """One cast on a fresh crowd: (raw damage on immortal fodder, hit events, kills on real fodder)."""
    ab = cfg["weapons"][family]["ability"]
    raw = hits = kills = 0.0
    for trial in range(trials):
        for mortal in (False, True):
            rng = random.Random(seed * 7919 + trial)
            world, centre = cast_world(cfg, family, spacing, rng, mortal)
            if ab["id"] == "magDump":
                tally = dump_damage(cfg, family, world, rng)
            else:
                cast = run_cast(cfg, family, centre, spacing, rng)
                tally = Tally()
                for dt, fn in sorted(cast.events, key=lambda e: e[0]):
                    world.tick(dt)
                    tally.add(fn(world))
            if mortal:
                kills += tally.kills
            else:
                raw += tally.dealt
                hits += tally.hits
    return raw / trials, hits / trials, kills / trials


def measure_boss(cfg, family, head=False):
    """A single-target ability on the boss dummy (RANGED_FRONT away), body or head aim."""
    ab = cfg["weapons"][family]["ability"]
    boss = cfg["crowd"]["kinds"]["boss"]
    rng = random.Random(5)
    world = make_single_world(cfg, "boss", RANGED_FRONT)
    if ab["id"] == "magDump":
        extra = dump_damage(cfg, family, world, rng).dealt - dump_damage(cfg, family, world, rng, False).dealt
        return extra
    aim_y = boss["height"] - boss["headRadius"] if head else boss["height"] / 2
    ctx = {"centre": (RANGED_FRONT, 0, 0), "aim_z": 0.0, "spacing": 6, "rng": rng, "seed": 1,
           "ray_origin": (0.0, aim_y, 0.0)}
    cast = plan_ability(cfg, family, ab, ctx)
    return sum(fn(world).dealt for _, fn in cast.events)


# ---------------------------------------------------------------------------------------------
# The busy-crowd fight: effective cooldown under kill refunds (INTERFACES P3 ruling 2).


def fight(cfg, family, spacing, respawn, seed, seconds=FIGHT_SECONDS):
    """Normal attacks with the family's default variant whenever the busy lock allows, the ability
    cast the moment the server would accept it, every kill refunding it (never below its floor).
    Dummies respawn in place after `respawn` seconds, as the range's dummy sets do. Casts that
    move the caster (Leap Smash, Impale Dash, the walking Whirlwind) resolve at the same geometry
    as measure_cast; normal attacks always come from the family's standard post. Only this
    family's kills refund it here; in play the other slot's kills refund it too. Returns the cast
    times and the kill count."""
    rng = random.Random(seed)
    v = variant_of(cfg, family)
    fam = cfg["weapons"][family]
    ab = fam["ability"]
    scale = cfg["abilities"]["cooldownScale"]
    early = cfg["abilities"]["earlySeconds"]
    base = ab["cooldownSeconds"] * scale
    floor_s = min(ab["minCooldownSeconds"] * scale, base)
    refund = ab["killRefundSeconds"] * scale
    world, centre = cast_world(cfg, family, spacing, rng, True, respawn)
    state = {"ready": 0.0, "floor": 0.0}

    def on_kill(now):
        if state["ready"] > now:
            state["ready"] = max(state["floor"], state["ready"] - refund)

    world.on_kill = on_kill
    queue = []
    counter = 0
    casts = []
    busy_until = 0.0
    buff = None
    buff_until = 0.0
    next_attack = 0.0
    last_attack = -math.inf
    step = 0
    combo_reset = cfg["controls"]["comboResetSeconds"]
    t = 0.0
    while t < seconds:
        world.tick(t)
        while queue and queue[0][0] <= t + 1e-9:
            _, _, fn = heapq.heappop(queue)
            fn(world)
        if t >= state["ready"] - early and t >= busy_until - BUSY_EARLY_SECONDS:
            casts.append(t)
            state["ready"], state["floor"] = t + base, t + floor_s
            cast = run_cast(cfg, family, centre, spacing, rng)
            busy_until = t + cast.busy
            if cast.buff is not None:
                buff, buff_until = cast.buff, t + cast.buff["seconds"]
            for dt, fn in sorted(cast.events, key=lambda e: e[0]):
                if dt <= 0:
                    fn(world)
                else:
                    counter += 1
                    heapq.heappush(queue, (t + dt, counter, fn))
        buffed = buff is not None and t < buff_until
        may_attack = t >= busy_until or (buffed and fam["slot"] == "ranged")
        if may_attack and t >= next_attack:
            if v["kind"] == "melee":
                if t - last_attack > combo_reset:
                    step = 0
                melee_attack(world, cfg, v, step)
                step += 1
                next_attack = t + attack_interval(v)
            else:
                ranged_attack(world, cfg, v, rng.uniform(-AIM_JITTER, AIM_JITTER),
                              pierce_override=buff["pierce"] if buffed else None,
                              seed=rng.randrange(1, PM_MODULUS))
                next_attack = t + attack_interval(v, buff["rateMult"] if buffed else 1.0)
            last_attack = t
        t += FRAME
    return casts, world.kills


def effective_cooldown(cfg, family, spacing, respawn):
    """Mean seconds between casts over FIGHT_SEEDS (after the warm-up cast), and kills per second."""
    intervals = []
    kills = 0.0
    for seed in FIGHT_SEEDS:
        casts, k = fight(cfg, family, spacing, respawn, seed)
        kills += k / FIGHT_SECONDS
        measured = casts[FIGHT_WARMUP_CASTS:]
        intervals += [b - a for a, b in zip(measured, measured[1:])]
    mean = sum(intervals) / len(intervals) if intervals else math.inf
    return mean, kills / len(FIGHT_SEEDS)


# ---------------------------------------------------------------------------------------------
# P4 threat: one player against a dummy set that fights (docs/INTERFACES.md "P4 contracts" and
# its "Wave 2 — roles").
#
# The server's rules, mirrored one by one. Each tag marks the line that applies the rule:
#   [fight]     ruling 13: only a group whose behaviour is `fight` runs its kind's brain;
#   [step]      CrowdService: the crowd moves and decides once per step, at crowd.snapshotHz;
#   [rush]      Types.CrowdKindDef.brain: a rusher closes on its target until its attack's
#               `reach` (CrowdService.seek), and bodies push each other apart
#               (CrowdService.separate); nothing pushes them off the player;
#   [keepAway]  wave 2: a shooter holds bandMin..bandMax from its target on the flat, also while
#               it recovers: in when further, straight back when closer, never off the floor;
#   [planted]   "Rules": a body in windup or attack is planted: separation does not move it, its
#               neighbours give way; a player's knockback still moves it;
#   [windup]    Types.CrowdAttackDef and ruling 21: the windup starts when the target is within
#               `reach` on the flat, and locks the facing (a line's follows until its lock);
#   [cap]       ruling 8 as the wave 2 review amends it: at most the kind's `perPlayer` enemies
#               of one kind are in windup or attack against one player; the others wait in
#               reach and take a freed place (a kind with no `perPlayer` has no cap); a shot in
#               the air holds no place, and a brute holds its place through its charge;
#   [timing]    "State timing": windup (ends at the impact) -> attack (threat.strikeSeconds; a
#               lane's lasts its charge) -> recover (the attack's `recover`) -> approach again;
#   [commit]    the commit rule: the shape is frozen at the impact T and tested, with no pad,
#               against the root at T + lag; an i-frame over any moment of [T, T + lag] voids
#               the hit ("dodged", ruling 7);
#   [height]    ruling 11: a player whose feet are above a ground shape's `height` is missed;
#   [interrupt] rulings 9, 10 and 22: a hit that staggers cancels a `stagger` windup, a hit of
#               crowd.heavyHit or more (before armour) a `heavy` one, but only before the
#               impact's time; a cancelled windup goes to recover;
#   [health]    ruling 4: the hit that would empty the bar puts the player down for
#               player.downSeconds, then up in place and full with player.getUpIframes; a downed
#               player is nobody's target and takes no hit;
#   [regen]     ruling 5: only after player.regenDelay seconds unhurt, at player.regenPerSecond;
#   [knock]     ruling 6: a hit with knockback or launch moves the player and is followed by
#               player.knockIframes; the push is capped at crowd.knockMax and bleeds off at
#               player.knockFriction, in the air as on the ground; fodder hits do not move him;
#   [together]  ruling 18: when a hit that knocks back lands, every other hit on that player
#               still waiting for its decision at that moment, or falling inside the
#               player.knockIframes it opens, is voided ("dodged"): hits decided together do
#               not stack through a knock;
#   [spawn]     "Rules": no windup for threat.spawnGrace after a spawn; a slot does not respawn
#               while a player stands within threat.spawnClear of it;
#   [shot]      wave 2: at T a sphere leaves the body centre for the target's body where it will
#               be after the flight plus that player's lag, which is when the hit is judged
#               (`lead` of the way there, by its motion over the last crowd step; a root that is
#               rising or falling is led down its fall), flies straight at `speed` for `seconds`
#               and is tested in 3D; at most threat.maxShots are in the air or being wound up;
#   [line]      wave 2: the facing follows the target until T - lockSeconds; at T a flat lane
#               `range` long and `width` wide from the body centre hits whoever stands in it,
#               in the air or not;
#   [lob]       wave 2: at T a circle is thrown at the target's floor point; `seconds` later
#               everyone inside it and under `height` is hit and pushed from its centre;
#   [lane]      wave 2: at T the body charges down its locked facing for `range` at `speed`
#               (shorter at the arena's edge); nothing cancels or moves it meanwhile; it hits a
#               player once, when its centre passes within width / 2 of them on the flat;
#   [plate]     wave 2: while the plate lasts a hit under crowd.heavyHit is blocked and does
#               nothing; a heavy one comes off the plate (the excess is lost) and otherwise acts
#               as any hit; when the plate empties the body reels for crowd.plateBreakSeconds;
#   [choice]    Stop 2: a body with several attacks takes, among those off `cooldown` (which
#               runs from the attack's impact), in `reach` and allowed in its phase, the one it
#               used longest ago, and never the same one twice running when another is ready;
#   [enrage]    Stop 2: at health share <= enrage.at, at the next moment it is neither winding
#               up nor attacking, for good: windups x windupScale, recovers x recoverScale,
#               `enraged` attacks unlock, and up to `chain` attacks follow each other with no
#               recover between (the last recovers, scaled);
#   [ring]      Stop 2: at T a front leaves the body's feet and grows to `radius` at `speed`; a
#               player is hit once, when the front, `width` thick, passes him with his feet
#               under `height`; he is pushed outward;
#   [summon]    Stop 2: at T `count` bodies of kind `summon` rise evenly on a circle of `radius`
#               round the caller, inside the arena and within crowd.maxAlive; they fight, obey
#               threat.spawnGrace, never respawn and are removed when their caller dies;
#   [barrage]   Stop 2: a lob with `count` throws that many circles at once, the first on the
#               target and the rest scattered within `spread` of them; each is an ordinary lob.
#   [uses]      Stop 3: an attack with `uses` lands at most that often in its body's life,
#               counted at the impact; a `calm` attack is only chosen before the enraged phase
#               (the mirror of `enraged`); an attack the body may no longer use stops counting
#               toward the reach it walks to, and with none left it stands;
#   [guarded]   Stop 3: the plate of a `guarded` kind takes nothing, heavy or not, from its
#               spawn until its guard (what it summoned) has been called and is dead; only the
#               plate is guarded. Enraged, a kind with enrage.brain moves by that brain. A
#               plate break reels every body, whatever its knockbackMult.
#
# Where the contract leaves a choice, the sim follows the code as written (CrowdBrain,
# ThreatField, VitalsService, MovementController.ApplyKnock) and says so at the line: the lunge
# is a capsule whose tip is `range` from the body centre and the player is a point; a place
# is held from the windup's start to the attack's end; an impact keeps its exact time and is
# handled on the first step at or after it; a locked facing is snapped to 1/256 of a turn; a
# shot is aimed in six passes from the target's motion over the last step; a shot and a charge
# are swept over each crowd step against the root as it is at that step; a voided shot flies
# on. One thing is the sim's own: a freed place goes to the lowest id of its kind waiting in
# reach (the server takes its records in list order). Stop 2 was written before the server's
# report and then set by it: the choice is CrowdBrain.choose's; the phase is asked when an
# attack ends and (since Stop 3) in every step outside a windup and an attack; a ring's
# `attack` state lasts threat.strikeSeconds and its band, `width` wide round the front, is
# judged as ThreatField.stepRing judges it; a chained
# attack begins on the step the one before it ends, aimed from where a charge set the body
# down; a call tops up; a barrage falls at even angles from one random turn and a player takes
# one circle of it; what is called rises on the caller's facing, half a step off it for an even
# count (Stop 3: before, the sim's summons rose from angle 0). One more thing is the sim's own:
# a body refused its place is not offered its next choice in the same step.


def armory_max_hp(armory, tier):
    """Armory.MaxHp with both slots at `tier` and no Ascension; tier 0 = the starter weapons."""
    total = armory["baseHp"]
    for slot in ("melee", "ranged"):
        slot_def = armory["slots"][slot]
        total += slot_def["starter"]["hp"] if tier <= 0 else slot_def["tiers"][tier - 1]["hp"]
    return total


def timing_tolerance():
    """RangeService.timingTolerance: Combat.json player.comboTimingTolerance, or its default."""
    try:
        return load_config(COMBAT_PATH)["player"]["comboTimingTolerance"]
    except (FileNotFoundError, KeyError):
        return TIMING_TOLERANCE_DEFAULT


def load_arena(name):
    """The numbers of Layouts/Arenas/<name>.luau the threat needs: the floor, the fence height
    and the lobby pad. The layout is a data file of plain numbers and named constants; they are
    read here so that none is copied into the simulator."""
    path = LAYOUT_DIR / f"{name}.luau"
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise SystemExit(f"sim_range: no arena layout at {path}") from None
    names = {m.group(1): float(m.group(2))
             for m in re.finditer(r"^local ([A-Z][A-Z0-9_]*) = (-?\d+(?:\.\d+)?)\s*$", text, re.MULTILINE)}

    def read(pattern, what):
        match = re.search(pattern, text)
        if match is None:
            raise SystemExit(f"sim_range: cannot read {what} from {path}")
        try:
            return [names[token] if token in names else float(token) for token in match.groups()]
        except ValueError:
            raise SystemExit(f"sim_range: {what} in {path} is not a number or a named constant") from None

    size = read(r"size = \{ x = ([\w.-]+), z = ([\w.-]+) \}", "the floor size")
    wall = read(r"wall = \{ height = ([\w.-]+),", "the fence height")
    pad = read(r"lobbyPad = \{ x = ([\w.-]+), z = ([\w.-]+) \}", "the lobby pad")
    return {"half": (size[0] / 2, size[1] / 2), "wall": wall[0], "pad": (pad[0], pad[1])}


def launch_airtime(launch):
    """Seconds in the air for a launch whose apex is `launch` studs (CrowdService.launchSpeed)."""
    return 2 * math.sqrt(2 * launch / GRAVITY) if launch > 0 else 0.0


def jump_clear(jump_height, height):
    """Seconds after take-off between which the feet of a `jump_height` jump are above `height`
    ([height]); None when the jump never clears it."""
    if height >= jump_height:
        return None
    speed = math.sqrt(2 * GRAVITY * jump_height)
    spread = math.sqrt(speed * speed - 2 * GRAVITY * height)
    return (speed - spread) / GRAVITY, (speed + spread) / GRAVITY


def group_positions(group, half, radius):
    """RangeService.groupPositions: up to ROW_MAX_COUNT stand in one row along x, more in a
    packed square grid, centred on `at` and clamped inside the floor."""
    count = int(group["count"])
    limit_x, limit_z = max(0.0, half[0] - radius), max(0.0, half[1] - radius)
    columns = count if count <= ROW_MAX_COUNT else math.ceil(math.sqrt(count))
    rows = math.ceil(count / max(columns, 1))
    positions = []
    for index in range(count):
        x = group["at"][0] + (index % columns - (columns - 1) / 2) * group["spacing"]
        z = group["at"][1] + (index // columns - (rows - 1) / 2) * group["spacing"]
        positions.append((clamp(x, -limit_x, limit_x), clamp(z, -limit_z, limit_z)))
    return positions


def fight_groups(cfg, set_name, only=None):
    """[fight] The groups of a set that fight: behaviour `fight` and a kind with a brain and an
    attack. Every other group is a dummy and never attacks. `only` keeps one kind."""
    kinds = cfg["crowd"]["kinds"]
    return [(group, kinds[group["kind"]]) for group in cfg["dummySets"].get(set_name, [])
            if group["behaviour"] == "fight" and kinds[group["kind"]].get("brain")
            and kinds[group["kind"]].get("attacks") and only in (None, group["kind"])]


def shape_contains(attack, ex, ez, face, px, pz, aim=None):
    """[commit] Is the root (px, pz) inside the shape frozen at (ex, ez) facing `face`, seen from
    above? No pad, and the player is a point (VitalsService.inPlan).
    lunge = a capsule `width` wide whose tip is `range` from the body centre; arc = a sector of
    radius `range` and `arcDegrees`; line = a rectangle `range` long and `width` wide with square
    ends (HitShapes.Lane); lob = the circle of `radius` round the point it was thrown at."""
    shape = attack["shape"]
    if shape == "lob":
        dx, dz = px - aim[0], pz - aim[1]
        return dx * dx + dz * dz <= (attack.get("radius") or 0) ** 2
    dx, dz = px - ex, pz - ez
    along = dx * face[0] + dz * face[1]
    across = dz * face[0] - dx * face[1]
    length = attack.get("range") or 0
    if shape == "lunge":
        radius = (attack.get("width") or 0) / 2
        gap = along - clamp(along, 0, max(length - radius, 0))
        return gap * gap + across * across <= radius * radius
    if shape == "arc":
        half_angle = math.radians(min(attack.get("arcDegrees") or 360, 360) / 2)
        return sector_overlap(along, across, 0.0, length, half_angle)
    if shape == "line":
        return 0 <= along <= length and abs(across) <= (attack.get("width") or 0) / 2
    raise ValueError(f"no threat mirror for the attack shape {shape}")


def worst_exit(attack):
    """The farthest a player in the shape can be from its edge when its tell shows: the most he
    ever has to walk to leave it.
    lunge: on the axis, half the width to either side.
    arc: on the axis at distance d the way out is min(range - d, d x sin(half angle)) (the far
    edge, or the nearer side; past a half-turn the side is the body itself), largest where the
    two meet or at d = reach.
    line and lane: half the width, from the axis. lob: the radius, from the centre."""
    shape = attack["shape"]
    length = attack.get("range") or 0
    if shape in ("lunge", "line", "lane"):
        return (attack.get("width") or 0) / 2
    if shape == "lob":
        return attack.get("radius") or 0
    if shape == "arc":
        half_angle = math.radians(min(attack.get("arcDegrees") or 360, 360) / 2)
        if half_angle >= math.pi:
            return length
        side = math.sin(half_angle) if half_angle < math.pi / 2 else 1.0
        start = min(attack["reach"], length)
        meet = length / (1 + side)
        return length * side / (1 + side) if meet <= start else min(length - start, start * side)
    raise ValueError(f"no threat mirror for the attack shape {shape}")


def longest_way_out(attack):
    """The longest straight line a player can walk inside the shape from a start within `reach`:
    walking on that far, in any direction, leaves it.
    lunge: corner to corner of the capsule's box, from `reach` out to its rounded back.
    arc: from one side at `reach` to the far corner of the other side (law of cosines); past a
    half-turn, straight through the body to the far edge."""
    length = attack.get("range") or 0
    start = min(attack["reach"], length)
    if attack["shape"] == "lunge":
        width = attack.get("width") or 0
        return math.hypot(start + width / 2, width)
    if attack["shape"] == "arc":
        arc = math.radians(min(attack.get("arcDegrees") or 360, 360))
        if arc >= math.pi:
            return start + length
        return math.sqrt(start * start + length * length - 2 * start * length * math.cos(arc))
    raise ValueError(f"no threat mirror for the attack shape {attack['shape']}")


def knock_facts(attack, knockback, friction, iframes):
    """The knock as MovementController.ApplyKnock applies it (`knockback` already capped at
    crowd.knockMax): the speed bleeds off at player.knockFriction from the first moment, so it
    lasts knockback / friction and carries knockback^2 / (2 x friction). `carried` = how far he
    is when the i-frames end. `clears` (arcs only) = the widest angle (degrees round the player,
    from the attacker) at which a second enemy of the kind, standing at its `reach` and aimed at
    where he stood, no longer holds him once he has been carried that far: 180 = no second
    attack of this kind can chain, whatever the angle."""
    if knockback <= 0 or friction <= 0:
        return {"slide": 0.0, "throw": 0.0, "carried": 0.0, "clears": None}
    slide = knockback / friction
    within = min(slide, iframes)
    carried = knockback * within - friction * within * within / 2
    clears = None
    if attack["shape"] == "arc":
        clears = 180
        for degrees in range(0, 181):
            turn = math.radians(degrees)
            # The player stood at the origin and is carried along +x; the first attacker is at -x.
            ex, ez = -attack["reach"] * math.cos(turn), attack["reach"] * math.sin(turn)
            face = (math.cos(turn), -math.sin(turn))
            if shape_contains(attack, ex, ez, face, carried, 0.0):
                clears = degrees - 1
                break
    return {"slide": slide, "throw": knockback * knockback / (2 * friction), "carried": carried, "clears": clears}


def pack_radius(count, radius):
    """Radius of `count` bodies of `radius` packed as tightly as CrowdService.separate lets them
    settle (hexagonal packing: 2 x sqrt(3) x radius^2 of floor each)."""
    return math.sqrt(count * 2 * math.sqrt(3) * radius * radius / math.pi)


def snap_face(face):
    """A locked facing as the server keeps it: snapped to 1/256 of a turn, the step the
    snapshot's yaw byte carries, so every client draws the shape the server judges."""
    turn = round(math.atan2(face[1], face[0]) / FACING_STEP) * FACING_STEP
    return math.cos(turn), math.sin(turn)


def point_segment_gap(p, a, b):
    """Distance from the point p to the segment a-b (tuples of any one length)."""
    ab = [y - x for x, y in zip(a, b)]
    ap = [y - x for x, y in zip(a, p)]
    span = sum(c * c for c in ab)
    along = clamp(sum(u * v for u, v in zip(ap, ab)) / span, 0, 1) if span > EPSILON else 0.0
    return math.sqrt(sum((u - along * v) ** 2 for u, v in zip(ap, ab)))


def shot_aim(origin, here, track, stand_y, speed, lead, lag):
    """[shot] CrowdBrain.ledAim: the target's body where it will be when the shot is judged
    against it, `lead` of the way from where it is (in all three axes). That moment is the
    flight plus `lag`: the commit rule tests the root now against where the shot was `lag` ago.
    The flight time depends on the point aimed at, so the aim takes SHOT_AIM_PASSES passes.
    CrowdBrain.ahead: straight on the flat, at the height the root is at; only a root that is
    rising or falling (not resting) is led down a fall, as far as the surface it last rested
    on, or its standing height once it is below that. `track` = the brain's view of him
    (ThreatRun.crowd_step)."""
    if speed <= 0 or lead <= 0:
        return here
    velocity = track["velocity"]
    aim = here
    for _ in range(SHOT_AIM_PASSES):
        on = distance(aim, origin) / speed + lag
        y = here[1]
        if not track["resting"]:
            floor = track["restY"] if y >= track["restY"] else stand_y
            y = max(floor, y + velocity[1] * on - GRAVITY * on * on / 2)
        ahead = (here[0] + velocity[0] * on, y, here[2] + velocity[2] * on)
        aim = tuple(h + (a - h) * lead for h, a in zip(here, ahead))
    return aim


def boss_cast(cfg, family, kind_name):
    """One cast of a family's ability at a lone body of kind `kind_name`, aimed at it from the
    family's own distance: (damage dealt, busy lock, cooldown). Mag Dump is a buff on the fire
    that goes on anyway: only what it adds counts, and it locks nothing."""
    ab = cfg["weapons"][family]["ability"]
    kind = cfg["crowd"]["kinds"][kind_name]
    melee = cfg["weapons"][family]["slot"] == "melee"
    front = MELEE_CAST_FRONT if melee else RANGED_FRONT
    world = make_single_world(cfg, kind_name, front)
    rng = random.Random(5)
    cooldown = ab["cooldownSeconds"] * cfg["abilities"]["cooldownScale"]
    if ab["id"] == "magDump":
        extra = dump_damage(cfg, family, world, rng).dealt - dump_damage(cfg, family, world, rng, False).dealt
        return extra, 0.0, cooldown
    ctx = {"centre": (front, 0.0, 0.0), "aim_z": 0.0, "spacing": 0.0, "rng": rng, "seed": 1,
           "ray_origin": (0.0, kind["height"] / 2, 0.0)}
    cast = plan_ability(cfg, family, ab, ctx)
    return sum(fn(world).dealt for _dt, fn in sorted(cast.events, key=lambda e: e[0])), cast.busy, cooldown


class Fighter(Enemy):
    """A crowd enemy whose group fights: the Enemy that strike() hits, plus the brain's state.
    (x, z) are its feet on the floor. States: approach, windup, attack, recover."""

    def __init__(self, ident, name, kind, x, z, respawn):
        super().__init__(ident, kind, x, z)
        self.name = name
        # [choice] A kind may have several attacks; `attack` is the one chosen last.
        self.attacks = kind["attacks"]
        self.attack = self.attacks[0]
        self.shape = self.attack["shape"]
        self.kind = kind
        self.enrage = kind.get("enrage")  # [enrage]
        self.boss = bool(kind.get("boss"))
        self.guarded = bool(kind.get("guarded"))  # [guarded]
        self.summoner = None  # [summon] the body that called this one
        self.slot = 0  # [summon] which of its caller's even places it rose on
        self.enraged = False
        self.landed = [0] * len(self.attacks)
        self.pace()
        self.speed = max(kind["speed"], 0)
        self.mult = max(kind["knockbackMult"], 0)
        self.head_y = kind["height"] - kind["headRadius"]
        self.max_plate = max(kind.get("plate") or 0, 0)
        # [cap] Its kind's places against one player; no key = no cap.
        self.places = math.floor(kind["perPlayer"]) if kind.get("perPlayer") is not None else math.inf
        self.home = (x, z)
        self.respawn = respawn
        self.respawn_at = math.inf
        # L1b: the index of the crowd floor it stands on (None = the one floor of a range set or
        # of a mission), the camp-group record of a resident, and where a resident that is not
        # fighting walks this step: (goal x, goal z, speed, stop distance), or None.
        self.floor = None
        self.resident = None
        self.idle = None
        # L1b-W2-10: a dormant body (its resting group far from every player) is not integrated,
        # not separated and not clamped; it stays where it stood.
        self.dormant = False
        self.spawn(0.0)

    def spawn(self, now):
        self.x, self.z = self.home
        self.alive = True
        self.hp = self.max_hp
        self.plate = self.max_plate  # [plate] a respawned elite is plated again
        self.enraged = False
        self.called = False  # [guarded] has it called its guard yet?
        self.landed = [0] * len(self.attacks)  # [uses] how often each attack has come to its impact
        self.pace()
        self.state = "approach"
        self.started = self.until = 0.0
        self.face = (0.0, 1.0)
        self.locked = False
        self.charge = None
        self.kx = self.kz = 0.0
        self.stagger_until = self.air_until = 0.0
        self.spawned_at = now
        self.respawn_at = math.inf
        # [choice] [enrage] Per attack: when it is off cooldown, and when it was last begun.
        self.index = 0
        self.attack = self.attacks[0]
        self.shape = self.attack["shape"]
        self.ready = [0.0] * len(self.attacks)
        self.used = [-math.inf] * len(self.attacks)
        self.last = None
        self.enraged_at = None
        self.chain_left = 0
        self.place()

    def place(self):
        self.body = (self.x, self.body_y, self.z)
        self.head = (self.x, self.head_y, self.z)

    def usable(self, index):
        """[choice] CrowdBrain.usable: may the body still use this attack at all? Not an
        `enraged` one before the second phase, not a `calm` one in it, and not one that has
        landed its `uses` ([uses] counted at the impact, in this body's life)."""
        attack = self.attacks[index]
        if attack.get("calm") if self.enraged else attack.get("enraged"):
            return False
        return attack.get("uses") is None or self.landed[index] < math.floor(attack["uses"])

    def pace(self):
        """The brain, the reach and the band of the body's phase. [enrage] An enraged body takes
        enrage.brain when it has one. [windup] Ruling 21: `reach` is measured on the flat, and a
        body closes to the shortest reach among the attacks it may still use (with none left it
        stands). [keepAway] CrowdBrain.Think: the band never holds it so far out that nothing
        reaches."""
        kind = self.kind
        self.brain = (self.enrage.get("brain") if self.enraged and self.enrage else None) or kind["brain"]
        self.reach = min((a["reach"] for i, a in enumerate(self.attacks) if self.usable(i)), default=math.inf)
        self.band_max = max(min(kind.get("bandMax") or self.reach, self.reach), 0)
        self.band_min = min(max(kind.get("bandMin") or 0, 0), self.band_max)

    def choose(self, now, gap):
        """[choice] CrowdBrain.choose: among the attacks allowed in this phase, in reach and off
        cooldown, the one whose last impact is oldest (never used = oldest; the list's order
        breaks a tie). The attack of the last windup is taken only when no other is ready.
        None when nothing is."""
        best, best_at, again = None, math.inf, False
        for i, a in enumerate(self.attacks):
            if not self.usable(i) or gap > a["reach"] + REACH_EPSILON:
                continue
            if now < self.ready[i] - THREAT_EPS:
                continue
            if i == self.last:
                again = True
            elif self.used[i] < best_at:
                best, best_at = i, self.used[i]
        return self.last if best is None and again else best

    def rage(self, now):
        """[enrage] CrowdBrain.enrage: asked when an attack ends and in every step the body is
        outside a windup and an attack, never inside one; for good. The share is the one the
        snapshot carries, in 1/255 steps rounded up. The body then closes to the shortest reach
        of the attacks its phase allows, by enrage.brain when the kind names one."""
        if self.enrage is None or self.enraged or self.plate > 0:
            return
        if math.ceil(self.hp / max(self.max_hp, 1) * HP_STEPS) / HP_STEPS <= self.enrage["at"]:
            self.enraged = True
            self.enraged_at = now
            self.pace()

    def begin(self, index, now):
        """[windup] The windup of attack `index` starts; [enrage] an enraged body's is scaled."""
        self.index = index
        self.attack = self.attacks[index]
        self.shape = self.attack["shape"]
        self.last = index
        self.state = "windup"
        self.started = now
        self.until = now + self.attack["windup"] * (self.enrage["windupScale"] if self.enraged else 1)
        self.locked = False

    def recover_seconds(self):
        """[timing] The recover of the attack under way; [enrage] an enraged body's is scaled."""
        return self.attack["recover"] * (self.enrage["recoverScale"] if self.enraged else 1)


class ThreatWorld(World):
    """A World whose hits also do what CrowdService.Damage does to a living enemy (shove, launch,
    stagger), apply the interrupt rules and know the plate. `blow` = (x, z, knockback, launch)
    of the strike being resolved; the shove points from there to the enemy. `owed` = called for
    an enemy killed after its impact's time, whose blow still lands (ruling 22)."""

    def __init__(self, cfg, fighters):
        super().__init__(cfg, fighters, mortal=True)
        crowd = cfg["crowd"]
        self.heavy = crowd["heavyHit"]
        self.stagger = max(crowd["staggerSeconds"], 0)
        self.knock_max = max(crowd["knockMax"], 0)
        self.reel = max(crowd["plateBreakSeconds"], 0)
        self.blow = None
        self.owed = None
        self.fell = None  # called with every body that dies
        self.cancelled = self.blocked = self.broken = 0
        self.warded = 0  # hits a living guard kept off its boss's plate
        self.broke_at = None  # when a boss's plate broke

    def damage(self, enemy, amount):
        if not enemy.alive or amount <= 0:
            return 0.0, False
        now = self.now
        if enemy.plate > 0:  # [plate]
            if self.wards(enemy):
                self.blocked += 1  # [guarded] its plate takes nothing, heavy or not
                self.warded += 1
                return 0.0, False
            if amount < self.heavy:
                self.blocked += 1
                return 0.0, False
            dealt = min(amount, enemy.plate)
            enemy.plate -= dealt
            self.react(enemy, amount, now)
            if enemy.plate <= 0:
                self.broken += 1
                if enemy.boss and self.broke_at is None:
                    self.broke_at = now
                if not (enemy.charge is not None and enemy.state == "attack"):
                    # The break (CrowdService.Damage, Stop 3): it reels for max(its stagger,
                    # plateBreakSeconds) whatever its knockbackMult; only a charge under way
                    # runs on. A windup it was in is cancelled whatever its `interrupt` (one
                    # whose impact time has come still lands) and recovers in full from here.
                    enemy.stagger_until = max(enemy.stagger_until, now + self.reel)
                    if enemy.state == "windup" and now < enemy.until - THREAT_EPS:
                        enemy.state = "recover"
                        enemy.until = now + enemy.recover_seconds()
                        self.cancelled += 1
            return dealt, False
        dealt, killed = super().damage(enemy, amount)
        if killed:
            enemy.respawn_at = now + enemy.respawn
            if self.fell is not None:
                self.fell(enemy)
            if enemy.state == "windup" and now >= enemy.until - THREAT_EPS and self.owed is not None:
                self.owed(enemy)  # [interrupt] ruling 22: a due impact is never lost
            return dealt, killed
        self.react(enemy, amount, now)
        return dealt, killed

    def guard_of(self, enemy):
        """[guarded] Does any body this one called still live?"""
        return any(e.alive and e.summoner is enemy for e in self.enemies)

    def wards(self, enemy):
        """[guarded] Is the plate of a `guarded` body kept? From the moment it spawns until its
        guard has been called and is dead (the lead's ruling, Stop 3). Only the plate is
        guarded, never health."""
        return enemy.guarded and enemy.plate > 0 and (not enemy.called or self.guard_of(enemy))

    def react(self, enemy, amount, now):
        """Shove, launch, stagger and the interrupt of a hit the enemy survives."""
        if enemy.charge is not None and enemy.state == "attack":
            return  # [lane] nothing cancels or moves a charging body; the hit still hurt it
        mult = enemy.mult
        if self.blow is not None and mult > 0:
            ox, oz, knockback, launch = self.blow
            dx, dz = enemy.x - ox, enemy.z - oz
            gap = math.hypot(dx, dz)
            if knockback > 0 and gap > EPSILON:
                enemy.kx += dx / gap * knockback * mult
                enemy.kz += dz / gap * knockback * mult
                speed = math.hypot(enemy.kx, enemy.kz)
                if speed > self.knock_max:
                    scale = self.knock_max / speed if self.knock_max > 0 else 0.0
                    enemy.kx, enemy.kz = enemy.kx * scale, enemy.kz * scale
            if launch > 0:
                enemy.air_until = max(enemy.air_until, now + launch_airtime(launch * mult))
        staggers = self.stagger * mult > 0
        if staggers:
            enemy.stagger_until = max(enemy.stagger_until, now + self.stagger * mult)
        if enemy.state == "windup" and now < enemy.until - THREAT_EPS:  # [interrupt]
            rule = enemy.attack["interrupt"]
            if (rule == "stagger" and staggers) or (rule == "heavy" and amount >= self.heavy):
                enemy.state = "recover"
                enemy.until = now + enemy.recover_seconds()
                self.cancelled += 1


# What the sim's player does.
#   walk    laps the arena at walk speed (every enemy is slower, so this is kiting);
#   wake    he does nothing until his health is at or under this share (caught, then he acts);
#   fight   swings the default melee family at the nearest enemy in reach;
#   evade   (wave 1) when a lunge or an arc he has had time to see is about to land on him, he
#           dashes through it if the dash is ready, or else walks out of it if his sword cannot
#           cancel it;
#   hop     holds jump on the spot;
#   strafe  walks one way, turning back only at the end of a long run (STRAFE_LEGS);
#   react   answers every tell he has had time to see with the cheapest move that works: a step,
#           then a jump, then a dash (ThreatRun.replan);
#   boss    (Stop 2) in a boss fight he strikes what the boss called while it is on him, then
#           the boss, with the weapon of his row, and its ability when the row has it;
#   chase   with nothing to answer he walks back to where his weapon reaches the boss;
#   hold    he holds his ground: a short step, then a jump he times, before a long walk or a dash;
#   heed    the only tells he answers.
THREAT_POLICIES = {
    "stand": {"label": "stands still"},
    "walk": {"label": "walks away", "walk": True},
    "break": {"label": "stands to half health, then walks", "walk": True, "wake": 0.5},
    "fight": {"label": "fights, dashes when threatened", "fight": True, "evade": True},
    "turn": {"label": "stands to half health, then fights", "fight": True, "evade": True, "wake": 0.5},
    "hop": {"label": "hops on the spot", "hop": True},
    "strafe": {"label": "strafes one way", "strafe": True},
    "react": {"label": "reacts to every tell", "react": True},
    "brawl": {"label": "swings, never dodges", "fight": True},
    "duel": {"label": "swings and reacts", "fight": True, "react": True},
    # Stop 2, the boss fight. boss = he strikes what the boss called while it is on him, then
    # the boss; chase = he closes in when nothing threatens; hold = he holds his ground (a timed
    # jump before a long walk); heed = the only tells he answers; weapon and abilities are set
    # per row (boss_rows).
    "siege": {"label": "jumps the ring, sidesteps the charge", "fight": True, "react": True, "boss": True,
              "chase": True, "hold": True, "heed": ("ring", "lane")},
    "slay": {"label": "reacts to every tell, attacks", "fight": True, "react": True, "boss": True, "chase": True,
             "hold": True},
    # Stop 3. adds = "never": he strikes the boss and nothing else. (While a guard keeps a boss's
    # plate, every other boss-fight player goes for the guard first.)
    "storm": {"label": "ignores the guard, chases him", "fight": True, "boss": True, "chase": True,
              "adds": "never"},
    "stalk": {"label": "the same, and reacts to every tell", "fight": True, "react": True, "boss": True,
              "chase": True, "hold": True, "adds": "never"},
}
# The rows of the threat table: each set with the players sent into it.
THREAT_PLAN = (
    ("fodderRush", ("stand", "walk", "break", "fight", "turn", "hop")),
    ("elites", ("stand", "walk", "break", "fight", "turn", "react", "brawl")),
    ("shooters", ("stand", "walk", "hop", "strafe", "react", "brawl")),
    ("brutes", ("stand", "walk", "hop", "strafe", "react", "brawl")),
    ("fight", ("stand", "walk", "hop", "strafe", "react", "brawl", "duel")),
)
# The reacting player's moves, cheapest first: stand, a step of one of these lengths (seconds of
# walking), a jump, a jump with a step, a dash.
PLAN_STEPS = (0.1, 0.2, 0.3, 0.45, 0.7, 1.0)
PLAN_DIRECTIONS = tuple((math.cos(2 * math.pi * k / 12), math.sin(2 * math.pi * k / 12)) for k in range(12))
PLAN_PROBES = ((0.0, 0.0), (PLAN_MARGIN, 0.0), (-PLAN_MARGIN, 0.0), (0.0, PLAN_MARGIN), (0.0, -PLAN_MARGIN))


class ThreatRun:
    """One player against one dummy set for `seconds`, under one policy. Time starts when the set
    loads, with the player on the lobby pad. `only` keeps one kind of the set and `heads` the
    first so many of them (a role on its own); `immortal` counts every hit but never takes the
    bar down (a clean rate of hits); `ping` = the player's, when it is not PLAYER_PING."""

    def __init__(self, cfg, env, set_name, policy, seed, seconds=THREAT_SECONDS, only=None, heads=None,
                 immortal=False, ping=None):
        self.cfg = cfg
        self.policy = policy
        self.seconds = seconds
        self.immortal = immortal
        crowd = cfg["crowd"]
        self.threat = crowd["threat"]
        self.vitals = cfg["player"]
        self.move = cfg["movement"]
        self.interval = 1 / crowd["snapshotHz"]  # [step]
        self.friction = max(crowd["knockFriction"], 0)  # the crowd's own slide
        self.slide = max(self.vitals["knockFriction"], 0)  # the player's
        shooting = cfg["shooting"]
        self.lag = min((PLAYER_PING if ping is None else ping) + shooting["originLagSeconds"],
                       shooting["originLagMaxSeconds"])
        self.half = env["half"]
        self.fighters = []
        for group, kind in fight_groups(cfg, set_name, only):
            for x, z in group_positions(group, self.half, kind["radius"]):
                self.fighters.append(Fighter(len(self.fighters) + 1, group["kind"], kind, x, z,
                                             group["respawnSeconds"]))
        if heads is not None:
            del self.fighters[heads:]
        self.world = ThreatWorld(cfg, self.fighters)
        self.world.owed = self.owe
        self.world.fell = self.fall
        self.boss = next((f for f in self.fighters if f.boss), None)
        self.rings = []
        self.volleys = set()  # [barrage] the barrages of which a circle has landed on him
        self.summoned = 0
        self.kill_at = None
        rng = self.rng = random.Random(seed)
        self.x = env["pad"][0] + rng.uniform(-START_JITTER, START_JITTER)
        self.z = env["pad"][1] + rng.uniform(-START_JITTER, START_JITTER)
        self.anchor = (self.x, self.z)
        self.max_hp = self.hp = env["hp"]
        self.last_hurt = -math.inf
        self.down_until = None
        self.down_span = (math.inf, -math.inf)  # the last time down: (from, until)
        self.windows = []  # i-frame windows (from, until): dash, knock and get-up
        self.knock_until = -math.inf  # [together] the last knock voids what is decided before this
        self.knock = None  # the slide a knock gave him: (unit x, unit z, speed, from)
        self.lift = None  # the launch that came with it: (from, until, apex)
        self.jump = None  # take-off time of the jump under way
        self.jump_speed = math.sqrt(2 * GRAVITY * self.move["jumpHeight"])
        self.jump_time = 2 * self.jump_speed / GRAVITY
        self.landed_at = -math.inf
        self.dash = None  # (vx, vz, until)
        self.dash_ready = 0.0
        self.dash_seconds = max(self.move["dashSeconds"], FRAME)
        self.awake = policy.get("wake") is None
        self.woke_at = 0.0 if self.awake else None
        self.lap = None
        self.heading = 1.0  # strafe: +x or -x
        self.legs = 0  # strafe: runs finished
        self.step = None  # react: the walk under way (unit x, unit z, until)
        self.seen = None  # react: the threats the last plan was made for
        # From a tell showing on screen to his moving: the practised player's, or the policy's.
        self.reaction = policy["reaction"] if policy.get("reaction") is not None else REACTION_SECONDS
        weapon = policy.get("weapon") or (cfg["loadout"]["melee"], None)
        self.variant = variant_of(cfg, *weapon)
        self.melee = self.variant["kind"] == "melee"
        # P5 ruling 8: the HP-loss scale of his weapon's slot, of the ground slam (melee) and of
        # his ability. A mission view carries them in `_scales`; the range has none, so all are 1.
        scales = cfg.get("_scales") or {}
        slot = cfg["weapons"][weapon[0]]["slot"]
        self.hit_scale = scales.get(slot, 1.0)
        self.slam_scale = scales.get("melee", 1.0)
        self.cast_scale = scales.get(slot + "Ability", self.hit_scale)
        if cfg["weapons"][weapon[0]]["ability"]["id"] == "magDump":
            # Mag Dump only buffs the fire: its bullets are ordinary attacks and scale as such
            # (damageMult, not abilityMult; the two differ from Ascension 1 on).
            self.cast_scale = self.hit_scale
        self.world.scale = self.hit_scale
        self.shots_fired = 0
        self.busy_until = 0.0
        self.jump_at = None  # react: when the jump he is timing leaves the floor
        # The boss fight: whom he closes on and how near, his ability if he uses it, and the
        # ground slam, his way through a plate when no hit of his weapon is heavy.
        self.want = math.inf
        self.quarry = self.boss
        self.cast = None
        self.cast_ready = 0.0
        self.casts = 0
        self.slams = 0
        self.slam_ready = 0.0
        chain = self.variant.get("chain") or [1.0]
        self.heavy = self.variant["damage"] * (max(chain) if self.melee else 1) >= crowd["heavyHit"]
        self.guards_at = None  # when the last of a boss's guard fell
        self.gave = 0.0  # studs the boss walked between then and its plate's break
        if self.boss is not None:
            self.want = self.wanted(self.boss)
            if policy.get("abilities"):
                # He casts it only when it beats what his own attacks would do in the time it
                # locks him: a crowd ability (a whirlwind) is no use on a lone giant.
                cast = boss_cast(cfg, weapon[0], self.boss.name)
                if cast[0] > single_dps(self.variant) * cast[1]:
                    self.cast = cast
        self.face = (0.0, -1.0)
        self.combo = 0
        self.next_swing = 0.0
        self.last_swing = -math.inf
        self.track = None  # CrowdBrain's view of the player (crowd_step)
        # Tuning.FastestMove: the fastest legal move, the most the led aim trusts.
        dash_speed = self.move["dashDistance"] / self.move["dashSeconds"] if self.move["dashSeconds"] > 0 else 0
        self.fastest = max(self.move["walkSpeed"], self.move["slamFallSpeed"], dash_speed, 0)
        self.swept_at = 0.0
        # Impacts waiting for their decision: [decided at, impact, kind, attack, x, z, facing,
        # voided, the point a lob was thrown at, when it was thrown].
        self.pending = []
        self.judging = ()  # the part of that queue resolve() is walking
        self.shots = []
        self.charges = []
        self.peak_shots = 0
        self.log = []  # every hit that landed: (time, damage, kind, shape)
        self.outcomes = {}  # per enemy kind: [attacks decided against a standing player, landed]
        self.downs = []
        self.dodged = self.whiffed = self.dashes = 0
        self.full_at = None
        self.nearest = math.inf
        self.in_reach = []

    # -- the player ---------------------------------------------------------------------------

    def player_box(self):
        """Where his root may go: (x0, x1, z0, z1). The arena's fence less FENCE_CLEARANCE."""
        limit_x, limit_z = self.half[0] - FENCE_CLEARANCE, self.half[1] - FENCE_CLEARANCE
        return -limit_x, limit_x, -limit_z, limit_z

    def body_box(self, radius, floor):
        """Where a body's centre may go on its floor: (x0, x1, z0, z1). The range and a mission
        have one floor centred on the origin (`floor` None); a level run has one per camp."""
        limit_x, limit_z = max(self.half[0] - radius, 0), max(self.half[1] - radius, 0)
        return -limit_x, limit_x, -limit_z, limit_z

    def may_target(self, e):
        """Has this body the player for a target this step? Always, but in a level run."""
        return True

    def before_think(self, now, dt):
        """Once per crowd step, after the player is tracked and before any body thinks (a level
        run's camp step)."""

    def swingable(self):
        """The bodies he may strike."""
        return [e for e in self.fighters if e.alive]

    def shift(self, dx, dz):
        x0, x1, z0, z1 = self.player_box()
        self.x = clamp(self.x + dx, x0, x1)
        self.z = clamp(self.z + dz, z0, z1)

    def feet(self, t):
        """Height of the feet above the floor: a jump, or the launch of a knock."""
        height = 0.0
        if self.jump is not None:
            since = t - self.jump
            height = max(self.jump_speed * since - GRAVITY * since * since / 2, 0.0)
        if self.lift is not None and t < self.lift[1]:
            since = t - self.lift[0]
            height = max(height, math.sqrt(2 * GRAVITY * self.lift[2]) * since - GRAVITY * since * since / 2)
        return height

    def root(self, t):
        return (self.x, ROOT_HEIGHT + self.feet(t), self.z)

    def shielded(self, start, until, t):
        """Did an i-frame meet [start, until], or does the last knock still void hits at t?"""
        return t < self.knock_until or any(a <= until and b >= start for a, b in self.windows)

    def control(self, t, dt):
        if self.down_until is not None:
            if t < self.down_until:
                return
            # [health] VitalsService.getUp: up in place and full, the get-up i-frames from here.
            self.down_until = None
            self.hp = self.max_hp
            self.last_hurt = t
            self.windows.append((t, t + self.vitals["getUpIframes"]))
        if self.hp < self.max_hp and t - self.last_hurt >= self.vitals["regenDelay"]:  # [regen]
            self.hp = min(self.max_hp, self.hp + self.vitals["regenPerSecond"] * dt)
            if self.hp >= self.max_hp and self.full_at is None:
                self.full_at = t
        if self.jump is not None and t - self.jump >= self.jump_time:
            self.jump = None
            self.landed_at = t
        if self.knock is not None:
            ux, uz, speed, since = self.knock
            speed -= self.slide * (t - since)
            if speed > 0:
                self.shift(ux * speed * dt, uz * speed * dt)  # [knock] the slide drives him
                return
            self.knock = None
        if not self.awake:
            if not self.log or self.hp > self.policy["wake"] * self.max_hp:
                return
            self.awake = True
            self.woke_at = t
        if self.dash is not None:
            if t < self.dash[2]:
                self.shift(self.dash[0] * dt, self.dash[1] * dt)
            else:
                self.dash = None
        policy = self.policy
        if self.jump_at is not None and t >= self.jump_at - THREAT_EPS:
            if self.jump is None:
                self.jump = t
            self.jump_at = None
        if policy.get("hop") and self.jump is None and t - self.landed_at >= HOP_GROUND_SECONDS:
            self.jump = t
        if policy.get("walk") and self.dash is None:
            self.walk_lap(dt)
        if policy.get("strafe") and self.dash is None:
            if (self.x - self.anchor[0]) * self.heading >= STRAFE_LEGS[self.legs % len(STRAFE_LEGS)]:
                self.heading = -self.heading
                self.legs += 1
            self.shift(self.heading * self.move["walkSpeed"] * dt, 0.0)
        if policy.get("fight"):
            self.swing(t)
            if policy.get("evade"):
                self.evade(t, dt)
        if policy.get("react"):
            self.react(t, dt)
        elif policy.get("chase") and self.dash is None:
            self.close_in(dt)  # he answers nothing: he only walks at his quarry

    def walk_lap(self, dt):
        """Walks a lap of the arena at walk speed, clockwise, easing onto a radius that keeps
        LAP_FENCE from the fence."""
        radius = math.hypot(self.x, self.z)
        if self.lap is None:
            self.lap = clamp(radius, LAP_MIN, min(self.half) - LAP_FENCE)
        rx, rz = (self.x / radius, self.z / radius) if radius > EPSILON else (0.0, 1.0)
        pull = clamp((self.lap - radius) / LAP_EASE, -1, 1)
        vx, vz = rz + rx * pull, -rx + rz * pull
        speed = self.move["walkSpeed"] / math.hypot(vx, vz)
        self.shift(vx * speed * dt, vz * speed * dt)

    def swing(self, t):
        live = self.swingable()
        if not live:
            return
        v = self.variant
        boss = self.boss if self.policy.get("boss") and self.boss is not None and self.boss.alive else None
        nearest = min(live, key=lambda e: (e.x - self.x) ** 2 + (e.z - self.z) ** 2)
        if boss is not None:
            nearest = self.mark(live, boss, nearest)
            # He closes on the boss, or on the one of its guard he is after.
            self.quarry = nearest if nearest.summoner is boss and boss.guarded else boss
            self.want = self.wanted(self.quarry)
            if self.slam_for(nearest):
                # The ground slam: every body within its radius takes it, and it is heavy.
                move = self.move
                if (t >= self.slam_ready - THREAT_EPS and t >= self.busy_until - THREAT_EPS
                        and math.hypot(nearest.x - self.x, nearest.z - self.z) <= self.slam_reach(nearest)):
                    # RangeService: a sphere round where his root stands when he lands.
                    self.world.now = t
                    self.world.blow = (self.x, self.z, move["slamKnockback"], move["slamLaunch"])
                    self.world.scale = self.slam_scale  # P5 ruling 8: the slam scales as melee
                    explode(self.world, self.cfg, (self.x, ROOT_HEIGHT, self.z), move["slamRadius"],
                            move["slamPad"], 0, move["slamDamage"])
                    self.world.scale = self.hit_scale
                    self.world.blow = None
                    self.slams += 1
                    self.slam_ready = t + move["slamCooldown"]
                    self.busy_until = t + SLAM_SECONDS
                    return
            if (self.cast is not None and boss.plate <= 0
                    and t >= self.cast_ready - THREAT_EPS and t >= self.busy_until - THREAT_EPS
                    and math.hypot(boss.x - self.x, boss.z - self.z) <= self.wanted(boss) + CHASE_MARGIN):
                dealt, busy, cooldown = self.cast  # one cast, at the boss
                self.world.now = t
                self.world.scale = self.cast_scale
                self.world.damage(boss, dealt)
                self.world.scale = self.hit_scale
                self.casts += 1
                self.cast_ready = t + cooldown
                self.busy_until = t + busy
                if not boss.alive:
                    return
        dx, dz = nearest.x - self.x, nearest.z - self.z
        gap = math.hypot(dx, dz)
        reach = v["range"] + (v["pad"] if self.melee else 0) + nearest.r
        if t >= self.next_swing - THREAT_EPS and t >= self.busy_until - THREAT_EPS and gap <= reach:
            if t - self.last_swing > self.cfg["controls"]["comboResetSeconds"]:
                self.combo = 0
            if gap > EPSILON:
                self.face = (dx / gap, dz / gap)
            self.world.now = t
            self.world.blow = (self.x, self.z, v.get("knockback") or 0, v.get("launch") or 0)
            if self.melee:
                melee_attack(self.world, self.cfg, v, self.combo, origin=(self.x, ROOT_HEIGHT, self.z),
                             direction=(self.face[0], 0.0, self.face[1]))
            else:
                # A ranged weapon: the aim ray from chest height at the target's body (the bow
                # report's `aim` "head": at the centre of its head).
                origin = (self.x, chest_height(self.cfg), self.z)
                aim = nearest.head if self.policy.get("aim") == "head" else nearest.body
                direction = v_unit(v_sub(aim, origin))
                if direction is not None:
                    self.shots_fired += 1
                    ranged_attack(self.world, self.cfg, v, 0.0, seed=self.shots_fired, origin=origin,
                                  direction=direction)
            self.world.blow = None
            self.combo += 1
            self.last_swing = t
            self.next_swing = t + attack_interval(v)

    def wanted(self, target):
        """How near a target he wants to stand: inside his weapon's reach of it, or, when only
        the slam breaks its plate, inside the slam's."""
        v = self.variant
        reach = v["range"] + (v["pad"] if self.melee else 0) + target.r
        want = reach - CHASE_MARGIN if self.melee else min(reach - CHASE_MARGIN, RANGED_STAND)
        if self.slam_for(target):
            want = min(want, self.slam_reach(target) - CHASE_MARGIN)
        return want

    def slam_reach(self, target):
        """How far off, on the flat, a ground slam still takes a body: the slam is a sphere
        round his standing root, and it is measured to the body's centre."""
        reach = self.move["slamRadius"] + self.move["slamPad"] + target.r
        return math.sqrt(max(reach * reach - (target.body_y - ROOT_HEIGHT) ** 2, 0.0))

    def slam_for(self, target):
        """Is the ground slam his way through this target's plate? It is when the plate can be
        hurt at all and no hit of his weapon is heavy."""
        return target.plate > 0 and not self.heavy and not self.world.wards(target)

    def mark(self, live, boss, nearest):
        """The boss fight: whom he strikes. A player who ignores what the boss called strikes
        the boss. While a guard keeps the boss's plate he goes for the nearest of the guard,
        wherever it is. Otherwise what the boss called comes first while it is on him."""
        if self.policy.get("adds") == "never":
            return boss
        if self.world.wards(boss):
            guard = [e for e in live if e.summoner is boss]
            if guard:
                return min(guard, key=lambda e: (e.x - self.x) ** 2 + (e.z - self.z) ** 2)
        near = self.variant["range"] + self.variant["pad"] if self.melee else ADDS_RANGE
        if nearest is boss or math.hypot(nearest.x - self.x, nearest.z - self.z) > near + nearest.r:
            return boss
        return nearest

    def close_in(self, dt):
        """The boss fight: with nothing to answer, he walks to where his weapon reaches the boss
        (or the one of its guard he is after)."""
        boss = self.quarry
        if boss is None or not boss.alive:
            return
        dx, dz = boss.x - self.x, boss.z - self.z
        gap = math.hypot(dx, dz)
        if gap > self.want:
            travel = min(self.move["walkSpeed"] * dt, gap - self.want)
            self.shift(dx / gap * travel, dz / gap * travel)

    def evade(self, t, dt):
        if self.dash is not None:
            return
        # A tell shows with the first snapshot after the windup starts, or one crowd step later
        # when that snapshot is lost (INTERFACES "Tells are drawn against server time"); the sim
        # allows the lost one, and the player acts a reaction time after that.
        seen = self.interval + self.reaction
        threats = [e for e in self.fighters
                   if e.alive and e.state == "windup" and e.shape in ("lunge", "arc") and t >= e.started + seen
                   and shape_contains(e.attack, e.x, e.z, e.face, self.x, self.z)]
        if not threats:
            return
        first = min(threats, key=lambda e: e.until)
        if t >= self.dash_ready - THREAT_EPS:
            if first.until - t <= DASH_LEAD:
                ax, az = self.x - first.x, self.z - first.z
                away = math.hypot(ax, az)
                ax, az = (ax / away, az / away) if away > EPSILON else first.face
                # A sidestep across the attack, to whichever side ends nearer where the player
                # started (so he holds his ground instead of drifting to the fence).
                distance_ = self.move["dashDistance"]
                side = min(((az, -ax), (-az, ax)),
                           key=lambda s: math.hypot(self.x + s[0] * distance_ - self.anchor[0],
                                                    self.z + s[1] * distance_ - self.anchor[1]))
                self.start_dash(t, side)
            return
        # The dash is cooling down: a lunge is answered with the sword (any hit that staggers
        # cancels it); a windup the sword cannot cancel is walked out of, straight away from
        # the body.
        solid = [e for e in threats if e.attack["interrupt"] != "stagger"]
        if solid:
            e = min(solid, key=lambda e: e.until)
            ax, az = self.x - e.x, self.z - e.z
            away = math.hypot(ax, az)
            ax, az = (ax / away, az / away) if away > EPSILON else e.face
            walk = self.move["walkSpeed"]
            self.shift(ax * walk * dt, az * walk * dt)

    def start_dash(self, t, direction):
        """MovementController: the whole distance in dashSeconds; RangeService.OnDash opens the
        i-frames."""
        speed = self.move["dashDistance"] / self.dash_seconds
        self.dash = (direction[0] * speed, direction[1] * speed, t + self.dash_seconds)
        self.dash_ready = t + self.move["dashCooldown"]
        self.windows.append((t, t + self.move["dashIframes"]))
        self.dashes += 1

    # -- the player who reacts ------------------------------------------------------------------

    def threats(self, t):
        """Every attack whose tell the player has had time to see and act on: one crowd step for
        a lost snapshot, then his reaction. A line counts from its lock, a shot from its
        release, a lob from its throw: before that there is nothing to step out of."""
        seen = self.interval + self.reaction
        found = []
        for e in self.fighters:
            if not e.alive:
                continue
            attack = e.attack
            if e.state == "windup":
                if e.shape in ("lunge", "arc") and t >= e.started + seen:
                    found.append(("shape", ("w", e.id, e.started), e.until, attack, e.x, e.z, e.face, None,
                                  e.shape == "lunge"))
                elif e.shape == "line" and e.locked and t >= e.until - (attack.get("lockSeconds") or 0) + seen:
                    found.append(("shape", ("w", e.id, e.started), e.until, attack, e.x, e.z, e.face, None, False))
                elif e.shape == "lane" and t >= e.started + seen:
                    length = min(attack.get("range") or 0, self.runway(e.x, e.z, e.face, e.r, e.floor))
                    found.append(("lane", ("w", e.id, e.started), e.until, attack, e.x, e.z, e.face, length))
                elif e.shape == "ring" and t >= e.started + seen:
                    found.append(("ring", ("w", e.id, e.started), e.until, attack, e.x, e.z))
            elif e.state == "attack" and e.charge is not None:
                c = e.charge
                found.append(("lane", ("w", e.id, e.started), c["T"], attack, c["x"], c["z"], c["face"], c["length"]))
        for entry in self.pending:
            if entry[9] is None:
                # A blow that has struck and waits out his lag: its body no longer shows the
                # windup, but stepping back into its shape now would still be a hit.
                found.append(("shape", ("p", entry[1], entry[4], entry[5]), entry[1], entry[3], entry[4],
                              entry[5], entry[6], None, entry[3]["shape"] == "lunge"))
            elif t >= entry[9] + seen:  # a lob in the air
                found.append(("shape", ("l", entry[9], entry[8]), entry[1], entry[3], entry[4], entry[5],
                              entry[6], entry[8], False))
        for shot in self.shots:
            if not shot["done"] and t >= shot["T"] + seen:
                found.append(("shot", ("s", shot["T"], shot["origin"]), shot))
        for ring in self.rings:  # its windup showed it: a ring in flight is no news
            if not ring["done"]:
                found.append(("ring", ("r", ring["T"], ring["x"], ring["z"]), ring["T"], ring["attack"],
                              ring["x"], ring["z"]))
        heed = self.policy.get("heed")
        if heed is not None:  # a player who answers only these tells
            found = [f for f in found if (f[3]["shape"] if f[0] == "shape" else f[0]) in heed]
        return found

    def plan_state(self, plan, t0, tau):
        """Where a plan begun at t0 has the root at tau: (x, z, feet above the floor)."""
        elapsed = tau - t0
        if plan["dash"]:
            run = self.move["dashDistance"] / self.dash_seconds * min(elapsed, self.dash_seconds)
        else:
            # A step begins in the frame he decides in, and a hit is decided after its frame has
            # moved him (run): one frame more of walking than the seconds between the two.
            run = self.move["walkSpeed"] * min(elapsed + FRAME, plan["dur"])
        x0, x1, z0, z1 = self.player_box()
        x = clamp(self.x + plan["ux"] * run, x0, x1)
        z = clamp(self.z + plan["uz"] * run, z0, z1)
        if plan["jump"]:
            since = elapsed - plan.get("delay", 0.0)  # a timed jump leaves the floor this much later
            if since < 0:
                return x, z, self.feet(tau)
            return x, z, max(self.jump_speed * since - GRAVITY * since * since / 2, 0.0)
        return x, z, self.feet(tau)

    def plan_shielded(self, plan, t0, start, until):
        if plan["dash"] and t0 <= until and t0 + self.move["dashIframes"] >= start:
            return True
        return self.shielded(start, until, until)

    def plan_hits(self, plan, threats, t0):
        """What would still land if the player did this from t0 on: (hits that are not a
        fodder's lunge, fodder lunges, when the first of the former lands). Each shape is judged
        as the server will judge it, grown by PLAN_MARGIN: a charge and a shot against the whole
        stretch they cover in one crowd step, because that is what the root is swept against
        (sweep)."""
        solid = fodder = 0
        first = math.inf
        lag = self.lag
        step = self.interval
        for threat in threats:
            if threat[0] == "shape":
                _kind, _key, impact, attack, ex, ez, face, aim, lunge = threat
                decided = impact + lag
                if self.policy.get("hold"):
                    # The boss fight's player knows the hit is decided on the first frame at or
                    # after `decided`, after he has moved in it: a blow due inside this very
                    # frame still counts, where this frame's move puts him. (The Stop 1 player's
                    # look is kept, and his tables with it.)
                    frame = math.ceil(decided / FRAME - 1e-9) * FRAME
                    if frame < t0 - THREAT_EPS:
                        continue
                    decided = max(decided, t0)
                elif decided < t0:
                    continue
                x, z, feet = self.plan_state(plan, t0, decided)
                height = None if attack["shape"] == "line" else attack.get("height")
                if height is not None:
                    # The hit is decided on the first frame at or after `decided`, and a jump
                    # coming down loses a stud in that time. He allows himself a frame either way.
                    frame = math.ceil(decided / FRAME - 1e-9) * FRAME
                    feet = min(feet, self.plan_state(plan, t0, frame - FRAME)[2], self.plan_state(plan, t0, frame)[2],
                               self.plan_state(plan, t0, frame + FRAME)[2])
                if (height is not None and feet > height) or self.plan_shielded(plan, t0, impact, decided):
                    continue
                if any(shape_contains(attack, ex, ez, face, x + ox, z + oz, aim) for ox, oz in PLAN_PROBES):
                    if lunge:
                        fodder += 1
                    else:
                        solid += 1
                        first = min(first, decided)
            elif threat[0] == "lane":
                _kind, _key, impact, attack, sx, sz, face, length = threat
                speed = attack.get("speed") or 0
                if speed <= 0:
                    continue
                reach = (attack.get("width") or 0) / 2 + PLAN_MARGIN
                height = attack.get("height")
                tau = max(t0, impact + lag)
                # The boss fight's player may jump a wide charge, and the last frames of that
                # jump decide: he follows it frame by frame, on the frames a crowd step can
                # fall on, and allows himself a frame either way. (The Stop 1 player steps out
                # of a lane; his coarser look is kept, and his tables with it.)
                fine = bool(self.policy.get("hold"))
                tick = FRAME if fine else PLAN_TICK
                if fine:
                    tau = math.ceil(tau / FRAME - 1e-9) * FRAME
                last = impact + length / speed + lag + step
                while tau <= last:
                    back = clamp((tau - step - lag - impact) * speed, 0, length)
                    front = clamp((tau - lag - impact) * speed, 0, length)
                    x, z, feet = self.plan_state(plan, t0, tau)
                    if fine and height is not None:
                        feet = min(feet, self.plan_state(plan, t0, tau - FRAME)[2],
                                   self.plan_state(plan, t0, tau + FRAME)[2])
                    if ((height is None or feet <= height) and not self.plan_shielded(plan, t0, tau - lag, tau)
                            and point_segment_gap((x, z), (sx + face[0] * back, sz + face[1] * back),
                                                  (sx + face[0] * front, sz + face[1] * front)) <= reach):
                        solid += 1
                        first = min(first, tau)
                        break
                    tau += tick
            elif threat[0] == "ring":
                _kind, _key, impact, attack, cx, cz = threat
                speed, radius = attack.get("speed") or 0, attack.get("radius") or 0
                if speed <= 0:
                    continue
                half, height = (attack.get("width") or 0) / 2 + PLAN_MARGIN, attack.get("height")
                # Frame by frame, on the frames themselves: the front is judged at a crowd step,
                # which falls on one, and a jump's last frames above it are what decides. He
                # allows himself a frame either way.
                tau = math.ceil(max(t0, impact + lag) / FRAME - 1e-9) * FRAME
                ends = impact + radius / speed
                last = ends + lag + step
                while tau <= last:
                    to = min(tau - lag, ends)
                    start = max(tau - step - lag, impact)
                    x, z, feet = self.plan_state(plan, t0, tau)
                    away = math.hypot(x - cx, z - cz)
                    if (to >= start and away <= radius + PLAN_MARGIN
                            and not (impact + (away + half) / speed < start or impact + (away - half) / speed > to)):
                        feet = min(feet, self.plan_state(plan, t0, tau - FRAME)[2],
                                   self.plan_state(plan, t0, tau + FRAME)[2])
                        if ((height is None or feet <= height)
                                and not self.plan_shielded(plan, t0, tau - lag, tau)):
                            solid += 1
                            first = min(first, tau)
                            break
                    tau += FRAME
            else:
                shot = threat[2]
                reach = shot["radius"] + PLAN_MARGIN
                tau = t0
                last = min(shot["ends"], t0 + PLAN_HORIZON) + lag
                while tau <= last:
                    x, z, feet = self.plan_state(plan, t0, tau)
                    if (point_segment_gap((x, ROOT_HEIGHT + feet, z), self.shot_at(shot, tau - step - lag),
                                          self.shot_at(shot, tau - lag)) <= reach
                            and not self.plan_shielded(plan, t0, tau - lag, tau)):
                        solid += 1
                        first = min(first, tau)
                        break
                    tau += PLAN_TICK
        return solid, fodder, first

    def candidates(self, t):
        """The moves open to the reacting player, cheapest first."""
        stand = {"ux": 0.0, "uz": 0.0, "dur": 0.0, "jump": False, "dash": False}
        if not self.policy.get("hold"):
            yield 0.0, stand
        # Of two steps of one length, the one that ends nearer where he started: he holds his
        # ground instead of drifting to the fence.
        ways = sorted(PLAN_DIRECTIONS, key=lambda d: math.hypot(self.x + d[0] * 4 - self.anchor[0],
                                                                self.z + d[1] * 4 - self.anchor[1]))
        steps = [{"ux": ux, "uz": uz, "dur": dur, "jump": False, "dash": False}
                 for dur in PLAN_STEPS for ux, uz in ways]
        can_jump = self.jump is None and (self.lift is None or t >= self.lift[1])
        if self.policy.get("hold"):
            # Holding his ground (the boss fight): first the walk back into his weapon's reach
            # when he is out of it, then short steps, then a jump, now or timed, before any long
            # walk or a dash.
            boss = self.quarry
            if self.policy.get("chase") and boss is not None and boss.alive:
                dx, dz = boss.x - self.x, boss.z - self.z
                gap = math.hypot(dx, dz)
                if gap > self.want + PLAN_MARGIN:
                    walk = self.move["walkSpeed"]
                    for dur in reversed(PLAN_STEPS):
                        if dur * walk <= gap - self.want + PLAN_MARGIN:
                            yield 0.0, {"ux": dx / gap, "uz": dz / gap, "dur": dur, "jump": False, "dash": False}
            yield 0.0, stand
            short = [plan for plan in steps if plan["dur"] <= HOLD_STEP_SECONDS + THREAT_EPS]
            for plan in short:
                yield plan["dur"], plan
            if can_jump:
                yield 1.0, dict(stand, jump=True)
                for delay in PLAN_DELAYS:
                    yield 1.0 + delay, dict(stand, jump=True, delay=delay)
                for plan in short:
                    yield 1.0 + plan["dur"], dict(plan, jump=True)
            for plan in steps:
                if plan["dur"] > HOLD_STEP_SECONDS + THREAT_EPS:
                    yield 2.0 + plan["dur"], plan
            if t >= self.dash_ready - THREAT_EPS:
                for ux, uz in ways:
                    yield 4.0, {"ux": ux, "uz": uz, "dur": 0.0, "jump": False, "dash": True}
            return
        for plan in steps:
            yield plan["dur"], plan
        if can_jump:
            yield 1.0, dict(stand, jump=True)
            for plan in steps:
                yield 1.0 + plan["dur"], dict(plan, jump=True)
        if t >= self.dash_ready - THREAT_EPS:
            for ux, uz in ways:
                yield 2.0, {"ux": ux, "uz": uz, "dur": 0.0, "jump": False, "dash": True}

    def react(self, t, dt):
        if self.dash is not None:
            return
        threats = self.threats(t)
        seen = tuple(sorted(threat[1] for threat in threats))
        if seen != self.seen:
            self.seen = seen
            if threats:
                self.replan(t, threats)
        if self.step is not None:
            if t < self.step[2]:
                walk = self.move["walkSpeed"]
                self.shift(self.step[0] * walk * dt, self.step[1] * walk * dt)
            else:
                self.step = None
                self.seen = None  # the step is done: he looks again at what is still coming
        elif not threats and self.jump_at is None and self.policy.get("chase"):
            self.close_in(dt)

    def replan(self, t, threats):
        """The cheapest move that avoids everything he can see. When none does: the one that
        puts the first telegraphed hit off longest (he looks again when it is done), then the
        fewest of them, then the fewest lunges."""
        best = None
        for cost, plan in self.candidates(t):
            solid, fodder, first = self.plan_hits(plan, threats, t)
            score = (-first, solid, fodder, cost)
            if best is None or score < best[0]:
                best = (score, plan)
            if solid == 0 and fodder == 0:
                break
        plan = best[1]
        self.step = None
        self.jump_at = None
        if plan["dash"]:
            self.start_dash(t, (plan["ux"], plan["uz"]))
            return
        if plan["jump"]:
            if plan.get("delay"):
                self.jump_at = t + plan["delay"]
            else:
                self.jump = t
        if plan["dur"] > 0:
            self.step = (plan["ux"], plan["uz"], t + plan["dur"])

    # -- hits on the player ---------------------------------------------------------------------

    def tally(self, kind, landed):
        counts = self.outcomes.setdefault(kind, [0, 0])
        counts[0] += 1
        counts[1] += 1 if landed else 0

    def rule(self, t, impact, kind, attack, held, voided, push):
        """VitalsService.rule: one standing player's outcome of one attack, judged at t. `held` =
        the shape holds him; `voided` = an i-frame met its span or a knock was decided with it.
        Returns True when the hit lands."""
        if not held:
            self.whiffed += 1
            self.tally(kind, False)
            return False
        if voided or t < self.knock_until:
            self.dodged += 1  # ruling 7: a voided hit that would have landed shows "dodged"
            self.tally(kind, False)
            return False
        self.tally(kind, True)
        self.hurt(t, kind, attack, push)
        return True

    def hurt(self, t, kind, attack, push):
        damage = attack["damage"]
        self.log.append((t, damage, kind, attack["shape"]))
        self.last_hurt = t
        self.full_at = None
        if self.immortal:
            damage = 0
        if self.hp - damage <= 0:  # [health] never 0: down, then up in place and full
            self.downs.append(t)
            self.down_until = t + self.vitals["downSeconds"]
            self.down_span = (t, self.down_until)
            self.knock = self.dash = self.lift = self.step = self.jump_at = None
            return
        self.hp -= damage
        knockback, launch = attack.get("knockback") or 0, attack.get("launch") or 0
        if knockback <= 0 and launch <= 0:
            return
        knock_iframes = self.vitals["knockIframes"]
        self.windows.append((t, t + knock_iframes))  # [knock]
        # [together] VitalsService.rule: what has struck and waits for its decision is voided
        # here (a lob still in the air has not struck); knock_until voids what is decided next.
        self.knock_until = t + knock_iframes
        for queue in (self.pending, self.judging):
            for other in queue:
                if other[1] <= t:
                    other[7] = True
        if self.dash is not None and t < self.dash[2]:
            return  # ApplyKnock: a dash under way beats the knock; the hit still costs health
        # ApplyKnock: capped at crowd.knockMax, bled off at player.knockFriction, and no slide
        # at all without friction.
        speed = min(knockback, self.world.knock_max) if self.slide > 0 else 0.0
        if speed > 0:
            self.knock = (push[0], push[1], speed, t)
        if launch > 0:
            self.lift = (t, t + launch_airtime(launch), launch)
        self.dash = self.step = None

    def was_down(self, t):
        return self.down_span[0] <= t < self.down_span[1]

    def resolve(self, t):
        """[commit] Walks the queue as VitalsService.settle does and decides every impact whose
        T + lag has come: a lunge, an arc, a line, and a lob at its landing."""
        self.judging, self.pending = self.pending, []
        for entry in self.judging:
            decided, impact, kind, attack, ex, ez, face, voided, aim, _thrown = entry
            if decided > t + THREAT_EPS:
                self.pending.append(entry)
                continue
            if self.down_until is not None or self.was_down(impact):
                continue  # [health] a downed player takes no further hits
            volley = (kind, _thrown) if attack["shape"] == "lob" and (attack.get("count") or 1) > 1 else None
            if volley is not None and volley in self.volleys:
                continue  # [barrage] a player takes at most one circle of a barrage
            held = shape_contains(attack, ex, ez, face, self.x, self.z, aim)
            height = None if attack["shape"] == "line" else attack.get("height")  # [height] [line]
            if held and height is not None and self.feet(t) > height:
                held = False
            if attack["shape"] == "arc":
                push = (self.x - ex, self.z - ez)
            elif attack["shape"] == "lob":
                push = (self.x - aim[0], self.z - aim[1])
            else:
                push = face
            away = math.hypot(push[0], push[1])
            push = (push[0] / away, push[1] / away) if away > EPSILON else face
            if (self.rule(t, impact, kind, attack, held, voided or self.shielded(impact, decided, t), push)
                    and volley is not None):
                self.volleys.add(volley)
        self.judging = ()
        self.windows = [w for w in self.windows if w[1] >= t - 1.0]

    def shot_at(self, shot, clock):
        run = shot["speed"] * (clamp(clock, shot["T"], shot["ends"]) - shot["T"])
        return tuple(o + d * run for o, d in zip(shot["origin"], shot["direction"]))

    def sweep(self, now):
        """ThreatField.Step: once per crowd step, the root as it is now against the stretch each
        shot flew, and each charging body ran, since the last step, as they were `lag` ago."""
        before = self.swept_at
        self.swept_at = now
        lag = self.lag
        root = self.root(now)
        kept = []
        for shot in self.shots:  # [shot]
            to = min(now - lag, shot["ends"])
            start = max(before - lag, shot["T"])
            # [health] His state is read at each contact (VitalsService.judgeTravelling): a hit
            # earlier in this very step may have taken him down.
            if (self.down_until is None and not shot["done"] and to >= start and not self.was_down(now - lag)
                    and point_segment_gap(root, self.shot_at(shot, start), self.shot_at(shot, to)) <= shot["radius"]):
                shot["done"] = True  # one attack, one outcome each
                if self.rule(now, now - lag, shot["kind"], shot["attack"], True,
                             self.shielded(now - lag, now, now), shot["push"]):
                    continue  # the one that lands ends it; a voided one flies on
            if now - lag < shot["ends"]:
                kept.append(shot)
            elif not shot["done"] and not shot["blind"]:
                self.whiffed += 1
                self.tally(shot["kind"], False)
        self.shots = kept
        kept = []
        for charge in self.charges:  # [lane]
            if not charge["owner"].alive:
                continue  # a kill ends the charge where the body was
            attack = charge["attack"]
            to = min(now - lag, charge["end"])
            start = max(before - lag, charge["T"])
            height = attack.get("height")
            if (self.down_until is None and not charge["done"] and to >= start and not self.was_down(now - lag)
                    and (height is None or self.feet(now) <= height)):
                a = (charge["x"] + charge["face"][0] * self.charge_run(charge, start),
                     charge["z"] + charge["face"][1] * self.charge_run(charge, start))
                b = (charge["x"] + charge["face"][0] * self.charge_run(charge, to),
                     charge["z"] + charge["face"][1] * self.charge_run(charge, to))
                if point_segment_gap((self.x, self.z), a, b) <= (attack.get("width") or 0) / 2:
                    charge["done"] = True
                    self.rule(now, now - lag, charge["kind"], attack, True,
                              self.shielded(now - lag, now, now), charge["face"])
            if now - lag < charge["end"]:
                kept.append(charge)
            elif not charge["done"] and not charge["blind"]:
                self.whiffed += 1
                self.tally(charge["kind"], False)
        self.charges = kept
        kept = []
        for ring in self.rings:  # [ring] ThreatField.stepRing: the front as it was `lag` ago
            attack = ring["attack"]
            speed, radius = attack.get("speed") or 0, attack.get("radius") or 0
            half, height = (attack.get("width") or 0) / 2, attack.get("height")
            left = ring["T"]
            ends = left + (radius / speed if speed > 0 else 0)
            to = min(now - lag, ends)
            start = max(before - lag, left)
            if (speed > 0 and self.down_until is None and not ring["done"] and to >= start
                    and not self.was_down(now - lag) and (height is None or self.feet(now) <= height)):
                away = math.hypot(self.x - ring["x"], self.z - ring["z"])
                # He is in its way while within `radius`; the band, `width` wide round the
                # front, covers his distance from its leading edge to its trailing one.
                if away <= radius and not (left + (away + half) / speed < start or left + (away - half) / speed > to):
                    ring["done"] = True  # each player at most once per ring
                    push = ((self.x - ring["x"]) / away, (self.z - ring["z"]) / away) if away > EPSILON else (0.0, 1.0)
                    self.rule(now, now - lag, ring["kind"], attack, True, self.shielded(now - lag, now, now), push)
            if speed > 0 and now - lag < ends:
                kept.append(ring)
            elif not ring["done"] and not ring["blind"]:
                self.whiffed += 1
                self.tally(ring["kind"], False)
        self.rings = kept

    @staticmethod
    def charge_run(charge, clock):
        return clamp((clock - charge["T"]) * charge["speed"], 0, charge["length"])

    # -- the crowd ----------------------------------------------------------------------------

    def runway(self, x, z, face, radius, floor=None):
        """CrowdBrain.runway: how far a body can run along `face` before its floor's edge."""
        room = math.inf
        x0, x1, z0, z1 = self.body_box(radius, floor)
        if face[0] > 0:
            room = min(room, (x1 - x) / face[0])
        elif face[0] < 0:
            room = min(room, (x0 - x) / face[0])
        if face[1] > 0:
            room = min(room, (z1 - z) / face[1])
        elif face[1] < 0:
            room = min(room, (z0 - z) / face[1])
        return max(room, 0.0)

    def follow(self, e, now):
        """CrowdBrain.follow: a line's facing follows its target until T - lockSeconds exactly;
        the step that first passes the lock takes the target back along its motion to it."""
        if e.locked or self.track is None:
            return
        lock_at = e.until - (e.attack.get("lockSeconds") or 0)
        sx, sz = self.x, self.z
        if now >= lock_at:
            e.locked = True
            velocity = self.track["velocity"]
            sx -= velocity[0] * (now - lock_at)
            sz -= velocity[2] * (now - lock_at)
        gap = math.hypot(sx - e.x, sz - e.z)
        if gap > EPSILON:
            e.face = ((sx - e.x) / gap, (sz - e.z) / gap)
        if e.locked:
            e.face = snap_face(e.face)

    def new_id(self):
        """The next body's id: one past the bodies so far (a mission run keeps its own count)."""
        return len(self.fighters) + 1

    def owe(self, e):
        """Ruling 22: the blow of a body killed after its impact's time still lands."""
        self.land(e, e.until, self.world.now)

    def call(self, e, attack, now):
        """[summon] Bodies of kind `summon` rise evenly on a circle of `radius` round the caller,
        inside the arena: as many as bring its living summons to `count`, and as crowd.maxAlive
        leaves room for. They fight, obey threat.spawnGrace and never respawn."""
        name = attack.get("summon")
        kind = self.cfg["crowd"]["kinds"].get(name)
        if kind is None or not kind.get("brain") or not kind.get("attacks"):
            return
        e.called = True  # [guarded] its guard has been called
        room = math.floor(self.cfg["crowd"]["maxAlive"]) - sum(1 for f in self.fighters if f.alive)
        # CrowdService.summon: the attack's `count` even places lie on a circle round the
        # caller, turned so that none lies straight behind it: the first on its facing for an
        # odd count, half a step off it for an even one. A call tops up: it raises a body on
        # each place none of its living summons rose on, as many as are missing (and as
        # crowd.maxAlive leaves room for, spread evenly through the free places).
        count = max(math.floor(attack.get("count") or 0), 0)
        taken = {f.slot for f in self.fighters if f.alive and f.summoner is e}
        free = [place for place in range(count) if place not in taken]
        raise_ = min(len(free), max(room, 0))
        radius = attack.get("radius") or 0
        x0, x1, z0, z1 = self.body_box(kind["radius"], e.floor)
        yaw = math.atan2(-e.face[0], -e.face[1])  # as yawToward has it: 0 looks down -Z
        turned = 0.5 if count % 2 == 0 else 0.0
        for n in range(raise_):
            place = free[n * len(free) // raise_]
            angle = yaw + (place + turned) / count * 2 * math.pi
            body = Fighter(self.new_id(), name, kind,
                           clamp(e.x - math.sin(angle) * radius, x0, x1),
                           clamp(e.z - math.cos(angle) * radius, z0, z1), math.inf)
            body.spawned_at = now
            body.summoner = e
            body.floor = e.floor  # L1b-1: a summon takes its summoner's floor
            body.slot = place
            self.fighters.append(body)
            self.summoned += 1

    def fall(self, enemy):
        """[summon] What a boss called is removed with it, and so is everything it had in the
        air; the run notes when a boss fell."""
        boss = enemy.summoner
        if boss is not None and boss.boss and self.guards_at is None and not self.world.guard_of(boss):
            self.guards_at = self.world.now  # the last of a boss's guard has fallen
        if enemy.boss or self.policy.get("anyKill") == enemy.name:
            if self.kill_at is None:
                self.kill_at = self.world.now
        if enemy.boss:
            self.rings = [r for r in self.rings if r["kind"] != enemy.name]
            self.charges = [c for c in self.charges if c["owner"] is not enemy]
            self.shots = [x for x in self.shots if x["kind"] != enemy.name]
            self.pending = [p for p in self.pending if p[2] != enemy.name]
        for f in self.fighters:
            if f.summoner is enemy and f.alive:
                f.alive = False
                f.respawn_at = math.inf

    def land(self, e, impact, now):
        """CrowdBrain.land and VitalsService.onImpact: the windup's end. The attack is frozen at
        the body's place now, on the heading the windup locked."""
        attack = e.attack
        shape = e.shape
        standing = self.down_until is None and not self.was_down(impact)
        if shape == "ring":  # [ring] the front leaves the body's feet at the impact
            self.rings.append({"T": impact, "x": e.x, "z": e.z, "attack": attack, "kind": e.name, "done": False,
                               "blind": not standing})
            return
        if shape == "summon":  # [summon]
            self.call(e, attack, now)
            return
        if shape == "line":
            self.follow(e, now)  # a lock that falls on the impact itself
        if shape in ("lunge", "arc", "line"):
            if standing:
                self.pending.append([impact + self.lag, impact, e.name, attack, e.x, e.z, e.face, False, None, None])
            return
        # A shot and a lob are aimed now: at the target's place at the impact's own time, which
        # this step may have passed.
        here = self.root(now) if standing else (self.x, ROOT_HEIGHT, self.z)
        track = self.track
        if track is None or not standing:  # nobody to lead: aimed where he was last seen
            track = {"velocity": (0.0, 0.0, 0.0), "resting": True, "restY": here[1]}
        here = tuple(h - v * (now - impact) for h, v in zip(here, track["velocity"]))
        origin = (e.x, e.body_y, e.z)
        if shape == "lob":  # [lob] its strike is its landing
            lands = impact + (attack.get("seconds") or 0)
            # [barrage] `count` circles land together: the first on the target, the others
            # scattered within `spread` of them (evenly over that disc, from the run's own dice).
            spread = max(attack.get("spread") or 0, 0)
            count = max(math.floor(attack.get("count") or 1), 1)
            start = self.rng.uniform(0, 2 * math.pi) if count > 1 else 0.0
            for n in range(count):
                cx, cz = here[0], here[2]
                if n > 0:  # at even angles from one random turn, each spread x sqrt(u) out
                    turn = start + 2 * math.pi * (n - 1) / (count - 1)
                    far = spread * math.sqrt(self.rng.random())
                    cx, cz = cx + math.cos(turn) * far, cz + math.sin(turn) * far
                self.pending.append([lands + self.lag, lands, e.name, attack, e.x, e.z, e.face, False,
                                     (cx, cz), impact])
        elif shape == "shot":  # [shot]
            speed = attack.get("speed") or 0
            seconds = attack.get("seconds") or 0
            if speed <= 0 or seconds <= 0:
                return
            aim = shot_aim(origin, here, track, ROOT_HEIGHT, speed, attack.get("lead") or 0, self.lag)
            direction = v_unit(v_sub(aim, origin)) or (e.face[0], 0.0, e.face[1])
            flat = math.hypot(direction[0], direction[2])
            self.shots.append({"T": impact, "ends": impact + seconds, "origin": origin, "direction": direction,
                               "speed": speed, "radius": max(attack.get("radius") or 0, 0), "attack": attack,
                               "kind": e.name, "done": False, "blind": not standing,
                               "push": (direction[0] / flat, direction[2] / flat) if flat > EPSILON else e.face})
            self.peak_shots = max(self.peak_shots, len(self.shots))
        elif shape == "lane":  # [lane]
            speed = attack.get("speed") or 0
            length = min(attack.get("range") or 0, self.runway(e.x, e.z, e.face, e.r, e.floor)) if speed > 0 else 0.0
            if length <= 0:
                return
            e.charge = {"T": impact, "x": e.x, "z": e.z, "face": e.face, "speed": speed, "length": length,
                        "end": impact + length / speed, "attack": attack, "kind": e.name, "done": False,
                        "blind": not standing, "owner": e}
            self.charges.append(e.charge)

    def crowd_step(self, now, dt):
        threat = self.threat
        fighters = self.fighters
        for e in fighters:  # [spawn] the slot waits while a player stands within spawnClear
            if not e.alive and now >= e.respawn_at:
                if math.hypot(self.x - e.home[0], self.z - e.home[1]) > threat["spawnClear"]:
                    e.spawn(now)
        # [health] A downed player is nobody's target: the crowd stands until he is up.
        standing = self.down_until is None
        if standing:
            # CrowdBrain.AddTarget: his motion is the root's displacement over the last step, no
            # faster than the fastest legal move. still = the root neither rose nor fell over
            # that step; resting = nor over the one before; restY = its height when it last
            # rested, the surface he stood on. Unseen for TRACK_GAP_SECONDS, he has no motion.
            root = self.root(now)
            velocity = (0.0, 0.0, 0.0)
            still = resting = True
            rest_y = root[1]
            last = self.track
            if last is not None:
                gap = now - last["clock"]
                if 0 < gap <= TRACK_GAP_SECONDS:
                    velocity = tuple((b - a) / gap for a, b in zip(last["root"], root))
                    pace = math.sqrt(sum(c * c for c in velocity))
                    if pace > self.fastest:
                        velocity = tuple(c * self.fastest / pace for c in velocity)
                    still = abs(velocity[1]) <= STILL_SPEED
                    resting = still and last["still"]
                if not resting:
                    rest_y = last["restY"]
            self.track = {"root": root, "clock": now, "velocity": velocity, "still": still,
                          "resting": resting, "restY": rest_y}
        self.before_think(now, dt)
        # [cap] CrowdBrain.BeginStep and Commit: the places each kind holds, counted before
        # anyone thinks, so the order the crowd is walked in never decides who may start.
        held = {}
        for e in fighters:
            if e.alive and e.state in ("windup", "attack"):
                held[e.name] = held.get(e.name, 0) + 1
        # [shot] CrowdBrain.BeginStep and Commit: shots in the air plus shot windups under way.
        shots_held = len(self.shots) + sum(1 for e in fighters
                                           if e.alive and e.shape == "shot" and e.state == "windup")
        strike_seconds = threat["strikeSeconds"]
        reach_count = 0
        landed = []
        for e in fighters:  # in id order: a freed place goes to the lowest id waiting in reach
            if not e.alive or e.dormant:
                continue
            attack = e.attack
            shape = e.shape
            dx, dz = self.x - e.x, self.z - e.z
            gap = math.hypot(dx, dz)
            if self.woke_at is not None and gap < self.nearest:
                self.nearest = gap
            if gap <= e.reach + REACH_EPSILON:
                reach_count += 1
            # [timing] The impact: T is the windup's exact end, handled on the first step at or
            # after it, with the shape frozen where the body stands on that step.
            if e.state == "windup" and now >= e.until - THREAT_EPS:
                landed.append((e, e.until))
                e.state = "attack"
                e.used[e.index] = e.until  # [choice] its turn and its cooldown run from the impact
                e.landed[e.index] += 1
                if attack.get("uses") is not None:
                    e.pace()  # [uses] a spent attack no longer counts toward the reach it walks to
                e.ready[e.index] = e.until + (attack.get("cooldown") or 0)
                if shape == "lane" and (attack.get("speed") or 0) > 0:
                    e.until += (attack.get("range") or 0) / attack["speed"]
                else:
                    e.until += strike_seconds
            if e.state == "attack" and now >= e.until - THREAT_EPS:
                if e.boss and e.charge is not None:
                    # CrowdBrain.Carried: the step that finds a charge over sets the body down
                    # at its lane's end, and what follows is aimed from there.
                    c = e.charge
                    e.x, e.z = c["x"] + c["face"][0] * c["length"], c["z"] + c["face"][1] * c["length"]
                    dx, dz = self.x - e.x, self.z - e.z
                    gap = math.hypot(dx, dz)
                e.charge = None
                # [enrage] The phase is asked here. A chain is made of second-phase attacks: the
                # attack the phase began in ends in a recover, an enraged one. A chained attack
                # follows with no recover, if it can start in this very step.
                chains = e.enraged
                e.rage(now)
                follow_on = None
                if (chains and e.chain_left > 0 and self.down_until is None and now >= e.air_until
                        and now >= e.stagger_until and self.may_target(e)):
                    follow_on = e.choose(now, gap)
                if follow_on is not None:
                    e.chain_left -= 1
                    if gap > EPSILON:
                        e.face = (dx / gap, dz / gap)
                    e.begin(follow_on, now)
                    if e.shape in ("lunge", "arc", "lane"):
                        e.face = snap_face(e.face)
                    attack, shape = e.attack, e.shape
                else:
                    e.state = "recover"
                    e.until += e.recover_seconds()
                    held[e.name] -= 1  # [cap] the place is free from here: `recover` holds none
            if e.state == "recover" and now >= e.until - THREAT_EPS:
                e.state = "approach"
            if e.state in ("approach", "recover"):
                # [enrage] Neither winding up nor attacking: the moment the second phase may
                # begin, whether or not the body is free and has a target.
                e.rage(now)
            grounded = now >= e.air_until
            vx = vz = 0.0
            state = e.state
            if state == "windup":
                if shape == "line" and standing and self.may_target(e):
                    self.follow(e, now)
            elif state == "attack":
                pass
            elif e.idle is not None:
                # L1b: a resident that is not fighting walks where CampBrain.Goal says
                # (CrowdService's seek, stopping at the goal's distance), and thinks of nothing.
                if grounded and now >= e.stagger_until:
                    gx, gz, pace, stop = e.idle
                    ox, oz = gx - e.x, gz - e.z
                    away = math.sqrt(ox * ox + oz * oz)
                    if away > stop and pace > 0:
                        travel = min(pace, (away - stop) / dt)
                        vx, vz = ox / away * travel, oz / away * travel
            elif (standing and grounded and now >= e.stagger_until and (state == "approach" or e.brain == "keepAway")
                  and self.may_target(e)):
                # A free body faces its target. A rusher stands exposed through its recover; a
                # shooter keeps its distance through it.
                if gap > EPSILON:
                    e.face = (dx / gap, dz / gap)
                ready = state == "approach" and now >= e.spawned_at + threat["spawnGrace"] - THREAT_EPS  # [spawn]
                admitted = False
                choice = e.choose(now, gap) if ready else None  # [windup] [choice]
                if choice is not None:
                    admitted = held.get(e.name, 0) < e.places  # [cap] its kind's turn
                    if admitted and e.attacks[choice]["shape"] == "shot":
                        admitted = shots_held < threat["maxShots"]  # [shot] a slinger at that cap waits
                        shots_held += 1 if admitted else 0
                    if admitted:
                        held[e.name] = held.get(e.name, 0) + 1
                if admitted:
                    # [enrage] An enraged body may follow this attack with chain - 1 more.
                    e.chain_left = max(math.floor(e.enrage["chain"]) - 1, 0) if e.enraged else 0
                    e.begin(choice, now)
                    if e.shape in ("lunge", "arc", "lane"):
                        e.face = snap_face(e.face)  # locked here, as the snapshot carries it
                elif e.reach == math.inf:
                    pass  # nothing left it may use: it stands
                elif e.brain == "rush":
                    if gap > e.reach:  # [rush] CrowdService.seek
                        travel = min(e.speed, (gap - e.reach) / dt)
                        vx, vz = dx / gap * travel, dz / gap * travel
                elif gap > e.band_max:  # [keepAway] in, as far as the band
                    travel = min(e.speed, (gap - e.band_max) / dt)
                    vx, vz = dx / gap * travel, dz / gap * travel
                elif gap < e.band_min:  # ...and straight back, no further than the arena's edge
                    x0, x1, z0, z1 = self.body_box(e.r, e.floor)
                    gx = clamp(e.x - e.face[0] * (e.band_min - gap), x0, x1) - e.x
                    gz = clamp(e.z - e.face[1] * (e.band_min - gap), z0, z1) - e.z
                    far = math.hypot(gx, gz)
                    if far > EPSILON:
                        travel = min(e.speed, far / dt)
                        vx, vz = gx / far * travel, gz / far * travel
            if e.charge is not None and state == "attack":
                # [lane] CrowdBrain.Carried: the brain carries the body down its lane.
                c = e.charge
                run = self.charge_run(c, now)
                e.x, e.z = c["x"] + c["face"][0] * run, c["z"] + c["face"][1] * run
                e.kx = e.kz = 0.0
                continue
            if grounded and (e.kx or e.kz):
                speed = math.hypot(e.kx, e.kz)
                slowed = max(speed - self.friction * dt, 0.0)
                e.kx, e.kz = (e.kx * slowed / speed, e.kz * slowed / speed) if slowed > 0 else (0.0, 0.0)
            e.x += (vx + e.kx) * dt
            e.z += (vz + e.kz) * dt
            if e.boss and self.guards_at is not None and self.world.broke_at is None:
                self.gave += math.hypot(vx, vz) * dt  # the ground it gives in the plate phase
        live = [e for e in fighters if e.alive and not e.dormant]
        # crowd.largeRadius: a body this wide is never pushed by a smaller one.
        large = self.cfg["crowd"]["largeRadius"]
        for index, a in enumerate(live):  # [rush] CrowdService.separate, each pair once
            ax, az, ar = a.x, a.z, a.r
            for b in live[index + 1:]:
                reach = ar + b.r
                dx = b.x - ax
                if dx >= reach or dx <= -reach:
                    continue
                dz = b.z - az
                if dz >= reach or dz <= -reach:
                    continue
                gap_sq = dx * dx + dz * dz
                if gap_sq >= reach * reach:
                    continue
                gap = math.sqrt(gap_sq)
                if gap > 1e-4:
                    nx, nz = dx / gap, dz / gap
                else:
                    angle = (a.id * GOLDEN_RATIO_FRACTION % 1) * 2 * math.pi
                    nx, nz = math.cos(angle), math.sin(angle)
                overlap = reach - gap
                # [planted] A body in windup or attack stays; the other takes the whole overlap.
                held_a, held_b = a.state in ("windup", "attack"), b.state in ("windup", "attack")
                if (ar >= large) != (b.r >= large):
                    # CrowdService.shoulder: a large body is never pushed by a smaller one, and
                    # a small one planted in its windup overlaps the giant until it has struck.
                    if held_b if ar >= large else held_a:
                        continue
                    share_a = 0.0 if ar >= large else 1.0
                elif held_a and held_b:
                    continue
                else:
                    share_a = 0.0 if held_a else 1.0 if held_b else b.r * b.r / (ar * ar + b.r * b.r)
                a.x -= nx * overlap * share_a
                a.z -= nz * overlap * share_a
                b.x += nx * overlap * (1 - share_a)
                b.z += nz * overlap * (1 - share_a)
                ax, az = a.x, a.z
        for e in live:
            x0, x1, z0, z1 = self.body_box(e.r, e.floor)
            e.x, e.z = clamp(e.x, x0, x1), clamp(e.z, z0, z1)
            e.place()
        for e, impact in landed:
            self.land(e, impact, now)
        self.sweep(now)
        if self.log and not self.downs:
            self.in_reach.append(reach_count)

    # -- the run ------------------------------------------------------------------------------

    def run(self):
        t = 0.0
        accumulator = 0.0
        while t < self.seconds:
            self.world.now = t
            self.control(t, FRAME)
            accumulator += FRAME
            while accumulator >= self.interval - THREAT_EPS:
                accumulator -= self.interval
                self.crowd_step(t, self.interval)
            self.resolve(t)
            t += FRAME
            if self.kill_at is not None:
                break
        log = self.log
        window = self.move["dashIframes"]
        burst = max((sum(d for when, d, _k, _s in log[i:] if when - log[i][0] <= window) for i in range(len(log))),
                    default=0.0)
        first_hit = log[0][0] if log else None
        first_down = self.downs[0] if self.downs else None
        rate = gap = None
        if first_down is not None:
            until_down = [when for when, _d, _k, _s in log if when <= first_down + THREAT_EPS]
            if len(until_down) > 1 and first_down > first_hit:
                rate = (len(until_down) - 1) / (first_down - first_hit)
                gap = max(b - a for a, b in zip(until_down, until_down[1:]))
        solid = [when for when, _d, _k, shape in log if shape != "lunge"]
        # What lands once the player acts (a policy with no `wake` acts from the start).
        awake = [(when, shape) for when, _d, _k, shape in log if self.woke_at is not None and when > self.woke_at]
        by_kind = {}
        for _when, damage, kind, _shape in log:
            by_kind[kind] = by_kind.get(kind, 0) + damage
        return {"firstHit": first_hit, "firstDown": first_down, "downs": len(self.downs),
                "damage": sum(d for _when, d, _k, _s in log), "hits": len(log), "dodged": self.dodged,
                "whiffed": self.whiffed, "byKind": by_kind, "outcomes": self.outcomes,
                "burst": burst, "rate": rate, "gap": gap, "kills": self.world.kills,
                "cancelled": self.world.cancelled, "blocked": self.world.blocked, "broken": self.world.broken,
                "dashes": self.dashes, "peakShots": self.peak_shots,
                "solidGap": min((b - a for a, b in zip(solid, solid[1:])), default=None),
                "nearest": self.nearest, "fullAt": self.full_at,
                "killAt": self.kill_at, "enragedAt": self.boss.enraged_at if self.boss is not None else None,
                "bossLeft": (self.boss.hp / self.boss.max_hp if self.boss is not None
                             else min((f.hp / f.max_hp for f in self.fighters), default=0.0)
                             if self.policy.get("anyKill") else None),
                "summoned": self.summoned, "casts": self.casts, "slams": self.slams,
                "guardsAt": self.guards_at, "brokeAt": self.world.broke_at, "warded": self.world.warded,
                "gave": self.gave,
                "plateLeft": (self.boss.plate / self.boss.max_plate
                              if self.boss is not None and self.boss.max_plate > 0 else None),
                "wokeAt": self.woke_at, "hitsAwake": len(awake),
                "solidAwake": sum(1 for _when, shape in awake if shape != "lunge"),
                "lastHitAwake": awake[-1][0] - self.woke_at if awake else None,
                "inReach": sum(self.in_reach) / len(self.in_reach) if self.in_reach else None}


def threat_env(cfg):
    """Everything the threat reads from outside ProvingGrounds.json."""
    armory = load_config(ARMORY_PATH)
    env = load_arena(cfg["arena"])
    env["hp"] = armory_max_hp(armory, THREAT_TIER)
    env["hpByTier"] = [armory_max_hp(armory, tier) for tier in range(len(armory["slots"]["melee"]["tiers"]) + 1)]
    env["tolerance"] = timing_tolerance()
    return env


def mean_of(values):
    known = [v for v in values if v is not None]
    return sum(known) / len(known) if known else None


def threat_rows(cfg, env):
    rows = []
    for set_name, keys in THREAT_PLAN:
        if not fight_groups(cfg, set_name):
            continue
        seconds = THREAT_SET_SECONDS.get(set_name, THREAT_SECONDS)
        for key in keys:
            policy = THREAT_POLICIES[key]
            runs = [ThreatRun(cfg, env, set_name, policy, seed, seconds).run() for seed in THREAT_SEEDS]
            row = {"set": set_name, "policy": key, "label": policy["label"], "seconds": seconds}
            for field in ("firstHit", "downs", "damage", "hits", "dodged", "whiffed", "rate", "kills", "cancelled",
                          "dashes", "inReach", "wokeAt", "blocked", "broken"):
                row[field] = mean_of([r[field] for r in runs])
            # A row goes down only if every seed does; the checks then use the earliest and latest.
            downs = [r["firstDown"] for r in runs]
            row["firstDown"] = mean_of(downs) if all(d is not None for d in downs) else None
            row["downSpan"] = (min(downs), max(downs)) if row["firstDown"] is not None else None
            # The worst seed, not the mean, for everything a check reads as a limit.
            for field in ("burst", "hitsAwake", "solidAwake", "peakShots"):
                row[field] = max(r[field] for r in runs)
            for field, pick in (("gap", max), ("solidGap", min), ("nearest", min), ("lastHitAwake", max)):
                known = [r[field] for r in runs if r[field] is not None]
                row[field] = pick(known) if known else None
            full = [r["fullAt"] for r in runs]
            row["fullAt"] = max(full) if all(f is not None for f in full) else None
            kinds = sorted({kind for r in runs for kind in r["byKind"]})
            row["byKind"] = {kind: mean_of([r["byKind"].get(kind, 0) for r in runs]) for kind in kinds}
            rows.append(row)
    return rows


def role_rows(cfg, env):
    """One shooter of each kind of the ROLE_SET set, alone, against three players who cannot be
    taken down: one who stands, one who hops, one who strafes one way. Per pair: the share of its
    attacks that land, the damage per second it deals, and the mean seconds between hits if
    every one of that kind in the COUNT_SET set (the real fight) landed as often as it did.
    A kind that throws a shot is also watched at each ping of PING_CHECKS against the players
    of BLIND_SHOT_SHARE: `byPing` = the share that lands at that ping."""
    table = {}
    kinds = [group["kind"] for group, kind in fight_groups(cfg, ROLE_SET) if kind["brain"] == "keepAway"]
    for name in dict.fromkeys(kinds):
        count = sum(group["count"] for group, _kind in fight_groups(cfg, COUNT_SET, name)) or 1
        for key in ROLE_PLAYERS:
            runs = [ThreatRun(cfg, env, ROLE_SET, THREAT_POLICIES[key], seed, ROLE_SECONDS, only=name, heads=1,
                              immortal=True).run() for seed in ROLE_SEEDS]
            decided = sum(r["outcomes"].get(name, [0, 0])[0] for r in runs)
            landed = sum(r["outcomes"].get(name, [0, 0])[1] for r in runs)
            watched = ROLE_SECONDS * len(runs)
            table[(name, key)] = {"share": landed / decided if decided else 0.0,
                                  "dps": sum(r["damage"] for r in runs) / watched,
                                  "between": watched / (landed * count) if landed else math.inf,
                                  "count": count, "byPing": {}}
            if cfg["crowd"]["kinds"][name]["attacks"][0]["shape"] != "shot" or key not in BLIND_SHOT_SHARE:
                continue
            for ping in PING_CHECKS:
                runs = [ThreatRun(cfg, env, ROLE_SET, THREAT_POLICIES[key], seed, ROLE_SECONDS, only=name, heads=1,
                                  immortal=True, ping=ping).run() for seed in ROLE_SEEDS]
                decided = sum(r["outcomes"].get(name, [0, 0])[0] for r in runs)
                landed = sum(r["outcomes"].get(name, [0, 0])[1] for r in runs)
                table[(name, key)]["byPing"][ping] = landed / decided if decided else 0.0
    return table


def plate_sequence(cfg, family, key, crit=False):
    """One weapon variant against one plated elite it never misses: normal attacks only, as the
    family tables model them (melee = the combo chain at `rate`; a bow = full charges at its
    cadence; every other gun = one hit per shot at `rate`, a beam per tick). Yields (seconds
    since the first hit, damage before armour)."""
    v = cfg["weapons"][family]["variants"][key]
    interval = attack_interval(v)
    chain = (v.get("chain") or [1.0]) if v["kind"] == "melee" else [1.0]
    scale = cfg["shooting"]["critMult"] if crit else 1.0
    step = 0
    while True:
        yield step * interval, v["damage"] * chain[step % len(chain)] * scale
        step += 1


def plate_row(cfg, name, hits, combo=None):
    """Runs a sequence of hits into the plate (ruling: a hit under crowd.heavyHit is blocked, a
    heavy one comes off the plate and its excess is lost, nothing carries over into HP) and then
    into the HP under it. Returns the hits and seconds to break, the seconds from the break to
    the kill, and the seconds an unplated elite lasts from this weapon's first hit."""
    kind = cfg["crowd"]["kinds"][PLATE_KIND]
    heavy = cfg["crowd"]["heavyHit"]
    floor_share = clamp(cfg["crowd"]["armorFloor"], 0, 1)
    armor = max(kind["armor"], 0)
    plate, hp = max(kind.get("plate") or 0, 0), kind["hp"]
    row = {"name": name, "combo": combo, "breakHits": None, "breakAt": None, "killAfter": None, "total": None,
           "bare": None, "heavy": 0, "perCombo": 0}
    bare_hp = kind["hp"]
    count = 0
    for when, amount in hits:
        if when > PLATE_GIVE_UP_SECONDS:
            break
        count += 1
        if combo is not None and count <= combo and amount >= heavy:
            row["perCombo"] += 1
        dealt = max(amount - armor, amount * floor_share)
        if row["bare"] is None:
            bare_hp -= dealt
            if bare_hp <= 0:
                row["bare"] = when
        if plate > 0:
            if amount >= heavy:
                row["heavy"] += 1
                plate -= amount
                if plate <= 0:
                    row["breakHits"], row["breakAt"] = count, when
        elif row["total"] is None:
            hp -= dealt
            if hp <= 0:
                row["killAfter"], row["total"] = when - row["breakAt"], when
        if row["total"] is not None and row["bare"] is not None:
            break
    return row


def plate_rows(cfg):
    """The plate matrix: every family and variant, body hits; the guns that only break it on a
    head are run again with crits; and the ground slam, which breaks plate for anyone."""
    rows = []
    for family, fam in cfg["weapons"].items():
        for key, v in fam["variants"].items():
            combo = len(v.get("chain") or [1.0]) if v["kind"] == "melee" else None
            row = plate_row(cfg, f"{fam['name']} {key}", plate_sequence(cfg, family, key), combo)
            row.update(family=family, key=key, slot=fam["slot"], melee=v["kind"] == "melee", head=None)
            if row["breakAt"] is None and v["kind"] != "melee":
                head = plate_row(cfg, row["name"], plate_sequence(cfg, family, key, crit=True))
                row["head"] = head["breakAt"]
            rows.append(row)
    move = cfg["movement"]
    slam = plate_row(cfg, "ground slam", ((n * move["slamCooldown"], move["slamDamage"]) for n in range(10 ** 6)))
    slam.update(family=None, key=None, slot=None, melee=False, head=None)
    rows.append(slam)
    return rows


def places_of(kind):
    """[cap] CrowdKindDef.perPlayer: the most of that kind in windup or attack against one player
    at once; a kind without the key has no cap."""
    return math.floor(kind["perPlayer"]) if kind.get("perPlayer") is not None else math.inf


def turn_cost(a):
    """What one turn of a kind can cost in one instant: `places` hits, or one when its attack
    knocks ([together] ruling 18: a hit that knocks voids every other decided with it)."""
    knocks = a["knockback"] > 0 or a["launch"] > 0
    return (1 if knocks and a["places"] > 1 else a["places"]) * a["damage"]


def threat_facts(cfg, env):
    """The sums that need no run: every fighting kind's attack against the player's speed, dash
    and jump, the attacker cap, the dash's uptime, the knock, the regen, the spawn rules."""
    crowd = cfg["crowd"]
    threat = crowd["threat"]
    vitals = cfg["player"]
    move = cfg["movement"]
    step = 1 / crowd["snapshotHz"]
    friction = max(vitals["knockFriction"], 0)
    hp = env["hp"]
    lag = min(PLAYER_PING + cfg["shooting"]["originLagSeconds"], cfg["shooting"]["originLagMaxSeconds"])
    walk = move["walkSpeed"]
    see = step + REACTION_SECONDS
    attacks = []
    roles = []
    for name, kind in crowd["kinds"].items():
        if not kind.get("brain") or kind.get("boss"):
            continue  # a boss has its own table (boss_facts)
        for attack in kind.get("attacks") or []:
            shape = attack["shape"]
            knockback, launch = attack.get("knockback") or 0, attack.get("launch") or 0
            air = launch_airtime(launch)
            length = attack.get("range") or 0
            exit_studs = worst_exit(attack) if shape != "shot" else (attack.get("radius") or 0)
            clear = jump_clear(move["jumpHeight"], attack.get("height") or 0)
            base = {"kind": name, "shape": shape, "damage": attack["damage"], "share": attack["damage"] / hp,
                    "places": places_of(kind),
                    "windup": attack["windup"], "exit": exit_studs, "reach": attack["reach"], "range": length,
                    "speed": kind["speed"], "knockback": knockback, "launch": launch, "air": air,
                    **knock_facts(attack, min(knockback, max(crowd["knockMax"], 0)), friction,
                                  vitals["knockIframes"])}
            if shape in ("lunge", "arc"):
                need = see + exit_studs / walk
                attacks.append({**base, "need": need, "margin": attack["windup"] - need, "jump": clear,
                                "seenFor": attack["windup"] - see,
                                "place": attack["windup"] + threat["strikeSeconds"],
                                "cycle": attack["windup"] + threat["strikeSeconds"] + attack["recover"],
                                "through": longest_way_out(attack), "walkOn": walk * attack["windup"]})
                continue
            # Wave 2. `tell` = what the player answers and `given` = how long it leaves him: a
            # lane its windup, a lob its flight, a line its lock, a shot its flight from the
            # nearest the slinger stands.
            charge = length / attack["speed"] if shape == "lane" and (attack.get("speed") or 0) > 0 else None
            strike = charge if charge is not None else threat["strikeSeconds"]
            band = (min(max(kind.get("bandMin") or 0, 0), attack["reach"]),
                    min(kind.get("bandMax") or attack["reach"], attack["reach"]))
            if shape == "lane":
                tell, given = "its windup", attack["windup"]
            elif shape == "lob":
                tell, given = "its flight", attack.get("seconds") or 0
            elif shape == "line":
                tell, given = "its lock", (attack.get("lockSeconds") or 0) + lag
            else:
                tell = "its flight from the near edge of its band"
                given = band[0] / attack["speed"] if (attack.get("speed") or 0) > 0 else math.inf
            need = see + exit_studs / walk
            role = {**base, "brain": kind["brain"], "band": band, "hp": kind["hp"], "tell": tell, "given": given,
                    "rawBand": (kind.get("bandMin") or 0, kind.get("bandMax") or 0),
                    "need": need, "margin": given - need, "jump": clear if shape in ("lane", "lob") else None,
                    "place": attack["windup"] + strike,
                    "cycle": attack["windup"] + strike + attack["recover"], "recover": attack["recover"],
                    "charge": charge, "lock": attack.get("lockSeconds"), "seconds": attack.get("seconds"),
                    "shotSpeed": attack.get("speed") if shape == "shot" else None, "lead": attack.get("lead"),
                    "radius": attack.get("radius"), "width": attack.get("width"), "height": attack.get("height")}
            role["stillDps"] = attack["damage"] / role["cycle"]
            roles.append(role)
    lunges = [a for a in attacks if a["shape"] == "lunge"]
    # [cap] The lunging kind's places against one player (no `perPlayer` = no cap).
    cap = max((places_of(crowd["kinds"][a["kind"]]) for a in lunges), default=0)
    ceiling = max((cap * a["damage"] / (a["windup"] + threat["strikeSeconds"]) for a in lunges), default=0.0)
    volley = max((cap * a["damage"] for a in lunges), default=0.0)
    accepted = move["dashCooldown"] * env["tolerance"]
    groups = [(group, kind) for name in cfg["dummySets"] for group, kind in fight_groups(cfg, name)]
    slots = [(x, z) for group, kind in groups for x, z in group_positions(group, env["half"], kind["radius"])]
    # Getting up inside the biggest pack a set can put round a player: the i-frames must outlast
    # seeing it, reacting, and walking out of the pack.
    pack = max((pack_radius(group["count"], kind["radius"]) for group, kind in groups), default=0.0)
    melee = variant_of(cfg, cfg["loadout"]["melee"])
    # [cap] [together] The most one instant can cost in each fighting set: one turn of every
    # kind in it that does not knock, plus the hardest knock (the first knock voids whatever is
    # decided with it or inside its knockIframes, so only one can land).
    by_kind = {a["kind"]: a for a in attacks + roles}
    instants = {}
    for set_name in cfg["dummySets"]:
        present = [by_kind[name] for name in dict.fromkeys(group["kind"] for group, _kind in
                                                           fight_groups(cfg, set_name)) if name in by_kind]
        if present:
            soft = sum(a["places"] * a["damage"] for a in present if a["knockback"] <= 0 and a["launch"] <= 0)
            knock = max((a["damage"] for a in present if a["knockback"] > 0 or a["launch"] > 0), default=0.0)
            instants[set_name] = soft + knock
    counts = {}
    for group, _kind in fight_groups(cfg, COUNT_SET):
        counts[group["kind"]] = counts.get(group["kind"], 0) + group["count"]
    return {"hp": hp, "step": step, "friction": friction, "attacks": attacks, "roles": roles,
            "cap": cap, "volley": volley, "ceiling": ceiling, "instants": instants, "counts": counts,
            "floorSeconds": hp / ceiling if ceiling > 0 else math.inf,
            "dashUptime": move["dashIframes"] / accepted if accepted > 0 else 1.0,
            "dashHonest": move["dashIframes"] / move["dashCooldown"] if move["dashCooldown"] > 0 else 1.0,
            "dashAccepted": accepted, "dashWindow": move["dashIframes"] + lag,
            "regenFull": (vitals["regenDelay"] + hp / vitals["regenPerSecond"] if vitals["regenPerSecond"] > 0
                          else math.inf),
            "padGap": min((math.hypot(x - env["pad"][0], z - env["pad"][1]) for x, z in slots), default=math.inf),
            "farReach": max((a["reach"] for a in attacks), default=0.0),
            "longest": max((a["through"] for a in attacks), default=0.0),
            "pack": pack, "getUpNeed": step + REACTION_SECONDS + pack / move["walkSpeed"],
            # One full combo of the default melee, first swing to finisher.
            "comboSeconds": (len(melee.get("chain") or [1.0]) - 1) / melee["rate"]}


# ---------------------------------------------------------------------------------------------
# Report and check.


def load_config(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def busy_respawn(cfg):
    return cfg["dummySets"]["stress"][0]["respawnSeconds"]


def range_crowd(cfg):
    group = cfg["dummySets"]["crowd100"][0]
    return group["spacing"], group["respawnSeconds"]


def plate_hits(cfg, family, key, plate):
    """How a weapon variant gets through a plate of `plate` when it never misses: (hits, heavy
    hits, seconds from the first hit); None when no hit of its is heavy. family None = the
    ground slam, one every slamCooldown."""
    heavy = cfg["crowd"]["heavyHit"]
    move = cfg["movement"]
    hits = (((n * move["slamCooldown"], move["slamDamage"]) for n in range(10 ** 6)) if family is None
            else plate_sequence(cfg, family, key))
    count = landed = 0
    for when, amount in hits:
        count += 1
        if amount >= heavy:
            landed += 1
            plate -= amount
            if plate <= 0:
                return count, landed, when
        if count >= 3 and landed == 0:
            return None  # a whole combo with no heavy hit: it never breaks a plate
    return None


def boss_sets(cfg):
    """The dummy sets a boss fights in: (set, the boss's kind name, its kind)."""
    found = []
    for set_name in cfg["dummySets"]:
        for group, kind in fight_groups(cfg, set_name):
            if kind.get("boss"):
                found.append((set_name, group["kind"], kind))
                break
    return found


def boss_facts(cfg, env, name, kind):
    """The sums of a boss that need no run. Per attack and phase: its tell against a reaction,
    and the window it leaves, that is, how long after its danger the boss does nothing (in the
    enraged phase a window follows the last attack of a chain).
    ring    the tell is the windup (its front is on a player at the body at once); the answer is
            a jump; the danger ends when the front has passed a player at the boss's standoff;
    lane    the tell is the windup; the answer is half the width aside; a melee player must
            walk back into his reach of where the charge ends, and that comes off the window;
    lob     the tell is the flight; the answer is the walk out of a circle; the boss is idle
            from the throw, while the circles are still in the air;
    arc     the tell is the windup; the answer is the walk out of the sector from the worst
            place in it (a jump is quicker); a melee player whose weapon does not reach from
            outside it walks back in, and that comes off the window;
    summon  no danger: its windup counts as window too.
    A `guarded` boss also gets: the kind it calls (the guard) with its tell, and each family's
    way through the guard's plate and its own."""
    crowd = cfg["crowd"]
    threat = crowd["threat"]
    vitals = cfg["player"]
    move = cfg["movement"]
    hp = env["hp"]
    step = 1 / crowd["snapshotHz"]
    walk = move["walkSpeed"]
    see = step + REACTION_SECONDS
    thumb = step + BOSS_THUMB_SECONDS
    friction = max(vitals["knockFriction"], 0)
    enrage = kind.get("enrage")
    attacks = kind.get("attacks") or []
    # The nearest it closes to in each phase: the shortest reach among the phase's attacks.
    reaches = {"calm": min((a["reach"] for a in attacks if not a.get("enraged")), default=math.inf),
               "enraged": min((a["reach"] for a in attacks if not a.get("calm")), default=math.inf)}
    melee = variant_of(cfg, cfg["loadout"]["melee"])
    want = melee["range"] + melee["pad"] + kind["radius"] - CHASE_MARGIN
    rows = []
    for attack in attacks:
        shape = attack["shape"]
        knockback, launch = attack.get("knockback") or 0, attack.get("launch") or 0
        knock = knock_facts(attack, min(knockback, max(crowd["knockMax"], 0)), friction, vitals["knockIframes"])
        for phase in ("calm", "enraged"):
            if (phase == "calm" and attack.get("enraged")) or (phase == "enraged" and enrage is None):
                continue
            if phase == "enraged" and attack.get("calm"):
                continue  # [choice] a calm attack ends with the first phase
            standoff = reaches[phase]
            windup = attack["windup"] * (enrage["windupScale"] if phase == "enraged" else 1)
            recover = attack["recover"] * (enrage["recoverScale"] if phase == "enraged" else 1)
            row = {"shape": shape, "phase": phase, "windup": windup, "recover": recover,
                   "cooldown": attack.get("cooldown") or 0, "damage": attack["damage"],
                   "share": attack["damage"] / hp, "reach": attack["reach"], "knockback": knockback,
                   "launch": launch, "air": launch_airtime(launch), "slide": knock["slide"], "throw": knock["throw"],
                   "given": None, "need": None, "needThumb": None, "answer": "", "note": ""}
            strike = threat["strikeSeconds"]
            if shape == "ring":
                speed, radius = attack.get("speed") or 0, attack.get("radius") or 0
                clear = jump_clear(move["jumpHeight"], attack.get("height") or 0)
                lift = clear[0] if clear is not None else math.inf
                # The band, `width` wide round the front, is on one spot for width / speed, and a
                # crowd step may judge him for one step more; a jump must hold the feet above
                # `height` for all of it.
                half = (attack.get("width") or 0) / 2
                passing = 2 * half / speed + step if speed > 0 else math.inf
                row.update(given=windup, need=see + lift, needThumb=thumb + lift, answer="a jump",
                           window=strike + recover - ((standoff + half) / speed if speed > 0 else 0),
                           radius=radius, speed=speed, passing=passing,
                           airtime=clear[1] - clear[0] if clear is not None else 0.0,
                           # Walking straight out from this far or further, he is past the edge
                           # when the front gets there; a dash adds its distance to the walk.
                           walkOut=radius - walk * (windup - see + ((radius - half) / speed if speed > 0 else 0)),
                           dashOut=move["dashDistance"] - walk * move["dashSeconds"])
            elif shape == "lane":
                speed, length = attack.get("speed") or 0, attack.get("range") or 0
                strike = length / speed if speed > 0 else strike
                aside = (attack.get("width") or 0) / 2
                far = max(length - standoff, 0)  # the charge ends this far past a player at the standoff
                walked = walk * (far / speed if speed > 0 else 0)  # ...who follows it once it has passed
                regain = max(math.hypot(far, aside) - walked - want, 0) / walk
                clear = jump_clear(move["jumpHeight"], attack.get("height") or 0)
                row.update(given=windup, need=see + aside / walk, needThumb=thumb + aside / walk,
                           answer=f"{aside:.1f} studs aside", window=recover - regain, regain=regain,
                           jump=clear, passes=(attack.get("width") or 0) / speed if speed > 0 else math.inf)
            elif shape == "lob":
                radius, seconds = attack.get("radius") or 0, attack.get("seconds") or 0
                spread = attack.get("spread") or 0
                row.update(given=seconds, need=see + radius / walk, needThumb=thumb + radius / walk,
                           answer=f"{radius:.0f} studs out of a circle", window=strike + recover,
                           count=max(math.floor(attack.get("count") or 1), 1), spread=spread,
                           # Every circle lies within spread + radius of him: does a straight
                           # walk begun on a reaction leave them all before they land?
                           walkAll=(seconds - see) * walk, reachAll=spread + radius)
            elif shape == "arc":
                length = attack.get("range") or 0
                out = worst_exit(attack)
                clear = jump_clear(move["jumpHeight"], attack.get("height") or 0)
                # A melee player who left it stands at its edge: has his weapon the reach from there?
                regain = max(length - want, 0) / walk
                row.update(given=windup, need=see + out / walk, needThumb=thumb + out / walk,
                           answer=f"{out:.1f} studs out of it", window=strike + recover - regain, regain=regain,
                           jump=clear, range=length, through=longest_way_out(attack),
                           degrees=min(attack.get("arcDegrees") or 360, 360))
            elif shape == "summon":
                row.update(window=windup + strike + recover, answer="none needed",
                           count=max(math.floor(attack.get("count") or 0), 0), summon=attack.get("summon"),
                           uses=attack.get("uses"))
            else:
                raise ValueError(f"no boss mirror for the attack shape {shape}")
            row["strike"] = strike
            rows.append(row)
    # [together] The most one instant can cost: one turn of each kind the boss calls whose hits
    # do not knock, plus the hardest hit that knocks, its own or theirs, plus any of its own
    # that does not (ruling 18 lets only one knock land).
    soft = 0.0
    hard = max((a["damage"] for a in attacks
                if (a.get("knockback") or 0) > 0 or (a.get("launch") or 0) > 0), default=0.0)
    guard = []
    for attack in attacks:
        if attack["shape"] == "summon":
            called = crowd["kinds"].get(attack.get("summon")) or {}
            for theirs in (called.get("attacks") or [])[:1]:
                if (theirs.get("knockback") or 0) <= 0 and (theirs.get("launch") or 0) <= 0:
                    soft += places_of(called) * theirs["damage"]
                else:
                    hard = max(hard, theirs["damage"])
                if kind.get("guarded") and theirs["shape"] in ("lunge", "arc"):
                    out = worst_exit(theirs)
                    guard.append({"kind": attack.get("summon"), "count": max(math.floor(attack.get("count") or 0), 0),
                                  "hp": called["hp"], "plate": max(called.get("plate") or 0, 0),
                                  "speed": called["speed"], "places": places_of(called), "shape": theirs["shape"],
                                  "damage": theirs["damage"], "share": theirs["damage"] / hp,
                                  "windup": theirs["windup"], "recover": theirs["recover"], "out": out,
                                  "need": see + out / walk, "needThumb": thumb + out / walk})
        elif (attack.get("knockback") or 0) <= 0 and (attack.get("launch") or 0) <= 0:
            soft += attack["damage"]
    plate = max(kind.get("plate") or 0, 0)
    ways = []
    if kind.get("guarded"):
        guard_plate = max((g["plate"] for g in guard), default=0)
        slam = {"guardHits": plate_hits(cfg, None, None, guard_plate), "ownHits": plate_hits(cfg, None, None, plate)}
        for family, fam in cfg["weapons"].items():
            v = fam["variants"][fam["default"]]
            heaviest = v["damage"] * (max(v.get("chain") or [1.0]) if v["kind"] == "melee" else 1)
            mine = {"guardHits": plate_hits(cfg, family, fam["default"], guard_plate),
                    "ownHits": plate_hits(cfg, family, fam["default"], plate)}
            ways.append({"family": family, "name": fam["name"], "slot": fam["slot"], "heaviest": heaviest,
                         "heavy": heaviest >= crowd["heavyHit"], **(mine if mine["ownHits"] is not None else slam)})
    return {"name": kind.get("name") or name, "kind": name, "hp": kind["hp"], "speed": kind["speed"],
            "standoff": reaches["calm"], "duel": reaches["enraged"], "want": want, "attacks": rows,
            "instant": soft + hard, "enrage": enrage, "plate": plate, "guarded": bool(kind.get("guarded")),
            "brain": kind["brain"], "band": (kind.get("bandMin") or 0, kind.get("bandMax") or 0),
            "guard": guard, "ways": ways, "stop": BOSS_STOP.get(name, 2),
            "melee": cfg["weapons"][cfg["loadout"]["melee"]]["name"]}


def boss_row(cfg, env, set_name, key, weapon=None, abilities=False, seeds=THREAT_SEEDS, label=None,
             seconds=None):
    """One player's fights with a boss, one per seed, each watched until the boss falls."""
    policy = dict(THREAT_POLICIES[key])
    if weapon is not None:
        policy["weapon"] = (weapon, None)
    if abilities:
        policy["abilities"] = True
    runs = [ThreatRun(cfg, env, set_name, policy, seed, seconds or BOSS_SECONDS).run() for seed in seeds]
    kills = [r["killAt"] for r in runs]
    downs = [r["firstDown"] for r in runs]
    family = cfg["weapons"][weapon or cfg["loadout"]["melee"]]

    def whole(field):
        """The mean over the seeds, or None unless it happened in every one."""
        return mean_of([r[field] for r in runs]) if all(r[field] is not None for r in runs) else None

    return {"policy": key, "label": label or policy["label"], "weapon": family["name"], "slot": family["slot"],
            "abilities": abilities, "seeds": len(seeds),
            "kill": mean_of(kills) if all(k is not None for k in kills) else None,
            "killSpan": (min(kills), max(kills)) if all(k is not None for k in kills) else None,
            "left": max(r["bossLeft"] for r in runs),
            "enraged": mean_of([r["enragedAt"] for r in runs]),
            "firstDown": mean_of(downs) if all(d is not None for d in downs) else None,
            "downSpan": (min(downs), max(downs)) if all(d is not None for d in downs) else None,
            "downs": max(r["downs"] for r in runs), "damage": mean_of([r["damage"] for r in runs]),
            # The worst seed: hits of the boss's own, and lunges of what it called.
            "solid": max(r["solidAwake"] for r in runs),
            "lunges": max(r["hitsAwake"] - r["solidAwake"] for r in runs),
            "burst": max(r["burst"] for r in runs), "summoned": mean_of([r["summoned"] for r in runs]),
            "kills": mean_of([r["kills"] for r in runs]), "casts": mean_of([r["casts"] for r in runs]),
            # Stop 3, the siege: when the last of the guard fell and when the plate broke (None
            # unless it did in every seed), the plate left in the best-kept seed, ground slams.
            "guardsAt": whole("guardsAt"), "brokeAt": whole("brokeAt"),
            "plateLeft": max((r["plateLeft"] or 0) for r in runs), "slams": mean_of([r["slams"] for r in runs]),
            "warded": mean_of([r["warded"] for r in runs]), "watched": seconds or BOSS_SECONDS,
            # The plate phase: its longest over the seeds, and the most ground the boss gave in it.
            "phase": (max(r["brokeAt"] - r["guardsAt"] for r in runs)
                      if all(r["brokeAt"] is not None and r["guardsAt"] is not None for r in runs) else None),
            "gave": max(r["gave"] for r in runs),
            # A bow: a ranged family whose shot is an arrow that falls (`gravity`).
            "bow": (variant_of(cfg, weapon or cfg["loadout"]["melee"]).get("gravity") or 0) > 0,
            "cost": min(r["damage"] for r in runs)}  # the health he lost in the seed that cost him least


def boss_rows(cfg, env):
    """Per boss set: its facts and the fights: a player who stands, one who only jumps the ring
    and sidesteps the charge, and one who reacts to every tell, with each melee family and each
    ranged one (default variants), without abilities and with them; and the default melee once
    more against a boss that calls nothing."""
    found = []
    for set_name, name, kind in boss_sets(cfg):
        facts = boss_facts(cfg, env, name, kind)
        rows = [boss_row(cfg, env, set_name, "stand", seconds=BOSS_STAND_SECONDS)]
        if kind.get("guarded"):
            # Stop 3: instead of the player who only answers the ring and the charge, the two
            # who ignore the guard and chase the boss.
            rows += [boss_row(cfg, env, set_name, "storm", seconds=CHASE_SECONDS),
                     boss_row(cfg, env, set_name, "stalk", seconds=CHASE_SECONDS)]
        else:
            rows.append(boss_row(cfg, env, set_name, "siege"))
        for slot, seeds in (("melee", THREAT_SEEDS), ("ranged", BOSS_RANGED_SEEDS)):
            for family, weapon in cfg["weapons"].items():
                if weapon["slot"] == slot:
                    for abilities in (False, True):
                        rows.append(boss_row(cfg, env, set_name, "slay", family, abilities, seeds))
        alone = json.loads(json.dumps(cfg))
        lone = alone["crowd"]["kinds"][name]
        lone["attacks"] = [a for a in lone["attacks"] if a["shape"] != "summon"]
        quiet = None
        if len(lone["attacks"]) < len(kind["attacks"]) and lone["attacks"] and not kind.get("guarded"):
            quiet = boss_row(alone, env, set_name, "slay", label="the same, and the boss calls nothing")
        found.append({"set": set_name, "facts": facts, "rows": rows, "quiet": quiet})
    return found


def family_rows(cfg, trials):
    rows = []
    for family, fam in cfg["weapons"].items():
        for key, v in fam["variants"].items():
            rng = random.Random(sum(map(ord, family + key)))
            crowd6, hits6 = crowd_dps(cfg, v, 6, trials, rng)
            crowd3, _ = crowd_dps(cfg, v, 3, trials, rng)
            row = {"family": family, "key": key, "era": fam["era"], "default": key == fam["default"],
                   "single": single_dps(v), "crowd6": crowd6, "hits6": hits6, "crowd3": crowd3, "note": v["label"]}
            if v["kind"] == "melee":
                row["surr6"], _ = crowd_dps(cfg, v, 6, trials, rng, surround=True)
            if is_charge(v):
                row["tap6"], _ = crowd_dps(cfg, v, 6, trials, rng, full=False)
            rows.append(row)
    return rows


def ability_rows(cfg, fam_rows, trials):
    busy = busy_respawn(cfg)
    r_spacing, r_respawn = range_crowd(cfg)
    rows = []
    for family, fam in cfg["weapons"].items():
        ab = fam.get("ability")
        if ab is None:
            continue
        basis = next(r for r in fam_rows if r["family"] == family and r["default"])
        # WEAPONS.md: crowd DPS = single DPS x enemies per shot, so never below single DPS. (The
        # level ray can slip between aligned columns; an aimed shot still finds its target.)
        basis_crowd = max(basis["crowd6"], basis["single"])
        raw6, hits6, kills6 = measure_cast(cfg, family, 6, trials, 1)
        raw3, _hits3, kills3 = measure_cast(cfg, family, 3, trials, 2)
        eff6, kps6 = effective_cooldown(cfg, family, 6, busy)
        eff3, _ = effective_cooldown(cfg, family, r_spacing, r_respawn)
        cast = plan_ability(cfg, family, ab, {"centre": (30, 0, 0), "aim_z": 0, "spacing": 6,
                                              "rng": random.Random(1), "seed": 1})
        scale = cfg["abilities"]["cooldownScale"]
        row = {"family": family, "id": ab["id"], "basis": basis_crowd, "single": basis["single"],
               "raw6": raw6, "hits6": hits6, "kills6": kills6, "raw3": raw3, "kills3": kills3,
               "burst": raw6 / basis_crowd, "busy": cast.busy if cast.buff is None else 0.0,
               "base": ab["cooldownSeconds"] * scale,
               "floor": min(ab["minCooldownSeconds"], ab["cooldownSeconds"]) * scale,
               "refund": ab["killRefundSeconds"], "eff6": eff6, "kps6": kps6, "eff3": eff3}
        if ab["id"] == "magDump":
            normal = 0.0
            for trial in range(trials):
                rng = random.Random(7919 + trial)  # the same crowds as measure_cast(seed=1)
                world, _ = cast_world(cfg, family, 6, rng, False)
                normal += dump_damage(cfg, family, world, rng, buffed=False).dealt
            row["raw6"] = raw6 - normal / trials  # the gain over the same seconds of normal fire
            row["burst"] = row["raw6"] / basis_crowd
        if ab["id"] in SINGLE_TARGET_ABILITIES:
            row["boss"] = measure_boss(cfg, family)
            row["bossHead"] = measure_boss(cfg, family, head=True)
            row["bossBurst"] = row["boss"] / basis["single"]
        rows.append(row)
    return rows


def share(part, whole):
    """part / whole in percent; None when cooldowns are off (abilities.cooldownScale 0)."""
    return 100 * part / whole if whole > 0 else None


def fmt(x, width=7, digits=0):
    if x is None:
        return " " * (width - 1) + "-"
    if x == math.inf:
        return " " * (width - 3) + "inf"
    return f"{x:{width}.{digits}f}"


def print_families(rows):
    print("WEAPON FAMILIES (tier 1; crowd = immortal fodder, 6-stud grid unless noted; P2 method)")
    print(f"{'family':10} {'v':1} {'era':>3} {'single':>7} {'crowd6':>7} {'hits6':>6} {'surr6':>7} {'crowd3':>7}  note")
    for r in rows:
        extra = f"  tap {r['tap6']:.0f}" if "tap6" in r else ""
        mark = "*" if r["default"] else " "
        print(f"{r['family']:10} {r['key']}{mark}{r['era']:>3} {fmt(r['single'])} {fmt(r['crowd6'])} "
              f"{fmt(r['hits6'], 6, 1)} {fmt(r.get('surr6'))} {fmt(r['crowd3'])}  {r['note']}{extra}")
    print("  * = default variant (the ability's DPS basis). Bows: full-charge cadence; 'tap' = minimum charge.")


def print_abilities(rows):
    print()
    print("ABILITIES (one cast; dmg = immortal fodder; kills = 40-HP fodder, no respawn during the cast)")
    print(f"{'ability':15} {'basis':>6} {'dmg6':>6} {'burst':>6} {'busy':>5} {'net':>5} {'hits6':>6} "
          f"{'kills6':>6} {'dmg3':>6} {'kills3':>6} | {'base':>5} {'floor':>5} {'rfnd':>5} "
          f"{'eff6':>5} {'eff%':>5} {'kill/s':>6} {'rng3':>5}")
    for r in rows:
        net = r["burst"] - r["busy"]
        print(f"{r['id']:15} {fmt(r['basis'], 6)} {fmt(r['raw6'], 6)} {fmt(r['burst'], 6, 1)} {fmt(r['busy'], 5, 2)} "
              f"{fmt(net, 5, 1)} {fmt(r['hits6'], 6, 1)} {fmt(r['kills6'], 6, 1)} {fmt(r['raw3'], 6)} "
              f"{fmt(r['kills3'], 6, 1)} | {fmt(r['base'], 5, 1)} {fmt(r['floor'], 5, 1)} {fmt(r['refund'], 5, 2)} "
              f"{fmt(r['eff6'], 5, 1)} {fmt(share(r['eff6'], r['base']), 4)}% {fmt(r['kps6'], 6, 1)} "
              f"{fmt(r['eff3'], 5, 1)}")
    print("  basis = the family's default-variant crowd DPS (6-stud); burst = dmg6 / basis in seconds;")
    print("  net = burst - busy (what casting beats the locked-out attacks by); magDump dmg = its gain over")
    print("  the same seconds of normal fire. eff6 = mean seconds between casts in the busy crowd (6-stud,")
    print("  respawn = stress set), kill/s = that fight's kill rate; rng3 = the same on the range's crowd100.")
    singles = [r for r in rows if "boss" in r]
    if singles:
        print()
        print("SINGLE-TARGET ABILITIES on the boss dummy (body aim / head aim; burst vs the family's single DPS)")
        for r in singles:
            print(f"  {r['id']:15} boss {r['boss']:6.0f} / {r['bossHead']:6.0f}   burst {r['bossBurst']:.1f} s "
                  f"(single {r['single']:.0f})   crowd burst {r['burst']:.1f} s")


def print_threat(cfg, env, facts, rows, roles, plates, ab_rows=()):
    hp = facts["hp"]
    move = cfg["movement"]
    vitals = cfg["player"]
    crowd = cfg["crowd"]
    threat = crowd["threat"]
    loadout = cfg["loadout"]
    family = cfg["weapons"][loadout["melee"]]
    print()
    print(f"THREAT (P4; tier-{THREAT_TIER} health {hp:.0f}; melee = {family['name']} {family['default']}; "
          f"{THREAT_SECONDS:.0f} s from the set's load, player on the lobby pad; mean of {len(THREAT_SEEDS)} seeds)")
    print(f"{'set':11} {'policy':34} {'1st hit':>7} {'down at':>7} {'downs':>5} {'damage':>6} {'hits':>5} "
          f"{'dodged':>6} {'missed':>6} {'burst':>5} {'hits/s':>6} {'kills':>5} {'cancel':>6}")
    for r in rows:
        print(f"{r['set']:11} {r['label']:34} {fmt(r['firstHit'], 7, 1)} {fmt(r['firstDown'], 7, 1)} "
              f"{fmt(r['downs'], 5, 1)} {fmt(r['damage'], 6)} {fmt(r['hits'], 5, 1)} {fmt(r['dodged'], 6, 1)} "
              f"{fmt(r['whiffed'], 6, 1)} {fmt(r['burst'], 5)} {fmt(r['rate'], 6, 1)} {fmt(r['kills'], 5, 1)} "
              f"{fmt(r['cancelled'], 6, 1)}")
    print("  Per run: downs, damage, hits, dodged (voided by the i-frames of a dash, a knock or the get-up), missed")
    print("  (the root was outside the shape), kills, cancel (windups the player's hits cancelled). burst = the most")
    print("  damage inside one dash i-frame window. hits/s = hits landing between the first hit and the first down.")
    short = sorted({(r["set"], r["seconds"]) for r in rows if r["seconds"] != THREAT_SECONDS})
    if short:
        print("  Shorter runs: " + ", ".join(f"{name} {seconds:.0f} s" for name, seconds in short) + ".")
    tiers = env["hpByTier"]
    print(f"  health: {hp:.0f}, tier {THREAT_TIER}, where the range pins it (ruling 17). A profile's own runs from "
          f"{tiers[0]:.0f} on starter gear to {tiers[-1]:.0f} at the last tier, and enemy damage is the same at "
          f"every tier (P5).")
    for a in facts["attacks"]:
        print(f"  {a['kind']} {a['shape']}: {a['damage']:.0f} = {a['share']:.0%} of health; one alone attacks every "
              f"{a['cycle']:.1f} s; it moves at {a['speed']:.0f} against the walk's {move['walkSpeed']:.0f}")
        print(f"    tell {a['windup']:.2f} s: walking out needs {a['need']:.2f} s (step {facts['step']:.2f} + reaction "
              f"{REACTION_SECONDS:.2f} + {a['exit']:.1f} studs at {move['walkSpeed']:.0f}/s)")
        jump = (f"a jump is clear of it {a['jump'][0]:.2f}-{a['jump'][1]:.2f} s after take-off"
                if a["jump"] is not None else "a jump does not clear it")
        print(f"    {jump}; walking on through the tell covers {a['walkOn']:.0f} studs, the longest way out is "
              f"{a['through']:.1f}")
        if a["knockback"] > 0 or a["launch"] > 0:
            print(f"    knock: {a['knockback']:.0f} studs/s bleeding off at {facts['friction']:.0f}/s2 = "
                  f"{a['throw']:.1f} studs in {a['slide']:.2f} s; launch {a['launch']:.0f} = {a['air']:.2f} s in the "
                  f"air; knockIframes {vitals['knockIframes']:.2f} s")
            print(f"      carried {a['carried']:.1f} studs, he is out of a second {a['shape']} from up to "
                  f"{a['clears']} degrees round him ({math.hypot(a['range'], a['reach']):.1f} studs would clear any)")
    print(f"  cap: {facts['cap']} lunging at once = at most {facts['volley']:.0f} in one volley "
          f"({facts['volley'] / hp:.0%} of health) and {facts['ceiling']:.1f} damage/s; a full bar lasts "
          f"{facts['floorSeconds']:.1f} s under that")
    print(f"  dash: {move['dashIframes']:.2f} s of i-frames, accepted every {facts['dashAccepted']:.2f} s "
          f"({move['dashCooldown']:.2f} s from an honest client) = invulnerable {facts['dashUptime']:.0%} "
          f"({facts['dashHonest']:.0%}) of the time;")
    print(f"    an i-frame dodge can be pressed for {facts['dashWindow']:.2f} s; its {move['dashDistance']:.0f} studs "
          f"also leave any shape (the longest way out is {facts['longest']:.1f})")
    print(f"  regen: {vitals['regenPerSecond']:.0f}/s after {vitals['regenDelay']:.0f} s unhurt: an empty bar is full "
          f"{facts['regenFull']:.0f} s after the last hit. Down {vitals['downSeconds']:.1f} s, then "
          f"{vitals['getUpIframes']:.1f} s of i-frames")
    print(f"    against the {facts['getUpNeed']:.2f} s it takes to see, react and walk out of the biggest pack "
          f"(radius {facts['pack']:.1f})")
    print(f"  spawn: the nearest fight slot is {facts['padGap']:.0f} studs from the pad (spawnClear "
          f"{threat['spawnClear']:.0f}); a fresh enemy cannot land a hit for "
          f"{threat['spawnGrace'] + min((a['windup'] for a in facts['attacks']), default=0):.1f} s")
    rates = [f"{cfg['weapons'][slot]['name']} {r['kps6']:.1f}/s" for slot in (loadout["melee"], loadout["ranged"])
             for r in ab_rows if r["family"] == slot]
    for r in rows:
        where = f"  {r['set']}, {r['label']}:"
        if r["policy"] == "stand" and r["inReach"] is not None:
            thrown = r["hits"] + r["dodged"] + r["whiffed"]
            print(f"{where} {r['inReach']:.1f} enemies stand in reach on average; {r['whiffed'] / thrown:.0%} of "
                  f"their attacks miss him; the longest lull between hits is {fmt(r['gap'], 0, 1).strip()} s")
            if r["solidGap"] is not None and r["set"] in BURST_SETS:
                print(f"    knocking hits land as close as {r['solidGap']:.2f} s apart (a still player is not "
                      f"carried out of every arc)")
        if r["policy"] in ("break", "turn") and r["wokeAt"] is not None:
            full = (f"; full again at {r['fullAt']:.0f} s" if r["fullAt"] is not None else "")
            last = (f", the last {r['lastHitAwake']:.2f} s later" if r["lastHitAwake"] is not None else "")
            print(f"{where} he acts at {r['wokeAt']:.1f} s; at most {r['hitsAwake']} more hits land{last}{full}")
        if r["policy"] == "fight" and r["kills"]:
            print(f"{where} he kills {r['kills'] / r['seconds']:.1f} enemies/s, all the set feeds him, and dashes "
                  f"{r['dashes']:.1f} times")
        if r["policy"] == "walk" and r["set"] not in BURST_SETS:
            print(f"{where} {fmt(r['damage'], 0).strip()} damage; the nearest enemy comes within "
                  f"{r['nearest']:.1f} studs")
        if r["set"] not in BURST_SETS and r["byKind"]:
            took = ", ".join(f"{kind} {amount:.0f}" for kind, amount in sorted(r["byKind"].items()))
            print(f"{where} damage by kind: {took}")
    if rates:
        print(f"  thinning: in the busy crowd (abilities table, kill/s) the loadout kills {', '.join(rates)}")

    # -- wave 2: the roles ----------------------------------------------------------------------
    if facts["roles"]:
        print()
        print(f"ROLES (P4 wave 2; a still player; one crowd step {facts['step']:.2f} s + reaction "
              f"{REACTION_SECONDS:.2f} s before he moves; walk {move['walkSpeed']:.0f})")
        print(f"{'kind':9} {'attack':5} {'hp':>4} {'speed':>5} {'band':>7} {'reach':>5} {'dmg':>4} {'share':>5} "
              f"{'cycle':>5} {'dmg/s':>5}  what he answers, and the time it leaves against the time a step out needs")
        for r in facts["roles"]:
            band = f"{r['band'][0]:.0f}-{r['band'][1]:.0f}" if r["brain"] == "keepAway" else "rush"
            print(f"{r['kind']:9} {r['shape']:5} {r['hp']:4.0f} {r['speed']:5.0f} {band:>7} {r['reach']:5.0f} "
                  f"{r['damage']:4.0f} {r['share']:5.0%} {r['cycle']:5.2f} {r['stillDps']:5.1f}  {r['tell']}: "
                  f"{r['given']:.2f} s against {r['need']:.2f} s ({r['exit']:.1f} studs out)")
        for r in facts["roles"]:
            notes = []
            if r["shape"] == "shot":
                notes.append(f"flies at {r['shotSpeed']:.0f} for {r['seconds']:.1f} s "
                             f"({r['shotSpeed'] * r['seconds']:.0f} studs), radius {r['radius']:.1f}, "
                             f"lead {r['lead']:.2f}")
            if r["shape"] == "line":
                notes.append(f"its line is seen for {r['windup'] - r['lock']:.2f} s before it locks, "
                             f"{r['lock']:.2f} s before the hit; {r['width']:.1f} wide, {r['range']:.0f} long, "
                             f"no height rule")
            if r["shape"] == "lob":
                notes.append(f"radius {r['radius']:.0f}, lands {r['seconds']:.1f} s after the throw, "
                             f"reaches {r['height']:.0f} studs up")
            if r["shape"] == "lane":
                notes.append(f"charges {r['range']:.0f} studs in {r['charge']:.2f} s, {r['width']:.0f} wide, "
                             f"{r['height']:.0f} high; then stands open for {r['recover']:.1f} s")
            if r["jump"] is not None:
                notes.append(f"a jump is clear of it {r['jump'][0]:.2f}-{r['jump'][1]:.2f} s after take-off")
            if r["knockback"] > 0 or r["launch"] > 0:
                notes.append(f"knock {r['throw']:.1f} studs in {r['slide']:.2f} s, {r['air']:.2f} s in the air")
            print(f"  {r['kind']}: " + "; ".join(notes))
    turns = facts["attacks"] + facts["roles"]
    if turns:
        print()
        print("TURNS (perPlayer: the most of one kind in windup or attack against one player; a place is held "
              "from the windup's start to the attack's end)")
        print(f"{'kind':9} {'places':>6} {'held':>6} {'cycle':>6} {'one turn':>12} {'in ' + COUNT_SET:>9} "
              f"{'attacks/s there':>16} {'without turns':>14}")
        for a in turns:
            count = facts["counts"].get(a["kind"], 0)
            free = count / a["cycle"]
            capped = min(free, a["places"] / a["place"])
            turn = turn_cost(a)
            print(f"{a['kind']:9} {a['places']:6} {a['place']:6.2f} {a['cycle']:6.2f} "
                  f"{turn:5.0f} = {turn / hp:4.0%} {count:9d} {capped:16.2f} {free:14.2f}")
        for name, most in facts["instants"].items():
            print(f"  {name}: one turn of each kind that does not knock, plus the hardest knock = {most:.0f} "
                  f"({most / hp:.0%} of health): the most one instant can cost there")
    if roles:
        kinds = sorted({kind for kind, _key in roles}, key=[k for k, _ in roles].index)
        print()
        print(f"SHOOTERS ALONE (one of each kind of `{ROLE_SET}`, by itself, against a player who cannot go down; "
              f"{ROLE_SECONDS:.0f} s, {len(ROLE_SEEDS)} seeds)")
        print(f"{'kind':9} {'in ' + COUNT_SET:>8} | "
              + " | ".join(f"{THREAT_POLICIES[key]['label']:>30}" for key in ROLE_PLAYERS))
        print(f"{'':9} {'':8} | " + " | ".join(f"{'lands':>7} {'dmg/s':>10} {'s between':>10}" for _ in ROLE_PLAYERS))
        for kind in kinds:
            cells = []
            for key in ROLE_PLAYERS:
                cell = roles[(kind, key)]
                cells.append(f"{cell['share']:7.0%} {cell['dps']:10.1f} {fmt(cell['between'], 10, 1)}")
            print(f"{kind:9} {roles[(kind, ROLE_PLAYERS[0])]['count']:8d} | " + " | ".join(cells))
        print("  lands = the share of its attacks that land; dmg/s = what one of them deals; s between = mean seconds")
        print(f"  between hits if every one of that kind in `{COUNT_SET}` landed as often. Cover is not modelled:")
        print("  only a lob goes over it.")
        for kind in kinds:
            for key in ROLE_PLAYERS:
                by_ping = roles[(kind, key)]["byPing"]
                if by_ping:
                    cells = ", ".join(f"{share:.0%} at {ping * 1000:.0f} ms" for ping, share in by_ping.items())
                    print(f"  {kind}, a player who {THREAT_POLICIES[key]['label']}, by his ping (the aim is led "
                          f"over the flight plus his lag): {roles[(kind, key)]['share']:.0%} at 0 ms, {cells}")
    if plates:
        kind = crowd["kinds"][PLATE_KIND]
        print()
        print(f"PLATE ({PLATE_KIND}: plate {kind.get('plate') or 0:.0f} over {kind['hp']:.0f} HP; a hit of "
              f"{crowd['heavyHit']:.0f} or more is heavy; it reels {crowd['plateBreakSeconds']:.1f} s when the plate "
              f"breaks; normal attacks, body hits, never missing)")
        print(f"{'weapon':18} {'breaks in':>16} {'then kills in':>13} {'total':>6} {'unplated':>8}  note")
        for r in plates:
            if r["breakAt"] is not None:
                breaks = f"{r['breakHits']} hits, {r['breakAt']:.2f} s"
            else:
                breaks = "never"
            note = ""
            if r["melee"]:
                note = f"{r['perCombo']} heavy of {r['combo']} per combo"
            elif r["breakAt"] is None and r["head"] is not None:
                note = f"on the head: {r['head']:.2f} s"
            elif r["breakAt"] is None:
                note = "no hit of it is heavy"
            print(f"{r['name']:18} {breaks:>16} {fmt(r['killAfter'], 13, 2)} {fmt(r['total'], 6, 2)} "
                  f"{fmt(r['bare'], 8, 2)}  {note}")
        print("  breaks in = hits and seconds from its first hit; then kills in = from the break to the kill with the")
        print("  same weapon; unplated = from its first hit to the kill of an elite with no plate.")


def check_threat(cfg, env, facts, rows, roles, plates, expect):
    """The P4 bands. `expect` is check()'s PASS/FAIL printer."""
    hp = facts["hp"]
    move = cfg["movement"]
    vitals = cfg["player"]
    crowd = cfg["crowd"]
    threat = crowd["threat"]
    step = facts["step"]
    row = {(r["set"], r["policy"]): r for r in rows}
    print()
    print(f"CHECK threat (targets: docs/INTERFACES.md \"P4 contracts\" and docs/BALANCE.md P4; tier-{THREAT_TIER} "
          f"health {hp:.0f})")
    expect(len(facts["attacks"]) > 0 and len(rows) > 0, "threat: at least one set fights")
    for a in facts["attacks"]:
        name = f"{a['kind']} {a['shape']}"
        expect(a["share"] <= HIT_SHARE_MAX,
               f"{name}: one hit {a['damage']:.0f} = {a['share']:.0%} of health <= {HIT_SHARE_MAX:.0%}")
        expect(a["margin"] >= TELL_MARGIN_SECONDS,
               f"{name}: tell {a['windup']:.2f} s beats the walk out ({a['need']:.2f} s) by {a['margin']:.2f} s "
               f"(>= {TELL_MARGIN_SECONDS})")
        expect(a["jump"] is not None and a["jump"][0] <= a["seenFor"],
               f"{name}: a jump clears it, and is clear {0 if a['jump'] is None else a['jump'][0]:.2f} s after "
               f"take-off (<= the {a['seenFor']:.2f} s left after seeing the tell)")
        expect(a["reach"] < a["range"],
               f"{name}: it reaches {a['range']:.1f}, past the {a['reach']:.1f} it starts from (a still player is hit)")
        expect(a["speed"] < move["walkSpeed"],
               f"{name}: the {a['kind']} is slower ({a['speed']:.0f}) than the walk ({move['walkSpeed']:.0f}): "
               f"walking away works")
        expect(a["cycle"] < vitals["regenDelay"],
               f"{name}: one alone attacks every {a['cycle']:.1f} s < regenDelay {vitals['regenDelay']:.0f} s "
               f"(regen cannot be out-waited in its reach)")
        if a["shape"] != "lunge":
            expect(a["walkOn"] >= a["through"],
                   f"{name}: walking on through the tell covers {a['walkOn']:.0f} studs >= the longest way out "
                   f"{a['through']:.1f} (a player who keeps moving is never hit by it)")
        if a["knockback"] > 0 or a["launch"] > 0:
            expect(a["launch"] < env["wall"],
                   f"{name}: launch {a['launch']:.0f} stays under the {env['wall']:.0f}-stud fence (never thrown out "
                   f"of the arena)")
            expect(max(a["air"], a["slide"]) <= vitals["knockIframes"] + THREAT_EPS,
                   f"{name}: {a['air']:.2f} s in the air and {a['slide']:.2f} s of slide are inside knockIframes "
                   f"{vitals['knockIframes']:.2f} s (never hit again while the knock has him)")
            # A launch with no knockback carries him nowhere: there is nothing to clear.
            expect(a["knockback"] <= 0 or a["clears"] >= KNOCK_CLEARS_DEGREES,
                   f"{name}: the knock carries him {a['carried']:.1f} studs, out of a second {a['shape']} from up to "
                   f"{a['clears']} degrees round him (>= {KNOCK_CLEARS_DEGREES}: attackers on one side cannot chain)")
    expect(facts["volley"] / hp <= HIT_SHARE_MAX,
           f"cap: a full volley {facts['volley']:.0f} = {facts['volley'] / hp:.0%} of health <= {HIT_SHARE_MAX:.0%}")
    for a in facts["attacks"] + facts["roles"]:
        if a["shape"] != "lunge":  # the lunge's turn is the volley above
            turn = turn_cost(a)
            expect(turn / hp <= HIT_SHARE_MAX,
                   f"turns: {a['places']} {a['kind']} at once"
                   + (", of which the first knock voids the rest," if turn < a["places"] * a["damage"] else "")
                   + f" = {turn:.0f} = {turn / hp:.0%} of health <= "
                   f"{HIT_SHARE_MAX:.0%} (one kind's turn costs no more than one hit may)")
    for name, most in facts["instants"].items():
        expect(most / hp <= INSTANT_SHARE_MAX,
               f"turns: in `{name}` the most one instant can cost is {most:.0f} = {most / hp:.0%} of health <= "
               f"{INSTANT_SHARE_MAX:.0%} (more than a third is left: one more hit does not finish a full bar)")
    lo_u, hi_u = DASH_UPTIME
    expect(lo_u <= facts["dashUptime"] <= hi_u,
           f"dash: spam is invulnerable {facts['dashUptime']:.0%} of the time, in [{lo_u:.0%}, {hi_u:.0%}]")
    expect(facts["dashWindow"] >= DASH_WINDOW_SECONDS and move["dashDistance"] >= facts["longest"],
           f"dash: the i-frame dodge's press window {facts['dashWindow']:.2f} s >= {DASH_WINDOW_SECONDS}, and its "
           f"{move['dashDistance']:.0f} studs >= the longest way out of a shape {facts['longest']:.1f}")
    expect(vitals["getUpIframes"] >= facts["getUpNeed"],
           f"get-up: {vitals['getUpIframes']:.1f} s of i-frames >= the {facts['getUpNeed']:.2f} s to see, react and "
           f"walk out of the biggest pack")
    expect(facts["padGap"] > threat["spawnClear"] > facts["farReach"],
           f"spawn: spawnClear {threat['spawnClear']:.0f} is under the pad's {facts['padGap']:.0f} studs to the "
           f"nearest slot (sets refill) and over the longest reach {facts['farReach']:.1f} (nobody spawns in reach)")
    expect(threat["spawnGrace"] >= step + REACTION_SECONDS,
           f"spawn: spawnGrace {threat['spawnGrace']:.1f} s >= a step + the reaction time "
           f"({step + REACTION_SECONDS:.2f} s)")
    for set_name, (lo, hi) in STAND_DOWN_SECONDS.items():
        r = row.get((set_name, "stand"))
        expect(r is not None, f"{set_name}: the set fights")
        if r is None:
            continue
        down = r["firstDown"]
        span = r["downSpan"]
        expect(down is not None and lo <= span[0] and span[1] <= hi,
               f"{set_name}, standing still: down at {fmt(down, 0, 1).strip()} s"
               + (f" ({span[0]:.1f}-{span[1]:.1f})" if span is not None else "") + f" in [{lo:.0f}, {hi:.0f}]")
        if set_name not in BURST_SETS:
            continue
        lunges = [a for a in facts["attacks"] if a["shape"] == "lunge"]
        if r["firstHit"] is not None and lunges and facts["cap"] > 0:
            lunge = max(lunges, key=lambda a: a["damage"])
            beat = (lunge["windup"] + threat["strikeSeconds"]) / facts["cap"]
            floor_down = r["firstHit"] + (math.ceil(hp / lunge["damage"]) - 1) * beat
            expect(floor_down >= lo,
                   f"{set_name}, standing still: with every lunge place taken the moment it frees, the down "
                   f"still comes at {floor_down:.1f} s >= {lo:.0f} (however the crowd packs)")
        lo_r, hi_r = SWARM_HITS_PER_SECOND
        expect(r["rate"] is not None and lo_r <= r["rate"] <= hi_r,
               f"{set_name}, standing still: {fmt(r['rate'], 0, 1).strip()} hits/s in [{lo_r}, {hi_r}] "
               f"(a rhythm, not a drain)")
        expect(r["gap"] is not None and r["gap"] < vitals["regenDelay"],
               f"{set_name}, standing still: the longest lull {fmt(r['gap'], 0, 1).strip()} s < regenDelay "
               f"{vitals['regenDelay']:.0f} s (regen cannot be out-waited inside the rush)")
    for r in rows:
        where = f"{r['set']}, {r['label']}"
        if r["policy"] == "stand" and r["set"] in BURST_SETS:
            expect(r["burst"] / hp <= HIT_SHARE_MAX,
                   f"{where}: the worst burst inside one dash window {r['burst']:.0f} = {r['burst'] / hp:.0%} of "
                   f"health <= {HIT_SHARE_MAX:.0%} (attacks that land together cost one hit)")
        # The distance band is wave 1's: wave 2's kinds attack from further than a walker keeps
        # off, and fodder fill `fight`. Their walker's row is printed, and judged as a dodger's.
        if r["policy"] == "walk" and r["set"] in BURST_SETS:
            expect(r["damage"] == 0 and r["nearest"] > facts["farReach"] * WALK_CLEAR_SHARE,
                   f"{where}: no damage, and nobody comes nearer than {r['nearest']:.1f} studs "
                   f"(> the longest reach {facts['farReach']:.1f})")
        if r["policy"] == "break":
            expect(r["downs"] == 0 and r["hitsAwake"] <= facts["cap"] and r["fullAt"] is not None,
                   f"{where}: he gets out (at most {r['hitsAwake']} more hits; only the {facts['cap']} lunges "
                   f"already winding up could land; no down) and regenerates to full")
        if r["policy"] in DODGING_POLICIES:
            expect(r["solidAwake"] == 0,
                   f"{where}: {r['solidAwake']} telegraphed hits land once he moves (0: only fodder may hurt a "
                   f"player who moves and dodges)")

    # -- wave 2 ---------------------------------------------------------------------------------
    walk = move["walkSpeed"]
    for r in facts["roles"]:
        name = f"{r['kind']} {r['shape']}"
        expect(r["share"] <= HIT_SHARE_MAX,
               f"{name}: one hit {r['damage']:.0f} = {r['share']:.0%} of health <= {HIT_SHARE_MAX:.0%}")
        expect(r["margin"] >= TELL_MARGIN_SECONDS,
               f"{name}: {r['tell']} leaves {r['given']:.2f} s, and stepping out needs {r['need']:.2f} s "
               f"(margin {r['margin']:.2f} s >= {TELL_MARGIN_SECONDS})")
        expect(r["speed"] < walk,
               f"{name}: the {r['kind']} is slower ({r['speed']:.0f}) than the walk ({walk:.0f})")
        if r["knockback"] > 0 or r["launch"] > 0:
            expect(r["launch"] < env["wall"] and max(r["air"], r["slide"]) <= vitals["knockIframes"] + THREAT_EPS,
                   f"{name}: launch {r['launch']:.0f} is under the {env['wall']:.0f}-stud fence, and {r['air']:.2f} s "
                   f"in the air and {r['slide']:.2f} s of slide are inside knockIframes "
                   f"{vitals['knockIframes']:.2f} s")
        if r["brain"] == "keepAway":
            low, high = r["rawBand"]
            expect(0 < low < high <= r["reach"],
                   f"{name}: band {low:.0f}-{high:.0f} lies inside its reach {r['reach']:.0f} "
                   f"(it attacks from anywhere in its band)")
        if r["shape"] == "shot":
            expect(r["shotSpeed"] * r["seconds"] >= r["reach"],
                   f"{name}: it flies {r['shotSpeed'] * r['seconds']:.0f} studs, at least its reach {r['reach']:.0f}")
        if r["shape"] == "line":
            expect(r["windup"] - r["lock"] >= step + REACTION_SECONDS and r["range"] >= r["reach"],
                   f"{name}: the line shows {r['windup'] - r['lock']:.2f} s before it locks (>= a step + the "
                   f"reaction, {step + REACTION_SECONDS:.2f} s) and is {r['range']:.0f} long, at least its reach "
                   f"{r['reach']:.0f}")
            # The locked facing is snapped to FACING_STEP: at most half a step off its target.
            drift = r["reach"] * math.tan(FACING_STEP / 2)
            expect(r["width"] / 2 > drift,
                   f"{name}: half its width {r['width'] / 2:.2f} is more than the {drift:.2f} studs its snapped "
                   f"facing can be off at its reach (a still player is always on the line)")
        if r["shape"] == "lob":
            expect(r["jump"] is not None,
                   f"{name}: a jump clears its {r['height']:.0f} studs")
        if r["shape"] == "lane":
            clear = r["jump"]
            expect(clear is not None and clear[1] - clear[0] >= r["charge"],
                   f"{name}: one jump is clear of it for {0 if clear is None else clear[1] - clear[0]:.2f} s, "
                   f"the whole {r['charge']:.2f} s charge")
            passing = r["width"] / cfg["crowd"]["kinds"][r["kind"]]["attacks"][0]["speed"]
            expect(move["dashIframes"] >= passing + TELL_MARGIN_SECONDS and move["dashDistance"] >= r["exit"],
                   f"{name}: a dash's {move['dashIframes']:.2f} s of i-frames outlast the {passing:.2f} s it takes "
                   f"to pass, and its {move['dashDistance']:.0f} studs clear the lane's {r['exit']:.1f}")
            expect(r["range"] > r["reach"],
                   f"{name}: it charges {r['range']:.0f} studs, past the {r['reach']:.0f} it starts from")
            opening = REACTION_SECONDS + facts["comboSeconds"]
            expect(r["recover"] >= opening + TELL_MARGIN_SECONDS,
                   f"{name}: its {r['recover']:.1f} s recover outlasts a reaction and one full combo of the "
                   f"default melee ({opening:.2f} s): a real opening")
    if roles:
        kinds = sorted({kind for kind, _key in roles}, key=[k for k, _ in roles].index)
        shots = [r["kind"] for r in facts["roles"] if r["shape"] == "shot"]
        lines = [r["kind"] for r in facts["roles"] if r["shape"] == "line"]
        for kind in shots:
            if (kind, "hop") not in roles:
                continue
            shot = next(r for r in facts["roles"] if r["kind"] == kind)
            answer = vitals["regenDelay"] + shot["damage"] / vitals["regenPerSecond"]
            for key, least in BLIND_SHOT_SHARE.items():
                cell = roles[(kind, key)]
                who = THREAT_POLICIES[key]["label"]
                expect(cell["share"] >= least and cell["between"] < answer,
                       f"{kind} alone, a player who {who}: {cell['share']:.0%} of shots land (>= {least:.0%}); the "
                       f"{cell['count']} of `{COUNT_SET}` would land one every {fmt(cell['between'], 0, 1).strip()} s "
                       f"(< the {answer:.1f} s his regen can answer): not a free pass")
        for kind in lines:
            if (kind, "hop") in roles:
                cell = roles[(kind, "hop")]
                expect(cell["share"] >= LINE_HOP_SHARE,
                       f"{kind} alone, a player who hops on the spot: {cell['share']:.0%} of lines land "
                       f"(>= {LINE_HOP_SHARE:.0%}: a line is a wall, the air does not avoid it)")
        for kind in kinds:
            best = [key for key in ROLE_PLAYERS
                    if all(roles[(kind, key)]["dps"] > roles[(other, key)]["dps"] for other in kinds if other != kind)]
            expect(len(best) > 0,
                   f"{kind}: the hardest hitter per head against the player who "
                   f"{' / '.join(THREAT_POLICIES[key]['label'] for key in best) or '-'} (each shooter leads "
                   f"somewhere: none is strictly better)")
    still = row.get((COUNT_SET, "stand"))
    if still is not None:
        expect(still["burst"] / hp <= FIGHT_BURST_SHARE,
               f"{COUNT_SET}, {still['label']}: the worst burst inside one dash window {still['burst']:.0f} = "
               f"{still['burst'] / hp:.0%} of health <= {FIGHT_BURST_SHARE:.0%} (enemies of one kind take turns: "
               f"the worst instant is half the bar, give or take a lunge)")
    for (kind, key), cell in roles.items():
        for ping, share in cell["byPing"].items():
            least = BLIND_SHOT_SHARE[key]
            expect(share >= least,
                   f"{kind} alone, a player who {THREAT_POLICIES[key]['label']} at {ping * 1000:.0f} ms of "
                   f"ping: {share:.0%} of shots land (>= {least:.0%}: lag is no cover)")
    most = max((r["peakShots"] for r in rows), default=0)
    if most > 0:
        expect(most < threat["maxShots"],
               f"shots: at most {most} are in the air in any set, under maxShots {threat['maxShots']:.0f} "
               f"(the cap never silences a slinger in a shipped set)")
    brawl = row.get(("fight", "brawl"))
    if brawl is not None:
        expect(brawl["firstDown"] is not None,
               f"fight, {brawl['label']}: down at {fmt(brawl['firstDown'], 0, 1).strip()} s (swinging alone is not "
               f"a free pass any more)")
    if plates:
        kind = crowd["kinds"][PLATE_KIND]
        plate = kind.get("plate") or 0
        for r in plates:
            if r["melee"]:
                expect(r["breakHits"] is not None and r["breakHits"] <= PLATE_COMBOS * r["combo"],
                       f"plate: {r['name']} breaks it in {r['breakHits']} hits, within {PLATE_COMBOS} combos "
                       f"({PLATE_COMBOS * r['combo']} hits)")
        biggest = max(v["damage"] * max(v.get("chain") or [1.0])
                      for fam in cfg["weapons"].values() for v in fam["variants"].values())
        expect(plate > biggest,
               f"plate: {plate:.0f} is more than the biggest body hit of any family ({biggest:.1f}): no normal "
               f"attack shatters it at once")
        for r in plates:
            if r["family"] == PLATE_FINISHER:
                expect(r["bare"] is not None and r["bare"] <= PLATE_FINISH_SECONDS,
                       f"plate: after the break {r['name']} kills the elite in {fmt(r['bare'], 0, 2).strip()} s "
                       f"(<= {PLATE_FINISH_SECONDS:.0f})")
        lo_p, hi_p = REACTION_SECONDS + PLATE_FOLLOW_SECONDS, PLATE_REEL_MAX_SECONDS
        expect(lo_p <= crowd["plateBreakSeconds"] <= hi_p,
               f"plate: it reels {crowd['plateBreakSeconds']:.2f} s, in [{lo_p:.2f}, {hi_p:.2f}]: long enough to "
               f"switch slot on a reaction and land the kill's first second, short enough that it fights again")
        slam = next(r for r in plates if r["family"] is None)
        expect(slam["breakHits"] is not None and slam["breakHits"] <= PLATE_SLAMS,
               f"plate: the ground slam breaks it in {slam['breakHits']} slams (<= {PLATE_SLAMS}): every loadout "
               f"has an answer")
        never = [r["name"] for r in plates if r["breakAt"] is None and r["family"] is not None]
        melee_ok = all(r["breakAt"] is not None for r in plates if r["melee"])
        expect(melee_ok,
               f"plate: every melee family breaks it, so every loadout can; alone, these cannot: "
               f"{', '.join(never) or 'none'}")


def print_boss(cfg, env, bosses):
    hp = env["hp"]
    for boss in bosses:
        f = boss["facts"]
        enrage = f["enrage"]
        print()
        if f["guarded"]:
            print(f"BOSS {f['name']} (P4 Stop {f['stop']}; set `{boss['set']}`; plate {f['plate']:.0f} over "
                  f"{f['hp']:.0f} HP, guarded; calm it keeps {f['band'][0]:.0f} to {f['band'][1]:.0f} studs off at "
                  f"{f['speed']:.0f}, enraged it closes to {f['duel']:.0f}; solo, tier-{THREAT_TIER} health {hp:.0f})")
            print(f"  enraged when its plate breaks (enrage.at {enrage['at']:.0%} of health): windups x "
                  f"{enrage['windupScale']}, recovers x {enrage['recoverScale']}, up to {enrage['chain']:.0f} attacks "
                  f"with no recover between; it then moves by `{enrage.get('brain') or f['brain']}`")
        else:
            print(f"BOSS {f['name']} (P4 Stop {f['stop']}; set `{boss['set']}`; {f['hp']:.0f} HP; it closes to "
                  f"{f['standoff']:.0f} studs at {f['speed']:.0f}; solo, tier-{THREAT_TIER} health {hp:.0f})")
            if enrage is not None:
                print(f"  enraged from {enrage['at']:.0%} health: windups x {enrage['windupScale']}, recovers x "
                      f"{enrage['recoverScale']}, up to {enrage['chain']:.0f} attacks with no recover between")
        print(f"{'attack':7} {'phase':8} {'dmg':>4} {'share':>5} {'windup':>6} {'recover':>7} {'cooldown':>8} "
              f"{'tell':>5} {'needs':>6} {'thumb':>6} {'window':>6}  the answer")
        for a in f["attacks"]:
            print(f"{a['shape']:7} {a['phase']:8} {a['damage']:4.0f} {a['share']:5.0%} {a['windup']:6.2f} "
                  f"{a['recover']:7.2f} {a['cooldown']:8.0f} {fmt(a['given'], 5, 2)} {fmt(a['need'], 6, 2)} "
                  f"{fmt(a['needThumb'], 6, 2)} {a['window']:6.2f}  {a['answer']}")
        print("  tell = the seconds the attack gives; needs = a crowd step + a 0.25 s reaction + the answer; thumb =")
        print("  the same with a 0.35 s reaction; window = how long after its danger the boss does nothing (in the")
        print(f"  enraged phase, after the last attack of a chain). A melee player ({f['melee']}) stands "
              f"{f['want']:.1f} studs off.")
        for a in f["attacks"]:
            if a["phase"] == "enraged" and any(o["shape"] == a["shape"] and o["phase"] == "calm"
                                               for o in f["attacks"]):
                continue  # the shape's notes are printed with its calm row
            if a["shape"] == "ring":
                print(f"  ring: radius {a['radius']:.0f}, front at {a['speed']:.0f} studs/s; it is on one spot for "
                      f"{a['passing']:.2f} s and a jump is above it for {a['airtime']:.2f} s; walking out works from "
                      f"{max(a['walkOut'], 0):.1f} studs or further (with a dash, from "
                      f"{max(a['walkOut'] - a['dashOut'], 0):.1f}); knock {a['throw']:.1f} studs in {a['slide']:.2f} s")
            elif a["shape"] == "lane":
                jump = (f"a jump is clear of it {a['jump'][0]:.2f}-{a['jump'][1]:.2f} s after take-off"
                        if a["jump"] is not None else "a jump does not clear it")
                print(f"  lane: it passes one spot in {a['passes']:.2f} s; {jump}; a melee player is back in reach "
                      f"{a['regain']:.2f} s into its recover; knock {a['throw']:.1f} studs in {a['slide']:.2f} s")
            elif a["shape"] == "lob":
                print(f"  lob: {a['count']} circles within {a['spread']:.0f} studs of the target; a straight walk "
                      f"begun on a reaction covers {a['walkAll']:.0f} studs before they land, and every circle lies "
                      f"within {a['reachAll']:.0f}; knock {a['throw']:.1f} studs in {a['slide']:.2f} s")
            elif a["shape"] == "arc":
                jump = (f"a jump is clear of it {a['jump'][0]:.2f}-{a['jump'][1]:.2f} s after take-off"
                        if a["jump"] is not None else "a jump does not clear it")
                print(f"  arc: {a['degrees']:.0f} degrees, {a['range']:.0f} studs from its centre, started within "
                      f"{a['reach']:.0f}; {jump}; a melee player is back in reach {a['regain']:.2f} s into its "
                      f"recover; knock {a['throw']:.1f} studs in {a['slide']:.2f} s")
            elif a["shape"] == "summon" and a["uses"] is not None:
                print(f"  summon: {a['count']} {a['summon']} rise round it, {a['uses']:.0f} time(s) in its life; they "
                      "never respawn and fall with it")
            elif a["shape"] == "summon":
                print(f"  summon: {a['count']} {a['summon']} rise round it; they never respawn and fall with it")
        print(f"  the most one instant can cost by the rules: {f['instant']:.0f} ({f['instant'] / hp:.0%} of health)")
        print(f"{'player':38} {'weapon':16} {'abil':>4} {'kill':>6} {'span':>11} {'enraged':>7} {'down at':>7} "
              f"{'downs':>5} {'hits':>4} {'lunges':>6} {'damage':>6} {'burst':>5} {'called':>6} {'casts':>5}")
        rows = boss["rows"] + ([boss["quiet"]] if boss["quiet"] is not None else [])
        for r in rows:
            span = f"{r['killSpan'][0]:.1f}-{r['killSpan'][1]:.1f}" if r["killSpan"] is not None else "-"
            print(f"{r['label']:38} {r['weapon']:16} {'yes' if r['abilities'] else '':>4} {fmt(r['kill'], 6, 1)} "
                  f"{span:>11} {fmt(r['enraged'], 7, 1)} {fmt(r['firstDown'], 7, 1)} {r['downs']:5d} {r['solid']:4d} "
                  f"{r['lunges']:6d} {fmt(r['damage'], 6)} {fmt(r['burst'], 5)} {fmt(r['summoned'], 6)} "
                  f"{fmt(r['casts'], 5, 1)}")
        print(f"  Each fight runs until the boss falls, {BOSS_SECONDS:.0f} s at most; three seeds a row, two for the "
              "ranged families.")
        print("  kill and span = seconds to the kill (mean, and fastest to slowest); hits = hits of the boss's own")
        print("  and lunges = lunges of what it called, both in the worst seed; abil = the family's ability is cast")
        print("  at the boss whenever it is ready (its base cooldown, no refunds).")
        if f["guarded"]:
            print_siege(cfg, env, boss)


def print_siege(cfg, env, boss):
    """Stop 3: the guard, each family's way through the plates, and the siege's share of each fight."""
    f = boss["facts"]
    crowd = cfg["crowd"]
    move = cfg["movement"]
    print("  (here `hits` counts the guard's arcs too, and an ability is cast only once the plate is broken.)")
    for g in f["guard"]:
        print(f"  THE GUARD: {g['count']} {g['kind']} (plate {g['plate']:.0f} over {g['hp']:.0f} HP, speed "
              f"{g['speed']:.0f}, {g['places']} at a time): {g['shape']} {g['damage']:.0f} ({g['share']:.0%}), windup "
              f"{g['windup']:.2f} s against {g['need']:.2f} s needed ({g['needThumb']:.2f} s for a thumb) to walk "
              f"{g['out']:.1f} studs out; recover {g['recover']:.1f} s")
    print(f"  THE WAY THROUGH THE PLATES (default variants, never missing; a hit of {crowd['heavyHit']:.0f} or more "
          f"is heavy; the ground slam is {move['slamDamage']:.0f} every {move['slamCooldown']:.1f} s)")
    print(f"  {'family':16} {'heaviest':>8} {'by':>10} {'guard plate':>16} {'its plate':>18}")
    for w in f["ways"]:
        by = "its hits" if w["heavy"] else "the slam"
        guard = f"{w['guardHits'][1]} heavy, {w['guardHits'][2]:.1f} s" if w["guardHits"] is not None else "-"
        own = f"{w['ownHits'][1]} heavy, {w['ownHits'][2]:.1f} s" if w["ownHits"] is not None else "-"
        print(f"  {w['name']:16} {w['heaviest']:8.1f} {by:>10} {guard:>16} {own:>18}")
    print(f"  THE SIEGE (the same fights as above; guard = the last of the guard falls, plate = its plate breaks, "
          "seconds from the set's load)")
    print(f"  {'player':38} {'weapon':16} {'abil':>4} {'guard':>6} {'plate':>6} {'kill':>6} {'siege':>6} {'duel':>6} "
          f"{'phase':>6} {'gave':>5} {'slams':>5} {'warded':>6} {'plate left':>10}")
    for r in boss["rows"]:
        siege = f"{r['brokeAt'] / r['kill']:6.0%}" if r["kill"] and r["brokeAt"] else "     -"
        duel = fmt(r["kill"] - r["brokeAt"], 6, 1) if r["kill"] and r["brokeAt"] else "     -"
        print(f"  {r['label']:38} {r['weapon']:16} {'yes' if r['abilities'] else '':>4} {fmt(r['guardsAt'], 6, 1)} "
              f"{fmt(r['brokeAt'], 6, 1)} {fmt(r['kill'], 6, 1)} {siege} {duel} {fmt(r['phase'], 6, 1)} "
              f"{fmt(r['gave'], 5)} {fmt(r['slams'], 5)} {fmt(r['warded'], 6)} {r['plateLeft']:10.0%}")
    print("  siege = the share of the kill that passed before the plate broke; duel = seconds from there to the")
    print("  kill; phase = the plate phase (guard dead to plate broken) and gave = the studs the boss walked in")
    print("  it, both in the worst seed; slams = ground slams (only by a family none of whose hits is heavy);")
    print("  warded = hits the living guard kept off the plate; plate left = in the seed that kept most of it.")


def check_boss(cfg, env, bosses, expect):
    """The Stop 2 bands, and for a `guarded` boss the Stop 3 ones."""
    hp = env["hp"]
    vitals = cfg["player"]
    move = cfg["movement"]
    for boss in bosses:
        f = boss["facts"]
        name = f["name"]
        print()
        print(f"CHECK boss {name} (targets: docs/INTERFACES.md \"Stop {f['stop']}\" and docs/BALANCE.md P4; solo, "
              f"tier-{THREAT_TIER} health {hp:.0f})")
        for a in f["attacks"]:
            what = f"{name} {a['shape']}, {a['phase']}"
            if a["damage"] > 0:
                expect(a["share"] <= HIT_SHARE_MAX,
                       f"{what}: one hit {a['damage']:.0f} = {a['share']:.0%} of health <= {HIT_SHARE_MAX:.0%}")
            if a["given"] is not None:
                expect(a["given"] - a["need"] >= TELL_MARGIN_SECONDS
                       and a["given"] - a["needThumb"] >= BOSS_THUMB_MARGIN_SECONDS,
                       f"{what}: its tell {a['given']:.2f} s clears a {REACTION_SECONDS:.2f} s reaction by "
                       f"{a['given'] - a['need']:.2f} s (>= {TELL_MARGIN_SECONDS}) and a {BOSS_THUMB_SECONDS:.2f} s "
                       f"thumb by {a['given'] - a['needThumb']:.2f} s (>= {BOSS_THUMB_MARGIN_SECONDS})")
            expect(a["window"] >= BOSS_WINDOW_SECONDS,
                   f"{what}: it leaves a window of {a['window']:.2f} s (>= {BOSS_WINDOW_SECONDS:.0f})")
            if a["phase"] == "enraged" and any(o["shape"] == a["shape"] and o["phase"] == "calm"
                                               for o in f["attacks"]):
                continue  # what follows does not change with the phase: said for the calm row
            if a["knockback"] > 0 or a["launch"] > 0:
                expect(a["launch"] < env["wall"] and max(a["air"], a["slide"]) <= vitals["knockIframes"] + THREAT_EPS,
                       f"{name} {a['shape']}: launch {a['launch']:.0f} is under the {env['wall']:.0f}-stud fence, and "
                       f"{a['air']:.2f} s in the air and {a['slide']:.2f} s of slide are inside knockIframes "
                       f"{vitals['knockIframes']:.2f} s")
            if a["shape"] == "ring":
                expect(a["airtime"] >= a["passing"] + TELL_MARGIN_SECONDS,
                       f"{name} ring: a jump holds the feet above it for {a['airtime']:.2f} s, and the front is on one "
                       f"spot for {a['passing']:.2f} s (jumpable at any distance inside its radius)")
                expect(a["radius"] > a["reach"],
                       f"{name} ring: it reaches {a['radius']:.0f}, past the {a['reach']:.0f} it starts from")
            elif a["shape"] == "lob":
                expect(a["walkAll"] >= a["reachAll"],
                       f"{name} lob: a straight walk covers {a['walkAll']:.0f} studs before the circles land, and "
                       f"they all lie within {a['reachAll']:.0f} (walking on, any way, leaves every circle)")
            elif a["shape"] == "lane":
                expect(a["jump"] is not None and move["dashIframes"] >= a["passes"] + TELL_MARGIN_SECONDS,
                       f"{name} lane: a jump clears its height, and a dash's {move['dashIframes']:.2f} s of i-frames "
                       f"outlast the {a['passes']:.2f} s it takes to pass")
            elif a["shape"] == "arc":
                expect(a["jump"] is not None and a["range"] > a["reach"],
                       f"{name} arc: a jump clears its height, and it reaches {a['range']:.0f}, past the "
                       f"{a['reach']:.0f} it starts from (a still player is hit)")
        for a in f["attacks"]:
            if a["shape"] == "ring":
                expect(a["walkOut"] >= a["reach"],
                       f"{name} ring, {a['phase']}: walking out works only from {max(a['walkOut'], 0):.1f} studs or "
                       f"further, beyond the {a['reach']:.0f} it is started from (the player it is aimed at must jump)")
        chained = [a for a in f["attacks"] if a["phase"] == "enraged" and a["given"] is not None]
        if f["enrage"] is not None and f["enrage"]["chain"] > 1 and chained:
            tight = min(chained, key=lambda a: a["given"] - a["needThumb"])
            expect(tight["given"] - tight["needThumb"] >= BOSS_THUMB_MARGIN_SECONDS,
                   f"{name}: in a chain the second attack's windup is whole and starts when the first attack ends; "
                   f"the tightest tell ({tight['shape']}, {tight['given']:.2f} s) clears a "
                   f"{BOSS_THUMB_SECONDS:.2f} s thumb by {tight['given'] - tight['needThumb']:.2f} s "
                   f"(>= {BOSS_THUMB_MARGIN_SECONDS})")
        expect(f["instant"] / hp <= INSTANT_SHARE_MAX,
               f"{name}: the most one instant can cost is {f['instant']:.0f} = {f['instant'] / hp:.0%} of health <= "
               f"{INSTANT_SHARE_MAX:.0%}")
        lo, hi = BOSS_KILL_SECONDS[f["kind"]]
        if f["guarded"]:
            check_siege(cfg, env, boss, expect)
        for r in boss["rows"]:
            who = f"{name}, {r['label']}" + (f", {r['weapon']}" if r["policy"] == "slay" else "")
            who += " with its ability" if r["abilities"] else ""
            if r["policy"] == "stand":
                expect(r["downSpan"] is not None and r["downSpan"][1] <= BOSS_STAND_DOWN_SECONDS,
                       f"{who}: down at {fmt(r['firstDown'], 0, 1).strip()} s"
                       + (f" ({r['downSpan'][0]:.1f}-{r['downSpan'][1]:.1f})" if r["downSpan"] is not None else "")
                       + f", inside {BOSS_STAND_DOWN_SECONDS:.0f}")
                expect(r["burst"] / hp <= FIGHT_BURST_SHARE,
                       f"{who}: the worst burst inside one dash window {r['burst']:.0f} = {r['burst'] / hp:.0%} of "
                       f"health <= {FIGHT_BURST_SHARE:.0%}")
            elif r["policy"] == "siege":
                expect(r["killSpan"] is not None and r["downs"] == 0,
                       f"{who}: he survives the fight ({r['downs']} downs; the boss falls at "
                       f"{fmt(r['kill'], 0, 1).strip()} s)")
            elif r["policy"] == "storm":
                expect(r["plateLeft"] >= 1 and r["guardsAt"] is None and r["downSpan"] is not None
                       and r["cost"] >= CHASE_COST_BARS * hp,
                       f"{who}: after {r['watched']:.0f} s the plate is whole ({r['plateLeft']:.0%}; {r['warded']:.0f} "
                       f"hits warded), the guard lives, he has been down (first at {fmt(r['firstDown'], 0, 1).strip()} "
                       f"s; {r['downs']} times at worst) and it has cost him {r['cost']:.0f} health at the least (>= "
                       f"{CHASE_COST_BARS:.0f} bars, {CHASE_COST_BARS * hp:.0f}; up to {r['solid']} hits)")
            elif r["policy"] == "stalk":
                expect(r["plateLeft"] >= 1 and r["guardsAt"] is None,
                       f"{who}: after {r['watched']:.0f} s the plate is whole ({r['plateLeft']:.0%}; {r['warded']:.0f} "
                       f"hits warded) and the guard lives: dodging everything gets him nowhere either")
            elif r["slot"] == "melee" and not r["abilities"]:
                expect(r["killSpan"] is not None and lo <= r["killSpan"][0] and r["killSpan"][1] <= hi,
                       f"{who}: the kill takes {fmt(r['kill'], 0, 1).strip()} s"
                       + (f" ({r['killSpan'][0]:.1f}-{r['killSpan'][1]:.1f})" if r["killSpan"] is not None else "")
                       + f", in [{lo:.0f}, {hi:.0f}]")
                expect(r["solid"] == 0 and r["lunges"] == 0,
                       f"{who}: he takes no hit ({r['solid']} of the boss's, {r['lunges']} lunges)")
            elif r["slot"] == "melee":
                expect(r["killSpan"] is not None and r["solid"] == 0,
                       f"{who}: the kill takes {fmt(r['kill'], 0, 1).strip()} s and none of the boss's hits lands")
            else:
                took = (f"the kill takes {r['kill']:.1f} s" if r["kill"] is not None
                        else f"no kill inside {BOSS_SECONDS:.0f} s")
                expect(r["solid"] == 0, f"{who}: none of the boss's hits lands ({took})")
        if f["guarded"]:
            lo_s, hi_s = SIEGE_SHARE
            slammers = {w["name"] for w in f["ways"] if not w["heavy"]}
            for r in boss["rows"]:
                if r["policy"] != "slay":
                    continue
                who = f"{name}, {r['weapon']}" + (" with its ability" if r["abilities"] else "")
                expect(r["brokeAt"] is not None,
                       f"{who}: a way through: the guard falls at {fmt(r['guardsAt'], 0, 1).strip()} s and the plate "
                       f"breaks at {fmt(r['brokeAt'], 0, 1).strip()} s ({r['slams']:.0f} ground slams)")
                if r["abilities"]:
                    continue
                if r["slot"] == "melee" and r["kill"] and r["brokeAt"]:
                    share = r["brokeAt"] / r["kill"]
                    expect(lo_s <= share <= hi_s,
                           f"{who}: the siege is {share:.0%} of the kill, in [{lo_s:.0%}, {hi_s:.0%}]")
                if r["weapon"] == f["melee"] or r["weapon"] in slammers:
                    route = "the ground slam" if r["weapon"] in slammers else "the default melee"
                    expect(r["phase"] is not None and r["phase"] <= PLATE_PHASE_SECONDS
                           and r["gave"] <= PLATE_PHASE_STUDS,
                           f"{who} ({route}): the plate phase lasts {fmt(r['phase'], 0, 1).strip()} s at the most (<= "
                           f"{PLATE_PHASE_SECONDS:.0f}) and the boss gives {r['gave']:.0f} studs of ground in it (<= "
                           f"{PLATE_PHASE_STUDS:.0f})")
                if r["slot"] == "ranged" and not r["bow"]:
                    slowest = r["killSpan"][1] if r["killSpan"] is not None else None
                    expect(slowest is not None and slowest <= RANGED_KILL_SECONDS,
                           f"{who}: a ranged family that is not a bow wins in {fmt(slowest, 0, 1).strip()} s at the "
                           f"slowest (<= {RANGED_KILL_SECONDS:.0f})")
        quiet = boss["quiet"]
        base = next((r for r in boss["rows"] if r["policy"] == "slay" and not r["abilities"]
                     and r["weapon"] == f["melee"]), None)
        if quiet is not None and base is not None and quiet["kill"] and base["kill"]:
            lo_c, hi_c = BOSS_CALL_SHARE
            share = base["kill"] / quiet["kill"] - 1
            expect(lo_c <= share <= hi_c,
                   f"{name}: what it calls lengthens the {f['melee']}'s kill by {share:.0%} ({quiet['kill']:.1f} s "
                   f"without, {base['kill']:.1f} s with), in [{lo_c:.0%}, {hi_c:.0%}]: it matters, it does not decide")


def check_siege(cfg, env, boss, expect):
    """Stop 3: the guard's own hit and tell, and that every loadout has a way through the plates."""
    f = boss["facts"]
    name = f["name"]
    crowd = cfg["crowd"]
    move = cfg["movement"]
    for g in f["guard"]:
        what = f"{name}'s {g['kind']} {g['shape']}"
        expect(g["share"] <= HIT_SHARE_MAX,
               f"{what}: one hit {g['damage']:.0f} = {g['share']:.0%} of health <= {HIT_SHARE_MAX:.0%}")
        expect(g["windup"] - g["need"] >= TELL_MARGIN_SECONDS
               and g["windup"] - g["needThumb"] >= BOSS_THUMB_MARGIN_SECONDS,
               f"{what}: its tell {g['windup']:.2f} s clears a {REACTION_SECONDS:.2f} s reaction by "
               f"{g['windup'] - g['need']:.2f} s (>= {TELL_MARGIN_SECONDS}) and a {BOSS_THUMB_SECONDS:.2f} s thumb by "
               f"{g['windup'] - g['needThumb']:.2f} s (>= {BOSS_THUMB_MARGIN_SECONDS})")
        expect(g["speed"] > f["speed"],
               f"{what}: the {g['kind']} is faster ({g['speed']:.0f}) than {name} backs off ({f['speed']:.0f}): a "
               f"player who chases him is caught by his guard")
    expect(move["slamDamage"] >= crowd["heavyHit"],
           f"{name}: the ground slam ({move['slamDamage']:.0f}) is a heavy hit (>= {crowd['heavyHit']:.0f}): every "
           f"loadout has a way through the guard's plates and his")
    light = [w["name"] for w in f["ways"] if not w["heavy"]]
    slam = next((w for w in f["ways"] if not w["heavy"]), None)
    if slam is not None and slam["guardHits"] is not None and slam["ownHits"] is not None:
        expect(slam["guardHits"][1] <= PLATE_SLAMS,
               f"{name}: the slam breaks a guard's plate in {slam['guardHits'][1]} (<= {PLATE_SLAMS}) and his in "
               f"{slam['ownHits'][1]}, {slam['ownHits'][2]:.0f} s of slams; the families with no heavy hit, which "
               f"need it: {', '.join(light)}")


# ---------------------------------------------------------------------------------------------
# P5 and L1: a level (docs/INTERFACES.md "P5 contracts" -> "Wave 1 — crowd in a mission", and
# "L1 contracts — Forest Road in grey").
#
# The same crowd, brains, shapes and player as the range, seen through a level's difficulty, in
# the level's camps, at the gear the bands are measured at (Combat.json debug.provingGear, 2/1):
#   [scales]   P5 ruling 10 and L1 ruling 23: every body's HP x hpScale (summons too), plates x
#              plateScale, every enemy hit max(round(damage x damageScale), 1), regen =
#              regenShare x MaxHealth; the scales are the played difficulty's;
#   [tier]     P5 rulings 8 and 9: the player's HP loss x Armory.DamageScale of the slot (the slam
#              as melee); heavy hits, plates, interrupts and armour read the tier-1 amount;
#   [health]   P5 ruling 11: the bar is Armory.MaxHp of the gear; ruling 18: solo, a down ends
#              the run, unless the field is already clear;
#   [level]    L1 rulings 1 and 27: a level is an ordered list of stages, `travel` and `camp`
#              (resolve_level mirrors StageFlow.Resolve: a level file that names a mission
#              becomes one camp of all that mission's waves, with the director's breather,
#              merging and a bank at every wave; plan_level mirrors StageFlow.Plan);
#   [road]     the player walks the layout's `route` at movement.walkSpeed, jumps included, his
#              own line (the seed's start offset) beside it; there is no enemy on the road;
#   [trigger]  L1 ruling 9 as the fix round's ruling 1 rewrote it: a camp triggers when his
#              root is inside its whole fenced rectangle (the floor grown by
#              levels.fenceThickness); levels.gateSeconds later the gates close, and a fighter
#              not inside the floor inset by levels.closeInset is put on the camp's entry point;
#              only the next camp can;
#   [camp]     L1 rulings 11 and 13: each camp is its own floor: its rectangle, its spawn
#              points, bursts whose rows step toward its centre, the boss at `boss.at` from its
#              centre. The simulator fights each camp in that camp's own frame (centre = origin);
#   [queue]    P5 ruling 15 and L1 ruling 14: a wave is its groups, in order, as bursts of up to
#              `burst` bodies; a burst rises at the camp's next spawn point (round-robin, one
#              cursor for the whole run) in a grid of pitch `burstSpacing`; bursts are Combat.BurstSeconds apart; a boss rises
#              first, at its own spot; the queue holds while the stage's maxAlive bodies live;
#   [director] P5 ruling 17: tempo from crowd kills (summons included) against spec.total /
#              targetWaveSeconds, set back to 1 with the kill stamps cleared when a camp closes
#              and held at 1 for tempoWarmupSeconds from then. It is kept on every tick of a
#              closed camp, its breathers as well as its fights (StageFlow.Directs: P5's
#              behaviour, restored in the fix round), before that tick's spawns and before
#              Advance is asked, against the wave queued last (through a breather still the wave
#              just cleared). That one value is what the tick's merge, the breather's length at
#              a clear and a finished burst's interval read. A wave that has finished spawning
#              merges the next in when Combat.ShouldMerge says so, only in a stage that merges
#              and never into or out of a boss wave. (The director's extra elite, which reads
#              the tempo when a wave is queued, is not mirrored: no shipped mission or level
#              names an eliteKind, and tools/check_levels.py refuses one in a level file.)
#   [rearm]    at a countdown's end with nobody on his feet the camp is armed again, and
#              triggers when somebody walks in; nothing closes and nothing spawns;
#   [grace]    for levels.closeGraceSeconds after the close, whoever is outside the floor inset
#              by levels.closeInset is still put on the entry point, once per close. (The
#              simulator's player never is: a run reports how often it happened.)
#   [advance]  StageFlow.Advance, row for row (LevelRun.advance): the run cap; the fallen
#              against a clear field; the trigger; the countdown; the close and the first wave;
#              the merge; the clear (threats cleared, the pool banked when the camp is beaten or
#              the stage banks each wave, the downed stood up), then the stage's breather or the
#              director's, or the gates open and the next stage begins, or the run ends cleared;
#   [bank]     L1 ruling 15: only a checkpoint pays. Kills go to a pool; a bank moves the pool to
#              the wallet; whatever ends the run drops what was not banked.
# The player of a whole run reacts to every tell and attacks with the default melee family only
# (no bow, no ability), going for the nearest body. During a camp's countdown he walks on to its
# middle; the player who stands still stops where he triggered it. After a camp he walks from
# where its last body fell to its exit and on.
# ---------------------------------------------------------------------------------------------

MISSIONS_DIR = REPO_ROOT / "src" / "shared" / "Config" / "Missions"
MISSION_FILE = "1_Village.json"
LEVEL_LAYOUT_DIR = REPO_ROOT / "src" / "shared" / "Layouts" / "Levels"
LEVELS_DIR = REPO_ROOT / "src" / "shared" / "Config" / "Levels"
EXPEDITIONS_PATH = REPO_ROOT / "src" / "shared" / "Config" / "Expeditions.json"
MISSION_GEAR_DEFAULT = {"melee": 2, "ranged": 2}
# The Raider Arena's bands (INTERFACES "P5" -> "Balance bands"): the bosses with the default
# sword, a clear of all ten waves by a reacting player (breathers included), a still player in a
# fodder wave, no enemy hit over HIT_SHARE_MAX of the bar, regen close to the range's 10/130.
MISSION_BOSS_SECONDS = {"colossus": (64.0, 90.0), "warlord": (77.0, 101.0)}
MISSION_CLEAR_SECONDS = (600.0, 900.0)
MISSION_STAND_DOWN_SECONDS = (6.0, 12.0)
MISSION_REGEN_SHARE = 10 / 130
MISSION_REGEN_TOLERANCE = 0.10
MISSION_SEEDS = (11, 23, 37)
# Forest Road's bands (INTERFACES "L1" -> "Balance bands", and the fix round's part E). Normal at
# the proving gear; Hard and Brutal at their recommended gear, which is the Studio gear preset
# (Combat.json debug.gearPresets) whose melee tier is the difficulty's recommendedTier: 4/4 and
# 6/6. "One preset below" is the preset before it.
GATE_PYTHON = (3, 12)  # the interpreter the bands are measured on: see interpreter_note
FOREST_LEVEL = "forestRoad"
FOREST_BOSS = "colossus"
# L1b Wave 2: Normal's first clear at the proving gear 2 / 2, from the start point to the
# Colossus's fall, walking included, every seed. The lead's ruling after the build: 6.5-8 min,
# not the contract's 7-8, because Ben's tent pace (one body every 6 s, his own pick) stands and
# no camp mix lifts the clear past 7 on every seed without breaking the Timber band (Ben about
# x1.36 of it: 8.8-10.9 min).
FOREST_CLEAR_SECONDS = (390.0, 480.0)
# L1b-W2-22: what a Normal clear pays a minute, every seed: Timber within 10% of Wave 1's 42;
# cash is reported against Wave 1's 19,800.
FOREST_TIMBER_PER_MINUTE = (37.8, 46.2)
FOREST_CASH_PER_MINUTE_WAVE1 = 19800
# The bow at 2 / 2 (reported for Ben's bow question): the default ranged family alone against
# these kinds, at the boss's spot in the boss room, aiming at the body and at the head.
BOW_KINDS = ("brute", "armoured", "colossus")
BOW_SECONDS = 240.0
TENT_ALONE_SECONDS = 20.0  # a tent with no resident to wait for is watched its stock x every, and this long more
# L1b: standing still in the group of camp A that wakes first, down this long after its wake.
FOREST_STILL_DOWN = (6.0, 12.0)
FOREST_BOSS_SECONDS = {"normal": (64.0, 90.0), "hard": (64.0, 100.0), "brutal": (64.0, 100.0)}
FOREST_HIT_SHARE = {"normal": 0.25, "hard": 0.30, "brutal": 0.30}

# The ideal player takes no hit, so no band on his runs can see damageScale: skill beats gear.
# These do. A player with a human's reaction clears at the recommended gear without going down
# (it fails when a difficulty hits too hard), and the player who never dodges is down before the
# end even at the recommended gear (it fails when it hits too softly).
HUMAN_REACTION_SECONDS = 0.55
# "Clearly beyond the gear below" (the lead's ruling, fix round E4). One preset below the
# recommended gear the human EITHER goes down (or meets the run cap) OR takes this many times as
# long as his slowest clear at the recommended gear; and the Colossus alone is not killed inside
# FOREST_BELOW_BOSS seconds. An under-geared player who plays well and clears slowly is fine.
# The lead's numbers are 1.8 and 135 s / 200 s. Hard's are his. Brutal's are the designer's:
# its two presets are x2.17 apart in melee scale, where Hard's are x3.33 apart, and a third of a
# clear is walking, countdowns and the bursts' own pace, so a slow Brutal clear at 4/4 takes
# x1.5 and its Colossus 196-203 s. 1.8 and 200 s cannot hold there without retuning Brutal to
# the gate.
HUMAN_BELOW_ENDS = ("down", "runCap")
HUMAN_BELOW_SLOWER = {"hard": 1.8, "brutal": 1.4}
FOREST_BELOW_BOSS = {"hard": 135.0, "brutal": 180.0}
FREE = 1e9  # the road has no fence: the half extents of "anywhere"


def luau_round(value):
    """Luau math.round: half away from zero (VitalsService rounds a scaled hit with it)."""
    return math.floor(value + 0.5) if value >= 0 else -math.floor(-value + 0.5)


def load_arena_points(name, key):
    """A named list of `{ x = , z = }` points of Layouts/Arenas/<name>.luau, in order: [(x, z)]."""
    text = (LAYOUT_DIR / f"{name}.luau").read_text(encoding="utf-8")
    names = {m.group(1): float(m.group(2))
             for m in re.finditer(r"^local ([A-Z][A-Z0-9_]*) = (-?\d+(?:\.\d+)?)\s*$", text, re.MULTILINE)}
    block = re.search(key + r" = \{(.*?)\n\t\}", text, re.DOTALL)
    if block is None:
        raise SystemExit(f"sim_range: no {key} in Layouts/Arenas/{name}.luau")

    def number(token):
        token = token.strip()
        negative = token.startswith("-")
        token = token.lstrip("-")
        value = names[token] if token in names else float(token)
        return -value if negative else value

    return [(number(x), number(z)) for x, z in re.findall(r"\{ x = ([\w.-]+), z = ([\w.-]+) \}", block.group(1))]


def load_rim(name):
    """The `enemySpawns` points of Layouts/Arenas/<name>.luau, in order: [(x, z)]."""
    return load_arena_points(name, "enemySpawns")


def arena_as_layout(name, kill_y):
    """LevelGeometry.FromArena (L1 ruling 27): an arena layout as a level layout of one camp
    "arena" at the world origin, that locks (L1b-12). Size, fence and barrier from the arena; no gates; entry =
    playerSpawns[1] (else the lobby pad); exit and start = the lobby pad; spawns = enemySpawns.
    The arena's obstacles are counted, not read: the crowd walks through them."""
    arena = load_arena(name)
    text = (LAYOUT_DIR / f"{name}.luau").read_text(encoding="utf-8")
    pad = arena["pad"]
    try:
        seats = load_arena_points(name, "playerSpawns")
    except SystemExit:
        seats = []
    entry = seats[0] if seats else pad
    height = re.search(r"barrierHeight = ([\d.]+)", text)
    thickness = re.search(r"barrierThickness = ([\d.]+)", text)
    barrier = None
    if height is not None:
        barrier = {"height": float(height.group(1)), "thickness": float(thickness.group(1)) if thickness else 1.0}
    obstacles = re.search(r"obstacles = \{(.*?)\n\t\}", text, re.DOTALL)
    camp = {"id": "arena", "locks": True, "x": 0.0, "y": 0.0, "z": 0.0, "sx": arena["half"][0] * 2,
            "sz": arena["half"][1] * 2, "fence": {"height": arena["wall"]}, "gates": [],
            "entry": {"x": entry[0], "z": entry[1]}, "exit": {"x": pad[0], "z": pad[1]},
            "spawns": [{"x": x, "z": z} for x, z in load_rim(name)],
            "obstacleCount": len(re.findall(r"\bsx = ", obstacles.group(1))) if obstacles else 0,
            # How tall its cover is, for tools/check_levels.py's note: nothing here stands on it.
            "obstacleTops": [float(top) for top in re.findall(r"\bsy = ([\d.]+)", obstacles.group(1))] if obstacles else []}
    return {"version": 1, "arena": name, "start": {"x": pad[0], "y": 0.0, "z": pad[1]}, "killY": kill_y,
            "barrier": barrier, "camps": [camp], "blocks": [], "secrets": [], "route": []}


def load_level_layout(name, rescue_below):
    """Catalog.GetLevelLayout, and for a file that names an `arena` the adapter of ruling 27
    (WaveService: LevelGeometry.FromArena(arena, -player.rescue.below))."""
    layout = load_config(LEVEL_LAYOUT_DIR / f"{name}.json")
    if layout.get("arena"):
        return arena_as_layout(layout["arena"], -rescue_below)
    return layout


def is_catalog_name(stem):
    """Catalog reads a module of Config/Levels (and of Config/Missions) only when its name begins
    with digits and an underscore: string.match(name, "^%d+_")."""
    return re.match(r"\d+_", stem) is not None


def load_level_files():
    """The level files Catalog reads, Config/Levels/<n>_<Name>.json, in Catalog.GetLevelIds'
    order: by the number, then by the name. A file named otherwise is not a level to the game,
    so it is none here (tools/check_levels.py refuses it by name)."""
    paths = [path for path in LEVELS_DIR.glob("*.json") if is_catalog_name(path.stem)]
    paths.sort(key=lambda path: (int(re.match(r"\d+", path.stem).group()), path.stem))
    return [load_config(path) for path in paths]


def gear_max_hp(armory, gear):
    """Armory.MaxHp of a gear with no Ascension."""
    total = armory["baseHp"]
    for slot in ("melee", "ranged"):
        tier = gear[slot]
        slot_def = armory["slots"][slot]
        total += slot_def["starter"]["hp"] if tier <= 0 else slot_def["tiers"][tier - 1]["hp"]
    return total


def mission_gear():
    """Combat.json debug.provingGear (P5 ruling 12), or the contract's default 2/1."""
    try:
        gear = load_config(COMBAT_PATH)["debug"].get("provingGear")
    except (FileNotFoundError, KeyError):
        gear = None
    gear = gear or MISSION_GEAR_DEFAULT
    return {"melee": gear["melee"], "ranged": gear["ranged"]}


def resolve_level(file, mission, run_cap, first_difficulty="normal"):
    """StageFlow.Resolve. A file with no `mission` is the level as it stands (None when it lacks
    stages, difficulties or a crowd block), under its own run cap when it names one over 0 and
    under the director's otherwise, with its `camps` (the residents, L1b) or none. A file that
    names a mission borrows that mission's crowd block and becomes one camp "arena" of all its
    waves: the mission's material, target and targetWaveSeconds; its one difficulty is
    `first_difficulty` (the first of Expeditions.json `difficulties`, which the map offers for a
    level that names none) with the block's three scales; the director's breather; merging; no
    residents. Nothing banks in either (L1b-15): every kill is paid as it falls."""
    if not file.get("mission"):
        if not file.get("stages") or not file.get("difficulties") or not file.get("crowd"):
            return None
        own = file.get("runCapSeconds") or 0
        return {"version": file["version"], "id": file["id"], "name": file["name"], "layout": file["layout"],
                "mission": None, "material": file.get("material") or "", "targetMinutes": file.get("targetMinutes") or 0,
                "runCapSeconds": own if own > 0 else run_cap, "difficulties": file["difficulties"],
                "crowd": file["crowd"], "stages": file["stages"], "camps": file.get("camps") or []}
    block = mission.get("crowd") if mission is not None else None
    if block is None or first_difficulty is None:
        return None
    only = {"hpScale": block["hpScale"], "damageScale": block["damageScale"], "plateScale": block["plateScale"],
            "countMult": 1, "rewardMult": 1, "recommendedTier": file.get("recommendedTier") or 0}
    camp = {"kind": "camp", "name": file["name"], "zone": "arena", "waves": block["waves"],
            "targetWaveSeconds": mission["targetWaveSeconds"], "breatherSeconds": None, "merge": True,
            "maxAlive": None}
    return {"version": file["version"], "id": file["id"], "name": file["name"], "layout": file["layout"],
            "mission": file["mission"], "material": mission["material"], "targetMinutes": mission["targetMinutes"],
            "runCapSeconds": run_cap, "difficulties": {first_difficulty: only},
            "crowd": {"regenShare": block["regenShare"], "maxAlive": block["maxAlive"], "burst": block["burst"],
                      "burstSpacing": block["burstSpacing"], "eliteKind": block.get("eliteKind"),
                      "rewards": block["rewards"]},
            "stages": [camp], "camps": []}


def whole(value):
    """Is `value` a whole number of at least 1 (an int, or a float with no fraction)?"""
    return (isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 1
            and float(value).is_integer())


def over_zero(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0


def is_num(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


# The `levels` numbers of Combat.json a run reads: StageFlow.Validate names every one that is
# missing, and the start then answers "unavailable". L1b adds three.
LEVEL_RULES_NEEDED = ("gateSeconds", "triggerBelow", "triggerHeight", "closeInset", "closeGraceSeconds",
                      "crowdCeiling", "fenceThickness", "startSpacing", "boxMargin", "checkpointReach",
                      "walletSendSeconds")
TENT_KEYS = ("x", "y", "z", "sx", "sy", "sz", "radius")  # StageFlow's NEEDED.tent
POSTURES = ("guard", "patrol", "fire")  # a layout spot's postures (a tent's group is made, never placed)
CB_POSTURES = ("guard", "patrol", "fire", "tent")  # CampBrain's POSTURES (L1b-W2-6)


def level_problems(level, layout, rules=None, kinds=None, ranks=None, crowd_max=None):
    """The fix round's ruling 6, as StageFlow.Validate reads a resolved level: zero and empty
    mean the same on both sides. One line per problem: a maxAlive that is not an integer of at
    least 1 (the level's, or a camp's own), a burst under 1, a camp's targetWaveSeconds of 0 or
    less (or none), a breatherSeconds under 0, a camp with no wave; and, when `rules` (Combat.json
    `levels`) is given, each of the numbers a run reads that it lacks. With `kinds` (and `ranks`
    and `crowd_max`) also Validate's L1b lines (camp_level_problems). Nothing here falls back on
    a number with `or`: Luau's 0 is not Python's. (A key of the level file that is missing
    altogether is a problem to Validate and a KeyError to these tools. A block or an obstacle
    with a size of 0 or less is LevelGeometry.Pieces' to refuse, and tools/check_levels.py's.)"""
    problems = []
    if rules is not None:
        lacks = [key for key in LEVEL_RULES_NEEDED if not is_num(rules.get(key))]
        if lacks:
            problems.append("Combat.json lacks " + ", ".join(f"levels.{key}" for key in lacks))
    crowd = level["crowd"]
    if not whole(crowd.get("maxAlive")):
        problems.append(f"crowd.maxAlive {crowd.get('maxAlive')} is not an integer of at least 1")
    burst = crowd.get("burst")
    if not over_zero(burst) or burst < 1:
        problems.append(f"crowd.burst {burst}: a burst is at least 1 body")
    for index, stage in enumerate(level["stages"], 1):
        if stage["kind"] != "camp":
            continue
        where = f"stage {index} (\"{stage.get('name')}\")"
        if not stage.get("waves"):
            problems.append(f"{where} has no wave")
        if not over_zero(stage.get("targetWaveSeconds")):
            problems.append(f"{where}: targetWaveSeconds {stage.get('targetWaveSeconds')} is not over 0")
        if stage.get("maxAlive") is not None and not whole(stage["maxAlive"]):
            problems.append(f"{where}: maxAlive {stage['maxAlive']} is not an integer of at least 1")
        rest = stage.get("breatherSeconds")
        if rest is not None and (not is_num(rest) or rest < 0):
            problems.append(f"{where}: breatherSeconds {rest} is not a time")
    if kinds is not None:
        camp_level_problems(level, layout, rules or {}, kinds, ranks or {}, crowd_max, problems)
    return problems


def camp_index(layout, camp_id):
    """StageFlow.campIndex: (the camp's place in layout.camps, 1-based, its floor index; the camp),
    or (0, None)."""
    for index, camp in enumerate(layout["camps"], 1):
        if camp["id"] == camp_id:
            return index, camp
    return 0, None


def spot_of(camp, spot_id):
    return next((spot for spot in camp.get("spots") or [] if spot.get("id") == spot_id), None)


def fielded_units(units, rank, ranks):
    """StageFlow.fieldedUnits (L1b-10): the units of a resident group fielded at `rank`, in the
    file's order, and their bodies. A unit with no minDifficulty is fielded; one whose
    minDifficulty is no difficulty never is. countMult and the party never count."""
    fielded = []
    bodies = 0
    for unit in units:
        needs = unit.get("minDifficulty")
        needs_rank = ranks.get(needs) if needs is not None and ranks is not None else None
        if needs is not None and (needs_rank is None or needs_rank > rank):
            continue
        fielded.append({"kind": unit["kind"], "count": unit["count"]})
        bodies += unit["count"]
    return fielded, bodies


def groups_of(level, layout, rank, ranks):
    """StageFlow.groupsOf: one CampGroupDef per resident group at `rank`, in the level file's
    order (its camps, then their groups), and each layout camp's residents by its id. A camp the
    layout lacks, a spot its camp lacks and a group whose units all drop are left out."""
    groups = []
    residents = {}
    for config in level.get("camps") or []:
        floor, camp = camp_index(layout, config.get("id"))
        if camp is None:
            continue
        for group in config.get("residents") or []:
            spot = spot_of(camp, group.get("spot"))
            units, bodies = fielded_units(group.get("units") or [], rank, ranks)
            if spot is None or not units:
                continue
            groups.append({
                "id": f"{camp['id']}.{spot['id']}", "camp": camp["id"], "floor": floor, "floorY": camp["y"],
                "rect": {"x": camp["x"], "z": camp["z"], "hx": camp["sx"] / 2, "hz": camp["sz"] / 2},
                "posture": spot["posture"], "points": [(p["x"], camp["y"], p["z"]) for p in spot["points"]],
                "yaw": (spot.get("facing") or 0) * (math.pi / 180.0), "radius": spot.get("radius") or 0,
                "held": camp.get("locks") is True, "units": units})
            residents[camp["id"]] = residents.get(camp["id"], 0) + bodies
    return groups, residents


def tent_door(block, x, z, clear):
    """LevelGeometry.TentDoor (the fix round's B-4): where a tent body steps out on its way to the
    ring post at (x, z): on the line from the marker's centre to the post, `clear` past the
    footprint's edge (negative = 0), never past the post; a post at the centre is its own door."""
    dx, dz = x - block["x"], z - block["z"]
    distance = math.sqrt(dx * dx + dz * dz)
    if not distance > 1e-6:
        return x, z
    ux, uz = dx / distance, dz / distance
    edge = math.inf
    if abs(ux) > 1e-9:
        edge = min(edge, block["sx"] / 2 / abs(ux))
    if abs(uz) > 1e-9:
        edge = min(edge, block["sz"] / 2 / abs(uz))
    out = min(edge + max(clear, 0), distance)
    return block["x"] + ux * out, block["z"] + uz * out


def tents_of(level, layout, rank, ranks, crowd_kinds=None):
    """StageFlow.tentsOf (L1b-W2-6): one PlanTent per open camp of the layout, in its order, whose
    camps entry carries a tent stock and whose layout camp has a tent block, with a stock left at
    `rank` (minDifficulty; never countMult); and each such camp's stock by its id. A tent is one
    group of its camp, posture "tent", on the ring round its marker: kinds[k] stands on posts[k]
    and steps out of the marker at doors[k] (B-4: its kind's radius clear of the wall, read from
    `crowd_kinds`; on the wall without it)."""
    tents = []
    stocks = {}
    configs = level.get("camps") or []
    for floor, camp in enumerate(layout["camps"], 1):
        config = next((c for c in configs if c.get("id") == camp["id"]), None)
        tent = config.get("tent") if config is not None else None
        block = camp.get("tent")
        if tent is None or block is None or camp.get("locks") is True:
            continue
        units, _bodies = fielded_units(tent.get("units") or [], rank, ranks)
        kinds = [unit["kind"] for unit in units for _ in range(unit["count"])]
        if not kinds:
            continue
        defn = {"id": f"{camp['id']}.tent", "camp": camp["id"], "floor": floor, "floorY": camp["y"],
                "rect": {"x": camp["x"], "z": camp["z"], "hx": camp["sx"] / 2, "hz": camp["sz"] / 2},
                "posture": "tent", "points": [(block["x"], camp["y"], block["z"])], "yaw": 0.0,
                "radius": block["radius"], "held": False, "units": units}
        posts = cb_posts(defn, len(kinds))
        doors = []
        for kind, post in zip(kinds, posts):
            body = crowd_kinds.get(kind) if crowd_kinds is not None else None
            x, z = tent_door(block, post["at"][0], post["at"][2], body["radius"] if body is not None else 0)
            doors.append((x, post["at"][1], z))
        tents.append({"zone": floor, "def": defn, "kinds": kinds, "posts": posts, "doors": doors,
                      "every": tent["every"]})
        stocks[camp["id"]] = len(kinds)
    return tents, stocks


def boss_reserve(level, kinds):
    """StageFlow.BossReserve (L1b-W2-5): over the camp stages' bosses, the largest 1 + the largest
    `count` of its kind's summon attacks (a kind `kinds` lacks, or no `kinds`: 1); 0 for no boss."""
    reserve = 0
    for stage in level.get("stages") or []:
        if stage.get("kind") != "camp":
            continue
        for wave in stage.get("waves") or []:
            boss = wave.get("boss")
            if not isinstance(boss, dict):
                continue
            kind = kinds.get(boss.get("kind")) if kinds is not None else None
            calls = max([0] + [a.get("count") or 0 for a in (kind or {}).get("attacks") or [] if a["shape"] == "summon"])
            reserve = max(reserve, 1 + calls)
    return reserve


def population_of(residents, tents, caps, reserve):
    """StageFlow.populationOf, L1b-W2-5's left side: every resident, every tent's stock (`tents`,
    the sum), the most room a boss room's cap leaves over its own residents, and the boss reserve."""
    room = 0
    for camp_id, cap in caps.items():
        room = max(room, cap - residents.get(camp_id, 0))
    return sum(residents.values()) + tents + room + reserve


def camp_level_problems(level, layout, rules, kinds, ranks, crowd_max, problems):
    """StageFlow.campProblems, Validate's L1b lines, appended to `problems`: the numbers the run
    reads; which camps lock and which stage names them; every spot of every layout camp; the
    level's `camps` entries, their groups and units; then, only when nothing at all is wrong so
    far (as in the Luau, which reads the shared list), every group's posts on its floor at the
    highest difficulty, a boss room's residents under its cap and the population gate at every
    difficulty."""
    def problem(text):
        problems.append(text)

    for key in ("checkpointReach", "walletSendSeconds"):
        value = rules.get(key)
        if is_num(value) and not value > 0:
            problem(f"levels.{key} is {value}, not above 0")
    bonus = (level.get("crowd") or {}).get("clearBonus")
    if bonus is not None and (not isinstance(bonus, dict) or not finite(bonus.get("share"))
                              or bonus["share"] < 0 or bonus["share"] > 1):
        problem("crowd.clearBonus needs a share from 0 to 1")
    rewards = (level.get("crowd") or {}).get("rewards") or {}

    def check_kind(where, kind):
        if kind not in kinds:
            problem(f"{where} names the unknown kind {kind}")
        if kind not in rewards:
            problem(f"{where} fields {kind}, which rewards does not price")

    camps = layout["camps"]
    named = {}
    for index, stage in enumerate(level["stages"], 1):
        _floor, camp = camp_index(layout, stage.get("zone") if stage["kind"] == "camp" else None)
        if camp is not None:
            named[camp["id"]] = named.get(camp["id"], 0) + 1
            if camp.get("locks") is not True:
                problem(f"stage {index} names camp {camp['id']}, which does not lock")
    for camp in camps:
        if camp.get("locks") is True and named.get(camp["id"], 0) != 1:
            problem(f"camp {camp['id']} locks and is named by {named.get(camp['id'], 0)} stages")
    for camp in camps:
        block = camp.get("tent")
        if block is not None:
            if not isinstance(block, dict) or not all(finite(block.get(key)) for key in TENT_KEYS):
                problem(f"camp {camp['id']}: its tent needs a finite {', '.join(TENT_KEYS)}")
            elif not (block["sx"] > 0 and block["sy"] > 0 and block["sz"] > 0 and block["radius"] > 0):
                problem(f"camp {camp['id']}: its tent's size and radius must be above 0")
            elif not (abs(block["x"] - camp["x"]) <= camp["sx"] / 2 and abs(block["z"] - camp["z"]) <= camp["sz"] / 2):
                problem(f"camp {camp['id']}: its tent's centre lies off the floor")
        spots = camp.get("spots")
        if spots is None:
            continue
        seen = set()
        for index, spot in enumerate(spots, 1):
            here = f"camp {camp['id']} spot {index}"
            sid = spot.get("id")
            if not isinstance(sid, str) or sid == "":
                problem(f"{here} has no id")
            elif sid in seen:
                problem(f"camp {camp['id']}: the spot id {sid} is used twice")
            else:
                seen.add(sid)
            posture = spot.get("posture")
            if posture not in POSTURES:
                problem(f"{here}: posture {posture} is not guard, patrol or fire")
            points = spot.get("points")
            if not isinstance(points, list) or not points:
                problem(f"{here} has no points")
                points = []
            for point in points:
                if not is_num(point.get("x")) or not is_num(point.get("z")):
                    problem(f"{here}: a point lacks x or z")
            if posture == "guard" and not is_num(spot.get("facing")):
                problem(f"{here}: a guard spot has no facing")
            elif posture == "patrol" and len(points) < 2:
                problem(f"{here}: a patrol of {len(points)} points")
            elif posture == "fire" and len(points) != 1:
                problem(f"{here}: a fire of {len(points)} points")
            if posture == "fire" and not (is_num(spot.get("radius")) and spot["radius"] > 0):
                problem(f"{here}: a fire's radius is {spot.get('radius')}")
    def unit_problems(at, units):
        if not isinstance(units, list) or not units:
            problem(f"{at} has no units")
            return
        for uindex, unit in enumerate(units, 1):
            which = f"{at} unit {uindex}"
            if not isinstance(unit.get("kind"), str):
                problem(f"{which} has no kind")
            else:
                check_kind(which, unit["kind"])
            if not whole(unit.get("count")):
                problem(f"{which}: count {unit.get('count')} is not a whole number of at least 1")
            needs = unit.get("minDifficulty")
            if needs is not None and needs not in ranks:
                problem(f"{which}: minDifficulty {needs} is no difficulty")

    entries = set()
    for index, config in enumerate(level.get("camps") or [], 1):
        cid = config.get("id")
        _floor, camp = camp_index(layout, cid if isinstance(cid, str) else None)
        here = f"camps entry {index} ({cid})"
        if camp is None:
            problem(f"{here} names a camp the layout lacks")
        elif cid in entries:
            problem(f"two camps entries for camp {cid}")
        if isinstance(cid, str):
            entries.add(cid)
        if not isinstance(config.get("name"), str) or config["name"] == "":
            problem(f"{here} has no name")
        tent = config.get("tent")
        if tent is not None:
            if not isinstance(tent, dict):
                problem(f"{here}: its tent is not a table")
            else:
                if not (finite(tent.get("every")) and tent["every"] > 0):
                    problem(f"{here}: its tent's every is {tent.get('every')}, not a time above 0")
                unit_problems(f"{here} tent", tent.get("units"))
                if camp is not None and camp.get("locks") is True:
                    problem(f"{here}: camp {camp['id']} locks, and a boss room's tent has no stock")
                elif camp is not None and camp.get("tent") is None:
                    problem(f"{here} has a tent stock, and camp {camp['id']} has no tent block")
        residents = config.get("residents")
        if not isinstance(residents, list):
            problem(f"{here} has no residents list")
            continue
        for gindex, group in enumerate(residents, 1):
            at = f"{here} resident group {gindex}"
            if camp is not None and spot_of(camp, group.get("spot")) is None:
                problem(f"{at} names the spot {group.get('spot')}, which camp {camp['id']} lacks")
            unit_problems(at, group.get("units"))
    if problems:
        return
    # The posts at every difficulty the level offers, the highest first (the fix round's B-2: a
    # difficulty that fields fewer bodies stands a ring's posts at other bearings); a group is told
    # of once, at the highest difficulty it fails at.
    told = set()
    for rank in sorted({ranks.get(name, 0) for name in level["difficulties"]}, reverse=True):
        groups, _residents = groups_of(level, layout, rank, ranks)
        for defn in groups:
            if defn["id"] in told:
                continue
            members = sum(unit["count"] for unit in defn["units"])
            widest = max((kinds[unit["kind"]]["radius"] if unit["kind"] in kinds else 0 for unit in defn["units"]),
                         default=0)
            if defn["posture"] == "guard" and members > len(defn["points"]):
                told.add(defn["id"])
                problem(f"group {defn['id']} holds {members} guards and has {len(defn['points'])} posts")
                continue
            _floor, camp = camp_index(layout, defn["camp"])
            for index, post in enumerate(cb_posts(defn, members), 1):
                x, _y, z = post["at"]
                if camp is not None and not (abs(x - camp["x"]) <= camp["sx"] / 2 - widest
                                             and abs(z - camp["z"]) <= camp["sz"] / 2 - widest):
                    told.add(defn["id"])
                    problem(f"group {defn['id']}: post {index} lies off its floor less {widest}")
                    break
        tents, _stocks = tents_of(level, layout, rank, ranks)
        for tent in tents:
            if tent["def"]["id"] in told:
                continue
            widest = max((kinds[kind]["radius"] if kind in kinds else 0 for kind in tent["kinds"]), default=0)
            _floor, camp = camp_index(layout, tent["def"]["camp"])
            for index, post in enumerate(tent["posts"], 1):
                x, _y, z = post["at"]
                if camp is not None and not (abs(x - camp["x"]) <= camp["sx"] / 2 - widest
                                             and abs(z - camp["z"]) <= camp["sz"] / 2 - widest):
                    told.add(tent["def"]["id"])
                    problem(f"group {tent['def']['id']}: ring post {index} lies off its floor less {widest}")
                    break
    reserve = boss_reserve(level, kinds)
    crowd_max = crowd_max if crowd_max is not None else math.inf
    for name in level["difficulties"]:
        _groups, residents = groups_of(level, layout, ranks.get(name, 0), ranks)
        _tents, tent_stocks = tents_of(level, layout, ranks.get(name, 0), ranks)
        for camp_id, stock in tent_stocks.items():
            if stock > 0 and residents.get(camp_id, 0) == 0:
                problem(f"on {name} camp {camp_id} has a tent stock of {stock} and no residents")
        caps = {}
        for stage in level["stages"]:
            _floor, camp = camp_index(layout, stage.get("zone") if stage["kind"] == "camp" else None)
            cap = stage.get("maxAlive") if stage.get("maxAlive") is not None else level["crowd"].get("maxAlive")
            if camp is None or not is_num(cap):
                continue
            caps[camp["id"]] = cap
            if residents.get(camp["id"], 0) >= cap:
                problem(f"on {name} camp {camp['id']} holds {residents.get(camp['id'], 0)} residents, not fewer "
                        f"than its stage's maxAlive ({cap})")
        population = population_of(residents, sum(tent_stocks.values()), caps, reserve)
        if population > crowd_max:
            problem(f"on {name} the population is {population}, over crowd.maxAlive ({crowd_max})")


def plan_level(level, layout, difficulty, rules, ranks=None, kinds=None):
    """StageFlow.Plan: the level as the run walks it, at one difficulty (L1b). A zone for every
    camp of the layout, in its order (its floor index); the stages (a camp stage names a locking
    zone); every resident group (`ranks` decides the minDifficulty units; without it none is
    fielded, as in the Luau); the population. None for a difficulty the level lacks, a camp stage
    whose zone the layout lacks, or a stage's camp whose entry is not inside its floor inset by
    levels.closeInset. A zone's rectangles are (x, z, hx, hz); its trigger is its whole fenced
    rectangle; `inner` is the floor inset by closeInset; its points are (x, z); `checkpoint` is
    (x, z) or None; an open camp with no entry or exit has its centre for each."""
    if difficulty not in level["difficulties"]:
        return None
    rank = (ranks.get(difficulty) or 0) if ranks is not None else 0
    groups, residents = groups_of(level, layout, rank, ranks)
    tents, tent_stocks = tents_of(level, layout, rank, ranks, kinds)
    by_kind = {}  # each camp's stock by kind (L1b-W2-21): its residents, then its tent's
    for defn in groups:
        stock = by_kind.setdefault(defn["camp"], {})
        for unit in defn["units"]:
            stock[unit["kind"]] = stock.get(unit["kind"], 0) + unit["count"]
    for tent in tents:
        stock = by_kind.setdefault(tent["def"]["camp"], {})
        for kind in tent["kinds"]:
            stock[kind] = stock.get(kind, 0) + 1
    names = {}
    for stage in level["stages"]:
        zid = stage.get("zone")
        if stage["kind"] == "camp" and zid is not None and zid not in names and stage.get("name") is not None:
            names[zid] = stage["name"]
    for config in level.get("camps") or []:
        if isinstance(config.get("name"), str) and config["name"] != "":
            names[config["id"]] = config["name"]
    zones = []
    by_id = {}
    grow = rules["fenceThickness"]
    keep = rules["closeInset"] if rules.get("closeInset") is not None else 0
    for index, camp in enumerate(layout["camps"], 1):
        hx, hz = camp["sx"] / 2, camp["sz"] / 2
        centre = {"x": camp["x"], "z": camp["z"]}
        entry, leave = camp.get("entry") or centre, camp.get("exit") or centre
        mark = camp.get("checkpoint")
        zone = {"id": camp["id"], "floor": index, "locks": camp.get("locks") is True,
                "name": names.get(camp["id"], camp["id"]),
                "checkpoint": (mark["x"], mark["z"]) if mark is not None else None,
                "residents": residents.get(camp["id"], 0), "stock": dict(by_kind.get(camp["id"], {})),
                "tentStock": tent_stocks.get(camp["id"], 0), "floorY": camp["y"],
                "rect": (camp["x"], camp["z"], hx, hz),
                "inner": (camp["x"], camp["z"], max(hx - keep, 0), max(hz - keep, 0)),
                "trigger": (camp["x"], camp["z"], max(hx + grow, 0), max(hz + grow, 0)),
                "entry": (entry["x"], entry["z"]), "exit": (leave["x"], leave["z"]),
                "spawns": [(p["x"], p["z"]) for p in camp.get("spawns") or []]}
        zones.append(zone)
        by_id[camp["id"]] = zone
    stages = []
    caps = {}
    for stage in level["stages"]:
        if stage["kind"] != "camp":
            stages.append({"kind": "travel", "name": stage["name"], "zone": None, "waves": 0, "boss": {}, "defs": [],
                           "breatherSeconds": None, "merge": False, "targetWaveSeconds": 0, "maxAlive": 0})
            continue
        zone = by_id.get(stage.get("zone"))
        if zone is None:
            return None
        _ix, _iz, keep_x, keep_z = zone["inner"]
        if abs(zone["entry"][0] - zone["rect"][0]) > keep_x or abs(zone["entry"][1] - zone["rect"][1]) > keep_z:
            return None
        waves = stage.get("waves") or []
        cap = stage["maxAlive"] if stage.get("maxAlive") is not None else level["crowd"]["maxAlive"]
        caps[zone["id"]] = cap
        stages.append({"kind": "camp", "name": stage["name"], "zone": zone, "waves": len(waves),
                       "boss": {index: True for index, wave in enumerate(waves, 1) if wave.get("boss")},
                       "defs": waves, "breatherSeconds": stage.get("breatherSeconds"),
                       "merge": stage.get("merge") is True,
                       "targetWaveSeconds": (stage["targetWaveSeconds"]
                                             if stage.get("targetWaveSeconds") is not None else 0),
                       "maxAlive": cap})
    start = layout["start"]
    return {"levelId": level["id"], "difficulty": difficulty, "start": (start["x"], start["z"]),
            "startY": start["y"], "killY": layout["killY"], "camps": len(zones), "stages": stages, "zones": zones,
            "groups": groups, "tents": tents,
            "population": population_of(residents, sum(tent_stocks.values()), caps, boss_reserve(level, kinds))}


def burst_point(at, size, index, spacing):
    """StageFlow.BurstPoint in the camp's own frame (its centre is the origin): the `index`-th
    body (0-based) of a burst of `size` at spawn point `at`. A grid of pitch `spacing`:
    ceil(sqrt(size)) columns across the line to the camp's centre, centred on the spawn point,
    its rows stepping toward the centre."""
    cx, cz = at
    reach = math.hypot(cx, cz)
    ix, iz = (-cx / reach, -cz / reach) if reach > 1e-3 else (0.0, 1.0)
    ax, az = -iz, ix
    columns = max(math.ceil(math.sqrt(size)), 1)
    row, column = index // columns, index % columns
    across = (column - (columns - 1) / 2) * spacing
    inward = row * spacing
    return cx + ax * across + ix * inward, cz + az * across + iz * inward


# ---------------------------------------------------------------------------------------------
# CampBrain (L1b): the mirror, rule for rule, of src/combat/server/Services/CampBrain.luau.
# tools/check_stage_mirror.py holds every function here to the Luau on grids and on the shipped
# files. Points are (x, y, z) tuples; a group, a post and a resident are dicts with the Luau's keys.
# ---------------------------------------------------------------------------------------------

CB_TIME_EPSILON = 1e-6  # CampBrain.TIME_EPSILON
CB_CONE_NEAR = 0.001  # CampBrain.CONE_NEAR
CB_CONE_EPSILON_DEGREES = 1e-6  # CampBrain.CONE_EPSILON_DEGREES
CB_ARC_EPSILON = 1e-9  # CampBrain.ARC_EPSILON
CB_POSTURE_KEYS = ("sight", "cone", "rise")
CB_RULE_KEYS = ("sightBelow", "sightAbove", "chaseMargin", "leashSeconds", "homePace", "patrolPace", "homeTolerance",
                "engagedHoldSeconds", "joinFactor", "dormantRadius")


def finite(value):
    return is_num(value) and math.isfinite(value)


def flat_distance(a, b):
    dx, dz = b[0] - a[0], b[2] - a[2]
    return math.sqrt(dx * dx + dz * dz)


def cb_problems(rules):
    """CampBrain.Problems: one line per key of Combat.json `camps` that is missing, not a finite
    number or negative; a sight of 0 or less; a cone outside (0, 360]; a homeTolerance or
    joinFactor of 0 or less; a dormantRadius not above every posture's sight. None = one line."""
    if not isinstance(rules, dict):
        return ["camps: missing"]
    problems = []
    for posture in CB_POSTURES:
        entry = rules.get(posture)
        if not isinstance(entry, dict):
            problems.append(f"camps.{posture}: missing")
            continue
        for key in CB_POSTURE_KEYS:
            value = entry.get(key)
            if not finite(value):
                problems.append(f"camps.{posture}.{key}: missing or not a finite number")
            elif value < 0:
                problems.append(f"camps.{posture}.{key}: negative ({value})")
            elif key == "sight" and value <= 0:
                problems.append(f"camps.{posture}.sight: must be above 0 ({value})")
            elif key == "cone" and (value <= 0 or value > 360):
                problems.append(f"camps.{posture}.cone: must be in (0, 360] ({value})")
    for key in CB_RULE_KEYS:
        value = rules.get(key)
        if not finite(value):
            problems.append(f"camps.{key}: missing or not a finite number")
        elif value < 0:
            problems.append(f"camps.{key}: negative ({value})")
        elif key in ("homeTolerance", "joinFactor") and value <= 0:
            problems.append(f"camps.{key}: must be above 0 ({value})")
    radius = rules.get("dormantRadius")
    if finite(radius):
        for posture in CB_POSTURES:
            entry = rules.get(posture)
            sight = entry.get("sight") if isinstance(entry, dict) else None
            if finite(sight) and radius <= sight:
                problems.append(f"camps.dormantRadius: must be above camps.{posture}.sight ({radius} <= {sight})")
    return problems


def cb_new_group(defn, now):
    return {"def": defn, "state": "rest", "held": defn.get("held") is True, "since": now, "quietSince": now,
            "hit": False, "inPlay": {}}


def cb_posture(defn, rules):
    posture = defn["posture"]
    return rules[posture] if posture in ("patrol", "fire", "tent") else rules["guard"]


def cb_yaw_toward(dx, dz):
    return math.atan2(-dx, -dz)


def cb_posts(defn, count):
    """CampBrain.Posts: where `count` members stand at rest (every post on the floor). guard: k on
    points[k]; patrol: evenly by arc length round the closed loop from points[1], each walking to
    the end of the leg it stands on and facing it; fire: evenly round the circle, the first north
    of the centre, each facing the centre; tent (L1b-W2-6): the fire's circle, each facing away."""
    points = defn["points"]
    floor_y = defn["floorY"]
    n = len(points)
    posts = []
    if n == 0:
        centre = (defn["rect"]["x"], floor_y, defn["rect"]["z"])
        return [{"at": centre, "yaw": defn["yaw"], "leg": 0} for _ in range(count)]
    if defn["posture"] == "patrol":
        total = 0.0
        for index in range(n):
            total += flat_distance(points[index], points[(index + 1) % n])
        for k in range(1, count + 1):
            s = total * (k - 1) / count
            at = (points[0][0], floor_y, points[0][2])
            leg = 2 if n > 1 else 1
            walked = 0.0
            for index in range(1, n + 1):
                frm, to = points[index - 1], points[index % n]
                length = flat_distance(frm, to)
                if length > CB_ARC_EPSILON and s < walked + length - CB_ARC_EPSILON:
                    share = (s - walked) / length
                    at = (frm[0] + (to[0] - frm[0]) * share, floor_y, frm[2] + (to[2] - frm[2]) * share)
                    leg = index % n + 1
                    break
                walked += length
            goal = points[leg - 1]
            dx, dz = goal[0] - at[0], goal[2] - at[2]
            yaw = cb_yaw_toward(dx, dz) if dx * dx + dz * dz > CB_ARC_EPSILON else defn["yaw"]
            posts.append({"at": at, "yaw": yaw, "leg": leg})
    elif defn["posture"] in ("fire", "tent"):
        centre = points[0]
        turn = math.pi if defn["posture"] == "fire" else 0
        for k in range(1, count + 1):
            theta = 2 * math.pi * (k - 1) / count
            at = (centre[0] - math.sin(theta) * defn["radius"], floor_y, centre[2] - math.cos(theta) * defn["radius"])
            yaw = theta + turn
            while yaw > math.pi:
                yaw -= 2 * math.pi
            while yaw <= -math.pi:
                yaw += 2 * math.pi
            posts.append({"at": at, "yaw": yaw, "leg": 0})
    else:
        for k in range(1, count + 1):
            point = points[(k - 1) % n]
            posts.append({"at": (point[0], floor_y, point[2]), "yaw": defn["yaw"], "leg": 0})
    return posts


def cb_in_band(defn, root, rules):
    return defn["floorY"] - rules["sightBelow"] <= root[1] <= defn["floorY"] + rules["sightAbove"]


def cb_sees(defn, member, target, rules):
    """CampBrain.Sees: distance only, no ray; a guard's cone about its post's facing."""
    root = target["root"]
    if not cb_in_band(defn, root, rules):
        return False
    posture = cb_posture(defn, rules)
    dx, dz = root[0] - member["at"][0], root[2] - member["at"][2]
    distance = math.sqrt(dx * dx + dz * dz)
    if distance > posture["sight"]:
        return False
    if posture["cone"] >= 360 or distance < CB_CONE_NEAR:
        return True
    yaw = member["post"]["yaw"]
    cosine = (-math.sin(yaw) * dx - math.cos(yaw) * dz) / distance
    angle = math.acos(min(max(cosine, -1.0), 1.0)) * (180.0 / math.pi)  # Luau's math.deg
    return angle <= posture["cone"] / 2 + CB_CONE_EPSILON_DEGREES


def cb_rect_distance(rect, root):
    """CampBrain's flat distance from a root to a floor rectangle: HitShapes.FlatToRect."""
    return hs_flat_to_rect(root[0], root[2], rect["x"], rect["z"], rect["hx"], rect["hz"])


def cb_in_play(defn, target, shooters, rules):
    """CampBrain.InPlay: in the band, and within chaseMargin of the floor rectangle on the flat
    (rounded corners: a rusher clamped in a corner reaches a circle, fix round crowd Major 1), or
    within reach of one of the group's living keepAway members."""
    root = target["root"]
    if not cb_in_band(defn, root, rules):
        return False
    if cb_rect_distance(defn["rect"], root) <= rules["chaseMargin"]:
        return True
    return any(flat_distance(shooter["at"], root) <= shooter["reach"] for shooter in shooters)


def longest_reach(kind):
    """StageFlow.LongestReach: the longest reach among a kind's attacks (0 for none)."""
    return max([0] + [a["reach"] for a in (kind or {}).get("attacks") or []])


def cb_engaged(last_at, now, rules):
    """CampBrain.Engaged (fix round, crowd Minor 1): a player last in play for a group in rise or
    fight at `last_at` (the crowd's step clock) stays engaged for engagedHoldSeconds, edge included."""
    return last_at is not None and now - last_at <= rules["engagedHoldSeconds"] + CB_TIME_EPSILON


def cb_at_post(post, at, rules):
    return flat_distance(post["at"], at) <= rules["homeTolerance"]


def cb_step(group, step, rules):
    """CampBrain.Step: at most one transition; the new state, or None. `hit` is cleared."""
    if not step["members"]:
        return None
    now = step["now"]
    in_play = group["inPlay"]
    in_play.clear()
    any_in_play = False
    for target in step["targets"]:
        if cb_in_play(group["def"], target, step["shooters"], rules):
            in_play[target["userId"]] = True
            any_in_play = True
    if group["held"]:
        group["hit"] = False
        return None
    changed = None
    state = group["state"]
    if state == "rest":
        if group["hit"] or any(cb_sees(group["def"], member, target, rules)
                               for member in step["members"] for target in step["targets"]):
            changed = "rise"
    elif state == "rise":
        if now - group["since"] >= cb_posture(group["def"], rules)["rise"] - CB_TIME_EPSILON:
            changed = "fight"
            group["quietSince"] = now
    elif state == "fight":
        if any_in_play:
            group["quietSince"] = now
        elif now - group["quietSince"] >= rules["leashSeconds"] - CB_TIME_EPSILON and not step["striking"]:
            changed = "home"
    elif state == "home":
        if all(cb_at_post(member["post"], member["at"], rules) for member in step["members"]):
            changed = "rest"
    if changed is not None:
        group["state"] = changed
        group["since"] = now
    group["hit"] = False
    return changed


def cb_release(group, now):
    if not group["held"]:
        return
    group["held"] = False
    group["state"] = "rise"
    group["since"] = now


def cb_evades(group):
    return group["held"] or group["state"] == "home"


def cb_struck(group, by_user_id):
    """CampBrain.Struck (L1b-7): an evading group records nothing; otherwise it is woken, and the
    damage lands only from a player in play at the last step, or from nobody (user 0)."""
    if cb_evades(group):
        return False
    group["hit"] = True
    return by_user_id == 0 or group["inPlay"].get(by_user_id) is True


def cb_goal(group, resident, at, rules):
    """CampBrain.Goal: where a member that is not fighting walks, and its pace; (None, 0) = it
    stands (rise and fight)."""
    post = resident["post"]
    state = group["state"]
    if group["held"] or state == "rest":
        defn = group["def"]
        points = defn["points"]
        n = len(points)
        if defn["posture"] != "patrol" or n == 0:
            return post["at"], rules["homePace"]
        if resident["leg"] < 1 or resident["leg"] > n:
            resident["leg"] = 1
        point = points[resident["leg"] - 1]
        goal = (point[0], defn["floorY"], point[2])
        if flat_distance(goal, at) <= rules["homeTolerance"]:
            resident["leg"] = resident["leg"] % n + 1
            point = points[resident["leg"] - 1]
            goal = (point[0], defn["floorY"], point[2])
        return goal, rules["patrolPace"]
    if state == "home":
        if cb_at_post(post, at, rules):
            resident["leg"] = post["leg"]
        return post["at"], rules["homePace"]
    return None, 0


def cb_shows(group, moving):
    state = group["state"]
    if group["held"] or state == "rest":
        if moving:
            return "move"
        return "rest" if group["def"]["posture"] == "fire" else "idle"
    if state == "home":
        return "move" if moving else "idle"
    if state == "rise":
        return "rise"
    return None


# SwingGate (L1b-W2-13/14): the mirror of src/shared/SwingGate.luau, held to it by
# tools/check_stage_mirror.py. A state is {"used": bool}.
SG_AIR_MARGIN_STUDS = 0.75  # SwingGate.AIR_MARGIN_STUDS


def sg_new():
    return {"used": False}


def sg_is_air(height, stand_offset):
    """SwingGate.IsAir: no floor under the swing (None) is airborne."""
    return True if height is None else height > stand_offset + SG_AIR_MARGIN_STUDS


def sg_allows(state, airborne):
    return not (airborne and state["used"])


def sg_took(state, airborne):
    state["used"] = airborne


def sg_landed(state):
    state["used"] = False


def cb_dormant(group, roots, rules):
    """CampBrain.Dormant (L1b-W2-10): at rest (held or not) and every root farther (flat) than
    dormantRadius from the camp's floor rectangle; no roots = dormant."""
    if group["state"] != "rest":
        return False
    rect = group["def"]["rect"]
    return all(hs_flat_to_rect(r[0], r[2], rect["x"], rect["z"], rect["hx"], rect["hz"]) > rules["dormantRadius"]
               for r in roots)


def cb_gap(a, b):
    """CampBrain.Gap (L1b-W2-12): the least flat distance between a post of each; inf if either
    has none."""
    best = math.inf
    for one in a:
        for other in b:
            d = flat_distance(one["at"], other["at"])
            if d < best:
                best = d
    return best


def cb_join_in(groups, living, gaps, woke, rules):
    """CampBrain.JoinIn (L1b-W2-12): breadth first from `woke`; each waker X brings in, in index
    order, every resting, unheld, living group Y with gaps[X][Y] set and at most joinFactor x X's
    own sight. Indices are 1-based, as the Luau's; `living` and `gaps` are dicts by index."""
    answer = []
    taken = set(woke)
    queue = list(woke)
    head = 0
    while head < len(queue):
        waker = queue[head]
        head += 1
        row = gaps.get(waker)
        group = groups[waker - 1] if 1 <= waker <= len(groups) else None
        if row is None or group is None:
            continue
        reach = rules["joinFactor"] * cb_posture(group["def"], rules)["sight"]
        for other in range(1, len(groups) + 1):
            gap = row.get(other)
            if gap is None or other == waker or other in taken:
                continue
            candidate = groups[other - 1]
            if candidate["state"] == "rest" and not candidate["held"] and living.get(other, 0) > 0 and gap <= reach:
                taken.add(other)
                answer.append(other)
                queue.append(other)
    return answer


def cb_rouse(group, now):
    """CampBrain.Rouse: a resting or homeward, unheld group rises (the fix round's B-3); True when it did."""
    if group["held"] or group["state"] not in ("rest", "home"):
        return False
    group["state"] = "rise"
    group["since"] = now
    group["hit"] = False
    return True


def cb_new_tent(stock):
    return {"left": stock, "nextAt": -math.inf}


def cb_tent_active(busy, residents_alive):
    """CampBrain.TentActive (L1b-W2-7): while its camp is busy, or once no resident is alive."""
    return busy or residents_alive <= 0


def cb_tent_due(tent, active, now):
    return active and tent["left"] > 0 and now >= tent["nextAt"] - CB_TIME_EPSILON


def cb_tent_sent(tent, now, every):
    tent["left"] = max(tent["left"] - 1, 0)
    tent["nextAt"] = now + every


def group_posts(defn):
    """CrowdService.AddGroup's posts: CampBrain.Posts at the sum of the def's units' counts."""
    return cb_posts(defn, sum(unit["count"] for unit in defn["units"]))


def chain_table(defs, rules, living=None):
    """The join-in from rest (L1b-W2-12): for every group of `defs` (CampGroupDefs in AddGroup
    order: the residents, then the tents), the groups a wake of it alone brings in while every
    other group rests, held as its def says, with `living` members ({index: n}; default: all its
    units; give a tent's 0 for one that has sent nobody yet). {def id: [def ids]}, in the order
    CampBrain.JoinIn answers them."""
    groups = [cb_new_group(defn, 0.0) for defn in defs]
    posts = [group_posts(defn) for defn in defs]
    gaps = {}
    for i, a in enumerate(defs, 1):
        for j, b in enumerate(defs, 1):
            if i != j and a["camp"] == b["camp"]:
                gaps.setdefault(i, {})[j] = cb_gap(posts[i - 1], posts[j - 1])
    if living is None:
        living = {i: sum(u["count"] for u in defn["units"]) for i, defn in enumerate(defs, 1)}
    return {defs[i - 1]["id"]: [defs[j - 1]["id"] for j in cb_join_in(groups, living, gaps, [i], rules)]
            for i in range(1, len(defs) + 1)}


def difficulty_ranks(expeditions):
    """The place of every difficulty in Expeditions.json `difficulties` (Combat.CampWave's ranks)."""
    return {name: index for index, name in enumerate(expeditions["difficulties"], 1)}


def level_context():
    """Every config a level run reads, loaded once."""
    combat_cfg = load_config(COMBAT_PATH)
    expeditions = load_config(EXPEDITIONS_PATH)
    missions = {m["id"]: m for m in (load_config(p) for p in sorted(MISSIONS_DIR.glob("*.json")))}
    return {"armory": load_config(ARMORY_PATH), "combat": combat_cfg, "expeditions": expeditions,
            "ranks": difficulty_ranks(expeditions), "missions": missions,
            "files": {f["id"]: f for f in load_level_files()}}


def level_view(cfg, scales, regen_share, armory, gear):
    """[scales] [tier] [health] The range's config as a difficulty plays it at a gear: (view, the
    bar). The view carries `_scales`, the player's HP-loss scale per source."""
    import sim_combat as sc  # the Armory and Combat mirrors live there (lazy: it imports this file)
    view = json.loads(json.dumps(cfg))
    for kind in view["crowd"]["kinds"].values():
        kind["hp"] = max(kind["hp"] * scales["hpScale"], 1)
        if kind.get("plate"):
            kind["plate"] = kind["plate"] * scales["plateScale"]
        for attack in kind.get("attacks") or []:
            if attack["damage"] > 0:
                attack["damage"] = max(luau_round(attack["damage"] * scales["damageScale"]), 1)
    hp = gear_max_hp(armory, gear)
    view["player"]["regenPerSecond"] = regen_share * hp
    view["_scales"] = {slot + suffix: sc.damage_scale(armory, slot, gear[slot], 0, ability)
                       for slot in ("melee", "ranged") for suffix, ability in (("", False), ("Ability", True))}
    return view, hp


def level_kinds(cfg, level, rank, ranks):
    """Every kind a level fields at a difficulty: its residents, its groups, its bosses and what
    they call."""
    kinds = cfg["crowd"]["kinds"]
    found = []
    names = []
    for config in level.get("camps") or []:
        for group in config.get("residents") or []:
            names += [unit["kind"] for unit in fielded_units(group.get("units") or [], rank, ranks)[0]]
    for stage in level["stages"]:
        for wave in stage.get("waves") or []:
            names += [g["kind"] for g in wave["groups"]
                      if g.get("minDifficulty") is None or ranks.get(g["minDifficulty"], math.inf) <= rank]
            names += [wave["boss"]["kind"]] if wave.get("boss") else []
    for name in names:
        if name not in found:
            found.append(name)
        for attack in (kinds.get(name) or {}).get("attacks") or []:
            called = attack.get("summon") if attack["shape"] == "summon" else None
            if called and called not in found:
                found.append(called)
    return found


def hit_rows(cfg, view, hp, names):
    """Each attack of the fielded kinds as the view scales it: its share of the bar."""
    rows = []
    for name in names:
        theirs = cfg["crowd"]["kinds"][name].get("attacks") or []
        for attack, base in zip(view["crowd"]["kinds"][name].get("attacks") or [], theirs):
            if attack["damage"] > 0:
                rows.append({"kind": name, "shape": attack["shape"], "damage": attack["damage"],
                             "share": attack["damage"] / hp, "base": base["damage"]})
    return rows


LEVEL_USER = 1  # the simulator plays solo, as user 1
KITE_KILLS = 2  # the kiting player runs out of the first camp after this many kills in it
EDGE_SECONDS = 30.0  # the edge player is watched this long
EDGE_SPARE = 0.1  # he stands this far past camps.chaseMargin
STRIKE_SECONDS = 30.0  # a first-strike approach is watched this long at most
# CrowdService.HOME_STOP_SHARE: a body walking home or on patrol stops at this share of
# camps.homeTolerance, so rounding never leaves it a hair outside AtPost for good (A's item 2).
HOME_STOP_SHARE = 0.5


class LevelWorld(ThreatWorld):
    """ThreatWorld with CrowdService.Damage's L1b gate: a hit on a resident asks CampBrain.Struck
    first, after the dead check. A group that evades (held, or walking home) and a hit from a
    player out of play answer "blocked": no damage, no knock, no stagger, no damage book."""

    def __init__(self, run, cfg, fighters):
        super().__init__(cfg, fighters)
        self.run = run
        self.evaded = 0  # hits a resident blocked

    def damage(self, enemy, amount):
        if enemy.alive and amount > 0 and enemy.resident is not None:
            group = self.run.groups[enemy.resident["group"] - 1]
            if not cb_struck(group, LEVEL_USER):
                self.evaded += 1
                self.run.blocked[enemy.resident["group"]] = self.run.blocked.get(enemy.resident["group"], 0) + 1
                return 0.0, False
        dealt, killed = super().damage(enemy, amount)
        if dealt > 0 and enemy.resident is not None:
            self.run.first_hit.setdefault(enemy.resident["group"], self.now)
        return dealt, killed


class LevelRun(ThreatRun):
    """One player through a level, solo, at one difficulty (L1b): StageFlow's rules (only the
    boss room is a stage), the queue, the director and the boss room of WaveService, every camp's
    residents on their own floors under CampBrain, every kill paid as it falls, and the crowd and
    the player of the threat. World coordinates throughout: a body is clamped to its own floor,
    the player to the boss room's floor while its gates are closed and nowhere otherwise.

    The player's course is the simulator's own choice, not a rule. He walks the route; at an open
    camp that still has residents he clears it (he goes for the nearest living resident of that
    camp) as soon as he is in play for it or one of its groups is awake, then walks from where he
    is to its exit and on; at the boss room he walks to its middle through the countdown and fights
    whatever is on its floor. `only` = the ids of the resident groups to place (a scenario);
    `start` = (x, z, ground y) and `from_route` = the route point he starts on; `seconds` stops
    the run ("stopped"); `stop_zone` = the zone index whose clear stops it."""

    def __init__(self, cfg, hp, ctx, level, layout, difficulty, policy, seed, only=None, start=None, from_route=None,
                 seconds=None, stop_zone=None):
        rules = ctx["combat"]["levels"]
        plan = plan_level(level, layout, difficulty, rules, ctx["ranks"], cfg["crowd"]["kinds"])
        route = [(p["x"], p["z"], p["y"], p.get("via")) for p in layout.get("route") or []]
        if from_route is not None:
            start = (route[from_route][0], route[from_route][1], route[from_route][2])
        begin = (start[0], start[1]) if start is not None else plan["start"]
        super().__init__(cfg, {"half": (FREE, FREE), "pad": begin, "hp": hp}, "", policy, seed,
                         level["runCapSeconds"])
        import sim_combat as sc
        self.sc = sc
        self.world = LevelWorld(self, cfg, self.fighters)
        self.world.owed = self.owe
        self.world.fell = self.fall
        self.world.scale = self.hit_scale
        self.level, self.plan, self.layout = level, plan, layout
        self.combat = ctx["combat"]
        self.director = self.combat["director"]
        self.rules = rules
        self.camp_rules = self.combat.get("camps")
        self.ranks = ctx["ranks"]
        self.rank = self.ranks.get(difficulty, 1)
        self.scales = level["difficulties"][difficulty]
        self.crowd = level["crowd"]
        self.zones = plan["zones"]
        self.watch = seconds
        self.stop_zone = stop_zone
        self.jitter = (self.x - begin[0], self.z - begin[1])
        self.still = not (policy.get("fight") or policy.get("react"))
        # StageFlow.State. `flow` is its step: travel | armed | gate | fight | breather | over.
        self.stage = 1
        self.flow = "armed" if plan["stages"][0]["kind"] == "camp" else "travel"
        self.wave = 0
        self.first_wave = 1
        self.gate_at = 0.0
        self.breather_until = 0.0
        self.cleared = 0
        self.last_cleared = 0
        self.settled = 0
        self.reached = {}
        self.done = {}
        self.closed_at = 0.0
        self.fought = []
        self.fighters_now = [LEVEL_USER]
        self.entered = False
        self.grace_moves = 0
        # WaveService's run.
        self.ids = 0
        self.cursor = 0
        self.spawns = []
        self.max_alive = 0
        self.spec = None
        self.queue = []
        self.boss_pending = None
        self.boss_valor = 0
        self.bursts = 0
        self.next_spawn = 0.0
        self.spawned = 0
        self.tempo = 1.0
        self.stamps = []
        self.live = None  # the boss room whose gates are closed (its zone), or None
        # The wallet (L1b-15): every kill split at once with the carry; `priced` is the sum of
        # each kill's reward x the share, kept exactly, that the wallet must equal (solo).
        self.carry = {}
        self.wallet = {"cash": 0, "materials": 0, "valor": 0}
        self.priced = {"cash": 0.0, "materials": 0.0, "valor": 0.0}
        self.credits = 0
        # What the run reports.
        self.camps = []  # one per countdown of the boss room: its times and its waves
        self.camp = None
        self.killed = {}
        self.killed_in = {}  # zone index -> {kind: kills}
        self.boss_fights = {}
        self.end_reason = None
        self.end_at = None
        self.peak_alive = 0
        self.breathers = 0.0
        self.forgiven = 0
        self.walked = 0.0
        self.actions = []
        self.cleared_at = {}  # zone index -> when its camp was cleared
        self.reached_at = {}
        self.first_hit = {}  # group index -> the first hit of his that landed on a member
        self.first_windup = {}  # group index -> the first windup a member began
        self.woke = {}  # group index -> (when, cause) of its first wake
        self.events = []  # (time, group index, from, to, held)
        self.blocked = {}  # group index -> his hits it blocked
        self.wake_floors = set()  # CrowdService.WakeFloor: released at the next step
        self.engaged = False
        self.engaged_at = None  # CrowdService's camp.engaged for him: the step he was last in play
        self.stood_at = None
        self.crossing = None  # the still player: the open camp he is walking across
        self.kite = None
        # The residents (WaveService's start: AddGroup, Posts, SpawnResident).
        self.groups = []
        for index, defn in enumerate(plan["groups"], 1):
            group = cb_new_group(defn, 0.0)
            group["members"] = []
            self.groups.append(group)
            if only is not None and defn["id"] not in only:
                continue
            posts = cb_posts(defn, sum(unit["count"] for unit in defn["units"]))
            k = 0
            for unit in defn["units"]:
                for _n in range(unit["count"]):
                    post = posts[k]
                    k += 1
                    body = self.raise_body(unit["kind"], post["at"][0], post["at"][2], 0.0, defn["floor"])
                    body.resident = {"group": index, "post": post, "leg": post["leg"]}
                    body.face = (-math.sin(post["yaw"]), -math.cos(post["yaw"]))
                    group["members"].append(body)
        # L1b-W2-6: each tent's stock is a group of its own, after the residents' (AddGroup answers
        # #plan.groups + t), with nobody out at the start. `only` places a tent only by its id.
        self.tents = []
        for tent in plan["tents"]:
            group = cb_new_group(tent["def"], 0.0)
            group["members"] = []
            self.groups.append(group)
            if only is not None and tent["def"]["id"] not in only:
                continue
            self.tents.append({"group": len(self.groups), "id": tent["def"]["id"], "camp": tent["def"]["camp"],
                               "floor": tent["zone"], "kinds": tent["kinds"], "posts": tent["posts"],
                               "every": tent["every"], "sent": 0, "state": cb_new_tent(len(tent["kinds"])),
                               "sentAt": [], "refused": 0})
        # L1b-W2-12: CrowdService.AddGroup's posts and the gap between every two groups of one camp,
        # post to post, worked out once (posts never move).
        posts_of = [cb_posts(g["def"], sum(u["count"] for u in g["def"]["units"])) for g in self.groups]
        self.gaps = {}
        for i, a in enumerate(self.groups, 1):
            for j, b in enumerate(self.groups, 1):
                if i != j and a["def"]["camp"] == b["def"]["camp"]:
                    self.gaps.setdefault(i, {})[j] = cb_gap(posts_of[i - 1], posts_of[j - 1])
        self.rouse_pending = set()  # CrowdService.RouseGroup: roused at the next camp step
        self.joined = []  # (when, the wakers, the groups their wake brought in)
        self.wave_stock = {}  # WaveService's run.waveStock: what the live boss room's waves queued
        self.bonuses = {}  # zone id -> the clear bonus it paid (cash, materials)
        self.dormant_steps = 0  # body-steps skipped as dormant (information)
        self.placed = len(self.fighters)
        # His course.
        self.route = route
        self.from_route = from_route
        self.ground = start[2] if start is not None else plan["startY"]
        self.order = self.route_order()
        self.target = 0
        self.mode = ("edge" if policy.get("edge") else "sneak" if policy.get("sneak")
                     else "stopped" if policy.get("parked") else "road")
        self.path = self.path_to(self.order[0], None) if self.order and self.mode == "road" else []
        if self.mode == "sneak":
            # The sneak (L1b-W2-3): along layout.sneak, every point at the ground's height there.
            self.path = [(p["x"], p["z"], self.sneak_ground(p["x"], p["z"])) for p in (layout.get("sneak") or [])[1:]]

    # -- floors and boxes -------------------------------------------------------------------------

    def body_box(self, radius, floor):
        if floor is None:
            return super().body_box(radius, floor)
        cx, cz, hx, hz = self.zones[floor - 1]["rect"]
        limit_x, limit_z = max(hx - radius, 0), max(hz - radius, 0)
        return cx - limit_x, cx + limit_x, cz - limit_z, cz + limit_z

    def player_box(self):
        if self.live is None:
            return -FREE, FREE, -FREE, FREE
        cx, cz, hx, hz = self.live["rect"]
        limit_x, limit_z = hx - FENCE_CLEARANCE, hz - FENCE_CLEARANCE
        return cx - limit_x, cx + limit_x, cz - limit_z, cz + limit_z

    def world_root(self, t):
        return self.x, self.ground + ROOT_HEIGHT + self.feet(t), self.z

    def sneak_ground(self, x, z):
        """The height a sneaking player stands at: a camp's floor inside it, else the route's height
        at its point nearest (the sneak path runs beside the road or on it)."""
        for zone in self.zones:
            cx, cz, hx, hz = zone["rect"]
            if abs(x - cx) <= hx and abs(z - cz) <= hz:
                return zone["floorY"]
        best, height = math.inf, self.plan["startY"]
        for a, b in zip(self.route, self.route[1:]):
            run = math.hypot(b[0] - a[0], b[1] - a[1])
            steps = max(int(run), 1)
            for k in range(steps + 1):
                f = k / steps
                d = math.hypot(a[0] + (b[0] - a[0]) * f - x, a[1] + (b[1] - a[1]) * f - z)
                if d < best:
                    best, height = d, a[2] + (b[2] - a[2]) * f
        return height

    def grouped_on(self, floor):
        """CrowdService.GroupedOn: the living bodies of a floor that belong to a group."""
        return sum(1 for f in self.fighters if f.alive and f.floor == floor and f.resident is not None)

    def tent_left(self, floor):
        """StageFlow's Input.tentLeft for a zone index: its tent's stock not sent yet (0 for none)."""
        return sum(t["state"]["left"] for t in self.tents if t["floor"] == floor)

    def send_tents(self, t):
        """WaveService.tick's tents (L1b-W2-7), before Advance: Busy once; for each tent, active
        while its camp is busy or once none of its camp's residents lives (its own bodies not
        counted); a due body spawns on its ring post, its group is roused at the next camp step,
        and the clock moves on. A refused spawn (the cap) counts as sent."""
        if not self.tents:
            return
        busy = self.busy()
        cap = self.cfg["crowd"]["maxAlive"]
        for tent in self.tents:
            group = self.groups[tent["group"] - 1]
            floor = tent["floor"]
            own = sum(1 for b in group["members"] if b.alive)
            active = cb_tent_active(busy.get(floor) is True, self.alive_on(floor) - own)
            if not cb_tent_due(tent["state"], active, t):
                continue
            k = tent["sent"]
            if sum(1 for f in self.fighters if f.alive) >= cap:
                tent["refused"] += 1
            else:
                post = tent["posts"][k]
                body = self.raise_body(tent["kinds"][k], post["at"][0], post["at"][2], t, floor)
                body.resident = {"group": tent["group"], "post": post, "leg": post["leg"]}
                body.face = (-math.sin(post["yaw"]), -math.cos(post["yaw"]))
                group["members"].append(body)
                self.rouse_pending.add(tent["group"])
                self.count_alive()
            cb_tent_sent(tent["state"], t, tent["every"])
            tent["sent"] += 1
            tent["sentAt"].append(t)

    def alive_on(self, floor):
        return sum(1 for f in self.fighters if f.alive and f.floor == floor)

    def awake_count(self):
        """CrowdService.Awake: groups in rise, fight or home with a living member."""
        return sum(1 for g in self.groups if g["state"] in ("rise", "fight", "home") and not g["held"]
                   and any(b.alive for b in g["members"]))

    def busy(self):
        """CrowdService.Busy: floors with a group in rise or fight."""
        return {g["def"]["floor"]: True for g in self.groups
                if g["state"] in ("rise", "fight") and not g["held"] and any(b.alive for b in g["members"])}

    def safe_threats(self):
        """WaveService's threats for StageFlow.SafePoint (fix round, data Minor 1): every living
        member of a group in rise or fight, where it stands, with StageFlow.LongestReach."""
        return [{"at": (b.x, g["def"]["floorY"], b.z), "reach": longest_reach(b.kind)} for g in self.groups
                if g["state"] in ("rise", "fight") for b in g["members"] if b.alive]

    def may_target(self, e):
        """L1b-6: a resident in fight goes only for a target in play for its group; one that is
        not fighting thinks of nothing. Every other body has the player."""
        if e.resident is None:
            return True
        group = self.groups[e.resident["group"] - 1]
        return group["state"] == "fight" and not group["held"] and group["inPlay"].get(LEVEL_USER) is True

    def heal(self, body):
        """L1b-8: at its post on the way home: HP, plate, stagger (the damage book is emptied)."""
        body.hp = body.max_hp
        body.plate = body.max_plate
        body.stagger_until = 0.0

    def note(self, now, index, before, after, held, cause=None):
        self.events.append((now, index, before, after, held))
        if before == "rest" and after == "rise":
            self.woke.setdefault(index, (now, cause or ("close" if held else "sight")))
            kite = self.kite
            if (kite is not None and kite.get("rested") is not None and kite.get("tentBack") is None
                    and self.groups[index - 1]["def"]["floor"] == kite["floor"]):
                kite["tentBack"] = self.tent_left(kite["floor"])  # before this tick's tent can send
            if self.still and self.mode == "road" and self.policy.get("stop") and self.stood_at is None:
                self.mode = "stopped"
                self.stood_at = now
                self.path = []

    def before_think(self, now, dt):
        """The camp step (CrowdService), once per crowd step after the player is tracked and
        before any body thinks: a pending WakeFloor releases its held groups; each group steps
        (CampBrain.Step) on its living members, the standing player and its shooters' reach; a
        member at its post while its group walks home is healed first (before the step that finds
        them all home, so the last to arrive is healed too); then every member that is not
        fighting is given CampBrain.Goal to walk to."""
        rules = self.camp_rules
        if rules is None or not self.groups:
            return
        targets = [{"userId": LEVEL_USER, "root": self.world_root(now)}] if self.down_until is None else []
        roots = [self.world_root(now)]  # L1b-W2-10: every player's root, down or not
        engaged = False
        woke = []  # the groups that went rest -> rise by Step this step (sight or a hit)
        for index, group in enumerate(self.groups, 1):
            defn = group["def"]
            alive = [b for b in group["members"] if b.alive]
            if not alive:
                self.rouse_pending.discard(index)
                continue
            for b in alive:
                if b.state != "approach" and index not in self.first_windup:
                    self.first_windup[index] = b.started
            y = defn["floorY"]
            members = [{"at": (b.x, y, b.z), "post": b.resident["post"]} for b in alive]
            if group["state"] == "home" and not group["held"]:
                for b, member in zip(alive, members):
                    if cb_at_post(member["post"], member["at"], rules):
                        self.heal(b)
            shooters = [{"at": (b.x, y, b.z), "reach": max(a["reach"] for a in b.attacks)}
                        for b in alive if b.kind.get("brain") == "keepAway"]
            striking = any(b.state in ("windup", "attack") for b in alive)
            before, hit = group["state"], group["hit"]
            step = {"now": now, "members": members, "targets": targets, "shooters": shooters, "striking": striking}
            if defn["floor"] in self.wake_floors and group["held"]:
                # The release step (CrowdService, A's report item 3): the held group is stepped
                # first, which only refreshes its in-play set, then released, and makes no other
                # transition this step, so a rise of 0 still lasts one step.
                cb_step(group, step, rules)
                cb_release(group, now)
                self.note(now, index, "rest", "rise", True, "close")
            else:
                changed = cb_step(group, step, rules)
                if changed is not None:
                    self.note(now, index, before, changed, False, "hit" if hit else "sight")
                    if before == "rest" and changed == "rise":
                        woke.append(index)
            if index in self.rouse_pending:
                # CrowdService.RouseGroup (L1b-W2-7): after the step, as a release is. The event
                # names the state it left (the fix round's B-3: a group walking home rises too).
                self.rouse_pending.discard(index)
                left = group["state"]
                if cb_rouse(group, now):
                    self.note(now, index, left, "rise", False, "tent")
        self.wake_floors = set()
        if woke:
            # L1b-W2-12: the resting neighbours of every group that woke by sight or by a hit.
            living = {i: sum(1 for b in g["members"] if b.alive) for i, g in enumerate(self.groups, 1)}
            joined = cb_join_in(self.groups, living, self.gaps, woke, rules)
            for index in joined:
                if cb_rouse(self.groups[index - 1], now):
                    self.note(now, index, "rest", "rise", False, "join")
            self.joined.append((now, list(woke), joined))
        for group in self.groups:
            # L1b-W2-10: dormancy, for every group, after the step, the join-in and any rouse.
            dormant = cb_dormant(group, roots, rules)
            for b in group["members"]:
                b.dormant = dormant and b.alive
                if b.dormant:
                    self.dormant_steps += 1
            if group["state"] in ("rise", "fight") and not group["held"] and group["inPlay"].get(LEVEL_USER) \
                    and any(b.alive for b in group["members"]):
                engaged = True
        if engaged:
            self.engaged_at = now
        elif not cb_engaged(self.engaged_at, now, rules):
            self.engaged_at = None
        self.engaged = cb_engaged(self.engaged_at, now, rules)
        for group in self.groups:
            resting = group["held"] or group["state"] in ("rest", "home")
            y = group["def"]["floorY"]
            for b in group["members"]:
                if not b.alive:
                    continue
                if not resting:
                    b.idle = None
                    continue
                goal, pace = cb_goal(group, b.resident, (b.x, y, b.z), rules)
                b.idle = (goal[0], goal[2], pace * max(b.kind["speed"], 0), rules["homeTolerance"] * HOME_STOP_SHARE)
                if group["state"] == "rest" and cb_at_post(b.resident["post"], (b.x, y, b.z), rules):
                    yaw = b.resident["post"]["yaw"]
                    b.face = (-math.sin(yaw), -math.cos(yaw))

    # -- his course -----------------------------------------------------------------------------

    def route_index(self, point):
        return next((i for i, p in enumerate(self.route) if math.hypot(p[0] - point[0], p[1] - point[1]) < 0.01), None)

    def route_order(self):
        """The zones in the order the route meets their entries (a zone it never meets: after)."""
        def key(zone):
            index = self.route_index(zone["entry"])
            return (index if index is not None else math.inf, zone["floor"])
        return [zone["floor"] for zone in sorted(self.zones, key=key)]

    def path_to(self, floor, after):
        """The points he walks to reach zone `floor`: from where he starts (or from zone `after`'s
        exit) along the route to its entry, and for the boss room on to its middle. (x, z, y)."""
        zone = self.zones[floor - 1]
        middle = (zone["rect"][0], zone["rect"][1], zone["floorY"])
        entry = self.route_index(zone["entry"])
        if not self.route or entry is None:
            return [middle] if zone["locks"] else [(zone["entry"][0], zone["entry"][1], zone["floorY"])]
        if after is not None:
            leave = self.zones[after - 1]
            begin = self.route_index(leave["exit"])
            lead = [(leave["exit"][0], leave["exit"][1], leave["floorY"])]
            begin = (begin + 1) if begin is not None else entry
        else:
            begin = (self.from_route + 1) if self.from_route is not None else 1
            lead = []
        points = lead + [(p[0], p[1], p[2]) for p in self.route[begin:entry + 1]]
        return points + [middle] if zone["locks"] else points

    def near(self, zone):
        cx, cz, hx, hz = zone["rect"]
        margin = self.camp_rules["chaseMargin"] if self.camp_rules else 0
        return cb_rect_distance({"x": cx, "z": cz, "hx": hx, "hz": hz}, (self.x, 0.0, self.z)) <= margin

    def residents_left(self, floor):
        return [b for g in self.groups if g["def"]["floor"] == floor for b in g["members"] if b.alive]

    def awake_in(self, floor):
        return any(g["state"] in ("rise", "fight") and not g["held"] for g in self.groups
                   if g["def"]["floor"] == floor and any(b.alive for b in g["members"]))

    def leave_zone(self, floor):
        """On to the next camp in the route's order, from this one's exit."""
        self.target += 1
        self.mode = "road"
        self.path = self.path_to(self.order[self.target], floor) if self.target < len(self.order) else []

    def steer(self, t):
        """The simulator's course (not a rule): what he does next."""
        if self.mode == "sneak":
            if not self.path and self.end_reason is None:
                self.end("stopped", t)  # at the boss room's entry, the way he came unseen
            return
        if self.mode in ("stopped", "edge", "lock") or self.end_reason is not None:
            return
        if self.mode in ("flee", "wait"):
            self.kite_step(t)
            return
        if self.target >= len(self.order):
            return
        floor = self.order[self.target]
        zone = self.zones[floor - 1]
        if zone["locks"]:
            if self.live is not None:
                self.mode = "lock"
                self.ground = zone["floorY"]
                self.path = []
            return
        if self.mode == "road":
            if self.still and (self.policy.get("stop") or self.policy.get("cross")):
                # The still player never clears: he walks on across each open camp, entry to exit,
                # until a group wakes (note() stops him there for good).
                if not self.path:
                    if self.crossing != floor:
                        self.crossing = floor
                        self.path = [(zone["exit"][0], zone["exit"][1], zone["floorY"])]
                    else:
                        self.leave_zone(floor)
                return
            if not self.residents_left(floor) and self.tent_left(floor) == 0:
                if self.path and self.near(zone):
                    return  # walking through a camp that is empty: on to its entry, then on
                self.leave_zone(floor)
                return
            if self.near(zone) or self.awake_in(floor) or not self.path:
                self.mode = "clear"
                self.ground = zone["floorY"]
                self.path = []
                if self.kite is not None and self.kite.get("back") is None and self.kite.get("rested") is not None:
                    self.kite_back(t, floor)
            return
        # mode == "clear": until its residents are dead and its tent is empty (he waits out the
        # tent's last bodies where he stands, so the camp clears and pays its bonus)
        if not self.residents_left(floor) and self.tent_left(floor) == 0:
            self.leave_zone(floor)
            return
        if (self.policy.get("kite") and self.kite is None and floor == self.order[0]
                and sum(self.killed_in.get(floor, {}).values()) >= KITE_KILLS):
            alive = self.residents_left(floor)
            self.kite = {"at": t, "floor": floor, "alive": alive,
                         "dead": [b for g in self.groups if g["def"]["floor"] == floor for b in g["members"]
                                  if not b.alive],
                         "hurt": sum(1 for b in alive if b.hp < b.max_hp or b.plate < b.max_plate),
                         "rested": None, "back": None}
            entry = self.route_index(zone["entry"])
            back = self.route[entry - 1] if entry else None
            self.mode = "flee"
            self.quarry = None
            self.path = [(zone["entry"][0], zone["entry"][1], zone["floorY"])]
            if back is not None:
                self.path.append((back[0], back[1], back[2]))

    def kite_step(self, t):
        """The kiting player: out to the road beyond the camp, then he waits until every group of
        it is at rest again (leashed, home and healed), and walks back in."""
        floor = self.kite["floor"]
        if self.mode == "flee" and not self.path:
            self.mode = "wait"
        if self.mode == "wait":
            groups = [g for g in self.groups if g["def"]["floor"] == floor and any(b.alive for b in g["members"])]
            if all(g["state"] == "rest" for g in groups):
                self.kite["rested"] = t
                self.kite["tentRested"] = self.tent_left(floor)
                self.mode = "road"
                zone = self.zones[floor - 1]
                self.path = [(zone["entry"][0], zone["entry"][1], zone["floorY"])]

    def kite_back(self, t, floor):
        """He is in play for the camp again: what he finds."""
        alive = self.residents_left(floor)
        self.kite["back"] = t
        self.kite["full"] = all(b.hp >= b.max_hp and b.plate >= b.max_plate for b in alive)
        # Every survivor still there, the dead still dead; what came out of the tent while he was
        # away (its stock does not pause while the camp is up) is new, and no other body is.
        tent_groups = {t["group"] for t in self.tents}
        known = {b.id for b in self.kite["alive"]}
        self.kite["same"] = (known <= {b.id for b in alive}
                             and all(b.resident["group"] in tent_groups for b in alive if b.id not in known)
                             and all(not b.alive for b in self.kite["dead"]))
        self.kite["leashes"] = sum(1 for e in self.events if e[0] >= self.kite["at"] and e[2] == "fight" and e[3] == "home"
                                   and self.groups[e[1] - 1]["def"]["floor"] == floor)

    def swingable(self):
        if self.mode == "clear":
            floor = self.order[self.target]
            return [e for e in self.fighters if e.alive and e.floor == floor]
        if self.mode == "lock" and self.live is not None:
            return [e for e in self.fighters if e.alive and e.floor == self.live["floor"]]
        if self.mode == "edge":
            return [e for e in self.fighters if e.alive]
        return []

    def walking(self):
        return (self.mode in ("road", "flee", "sneak") and self.down_until is None
                and (self.flow != "gate" or not self.still))

    def emit(self, kind, **fields):
        self.actions.append((kind, fields))

    def new_id(self):
        self.ids += 1
        return self.ids

    def walk_path(self, dt):
        """[road] One frame of walking toward the next point of his path, on his own line."""
        if not self.path:
            return
        tx, tz = self.path[0][0] + self.jitter[0], self.path[0][1] + self.jitter[1]
        dx, dz = tx - self.x, tz - self.z
        gap = math.hypot(dx, dz)
        stride = self.move["walkSpeed"] * dt
        if gap <= stride:
            self.x, self.z = tx, tz
            self.ground = self.path[0][2]
            self.walked += gap
            self.path.pop(0)
            return
        self.x += dx / gap * stride
        self.z += dz / gap * stride
        self.walked += stride

    # -- the queue and the director (WaveService) ----------------------------------------------

    def raise_body(self, name, x, z, t, floor):
        kind = self.cfg["crowd"]["kinds"][name]
        x0, x1, z0, z1 = self.body_box(kind["radius"], floor)
        body = Fighter(self.new_id(), name, kind, clamp(x, x0, x1), clamp(z, z0, z1), math.inf)
        body.floor = floor
        body.spawned_at = t
        self.fighters.append(body)
        return body

    def live_zone(self):
        stage = self.plan["stages"][self.stage - 1] if 1 <= self.stage <= len(self.plan["stages"]) else None
        return stage["zone"] if stage is not None else None

    def spawn_boss(self, t):
        """WaveService.spawnBoss: the boss first, at StageFlow.BossPoint, on the camp's floor."""
        entry = self.boss_pending
        if entry is None:
            return
        self.boss_pending = None
        zone = self.live_zone()
        boss = self.raise_body(entry["kind"], zone["rect"][0] + entry["at"][0], zone["rect"][1] + entry["at"][1], t,
                               zone["floor"])
        self.boss = self.quarry = boss
        self.want = self.wanted(boss)
        self.guards_at = None
        self.boss_fights[entry["kind"]] = (t, None)
        self.count_alive()

    def count_alive(self):
        alive = sum(1 for f in self.fighters if f.alive)
        self.peak_alive = max(self.peak_alive, alive)
        if self.camp is not None:
            self.camp["peakAlive"] = max(self.camp["peakAlive"], self.alive_on(self.camp["floor"]))

    def spawn_next(self, t):
        """WaveService.spawnBursts: the head burst, body by body while the boss room's own floor
        holds fewer than its maxAlive, its residents included (L1b-14)."""
        if not self.queue:
            return
        burst = self.queue[0]
        if burst[2] == 0 and t < self.next_spawn - THREAT_EPS:
            return
        if burst[3] is None:
            burst[3] = self.spawns[self.cursor % len(self.spawns)]
            self.cursor += 1
        zone = self.live_zone()
        cx, cz = zone["rect"][0], zone["rect"][1]
        size = burst[1] + burst[2]
        spacing = self.crowd["burstSpacing"]
        while burst[1] > 0 and self.alive_on(zone["floor"]) < self.max_alive:
            x, z = burst_point(burst[3], size, burst[2], spacing)
            self.raise_body(burst[0], x + cx, z + cz, t, zone["floor"])
            burst[2] += 1
            burst[1] -= 1
        self.count_alive()
        if burst[1] > 0:
            return
        self.queue.pop(0)
        if not self.queue:
            self.camp["waves"][self.wave]["spawnEnd"] = t
        stage = self.plan["stages"][self.stage - 1]
        self.next_spawn = t + self.sc.burst_seconds(stage["targetWaveSeconds"], self.bursts, self.tempo)

    def update_tempo(self, t):
        """[director] WaveService.updateTempo, on every tick of a closed camp (directs)."""
        director = self.director
        cutoff = t - director["windowSeconds"]
        self.stamps = [s for s in self.stamps if s >= cutoff]
        if t - self.closed_at < director["tempoWarmupSeconds"]:
            self.tempo = 1.0
            return
        target = self.plan["stages"][self.stage - 1]["targetWaveSeconds"]
        expected = self.spec["total"] / target if target > 0 and self.spec is not None else 0
        self.tempo = self.sc.tempo(len(self.stamps), director["windowSeconds"], expected, director)

    # -- the actions (what WaveService does for each) ---------------------------------------------

    def on_gate(self, index, t):
        if self.policy.get("cross"):
            self.end("stopped", t)  # the careless road ends where the boss room's countdown begins
            return
        stage = self.plan["stages"][index - 1]
        self.max_alive = stage["maxAlive"]
        self.camp = {"stage": index, "name": stage["name"], "zone": stage["zone"]["id"], "floor": stage["zone"]["floor"],
                     "gateAt": t, "closedAt": None, "clearedAt": None, "waves": {}, "peakAlive": 0,
                     "walked": self.walked, "killed": {}}
        self.camps.append(self.camp)

    def on_close(self, t):
        """`close`: the gates shut. A fighter outside the floor inset by levels.closeInset is put
        on the entry point; the boss room's held residents are released at the next step
        (CrowdService.WakeFloor); tempo back to 1, kill stamps cleared."""
        zone = self.plan["stages"][self.stage - 1]["zone"]
        cx, cz = zone["rect"][0], zone["rect"][1]
        _ix, _iz, keep_x, keep_z = zone["inner"]
        self.entered = False
        if abs(self.x - cx) > keep_x or abs(self.z - cz) > keep_z:
            self.x, self.z = zone["entry"]
            self.entered = True
        self.live = zone
        self.ground = zone["floorY"]
        self.anchor = self.jitter
        self.spawns = [(x - cx, z - cz) for x, z in zone["spawns"]]
        self.path = []
        self.tempo = 1.0
        self.stamps = []
        self.wave_stock = {}  # a new locking camp's waves begin
        self.wake_floors.add(zone["floor"])
        self.camp["closedAt"] = t

    def on_wave(self, wave, merged, t):
        """`wave`: P5's queueWave on Combat.CampWave. A merged wave adds to the group in play."""
        stage = self.plan["stages"][self.stage - 1]
        spec = self.sc.camp_wave(stage["defs"][wave - 1], self.crowd["regenShare"], self.scales, self.rank,
                                 self.ranks, 1, self.combat)
        spec["wave"] = wave
        self.spec = spec
        if not merged:
            self.spawned = 0
        if spec["boss"] is not None:
            self.boss_pending = spec["boss"]
            self.boss_valor = luau_round(spec["boss"]["valor"] * self.scales["rewardMult"])
        bursts = self.sc.crowd_bursts(spec, self.crowd["burst"])
        self.queue += [[kind, count, 0, None] for kind, count in bursts]
        self.sc.wave_stock(self.wave_stock, spec)  # WaveService.queueWave: run.waveStock (L1b-W2-21)
        self.bursts = len(bursts)
        self.spawned += spec["total"]
        self.next_spawn = t
        self.camp["waves"][wave] = {"start": t, "spawnEnd": None, "clear": None, "merged": merged, "kills": 0,
                                    "bodies": spec["total"], "boss": spec["boss"] is not None, "tempo": self.tempo}

    def clear_threats(self):
        self.pending = []
        self.shots = []
        self.charges = []
        self.rings = []

    def on_clear(self, t):
        """`clear`: what the dead still had in the air goes with them (VitalsService.ClearThreats)."""
        self.clear_threats()
        for record in self.camp["waves"].values():
            if record["clear"] is None:
                record["clear"] = t
                if record["spawnEnd"] is None:
                    record["spawnEnd"] = t

    def on_open(self, t, index=None, skipped=False):
        """`open` (WaveService.campCleared): the locking camp is behind him; unless a Studio skip
        passed it, its clear bonus (L1b-W2-21) over its residents and what its waves queued."""
        if not skipped:
            stage = self.plan["stages"][(index if index is not None else self.stage) - 1]
            if stage["zone"] is not None:
                self.pay_clear_bonus(stage["zone"]["floor"])
        if index is not None and (self.camp is None or self.camp["stage"] != index):
            return
        self.live = None
        if self.camp is not None:
            self.camp["clearedAt"] = t
            self.cleared_at[self.camp["floor"]] = t

    def pay_clear_bonus(self, floor):
        """WaveService's clear bonus (L1b-W2-21): Combat.ClearBonus over the camp's whole stock at the
        difficulty's price (an open camp: its residents and its tent's stock; the boss room: its
        residents and every body its waves queued, the boss not), split evenly among the fighting
        humans and kept at once; nothing for no clearBonus or a share of 0."""
        bonus = self.crowd.get("clearBonus")
        share = bonus.get("share") if isinstance(bonus, dict) else None
        zone = self.zones[floor - 1]
        if not share:
            self.bonuses[zone["id"]] = (0, 0)
            return
        stock = dict(zone["stock"])
        if zone["locks"]:
            for kind, count in self.wave_stock.items():
                stock[kind] = stock.get(kind, 0) + count
        cash, materials = self.sc.clear_bonus(stock, self.crowd["rewards"], self.scales["rewardMult"], share)
        self.bonuses[zone["id"]] = (cash, materials)
        if cash or materials:
            self.credit({"cash": cash, "materials": materials, "valor": 0}, {LEVEL_USER: 1.0})

    def on_rearm(self, t):
        if self.camp in self.camps:
            self.camps.remove(self.camp)
        self.camp = None

    def on_drop(self, t):
        """`drop` (a Studio skip): CrowdService.ClearFloor of the live boss room's floor (its
        queue, its bodies, its residents, without a kill) and VitalsService.ClearThreats."""
        zone = self.live_zone()
        for f in self.fighters:
            if f.alive and zone is not None and f.floor == zone["floor"]:
                f.alive = False
                f.respawn_at = math.inf
        self.fighters[:] = [f for f in self.fighters if f.alive]
        self.queue = []
        self.boss_pending = None
        self.boss = self.quarry = None
        self.clear_threats()

    def on_move(self, index, t):
        zone = self.plan["stages"][index - 1]["zone"]
        self.live = None
        self.x, self.z = zone["entry"]
        self.ground = zone["floorY"]
        self.anchor = (self.x, self.z)
        self.path = [(zone["rect"][0], zone["rect"][1], zone["floorY"])]

    def on_reach(self, floor, t):
        self.reached_at[floor] = t

    def on_camp_clear(self, floor, t):
        """`campClear` (L1b-17): the bonus x rewardMult, split evenly among the fighting humans."""
        self.cleared_at[floor] = t
        self.pay_clear_bonus(floor)
        if self.stop_zone == floor:
            self.end("stopped", t)

    def end(self, reason, t):
        self.flow = "over"
        self.end_reason = reason
        self.end_at = t

    def hurt(self, t, kind, attack, push):
        """P5 ruling 18: in a run a down does not end by itself (no get-up timer)."""
        before = len(self.downs)
        super().hurt(t, kind, attack, push)
        if len(self.downs) > before:
            self.down_until = math.inf
            self.down_span = (t, math.inf)

    def stand_up(self, t):
        """`boundary`: VitalsService.StandUp: the down ends here, full health, the get-up i-frames."""
        if self.down_until is None:
            return
        self.down_until = None
        self.down_span = (self.down_span[0], t)
        self.hp = self.max_hp
        self.last_hurt = t
        self.knock_until = -math.inf
        self.windows.append((t, t + self.vitals["getUpIframes"]))
        self.forgiven += 1

    # -- StageFlow: Advance, and the Studio levers Skip and Force ----------------------------------

    def flow_input(self, t):
        """StageFlow.Input as WaveService builds it this tick."""
        standing = self.down_until is None
        by_floor = [self.alive_on(zone["floor"]) for zone in self.zones]
        zone = self.live_zone() if self.flow in ("gate", "fight", "breather") else None
        return {"roots": [self.world_root(t)], "standing": [standing], "fighters": list(self.fighters_now),
                "spawningDone": not self.queue and self.boss_pending is None,
                "alive": by_floor[zone["floor"] - 1] if zone is not None else 0, "awake": self.awake_count(),
                "aliveByFloor": by_floor, "fallen": None if standing else "down",
                "tentLeft": [self.tent_left(z["floor"]) for z in self.zones]}

    def stands_up(self, given):
        """StageFlow.StandsUp (the fix round): in travel, armed or gate, with the road's field
        clear, somebody in `standing` is down."""
        if self.flow not in ("travel", "armed", "gate"):
            return False
        standing = given.get("standing")
        if standing is None or not self.field_clear(given):
            return False
        return any(up is False for up in standing)

    def field_clear(self, given):
        """StageFlow.FieldClear (L1b-19)."""
        if self.flow in ("fight", "breather"):
            return given["spawningDone"] and given["alive"] == 0
        return given["spawningDone"] and given["awake"] == 0

    def armed_index(self):
        index = self.stage if self.flow == "armed" else self.stage + 1 if self.flow == "travel" else 0
        stages = self.plan["stages"]
        return index if 1 <= index <= len(stages) and stages[index - 1]["kind"] == "camp" else 0

    def triggered(self, zone, given):
        cx, cz, hx, hz = zone["trigger"]
        for index, root in enumerate(given["roots"]):
            above = root[1] - zone["floorY"]
            standing = given.get("standing")
            if (-self.rules["triggerBelow"] <= above <= self.rules["triggerHeight"]
                    and abs(root[0] - cx) <= hx and abs(root[2] - cz) <= hz
                    and (standing is None or standing[index] is not False)):
                return True
        return False

    def to_gate(self, index, t):
        self.stage = index
        self.flow = "gate"
        self.gate_at = t + self.rules["gateSeconds"]
        self.emit("gate", stage=index, at=self.gate_at)
        self.on_gate(index, t)

    def to_close(self, t):
        first = max(self.first_wave, 1)
        self.first_wave = 1
        self.flow = "fight"
        self.wave = first
        self.settled = first - 1
        self.closed_at = t
        self.emit("close", stage=self.stage)
        self.emit("wave", stage=self.stage, wave=first)
        self.on_close(t)
        self.on_wave(first, False, t)

    def leave_camp(self, t, skipped=False):
        """StageFlow's leaveCamp: `open` (`skipped` when a Studio skip passed the camp: L1b-22,
        a skip pays nothing), then the next stage or the end."""
        stages = self.plan["stages"]
        index = self.stage
        zone = stages[index - 1]["zone"]
        if zone is not None:
            self.done[zone["floor"]] = True
        self.cleared += 1
        self.last_cleared = index
        self.emit("open", stage=index, skipped=skipped)
        self.on_open(t, skipped=skipped)
        if index >= len(stages):
            self.emit("end", stage=index, reason="cleared")
            self.end("cleared", t)
            return
        self.stage = index + 1
        self.flow = "armed" if stages[self.stage - 1]["kind"] == "camp" else "travel"
        self.wave = 0
        if self.flow == "travel":
            self.emit("travel", stage=self.stage)

    def progress(self, given, t):
        """StageFlow.progress (L1b-18, L1b-17), in every live step before the rows."""
        reach = self.rules["checkpointReach"]
        standing = given.get("standing")
        for index, zone in enumerate(self.zones, 1):
            mark = zone["checkpoint"]
            if mark is None or self.reached.get(index):
                continue
            for root_index, root in enumerate(given["roots"]):
                rise = root[1] - zone["floorY"]
                flat = math.sqrt((root[0] - mark[0]) ** 2 + (root[2] - mark[1]) ** 2)
                if (flat <= reach and -self.rules["triggerBelow"] <= rise <= self.rules["triggerHeight"]
                        and (standing is None or standing[root_index] is not False)):
                    self.reached[index] = True
                    self.emit("reach", stage=self.stage, zone=index)
                    self.on_reach(index, t)
                    break
        by_floor = given.get("aliveByFloor") or []
        left = given.get("tentLeft") or []
        for index, zone in enumerate(self.zones, 1):
            alive = by_floor[index - 1] if index <= len(by_floor) else None
            if zone["locks"] or zone["residents"] <= 0 or self.done.get(index) or alive != 0:
                continue
            if (left[index - 1] if index <= len(left) else 0) != 0:
                continue  # L1b-W2-8: its tent's stock is still to come out
            self.done[index] = True
            self.cleared += 1
            self.emit("campClear", stage=self.stage, zone=index)
            self.on_camp_clear(index, t)

    def merge_ok(self, given):
        """The director's answer, as WaveService computes it (scripted runs hand their own)."""
        zone = self.live_zone()
        queued = given["alive"] - (self.grouped_on(zone["floor"]) if zone is not None else 0)
        dead = self.sc.dead_fraction(self.spawned, queued)  # L1b-W2-26: only what the waves queued
        return self.sc.should_merge(self.tempo, dead, self.director)

    def breather_input(self):
        return self.sc.breather_seconds(self.tempo, self.director)

    def advance(self, t):
        """[advance] StageFlow.Advance, row for row."""
        stages = self.plan["stages"]
        if self.flow == "over":
            return
        cap = self.level["runCapSeconds"]  # WaveService: a cap of 0 or less is no cap
        if cap > 0 and t >= cap:
            self.emit("end", stage=self.stage, reason="runCap")
            self.end("runCap", t)
            return
        given = self.flow_input(t)
        clear = self.field_clear(given)
        fallen = given["fallen"]
        if fallen is not None and not clear:
            self.emit("end", stage=self.stage, reason=fallen)
            self.end(fallen, self.downs[-1] if self.downs else t)
            return
        self.progress(given, t)
        if self.flow == "over":
            return
        if self.flow in ("travel", "armed"):
            index = self.armed_index()
            if index != 0 and self.triggered(stages[index - 1]["zone"], given):
                self.to_gate(index, t)
            return
        if self.flow == "gate":
            if t >= self.gate_at - THREAT_EPS:
                if fallen is not None:
                    self.flow = "armed"
                    self.gate_at = 0.0
                    self.emit("rearm", stage=self.stage)
                    self.on_rearm(t)
                else:
                    self.to_close(t)
            return
        if self.flow == "breather":
            if t >= self.breather_until - THREAT_EPS:
                self.wave += 1
                self.flow = "fight"
                self.emit("wave", stage=self.stage, wave=self.wave)
                self.on_wave(self.wave, False, t)
            return
        # flow == "fight"
        if not given["spawningDone"]:
            return
        stage = stages[self.stage - 1]
        wave = self.wave
        if not clear:
            if (stage["merge"] and wave < stage["waves"] and not stage["boss"].get(wave)
                    and not stage["boss"].get(wave + 1) and self.merge_ok(given)):
                self.wave = wave + 1
                self.emit("wave", stage=self.stage, wave=wave + 1, merged=True)
                self.on_wave(wave + 1, True, t)
            return
        self.fought = list(given["fighters"])
        self.emit("clear", stage=self.stage, wave=wave, count=wave - self.settled)
        self.on_clear(t)
        self.settled = wave
        last_wave = wave >= stage["waves"]
        ending = last_wave and self.stage >= len(stages)
        self.emit("boundary", stage=self.stage, release=not ending)
        self.stand_up(t)
        if not last_wave:
            self.flow = "breather"
            seconds = stage["breatherSeconds"]
            if seconds is None:
                seconds = self.breather_input()
            self.breathers += seconds
            self.breather_until = t + seconds
            self.emit("breather", stage=self.stage, at=self.breather_until)
            return
        self.leave_camp(t)

    def boss_wave_after(self, stage, after):
        if stage is None:
            return 0
        return next((wave for wave in range(after + 1, stage["waves"] + 1) if stage["boss"].get(wave)), 0)

    def skip(self, which, t, fighters=None):
        """StageFlow.Skip, Studio only, row for row (L1b-22). The simulator's own runs never skip:
        tools/check_stage_mirror.py holds this to the Luau."""
        stages = self.plan["stages"]
        if self.flow == "over":
            return
        live = self.flow in ("fight", "breather")
        if which == "stage":
            if self.flow in ("travel", "armed"):
                index = self.armed_index()
                if index != 0:
                    self.emit("move", stage=index)
                    self.on_move(index, t)
                    self.to_gate(index, t)
            elif self.flow == "gate":
                self.to_close(t)
            else:
                self.fought = list(fighters) if fighters is not None else []
                ending = self.stage >= len(stages)
                self.emit("drop", stage=self.stage)
                self.on_drop(t)
                self.emit("boundary", stage=self.stage, release=not ending)
                self.stand_up(t)
                self.leave_camp(t, skipped=True)
            return
        if which != "boss":
            return
        here = stages[self.stage - 1] if 1 <= self.stage <= len(stages) else None
        if live or self.flow in ("gate", "armed"):
            wave = self.boss_wave_after(here, self.wave if live else 0)
            if wave != 0:
                if live:
                    self.flow = "fight"
                    self.wave = wave
                    self.settled = wave - 1
                    self.emit("drop", stage=self.stage)
                    self.on_drop(t)
                    self.emit("wave", stage=self.stage, wave=wave)
                    self.on_wave(wave, False, t)
                elif self.flow == "gate":
                    self.first_wave = wave
                    self.to_close(t)
                else:
                    self.first_wave = wave
                    self.emit("move", stage=self.stage)
                    self.on_move(self.stage, t)
                    self.to_gate(self.stage, t)
                return
        target = target_wave = 0
        for index in range(self.stage + 1, len(stages) + 1):
            wave = self.boss_wave_after(stages[index - 1], 0)
            if wave != 0:
                target, target_wave = index, wave
                break
        if target == 0:
            return
        if live or self.flow == "gate":
            self.emit("drop", stage=self.stage)
            self.on_drop(t)
        for index in range(self.stage, target):
            if 1 <= index <= len(stages) and stages[index - 1]["kind"] == "camp":
                zone = stages[index - 1]["zone"]
                if zone is not None:
                    self.done[zone["floor"]] = True
                self.cleared += 1
                self.last_cleared = index
                self.emit("open", stage=index, skipped=True)
                self.on_open(t, index, skipped=True)
        self.first_wave = target_wave
        self.wave = 0
        self.emit("move", stage=target)
        self.on_move(target, t)
        self.to_gate(target, t)

    def force(self, wave, t):
        """StageFlow.Force, Studio only (the `wave` lever)."""
        stages = self.plan["stages"]
        stage = stages[self.stage - 1] if 1 <= self.stage <= len(stages) else None
        if stage is None or self.flow not in ("fight", "breather") or stage["waves"] < 1:
            return
        target = min(max(math.floor(wave), 1), stage["waves"])
        self.flow = "fight"
        self.wave = target
        self.settled = target - 1
        self.emit("drop", stage=self.stage)
        self.on_drop(t)
        self.emit("wave", stage=self.stage, wave=target)
        self.on_wave(target, False, t)

    def directs(self):
        return self.flow in ("fight", "breather")

    def still_closing(self, t):
        return self.flow in ("fight", "breather") and t - self.closed_at < self.rules["closeGraceSeconds"]

    def earns_star(self, user_id):
        return self.end_reason == "cleared" and user_id in self.fought

    def safe_point(self, busy=None, threats=None):
        """StageFlow.SafePoint (L1b-18; the fix round skips a checkpoint a threat reaches on the
        flat): (x, y, z)."""
        if self.flow in ("gate", "fight", "breather"):
            zone = self.live_zone()
            if zone is not None:
                return zone["entry"][0], zone["floorY"], zone["entry"][1]
        for index in range(len(self.zones), 0, -1):
            zone = self.zones[index - 1]
            mark = zone["checkpoint"]
            quiet = not (busy or {}).get(index)
            if mark is not None and any(math.sqrt((mark[0] - th["at"][0]) ** 2 + (mark[1] - th["at"][2]) ** 2)
                                        <= th["reach"] for th in threats or []):
                quiet = False
            if mark is not None and self.reached.get(index) and quiet:
                return zone["checkpoint"][0], zone["floorY"], zone["checkpoint"][1]
        stages = self.plan["stages"]
        cleared = stages[self.last_cleared - 1] if self.last_cleared >= 1 else None
        if cleared is not None and cleared["zone"] is not None:
            zone = cleared["zone"]
            return zone["exit"][0], zone["floorY"], zone["exit"][1]
        return self.plan["start"][0], self.plan["startY"], self.plan["start"][1]

    def tick(self, t):
        """WaveService.tick, in its order: the tempo while a camp is closed, the spawns in its
        fight, the close judged again in its grace, then StageFlow.Advance."""
        if self.directs():
            self.update_tempo(t)
        if self.flow == "fight":
            self.spawn_boss(t)
            self.spawn_next(t)
        self.send_tents(t)
        if self.still_closing(t) and not self.entered:
            zone = self.live_zone()
            cx, cz = zone["rect"][0], zone["rect"][1]
            if abs(self.x - cx) > zone["inner"][2] or abs(self.z - cz) > zone["inner"][3]:
                self.x, self.z = zone["entry"]
                self.entered = True
                self.grace_moves += 1
        self.advance(t)
        if self.flow != "over" and self.stands_up(self.flow_input(t)):
            # A down on a quiet road (nothing awake): WaveService's placer puts him on the safe
            # point and he gets up (never met in the gated runs; it is here so a run cannot hang).
            x, y, z = self.safe_point(self.busy(), self.safe_threats())
            self.x, self.z, self.ground = x, z, y
            self.stand_up(t)

    # -- the player and the kills ---------------------------------------------------------------

    def swing(self, t):
        if self.policy.get("hunt") and (self.boss is None or not self.boss.alive):
            live = self.swingable()
            if live:
                nearest = min(live, key=lambda e: (e.x - self.x) ** 2 + (e.z - self.z) ** 2)
                self.quarry = nearest
                self.want = self.wanted(nearest)
            else:
                self.quarry = None
        super().swing(t)

    def credit(self, pool, shares):
        """WaveService: Combat.SplitCarry with the carry and the cash multiplier (1: no profile)."""
        paid = self.sc.split_carry(pool, shares, self.carry, {LEVEL_USER: 1.0})
        mine = paid.get(LEVEL_USER)
        if mine is None:
            return
        for key in self.wallet:
            self.wallet[key] += mine[key]
            self.priced[key] += pool[key] * shares[LEVEL_USER]
        self.credits += 1

    def fall(self, enemy):
        """WaveService.onCrowdKilled (L1b-15): the kill is paid at once, in every live phase: its
        kind's reward x the difficulty's rewardMult (Combat.KillReward), the boss's Valor on the
        boss, split by the kill's own damage book (ContributionShares; solo: all of it) through
        SplitCarry. The kill stamps the tempo. A body dismissed with its boss is no kill."""
        super().fall(enemy)
        now = self.world.now
        self.killed[enemy.name] = self.killed.get(enemy.name, 0) + 1
        mine = self.killed_in.setdefault(enemy.floor, {})
        mine[enemy.name] = mine.get(enemy.name, 0) + 1
        if self.camp is not None and enemy.floor == self.camp["floor"]:
            self.camp["killed"][enemy.name] = self.camp["killed"].get(enemy.name, 0) + 1
        self.stamps.append(now)
        if self.camp is not None and self.wave in self.camp["waves"] and enemy.floor == self.camp["floor"]:
            self.camp["waves"][self.wave]["kills"] += 1
        cash, materials = self.sc.kill_reward(self.crowd["rewards"], enemy.name, self.scales["rewardMult"])
        valor = self.boss_valor if enemy.boss else 0
        shares = self.sc.contribution_shares({LEVEL_USER: 1.0}, self.combat["coop"]["contributionFloor"])
        self.credit({"cash": cash, "materials": materials, "valor": valor}, shares)
        if enemy.boss:
            self.boss_fights[enemy.name] = (self.boss_fights.get(enemy.name, (now, None))[0], now)
            self.kill_at = None

    def where(self):
        """Where he is: the boss room he is shut in, else the camp whose in-play rectangle holds
        him, else the road."""
        if self.live is not None:
            return self.live["id"]
        for zone in self.zones:
            if self.near(zone):
                return zone["id"]
        return "road"

    def run(self):
        t = 0.0
        accumulator = 0.0
        down_in = None
        while self.end_reason is None:
            self.world.now = t
            self.steer(t)
            self.control(t, FRAME)
            if self.walking():
                self.walk_path(FRAME)
            accumulator += FRAME
            while accumulator >= self.interval - THREAT_EPS:
                accumulator -= self.interval
                self.crowd_step(t, self.interval)
                self.fighters[:] = [f for f in self.fighters if f.alive]
            self.resolve(t)
            if self.downs and down_in is None:
                down_in = self.where()
            self.tick(t)
            if self.end_reason is None and self.watch is not None and t >= self.watch:
                self.end("stopped", t)
            t += FRAME
        log = self.log
        first = self.camps[0] if self.camps else None
        closed = first["closedAt"] if first is not None else None
        names = {zone["id"]: zone["name"] for zone in self.zones}
        return {"end": self.end_reason, "at": self.end_at, "camps": self.camps, "zones": self.zones,
                "clearedAt": {self.zones[f - 1]["id"]: at for f, at in self.cleared_at.items()},
                "reachedAt": {self.zones[f - 1]["id"]: at for f, at in self.reached_at.items()},
                "waves": first["waves"] if first is not None else {}, "killed": self.killed,
                "killedIn": {self.zones[f - 1]["id"]: k for f, k in self.killed_in.items() if f is not None},
                "bosses": self.boss_fights, "downs": len(self.downs), "firstDown": self.downs[0] if self.downs else None,
                "downAfterClose": (self.downs[0] - closed) if self.downs and closed is not None else None,
                "hitAfterClose": (log[0][0] - closed) if log and closed is not None else None,
                "downIn": down_in, "downInName": names.get(down_in, down_in),
                "hits": len(log), "damage": sum(d for _w, d, _k, _s in log), "dodged": self.dodged,
                "byKind": {k: sum(d for _w, d, kk, _s in log if kk == k) for k in {kk for _w, _d, kk, _s in log}},
                "peakAlive": self.peak_alive, "placed": self.placed, "breathers": self.breathers,
                "summoned": self.summoned, "forgiven": self.forgiven, "firstHit": log[0][0] if log else None,
                "wallet": dict(self.wallet), "priced": dict(self.priced), "credits": self.credits,
                "walked": self.walked, "wave": self.wave, "graceMoves": self.grace_moves,
                "stage": self.plan["stages"][self.stage - 1]["name"], "star": self.earns_star(self.fighters_now[0]),
                "woke": dict(self.woke), "events": list(self.events), "firstHits": dict(self.first_hit),
                "firstWindups": dict(self.first_windup), "blocked": dict(self.blocked), "evaded": self.world.evaded,
                "stoodAt": self.stood_at,
                "downAfterWake": (self.downs[0] - self.stood_at) if self.downs and self.stood_at is not None else None,
                "kite": self.kite, "groups": [g["def"]["id"] for g in self.groups],
                "tents": [{"id": x["id"], "camp": x["camp"], "stock": len(x["kinds"]), "sent": x["sent"],
                           "left": x["state"]["left"], "sentAt": list(x["sentAt"]), "refused": x["refused"]}
                          for x in self.tents],
                "joined": list(self.joined), "bonuses": dict(self.bonuses), "dormantSteps": self.dormant_steps,
                "wakes": sum(1 for e in self.events if e[2] == "rest" and e[3] == "rise"),
                "leashes": sum(1 for e in self.events if e[2] == "fight" and e[3] == "home"),
                "rests": sum(1 for e in self.events if e[2] == "home" and e[3] == "rest")}


THREAT_POLICIES["mission"] = {"label": "reacts to every tell, attacks the nearest", "fight": True, "react": True,
                              "boss": True, "chase": True, "hold": True, "hunt": True}
THREAT_POLICIES["rampage"] = {"label": "attacks the nearest, never dodges", "fight": True, "boss": True,
                              "chase": True, "hunt": True}
THREAT_POLICIES["human"] = dict(THREAT_POLICIES["mission"], label="a human's reaction, attacks the nearest",
                                reaction=HUMAN_REACTION_SECONDS)
# L1b: the still player walks the route and stops for good where a group first wakes; the
# kiting player wakes a group, runs out past its reach, waits for it to go home and heal and
# comes back; the edge player stands just past chaseMargin of a group with no shooter and hits
# whatever is in his reach.
THREAT_POLICIES["still"] = {"label": "walks in, stands where a group wakes", "stop": True}
THREAT_POLICIES["kite"] = dict(THREAT_POLICIES["mission"], label="wakes a group, runs out, comes back", kite=True)
THREAT_POLICIES["edge"] = {"label": "stands just past chaseMargin, hits the edge", "fight": True, "edge": True}
# L1b Wave 2: the sneak walks layout.sneak to the boss room's entry and never attacks; the
# careless road walks the route across every open camp, entry to exit, never fighting, to the
# boss room's countdown.
THREAT_POLICIES["sneak"] = {"label": "keeps to the sneak path, never attacks", "sneak": True}
THREAT_POLICIES["cross"] = {"label": "walks the road through every camp, never fights", "cross": True}
THREAT_POLICIES["parked"] = {"label": "stands at the start point, never moves", "parked": True}


def preset_gears(combat_cfg):
    presets = [{"melee": p["melee"], "ranged": p["ranged"]} for p in combat_cfg["debug"].get("gearPresets") or []]
    return sorted(presets, key=lambda g: (g["melee"], g["ranged"])) or [mission_gear()]


def recommended_gear(presets, tier):
    return dict(next((g for g in presets if g["melee"] == tier), {"melee": tier, "ranged": tier}))


def preset_below(presets, gear):
    under = [g for g in presets if (g["melee"], g["ranged"]) < (gear["melee"], gear["ranged"])]
    return dict(under[-1]) if under else None


def gear_text(gear):
    return f"{gear['melee']}/{gear['ranged']}"


def camp_env(plan, hp, zone_id, start=None):
    """The threat's env for one camp, in the camp's own frame: its half extents, and where the
    player of an isolated fight starts (`start` in world x and z; default the camp's entry)."""
    zone = next(z for z in plan["zones"] if z["id"] == zone_id)
    cx, cz, hx, hz = zone["rect"]
    sx, sz = start if start is not None else zone["entry"]
    return {"half": (hx, hz), "pad": (sx - cx, sz - cz), "hp": hp, "tolerance": timing_tolerance(),
            "spawns": [(x - cx, z - cz) for x, z in zone["spawns"]]}


def boss_spots(level):
    found = {}
    for stage in level["stages"]:
        for wave in stage.get("waves") or []:
            boss = wave.get("boss")
            if boss and boss["kind"] not in found:
                found[boss["kind"]] = (stage["zone"], boss["at"])
    return found


def boss_alone(view, plan, hp, level, name, start=None, seeds=THREAT_SEEDS, seconds=None, weapon=None):
    """The reacting player's fights with one of the level's bosses, alone in its camp at its
    `boss.at`: a boss_row, or None when the level has no such boss."""
    spot = boss_spots(level).get(name)
    if spot is None:
        return None
    zone_id, at = spot
    set_name = f"_level_{level['id']}_{name}"
    view["dummySets"][set_name] = [{"kind": name, "behaviour": "fight", "count": 1, "at": list(at), "spacing": 0,
                                    "respawnSeconds": 12}]
    return boss_row(view, camp_env(plan, hp, zone_id, start), set_name, "slay", weapon=weapon, seeds=seeds,
                    seconds=seconds)


def open_zones(plan, layout):
    """The open camps with residents, in the order the route meets them."""
    route = [(p["x"], p["z"]) for p in layout.get("route") or []]

    def at(zone):
        found = next((i for i, p in enumerate(route) if math.hypot(p[0] - zone["entry"][0], p[1] - zone["entry"][1]) < 0.01),
                     None)
        return found if found is not None else math.inf

    return sorted((z for z in plan["zones"] if not z["locks"] and z["residents"] > 0), key=at)


def route_before(layout, zone):
    """The index of the route point before a zone's entry (where an approach starts), or None."""
    route = layout.get("route") or []
    entry = next((i for i, p in enumerate(route) if math.hypot(p["x"] - zone["entry"][0], p["z"] - zone["entry"][1]) < 0.01),
                 None)
    return entry - 1 if entry else None


def strike_runs(view, hp, ctx, level, layout, difficulty):
    """The first strike (L1b bands): every fire group of an open camp, alone, met by the reacting
    player walking in from the route point before its camp's entry. {group id: [run per seed]},
    each run with `strike`: when the group woke and why, his first hit that landed on a member,
    and the first windup a member began."""
    plan = plan_level(level, layout, difficulty, ctx["combat"]["levels"], ctx["ranks"], view["crowd"]["kinds"])
    found = {}
    for index, defn in enumerate(plan["groups"], 1):
        zone = plan["zones"][defn["floor"] - 1]
        start = route_before(layout, zone)
        if defn["posture"] != "fire" or zone["locks"] or start is None:
            continue
        runs = []
        for seed in MISSION_SEEDS:
            r = LevelRun(view, hp, ctx, level, layout, difficulty, THREAT_POLICIES["mission"], seed, only={defn["id"]},
                         from_route=start, seconds=STRIKE_SECONDS, stop_zone=defn["floor"]).run()
            r["strike"] = {"group": defn["id"], "woke": r["woke"].get(index), "hit": r["firstHits"].get(index),
                           "windup": r["firstWindups"].get(index)}
            runs.append(r)
        found[defn["id"]] = runs
    return found


def edge_group(plan, layout, cfg):
    """The group of the edge band: the first group with no keepAway kind in the first open camp
    the route meets, and where the player stands: just past chaseMargin of the floor's edge
    nearest its posts, in line with their middle. (group index, def, (x, z))."""
    kinds = cfg["crowd"]["kinds"]
    camps = open_zones(plan, layout)
    margin = load_config(COMBAT_PATH)["camps"]["chaseMargin"]
    for zone in camps:
        for index, defn in enumerate(plan["groups"], 1):
            if defn["floor"] != zone["floor"] or any(kinds[u["kind"]].get("brain") == "keepAway" for u in defn["units"]):
                continue
            posts = cb_posts(defn, sum(u["count"] for u in defn["units"]))
            px = sum(p["at"][0] for p in posts) / len(posts)
            pz = sum(p["at"][2] for p in posts) / len(posts)
            cx, cz, hx, hz = zone["rect"]
            out = margin + EDGE_SPARE
            sides = {(cx - hx - out, pz): px - (cx - hx), (cx + hx + out, pz): (cx + hx) - px,
                     (px, cz - hz - out): pz - (cz - hz), (px, cz + hz + out): (cz + hz) - pz}
            return index, defn, min(sides, key=sides.get)
    return None


def edge_runs(view, hp, ctx, level, layout, difficulty, cfg):
    plan = plan_level(level, layout, difficulty, ctx["combat"]["levels"], ctx["ranks"], view["crowd"]["kinds"])
    found = edge_group(plan, layout, cfg)
    if found is None:
        return []
    index, defn, (sx, sz) = found
    runs = []
    for seed in MISSION_SEEDS:
        run = LevelRun(view, hp, ctx, level, layout, difficulty, THREAT_POLICIES["edge"], seed, only={defn["id"]},
                       start=(sx, sz, defn["floorY"]), seconds=EDGE_SECONDS)
        run.x, run.z = sx, sz  # exactly there: no seed's offset
        run.anchor = (sx, sz)
        r = run.run()
        r["edge"] = {"group": defn["id"], "at": (sx, sz), "kills": sum(r["killedIn"].get(defn["camp"], {}).values()),
                     "blocked": r["blocked"].get(index, 0), "wakes": r["wakes"]}
        runs.append(r)
    return runs


def chain_of(defs, rules, living, wakers):
    """CampBrain.JoinIn from rest: the def ids a wake of `wakers` (def ids) brings in, every
    other group at rest, `living` {def id: members}."""
    groups = [cb_new_group(defn, 0.0) for defn in defs]
    posts = [group_posts(defn) for defn in defs]
    index = {defn["id"]: i for i, defn in enumerate(defs, 1)}
    gaps = {}
    for i, a in enumerate(defs, 1):
        for j, b in enumerate(defs, 1):
            if i != j and a["camp"] == b["camp"]:
                gaps.setdefault(i, {})[j] = cb_gap(posts[i - 1], posts[j - 1])
    alive = {index[k]: v for k, v in living.items()}
    return [defs[j - 1]["id"] for j in cb_join_in(groups, alive, gaps, [index[w] for w in wakers], rules)]


def first_joins(run, plan, rules):
    """Each open camp's first wake in a run (by sight or a hit), what it brought in, and what the
    chain from rest says it should: [(camp, wakers, joined, expected)]."""
    defs = plan["groups"] + [tent["def"] for tent in plan["tents"]]
    living = {d["id"]: sum(u["count"] for u in d["units"]) for d in plan["groups"]}
    living.update({tent["def"]["id"]: 0 for tent in plan["tents"]})
    ids = run["groups"]
    found = []
    seen = set()
    for _when, woke, joined in run["joined"]:
        camp = defs[woke[0] - 1]["camp"]
        if camp in seen:
            continue
        seen.add(camp)
        wakers = [ids[i - 1] for i in woke]
        found.append((camp, wakers, [ids[i - 1] for i in joined], chain_of(defs, rules, living, wakers)))
    return found


def tent_alone_runs(view, hp, ctx, level, layout, difficulty, plan):
    """A tent with no resident to wait for (L1b-W2-7's second clause): each tent's group alone,
    the player far away at the start, watched TENT_ALONE_SECONDS. {tent id: [run per seed]}."""
    found = {}
    for tent in plan["tents"]:
        found[tent["def"]["id"]] = [
            LevelRun(view, hp, ctx, level, layout, difficulty, THREAT_POLICIES["parked"], seed, only={tent["def"]["id"]},
                     seconds=tent["every"] * len(tent["kinds"]) + TENT_ALONE_SECONDS).run()
            for seed in MISSION_SEEDS[:1]]
    return found


def bow_rows(view, plan, hp, level, bow):
    """The bow at 2 / 2 (L1b-W2-20, reported): the default ranged family alone against each of
    BOW_KINDS, one at a time at the boss's spot in the boss room, the reacting player aiming at
    its body or at its head, under the old ray rule and the new one (L1b-W2-15/16). Rows of
    (kind, aim, rule, a boss_row)."""
    global RAY_RULE
    spot = boss_spots(level).get(FOREST_BOSS)
    if spot is None:
        return []
    zone_id, at = spot
    rows = []
    saved = RAY_RULE
    try:
        for kind in BOW_KINDS:
            set_name = f"_bow_{kind}"
            view["dummySets"][set_name] = [{"kind": kind, "behaviour": "fight", "count": 1, "at": list(at),
                                            "spacing": 0, "respawnSeconds": 1e9}]
            for aim in ("body", "head"):
                for rule in ("sphere", "capsule"):
                    RAY_RULE = rule
                    policy = dict(THREAT_POLICIES["mission"], aim=aim, anyKill=kind,
                                  label=f"{aim} aim, {rule} rule")
                    THREAT_POLICIES["_bow"] = policy
                    row = boss_row(view, camp_env(plan, hp, zone_id), set_name, "_bow", weapon=bow,
                                   seeds=BOSS_RANGED_SEEDS, seconds=BOW_SECONDS)
                    rows.append((kind, aim, rule, row))
    finally:
        RAY_RULE = saved
        THREAT_POLICIES.pop("_bow", None)
    return rows


def mission_report(cfg, path=None, mission=None, careless=True):
    """The Raider Arena: a mission's crowd block played as a level through the two adapters of
    L1 ruling 27. Everything its P5 bands read: the hit shares, the still player in the first
    wave, the two bosses at the mission's scales, and the whole run of the reacting player (and,
    for information, of one who never dodges). `mission` = an already loaded mission config."""
    import sim_combat as sc
    ctx = level_context()
    if mission is None:
        mission = load_config(path or MISSIONS_DIR / MISSION_FILE)
    if mission.get("crowd") is None:
        return None
    combat_cfg = ctx["combat"]
    below = combat_cfg["player"]["rescue"]["below"]
    file = next((f for f in ctx["files"].values() if f.get("mission") == mission["id"]), None)
    if file is None:  # a mission no level names yet: the same adapters, on its own arena
        file = {"version": 1, "id": mission["id"], "name": mission["name"], "layout": None, "mission": mission["id"]}
        layout = arena_as_layout(mission["arena"], -below)
    else:
        layout = load_level_layout(file["layout"], below)
    difficulty = ctx["expeditions"]["difficulties"][0]
    level = resolve_level(file, mission, combat_cfg["director"]["runCapSeconds"], difficulty)
    gear = mission_gear()
    scales = level["difficulties"][difficulty]
    view, hp = level_view(cfg, scales, level["crowd"]["regenShare"], ctx["armory"], gear)
    plan = plan_level(level, layout, difficulty, combat_cfg["levels"], ctx["ranks"], cfg["crowd"]["kinds"])
    hits = hit_rows(cfg, view, hp, level_kinds(view, level, ctx["ranks"][difficulty], ctx["ranks"]))

    def run(key, seed):
        return LevelRun(view, hp, ctx, level, layout, difficulty, THREAT_POLICIES[key], seed).run()

    stand = [run("stand", seed) for seed in MISSION_SEEDS]
    bosses = {}
    for name in MISSION_BOSS_SECONDS:
        row = boss_alone(view, plan, hp, level, name, start=plan["start"])
        if row is not None:
            bosses[name] = row
    runs = [run("mission", seed) for seed in MISSION_SEEDS]
    careless_runs = [run("rampage", seed) for seed in MISSION_SEEDS] if careless else []
    return {"mission": mission, "level": level, "layout": layout, "view": view, "gear": gear, "hp": hp, "hits": hits,
            "stand": stand, "bosses": bosses, "runs": runs, "careless": careless_runs, "combat": combat_cfg, "sc": sc}


def forest_report(cfg, careless=True, level_id=FOREST_LEVEL, human=True, ranged=True, below=True, scenarios=True):
    """Forest Road's bands, per difficulty, each at its recommended gear (Normal at the proving
    gear, Hard and Brutal at the gear preset of their recommendedTier): the hit shares, the boss
    alone in its camp, whole runs of the reacting player, of the player with a human's reaction
    and of the one who never dodges. Normal also has L1b's scenarios: the still player, the first
    strike on every fire group, the kiting player and the edge player. Hard and Brutal twice more,
    reported: one preset below (`below`) and at the proving gear. For information, the default
    ranged family (the Longbow) through the first camp and against the boss."""
    import sim_combat as sc
    ctx = level_context()
    file = ctx["files"].get(level_id)
    if file is None:
        return None
    combat_cfg = ctx["combat"]
    level = resolve_level(file, ctx["missions"].get(file.get("mission")), combat_cfg["director"]["runCapSeconds"],
                          ctx["expeditions"]["difficulties"][0])
    layout = load_level_layout(level["layout"], combat_cfg["player"]["rescue"]["below"])
    problems = level_problems(level, layout, combat_cfg["levels"], cfg["crowd"]["kinds"], ctx["ranks"],
                              cfg["crowd"]["maxAlive"]) + cb_problems(combat_cfg.get("camps"))
    if problems:
        raise SystemExit(f"sim_range: {level_id} cannot be played (StageFlow.Validate refuses it): " + "; ".join(problems))
    proving = mission_gear()
    presets = preset_gears(combat_cfg)
    bow = cfg["loadout"]["ranged"]
    report = {"level": level, "layout": layout, "ctx": ctx, "sc": sc, "proving": proving, "presets": presets,
              "bow": bow, "difficulties": {}}

    def runs_of(view, hp, difficulty, key, weapon=None, stop_zone=None):
        policy = THREAT_POLICIES[key] if weapon is None else dict(THREAT_POLICIES[key], weapon=(weapon, None))
        return [LevelRun(view, hp, ctx, level, layout, difficulty, policy, seed, stop_zone=stop_zone).run()
                for seed in MISSION_SEEDS]

    for difficulty in ctx["expeditions"]["difficulties"]:
        scales = level["difficulties"].get(difficulty)
        if scales is None:
            continue
        rank = ctx["ranks"][difficulty]
        gear = dict(proving) if rank == 1 else recommended_gear(presets, scales["recommendedTier"])
        plan = plan_level(level, layout, difficulty, combat_cfg["levels"], ctx["ranks"], cfg["crowd"]["kinds"])
        view, hp = level_view(cfg, scales, level["crowd"]["regenShare"], ctx["armory"], gear)
        first_open = (open_zones(plan, layout) or [None])[0]
        row = {"scales": scales, "gear": gear, "hp": hp, "view": view, "plan": plan,
               "hits": hit_rows(cfg, view, hp, level_kinds(view, level, rank, ctx["ranks"])),
               "boss": boss_alone(view, plan, hp, level, FOREST_BOSS),
               "runs": runs_of(view, hp, difficulty, "mission"),
               "human": runs_of(view, hp, difficulty, "human") if human else [],
               "careless": runs_of(view, hp, difficulty, "rampage") if careless else [],
               "stand": [], "strikes": {}, "kite": [], "edge": [], "under": None, "below": None, "ranged": None}
        if ranged and first_open is not None:
            row["ranged"] = {"camp": runs_of(view, hp, difficulty, "mission", bow, first_open["floor"]),
                             "zone": first_open["id"],
                             "boss": boss_alone(view, plan, hp, level, FOREST_BOSS, seeds=BOSS_RANGED_SEEDS, weapon=bow)}
        row.update({"sneak": [], "road": [], "tentAlone": {}, "bow": []})
        if rank == 1:
            if scenarios:
                row["stand"] = runs_of(view, hp, difficulty, "still")
                row["strikes"] = strike_runs(view, hp, ctx, level, layout, difficulty)
                row["kite"] = runs_of(view, hp, difficulty, "kite")
                row["edge"] = edge_runs(view, hp, ctx, level, layout, difficulty, cfg)
                row["sneak"] = runs_of(view, hp, difficulty, "sneak")
                row["road"] = runs_of(view, hp, difficulty, "cross")
                row["tentAlone"] = tent_alone_runs(view, hp, ctx, level, layout, difficulty, plan)
            if ranged:
                row["bow"] = bow_rows(view, plan, hp, level, bow)
        else:
            weak_view, weak_hp = level_view(cfg, scales, level["crowd"]["regenShare"], ctx["armory"], proving)
            row["under"] = {
                "gear": dict(proving), "hp": weak_hp,
                "hits": hit_rows(cfg, weak_view, weak_hp, level_kinds(weak_view, level, rank, ctx["ranks"])),
                "boss": boss_alone(weak_view, plan, weak_hp, level, FOREST_BOSS, seeds=BOSS_RANGED_SEEDS),
                "careless": runs_of(weak_view, weak_hp, difficulty, "rampage") if careless else []}
            lesser = preset_below(presets, gear)
            if lesser is not None and below:
                if lesser == proving:
                    low_view, low_hp, low_boss = weak_view, weak_hp, row["under"]["boss"]
                else:
                    low_view, low_hp = level_view(cfg, scales, level["crowd"]["regenShare"], ctx["armory"], lesser)
                    low_boss = boss_alone(low_view, plan, low_hp, level, FOREST_BOSS, seeds=BOSS_RANGED_SEEDS)
                row["below"] = {"gear": lesser, "hp": low_hp, "boss": low_boss,
                                "human": runs_of(low_view, low_hp, difficulty, "human") if human else [],
                                "runs": runs_of(low_view, low_hp, difficulty, "mission")}
        report["difficulties"][difficulty] = row
    return report


def print_run_rows(runs):
    print("    seed  end      clear    down  hits  damage  peak alive  breathers  kills")
    for seed, r in zip(MISSION_SEEDS, runs):
        kills = sum(r["killed"].values())
        print(f"    {seed:>4}  {r['end']:<7}  {r['at'] / 60:5.2f} min  {r['downs']:>4}  {r['hits']:>4}  {r['damage']:>6.0f}  "
              f"{r['peakAlive']:>10}  {r['breathers']:>7.1f} s  {kills:>5}")


def wallet_text(r):
    w = r["wallet"]
    return f"{w['cash']:,} cash, {w['materials']} mat, {w['valor']} Valor"


def print_mission(cfg, report):
    if report is None:
        print()
        print("RAIDER ARENA: no crowd block, nothing to measure")
        return
    mission, view, level = report["mission"], report["view"], report["level"]
    scales_of = next(iter(level["difficulties"].values()))
    scales = view["_scales"]
    print()
    print(f"RAIDER ARENA (P5 and L1 ruling 27; {mission['name']} as a level of one camp, arena {mission['arena']}, gear "
          f"{report['gear']['melee']}/{report['gear']['ranged']}, health {report['hp']:.0f}; hpScale "
          f"{scales_of['hpScale']:g}, plateScale {scales_of['plateScale']:g}, damageScale {scales_of['damageScale']:g}, "
          f"regenShare {level['crowd']['regenShare']:g} = {view['player']['regenPerSecond']:.1f}/s; his HP-loss scale "
          f"melee x{scales['melee']:g}, ranged x{scales['ranged']:g})")
    print("  enemy hits at the arena's scale:")
    for h in report["hits"]:
        print(f"    {h['kind']:<9} {h['shape']:<6} {h['base']:>3} -> {h['damage']:>3} = {100 * h['share']:4.1f}% of the bar")
    print("  stands still in wave 1 (from the gates' closing, which is the wave's start): first hit "
          + ", ".join(fmt(r["hitAfterClose"], 0, 1).strip() for r in report["stand"]) + " s; down at "
          + ", ".join(fmt(r["downAfterClose"], 0, 1).strip() for r in report["stand"]) + " s")
    for name, row in report["bosses"].items():
        lo, hi = MISSION_BOSS_SECONDS[name]
        span = row["killSpan"]
        print(f"  {row['weapon']} against the {name} alone at its boss.at, from the pad: kill "
              f"{fmt(row['kill'], 0, 1).strip()} s ({span[0]:.1f}-{span[1]:.1f}) " if span else
              f"  {row['weapon']} against the {name}: never killed ", end="")
        print(f"[band {lo:.0f}-{hi:.0f}], hits of the boss {row['solid']}, lunges {row['lunges']}, "
              f"summoned {row['summoned']:.1f}, damage taken {row['damage']:.0f}")
    print("  the whole run, reacting player, default melee only (per seed; the clock starts at the start point, "
          f"{load_config(COMBAT_PATH)['levels']['gateSeconds']:g} s before the gates close):")
    print_run_rows(report["runs"])
    forgiven = sum(r["forgiven"] for r in report["runs"] + report["careless"])
    if forgiven:
        print(f"  downs on a field already clear, stood up at the boundary (a clear field wins): {forgiven}")
    first = report["runs"][0]
    print(f"  waves of seed {MISSION_SEEDS[0]}: wave  bodies  start  spawned by  clear  length  kills  merged")
    for wave, w in sorted(first["waves"].items()):
        clear = w["clear"]
        print(f"    {wave:>4}  {w['bodies'] + (1 if w['boss'] else 0):>6}  {w['start']:6.1f}  "
              f"{fmt(w['spawnEnd'], 0, 1):>9}  {fmt(clear, 0, 1):>6}  "
              f"{fmt(clear - w['start'] if clear is not None else None, 0, 1):>6}  {w['kills']:>5}  "
              f"{'yes' if w['merged'] else ''}")
    for name, (spawned, fell) in sorted(first["bosses"].items()):
        print(f"    the {name} in the run: {fmt(fell - spawned if fell is not None else None, 0, 1).strip()} s "
              f"from its rise to its fall")
    if report["careless"]:
        print("  the same player who never dodges (information): "
              + "; ".join(f"seed {seed} {r['end']} in wave {r['wave']} at {r['at'] / 60:.2f} min "
                          f"({r['hits']} hits; " + ", ".join(f"{k} {v:.0f}" for k, v in sorted(r["byKind"].items()))
                          + f"; kept {r['wallet']['cash']:,} cash)"
                          for seed, r in zip(MISSION_SEEDS, report["careless"])))
    killed = {}
    for r in report["runs"]:
        for kind, n in r["killed"].items():
            killed[kind] = killed.get(kind, 0) + n / len(report["runs"])
    print("  kills per run (mean): " + ", ".join(f"{k} {v:.1f}" for k, v in sorted(killed.items())))
    print("  what the runs paid (every kill as it falls, L1b-15): "
          + "; ".join(f"{r['wallet']['cash']:,} cash, {r['wallet']['materials']} {mission['material']}, "
                      f"{r['wallet']['valor']} Valor" for r in report["runs"])
          + " (sim_combat.py --check bands the configured run)")


def check_mission(cfg, report, expect):
    if report is None:
        return
    mission, view, level = report["mission"], report["view"], report["level"]
    crowd = level["crowd"]
    hp = report["hp"]
    worst = max(report["hits"], key=lambda h: h["share"])
    expect(worst["share"] <= HIT_SHARE_MAX,
           f"arena: no enemy hit over {HIT_SHARE_MAX:.0%} of the bar ({hp:.0f}): the worst is the {worst['kind']}'s "
           f"{worst['shape']}, {worst['damage']} = {worst['share']:.1%}")
    regen = crowd["regenShare"]
    expect(abs(regen / MISSION_REGEN_SHARE - 1) <= MISSION_REGEN_TOLERANCE,
           f"arena: regenShare {regen:g} within {MISSION_REGEN_TOLERANCE:.0%} of the range's 10/130 = "
           f"{MISSION_REGEN_SHARE:.4f} ({view['player']['regenPerSecond']:.1f}/s on {hp:.0f})")
    lo, hi = MISSION_STAND_DOWN_SECONDS
    downs = [r["downAfterClose"] for r in report["stand"]]
    expect(all(d is not None and lo <= d <= hi for d in downs),
           f"arena: standing still in wave 1, down in {lo:.0f}-{hi:.0f} s from the wave's start, "
           f"every seed: " + ", ".join(fmt(d, 0, 1).strip() for d in downs))
    for name, (lo, hi) in MISSION_BOSS_SECONDS.items():
        row = report["bosses"].get(name)
        if row is None:
            expect(False, f"arena: the {name} is fought in the arena")
            continue
        span = row["killSpan"]
        expect(span is not None and lo <= span[0] and span[1] <= hi,
               f"arena: the {name} with the {row['weapon']}, every seed, {lo:.0f}-{hi:.0f} s: "
               + (f"{span[0]:.1f}-{span[1]:.1f} s" if span else "never killed"))
        expect(row["solid"] == 0 and row["lunges"] == 0,
               f"arena: the {name}: the reacting player takes no hit ({row['solid']} of the boss, "
               f"{row['lunges']} lunges)")
    lo, hi = MISSION_CLEAR_SECONDS
    for seed, r in zip(MISSION_SEEDS, report["runs"]):
        expect(r["end"] == "cleared" and lo <= r["at"] <= hi,
               f"arena: seed {seed}, the reacting player clears all {mission['waves']} waves in "
               f"{lo / 60:.0f}-{hi / 60:.0f} min: {r['end']} at {r['at'] / 60:.2f} min, {r['downs']} down(s)")
    alive = max(r["peakAlive"] for r in report["runs"])
    expect(alive <= cfg["crowd"]["maxAlive"] and crowd["maxAlive"] <= cfg["crowd"]["maxAlive"],
           f"arena: maxAlive {crowd['maxAlive']} <= the crowd's {cfg['crowd']['maxAlive']} (peak alive {alive})")
    # L1b-15: every kill is paid as it falls, so a failed run keeps every kill it made.
    every = report["runs"] + report["careless"] + report["stand"]
    paid = all(r["wallet"] == {k: luau_round(v) for k, v in r["priced"].items()} for r in every)
    kept = [r for r in report["careless"] if r["end"] != "cleared"]
    expect(paid and all(r["wallet"]["cash"] > 0 for r in kept),
           f"arena: every kill is paid as it falls (L1b-15): each of {len(every)} runs was paid exactly what its kills "
           f"pay, and each failed run kept its kills: " + ", ".join(f"{r['end']} {r['wallet']['cash']:,}" for r in kept))


def boss_text(row):
    span = row["killSpan"] if row is not None else None
    if row is None:
        return "no such boss"
    if span is None:
        return f"not killed inside {row['watched']:.0f} s ({100 * row['left']:.0f}% of its health left)"
    return f"{row['kill']:.1f} s ({span[0]:.1f}-{span[1]:.1f})"


def run_text(seed, r):
    """One whole run in a few words: how it ended, where, and what it cost and kept."""
    where = "" if r["end"] == "cleared" else f" in {r['downInName'] or r['stage']}"
    return (f"seed {seed} {r['end']}{where} at {r['at'] / 60:.2f} min ({r['downs']} down(s), {r['hits']} hits, "
            f"{r['damage']:.0f} damage; kept {r['wallet']['cash']:,} cash)")


def camp_times(r):
    """When each camp of a run was done: open camps cleared, the boss room closed and cleared."""
    parts = []
    for zone in r["zones"]:
        at = r["clearedAt"].get(zone["id"])
        if zone["locks"]:
            camp = next((c for c in r["camps"] if c["zone"] == zone["id"]), None)
            closed = camp["closedAt"] if camp is not None else None
            parts.append(f"{zone['id']} closed {fmt(closed, 0, 1).strip()} s, cleared {fmt(at, 0, 1).strip()} s")
        else:
            parts.append(f"{zone['id']} cleared {fmt(at, 0, 1).strip()} s")
    return "; ".join(parts)


def print_forest(cfg, report):
    if report is None:
        print()
        print("FOREST ROAD: no level file, nothing to measure")
        return
    level, ctx = report["level"], report["ctx"]
    names = ctx["expeditions"]["difficultyNames"]
    camps_rules = ctx["combat"]["camps"]
    print()
    print(f"FOREST ROAD (L1b; {level['name']}, layout {level['layout']}; regenShare {level['crowd']['regenShare']:g}, "
          f"burst {level['crowd']['burst']}; a run's clock starts at the start point and stops at the boss room's "
          f"clear; camps: sight guard {camps_rules['guard']['sight']:g}/{camps_rules['guard']['cone']:g} deg, patrol "
          f"{camps_rules['patrol']['sight']:g}, fire {camps_rules['fire']['sight']:g} (rise "
          f"{camps_rules['fire']['rise']:g} s), chaseMargin {camps_rules['chaseMargin']:g}, leash "
          f"{camps_rules['leashSeconds']:g} s)")
    for difficulty, row in report["difficulties"].items():
        s, view, plan = row["scales"], row["view"], row["plan"]
        mine = view["_scales"]
        print(f"  {names.get(difficulty, difficulty).upper()}: hpScale {s['hpScale']:g}, damageScale {s['damageScale']:g}, "
              f"plateScale {s['plateScale']:g}, rewardMult {s['rewardMult']:g}; at gear "
              f"{row['gear']['melee']}/{row['gear']['ranged']} (health {row['hp']:.0f}, regen "
              f"{view['player']['regenPerSecond']:.1f}/s, his HP loss melee x{mine['melee']:g}, ranged x{mine['ranged']:g})")
        print("    residents: " + ", ".join(f"{z['id']} {z['residents']}" for z in plan["zones"])
              + f" ({sum(z['residents'] for z in plan['zones'])}); population {plan['population']} "
              f"(crowd.maxAlive {cfg['crowd']['maxAlive']})")
        worst = max(row["hits"], key=lambda h: h["share"])
        print("    enemy hits: " + ", ".join(f"{h['kind']} {h['shape']} {h['damage']} ({100 * h['share']:.0f}%)"
                                              for h in row["hits"]))
        print(f"    the worst hit: the {worst['kind']}'s {worst['shape']}, {worst['damage']} = {worst['share']:.1%}")
        boss = row["boss"]
        if boss is not None:
            print(f"    {boss['weapon']} against the {FOREST_BOSS} alone in its camp, from the camp's entry: "
                  f"{boss_text(boss)}; hits of the boss {boss['solid']}, lunges {boss['lunges']}, summoned "
                  f"{boss['summoned']:.1f}")
        print("    the whole run, reacting player, default melee only:")
        for line_seed, r in zip(MISSION_SEEDS, row["runs"]):
            rose = r["bosses"].get(FOREST_BOSS)
            fight = f"{rose[1] - rose[0]:.1f} s" if rose and rose[1] is not None else "not reached"
            print(f"      seed {line_seed}: {r['end']} at {r['at'] / 60:.2f} min, {r['downs']} down(s), {r['hits']} hits "
                  f"({r['damage']:.0f}), peak alive {r['peakAlive']}, {sum(r['killed'].values())} kills, "
                  f"{r['walked']:.0f} studs walked, {r['wakes']} wakes, {r['leashes']} leashes, the {FOREST_BOSS} "
                  f"{fight}; paid {wallet_text(r)}")
            print(f"        {camp_times(r)}")
        if row["human"]:
            print(f"    the same player with a human's reaction ({HUMAN_REACTION_SECONDS:g} s, not "
                  f"{REACTION_SECONDS:g}): " + "; ".join(run_text(seed, r) for seed, r in zip(MISSION_SEEDS, row["human"])))
        if row["careless"]:
            print("    the same player who never dodges: "
                  + "; ".join(run_text(seed, r) for seed, r in zip(MISSION_SEEDS, row["careless"])))
        if row["stand"]:
            print("    stands still where a group first wakes: woke at "
                  + ", ".join(fmt(r["stoodAt"], 0, 1).strip() for r in row["stand"]) + " s; down "
                  + ", ".join(fmt(r["downAfterWake"], 0, 1).strip() for r in row["stand"]) + " s after it, in "
                  + ", ".join(str(r["downInName"]) for r in row["stand"]))
        for group_id, runs in row["strikes"].items():
            print(f"    first strike on {group_id} (alone, walked up to from the road): " + "; ".join(
                f"woke {fmt(r['strike']['woke'][0] if r['strike']['woke'] else None, 0, 2).strip()} s "
                f"({r['strike']['woke'][1] if r['strike']['woke'] else '-'}), his first hit "
                f"{fmt(r['strike']['hit'], 0, 2).strip()} s, their first windup {fmt(r['strike']['windup'], 0, 2).strip()} s"
                for r in runs))
        for seed, r in zip(MISSION_SEEDS, row["kite"]):
            k = r["kite"] or {}
            print(f"    kites (seed {seed}): out at {fmt(k.get('at'), 0, 1).strip()} s with {len(k.get('alive', []))} "
                  f"alive ({k.get('hurt', 0)} hurt), {len(k.get('dead', []))} dead; at rest again "
                  f"{fmt(k.get('rested'), 0, 1).strip()} s, back in {fmt(k.get('back'), 0, 1).strip()} s: all whole "
                  f"{k.get('full')}, the dead still dead {k.get('same')}, {k.get('leashes', 0)} leash(es); then "
                  f"{r['end']} at {r['at'] / 60:.2f} min, paid {wallet_text(r)}")
        for seed, r in zip(MISSION_SEEDS, row["edge"]):
            e = r["edge"]
            print(f"    the edge (seed {seed}): {e['group']} from ({e['at'][0]:g}, {e['at'][1]:g}), {EDGE_SECONDS:.0f} s: "
                  f"{e['blocked']} hits blocked, {e['wakes']} wakes, {e['kills']} kills, paid {wallet_text(r)}")
        below = row["below"]
        if below is not None:
            slowest = max((r["at"] for r in row["human"] if r["end"] == "cleared"), default=None)
            print(f"    one preset below, gear {gear_text(below['gear'])} (health {below['hp']:.0f}): the "
                  f"{FOREST_BOSS} alone: {boss_text(below['boss'])}")
            if below["human"]:
                print("      the human's reaction: " + "; ".join(
                    run_text(seed, r) + (f" = x{r['at'] / slowest:.2f} of his slowest clear at gear "
                                         f"{gear_text(row['gear'])}" if r["end"] == "cleared" and slowest else "")
                    for seed, r in zip(MISSION_SEEDS, below["human"])))
            print("      the reacting player: " + "; ".join(run_text(seed, r) for seed, r in zip(MISSION_SEEDS, below["runs"])))
        under = row["under"]
        if under is not None:
            worst = max(under["hits"], key=lambda h: h["share"])
            print(f"    against gear {under['gear']['melee']}/{under['gear']['ranged']} (health {under['hp']:.0f}): the "
                  f"worst hit is {worst['damage']} = {worst['share']:.0%} of the bar; the {FOREST_BOSS} alone: "
                  f"{boss_text(under['boss'])}; the player who never dodges: "
                  + "; ".join(f"{r['end']} in {r['downInName'] or r['stage']} at {r['at'] / 60:.2f} min"
                              for r in under["careless"]))
        shots = row["ranged"]
        if shots is not None:
            name = cfg["weapons"][report["bow"]]["name"]
            print(f"    ranged, for information ({name} only, the reacting player): camp {shots['zone']} "
                  + "; ".join((f"cleared at {r['at']:.0f} s" if r["end"] == "stopped" else f"{r['end']} at {r['at']:.0f} s")
                              + f" ({r['hits']} hits)" for r in shots["camp"])
                  + f"; the {FOREST_BOSS} alone: {boss_text(shots['boss'])}")
        if row["runs"]:
            rates = [pay_rate(r) for r in row["runs"] if r["end"] == "cleared"]
            if rates:
                print("    what a clear pays a minute: " + "; ".join(
                    f"{c:,.0f} cash ({c / FOREST_CASH_PER_MINUTE_WAVE1 - 1:+.0%} of Wave 1's "
                    f"{FOREST_CASH_PER_MINUTE_WAVE1:,}), {m:.1f} {level['material']}" for c, m in rates))
            r = row["runs"][0]
            print("    the camps' clear bonuses (seed 11): " + ", ".join(
                f"{k} {c:,} cash, {m} {level['material']}" for k, (c, m) in r["bonuses"].items()))
            print("    each camp's first wake brought in (seed 11): " + "; ".join(
                f"{camp}: {', '.join(w)} -> {', '.join(j) or 'nobody'} (the chain from rest: {', '.join(e) or 'nobody'})"
                for camp, w, j, e in first_joins(r, plan, ctx["combat"]["camps"])))
            print("    tents (seed 11): " + "; ".join(
                f"{t['id']} sent {t['sent']} of {t['stock']} at " + ", ".join(f"{x:.1f}" for x in t["sentAt"]) + " s"
                for t in r["tents"]) + f"; dormant body-steps {r['dormantSteps']:,}")
        for seed, r in zip(MISSION_SEEDS, row["sneak"]):
            woke = sorted({r["groups"][i - 1] for i in r["woke"]})
            print(f"    the sneak (seed {seed}): {r['end']} at {r['at']:.0f} s, {r['walked']:.0f} studs walked, woke "
                  + (", ".join(woke) or "nobody"))
        for seed, r in zip(MISSION_SEEDS, row["road"]):
            woke = ", ".join(f"{r['groups'][i - 1]} ({w[1]})" for i, w in sorted(r["woke"].items()))
            print(f"    the careless road (seed {seed}): {r['end']} at {r['at']:.0f} s, {r['downs']} down(s), woke "
                  + (woke or "nobody"))
        for tid, runs in row["tentAlone"].items():
            for r in runs:
                t = next(x for x in r["tents"] if x["id"] == tid)
                print(f"    {tid} with no resident alive, its camp at rest: sent {t['sent']} of {t['stock']} at "
                      + ", ".join(f"{x:.1f}" for x in t["sentAt"]) + f" s; {t['left']} left after {r['at']:.0f} s")
        for kind, aim, rule, b in row["bow"]:
            print(f"    the bow at {gear_text(row['gear'])}: {b['weapon']} alone against a {kind}, {aim} aim, {rule} rule: "
                  + boss_text(b) + f"; hits taken {b['solid']}")
    walk = report["difficulties"][ctx["expeditions"]["difficulties"][0]]["runs"][0]
    print(f"  the road: {walk['walked']:.0f} studs walked outside the fights = "
          f"{walk['walked'] / cfg['movement']['walkSpeed']:.1f} s at walk speed")


def pay_rate(r):
    """What a run paid a minute: (cash, materials)."""
    minutes = r["at"] / 60 if r["at"] else math.inf
    return r["wallet"]["cash"] / minutes, r["wallet"]["materials"] / minutes


def paid_exactly(r):
    """L1b-15, solo: the wallet is each kill's reward x the share (1), summed: exactly."""
    return r["wallet"] == {key: luau_round(value) for key, value in r["priced"].items()} and all(
        float(value).is_integer() for value in r["priced"].values())


def check_forest(cfg, report, expect):
    if report is None:
        return
    level, ctx = report["level"], report["ctx"]
    names = ctx["expeditions"]["difficultyNames"]
    regen = level["crowd"]["regenShare"]
    expect(abs(regen / MISSION_REGEN_SHARE - 1) <= MISSION_REGEN_TOLERANCE,
           f"forest: regenShare {regen:g} within {MISSION_REGEN_TOLERANCE:.0%} of the range's 10/130")
    first = ctx["expeditions"]["difficulties"][0]
    for difficulty, row in report["difficulties"].items():
        tag = f"forest, {names.get(difficulty, difficulty)}"
        gear = gear_text(row["gear"])
        plan = row["plan"]
        expect(plan["population"] <= cfg["crowd"]["maxAlive"],
               f"{tag}: the population {plan['population']} is at most crowd.maxAlive {cfg['crowd']['maxAlive']} (L1b-11; "
               + ", ".join(f"{z['id']} {z['residents']}" for z in plan["zones"]) + " residents)")
        share = FOREST_HIT_SHARE[difficulty]
        worst = max(row["hits"], key=lambda h: h["share"])
        expect(worst["share"] <= share + THREAT_EPS,
               f"{tag} at gear {gear}: no enemy hit over {share:.0%} of the bar ({row['hp']:.0f}): the worst is the "
               f"{worst['kind']}'s {worst['shape']}, {worst['damage']} = {worst['share']:.1%}")
        lo, hi = FOREST_BOSS_SECONDS[difficulty]
        boss = row["boss"]
        span = boss["killSpan"] if boss is not None else None
        expect(span is not None and lo <= span[0] and span[1] <= hi,
               f"{tag} at gear {gear}: the {FOREST_BOSS} alone in its camp, every seed, {lo:.0f}-{hi:.0f} s: "
               + boss_text(boss))
        expect(boss is not None and boss["solid"] == 0 and boss["lunges"] == 0,
               f"{tag}: the {FOREST_BOSS} alone: the reacting player takes no hit"
               + (f" ({boss['solid']} of the boss, {boss['lunges']} lunges)" if boss is not None else ""))
        for seed, r in zip(MISSION_SEEDS, row["runs"]):
            rose = r["bosses"].get(FOREST_BOSS)
            fight = rose[1] - rose[0] if rose and rose[1] is not None else None
            expect(fight is not None and lo <= fight <= hi,
                   f"{tag}: seed {seed}, the {FOREST_BOSS} in the run takes {lo:.0f}-{hi:.0f} s: "
                   + (f"{fight:.1f} s" if fight is not None else "not killed"))
            if difficulty == first:
                lo_c, hi_c = FOREST_CLEAR_SECONDS
                expect(r["end"] == "cleared" and lo_c <= r["at"] <= hi_c,
                       f"{tag} at gear {gear}: seed {seed}, the reacting player's first clear takes "
                       f"{lo_c / 60:g}-{hi_c / 60:g} min, walking included: {r['end']} at {r['at'] / 60:.2f} min, "
                       f"{r['downs']} down(s)")
                lo_m, hi_m = FOREST_TIMBER_PER_MINUTE
                cash_rate, rate = pay_rate(r)
                expect(r["end"] == "cleared" and lo_m <= rate <= hi_m,
                       f"{tag} at gear {gear}: seed {seed}, the clear pays {lo_m:g}-{hi_m:g} {level['material']} a minute "
                       f"(Wave 1's 42 +-10%): {rate:.1f}; cash {cash_rate:,.0f} a minute (reported against Wave 1's "
                       f"{FOREST_CASH_PER_MINUTE_WAVE1:,})")
            else:
                print(f"  note  {tag} at gear {gear}: seed {seed}, the reacting player's clear (reported): {r['end']} at "
                      f"{r['at'] / 60:.2f} min, {r['downs']} down(s), paid {wallet_text(r)}")
        # Every kill is paid once, at once (L1b-15): every run of the row, the lost ones above all.
        under, below = row["under"], row["below"]
        every = (row["runs"] + row["human"] + row["careless"] + row["stand"] + row["kite"] + row["edge"]
                 + [r for runs in row["strikes"].values() for r in runs]
                 + (under["careless"] if under is not None else [])
                 + (below["human"] + below["runs"] if below is not None else []))
        wrong = [f"{r['end']} in {r['downInName'] or r['stage']}: paid {wallet_text(r)}, its kills price "
                 f"{r['priced']}" for r in every if not paid_exactly(r)]
        lost = [r for r in every if r["end"] not in ("cleared", "stopped")]
        expect(not wrong and all(r["wallet"]["cash"] > 0 for r in lost if sum(r["killed"].values()) > 0),
               f"{tag}: every kill is paid once, at once: each of {len(every)} runs ({len(lost)} lost) was paid exactly "
               f"each kill's reward x its share, and a lost run kept every kill"
               + (": " + "; ".join(wrong[:3]) if wrong else ""))
        valor = luau_round(next(w["boss"]["valor"] for st in level["stages"] for w in st.get("waves") or [] if w.get("boss"))
                           * row["scales"]["rewardMult"])
        cleared = [r for r in row["runs"] + row["human"] if r["end"] == "cleared"]
        expect(bool(cleared) and all(r["wallet"]["valor"] == valor for r in cleared),
               f"{tag}: a clear pays exactly {valor} Valor (the boss's x rewardMult): "
               + ", ".join(str(r["wallet"]["valor"]) for r in cleared))
        moved = sum(r["graceMoves"] for r in every)
        if moved:
            print(f"  note  {tag}: the close, judged again in its grace, moved the simulator's player {moved} time(s)")
        if row["stand"]:
            lo_s, hi_s = FOREST_STILL_DOWN
            downs = [r["downAfterWake"] for r in row["stand"]]
            expect(all(d is not None and lo_s <= d <= hi_s for d in downs) and all(r["downIn"] == row["stand"][0]["downIn"]
                                                                                for r in row["stand"]),
                   f"{tag}: standing still in the group that wakes first, down {lo_s:.0f}-{hi_s:.0f} s after its wake, "
                   f"every seed: " + ", ".join(f"{fmt(d, 0, 1).strip()} s" for d in downs)
                   + f" (in {row['stand'][0]['downInName']})")
        if row["strikes"]:
            told = []
            good = True
            for group_id, runs in row["strikes"].items():
                for r in runs:
                    s = r["strike"]
                    ok = (s["woke"] is not None and s["woke"][1] == "sight" and s["hit"] is not None
                          and (s["windup"] is None or s["hit"] < s["windup"]))
                    good = good and ok
                    if not ok:
                        told.append(f"{group_id}: woke {s['woke']}, hit {s['hit']}, windup {s['windup']}")
            expect(good and len(row["strikes"]) > 0,
                   f"{tag}: a first strike: walking up to each of {len(row['strikes'])} fire groups from outside its "
                   f"sight, the reacting player lands a hit on a sitter before any sitter winds up, every seed"
                   + (": " + "; ".join(told[:3]) if told else ""))
        if row["kite"]:
            told = []
            good = True
            for seed, r in zip(MISSION_SEEDS, row["kite"]):
                k = r["kite"] or {}
                ok = (k.get("back") is not None and k.get("full") is True and k.get("same") is True
                      and k.get("leashes", 0) > 0 and paid_exactly(r))
                paused = k.get("tentRested") is not None and k.get("tentRested") == k.get("tentBack")
                ok = ok and paused
                good = good and ok
                told.append(f"seed {seed}: " + (f"whole, the dead still dead, the tent paused at {k.get('tentBack')} left"
                                                if ok else str({key: k.get(key) for key in ('back', 'full', 'same',
                                                                                            'leashes', 'tentRested',
                                                                                            'tentBack')})))
            expect(good, f"{tag}: the leash (kite): out of play, the group goes home and heals; back in, every survivor "
                   f"is at full health, no body killed before is back, he was paid only what his kills pay, and the "
                   f"tent's stock left is what it was when the camp went home: " + "; ".join(told))
        if row["edge"]:
            ok = all(r["edge"]["kills"] == 0 and r["wallet"] == {"cash": 0, "materials": 0, "valor": 0}
                     and r["edge"]["blocked"] > 0 for r in row["edge"])
            expect(ok, f"{tag}: the edge: standing just past chaseMargin of {row['edge'][0]['edge']['group']} (no "
                   f"shooter) and hitting it earns 0 from it, every seed: "
                   + ", ".join(f"{r['edge']['blocked']} hits blocked, {r['edge']['kills']} kills, "
                               f"{r['wallet']['cash']} cash" for r in row["edge"]))
        # L1's gates back (L1b-W2-22): skill beats gear. At the recommended gear the human clears
        # without going down and the player who never dodges does not clear, every difficulty.
        human = row["human"]
        if human:
            expect(all(r["end"] == "cleared" and r["downs"] == 0 for r in human),
                   f"{tag} at gear {gear}: the player with a human's reaction ({HUMAN_REACTION_SECONDS:g} s) clears "
                   f"without going down, every seed: " + "; ".join(run_text(seed, r) for seed, r in zip(MISSION_SEEDS, human)))
        if row["careless"]:
            expect(all(r["end"] != "cleared" for r in row["careless"]),
                   f"{tag} at gear {gear}: the player who never dodges does not clear, every seed: "
                   + "; ".join(run_text(seed, r) for seed, r in zip(MISSION_SEEDS, row["careless"])))
        if below is not None:
            # Clearly beyond the gear below: he goes down (or meets the cap), or takes this many
            # times as long as his slowest clear at the recommended gear; the Colossus alone is
            # not killed inside FOREST_BELOW_BOSS seconds.
            slowest = max((r["at"] for r in human if r["end"] == "cleared"), default=None)
            times = HUMAN_BELOW_SLOWER[difficulty]
            told = []
            good = slowest is not None and bool(below["human"])
            for seed, r in zip(MISSION_SEEDS, below["human"]):
                ok = r["end"] in HUMAN_BELOW_ENDS or (r["end"] == "cleared" and slowest and r["at"] >= times * slowest)
                good = good and bool(ok)
                told.append(run_text(seed, r) + (f" = x{r['at'] / slowest:.2f}" if r["end"] == "cleared" and slowest else ""))
            expect(good, f"{tag}: one preset below, at gear {gear_text(below['gear'])}, the human goes down or takes at "
                   f"least x{times:g} his slowest clear at {gear}, every seed: " + "; ".join(told))
            span = below["boss"]["killSpan"] if below["boss"] is not None else None
            limit = FOREST_BELOW_BOSS[difficulty]
            expect(below["boss"] is not None and (span is None or span[0] > limit),
                   f"{tag}: one preset below, at gear {gear_text(below['gear'])}, the {FOREST_BOSS} alone is not killed "
                   f"inside {limit:.0f} s: " + boss_text(below["boss"]))
            # Under-gearing never pays better: the clear one preset below pays less cash a minute.
            mine = [pay_rate(r)[0] for r in row["runs"] if r["end"] == "cleared"]
            theirs = [pay_rate(r)[0] for r in below["runs"]]
            expect(bool(mine) and bool(theirs) and max(theirs) < min(mine),
                   f"{tag}: one preset below, the reacting player is paid less cash a minute than at {gear}: "
                   + ", ".join(f"{x:,.0f}" for x in theirs) + " against " + ", ".join(f"{x:,.0f}" for x in mine))
        if row["sneak"]:
            told = []
            good = True
            for seed, r in zip(MISSION_SEEDS, row["sneak"]):
                woke = sorted({r["groups"][i - 1] for i in r["woke"]
                               if not plan["zones"][plan_floor(plan, r["groups"][i - 1]) - 1]["locks"]})
                ok = r["end"] == "stopped" and not woke
                good = good and ok
                told.append(f"seed {seed} {r['walked']:.0f} studs, woke {', '.join(woke) or 'nobody'}")
            expect(good, f"{tag}: the sneak: keeping to layout.sneak to the boss room's entry wakes no group of an open "
                   f"camp, every seed: " + "; ".join(told))
        if row["runs"] and difficulty == first:
            told = []
            good = True
            for seed, r in zip(MISSION_SEEDS, row["runs"]):
                for camp, wakers, joined, wanted in first_joins(r, plan, ctx["combat"]["camps"]):
                    ok = joined == wanted
                    good = good and ok
                    if not ok or seed == MISSION_SEEDS[0]:
                        told.append(f"seed {seed} {camp}: {', '.join(wakers)} -> {', '.join(joined) or 'nobody'}"
                                    + ("" if ok else f" (the chain from rest: {', '.join(wanted) or 'nobody'})"))
            expect(good, f"{tag}: the join-in: each open camp's first wake brings in the groups the chain from rest "
                   f"names (check_levels.py's table), every seed: " + "; ".join(told))
            # The tents: `every` apart from the wake while the camp is busy, the whole stock, never more.
            told = []
            good = True
            for seed, r in zip(MISSION_SEEDS, row["runs"]):
                for t in r["tents"]:
                    gaps = [b - a for a, b in zip(t["sentAt"], t["sentAt"][1:])]
                    every = next(x["every"] for x in plan["tents"] if x["def"]["id"] == t["id"])
                    ok = t["sent"] == t["stock"] and t["left"] == 0 and all(g >= every - THREAT_EPS for g in gaps)
                    good = good and ok
                    if seed == MISSION_SEEDS[0] or not ok:
                        told.append(f"seed {seed} {t['id']} {t['sent']} of {t['stock']} out in "
                                    f"{(t['sentAt'][-1] - t['sentAt'][0]) if t['sentAt'] else 0:.1f} s"
                                    + (f" (the shortest gap {min(gaps):.2f} s)" if gaps else ""))
            for tid, runs in row["tentAlone"].items():
                for r in runs:
                    t = next(x for x in r["tents"] if x["id"] == tid)
                    ok = t["sent"] == t["stock"] and t["left"] == 0
                    good = good and ok
                    told.append(f"{tid} with no resident alive and its camp at rest sends its {t['sent']} of {t['stock']}")
            expect(good, f"{tag}: a tent sends its whole stock `every` seconds apart, never more, and empties once no "
                   f"resident of its camp lives even with the camp at rest: " + "; ".join(told))


def plan_floor(plan, group_id):
    """The floor (zone index) of a group of the plan, residents' or a tent's, by its id."""
    for defn in plan["groups"] + [tent["def"] for tent in plan["tents"]]:
        if defn["id"] == group_id:
            return defn["floor"]
    return 0


def interpreter_note():
    """Which Python this is, and whether it is the gate's. The gate is `py tools/sim_range.py
    --check`, and the launcher follows this file's first line to the 64-bit Python 3.12. The
    other Python on the owner's machine (3.14, a 32-bit build) is what `py -` and a script with
    no such line get, and what imports this file from one. A level run is chaotic: a sum whose
    last digit rounds differently on the 32-bit build can move a kill by a frame, and the same
    seed then differs by up to 0.08 min in a seven-minute run. Bands are set to pass on both;
    the numbers in docs/BALANCE.md are the gate's."""
    bits = 64 if sys.maxsize > 2 ** 32 else 32
    version = f"Python {sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}, {bits}-bit"
    gate = bits == 64 and sys.version_info[:2] == GATE_PYTHON
    return (f"interpreter: {version}" + (" (the gate's)" if gate else
                                         f" (NOT the gate's, which is the 64-bit Python "
                                         f"{GATE_PYTHON[0]}.{GATE_PYTHON[1]} that `py tools/sim_range.py` selects: a level "
                                         f"run's times can differ here by up to 0.08 min)"))


def check(cfg, fam_rows, ab_rows, threat=None, bosses=None, mission=None, forest=None):
    failures = []

    def expect(ok, text):
        print(f"  {'PASS' if ok else 'FAIL'}  {text}")
        if not ok:
            failures.append(text)

    print()
    print("CHECK (bands in tools/sim_range.py; targets from docs/WEAPONS.md and docs/BALANCE.md P3)")
    print(f"  {interpreter_note()}")
    lo_t, hi_t = 1 - FAMILY_TOLERANCE, 1 + FAMILY_TOLERANCE
    for family, targets in FAMILY_TARGETS.items():
        rows = [r for r in fam_rows if r["family"] == family]
        expect(len(rows) > 0, f"{family}: family exists")
        for r in rows:
            for metric, target in targets.items():
                value = r[metric]
                expect(lo_t * target <= value <= hi_t * target,
                       f"{family} {r['key']} {metric} DPS {value:.0f} in [{lo_t * target:.0f}, {hi_t * target:.0f}]")
        if len(rows) >= 2:
            metric = "crowd3" if "crowd3" in targets else "crowd6"
            crowds = [r[metric] for r in rows]
            spread = (max(crowds) - min(crowds)) / (sum(crowds) / len(crowds))
            expect(spread <= AB_SPREAD, f"{family}: A/B crowd DPS within {AB_SPREAD:.0%} ({spread:.0%})")
    lo_b, hi_b = BURST_SECONDS
    lo_e, hi_e = EFFECTIVE_COOLDOWN_SHARE
    lo_f, hi_f = FLOOR_SHARE
    scale = cfg["abilities"]["cooldownScale"]
    expect(scale == 1, f"abilities.cooldownScale ships at 1 (it is {scale}; 0 is the range's cooldowns-off switch)")
    if scale <= 0:
        print()
        print("CHECK: FAIL (cooldowns are off)")
        return False
    for r in ab_rows:
        name = r["id"]
        if name in SINGLE_TARGET_ABILITIES:
            expect(lo_b <= r["bossBurst"] <= hi_b,
                   f"{name}: boss burst {r['bossBurst']:.1f} s of single DPS in [{lo_b}, {hi_b}]")
            expect(r["burst"] <= SINGLE_TARGET_CROWD_CEILING,
                   f"{name}: crowd burst {r['burst']:.1f} s <= {SINGLE_TARGET_CROWD_CEILING}")
        else:
            expect(lo_b <= r["burst"] <= hi_b, f"{name}: burst {r['burst']:.1f} s of crowd DPS in [{lo_b}, {hi_b}]")
        if r["busy"] > 0:
            net = r["burst"] - r["busy"]
            expect(net >= NET_AFTER_BUSY_SECONDS,
                   f"{name}: beats its {r['busy']:.2f} s busy lock by {net:.1f} s (>= {NET_AFTER_BUSY_SECONDS})")
        share = r["eff6"] / r["base"]
        expect(lo_e <= share <= hi_e, f"{name}: busy-crowd cooldown {r['eff6']:.1f} s = {share:.0%} of "
                                      f"{r['base']:.0f} s in [{lo_e:.0%}, {hi_e:.0%}]")
        floor_share = r["floor"] / r["base"]
        expect(lo_f <= floor_share <= hi_f and r["floor"] >= FLOOR_MIN_SECONDS,
               f"{name}: floor {r['floor']:.1f} s = {floor_share:.0%} of base in [{lo_f:.0%}, {hi_f:.0%}], "
               f">= {FLOOR_MIN_SECONDS:.0f} s")
    if threat is not None:
        check_threat(cfg, *threat, expect)
        if bosses:
            check_boss(cfg, threat[0], bosses, expect)
    if mission is not None:
        check_mission(cfg, mission, expect)
    if forest is not None:
        check_forest(cfg, forest, expect)
    print()
    print(f"CHECK: {'PASS' if not failures else 'FAIL (' + str(len(failures)) + ')'}")
    return not failures


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="exit 1 if a shipped value leaves the design bands")
    parser.add_argument("--config", default=str(CONFIG_PATH), help="ProvingGrounds.json to measure")
    parser.add_argument("--trials", type=int, default=120, help="random trials per measurement")
    parser.add_argument("--mission", default=None,
                        help="a Missions/*.json to play as the Raider Arena (default: Village)")
    parser.add_argument("--levels-only", "--mission-only", dest="levels_only", action="store_true",
                        help="only the level sections (the Raider Arena and Forest Road)")
    parser.add_argument("--level", choices=("arena", "forest"), default=None,
                        help="with --levels-only: only that level")
    args = parser.parse_args()
    cfg = load_config(args.config)
    if args.levels_only:
        report = mission_report(cfg, args.mission) if args.level in (None, "arena") else None
        forest = forest_report(cfg) if args.level in (None, "forest") else None
        if args.level in (None, "arena"):
            print_mission(cfg, report)
        if args.level in (None, "forest"):
            print_forest(cfg, forest)
        if args.check:
            failures = []

            def expect(ok, text):
                print(f"  {'PASS' if ok else 'FAIL'}  {text}")
                if not ok:
                    failures.append(text)

            print()
            print(f"  {interpreter_note()}")
            check_mission(cfg, report, expect)
            check_forest(cfg, forest, expect)
            print(f"\nCHECK (levels only): {'PASS' if not failures else 'FAIL (' + str(len(failures)) + ')'}")
            sys.exit(0 if not failures else 1)
        return
    fam_rows = family_rows(cfg, args.trials)
    print_families(fam_rows)
    ab_rows = ability_rows(cfg, fam_rows, args.trials)
    print_abilities(ab_rows)
    env = threat_env(cfg)
    threat = (env, threat_facts(cfg, env), threat_rows(cfg, env), role_rows(cfg, env), plate_rows(cfg))
    print_threat(cfg, *threat, ab_rows)
    bosses = boss_rows(cfg, env)
    print_boss(cfg, env, bosses)
    report = mission_report(cfg, args.mission)
    print_mission(cfg, report)
    forest = forest_report(cfg)
    print_forest(cfg, forest)
    if args.check:
        sys.exit(0 if check(cfg, fam_rows, ab_rows, threat, bosses, report, forest) else 1)


if __name__ == "__main__":
    main()
