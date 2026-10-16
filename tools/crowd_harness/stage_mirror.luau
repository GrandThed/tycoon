-- The Luau half of tools/check_stage_mirror.py (never shipped). That tool prepends `DATA` (the
-- shipped files and the cases it wants answered) and `SOURCES.<name>(game, script, require,
-- Vector3, ...)`, the real module bodies wrapped the way tools/crowd_harness/run_harness.py wraps
-- them. This file runs the real Combat, StageFlow, CampBrain, Region and LevelGeometry on them and prints
-- one line an answer: `OUT<tab>id<tab>json`. It decides nothing: every comparison is the Python's.

-- Vector3, as much of it as StageFlow uses -----------------------------------------------------
local vmeta = {}
local function vec(x: number, y: number, z: number): any
	return setmetatable({ X = x, Y = y, Z = z }, vmeta)
end
vmeta.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		return vec(self.X / m, self.Y / m, self.Z / m)
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	end
	return nil
end
vmeta.__add = function(a, b)
	return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vmeta.__sub = function(a, b)
	return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
vmeta.__mul = function(a, b)
	if type(a) == "number" then
		return vec(b.X * a, b.Y * a, b.Z * a)
	end
	return vec(a.X * b, a.Y * b, a.Z * b)
end
vmeta.__div = function(a, b)
	return vec(a.X / b, a.Y / b, a.Z / b)
end
vmeta.__unm = function(a)
	return vec(-a.X, -a.Y, -a.Z)
end
local V: any = {
	new = function(x, y, z)
		return vec(x or 0, y or 0, z or 0)
	end,
	zero = vec(0, 0, 0),
}

-- The modules -----------------------------------------------------------------------------------
local function token(name: string): any
	local t: any = { __module = name }
	t.WaitForChild = function(_self, child)
		return token(child)
	end
	t.Parent = t
	return t
end
local M: any = { modules = { Types = {} } }
function M.load(name: string): any
	if M.modules[name] == nil then
		local source = (SOURCES :: any)[name]
		assert(source, "no source for " .. name)
		local gameStub = {
			GetService = function(_self, service)
				return token(service)
			end,
		}
		local function requireStub(t: any): any
			return M.load(t.__module)
		end
		M.modules[name] =
			source(gameStub, token("script"), requireStub, V, os, nil, print, nil, nil)
	end
	return M.modules[name]
end

-- JSON, enough of it ------------------------------------------------------------------------------
local J: any = {}
function J.text(value: any): string
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return if value then "true" else "false"
	elseif kind == "number" then
		if value ~= value then
			return '"nan"'
		elseif value == math.huge then
			return '"inf"'
		elseif value == -math.huge then
			return '"-inf"'
		end
		return string.format("%.17g", value)
	elseif kind == "string" then
		return '"' .. string.gsub(string.gsub(value, '[\\"]', "\\%0"), "\n", "\\n") .. '"'
	elseif kind ~= "table" then
		return '"<' .. kind .. '>"'
	end
	if getmetatable(value) == vmeta then
		return `[{J.text(value.X)},{J.text(value.Y)},{J.text(value.Z)}]`
	end
	local count = 0
	for _ in value do
		count += 1
	end
	local parts: { string } = {}
	if count == #value then
		for _, item in value do
			table.insert(parts, J.text(item))
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local keys: { string } = {}
	local byText: { [string]: any } = {}
	for key, item in value do
		local name = tostring(key)
		table.insert(keys, name)
		byText[name] = item
	end
	table.sort(keys)
	for _, name in keys do
		table.insert(parts, J.text(name) .. ":" .. J.text(byText[name]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end
function J.out(id: string, value: any): ()
	print("OUT\t" .. id .. "\t" .. J.text(value))
end
-- Runs `fn`; a throw is an answer too (`{ threw = message }`), never the end of the run.
function J.try(id: string, fn: () -> any): any
	local ok, value = pcall(fn)
	if not ok then
		J.out(id, { threw = tostring(value) })
		return nil
	end
	J.out(id, value)
	return value
end

local Combat = M.load("Combat")
local Brain = M.load("CampBrain")
local Flow = M.load("StageFlow")
local Geo = M.load("LevelGeometry")
local Shapes = M.load("HitShapes")
local Gate = M.load("SwingGate")
local Region = M.load("Region")
local data: any = DATA
local rules = data.combat.levels
local director = data.combat.director

-- What the module exports: the Python lists a comparison whose function is not there.
do
	local names: { [string]: { string } } =
		{ Combat = {}, StageFlow = {}, CampBrain = {}, HitShapes = {}, SwingGate = {}, Region = {} }
	for module, value in
		{
			Combat = Combat,
			StageFlow = Flow,
			CampBrain = Brain,
			HitShapes = Shapes,
			SwingGate = Gate,
			Region = Region,
		}
	do
		for name, item in value do
			if type(item) == "function" then
				table.insert(names[module], name)
			end
		end
		table.sort(names[module])
	end
	J.out("exports", names)
end

-- Levels ------------------------------------------------------------------------------------------
local L: any = {}
function L.layout(name: string): any
	local layout = data.layouts[name]
	if layout ~= nil and layout.arena ~= nil then
		return Geo.FromArena(M.load("Arena_" .. layout.arena), -data.combat.player.rescue.below)
	end
	return layout
end
function L.mission(file: any): any
	for _, mission in data.missions do
		if file.mission ~= nil and mission.id == file.mission then
			return mission
		end
	end
	return nil
end
function L.resolve(file: any): any
	return Flow.Resolve(
		file,
		L.mission(file),
		director.runCapSeconds,
		data.expeditions.difficulties[1]
	)
end
function L.rect(rect: any): any
	return { rect.x, rect.z, rect.hx, rect.hz }
end
-- A set { [index] = true } as the sorted list of its indices (JSON cannot tell the two apart).
function L.keys(set: any): any
	local found = {}
	for key, value in set or {} do
		if value then
			table.insert(found, key)
		end
	end
	table.sort(found)
	return found
end
-- A RegionGraph as plain values: cells as { x, z, hx, hz }, next and hops as rows, the doors as a
-- sorted list of { i, j, x, z } (a sparse table of tables reads ambiguously as JSON).
function L.graph(graph: any): any
	local cells = {}
	for index, cell in graph.cells do
		cells[index] = { cell.x, cell.z, cell.hx, cell.hz }
	end
	local doors = {}
	for i = 1, #graph.cells do
		local row = graph.doors[i] or {}
		local js = {}
		for j in row do
			table.insert(js, j)
		end
		table.sort(js)
		for _, j in js do
			table.insert(doors, { i, j, row[j].x, row[j].z })
		end
	end
	return { cells = cells, next = graph.next, hops = graph.hops, doors = doors }
end
-- A Plan zone as plain values.
function L.zone(zone: any): any
	return {
		id = zone.id,
		floor = zone.floor,
		locks = zone.locks,
		name = zone.name,
		checkpoint = zone.checkpoint,
		residents = zone.residents,
		stock = zone.stock,
		tentStock = zone.tentStock,
		floorY = zone.floorY,
		rect = L.rect(zone.rect),
		inner = L.rect(zone.inner),
		trigger = L.rect(zone.trigger),
		entry = zone.entry,
		exit = zone.exit,
		spawns = zone.spawns,
		region = if zone.region ~= nil then L.graph(zone.region) else nil,
		approach = zone.approach,
	}
end
-- A Plan as plain values: a zone's rectangles as { x, z, hx, hz }, its boss waves as a list.
function L.plan(plan: any): any
	local stages = {}
	for index, stage in plan.stages do
		local boss = {}
		for wave = 1, stage.waves do
			if stage.boss[wave] then
				table.insert(boss, wave)
			end
		end
		local zone = stage.zone
		stages[index] = {
			kind = stage.kind,
			name = stage.name,
			waves = stage.waves,
			boss = boss,
			breatherSeconds = stage.breatherSeconds,
			merge = stage.merge,
			targetWaveSeconds = stage.targetWaveSeconds,
			maxAlive = stage.maxAlive,
			zone = if zone ~= nil then zone.id else nil,
		}
	end
	local zones = {}
	for index, zone in plan.zones or {} do
		zones[index] = L.zone(zone)
	end
	return {
		levelId = plan.levelId,
		difficulty = plan.difficulty,
		start = plan.start,
		killY = plan.killY,
		camps = plan.camps,
		stages = stages,
		zones = zones,
		groups = plan.groups,
		tents = plan.tents or {},
		population = plan.population,
	}
end
-- { plan = ... } or { refused = reason }.
function L.planned(level: any, layout: any, difficulty: string): (any, any)
	local plan, why = Flow.Plan(
		level,
		layout,
		difficulty,
		rules,
		Geo.Bounds(layout),
		data.ranks,
		data.proving.crowd.kinds
	)
	if plan == nil then
		return nil, { refused = why or "nil" }
	end
	return plan, { plan = L.plan(plan) }
end

for index, file in data.levels do
	local id = `level.{index}`
	local level = J.try(id .. ".resolve", function()
		return L.resolve(file)
	end)
	local layout = nil
	pcall(function()
		layout = L.layout(file.layout)
	end)
	if level == nil or layout == nil then
		continue
	end
	J.try(id .. ".validate", function()
		return Flow.Validate(
			level,
			layout,
			data.proving.crowd.kinds,
			data.ranks,
			rules,
			data.proving.crowd.maxAlive
		)
	end)
	for _, difficulty in data.planDifficulties do
		local plan = nil
		J.try(`{id}.plan.{difficulty}`, function()
			local planned, answer = L.planned(level, layout, difficulty)
			plan = planned
			return answer
		end)
		if plan == nil then
			continue
		end
		-- Spawn grids and the boss's place, in the world.
		for _, case in data.pointCases do
			if case.level ~= index or case.difficulty ~= difficulty then
				continue
			end
			local zone = plan.stages[case.stage].zone
			J.try(case.id, function()
				if case.boss ~= nil then
					return Flow.BossPoint(zone, case.boss)
				end
				return Flow.BurstPoint(
					zone,
					zone.spawns[case.spawn],
					case.size,
					case.index,
					case.spacing
				)
			end)
		end
	end
end

-- Combat: one wave of one camp for a difficulty and a party, and what its kills pay ---------------------
for _, case in data.waveCases do
	local file = data.levels[case.level]
	local spec = J.try(case.id, function()
		local level = L.resolve(file)
		local stage = level.stages[case.stage]
		return Combat.CampWave(
			stage.waves[case.wave],
			level.crowd.regenShare,
			level.difficulties[case.difficulty],
			data.ranks[case.difficulty],
			data.ranks,
			case.party,
			data.combat
		)
	end)
	if spec ~= nil and case.kinds ~= nil then
		J.try(case.id .. ".rewards", function()
			local level = L.resolve(file)
			local paid = {}
			for _, kind in case.kinds do
				local cash, materials = Combat.CampReward(level.crowd.rewards, kind, spec)
				paid[kind] = { cash, materials }
			end
			return paid
		end)
	end
end

-- Combat: prices under reward multipliers that leave halves, and the director's four numbers, on
-- the Python's grids -----------------------------------------------------------------------------
J.try("grid.campReward", function()
	local found = {}
	for index, case in data.rewardCases do
		local cash, materials = Combat.CampReward(
			{ probe = { cash = case[1], materials = case[2] } },
			"probe",
			{ rewardMult = case[3] }
		)
		found[index] = { cash, materials }
	end
	return found
end)
J.try("grid.killReward", function()
	local found = {}
	for index, case in data.rewardCases do
		local cash, materials =
			Combat.KillReward({ probe = { cash = case[1], materials = case[2] } }, "probe", case[3])
		local noCash, noMaterials = Combat.KillReward({}, "probe", case[3])
		found[index] = { cash, materials, noCash, noMaterials }
	end
	return found
end)
J.try("grid.burstSeconds", function()
	local found = {}
	for index, case in data.burstCases do
		found[index] = Combat.BurstSeconds(case[1], case[2], case[3])
	end
	return found
end)
J.try("grid.tempo", function()
	local found = {}
	for index, case in data.tempoCases do
		found[index] = Combat.Tempo(case[1], case[2], case[3], director)
	end
	return found
end)
J.try("grid.shouldMerge", function()
	local found = {}
	for index, case in data.mergeCases do
		found[index] = Combat.ShouldMerge(case[1], case[2], director)
	end
	return found
end)
J.try("grid.breatherSeconds", function()
	local found = {}
	for index, tempo in data.breatherCases do
		found[index] = Combat.BreatherSeconds(tempo, director)
	end
	return found
end)

-- Ruling 6: is a level with one number set to zero or emptied refused? ---------------------------------
for _, case in data.refusalCases do
	J.try(case.id, function()
		local level = L.resolve(case.file)
		if level == nil then
			return { "it does not resolve" }
		end
		local layout = if case.layout ~= nil then case.layout else L.layout(case.file.layout)
		return Flow.Validate(
			level,
			layout,
			data.proving.crowd.kinds,
			data.ranks,
			case.rules,
			data.proving.crowd.maxAlive
		)
	end)
end

-- Traces: the real Advance (and the Studio levers Skip and Force), tick by tick, on the Python's
-- script -----------------------------------------------------------------------------------------
for _, trace in data.traces do
	J.try(trace.id, function()
		local file = data.levels[trace.level]
		local level = L.resolve(file)
		local layout = L.layout(file.layout)
		local plan = L.planned(level, layout, trace.difficulty)
		if plan == nil then
			return { refused = true }
		end
		local state = Flow.Begin(plan)
		local ticks = {}
		for index, tick in trace.ticks do
			local roots = {}
			for _, root in tick.roots do
				table.insert(roots, V.new(root[1], root[2], root[3]))
			end
			local input = {
				now = tick.now,
				roots = roots,
				standing = tick.standing,
				fighters = tick.fighters,
				spawningDone = tick.spawningDone,
				alive = tick.alive,
				awake = tick.awake,
				aliveByFloor = tick.aliveByFloor,
				mergeOk = tick.mergeOk,
				breatherSeconds = tick.breatherSeconds,
				fallen = tick.fallen,
				runCap = tick.runCap,
			}
			local clear = Flow.FieldClear(plan, state, input)
			local standsUp = Flow.StandsUp(plan, state, input)
			local actions
			if tick.op == "skip" then
				actions = Flow.Skip(plan, state, tick.which, tick.now, rules, tick.fighters)
			elseif tick.op == "force" then
				actions = Flow.Force(plan, state, tick.wave)
			else
				actions = Flow.Advance(plan, state, input, rules)
			end
			local shown = table.clone(state)
			shown.reached = L.keys(state.reached)
			shown.done = L.keys(state.done)
			local safe = {}
			for which, case in data.busyCases do
				local zones = #plan.zones
				local busy = nil
				if case == "all" and zones > 0 then
					busy = {}
					for floor = 1, zones do
						busy[floor] = true
					end
				elseif case == "first" and zones > 0 then
					busy = { [1] = true }
				elseif case == "last" and zones > 0 then
					busy = { [zones] = true }
				end
				-- The fix round's threats: 5 studs off every checkpoint, reach exactly 5 or a hair under.
				local threats = nil
				local reach = if case == "threatAll"
					then 5
					elseif case == "threatShort" then 5 - 1e-6
					else nil
				if reach ~= nil then
					threats = {}
					for _, zone in plan.zones do
						local mark = zone.checkpoint
						if mark ~= nil then
							table.insert(
								threats,
								{ at = V.new(mark.X + 3, mark.Y + 7, mark.Z + 4), reach = reach }
							)
						end
					end
				end
				safe[which] = Flow.SafePoint(plan, state, busy, threats)
			end
			ticks[index] = {
				actions = actions,
				state = shown,
				directs = Flow.Directs(state),
				closing = Flow.StillClosing(state, tick.now, rules),
				clear = clear,
				safe = safe,
				standsUp = standsUp,
			}
		end
		local stars = {}
		for index, user in trace.users do
			stars[index] = Flow.EarnsStar(state, user)
		end
		return { ticks = ticks, stars = stars }
	end)
end
-- CampBrain (L1b): the Python's cases, each answered by the real module -----------------------------
local C: any = {}
function C.v(point: any): any
	return V.new(point[1], point[2], point[3])
end
-- A def row (points as { x, y, z }) as a CampGroupDef.
function C.def(row: any): any
	local def = table.clone(row)
	local points = {}
	for index, point in row.points do
		points[index] = C.v(point)
	end
	def.points = points
	def.radius = row.radius or 0
	return def
end
function C.post(row: any): any
	return { at = C.v(row.at), yaw = row.yaw, leg = row.leg }
end
function C.targets(rows: any): any
	local found = {}
	for index, row in rows do
		found[index] = {
			userId = row.userId,
			root = C.v(row.root),
			rest = if row.rest ~= nil then row.rest else row.root[2],
		}
	end
	return found
end
function C.group(row: any, state: string, held: boolean): any
	local group = Brain.NewGroup(C.def(row), 0)
	group.state = state
	group.held = held
	return group
end
function C.snapshot(group: any): any
	local hitAt = {}
	for _, user in L.keys(group.hitAt) do
		table.insert(hitAt, { user, group.hitAt[user] })
	end
	return {
		state = group.state,
		held = group.held,
		since = group.since,
		quietSince = group.quietSince,
		hit = group.hit,
		known = L.keys(group.known),
		reachable = L.keys(group.reachable),
		hitAt = hitAt,
		struckBy = L.keys(group.struckBy),
		meleeQuietSince = group.meleeQuietSince,
		standDown = group.standDown,
	}
end
function C.shooters(rows: any): any
	local shooters = {}
	for index, shooter in rows do
		shooters[index] = { at = C.v(shooter.at), reach = shooter.reach }
	end
	return shooters
end
function C.cells(rows: any): any
	local cells = {}
	for index, row in rows do
		cells[index] = { x = row[1], z = row[2], hx = row[3], hz = row[4] }
	end
	return cells
end
local campRules = data.campRules
for _, case in data.campCases do
	J.try(case.id, function()
		local op = case.op
		if op == "posts" then
			return Brain.Posts(C.def(case.def), case.count)
		elseif op == "sees" then
			local def = C.def(case.def)
			local member = { at = C.v(case.member.at), post = C.post(case.member.post) }
			local found = {}
			for index, target in C.targets(case.targets) do
				found[index] = Brain.Sees(def, member, target, campRules)
			end
			return found
		elseif op == "inPlay" then
			local def = C.def(case.def)
			local shooters = {}
			for index, shooter in case.shooters do
				shooters[index] = { at = C.v(shooter.at), reach = shooter.reach }
			end
			local found = {}
			for index, target in C.targets(case.targets) do
				found[index] = Brain.InPlay(def, target, shooters, campRules)
			end
			return found
		elseif op == "atPost" then
			local post = C.post(case.post)
			local found = {}
			for index, at in case.ats do
				found[index] = Brain.AtPost(post, C.v(at), campRules)
			end
			return found
		elseif op == "goal" then
			local group = C.group(case.def, case.state, case.held)
			group.standDown = case.standDown == true
			local resident = { group = 1, post = C.post(case.post), leg = case.leg }
			local goal, pace = Brain.Goal(group, resident, C.v(case.at), campRules)
			return { if goal ~= nil then goal else "nil", pace, resident.leg }
		elseif op == "struck" then
			local group = C.group(case.def, case.state, case.held)
			group.standDown = case.standDown == true
			local rows = {}
			for index, now in { 4.25, 7.5 } do
				local landed = Brain.Struck(group, case.by, now)
				rows[index] = { landed, group.hit, Brain.Evades(group), C.snapshot(group) }
			end
			return rows
		elseif op == "shows" then
			local group = C.group(case.def, case.state, case.held)
			group.standDown = case.standDown == true
			local shown = Brain.Shows(group, case.moving)
			return if shown ~= nil then shown else "nil"
		elseif op == "melee" or op == "reachable" then
			local def = C.def(case.def)
			local shooters = C.shooters(case.shooters)
			local found = {}
			for index, target in C.targets(case.targets) do
				found[index] = if op == "melee"
					then Brain.Melee(def, target, campRules)
					else Brain.Reachable(def, target, shooters, campRules)
			end
			return found
		elseif op == "standsDown" then
			local found = {}
			for index, row in case.rows do
				local group = C.group(case.def, row[1], row[2])
				group.standDown = row[3]
				found[index] = Brain.StandsDown(group, row[4])
			end
			return found
		elseif op == "forget" then
			local group = C.group(case.def, case.state, case.held)
			group.standDown = true
			group.known[1] = true
			group.reachable[1] = true
			group.struckBy[2] = true
			group.hitAt[2] = 1.5
			local ret = Brain.Forget(group, 3.25)
			return { ret = if ret ~= nil then ret else "nil", group = C.snapshot(group) }
		elseif op == "problems" then
			return #Brain.Problems(case.rules)
		elseif op == "dormant" then
			local group = C.group(case.def, case.state, case.held)
			local found = {}
			for index, roots in case.rootSets do
				local points = {}
				for k, root in roots do
					points[k] = C.v(root)
				end
				found[index] = Brain.Dormant(group, points, campRules)
			end
			return found
		elseif op == "gap" then
			local posts = {}
			for index, list in case.posts do
				local converted = {}
				for k, row in list do
					converted[k] = C.post(row)
				end
				posts[index] = converted
			end
			local found = {}
			for index, pair in case.pairs do
				found[index] = Brain.Gap(posts[pair[1]] or {}, posts[pair[2]] or {})
			end
			return found
		elseif op == "joinIn" then
			local groups = {}
			for index, row in case.defs do
				groups[index] = Brain.NewGroup(C.def(row), 0)
			end
			for _, entry in case.states do
				groups[entry[1]].state = entry[2]
				groups[entry[1]].held = entry[3]
			end
			local living = {}
			for _, entry in case.living do
				living[entry[1]] = entry[2]
			end
			local gaps = {}
			for _, entry in case.gaps do
				gaps[entry[1]] = gaps[entry[1]] or {}
				gaps[entry[1]][entry[2]] = entry[3]
			end
			return Brain.JoinIn(groups, living, gaps, case.woke, campRules)
		elseif op == "rouse" then
			local group = C.group(case.def, case.state, case.held)
			group.hit = true
			local ret = Brain.Rouse(group, 4.5, case.reachable == true)
			return { ret = ret, group = C.snapshot(group) }
		elseif op == "tentRouse" then
			local group = C.group(case.def, case.state, case.held)
			group.hit = true
			local ret = Brain.TentRouse(group, 4.5, case.reachable == true)
			return { ret = ret, group = C.snapshot(group) }
		elseif op == "tent" then
			local tent = Brain.NewTent(case.stock, case.residents)
			local rows = {}
			for index, step in case.ops do
				local ret: any = "nil"
				if step[1] == "active" then
					ret = Brain.TentActive(step[2], step[3], step[4])
				elseif step[1] == "due" then
					ret = Brain.TentDue(tent, step[2], step[3])
				elseif step[1] == "clock" then
					Brain.TentClock(tent, step[2], step[3], step[4], step[5])
				elseif step[1] == "ahead" then
					ret = Brain.Ahead(step[2], step[3], tent.busySeconds, step[4])
				elseif step[1] == "aheadTent" then
					-- R7: WaveService's call, counted from the tent's own residents.
					ret = Brain.Ahead(
						tent.residents - step[2],
						tent.residents,
						tent.busySeconds,
						step[3]
					)
				else
					Brain.TentSent(tent, step[2], case.every)
				end
				rows[index] = {
					ret = ret,
					left = tent.left,
					nextAt = tent.nextAt,
					busySeconds = tent.busySeconds,
					lastAt = if tent.lastAt ~= nil then tent.lastAt else "nil",
					residents = tent.residents,
				}
			end
			return rows
		elseif op == "engaged" then
			local found = {}
			for index, row in case.rows do
				found[index] = Brain.Engaged(
					if row.lastAt == "nil" then nil else row.lastAt,
					row.now,
					campRules
				)
			end
			return found
		elseif op == "timeline" then
			local group = Brain.NewGroup(C.def(case.def), 0)
			local rows = {}
			for index, step in case.ops do
				local ret: any = nil
				if step.kind == "step" then
					local members = {}
					for m, member in step.members do
						members[m] = { at = C.v(member.at), post = C.post(member.post) }
					end
					local shooters = {}
					for k, shooter in step.shooters do
						shooters[k] = { at = C.v(shooter.at), reach = shooter.reach }
					end
					ret = Brain.Step(group, {
						now = step.now,
						members = members,
						targets = C.targets(step.targets),
						shooters = shooters,
						striking = step.striking,
						closing = step.closing == true,
					}, campRules)
				elseif step.kind == "release" then
					Brain.Release(group, step.now)
				elseif step.kind == "forget" then
					ret = Brain.Forget(group, step.now)
				else
					ret = Brain.Struck(group, step.by, step.now)
				end
				rows[index] = { ret = if ret ~= nil then ret else "nil", group = C.snapshot(group) }
			end
			return rows
		end
		error("unknown op " .. tostring(op))
	end)
end

-- L1b Wave 2: HitShapes' ray rules, SwingGate, Combat's bonus and merge numbers, BossReserve ------------
for _, case in data.rayCases do
	J.try(case.id, function()
		local found = {}
		for index, row in case.rows do
			if case.op == "crowdRay" then
				local entry, crit = Shapes.CrowdRay(
					C.v(row[1]),
					C.v(row[2]),
					row[3],
					row[4],
					row[5],
					C.v(row[6]),
					row[7],
					row[8],
					row[9]
				)
				found[index] = { if entry ~= nil then entry else "nil", crit }
			elseif case.op == "rayUpright" then
				local entry = Shapes.RayUpright(
					C.v(row[1]),
					C.v(row[2]),
					row[3],
					row[4],
					row[5],
					C.v(row[6]),
					row[7],
					row[8],
					row[9]
				)
				found[index] = if entry ~= nil then entry else "nil"
			else
				found[index] = Shapes.FlatToRect(row[1], row[2], row[3], row[4], row[5], row[6])
			end
		end
		return found
	end)
end
for _, case in data.swingCases do
	J.try(case.id, function()
		if case.op == "margin" then
			return Gate.AIR_MARGIN_STUDS
		elseif case.op == "isAir" then
			local found = {}
			for index, height in case.heights do
				found[index] = Gate.IsAir(if height == "nil" then nil else height, case.stand)
			end
			return found
		end
		local state = Gate.New()
		local rows = {}
		for index, step in case.ops do
			local ret: any = "nil"
			if step[1] == "allows" then
				ret = Gate.Allows(state, step[2])
			elseif step[1] == "took" then
				Gate.Took(state, step[2])
			else
				Gate.Landed(state)
			end
			rows[index] = { ret = ret, used = state.used }
		end
		return rows
	end)
end
local waveById: { [string]: any } = {}
for _, case in data.waveCases do
	waveById[case.id] = case
end
for _, case in data.combatCases do
	J.try(case.id, function()
		local found = {}
		for index, row in case.rows do
			if case.op == "clearBonus" then
				local cash, materials = Combat.ClearBonus(row[1], row[2], row[3], row[4])
				found[index] = { cash, materials }
			elseif case.op == "deadFraction" then
				found[index] = Combat.DeadFraction(row[1], row[2])
			else
				local wave = waveById[row[1]]
				local level = L.resolve(data.levels[wave.level])
				local stage = level.stages[wave.stage]
				local spec = Combat.CampWave(
					stage.waves[wave.wave],
					level.crowd.regenShare,
					level.difficulties[wave.difficulty],
					data.ranks[wave.difficulty],
					data.ranks,
					wave.party,
					data.combat
				)
				local stock = { fodder = 2 }
				Combat.WaveStock(stock, spec, if row[2] == "nil" then nil else row[2])
				found[index] = stock
			end
		end
		return found
	end)
end
for _, case in data.reserveCases do
	J.try(case.id, function()
		local level = L.resolve(data.levels[case.level])
		return { Flow.BossReserve(level, data.proving.crowd.kinds), Flow.BossReserve(level, nil) }
	end)
end
for _, case in data.tentOwesCases do
	J.try(case.id, function()
		local found = {}
		for index, row in case.rows do
			found[index] = if case.op == "threatening"
				then Flow.Threatening(row)
				else Flow.TentOwesRouse(row[1], row[2], row[3])
		end
		return found
	end)
end

-- L1b Wave 4: Region on the Python's grids, and StageFlow.Fielded on the shipped plans ----------------
for _, case in data.regionCases do
	J.try(case.id, function()
		local cells = C.cells(case.cells)
		local op = case.op
		if op == "build" then
			return L.graph(Region.Build(cells))
		elseif op == "problems" then
			return #Region.Problems(cells, case.minDoor)
		end
		local found = {}
		if op == "distance" then
			for index, point in case.points do
				found[index] = Region.Distance(cells, point[1], point[2])
			end
		elseif op == "inside" or op == "clamp" then
			for index, row in case.rows do
				local point = V.new(row[1], row[2], row[3])
				found[index] = if op == "inside"
					then Region.Inside(cells, point, row[4])
					else Region.Clamp(cells, point, row[4])
			end
		elseif op == "runway" then
			for index, row in case.rows do
				found[index] = Region.Runway(
					cells,
					V.new(row[1], row[2], row[3]),
					V.new(row[4], 0, row[5]),
					row[6]
				)
			end
		elseif op == "toward" then
			local graph = Region.Build(cells)
			for index, row in case.rows do
				local point, through = Region.Toward(
					graph,
					V.new(row[1], row[2], row[3]),
					V.new(row[4], row[5], row[6]),
					row[7]
				)
				found[index] = { point, through }
			end
		else
			error("unknown region op " .. tostring(op))
		end
		return found
	end)
end
for _, case in data.fieldedCases do
	J.try(case.id, function()
		local file = data.levels[case.level]
		local level = L.resolve(file)
		local plan = L.planned(level, L.layout(file.layout), case.difficulty)
		if plan == nil then
			return { refused = true }
		end
		local tent = if case.tent ~= 0 then plan.tents[case.tent] else nil
		-- The fix round's R12: the stock indices the crowd refused.
		local refused: { [number]: boolean }? = nil
		if case.refused ~= nil then
			refused = {}
			for _, index in case.refused do
				(refused :: any)[index] = true
			end
		end
		return Flow.Fielded(plan.zones[case.zone], tent, case.sent, refused)
	end)
end

-- Combat.SplitCarry: the Python's seeded kills, the carry after each ------------------------------------
for _, case in data.splitCases do
	J.try(case.id, function()
		local carry = {}
		local rows = {}
		for index, call in case.calls do
			local shares = {}
			for _, pair in call.shares do
				shares[pair[1]] = pair[2]
			end
			local mults = nil
			if call.mults ~= nil then
				mults = {}
				for _, pair in call.mults do
					mults[pair[1]] = pair[2]
				end
			end
			local paid = Combat.SplitCarry(call.pool, shares, carry, mults)
			local function listed(map: any): any
				local users = {}
				for user in map do
					table.insert(users, user)
				end
				table.sort(users)
				local found = {}
				for _, user in users do
					local entry = map[user]
					table.insert(found, { user, entry.cash, entry.materials, entry.valor })
				end
				return found
			end
			rows[index] = { paid = listed(paid), carry = listed(carry) }
		end
		return rows
	end)
end
print("DONE")
