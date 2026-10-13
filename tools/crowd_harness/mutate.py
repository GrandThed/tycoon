"""Proves the harness cases are not vacuous. Copies the sources into `mutant/` beside this
file, undoes one rule at a time there, and runs the harness against the copy: every
mutation must fail at least one check.
Usage: py tools/crowd_harness/mutate.py <repo root> <luau.exe> [filter]"""
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
FILES = [
    TALLY,
    TUNING,
    "src/shared/CrowdCodec.luau",
    "src/shared/HitShapes.luau",
    "src/shared/Armory.luau",
    "src/shared/Config/Armory.json",
    BRAIN,
    CROWD,
    VITALS,
    FIELD,
]
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
DIED = 'enemy.state = "dead"\n\t\taliveCount -= 1\n\t\tlocal summoner = enemy.summoner\n\t\tif summoner ~= nil then\n\t\t\tsummoner.guard = math.max(summoner.guard - 1, 0)'
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
        "if vitalsByPlayer[player] ~= vitals or vitals.down or wasDown(vitals, strike.at) then",
        "if vitalsByPlayer[player] ~= vitals or vitals.down then",
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
        "if vitals == nil or vitals.down or wasDown(vitals, impactAt) then",
        "if vitals == nil or vitals.down then",
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
        "\tif not plated then\n\t\tenemy.hp -= dealt\n\tend",
        "\tenemy.hp -= dealt",
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
    "boss: its attacks outlive it": (CROWD, "dismiss(enemy, def.boss == true)", "dismiss(enemy, false)"),
    "boss: every kind's attacks die with it": (CROWD, "dismiss(enemy, def.boss == true)", "dismiss(enemy, true)"),
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
}

vacuous = []
ran = 0
# An optional fifth argument "from:to" runs that slice of the list (a long run in two halves).
span = sys.argv[4] if len(sys.argv) > 4 else ""
chosen = list(MUTATIONS.items())
if span:
    low, high = span.split(":")
    chosen = chosen[int(low) : int(high)]
for label, (rel, old, new) in chosen:
    if only and only not in label:
        continue
    root = here / "mutant"
    if root.exists():
        shutil.rmtree(root)
    for file in FILES:
        target = root / file
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(repo / file, target)
    path = root / rel
    text = path.read_text(encoding="utf-8")
    assert text.count(old) == 1, (label, text.count(old))
    path.write_text(text.replace(old, new), encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(here / "run_harness.py"), str(root), luau], capture_output=True, text=True
    )
    ran += 1
    fails = [line.strip() for line in result.stdout.splitlines() if line.strip().startswith("FAIL")]
    crashed = "HARNESS: PASS" not in result.stdout and "HARNESS: FAIL" not in result.stdout
    if not fails and not crashed:
        vacuous.append(label)
    outcome = f"{len(fails)} checks fail" + (", then the harness stopped" if crashed else "")
    print(f"== {label}: {outcome}")
    for line in fails[:2]:
        print("     " + line[:150])
if (here / "mutant").exists():
    shutil.rmtree(here / "mutant")
print(f"MUTATIONS: {ran} run, {len(vacuous)} not caught")
for label in vacuous:
    print("   not caught: " + label)
