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
FILES = [
    TALLY,
    TUNING,
    RING,
    FLOW,
    GEOMETRY,
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
FLOOR = "local floor = if y >= target.restY then target.restY else target.standY"
UNDER = '(shape ~= "lob" or above >= -height)'
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
DIED = 'enemy.state = "dead"\n\taliveCount -= 1\n\tlocal summoner = enemy.summoner\n\tif summoner ~= nil then\n\t\tsummoner.guard = math.max(summoner.guard - 1, 0)'
LEFT = "-- Removed alive (a set load, its summoner's death): it leaves its summoner's guard.\n\t\tlocal summoner = enemy.summoner\n\t\tif summoner ~= nil then\n\t\t\tsummoner.guard = math.max(summoner.guard - 1, 0)"
BRAIN_OF = "if mind.enraged and phaseDef ~= nil and phaseDef.brain ~= nil then"
SCALE = "local scale = if recover then phase.recoverScale else phase.windupScale"
CHAINED = "or mind.chained >= math.floor(phase.chain)"
RING_SWEEP = "local to = math.min(now - who.lag, endAt)\n\t\tlocal from = math.max(before - who.lag, leftAt)"
RING_HEIGHT = "if to < from or (height ~= nil and who.feetY - strike.floorY > height) then\n\t\t\tcontinue\n\t\tend\n\t\tlocal dx"
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
    "1c: the lob reaches under its floor": (VITALS, UNDER, "true"),
    "1c: every ground shape has an under side": (VITALS, UNDER, "above >= -height"),
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
    "ring: it has no height": (FIELD, RING_HEIGHT, "if to < from then\n\t\t\tcontinue\n\t\tend\n\t\tlocal dx"),
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
        "if fallen ~= nil and not input.fieldClear then",
        "if fallen ~= nil then",
    ),
    "l1: the fallen are asked before the cap": (
        FLOW,
        "\tif input.runCap then\n",
        "\tif input.runCap and (input.fallen == nil or input.fieldClear) then\n",
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
        "if not inRect(inner, camp.entry.x, camp.entry.z) then",
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
        "maxAlive = stage.maxAlive or level.crowd.maxAlive,",
        "maxAlive = level.crowd.maxAlive,",
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
        "\t\t\tCrowdCodec.Encode(chunk, boundsCenter, serverTime)\n\t\t)\n\t\ttable.clear(chunk)\n\tend\nend",
    ),
    "l1: a full packet's origin following the bounds": (
        CROWD,
        "\t\t\t\tCrowdCodec.Encode(chunk, WIRE_ORIGIN, serverTime)\n\t\t\t)\n\t\t\ttable.clear(chunk)\n\t\t\tcount = 0\n",
        "\t\t\t\tCrowdCodec.Encode(chunk, boundsCenter, serverTime)\n\t\t\t)\n\t\t\ttable.clear(chunk)\n\t\t\tcount = 0\n",
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
