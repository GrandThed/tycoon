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

print("L4 W1b: RunState's floors carry their cells once per member per floor set (RunFloors)")

local L4R: any = {
	Floors = load("RunFloors"),
	Flow = load("StageFlow"),
	Geo = load("LevelGeometry"),
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
-- play.cellsSent, cleared at Admit and Remove. `send` is ArenaService.sendRunState: Attach with
-- what that member was sent, then the set noted as sent either way. `build` is BuildRunState's
-- floors (Attach with the set's own number: never the cells).
L4R.Server = {}

function L4R.Server.new(floors: { any }): any
	return { floors = floors, seq = 1, sent = {} }
end

function L4R.Server.setFloors(server: any, floors: { any }): ()
	server.floors = floors
	server.seq += 1
end

function L4R.Server.send(server: any, userId: number): ({ any }, boolean)
	local floors, went = L4R.Floors.Attach(server.floors, server.seq, server.sent[userId])
	server.sent[userId] = server.seq
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

-- The shipped Forest Road, its floors built as WaveService.startLevel builds them.
function L4R.shippedTests(): ()
	print(" The shipped Forest Road: its region floors' cells go once")
	local file = nil
	for _, candidate in FIXTURES.levels do
		if candidate.id == "forestRoad" then
			file = candidate
		end
	end
	if file == nil then
		check(false, "Forest Road's level file is there (the cases below need it)")
		return
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

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
