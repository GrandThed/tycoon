# luau-engineer B's L4 W3 pins, for the economy-designer to paste into tools/crowd_harness/run_harness.py
# (after l4w2_reading, before the fixtures), with one registration line in source_reading's dict:
#         "l4w3b": l4w3b_reading(text),
# The expected counts live in tests_l4w3_run.luau (L4W3R.PINS, L4W3R.ORDER, group "pins"), as
# L4B's live in tests_l3_w2.luau. Verified in a scratch copy of the checkout: the harness passes with it,
# and every mutant in luau-b-mutants.py is caught.

# L4 W3 (docs/prompts/l4-w3-contract.md §3, §4.1, §5; docs/prompts/l4-w3-reports/luau-b.md): the lines
# that run the auto-start (WaveService.tickDepart, openDepart, OnStartLevel, Reset, the tick), name
# each credit's source (onCrowdKilled, campCleared, EndRun, announceSecret), pay at the era frozen at
# the admit (credit), put the run's last wallet between its last credit and the card (EndRun), and
# freeze the era and write both cards (ArenaService), read as text: neither service loads here.
# tests_l4w3_run.luau's copies (L4W3R.holders, endTail, credit, cardsCredit) are these lines, and its
# "pins" group holds every count. Counted on the code (comments blanked), as L4B_LINES.
L4W3B_LINES = {
    # The auto-start's tick: its facts, its one start, a refusal's fallback, the broadcast.
    "departClear": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\ttable.clear(holders)"),
    "departHolderRule": (WAVE_SERVICE, body_of("tickDepart"), "lines",
                         "\t\tif depart.standIn or ArenaService.IsExpected(member.userId) then"),
    "departHolderAdd": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\t\ttable.insert(holders, member)"),
    "departStep": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\tlocal action = StageFlow.DepartStep(depart, {"),
    "departExpected": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\texpectedIn = ArenaService.ExpectedIn(),"),
    "departHost": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\thostIn = ArenaService.HostIn(),"),
    "departBodies": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\tbodies = VitalsService.AllHaveBodies(holders),"),
    "departWait": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\twaitSeconds = combatConfig.coop.lobbyWaitSeconds,"),
    "departCountdown": (WAVE_SERVICE, body_of("tickDepart"), "lines",
                        "\t\tcountdownSeconds = combatConfig.levels.departCountdownSeconds,"),
    "departStart": (WAVE_SERVICE, body_of("tickDepart"), "lines", '\tif action == "start" then'),
    "departStartLevel": (WAVE_SERVICE, body_of("tickDepart"), "lines",
                         "\t\t\tthen startLevel(player, depart.levelId, depart.difficulty)"),
    "departRefused": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\t\tStageFlow.DepartRefused(depart)"),
    "departToast": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\t\t\t\trefuseStart(player, depart.levelId, refusal)"),
    "departBeat": (WAVE_SERVICE, body_of("tickDepart"), "lines", "\tif beat ~= boot.departBeat then"),
    "departTicked": (WAVE_SERVICE, body_of("tick"), "lines", "\t\ttickDepart(combatConfig)"),
    "departTickCalls": (WAVE_SERVICE, None, "text", "tickDepart("),
    # Who writes the auto-start: openDepart, FakeDepart and Reset only (never a run's end), and never
    # its state (StageFlow's alone).
    "departWrites": (WAVE_SERVICE, None, "regex", r"\bboot\.depart\s*=(?!=)"),
    "departStateWrites": (WAVE_SERVICE, None, "regex", r"\bdepart\.state\s*=(?!=)"),
    "lobbyLeavesDepart": (WAVE_SERVICE, body_of("backToLobby"), "regex", r"\bdepart"),
    "openPick": (WAVE_SERVICE, body_of("openDepart"), "lines", "\tlocal levelId, difficulty, verified = ArenaService.Pick()"),
    "openStudio": (WAVE_SERVICE, body_of("openDepart"), "lines", "\t\t\tand RunService:IsStudio()"),
    "openDepart": (WAVE_SERVICE, body_of("openDepart"), "lines",
                   "\tboot.depart = StageFlow.DepartOpen(levelId, difficulty, verified, proving, since)"),
    "openOnAdmit": (WAVE_SERVICE, body_of("WaveService.OnAdmitted"), "lines", "\topenDepart()"),
    "askedEnds": (WAVE_SERVICE, body_of("WaveService.OnStartLevel"), "lines",
                  '\tif refusal ~= "notLeader" and StageFlow.DepartAsked(boot.depart) and run.phase == "lobby" then'),
    "resetDepart": (WAVE_SERVICE, body_of("WaveService.Reset"), "lines", "\tboot.depart = nil"),
    "resetOpened": (WAVE_SERVICE, body_of("WaveService.Reset"), "lines", "\tboot.departOpened = false"),
    "resetCashEra": (WAVE_SERVICE, body_of("WaveService.Reset"), "lines", "\tboot.cashEra = nil"),
    "fakeStudio": (WAVE_SERVICE, body_of("WaveService.FakeDepart"), "lines",
                   '\tif not RunService:IsStudio() or not boot.mission or run.phase ~= "lobby" then'),
    "eraStudio": (WAVE_SERVICE, body_of("WaveService.NextCashEra"), "lines",
                  "\tif not RunService:IsStudio() or not boot.mission then"),
    # The pay era at the one cash choke point (credit), and nothing else writes a member's era.
    "creditRewards": (WAVE_SERVICE, body_of("credit"), "lines", "\tlocal rewards = combatConfig.rewards"),
    "creditEra": (WAVE_SERVICE, body_of("credit"), "lines", "\t\t\tlocal era = RunCredit.PayEra(member.cashEra, boot.cashEra)"),
    "creditMult": (WAVE_SERVICE, body_of("credit"), "lines",
                   "\t\t\tmults[userId] = Combat.CombatCashMult(state, gameConfig, shopConfig, rewards, era)"),
    "creditKey": (WAVE_SERVICE, body_of("credit"), "lines", "\t\t\tkey,"),
    "creditKiller": (WAVE_SERVICE, body_of("credit"), "lines",
                     "\t\t\tArenaService.CreditSummary(killer, key, 0, material, 0, 0, 1)"),
    "cashMultCalls": (WAVE_SERVICE, None, "text", "Combat.CombatCashMult("),
    "waveEraWrites": (WAVE_SERVICE, None, "regex", r"\.cashEra\s*=(?!=)"),
    # Each credit site's key.
    "killBoss": (WAVE_SERVICE, body_of("onCrowdKilled"), "lines", "\tlocal boss = info.boss and id == run.bossId"),
    "killKey": (WAVE_SERVICE, body_of("onCrowdKilled"), "lines", "\tlocal key = RunCredit.KillKey(boss, info.kind, run.bossName)"),
    "killCredit": (WAVE_SERVICE, body_of("onCrowdKilled"), "lines",
                   "\tcredit({ cash = cash, materials = materials, valor = valor, kills = 1 }, tally, byUserId, key)"),
    "campKey": (WAVE_SERVICE, body_of("campCleared"), "lines", "\t\tlocal key = RunCredit.CampKey(zone.id, zone.name)"),
    "campCredit": (WAVE_SERVICE, body_of("campCleared"), "lines",
                   "\t\tcredit({ cash = cash, materials = materials, valor = 0, kills = 0 }, evenTally(), 0, key)"),
    "chestKey": (WAVE_SERVICE, body_of("announceSecret"), "lines", "\t\tRunCredit.ChestKey(site.id, site.name),"),
    "keyKey": (WAVE_SERVICE, body_of("announceSecret"), "lines",
               "\t\tlocal keyLine = RunCredit.KeyKey(key, if map ~= nil then map.keys else nil)"),
    "keyCredit": (WAVE_SERVICE, body_of("announceSecret"), "lines", '\t\tArenaService.CreditSummary(userId, keyLine, 0, "", 0, 0, 0)'),
    "creditSummaryCalls": (WAVE_SERVICE, None, "text", "ArenaService.CreditSummary("),
    "creditCalls": (WAVE_SERVICE, None, "regex", r"(?m)^\s*credit\("),
    # The run's end: the first clear's line and wallet, then the wallets, then the card.
    "endFirstKey": (WAVE_SERVICE, body_of("WaveService.EndRun"), "lines",
                    "\t\t\tlocal key = RunCredit.FirstClearKey(plan.levelId, plan.difficulty)"),
    "endFirstCredit": (WAVE_SERVICE, body_of("WaveService.EndRun"), "lines",
                       '\t\t\tArenaService.CreditSummary(member.userId, key, 0, "", 0, given.valor, 0)'),
    "endFirstDirty": (WAVE_SERVICE, body_of("WaveService.EndRun"), "lines", "\t\t\trun.walletDirty[member.userId] = true"),
    "endWallets": (WAVE_SERVICE, body_of("WaveService.EndRun"), "lines", "\tsendWallets(os.clock(), true)"),
    "endWalletCalls": (WAVE_SERVICE, body_of("WaveService.EndRun"), "text", "sendWallets("),
    "endCard": (WAVE_SERVICE, body_of("WaveService.EndRun"), "lines", "\tArenaService.BroadcastSummary()"),
    "walletsAll": (WAVE_SERVICE, body_of("sendWallets"), "lines", "\t\tif not all and sentAt ~= nil and now - sentAt < every then"),
    "walletsSend": (WAVE_SERVICE, body_of("sendWallets"), "lines", "\t\t\tArenaService.SendSnapshot(member.player)"),
    # ArenaService: the era frozen at the admit, written once; both cards through RunCredit.
    "admitEra": (ARENA_SERVICE, ADMIT_BODY, "lines", "\t\t\tcashEra = RunCredit.EraOf(state),"),
    "arenaEraWrites": (ARENA_SERVICE, None, "regex", r"\bcashEra\s*=(?!=)"),
    "cardsLoop": (ARENA_SERVICE, body_of("ArenaService.CreditSummary"), "lines",
                  "\tfor _, summary in { runSummaryFor(userId), sessionSummaryFor(userId) } do"),
    "cardsCredit": (ARENA_SERVICE, body_of("ArenaService.CreditSummary"), "lines",
                    "\t\tRunCredit.Credit(summary, key, cash, material, materials, valor, kills)"),
    "mentorLoop": (ARENA_SERVICE, body_of("ArenaService.CreditMentor"), "lines",
                   "\tfor _, summary in { runSummaryFor(userId), sessionSummaryFor(userId) } do"),
    "mentorCredit": (ARENA_SERVICE, body_of("ArenaService.CreditMentor"), "lines", "\t\tRunCredit.Mentor(summary, valor)"),
    "pickVerified": (ARENA_SERVICE, body_of("ArenaService.Pick"), "lines",
                     '\tlocal verified = session.ticket ~= nil and session.levelId ~= ""'),
    "hostIn": (ARENA_SERVICE, body_of("ArenaService.HostIn"), "lines",
               "\treturn session.hostUserId ~= 0 and party[session.hostUserId] ~= nil"),
    "expectedLoop": (ARENA_SERVICE, body_of("ArenaService.ExpectedIn"), "lines", "\t\t\tif not session.everAdmitted[userId] then"),
    "partyInExpected": (ARENA_SERVICE, body_of("ArenaService.PartyIn"), "lines", "\tif ArenaService.ExpectedIn() then"),
}
# (file, function body, the first text, the text that must come after it).
L4W3B_ORDER = {
    "endCreditThenWallets": (WAVE_SERVICE, body_of("WaveService.EndRun"),
                             "ArenaService.CreditSummary(member.userId, key", "sendWallets(os.clock(), true)"),
    "endWalletsThenCard": (WAVE_SERVICE, body_of("WaveService.EndRun"),
                           "sendWallets(os.clock(), true)", "ArenaService.BroadcastSummary()"),
    "killCreditThenMentor": (WAVE_SERVICE, body_of("onCrowdKilled"),
                             "\tcredit({ cash = cash", "\t\tpayMentors(combatConfig, tally)"),
    "departStepThenStart": (WAVE_SERVICE, body_of("tickDepart"),
                            "StageFlow.DepartStep(depart, {", "then startLevel(player, depart.levelId, depart.difficulty)"),
}


def l4w3b_reading(text) -> dict:
    """L4W3B_LINES counted on the code (comments blanked) of the function each belongs to, and the
    L4W3B_ORDER pairs, as l4b_reading reads L4B's."""
    counts, found = {}, {}
    for key, (rel, pattern, how, line) in L4W3B_LINES.items():
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
    for key, (rel, pattern, first, then) in L4W3B_ORDER.items():
        body = pattern.search(luau_code(text(rel)))
        code = body.group(0) if body else ""
        a, b = code.find(first), code.find(then)
        order[key] = a >= 0 and b > a
    return {"counts": counts, "order": order, "missing": sorted(p for p, ok in found.items() if not ok)}
