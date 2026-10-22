-- Cases for L4 W1b's RunState floors (docs/prompts/l4-w1b-contract.md §5, L4B-8): a floor's
-- region cells ride on a member's first RunState of each floor set and never again in it; the
-- client keeps the cells it holds while the set is the same and takes what is sent on a new one.
-- The pure RunFloors (luau-engineer A's) is loaded; ArenaService, which calls Attach for each
-- member and notes the set as sent, and WaveService, which numbers each set (floorsSeq), cannot be
-- loaded here: L4R.Server below is their bookkeeping, line for line, and run_harness.py reads
-- their lines as text. Appended by run_harness.py after the earlier case files, so every local of
-- those is in scope (check, load, FIXTURES). Everything hangs off the L4R table (the 200-local
-- limit), and every group runs behind L4R.group, so a group that throws fails one check and the
-- bundle goes on.
-- Fix round 3's H1 (docs/prompts/l4-w1b-fix3.md), last: a clear never erases a blow that waits for a
-- dash claim. WaveService's fieldHeld and its use in advance are copied line for line into L4R.Wave
-- (run_harness.py reads WaveService's lines as text) and run on the real StageFlow and a real
-- VitalsService of this file's own, frame by frame in both orders a Heartbeat may run the two
-- handlers in.

print("L4 W1b: RunState's floors carry their cells once per member per floor set (RunFloors)")

local L4R: any = {
	Floors = load("RunFloors"),
	Flow = load("StageFlow"),
	Geo = load("LevelGeometry"),
	Proof = load("DashProof"),
	Ring = load("PositionRing"),
}

function L4R.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `{name} stopped: {tostring(problem)}`)
	end
end

-- Three floors: two camps of one region (the same cells table on both, as StageFlow.Plan gives
-- it) and a boss room with none.
function L4R.fixture(): { any }
	local cells = {
		{ x = 0, z = 0, hx = 10, hz = 10 },
		{ x = 30, z = 0, hx = 4, hz = 8 },
		{ x = 60, z = 0, hx = 10, hz = 10 },
	}
	return {
		{ x = 0, y = 8, z = 0, hx = 10, hz = 10, cells = cells },
		{ x = 60, y = 8, z = 0, hx = 10, hz = 10, cells = cells },
		{ x = 200, y = 0, z = 0, hx = 20, hz = 20, locks = true, ceiling = 64, fence = 2.5 },
	}
end

-- Whether any floor of `floors` holds a `cells` key at all.
function L4R.anyCells(floors: { any }): boolean
	for _, floor in floors do
		for key in floor do
			if key == "cells" then
				return true
			end
		end
	end
	return false
end

-- The floors' fields other than `cells`, as one string, so two lists can be compared.
function L4R.shape(floors: { any }): string
	local rows = {}
	for _, floor in floors do
		table.insert(
			rows,
			`{floor.x},{floor.y},{floor.z},{floor.hx},{floor.hz},{tostring(floor.locks)},{tostring(
				floor.ceiling
			)},{tostring(floor.fence)}`
		)
	end
	return table.concat(rows, ";")
end

-- Each floor's cells, as one string ("-" for none).
function L4R.cellsOf(floors: { any }): string
	local rows = {}
	for _, floor in floors do
		local cells = floor.cells
		if cells == nil then
			table.insert(rows, "-")
		else
			local parts = {}
			for _, cell in cells do
				table.insert(parts, `{cell.x}/{cell.z}/{cell.hx}/{cell.hz}`)
			end
			table.insert(rows, table.concat(parts, " "))
		end
	end
	return table.concat(rows, ";")
end

-- The server's half, as ArenaService and WaveService keep it: `floors` and `seq` are the run's
-- (WaveService.setFloors raises the number with every set), `sent` is ArenaService's
-- play.cellsSent, cleared at Admit and Remove. `send` is ArenaService.sendRunState: a member
-- not yet noted for the set gets Attach with what it was sent (its floors only if the cells went)
-- and the set noted; a noted member never reaches Attach and gets BuildRunState's floors as they
-- are. `build` is BuildRunState's floors (Attach with the set's own number: never the cells).
-- `attaches` counts the Attach calls `send` made.
L4R.Server = {}

function L4R.Server.new(floors: { any }): any
	return { floors = floors, seq = 1, sent = {}, attaches = 0 }
end

function L4R.Server.setFloors(server: any, floors: { any }): ()
	server.floors = floors
	server.seq += 1
end

function L4R.Server.send(server: any, userId: number): ({ any }, boolean)
	local floors, went = L4R.Server.build(server), false
	if server.sent[userId] ~= server.seq then
		server.attaches += 1
		local attached, cellsWent =
			L4R.Floors.Attach(server.floors, server.seq, server.sent[userId])
		if cellsWent then
			floors, went = attached, true
		end
		server.sent[userId] = server.seq
	end
	return floors, went
end

function L4R.Server.build(server: any): { any }
	local floors = L4R.Floors.Attach(server.floors, server.seq, server.seq)
	return floors
end

-- A client: what it holds (nothing yet: no floors, no seq), merged from each RunState it is sent
-- (CombatUIController.applyFloors).
function L4R.client(): any
	return { floors = {}, seq = nil }
end

function L4R.receive(client: any, floors: { any }, seq: number): ()
	client.floors = L4R.Floors.Merge(client.floors, client.seq, floors, seq)
	client.seq = seq
end

function L4R.attachTests(): ()
	print(" Attach: the cells on a member's first RunState of a floor set, never after (L4B-8)")
	local full = L4R.fixture()
	local wanted = L4R.cellsOf(full)
	local shape = L4R.shape(full)
	local server = L4R.Server.new(full)

	local first, went = L4R.Server.send(server, 1)
	check(went == true, "a member's first send of a floor set says the cells went")
	check(
		L4R.cellsOf(first) == wanted,
		"and it carries every floor's cells, none on the floor without a region"
	)
	check(L4R.shape(first) == shape, "with every other field of every floor as the run has it")

	local second, again = L4R.Server.send(server, 1)
	check(again == false, "the same member's next send of that set says no cells went")
	check(not L4R.anyCells(second), "and none of its floors holds a `cells` key at all")
	check(
		#second == #full and L4R.shape(second) == shape,
		"every floor still there, every other field kept"
	)
	local steady = true
	for _ = 1, 20 do
		local floors, sent = L4R.Server.send(server, 1)
		steady = steady and not sent and not L4R.anyCells(floors)
	end
	check(steady, "nor on any of twenty sends after it")
	check(server.attaches == 1, "and Attach ran for the first of those 22 sends only")

	-- sendRunState skips Attach for a member noted for the set (`play.cellsSent[userId] ~= seq`).
	-- That loses nothing only while Attach's own rule is that same test: checked on the real
	-- module for no note, an older set, this set and a later one.
	local agrees = true
	for index = 0, 3 do
		local noted = if index == 0 then nil else server.seq - 2 + index
		local _, cellsWent = L4R.Floors.Attach(full, server.seq, noted)
		agrees = agrees and cellsWent == (noted ~= server.seq)
	end
	check(
		agrees,
		"Attach sends the cells exactly when the member's note is not the set: sendRunState's skip test"
	)

	local other, otherWent = L4R.Server.send(server, 2)
	check(
		otherWent == true and L4R.cellsOf(other) == wanted,
		"another member's first send of the same set carries them: the note is per member"
	)
	check(
		L4R.cellsOf(full) == wanted,
		"Attach leaves the run's own floors and their cells as they were"
	)

	-- ArenaService.Admit and Remove clear the note: a rejoin, a fresh join, a latecomer.
	server.sent[1] = nil
	local back, backWent = L4R.Server.send(server, 1)
	check(
		backWent == true and L4R.cellsOf(back) == wanted,
		"after the note is cleared (Admit, Remove) the member's next send carries them again"
	)
	local after, afterWent = L4R.Server.send(server, 1)
	check(afterWent == false and not L4R.anyCells(after), "and only that one")

	-- A new set (WaveService.setFloors): every member gets its cells once more.
	local nextSet = L4R.fixture()
	nextSet[1].cells = { { x = 5, z = 5, hx = 1, hz = 1 } }
	nextSet[2].cells = nextSet[1].cells
	L4R.Server.setFloors(server, nextSet)
	local fresh, freshWent = L4R.Server.send(server, 1)
	check(
		freshWent == true and L4R.cellsOf(fresh) == L4R.cellsOf(nextSet),
		"a new floor set: the member's first send carries the new set's cells"
	)
	local fresh2, fresh2Went = L4R.Server.send(server, 2)
	check(
		fresh2Went == true and L4R.cellsOf(fresh2) == L4R.cellsOf(nextSet),
		"so does every other member's"
	)
	local later, laterWent = L4R.Server.send(server, 2)
	check(laterWent == false and not L4R.anyCells(later), "then none again")

	-- BuildRunState's own floors (the one payload, and ReturnService's leave card): no cells, ever.
	check(not L4R.anyCells(L4R.Server.build(server)), "BuildRunState's floors hold no `cells` key")
	server.sent[3] = nil
	check(
		not L4R.anyCells(L4R.Server.build(server)) and server.sent[3] == nil,
		"even for a set nobody has been sent, and building notes nothing"
	)
	check(L4R.shape(L4R.Server.build(server)) == L4R.shape(nextSet), "with every other field kept")

	-- The lobby's empty set.
	L4R.Server.setFloors(server, {})
	local lobby = L4R.Server.send(server, 1)
	check(#lobby == 0, "the lobby's empty set sends an empty list")
end
L4R.group("l4b attachTests", L4R.attachTests)

function L4R.mergeTests(): ()
	print(
		" Merge: the client keeps its cells while the set is the same, takes the sent ones on a new one"
	)
	local Floors = L4R.Floors
	local full = L4R.fixture()
	local wanted = L4R.cellsOf(full)
	local server = L4R.Server.new(full)
	local first = L4R.Server.send(server, 1)
	local steady = L4R.Server.send(server, 1)

	local held = Floors.Merge({}, nil, first, 1)
	check(L4R.cellsOf(held) == wanted, "a client holding nothing takes a first send's cells")
	local kept = Floors.Merge(held, 1, steady, 1)
	check(
		L4R.cellsOf(kept) == wanted and L4R.shape(kept) == L4R.shape(full),
		"the same set without cells: each floor keeps the cells it held"
	)
	local bare = Floors.Merge({}, nil, steady, 1)
	check(
		L4R.cellsOf(bare) == "-;-;-",
		"a client that holds nothing and is sent none has none (the rectangle alone)"
	)
	local resent = L4R.fixture()
	resent[1].cells = { { x = 1, z = 2, hx = 3, hz = 4 } }
	local taken = Floors.Merge(kept, 1, resent, 1)
	check(
		L4R.cellsOf(taken) == `1/2/3/4;{L4R.cellsOf({ full[2] })};-`,
		"cells that arrive are taken even on the same set; a floor sent without keeps its own"
	)

	local nextSet = L4R.fixture()
	nextSet[1].cells = { { x = 5, z = 5, hx = 1, hz = 1 } }
	nextSet[2].cells = nextSet[1].cells
	L4R.Server.setFloors(server, nextSet)
	local nextFirst = L4R.Server.send(server, 1)
	local replaced = Floors.Merge(kept, 1, nextFirst, 2)
	check(
		L4R.cellsOf(replaced) == L4R.cellsOf(nextSet),
		"a new set with cells: they replace the held ones"
	)
	local dropped = Floors.Merge(kept, 1, L4R.Server.build(server), 2)
	check(
		L4R.cellsOf(dropped) == "-;-;-",
		"a new set sent without cells: nothing held is kept (the rectangle alone, as before L4)"
	)
	local empty = Floors.Merge(kept, 1, {}, 3)
	check(#empty == 0, "the lobby's empty set: an empty list")
end
L4R.group("l4b mergeTests", L4R.mergeTests)

-- One session, as the server sends it and one client merges it: after every RunState the client's
-- floors must be the run's, cells and all.
function L4R.sessionTests(): ()
	print(" A session: whatever the order of sends, the client's floors are the run's")
	local server = L4R.Server.new({})
	local client = L4R.client()
	local function sendTo(userId: number, viaBuild: boolean?): ()
		local floors = if viaBuild
			then L4R.Server.build(server)
			else (L4R.Server.send(server, userId))
		L4R.receive(client, floors, server.seq)
	end
	local function same(label: string): ()
		check(
			L4R.cellsOf(client.floors) == L4R.cellsOf(server.floors)
				and L4R.shape(client.floors) == L4R.shape(server.floors),
			`{label}: the client holds the run's floors, cells and all`
		)
	end
	sendTo(1)
	same("the lobby, first RunState")
	L4R.Server.setFloors(server, L4R.fixture())
	sendTo(1)
	same("a start")
	for _ = 1, 5 do
		sendTo(1)
	end
	same("five steady sends")
	-- ReturnService's leave card: BuildRunState, same set, no cells.
	sendTo(1, true)
	same("the leave card")
	-- A failed trip home: Remove, then Admit, both clear the note.
	server.sent[1] = nil
	sendTo(1)
	same("the rejoin's first RunState")
	sendTo(1)
	same("and the one after it")
	L4R.Server.setFloors(server, {})
	sendTo(1)
	same("back in the lobby")
	local second = L4R.fixture()
	second[3].cells = { { x = 200, z = 0, hx = 20, hz = 20 } }
	L4R.Server.setFloors(server, second)
	sendTo(1)
	sendTo(1)
	same("a second start, a set whose boss room has cells too")
end
L4R.group("l4b sessionTests", L4R.sessionTests)

-- The shipped Forest Road planned on Normal as WaveService.startLevel plans it; nil after a failed
-- check that says why.
function L4R.forestPlan(): any?
	local file = nil
	for _, candidate in FIXTURES.levels do
		if candidate.id == "forestRoad" then
			file = candidate
		end
	end
	if file == nil then
		check(false, "Forest Road's level file is there (the cases below need it)")
		return nil
	end
	local rules = FIXTURES.combat.levels
	local layout = FIXTURES.layouts[file.layout]
	local level = L4R.Flow.Resolve(file, FIXTURES.combat.director.runCapSeconds)
	local ranks = {}
	for index, name in FIXTURES.expeditions.difficulties do
		ranks[name] = index
	end
	local bounds = L4R.Geo.Bounds(layout, rules.floorThickness)
	local plan, why =
		L4R.Flow.Plan(level, layout, "normal", rules, bounds, ranks, FIXTURES.proving.crowd.kinds)
	if plan == nil then
		check(false, `Forest Road plans on Normal ({tostring(why)})`)
	end
	return plan
end

-- The shipped Forest Road, its floors built as WaveService.startLevel builds them.
function L4R.shippedTests(): ()
	print(" The shipped Forest Road: its region floors' cells go once")
	local plan = L4R.forestPlan()
	if plan == nil then
		return
	end
	local floors = {}
	local regions = 0
	for _, zone in plan.zones do
		local rect = zone.rect
		local region = zone.region
		if region ~= nil then
			regions += 1
		end
		table.insert(floors, {
			x = rect.x,
			y = zone.floorY,
			z = rect.z,
			hx = rect.hx,
			hz = rect.hz,
			cells = if region ~= nil then region.cells else nil,
			locks = zone.locks,
			ceiling = zone.ceiling,
			fence = zone.fence,
		})
	end
	check(
		regions >= 2,
		`at least two floors share a region ({regions} do): the cells are worth sending once`
	)
	local server = L4R.Server.new(floors)
	local first, went = L4R.Server.send(server, 1)
	check(
		went == true and L4R.cellsOf(first) == L4R.cellsOf(floors),
		"the first send carries every region floor's cells"
	)
	local steady, again = L4R.Server.send(server, 1)
	check(again == false and not L4R.anyCells(steady), "a steady send's floors hold no `cells` key")
	local client = L4R.client()
	L4R.receive(client, first, server.seq)
	L4R.receive(client, steady, server.seq)
	check(
		L4R.cellsOf(client.floors) == L4R.cellsOf(floors)
			and L4R.shape(client.floors) == L4R.shape(floors),
		"and the client, merging both, holds the run's floors with their cells"
	)
end
L4R.group("l4b shippedTests", L4R.shippedTests)

-- H1 (docs/prompts/l4-w1b-fix3.md): the clear waits for a held blow ----------------------------------
-- Forest Road's boss room in its last wave: the Colossus (crowd id BOSS) slams the fighter (impact
-- at 0, decided at 0.1 at ping 0.05, 100 health) and dies to his next swing at `killAt`. The clear
-- empties every queue (VitalsService.ClearThreats), so a slam still waiting for his dash claim was
-- erased by it (the second fix-diff review's m3). Every body stands at x 10000, off the map and
-- outside every camp; the slam reaches 100 studs, so a partner at +500 is never in it.
L4R.ID = 61
L4R.BOSS = 9001
L4R.X = 10000
L4R.HZ = 60
L4R.rule = L4R.Proof.Rule(FIXTURES.proving.movement, FIXTURES.proving.shooting)
L4R.move = FIXTURES.proving.movement

-- A fighter at `x`: their body and player, the claimant and ring WeaponService keeps for them, and
-- the member ArenaService keeps.
function L4R.body(userId: number, x: number): any
	local who: any = {}
	who.root = {
		Position = vec(x, 3, 0),
		Size = vec(2, 2, 1),
		IsA = function(_self, class)
			return class == "BasePart"
		end,
	}
	who.humanoid = { Health = 100, MaxHealth = 100, HipHeight = 2 }
	who.character = {
		Parent = {},
		FindFirstChild = function(_self, name)
			return if name == "HumanoidRootPart" then who.root else nil
		end,
		FindFirstChildOfClass = function(_self, class)
			return if class == "Humanoid" then who.humanoid else nil
		end,
		GetChildren = function()
			return {}
		end,
		ChildAdded = {
			Connect = function(_self, _fn)
				return { Disconnect = function() end }
			end,
		},
	}
	who.player = {
		UserId = userId,
		Character = who.character,
		Parent = {},
		GetNetworkPing = function()
			return 0.05
		end,
	}
	who.claim = {
		dashClaimAt = nil,
		iframesFrom = 0,
		iframesUntil = 0,
		iframesWasFrom = 0,
		iframesWasUntil = 0,
	}
	who.history = L4R.Ring.New(120)
	who.member = {
		player = who.player,
		userId = userId,
		waiting = false,
		character = who.character,
		humanoid = who.humanoid,
	}
	return who
end

-- This file's own VitalsService: WeaponService's hooks on each body's claimant (L4R.byPlayer), and
-- the mission WaveService sets, whose onDown is WaveService.OnDown (L4R.Wave.onDown).
function L4R.startVitals(): ()
	L4R.byPlayer = {}
	L4R.vitals = SOURCES.VitalsService(
		gameStub,
		token("script"),
		requireStub,
		V,
		osStub,
		{
			spawn = function(fn, ...)
				fn(...)
			end,
		},
		print,
		{
			new = function()
				return {}
			end,
		},
		{ RaycastFilterType = { Exclude = 1 } }
	)
	L4R.vitals.Start({
		iframeWindow = function(who)
			local body = L4R.byPlayer[who]
			if body == nil then
				return 0, 0, 0, 0
			end
			local w = body.claim
			return w.iframesFrom, w.iframesUntil, w.iframesWasFrom, w.iframesWasUntil
		end,
		grantIframes = function(who, seconds, from)
			local body = L4R.byPlayer[who]
			if body ~= nil and seconds > 0 then
				L4R.Proof.Open(body.claim, math.min(from or fakeNow, fakeNow), seconds)
			end
		end,
		dashClaim = function(who)
			local body = L4R.byPlayer[who]
			if body == nil then
				return 0, 0, 0
			end
			return L4R.Proof.Pending(body.claim.dashClaimAt, L4R.rule, L4R.move.dashIframes)
		end,
	})
	L4R.threat = threatHooks
	L4R.vitals.SetMission({
		mayJudge = function(who)
			local body = L4R.byPlayer[who]
			return body ~= nil and not body.member.waiting
		end,
		onDown = function(_who)
			if L4R.wave ~= nil then
				L4R.Wave.onDown(L4R.wave)
			end
		end,
		maxHpOf = function()
			return nil
		end,
		damageScale = 1,
		regenShare = 0,
	})
end

-- WaveService's side, line for line where H1 decides: `fieldHeld`, and `advance` building StageFlow's
-- input, holding the field and executing what matters here (`clear` empties every queue, `boundary`
-- stands the downed up, `end` is EndRun's clearField). ArenaService.IsFighting and fallenReason as
-- they are. `hold`, `latch` and `cap` false are this file's controls: the lines they switch off
-- each change an outcome below. `hasWaiting` is VitalsService.HasWaiting unless a case replaces it.
L4R.Wave = {}

function L4R.Wave.new(plan: any, flow: any, bodies: { any }): any
	local members = {}
	for _, body in bodies do
		table.insert(members, body.member)
	end
	return {
		plan = plan,
		flow = flow,
		members = members,
		run = { blowWaits = false, heldSince = 0 },
		alive = 1,
		awake = 0,
		live = true,
		log = {},
		from = fakeNow,
		hold = true,
		latch = true,
		cap = true,
		hasWaiting = function(who)
			return L4R.vitals.HasWaiting(who)
		end,
	}
end

function L4R.Wave.isFighting(member: any): boolean
	local humanoid = member.humanoid
	local character = member.character
	return not member.waiting
		and humanoid ~= nil
		and character ~= nil
		and character.Parent ~= nil
		and humanoid.Health > 0
end

function L4R.Wave.fieldHeld(w: any, input: any, now: number, delta: number?): boolean
	local waits = false
	for _, member in w.members do
		if L4R.Wave.isFighting(member) and w.hasWaiting(member.player) then
			waits = true
			break
		end
	end
	if delta == nil then
		return (waits or (w.latch and w.run.blowWaits))
			and L4R.Flow.FieldClear(w.plan, w.flow, input)
	end
	w.run.blowWaits = waits
	if not waits or not L4R.Flow.FieldClear(w.plan, w.flow, input) then
		w.run.heldSince = 0
		return false
	end
	if w.run.heldSince == 0 then
		w.run.heldSince = now
	end
	-- WaveService reads DashProof.Rule(Tuning.Get().movement, Tuning.Get().shooting): the shipped one.
	local rule = L4R.rule
	local lapse = if rule ~= nil then rule.lapse else 0
	return not w.cap or now - w.run.heldSince <= lapse + delta
end

function L4R.Wave.advance(w: any, delta: number?): ()
	if not w.live then
		return
	end
	local now = fakeNow
	local roots, standing, fighters = {}, {}, {}
	for _, member in w.members do
		if not member.waiting then
			table.insert(fighters, member.userId)
		end
		if L4R.Wave.isFighting(member) then
			table.insert(roots, member.character:FindFirstChild("HumanoidRootPart").Position)
			table.insert(standing, not L4R.vitals.IsDown(member.player))
		end
	end
	local lost, fallenIds = L4R.vitals.RunLost(w.members, false)
	local fallen: string? = nil
	if lost then
		fallen = "wipe"
		for _, member in w.members do
			if table.find(fallenIds, member.userId) ~= nil and L4R.vitals.IsDown(member.player) then
				fallen = "down"
			end
		end
	end
	local input = {
		now = now,
		roots = roots,
		standing = standing,
		fighters = fighters,
		spawningDone = true,
		alive = w.alive,
		awake = w.awake,
		aliveByFloor = {},
		mergeOk = false,
		breatherSeconds = 6,
		fallen = fallen,
		runCap = false,
	}
	if w.hold and L4R.Wave.fieldHeld(w, input, now, delta) then
		input.spawningDone = false
	end
	local actions = L4R.Flow.Advance(w.plan, w.flow, input, FIXTURES.combat.levels)
	for _, action in actions do
		table.insert(w.log, { kind = action.kind, at = now - w.from })
		if action.kind == "clear" then
			w.clearAt = w.clearAt or now - w.from
			L4R.vitals.ClearThreats()
		elseif action.kind == "boundary" then
			for _, member in w.members do
				if L4R.vitals.IsDown(member.player) then
					L4R.vitals.StandUp(member.player)
				end
			end
		elseif action.kind == "end" then
			w.ended = action.reason
			w.endedAt = now - w.from
			w.live = false
			L4R.vitals.ClearThreats()
			return
		end
	end
end

-- WaveService.OnDown, inside VitalsService.Step: `waitedAtDown` notes whether any list still held a
-- decision then (the latch is what carries the tick's finding past an emptied list).
function L4R.Wave.onDown(w: any): ()
	w.downAt = w.downAt or fakeNow - w.from
	local waited = false
	for _, member in w.members do
		waited = waited or L4R.vitals.HasWaiting(member.player)
	end
	w.waitedAtDown = waited
	L4R.Wave.advance(w, nil)
end

-- The boss room in its last wave (true when it is the plan's last stage, so its clear ends the run
-- "cleared"); `road` = the road before the first camp instead.
function L4R.Wave.flow(plan: any, road: boolean?): (any, boolean)
	local flow = L4R.Flow.Begin(plan)
	if road then
		return flow, flow.step == "travel" or flow.step == "armed"
	end
	local index = 0
	for at, stage in plan.stages do
		if stage.zone ~= nil and stage.zone.locks then
			index = at
		end
	end
	local stage = plan.stages[index]
	if stage == nil then
		return flow, false
	end
	flow.stage = index
	flow.step = "fight"
	flow.wave = stage.waves
	flow.settled = stage.waves - 1
	return flow, index == #plan.stages
end

-- WeaponService's Heartbeat for every body: the ring sample, a pending claim stepped, then
-- VitalsService.Step. Notes the frame a claim is proven (L4R.provenAt).
function L4R.weaponStep(bodies: { any }): ()
	for _, body in bodies do
		L4R.Ring.Record(body.history, fakeNow, body.root.Position)
		if body.claim.dashClaimAt ~= nil then
			local verdict = L4R.Proof.Step(
				body.claim,
				body.history,
				fakeNow,
				body.root.Position,
				L4R.rule,
				L4R.move.dashIframes
			)
			if verdict == "proven" then
				L4R.provenAt = fakeNow
			end
		end
	end
	L4R.vitals.Step(1 / L4R.HZ)
end

-- One course, in frames of 1/60 s from a fresh fight. `o` holds:
-- * damage: the slam's (200 downs, 8 does not); killAt: the boss's death (nil = never);
-- * claim: nil = no dash, "still" = a claim at 0 the ring never proves (a request-only forger, or
--   a dash into the wall), a number = a claim at 0 whose dash the server's copy starts that late;
-- * order: "wave" = WaveService's tick first in each Heartbeat, "weapon" = WeaponService's first;
-- * partner: a second fighter far off, whom nothing hits; road: the road with one awake group
--   that the kill puts to rest, not the boss room;
-- * hold, latch, cap, hasWaiting: the controls (L4R.Wave.new).
-- Returns the hand copy (its log, clearAt, ended, endedAt, downAt, waitedAtDown), the hero's hurts
-- ({ fx, at }), the health he lost, when the proof came and when the field was first held.
function L4R.holdCourse(o: any): (any, { any }, number, number?, number?)
	fakeNow = math.floor(fakeNow) + 5
	L4R.vitals.ClearThreats()
	table.clear(fired)
	local hero = L4R.body(L4R.ID, L4R.X)
	local bodies = { hero }
	if o.partner then
		table.insert(bodies, L4R.body(L4R.ID + 1, L4R.X + 500))
	end
	table.clear(L4R.byPlayer)
	for _, body in bodies do
		L4R.byPlayer[body.player] = body
		L4R.vitals.AddPlayer(body.player)
		L4R.vitals.PrepareCharacter(body.player, body.character)
	end
	local plan = L4R.plan
	local flow = L4R.Wave.flow(plan, o.road)
	local w = L4R.Wave.new(plan, flow, bodies)
	if o.road then
		w.alive = 0
		w.awake = 1
	end
	for _, key in { "hold", "latch", "cap", "hasWaiting" } do
		if o[key] ~= nil then
			w[key] = o[key]
		end
	end
	L4R.wave = w
	L4R.provenAt = nil
	local from = fakeNow
	if o.claim ~= nil then
		hero.claim.dashClaimAt = from
	end
	local speed = L4R.move.dashDistance / L4R.move.dashSeconds
	local hurts = {}
	local heldFrom: number? = nil
	local killed = false
	for k = 1, math.floor((o.seconds or 1) * L4R.HZ + 0.5) do
		fakeNow = from + k / L4R.HZ
		local since = k / L4R.HZ
		if k == 1 then
			L4R.threat.impact({
				at = from,
				enemyKind = "colossus",
				attack = 1,
				def = { shape = "arc", range = 100, arcDegrees = 360, damage = o.damage },
				targetUserId = L4R.ID,
				origin = vec(L4R.X - 30, 3, 0),
				floorY = 0,
				facing = vec(1, 0, 0),
				bodyId = L4R.BOSS,
			})
		end
		if not killed and o.killAt ~= nil and since >= o.killAt - 1e-9 then
			-- His swing, a remote between two Heartbeats: the body is gone, and with it what it had
			-- in the air (onGone), but not what had already fallen due on him.
			killed = true
			if o.road then
				w.awake = 0
			else
				w.alive = 0
			end
			L4R.threat.gone({ [L4R.BOSS] = true })
		end
		local late = o.claim
		local x = if type(late) == "number"
			then math.min(math.max(since - late, 0) * speed, L4R.move.dashDistance)
			else 0
		hero.root.Position = vec(L4R.X + x, 3, 0)
		if o.order == "wave" then
			L4R.Wave.advance(w, 1 / L4R.HZ)
			L4R.weaponStep(bodies)
		else
			L4R.weaponStep(bodies)
			L4R.Wave.advance(w, 1 / L4R.HZ)
		end
		if heldFrom == nil and w.run.heldSince ~= 0 then
			heldFrom = w.run.heldSince - from
		end
		for _, call in fired do
			if call.player == player and call.name == "CombatFx" then
				for _, fx in call.payload do
					if fx.kind == "hurt" and fx.userId == L4R.ID then
						table.insert(hurts, { fx = fx, at = since })
					end
				end
			end
		end
		table.clear(fired)
	end
	local lost = 100 - hero.humanoid.Health
	for _, body in bodies do
		L4R.vitals.RemovePlayer(body.player)
	end
	L4R.wave = nil
	local proven = if L4R.provenAt ~= nil then L4R.provenAt - from else nil
	return w, hurts, lost, proven, heldFrom
end

-- "landed@0.467 down" etc.: what each hurt said and when.
function L4R.said(hurts: { any }): string
	local parts = {}
	for _, entry in hurts do
		local what = if entry.fx.dodged then "dodged" elseif entry.fx.down then "down" else "landed"
		table.insert(parts, `{what}@{string.format("%.3f", entry.at)}`)
	end
	return if #parts == 0 then "nothing" else table.concat(parts, " ")
end

-- A course time for a label ("-" for none).
function L4R.secs(at: number?): string
	return if at ~= nil then string.format("%.3f", at) else "-"
end

-- The kinds of every action StageFlow gave the course, in order.
function L4R.kinds(w: any): string
	local parts = {}
	for _, entry in w.log do
		table.insert(parts, entry.kind)
	end
	return table.concat(parts, " ")
end

function L4R.holdTests(): ()
	print(" H1: a clear never erases a blow that waits for a dash claim (WaveService.fieldHeld)")
	if type(L4R.vitals.HasWaiting) ~= "function" then
		check(
			false,
			"VitalsService.HasWaiting(player?) is there (H1, luau-engineer A's): the cases below need it"
		)
		return
	end
	local plan = L4R.forestPlan()
	if plan == nil then
		return
	end
	L4R.plan = plan
	local _flow, last = L4R.Wave.flow(plan)
	check(last, "Forest Road's boss room is its last stage: its clear ends the run, cleared")
	local lapse = L4R.rule.lapse
	local frame = 1 / L4R.HZ
	local function atLapse(at: number?): boolean
		return at ~= nil and at > lapse - 1e-9 and at <= lapse + frame + 1e-9
	end

	for _, order in { "wave", "weapon" } do
		local label = if order == "wave" then "the tick first" else "the proofs first"
		-- No dash: the slam downs him at 0.1, before his swing; solo, the run is lost.
		local free, freeHurts = L4R.holdCourse({ damage = 200, killAt = 0.3, order = order })
		check(
			free.ended == "down" and free.clearAt == nil and L4R.said(freeHurts) == "down@0.100",
			`H1 ({label}): with no dash the slam downs him at 0.1 and the run is lost ({L4R.said(
				freeHurts
			)}; ended {tostring(free.ended)}; {L4R.kinds(free)})`
		)
		-- A claim that never proves: the slam waits until the claim lapses (0.45), the boss dies at
		-- 0.3 meanwhile, and the clear waits for the slam. It lands first, downs him, and the run is
		-- lost as with no dash: no clear ever ran.
		local held, heldHurts =
			L4R.holdCourse({ damage = 200, killAt = 0.3, claim = "still", order = order })
		local downed = heldHurts[1]
		check(
			held.ended == "down"
				and held.clearAt == nil
				and #heldHurts == 1
				and downed.fx.down == true
				and atLapse(downed.at)
				and atLapse(held.endedAt),
			`H1 ({label}): a claim that never proves: the boss dies at 0.3, the held slam still lands as the claim lapses and downs him, and the run is lost, no clear ({L4R.said(
				heldHurts
			)}; ended {tostring(held.ended)} at {L4R.secs(held.endedAt)}; {L4R.kinds(held)})`
		)
		check(
			held.waitedAtDown == false,
			`H1 ({label}): when that down is judged his list is already empty, so only the tick's finding (blowWaits) holds the field then ({tostring(
				held.waitedAtDown
			)})`
		)
		-- The m3 failure, with the field never held: the clear at the kill erases the slam and the
		-- solo run is won.
		local bare, bareHurts = L4R.holdCourse({
			damage = 200,
			killAt = 0.3,
			claim = "still",
			order = order,
			hold = false,
		})
		check(
			bare.ended == "cleared"
				and #bareHurts == 0
				and bare.clearAt ~= nil
				and bare.clearAt < 0.3 + 2 * frame,
			`H1 ({label}) control: with the field never held the clear at the kill erases the slam and the run is won ({L4R.said(
				bareHurts
			)}; ended {tostring(bare.ended)}): the case sees m3`
		)
		-- Without the tick's finding the down is judged on a clear field and the run is won.
		local unlatched, unlatchedHurts = L4R.holdCourse({
			damage = 200,
			killAt = 0.3,
			claim = "still",
			order = order,
			latch = false,
		})
		check(
			unlatched.ended == "cleared"
				and #unlatchedHurts == 1
				and unlatchedHurts[1].fx.down == true,
			`H1 ({label}) control: without the tick's finding the down meets a clear field and the run is won ({L4R.said(
				unlatchedHurts
			)}; ended {tostring(unlatched.ended)}): the latch is load-bearing`
		)
		-- An honest dash proven late (its motion seen from 0.3, after the kill at 0.2): the slam
		-- waits, the proof dodges it, and the clear goes through on the proof's frame (the proofs
		-- first) or the next (the tick first). Nothing is lost and the run is cleared.
		local honest, honestHurts, honestLost, proven =
			L4R.holdCourse({ damage = 200, killAt = 0.2, claim = 0.3, order = order })
		local clearWait = if honest.clearAt ~= nil and proven ~= nil
			then honest.clearAt - proven
			else nil
		check(
			honest.ended == "cleared"
				and honestLost == 0
				and #honestHurts == 1
				and honestHurts[1].fx.dodged == true
				and proven ~= nil
				and proven > 0.2
				and clearWait ~= nil
				and clearWait > -1e-9
				and clearWait <= (if order == "wave" then frame else 0) + 1e-9,
			`H1 ({label}): an honest dash proven at {L4R.secs(proven)} after the kill at 0.2: the slam is dodged and the clear goes through {if clearWait
					~= nil
				then string.format("%.3f", clearWait)
				else "never"} s after the proof ({L4R.said(honestHurts)}; ended {tostring(
				honest.ended
			)})`
		)
		-- A slam that does not down him: it lands as the claim lapses and the clear follows at once.
		-- The clear waited at most one lapse and a frame after the claim.
		local light, lightHurts, lightLost =
			L4R.holdCourse({ damage = 8, killAt = 0.3, claim = "still", order = order })
		check(
			light.ended == "cleared"
				and lightLost == 8
				and #lightHurts == 1
				and atLapse(lightHurts[1].at)
				and light.clearAt ~= nil
				and light.clearAt >= lightHurts[1].at - 1e-9
				and light.clearAt <= lapse + 2 * frame + 1e-9,
			`H1 ({label}): a slam that does not down him lands as the claim lapses, then the clear goes through at {L4R.secs(
				light.clearAt
			)} ({L4R.said(lightHurts)}; lost {lightLost})`
		)
		-- Co-op: the held slam downs him while his partner stands, so the run goes on; the clear then
		-- stands him up and the run is cleared, as with no dash.
		local pair, pairHurts = L4R.holdCourse({
			damage = 200,
			killAt = 0.3,
			claim = "still",
			order = order,
			partner = true,
		})
		local pairFree =
			L4R.holdCourse({ damage = 200, killAt = 0.3, order = order, partner = true })
		check(
			pair.ended == "cleared"
				and pairFree.ended == "cleared"
				and #pairHurts == 1
				and pairHurts[1].fx.down == true
				and pair.clearAt ~= nil
				and pair.clearAt >= pairHurts[1].at - 1e-9,
			`H1 ({label}): with a partner standing the held down loses nothing: cleared after it, as with no dash ({L4R.said(
				pairHurts
			)}; ended {tostring(pair.ended)}, no dash {tostring(pairFree.ended)})`
		)
		-- The road: the last awake raider dies at 0.3 while his slam waits. A clear field would spare
		-- the solo down (L1b-19); the slam fell when its striker lived, so the run is lost, as with no
		-- dash.
		local road, roadHurts = L4R.holdCourse({
			damage = 200,
			killAt = 0.3,
			claim = "still",
			order = order,
			road = true,
		})
		local roadFree = L4R.holdCourse({ damage = 200, killAt = 0.3, order = order, road = true })
		local roadBare = L4R.holdCourse({
			damage = 200,
			killAt = 0.3,
			claim = "still",
			order = order,
			road = true,
			hold = false,
		})
		check(
			road.ended == "down"
				and roadFree.ended == "down"
				and roadBare.ended == nil
				and #roadHurts == 1
				and roadHurts[1].fx.down == true,
			`H1 ({label}): on the road too, a held down after the last awake raider fell loses the solo run, as with no dash ({L4R.said(
				roadHurts
			)}; ended {tostring(road.ended)}, no dash {tostring(roadFree.ended)}, never held {tostring(
				roadBare.ended
			)})`
		)
	end

	-- The cap: a list that never empties (HasWaiting stuck) holds the clear field one lapse and a frame
	-- from the first tick that held it, then the clear goes through; without the cap, never.
	local stuck = function()
		return true
	end
	local capped, _ch, _cl, _cp, cappedFrom = L4R.holdCourse({
		damage = 8,
		killAt = 0.3,
		order = "wave",
		hasWaiting = stuck,
		seconds = 1.5,
	})
	local deferral = if capped.clearAt ~= nil and cappedFrom ~= nil
		then capped.clearAt - cappedFrom
		else nil
	check(
		capped.ended == "cleared"
			and deferral ~= nil
			and deferral > lapse - 1e-9
			and deferral <= lapse + 2 * frame + 1e-9,
		`H1: a list that never empties holds the clear field {if deferral ~= nil
			then string.format("%.3f", deferral)
			else "-"} s from the first tick that held it (one lapse, {lapse}, and a frame), then the clear goes through`
	)
	local uncapped = L4R.holdCourse({
		damage = 8,
		killAt = 0.3,
		order = "wave",
		hasWaiting = stuck,
		cap = false,
		seconds = 1.5,
	})
	check(
		uncapped.ended == nil and uncapped.clearAt == nil,
		"H1 control: without the cap that run would never clear"
	)
	-- Nothing waits, the field is clear: the clear goes through on the kill's first tick, never held.
	local plain, plainHurts, _pl, _pp, plainFrom =
		L4R.holdCourse({ damage = 8, killAt = 0.3, order = "weapon" })
	check(
		plain.ended == "cleared"
			and plainFrom == nil
			and plain.clearAt ~= nil
			and plain.clearAt < 0.3 + frame + 1e-9
			and L4R.said(plainHurts) == "landed@0.100",
		`H1: with nothing waiting the clear goes through on the kill's own frame, never held ({L4R.secs(
			plain.clearAt
		)}; {L4R.said(plainHurts)})`
	)
end

function L4R.holdGroup(): ()
	L4R.startVitals()
	local ok, problem = pcall(L4R.holdTests)
	L4R.vitals.ClearThreats()
	-- tests.luau's VitalsService takes the crowd's hooks back.
	Crowd.SetThreatHooks(hooks)
	if not ok then
		error(problem, 0)
	end
end
L4R.group("l4b H1 holdTests", L4R.holdGroup)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
