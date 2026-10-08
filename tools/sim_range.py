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

Usage:
  py tools/sim_range.py                 # all tables
  py tools/sim_range.py --check         # exit 1 if a shipped value leaves the design bands
  py tools/sim_range.py --config PATH   # measure another ProvingGrounds.json
  py tools/sim_range.py --trials 60     # fewer random trials (faster, noisier)
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
FACING_STEP = 2 * math.pi / 256  # a locked facing is snapped to the snapshot's yaw byte


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

    __slots__ = ("id", "r", "hr", "body_y", "body", "head", "hp", "max_hp", "armor", "alive", "back_at")

    def __init__(self, ident, kind, x, z):
        self.id = ident
        self.r = kind["radius"]
        self.hr = kind["headRadius"]
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

    def live(self):
        return [e for e in self.enemies if e.alive]

    def damage(self, enemy, amount):
        """CrowdService.Damage: flat armour with a floor; returns (dealt, killed)."""
        if not enemy.alive or amount <= 0:
            return 0.0, False
        dealt = max(amount - enemy.armor, amount * self.floor_share)
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
            entry = ray_entry(origin, unit, size, width / 2 + pad + e.r, e.body)
            if entry is None:
                return None
            crit = want_crit and ray_entry(origin, unit, size, width / 2 + e.hr, e.head) is not None
            return (entry, crit)
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
    found = []
    unit = v_unit(direction)
    if unit is None or reach <= 0:
        return found
    for e in world.enemies:
        if not e.alive:
            continue
        entry = ray_entry(origin, unit, reach, width / 2 + pad + e.r, e.body)
        if entry is not None:
            found.append((entry, e.id, e))
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
        for entry, eid, enemy in path_candidates(world, start, d, budget, width, pad):
            frame = 0 if entry <= first else 1 + math.floor((entry - first) / step_len)
            claims.append((frame, index, entry, eid, enemy))
    claims.sort(key=lambda c: (c[0], c[1], c[2], c[3]))
    hits_left = [pierce] * len(arrows)
    stop = [None] * len(arrows)
    for _frame, index, entry, _eid, enemy in claims:
        if stop[index] is not None or enemy.id in volley_hit:
            continue
        if capped():
            stop[index] = 0.0
            continue
        hit(world, tally, enemy, damage)
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


def ranged_attack(world, cfg, v, aim_z, pierce_override=None, full=True, seed=1, aim_y=None):
    """resolveRanged: camera ray level at chest height (aim_y), aimed along +x, offset aim_z."""
    origin = (0.0, chest_height(cfg) if aim_y is None else aim_y, aim_z)
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
#               as any hit; when the plate empties the body reels for crowd.plateBreakSeconds.
#
# Where the contract leaves a choice, the sim follows the code as written (CrowdBrain,
# ThreatField, VitalsService, MovementController.ApplyKnock) and says so at the line: the lunge
# is a capsule whose tip is `range` from the body centre and the player is a point; a place
# is held from the windup's start to the attack's end; an impact keeps its exact time and is
# handled on the first step at or after it; a locked facing is snapped to 1/256 of a turn; a
# shot is aimed in two passes from the target's motion over the last step; a shot and a charge
# are swept over each crowd step against the root as it is at that step; a voided shot flies
# on. One thing is the sim's own: a freed place goes to the lowest id of its kind waiting in
# reach (the server takes its records in list order).


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


class Fighter(Enemy):
    """A crowd enemy whose group fights: the Enemy that strike() hits, plus the brain's state.
    (x, z) are its feet on the floor. States: approach, windup, attack, recover."""

    def __init__(self, ident, name, kind, x, z, respawn):
        super().__init__(ident, kind, x, z)
        self.name = name
        self.attack = kind["attacks"][0]
        self.shape = self.attack["shape"]
        self.brain = kind["brain"]
        # [windup] Ruling 21: `reach` is measured on the flat.
        self.reach = self.attack["reach"]
        # [keepAway] CrowdBrain.Think: the band never holds it so far out that nothing reaches.
        self.band_max = max(min(kind.get("bandMax") or self.reach, self.reach), 0)
        self.band_min = min(max(kind.get("bandMin") or 0, 0), self.band_max)
        self.speed = max(kind["speed"], 0)
        self.mult = max(kind["knockbackMult"], 0)
        self.head_y = kind["height"] - kind["headRadius"]
        self.max_plate = max(kind.get("plate") or 0, 0)
        # [cap] Its kind's places against one player; no key = no cap.
        self.places = math.floor(kind["perPlayer"]) if kind.get("perPlayer") is not None else math.inf
        self.home = (x, z)
        self.respawn = respawn
        self.respawn_at = math.inf
        self.spawn(0.0)

    def spawn(self, now):
        self.x, self.z = self.home
        self.alive = True
        self.hp = self.max_hp
        self.plate = self.max_plate  # [plate] a respawned elite is plated again
        self.state = "approach"
        self.started = self.until = 0.0
        self.face = (0.0, 1.0)
        self.locked = False
        self.charge = None
        self.kx = self.kz = 0.0
        self.stagger_until = self.air_until = 0.0
        self.spawned_at = now
        self.respawn_at = math.inf
        self.place()

    def place(self):
        self.body = (self.x, self.body_y, self.z)
        self.head = (self.x, self.head_y, self.z)


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
        self.cancelled = self.blocked = self.broken = 0

    def damage(self, enemy, amount):
        if not enemy.alive or amount <= 0:
            return 0.0, False
        now = self.now
        if enemy.plate > 0:  # [plate]
            if amount < self.heavy:
                self.blocked += 1
                return 0.0, False
            dealt = min(amount, enemy.plate)
            enemy.plate -= dealt
            self.react(enemy, amount, now)
            if enemy.plate <= 0:
                # The break: it reels for max(its stagger, plateBreakSeconds), whatever its
                # knockbackMult, and the windup it was in is cancelled.
                self.broken += 1
                enemy.stagger_until = max(enemy.stagger_until, now + self.reel)
                if enemy.state == "windup" and now < enemy.until - THREAT_EPS:
                    enemy.state = "recover"
                    enemy.until = now + enemy.attack["recover"]
                    self.cancelled += 1
            return dealt, False
        dealt, killed = super().damage(enemy, amount)
        if killed:
            enemy.respawn_at = now + enemy.respawn
            if enemy.state == "windup" and now >= enemy.until - THREAT_EPS and self.owed is not None:
                self.owed(enemy)  # [interrupt] ruling 22: a due impact is never lost
            return dealt, killed
        self.react(enemy, amount, now)
        return dealt, killed

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
                enemy.until = now + enemy.attack["recover"]
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
#           then a jump, then a dash (ThreatRun.replan).
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
        rng = random.Random(seed)
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
        self.variant = variant_of(cfg, cfg["loadout"]["melee"])
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

    def shift(self, dx, dz):
        limit_x, limit_z = self.half[0] - FENCE_CLEARANCE, self.half[1] - FENCE_CLEARANCE
        self.x = clamp(self.x + dx, -limit_x, limit_x)
        self.z = clamp(self.z + dz, -limit_z, limit_z)

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
        live = [e for e in self.fighters if e.alive]
        if not live:
            return
        v = self.variant
        nearest = min(live, key=lambda e: (e.x - self.x) ** 2 + (e.z - self.z) ** 2)
        dx, dz = nearest.x - self.x, nearest.z - self.z
        gap = math.hypot(dx, dz)
        if t >= self.next_swing - THREAT_EPS and gap <= v["range"] + v["pad"] + nearest.r:
            if t - self.last_swing > self.cfg["controls"]["comboResetSeconds"]:
                self.combo = 0
            if gap > EPSILON:
                self.face = (dx / gap, dz / gap)
            self.world.now = t
            self.world.blow = (self.x, self.z, v.get("knockback") or 0, v.get("launch") or 0)
            melee_attack(self.world, self.cfg, v, self.combo, origin=(self.x, ROOT_HEIGHT, self.z),
                         direction=(self.face[0], 0.0, self.face[1]))
            self.world.blow = None
            self.combo += 1
            self.last_swing = t
            self.next_swing = t + attack_interval(v)

    def evade(self, t, dt):
        if self.dash is not None:
            return
        # A tell shows with the first snapshot after the windup starts, or one crowd step later
        # when that snapshot is lost (INTERFACES "Tells are drawn against server time"); the sim
        # allows the lost one, and the player acts a reaction time after that.
        seen = self.interval + REACTION_SECONDS
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
        seen = self.interval + REACTION_SECONDS
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
                    length = min(attack.get("range") or 0, self.runway(e.x, e.z, e.face, e.r))
                    found.append(("lane", ("w", e.id, e.started), e.until, attack, e.x, e.z, e.face, length))
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
        limit_x, limit_z = self.half[0] - FENCE_CLEARANCE, self.half[1] - FENCE_CLEARANCE
        x = clamp(self.x + plan["ux"] * run, -limit_x, limit_x)
        z = clamp(self.z + plan["uz"] * run, -limit_z, limit_z)
        if plan["jump"]:
            return x, z, max(self.jump_speed * elapsed - GRAVITY * elapsed * elapsed / 2, 0.0)
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
                if decided < t0:
                    continue
                x, z, feet = self.plan_state(plan, t0, decided)
                height = None if attack["shape"] == "line" else attack.get("height")
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
                last = impact + length / speed + lag + step
                while tau <= last:
                    back = clamp((tau - step - lag - impact) * speed, 0, length)
                    front = clamp((tau - lag - impact) * speed, 0, length)
                    x, z, feet = self.plan_state(plan, t0, tau)
                    if ((height is None or feet <= height) and not self.plan_shielded(plan, t0, tau - lag, tau)
                            and point_segment_gap((x, z), (sx + face[0] * back, sz + face[1] * back),
                                                  (sx + face[0] * front, sz + face[1] * front)) <= reach):
                        solid += 1
                        first = min(first, tau)
                        break
                    tau += PLAN_TICK
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
        yield 0.0, stand
        # Of two steps of one length, the one that ends nearer where he started: he holds his
        # ground instead of drifting to the fence.
        ways = sorted(PLAN_DIRECTIONS, key=lambda d: math.hypot(self.x + d[0] * 4 - self.anchor[0],
                                                                self.z + d[1] * 4 - self.anchor[1]))
        steps = [{"ux": ux, "uz": uz, "dur": dur, "jump": False, "dash": False}
                 for dur in PLAN_STEPS for ux, uz in ways]
        for plan in steps:
            yield plan["dur"], plan
        if self.jump is None and (self.lift is None or t >= self.lift[1]):
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
        if plan["dash"]:
            self.start_dash(t, (plan["ux"], plan["uz"]))
            return
        if plan["jump"]:
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
            self.knock = self.dash = self.lift = self.step = None
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
            self.rule(t, impact, kind, attack, held, voided or self.shielded(impact, decided, t), push)
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

    @staticmethod
    def charge_run(charge, clock):
        return clamp((clock - charge["T"]) * charge["speed"], 0, charge["length"])

    # -- the crowd ----------------------------------------------------------------------------

    def runway(self, x, z, face, radius):
        """CrowdBrain.runway: how far a body can run along `face` before the arena's edge."""
        room = math.inf
        limit_x, limit_z = max(self.half[0] - radius, 0), max(self.half[1] - radius, 0)
        if face[0] > 0:
            room = min(room, (limit_x - x) / face[0])
        elif face[0] < 0:
            room = min(room, (-limit_x - x) / face[0])
        if face[1] > 0:
            room = min(room, (limit_z - z) / face[1])
        elif face[1] < 0:
            room = min(room, (-limit_z - z) / face[1])
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

    def owe(self, e):
        """Ruling 22: the blow of a body killed after its impact's time still lands."""
        self.land(e, e.until, self.world.now)

    def land(self, e, impact, now):
        """CrowdBrain.land and VitalsService.onImpact: the windup's end. The attack is frozen at
        the body's place now, on the heading the windup locked."""
        attack = e.attack
        shape = e.shape
        standing = self.down_until is None and not self.was_down(impact)
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
            self.pending.append([lands + self.lag, lands, e.name, attack, e.x, e.z, e.face, False,
                                 (here[0], here[2]), impact])
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
            length = min(attack.get("range") or 0, self.runway(e.x, e.z, e.face, e.r)) if speed > 0 else 0.0
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
            if not e.alive:
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
                if shape == "lane" and (attack.get("speed") or 0) > 0:
                    e.until += (attack.get("range") or 0) / attack["speed"]
                else:
                    e.until += strike_seconds
            if e.state == "attack" and now >= e.until - THREAT_EPS:
                e.state = "recover"
                e.until += attack["recover"]
                e.charge = None
                held[e.name] -= 1  # [cap] the place is free from here: `recover` holds none
            if e.state == "recover" and now >= e.until - THREAT_EPS:
                e.state = "approach"
            grounded = now >= e.air_until
            vx = vz = 0.0
            state = e.state
            if state == "windup":
                if shape == "line" and standing:
                    self.follow(e, now)
            elif state == "attack":
                pass
            elif standing and grounded and now >= e.stagger_until and (state == "approach" or e.brain == "keepAway"):
                # A free body faces its target. A rusher stands exposed through its recover; a
                # shooter keeps its distance through it.
                if gap > EPSILON:
                    e.face = (dx / gap, dz / gap)
                ready = state == "approach" and now >= e.spawned_at + threat["spawnGrace"] - THREAT_EPS  # [spawn]
                admitted = False
                if ready and gap <= e.reach + REACH_EPSILON:  # [windup]
                    admitted = held.get(e.name, 0) < e.places  # [cap] its kind's turn
                    if admitted and shape == "shot":
                        admitted = shots_held < threat["maxShots"]  # [shot] a slinger at that cap waits
                        shots_held += 1 if admitted else 0
                    if admitted:
                        held[e.name] = held.get(e.name, 0) + 1
                if admitted:
                    e.state = "windup"
                    e.started = now
                    e.until = now + attack["windup"]
                    e.locked = False
                    if shape in ("lunge", "arc", "lane"):
                        e.face = snap_face(e.face)  # locked here, as the snapshot carries it
                elif e.brain == "rush":
                    if gap > e.reach:  # [rush] CrowdService.seek
                        travel = min(e.speed, (gap - e.reach) / dt)
                        vx, vz = dx / gap * travel, dz / gap * travel
                elif gap > e.band_max:  # [keepAway] in, as far as the band
                    travel = min(e.speed, (gap - e.band_max) / dt)
                    vx, vz = dx / gap * travel, dz / gap * travel
                elif gap < e.band_min:  # ...and straight back, no further than the arena's edge
                    limit_x, limit_z = max(self.half[0] - e.r, 0), max(self.half[1] - e.r, 0)
                    gx = clamp(e.x - e.face[0] * (e.band_min - gap), -limit_x, limit_x) - e.x
                    gz = clamp(e.z - e.face[1] * (e.band_min - gap), -limit_z, limit_z) - e.z
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
        live = [e for e in fighters if e.alive]
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
                if held_a and held_b:
                    continue
                share_a = 0.0 if held_a else 1.0 if held_b else b.r * b.r / (ar * ar + b.r * b.r)
                a.x -= nx * overlap * share_a
                a.z -= nz * overlap * share_a
                b.x += nx * overlap * (1 - share_a)
                b.z += nz * overlap * (1 - share_a)
                ax, az = a.x, a.z
        for e in live:
            limit_x, limit_z = max(self.half[0] - e.r, 0), max(self.half[1] - e.r, 0)
            e.x, e.z = clamp(e.x, -limit_x, limit_x), clamp(e.z, -limit_z, limit_z)
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
        if not kind.get("brain"):
            continue
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
            turn = a["places"] * a["damage"]
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
            turn = a["places"] * a["damage"]
            expect(turn / hp <= HIT_SHARE_MAX,
                   f"turns: {a['places']} {a['kind']} at once = {turn:.0f} = {turn / hp:.0%} of health <= "
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


def check(cfg, fam_rows, ab_rows, threat=None):
    failures = []

    def expect(ok, text):
        print(f"  {'PASS' if ok else 'FAIL'}  {text}")
        if not ok:
            failures.append(text)

    print()
    print("CHECK (bands in tools/sim_range.py; targets from docs/WEAPONS.md and docs/BALANCE.md P3)")
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
    print()
    print(f"CHECK: {'PASS' if not failures else 'FAIL (' + str(len(failures)) + ')'}")
    return not failures


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="exit 1 if a shipped value leaves the design bands")
    parser.add_argument("--config", default=str(CONFIG_PATH), help="ProvingGrounds.json to measure")
    parser.add_argument("--trials", type=int, default=120, help="random trials per measurement")
    args = parser.parse_args()
    cfg = load_config(args.config)
    fam_rows = family_rows(cfg, args.trials)
    print_families(fam_rows)
    ab_rows = ability_rows(cfg, fam_rows, args.trials)
    print_abilities(ab_rows)
    env = threat_env(cfg)
    threat = (env, threat_facts(cfg, env), threat_rows(cfg, env), role_rows(cfg, env), plate_rows(cfg))
    print_threat(cfg, *threat, ab_rows)
    if args.check:
        sys.exit(0 if check(cfg, fam_rows, ab_rows, threat) else 1)


if __name__ == "__main__":
    main()
