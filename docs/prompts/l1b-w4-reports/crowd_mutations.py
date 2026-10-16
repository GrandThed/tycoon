CROWD = "src/combat/server/Services/CrowdService.luau"
BRAIN = "src/combat/server/Services/CrowdBrain.luau"
CAMP = "src/combat/server/Services/CampBrain.luau"
REGION = "src/shared/Region.luau"

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
