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
     * the lunge's thrust: the leading foot steps forward with it and the arm's strike pose carries
       the reach; and (L4 W2 fix round, K1: the arm alone reaches 2.27 of the placeholder's 3.44)
       the whole body slides forward by `slideShare` of the thrust while the thrust is forward,
       which is the strike window (late in the windup's snap, through the blow, back to 0 by its
       recover), as the placeholder slid; the trailing foot stays where it stood. The head rule is
       waived for that slide alone: the head keeps its rule against the slid body, and the anchor
       (the scored head, which the server never moves) stays put;
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
KITS_ROOT = os.path.join(REPO_ROOT, "assets", "kenney3d")
GLB_DIR = os.path.join("Models", "GLB format")
WEAPONS_DIR = os.path.join(KITS_ROOT, "weapon-kit", GLB_DIR)
PIECES = ("head", "torso", "arm", "legL", "legR")
PIECE_SUFFIX = {"head": "Head", "torso": "Torso", "arm": "Arm", "legL": "LegL", "legR": "LegR"}
# A vertex of another piece (or the held weapon) this close to the scored head's centre, in head
# radii, is "in the head": a hit there would crit though it lands on the body. The neck reaching up
# under the skull stays outside it (raiderview marks the same in every strip frame).
INTRUDE_SHARE = 0.8
# --check's in-head gate, over every sampled pose but the flinch (a reaction to a hit that has landed:
# the side lean swings a shoulder up under the skull for 0.16 s): a little under the strips' mark, so
# the neck under the jaw (0.79-0.81 hr on the fodder) never trips it and a crossbow stock, a raised
# arm or a pauldron through the face always does.
IN_HEAD_GATE = 0.75
REACTION_POSES = ("flinch",)

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
    "COMBAT_RANGE_ENRAGE_GLOW_COLOR", "COMBAT_REST_HIP_SHARE",
    "COMBAT_RANGE_CUE_CHARGE_SHARE", "COMBAT_RANGE_CUE_AIM_CHARGE_SHARE", "COMBAT_RANGE_CUE_BOSS_CHARGE_SHARE",
    "COMBAT_RANGE_ENRAGE_CORE_SCALE", "COMBAT_RANGE_PLATE_COLOR", "COMBAT_RANGE_CUE_BREAK_GROW", "COMBAT_RANGE_WARD_COLOR",
    "COMBAT_RAIDER_WALK_EASE_RATE", "COMBAT_RAIDER_WALK_SETTLE",
)
RENDERER_NAMES = (
    "STAGGER_LEAN", "WINDUP_LEAN", "AIRBORNE_LEAN", "AIRBORNE_TUCK", "HEAD_TINT", "HEAD_TINT_SHARE",
    "LEG_SHADE", "LEG_SHADE_SHARE", "VISOR_COLOR", "VISOR_HOT_COLOR", "FLASH_COLOR", "TORSO_DEPTH",
)
# ProvingGrounds.json crowd keys (L4 W2, contract 5: the server steps the seat too, so the drop and
# the rise are config, no longer Theme numbers): read by their config names.
CROWD_NAMES = ("restDrop", "riseBlendSeconds")

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


def _read_crowd(path: str, names: tuple[str, ...]) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        crowd = json.load(fh).get("crowd") or {}
    found = {n: float(crowd[n]) for n in names
             if isinstance(crowd.get(n), (int, float)) and not isinstance(crowd.get(n), bool)}
    missing = [n for n in names if n not in found]
    if missing:
        raise ValueError(f"{os.path.relpath(path, REPO_ROOT)} crowd no longer defines {', '.join(missing)}: re-port raiderpose.py")
    return found


class Constants:
    """Theme.luau and CrowdRenderer.luau's numbers, by their Luau names, and ProvingGrounds.json's
    crowd numbers the pose reads, by their config names (CROWD_NAMES)."""

    def __init__(self):
        self.values = {**_read_constants(THEME_PATH, THEME_NAMES), **_read_constants(RENDERER_PATH, RENDERER_NAMES),
                       **_read_crowd(PROVING_PATH, CROWD_NAMES)}

    def __getattr__(self, name: str):
        try:
            return self.values[name]
        except KeyError:
            raise AttributeError(name) from None


# --- kinds ------------------------------------------------------------------------------------

def load_kinds(path: str = PROVING_PATH) -> tuple[dict, dict, dict]:
    """(kinds, crowd.threat, notes): ProvingGrounds.json's crowd kinds. The Camp Chief is the real
    `chief` kind (L4 W2 contract 4; its stand-in went with W2): a model whose kind is missing fails
    --check by name."""
    with open(path, "r", encoding="utf-8") as fh:
        crowd = json.load(fh)["crowd"]
    return dict(crowd["kinds"]), crowd.get("threat", {}), {}


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
    lock: float = 0.0  # a line's lockSeconds: the aim is fixed this long before the hit


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
    lock = max(a.get("lockSeconds", 0) or 0, 0) if shape == "line" else 0.0
    return Attack(shape, windup, recover, strike, reach, arc, lock)


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
    # For the arm channel: the phase and its clocks (age = seconds into the phase).
    phase: str = "none"
    age: float = 0.0
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
    out = Threat(phase=phase, age=age)
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
    "slideShare": 0.6,  # share of the lunge's forward thrust the whole body slides (K1: the strike window only)
    "seatLean": 0.12,  # radians a seated body leans forward
    "seatSplay": 0.14,  # radians each seated leg turns outward
    "airTuck": 0.5,  # radians the legs swing forward while airborne
    "throwShare": 0.35,  # a throw or a shot (shot, lob, line): share of the strike spent going coil -> strike
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
    anchor: Vec = (0.0, 0.0, 0.0)  # the scored head's centre (never slid: the server's head stays)
    head_offset: float = 0.0  # studs, from the anchor (the slide included)
    drop: float = 0.0
    foot_float: dict[str, float] = field(default_factory=dict)
    slide: float = 0.0  # studs the whole body slid along its facing (K1: a lunge's strike window)

    def anchor_frame(self) -> CFrame:
        """The invisible anchor part's transform (RaiderPose.Rig's `anchor`): at the scored head, unturned."""
        return cf_at(self.anchor)


def lean_parts(yaw: float, lean_x: float, lean_z: float) -> tuple[float, float]:
    """RaiderPose.Lean: a flat lean vector (CrowdRenderer keeps one per body) split along the body's
    facing (+ forward) and across it (+ toward its right): the Pose's lean and lean_side. The facing
    and the right are look_of(yaw) and (cos yaw, 0, -sin yaw), the basis rig() rebuilds it from."""
    s, c = math.sin(yaw), math.cos(yaw)
    return lean_x * -s + lean_z * -c, lean_x * c + lean_z * -s


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
    seat_drop = height * consts.restDrop * seat
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
    # K1: the strike window's slide, a lunge's forward thrust only (0 in its coil, which draws back).
    slide = max(pose.thrust, 0.0) * k["slideShare"]
    out = Rigged(anchor=anchor, drop=drop, slide=slide)

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
        # The leading foot steps with the lunge's thrust; the trailing one stays where it stood
        # while the body slides (its spot lies `slide` behind in the body's frame).
        step = pose.thrust * k["stepShare"] if name == model.get("leadLeg", "legL") else -slide
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
    if slide > 0:
        shift = v_mul(facing, slide)
        for name in PIECES:
            out.pieces[name] = cf_at(shift) * out.pieces[name]
        out.head_world = v_add(out.head_world, shift)
        out.head_offset = v_len(v_sub(out.head_world, anchor))
    return out


# --- the walk cycle --------------------------------------------------------------------------------


def walk_step(phase: float, amp: float, travel: float, dt: float, speed: float, leg_length: float,
              distance: float, near_studs: float, rig_numbers: dict, consts: Constants) -> tuple[float, float]:
    """One frame of the walk cycle (RaiderPose.Walk, L4 W2 contract 3.3): (phase, amplitude).

    `travel` = studs the drawn feet moved on the flat this frame, `dt` its seconds, `speed` the kind's,
    `distance` the body's from the camera, `near_studs` the most it walks at (rig.walkNearStuds, or
    Theme.COMBAT_RAIDER_WALK_NEAR_LOW on a low-end device). The phase runs 2 pi per strideLegs x
    legLength of travel; the amplitude eases toward the pace's share of speed x walkFullShare (0 past
    near_studs), at COMBAT_RAIDER_WALK_EASE_RATE, and snaps once within COMBAT_RAIDER_WALK_SETTLE."""
    k = {**RIG_DEFAULTS, **(rig_numbers or {})}
    stride = k["strideLegs"] * leg_length
    if stride > 0:
        phase = (phase + 2 * math.pi * travel / stride) % (2 * math.pi)
    full = speed * k["walkFullShare"]
    goal = min(max((travel / dt) / full, 0.0), 1.0) if distance <= near_studs and dt > 0 and full > 0 else 0.0
    gap = goal - amp
    if abs(gap) < consts.COMBAT_RAIDER_WALK_SETTLE:
        amp = goal
    else:
        amp = amp + gap * (1 - math.exp(-dt * consts.COMBAT_RAIDER_WALK_EASE_RATE))
    return phase, amp


# --- the weapon arm's channel ----------------------------------------------------------------------

SNAP_SHAPES = ("lunge", "ring")
# A throw or a shot leaves the hand during the strike: the arm goes coil -> strike -> follow.
THROW_SHAPES = ("shot", "lob", "line")


def a_lerp(a, b, t: float) -> tuple[float, ...]:
    """Angles blended the shortest way round: each difference wrapped into [-pi, pi) first."""
    return tuple(x + ((y - x + math.pi) % (2 * math.pi) - math.pi) * t for x, y in zip(a, b))


def arm_channel(model: dict, shape: str, threat: Threat, pose: Pose, rig_numbers: dict,
                attack: Attack | None = None) -> tuple[float, float, float]:
    """The weapon arm's pitch, yaw, roll for one frame: keyed poses blended on threatPose's clocks.

    Keys (RaiderModels.json `arm`): carry, seat, slump, and per shape coil / strike / follow, plus
    the shape's optional rules (L4 W2):
      * `whirl` {turns, sin, cos} (the sling): through the windup the arm adds
        build x (sin(t) x sin + (cos(t) - 1) x cos), t = 2 pi x turns x u (u = the windup's share
        run), so it circles `turns` times and is back on its coil exactly at the release;
      * `steady` true (a two-handed aim, the crossbow): the keys are pitches in the world: the
        body's lean along its facing (pose.lean, + forward, which tips a forward-held weapon down)
        is added to the pitch in every phase, so the aim stays where the key says;
      * a `line` attack with a lock (the marksman) is aimed when its line locks: the arm's build
        runs to windup - lockSeconds, squared like the body's, instead of the body's own build.
    windup: carry -> coil with the build (and coil -> strike with the snap for a lunge or a slam);
    attack: an arc swings coil -> follow with the sweep, a lane holds its strike, a throw (shot, lob,
    line) goes coil -> strike over throwShare of the strike, then strike -> follow, the rest go
    strike -> follow; recover: from where the blow left it to the slump, waking to the carry. Every
    blend goes angle by angle the shortest way round (a_lerp), so a key may sit past pi: the lobber's
    reach back over the shoulder (pitch -2.6) and his release (+2.3) blend over the top, not through
    the hanging arm. (No key of the step-1 kinds is more than pi from the key it blends with, so
    their poses are unchanged by it.)"""
    k = {**RIG_DEFAULTS, **(rig_numbers or {})}
    keys = model["arm"]
    carry = keys["carry"]
    s = keys["shapes"].get(shape) or {}
    coil, strike, follow = s.get("coil", carry), s.get("strike", carry), s.get("follow", s.get("strike", carry))
    phase = threat.phase
    if phase == "windup":
        build = threat.build
        if shape == "line" and attack is not None and attack.lock > 0 and attack.windup > attack.lock:
            build = min(threat.age / (attack.windup - attack.lock), 1.0) ** 2
        a = a_lerp(carry, coil, build)
        if shape in SNAP_SHAPES and threat.snap > 0:
            a = a_lerp(coil, strike, threat.snap)
        whirl = s.get("whirl")
        if whirl:
            t = 2 * math.pi * whirl["turns"] * threat.u
            sn, cs = math.sin(t), math.cos(t) - 1
            a = tuple(a[i] + build * (sn * whirl["sin"][i] + cs * whirl["cos"][i]) for i in range(3))
    elif phase == "attack":
        if shape == "arc":
            a = a_lerp(coil, follow, threat.sweep)
        elif shape == "lane":
            a = a_lerp(coil, strike, min(threat.u / 0.25, 1.0))
        elif shape in THROW_SHAPES:
            share = k["throwShare"]
            if threat.u < share:
                a = a_lerp(coil, strike, threat.u / share)
            else:
                a = a_lerp(strike, follow, (threat.u - share) / (1 - share))
        else:
            a = a_lerp(strike, follow, threat.u)
    elif phase == "recover":
        last = strike if shape == "lane" else follow
        rest = a_lerp(carry, keys["slump"], threat.slump)
        a = a_lerp(last, rest, threat.settle)
    else:
        a = carry
    seat = smoothstep(min(max(pose.seat, 0.0), 1.0))
    if seat > 0:
        a = a_lerp(a, keys["seat"], seat)
    swing = k["armSwing"] * model.get("armSwingShare", 1.0) * pose.walk_amp * math.sin(pose.walk_phase)
    steady = pose.lean if s.get("steady") else 0.0
    return (a[0] + swing + steady, a[1], a[2])


# --- the lit piece (ThreatFx/Cues), where a model carries it ------------------------------------


def cue_sizes(consts: Constants, kind: dict, model: dict) -> tuple[float, float] | None:
    """(rest diameter, fully charged diameter) of the kind's lit piece, as Cues.Attach sizes it
    today, or as the model's `cue` record overrides it (the Chief's core at model size). None: the
    kind has no lit piece."""
    cue = model.get("cue")
    if not cue:
        return None
    if "size" in cue and "charged" in cue:
        return cue["size"], cue["charged"]
    shape = (kind.get("attacks") or [{}])[0].get("shape")
    r, h = kind["radius"], kind["height"]
    if kind.get("boss"):
        d = max(r * 0.6, 0.8)
        return d, max(h * consts.COMBAT_RANGE_CUE_BOSS_CHARGE_SHARE, d)
    if shape == "shot":
        d = max(r * 0.75, 0.6)
        return d, h * consts.COMBAT_RANGE_CUE_CHARGE_SHARE
    if shape == "lob":
        d = max(r * 0.8, 0.7)
        return d, h * consts.COMBAT_RANGE_CUE_CHARGE_SHARE
    if shape == "line":
        return 0.55, h * consts.COMBAT_RANGE_CUE_AIM_CHARGE_SHARE
    return None


# --- the posed extent: every vertex over every pose -------------------------------------------------


def _glb_points(path: str) -> list[Vec]:
    sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "assets"))
    import glbtools  # noqa: E402  (stdlib only: runs under py and inside Blender)

    with open(path, "rb") as fh:
        doc, binary = glbtools.parse_glb(fh.read())
    out: list[Vec] = []
    scene = doc["scenes"][doc.get("scene", 0)]

    def visit(index, parent):
        node = doc["nodes"][index]
        world = glbtools.mat_mul(parent, glbtools.trs_matrix(node))
        if "mesh" in node:
            for prim in doc["meshes"][node["mesh"]]["primitives"]:
                out.extend(glbtools.apply(world, p)
                           for p in glbtools.read_positions(doc, binary, prim["attributes"]["POSITION"]))
        for child in node.get("children", []):
            visit(child, world)

    for root in scene.get("nodes", []):
        visit(root, glbtools.trs_matrix({}))
    return out


def unique_points(points, grid: float = 0.005) -> list[Vec]:
    seen: dict = {}
    for p in points:
        seen.setdefault((round(p[0] / grid), round(p[1] / grid), round(p[2] / grid)), tuple(p))
    return list(seen.values())


def model_points(model: dict, root: str = KITS_ROOT) -> tuple[dict[str, list[Vec]], list[Vec]]:
    """(piece -> its vertices, the held weapon's vertices) from the generator's GLBs: what --check
    measures the posed extent on."""
    pieces = {}
    for entry in model["pieces"]:
        pts: list[Vec] = []
        for kit in entry["parts"]:
            path = os.path.join(root, kit, GLB_DIR, f"{model['model']}_{PIECE_SUFFIX[entry['name']]}.glb")
            if not os.path.isfile(path):
                raise FileNotFoundError(f"{os.path.relpath(path, REPO_ROOT)} is missing: run the generator")
            pts += _glb_points(path)
        pieces[entry["name"]] = unique_points(pts)
    held: list[Vec] = []
    hold = model.get("hold")
    if hold:
        path = os.path.join(WEAPONS_DIR, f"{hold['model']}.glb")
        if os.path.isfile(path):
            held = unique_points(_glb_points(path))
    return pieces, held


def hold_frame(hold: dict) -> CFrame:
    right, up = tuple(hold["right"]), tuple(hold["up"])
    back = v_cross(right, up)
    rot = ((right[0], up[0], back[0]), (right[1], up[1], back[1]), (right[2], up[2], back[2]))
    return CFrame(rot, tuple(hold["grip"]))  # type: ignore[arg-type]


def posed_extent(model: dict, kind: dict, threat_cfg: dict, consts: Constants, rig_numbers: dict,
                 pieces: dict[str, list[Vec]], held: list[Vec]) -> dict:
    """The body's extent over every sampled pose before a hit lands (sweep_poses), from every vertex
    of every piece and of the held weapon: how far it reaches out from its axis and up from its feet
    (the sight gate's input, in place of the placeholder torso's half-diagonal), and how close any
    piece but the head comes to the scored head's centre, in head radii (the flinch left out)."""
    hold = model.get("hold")
    hf = hold_frame(hold) if hold else None
    scale = hold["scale"] if hold else 1.0
    held_local = [hf.point(v_mul(v, scale)) for v in held] if hf else []
    hr = model["headRadius"]
    out = {"out": 0.0, "up": 0.0, "down": math.inf, "outPose": "", "upPose": "", "downPose": "", "intrude": math.inf,
           "intrudePose": "", "cueOut": 0.0, "cueUp": 0.0}
    cue = model.get("cue")
    sizes = cue_sizes(consts, kind, model) if cue else None
    cue_r = max(sizes) / 2 if sizes else 0.0
    for name, pose, _, _ in sweep_poses(kind, threat_cfg, consts, model, rig_numbers):
        r = rig(model, rig_numbers, consts, pose)
        ax, ay, az = r.anchor
        if sizes:
            # The lit piece at its largest wherever its anchor goes (a cue swells only in a windup;
            # taking its largest everywhere is the safe side for a sight gate).
            c = r.pieces[cue["piece"]].point(tuple(model["points"][cue["point"]]))
            out["cueOut"] = max(out["cueOut"], math.hypot(c[0], c[2]) + cue_r)
            out["cueUp"] = max(out["cueUp"], c[1] + cue_r)
        for piece in PIECES:
            cf = r.pieces[piece]
            (r00, r01, r02), (r10, r11, r12), (r20, r21, r22) = cf.r
            px, py, pz = cf.p
            pts = pieces.get(piece, [])
            if hold and hold.get("piece", "arm") == piece:
                pts = pts + held_local
            far, top, low, near = 0.0, -math.inf, math.inf, math.inf
            for x, y, z in pts:
                wx = r00 * x + r01 * y + r02 * z + px
                wy = r10 * x + r11 * y + r12 * z + py
                wz = r20 * x + r21 * y + r22 * z + pz
                d = wx * wx + wz * wz
                if d > far:
                    far = d
                if wy > top:
                    top = wy
                if wy < low:
                    low = wy
                if piece != "head":
                    e = (wx - ax) ** 2 + (wy - ay) ** 2 + (wz - az) ** 2
                    if e < near:
                        near = e
            far = math.sqrt(far)
            if far > out["out"]:
                out["out"], out["outPose"] = far, f"{name} ({piece})"
            if top > out["up"]:
                out["up"], out["upPose"] = top, f"{name} ({piece})"
            if low < out["down"]:
                out["down"], out["downPose"] = low, f"{name} ({piece})"
            if piece != "head" and pts and name not in REACTION_POSES and math.sqrt(near) / hr < out["intrude"]:
                out["intrude"], out["intrudePose"] = math.sqrt(near) / hr, f"{name} ({piece})"
    return out


# --check's weapon rules at an attack's blow (L4 W2 contract 3.4, risk 4; fix round K1, K2). The
# weapon is the arm piece and the held model (the Chief's hammer), on the body where the rig puts it
# (a lunge's slide included), sampled IMPACT_STEPS times over the strike, enraged or not.
#   * Never too far: over the strike the weapon reaches on the flat no farther than the attack itself
#     (its `range`, or its `reach` when it has none) + IMPACT_SLACK. For an arc only what lies inside
#     the arc counts: a hammer behind the shoulder is not the sweep.
#   * K1, never short where nothing else tells: an attack the client draws no tell for on the floor
#     (NO_TELL_SHAPES: CrowdRenderer's wedge is an arc's, ThreatFx draws lanes, lines, slams and
#     calls, shots and lobs fly) reaches on the flat at its impact at least the placeholder's front
#     there (placeholder_front), the look the game was played with.
#   * K2, a sweep drawn where it hits (SWEEP_FLOOR_KINDS): every SECTOR_DEGREES of its arc is swept at
#     a flat reach of at least its range - IMPACT_SLACK. Every arc's sectors are printed; the ruling
#     names the Camp Chief's hammer, so only that kind fails on them. Fix round 2 (L1): the sectors
#     are 5 degrees (at 15 a sector "swept" by its last 0.6 degrees hid a 10-degree hole at his left),
#     and two more rules hold for those kinds, both on the weapon "at range" (its vertices at a flat
#     reach of range - IMPACT_SLACK or more):
#       - the span: its angles inside the arc come within one sector of each edge of the wedge;
#       - the lag: at every sample of the strike its leading end (the angle farthest toward his left,
#         the way the sweep runs) is never more than one sector behind the ground tell's leading
#         edge (tell_lead); a sample with nothing at range lags without end.
IMPACT_SLACK = 0.5
IMPACT_STEPS = 120
NO_TELL_SHAPES = ("lunge",)
SECTOR_DEGREES = 5.0
SWEEP_FLOOR_KINDS = ("chief",)


def placeholder_front(consts: Constants, kind: dict, attack: Attack) -> tuple[float, float]:
    """(the placeholder torso's front face at the attack's impact, its head's front there): the
    figure CrowdRenderer draws for a kind with no model slides by the blow's thrust and tips forward
    by its lean, pivoting at its feet. The gate's floor is the first, upright (the review's measure
    the ruling quotes); the second, its head carried forward by that tip, is printed beside it."""
    t = threat_pose(consts, kind, attack, "attack", 0.0)
    face = t.thrust + kind["radius"] * consts.TORSO_DEPTH / 2
    head = t.thrust + (kind["height"] - kind["headRadius"]) * math.sin(t.lean) + kind["headRadius"]
    return face, head


def arc_angle(x: float, z: float) -> float:
    """Degrees from the body's facing (-Z at yaw 0), + toward its right (+X)."""
    return math.degrees(math.atan2(x, -z))


def tell_lead(half: float, sweep: float) -> float:
    """An arc's ground tell's leading edge in arc_angle degrees. CrowdRenderer.layTell lays it at
    yaw - arc / 2 + arc x sweep (a larger yaw turns toward the body's left), so it runs from his
    right edge (+half at sweep 0) to his left one (-half at sweep 1) on threatPose's own sweep."""
    return half - 2 * half * sweep


def impact_reach(model: dict, kind: dict, threat_cfg: dict, consts: Constants, rig_numbers: dict,
                 pieces: dict[str, list[Vec]], held: list[Vec], kind_id: str = "") -> list[dict]:
    """Per attack of the kind, the weapon rules above: `reach` = the farthest flat reach that counts
    (inside the arc for an arc), `impact` = the flat reach at the impact (u = 0, not enraged),
    `floor` / `head` = placeholder_front for a no-tell shape, `sectors` = an arc's farthest reach per
    sector (0 = never swept), `span` = an arc's angles at range inside it (left, right), `lag` / `lagAt`
    = the most its leading end at range fell behind the tell's leading edge and when, `ok` = every rule
    that applies holds."""
    hold = model.get("hold")
    hf = hold_frame(hold) if hold else None
    scale = hold["scale"] if hold else 1.0
    held_local = [hf.point(v_mul(v, scale)) for v in held] if hf else []
    weapon = list(pieces.get("arm", []))
    if hold and hold.get("piece", "arm") == "arm":
        weapon += held_local
    rows = []
    for index, raw in enumerate(kind.get("attacks") or [], start=1):
        limit = raw.get("range", raw.get("reach"))
        if not isinstance(limit, (int, float)):
            continue
        shape = raw.get("shape", "")
        base = attack_of(kind, index, threat_cfg, consts)
        half = math.degrees(base.arc) / 2 if shape == "arc" else 180.0
        count = max(int(round(2 * half / SECTOR_DEGREES)), 1) if shape == "arc" else 0
        sectors = [0.0] * count
        at_range = float(limit) - IMPACT_SLACK
        span = [math.inf, -math.inf]
        lag, lag_at = -math.inf, ""
        worst, worst_at, impact = 0.0, "", 0.0
        for enraged in (False, True):
            atk = attack_of(kind, index, threat_cfg, consts, enraged)
            for step in range(0, IMPACT_STEPS + 1):
                u = step / IMPACT_STEPS
                age = atk.strike * u
                t = threat_pose(consts, kind, atk, "attack", age, enraged=enraged, server_now=age * 7.3)
                pose = Pose(lean=t.lean, twist=t.twist, squash=drawn_squash(t.squash), thrust=t.thrust)
                pose.arm = arm_channel(model, atk.shape, t, pose, rig_numbers, atk)
                cf = rig(model, rig_numbers, consts, pose).pieces["arm"]
                leading = math.inf
                for v in weapon:
                    w = cf.point(v)
                    d = math.hypot(w[0], w[2])
                    if step == 0 and not enraged and d > impact:
                        impact = d
                    if count:
                        angle = arc_angle(w[0], w[2])
                        if d >= at_range:
                            leading = min(leading, angle)
                        if abs(angle) > half:
                            continue
                        slot = min(int((angle + half) // SECTOR_DEGREES), count - 1)
                        sectors[slot] = max(sectors[slot], d)
                        if d >= at_range:
                            span[0], span[1] = min(span[0], angle), max(span[1], angle)
                    if d > worst:
                        worst, worst_at = d, f"u {u:.2f}{' enraged' if enraged else ''}"
                if count:
                    behind = leading - tell_lead(half, t.sweep)
                    if behind > lag:
                        lag, lag_at = behind, f"u {u:.2f}{' enraged' if enraged else ''}"
        row = {"index": index, "shape": shape, "reach": worst, "at": worst_at, "limit": float(limit),
               "impact": impact, "sectors": sectors, "floor": None, "head": None, "swept": None,
               "half": half, "span": span, "lag": lag, "lagAt": lag_at}
        ok = worst <= float(limit) + IMPACT_SLACK + 1e-9
        if shape in NO_TELL_SHAPES:
            row["floor"], row["head"] = placeholder_front(consts, kind, base)
            ok = ok and impact >= row["floor"] - 1e-9
        if count and kind_id in SWEEP_FLOOR_KINDS:
            row["swept"] = at_range
            ok = (ok and min(sectors) >= at_range - 1e-9
                  and span[0] <= -half + SECTOR_DEGREES + 1e-9 and span[1] >= half - SECTOR_DEGREES - 1e-9
                  and lag <= SECTOR_DEGREES + 1e-9)
        row["ok"] = ok
        rows.append(row)
    return rows


def impact_text(row: dict) -> str:
    """One attack's weapon rules for --check's line."""
    text = f"{row['shape']} {row['reach']:.2f} of {row['limit']:g} ({row['at']}"
    text += ", inside the arc)" if row["sectors"] else ")"
    if row["floor"] is not None:
        text += (f", at the impact {row['impact']:.2f} >= the placeholder torso's {row['floor']:.2f} (its tipped "
                 f"head reached {row['head']:.2f})")
    if row["sectors"]:
        gated = row["swept"] is not None
        floor = f" >= {row['swept']:g}" if gated else ""
        text += (f", per {SECTOR_DEGREES:g} deg from his left{floor}: "
                 + " ".join(f"{s:.2f}" for s in row["sectors"]))
        edge = row["half"] - SECTOR_DEGREES
        within = f" (within {SECTOR_DEGREES:g} of -{row['half']:g} and +{row['half']:g}: <= -{edge:g}, >= +{edge:g})"
        behind = f" <= {SECTOR_DEGREES:g}" if gated else ""
        spans = (f"spans {row['span'][0]:+.1f}..{row['span'][1]:+.1f}" if row["span"][0] <= row["span"][1]
                 else "is never inside the arc")
        lags = (f"behind the tell's leading edge at most {row['lag']:+.1f} deg ({row['lagAt']})" if row["lag"] < math.inf
                else f"nowhere at {row['lagAt']}, so behind the tell's leading edge without end")
        text += (f"; at range {row['limit'] - IMPACT_SLACK:g} it {spans}" + (within if gated else "")
                 + f"; {lags}{behind}")
    return text + ("" if row["ok"] else " FAIL")


def reach_record(extent: dict, radius: float) -> dict:
    """RaiderModels.json `posedReach`: what camp C's sight gate reads (studs from the body's axis and
    up from its feet; outRadii = out / radius, the unit check_levels' body_reach uses; withCue: the same
    with the kind's lit piece at its largest)."""
    record = {"out": round(extent["out"], 2), "outRadii": round(extent["out"] / radius, 3), "up": round(extent["up"], 2),
              "outPose": extent["outPose"], "upPose": extent["upPose"]}
    if extent.get("cueUp"):
        # With the kind's lit piece (a client cue, not in the model) at its largest: the orb whirled
        # over a slinger's head stands far above the model.
        record["withCue"] = {"out": round(max(extent["out"], extent["cueOut"]), 2),
                             "up": round(max(extent["up"], extent["cueUp"]), 2)}
    return record


# --- the strip's frames -----------------------------------------------------------------------------


@dataclass
class Frame:
    name: str
    label: str
    pose: Pose
    threat: Threat
    shape: str = ""
    enraged: bool = False
    # The plate's state for a kind with one (the plate role, raider-plate): "on", "glint" (it has just
    # turned a hit), "break" (the burst, `plate_share` of it played), "gone". "" = the kind's default
    # (on for a plated kind).
    plate: str = ""
    plate_share: float = 0.0


def reel_pose(consts: Constants, server_now: float = 0.15) -> tuple[Pose, Threat]:
    """The reel after a plate breaks (stepAlive's `reeling` branch): thrown back, swaying, slumped,
    tinted dull like a spent body."""
    pose = Pose(lean=-consts.COMBAT_RANGE_REEL_LEAN,
                twist=consts.COMBAT_RANGE_REEL_SWAY * math.sin(server_now * 2 * math.pi * consts.COMBAT_RANGE_REEL_SWAY_HZ),
                squash=consts.COMBAT_RANGE_REEL_SQUASH)
    threat = Threat(tint=stepped(consts, consts.COMBAT_RANGE_TELL_SPENT_SHARE), tint_colour=consts.COMBAT_RANGE_TELL_SPENT_COLOR)
    return pose, threat


def frames_for(kind_id: str, kinds: dict, threat_cfg: dict, consts: Constants, model: dict, rig_numbers: dict) -> list[Frame]:
    """rest, two walk frames, the windup and the blow of the kind's first attack (a shooter's own
    attack in its steps: the sling's whirl and release, the crossbow raised, aimed at the lock and
    fired, the firepot's throw), seated, spent; a kind with an arc that is not its first attack (the
    Chief's sweep) also that arc's windup and swing; a boss with a second phase its enraged look; a
    plated kind its plate glinting, breaking, the reel after it and the bare body."""
    kind = kinds[kind_id]
    first = attack_of(kind, 1, threat_cfg, consts)
    frames: list[Frame] = []
    k = {**RIG_DEFAULTS, **(rig_numbers or {})}

    def make(name, label, threat, attack=None, enraged=False, plate="", plate_share=0.0, **pose_kw):
        atk = attack or first
        pose = Pose(**pose_kw)
        pose.lean, pose.twist, pose.squash, pose.thrust = (pose.lean + threat.lean, pose.twist + threat.twist,
                                                         drawn_squash(pose.squash * threat.squash), pose.thrust + threat.thrust)
        pose.arm = arm_channel(model, atk.shape, threat, pose, rig_numbers, atk)
        frames.append(Frame(name, label, pose, threat, atk.shape, enraged, plate, plate_share))

    def at(phase, age, attack=None):
        return threat_pose(consts, kind, attack or first, phase, age)

    idle = Threat()
    make("rest", "rest", idle)
    make("walkA", "walk", idle, walk_phase=math.pi / 2, walk_amp=1.0)
    make("walkB", "walk", idle, walk_phase=3 * math.pi / 2, walk_amp=1.0)
    shape = first.shape
    coil_age = first.windup * consts.COMBAT_RANGE_TELL_COIL_SHARE
    throw_age = first.strike * k["throwShare"]
    if shape == "shot":
        make("whirlEarly", "windup 40%: the whirl starts", at("windup", first.windup * 0.4))
        make("windup", "windup 80%: whirling", at("windup", coil_age))
        make("whirlLate", "windup 95%: last turn", at("windup", first.windup * 0.95))
        make("blow", "the release (shot)", at("attack", throw_age))
        make("follow", "follow-through", at("attack", first.strike))
    elif shape == "line":
        aim_age = first.windup - first.lock if first.lock > 0 else coil_age
        make("raise", "windup 20%: raising", at("windup", first.windup * 0.2))
        make("windup", f"aimed: the line locks ({first.lock:.2f} s left)", at("windup", aim_age))
        make("hold", "held on the lock (windup 95%)", at("windup", first.windup * 0.95))
        make("blow", "the shot (recoil)", at("attack", throw_age))
        make("follow", "follow-through", at("attack", first.strike))
    elif shape == "lob":
        make("windup", "windup: reaching back (lob)", at("windup", coil_age))
        make("blow", "the throw (release)", at("attack", throw_age))
        make("follow", "follow-through", at("attack", first.strike))
    elif shape == "arc":
        make("windup", "windup (arc)", at("windup", coil_age))
        make("blow", "the sweep (arc)", at("attack", first.strike * 0.3))
    else:
        make("windup", f"windup ({shape})", at("windup", coil_age))
        make("blow", f"blow ({shape})", at("attack", 0.0))
    make("seated", "seated", idle, seat=1.0)
    spent_age = max(first.recover - consts.COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS, consts.COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS)
    make("spent", "spent", at("recover", spent_age))
    for index, raw in enumerate(kind["attacks"], start=1):
        if raw.get("shape") == "arc" and index != 1:
            # The sweep through its wedge (K2): from his right, across his front, to his left.
            arc = attack_of(kind, index, threat_cfg, consts)
            make("sweepWindup", "sweep windup", at("windup", arc.windup * consts.COMBAT_RANGE_TELL_COIL_SHARE, arc), arc)
            make("sweepStart", "sweep: his right", at("attack", arc.strike * 0.1, arc), arc)
            make("sweepSwing", "sweep: his front", at("attack", arc.strike * 0.3, arc), arc)
            make("sweepEnd", "sweep: his left", at("attack", arc.strike * 0.6, arc), arc)
            break
    if kind.get("boss") and (kind.get("enrage") or {}).get("at", 0) > 0:
        make("enraged", "enraged (rest)", idle, enraged=True)
    if (kind.get("plate") or 0) > 0:
        make("glint", "the plate turns a hit (glint)", idle, plate="glint")
        reel, dull = reel_pose(consts)
        make("break", "the plate breaks (burst)", dull, plate="break", plate_share=0.45,
             lean=reel.lean, twist=reel.twist, squash=reel.squash)
        make("reel", "the reel after it (the opening)", dull, plate="gone", lean=reel.lean, twist=reel.twist,
             squash=reel.squash)
        make("bare", "bare: no plate (rest)", idle, plate="gone")
        make("bareWindup", "bare: windup (arc)", at("windup", coil_age), plate="gone")
    return frames


# --- the head rule check ------------------------------------------------------------------------------


def sweep_poses(kind: dict, threat_cfg: dict, consts: Constants, model: dict, rig_numbers: dict):
    """Every pose a living body can take before a hit lands, sampled: idle, walk, seat, stagger,
    reel, flinch, every phase of every attack, walking through a recover, enraged or not. Every pose
    carries its arm from the arm channel (out of an attack: the carry, the seat, the walk swing)."""
    first = (kind.get("attacks") or [{}])[0].get("shape", "")

    def idle(pose: Pose) -> Pose:
        pose.arm = arm_channel(model, first, Threat(), pose, rig_numbers)
        return pose

    for walk in (0.0, 0.5, 1.0):
        for phase in (0.0, 0.7, 1.6, 2.4, 3.9, 4.7):
            yield "walk", idle(Pose(walk_phase=phase, walk_amp=walk)), Threat(), ""
    for seat in (0.25, 0.5, 0.75, 1.0):
        yield "seat", idle(Pose(seat=seat)), Threat(), ""
    yield "stagger", idle(Pose(lean=state_lean(consts, "stagger"))), Threat(), ""
    yield "reel", idle(Pose(lean=-consts.COMBAT_RANGE_REEL_LEAN, twist=consts.COMBAT_RANGE_REEL_SWAY,
                            squash=consts.COMBAT_RANGE_REEL_SQUASH)), Threat(), ""
    yield "flinch", idle(Pose(lean_side=0.35 * 3, squash=0.5)), Threat(), ""
    if kind.get("boss"):
        for t in (0.0, 0.4, 0.7, 1.1, 1.6):
            for enraged in (False, True):
                yield "breath", idle(Pose(squash=boss_breath(consts, t, enraged))), Threat(), ""
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
                        pose.arm = arm_channel(model, atk.shape, t, pose, rig_numbers, atk)
                        yield f"{atk.shape} {phase}", pose, t, atk.shape


def head_rule_offset(r: Rigged, pose: Pose, mesh_centre: Vec, head_radius: float) -> float:
    """The head rule's measure, in head radii: the drawn head's centre (the head piece carrying
    `mesh_centre`) from the scored head, the anchor. K1: a lunge's slide is waived, so the anchor is
    carried with the body by it (the slide is 0 out of the strike window)."""
    drawn = r.pieces["head"].point(mesh_centre)
    waived = v_add(r.anchor, v_mul(look_of(pose.yaw), r.slide))
    return v_len(v_sub(drawn, waived)) / head_radius


def check(models: dict, kinds: dict, threat_cfg: dict, consts: Constants, *, extent: bool = True) -> int:
    """The head rule over every sampled pose; with `extent` also, from every vertex of the
    generator's GLBs: the posed reach against the config's `posedReach` (a stale config fails) and
    the in-head rule (nothing but the head within INTRUDE_SHARE head radii of the scored head)."""
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
        for name, pose, _, _ in sweep_poses(kind, threat_cfg, consts, model, rig_numbers):
            r = rig(model, rig_numbers, consts, pose)
            off = head_rule_offset(r, pose, mesh_off, hr)
            count += 1
            if off > worst:
                worst, worst_name = off, name
            floats = max(floats, max(r.foot_float.values()))
        verdict = "PASS" if worst <= 0.5 else "FAIL"
        if worst > 0.5:
            failures += 1
        line = (f"[raiderpose] {kind_id}: head rule {verdict} over {count} poses: worst {worst:.3f} head radii ({worst_name}); "
                f"a foot floats at most {floats:.3f} studs")
        if not extent:
            print(line)
            continue
        pieces, held = model_points(model)
        ext = posed_extent(model, kind, threat_cfg, consts, rig_numbers, pieces, held)
        rec = reach_record(ext, model["radius"])
        stored = model.get("posedReach") or {}
        stale = [key for key in ("out", "up") if abs((stored.get(key) or -1) - rec[key]) > 0.011]
        if rec.get("withCue") != stored.get("withCue") and (
                not rec.get("withCue") or not stored.get("withCue")
                or any(abs(rec["withCue"][k] - stored["withCue"][k]) > 0.011 for k in ("out", "up"))):
            stale.append("withCue")
        inside = "PASS" if ext["intrude"] >= IN_HEAD_GATE else "FAIL"
        if inside == "FAIL":
            failures += 1
        if stale:
            failures += 1
        print(line + f"; in-head {inside}: nothing else within {ext['intrude']:.2f} hr ({ext['intrudePose']})")
        print(f"[raiderpose] {kind_id}:   posed reach {rec['out']} studs out ({rec['outRadii']} radii, {rec['outPose']}), "
              f"{rec['up']} up ({rec['upPose']}), lowest point {ext['down']:.2f} ({ext['downPose']})"
              + (f"; with its lit piece {rec['withCue']['out']} out, {rec['withCue']['up']} up" if rec.get("withCue") else "")
              + (f"; STALE config posedReach {stored or 'missing'}: re-run the generator" if stale else "; config posedReach matches"))
        rows = impact_reach(model, kind, threat_cfg, consts, rig_numbers, pieces, held, kind_id)
        bad = [r for r in rows if not r["ok"]]
        failures += 1 if bad else 0
        print(f"[raiderpose] {kind_id}:   weapon at impact {'FAIL' if bad else 'PASS'} (within reach + {IMPACT_SLACK:g}): "
              + "; ".join(impact_text(r) for r in rows))
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Raider model poses: the client's maths and the rig.")
    parser.add_argument("--check", action="store_true", help="the head rule, the in-head rule and the posed reach")
    parser.add_argument("--no-extent", action="store_true", help="--check the head rule only (no GLBs read)")
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
                  f"tint {f.threat.tint:.3f} glow {f.threat.glow} charge {f.threat.charge:.2f} plate {f.plate or '-'}")
        return 0
    return check(models, kinds, threat_cfg, consts, extent=not args.no_extent)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
