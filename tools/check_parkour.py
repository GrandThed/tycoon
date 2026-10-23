#!/usr/bin/env python
"""The parkour gate (L4 W2, MISSIONS_DESIGN 28: the mountain climb and the Castle Key): a climb of
double jumps round a peak, a chest on top. For every climb CLIMBS names, on the layout as it ships:

  * blocks:   the yard, the ledges and the summit are there, solid and of a ground look; the summit
              holds the climb's secret, which needs the bought double jump; every ledge's open top is
              at least LEDGE_MIN (a phone's thumb), and its tops rise in order.
  * hops:     every hop (yard -> ledge 1 -> ... -> summit) rises inside L2-18a's band (over one jump
              and a step up, at least LOOKOUT_UNDER_DOUBLE under jump + double jump), the two tops meet
              along a face at least FACE_MIN wide (or the double jump carries the gap), no surface under
              the next top is within one jump, a step up and a dash of it (L2-18b), and no lifting
              ability's arc puts a player without the double jump on it (L2-18c, LIFT_MODEL).
  * order:    with the double jump, and every lifting ability on top of it, no hop skips more than
              one ledge (the shortest climb to the summit is reported), and no standable top inside
              the climb's ground but the yard, the ledges, the summit and the chest.
  * falls:    every ledge and the summit stand wholly over the yard, so a fall off any edge lands on a
              lower ledge or the yard (the fall table); the yard's ground meets the rest of the level
              only at its mouths, and every ledge lies farther from every mouth than its flight
              carries (flight_reach: the jump, a double jump at the best moment, a dash that stops the
              fall, the walk-off grace, and the longest ability that carries) and FALL_MARGIN more; the
              forest generator's wall on the yard's other edges (wallTop) stands over every flight.
  * sight:    no point of the climb sees a region cell within R8's reach (ctx sniperReach), or a wall
              stands between (check_levels.sight_blockers, sees_region).
  * time:     a rough climb: a perfect run and a first one (FIRST_*), against Ben's 1-2 minutes.

check_levels.py calls `check_climbs` from check_layout (one hook) and `ledge_below` from L2-18a (a
climb's secret is held to the band over its last ledge, not the road). Run alone it loads the files
the way check_levels does; `--mutants` turns each rule red once on a copy in memory (MUTANTS).

Usage:
  py tools/check_parkour.py              # the gates; exit 1 when one fails
  py tools/check_parkour.py --mutants    # every mutant must turn the gate red; exit 1 when one does not
"""

from __future__ import annotations

import argparse
import copy
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

# ---------------------------------------------------------------------------------------------
# The climbs (tool data, like check_levels' EXPECTED: the game reads none of it).
# ---------------------------------------------------------------------------------------------

CLIMBS = {
    "ForestRoad": {
        # MISSIONS_DESIGN 28: behind the trailhead, one lap of eight double jumps, the Castle Key on top.
        "secret": "mountain",
        # The ground at the climb's foot, one height: the yard round the mountain and the trail to it.
        "yard": ("MountainYard", "MountainTrail", "MountainPath"),
        # In climbing order. The summit is the mountain's core: its only top is where the chest stands.
        "ledges": ("MountainLedge1", "MountainLedge2", "MountainLedge3", "MountainLedge4", "MountainLedge5",
                   "MountainLedge6", "MountainLedge7"),
        "summit": "MountainSummit",
        # The forest generator's invisible wall on the yard's and the trail's edges, but their mouths, stands
        # this high (the summit's 200 and barrier.height 80): tools/levels/forest.py's to build.
        "wallTop": 280.0,
    },
}

LEDGE_MIN = (14.0, 20.0)  # a ledge's open top: its shorter side at least the lookout ledge's 14, its longer 20
FACE_MIN = 14.0  # two tops of a hop meet along at least this much (the face a player lines up on)
FALL_MARGIN = 10.0  # every flight ends at least this far short of a mouth; the wall stands this far over it
# A rough climb (time line): a first climb walks at this share of walk speed (a thumbstick and the camera),
# spends this long on each hop reading the face and lining up, and misses this share of hops once.
FIRST_WALK_SHARE = 0.75
FIRST_HOP_SECONDS = 3.0
FIRST_MISS_SHARE = 1 / 3
TIME_BAND = (45.0, 120.0)  # the first climb's estimate (Ben's "1-2 minutes", a minute either side of a perfect run)
LANDING_IN = 2.0  # a landing stands this far inside the face it came over; a take-off a body's radius short of it
FLIGHT_STEP = 0.02  # the flight optimiser's grid (s), refined round the best to FLIGHT_FINE
FLIGHT_FINE = 0.002
FLIGHT_SECONDS = 5.0  # the latest moment a double jump or a dash is tried after the jump

# ---------------------------------------------------------------------------------------------
# Flight: how far on the flat a player travels before his feet come down to a height
# ---------------------------------------------------------------------------------------------

_FLIGHTS = {}


def _land(y, vy, target, gravity):
    """Seconds until a body at y moving up at vy comes down through `target` (None: it never does)."""
    under = vy * vy + 2 * gravity * (y - target)
    if under < 0:
        return None
    t = (vy + math.sqrt(under)) / gravity
    return t if t > -1e-9 else None


def _flight_once(move, gravity, drop, t1, t2, coyote):
    """One flight (MovementController): a jump at t = 0 (or the walk-off grace: off the edge, falling
    coyoteSeconds from rest, then the ground jump from there); the double jump at t1 (or None) sets the
    rise to jumpSpeed(doubleJumpHeight), never sooner than airJumpDelay; a dash at t2 (or None) holds
    the altitude for dashSeconds and covers dashDistance, leaving no rise or fall (the mover's vector
    is flat). Walk speed on the flat throughout (air control). The flat distance when the feet come
    down through -drop, or None."""
    v1 = math.sqrt(2 * gravity * move["jumpHeight"])
    v2 = math.sqrt(2 * gravity * move["doubleJumpHeight"])
    walk, grace = move["walkSpeed"], move.get("coyoteSeconds") or 0.0
    seconds = max(move.get("dashSeconds") or 0.0, 1 / 60)
    y, d = 0.0, 0.0
    if coyote:
        d += walk * grace
        y -= gravity * grace * grace / 2
    vy, t = v1, 0.0
    events = ([(t1, 0)] if t1 is not None else []) + ([(t2, 1)] if t2 is not None else [])
    for when, kind in sorted(events):
        if when < t:
            return None  # the double jump fell inside the dash (run() refuses that; kept as a net)
        land = _land(y, vy, -drop, gravity)
        if land is not None and land <= when - t:
            return d + walk * land
        dt = when - t
        y, vy, d, t = y + vy * dt - gravity * dt * dt / 2, vy - gravity * dt, d + walk * dt, when
        if kind == 0:
            vy = v2
        else:
            d += move["dashDistance"]
            t += seconds
            vy = 0.0
    land = _land(y, vy, -drop, gravity)
    return None if land is None else d + walk * land


def flight_reach(move, gravity, drop, dash=True, air=True):
    """The farthest a player travels on the flat before his feet come down to `drop` studs under
    where he left (a negative drop: over it), at the best moment for each move: the walk-off grace or
    not, the double jump (`air`) and one dash (`dash`). None when no flight gets that high. Kept per
    (movement, drop, dash, air)."""
    key = (tuple(sorted((k, v) for k, v in move.items() if isinstance(v, (int, float)))), gravity, round(drop, 4),
           dash, air)
    if key in _FLIGHTS:
        return _FLIGHTS[key]
    delay = move.get("airJumpDelay") or 0.0
    seconds = max(move.get("dashSeconds") or 0.0, 1 / 60)

    def run(t1, t2, coyote):
        if t1 is not None and t1 < delay - 1e-9:
            return None
        if t1 is not None and t2 is not None and t2 < t1 < t2 + seconds:
            return None  # a double jump inside the dash is held flat by the mover: wasted
        return _flight_once(move, gravity, drop, t1, t2, coyote)

    steps = int(FLIGHT_SECONDS / FLIGHT_STEP)
    jumps = [None] + ([delay + FLIGHT_STEP * k for k in range(steps)] if air else [])
    dashes = [None] + ([FLIGHT_STEP * k for k in range(steps)] if dash else [])
    best = (None, None)
    for coyote in (False, True):
        for t1 in jumps:
            for t2 in dashes:
                found = run(t1, t2, coyote)
                if found is not None and (best[0] is None or found > best[0]):
                    best = (found, (t1, t2, coyote))
    if best[0] is not None:
        t1, t2, coyote = best[1]
        span = int(2 * FLIGHT_STEP / FLIGHT_FINE)
        for i in range(-span, span + 1):
            a = None if t1 is None else t1 + i * FLIGHT_FINE
            for k in range(-span, span + 1):
                b = None if t2 is None else max(t2 + k * FLIGHT_FINE, 0.0)
                found = run(a, b, coyote)
                if found is not None and found > best[0]:
                    best = (found, (a, b, coyote))
                if t2 is None:
                    break
            if t1 is None:
                break
    _FLIGHTS[key] = best[0]
    return best[0]


def air_seconds(move, gravity, rise):
    """A hop's time in the air: the jump, the double jump at its peak, down to `rise`."""
    up = math.sqrt(2 * move["jumpHeight"] / gravity) + math.sqrt(2 * move["doubleJumpHeight"] / gravity)
    return up + math.sqrt(2 * max(move["jumpHeight"] + move["doubleJumpHeight"] - rise, 0.0) / gravity)


# ---------------------------------------------------------------------------------------------
# Plan helpers
# ---------------------------------------------------------------------------------------------


def _box(s):
    return (s.x0, s.x1, s.z0, s.z1)


def contact(a, b, eps=1e-6):
    """Where two footprints meet edge to edge: (length, (x, z) of its middle), or (0, None)."""
    ox = min(a.x1, b.x1) - max(a.x0, b.x0)
    oz = min(a.z1, b.z1) - max(a.z0, b.z0)
    if abs(ox) <= eps and oz > eps:
        x = a.x1 if abs(a.x1 - b.x0) <= eps else a.x0
        return oz, (x, (max(a.z0, b.z0) + min(a.z1, b.z1)) / 2)
    if abs(oz) <= eps and ox > eps:
        z = a.z1 if abs(a.z1 - b.z0) <= eps else a.z0
        return ox, ((max(a.x0, b.x0) + min(a.x1, b.x1)) / 2, z)
    return 0.0, None


def inside_point(s, point, by):
    """A point `by` studs inside a footprint from a point on (or near) its edge, toward its centre on
    the axis that edge faces."""
    x, z = point
    cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
    if min(abs(x - s.x0), abs(x - s.x1)) <= min(abs(z - s.z0), abs(z - s.z1)):
        x += by if x < cx else -by
    else:
        z += by if z < cz else -by
    return min(max(x, s.x0), s.x1), min(max(z, s.z0), s.z1)


def over_yard(yards, s, step=1.0):
    """The points of a footprint (a `step` grid and its edges) no yard block holds."""
    xs = [s.x0 + step * k for k in range(int((s.x1 - s.x0) / step) + 1)] + [s.x1]
    zs = [s.z0 + step * k for k in range(int((s.z1 - s.z0) / step) + 1)] + [s.z1]
    return [(x, z) for x in xs for z in zs if not any(y.holds(x, z) for y in yards)]


def outline(rects, eps=1e-6):
    """The outline of a union of rectangles: [(side, c, a, b)] stretches, side "x" (a line x = c from
    z a to b) or "z" (z = c from x a to b), each with the outward normal's sign: (side, c, a, b, sign)."""
    found = []
    for r in rects:
        for side, c, lo, hi, sign in (("x", r.x0, r.z0, r.z1, -1), ("x", r.x1, r.z0, r.z1, 1),
                                      ("z", r.z0, r.x0, r.x1, -1), ("z", r.z1, r.x0, r.x1, 1)):
            cuts = []
            for o in rects:
                if o is r:
                    continue
                if side == "x" and (o.x0 <= c + eps if sign > 0 else o.x1 >= c - eps) and \
                        (o.x1 > c + eps if sign > 0 else o.x0 < c - eps):
                    cuts.append((o.z0, o.z1))
                if side == "z" and (o.z0 <= c + eps if sign > 0 else o.z1 >= c - eps) and \
                        (o.z1 > c + eps if sign > 0 else o.z0 < c - eps):
                    cuts.append((o.x0, o.x1))
            spans = [(lo, hi)]
            for a, b in sorted(cuts):
                spans = [p for s0, s1 in spans for p in ((s0, min(s1, a)), (max(s0, b), s1)) if p[1] - p[0] > eps]
            found += [(side, c, a, b, sign) for a, b in spans]
    return found


def yard_face(dst, yards, tops, step=0.5):
    """How much of a top's outline a player in the yard stands against: the points half a stud
    outside it over yard ground that no other top of the climb covers."""
    held = 0.0
    for side, c, a, b, sign in outline([dst]):
        cuts = int(math.ceil((b - a) / step))
        for k in range(cuts):
            m = a + (k + 0.5) * (b - a) / cuts
            px, pz = (c + sign * 0.5, m) if side == "x" else (m, c + sign * 0.5)
            if any(y.holds(px, pz) for y in yards) and not any(o is not dst and o.holds(px, pz) for o in tops):
                held += (b - a) / cuts
    return held


def segment_box_gap(stretch, box):
    """The flat distance from an outline stretch to a rectangle (x0, x1, z0, z1)."""
    side, c, a, b, _sign = stretch
    if side == "x":
        dx = max(box[0] - c, c - box[1], 0.0)
        dz = max(box[2] - b, a - box[3], 0.0)
    else:
        dz = max(box[2] - c, c - box[3], 0.0)
        dx = max(box[0] - b, a - box[1], 0.0)
    return math.hypot(dx, dz)


# ---------------------------------------------------------------------------------------------
# The gate
# ---------------------------------------------------------------------------------------------


def ledge_below(layout, secret):
    """L2-18a's hook (check_levels.check_secret_reach): for a climb's secret, (the top of the ledge
    the summit is climbed from, the flat distance from the chest's centre to it); None for any other
    secret, or when the layout lacks the climb's blocks."""
    for spec in CLIMBS.values():
        if spec["secret"] != secret.get("id"):
            continue
        blocks = {b.get("name"): b for b in layout.get("blocks") or []}
        last, summit = blocks.get(spec["ledges"][-1]), blocks.get(spec["summit"])
        if last is None or summit is None:
            return None
        hx, hz = last["sx"] / 2, last["sz"] / 2
        away = math.hypot(max(abs(secret["x"] - last["x"]) - hx, 0.0), max(abs(secret["z"] - last["z"]) - hz, 0.0))
        return last["y"] + last["sy"] / 2, away
    return None


def check_climbs(cl, name, layout, ctx, expect, solids, tall):
    """Every rule of the module docstring for the climbs CLIMBS names on layout `name`. `cl` is the
    check_levels module (its jumps, lifts and sight helpers: the same numbers, never copied)."""
    spec = CLIMBS.get(name)
    if spec is None:
        return None
    return _check_climb(cl, name, layout, ctx, expect, solids, tall, spec)


def _check_climb(cl, name, layout, ctx, expect, solids, tall, spec):
    move, eps = ctx["move"], cl.EPS
    gravity = cl.sr.GRAVITY
    sid = spec["secret"]
    tag = f"{name}: the {sid} climb"
    by_name = {s.name: s for s in solids}
    names = list(spec["yard"]) + list(spec["ledges"]) + [spec["summit"]]
    blocks = {b.get("name"): b for b in layout["blocks"]}
    lost = [n for n in names if n not in by_name]
    soft = [n for n in names if n in blocks and (blocks[n]["look"] not in cl.GROUND_LOOKS or blocks[n]["look"] == "water")]
    secret = next((s for s in layout["secrets"] if s["id"] == sid), None)
    chest = by_name.get(f"Secret_{sid}")
    base = cl.secret_base(solids, secret) if secret is not None else None
    expect(not lost and not soft and secret is not None and secret.get("needs") == cl.AIR_JUMP and base is not None
           and base.name == spec["summit"],
           f"{tag}: its {len(spec['yard'])} yard blocks, {len(spec['ledges'])} ledges and summit are solid blocks of a "
           f"ground look, and the {sid} chest stands on the summit behind the double jump"
           + (f" (missing: {', '.join(lost)})" if lost else "") + (f" (not ground: {', '.join(soft)})" if soft else "")
           + ("" if secret is not None else f" (no secret {sid})")
           + (f" (needs {secret.get('needs')})" if secret is not None and secret.get("needs") != cl.AIR_JUMP else "")
           + (f" (it stands on {base.name if base else 'nothing'})" if secret is not None and (base is None
                                                                                            or base.name != spec["summit"]) else ""))
    if lost or secret is None or chest is None:
        return None
    yards = [by_name[n] for n in spec["yard"]]
    ledges = [by_name[n] for n in spec["ledges"]]
    summit = by_name[spec["summit"]]
    tops = ledges + [summit]
    floor = yards[0].top
    level = [y.name for y in yards if abs(y.top - floor) > eps]
    rising = all(b.top > a.top + eps for a, b in zip([yards[0]] + tops, tops))
    # The open top of a ledge: its footprint less any solid standing on it.
    small = []
    for s in tops:
        covers = [o for o in solids if o is not s and o is not chest and o.top > s.top + eps
                  and o.bottom < s.top + cl.BODY_HEIGHT and o.x1 > s.x0 + eps and o.x0 < s.x1 - eps
                  and o.z1 > s.z0 + eps and o.z0 < s.z1 - eps]
        short, long = sorted((s.x1 - s.x0, s.z1 - s.z0))
        if covers or short < LEDGE_MIN[0] - eps or long < LEDGE_MIN[1] - eps:
            small.append(f"{s.name} {s.x1 - s.x0:g} x {s.z1 - s.z0:g}" + (f" under {covers[0].name}" if covers else ""))
    expect(not level and rising and not small,
           f"{tag}: the yard is one height ({floor:g}), the tops rise in climbing order "
           f"({', '.join(f'{s.top:g}' for s in tops)}), and every ledge's open top is at least {LEDGE_MIN[0]:g} x "
           f"{LEDGE_MIN[1]:g} (the lookout ledge is 24 x 14)"
           + (f" (yard blocks off its height: {', '.join(level)})" if level else "")
           + ("" if rising else " (the tops do not rise in order)") + (f" (too small: {', '.join(small)})" if small else ""))

    # --- Hops -------------------------------------------------------------------------------------
    lo = move["jumpHeight"] + cl.STEP_UP
    hi = move["jumpHeight"] + move["doubleJumpHeight"] - cl.LOOKOUT_UNDER_DOUBLE
    bare = cl.exposed(solids)
    standable = ("block", "floor", "secret", "fence", "obstacle")
    lifts = ctx.get("lifts") or []
    hop_rows, bad_band, bad_face, singles, lifted = [], [], [], [], []
    froms = [None] + tops[:-1]
    for k, (src, dst) in enumerate(zip(froms, tops), start=1):
        src_top = floor if src is None else src.top
        rise = dst.top - src_top
        label = f"{'yard' if src is None else src.name} -> {dst.name}"
        if not lo < rise <= hi + eps:
            bad_band.append(f"{label} rises {rise:g}")
        if src is None:
            gap, face = 0.0, yard_face(dst, yards, tops)
        else:
            gap = src.gap_to(dst)
            face, _mid = contact(src, dst)
        dj_reach = flight_reach(move, gravity, -(rise - cl.STEP_UP), dash=False)
        if (gap <= eps and face < FACE_MIN - eps) or (gap > eps and (dj_reach is None or gap > dj_reach - FALL_MARGIN)):
            bad_face.append(f"{label}: gap {gap:g}, face {face:g}")
        # L2-18b on this top: one jump, a step up and a dash, from every lower surface.
        ways = []
        for s in solids:
            if s.kind not in standable or s.name in tall or s.name not in bare or s.top >= dst.top - eps or s is chest:
                continue
            need = dst.top - s.top - cl.STEP_UP
            carry = cl.reach_at_rise(move, need)
            if carry is not None and s.gap_to(dst) <= carry + move["dashDistance"] + eps:
                ways.append(f"{s.name} ({dst.top - s.top:g} up, {s.gap_to(dst):.0f} away)")
        if ways:
            singles.append(f"{dst.name} from {', '.join(ways[:3])}")
        # L2-18c on this top: every lifting ability's arc, no double jump, from every lower surface.
        keys = [(dst.x0, dst.x1, dst.z0, dst.z1, dst.top, dst.name)]
        skip = {s.name for s in solids if s.top >= dst.top - eps}
        routes = cl.lift_routes(solids, keys, skip, tall, move, lifts)
        if routes:
            lifted.append(f"{dst.name}: {routes[0]}")
        # The highest feet a lift without the double jump gives from this hop's take-off (LIFT_MODEL "floor"): his
        # jump's top, or a target's floor (at most a jump over his own, within castRange) and the lift's height.
        best_lift = float(move["jumpHeight"])
        for _family, ability in lifts:
            near = [o.top - src_top for o in solids if o.kind in standable and o.top - src_top <= move["jumpHeight"] + eps
                    and min(o.gap_to(r) for r in (yards if src is None else [src])) <= float(ability["castRange"]) + eps]
            best_lift = max(best_lift, max(near + [0.0]) + float(ability["height"]))
        hop_rows.append({"k": k, "label": label, "gap": gap, "face": face, "rise": rise,
                         "one": move["jumpHeight"] + cl.STEP_UP, "dj": move["jumpHeight"] + move["doubleJumpHeight"],
                         "djReach": dj_reach, "lift": best_lift, "air": air_seconds(move, gravity, rise)})
    expect(not bad_band, f"{tag}: every hop rises over one jump and a step up ({lo:g}) and at most {hi:g} (jump + double "
           f"jump {move['jumpHeight'] + move['doubleJumpHeight']:g} less {cl.LOOKOUT_UNDER_DOUBLE:g}, L2-18a's band): "
           + (", ".join(bad_band) if bad_band else ", ".join(f"{r['rise']:g}" for r in hop_rows)))
    expect(not bad_face, f"{tag}: the two tops of every hop meet along a face at least {FACE_MIN:g} wide, or the double "
           f"jump alone carries the gap with {FALL_MARGIN:g} to spare"
           + (": " + "; ".join(bad_face) if bad_face else
              f" (faces {', '.join(f'{r['face']:g}' for r in hop_rows)}; the double jump alone carries "
              f"{hop_rows[0]['djReach']:.1f} at the first hop's rise)"))
    expect(not singles, f"{tag}: every hop needs the double jump: no lower surface is within one jump, a step up of "
           f"{cl.STEP_UP:g} and a dash of the next top (L2-18b on each top)"
           + (": " + "; ".join(singles) if singles else
              f" (one jump and a step up reach {lo:g}; the lowest rise is {min(r['rise'] for r in hop_rows):g}, "
              f"{min(r['rise'] for r in hop_rows) - lo:g} short)"))
    told = ", ".join(f"{f} ({a.get('name')}, height {float(a['height']):g}, castRange {float(a['castRange']):g})"
                     for f, a in lifts) or "none"
    expect(not lifted, f"{tag}: no lifting ability ({told}; LIFT_MODEL \"{cl.LIFT_MODEL}\") puts a player without the "
           f"double jump on any top from a lower surface (L2-18c on each top)" + (": " + "; ".join(lifted[:3]) if lifted else ""))

    # --- Order: no hop skips more than one ledge, nothing else to stand on --------------------------
    seq = [None] + tops  # index 0 = the yard
    reach_top = move["jumpHeight"] + move["doubleJumpHeight"] + cl.STEP_UP
    skips, worst = [], 0
    for j in range(2, len(seq)):
        dst = seq[j]
        for i in range(0, j - 1):
            src_top = floor if seq[i] is None else seq[i].top
            src_rects = yards if seq[i] is None else [seq[i]]
            rise = dst.top - src_top
            hit = None
            if rise <= reach_top + eps:
                carry = flight_reach(move, gravity, -(rise - cl.STEP_UP))
                gap = min(s.gap_to(dst) for s in src_rects)
                if carry is not None and gap <= carry + eps:
                    hit = f"the jumps and a dash from {'the yard' if i == 0 else seq[i].name} ({rise:g} up, {gap:.0f} away)"
            if hit is None:
                keys = [(dst.x0, dst.x1, dst.z0, dst.z1, dst.top, dst.name)]
                skip = {s.name for s in solids if s.top > src_top + eps}
                routes = cl.lift_routes(solids, keys, skip, tall, move, lifts, air=True)
                hit = routes[0] if routes else None
            if hit is not None:
                worst = max(worst, j - i - 1)
                skips.append(f"{dst.name} skipping {j - i - 1}: {hit}")
                break
    # The fewest double jumps to the summit (each hop as the jumps carry it, lifts aside).
    hops = {0: 0}
    frontier = [0]
    while frontier:
        nxt = []
        for i in frontier:
            for j in range(1, len(seq)):
                if j in hops:
                    continue
                src_top = floor if seq[i] is None else seq[i].top
                rise = seq[j].top - src_top
                if rise <= eps or rise > reach_top + eps:
                    continue
                carry = flight_reach(move, gravity, -(rise - cl.STEP_UP))
                gap = min(s.gap_to(seq[j]) for s in (yards if seq[i] is None else [seq[i]]))
                if carry is not None and gap <= carry + eps:
                    hops[j] = hops[i] + 1
                    nxt.append(j)
        frontier = nxt
    fewest = hops.get(len(seq) - 1)
    expect(worst <= 1 and fewest == len(tops),
           f"{tag}: with the double jump, a dash and every lifting ability on top, no hop skips more than one ledge, and "
           f"the summit is reached in order: {fewest if fewest is not None else 'never'} double jumps at the fewest "
           f"(the climb has {len(tops)}); the most any hop skips: {worst}" + (" (" + "; ".join(skips[:3]) + ")" if skips else ""))
    listed = set(names) | {chest.name}
    stray = []
    for s in solids:
        if s.name in listed or s.kind not in standable or s.name not in bare:
            continue
        if any(min(s.x1, y.x1) - max(s.x0, y.x0) > eps and min(s.z1, y.z1) - max(s.z0, y.z0) > eps for y in yards):
            stray.append(f"{s.name} (top {s.top:g})")
    expect(not stray, f"{tag}: over its ground nothing is standable but the yard, the ledges, the summit and the chest "
           f"(the summit is the mountain's core: its only top)" + (f" (found: {', '.join(stray)})" if stray else ""))

    # --- Falls --------------------------------------------------------------------------------------
    loose = [f"{s.name} at ({p[0]:g}, {p[1]:g})" for s in tops for p in over_yard(yards, s)[:1]]
    rows = []
    void = []
    for s in tops:
        sides = {}
        for side, c, a, b, sign in outline([s]):
            m = (a + b) / 2
            px, pz = (c + sign * 0.5, m) if side == "x" else (m, c + sign * 0.5)
            word = ("west" if sign < 0 else "east") if side == "x" else ("north" if sign < 0 else "south")
            wall = next((o for o in tops if o is not s and o.holds(px, pz) and o.top > s.top + eps), None)
            top, under = cl.ground(solids, px, pz, s.top - eps)
            if wall is not None:
                sides[word] = f"{wall.name}'s face"
            elif under is None:
                sides[word] = "the void"
                void.append(f"{s.name} {word}")
            else:
                sides[word] = f"{under.name} ({s.top - top:g} down)"
                if under.name not in names:
                    void.append(f"{s.name} {word} onto {under.name}")
        rows.append((s.name, s.top, sides))
    expect(not loose and not void, f"{tag}: every ledge and the summit stand wholly over the yard, so a fall off any edge "
           f"lands on a lower ledge or the yard" + (f" (off the yard: {', '.join(loose)})" if loose else "")
           + (f" (falls into {', '.join(void)})" if void else ""))
    # The mouths: the yard's outline where it meets anything of the level's walkable whole that is not the climb's
    # (ground at any height, water, a camp's floor): the forest generator stands no wall there.
    walkable = [o for o in solids if o.name not in names and (o.kind == "floor" or (o.kind == "block" and o.look in cl.GROUND_LOOKS))]
    walkable += [cl.block_solid(b) for b in layout["blocks"] if b.get("collide") is False and b["look"] in cl.GROUND_LOOKS]
    mouths = []
    for stretch in outline(yards):
        side, c, a, b, sign = stretch
        for o in walkable:
            if side == "x" and abs((o.x0 if sign > 0 else o.x1) - c) <= eps:
                lo_, hi_ = max(a, o.z0), min(b, o.z1)
            elif side == "z" and abs((o.z0 if sign > 0 else o.z1) - c) <= eps:
                lo_, hi_ = max(a, o.x0), min(b, o.x1)
            else:
                continue
            if hi_ - lo_ > eps:
                mouths.append((side, c, lo_, hi_, sign, o.name))
    carriers = cl.carrying_families(ctx)
    carry = max([0.0] + [studs for _n, studs in carriers.values()])
    carried = ", ".join(f"{f}'s {a} {studs:g}" for f, (a, studs) in sorted(carriers.items())) or "none"
    short, tightest = [], None
    for s in tops:
        flight = flight_reach(move, gravity, s.top - floor) or 0.0
        need = flight + carry + FALL_MARGIN
        for m in mouths:
            gap = segment_box_gap(m[:5], _box(s))
            spare = gap - need
            if tightest is None or spare < tightest[0]:
                tightest = (spare, s.name, m[5], gap, flight)
            if spare < -eps:
                short.append(f"{s.name} {gap:.1f} from the mouth onto {m[5]} (its flight {flight:.1f} + {carry:g} + "
                             f"{FALL_MARGIN:g})")
    wall_need = summit.top + move["jumpHeight"] + move["doubleJumpHeight"] + ctx.get("abilityHeight", 0.0) + FALL_MARGIN
    expect(bool(mouths) and not short and spec["wallTop"] >= wall_need - eps,
           f"{tag}: no fall leaves the yard: its ground meets the level only at its mouths "
           f"({', '.join(sorted({m[5] for m in mouths})) or 'none'}), every top lies farther from each than its flight "
           f"(the jumps, a dash that stops the fall, the walk-off grace; flight_reach) and the longest ability that carries "
           f"({carried}) carry, and {FALL_MARGIN:g} more, and the yard's wall (wallTop {spec['wallTop']:g}) stands at least "
           f"{wall_need:g} high" + (": " + "; ".join(short[:3]) if short else
                                    f" (the tightest: {tightest[1]} {tightest[3]:.1f} from the mouth onto {tightest[2]}, "
                                    f"its flight {tightest[4]:.1f}, {tightest[0]:.1f} to spare)" if tightest else ""))

    # --- Sight --------------------------------------------------------------------------------------
    reach = (ctx.get("sniperReach") or (0.0, "none"))[0]
    seen, nearest = [], None
    for region in layout.get("regions") or []:
        cells = [cl.cell_box(c) for c in cl.sr.region_cells(layout, region)]
        for s in yards + tops:
            gap = min(cl.rect_gap(_box(s), c) for c in cells)
            if nearest is None or gap < nearest[0]:
                nearest = (gap, s.name, region["id"])
            if gap > reach + eps:
                continue
            blockers = tuple(cl.sight_blockers(solids, s.top, region["y"]))
            for x, z in cl.standable_points(solids, s, cl.SPOT_STEP):
                if cl.sees_region(x, z, cells, blockers, reach):
                    seen.append(f"{s.name} at ({x:g}, {z:g})")
                    break
    expect(not seen, f"{tag}: no point of it sees a region cell within R8's reach {reach:g} without a wall between"
           + (f": {', '.join(seen)}" if seen else
              f" (the nearest: {nearest[1]} {nearest[0]:.0f} studs off the {nearest[2]} region)" if nearest else
              " (no region)"))

    # --- Time ---------------------------------------------------------------------------------------
    walk = move["walkSpeed"]
    mouth = mouths[0] if mouths else None
    path, here = 0.0, None
    if mouth is not None:
        side, c, a, b, _sign, _n = mouth
        here = (c, (a + b) / 2) if side == "x" else ((a + b) / 2, c)
    legs = []
    for k, dst in enumerate(tops):
        src = None if k == 0 else tops[k - 1]
        if src is None:
            # The yard's walk: to the nearest point of the first ledge's foot.
            target = (min(max(here[0], dst.x0), dst.x1), min(max(here[1], dst.z0), dst.z1)) if here else None
            legs.append(math.dist(here, target) if here else 0.0)
            here = inside_point(dst, target, LANDING_IN) if target else None
            continue
        _len, mid = contact(src, dst)
        if mid is None:  # no shared face (the face rule says so): from centre to centre
            mid = ((src.x0 + src.x1 + dst.x0 + dst.x1) / 4, (src.z0 + src.z1 + dst.z0 + dst.z1) / 4)
        take = inside_point(src, mid, cl.BODY_RADIUS)
        legs.append(math.dist(here, take) if here else 0.0)
        here = inside_point(dst, mid, LANDING_IN)
    legs.append(cl.trigger_gap(secret, *here) if here else 0.0)
    path = sum(legs)
    air = sum(r["air"] for r in hop_rows)
    perfect = path / walk + air
    first = path / (walk * FIRST_WALK_SHARE) + air + len(hop_rows) * FIRST_HOP_SECONDS \
        + len(hop_rows) * FIRST_MISS_SHARE * (hop_rows[0]["air"] + FIRST_HOP_SECONDS)
    expect(TIME_BAND[0] <= first <= TIME_BAND[1],
           f"{tag}: a rough climb from its mouth: {path:.0f} studs walked and {len(hop_rows)} hops ({air:.1f} s in the air); "
           f"a perfect run {perfect:.0f} s, a first one about {first:.0f} s (walking at {FIRST_WALK_SHARE:g} of walk speed, "
           f"{FIRST_HOP_SECONDS:g} s on each hop, one hop in {1 / FIRST_MISS_SHARE:g} missed once), inside "
           f"{TIME_BAND[0]:g}-{TIME_BAND[1]:g} s (Ben's 1-2 minutes)")
    return {"hops": hop_rows, "falls": rows, "mouths": mouths, "tightest": tightest, "path": path, "perfect": perfect,
            "first": first, "legs": legs, "skips": worst, "fewest": fewest, "carry": carry,
            "heights": [0.0] + [s.top - floor for s in tops]}


# ---------------------------------------------------------------------------------------------
# Run alone, and the mutants
# ---------------------------------------------------------------------------------------------


def _tables(cl, result, move):
    """The hop and fall tables, for the report."""
    gravity = cl.sr.GRAVITY
    print("  hops: gap / face / rise; one jump + step up tops at; the double jump at its peak; the double jump's flat "
          "reach at the rise (no dash); the best lift without it (feet); margins")
    for r in result["hops"]:
        print(f"    {r['k']}. {r['label']}: gap {r['gap']:g}, face {r['face']:g}, rise {r['rise']:g}; one jump "
              f"{r['one']:g} ({r['rise'] - r['one']:g} short); double jump {r['dj']:g} ({r['dj'] - r['rise']:g} over, "
              f"{r['dj'] + cl.STEP_UP - r['rise']:g} with the step up); its reach {r['djReach']:.1f}; best lift "
              f"{r['lift']:g} ({r['rise'] - cl.STEP_UP - r['lift']:g} short); {r['air']:.2f} s in the air")
    print("  falls (off each edge's middle):")
    for nm, top, sides in result["falls"]:
        print(f"    {nm} (top {top:g}): " + "; ".join(f"{k} -> {v}" for k, v in sides.items()))
    print("  flight reach to the yard (the jumps, a double jump at the best moment, one dash that stops the fall, the "
          "walk-off grace):")
    for drop in result["heights"]:
        print(f"    from {drop:g} up: {flight_reach(move, gravity, drop):.1f} studs (no dash "
              f"{flight_reach(move, gravity, drop, dash=False):.1f}; check_levels.stray_reach "
              f"{cl.stray_reach(move, drop):.1f})")
    print(f"  walk legs: {', '.join(f'{v:.0f}' for v in result['legs'])}")


def _context(cl):
    combat, expeditions, layouts, level_files, ctx = cl.load_all()
    ctx["ownedFamilies"] = cl.ownable_families(level_files, layouts, expeditions, ctx.get("weapons") or {},
                                               ctx.get("loadout") or [])
    ctx["sniperReach"] = cl.sniper_reach(ctx.get("weapons") or {}, ctx["ownedFamilies"])
    return layouts, ctx


def run(cl, layouts, ctx, expect, tables=False):
    levels = ctx["levels"]
    results = {}
    for name in CLIMBS:
        layout = layouts.get(name)
        if layout is None:
            expect(False, f"{name}: the layout CLIMBS names is there")
            continue
        solids = cl.solids_of(layout, levels["fenceThickness"], levels["floorThickness"])
        tall = cl.unclimbable(solids, ctx["move"], ctx["abilityHeight"])
        results[name] = check_climbs(cl, name, layout, ctx, expect, solids, tall)
        if tables and results[name]:
            _tables(cl, results[name], ctx["move"])
    return results


def _blocks(layout):
    return {b.get("name"): b for b in layout["blocks"]}


def _lower(layout):
    """A ledge lowered to one jump's reach of the one under it."""
    b = _blocks(layout)
    low, high = b["MountainLedge3"], b["MountainLedge4"]
    top = low["y"] + low["sy"] / 2 + 20
    high["sy"] = top - (high["y"] - high["sy"] / 2)
    high["y"] = top - high["sy"] / 2


def _widen(layout):
    """A gap widened past the double jump's reach: ledge 5 pulled 50 studs north, 30 off ledge 4."""
    b = _blocks(layout)
    b["MountainLedge5"]["z"] -= 50


def _void(layout):
    """A ledge moved so a fall reaches the void: ledge 2 pushed 20 studs out past the yard's east edge."""
    b = _blocks(layout)
    b["MountainLedge2"]["x"] += 20


def _shelf(layout):
    """The core given a standable top: a 6 x 10 shelf out of its east face over ledge 3, 12 over its top."""
    b = _blocks(layout)
    core, l3 = b["MountainSummit"], b["MountainLedge3"]
    top = l3["y"] + l3["sy"] / 2 + 12
    layout["blocks"].append({"name": "MutantShelf", "look": "ground", "x": core["x"] + core["sx"] / 2 + 3, "y": top - 2,
                             "z": l3["z"], "sx": 6, "sy": 4, "sz": 10})


def _raise(layout):
    """A ledge raised past what the double jump carries: ledge 6 at 28 over ledge 5."""
    b = _blocks(layout)
    l5, l6 = b["MountainLedge5"], b["MountainLedge6"]
    top = l5["y"] + l5["sy"] / 2 + 28
    bottom = l6["y"] - l6["sy"] / 2
    l6["sy"], l6["y"] = top - bottom, (top + bottom) / 2


def _mouth(layout):
    """A mouth within a ledge's flight: the trail cut short, the yard met by a path 40 studs east of it."""
    b = _blocks(layout)
    yard = b["MountainYard"]
    x1 = yard["x"] + yard["sx"] / 2
    layout["blocks"].append({"name": "MutantPath", "look": "path", "x": x1 + 20, "y": -2, "z": yard["z"], "sx": 40,
                             "sy": 4, "sz": 16})


MUTANTS = (
    ("a ledge lowered to one jump's reach (ledge 4 at 20 over ledge 3)", _lower, "every hop needs the double jump"),
    ("a gap widened past the double jump's reach (ledge 5 30 studs off ledge 4)", _widen, "meet along a face"),
    ("a ledge moved so a fall reaches the void (ledge 2 20 studs out)", _void, "stand wholly over the yard"),
    ("the core given a standable top (a shelf 12 over ledge 3)", _shelf, "nothing is standable but"),
    ("a ledge raised past the double jump (ledge 6 at 28 over ledge 5)", _raise, "every hop rises over one jump"),
    ("a mouth within a flight (a path off the yard's east edge)", _mouth, "no fall leaves the yard"),
)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--mutants", action="store_true", help="turn each rule red once on a copy in memory")
    parser.add_argument("--tables", action="store_true", help="print the hop and fall tables")
    args = parser.parse_args()
    import check_levels as cl

    layouts, ctx = _context(cl)
    if args.mutants:
        bad = []
        for label, mutate, rule in MUTANTS:
            copies = copy.deepcopy(layouts)
            for name in CLIMBS:
                mutate(copies[name])
            lines = []
            run(cl, copies, ctx, lambda ok, text: lines.append((ok, text)))
            red = [text for ok, text in lines if not ok and rule in text]
            print(f"  {'ok ' if red else 'NOT'}  {label}: " + (red[0][:300] if red else f"no red line carrying \"{rule}\""))
            if not red:
                bad.append(label)
        print()
        print(f"MUTANTS: {'PASS' if not bad else 'FAIL (' + str(len(bad)) + ')'} ({len(MUTANTS) - len(bad)} of "
              f"{len(MUTANTS)} red)")
        sys.exit(0 if not bad else 1)
    failures = []

    def expect(ok, text):
        print(f"  {'PASS' if ok else 'FAIL'}  {text}")
        if not ok:
            failures.append(text)

    run(cl, layouts, ctx, expect, tables=args.tables)
    print()
    print(f"PARKOUR: {'PASS' if not failures else 'FAIL (' + str(len(failures)) + ')'}")
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
