# luau-engineer B's L4 W3 FIX ROUND pins, for the economy-designer to paste into
# tools/crowd_harness/run_harness.py right AFTER the L4W3B_ORDER dict (before `def l4w3b_reading`).
# Nothing else in run_harness.py changes: l4w3b_reading reads L4W3B_LINES / L4W3B_ORDER when it runs,
# so the two .update() calls below re-aim the six keys that moved and add the new ones. The expected
# counts are already in tests_l4w3_run.luau (L4W3R.PINS, L4W3R.ORDER). Verified in a scratch copy of
# the worktree: with this block pasted the harness passes, and every mutant in luau-b-mutants.py is
# caught.
#
# Why: the review's slice 2 m2 (19 of 20 condition probes passed the harness: the pins held the call
# lines, not their conditions) and the fix round's F1-F6 (docs/prompts/l4-w3-fix-round.md).

RUN_REGISTRY = "src/combat/server/Services/RunRegistry.luau"

L4W3B_LINES.update({
    # --- Re-aimed (same keys, new text) -------------------------------------------------------------
    # F2 + s2: the start at zero runs inside a pcall closure, with the late arrivals.
    "departStartLevel": (WAVE_SERVICE, body_of("tickDepart"), "lines",
                         "\t\t\t\trefusal = startLevel(player, depart.levelId, depart.difficulty, lateAtZero())"),
    # F1: WaveService writes `boot.depart` nowhere now; StageFlow's DepartAdmit / DepartForget /
    # DepartLever do (expected 0).
    "departWrites": (WAVE_SERVICE, None, "regex", r"\bboot\.depart\s*=(?!=)"),
    "openDepart": (WAVE_SERVICE, body_of("openDepart"), "lines",
                   "\tStageFlow.DepartAdmit(boot, levelId, difficulty, verified, proving, since)"),
    "resetDepart": (WAVE_SERVICE, body_of("WaveService.Reset"), "lines", "\tStageFlow.DepartForget(boot)"),
    # F1: "Reset keeps it" (expected 0): no line of Reset names departOpened.
    "resetOpened": (WAVE_SERVICE, body_of("WaveService.Reset"), "regex", r"\bdepartOpened\b"),

    # --- F1: once a server ---------------------------------------------------------------------------
    "bootOpened": (WAVE_SERVICE, None, "lines", "\tdepartOpened = false,"),
    "openedWrites": (WAVE_SERVICE, None, "regex", r"\bboot\.departOpened\s*=(?!=)"),
    "leverBook": (WAVE_SERVICE, body_of("WaveService.FakeDepart"), "lines",
                  "\treturn StageFlow.DepartLever(boot, levelId, difficulty, os.clock())"),
    # probes 9-10: the wait counts from the first arrival, else now.
    "openSince": (WAVE_SERVICE, body_of("openDepart"), "lines", "\tlocal since = ArenaService.FirstArrivalAt()"),
    "openSinceGuard": (WAVE_SERVICE, body_of("openDepart"), "lines", "\tif since <= 0 then"),
    "openSinceClock": (WAVE_SERVICE, body_of("openDepart"), "lines", "\t\tsince = os.clock()"),

    # --- The tick (probes 3, 4, 5, 20; s2; s3) ---------------------------------------------------------
    "departLive": (WAVE_SERVICE, body_of("tickDepart"), "lines",
                   "\tif depart == nil or not StageFlow.DepartLive(depart) then"),
    "departLeader": (WAVE_SERVICE, body_of("tickDepart"), "lines",
                     "\t\tlocal leader = ArenaService.GetMember(ArenaService.LeaderUserId())"),
    "departNotLeader": (WAVE_SERVICE, body_of("tickDepart"), "lines", '\t\tlocal refusal: StartRefusal? = "notLeader"'),
    "departPlayerGuard": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\tif player ~= nil then"),
    "departPcall": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\t\tlocal started, problem = pcall(function()"),
    "departThrown": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\t\tif not started then"),
    "departThrownRefusal": (WAVE_SERVICE, body_of("tickDepart"), "lines", '\t\t\t\trefusal = "unavailable"'),
    "departRefusedIf": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\tif refusal ~= nil then"),
    "departToastGuard": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\t\tif player ~= nil then"),
    "departBeatLobby": (WAVE_SERVICE, body_of("tickDepart"), "lines", '\t\tif run.phase == "lobby" then'),
    "departBeatBroadcast": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\t\tbroadcast()"),

    # --- F2: the late arrivals at zero, and startLevel's lines for them --------------------------------
    "lateExpected": (WAVE_SERVICE, body_of("lateAtZero"), "lines",
                     "\t\t\texpected = ArenaService.IsExpected(member.userId),"),
    "lateBody": (WAVE_SERVICE, body_of("lateAtZero"), "lines", "\t\t\tbody = VitalsService.AllHaveBodies({ member }),"),
    "lateRule": (WAVE_SERVICE, body_of("lateAtZero"), "lines", "\treturn StageFlow.DepartLate(facts)"),
    "lateCalls": (WAVE_SERVICE, None, "text", "lateAtZero("),
    "startOwnNoLate": (WAVE_SERVICE, body_of("WaveService.OnStartLevel"), "lines",
                       "\tlocal refusal = startLevel(player, levelId, difficulty)"),
    "startStarting": (WAVE_SERVICE, body_of("startLevel"), "lines", "\tlocal starting = members"),
    "startLateAny": (WAVE_SERVICE, body_of("startLevel"), "lines", "\tif late ~= nil and next(late) ~= nil then"),
    "startStartingNew": (WAVE_SERVICE, body_of("startLevel"), "lines", "\t\tstarting = {}"),
    "startNotLate": (WAVE_SERVICE, body_of("startLevel"), "lines", "\t\t\tif not late[other.userId] then"),
    "startNotLateAdd": (WAVE_SERVICE, body_of("startLevel"), "lines", "\t\t\t\ttable.insert(starting, other)"),
    "startBodies": (WAVE_SERVICE, body_of("startLevel"), "lines",
                    "\tif not ArenaService.PartyIn() or not VitalsService.AllHaveBodies(starting) then"),
    "startLateWaits": (WAVE_SERVICE, body_of("startLevel"), "lines", "\t\tif late ~= nil and late[other.userId] then"),
    "startLateWaiting": (WAVE_SERVICE, body_of("startLevel"), "lines", "\t\t\tother.waiting = true"),

    # --- probes 16, 17, 19 -----------------------------------------------------------------------------
    "askedBroadcast": (WAVE_SERVICE, body_of("WaveService.OnStartLevel"), "lines", "\t\tbroadcast()"),
    "pushDepart": (WAVE_SERVICE, body_of("pushRunFields"), "lines",
                   '\t\tdepart = StageFlow.DepartView(boot.depart, now, phase == "lobby", lobbyWaitSeconds()),'),
    "endGiven": (WAVE_SERVICE, body_of("WaveService.EndRun"), "lines", "\t\tif given ~= nil then"),

    # --- F4: P never pays into a real save --------------------------------------------------------------
    "eraRefusal": (WAVE_SERVICE, body_of("WaveService.NextCashEra"), "lines",
                   "\tlocal refusal = RunCredit.PayLeverRefusal(DataService.IsMockMode(), leader ~= nil)"),
    "eraRefused": (WAVE_SERVICE, body_of("WaveService.NextCashEra"), "lines", "\tif refusal ~= nil then"),
    "pRealStore": (DEBUG_SERVICE, body_of("nextCashEra"), "lines", '\tif refusal == "realStore" then'),
    "pRealStoreToast": (DEBUG_SERVICE, body_of("nextCashEra"), "lines",
                        '\t\tRunFx.Push({ kind = "notice", text = "P needs Studio API access off" })'),
    "pOtherRefusal": (DEBUG_SERVICE, body_of("nextCashEra"), "lines", "\telseif refusal ~= nil then"),
    "pReturns": (DEBUG_SERVICE, body_of("nextCashEra"), "lines", "\t\treturn"),

    # --- F6: a bad note is dropped with one warn, never a refusal ---------------------------------------
    "noteRead": (WAVE_SERVICE, body_of("readLevel"), "lines", "\tlocal _, dropped = StageFlow.Notes(level)"),
    "noteWarnOnce": (WAVE_SERVICE, body_of("readLevel"), "lines",
                     "\tif #dropped > 0 and not boot.warnedNotes[levelId] then"),
    "noteRefusal": (WAVE_SERVICE, body_of("readLevel"), "lines",
                    "\tif #problems > 0 or level.difficulties[difficulty] == nil then"),

    # --- F9: one copy of the secret rows -----------------------------------------------------------------
    "secretRowsShared": (WAVE_SERVICE, body_of("secretRows"), "lines", "\treturn MapRules.SecretRows("),
    "secretRowsOpened": (WAVE_SERVICE, body_of("secretRows"), "lines",
                         "\t\tif profile ~= nil then profile.combat.secrets else nil"),
    "secretRowCopies": (WAVE_SERVICE, None, "text", "MapRules.SecretRow("),

    # --- ArenaService (probes 6, 7, 8, 9, 18) ------------------------------------------------------------
    "expectedGuard": (ARENA_SERVICE, body_of("ArenaService.ExpectedIn"), "lines",
                      "\tif not session.open or session.ticketPending then"),
    "expectedMissing": (ARENA_SERVICE, body_of("ArenaService.ExpectedIn"), "lines", "\t\t\t\treturn false"),
    "partyInFirst": (ARENA_SERVICE, body_of("ArenaService.PartyIn"), "lines", "\treturn session.firstArrivalAt > 0"),
    "partyInCap": (ARENA_SERVICE, body_of("ArenaService.PartyIn"), "lines",
                   "\t\tand os.clock() - session.firstArrivalAt >= config.coop.lobbyWaitSeconds"),
    "firstArrival": (ARENA_SERVICE, body_of("ArenaService.FirstArrivalAt"), "lines", "\treturn session.firstArrivalAt"),
    "buildDepart": (ARENA_SERVICE, body_of("ArenaService.BuildRunState"), "lines",
                    '\t\tdepart = if phase == "lobby" then runFields.depart else nil,'),

    # --- Main's hint (probes 11, 12) ---------------------------------------------------------------------
    "hintLevelType": (MAIN_SERVER, body_of("hintPair"), "lines", '\t\ttypeof(levelId) ~= "string"'),
    "hintEmpty": (MAIN_SERVER, body_of("hintPair"), "lines", '\t\tor levelId == ""'),
    "hintLevelCap": (MAIN_SERVER, body_of("hintPair"), "lines", "\t\tor #levelId > MapRules.MAX_LEVEL_ID_LENGTH"),
    "hintDifficultyType": (MAIN_SERVER, body_of("hintPair"), "lines", '\t\tor typeof(difficulty) ~= "string"'),
    "hintDifficultyCap": (MAIN_SERVER, body_of("hintPair"), "lines",
                          "\t\tor #difficulty > MapRules.MAX_DIFFICULTY_LENGTH"),

    # --- RunRegistry's ticket (probes 13, 14, 15) --------------------------------------------------------
    "ticketLevel": (RUN_REGISTRY, body_of("readTicket"), "lines", '\t\tor typeof(entry.levelId) ~= "string"'),
    "ticketDifficulty": (RUN_REGISTRY, body_of("readTicket"), "lines", '\t\tor typeof(entry.difficulty) ~= "string"'),
    "resolveMatch": (RUN_REGISTRY, body_of("RunRegistry.ResolveTicket"), "lines",
                     "\tif ticket.levelId ~= levelId or ticket.difficulty ~= difficulty then"),
    "resolveServer": (RUN_REGISTRY, body_of("RunRegistry.ResolveTicket"), "lines",
                      "\tif ticket.privateServerId ~= expectedPrivateServerId() then"),
    "mockLevel": (RUN_REGISTRY, body_of("RunRegistry.ResolveTicket"), "lines", "\t\t\tlevelId = levelId,"),
    "mockDifficulty": (RUN_REGISTRY, body_of("RunRegistry.ResolveTicket"), "lines", "\t\t\tdifficulty = difficulty,"),
})

L4W3B_ORDER.update({
    # Re-aimed: the rule decides before the start at zero (now inside the pcall closure).
    "departStepThenStart": (WAVE_SERVICE, body_of("tickDepart"),
                            "StageFlow.DepartStep(depart, {",
                            "refusal = startLevel(player, depart.levelId, depart.difficulty, lateAtZero())"),
    # s3: the early return comes before the tick's work.
    "departLiveThenStep": (WAVE_SERVICE, body_of("tickDepart"),
                           "StageFlow.DepartLive(depart)", "StageFlow.DepartStep(depart, {"),
    # F4: the refusal is asked before the pay era steps.
    "eraRefusalThenStep": (WAVE_SERVICE, body_of("WaveService.NextCashEra"),
                           "RunCredit.PayLeverRefusal(", "boot.cashEra = era"),
    # F6: the problems are warned, then the dropped notes, then the verdict.
    "noteThenVerdict": (WAVE_SERVICE, body_of("readLevel"),
                        "StageFlow.Notes(level)", "if #problems > 0 or level.difficulties[difficulty] == nil then"),
})
