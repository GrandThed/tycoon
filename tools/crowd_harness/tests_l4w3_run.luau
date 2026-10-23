-- Cases for L4 W3's run (docs/prompts/l4-w3-contract.md §3, §4.1, §5, §7, §9; luau-engineer B's):
-- the auto-start's rule (StageFlow.DepartOpen, DepartStep, DepartAsked, DepartRefused, DepartView,
-- DepartBeat, DepartPair) at every edge; what each credit site writes on a card (RunCredit's keys,
-- Credit and Mentor, on RunLines); the pay era frozen at the admit (RunCredit.EraOf, PayEra,
-- NextPayEra, through the real Combat.CombatCashMult); the run's last wallet after its last credit
-- and before the card; a difficulty's `note` (Validate, StageFlow.Notes). The fix round's cases
-- (docs/prompts/l4-w3-fix-round.md): once a server (F1, group server), the late arrivals at zero (F2,
-- late), a kill's line counting kills (F3, kills), P on the mock store only (F4, payLever), the tick's
-- early return (s3, live), a bad note dropped (F6, note). StageFlow, RunCredit, RunLines and Combat
-- are loaded as they stand. WaveService and ArenaService cannot be loaded here: L4W3R.holders,
-- L4W3R.starting, L4W3R.endTail, L4W3R.credit and L4W3R.cardsCredit below are their lines, copied
-- line for line, and run_harness.py reads those lines as text so a copy cannot drift. Appended by
-- run_harness.py after the earlier case files, so every local of those is in scope (check, load,
-- near, FIXTURES, L1). Everything hangs off the L4W3R table (the 200-local limit), and every group
-- runs behind L4W3R.group, so a group that throws fails one check and the bundle goes on. Last in
-- TESTS: it ends with the verdict line (run_harness.py strips that line from every file but the
-- last).

print("L4 W3: the auto-start, the cards' lines, the pay era, the wallet before the card")

-- A module of this file, or nil when the bundle has none (its groups then fail, the bundle goes on).
local L4W3R: any = {}
function L4W3R.load(name: string): any
	local ok, loaded = pcall(load, name)
	if not ok then
		check(false, `l4w3 run: run_harness.py SOURCES has no {name} ({tostring(loaded)})`)
		return nil
	end
	return loaded
end
L4W3R = {
	load = L4W3R.load,
	Flow = L4W3R.load("StageFlow"),
	Credit = L4W3R.load("RunCredit"),
	Lines = L4W3R.load("RunLines"),
	Combat = L4W3R.load("Combat"),
	NAN = 0 / 0,
	-- A value that takes a key away in `over` (nil cannot be written into a table).
	NONE = {},
}

function L4W3R.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `l4w3 run {name} stopped: {tostring(problem)}`)
	end
end

-- One tick's facts, every one true unless `over` says otherwise; the wait 30 s, the countdown 5 s.
function L4W3R.input(now: number, over: any?): any
	local input: any = {
		now = now,
		expectedIn = true,
		hostIn = true,
		bodies = true,
		waitSeconds = 30,
		countdownSeconds = 5,
	}
	for key, value in over or {} do
		input[key] = if value == L4W3R.NONE then nil else value
	end
	return input
end

-- A verified departure opened at `since` (waiting, no stand-in).
function L4W3R.waiting(since: number): any
	return L4W3R.Flow.DepartOpen("forestRoad", "normal", true, nil, since)
end

-- The lines' kinds in order, as one string.
function L4W3R.kinds(lines: { any }): string
	local kinds = {}
	for _, line in lines do
		table.insert(kinds, line.kind)
	end
	return table.concat(kinds, ",")
end

-- The line of `kind` and `id`, or nil.
function L4W3R.line(lines: { any }, kind: string, id: string): any
	for _, line in lines do
		if line.kind == kind and line.id == id then
			return line
		end
	end
	return nil
end

-- WaveService.tickDepart's bodies, line for line (run_harness.py reads them): the expected members
-- present, everyone present with `standIn`. `members` = { userId, body }, `expected` = a set.
function L4W3R.holders(depart: any, members: { any }, expected: { [number]: boolean }): boolean
	local ArenaService = {
		GetMembers = function()
			return members
		end,
		IsExpected = function(userId: number): boolean
			return expected[userId] == true
		end,
	}
	local VitalsService = {
		AllHaveBodies = function(list: { any }): boolean
			for _, member in list do
				if not member.body then
					return false
				end
			end
			return true
		end,
	}
	local holders = {}
	table.clear(holders)
	for _, member in ArenaService.GetMembers() do
		if depart.standIn or ArenaService.IsExpected(member.userId) then
			table.insert(holders, member)
		end
	end
	return VitalsService.AllHaveBodies(holders)
end

-- WaveService.startLevel's body rule and placement for the auto-start's late arrivals (F2), line for
-- line (run_harness.py reads them): whether the start goes ahead, and who is placed or left waiting.
-- `members` = { userId, body, waiting }, `late` = StageFlow.DepartLate's set (nil: the leader's own).
function L4W3R.starting(members: { any }, late: { [number]: boolean }?): (boolean, { number })
	local VitalsService = {
		AllHaveBodies = function(list: { any }): boolean
			for _, member in list do
				if not member.body then
					return false
				end
			end
			return true
		end,
	}
	local ArenaService = {
		PartyIn = function(): boolean
			return true
		end,
	}
	local starting = members
	if late ~= nil and next(late) ~= nil then
		starting = {}
		for _, other in members do
			if not late[other.userId] then
				table.insert(starting, other)
			end
		end
	end
	if not ArenaService.PartyIn() or not VitalsService.AllHaveBodies(starting) then
		return false, {}
	end
	local placed: { number } = {}
	for _, other in members do
		if late ~= nil and late[other.userId] then
			other.waiting = true
			continue
		end
		other.waiting = false
		table.insert(placed, other.userId)
	end
	return true, placed
end

-- ArenaService.CreditSummary and CreditMentor, line for line: both cards, through RunCredit.
function L4W3R.cardsCredit(
	cards: { any },
	key: any,
	cash: number,
	material: string,
	materials: number,
	valor: number,
	kills: number
): ()
	local RunCredit = L4W3R.Credit
	for _, summary in { cards[1], cards[2] } do
		RunCredit.Credit(summary, key, cash, material, materials, valor, kills)
	end
end

function L4W3R.cardsMentor(cards: { any }, valor: number): ()
	local RunCredit = L4W3R.Credit
	for _, summary in { cards[1], cards[2] } do
		RunCredit.Mentor(summary, valor)
	end
end

-- WaveService.credit's pay era, line for line: each member's multiplier at the one cash choke
-- point (Combat.CombatCashMult), the era RunCredit.PayEra gives (frozen at the admit, or the P
-- lever's session override).
function L4W3R.credit(
	members: { [number]: any },
	states: { [number]: any },
	override: number?,
	rewards: any
): { [number]: number }
	local Combat = L4W3R.Combat
	local RunCredit = L4W3R.Credit
	local boot = { cashEra = override }
	local gameConfig = { legacy = { incomePerPoint = 0.1 } }
	local shopConfig = { perks = {} }
	local mults: { [number]: number } = {}
	for userId, member in members do
		local state = states[userId]
		if member ~= nil and state ~= nil then
			local era = RunCredit.PayEra(member.cashEra, boot.cashEra)
			mults[userId] = Combat.CombatCashMult(state, gameConfig, shopConfig, rewards, era)
		end
	end
	return mults
end

-- WaveService.EndRun's tail, line for line from the first clear's credit to the card: `log` gets
-- "credit <id>", "snapshot <id>" and "card" in the order they happen. `members` = { userId,
-- given }, `dirty` = the wallets a run's credits left unsent (L1b-16).
function L4W3R.endTail(members: { any }, dirty: { [number]: boolean }, log: { string }): ()
	local RunCredit = L4W3R.Credit
	local run = { walletDirty = dirty, walletSentAt = {} }
	local plan = { levelId = "forestRoad", difficulty = "hard" }
	local ArenaService = {
		GetMembers = function()
			return members
		end,
		CreditSummary = function(
			userId: number,
			_key: any,
			_cash: number,
			_material: string,
			_materials: number,
			_valor: number,
			_kills: number
		)
			table.insert(log, `credit {userId}`)
		end,
		GetMember = function(userId: number): any
			for _, member in members do
				if member.userId == userId then
					return member
				end
			end
			return nil
		end,
		SendSnapshot = function(player: any)
			table.insert(log, `snapshot {player}`)
		end,
		BroadcastSummary = function()
			table.insert(log, "card")
		end,
	}
	local function sendWallets(now: number, all: boolean): ()
		local every = 1
		for userId in run.walletDirty do
			local sentAt = run.walletSentAt[userId]
			if not all and sentAt ~= nil and now - sentAt < every then
				continue
			end
			run.walletDirty[userId] = nil
			run.walletSentAt[userId] = now
			local member = ArenaService.GetMember(userId)
			if member ~= nil then
				ArenaService.SendSnapshot(member.player)
			end
		end
	end
	local function pushRunFields(): () end
	for _, member in ArenaService.GetMembers() do
		local given = member.given
		if given ~= nil then
			local key = RunCredit.FirstClearKey(plan.levelId, plan.difficulty)
			ArenaService.CreditSummary(member.userId, key, 0, "", 0, given.valor, 0)
			run.walletDirty[member.userId] = true
		end
	end
	-- After the run's last credit (the first clears above) and before the card (§4.1).
	sendWallets(os.clock(), true)
	pushRunFields()
	ArenaService.BroadcastSummary()
end

-- The auto-start opens ------------------------------------------------------------------------------

L4W3R.group("open", function()
	local Flow = L4W3R.Flow
	local verified = Flow.DepartOpen("forestRoad", "hard", true, nil, 12)
	check(
		verified ~= nil
			and verified.state == "waiting"
			and verified.levelId == "forestRoad"
			and verified.difficulty == "hard"
			and verified.standIn == false
			and verified.waitFrom == 12
			and verified.startsAt == 0,
		"open: a verified departure waits for its party on its own pair, from the first arrival"
	)
	local hinted = Flow.DepartOpen("forestRoad", "hard", false, nil, 12)
	check(
		hinted ~= nil
			and hinted.state == "picked"
			and hinted.levelId == "forestRoad"
			and hinted.difficulty == "hard",
		"open: a hint the ticket did not verify (none, a mismatch, an old shape) is only picked on the map"
	)
	check(
		Flow.DepartOpen("", "", true, nil, 12) == nil,
		"open: no hint is nothing, even with a ticket"
	)
	check(Flow.DepartOpen("", "", false, nil, 12) == nil, "open: no hint and no ticket is nothing")
	local proving = Flow.DepartOpen(
		"castle",
		"brutal",
		false,
		{ levelId = "forestRoad", difficulty = "normal" },
		3
	)
	check(
		proving ~= nil
			and proving.state == "waiting"
			and proving.standIn == true
			and proving.levelId == "forestRoad"
			and proving.difficulty == "normal"
			and proving.waitFrom == 3,
		"open: a proving boot with provingAutoStart waits on its own pair with the present standing in, whatever the hint (L4W3-12)"
	)
	local provingNoHint =
		Flow.DepartOpen("", "", false, { levelId = "forestRoad", difficulty = "normal" }, 3)
	check(
		provingNoHint ~= nil and provingNoHint.state == "waiting" and provingNoHint.standIn,
		"open: a proving boot with no hint still waits (Play alone reaches the countdown)"
	)
	check(
		Flow.DepartOpen("forestRoad", "normal", true, { levelId = "", difficulty = "normal" }, 3)
			== nil,
		"open: a proving pair with no level is nothing"
	)
end)

-- The auto-start's tick --------------------------------------------------------------------------------

L4W3R.group("step", function()
	local Flow = L4W3R.Flow
	local depart = L4W3R.waiting(0)
	check(
		Flow.DepartStep(depart, L4W3R.input(1)) == nil,
		"step: waiting -> counting answers nothing yet"
	)
	check(
		depart.state == "counting" and near(depart.startsAt, 6),
		"step: once the party is in, the countdown starts (5 s)"
	)
	check(
		Flow.DepartStep(depart, L4W3R.input(5.99)) == nil and depart.state == "counting",
		"step: nothing before zero"
	)
	check(
		Flow.DepartStep(depart, L4W3R.input(6)) == "start" and depart.state == "done",
		"step: at zero, start once and done"
	)
	check(
		Flow.DepartStep(depart, L4W3R.input(7)) == nil and depart.state == "done",
		"step: done never starts again"
	)

	for _, missing in { "expectedIn", "hostIn", "bodies" } do
		local held = L4W3R.waiting(0)
		Flow.DepartStep(held, L4W3R.input(10, { [missing] = false }))
		check(held.state == "waiting", `step: without {missing} the party is not in, it waits`)
		Flow.DepartStep(held, L4W3R.input(29.99, { [missing] = false }))
		check(held.state == "waiting", `step: without {missing}, still waiting just before the cap`)
		check(
			Flow.DepartStep(held, L4W3R.input(30, { [missing] = false })) == nil
				and held.state == "picked",
			`step: without {missing} at the cap, picked on the map (no start)`
		)
	end
	local atCap = L4W3R.waiting(0)
	Flow.DepartStep(atCap, L4W3R.input(30))
	check(
		atCap.state == "counting",
		"step: a party in at the cap's very moment counts down (in wins over the cap)"
	)

	local standIn = Flow.DepartOpen(
		"forestRoad",
		"normal",
		false,
		{ levelId = "forestRoad", difficulty = "normal" },
		0
	)
	Flow.DepartStep(standIn, L4W3R.input(1, { expectedIn = false, hostIn = false }))
	check(
		standIn.state == "counting",
		"step: standing in, the bodies alone decide (no expected list, no host)"
	)
	local standInNoBody = Flow.DepartOpen(
		"forestRoad",
		"normal",
		false,
		{ levelId = "forestRoad", difficulty = "normal" },
		0
	)
	Flow.DepartStep(
		standInNoBody,
		L4W3R.input(1, { expectedIn = false, hostIn = false, bodies = false })
	)
	check(standInNoBody.state == "waiting", "step: standing in, a body still spawning holds it")

	local counting = L4W3R.waiting(0)
	Flow.DepartStep(counting, L4W3R.input(1))
	check(
		Flow.DepartStep(
			counting,
			L4W3R.input(6, { expectedIn = false, hostIn = false, bodies = false })
		) == "start",
		"step: leaving during the countdown stops nothing (whoever leads at zero starts it)"
	)
	local late = L4W3R.waiting(0)
	Flow.DepartStep(late, L4W3R.input(1))
	check(
		Flow.DepartStep(late, L4W3R.input(500)) == "start",
		"step: a tick that comes late still starts once"
	)

	local picked = Flow.DepartOpen("forestRoad", "normal", false, nil, 0)
	check(
		Flow.DepartStep(picked, L4W3R.input(1)) == nil and picked.state == "picked",
		"step: picked never moves, whatever the party does"
	)

	local noCountdown = L4W3R.waiting(0)
	Flow.DepartStep(noCountdown, L4W3R.input(2, { countdownSeconds = L4W3R.NONE }))
	check(
		noCountdown.state == "counting" and noCountdown.startsAt == 2,
		"step: no countdown key starts at once (degrade)"
	)
	for _, bad in { L4W3R.NAN, -5, math.huge } do
		local odd = L4W3R.waiting(0)
		Flow.DepartStep(odd, L4W3R.input(2, { countdownSeconds = bad }))
		check(odd.startsAt == 2, `step: a countdown of {tostring(bad)} starts at once`)
	end
	local noWait = L4W3R.waiting(0)
	Flow.DepartStep(noWait, L4W3R.input(0, { waitSeconds = L4W3R.NONE, bodies = false }))
	check(noWait.state == "picked", "step: no wait key: a party not in is picked at once (degrade)")
	local waitFrom = L4W3R.waiting(100)
	Flow.DepartStep(waitFrom, L4W3R.input(129, { bodies = false }))
	check(
		waitFrom.state == "waiting",
		"step: the wait counts from waitFrom (the first arrival or R's press)"
	)
	Flow.DepartStep(waitFrom, L4W3R.input(130, { bodies = false }))
	check(waitFrom.state == "picked", "step: and ends coop.lobbyWaitSeconds after it")
end)

-- The leader's own start, a refusal at zero ----------------------------------------------------------

L4W3R.group("asked", function()
	local Flow = L4W3R.Flow
	for _, state in { "waiting", "counting", "picked" } do
		local depart = L4W3R.waiting(0)
		depart.state = state
		check(
			Flow.DepartAsked(depart) == true and depart.state == "done",
			`asked: the leader's own start ends a {state} auto-start`
		)
	end
	local done = L4W3R.waiting(0)
	done.state = "done"
	check(
		Flow.DepartAsked(done) == false and done.state == "done",
		"asked: a done one says nothing changed"
	)
	check(Flow.DepartAsked(nil) == false, "asked: no auto-start says nothing changed")
	local refused = L4W3R.waiting(0)
	Flow.DepartStep(refused, L4W3R.input(1))
	check(Flow.DepartStep(refused, L4W3R.input(6)) == "start", "refused: zero answers start")
	Flow.DepartRefused(refused)
	check(
		refused.state == "picked",
		"refused: a refusal at zero leaves the level picked on the map"
	)
	check(
		Flow.DepartStep(refused, L4W3R.input(7)) == nil and refused.state == "picked",
		"refused: and never retries"
	)
end)

-- What the wire shows -------------------------------------------------------------------------------------

L4W3R.group("view", function()
	local Flow = L4W3R.Flow
	check(Flow.DepartView(nil, 0, true, 30) == nil, "view: none is nil")
	local depart = L4W3R.waiting(0)
	check(Flow.DepartView(depart, 0, false, 30) == nil, "view: nil outside the lobby")
	local waiting = Flow.DepartView(depart, 4.2, true, 30)
	check(
		waiting ~= nil
			and waiting.state == "waiting"
			and waiting.levelId == "forestRoad"
			and waiting.difficulty == "normal"
			and waiting.waitIn == 26
			and waiting.startsIn == nil,
		"view: waiting shows what is left of the wait, a whole number rounded up (25.8 -> 26)"
	)
	local over = Flow.DepartView(depart, 40, true, 30)
	check(over ~= nil and over.waitIn == 0, "view: never under 0")
	Flow.DepartStep(depart, L4W3R.input(10))
	local counting = Flow.DepartView(depart, 10.5, true, 30)
	check(
		counting ~= nil
			and counting.state == "counting"
			and counting.startsIn == 5
			and counting.waitIn == nil,
		"view: counting shows the seconds to the start, rounded up (4.5 -> 5)"
	)
	check(Flow.DepartView(depart, 14.01, true, 30).startsIn == 1, "view: 0.99 s left reads 1")
	check(Flow.DepartView(depart, 15, true, 30).startsIn == 0, "view: at zero reads 0")
	check(
		Flow.DepartView(depart, 16, true, 30).startsIn == 0,
		"view: past zero still reads 0, never under"
	)
	depart.state = "picked"
	local picked = Flow.DepartView(depart, 20, true, 30)
	check(
		picked ~= nil
			and picked.state == "picked"
			and picked.startsIn == nil
			and picked.waitIn == nil,
		"view: picked carries the pair only"
	)
	depart.state = "done"
	check(Flow.DepartView(depart, 20, true, 30) == nil, "view: done is nil")
end)

L4W3R.group("beat", function()
	local Flow = L4W3R.Flow
	check(Flow.DepartBeat(nil) == "", "beat: none is the empty beat")
	local depart = L4W3R.waiting(0)
	local a = Flow.DepartBeat(Flow.DepartView(depart, 1.1, true, 30))
	local b = Flow.DepartBeat(Flow.DepartView(depart, 1.9, true, 30))
	local c = Flow.DepartBeat(Flow.DepartView(depart, 2.1, true, 30))
	check(a == b, "beat: the same within a whole second")
	check(a ~= c, "beat: a new one at each whole second of the wait")
	Flow.DepartStep(depart, L4W3R.input(2.1))
	local d = Flow.DepartBeat(Flow.DepartView(depart, 2.1, true, 30))
	check(d ~= c, "beat: a new one when the state changes")
	local e = Flow.DepartBeat(Flow.DepartView(depart, 3.2, true, 30))
	check(e ~= d, "beat: a new one at each whole second of the countdown")
	check(
		Flow.DepartBeat(Flow.DepartView(depart, 3.2, false, 30)) == "",
		"beat: leaving the lobby is a change too"
	)
end)

-- The R lever --------------------------------------------------------------------------------------------

L4W3R.group("lever", function()
	local Flow = L4W3R.Flow
	local level, difficulty = Flow.DepartPair("forestRoad:hard", "x", "y")
	check(
		level == "forestRoad" and difficulty == "hard",
		"R: the map's selection, <levelId>:<difficulty>"
	)
	for _, odd in { "", "forestRoad", "forestRoad:", ":hard", "a:b:c", 7, true, nil } do
		local l, d = Flow.DepartPair(odd, "forestRoad", "normal")
		check(l == "forestRoad" and d == "normal", `R: "{tostring(odd)}" is the proving pair`)
	end
	-- WaveService.FakeDepart opens the pair with itself standing in, from the press.
	local pair = { levelId = "forestRoad", difficulty = "hard" }
	local fake = Flow.DepartOpen("forestRoad", "hard", true, pair, 50)
	check(
		fake ~= nil and fake.state == "waiting" and fake.standIn and fake.waitFrom == 50,
		"R: waits from the press, the present standing in"
	)
	Flow.DepartStep(fake, L4W3R.input(51, { expectedIn = false, hostIn = false }))
	check(
		fake.state == "counting",
		"R: the members present are the party (a session without the departed list)"
	)
	check(Flow.DepartStep(fake, L4W3R.input(56)) == "start", "R: then the real countdown starts it")
end)

-- The bodies it waits for (WaveService.tickDepart's lines) -------------------------------------------------

L4W3R.group("holders", function()
	local depart = L4W3R.waiting(0)
	local members = {
		{ userId = 1, body = true },
		{ userId = 2, body = false },
	}
	check(
		L4W3R.holders(depart, members, { [1] = true }) == true,
		"holders: an arrival from the run list never holds the countdown"
	)
	check(
		L4W3R.holders(depart, members, { [1] = true, [2] = true }) == false,
		"holders: an expected member still spawning holds it"
	)
	depart.standIn = true
	check(
		L4W3R.holders(depart, members, { [1] = true }) == false,
		"holders: standing in, everyone present counts"
	)
	check(L4W3R.holders(depart, {}, {}) == true, "holders: nobody to wait for holds nothing")
end)

-- A whole session, frame by frame -------------------------------------------------------------------------

L4W3R.group("session", function()
	local Flow = L4W3R.Flow
	-- A party of two departs; the second arrives at 12 s, its body stands at 14 s.
	local depart = L4W3R.waiting(0)
	local started = 0
	local startedAt = -1
	local t = 0
	while t <= 40 do
		local input = L4W3R.input(t, { expectedIn = t >= 12, bodies = t >= 14 })
		if Flow.DepartStep(depart, input) == "start" then
			started += 1
			startedAt = t
		end
		t += 0.25
	end
	check(
		started == 1 and near(startedAt, 19),
		"session: the party in at 14 s starts once, 5 s later"
	)
	-- The second never comes: picked at the cap, nothing starts.
	local alone = L4W3R.waiting(0)
	local starts = 0
	t = 0
	while t <= 40 do
		if Flow.DepartStep(alone, L4W3R.input(t, { expectedIn = false })) == "start" then
			starts += 1
		end
		t += 0.25
	end
	check(
		starts == 0 and alone.state == "picked",
		"session: a member missing at the cap: picked, nothing starts"
	)
	-- After the run nothing re-arms it: done stays done for good.
	local after = L4W3R.waiting(0)
	Flow.DepartStep(after, L4W3R.input(1))
	Flow.DepartStep(after, L4W3R.input(6))
	local again = 0
	for frame = 7, 600 do
		if Flow.DepartStep(after, L4W3R.input(frame)) == "start" then
			again += 1
		end
	end
	check(
		again == 0 and Flow.DepartView(after, 600, true, 30) == nil,
		"session: nothing auto-starts after a run (L4W3-4)"
	)
end)

-- Once a server (the fix round's F1) -----------------------------------------------------------------

-- WaveService's boot as StageFlow.DepartBook sees it, on a new server.
function L4W3R.book(): any
	return { depart = nil, departOpened = false }
end

L4W3R.group("server", function()
	local Flow = L4W3R.Flow
	-- A solo departure: the hub's ticket verifies Forest Road Normal.
	local book = L4W3R.book()
	Flow.DepartAdmit(book, "forestRoad", "normal", true, nil, 0)
	check(
		book.departOpened == true and book.depart ~= nil and book.depart.state == "waiting",
		"server: the server's first admit opens the verified departure"
	)
	local first = book.depart
	Flow.DepartAdmit(book, "forestRoad", "hard", true, nil, 3)
	check(
		book.depart == first and first.difficulty == "normal" and first.waitFrom == 0,
		"server: a later admit in the same session opens nothing"
	)
	-- Arm and run: the countdown, then the start at zero.
	Flow.DepartStep(book.depart, L4W3R.input(1))
	check(Flow.DepartStep(book.depart, L4W3R.input(6)) == "start", "server: it starts the run once")
	-- The player clears it and presses Return: the last member leaves, the session ends (Reset).
	Flow.DepartForget(book)
	check(book.depart == nil, "server: the session's end forgets the auto-start")
	check(book.departOpened == true, "server: and keeps that this server opened one (F1)")
	-- The trip home fails; the rejoin re-reads the same join data and the hub's ticket still verifies.
	Flow.DepartAdmit(book, "forestRoad", "normal", true, nil, 100)
	check(
		book.depart == nil,
		"server: a rejoin with the same verified ticket opens nothing: no waiting, no counting (F1)"
	)
	local starts, shown = 0, 0
	for frame = 100, 160 do
		Flow.DepartAdmit(book, "forestRoad", "normal", true, nil, frame)
		local depart = book.depart
		if Flow.DepartLive(depart) and Flow.DepartStep(depart, L4W3R.input(frame)) == "start" then
			starts += 1
		end
		if Flow.DepartBeat(Flow.DepartView(book.depart, frame, true, 30)) ~= "" then
			shown += 1
		end
	end
	check(
		starts == 0 and shown == 0,
		"server: a minute after the rejoin nothing has started and the wire shows no countdown and no pick"
	)
	Flow.DepartAdmit(book, "", "", false, { levelId = "forestRoad", difficulty = "normal" }, 200)
	check(book.depart == nil, "server: nor a proving boot's stand-in after the session's end")

	-- A hint the ticket did not verify: picked once, never forced open again after the session's end.
	local hinted = L4W3R.book()
	Flow.DepartAdmit(hinted, "forestRoad", "normal", false, nil, 0)
	check(
		hinted.depart ~= nil and hinted.depart.state == "picked",
		"server: a hint alone is picked"
	)
	Flow.DepartForget(hinted)
	Flow.DepartAdmit(hinted, "forestRoad", "normal", false, nil, 50)
	check(
		hinted.depart == nil and Flow.DepartView(hinted.depart, 50, true, 30) == nil,
		"server: after the session's end a rejoin is not picked again (the map is not forced open)"
	)

	-- R still works on a server that has opened one, from its press, standing in.
	check(
		Flow.DepartLever(book, "forestRoad", "hard", 300) == true
			and book.depart ~= nil
			and book.depart.state == "waiting"
			and book.depart.standIn
			and book.depart.difficulty == "hard"
			and book.depart.waitFrom == 300
			and book.departOpened,
		"server: R waits on its pair after the session's end"
	)
	check(
		Flow.DepartLever(book, "", "hard", 301) == false and book.depart == nil,
		"server: R on a pair with no level is nothing"
	)
	local lever = L4W3R.book()
	Flow.DepartLever(lever, "forestRoad", "normal", 5)
	Flow.DepartAdmit(lever, "forestRoad", "hard", true, nil, 6)
	check(
		lever.departOpened and lever.depart ~= nil and lever.depart.difficulty == "normal",
		"server: R counts as the server's opening (a later admit does not replace it)"
	)

	-- A session that ended before anybody was admitted leaves the first admit its own.
	local empty = L4W3R.book()
	Flow.DepartForget(empty)
	Flow.DepartAdmit(empty, "forestRoad", "normal", true, nil, 0)
	check(
		empty.depart ~= nil and empty.depart.state == "waiting",
		"server: a session's end before any admit opens nothing and closes nothing"
	)
	-- A first admit with no hint is still the server's one opening.
	local none = L4W3R.book()
	Flow.DepartAdmit(none, "", "", false, nil, 0)
	Flow.DepartAdmit(none, "forestRoad", "normal", true, nil, 5)
	check(
		none.departOpened and none.depart == nil,
		"server: a first admit with no hint opens nothing, and nothing opens after it"
	)
end)

-- The tick's early return (the review's s3) -------------------------------------------------------------

L4W3R.group("live", function()
	local Flow = L4W3R.Flow
	check(Flow.DepartLive(nil) == false, "live: none has nothing to do")
	local depart = L4W3R.waiting(0)
	check(Flow.DepartLive(depart) == true, "live: waiting moves")
	depart.state = "counting"
	check(Flow.DepartLive(depart) == true, "live: counting moves")
	depart.state = "picked"
	check(Flow.DepartLive(depart) == false, "live: picked never moves (its view is on the wire)")
	depart.state = "done"
	check(Flow.DepartLive(depart) == false, "live: done never moves")
	-- The tick of the change still sees it: a wait that runs out turns picked inside DepartStep.
	local capped = L4W3R.waiting(0)
	check(Flow.DepartLive(capped), "live: a wait is live up to its cap")
	Flow.DepartStep(capped, L4W3R.input(30, { bodies = false }))
	check(
		capped.state == "picked" and not Flow.DepartLive(capped),
		"live: and the cap's own tick turns it picked, after which the tick returns at once"
	)
end)

-- The start at zero's late arrivals (the fix round's F2) ------------------------------------------------

L4W3R.group("late", function()
	local Flow = L4W3R.Flow
	local late = Flow.DepartLate({
		{ userId = 1, expected = true, body = true },
		{ userId = 2, expected = false, body = false },
		{ userId = 3, expected = false, body = true },
	})
	check(
		late[2] == true and late[1] == nil and late[3] == nil,
		"late: a run-list arrival still spawning at zero is late; who stands is not"
	)
	check(
		next(Flow.DepartLate({
			{ userId = 1, expected = true, body = false },
			{ userId = 2, expected = false, body = true },
		})) == nil,
		"late: an expected member is never late (they held the countdown; the start's body rule answers)"
	)
	check(
		next(Flow.DepartLate({ { userId = 4, expected = false, body = false } })) == nil,
		"late: when that would be every member, nobody is (a level started for nobody)"
	)
	check(next(Flow.DepartLate({})) == nil, "late: nobody present, nobody late")

	-- The start at zero through startLevel's lines: a party of two departed; a stranger from the run
	-- list was admitted during the countdown and their character has not spawned yet.
	local members = {
		{ userId = 1, body = true, waiting = false },
		{ userId = 2, body = true, waiting = false },
		{ userId = 9, body = false, waiting = false },
	}
	local set = Flow.DepartLate({
		{ userId = 1, expected = true, body = true },
		{ userId = 2, expected = true, body = true },
		{ userId = 9, expected = false, body = false },
	})
	local goes, placed = L4W3R.starting(members, set)
	check(
		goes and #placed == 2 and placed[1] == 1 and placed[2] == 2,
		"late: the auto-start goes ahead for the departed party (F2: never refused for the stranger)"
	)
	check(
		members[3].waiting == true and members[1].waiting == false,
		"late: and the stranger waits in the lobby camp, entering when their body stands"
	)
	local own = {
		{ userId = 1, body = true, waiting = false },
		{ userId = 9, body = false, waiting = false },
	}
	check(
		L4W3R.starting(own, nil) == false,
		"late: the leader's own start still needs every body (nobody is late without the auto-start)"
	)
	local expectedMissing = {
		{ userId = 1, body = true, waiting = false },
		{ userId = 2, body = false, waiting = false },
	}
	local stillExpected = Flow.DepartLate({
		{ userId = 1, expected = true, body = true },
		{ userId = 2, expected = true, body = false },
	})
	check(
		L4W3R.starting(expectedMissing, stillExpected) == false,
		"late: an expected member without a body still refuses the start at zero (busy, picked)"
	)
end)

-- The cards' lines -------------------------------------------------------------------------------------------

L4W3R.group("keys", function()
	local C = L4W3R.Credit
	local boss = C.KillKey(true, "chief", "The Camp Chief")
	check(
		boss.kind == "boss" and boss.id == "chief" and boss.name == "The Camp Chief",
		"keys: the run's boss by its kind, named by the run"
	)
	local unnamed = C.KillKey(true, "chief", nil)
	check(
		unnamed.kind == "boss" and unnamed.name == "chief",
		"keys: a boss without a name reads its kind"
	)
	local raider = C.KillKey(false, "brute", "The Camp Chief")
	check(
		raider.kind == "raiders" and raider.id == "raiders" and raider.name == "",
		"keys: every other body is the one raiders line, its words the client's"
	)
	local camp = C.CampKey("pickets", "The Pickets")
	check(
		camp.kind == "camp" and camp.id == "pickets" and camp.name == "The Pickets",
		"keys: a camp's clear by its id and name"
	)
	local first = C.FirstClearKey("forestRoad", "hard")
	check(
		first.kind == "firstClear" and first.id == "forestRoad:hard" and first.name == "",
		"keys: a first clear by level and difficulty"
	)
	check(
		#C.FirstClearKey(string.rep("l", 32), string.rep("d", 12)).id <= L4W3R.Lines.MAX_TEXT,
		"keys: the longest first-clear id fits RunLines' text cap"
	)
	local chest = C.ChestKey("lookout", "Lookout Chest")
	check(
		chest.kind == "chest" and chest.id == "lookout" and chest.name == "Lookout Chest",
		"keys: a chest by its id and name"
	)
	local keys = FIXTURES.expeditions.keys
	local castle = C.KeyKey("castle", keys)
	check(
		castle.kind == "key" and castle.id == "castle" and castle.name == keys.castle.name,
		"keys: a key named by the shipped Expeditions.json keys"
	)
	check(C.KeyKey("castle", nil).name == "castle", "keys: a key with no keys block reads its id")
	check(
		C.KeyKey("castle", { castle = { name = "", text = "" } }).name == "castle",
		"keys: an empty name reads its id"
	)
	check(C.KeyKey("vault", keys).name == "vault", "keys: an unknown key reads its id")
	local mentor = C.MentorKey()
	check(
		mentor.kind == "mentor" and mentor.id == "mentor" and mentor.name == "",
		"keys: the mentor line"
	)
	check(
		C.KillKey(false, "a", nil) ~= C.KillKey(false, "a", nil),
		"keys: every key is a fresh table"
	)
end)

L4W3R.group("empty", function()
	local C = L4W3R.Credit
	local card = C.Empty("Forest Road")
	check(
		card.title == "Forest Road"
			and card.cash == 0
			and card.valor == 0
			and card.kills == 0
			and card.seconds == 0
			and card.mentorValor == 0
			and card.damageShare == 0
			and card.wavesCleared == 0
			and card.bestWave == 0
			and card.died == false
			and next(card.materials) == nil
			and #card.lines == 0,
		"empty: a card under its title, every number 0, no lines"
	)
	check(C.Empty("a").lines ~= C.Empty("a").lines, "empty: every card has lines of its own")
	check(
		card.missionId == nil and card.overdrive == nil,
		"empty: no mission id, no Overdrive (L4W3-3)"
	)
end)

L4W3R.group("credit", function()
	local C = L4W3R.Credit
	local card = C.Empty("Forest Road")
	C.Credit(card, C.KillKey(false, "fodder", nil), 30, "Timber", 2, 0, 1)
	C.Credit(card, C.KillKey(false, "brute", nil), 45, "Timber", 3, 0, 0)
	check(
		card.cash == 75 and card.materials.Timber == 5 and card.kills == 1,
		"credit: the totals as before (kills only for the killer)"
	)
	local raiders = L4W3R.line(card.lines, "raiders", "raiders")
	check(
		#card.lines == 1
			and raiders ~= nil
			and raiders.count == 1
			and raiders.cash == 75
			and raiders.materials == 5
			and raiders.material == "Timber",
		"credit: every body on one raiders line, its count one per kill (F3: a share adds its pay only)"
	)
	C.Credit(card, C.CampKey("pickets", "The Pickets"), 120, "Timber", 8, 0, 0)
	C.Credit(card, C.KillKey(false, "fodder", nil), 30, "Timber", 2, 0, 1)
	check(
		L4W3R.kinds(card.lines) == "raiders,camp",
		"credit: lines in the order of their first credit"
	)
	check(
		L4W3R.line(card.lines, "raiders", "raiders").count == 2,
		"credit: a later raider merges into the first line"
	)
	C.Credit(card, C.ChestKey("lookout", "Lookout Chest"), 0, "Timber", 20, 6, 0)
	C.Credit(card, C.KeyKey("castle", nil), 0, "", 0, 0, 0)
	local key = L4W3R.line(card.lines, "key", "castle")
	check(
		key ~= nil and key.count == 1 and key.cash == 0 and key.materials == 0 and key.valor == 0,
		"credit: a key's line pays nothing"
	)
	check(
		card.valor == 6 and card.materials.Timber == 35,
		"credit: the chest's Valor and Timber are in the totals"
	)
	C.Credit(card, C.CampKey("x", "X"), 0, "", 9, 0, 0)
	check(card.materials[""] == nil, "credit: materials with no material go nowhere on the totals")
	C.Mentor(card, 10)
	local mentor = L4W3R.line(card.lines, "mentor", "mentor")
	check(
		card.valor == 16
			and card.mentorValor == 10
			and mentor ~= nil
			and mentor.valor == 10
			and mentor.count == 1,
		"credit: the mentor bonus in valor, mentorValor and its own line"
	)
	-- The totals stay the truth past the wire's cap.
	local full = C.Empty("Expeditions")
	for index = 1, L4W3R.Lines.MAX + 3 do
		C.Credit(full, C.ChestKey(`c{index}`, `Chest {index}`), 0, "Timber", 1, 1, 0)
	end
	check(
		#full.lines == L4W3R.Lines.MAX
			and full.valor == L4W3R.Lines.MAX + 3
			and full.materials.Timber == L4W3R.Lines.MAX + 3,
		"credit: past RunLines.MAX lines the totals still count"
	)
end)

-- Both cards, every credit site of a first Hard clear, in the order a run makes them.
L4W3R.group("sites", function()
	local C = L4W3R.Credit
	local cards = { C.Empty("Forest Road"), C.Empty("Expeditions") }
	for _ = 1, 40 do
		L4W3R.cardsCredit(cards, C.KillKey(false, "fodder", nil), 12, "Timber", 1, 0, 1)
	end
	L4W3R.cardsCredit(cards, C.CampKey("pickets", "The Pickets"), 90, "Timber", 6, 0, 0)
	L4W3R.cardsCredit(cards, C.ChestKey("lookout", "Lookout Chest"), 0, "Timber", 20, 6, 0)
	L4W3R.cardsCredit(cards, C.KeyKey("castle", FIXTURES.expeditions.keys), 0, "", 0, 0, 0)
	L4W3R.cardsCredit(cards, C.CampKey("mainCamp", "Main Camp"), 150, "Timber", 9, 0, 0)
	L4W3R.cardsCredit(cards, C.KillKey(true, "chief", "The Camp Chief"), 600, "Timber", 30, 25, 1)
	L4W3R.cardsMentor(cards, 5)
	L4W3R.cardsCredit(cards, C.FirstClearKey("forestRoad", "hard"), 0, "", 0, 40, 0)
	for which, card in cards do
		check(
			L4W3R.kinds(card.lines) == "raiders,camp,chest,key,camp,boss,mentor,firstClear",
			`sites: card {which} holds one line per source, in the run's order`
		)
		local cash, materials, valor = 0, 0, 0
		for _, line in card.lines do
			cash += line.cash
			materials += line.materials
			valor += line.valor
		end
		check(
			cash == card.cash and materials == card.materials.Timber and valor == card.valor,
			`sites: card {which}'s lines add up to its totals`
		)
		check(
			card.kills == 41 and L4W3R.line(card.lines, "raiders", "raiders").count == 40,
			`sites: card {which} counts 40 raiders and 41 kills`
		)
	end
end)

-- A kill's line counts kills (the fix round's F3) --------------------------------------------------------------

L4W3R.group("kills", function()
	local C = L4W3R.Credit
	-- A party of two splits a camp: A lands 25 killing blows, B 35, and each shares every body.
	local a, b = C.Empty("Forest Road"), C.Empty("Forest Road")
	for _ = 1, 25 do
		C.Credit(a, C.KillKey(false, "fodder", nil), 6, "Timber", 1, 0, 1)
		C.Credit(b, C.KillKey(false, "fodder", nil), 6, "Timber", 1, 0, 0)
	end
	for _ = 1, 35 do
		C.Credit(a, C.KillKey(false, "brute", nil), 6, "Timber", 1, 0, 0)
		C.Credit(b, C.KillKey(false, "brute", nil), 6, "Timber", 1, 0, 1)
	end
	local lineA = L4W3R.line(a.lines, "raiders", "raiders")
	local lineB = L4W3R.line(b.lines, "raiders", "raiders")
	check(
		lineA.count == 25 and a.kills == 25 and lineB.count == 35 and b.kills == 35,
		"kills: in a party Raiders xn is the card's own kills, as its kill count says (F3)"
	)
	check(
		lineA.cash == 360 and lineA.materials == 60,
		"kills: a share without the killing blow still adds its pay to the line"
	)
	-- The boss: the killer's line counts 1, a share counts 0.
	C.Credit(a, C.KillKey(true, "chief", "The Camp Chief"), 600, "Timber", 30, 25, 0)
	C.Credit(b, C.KillKey(true, "chief", "The Camp Chief"), 600, "Timber", 30, 25, 1)
	check(
		L4W3R.line(a.lines, "boss", "chief").count == 0
			and L4W3R.line(b.lines, "boss", "chief").count == 1
			and L4W3R.line(a.lines, "boss", "chief").valor == 25,
		"kills: the boss line counts the killing blow; a share is paid on it, uncounted"
	)
	-- WaveService.credit's killer without a share: the kill alone, counted.
	local blow = C.Empty("Forest Road")
	C.Credit(blow, C.KillKey(false, "fodder", nil), 0, "Timber", 0, 0, 1)
	check(
		L4W3R.line(blow.lines, "raiders", "raiders").count == 1 and blow.kills == 1,
		"kills: a killing blow with no share counts on the line and the total"
	)
	-- Every other kind counts one per event, whatever `kills` says.
	local events = C.Empty("Forest Road")
	C.Credit(events, C.CampKey("pickets", "The Pickets"), 90, "Timber", 6, 0, 0)
	C.Credit(events, C.CampKey("pickets", "The Pickets"), 90, "Timber", 6, 0, 1)
	C.Credit(events, C.ChestKey("lookout", "Lookout Chest"), 0, "Timber", 20, 6, 0)
	C.Credit(events, C.KeyKey("castle", nil), 0, "", 0, 0, 0)
	C.Credit(events, C.FirstClearKey("forestRoad", "hard"), 0, "", 0, 40, 0)
	C.Mentor(events, 5)
	check(
		L4W3R.line(events.lines, "camp", "pickets").count == 2
			and L4W3R.line(events.lines, "chest", "lookout").count == 1
			and L4W3R.line(events.lines, "key", "castle").count == 1
			and L4W3R.line(events.lines, "firstClear", "forestRoad:hard").count == 1
			and L4W3R.line(events.lines, "mentor", "mentor").count == 1,
		"kills: camp, chest, key, first clear and mentor lines count one per credit"
	)
end)

-- The pay era -----------------------------------------------------------------------------------------------

L4W3R.group("era", function()
	local C = L4W3R.Credit
	check(C.EraOf(nil) == 1, "era: no profile pays as the first era")
	check(C.EraOf({ era = 3 }) == 3, "era: the profile's era at the admit")
	for _, bad in { 0, -1, 2.5, L4W3R.NAN, math.huge, "3", false } do
		check(C.EraOf({ era = bad }) == 1, `era: {tostring(bad)} pays as the first era`)
	end
	check(C.PayEra(2, nil) == 2, "pay era: the era frozen at the admit")
	check(C.PayEra(2, 4) == 4, "pay era: the P lever's session override wins")
	check(
		C.NextPayEra(1, 4) == 2 and C.NextPayEra(2, 4) == 3 and C.NextPayEra(3, 4) == 4,
		"P: 1 -> 2 -> 3 -> 4"
	)
	check(C.NextPayEra(4, 4) == 1, "P: the last era wraps to the first")
	check(C.NextPayEra(9, 4) == 1, "P: an era past the list wraps to the first")
	check(C.NextPayEra(L4W3R.NAN, 4) == 2, "P: a bad current era steps from the first")
	check(C.NextPayEra(2, 0) == 1, "P: with no eras known, the first")
end)

-- P never pays into a real save (the fix round's F4) ----------------------------------------------------------

L4W3R.group("payLever", function()
	local C = L4W3R.Credit
	check(
		C.PayLeverRefusal(true, true) == nil,
		"P: on the mock store with a member admitted it steps"
	)
	check(
		C.PayLeverRefusal(false, true) == "realStore",
		"P: refused on the real store (Studio with API access on): it would pay into a real save (F4)"
	)
	check(
		C.PayLeverRefusal(false, false) == "realStore",
		"P: the real store refuses before anything else"
	)
	check(
		C.PayLeverRefusal(true, false) == "nobody",
		"P: with nobody admitted the store may not have answered yet: nothing steps"
	)
end)

L4W3R.group("frozen", function()
	local C = L4W3R.Credit
	local rewards = FIXTURES.combat.rewards
	check(
		rewards ~= nil and type(rewards.eraCashMult) == "table",
		"frozen: the shipped Combat.json has rewards.eraCashMult"
	)
	local state = { era = 3, legacy = 0 }
	local member = { cashEra = C.EraOf(state) }
	local members = { [7] = member }
	local states = { [7] = state }
	local at = L4W3R.credit(members, states, nil, rewards)
	check(
		at[7] == rewards.eraCashMult[3],
		"frozen: a member is paid at the era of their admit (x Legacy 1, Founder's 1)"
	)
	state.era = 4
	check(
		L4W3R.credit(members, states, nil, rewards)[7] == rewards.eraCashMult[3],
		"frozen: a later change of the profile's era moves nothing"
	)
	check(
		L4W3R.credit(members, states, 2, rewards)[7] == rewards.eraCashMult[2],
		"frozen: the P lever's override pays every member at its era"
	)
	local mixed = L4W3R.credit(
		{ [1] = { cashEra = 1 }, [2] = { cashEra = 4 } },
		{ [1] = { era = 1, legacy = 0 }, [2] = { era = 4, legacy = 10 } },
		nil,
		rewards
	)
	check(mixed[1] == rewards.eraCashMult[1], "frozen: a party mixes eras: a Village member at x1")
	check(
		near(mixed[2], 2 * rewards.eraCashMult[4], 1e-6),
		"frozen: an Orbital member at its era, Legacy on top (x2 at legacy 10)"
	)
	check(
		L4W3R.credit(members, states, nil, nil)[7] == 1,
		"frozen: no rewards block pays x1 everywhere (degrade)"
	)
	check(
		next(L4W3R.credit({ [9] = { cashEra = 2 } }, {}, nil, rewards)) == nil,
		"frozen: a member without a profile is paid nothing"
	)
end)

-- The run's last wallet ---------------------------------------------------------------------------------------

L4W3R.group("wallet", function()
	local log: { string } = {}
	local members = {
		{ userId = 1, player = 1, given = { valor = 25 } },
		{ userId = 2, player = 2, given = nil },
		{ userId = 3, player = 3, given = nil },
	}
	L4W3R.endTail(members, { [2] = true }, log)
	local card = table.find(log, "card")
	local credit1 = table.find(log, "credit 1")
	local snapshot1 = table.find(log, "snapshot 1")
	local snapshot2 = table.find(log, "snapshot 2")
	check(card == #log, "wallet: the card goes last")
	check(
		credit1 ~= nil and snapshot1 ~= nil and credit1 < snapshot1,
		"wallet: a first clear's member gets their wallet after its Valor's credit"
	)
	check(snapshot1 ~= nil and snapshot1 < card, "wallet: and before the card")
	check(
		snapshot2 ~= nil and snapshot2 < card,
		"wallet: a wallet the run left unsent goes before the card too"
	)
	check(
		table.find(log, "snapshot 3") == nil,
		"wallet: a wallet already sent is not sent again (its last one is current)"
	)
	local count = 0
	for _, entry in log do
		if entry == "card" then
			count += 1
		end
	end
	check(count == 1, "wallet: one card")
end)

-- A difficulty's note (Validate, §7) ---------------------------------------------------------------------------

L4W3R.group("note", function()
	local Flow = L4W3R.Flow
	-- Validate's lines that name a note, and StageFlow.Notes' kept notes and dropped lines, for a
	-- copy of Forest Road whose Hard carries `note`.
	local function read(note: any): ({ string }, { [string]: string }, { string })
		local level = L1.level()
		level.difficulties.hard.note = note
		local found = {}
		local ok, problems =
			pcall(Flow.Validate, level, L1.layout(), L1.kinds, L1.ranks, L1.rules, L1.crowdMax)
		if not ok then
			return { "Validate threw: " .. tostring(problems) }, {}, {}
		end
		for _, line in problems do
			if string.find(line, ".note", 1, true) ~= nil then
				table.insert(found, line)
			end
		end
		local kept, dropped = Flow.Notes(level)
		return found, kept, dropped
	end
	for _, good in { "Castle gear", string.rep("x", 24) } do
		local found, kept, dropped = read(good)
		check(
			#found == 0 and kept.hard == good and #dropped == 0,
			`note: {#good} bytes is kept, nothing warned`
		)
	end
	local _, keptNone, droppedNone = read(nil)
	check(keptNone.hard == nil and #droppedNone == 0, "note: none is fine, and nothing is kept")
	for _, bad in { string.rep("x", 25), "", 7, true, {} } do
		local found, kept, dropped = read(bad)
		local label = `{type(bad)} "{if type(bad) == "string" then bad else ""}"`
		check(#found == 0, `note: {label} never refuses the level (F6: Validate names no note)`)
		check(
			kept.hard == nil
				and #dropped == 1
				and string.find(dropped[1], "difficulties.hard.note", 1, true) ~= nil
				and string.find(dropped[1], "dropped", 1, true) ~= nil,
			`note: {label} is dropped with one warn line naming it (F6)`
		)
	end
	-- Two difficulties: the good note stays beside the dropped one, the lines in name order.
	local level = L1.level()
	level.difficulties.hard.note = string.rep("h", 30)
	level.difficulties.normal.note = "Start here"
	local kept, dropped = Flow.Notes(level)
	check(
		kept.normal == "Start here" and kept.hard == nil and #dropped == 1,
		"note: a good note is kept beside a dropped one"
	)
	local shipped = nil
	for _, file in FIXTURES.levels do
		if file.id == "forestRoad" then
			shipped = file
		end
	end
	check(
		shipped ~= nil and shipped.difficulties.brutal.note == "Castle gear",
		"note: the shipped Forest Road's Brutal says Castle gear"
	)
	if shipped ~= nil then
		local shippedKept, shippedDropped = Flow.Notes(shipped)
		check(
			shippedKept.brutal == "Castle gear" and #shippedDropped == 0,
			"note: and keeps it, warning nothing"
		)
	end
end)

-- The lines the copies above stand for (FIXTURES.source.l4w3b: run_harness.py's L4W3B_LINES and
-- L4W3B_ORDER, read on the code of WaveService and ArenaService, neither of which loads here).
L4W3R.PINS = {
	departClear = { 1, "tickDepart refills the bodies it waits for each tick" },
	departHolderRule = {
		1,
		"the expected members present (everyone with standIn) are the bodies it waits for",
	},
	departHolderAdd = { 1, "and each such member is one of them" },
	departStep = { 1, "StageFlow.DepartStep decides, once a tick" },
	departExpected = { 1, "on every expected member admitted once (ArenaService.ExpectedIn)" },
	departHost = { 1, "the host present (ArenaService.HostIn)" },
	departBodies = { 1, "their bodies (VitalsService.AllHaveBodies)" },
	departWait = { 1, "the wait coop.lobbyWaitSeconds" },
	departCountdown = { 1, "and the countdown levels.departCountdownSeconds" },
	departStart = { 1, "a start answer starts the level" },
	departStartLevel = {
		1,
		"through startLevel, the leader's own start, once, with the late arrivals (F2)",
	},
	departRefused = { 1, "a refusal leaves it picked on the map" },
	departToast = { 1, "with the leader's refusal toast" },
	departBeat = { 1, "and a new beat broadcasts at once" },
	departTicked = { 1, "the lobby's tick runs it" },
	departTickCalls = { 2, "and nothing else calls it" },
	departWrites = {
		0,
		"WaveService writes boot.depart nowhere: StageFlow's DepartAdmit, DepartForget and DepartLever do (F1)",
	},
	departStateWrites = { 0, "WaveService never writes its state (StageFlow's rule alone)" },
	lobbyLeavesDepart = {
		0,
		"the return to the lobby leaves it alone: nothing starts after a run (L4W3-4)",
	},
	openPick = { 1, "it opens on ArenaService.Pick" },
	openStudio = { 1, "the proving path only in Studio" },
	openDepart = { 1, "through StageFlow.DepartAdmit (once a server, F1)" },
	openOnAdmit = { 1, "at an admit" },
	askedEnds = { 1, "the leader's own ask ends it" },
	resetDepart = { 1, "the session's end forgets it (StageFlow.DepartForget)" },
	resetOpened = {
		0,
		"and Reset keeps departOpened: a later session on this server never opens it again (F1)",
	},
	resetCashEra = { 1, "and forgets the P lever's era" },
	fakeStudio = { 1, "R works only in Studio and the lobby" },
	eraStudio = { 1, "P steps only in Studio" },
	creditRewards = { 1, "credit reads Combat.json rewards" },
	creditEra = { 1, "pays each member at RunCredit.PayEra (frozen at the admit, or the lever's)" },
	creditMult = { 1, "through the one cash choke point, Combat.CombatCashMult" },
	creditKey = { 1, "and names the credit's source on the cards" },
	creditKiller = { 1, "a killer without a share is credited under the same source" },
	cashMultCalls = { 1, "the cash multiplier is read in one place" },
	waveEraWrites = {
		2,
		"WaveService writes only the lever's era (NextCashEra, Reset), never a member's",
	},
	killBoss = { 1, "the run's boss is the body whose death pays its Valor" },
	killKey = { 1, "a kill's source is RunCredit.KillKey" },
	killCredit = { 1, "and the kill is credited under it" },
	campKey = { 1, "a camp's clear bonus is under RunCredit.CampKey" },
	campCredit = { 1, "and credited under it" },
	chestKey = { 1, "a chest's pay is under RunCredit.ChestKey" },
	keyKey = { 1, "a key it gave is under RunCredit.KeyKey" },
	keyCredit = { 1, "on a line that pays nothing" },
	creditSummaryCalls = {
		5,
		"every card credit is one of the five sites (kill share, killer, first clear, chest, key)",
	},
	creditCalls = { 2, "credit is called by the kill and the camp clear only" },
	endFirstKey = { 1, "a first clear is under RunCredit.FirstClearKey" },
	endFirstCredit = { 1, "credited on the cards" },
	endFirstDirty = { 1, "and its wallet marked to go out" },
	endWallets = { 1, "every changed wallet goes out at the end" },
	endWalletCalls = { 1, "once" },
	endCard = { 1, "and then the card" },
	walletsAll = { 1, "sendWallets' `all` sends every dirty wallet" },
	walletsSend = { 1, "as a Snapshot" },
	admitEra = { 1, "the admit freezes the member's era (RunCredit.EraOf)" },
	arenaEraWrites = { 1, "and nothing else in ArenaService writes it" },
	cardsLoop = { 1, "CreditSummary writes both cards" },
	cardsCredit = { 1, "through RunCredit.Credit" },
	mentorLoop = { 1, "CreditMentor writes both cards" },
	mentorCredit = { 1, "through RunCredit.Mentor" },
	pickVerified = { 1, "Pick verifies only a ticket with a level" },
	hostIn = { 1, "HostIn is the session's host in the roster" },
	expectedLoop = { 1, "ExpectedIn: every expected id admitted once" },
	partyInExpected = { 1, "PartyIn starts from ExpectedIn" },
	-- The fix round (docs/prompts/l4-w3-fix-round.md): F1-F6, and the conditions slice 2's m2 probed.
	bootOpened = { 1, "only a new server boot starts with departOpened unset (F1)" },
	openedWrites = {
		0,
		"WaveService never writes departOpened (StageFlow.DepartAdmit and DepartLever do, F1)",
	},
	leverBook = { 1, "R opens through StageFlow.DepartLever" },
	openSince = { 1, "the wait counts from the first arrival (ArenaService.FirstArrivalAt)" },
	openSinceGuard = { 1, "and, with none yet," },
	openSinceClock = { 1, "from now" },
	departLive = { 1, "the tick returns at once unless waiting or counting (s3)" },
	departLeader = { 1, "whoever leads at zero starts it (LeaderUserId, not the host)" },
	departNotLeader = { 1, "with no such player the refusal is notLeader" },
	departPlayerGuard = { 1, "and startLevel runs only for a player" },
	departPcall = { 1, "inside a pcall (s2)" },
	departThrown = { 1, "a throw" },
	departThrownRefusal = { 1, "is an unavailable refusal" },
	departRefusedIf = { 1, "only a refusal falls back to picked" },
	departToastGuard = { 1, "and toasts only a player" },
	departBeatLobby = { 1, "a new beat broadcasts in the lobby" },
	departBeatBroadcast = { 1, "at once" },
	lateExpected = { 1, "the late arrivals read the expected list (F2)" },
	lateBody = { 1, "and each member's body" },
	lateRule = { 1, "through StageFlow.DepartLate" },
	lateCalls = { 2, "and only the start at zero asks for them" },
	startOwnNoLate = { 1, "the leader's own start leaves nobody late" },
	startStarting = { 1, "startLevel's bodies are the members" },
	startLateAny = { 1, "unless some are late" },
	startStartingNew = { 1, "then a list of its own" },
	startNotLate = { 1, "of every member not late" },
	startNotLateAdd = { 1, "each added" },
	startBodies = { 1, "and only they need a body to start" },
	startLateWaits = { 1, "a late member is not placed" },
	startLateWaiting = { 1, "and waits in the lobby camp" },
	askedBroadcast = { 1, "a manual ask that ended it broadcasts at once" },
	pushDepart = { 1, "the RunState carries the depart view" },
	endGiven = { 1, "a first clear that gave something is credited" },
	eraRefusal = {
		1,
		"P asks RunCredit.PayLeverRefusal on the mock store and an admitted member (F4)",
	},
	eraRefused = { 1, "a refusal steps nothing" },
	pRealStore = { 1, "the real store's refusal" },
	pRealStoreToast = { 1, "says P needs Studio API access off" },
	pOtherRefusal = { 1, "any other refusal says nothing and steps nothing" },
	pReturns = { 2, "both refusals return before the Pay as notice" },
	noteRead = { 1, "readLevel reads the dropped notes (F6)" },
	noteWarnOnce = { 1, "and warns them once a server" },
	noteRefusal = { 1, "the verdict stays the problems and the difficulty alone" },
	secretRowsShared = { 1, "the secret rows are MapRules.SecretRows (F9)" },
	secretRowsOpened = { 1, "against the receiver's own opened chests" },
	secretRowCopies = { 0, "and WaveService keeps no copy of the row loop" },
	expectedGuard = { 1, "ExpectedIn answers nothing before the session and its ticket" },
	expectedMissing = { 1, "and false for any expected id never admitted" },
	partyInFirst = { 1, "PartyIn's cap needs a first arrival" },
	partyInCap = { 1, "and coop.lobbyWaitSeconds since it" },
	firstArrival = { 1, "FirstArrivalAt is the session's first admit" },
	buildDepart = { 1, "the depart reaches the clients in the lobby only" },
	hintLevelType = { 1, "the hint's level is a string" },
	hintEmpty = { 1, "not empty" },
	hintLevelCap = { 1, "within the level id cap" },
	hintDifficultyType = { 1, "its difficulty a string" },
	hintDifficultyCap = { 1, "within the difficulty cap" },
	ticketLevel = { 1, "a ticket's level is a string" },
	ticketDifficulty = { 1, "and its difficulty" },
	resolveMatch = { 1, "a ticket verifies only its own level and difficulty" },
	resolveServer = { 1, "on its own server" },
	mockLevel = { 1, "the Studio mock ticket names the hint's level" },
	mockDifficulty = { 1, "and difficulty" },
}
L4W3R.ORDER = {
	endCreditThenWallets = "the first clear's credit comes before the wallets",
	endWalletsThenCard = "the wallets come before the card",
	killCreditThenMentor = "the boss's credit comes before the mentor bonus",
	departStepThenStart = "the rule decides before the start",
	departLiveThenStep = "the tick's early return comes before its work (s3)",
	eraRefusalThenStep = "P's refusal is asked before the pay era steps (F4)",
	noteThenVerdict = "the dropped notes are read before the verdict (F6)",
}

L4W3R.group("pins", function()
	local reading = FIXTURES.source.l4w3b
	if reading == nil then
		check(false, "pins: run_harness.py reads no l4w3b lines (luau-b-pins.py is not pasted in)")
		return
	end
	check(
		#reading.missing == 0,
		`pins: every function the lines live in is there ({table.concat(reading.missing, ", ")})`
	)
	local keys = {}
	for key in L4W3R.PINS do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local expected = L4W3R.PINS[key]
		local count = reading.counts[key]
		check(
			count == expected[1],
			`pins: {expected[2]} ({key}: {tostring(count)}, expected {expected[1]})`
		)
	end
	local unknown = {}
	for key in reading.counts do
		if L4W3R.PINS[key] == nil then
			table.insert(unknown, key)
		end
	end
	for key, text in L4W3R.ORDER do
		check(reading.order[key] == true, `pins: {text} ({key})`)
	end
	for key in reading.order do
		if L4W3R.ORDER[key] == nil then
			table.insert(unknown, key)
		end
	end
	table.sort(unknown)
	check(
		#unknown == 0,
		`pins: every line read has an expected count here ({table.concat(unknown, ", ")})`
	)
end)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
