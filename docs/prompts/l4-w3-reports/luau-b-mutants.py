# luau-engineer B's L4 W3 mutants, for the economy-designer to paste into tools/crowd_harness/mutate.py
# (with RUN_CREDIT added to FILES, as RunCredit.luau is a run_harness.py SOURCES module). Each text
# occurs exactly once in its file; each was run in a scratch copy of the checkout with luau-b-pins.py
# pasted in, and every one is caught (luau-b.md names the run).
RUN_CREDIT = "src/combat/server/Services/RunCredit.luau"
FILES.append(RUN_CREDIT)
L4W3B_MUTATIONS = {
    # StageFlow: the depart rule (tests_l4w3_run.luau "open", "step", "asked", "view", "beat", "lever").
    "l4w3b open: a verified departure only picked": (
        FLOW, 'state = if standIn or verified then "waiting" else "picked",', 'state = if standIn then "waiting" else "picked",'),
    "l4w3b open: a hint alone waits": (
        FLOW, 'state = if standIn or verified then "waiting" else "picked",', 'state = "waiting",'),
    "l4w3b open: the proving pair ignored": (
        FLOW, "local level = if proving ~= nil then proving.levelId else levelId", "local level = levelId"),
    "l4w3b open: no hint still opens": (
        FLOW, '\tif level == "" then\n\t\treturn nil\n\tend\n\treturn {\n\t\tlevelId = level,', "\treturn {\n\t\tlevelId = level,"),
    "l4w3b open: standing in never": (FLOW, "\tlocal standIn = proving ~= nil\n", "\tlocal standIn = false\n"),
    "l4w3b step: the host not needed": (
        FLOW, "local partyIn = (depart.standIn or (input.expectedIn and input.hostIn)) and input.bodies",
        "local partyIn = (depart.standIn or input.expectedIn) and input.bodies"),
    "l4w3b step: the expected list not needed": (
        FLOW, "local partyIn = (depart.standIn or (input.expectedIn and input.hostIn)) and input.bodies",
        "local partyIn = (depart.standIn or input.hostIn) and input.bodies"),
    "l4w3b step: the bodies not needed": (
        FLOW, "local partyIn = (depart.standIn or (input.expectedIn and input.hostIn)) and input.bodies",
        "local partyIn = depart.standIn or (input.expectedIn and input.hostIn)"),
    "l4w3b step: standing in needs the party": (
        FLOW, "local partyIn = (depart.standIn or (input.expectedIn and input.hostIn)) and input.bodies",
        "local partyIn = input.expectedIn and input.hostIn and input.bodies"),
    "l4w3b step: no countdown": (
        FLOW, "depart.startsAt = input.now + seconds(input.countdownSeconds)", "depart.startsAt = input.now"),
    "l4w3b step: the cap never picks": (
        FLOW, "elseif input.now - depart.waitFrom >= seconds(input.waitSeconds) then", "elseif false then"),
    "l4w3b step: the cap a tick late": (
        FLOW, "elseif input.now - depart.waitFrom >= seconds(input.waitSeconds) then",
        "elseif input.now - depart.waitFrom > seconds(input.waitSeconds) then"),
    "l4w3b step: the cap from the session's start": (
        FLOW, "elseif input.now - depart.waitFrom >= seconds(input.waitSeconds) then",
        "elseif input.now >= seconds(input.waitSeconds) then"),
    "l4w3b step: the countdown starts at once": (
        FLOW, 'if depart.state == "counting" and input.now >= depart.startsAt then', 'if depart.state == "counting" then'),
    "l4w3b step: zero a tick late": (
        FLOW, 'if depart.state == "counting" and input.now >= depart.startsAt then',
        'if depart.state == "counting" and input.now > depart.startsAt then'),
    "l4w3b step: a start leaves it counting": (FLOW, '\t\tdepart.state = "done"\n\t\treturn "start"', '\t\treturn "start"'),
    "l4w3b step: seconds take a negative": (
        FLOW, "return if isFinite(value) and value > 0 then value else 0", "return if isFinite(value) then value else 0"),
    "l4w3b step: seconds take a missing key": (
        FLOW, "return if isFinite(value) and value > 0 then value else 0", "return if isFinite(value) and value > 0 then value else 5"),
    "l4w3b asked: the leader's ask changes nothing": (FLOW, '\tdepart.state = "done"\n\treturn true', "\treturn true"),
    "l4w3b asked: a done one changes again": (
        FLOW, 'if depart == nil or depart.state == "done" then\n\t\treturn false', "if depart == nil then\n\t\treturn false"),
    "l4w3b refused: a refusal counts again": (
        FLOW, 'function StageFlow.DepartRefused(depart: Depart): ()\n\tdepart.state = "picked"',
        'function StageFlow.DepartRefused(depart: Depart): ()\n\tdepart.state = "counting"'),
    "l4w3b view: shown outside the lobby": (FLOW, "if depart == nil or not inLobby then", "if depart == nil then"),
    "l4w3b view: the wait rounded down": (
        FLOW, "waitIn = math.max(math.ceil(depart.waitFrom + seconds(waitSeconds) - now), 0),",
        "waitIn = math.max(math.floor(depart.waitFrom + seconds(waitSeconds) - now), 0),"),
    "l4w3b view: the wait under 0": (
        FLOW, "waitIn = math.max(math.ceil(depart.waitFrom + seconds(waitSeconds) - now), 0),",
        "waitIn = math.ceil(depart.waitFrom + seconds(waitSeconds) - now),"),
    "l4w3b view: the countdown rounded down": (
        FLOW, "startsIn = math.max(math.ceil(depart.startsAt - now), 0),",
        "startsIn = math.max(math.floor(depart.startsAt - now), 0),"),
    "l4w3b view: the countdown under 0": (
        FLOW, "startsIn = math.max(math.ceil(depart.startsAt - now), 0),", "startsIn = math.ceil(depart.startsAt - now),"),
    "l4w3b view: done still shown": (
        FLOW, '\t\t\twaitIn = nil,\n\t\t}\n\telse\n\t\treturn nil\n\tend\n\treturn view',
        '\t\t\twaitIn = nil,\n\t\t}\n\telse\n\t\tview = { levelId = depart.levelId, difficulty = depart.difficulty, state = "picked" }\n\tend\n\treturn view'),
    "l4w3b beat: blind to the seconds": (
        FLOW, "return `{view.state}:{view.levelId}:{view.difficulty}:{view.startsIn or -1}:{view.waitIn or -1}`",
        "return `{view.state}:{view.levelId}:{view.difficulty}`"),
    "l4w3b lever: an empty name is a pair": (FLOW, '"^([^:]+):([^:]+)$"', '"^([^:]*):([^:]*)$"'),
    # StageFlow: a difficulty's note (tests_l4w3_run.luau "note").
    "l4w3b note: never checked": (FLOW, "\tnoteProblems(level, problem)\n", ""),
    "l4w3b note: any length": (FLOW, ' or #note > NOTE_MAX_LENGTH) then', ") then"),
    "l4w3b note: empty passes": (FLOW, 'or note == "" or #note > NOTE_MAX_LENGTH', "or #note > NOTE_MAX_LENGTH"),
    "l4w3b note: one byte longer": (FLOW, "local NOTE_MAX_LENGTH = 24", "local NOTE_MAX_LENGTH = 25"),
    # RunCredit: the cards' lines and the pay era (tests_l4w3_run.luau "keys", "empty", "credit", "sites",
    # "era", "frozen").
    "l4w3b credit: no count": (RUN_CREDIT, "local CREDIT_COUNT = 1", "local CREDIT_COUNT = 0"),
    "l4w3b credit: no line": (RUN_CREDIT, "\tRunLines.Add(summary.lines, key, CREDIT_COUNT, cash, material, materials, valor)\n", ""),
    "l4w3b credit: the totals miss the cash": (RUN_CREDIT, "\tsummary.cash += cash\n", ""),
    "l4w3b credit: kills off the totals": (RUN_CREDIT, "\tsummary.kills += kills\n", ""),
    "l4w3b credit: materials with no material": (RUN_CREDIT, 'if materials > 0 and material ~= "" then', "if materials > 0 then"),
    "l4w3b mentor: no line": (RUN_CREDIT, '\tRunLines.Add(summary.lines, RunCredit.MentorKey(), CREDIT_COUNT, 0, "", 0, valor)\n', ""),
    "l4w3b mentor: mentorValor not kept": (RUN_CREDIT, "\tsummary.mentorValor += valor\n", ""),
    "l4w3b keys: every kill a boss": (RUN_CREDIT, '\tif boss then\n\t\treturn { kind = "boss"', '\tif true then\n\t\treturn { kind = "boss"'),
    "l4w3b keys: a boss unnamed": (RUN_CREDIT, "name = bossName or kind }", "name = kind }"),
    "l4w3b keys: raiders keyed by kind": (RUN_CREDIT, 'return { kind = "raiders", id = "raiders", name = "" }', 'return { kind = "raiders", id = kind, name = "" }'),
    "l4w3b keys: a camp keyed by name": (RUN_CREDIT, 'return { kind = "camp", id = id, name = name }', 'return { kind = "camp", id = name, name = name }'),
    "l4w3b keys: a first clear per level": (RUN_CREDIT, 'id = levelId .. ":" .. difficulty', "id = levelId"),
    "l4w3b keys: a chest keyed by name": (RUN_CREDIT, 'return { kind = "chest", id = id, name = name }', 'return { kind = "chest", id = name, name = name }'),
    "l4w3b keys: a key never named": (RUN_CREDIT, "\t\tthen def.name\n\t\telse key", "\t\tthen key\n\t\telse key"),
    "l4w3b keys: an empty key name kept": (RUN_CREDIT, '\t\t\tand def.name ~= ""\n', ""),
    "l4w3b empty: a card with a line": (RUN_CREDIT, "\t\tlines = {},\n", '\t\tlines = { { kind = "raiders", id = "raiders", name = "", count = 0, cash = 0, material = "", materials = 0, valor = 0 } },\n'),
    "l4w3b era: a fraction kept": (RUN_CREDIT, "\t\tor era % 1 ~= 0\n", ""),
    "l4w3b era: 0 kept": (RUN_CREDIT, "\t\tor era < FIRST_ERA\n", ""),
    "l4w3b era: a string read": (RUN_CREDIT, '\t\ttype(era) ~= "number"\n\t\tor era ~= era', "\t\tera ~= era"),
    "l4w3b pay era: the override ignored": (RUN_CREDIT, "return override or cashEra", "return cashEra"),
    "l4w3b pay era: the frozen era ignored": (RUN_CREDIT, "return override or cashEra", "return override or 1"),
    "l4w3b P: never wraps": (RUN_CREDIT, "\tif era >= eraCount then\n\t\treturn FIRST_ERA", "\tif false then\n\t\treturn FIRST_ERA"),
    # WaveService and ArenaService: the wiring the copies stand for (luau-b-pins.py, group "pins").
    "l4w3b pins: a run-list arrival holds the countdown": (
        WAVE_SERVICE, "\t\tif depart.standIn or ArenaService.IsExpected(member.userId) then\n", "\t\tif true then\n"),
    "l4w3b pins: no host needed": (WAVE_SERVICE, "\t\thostIn = ArenaService.HostIn(),\n", "\t\thostIn = true,\n"),
    "l4w3b pins: the countdown from the wait key": (
        WAVE_SERVICE, "\t\tcountdownSeconds = combatConfig.levels.departCountdownSeconds,\n",
        "\t\tcountdownSeconds = combatConfig.coop.lobbyWaitSeconds,\n"),
    "l4w3b pins: a refusal retries": (WAVE_SERVICE, "\t\t\tStageFlow.DepartRefused(depart)\n", ""),
    "l4w3b pins: a refusal is silent": (WAVE_SERVICE, "\t\t\t\trefuseStart(player, depart.levelId, refusal)\n", ""),
    "l4w3b pins: the return re-arms it": (
        WAVE_SERVICE, "\tboot.returnedAt = os.clock()\n",
        "\tboot.returnedAt = os.clock()\n\tboot.depart = StageFlow.DepartOpen(\"forestRoad\", \"normal\", true, nil, os.clock())\n"),
    "l4w3b pins: proving outside Studio": (WAVE_SERVICE, "\t\t\tand RunService:IsStudio()\n", ""),
    "l4w3b pins: the leader's ask leaves it": (
        WAVE_SERVICE, '\tif refusal ~= "notLeader" and StageFlow.DepartAsked(boot.depart) and run.phase == "lobby" then',
        '\tif refusal ~= "notLeader" and run.phase == "lobby" then'),
    "l4w3b pins: the session's end keeps the lever era": (WAVE_SERVICE, "\tboot.cashEra = nil\n", ""),
    "l4w3b pins: paid at the live profile era": (
        WAVE_SERVICE, "\t\t\tlocal era = RunCredit.PayEra(member.cashEra, boot.cashEra)\n",
        "\t\t\tlocal era = RunCredit.PayEra(state.era, boot.cashEra)\n"),
    "l4w3b pins: the lever era ignored": (
        WAVE_SERVICE, "\t\t\tlocal era = RunCredit.PayEra(member.cashEra, boot.cashEra)\n",
        "\t\t\tlocal era = RunCredit.PayEra(member.cashEra, nil)\n"),
    "l4w3b pins: the boss before its own line": (
        WAVE_SERVICE, "\tcredit({ cash = cash, materials = materials, valor = valor, kills = 1 }, tally, byUserId, key)\n\tif boss then\n\t\t-- After",
        "\tif boss then\n\t\tpayMentors(combatConfig, tally)\n\tend\n\tcredit({ cash = cash, materials = materials, valor = valor, kills = 1 }, tally, byUserId, key)\n\tif false then\n\t\t-- After"),
    "l4w3b pins: a camp under the raiders": (
        WAVE_SERVICE, "\t\tlocal key = RunCredit.CampKey(zone.id, zone.name)\n", "\t\tlocal key = RunCredit.KillKey(false, \"\", nil)\n"),
    "l4w3b pins: a key with no line": (WAVE_SERVICE, '\t\tArenaService.CreditSummary(userId, keyLine, 0, "", 0, 0, 0)\n', ""),
    "l4w3b pins: a first clear's wallet left": (WAVE_SERVICE, "\t\t\trun.walletDirty[member.userId] = true\n", ""),
    "l4w3b pins: the wallets before the first clear": (
        WAVE_SERVICE, "\tlocal results: { [number]: Types.RunResult } = {}\n",
        "\tsendWallets(os.clock(), true)\n\tlocal results: { [number]: Types.RunResult } = {}\n"),
    "l4w3b pins: the card before the wallets": (
        WAVE_SERVICE, "\tsendWallets(os.clock(), true)\n\tpushRunFields()\n\tArenaService.BroadcastSummary()\n",
        "\tpushRunFields()\n\tArenaService.BroadcastSummary()\n\tsendWallets(os.clock(), true)\n"),
    "l4w3b pins: the era read again later": (
        ARENA_SERVICE, "\t\t\tcashEra = RunCredit.EraOf(state),\n", "\t\t\tcashEra = 1,\n"),
    "l4w3b pins: the session card without lines": (
        ARENA_SERVICE, "\t\tRunCredit.Credit(summary, key, cash, material, materials, valor, kills)\n",
        "\t\tsummary.cash += cash\n"),
    "l4w3b pins: Pick verifies a hint with no ticket": (
        ARENA_SERVICE, '\tlocal verified = session.ticket ~= nil and session.levelId ~= ""', '\tlocal verified = session.levelId ~= ""'),
}
assert not set(L4W3B_MUTATIONS) & set(MUTATIONS), sorted(set(L4W3B_MUTATIONS) & set(MUTATIONS))
MUTATIONS.update(L4W3B_MUTATIONS)
