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
(`filter` = only the mutations whose label holds that text; "" = all of them.)"""
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
    "17: the body keeps the profile's health": (VITALS, "{ melee = 1, ranged = 1 }", "{ melee = 0, ranged = 0 }"),
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
        '\tif verdict == "gone" then\n',
        '\tif false then\n',
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
        "\t\t\tabove >= -rules.triggerBelow\n\t\t\tand above <= rules.triggerHeight\n\t\t\tand inRect(zone.trigger, root.X, root.Z)",
        "\t\t\tinRect(zone.trigger, root.X, root.Z)",
    ),
    "l1: the trigger reaches any depth under the floor": (
        FLOW,
        "\t\t\tabove >= -rules.triggerBelow\n\t\t\tand above <= rules.triggerHeight\n",
        "\t\t\tabove <= rules.triggerHeight\n",
    ),
    "l1: the trigger stops at the floor's edge": (
        FLOW,
        "trigger = grown(rect, rules.fenceThickness),",
        "trigger = rect,",
    ),
    "l1: the trigger is the close's rectangle": (
        FLOW,
        "trigger = grown(rect, rules.fenceThickness),",
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
    "l1: the countdown is not gateSeconds": (FLOW, "state.gateAt = now + rules.gateSeconds", "state.gateAt = now + 1"),
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
        "for index, box in LevelGeometry.BlockBoxes(layout, depth) do",
        "for index, box in LevelGeometry.BlockBoxes(layout, nil) do",
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
        "local gates: { Box } = if locks then LevelGeometry.GateBoxes(camp, sizes.fence) else {}",
        "local gates: { Box } = LevelGeometry.GateBoxes(camp, sizes.fence)",
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
        "\treturn math.abs(x - rect.x) <= rect.hx\n\t\tand math.abs(z - rect.z) <= rect.hz\n",
        "\treturn math.abs(x - rect.x) < rect.hx\n\t\tand math.abs(z - rect.z) < rect.hz\n",
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
        "return movement.jumpHeight + movement.doubleJumpHeight",
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
        "\t\tand y - rect.y <= height\n",
        "\t\tand true\n",
    ),
    "l1c fix: exactly the height is outside (m1)": (
        WALL_CLIP,
        "and y - rect.y <= height",
        "and y - rect.y < height",
    ),
    "l1c fix: the height measured from the world's zero (m1)": (
        WALL_CLIP,
        "and y - rect.y <= height",
        "and y <= height",
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
