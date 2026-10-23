#!/usr/bin/env python
"""The raider pose mirror (docs/prompts/l4-w2-contract.md 3.4, L4W2-9): the client's pure
`src/combat/client/Controllers/Raiders/RaiderPose.luau`, run under the official `luau` interpreter,
against `tools/testfit/raiderpose.py` (the maths the strips, the posed reach and the head rule are
judged with) on the same inputs: every number within 1e-6, every flag and phase name equal.

    py tools/check_raider_mirror.py --luau <luau.exe>             # the mirror; exit 1 on a difference
    py tools/check_raider_mirror.py --luau <luau.exe> --mutants   # also: every mutant below must FAIL it
    py tools/check_raider_mirror.py --module <copy of RaiderPose.luau>   # judge another copy
    py tools/check_raider_mirror.py --only whirl --mutants        # the mutants whose label holds it

The inputs, read from the configs the game reads (Config/RaiderModels.json, ProvingGrounds.json's
crowd, Theme.luau's and CrowdRenderer.luau's constants through raiderpose.Constants):
  * Rig:    every pose raiderpose.py --check samples (sweep_poses: 113 a kind, 387 the Chief), each
            also turned to two other headings, and leaning sideways, airborne and seated variants;
            all five pieces' transforms, the anchor, where the head is drawn, the drop, the feet;
  * Threat: every attack of every crowd kind (the placeholders draw from it too) x windup, attack,
            recover, a spent phase and "none" x 11 ages (and past the recover) x enraged or not, the
            walk's stride, an arc's unwind and an enraged boss's held recover;
  * Arm:    every model kind's every attack shape on that grid, its idle, walking and seated arm,
            with no threat at all, and a `line` with and without its lock;
  * Walk:   walk steps over the phase, amplitude, travel, frame time, speed, distance and radius;
  * Paint:  per model kind its idle, windup, blow and spent looks, flashed or not, enraged or not.

Mutants (the tools/crowd_harness/mirror_mutants.py pattern): each is one exact-text change to a copy
of RaiderPose.luau, and the mirror must FAIL on it. A mutant whose text no longer occurs exactly once
is STALE and counts as missed: re-aim it, never delete it to go green. The contract's four (a lean
sign flipped, the head clamp removed, the snap skipped, the leg shade dropped) and one per rule the
W2 port added (raiders.md risk 2: the throw path, the whirl, steady, the aim by the lock, the
short-way blend) and the walk's.

The interpreter is tools/bin/luau.exe (tools/check_mirror.py fetches it); a git worktree falls back
to its main checkout's. Pure stdlib; nothing in the repo is written.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "testfit"))
import raiderpose as rp  # noqa: E402

MODULE = ROOT / "src" / "combat" / "client" / "Controllers" / "Raiders" / "RaiderPose.luau"
MODELS = ROOT / "src" / "shared" / "Config" / "RaiderModels.json"
TOLERANCE = 1e-6
PIECE_KEYS = ("head", "torso", "arm", "legL", "legR")
# Rig's extra headings and lean variants: the sweep's poses all face yaw 0.
YAWS = (0.0, 0.9, -2.3)
# Lean's flat lean vectors (x, z), K4.
LEANS = ((0.0, 0.0), (0.3, -0.2), (-0.5, 0.1), (0.07, 0.4), (1.0, 0.0), (0.0, -1.0))

# (label, old text, new text). Each must turn the mirror red.
MUTANTS = (
    ("Threat: the windup's lean sign flipped", "local back = -c.COMBAT_RANGE_TELL_LEAN_BACK * build",
     "local back = c.COMBAT_RANGE_TELL_LEAN_BACK * build"),
    ("Rig: the head clamp removed", "local drop = clamp(wanted, -keep, keep)", "local drop = wanted"),
    ("Arm: the snap skipped", "if SNAP_SHAPES[shape] and threat.snap > 0 then", "if false then"),
    ("Paint: the leg shade dropped", "setLerp(leg, base, c.LEG_SHADE, c.LEG_SHADE_SHARE)", "setRgb(leg, base)"),
    ("Arm: the whirl dropped", "local whirl = s.whirl", "local whirl = nil"),
    ("Arm: steady ignored", "local steady = if s.steady then pose.lean else 0", "local steady = 0"),
    ("Arm: the throw path gone (strike -> follow)", "elseif THROW_SHAPES[shape] then", "elseif false then"),
    ("Arm: a line aimed by the body's build, not its lock", "\t\t\tand attack.windup > attack.lock\n", "\t\t\tand false\n"),
    ("Arm: blends the long way round", "return a + ((b - a + math.pi) % TWO_PI - math.pi) * t", "return a + (b - a) * t"),
    ("Walk: the ease at half its rate", "amp += gap * (1 - math.exp(-dt * consts.COMBAT_RAIDER_WALK_EASE_RATE))",
     "amp += gap * (1 - math.exp(-dt * consts.COMBAT_RAIDER_WALK_EASE_RATE * 0.5))"),
    ("Walk: walks past the near radius", "if distance <= nearStuds and dt > 0 and full > 0 then",
     "if dt > 0 and full > 0 then"),
    ("Rig: the seat's drop gone", "local seatDrop = model.height * consts.restDrop * seat", "local seatDrop = 0"),
    ("Rig: the leading foot never steps", "local step = pose.thrust * rig.stepShare", "local step = 0"),
    ("Paint: the skin takes the full tint", "setLerp(o.skin, skinBase, threat.tintColor, threat.tint * 0.5)",
     "setLerp(o.skin, skinBase, threat.tintColor, threat.tint)"),
    # The L4 W2 fix round (ui-engineer B's K1 and K4): the strike window's slide, the anchor, the lean split.
    ("Rig: the strike window's slide gone", "local slide = math.max(pose.thrust, 0) * rig.slideShare", "local slide = 0"),
    ("Rig: the trailing foot slides with the body", 'if lead == "legR" then step else -slide,',
     'if lead == "legR" then step else 0,'),
    ("Rig: the slide runs backward", "local sx, sz = -sinYaw * slide, -cosYaw * slide",
     "local sx, sz = sinYaw * slide, cosYaw * slide"),
    ("Rig: the coil slides back too", "local slide = math.max(pose.thrust, 0) * rig.slideShare",
     "local slide = pose.thrust * rig.slideShare"),
    ("Lean: along and across swapped", "return leanX * -s + leanZ * -c, leanX * c + leanZ * -s",
     "return leanX * c + leanZ * -s, leanX * -s + leanZ * -c"),
    ("Rig: the anchor rides the drop", "write(o.anchor, 0, o.anchorY, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)",
     "write(o.anchor, 0, o.anchorY - drop, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)"),
)


# ---------------------------------------------------------------------------------------------
# The inputs and what raiderpose.py makes of them
# ---------------------------------------------------------------------------------------------


def load_models(path: Path = MODELS) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def rgb(value) -> list:
    return [float(v) for v in value]


def consts_table(consts: rp.Constants) -> dict:
    """raiderpose's constants as RaiderPose's Consts: every value, colours as {r, g, b}."""
    return {name: (rgb(value) if isinstance(value, tuple) else float(value)) for name, value in consts.values.items()}


def pose_table(pose: rp.Pose) -> dict:
    return {"yaw": pose.yaw, "lean": pose.lean, "leanSide": pose.lean_side, "twist": pose.twist, "squash": pose.squash,
            "thrust": pose.thrust, "seat": pose.seat, "airborne": pose.airborne, "walkPhase": pose.walk_phase,
            "walkAmp": pose.walk_amp, "armPitch": pose.arm[0], "armYaw": pose.arm[1], "armRoll": pose.arm[2]}


def threat_table(t: rp.Threat) -> dict:
    """A Python Threat as RaiderPose's ThreatOut (what Arm and Paint read)."""
    return {"phase": t.phase, "age": t.age, "lean": t.lean, "thrust": t.thrust, "twist": t.twist, "squash": t.squash,
            "tint": t.tint, "tintColor": rgb(t.tint_colour), "glow": t.glow, "visorHot": t.visor_hot, "charge": t.charge,
            "build": t.build, "snap": t.snap, "u": t.u, "sweep": t.sweep, "settle": t.settle, "spent": t.spent,
            "slump": t.slump}


THREAT_FIELDS = ("phase", "age", "lean", "thrust", "twist", "squash", "tint", "tintColor.r", "tintColor.g", "tintColor.b",
                 "glow", "visorHot", "charge", "build", "snap", "u", "sweep", "settle", "spent", "slump")


def threat_values(t: rp.Threat) -> list:
    return [t.phase, t.age, t.lean, t.thrust, t.twist, t.squash, t.tint, *t.tint_colour, t.glow, t.visor_hot, t.charge,
            t.build, t.snap, t.u, t.sweep, t.settle, t.spent, t.slump]


def cframe_numbers(cf: rp.CFrame) -> list:
    return [cf.p[0], cf.p[1], cf.p[2], *cf.r[0], *cf.r[1], *cf.r[2]]


RIG_FIELDS = tuple(f"{piece}[{i}]" for piece in PIECE_KEYS for i in range(1, 13)) + (
    "anchorY", "headX", "headY", "headZ", "headOffset", "drop", "footL", "footR", "slide") + tuple(
    f"anchor[{i}]" for i in range(1, 13))


def rig_values(r: rp.Rigged) -> list:
    out = []
    for piece in PIECE_KEYS:
        out += cframe_numbers(r.pieces[piece])
    return out + [r.anchor[1], *r.head_world, r.head_offset, r.drop, r.foot_float["legL"], r.foot_float["legR"],
                  r.slide, *cframe_numbers(r.anchor_frame())]


PAINT_FIELDS = ("cloth.r", "cloth.g", "cloth.b", "clothNeon", "clothLeg.r", "clothLeg.g", "clothLeg.b", "clothLegNeon",
                "skin.r", "skin.g", "skin.b", "skinNeon", "glow.r", "glow.g", "glow.b", "glowNeon")


def paint_values(p: dict) -> list:
    out = []
    for role in ("cloth", "clothLeg", "skin", "glow"):
        colour, material = p[role]
        out += [*colour, material == "Neon"]
    return out


def threat_input(kind: dict, atk: rp.Attack, phase: str, age: float, server_now: float, stride: float, unwind: float,
                 held: float) -> dict:
    return {"shape": atk.shape, "phase": phase, "age": age, "windup": atk.windup, "strike": atk.strike,
            "recover": atk.recover, "reach": atk.reach, "arc": atk.arc, "lock": atk.lock, "radius": kind["radius"],
            "serverNow": server_now, "stride": stride, "unwind": unwind, "held": held}


def build_cases(consts: rp.Constants, kinds: dict, threat_cfg: dict, models: dict) -> tuple[list, list, dict]:
    """(cases for the Luau, what raiderpose.py answers for each, counts by function)."""
    rig_numbers = models["rig"]
    cases, expected = [], []
    counts = {"rig": 0, "threat": 0, "arm": 0, "walk": 0, "paint": 0, "lean": 0}

    def add(case, values, fields, label):
        cases.append(case)
        expected.append((label, fields, values))
        counts[case["f"]] += 1

    # Lean (K4): the flat lean vector split along the facing and across it, at every heading the rig
    # cases use and a few more.
    for yaw in YAWS + (math.pi / 2, -math.pi, 3.4):
        for x, z in LEANS:
            add({"f": "lean", "yaw": yaw, "x": x, "z": z}, list(rp.lean_parts(yaw, x, z)), ("along", "across"),
                f"Lean yaw {yaw:g} ({x:g}, {z:g})")
    # Threat: every attack of every crowd kind (models and placeholders alike).
    for kind_id in sorted(kinds):
        kind = kinds[kind_id]
        for index in range(1, len(kind.get("attacks") or []) + 1):
            for enraged in (False, True):
                atk = rp.attack_of(kind, index, threat_cfg, consts, enraged)
                spans = (("windup", atk.windup), ("attack", atk.strike), ("recover", atk.recover))
                for phase, length in spans:
                    ages = [length * step / 10 for step in range(11)] + ([length + 0.25] if phase == "recover" else [])
                    for age in ages:
                        variants = [(age * 7.3, 0.0, 0.0, 0.0)]
                        if phase == "recover":
                            variants += [(age * 3.1, 0.5, 0.6, 0.0), (age * 1.7, 1.0, -0.4, 0.3)]
                        for server_now, stride, unwind, held in variants:
                            t = rp.threat_pose(consts, kind, atk, phase, age, server_now=server_now, enraged=enraged,
                                               stride=stride, unwind=unwind, held=held)
                            add({"f": "threat", "input": threat_input(kind, atk, phase, age, server_now, stride, unwind,
                                                                      held)},
                                threat_values(t), THREAT_FIELDS,
                                f"Threat {kind_id} attack {index} ({atk.shape}) {phase} {age:.3f}"
                                f"{' enraged' if enraged else ''} stride {stride:g} unwind {unwind:g} held {held:g}")
                for phase in ("none", "spent"):
                    t = rp.threat_pose(consts, kind, atk, phase, 0.2)
                    add({"f": "threat", "input": threat_input(kind, atk, phase, 0.2, 0.0, 0.0, 0.0, 0.0)},
                        threat_values(t), THREAT_FIELDS, f"Threat {kind_id} attack {index} ({atk.shape}) {phase}")

    for kind_id in sorted(models["kinds"]):
        model = models["kinds"][kind_id]
        kind = kinds[kind_id]
        first = (kind.get("attacks") or [{}])[0].get("shape", "")
        # Rig: every pose --check samples, turned and varied.
        for number, (name, pose, _t, _shape) in enumerate(rp.sweep_poses(kind, threat_cfg, consts, model, rig_numbers)):
            for yaw in YAWS:
                variants = [dict(yaw=yaw)]
                if yaw == YAWS[1]:
                    variants += [dict(yaw=yaw, lean_side=0.3), dict(yaw=yaw, airborne=True),
                                 dict(yaw=yaw, seat=min(pose.seat + 0.4, 1.0))]
                for change in variants:
                    p = rp.Pose(**{**pose.__dict__, **change})
                    r = rp.rig(model, rig_numbers, consts, p)
                    add({"f": "rig", "kind": kind_id, "pose": pose_table(p)}, rig_values(r), RIG_FIELDS,
                        f"Rig {kind_id} pose {number} ({name}) {change}")
        # Arm: every attack shape of the kind on the Threat grid, idle, walking, seated, no threat.
        for index in range(1, len(kind.get("attacks") or []) + 1):
            for enraged in (False, True):
                atk = rp.attack_of(kind, index, threat_cfg, consts, enraged)
                locks = [atk] + ([rp.Attack(atk.shape, atk.windup, atk.recover, atk.strike, atk.reach, atk.arc, 0.0)]
                                 if atk.lock > 0 else [])
                for use in locks:
                    for phase, length in (("windup", use.windup), ("attack", use.strike), ("recover", use.recover)):
                        for step in range(11):
                            age = length * step / 10
                            for stride, seat in ((0.0, 0.0), (1.0, 0.0), (0.0, 0.6)):
                                t = rp.threat_pose(consts, kind, use, phase, age, enraged=enraged, stride=stride, unwind=0.6,
                                                   server_now=age * 7.3)
                                pose = rp.Pose(lean=t.lean, twist=t.twist, squash=rp.drawn_squash(t.squash), thrust=t.thrust,
                                               walk_phase=1.3 + age, walk_amp=stride, seat=seat)
                                arm = rp.arm_channel(model, use.shape, t, pose, rig_numbers, use)
                                add({"f": "arm", "kind": kind_id, "shape": use.shape, "threat": threat_table(t),
                                     "pose": pose_table(pose), "attack": {"windup": use.windup, "lock": use.lock}},
                                    list(arm), ("pitch", "yaw", "roll"),
                                    f"Arm {kind_id} attack {index} ({use.shape}, lock {use.lock:g}) {phase} {age:.3f}"
                                    f"{' enraged' if enraged else ''} stride {stride:g} seat {seat:g}")
        for walk_phase in (0.0, 0.7, 2.4, 4.7):
            for amp in (0.0, 0.5, 1.0):
                for seat in (0.0, 0.5, 1.0):
                    for lean in (0.0, -0.3):
                        pose = rp.Pose(walk_phase=walk_phase, walk_amp=amp, seat=seat, lean=lean)
                        arm = rp.arm_channel(model, first, rp.Threat(), pose, rig_numbers)
                        add({"f": "arm", "kind": kind_id, "shape": first, "threat": threat_table(rp.Threat()),
                             "pose": pose_table(pose), "attack": None}, list(arm), ("pitch", "yaw", "roll"),
                            f"Arm {kind_id} idle ({first}) walk {walk_phase:g} x {amp:g} seat {seat:g} lean {lean:g}")
                        if walk_phase == 0.7:
                            add({"f": "arm", "kind": kind_id, "shape": first, "threat": None, "pose": pose_table(pose),
                                 "attack": None}, list(arm), ("pitch", "yaw", "roll"),
                                f"Arm {kind_id} no threat ({first}) walk {walk_phase:g} x {amp:g} seat {seat:g} lean {lean:g}")
        # Walk: steps over the grid.
        near = rig_numbers["walkNearStuds"]
        for phase in (0.0, 1.3, 6.2):
            for amp in (0.0, 0.004, 0.5, 1.0):
                for travel in (0.0, 0.2, 1.5, 30.0):
                    for dt in (0.0, 1 / 60, 0.1):
                        for distance, radius in ((10.0, near), (near, near), (near + 1, near), (59.0, 60.0), (61.0, 60.0)):
                            out = rp.walk_step(phase, amp, travel, dt, kind["speed"], model["legLength"], distance, radius,
                                               rig_numbers, consts)
                            add({"f": "walk", "kind": kind_id, "args": [phase, amp, travel, dt, kind["speed"],
                                                                         model["legLength"], distance, radius]},
                                [("angle", out[0]), out[1]], ("phase", "amp"),
                                f"Walk {kind_id} phase {phase:g} amp {amp:g} travel {travel:g} dt {dt:.4f} distance "
                                f"{distance:g} near {radius:g}")
        # Paint: idle, three windup heats, the blow, spent; flashed or not, enraged or not.
        atk = rp.attack_of(kind, 1, threat_cfg, consts)
        looks = [("idle", rp.Threat())]
        looks += [(f"windup {share:g}", rp.threat_pose(consts, kind, atk, "windup", atk.windup * share)) for share in (0.3, 0.6, 1.0)]
        looks += [("blow", rp.threat_pose(consts, kind, atk, "attack", 0.0))]
        looks += [("spent", rp.threat_pose(consts, kind, atk, "recover", max(atk.recover - 0.3, 0.0)))]
        skin = rp.rgb01(model["skin"])
        for look, t in looks:
            for flash in (False, True):
                for enraged in (False, True):
                    p = rp.paint(consts, kind, skin, t, flash=flash, enraged=enraged)
                    add({"f": "paint", "color": list(kind["color"]), "skin": list(model["skin"]), "threat": threat_table(t),
                         "flash": flash, "enraged": enraged}, paint_values(p), PAINT_FIELDS,
                        f"Paint {kind_id} {look}{' flash' if flash else ''}{' enraged' if enraged else ''}")
    return cases, expected, counts


# ---------------------------------------------------------------------------------------------
# The Luau side
# ---------------------------------------------------------------------------------------------


def to_luau(value) -> str:
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{json.dumps(key)}] = {to_luau(item)}" for key, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(to_luau(item) for item in value) + "}"
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and not math.isfinite(value):
        return "(0/0)" if math.isnan(value) else ("math.huge" if value > 0 else "-math.huge")
    return json.dumps(value)


DRIVER = r'''
local function fmt(v: any): string
	local t = type(v)
	if t == "number" then
		return string.format("%.17g", v)
	elseif t == "boolean" then
		return if v then "true" else "false"
	end
	return tostring(v)
end

local lines = {}
local function emit(i: number, values: { any })
	local parts = table.create(#values)
	for k, v in values do
		parts[k] = fmt(v)
	end
	table.insert(lines, tostring(i) .. " " .. table.concat(parts, " "))
end

local threatOut = RaiderPose.NewThreatOut()
local rigOut = RaiderPose.NewRigOut()
local paintOut = RaiderPose.NewPaintOut()
local CONSTS = DATA.consts
local RIG = DATA.rig
local MODELS = DATA.models

for i, c in CASES do
	local ok, err = pcall(function()
		if c.f == "threat" then
			local o = RaiderPose.Threat(c.input, CONSTS, threatOut)
			emit(i, { o.phase, o.age, o.lean, o.thrust, o.twist, o.squash, o.tint, o.tintColor[1], o.tintColor[2],
				o.tintColor[3], o.glow, o.visorHot, o.charge, o.build, o.snap, o.u, o.sweep, o.settle, o.spent, o.slump })
		elseif c.f == "rig" then
			local o = RaiderPose.Rig(MODELS[c.kind], RIG, CONSTS, c.pose, rigOut)
			local values = {}
			for _, piece in { "head", "torso", "arm", "legL", "legR" } do
				for k = 1, 12 do
					table.insert(values, o[piece][k])
				end
			end
			for _, v in { o.anchorY, o.headX, o.headY, o.headZ, o.headOffset, o.drop, o.footL, o.footR, o.slide } do
				table.insert(values, v)
			end
			for k = 1, 12 do
				table.insert(values, o.anchor[k])
			end
			emit(i, values)
		elseif c.f == "lean" then
			local a, b = RaiderPose.Lean(c.yaw, c.x, c.z)
			emit(i, { a, b })
		elseif c.f == "arm" then
			local pitch, yaw, roll = RaiderPose.Arm(MODELS[c.kind], c.shape, c.threat, c.pose, RIG, c.attack)
			emit(i, { pitch, yaw, roll })
		elseif c.f == "walk" then
			local a = c.args
			local phase, amp = RaiderPose.Walk(a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], RIG, CONSTS)
			emit(i, { phase, amp })
		elseif c.f == "paint" then
			local o = RaiderPose.Paint(c.color, c.skin, c.threat, c.flash, c.enraged, CONSTS, paintOut)
			emit(i, { o.cloth[1], o.cloth[2], o.cloth[3], o.clothNeon, o.clothLeg[1], o.clothLeg[2], o.clothLeg[3],
				o.clothLegNeon, o.skin[1], o.skin[2], o.skin[3], o.skinNeon, o.glow[1], o.glow[2], o.glow[3], o.glowNeon })
		else
			error("unknown case " .. tostring(c.f))
		end
	end)
	if not ok then
		table.insert(lines, tostring(i) .. " THREW " .. tostring(err))
	end
end
table.insert(lines, "DONE")
print(table.concat(lines, "\n"))
'''


def bundle(module_text: str, consts: dict, models: dict, cases: list) -> str:
    """One chunk: the data, the module as a function (its export types made local, as the crowd
    harness wraps modules), the driver. Cases go in one statement each, so no table constructor holds
    thousands of entries."""
    text = re.sub(r"(?m)^export type", "type", module_text)
    parts = [f"local DATA: any = {{consts = {to_luau(consts)}, rig = {to_luau(models['rig'])}, "
             f"models = {to_luau(models['kinds'])}}}\n",
             "local CASES: { any } = {}\n",
             "local RaiderPose = (function()\n", text, "\nend)()\n"]
    chunk = []
    for index, case in enumerate(cases, start=1):
        chunk.append(f"CASES[{index}] = {to_luau(case)}\n")
    # Fill CASES inside functions of at most 2000 statements each (a function's constants stay few).
    for start in range(0, len(chunk), 2000):
        parts.append("do (function()\n" + "".join(chunk[start:start + 2000]) + "end)() end\n")
    parts.append(DRIVER)
    return "".join(parts)


def run_luau(luau: Path, text: str) -> tuple[dict, str]:
    """({case index: [tokens]}, an error text or "")."""
    with tempfile.TemporaryDirectory() as scratch:
        path = Path(scratch) / "raider_mirror_bundle.luau"
        path.write_text(text, encoding="utf-8", newline="\n")
        try:
            done = subprocess.run([str(luau), str(path)], capture_output=True, text=True, timeout=600)
        except subprocess.TimeoutExpired:
            return {}, "the Luau did not finish in 600 s"
    lines = done.stdout.splitlines()
    if done.returncode != 0 or "DONE" not in lines:
        tail = "\n".join(lines[-3:] + done.stderr.splitlines()[-6:])
        return {}, f"the Luau run did not finish (exit {done.returncode}): {tail}"
    answers = {}
    for line in lines:
        if line == "DONE":
            continue
        head, _, rest = line.partition(" ")
        if head.isdigit():
            answers[int(head)] = rest
    return answers, ""


def parse(token: str):
    if token in ("true", "false"):
        return token == "true"
    try:
        return float(token)
    except ValueError:
        return token


def same(python, luau) -> bool:
    if isinstance(python, tuple) and python and python[0] == "angle":  # a phase: equal modulo 2 pi
        if not isinstance(luau, float) or not math.isfinite(luau):
            return False
        d = (luau - python[1] + math.pi) % (2 * math.pi) - math.pi
        return abs(d) <= TOLERANCE
    if isinstance(python, bool):
        return luau is python
    if isinstance(python, (int, float)):
        return isinstance(luau, float) and not isinstance(luau, bool) and math.isfinite(luau) and abs(luau - python) <= TOLERANCE
    return luau == python


def compare(expected: list, answers: dict) -> tuple[list, float]:
    """(differences, the worst numeric difference seen)."""
    found, worst = [], 0.0
    for index, (label, fields, values) in enumerate(expected, start=1):
        text = answers.get(index)
        if text is None:
            found.append(f"{label}: no answer from the Luau")
            continue
        if text.startswith("THREW "):
            found.append(f"{label}: the Luau threw: {text[6:]}")
            continue
        tokens = [parse(t) for t in text.split(" ")]
        if len(tokens) != len(values):
            found.append(f"{label}: the Luau answered {len(tokens)} values, raiderpose.py {len(values)}")
            continue
        bad = []
        for field, py, lu in zip(fields, values, tokens):
            if not same(py, lu):
                bad.append(f"{field} Luau {lu} vs Python {py[1] if isinstance(py, tuple) else py}")
            elif isinstance(py, (int, float)) and not isinstance(py, bool):
                worst = max(worst, abs(lu - py))
            elif isinstance(py, tuple):
                worst = max(worst, abs((lu - py[1] + math.pi) % (2 * math.pi) - math.pi))
        if bad:
            found.append(f"{label}: " + "; ".join(bad[:4]) + (f" (+{len(bad) - 4} more)" if len(bad) > 4 else ""))
    return found, worst


def find_luau(given):
    if given:
        return Path(given)
    name = "luau.exe" if sys.platform.startswith("win") else "luau"
    here = ROOT / "tools" / "bin" / name
    if here.exists():
        return here
    link = ROOT / ".git"
    if link.is_file():  # a worktree: `gitdir: <main checkout>/.git/worktrees/<name>`
        found = re.match(r"gitdir:\s*(.+)", link.read_text(encoding="utf-8").strip())
        if found:
            main = Path(found.group(1)).parents[2] / "tools" / "bin" / name
            if main.exists():
                return main
    raise SystemExit(f"check_raider_mirror: no Luau interpreter at {here}. Run `py tools/check_mirror.py` once (it "
                     f"fetches one), or pass --luau <path>.")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--luau", default=None, help="the Luau interpreter (default: tools/bin/luau.exe)")
    parser.add_argument("--module", default=None, help="a copy of RaiderPose.luau to judge instead of the repo's")
    parser.add_argument("--mutants", action="store_true", help="after the mirror, every mutant must turn it red")
    parser.add_argument("--only", default=None, help="with --mutants: only the mutants whose label holds this text")
    args = parser.parse_args(argv)
    luau = find_luau(args.luau)
    consts = rp.Constants()
    kinds, threat_cfg, _notes = rp.load_kinds()
    models = load_models()
    missing = sorted(set(models["kinds"]) - set(kinds))
    if missing:
        print(f"CHECK: FAIL -- RaiderModels.json names kinds ProvingGrounds.json lacks: {', '.join(missing)}")
        return 1
    cases, expected, counts = build_cases(consts, kinds, threat_cfg, models)
    module = Path(args.module) if args.module else MODULE
    module_text = module.read_text(encoding="utf-8")
    table = consts_table(consts)
    answers, error = run_luau(luau, bundle(module_text, table, models, cases))
    found, worst = ([error], 0.0) if error else compare(expected, answers)
    print(f"check_raider_mirror: {module.relative_to(ROOT).as_posix() if module.is_relative_to(ROOT) else module} under {luau.name} "
          f"against tools/testfit/raiderpose.py: {len(cases)} cases ("
          + ", ".join(f"{name} {n}" for name, n in counts.items()) + f"), {len(models['kinds'])} model kinds, "
          f"{len(kinds)} crowd kinds; worst difference {worst:.2e} (tolerance {TOLERANCE:g})")
    for line in found[:20]:
        print(f"  DIFF  {line}")
    if len(found) > 20:
        print(f"  ... and {len(found) - 20} more")
    failed = bool(found)
    if args.mutants and not failed:
        caught = 0
        chosen = [m for m in MUTANTS if not args.only or args.only in m[0]]
        for label, old, new in chosen:
            if module_text.count(old) != 1:
                print(f"  STALE  {label}: the text {old!r} occurs {module_text.count(old)} times (re-aim it)")
                continue
            got, err = run_luau(luau, bundle(module_text.replace(old, new), table, models, cases))
            diffs, _w = ([err], 0.0) if err else compare(expected, got)
            if diffs:
                caught += 1
                print(f"  ok     {label}: red ({len(diffs)} case(s); e.g. {diffs[0][:140]})")
            else:
                print(f"  MISSED {label}: the mirror stays green")
        print(f"MUTANTS: {'PASS' if caught == len(chosen) else 'FAIL'} ({caught} of {len(chosen)} red)")
        failed = caught != len(chosen)
    print(f"CHECK: {'FAIL' if found else 'PASS'}" + (f" -- {len(found)} difference(s)" if found else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
