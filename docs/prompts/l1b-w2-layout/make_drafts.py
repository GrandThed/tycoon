#!/usr/bin/env python
"""Writes the two Wave 2 layout drafts for Forest Road (L1b Wave 2, "the long road").

A draft, not game data: nothing in src/ reads these files. Each design writes two JSON files in
the shapes the game already reads, so the contract can adopt them nearly as they stand:

  <name>.level.json   the shape of src/shared/Config/Levels/1_ForestRoad.json
  <name>.layout.json  the shape of src/shared/Layouts/Levels/ForestRoad.json

Keys a Wave 2 contract would add (the game reads none of them today):
  level  crowd.clearBonus.share     Ben's ruling 2: ~10% of the camp's stock at full price
  level  camps[].tent               { every, units }: the reinforcement tent's pace and stock
  layout camps[].tent               { x, z, sx, sy, sz }: the tent's walk-through marker block
  layout sneak                      the sneak path, a polyline for check_levels' Wave 2 gate

Spots are written in camp-local studs (u east, v south of the camp's centre) and turned into
world x, z here. North is -z (yaw 0 faces -z; layout `facing` 0 = north, 90 = west, 180 = south,
270 = east).

Usage: py make_drafts.py        (writes the four JSON files next to this script)
"""

from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
GREY = [104, 106, 112]

DIFFICULTIES = {
    "normal": {"hpScale": 1.5, "damageScale": 1.12, "plateScale": 1, "countMult": 1, "rewardMult": 1, "recommendedTier": 2},
    "hard": {"hpScale": 5.2, "damageScale": 2.0, "plateScale": 1, "countMult": 1.2, "rewardMult": 2, "recommendedTier": 4},
    "brutal": {"hpScale": 11.5, "damageScale": 3.35, "plateScale": 1, "countMult": 1.35, "rewardMult": 4, "recommendedTier": 6},
}
REWARDS = {
    "fodder": {"cash": 100, "materials": 0},
    "slinger": {"cash": 500, "materials": 1},
    "brute": {"cash": 2000, "materials": 6},
    "lobber": {"cash": 700, "materials": 4},
    "marksman": {"cash": 600, "materials": 1},
    "armoured": {"cash": 1200, "materials": 2},
    "colossus": {"cash": 29000, "materials": 70},
}


def road(name, x0, x1, z0, z1, top, deep=4.0, look="path"):
    """A ground block whose top is at `top`, `deep` studs deep."""
    return {"name": name, "look": look, "x": (x0 + x1) / 2, "y": top - deep / 2, "z": (z0 + z1) / 2,
            "sx": x1 - x0, "sy": deep, "sz": z1 - z0}


def u(n):
    """One unit entry; `hard` = fielded from Hard up (L1b-10's minDifficulty)."""
    kind, count, *rest = n
    entry = {"kind": kind, "count": count}
    if rest:
        entry["minDifficulty"] = rest[0]
    return entry


class Camp:
    """A camp in world coordinates, with helpers that take camp-local (u, v) studs."""

    def __init__(self, cid, cx, cz, sx, sz, top):
        self.cid, self.cx, self.cz, self.sx, self.sz, self.top = cid, cx, cz, sx, sz, top

    def p(self, uu, vv):
        return {"x": round(self.cx + uu, 3), "z": round(self.cz + vv, 3)}

    @property
    def x0(self):
        return self.cx - self.sx / 2

    @property
    def x1(self):
        return self.cx + self.sx / 2

    @property
    def z0(self):
        return self.cz - self.sz / 2

    @property
    def z1(self):
        return self.cz + self.sz / 2

    def fire(self, sid, uu, vv, radius):
        return {"id": sid, "posture": "fire", "points": [self.p(uu, vv)], "radius": radius}

    def guard(self, sid, points, facing):
        return {"id": sid, "posture": "guard", "points": [self.p(a, b) for a, b in points], "facing": facing}

    def patrol(self, sid, points):
        return {"id": sid, "posture": "patrol", "points": [self.p(a, b) for a, b in points]}

    def row(self, u0, v0, du, dv, n):
        return [(u0 + du * k, v0 + dv * k) for k in range(n)]

    def cover(self, uu, vv, sx, sz, sy=3.5):
        return {"x": round(self.cx + uu, 3), "z": round(self.cz + vv, 3), "sx": sx, "sy": sy, "sz": sz,
                "material": "SmoothPlastic", "color": GREY}

    def tent(self, uu, vv, sx=10, sz=10, sy=8):
        """The tent's marker: a walk-through block (collide false), so it is no perch or cover."""
        return {"x": round(self.cx + uu, 3), "y": self.top + sy / 2, "z": round(self.cz + vv, 3),
                "sx": sx, "sy": sy, "sz": sz}

    def body(self, name, **rest):
        out = {"id": self.cid}
        if rest.pop("locks", False):
            out["locks"] = True
        out.update({"name": name, "x": self.cx, "y": self.top, "z": self.cz, "sx": self.sx, "sz": self.sz,
                    "fence": {"height": 4}})
        out.update(rest)
        out.pop("name")
        return out


def level_file(camps, c_waves, target_minutes, run_cap):
    return {
        "version": 1, "id": "forestRoad", "name": "Forest Road", "layout": "ForestRoad", "material": "Timber",
        "targetMinutes": target_minutes, "runCapSeconds": run_cap, "difficulties": DIFFICULTIES,
        "crowd": {"regenShare": 0.077, "maxAlive": 40, "burst": 8, "burstSpacing": 3.5,
                  "clearBonus": {"cash": 0, "materials": 0, "share": 0.1}, "rewards": REWARDS},
        "stages": [
            {"kind": "travel", "name": "Follow the road"},
            {"kind": "camp", "zone": "C", "name": "The Chief's Clearing", "targetWaveSeconds": 34, "breatherSeconds": 3,
             "maxAlive": c_waves["maxAlive"], "waves": c_waves["waves"]},
        ],
        "camps": camps,
    }


def residents(spec):
    return [{"spot": sid, "units": [u(n) for n in units]} for sid, units in spec]


# The boss room's waves, both designs: L1's wave of 35, a second wave of 33 from the Chief's tent,
# then the Colossus at the same spot as L1 (14 studs east of the centre), Valor 10 (fixed). The
# waves cost the cap nothing beyond the room's maxAlive: they come out as the residents fall.
C_WAVES = {
    "maxAlive": 42,
    "waves": [
        {"groups": [{"kind": "fodder", "count": 16}, {"kind": "brute", "count": 2},
                    {"kind": "armoured", "count": 2, "minDifficulty": "hard"}, {"kind": "fodder", "count": 16},
                    {"kind": "brute", "count": 1}]},
        {"groups": [{"kind": "fodder", "count": 14}, {"kind": "slinger", "count": 2}, {"kind": "brute", "count": 3},
                    {"kind": "fodder", "count": 14}]},
        {"groups": [], "boss": {"kind": "colossus", "at": [14, 0], "valor": 10}},
    ],
}

# Who lives where, both designs (the spots differ by layout; the ids are shared, so one level
# file's residents fit either layout). Normal 30 / 46 / 36 = 112; Hard and Brutal 36 / 50 / 38 =
# 124 (Hard adds 12 units; the cap, not the wish, sets that number).
RES_A = [
    ("fireW", [("fodder", 5), ("slinger", 2), ("slinger", 1, "hard")]),
    ("fireN", [("fodder", 6), ("slinger", 1), ("armoured", 1, "hard")]),
    ("watch", [("fodder", 6), ("slinger", 2), ("marksman", 1, "hard"), ("armoured", 1, "hard")]),
    ("loop", [("fodder", 6), ("slinger", 2), ("slinger", 1, "hard"), ("armoured", 1, "hard")]),
]
RES_B = [
    ("fire1", [("fodder", 4), ("slinger", 1), ("brute", 2), ("armoured", 1, "hard")]),
    ("fire2", [("fodder", 4), ("slinger", 2), ("brute", 1), ("marksman", 1, "hard")]),
    ("loop", [("fodder", 4), ("brute", 3), ("slinger", 1)]),
    ("fire3", [("fodder", 3), ("slinger", 1), ("lobber", 1), ("brute", 3), ("marksman", 1, "hard")]),
    ("eastWatch", [("brute", 4), ("armoured", 2), ("slinger", 1), ("lobber", 1)]),
    ("eastFire", [("fodder", 4), ("slinger", 1), ("brute", 3), ("armoured", 1, "hard")]),
]
RES_C = [
    ("gate", [("fodder", 6), ("brute", 3)]),
    ("chiefFire", [("brute", 3), ("fodder", 4), ("armoured", 2)]),
    ("north", [("fodder", 4), ("brute", 2), ("slinger", 2), ("armoured", 1, "hard")]),
    ("south", [("fodder", 4), ("brute", 2), ("slinger", 2), ("lobber", 2), ("armoured", 1, "hard")]),
]
TENT_A = {"every": 6, "units": [{"kind": "fodder", "count": 4}, {"kind": "slinger", "count": 2},
                                 {"kind": "brute", "count": 2}]}
TENT_B = {"every": 6, "units": [{"kind": "fodder", "count": 2}, {"kind": "slinger", "count": 2},
                                 {"kind": "brute", "count": 4}]}


def level_camps():
    return [
        {"id": "A", "name": "Pickets", "residents": residents(RES_A), "tent": TENT_A},
        {"id": "B", "name": "Main Camp", "residents": residents(RES_B), "tent": TENT_B},
        {"id": "C", "name": "The Chief's Clearing", "residents": residents(RES_C)},
    ]


# ---------------------------------------------------------------------------------------------
# Design 1 (recommended): "the winding road". West to east, the road zigzags between three
# camps at one height band (0, then 8, then 12), every camp crossed west to east along its
# NORTH side; the camp sprawls south of the road. The sneak path is the fence line: a careful
# player hugs the inside of the north fence, out of every resting eye's sight.
# ---------------------------------------------------------------------------------------------


def winding():
    blocks = [
        road("Trailhead", -482, -458, -12, 12, 0),
        {"name": "TrailSign", "look": "sign", "x": -472, "y": 3, "z": -9, "sx": 1, "sy": 6, "sz": 6, "collide": False,
         "text": "FOREST ROAD"},
        road("Road1", -458, -436, -8, 8, 0),
        # the gap: 12 studs, -436 to -424
        road("Road2", -424, -340, -8, 8, 0),
        {"name": "Creek", "look": "water", "x": -400, "y": -3, "z": 15, "sx": 20, "sy": 4, "sz": 90},
        {"name": "Pond", "look": "water", "x": -400, "y": -3, "z": 82, "sx": 52, "sy": 4, "sz": 44},
        road("ShrineSignPad", -390, -380, 8, 18, 0),
        road("Road3", -356, -340, -52, 8, 0),
        road("Road4", -356, -302, -52, -36, 0),
        road("Road5", -302, -264, -52, -36, 8, deep=12),
        {"name": "LookoutLedge", "look": "ground", "x": -283, "y": 15, "z": -59, "sx": 24, "sy": 38, "sz": 14},
        road("LookoutSignPad", -306, -296, -62, -52, 8, deep=12),
    ]
    a = Camp("A", -221.5, -16, 85, 85, 8)   # x -264..-179, z -58.5..26.5; the road at v -28 (z -44)
    b = Camp("B", 0.5, 2, 141, 133, 8)      # x -70..71, z -64.5..68.5; the road at v -46 (z -44)
    c = Camp("C", 313.5, -44, 115, 115, 12)  # x 256..371, z -101.5..13.5; the road at v 0 (z -44)
    blocks += [
        road("RoadAB1", -179, -122, -52, -36, 8),
        road("RoadAB2", -138, -122, -52, 8, 8),
        road("RoadAB3", -138, -100, -8, 8, 8),
        road("RoadAB4", -116, -100, -52, 8, 8),
        road("RoadAB5", -116, -70, -52, -36, 8),
        road("RoadBC1", 71, 128, -52, -36, 8),
        road("CacheSpur", 94, 106, -36, -10, 8),
        road("CacheSignPad", 106, 114, -34, -26, 8),
        road("RoadBC2", 112, 128, -52, 8, 8),
        road("RoadBC3", 112, 198, -8, 8, 8),
        road("RoadBC4", 182, 198, -52, 8, 8),
        road("RoadBC5", 198, 230, -52, -36, 8),
        road("RoadBC6", 230, 256, -52, -36, 12, deep=12),
        road("TrailEnd", 371, 387, -52, -36, 12),
    ]
    secrets = [
        {"id": "lookout", "needs": "doubleJump", "x": -283, "y": 36, "z": -59, "sx": 6, "sy": 4, "sz": 6,
         "sign": {"x": -301, "y": 8, "z": -57, "text": "LOOKOUT - needs DOUBLE JUMP"}},
        {"id": "cache", "needs": "fire", "x": 100, "y": 13, "z": -4, "sx": 12, "sy": 10, "sz": 12,
         "sign": {"x": 110, "y": 8, "z": -30, "text": "RAIDERS' CACHE - needs FIRE"}},
        {"id": "shrine", "needs": "ice", "x": -400, "y": 0.5, "z": 82, "sx": 12, "sy": 3, "sz": 12,
         "sign": {"x": -385, "y": 0, "z": 13, "text": "ISLAND SHRINE - needs ICE"}},
    ]

    # Camp A, the Pickets (85 x 85). The road crosses its north side at v -28; the fence line
    # (sneak) is v -38.5. Two wake clusters: the road fires (fireW, fireN) and, in the south-east
    # by the tent, the watch and the patrol. A fire's wake reaches 32 studs, so a wake at the
    # road wakes the road fires only; the watch's reaches 60 and pulls in whatever is left.
    camp_a = a.body(
        "Pickets",
        gates=[{"side": "west", "at": -28, "width": 16}, {"side": "east", "at": -28, "width": 16}],
        entry=a.p(-36.5, -28), exit=a.p(36.5, -28), checkpoint={"x": -150, "z": -44},
        spawns=[a.p(-30, 30), a.p(30, 30), a.p(0, 36), a.p(-34, 10)],
        obstacles=[a.cover(-14, 22, 6, 6), a.cover(12, 2, 6, 6), a.cover(-36, 32, 6, 6)],
        spots=[
            a.fire("fireW", -30, 2, 5),
            a.fire("fireN", -8, -10, 5.5),
            a.guard("watch", [(x, 37) for x in range(3, 40, 4)], 0),
            a.patrol("loop", [(30, 6), (38, 6), (38, 28), (30, 28)]),
        ],
        tent=a.tent(20, 22),
    )
    # Camp B, the Main Camp (141 x 133). The road along its north side at v -46; the fence line
    # at v -62.5. Three wake clusters: the road fires (west), the patrol and fire3 (south-west),
    # the east watch and its fire, with the tent (east).
    camp_b = b.body(
        "Main Camp",
        gates=[{"side": "west", "at": -46, "width": 16}, {"side": "east", "at": -46, "width": 16}],
        entry=b.p(-64.5, -46), exit=b.p(64.5, -46), checkpoint={"x": 110, "z": -44},
        spawns=[b.p(-50, 50), b.p(50, 50), b.p(0, 60), b.p(-60, 0)],
        obstacles=[b.cover(-36, 2, 10, 8), b.cover(20, 4, 8, 8), b.cover(-30, 20, 8, 8), b.cover(28, 52, 8, 8),
                   b.cover(-60, 22, 8, 8)],
        spots=[
            b.fire("fire1", -50, -26, 6.5),
            b.fire("fire2", -22, -25, 6.5),
            b.patrol("loop", [(-40, 34), (-12, 34), (-12, 58), (-40, 58)]),
            b.fire("fire3", 0, 50, 7.5),
            b.guard("eastWatch", [(64, v) for v in range(-8, 28, 5)], 90),
            b.fire("eastFire", 44, 22, 7.5),
        ],
        tent=b.tent(50, 46),
    )
    camp_c = c.body(
        "The Chief's Clearing", locks=True,
        gates=[{"side": "west", "at": 0, "width": 16}, {"side": "east", "at": 0, "width": 16}],
        entry=c.p(-51.5, 0), exit=c.p(51.5, 0), checkpoint=c.p(53.5, -11),
        spawns=[c.p(-10, -50), c.p(-10, 50), c.p(36, -40), c.p(36, 40), c.p(46, 20)],
        obstacles=[c.cover(30, -30, 18, 12), c.cover(-24, 34, 12, 8)],
        spots=[
            c.guard("gate", [(-38, -10), (-38, 10), (-34, -16), (-34, 16), (-34, -6), (-34, 6), (-30, -12), (-30, 12),
                             (-30, 0)], 90),
            c.fire("chiefFire", 20, 34, 7.5),
            c.guard("north", c.row(-16, -44, 5, 0, 9), 180),
            c.guard("south", c.row(-6, 50, 5, 0, 11), 0),
        ],
        tent=c.tent(40, 44, 14, 12, 10),
    )
    route = [
        {"x": -470, "y": 0, "z": 0}, {"x": -436, "y": 0, "z": 0}, {"x": -424, "y": 0, "z": 0, "via": "gap"},
        {"x": -348, "y": 0, "z": 0}, {"x": -348, "y": 0, "z": -44}, {"x": -303, "y": 0, "z": -44},
        {"x": -301, "y": 8, "z": -44, "via": "climb"},
        dict(camp_a["entry"], y=8), dict(camp_a["exit"], y=8, via="camp"),
        {"x": -130, "y": 8, "z": -44}, {"x": -130, "y": 8, "z": 0}, {"x": -108, "y": 8, "z": 0},
        {"x": -108, "y": 8, "z": -44},
        dict(camp_b["entry"], y=8), dict(camp_b["exit"], y=8, via="camp"),
        {"x": 120, "y": 8, "z": -44}, {"x": 120, "y": 8, "z": 0}, {"x": 190, "y": 8, "z": 0}, {"x": 190, "y": 8, "z": -44},
        {"x": 229, "y": 8, "z": -44}, {"x": 231, "y": 12, "z": -44, "via": "climb"},
        dict(camp_c["entry"], y=12), dict(camp_c["exit"], y=12, via="camp"),
    ]
    # The sneak path: the road, but inside A and B along the north fence (v -38.5 and v -62.5).
    # It ends on the road before the boss room's gate (the room's residents are held).
    sneak = [
        {"x": -470, "z": 0}, {"x": -436, "z": 0}, {"x": -424, "z": 0}, {"x": -348, "z": 0}, {"x": -348, "z": -44},
        {"x": -264, "z": -44}, a.p(-41.5, -35), a.p(-38, -38.5), a.p(38, -38.5), a.p(41.5, -35), {"x": -130, "z": -44},
        {"x": -130, "z": 0}, {"x": -108, "z": 0}, {"x": -108, "z": -44}, {"x": -70, "z": -44},
        b.p(-69.5, -53), b.p(-64, -62.5), b.p(64, -62.5), b.p(69.5, -53), {"x": 120, "z": -44}, {"x": 120, "z": 0},
        {"x": 190, "z": 0}, {"x": 190, "z": -44}, {"x": 250, "z": -44},
    ]
    layout = {"version": 1, "start": {"x": -470, "y": 0, "z": 0}, "killY": -13,
              "barrier": {"height": 80, "thickness": 8}, "camps": [camp_a, camp_b, camp_c], "blocks": blocks,
              "secrets": secrets, "route": route, "sneak": sneak}
    return layout


# ---------------------------------------------------------------------------------------------
# Design 2 (alternative): "the switchback". The road climbs a hillside in three terraces
# (0 -> 8 -> 18 -> 28) and folds back on itself: east along the valley through camp A, a
# hairpin up and WEST to camp B on the middle terrace, a second hairpin up and EAST along the
# high road, which overlooks B's north side, to camp C at the top. A and B are crossed
# diagonally (in by one side, out by the next). The sneak path past B is a goat track OUTSIDE
# its fence (side ground is allowed beside an open camp); past A it is the inside of the fence.
# ---------------------------------------------------------------------------------------------


def switchback():
    blocks = [
        road("Trailhead", -482, -458, 178, 202, 0),
        {"name": "TrailSign", "look": "sign", "x": -472, "y": 3, "z": 181, "sx": 1, "sy": 6, "sz": 6, "collide": False,
         "text": "FOREST ROAD"},
        road("Road1", -458, -436, 182, 198, 0),
        road("Road2", -424, -352, 182, 198, 0),
        {"name": "Creek", "look": "water", "x": -400, "y": -3, "z": 205, "sx": 20, "sy": 4, "sz": 90},
        {"name": "Pond", "look": "water", "x": -400, "y": -3, "z": 272, "sx": 52, "sy": 4, "sz": 44},
        road("ShrineSignPad", -390, -380, 198, 208, 0),
        road("Road4", -352, -87.5, 182, 198, 8, deep=12),
        {"name": "LookoutLedge", "look": "ground", "x": -326, "y": 15, "z": 205, "sx": 24, "sy": 38, "sz": 14},
        road("LookoutSignPad", -351, -341, 198, 208, 8, deep=12),
    ]
    a = Camp("A", -45, 190, 85, 85, 8)      # x -87.5..-2.5, z 147.5..232.5; in west at v 0, out north at u 0
    b = Camp("B", -200, 100, 141, 133, 18)  # x -270.5..-129.5, z 33.5..166.5; in east at v 12, out north at u -40
    c = Camp("C", 60, 2, 115, 115, 28)      # x 2.5..117.5, z -55.5..59.5; in west at v 0, out east
    blocks += [
        road("RoadA1", -53, -37, 120, 147.5, 8),
        road("RoadA2", -53, -37, 104, 120, 18, deep=14),
        road("RoadA3", -129.5, -53, 104, 120, 18),
        road("GoatTrack1", -128, -118, 24, 104, 18),
        road("GoatTrack2", -248, -128, 24, 32, 18),
        road("RoadB1", -248, -232, 10, 33.5, 18),
        road("RoadB2", -248, -232, -6, 10, 28, deep=14),
        road("HighRoad", -232, 2.5, -6, 10, 28),
        road("Overlook", -200, -176, 10, 18, 28),
        road("CacheSpur", -110, -98, -32, -6, 28),
        road("CacheSignPad", -96, -88, -16, -8, 28),
        road("TrailEnd", 117.5, 133.5, -6, 10, 28),
    ]
    secrets = [
        {"id": "lookout", "needs": "doubleJump", "x": -326, "y": 36, "z": 205, "sx": 6, "sy": 4, "sz": 6,
         "sign": {"x": -346, "y": 8, "z": 203, "text": "LOOKOUT - needs DOUBLE JUMP"}},
        {"id": "cache", "needs": "fire", "x": -104, "y": 33, "z": -38, "sx": 12, "sy": 10, "sz": 12,
         "sign": {"x": -92, "y": 28, "z": -12, "text": "RAIDERS' CACHE - needs FIRE"}},
        {"id": "shrine", "needs": "ice", "x": -400, "y": 0.5, "z": 272, "sx": 12, "sy": 3, "sz": 12,
         "sign": {"x": -385, "y": 0, "z": 203, "text": "ISLAND SHRINE - needs ICE"}},
    ]
    # A, in the valley: in from the west at v 0, out by the north gate at u 0. The fence line runs
    # inside the west and north fences. Two wake clusters: the road fires (west), the watch and
    # the patrol by the tent (south-east).
    camp_a = a.body(
        "Pickets",
        gates=[{"side": "west", "at": 0, "width": 16}, {"side": "north", "at": 0, "width": 16}],
        entry=a.p(-36.5, 0), exit=a.p(0, -36.5), checkpoint={"x": -45, "z": 128},
        spawns=[a.p(30, 30), a.p(-30, 34), a.p(34, -10), a.p(0, 36)],
        obstacles=[a.cover(0, 14, 6, 6), a.cover(-32, 36, 6, 6), a.cover(14, -24, 6, 6)],
        spots=[
            a.fire("fireW", -16, 26, 5),
            a.fire("fireN", -12, -4, 5.5),
            a.guard("watch", [(x, v) for v in (33, 37) for x in range(22, 39, 4)], 0),
            a.patrol("loop", [(28, 0), (38, 0), (38, 22), (28, 22)]),
        ],
        tent=a.tent(14, 20),
    )
    # B, on the middle terrace: in by the east gate at v 12, out by the north gate at u -40. The
    # goat track runs outside its east and north fences. Three wake clusters: the road fires
    # (north-east), the patrol and fire3 (south-west), the watch and its fire (south-east).
    camp_b = b.body(
        "Main Camp",
        gates=[{"side": "east", "at": 12, "width": 16}, {"side": "north", "at": -40, "width": 16}],
        entry=b.p(64.5, 12), exit=b.p(-40, -60.5), checkpoint={"x": -240, "z": 20},
        spawns=[b.p(-50, 60), b.p(50, 60), b.p(0, 60), b.p(-60, -10)],
        obstacles=[b.cover(-16, 46, 10, 8), b.cover(10, -4, 10, 8), b.cover(50, 40, 8, 8), b.cover(-50, -14, 8, 8)],
        spots=[
            b.fire("fire1", 36, -30, 6.5),
            b.fire("fire2", 16, -45, 6.5),
            b.patrol("loop", [(-60, 40), (-30, 40), (-30, 60), (-60, 60)]),
            b.fire("fire3", -50, 20, 7.5),
            b.guard("eastWatch", [(x, 50) for x in range(31, 67, 5)], 0),
            b.fire("eastFire", 28, 24, 7.5),
        ],
        tent=b.tent(0, 56),
    )
    camp_c = c.body(
        "The Chief's Clearing", locks=True,
        gates=[{"side": "west", "at": 0, "width": 16}, {"side": "east", "at": 0, "width": 16}],
        entry=c.p(-51.5, 0), exit=c.p(51.5, 0), checkpoint=c.p(53.5, -11),
        spawns=[c.p(-10, -50), c.p(-10, 50), c.p(36, -40), c.p(36, 40), c.p(46, 20)],
        obstacles=[c.cover(30, -30, 18, 12), c.cover(-24, 34, 12, 8)],
        spots=[
            c.guard("gate", [(-38, -10), (-38, 10), (-34, -16), (-34, 16), (-34, -6), (-34, 6), (-30, -12), (-30, 12),
                             (-30, 0)], 90),
            c.fire("chiefFire", 20, 34, 7.5),
            c.guard("north", c.row(-16, -44, 5, 0, 9), 180),
            c.guard("south", c.row(-6, 50, 5, 0, 11), 0),
        ],
        tent=c.tent(40, 44, 14, 12, 10),
    )
    route = [
        {"x": -470, "y": 0, "z": 190}, {"x": -436, "y": 0, "z": 190}, {"x": -424, "y": 0, "z": 190, "via": "gap"},
        {"x": -353, "y": 0, "z": 190}, {"x": -351, "y": 8, "z": 190, "via": "climb"},
        dict(camp_a["entry"], y=8), dict(camp_a["exit"], y=8, via="camp"),
        {"x": -45, "y": 8, "z": 121}, {"x": -45, "y": 18, "z": 119, "via": "climb"}, {"x": -45, "y": 18, "z": 112},
        dict(camp_b["entry"], y=18), dict(camp_b["exit"], y=18, via="camp"),
        {"x": -240, "y": 18, "z": 11}, {"x": -240, "y": 28, "z": 9, "via": "climb"}, {"x": -240, "y": 28, "z": 2},
        dict(camp_c["entry"], y=28), dict(camp_c["exit"], y=28, via="camp"),
    ]
    sneak = [
        {"x": -470, "z": 190}, {"x": -436, "z": 190}, {"x": -424, "z": 190}, {"x": -87.5, "z": 190},
        a.p(-38.5, -4), a.p(-38.5, -38.5), a.p(-4, -38.5), {"x": -45, "z": 147.5}, {"x": -45, "z": 112},
        {"x": -123, "z": 112}, {"x": -123, "z": 28}, {"x": -240, "z": 28}, {"x": -240, "z": 2}, {"x": -6, "z": 2},
    ]
    layout = {"version": 1, "start": {"x": -470, "y": 0, "z": 190}, "killY": -13,
              "barrier": {"height": 80, "thickness": 8}, "camps": [camp_a, camp_b, camp_c], "blocks": blocks,
              "secrets": secrets, "route": route, "sneak": sneak}
    return layout


def write(name, layout, level):
    for suffix, data in (("layout", layout), ("level", level)):
        path = HERE / f"{name}.{suffix}.json"
        path.write_text(json.dumps(data, indent="\t") + "\n", encoding="utf-8", newline="\n")
        print(f"wrote {path.name}")


def main():
    write("winding", winding(), level_file(level_camps(), C_WAVES, 9, 1500))
    write("switchback", switchback(), level_file(level_camps(), C_WAVES, 9, 1500))


if __name__ == "__main__":
    main()
