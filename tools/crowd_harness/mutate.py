"""Proves the harness cases are not vacuous. Copies the sources into `mutant/` beside this
file, undoes one rule at a time there, and runs the harness against the copy: every
mutation must fail at least one check.
Three things are settled before a mutation counts: every text a mutation replaces occurs
exactly once in its file (checked for the whole list before anything runs); the UNMUTATED copy
passes (run first: on a harness that fails or says nothing, every mutation would look caught);
and a mutant is caught only by a failing check. A harness with no verdict and no failing check
has run nothing and is listed as not caught.
Exits 1 when a mutation is out of date, the baseline does not pass, or one is not caught.
Usage: py tools/crowd_harness/mutate.py <repo root> <luau.exe> [filter] [from:to]
(`filter` = only the mutations whose label holds that text; "" = all of them; "files:<a>,<b>" =
only the mutations of the files whose repo path ends with one of those names, the run a fix round
owes for the files it changed.)"""
import shutil
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
luau = sys.argv[2]
only = sys.argv[3] if len(sys.argv) > 3 else ""
here = Path(__file__).parent
CROWD = "src/combat/server/Services/CrowdService.luau"
BRAIN = "src/combat/server/Services/CrowdBrain.luau"
VITALS = "src/combat/server/Services/VitalsService.luau"
FIELD = "src/combat/server/Services/ThreatField.luau"
TALLY = "src/combat/server/Services/StrikeTally.luau"
TUNING = "src/shared/Tuning.luau"
RING = "src/combat/server/Services/PositionRing.luau"
FLOW = "src/combat/server/Services/StageFlow.luau"
GEOMETRY = "src/combat/server/Services/LevelGeometry.luau"
COMBAT = "src/shared/Combat.luau"
CAMP = "src/combat/server/Services/CampBrain.luau"
FILES = [
    TALLY,
    TUNING,
    RING,
    FLOW,
    GEOMETRY,
    CAMP,
    COMBAT,
    "src/shared/Economy.luau",
    "src/shared/Config/Combat.json",
    "src/shared/Config/Missions/1_Village.json",
    "src/shared/CrowdCodec.luau",
    "src/shared/HitShapes.luau",
    "src/shared/Armory.luau",
    "src/shared/Config/Armory.json",
    BRAIN,
    CROWD,
    VITALS,
    FIELD,
]
# The data the harness's "real files" cases read (run_harness.py reads the same folders): copied
# whole into the mutant root. A mutation undoes a rule, never the data.
FILES += ["src/shared/Config/Expeditions.json", "src/shared/Config/ProvingGrounds.json"]
for folder, pattern in (
    ("src/shared/Config/Levels", "*.json"),
    ("src/shared/Config/Missions", "*.json"),
    ("src/shared/Layouts/Levels", "*.json"),
    ("src/shared/Layouts/Arenas", "*.luau"),
):
    for path in sorted((repo / folder).glob(pattern)):
        if f"{folder}/{path.name}" not in FILES:
            FILES.append(f"{folder}/{path.name}")
OVERLAY = "(overlaid and CrowdBrain.IsStriking(mind))"
BOTH = "elseif planted then\n" + "\t" * 6 + "continue\n" + "\t" * 5 + "end"
AIMED = "if not held and not (voided and strike.targetUserId == player.UserId) then"
FLOOR = "local floor = if y >= target.restY then target.restY else floorY + target.lift"
ENDED = "\t\tshot.flying = false\n\t\tflying -= 1\n"
STRIKING = "if attack == nil or not CrowdBrain.IsStriking(mind) then"
TAKEN = "local taken = held[userId] or 0"
RAISE = "local raise = math.min(count - living, room, #free)"
HITSHAPES = "src/shared/HitShapes.luau"
CODEC = "src/shared/CrowdCodec.luau"
REACHED = "if not usable(mind, index, attack) or distance > attack.reach + REACH_EPSILON then"
USES = "return uses == nil or (mind.landed[index] or 0) < math.floor(uses)"
GUARDED = "\t\tand def.guarded == true\n\t\tand (enemy.guard > 0 or (mind ~= nil and CrowdBrain.OwesCall(mind, def)))\n"
OWED = "and (attack.uses ~= nil or (mind.landed[index] or 0) == 0)"
DIED = 'enemy.state = "dead"\n\tnoteGone(enemy)\n\tlocal summoner = enemy.summoner\n\tif summoner ~= nil then\n\t\tsummoner.guard = math.max(summoner.guard - 1, 0)'
LEFT = "-- Removed alive (a set load, its summoner's death): it leaves its summoner's guard.\n\t\tlocal summoner = enemy.summoner\n\t\tif summoner ~= nil then\n\t\t\tsummoner.guard = math.max(summoner.guard - 1, 0)"
BRAIN_OF = "if mind.enraged and phaseDef ~= nil and phaseDef.brain ~= nil then"
SCALE = "local scale = if recover then phase.recoverScale else phase.windupScale"
CHAINED = "or mind.chained >= math.floor(phase.chain)"
RING_SWEEP = "local to = math.min(now - who.lag, endAt)\n\t\tlocal from = math.max(before - who.lag, leftAt)"
GIANTS = "\t\t\t\ttable.insert(giants, enemy)\n\t\t\telse\n\t\t\t\twidest = math.max(widest, radius)\n\t\t\tend\n"
MUTATIONS = {
    # Wave 1 and its review round.
    "no planting (the walked body)": (
        CROWD,
        "local planted = mind ~= nil and CrowdBrain.IsStriking(mind)\n\t\tlocal cx = math.floor(enemy.position.X",
        "local planted = false\n\t\tlocal cx = math.floor(enemy.position.X",
    ),
    "no planting (its neighbour)": (
        CROWD,
        "local otherPlanted = otherMind ~= nil and CrowdBrain.IsStriking(otherMind)\n\t\t\t\t\tif planted ~= otherPlanted",
        "local otherPlanted = false\n\t\t\t\t\tif planted ~= otherPlanted",
    ),
    "two planted bodies still split": (CROWD, BOTH, "end"),
    "no index under an overlay": (CROWD, OVERLAY, "false"),
    "index kept under a cancelled overlay": (CROWD, OVERLAY, "overlaid"),
    "the brain on the step's clock, not the frame's": (
        CROWD,
        "simulate(interval, started)",
        "simulate(interval, started - accumulator)",
    ),
    "18: no knock window at the decision": (
        VITALS,
        "local voided = covered or now < vitals.knockUntil",
        "local voided = covered",
    ),
    "18: hits waiting at the knock not voided": (VITALS, "other.covered = true", "other.covered = other.covered"),
    "21: reach measured in 3D": (
        BRAIN,
        "local distance = flat.Magnitude\n\tif distance > FACING_EPSILON then\n\t\tmind.facing = flat.Unit\n\tend\n\tlocal ready",
        "local distance = offset.Magnitude\n\tif distance > FACING_EPSILON then\n\t\tmind.facing = flat.Unit\n\tend\n\tlocal ready",
    ),
    "22: a hit cancels a due impact": (
        BRAIN,
        'if mind.phase ~= "windup" or attack == nil or isDue(mind, now) then',
        'if mind.phase ~= "windup" or attack == nil then',
    ),
    "22: a kill loses a due impact": (
        BRAIN,
        "\tif isDue(mind, now) then\n\t\tland(body, mind, def, crowd.threat)",
        "\tif false then\n\t\tland(body, mind, def, crowd.threat)",
    ),
    "24a: an instant shape judged though they were down": (
        VITALS,
        "\t\tor wasDown(vitals, strike.at)\n",
        "",
    ),
    "24b: the previous window forgotten": (VITALS, "or met(wasFrom, wasUntil, impact, limit)", "or false"),
    # Re-aimed for L3-2 (luau-engineer B): the range's body is Armory.RangeHp now.
    "17: the body keeps the profile's health": (VITALS, "\treturn Armory.RangeHp(armoryConfig)\n", "\treturn nil\n"),
    "23: effects wait for the crowd step": (VITALS, "\tsettle(config, now)\n\tflush()\n", "\tsettle(config, now)\n"),
    "26: an aimed miss under an i-frame says nothing": (VITALS, AIMED, "if not held then"),
    "26: any covered miss is a dodge, aimed or not": (VITALS, AIMED, "if not held and not voided then"),
    "26: every aimed miss is a dodge, i-frame or not": (
        VITALS,
        AIMED,
        "if not held and strike.targetUserId ~= player.UserId then",
    ),
    "26: the strike forgets who it was aimed at": (BRAIN, "targetUserId = mind.targetUserId,", "targetUserId = 0,"),
    # Wave 2: the keepAway brain.
    "keepAway never walks in": (BRAIN, "\tif distance > bandMax then\n", "\tif false then\n"),
    "keepAway never backs off": (BRAIN, "\telseif distance < bandMin then\n", "\telseif false then\n"),
    "keepAway stands through its recover": (
        BRAIN,
        '(phase == "recover" and not shooter)',
        'phase == "recover"',
    ),
    "a shooter turns its back as it walks": (BRAIN, "mind.watch = true", "mind.watch = false"),
    "a retreat ignores the arena's edge": (
        BRAIN,
        "return inArena(body.position - mind.facing * (bandMin - distance), def.radius), 0",
        "return body.position - mind.facing * (bandMin - distance), 0",
    ),
    # Wave 2: shot.
    "shot: no lead": (
        BRAIN,
        "aim = here + (ahead(here, target, flight + target.lag) - here) * lead",
        "aim = here + (ahead(here, target, flight + target.lag) - here) * 0",
    ),
    "shot: no gravity in the lead": (BRAIN, "if not target.resting then", "if false then"),
    "shot: aimed along the locked facing, not at T": (
        BRAIN,
        "strike.aim = if target ~= nil then ledAim(origin, here, target, attack) else here",
        "strike.aim = origin + mind.facing",
    ),
    "shot: judged with no lag": (
        FIELD,
        "local to = math.min(now - who.lag, endsAt)",
        "local to = math.min(now, endsAt)",
    ),
    "shot: no world ray": (
        FIELD,
        "local result = Workspace:Raycast(strike.origin, direction * path, world())",
        "local result = (nil :: any)",
    ),
    "shot: it flies on through the player it hurt": (
        FIELD,
        'if verdict == "landed" then',
        'if verdict == "landed" and shot.speed < 0 then',
    ),
    "shot: a voided contact stops it": (FIELD, 'if verdict == "landed" then', "if verdict ~= nil then"),
    "shot: no cap": (BRAIN, "if shotsHeld >= math.floor(threat.maxShots) then", "if false then"),
    "shot: a set load leaves them in the air": (VITALS, "\tThreatField.Clear(raise)\n", ""),
    "travelling: an aimed miss is never judged": (
        FIELD,
        "if not done[aimedAt] and judge(strike, who.player, aimAt, false) ~= nil then",
        "if false then",
    ),
    "travelling: judged though they were down": (
        VITALS,
        "if vitals == nil or vitals.down or wasDown(vitals, impactAt) or not judged(player) then",
        "if vitals == nil or vitals.down or not judged(player) then",
    ),
    # Wave 2: line.
    "line: never locks": (
        BRAIN,
        "\t\t\tmind.locked = true\n\t\t\tseen -= target.velocity * (now - lockAt)",
        "\t\t\tseen -= target.velocity * (now - lockAt)",
    ),
    "line: the lock is the step's sample": (BRAIN, "\t\t\tseen -= target.velocity * (now - lockAt)\n", ""),
    "line: locked from the windup's start": (
        BRAIN,
        'if shape == "shot" or shape == "lob" or shape == "line" then',
        'if shape == "shot" or shape == "lob" then',
    ),
    "line: it obeys the height rule": (
        VITALS,
        'local height = if shape == "line" then nil else attack.height',
        "local height = attack.height",
    ),
    "line: world geometry does not stop it": (
        FIELD,
        "local result = Workspace:Raycast(origin, toward * (cast / length), world())",
        "local result = (nil :: any)",
    ),
    # Wave 2: lob.
    "lob: judged at its throw": (VITALS, "\tstrike.at += seconds\n", ""),
    "lob: a knock voids one still in the air": (
        VITALS,
        "if other.vitals == vitals and other.strike.at <= now then",
        "if other.vitals == vitals then",
    ),
    "lob: pushed along its throw": (VITALS, 'elseif shape == "lob" then strike.aim', "elseif false then strike.aim"),
    "lob: with nothing under its target it lands at the root": (
        FIELD,
        "world())\n\treturn if result ~= nil then result.Position else Vector3.new(point.X, floorY, point.Z)\nend\n\n-- Where a barrage",
        "world())\n\treturn if result ~= nil then result.Position else point\nend\n\n-- Where a barrage",
    ),
    "lob: its circle is never tested": (VITALS, "return dx * dx + dz * dz <= radius * radius", "return true"),
    # Wave 2: lane.
    "lane: the brain does not carry the body": (
        BRAIN,
        "local run = math.clamp((stepNow - charge.at) * (charge.def.speed or 0), 0, length)",
        "local run = 0",
    ),
    "lane: the body stops short of its run": (
        BRAIN,
        "\t\tmind.charge = nil\n\t\treturn feet + charge.facing * length",
        "\t\tmind.charge = nil\n\t\treturn (nil :: any)",
    ),
    "lane: judged with no lag": (
        FIELD,
        "local to = math.min(now - who.lag, endAt)\n\t\tlocal from = math.max(before - who.lag, strike.at)",
        "local to = math.min(now, endAt)\n\t\tlocal from = math.max(before - who.lag, strike.at)",
    ),
    "lane: it hits again every step": (FIELD, "charge.done[who.userId] = true", "charge.done[who.userId] = nil"),
    "lane: a kill does not end it": (BRAIN, "charge.endedAt = now", "charge.endedAt = nil"),
    "lane: a hit staggers a charging brute": (
        CROWD,
        "\tif charging then\n\t\tmult = 0\n",
        "\tif false then\n\t\tmult = 0\n",
    ),
    "lane: the charge ignores the arena's edge": (
        BRAIN,
        "then math.min(range, runway(body.position, mind.facing, def.radius))",
        "then range",
    ),
    "lane: it has no height": (
        FIELD,
        "if to < from or (height ~= nil and who.feetY - strike.floorY > height) then\n\t\t\tcontinue\n\t\tend\n\t\t-- On the flat",
        "if to < from then\n\t\t\tcontinue\n\t\tend\n\t\t-- On the flat",
    ),
    "lane: its attack state lasts strikeSeconds": (BRAIN, "\t\t\t\tlasts = range / speed\n", "\t\t\t\tlasts = lasts\n"),
    # Wave 2: the plate.
    "plate: a light hit goes to it": (CROWD, "if amount < crowd.heavyHit then", "if false then"),
    "plate: its damage also takes HP": (
        CROWD,
        "\tif not plated then\n\t\tlocal removed",
        "\tdo\n\t\tlocal removed",
    ),
    "plate: no reel when it breaks": (
        CROWD,
        "stagger = math.max(stagger, math.max(crowd.plateBreakSeconds, 0))",
        "stagger = stagger + 0",
    ),
    "plate: the bar shows HP under it": (
        CROWD,
        "then enemy.plate / enemy.plateMax",
        "then enemy.hp / enemy.maxHp",
    ),
    "plate: the bit is never sent": (CROWD, "entry.plated = plated", "entry.plated = false"),
    "plate: armor applies under it too": (
        CROWD,
        "\t\tdealt = amount\n",
        "\t\tdealt = math.max(amount - math.max(def.armor, 0), 0)\n",
    ),
    # The lead's rulings on the finished wave 2.
    "A: a facing locked at the windup's start is not snapped": (
        BRAIN,
        "\t\t\tmind.facing = snapped(mind.facing)\n\t\t\tmind.locked = false",
        "\t\t\tmind.facing = mind.facing\n\t\t\tmind.locked = false",
    ),
    "A: a line's lock is not snapped": (
        BRAIN,
        "mind.facing = if mind.locked then snapped(heading) else heading",
        "mind.facing = heading",
    ),
    "A: a shove turns the wire yaw of a body that is not free": (
        CROWD,
        "enemy.yaw = yawToward(if moving and not mind.watch then desired else mind.facing)",
        "enemy.yaw = if free then yawToward(if moving and not mind.watch then desired else mind.facing) else enemy.yaw",
    ),
    "B: plate and health merged into one entry": (
        TALLY,
        "if blocked or hit.blocked == true or (hit.plate == true) == onPlate then",
        "if true then",
    ),
    "B: every entry counts as an enemy": (TALLY, "\t\tif not known then\n", "\t\tif true then\n"),
    "B: a blocked part keeps the entry blocked": (TALLY, "\t\tentry.blocked = nil\n", ""),
    # The wave 2 review round. 1a: the fall lead.
    "1a: the wave 2 rule (in the air = above the standing height, down to the crowd's floor)": (
        BRAIN,
        "\tif not target.resting then\n\t\t" + FLOOR,
        "\tif y - target.standY > 0.75 then\n\t\tlocal floor = target.standY",
    ),
    "1a: a jump off a block is led down to the crowd's floor": (BRAIN, FLOOR, "local floor = target.standY"),
    "1a: a fall off a block stops at the block's height": (BRAIN, FLOOR, "local floor = target.restY"),
    "1a: one still step is rest": (BRAIN, "resting = still and target.still", "resting = still"),
    "1a: the surface they stood on is never learnt": (
        BRAIN,
        "\t\tif resting then\n\t\t\ttarget.restY = position.Y\n\t\tend\n",
        "",
    ),
    # 1b: the line's ray.
    "1b: the line's ray is cast level": (
        FIELD,
        "local toward = if aim ~= nil then aim - origin else facing",
        "local toward = facing",
    ),
    "1b: the strike forgets the body it locked on": (
        BRAIN,
        "\t\t\tstrike.facing = mind.facing\n\t\t\tstrike.aim = mind.aim\n",
        "\t\t\tstrike.facing = mind.facing\n",
    ),
    "1b: the lane is as long as the ray flew": (
        FIELD,
        "return math.min(math.sqrt(reached.X * reached.X + reached.Z * reached.Z), range)",
        "return math.min(reached.Magnitude, range)",
    ),
    "1b: a climbing ray stops short of the range": (
        FIELD,
        "local cast = math.min(range / flat * length, MAX_RAY_STUDS)",
        "local cast = math.min(range, MAX_RAY_STUDS)",
    ),
    # 1c: the lob's floor.
    "1c: the lob lands on the crowd's floor, block or not": (
        VITALS,
        "throw(strike, ThreatField.Below(target, strike.floorY), first, serverOffset)",
        "throw(strike, Vector3.new(target.X, strike.floorY, target.Z), first, serverOffset)",
    ),
    "1c: its height is still measured from the crowd's floor": (VITALS, "\tstrike.floorY = centre.Y\n", ""),
    "1c: the lob reaches under its floor": (
        VITALS,
        "held = above <= height and above >= -height",
        "held = above <= height",
    ),
    # Retired by the L1b Wave 4 fix round's R6 (every ground shape has the lower bound now):
    # "1c: every ground shape has an under side" -> "l1b w4 fix crowd: only a lob has an under
    # side (R6)".
    # 2: a shot's path is cut once, at fire.
    "2: the cut is not in the seconds sent": (
        FIELD,
        "\t\tseconds = seconds,\n",
        "\t\tseconds = attack.seconds or 0,\n",
    ),
    "2: the shot flies on past the wall": (
        FIELD,
        "endsAt = strike.at + seconds,",
        "endsAt = strike.at + (attack.seconds or 0),",
    ),
    "2: an end is sent when it runs out or meets a wall": (
        FIELD,
        ENDED,
        "\t\tshot.flying = false\n\t\tflying -= 1\n"
        + '\t\traise({ kind = "enemyShotEnd", id = shot.id, at = shotAt(shot, endsAt), hit = false })\n',
    ),
    "2: a shot that ended still counts under the cap": (FIELD, ENDED, "\t\tshot.flying = false\n"),
    "2: a hit on a player sends no end": (
        FIELD,
        "\t\t\tif shot.flying then\n\t\t\t\tflying -= 1\n",
        "\t\t\tif shot.flying then\n\t\t\t\tflying -= 1\n\t\t\tend\n\t\t\tif false then\n",
    ),
    "2: a set load sends no end": (
        FIELD,
        "\t\tif shot.flying then\n\t\t\traise({",
        "\t\tif false then\n\t\t\traise({",
    ),
    # 3 and the minors.
    "3: a line that never locked fires unsnapped": (
        BRAIN,
        "\t\t\t\tmind.locked = true\n\t\t\t\tmind.facing = snapped(mind.facing)\n",
        "\t\t\t\tmind.locked = true\n",
    ),
    "6: the lead trusts any speed": (BRAIN, "elseif speed > stepFastest then", "elseif false then"),
    "6: no move is the fastest": (
        TUNING,
        "return math.max(movement.walkSpeed, movement.slamFallSpeed, dashSpeed, 0)",
        "return math.huge",
    ),
    # From the balance report: enemies of one kind take turns.
    "turns: no cap at all": (BRAIN, "if cap ~= nil and taken >= math.floor(cap) then", "if false then"),
    "turns: a kind with no perPlayer never attacks": (
        BRAIN,
        "if cap ~= nil and taken >= math.floor(cap) then",
        "if taken >= math.floor(cap or 0) then",
    ),
    "turns: every kind shares one set of places": (
        BRAIN,
        "\tlocal held = places[kind]\n\tif held == nil then\n\t\theld = {}\n\t\tplaces[kind] = held\n",
        '\tlocal held = places[""]\n\tif held == nil then\n\t\theld = {}\n\t\tplaces[""] = held\n',
    ),
    "turns: every player shares one set of places": (BRAIN, TAKEN, "local taken = held[7] or 0"),
    "turns: an attack state holds no place": (BRAIN, STRIKING, 'if attack == nil or mind.phase ~= "windup" then'),
    "turns: a recover holds a place": (BRAIN, STRIKING, 'if attack == nil or mind.phase == "approach" then'),
    "turns: a place is not given back when the attack ends": (
        BRAIN,
        "held[mind.targetUserId] = math.max((held[mind.targetUserId] or 0) - 1, 0)",
        "held[mind.targetUserId] = held[mind.targetUserId] or 0",
    ),
    "turns: places pile up from step to step": (
        BRAIN,
        "\tfor _, held in places do\n\t\ttable.clear(held)\n\tend\n",
        "",
    ),
    "turns: a shot in the air holds a place": (
        BRAIN,
        TAKEN,
        'local taken = (held[userId] or 0) + (if attack.shape == "shot" then shotsHeld else 0)',
    ),
    "turns: perPlayer may be tuned below 0": (TUNING, '\t"^crowd%.kinds%.[^.]+%.perPlayer$",\n', ""),
    # From the balance report: a shot is led over its flight plus the player's lag.
    "aim: refined twice, as before the table": (BRAIN, "local AIM_PASSES = 6", "local AIM_PASSES = 2"),
    "aim: refined five times": (BRAIN, "local AIM_PASSES = 6", "local AIM_PASSES = 5"),
    "lag: a shot is led over its flight alone": (
        BRAIN,
        "ahead(here, target, flight + target.lag)",
        "ahead(here, target, flight)",
    ),
    "lag: every player is led by the same lag": (
        CROWD,
        "local lag = Tuning.CommitLag(shooting, player:GetNetworkPing())",
        "local lag = Tuning.CommitLag(shooting, 0.05)",
    ),
    "lag: no ceiling on the lag": (
        TUNING,
        "\treturn math.min(\n\t\tseen + math.max(shooting.originLagSeconds, 0),\n"
        + "\t\tmath.max(shooting.originLagMaxSeconds, 0)\n\t)\n",
        "\treturn seen + math.max(shooting.originLagSeconds, 0)\n",
    ),
    "lag: the fixed allowance is left out": (
        TUNING,
        "\t\tseen + math.max(shooting.originLagSeconds, 0),\n",
        "\t\tseen,\n",
    ),
    # Stop 2. Choosing an attack.
    "choose: the first ready one in the list, whenever it was used": (
        BRAIN,
        "elseif (used or -math.huge) < bestAt then",
        "elseif best == 0 then",
    ),
    "choose: the last one again while another is ready": (BRAIN, "if index == mind.last then", "if false then"),
    "choose: cooldowns are ignored": (
        BRAIN,
        "if used ~= nil and now < used + math.max(attack.cooldown or 0, 0) - TIME_EPSILON then",
        "if false then",
    ),
    "choose: a cooldown runs from the windup's start": (
        BRAIN,
        "mind.usedAt[mind.attack] = impactAt",
        "mind.usedAt[mind.attack] = impactAt - math.max(attack.windup, 0)",
    ),
    "choose: reach is ignored": (
        BRAIN,
        REACHED,
        "if not usable(mind, index, attack) then",
    ),
    "choose: an enraged attack at any time": (
        BRAIN,
        "if attack.enraged == true and not mind.enraged then",
        "if false then",
    ),
    # Stop 2. The second phase.
    "enrage: asked of the raw share, not the byte": (
        BRAIN,
        "if CrowdCodec.SnapHp(body.hp / math.max(body.maxHp, 1)) <= phase.at then",
        "if body.hp / math.max(body.maxHp, 1) <= phase.at then",
    ),
    "enrage: the byte is rounded to nearest": (
        CODEC,
        "return encodeHp(fraction) / 255",
        "return math.round(fraction * 255) / 255",
    ),
    "enrage: under a plate too": (
        BRAIN,
        "if phase == nil or mind.enraged or body.plate > 0 then",
        "if phase == nil or mind.enraged then",
    ),
    "enrage: windups keep their length": (BRAIN, SCALE, "local scale = if recover then phase.recoverScale else 1"),
    "enrage: recovers keep their length": (BRAIN, SCALE, "local scale = if recover then 1 else phase.windupScale"),
    "enrage: not asked when an attack ends": (
        BRAIN,
        "\t\tlocal chains = mind.enraged\n\t\tenrage(body, mind, def)\n",
        "\t\tlocal chains = mind.enraged\n",
    ),
    "chain: straight out of the attack the phase began in": (
        BRAIN,
        "\t\tlocal chains = mind.enraged\n\t\tenrage(body, mind, def)\n",
        "\t\tenrage(body, mind, def)\n\t\tlocal chains = mind.enraged\n",
    ),
    "chain: never": (BRAIN, CHAINED, "or true"),
    "chain: one attack too many": (BRAIN, CHAINED, "or mind.chained > math.floor(phase.chain)"),
    "chain: the count never starts over": (
        BRAIN,
        "if ready and begin(body, mind, def, attacks, threat, target, distance, now, 1) then",
        "if ready and begin(body, mind, def, attacks, threat, target, distance, now, mind.chained + 1) then",
    ),
    "chain: the place is not given back first": (
        BRAIN,
        "\t\trelease(body, mind)\n\t\t-- A chain is made",
        "\t\t-- A chain is made",
    ),
    # Stop 2. The ring.
    "ring: judged with no lag": (FIELD, RING_SWEEP, "local to = math.min(now, endAt)\n\t\tlocal from = math.max(before - who.lag, leftAt)"),
    # Its text follows R15 (the L1b Wave 4 fix round: the ring has the lower bound too).
    "ring: it has no height": (
        FIELD,
        "if to < from or (height ~= nil and (rise > height or rise < -height)) then",
        "if to < from then",
    ),
    "ring: it hits again every step": (FIELD, "ring.done[who.userId] = true", "ring.done[who.userId] = nil"),
    "ring: it reaches past its radius": (FIELD, "if distance > ring.radius then", "if false then"),
    "ring: its front has no leading half": (
        FIELD,
        "local reached = leftAt + (distance - halfWidth) / speed",
        "local reached = leftAt + distance / speed",
    ),
    "ring: its front has no trailing half": (
        FIELD,
        "local passed = leftAt + (distance + halfWidth) / speed",
        "local passed = leftAt + distance / speed",
    ),
    "ring: ruling 26 is never asked": (
        FIELD,
        "ring.missed = aimedMiss(strike, ring.done, ring.aimAt, endAt, now, standing, maxLag, judge)",
        "ring.missed = true",
    ),
    "ring: aimed at its own origin": (FIELD, "aimAt = strike.at + aimed / speed,", "aimAt = strike.at,"),
    "ring: its record never goes": (
        FIELD,
        "\t\tring.missed = aimedMiss(strike, ring.done, ring.aimAt, endAt, now, standing, maxLag, judge)\n\tend\n\treturn now - maxLag < endAt",
        "\t\tring.missed = aimedMiss(strike, ring.done, ring.aimAt, endAt, now, standing, maxLag, judge)\n\tend\n\treturn true",
    ),
    "ring: pushed along its facing": (VITALS, 'if shape == "arc" or shape == "ring"', 'if shape == "arc"'),
    "ring: judged as a frozen shape": (VITALS, 'elseif shape == "ring" then', 'elseif shape == "ring" and false then'),
    # Stop 2. The summon.
    "summon: a dead summoner still calls": (
        CROWD,
        "if summoner == nil or summoner.deadAt ~= nil or kind == nil then",
        "if summoner == nil or kind == nil then",
    ),
    "summon: maxAlive is not asked": (CROWD, RAISE, "local raise = math.min(count - living, #free)"),
    "summon: under maxAlive the first free places, not spread": (
        CROWD,
        "local place = free[index * #free // raise + 1]",
        "local place = free[index + 1]",
    ),
    "top-up: every call raises the full count": (
        CROWD,
        "if other.summoner == summoner and other.deadAt == nil then",
        "if false then",
    ),
    "top-up: a body in its dead state still counts": (
        CROWD,
        "if other.summoner == summoner and other.deadAt == nil then",
        "if other.summoner == summoner then",
    ),
    "top-up: more living than count when count was lowered": (
        CROWD,
        RAISE,
        "local raise = math.min(room, #free)",
    ),
    "top-up: the new bodies ignore which places are held": (CROWD, "\t\tif not held[place] then\n", "\t\tif true then\n"),
    "top-up: a summoned body forgets its place": (CROWD, "\t\t\trisen.place = place\n", ""),
    "summon: the circle ignores the summoner's facing": (
        CROWD,
        "local angle = summoner.yaw + (place + turned) / count * 2 * math.pi",
        "local angle = (place + turned) / count * 2 * math.pi",
    ),
    "summon: they stand idle": (
        CROWD,
        'local risen = enemies[CrowdService.Spawn(kind, spot, "fight")]',
        'local risen = enemies[CrowdService.Spawn(kind, spot, "idle")]',
    ),
    "summon: left behind when the summoner dies": (CROWD, "if other.summoner == enemy then", "if false then"),
    "summon: the summoner does not know it called": (CROWD, "summoner.summoned += 1", "summoner.summoned += 0"),
    # Stop 2. A boss's death, a set load.
    "boss: its attacks outlive it": (CROWD, "dismiss(enemy, boss)", "dismiss(enemy, false)"),
    "boss: every kind's attacks die with it": (CROWD, "dismiss(enemy, boss)", "dismiss(enemy, true)"),
    "boss: its queued impact is still handed over": (CROWD, "\tCrowdBrain.Recall(ids)\n", ""),
    "boss: decisions still waiting are kept": (VITALS, "if not ids[entry.strike.bodyId] then", "if true then"),
    "boss: what travels is kept": (VITALS, "\tThreatField.Drop(ids, raise)\n", ""),
    "boss: its ring is kept": (FIELD, "return not ids[ring.strike.bodyId]", "return true"),
    "boss: its charge is kept": (FIELD, "return not ids[charge.strike.bodyId]", "return true"),
    "boss: its shot is kept": (
        FIELD,
        "\t\tif not ids[shot.strike.bodyId] then\n\t\t\treturn true\n\t\tend\n",
        "\t\tif true then\n\t\t\treturn true\n\t\tend\n",
    ),
    "set load: an impact still queued survives": (CROWD, "\tCrowdBrain.DrainStrikes(nil)\n", ""),
    "set load: rings survive": (FIELD, "\ttable.clear(rings)\n", ""),
    # Stop 2. The barrage.
    "barrage: one circle whatever the count": (VITALS, "if count >= 2 then", "if false then"),
    "barrage: every circle hits the same player": (
        VITALS,
        "if volley ~= nil and volley[player.UserId] then",
        "if false then",
    ),
    "barrage: the circles share one strike": (VITALS, "circles[index] = table.clone(strike)", "circles[index] = strike"),
    "barrage: a scattered circle is probed from root height": (
        VITALS,
        "local centre = ThreatField.Landing(point, floorY)",
        "local centre = ThreatField.Below(point, floorY)",
    ),
    "barrage: not seeded by its first id": (
        VITALS,
        "HitShapes.Barrage(target, count, spread, first)",
        "HitShapes.Barrage(target, count, spread, 1)",
    ),
    "barrage: every circle at the full spread": (
        HITSHAPES,
        "local distance = reach * math.sqrt(share)",
        "local distance = reach",
    ),
    "barrage: all round one angle": (
        HITSHAPES,
        "local angle = turn + FULL_TURN * (index - 1) / outer",
        "local angle = turn",
    ),
    # Stop 2. Nothing moves it; large bodies.
    "reel: a body nothing moves does not reel at its plate's break": (
        CROWD,
        'local reels = verdict == "broke" and not charging',
        'local reels = verdict == "broke" and not charging and mult > 0',
    ),
    "reel: the break does not cancel a windup that nothing interrupts": (
        BRAIN,
        "if reels or (rule ==",
        "if (rule ==",
    ),
    "reel: every hit reels a body nothing moves": (
        CROWD,
        'local reels = verdict == "broke" and not charging',
        "local reels = not charging",
    ),
    "separate: a giant widens what every body scans": (
        CROWD,
        GIANTS,
        "\t\t\t\ttable.insert(giants, enemy)\n\t\t\tend\n\t\t\twidest = math.max(widest, radius)\n",
    ),
    "separate: a small body pushes a large one": (CROWD, "\t\t\t\t\tlocal shareA = 0\n", "\t\t\t\t\tlocal shareA = 0.5\n"),
    "separate: a large body shoves a planted small one": (
        CROWD,
        "\t\t\t\t\telseif otherPlanted then\n",
        "\t\t\t\t\telseif false then\n",
    ),
    "separate: large bodies are never separated": (CROWD, "\tif #giants > 0 then\n", "\tif false then\n"),
    "separate: the main pass handles large bodies too": (
        CROWD,
        "\t\t\t\t\tif otherDef.radius >= largeRadius then\n",
        "\t\t\t\t\tif false then\n",
    ),
    # Stop 2, the review round.
    "review: a shot does not name its body": (FIELD, "\t\tenemyId = strike.bodyId,\n", "\t\tenemyId = 0,\n"),
    "review: a circle does not name its body": (VITALS, "\t\tenemyId = strike.bodyId,\n", "\t\tenemyId = 0,\n"),
    "review: the large line is fixed at 3": (CROWD, "separate(crowd.largeRadius)", "separate(3)"),
    "review: largeRadius may be tuned below 0": (TUNING, '\t"^crowd%.largeRadius$",\n', ""),
    "review: a removed body is booked as a hit of 0": (
        TALLY,
        '\tif verdict == "gone" or verdict == "held" then\n',
        '\tif verdict == "held" then\n',
    ),
    "review: Damage does not say a body is gone": (
        CROWD,
        '\t\treturn 0, false, "gone"\n',
        "\t\treturn 0, false, nil\n",
    ),
    # Stop 3. calm, uses.
    "calm: a calm attack in the second phase too": (BRAIN, "if attack.calm == true and mind.enraged then", "if false then"),
    "uses: no limit": (BRAIN, USES, "return true"),
    "uses: one more than allowed": (BRAIN, USES, "return uses == nil or (mind.landed[index] or 0) <= math.floor(uses)"),
    "uses: never counted": (
        BRAIN,
        "\t\tmind.landed[mind.attack] = (mind.landed[mind.attack] or 0) + 1\n",
        "",
    ),
    # Stop 3. guarded.
    "guarded: his plate is never guarded": (CROWD, GUARDED, "\t\tand false\n"),
    "guarded: guarded with no guard alive": (CROWD, GUARDED, "\t\tand def.guarded == true\n"),
    "guarded: every plated summoner is": (
        CROWD,
        GUARDED,
        "\t\tand (enemy.guard > 0 or (mind ~= nil and CrowdBrain.OwesCall(mind, def)))\n",
    ),
    "guarded: open until the guard has risen": (
        CROWD,
        GUARDED,
        "\t\tand def.guarded == true\n\t\tand enemy.guard > 0\n",
    ),
    "guarded: a hit of 0 on a guarded plate is a plain hit": (
        CROWD,
        "\tif enemy.deadAt ~= nil then\n\t\treturn 0, false, nil\n\tend\n",
        "\tif enemy.deadAt ~= nil or not isFinite(amount) or amount <= 0 then\n\t\treturn 0, false, nil\n\tend\n",
    ),
    "guarded: an unlimited call is owed for ever": (BRAIN, OWED, "and true"),
    "guarded: a limited call is owed only until its first use": (BRAIN, OWED, "and (mind.landed[index] or 0) == 0"),
    "guarded: a call it can no longer make is still owed": (
        BRAIN,
        '\t\t\tattack.shape == "summon"\n\t\t\tand usable(mind, index, attack)\n',
        '\t\t\tattack.shape == "summon"\n',
    ),
    "guarded: any attack left counts as a call": (
        BRAIN,
        '\t\t\tattack.shape == "summon"\n\t\t\tand usable(mind, index, attack)\n',
        "\t\t\tusable(mind, index, attack)\n",
    ),
    "guarded: it reads as an ordinary block": (CROWD, '\t\treturn 0, false, "guarded"\n', '\t\treturn 0, false, "blocked"\n'),
    "guarded: a guard in its dead state still guards": (CROWD, DIED, DIED.replace("summoner.guard - 1", "summoner.guard")),
    "guarded: a guard removed alive still guards": (CROWD, LEFT, LEFT.replace("summoner.guard - 1", "summoner.guard")),
    "guarded: a summoned body does not join the guard": (CROWD, "\t\t\tsummoner.guard += 1\n", ""),
    "guarded: the spawn does not name its summoner": (CROWD, "\t\t\trisen.spawnInfo.summonerId = summoner.id\n", ""),
    "guarded: the hit is not marked": (TALLY, "\t\t\tguarded = if guarded then true else nil,\n", ""),
    "guarded: the hit is not a block": (
        TALLY,
        'local blocked = verdict == "blocked" or guarded',
        'local blocked = verdict == "blocked"',
    ),
    "guarded: the mark outlives a real hit": (TALLY, "\t\tentry.guarded = nil\n", ""),
    # Stop 3. enrage.brain, and where the summons rise.
    "brain: the enraged brain is never taken": (BRAIN, BRAIN_OF, "if false then"),
    "brain: the enraged brain from the start": (BRAIN, BRAIN_OF, "if phaseDef ~= nil and phaseDef.brain ~= nil then"),
    "summon: one rises straight behind its summoner": (
        CROWD,
        "local turned = if count % 2 == 0 then 0.5 else 0",
        "local turned = 0",
    ),
    "tuning: enrage.brain may be anything": (
        TUNING,
        'pattern = "^crowd%.kinds%.[^.]+%.enrage%.brain$",',
        'pattern = "^never2$",',
    ),
    # Stop 2. Tuning.
    "tuning: the new shapes are not legal": (TUNING, '"shot", "lob", "ring", "summon" })', '"shot", "lob" })'),
    "tuning: summon may name anything": (
        TUNING,
        'pattern = "^crowd%.kinds%.[^.]+%.attacks%.%d+%.summon$",',
        'pattern = "^never$",',
    ),
    "tuning: enrage numbers may go below 0": (TUNING, '\t"^crowd%.kinds%.[^.]+%.enrage%.[^.]+$",\n', ""),
    # P5 wave 1: the crowd in a mission (tests_p5.luau).
    "p5: plate loss scaled": (
        CROWD,
        "enemy.plate = math.max(enemy.plate - amount, 0)",
        "enemy.plate = math.max(enemy.plate - amount * (scale or 1), 0)",
    ),
    "p5: damageBy uncapped": (CROWD, "local removed = math.min(dealt, enemy.hp)", "local removed = dealt"),
    "p5: mayJudge skipped for areas": (VITALS, "\t\tor not judged(player)\n\tthen", "\tthen"),
    "p5: canTarget ignores mayJudge": (
        VITALS,
        "return (vitals == nil or not vitals.down) and judged(player)",
        "return vitals == nil or not vitals.down",
    ),
    "p5: hpMult ignored": (
        CROWD,
        "local maxHp = math.max(def.hp * scales.hp * bodyMult, 1)",
        "local maxHp = math.max(def.hp * scales.hp, 1)",
    ),
    "p5: plate not scaled": (
        CROWD,
        "local plate = math.max((def.plate or 0) * scales.plate, 0)",
        "local plate = math.max(def.plate or 0, 0)",
    ),
    "p5: armour judged on the scaled amount": (
        CROWD,
        "\t\tdealt = math.max(\n\t\t\tamount - math.max(def.armor, 0),\n\t\t\tamount * math.clamp(crowd.armorFloor, 0, 1)\n\t\t) * lossScale",
        "\t\tdealt = math.max(\n\t\t\tamount * lossScale - math.max(def.armor, 0),\n\t\t\tamount * lossScale * math.clamp(crowd.armorFloor, 0, 1)\n\t\t)",
    ),
    "p5: the interrupt judges the scaled amount": (
        CROWD,
        "CrowdBrain.OnHit(mind, def, amount, stagger > 0, reels, crowd.heavyHit, os.clock())",
        "CrowdBrain.OnHit(mind, def, amount * (scale or 1), stagger > 0, reels, crowd.heavyHit, os.clock())",
    ),
    "p5: enemy damage not rounded": (
        VITALS,
        "amount = math.max(math.round(amount * rules.damageScale), 1)",
        "amount = math.max(amount * rules.damageScale, 1)",
    ),
    "p5: onDown every frame": (VITALS, "\tlocal list = downed\n\tdowned = {}\n", "\tlocal list = downed\n"),
    "p5: a mission down gets up by itself": (
        VITALS,
        "vitals.downUntil = math.huge",
        "vitals.downUntil = now + math.max(config.player.downSeconds, 0)",
    ),
    "p5: regen share ignored": (VITALS, "return math.max(rules.regenShare, 0) * humanoid.MaxHealth", "return 0"),
    "p5: a new character ends a mission down": (
        VITALS,
        "local stayDown = mission ~= nil and vitals.down",
        "local stayDown = false",
    ),
    "p5: KillAll kills nobody": (CROWD, "\t\t\tdie(enemy, currentDef(enemy, crowd.kinds), crowd, byUserId)\n", ""),
    # Review round: ruling 18 judged from state (VitalsService.RunLost).
    "p5 lost: a member on the pad still fights": (
        VITALS,
        "if member.bot or player == nil or member.waiting then",
        "if member.bot or player == nil then",
    ),
    "p5 lost: a dead partner still stands": (
        VITALS,
        "if root ~= nil and not VitalsService.IsDown(player) then",
        "if not VitalsService.IsDown(player) then",
    ),
    "p5 lost: a downed fighter still stands": (
        VITALS,
        "if root ~= nil and not VitalsService.IsDown(player) then",
        "if root ~= nil then",
    ),
    "p5 lost: an empty fight is lost": (
        VITALS,
        "return fieldClear ~= true and #fighters > 0 and not anyStanding, fighters",
        "return fieldClear ~= true and not anyStanding, fighters",
    ),
    "p5 lost: a clear field does not win": (
        VITALS,
        "return fieldClear ~= true and #fighters > 0 and not anyStanding, fighters",
        "return #fighters > 0 and not anyStanding, fighters",
    ),
    # Second review round.
    "p5: a start does not wait for bodies": (
        VITALS,
        "if not member.bot and player ~= nil and bodyOf(player) == nil then",
        "if false then",
    ),
    "p5: ClearThreats keeps the queued decisions": (
        VITALS,
        "function VitalsService.ClearThreats(): ()\n\ttable.clear(pending)\n",
        "function VitalsService.ClearThreats(): ()\n",
    ),
    "p5: the perf line counts an empty field": (
        CROWD,
        "if perf.every <= 0 or aliveCount == 0 then",
        "if perf.every <= 0 then",
    ),
    # Ruling 7: the server's own reading of a player's speed (PositionRing), and its span.
    "speed ring: the divisor floor removed": (RING, "/ math.max(elapsed, stretch)", "/ elapsed"),
    "speed ring: the index without the modulo": (
        RING,
        "return (history.head - order) % history.capacity + 1",
        "return history.head - order + 1",
    ),
    "speed ring: the anchor is not moved back to the span": (
        RING,
        "\t\twhile anchorOrder < count and endAt - history.times[anchor] < stretch do\n\t\t\tanchorOrder += 1\n\t\t\tanchor = indexOf(history, anchorOrder)\n\t\tend\n",
        "\t\twhile anchorOrder < count and endAt - history.times[anchor] < 0 do\n\t\t\tanchorOrder += 1\n\t\t\tanchor = indexOf(history, anchorOrder)\n\t\tend\n",
    ),
    "speed ring: the window break removed": (
        RING,
        "\t\t\tif now - endAt > window then\n\t\t\t\tbreak\n\t\t\tend\n",
        "",
    ),
    "speed ring: a bad span is not the whole window": (
        RING,
        "local stretch = if span > 0 and span < window then span else window",
        "local stretch = if span > 0 and span < window then span else 0",
    ),
    "tuning: the speed span may be 0 or outlast its window": (
        TUNING,
        "return value > 0 and base ~= nil and value <= base.shooting.originLagMaxSeconds",
        "return true",
    ),
}

# L1: the run's rules (StageFlow, tests_l1.luau), Combat's camp functions, CrowdService's floor.
L1_MUTATIONS = {
    "l1: a camp triggers with nobody inside": (
        FLOW,
        "\t\t\treturn true\n\t\tend\n\tend\n\treturn false\nend\n\n-- The stage index of the camp that may trigger now",
        "\t\t\treturn true\n\t\tend\n\tend\n\treturn true\nend\n\n-- The stage index of the camp that may trigger now",
    ),
    "l1: the trigger ignores height": (
        FLOW,
        "\t\t\tabove >= -rules.triggerBelow\n\t\t\tand above <= zone.ceiling\n\t\t\tand inRect(zone.trigger, root.X, root.Z)",
        "\t\t\tinRect(zone.trigger, root.X, root.Z)",
    ),
    "l1: the trigger reaches any depth under the floor": (
        FLOW,
        "\t\t\tabove >= -rules.triggerBelow\n\t\t\tand above <= zone.ceiling\n",
        "\t\t\tabove <= zone.ceiling\n",
    ),
    "l1: the trigger stops at the floor's edge": (
        FLOW,
        "trigger = grown(rect, fence),",
        "trigger = rect,",
    ),
    "l1: the trigger is the close's rectangle": (
        FLOW,
        "trigger = grown(rect, fence),",
        "trigger = inner,",
    ),
    "l1: a camp that is not next triggers": (
        FLOW,
        'elseif state.step == "travel" then state.stage + 1',
        'elseif state.step == "travel" then state.stage + 3',
    ),
    "l1: a downed body triggers a camp": (
        FLOW,
        "\t\t\tand (standing == nil or standing[index] ~= false)\n",
        "",
    ),
    "l1: the last clear lets the waiting into the ending level": (
        FLOW,
        '\ttable.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })\n\tif not lastWave then',
        '\ttable.insert(actions, { kind = "boundary", stage = state.stage, release = true })\n\tif not lastWave then',
    ),
    "l1: a boundary the run goes on from lets nobody in": (
        FLOW,
        '\ttable.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })\n\tif not lastWave then',
        '\ttable.insert(actions, { kind = "boundary", stage = state.stage, release = false })\n\tif not lastWave then',
    ),
    "l1: a skip that ends the run lets the waiting in": (
        FLOW,
        '\t\t\ttable.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })\n\t\t\tleaveCamp',
        '\t\t\ttable.insert(actions, { kind = "boundary", stage = state.stage, release = true })\n\t\t\tleaveCamp',
    ),
    "l1: the close's grace judges the close's margin": (
        FLOW,
        "return not inRect(zone.rect, position.X, position.Z)",
        "return not inRect(zone.inner, position.X, position.Z)",
    ),
    "l1: the gates close at once": (FLOW, "if input.now >= state.gateAt then", "if true then"),
    "l1: the countdown is not gateSeconds": (FLOW, "\t\telse rules.gateSeconds\n", "\t\telse 1\n"),
    "l1: the gates close on a yard nobody can fight in": (
        FLOW,
        "\t\t\tif fallen ~= nil then\n\t\t\t\t-- But somebody has to be able to fight.",
        "\t\t\tif false then\n\t\t\t\t-- But somebody has to be able to fight.",
    ),
    "l1: a re-armed camp is no longer the next": (
        FLOW,
        '\t\t\t\tstate.step = "armed"\n\t\t\t\tstate.gateAt = 0\n',
        '\t\t\t\tstate.step = "travel"\n\t\t\t\tstate.gateAt = 0\n',
    ),
    "l1: a re-arm forgets the boss skip's wave": (
        FLOW,
        '\t\t\t\tstate.step = "armed"\n\t\t\t\tstate.gateAt = 0\n',
        '\t\t\t\tstate.step = "armed"\n\t\t\t\tstate.firstWave = 1\n\t\t\t\tstate.gateAt = 0\n',
    ),
    "l1: a clear with a boss still pending": (
        FLOW,
        "if stage == nil or not input.spawningDone then",
        "if stage == nil then",
    ),
    "l1: a camp clear without bank": (
        FLOW,
        "if lastWave or stage.bankEachWave then",
        "if stage.bankEachWave then",
    ),
    "l1: bankEachWave ignored": (FLOW, "if lastWave or stage.bankEachWave then", "if lastWave then"),
    "l1: a bank counts one wave whatever it covers": (FLOW, "count = wave - state.settled,", "count = 1,"),
    "l1: the last camp does not end the run": (
        FLOW,
        '\t\ttable.insert(actions, over(state, "cleared"))\n\t\treturn\n',
        '\t\tover(state, "cleared")\n\t\treturn\n',
    ),
    "l1: a merge into a boss wave": (FLOW, "\t\t\tand not stage.boss[wave + 1]\n", ""),
    "l1: a merge out of a boss wave": (FLOW, "\t\t\tand not stage.boss[wave]\n", ""),
    "l1: a merge in a stage that does not merge": (
        FLOW,
        "\t\t\tstage.merge\n\t\t\tand wave < stage.waves\n",
        "\t\t\twave < stage.waves\n",
    ),
    "l1: the stage's own breather ignored": (
        FLOW,
        "input.now + (stage.breatherSeconds or input.breatherSeconds)",
        "input.now + input.breatherSeconds",
    ),
    "l1: fallen wins on a clear field": (
        FLOW,
        "if fallen ~= nil and not fieldClear then",
        "if fallen ~= nil then",
    ),
    "l1: the fallen are asked before the cap": (
        FLOW,
        "\tif input.runCap then\n",
        "\tif input.runCap and (input.fallen == nil or StageFlow.FieldClear(plan, state, input)) then\n",
    ),
    "l1: an end that banks": (
        FLOW,
        "\t\ttable.insert(actions, over(state, fallen))\n",
        '\t\ttable.insert(actions, { kind = "bank", stage = state.stage, wave = state.wave, count = 1 })\n\t\ttable.insert(actions, over(state, fallen))\n',
    ),
    "l1: the run cap banks": (
        FLOW,
        '\t\ttable.insert(actions, over(state, "runCap"))\n',
        '\t\ttable.insert(actions, { kind = "bank", stage = state.stage, wave = state.wave, count = 1 })\n\t\ttable.insert(actions, over(state, "runCap"))\n',
    ),
    "l1: a skip that banks": (
        FLOW,
        '\t\t\ttable.insert(actions, { kind = "drop", stage = state.stage })\n\t\t\ttable.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })\n',
        '\t\t\ttable.insert(actions, { kind = "drop", stage = state.stage })\n\t\t\ttable.insert(actions, { kind = "bank", stage = state.stage, wave = state.wave, count = 1 })\n\t\t\ttable.insert(actions, { kind = "boundary", stage = state.stage, release = not ending })\n',
    ),
    "l1: a boss skip credits the waves it passed": (
        FLOW,
        "\tstate.firstWave = 1\n\tstate.step = \"fight\"\n\tstate.wave = first\n\tstate.settled = first - 1\n",
        "\tstate.firstWave = 1\n\tstate.step = \"fight\"\n\tstate.wave = first\n\tstate.settled = 0\n",
    ),
    "l1: a boss skip leaves the camp it left on the field": (
        FLOW,
        '\tif live or step == "gate" then\n',
        "\tif false then\n",
    ),
    "l1: a boss skip out of a countdown drops nothing": (
        FLOW,
        '\tif live or step == "gate" then\n',
        "\tif live then\n",
    ),
    "l1: SafePoint of a live camp is the start": (
        FLOW,
        "\t\tif zone ~= nil then\n\t\t\treturn zone.entry\n\t\tend\n",
        "\t\tif zone ~= nil then\n\t\t\treturn plan.start\n\t\tend\n",
    ),
    "l1: SafePoint forgets the cleared camp": (
        FLOW,
        "\tif zone ~= nil then\n\t\treturn zone.exit\n\tend\n",
        "",
    ),
    "l1: IsOut uses the level box in a closed camp": (
        FLOW,
        '\tlocal step = state.step\n\tif step == "fight" or step == "breather" then\n\t\tlocal stage = plan.stages[state.stage]\n\t\tlocal zone = if stage ~= nil then stage.zone else nil\n\t\tif zone ~= nil then\n\t\t\tlocal rect = zone.rect',
        '\tlocal step = state.step\n\tif false then\n\t\tlocal stage = plan.stages[state.stage]\n\t\tlocal zone = if stage ~= nil then stage.zone else nil\n\t\tif zone ~= nil then\n\t\t\tlocal rect = zone.rect',
    ),
    "l1: a closed camp's kill height is the level's": (
        FLOW,
        "return position.Y < zone.floorY - rescue.below",
        "return position.Y < plan.killY",
    ),
    "l1: once a run is over a body in the lobby is put into its level": (
        FLOW,
        '\tif state.step == "over" then\n\t\treturn if inLobby or not out then nil else "lobby"\n\tend\n',
        "",
    ),
    "l1: the end pulls the whole party into the lobby": (
        FLOW,
        'return if inLobby or not out then nil else "lobby"',
        'return if inLobby then nil else "lobby"',
    ),
    "l1: once a run is over a fall is left to fall": (
        FLOW,
        'return if inLobby or not out then nil else "lobby"',
        "return nil",
    ),
    "l1: a member who waits is judged by the level's box": (
        FLOW,
        "\tif plan == nil or state == nil or waiting then\n",
        "\tif plan == nil or state == nil then\n",
    ),
    "l1: the close moves only who is off the floor": (
        FLOW,
        "local inner = grown(rect, -rules.closeInset)",
        "local inner = rect",
    ),
    "l1: an entry in the close's band is planned": (
        FLOW,
        "if not inRect(zone.inner, zone.entry.X, zone.entry.Z) then",
        "if false then",
    ),
    "l1: the close is judged once": (
        FLOW,
        "\t\tand now - state.closedAt < rules.closeGraceSeconds\n",
        "\t\tand false\n",
    ),
    "l1: the close's grace never ends": (
        FLOW,
        "\t\tand now - state.closedAt < rules.closeGraceSeconds\n",
        "\t\tand now >= state.closedAt\n",
    ),
    "l1: the close does not stamp its time": (FLOW, "\tstate.closedAt = now\n", ""),
    "l1: the tempo is frozen through a breather": (
        FLOW,
        '\treturn step == "fight" or step == "breather"\n',
        '\treturn step == "fight"\n',
    ),
    "l1: the tempo runs on the road": (
        FLOW,
        '\treturn step == "fight" or step == "breather"\n',
        '\treturn step ~= "over"\n',
    ),
    "l1: the fighters are noted once, at the first clear": (
        FLOW,
        "\tstate.fought = table.clone(input.fighters)\n",
        "\tif #state.fought == 0 then\n\t\tstate.fought = table.clone(input.fighters)\n\tend\n",
    ),
    "l1: the run keeps the caller's list of fighters": (
        FLOW,
        "\tstate.fought = table.clone(input.fighters)\n",
        "\tstate.fought = input.fighters\n",
    ),
    "l1: a skip's boundary keeps the fighters of a wave before": (
        FLOW,
        "\t\t\tstate.fought = if fighters ~= nil then table.clone(fighters) else {}\n",
        "\t\t\tstate.fought = if fighters ~= nil then table.clone(fighters) else state.fought\n",
    ),
    "l1: a star without a clear": (
        FLOW,
        'return state.ended == "cleared" and table.find(state.fought, userId) ~= nil',
        "return table.find(state.fought, userId) ~= nil",
    ),
    "l1: a star for whoever is there at the end": (
        FLOW,
        'return state.ended == "cleared" and table.find(state.fought, userId) ~= nil',
        'return state.ended == "cleared"',
    ),
    "l1: an unbuilt node opens": (
        FLOW,
        "if levelId == nil or built[levelId] ~= true then",
        "if false then",
    ),
    "l1: a node opens by the member's own stars": (
        FLOW,
        "if not hasStar(leader, if required ~= nil then required.level else nil) then",
        "if not hasStar(own, if required ~= nil then required.level else nil) then",
    ),
    "l1: needsStars is never asked": (
        FLOW,
        "if needsStars ~= nil and starCount(leader) < needsStars then",
        "if false then",
    ),
    "l1: a star for a difficulty that was not played": (
        FLOW,
        "\town[difficulty] = true\n\treturn true\n",
        "\town[difficulty] = true\n\town.normal = true\n\treturn true\n",
    ),
    "l1: the arena adapter without bankEachWave": (FLOW, "\t\tbankEachWave = true,\n", "\t\tbankEachWave = false,\n"),
    "l1: the arena adapter without merging": (FLOW, "\t\tmerge = true,\n", "\t\tmerge = false,\n"),
    "l1: the arena is always played on normal": (
        FLOW,
        "difficulties = { [firstDifficulty] = only },",
        "difficulties = { normal = only },",
    ),
    "l1: burst rows stepping outward": (
        FLOW,
        "local inward = Vector3.new(zone.rect.x - at.X, 0, zone.rect.z - at.Z)",
        "local inward = Vector3.new(at.X - zone.rect.x, 0, at.Z - zone.rect.z)",
    ),
    "l1: boss.at is read from the world origin": (
        FLOW,
        "return Vector3.new(zone.rect.x + (at[1] or 0), zone.floorY, zone.rect.z + (at[2] or 0))",
        "return Vector3.new(at[1] or 0, zone.floorY, at[2] or 0)",
    ),
    "l1: a stage's cap is always the level's": (
        FLOW,
        "local cap = stage.maxAlive or level.crowd.maxAlive\n\t\tcaps[zone.id] = cap",
        "local cap = level.crowd.maxAlive\n\t\tcaps[zone.id] = cap",
    ),
    "l1: Plan carries a missing name to the client": (
        FLOW,
        'kind = KIND_CAMP,\n\t\t\tname = stage.name or "",',
        "kind = KIND_CAMP,\n\t\t\tname = stage.name,",
    ),
    "l1: Validate lets a level end on a road": (
        FLOW,
        "if last ~= nil and last.kind ~= KIND_CAMP then",
        "if false then",
    ),
    "l1: Validate lets a level have no stage": (FLOW, "\tif #stages == 0 then\n", "\tif false then\n"),
    "l1: Validate lets a stage have no name": (
        FLOW,
        'if type(stage.name :: any) ~= "string" then',
        "if false then",
    ),
    "l1: Validate lets a boss stand off the floor": (
        FLOW,
        "if camp ~= nil and not onFloor(camp, camp.x + at[1], camp.z + at[2], radius) then",
        "if false then",
    ),
    "l1: Validate reads a camp whose keys are missing": (
        FLOW,
        "elseif lacks(`{where}: camp {camp.id}`, campLacks(camp)) then",
        "elseif false then",
    ),
    "l1: Validate takes a wall of no height for a wall": (
        FLOW,
        "\t\tand barrier.height > 0\n",
        "",
    ),
    "l1: Validate lets a stage's cap of 0 through": (
        FLOW,
        "if cap ~= nil and not isCap(cap) then",
        "if false then",
    ),
    "l1: Validate lets the level's cap of 0 through": (
        FLOW,
        'if type(crowd.maxAlive) == "number" and not isCap(crowd.maxAlive) then',
        "if false then",
    ),
    "l1: Validate takes any cap over 1, whole or not": (
        FLOW,
        'return type(value) == "number" and value >= 1 and value % 1 == 0',
        'return type(value) == "number" and value >= 1',
    ),
    "l1: Validate lets a burst of 0 through": (
        FLOW,
        'if type(crowd.burst) == "number" and crowd.burst < 1 then',
        "if false then",
    ),
    "l1: Validate lets a targetWaveSeconds of 0 through": (
        FLOW,
        'if type(pace) ~= "number" or pace <= 0 then',
        'if type(pace) ~= "number" then',
    ),
    "l1: Validate lets a camp go without targetWaveSeconds": (
        FLOW,
        'if type(pace) ~= "number" or pace <= 0 then',
        'if type(pace) == "number" and pace <= 0 then',
    ),
    "l1: Validate lets a breather of -1 through": (
        FLOW,
        'if rest ~= nil and (type(rest) ~= "number" or rest < 0) then',
        "if false then",
    ),
    "l1: Validate does not ask the wire's reach on X": (
        FLOW,
        "\t\t\t\tmath.abs(camp.x) + camp.sx / 2 > WIRE_REACH\n\t\t\t\tor math.abs(camp.z) + camp.sz / 2 > WIRE_REACH\n",
        "\t\t\t\tmath.abs(camp.z) + camp.sz / 2 > WIRE_REACH\n",
    ),
    "l1: Validate does not ask the wire's reach on Z": (
        FLOW,
        "\t\t\t\tor math.abs(camp.z) + camp.sz / 2 > WIRE_REACH\n",
        "",
    ),
    "l1: Validate's height bound forgets the crowd's ceiling": (
        FLOW,
        "\t\t\t\tor camp.y + ceiling > WIRE_REACH\n",
        "\t\t\t\tor camp.y > WIRE_REACH\n",
    ),
    "l1: Validate lets a floor stand under the wire's reach": (
        FLOW,
        "\t\t\t\tor camp.y < -WIRE_REACH\n",
        "",
    ),
    "l1: Validate does not ask for Combat.json's keys": (
        FLOW,
        '\tneed(missing, rules, "levels.", NEEDED.rules, "number")\n',
        "",
    ),
    "l1: Validate does not ask for a reward's numbers": (
        FLOW,
        '\t\t\tneed(missing, reward, `crowd.rewards.{tostring(kind)}.`, NEEDED.reward, "number")\n',
        "",
    ),
    "l1: Validate does not ask for a difficulty's numbers": (
        FLOW,
        '\t\t\tneed(missing, scales, `difficulties.{tostring(name)}.`, NEEDED.difficulty, "number")\n',
        "",
    ),
    "l1: minDifficulty ignored": (
        COMBAT,
        "if needs ~= nil and (needsRank == nil or needsRank > rank) then",
        "if false then",
    ),
    "l1: countMult floors instead of rounding": (
        COMBAT,
        "math.max(math.round(group.count * (1 + perExtra * extras) * scales.countMult), 0)",
        "math.max(math.floor(group.count * (1 + perExtra * extras) * scales.countMult), 0)",
    ),
    "l1: CampWave ignores countMult": (
        COMBAT,
        "math.max(math.round(group.count * (1 + perExtra * extras) * scales.countMult), 0)",
        "math.max(math.round(group.count * (1 + perExtra * extras)), 0)",
    ),
    "l1: CampWave ignores the party's size": (
        COMBAT,
        "math.max(math.round(group.count * (1 + perExtra * extras) * scales.countMult), 0)",
        "math.max(math.round(group.count * scales.countMult), 0)",
    ),
    "l1: the boss's health ignores the party's size": (
        COMBAT,
        "boss = waveDef.boss,\n\t\tbossHpMult = 1 + combatCfg.coop.bossHpPerExtraPlayer * extras,",
        "boss = waveDef.boss,\n\t\tbossHpMult = 1,",
    ),
    "l1: CampReward ignores rewardMult": (
        COMBAT,
        "return math.round(reward.cash * spec.rewardMult), math.round(reward.materials * spec.rewardMult)",
        "return math.round(reward.cash), math.round(reward.materials)",
    ),
    "l1: CampReward floors": (
        COMBAT,
        "return math.round(reward.cash * spec.rewardMult), math.round(reward.materials * spec.rewardMult)",
        "return math.floor(reward.cash * spec.rewardMult), math.floor(reward.materials * spec.rewardMult)",
    ),
    "l1: BurstSeconds ignores tempo": (
        COMBAT,
        "\treturn targetWaveSeconds / bursts / tempo\n",
        "\treturn targetWaveSeconds / bursts\n",
    ),
    "l1: BurstSeconds ignores the number of bursts": (
        COMBAT,
        "\treturn targetWaveSeconds / bursts / tempo\n",
        "\treturn targetWaveSeconds / tempo\n",
    ),
    "l1: the wire origin following the bounds": (
        CROWD,
        "\t\t\tCrowdCodec.Encode(chunk, WIRE_ORIGIN, serverTime)\n\t\t)\n\t\ttable.clear(chunk)\n\tend\nend",
        "\t\t\tCrowdCodec.Encode(chunk, floors[1].centre, serverTime)\n\t\t)\n\t\ttable.clear(chunk)\n\tend\nend",
    ),
    "l1: a full packet's origin following the bounds": (
        CROWD,
        "\t\t\t\tCrowdCodec.Encode(chunk, WIRE_ORIGIN, serverTime)\n\t\t\t)\n\t\t\ttable.clear(chunk)\n\t\t\tcount = 0\n",
        "\t\t\t\tCrowdCodec.Encode(chunk, floors[1].centre, serverTime)\n\t\t\t)\n\t\t\ttable.clear(chunk)\n\t\t\tcount = 0\n",
    ),
    "l1: SetBounds accepted with a body alive": (
        CROWD,
        "\tif aliveCount > 0 then\n\t\tif not warnedBoundsAlive then",
        "\tif false then\n\t\tif not warnedBoundsAlive then",
    ),
}
MUTATIONS.update(L1_MUTATIONS)

# L1, from engineer A (the world): LevelGeometry, tests_l1_world.luau. Copied verbatim from A's
# final handover file of the fix round; the comment over each entry names a check that fails.
WORLD_MUTATIONS = {
    # ------------------------------------------------------------------ the invisible wall
    # caught by: the wall is closed all the way round, corners included
    "world: the invisible wall's corners are open": (
        GEOMETRY,
        "sx = (edgeX + depth) * 2,",
        "sx = edgeX * 2,",
    ),
    # caught by: each inner face is on the floor's edge
    "world: the wall's inner face is off the floor's edge (north and south)": (
        GEOMETRY,
        "z = camp.z + side.sign * (edgeZ + depth / 2),",
        "z = camp.z + side.sign * (edgeZ + depth),",
    ),
    # caught by: each inner face is on the floor's edge
    "world: the wall's inner face is off the floor's edge (west and east)": (
        GEOMETRY,
        "x = camp.x + side.sign * (edgeX + depth / 2),",
        "x = camp.x + side.sign * (edgeX + depth),",
    ),
    # caught by: the fence and the gates stand inside the wall: no point on top of them is free
    "world: the wall's inner face is on the fence's outer face (west and east)": (
        GEOMETRY,
        "local edgeX = camp.sx / 2",
        "local edgeX = camp.sx / 2 + thickness",
    ),
    # caught by: the fence and the gates stand inside the wall: no point on top of them is free
    "world: the wall's inner face is on the fence's outer face (north and south)": (
        GEOMETRY,
        "local edgeZ = camp.sz / 2\n\tlocal y = camp.y + height / 2",
        "local edgeZ = camp.sz / 2 + thickness\n\tlocal y = camp.y + height / 2",
    ),
    # caught by: a wall thinner than the fence is made as deep as the fence, from the floor's edge
    "world: the wall may be thinner than the fence": (
        GEOMETRY,
        "local depth = math.max(barrier.thickness, thickness, 0)",
        "local depth = barrier.thickness",
    ),
    # caught by: each stands from the floor's top (12) up to barrier.height above it (92)
    "world: the wall stands from height 0, not from the camp's floor": (
        GEOMETRY,
        "local edgeZ = camp.sz / 2\n\tlocal y = camp.y + height / 2",
        "local edgeZ = camp.sz / 2\n\tlocal y = height / 2",
    ),
    # ------------------------------------------------------------------ the fence and its gates
    # caught by: fence and gates cover every side once, end to end: the gate fills the cut
    "world: a gate is not cut from the fence": (
        GEOMETRY,
        "if gate.side == name then",
        "if false then",
    ),
    # caught by: a gate past the end of its side is held to the floor's edge
    "world: a gate runs past the end of its side": (
        GEOMETRY,
        "local to = math.min(gate.at + gate.width / 2, half)",
        "local to = gate.at + gate.width / 2",
    ),
    # caught by: a gate past the end of its side is held to the floor's edge
    "world: a gate starts before the start of its side": (
        GEOMETRY,
        "local from = math.max(gate.at - gate.width / 2, -half)",
        "local from = gate.at - gate.width / 2",
    ),
    # caught by: a gate inside a wider one: the fence stays cut for the whole of the wider gate
    "world: a gate inside a wider one puts the fence back": (
        GEOMETRY,
        "standing = math.max(standing, cut[2])",
        "standing = cut[2]",
    ),
    # caught by: with no gate the fence is the C1 arena's four boxes
    "world: the fence's corners are open": (
        GEOMETRY,
        "local reach = if side.alongX then half + thickness else half",
        "local reach = half",
    ),
    # caught by: no fence, gate or wall box reaches inside it, in three camps
    "world: the north and south fence stand inside the floor's edge": (
        GEOMETRY,
        "z = camp.z + side.sign * (camp.sz / 2 + thickness / 2),",
        "z = camp.z + side.sign * (camp.sz / 2 - thickness / 2),",
    ),
    # caught by: no fence, gate or wall box reaches inside it, in three camps
    "world: the west and east fence stand inside the floor's edge": (
        GEOMETRY,
        "x = camp.x + side.sign * (camp.sx / 2 + thickness / 2),",
        "x = camp.x + side.sign * (camp.sx / 2 - thickness / 2),",
    ),
    # caught by: north: x 69 to 103, then 117 to 131
    "world: the fence stands from height 0, not from the camp's floor": (
        GEOMETRY,
        "local length = to - from\n\tlocal y = camp.y + height / 2",
        "local length = to - from\n\tlocal y = height / 2",
    ),
    # ------------------------------------------------------------------ the floor and the other boxes
    # caught by: the floor is as deep as it is told (4), downward: its top is camp.y
    "world: the floor's top is not at camp.y": (
        GEOMETRY,
        "y = camp.y - depth / 2,",
        "y = camp.y,",
    ),
    # caught by: its floor is levels.floorThickness deep like any camp's (4), its top still at 0
    "world: a camp's floor is built one stud deep whatever the config says": (
        GEOMETRY,
        "box = LevelGeometry.FloorBox(camp, depth),",
        "box = LevelGeometry.FloorBox(camp, 1),",
    ),
    # caught by: a secret's block is where the layout puts it; its sign rises from the sign's point
    "world: a sign hangs centred on its point": (
        GEOMETRY,
        "y = sign.y + size.sy / 2,",
        "y = sign.y,",
    ),
    # caught by: a camp alone: its floor, the floor's depth under the top, and the fence's height above it
    "world: Bounds forgets the fence's height": (
        GEOMETRY,
        "\t\tif height > 0 then\n",
        "\t\tif false then\n",
    ),
    # caught by: a camp alone: its floor, the floor's depth under the top, and the fence's height above it
    "world: Bounds forgets a floor's depth": (
        GEOMETRY,
        "bounds = widen(bounds, LevelGeometry.FloorBox(camp, depth or 0))",
        "bounds = widen(bounds, LevelGeometry.FloorBox(camp, 0))",
    ),
    # caught by: Bounds with levels.floorThickness holds the deepened block (down to -4)
    "world: Bounds forgets how deep the ground is built": (
        GEOMETRY,
        "for _, box in LevelGeometry.BlockBoxes(layout, depth) do\n\t\tbounds = widen(bounds, box)",
        "for _, box in LevelGeometry.BlockBoxes(layout, nil) do\n\t\tbounds = widen(bounds, box)",
    ),
    # ------------------------------------------------------------------ the ground's depth
    # caught by: a thin block over the void is made levels.floorThickness deep, downward
    "world: thin ground over the void is left a slab": (
        GEOMETRY,
        "if not heldUp(box, under) then",
        "if false then",
    ),
    # caught by: a thin block that rests wholly on another stays as written
    "world: ground that rests on something is deepened too": (
        GEOMETRY,
        "if not heldUp(box, under) then",
        "if true then",
    ),
    # caught by: nor is a solid block of a look nobody lands on (a wall): as written
    "world: a wall is ground": (
        GEOMETRY,
        "local ground = GROUND_LOOKS[block.look] == true and block.collide ~= false",
        "local ground = block.collide ~= false",
    ),
    # caught by: a block nothing collides with is not ground: as written
    "world: a walked-through block is ground": (
        GEOMETRY,
        "local ground = GROUND_LOOKS[block.look] == true and block.collide ~= false",
        "local ground = GROUND_LOOKS[block.look] == true",
    ),
    # caught by: water and a lobby's floor are ground: deepened like a road
    "world: water is not ground": (
        GEOMETRY,
        "\twater = true,\n",
        "\twater = false,\n",
    ),
    # caught by: water and a lobby's floor are ground: deepened like a road
    "world: a lobby's floor is not ground": (
        GEOMETRY,
        "\tlobby = true,\n",
        "\tlobby = false,\n",
    ),
    # caught by: a block with a size of 0 or less is left exactly as written
    "world: a block with no height is deepened into one": (
        GEOMETRY,
        "if ground and isSound(box) and box.sy < depth then",
        "if ground and box.sy < depth then",
    ),
    # caught by: a thin block over the void is made levels.floorThickness deep, downward
    "world: deepening a block moves its top": (
        GEOMETRY,
        "y = box.y + box.sy / 2 - depth / 2,",
        "y = box.y,",
    ),
    # caught by: one whose middle rests on another and whose end hangs over the void is deepened
    "world: a block that rests at one end along X counts as held": (
        GEOMETRY,
        "if x > xs[1] and x < xs[2] then",
        "if false then",
    ),
    # caught by: the same along Z
    "world: a block that rests at one end along Z counts as held": (
        GEOMETRY,
        "if z > zs[1] and z < zs[2] then",
        "if false then",
    ),
    # caught by: two blocks side by side hold up a deck that crosses the seam between them
    "world: the seam between two supports is a hole": (
        GEOMETRY,
        "if xs[i + 1] - xs[i] > SEAM and zs[j + 1] - zs[j] > SEAM then",
        "if true then",
    ),
    # caught by: a block at its neighbour's own depth is held by nothing: the void is under both
    "world: a block at its neighbour's own depth holds it up": (
        GEOMETRY,
        "if reaches and other.y - other.sy / 2 < bottom - SEAM then",
        "if reaches and other.y - other.sy / 2 <= bottom then",
    ),
    # caught by: a plank with air under it is deepened too, whatever lies further down
    "world: ground far below holds a block up": (
        GEOMETRY,
        "local reaches = other.y + other.sy / 2 >= bottom - SEAM",
        "local reaches = true",
    ),
    # caught by: a thin block lying on a camp's floor is held by it
    "world: a camp's floor holds nothing up": (
        GEOMETRY,
        "table.insert(solids, LevelGeometry.FloorBox(camp, depth))",
        "table.insert(solids, LevelGeometry.FloorBox(camp, 0))",
    ),
    # caught by: a thin block lying on a secret's block is held by it
    "world: a secret holds nothing up": (
        GEOMETRY,
        "for _, secret in listOf(layout.secrets) do\n\t\ttable.insert(solids,",
        "for _, secret in {} :: { Types.LevelSecret } do\n\t\ttable.insert(solids,",
    ),
    # caught by: and a block nothing collides with holds nothing up
    "world: a walked-through block holds ground up": (
        GEOMETRY,
        "if block.collide ~= false and isSound(written[index]) then",
        "if isSound(written[index]) then",
    ),
    # caught by: a lobby file that leaves camps, secrets and route out is its blocks
    "world: Pieces builds the ground as the layout writes it": (
        GEOMETRY,
        "local built = LevelGeometry.BlockBoxes(measured, depth)",
        "local built = LevelGeometry.BlockBoxes(measured, nil)",
    ),
    # caught by: a camp and no floor depth (none, 0, under 0, not a number, not finite): refused
    "world: a camp is built with no floor depth": (
        GEOMETRY,
        "\t\tif depth == nil then\n\t\t\treturn nil,",
        "\t\tif false then\n\t\t\treturn nil,",
    ),
    # caught by: a camp and no floor depth (none, 0, under 0, not a number, not finite): refused
    "world: a floor depth of 0 is a depth": (
        GEOMETRY,
        "if value ~= nil and value > 0 and isFinite(value) then",
        "if value ~= nil and value >= 0 and isFinite(value) then",
    ),
    # caught by: a camp and no floor depth (none, 0, under 0, not a number, not finite): refused
    "world: a floor depth that is not finite is a depth": (
        GEOMETRY,
        "if value ~= nil and value > 0 and isFinite(value) then",
        "if value ~= nil and value > 0 then",
    ),
    # ------------------------------------------------------------------ the arena as a level
    # caught by: the party enters at the first player spawn and leaves at the pad
    "world: the arena's entry is its pad": (
        GEOMETRY,
        "local first = listOf(arena.playerSpawns)[1] or pad",
        "local first = pad",
    ),
    # caught by: every table is new: changing the level leaves the arena's module untouched
    "world: the level shares the arena's obstacle tables": (
        GEOMETRY,
        "table.insert(obstacles, table.clone(obstacle))",
        "table.insert(obstacles, obstacle)",
    ),
    # ------------------------------------------------------------------ what Pieces refuses
    # caught by: a camp with gates and no fence is refused, by name
    "world: gates with no fence are built": (
        GEOMETRY,
        "if fence == nil and #listOf(camp.gates) > 0 then",
        "if false then",
    ),
    # caught by: at most maxParts Parts: 19 of 19 builds, 19 of 18 does not
    "world: maxParts is not checked": (
        GEOMETRY,
        "if #pieces > maxParts then",
        "if false then",
    ),
    # caught by: a block with no height, or a position that is not a number, is refused by name
    "world: a size of 0 is built": (
        GEOMETRY,
        "if not isSound(piece.box) then",
        "if false then",
    ),
    # caught by: a block with a size of 0 or less on any axis is refused by name
    "world: a block with no width is built": (
        GEOMETRY,
        "\t\tand box.sx > 0\n",
        "\t\tand box.sx >= 0\n",
    ),
    # caught by: a block with a size of 0 or less on any axis is refused by name
    "world: a block with no height is built": (
        GEOMETRY,
        "\t\tand box.sy > 0\n",
        "\t\tand box.sy >= 0\n",
    ),
    # caught by: a block with a size of 0 or less on any axis is refused by name
    "world: a block with no depth is built": (
        GEOMETRY,
        "\t\tand box.sz > 0\n",
        "\t\tand box.sz >= 0\n",
    ),
    # caught by: a piece of cover with a size of 0 or less on any axis is refused by name
    "world: a negative height is built": (
        GEOMETRY,
        "\t\tand box.sy > 0\n",
        "\t\tand box.sy ~= 0\n",
    ),
    # caught by: and a size that is not finite
    "world: a size that is not finite is built": (
        GEOMETRY,
        "\t\tand isFinite(box.sx)\n",
        "\t\tand box.sx == box.sx\n",
    ),
    # caught by: collide = false and text are carried
    "world: a block's collide = false is ignored": (
        GEOMETRY,
        "collide = block.collide ~= false,",
        "collide = true,",
    ),
    # ------------------------------------------------------------------ one axis read for the other
    # caught by: north, on z -83.5 (47 from the centre, not 50)
    "world: every side is as long as the camp is deep": (
        GEOMETRY,
        "return (if side.alongX then camp.sx else camp.sz) / 2",
        "return camp.sz / 2",
    ),
    # caught by: north, on z -83.5 (47 from the centre, not 50)
    "world: the north and south fence stand the camp's width away": (
        GEOMETRY,
        "z = camp.z + side.sign * (camp.sz / 2 + thickness / 2),",
        "z = camp.z + side.sign * (camp.sx / 2 + thickness / 2),",
    ),
    # caught by: west, on x 37.5 (50 from the centre, not 47)
    "world: the west and east fence stand the camp's depth away": (
        GEOMETRY,
        "x = camp.x + side.sign * (camp.sx / 2 + thickness / 2),",
        "x = camp.x + side.sign * (camp.sz / 2 + thickness / 2),",
    ),
    # caught by: north, on z -83.5 (47 from the centre, not 50)
    "world: a north or south stretch is placed from the camp's z": (
        GEOMETRY,
        "x = camp.x + middle,",
        "x = camp.z + middle,",
    ),
    # caught by: west, on x 37.5 (50 from the centre, not 47)
    "world: a west or east stretch is placed from the camp's x": (
        GEOMETRY,
        "z = camp.z + middle,",
        "z = camp.x + middle,",
    ),
    # caught by: fence and gates cover all four sides once, end to end
    "world: the corner posts stand on the west and east sides": (
        GEOMETRY,
        "local reach = if side.alongX then half + thickness else half",
        "local reach = if side.alongX then half else half + thickness",
    ),
    # caught by: the north gate: on z -83.5, x 62 to 74
    "world: north stands on the south side": (
        GEOMETRY,
        "north = { alongX = true, sign = -1 },",
        "north = { alongX = true, sign = 1 },",
    ),
    # caught by: the west gate: on x 37.5, z -54 to -38
    "world: west stands on the east side": (
        GEOMETRY,
        "west = { alongX = false, sign = -1 },",
        "west = { alongX = false, sign = 1 },",
    ),
    # caught by: the south gate: on z 11.5, x 113 to 123
    "world: south runs along Z, a second east side": (
        GEOMETRY,
        "south = { alongX = true, sign = 1 },",
        "south = { alongX = false, sign = 1 },",
    ),
    # caught by: the floor: 100 along X and 94 along Z round (88, -36)
    "world: the floor is as wide as the camp is deep": (
        GEOMETRY,
        "sx = camp.sx,\n\t\tsy = depth,\n\t\tsz = camp.sz,",
        "sx = camp.sz,\n\t\tsy = depth,\n\t\tsz = camp.sx,",
    ),
    # caught by: the wall, west and east: 94 long, from x 38 and from x 138 outward
    "world: the wall's west and east sides stand the camp's depth away": (
        GEOMETRY,
        "local edgeX = camp.sx / 2",
        "local edgeX = camp.sz / 2",
    ),
    # caught by: the wall, north and south: 116 long, from z -83 and from z 11 outward
    "world: the wall's north and south sides stand the camp's width away": (
        GEOMETRY,
        "local edgeZ = camp.sz / 2\n\tlocal y = camp.y + height / 2",
        "local edgeZ = camp.sx / 2\n\tlocal y = camp.y + height / 2",
    ),
    # caught by: the wall, north and south: 116 long, from z -83 and from z 11 outward
    "world: the wall's north and south boxes are as long as the camp is deep": (
        GEOMETRY,
        "sx = (edgeX + depth) * 2,",
        "sx = (edgeZ + depth) * 2,",
    ),
    # caught by: the wall, west and east: 94 long, from x 38 and from x 138 outward
    "world: the wall's west and east boxes are as long as the camp is wide": (
        GEOMETRY,
        "sz = edgeZ * 2,",
        "sz = edgeX * 2,",
    ),
    # caught by: Bounds: x 38 to 138, z -83 to 11,
    "world: Bounds reads a camp's width for its depth": (
        GEOMETRY,
        "sx = camp.sx,\n\t\t\t\tsy = height,\n\t\t\t\tsz = camp.sz,",
        "sx = camp.sz,\n\t\t\t\tsy = height,\n\t\t\t\tsz = camp.sx,",
    ),
    # caught by: and with two blocks: each widens it by its own width along X and its own depth along Z
    "world: Bounds reads a box's depth for its width": (
        GEOMETRY,
        "local minX = box.x - box.sx / 2",
        "local minX = box.x - box.sz / 2",
    ),
    # caught by: a block is its own box in its own look, solid unless it says otherwise
    "world: a block is as wide as it is deep": (
        GEOMETRY,
        "sx = block.sx,\n\t\t\tsy = block.sy,\n\t\t\tsz = block.sz,",
        "sx = block.sz,\n\t\t\tsy = block.sy,\n\t\t\tsz = block.sx,",
    ),
    # caught by: a block is its own box in its own look, solid unless it says otherwise
    "world: a block stands at its z along X": (
        GEOMETRY,
        "x = block.x,\n\t\t\ty = block.y,\n\t\t\tz = block.z,",
        "x = block.z,\n\t\t\ty = block.y,\n\t\t\tz = block.x,",
    ),
    # caught by: a thin block over the void is made levels.floorThickness deep, downward
    "world: a deepened block is as wide as it is deep": (
        GEOMETRY,
        "sx = box.sx,\n\t\t\t\t\tsy = depth,\n\t\t\t\t\tsz = box.sz,",
        "sx = box.sz,\n\t\t\t\t\tsy = depth,\n\t\t\t\t\tsz = box.sx,",
    ),
    # caught by: alone with its support along X: the shelf is deepened, the step is not
    "world: a support's edges along X are read from its depth": (
        GEOMETRY,
        "local x = other.x + way * other.sx / 2",
        "local x = other.x + way * other.sz / 2",
    ),
    # caught by: alone with its support along Z: the lip is deepened
    "world: a support's edges along Z are read from its width": (
        GEOMETRY,
        "local z = other.z + way * other.sz / 2",
        "local z = other.z + way * other.sx / 2",
    ),
    # caught by: a thin block that rests wholly on another stays as written
    "world: a support holds as far along X as it is deep": (
        GEOMETRY,
        "if dx < other.sx / 2 and dz < other.sz / 2 then",
        "if dx < other.sz / 2 and dz < other.sx / 2 then",
    ),
    # caught by: cover: its own x and z, its own width and depth
    "world: cover is as wide as it is deep": (
        GEOMETRY,
        "sx = obstacle.sx,\n\t\t\tsy = obstacle.sy,\n\t\t\tsz = obstacle.sz,",
        "sx = obstacle.sz,\n\t\t\tsy = obstacle.sy,\n\t\t\tsz = obstacle.sx,",
    ),
    # caught by: cover: its own x and z, its own width and depth
    "world: cover stands at its z along X": (
        GEOMETRY,
        "x = obstacle.x,\n\t\t\ty = camp.y + obstacle.sy / 2,\n\t\t\tz = obstacle.z,",
        "x = obstacle.z,\n\t\t\ty = camp.y + obstacle.sy / 2,\n\t\t\tz = obstacle.x,",
    ),
    # caught by: the checkpoint marker: the point's x and z, the size's width and depth
    "world: the checkpoint marker is as wide as it is deep": (
        GEOMETRY,
        "z = point.z,\n\t\tsx = size.sx,\n\t\tsy = size.sy,\n\t\tsz = size.sz,",
        "z = point.z,\n\t\tsx = size.sz,\n\t\tsy = size.sy,\n\t\tsz = size.sx,",
    ),
    # caught by: the checkpoint marker: the point's x and z, the size's width and depth
    "world: the checkpoint marker stands at its z along X": (
        GEOMETRY,
        "x = point.x,\n\t\ty = camp.y + size.sy / 2,\n\t\tz = point.z,",
        "x = point.z,\n\t\ty = camp.y + size.sy / 2,\n\t\tz = point.x,",
    ),
    # caught by: a secret and its sign: each its own x and z, width and depth
    "world: a secret is as wide as it is deep": (
        GEOMETRY,
        "sx = secret.sx,\n\t\tsy = secret.sy,\n\t\tsz = secret.sz,",
        "sx = secret.sz,\n\t\tsy = secret.sy,\n\t\tsz = secret.sx,",
    ),
    # caught by: a secret and its sign: each its own x and z, width and depth
    "world: a sign is as wide as it is deep": (
        GEOMETRY,
        "z = sign.z,\n\t\tsx = size.sx,\n\t\tsy = size.sy,\n\t\tsz = size.sz,",
        "z = sign.z,\n\t\tsx = size.sz,\n\t\tsy = size.sy,\n\t\tsz = size.sx,",
    ),
    # caught by: FromArena: the arena's size.x is the camp's width and its size.z the depth
    "world: the arena's camp is as wide as the arena is deep": (
        GEOMETRY,
        "sx = arena.size.x,\n\t\tsz = arena.size.z,",
        "sx = arena.size.z,\n\t\tsz = arena.size.x,",
    ),
}
MUTATIONS.update(WORLD_MUTATIONS)

# L1, "the real files" (tests_l1.luau): rules that only the data that ships showed broken when
# these were added. The fixture level started at the world origin and no fixture case read a
# camp's depth apart from its width; Forest Road starts at x -260 and its Main Camp is 100 x 94.
# Each now has a fixture case of its own as well (tests_l1.luau "what only a camp that is not
# square, or a start off the axes, shows"; the fence's in tests_l1_world.luau), so a layout that
# changes shape leaves none of them uncaught.
REAL_MUTATIONS = {
    "real: the plan's start with x and z swapped": (
        FLOW,
        "start = Vector3.new(layout.start.x, layout.start.y, layout.start.z),",
        "start = Vector3.new(layout.start.z, layout.start.y, layout.start.x),",
    ),
    "real: a level file's id dropped for its layout's": (
        FLOW,
        "\t\t\tversion = file.version,\n\t\t\tid = file.id,\n",
        "\t\t\tversion = file.version,\n\t\t\tid = file.layout,\n",
    ),
    "real: the arena's level takes its mission's id": (
        FLOW,
        "\t\tid = file.id,\n\t\tname = file.name,\n\t\tlayout = file.layout,\n\t\tmission = file.mission,",
        "\t\tid = mission.id,\n\t\tname = file.name,\n\t\tlayout = file.layout,\n\t\tmission = file.mission,",
    ),
    "real: the plan's floor as deep as it is wide": (
        FLOW,
        "local rect: Rect = { x = camp.x, z = camp.z, hx = camp.sx / 2, hz = camp.sz / 2 }",
        "local rect: Rect = { x = camp.x, z = camp.z, hx = camp.sx / 2, hz = camp.sx / 2 }",
    ),
    "real: a grown rectangle as deep as it is wide": (
        FLOW,
        "\t\thz = math.max(rect.hz + by, 0),\n",
        "\t\thz = math.max(rect.hx + by, 0),\n",
    ),
    "real: a rectangle judged by its width on both axes": (
        FLOW,
        "return math.abs(x - rect.x) <= rect.hx and math.abs(z - rect.z) <= rect.hz",
        "return math.abs(x - rect.x) <= rect.hx and math.abs(z - rect.z) <= rect.hx",
    ),
    "real: a closed camp's rescue reaches as far in Z as the camp is wide": (
        FLOW,
        "\t\t\t\tor math.abs(position.Z - rect.z) > rect.hz + rescue.outside",
        "\t\t\t\tor math.abs(position.Z - rect.z) > rect.hx + rescue.outside",
    ),
    "real: a closed camp's rescue reaches as far in X as the camp is deep": (
        FLOW,
        "\t\t\t\tor math.abs(position.X - rect.x) > rect.hx + rescue.outside",
        "\t\t\t\tor math.abs(position.X - rect.x) > rect.hz + rescue.outside",
    ),
    "real: a fence side as long as the camp is wide": (
        GEOMETRY,
        "return (if side.alongX then camp.sx else camp.sz) / 2",
        "return camp.sx / 2",
    ),
}
MUTATIONS.update(REAL_MUTATIONS)


# ------------------------------------------------------------------------------------------------
# L1b Wave 1 (docs/INTERFACES.md "L1b contracts — the living road").
# From luau-engineer A (the crowd), verbatim from docs/prompts/l1b-w1-reports/A-crowd.md: its new
# entries, and the existing entries its edits changed, under their own labels (a dict update keeps
# each one's place in the run).
# L1b Wave 1, luau-engineer A: new mutations (labels prefixed "l1b crowd:").
L1B_CROWD_MUTATIONS = {
    "l1b crowd: sight ignores the height band": (
        CAMP,
        "\tif not inBand(def, root, rules) then\n\t\treturn false\n\tend\n\tlocal posture = postureRules(def, rules)",
        "\tlocal posture = postureRules(def, rules)",
    ),
    "l1b crowd: the cone is ignored": (
        CAMP,
        "if posture.cone >= 360 or distance < CONE_NEAR then",
        "if true then",
    ),
    "l1b crowd: the cone uses the full angle": (
        CAMP,
        "return angle <= posture.cone / 2 + CONE_EPSILON_DEGREES",
        "return angle <= posture.cone + CONE_EPSILON_DEGREES",
    ),
    "l1b crowd: in play ignores chaseMargin": (
        CAMP,
        "local margin = rules.chaseMargin",
        "local margin = 0",
    ),
    "l1b crowd: in play ignores the shooters' reach": (
        CAMP,
        "if flatDistance(shooter.at, root) <= shooter.reach then",
        "if false then",
    ),
    "l1b crowd: rise skips its seconds": (
        CAMP,
        "if now - group.since >= postureRules(group.def, rules).rise - TIME_EPSILON then",
        "if true then",
    ),
    "l1b crowd: two transitions in one call": (
        CAMP,
        '\t\t\tchanged = "rise"\n\t\tend\n\telseif state == "rise" then',
        '\t\t\tchanged = "rise"\n\t\tend\n\tend\n\tif state == "rise" or changed == "rise" then',
    ),
    "l1b crowd: the leash fires while striking": (
        CAMP,
        "now - group.quietSince >= rules.leashSeconds - TIME_EPSILON and not input.striking",
        "now - group.quietSince >= rules.leashSeconds - TIME_EPSILON",
    ),
    "l1b crowd: the leash is not reset by a target back in play": (
        CAMP,
        "\t\tif anyInPlay then\n\t\t\tgroup.quietSince = now",
        "\t\tif anyInPlay then\n\t\t\tgroup.quietSince = group.quietSince",
    ),
    # Retired in L1b Wave 4 (their rule is reversed; L1B_W4_CROWD_RETIRED below is the record):
    #   "l1b crowd: home takes damage"           -> "l1b w4 crowd: Struck blocks a homeward group"
    #   "l1b crowd: home wakes on a hit"         -> "l1b w4 crowd: home turns back on an unreachable hit"
    #   "l1b crowd: a hit from out of play lands" -> "l1b w4 crowd: a hit from out of play is blocked again"
    "l1b crowd: a held group wakes on sight": (
        CAMP,
        "\tif group.held then\n\t\t-- Held until the close: neither sight nor a hit wakes it (ruling L1b-13).\n\t\tgroup.hit = false",
        "\tif group.held and not anySeen(group, input, rules) then\n\t\tgroup.hit = false",
    ),
    "l1b crowd: Release frees a group that was not held": (
        CAMP,
        "\tif not group.held then\n\t\treturn\n\tend\n\tgroup.held = false",
        "\tgroup.held = false",
    ),
    "l1b crowd: patrol posts not spaced by arc length": (
        CAMP,
        "local s = total * (k - 1) / count",
        "local s = total * ((k - 1) % n) / n",
    ),
    "l1b crowd: a fire's sitters face away from it": (
        CAMP,
        "local yaw = theta + math.pi",
        "local yaw = theta",
    ),
    "l1b crowd: a patrol's leg does not wrap": (
        CAMP,
        "resident.leg = resident.leg % n + 1",
        "resident.leg = resident.leg + 1",
    ),
    "l1b crowd: home does not restore the post's leg": (
        CAMP,
        "\t\t\tresident.leg = post.leg",
        "\t\t\tresident.leg = resident.leg",
    ),
    "l1b crowd: a sitter shows idle": (
        CAMP,
        'return if group.def.posture == "fire" then "rest" else "idle"',
        'return "idle"',
    ),
    "l1b crowd: the heal leaves the plate broken": (
        CROWD,
        "\tenemy.hp = enemy.maxHp\n\tenemy.plate = enemy.plateMax\n",
        "\tenemy.hp = enemy.maxHp\n",
    ),
    "l1b crowd: the heal keeps the damage book": (
        CROWD,
        "\ttable.clear(enemy.damageBy)\n\tenemy.staggerUntil = 0",
        "\tenemy.staggerUntil = 0",
    ),
    "l1b crowd: a summon on floor 1": (
        CROWD,
        'local risen = enemies[CrowdService.Spawn(kind, spot, "fight", nil, nil, summoner.floor)]',
        'local risen = enemies[CrowdService.Spawn(kind, spot, "fight", nil, nil, 1)]',
    ),
    "l1b crowd: a strike's floorY from floor 1": (
        BRAIN,
        "floorY = floor.centre.Y,",
        "floorY = (floors[1] or DEFAULT_FLOOR).centre.Y,",
    ),
    "l1b crowd: the clamp on floor 1": (
        CROWD,
        "local floor = floorOf(enemy)\n\tlocal boundsCenter = floor.centre",
        "local floor = floors[1]\n\tlocal boundsCenter = floor.centre",
    ),
    "l1b crowd: AliveOn counts every floor": (
        CROWD,
        "return aliveOn[floor] or 0",
        "return aliveCount",
    ),
    "l1b crowd: ClearFloor clears every floor": (
        CROWD,
        "if enemy ~= nil and enemy.floor == floor then",
        "if enemy ~= nil then",
    ),
    "l1b crowd: Think ignores allowed": (
        BRAIN,
        "if allowed ~= nil and not allowed[target.userId] then",
        "if false then",
    ),
    "l1b crowd: SetFloors accepted with a body alive": (
        CROWD,
        "\tif aliveCount > 0 then\n\t\tif not warnedBoundsAlive then",
        "\tif false then\n\t\tif not warnedBoundsAlive then",
    ),
    "l1b crowd: the codec's new states swapped": (
        CODEC,
        '"attack", "recover", "rest", "rise" }',
        '"attack", "recover", "rise", "rest" }',
    ),
    "l1b crowd: an unknown floor index is not refused": (
        CROWD,
        "local stand = if isFinite(floorIndex) then floors[floorIndex] else nil",
        "local stand = if isFinite(floorIndex) then floors[floorIndex] or floors[1] else nil",
    ),
    "l1b crowd: AddGroup takes an unknown floor": (
        CROWD,
        'if typeof(def) ~= "table" or floors[def.floor] == nil then',
        'if typeof(def) ~= "table" then',
    ),
    "l1b crowd: a resting resident thinks": (
        CROWD,
        'local resting = brain ~= nil and (brain.held or brain.state ~= "fight")',
        "local resting = false",
    ),
    "l1b crowd: a released group fights in the step that releases it": (
        CROWD,
        "\t\t\tCampBrain.Step(brain, input, rules)\n\t\t\tCampBrain.Release(brain, simTime)",
        "\t\t\tCampBrain.Release(brain, simTime)\n\t\t\tCampBrain.Step(brain, input, rules)",
    ),
    "l1b crowd: a group with no living member is busy": (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and (state == "rise" or state == "fight") then',
        'if not group.brain.held and (state == "rise" or state == "fight") then',
    ),
    "l1b crowd: a group with no living member is awake": (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and state ~= "rest" then',
        'if not group.brain.held and state ~= "rest" then',
    ),
    "l1b crowd: Damage never asks the group": (
        CROWD,
        "if group ~= nil and not CampBrain.Struck(group.brain, byUserId) then",
        "if false then",
    ),
}

# Existing mutations in mutate.py whose text L1b's crowd edits changed: label -> the new entry.
STALE_REPLACEMENTS = {
    "a retreat ignores the arena's edge": (
        BRAIN,
        "return inArena(\n\t\t\tbody.position - mind.facing * (bandMin - distance),\n\t\t\tdef.radius,\n\t\t\tfloorOf(body)\n\t\t),\n\t\t\t0",
        "return body.position - mind.facing * (bandMin - distance),\n\t\t\t0",
    ),
    "shot: no lead": (
        BRAIN,
        "aim = here + (ahead(here, target, flight + target.lag, floorY) - here) * lead",
        "aim = here + (ahead(here, target, flight + target.lag, floorY) - here) * 0",
    ),
    "shot: aimed along the locked facing, not at T": (
        BRAIN,
        "strike.aim = if target ~= nil\n\t\t\t\t\tthen ledAim(origin, here, target, attack, floor.centre.Y)\n\t\t\t\t\telse here",
        "strike.aim = origin + mind.facing",
    ),
    "lane: the charge ignores the arena's edge": (
        BRAIN,
        "then math.min(range, runway(body.position, mind.facing, def.radius, floor))",
        "then range",
    ),
    "1a: the wave 2 rule (in the air = above the standing height, down to the crowd's floor)": (
        BRAIN,
        "\tif not target.resting then\n\t\tlocal floor = if y >= target.restY then target.restY else floorY + target.lift",
        "\tif y - (floorY + target.lift) > 0.75 then\n\t\tlocal floor = floorY + target.lift",
    ),
    "1a: a jump off a block is led down to the crowd's floor": (
        BRAIN,
        "local floor = if y >= target.restY then target.restY else floorY + target.lift",
        "local floor = floorY + target.lift",
    ),
    "1a: a fall off a block stops at the block's height": (
        BRAIN,
        "local floor = if y >= target.restY then target.restY else floorY + target.lift",
        "local floor = target.restY",
    ),
    "lag: a shot is led over its flight alone": (
        BRAIN,
        "ahead(here, target, flight + target.lag, floorY)",
        "ahead(here, target, flight, floorY)",
    ),
    "summon: they stand idle": (
        CROWD,
        'local risen = enemies[CrowdService.Spawn(kind, spot, "fight", nil, nil, summoner.floor)]',
        'local risen = enemies[CrowdService.Spawn(kind, spot, "idle", nil, nil, summoner.floor)]',
    ),
    "boss: its queued impact is still handed over": (
        CROWD,
        "\t\tend\n\tend\n\tCrowdBrain.Recall(ids)\n",
        "\t\tend\n\tend\n",
    ),
    "guarded: a guard in its dead state still guards": (
        CROWD,
        'enemy.state = "dead"\n\tnoteGone(enemy)\n\tlocal summoner = enemy.summoner\n\tif summoner ~= nil then\n\t\tsummoner.guard = math.max(summoner.guard - 1, 0)',
        'enemy.state = "dead"\n\tnoteGone(enemy)\n\tlocal summoner = enemy.summoner\n\tif summoner ~= nil then\n\t\tsummoner.guard = math.max(summoner.guard, 0)',
    ),
}

MUTATIONS.update(L1B_CROWD_MUTATIONS)
MUTATIONS.update(STALE_REPLACEMENTS)

# L1 entries L1b's rulings retired, each with the L1b entry that now holds its rule (never deleted
# silently; the report of luau-engineer B lists them):
#   "l1: a camp clear without bank"         -> "l1b: a bank emitted" (L1b-15: nothing banks, ever)
#   "l1: bankEachWave ignored"              -> "l1b: a clear does not settle its waves"
#   "l1: a bank counts one wave whatever it covers" -> "l1b: a clear counts one wave whatever it covers"
#   "l1: the arena adapter without bankEachWave"    -> "l1b: Resolve drops the file's camps"
#   "l1: CampReward ignores rewardMult"     -> "l1b: KillReward ignores rewardMult"
#   "l1: CampReward floors"                 -> "l1b: KillReward floors"
#   "l1: SetBounds accepted with a body alive" -> A's "l1b crowd: SetFloors accepted with a body alive"
#                                              (the same text: SetBounds is SetFloors of one floor)
RETIRED = [
    "l1: a camp clear without bank",
    "l1: bankEachWave ignored",
    "l1: a bank counts one wave whatever it covers",
    "l1: the arena adapter without bankEachWave",
    "l1: CampReward ignores rewardMult",
    "l1: CampReward floors",
    "l1: SetBounds accepted with a body alive",
]
for label in RETIRED:
    del MUTATIONS[label]

CLEARED = "\tstate.settled = wave\n\tlocal lastWave = wave >= stage.waves"
# The camp's clear. L1b Wave 2 gave it a tent clause (L1b-W2-8) and Wave 4 took it away again
# (L1b-W4-29: the clear never waits for a tent), so it is one line once more.
CAMP_CLEAR = "if zone.locks or zone.residents <= 0 or state.done[index] or byFloor[index] ~= 0 then"
SPLIT = "local paid = math.floor(exact + 1e-9)\n\treturn paid, math.max(exact - paid, 0)"
KILL = "return math.round(reward.cash * rewardMult), math.round(reward.materials * rewardMult)"
# From luau-engineer B (the run): StageFlow, Combat, LevelGeometry, tests_l1b.luau.
L1B_RUN_MUTATIONS = {
    "l1b: a bank emitted": (
        FLOW,
        CLEARED,
        '\tstate.settled = wave\n\ttable.insert(actions, { kind = "bank", stage = state.stage, wave = wave, count = 1 })\n\tlocal lastWave = wave >= stage.waves',
    ),
    "l1b: a clear does not settle its waves": (FLOW, CLEARED, "\tlocal lastWave = wave >= stage.waves"),
    "l1b: a clear counts one wave whatever it covers": (
        FLOW,
        "count = wave - state.settled }",
        "count = 1 }",
    ),
    "l1b: campClear twice": (
        FLOW,
        CAMP_CLEAR,
        CAMP_CLEAR.replace(" or state.done[index]", ""),
    ),
    "l1b: campClear for a zone with no residents": (
        FLOW,
        CAMP_CLEAR,
        CAMP_CLEAR.replace(" or zone.residents <= 0", ""),
    ),
    "l1b: campClear for the locking zone": (
        FLOW,
        CAMP_CLEAR,
        CAMP_CLEAR.replace("zone.locks or ", ""),
    ),
    "l1b: a reach from a downed root": (
        FLOW,
        "\t\t\t\tand inBand\n\t\t\t\tand (standing == nil or standing[rootIndex] ~= false)\n",
        "\t\t\t\tand inBand\n",
    ),
    "l1b: reach ignores the band": (
        FLOW,
        "local inBand = rise >= -rules.triggerBelow and rise <= rules.triggerHeight",
        "local inBand = true",
    ),
    "l1b: a checkpoint reached from past checkpointReach": (
        FLOW,
        "\t\t\t\tflat <= rules.checkpointReach\n",
        "\t\t\t\tflat <= rules.checkpointReach + 1\n",
    ),
    "l1b: SafePoint returns a busy floor's checkpoint": (
        FLOW,
        "local quiet = busy == nil or busy[index] ~= true",
        "local quiet = true",
    ),
    "l1b: SafePoint ignores reached": (
        FLOW,
        "if mark ~= nil and state.reached[index] and quiet then",
        "if mark ~= nil and quiet then",
    ),
    "l1b: SafePoint takes the nearest checkpoint first": (
        FLOW,
        "for index = #plan.zones, 1, -1 do",
        "for index = 1, #plan.zones do",
    ),
    "l1b: FieldClear on the road ignores awake": (
        FLOW,
        "return input.spawningDone and input.awake == 0",
        "return input.spawningDone",
    ),
    "l1b: FieldClear in the camp counts every floor": (
        FLOW,
        "return input.spawningDone and input.alive == 0",
        "local all = input.alive\n\t\tfor _, bodies in input.aliveByFloor do\n\t\t\tall += bodies\n\t\tend\n\t\treturn input.spawningDone and all == 0",
    ),
    "l1b: RescueGrace gives the i-frames while engaged": (
        FLOW,
        "return if engaged then 0 else iframes",
        "return iframes",
    ),
    "l1b: the boss room's clear leaves it not done": (
        FLOW,
        "\tif zone ~= nil then\n\t\tstate.done[zone.floor] = true\n\tend\n\tstate.cleared += 1",
        "\tstate.cleared += 1",
    ),
    "l1b: countMult applied to residents": (
        FLOW,
        "local groups, residents, residentStocks = groupsOf(level, layout, rank, ranks)",
        "local groups, residents, residentStocks = groupsOf(level, layout, rank, ranks)\n\tfor _, def in groups do\n\t\tfor _, unit in def.units do\n\t\t\tunit.count = math.round(unit.count * level.difficulties[difficulty].countMult)\n\t\tend\n\tend",
    ),
    "l1b: minDifficulty ignored for residents": (
        FLOW,
        "if needs ~= nil and (needsRank == nil or needsRank > rank) then",
        "if false then",
    ),
    "l1b: the population gate without the reserve": (
        FLOW,
        "return placed + tents + room + reserve",
        "return placed + tents + room",
    ),
    "l1b: a locking camp's residents not held": (
        FLOW,
        "held = camp.locks == true,",
        "held = false,",
    ),
    "l1b: a stage naming an open camp passes Validate": (
        FLOW,
        "if camp.locks ~= true then",
        "if false then",
    ),
    "l1b: Validate counts no guard against its posts": (
        FLOW,
        'if def.posture == "guard" and members > #def.points then',
        "if false then",
    ),
    "l1b: Validate lets a post hang its widest kind over the edge": (
        FLOW,
        "for index, post in posts :: { CampBrain.Post } do\n\t\t\t\tif camp ~= nil and not onFloor(camp, post.at.X, post.at.Z, widest)",
        "for index, post in posts :: { CampBrain.Post } do\n\t\t\t\tif camp ~= nil and not onFloor(camp, post.at.X, post.at.Z, 0)",
    ),
    "l1b: Validate lets the boss room's residents fill its cap": (
        FLOW,
        "if held >= cap then",
        "if held > cap then",
    ),
    "l1b: Plan names a zone by its id alone": (
        FLOW,
        "name = names[camp.id] or camp.id,",
        "name = camp.id,",
    ),
    "l1b: Resolve drops the file's camps": (
        FLOW,
        "camps = file.camps or {},",
        "camps = {},",
    ),
    "l1b: SplitCarry drops the carry": (COMBAT, SPLIT, "local paid = math.floor(exact + 1e-9)\n\treturn paid, 0"),
    "l1b: SplitCarry pays a fraction rounded up": (
        COMBAT,
        SPLIT,
        "local paid = math.ceil(exact - 1e-9)\n\treturn paid, math.max(exact - paid, 0)",
    ),
    "l1b: SplitCarry ignores the cash multiplier": (
        COMBAT,
        "local mult = if cashMults ~= nil then cashMults[userId] or NEUTRAL_MULT else NEUTRAL_MULT",
        "local mult = NEUTRAL_MULT",
    ),
    "l1b: SplitCarry pays a bad share": (
        COMBAT,
        "if not (share >= 0 and share < math.huge) then",
        "if false then",
    ),
    "l1b: KillReward ignores rewardMult": (COMBAT, KILL, "return math.round(reward.cash), math.round(reward.materials)"),
    "l1b: KillReward floors": (
        COMBAT,
        KILL,
        "return math.floor(reward.cash * rewardMult), math.floor(reward.materials * rewardMult)",
    ),
    "l1b: an open camp builds a barrier": (
        GEOMETRY,
        "if barrier ~= nil and locks then",
        "if barrier ~= nil then",
    ),
    "l1b: an open camp builds gates": (
        GEOMETRY,
        "local gates: { Box } = if locks then LevelGeometry.GateBoxes(camp, thickness) else {}",
        "local gates: { Box } = LevelGeometry.GateBoxes(camp, thickness)",
    ),
    "l1b: FromArena not locking": (
        GEOMETRY,
        "\t\tlocks = true,\n\t\tspots = nil,",
        "\t\tlocks = nil,\n\t\tspots = nil,",
    ),
    "l1b: a fire marker on a spot that is no fire": (
        GEOMETRY,
        'if spot.posture == "fire" and spot.points ~= nil then',
        "if spot.points ~= nil then",
    ),
    "l1b: the fire marker stands at its z along X": (
        GEOMETRY,
        "x = centre.x,\n\t\ty = camp.y + size.sy / 2,\n\t\tz = centre.z,",
        "x = centre.z,\n\t\ty = camp.y + size.sy / 2,\n\t\tz = centre.x,",
    ),
    # Added by the second B (the continuation, 2026-10-14): Validate's other new refusals, the
    # reach's once-only rule, the countdown's safe point and the minDifficulty rank edge.
    "l1b: Validate without the population gate": (FLOW, "if population > crowdMax then", "if false then"),
    "l1b: a locking camp no stage names passes Validate": (
        FLOW,
        "if camp.locks == true and times ~= 1 then",
        "if camp.locks == true and times > 1 then",
    ),
    "l1b: Validate takes a checkpointReach of 0": (
        FLOW,
        'if type(value) == "number" and not (value > 0) then',
        "if false then",
    ),
    # L1b Wave 2 removed the flat population reserve key: its refusal became the clear bonus share's
    # (and the reserve itself the boss reserve: "l1b w2: BossReserve reads the smallest summon").
    "l1b w2: Validate takes a clear bonus share under 0": (FLOW, "or bonus.share < 0", ""),
    "l1b: Validate takes two camps entries for one camp": (FLOW, "elseif entries[id] then", "elseif false then"),
    "l1b: Validate takes a spot id used twice": (FLOW, "elseif seen[id] then", "elseif false then"),
    "l1b: Validate takes a fire of radius 0": (
        FLOW,
        'if posture == "fire" and not (type(spot.radius) == "number" and spot.radius > 0) then',
        "if false then",
    ),
    "l1b: a minDifficulty unit joins one difficulty late": (
        FLOW,
        "if needs ~= nil and (needsRank == nil or needsRank > rank) then",
        "if needs ~= nil and (needsRank == nil or needsRank >= rank) then",
    ),
    "l1b: a zone counts no residents": (FLOW, "residents = residents[camp.id] or 0,", "residents = 0,"),
    "l1b: a checkpoint at the world's height": (
        FLOW,
        "checkpoint = if mark ~= nil then Vector3.new(mark.x, camp.y, mark.z) else nil,",
        "checkpoint = if mark ~= nil then Vector3.new(mark.x, 0, mark.z) else nil,",
    ),
    "l1b: reach twice": (
        FLOW,
        "if mark == nil or state.reached[index] then",
        "if mark == nil then",
    ),
    "l1b: SafePoint in the countdown is a checkpoint": (
        FLOW,
        'if step == "gate" or step == "fight" or step == "breather" then\n\t\tlocal stage = plan.stages[state.stage]\n\t\tlocal zone = if stage ~= nil then stage.zone else nil\n\t\tif zone ~= nil then\n\t\t\treturn zone.entry',
        'if step == "fight" or step == "breather" then\n\t\tlocal stage = plan.stages[state.stage]\n\t\tlocal zone = if stage ~= nil then stage.zone else nil\n\t\tif zone ~= nil then\n\t\t\treturn zone.entry',
    ),
}
MUTATIONS.update(L1B_RUN_MUTATIONS)

# The L1b Wave 1 fix round, B (docs/prompts/l1b-w1-fix-round.md): the stand-up on a clear road,
# a skip that pays nothing, progress in every live step, the safe point out of every threat.
FIX_B_MUTATIONS = {
    "l1b fix: StandsUp in the boss room's fight": (
        FLOW,
        'if step ~= "travel" and step ~= "armed" and step ~= "gate" then\n\t\treturn false',
        'if step == "over" then\n\t\treturn false',
    ),
    "l1b fix: StandsUp ignores the field": (
        FLOW,
        "if standing == nil or not StageFlow.FieldClear(plan, state, input) then",
        "if standing == nil then",
    ),
    "l1b fix: StandsUp with nobody down": (
        FLOW,
        "\tfor _, up in standing do\n\t\tif up == false then",
        "\tfor _, up in standing do\n\t\tif up ~= nil then",
    ),
    "l1b fix: a stage skip's open is not marked skipped": (
        FLOW,
        "leaveCamp(plan, state, actions, true)",
        "leaveCamp(plan, state, actions, false)",
    ),
    "l1b fix: a cleared camp's open is marked skipped": (
        FLOW,
        "leaveCamp(plan, state, actions, false)",
        "leaveCamp(plan, state, actions, true)",
    ),
    "l1b fix: a boss skip's passed camps are not marked skipped": (
        FLOW,
        'table.insert(actions, { kind = "open", stage = index, skipped = true })',
        'table.insert(actions, { kind = "open", stage = index })',
    ),
    "l1b fix: progress only on the road": (
        FLOW,
        "\tprogress(plan, state, input, rules, actions)\n",
        '\tif step == "travel" or step == "armed" then\n\t\tprogress(plan, state, input, rules, actions)\n\tend\n',
    ),
    "l1b fix: SafePoint ignores the threats": (
        FLOW,
        "if mark ~= nil and threatened(mark, threats) then",
        "if mark ~= nil and false then",
    ),
    "l1b fix: a threat's reach judged in 3D": (
        FLOW,
        "if Vector3.new(mark.X - threat.at.X, 0, mark.Z - threat.at.Z).Magnitude <= threat.reach then",
        "if (mark - threat.at).Magnitude <= threat.reach then",
    ),
    "l1b fix: a threat's reach edge left out": (
        FLOW,
        "mark.Z - threat.at.Z).Magnitude <= threat.reach then",
        "mark.Z - threat.at.Z).Magnitude < threat.reach then",
    ),
    "l1b fix: LongestReach takes the last attack": (
        FLOW,
        "longest = math.max(longest, attack.reach)",
        "longest = attack.reach",
    ),
}
MUTATIONS.update(FIX_B_MUTATIONS)

# The L1b Wave 1 fix round, A (docs/prompts/l1b-w1-reports/fix-A.md): rounded in-play corners,
# the engaged hold, and the three `home` survivors of the crowd review.
FIX_A_MUTATIONS = {
    "l1b crowd: in play has square corners": (
        CAMP,
        "if math.sqrt(outX * outX + outZ * outZ) <= margin then",
        "if outX <= margin and outZ <= margin then",
    ),
    "l1b crowd: no engaged hold": (
        CAMP,
        "return lastAt ~= nil and now - lastAt <= rules.engagedHoldSeconds + TIME_EPSILON",
        "return lastAt ~= nil and now - lastAt <= TIME_EPSILON",
    ),
    "l1b crowd: the engaged hold never ends": (
        CAMP,
        "return lastAt ~= nil and now - lastAt <= rules.engagedHoldSeconds + TIME_EPSILON",
        "return lastAt ~= nil",
    ),
    "l1b crowd: Engaged reads the last step only": (
        CROWD,
        "return rules ~= nil and CampBrain.Engaged(camp.engaged[userId], simTime, rules)",
        "return rules ~= nil and camp.engaged[userId] == simTime",
    ),
    "l1b crowd: Awake leaves out a group walking home": (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and state ~= "rest" then',
        'if #group.bodies > 0 and not group.brain.held and (state == "rise" or state == "fight") then',
    ),
    "l1b crowd: Busy counts a group walking home": (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and (state == "rise" or state == "fight") then',
        'if #group.bodies > 0 and not group.brain.held and state ~= "rest" then',
    ),
    "l1b crowd: a group walking home engages": (
        CROWD,
        'if #members > 0 and (brain.state == "rise" or brain.state == "fight") then',
        'if #members > 0 and brain.state ~= "rest" then',
    ),
}
MUTATIONS.update(FIX_A_MUTATIONS)

# L1b Wave 2, luau-engineer B (docs/INTERFACES.md "Wave 2 — the long road" → "Mutations (B)"):
# tents in Plan and Validate, the population rule, the clear bonus, the dead fraction, the tent
# marker. And the ui-engineer's SpawnSeed (two mutations, routed to B by the lead).
SPAWN_SEED = "src/combat/client/Controllers/SpawnSeed.luau"
# "l1b w2: campClear with tent stock left" was retired in L1b Wave 4 (its clause is gone, L1b-W4-29);
# "l1b w4: progress waits for tent stock again" holds the reversed rule.
W2_RUN_MUTATIONS = {
    "l1b w2: the tent stock left out of the population": (
        FLOW,
        "return placed + tents + room + reserve",
        "return placed + room + reserve",
    ),
    "l1b w2: BossReserve reads the smallest summon": (
        FLOW,
        "calls = math.max(calls, attack.count or 0)",
        "calls = if calls == 0 then attack.count or 0 else math.min(calls, attack.count or 0)",
    ),
    "l1b w2: BossReserve leaves the boss out": (
        FLOW,
        "reserve = math.max(reserve, 1 + calls)",
        "reserve = math.max(reserve, calls)",
    ),
    "l1b w2: countMult applied to a tent's stock": (
        FLOW,
        "\t\t\tfor _ = 1, unit.count do\n\t\t\t\ttable.insert(kinds, unit.kind)",
        "\t\t\tfor _ = 1, math.round(unit.count * level.difficulties.hard.countMult) do\n\t\t\t\ttable.insert(kinds, unit.kind)",
    ),
    "l1b w2: minDifficulty ignored for a tent": (
        FLOW,
        "local units = fieldedUnits(tent.units or {}, rank, ranks)",
        "local units = fieldedUnits(tent.units or {}, math.huge, ranks)",
    ),
    "l1b w2: a tent allowed on a locking camp": (
        FLOW,
        "if camp ~= nil and camp.locks == true then",
        "if false then",
    ),
    "l1b w2: Validate takes a clear bonus share above 1": (FLOW, "or bonus.share > 1", ""),
    "l1b w2: Validate takes a tent stock with no layout block": (
        FLOW,
        "elseif camp ~= nil and camp.tent == nil then",
        "elseif false then",
    ),
    "l1b w2: Validate takes a tent on a camp with no residents": (
        FLOW,
        "if stock > 0 and (residents[id] or 0) == 0 then",
        "if false then",
    ),
    "l1b w2: Validate takes a tent's every of 0": (
        FLOW,
        "if not (isFinite(tent.every) and tent.every > 0) then",
        "if not isFinite(tent.every) then",
    ),
    "l1b w2: Validate takes a tent block of radius 0": (
        FLOW,
        "and block.radius > 0",
        "",
    ),
    "l1b w2: Validate lets a ring post hang its widest kind over the edge": (
        FLOW,
        "for index, post in tent.posts do\n\t\t\t\tif camp ~= nil and not onFloor(camp, post.at.X, post.at.Z, widest)",
        "for index, post in tent.posts do\n\t\t\t\tif camp ~= nil and not onFloor(camp, post.at.X, post.at.Z, 0)",
    ),
    "l1b w2: a tent's posts counted by its units, not its bodies": (
        FLOW,
        "pcall(CampBrain.Posts, def, #kinds)",
        "pcall(CampBrain.Posts, def, #units)",
    ),
    "l1b w2: a zone's stock without its tent": (
        FLOW,
        "stock[kind] = (stock[kind] or 0) + 1",
        "stock[kind] = stock[kind]",
    ),
    "l1b w2: ClearBonus floors": (
        COMBAT,
        "return math.round(share * cash), math.round(share * materials)",
        "return math.floor(share * cash), math.floor(share * materials)",
    ),
    "l1b w2: ClearBonus ignores rewardMult": (
        COMBAT,
        "local each, eachMaterials = Combat.KillReward(rewards, kind, rewardMult)",
        "local each, eachMaterials = Combat.KillReward(rewards, kind, 1)",
    ),
    "l1b w2: ClearBonus counts the boss (WaveStock)": (
        COMBAT,
        "\tif elite ~= nil then\n\t\tstock[elite] = (stock[elite] or 0) + 1\n\tend",
        "\tif elite ~= nil then\n\t\tstock[elite] = (stock[elite] or 0) + 1\n\tend\n"
        "\tif spec.boss ~= nil then\n\t\tstock[spec.boss.kind] = (stock[spec.boss.kind] or 0) + 1\n\tend",
    ),
    "l1b w2: WaveStock drops the director's elite": (
        COMBAT,
        "\t\tstock[elite] = (stock[elite] or 0) + 1\n",
        "",
    ),
    # DeadFraction is handed queuedAlive with the residents already taken out (WaveService, read
    # by review); its own rules are the guard and the clamps.
    "l1b w2: DeadFraction goes under 0": (
        COMBAT,
        "return math.min(math.max((spawned - math.max(queuedAlive, 0)) / spawned, 0), 1)",
        "return math.min((spawned - math.max(queuedAlive, 0)) / spawned, 1)",
    ),
    "l1b w2: DeadFraction divides by nothing spawned": (
        COMBAT,
        "if spawned <= 0 then\n\t\treturn 0\n\tend\n\treturn math.min(math.max(",
        "if spawned < 0 then\n\t\treturn 0\n\tend\n\treturn math.min(math.max(",
    ),
    "l1b w2: the tent marker built colliding": (
        GEOMETRY,
        'look = "tent",\n\t\t\t\tcamp = id,\n\t\t\t\tcollide = false,',
        'look = "tent",\n\t\t\t\tcamp = id,\n\t\t\t\tcollide = true,',
    ),
    "l1b w2: no tent marker": (
        GEOMETRY,
        "local tent = LevelGeometry.TentBox(camp)\n\t\tif tent ~= nil then",
        "local tent = LevelGeometry.TentBox(camp)\n\t\tif false and tent ~= nil then",
    ),
    "l1b w2 ui: seed of a dead body": (SPAWN_SEED, 'if state == "dead" then', "if false then"),
    "l1b w2 ui: seed keeps an attack": (
        SPAWN_SEED,
        '\telseif state == "rise" then\n\t\tpose = "rise"\n\tend',
        '\telseif state == "rise" then\n\t\tpose = "rise"\n\telseif typeof(state) == "string" then\n\t\tpose = state :: any\n\tend',
    ),
}
MUTATIONS.update(W2_RUN_MUTATIONS)

# The L1b Wave 2 fix round, B (docs/prompts/l1b-w2-fix-round.md B-2 to B-4): ring posts checked
# at every difficulty and each group told of once; a tent's owed rouse; the tent's door.
W2_FIX_B_MUTATIONS = {
    "l1b w2 fix B: Validate checks resident posts at the highest difficulty only": (
        FLOW,
        "for _, def in (groupsOf(level, layout, rank, ranks)) do",
        "for _, def in (groupsOf(level, layout, levelRanks[1], ranks)) do",
    ),
    "l1b w2 fix B: Validate checks a tent's ring at the highest difficulty only": (
        FLOW,
        "for _, tent in (tentsOf(level, layout, rank, ranks)) do",
        "for _, tent in (tentsOf(level, layout, levelRanks[1], ranks)) do",
    ),
    "l1b w2 fix B: Validate tells of a resident post once a difficulty": (
        FLOW,
        "\t\t\t\t\ttold[def.id] = true\n\t\t\t\t\tproblem(\n\t\t\t\t\t\t`group {def.id}: post {index}",
        "\t\t\t\t\tproblem(\n\t\t\t\t\t\t`group {def.id}: post {index}",
    ),
    "l1b w2 fix B: Validate tells of a ring post once a difficulty": (
        FLOW,
        "\t\t\t\t\ttold[id] = true\n\t\t\t\t\tproblem(\n\t\t\t\t\t\t`group {id}: ring post {index}",
        "\t\t\t\t\tproblem(\n\t\t\t\t\t\t`group {id}: ring post {index}",
    ),
    "l1b w2 fix B: TentOwesRouse keeps rousing a group already up": (
        FLOW,
        "return owed and campBusy and not groupAwake",
        "return owed and campBusy",
    ),
    "l1b w2 fix B: TentOwesRouse keeps rousing for a quiet camp": (
        FLOW,
        "return owed and campBusy and not groupAwake",
        "return owed and not groupAwake",
    ),
    "l1b w2 fix B: TentDoor on the wall, no clearance": (
        GEOMETRY,
        "local out = math.min(edge + math.max(clear, 0), distance)",
        "local out = math.min(edge, distance)",
    ),
    "l1b w2 fix B: TentDoor runs past the post": (
        GEOMETRY,
        "local out = math.min(edge + math.max(clear, 0), distance)",
        "local out = edge + math.max(clear, 0)",
    ),
    "l1b w2 fix B: TentDoor takes a negative clearance": (
        GEOMETRY,
        "edge + math.max(clear, 0)",
        "edge + clear",
    ),
    "l1b w2 fix B: TentDoor swaps the box's sides": (
        GEOMETRY,
        "edge = math.min(edge, box.sx / 2 / math.abs(ux))",
        "edge = math.min(edge, box.sz / 2 / math.abs(ux))",
    ),
    "l1b w2 fix B: a post inside the footprint steps out anyway": (
        GEOMETRY,
        "local out = math.min(edge + math.max(clear, 0), distance)",
        "local out = math.max(math.min(edge + math.max(clear, 0), distance), edge)",
    ),
    "l1b w2 fix B: Plan's doors without the kind's radius": (
        FLOW,
        "local clear = if body ~= nil then body.radius else 0",
        "local clear = 0",
    ),
    "l1b w2 fix B: Plan's door is the post": (
        FLOW,
        "table.insert(doors, Vector3.new(x, post.at.Y, z))",
        "table.insert(doors, post.at)",
    ),
}
MUTATIONS.update(W2_FIX_B_MUTATIONS)

# The L1b Wave 2 fix round, the ui-engineer's ui-2 (fix-ui.md, texts as given): touch
# auto-target's camp rule, CampAim.
CAMP_AIM = "src/combat/client/Controllers/CampAim.luau"
FILES.append(CAMP_AIM)
# L1b Wave 4 (L1b-W4-32) rewrote CampAim.Takes as (onCampFloor, resting, phase): the six texts
# below are gone from the file. Kept as the record, never run; W4_UI_MUTATIONS holds their rules:
#   "a resting body is taken", "engaged takes a resting body" -> "l1b w4 ui: a resting body is taken"
#   "the gate takes camp bodies"                              -> "l1b w4 ui: the gate takes camp bodies"
#   "auto-target corners square", "... has no sight band"     -> "l1b w4 ui: an awake camp body is refused"
#                                                                (clause 4, in play, is gone)
#   "a body with no camp floor is refused"                    -> "l1b w4 ui: a body with no camp floor is refused"
W2_FIX_UI_REPLACED = {
    "l1b w2 ui: a resting body is taken": (CAMP_AIM, 'if phase == "gate" or resting then', 'if phase == "gate" then'),
    "l1b w2 ui: the gate takes camp bodies": (CAMP_AIM, 'if phase == "gate" or resting then', "if resting then"),
    "l1b w2 ui: engaged takes a resting body": (
        CAMP_AIM,
        '\tif phase == "gate" or resting then\n\t\treturn false\n\tend\n\tif camps == nil or engaged then\n\t\treturn true\n\tend\n',
        '\tif phase == "gate" then\n\t\treturn false\n\tend\n\tif camps == nil or engaged then\n\t\treturn true\n\tend\n\tif resting then\n\t\treturn false\n\tend\n',
    ),
    "l1b w2 ui: auto-target corners square": (
        CAMP_AIM,
        "return HitShapes.FlatToRect(root.X, root.Z, centre.X, centre.Z, half.X, half.Z)\n\t\t<= camps.chaseMargin",
        "return math.max(math.abs(root.X - centre.X) - half.X, math.abs(root.Z - centre.Z) - half.Z)\n\t\t<= camps.chaseMargin",
    ),
    "l1b w2 ui: auto-target has no sight band": (
        CAMP_AIM,
        "if root.Y < centre.Y - camps.sightBelow or root.Y > centre.Y + camps.sightAbove then",
        "if false then",
    ),
    "l1b w2 ui: a body with no camp floor is refused": (
        CAMP_AIM,
        "if centre == nil or half == nil then\n\t\treturn true",
        "if centre == nil or half == nil then\n\t\treturn false",
    ),
}
# The ui-engineer's L1b Wave 4 mutations (docs/prompts/l1b-w4-reports/client.md, texts as given).
W4_UI_MUTATIONS = {
    "l1b w4 ui: a resting body is taken": (
        CAMP_AIM,
        'return phase ~= "gate" and not resting',
        'return phase ~= "gate"',
    ),
    "l1b w4 ui: the gate takes camp bodies": (
        CAMP_AIM,
        'return phase ~= "gate" and not resting',
        "return not resting",
    ),
    "l1b w4 ui: an awake camp body is refused": (
        CAMP_AIM,
        'return phase ~= "gate" and not resting',
        "return false",
    ),
    "l1b w4 ui: a body with no camp floor is refused": (
        CAMP_AIM,
        "if not onCampFloor then\n\t\treturn true",
        "if not onCampFloor then\n\t\treturn false",
    ),
}
MUTATIONS.update(W4_UI_MUTATIONS)
FILES += ["src/shared/SwingGate.luau", SPAWN_SEED]  # SwingGate: A's SWING

# L1b Wave 2, luau-engineer A (docs/prompts/l1b-w2-reports/build-A.md "For B"): the crowd's ray,
# SwingGate, CampBrain's tent, dormancy and join-in, CrowdService's executors. Texts as A gave them.
SWING = "src/shared/SwingGate.luau"

L1B_W2_CROWD_MUTATIONS = {
    # HitShapes.CrowdRay / RayUpright / FlatToRect
    "l1b w2 crowd: CrowdRay without the head term": (
        HITSHAPES,
        "local entry = earlier(bodyEntry, headEntry)",
        "local entry = bodyEntry",
    ),
    "l1b w2 crowd: CrowdRay's crit test padded": (
        HITSHAPES,
        "return entry, HitShapes.Ray(origin, direction, reach, width, 0, head, headRadius) ~= nil",
        "return entry, HitShapes.Ray(origin, direction, reach, width, pad, head, headRadius) ~= nil",
    ),
    "l1b w2 crowd: CrowdRay's head at half height": (
        HITSHAPES,
        "local head = feet + Vector3.new(0, height - headRadius, 0)\n\tlocal bodyEntry",
        "local head = feet + Vector3.new(0, height / 2, 0)\n\tlocal bodyEntry",
    ),
    "l1b w2 crowd: CrowdRay's body back to a sphere": (
        HITSHAPES,
        "\t\tfeet,\n\t\tradius,\n\t\ttop - radius,\n\t\tradius\n\t)",
        "\t\tfeet,\n\t\theight / 2,\n\t\theight / 2,\n\t\tradius\n\t)",
    ),
    "l1b w2 crowd: CrowdRay's entry always the head's": (
        HITSHAPES,
        "local entry = earlier(bodyEntry, headEntry)",
        "local entry = if headEntry ~= nil then headEntry else bodyEntry",
    ),
    "l1b w2 crowd: CrowdRay's top without the max": (
        HITSHAPES,
        "local top = math.max(height - 2 * headRadius, height / 2 + radius)",
        "local top = height - 2 * headRadius",
    ),
    "l1b w2 crowd: RayUpright drops a cap": (
        HITSHAPES,
        "local best = earlier(firstIn(lowEnter, lowExit, reach), firstIn(highEnter, highExit, reach))",
        "local best = firstIn(lowEnter, lowExit, reach)",
    ),
    "l1b w2 crowd: FlatToRect with square corners": (
        HITSHAPES,
        "local dz = math.max(math.abs(z - cz) - hz, 0)\n\treturn math.sqrt(dx * dx + dz * dz)",
        "local dz = math.max(math.abs(z - cz) - hz, 0)\n\treturn math.max(dx, dz)",
    ),
    # SwingGate
    "l1b w2 crowd: SwingGate.Took ignores airborne": (SWING, "state.used = airborne", "state.used = true"),
    "l1b w2 crowd: SwingGate.Landed does nothing": (
        SWING,
        "function SwingGate.Landed(state: State)\n\tstate.used = false",
        "function SwingGate.Landed(state: State)\n\tlocal _ = state",
    ),
    "l1b w2 crowd: SwingGate.Allows ignores used": (SWING, "return not (airborne and state.used)", "return true"),
    "l1b w2 crowd: SwingGate.IsAir with >=": (
        SWING,
        "return height > standOffset + SwingGate.AIR_MARGIN_STUDS",
        "return height >= standOffset + SwingGate.AIR_MARGIN_STUDS",
    ),
    # CampBrain
    "l1b w2 crowd: a tent's ring faces inward": (
        CAMP,
        'local turn = if posture == "fire" then math.pi else 0',
        "local turn = math.pi",
    ),
    "l1b w2 crowd: a tent sits at rest": (
        CAMP,
        'return if group.def.posture == "fire" then "rest" else "idle"',
        'return if group.def.posture == "fire" or group.def.posture == "tent" then "rest" else "idle"',
    ),
    "l1b w2 crowd: Problems skips the tent posture": (
        CAMP,
        'local POSTURES: { Types.CampPosture } = { "guard", "patrol", "fire", "tent" }',
        'local POSTURES: { Types.CampPosture } = { "guard", "patrol", "fire" }',
    ),
    "l1b w2 crowd: Problems lets dormantRadius equal a sight": (
        CAMP,
        "if isFinite(sight) and dormantRadius <= sight then",
        "if isFinite(sight) and dormantRadius < sight then",
    ),
    "l1b w2 crowd: Dormant while in home": (
        CAMP,
        'function CampBrain.Dormant(group: Group, roots: { Vector3 }, rules: Types.CampRulesConfig): boolean\n\tif group.state ~= "rest" then',
        'function CampBrain.Dormant(group: Group, roots: { Vector3 }, rules: Types.CampRulesConfig): boolean\n\tif group.state ~= "rest" and group.state ~= "home" then',
    ),
    "l1b w2 crowd: Dormant ignores dormantRadius": (
        CAMP,
        "local radius = rules.dormantRadius",
        "local radius = 0",
    ),
    "l1b w2 crowd: JoinIn does not chain": (
        CAMP,
        "\t\t\t\ttable.insert(answer, other)\n\t\t\t\ttable.insert(queue, other)",
        "\t\t\t\ttable.insert(answer, other)",
    ),
    "l1b w2 crowd: JoinIn uses the first waker's sight for the whole chain": (
        CAMP,
        "local reach = rules.joinFactor * postureRules(group.def, rules).sight",
        "local reach = rules.joinFactor * postureRules(groups[woke[1]].def, rules).sight",
    ),
    "l1b w2 crowd: JoinIn joins a held group": (
        CAMP,
        '\t\t\t\tcandidate.state == "rest"\n\t\t\t\tand not candidate.held\n',
        '\t\t\t\tcandidate.state == "rest"\n',
    ),
    "l1b w2 crowd: gaps written across camps": (
        CROWD,
        "if earlier.brain.def.camp == def.camp then",
        "if true then",
    ),
    # Re-aimed by the fix round's tail (B-3: the held test is a clause of its own now): same rule.
    "l1b w2 crowd: Rouse wakes a held group": (
        CAMP,
        'if group.held then\n\t\treturn false\n\tend\n\tif group.state ~= "rest" and not',
        'if false then\n\t\treturn false\n\tend\n\tif group.state ~= "rest" and not',
    ),
    "l1b w2 crowd: TentActive ignores the dead residents": (
        CAMP,
        "return busy or residentsAlive <= 0",
        "return busy",
    ),
    "l1b w2 crowd: TentDue ignores active": (
        CAMP,
        "return active and tent.left > 0 and now >= tent.nextAt - TIME_EPSILON",
        "return tent.left > 0 and now >= tent.nextAt - TIME_EPSILON",
    ),
    "l1b w2 crowd: TentSent does not move nextAt": (
        CAMP,
        "tent.nextAt = now + every",
        "tent.nextAt = tent.nextAt",
    ),
    # CrowdService
    "l1b w2 crowd: a dormant body is integrated": (
        CROWD,
        "\t\tif enemy.dormant then\n\t\t\t-- L1b-W2-10: not integrated",
        "\t\tif false then\n\t\t\t-- L1b-W2-10: not integrated",
    ),
    "l1b w2 crowd: a dormant body is sent": (
        CROWD,
        "\t\tif enemy.dormant then\n\t\t\t-- L1b-W2-10: far from every player",
        "\t\tif false then\n\t\t\t-- L1b-W2-10: far from every player",
    ),
    "l1b w2 crowd: the flush skips the info refresh": (
        CROWD,
        "pendingSpawnSet[id] = nil\n\t\t\t\ttable.insert(batch, refreshInfo(enemy))",
        "pendingSpawnSet[id] = nil\n\t\t\t\ttable.insert(batch, enemy.spawnInfo)",
    ),
    "l1b w2 crowd: a late joiner's batch skips the info refresh": (
        CROWD,
        "if not pendingSpawnSet[enemy.id] then\n\t\t\ttable.insert(batch, refreshInfo(enemy))",
        "if not pendingSpawnSet[enemy.id] then\n\t\t\ttable.insert(batch, enemy.spawnInfo)",
    ),
    "l1b w2 crowd: the join-in never runs": (CROWD, "\tif #woke > 0 then\n", "\tif false then\n"),
    # Re-aimed by the fix round's tail (the rouse's event names the state it left): same rule.
    "l1b w2 crowd: a rouse is never executed": (
        CROWD,
        "\t\tif rouse[index] then\n",
        "\t\tif false then\n",
    ),
    "l1b w2 crowd: GroupedOn not taken down at a death": (
        CROWD,
        "grouped[enemy.floor] = math.max((grouped[enemy.floor] or 0) - 1, 0)",
        "grouped[enemy.floor] = grouped[enemy.floor] or 0",
    ),
    "l1b w2 crowd: the [Perf] attribute never set": (
        CROWD,
        "Workspace:SetAttribute(attribute, p95)",
        "Workspace:SetAttribute(attribute, nil)",
    ),
    "l1b w2 crowd: the [Perf] attribute set with no name": (
        CROWD,
        'perf.attribute = if typeof(attribute) == "string" and attribute ~= "" then attribute else nil',
        'perf.attribute = if typeof(attribute) == "string" and attribute ~= "" then attribute else "CrowdPerfMs"',
    ),
}

# Stale Wave 1 mutations whose text A's edits changed: label -> (file, new old-text, new new-text).
L1B_W2_CROWD_REPLACED = {
    "l1b crowd: in play ignores chaseMargin": (
        CAMP,
        "HitShapes.FlatToRect(root.X, root.Z, rect.x, rect.z, rect.hx, rect.hz) <= rules.chaseMargin",
        "HitShapes.FlatToRect(root.X, root.Z, rect.x, rect.z, rect.hx, rect.hz) <= 0",
    ),
    "l1b crowd: a fire's sitters face away from it": (
        CAMP,
        'local turn = if posture == "fire" then math.pi else 0',
        "local turn = 0",
    ),
    "l1b crowd: a group walking home engages": (
        CROWD,
        'if #group.bodies > 0 and (brain.state == "rise" or brain.state == "fight") then',
        'if #group.bodies > 0 and brain.state ~= "rest" then',
    ),
}
# "l1b crowd: in play has square corners" is retired: the rectangle distance moved into
# HitShapes.FlatToRect, whose own mutation "l1b w2 crowd: FlatToRect with square corners" replaces it.
MUTATIONS.update(L1B_W2_CROWD_MUTATIONS)
# A's edits moved the text of three Wave 1 mutations: same labels, same rules, new texts.
MUTATIONS.update(L1B_W2_CROWD_REPLACED)

# The L1b Wave 2 fix round, luau-engineer A (fix-A.md "For B", texts as given): SwingGate's one
# landing rule (A-1), the frozen patroller's state (A-2), `resting` on the spawn info (ui-2).
L1B_W2_FIX_A_MUTATIONS = {
    # A-1: SwingGate's one landing rule
    "l1b w2 fix A: a turn near the floor is no landing": (
        SWING,
        "if math.min(state.lowest, excess) <= reach then",
        "if false then",
    ),
    "l1b w2 fix A: a fall that ends grounded is no landing": (
        SWING,
        "if state.airborne or state.falling then\n\t\t\tlanded = true",
        "if false then\n\t\t\tlanded = true",
    ),
    "l1b w2 fix A: the fall's lowest sample not kept": (
        SWING,
        "state.lowest = math.min(state.lowest, excess)\n\t\t\tstate.fallSpeed",
        "state.lowest = state.lowest\n\t\t\tstate.fallSpeed",
    ),
    "l1b w2 fix A: direction from the replicated speed first": (
        SWING,
        "local sinking = step < 0 or (step == 0 and vy < -SwingGate.STILL_SPEED)",
        "local sinking = vy < -SwingGate.STILL_SPEED or (step < 0 and vy <= SwingGate.STILL_SPEED)",
    ),
    "l1b w2 fix A: the footprint is the centre only": (
        SWING,
        "SwingGate.FOOTPRINT = { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }",
        "SwingGate.FOOTPRINT = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }",
    ),
    "l1b w2 fix A: Higher keeps the lower floor": (
        SWING,
        "return math.max(floorY, hitY)",
        "return math.min(floorY, hitY)",
    ),
    "l1b w2 fix A: ProbePoint's back axis not turned": (
        SWING,
        "local bx, bz = -rz, rx",
        "local bx, bz = rx, rz",
    ),
    "l1b w2 fix A: a down does not clear": (
        SWING,
        "if down then\n\t\tstate.used = false",
        "if down then\n\t\tstate.used = state.used",
    ),
    "l1b w2 fix A: the claim's landing ahead never taken": (
        SWING,
        "state.used = false\n\t\t\tstate.ahead = true",
        "state.used = true\n\t\t\tstate.ahead = true",
    ),
    "l1b w2 fix A: Judge without the lag": (
        SWING,
        "(SwingGate.TURN_WINDOW_SECONDS + lag)",
        "(SwingGate.TURN_WINDOW_SECONDS)",
    ),
    "l1b w2 fix A: a landing taken ahead counted again": (
        SWING,
        "if state.ahead then\n\t\tstate.ahead = false\n\telse",
        "if false then\n\t\tstate.ahead = false\n\telse",
    ),
    # A-2: the freeze-time reset (the reviewer's mutation)
    "l1b w2 fix A: a frozen patroller keeps its walking state": (
        CROWD,
        "body.state = CampBrain.Shows(brain, false) or body.state",
        "body.state = body.state",
    ),
    # ui-2: resting on the spawn info
    "l1b w2 fix A: no re-announce at a change to or from rest": (
        CROWD,
        'local restChanged = from == "rest" or to == "rest"',
        "local restChanged = false",
    ),
    "l1b w2 fix A: refreshInfo never writes resting": (
        CROWD,
        'info.resting = if group ~= nil and (group.brain.held or group.brain.state == "rest")',
        'info.resting = if false and (group.brain.held or group.brain.state == "rest")',
    ),
    "l1b w2 fix A: a batch of re-announces alone is never sent": (
        CROWD,
        "if #pendingSpawnOrder > 0 or #camp.reannounceOrder > 0 then",
        "if #pendingSpawnOrder > 0 then",
    ),
}
MUTATIONS.update(L1B_W2_FIX_A_MUTATIONS)
# Retired, never silently: the rectangle distance moved into HitShapes.FlatToRect, whose own
# "l1b w2 crowd: FlatToRect with square corners" holds the rule now.
del MUTATIONS["l1b crowd: in play has square corners"]

# The fix round's tail (docs/prompts/l1b-w2-fix-tail.md): B-4's door and rise on SpawnResident,
# B-3's rouse from home and the event naming the state it left.
L1B_W2_FIX_TAIL_MUTATIONS = {
    "l1b w2 fix tail: SpawnResident ignores `from`": (
        CROWD,
        'CrowdService.Spawn(kind, from or post.at, "fight", post.at, nil, record.floor)',
        'CrowdService.Spawn(kind, post.at, "fight", post.at, nil, record.floor)',
    ),
    "l1b w2 fix tail: the door taken as its post": (
        CROWD,
        "enemy.resident = { group = group, post = post, leg = post.leg }",
        "enemy.resident = { group = group, post = { at = enemy.position, yaw = post.yaw, leg = post.leg }, leg = post.leg }",
    ),
    "l1b w2 fix tail: a body from its door never rises": (
        CROWD,
        "enemy.spawnInfo.rises = true",
        "enemy.spawnInfo.rises = nil",
    ),
    "l1b w2 fix tail: every resident rises": (
        CROWD,
        "if from ~= nil then\n\t\t-- Shown rising",
        "if true then\n\t\t-- Shown rising",
    ),
    "l1b w2 fix tail: the rise is never cleared after the announce": (
        CROWD,
        "info.rises = nil",
        "info.rises = info.rises",
    ),
    # Re-aimed when the lead ruled B-3 option (b): from home only with a player in play.
    "l1b w2 fix tail: Rouse leaves a homeward group home": (
        CAMP,
        '(group.state == "home" and inPlay)',
        "false",
    ),
    "l1b w2 fix tail: Rouse lifts a homeward group with nobody in play": (
        CAMP,
        '(group.state == "home" and inPlay)',
        '(group.state == "home")',
    ),
    # Re-aimed by the lead's ruling (i) (the tent's rouse goes through CampBrain.TentRouse): same rules.
    "l1b w2 fix tail: the tent's rouse is told a player is always in play": (
        CROWD,
        "CampBrain.TentRouse(brain, simTime, next(brain.inPlay) ~= nil)",
        "CampBrain.TentRouse(brain, simTime, true)",
    ),
    "l1b w2 fix tail: the tent's rouse is told nobody is ever in play": (
        CROWD,
        "CampBrain.TentRouse(brain, simTime, next(brain.inPlay) ~= nil)",
        "CampBrain.TentRouse(brain, simTime, false)",
    ),
    # The lead's ruling (i): a tent's rouse needs a player in play, from rest or from home.
    "l1b w2 fix tail: TentRouse with nobody in play rouses": (
        CAMP,
        "if not inPlay then\n\t\treturn false\n\tend\n\treturn CampBrain.Rouse(group, now, inPlay)",
        "if false then\n\t\treturn false\n\tend\n\treturn CampBrain.Rouse(group, now, inPlay)",
    ),
    "l1b w2 fix tail: TentRouse never lifts a homeward group": (
        CAMP,
        "return CampBrain.Rouse(group, now, inPlay)",
        "return CampBrain.Rouse(group, now, false)",
    ),
    "l1b w2 fix tail: the tent's rouse is a plain Rouse": (
        CROWD,
        "if CampBrain.TentRouse(brain, simTime, next(brain.inPlay) ~= nil) then",
        "if CampBrain.Rouse(brain, simTime, next(brain.inPlay) ~= nil) then",
    ),
    "l1b w2 fix tail: a rouse's event says it left rest": (
        CROWD,
        'queueEvent(index, group, before, "rise", false)',
        'queueEvent(index, group, "rest", "rise", false)',
    ),
}
MUTATIONS.update(L1B_W2_FIX_TAIL_MUTATIONS)

# The fix-diff round (docs/prompts/l1b-w2-fix-diff-round.md): M1 the landing ahead only with a
# lag (the server), m1 the client's stricter turn window, and the fall's speed-up inside the lag
# that the held-hop and low double-jump cases at the 0.3 s ceiling need.
L1B_W2_FIX_DIFF_MUTATIONS = {
    "l1b w2 fix diff: the client takes the landing ahead too (no lag guard)": (
        SWING,
        "if lag > 0 and airborne and state.used and state.falling and not state.ahead then",
        "if airborne and state.used and state.falling and not state.ahead then",
    ),
    "l1b w2 fix diff: the client's turn window is the server's": (
        SWING,
        "SwingGate.CLIENT_TURN_WINDOW_SECONDS = 0.05",
        "SwingGate.CLIENT_TURN_WINDOW_SECONDS = 0.1",
    ),
    "l1b w2 fix diff: Observe ignores the window it is passed": (
        SWING,
        "local window = if turnWindow ~= nil then turnWindow else SwingGate.TURN_WINDOW_SECONDS",
        "local window = SwingGate.TURN_WINDOW_SECONDS",
    ),
    "l1b w2 fix diff: the landing ahead without gravity": (
        SWING,
        "\n\t\t\t+ SwingGate.FALL_GRAVITY * lag * (SwingGate.TURN_WINDOW_SECONDS + lag * 0.5)",
        "",
    ),
    "l1b w2 fix diff: the landing ahead's turn window at today's speed": (
        SWING,
        "SwingGate.FALL_GRAVITY * lag * (SwingGate.TURN_WINDOW_SECONDS + lag * 0.5)",
        "SwingGate.FALL_GRAVITY * lag * (lag * 0.5)",
    ),
}
MUTATIONS.update(L1B_W2_FIX_DIFF_MUTATIONS)

# ------------------------------------------------------------------------------------------------
# L1b Wave 4 (docs/INTERFACES.md "L1b Wave 4 — no waits, no walls").
REGION = "src/shared/Region.luau"
FILES.append(REGION)
# Wave 1-3 entries of StageFlow whose text this wave changed: same labels, same rules. (The three
# "l1b: campClear ..." entries follow CAMP_CLEAR, rewritten above for the one-line clear.)
L1B_W4_RUN_REPLACED = {
    "l1b: countMult applied to residents": (
        FLOW,
        "local groups, residents, residentStocks = groupsOf(level, layout, rank, ranks, cellsOf)",
        "local groups, residents, residentStocks = groupsOf(level, layout, rank, ranks, cellsOf)\n\tfor _, def in groups do\n\t\tfor _, unit in def.units do\n\t\t\tunit.count = math.round(unit.count * level.difficulties[difficulty].countMult)\n\t\tend\n\tend",
    ),
}
MUTATIONS.update(L1B_W4_RUN_REPLACED)
# Retired, never silently: their rules were reversed by this wave, and each has a Wave 4 entry
# that holds the new rule.
#   "l1b w2: campClear with tent stock left" -> "l1b w4: progress waits for tent stock again"
#                                               (L1b-W4-29; taken out of W2_RUN_MUTATIONS itself)
#   "l1b w2: a zone's stock without its tent" -> "l1b w4: zone.stock counts the tent again"
#                                               (L1b-W4-30: zone.stock is the residents only)
del MUTATIONS["l1b w2: a zone's stock without its tent"]

# luau-engineer B (the run): StageFlow's regions, approaches, pace, the clear and Fielded.
L1B_W4_RUN_MUTATIONS = {
    "l1b w4: progress waits for tent stock again": (
        FLOW,
        "byFloor[index] ~= 0 then",
        "byFloor[index] ~= 0 or zone.tentStock > 0 then",
    ),
    "l1b w4: zone.stock counts the tent again": (
        FLOW,
        "local stop = if camp.locks == true then nil else camp.approach",
        "local stop = if camp.locks == true then nil else camp.approach\n\t\tfor _, tent in tents do\n\t\t\tif tent.zone == index then\n\t\t\t\tlocal own = residentStocks[camp.id] or {}\n\t\t\t\tresidentStocks[camp.id] = own\n\t\t\t\tfor _, kind in tent.kinds do\n\t\t\t\t\town[kind] = (own[kind] or 0) + 1\n\t\t\t\tend\n\t\t\tend\n\t\tend",
    ),
    "l1b w4: Fielded counts the whole stock": (
        FLOW,
        "for index = 1, math.min(sent, #tent.kinds) do",
        "for index = 1, #tent.kinds do",
    ),
    "l1b w4: Fielded ignores sent": (
        FLOW,
        "for index = 1, math.min(sent, #tent.kinds) do",
        "for index = 1, math.min(0, #tent.kinds) do",
    ),
    "l1b w4: Plan gives B's zone its own copy of the graph": (
        FLOW,
        "graphs[id] = graph",
        "graphs[id] = if id == region.camps[1] then graph else Region.Build(cells)",
    ),
    "l1b w4: Plan gives each def its own copy of the cells": (
        FLOW,
        "cellsOf[id] = graph.cells",
        "cellsOf[id] = table.clone(graph.cells)",
    ),
    "l1b w4: a locking camp allowed in a region": (
        FLOW,
        "if camp.locks == true then\n\t\t\t\tproblem(`{here}: camp {camp.id} locks, and a boss room is in no region`)",
        "if false then\n\t\t\t\tproblem(`{here}: camp {camp.id} locks, and a boss room is in no region`)",
    ),
    "l1b w4: the lock clearance skipped": (FLOW, "if gap < needed - 1e-6 then", "if false then"),
    "l1b w4: the lock clearance measured from the floor's centre": (
        FLOW,
        "local gap = rectGap(cell, floor)",
        "local gap = rectGap(cell, { x = floor.x, z = floor.z, hx = 0, hz = 0 })",
    ),
    "l1b w4: the lock clearance's reach at Normal only": (
        FLOW,
        "top = math.max(top, ranks[name] or 0)",
        "top = math.min(math.max(top, ranks[name] or 0), 1)",
    ),
    "l1b w4: doorSpare ignored": (
        FLOW,
        "local spare = if isFinite(numbers.doorSpare) then numbers.doorSpare else 0",
        "local spare = 0",
    ),
    "l1b w4: a road cell's wire check at its centre": (
        FLOW,
        "math.abs(cell.x) + cell.sx / 2 > WIRE_REACH",
        "math.abs(cell.x) > WIRE_REACH",
    ),
    "l1b w4: a tent without pace passes": (
        FLOW,
        'if type(pace) ~= "table" then',
        "if false then",
    ),
    "l1b w4: a pace lead over 1 passes": (
        FLOW,
        "pace.lead >= 0 and pace.lead <= 1",
        "pace.lead >= 0",
    ),
    "l1b w4: an approach on a locking camp passes": (
        FLOW,
        "if camp.locks == true then\n\t\t\t\tproblem(`camp {camp.id} locks, and a boss room has no approach`)",
        "if false then\n\t\t\t\tproblem(`camp {camp.id} locks, and a boss room has no approach`)",
    ),
    "l1b w4: Plan keeps a locking camp's approach": (
        FLOW,
        "local stop = if camp.locks == true then nil else camp.approach",
        "local stop = camp.approach",
    ),
    "l1b w4: Skip passes over the open camps (Wave 2's N)": (
        FLOW,
        "local stop = nextApproach(plan, state, index)",
        "local stop = 0",
    ),
    "l1b w4: Skip takes a done camp": (
        FLOW,
        "zone.approach ~= nil and not state.done[index] then",
        "zone.approach ~= nil then",
    ),
    # The lead's amendment of L1b-W4-31: N never moves a party backwards. This clause also holds
    # the rule "a camp whose checkpoint was reached is passed over" (its old per-zone test is gone:
    # every zone after the furthest reached checkpoint has none reached), so it replaces the entry
    # "l1b w4: Skip takes a camp whose checkpoint was reached".
    "l1b w4: N moves a party back past a reached checkpoint": (
        FLOW,
        "\tfor index in state.reached do\n\t\tfrom = math.max(from, index)\n\tend\n",
        "",
    ),
    "l1b w4: Skip ignores approached": (
        FLOW,
        "local from = state.approached",
        "local from = 0",
    ),
    "l1b w4: Skip forgets where it stopped": (FLOW, "state.approached = stop", "state.approached = state.approached"),
}
MUTATIONS.update(L1B_W4_RUN_MUTATIONS)

# L1b Wave 4, luau-engineer A (docs/prompts/l1b-w4-reports/crowd_mutations.py, texts verbatim).
# L1b Wave 4, luau-engineer A (docs/prompts/l1b-w4-reports/crowd.md "For other owners"): Region,
# CampBrain's chase, the stand-down, Forget and the pace tent, CrowdService's executors.
L1B_W4_CROWD_MUTATIONS = {
    # Region
    "l1b w4 crowd: Region.Clamp ignores the radius": (
        REGION,
        "\t\tlocal limitX = math.max(cell.hx - radius, 0)\n\t\tlocal limitZ = math.max(cell.hz - radius, 0)\n\t\tlocal cx",
        "\t\tlocal limitX = cell.hx\n\t\tlocal limitZ = cell.hz\n\t\tlocal cx",
    ),
    "l1b w4 crowd: Region.Runway stops at the first cell's edge": (
        REGION,
        "if t0 <= t1 and t0 <= reach + EPS and t1 > reach then",
        "if t0 <= t1 and t0 <= reach + EPS and t1 > reach and reach == 0 then",
    ),
    "l1b w4 crowd: Region.Toward always answers the goal": (
        REGION,
        "return Vector3.new(door.x, from.Y, door.z), true",
        "return g, false",
    ),
    "l1b w4 crowd: Region.Problems accepts a cycle": (
        REGION,
        "if joined and pairCount ~= count - 1 then",
        "if false then",
    ),
    "l1b w4 crowd: Region.Problems checks a door on one axis only": (
        REGION,
        "if wideX < minDoor - EPS or wideZ < minDoor - EPS then",
        "if wideX < minDoor - EPS then",
    ),
    "l1b w4 crowd: Region.Distance takes the farthest cell": (
        REGION,
        "\t\tlocal distance = HitShapes.FlatToRect(x, z, cell.x, cell.z, cell.hx, cell.hz)\n\t\tif distance < best then",
        "\t\tlocal distance = HitShapes.FlatToRect(x, z, cell.x, cell.z, cell.hx, cell.hz)\n\t\tif distance > best or best == math.huge then",
    ),
    "l1b w4 crowd: Region.Build makes touching cells neighbours": (
        REGION,
        "return wideX > EPS and wideZ > EPS",
        "return wideX >= 0 and wideZ >= 0",
    ),
    "l1b w4 crowd: Region.Inside ignores the radius": (
        REGION,
        "\tlocal limitX = math.max(cell.hx - radius, 0)\n\tlocal limitZ = math.max(cell.hz - radius, 0)\n\treturn math.abs(x - cell.x)",
        "\tlocal limitX = cell.hx\n\tlocal limitZ = cell.hz\n\treturn math.abs(x - cell.x)",
    ),
    # CampBrain: Struck, known, Melee, Reachable
    "l1b w4 crowd: Struck blocks a homeward group": (
        CAMP,
        "function CampBrain.Evades(group: Group): boolean\n\treturn group.held\nend",
        'function CampBrain.Evades(group: Group): boolean\n\treturn group.held or group.state == "home"\nend',
    ),
    "l1b w4 crowd: Struck ignores now (hitAt not set)": (
        CAMP,
        "\t\tgroup.hitAt[byUserId] = now\n",
        "",
    ),
    "l1b w4 crowd: a lever's hit is remembered": (
        CAMP,
        "\tgroup.hit = true\n\tif byUserId ~= 0 then",
        "\tgroup.hit = true\n\tif true then",
    ),
    "l1b w4 crowd: known ignores the hit memory": (
        CAMP,
        "\tif group.hitAt[target.userId] ~= nil then\n\t\treturn true\n\tend",
        "\tif false then\n\t\treturn true\n\tend",
    ),
    "l1b w4 crowd: known ignores the band": (
        CAMP,
        "\tif not inBand(def, root, rules) then\n\t\treturn false\n\tend\n\tlocal sight = rules.chaseSight",
        "\tlocal sight = rules.chaseSight",
    ),
    "l1b w4 crowd: the prune keeps old hits": (
        CAMP,
        "if now - at > memory + TIME_EPSILON then",
        "if false then",
    ),
    "l1b w4 crowd: Melee ignores meleeAbove": (
        CAMP,
        "\t\tand root.Y - def.floorY <= rules.meleeAbove",
        "\t\tand true",
    ),
    "l1b w4 crowd: Melee ignores chaseMargin": (
        CAMP,
        "and Region.Distance(region, root.X, root.Z) <= rules.chaseMargin",
        "and Region.Distance(region, root.X, root.Z) <= 0",
    ),
    "l1b w4 crowd: Reachable drops the shooter clause": (
        CAMP,
        "\t\treturn false\n\tend\n\tfor _, shooter in shooters do\n\t\tif flatDistance(shooter.at, root) <= shooter.reach then",
        "\t\treturn false\n\tend\n\tfor _, shooter in shooters do\n\t\tif false then",
    ),
    "l1b w4 crowd: a group with no region uses chaseSight": (
        CAMP,
        "\tif def.region == nil then\n\t\treturn CampBrain.InPlay(def, target, input.shooters, rules)\n\tend\n\tif group.hitAt",
        "\tif group.hitAt",
    ),
    # CampBrain: the leash, the stand-down, home, Forget
    "l1b w4 crowd: the leash ignores closing": (
        CAMP,
        "if anyReach or input.closing then\n\t\t\tgroup.quietSince = now",
        "if anyReach then\n\t\t\tgroup.quietSince = now",
    ),
    "l1b w4 crowd: the stand-down never sets": (
        CAMP,
        "elseif not group.standDown and now - group.meleeQuietSince >= leash then\n\t\t\t\tgroup.standDown = true",
        "elseif not group.standDown and now - group.meleeQuietSince >= leash then\n\t\t\t\tgroup.standDown = false",
    ),
    "l1b w4 crowd: closing does not hold the melee clock": (
        CAMP,
        "elseif not group.standDown and input.closing then\n\t\t\t\tgroup.meleeQuietSince = now",
        "elseif false then\n\t\t\t\tgroup.meleeQuietSince = now",
    ),
    "l1b w4 crowd: a melee-reachable player does not clear the stand-down": (
        CAMP,
        "\t\t\tif anyMelee then\n\t\t\t\tgroup.meleeQuietSince = now\n\t\t\t\tgroup.standDown = false",
        "\t\t\tif anyMelee then\n\t\t\t\tgroup.meleeQuietSince = now",
    ),
    "l1b w4 crowd: StandsDown ignores rusher": (
        CAMP,
        'return rusher and not group.held and group.state == "fight" and group.standDown',
        'return not group.held and group.state == "fight" and group.standDown',
    ),
    "l1b w4 crowd: home turns back on an unreachable hit": (
        CAMP,
        "\t\tif not reachable[userId] then\n\t\t\tcontinue\n\t\tend\n\t\tif group.struckBy[userId] then",
        "\t\tif not reachable[userId] and not group.struckBy[userId] then\n\t\t\tcontinue\n\t\tend\n\t\tif group.struckBy[userId] then",
    ),
    "l1b w4 crowd: home goes through rise": (
        CAMP,
        '\t\t\t-- that was just fighting has nothing to rise from.\n\t\t\tchanged = "fight"',
        '\t\t\t-- that was just fighting has nothing to rise from.\n\t\t\tchanged = "rise"',
    ),
    "l1b w4 crowd: home never turns back on a sighting": (
        CAMP,
        "\t\tfor _, member in input.members do\n\t\t\tif CampBrain.Sees(def, member, target, rules) then\n\t\t\t\treturn true\n\t\t\tend\n\t\tend\n\tend\n\treturn false\nend\n\n-- One step of a group",
        "\tend\n\treturn false\nend\n\n-- One step of a group",
    ),
    "l1b w4 crowd: Forget leaves a fighting group fighting": (
        CAMP,
        'if group.held or (group.state ~= "rise" and group.state ~= "fight") then',
        'if group.held or group.state ~= "rise" then',
    ),
    "l1b w4 crowd: Forget keeps the hit memory": (
        CAMP,
        "\ttable.clear(group.reachable)\n\ttable.clear(group.hitAt)\n\ttable.clear(group.struckBy)\n\tif group.held",
        "\ttable.clear(group.reachable)\n\ttable.clear(group.struckBy)\n\tif group.held",
    ),
    "l1b w4 crowd: Goal leaves a stood-down rusher standing": (
        CAMP,
        'elseif state == "home" or (state == "fight" and group.standDown) then\n\t\tif CampBrain.AtPost(post, at, rules) then',
        'elseif state == "home" then\n\t\tif CampBrain.AtPost(post, at, rules) then',
    ),
    "l1b w4 crowd: Shows a stood-down rusher as the brain's": (
        CAMP,
        'elseif state == "home" or (state == "fight" and group.standDown) then\n\t\treturn if moving then "move" else "idle"',
        'elseif state == "home" then\n\t\treturn if moving then "move" else "idle"',
    ),
    "l1b w4 crowd: chaseSight may be 0": (
        CAMP,
        "\tchaseSight = true,\n\tmeleeAbove = true,",
        "\tmeleeAbove = true,",
    ),
    # CampBrain: the pace tent
    "l1b w4 crowd: TentActive ignores ahead": (
        CAMP,
        "return busy and residentsAlive > 0 and ahead",
        "return busy and residentsAlive > 0",
    ),
    "l1b w4 crowd: Ahead ignores lead": (
        CAMP,
        ">= pace.lead - TIME_EPSILON",
        ">= -TIME_EPSILON",
    ),
    "l1b w4 crowd: Ahead with no residents": (
        CAMP,
        "if residents <= 0 or pace.seconds <= 0 then\n\t\treturn false",
        "if pace.seconds <= 0 then\n\t\treturn false",
    ),
    "l1b w4 crowd: TentClock counts idle time": (
        CAMP,
        "\tif busy and lastAt ~= nil then\n\t\ttent.busySeconds += math.max(now - lastAt, 0)\n\tend\n\ttent.lastAt = if busy then now else nil",
        "\tif lastAt ~= nil then\n\t\ttent.busySeconds += math.max(now - lastAt, 0)\n\tend\n\ttent.lastAt = now",
    ),
    # CrowdBrain
    "l1b w4 crowd: a lane is cut at the floor's rectangle": (
        BRAIN,
        "\tif region ~= nil then\n\t\treturn Region.Runway(region.cells, from, heading, radius)",
        "\tif false then\n\t\treturn Region.Runway(region.cells, from, heading, radius)",
    ),
    "l1b w4 crowd: a retreat is cut at the floor's rectangle": (
        BRAIN,
        "\tif region ~= nil then\n\t\treturn Region.Clamp(region.cells, point, radius)",
        "\tif false then\n\t\treturn Region.Clamp(region.cells, point, radius)",
    ),
    # CrowdService
    "l1b w4 crowd: a region body is clamped to its floor rectangle": (
        CROWD,
        "\tlocal region = floor.region\n\tif region ~= nil then\n\t\tlocal inside = Region.Clamp(region.cells, position, radius)",
        "\tlocal region = floor.region\n\tif false then\n\t\tlocal inside = Region.Clamp(region.cells, position, radius)",
    ),
    "l1b w4 crowd: goals are not routed": (
        CROWD,
        "\t\tif region ~= nil then\n\t\t\t-- L1b-W4-17: through the region's doors.",
        "\t\tif false then\n\t\t\t-- L1b-W4-17: through the region's doors.",
    ),
    "l1b w4 crowd: a door is sought with the brain's stop distance": (
        CROWD,
        "\t\t\tif through then\n\t\t\t\tstop = 0\n\t\t\telse",
        "\t\t\tif through then\n\t\t\t\tstop = stop\n\t\t\telse",
    ),
    "l1b w4 crowd: a goal off the region keeps the brain's stop distance": (
        CROWD,
        "stop = math.max(stop - math.sqrt(dx * dx + dz * dz), 0)",
        "stop = stop",
    ),
    "l1b w4 crowd: allowed is reachable instead of known": (
        CROWD,
        "local allowed = if brain ~= nil then brain.known else nil",
        "local allowed = if brain ~= nil then brain.reachable else nil",
    ),
    "l1b w4 crowd: ForgetOthers forgets its own floor too": (
        CROWD,
        "\t\t\tif group.floor ~= keep then",
        "\t\t\tif true then",
    ),
    "l1b w4 crowd: ForgetOthers is never acted on": (
        CROWD,
        "\tlocal keep = camp.forgetBut\n\tif keep ~= nil then",
        "\tlocal keep = camp.forgetBut\n\tif false then",
    ),
    "l1b w4 crowd: a stood-down rusher keeps thinking": (
        CROWD,
        "\t\t\tor (\n\t\t\t\tCampBrain.StandsDown(brain, rusher)",
        "\t\t\tor (\n\t\t\t\tfalse",
    ),
    "l1b w4 crowd: a stood-down rusher is not healed at its post": (
        CROWD,
        '(homeward or CampBrain.StandsDown(brain, def.brain ~= "keepAway"))',
        "homeward",
    ),
    "l1b w4 crowd: a walking shooter stamps closing": (
        CROWD,
        "if resident ~= nil and not resting and mind ~= nil and rusher then",
        "if resident ~= nil and not resting and mind ~= nil then",
    ),
    "l1b w4 crowd: the group's input never closes": (
        CROWD,
        "\t\tinput.closing = closing",
        "\t\tinput.closing = false",
    ),
    "l1b w4 crowd: engagement reads the known set": (
        CROWD,
        "for userId in brain.reachable do\n\t\t\t\tengaged[userId] = simTime",
        "for userId in brain.known do\n\t\t\t\tengaged[userId] = simTime",
    ),
    "l1b w4 crowd: SetFloors drops every region": (
        CROWD,
        "\t\t\tregion = region,\n\t\t})",
        "\t\t\tregion = nil,\n\t\t})",
    ),
    "l1b w4 crowd: SetFloors keeps a region with no cells": (
        CROWD,
        "\t\t\t\tand #region.cells > 0\n",
        "\n",
    ),
    "l1b w4 crowd: AddGroup accepts an empty region": (
        CROWD,
        'finite = typeof(region) == "table" and #region > 0',
        'finite = typeof(region) == "table"',
    ),
}

# Stale Wave 1 and Wave 2 mutations whose text A's Wave 4 edits changed: same label, same rule
# re-expressed on the new code (label -> (file, new old-text, new new-text)).
L1B_W4_CROWD_REPLACED = {
    "l1b crowd: in play ignores the shooters' reach": (
        CAMP,
        "\t\treturn true\n\tend\n\tfor _, shooter in shooters do\n\t\tif flatDistance(shooter.at, root) <= shooter.reach then",
        "\t\treturn true\n\tend\n\tfor _, shooter in shooters do\n\t\tif false then",
    ),
    "l1b crowd: rise skips its seconds": (
        CAMP,
        "if now - group.since >= postureRules(def, rules).rise - TIME_EPSILON then",
        "if true then",
    ),
    "l1b crowd: the leash fires while striking": (
        CAMP,
        "elseif now - group.quietSince >= leash and not input.striking then",
        "elseif now - group.quietSince >= leash then",
    ),
    "l1b crowd: the leash is not reset by a target back in play": (
        CAMP,
        "if anyReach or input.closing then\n\t\t\tgroup.quietSince = now",
        "if input.closing then\n\t\t\tgroup.quietSince = now",
    ),
    "l1b crowd: a held group wakes on sight": (
        CAMP,
        "\tif group.held then\n\t\t-- Held until the close: neither sight nor a hit wakes it (ruling L1b-13).",
        "\tif group.held and not anySeen(group, input, rules) then\n\t\t-- Held until the close: neither sight nor a hit wakes it (ruling L1b-13).",
    ),
    "l1b crowd: a resting resident thinks": (
        CROWD,
        "\tlocal resting = brain ~= nil\n\t\tand (",
        "\tlocal resting = false\n\t\tand (",
    ),
    "l1b crowd: Damage never asks the group": (
        CROWD,
        "if group ~= nil and not CampBrain.Struck(group.brain, byUserId, simTime) then",
        "if false then",
    ),
    "l1b w2 crowd: TentActive ignores the dead residents": (
        CAMP,
        "return busy and residentsAlive > 0 and ahead",
        "return busy and ahead",
    ),
    "l1b w2 fix tail: Rouse leaves a homeward group home": (
        CAMP,
        '(group.state == "home" and reachable)',
        "false",
    ),
    "l1b w2 fix tail: Rouse lifts a homeward group with nobody in play": (
        CAMP,
        '(group.state == "home" and reachable)',
        '(group.state == "home")',
    ),
    "l1b w2 fix tail: the tent's rouse is told a player is always in play": (
        CROWD,
        "CampBrain.TentRouse(brain, simTime, next(brain.reachable) ~= nil)",
        "CampBrain.TentRouse(brain, simTime, true)",
    ),
    "l1b w2 fix tail: the tent's rouse is told nobody is ever in play": (
        CROWD,
        "CampBrain.TentRouse(brain, simTime, next(brain.reachable) ~= nil)",
        "CampBrain.TentRouse(brain, simTime, false)",
    ),
    "l1b w2 fix tail: TentRouse with nobody in play rouses": (
        CAMP,
        "if not reachable then\n\t\treturn false\n\tend\n\treturn CampBrain.Rouse(group, now, reachable)",
        "if false then\n\t\treturn false\n\tend\n\treturn CampBrain.Rouse(group, now, reachable)",
    ),
    "l1b w2 fix tail: TentRouse never lifts a homeward group": (
        CAMP,
        "return CampBrain.Rouse(group, now, reachable)",
        "return CampBrain.Rouse(group, now, false)",
    ),
    "l1b w2 fix tail: the tent's rouse is a plain Rouse": (
        CROWD,
        "if CampBrain.TentRouse(brain, simTime, next(brain.reachable) ~= nil) then",
        "if CampBrain.Rouse(brain, simTime, next(brain.reachable) ~= nil) then",
    ),
}

# Retired: their rule is the opposite of Wave 4's, so their mutant is now the shipped code. Each
# is replaced by the Wave 4 mutation named here (which undoes the rule that took its place).
L1B_W4_CROWD_RETIRED = {
    "l1b crowd: home takes damage": "l1b w4 crowd: Struck blocks a homeward group",
    "l1b crowd: home wakes on a hit": "l1b w4 crowd: home turns back on an unreachable hit",
    "l1b crowd: a hit from out of play lands": "l1b w4 crowd: a hit from out of play is blocked again",
}
L1B_W4_CROWD_MUTATIONS["l1b w4 crowd: a hit from out of play is blocked again"] = (
    CAMP,
    "\t\tgroup.struckBy[byUserId] = true\n\tend\n\treturn true",
    "\t\tgroup.struckBy[byUserId] = true\n\tend\n\treturn byUserId == 0 or group.reachable[byUserId] == true",
)
MUTATIONS.update(L1B_W4_CROWD_MUTATIONS)
# After every table that defines those labels: same labels, the new texts.
MUTATIONS.update(L1B_W4_CROWD_REPLACED)

# L1b Wave 4 fix round (docs/prompts/l1b-w4-fix-round.md), luau-engineer B (the run): R10's safe
# point by position, R11's two untested rules, R12's refused tent spawn.
L1B_W4_FIX_RUN_MUTATIONS = {
    "l1b w4 fix: a region floor judged by its busy flag": (
        FLOW,
        "local quiet = zone.region ~= nil or busy == nil or busy[index] ~= true",
        "local quiet = busy == nil or busy[index] ~= true",
    ),
    "l1b w4 fix: a homeward group is no threat": (
        FLOW,
        'return state == "rise" or state == "fight" or state == "home"',
        'return state == "rise" or state == "fight"',
    ),
    "l1b w4 fix: regionReach ignores the tent": (
        FLOW,
        '\t\tif type(config.tent) == "table" then\n\t\t\ttake(config.tent.units)\n\t\tend\n',
        "",
    ),
    "l1b w4 fix: N carries the party past the locking camp": (
        FLOW,
        "for index = from + 1, lock.floor - 1 do",
        "for index = from + 1, #plan.zones do",
    ),
    "l1b w4 fix: Fielded prices a refused tent spawn": (
        FLOW,
        "if refused ~= nil and refused[index] then",
        "if false then",
    ),
}
# R10 rewrote the line this earlier entry undid (the busy clause now sits behind the region test):
# same label, same rule (a busy floor's checkpoint taken), the new text.
L1B_W4_FIX_RUN_REPLACED = {
    "l1b: SafePoint returns a busy floor's checkpoint": (
        FLOW,
        "busy == nil or busy[index] ~= true",
        "true",
    ),
}
MUTATIONS.update(L1B_W4_FIX_RUN_MUTATIONS)
MUTATIONS.update(L1B_W4_FIX_RUN_REPLACED)

# The ui-engineer's R13 (docs/prompts/l1b-w4-fix-reports/client.md, texts verbatim): CampAim.ShotSpares.
W4_FIX_UI_MUTATIONS = {
    "l1b w4 fix ui: a refused body on the line is ignored": (
        CAMP_AIM,
        "if refusedEntry == nil then\n\t\treturn true",
        "if true then\n\t\treturn true",
    ),
    "l1b w4 fix ui: the shot ignores its pierce": (
        CAMP_AIM,
        "local hits = hitsOf(pierce)",
        "local hits = 1",
    ),
    "l1b w4 fix ui: a tie favours the shot": (
        CAMP_AIM,
        "if entry < refusedEntry then",
        "if entry <= refusedEntry then",
    ),
    "l1b w4 fix ui: awake bodies behind the refused one count": (
        CAMP_AIM,
        "if entry < refusedEntry then",
        "if true then",
    ),
    "l1b w4 fix ui: pierce is not floored": (
        CAMP_AIM,
        "math.max(1, math.floor(pierce or 0))",
        "math.max(1, pierce or 0)",
    ),
    "l1b w4 fix ui: a zero pierce hits nothing": (
        CAMP_AIM,
        "math.max(1, math.floor(pierce or 0))",
        "math.floor(pierce or 0)",
    ),
}
MUTATIONS.update(W4_FIX_UI_MUTATIONS)

# The ui-engineer's R17 (fix-diff round; docs/prompts/l1b-w4-fix-reports/client.md): a shot that
# bursts is held while a refused body lies within the burst of the stop span. ("the shot ignores
# its pierce" above was re-aimed at the same round's `hitsOf`.)
W4_FIX_UI_R17_MUTATIONS = {
    "l1b w4 fix ui r17: the stop ignores its pierce": (
        CAMP_AIM,
        "local spent = hitsOf(pierce)",
        "local spent = 1",
    ),
    "l1b w4 fix ui r17: the stop span is read unsorted": (
        CAMP_AIM,
        "\ttable.sort(takenEntries)\n",
        "",
    ),
    "l1b w4 fix ui r17: a shot with exactly its hits on the line flies on": (
        CAMP_AIM,
        "if count >= spent then",
        "if count > spent then",
    ),
    "l1b w4 fix ui r17: a passing shot's span stops short of its range": (
        CAMP_AIM,
        "else 0, range",
        "else 0, 0",
    ),
    "l1b w4 fix ui r17: a passing shot's span starts at the muzzle": (
        CAMP_AIM,
        "then takenEntries[count] else 0",
        "then 0 else 0",
    ),
    "l1b w4 fix ui r17: a tie at the burst's reach favours the shot": (
        CAMP_AIM,
        "gap * gap + off * off > reach * reach",
        "gap * gap + off * off >= reach * reach",
    ),
    "l1b w4 fix ui r17: the burst ignores the distance off the line": (
        CAMP_AIM,
        "gap * gap + off * off > reach * reach",
        "gap * gap > reach * reach",
    ),
    "l1b w4 fix ui r17: a body behind the span's start counts as inside it": (
        CAMP_AIM,
        "math.max(0, from - along, along - to)",
        "math.max(0, along - to)",
    ),
    "l1b w4 fix ui r17: a body past the span's end counts as inside it": (
        CAMP_AIM,
        "math.max(0, from - along, along - to)",
        "math.max(0, from - along)",
    ),
    "l1b w4 fix ui r17: a burst never holds the shot": (
        CAMP_AIM,
        "return gap * gap + off * off > reach * reach",
        "return true",
    ),
}
MUTATIONS.update(W4_FIX_UI_R17_MUTATIONS)

# L1b Wave 4 fix round, luau-engineer A (docs/prompts/l1b-w4-fix-reports/crowd_mutations.py, texts
# verbatim). The REPLACED table re-aims labels defined in earlier tables (same rule, new text); its
# 1c entry is the text already written above, where the retired "under side" entry was.
# New rules (R1, R2, R4, R5, R6, R7).
L1B_W4_FIX_CROWD_MUTATIONS = {
    'l1b w4 fix crowd: closing is stamped from the desired speed again (R1)': (
        CROWD,
        '\t\tenemy.closing = progressed\n',
        '\t\tenemy.closing = moving\n',
    ),
    'l1b w4 fix crowd: only a stood-down rusher finishes its blow (R2)': (
        CROWD,
        '\t\tand not (mind ~= nil and (CrowdBrain.IsStriking(mind) or mind.charge ~= nil))\n',
        '\t\tand not (brain.state == "fight" and mind ~= nil and (CrowdBrain.IsStriking(mind) or mind.charge ~= nil))\n',
    ),
    'l1b w4 fix crowd: home rests with a blow in the air (R2)': (
        CAMP,
        '\t\telseif not input.striking then\n\t\t\t-- R2:',
        '\t\telse\n\t\t\t-- R2:',
    ),
    'l1b w4 fix crowd: a stood-down rusher is healed every step at its post (R4)': (
        CROWD,
        '(homeward or (rusherDown and not body.healed))',
        '(homeward or rusherDown)',
    ),
    'l1b w4 fix crowd: the heal latch is never cleared (R4)': (
        CROWD,
        '\t\t\tif not rusherDown then\n\t\t\t\tbody.healed = false\n\t\t\tend\n',
        '',
    ),
    'l1b w4 fix crowd: only a lob has an under side (R6)': (
        VITALS,
        'held = above <= height and above >= -height',
        'held = above <= height and (shape ~= "lob" or above >= -height)',
    ),
    'l1b w4 fix crowd: the pace measure never starts again at rest (R7)': (
        CAMP,
        '\tif rested then\n\t\ttent.busySeconds = 0',
        '\tif false then\n\t\ttent.busySeconds = 0',
    ),
    'l1b w4 fix crowd: a restart at rest keeps the busy time (R7)': (
        CAMP,
        '\tif rested then\n\t\ttent.busySeconds = 0\n',
        '\tif rested then\n',
    ),
    'l1b w4 fix crowd: a restart at rest keeps the old resident count (R7)': (
        CAMP,
        '\t\ttent.residents = residentsAlive\n',
        '',
    ),
    'l1b w4 fix crowd: NewTent counts from no resident (R7)': (
        CAMP,
        '\t\tlastAt = nil,\n\t\tresidents = residents,\n',
        '\t\tlastAt = nil,\n\t\tresidents = 0,\n',
    ),
    'l1b w4 fix crowd: a homeward group does not stir its floor (R7)': (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and group.brain.state ~= "rest" then',
        'if #group.bodies > 0 and not group.brain.held and (group.brain.state == "rise" or group.brain.state == "fight") then',
    ),
    'l1b w4 fix crowd: a held group stirs its floor (R7)': (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and group.brain.state ~= "rest" then',
        'if #group.bodies > 0 and (group.brain.held or group.brain.state ~= "rest") then',
    ),
    'l1b w4 fix crowd: a dead group stirs its floor (R7)': (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and group.brain.state ~= "rest" then',
        'if not group.brain.held and group.brain.state ~= "rest" then',
    ),
    'l1b w4 fix crowd: a brute starts a lane the region cannot run (R5)': (
        BRAIN,
        '\tif floor.region == nil then\n\t\treturn true\n\tend\n\tlocal room = runway(',
        '\tif true then\n\t\treturn true\n\tend\n\tlocal room = runway(',
    ),
    "l1b w4 fix crowd: the lane's runway is not checked against the target's distance (R5)": (
        BRAIN,
        'return room >= distance - math.max(attack.width or 0, 0)',
        'return room > 0',
    ),
    'l1b w4 fix crowd: no lane ever runs on a region floor (R5)': (
        BRAIN,
        'return room >= distance - math.max(attack.width or 0, 0)',
        'return false',
    ),
}

# Stale entries of mutate.py whose text this round changed: same label, same rule, the new text.
# Update them after the tables that define them (as L1B_W4_CROWD_REPLACED is).
L1B_W4_FIX_CROWD_REPLACED = {
    'l1b crowd: a resting resident thinks': (
        CROWD,
        '\tlocal resting = brain ~= nil\n\t\tand not (',
        '\tlocal resting = false\n\t\tand not (',
    ),
    'l1b w4 crowd: a stood-down rusher keeps thinking': (
        CROWD,
        'or brain.state ~= "fight" or CampBrain.StandsDown(brain, rusher))',
        'or brain.state ~= "fight" or false)',
    ),
    'l1b w4 crowd: a stood-down rusher is not healed at its post': (
        CROWD,
        '(homeward or (rusherDown and not body.healed))',
        'homeward',
    ),
    '1c: the lob reaches under its floor': (
        VITALS,
        'held = above <= height and above >= -height',
        'held = above <= height',
    ),
}
MUTATIONS.update(L1B_W4_FIX_CROWD_MUTATIONS)
MUTATIONS.update(L1B_W4_FIX_CROWD_REPLACED)
# A's R14 (the same file, texts verbatim).
# R14 (added during the round): the foot of the climb. Each proved caught on a scratch copy.
L1B_W4_FIX_CROWD_R14_MUTATIONS = {
    "l1b w4 fix crowd: Melee has no lower bound (R14)": (
        CAMP,
        "\t\tand above >= -rules.meleeBelow\n",
        "",
    ),
    "l1b w4 fix crowd: Problems does not ask for meleeBelow (R14)": (
        CAMP,
        '\t"meleeAbove",\n\t"meleeBelow",\n}',
        '\t"meleeAbove",\n}',
    ),
    "l1b w4 fix crowd: begin starts a blow it cannot land (R14)": (
        BRAIN,
        "\t\t\treaches(body, attack, target)\n\t\t\tand laneRuns(",
        "\t\t\ttrue\n\t\t\tand laneRuns(",
    ),
    "l1b w4 fix crowd: a blow's band has no under side (R14)": (
        BRAIN,
        "\treturn above <= height and above >= -height\n",
        "\treturn above <= height\n",
    ),
    "l1b w4 fix crowd: a blow's band is judged at the root's height, not the surface stood on (R14)": (
        BRAIN,
        "local above = target.restY - target.lift - floorOf(body).centre.Y",
        "local above = target.position.Y - target.lift - floorOf(body).centre.Y",
    ),
}

# R14 made this mutate.py entry stale (Melee now names `above`): same label, the new text.
L1B_W4_FIX_CROWD_R14_REPLACED = {
    "l1b w4 crowd: Melee ignores meleeAbove": (
        CAMP,
        "\t\tand above <= rules.meleeAbove\n",
        "\t\tand true\n",
    ),
}
MUTATIONS.update(L1B_W4_FIX_CROWD_R14_MUTATIONS)
MUTATIONS.update(L1B_W4_FIX_CROWD_R14_REPLACED)
# A's R15 (the same file, texts verbatim; its FIELD line is mutate.py's own).
# R15 (added during the round): the travelling ground shapes' under side. Each proved caught.
L1B_W4_FIX_CROWD_R15_MUTATIONS = {
    "l1b w4 fix crowd: a charge has no under side (R15)": (
        FIELD,
        "(over > height or over < -height)",
        "(over > height)",
    ),
    "l1b w4 fix crowd: a ring has no under side (R15)": (
        FIELD,
        "(rise > height or rise < -height)",
        "(rise > height)",
    ),
}

# R15 made these mutate.py entries stale (the RING_HEIGHT constant and the lane's inline text):
# same label, same rule, the new text. RING_HEIGHT can then go.
L1B_W4_FIX_CROWD_R15_REPLACED = {
    "lane: it has no height": (
        FIELD,
        "if to < from or (height ~= nil and (over > height or over < -height)) then",
        "if to < from then",
    ),
    "ring: it has no height": (
        FIELD,
        "if to < from or (height ~= nil and (rise > height or rise < -height)) then",
        "if to < from then",
    ),
}
MUTATIONS.update(L1B_W4_FIX_CROWD_R15_MUTATIONS)
MUTATIONS.update(L1B_W4_FIX_CROWD_R15_REPLACED)
# A's R16 (the same file, text verbatim).
# R16 (the fix-diff round): Melee judges height on the surface last stood on. Proved caught.
L1B_W4_FIX_CROWD_R16_MUTATIONS = {
    "l1b w4 fix crowd: Melee judges height on the live root again (R16)": (
        CAMP,
        "\tlocal above = target.rest - def.floorY\n",
        "\tlocal above = root.Y - def.floorY\n",
    ),
}
MUTATIONS.update(L1B_W4_FIX_CROWD_R16_MUTATIONS)


# ------------------------------------------------------------------------------------------------
# L1c, the Chief's Clearing redone (docs/prompts/l1c-contract.md). From the luau-engineer: the pure
# WallClip (L1c-5a's camera clip, §8's ground point height rule) and the walled camp the shipped
# data builds and plans (tests_l1c.luau). WeaponService.GroundPoint and WaveService cannot be loaded
# here: the rule they call is WallClip's, mutated below.
WALL_CLIP = "src/shared/WallClip.luau"
FILES.append(WALL_CLIP)
L1C_MUTATIONS = {
    "l1c: Reach cuts a box that holds the root": (
        WALL_CLIP,
        "if usable(rect) and not holds(rect, rootX, rootY, rootZ, clip.height) then",
        "if usable(rect) then",
    ),
    "l1c: a root on the box's edge is outside it (open)": (
        WALL_CLIP,
        "return math.abs(x - rect.x) <= rect.hx and math.abs(z - rect.z) <= rect.hz and",
        "return math.abs(x - rect.x) < rect.hx and math.abs(z - rect.z) < rect.hz and",
    ),
    "l1c: Reach ignores the pad": (
        WALL_CLIP,
        "math.max(at - back / boom, 0)",
        "math.max(at, 0)",
    ),
    "l1c: Reach lets the pad go negative": (
        WALL_CLIP,
        "math.max(at - back / boom, 0)",
        "at - back / boom",
    ),
    "l1c: a boom that starts inside a box is whole": (
        WALL_CLIP,
        "if at <= 0 then 0 else",
        "if at <= 0 then 1 else",
    ),
    "l1c: a negative or NaN pad is taken as it is": (
        WALL_CLIP,
        "local back = length(clip.pad)",
        "local back = clip.pad",
    ),
    "l1c: a slab that ends before the other starts still enters": (
        WALL_CLIP,
        "\t\t\tif first > last then\n\t\t\t\treturn nil\n\t\t\tend\n",
        "",
    ),
    "l1c: a boom parallel to a slab and outside it still enters": (
        WALL_CLIP,
        "\t\t\tif start < low or start > high then\n\t\t\t\treturn nil\n\t\t\tend\n",
        "",
    ),
    "l1c: only the x slab's entry counts": (
        WALL_CLIP,
        "first = math.max(first, a)",
        "first = if axis == 1 then math.max(first, a) else first",
    ),
    "l1c: a boom that is not a number is measured": (
        WALL_CLIP,
        "\tif not (finite(fromX) and finite(fromZ) and finite(dx) and finite(dz)) then\n\t\treturn 1\n\tend\n",
        "",
    ),
    "l1c: a broken box is judged": (
        WALL_CLIP,
        "\t\tand rect.hx >= 0\n\t\tand rect.hz >= 0\n",
        "\t\tand true\n",
    ),
    "l1c: TooHigh refuses exactly the limit": (
        WALL_CLIP,
        "return targetY - floorY > rise",
        "return targetY - floorY >= rise",
    ),
    "l1c: TooHigh measured from the world's zero": (
        WALL_CLIP,
        "return targetY - floorY > rise",
        "return targetY > rise",
    ),
    "l1c: Rise is the first jump alone": (
        WALL_CLIP,
        "return movement.jumpHeight + (if airJump then movement.doubleJumpHeight else 0)",
        "return movement.jumpHeight",
    ),
    "l1c: a locking camp's groups are not held": (
        FLOW,
        "held = camp.locks == true,",
        "held = false,",
    ),
    "l1c: a closed gate stops short of a tall wall": (
        GEOMETRY,
        "table.insert(boxes, sideBox(camp, side, from, to, thickness, height))",
        "table.insert(boxes, sideBox(camp, side, from, to, thickness, math.min(height, 6)))",
    ),
}
MUTATIONS.update(L1C_MUTATIONS)

# The L1c fix round (docs/prompts/l1c-fix-round.md), from its code agent: WallClip's margin and
# height (C1, m1), the held resident's verdict (M2), a stage's own countdown (M3), and the two lists
# and the zoom cap the cases read from source text (m2, M1). The three text sources are copied into
# every mutant root so run_harness.py reads the mutated copy.
INPUT = "src/combat/client/Controllers/InputController.luau"
ABILITY = "src/combat/server/Services/AbilityService.luau"
PROJECT = "combat.project.json"
FILES += [INPUT, ABILITY, PROJECT]
L1C_FIX_MUTATIONS = {
    "l1c fix: the margin is ignored (C1)": (
        WALL_CLIP,
        "rect.hx + grow, rect.hz + grow",
        "rect.hx, rect.hz",
    ),
    "l1c fix: the root is judged inside on the grown rectangle (C1)": (
        WALL_CLIP,
        "not holds(rect, rootX, rootY, rootZ, clip.height)",
        "not holds({ x = rect.x, y = rect.y, z = rect.z, hx = rect.hx + grow, hz = rect.hz + grow }, rootX, rootY, rootZ, clip.height)",
    ),
    "l1c fix: a negative or NaN margin is taken as it is (C1)": (
        WALL_CLIP,
        "local grow = length(clip.margin)",
        "local grow = clip.margin",
    ),
    "l1c fix: the root's height is not asked (m1)": (
        WALL_CLIP,
        "and y - rect.y <= top\n",
        "and true\n",
    ),
    "l1c fix: exactly the height is outside (m1)": (
        WALL_CLIP,
        "and y - rect.y <= top",
        "and y - rect.y < top",
    ),
    "l1c fix: the height measured from the world's zero (m1)": (
        WALL_CLIP,
        "and y - rect.y <= top",
        "and y <= top",
    ),
    "l1c fix: a box's floor height is not checked (m1)": (
        WALL_CLIP,
        "\t\tand finite(rect.y)\n",
        "",
    ),
    "l1c fix: a held resident answers blocked again (M2)": (
        CROWD,
        '\t\t\treturn 0, false, "held"\n',
        '\t\t\treturn 0, false, "blocked"\n',
    ),
    "l1c fix: StrikeTally books a hit on a held resident (M2)": (
        TALLY,
        'if verdict == "gone" or verdict == "held" then',
        'if verdict == "gone" then',
    ),
    "l1c fix: the countdown ignores the stage's own (M3)": (
        FLOW,
        "\t\tthen stage.gateSeconds\n",
        "\t\tthen rules.gateSeconds\n",
    ),
    "l1c fix: Plan drops a stage's gateSeconds (M3)": (
        FLOW,
        "\t\t\tgateSeconds = stage.gateSeconds,\n",
        "",
    ),
    "l1c fix: Validate takes any gateSeconds (M3)": (
        FLOW,
        "\t\t\tproblem(`{where}: gateSeconds is {tostring(countdown)}, not a time`)\n",
        "",
    ),
    "l1c fix: a countdown of 0 waits a tick after the trigger (M3)": (
        FLOW,
        '\t\tstep = "gate"\n',
        "\t\treturn actions\n",
    ),
    "l1c fix: a skip into a countdown of 0 waits a tick (M3)": (
        FLOW,
        "\tif now >= state.gateAt then\n\t\tclose(state, actions, now)\n",
        "\tif false then\n\t\tclose(state, actions, now)\n",
    ),
    "l1c fix: the client predicts a ground ability the server does not aim (m2)": (
        INPUT,
        "{ leapSmash = true, bladeStorm = true, arrowRain = true, stormCoil = true }",
        "{ leapSmash = true, bladeStorm = true, arrowRain = true }",
    ),
    "l1c fix: the server aims a ground ability the client does not list (m2)": (
        ABILITY,
        'stormCoil = { target = "ground"',
        'stormCoil = { target = "floor"',
    ),
    "l1c fix: the place's zoom cap drifts from camera.maxZoom (M1)": (
        PROJECT,
        '"CameraMaxZoomDistance": 16',
        '"CameraMaxZoomDistance": 128',
    ),
}
MUTATIONS.update(L1C_FIX_MUTATIONS)

# The L1c second fix round (docs/prompts/l1c-fix2.md), from its code agent: a walled camp's band
# reaches its fence top (F1, F3: StageFlow.Ceiling, the trigger, WallClip's rectangle ceiling) and
# a held resident is passed over by a strike's cap, seeds and chain jumps (F4: the pure StrikePick
# WeaponService walks; WeaponService itself does not load here).
STRIKE_PICK = "src/combat/server/Services/StrikePick.luau"
FILES.append(STRIKE_PICK)
L1C_FIX2_MUTATIONS = {
    "l1c fix2: Plan gives every camp triggerHeight (F1)": (
        FLOW,
        "ceiling = StageFlow.Ceiling(camp, rules.triggerHeight),",
        "ceiling = rules.triggerHeight,",
    ),
    "l1c fix2: the trigger asks triggerHeight again (F1, F3)": (
        FLOW,
        "and above <= zone.ceiling",
        "and above <= rules.triggerHeight",
    ),
    "l1c fix2: an open camp's tall fence raises its band (F1)": (
        FLOW,
        "if camp.locks ~= true or fence == nil then",
        "if fence == nil then",
    ),
    "l1c fix2: a fence under triggerHeight lowers the band (F1)": (
        FLOW,
        "if isFinite(top) and top > triggerHeight then",
        "if isFinite(top) then",
    ),
    "l1c fix2: a fence height is not checked for a finite number (F1)": (
        FLOW,
        "if isFinite(top) and top > triggerHeight then",
        "if top == top and top > triggerHeight then",
    ),
    "l1c fix2: WallClip ignores the rectangle's ceiling (F1)": (
        WALL_CLIP,
        "local top = if ceiling ~= nil and finite(ceiling) then ceiling else height",
        "local top = height",
    ),
    "l1c fix2: WallClip takes a NaN or infinite ceiling as it is (F1)": (
        WALL_CLIP,
        "local top = if ceiling ~= nil and finite(ceiling) then ceiling else height",
        "local top = if ceiling ~= nil then ceiling else height",
    ),
    "l1c fix2: a held body spends the cap and seeds (F4)": (
        STRIKE_PICK,
        "\t\tif land(candidate) then\n\t\t\ttable.insert(seeds, candidate)",
        "\t\tif land(candidate) or true then\n\t\t\ttable.insert(seeds, candidate)",
    ),
    "l1c fix2: a chain jumps to a held body (F4)": (
        STRIKE_PICK,
        "if not taken(candidate) and land(candidate) then",
        "if not taken(candidate) and (land(candidate) or true) then",
    ),
    "l1c fix2: a chain strikes a taken body (F4)": (
        STRIKE_PICK,
        "if not taken(candidate) and land(candidate) then",
        "if land(candidate) and not taken(candidate) then",
    ),
    "l1c fix2: the cap is never spent (F4)": (
        STRIKE_PICK,
        "\t\t\tif #seeds >= cap then\n",
        "\t\t\tif false then\n",
    ),
    "l1c fix2: a cap of 0 strikes everyone (F4)": (
        STRIKE_PICK,
        "\tif not (cap > 0) then\n\t\treturn seeds, nil\n\tend\n",
        "",
    ),
    "l1c fix2: the cap is said spent at the seed count, not the candidate (F4)": (
        STRIKE_PICK,
        "return seeds, index",
        "return seeds, #seeds",
    ),
    "l1c fix2: the nudge ignores the height band (F2)": (
        FLOW,
        "\tif not (above <= zone.ceiling and above >= -rules.triggerBelow) then\n\t\treturn nil\n\tend\n",
        "",
    ),
}
MUTATIONS.update(L1C_FIX2_MUTATIONS)

# The L1c third fix round (docs/prompts/l1c-fix3.md): m3, the close nudges any root in the fenced
# rectangle onto the nearest point of `inner` (the second round's lanes are gone).
L1C_FIX3_MUTATIONS = {
    "l1c fix3: the nudge drops the fenced-rectangle (depth) test (m3)": (
        FLOW,
        "\tif not inRect(zone.trigger, position.X, position.Z) then\n\t\treturn nil\n\tend\n",
        "",
    ),
    "l1c fix3: the nudge does not hold X to inner (m3)": (
        FLOW,
        "\t\tmath.min(math.max(position.X, inner.x - inner.hx), inner.x + inner.hx),\n",
        "\t\tposition.X,\n",
    ),
    "l1c fix3: the nudge does not hold Z to inner (m3)": (
        FLOW,
        "\t\tmath.min(math.max(position.Z, inner.z - inner.hz), inner.z + inner.hz)\n",
        "\t\tposition.Z\n",
    ),
    "l1c fix3: the nudge lands on the floor's edge, not inner's (m3)": (
        FLOW,
        "\tlocal inner = zone.inner\n\treturn Vector3.new(\n",
        "\tlocal inner = zone.rect\n\treturn Vector3.new(\n",
    ),
    "l1c fix3: the nudge drops the root to the floor (m3)": (
        FLOW,
        "inner.x + inner.hx),\n\t\tposition.Y,\n",
        "inner.x + inner.hx),\n\t\tzone.floorY + 3,\n",
    ),
}
MUTATIONS.update(L1C_FIX3_MUTATIONS)

# L2 W1, the bought double jump and the lookout (docs/prompts/l2-w1-contract.md). From the
# luau-engineer: the profile's v7 step (ProfileSchema), the pure Unlocks and SecretFlow, WallClip's
# rise per player, and StageFlow's secrets lines and map rows (tests_l2.luau).
SCHEMA = "src/server/Services/ProfileSchema.luau"
UNLOCKS = "src/shared/Unlocks.luau"
SECRET_FLOW = "src/combat/server/Services/SecretFlow.luau"
FILES += [SCHEMA, UNLOCKS, SECRET_FLOW]
L2_MUTATIONS = {
    # WallClip.Rise (L2-4).
    "l2: Rise always adds the double jump": (
        WALL_CLIP,
        "(if airJump then movement.doubleJumpHeight else 0)",
        "movement.doubleJumpHeight",
    ),
    "l2: Rise never adds the double jump": (WALL_CLIP, "(if airJump then movement.doubleJumpHeight else 0)", "0"),
    # WallClip.CasterFloor and LeapApex (§11, the leap finding's F2 and F1).
    "l2 leap: over a void the floor is the feet (F2 undone)": (
        WALL_CLIP,
        "return if probed ~= nil then probed else feetY - rise",
        "return if probed ~= nil then probed else feetY",
    ),
    "l2 leap: the probed floor is ignored": (
        WALL_CLIP,
        "return if probed ~= nil then probed else feetY - rise",
        "return feetY - rise",
    ),
    "l2 leap: the height stacks on an airborne root (F1 undone)": (
        WALL_CLIP,
        "return math.max(fromY, toY + lift, floorY + standing + lift)",
        "return math.max(fromY, toY) + lift",
    ),
    "l2 leap: the caster's floor never lifts the apex": (
        WALL_CLIP,
        "return math.max(fromY, toY + lift, floorY + standing + lift)",
        "return math.max(fromY, toY + lift)",
    ),
    "l2 leap: a negative height lowers the apex": (
        WALL_CLIP,
        "local lift = if height > 0 then height else 0",
        "local lift = height",
    ),
    # ProfileSchema v7 (L2-1).
    "l2: the schema stays at v6": (SCHEMA, "local SCHEMA_VERSION = 8", "local SCHEMA_VERSION = 6"),
    "l2: the template lacks abilities": (SCHEMA, "\t\tabilities = {},\n", ""),
    "l2: there is no step from v6": (
        SCHEMA,
        "[6] = function(state: Types.PlayerState): ()",
        "[16] = function(state: Types.PlayerState): ()",
    ),
    "l2: the step shares the template's table": (
        SCHEMA,
        "\t\t\tcombat.abilities = {}\n",
        "\t\t\tcombat.abilities = PROFILE_TEMPLATE.combat.abilities\n",
    ),
    "l2: the step replaces a map that is there": (
        SCHEMA,
        "\t\tif combat.abilities == nil then\n\t\t\tcombat.abilities = {}\n\t\tend\n",
        "\t\tcombat.abilities = {}\n",
    ),
    "l2: the step forgets shortcuts": (
        SCHEMA,
        "\t\tif combat.shortcuts == nil then\n\t\t\tcombat.shortcuts = {}\n\t\tend\n",
        "",
    ),
    # Unlocks (L2-2, L2-9).
    "l2: the air jump keys on another id": (UNLOCKS, 'local AIR_JUMP = "doubleJump"', 'local AIR_JUMP = "double"'),
    "l2: the attribute's prefix drifts": (
        UNLOCKS,
        'local ATTRIBUTE_PREFIX = "Ability_"',
        'local ATTRIBUTE_PREFIX = "Ability"',
    ),
    "l2: any entry counts as owned": (
        UNLOCKS,
        "return abilities ~= nil and abilities[id] == true",
        "return abilities ~= nil and abilities[id] ~= nil",
    ),
    "l2: a key need not be sold": (
        UNLOCKS,
        "return Unlocks.Find(config, needs) ~= nil and Unlocks.Owns(abilities, needs)",
        "return Unlocks.Owns(abilities, needs)",
    ),
    "l2: a key need not be owned": (
        UNLOCKS,
        "return Unlocks.Find(config, needs) ~= nil and Unlocks.Owns(abilities, needs)",
        "return Unlocks.Find(config, needs) ~= nil",
    ),
    "l2: a fractional price sells": (
        UNLOCKS,
        "or not (valor > 0 and valor < math.huge) or valor % 1 ~= 0 then",
        "or not (valor > 0 and valor < math.huge) then",
    ),
    "l2: a price of 0 sells": (
        UNLOCKS,
        "or not (valor > 0 and valor < math.huge) or valor % 1 ~= 0 then",
        "or not (valor >= 0 and valor < math.huge) or valor % 1 ~= 0 then",
    ),
    "l2: an entry with no name sells": (
        UNLOCKS,
        '\tif type(def.name) ~= "string" or def.name == "" then\n\t\treturn "has no name"\n\tend\n',
        "",
    ),
    "l2: Find returns a malformed entry": (
        UNLOCKS,
        'if type(def) == "table" and def.id == id and Unlocks.DefProblem(def) == nil then',
        'if type(def) == "table" and def.id == id then',
    ),
    "l2: no profile reads as invalid": (UNLOCKS, 'return "unavailable"', 'return "invalid"'),
    "l2: a malformed entry may be bought": (
        UNLOCKS,
        "if def == nil or Unlocks.DefProblem(def) ~= nil then",
        "if def == nil then",
    ),
    "l2: owned is not checked": (
        UNLOCKS,
        '\tif Unlocks.Owns(combat.abilities, def.id) then\n\t\treturn "owned"\n\tend\n',
        "",
    ),
    "l2: the gate is not checked": (UNLOCKS, "\tif not gateOpen then\n", "\tif false then\n"),
    "l2: the gate is judged after the funds": (
        UNLOCKS,
        '\tif not gateOpen then\n\t\treturn "busy"\n\tend\n'
        '\tif not (combat.valor >= def.price.valor) then\n\t\treturn "insufficientFunds"\n\tend\n',
        '\tif not (combat.valor >= def.price.valor) then\n\t\treturn "insufficientFunds"\n\tend\n'
        '\tif not gateOpen then\n\t\treturn "busy"\n\tend\n',
    ),
    "l2: exactly the price is short": (
        UNLOCKS,
        "if not (combat.valor >= def.price.valor) then",
        "if not (combat.valor > def.price.valor) then",
    ),
    "l2: a NaN Valor buys": (
        UNLOCKS,
        "if not (combat.valor >= def.price.valor) then",
        "if combat.valor < def.price.valor then",
    ),
    # SecretFlow (L2-11, L2-15).
    "l2: a site stands on the block's centre": (SECRET_FLOW, "floorY = secret.y - secret.sy / 2,", "floorY = secret.y,"),
    "l2: a name alone is a reward entry": (
        SECRET_FLOW,
        "if entry == nil or (entry.valor == nil and entry.materials == nil and entry.family == nil) then",
        "if entry == nil then",
    ),
    "l2: a fractional amount pays": (
        SECRET_FLOW,
        "if finite(value) and value >= 0 and value % 1 == 0 then value else 0",
        "if finite(value) and value >= 0 then value else 0",
    ),
    "l2: a site with no key is kept": (SECRET_FLOW, '\t\t\tor type(secret.needs) ~= "string"\n', ""),
    "l2: the reach is open": (
        SECRET_FLOW,
        "<= (reach :: number) * (reach :: number)",
        "< (reach :: number) * (reach :: number)",
    ),
    "l2: the reach is measured in 3D": (
        SECRET_FLOW,
        "return dx * dx + dz * dz <= (reach :: number) * (reach :: number)",
        "return dx * dx + dz * dz + rise * rise <= (reach :: number) * (reach :: number)",
    ),
    "l2: the band's bottom is open": (SECRET_FLOW, "and rise >= -(below :: number)", "and rise > -(below :: number)"),
    "l2: the band has no bottom": (SECRET_FLOW, "\t\tand rise >= -(below :: number)\n", ""),
    "l2: the band's top is open": (SECRET_FLOW, "and rise <= (above :: number)", "and rise < (above :: number)"),
    "l2: the band has no top": (SECRET_FLOW, "\n\t\tand rise <= (above :: number)", ""),
    "l2: unusable rules are used": (
        SECRET_FLOW,
        "\tif not (finite(reach) and finite(below) and finite(above)) then\n\t\treturn false\n\tend\n",
        "",
    ),
    "l2: the key is asked before found": (
        SECRET_FLOW,
        'if found then\n\t\treturn "known"\n\telseif not hasKey then\n\t\treturn "locked"',
        'if not hasKey then\n\t\treturn "locked"\n\telseif found then\n\t\treturn "known"',
    ),
    "l2: no key is asked": (SECRET_FLOW, "elseif not hasKey then", "elseif false then"),
    "l2: the reward is asked before the key": (
        SECRET_FLOW,
        'elseif not hasKey then\n\t\treturn "locked"\n\telseif site.reward == nil then\n\t\treturn "nothing"',
        'elseif site.reward == nil then\n\t\treturn "nothing"\n\telseif not hasKey then\n\t\treturn "locked"',
    ),
    "l2: a row is found on any entry": (
        SECRET_FLOW,
        "found = found ~= nil and found[site.id] == true,",
        "found = found ~= nil and found[site.id] ~= nil,",
    ),
    # StageFlow's secrets lines and map rows (L2-13, L2-15).
    "l2: Resolve drops the secrets": (FLOW, "\t\t\tsecrets = file.secrets,\n\t\t}\n\tend", "\t\t}\n\tend"),
    "l2: Validate skips the secrets": (FLOW, "\tsecretProblems(level, layout, problem)\n", ""),
    "l2: an entry needs no name": (
        FLOW,
        'if type(entry) ~= "table" or type(entry.name) ~= "string" or entry.name == "" then',
        'if type(entry) ~= "table" then',
    ),
    "l2: a fractional amount is accepted": (
        FLOW,
        "amount ~= nil and not (isFinite(amount) and amount >= 0 and amount % 1 == 0)",
        "amount ~= nil and not (isFinite(amount) and amount >= 0)",
    ),
    "l2: a negative amount is accepted": (
        FLOW,
        "amount ~= nil and not (isFinite(amount) and amount >= 0 and amount % 1 == 0)",
        "amount ~= nil and not (isFinite(amount) and amount % 1 == 0)",
    ),
    "l2: a family of any length is accepted": (FLOW, " or #family > Unlocks.MAX_FAMILY_LENGTH", ""),
    "l2: a block that is not a table is accepted": (FLOW, '\t\tproblem("secrets is not a table")\n', ""),
    "l2: MapState passes no rows": (
        FLOW,
        "StageFlow.NodeState(map, built, leader, own, node.id, secrets)",
        "StageFlow.NodeState(map, built, leader, own, node.id)",
    ),
    "l2: a node carries no row": (
        FLOW,
        "secrets = if secrets ~= nil and levelId ~= nil then secrets[levelId] else nil,",
        "secrets = nil,",
    ),
}
MUTATIONS.update(L2_MUTATIONS)

# The L2 W1 fix round (docs/prompts/l2-w1-fix-round.md), from the server agent: the trigger measured
# to the chest's footprint (s1), the caps' one home and the empty text (s2, c5), Unlocks.Apply and
# SecretFlow.Open (s3), one rule for a repeated id (s4), WallClip.GroundFloor and the source check
# that both ground-point callers make it (c4). WeaponService is copied for that source check.
WEAPON = "src/combat/server/Services/WeaponService.luau"
FILES.append(WEAPON)
L2_FIX_MUTATIONS = {
    # s1: the footprint.
    "l2 fix s1: the trigger is measured to the chest's centre": (
        SECRET_FLOW,
        "local dx = math.max(math.abs(root.X - site.x) - site.sx / 2, 0)\n"
        "\tlocal dz = math.max(math.abs(root.Z - site.z) - site.sz / 2, 0)",
        "local dx, dz = root.X - site.x, root.Z - site.z",
    ),
    "l2 fix s1: the footprint is ignored on z": (
        SECRET_FLOW,
        "local dz = math.max(math.abs(root.Z - site.z) - site.sz / 2, 0)",
        "local dz = root.Z - site.z",
    ),
    "l2 fix s1: the footprint reaches its whole size each way": (SECRET_FLOW, "- site.sx / 2, 0)", "- site.sx, 0)"),
    "l2 fix s1: a root inside the footprint counts as far": (
        SECRET_FLOW,
        "local dx = math.max(math.abs(root.X - site.x) - site.sx / 2, 0)",
        "local dx = math.abs(root.X - site.x) - site.sx / 2",
    ),
    "l2 fix s1: a site with no footprint is kept": (SECRET_FLOW, "\t\t\t\tand finite(secret.sx)\n", ""),
    "l2 fix s1: a negative footprint is kept": (
        SECRET_FLOW,
        "\t\t\t\tand secret.sx >= 0\n\t\t\t\tand secret.sz >= 0\n",
        "",
    ),
    "l2 fix s1: a site forgets its footprint": (
        SECRET_FLOW,
        "\t\t\tsx = secret.sx,\n\t\t\tsz = secret.sz,\n",
        "\t\t\tsx = 0,\n\t\t\tsz = 0,\n",
    ),
    # s2 and c5: the caps and the empty text.
    "l2 fix s2: an empty text sells": (
        UNLOCKS,
        'if type(def.text) ~= "string" or def.text == "" then',
        'if type(def.text) ~= "string" then',
    ),
    "l2 fix s2: an id past the cap sells": (UNLOCKS, "\tif #def.id > MAX_ID_LENGTH then\n", "\tif false then\n"),
    "l2 fix s2: the ability id cap drifts": (UNLOCKS, "local MAX_ID_LENGTH = 32", "local MAX_ID_LENGTH = 31"),
    "l2 fix s2: the family id cap drifts": (UNLOCKS, "local MAX_FAMILY_LENGTH = 24", "local MAX_FAMILY_LENGTH = 25"),
    # s3: the purchase and the chest, written by pure calls.
    "l2 fix s3: Apply sells whatever the verdict (sells at 0 Valor)": (
        UNLOCKS,
        "if verdict ~= nil or state == nil or def == nil then",
        "if state == nil or def == nil then",
    ),
    "l2 fix s3: Apply takes no Valor": (UNLOCKS, "\tcombat.valor -= def.price.valor\n", ""),
    "l2 fix s3: Apply does not record the ability": (UNLOCKS, "\tUnlocks.AbilitiesOf(combat)[def.id] = true\n", ""),
    "l2 fix s3: AbilitiesOf replaces the profile's map": (
        UNLOCKS,
        "\tlocal existing = combat.abilities\n\tif existing ~= nil then\n\t\treturn existing\n\tend\n",
        "",
    ),
    "l2 fix s3: Open pays whatever the verdict": (
        SECRET_FLOW,
        'if verdict ~= "pay" or reward == nil then',
        "if reward == nil then",
    ),
    "l2 fix s3: Open pays no Valor": (SECRET_FLOW, "\tcombat.valor += reward.valor\n", ""),
    "l2 fix s3: Open does not record the secret": (SECRET_FLOW, "\tsecretsOf(combat, levelId)[site.id] = true\n", ""),
    "l2 fix s3: Open drops the family": (SECRET_FLOW, "\t\tfamiliesOf(combat)[family] = true\n", ""),
    "l2 fix s3: Open credits materials to a level with none": (
        SECRET_FLOW,
        'if material ~= "" then reward.materials else 0',
        "reward.materials",
    ),
    "l2 fix s3: Open reads found from another level": (
        SECRET_FLOW,
        "local opened = if byLevel ~= nil then byLevel[levelId] else nil",
        "local opened = if byLevel ~= nil then byLevel.forestRoad else nil",
    ),
    "l2 fix s3: a level's secrets map is replaced": (SECRET_FLOW, "\tlocal own = levels[levelId]\n", "\tlocal own = nil\n"),
    "l2 fix s3: the families map is replaced": (
        SECRET_FLOW,
        "\tlocal existing = combat.families\n\tif existing ~= nil then\n\t\treturn existing\n\tend\n",
        "",
    ),
    # s4: one rule for a repeated id.
    "l2 fix s4: Sellable keeps every repeat": (UNLOCKS, "\t\t\tif first ~= index then\n", "\t\t\tif false then\n"),
    # c4: the ground point's step 4.
    "l2 fix c4: GroundFloor owns on any attribute": (
        WALL_CLIP,
        "WallClip.Rise(movement, airJump == true)",
        "WallClip.Rise(movement, airJump ~= nil)",
    ),
    "l2 fix c4: GroundFloor ignores the probed target": (
        WALL_CLIP,
        "local floorY = if probedTarget ~= nil then probedTarget else casterFloor",
        "local floorY = casterFloor",
    ),
    "l2 fix c4: GroundFloor never refuses": (
        WALL_CLIP,
        "\tif WallClip.TooHigh(casterFloor, floorY, rise) then\n\t\treturn nil, casterFloor\n\tend\n",
        "",
    ),
    "l2 fix c4: GroundFloor measures from the feet": (
        WALL_CLIP,
        "local casterFloor = WallClip.CasterFloor(probedCaster, feetY, rise)",
        "local casterFloor = feetY",
    ),
    "l2 fix c4: the server's ground point keeps its own copy": (
        WEAPON,
        "local floorY = GroundRule.Floor(",
        "local floorY = WallClip.TooHigh(",
    ),
    "l2 fix c4: the client's ground point keeps its own copy": (
        INPUT,
        "local floorY, casterFloor = GroundRule.Floor(",
        "local floorY, casterFloor = WallClip.TooHigh(",
    ),
}
MUTATIONS.update(L2_FIX_MUTATIONS)

# The L2 W1 second fix round (docs/prompts/l2-w1-fix2.md), Minor 1: GroundRule reads the ground
# point's inputs for both callers, and the source check reads each ground-point function alone.
# The first two are the fix-diff reviewer's own probes, written against the new call sites: each
# caller going back to writing its inputs, one of them wrong.
GROUND_RULE = "src/shared/GroundRule.luau"
FILES.append(GROUND_RULE)
CLIENT_GROUND_CALL = (
    "GroundRule.Floor(\n"
    "\t\tPlayers.LocalPlayer,\n"
    "\t\tfloorHit(root, params),\n"
    "\t\troot.Y - rig.root.Size.Y * HALF - rig.humanoid.HipHeight,\n"
    "\t\tfloorHit(point + Vector3.new(0, GROUND_PROBE_LIFT, 0), params)\n"
    "\t)"
)
SERVER_GROUND_CALL = (
    "GroundRule.Floor(\n"
    "\t\tplayer,\n"
    "\t\tfloorBelow(root, params),\n"
    "\t\trootPosition.Y - standingOffset(root, humanoid),\n"
    "\t\tfloorUnder(point, params)\n"
    "\t)"
)
L2_FIX2_MUTATIONS = {
    "l2 fix2 m1: the client writes its own inputs and reads the attribute as ~= false": (
        INPUT,
        CLIENT_GROUND_CALL,
        "WallClip.GroundFloor(\n"
        "\t\tfloorHit(root, params),\n"
        "\t\troot.Y - rig.root.Size.Y * HALF - rig.humanoid.HipHeight,\n"
        "\t\tfloorHit(point + Vector3.new(0, GROUND_PROBE_LIFT, 0), params),\n"
        "\t\tTuning.Get().movement,\n"
        "\t\tPlayers.LocalPlayer:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)) ~= false\n"
        "\t)",
    ),
    "l2 fix2 m1: the server writes its own inputs with 30 studs of rise": (
        WEAPON,
        SERVER_GROUND_CALL,
        "WallClip.GroundFloor(\n"
        "\t\tfloorBelow(root, params),\n"
        "\t\trootPosition.Y - standingOffset(root, humanoid),\n"
        "\t\tfloorUnder(point, params),\n"
        "\t\t{ jumpHeight = 30, doubleJumpHeight = 0 },\n"
        "\t\tplayer:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP))\n"
        "\t)",
    ),
    "l2 fix2 m1: the server calls the rule but overrides the double jump itself": (
        WEAPON,
        "\t\tfloorUnder(point, params)\n\t)\n\tif floorY == nil then",
        "\t\tfloorUnder(point, params)\n\t)\n"
        "\tif player:GetAttribute(\"Ability_doubleJump\") ~= nil then\n\t\tfloorY = floorUnder(point, params)\n\tend\n"
        "\tif floorY == nil then",
    ),
    "l2 fix2 m1: the server's ground point is not where the check reads": (
        WEAPON,
        "function WeaponService.GroundPoint(",
        "function WeaponService.GroundPointAt(",
    ),
    "l2 fix2 m1: GroundRule owns on any attribute but false": (GROUND_RULE, ") == true", ") ~= false"),
    "l2 fix2 m1: GroundRule types its own heights": (
        GROUND_RULE,
        "Tuning.Get().movement",
        "{ jumpHeight = 30, doubleJumpHeight = 0 }",
    ),
    "l2 fix2 m1: GroundRule keeps the heights of its first call": (
        GROUND_RULE,
        "\t\tTuning.Get().movement,\n",
        "\t\tGroundRule.kept or (function()\n\t\t\tGroundRule.kept = Tuning.Get().movement\n"
        "\t\t\treturn GroundRule.kept\n\t\tend)(),\n",
    ),
    "l2 fix2 m1: GroundRule ignores the double jump": (GROUND_RULE, "GroundRule.OwnsAirJump(player)\n", "false\n"),
    "l2 fix2 m1: GroundRule reads another attribute": (
        GROUND_RULE,
        "Unlocks.Attribute(Unlocks.AIR_JUMP)",
        'Unlocks.Attribute("airJump")',
    ),
}
MUTATIONS.update(L2_FIX2_MUTATIONS)

# L2 W2, fire, the Flamethrower, the cave and the shortcut (docs/prompts/l2-w2-contract.md), from the
# luau-engineer: Unlocks' families and element keys (L2-30 to L2-32), the pure WorldReact (L2-34),
# SecretFlow's shortcuts (L2-36), Pieces' open set, Validate's react / opens / shortcuts lines and
# the element as a structural Tuning path. Proved by tests_l2w2.luau.
WORLD_REACT = "src/shared/WorldReact.luau"
FILES.append(WORLD_REACT)
L2W2_MUTATIONS = {
    # Unlocks (L2-30 to L2-32).
    "l2w2: the variant cap drifts": (UNLOCKS, "local MAX_VARIANT_LENGTH = 8", "local MAX_VARIANT_LENGTH = 9"),
    "l2w2: a starter is not owned": (
        UNLOCKS,
        "return starters[id] == true or (families ~= nil and families[id] == true)",
        "return families ~= nil and families[id] == true",
    ),
    "l2w2: any written value owns a family": (
        UNLOCKS,
        "(families ~= nil and families[id] == true)",
        "(families ~= nil and families[id] ~= nil)",
    ),
    "l2w2: the ranged starter is dropped": (
        UNLOCKS,
        "for _, family in { loadout.melee, loadout.ranged } do",
        "for _, family in { loadout.melee } do",
    ),
    "l2w2: an empty starter name counts": (UNLOCKS, 'if type(family) == "string" and family ~= "" then', 'if type(family) == "string" then'),
    "l2w2: ElementOf takes any word": (
        UNLOCKS,
        'return if type(element) == "string" then ELEMENTS[element] else nil',
        'return if type(element) == "string" then element else nil',
    ),
    # Re-aimed for L3 W1: LoadoutOf asks OwnsFamily in a line of the same text.
    "l2w2: HasElement ignores ownership": (
        UNLOCKS,
        "\t\t\tUnlocks.ElementOf(weapons, family) == element\n\t\t\tand Unlocks.OwnsFamily(families, family, starters)\n",
        "\t\t\tUnlocks.ElementOf(weapons, family) == element\n",
    ),
    "l2w2: HoldsKey asks no element": (
        UNLOCKS,
        "\n\t\tor Unlocks.HasElement(combat.families, weapons, starters, needs)",
        "",
    ),
    "l2w2: HoldsKey asks no ability": (
        UNLOCKS,
        "return Unlocks.HasKey(combat.abilities, config, needs)\n",
        "return false\n",
    ),
    "l2w2: FamilyVerdict, no profile reads as invalid": (UNLOCKS, 'verdict = "unavailable"', 'verdict = "invalid"'),
    "l2w2: FamilyVerdict, the slot is not checked": (UNLOCKS, "\t\tor def.slot ~= slot\n", ""),
    "l2w2: FamilyVerdict, the variant is not checked": (UNLOCKS, "\t\tor def.variants[variant] == nil\n", ""),
    "l2w2: FamilyVerdict, ownership is not checked": (
        UNLOCKS,
        "elseif not Unlocks.OwnsFamily(state.combat.families, family, starters) then",
        "elseif false then",
    ),
    "l2w2: FamilyVerdict, the gate is not checked": (UNLOCKS, "elseif not gateOpen then", "elseif false then"),
    # WorldReact (L2-34, L2-35).
    "l2w2: a cone sweeps a segment": (
        WORLD_REACT,
        'if shape ~= "capsule" and shape ~= "ray" then',
        'if shape ~= "capsule" and shape ~= "ray" and shape ~= "cone" then',
    ),
    "l2w2: a ray ignores where it stopped": (
        WORLD_REACT,
        'local finish = if shape == "ray" then fx.endPoint else nil',
        "local finish = nil",
    ),
    "l2w2: the direction is not made a unit": (
        WORLD_REACT,
        "finish = origin + direction / direction.Magnitude * size",
        "finish = origin + direction * size",
    ),
    "l2w2: a negative size sweeps": (WORLD_REACT, "if not (size >= 0) then", "if false then"),
    "l2w2: the width is not grown": (
        WORLD_REACT,
        "local grow = length(fx.width) / 2 + length(pad)",
        "local grow = length(pad)",
    ),
    "l2w2: the pad is not grown": (
        WORLD_REACT,
        "local grow = length(fx.width) / 2 + length(pad)",
        "local grow = length(fx.width) / 2",
    ),
    "l2w2: the whole width is grown": (
        WORLD_REACT,
        "local grow = length(fx.width) / 2 + length(pad)",
        "local grow = length(fx.width) + length(pad)",
    ),
    "l2w2: a negative length grows": (
        WORLD_REACT,
        "return if finite(value) and (value :: number) >= 0 then value :: number else 0",
        "return if finite(value) then value :: number else 0",
    ),
    "l2w2: grazing a face is no touch": (WORLD_REACT, "\t\t\tif low > high then\n", "\t\t\tif low >= high then\n"),
    "l2w2: an axis with no motion is not judged": (WORLD_REACT, "if a < min or a > max then", "if false then"),
    "l2w2: a block with no size is met": (
        WORLD_REACT,
        "\t\t\tand box.sx > 0\n\t\t\tand box.sy > 0\n",
        "\t\t\tand box.sy > 0\n",
    ),
    # Re-aimed by the second fix round: Holds checks a cell with the same first line.
    "l2w2: a block that is not finite is met": (
        WORLD_REACT,
        "\t\t\tfinite(box.x)\n\t\t\tand finite(box.y)\n\t\t\tand finite(box.z)\n\t\t\tand finite(box.sx)\n"
        "\t\t\tand finite(box.sy)\n\t\t\tand finite(box.sz)\n\t\t\tand box.sx > 0\n",
        "\t\t\ttrue\n\t\t\tand finite(box.y)\n\t\t\tand finite(box.z)\n\t\t\tand finite(box.sx)\n"
        "\t\t\tand finite(box.sy)\n\t\t\tand finite(box.sz)\n\t\t\tand box.sx > 0\n",
    ),
    "l2w2: fire takes iceHits": (WORLD_REACT, "then rules.fireHits", "then rules.iceHits"),
    "l2w2: a fractional count reacts": (WORLD_REACT, "hits >= 1 and hits % 1 == 0 then", "hits >= 1 then"),
    "l2w2: a count of 0 reacts": (WORLD_REACT, "hits >= 1 and hits % 1 == 0 then", "hits >= 0 and hits % 1 == 0 then"),
    "l2w2: the pad is a constant": (
        WORLD_REACT,
        "return length(if rules ~= nil then rules.pad else nil)",
        "return 0.5",
    ),
    "l2w2: the last strike is not enough": (WORLD_REACT, "return now, now >= need", "return now, now > need"),
    "l2w2: a need of 0 still heats": (
        WORLD_REACT,
        "if not (finite(need) and need >= 1 and need % 1 == 0) then",
        "if false then",
    ),
    "l2w2: the share is not held to 1": (WORLD_REACT, "math.clamp(heat / need, 0, 1)", "heat / need"),
    # SecretFlow's shortcuts (L2-36).
    "l2w2: a shortcut with a NaN x is kept": (SECRET_FLOW, "\t\t\t\tfinite(entry.x)\n", "\t\t\t\ttrue\n"),
    "l2w2: a shortcut with a negative size is kept": (SECRET_FLOW, "\t\t\t\tand entry.sx >= 0\n", ""),
    "l2w2: a nameless shortcut has no name": (SECRET_FLOW, "\t\t\t\telse entry.id,\n", '\t\t\t\telse "",\n'),
    "l2w2: a shortcut's X faces are open": (SECRET_FLOW, "math.abs(root.X - box.x) <= box.sx / 2", "math.abs(root.X - box.x) < box.sx / 2"),
    "l2w2: a shortcut has no height": (SECRET_FLOW, "\t\tand math.abs(root.Y - box.y) <= box.sy / 2\n", ""),
    "l2w2: a shortcut's Z faces are open": (SECRET_FLOW, "math.abs(root.Z - box.z) <= box.sz / 2", "math.abs(root.Z - box.z) < box.sz / 2"),
    "l2w2: every find is new": (SECRET_FLOW, "\tif found[id] == true then\n\t\treturn false", "\tif false then\n\t\treturn false"),
    "l2w2: a find is not written": (SECRET_FLOW, "\tfound[id] = true\n\treturn true", "\treturn true"),
    "l2w2: a level's shortcut map is replaced": (SECRET_FLOW, "local mine = shortcutsByLevel[levelId]", "local mine = nil"),
    "l2w2: FoundShortcuts counts any value": (SECRET_FLOW, "\t\t\tif found == true then\n", "\t\t\tif found ~= nil then\n"),
    "l2w2: FoundShortcuts hands out the profile's own map": (
        SECRET_FLOW,
        "\treturn open\nend",
        '\treturn if type(own) == "table" then own else open\nend',
    ),
    # Pieces' open set (L2-36) and its reactive pieces (L2-34).
    "l2w2: a found shortcut's blocks are still built": (
        GEOMETRY,
        "if opens == nil or open[opens] ~= true then",
        "if true then",
    ),
    "l2w2: every block that opens anything is left out": (
        GEOMETRY,
        "if opens == nil or open[opens] ~= true then",
        "if opens == nil then",
    ),
    "l2w2: the layout itself loses the block": (GEOMETRY, "\t\tmeasured = table.clone(layout)\n", "\t\tmeasured = layout\n"),
    "l2w2: a piece drops its react": (GEOMETRY, "\t\t\treact = block.react,\n", ""),
    "l2w2: a piece drops its opens": (GEOMETRY, "\t\t\topens = block.opens,\n", ""),
    # Validate's react, opens and shortcuts lines (L2-34, L2-36).
    "l2w2: any react word is accepted": (
        FLOW,
        "if react ~= \"fire\" then\n\t\t\t\tproblem(`{where}: react is",
        "if false then\n\t\t\t\tproblem(`{where}: react is",
    ),
    "l2w2: a reactive block may not collide": (FLOW, "\t\t\tif block.collide == false then\n", "\t\t\tif false then\n"),
    "l2w2: opens is not checked": (
        FLOW,
        'if opens ~= nil and (type(opens) ~= "string" or not ids[opens]) then',
        "if false then",
    ),
    "l2w2: a shortcut id may repeat": (FLOW, "\t\tif ids[id] then\n", "\t\tif false then\n"),
    "l2w2: a shortcut's numbers are not checked": (FLOW, "if not isFinite(entry[key]) then", "if false then"),
    "l2w2: a long shortcut id is accepted": (FLOW, "#id > Unlocks.MAX_ID_LENGTH then", "#id > 40 then"),
    "l2w2: shortcuts that are no list are accepted": (
        FLOW,
        'if shortcuts ~= nil and type(shortcuts) ~= "table" then',
        "if false then",
    ),
    # The element is structural (L2-29).
    "l2w2: the element tunes": (TUNING, '\t"^weapons%.[^.]+%.element$",\n', ""),
}
MUTATIONS.update(L2W2_MUTATIONS)

# The L2 W2 fix round (docs/prompts/l2-w2-fix-round.md), from the server agent: WorldReact's
# StrikeElement, Apply, Wants and OriginClear (s-m1, s-m2, c-M1, d-m3), Unlocks.IsElement,
# Validate's shortcut sizes (s-m3), and the source checks on Main's wiring, finish()'s abandoned skip, LevelService.React and
# aimAllowed's wall ray (d-m3). Main and LevelService are copied for those source checks.
MAIN_SERVER = "src/combat/server/Main.server.luau"
LEVEL_SERVICE = "src/combat/server/Services/LevelService.luau"
FILES += [MAIN_SERVER, LEVEL_SERVICE]
L2W2_FIX_MUTATIONS = {
    # s-m2: an ability's strike carries no element.
    "l2w2 fix: an ability's strike carries its family's element": (
        WORLD_REACT,
        "\tif ability ~= nil then\n\t\treturn nil\n\tend\n\treturn Unlocks.ElementOf(weapons, weapon)",
        "\treturn Unlocks.ElementOf(weapons, weapon)",
    ),
    "l2w2 fix: every attack carries fire": (
        WORLD_REACT,
        "\treturn Unlocks.ElementOf(weapons, weapon)\nend",
        '\treturn "fire"\nend',
    ),
    # s-m1: Apply.
    "l2w2 fix: Apply heats any element's block": (WORLD_REACT, "if entry.react ~= element or not", "if not"),
    "l2w2 fix: Apply's element is a constant": (
        WORLD_REACT,
        "if entry.react ~= element or not",
        'if entry.react ~= "fire" or not',
    ),
    "l2w2 fix: Apply heats what the strike misses": (
        WORLD_REACT,
        "if entry.react ~= element or not WorldReact.Touches(fx, entry.box, pad) then",
        "if entry.react ~= element then",
    ),
    "l2w2 fix: Apply drops the pad": (
        WORLD_REACT,
        "not WorldReact.Touches(fx, entry.box, pad) then",
        "not WorldReact.Touches(fx, entry.box, 0) then",
    ),
    "l2w2 fix: Apply does not write the heat back": (WORLD_REACT, "\t\tentry.heat = heat\n", ""),
    "l2w2 fix: Apply swaps gone and heated": (
        WORLD_REACT,
        "table.insert(if done then gone else heated, index)",
        "table.insert(if done then heated else gone, index)",
    ),
    "l2w2 fix: Apply walks the list upwards": (
        WORLD_REACT,
        "\tfor index = #entries, 1, -1 do\n",
        "\tfor index = 1, #entries do\n",
    ),
    "l2w2 fix: BoxOf swaps two sizes": (WORLD_REACT, "sx = size.X, sy = size.Y", "sx = size.Y, sy = size.X"),
    # c-M1: Wants.
    "l2w2 fix: Wants ignores the element": (
        WORLD_REACT,
        "if not Unlocks.IsElement(element) or react ~= element then",
        "if not Unlocks.IsElement(react) then",
    ),
    "l2w2 fix: Wants takes any word": (
        WORLD_REACT,
        "if not Unlocks.IsElement(element) or react ~= element then",
        "if element == nil or react ~= element then",
    ),
    "l2w2 fix: Wants ignores the heat": (WORLD_REACT, "return share < 1 and WorldReact.Touches", "return WorldReact.Touches"),
    "l2w2 fix: Wants reads no heat as burnt": (
        WORLD_REACT,
        "local share = if heat == nil then 0 elseif",
        "local share = if heat == nil then 1 elseif",
    ),
    "l2w2 fix: Wants reads a broken heat as 0": (
        WORLD_REACT,
        "elseif finite(heat) then heat :: number else 1",
        "elseif finite(heat) then heat :: number else 0",
    ),
    "l2w2 fix: Wants ignores the stream": (
        WORLD_REACT,
        "return share < 1 and WorldReact.Touches(fx, box, pad)",
        "return share < 1",
    ),
    "l2w2 fix: Wants drops the pad": (
        WORLD_REACT,
        "return share < 1 and WorldReact.Touches(fx, box, pad)",
        "return share < 1 and WorldReact.Touches(fx, box, 0)",
    ),
    "l2w2 fix: IsElement takes any word": (
        UNLOCKS,
        'return type(word) == "string" and ELEMENTS[word] ~= nil',
        'return type(word) == "string" and word ~= ""',
    ),
    # s-m3: Validate's shortcut sizes.
    "l2w2 fix: a shortcut size of 0 is accepted": (
        FLOW,
        "if isFinite(entry[key]) and entry[key] <= 0 then",
        "if isFinite(entry[key]) and entry[key] < 0 then",
    ),
    "l2w2 fix: a negative shortcut size is accepted": (
        FLOW,
        "if isFinite(entry[key]) and entry[key] <= 0 then",
        "if false then",
    ),
    "l2w2 fix: only a shortcut's sz is a size": (FLOW, 'for _, key in { "sx", "sy", "sz" } do', 'for _, key in { "sz" } do'),
    # The source checks (s-m1, s-m2, d-m3).
    "l2w2 fix: Main does not wire React": (
        MAIN_SERVER,
        "WeaponService.OnStrikeResolved(LevelService.React)",
        "-- WeaponService.OnStrikeResolved(LevelService.React) (unwired)",
    ),
    "l2w2 fix: finish tells listeners of abandoned strikes": (
        WEAPON,
        "\tif not fx.abandoned then\n\t\tlocal abilityId",
        "\tif true then\n\t\tlocal abilityId",
    ),
    "l2w2 fix: React forgets the ability": (
        LEVEL_SERVICE,
        "WorldReact.StrikeElement(config.weapons, weapon, abilityId)",
        "WorldReact.StrikeElement(config.weapons, weapon, nil)",
    ),
    "l2w2 fix: React's element is a constant": (
        LEVEL_SERVICE,
        "local element = WorldReact.StrikeElement(config.weapons, weapon, abilityId)",
        'local element = "fire"',
    ),
    "l2w2 fix: React keeps a loop of its own": (
        LEVEL_SERVICE,
        "local gone, heated = WorldReact.Apply(cells, element, fx, pad, need)",
        "local gone, heated = {}, {}\n\tfor index = #reactive, 1, -1 do\n"
        "\t\tif WorldReact.Touches(fx, cells[index].box, pad) then\n\t\t\ttable.insert(gone, index)\n"
        "\t\tend\n\tend",
    ),
    # Re-aimed by the second fix round: the rays are WorldReact.AimClear's (lineClear).
    "l2w2 fix: the aim has no wall ray": (WORLD_REACT, "\tlocal forward = cast(from, to)\n", "\tlocal forward = nil\n"),
    "l2w2 fix: the aim has no ray back": (
        WORLD_REACT,
        "local backward = if forward ~= nil then cast(to, from) else nil",
        "local backward = nil",
    ),
    "l2w2 fix: the aim ignores the verdict": (WEAPON, "\treturn clear\nend", "\treturn true\nend"),
    # d-m3: OriginClear.
    "l2w2 fix: an origin behind any wall is clear": (
        WORLD_REACT,
        "\tif forward == nil then\n\t\treturn true\n\tend\n\tif backward == nil",
        "\tif true then\n\t\treturn true\n\tend\n\tif backward == nil",
    ),
    "l2w2 fix: an origin inside a solid is clear": (
        WORLD_REACT,
        "if backward == nil or not (finite(distance)",
        "if backward == nil then\n\t\treturn true\n\tend\n\tif not (finite(distance)",
    ),
    "l2w2 fix: an endless hit is a number": (
        WORLD_REACT,
        " or not (finite(distance) and finite(forward) and finite(backward)) then",
        " then",
    ),
    "l2w2 fix: the chord ignores the hit back": (
        WORLD_REACT,
        "local chord = distance - (backward :: number) - (forward :: number)",
        "local chord = distance - (forward :: number)",
    ),
    "l2w2 fix: the wall tolerance is 0": (WORLD_REACT, "return chord <= length(tolerance)", "return chord <= 0"),
    "l2w2 fix: the wall tolerance is open": (WORLD_REACT, "return chord <= length(tolerance)", "return chord < length(tolerance)"),
    "l2w2 fix: a negative wall tolerance counts": (WORLD_REACT, "return chord <= length(tolerance)", "return chord <= tolerance"),
}
MUTATIONS.update(L2W2_FIX_MUTATIONS)

# The L2 W2 second fix round (docs/prompts/l2-w2-fix2.md): m1, a camp's own fence.thickness
# (LevelGeometry.FenceThickness, Pieces, StageFlow's trigger) and aimAllowed's chord argument (read
# by run_harness.py's source check); m2, the head led by the lag (WorldReact.LeadHead, AimClear) and
# its wiring in aimAllowed and worldHit.
L2W2_FIX2_MUTATIONS = {
    "fix2 m1: aimAllowed's chord is originPad": (
        WEAPON,
        "config.shooting.originWallChord, worldHit)",
        "config.shooting.originPad, worldHit)",
    ),
    "fix2 m1: FenceThickness ignores the camp's own": (
        GEOMETRY,
        '\tif type(own) == "number" and own > 0 and own < math.huge then\n\t\treturn own\n\tend\n\treturn default',
        "\treturn default",
    ),
    "fix2 m1: FenceThickness takes a thickness of 0": (
        GEOMETRY,
        '\tif type(own) == "number" and own > 0 and own < math.huge then\n\t\treturn own',
        '\tif type(own) == "number" and own >= 0 and own < math.huge then\n\t\treturn own',
    ),
    "fix2 m1: Pieces builds the config's thickness": (
        GEOMETRY,
        "local thickness = LevelGeometry.FenceThickness(camp, sizes.fence)",
        "local thickness = sizes.fence",
    ),
    "fix2 m1: Pieces takes any fence.thickness": (
        GEOMETRY,
        'if own ~= nil and not (type(own) == "number" and own > 0 and own < math.huge) then',
        "if false then",
    ),
    "fix2 m1: the trigger grows by the config's thickness": (
        FLOW,
        "local fence = LevelGeometry.FenceThickness(camp, rules.fenceThickness)",
        "local fence = rules.fenceThickness",
    ),
    "fix2 m2: the aim leads nowhere": (
        WEAPON,
        "local lead = WorldReact.LeadHead(anchor, motion, root.AssemblyLinearVelocity, speed, lag)",
        "local lead = anchor",
    ),
    "fix2 m2: worldHit ignores the world query": (
        WEAPON,
        "workspace:Raycast(from, to - from, worldParams())",
        "workspace:Raycast(from, to - from)",
    ),
    "fix2 m2: the lead runs at the root's full speed": (
        WORLD_REACT,
        "math.min(along, length(speed)) * length(lag)",
        "along * length(lag)",
    ),
    "fix2 m2: the lead ignores the lag": (
        WORLD_REACT,
        "math.min(along, length(speed)) * length(lag)",
        "math.min(along, length(speed))",
    ),
    "fix2 m2: an endless velocity leads": (
        WORLD_REACT,
        "\tif not (finitePoint(head) and finitePoint(motion) and finitePoint(velocity)) then\n\t\treturn head\n\tend\n\tlocal magnitude",
        "\tlocal magnitude",
    ),
    "fix2 m2: the lead is carried through walls": (
        WORLD_REACT,
        "local carried = if hit ~= nil\n\t\tthen head + reach * (math.max(hit - LEAD_STANDOFF, 0) / distance)\n\t\telse lead",
        "local carried = lead",
    ),
    "fix2 m2: AimClear never tries the lead": (
        WORLD_REACT,
        "return lineClear(carried, origin, tolerance, cast)",
        "return false",
    ),
}
MUTATIONS.update(L2W2_FIX2_MUTATIONS)

# The L2 W2 third fix round (docs/prompts/l2-w2-fix3.md): m1, the lead goes along the position
# ring's own way (PositionRing.Motion through claimSlack, read by run_harness.py's source check),
# the client's velocity only shortening it (WorldReact.LeadHead); s1, the honest gatehouse case
# through AimClear's cut-back.
L2W2_FIX3_MUTATIONS = {
    "fix3 m1: the lead goes along the client's velocity": (
        WORLD_REACT,
        "local way = motion / magnitude",
        "local way = if velocity.Magnitude > 0 then velocity / velocity.Magnitude else motion / magnitude",
    ),
    "fix3 m1: aimAllowed leads along the root's velocity": (
        WEAPON,
        "local lead = WorldReact.LeadHead(anchor, motion, root.AssemblyLinearVelocity, speed, lag)",
        "local lead = WorldReact.LeadHead(anchor, root.AssemblyLinearVelocity, root.AssemblyLinearVelocity, speed, lag)",
    ),
    "fix3 m1: claimSlack hands back the root's velocity": (
        WEAPON,
        "return math.max(pad, 0) + speed * lag, speed, lag, motion\n",
        "return math.max(pad, 0) + speed * lag, speed, lag, root.AssemblyLinearVelocity\n",
    ),
    "fix3 m1: the velocity does not shorten the lead": (
        WORLD_REACT,
        "math.min(along, length(speed)) * length(lag)",
        "length(speed) * length(lag)",
    ),
    "fix3 m1: a velocity against the way is not floored": (
        WORLD_REACT,
        "local along = math.max(velocity:Dot(way), 0)",
        "local along = velocity:Dot(way)",
    ),
    "fix3 m1: the way is taken at its length": (
        WORLD_REACT,
        "local way = motion / magnitude",
        "local way = motion",
    ),
    "fix3 m1: a way that is not finite leads": (
        WORLD_REACT,
        "finitePoint(head) and finitePoint(motion) and finitePoint(velocity)",
        "finitePoint(head) and finitePoint(velocity)",
    ),
    "fix3 m1: the ring's way is the first stretch's": (
        RING,
        "\t\t\tfastest = speed\n\t\t\tway = moved / distance\n",
        "\t\t\tfastest = speed\n\t\t\tif way.Magnitude == 0 then\n\t\t\t\tway = moved / distance\n\t\t\tend\n",
    ),
    "fix3 m1: the ring's way is not a unit": (
        RING,
        "way = moved / distance",
        "way = moved",
    ),
    "fix3 s1: a lead that meets a wall counts for nothing": (
        WORLD_REACT,
        "then head + reach * (math.max(hit - LEAD_STANDOFF, 0) / distance)",
        "then head",
    ),
    "fix3 s1: LEAD_STANDOFF = 50": (WORLD_REACT, "local LEAD_STANDOFF = 0.5", "local LEAD_STANDOFF = 50"),
}
MUTATIONS.update(L2W2_FIX3_MUTATIONS)


# L2 W3, ice, the frost hammer, deep water and the island shrine (docs/prompts/l2-w3-contract.md),
# from the luau-engineer: WorldReact's Cells, Chills and Freeze (L2-53, L2-54), Need for fire alone,
# Pieces' ice cells, Validate's ice and landing lines (L2-52, L2-58), Plan's waters, Landing and
# FallLanding (L2-58), and the source checks on LevelService's freeze, the rescue's landing in
# WaveService and Frost Quake's launcher. Proved by tests_l2w3.luau. WaveService is copied for its
# source check.
WAVE_SERVICE = "src/combat/server/Services/WaveService.luau"
FILES.append(WAVE_SERVICE)
ICE_BRANCH = '\tif element == "ice" then\n\t\tfreeze(element, fx, rules)\n\t\treturn\n\tend\n'
L2W3_MUTATIONS = {
    # Cells (L2-53).
    "l2w3: CellGrid takes a negative cell": (WORLD_REACT, "\t\t\tfinite(cell)\n\t\t\tand cell > 0\n", "\t\t\tfinite(cell)\n"),
    "l2w3: CellGrid rounds down": (
        WORLD_REACT,
        "return math.ceil(box.sx / cell), math.ceil(box.sz / cell)",
        "return math.floor(box.sx / cell), math.ceil(box.sz / cell)",
    ),
    "l2w3: CellGrid swaps the axes": (
        WORLD_REACT,
        "return math.ceil(box.sx / cell), math.ceil(box.sz / cell)",
        "return math.ceil(box.sz / cell), math.ceil(box.sx / cell)",
    ),
    "l2w3: Cells runs Z fastest": (
        WORLD_REACT,
        "\tfor j = 1, nz do\n\t\tfor i = 1, nx do\n",
        "\tfor i = 1, nx do\n\t\tfor j = 1, nz do\n",
    ),
    "l2w3: Cells starts at the block's centre": (
        WORLD_REACT,
        "local west, north = box.x - box.sx / 2, box.z - box.sz / 2",
        "local west, north = box.x, box.z",
    ),
    "l2w3: Cells is half a cell off": (WORLD_REACT, "x = west + (i - 0.5) * wide,", "x = west + i * wide,"),
    "l2w3: Cells loses the block's height": (WORLD_REACT, "\t\t\t\ty = box.y,\n", "\t\t\t\ty = 0,\n"),
    # Chills (L2-54).
    "l2w3: any shape chills": (
        WORLD_REACT,
        '\tif fx.shape ~= "arc" or fx.airborne == true then\n\t\treturn false\n\tend\n\tlocal origin, direction, arc',
        '\tif fx.airborne == true then\n\t\treturn false\n\tend\n\tlocal origin, direction, arc',
    ),
    "l2w3: the band has no floor": (
        WORLD_REACT,
        "if not (top <= origin.Y and top >= origin.Y - reachDown) then",
        "if not (top <= origin.Y) then",
    ),
    "l2w3: the band has no ceiling": (
        WORLD_REACT,
        "if not (top <= origin.Y and top >= origin.Y - reachDown) then",
        "if not (top >= origin.Y - reachDown) then",
    ),
    "l2w3: the band reads the cell's centre": (
        WORLD_REACT,
        "local top = box.y + box.sy / 2\n\tif not (top <= origin.Y",
        "local top = box.y\n\tif not (top <= origin.Y",
    ),
    "l2w3: ahead is not added": (WORLD_REACT, "if not (distance <= fx.size + ahead) then", "if not (distance <= fx.size) then"),
    "l2w3: the reach's edge is open": (
        WORLD_REACT,
        "if not (distance <= fx.size + ahead) then",
        "if not (distance < fx.size + ahead) then",
    ),
    "l2w3: 360 is not all round": (WORLD_REACT, "if sweep >= 360 or distance == 0 then", "if distance == 0 then"),
    "l2w3: a centre under the origin needs a heading": (
        WORLD_REACT,
        "if sweep >= 360 or distance == 0 then",
        "if sweep >= 360 then",
    ),
    "l2w3: the whole arc each side": (WORLD_REACT, "math.cos(math.rad(sweep / 2))", "math.cos(math.rad(sweep))"),
    "l2w3: the heading keeps its height": (
        WORLD_REACT,
        "local heading = math.sqrt(hx * hx + hz * hz)",
        "local heading = direction.Magnitude",
    ),
    "l2w3: an arc of 0 chills": (WORLD_REACT, "\tif not (sweep > 0) then\n\t\treturn false", "\tif false then\n\t\treturn false"),
    "l2w3: an endless reachDown reaches": (WORLD_REACT, "\t\t\tand finite(reachDown)\n\t\t\tand finite(ahead)\n", "\t\t\tand finite(ahead)\n"),
    # Freeze (L2-54) and Need.
    "l2w3: Freeze takes any element": (
        WORLD_REACT,
        '\tif element ~= "ice" then\n\t\treturn frozen',
        "\tif element == nil then\n\t\treturn frozen",
    ),
    "l2w3: Freeze freezes the frozen again": (
        WORLD_REACT,
        "\t\t\tnot cell.frozen\n\t\t\tand WorldReact.Chills(fx, cell.box, reachDown, ahead)\n",
        "\t\t\tWorldReact.Chills(fx, cell.box, reachDown, ahead)\n",
    ),
    "l2w3: Freeze does not write frozen": (WORLD_REACT, "\t\t\tcell.frozen = true\n", ""),
    "l2w3: Freeze drops ahead": (
        WORLD_REACT,
        "\t\t\tand WorldReact.Chills(fx, cell.box, reachDown, ahead)\n",
        "\t\t\tand WorldReact.Chills(fx, cell.box, reachDown, 0)\n",
    ),
    "l2w3: Freeze answers highest first": (
        WORLD_REACT,
        "\tfor index, cell in cells do\n\t\tif\n\t\t\tnot cell.frozen",
        "\tfor index = #cells, 1, -1 do\n\t\tlocal cell = cells[index]\n\t\tif\n\t\t\tnot cell.frozen",
    ),
    "l2w3: ice counts iceHits again": (
        WORLD_REACT,
        'local hits: any = if element == "fire" then rules.fireHits else nil',
        'local hits: any = if element == "fire" then rules.fireHits elseif element == "ice" then (rules :: any).iceHits else nil',
    ),
    # Pieces' ice cells (L2-53).
    "l2w3: no ice cells": (GEOMETRY, "\tlocal ice = sizes.ice\n\tif ice ~= nil then", "\tlocal ice = sizes.ice\n\tif false then"),
    "l2w3: every reactive block has cells": (
        GEOMETRY,
        '\t\t\tif block.react ~= "ice" then\n\t\t\t\tcontinue',
        "\t\t\tif block.react == nil then\n\t\t\t\tcontinue",
    ),
    "l2w3: nothing covers the water": (GEOMETRY, "\t\t\t\tother.y + other.sy / 2 > top\n", "\t\t\t\tfalse\n"),
    "l2w3: a cover's height is not judged": (
        GEOMETRY,
        "\t\t\t\tother.y + other.sy / 2 > top\n",
        "\t\t\t\tother.y + other.sy / 2 > -math.huge\n",
    ),
    # Re-aimed by the fix round's d-m1 (a cover holds the WHOLE cell): a cover exactly the cell's
    # footprint no longer covers it.
    "l2w3: a cover's edge is open": (
        GEOMETRY,
        "and math.abs(cell.x - other.x) + cell.sx / 2 <= other.sx / 2 + SEAM",
        "and math.abs(cell.x - other.x) + cell.sx / 2 < other.sx / 2 - SEAM",
    ),
    "l2w3: secrets cover nothing": (
        GEOMETRY,
        "\t\tfor _, secret in listOf(layout.secrets) do\n\t\t\ttable.insert(covers, LevelGeometry.SecretBox(secret))\n\t\tend\n",
        "",
    ),
    "l2w3: a block nothing meets covers": (
        GEOMETRY,
        "\t\t\tif blocks[index].collide ~= false then\n\t\t\t\ttable.insert(covers, box)",
        "\t\t\tif true then\n\t\t\t\ttable.insert(covers, box)",
    ),
    "l2w3: the ice's top ignores lift": (
        GEOMETRY,
        "y = top + ice.lift - ice.thickness / 2,",
        "y = top - ice.thickness / 2,",
    ),
    "l2w3: the ice is the water's depth": (GEOMETRY, "\t\t\t\t\tsy = ice.thickness,\n", "\t\t\t\t\tsy = cell.sy,\n"),
    "l2w3: an ice piece collides": (
        GEOMETRY,
        '\t\t\t\tlook = "ice",\n\t\t\t\tcollide = false,',
        '\t\t\t\tlook = "ice",\n\t\t\t\tcollide = true,',
    ),
    "l2w3: ice names skip no covered cell": (GEOMETRY, "name = `Ice_{name}_{k}`,", "name = `Ice_{name}_{#pieces + 1}`,"),
    # Validate's ice and landing lines (L2-52, L2-58).
    "l2w3: ice takes the fire lines": (
        FLOW,
        '\t\tif react == "ice" then\n\t\t\t-- L2-52',
        "\t\tif false then\n\t\t\t-- L2-52",
    ),
    "l2w3: an ice block may collide": (
        FLOW,
        "\t\t\tif block.collide ~= false then\n\t\t\t\tproblem(`{where} is ice and collides`)",
        "\t\t\tif false then\n\t\t\t\tproblem(`{where} is ice and collides`)",
    ),
    "l2w3: an ice block may open a shortcut": (
        FLOW,
        "\t\t\tif opens ~= nil then\n\t\t\t\tproblem(`{where} is ice and opens",
        "\t\t\tif false then\n\t\t\t\tproblem(`{where} is ice and opens",
    ),
    # Re-aimed by the fix round's Q3: a landing on any block a body falls through.
    "l2w3: any block may have a landing": (
        FLOW,
        "\t\t\tif block.collide ~= false then\n\t\t\t\tproblem(`{where} has a landing and collides`)",
        "\t\t\tif false then\n\t\t\t\tproblem(`{where} has a landing and collides`)",
    ),
    "l2w3: a landing's numbers are not checked": (FLOW, "\t\t\t\t\tif not isFinite(landing[key]) then", "\t\t\t\t\tif false then"),
    "l2w3: a landing that is no table passes": (
        FLOW,
        '\t\t\tif type(landing) ~= "table" then\n\t\t\t\tproblem(`{where}: landing is {tostring(landing)}, not a point`)\n\t\t\telse',
        '\t\t\tif false then\n\t\t\telseif type(landing) == "table" then',
    ),
    # Plan's waters, Landing, FallLanding (L2-58).
    "l2w3: Plan has no waters": (FLOW, "\t\tif block.collide == false and landing ~= nil then", "\t\tif false then"),
    "l2w3: any block's landing is a water": (
        FLOW,
        "\t\tif block.collide == false and landing ~= nil then",
        "\t\tif landing ~= nil then",
    ),
    "l2w3: Landing ignores the margin": (
        FLOW,
        "if inRect(grown(water.rect, grow), point.X, point.Z) then",
        "if inRect(water.rect, point.X, point.Z) then",
    ),
    "l2w3: Landing takes a negative margin": (
        FLOW,
        "local grow = if isFinite(margin) and margin >= 0 then margin else 0",
        "local grow = if isFinite(margin) then margin else 0",
    ),
    "l2w3: Landing takes a margin that is not finite": (
        FLOW,
        "local grow = if isFinite(margin) and margin >= 0 then margin else 0",
        "local grow = if margin >= 0 then margin else 0",
    ),
    "l2w3: Landing takes the last water": (
        FLOW,
        "\tfor _, water in plan.waters do\n",
        "\tfor index = #plan.waters, 1, -1 do\n\t\tlocal water = plan.waters[index]\n",
    ),
    "l2w3: FallLanding lands in a closed camp": (
        FLOW,
        '\tif step == "fight" or step == "breather" then\n\t\treturn nil\n\tend\n\treturn StageFlow.Landing',
        "\treturn StageFlow.Landing",
    ),
    "l2w3: FallLanding lands in a breather": (
        FLOW,
        '\tif step == "fight" or step == "breather" then\n\t\treturn nil\n\tend\n\treturn StageFlow.Landing',
        '\tif step == "fight" then\n\t\treturn nil\n\tend\n\treturn StageFlow.Landing',
    ),
    # The lines that act on them (source checks, tests_l2w3.luau's wiringTests).
    "l2w3: React sends ice down the fire path": (LEVEL_SERVICE, ICE_BRANCH, ""),
    "l2w3: freeze asks no Freeze": (
        LEVEL_SERVICE,
        "WorldReact.Freeze(cells, element, fx, reachDown, ahead, held, sink)",
        "WorldReact.Freeze(cells, element, fx, reachDown, 0, held, sink)",
    ),
    # Re-aimed by the fix round's s-m1: a cell shows as WorldReact.IceLook says, through showIce.
    "l2w3: a frozen cell does not collide": (LEVEL_SERVICE, "\tpart.CanCollide = look.collide\n", "\tpart.CanCollide = false\n"),
    "l2w3: a frozen cell is not met by rays": (LEVEL_SERVICE, "\tpart.CanQuery = look.collide\n", "\tpart.CanQuery = false\n"),
    "l2w3: a frozen cell keeps Ice false": (
        WORLD_REACT,
        "collide = true, shadow = true, frozen = true }",
        "collide = true, shadow = true, frozen = false }",
    ),
    "l2w3: nobody hears a freeze": (
        LEVEL_SERVICE,
        "box = entry.cell.box }\n\t\tfor _, listener in state.reactedListeners do\n\t\t\tlistener(event)\n",
        "box = entry.cell.box }\n\t\tfor _, listener in state.reactedListeners do\n\t\t\tlocal _ = listener\n",
    ),
    "l2w3: the rescue ignores the landing": (
        WAVE_SERVICE,
        "local landing = StageFlow.FallLanding(plan, flow, root.Position, stood, rescue.outside)",
        "local landing = nil",
    ),
    "l2w3: the rescue's margin is rescue.below": (
        WAVE_SERVICE,
        "StageFlow.FallLanding(plan, flow, root.Position, stood, rescue.outside)",
        "StageFlow.FallLanding(plan, flow, root.Position, stood, rescue.below)",
    ),
    "l2w3: Frost Quake has no launcher": (
        ABILITY,
        "MECHANICS.frostQuake = MECHANICS.earthquake",
        "MECHANICS.frostQuake = MECHANICS.whirlwind",
    ),
}
MUTATIONS.update(L2W3_MUTATIONS)


# The L2 W3 fix round (docs/prompts/l2-w3-fix-round.md), from the luau-engineer: the pure answers
# moved out of the services (WorldReact's SwingStrike, IceReach, IceLook, Reactive, ICE_ATTRIBUTE;
# LevelGeometry's SizesOf, IceOf, Overlap; StageFlow's Landing by where the body stood) and the
# lines that apply them (tests_l2w3.luau's wiringTests read those as text). One mutant at least
# for each of the server review's s-m1 lines and the data review's d-m5 reads. The client's three
# copies of a swing's strike (c-m3's client half) are read as text too, so their files are copied.
FROST_FX = "src/combat/client/Controllers/FrostFx.luau"
FEEDBACK = "src/combat/client/Controllers/FeedbackController.luau"
FILES += [FROST_FX, FEEDBACK]
L2W3_FIX_MUTATIONS = {
    # c-m3, client half: each copy builds its strike by hand again (a step of its own, a pad).
    "l2w3 fix c-m3: the frost ghost's own step": (
        FROST_FX,
        "\t\tswing.variant,\n\t\tswing.step,\n\t\tswing.origin,\n",
        "\t\tswing.variant,\n\t\t1,\n\t\tswing.origin,\n",
    ),
    "l2w3 fix c-m3: the phone's own step": (
        INPUT,
        "local strike = WorldReact.SwingStrike(variant, step, origin, heading, airborne)",
        "local strike = WorldReact.SwingStrike(variant, 1, origin, heading, airborne)",
    ),
    "l2w3 fix c-m3: the early hitbox's own step": (
        FEEDBACK,
        "WorldReact.SwingStrike(variant, swing.step, swing.origin, swing.heading, swing.airSwing)",
        "WorldReact.SwingStrike(variant, 1, swing.origin, swing.heading, swing.airSwing)",
    ),
    "l2w3 fix c-m3: the early hitbox pads its size": (
        FEEDBACK,
        "\t\tsize = predicted.size,\n",
        "\t\tsize = predicted.size + variant.pad,\n",
    ),
    # s-m1: the five lines that applied the ice unharnessed, as moved.
    "l2w3 fix s-m1: SizesOf builds no ice": (GEOMETRY, "\t\tice = ice,\n", "\t\tice = nil,\n"),
    "l2w3 fix s-m1: sizesOf drops SizesOf's config": (
        LEVEL_SERVICE,
        "local sizes, iceRefused = LevelGeometry.SizesOf(expeditions, rules)",
        "local sizes, iceRefused = LevelGeometry.SizesOf(expeditions, nil)",
    ),
    "l2w3 fix s-m1: IceOf takes a lift that is not finite": (
        GEOMETRY,
        '\t\tand type(lift) == "number"\n\t\tand isFinite(lift)\n',
        '\t\tand type(lift) == "number"\n',
    ),
    "l2w3 fix s-m1: IceOf refuses nothing": (GEOMETRY, "\treturn nil, true\nend", "\treturn nil, false\nend"),
    "l2w3 fix s-m1: React's guard forgets the ice": (
        LEVEL_SERVICE,
        "\tlocal config: any = Tuning.Get()\n\tlocal element = WorldReact.StrikeElement(",
        "\tif #state.reactive == 0 then\n\t\treturn\n\tend\n\tlocal config: any = Tuning.Get()\n\tlocal element = WorldReact.StrikeElement(",
    ),
    "l2w3 fix s-m1: a cell is built with no Ice attribute": (
        LEVEL_SERVICE,
        "\tpart:SetAttribute(WorldReact.ICE_ATTRIBUTE, look.frozen)\n",
        "",
    ),
    "l2w3 fix s-m1: water is built frozen": (
        LEVEL_SERVICE,
        "showIce(part, WorldReact.IceLook(false, shown))",
        "showIce(part, WorldReact.IceLook(true, shown))",
    ),
    "l2w3 fix s-m1: a frozen cell stays invisible (showIce)": (
        LEVEL_SERVICE,
        "\tpart.Transparency = look.transparency\n",
        "\tpart.Transparency = 1\n",
    ),
    "l2w3 fix s-m1: a frozen cell stays invisible (IceLook)": (
        WORLD_REACT,
        "return { transparency = shown, collide = true",
        "return { transparency = 1, collide = true",
    ),
    "l2w3 fix s-m1: water shows (IceLook)": (
        WORLD_REACT,
        "return { transparency = 1, collide = false",
        "return { transparency = shown, collide = false",
    ),
    "l2w3 fix s-m1: water is met (IceLook)": (
        WORLD_REACT,
        "transparency = 1, collide = false, shadow = false",
        "transparency = 1, collide = true, shadow = false",
    ),
    "l2w3 fix s-m1: ice blocks are reactive (Reactive)": (
        WORLD_REACT,
        'return react ~= nil and react ~= "ice"',
        "return react ~= nil",
    ),
    "l2w3 fix s-m1: ice blocks are reactive (construct)": (
        LEVEL_SERVICE,
        'if react ~= nil and piece.role == "block" and WorldReact.Reactive(react) then',
        'if react ~= nil and piece.role == "block" then',
    ),
    "l2w3 fix s-s3: the attribute is renamed": (
        WORLD_REACT,
        'WorldReact.ICE_ATTRIBUTE = "Ice"',
        'WorldReact.ICE_ATTRIBUTE = "Frozen"',
    ),
    # d-m5: the two reads.
    "l2w3 fix d-m5: IceReach swaps them": (WORLD_REACT, "\treturn reachDown, ahead\nend", "\treturn ahead, reachDown\nend"),
    "l2w3 fix d-m5: IceReach reads lift for ahead": (
        WORLD_REACT,
        'local ahead: number? = if type(ice.ahead) == "number" then ice.ahead else nil',
        'local ahead: number? = if type(ice.lift) == "number" then ice.lift else nil',
    ),
    "l2w3 fix d-m5: IceReach reads ahead for reachDown": (
        WORLD_REACT,
        'local reachDown: number? = if type(ice.reachDown) == "number" then ice.reachDown else nil',
        'local reachDown: number? = if type(ice.ahead) == "number" then ice.ahead else nil',
    ),
    "l2w3 fix d-m5: freeze swaps the reads": (
        LEVEL_SERVICE,
        "WorldReact.Freeze(cells, element, fx, reachDown, ahead, held, sink)",
        "WorldReact.Freeze(cells, element, fx, ahead, reachDown, held, sink)",
    ),
    "l2w3 fix d-m5: freeze reads the wrong table": (
        LEVEL_SERVICE,
        "WorldReact.IceReach(if rules ~= nil then rules.ice else nil)",
        "WorldReact.IceReach(if rules ~= nil then rules else nil)",
    ),
    # Q2: the grip.
    "l2w3 fix Q2: frozen ice slides": (LEVEL_SERVICE, "\t\t\t\tpart.CustomPhysicalProperties = grip\n", ""),
    "l2w3 fix Q2: the grip is the ice look's": (
        LEVEL_SERVICE,
        "local look = if looks ~= nil then looks[CONST.GRIP_LOOK] else nil",
        "local look = if looks ~= nil then looks.ice else nil",
    ),
    "l2w3 fix Q2: GRIP_LOOK names the ice": (LEVEL_SERVICE, 'GRIP_LOOK = "ground",', 'GRIP_LOOK = "ice",'),
    # c-m3: one strike for a swing.
    "l2w3 fix c-m3: SwingStrike pads the size": (WORLD_REACT, "size = variant.range,", "size = variant.range + variant.pad,"),
    "l2w3 fix c-m3: the finisher on every step": (
        WORLD_REACT,
        "if chain ~= nil and step == #chain and variant.finisherArcDegrees ~= nil then",
        "if chain ~= nil and variant.finisherArcDegrees ~= nil then",
    ),
    "l2w3 fix c-m3: never the finisher": (
        WORLD_REACT,
        "if chain ~= nil and step == #chain and variant.finisherArcDegrees ~= nil then",
        "if false then",
    ),
    "l2w3 fix c-m3: SwingStrike drops the width": (WORLD_REACT, "\t\twidth = variant.width,\n", "\t\twidth = nil,\n"),
    "l2w3 fix c-m3: SwingStrike points at its origin": (WORLD_REACT, "\t\tdirection = heading,\n", "\t\tdirection = origin,\n"),
    "l2w3 fix c-m3: resolveMelee builds its own step": (
        WEAPON,
        "local swing = WorldReact.SwingStrike(variant, step, origin, heading, airSwing)",
        "local swing = WorldReact.SwingStrike(variant, 1, origin, heading, airSwing)",
    ),
    "l2w3 fix c-m3: finish() sends a padded size": (WEAPON, "\t\tsize = swing.size,\n", "\t\tsize = range + variant.pad,\n"),
    "l2w3 fix c-m3: the candidates sweep their own arc": (
        WEAPON,
        "local arcDegrees = swing.arcDegrees\n",
        "local arcDegrees = variant.arcDegrees\n",
    ),
    # s-s2: overlapping ice.
    "l2w3 fix s-s2: Overlap counts touching": (
        GEOMETRY,
        "return math.abs(a.x - b.x) < (a.sx + b.sx) / 2 - SEAM",
        "return math.abs(a.x - b.x) <= (a.sx + b.sx) / 2 + SEAM",
    ),
    "l2w3 fix s-s2: Overlap ignores Z": (
        GEOMETRY,
        "\t\tand math.abs(a.z - b.z) < (a.sz + b.sz) / 2 - SEAM\n",
        "\t\tand true\n",
    ),
    "l2w3 fix s-s2: ice blocks may overlap": (FLOW, "if LevelGeometry.Overlap(other.block, block) then", "if false then"),
    "l2w3 fix s-s2: any blocks may overlap": (
        FLOW,
        '\t\tif type(block) ~= "table" or block.react ~= "ice" then\n\t\t\tcontinue\n\t\tend\n\t\tif\n',
        '\t\tif type(block) ~= "table" then\n\t\t\tcontinue\n\t\tend\n\t\tif\n',
    ),
    # d-m1: a cover holds the whole cell.
    "l2w3 fix d-m1: a cover holding the centre covers (x)": (
        GEOMETRY,
        "and math.abs(cell.x - other.x) + cell.sx / 2 <= other.sx / 2 + SEAM",
        "and math.abs(cell.x - other.x) <= other.sx / 2",
    ),
    "l2w3 fix d-m1: a cover holding the centre covers (z)": (
        GEOMETRY,
        "and math.abs(cell.z - other.z) + cell.sz / 2 <= other.sz / 2 + SEAM",
        "and math.abs(cell.z - other.z) <= other.sz / 2",
    ),
    # s-M1 and Q3: the landing by where the body stood, on any deep water.
    "l2w3 fix s-M1: Landing ignores where the body stood": (
        FLOW,
        "return waterAt(plan, stood, grow) or waterAt(plan, position, grow)",
        "return waterAt(plan, position, grow)",
    ),
    "l2w3 fix s-M1: Landing ignores where the body is": (
        FLOW,
        "return waterAt(plan, stood, grow) or waterAt(plan, position, grow)",
        "return waterAt(plan, stood, grow)",
    ),
    "l2w3 fix s-M1: where the body is decides first": (
        FLOW,
        "return waterAt(plan, stood, grow) or waterAt(plan, position, grow)",
        "return waterAt(plan, position, grow) or waterAt(plan, stood, grow)",
    ),
    "l2w3 fix s-M1: FallLanding drops where it stood": (
        FLOW,
        "return StageFlow.Landing(plan, position, stood, margin)",
        "return StageFlow.Landing(plan, position, nil, margin)",
    ),
    "l2w3 fix s-M1: the rescue forgets where the body stood": (
        WAVE_SERVICE,
        "local stood = WeaponService.LastGround(player)",
        "local stood = nil",
    ),
    "l2w3 fix s-M1: the air tracking never records where it stood": (WEAPON, "\t\t\tshooter.stood = position\n", ""),
    "l2w3 fix s-M1: an airborne root counts as standing": (
        WEAPON,
        "if footing ~= nil and not SwingGate.IsAir(position.Y - footing, offset) then",
        "if footing ~= nil then",
    ),
    "l2w3 fix s-M1: a server move keeps the stood point": (
        WEAPON,
        "PositionRing.Clear(shooter.history)\n\t\tshooter.stood = nil\n",
        "PositionRing.Clear(shooter.history)\n",
    ),
    "l2w3 fix s-M1: a fresh body keeps the stood point": (
        WEAPON,
        "\tshooter.stood = nil\n\tshooter.fall = nil\n\tshooter.airSwing = SwingGate.New()",
        "\tshooter.fall = nil\n\tshooter.airSwing = SwingGate.New()",
    ),
    "l2w3 fix s-M1: LastGround answers nothing": (
        WEAPON,
        "return if shooter ~= nil then shooter.stood else nil",
        "return nil",
    ),
    "l2w3 fix Q3: only ice's landing is a water": (
        FLOW,
        "\t\tif block.collide == false and landing ~= nil then",
        '\t\tif block.collide == false and block.react == "ice" and landing ~= nil then',
    ),
}
MUTATIONS.update(L2W3_FIX_MUTATIONS)


# The L2 W3 second fix round (docs/prompts/l2-w3-fix2.md). Q5: an air swing freezes nothing and no
# cell freezes while a body stands in it (WorldReact's SwingStrike `airborne`, Chills, BodyBox,
# Holds, Freeze's bodies, IceSink; the lines on both sides that hand them the verdict and the
# bodies). Q6: the cells inset from their water's faces (LevelGeometry's IceOf and iceCells).
# Proved by tests_l2w3.luau's bodyTests, insetTests, realTests and fix2WiringTests. ReactFx is read
# as text for the ghost's and the bodies' lines, so it is copied.
REACT_FX = "src/combat/client/Controllers/ReactFx.luau"
FILES.append(REACT_FX)
BODY_FINITE = (
    "\t\t\tfinite(body.x)\n\t\t\tand finite(body.y)\n\t\t\tand finite(body.z)\n\t\t\tand finite(body.sx)\n"
    "\t\t\tand finite(body.sy)\n\t\t\tand finite(body.sz)\n\t\t\tand math.abs(body.x"
)
CELL_FINITE = (
    "\tif\n\t\tnot (\n\t\t\tfinite(box.x)\n\t\t\tand finite(box.y)\n\t\t\tand finite(box.z)\n\t\t\tand finite(box.sx)\n"
    "\t\t\tand finite(box.sy)\n\t\t\tand finite(box.sz)\n\t\t)\n\tthen\n\t\treturn false\n\tend\n\tlocal top = box.y + box.sy / 2\n"
    "\tlocal bottom"
)
INSET_WEST = "local west = x0 + (if openWest then ice.inset else 0)"
L2W3_FIX2_MUTATIONS = {
    # Q5, the pure rules.
    "l2w3 fix2 Q5: Chills takes an air swing": (
        WORLD_REACT,
        '\tif fx.shape ~= "arc" or fx.airborne == true then',
        '\tif fx.shape ~= "arc" then',
    ),
    "l2w3 fix2 Q5: SwingStrike drops the air verdict": (WORLD_REACT, "\t\tairborne = airborne,\n", "\t\tairborne = false,\n"),
    "l2w3 fix2 Q5: Freeze ignores the bodies": (
        WORLD_REACT,
        "\t\t\tand not WorldReact.Holds(cell.box, bodies, sink)\n",
        "",
    ),
    "l2w3 fix2 Q5: Holds ignores the sink": (WORLD_REACT, "local below = top - (sink :: number)", "local below = top"),
    "l2w3 fix2 Q5: Holds judges bodies with a sink under 0": (
        WORLD_REACT,
        "if bodies == nil or not (finite(sink) and (sink :: number) >= 0) then",
        "if bodies == nil or sink == nil then",
    ),
    "l2w3 fix2 Q5: Holds counts touching in plan (x)": (
        WORLD_REACT,
        "and math.abs(body.x - box.x) < (body.sx + box.sx) / 2",
        "and math.abs(body.x - box.x) <= (body.sx + box.sx) / 2",
    ),
    "l2w3 fix2 Q5: Holds counts touching in plan (z)": (
        WORLD_REACT,
        "and math.abs(body.z - box.z) < (body.sz + box.sz) / 2",
        "and math.abs(body.z - box.z) <= (body.sz + box.sz) / 2",
    ),
    "l2w3 fix2 Q5: Holds ignores the feet": (WORLD_REACT, "\t\t\tand body.y - body.sy / 2 < below\n", ""),
    "l2w3 fix2 Q5: Holds ignores the cell's bottom": (WORLD_REACT, "\t\t\tand body.y + body.sy / 2 > bottom\n", ""),
    "l2w3 fix2 Q5: Holds takes a body that is not finite": (WORLD_REACT, BODY_FINITE, "\t\t\tmath.abs(body.x"),
    "l2w3 fix2 Q5: Holds takes a cell that is not finite": (
        WORLD_REACT,
        CELL_FINITE,
        "\tlocal top = box.y + box.sy / 2\n\tlocal bottom",
    ),
    "l2w3 fix2 Q5: BodyBox's feet at the hip": (
        WORLD_REACT,
        "local stand = hipHeight + size.Y / 2",
        "local stand = hipHeight",
    ),
    "l2w3 fix2 Q5: BodyBox ignores the turn": (
        WORLD_REACT,
        "sx = 2 * (rx * halfX + rz * halfZ),",
        "sx = 2 * halfX,",
    ),
    "l2w3 fix2 Q5: BodyBox reads no flat part as facing +Z": (
        WORLD_REACT,
        "local rx = if flat > FLAT_MIN then math.abs(right.X) / flat else 1",
        "local rx = if flat > FLAT_MIN then math.abs(right.X) / flat else 0",
    ),
    "l2w3 fix2 Q5: IceSink takes a sink under 0": (WORLD_REACT, "if finite(sink) and sink >= 0 then", "if finite(sink) then"),
    "l2w3 fix2 Q5: IceSink takes one that is not finite": (
        WORLD_REACT,
        "if finite(sink) and sink >= 0 then",
        'if type(sink) == "number" and sink >= 0 then',
    ),
    "l2w3 fix2 Q5: IceSink reads lift": (
        WORLD_REACT,
        'local sink: any = if type(ice) == "table" then ice.sink else nil',
        'local sink: any = if type(ice) == "table" then ice.lift else nil',
    ),
    # Q5, the lines that hand them the verdict and the bodies (read as text).
    "l2w3 fix2 Q5: resolveMelee calls every swing grounded": (
        WEAPON,
        "local swing = WorldReact.SwingStrike(variant, step, origin, heading, airSwing)",
        "local swing = WorldReact.SwingStrike(variant, step, origin, heading, false)",
    ),
    "l2w3 fix2 Q5: OnAttack hands resolveMelee no verdict": (
        WEAPON,
        "\t\t\tdirection,\n\t\t\tairSwing\n\t\t)",
        "\t\t\tdirection,\n\t\t\tfalse\n\t\t)",
    ),
    "l2w3 fix2 Q5: finish() drops the verdict": (WEAPON, "\t\tairborne = swing.airborne,\n", ""),
    "l2w3 fix2 Q5: freeze hands no bodies": (
        LEVEL_SERVICE,
        "local held = if sink ~= nil then bodies() else nil",
        "local held = nil",
    ),
    "l2w3 fix2 Q5: freeze reads no sink": (
        LEVEL_SERVICE,
        "local sink = WorldReact.IceSink(if rules ~= nil then rules.ice else nil)",
        "local sink = WorldReact.IceSink(nil)",
    ),
    "l2w3 fix2 Q5: the server's bodies turn by the look": (
        LEVEL_SERVICE,
        "root.CFrame.RightVector,",
        "root.CFrame.LookVector,",
    ),
    "l2w3 fix2 Q5: the server's bodies are only the first player's": (
        LEVEL_SERVICE,
        "\tfor _, player in Players:GetPlayers() do\n\t\tlocal character = player.Character",
        "\tfor _, player in { Players:GetPlayers()[1] } do\n\t\tlocal character = player.Character",
    ),
    "l2w3 fix2 Q5: the ghost ignores the bodies": (
        REACT_FX,
        "if not WorldReact.Holds(box, around, sink) then",
        "if true then",
    ),
    "l2w3 fix2 Q5: the ghost judges no sink": (REACT_FX, "local sink = ReactFx.IceSink()", "local sink = nil"),
    "l2w3 fix2 Q5: the client's bodies turn by the look": (REACT_FX, "root.CFrame.RightVector,", "root.CFrame.LookVector,"),
    "l2w3 fix2 Q5: ReactFx reads its own sink": (
        REACT_FX,
        "return WorldReact.IceSink(if react ~= nil then react.ice else nil)",
        "return 0",
    ),
    "l2w3 fix2 Q5: the phone ignores the bodies": (
        INPUT,
        "return not WorldReact.Holds(box, around, ReactFx.IceSink())",
        "return true",
    ),
    "l2w3 fix2 Q5: the predicted swing's verdict is the Humanoid's": (
        INPUT,
        "airSwing = swingAirborne,",
        "airSwing = airborne,",
    ),
    "l2w3 fix2 Q5: the phone's strike is an air swing": (
        INPUT,
        "local strike = WorldReact.SwingStrike(variant, step, origin, heading, airborne)",
        "local strike = WorldReact.SwingStrike(variant, step, origin, heading, true)",
    ),
    "l2w3 fix2 Q5: the ghost's strike is always grounded": (FROST_FX, "\t\tswing.airSwing\n\t)", "\t\tfalse\n\t)"),
    "l2w3 fix2 Q5: the early hitbox's strike is always grounded": (
        FEEDBACK,
        "swing.heading, swing.airSwing)",
        "swing.heading, false)",
    ),
    # Q6.
    "l2w3 fix2 Q6: no inset on the west": (GEOMETRY, INSET_WEST, "local west = x0"),
    "l2w3 fix2 Q6: no inset on the east": (
        GEOMETRY,
        "local east = x1 - (if openEast then ice.inset else 0)",
        "local east = x1",
    ),
    "l2w3 fix2 Q6: no inset on the north": (
        GEOMETRY,
        "local north = z0 + (if openNorth then ice.inset else 0)",
        "local north = z0",
    ),
    "l2w3 fix2 Q6: no inset on the south": (
        GEOMETRY,
        "local south = z1 - (if openSouth then ice.inset else 0)",
        "local south = z1",
    ),
    "l2w3 fix2 Q6: every west face inset": (GEOMETRY, INSET_WEST, "local west = x0 + ice.inset"),
    "l2w3 fix2 Q6: the inset doubled": (
        GEOMETRY,
        "local east = x1 - (if openEast then ice.inset else 0)",
        "local east = x1 - (if openEast then 2 * ice.inset else 0)",
    ),
    "l2w3 fix2 Q6: Cells' order read Z fastest": (
        GEOMETRY,
        "local i, j = (k - 1) % nx + 1, (k - 1) // nx + 1",
        "local j, i = (k - 1) % nz + 1, (k - 1) // nz + 1",
    ),
    "l2w3 fix2 Q6: a cell left no width is built": (
        GEOMETRY,
        "if not covered and east - west > SEAM and south - north > SEAM then",
        "if not covered then",
    ),
    "l2w3 fix2 Q6: IceOf takes an inset under 0": (GEOMETRY, "\t\tand inset >= 0\n", ""),
    "l2w3 fix2 Q6: IceOf takes an endless inset": (GEOMETRY, "\t\tand isFinite(inset)\n", ""),
    "l2w3 fix2 Q6: IceOf drops the inset": (
        GEOMETRY,
        "thickness = thickness, inset = inset }, false",
        "thickness = thickness, inset = 0 }, false",
    ),
    "l2w3 fix2 Q6: IceOf's inset defaults to a stud": (
        GEOMETRY,
        "local inset: any = if ice.inset == nil then 0 else ice.inset",
        "local inset: any = if ice.inset == nil then 1 else ice.inset",
    ),
}
MUTATIONS.update(L2W3_FIX2_MUTATIONS)


# The L2 W3 third fix round (docs/prompts/l2-w3-fix3.md). fd-m2: the server leads a falling body's
# feet by its fall over its commit lag (WorldReact.FallDrop and BodyBox's `drop`; LevelService's
# bodies; WeaponService's measured fall and FallSpeed). fd-s1: the phone's ice auto-swing asks
# AirSwing.Judge. fd-s2: a cell's side another ice block meets whole is not inset (LevelGeometry's
# meetsIce and the list of ice blocks). Proved by tests_l2w3.luau's fix3Tests, insetTests,
# realTests and fix3WiringTests.
FALL_RETURN = "return speed * lag + math.max(gravity, 0) * lag * lag / 2"
FALL_SPEED = "local speed = math.min(math.max(fallSpeed, 0), math.max(fastest, 0))"
OPEN_SOUTH = "local openSouth = j == nz and not meetsIce(waters, top, false, z1, 1, x0, x1)"
L2W3_FIX3_MUTATIONS = {
    # fd-m2, the pure rules.
    "l2w3 fix3 fd-m2: FallDrop drops gravity's part": (WORLD_REACT, FALL_RETURN, "return speed * lag"),
    "l2w3 fix3 fd-m2: FallDrop drops the speed's part": (
        WORLD_REACT,
        FALL_RETURN,
        "return math.max(gravity, 0) * lag * lag / 2",
    ),
    "l2w3 fix3 fd-m2: FallDrop squares gravity's whole": (
        WORLD_REACT,
        FALL_RETURN,
        "return speed * lag + math.max(gravity, 0) * lag * lag",
    ),
    "l2w3 fix3 fd-m2: FallDrop's gravity under 0 lifts": (
        WORLD_REACT,
        FALL_RETURN,
        "return speed * lag + gravity * lag * lag / 2",
    ),
    "l2w3 fix3 fd-m2: FallDrop's speed is not capped": (WORLD_REACT, FALL_SPEED, "local speed = math.max(fallSpeed, 0)"),
    "l2w3 fix3 fd-m2: FallDrop takes a rising speed": (
        WORLD_REACT,
        FALL_SPEED,
        "local speed = math.min(fallSpeed, math.max(fastest, 0))",
    ),
    "l2w3 fix3 fd-m2: FallDrop runs a lag under 0": (WORLD_REACT, "\t\tor not (lag > 0)\n", "\t\tor false\n"),
    "l2w3 fix3 fd-m2: FallDrop takes an endless gravity": (
        WORLD_REACT,
        "not (finite(fallSpeed) and finite(lag) and finite(gravity) and finite(fastest))",
        "not (finite(fallSpeed) and finite(lag) and finite(fastest))",
    ),
    "l2w3 fix3 fd-m2: BodyBox ignores the drop": (WORLD_REACT, "local lower = length(drop)", "local lower = 0"),
    "l2w3 fix3 fd-m2: BodyBox takes a drop under 0": (WORLD_REACT, "local lower = length(drop)", "local lower = drop or 0"),
    "l2w3 fix3 fd-m2: BodyBox's drop moves the whole body": (
        WORLD_REACT,
        "\t\ty = position.Y - lower / 2,\n",
        "\t\ty = position.Y - lower,\n",
    ),
    "l2w3 fix3 fd-m2: BodyBox's drop lowers the top too": (
        WORLD_REACT,
        "\t\tsy = 2 * stand + lower,\n",
        "\t\tsy = 2 * stand,\n",
    ),
    # fd-m2, the lines that apply them.
    "l2w3 fix3 fd-m2: the server leads no body": (
        LEVEL_SERVICE,
        "then WorldReact.FallDrop(fall, lag, Workspace.Gravity, fastest)",
        "then 0",
    ),
    "l2w3 fix3 fd-m2: the server leads a standing body by gravity": (
        LEVEL_SERVICE,
        "\t\t\t\telse 0\n",
        "\t\t\t\telse WorldReact.FallDrop(0, lag, Workspace.Gravity, fastest)\n",
    ),
    "l2w3 fix3 fd-m2: the server's lag ignores the ping": (
        LEVEL_SERVICE,
        "local lag = Tuning.CommitLag(config.shooting, player:GetNetworkPing())",
        "local lag = Tuning.CommitLag(config.shooting, 0)",
    ),
    "l2w3 fix3 fd-m2: the server's lead has no cap": (
        LEVEL_SERVICE,
        "local fastest = Tuning.FastestMove(config)",
        "local fastest = math.huge",
    ),
    "l2w3 fix3 fd-m2: the server hands BodyBox no drop": (
        LEVEL_SERVICE,
        "\t\t\t\t\thumanoid.HipHeight,\n\t\t\t\t\tdrop\n",
        "\t\t\t\t\thumanoid.HipHeight\n",
    ),
    "l2w3 fix3 fd-m2: trackAir measures no fall": (
        WEAPON,
        "shooter.fall = if shooter.stood == position then nil else math.max(fallSpeed, 0)",
        "shooter.fall = nil",
    ),
    "l2w3 fix3 fd-m2: trackAir's fall ignores the footing": (
        WEAPON,
        "shooter.fall = if shooter.stood == position then nil else math.max(fallSpeed, 0)",
        "shooter.fall = math.max(fallSpeed, 0)",
    ),
    "l2w3 fix3 fd-m2: no root keeps the fall": (
        WEAPON,
        "\t\t\tshooter.fall = nil\n\t\t\tPositionRing.Clear(shooter.history)\n",
        "\t\t\tPositionRing.Clear(shooter.history)\n",
    ),
    "l2w3 fix3 fd-m2: a server move keeps the fall": (
        WEAPON,
        "\t\tshooter.stood = nil\n\t\tshooter.fall = nil\n\tend\nend",
        "\t\tshooter.stood = nil\n\tend\nend",
    ),
    "l2w3 fix3 fd-m2: a fresh body keeps the fall": (
        WEAPON,
        "\tshooter.fall = nil\n\tshooter.airSwing = SwingGate.New()",
        "\tshooter.airSwing = SwingGate.New()",
    ),
    "l2w3 fix3 fd-m2: FallSpeed answers nothing": (
        WEAPON,
        "return if shooter ~= nil then shooter.fall else nil",
        "return nil",
    ),
    # fd-s1: the phone asks the server's question.
    "l2w3 fix3 fd-s1: the phone asks the Humanoid again": (
        INPUT,
        "local allowed, inAir = AirSwing.Judge(origin, rig.root, rig.humanoid)",
        "local allowed, inAir = true, MovementController.IsAirborne()",
    ),
    "l2w3 fix3 fd-s1: the phone swings in the air": (INPUT, "if not allowed or inAir then", "if not allowed then"),
    "l2w3 fix3 fd-s1: the phone swings a refused swing": (INPUT, "if not allowed or inAir then", "if inAir then"),
    "l2w3 fix3 fd-s1: the phone's first strike drops the verdict": (
        INPUT,
        "local first = autoIceStrike(variant, 1, origin, heading, cone, inAir)",
        "local first = autoIceStrike(variant, 1, origin, heading, cone, false)",
    ),
    "l2w3 fix3 fd-s1: the phone's other strikes drop the verdict": (
        INPUT,
        "table.insert(made, autoIceStrike(variant, step, origin, heading, cone, inAir))",
        "table.insert(made, autoIceStrike(variant, step, origin, heading, cone, false))",
    ),
    # fd-s2: a side another ice block meets whole is not inset.
    "l2w3 fix3 fd-s2: the west side always inset": (
        GEOMETRY,
        "local openWest = i == 1 and not meetsIce(waters, top, true, x0, -1, z0, z1)",
        "local openWest = i == 1",
    ),
    "l2w3 fix3 fd-s2: the east side always inset": (
        GEOMETRY,
        "local openEast = i == nx and not meetsIce(waters, top, true, x1, 1, z0, z1)",
        "local openEast = i == nx",
    ),
    "l2w3 fix3 fd-s2: the north side always inset": (
        GEOMETRY,
        "local openNorth = j == 1 and not meetsIce(waters, top, false, z0, -1, x0, x1)",
        "local openNorth = j == 1",
    ),
    "l2w3 fix3 fd-s2: the south side always inset": (GEOMETRY, OPEN_SOUTH, "local openSouth = j == nz"),
    "l2w3 fix3 fd-s2: the south side asks the north plane": (
        GEOMETRY,
        OPEN_SOUTH,
        "local openSouth = j == nz and not meetsIce(waters, top, false, z0, 1, x0, x1)",
    ),
    "l2w3 fix3 fd-s2: the east side asks the wrong facing": (
        GEOMETRY,
        "local openEast = i == nx and not meetsIce(waters, top, true, x1, 1, z0, z1)",
        "local openEast = i == nx and not meetsIce(waters, top, true, x1, -1, z0, z1)",
    ),
    "l2w3 fix3 fd-s2: meetsIce ignores the top": (
        GEOMETRY,
        "\t\t\tand math.abs(other.y + other.sy / 2 - top) <= SEAM\n",
        "",
    ),
    "l2w3 fix3 fd-s2: meetsIce takes a side met in part": (
        GEOMETRY,
        "\t\t\tand along - span / 2 <= low + SEAM\n\t\t\tand along + span / 2 >= high - SEAM\n",
        "\t\t\tand along - span / 2 < high\n\t\t\tand along + span / 2 > low\n",
    ),
    "l2w3 fix3 fd-s2: meetsIce reads the neighbour's near side": (
        GEOMETRY,
        "math.abs(centre - facing * size / 2 - plane) <= SEAM",
        "math.abs(centre + facing * size / 2 - plane) <= SEAM",
    ),
    "l2w3 fix3 fd-s2: Pieces lists no ice block to meet": (
        GEOMETRY,
        '\t\t\tif blocks[index].react == "ice" then\n\t\t\t\ttable.insert(waters, box)',
        "\t\t\tif false then\n\t\t\t\ttable.insert(waters, box)",
    ),
}
MUTATIONS.update(L2W3_FIX3_MUTATIONS)


# L3 W1, tiers per weapon and the saved loadout (docs/prompts/l3-w1-contract.md). From luau-engineer
# A: the pure Armory ladder, windows, upgrade, levers and refund, the profile's v8 step and Unlocks'
# saved loadout and stars (tests_l3.luau). The harness now also bundles the Armory screen's pure
# model and the formatting it reads (tests_l3_ui.luau), so both files go into every mutant root.
ARMORY = "src/shared/Armory.luau"
FILES += ["src/shared/Format.luau", "src/client/UI/ArmoryModel.luau"]
VERDICT_LOCKED = '\tif start == nil then\n\t\treturn "invalid"\n\tend\n\tif not owned then\n\t\treturn "locked"\n\tend\n'
VERDICT_PEAK = '\tif nextTier == nil then\n\t\treturn "peak"\n\tend\n\tif not gateOpen then\n\t\treturn "busy"\n\tend\n'
L3_MUTATIONS = {
    # The ladder and the windows (L3-1 to L3-3).
    "l3: Window does not hold a window inside the ladder": (
        ARMORY,
        "return clampTier(window.start, size), clampTier(window.top, size)",
        "return window.start, window.top",
    ),
    "l3: Window takes a start above its top": (
        ARMORY,
        "\t\tor not whole(window.top)\n\t\tor window.start > window.top\n\tthen",
        "\t\tor not whole(window.top)\n\tthen",
    ),
    "l3: Window takes a fraction": (
        ARMORY,
        "\t\tor not whole(window.start)\n\t\tor not whole(window.top)\n\t\tor window.start > window.top\n\tthen",
        "\t\tor window.start > window.top\n\tthen",
    ),
    "l3: TierOf ignores the saved tier": (ARMORY, "return math.min(math.max(saved, start), top)", "return start"),
    "l3: TierOf does not hold a saved tier under the top": (
        ARMORY,
        "return math.min(math.max(saved, start), top)",
        "return math.max(saved, start)",
    ),
    "l3: TierOf does not lift a saved tier to the start": (
        ARMORY,
        "return math.min(math.max(saved, start), top)",
        "return math.min(saved, top)",
    ),
    "l3: TierOf takes a saved fraction": (
        ARMORY,
        "\tif not whole(saved) then\n\t\treturn start",
        "\tif type(saved) ~= \"number\" or saved ~= saved then\n\t\treturn start",
    ),
    "l3: a family with no window fights at T2": (
        ARMORY,
        "if start == nil or top == nil then\n\t\treturn 1\n",
        "if start == nil or top == nil then\n\t\treturn 2\n",
    ),
    "l3: HeldTiers reads the melee family for both": (
        ARMORY,
        "ranged = Armory.TierOf(cfg, combat, ranged) }",
        "ranged = Armory.TierOf(cfg, combat, melee) }",
    ),
    "l3: NextTier passes the top": (ARMORY, "return if nextTier <= top then nextTier else nil", "return nextTier"),
    # Strength and health (L3-1, L3-2, L3-6).
    "l3: Multiplier does not hold the tier inside the ladder": (
        ARMORY,
        "ladder.damage[clampTier(tier, #ladder.damage)]",
        "ladder.damage[tier]",
    ),
    "l3: Multiplier takes a tier that is not whole": (
        ARMORY,
        " or not whole(tier) then\n\t\treturn NEUTRAL_MULT",
        " then\n\t\treturn NEUTRAL_MULT",
    ),
    "l3: WeaponHp takes a tier that is not whole": (
        ARMORY,
        "if list == nil or #list == 0 or not whole(tier) then",
        "if list == nil or #list == 0 then",
    ),
    "l3: a multiplier of 0 is kept": (
        ARMORY,
        "return if finite(value) and value > 0 then value else NEUTRAL_MULT",
        "return if finite(value) then value else NEUTRAL_MULT",
    ),
    "l3: DamageScale ignores Ascension": (
        ARMORY,
        "return Armory.Multiplier(cfg, tier) * ascensionMult(cfg, ascLevel, ability)",
        "return Armory.Multiplier(cfg, tier)",
    ),
    "l3: an ability scales by damageMult": (
        ARMORY,
        "return if ability then level.abilityMult else level.damageMult",
        "return level.damageMult",
    ),
    "l3: WeaponHp ignores hpMult": (
        ARMORY,
        "return value * (if level ~= nil then level.hpMult else NEUTRAL_MULT)",
        "return value",
    ),
    "l3: WeaponHp reads melee for every slot": (
        ARMORY,
        'local list: any = if slot == "melee"\n\t\tthen hp.melee\n\t\telseif slot == "ranged" then hp.ranged\n\t\telse nil',
        "local list: any = hp.melee",
    ),
    "l3: RangeHp is baseHp": (
        ARMORY,
        "return if finite(value) and value > 0 then value else cfg.baseHp",
        "return cfg.baseHp",
    ),
    "l3: GearPower weighs the tiers at 1": (
        ARMORY,
        "local tierWeight = if finite(weight) then weight else 0",
        "local tierWeight = 1",
    ),
    "l3: GearPower drops health": (
        ARMORY,
        "damage * tierWeight + Armory.MaxHp(cfg, tiers, ascension) * cfg.power.hpWeight",
        "damage * tierWeight",
    ),
    "l3: Preview drops the multiplier": (
        ARMORY,
        "return math.round(baseDamage * Armory.Multiplier(cfg, tier)),",
        "return math.round(baseDamage),",
    ),
    # Bands and costs (L3-4).
    "l3: BandOf counts positions from 0": (ARMORY, "(tier - 1) % bandSize + 1", "tier % bandSize + 1"),
    "l3: BandOf takes a fraction": (ARMORY, "\t\tor not whole(tier)\n", ""),
    "l3: TierCost takes a negative cost": (
        ARMORY,
        "if def == nil or not finite(cost) or cost < 0 then",
        "if def == nil or not finite(cost) then",
    ),
    # UpgradeVerdict's reasons and their order (L3-5).
    "l3: locked before invalid": (
        ARMORY,
        VERDICT_LOCKED,
        '\tif not owned then\n\t\treturn "locked"\n\tend\n\tif start == nil then\n\t\treturn "invalid"\n\tend\n',
    ),
    "l3: busy before peak": (
        ARMORY,
        VERDICT_PEAK,
        '\tif not gateOpen then\n\t\treturn "busy"\n\tend\n\tif nextTier == nil then\n\t\treturn "peak"\n\tend\n',
    ),
    "l3: no gate": (ARMORY, '\tif not gateOpen then\n\t\treturn "busy"\n\tend\n', ""),
    "l3: an unbuilt band is for sale": (ARMORY, "built[band.levelId] ~= true or ", ""),
    "l3: a priceless tier is for sale": (
        ARMORY,
        ' or material == "" then\n\t\treturn "notBuilt"',
        ' then\n\t\treturn "notBuilt"',
    ),
    # Re-aimed by the fix round's R1: the verdict asks Armory.StarHeld.
    "l3: a band top needs no star": (
        ARMORY,
        "position == ladder.bandSize and not Armory.StarHeld(",
        "false and not Armory.StarHeld(",
    ),
    "l3: a star of any difficulty is the trophy": (
        ARMORY,
        'return type(difficulty) == "string" and type(row) == "table" and row[difficulty] == true',
        'return type(row) == "table" and next(row) ~= nil',
    ),
    "l3: the funds at a strict edge": (
        ARMORY,
        "if not (finite(have) and have >= cost) then",
        "if not (finite(have) and have > cost) then",
    ),
    # Upgrade (L3-13).
    "l3: Upgrade skips its verdict": (
        ARMORY,
        "\tif verdict ~= nil then\n\t\treturn verdict\n\tend\n\tlocal nextTier = Armory.NextTier(cfg, combat, family)",
        "\tlocal nextTier = Armory.NextTier(cfg, combat, family)",
    ),
    "l3: Upgrade spends nothing": (
        ARMORY,
        "\tcombat.materials[material] = math.max(0, (combat.materials[material] or 0) - cost)\n",
        "",
    ),
    "l3: Upgrade writes a tier too many": (
        ARMORY,
        "\ttiers[family] = nextTier\n\treturn nil",
        "\ttiers[family] = nextTier + 1\n\treturn nil",
    ),
    "l3: Upgrade makes a tiers table it does not keep": (
        ARMORY,
        "\tlocal tiers = combat.tiers or {}\n\tcombat.tiers = tiers\n\ttiers[family] = nextTier",
        "\tlocal tiers = combat.tiers or {}\n\ttiers[family] = nextTier",
    ),
    # The levers' pieces (L3-28) and the refund (L3-8).
    "l3: SetTier does not hold to the window": (
        ARMORY,
        "local held = math.min(math.max(math.floor(tier), start), top)",
        "local held = math.floor(tier)",
    ),
    "l3: SetTier takes a NaN": (
        ARMORY,
        "if start == nil or top == nil or not finite(tier) then",
        "if start == nil or top == nil then",
    ),
    "l3: BuiltBands lists bands not built": (ARMORY, "\t\t\tand built[def.levelId] == true\n", ""),
    "l3: BuiltBands repeats a shared material": (
        ARMORY,
        "\t\t\tif table.find(materials, def.material) == nil then\n\t\t\t\ttable.insert(materials, def.material)\n\t\t\tend",
        "\t\t\ttable.insert(materials, def.material)",
    ),
    "l3: the refund counts one tier too many": (
        ARMORY,
        "for t = 1, math.min(owned, #list) do",
        "for t = 1, math.min(owned + 1, #list) do",
    ),
    "l3: the refund rounds a fraction down": (
        ARMORY,
        "\t\tif not whole(owned) then\n\t\t\tcontinue",
        "\t\tif not finite(owned) then\n\t\t\tcontinue\n\t\tend\n\t\towned = math.floor(owned)\n\t\tif false then\n\t\t\tcontinue",
    ),
    "l3: the refund reads only melee": (
        ARMORY,
        "for _, owned: any in { gear.melee, gear.ranged } do",
        "for _, owned: any in { gear.melee } do",
    ),
    "l3: the refund takes a negative amount": (ARMORY, "\t\t\t\tand entry.amount >= 0\n", ""),
    # Problems (L3-5).
    "l3: Problems takes a damage entry that does not rise": (
        ARMORY,
        "elseif t > 1 and finite(before) and value <= before then",
        "elseif false then",
    ),
    "l3: Problems takes ranged above melee": (
        ARMORY,
        "if finite(melee[t]) and finite(ranged[t]) and melee[t] < ranged[t] then",
        "if false then",
    ),
    "l3: Problems takes a window naming no family": (ARMORY, "if not known[family] then", "if false then"),
    # ProfileSchema v8 (L3-7, L3-8).
    "l3: the schema stays at v7": (SCHEMA, "local SCHEMA_VERSION = 8", "local SCHEMA_VERSION = 7"),
    "l3: the template lacks tiers": (SCHEMA, "\t\ttiers = {},\n", ""),
    "l3: the template names a starter": (
        SCHEMA,
        "\t\tloadout = { variants = {} },\n\t\tstars = {},",
        '\t\tloadout = { melee = "broadsword", variants = {} },\n\t\tstars = {},',
    ),
    "l3: there is no step from v7": (
        SCHEMA,
        "[7] = function(state: Types.PlayerState): ()",
        "[17] = function(state: Types.PlayerState): ()",
    ),
    "l3: the step shares the template's tiers": (
        SCHEMA,
        "\t\t\tcombat.tiers = {}\n",
        "\t\t\tcombat.tiers = PROFILE_TEMPLATE.combat.tiers\n",
    ),
    "l3: the step replaces a loadout that is there": (
        SCHEMA,
        '\t\tif loadout == nil then\n\t\t\tcombat.loadout = { variants = {} }\n\t\telseif type(loadout.variants) ~= "table" then\n\t\t\tloadout.variants = {}\n\t\tend\n',
        "\t\tcombat.loadout = { variants = {} }\n",
    ),
    "l3: the step leaves a loadout without its variants": (
        SCHEMA,
        '\t\telseif type(loadout.variants) ~= "table" then\n\t\t\tloadout.variants = {}\n',
        "",
    ),
    "l3: the step forgets stars": (SCHEMA, "\t\tif combat.stars == nil then\n\t\t\tcombat.stars = {}\n\t\tend\n", ""),
    "l3: the step refunds nothing": (
        SCHEMA,
        "\t\t\tcombat.materials[material] = (combat.materials[material] or 0) + amount\n",
        "",
    ),
    "l3: the step refunds twice over": (
        SCHEMA,
        "(combat.materials[material] or 0) + amount\n",
        "(combat.materials[material] or 0) + 2 * amount\n",
    ),
    "l3: the step zeroes the frozen gear": (
        SCHEMA,
        "\t\tfor material, amount in Armory.LegacyRefund(armoryConfig, combat.gear) do",
        "\t\tlocal gear = combat.gear\n\t\tcombat.gear = { melee = 0, ranged = 0 }\n"
        "\t\tfor material, amount in Armory.LegacyRefund(armoryConfig, gear) do",
    ),
    "l3: the step refunds at other prices": (
        SCHEMA,
        "Armory.LegacyRefund(armoryConfig, combat.gear)",
        'Armory.LegacyRefund({ legacy = { gearCosts = { { material = "Timber", amount = 100 } } } } :: any, combat.gear)',
    ),
    # Unlocks: the saved loadout and stars (L3-9, L3-10), the levers' pieces (L3-28).
    # Re-aimed by the fix round's R7: the slot rule moved to Armory.HeldFamily, which LoadoutOf calls.
    "l3: LoadoutOf holds a family not owned": (
        ARMORY,
        "return if isStarter or found then family else starter",
        "return family",
    ),
    "l3: LoadoutOf holds a family in the wrong slot": (
        ARMORY,
        'if type(def) ~= "table" or def.slot ~= slot then\n\t\treturn starter',
        'if type(def) ~= "table" then\n\t\treturn starter',
    ),
    "l3: LoadoutOf keeps an unknown style": (UNLOCKS, "\t\t\t\tand def.variants[key] ~= nil\n", ""),
    "l3: SaveLoadout writes any slot": (
        UNLOCKS,
        '\tif slot ~= "melee" and slot ~= "ranged" then\n\t\treturn\n\tend\n',
        "",
    ),
    "l3: SaveLoadout forgets the style": (UNLOCKS, "\tvariants[family] = variant\n", ""),
    "l3: SaveLoadout makes a loadout it does not keep": (
        UNLOCKS,
        "\tcombat.loadout = loadout\n\t-- A hand-edited",
        "\t-- A hand-edited",
    ),
    "l3: StarsOf does not keep what it made": (UNLOCKS, "\tcombat.stars = made\n", ""),
    "l3: ResetArmory keeps the stars": (UNLOCKS, "\tcombat.stars = {}\nend", "end"),
    "l3: ResetArmory clears the families": (
        UNLOCKS,
        "\tcombat.tiers = {}\n\tcombat.loadout = { variants = {} }",
        "\tcombat.tiers = {}\n\tcombat.families = {}\n\tcombat.loadout = { variants = {} }",
    ),
    "l3: TierLever takes a fraction": (UNLOCKS, '"^([%w_]+)=(%d+)$"', '"^([%w_]+)=([%d%.]+)$"'),
    "l3: TierLever takes a long id": (
        UNLOCKS,
        " or #family > MAX_FAMILY_LENGTH then\n\t\treturn nil, nil",
        " then\n\t\treturn nil, nil",
    ),
}
MUTATIONS.update(L3_MUTATIONS)

# L3 W1, from luau-engineer B: the range's body read from the ladder, and StageFlow's first clear
# (FirstClear and Validate's firstClear lines, tests_l3_run.luau).
L3_RUN_MUTATIONS = {
    "l3: the range's body is the held pair's MaxHp": (
        VITALS,
        "return Armory.RangeHp(armoryConfig)",
        "return Armory.MaxHp(armoryConfig, { melee = 1, ranged = 1 }, { melee = 0, ranged = 0 })",
    ),
    "l3: Validate skips the first clears": (FLOW, "\tfirstClearProblems(level, weapons, starters, problem)\n", ""),
    "l3: a firstClear that is no table is accepted": (FLOW, "\t\t\tproblem(`{where} is not a table`)\n", ""),
    "l3: a first-clear family of any length is accepted": (FLOW, " or #id > Unlocks.MAX_FAMILY_LENGTH", ""),
    "l3: an empty first-clear family is accepted": (
        FLOW,
        'if type(id) ~= "string" or id == "" or #id > Unlocks.MAX_FAMILY_LENGTH then',
        'if type(id) ~= "string" or #id > Unlocks.MAX_FAMILY_LENGTH then',
    ),
    "l3: a first clear may name an unknown family": (
        FLOW,
        "elseif weapons ~= nil and weapons[id] == nil then",
        "elseif false then",
    ),
    "l3: a first clear may name a starter": (
        FLOW,
        "elseif starters ~= nil and starters[id] == true then",
        "elseif false then",
    ),
    "l3: a fractional first-clear Valor is accepted": (
        FLOW,
        "valor ~= nil and not (isFinite(valor) and valor >= 0 and valor % 1 == 0)",
        "valor ~= nil and not (isFinite(valor) and valor >= 0)",
    ),
    "l3: a negative first-clear Valor is accepted": (
        FLOW,
        "valor ~= nil and not (isFinite(valor) and valor >= 0 and valor % 1 == 0)",
        "valor ~= nil and not (isFinite(valor) and valor % 1 == 0)",
    ),
    "l3: the first-clear lines come in the table's order": (FLOW, "\ttable.sort(names)\n", ""),
    "l3: FirstClear keeps an empty family": (
        FLOW,
        'family = if type(family) == "string" and family ~= "" then family else nil,',
        'family = if type(family) == "string" then family else nil,',
    ),
    "l3: FirstClear keeps a fractional Valor": (
        FLOW,
        "valor = if isFinite(valor) and valor > 0 and valor % 1 == 0 then valor else nil,",
        "valor = if isFinite(valor) and valor > 0 then valor else nil,",
    ),
    "l3: FirstClear keeps a Valor of 0": (
        FLOW,
        "valor = if isFinite(valor) and valor > 0 and valor % 1 == 0 then valor else nil,",
        "valor = if isFinite(valor) and valor >= 0 and valor % 1 == 0 then valor else nil,",
    ),
    "l3: FirstClear gives an empty reward": (
        FLOW,
        "\tif given.family == nil and given.valor == nil then\n\t\treturn nil\n\tend\n",
        "",
    ),
    "l3: FirstClear hands out the level file's table": (FLOW, "\treturn given\nend\n", "\treturn reward\nend\n"),
    "l3: FirstClear reads the hard difficulty whatever is asked": (
        FLOW,
        "then difficulties[difficulty] else nil",
        "then difficulties.hard else nil",
    ),
}
MUTATIONS.update(L3_RUN_MUTATIONS)
# L3 W1, from ui-engineer A: the Armory screen's pure ArmoryModel (tests_l3_ui.luau). Format.luau
# and ArmoryModel.luau are in FILES (luau-engineer A's block above).
ARMORY_MODEL = "src/client/UI/ArmoryModel.luau"
L3_UI_MUTATIONS = {
    "l3 ui: the shelf runs against window starts": (ARMORY_MODEL, "\t\t\treturn aStart < bStart\n", "\t\t\treturn aStart > bStart\n"),
    "l3 ui: ranged before melee on one start": (ARMORY_MODEL, "return SLOT_ORDER[a.slot] < SLOT_ORDER[b.slot]", "return SLOT_ORDER[a.slot] > SLOT_ORDER[b.slot]"),
    "l3 ui: a family with no window first": (ARMORY_MODEL, "local NO_WINDOW = math.huge", "local NO_WINDOW = 0"),
    "l3 ui: a found entry beats the secret's hint": (ARMORY_MODEL, "\t\t\t\tand where[family] == nil\n", ""),
    "l3 ui: an owned family keeps its hint": (ARMORY_MODEL, "hint = if owned then nil else hints[family],", "hint = hints[family],"),
    "l3 ui: the held pair ignores the saved loadout": (ARMORY_MODEL, "return Unlocks.LoadoutOf(inputs.combat, inputs.weapons, fallback)", "return { melee = fallback.melee, ranged = fallback.ranged, variants = {} }"),
    "l3 ui: the tier's own pip is not lit": (ARMORY_MODEL, "state = if card.owned and tier <= card.tier then", "state = if card.owned and tier < card.tier then"),
    "l3 ui: an unowned window is lit": (ARMORY_MODEL, "state = if card.owned and tier <= card.tier then", "state = if tier <= card.tier then"),
    "l3 ui: pips lose their band colour": (ARMORY_MODEL, "color = bandColor(inputs, band),", "color = nil,"),
    "l3 ui: the next line ignores the held style": (ARMORY_MODEL, "nextLine = nextLine(inputs, card, equipVariant),", "nextLine = nextLine(inputs, card, card.default),"),
    "l3 ui: the cost line forgets the star": (ARMORY_MODEL, "if bandTop and not hasStar(inputs, levelId) then", "if bandTop then"),
    "l3 ui: an unbuilt band's cost shows": (ARMORY_MODEL, "if levelId == nil or inputs.built[levelId] ~= true or material == \"\" then", "if levelId == nil or material == \"\" then"),
    "l3 ui: Upgrade is live whatever the verdict": (ARMORY_MODEL, "\t)\n\tif verdict == nil then\n\t\tlocal nextTier", "\t)\n\tif true then\n\t\tlocal nextTier"),
    "l3 ui: two upgrades in flight": (ARMORY_MODEL, "return { visible = true, live = pending == nil, text = text, look = \"action\" }, nextTier", "return { visible = true, live = true, text = text, look = \"action\" }, nextTier"),
    "l3 ui: Equip ignores the gate": (ARMORY_MODEL, "\t\tvariant,\n\t\tinputs.gateOpen\n\t)", "\t\tvariant,\n\t\ttrue\n\t)"),
    "l3 ui: the held family is not Equipped": (ARMORY_MODEL, "\tif card.held then\n\t\treturn { visible = true, live = false, text = TEXT.equipped, look = \"held\" }", "\tif false then\n\t\treturn { visible = true, live = false, text = TEXT.equipped, look = \"held\" }"),
    "l3 ui: two equips in flight": (ARMORY_MODEL, "\t\t\tlive = pending.equipFamily == nil,\n", "\t\t\tlive = true,\n"),
    "l3 ui: the held style is not held": (ARMORY_MODEL, "if card.held and heldKey == variant.key then", "if false then"),
    "l3 ui: busy toasts Try again": (ARMORY_MODEL, "\tif reason == \"busy\" then\n\t\treturn TEXT.busy\n\tend\n\tif action", "\tif action"),
    "l3 ui: the shortfall is the whole price": (ARMORY_MODEL, "local short = amount - (combat.materials[material] or 0)", "local short = amount"),
    "l3 ui: the wallet shows unbuilt bands": (ARMORY_MODEL, "Armory.BuiltBands(armory, inputs.built)", "Armory.BuiltBands(armory, { forestRoad = true, castle = true })"),
    "l3 ui: the screen opens on the ranged family": (ARMORY_MODEL, "if card.family == held.melee then", "if card.family == held.ranged then"),
}
MUTATIONS.update(L3_UI_MUTATIONS)
# L3 W1 fix round, from the ui-engineer (tests_l3_ui.luau): R1, R11, 4-s4, 4-s5, 3-s2.
L3_UI_FIX_MUTATIONS = {
    "l3 ui: a style is live during another equip": (ARMORY_MODEL, "\t\t\tlive = pending.equipFamily == nil\n", "\t\t\tlive = true\n"),
    "l3 ui: the cost line reads only the Hard star": (ARMORY_MODEL, "\treturn armory ~= nil and combat ~= nil and Armory.StarHeld(armory, combat, levelId)\n", "\treturn combat ~= nil and type(combat.stars) == \"table\" and type(combat.stars[levelId]) == \"table\" and combat.stars[levelId].hard == true\n"),
    "l3 ui: an unnamed star reads as Hard": (ARMORY_MODEL, "\treturn if type(key) == \"string\" and key ~= \"\" then key else nil\n", "\treturn if type(key) == \"string\" and key ~= \"\" then key else \"hard\"\n"),
    "l3 ui: an unnamed star's button names Hard": (ARMORY_MODEL, "\t\t\telse TEXT.needsAStar .. levelName\n", "\t\t\telse \"Needs \u2605 Hard on \" .. levelName\n"),
    "l3 ui: a style switch toasts a plain equip": (ARMORY_MODEL, "\tif style ~= nil then\n", "\tif false then\n"),
    "l3 ui: the star lever names the first level only": (ARMORY_MODEL, "table.concat(names, \", \")", "names[1]"),
    "l3 ui: the star lever ignores what is built": (ARMORY_MODEL, "\t\tlocal levelIds = Armory.BuiltBands(armory, built)\n", "\t\tlocal levelIds = { \"forestRoad\" }\n"),
}
MUTATIONS.update(L3_UI_FIX_MUTATIONS)

# The L3 W1 fix round (docs/prompts/l3-w1-fix-round.md), from luau-engineer A': the band top's trophy
# (StarHeld, R1), the strike tier (StrikeTier, R3), the saved pair's Power and the hub's copy
# (HeldFamily, SavedPower, ProfileCopy, R7), the one runner (ProfileSchema.Run, R5), single-rule
# breaks of Problems (R6), and the service lines tests_l3 reads as text (run_harness.py L3_LINES):
# those services never load here, so only those counts can catch their mutants. Then
# luau-engineer B's entries on its own lines. Every file the text reading counts in goes into
# every mutant root.
UNLOCK_SERVICE = "src/combat/server/Services/UnlockService.luau"
DEBUG_SERVICE = "src/combat/server/Services/DebugService.luau"
HUB_ECONOMY = "src/server/Services/EconomyService.luau"
HUB_DATA = "src/server/Services/DataService.luau"
HUB_ARMORY = "src/server/Services/ArmoryService.luau"
PROFILE_COPY = "src/shared/ProfileCopy.luau"
FILES += [UNLOCK_SERVICE, DEBUG_SERVICE, HUB_ECONOMY, HUB_DATA, HUB_ARMORY, PROFILE_COPY]
L3_FIX_MUTATIONS = {
    # R1: StarHeld and the starAlso rule.
    "l3fix R1: StarHeld ignores starAlso": (ARMORY, "for index = 1, #also do", "for index = 1, 0 do"),
    "l3fix R1: StarHeld ignores starDifficulty": (
        ARMORY,
        "if starHeld(combat, levelId, ladder.starDifficulty) then",
        "if false then",
    ),
    "l3fix R1: Problems takes any starAlso": (ARMORY, "if also ~= nil and not namesList(also) then", "if false then"),
    "l3fix R1: a starAlso keyed by name is a list": (ARMORY, "return count == #value", "return true"),
    "l3fix R1: a starAlso with an empty name is a list": (
        ARMORY,
        'if type(name) ~= "string" or name == "" then\n\t\t\treturn false',
        'if type(name) ~= "string" then\n\t\t\treturn false',
    ),
    # R3: StrikeTier.
    "l3fix R3: StrikeTier ignores the override": (
        ARMORY,
        "if overrideTier == nil then\n\t\treturn Armory.TierOf(cfg, combat, family)",
        "if true then\n\t\treturn Armory.TierOf(cfg, combat, family)",
    ),
    "l3fix 2-s1: StrikeTier does not hold the override in the window": (
        ARMORY,
        "return math.min(math.max(overrideTier, first), last)",
        "return overrideTier",
    ),
    "l3fix 2-s1: StrikeTier lifts no override to the window's start": (
        ARMORY,
        "return math.min(math.max(overrideTier, first), last)",
        "return math.min(overrideTier, last)",
    ),
    "l3fix R3: an override fields a family with no window": (
        ARMORY,
        "if first == nil or last == nil then\n\t\treturn 1",
        "if first == nil or last == nil then\n\t\treturn overrideTier",
    ),
    "l3fix R3: StrikeTier takes a fractional override": (
        ARMORY,
        "if not whole(overrideTier) then\n\t\treturn first",
        "if false then\n\t\treturn first",
    ),
    # R7: SavedPower (HeldFamily's two rules are the re-aimed LoadoutOf entries above).
    "l3fix R7: SavedPower reads the melee family for both slots": (
        ARMORY,
        'local ranged = Armory.HeldFamily(combat, weapons, starters, "ranged")',
        'local ranged = Armory.HeldFamily(combat, weapons, starters, "melee")',
    ),
    "l3fix R7: SavedPower ignores Ascension": (
        ARMORY,
        "return Armory.GearPower(cfg, Armory.HeldTiers(cfg, combat, melee, ranged), ascension)",
        "return Armory.GearPower(cfg, Armory.HeldTiers(cfg, combat, melee, ranged), { melee = 0, ranged = 0 })",
    ),
    "l3fix R7: SavedPower reads the frozen gear": (
        ARMORY,
        "return Armory.GearPower(cfg, Armory.HeldTiers(cfg, combat, melee, ranged), ascension)",
        "return Armory.GearPower(cfg, if combat ~= nil then combat.gear else { melee = 1, ranged = 1 }, ascension)",
    ),
    # R7: ProfileCopy.
    "l3fix R7: the copy shares the profile's tables": (PROFILE_COPY, "copy[key] = deepCopy(item)", "copy[key] = item"),
    "l3fix R7: the copy drops a field (stars)": (
        PROFILE_COPY,
        "\tfor key, item in value do\n\t\tcopy[key] = deepCopy(item)",
        '\tfor key, item in value do\n\t\tif key == "stars" then\n\t\t\tcontinue\n\t\tend\n\t\tcopy[key] = deepCopy(item)',
    ),
    "l3fix R7: the copy is the profile itself": (
        PROFILE_COPY,
        "local copy: Types.CombatProfile = deepCopy(combat)",
        "local copy: Types.CombatProfile = combat",
    ),
    "l3fix R7: a loadout copied without its variants": (
        PROFILE_COPY,
        'if type(loadout) == "table" and type(loadout.variants) ~= "table" then',
        "if false then",
    ),
    # R5: ProfileSchema.Run, the one runner.
    "l3fix R5: the runner runs a step twice": (
        SCHEMA,
        "\t\tmigrate(state)\n\t\tstate.version = version + 1",
        "\t\tmigrate(state)\n\t\tmigrate(state)\n\t\tstate.version = version + 1",
    ),
    "l3fix R5: the runner does not stamp the version": (SCHEMA, "\t\tstate.version = version + 1\n", ""),
    "l3fix R5: the runner says nothing of a missing step": (
        SCHEMA,
        'if migrate == nil then\n\t\t\treturn "missing"',
        "if migrate == nil then\n\t\t\treturn nil",
    ),
    "l3fix R5: the runner says nothing of a newer profile": (SCHEMA, 'return "ahead"', "return nil"),
    "l3fix R5: the runner takes a version that is not whole": (
        SCHEMA,
        'if from % 1 ~= 0 then\n\t\treturn "missing"',
        'if false then\n\t\treturn "missing"',
    ),
    # R6: the three Problems rules no break proved alone (review 1-m2).
    "l3fix R6: Problems takes a bandSize that is not whole": (
        ARMORY,
        "if not whole(bandSize) or bandSize <= 0 then",
        "if false then",
    ),
    "l3fix R6: Problems takes bands that do not cover the ladder": (
        ARMORY,
        "elseif bandSize * #bands ~= size then",
        "elseif false then",
    ),
    "l3fix R6: Problems takes a negative HP entry": (
        ARMORY,
        "if not finite(value) or value < 0 then\n\t\t\t\t\tproblem(",
        "if not finite(value) then\n\t\t\t\t\tproblem(",
    ),
    # R3: the service lines, caught only by tests_l3's text counts (run_harness.py L3_LINES).
    "l3fix R3: the slam scales by the word melee": (
        WEAPON,
        "StrikeTally.New(damageScale(player, shooter.loadout.melee, false))",
        'StrikeTally.New(damageScale(player, "melee", false))',
    ),
    "l3fix R3: a ranged hit reads the melee override": (
        WEAPON,
        'elseif slot == "ranged" then gear.ranged\n\t\t\telse nil',
        'elseif slot == "ranged" then gear.melee\n\t\t\telse nil',
    ),
    "l3fix R3: a hit ignores its slot's Ascension": (
        WEAPON,
        "return Armory.DamageScale(armoryConfig, tier, level, ability)",
        "return Armory.DamageScale(armoryConfig, tier, 0, ability)",
    ),
    "l3fix R3: the bar ignores the ranged override": (
        WEAPON,
        "local rangedOverride = if gear ~= nil then gear.ranged else nil",
        "local rangedOverride = nil",
    ),
    "l3fix R3: the dungeon upgrades in a fight": (UNLOCK_SERVICE, "\t\tgate ~= nil and gate(player),\n", "\t\ttrue,\n"),
    "l3fix R3: the dungeon upgrades a family not owned": (
        UNLOCK_SERVICE,
        "Unlocks.OwnsFamily(combat.families, family, starters()),",
        "true,",
    ),
    "l3fix R3: EndRun reads no first-clear reward": (
        WAVE_SERVICE,
        "local reward = if star then StageFlow.FirstClear(level, plan.difficulty) else nil",
        "local reward = nil",
    ),
    "l3fix R3: EndRun gives no first clear": (
        WAVE_SERVICE,
        "local given = if reward ~= nil then UnlockService.GrantFirstClear(player, reward) else nil",
        "local given = nil",
    ),
    "l3fix R3: the stars stay in session memory": (
        WAVE_SERVICE,
        "if profile ~= nil then\n\t\treturn Unlocks.StarsOf(profile.combat)",
        "if false then\n\t\treturn Unlocks.StarsOf(profile.combat)",
    ),
    "l3fix R3: readLevel hands Validate no weapons": (
        WAVE_SERVICE,
        "\t\ttuned.weapons,\n\t\tUnlocks.Starters(tuned.loadout)\n\t)",
        "\t\tnil,\n\t\tUnlocks.Starters(tuned.loadout)\n\t)",
    ),
    "l3fix R3: readLevel hands Validate no starters": (
        WAVE_SERVICE,
        "\t\ttuned.weapons,\n\t\tUnlocks.Starters(tuned.loadout)\n\t)",
        "\t\ttuned.weapons,\n\t\tnil\n\t)",
    ),
    "l3fix R7: the dungeon Snapshot reads the bar's tiers": (
        MAIN_SERVER,
        "\t\tgearPower = if armoryConfig ~= nil\n",
        "\t\tgearPower = if armoryConfig ~= nil and WeaponService.GearOf(player) ~= nil\n",
    ),
    # R7, R5, 3-s2 in the hub.
    "l3fix R7: the hub's Power reads a fresh profile": (
        HUB_ECONOMY,
        "return Armory.SavedPower(\n\t\tarmoryConfig,\n\t\tstate.combat,\n",
        "return Armory.SavedPower(\n\t\tarmoryConfig,\n\t\tnil,\n",
    ),
    "l3fix R7: the hub's Delta drops the Power": (HUB_ECONOMY, "\t\t\tdelta.gearPower = computeGearPower(state)\n", ""),
    "l3fix R7: the hub's Delta sends the profile itself": (
        HUB_ECONOMY,
        "delta.combat = ProfileCopy.Combat(state.combat)",
        "delta.combat = state.combat",
    ),
    "l3fix R7: the hub's Power reads the frozen gear": (
        HUB_ECONOMY,
        "local function computeGearPower(state: Types.PlayerState): number\n",
        "local function computeGearPower(state: Types.PlayerState): number\n\tlocal _ = state.combat.gear\n",
    ),
    "l3fix R5: DataService runs no migration": (HUB_DATA, "local verdict = ProfileSchema.Run(state)", "local verdict = nil"),
    "l3fix R5: DataService steps a profile itself": (
        HUB_DATA,
        "local verdict = ProfileSchema.Run(state)",
        "local verdict = ProfileSchema.Migrations[state.version] and ProfileSchema.Run(state)",
    ),
    "l3fix R3: the hub upgrades a family not owned": (
        HUB_ARMORY,
        "local owned = Unlocks.OwnsFamily(state.combat.families, family, starters)",
        "local owned = true",
    ),
    "l3fix R3: the hub's upgrade is gated shut": (
        HUB_ARMORY,
        "Armory.Upgrade(armoryConfig, state.combat, family, owned, true, built)",
        "Armory.Upgrade(armoryConfig, state.combat, family, owned, false, built)",
    ),
    "l3fix 3-s2: the star wildcard is spelled in the hub": (
        HUB_ARMORY,
        "if value == Unlocks.ALL_STARS then",
        'if value == "*" then',
    ),
}
MUTATIONS.update(L3_FIX_MUTATIONS)
# The L3 W1 fix round, from luau-engineer B' (docs/prompts/l3-w1-fix-reports/luau-b.md): its own lines
# in WeaponService, WaveService, DebugService and Main, caught by the same text counts.
L3_FIX_RUN_MUTATIONS = {
    "l3fix R3: a hit ignores its family's tier": (WEAPON, "local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)", "local tier = 1"),
    "l3fix R3: a hit ignores the Studio override": (WEAPON, "local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)", "local tier = Armory.StrikeTier(armoryConfig, combat, family, nil)"),
    "l3fix 2-s1: the override reaches a hit unclamped": (WEAPON, "local tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)", "local tier = overrideTier or Armory.TierOf(armoryConfig, combat, family)"),
    "l3fix R3: a melee hit reads the ranged override": (WEAPON, "\t\t\tthen gear.melee\n", "\t\t\tthen gear.ranged\n"),
    "l3fix R3: the bar's melee tier is T1": (WEAPON, "melee = Armory.StrikeTier(armoryConfig, combat, held.melee, meleeOverride),", "melee = 1,"),
    "l3fix R3: the bar's ranged tier is the melee family's": (WEAPON, "ranged = Armory.StrikeTier(armoryConfig, combat, held.ranged, rangedOverride),", "ranged = Armory.StrikeTier(armoryConfig, combat, held.melee, rangedOverride),"),
    "l3fix 2-s1: the bar reads the override unclamped": (WEAPON, "melee = Armory.StrikeTier(armoryConfig, combat, held.melee, meleeOverride),", "melee = meleeOverride or Armory.TierOf(armoryConfig, combat, held.melee),"),
    "l3fix R3: the bar ignores the override": (WEAPON, "local meleeOverride = if gear ~= nil then gear.melee else nil", "local meleeOverride = nil"),
    "l3fix R4: a lever star pays nothing": (WAVE_SERVICE, "local grant = if reward ~= nil then UnlockService.GrantFirstClear(player, reward) else nil", "local grant = nil"),
    # Re-aimed in the fix round 2 (F3: the level is resolved before the star, so the line reads it plain).
    "l3fix R4: a lever star reads no reward": (WAVE_SERVICE, "local reward = StageFlow.FirstClear(level, difficulty)", "local reward = nil"),
    "l3fix R4: a lever star pays the Normal reward": (WAVE_SERVICE, "local reward = StageFlow.FirstClear(level, difficulty)", 'local reward = StageFlow.FirstClear(level, "normal")'),
    "l3fix R4: an old lever star pays again": (WAVE_SERVICE, "\t\tif not StageFlow.Award(stars, levelId, difficulty) then\n\t\t\tcontinue\n\t\tend\n", "\t\tStageFlow.Award(stars, levelId, difficulty)\n"),
    "l3fix R4: the lever pays on a live server": (WAVE_SERVICE, "if not boot.mission or not RunService:IsStudio() then", "if not boot.mission then"),
    "l3fix 3-s2: the star wildcard is spelled in DebugService": (DEBUG_SERVICE, "if which == Unlocks.ALL_STARS then", 'if which == "*" then'),
    "l3fix 2-s1: G matches its presets against the clamped bar": (DEBUG_SERVICE, "local gear = WeaponService.GearOverride(player) or WeaponService.GearOf(player)", "local gear = WeaponService.GearOf(player)"),
    "l3fix 2-s1: setGear keeps the clamped tier of an unnamed slot": (DEBUG_SERVICE, "local gear = WeaponService.GearOverride(target) or fought", "local gear = fought"),
    "l3fix R7: the dungeon Power reads a fresh profile": (MAIN_SERVER, "then Armory.SavedPower(\n\t\t\t\tarmoryConfig,\n\t\t\t\tstate.combat,\n", "then Armory.SavedPower(\n\t\t\t\tarmoryConfig,\n\t\t\t\tnil,\n"),
}
MUTATIONS.update(L3_FIX_RUN_MUTATIONS)

# The L3 W1 fix round 2 (docs/prompts/l3-w1-fix2.md): F1, the lines that feed each pinned call and
# the exits of the bodies they live in (the fix-diff review's eleven probes are the first entries),
# and the count-0 rules in the review's other spellings; F2, Unlocks.ApplyFirstClear's rules and the
# lines that call it in both places; F3, U resolves the level before its star. Every service entry
# is caught only by tests_l3's text counts (run_harness.py L3_LINES and L3_PATTERNS).
HUB_UI = "src/client/Controllers/UIController.luau"
FILES.append(HUB_UI)
L3_FIX2_MUTATIONS = {
    # F1: the review's probes (docs/prompts/l3-w1-fix-diff-review.md m1), as it gave them.
    "l3fix2 F1: a hit reads no profile (combat = nil)": (
        WEAPON,
        "\tlocal combat = if profile ~= nil then profile.combat else nil\n\tlocal override = state.gearOverride[player]\n\tlocal overrideTier",
        "\tlocal combat = nil\n\tlocal override = state.gearOverride[player]\n\tlocal overrideTier",
    ),
    "l3fix2 F1: the bar reads no profile (combat = nil)": (
        WEAPON,
        "\tlocal combat = if profile ~= nil then profile.combat else nil\n\tlocal shooter = state.shooters[player]",
        "\tlocal combat = nil\n\tlocal shooter = state.shooters[player]",
    ),
    "l3fix2 F1: the bar ignores the shooter's live pair": (
        WEAPON,
        "\tlocal held = if shooter ~= nil\n\t\tthen shooter.loadout",
        "\tlocal held = if false\n\t\tthen shooter.loadout",
    ),
    "l3fix2 F1: the bar's raw-override early return comes back": (
        WEAPON,
        "\tlocal profile = DataService.GetState(player)\n\tlocal combat = if profile ~= nil then profile.combat else nil\n\tlocal shooter = state.shooters[player]",
        "\tlocal raw = state.gearOverride[player]\n\tif raw ~= nil then\n\t\treturn table.clone(raw.gear), table.clone(raw.ascension)\n\tend\n"
        "\tlocal profile = DataService.GetState(player)\n\tlocal combat = if profile ~= nil then profile.combat else nil\n\tlocal shooter = state.shooters[player]",
    ),
    "l3fix2 F1: a hit's raw override tier returned early": (
        WEAPON,
        "\tlocal tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)\n",
        "\tif overrideTier ~= nil then\n\t\treturn Armory.DamageScale(armoryConfig, overrideTier, level, ability)\n\tend\n"
        "\tlocal tier = Armory.StrikeTier(armoryConfig, combat, family, overrideTier)\n",
    ),
    "l3fix2 F1: a hit takes the other slot's Ascension": (
        WEAPON,
        '\tlocal level = if slot == "melee"\n\t\tthen ascension.melee\n\t\telseif slot == "ranged" then ascension.ranged',
        '\tlocal level = if slot == "melee"\n\t\tthen ascension.ranged\n\t\telseif slot == "ranged" then ascension.melee',
    ),
    "l3fix2 F1: a load runs no migration": (HUB_DATA, "\trunMigrations(profile.Data, player)\n", ""),
    "l3fix2 F1: U resolves no level": (
        WAVE_SERVICE,
        "\t\tlocal level = if combatConfig ~= nil and map ~= nil\n",
        "\t\tlocal level = if false\n",
    ),
    "l3fix2 F1: U stars and pays Normal": (
        DEBUG_SERVICE,
        "\tlocal difficulty = ladder.starDifficulty\n",
        '\tlocal difficulty = "normal"\n',
    ),
    "l3fix2 F1: the dungeon's Power with no weapons": (
        MAIN_SERVER,
        "\t\t\t\tif provingConfig ~= nil then provingConfig.weapons else nil,\n",
        "\t\t\t\tnil,\n",
    ),
    "l3fix2 F1: the hub's Power with no weapons": (
        HUB_ECONOMY,
        "\t\tif provingConfig ~= nil then provingConfig.weapons else nil,\n",
        "\t\tnil,\n",
    ),
    # F1: one entry for each other new count, in gearOf.
    "l3fix2 F1: the bar is the range's T1 everywhere": (
        WEAPON,
        'if state.mode == "range" or armoryConfig == nil then',
        "if true then",
    ),
    "l3fix2 F1: the bar reads nobody's profile": (
        WEAPON,
        "\tlocal profile = DataService.GetState(player)\n\tlocal combat = if profile ~= nil then profile.combat else nil\n\tlocal shooter",
        "\tlocal profile = nil\n\tlocal combat = if profile ~= nil then profile.combat else nil\n\tlocal shooter",
    ),
    "l3fix2 F1: the bar ignores the Studio override": (
        WEAPON,
        "\tlocal gear = if override ~= nil then override.gear else nil\n",
        "\tlocal gear = nil\n",
    ),
    "l3fix2 F1: the bar ignores the profile's Ascension": (
        WEAPON,
        "local rangedOverride = if gear ~= nil then gear.ranged else nil\n\tlocal ascension = if override ~= nil\n"
        "\t\tthen override.ascension\n\t\telseif combat ~= nil then combat.ascension",
        "local rangedOverride = if gear ~= nil then gear.ranged else nil\n\tlocal ascension = if override ~= nil\n"
        "\t\tthen override.ascension\n\t\telseif false then combat.ascension",
    ),
    "l3fix2 F1: the bar's ranged slot takes the melee Ascension": (
        WEAPON,
        "\t}, { melee = ascension.melee, ranged = ascension.ranged }\n",
        "\t}, { melee = ascension.melee, ranged = ascension.melee }\n",
    ),
    # In damageScale.
    "l3fix2 F1: no hit is ever scaled": (
        WEAPON,
        "\tif armoryConfig == nil then\n\t\treturn 1\n\tend\n\tlocal def = familyDef(Tuning.Get(), family)",
        "\tif true then\n\t\treturn 1\n\tend\n\tlocal def = familyDef(Tuning.Get(), family)",
    ),
    "l3fix2 F1: every hit's slot is melee": (
        WEAPON,
        '\tlocal slot = if def ~= nil then def.slot else ""\n',
        '\tlocal slot = "melee"\n',
    ),
    "l3fix2 F1: a hit ignores the Studio override": (
        WEAPON,
        "\tlocal overrideTier: number? = nil\n\tif override ~= nil then\n",
        "\tlocal overrideTier: number? = nil\n\tif false then\n",
    ),
    "l3fix2 F1: a hit ignores the profile's Ascension": (
        WEAPON,
        "\t\telseif combat ~= nil then combat.ascension\n\t\telse CONST.NO_ASCENSION\n\tlocal level",
        "\t\telseif false then combat.ascension\n\t\telse CONST.NO_ASCENSION\n\tlocal level",
    ),
    # In WaveService.GrantStars (and F3).
    "l3fix2 F1: U's stars go to a table nobody keeps": (
        WAVE_SERVICE,
        "\tlocal stars = starsOf(player.UserId)\n\tlocal new = 0\n",
        "\tlocal stars = {}\n\tlocal new = 0\n",
    ),
    "l3fix2 F3: U awards the star before the level resolves (the order before F3)": (
        WAVE_SERVICE,
        "\t\tif level == nil then\n\t\t\tcontinue\n\t\tend\n\t\tif not StageFlow.Award(stars, levelId, difficulty) then\n\t\t\tcontinue\n\t\tend\n",
        "\t\tif not StageFlow.Award(stars, levelId, difficulty) then\n\t\t\tcontinue\n\t\tend\n\t\tif level == nil then\n\t\t\tcontinue\n\t\tend\n",
    ),
    "l3fix2 F3: U awards a star whose level does not resolve": (
        WAVE_SERVICE,
        "\t\tif level == nil then\n\t\t\tcontinue\n\t\tend\n\t\tif not StageFlow.Award(stars, levelId, difficulty) then",
        "\t\tif not StageFlow.Award(stars, levelId, difficulty) then",
    ),
    "l3fix2 F1: U keeps no grant for the notice": (
        WAVE_SERVICE,
        "\t\tif grant ~= nil then\n\t\t\ttable.insert(grants, grant)\n\t\tend\n",
        "",
    ),
    "l3fix2 F1: U pays only Normal's rewards": (
        WAVE_SERVICE,
        "\t\tnew += 1\n",
        '\t\tnew += 1\n\t\tif difficulty ~= "normal" then\n\t\t\tcontinue\n\t\tend\n',
    ),
    # In DebugService's grantStar.
    "l3fix2 F1: the star lever always finds no ladder": (
        DEBUG_SERVICE,
        'local ladder = if armoryConfig ~= nil then armoryConfig.ladder else nil\n\tif ladder == nil then\n\t\twarn("[DebugService] grantStar',
        'local ladder = if armoryConfig ~= nil then armoryConfig.ladder else nil\n\tif true then\n\t\twarn("[DebugService] grantStar',
    ),
    "l3fix2 F1: the star lever names no level": (
        DEBUG_SERVICE,
        "\telseif Catalog.GetLevelFile(which) ~= nil then\n\t\ttable.insert(levelIds, which)\n",
        "\telseif false then\n\t\ttable.insert(levelIds, which)\n",
    ),
    "l3fix2 F1: the star attribute stars nobody": (
        DEBUG_SERVICE,
        "local targets: { Player } = if player ~= nil then { player } else UnlockService.Admitted()\n\t-- What the new stars",
        "local targets: { Player } = if player ~= nil then { player } else {}\n\t-- What the new stars",
    ),
    "l3fix2 F1: the star lever's call asks Normal": (
        DEBUG_SERVICE,
        "local _new, grants = WaveService.GrantStars(target, levelIds, difficulty)",
        'local _new, grants = WaveService.GrantStars(target, levelIds, "normal")',
    ),
    "l3fix2 F1: the star lever stops before its first player": (
        DEBUG_SERVICE,
        "\tlocal valor = 0\n\tfor _, target in targets do\n",
        "\tlocal valor = 0\n\tif #targets > 0 then\n\t\treturn\n\tend\n\tfor _, target in targets do\n",
    ),
    # In Main's sendSnapshot.
    "l3fix2 F1: the dungeon's Power reads no Armory.json": (
        MAIN_SERVER,
        "\tlocal armoryConfig = Catalog.GetArmoryConfig()\n\t-- L3-6, R7",
        "\tlocal armoryConfig = nil\n\t-- L3-6, R7",
    ),
    "l3fix2 F1: the dungeon's Power reads no ProvingGrounds.json": (
        MAIN_SERVER,
        "\tlocal provingConfig = Catalog.GetProvingGroundsConfig()\n\tlocal snapshot: Types.Snapshot = {",
        "\tlocal provingConfig = nil\n\tlocal snapshot: Types.Snapshot = {",
    ),
    "l3fix2 F1: the dungeon's Power with no starters": (
        MAIN_SERVER,
        '\t\t\t\tif provingConfig ~= nil then provingConfig.loadout else { melee = "", ranged = "" }\n',
        '\t\t\t\t{ melee = "", ranged = "" }\n',
    ),
    "l3fix2 F1: the dungeon's Snapshot returns before it is sent": (
        MAIN_SERVER,
        '\t\twelcomeBack = nil,\n\t}\n\tRemoteService.FireClient(player, "StateChanged", snapshot)\n',
        '\t\twelcomeBack = nil,\n\t}\n\tif snapshot.gearPower > 64 then\n\t\treturn\n\tend\n\tRemoteService.FireClient(player, "StateChanged", snapshot)\n',
    ),
    # In EconomyService's computeGearPower.
    "l3fix2 F1: the hub's Power is always 0": (
        HUB_ECONOMY,
        "\tif armoryConfig == nil then\n\t\treturn 0\n\tend\n\tlocal provingConfig",
        "\tif true then\n\t\treturn 0\n\tend\n\tlocal provingConfig",
    ),
    "l3fix2 F1: the hub's Power reads no ProvingGrounds.json": (
        HUB_ECONOMY,
        "\tlocal provingConfig = Catalog.GetProvingGroundsConfig()\n\treturn Armory.SavedPower(",
        "\tlocal provingConfig = nil\n\treturn Armory.SavedPower(",
    ),
    "l3fix2 F1: the hub's Power with no starters": (
        HUB_ECONOMY,
        '\t\tif provingConfig ~= nil then provingConfig.loadout else { melee = "", ranged = "" }\n',
        '\t\t{ melee = "", ranged = "" }\n',
    ),
    "l3fix2 F1: the hub's Power is 0 once a family is found": (
        HUB_ECONOMY,
        "\tlocal provingConfig = Catalog.GetProvingGroundsConfig()\n\treturn Armory.SavedPower(",
        "\tlocal provingConfig = Catalog.GetProvingGroundsConfig()\n\tif next(state.combat.families or {}) ~= nil then\n"
        "\t\treturn 0\n\tend\n\treturn Armory.SavedPower(",
    ),
    # In DataService's attemptLoad.
    "l3fix2 F1: a load migrates only a profile with no version": (
        HUB_DATA,
        "\trunMigrations(profile.Data, player)\n",
        "\tif profile.Data.version == nil then\n\trunMigrations(profile.Data, player)\n\tend\n",
    ),
    "l3fix2 F1: a load returns before it migrates": (
        HUB_DATA,
        "\tprofile:AddUserId(player.UserId) -- GDPR right-to-erasure association\n",
        "\tprofile:AddUserId(player.UserId) -- GDPR right-to-erasure association\n\tif profile.Data.version ~= nil then\n"
        "\t\tprofiles[player] = profile\n\t\treturn profile.Data\n\tend\n",
    ),
    # F1: the count-0 rules in the review's other spellings, each beside lines that all still stand.
    "l3fix2 F1: DebugService spells the wildcard '*'": (
        DEBUG_SERVICE,
        "\tlocal levelIds: { string } = {}\n\tif which == Unlocks.ALL_STARS then",
        "\tlocal levelIds: { string } = {}\n\tif '*' == which then\n\t\twhich = Unlocks.ALL_STARS\n\tend\n\tif which == Unlocks.ALL_STARS then",
    ),
    "l3fix2 F1: the hub spells the wildcard \"*\", the compare reversed": (
        HUB_ARMORY,
        "\tlocal family, tier = Unlocks.TierLever(value)\n",
        '\tif "*" == value then\n\t\treturn\n\tend\n\tlocal family, tier = Unlocks.TierLever(value)\n',
    ),
    "l3fix2 F1: EconomyService reads the frozen gear by key": (
        HUB_ECONOMY,
        "local function computeGearPower(state: Types.PlayerState): number\n",
        'local function computeGearPower(state: Types.PlayerState): number\n\tlocal _frozen = state.combat["gear"]\n',
    ),
    "l3fix2 F1: DataService steps a profile through a local alias": (
        HUB_DATA,
        "local function runMigrations(state: Types.PlayerState, player: Player): ()\n",
        "local function runMigrations(state: Types.PlayerState, player: Player): ()\n"
        "\tlocal steps = ProfileSchema.Migrations\n\tlocal _ = steps[state.version]\n",
    ),
    "l3fix2 F1: Main reads the bar by key": (
        MAIN_SERVER,
        "\tlocal provingConfig = Catalog.GetProvingGroundsConfig()\n\tlocal snapshot",
        '\tlocal provingConfig = Catalog.GetProvingGroundsConfig()\n\tlocal _bar = WeaponService["GearOf"](player)\n\tlocal snapshot',
    ),
    # F2: Unlocks.ApplyFirstClear (tests_l3.luau "l3 firstClearTests").
    "l3fix2 F2: ApplyFirstClear writes a family no weapons config names": (UNLOCKS, "\t\tand weapons[family] ~= nil\n", ""),
    "l3fix2 F2: ApplyFirstClear gives an owned family again (and a starter)": (
        UNLOCKS,
        "\t\tand not Unlocks.OwnsFamily(combat.families, family, starters)\n",
        "",
    ),
    "l3fix2 F2: ApplyFirstClear writes no family": (UNLOCKS, "\t\tfamilies[family] = true\n", ""),
    "l3fix2 F2: ApplyFirstClear says it gave no family": (UNLOCKS, "\t\tgiven.family = family\n", ""),
    "l3fix2 F2: ApplyFirstClear adds no Valor": (UNLOCKS, "\t\tcombat.valor += valor\n", ""),
    "l3fix2 F2: ApplyFirstClear says it gave no Valor": (UNLOCKS, "\t\tgiven.valor = valor\n", ""),
    "l3fix2 F2: ApplyFirstClear pays a fractional Valor": (
        UNLOCKS,
        'if type(valor) == "number" and valor > 0 and valor % 1 == 0 then',
        'if type(valor) == "number" and valor > 0 then',
    ),
    "l3fix2 F2: ApplyFirstClear pays a negative Valor": (
        UNLOCKS,
        'if type(valor) == "number" and valor > 0 and valor % 1 == 0 then',
        'if type(valor) == "number" and valor ~= 0 and valor % 1 == 0 then',
    ),
    "l3fix2 F2: ApplyFirstClear reads a reward that is no table": (
        UNLOCKS,
        '\tif type(reward) ~= "table" then\n\t\treturn given\n\tend\n',
        "",
    ),
    "l3fix2 F2: ApplyFirstClear makes no families map": (
        UNLOCKS,
        "local families: { [string]: boolean } = combat.families or {}",
        "local families: { [string]: boolean } = combat.families :: any",
    ),
    "l3fix2 F2: ApplyFirstClear indexes weapons it was not given": (UNLOCKS, '\t\tand type(weapons) == "table"\n', ""),
    # F2: the dungeon's call (UnlockService.GrantFirstClear).
    "l3fix2 F2: the dungeon's first clear writes a copy of the profile": (
        UNLOCK_SERVICE,
        "\tlocal combat = profile.combat\n\tlocal given = Unlocks.ApplyFirstClear",
        "\tlocal combat = table.clone(profile.combat)\n\tlocal given = Unlocks.ApplyFirstClear",
    ),
    "l3fix2 F2: the dungeon's first clear knows no weapons": (
        UNLOCK_SERVICE,
        "local given = Unlocks.ApplyFirstClear(combat, reward, weapons(), starters())",
        "local given = Unlocks.ApplyFirstClear(combat, reward, nil, starters())",
    ),
    "l3fix2 F2: the dungeon's first clear answers nothing for Valor only": (
        UNLOCK_SERVICE,
        "\tif given.family == nil and given.valor == 0 then\n",
        "\tif given.family == nil then\n",
    ),
    "l3fix2 F2: the dungeon's first clear resends no wallet": (
        UNLOCK_SERVICE,
        "\tArenaService.SendSnapshot(player)\n\treturn given\n",
        "\treturn given\n",
    ),
    "l3fix2 F2: a family's first clear returns before it is written": (
        UNLOCK_SERVICE,
        "\tlocal given = Unlocks.ApplyFirstClear(combat, reward, weapons(), starters())\n",
        "\tif reward.family ~= nil then\n\t\treturn nil\n\tend\n\tlocal given = Unlocks.ApplyFirstClear(combat, reward, weapons(), starters())\n",
    ),
    # F2: the hub's star lever (ArmoryService.grantStarTo, fileFirstClear).
    "l3fix2 F2: the hub's star lever names no single level": (
        HUB_ARMORY,
        "\telseif built[value] == true then\n\t\tlevels = { value }\n",
        "\telseif false then\n\t\tlevels = { value }\n",
    ),
    "l3fix2 F2: the hub's star lever pays with no weapons": (
        HUB_ARMORY,
        "\tlocal weapons, starters = weaponsConfig()\n\tlocal stars = Unlocks.StarsOf(state.combat)\n",
        "\tlocal _, starters = weaponsConfig()\n\tlocal weapons = nil\n\tlocal stars = Unlocks.StarsOf(state.combat)\n",
    ),
    "l3fix2 F2: the hub's star lever pays an old star again": (
        HUB_ARMORY,
        "\t\tif row[difficulty] == true then\n\t\t\tcontinue\n\t\tend\n",
        "",
    ),
    "l3fix2 F2: the hub's star lever reads the Normal reward": (
        HUB_ARMORY,
        "local reward = fileFirstClear(levelId, difficulty)",
        'local reward = fileFirstClear(levelId, "normal")',
    ),
    "l3fix2 F2: the hub's star lever pays nothing": (
        HUB_ARMORY,
        "local grant = Unlocks.ApplyFirstClear(state.combat, reward, weapons, starters)",
        "local grant = { family = nil :: string?, valor = 0 }",
    ),
    "l3fix2 F2: the hub's notice names no Valor": (HUB_ARMORY, "\t\tvalor += grant.valor\n", ""),
    "l3fix2 F2: the hub's star lever marks nothing for the Delta": (
        HUB_ARMORY,
        "\tEconomyService.MarkDirty(player, { combat = true })\n\tlocal given = if #gifts",
        "\tlocal given = if #gifts",
    ),
    "l3fix2 F2: the hub's star lever stops after its first level": (
        HUB_ARMORY,
        "\t\tvalor += grant.valor\n\tend\n",
        "\t\tvalor += grant.valor\n\t\tbreak\n\tend\n",
    ),
    "l3fix2 F2: the hub reads the reward of no difficulty": (
        HUB_ARMORY,
        '\tlocal scales: any = if type(difficulties) == "table" then difficulties[difficulty] else nil\n',
        "\tlocal scales: any = nil\n",
    ),
    "l3fix2 F2: the hub reads no file's reward": (
        HUB_ARMORY,
        "\tlocal file = Catalog.GetLevelFile(levelId)\n",
        '\tif levelId ~= "" then\n\t\treturn nil\n\tend\n\tlocal file = Catalog.GetLevelFile(levelId)\n',
    ),
    # F5: the hub's client (UIController), read as text too.
    "l3fix2 F5: the late families replay no push": (
        HUB_UI,
        "\t\tthen\n\t\t\tpushArmory(current.state.combat)\n",
        "\t\tthen\n\t\t\tlocal _ = current\n",
    ),
    "l3fix2 F5: the families never count as late": (
        HUB_UI,
        "\t\tlocal waiting = provingConfig == nil\n",
        "\t\tlocal waiting = false\n",
    ),
    "l3fix2 F5: a push before the families asks for them no more": (
        HUB_UI,
        "\t\t\trefreshCombatKeys()\n\t\t\treturn\n",
        "\t\t\treturn\n",
    ),
}
MUTATIONS.update(L3_FIX2_MUTATIONS)

# L3 W2, the models in the game (docs/prompts/l3-w2-contract.md, L3-46 to L3-56): the pure
# WeaponLook (tests_l3_w2.luau's built and shipped cases) and the contract's text checks T1 to T14
# (run_harness.py L3W2_LINES, L3W2_PATTERNS, L3W2_ORDER), from the luau-engineer. The text-read
# files are copied into every mutant root, the client ones included: only their counts can catch
# their mutants. Run them alone with `mutate.py <root> <luau> l3w2`.
LOOK = "src/shared/WeaponLook.luau"
RANGE_SERVICE = "src/combat/server/Services/RangeService.luau"
HELD_WEAPONS = "src/combat/client/Controllers/HeldWeapons.luau"
WEAPON_CONTROLLER = "src/combat/client/Controllers/WeaponController.luau"
FLAME_FX = "src/combat/client/Controllers/FlameFx.luau"
ABILITY_SHARED = "src/combat/client/Controllers/AbilityFx/Shared.luau"
MAG_DUMP = "src/combat/client/Controllers/AbilityFx/MagDump.luau"
ARMORY_STAGE = "src/client/UI/ArmoryStage.luau"
ARMORY_SCREEN = "src/client/UI/ArmoryScreen.luau"
FILES += [
    LOOK,
    "src/shared/Config/WeaponModels.json",
    RANGE_SERVICE,
    HELD_WEAPONS,
    WEAPON_CONTROLLER,
    FLAME_FX,
    ABILITY_SHARED,
    MAG_DUMP,
    ARMORY_STAGE,
    ARMORY_SCREEN,
]
L3W2_MUTATIONS = {
    # WeaponLook: names, entries, points, icons, the attributes and the faults (L3-48).
    "l3w2: ModelName does not capitalise": (
        LOOK,
        "return string.upper(string.sub(family, 1, 1)) .. string.sub(family, 2)",
        "return family",
    ),
    "l3w2: an attribute takes another name": (LOOK, 'held = "WeaponHeld",', 'held = "WeaponSlot",'),
    "l3w2: finite takes a NaN": (LOOK, 'type(value) == "number" and value == value and', 'type(value) == "number" and'),
    "l3w2: finite takes +inf": (LOOK, "value == value and value ~= math.huge and", "value == value and"),
    "l3w2: finite takes -inf": (LOOK, "value ~= math.huge and value ~= -math.huge", "value ~= math.huge"),
    "l3w2: a point of four numbers is three": (LOOK, "and #value == 3", "and #value >= 3"),
    "l3w2: a point's third number is not checked": (LOOK, "\t\tand finite(value[3])\n", ""),
    "l3w2: Def takes another family's model": (LOOK, "if def.model ~= expected then", "if false then"),
    "l3w2: Def needs no holster": (LOOK, '{ "grip", "tip", "holster" }', '{ "grip", "tip" }'),
    "l3w2: Def takes malformed bounds": (
        LOOK,
        'if type(bounds) ~= "table" or not triple(bounds.min) or not triple(bounds.max) then',
        'if type(bounds) ~= "table" then',
    ),
    "l3w2: Def takes min above max": (LOOK, "if bounds.min[axis] > bounds.max[axis] then", "if false then"),
    "l3w2: Def refuses a flat model": (
        LOOK,
        "if bounds.min[axis] > bounds.max[axis] then",
        "if bounds.min[axis] >= bounds.max[axis] then",
    ),
    "l3w2: Def checks the bounds on two axes": (
        LOOK,
        "\tfor axis = 1, 3 do\n\t\tif bounds.min[axis]",
        "\tfor axis = 1, 2 do\n\t\tif bounds.min[axis]",
    ),
    "l3w2: Def answers a broken entry": (
        LOOK,
        "if models == nil or defProblem(models, family) ~= nil then",
        "if models == nil then",
    ),
    "l3w2: Point takes a malformed point": (LOOK, "\tif not triple(point) then\n\t\treturn nil\n", "\tif point == nil then\n\t\treturn nil\n"),
    "l3w2: Point answers the tip for every name": (
        LOOK,
        'local point = if type(points) == "table" then points[name] else nil',
        'local point = if type(points) == "table" then points.tip else nil',
    ),
    "l3w2: IconId takes a negative id": (LOOK, "and imageId > 0 and", "and imageId ~= 0 and"),
    "l3w2: IconId takes a fraction": (LOOK, " and imageId % 1 == 0", ""),
    "l3w2: IconId compares a string": (LOOK, "if finite(imageId) and imageId > 0", "if imageId ~= nil and imageId > 0"),
    "l3w2: IconId reads the Weapons set whatever the folder": (
        LOOK,
        'type(folder) == "string" then icons[folder] else nil',
        'type(folder) == "string" then icons.Weapons else nil',
    ),
    "l3w2: IconId keys the set by family": (
        LOOK,
        'local icon = if type(set) == "table" then set[def.model] else nil',
        'local icon = if type(set) == "table" then set[family] else nil',
    ),
    "l3w2: IconId answers for a broken entry": (
        LOOK,
        'if def == nil or models == nil or type(config) ~= "table" then',
        'if models == nil or type(config) ~= "table" then',
    ),
    "l3w2: Values passes any held word": (
        LOOK,
        'values[ATTRIBUTES.held] = if held == "ranged" then "ranged" else "melee"',
        "values[ATTRIBUTES.held] = held",
    ),
    "l3w2: Values reads any other word as ranged": (
        LOOK,
        'values[ATTRIBUTES.held] = if held == "ranged" then "ranged" else "melee"',
        'values[ATTRIBUTES.held] = if held == "melee" then "melee" else "ranged"',
    ),
    "l3w2: Values writes the ranged family as melee": (
        LOOK,
        "values[ATTRIBUTES.melee] = loadout.melee",
        "values[ATTRIBUTES.melee] = loadout.ranged",
    ),
    "l3w2: Read takes an empty family": (LOOK, 'and value ~= "" then value else nil', "then value else nil"),
    "l3w2: Read takes a number": (
        LOOK,
        'return if type(value) == "string" and value ~= "" then value else nil',
        'return if value ~= nil and value ~= "" then value else nil',
    ),
    "l3w2: Read passes any held word": (
        LOOK,
        'if held == "melee" or held == "ranged" then held else nil',
        "held",
    ),
    "l3w2: Read asks for the melee attribute twice": (
        LOOK,
        "familyOf(get(ATTRIBUTES.ranged)),",
        "familyOf(get(ATTRIBUTES.melee)),",
    ),
    "l3w2: Problems with no file says nothing": (
        LOOK,
        '\t\ttable.insert(problems, "WeaponModels.json has no families: every hand stays empty")\n',
        "",
    ),
    "l3w2: Problems takes an empty folder": (
        LOOK,
        'if type(config.folder) ~= "string" or config.folder == "" then',
        'if type(config.folder) ~= "string" then',
    ),
    "l3w2: Problems takes a family with no entry": (
        LOOK,
        "local problem = defProblem(config, family)",
        "local problem = if config.families[family] == nil then defProblem(config, family) else nil",
    ),
    "l3w2: Problems takes an extra family": (LOOK, "\t\tif weapons[family] == nil then\n", "\t\tif false then\n"),
    "l3w2: Problems takes a grip off the origin": (
        LOOK,
        "if grip ~= nil and (grip.X ~= 0 or grip.Y ~= 0 or grip.Z ~= 0) then",
        "if false then",
    ),
    "l3w2: Problems reads the grip on two axes": (
        LOOK,
        "(grip.X ~= 0 or grip.Y ~= 0 or grip.Z ~= 0)",
        "(grip.Y ~= 0 or grip.Z ~= 0)",
    ),
    "l3w2: Problems takes a malformed extra": (
        LOOK,
        "\t\t\tif point == nil then\n\t\t\t\ttable.insert(problems,",
        "\t\t\tif false then\n\t\t\t\ttable.insert(problems,",
    ),
    "l3w2: Problems takes a point outside its bounds": (LOOK, "elseif not inside(point, def.bounds) then", "elseif false then"),
    "l3w2: no slack at the bounds": (LOOK, "local BOUNDS_SLACK = 0.01", "local BOUNDS_SLACK = 0"),
    "l3w2: the slack swallows a real fault": (LOOK, "local BOUNDS_SLACK = 0.01", "local BOUNDS_SLACK = 0.1"),
    "l3w2: inside reads the low side only": (
        LOOK,
        "if value < bounds.min[axis] - BOUNDS_SLACK or value > bounds.max[axis] + BOUNDS_SLACK then",
        "if value < bounds.min[axis] - BOUNDS_SLACK then",
    ),
    "l3w2: inside reads two axes": (
        LOOK,
        "local coordinates = { point.X, point.Y, point.Z }\n\tfor axis = 1, 3 do",
        "local coordinates = { point.X, point.Y, point.Z }\n\tfor axis = 1, 2 do",
    ),
    # T1: the one writer.
    "l3w2 T1: showWeapons writes the starting slot": (
        WEAPON,
        "WeaponLook.Values(shooter.loadout, shooter.held)",
        'WeaponLook.Values(shooter.loadout, "melee")',
    ),
    "l3w2 T1: showWeapons writes only on the live character": (
        WEAPON,
        "local target = character or shooter.player.Character",
        "local target = shooter.player.Character",
    ),
    "l3w2 T1: showWeapons writes nothing": (WEAPON, "\t\ttarget:SetAttribute(name, value)\n", "\t\tlocal _ = { name, value }\n"),
    "l3w2 T1: showWeapons returns early": (
        WEAPON,
        "\tlocal target = character or shooter.player.Character\n",
        '\tif shooter.held == "ranged" then\n\t\treturn\n\tend\n\tlocal target = character or shooter.player.Character\n',
    ),
    # T2: every fresh character.
    "l3w2 T2: a fresh character shows nothing": (
        WEAPON,
        "\t\tresetAir(shooter)\n\t\tshowWeapons(shooter, character)\n",
        "\t\tresetAir(shooter)\n",
    ),
    "l3w2 T2: shown on the old character": (
        WEAPON,
        "\t\tshowWeapons(shooter, character)\n",
        "\t\tshowWeapons(shooter, nil)\n",
    ),
    "l3w2 T2: PrepareCharacter returns before it shows": (
        WEAPON,
        "\tlocal shooter = state.shooters[player]\n\tif shooter ~= nil then\n\t\tresetAir(shooter)\n",
        "\tlocal shooter = state.shooters[player]\n\tif shooter == nil then\n\t\treturn\n\tend\n"
        "\tif shooter ~= nil then\n\t\tresetAir(shooter)\n",
    ),
    "l3w2 T2: the range prepares no character": (RANGE_SERVICE, "\tWeaponService.PrepareCharacter(player, character)\n", ""),
    "l3w2 T2: a mission's later characters are not prepared": (
        WAVE_SERVICE,
        "ArenaService.SetCharacterHook(WeaponService.PrepareCharacter)",
        "ArenaService.SetCharacterHook(function() end)",
    ),
    # T3: every loadout change.
    "l3w2 T3: a family change shows nothing": (
        WEAPON,
        "\tshowWeapons(shooter, nil)\n\ttuneStateFor(shooter)\n",
        "\ttuneStateFor(shooter)\n",
    ),
    "l3w2 T3: only a new family shows": (
        WEAPON,
        "\tshowWeapons(shooter, nil)\n\ttuneStateFor(shooter)\n\tif previous ~= family then\n",
        "\ttuneStateFor(shooter)\n\tif previous ~= family then\n\t\tshowWeapons(shooter, nil)\n",
    ),
    "l3w2 T3: shown before the pair is written": (
        WEAPON,
        "\tlocal previous = slotFamily(shooter, slot)\n\tif slot == \"melee\" then\n\t\tshooter.loadout.melee = family\n",
        "\tlocal previous = slotFamily(shooter, slot)\n\tshowWeapons(shooter, nil)\n"
        "\tif slot == \"melee\" then\n\t\tshooter.loadout.melee = family\n",
    ),
    # T4, T5: an accepted attack and draw.
    "l3w2 T4: an attack notes nothing": (WEAPON, "\tshooter.lastSeq[slot] = seq\n\tnoteHeld(shooter, slot)\n", "\tshooter.lastSeq[slot] = seq\n"),
    "l3w2 T4: an attack notes melee": (
        WEAPON,
        "\tshooter.lastSeq[slot] = seq\n\tnoteHeld(shooter, slot)\n",
        '\tshooter.lastSeq[slot] = seq\n\tnoteHeld(shooter, "melee")\n',
    ),
    "l3w2 T4: a refused attack is noted": (
        WEAPON,
        "\tif seq <= (shooter.lastSeq[slot] or -1) then\n",
        "\tnoteHeld(shooter, slot)\n\tif seq <= (shooter.lastSeq[slot] or -1) then\n",
    ),
    "l3w2 T5: a draw notes nothing": (WEAPON, "\tshooter.drawWeapon = weapon\n\tnoteHeld(shooter, slot)\nend", "\tshooter.drawWeapon = weapon\nend"),
    "l3w2 T5: a draw notes ranged whatever its slot": (
        WEAPON,
        "\tshooter.drawWeapon = weapon\n\tnoteHeld(shooter, slot)\nend",
        '\tshooter.drawWeapon = weapon\n\tnoteHeld(shooter, "ranged")\nend',
    ),
    "l3w2 T5: a second writer of held": (
        WEAPON,
        "\tshooter.drawWeapon = weapon\n\tnoteHeld(shooter, slot)\nend",
        "\tshooter.drawWeapon = weapon\n\tshooter.held = slot\nend",
    ),
    # T6: an accepted cast.
    "l3w2 T6: a cast notes nothing": (ABILITY, "\tWeaponService.NoteHeld(player, slotName)\n", ""),
    "l3w2 T6: a cast notes melee": (
        ABILITY,
        "WeaponService.NoteHeld(player, slotName)",
        'WeaponService.NoteHeld(player, "melee")',
    ),
    # Re-aimed by the fix round's S6: the note now stands before the effect is sent, so a note
    # before an earlier refusal (the aim's) is the one a refused cast would show.
    "l3w2 fix S6: a cast refused for its aim is noted": (
        ABILITY,
        "\tlocal root = WeaponService.RootOf(player)\n",
        "\tWeaponService.NoteHeld(player, slotName)\n\tlocal root = WeaponService.RootOf(player)\n",
    ),
    # T7: shown only on a change.
    "l3w2 T7: noteHeld shows every time": (WEAPON, "\tif shooter.held == slot then\n\t\treturn\n\tend\n", ""),
    "l3w2 T7: noteHeld forgets the slot": (
        WEAPON,
        "\tshooter.held = slot\n\tshowWeapons(shooter, nil)\nend",
        "\tshowWeapons(shooter, nil)\nend",
    ),
    "l3w2 T7: noteHeld shows nothing": (
        WEAPON,
        "\tshooter.held = slot\n\tshowWeapons(shooter, nil)\nend",
        "\tshooter.held = slot\nend",
    ),
    "l3w2 T7: NoteHeld takes any slot word": (WEAPON, ' or (slot ~= "melee" and slot ~= "ranged")', ""),
    "l3w2 T7: NoteHeld notes ranged for every cast": (
        WEAPON,
        'noteHeld(shooter, if slot == "melee" then "melee" else "ranged")',
        'noteHeld(shooter, "ranged")',
    ),
    "l3w2 T7: a new shooter holds ranged": (WEAPON, '\t\theld = "melee",\n', '\t\theld = "ranged",\n'),
    "l3w2 T3: a second writer of the pair": (
        WEAPON,
        "\tshooter.loadout.variants[family] = key\n",
        "\tshooter.loadout.variants[family] = key\n\tshooter.loadout.melee = shooter.loadout.melee\n",
    ),
    # T8: no hit reads the look.
    "l3w2 T8: damageScale reads the slot in use": (
        WEAPON,
        "return Armory.DamageScale(armoryConfig, tier, level, ability)",
        "return Armory.DamageScale(armoryConfig, tier, level, ability)"
        ' * (if (state.shooters[player] :: any).held == "ranged" then 1 else 1)',
    ),
    "l3w2 T8: meleeOrigin reads the slot in use": (
        WEAPON,
        "local allowed = claimSlack(shooter, root, config.controls.meleeOriginPad, config)",
        "local allowed = claimSlack(shooter, root, config.controls.meleeOriginPad, config)"
        ' + (if shooter.held == "melee" then 0 else 0)',
    ),
    "l3w2 T8: aimAllowed reads the look": (
        WEAPON,
        "local anchor = if head ~= nil and head:IsA(\"BasePart\") then head.Position else root.Position\n",
        "local anchor = if head ~= nil and head:IsA(\"BasePart\") then head.Position else root.Position\n"
        "\tlocal _look = WeaponLook.ATTRIBUTES\n",
    ),
    "l3w2 T8: claimSlack notes the slot": (
        WEAPON,
        "\tlocal window = math.max(shooting.originLagMaxSeconds, 0)\n",
        "\tlocal window = math.max(shooting.originLagMaxSeconds, 0)\n\tnoteHeld(shooter, \"melee\")\n",
    ),
    "l3w2 T8: resolveMelee reads the slot in use": (
        WEAPON,
        "local step = shooter.combo[weapon] or 0",
        'local step = shooter.combo[weapon] or (if shooter.held == "melee" then 0 else 0)',
    ),
    "l3w2 T8: resolveRanged shows the weapons": (
        WEAPON,
        "\tlocal seed = newSeed(shooter, false)\n",
        "\tlocal seed = newSeed(shooter, false)\n\tshowWeapons(shooter, nil)\n",
    ),
    "l3w2 T8: strike reads the look": (
        WEAPON,
        "\tStrikeTally.Add(tally, id, dealt, crit, killed, verdict)\n",
        "\tStrikeTally.Add(tally, id, dealt, crit, killed, verdict)\n\tlocal _look = WeaponLook.ATTRIBUTES\n",
    ),
    # T9: another player's arm.
    "l3w2 T9: no arm moves": (FEEDBACK, "\t\tWeaponController.SwingOther(strike.userId, strike.step or 1)\n", ""),
    "l3w2 T9: the arm always swings step 1": (
        FEEDBACK,
        "WeaponController.SwingOther(strike.userId, strike.step or 1)",
        "WeaponController.SwingOther(strike.userId, 1)",
    ),
    "l3w2 T9: the arm swings for my own strike too": (
        FEEDBACK,
        "\t\tWeaponController.SwingOther(strike.userId, strike.step or 1)\n\tend\n",
        "\tend\n\tWeaponController.SwingOther(strike.userId, strike.step or 1)\n",
    ),
    "l3w2 T9: a swing leaves onStrike before the arm": (
        FEEDBACK,
        "\tlocal drawnEarly = false\n\tlocal seq = strike.seq\n",
        "\tlocal drawnEarly = false\n\tif swing and not mine then\n\t\treturn\n\tend\n\tlocal seq = strike.seq\n",
    ),
    "l3w2 T9: someone else's strike counts as mine": (
        FEEDBACK,
        "\tlocal mine = strike.userId == localUserId()\n",
        "\tlocal mine = strike.userId ~= 0\n",
    ),
    # T10: one muzzle.
    "l3w2 T10: the pellets leave from the hand": (
        FEEDBACK,
        "local from = (HeldWeapons.Muzzle(strike.userId)) or origin",
        'local from = ((Players:GetPlayerByUserId(strike.userId) :: any).Character:FindFirstChild("RightHand")).Position'
        " or origin",
    ),
    "l3w2 T10: the beam asks for the muzzle twice": (
        FEEDBACK,
        "local from = (HeldWeapons.Muzzle(userId)) or beam.origin",
        "local from = HeldWeapons.Muzzle(userId) and (HeldWeapons.Muzzle(userId)) or beam.origin",
    ),
    "l3w2 T10: the flame pushes the tip forward": (
        FLAME_FX,
        "\tif point == nil or fromModel then\n\t\treturn point\n\tend\n",
        "\tif point == nil then\n\t\treturn point\n\tend\n",
    ),
    "l3w2 T10: the flame leaves from the hand": (
        FLAME_FX,
        "\tlocal point, fromModel = HeldWeapons.Muzzle(userId)\n",
        '\tlocal hand = (Players:GetPlayerByUserId(userId) :: any).Character:FindFirstChild("RightHand")\n'
        "\tlocal point, fromModel = hand.Position, false\n",
    ),
    "l3w2 T10: an ability pushes the tip forward": (
        ABILITY_SHARED,
        "return if fromModel then point else point + aim * MUZZLE_FORWARD",
        "return point + aim * MUZZLE_FORWARD",
    ),
    "l3w2 T10: an ability muzzle from the hand": (
        ABILITY_SHARED,
        "\tlocal point, fromModel = HeldWeapons.Muzzle(userId)\n",
        "\tlocal root, _, character = casterOf(userId)\n"
        "\tlocal point, fromModel = if root ~= nil then handOf(character, root) else nil, false\n",
    ),
    "l3w2 T10: MagDump's muzzle from its hand again": (
        MAG_DUMP,
        "muzzle = muzzleOf(cast.userId, look, muzzle)",
        "muzzle = handPoint + look * MUZZLE_FORWARD",
    ),
    "l3w2 T10: the local muzzle is the hand": (
        WEAPON_CONTROLLER,
        "\treturn HeldWeapons.Muzzle(Players.LocalPlayer.UserId) or fallback\n",
        "\tlocal rig = character\n\tlocal hand = if rig ~= nil then handOf(rig) else nil\n"
        "\treturn if hand ~= nil then hand.Position else fallback\n",
    ),
    "l3w2 T10: the muzzle is never the model's tip": (
        HELD_WEAPONS,
        "return held.base.CFrame:PointToWorldSpace(tip), true",
        "return held.base.Position, true",
    ),
    "l3w2 T10: a second hand list": (
        HELD_WEAPONS,
        "\tlocal hand = firstPart(character, HAND_PARTS)\n",
        '\tlocal hand = firstPart(character, { "RightHand" })\n',
    ),
    "l3w2 L3-51: HeldWeapons never starts": (WEAPON_CONTROLLER, "\tHeldWeapons.Start()\n", ""),
    "l3w2 L3-54: the local stance never reaches HeldWeapons": (
        WEAPON_CONTROLLER,
        "\tHeldWeapons.SetLocalStance(nextStance)\n",
        "",
    ),
    "l3w2 L3-53: WeaponController requires FeedbackController": (
        WEAPON_CONTROLLER,
        'local HeldWeapons = require(script.Parent:WaitForChild("HeldWeapons"))\n',
        'local HeldWeapons = require(script.Parent:WaitForChild("HeldWeapons"))\n'
        'local _Feedback = require(script.Parent:WaitForChild("FeedbackController"))\n',
    ),
    "l3w2 L3-53: HeldWeapons requires WeaponController": (
        HELD_WEAPONS,
        "local WeaponLook = require(sharedFolder:WaitForChild(\"WeaponLook\"))\n",
        "local WeaponLook = require(sharedFolder:WaitForChild(\"WeaponLook\"))\n"
        "local _Weapon = require(script.Parent:WaitForChild(\"WeaponController\"))\n",
    ),
    # T11 to T13: HeldWeapons.
    "l3w2 T11: a clone on every call": (
        HELD_WEAPONS,
        "\tif cached ~= nil then\n\t\treturn cached\n\tend\n\tlocal config = Catalog.GetWeaponModelsConfig()\n",
        "\tlocal config = Catalog.GetWeaponModelsConfig()\n",
    ),
    "l3w2 T11: a second clone": (
        HELD_WEAPONS,
        "\tlocal model = template:Clone()\n",
        "\tlocal model = template:Clone()\n\tlocal _spare = template:Clone()\n",
    ),
    "l3w2 T11: HeldWeapons runs per frame": (
        HELD_WEAPONS,
        'local Players = game:GetService("Players")\n',
        'local Players = game:GetService("Players")\nlocal RunService = game:GetService("RunService")\n',
    ),
    "l3w2 T12: the clone is not sealed": (HELD_WEAPONS, "\tseal(model)\n", ""),
    "l3w2 T12: sealed after its first parent": (
        HELD_WEAPONS,
        "\tseal(model)\n",
        "\tmodel.Parent = character\n\tseal(model)\n",
    ),
    "l3w2 T12: seal stops at the children": (
        HELD_WEAPONS,
        "\tfor _, part in model:GetDescendants() do\n\t\tif part:IsA(\"BasePart\") then\n\t\t\tpart.Anchored = false\n",
        "\tfor _, part in model:GetChildren() do\n\t\tif part:IsA(\"BasePart\") then\n\t\t\tpart.Anchored = false\n",
    ),
    "l3w2 T12: seal leaves it anchored": (HELD_WEAPONS, "\t\t\tpart.Anchored = false\n", ""),
    "l3w2 T12: seal leaves collisions on": (HELD_WEAPONS, "\t\t\tpart.CanCollide = false\n", ""),
    "l3w2 T12: seal leaves queries on": (HELD_WEAPONS, "\t\t\tpart.CanQuery = false\n", ""),
    "l3w2 T12: seal leaves touches on": (HELD_WEAPONS, "\t\t\tpart.CanTouch = false\n", ""),
    "l3w2 T12: seal leaves its mass": (HELD_WEAPONS, "\t\t\tpart.Massless = true\n", ""),
    "l3w2 T13: a recursive attachment lookup": (
        HELD_WEAPONS,
        "local attachment = if part ~= nil then part:FindFirstChild(attachmentName) else nil",
        "local attachment = if part ~= nil then character:FindFirstChild(attachmentName, true) else nil",
    ),
    # T14: the stage's turn.
    # Re-aimed by the fix round (C3 moved the turn into syncTurn; S3 pins its gate exactly).
    "l3w2 T14: the stage turns on reducedMotion": (
        ARMORY_STAGE,
        "\t\tif look.turn == nil and not Theme.lowEndDevice then\n\t\t\tlook.turn = RunService.RenderStepped:Connect(",
        "\t\tif look.turn == nil and not Theme.reducedMotion then\n\t\t\tlook.turn = RunService.RenderStepped:Connect(",
    ),
    "l3w2 T14: the stage turns on a low-end device": (
        ARMORY_STAGE,
        "\t\tif look.turn == nil and not Theme.lowEndDevice then\n\t\t\tlook.turn = RunService.RenderStepped:Connect(",
        "\t\tif look.turn == nil and (true or not Theme.lowEndDevice) then\n"
        "\t\t\tlook.turn = RunService.RenderStepped:Connect(",
    ),
    "l3w2 T14: the model is posed every frame": (
        ARMORY_STAGE,
        "\t\t\t\tturnBy(rate * deltaTime)\n",
        "\t\t\t\t(look.model :: any):PivotTo(CFrame.identity)\n\t\t\t\tturnBy(rate * deltaTime)\n",
    ),
    "l3w2 T14: the select path poses nothing": (ARMORY_STAGE, "\t\tmodel:PivotTo(pose)\n", ""),
    "l3w2 T14: the stage stands flat": (
        ARMORY_STAGE,
        "local pose = CFrame.Angles(math.rad(Theme.ARMORY_STAGE_TILT_DEGREES), 0, 0)",
        "local pose = CFrame.identity",
    ),
    "l3w2 T14: the screen never turns the stage on": (
        ARMORY_SCREEN,
        'stage.SetActive(view.open and shown == "weapons")',
        "stage.SetActive(false)",
    ),
    "l3w2 T14: the stage keeps turning when the screen closes": (ARMORY_SCREEN, "\t\t\tstage.SetActive(false)\n", ""),
    # The lead's ruling 6 (§11): the rest poses (HeldWeapons' hold and raised hand, WeaponController's rest).
    "l3w2 R6: a ranged hand held as melee": (
        HELD_WEAPONS,
        "\t\telseif ranged then Theme.COMBAT_HOLD_GRIP_RANGED\n",
        "\t\telseif ranged then Theme.COMBAT_HOLD_GRIP_MELEE\n",
    ),
    "l3w2 R6: the back held as a melee hand": (
        HELD_WEAPONS,
        "\t\tthen Theme.COMBAT_HOLD_BACK\n",
        "\t\tthen Theme.COMBAT_HOLD_GRIP_MELEE\n",
    ),
    "l3w2 R6: the weld leaves out the hold": (
        HELD_WEAPONS,
        "held.weld.C0 = attachment.CFrame * hold * CFrame.new(-point)",
        "held.weld.C0 = attachment.CFrame * CFrame.new(-point)",
    ),
    "l3w2 R6: the back hangs by the grip": (
        HELD_WEAPONS,
        'if inHand then "grip" else "holster"',
        '"grip"',
    ),
    "l3w2 R6: the hand never held as ranged": (
        HELD_WEAPONS,
        "\trig.inHand = hang(rig, inUse, true, rangedInUse)\n",
        "\trig.inHand = hang(rig, inUse, true, false)\n",
    ),
    "l3w2 R6: a ranged slot with an empty hand is raised": (
        HELD_WEAPONS,
        "local raised = rangedInUse and rig.inHand ~= nil",
        "local raised = rangedInUse",
    ),
    "l3w2 R6: a remote hand reads the local stance": (
        HELD_WEAPONS,
        "\tlocal slot = if rig.isLocal then localStance else held\n",
        "\tlocal slot = localStance\n",
    ),
    "l3w2 R6: the listener is never told": (HELD_WEAPONS, "\t\t\tlistener(character, rig.isLocal, raised)\n", ""),
    "l3w2 R6: the raised hand is never kept": (HELD_WEAPONS, "\t\trig.raised = raised\n", ""),
    "l3w2 R6: OnHold keeps no listener": (HELD_WEAPONS, "\tholdListener = listener\n", ""),
    "l3w2 R6: a late listener misses the raised hands": (
        HELD_WEAPONS,
        "\t\tif rig.raised then\n\t\t\tlistener(rig.character, rig.isLocal, true)\n",
        "\t\tif false then\n\t\t\tlistener(rig.character, rig.isLocal, true)\n",
    ),
    "l3w2 R6: the raise is never applied": (
        WEAPON_CONTROLLER,
        "\t\tthen Theme.COMBAT_HOLD_RANGED_RAISE_DEGREES\n",
        "\t\tthen 0\n",
    ),
    "l3w2 R6: the rest frame ignores the rest": (
        WEAPON_CONTROLLER,
        "return rig.base * CFrame.Angles(math.rad(rig.rest), 0, 0)",
        "return rig.base",
    ),
    "l3w2 R6: a cancel snaps to the hanging arm": (WEAPON_CONTROLLER, "motor.C0 = restFrame(rig)", "motor.C0 = rig.base"),
    "l3w2 R6: a new rest is never written": (WEAPON_CONTROLLER, "\trig.rest = degrees\n", ""),
    "l3w2 R6: the swing settles to the hanging arm": (
        WEAPON_CONTROLLER,
        "rigPoseTo(rig, rig.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)",
        "rigPoseTo(rig, 0, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)",
    ),
    "l3w2 R6: Release drops the arm": (
        WEAPON_CONTROLLER,
        "poseTo(localPose.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)",
        "poseTo(0, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)",
    ),
    "l3w2 R6: Release resets the rest": (
        WEAPON_CONTROLLER,
        "\tcancelPose()\n\tposeTo(localPose.rest,",
        "\tcancelPose()\n\tlocalPose.rest = 0\n\tposeTo(localPose.rest,",
    ),
    "l3w2 R6: the kick from the hanging arm": (
        WEAPON_CONTROLLER,
        "localPose.rest + Theme.COMBAT_SHOOT_KICK_DEGREES",
        "Theme.COMBAT_SHOOT_KICK_DEGREES",
    ),
    "l3w2 R6: the hold is never wired": (WEAPON_CONTROLLER, "\tHeldWeapons.OnHold(onHold)\n", ""),
    "l3w2 R6: the local hold is ignored": (
        WEAPON_CONTROLLER,
        "\telseif rigModel == character then\n\t\tsetRest(localPose, restOf(rigModel))\n",
        "\telseif false then\n\t\tsetRest(localPose, restOf(rigModel))\n",
    ),
    "l3w2 R6: the raised set is never kept": (WEAPON_CONTROLLER, "\traisedRigs[rigModel] = raised\n", ""),
    "l3w2 R6: the local shoulder starts hanging": (WEAPON_CONTROLLER, "\t\tlocalPose.rest = restOf(rig)\n", ""),
    "l3w2 R6: a remote record starts hanging": (WEAPON_CONTROLLER, "\tfresh.rest = restOf(rigModel)\n", "\tfresh.rest = 0\n"),
}
MUTATIONS.update(L3W2_MUTATIONS)

# The L3 W2 fix round (docs/prompts/l3-w2-fix-round.md S1 to S6), from the luau-engineer. Run them
# alone with `mutate.py <root> <luau> "l3w2 fix"`. ArenaService is read as text (S2's hook).
ARENA_SERVICE = "src/combat/server/Services/ArenaService.luau"
ARMORY_SHELF = "src/client/UI/ArmoryShelf.luau"
FILES += [ARENA_SERVICE, ARMORY_SHELF]


def moved_down(rel: str, block: str, anchor: str) -> tuple:
    """A mutation that moves `block` to just after the first `anchor` that follows it, as one
    replacement: old = the span from the block through the anchor. Built from the file as it
    stands; a block or anchor that is gone makes an entry found 0 times (the stale check)."""
    text = (repo / rel).read_text(encoding="utf-8")
    start = text.find(block)
    end = text.find(anchor, start + len(block)) if start >= 0 else -1
    if end < 0:
        return (rel, f"<{block!r} before {anchor!r}: not found>", "")
    old = text[start : end + len(anchor)]
    return (rel, old, old[len(block) :] + block)


def moved_up(rel: str, anchor: str, block: str) -> tuple:
    """moved_down's mirror: `block` moves to just before the last `anchor` that precedes it."""
    text = (repo / rel).read_text(encoding="utf-8")
    end = text.find(block)
    start = text.rfind(anchor, 0, end) if end >= 0 else -1
    if start < 0:
        return (rel, f"<{anchor!r} before {block!r}: not found>", "")
    old = text[start : end + len(block)]
    return (rel, old, block + old[: -len(block)])


L3W2_FIX_MUTATIONS = {
    # S1 (2-m1): a function T8 does not list reads the slot in use (the review's P1 and P2).
    "l3w2 fix S1: slotFamily answers nothing for the slot not in use": (
        WEAPON,
        '\treturn if slot == "melee" then shooter.loadout.melee else shooter.loadout.ranged\n',
        '\tif slot ~= shooter.held then\n\t\treturn ""\n\tend\n'
        '\treturn if slot == "melee" then shooter.loadout.melee else shooter.loadout.ranged\n',
    ),
    "l3w2 fix S1: variantFor drops the style while ranged is in use": (
        WEAPON,
        "\tlocal chosen = shooter.loadout.variants[family]\n",
        '\tlocal chosen = if shooter.held == "ranged" then nil else shooter.loadout.variants[family]\n',
    ),
    "l3w2 fix S1: AbilityService reads the slot in use": (
        ABILITY,
        "\tlocal family = familyOf(loadout, slotName)\n",
        "\tlocal family = familyOf(loadout, if (caster :: any).held ~= nil then slotName else slotName)\n",
    ),
    # S2 (2-m2): each way a character reaches PrepareCharacter (the review's P3 to P6, and the
    # exits and keepers around them).
    "l3w2 fix S2: live missions never prepare a later character": (
        WAVE_SERVICE,
        "\tArenaService.SetCharacterHook(WeaponService.PrepareCharacter)\n",
        "\tif boot.proving then\n\t\tArenaService.SetCharacterHook(WeaponService.PrepareCharacter)\n\tend\n",
    ),
    "l3w2 fix S2: Init leaves a live mission before the hook": (
        WAVE_SERVICE,
        "\tboot.proving = CombatMode.IsProving()\n",
        "\tboot.proving = CombatMode.IsProving()\n\tif not boot.proving then\n\t\treturn\n\tend\n",
    ),
    "l3w2 fix S2: WaveService sets the hook a second time": (
        WAVE_SERVICE,
        "\tArenaService.SetMovedHook(WeaponService.ForgetMotion)\n",
        "\tArenaService.SetMovedHook(WeaponService.ForgetMotion)\n\tArenaService.SetCharacterHook(function() end)\n",
    ),
    "l3w2 fix S2: a mission respawn skips the hook": (
        ARENA_SERVICE,
        "\t\t\t\t\thook(player, character)\n",
        "\t\t\t\t\tlocal _ = character\n",
    ),
    "l3w2 fix S2: the admit's handler leaves before the hook": (
        ARENA_SERVICE,
        "\t\t\t\tplaceBody(live)\n",
        "\t\t\t\tplaceBody(live)\n\t\t\t\tif live.bot then\n\t\t\t\t\treturn\n\t\t\t\tend\n",
    ),
    "l3w2 fix S2: ArenaService keeps no hook": (ARENA_SERVICE, "\thooks.character = hook\n", "\tlocal _ = hook\n"),
    "l3w2 fix S2: a second writer clears the hook": (
        ARENA_SERVICE,
        "\thooks.share = source\n",
        "\thooks.share = source\n\thooks.character = nil\n",
    ),
    "l3w2 fix S2: a range respawn is not prepared": (
        RANGE_SERVICE,
        "\t\t\tprepareCharacter(player, character)\n\t\tend)\n",
        "\t\tend)\n",
    ),
    "l3w2 fix S2: the range's first character is not prepared": (
        RANGE_SERVICE,
        "\tif character ~= nil then\n\t\tprepareCharacter(player, character)\n\tend\nend",
        "\tif character ~= nil then\n\t\tlocal _ = character\n\tend\nend",
    ),
    "l3w2 fix S2: the range's AddPlayer gives no weapons": (RANGE_SERVICE, "\tWeaponService.AddPlayer(player)\n", ""),
    "l3w2 fix S2: the range's AddPlayer leaves before its characters": (
        RANGE_SERVICE,
        "\tlocal member: Member = { connections = {} }\n",
        "\tif player.UserId < 0 then\n\t\treturn\n\tend\n\tlocal member: Member = { connections = {} }\n",
    ),
    "l3w2 fix S2: the range places a body and leaves": (
        RANGE_SERVICE,
        "\tcharacter:PivotTo(spawnCFrame)\n",
        "\tcharacter:PivotTo(spawnCFrame)\n\tif spawnLocation == nil then\n\t\treturn\n\tend\n",
    ),
    "l3w2 fix S2: AddPlayer prepares in the range instead": (
        WEAPON,
        '\tif state.mode == "mission" then\n\t\t-- The character usually',
        '\tif state.mode == "range" then\n\t\t-- The character usually',
    ),
    "l3w2 fix S2: AddPlayer leaves before the mission's prepare": (
        WEAPON,
        "\tstate.shooters[player] = shooter\n\tVitalsService.AddPlayer(player)\n",
        "\tstate.shooters[player] = shooter\n\tVitalsService.AddPlayer(player)\n\tif player.UserId < 0 then\n\t\treturn\n\tend\n",
    ),
    # S3 (2-m3): a pinned line wrapped in a block is indented further and no longer counts.
    "l3w2 fix S3: the range prepares only at a spawn": (
        RANGE_SERVICE,
        "\tWeaponService.PrepareCharacter(player, character)\n",
        "\tif spawnLocation ~= nil then\n\t\tWeaponService.PrepareCharacter(player, character)\n\tend\n",
    ),
    "l3w2 fix S3: no arm moves, inside the branch (the review's P7)": (
        FEEDBACK,
        "\t\tWeaponController.SwingOther(strike.userId, strike.step or 1)\n",
        "\t\tif false then\n\t\t\tWeaponController.SwingOther(strike.userId, strike.step or 1)\n\t\tend\n",
    ),
    "l3w2 fix S3: no arm moves, in a block left at the branch's own depth": (
        FEEDBACK,
        "\t\t-- L3-53: and their arm swings, with the step the server used.\n"
        "\t\tWeaponController.SwingOther(strike.userId, strike.step or 1)\n",
        "\t\tif false then\n\t\tWeaponController.SwingOther(strike.userId, strike.step or 1)\n\t\tend\n",
    ),
    "l3w2 fix S3: a sealed clone queried again (the review's P13)": (
        HELD_WEAPONS,
        "\tseal(model)\n",
        "\tseal(model)\n\tfor _, part in model:GetDescendants() do\n\t\t(part :: BasePart).CanQuery = true\n\tend\n",
    ),
    "l3w2 fix S3: a new rest waits for the next pose": (
        WEAPON_CONTROLLER,
        "\trigPoseTo(rig, degrees, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)\nend",
        "\tlocal _ = degrees\nend",
    ),
    "l3w2 fix S3: another player's respawn hangs a raised arm": (
        WEAPON_CONTROLLER,
        "\t\tfreshMotor.C0 = restFrame(fresh)\n",
        "\t\tfreshMotor.C0 = fresh.base\n",
    ),
    # S3 (3-m3) and C1 to C3, the stage (written against the ui-engineer's final text).
    "l3w2 fix S3: a close leaves the stage turning": (
        ARMORY_STAGE,
        "\t\t\t\tstop()\n\t\t\t\treturn\n",
        "\t\t\t\treturn\n",
    ),
    "l3w2 fix S3: opening the screen never syncs the turn": (
        ARMORY_STAGE,
        "\t\t\t\twarm()\n\t\t\tend\n\t\t\tsyncTurn()\n",
        "\t\t\t\twarm()\n\t\t\tend\n",
    ),
    "l3w2 fix S3: SetActive leaves before a model is shown": (
        ARMORY_STAGE,
        "\t\t\tlook.active = active\n",
        "\t\t\tif active and look.model == nil then\n\t\t\t\treturn\n\t\t\tend\n\t\t\tlook.active = active\n",
    ),
    "l3w2 fix S3: every selection stacks another clone": (
        ARMORY_STAGE,
        "\tlocal function selectFamily(family: string): ()\n\t\tclear()\n",
        "\tlocal function selectFamily(family: string): ()\n",
    ),
    "l3w2 fix S3: an unowned weapon stands in colour on the stage": (
        ARMORY_STAGE,
        "if owned then WHITE else Theme.ARMORY_STAGE_SILHOUETTE",
        "WHITE",
    ),
    "l3w2 fix C1: the stage pivots its clone without a PrimaryPart": (
        ARMORY_STAGE,
        "\t\tmodel.PrimaryPart = base\n\t\tfor _, part in model:GetDescendants() do\n",
        "\t\tfor _, part in model:GetDescendants() do\n",
    ),
    "l3w2 fix C1: the stage makes Base its PrimaryPart after the pose": moved_down(
        ARMORY_STAGE,
        "\t\tmodel.PrimaryPart = base\n",
        "\t\tmodel:PivotTo(pose)\n",
    ),
    "l3w2 fix C1: the stage takes a template with no Base": (
        ARMORY_STAGE,
        "\tlocal base = template:FindFirstChild(TEMPLATE_BASE_NAME)\n"
        "\tif base == nil or not base:IsA(\"BasePart\") then\n\t\treturn nil, nil\n\tend\n",
        "",
    ),
    "l3w2 fix C1: the stage looks for another Base": (
        ARMORY_STAGE,
        "local TEMPLATE_BASE_NAME = \"Base\"\n",
        "local TEMPLATE_BASE_NAME = \"Handle\"\n",
    ),
    "l3w2 fix C1: the stage reads the PrimaryPart ref": (
        ARMORY_STAGE,
        "\t\tlocal base = model:FindFirstChild(TEMPLATE_BASE_NAME)\n",
        "\t\tlocal base = model.PrimaryPart or model:FindFirstChild(TEMPLATE_BASE_NAME)\n",
    ),
    "l3w2 fix C3: the stage turns with no model shown": (
        ARMORY_STAGE,
        "\t\tif not look.active or look.model == nil then\n\t\t\tstop()\n",
        "\t\tif not look.active then\n\t\t\tstop()\n",
    ),
    "l3w2 fix C3: the slow turn never turns": (
        ARMORY_STAGE,
        "\t\t\t\tturnBy(rate * deltaTime)\n",
        "\t\t\t\tlocal _ = rate * deltaTime\n",
    ),
    "l3w2 fix C3: the right stick is never heard": (
        ARMORY_STAGE,
        "\t\t\ttable.insert(look.inputs, UserInputService.InputChanged:Connect(onStick))\n",
        "",
    ),
    "l3w2 fix C3: a lost focus keeps the drag": (
        ARMORY_STAGE,
        "\t\t\t\t\tlook.stickX = 0\n\t\t\t\t\tendDrag()\n",
        "\t\t\t\t\tlook.stickX = 0\n",
    ),
    "l3w2 fix C3: a low-end device gets no stick": (
        ARMORY_STAGE,
        "\t\tif #look.inputs == 0 then\n",
        "\t\tif Theme.lowEndDevice then\n\t\t\treturn\n\t\tend\n\t\tif #look.inputs == 0 then\n",
    ),
    "l3w2 fix C3: stop leaves the listeners counted": (ARMORY_STAGE, "\t\ttable.clear(look.inputs)\n", ""),
    "l3w2 fix C3: Show(nil) leaves the stage live": (
        ARMORY_STAGE,
        "\t\t\t\tlook.family = nil\n\t\t\t\tsyncTurn()\n",
        "\t\t\t\tlook.family = nil\n",
    ),
    "l3w2 fix C3: a selection never syncs": (
        ARMORY_STAGE,
        "\t\t\t\tselectFamily(view.family)\n\t\t\t\tsyncTurn()\n",
        "\t\t\t\tselectFamily(view.family)\n",
    ),
    "l3w2 fix C3: any stick turns the stage": (
        ARMORY_STAGE,
        "\t\tif input.KeyCode ~= Enum.KeyCode.Thumbstick2 then\n",
        "\t\tif input.KeyCode == Enum.KeyCode.Unknown then\n",
    ),
    "l3w2 fix C3: the stick turns per event off low-end too": (
        ARMORY_STAGE,
        "if Theme.lowEndDevice and look.stickX ~= 0",
        "if look.stickX ~= 0",
    ),
    "l3w2 fix C3: a lost mouse release keeps the drag": (
        ARMORY_STAGE,
        "\t\t\t\tif not touch and not UserInputService:IsMouseButtonPressed(kind) then\n"
        "\t\t\t\t\tendDrag()\n\t\t\t\t\treturn\n\t\t\t\tend\n",
        "",
    ),
    "l3w2 fix C3: a mouse release never ends the drag": (
        ARMORY_STAGE,
        "if ended == input or (not touch and ended.UserInputType == kind) then",
        "if ended == input then",
    ),
    # C2: the shelf's ghost tone.
    "l3w2 fix C2: the shelf draws the near-black silhouette again": (
        ARMORY_SHELF,
        "if owned then WHITE else Theme.ARMORY_SCREEN_ICON_GHOST",
        "if owned then WHITE else Theme.ARMORY_STAGE_SILHOUETTE",
    ),
    "l3w2 fix S3: an unowned shelf icon in colour": (
        ARMORY_SHELF,
        "if owned then WHITE else Theme.ARMORY_SCREEN_ICON_GHOST",
        "WHITE",
    ),
    # S3 (3-m3) and C1, C4, HeldWeapons.
    "l3w2 fix S3: a family that leaves stays welded on": (
        HELD_WEAPONS,
        "\t\t\t\tcache[family] = nil\n\t\t\t\tentry.model:Destroy()\n",
        "\t\t\t\tcache[family] = nil\n",
    ),
    "l3w2 fix S3: a teammate's slot switch is never watched": (
        HELD_WEAPONS,
        "{ names.melee, names.ranged, names.held }",
        "{ names.melee, names.ranged }",
    ),
    "l3w2 fix S3: an attribute change shows nothing": (
        HELD_WEAPONS,
        "character:GetAttributeChangedSignal(name):Connect(function()\n\t\t\t\tqueueShow(rig)\n",
        "character:GetAttributeChangedSignal(name):Connect(function()\n\t\t\t\tlocal _ = rig\n",
    ),
    "l3w2 fix S3: a late mount part never re-shows": (
        HELD_WEAPONS,
        "\t\t\t\twatchPart(rig, child)\n\t\t\t\tqueueShow(rig)\n",
        "\t\t\t\twatchPart(rig, child)\n",
    ),
    "l3w2 fix S3: a late attachment on the back never re-shows": (
        HELD_WEAPONS,
        "if child.Name == GRIP_ATTACHMENT or child.Name == BACK_ATTACHMENT then",
        "if child.Name == GRIP_ATTACHMENT then",
    ),
    "l3w2 fix S3: bind shows nothing until a change": (
        HELD_WEAPONS,
        "\t\t)\n\tend\n\tshow(rig)\nend\n",
        "\t\t)\n\tend\nend\n",
    ),
    "l3w2 fix S3: bind leaves early": (
        HELD_WEAPONS,
        "\trigs[player] = rig\n",
        "\trigs[player] = rig\n\tif character.Parent == nil then\n\t\treturn\n\tend\n",
    ),
    "l3w2 fix S3: the local switch shows nothing": (
        HELD_WEAPONS,
        "\tlocal rig = rigs[Players.LocalPlayer]\n\tif rig ~= nil then\n\t\tshow(rig)\n",
        "\tlocal rig = rigs[Players.LocalPlayer]\n\tif rig ~= nil then\n\t\tlocal _ = rig\n",
    ),
    "l3w2 fix S3: the local switch to ranged leaves early": (
        HELD_WEAPONS,
        "\tlocalStance = nextStance\n",
        "\tif nextStance == RANGED_SLOT then\n\t\treturn\n\tend\n\tlocalStance = nextStance\n",
    ),
    "l3w2 fix S3: a player who joins is never watched": (
        HELD_WEAPONS,
        "\ttable.insert(connections, Players.PlayerAdded:Connect(watchPlayer))\n",
        "",
    ),
    "l3w2 fix S3: the players already in are never watched": (
        HELD_WEAPONS,
        "\t\twatchPlayer(player)\n\tend\n",
        "\t\tlocal _ = player\n\tend\n",
    ),
    "l3w2 fix S3: Start leaves without a models file": (
        HELD_WEAPONS,
        "\tstarted = true\n",
        "\tstarted = true\n\tif Catalog.GetWeaponModelsConfig() == nil then\n\t\treturn\n\tend\n",
    ),
    "l3w2 fix C4: a queued show never runs": (HELD_WEAPONS, "\ttask.defer(flush, rig)\n", ""),
    "l3w2 fix C4: every change defers its own show": (
        HELD_WEAPONS,
        "\tif rig.pending then\n\t\treturn\n\tend\n\trig.pending = true\n",
        "\trig.pending = true\n",
    ),
    "l3w2 fix C4: a gone rig is shown": (
        HELD_WEAPONS,
        "\tif rig.bound then\n\t\tshow(rig)\n\tend\n",
        "\tshow(rig)\n",
    ),
    "l3w2 fix C4: unbind leaves the rig bound": (HELD_WEAPONS, "\trig.bound = false\n", ""),
    "l3w2 fix C4: Muzzle reads before the pending show": (HELD_WEAPONS, "\t\tflush(rig)\n", ""),
    "l3w2 fix C4: a burst shows at once, change by change": (
        HELD_WEAPONS,
        "\t\t\t\twatchPart(rig, child)\n\t\t\t\tqueueShow(rig)\n",
        "\t\t\t\twatchPart(rig, child)\n\t\t\t\tshow(rig)\n",
    ),
    "l3w2 fix C1: the clone keeps the template's PrimaryPart ref": (HELD_WEAPONS, "\tmodel.PrimaryPart = base\n", ""),
    "l3w2 fix C1: Base becomes PrimaryPart after the welds": moved_down(
        HELD_WEAPONS,
        "\tmodel.PrimaryPart = base\n",
        "\tseal(model)\n\tfor _, part in model:GetDescendants() do\n"
        "\t\tif part:IsA(\"BasePart\") and part ~= base then\n"
        "\t\t\tCreate(\"WeldConstraint\", { Part0 = base, Part1 = part, Parent = base })\n\t\tend\n\tend\n",
    ),
    "l3w2 fix C1: a template with no Base is cloned": (
        HELD_WEAPONS,
        "\tlocal base = template:FindFirstChild(TEMPLATE_BASE_NAME)\n"
        "\tif base == nil or not base:IsA(\"BasePart\") then\n\t\treturn nil\n\tend\n\treturn template\n",
        "\treturn template\n",
    ),
    "l3w2 fix C1: HeldWeapons looks for another Base": (
        HELD_WEAPONS,
        "local TEMPLATE_BASE_NAME = \"Base\"\n",
        "local TEMPLATE_BASE_NAME = \"Handle\"\n",
    ),
    "l3w2 fix C1: HeldWeapons reads the PrimaryPart ref": (
        HELD_WEAPONS,
        "\tlocal base = model:FindFirstChild(TEMPLATE_BASE_NAME)\n",
        "\tlocal base = model.PrimaryPart or model:FindFirstChild(TEMPLATE_BASE_NAME)\n",
    ),
    # S4 (2-m5): a melee family may draw again.
    "l3w2 fix S4: a melee family draws": (
        WEAPON,
        '\t\tdef.slot ~= "ranged"\n\t\tor slotFamily(shooter, slot) ~= weapon\n',
        "\t\tslotFamily(shooter, slot) ~= weapon\n",
    ),
    # S5 (2-s1): the spellings the older counts missed (the review's P9, P10, P12).
    "l3w2 fix S5: a dash writes held by index": (
        WEAPON,
        "\tshooter.lastDashAt = now\n",
        '\tshooter.lastDashAt = now\n\tshooter["held"] = "ranged"\n',
    ),
    "l3w2 fix S5: a dash writes WeaponHeld itself": (
        WEAPON,
        "\tshooter.lastDashAt = now\n",
        '\tshooter.lastDashAt = now\n\tcharacter:SetAttribute("WeaponHeld", "ranged")\n',
    ),
    "l3w2 fix S5: SetVariant swaps the whole loadout": (
        WEAPON,
        "\tshooter.loadout.variants[family] = key\n",
        "\tshooter.loadout = { melee = shooter.loadout.ranged, ranged = shooter.loadout.melee,"
        " variants = shooter.loadout.variants }\n\tshooter.loadout.variants[family] = key\n",
    ),
    "l3w2 fix S5: SetVariant writes the pair by index": (
        WEAPON,
        "\tshooter.loadout.variants[family] = key\n",
        '\tshooter.loadout["melee"] = shooter.loadout.ranged\n\tshooter.loadout.variants[family] = key\n',
    ),
    # S5 (2-s2): a refusal moved past the note keeps the total of exits (the review's P11), and so
    # does the cast's note moved above its aim refusal with the send it precedes.
    "l3w2 fix S5: OnAttack's credit refusal after the note": moved_down(
        WEAPON,
        "\tif credit < timingTolerance() then\n\t\tsendRefused(shooter, seq)\n\t\treturn\n\tend\n",
        "\tnoteHeld(shooter, slot)\n",
    ),
    "l3w2 fix S5: the cast's note and send before its aim refusal": moved_up(
        ABILITY,
        "\tlocal root = WeaponService.RootOf(player)\n",
        "\tWeaponService.NoteHeld(player, slotName)\n\tbroadcastFx(fx)\n",
    ),
    # S5 (2-s4): Problems' whole list in family order.
    "l3w2 fix S5: Problems sorts each pass alone": (LOOK, "\ttable.sort(problems)\n\treturn problems\n", "\treturn problems\n"),
    # S6 (3-m1): the note after the cast's effect has left.
    "l3w2 fix S6: a cast's effect leaves before the note": (
        ABILITY,
        "\tWeaponService.NoteHeld(player, slotName)\n\tbroadcastFx(fx)\n",
        "\tbroadcastFx(fx)\n\tWeaponService.NoteHeld(player, slotName)\n",
    ),
    "l3w2 fix S6: the cast is noted once accepted, as before": moved_down(
        ABILITY,
        "\tWeaponService.NoteHeld(player, slotName)\n",
        "\tcaster.lastSeq = seq\n",
    ),
}
MUTATIONS.update(L3W2_FIX_MUTATIONS)

def harness(root: Path) -> tuple:
    """Runs the harness on `root`. Returns its failing check lines and its verdict line ("" when
    it printed none: run_harness.py prints one whenever a case ran)."""
    result = subprocess.run(
        [sys.executable, str(here / "run_harness.py"), str(root), luau], capture_output=True, text=True
    )
    lines = [line.strip() for line in result.stdout.splitlines()]
    verdicts = [line for line in lines if line.startswith("HARNESS: ")]
    return [line for line in lines if line.startswith("FAIL")], verdicts[-1] if verdicts else ""


sys.path.insert(0, str(here))
import run_harness  # noqa: E402  (importing it runs nothing)

# The harness's own files go into every mutant root too: run_harness.py refuses a root that holds
# another copy of it, and these are the very files running.
HARNESS_FILES = ["run_harness.py", *run_harness.TESTS]


def copy(root: Path) -> None:
    if root.exists():
        shutil.rmtree(root)
    for file in FILES:
        target = root / file
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repo / file, target)
    for name in HARNESS_FILES:
        target = root / "tools" / "crowd_harness" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(here / name, target)


# An optional fifth argument "from:to" runs that slice of the list (a long run in two halves).
span = sys.argv[4] if len(sys.argv) > 4 else ""
chosen = list(MUTATIONS.items())
if span:
    low, high = span.split(":")
    chosen = chosen[int(low) : int(high)]
if only.startswith("files:"):
    ends = tuple(name.strip() for name in only[len("files:") :].split(",") if name.strip())
    chosen = [(label, entry) for label, entry in chosen if entry[0].endswith(ends)]
else:
    chosen = [(label, entry) for label, entry in chosen if not only or only in label]

# Run from one checkout against another, this would undo the other's rules and judge them by this
# one's cases: refused, as run_harness.py refuses it.
mine = Path(__file__).resolve()
theirs = repo / "tools" / "crowd_harness" / "mutate.py"
differ = ([] if theirs.is_file() and theirs.read_bytes() == mine.read_bytes() else ["mutate.py"])
differ += run_harness.differences(repo)
if differ:
    print(
        f"MUTATIONS: refused: {repo} holds another harness than the one running ({mine.parent}):"
        f" {', '.join(differ)} differ. Run that checkout's own tools/crowd_harness/mutate.py."
    )
    sys.exit(2)

# Before anything runs: every rule a mutation undoes is still written the way it expects.
stale = []
for label, (rel, old, new) in chosen:
    count = (repo / rel).read_text(encoding="utf-8").count(old)
    if count != 1:
        stale.append(f"{label}: its text occurs {count} times in {rel}")
if stale:
    print(f"MUTATIONS: {len(stale)} out of date, nothing was run")
    for line in stale:
        print("   " + line)
    sys.exit(1)

# The unmutated bundle first. A harness that does not pass as it stands (or says nothing at all:
# no interpreter, a bundle that does not compile) would make every mutation look caught.
root = here / "mutant"
copy(root)
fails, verdict = harness(root)
if not verdict.startswith("HARNESS: PASS (") or fails:
    print(f"BASELINE: the unmutated bundle does not pass ({verdict or 'no verdict'}); nothing was mutated")
    for line in fails[:5]:
        print("     " + line[:150])
    shutil.rmtree(root)
    sys.exit(1)
print(f"BASELINE: {verdict}")

vacuous = []
ran = 0
for label, (rel, old, new) in chosen:
    copy(root)
    path = root / rel
    text = path.read_text(encoding="utf-8")
    assert text.count(old) == 1, (label, text.count(old))
    path.write_text(text.replace(old, new), encoding="utf-8")
    fails, verdict = harness(root)
    ran += 1
    # Caught = a check failed. A bundle that stopped part way is one too (run_harness.py reports
    # the stop as a failing check under a FAIL verdict). A harness with no verdict and no failing
    # check has run nothing, and one that passes has seen nothing: neither is a catch.
    if not fails and not verdict.startswith("HARNESS: FAIL"):
        vacuous.append(f"{label} ({verdict or 'the harness said nothing'})")
    outcome = f"{len(fails)} checks fail"
    if verdict.startswith("HARNESS: FAIL (stopped"):
        outcome += ", the last of them the bundle stopping"
    elif not verdict.startswith("HARNESS: FAIL"):
        outcome += f" [{verdict or 'no verdict'}]"
    print(f"== {label}: {outcome}")
    for line in fails[:2]:
        print("     " + line[:150])
if root.exists():
    shutil.rmtree(root)
print(f"MUTATIONS: {ran} run, {len(vacuous)} not caught")
for label in vacuous:
    print("   not caught: " + label)
sys.exit(1 if vacuous else 0)
