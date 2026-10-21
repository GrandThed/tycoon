"""How a raider model is posed (L4): CrowdRenderer's pose maths in Python, plus the model rig.

Pure stdlib, so it runs under `py` (the check below) and inside Blender (raiderview.py imports it).

    py tools/testfit/raiderpose.py --check            # the head rule over every pose of every model
    py tools/testfit/raiderpose.py --frames fodder    # print the strip's frames for one kind

Two layers, kept apart on purpose:

1. **The client's own maths, ported** (`threat_pose`, `state_lean`, `paint`): the lean, thrust,
   twist and squash CrowdRenderer.threatPose draws for each attack phase, the seat, and the tints
   (the windup's heat in 8 steps, the neon blow, the white flash, the dull spent body, the enraged
   base). Every number is read from the Luau itself (Theme.luau and CrowdRenderer.luau constants,
   ProvingGrounds.json kinds), so a strip can never pose with a number the game does not use.
   Any constant that goes missing is an error, never a silent default.

2. **The model rig** (`rig`), the proposal for W2 (docs/prompts/l4-w1-reports/raiders.md). A model
   body is five rigid pieces (head, torso, weapon arm, left leg, right leg), each a stage of the
   kind's prop, posed from the same inputs today's figure takes, by these rules:
     * the head rule: **the head is placed at the scored head** (HitShapes: the sphere at the feet +
       height - headRadius, lowered by the seat once the server's seated hit shapes land) and moves
       from it only vertically, by the body's drop, clamped to `headKeep` x headRadius (0.4 < 0.5);
       it nods and turns about its own centre, which moves nothing;
     * every lean (a windup's, a blow's, a stagger, a reel, a flinch) bends the body **below the
       neck**: the torso turns about the neck joint, so the hips swing the other way and the head
       stays; the body drops by the hips' rise so the feet reach the floor;
     * the legs hang from the hips and are aimed back at the floor spot under each hip (a small
       two-angle aim, no knees), plus the walk swing; seated they lie forward;
     * the twist (an arc's coil and sweep, the call's shake, the reel's sway) turns the upper body
       and arm; the legs keep the heading;
     * the lunge's thrust never moves the head: the leading foot steps forward with it and the arm's
       strike pose carries the reach;
     * squash (the slam, the spent slump, a boss's breath) is the same clamped drop; rigid pieces
       never scale;
     * reactions that follow a landed hit (knockback, launch, the death fling and topple, a summoned
       body rising) keep today's whole-body transform on the rest pose: they are exempt.
   The weapon arm has its own channel: keyed poses per attack shape (carry, coil, strike, follow,
   slump, seat) blended on threatPose's own clock, plus the walk swing.

Frames: glTF / Roblox body frame, feet at the origin, front -Z, up +Y, right +X. Rotations follow
Roblox: `euler_yxz(rx, ry, rz)` = CFrame.fromEulerAnglesYXZ(rx, ry, rz) = Ry(ry) * Rx(rx) * Rz(rz);
+pitch (rx) swings a hanging arm forward, +roll (rz) swings a right arm out to the side, +yaw (ry)
turns toward -X (left).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from dataclasses import dataclass, field

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
THEME_PATH = os.path.join(REPO_ROOT, "src", "client", "UI", "Theme.luau")
RENDERER_PATH = os.path.join(REPO_ROOT, "src", "combat", "client", "Controllers", "CrowdRenderer.luau")
PROVING_PATH = os.path.join(REPO_ROOT, "src", "shared", "Config", "ProvingGrounds.json")
MODELS_PATH = os.path.join(REPO_ROOT, "tools", "assets", "out", "RaiderModels.json")

Vec = tuple[float, float, float]
Rgb = tuple[float, float, float]  # 0..1, as Color3 stores it

# --- the Luau constants this module mirrors -------------------------------------------------------

THEME_NAMES = (
    "COMBAT_RANGE_TELL_COLOR", "COMBAT_RANGE_TELL_SPENT_COLOR", "COMBAT_RANGE_TELL_HEAT_SHARE",
    "COMBAT_RANGE_TELL_SPENT_SHARE", "COMBAT_RANGE_TELL_TINT_STEPS", "COMBAT_RANGE_TELL_COIL_SHARE",
    "COMBAT_RANGE_TELL_LEAN_BACK", "COMBAT_RANGE_TELL_LEAN_FORWARD", "COMBAT_RANGE_TELL_PULL_BACK",
    "COMBAT_RANGE_TELL_LUNGE_SHARE", "COMBAT_RANGE_TELL_ARC_TWIST_SHARE", "COMBAT_RANGE_TELL_ARC_SWEEP_SHARE",
    "COMBAT_RANGE_TELL_SPENT_LEAN", "COMBAT_RANGE_TELL_SPENT_SQUASH", "COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS",
    "COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS", "COMBAT_RANGE_REEL_LEAN", "COMBAT_RANGE_REEL_SWAY",
    "COMBAT_RANGE_REEL_SWAY_HZ", "COMBAT_RANGE_REEL_SQUASH", "COMBAT_RANGE_RING_SLAM_RISE",
    "COMBAT_RANGE_RING_SLAM_SQUASH", "COMBAT_RANGE_RING_SLAM_LEAN", "COMBAT_RANGE_CALL_LEAN",
    "COMBAT_RANGE_CALL_SHAKE", "COMBAT_RANGE_CALL_SHAKE_HZ", "COMBAT_RANGE_CALL_STRETCH",
    "COMBAT_RANGE_BOSS_BREATH", "COMBAT_RANGE_BOSS_BREATH_HZ", "COMBAT_RANGE_ENRAGE_BREATH",
    "COMBAT_RANGE_ENRAGE_BREATH_HZ", "COMBAT_RANGE_ENRAGE_COLOR", "COMBAT_RANGE_ENRAGE_SHARE",
    "COMBAT_RANGE_ENRAGE_GLOW_COLOR", "COMBAT_REST_DROP", "COMBAT_RISE_BLEND_SECONDS", "COMBAT_REST_HIP_SHARE",
)
RENDERER_NAMES = (
    "STAGGER_LEAN", "WINDUP_LEAN", "AIRBORNE_LEAN", "AIRBORNE_TUCK", "HEAD_TINT", "HEAD_TINT_SHARE",
    "LEG_SHADE", "LEG_SHADE_SHARE", "VISOR_COLOR", "VISOR_HOT_COLOR", "FLASH_COLOR",
)

_NUMBER = r"-?\d+(?:\.\d+)?"
_VALUE = re.compile(
    rf"^\s*(?:local\s+)?([A-Z][A-Z0-9_]*)\s*=\s*(Color3\.fromRGB\(\s*({_NUMBER})\s*,\s*({_NUMBER})\s*,\s*({_NUMBER})\s*\)"
    rf"|Color3\.new\(\s*({_NUMBER})\s*,\s*({_NUMBER})\s*,\s*({_NUMBER})\s*\)|({_NUMBER}))\s*,?\s*(?:--.*)?$"
)


def _read_constants(path: str, names: tuple[str, ...]) -> dict:
    found: dict[str, object] = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            m = _VALUE.match(line)
            if not m or m.group(1) not in names or m.group(1) in found:
                continue
            if m.group(3) is not None:
                found[m.group(1)] = tuple(float(m.group(i)) / 255.0 for i in (3, 4, 5))
            elif m.group(6) is not None:
                found[m.group(1)] = tuple(float(m.group(i)) for i in (6, 7, 8))
            else:
                found[m.group(1)] = float(m.group(9))
    missing = [n for n in names if n not in found]
    if missing:
        raise ValueError(f"{os.path.relpath(path, REPO_ROOT)} no longer defines {', '.join(missing)}: re-port raiderpose.py")
    return found


class Constants:
    """Theme.luau and CrowdRenderer.luau's numbers, by their Luau names."""

    def __init__(self):
        self.values = {**_read_constants(THEME_PATH, THEME_NAMES), **_read_constants(RENDERER_PATH, RENDERER_NAMES)}

    def __getattr__(self, name: str):
        try:
            return self.values[name]
        except KeyError:
            raise AttributeError(name) from None


# --- kinds ------------------------------------------------------------------------------------

# The Camp Chief is a new crowd kind (study report section 2; the economy-designer adds it to
# ProvingGrounds.json). Until it exists the strips pose it with the study's proposal: the
# Colossus's body and attacks with the war-club sweep in place of the barrage. Read the file
# first; this is only the stand-in, and the report says which one a strip used.
CHIEF_STAND_IN_SWEEP = {"shape": "arc", "reach": 14, "range": 16, "arcDegrees": 150, "height": 6,
                        "windup": 1.0, "recover": 1.6}


def load_kinds() -> tuple[dict, dict, dict]:
    """(kinds, crowd.threat, notes): ProvingGrounds.json's crowd kinds, the chief included."""
    with open(PROVING_PATH, "r", encoding="utf-8") as fh:
        crowd = json.load(fh)["crowd"]
    kinds = dict(crowd["kinds"])
    notes = {}
    if "chief" not in kinds and "colossus" in kinds:
        chief = json.loads(json.dumps(kinds["colossus"]))
        chief["name"] = "Camp Chief"
        chief["attacks"] = [a for a in chief["attacks"] if a.get("shape") != "lob"] + [dict(CHIEF_STAND_IN_SWEEP)]
        kinds["chief"] = chief
        notes["chief"] = "stand-in: the colossus's numbers with the study's sweep (no `chief` in ProvingGrounds.json yet)"
    return kinds, crowd.get("threat", {}), notes


def load_models(path: str = MODELS_PATH) -> dict:
    if not os.path.isfile(path):
        raise FileNotFoundError(f"{os.path.relpath(path, REPO_ROOT)} is missing: run the generator (tools/assets/raider_kit.py)")
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


# --- small maths: Roblox CFrames ----------------------------------------------------------------


def v_add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_mul(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s, a[2] * s)


def v_dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def v_len(a: Vec) -> float:
    return math.sqrt(v_dot(a, a))


def luau_round(x: float) -> float:
    """Luau's math.round: half away from zero (Python's round() goes to even)."""
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def v_lerp(a, b, t: float):
    return tuple(lerp(x, y, t) for x, y in zip(a, b))


def smoothstep(u: float) -> float:
    return u * u * (3 - 2 * u)


def look_of(yaw: float) -> Vec:
    return (-math.sin(yaw), 0.0, -math.cos(yaw))


@dataclass(frozen=True)
class CFrame:
    """A rotation (rows) and a position, composed like Roblox's: (a * b) * p = a * (b * p)."""

    r: tuple[Vec, Vec, Vec] = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))
    p: Vec = (0.0, 0.0, 0.0)

    def rotate(self, v: Vec) -> Vec:
        return (v_dot(self.r[0], v), v_dot(self.r[1], v), v_dot(self.r[2], v))

    def point(self, v: Vec) -> Vec:
        return v_add(self.rotate(v), self.p)

    def __mul__(self, other: "CFrame") -> "CFrame":
        cols = [(other.r[0][j], other.r[1][j], other.r[2][j]) for j in range(3)]
        rot = tuple(tuple(v_dot(self.r[i], cols[j]) for j in range(3)) for i in range(3))
        return CFrame(rot, self.point(other.p))  # type: ignore[arg-type]

    def inverse(self) -> "CFrame":
        rt = tuple(tuple(self.r[j][i] for j in range(3)) for i in range(3))
        inv = CFrame(rt, (0.0, 0.0, 0.0))  # type: ignore[arg-type]
        return CFrame(inv.r, v_mul(inv.rotate(self.p), -1.0))

    def matrix(self) -> list[list[float]]:
        """4x4 row-major, for Blender (after the axis change)."""
        return [list(self.r[0]) + [self.p[0]], list(self.r[1]) + [self.p[1]], list(self.r[2]) + [self.p[2]], [0.0, 0.0, 0.0, 1.0]]


def cf_at(p: Vec) -> CFrame:
    return CFrame(p=(float(p[0]), float(p[1]), float(p[2])))


def rx(a: float) -> CFrame:
    c, s = math.cos(a), math.sin(a)
    return CFrame(((1.0, 0.0, 0.0), (0.0, c, -s), (0.0, s, c)))


def ry(a: float) -> CFrame:
    c, s = math.cos(a), math.sin(a)
    return CFrame(((c, 0.0, s), (0.0, 1.0, 0.0), (-s, 0.0, c)))


def rz(a: float) -> CFrame:
    c, s = math.cos(a), math.sin(a)
    return CFrame(((c, -s, 0.0), (s, c, 0.0), (0.0, 0.0, 1.0)))


def euler_yxz(pitch: float, yaw: float, roll: float) -> CFrame:
    """CFrame.fromEulerAnglesYXZ(pitch, yaw, roll) = Ry(yaw) * Rx(pitch) * Rz(roll)."""
    return ry(yaw) * rx(pitch) * rz(roll)


def axis_angle(axis: Vec, angle: float) -> CFrame:
    """CFrame.fromAxisAngle (Rodrigues, right-handed); `axis` must be a unit vector."""
    x, y, z = axis
    c, s = math.cos(angle), math.sin(angle)
    t = 1 - c
    return CFrame((
        (t * x * x + c, t * x * y - s * z, t * x * z + s * y),
        (t * x * y + s * z, t * y * y + c, t * y * z - s * x),
        (t * x * z - s * y, t * y * z + s * x, t * z * z + c),
    ))


def lean_rotation(lean: Vec) -> CFrame:
    """rootFrame's lean: up x lean tips the top of the body toward `lean` by |lean| radians."""
    angle = v_len(lean)
    if angle <= 1e-4:
        return CFrame()
    axis = v_mul(v_cross((0.0, 1.0, 0.0), lean), 1.0 / angle)
    n = v_len(axis)
    if n <= 1e-9:
        return CFrame()
    return axis_angle(v_mul(axis, 1.0 / n), angle)


# --- layer 1: CrowdRenderer's pose maths, ported -----------------------------------------------


@dataclass
class Attack:
    """An attack as CrowdRenderer reads it for drawing (readThreat, the lines that set threat*)."""

    shape: str
    windup: float
    recover: float
    strike: float
    reach: float  # threatReach: the lunge's jab, an arc's radius, a lane's or line's length...
    arc: float  # threatArc, radians (arcs only)


def attack_of(kind: dict, index: int, threat: dict, consts: Constants, enraged: bool = False) -> Attack:
    a = kind["attacks"][index - 1]
    shape = a["shape"]
    enrage = kind.get("enrage") if enraged else None
    windup = max(a.get("windup", 0), 0) * (max(enrage.get("windupScale", 1), 0) if enrage else 1)
    recover = max(a.get("recover", 0), 0) * (max(enrage.get("recoverScale", 1), 0) if enrage else 1)
    speed = a.get("speed", 0) or 0
    rng = a.get("range", a.get("reach", 0)) or 0
    strike = rng / speed if shape == "lane" and speed > 0 else max(threat.get("strikeSeconds", 0), 0)
    arc = 0.0
    if shape == "lunge":
        reach = max(rng - kind["radius"], 0) * consts.COMBAT_RANGE_TELL_LUNGE_SHARE
    elif shape == "arc":
        reach = rng
        arc = math.radians(min(max(a.get("arcDegrees", 360), 0), 360))
    elif shape in ("lane", "line"):
        reach = rng
    elif shape in ("ring", "summon"):
        reach = max(a.get("radius", 0) or 0, 0)
    else:
        reach = 0.0
    return Attack(shape, windup, recover, strike, reach, arc)


@dataclass
class Threat:
    """threatPose's four outputs plus what it paints and the clocks the arm channel reads."""

    lean: float = 0.0  # radians, + forward
    thrust: float = 0.0  # studs along the facing
    twist: float = 0.0  # radians added to the drawn yaw
    squash: float = 1.0
    tint: float = 0.0  # share (already stepped)
    tint_colour: Rgb = (1.0, 1.0, 1.0)
    glow: bool = False
    visor_hot: bool = False
    charge: float = 0.0  # a lit cue's charge (Cues.Paint): u * u through a windup, 0 otherwise
    # For the arm channel: the phase and its clocks.
    phase: str = "none"
    build: float = 0.0
    snap: float = 0.0
    u: float = 0.0
    sweep: float = 0.0
    settle: float = 0.0
    spent: float = 0.0
    slump: float = 0.0


def stepped(consts: Constants, share: float) -> float:
    steps = consts.COMBAT_RANGE_TELL_TINT_STEPS
    return luau_round(min(max(share, 0.0), 1.0) * steps) / steps


def threat_pose(consts: Constants, kind: dict, attack: Attack, phase: str, age: float, *,
                server_now: float = 0.0, enraged: bool = False, stride: float = 0.0,
                unwind: float = 0.0, held: float = 0.0) -> Threat:
    """CrowdRenderer.threatPose for one phase at `age` seconds into it (plus setThreat's visor).

    unwind = angleDelta(yaw, lastYaw) for an arc's recover (how far its body was turned at the
    blow's end); held = interval + lag for an enraged boss's chained recover (0 in the strips)."""
    c = consts
    out = Threat(phase=phase)
    twist_most = attack.arc * 0.5 * c.COMBAT_RANGE_TELL_ARC_TWIST_SHARE
    shape = attack.shape
    if phase == "windup":
        u = min(age / attack.windup, 1.0) if attack.windup > 0 else 1.0
        coil = c.COMBAT_RANGE_TELL_COIL_SHARE
        build = min(u / coil, 1.0) ** 2
        out.u, out.build = u, build
        out.charge = u * u
        out.tint, out.tint_colour, out.glow = stepped(c, build * c.COMBAT_RANGE_TELL_HEAT_SHARE), c.COMBAT_RANGE_TELL_COLOR, False
        out.visor_hot = True
        back = -c.COMBAT_RANGE_TELL_LEAN_BACK * build
        if shape == "lunge":
            pull = -kind["radius"] * c.COMBAT_RANGE_TELL_PULL_BACK * build
            if u <= coil:
                out.lean, out.thrust = back, pull
                return out
            snap = ((u - coil) / (1 - coil)) ** 2
            out.snap = snap
            out.lean = back + (c.COMBAT_RANGE_TELL_LEAN_FORWARD - back) * snap
            out.thrust = pull + (attack.reach - pull) * snap
            return out
        if shape == "ring":
            rise = 1 + c.COMBAT_RANGE_RING_SLAM_RISE * build
            if u <= coil:
                out.lean, out.squash = back, rise
                return out
            snap = ((u - coil) / (1 - coil)) ** 2
            out.snap = snap
            out.lean = back + (c.COMBAT_RANGE_RING_SLAM_LEAN - back) * snap
            out.squash = rise + (c.COMBAT_RANGE_RING_SLAM_SQUASH - rise) * snap
            return out
        if shape == "summon":
            out.lean = -c.COMBAT_RANGE_CALL_LEAN * build
            out.twist = c.COMBAT_RANGE_CALL_SHAKE * build * math.sin(server_now * 2 * math.pi * c.COMBAT_RANGE_CALL_SHAKE_HZ)
            out.squash = 1 + c.COMBAT_RANGE_CALL_STRETCH * build
            return out
        out.lean, out.twist = back, -twist_most * build
        return out
    if phase == "attack":
        u = min(age / attack.strike, 1.0) if attack.strike > 0 else 1.0
        left = 1 - u
        out.u = u
        out.tint, out.tint_colour, out.glow = 1.0, c.COMBAT_RANGE_TELL_COLOR, True
        out.visor_hot = True
        forward = c.COMBAT_RANGE_TELL_LEAN_FORWARD * left
        if shape == "lunge":
            out.lean, out.thrust = forward, attack.reach * left * left
            return out
        if shape == "lane":
            out.lean = c.COMBAT_RANGE_TELL_LEAN_FORWARD
            return out
        if shape == "ring":
            out.lean = c.COMBAT_RANGE_RING_SLAM_LEAN * left
            out.squash = 1 - (1 - c.COMBAT_RANGE_RING_SLAM_SQUASH) * left
            return out
        sweep = smoothstep(min(u / c.COMBAT_RANGE_TELL_ARC_SWEEP_SHARE, 1.0))
        out.sweep = sweep
        out.lean, out.twist = forward, twist_most * (2 * sweep - 1)
        return out
    if phase == "recover":
        if age >= attack.recover:
            out.phase = "none"
            return out
        settle = min(max(age - held, 0.0) / c.COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS, 1.0)
        wake = min((attack.recover - age) / c.COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS, 1.0)
        spent = min(settle, wake)
        out.settle, out.spent = settle, spent
        out.tint, out.tint_colour = stepped(c, spent * c.COMBAT_RANGE_TELL_SPENT_SHARE), c.COMBAT_RANGE_TELL_SPENT_COLOR
        out.twist = unwind * (1 - settle) if shape == "arc" else 0.0
        slump = spent * (1 - stride)
        out.slump = slump
        out.lean = c.COMBAT_RANGE_TELL_SPENT_LEAN * slump
        out.squash = 1 - (1 - c.COMBAT_RANGE_TELL_SPENT_SQUASH) * slump
        return out
    return out


def drawn_squash(squash: float) -> float:
    """stepAlive rounds the squash it draws to hundredths (math.round(slump * 100) / 100)."""
    return luau_round(squash * 100) / 100


def state_lean(consts: Constants, state: str) -> float:
    """stateLeanTarget as a signed lean along the facing (+ forward)."""
    if state == "stagger":
        return -consts.STAGGER_LEAN
    if state == "windup":
        return -consts.WINDUP_LEAN
    if state == "airborne":
        return -consts.AIRBORNE_LEAN
    return 0.0


def boss_breath(consts: Constants, server_now: float, enraged: bool) -> float:
    depth = consts.COMBAT_RANGE_ENRAGE_BREATH if enraged else consts.COMBAT_RANGE_BOSS_BREATH
    rate = consts.COMBAT_RANGE_ENRAGE_BREATH_HZ if enraged else consts.COMBAT_RANGE_BOSS_BREATH_HZ
    return luau_round((1 + depth * math.sin(server_now * 2 * math.pi * rate)) * 100) / 100


def c3_lerp(a: Rgb, b: Rgb, t: float) -> Rgb:
    """Color3:Lerp: straight on the stored components."""
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t))


def rgb01(values) -> Rgb:
    return (values[0] / 255.0, values[1] / 255.0, values[2] / 255.0)


def paint(consts: Constants, kind: dict, skin: Rgb, threat: Threat, *, flash: bool = False,
          enraged: bool = False) -> dict[str, tuple[Rgb, str]]:
    """What each painted role shows: role -> (colour 0..1, "SmoothPlastic" | "Neon").

    cloth = today's torso rule on the kind's colour, clothLeg = today's legs rule, skin = today's
    head rule (the tint half as far) on the kind's skin colour in place of the warm-yellow head,
    glow = today's visor rule, held lit (ember) for good once enraged. gear is never painted."""
    c = consts
    base = rgb01(kind["color"])
    skin_base = skin
    if enraged:
        base = c3_lerp(base, c.COMBAT_RANGE_ENRAGE_COLOR, c.COMBAT_RANGE_ENRAGE_SHARE)
        skin_base = c3_lerp(skin_base, c.COMBAT_RANGE_ENRAGE_COLOR, c.COMBAT_RANGE_ENRAGE_SHARE * 0.5)
    leg = c3_lerp(base, c.LEG_SHADE, c.LEG_SHADE_SHARE)
    material = "Neon" if flash or threat.glow else "SmoothPlastic"
    if flash:
        cloth = leg_c = skin_c = c.FLASH_COLOR
    elif threat.tint > 0:
        cloth = c3_lerp(base, threat.tint_colour, threat.tint)
        leg_c = c3_lerp(leg, threat.tint_colour, threat.tint)
        skin_c = c3_lerp(skin_base, threat.tint_colour, threat.tint * 0.5)
    else:
        cloth, leg_c, skin_c = base, leg, skin_base
    if enraged:
        glow = (c.COMBAT_RANGE_ENRAGE_GLOW_COLOR, "Neon")
    elif threat.visor_hot:
        glow = (c.VISOR_HOT_COLOR, "Neon")
    else:
        glow = (c.VISOR_COLOR, "SmoothPlastic")
    return {"cloth": (cloth, material), "clothLeg": (leg_c, material), "skin": (skin_c, material), "glow": glow}


# --- layer 2: the model rig (the proposal) -------------------------------------------------------

# Defaults written into RaiderModels.json `rig` by the generator; once that file exists this module
# reads the file's values, so an edit there is what the strips pose with.
RIG_DEFAULTS = {
    "headKeep": 0.4,  # most the head may move from the scored head, in head radii (the rule says 0.5)
    "headNod": 0.35,  # share of the lean the head tilts by, about its own centre
    "headTurn": 0.5,  # share of the twist the head turns by, about its own centre
    "legSwing": 0.42,  # radians each leg swings either way at a full stride
    "armSwing": 0.32,  # radians the weapon arm swings with the walk (x the kind's armSwingShare)
    "walkLean": 0.06,  # radians the upper body leans into a full stride (about the neck)
    "strideLegs": 2.4,  # one walk cycle covers this many leg lengths
    "walkFullShare": 0.5,  # the stride is full at this share of the kind's speed
    "walkNearStuds": 140,  # past this distance from the camera the walk cycle stops (a cost guard)
    "stepShare": 0.4,  # share of the lunge's thrust the leading foot steps forward (as far as it reaches)
    "seatLean": 0.12,  # radians a seated body leans forward
    "seatSplay": 0.14,  # radians each seated leg turns outward
    "airTuck": 0.5,  # radians the legs swing forward while airborne
}


@dataclass
class Pose:
    """Everything the rig takes for one frame (body frame: feet at the origin, heading `yaw`)."""

    yaw: float = 0.0
    lean: float = 0.0  # along the facing, + forward (the client hands a vector; strips lean along the facing)
    lean_side: float = 0.0  # across it, + toward the body's right (flinches, reels from the side)
    twist: float = 0.0
    squash: float = 1.0
    thrust: float = 0.0
    seat: float = 0.0  # 0..1, before the ease
    airborne: bool = False
    walk_phase: float = 0.0
    walk_amp: float = 0.0
    arm: tuple[float, float, float] = (0.0, 0.0, 0.0)  # pitch, yaw, roll of the weapon arm


@dataclass
class Rigged:
    """Each piece's transform (body frame -> world), and the head rule's numbers."""

    pieces: dict[str, CFrame] = field(default_factory=dict)
    head_world: Vec = (0.0, 0.0, 0.0)
    anchor: Vec = (0.0, 0.0, 0.0)  # the scored head's centre
    head_offset: float = 0.0  # studs
    drop: float = 0.0
    foot_float: dict[str, float] = field(default_factory=dict)


def rig(model: dict, rig_numbers: dict, consts: Constants, pose: Pose, *, seated_hit_shapes: bool = True) -> Rigged:
    """Place the five pieces for one pose. `model` is a RaiderModels.json kind entry.

    seated_hit_shapes: the server lowers a resting body's head sphere by the seat (the PLAN fix
    the study names, owners ui-engineer + luau-engineer A); the anchor follows it."""
    k = {**RIG_DEFAULTS, **(rig_numbers or {})}
    pts = model["points"]
    height, head_r = model["height"], model["headRadius"]
    head_c = tuple(pts["head"])
    neck = tuple(pts["neck"])
    hips = {"legL": tuple(pts["hipL"]), "legR": tuple(pts["hipR"])}
    shoulder = tuple(pts["shoulder"])
    leg_len = model["legLength"]
    torso_len = neck[1] - (hips["legL"][1] + hips["legR"][1]) / 2

    seat = smoothstep(min(max(pose.seat, 0.0), 1.0))
    seat_drop = height * consts.COMBAT_REST_DROP * seat
    walk = pose.walk_amp
    swing = k["legSwing"] * walk * math.sin(pose.walk_phase)
    facing = look_of(pose.yaw)
    side = (math.cos(pose.yaw), 0.0, -math.sin(pose.yaw))  # the body's right (+X at yaw 0)
    lean_f = pose.lean + k["walkLean"] * walk + k["seatLean"] * seat
    lean_vec = v_add(v_mul(facing, lean_f), v_mul(side, pose.lean_side))
    theta = v_len(lean_vec)

    # The drop: the hips' rise from bending about the neck, today's carried squash, the walk.
    d_lean = torso_len * (1 - math.cos(theta))
    d_squash = torso_len * (1 - pose.squash)
    d_walk = leg_len * (1 - math.cos(abs(swing))) * (1 - seat)
    wanted = d_lean + d_squash + d_walk
    keep = k["headKeep"] * head_r
    drop = min(max(wanted, -keep), keep)

    anchor_y = head_c[1] - (seat_drop if seated_hit_shapes else 0.0)
    anchor = (0.0, anchor_y, 0.0)
    out = Rigged(anchor=anchor, drop=drop)

    upper_yaw = pose.yaw + pose.twist
    r_lean = lean_rotation(lean_vec)
    r_upper = r_lean * ry(upper_yaw)
    head_world = (head_c[0], head_c[1] - seat_drop - drop, head_c[2])
    r_head = lean_rotation(v_mul(lean_vec, k["headNod"])) * ry(pose.yaw + pose.twist * k["headTurn"])
    out.pieces["head"] = cf_at(head_world) * r_head * cf_at(v_mul(head_c, -1.0))
    out.head_world = head_world
    out.head_offset = v_len(v_sub(head_world, anchor))

    neck_world = v_add(ry(upper_yaw).rotate((neck[0], 0.0, neck[2])), (0.0, neck[1] - seat_drop - drop, 0.0))
    torso = cf_at(neck_world) * r_upper * cf_at(v_mul(neck, -1.0))
    out.pieces["torso"] = torso
    pitch, yaw_a, roll = pose.arm
    out.pieces["arm"] = torso * cf_at(shoulder) * euler_yxz(pitch, yaw_a, roll) * cf_at(v_mul(shoulder, -1.0))

    legs_frame = ry(pose.yaw)
    for name, hip in hips.items():
        hip_world = torso.point(hip)
        local = legs_frame.inverse().rotate(hip_world)  # the hip in the legs' own frame
        sign = 1.0 if name == "legL" else -1.0
        step = 0.0
        if name == model.get("leadLeg", "legL"):
            step = pose.thrust * k["stepShare"]
        target = (hip[0], 0.0, hip[2] - step)  # the floor spot under the rest hip (+ the lunge's step)
        # A foot the leg cannot reach slides toward the spot under the hip until it can: feet stay on
        # the floor and slide under a bending body instead of hanging in the air.
        flat = (target[0] - local[0], target[2] - local[2])
        span = math.hypot(*flat)
        reach = math.sqrt(max(leg_len * leg_len - local[1] * local[1], 0.0))
        if span > reach and span > 1e-9:
            target = (local[0] + flat[0] * reach / span, 0.0, local[2] + flat[1] * reach / span)
        v = v_sub(target, local)
        n = v_len(v)
        vx, vz = (v[0] / n, v[2] / n) if n > 1e-9 else (0.0, 0.0)
        gamma = math.asin(min(max(vx, -1.0), 1.0))
        cg = math.cos(gamma)
        beta = math.asin(min(max(-vz / cg, -1.0), 1.0)) if cg > 1e-6 else 0.0
        beta += sign * swing
        if pose.airborne:
            beta += k["airTuck"]
        out.foot_float[name] = max(local[1] - leg_len * math.cos(gamma) * math.cos(beta), 0.0)
        if seat > 0:
            beta = lerp(beta, math.pi / 2, seat)
            gamma = lerp(gamma, -sign * k["seatSplay"], seat)
        r_leg = legs_frame * euler_yxz(beta, 0.0, gamma)
        out.pieces[name] = cf_at(hip_world) * r_leg * cf_at(v_mul(hip, -1.0))
    return out


# --- the weapon arm's channel ----------------------------------------------------------------------

SNAP_SHAPES = ("lunge", "ring")


def arm_channel(model: dict, shape: str, threat: Threat, pose: Pose, rig_numbers: dict) -> tuple[float, float, float]:
    """The weapon arm's pitch, yaw, roll for one frame: keyed poses blended on threatPose's clocks.

    Keys (RaiderModels.json `arm`): carry, seat, slump, and per shape coil / strike / follow.
    windup: carry -> coil with the build (and coil -> strike with the snap for a lunge or a slam);
    attack: an arc swings coil -> follow with the sweep, a lane holds its strike, the rest go
    strike -> follow; recover: from where the blow left it to the slump, waking to the carry."""
    k = {**RIG_DEFAULTS, **(rig_numbers or {})}
    keys = model["arm"]
    carry = keys["carry"]
    s = keys["shapes"].get(shape) or {}
    coil, strike, follow = s.get("coil", carry), s.get("strike", carry), s.get("follow", s.get("strike", carry))
    phase = threat.phase
    if phase == "windup":
        a = v_lerp(carry, coil, threat.build)
        if shape in SNAP_SHAPES and threat.snap > 0:
            a = v_lerp(coil, strike, threat.snap)
    elif phase == "attack":
        if shape == "arc":
            a = v_lerp(coil, follow, threat.sweep)
        elif shape == "lane":
            a = v_lerp(coil, strike, min(threat.u / 0.25, 1.0))
        else:
            a = v_lerp(strike, follow, threat.u)
    elif phase == "recover":
        last = strike if shape == "lane" else follow
        rest = v_lerp(carry, keys["slump"], threat.slump)
        a = v_lerp(last, rest, threat.settle)
    else:
        a = carry
    seat = smoothstep(min(max(pose.seat, 0.0), 1.0))
    if seat > 0:
        a = v_lerp(a, keys["seat"], seat)
    swing = k["armSwing"] * model.get("armSwingShare", 1.0) * pose.walk_amp * math.sin(pose.walk_phase)
    return (a[0] + swing, a[1], a[2])


# --- the strip's frames -----------------------------------------------------------------------------


@dataclass
class Frame:
    name: str
    label: str
    pose: Pose
    threat: Threat
    shape: str = ""
    enraged: bool = False


def frames_for(kind_id: str, kinds: dict, threat_cfg: dict, consts: Constants, model: dict, rig_numbers: dict) -> list[Frame]:
    """rest, two walk frames, windup, blow, seated, spent (of the kind's first attack); for a kind
    with an arc that is not its first attack (the Chief's sweep) also that arc's windup and swing;
    for a boss with a second phase, its enraged look at rest."""
    kind = kinds[kind_id]
    first = attack_of(kind, 1, threat_cfg, consts)
    frames: list[Frame] = []

    def make(name, label, threat, attack_shape="", enraged=False, **pose_kw):
        pose = Pose(**pose_kw)
        pose.lean, pose.twist, pose.squash, pose.thrust = (pose.lean + threat.lean, pose.twist + threat.twist,
                                                         drawn_squash(pose.squash * threat.squash), pose.thrust + threat.thrust)
        pose.arm = arm_channel(model, attack_shape or first.shape, threat, pose, rig_numbers)
        frames.append(Frame(name, label, pose, threat, attack_shape or first.shape, enraged))

    idle = Threat()
    make("rest", "rest", idle)
    make("walkA", "walk", idle, walk_phase=math.pi / 2, walk_amp=1.0)
    make("walkB", "walk", idle, walk_phase=3 * math.pi / 2, walk_amp=1.0)
    coil_age = first.windup * consts.COMBAT_RANGE_TELL_COIL_SHARE
    make("windup", f"windup ({first.shape})", threat_pose(consts, kind, first, "windup", coil_age))
    make("blow", f"blow ({first.shape})", threat_pose(consts, kind, first, "attack", 0.0))
    make("seated", "seated", idle, seat=1.0)
    spent_age = max(first.recover - consts.COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS, consts.COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS)
    make("spent", "spent", threat_pose(consts, kind, first, "recover", spent_age))
    for index, raw in enumerate(kind["attacks"], start=1):
        if raw.get("shape") == "arc" and index != 1:
            arc = attack_of(kind, index, threat_cfg, consts)
            make("sweepWindup", "sweep windup", threat_pose(consts, kind, arc, "windup", arc.windup * consts.COMBAT_RANGE_TELL_COIL_SHARE), "arc")
            make("sweepSwing", "sweep swing", threat_pose(consts, kind, arc, "attack", arc.strike * 0.3), "arc")
            break
    if kind.get("boss") and (kind.get("enrage") or {}).get("at", 0) > 0:
        make("enraged", "enraged (rest)", idle, enraged=True)
    return frames


# --- the head rule check ------------------------------------------------------------------------------


def sweep_poses(kind: dict, threat_cfg: dict, consts: Constants, model: dict, rig_numbers: dict):
    """Every pose a living body can take before a hit lands, sampled: idle, walk, seat, stagger,
    reel, flinch, every phase of every attack, walking through a recover, enraged or not."""
    for walk in (0.0, 0.5, 1.0):
        for phase in (0.0, 0.7, 1.6, 2.4, 3.9, 4.7):
            yield "walk", Pose(walk_phase=phase, walk_amp=walk), Threat(), ""
    for seat in (0.25, 0.5, 1.0):
        yield "seat", Pose(seat=seat), Threat(), ""
    yield "stagger", Pose(lean=state_lean(consts, "stagger")), Threat(), ""
    yield "reel", Pose(lean=-consts.COMBAT_RANGE_REEL_LEAN, twist=consts.COMBAT_RANGE_REEL_SWAY,
                       squash=consts.COMBAT_RANGE_REEL_SQUASH), Threat(), ""
    yield "flinch", Pose(lean_side=0.35 * 3, squash=0.5), Threat(), ""
    if kind.get("boss"):
        for t in (0.0, 0.4, 0.7, 1.1, 1.6):
            for enraged in (False, True):
                yield "breath", Pose(squash=boss_breath(consts, t, enraged)), Threat(), ""
    for enraged in (False, True):
        for index in range(1, len(kind["attacks"]) + 1):
            atk = attack_of(kind, index, threat_cfg, consts, enraged)
            for phase, length in (("windup", atk.windup), ("attack", atk.strike), ("recover", atk.recover)):
                for step in range(0, 11):
                    age = length * step / 10
                    for stride in ((0.0, 1.0) if phase == "recover" else (0.0,)):
                        t = threat_pose(consts, kind, atk, phase, age, enraged=enraged, stride=stride, unwind=0.6,
                                        server_now=age * 7.3)
                        pose = Pose(lean=t.lean, twist=t.twist, squash=drawn_squash(t.squash), thrust=t.thrust,
                                    walk_phase=1.3, walk_amp=stride)
                        pose.arm = arm_channel(model, atk.shape, t, pose, rig_numbers)
                        yield f"{atk.shape} {phase}", pose, t, atk.shape


def check(models: dict, kinds: dict, threat_cfg: dict, consts: Constants) -> int:
    rig_numbers = models.get("rig", {})
    failures = 0
    for kind_id, model in sorted(models["kinds"].items()):
        kind = kinds.get(kind_id)
        if kind is None:
            print(f"[raiderpose] {kind_id}: no such crowd kind in ProvingGrounds.json")
            failures += 1
            continue
        for key in ("height", "radius", "headRadius"):
            if abs(model[key] - kind[key]) > 1e-6:
                print(f"[raiderpose] {kind_id}: model built for {key} {model[key]}, the kind has {kind[key]}")
                failures += 1
        hr = model["headRadius"]
        worst, worst_name, floats = 0.0, "", 0.0
        mesh_off = tuple(model.get("headMeshCentre", model["points"]["head"]))
        count = 0
        # How far the posed body reaches (the sight gate's input): the weapon's tip and the hand,
        # flat from the axis and up from the feet, over the same poses.
        tip = model["points"].get("tip")
        reach, top = 0.0, 0.0
        for name, pose, _, _ in sweep_poses(kind, threat_cfg, consts, model, rig_numbers):
            r = rig(model, rig_numbers, consts, pose)
            drawn = r.pieces["head"].point(mesh_off)
            off = v_len(v_sub(drawn, r.anchor)) / hr
            count += 1
            if off > worst:
                worst, worst_name = off, name
            floats = max(floats, max(r.foot_float.values()))
            for p in (model["points"]["hand"], tip):
                if p is not None:
                    q = r.pieces["arm"].point(tuple(p))
                    reach = max(reach, math.hypot(q[0], q[2]))
                    top = max(top, q[1])
        verdict = "PASS" if worst <= 0.5 else "FAIL"
        if worst > 0.5:
            failures += 1
        print(f"[raiderpose] {kind_id}: head rule {verdict} over {count} poses: worst {worst:.3f} head radii ({worst_name}); "
              f"a foot floats at most {floats:.3f} studs; the weapon reaches {reach:.2f} studs out and {top:.2f} up "
              f"(rest bounds reach {model['reach']}, {model['reachRadii']} radii)")
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Raider model poses: the client's maths and the rig.")
    parser.add_argument("--check", action="store_true", help="the head rule over every sampled pose")
    parser.add_argument("--frames", help="print one kind's strip frames")
    parser.add_argument("--models", default=MODELS_PATH, help="RaiderModels.json to read")
    args = parser.parse_args(argv)
    consts = Constants()
    kinds, threat_cfg, notes = load_kinds()
    for kind_id, note in notes.items():
        print(f"[raiderpose] {kind_id}: {note}")
    models = load_models(args.models)
    if args.frames:
        model = models["kinds"][args.frames]
        for f in frames_for(args.frames, kinds, threat_cfg, consts, model, models.get("rig", {})):
            p = f.pose
            print(f"{f.name:12s} lean {p.lean:+.3f} twist {p.twist:+.3f} squash {p.squash:.3f} thrust {p.thrust:+.3f} "
                  f"seat {p.seat:.1f} walk {p.walk_amp:.1f}@{p.walk_phase:.2f} arm {tuple(round(x, 3) for x in p.arm)} "
                  f"tint {f.threat.tint:.3f} glow {f.threat.glow}")
        return 0
    return check(models, kinds, threat_cfg, consts)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
