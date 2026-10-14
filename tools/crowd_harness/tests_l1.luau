-- Cases for L1's run rules (docs/INTERFACES.md "L1 contracts" → "B — the run"): the pure
-- StageFlow, Combat's camp functions, and CrowdService's floor. Appended last by run_harness.py,
-- so every local of the earlier files is in scope. Everything hangs off the L1 table (the
-- 200-local limit). WaveService and ArenaService are Instance and service work and cannot be
-- loaded here: they only execute what StageFlow returns.
-- The last group, "the real files", runs the same rules (and LevelGeometry's) on the level
-- files, layouts and map that ship, not on fixtures.

print("L1: the run (StageFlow)")

local L1: any = {
	Flow = load("StageFlow"),
	Combat = load("Combat"),
	Geo = load("LevelGeometry"),
	village = FIXTURES.village,
	combat = FIXTURES.combat,
	rules = { gateSeconds = 3, triggerInset = 4, triggerHeight = 30, startSpacing = 4, startCooldownSeconds = 2, fenceThickness = 1, boxMargin = 40, maxParts = 600, closeInset = 2 },
	ranks = { normal = 1, hard = 2, brutal = 3 },
	bounds = { minX = -50, minY = -1, minZ = -20, maxX = 150, maxY = 20, maxZ = 560 },
	rescue = { below = 8, outside = 4 },
}

function L1.copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, item in value do
		out[key] = L1.copy(item)
	end
	return out
end

-- Three camps at three heights along +Z: A (60 x 60, floor 0), B (100 x 94, floor 12, off the
-- axis), C (80 x 80, floor 4).
function L1.layout(): any
	local function camp(id: string, x: number, y: number, z: number, sx: number, sz: number): any
		return {
			id = id, x = x, y = y, z = z, sx = sx, sz = sz,
			fence = { height = 6 },
			gates = { { side = "north", at = 0, width = 14 }, { side = "south", at = 0, width = 14 } },
			entry = { x = x, z = z - sz / 2 + 4 },
			exit = { x = x, z = z + sz / 2 - 4 },
			checkpoint = { x = x + 6, z = z + sz / 2 - 6 },
			spawns = { { x = x - 20, z = z + 10 }, { x = x + 20, z = z + 10 }, { x = x - 20, z = z + 20 }, { x = x + 20, z = z + 20 } },
		}
	end
	return {
		version = 1,
		start = { x = 0, y = 0, z = 0 },
		killY = -60,
		barrier = { height = 80, thickness = 8 },
		camps = { camp("A", 0, 0, 100, 60, 60), camp("B", 100, 12, 300, 100, 94), camp("C", 0, 4, 520, 80, 80) },
		blocks = {},
		secrets = {},
		route = {},
	}
end

function L1.level(): any
	local function scales(hp: number, count: number, reward: number, tier: number): any
		return { hpScale = hp, damageScale = 1.1, plateScale = 1, countMult = count, rewardMult = reward, recommendedTier = tier }
	end
	return {
		version = 1, id = "road", name = "Road", layout = "Road",
		material = "Timber", targetMinutes = 7, runCapSeconds = 900,
		difficulties = { normal = scales(1.5, 1, 1, 2), hard = scales(5, 1.25, 2, 4) },
		crowd = {
			regenShare = 0.07, maxAlive = 40, burst = 8, burstSpacing = 3.5,
			rewards = { fodder = { cash = 90, materials = 0 }, slinger = { cash = 450, materials = 1 }, armoured = { cash = 2200, materials = 6 }, colossus = { cash = 30000, materials = 60 } },
		},
		stages = {
			{ kind = "travel", name = "Follow the road" },
			{ kind = "camp", zone = "A", name = "Pickets", targetWaveSeconds = 20, breatherSeconds = 3, maxAlive = 16, waves = {
				{ groups = { { kind = "fodder", count = 8 } } },
				{ groups = { { kind = "fodder", count = 8 }, { kind = "slinger", count = 2 }, { kind = "armoured", count = 2, minDifficulty = "hard" } } },
			} },
			{ kind = "travel", name = "On to the main camp" },
			{ kind = "camp", zone = "B", name = "Main Camp", targetWaveSeconds = 25, waves = { { groups = { { kind = "fodder", count = 10 } } } } },
			{ kind = "travel", name = "To the chief" },
			{ kind = "camp", zone = "C", name = "Clearing", targetWaveSeconds = 30, waves = {
				{ groups = { { kind = "fodder", count = 6 } } },
				{ groups = {}, boss = { kind = "colossus", at = { 0, 10 }, valor = 10 } },
			} },
		},
	}
end

L1.kinds = {
	fodder = { radius = 1.3 },
	slinger = { radius = 1.2 },
	armoured = { radius = 1.7 },
	colossus = { radius = 4 },
	stray = { radius = 1 },
}

function L1.plan(level: any?, layout: any?, difficulty: string?): any
	return L1.Flow.Plan(level or L1.level(), layout or L1.layout(), difficulty or "normal", L1.rules, L1.bounds)
end

-- An Input with the quiet defaults: nobody anywhere, a clear field, nothing wrong.
function L1.input(over: any?): any
	local input: any = { now = 0, roots = {}, fieldClear = true, spawningDone = true, mergeOk = false, breatherSeconds = 6, fallen = nil, runCap = false }
	for key, value in over or {} do
		input[key] = value
	end
	return input
end

function L1.names(actions: { any }): string
	local out = {}
	for _, action in actions do
		table.insert(out, action.kind)
	end
	return table.concat(out, " ")
end

function L1.find(actions: { any }, kind: string): any
	for _, action in actions do
		if action.kind == kind then
			return action
		end
	end
	return nil
end

function L1.advance(plan: any, state: any, over: any?): { any }
	return L1.Flow.Advance(plan, state, L1.input(over), L1.rules)
end

-- A root standing on a camp's floor, at its centre.
function L1.inCamp(plan: any, stage: number): any
	local zone = plan.stages[stage].zone
	return vec(zone.rect.x, zone.floorY + 3, zone.rect.z)
end

-- Walks a fresh run to the fight of the camp at `stage` (clearing every camp before it), at
-- time `now`, and returns the state.
function L1.toFight(plan: any, stage: number, now: number?): any
	local state = L1.Flow.Begin(plan)
	local at = now or 0
	for _ = 1, 200 do
		if state.stage == stage and state.step == "fight" then
			return state
		end
		if state.step == "travel" or state.step == "armed" then
			local target = if state.step == "armed" then state.stage else state.stage + 1
			L1.advance(plan, state, { now = at, roots = { L1.inCamp(plan, target) } })
		elseif state.step == "gate" then
			at = state.gateAt
			L1.advance(plan, state, { now = at })
		elseif state.step == "breather" then
			at = state.breatherUntil
			L1.advance(plan, state, { now = at })
		else
			L1.advance(plan, state, { now = at })
		end
	end
	error("L1.toFight: the run never reached stage " .. stage)
end

function L1.has(problems: { string }, text: string): boolean
	for _, problem in problems do
		if string.find(problem, text, 1, true) ~= nil then
			return true
		end
	end
	return false
end

function L1.same(a: any, b: any): boolean
	return near(a.X, b.X, 1e-9) and near(a.Y, b.Y, 1e-9) and near(a.Z, b.Z, 1e-9)
end

function L1.resolveTests(): ()
	print(" Resolve: the Raider Arena is a level of one camp (ruling 27)")
	local Flow = L1.Flow
	local Combat = L1.Combat
	local village = L1.village
	local block = village.crowd
	local file = { version = 1, id = "raiderArena", name = "Raider Arena", layout = "RaiderArena", mission = "village", recommendedTier = 2 }
	local level = Flow.Resolve(file, village, 1800)
	local stage = level.stages[1]
	local bosses = {}
	for index, wave in stage.waves do
		if wave.boss ~= nil then
			table.insert(bosses, tostring(index))
		end
	end
	check(#level.stages == 1 and stage.kind == "camp" and stage.zone == "arena" and stage.name == "Raider Arena", "one stage: a camp named after the level, in the zone `arena`")
	check(#stage.waves == 10 and table.concat(bosses, ",") == "5,10", `ten waves, bosses at 5 and 10 ({table.concat(bosses, ",")})`)
	check(stage.merge == true and stage.breatherSeconds == nil and stage.bankEachWave == true, "it merges, takes the director's breather, and banks at every wave clear")
	check(stage.targetWaveSeconds == village.targetWaveSeconds and stage.maxAlive == nil, "the mission's targetWaveSeconds; no cap of its own")
	local normal = level.difficulties.normal
	check(normal.hpScale == block.hpScale and normal.damageScale == block.damageScale and normal.plateScale == block.plateScale, "Normal's three scales are the block's")
	check(normal.countMult == 1 and normal.rewardMult == 1 and normal.recommendedTier == 2 and next(level.difficulties, "normal") == nil, "countMult 1, rewardMult 1, the file's recommendedTier, and no other difficulty")
	check(level.material == village.material and level.targetMinutes == village.targetMinutes and level.runCapSeconds == 1800 and level.mission == "village", "the mission's material and minutes, the director's cap, and the mission it writes")
	check(level.crowd.regenShare == block.regenShare and level.crowd.maxAlive == block.maxAlive and level.crowd.burst == block.burst and level.crowd.burstSpacing == block.burstSpacing and level.crowd.rewards == block.rewards, "its crowd numbers are the block's")
	check(Flow.Resolve(file, nil, 1800) == nil and Flow.Resolve(file, { id = "bare", material = "Timber" }, 1800) == nil, "a file whose mission is missing, or has no crowd block, is no level")

	local own = L1.level()
	local asItStands = Flow.Resolve(own, nil, 1800)
	check(asItStands ~= nil and asItStands.stages == own.stages and asItStands.crowd == own.crowd and asItStands.difficulties == own.difficulties and asItStands.runCapSeconds == 900 and asItStands.mission == nil, "a file with no mission is taken as it stands, with its own run cap")
	own.runCapSeconds = 0
	check(Flow.Resolve(own, nil, 1800).runCapSeconds == 1800, "(a file that names no cap runs under the director's)")
	for _, key in { "stages", "difficulties", "crowd" } do
		local broken = L1.level()
		broken[key] = nil
		check(Flow.Resolve(broken, nil, 1800) == nil, `a file without {key} is no level`)
	end

	print(" Combat: CampWave on the adapter is CrowdWave on the mission")
	local allSame = true
	local shown = ""
	for _, party in { 1, 3 } do
		for wave = 1, 10 do
			local camp = Combat.CampWave(stage.waves[wave], level.crowd.regenShare, normal, 1, { normal = 1 }, party, L1.combat)
			local crowd = Combat.CrowdWave(village, wave, party, false, L1.combat)
			local same = camp.total == crowd.total and #camp.groups == #crowd.groups and camp.boss == crowd.boss and camp.bossHpMult == crowd.bossHpMult and camp.hpScale == crowd.hpScale and camp.plateScale == crowd.plateScale and camp.damageScale == crowd.damageScale and camp.regenShare == crowd.regenShare and camp.rewardMult == crowd.rewardMult and crowd.wave == wave
			for index, group in crowd.groups do
				local other = camp.groups[index]
				same = same and other ~= nil and other.kind == group.kind and other.count == group.count
			end
			if not same and shown == "" then
				shown = `wave {wave}, party {party}`
			end
			allSame = allSame and same
		end
	end
	check(allSame, `all ten waves, solo and in a party of three: groups, counts, boss, every scale ({shown})`)
	local spec = Combat.CrowdWave(village, 1, 1, false, L1.combat)
	local rewardsSame = true
	for kind in block.rewards do
		local cash, materials = Combat.CampReward(level.crowd.rewards, kind, spec)
		local wasCash, wasMaterials = Combat.CrowdReward(village, kind, spec)
		rewardsSame = rewardsSame and cash == wasCash and materials == wasMaterials
	end
	local nothing, none = Combat.CampReward(level.crowd.rewards, "nobody", spec)
	check(rewardsSame and nothing == 0 and none == 0, "CampReward is CrowdReward for every kind, and 0 for a kind with no price")
	check(Combat.BurstSeconds(45, 6, 1.5) == Combat.BurstInterval(village, 6, 1.5, false, L1.combat) and Combat.BurstSeconds(45, 0, 1) == 45 and Combat.BurstSeconds(45, 6, 0) == 45, "BurstSeconds is BurstInterval without Overdrive, and the whole target with no burst or no tempo")
	local overdrive = Combat.CrowdWave(village, 1, 1, true, L1.combat)
	check(overdrive.hpScale == block.hpScale * L1.combat.overdrive.hpMult and overdrive.rewardMult == L1.combat.overdrive.rewardMult, "(CrowdWave still takes Overdrive, for the simulator's old assertions)")

	print(" Combat: minDifficulty and countMult")
	local waveDef = { groups = { { kind = "fodder", count = 8 }, { kind = "armoured", count = 3, minDifficulty = "hard" }, { kind = "slinger", count = 1, minDifficulty = "nightmare" } } }
	local function field(rank: number, countMult: number, party: number?): string
		local scales = { hpScale = 1, damageScale = 1, plateScale = 1, countMult = countMult, rewardMult = 2 }
		local out = {}
		for _, group in Combat.CampWave(waveDef, 0.07, scales, rank, L1.ranks, party or 1, L1.combat).groups do
			table.insert(out, `{group.kind} {group.count}`)
		end
		return table.concat(out, ", ")
	end
	check(field(1, 1) == "fodder 8", `on Normal a group that asks for Hard is not fielded ({field(1, 1)})`)
	check(field(2, 1) == "fodder 8, armoured 3" and field(3, 1) == "fodder 8, armoured 3", `on Hard and above it is ({field(2, 1)}); a minDifficulty that is no difficulty fields nothing`)
	check(field(2, 1.25) == "fodder 10, armoured 4" and field(2, 1.5) == "fodder 12, armoured 5", `countMult rounds to the nearest body: 3 x 1.25 = 3.75 -> 4, 3 x 1.5 = 4.5 -> 5 ({field(2, 1.25)}; {field(2, 1.5)})`)
	check(field(2, 0.1) == "fodder 1, armoured 0", `and may round a group to nobody ({field(2, 0.1)})`)
	local extra = L1.combat.coop.countPerExtraPlayer
	check(field(1, 1.25, 3) == `fodder {math.round(8 * (1 + extra * 2) * 1.25)}`, `party size and countMult multiply before the one rounding ({field(1, 1.25, 3)})`)
	local scaled = Combat.CampWave(waveDef, 0.07, { hpScale = 5, damageScale = 1.8, plateScale = 2, countMult = 1, rewardMult = 2 }, 2, L1.ranks, 1, L1.combat)
	check(scaled.hpScale == 5 and scaled.damageScale == 1.8 and scaled.plateScale == 2 and scaled.rewardMult == 2 and scaled.regenShare == 0.07 and scaled.wave == 0 and scaled.total == 11, "the spec carries the difficulty's scales, and counts its total")
end
L1.resolveTests()

function L1.planTests(): ()
	print(" Plan")
	local Flow = L1.Flow
	local plan = L1.plan()
	local a = plan.stages[2]
	local b = plan.stages[4]
	local c = plan.stages[6]
	check(#plan.stages == 6 and plan.camps == 3 and plan.levelId == "road" and plan.difficulty == "normal" and plan.killY == -60 and L1.same(plan.start, vec(0, 0, 0)), "six stages, three camps, the start and the kill height of the layout")
	check(plan.stages[1].kind == "travel" and plan.stages[1].zone == nil and plan.stages[1].waves == 0, "a travel stage has no zone and no wave")
	check(a.zone.rect.x == 0 and a.zone.rect.z == 100 and a.zone.rect.hx == 30 and a.zone.rect.hz == 30 and a.zone.floorY == 0, "a camp's rectangle is its floor")
	check(a.zone.trigger.hx == 26 and a.zone.trigger.hz == 26 and a.zone.trigger.x == 0 and a.zone.trigger.z == 100, "its trigger is the floor inset by triggerInset")
	check(L1.same(b.zone.entry, vec(100, 12, 257)) and L1.same(b.zone.exit, vec(100, 12, 343)) and #b.zone.spawns == 4 and b.zone.spawns[1].Y == 12 and b.zone.floorY == 12, "entry, exit and spawn points are feet on the camp's own floor (12)")
	check(a.waves == 2 and a.breatherSeconds == 3 and a.maxAlive == 16 and a.targetWaveSeconds == 20 and a.merge == false and a.bankEachWave == false, "a camp carries its waves, its breather, its cap and its pace")
	check(b.maxAlive == 40 and b.breatherSeconds == nil, "a stage with no cap of its own takes the level's")
	check(c.boss[2] == true and c.boss[1] == nil and a.boss[1] == nil, "boss[wave] marks the waves with a boss")
	check(L1.plan(nil, nil, "brutal") == nil, "a difficulty the level lacks: no plan")
	local stray = L1.level()
	stray.stages[4].zone = "Z"
	check(L1.plan(stray) == nil, "a camp stage whose zone the layout lacks: no plan")
	check(a.zone.inner.hx == 28 and a.zone.inner.hz == 28 and a.zone.inner.x == 0 and a.zone.inner.z == 100, "its `inner` rectangle is the floor inset by closeInset")
	local tight = L1.layout()
	tight.camps[1].entry = { x = 0, z = 71 }
	local refused, why = L1.plan(nil, tight)
	check(refused == nil and why ~= nil and string.find(why, "closeInset", 1, true) ~= nil, "a camp whose entry lies within closeInset of the floor's edge is refused, by name: the close would move a fighter onto a place it must then move them from")
	tight.camps[1].entry = { x = 0, z = 72 }
	check(L1.plan(nil, tight) ~= nil, "(an entry exactly closeInset inside is allowed)")
	local _nothing, noDifficulty = L1.plan(nil, nil, "brutal")
	check(noDifficulty ~= nil, "(every refusal says why)")
	local start = Flow.Begin(plan)
	check(start.stage == 1 and start.step == "travel" and start.cleared == 0 and start.lastCleared == 0 and start.ended == nil, "a level that opens with a road begins travelling")

	print(" Validate")
	local function problems(level: any?, layout: any?): { string }
		return Flow.Validate(level or L1.level(), layout or L1.layout(), L1.kinds, L1.ranks)
	end
	local good = problems()
	check(#good == 0, `a good level on a good layout has no problem ({good[1] or "none"})`)
	local level = L1.level()
	table.remove(level.stages, 3)
	check(L1.has(problems(level), "take turns"), "two camps in a row: travel and camp take turns")
	level = L1.level()
	table.insert(level.stages, { kind = "travel", name = "Home" })
	check(L1.has(problems(level), "last stage is not a camp"), "a level that ends on a road")
	level = L1.level()
	level.stages[1].kind = "swim"
	check(L1.has(problems(level), "neither travel nor camp"), "a stage of an unknown kind")
	level = L1.level()
	level.stages = { level.stages[2] }
	check(#problems(level) == 0, "(a level of one camp is legal)")
	level = L1.level()
	level.stages[2].zone = "Z"
	check(L1.has(problems(level), "which the layout lacks"), "a camp that names a zone the layout lacks")
	level = L1.level()
	level.stages[4].waves = {}
	check(L1.has(problems(level), "has no wave"), "a camp with no wave")
	local layout = L1.layout()
	layout.camps[1].spawns = {}
	check(L1.has(problems(nil, layout), "has no spawn point"), "a camp with no spawn point")
	layout = L1.layout()
	layout.barrier = nil
	check(L1.has(problems(nil, layout), "has no barrier"), "a layout with no barrier")
	layout = L1.layout()
	layout.camps[1].spawns[2] = { x = 31, z = 100 }
	check(L1.has(problems(nil, layout), "spawn point 2 lies off the floor"), "a spawn point off the floor")
	layout = L1.layout()
	layout.camps[2].entry = { x = 100, z = 252 }
	check(L1.has(problems(nil, layout), "the entry lies off the floor"), "an entry off the floor")
	layout = L1.layout()
	layout.camps[3].exit = { x = 41, z = 520 }
	check(L1.has(problems(nil, layout), "the exit lies off the floor"), "an exit off the floor")
	level = L1.level()
	level.stages[6].waves[2].boss.at = { 0, 37 }
	check(L1.has(problems(level), "the boss's place lies off the floor"), "a boss placed nearer the edge than its radius (37 of 40, radius 4)")
	level.stages[6].waves[2].boss.at = { 0, 36 }
	check(#problems(level) == 0, "(36 of 40 is on it)")
	level = L1.level()
	level.stages[2].waves[1].groups[1].kind = "ghost"
	check(L1.has(problems(level), 'the unknown kind "ghost"'), "a group of a kind ProvingGrounds.json lacks")
	level = L1.level()
	level.stages[2].waves[1].groups[1].kind = "stray"
	check(L1.has(problems(level), 'fields "stray", which rewards does not price'), "a group of a kind the rewards do not price")
	level = L1.level()
	level.stages[6].waves[2].boss.kind = "ghost"
	check(L1.has(problems(level), "boss names the unknown kind"), "a boss of an unknown kind")
	level = L1.level()
	level.crowd.eliteKind = "stray"
	check(L1.has(problems(level), 'eliteKind fields "stray"'), "an eliteKind the rewards do not price")
	level = L1.level()
	level.stages[2].waves[2].groups[3].minDifficulty = "nightmare"
	check(L1.has(problems(level), 'minDifficulty "nightmare" is no difficulty'), "a minDifficulty that is no difficulty")
	layout = L1.layout()
	layout.camps[3].z = 990
	check(L1.has(problems(nil, layout), "beyond 1000 studs"), "a camp beyond 1,000 studs of the origin (the wire's reach)")
	layout = L1.layout()
	layout.killY = -451
	check(L1.has(problems(nil, layout), "killY -451 is under -450"), "a kill height under -450")
	layout.killY = -450
	check(#problems(nil, layout) == 0, "(-450 itself is allowed)")

	print(" the Village arena as a level, through both adapters")
	local arenaFile = { version = 1, id = "raiderArena", name = "Raider Arena", layout = "RaiderArena", mission = "village", recommendedTier = 2 }
	local arenaLevel = Flow.Resolve(arenaFile, L1.village, 1800)
	local arenaLayout = L1.Geo.FromArena(L1W.village(), -8)
	local arenaProblems = Flow.Validate(arenaLevel, arenaLayout, config.crowd.kinds, L1.ranks)
	check(#arenaProblems == 0, `the real Village mission on the Village arena validates ({arenaProblems[1] or "none"})`)
	local arenaPlan = Flow.Plan(arenaLevel, arenaLayout, "normal", L1.rules, L1.Geo.Bounds(arenaLayout))
	local camp = arenaPlan.stages[1]
	check(#arenaPlan.stages == 1 and arenaPlan.camps == 1 and camp.waves == 10 and camp.boss[5] == true and camp.boss[10] == true and camp.merge and camp.bankEachWave and camp.maxAlive == L1.village.crowd.maxAlive, "its plan: one camp of ten waves, bosses at 5 and 10, the block's cap")
	check(camp.zone.rect.hx == 55 and camp.zone.rect.x == 0 and camp.zone.floorY == 0 and #camp.zone.spawns == 8 and L1.same(arenaPlan.start, vec(0, 0, 0)), "at the world origin, 110 x 110, eight spawn points: the arena's numbers do not change")
	check(Flow.Begin(arenaPlan).step == "armed" and Flow.Plan(arenaLevel, arenaLayout, "hard", L1.rules, L1.bounds) == nil, "it begins armed (no road), and has no Hard")
end
L1.planTests()

function L1.walkTests(): ()
	print(" a three-camp walk-through")
	local Flow = L1.Flow
	local plan = L1.plan()
	local state = Flow.Begin(plan)
	local function fresh(): any
		return Flow.Begin(plan)
	end
	check(#L1.advance(plan, fresh(), { roots = { vec(0, 3, 0) } }) == 0, "on the road, far from every camp: nothing")
	check(#L1.advance(plan, fresh(), { roots = {} }) == 0, "nobody anywhere: nothing triggers")
	check(#L1.advance(plan, fresh(), { roots = { vec(0, 3, 73) } }) == 0, "on camp A's floor but outside its trigger (the inset band): nothing")
	check(#L1.advance(plan, fresh(), { roots = { vec(27, 3, 100) } }) == 0, "(the band, on the other axis)")
	check(#L1.advance(plan, fresh(), { roots = { vec(0, 30.5, 100) } }) == 0, "over the trigger, above triggerHeight: nothing")
	check(L1.names(L1.advance(plan, fresh(), { roots = { vec(0, 30, 100) } })) == "gate", "(at triggerHeight exactly: it triggers)")
	check(#L1.advance(plan, fresh(), { roots = { vec(0, -4.5, 100) } }) == 0 and L1.names(L1.advance(plan, fresh(), { roots = { vec(0, -4, 100) } })) == "gate", "more than 4 studs under the floor: nothing; 4 under: it triggers")
	check(#L1.advance(plan, fresh(), { roots = { L1.inCamp(plan, 4) } }) == 0 and #L1.advance(plan, fresh(), { roots = { L1.inCamp(plan, 6) } }) == 0, "inside a camp that is not the next (B, C): nothing")
	check(L1.names(L1.advance(plan, fresh(), { roots = { vec(0, 3, 0), L1.inCamp(plan, 2) } })) == "gate", "any one fighter inside is enough")

	local actions = L1.advance(plan, state, { now = 10, roots = { L1.inCamp(plan, 2) } })
	check(L1.names(actions) == "gate" and actions[1].stage == 2 and actions[1].at == 13, "walking into camp A: `gate`, due at now + gateSeconds")
	check(state.step == "gate" and state.stage == 2 and Flow.Phase(state, false) == "gate", "the run is in A's countdown")
	check(#L1.advance(plan, state, { now = 12.99, roots = {} }) == 0, "the countdown is not over a moment before gateSeconds")
	actions = L1.advance(plan, state, { now = 13, roots = {} })
	check(L1.names(actions) == "close wave" and actions[2].wave == 1 and actions[1].stage == 2, "at gateSeconds exactly the gates close and wave 1 comes with them, though everyone walked out again")
	check(state.step == "fight" and state.wave == 1 and Flow.Phase(state, false) == "wave" and Flow.Phase(state, true) == "boss", "the camp fights")

	check(#L1.advance(plan, state, { now = 14, spawningDone = false, fieldClear = false }) == 0, "no clear while a body is still queued")
	check(#L1.advance(plan, state, { now = 14, spawningDone = false, fieldClear = true }) == 0, "nor while a boss is still to place, whatever is alive")
	check(#L1.advance(plan, state, { now = 14, spawningDone = true, fieldClear = false, mergeOk = true }) == 0, "nor while a body lives (and this stage does not merge)")
	actions = L1.advance(plan, state, { now = 20 })
	check(L1.names(actions) == "clear boundary breather" and L1.find(actions, "breather").at == 23, "wave 1 of 2 cleared: `clear`, `boundary`, and the stage's own breather of 3 s; no bank")
	check(state.step == "breather" and Flow.Phase(state, false) == "breather", "the camp rests")
	check(#L1.advance(plan, state, { now = 22.9 }) == 0, "the breather is not over early")
	actions = L1.advance(plan, state, { now = 23 })
	check(L1.names(actions) == "wave" and actions[1].wave == 2 and state.step == "fight" and state.wave == 2, "then wave 2")
	actions = L1.advance(plan, state, { now = 40 })
	local bank = L1.find(actions, "bank")
	check(L1.names(actions) == "clear bank boundary open travel", `the camp's last wave cleared: clear, bank, boundary, open, travel, in that order ({L1.names(actions)})`)
	check(bank ~= nil and bank.wave == 2 and bank.count == 2 and bank.stage == 2, "the checkpoint banks both waves of the camp")
	check(state.stage == 3 and state.step == "travel" and state.cleared == 1 and state.lastCleared == 2 and Flow.Phase(state, false) == "travel", "one camp cleared; on the road again")

	check(#L1.advance(plan, state, { now = 41, roots = { L1.inCamp(plan, 2) } }) == 0, "walking back into the cleared camp triggers nothing")
	check(#L1.advance(plan, state, { now = 41, roots = { L1.inCamp(plan, 6) } }) == 0, "nor does running ahead to C")
	actions = L1.advance(plan, state, { now = 50, roots = { L1.inCamp(plan, 4) } })
	check(L1.names(actions) == "gate" and actions[1].stage == 4 and state.stage == 4, "camp B triggers (a floor at height 12, a root at 15)")
	actions = L1.advance(plan, state, { now = 53 })
	check(L1.names(actions) == "close wave", "B closes")
	actions = L1.advance(plan, state, { now = 70 })
	bank = L1.find(actions, "bank")
	check(L1.names(actions) == "clear bank boundary open travel" and bank.count == 1 and state.cleared == 2 and state.lastCleared == 4, "a camp of one wave: its clear is its checkpoint")

	L1.advance(plan, state, { now = 80, roots = { L1.inCamp(plan, 6) } })
	L1.advance(plan, state, { now = 83 })
	actions = L1.advance(plan, state, { now = 90, breatherSeconds = 7.5 })
	check(L1.names(actions) == "clear boundary breather" and L1.find(actions, "breather").at == 97.5, "C names no breather: the director's (7.5 s here)")
	actions = L1.advance(plan, state, { now = 97.5 })
	check(L1.names(actions) == "wave" and actions[1].wave == 2, "C's boss wave")
	check(#L1.advance(plan, state, { now = 98, spawningDone = false, fieldClear = true }) == 0, "the boss is still to place: no clear")
	check(#L1.advance(plan, state, { now = 99, spawningDone = true, fieldClear = false, mergeOk = true }) == 0, "the boss lives: no clear")
	actions = L1.advance(plan, state, { now = 160 })
	check(L1.names(actions) == "clear bank boundary open end", `the last camp's clear ends the run: clear, bank, boundary, open, end ({L1.names(actions)})`)
	check(L1.find(actions, "end").reason == "cleared" and state.step == "over" and state.ended == "cleared" and state.cleared == 3 and Flow.Phase(state, false) == "summary", "the run is over, cleared, three camps of three")
	check(#L1.advance(plan, state, { now = 161 }) == 0 and #L1.advance(plan, state, { now = 162, runCap = true, fallen = "down", fieldClear = false }) == 0, "after that nothing happens any more")
end
L1.walkTests()

function L1.waveTests(): ()
	print(" waves in a camp: banking, breathers, merges")
	local Flow = L1.Flow
	local level = L1.level()
	level.stages[2].bankEachWave = true
	local plan = L1.plan(level)
	local state = L1.toFight(plan, 2, 0)
	local actions = L1.advance(plan, state, { now = 30 })
	local bank = L1.find(actions, "bank")
	check(L1.names(actions) == "clear bank boundary breather" and bank.count == 1 and bank.wave == 1, "with bankEachWave a wave clear banks that wave")
	L1.advance(plan, state, { now = state.breatherUntil })
	actions = L1.advance(plan, state, { now = 60 })
	check(L1.names(actions) == "clear bank boundary open travel" and L1.find(actions, "bank").count == 1, "and the camp's clear banks only the last one")

	level = L1.level()
	level.stages[2].merge = true
	level.stages[2].bankEachWave = true
	table.insert(level.stages[2].waves, { groups = { { kind = "fodder", count = 4 } } })
	plan = L1.plan(level)
	state = L1.toFight(plan, 2, 0)
	check(#L1.advance(plan, state, { now = 20, fieldClear = false, mergeOk = false }) == 0, "a merging stage with the director unconvinced: nothing")
	check(#L1.advance(plan, state, { now = 20, fieldClear = false, spawningDone = false, mergeOk = true }) == 0, "no merge while this wave is still spawning")
	actions = L1.advance(plan, state, { now = 21, fieldClear = false, mergeOk = true })
	check(L1.names(actions) == "wave" and actions[1].wave == 2 and actions[1].merged == true and state.wave == 2 and state.step == "fight", "the director folds wave 2 in on top of wave 1: `wave` 2, merged")
	actions = L1.advance(plan, state, { now = 30 })
	check(L1.names(actions) == "clear bank boundary breather" and L1.find(actions, "bank").count == 2, "the merged pair clears at once, and its bank covers both waves")
	L1.advance(plan, state, { now = state.breatherUntil })
	check(state.wave == 3 and #L1.advance(plan, state, { now = 50, fieldClear = false, mergeOk = true }) == 0, "the last wave has nothing to fold in")

	plan = L1.plan()
	state = L1.toFight(plan, 2, 0)
	check(#L1.advance(plan, state, { now = 20, fieldClear = false, mergeOk = true }) == 0 and state.wave == 1, "a stage that does not merge never merges, whatever the director says")

	level = L1.level()
	level.stages[6].merge = true
	plan = L1.plan(level)
	state = L1.toFight(plan, 6, 0)
	check(state.wave == 1 and #L1.advance(plan, state, { now = 20, fieldClear = false, mergeOk = true }) == 0, "never INTO a boss wave (C's wave 2)")
	level = L1.level()
	level.stages[6].merge = true
	level.stages[6].waves = { level.stages[6].waves[2], level.stages[6].waves[1] }
	plan = L1.plan(level)
	state = L1.toFight(plan, 6, 0)
	check(plan.stages[6].boss[1] == true and #L1.advance(plan, state, { now = 20, fieldClear = false, mergeOk = true }) == 0, "never OUT OF a boss wave")

	print(" the arena plays as at P5: ten waves, a bank at each, the director's breathers and merges")
	local Geo = L1.Geo
	local arenaLevel = Flow.Resolve({ version = 1, id = "raiderArena", name = "Raider Arena", layout = "RaiderArena", mission = "village" }, L1.village, 1800)
	local arenaLayout = Geo.FromArena(L1W.village(), -8)
	plan = Flow.Plan(arenaLevel, arenaLayout, "normal", L1.rules, Geo.Bounds(arenaLayout))
	state = Flow.Begin(plan)
	actions = L1.advance(plan, state, { now = 0, roots = { vec(0, 3, 0) } })
	check(L1.names(actions) == "gate", "the party starts on the pad, inside the trigger: the countdown begins at once")
	actions = L1.advance(plan, state, { now = 3 })
	check(L1.names(actions) == "close wave", "then wave 1")
	local banks = 0
	local order = {}
	local now = 3
	local merges = 0
	for _ = 1, 60 do
		if state.step == "over" then
			break
		end
		now += 10
		if state.step == "fight" then
			-- The director is always convinced here: a merge happens wherever one is allowed.
			local folded = L1.advance(plan, state, { now = now, fieldClear = false, mergeOk = true })
			if #folded > 0 then
				merges += 1
				table.insert(order, `{state.wave - 1}+{state.wave}`)
			end
			local cleared = L1.advance(plan, state, { now = now + 1, breatherSeconds = 6 })
			local banked = L1.find(cleared, "bank")
			if banked ~= nil then
				banks += 1
			end
			if L1.find(cleared, "breather") ~= nil and L1.find(cleared, "breather").at ~= now + 7 then
				banks = -100
			end
		else
			L1.advance(plan, state, { now = state.breatherUntil })
		end
	end
	check(state.step == "over" and state.ended == "cleared" and state.cleared == 1, "it ends cleared after wave 10")
	check(table.concat(order, " ") == "1+2 3+4 6+7 8+9", `with a director that always says yes, waves merge in pairs and never round the bosses of 5 and 10 ({table.concat(order, " ")})`)
	check(banks == 6 and merges == 4, `every clear banks (six clears: four pairs, wave 5, wave 10), each after the director's breather ({banks})`)
end
L1.waveTests()

function L1.endTests(): ()
	print(" what ends a run")
	local Flow = L1.Flow
	local plan = L1.plan()
	local function at(step: string): any
		local state = L1.toFight(plan, 2, 0)
		if step == "travel" then
			return Flow.Begin(plan)
		elseif step == "gate" then
			state = Flow.Begin(plan)
			L1.advance(plan, state, { now = 0, roots = { L1.inCamp(plan, 2) } })
		elseif step == "breather" then
			L1.advance(plan, state, { now = 10 })
		end
		return state
	end
	for _, step in { "gate", "fight", "breather" } do
		local state = at(step)
		local actions = L1.advance(plan, state, { now = 1, fallen = "down", fieldClear = false, spawningDone = false })
		check(state.step == "over" and L1.names(actions) == "end" and actions[1].reason == "down" and state.ended == "down", `the fallen end the run in {step}, with their reason`)
	end
	local wiped = at("fight")
	check(L1.advance(plan, wiped, { now = 1, fallen = "wipe", fieldClear = false })[1].reason == "wipe", "(a wipe ends it as a wipe)")

	local state = at("fight")
	local actions = L1.advance(plan, state, { now = 5, fallen = "down", fieldClear = true })
	check(L1.names(actions) == "clear boundary breather" and state.step == "breather", "a clear field wins: the fallen do not end a wave that is beaten; its clear runs instead")
	state = L1.toFight(plan, 6, 0)
	L1.advance(plan, state, { now = 200 })
	L1.advance(plan, state, { now = state.breatherUntil })
	actions = L1.advance(plan, state, { now = 300, fallen = "down", fieldClear = true })
	check(L1.find(actions, "end").reason == "cleared" and L1.find(actions, "bank") ~= nil, "on the last wave of the last camp the run ends cleared, and banks")
	check(#L1.advance(plan, at("travel"), { now = 5, fallen = "wipe", fieldClear = true }) == 0, "on the road the field is always clear: a death there costs a respawn, not the run")
	state = at("gate")
	check(#L1.advance(plan, state, { now = 1, fallen = "down", fieldClear = true }) == 0 and state.step == "gate", "nor does one in a countdown, with the crowd not yet on the floor")

	for _, step in { "travel", "gate", "fight", "breather" } do
		local capped = at(step)
		local out = L1.advance(plan, capped, { now = 1, runCap = true, roots = { L1.inCamp(plan, 2) } })
		check(L1.names(out) == "end" and out[1].reason == "runCap" and capped.step == "over", `the run cap ends it from {step}`)
	end
	state = at("fight")
	actions = L1.advance(plan, state, { now = 5, runCap = true, fallen = "down", fieldClear = true })
	check(L1.names(actions) == "end" and actions[1].reason == "runCap", "the cap wins over everything else, a clear included: nothing is banked")

	state = at("fight")
	actions = Flow.Finish(plan, state, "abandoned")
	check(L1.names(actions) == "end" and actions[1].reason == "abandoned" and state.step == "over" and state.ended == "abandoned", "Finish: the run ends abandoned")
	check(#Flow.Finish(plan, state, "abandoned") == 0 and state.ended == "abandoned", "and only once")
	check(#Flow.Skip(plan, state, "stage", 9, L1.rules) == 0 and #Flow.Skip(plan, state, "boss", 9, L1.rules) == 0 and #Flow.Force(plan, state, 2) == 0, "no skip and no lever acts on a run that is over")
end
L1.endTests()

function L1.bodyTests(): ()
	print(" SafePoint")
	local Flow = L1.Flow
	local plan = L1.plan()
	local a = plan.stages[2].zone
	local b = plan.stages[4].zone
	local c = plan.stages[6].zone
	local state = Flow.Begin(plan)
	check(L1.same(Flow.SafePoint(plan, state), plan.start), "on the first road: the level's start")
	L1.advance(plan, state, { now = 0, roots = { L1.inCamp(plan, 2) } })
	check(L1.same(Flow.SafePoint(plan, state), a.entry), "in a camp's countdown: its entry")
	L1.advance(plan, state, { now = 3 })
	check(state.step == "fight" and L1.same(Flow.SafePoint(plan, state), a.entry), "in its fight: its entry")
	L1.advance(plan, state, { now = 10 })
	check(state.step == "breather" and L1.same(Flow.SafePoint(plan, state), a.entry), "between its waves: its entry")
	L1.advance(plan, state, { now = 13 })
	L1.advance(plan, state, { now = 20 })
	check(state.step == "travel" and L1.same(Flow.SafePoint(plan, state), a.exit), "on the road after it: its exit")
	L1.advance(plan, state, { now = 30, roots = { L1.inCamp(plan, 4) } })
	check(L1.same(Flow.SafePoint(plan, state), b.entry) and Flow.SafePoint(plan, state).Y == 12, "in the next camp's countdown: that camp's entry, on its own floor")
	state = L1.toFight(plan, 6, 0)
	L1.advance(plan, state, { now = 500 })
	L1.advance(plan, state, { now = state.breatherUntil })
	L1.advance(plan, state, { now = 600 })
	check(state.step == "over" and L1.same(Flow.SafePoint(plan, state), c.exit), "once the run is over: the exit of the last cleared camp")
	local abandoned = Flow.Begin(plan)
	Flow.Finish(plan, abandoned, "abandoned")
	check(L1.same(Flow.SafePoint(plan, abandoned), plan.start), "(abandoned on the first road: the start)")

	print(" IsOut")
	local function out(given: any, x: number, y: number, z: number): boolean
		return Flow.IsOut(plan, given, vec(x, y, z), L1.rescue, L1.rules.boxMargin)
	end
	local road = Flow.Begin(plan)
	check(not out(road, 0, 3, 0) and not out(road, 189, 3, 100) and out(road, 191, 3, 100) and out(road, -91, 3, 100), "on the road the box is the level's bounds plus boxMargin (150 + 40)")
	check(not out(road, 0, 3, 599) and out(road, 0, 3, 601) and out(road, 0, 3, -61), "on Z too")
	check(not out(road, 0, -59, 100) and out(road, 0, -61, 100), "and the kill height is the layout's killY (-60)")
	local fight = L1.toFight(plan, 2, 0)
	check(not out(fight, 33, 3, 100) and out(fight, 35, 3, 100) and out(fight, 0, 3, 65) and not out(fight, 0, 3, 67), "while a camp is closed the box is its floor plus rescue.outside (30 + 4)")
	check(not out(fight, 0, -7, 100) and out(fight, 0, -9, 100), "and the kill height is its floor less rescue.below (0 - 8)")
	check(out(fight, 100, 15, 300) and not out(road, 100, 15, 300), "a body inside the level but outside the closed camp is out; on the road the same place is fine")
	local inB = L1.toFight(plan, 4, 0)
	check(out(inB, 100, 3, 300) and not out(inB, 100, 5, 300) and not out(road, 100, 3, 300), "the kill height follows the camp's own floor (12 - 8 = 4)")
	local resting = L1.toFight(plan, 2, 0)
	L1.advance(plan, resting, { now = 10 })
	check(resting.step == "breather" and out(resting, 35, 3, 100), "between its waves the camp is still closed")
	local counting = Flow.Begin(plan)
	L1.advance(plan, counting, { now = 0, roots = { L1.inCamp(plan, 2) } })
	check(counting.step == "gate" and not out(counting, 35, 3, 100) and out(counting, 191, 3, 100), "in the countdown the gates are still open: the level's box")
	check(Flow.OutOfBox(L1.bounds, -60, vec(0, -61, 0), 40) and not Flow.OutOfBox(L1.bounds, -60, vec(189, 0, -59), 40) and Flow.OutOfBox(L1.bounds, -60, vec(0, 0, -61), 40), "OutOfBox (the lobby is judged with it): under the kill height, or past the margin")

	print(" MustEnter: who the close brings inside")
	check(Flow.MustEnter(a, vec(0, 3, 60)) and Flow.MustEnter(a, vec(0, 3, 69.5)), "a body on the road, or in the gate gap, is moved to the entry")
	check(Flow.MustEnter(a, vec(0, 3, 71)), "so is one on the floor but only 1 stud inside the edge, at the gate: the gate would close on it")
	check(not Flow.MustEnter(a, vec(0, 3, 73)) and not Flow.MustEnter(a, vec(0, 3, 100)), "one 3 studs inside, or in the middle, stays where it is")
	check(Flow.MustEnter(a, vec(29, 3, 100)) and not Flow.MustEnter(a, vec(-27, 3, 100)) and Flow.MustEnter(a, vec(0, 3, 129)), "the same on every side")
	check(not Flow.MustEnter(a, a.entry) and not Flow.MustEnter(b, b.entry) and not Flow.MustEnter(c, c.entry), "the entry itself is inside: whoever is moved there is not moved again")
	check(Flow.MustEnter(b, vec(0, 3, 100)), "(a body in another camp is outside this one)")

	print(" StartPoint, BurstPoint, BossPoint")
	local seen: { [string]: boolean } = {}
	local distinct = 0
	for index = 1, 9 do
		local point = Flow.StartPoint(plan, index, 4)
		local key = `{point.X},{point.Z}`
		if not seen[key] and point.Y == 0 and math.abs(point.X) <= 4 and math.abs(point.Z) <= 4 then
			seen[key] = true
			distinct += 1
		end
	end
	check(L1.same(Flow.StartPoint(plan, 1, 4), plan.start) and L1.same(Flow.StartPoint(plan, 2, 4), vec(4, 0, 0)), "the first member starts on the start point, the second `spacing` beside it")
	check(distinct == 9 and L1.same(Flow.StartPoint(plan, 10, 4), plan.start), "nine members stand on nine places within one spacing; the tenth takes the ring again")

	local arena = { id = "arena", floorY = 0, rect = { x = 0, z = 0, hx = 55, hz = 55 }, inner = { x = 0, z = 0, hx = 53, hz = 53 }, trigger = { x = 0, z = 0, hx = 51, hz = 51 }, entry = vec(0, 0, 0), exit = vec(0, 0, 0), spawns = {} }
	local first = Flow.BurstPoint(arena, vec(0, 0, -46), 12, 0, 3.5)
	local second = Flow.BurstPoint(arena, vec(0, 0, -46), 12, 1, 3.5)
	local nextRow = Flow.BurstPoint(arena, vec(0, 0, -46), 12, 4, 3.5)
	check(L1.same(first, vec(5.25, 0, -46)) and L1.same(second, vec(1.75, 0, -46)), `a burst of 12 is four across, centred on its spawn point ({first.X}, {second.X})`)
	check(L1.same(nextRow, vec(5.25, 0, -42.5)), "its next row steps toward the centre: these are P5's arena numbers")
	local east = Flow.BurstPoint(b, vec(140, 12, 300), 8, 3, 3.5)
	local north = Flow.BurstPoint(b, vec(100, 12, 260), 8, 3, 3.5)
	check(near(east.X, 136.5) and near(east.Y, 12) and near(north.Z, 263.5) and near(north.Y, 12), `off the origin too: rows step toward the camp's own centre, on its own floor ({east.X}, {north.Z})`)
	local middle = Flow.BurstPoint(b, vec(100, 12, 300), 1, 0, 3.5)
	check(L1.same(middle, vec(100, 12, 300)), "(a spawn point on the centre itself is still a place)")
	check(L1.same(Flow.BossPoint(b, { 5, -10 }), vec(105, 12, 290)) and L1.same(Flow.BossPoint(b, {}), vec(100, 12, 300)), "boss.at is { x, z } from the camp's centre, on its floor")
end
L1.bodyTests()

function L1.skipTests(): ()
	print(" Skip (Studio): stage")
	local Flow = L1.Flow
	local plan = L1.plan()
	local rules = L1.rules
	local state = Flow.Begin(plan)
	local actions = Flow.Skip(plan, state, "stage", 5, rules)
	check(L1.names(actions) == "move gate" and actions[1].stage == 2 and actions[2].at == 8 and state.step == "gate" and state.stage == 2, "on the road: the party is moved to the next camp and its countdown starts")
	actions = Flow.Skip(plan, state, "stage", 6, rules)
	check(L1.names(actions) == "close wave" and actions[2].wave == 1 and state.step == "fight", "in a countdown: the gates close now")
	actions = Flow.Skip(plan, state, "stage", 7, rules)
	check(L1.names(actions) == "drop boundary open travel" and state.stage == 3 and state.step == "travel" and state.cleared == 1 and state.lastCleared == 2, "in a camp: it is dropped and counts as cleared, with no bank")
	state = L1.toFight(plan, 2, 0)
	L1.advance(plan, state, { now = 10 })
	check(state.step == "breather" and L1.names(Flow.Skip(plan, state, "stage", 11, rules)) == "drop boundary open travel", "between a camp's waves: the same")
	state = L1.toFight(plan, 6, 0)
	actions = Flow.Skip(plan, state, "stage", 7, rules)
	check(L1.names(actions) == "drop boundary open end" and L1.find(actions, "end").reason == "cleared" and state.step == "over", "in the last camp: the run ends cleared, and banks nothing")
	check(#Flow.Skip(plan, Flow.Begin(plan), "sideways", 0, rules) == 0, "an unknown skip does nothing")

	print(" Skip (Studio): boss")
	state = Flow.Begin(plan)
	actions = Flow.Skip(plan, state, "boss", 5, rules)
	check(L1.names(actions) == "open open move gate" and actions[1].stage == 2 and actions[2].stage == 4 and actions[3].stage == 6 and actions[4].stage == 6, `from the first road: the camps between count as cleared, the party is moved to the boss's camp ({L1.names(actions)})`)
	check(state.stage == 6 and state.step == "gate" and state.cleared == 2 and state.lastCleared == 4 and state.firstWave == 2, "and its countdown starts, to open on the boss's wave")
	actions = L1.advance(plan, state, { now = 8 })
	check(L1.names(actions) == "close wave" and actions[2].wave == 2 and state.wave == 2 and state.firstWave == 1, "the gates close on wave 2, the boss's")
	actions = L1.advance(plan, state, { now = 60 })
	check(L1.names(actions) == "clear bank boundary open end" and L1.find(actions, "bank").count == 1, "killing him banks his wave alone: nothing skipped is credited")
	state = L1.toFight(plan, 2, 0)
	actions = Flow.Skip(plan, state, "boss", 5, rules)
	check(L1.names(actions) == "drop open open move gate" and actions[2].stage == 2 and actions[3].stage == 4 and state.cleared == 2, "from a live camp with no boss: it is dropped first, then the same")
	state = L1.toFight(plan, 6, 0)
	actions = Flow.Skip(plan, state, "boss", 5, rules)
	check(L1.names(actions) == "drop wave" and actions[2].wave == 2 and state.wave == 2 and state.step == "fight", "in the boss's own camp: the field is dropped and his wave starts")
	check(#Flow.Skip(plan, state, "boss", 6, rules) == 0 and state.wave == 2, "with no boss left: nothing")
	actions = L1.advance(plan, state, { now = 60 })
	check(L1.find(actions, "bank").count == 1, "(and the wave skipped over is not banked with his)")
	state = Flow.Begin(plan)
	Flow.Skip(plan, state, "boss", 5, rules)
	state = L1.toFight(plan, 4, 0)
	L1.advance(plan, state, { now = 30 })
	L1.advance(plan, state, { now = 40, roots = { L1.inCamp(plan, 6) } })
	actions = Flow.Skip(plan, state, "boss", 41, rules)
	check(state.step == "fight" and L1.names(actions) == "close wave" and actions[2].wave == 2, "in the countdown of the boss's camp: the gates close now, on his wave")

	local Geo = L1.Geo
	local arenaLevel = Flow.Resolve({ version = 1, id = "raiderArena", name = "Raider Arena", layout = "RaiderArena", mission = "village" }, L1.village, 1800)
	local arenaLayout = Geo.FromArena(L1W.village(), -8)
	local arena = Flow.Plan(arenaLevel, arenaLayout, "normal", rules, Geo.Bounds(arenaLayout))
	state = Flow.Begin(arena)
	actions = Flow.Skip(arena, state, "boss", 0, rules)
	check(L1.names(actions) == "move gate" and state.firstWave == 5 and state.step == "gate", "the arena, before its gates: B arms wave 5")
	actions = L1.advance(arena, state, { now = 3 })
	check(actions[2].wave == 5 and state.settled == 4, "it opens on wave 5, with waves 1 to 4 settled unpaid")
	actions = Flow.Skip(arena, state, "boss", 4, rules)
	check(L1.names(actions) == "drop wave" and actions[2].wave == 10 and state.settled == 9, "B again: wave 10 (P5's ForceWave)")
	check(#Flow.Skip(arena, state, "boss", 5, rules) == 0, "and then none is left")
	state = Flow.Begin(arena)
	actions = Flow.Skip(arena, state, "stage", 0, rules)
	check(L1.names(actions) == "move gate" and state.firstWave == 1, "N in the arena before its gates: the countdown")

	print(" Force (the wave lever)")
	state = L1.toFight(arena, 1, 0)
	actions = Flow.Force(arena, state, 7)
	check(L1.names(actions) == "drop wave" and actions[2].wave == 7 and state.wave == 7 and state.settled == 6 and state.step == "fight", "in the live camp: that wave at once, the ones before it settled unpaid")
	check(Flow.Force(arena, state, 99)[2].wave == 10 and Flow.Force(arena, state, 0)[2].wave == 1, "clamped to the camp's waves")
	check(#Flow.Force(arena, Flow.Begin(arena), 3) == 0 and #Flow.Force(plan, Flow.Begin(plan), 3) == 0, "outside a live camp it does nothing")
end
L1.skipTests()

function L1.mapTests(): ()
	print(" the map")
	local Flow = L1.Flow
	local map = {
		difficulties = { "normal", "hard", "brutal" },
		nodes = {
			{ id = "forestRoad", name = "Forest Road", level = "forestRoad" },
			{ id = "raiderArena", name = "Raider Arena", level = "raiderArena", from = "forestRoad" },
			{ id = "castle", name = "Castle", from = "forestRoad", requires = { node = "forestRoad" } },
			{ id = "keep", name = "Keep", level = "keep", requires = { node = "forestRoad" } },
			{ id = "vault", name = "Vault", level = "vault", requires = { stars = 2 } },
			{ id = "ruin", name = "Ruin", level = "ruin" },
		},
	}
	local built = { forestRoad = true, raiderArena = true, keep = true, vault = true }
	local none = {}
	local function node(leader: any, own: any, id: string): any
		return Flow.NodeState(map, built, leader, own, id)
	end
	local road = node(none, none, "forestRoad")
	check(road.open == true and road.reason == nil and #road.stars == 0 and road.id == "forestRoad", "a built node that asks for nothing is open")
	check(node(none, none, "raiderArena").open == true, "so is the arena, from the start")
	local starred = { forestRoad = { normal = true } }
	local castle = node(starred, starred, "castle")
	check(castle.open == false and castle.reason == "notBuilt", "a node with no level is not built, whatever else is true: notBuilt wins")
	check(node(starred, starred, "ruin").reason == "notBuilt", "so is one whose level has no file")
	local keep = node(none, starred, "keep")
	check(keep.open == false and keep.reason == "needsNode" and keep.needs == "Forest Road", "a node behind another is locked until the LEADER has a star there, and says which node by name")
	check(node(starred, none, "keep").open == true, "the leader's star opens it for a member who has none")
	local vault = node(starred, none, "vault")
	check(vault.open == false and vault.reason == "needsStars" and vault.needs == "2", "a node that asks for stars says how many")
	check(node({ forestRoad = { normal = true, hard = true } }, none, "vault").open == true and node({ forestRoad = { normal = true }, raiderArena = { normal = true } }, none, "vault").open == true, "two stars, on one level or two, open it")
	local mine = node(none, { forestRoad = { hard = true, normal = true } }, "forestRoad")
	check(table.concat(mine.stars, ",") == "normal,hard", `a node's stars are the receiver's own, in the map's order ({table.concat(mine.stars, ",")})`)
	check(node(none, none, "nowhere") == nil, "(no such node: nil)")

	local stars = {}
	check(Flow.Award(stars, "forestRoad", "hard") == true and stars.forestRoad.hard == true, "Award gives the star of the difficulty that was played")
	check(Flow.Award(stars, "forestRoad", "hard") == false, "and says it is new only once")
	check(stars.forestRoad.normal == nil and stars.forestRoad.brutal == nil and next(stars, "forestRoad") == nil, "no other difficulty and no other level gets one")

	local state = Flow.MapState(map, built, starred, { raiderArena = { normal = true } }, 42)
	local ids = {}
	for _, entry in state.nodes do
		table.insert(ids, entry.id)
	end
	check(state.kind == "map" and state.leaderUserId == 42 and table.concat(ids, ",") == "forestRoad,raiderArena,castle,keep,vault,ruin", "MapState lists every node in the config's order, with the leader's id")
	check(#state.nodes[1].stars == 0 and state.nodes[2].stars[1] == "normal" and state.nodes[4].open == true and state.nodes[5].open == false, "each with the receiver's own stars, and open by the leader's")
end
L1.mapTests()

function L1.crowdTests(): ()
	print(" CrowdService on a camp's floor (rulings 11 and 12)")
	fresh()
	check(Crowd.SetBounds(vec(100, 12, 300), vec(50, 200, 47)) == true, "with nobody alive the bounds move: a floor at height 12, off the origin")
	root.Position = vec(100, 15, 300)
	local standing = Crowd.Spawn("pawn", vec(110, 12, 290), "idle")
	local sunk = Crowd.Spawn("pawn", vec(90, 0, 310), "idle")
	local far = Crowd.Spawn("pawn", vec(400, 12, 600), "idle")
	step2(2)
	check(near(Crowd.Get(standing).position.Y, 12), "a body stands on the floor, at 12")
	check(near(Crowd.Get(sunk).position.Y, 12), "a spawn under the floor is lifted onto it")
	local held = Crowd.Get(far).position
	check(near(held.X, 150 - 1.3) and near(held.Z, 347 - 1.3), `the clamp holds the new rectangle ({held.X}, {held.Z})`)
	local entry = seen(standing)
	check(near(entry.position.X, 110, 1 / 16) and near(entry.position.Y, 12, 1 / 16) and near(entry.position.Z, 290, 1 / 16), `the snapshot decodes against the world origin, not the camp's centre ({entry.position.X}, {entry.position.Y}, {entry.position.Z})`)
	table.clear(struck)
	Vitals.ToggleGod(player)
	local fighter = Crowd.Spawn("fodder", vec(100, 12, 304), "fight")
	waitFor(fighter, "windup", 60)
	for _ = 1, 20 do
		if #struck > 0 then
			break
		end
		step2()
	end
	check(#struck > 0 and struck[1].floorY == 12, `a strike is judged from the camp's floor: floorY 12 ({if struck[1] ~= nil then struck[1].floorY else "no strike"})`)
	Vitals.ToggleGod(player)
	check(Crowd.SetBounds(vec(0, 0, 0), vec(100, 50, 100)) == false, "SetBounds is refused while a body is alive")
	step2()
	check(near(Crowd.Get(standing).position.Y, 12) and near(Crowd.Get(standing).position.X, 110), "and nothing moved: the bodies still stand on their floor")
	fresh()
	check(Crowd.SetBounds(vec(0, 0, 0), vec(100, 50, 100)) == true, "once the crowd is cleared the bounds move back")
	local home = Crowd.Spawn("pawn", vec(10, 0, 10), "idle")
	step2()
	check(near(Crowd.Get(home).position.Y, 0) and near(seen(home).position.X, 10, 1 / 16), "and the arena at the origin is as it was")
	fresh()
end
L1.crowdTests()

-- The real files ---------------------------------------------------------------------------------
-- Everything above runs on fixtures written for the cases. These run the same rules on the data
-- that ships, read the way WaveService.resolveLevel, WaveService.startLevel and LevelService read
-- it: the level files, their layouts, the missions, the map, the crowd kinds, Combat.json
-- `levels`. tools/check_levels.py passes the same files in Python and never meets these rules;
-- where the two disagree on a field, the owner's first Depart answers "unavailable".
-- run_harness.py injects the files (FIXTURES), bundles the arena a layout names, and asks
-- check_levels.py for its Part counts and its own reading of that arena (FIXTURES.gate).

L1.real = {
	map = FIXTURES.expeditions,
	levels = FIXTURES.levels,
	missions = FIXTURES.missions,
	layouts = FIXTURES.layouts,
	kinds = FIXTURES.proving.crowd.kinds,
	rules = FIXTURES.combat.levels,
	rescue = FIXTURES.combat.player.rescue,
	gate = FIXTURES.gate,
	-- A root's height over the feet in these cases.
	ROOT = 3,
	-- Every action WaveService.execute has a branch for.
	EXECUTED = { gate = true, close = true, wave = true, clear = true, bank = true, boundary = true, breather = true, open = true, travel = true, drop = true, move = true, ["end"] = true },
	-- The actions that do nothing in WaveService.execute when their stage has no zone.
	ZONED = { gate = true, close = true, open = true, move = true },
}

-- WaveService.difficultyRanks: the order of Expeditions.json `difficulties` is the rank.
function L1.real.ranks(): any
	local ranks = {}
	for index, name in L1.real.map.difficulties do
		ranks[name] = index
	end
	return ranks
end

-- WaveService.builtLevels: a node is built when a level file with its `level` id exists.
function L1.real.built(): any
	local built = {}
	for _, file in L1.real.levels do
		built[file.id] = true
	end
	return built
end

function L1.real.file(levelId: string): any
	for _, file in L1.real.levels do
		if file.id == levelId then
			return file
		end
	end
	return nil
end

-- A layout by its file's name; one that names an arena is read through LevelGeometry.FromArena
-- as WaveService does, the kill height its floor less player.rescue.below. nil and why.
function L1.real.layout(name: string): (any, string?)
	local layout = L1.real.layouts[name]
	if layout == nil then
		return nil, `no Layouts/Levels/{name}.json`
	end
	local arena = layout.arena
	if arena == nil then
		return layout, nil
	end
	if table.find(FIXTURES.arenas, arena) == nil then
		return nil, `no Layouts/Arenas/{arena}.luau`
	end
	return L1.Geo.FromArena(load("Arena_" .. arena), -L1.real.rescue.below), nil
end

-- WaveService.resolveLevel: the file, the mission it names, the level, its layout.
function L1.real.resolve(levelId: string): any
	local file = L1.real.file(levelId)
	if file == nil then
		return { why = "no level file" }
	end
	local mission = nil
	for _, candidate in L1.real.missions do
		if file.mission ~= nil and candidate.id == file.mission then
			mission = candidate
		end
	end
	local layout, why = L1.real.layout(file.layout)
	local read, level = pcall(L1.Flow.Resolve, file, mission, L1.combat.director.runCapSeconds)
	return { file = file, mission = mission, level = if read then level else nil, layout = layout, why = why }
end

-- LevelService.sizesOf: what a layout does not say and the config does.
function L1.real.sizes(): any
	local function size(value: any): any
		if value == nil then
			return nil
		end
		local sx, sy, sz = value[1], value[2], value[3]
		if sx ~= nil and sy ~= nil and sz ~= nil and sx > 0 and sy > 0 and sz > 0 then
			return { sx = sx, sy = sy, sz = sz }
		end
		return nil
	end
	return { fence = L1.real.rules.fenceThickness, checkpoint = size(L1.real.rules.checkpointSize), sign = size(L1.real.map.sign.size) }
end

-- LevelService.piecesOf: Pieces behind a pcall, so a key of the wrong type refuses the layout.
function L1.real.pieces(layout: any): (any, string?)
	local ok, pieces, refusal = pcall(L1.Geo.Pieces, layout, L1.real.sizes(), L1.real.rules.maxParts)
	if not ok then
		return nil, `the layout could not be read: {tostring(pieces)}`
	end
	return pieces, refusal
end

-- StageFlow.Plan as these cases ask it. WaveService calls it bare: a layout or a level file that
-- makes it throw gives the leader no answer at all, so a throw is reported here as a refusal.
function L1.real.plan(level: any, layout: any, difficulty: string, bounds: any): (any, string?)
	local ok, plan, why = pcall(L1.Flow.Plan, level, layout, difficulty, L1.real.rules, bounds)
	if not ok then
		return nil, `Plan threw: {tostring(plan)}`
	end
	return plan, why
end

-- The solid Part whose top face a body with its feet at `feet` stands on (nil = on nothing), and
-- the name of a solid Part that body would stand INSIDE (nil = none).
function L1.real.footing(pieces: { any }, feet: any): (any, string?)
	local under = nil
	local inside = nil
	for _, piece in pieces do
		local box = piece.box
		if not piece.collide or math.abs(feet.X - box.x) > box.sx / 2 or math.abs(feet.Z - box.z) > box.sz / 2 then
			continue
		end
		local top = box.y + box.sy / 2
		if math.abs(top - feet.Y) <= 1e-6 then
			under = piece
		elseif top > feet.Y and box.y - box.sy / 2 < feet.Y + L1.real.ROOT then
			inside = piece.name
		end
	end
	return under, inside
end

function L1.real.list(items: { string }): string
	return if #items > 0 then ": " .. table.concat(items, "; ") else ""
end

-- What a run of `level` must answer when every wave is beaten as it is fielded, read from its
-- stages alone: per camp its countdown, its close, every wave in turn with one bank at the last
-- (or one per wave in a stage that banks each), its opening; then the road, or the end.
function L1.real.script(level: any): string
	local out = {}
	for index, stage in level.stages do
		if stage.kind ~= "camp" then
			if index > 1 then
				table.insert(out, "travel")
			end
			continue
		end
		table.insert(out, "gate")
		table.insert(out, "close")
		local waves = #(stage.waves or {})
		for wave = 1, waves do
			table.insert(out, "wave" .. wave)
			table.insert(out, "clear")
			if wave == waves or stage.bankEachWave == true then
				table.insert(out, "bank")
			end
			table.insert(out, "boundary")
			if wave < waves then
				table.insert(out, "breather")
			end
		end
		table.insert(out, "open")
	end
	table.insert(out, "end")
	return table.concat(out, " ")
end

function L1.real.said(log: { any }): string
	local out = {}
	for _, action in log do
		table.insert(out, if action.kind == "wave" then "wave" .. tostring(action.wave) else action.kind)
	end
	return table.concat(out, " ")
end

-- One run through StageFlow alone, asked as WaveService's tick asks it. A party of four stands
-- where the run puts it (the start, then each cleared camp's exit), walks to the next camp's
-- entry, waits the countdown out and beats every wave the moment it is fielded. `merging`:
-- while a wave is up the director answers "merge" every time it is asked.
-- Returns `log` (every action Advance answered, in order, with the clock it was answered at),
-- the final `state`, `early` (camps that triggered before anybody walked), `held` (nothing
-- happened a moment before a countdown or a breather was over), `stuck` (why the walk stopped),
-- and `safe` / `unsafe`: every state's SafePoint, asked, and those that are no place for a body.
function L1.real.run(plan: any, pieces: any, merging: boolean): any
	local Flow = L1.Flow
	local real = L1.real
	local rules = real.rules
	local state = Flow.Begin(plan)
	local out: any = { log = {}, state = state, early = {}, held = true, stuck = nil, safe = 0, unsafe = {} }
	local now = 0
	local breather = L1.Combat.BreatherSeconds(1, L1.combat.director)
	local party = {}
	for member = 1, 4 do
		local feet = Flow.StartPoint(plan, member, rules.startSpacing)
		table.insert(party, vec(feet.X, feet.Y + real.ROOT, feet.Z))
	end
	local function ask(over: any): { any }
		over.now = now
		over.roots = party
		over.breatherSeconds = breather
		local actions = Flow.Advance(plan, state, L1.input(over), rules)
		for _, action in actions do
			action.now = now
			table.insert(out.log, action)
		end
		return actions
	end
	local function safe(): ()
		if state.step == "over" then
			return
		end
		out.safe += 1
		local at = Flow.SafePoint(plan, state)
		local bounds = plan.bounds
		local under, inside = nil, nil
		if pieces ~= nil then
			under, inside = real.footing(pieces, at)
		end
		local why = nil
		if at.X < bounds.minX or at.X > bounds.maxX or at.Z < bounds.minZ or at.Z > bounds.maxZ or at.Y > bounds.maxY then
			why = "outside the level's bounds"
		elseif at.Y <= plan.killY then
			why = "not above the kill height"
		elseif Flow.IsOut(plan, state, vec(at.X, at.Y + real.ROOT, at.Z), real.rescue, rules.boxMargin) then
			why = "where the rescue takes a body from"
		elseif pieces ~= nil and under == nil then
			why = "on nothing"
		elseif inside ~= nil then
			why = "inside " .. inside
		end
		if why ~= nil then
			table.insert(out.unsafe, `stage {state.stage} {state.step}: ({at.X}, {at.Y}, {at.Z}) is {why}`)
		end
	end
	safe()
	for _ = 1, 400 do
		local step = state.step
		if step == "over" then
			break
		end
		if step == "travel" or step == "armed" then
			local camp = if step == "armed" then state.stage else state.stage + 1
			local stage = plan.stages[camp]
			local zone = if stage ~= nil then stage.zone else nil
			if zone == nil then
				out.stuck = `stage {state.stage}: no camp follows`
				break
			end
			if state.lastCleared > 0 then
				local at = Flow.SafePoint(plan, state)
				party = { vec(at.X, at.Y + real.ROOT, at.Z) }
			end
			if #ask({}) > 0 then
				table.insert(out.early, camp)
			else
				party = { vec(zone.entry.X, zone.entry.Y + real.ROOT, zone.entry.Z) }
				if #ask({}) == 0 then
					out.stuck = `stage {camp}: a body on the camp's entry does not trigger it`
					break
				end
			end
		elseif step == "gate" then
			now = state.gateAt - 0.001
			if #ask({}) > 0 then
				out.held = false
			end
			now = state.gateAt
			ask({})
		elseif step == "breather" then
			now = state.breatherUntil - 0.001
			if #ask({}) > 0 then
				out.held = false
			end
			now = state.breatherUntil
			ask({})
		else
			now += 1
			if merging then
				for _ = 1, 100 do
					if #ask({ fieldClear = false, mergeOk = true }) == 0 then
						break
					end
				end
			end
			ask({ fieldClear = true })
		end
		safe()
	end
	if state.step ~= "over" and out.stuck == nil then
		out.stuck = `still in stage {state.stage} ({state.step}) after 400 asks`
	end
	return out
end

-- What holds for one level at one difficulty, whatever the level: the camps the plan gives it,
-- the waves it fields, where a party starts.
function L1.real.planChecks(tag: string, level: any, layout: any, plan: any, pieces: any): ()
	local Flow = L1.Flow
	local real = L1.real
	local rules = real.rules
	local ranks = real.ranks()
	local scales = level.difficulties[plan.difficulty]
	local campStages = 0
	for index, stageDef in level.stages do
		if stageDef.kind ~= "camp" then
			continue
		end
		campStages += 1
		local stage = plan.stages[index]
		local zone = if stage ~= nil then stage.zone else nil
		local camp = nil
		for _, candidate in layout.camps do
			if candidate.id == stageDef.zone then
				camp = candidate
			end
		end
		local where = `{tag}, camp {tostring(stageDef.zone)}`
		if zone == nil or camp == nil then
			check(false, `{where}: the plan has its zone`)
			continue
		end
		local rect = zone.rect
		local function on(x: number, z: number): boolean
			return math.abs(x - rect.x) <= rect.hx and math.abs(z - rect.z) <= rect.hz
		end
		local strays: { string } = {}
		if not on(zone.entry.X, zone.entry.Z) then
			table.insert(strays, "the entry")
		end
		if not on(zone.exit.X, zone.exit.Z) then
			table.insert(strays, "the exit")
		end
		local mark = camp.checkpoint
		if mark ~= nil and not on(mark.x, mark.z) then
			table.insert(strays, "the checkpoint")
		end
		for spawnIndex, point in zone.spawns do
			if not on(point.X, point.Z) or point.Y ~= zone.floorY then
				table.insert(strays, `spawn point {spawnIndex}`)
			end
		end
		check(#strays == 0 and #zone.spawns > 0, `{where}: its entry, exit, checkpoint and {#zone.spawns} spawn points are on the floor the plan gives it{real.list(strays)}`)
		check(not Flow.MustEnter(zone, zone.entry), `{where}: the close leaves a body on its entry where it stands`)
		-- Ruling 9 and the lead's ruling on the close, on this camp's own numbers and on all four
		-- of its sides.
		local function insetBy(inner: any, by: number): boolean
			return near(inner.x, rect.x) and near(inner.z, rect.z) and near(inner.hx, rect.hx - by) and near(inner.hz, rect.hz - by)
		end
		check(insetBy(zone.trigger, rules.triggerInset) and insetBy(zone.inner, rules.closeInset), `{where}: its trigger is its floor inset by levels.triggerInset ({rules.triggerInset}) and its close keeps the floor inset by levels.closeInset ({rules.closeInset}), on both axes`)
		local edge: { string } = {}
		local sides = { { "north", 0, -1 }, { "south", 0, 1 }, { "west", -1, 0 }, { "east", 1, 0 } }
		for _, side in sides do
			local function at(inside: number): any
				return vec(rect.x + side[2] * (rect.hx - inside), zone.floorY + real.ROOT, rect.z + side[3] * (rect.hz - inside))
			end
			if rules.closeInset > 0 and not Flow.MustEnter(zone, at(rules.closeInset / 2)) then
				table.insert(edge, `a body {rules.closeInset / 2} inside the {side[1]} edge is left there`)
			end
			if Flow.MustEnter(zone, at(rules.closeInset + 1)) then
				table.insert(edge, `a body {rules.closeInset + 1} inside the {side[1]} edge is moved`)
			end
		end
		check(#edge == 0, `{where}: at the close a body against any of its four edges is brought to the entry, and one a stud clear of the inset is left{real.list(edge)}`)
		-- Ruling 19 while the camp is closed, on its own numbers: the camp is the place a body may
		-- be in, its floor plus player.rescue.outside, down to its floor less player.rescue.below.
		-- (Walked to its fight with the fixture cases' helper: only the state matters here.)
		local rescue = real.rescue
		local reached, fight = pcall(L1.toFight, plan, index)
		local loose: { string } = {}
		if not reached then
			table.insert(loose, "the run never reaches its fight")
		else
			for _, side in sides do
				local function past(by: number): any
					return vec(rect.x + side[2] * (rect.hx + by), zone.floorY + real.ROOT, rect.z + side[3] * (rect.hz + by))
				end
				if not Flow.IsOut(plan, fight, past(rescue.outside + 1), rescue, rules.boxMargin) then
					table.insert(loose, `a body {rescue.outside + 1} past the {side[1]} edge is left out there`)
				end
				if rescue.outside >= 1 and Flow.IsOut(plan, fight, past(rescue.outside - 1), rescue, rules.boxMargin) then
					table.insert(loose, `a body {rescue.outside - 1} past the {side[1]} edge is taken back`)
				end
			end
			if not Flow.IsOut(plan, fight, vec(rect.x, zone.floorY - rescue.below - 1, rect.z), rescue, rules.boxMargin) then
				table.insert(loose, `a body {rescue.below + 1} under the floor is left there`)
			end
			if Flow.IsOut(plan, fight, vec(rect.x, zone.floorY - rescue.below + 1, rect.z), rescue, rules.boxMargin) then
				table.insert(loose, `a body {rescue.below - 1} under the floor is taken back`)
			end
		end
		check(#loose == 0, `{where}: while it is closed the rescue takes back a body more than player.rescue.outside ({rescue.outside}) past any of its edges or player.rescue.below ({rescue.below}) under its floor, and nobody nearer{real.list(loose)}`)
		-- Ruling 13: a burst at a spawn point arrives as a block inside the camp.
		local spilled: { string } = {}
		local size = math.max(math.floor(level.crowd.burst), 1)
		for spawnIndex, at in zone.spawns do
			for body = 0, size - 1 do
				local point = Flow.BurstPoint(zone, at, size, body, level.crowd.burstSpacing)
				if not on(point.X, point.Z) or point.Y ~= zone.floorY then
					table.insert(spilled, `spawn point {spawnIndex}, body {body + 1}`)
					break
				end
			end
		end
		check(#spilled == 0, `{where}: every body of a full burst ({size}, {level.crowd.burstSpacing} apart) at each of its spawn points is placed on its floor{real.list(spilled)}`)
		local floor = nil
		for _, piece in pieces or {} do
			if piece.role == "floor" and piece.camp == zone.id then
				floor = piece.box
			end
		end
		check(pieces == nil or (floor ~= nil and near(floor.x, rect.x) and near(floor.z, rect.z) and near(floor.sx, rect.hx * 2) and near(floor.sz, rect.hz * 2) and near(floor.y + floor.sy / 2, zone.floorY)), `{where}: the floor the run fights on is the floor that is built: its centre, its size, its top`)
		local empty: { string } = {}
		local wrong: { string } = {}
		-- A camp stage with no `waves` key is Validate's to report; nothing here may throw on it.
		local waveDefs = stageDef.waves or {}
		for waveIndex, waveDef in waveDefs do
			local spec = L1.Combat.CampWave(waveDef, level.crowd.regenShare, scales, ranks[plan.difficulty] or 0, ranks, 1, L1.combat)
			if spec.total <= 0 and spec.boss == nil then
				table.insert(empty, `wave {waveIndex}`)
			end
			local boss = waveDef.boss
			if boss ~= nil then
				local def = real.kinds[boss.kind]
				if def == nil or def.boss ~= true then
					table.insert(wrong, `wave {waveIndex}: {boss.kind} is not a boss kind`)
				end
				for _, attack in (if def ~= nil and def.attacks ~= nil then def.attacks else {}) do
					local called = attack.summon
					if called ~= nil and (real.kinds[called] == nil or level.crowd.rewards[called] == nil) then
						table.insert(wrong, `wave {waveIndex}: {boss.kind} calls {called}, which is unknown or unpriced`)
					end
				end
			end
		end
		check(#empty == 0 and #waveDefs > 0, `{where}: each of its {#waveDefs} waves fields a body or a boss at this difficulty{real.list(empty)}`)
		check(#wrong == 0, `{where}: a wave's boss is a boss kind (only that kill pays the Valor) and what it calls is a priced kind{real.list(wrong)}`)
		check(stage.waves == #waveDefs and stage.maxAlive >= 1 and stage.maxAlive <= FIXTURES.proving.crowd.maxAlive, `{where}: the plan has its {#waveDefs} waves and a cap the crowd can hold ({stage.maxAlive} of {FIXTURES.proving.crowd.maxAlive})`)
	end
	check(plan.camps == campStages and #plan.stages == #level.stages and campStages > 0 and plan.levelId == level.id, `{tag}: the plan is {level.id}'s, with the file's {#level.stages} stages, {campStages} of them camps`)

	local begin = Flow.Begin(plan)
	local unsound: { string } = {}
	local taken: { [string]: boolean } = {}
	for member = 1, 4 do
		local feet = Flow.StartPoint(plan, member, rules.startSpacing)
		local under, inside = nil, nil
		if pieces ~= nil then
			under, inside = real.footing(pieces, feet)
		end
		local key = `{feet.X} {feet.Z}`
		if pieces ~= nil and under == nil then
			table.insert(unsound, `member {member} stands on nothing at ({feet.X}, {feet.Y}, {feet.Z})`)
		elseif inside ~= nil then
			table.insert(unsound, `member {member} is put inside {inside}`)
		elseif taken[key] then
			table.insert(unsound, `member {member} is put where another stands`)
		elseif Flow.IsOut(plan, begin, vec(feet.X, feet.Y + real.ROOT, feet.Z), real.rescue, rules.boxMargin) then
			table.insert(unsound, `member {member} starts where the rescue takes a body from`)
		end
		taken[key] = true
	end
	check(#unsound == 0, `{tag}: a party of four starts on the start: each on solid ground, inside nothing, apart, and not where the rescue would take them from{real.list(unsound)}`)
end

-- A camp as LevelGeometry built it, against the layout's own points: the fence and its gates
-- stand on the fence line and nowhere else, the Part straight out from the entry and from the
-- exit is a gate, and the invisible wall stands behind every side, the gates included (closed,
-- it is all that holds a body in).
function L1.real.campChecks(name: string, layout: any, pieces: { any }): ()
	local real = L1.real
	local thickness = real.rules.fenceThickness
	for _, camp in layout.camps or {} do
		local where = `{name}, camp {camp.id}`
		local hx, hz = camp.sx / 2, camp.sz / 2
		-- The Part of `role` of this camp that holds the point (x, z) at the floor's level.
		local function partAt(role: string, x: number, z: number): any
			for _, piece in pieces do
				local box = piece.box
				if piece.role == role and piece.camp == camp.id and math.abs(x - box.x) <= box.sx / 2 and math.abs(z - box.z) <= box.sz / 2 and box.y - box.sy / 2 <= camp.y + 1e-6 and box.y + box.sy / 2 > camp.y then
					return piece
				end
			end
			return nil
		end
		local stray: { string } = {}
		local fences = 0
		for _, piece in pieces do
			if piece.camp ~= camp.id or (piece.role ~= "fence" and piece.role ~= "gate") then
				continue
			end
			fences += 1
			local box = piece.box
			local dx, dz = math.abs(box.x - camp.x), math.abs(box.z - camp.z)
			-- Inside the floor grown by the fence's thickness, and not over the floor itself.
			local within = dx + box.sx / 2 <= hx + thickness + 1e-6 and dz + box.sz / 2 <= hz + thickness + 1e-6
			local onFloor = dx - box.sx / 2 < hx - 1e-6 and dz - box.sz / 2 < hz - 1e-6
			if not within or onFloor or not near(box.y - box.sy / 2, camp.y) then
				table.insert(stray, piece.name)
			end
		end
		check(#stray == 0, `{where}: its {fences} fence and gate Parts stand on the fence line: outside the floor's edge, within the fence's thickness of it, on the floor's level{real.list(stray)}`)

		local unwalled: { string } = {}
		for _, piece in pieces do
			local box = piece.box
			-- The wall's inner face is the fence's outer face: a wall that reached over the fence
			-- line or the floor would hold fighters off the edge of their own camp.
			if piece.role == "barrier" and piece.camp == camp.id and math.abs(box.x - camp.x) - box.sx / 2 < hx + thickness - 1e-6 and math.abs(box.z - camp.z) - box.sz / 2 < hz + thickness - 1e-6 then
				table.insert(unwalled, `{piece.name} reaches inside the fence line`)
			end
		end
		local sides = { { "north", 0, -1 }, { "south", 0, 1 }, { "west", -1, 0 }, { "east", 1, 0 } }
		for _, side in sides do
			local x = camp.x + side[2] * (hx + thickness + 0.5)
			local z = camp.z + side[3] * (hz + thickness + 0.5)
			if layout.barrier ~= nil and partAt("barrier", x, z) == nil then
				table.insert(unwalled, side[1])
			end
		end
		-- Straight out of the camp from a point on its floor, through the nearest edge: what
		-- stands on the fence line there, and whether the invisible wall stands behind it.
		local function way(what: string, point: any): ()
			local toWest, toEast = point.x - (camp.x - hx), camp.x + hx - point.x
			local toNorth, toSouth = point.z - (camp.z - hz), camp.z + hz - point.z
			local least = math.min(toWest, toEast, toNorth, toSouth)
			local fx, fz, bx, bz = point.x, point.z, point.x, point.z
			if least == toWest then
				fx, bx = camp.x - hx - thickness / 2, camp.x - hx - thickness - 0.5
			elseif least == toEast then
				fx, bx = camp.x + hx + thickness / 2, camp.x + hx + thickness + 0.5
			elseif least == toNorth then
				fz, bz = camp.z - hz - thickness / 2, camp.z - hz - thickness - 0.5
			else
				fz, bz = camp.z + hz + thickness / 2, camp.z + hz + thickness + 0.5
			end
			if partAt("gate", fx, fz) == nil or partAt("fence", fx, fz) ~= nil then
				table.insert(unwalled, `the {what} faces no gate`)
			elseif layout.barrier ~= nil and partAt("barrier", bx, bz) == nil then
				table.insert(unwalled, `no wall behind the {what}'s gate`)
			end
		end
		local gates = #(camp.gates or {})
		if gates > 0 and (camp.entry == nil or camp.exit == nil) then
			table.insert(unwalled, "it has gates and no entry or no exit")
		elseif gates > 0 then
			way("entry", camp.entry)
			way("exit", camp.exit)
		end
		check(#unwalled == 0, `{where}: the invisible wall stands behind all four sides and nowhere inside the fence line{if gates > 0 then ", and straight out from its entry and from its exit the fence line holds a gate with the wall across it" else " (it has no gate)"}{real.list(unwalled)}`)
	end
end

function L1.realLevelTests(): ()
	print(" the real files: every built level resolves, validates and plans, as WaveService starts it")
	local real = L1.real
	local Flow = L1.Flow
	local ranks = real.ranks()
	local built = real.built()
	-- Catalog reads a level file or a mission only when it is named <n>_<Name>, and keeps one
	-- file per id; check_levels.py reads every *.json in those folders.
	check(#FIXTURES.unread == 0, `every file of Config/Levels and Config/Missions is named <n>_<Name>, the only ones Catalog reads{real.list(FIXTURES.unread)}`)
	local owned: { [string]: boolean } = {}
	local twice: { string } = {}
	for _, file in real.levels do
		local key = tostring(file.id)
		if owned[key] or type(file.id) ~= "string" then
			table.insert(twice, key)
		end
		owned[key] = true
	end
	check(#real.levels > 0 and #twice == 0, `the {#real.levels} level files each have an id of their own{real.list(twice)}`)
	local played: { string } = {}
	for _, node in real.map.nodes do
		local id = node.level
		if id == nil or not built[id] then
			continue
		end
		table.insert(played, id)
		local got = real.resolve(id)
		local file, level, layout = got.file, got.level, got.layout
		check(level ~= nil and level.id == id, `{id}: Resolve reads its file {if file ~= nil and file.mission ~= nil then "through the mission " .. file.mission else "as it stands"}, and the level keeps the id its node names`)
		check(layout ~= nil, `{id}: its layout {if file ~= nil then file.layout else "?"} is there{if got.why ~= nil then " (" .. got.why .. ")" else ""}`)
		if level == nil or layout == nil then
			continue
		end
		local validated, problems = pcall(Flow.Validate, level, layout, real.kinds, ranks)
		if not validated then
			problems = { `Validate threw: {tostring(problems)}` }
		end
		check(#problems == 0, `{id}: Validate finds no problem{real.list(problems)}`)
		local strange: { string } = {}
		local offered = 0
		for name in level.difficulties do
			offered += 1
			if ranks[name] == nil then
				table.insert(strange, name)
			end
		end
		check(offered > 0 and #strange == 0, `{id}: each of its {offered} difficulties is one of the map's (one that is not has rank 0, and fields no minDifficulty group){real.list(strange)}`)
		check(level.runCapSeconds > 0 and level.crowd.burst >= 1, `{id}: a run cap ({level.runCapSeconds} s) and a burst size ({level.crowd.burst})`)
		local pieces = real.pieces(layout)
		local bounds = L1.Geo.Bounds(layout)
		for _, difficulty in real.map.difficulties do
			if level.difficulties[difficulty] == nil then
				continue
			end
			local plan, why = real.plan(level, layout, difficulty, bounds)
			check(plan ~= nil and why == nil, `{id} {difficulty}: Plan gives a plan and refuses nothing{if why ~= nil then " (" .. why .. ")" else ""}`)
			-- With a problem Validate named the level is never started: its camps are not judged.
			if plan ~= nil and #problems == 0 then
				real.planChecks(`{id} {difficulty}`, level, layout, plan, pieces)
			end
		end
	end
	check(table.find(played, "forestRoad") ~= nil and table.find(played, "raiderArena") ~= nil, `the map's built levels are played here: {table.concat(played, ", ")}`)

	-- What Play does first in a proving build (ruling 32), and what its panel offers.
	local debug = L1.combat.debug
	local proving = real.resolve(debug.provingLevel)
	check(proving.level ~= nil and proving.level.difficulties[debug.provingDifficulty] ~= nil, `Combat.json debug.provingLevel ({debug.provingLevel}) is a level and offers debug.provingDifficulty ({debug.provingDifficulty})`)
	local presets = debug.gearPresets
	local sound = type(debug.provingAutoStart) == "boolean" and type(presets) == "table" and #presets > 0
	for _, preset in if type(presets) == "table" then presets else {} do
		sound = sound and type(preset.name) == "string" and type(preset.melee) == "number" and type(preset.ranged) == "number"
	end
	check(sound, "Combat.json debug: provingAutoStart is a boolean, and each gear preset (the G key) has a name and its two tiers")

	-- Every number a level's start, its run, the session and the builder read from Combat.json.
	-- A missing one is arithmetic on nil in the remote's thread or in the tick, not a refusal.
	local needs = {
		levels = { "gateSeconds", "triggerInset", "closeInset", "triggerHeight", "startSpacing", "startCooldownSeconds", "fenceThickness", "boxMargin", "maxParts" },
		director = { "windowSeconds", "tempoWarmupSeconds", "eliteTempo", "runCapSeconds" },
		coop = { "maxParty", "joinUntilWave", "contributionFloor", "countPerExtraPlayer", "bossHpPerExtraPlayer", "mentorMinDamageShare", "mentorValor", "lobbyWaitSeconds", "returnGroupSeconds" },
		remotes = { "combatStateHz" },
		debug = { "provingStartDelay" },
	}
	local missing: { string } = {}
	for block, keys in needs do
		local holder = L1.combat[block]
		for _, key in keys do
			if type(holder) ~= "table" or type(holder[key]) ~= "number" then
				table.insert(missing, `{block}.{key}`)
			end
		end
	end
	local rescue = L1.combat.player.rescue
	if type(rescue) ~= "table" or type(rescue.below) ~= "number" or type(rescue.outside) ~= "number" then
		table.insert(missing, "player.rescue")
	end
	table.sort(missing)
	check(#missing == 0, `Combat.json holds every number a level's start, its run, the session and the builder read (levels, director, coop, remotes, player.rescue){real.list(missing)}`)
end
L1.realLevelTests()

function L1.realWorldTests(): ()
	print(" the real files: every layout builds (LevelGeometry.Pieces, as LevelService asks it) and check_levels.py counts the same Parts")
	local real = L1.real
	local Geo = L1.Geo
	local counts = real.gate.parts
	check(counts ~= nil, "tools/check_levels.py gave its Part counts (run_harness.py imports it; its stderr says why not)")
	local names: { string } = {}
	for name in real.layouts do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local layout, why = real.layout(name)
		check(layout ~= nil, `{name}: the layout is read{if why ~= nil then " (" .. why .. ")" else ""}`)
		if layout == nil then
			continue
		end
		local pieces, refusal = real.pieces(layout)
		check(pieces ~= nil and refusal == nil, `{name}: Pieces builds it and refuses nothing{if refusal ~= nil then " (" .. refusal .. ")" else ""}`)
		if pieces == nil then
			continue
		end
		local expected = if counts ~= nil then counts[name] else nil
		check(#pieces == expected and #pieces > 0, `{name}: {#pieces} Parts, the number check_levels.py counts ({tostring(expected)})`)
		local bounds = Geo.Bounds(layout)
		local margin = real.rules.boxMargin
		local outside: { string } = {}
		local far: { string } = {}
		local unlooked: { string } = {}
		local reach = 0
		for _, piece in pieces do
			local box = piece.box
			local over = math.max(bounds.minX - (box.x - box.sx / 2), box.x + box.sx / 2 - bounds.maxX, bounds.minZ - (box.z - box.sz / 2), box.z + box.sz / 2 - bounds.maxZ, 0)
			local role = piece.role
			if role == "block" or role == "floor" or role == "obstacle" or role == "secret" then
				if over > 1e-6 or box.y - box.sy / 2 < bounds.minY - 1e-6 or box.y + box.sy / 2 > bounds.maxY + 1e-6 then
					table.insert(outside, piece.name)
				end
			end
			reach = math.max(reach, over)
			if over > margin then
				table.insert(far, piece.name)
			end
			if piece.look ~= nil and real.map.looks[piece.look] == nil then
				table.insert(unlooked, `{piece.name} ({piece.look})`)
			end
			if piece.look == nil and role ~= "barrier" then
				table.insert(unlooked, `{piece.name} (no look)`)
			end
		end
		check(#outside == 0, `{name}: Bounds holds every block, floor, obstacle and secret whole{real.list(outside)}`)
		check(#far == 0, `{name}: every other Part (fence, gate, marker, sign, invisible wall) reaches at most {reach} studs past it, inside the rescue's box (Bounds + levels.boxMargin {margin}){real.list(far)}`)
		check(#unlooked == 0, `{name}: every Part's look is one of Expeditions.json looks (only the invisible wall has none){real.list(unlooked)}`)
		check(layout.killY < bounds.minY, `{name}: its kill height ({layout.killY}) is under its lowest Part ({bounds.minY})`)
		real.campChecks(name, layout, pieces)
	end

	-- The lobby: where LevelService.LobbyPoint puts a body, and what WaveService's rescue judges
	-- it against (the lobby's bounds + boxMargin, down to its layout's killY).
	local lobby = real.layouts[real.map.lobby.layout]
	check(lobby ~= nil and lobby.arena == nil, `the map's lobby layout ({real.map.lobby.layout}) is a layout file of its own`)
	local lobbyPieces = if lobby ~= nil and lobby.arena == nil then real.pieces(lobby) else nil
	if lobby ~= nil and lobbyPieces ~= nil then
		local bounds = Geo.Bounds(lobby)
		local points = { lobby.start }
		for _, point in lobby.spawns or {} do
			table.insert(points, point)
		end
		local unsound: { string } = {}
		for index, point in points do
			local feet = vec(point.x, point.y, point.z)
			local under, inside = real.footing(lobbyPieces, feet)
			if under == nil then
				table.insert(unsound, `point {index} stands on nothing`)
			elseif inside ~= nil then
				table.insert(unsound, `point {index} is inside {inside}`)
			elseif L1.Flow.OutOfBox(bounds, lobby.killY, vec(point.x, point.y + real.ROOT, point.z), real.rules.boxMargin) then
				table.insert(unsound, `point {index} is where the rescue takes a body from`)
			end
		end
		check(#unsound == 0 and #points >= 2, `the lobby's start and its {#points - 1} spawn points stand on its floor, inside nothing, and the rescue leaves them be{real.list(unsound)}`)
	end

	-- The arena's two adapters: LevelGeometry.FromArena on the real module against the layout
	-- check_levels.py (sim_range.arena_as_layout) reads out of the same file.
	local seen = 0
	for name, theirs in real.gate.arenas or {} do
		seen += 1
		local ours = real.layout(name)
		local a = if ours ~= nil then ours.camps[1] else nil
		local b = theirs.camps[1]
		if ours == nil or a == nil or b == nil then
			check(false, `{name}: both adapters read the arena {tostring(theirs.arena)}`)
			continue
		end
		local differs: { string } = {}
		local function same(what: string, x: any, y: any): ()
			if type(x) ~= "number" or type(y) ~= "number" or not near(x, y) then
				table.insert(differs, `{what} {tostring(x)} / {tostring(y)}`)
			end
		end
		same("camp sx", a.sx, b.sx)
		same("camp sz", a.sz, b.sz)
		same("camp x", a.x, b.x)
		same("camp y", a.y, b.y)
		same("camp z", a.z, b.z)
		same("fence height", if a.fence ~= nil then a.fence.height else nil, if b.fence ~= nil then b.fence.height else nil)
		same("gates", #a.gates, #b.gates)
		same("entry x", a.entry.x, b.entry.x)
		same("entry z", a.entry.z, b.entry.z)
		same("exit x", a.exit.x, b.exit.x)
		same("exit z", a.exit.z, b.exit.z)
		same("start x", ours.start.x, theirs.start.x)
		same("start y", ours.start.y, theirs.start.y)
		same("start z", ours.start.z, theirs.start.z)
		same("killY", ours.killY, theirs.killY)
		same("barrier height", if ours.barrier ~= nil then ours.barrier.height else nil, if theirs.barrier ~= nil then theirs.barrier.height else nil)
		same("barrier thickness", if ours.barrier ~= nil then ours.barrier.thickness else nil, if theirs.barrier ~= nil then theirs.barrier.thickness else nil)
		same("spawn points", #a.spawns, #b.spawns)
		for index, point in a.spawns do
			local other = b.spawns[index]
			same(`spawn {index} x`, point.x, if other ~= nil then other.x else nil)
			same(`spawn {index} z`, point.z, if other ~= nil then other.z else nil)
		end
		same("obstacles", #(a.obstacles or {}), b.obstacleCount)
		check(#differs == 0, `{name}: LevelGeometry.FromArena and check_levels.py's adapter read the arena {tostring(theirs.arena)} alike: size, fence, entry, exit, start, kill height, invisible wall, {#a.spawns} spawn points in order, {#(a.obstacles or {})} obstacles (ours / theirs){real.list(differs)}`)
	end
	local arenaLayouts = 0
	for _, layout in real.layouts do
		if layout.arena ~= nil then
			arenaLayouts += 1
		end
	end
	check(seen == arenaLayouts, `check_levels.py read every layout that names an arena ({seen} of {arenaLayouts})`)
end
L1.realWorldTests()

function L1.realRunTests(): ()
	print(" the real files: a whole run of every built level at every difficulty, through Begin and Advance")
	local real = L1.real
	local Flow = L1.Flow
	local built = real.built()
	for _, node in real.map.nodes do
		local id = node.level
		local got = if id ~= nil and built[id] then real.resolve(id) else nil
		local level = if got ~= nil then got.level else nil
		local layout = if got ~= nil then got.layout else nil
		if id == nil or level == nil or layout == nil then
			continue
		end
		local pieces = real.pieces(layout)
		local bounds = L1.Geo.Bounds(layout)
		local waves = 0
		local camps = 0
		local merges = false
		for _, stage in level.stages do
			if stage.kind == "camp" then
				camps += 1
				waves += #(stage.waves or {})
				merges = merges or stage.merge == true
			end
		end
		for _, difficulty in real.map.difficulties do
			local plan = if level.difficulties[difficulty] ~= nil then real.plan(level, layout, difficulty, bounds) else nil
			if plan == nil then
				continue
			end
			local tag = `{id} {difficulty}`
			local run = real.run(plan, pieces, false)
			local log = run.log
			local last = log[#log]
			check(run.stuck == nil, `{tag}: the run walks to its end{if run.stuck ~= nil then " (" .. run.stuck .. ")" else ""}`)
			check(real.said(log) == real.script(level), `{tag}: it answers exactly what its file lists: {camps} camps, {waves} waves in turn, each camp's bank and opening, then the end ({real.said(log)})`)
			check(last ~= nil and last.kind == "end" and last.reason == "cleared" and run.state.ended == "cleared" and run.state.cleared == camps, `{tag}: it ends "cleared" with {camps} camps cleared`)

			local strange: { string } = {}
			local banks = 0
			local banked = 0
			for _, action in log do
				local stageDef = level.stages[action.stage]
				local stage = plan.stages[action.stage]
				local kind = action.kind
				if not real.EXECUTED[kind] then
					table.insert(strange, `{kind} is no action WaveService executes`)
				elseif real.ZONED[kind] and (stage == nil or stage.zone == nil) then
					table.insert(strange, `{kind} names stage {action.stage}, which has no zone`)
				elseif kind == "wave" and (stageDef == nil or stageDef.waves == nil or stageDef.waves[action.wave] == nil) then
					table.insert(strange, `wave {tostring(action.wave)} of stage {action.stage} is not in the file`)
				elseif kind == "gate" and not near(action.at, action.now + real.rules.gateSeconds) then
					table.insert(strange, `stage {action.stage}'s countdown is {action.at - action.now} s, not levels.gateSeconds`)
				elseif kind == "breather" then
					local expected = if stageDef ~= nil and stageDef.breatherSeconds ~= nil then stageDef.breatherSeconds else L1.Combat.BreatherSeconds(1, L1.combat.director)
					if not near(action.at, action.now + expected) then
						table.insert(strange, `stage {action.stage}'s breather is {action.at - action.now} s, not {expected}`)
					end
				elseif kind == "bank" then
					banks += 1
					banked += action.count
					local each = stageDef ~= nil and stageDef.bankEachWave == true
					local size = if stageDef ~= nil and stageDef.waves ~= nil then #stageDef.waves else 0
					if each and action.count ~= 1 then
						table.insert(strange, `stage {action.stage} banks {action.count} waves at wave {action.wave}`)
					elseif not each and (action.wave ~= size or action.count ~= size) then
						table.insert(strange, `stage {action.stage} banks {action.count} waves at wave {action.wave} of {size}`)
					end
				end
			end
			check(#strange == 0, `{tag}: every action is one WaveService executes, on a stage and a wave that are there, with the config's countdown and the stage's breather{real.list(strange)}`)
			check(banked == waves and banks >= camps, `{tag}: {banks} banks pay for all {waves} waves, and nothing is banked twice`)
			check(run.held, `{tag}: a moment before a countdown or a breather is over, nothing happens`)
			check(#run.unsafe == 0 and run.safe > camps * 3, `{tag}: the safe point is asked {run.safe} times (the start, each countdown, each wave, each breather, each cleared camp) and is always inside the level's bounds, above its kill height, on solid ground, inside nothing, and no place the rescue takes a body from{real.list(run.unsafe)}`)
			local stars = {}
			local isNew = Flow.Award(stars, plan.levelId, plan.difficulty)
			local shown = Flow.NodeState(real.map, built, stars, stars, node.id)
			check(isNew and shown ~= nil and table.find(shown.stars, difficulty) ~= nil, `{tag}: clearing it puts the {difficulty} star on its node, {node.id}`)
			local first = level.stages[1]
			local early = table.concat(run.early, ", ")
			if first ~= nil and first.kind == "camp" then
				check(early == "1", `{tag}: it opens on a camp, and the party's start is inside it: the countdown begins with nobody walking (stages triggered at a standstill: {early})`)
			else
				check(early == "", `{tag}: no camp triggers from where the run puts the party (the start, the last camp's exit){if early ~= "" then ": stage " .. early else ""}`)
			end

			if merges then
				-- The director says "merge" at every ask: a wave is folded in unless it, or the wave
				-- before it, has a boss.
				local merged = real.run(plan, pieces, true)
				local folded: { string } = {}
				local expected: { string } = {}
				local paid = 0
				local fielded = 0
				local wrong: { string } = {}
				-- Within the stage being played: the waves queued so far, and those since its last bank.
				local inStage = 0
				local queued = 0
				local group = 0
				for _, action in merged.log do
					local stage = plan.stages[action.stage]
					if action.kind == "wave" then
						if action.stage ~= inStage then
							inStage = action.stage
							queued = 0
							group = 0
						end
						fielded += 1
						queued += 1
						group += 1
						if action.merged == true then
							table.insert(folded, `{action.stage}.{action.wave}`)
						end
						if action.wave ~= queued then
							table.insert(wrong, `stage {action.stage}: wave {action.wave} came as number {queued}`)
						end
						if stage ~= nil and stage.merge and action.wave > 1 and not stage.boss[action.wave] and not stage.boss[action.wave - 1] then
							table.insert(expected, `{action.stage}.{action.wave}`)
						end
					elseif action.kind == "bank" then
						paid += action.count
						if action.count ~= group then
							table.insert(wrong, `the bank at wave {action.wave} counts {action.count} waves of a group of {group}`)
						end
						group = 0
					end
				end
				local ended = merged.log[#merged.log]
				check(merged.stuck == nil and ended ~= nil and ended.reason == "cleared" and fielded == waves and #wrong == 0, `{tag}, merging: every wave is still fielded once, in turn, and the run ends "cleared"{real.list(wrong)}`)
				check(table.concat(folded, " ") == table.concat(expected, " ") and #folded > 0, `{tag}, merging: the waves folded in are those with no boss in them or before them ({table.concat(folded, " ")})`)
				check(paid == waves, `{tag}, merging: each merged group banks once, for every wave in it ({paid} waves paid)`)
			end
		end

		-- The arena as P5 played it (ruling 27, and the skeleton Ben ruled for every era).
		if id == "raiderArena" then
			local plan = real.plan(level, layout, "normal", bounds)
			local stage = if plan ~= nil then plan.stages[1] else nil
			local bosses: { string } = {}
			if stage ~= nil then
				for wave = 1, stage.waves do
					if stage.boss[wave] then
						table.insert(bosses, tostring(wave))
					end
				end
			end
			check(stage ~= nil and #plan.stages == 1 and stage.waves == 10 and table.concat(bosses, " ") == "5 10", `raiderArena: one camp of ten waves, bosses at 5 and 10 ({table.concat(bosses, " ")})`)
			check(stage ~= nil and stage.bankEachWave and stage.merge and stage.breatherSeconds == nil, "raiderArena: it banks at every wave clear, merges, and takes the director's breather")
		end
	end
end
L1.realRunTests()

function L1.realMapTests(): ()
	print(" the real files: the map (Expeditions.json) as a leader with no star sees it")
	local real = L1.real
	local map = real.map
	local state = L1.Flow.MapState(map, real.built(), {}, {}, 7)
	check(state.kind == "map" and state.leaderUserId == 7 and #state.nodes == #map.nodes, `every one of the {#map.nodes} nodes is on the map`)
	local byId = {}
	for _, node in state.nodes do
		byId[node.id] = node
	end
	local open: { string } = {}
	local unbuilt: { string } = {}
	local other: { string } = {}
	for _, node in map.nodes do
		local got = byId[node.id]
		local hasFile = node.level ~= nil and real.file(node.level) ~= nil
		if got ~= nil and got.open == true and got.reason == nil and hasFile then
			table.insert(open, node.id)
		elseif got ~= nil and got.open == false and got.reason == "notBuilt" and not hasFile then
			table.insert(unbuilt, node.id)
		else
			table.insert(other, `{node.id} ({if got ~= nil then tostring(got.reason) else "missing"})`)
		end
	end
	check(table.concat(open, " ") == "forestRoad raiderArena", `forestRoad and raiderArena are open ({table.concat(open, " ")})`)
	check(#unbuilt == #map.nodes - #open and #other == 0, `the other {#unbuilt} have no level file and are locked, each "notBuilt": {table.concat(unbuilt, ", ")}{real.list(other)}`)

	local ids: { [string]: number } = {}
	for _, node in map.nodes do
		ids[node.id] = (ids[node.id] or 0) + 1
	end
	local loose: { string } = {}
	for _, node in map.nodes do
		if ids[node.id] ~= 1 then
			table.insert(loose, `{node.id} is the id of {ids[node.id]} nodes`)
		end
		if node.from ~= nil and ids[node.from] == nil then
			table.insert(loose, `{node.id}.from names {node.from}`)
		end
		local requires = node.requires
		if requires ~= nil and requires.node ~= nil and ids[requires.node] == nil then
			table.insert(loose, `{node.id}.requires.node names {requires.node}`)
		end
		if map.themes[node.theme] == nil then
			table.insert(loose, `{node.id}'s theme {tostring(node.theme)} is not in themes`)
		end
		if node.level ~= nil and real.file(node.level) == nil and byId[node.id] ~= nil and byId[node.id].open then
			table.insert(loose, `{node.id} is open and has no level file`)
		end
	end
	check(#loose == 0, `every node has an id of its own, a \`from\` and a \`requires.node\` that are nodes, and a theme that is in themes{real.list(loose)}`)
	local unnamed: { string } = {}
	for _, name in map.difficulties do
		if map.difficultyNames[name] == nil then
			table.insert(unnamed, name)
		end
	end
	check(#map.difficulties > 0 and #unnamed == 0, `the map's {#map.difficulties} difficulties each have a name{real.list(unnamed)}`)

	-- A star on Forest Road changes nothing a file does not back: the nodes behind it stay
	-- "notBuilt" (it wins over every other reason) until their level files exist.
	local starred = L1.Flow.MapState(map, real.built(), { forestRoad = { normal = true } }, { forestRoad = { normal = true } }, 7)
	local still = 0
	local shown = false
	for _, node in starred.nodes do
		if node.reason == "notBuilt" then
			still += 1
		end
		if node.id == "forestRoad" and #node.stars == 1 and node.stars[1] == "normal" then
			shown = true
		end
	end
	check(still == #unbuilt and shown, "with the leader's star on forestRoad its star shows, and the unbuilt nodes stay notBuilt")
end
L1.realMapTests()

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
