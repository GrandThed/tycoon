"""L1b Wave 4 fix round, luau-engineer A (the crowd): mutation texts for tools/crowd_harness/mutate.py,
verbatim. Each was applied alone to a scratch copy of the worktree and the harness caught it
(see docs/prompts/l1b-w4-fix-reports/crowd.md). Same file constants as mutate.py."""
CROWD = "src/combat/server/Services/CrowdService.luau"
BRAIN = "src/combat/server/Services/CrowdBrain.luau"
CAMP = "src/combat/server/Services/CampBrain.luau"
VITALS = "src/combat/server/Services/VitalsService.luau"

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

# Retired (its rule is now the code): delete it from MUTATIONS, with this successor named.
L1B_W4_FIX_CROWD_RETIRED = {
    "1c: every ground shape has an under side": "l1b w4 fix crowd: only a lob has an under side (R6)",
}

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
# For the economy-designer's mirror_mutants.py, its entry of the same name:
#   ("Melee ignores meleeAbove", "CampBrain", "and above <= rules.meleeAbove", "and true")
