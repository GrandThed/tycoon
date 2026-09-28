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
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = REPO_ROOT / "src" / "shared" / "Config" / "ProvingGrounds.json"

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


def melee_attack(world, cfg, v, step, origin=None):
    """resolveMelee from the root, facing +x. step is the combo index (0-based)."""
    origin = origin or (0.0, ROOT_HEIGHT, 0.0)
    chain = v.get("chain") or [1.0]
    k = step % len(chain)
    arc = v.get("arcDegrees")
    if k == len(chain) - 1 and v.get("finisherArcDegrees") is not None:
        arc = v["finisherArcDegrees"]
    spec = {"shape": v["shape"], "origin": origin, "direction": (1, 0, 0), "size": v["range"], "pad": v["pad"],
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


def check(cfg, fam_rows, ab_rows):
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
    if args.check:
        sys.exit(0 if check(cfg, fam_rows, ab_rows) else 1)


if __name__ == "__main__":
    main()
