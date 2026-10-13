-- Cases for L1's run rules (docs/INTERFACES.md "L1 contracts" → "B — the run"): the pure
-- StageFlow, Combat's camp functions, and CrowdService's floor. Appended last by run_harness.py,
-- so every local of the earlier files is in scope. Everything hangs off the L1 table (the
-- 200-local limit). WaveService and ArenaService are Instance and service work and cannot be
-- loaded here: they only execute what StageFlow returns.

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

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
