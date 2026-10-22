"""Regression harness for the crowd combat server (P4): bundles the real CrowdCodec, HitShapes,
Armory, Tuning, CrowdBrain, ThreatField, StrikeTally, CrowdService and VitalsService sources
with stubbed Roblox globals and runs the tests_*.luau cases under the plain luau interpreter.
P5 adds tests_p5.luau: the mission scales, kill info, KillAll, VitalsService.SetMission and
the pure PositionRing (the server's own reading of a player's speed).
L1 adds the pure rules of a run through a level: StageFlow (tests_l1.luau, with Combat and
Economy, which it is checked against) and LevelGeometry (tests_l1_world.luau). Combat.json is
injected as a FIXTURE, the way Armory.json is.
"The real files" (tests_l1.luau) runs those same rules on the data that ships: every level
file, layout and the map are injected as they stand, and tools/check_levels.py is asked for its
Part counts, so the Luau rules and the Python gate are held to one answer.
L1b adds the pure CampBrain (how a camp's resident groups rest, wake, chase and go home) and two
case files: tests_l1b_crowd.luau (CampBrain and CrowdService's floors and groups) and
tests_l1b.luau (StageFlow's open camps, checkpoints and clear field, Combat's per-kill split with
its carry, LevelGeometry's open camps and fire markers).
L1c adds the pure WallClip (the camera boom kept out of a locking camp, the ground point's height
rule) and tests_l1c.luau (it, and the walled Chief's Clearing as it ships). Its fix round reads two
lists out of source text, InputController's GROUND_AIMED and AbilityService's `target = "ground"`
mechanics (neither file loads here), and combat.project.json's CameraMaxZoomDistance, so the cases
can hold each to the other (FIXTURES.source). Its second fix round adds the pure StrikePick (which
of a strike's candidates it lands on and chains from, a held resident passed over).
L2 W1 adds the profile's v7 step (ProfileSchema, loaded as it stands: its Types require resolves
to the stub), the pure Unlocks (ownership, keys, the purchase) and SecretFlow (the chests), and
tests_l2.luau: those, WallClip.Rise per player, StageFlow's secrets lines and the shipped chests.
Its second fix round adds GroundRule (the ground point's movement and double-jump inputs, read
once for both callers) and scopes the ground-point source check to the two functions.
L2 W2 adds the pure WorldReact (a strike's segment against a reactive block, the heat) and
tests_l2w2.luau: Unlocks' owned families, element keys and set-family verdict, WorldReact,
SecretFlow's shortcuts, LevelGeometry.Pieces' open set, Validate's react, opens and shortcuts
lines, and a family's element as a structural Tuning path. Its fix round adds WorldReact's
StrikeElement, Apply and Wants, and reads as text the lines that act on them (Main's wiring,
finish()'s abandoned skip, LevelService.React) and aimAllowed's wall ray (`source.wiring`).
L2 W3 adds tests_l2w3.luau: WorldReact's Cells, Chills and Freeze, LevelGeometry.Pieces' ice cells,
Validate's ice and landing lines, Plan's waters with StageFlow.Landing and FallLanding, the shipped
creek crossed swing by swing, and as text (`source.w3`) LevelService.React's ice branch and its
freeze, the rescue's landing in WaveService and Frost Quake's launcher in AbilityService.
L3 W1 adds tests_l3.luau (the pure Armory ladder, windows, upgrade and refund, the profile's v8
step, Unlocks' saved loadout and stars, Armory.json as it ships), tests_l3_run.luau (StageFlow's
first clear) and tests_l3_ui.luau (the Armory screen's pure ArmoryModel, bundled with Format).
Its fix round adds the pure ProfileCopy (the hub's Delta copy) and reads as text (`source.l3`, the
L2 pattern) the service lines that apply L3's rules: the strike tier in WeaponService's hits, bar and
slam, the upgrade's gate, the first clear in EndRun and the U lever, the stars from the profile,
readLevel's Validate inputs, DebugService's wildcard and presets, both places' Power, the hub's copy,
DataService's runner and the hub's upgrade (L3_LINES, counted in the function each belongs to).
Its second fix round (docs/prompts/l3-w1-fix2.md F1, F2) also counts the lines that feed each
pinned call and the exits of the functions they live in (an early return cannot hide), reads the
count-0 rules on the code with its comments blanked and by pattern, so no other spelling passes
(L3_PATTERNS), and tests Unlocks.ApplyFirstClear and the lines that call it in both places.
L3 W2 adds the pure WeaponLook (the look's attributes, model entries, points, icon ids and their
faults) and tests_l3_w2.luau: those, on built inputs and on the shipped WeaponModels.json, and read
as text (`source.l3w2`, the L3 pattern) the contract's T1 to T14: WeaponService's attribute writer
and the slot in use, AbilityService's cast, the other player's arm, the one muzzle, HeldWeapons'
clone, seal and lookups, and the Armory stage's turn (L3W2_LINES, L3W2_PATTERNS, L3W2_ORDER).
Its fix round (docs/prompts/l3-w2-fix-round.md) counts every pinned text as whole lines with
their indentation (whole_lines), the exits after each noted line, every `held` read in the
server, the attribute names spelled anywhere under src, the three ways a character reaches
PrepareCharacter, and the client lines that tear down, re-show and drive the models and the stage.
Its second fix round (docs/prompts/l3-w2-fix2.md G1 to G3) pins the flush another player's swing
runs first (its first code line in T9's branch, before SwingOther), the order in Muzzle and a new
rig's first state, and that the stage hears no gamepad stick.
L4 W1b (docs/prompts/l4-w1b-contract.md) retires the C1 mission code: the Village mission, the
missions' and the arenas' fixtures and the Raider Arena's adapter go (the cases that used the arena
only as a fixture for a rule that stays play the hand-written L1W.field / L1.field instead), and
adds the pure DashProof (tests_l4b.luau: a dash's i-frames once the server's ring has seen it) and
RunFloors (tests_l4b_run.luau: RunState's region cells once per member per floor set).
It proves the logic, not Roblox behaviour. RangeService is not loadable here.

The cases are this folder's, and the sources the first argument's. So it refuses to run (exit 2,
`HARNESS: REFUSED`) when that root holds another copy of this harness: run_harness.py or a case
file that differs from the ones running, or is missing. Run from the main checkout against a
worktree it would otherwise run main's cases on the worktree's sources and could say PASS.

The verdict is always the last line, and names how many checks ran and from which folder, so a
count can be compared with the one its author reported:
  HARNESS: PASS (1,292 checks, <folder>)                  every case ran and passed
  HARNESS: FAIL (n of 1,292 checks, <folder>)             every case ran, n failed
  HARNESS: FAIL (stopped after 96 checks, <folder>)       the bundle stopped part way (a module
                                                          or a case threw): reported as one more
                                                          failing check, `FAIL  the bundle stopped`
  HARNESS: SILENT (no case ran, <folder>)                 no interpreter, or a bundle that does
                                                          not compile
  HARNESS: HUNG (stopped after 150 s, <folder>)
  HARNESS: REFUSED (another checkout's harness, <folder>)
Only PASS exits 0. tools/crowd_harness/mutate.py reads these lines.

Usage: py tools/crowd_harness/run_harness.py [repo root] [luau.exe]
(defaults: this repo, tools/bin/luau.exe, which tools/check_mirror.py fetches).
Importing this file runs nothing: `sources`, `wrap`, `fixtures`, `to_luau` and `prelude` are
there for another tool that wants the same modules under the same wrapper."""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TIMEOUT_SECONDS = 150

# The modules every bundle carries, by the name the cases load them under.
SOURCES = {
    "CrowdCodec": "src/shared/CrowdCodec.luau",
    "HitShapes": "src/shared/HitShapes.luau",
    # L1b Wave 4: the chase region (CrowdBrain, CampBrain, StageFlow and CampAim's renderer need it).
    "Region": "src/shared/Region.luau",
    "Economy": "src/shared/Economy.luau",
    "Armory": "src/shared/Armory.luau",
    "Combat": "src/shared/Combat.luau",
    "Tuning": "src/shared/Tuning.luau",
    "CrowdBrain": "src/combat/server/Services/CrowdBrain.luau",
    "ThreatField": "src/combat/server/Services/ThreatField.luau",
    "StrikeTally": "src/combat/server/Services/StrikeTally.luau",
    "PositionRing": "src/combat/server/Services/PositionRing.luau",
    "CrowdService": "src/combat/server/Services/CrowdService.luau",
    "VitalsService": "src/combat/server/Services/VitalsService.luau",
    "LevelGeometry": "src/combat/server/Services/LevelGeometry.luau",
    "SwingGate": "src/shared/SwingGate.luau",
    "CampBrain": "src/combat/server/Services/CampBrain.luau",
    "StageFlow": "src/combat/server/Services/StageFlow.luau",
    # L1b Wave 2: the client's pure reading of a spawn info (the lead's routing: tested here).
    "SpawnSeed": "src/combat/client/Controllers/SpawnSeed.luau",
    # The L1b Wave 2 fix round, ui-2: touch auto-target's camp rule (the ui-engineer's).
    "CampAim": "src/combat/client/Controllers/CampAim.luau",
    # L1c: the camera boom's clip and the ground point's height rule (tests_l1c.luau).
    "WallClip": "src/shared/WallClip.luau",
    # The L1c second fix round's F4: which candidates a strike lands on and chains from.
    "StrikePick": "src/combat/server/Services/StrikePick.luau",
    # L2 W1: the v7 step, the unlocks and the chests (tests_l2.luau).
    "ProfileSchema": "src/server/Services/ProfileSchema.luau",
    "Unlocks": "src/shared/Unlocks.luau",
    "SecretFlow": "src/combat/server/Services/SecretFlow.luau",
    # The L2 W1 second fix round's Minor 1: the ground point's inputs, read in one place.
    "GroundRule": "src/shared/GroundRule.luau",
    # L2 W2: the world's reactions (tests_l2w2.luau).
    "WorldReact": "src/shared/WorldReact.luau",
    # L3 W1: the Armory screen's pure model (tests_l3_ui.luau) and the number formatting it reads.
    "Format": "src/shared/Format.luau",
    "ArmoryModel": "src/client/UI/ArmoryModel.luau",
    # The L3 W1 fix round's R7: the hub's Delta copy of a combat profile, made pure.
    "ProfileCopy": "src/shared/ProfileCopy.luau",
    # L3 W2: what a player's weapons look like, read by the server and every client (tests_l3_w2.luau).
    "WeaponLook": "src/shared/WeaponLook.luau",
    # L4 W1b: a dash's proof against the server's ring (tests_l4b.luau) and RunState's floors sent
    # once per member per floor set (tests_l4b_run.luau).
    "DashProof": "src/combat/server/Services/DashProof.luau",
    "RunFloors": "src/shared/RunFloors.luau",
}
# One bundle, in this order: each file sees every local of the files before it. Only the last
# file's verdict line is kept, so the bundle prints one HARNESS line, after every case has run.
TESTS = [
    "tests.luau",
    "tests_w2.luau",
    "tests_s2.luau",
    "tests_s3.luau",
    "tests_p5.luau",
    "tests_l1_world.luau",
    "tests_l1.luau",
    "tests_l1b_crowd.luau",
    "tests_l1b.luau",
    "tests_l1b_w2_crowd.luau",
    "tests_l1b_w2.luau",
    # L1b Wave 4: the region, the chase and the pace tent in the crowd (A's), then the run's
    # regions, pace, Fielded and N (B's).
    "tests_l1b_w4_crowd.luau",
    "tests_l1b_w4.luau",
    # L1c: WallClip, then the walled Chief's Clearing as built and planned.
    "tests_l1c.luau",
    # L2 W1: the v7 step, Unlocks, SecretFlow, Rise per player, the shipped chests.
    "tests_l2.luau",
    # L2 W2: owned families, element keys, the set-family verdict, WorldReact, shortcuts,
    # Pieces' open set, Validate's react/opens/shortcuts lines, the element as structural.
    "tests_l2w2.luau",
    # L2 W3: Cells, Chills, Freeze, the ice pieces, Validate's ice and landing lines, Landing,
    # the shipped crossing, and the lines that act on them.
    "tests_l2w3.luau",
    # L3 W1: the ladder, the windows, the upgrade, the refund and profile v8, the saved loadout and
    # the shipped Armory.json (luau-engineer A's); the first clear (B's); the Armory screen's
    # pure model (ui-engineer A's).
    "tests_l3.luau",
    "tests_l3_run.luau",
    "tests_l3_ui.luau",
    # L3 W2: WeaponLook on built inputs and on the shipped WeaponModels.json, then T1 to T14 as text.
    "tests_l3_w2.luau",
    "tests_l4b.luau",
    "tests_l4b_run.luau",
]
VERDICT = 'print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)'
NUMBERED = r"\d+_"
# A case's line, as tests.luau's `check` prints it.
CHECK_LINE = re.compile(r"^\s+(ok|FAIL)\s")


def to_luau(value) -> str:
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{json.dumps(key)}] = {to_luau(item)}" for key, item in value.items()) + "}"
    if isinstance(value, (list, tuple)):
        return "{" + ", ".join(to_luau(item) for item in value) + "}"
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    return json.dumps(value)


def read(repo: Path, path: str) -> object:
    return json.loads((repo / path).read_text(encoding="utf-8"))


def read_optional(repo: Path, path: str) -> object:
    """A JSON file, or None when it is not there."""
    return read(repo, path) if (repo / path).is_file() else None


def read_folder(repo: Path, folder: str, numbered: bool = False) -> list:
    """Every JSON file of a folder as (stem, content). `numbered`: only the files Catalog reads
    there, those named <n>_<Name>, in its order: by that number, then by name."""
    def order(path: Path):
        prefix = re.match(r"\d+", path.stem)
        return (int(prefix.group()) if prefix else 0, path.stem)

    paths = sorted((repo / folder).glob("*.json"), key=order)
    if numbered:
        paths = [path for path in paths if re.match(NUMBERED, path.stem)]
    return [(path.stem, read(repo, f"{folder}/{path.name}")) for path in paths]


def gate_reading() -> dict:
    """What tools/check_levels.py makes of the layouts: its Part count for each (its `N Parts`
    lines). Always this checkout's files (the tool takes no root; a mutant root holds copies of the
    same data). Empty when the tool cannot be imported: the cases that need it then fail."""
    try:
        sys.path.insert(0, str(HERE.parent))
        import check_levels

        layouts = check_levels.load_all()[2]
        return {"parts": {name: check_levels.part_count(layout) for name, layout in layouts.items()}}
    except (Exception, SystemExit) as problem:  # the harness still runs, and says so
        print(f"run_harness: tools/check_levels.py could not be read ({problem!r})", file=sys.stderr)
        return {}


INPUT_CONTROLLER = "src/combat/client/Controllers/InputController.luau"
ABILITY_SERVICE = "src/combat/server/Services/AbilityService.luau"
WEAPON_SERVICE = "src/combat/server/Services/WeaponService.luau"
# The L2 W1 fix round's c4 and its second round's Minor 1: the ground point's step 4 is one call on
# both sides, GroundRule.Floor, which reads the movement heights and the double jump itself. A
# caller that calls WallClip.GroundFloor or its parts again, or reads an input of its own, holds a
# copy that can drift. Read inside each ground-point function only, so the rest of a file may use
# WallClip as it likes.
GROUND_RULE_CALL = re.compile(r"\bGroundRule\.Floor\(")
GROUND_FLOOR_CALL = re.compile(r"\bWallClip\.GroundFloor\(")
GROUND_PART_CALL = re.compile(r"\bWallClip\.(?:Rise|TooHigh|CasterFloor)\(")
GROUND_INPUT_READ = re.compile(r"\bGetAttribute\(|\bTuning\.Get\(|\.movement\b")
GROUND_POINT_BODY = {
    "client": re.compile(r"(?ms)^local function groundPoint\(.*?^end$"),
    "server": re.compile(r"(?ms)^function WeaponService\.GroundPoint\(.*?^end$"),
}
# The L2 W2 fix round's s-m1, s-m2 and d-m3: the service lines that act on WorldReact's and the
# aim rule's verdicts, read as text (none of these files loads here). Main wires the strike
# listener once; finish() tells the listeners only inside its `if not fx.abandoned` block;
# LevelService.React takes its element from WorldReact.StrikeElement (with the ability id, so an
# ability's strike burns nothing) and hands the loop to WorldReact.Apply, with no loop of its
# own; aimAllowed answers with WorldReact.AimClear (the second fix round's m1 and m2): from the
# head, and from the head carried by claimSlack's own speed and lag along its ring's way
# (WorldReact.LeadHead, the root's velocity only shortening it: the third fix round's m1), with
# shooting.originWallChord as the tolerance (its argument is read too: a copy of another number
# there left every gate green) and worldHit, whose ray goes through the world query every other
# one uses. claimSlack hands back PositionRing.Motion's way as it came.
MAIN_SERVER = "src/combat/server/Main.server.luau"
LEVEL_SERVICE = "src/combat/server/Services/LevelService.luau"
# A live line at the top level of Main (a commented-out one does not count).
REACT_WIRING = re.compile(r"(?m)^WeaponService\.OnStrikeResolved\(LevelService\.React\)[ \t]*$")
FINISH_BODY = re.compile(r"(?ms)^local function finish\(.*?^end$")
FINISH_GUARDED = re.compile(r"(?s)\n\tif not fx\.abandoned then\n(?:(?!\n\tend\n).)*?\bstate\.strikeListeners\b")
REACT_BODY = re.compile(r"(?ms)^function LevelService\.React\(.*?^end$")
REACT_ELEMENT = "local element = WorldReact.StrikeElement(config.weapons, weapon, abilityId)"
REACT_APPLY = "WorldReact.Apply(cells, element, fx, pad, need)"
REACT_OWN_LOOP = re.compile(r"\bWorldReact\.(?:Touches|Heat)\(|\.react\s*[~=]=")
AIM_BODY = re.compile(r"(?ms)^local function aimAllowed\(.*?^end$")
AIM_RAYS = (
    "local slack, speed, lag, motion = claimSlack(shooter, root, config.shooting.originPad, config)",
    "if distance > slack then",
    "local lead = WorldReact.LeadHead(anchor, motion, root.AssemblyLinearVelocity, speed, lag)",
    "WorldReact.AimClear(anchor, lead, origin, config.shooting.originWallChord, worldHit)",
    "\treturn clear\n",
)
CLAIM_BODY = re.compile(r"(?ms)^local function claimSlack\(.*?^end$")
CLAIM_LINES = (
    "local speed, motion = PositionRing.Motion(",
    "return math.max(pad, 0) + speed * lag, speed, lag, motion\n",
)
WORLD_HIT_BODY = re.compile(r"(?ms)^local function worldHit\(.*?^end$")
WORLD_HIT_LINES = (
    "local result = workspace:Raycast(from, to - from, worldParams())",
    "return if result ~= nil then result.Distance else nil",
)
# L2 W3: the lines that act on Freeze, FallLanding and Frost Quake, read as text. React sends a
# strike of ice to `freeze`; freeze hands the cells to WorldReact.Freeze, turns each frozen cell
# to floor (collides, met by rays, `Ice` true) and tells the listeners; rescueFallen asks
# StageFlow.FallLanding with player.rescue's outside and goes to its answer; Frost Quake is the
# Earthquake launcher's entry.
WAVE_SERVICE = "src/combat/server/Services/WaveService.luau"
FREEZE_BODY = re.compile(r"(?ms)^local function freeze\(.*?^end$")
RESCUE_BODY = re.compile(r"(?ms)^local function rescueFallen\(.*?^end$")
W3_LINES = {
    "reactIce": '\tif element == "ice" then\n\t\tfreeze(element, fx, rules)\n\t\treturn\n\tend\n',
    "reactFreeze": "freeze(element, fx, rules)",
    # The fix round's d-m5: the two numbers come from WorldReact.IceReach, and go to Freeze in
    # that order.
    "freezeReach": "local reachDown, ahead = WorldReact.IceReach(if rules ~= nil then rules.ice else nil)",
    # The second fix round's Q5: every body and the sink go with them.
    "freezeCall": "WorldReact.Freeze(cells, element, fx, reachDown, ahead, held, sink)",
    "freezeTold": "\t\tfor _, listener in state.reactedListeners do\n\t\t\tlistener(event)\n",
    # The fix round's s-M1: where the body last stood goes with where it is.
    "rescueStood": "local stood = WeaponService.LastGround(player)",
    "rescueLanding": "local landing = StageFlow.FallLanding(plan, flow, root.Position, stood, rescue.outside)",
    "rescueTarget": "\t\t\tif landing ~= nil then\n\t\t\t\ttarget = landing\n",
    "quakeAlias": "MECHANICS.frostQuake = MECHANICS.earthquake",
}
# The fix round's s-m1: a frozen cell is shown by `showIce` with WorldReact.IceLook's floor.
FREEZE_SHOW = "showIce(entry.part, WorldReact.IceLook(true, entry.shown))"
# The W3 fix round (s-m1, s-s3, d-m5, s-M1, c-m3, Q2): the lines that apply the pure answers
# (WorldReact.IceLook, Reactive, ICE_ATTRIBUTE, SwingStrike; LevelGeometry.SizesOf), read in the one
# function each belongs to. showIce sets the five properties from the look; construct shows a cell
# as water, gives it the ground's grip and lists a block by WorldReact.Reactive; React reads no
# count before its element; LevelService's sizesOf is LevelGeometry.SizesOf's first answer and both
# builds use it; trackAir records the stood point on the footprint floor's grounded verdict,
# ForgetMotion and resetAir clear it and LastGround answers it; resolveMelee builds its strike with
# WorldReact.SwingStrike and sends it to finish() as built.
SHOW_ICE_BODY = re.compile(r"(?ms)^local function showIce\(.*?^end$")
SHOW_ICE_LINES = (
    "\tpart.Transparency = look.transparency\n",
    "\tpart.CanCollide = look.collide\n",
    "\tpart.CanQuery = look.collide\n",
    "\tpart.CastShadow = look.shadow\n",
    "\tpart:SetAttribute(WorldReact.ICE_ATTRIBUTE, look.frozen)\n",
)
CONSTRUCT_BODY = re.compile(r"(?ms)^local function construct\(.*?^end$")
GRIP_BODY = re.compile(r"(?ms)^local function gripOf\(.*?^end$")
SIZES_BODY = re.compile(r"(?ms)^local function sizesOf\(.*?^end$")
OWN_ICE_ATTRIBUTE = re.compile(r'"Ice"|\bICE_ATTRIBUTE\s*=')
W3_FIX_LINES = {
    "constructWater": "showIce(part, WorldReact.IceLook(false, shown))",
    "constructGripAsk": "grip = gripOf(looks)",
    "constructGrip": "part.CustomPhysicalProperties = grip",
    "constructReactive": 'if react ~= nil and piece.role == "block" and WorldReact.Reactive(react) then',
    "gripLook": "looks[CONST.GRIP_LOOK]",
    "gripReturn": "return PhysicalProperties.new(material)",
    "gripConst": 'GRIP_LOOK = "ground",',
    "sizesCall": "local sizes, iceRefused = LevelGeometry.SizesOf(expeditions, rules)",
    "sizesReturn": "\treturn sizes\n",
    "sizesUsed": "= sizesOf(expeditions, rules)",
    "trackStood": "\t\tif footing ~= nil and not SwingGate.IsAir(position.Y - footing, offset) then\n\t\t\tshooter.stood = position\n",
    "stoodCleared": "shooter.stood = nil",
    "lastGround": "return if shooter ~= nil then shooter.stood else nil",
    "meleeSwing": "local swing = WorldReact.SwingStrike(variant, step, origin, heading, airSwing)",
}
TRACK_AIR_BODY = re.compile(r"(?ms)^local function trackAir\(.*?^end$")
RESET_AIR_BODY = re.compile(r"(?ms)^local function resetAir\(.*?^end$")
FORGET_BODY = re.compile(r"(?ms)^function WeaponService\.ForgetMotion\(.*?^end$")
LAST_GROUND_BODY = re.compile(r"(?ms)^function WeaponService\.LastGround\(.*?^end$")
MELEE_BODY = re.compile(r"(?ms)^local function resolveMelee\(.*?^end$")
# The fix round's c-m3, client half (the client agent's report, fix-client.md): the three client
# copies of a swing's strike are WorldReact.SwingStrike's, read inside the function each lives in,
# and handed on as built (the frost ghost and puff, the phone's auto-swing at water with only its
# arc cut to controls.iceAutoDegrees, the early hitbox effect).
FROST_FX = "src/combat/client/Controllers/FrostFx.luau"
FEEDBACK = "src/combat/client/Controllers/FeedbackController.luau"
CLIENT_STRIKES = {
    "frost": (
        FROST_FX,
        re.compile(r"(?ms)^function FrostFx\.OnSwing\(.*?^end$"),
        "local strike = WorldReact.SwingStrike(\n\t\tswing.variant,\n\t\tswing.step,\n\t\tswing.origin,\n"
        "\t\tswing.heading,\n\t\tswing.airSwing\n\t)",
        ("ReactFx.PredictFreeze(strike, swing.seq)",),
    ),
    "phone": (
        INPUT_CONTROLLER,
        re.compile(r"(?ms)^local function autoIceStrike\(.*?^end$"),
        "local strike = WorldReact.SwingStrike(variant, step, origin, heading, airborne)",
        ("strike.arcDegrees = math.min(arc, cone)", "\treturn strike\n"),
    ),
    "hitbox": (
        FEEDBACK,
        re.compile(r"(?ms)^function FeedbackController\.PredictSwing\(.*?^end$"),
        "local predicted =\n\t\tWorldReact.SwingStrike(variant, swing.step, swing.origin, swing.heading, swing.airSwing)",
        (
            "local shape = predicted.shape\n",
            "origin = predicted.origin,",
            "direction = predicted.direction,",
            "size = predicted.size,",
            "arcDegrees = predicted.arcDegrees,",
            "width = predicted.width,",
        ),
    ),
}
# The strike's geometry, each line once: the locals the candidates use and finish()'s fields.
MELEE_FX_LINES = (
    "local arcDegrees = swing.arcDegrees\n",
    "local range = swing.size\n",
    "local shape: Types.HitShape = swing.shape\n",
    "width = swing.width or 0,",
    "shape = swing.shape,",
    "origin = swing.origin,",
    "direction = swing.direction,",
    "size = swing.size,",
    "arcDegrees = swing.arcDegrees,",
    "width = swing.width,",
)
# The W3 second fix round (docs/prompts/l2-w3-fix2.md, Q5): the lines that hand the pure rules a
# swing's air verdict and every body, read in the one function each belongs to. OnAttack passes
# SwingGate's own verdict to resolveMelee, which builds its strike with it and sends it on; freeze
# reads the sink and hands every body and it to Freeze; LevelService's bodies and ReactFx.Bodies
# read each player's character through WorldReact.BodyBox; the ghost (ReactFx.PredictFreeze) and
# the phone (InputController.iceOnAuto) skip a held cell with the server's sink; the predicted
# swing carries AirSwing's verdict to the ghost and the early hitbox.
REACT_FX = "src/combat/client/Controllers/ReactFx.luau"
ATTACK_BODY = re.compile(r"(?ms)^function WeaponService\.OnAttack\(.*?^end$")
ATTACK_PASS = re.compile(
    r"resolveMelee\(\s*config,\s*shooter,\s*weapon,\s*variantKey,\s*variant,\s*root,\s*seq,\s*swingAt,\s*direction,"
    r"\s*airSwing\s*\)"
)
BODY_BOX_CALL = re.compile(
    r"WorldReact\.BodyBox\(\s*root\.Position,\s*root\.CFrame\.RightVector,\s*root\.Size,\s*humanoid\.HipHeight\s*\)"
)
# The W3 third fix round's fd-m2: the server's call hands BodyBox the falling body's lead too.
BODY_BOX_LED = re.compile(
    r"WorldReact\.BodyBox\(\s*root\.Position,\s*root\.CFrame\.RightVector,\s*root\.Size,\s*humanoid\.HipHeight,"
    r"\s*drop\s*\)"
)
BODIES_BODY = {
    "server": (LEVEL_SERVICE, re.compile(r"(?ms)^local function bodies\(.*?^end$"), BODY_BOX_LED),
    "client": (REACT_FX, re.compile(r"(?ms)^function ReactFx\.Bodies\(.*?^end$"), BODY_BOX_CALL),
}
GHOST_BODY = re.compile(r"(?ms)^function ReactFx\.PredictFreeze\(.*?^end$")
SINK_BODY = re.compile(r"(?ms)^function ReactFx\.IceSink\(.*?^end$")
PHONE_BODY = re.compile(r"(?ms)^local function iceOnAuto\(.*?^end$")
RANGE_ATTACK_BODY = re.compile(r"(?ms)^local function rangeAttack\(.*?^end$")
W3_FIX2_LINES = {
    "attackJudge": "allowed, airSwing = SwingGate.Judge(shooter.airSwing, swingAt.Y, floorY, standOffset, lag)",
    "meleeAir": "\tairSwing: boolean\n): ()",
    "finishAir": "\t\tairborne = swing.airborne,\n",
    "freezeSink": "local sink = WorldReact.IceSink(if rules ~= nil then rules.ice else nil)",
    "freezeHeld": "local held = if sink ~= nil then bodies() else nil",
    "players": "for _, player in Players:GetPlayers() do",
    "ghostSink": "local sink = ReactFx.IceSink()",
    "ghostHolds": "if not WorldReact.Holds(box, around, sink) then",
    "phoneHolds": "return not WorldReact.Holds(box, around, ReactFx.IceSink())",
    "phoneGround": "WorldReact.SwingStrike(variant, step, origin, heading, airborne)",
    "predictedAir": "airSwing = swingAirborne,",
    "swingAir": "swing.airSwing",
    "sinkReader": "return WorldReact.IceSink(if react ~= nil then react.ice else nil)",
}
# The W3 third fix round (docs/prompts/l2-w3-fix3.md): fd-m2, the server leads a falling body's feet
# by its fall over its commit lag (LevelService's bodies, from WeaponService.FallSpeed, which
# trackAir measures and a server move or a fresh body clears); fd-s1, the phone's ice auto-swing
# asks AirSwing.Judge (the server's question) and refuses an air swing, its strikes carrying the
# verdict, the Humanoid's floor sensor no longer asked.
FALL_SPEED_BODY = re.compile(r"(?ms)^function WeaponService\.FallSpeed\(.*?^end$")
W3_FIX3_LINES = {
    "bodiesFastest": "local fastest = Tuning.FastestMove(config)",
    "bodiesFall": "local fall = WeaponService.FallSpeed(player)",
    "bodiesLag": "local lag = Tuning.CommitLag(config.shooting, player:GetNetworkPing())",
    "bodiesDrop": "then WorldReact.FallDrop(fall, lag, Workspace.Gravity, fastest)",
    "bodiesStands": "else 0",
    "trackFall": "shooter.fall = if shooter.stood == position then nil else math.max(fallSpeed, 0)",
    "fallCleared": "shooter.fall = nil",
    "fallAnswer": "return if shooter ~= nil then shooter.fall else nil",
    "phoneJudge": "local allowed, inAir = AirSwing.Judge(origin, rig.root, rig.humanoid)",
    "phoneRefuse": "if not allowed or inAir then",
    "phoneCarry": "cone, inAir)",
    "phoneHumanoid": "MovementController.IsAirborne",
}
COMBAT_PROJECT = "combat.project.json"
# The L3 W1 fix round (docs/prompts/l3-w1-fix-round.md R3, R4, R5, R7, 3-s2): the service lines that
# apply L3's pure rules. None of these services loads here, so each line is counted as text in the
# one function it belongs to (None = the whole file), and tests_l3.luau holds each count to its
# expected value: a call site that stops calling the rule, or calls it with other inputs, fails.
UNLOCK_SERVICE = "src/combat/server/Services/UnlockService.luau"
DEBUG_SERVICE = "src/combat/server/Services/DebugService.luau"
HUB_ECONOMY = "src/server/Services/EconomyService.luau"
HUB_DATA = "src/server/Services/DataService.luau"
HUB_ARMORY = "src/server/Services/ArmoryService.luau"
# F5: the hub's client replays the Armory push once the weapon families come (UIController's boot).
HUB_UI = "src/client/Controllers/UIController.luau"
L3_BODIES = {
    "gearOf": (WEAPON_SERVICE, re.compile(r"(?ms)^local function gearOf\(.*?^end$")),
    "damageScale": (WEAPON_SERVICE, re.compile(r"(?ms)^local function damageScale\(.*?^end$")),
    "onSlam": (WEAPON_SERVICE, re.compile(r"(?ms)^function WeaponService\.OnSlam\(.*?^end$")),
    "onUpgrade": (UNLOCK_SERVICE, re.compile(r"(?ms)^function UnlockService\.OnUpgradeWeapon\(.*?^end$")),
    "grantFirstClear": (UNLOCK_SERVICE, re.compile(r"(?ms)^function UnlockService\.GrantFirstClear\(.*?^end$")),
    "endRun": (WAVE_SERVICE, re.compile(r"(?ms)^function WaveService\.EndRun\(.*?^end$")),
    "starsOf": (WAVE_SERVICE, re.compile(r"(?ms)^local function starsOf\(.*?^end$")),
    "readLevel": (WAVE_SERVICE, re.compile(r"(?ms)^local function readLevel\(.*?^end$")),
    "grantStars": (WAVE_SERVICE, re.compile(r"(?ms)^function WaveService\.GrantStars\(.*?^end$")),
    "nextGear": (DEBUG_SERVICE, re.compile(r"(?ms)^local function nextGear\(.*?^end$")),
    "setGear": (DEBUG_SERVICE, re.compile(r"(?ms)^local function setGear\(.*?^end$")),
    "grantStar": (DEBUG_SERVICE, re.compile(r"(?ms)^local function grantStar\(.*?^end$")),
    "mainSnapshot": (MAIN_SERVER, re.compile(r"(?ms)^local function sendSnapshot\(.*?^end$")),
    "hubPower": (HUB_ECONOMY, re.compile(r"(?ms)^local function computeGearPower\(.*?^end$")),
    "runMigrations": (HUB_DATA, re.compile(r"(?ms)^local function runMigrations\(.*?^end$")),
    "attemptLoad": (HUB_DATA, re.compile(r"(?ms)^local function attemptLoad\(.*?^end$")),
    "hubUpgrade": (HUB_ARMORY, re.compile(r"(?ms)^local function tryUpgradeWeapon\(.*?^end$")),
    "hubStar": (HUB_ARMORY, re.compile(r"(?ms)^local function grantStarTo\(.*?^end$")),
    "hubFileReward": (HUB_ARMORY, re.compile(r"(?ms)^local function fileFirstClear\(.*?^end$")),
    "uiKeys": (HUB_UI, re.compile(r"(?ms)^\tlocal function refreshCombatKeys\(.*?^\tend$")),
    "uiPush": (HUB_UI, re.compile(r"(?ms)^\tpushArmory = function\(.*?^\tend$")),
}
# The ascension a hit and the bar read: the override's, else the profile's, else none (both bodies).
ASCENSION_READ = ("local ascension = if override ~= nil\n\t\tthen override.ascension\n"
                  "\t\telseif combat ~= nil then combat.ascension\n\t\telse CONST.NO_ASCENSION")
# The profile a hit and the bar read (both bodies; the review's m1 probes set `combat` to nil).
PROFILE_READ = "local profile = DataService.GetState(player)\n\tlocal combat = if profile ~= nil then profile.combat else nil"
# key: (file, body or None for the whole file, the exact text). The expected counts are the cases'.
L3_LINES = {
    # R3: hits and the bar take the strike tier (luau-engineer B's lines), the slam the held melee family.
    "strikeTierCalls": (WEAPON_SERVICE, None, "Armory.StrikeTier("),
    "gearMelee": (WEAPON_SERVICE, "gearOf", "melee = Armory.StrikeTier(armoryConfig, combat, held.melee, meleeOverride),"),
    "gearRanged": (WEAPON_SERVICE, "gearOf", "ranged = Armory.StrikeTier(armoryConfig, combat, held.ranged, rangedOverride),"),
    "gearMeleeOverride": (WEAPON_SERVICE, "gearOf", "local meleeOverride = if gear ~= nil then gear.melee else nil"),
    "gearRangedOverride": (WEAPON_SERVICE, "gearOf", "local rangedOverride = if gear ~= nil then gear.ranged else nil"),
    # F1: what feeds the bar's two StrikeTier calls, in gearOf.
    "gearConfig": (WEAPON_SERVICE, "gearOf", "local armoryConfig = Catalog.GetArmoryConfig()\n"
                   "\tif state.mode == \"range\" or armoryConfig == nil then\n"
                   "\t\treturn table.clone(CONST.RANGE_GEAR), table.clone(CONST.NO_ASCENSION)\n\tend\n"),
    "gearProfile": (WEAPON_SERVICE, "gearOf", PROFILE_READ),
    "gearHeld": (WEAPON_SERVICE, "gearOf", "local shooter = state.shooters[player]\n\tlocal config = Tuning.Get()\n"
                 "\tlocal held = if shooter ~= nil\n\t\tthen shooter.loadout\n"
                 "\t\telse Unlocks.LoadoutOf(combat, config.weapons, {\n"
                 "\t\t\tmelee = startingFamily(config, \"melee\"),\n"
                 "\t\t\tranged = startingFamily(config, \"ranged\"),\n\t\t})\n"),
    "gearOverrideRead": (WEAPON_SERVICE, "gearOf", "local override = state.gearOverride[player]\n"
                         "\tlocal gear = if override ~= nil then override.gear else nil\n"),
    "gearAscension": (WEAPON_SERVICE, "gearOf", ASCENSION_READ),
    "gearAscensionOut": (WEAPON_SERVICE, "gearOf", "\t}, { melee = ascension.melee, ranged = ascension.ranged }\n"),
    "scaleTier": (WEAPON_SERVICE, "damageScale", "local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)"),
    "scaleMelee": (WEAPON_SERVICE, "damageScale", "\t\t\tthen gear.melee\n"),
    "scaleRanged": (WEAPON_SERVICE, "damageScale", 'elseif slot == "ranged" then gear.ranged'),
    "scaleReturn": (WEAPON_SERVICE, "damageScale", "return Armory.DamageScale(armoryConfig, tier, level, ability)"),
    # F1: what feeds a hit's StrikeTier and DamageScale, in damageScale.
    "scaleGuards": (WEAPON_SERVICE, "damageScale", "\tif state.mode == \"range\" then\n\t\treturn 1\n\tend\n"
                    "\tlocal armoryConfig = Catalog.GetArmoryConfig()\n\tif armoryConfig == nil then\n\t\treturn 1\n\tend\n"),
    "scaleSlot": (WEAPON_SERVICE, "damageScale", "local def = familyDef(Tuning.Get(), family)\n"
                  "\tlocal slot = if def ~= nil then def.slot else \"\"\n"),
    "scaleProfile": (WEAPON_SERVICE, "damageScale", PROFILE_READ),
    "scaleOverrideRead": (WEAPON_SERVICE, "damageScale", "local override = state.gearOverride[player]\n"
                          "\tlocal overrideTier: number? = nil\n\tif override ~= nil then\n"
                          "\t\tlocal gear = override.gear\n\t\toverrideTier = if slot == \"melee\"\n"),
    "scaleAscension": (WEAPON_SERVICE, "damageScale", ASCENSION_READ),
    "scaleLevel": (WEAPON_SERVICE, "damageScale", "local level = if slot == \"melee\"\n\t\tthen ascension.melee\n"
                   "\t\telseif slot == \"ranged\" then ascension.ranged\n\t\telse 0\n"),
    "slamFamily": (WEAPON_SERVICE, "onSlam", "StrikeTally.New(damageScale(player, shooter.loadout.melee, false))"),
    # R3: the combat place's upgrade is gated on MayLeave and owns through the starters.
    "upgradeGate": (UNLOCK_SERVICE, "onUpgrade", "\t\tgate ~= nil and gate(player),\n"),
    "upgradeOwned": (UNLOCK_SERVICE, "onUpgrade", "Unlocks.OwnsFamily(combat.families, family, starters()),"),
    # F2: the dungeon's first clear is the pure Unlocks.ApplyFirstClear on the player's own profile.
    "grantProfile": (UNLOCK_SERVICE, "grantFirstClear", "local profile = DataService.GetState(player)\n"
                     "\tif profile == nil then\n\t\treturn nil\n\tend\n\tlocal combat = profile.combat\n"),
    "grantApply": (UNLOCK_SERVICE, "grantFirstClear",
                   "local given = Unlocks.ApplyFirstClear(combat, reward, weapons(), starters())"),
    "grantNothing": (UNLOCK_SERVICE, "grantFirstClear", "\tif given.family == nil and given.valor == 0 then\n"
                     "\t\treturn nil\n\tend\n"),
    "grantSent": (UNLOCK_SERVICE, "grantFirstClear", "\tArenaService.SendSnapshot(player)\n\treturn given\n"),
    # R3 (L3-17): a new star's first-clear reward in EndRun; R4: the U lever pays the same way.
    "endRunReward": (WAVE_SERVICE, "endRun", "local reward = if star then StageFlow.FirstClear(level, plan.difficulty) else nil"),
    "endRunGrant": (WAVE_SERVICE, "endRun", "local given = if reward ~= nil then UnlockService.GrantFirstClear(player, reward) else nil"),
    "grantFirstClearCalls": (WAVE_SERVICE, None, "UnlockService.GrantFirstClear("),
    "starsProfile": (WAVE_SERVICE, "starsOf", "if profile ~= nil then\n\t\treturn Unlocks.StarsOf(profile.combat)"),
    "readLevelInputs": (WAVE_SERVICE, "readLevel", "\t\ttuned.weapons,\n\t\tUnlocks.Starters(tuned.loadout)\n\t)"),
    "leverAward": (WAVE_SERVICE, "grantStars", "if not StageFlow.Award(stars, levelId, difficulty) then"),
    # F3: the level is resolved first, and one that does not resolve gets neither star nor reward.
    "leverInputs": (WAVE_SERVICE, "grantStars", "local combatConfig = config()\n"
                    "\tlocal map = Catalog.GetExpeditionsConfig()\n\tlocal stars = starsOf(player.UserId)\n"),
    "leverLevel": (WAVE_SERVICE, "grantStars", "local level = if combatConfig ~= nil and map ~= nil\n"
                   "\t\t\tthen resolveLevel(levelId, difficulty, combatConfig, map)\n\t\t\telse nil\n"
                   "\t\tif level == nil then\n\t\t\tcontinue\n\t\tend\n"
                   "\t\tif not StageFlow.Award(stars, levelId, difficulty) then\n"),
    "leverReward": (WAVE_SERVICE, "grantStars", "local reward = StageFlow.FirstClear(level, difficulty)"),
    "leverGrant": (WAVE_SERVICE, "grantStars", "local grant = if reward ~= nil then UnlockService.GrantFirstClear(player, reward) else nil"),
    "leverGrants": (WAVE_SERVICE, "grantStars", "\t\tif grant ~= nil then\n\t\t\ttable.insert(grants, grant)\n\t\tend\n"),
    "leverStudio": (WAVE_SERVICE, "grantStars", "if not boot.mission or not RunService:IsStudio() then"),
    # 3-s2 and 2-s1 in the combat place's levers.
    "debugAllStars": (DEBUG_SERVICE, None, "if which == Unlocks.ALL_STARS then"),
    "debugNextGear": (DEBUG_SERVICE, "nextGear", "local gear = WeaponService.GearOverride(player) or WeaponService.GearOf(player)"),
    "debugSetGear": (DEBUG_SERVICE, "setGear", "local gear = WeaponService.GearOverride(target) or fought"),
    # F1: the star lever's difficulty, levels and players, and its call, in grantStar.
    "debugLadder": (DEBUG_SERVICE, "grantStar", "local armoryConfig = Catalog.GetArmoryConfig()\n"
                    "\tlocal ladder = if armoryConfig ~= nil then armoryConfig.ladder else nil\n\tif ladder == nil then\n"),
    "debugLevels": (DEBUG_SERVICE, "grantStar", "\tif which == Unlocks.ALL_STARS then\n\t\tlevelIds = builtBands()\n"
                    "\telseif Catalog.GetLevelFile(which) ~= nil then\n\t\ttable.insert(levelIds, which)\n"
                    "\tend\n\tif #levelIds == 0 then\n"),
    "debugDifficulty": (DEBUG_SERVICE, "grantStar", "\tlocal difficulty = ladder.starDifficulty\n"),
    "debugTargets": (DEBUG_SERVICE, "grantStar",
                     "local targets: { Player } = if player ~= nil then { player } else UnlockService.Admitted()"),
    "debugGrant": (DEBUG_SERVICE, "grantStar", "local _new, grants = WaveService.GrantStars(target, levelIds, difficulty)"),
    # R7: both places show the saved pair's Power; the hub's Delta carries the pure copy. F1: and each
    # place hands SavedPower its own profile and ProvingGrounds.json's weapons and starters.
    "mainPower": (MAIN_SERVER, "mainSnapshot", "then Armory.SavedPower(\n\t\t\t\tarmoryConfig,\n\t\t\t\tstate.combat,\n"),
    "mainArmory": (MAIN_SERVER, "mainSnapshot", "\tlocal armoryConfig = Catalog.GetArmoryConfig()\n"),
    "mainProving": (MAIN_SERVER, "mainSnapshot", "\tlocal provingConfig = Catalog.GetProvingGroundsConfig()\n"),
    "mainWeapons": (MAIN_SERVER, "mainSnapshot", "\t\t\t\tif provingConfig ~= nil then provingConfig.weapons else nil,\n"),
    "mainStarters": (MAIN_SERVER, "mainSnapshot",
                     "\t\t\t\tif provingConfig ~= nil then provingConfig.loadout else { melee = \"\", ranged = \"\" }\n"),
    "hubPower": (HUB_ECONOMY, "hubPower", "return Armory.SavedPower(\n\t\tarmoryConfig,\n\t\tstate.combat,\n"),
    "hubArmory": (HUB_ECONOMY, "hubPower", "\tlocal armoryConfig = Catalog.GetArmoryConfig()\n"
                  "\tif armoryConfig == nil then\n\t\treturn 0\n\tend\n"),
    "hubProving": (HUB_ECONOMY, "hubPower", "\tlocal provingConfig = Catalog.GetProvingGroundsConfig()\n"),
    "hubWeapons": (HUB_ECONOMY, "hubPower", "\t\tif provingConfig ~= nil then provingConfig.weapons else nil,\n"),
    "hubStarters": (HUB_ECONOMY, "hubPower",
                    "\t\tif provingConfig ~= nil then provingConfig.loadout else { melee = \"\", ranged = \"\" }\n"),
    "hubPowerSent": (HUB_ECONOMY, None, "gearPower = computeGearPower(state)"),
    "hubCopy": (HUB_ECONOMY, None, "delta.combat = ProfileCopy.Combat(state.combat)"),
    # R5: DataService runs the one runner, and F1: a load reaches it (a statement of attemptLoad's own).
    "runnerCall": (HUB_DATA, "runMigrations", "local verdict = ProfileSchema.Run(state)"),
    # Held between its neighbours, so nothing can be wrapped round it unseen.
    "loadMigrates": (HUB_DATA, "attemptLoad", "profile:Reconcile() -- fill fields added to the template since this"
                     " profile was created\n\trunMigrations(profile.Data, player)\n\t-- Before the profile is published"),
    # The hub's upgrade: its gate is open (no fight) and it owns through the starters; 3-s2 there too.
    "hubUpgradeCall": (HUB_ARMORY, "hubUpgrade", "Armory.Upgrade(armoryConfig, state.combat, family, owned, true, built)"),
    "hubUpgradeOwned": (HUB_ARMORY, "hubUpgrade", "local owned = Unlocks.OwnsFamily(state.combat.families, family, starters)"),
    "hubAllStars": (HUB_ARMORY, None, "if value == Unlocks.ALL_STARS then"),
    # F2: the hub's star lever pays a NEW star's first clear, read from the level file, through
    # Unlocks.ApplyFirstClear on the player's profile, and marks the profile for the Delta.
    "hubStarLevels": (HUB_ARMORY, "hubStar", "\tlocal armoryConfig = Catalog.GetArmoryConfig()\n"
                      "\tlocal ladder = if armoryConfig ~= nil then armoryConfig.ladder else nil\n"
                      "\tif armoryConfig == nil or ladder == nil or typeof(value) ~= \"string\" then\n"
                      "\t\treturn\n\tend\n\tlocal levels: { string } = {}\n"
                      "\tif value == Unlocks.ALL_STARS then\n\t\tlevels = (Armory.BuiltBands(armoryConfig, built))\n"
                      "\telseif built[value] == true then\n\t\tlevels = { value }\n\tend\n\tif #levels == 0 then\n"),
    "hubStarInputs": (HUB_ARMORY, "hubStar", "\tlocal difficulty = ladder.starDifficulty\n"
                      "\tlocal weapons, starters = weaponsConfig()\n\tlocal stars = Unlocks.StarsOf(state.combat)\n"),
    "hubStarNew": (HUB_ARMORY, "hubStar", "\t\tif row[difficulty] == true then\n\t\t\tcontinue\n\t\tend\n"
                   "\t\trow[difficulty] = true\n\t\tlocal reward = fileFirstClear(levelId, difficulty)\n"
                   "\t\tif reward == nil then\n\t\t\tcontinue\n\t\tend\n"),
    "hubStarApply": (HUB_ARMORY, "hubStar",
                     "local grant = Unlocks.ApplyFirstClear(state.combat, reward, weapons, starters)"),
    "hubStarDirty": (HUB_ARMORY, "hubStar", "\tEconomyService.MarkDirty(player, { combat = true })\n"),
    "hubStarValor": (HUB_ARMORY, "hubStar", "\t\tvalor += grant.valor\n"),
    "hubFileRead": (HUB_ARMORY, "hubFileReward", "\tlocal file = Catalog.GetLevelFile(levelId)\n"
                    "\tlocal difficulties: any = if file ~= nil then file.difficulties else nil\n"
                    "\tlocal scales: any = if type(difficulties) == \"table\" then difficulties[difficulty] else nil\n"
                    "\tlocal reward: any = if type(scales) == \"table\" then scales.firstClear else nil\n"
                    "\treturn if type(reward) == \"table\" then reward else nil\n"),
    # F5: the first refresh that finds the families pushes the model's profile; a push before them asks.
    "uiWaiting": (HUB_UI, "uiKeys", "\t\tlocal waiting = provingConfig == nil\n"),
    "uiReplay": (HUB_UI, "uiKeys", "\t\t\twaiting\n\t\t\tand provingConfig ~= nil\n\t\t\tand current ~= nil\n"
                 "\t\t\tand isCombatProfile(current.state.combat)\n\t\tthen\n\t\t\tpushArmory(current.state.combat)\n"),
    "uiPushWaits": (HUB_UI, "uiPush", "\t\tlocal config = provingConfig\n\t\tif config == nil then\n"
                    "\t\t\trefreshCombatKeys()\n\t\t\treturn\n\t\tend\n"),
}
# F1: the rules read by pattern, on the code with its comments blanked (luau_code): what must not be
# spelled at all, in any spelling, and every exit (`return`, `continue`, `break`) of a body that a
# pinned call lives in, so an early way out cannot hide behind lines that are all still there.
# key: (file, body or None, the pattern). The expected counts are the cases', with L3_LINES'.
LITERAL_STAR = re.compile(r"\"\*\"|'\*'|`\*`|\[(=*)\[\*\]\1\]")
EXITS = re.compile(r"\b(?:return|continue|break)\b")
L3_PATTERNS = {
    "debugLiteral": (DEBUG_SERVICE, None, LITERAL_STAR),
    "hubLiteral": (HUB_ARMORY, None, LITERAL_STAR),
    "mainGearOf": (MAIN_SERVER, None, re.compile(r"\bGearOf\b")),
    # `.gear` or `["gear"]` (never `..` before a local named gear).
    "hubFrozenGear": (HUB_ECONOMY, None, re.compile(r"(?<![.])\.\s*gear\b|\[\s*([\"'`])gear\1\s*\]")),
    "runnerSteps": (HUB_DATA, None, re.compile(r"\bMigrations\b")),
    "gearExits": (WEAPON_SERVICE, "gearOf", EXITS),
    "scaleExits": (WEAPON_SERVICE, "damageScale", EXITS),
    "grantExits": (UNLOCK_SERVICE, "grantFirstClear", EXITS),
    "leverExits": (WAVE_SERVICE, "grantStars", EXITS),
    "debugStarExits": (DEBUG_SERVICE, "grantStar", EXITS),
    "mainSnapshotExits": (MAIN_SERVER, "mainSnapshot", EXITS),
    "hubPowerExits": (HUB_ECONOMY, "hubPower", EXITS),
    "loadExits": (HUB_DATA, "attemptLoad", EXITS),
    "hubStarExits": (HUB_ARMORY, "hubStar", EXITS),
    "hubFileExits": (HUB_ARMORY, "hubFileReward", EXITS),
}
LONG_BRACKET = re.compile(r"\[(=*)\[")


def luau_code(source: str) -> str:
    """`source` with every comment blanked (its newlines kept) and every string kept: what
    L3_PATTERNS reads, so a comment that names a spelling never counts, and no spelling can hide
    in a string the code runs (`WeaponService["GearOf"]`, `combat["gear"]`)."""
    out = []
    i, n = 0, len(source)
    while i < n:
        if source.startswith("--", i):
            opened = LONG_BRACKET.match(source, i + 2)
            if opened:
                close = source.find("]" + opened.group(1) + "]", opened.end())
                end = n if close < 0 else close + len(opened.group(1)) + 2
            else:
                newline = source.find("\n", i)
                end = n if newline < 0 else newline
            out.append(re.sub(r"[^\n]", " ", source[i:end]))
            i = end
            continue
        opened = LONG_BRACKET.match(source, i)
        if opened:
            close = source.find("]" + opened.group(1) + "]", opened.end())
            end = n if close < 0 else close + len(opened.group(1)) + 2
            out.append(source[i:end])
            i = end
            continue
        quote = source[i]
        if quote in "\"'`":
            j = i + 1
            while j < n and source[j] != quote and source[j] != "\n":
                j += 2 if source[j] == "\\" else 1
            out.append(source[i:j + 1])
            i = j + 1
            continue
        out.append(quote)
        i += 1
    return "".join(out)


def l3_reading(text) -> dict:
    """The L3 W1 fix rounds' lines (L3_LINES, exact text) and patterns (L3_PATTERNS, on luau_code),
    each counted in the function it belongs to. `found` names the functions whose body was found;
    `text` reads a repo file (empty when missing)."""
    bodies = {}
    for key, (rel, pattern) in L3_BODIES.items():
        found = pattern.search(text(rel))
        bodies[key] = found.group(0) if found else None
    counts = {}
    for key, (rel, body, line) in L3_LINES.items():
        source = text(rel) if body is None else (bodies[body] or "")
        counts[key] = source.count(line)
    for key, (rel, body, pattern) in L3_PATTERNS.items():
        source = text(rel) if body is None else (bodies[body] or "")
        counts[key] = sum(1 for _ in pattern.finditer(luau_code(source)))
    return {"found": {key: value is not None for key, value in bodies.items()}, "counts": counts}


# L3 W2 (docs/prompts/l3-w2-contract.md §9, T1 to T14): the lines that show a player's weapons
# (WeaponService's three attributes and the slot in use, AbilityService's cast) and the client
# lines that hang, aim and turn the models, read as text: none of these files loads here. Each
# check pins the call, the inputs it is given (the lines that feed it, in the same exact text) and
# that it is reached (the exits of the function it lives in are counted, so an early way out
# cannot hide). tests_l3_w2.luau holds every count to its expected value (W2L3.LINES).
RANGE_SERVICE = "src/combat/server/Services/RangeService.luau"
HELD_WEAPONS = "src/combat/client/Controllers/HeldWeapons.luau"
WEAPON_CONTROLLER = "src/combat/client/Controllers/WeaponController.luau"
FLAME_FX = "src/combat/client/Controllers/FlameFx.luau"
ABILITY_SHARED = "src/combat/client/Controllers/AbilityFx/Shared.luau"
MAG_DUMP = "src/combat/client/Controllers/AbilityFx/MagDump.luau"
ARMORY_STAGE = "src/client/UI/ArmoryStage.luau"
ARMORY_SCREEN = "src/client/UI/ArmoryScreen.luau"
# The W2 fix round's S2: ArenaService's character hook is how a mission's later characters reach
# PrepareCharacter. S5: WeaponLook alone spells the attribute names.
ARENA_SERVICE = "src/combat/server/Services/ArenaService.luau"
WEAPON_LOOK = "src/shared/WeaponLook.luau"
# C2: the shelf's unowned icon tone.
ARMORY_SHELF = "src/client/UI/ArmoryShelf.luau"


def body_of(name: str) -> re.Pattern:
    """A module-level function's whole text, `local function <name>(` or `function <name>(`."""
    return re.compile(r"(?ms)^(?:local )?function " + re.escape(name) + r"\(.*?^end$")


L3W2_BODIES = {
    # T1 to T8, the server.
    "showWeapons": (WEAPON_SERVICE, body_of("showWeapons")),
    "noteHeld": (WEAPON_SERVICE, body_of("noteHeld")),
    "NoteHeld": (WEAPON_SERVICE, body_of("WeaponService.NoteHeld")),
    "addPlayer": (WEAPON_SERVICE, body_of("WeaponService.AddPlayer")),
    "prepare": (WEAPON_SERVICE, body_of("WeaponService.PrepareCharacter")),
    "setFamily": (WEAPON_SERVICE, body_of("WeaponService.SetFamily")),
    "onAttack": (WEAPON_SERVICE, body_of("WeaponService.OnAttack")),
    "onDraw": (WEAPON_SERVICE, body_of("WeaponService.OnDraw")),
    "onCast": (ABILITY_SERVICE, body_of("AbilityService.OnCast")),
    "rangePrepare": (RANGE_SERVICE, body_of("prepareCharacter")),
    # The fix round's S2: the three ways a character reaches PrepareCharacter, each in its caller.
    "waveInit": (WAVE_SERVICE, body_of("WaveService.Init")),
    "arenaAdmit": (ARENA_SERVICE, body_of("ArenaService.Admit")),
    "arenaSetHook": (ARENA_SERVICE, body_of("ArenaService.SetCharacterHook")),
    "rangeAdd": (RANGE_SERVICE, body_of("RangeService.AddPlayer")),
    "damageScale": (WEAPON_SERVICE, body_of("damageScale")),
    "meleeOrigin": (WEAPON_SERVICE, body_of("meleeOrigin")),
    "aimAllowed": (WEAPON_SERVICE, body_of("aimAllowed")),
    "claimSlack": (WEAPON_SERVICE, body_of("claimSlack")),
    "resolveMelee": (WEAPON_SERVICE, body_of("resolveMelee")),
    "resolveRanged": (WEAPON_SERVICE, body_of("resolveRanged")),
    "strike": (WEAPON_SERVICE, body_of("strike")),
    # T9, T10: the other player's arm and the one muzzle.
    "onStrike": (FEEDBACK, body_of("onStrike")),
    "sharedHand": (ABILITY_SHARED, body_of("handOf")),
    "sharedMuzzle": (ABILITY_SHARED, body_of("muzzleOf")),
    "flameMuzzle": (FLAME_FX, body_of("muzzleOf")),
    "muzzlePoint": (WEAPON_CONTROLLER, body_of("muzzlePoint")),
    # T10 to T13, HeldWeapons.
    "heldMuzzle": (HELD_WEAPONS, body_of("HeldWeapons.Muzzle")),
    "modelFor": (HELD_WEAPONS, body_of("modelFor")),
    "seal": (HELD_WEAPONS, body_of("seal")),
    # T14, the Armory stage: its handle's SetActive and Show (fields of the table ArmoryStage.new
    # returns), the path that shows a selection's model (selectFamily, a local of ArmoryStage.new)
    # and, since the fix round's C3, syncTurn: the turn and the stage's listeners live only while
    # the screen is open on Weapons with a model shown, so the one RenderStepped is made there.
    "stageSetActive": (ARMORY_STAGE, re.compile(r"(?ms)^\t\tSetActive = function\(.*?^\t\tend,$")),
    "stageShow": (ARMORY_STAGE, re.compile(r"(?ms)^\t\tShow = function\(.*?^\t\tend,$")),
    "stageSelect": (ARMORY_STAGE, re.compile(r"(?ms)^\tlocal function selectFamily\(.*?^\tend$")),
    "stageSync": (ARMORY_STAGE, re.compile(r"(?ms)^\tlocal function syncTurn\(.*?^\tend$")),
    "stageStop": (ARMORY_STAGE, re.compile(r"(?ms)^\tlocal function stop\(.*?^\tend$")),
    "stageDrag": (ARMORY_STAGE, re.compile(r"(?ms)^\tviewport\.InputBegan:Connect\(function\(.*?^\tend\)$")),
    "stageTemplate": (ARMORY_STAGE, body_of("templateOf")),
    # The fix round's S3 (3-m3) and C1 to C4, HeldWeapons: how a character's weapons are watched,
    # shown (once per batch, C4) and torn down, and how a template's Base is found (C1).
    "heldTemplate": (HELD_WEAPONS, body_of("templateOf")),
    "heldBind": (HELD_WEAPONS, body_of("bind")),
    "heldUnbind": (HELD_WEAPONS, body_of("unbind")),
    "heldWatchPart": (HELD_WEAPONS, body_of("watchPart")),
    "heldQueue": (HELD_WEAPONS, body_of("queueShow")),
    "heldFlush": (HELD_WEAPONS, body_of("flush")),
    # Fix round 2 (G1): the public flush, which Muzzle and another player's swing run first.
    "heldFlushPublic": (HELD_WEAPONS, body_of("HeldWeapons.Flush")),
    "heldStart": (HELD_WEAPONS, body_of("HeldWeapons.Start")),
    "heldSetStance": (HELD_WEAPONS, body_of("HeldWeapons.SetLocalStance")),
    # The lead's ruling 6 (§11): the rest poses, in HeldWeapons (the hold a slot hangs by, whether
    # a ranged model is in the hand, the listener told of it) and WeaponController (the arm's rest).
    "hang": (HELD_WEAPONS, body_of("hang")),
    "heldShow": (HELD_WEAPONS, body_of("show")),
    "heldOnHold": (HELD_WEAPONS, body_of("HeldWeapons.OnHold")),
    "restOf": (WEAPON_CONTROLLER, body_of("restOf")),
    "restFrame": (WEAPON_CONTROLLER, body_of("restFrame")),
    "cancelRig": (WEAPON_CONTROLLER, body_of("cancelRig")),
    "setRest": (WEAPON_CONTROLLER, body_of("setRest")),
    "remotePoseFor": (WEAPON_CONTROLLER, body_of("remotePoseFor")),
    "swingRig": (WEAPON_CONTROLLER, body_of("swingRig")),
    "onHold": (WEAPON_CONTROLLER, body_of("onHold")),
    "bindCharacter": (WEAPON_CONTROLLER, body_of("bindCharacter")),
    "release": (WEAPON_CONTROLLER, body_of("WeaponController.Release")),
    "shoot": (WEAPON_CONTROLLER, body_of("WeaponController.Shoot")),
    "controllerStart": (WEAPON_CONTROLLER, body_of("WeaponController.Start")),
}
# The hit-deciding functions T8 reads (L3-50: none of them sees the look).
L3W2_HITS = ("damageScale", "meleeOrigin", "aimAllowed", "claimSlack", "resolveMelee", "resolveRanged", "strike")
L3W2_EXITS = re.compile(r"\b(?:return|continue|break)\b")
# The `held` field in any spacing (never `..` before a local named held).
L3W2_HELD = re.compile(r"(?<![.])\.\s*held\b")
L3W2_SLOT = '\tlocal slot: SlotName = if def.slot == "melee" then "melee" else "ranged"\n'
# key: (file, body or None, the exact text), counted on the raw text as whole lines with their
# indentation (whole_lines: the fix round's S3), so a pinned line wrapped in a new block, which
# indents it further, no longer counts.
L3W2_LINES = {
    # T1: the one writer, its target and the pair and slot it writes.
    "showTarget": (WEAPON_SERVICE, "showWeapons", "\tlocal target = character or shooter.player.Character\n"
                   "\tif target == nil then\n\t\treturn\n\tend\n"),
    "showValues": (WEAPON_SERVICE, "showWeapons",
                   "\tfor name, value in WeaponLook.Values(shooter.loadout, shooter.held) do\n"
                   "\t\ttarget:SetAttribute(name, value)\n\tend\n"),
    "showSignature": (WEAPON_SERVICE, None, "local function showWeapons(shooter: Shooter, character: Model?): ()"),
    # T2: every fresh character, in both modes.
    "prepareShow": (WEAPON_SERVICE, "prepare", "\tlocal shooter = state.shooters[player]\n\tif shooter ~= nil then\n"
                    "\t\tresetAir(shooter)\n\t\tshowWeapons(shooter, character)\n\tend\n"),
    "prepareActive": (WEAPON_SERVICE, "prepare", "\tif not state.active then\n\t\treturn\n\tend\n"),
    "addPrepares": (WEAPON_SERVICE, "addPlayer", "\t\tif character ~= nil then\n"
                    "\t\t\tWeaponService.PrepareCharacter(player, character)\n\t\tend\n"),
    "addHeld": (WEAPON_SERVICE, "addPlayer", '\t\theld = "melee",\n'),
    "rangePrepares": (RANGE_SERVICE, "rangePrepare", "\tWeaponService.PrepareCharacter(player, character)\n"),
    # The fix round's S2 (2-m2): each caller, as it reaches PrepareCharacter. A mission's Init
    # hands it to ArenaService (Init's only early way out is the range's, initExits) ...
    "missionHook": (WAVE_SERVICE, "waveInit", "\tArenaService.SetCharacterHook(WeaponService.PrepareCharacter)\n"),
    # ... which keeps it, and runs it for every character an admitted member gets, after placing it.
    "arenaHookSet": (ARENA_SERVICE, "arenaSetHook", "\thooks.character = hook\n"),
    "arenaHook": (ARENA_SERVICE, "arenaAdmit", "\t\t\tplayer.CharacterAdded:Connect(function(character: Model)\n"
                  "\t\t\t\tlocal live = byPlayer[player]\n\t\t\t\tif live == nil then\n\t\t\t\t\treturn\n\t\t\t\tend\n"
                  "\t\t\t\twatchCharacter(live, character)\n\t\t\t\tplaceBody(live)\n"
                  "\t\t\t\tlocal hook = hooks.character\n\t\t\t\tif hook ~= nil then\n"
                  "\t\t\t\t\thook(player, character)\n\t\t\t\tend\n"),
    # The range prepares every respawn and the character it finds at its admit.
    "rangeAddWeapons": (RANGE_SERVICE, "rangeAdd", "\tWeaponService.AddPlayer(player)\n"),
    "rangeRespawn": (RANGE_SERVICE, "rangeAdd", "\t\tplayer.CharacterAdded:Connect(function(character: Model)\n"
                     "\t\t\tprepareCharacter(player, character)\n\t\tend)\n"),
    "rangeFirst": (RANGE_SERVICE, "rangeAdd", "\tlocal character = player.Character\n\tif character ~= nil then\n"
                   "\t\tprepareCharacter(player, character)\n\tend\nend"),
    # T3: every loadout change, after the pair is written, outside `if previous ~= family`.
    "familyShow": (WEAPON_SERVICE, "setFamily", "\tif slot == \"melee\" then\n\t\tshooter.loadout.melee = family\n"
                   "\telse\n\t\tshooter.loadout.ranged = family\n\tend\n\tshooter.drawStartedAt = 0\n"
                   "\tshowWeapons(shooter, nil)\n\ttuneStateFor(shooter)\n\tif previous ~= family then\n"),
    "familySlot": (WEAPON_SERVICE, "setFamily", L3W2_SLOT),
    # T4, T5: an accepted attack and a draw, on the line after each acceptance.
    "attackHeld": (WEAPON_SERVICE, "onAttack", "\tshooter.lastSeq[slot] = seq\n\tnoteHeld(shooter, slot)\n"),
    "attackSlot": (WEAPON_SERVICE, "onAttack", L3W2_SLOT),
    "drawHeld": (WEAPON_SERVICE, "onDraw", "\tshooter.drawWeapon = weapon\n\tnoteHeld(shooter, slot)\nend"),
    "drawSlot": (WEAPON_SERVICE, "onDraw", L3W2_SLOT),
    # T6: a cast (AbilityService alone knows its slot), right before its effect is sent, after
    # every refusal but the projectile budget's (the fix round's S6: castExitsAfter).
    "castHeld": (ABILITY_SERVICE, "onCast", "\tWeaponService.NoteHeld(player, slotName)\n\tbroadcastFx(fx)\n"),
    "castSlot": (ABILITY_SERVICE, "onCast", '\tlocal slotName: SlotName = if slot == "melee" then "melee" else "ranged"\n'),
    # The fix round's S4 (2-m5): only a ranged family draws, beside the draw's other refusals.
    "drawRanged": (WEAPON_SERVICE, "onDraw", "\tif\n\t\tdef.slot ~= \"ranged\"\n\t\tor slotFamily(shooter, slot) ~= weapon\n"
                   "\t\tor VitalsService.IsDown(player)\n\t\tor not mayAct(player)\n\tthen\n\t\treturn\n\tend\n"),
    # T7: shown only on a change; the cast's hook checks the slot word.
    "noteBody": (WEAPON_SERVICE, "noteHeld", "\tif shooter.held == slot then\n\t\treturn\n\tend\n"
                 "\tshooter.held = slot\n\tshowWeapons(shooter, nil)\nend"),
    "noteGuard": (WEAPON_SERVICE, "NoteHeld", "\tlocal shooter = state.shooters[player]\n"
                  "\tif not state.active or shooter == nil or (slot ~= \"melee\" and slot ~= \"ranged\") then\n"
                  "\t\treturn\n\tend\n"),
    "noteCall": (WEAPON_SERVICE, "NoteHeld", "\tnoteHeld(shooter, if slot == \"melee\" then \"melee\" else \"ranged\")\n"),
    # T9: another player's weapon swing moves their arm, with the strike's own step.
    "otherMine": (FEEDBACK, "onStrike", "\tlocal mine = strike.userId == localUserId()\n"),
    "otherSwing": (FEEDBACK, "onStrike",
                   '\tlocal swing = ability == nil and not strike.tick and variant ~= nil and variant.kind == "melee"\n'),
    "otherWired": (FEEDBACK, None, "\telseif fx.kind == \"strike\" then\n"
                   "\t\tlocal strike = parseStrike(fx :: { [string]: any })\n\t\tif strike ~= nil then\n"
                   "\t\t\tonStrike(strike)\n"),
    # T10: the one muzzle. AbilityFx's and FlameFx's push the point along the aim only when it is
    # not from a model (the nozzle is the tip); MagDump takes both its muzzles from Shared's.
    "sharedHeld": (ABILITY_SHARED, "sharedMuzzle", "\tlocal point, fromModel = HeldWeapons.Muzzle(userId)\n"
                   "\tif point == nil then\n\t\treturn fallback\n\tend\n"),
    "sharedPush": (ABILITY_SHARED, "sharedMuzzle", "\treturn if fromModel then point else point + aim * MUZZLE_FORWARD\n"),
    "flameHeld": (FLAME_FX, "flameMuzzle", "\tlocal point, fromModel = HeldWeapons.Muzzle(userId)\n"),
    "flamePush": (FLAME_FX, "flameMuzzle", "\tif point == nil or fromModel then\n\t\treturn point\n\tend\n"
                  "\treturn point + aim * MUZZLE_FORWARD\n"),
    "magHelper": (MAG_DUMP, None, "local muzzleOf = Shared.muzzleOf\n"),
    # HeldWeapons' muzzle: the tip of the model in the hand, else W1's chain from its one hand
    # list (the parts the weapon in use hangs from too).
    "heldHandList": (HELD_WEAPONS, None, 'local HAND_PARTS = { "RightHand", "Right Arm" }\n'),
    "heldFallback": (HELD_WEAPONS, "heldMuzzle", "\tlocal hand = firstPart(character, HAND_PARTS)\n"),
    "heldTip": (HELD_WEAPONS, "heldMuzzle", "\t\treturn held.base.CFrame:PointToWorldSpace(tip), true\n"),
    # T11, T12: the cache answers first; seal visits every part of the clone.
    "heldCached": (HELD_WEAPONS, "modelFor", "\tlocal cached = if cache ~= nil then cache[family] else nil\n"
                   "\tif cached ~= nil then\n\t\treturn cached\n\tend\n"),
    "sealLoop": (HELD_WEAPONS, "seal", "\tfor _, part in model:GetDescendants() do\n\t\tif part:IsA(\"BasePart\") then\n"),
    # HeldWeapons is reached: WeaponController starts it and hands it the local stance on a switch.
    "heldStarted": (WEAPON_CONTROLLER, None, "\tHeldWeapons.Start()\n"),
    "heldStance": (WEAPON_CONTROLLER, None, "\tcancelPose()\n\tHeldWeapons.SetLocalStance(nextStance)\n"),
    # T14: the select path poses the clone once (the tip rising); the screen alone switches the
    # turn, on while it is open on the Weapons tab, off on close.
    "selectPose": (ARMORY_STAGE, "stageSelect", "\t\tlocal pose = CFrame.Angles(math.rad(Theme.ARMORY_STAGE_TILT_DEGREES), 0, 0)\n"
                   "\t\tmodel:PivotTo(pose)\n"),
    "screenActive": (ARMORY_SCREEN, None, "\t\tstage.SetActive(view.open and shown == \"weapons\")\n"),
    "screenClosed": (ARMORY_SCREEN, None, "\t\t\tstage.SetActive(false)\n"),
    # Ruling 6, HeldWeapons: the back by the holster, a ranged model along the arm, a melee one tip
    # forward; the slot in use decides which; a hand is raised only while a ranged model is in it,
    # and the listener (WeaponController) is told each change, and of every raised hand when set.
    "hangHold": (HELD_WEAPONS, "hang", "\tlocal hold = if not inHand\n\t\tthen Theme.COMBAT_HOLD_BACK\n"
                 "\t\telseif ranged then Theme.COMBAT_HOLD_GRIP_RANGED\n\t\telse Theme.COMBAT_HOLD_GRIP_MELEE\n"),
    "hangPoint": (HELD_WEAPONS, "hang",
                  "\tlocal point = WeaponLook.Point(held.def, if inHand then \"grip\" else \"holster\") or Vector3.zero\n"),
    "hangWeld": (HELD_WEAPONS, "hang", "\theld.weld.Part0 = part\n\theld.weld.C0 = attachment.CFrame * hold * CFrame.new(-point)\n"
                 "\theld.model.Parent = character\n\treturn held\n"),
    "showSlot": (HELD_WEAPONS, "heldShow", "\tlocal slot = if rig.isLocal then localStance else held\n"
                 "\tlocal rangedInUse = slot == RANGED_SLOT\n\tlocal inUse = if rangedInUse then ranged else melee\n"
                 "\tlocal other = if rangedInUse then melee else ranged\n"),
    "showRaised": (HELD_WEAPONS, "heldShow", "\trig.inHand = hang(rig, inUse, true, rangedInUse)\n"
                   "\thang(rig, other, false, not rangedInUse)\n\tlocal raised = rangedInUse and rig.inHand ~= nil\n"),
    "showTold": (HELD_WEAPONS, "heldShow", "\tif raised ~= rig.raised then\n\t\trig.raised = raised\n"
                 "\t\tlocal listener = holdListener\n\t\tif listener ~= nil then\n"
                 "\t\t\tlistener(character, rig.isLocal, raised)\n\t\tend\n\tend\nend"),
    "holdSet": (HELD_WEAPONS, "heldOnHold", "\tholdListener = listener\n"),
    "holdReplay": (HELD_WEAPONS, "heldOnHold", "\tfor _, rig in rigs do\n\t\tif rig.raised then\n"
                   "\t\t\tlistener(rig.character, rig.isLocal, true)\n"),
    # Ruling 6, WeaponController: the rest is the raise while that character's hand is raised, else
    # 0; every pose ends there (the cancel, the swing's settle, Release, the kick's base); the
    # listener is wired before HeldWeapons starts; the local and remote records read it.
    "restRaise": (WEAPON_CONTROLLER, "restOf", "\treturn if rigModel ~= nil and raisedRigs[rigModel] == true\n"
                  "\t\tthen Theme.COMBAT_HOLD_RANGED_RAISE_DEGREES\n\t\telse 0\n"),
    "restAngle": (WEAPON_CONTROLLER, "restFrame", "\treturn rig.base * CFrame.Angles(math.rad(rig.rest), 0, 0)\n"),
    "cancelRest": (WEAPON_CONTROLLER, "cancelRig", "\tlocal motor = rig.motor\n\tif motor ~= nil then\n"
                   "\t\tmotor.C0 = restFrame(rig)\n\tend\nend"),
    "setRestWrite": (WEAPON_CONTROLLER, "setRest", "\tif rig.rest == degrees then\n\t\treturn\n\tend\n\trig.rest = degrees\n"),
    "swingSettle": (WEAPON_CONTROLLER, "swingRig",
                    "\t\t\trigPoseTo(rig, rig.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)\n"),
    "releaseRest": (WEAPON_CONTROLLER, "release", "\tcancelPose()\n"
                    "\tposeTo(localPose.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)\nend"),
    "kickRest": (WEAPON_CONTROLLER, "shoot", "\t\tposeTo(\n\t\t\tlocalPose.rest + Theme.COMBAT_SHOOT_KICK_DEGREES,\n"),
    "kickReleased": (WEAPON_CONTROLLER, "shoot", "\t\t\tWeaponController.Release()\n"),
    "holdWired": (WEAPON_CONTROLLER, "controllerStart", "\tHeldWeapons.OnHold(onHold)\n\tHeldWeapons.Start()\n"),
    "onHoldBody": (WEAPON_CONTROLLER, "onHold", "\traisedRigs[rigModel] = raised\n\tif not isLocal then\n"
                   "\t\tsetRest(remotePoseFor(rigModel), restOf(rigModel))\n\telseif rigModel == character then\n"
                   "\t\tsetRest(localPose, restOf(rigModel))\n\tend\nend"),
    "bindRest": (WEAPON_CONTROLLER, "bindCharacter", "\t\tlocalPose.rest = restOf(rig)\n\t\tmotor.C0 = restFrame(localPose)\n"),
    "remoteRest": (WEAPON_CONTROLLER, None, "\tfresh.rest = restOf(rigModel)\n"),
    # The fix round's S3 (3-m3): a new rest eases the arm there at once (not at the next pose), and
    # another player's fresh record snaps a raised arm up (a respawn with a ranged model in hand).
    "setRestEase": (WEAPON_CONTROLLER, "setRest", "\tif tween ~= nil then\n\t\ttween:Cancel()\n\tend\n"
                    "\trigPoseTo(rig, degrees, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)\nend"),
    "remoteSnap": (WEAPON_CONTROLLER, "remotePoseFor", "\tlocal freshMotor = fresh.motor\n"
                   "\tif freshMotor ~= nil and fresh.rest ~= 0 then\n\t\tfreshMotor.C0 = restFrame(fresh)\n"
                   "\tend\n\treturn fresh\nend"),
    # S3 (3-m3), the stage: a close stops it, the screen's open state syncs it, a selection clears
    # the old clone first; C3: syncTurn stops everything unless the screen is open on Weapons with
    # a model shown, then holds the window's focus listener and the one per-frame turn (T14:
    # behind exactly this gate); stop drops both; every drag ends on its own release, a lost one or
    # the window's focus (fix round 2, G3: no stick turns it); C1: Base by name, made PrimaryPart
    # before the pose; an unowned model is a silhouette.
    "stageStops": (ARMORY_STAGE, "stageSetActive", "\t\t\tif not active then\n\t\t\t\tstop()\n\t\t\t\treturn\n\t\t\tend\n"),
    "activeSyncs": (ARMORY_STAGE, "stageSetActive", "\t\t\t\twarm()\n\t\t\tend\n\t\t\tsyncTurn()\n\t\tend,"),
    "selectClears": (ARMORY_STAGE, "stageSelect", "\tlocal function selectFamily(family: string): ()\n\t\tclear()\n"),
    "selectBase": (ARMORY_STAGE, "stageSelect", "\t\tlocal model = template:Clone() :: Model\n"
                   "\t\tlocal base = model:FindFirstChild(TEMPLATE_BASE_NAME)\n"
                   "\t\tif base == nil or not base:IsA(\"BasePart\") then\n\t\t\tmodel:Destroy()\n\t\t\treturn\n"
                   "\t\tend\n\t\tmodel.PrimaryPart = base\n"),
    "stageTemplateBase": (ARMORY_STAGE, "stageTemplate", "\tlocal base = template:FindFirstChild(TEMPLATE_BASE_NAME)\n"
                          "\tif base == nil or not base:IsA(\"BasePart\") then\n\t\treturn nil, nil\n\tend\n"
                          "\treturn template, def\n"),
    "stageBaseName": (ARMORY_STAGE, None, "local TEMPLATE_BASE_NAME = \"Base\"\n"),
    "syncStops": (ARMORY_STAGE, "stageSync", "\tlocal function syncTurn(): ()\n"
                  "\t\tif not look.active or look.model == nil then\n\t\t\tstop()\n\t\t\treturn\n\t\tend\n"),
    "gatedFrames": (ARMORY_STAGE, "stageSync", "\t\tif look.turn == nil and not Theme.lowEndDevice then\n"
                    "\t\t\tlook.turn = RunService.RenderStepped:Connect(function(deltaTime: number)\n"),
    "syncStep": (ARMORY_STAGE, "stageSync", "\t\t\t\tturnBy(Theme.ARMORY_STAGE_TURN_DEGREES_PER_SECOND * deltaTime)\n"),
    "syncFocusOnce": (ARMORY_STAGE, "stageSync", "\t\tif look.focus == nil then\n"),
    "syncFocus": (ARMORY_STAGE, "stageSync",
                  "\t\t\tlook.focus = UserInputService.WindowFocusReleased:Connect(endDrag)\n"),
    "stopDrops": (ARMORY_STAGE, "stageStop", "\t\tlocal focus = look.focus\n\t\tif focus ~= nil then\n"
                  "\t\t\tlook.focus = nil\n\t\t\tfocus:Disconnect()\n\t\tend\n\t\tendDrag()\n\tend"),
    "showNilSyncs": (ARMORY_STAGE, "stageShow", "\t\t\t\tclear()\n\t\t\t\tlook.family = nil\n\t\t\t\tsyncTurn()\n"),
    "selectSyncs": (ARMORY_STAGE, "stageShow", "\t\t\t\tselectFamily(view.family)\n\t\t\t\tsyncTurn()\n"),
    "stageSilhouette": (ARMORY_STAGE, "stageShow",
                        "\t\t\tviewport.ImageColor3 = if owned then WHITE else Theme.ARMORY_STAGE_SILHOUETTE\n"),
    "dragLost": (ARMORY_STAGE, "stageDrag", "\t\t\t\tif not touch and not UserInputService:IsMouseButtonPressed(kind) then\n"
                 "\t\t\t\t\tendDrag()\n\t\t\t\t\treturn\n\t\t\t\tend\n"),
    "dragEnds": (ARMORY_STAGE, "stageDrag", "\t\t\t\tif ended == input or (not touch and ended.UserInputType == kind) then\n"
                 "\t\t\t\t\tendDrag()\n\t\t\t\tend\n"),
    # C2: the shelf's unowned icon takes its own ghost tone (the stage keeps the silhouette).
    "shelfGhost": (ARMORY_SHELF, None,
                   "\t\t\tcard.icon.ImageColor3 = if owned then WHITE else Theme.ARMORY_SCREEN_ICON_GHOST\n"),
    # S3 (3-m3), HeldWeapons: a family that leaves the loadout is destroyed; the three names are
    # watched (C4: each change queued); a mount part or attachment arriving re-shows; bind ends on
    # a show, as does the local switch (on its own frame); every player is watched, now and as
    # they join. C4: one deferred show per batch, none for a rig that has gone, and Muzzle shows a
    # pending change first (else a teammate's effect leaves from the weapon before, 3-m1): since
    # fix round 2 (G1, G2) through the public Flush, of the player's current character only, as
    # Muzzle's first line (L3W2_ORDER: before it reads the hand); a new rig starts with nothing
    # pending and bound, else every queued show is dropped or never deferred. C1: Base by name,
    # PrimaryPart before any weld.
    "heldCleanup": (HELD_WEAPONS, "heldShow", "\tlocal cache = models[character]\n\tif cache ~= nil then\n"
                    "\t\tfor family, entry in cache do\n\t\t\tif family ~= melee and family ~= ranged then\n"
                    "\t\t\t\tcache[family] = nil\n\t\t\t\tentry.model:Destroy()\n\t\t\tend\n\t\tend\n\tend\n"),
    "heldWatched": (HELD_WEAPONS, "heldBind", "\tlocal names = WeaponLook.ATTRIBUTES\n"
                    "\tfor _, name in { names.melee, names.ranged, names.held } do\n\t\ttable.insert(\n"
                    "\t\t\trig.connections,\n\t\t\tcharacter:GetAttributeChangedSignal(name):Connect(function()\n"
                    "\t\t\t\tqueueShow(rig)\n\t\t\tend)\n\t\t)\n\tend\n"),
    "heldMountShows": (HELD_WEAPONS, "heldBind", "\t\t\tif isMountPart(child.Name) then\n\t\t\t\twatchPart(rig, child)\n"
                       "\t\t\t\tqueueShow(rig)\n\t\t\tend\n"),
    "bindShows": (HELD_WEAPONS, "heldBind", "\t\t)\n\tend\n\tshow(rig)\nend"),
    "attachShows": (HELD_WEAPONS, "heldWatchPart",
                    "\t\t\tif child.Name == GRIP_ATTACHMENT or child.Name == BACK_ATTACHMENT then\n"
                    "\t\t\t\tqueueShow(rig)\n\t\t\tend\n"),
    "stanceShows": (HELD_WEAPONS, "heldSetStance", "\tlocal rig = rigs[Players.LocalPlayer]\n\tif rig ~= nil then\n"
                    "\t\tshow(rig)\n\tend\nend"),
    "playerWatch": (HELD_WEAPONS, "heldStart", "\ttable.insert(connections, Players.PlayerAdded:Connect(watchPlayer))\n"),
    "playersNow": (HELD_WEAPONS, "heldStart", "\tfor _, player in Players:GetPlayers() do\n\t\twatchPlayer(player)\n\tend\n"),
    "queueOnce": (HELD_WEAPONS, "heldQueue", "\tif rig.pending then\n\t\treturn\n\tend\n\trig.pending = true\n"
                  "\ttask.defer(flush, rig)\nend"),
    "flushShows": (HELD_WEAPONS, "heldFlush", "\tif not rig.pending then\n\t\treturn\n\tend\n\trig.pending = false\n"
                   "\tif rig.bound then\n\t\tshow(rig)\n\tend\nend"),
    "unbindUnbinds": (HELD_WEAPONS, "heldUnbind", "\trigs[player] = nil\n\trig.bound = false\n"),
    "muzzleFlushes": (HELD_WEAPONS, "heldMuzzle", "function HeldWeapons.Muzzle(userId: number): (Vector3?, boolean)\n"
                      "\tHeldWeapons.Flush(userId)\n"),
    "flushPublic": (HELD_WEAPONS, "heldFlushPublic", "\tlocal player = Players:GetPlayerByUserId(userId)\n"
                    "\tlocal rig = if player ~= nil then rigs[player] else nil\n"
                    "\tif player ~= nil and rig ~= nil and rig.character == player.Character then\n"
                    "\t\tflush(rig)\n\tend\nend"),
    "rigPending": (HELD_WEAPONS, "heldBind", "\t\tpending = false,\n"),
    "rigBound": (HELD_WEAPONS, "heldBind", "\t\tbound = true,\n"),
    "heldBaseName": (HELD_WEAPONS, None, "local TEMPLATE_BASE_NAME = \"Base\"\n"),
    "heldTemplateBase": (HELD_WEAPONS, "heldTemplate", "\tlocal base = template:FindFirstChild(TEMPLATE_BASE_NAME)\n"
                         "\tif base == nil or not base:IsA(\"BasePart\") then\n\t\treturn nil\n\tend\n\treturn template\n"),
    "heldBase": (HELD_WEAPONS, "modelFor", "\tlocal model = template:Clone()\n"
                 "\tlocal base = model:FindFirstChild(TEMPLATE_BASE_NAME)\n"
                 "\tif base == nil or not base:IsA(\"BasePart\") then\n\t\tmodel:Destroy()\n\t\treturn nil\n\tend\n"
                 "\tmodel.PrimaryPart = base\n"),
}
# key: (file, body or None, the pattern), counted on luau_code (comments blanked, strings kept).
L3W2_PATTERNS = {
    # T1, T7: one writer of the attributes and of `held`; the look's pure rules are read once.
    "showCalls": (WEAPON_SERVICE, None, re.compile(r"\bshowWeapons\(")),
    "noteCalls": (WEAPON_SERVICE, None, re.compile(r"\bnoteHeld\(")),
    "heldWrites": (WEAPON_SERVICE, None, re.compile(r"\.held\s*=(?!=)")),
    # The fix round's S1 (2-m1): `held` is read in WeaponService by the Values call and noteHeld's
    # compare and write alone, so no function a hit runs through (not only T8's seven) reads it;
    # AbilityService never does.
    "heldReads": (WEAPON_SERVICE, None, L3W2_HELD),
    "abilityHeld": (ABILITY_SERVICE, None, L3W2_HELD),
    # S5 (2-s1): the spellings the counts above do not see. `held` by index, a whole loadout
    # replaced (the constructor writes `loadout = loadout`, with no dot), the pair by index.
    "heldIndexed": (WEAPON_SERVICE, None, re.compile(r"\[\s*([\"'`])held\1\s*\]|\[(=*)\[held\]\2\]")),
    "loadoutWhole": (WEAPON_SERVICE, None, re.compile(
        r"(?<![.])\.\s*loadout\s*=(?!=)|\[\s*([\"'`])loadout\1\s*\]\s*=(?!=)")),
    # T1, T3: the pair showWeapons writes changes in SetFamily alone (its two writes), which shows it.
    "loadoutWrites": (WEAPON_SERVICE, None, re.compile(
        r"(?<![.])\.\s*loadout\s*(?:\.\s*(?:melee|ranged)\b|\[\s*([\"'`])(?:melee|ranged)\1\s*\])\s*=(?!=)")),
    "lookReads": (WEAPON_SERVICE, None, re.compile(r"\bWeaponLook\.")),
    "castNotes": (ABILITY_SERVICE, None, re.compile(r"\bWeaponService\.NoteHeld\(")),
    "showExits": (WEAPON_SERVICE, "showWeapons", L3W2_EXITS),
    "noteExits": (WEAPON_SERVICE, "noteHeld", L3W2_EXITS),
    "NoteExits": (WEAPON_SERVICE, "NoteHeld", L3W2_EXITS),
    "prepareExits": (WEAPON_SERVICE, "prepare", L3W2_EXITS),
    "familyExits": (WEAPON_SERVICE, "setFamily", L3W2_EXITS),
    "attackExits": (WEAPON_SERVICE, "onAttack", L3W2_EXITS),
    "drawExits": (WEAPON_SERVICE, "onDraw", L3W2_EXITS),
    "castExits": (ABILITY_SERVICE, "onCast", L3W2_EXITS),
    # S2: AddPlayer's own mission test is the one that prepares the character it finds (code only:
    # the comment lines inside it read as blank), and nothing leaves AddPlayer before it.
    "addMission": (WEAPON_SERVICE, "addPlayer", re.compile(
        r"(?m)^\tif state\.mode == \"mission\" then\n(?:[ \t]*\n)*"
        r"\t\tlocal character = player\.Character\n\t\tif character ~= nil then\n"
        r"\t\t\tWeaponService\.PrepareCharacter\(player, character\)\n\t\tend\n\tend\n")),
    "addExits": (WEAPON_SERVICE, "addPlayer", L3W2_EXITS),
    # S2: the ways out of the callers (Init's range return and its two sources' answers; the
    # range's AddPlayer guard; none in its prepareCharacter), one keeper and one setter of the hook.
    "initExits": (WAVE_SERVICE, "waveInit", L3W2_EXITS),
    "rangeAddExits": (RANGE_SERVICE, "rangeAdd", L3W2_EXITS),
    "rangePrepareExits": (RANGE_SERVICE, "rangePrepare", L3W2_EXITS),
    "hookWrites": (ARENA_SERVICE, None, re.compile(
        r"\bhooks\s*\.\s*character\s*=(?!=)|\bhooks\s*\[\s*([\"'`])character\1\s*\]\s*=(?!=)")),
    "hookSetters": (WAVE_SERVICE, None, re.compile(r"\bSetCharacterHook\(")),
    # T9: the arm's one call and the require (onStrike's ways out before it: l3w2_reading).
    "otherCalls": (FEEDBACK, None, re.compile(r"\bWeaponController\.SwingOther\(")),
    "otherRequire": (FEEDBACK, None, re.compile(r"(?m)^local WeaponController = require\(")),
    # T10: no hand read as a muzzle outside HeldWeapons and AbilityFx's handOf.
    "feedbackHand": (FEEDBACK, None, re.compile(r"\"RightHand\"")),
    "feedbackOwnMuzzle": (FEEDBACK, None, re.compile(r"\blocal function muzzleOf\(")),
    "feedbackHeld": (FEEDBACK, None, re.compile(r"\(HeldWeapons\.Muzzle\(")),
    "feedbackMuzzles": (FEEDBACK, None, re.compile(r"\bHeldWeapons\.Muzzle\(")),
    # L3-53: no require cycle (WeaponController requires neither FeedbackController nor
    # InputController; HeldWeapons requires none of the controllers that call it).
    "controllerCycle": (WEAPON_CONTROLLER, None, re.compile(r"WaitForChild\(\"(?:FeedbackController|InputController)\"\)")),
    "heldCycle": (HELD_WEAPONS, None, re.compile(
        r"WaitForChild\(\"(?:WeaponController|FeedbackController|InputController|FlameFx|CombatFxController)\"\)")),
    "flameHand": (FLAME_FX, None, re.compile(r"\"RightHand\"")),
    "sharedHands": (ABILITY_SHARED, None, re.compile(r"\"RightHand\"")),
    "sharedHandOf": (ABILITY_SHARED, "sharedHand", re.compile(r"\"RightHand\"")),
    # MagDump: every `muzzle =` line, and those that take it from muzzleOf.
    "magMuzzles": (MAG_DUMP, None, re.compile(r"(?m)^.*\bmuzzle\s*=(?!=).*$")),
    "magFromHelper": (MAG_DUMP, None, re.compile(r"(?m)^.*\bmuzzle\s*=(?!=).*\bmuzzleOf\(.*$")),
    "magOldMuzzle": (MAG_DUMP, None, re.compile(r"\bhandPoint\s*\+\s*look\s*\*\s*MUZZLE_FORWARD\b")),
    "pointIsHelper": (WEAPON_CONTROLLER, "muzzlePoint", re.compile(
        r"\Alocal function muzzlePoint\(fallback: Vector3\): Vector3\s+"
        r"return HeldWeapons\.Muzzle\(Players\.LocalPlayer\.UserId\) or fallback\s+end\Z")),
    "heldHands": (HELD_WEAPONS, None, re.compile(r"\"RightHand\"")),
    # T11 to T13: one clone, no per-frame work, no recursive lookup.
    "heldClones": (HELD_WEAPONS, None, re.compile(r":Clone\(\)")),
    "modelClones": (HELD_WEAPONS, "modelFor", re.compile(r":Clone\(\)")),
    "heldFrames": (HELD_WEAPONS, None, re.compile(r"\bRunService\b")),
    "heldDeep": (HELD_WEAPONS, None, re.compile(r"\bFindFirst\w*\([^()\n]*,\s*true\s*\)|\bFindFirstDescendant\b")),
    "sealCalls": (HELD_WEAPONS, "modelFor", re.compile(r"\bseal\(")),
    # The fix round's S3 (2-m3): and no line of HeldWeapons turns one of seal's properties back.
    "sealUndone": (HELD_WEAPONS, None, re.compile(
        r"\.\s*(?:CanCollide|CanQuery|CanTouch|Anchored)\s*=\s*true\b|\.\s*Massless\s*=\s*false\b"
        r"|\[\s*([\"'`])(?:CanCollide|CanQuery|CanTouch|Anchored)\1\s*\]\s*=\s*true\b"
        r"|\[\s*([\"'`])Massless\2\s*\]\s*=\s*false\b")),
    # T14: no motion gate on reducedMotion; one per-frame turn, made in syncTurn (C3); one pose.
    "stageReduced": (ARMORY_STAGE, None, re.compile(r"\bTheme\.reducedMotion\b")),
    "stageFrames": (ARMORY_STAGE, None, re.compile(r"\bRenderStepped:Connect\(")),
    "activeFrames": (ARMORY_STAGE, "stageSync", re.compile(r"\bRenderStepped:Connect\(")),
    # C3: syncTurn is defined once and called by SetActive(true), Show(nil) and a selection; its
    # ways out are the stop and the per-frame turn's wait for a drag; SetActive's are the same
    # state and the close.
    "syncCalls": (ARMORY_STAGE, None, re.compile(r"\bsyncTurn\(")),
    # Fix round 2 (G3, m3): no gamepad stick turns the stage; the world camera behind the screen
    # reads the right stick unsunk, so it would turn the lobby and the character as well.
    "stageSticks": (ARMORY_STAGE, None, re.compile(r"\bThumbstick[12]\b")),
    "syncExits": (ARMORY_STAGE, "stageSync", L3W2_EXITS),
    "setActiveExits": (ARMORY_STAGE, "stageSetActive", L3W2_EXITS),
    # C1: neither clone's Base is read from a PrimaryPart ref (it can arrive nil in a session).
    "stagePrimaryReads": (ARMORY_STAGE, None, re.compile(r"\.\s*PrimaryPart\b(?!\s*=[^=])")),
    "heldPrimaryReads": (HELD_WEAPONS, None, re.compile(r"\.\s*PrimaryPart\b(?!\s*=[^=])")),
    # C2: the shelf never draws the stage's near-black silhouette (it cannot read on the dark card).
    "shelfSilhouette": (ARMORY_SHELF, None, re.compile(r"\bARMORY_STAGE_SILHOUETTE\b")),
    # S3, C4: HeldWeapons shows directly in flush, at bind's end, on the local switch and in
    # refreshAll, and queues from its three event handlers; bind has no way out, SetLocalStance's
    # is the same stance and Start's a second start.
    "heldDirectShows": (HELD_WEAPONS, None, re.compile(r"\bshow\(rig\)")),
    "heldQueues": (HELD_WEAPONS, None, re.compile(r"\bqueueShow\(rig\)")),
    "bindExits": (HELD_WEAPONS, "heldBind", L3W2_EXITS),
    "flushPublicExits": (HELD_WEAPONS, "heldFlushPublic", L3W2_EXITS),
    "stanceExits": (HELD_WEAPONS, "heldSetStance", L3W2_EXITS),
    "startExits": (HELD_WEAPONS, "heldStart", L3W2_EXITS),
    "stagePoses": (ARMORY_STAGE, None, re.compile(r":PivotTo\(")),
    "selectPoses": (ARMORY_STAGE, "stageSelect", re.compile(r":PivotTo\(")),
    # Ruling 6: who writes the rest and the raised set, and the ways out of the bodies above.
    "restWrites": (WEAPON_CONTROLLER, None, re.compile(r"\.rest\s*=(?!=)")),
    "raisedWrites": (WEAPON_CONTROLLER, None, re.compile(r"\braisedRigs\[[^\]\n]*\]\s*=(?!=)")),
    "hangExits": (HELD_WEAPONS, "hang", L3W2_EXITS),
    "heldShowExits": (HELD_WEAPONS, "heldShow", L3W2_EXITS),
    "holdSetExits": (HELD_WEAPONS, "heldOnHold", L3W2_EXITS),
    "cancelExits": (WEAPON_CONTROLLER, "cancelRig", L3W2_EXITS),
    "onHoldExits": (WEAPON_CONTROLLER, "onHold", L3W2_EXITS),
    "swingExits": (WEAPON_CONTROLLER, "swingRig", L3W2_EXITS),
    "releaseExits": (WEAPON_CONTROLLER, "release", L3W2_EXITS),
    # S3 (3-m3): setRest's ways out are the same rest and no shoulder; remotePoseFor's are its
    # cached record and its fresh one.
    "setRestExits": (WEAPON_CONTROLLER, "setRest", L3W2_EXITS),
    "remotePoseExits": (WEAPON_CONTROLLER, "remotePoseFor", L3W2_EXITS),
}
for _name in L3W2_HITS:
    # T8: `.held` (the field; the word "held" is a StrikePick verdict there), the writers, the look.
    L3W2_PATTERNS[f"hit_{_name}"] = (
        WEAPON_SERVICE, _name, re.compile(r"(?<![.])\.\s*held\b|\bshowWeapons\b|\b[nN]oteHeld\b|\bWeaponLook\b"))
# The five properties a clone's parts take (L3-52, T12), each once in seal.
L3W2_SEAL = (".Anchored = false", ".CanCollide = false", ".CanQuery = false", ".CanTouch = false",
             ".Massless = true")
# key: (body, the first text, the second): 1 when both are in that body and the first comes first.
L3W2_ORDER = {
    # T11: the clone comes after the cache's answer; T12: sealed before its first parent.
    "cacheBeforeClone": ("modelFor", "return cached", ":Clone()"),
    "sealBeforeParent": ("modelFor", "seal(model)", "model.Parent = character"),
    # C1: Base is the PrimaryPart before any weld in HeldWeapons and before the stage's pose.
    "baseBeforeWelds": ("modelFor", "model.PrimaryPart = base", "WeldConstraint"),
    "baseBeforePose": ("stageSelect", "model.PrimaryPart = base", ":PivotTo("),
    # Fix round 2 (G2, m2): Muzzle runs the pending show before it reads the hand.
    "muzzleFlushFirst": ("heldMuzzle", "HeldWeapons.Flush(userId)", "rig.inHand"),
}


def branch(source: str, header: re.Pattern) -> str:
    """The block a branch line opens (the first line `header` matches, through the line before
    the next `elseif`, `else` or `end` at its own indentation); "" when there is none."""
    found = header.search(source)
    if not found:
        return ""
    start = source.rfind("\n", 0, found.start()) + 1
    indent = re.match(r"[ \t]*", source[start:]).group(0)
    close = re.compile(r"\n" + re.escape(indent) + r"(?:elseif|else|end)\b").search(source, found.end())
    return source[start: close.start() if close else len(source)]


# T9's branch. Its call is a whole line at the branch's own depth plus one tab, with no line
# between the branch head and it that opens a block (the fix round's S3, 2-m3). T14's gate is
# an exact whole line since the same round (gatedFrames in L3W2_LINES).
OTHER_BRANCH = re.compile(r"(?m)^\telseif swing and not mine then$")
OTHER_CALL = "WeaponController.SwingOther(strike.userId, strike.step or 1)"
OTHER_LINE = "\t\t" + OTHER_CALL
# Fix round 2 (G1, m1): the branch's first code line shows that player's pending slot change, so
# the hold listener lowers a raised arm before the swing starts instead of cancelling it.
OTHER_FLUSH = "\t\tHeldWeapons.Flush(strike.userId)"
BLOCK_OPENER = re.compile(r"(?m)^[ \t]*(?:if|while|for|repeat|do)\b")
# S5 (2-s1): an attribute name spelled as a literal, in any quote or a long bracket. WeaponLook
# alone may hold one; every other file under src reads WeaponLook.ATTRIBUTES.
ATTRIBUTE_NAME = re.compile(r"Weapon(?:Melee|Ranged|Held)")
ATTRIBUTE_LITERAL = re.compile(r"([\"'`])Weapon(?:Melee|Ranged|Held)\1|\[(=*)\[Weapon(?:Melee|Ranged|Held)\]\2\]")
# S5 (2-s2), ruling 7's form for T4 and T6: the noted line, and the exits after it.
NOTED_AFTER = {
    "attackExitsAfter": ("onAttack", "\tnoteHeld(shooter, slot)\n"),
    "castExitsAfter": ("onCast", "\tWeaponService.NoteHeld(player, slotName)\n"),
}


def whole_line_at(source: str, text: str, start: int = 0) -> int:
    """Where `text` first stands in `source` (from `start`) as whole lines: it begins a line (or the
    source) and ends one (with its own newline, before a newline, or at the source's end). -1 when
    it does not."""
    at = source.find(text, start)
    while at >= 0:
        end = at + len(text)
        begins = at == 0 or source[at - 1] == "\n"
        ends = text.endswith("\n") or end == len(source) or source[end] == "\n"
        if begins and ends:
            return at
        at = source.find(text, at + 1)
    return -1


def whole_lines(source: str, text: str) -> int:
    """How many times `text` stands in `source` as whole lines with their indentation (S3)."""
    count = 0
    at = whole_line_at(source, text)
    while at >= 0:
        count += 1
        at = whole_line_at(source, text, at + len(text))
    return count


def attribute_literals(repo) -> int:
    """S5: the attribute names spelled as string literals in the code (comments blanked) of every
    .luau file under `repo`/src but WeaponLook's. None is the answer."""
    if repo is None:
        return -1
    count = 0
    for path in sorted((Path(repo) / "src").rglob("*.luau")):
        if path.relative_to(repo).as_posix() == WEAPON_LOOK:
            continue
        source = path.read_text(encoding="utf-8")
        if ATTRIBUTE_NAME.search(source):
            count += sum(1 for _ in ATTRIBUTE_LITERAL.finditer(luau_code(source)))
    return count


def l3w2_reading(text, repo=None) -> dict:
    """T1 to T14 (L3W2_LINES as whole lines, L3W2_PATTERNS on luau_code, L3W2_ORDER), each counted
    in the function it belongs to; `found` names the functions whose body was found. `text` reads a
    repo file (empty when missing); `repo` is the root whose src the attribute literals are
    counted in (-1 without one)."""
    bodies = {}
    for key, (rel, pattern) in L3W2_BODIES.items():
        found = pattern.search(text(rel))
        bodies[key] = found.group(0) if found else None
    counts = {}
    for key, (rel, body, line) in L3W2_LINES.items():
        source = text(rel) if body is None else (bodies[body] or "")
        counts[key] = whole_lines(source, line)
    for key, (body, line) in NOTED_AFTER.items():
        source = bodies[body] or ""
        at = whole_line_at(source, line)
        counts[key] = len(L3W2_EXITS.findall(luau_code(source[at + len(line):]))) if at >= 0 else -1
    counts["lookLiterals"] = attribute_literals(repo)
    for key, (rel, body, pattern) in L3W2_PATTERNS.items():
        source = text(rel) if body is None else (bodies[body] or "")
        counts[key] = sum(1 for _ in pattern.finditer(luau_code(source)))
    seal = luau_code(bodies["seal"] or "")
    for index, line in enumerate(L3W2_SEAL):
        counts[f"seal{index + 1}"] = seal.count(line)
    for key, (body, first, second) in L3W2_ORDER.items():
        source = luau_code(bodies[body] or "")
        a, b = source.find(first), source.find(second)
        counts[key] = 1 if 0 <= a < b else 0
    strike = bodies["onStrike"] or ""
    other = branch(strike, OTHER_BRANCH)
    counts["otherInBranch"] = whole_lines(other, OTHER_LINE)
    line = whole_line_at(other, OTHER_LINE)
    head = other.find("\n") + 1
    counts["otherBlocks"] = len(BLOCK_OPENER.findall(luau_code(other[head:line]))) if line >= 0 else -1
    counts["otherFlush"] = whole_lines(other, OTHER_FLUSH)
    flushed = whole_line_at(other, OTHER_FLUSH)
    counts["otherFlushBefore"] = 1 if 0 <= flushed < line else 0
    code = [row for row in luau_code(other[head:]).split("\n") if row.strip()]
    counts["otherFlushFirst"] = 1 if code and code[0] == OTHER_FLUSH else 0
    # The lead's ruling 7 (§11): onStrike's ways out before the SwingOther call (-1 when the call
    # is not there), not the whole function's (it has had more since before W2).
    called = strike.find(OTHER_CALL)
    counts["strikeExits"] = len(L3W2_EXITS.findall(luau_code(strike[:called]))) if called >= 0 else -1
    return {"found": {key: value is not None for key, value in bodies.items()}, "counts": counts}


GROUND_AIMED = re.compile(r"local GROUND_AIMED: \{ \[string\]: true \} =\s*\{([^}]*)\}")
GROUND_TARGET = re.compile(r'(?m)^\s*(\w+)\s*=\s*\{[^\n]*\btarget\s*=\s*"ground"')


def source_reading(repo: Path) -> dict:
    """The L1c fix round's m2 and M1, read as text (neither module loads in the harness):
    `groundClient` = the names InputController's GROUND_AIMED lists, `groundServer` = the
    AbilityService mechanics whose target is "ground", `zoomCap` = combat.project.json's
    StarterPlayer.CameraMaxZoomDistance (None when unset). A file that is missing reads as empty,
    and the cases fail on an empty list. The L2 W1 fix round's c4 adds `groundFloor`: for the client
    (InputController.groundPoint) and the server (WeaponService.GroundPoint), read inside that one
    function (`found` false when it is not there): how many times it calls GroundRule.Floor
    (`rule`), WallClip.GroundFloor (`calls`), Rise, TooHigh or CasterFloor (`parts`), and how many
    inputs it reads itself (`reads`: GetAttribute, Tuning.Get, `.movement`)."""
    def text(rel: str) -> str:
        path = repo / rel
        return path.read_text(encoding="utf-8") if path.is_file() else ""

    aimed = GROUND_AIMED.search(text(INPUT_CONTROLLER))
    client = sorted(re.findall(r"(\w+)\s*=\s*true", aimed.group(1))) if aimed else []
    server = sorted(GROUND_TARGET.findall(text(ABILITY_SERVICE)))
    zoom = None
    project = text(COMBAT_PROJECT)
    if project:
        player = json.loads(project).get("tree", {}).get("StarterPlayer", {})
        zoom = player.get("$properties", {}).get("CameraMaxZoomDistance")
    ground_floor = {}
    for side, rel in (("client", INPUT_CONTROLLER), ("server", WEAPON_SERVICE)):
        body = GROUND_POINT_BODY[side].search(text(rel))
        source = body.group(0) if body else ""
        ground_floor[side] = {
            "found": body is not None,
            "rule": len(GROUND_RULE_CALL.findall(source)),
            "calls": len(GROUND_FLOOR_CALL.findall(source)),
            "parts": len(GROUND_PART_CALL.findall(source)),
            "reads": len(GROUND_INPUT_READ.findall(source)),
        }
    finish = FINISH_BODY.search(text(WEAPON_SERVICE))
    finish_text = finish.group(0) if finish else ""
    react = REACT_BODY.search(text(LEVEL_SERVICE))
    react_text = react.group(0) if react else ""
    aim = AIM_BODY.search(text(WEAPON_SERVICE))
    aim_text = aim.group(0) if aim else ""
    hit = WORLD_HIT_BODY.search(text(WEAPON_SERVICE))
    hit_text = hit.group(0) if hit else ""
    claim = CLAIM_BODY.search(text(WEAPON_SERVICE))
    claim_text = claim.group(0) if claim else ""
    wiring = {
        "main": len(REACT_WIRING.findall(text(MAIN_SERVER))),
        "finishFound": finish is not None,
        "finishListeners": finish_text.count("state.strikeListeners"),
        "finishGuarded": FINISH_GUARDED.search(finish_text) is not None,
        "reactFound": react is not None,
        "reactElement": react_text.count(REACT_ELEMENT),
        "reactApply": react_text.count(REACT_APPLY),
        "reactOwnLoop": len(REACT_OWN_LOOP.findall(react_text)),
        "aimFound": aim is not None,
        # Each line of the rule once: the smallest and the largest count.
        "aimRay": min(aim_text.count(line) for line in AIM_RAYS),
        "aimRayMost": max(aim_text.count(line) for line in AIM_RAYS),
        "hitFound": hit is not None,
        "hitLines": min(hit_text.count(line) for line in WORLD_HIT_LINES),
        # Each line once, and `motion` only in them (taken, then returned).
        "claimFound": claim is not None,
        "claimLines": min(claim_text.count(line) for line in CLAIM_LINES),
        "claimMotion": claim_text.count("motion"),
    }
    freeze = FREEZE_BODY.search(text(LEVEL_SERVICE))
    freeze_text = freeze.group(0) if freeze else ""
    rescue = RESCUE_BODY.search(text(WAVE_SERVICE))
    rescue_text = rescue.group(0) if rescue else ""
    w3 = {
        "reactIce": react_text.count(W3_LINES["reactIce"]),
        "reactFreeze": react_text.count(W3_LINES["reactFreeze"]),
        "freezeFound": freeze is not None,
        "freezeReach": freeze_text.count(W3_LINES["freezeReach"]),
        "freezeCall": freeze_text.count(W3_LINES["freezeCall"]),
        "freezeTold": freeze_text.count(W3_LINES["freezeTold"]),
        "freezeShow": freeze_text.count(FREEZE_SHOW),
        "rescueFound": rescue is not None,
        "rescueStood": rescue_text.count(W3_LINES["rescueStood"]),
        "rescueLanding": rescue_text.count(W3_LINES["rescueLanding"]),
        "rescueTarget": rescue_text.count(W3_LINES["rescueTarget"]),
        "quakeAlias": text(ABILITY_SERVICE).count(W3_LINES["quakeAlias"]),
    }
    return {
        "groundClient": client,
        "groundServer": server,
        "zoomCap": zoom,
        "groundFloor": ground_floor,
        "wiring": wiring,
        "w3": w3,
        "w3fix": w3_fix_reading(text, react_text, freeze_text),
        "w3fix2": w3_fix2_reading(text, freeze_text),
        "w3fix3": w3_fix3_reading(text),
        "l3": l3_reading(text),
        "l3w2": l3w2_reading(text, repo),
        "l4b": l4b_reading(text),
    }


# L4 W1b (docs/prompts/l4-w1b-contract.md §4, §5): the lines that apply L4B-7 (a dash's i-frames once
# the server's ring has seen it) in WeaponService and L4B-8 (a floor set's cells once per member) in
# ArenaService and WaveService, none of which loads here. Each: (file, function body or None for the
# whole file's code, how it is counted, the text, the count expected), counted on the code with its
# comments blanked (luau_code); "lines" = whole lines with their indentation, "text" = occurrences,
# "regex" = matches. The expected counts are tests_l3_w2.luau's (L4BP).
ON_DASH_BODY = re.compile(r"(?ms)^function WeaponService\.OnDash\(.*?^end$")
PROVE_DASH_BODY = re.compile(r"(?ms)^local function proveDash\(.*?^end$")
PENDING_DASH_BODY = re.compile(r"(?ms)^local function pendingDash\(.*?^end$")
WEAPON_STEP_BODY = re.compile(r"(?ms)^local function step\(.*?^end$")
WEAPON_START_BODY = re.compile(r"(?ms)^function WeaponService\.Start\(.*?^end$")
GRANT_IFRAMES_BODY = re.compile(r"(?ms)^function WeaponService\.GrantIframes\(.*?^end$")
SEND_RUN_STATE_BODY = re.compile(r"(?ms)^local function sendRunState\(.*?^end$")
BUILD_RUN_STATE_BODY = re.compile(r"(?ms)^function ArenaService\.BuildRunState\(.*?^end$")
ADMIT_BODY = re.compile(r"(?ms)^function ArenaService\.Admit\(.*?^end$")
REMOVE_BODY = re.compile(r"(?ms)^function ArenaService\.Remove\(.*?^end$")
SET_FLOORS_BODY = re.compile(r"(?ms)^local function setFloors\(.*?^end$")
PUSH_RUN_FIELDS_BODY = re.compile(r"(?ms)^local function pushRunFields\(.*?^end$")
# The L4 W1b fix round (docs/prompts/l4-w1b-fix-round.md F3, F4, F6): the client's half of the
# cells-once rule, in CombatUIController (both functions are nested in bootMission, one tab in),
# and the mentor pay's deciding lines in WaveService.payMentors.
UI_CONTROLLER = "src/combat/client/Controllers/CombatUIController.luau"
APPLY_FLOORS_BODY = re.compile(r"(?ms)^\tlocal function applyFloors\(.*?^\tend$")
ON_RUN_STATE_BODY = re.compile(r"(?ms)^\tlocal function onRunState\(.*?^\tend$")
PAY_MENTORS_BODY = re.compile(r"(?ms)^local function payMentors\(.*?^end$")
L4B_LINES = {
    # L4B-7, WeaponService.
    "dashGrantsNothing": (WEAPON_SERVICE, ON_DASH_BODY, "regex",
                          r"\bGrantIframes\(|\bDashProof\.|\bshowIframes\(|\bopenIframes\(|\biframes\w*\s*=(?!=)"),
    "dashClaim": (WEAPON_SERVICE, ON_DASH_BODY, "lines", "\tshooter.dashClaimAt = now"),
    "dashStamp": (WEAPON_SERVICE, ON_DASH_BODY, "lines", "\tshooter.lastDashAt = now"),
    "dashDown": (WEAPON_SERVICE, ON_DASH_BODY, "lines",
                 "\tif character == nil or root == nil or VitalsService.IsDown(player) or not mayAct(player) then"),
    "trackRecordThenProve": (WEAPON_SERVICE, TRACK_AIR_BODY, "text",
                             "\t\tPositionRing.Record(shooter.history, now, position)\n\t\tif shooter.dashClaimAt ~= nil then\n"
                             "\t\t\tproveDash(shooter, now, position)\n\t\tend\n"),
    "trackNoRootClears": (WEAPON_SERVICE, TRACK_AIR_BODY, "lines", "\t\t\tshooter.dashClaimAt = nil"),
    "proveStep": (WEAPON_SERVICE, PROVE_DASH_BODY, "text",
                  "\tlocal verdict = DashProof.Step(\n\t\tshooter,\n\t\tshooter.history,\n\t\tnow,\n\t\tposition,\n"
                  "\t\tdashRule(config),\n\t\tconfig.movement.dashIframes\n\t)\n"),
    "proveShows": (WEAPON_SERVICE, PROVE_DASH_BODY, "text", '\tif verdict == "proven" then\n\t\tshowIframes(shooter, now)\n\tend\n'),
    "proveWritesNothing": (WEAPON_SERVICE, PROVE_DASH_BODY, "regex",
                           r"\bdashClaimAt\s*=(?!=)|\biframes\w*\s*=(?!=)|\bDashProof\.Open\("),
    "ruleRead": (WEAPON_SERVICE, None, "text", "local rule = DashProof.Rule(config.movement, config.shooting)"),
    "ruleCalls": (WEAPON_SERVICE, None, "text", "DashProof.Rule("),
    "pendingNoClaim": (WEAPON_SERVICE, PENDING_DASH_BODY, "lines",
                       "\tif shooter == nil or shooter.dashClaimAt == nil then"),
    "pendingClaim": (WEAPON_SERVICE, PENDING_DASH_BODY, "text",
                     "return DashProof.Pending(shooter.dashClaimAt, dashRule(config), config.movement.dashIframes)"),
    "hookClaim": (WEAPON_SERVICE, WEAPON_START_BODY, "lines", "\t\tdashClaim = pendingDash,"),
    # G2 and G3 (docs/prompts/l4-w1b-fix2.md): step opens with the clock, then the proofs, then
    # VitalsService, each under xpcall, with nothing between the function's start and the two
    # (stepHead, one block); the rest comes after (stepRest, restLast); Start connects step itself.
    "stepHead": (WEAPON_SERVICE, WEAPON_STEP_BODY, "text",
                 "local function step(deltaTime: number): ()\n\tlocal now = os.clock()\n"
                 "\txpcall(trackAir, stepFailed, now, deltaTime)\n\txpcall(VitalsService.Step, stepFailed, deltaTime)\n"),
    "stepVitals": (WEAPON_SERVICE, WEAPON_STEP_BODY, "lines", "\txpcall(VitalsService.Step, stepFailed, deltaTime)"),
    "stepRest": (WEAPON_SERVICE, WEAPON_STEP_BODY, "lines", "\txpcall(stepRest, stepFailed, now, deltaTime)"),
    "startConnects": (WEAPON_SERVICE, WEAPON_START_BODY, "lines", "\tRunService.Heartbeat:Connect(step)"),
    "vitalsStepCalls": (WEAPON_SERVICE, None, "text", "VitalsService.Step"),
    "heartbeats": (WEAPON_SERVICE, None, "text", "Heartbeat:Connect("),
    "grantOpens": (WEAPON_SERVICE, GRANT_IFRAMES_BODY, "text",
                   "\tDashProof.Open(shooter, math.min(from or now, now), seconds)\n\tshowIframes(shooter, now)\n"),
    "openCalls": (WEAPON_SERVICE, None, "text", "DashProof.Open("),
    "stepCalls": (WEAPON_SERVICE, None, "text", "DashProof.Step("),
    "claimWrites": (WEAPON_SERVICE, None, "regex", r"\bshooter\.dashClaimAt\s*=(?!=)"),
    "resetDropsClaim": (WEAPON_SERVICE, RESET_AIR_BODY, "text", "shooter.dashClaimAt = nil"),
    # L4B-8, ArenaService.
    "runStateSpelled": (ARENA_SERVICE, None, "text", '"RunState"'),
    "sendRunStateCalls": (ARENA_SERVICE, None, "text", "sendRunState("),
    "attachCalls": (ARENA_SERVICE, None, "text", "RunFloors.Attach("),
    "sendSkip": (ARENA_SERVICE, SEND_RUN_STATE_BODY, "lines", "\tif play.cellsSent[userId] ~= seq then"),
    "sendAttach": (ARENA_SERVICE, SEND_RUN_STATE_BODY, "lines",
                   "\t\tlocal floors, cellsWent = RunFloors.Attach(runFields.floors, seq, play.cellsSent[userId])"),
    "sendCellsWent": (ARENA_SERVICE, SEND_RUN_STATE_BODY, "lines", "\t\tif cellsWent then"),
    "sendClone": (ARENA_SERVICE, SEND_RUN_STATE_BODY, "lines", "\t\t\tsent = table.clone(runState)"),
    "sendFloors": (ARENA_SERVICE, SEND_RUN_STATE_BODY, "lines", "\t\t\tsent.floors = floors"),
    "sendFloorsWrites": (ARENA_SERVICE, SEND_RUN_STATE_BODY, "regex", r"\bsent\.floors\s*=(?!=)"),
    "sendNote": (ARENA_SERVICE, SEND_RUN_STATE_BODY, "lines", "\t\tplay.cellsSent[userId] = seq"),
    "sendFires": (ARENA_SERVICE, SEND_RUN_STATE_BODY, "lines", '\tRemoteService.FireClient(player, "RunState", sent)'),
    "buildAttach": (ARENA_SERVICE, BUILD_RUN_STATE_BODY, "text",
                    "local floors = RunFloors.Attach(runFields.floors, runFields.floorsSeq, runFields.floorsSeq)"),
    "buildFloors": (ARENA_SERVICE, BUILD_RUN_STATE_BODY, "lines", "\t\tfloors = floors,"),
    "buildSeq": (ARENA_SERVICE, BUILD_RUN_STATE_BODY, "lines", "\t\tfloorsSeq = runFields.floorsSeq,"),
    "admitClears": (ARENA_SERVICE, ADMIT_BODY, "lines", "\tplay.cellsSent[player.UserId] = nil"),
    "removeClears": (ARENA_SERVICE, REMOVE_BODY, "lines", "\tplay.cellsSent[member.userId] = nil"),
    "noteWrites": (ARENA_SERVICE, None, "regex", r"\bplay\.cellsSent\[[^\]]*\]\s*=(?!=)"),
    # L4B-8, WaveService.
    "floorsAssigned": (WAVE_SERVICE, None, "regex", r"\brun\.floors\s*=(?!=)"),
    "seqRaised": (WAVE_SERVICE, SET_FLOORS_BODY, "lines", "\tboot.floorsSeq += 1"),
    "seqWrites": (WAVE_SERVICE, None, "regex", r"\bboot\.floorsSeq\s*(?:\+=|=(?!=))"),
    "setFloorsCalls": (WAVE_SERVICE, None, "text", "setFloors("),
    "startSets": (WAVE_SERVICE, None, "lines", "\tsetFloors(runFloors)"),
    "lobbySets": (WAVE_SERVICE, None, "lines", "\tsetFloors({})"),
    "pushSeq": (WAVE_SERVICE, PUSH_RUN_FIELDS_BODY, "lines", "\t\tfloorsSeq = boot.floorsSeq,"),
    # L4B-8, CombatUIController (the client's half; F3, F4).
    "uiHeld": (UI_CONTROLLER, APPLY_FLOORS_BODY, "lines", "\t\tlocal held = st.floors"),
    "uiMerge": (UI_CONTROLLER, APPLY_FLOORS_BODY, "lines", "\t\tfresh = RunFloors.Merge(held, st.floorsSeq, fresh, seq)"),
    "uiSeq": (UI_CONTROLLER, APPLY_FLOORS_BODY, "lines", "\t\tst.floorsSeq = seq"),
    "uiKeep": (UI_CONTROLLER, APPLY_FLOORS_BODY, "lines", "\t\tst.floors = fresh"),
    "uiCall": (UI_CONTROLLER, ON_RUN_STATE_BODY, "lines",
               '\t\tapplyFloors(run.floors, if typeof(run.floorsSeq) == "number" then run.floorsSeq else 0)'),
    "uiApplyCalls": (UI_CONTROLLER, None, "text", "applyFloors("),
    "uiMergeCalls": (UI_CONTROLLER, None, "text", "RunFloors.Merge("),
    "uiSeqWrites": (UI_CONTROLLER, None, "regex", r"\bst\.floorsSeq\s*=(?!=)"),
    "uiConnect": (UI_CONTROLLER, None, "lines", "\tremotes.runState.OnClientEvent:Connect(onRunState)"),
    # F6, WaveService.payMentors (B's lines; the rule itself is check_stage_mirror's MentorBonus).
    # s1 (fix round 2): its inputs too: the damage total, and the guard on a bonus of nothing.
    "mentorTotal": (WAVE_SERVICE, PAY_MENTORS_BODY, "text",
                    "\tlocal total = 0\n\tfor _, damage in tally do\n\t\ttotal += damage\n\tend\n"),
    "mentorNone": (WAVE_SERVICE, PAY_MENTORS_BODY, "lines", "\tif total <= 0 then"),
    "mentorFloor": (WAVE_SERVICE, PAY_MENTORS_BODY, "lines",
                    "\t\tif mentor.waiting or (tally[mentor.userId] or 0) / total < coop.mentorMinDamageShare then"),
    "menteeOther": (WAVE_SERVICE, PAY_MENTORS_BODY, "lines", "\t\t\t\tother ~= mentor"),
    "menteeFloor": (WAVE_SERVICE, PAY_MENTORS_BODY, "lines",
                    "\t\t\t\tand (tally[other.userId] or 0) / total >= coop.mentorMinDamageShare"),
    "menteeRate": (WAVE_SERVICE, PAY_MENTORS_BODY, "lines", "\t\t\t\ttable.insert(menteeRates, other.incomeRate)"),
    "mentorBonusCall": (WAVE_SERVICE, PAY_MENTORS_BODY, "lines",
                        "\t\tlocal bonus = Combat.MentorBonus(combatConfig, mentor.incomeRate, menteeRates)"),
    "mentorValor": (WAVE_SERVICE, PAY_MENTORS_BODY, "lines", "\t\tstate.combat.valor += bonus"),
    "mentorCard": (WAVE_SERVICE, PAY_MENTORS_BODY, "lines", "\t\tArenaService.CreditMentor(mentor.userId, bonus)"),
    "mentorNoBonus": (WAVE_SERVICE, PAY_MENTORS_BODY, "text", "\t\tif bonus <= 0 then\n\t\t\tcontinue\n\t\tend\n"),
    "mentorBonusCalls": (WAVE_SERVICE, None, "text", "Combat.MentorBonus("),
    "bossPaysMentors": (WAVE_SERVICE, None, "lines", "\t\tpayMentors(combatConfig, tally)"),
}
# Two lines that must come in this order inside their function: (key, file, body, first, then).
L4B_ORDER = {
    "trackOrder": (WEAPON_SERVICE, TRACK_AIR_BODY, "PositionRing.Record(shooter.history, now, position)",
                   "proveDash(shooter, now, position)"),
    "frameOrder": (WEAPON_SERVICE, WEAPON_STEP_BODY, "xpcall(trackAir, stepFailed, now, deltaTime)",
                   "xpcall(VitalsService.Step, stepFailed, deltaTime)"),
    "restLast": (WEAPON_SERVICE, WEAPON_STEP_BODY, "xpcall(VitalsService.Step, stepFailed, deltaTime)",
                 "xpcall(stepRest, stepFailed, now, deltaTime)"),
    "sendOrder": (ARENA_SERVICE, SEND_RUN_STATE_BODY,
                  "RunFloors.Attach(runFields.floors, seq, play.cellsSent[userId])", "play.cellsSent[userId] = seq"),
    "uiMergeThenSeq": (UI_CONTROLLER, APPLY_FLOORS_BODY,
                       "RunFloors.Merge(held, st.floorsSeq, fresh, seq)", "st.floorsSeq = seq"),
    "uiMergeThenSame": (UI_CONTROLLER, APPLY_FLOORS_BODY,
                        "RunFloors.Merge(held, st.floorsSeq, fresh, seq)", "local same = #fresh == #held"),
    "uiGuardThenFloors": (UI_CONTROLLER, ON_RUN_STATE_BODY, "if not isRunState(payload) then", "applyFloors(run.floors, "),
    "uiFloorsFirst": (UI_CONTROLLER, ON_RUN_STATE_BODY, "applyFloors(run.floors, ", "if run.levelId ~= st.levelId then"),
    "bonusGuardThenPay": (WAVE_SERVICE, PAY_MENTORS_BODY, "if bonus <= 0 then", "state.combat.valor += bonus"),
    "mentorFloorThenPay": (WAVE_SERVICE, PAY_MENTORS_BODY,
                           "(tally[mentor.userId] or 0) / total < coop.mentorMinDamageShare", "state.combat.valor += bonus"),
}


def l4b_reading(text) -> dict:
    """L4B_LINES counted on the code (comments blanked) of the function each belongs to, and the
    L4B_ORDER pairs (True when both are there, in that order). `found` names the bodies found.
    `text` reads a repo file (empty when missing)."""
    counts, found = {}, {}
    for key, (rel, pattern, how, line) in L4B_LINES.items():
        code = luau_code(text(rel))
        if pattern is not None:
            body = pattern.search(code)
            found[pattern.pattern] = body is not None
            code = body.group(0) if body else ""
        if how == "lines":
            counts[key] = whole_lines(code, line)
        elif how == "regex":
            counts[key] = len(re.findall(line, code))
        else:
            counts[key] = code.count(line)
    order = {}
    for key, (rel, pattern, first, then) in L4B_ORDER.items():
        body = pattern.search(luau_code(text(rel)))
        code = body.group(0) if body else ""
        a, b = code.find(first), code.find(then)
        order[key] = a >= 0 and b > a
    return {"counts": counts, "order": order, "missing": sorted(p for p, ok in found.items() if not ok)}


def w3_fix3_reading(text) -> dict:
    """The W3 third fix round's lines (W3_FIX3_LINES), counted in the function each belongs to.
    `text` reads a repo file (empty when missing)."""
    weapon = text(WEAPON_SERVICE)
    lines = W3_FIX3_LINES

    def body(pattern, source: str) -> str:
        found = pattern.search(source)
        return found.group(0) if found else ""

    bodies = body(BODIES_BODY["server"][1], text(LEVEL_SERVICE))
    track = body(TRACK_AIR_BODY, weapon)
    phone = body(PHONE_BODY, text(INPUT_CONTROLLER))
    return {
        "bodiesFound": bool(bodies),
        "bodies": {key: bodies.count(lines[key]) for key in
                   ("bodiesFastest", "bodiesFall", "bodiesLag", "bodiesDrop", "bodiesStands")},
        "trackFall": track.count(lines["trackFall"]),
        "trackCleared": track.count(lines["fallCleared"]),
        "resetCleared": body(RESET_AIR_BODY, weapon).count(lines["fallCleared"]),
        "forgetCleared": body(FORGET_BODY, weapon).count(lines["fallCleared"]),
        "fallAnswer": body(FALL_SPEED_BODY, weapon).count(lines["fallAnswer"]),
        "phoneFound": bool(phone),
        "phoneJudge": phone.count(lines["phoneJudge"]),
        "phoneRefuse": phone.count(lines["phoneRefuse"]),
        "phoneCarry": phone.count(lines["phoneCarry"]),
        "phoneHumanoid": phone.count(lines["phoneHumanoid"]),
    }


def w3_fix2_reading(text, freeze_text: str) -> dict:
    """The W3 second fix round's lines (W3_FIX2_LINES and the bodies above), counted in the function
    each belongs to. `text` reads a repo file (empty when missing); freeze's body is source_reading's."""
    weapon = text(WEAPON_SERVICE)
    lines = W3_FIX2_LINES

    def body(pattern, source: str) -> str:
        found = pattern.search(source)
        return found.group(0) if found else ""

    attack = body(ATTACK_BODY, weapon)
    melee = body(MELEE_BODY, weapon)
    bodies = {}
    for side, (rel, pattern, call) in BODIES_BODY.items():
        inside = body(pattern, text(rel))
        bodies[side] = {
            "found": bool(inside),
            "players": inside.count(lines["players"]),
            "box": len(call.findall(inside)),
        }
    ghost = body(GHOST_BODY, text(REACT_FX))
    sink = body(SINK_BODY, text(REACT_FX))
    phone = body(PHONE_BODY, text(INPUT_CONTROLLER))
    strike = body(CLIENT_STRIKES["phone"][1], text(INPUT_CONTROLLER))
    attack_input = body(RANGE_ATTACK_BODY, text(INPUT_CONTROLLER))
    frost = body(CLIENT_STRIKES["frost"][1], text(FROST_FX))
    hitbox = body(CLIENT_STRIKES["hitbox"][1], text(FEEDBACK))
    return {
        "attackJudge": attack.count(lines["attackJudge"]),
        "attackPass": len(ATTACK_PASS.findall(attack)),
        "meleeAir": melee.count(lines["meleeAir"]),
        "finishAir": melee.count(lines["finishAir"]),
        "freezeSink": freeze_text.count(lines["freezeSink"]),
        "freezeHeld": freeze_text.count(lines["freezeHeld"]),
        "freezeCall": freeze_text.count(W3_LINES["freezeCall"]),
        "bodies": bodies,
        "ghostSink": ghost.count(lines["ghostSink"]),
        "ghostHolds": ghost.count(lines["ghostHolds"]),
        "phoneHolds": phone.count(lines["phoneHolds"]),
        "phoneGround": strike.count(lines["phoneGround"]),
        "predictedAir": attack_input.count(lines["predictedAir"]),
        "frostAir": frost.count(lines["swingAir"]),
        "hitboxAir": hitbox.count(lines["swingAir"]),
        "sinkReader": sink.count(lines["sinkReader"]),
    }


def w3_fix_reading(text, react_text: str, freeze_text: str) -> dict:
    """The W3 fix round's lines (W3_FIX_LINES and the bodies above), counted in the function each
    belongs to. `text` reads a repo file (empty when missing); React's and freeze's bodies are
    source_reading's."""
    level = text(LEVEL_SERVICE)
    weapon = text(WEAPON_SERVICE)

    def body(pattern, source: str) -> str:
        found = pattern.search(source)
        return found.group(0) if found else ""

    show = body(SHOW_ICE_BODY, level)
    construct = body(CONSTRUCT_BODY, level)
    grip = body(GRIP_BODY, level)
    sizes = body(SIZES_BODY, level)
    track = body(TRACK_AIR_BODY, weapon)
    reset = body(RESET_AIR_BODY, weapon)
    forget = body(FORGET_BODY, weapon)
    last = body(LAST_GROUND_BODY, weapon)
    melee = body(MELEE_BODY, weapon)
    lines = W3_FIX_LINES
    ice_branch = react_text.find(W3_LINES["reactIce"])
    # Per client copy: its function found, the SwingStrike line in it (and in the whole file, so a
    # second hand-built copy elsewhere in the file reads 2 calls or 0), and the smallest count of the
    # lines that pass the strike on.
    client = {}
    for name, (rel, pattern, call, uses) in CLIENT_STRIKES.items():
        source = text(rel)
        inside = body(pattern, source)
        client[name] = {
            "found": bool(inside),
            "call": inside.count(call),
            "calls": len(re.findall(r"\bWorldReact\.SwingStrike\(", source)),
            "uses": min(inside.count(line) for line in uses),
        }
    return {
        "client": client,
        "reactFound": bool(react_text) and ice_branch >= 0,
        # React's text before its ice branch: no `#` (no count of the reactive list or the ice).
        "reactCounted": react_text[: max(ice_branch, 0)].count("#") if ice_branch >= 0 else -1,
        "showFound": bool(show),
        "showLines": min(show.count(line) for line in SHOW_ICE_LINES),
        "showLinesMost": max(show.count(line) for line in SHOW_ICE_LINES),
        # Every call of showIce in the file (its own definition is `showIce(part: BasePart, ...`).
        "showCalls": len(re.findall(r"\bshowIce\((?!part: )", level)),
        "attributeOwn": len(OWN_ICE_ATTRIBUTE.findall(level)),
        "constructWater": construct.count(lines["constructWater"]),
        "constructGripAsk": construct.count(lines["constructGripAsk"]),
        "constructGrip": construct.count(lines["constructGrip"]),
        "constructReactive": construct.count(lines["constructReactive"]),
        "gripLook": grip.count(lines["gripLook"]),
        "gripReturn": grip.count(lines["gripReturn"]),
        "gripConst": level.count(lines["gripConst"]),
        "freezeShow": freeze_text.count(FREEZE_SHOW),
        "sizesCall": sizes.count(lines["sizesCall"]),
        "sizesReturn": sizes.count(lines["sizesReturn"]),
        "sizesUsed": level.count(lines["sizesUsed"]),
        "trackStood": track.count(lines["trackStood"]),
        "forgetStood": forget.count(lines["stoodCleared"]),
        "resetStood": reset.count(lines["stoodCleared"]),
        "lastGround": last.count(lines["lastGround"]),
        "meleeSwing": melee.count(lines["meleeSwing"]),
        "meleeFx": min(melee.count(line) for line in MELEE_FX_LINES),
        "meleeFxMost": max(melee.count(line) for line in MELEE_FX_LINES),
    }


def sources(repo: Path) -> dict:
    """SOURCES. (Until L4 W1b also every arena a level layout named, for ruling 27's adapter: no
    layout names one since the Raider Arena went.)"""
    return dict(SOURCES)


def fixtures(repo: Path) -> dict:
    """One local for every config a case reads (the bundle is one chunk of at most 200 locals)."""
    layouts = dict(read_folder(repo, "src/shared/Layouts/Levels"))
    return {
        "combat": read(repo, "src/shared/Config/Combat.json"),
        # The real files, as they ship (tests_l1.luau "the real files").
        "expeditions": read(repo, "src/shared/Config/Expeditions.json"),
        "proving": read(repo, "src/shared/Config/ProvingGrounds.json"),
        # L3 W2: the generated weapon models as they ship (nil when the file is missing: the cases
        # that read it then fail).
        "weaponModels": read_optional(repo, "src/shared/Config/WeaponModels.json"),
        "levels": [content for _, content in read_folder(repo, "src/shared/Config/Levels", True)],
        # Files of those two folders that Catalog does not read (it takes <n>_<Name> only), while
        # tools/check_levels.py reads every *.json there.
        "unread": sorted(
            f"{folder}/{path.name}"
            for folder in ("Config/Levels", "Config/Missions")
            for path in (repo / "src/shared" / folder).glob("*.json")
            if not re.match(NUMBERED, path.stem)
        ),
        "layouts": layouts,
        "gate": gate_reading(),
        "source": source_reading(repo),
    }


# The interpreter's typeof answers "table" for the cases' Vector3 shim; a module that checks
# `typeof(x) == "Vector3"` (SpawnSeed reads one off the network) must see "Vector3" for it.
TYPEOF = (
    "local typeof = function(value: any): string\n"
    '\tif type(value) == "table" and getmetatable(value) == getmetatable(Vector3.new(0, 0, 0)) then\n'
    '\t\treturn "Vector3"\n'
    "\tend\n"
    "\treturn typeof(value)\n"
    "end\n"
)


def wrap(name: str, text: str) -> str:
    """A module's source as `SOURCES.<name>`: a function of the globals the cases stub."""
    text = re.sub(r"(?m)^export type", "type", text)
    return (
        f"SOURCES.{name} = function(game, script, require, Vector3, os, task, warn, RaycastParams, Enum)\n"
        f"{TYPEOF}{text}\nend\n"
    )


def prelude(repo: Path) -> str:
    """Everything before the cases: ARMORY, FIXTURES and the wrapped modules."""
    parts = [
        f"local ARMORY: any = {to_luau(read(repo, 'src/shared/Config/Armory.json'))}\n",
        f"local FIXTURES: any = {to_luau(fixtures(repo))}\n",
        "local SOURCES = {}\n",
    ]
    for name, rel in sources(repo).items():
        parts.append(wrap(name, (repo / rel).read_text(encoding="utf-8")))
    return "".join(parts)


def bundle(repo: Path) -> str:
    parts = [prelude(repo)]
    for index, name in enumerate(TESTS):
        text = (HERE / name).read_text(encoding="utf-8")
        if index < len(TESTS) - 1:
            text = text.replace(VERDICT, "")
        parts.append(text)
    return "".join(parts)


def differences(repo: Path) -> list:
    """This harness's own files (this script and its case files) that `repo` holds differently
    from the ones running, or not at all."""
    differ = []
    for name in ["run_harness.py", *TESTS]:
        theirs = repo / "tools" / "crowd_harness" / name
        if not theirs.is_file() or theirs.read_bytes() != (HERE / name).read_bytes():
            differ.append(name)
    return differ


def main(argv: list) -> int:
    repo = Path(argv[1]) if len(argv) > 1 else HERE.parents[1]
    luau = argv[2] if len(argv) > 2 else str(HERE.parents[1] / "tools" / "bin" / "luau.exe")
    differ = differences(repo)
    if differ:
        print(
            f"run_harness: {repo} holds another harness than the one running ({HERE}): "
            f"{', '.join(differ)} differ. Run that checkout's own tools/crowd_harness/run_harness.py.",
            file=sys.stderr,
        )
        print(f"HARNESS: REFUSED (another checkout's harness, {HERE})")
        return 2
    path = HERE / "bundle.luau"
    path.write_text(bundle(repo), encoding="utf-8")
    try:
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired as hung:
        out = hung.stdout or b""
        print(out.decode("utf-8", "replace") if isinstance(out, bytes) else out)
        print(f"HARNESS: HUNG (stopped after {TIMEOUT_SECONDS} s, {HERE})")
        return 2
    except OSError as problem:
        print(f"run_harness: {luau} could not be run ({problem})", file=sys.stderr)
        print(f"HARNESS: SILENT (no case ran, {HERE})")
        return 2
    lines = result.stdout.splitlines()
    ran = sum(1 for line in lines if CHECK_LINE.match(line))
    verdicts = [index for index, line in enumerate(lines) if line.startswith("HARNESS: ")]
    if verdicts:
        # The bundle's own verdict, with the count and the folder added.
        last = verdicts[-1]
        passed = lines[last] == "HARNESS: PASS" and result.returncode == 0
        failed = re.match(r"HARNESS: FAIL \((\d+)\)$", lines[last])
        if passed:
            lines[last] = f"HARNESS: PASS ({ran:,} checks, {HERE})"
        elif failed:
            lines[last] = f"HARNESS: FAIL ({failed.group(1)} of {ran:,} checks, {HERE})"
        print("\n".join(lines))
        print(result.stderr, file=sys.stderr)
        return 0 if passed else 1
    print(result.stdout)
    print(result.stderr, file=sys.stderr)
    # No verdict: the bundle did not reach its last line.
    if ran == 0:
        print(f"HARNESS: SILENT (no case ran, {HERE})")
        return 2
    said = (result.stderr.strip().splitlines() or ["no error was printed"])[0]
    print(f"  FAIL  the bundle stopped after {ran} checks, before its verdict: {said}")
    print(f"HARNESS: FAIL (stopped after {ran:,} checks, {HERE})")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
