-- The Luau half of tools/check_stage_mirror.py (never shipped). That tool prepends `DATA` (the
-- shipped files and the cases it wants answered) and `SOURCES.<name>(game, script, require,
-- Vector3, ...)`, the real module bodies wrapped the way tools/crowd_harness/run_harness.py wraps
-- them. This file runs the real Combat, StageFlow and LevelGeometry on them and prints one line
-- an answer: `OUT<tab>id<tab>json`. It decides nothing: every comparison is the Python's.

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
		M.modules[name] = source(gameStub, token("script"), requireStub, V, os, nil, print, nil, nil)
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
local Flow = M.load("StageFlow")
local Geo = M.load("LevelGeometry")
local data: any = DATA
local rules = data.combat.levels
local director = data.combat.director

-- What the module exports: the Python lists a comparison whose function is not there.
do
	local names: { [string]: { string } } = { Combat = {}, StageFlow = {} }
	for name, value in Combat do
		if type(value) == "function" then
			table.insert(names.Combat, name)
		end
	end
	for name, value in Flow do
		if type(value) == "function" then
			table.insert(names.StageFlow, name)
		end
	end
	table.sort(names.Combat)
	table.sort(names.StageFlow)
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
	return Flow.Resolve(file, L.mission(file), director.runCapSeconds, data.expeditions.difficulties[1])
end
function L.rect(rect: any): any
	return { rect.x, rect.z, rect.hx, rect.hz }
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
			bankEachWave = stage.bankEachWave,
			targetWaveSeconds = stage.targetWaveSeconds,
			maxAlive = stage.maxAlive,
			zone = if zone ~= nil
				then {
					id = zone.id,
					floorY = zone.floorY,
					rect = L.rect(zone.rect),
					inner = L.rect(zone.inner),
					trigger = L.rect(zone.trigger),
					entry = zone.entry,
					exit = zone.exit,
					spawns = zone.spawns,
				}
				else nil,
		}
	end
	return {
		levelId = plan.levelId,
		difficulty = plan.difficulty,
		start = plan.start,
		killY = plan.killY,
		camps = plan.camps,
		stages = stages,
	}
end
-- { plan = ... } or { refused = reason }.
function L.planned(level: any, layout: any, difficulty: string): (any, any)
	local plan, why = Flow.Plan(level, layout, difficulty, rules, Geo.Bounds(layout))
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
		return Flow.Validate(level, layout, data.proving.crowd.kinds, data.ranks, rules)
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
				return Flow.BurstPoint(zone, zone.spawns[case.spawn], case.size, case.index, case.spacing)
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
		return Combat.CampWave(stage.waves[case.wave], level.crowd.regenShare, level.difficulties[case.difficulty], data.ranks[case.difficulty], data.ranks, case.party, data.combat)
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
		local cash, materials = Combat.CampReward({ probe = { cash = case[1], materials = case[2] } }, "probe", { rewardMult = case[3] })
		found[index] = { cash, materials }
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
		return Flow.Validate(level, L.layout(case.file.layout), data.proving.crowd.kinds, data.ranks, case.rules)
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
			local actions
			if tick.op == "skip" then
				actions = Flow.Skip(plan, state, tick.which, tick.now, rules, tick.fighters)
			elseif tick.op == "force" then
				actions = Flow.Force(plan, state, tick.wave)
			else
				actions = Flow.Advance(plan, state, {
					now = tick.now,
					roots = roots,
					fighters = tick.fighters,
					fieldClear = tick.fieldClear,
					spawningDone = tick.spawningDone,
					mergeOk = tick.mergeOk,
					breatherSeconds = tick.breatherSeconds,
					fallen = tick.fallen,
					runCap = tick.runCap,
				}, rules)
			end
			ticks[index] = {
				actions = actions,
				state = table.clone(state),
				directs = Flow.Directs(state),
				closing = Flow.StillClosing(state, tick.now, rules),
			}
		end
		local stars = {}
		for index, user in trace.users do
			stars[index] = Flow.EarnsStar(state, user)
		end
		return { ticks = ticks, stars = stars }
	end)
end
print("DONE")
