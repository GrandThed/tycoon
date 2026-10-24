-- Cases for the L4 W3 fix round's pins (docs/prompts/l4-w3-fix-round.md, "Pins and mutants for everyone's
-- lists"; the economy-designer's): the conditions the hub server, the dungeon server and both clients put
-- round their calls into the shared rules (MapRules, RunLines, TallyRules), read as text by run_harness.py
-- (FIXTURES.source.l4w3fix: L4W3FIX_LINES and L4W3FIX_ORDER), because none of those files loads here; fix
-- round 2's (docs/prompts/l4-w3-fix2.md, G2-G5) follow as L4P.FIX2 (FIXTURES.source.l4w3fix2). A
-- count of 1 is a condition with what it guards, or a call with every argument, standing once in the
-- function it belongs to; 0 is a spelling that must be gone. A key the reading drops, or one it adds,
-- fails too. Appended by run_harness.py after the earlier case files, so every local of theirs is in
-- scope (check, FIXTURES). Everything hangs off the L4P table (the 200-local limit).

print("L4 W3 fix round: the conditions round the shared rules, read as text (pins)")

local L4P: any = {}
L4P.LINES = {
	-- Slice 1 m1: the hub's Depart and SendMap ask the shared rule exactly (L4W3-1), the bridge and the
	-- remotes cap what they take.
	departStars = { 1, "the hub's Depart asks MapRules.Startable with the leader's own stars, the level and difficulty" },
	departVerdict = { 1, "with the level file's difficulties, and refuses on every verdict but ok" },
	departReason = { 1, "answering locked for a locked level and unavailable for the rest" },
	departLeader = { 1, "and only the party leader gets that far (so those stars are the leader's)" },
	sendMapLeader = { 1, "SendMap opens nodes by the party leader's stars" },
	sendMapSolo = { 1, "or the player's own when he leads" },
	sendMapArgs = { 1, "and hands MapState the leader's stars, the player's own and F9's secret rows" },
	bridgeReads = { 1, "the bridge keeps only a card RunLines.ReadSummary reads (F7)" },
	bridgeCards = { 1, "and stores a card nowhere else" },
	bridgeNoOwnReader = { 0, "the bridge has no summary reader of its own (F7)" },
	arrivalCaps = { 1, "ReadArrival caps the level id and the difficulty where the dungeon's start does" },
	expeditionArgs = { 1, "RequestExpedition caps the level id and the difficulty (MapRules)" },
	shortName = { 1, "through isShortName: a string of 1 to the cap's bytes" },
	-- Slice 3 m3: the dungeon lobby acts only on TallyRules' answers; the card's gates.
	uiDepartStep = { 1, "the lobby asks TallyRules.Depart once a RunState, with its own memory" },
	uiDepartKept = { 1, "and keeps the memory it answers (the picked once-per-arrival guard)" },
	uiDepartWrites = { 1, "and writes that memory nowhere else" },
	uiDepartCalls = { 1, "TallyRules.Depart is asked in one place" },
	uiDepartLine = { 1, "the notice line is its answer" },
	uiDepartClose = { 1, "the map closes only on its close (the hold beginning)" },
	uiDepartPick = { 1, "a pick is its select" },
	uiDepartSelect = { 1, "selecting that node and difficulty" },
	uiDepartOpen = { 1, "the map opens only on its open" },
	uiOneOpen = { 1, "and nothing else in a RunState opens it" },
	uiResult = { 1, "a card is built only from what TallyRules.IsRunResult accepts (F15)" },
	uiNoLocalResult = { 0, "no local isRunResult is left (F15)" },
	uiFirstPick = { 1, "the lobby's first map opens on MapRules.FirstPick (F13)" },
	uiWallet = { 1, "the card's wallet is the run's wallet and the profile's combat" },
	tallyFlights = { 1, "the flying icons are TallyRules.Flights on Theme.lowEndDevice" },
	tallyLowEnd = { 1, "and lowEndDevice is read there only" },
	tallyNoReduced = { 0, "never on reducedMotion (true on every touch device)" },
	tallyCoins = { 1, "the coins launched are the planned count" },
	tallyLogs = { 1, "and so are the logs, after their delay" },
	tallyPile = { 1, "the pile has a place for every log" },
	tallyGlyph = { 1, "the Valor badge is a glyph (F14)" },
	tallyNoTurn = { 0, "never a turned element inside the clipped rows (F14)" },
	tallyOneTurn = { 1, "only the flying icons turn" },
	hostSummary = { 1, "the dungeon's card host reads the summary through RunLines.ReadSummary" },
	hostNoReader = { 0, "and has no reader of its own" },
	hostWallet = { 1, "and builds the wallet through TallyRules.Wallet" },
	-- Slice 3 m3 and F7, F11, F12, F13, F16: the city's map and report.
	mapDepartArgs = { 1, "the city map departs with Party & runs' toggle, never a literal (p4)" },
	mapPublicReads = { 1, "and reads the toggle in that one place" },
	mapFirstPick = { 1, "the city map seeds through MapRules.FirstPick (F13)" },
	mapHoldAfterClose = { 1, "opening, it closes the Armory first, then holds the touch controls (F11)" },
	mapReleaseFirst = { 1, "closing, it lets go before the Armory may open (F11)" },
	mapDestroyReleases = { 1, "and Destroy lets go (F11)" },
	mapHolds = { 1, "the map holds in one place" },
	mapReleases = { 2, "and lets go in two (a close and Destroy)" },
	mapNoConfigToast = { 1, "with no Config/Expeditions the Expedition key toasts (F16)" },
	cityWallet = { 1, "the city card's wallet is the city's own cash (p6)" },
	citySummary = { 1, "the city reads a card through RunLines.ReadSummary (F7)" },
	cityNoStar = { 1, "and claims no star: a report of the whole visit (F12)" },
	cityReportShown = { 1, "the report is up while its card is visible (F11)" },
	cityMapNotOverReport = { 1, "the map never opens over the report (F11)" },
	cityArmoryNotOverReport = { 1, "nor the Armory (F11)" },
	cityMapLetsGo = { 1, "the map lets go before the Armory opens (F11)" },
	cityMapClosesArmory = { 1, "the map's open closes the Armory before its hold (F11)" },
	cityReportHolds = { 1, "the report closes the Armory and the map, then holds, then shows (F11)" },
	cityDismissReleases = { 1, "and Dismiss lets go (F11)" },
	cityToast = { 1, "the map's toast is an error toast (F16)" },
	cityHolds = { 1, "the city holds in one place" },
	cityReleases = { 1, "and lets go in one" },
	cityArmoryToggles = { 1, "the Armory toggles in one place" },
	cityMapToggles = { 1, "the map toggles in one place" },
	cityCardHides = { 1, "the card hides in one place" },
}
L4P.ORDER = {
	uiDepartOrder = "the map's decision comes in its order, and before the card's",
}

function L4P.pinTests(): ()
	local reading = FIXTURES.source.l4w3fix
	if reading == nil then
		check(false, "l4w3fix pins: run_harness.py reads no l4w3fix lines")
		return
	end
	check(
		#reading.missing == 0,
		`l4w3fix pins: every function the lines live in is there ({table.concat(reading.missing, ", ")})`
	)
	local unknown = {}
	for key in reading.counts do
		if L4P.LINES[key] == nil then
			table.insert(unknown, key)
		end
	end
	table.sort(unknown)
	check(#unknown == 0, `l4w3fix pins: every line read has an expected count ({table.concat(unknown, ", ")})`)
	local keys = {}
	for key in L4P.LINES do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local expected = L4P.LINES[key]
		local count = reading.counts[key]
		check(count == expected[1], `l4w3fix pins: {expected[2]} ({key}: {tostring(count)}, expected {expected[1]})`)
	end
	local orders = {}
	for key in L4P.ORDER do
		table.insert(orders, key)
	end
	table.sort(orders)
	for _, key in orders do
		check(reading.order[key] == true, `l4w3fix pins: {L4P.ORDER[key]} ({key})`)
	end
	local extra = {}
	for key in reading.order do
		if L4P.ORDER[key] == nil then
			table.insert(extra, key)
		end
	end
	table.sort(extra)
	check(#extra == 0, `l4w3fix pins: every order read has a case ({table.concat(extra, ", ")})`)
end

do
	local ok, problem = pcall(L4P.pinTests)
	if not ok then
		check(false, `l4w3fix pins threw: {tostring(problem)}`)
	end
end

-- Fix round 2 (docs/prompts/l4-w3-fix2.md; the fix-diff review's m2, m3, m4, s1): FIXTURES.source.l4w3fix2,
-- run_harness.py's L4W3FIX2_LINES, START_BLOCK and SESSION_DEFAULT. G1's rule is StageFlow's, run for real
-- in tests_l4w3_run.luau (group "carry"); G3's MapRules.Note in tests_l4w3.luau (group "note").
L4P.FIX2 = {
	-- G2 (m2): the five lines the review's probes passed.
	lateMembers = { 1, "the late set reads every member present (ArenaService.GetMembers, G2 P2)" },
	lateUserId = { 1, "and keys each by its own userId (G2 P1)" },
	secretRowsSites = { 1, "the dungeon's secret rows read each level's chests through sitesOf (G2 P4)" },
	uiPickSeeded = { 1, "a picked depart marks the map seeded, so the first MapState keeps it (G2 Q1)" },
	uiPickArmory = { 1, "and closes the Armory, one sheet at a time (G2 Q2)" },
	uiPickBranch = { 1, "both inside the pick's branch, seeded before the select" },
	-- G3 (m3): one note rule.
	notesAsk = { 1, "StageFlow.Notes keeps what MapRules.Note keeps (G3)" },
	notesKeep = { 1, "the note it answers" },
	notesOwnCap = { 0, "StageFlow keeps no note cap of its own (MapRules.MAX_NOTE_LENGTH is the one home)" },
	notesOwnRule = { 0, "nor a length rule of its own" },
	mapNote = { 1, "the map shows only what MapRules.Note returns (G3)" },
	mapOwnNote = { 0, "and reads no note of its own" },
	-- G4 (m4): the refused arrival's card is titled as the session card.
	returnTitle = { 1, "ReturnService's zero card is titled by ArenaService.SessionName (G4)" },
	returnEmpties = { 1, "and is its only empty card" },
	sessionFallback = { 1, "SessionName is the map's name, else DEFAULT_SESSION_NAME" },
	sessionCards = { 2, "ArenaService's session cards take it too (admit and first read)" },
	sessionDefaults = { 2, "DEFAULT_SESSION_NAME is declared once and read once" },
	-- G5 (s1): the start at zero.
	startTraceback = { 1, "the start at zero runs under xpcall with debug.traceback (G5)" },
	startNoPcall = { 0, "and under no plain pcall" },
	startLobbyOnly = { 1, "a throw refuses only in the lobby; after the level went live it only warns (G5)" },
	startCopy = { 1, "tickDepart's start block stands verbatim in L4W3R.startAtZero, which runs it (G5)" },
}

function L4P.fix2Tests(): ()
	local reading = FIXTURES.source.l4w3fix2
	if reading == nil then
		check(false, "l4w3fix2 pins: run_harness.py reads no l4w3fix2 lines")
		return
	end
	check(
		#reading.missing == 0,
		`l4w3fix2 pins: every function the lines live in is there ({table.concat(reading.missing, ", ")})`
	)
	local unknown = {}
	for key in reading.counts do
		if L4P.FIX2[key] == nil then
			table.insert(unknown, key)
		end
	end
	table.sort(unknown)
	check(#unknown == 0, `l4w3fix2 pins: every line read has an expected count ({table.concat(unknown, ", ")})`)
	local keys = {}
	for key in L4P.FIX2 do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local expected = L4P.FIX2[key]
		local count = reading.counts[key]
		check(count == expected[1], `l4w3fix2 pins: {expected[2]} ({key}: {tostring(count)}, expected {expected[1]})`)
	end
	-- G4: the title a card takes with no Config/Expeditions is one RunLines.ReadSummary keeps, so the hub's
	-- bridge, the city and the dungeon's host never drop a card this place built.
	local default = reading.sessionDefault
	local Lines = load("RunLines")
	local Credit = load("RunCredit")
	check(type(default) == "string", `l4w3fix2: ArenaService declares DEFAULT_SESSION_NAME ({tostring(default)})`)
	check(
		type(default) == "string" and Lines.ReadSummary(Credit.Empty(default)) ~= nil,
		"l4w3fix2: the zero card titled by that default is a card ReadSummary keeps (G4)"
	)
	check(
		Lines.ReadSummary(Credit.Empty(FIXTURES.expeditions.name)) ~= nil,
		"l4w3fix2: and so is one titled by the shipped map's name"
	)
	check(
		Lines.ReadSummary(Credit.Empty("")) == nil,
		"l4w3fix2: an untitled card is dropped (what the zero card was without Config/Expeditions, m4)"
	)
end

do
	local ok, problem = pcall(L4P.fix2Tests)
	if not ok then
		check(false, `l4w3fix2 pins threw: {tostring(problem)}`)
	end
end

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
