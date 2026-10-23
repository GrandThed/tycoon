# luau-engineer B's L4 W3 FIX ROUND mutants, for the economy-designer to paste into
# tools/crowd_harness/mutate.py after the last MUTATIONS.update(...) and before
# `sys.path.insert(0, str(here))` (the list must be whole before MUTATE_COUNT and `chosen` read it;
# every constant used is already defined there: FLOW, RUN_CREDIT, WAVE_SERVICE, ARENA_SERVICE,
# DEBUG_SERVICE, MAIN_SERVER, RUN_REGISTRY). Two existing entries went stale with the fix round and
# are re-aimed here by key (the update replaces them in place). Verified in a scratch copy of the
# worktree with luau-b-pins.py pasted: every entry occurs once, and every one is caught.
#
# Why: the review's slice 2 m2 (the 19 condition probes that passed the harness) and the fix round's
# F1-F6 (docs/prompts/l4-w3-fix-round.md).

MUTATIONS.update({
    # --- Re-aimed (stale since the fix round) ------------------------------------------------------
    # F6: Validate no longer checks the note (StageFlow.Notes drops it); the mutant now makes a bad
    # note refuse the level again.
    "l4w3b note: never checked": (
        FLOW, "\treactProblems(layout, problem)\n\treturn problems\n",
        "\tfor _, line in (select(2, StageFlow.Notes(level))) do\n\t\tproblem(line)\n\tend\n"
        "\treactProblems(layout, problem)\n\treturn problems\n"),
    # F3: the line's count is `count` now (kills for a kill's key, one for an event).
    "l4w3b credit: no line": (
        RUN_CREDIT, "\tRunLines.Add(summary.lines, key, count, cash, material, materials, valor)\n", ""),
})

L4W3B_FIX_MUTATIONS = {
    # --- F1: once a server ---------------------------------------------------------------------------
    "l4w3b-fix F1: an admit opens again": (
        FLOW, "\tif book.departOpened then\n\t\treturn\n\tend\n\tbook.departOpened = true\n",
        "\tbook.departOpened = true\n"),
    "l4w3b-fix F1: the first admit not remembered": (
        FLOW, "\tbook.departOpened = true\n\tbook.depart = StageFlow.DepartOpen(levelId, difficulty, verified, proving, since)",
        "\tbook.depart = StageFlow.DepartOpen(levelId, difficulty, verified, proving, since)"),
    "l4w3b-fix F1: the session's end reopens (DepartForget)": (
        FLOW, "function StageFlow.DepartForget(book: DepartBook): ()\n\tbook.depart = nil\n",
        "function StageFlow.DepartForget(book: DepartBook): ()\n\tbook.depart = nil\n\tbook.departOpened = false\n"),
    "l4w3b-fix F1: the session's end keeps the auto-start": (
        FLOW, "function StageFlow.DepartForget(book: DepartBook): ()\n\tbook.depart = nil\n",
        "function StageFlow.DepartForget(book: DepartBook): ()\n"),
    "l4w3b-fix F1: R is not an opening": (
        FLOW, "\tbook.departOpened = true\n\treturn book.depart ~= nil", "\treturn book.depart ~= nil"),
    # The ruling's own mutant: Reset clears departOpened again (the pins resetOpened, openedWrites).
    "l4w3b-fix F1: Reset clears the opening": (
        WAVE_SERVICE, "\tStageFlow.DepartForget(boot)\n", "\tStageFlow.DepartForget(boot)\n\tboot.departOpened = false\n"),
    "l4w3b-fix F1: Reset forgets nothing": (WAVE_SERVICE, "\tStageFlow.DepartForget(boot)\n", ""),
    "l4w3b-fix F1: openDepart past the book": (
        WAVE_SERVICE, "\tStageFlow.DepartAdmit(boot, levelId, difficulty, verified, proving, since)\n",
        "\tboot.depart = StageFlow.DepartOpen(levelId, difficulty, verified, proving, since)\n"),
    "l4w3b-fix F1: R past the book": (
        WAVE_SERVICE, "\treturn StageFlow.DepartLever(boot, levelId, difficulty, os.clock())\n",
        "\tboot.depart = StageFlow.DepartOpen(levelId, difficulty, true, nil, os.clock())\n\treturn boot.depart ~= nil\n"),

    # --- s3: the tick's early return -------------------------------------------------------------------
    "l4w3b-fix s3: picked still live": (
        FLOW, '(depart.state == "waiting" or depart.state == "counting")', '(depart.state ~= "done")'),
    "l4w3b-fix s3: counting not live": (FLOW, ' or depart.state == "counting")', ")"),
    "l4w3b-fix s3: no early return": (
        WAVE_SERVICE, "\tif depart == nil or not StageFlow.DepartLive(depart) then\n", "\tif depart == nil then\n"),

    # --- F2: the late arrivals at zero -------------------------------------------------------------------
    "l4w3b-fix F2: nobody late": (FLOW, "\t\tif member.expected or member.body then\n", "\t\tif true then\n"),
    "l4w3b-fix F2: an expected member late": (
        FLOW, "\t\tif member.expected or member.body then\n", "\t\tif member.body then\n"),
    "l4w3b-fix F2: everyone late": (
        FLOW, "\tif starting == 0 then\n\t\treturn {}\n\tend\n\treturn late\n", "\treturn late\n"),
    "l4w3b-fix F2: the auto-start passes no late": (
        WAVE_SERVICE, "refusal = startLevel(player, depart.levelId, depart.difficulty, lateAtZero())",
        "refusal = startLevel(player, depart.levelId, depart.difficulty)"),
    "l4w3b-fix F2: the body rule ignores late": (
        WAVE_SERVICE, "or not VitalsService.AllHaveBodies(starting) then", "or not VitalsService.AllHaveBodies(members) then"),
    "l4w3b-fix F2: late ignored when building the list": (
        WAVE_SERVICE, "\t\t\tif not late[other.userId] then\n\t\t\t\ttable.insert(starting, other)",
        "\t\t\tif true then\n\t\t\t\ttable.insert(starting, other)"),
    "l4w3b-fix F2: a late member placed": (
        WAVE_SERVICE, "\t\tif late ~= nil and late[other.userId] then\n\t\t\tother.waiting = true\n\t\t\tcontinue\n\t\tend\n", ""),
    "l4w3b-fix F2: a late member fighting": (
        WAVE_SERVICE, "\t\t\tother.waiting = true\n\t\t\tcontinue\n", "\t\t\tother.waiting = false\n\t\t\tcontinue\n"),
    "l4w3b-fix F2: late reads no expected list": (
        WAVE_SERVICE, "\t\t\texpected = ArenaService.IsExpected(member.userId),\n", "\t\t\texpected = false,\n"),
    "l4w3b-fix F2: late reads no body": (
        WAVE_SERVICE, "\t\t\tbody = VitalsService.AllHaveBodies({ member }),\n", "\t\t\tbody = false,\n"),
    "l4w3b-fix F2: the leader's own start leaves members behind": (
        WAVE_SERVICE, "\tlocal refusal = startLevel(player, levelId, difficulty)\n",
        "\tlocal refusal = startLevel(player, levelId, difficulty, lateAtZero())\n"),

    # --- s2: the start at zero inside a pcall --------------------------------------------------------------
    "l4w3b-fix s2: no pcall": (
        WAVE_SERVICE,
        "\t\t\tlocal started, problem = pcall(function()\n"
        "\t\t\t\trefusal = startLevel(player, depart.levelId, depart.difficulty, lateAtZero())\n\t\t\tend)\n",
        "\t\t\tlocal started, problem = true, nil\n"
        "\t\t\trefusal = startLevel(player, depart.levelId, depart.difficulty, lateAtZero())\n"),
    "l4w3b-fix s2: a throw is no refusal": (WAVE_SERVICE, '\t\t\t\trefusal = "unavailable"\n', ""),

    # --- F3: a kill's line counts kills --------------------------------------------------------------------
    "l4w3b-fix F3: a share counts a raider": (
        RUN_CREDIT, "local KILL_KINDS: { [string]: boolean } = { raiders = true, boss = true }",
        "local KILL_KINDS: { [string]: boolean } = {}"),
    "l4w3b-fix F3: the boss counts shares": (RUN_CREDIT, "{ raiders = true, boss = true }", "{ raiders = true }"),
    "l4w3b-fix F3: every kind counts kills": (
        RUN_CREDIT, "if KILL_KINDS[key.kind] then kills else CREDIT_COUNT", "kills"),

    # --- F4: P never pays into a real save ------------------------------------------------------------------
    "l4w3b-fix F4: the real store steps": (RUN_CREDIT, '\tif not mock then\n\t\treturn "realStore"\n\tend\n', ""),
    "l4w3b-fix F4: nobody needed": (RUN_CREDIT, '\tif not admitted then\n\t\treturn "nobody"\n\tend\n', ""),
    "l4w3b-fix F4: never asked": (
        WAVE_SERVICE, "\tlocal refusal = RunCredit.PayLeverRefusal(DataService.IsMockMode(), leader ~= nil)\n",
        "\tlocal refusal = nil\n"),
    "l4w3b-fix F4: the store not read": (
        WAVE_SERVICE, "RunCredit.PayLeverRefusal(DataService.IsMockMode(), leader ~= nil)",
        "RunCredit.PayLeverRefusal(true, leader ~= nil)"),
    "l4w3b-fix F4: a refusal still steps": (
        WAVE_SERVICE, "\tif refusal ~= nil then\n\t\treturn current, Combat.EraCashMult(rewards, current), refusal\n\tend\n", ""),
    "l4w3b-fix F4: no notice": (
        DEBUG_SERVICE, '\t\tRunFx.Push({ kind = "notice", text = "P needs Studio API access off" })\n', ""),
    "l4w3b-fix F4: another refusal still says Pay as": (
        DEBUG_SERVICE, "\telseif refusal ~= nil then\n\t\treturn\n", "\telseif refusal ~= nil then\n"),

    # --- F6: a bad note is dropped, never a refusal -----------------------------------------------------------
    "l4w3b-fix F6: a dropped note refuses the level": (
        WAVE_SERVICE, "\tif #problems > 0 or level.difficulties[difficulty] == nil then\n",
        "\tif #problems > 0 or #dropped > 0 or level.difficulties[difficulty] == nil then\n"),
    "l4w3b-fix F6: warned at every read": (
        WAVE_SERVICE, "\tif #dropped > 0 and not boot.warnedNotes[levelId] then\n", "\tif #dropped > 0 then\n"),
    "l4w3b-fix F6: a good note dropped": (FLOW, "\t\t\tkept[name] = note\n", ""),
    "l4w3b-fix F6: a bad note kept": (
        FLOW, "\t\telseif note ~= nil then\n\t\t\tkept[name] = note\n",
        "\t\tend\n\t\tif note ~= nil then\n\t\t\tkept[name] = note\n"),

    # --- F9: one copy of the secret rows -----------------------------------------------------------------------
    "l4w3b-fix F9: no secret rows": (
        WAVE_SERVICE,
        "\treturn MapRules.SecretRows(\n\t\tbuilt,\n\t\tsitesOf,\n\t\tif profile ~= nil then profile.combat.secrets else nil\n\t)\n",
        "\treturn {}\n"),
    "l4w3b-fix F9: nothing opened": (
        WAVE_SERVICE, "\t\tif profile ~= nil then profile.combat.secrets else nil\n\t)\n", "\t\tnil\n\t)\n"),

    # --- The review's 19 condition probes (slice 2 m2), each now a pin ------------------------------------------
    "l4w3b-fix probe 3: a start falls back to picked": (
        WAVE_SERVICE, "\t\tif refusal ~= nil then\n\t\t\tStageFlow.DepartRefused(depart)",
        "\t\tif refusal == nil then\n\t\t\tStageFlow.DepartRefused(depart)"),
    "l4w3b-fix probe 4: no player is no refusal": (
        WAVE_SERVICE, '\t\tlocal refusal: StartRefusal? = "notLeader"\n', "\t\tlocal refusal: StartRefusal? = nil\n"),
    "l4w3b-fix probe 5: the beat never broadcast": (
        WAVE_SERVICE, '\t\t-- A start broadcast its own RunState already.\n\t\tif run.phase == "lobby" then\n\t\t\tbroadcast()\n',
        '\t\t-- A start broadcast its own RunState already.\n\t\tif run.phase == "lobby" then\n'),
    "l4w3b-fix probe 6: ExpectedIn skips a missing member": (
        ARENA_SERVICE, "\t\t\tif not session.everAdmitted[userId] then\n\t\t\t\treturn false\n",
        "\t\t\tif not session.everAdmitted[userId] then\n\t\t\t\tcontinue\n"),
    "l4w3b-fix probe 7: ExpectedIn during the ticket read": (
        ARENA_SERVICE, "function ArenaService.ExpectedIn(): boolean\n\tif not session.open or session.ticketPending then\n\t\treturn false\n\tend\n",
        "function ArenaService.ExpectedIn(): boolean\n"),
    "l4w3b-fix probe 8: PartyIn never by the cap": (
        ARENA_SERVICE, "\treturn session.firstArrivalAt > 0\n\t\tand os.clock() - session.firstArrivalAt >= config.coop.lobbyWaitSeconds\n",
        "\treturn false\n"),
    "l4w3b-fix probe 9: no first arrival": (
        ARENA_SERVICE, "function ArenaService.FirstArrivalAt(): number\n\treturn session.firstArrivalAt\n",
        "function ArenaService.FirstArrivalAt(): number\n\treturn 0\n"),
    "l4w3b-fix probe 10: the wait from 0": (
        WAVE_SERVICE, "\tif since <= 0 then\n\t\tsince = os.clock()\n\tend\n", "\tsince = 0\n"),
    "l4w3b-fix probe 11: an empty hint level": (MAIN_SERVER, '\t\tor levelId == ""\n', ""),
    "l4w3b-fix probe 12: any difficulty length": (MAIN_SERVER, "\t\tor #difficulty > MapRules.MAX_DIFFICULTY_LENGTH\n", ""),
    "l4w3b-fix probe 13: a ticket's level unread": (RUN_REGISTRY, '\t\tor typeof(entry.levelId) ~= "string"\n', ""),
    "l4w3b-fix probe 14: any difficulty verifies": (
        RUN_REGISTRY, "\tif ticket.levelId ~= levelId or ticket.difficulty ~= difficulty then\n",
        "\tif ticket.levelId ~= levelId then\n"),
    "l4w3b-fix probe 15: the mock ticket names nothing": (
        RUN_REGISTRY, "\t\t\tlevelId = levelId,\n\t\t\tdifficulty = difficulty,\n\t\t\tpublic = if combatConfig",
        '\t\t\tlevelId = "",\n\t\t\tdifficulty = difficulty,\n\t\t\tpublic = if combatConfig'),
    "l4w3b-fix probe 16: a manual ask not broadcast": (
        WAVE_SERVICE,
        '\tif refusal ~= "notLeader" and StageFlow.DepartAsked(boot.depart) and run.phase == "lobby" then\n\t\tbroadcast()\n',
        '\tif refusal ~= "notLeader" and StageFlow.DepartAsked(boot.depart) and run.phase == "lobby" then\n'),
    "l4w3b-fix probe 17: the RunState carries no depart": (
        WAVE_SERVICE, '\t\tdepart = StageFlow.DepartView(boot.depart, now, phase == "lobby", lobbyWaitSeconds()),\n',
        "\t\tdepart = nil,\n"),
    "l4w3b-fix probe 18: BuildRunState drops the depart": (
        ARENA_SERVICE, '\t\tdepart = if phase == "lobby" then runFields.depart else nil,\n', ""),
    "l4w3b-fix probe 19: a family-only first clear unlined": (
        WAVE_SERVICE, "\t\tif given ~= nil then\n\t\t\tlocal key = RunCredit.FirstClearKey",
        "\t\tif given ~= nil and given.valor > 0 then\n\t\t\tlocal key = RunCredit.FirstClearKey"),
    "l4w3b-fix probe 20: the host starts at zero": (
        WAVE_SERVICE, "\t\tlocal leader = ArenaService.GetMember(ArenaService.LeaderUserId())\n\t\tlocal player = if leader",
        "\t\tlocal leader = ArenaService.GetMember(ArenaService.GetHostUserId())\n\t\tlocal player = if leader"),
}
MUTATIONS.update(L4W3B_FIX_MUTATIONS)
