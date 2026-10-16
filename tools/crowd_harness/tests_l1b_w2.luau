-- Cases for L1b Wave 2, the run (docs/INTERFACES.md "Wave 2 — the long road" → "B —
-- StageFlow", "B — Combat", "B — LevelGeometry"): a tent's stock in Plan and its refusals in
-- Validate, the boss reserve and the population rule (L1b-W2-5), a camp's clear held by its tent
-- (L1b-W2-8), the clear bonus and the merge test's dead fraction (L1b-W2-21, -26), the tent
-- marker (L1b-W2-9), and the shipped Forest Road. Appended after tests_l1b.luau, so every local
-- of the earlier files is in scope (vec, check, near, load, L1, L1W, L1B). Everything hangs off
-- the W2B table (the 200-local limit), and every group runs behind L1.group, so one that throws
-- fails a check and the bundle goes on to its verdict.

print("L1b Wave 2: the run (tents, the population, the clear bonus)")

local W2B: any = {
	Flow = load("StageFlow"),
	Combat = load("Combat"),
	Geo = load("LevelGeometry"),
	-- The real crowd kinds: the colossus calls 12, the warlord 4.
	real = FIXTURES.proving.crowd.kinds,
}

-- L1B's road with two tents: A's (2 fodder, a slinger from Hard, a brute; one every 6 s) round
-- (10, 110), B's (3 fodder; every 4 s) round (120, 320), and a marker only on the boss room C.
-- L1b Wave 4: each tent carries its pace (L1b-W4-28), which Validate requires.
function W2B.level(): any
	local level = L1B.level()
	level.camps[1].tent = {
		every = 6,
		units = { { kind = "fodder", count = 2 }, { kind = "slinger", count = 1, minDifficulty = "hard" }, { kind = "brute", count = 1 } },
		pace = { seconds = 25, lead = 0.15 },
	}
	level.camps[2].tent = { every = 4, units = { { kind = "fodder", count = 3 } }, pace = { seconds = 130, lead = 0.15 } }
	return level
end

function W2B.layout(): any
	local layout = L1B.layout()
	layout.camps[1].tent = { x = 10, y = 12, z = 110, sx = 4, sy = 8, sz = 4, radius = 5 }
	layout.camps[2].tent = { x = 120, y = 16, z = 320, sx = 6, sy = 8, sz = 6, radius = 6 }
	layout.camps[3].tent = { x = 20, y = 9, z = 500, sx = 8, sy = 10, sz = 8, radius = 5 }
	return layout
end

function W2B.plan(level: any?, layout: any?, difficulty: string?, kinds: any?): any
	local given = if kinds == false then nil else kinds or L1B.kinds
	return W2B.Flow.Plan(level or W2B.level(), layout or W2B.layout(), difficulty or "normal", L1B.rules, L1B.bounds, L1B.ranks, given)
end

function W2B.problems(level: any?, layout: any?, crowdMax: number?): { string }
	local ok, problems = pcall(W2B.Flow.Validate, level or W2B.level(), layout or W2B.layout(), L1B.kinds, L1B.ranks, L1B.rules, crowdMax or L1B.crowdMax)
	if not ok then
		return { "Validate threw: " .. tostring(problems) }
	end
	return problems
end

-- "kind count, kind count", sorted, of a stock by kind.
function W2B.stock(stock: any): string
	local out = {}
	for kind, count in stock or {} do
		table.insert(out, `{kind} {count}`)
	end
	table.sort(out)
	return table.concat(out, ", ")
end

-- Validate ------------------------------------------------------------------------------------

function W2B.validateTests(): ()
	print(" Validate: a tent's refusals (L1b-W2-6), the clear bonus's share (L1b-W2-21)")
	local problems = W2B.problems
	local has = L1.has
	local good = problems()
	check(#good == 0, `the fixture (two tents on open camps, a marker on the boss room) has no problem ({good[1] or "none"})`)
	local function names(what: string, text: string, edit: (level: any, layout: any) -> (), crowdMax: number?): ()
		local level, layout = W2B.level(), W2B.layout()
		edit(level, layout)
		local list = problems(level, layout, crowdMax)
		check(not has(list, "Validate threw") and has(list, text), `{what}: "{text}" ({list[1] or "no problem"})`)
	end
	names("a tent with no every", `camps entry 1 ("A"): its tent's every is nil, not a time above 0`, function(level)
		level.camps[1].tent.every = nil
	end)
	names("a tent's every of 0", "its tent's every is 0, not a time above 0", function(level)
		level.camps[1].tent.every = 0
	end)
	names("a tent's every that is not a number", 'its tent\'s every is soon, not a time above 0', function(level)
		level.camps[2].tent.every = "soon"
	end)
	names("a tent's every that is infinite", "its tent's every is inf, not a time above 0", function(level)
		level.camps[1].tent.every = math.huge
	end)
	names("a tent's every that is NaN", "not a time above 0", function(level)
		level.camps[1].tent.every = 0 / 0
	end)
	names("a tent with no units", `camps entry 2 ("B") tent has no units`, function(level)
		level.camps[2].tent.units = {}
	end)
	names("a tent unit with no kind", `camps entry 1 ("A") tent unit 3 has no kind`, function(level)
		level.camps[1].tent.units[3].kind = nil
	end)
	names("a tent unit of a kind ProvingGrounds.json lacks", 'tent unit 1 names the unknown kind "ghost"', function(level)
		level.camps[1].tent.units[1].kind = "ghost"
	end)
	names("a tent unit the rewards do not price", 'tent unit 1 fields "stray", which rewards does not price', function(level)
		level.camps[2].tent.units[1].kind = "stray"
	end)
	names("a tent unit of count 0", "tent unit 1: count 0 is not a whole number of at least 1", function(level)
		level.camps[1].tent.units[1].count = 0
	end)
	names("a tent unit of count 2.5", "count 2.5 is not a whole number of at least 1", function(level)
		level.camps[2].tent.units[1].count = 2.5
	end)
	names("a tent unit's minDifficulty that is no difficulty", 'tent unit 2: minDifficulty "nightmare" is no difficulty', function(level)
		level.camps[1].tent.units[2].minDifficulty = "nightmare"
	end)
	names("a tent stock on the boss room", `camps entry 3 ("C"): camp C locks, and a boss room's tent has no stock`, function(level)
		level.camps[3].tent = { every = 6, units = { { kind = "fodder", count = 2 } }, pace = { seconds = 25, lead = 0.15 } }
	end)
	names("a tent stock whose layout camp has no tent block", `camps entry 2 ("B") has a tent stock, and camp B has no tent block`, function(_level, layout)
		layout.camps[2].tent = nil
	end)
	names("a tent stock on a camp with no residents", "on normal camp A has a tent stock of 3 and no residents", function(level)
		level.camps[1].residents = {}
	end)
	-- Residents of Hard alone: Normal's camp has none, Hard's has one.
	local hardOnly = W2B.level()
	hardOnly.camps[1].residents = { { spot = "gate", units = { { kind = "slinger", count = 1, minDifficulty = "hard" } } } }
	local hardList = problems(hardOnly)
	check(has(hardList, "on normal camp A has a tent stock of 3 and no residents") and not has(hardList, "on hard camp A"), "it is judged at each difficulty: Normal has no resident there, Hard has its slinger")
	names("a tent block with a radius of 0", "camp A: its tent's size and radius must be above 0", function(_level, layout)
		layout.camps[1].tent.radius = 0
	end)
	names("a tent block with no radius (Wave 1's draft shape)", "camp A: its tent needs a finite x, y, z, sx, sy, sz, radius", function(_level, layout)
		layout.camps[1].tent.radius = nil
	end)
	names("a tent block of height 0", "camp B: its tent's size and radius must be above 0", function(_level, layout)
		layout.camps[2].tent.sy = 0
	end)
	names("a tent block at NaN", "camp A: its tent needs a finite", function(_level, layout)
		layout.camps[1].tent.x = 0 / 0
	end)
	names("a tent block with an infinite size", "camp A: its tent needs a finite", function(_level, layout)
		layout.camps[1].tent.sz = math.huge
	end)
	names("a boss room's marker off its floor", "camp C: its tent's centre lies off the floor", function(_level, layout)
		layout.camps[3].tent.x = 41
	end)
	local edge = W2B.layout()
	edge.camps[1].tent.x = 30
	edge.camps[1].tent.radius = 0.5
	check(not has(problems(nil, edge), "its tent's centre lies off the floor"), "(a centre on the floor's edge is on it; A's floor ends at x 30)")
	-- A's floor ends at x 30, the brute's radius is 2.2: a ring of 4 round x 25 reaches x 29.
	names("a ring that reaches past its floor less its widest kind", "group A.tent: ring post", function(_level, layout)
		layout.camps[1].tent.x = 25
		layout.camps[1].tent.z = 100
		layout.camps[1].tent.radius = 4
	end)
	local inside = W2B.layout()
	inside.camps[1].tent.x = 25
	inside.camps[1].tent.z = 100
	inside.camps[1].tent.radius = 2.7
	check(not has(problems(nil, inside), "ring post"), "(a ring of 2.7 round x 25 keeps to x 27.7, inside the floor less 2.2)")
	names("a clear bonus share of 1.5", "crowd.clearBonus needs a share from 0 to 1", function(level)
		level.crowd.clearBonus = { share = 1.5 }
	end)
	names("a clear bonus share that is NaN", "crowd.clearBonus needs a share from 0 to 1", function(level)
		level.crowd.clearBonus = { share = 0 / 0 }
	end)
	names("a clear bonus that is a number", "crowd.clearBonus needs a share from 0 to 1", function(level)
		level.crowd.clearBonus = 0.1
	end)
	for _, share in { 0, 1 } do
		local level = W2B.level()
		level.crowd.clearBonus = { share = share }
		check(not has(problems(level), "clearBonus"), `(a share of {share} is legal)`)
	end

	print(" Validate: the population rule at each difficulty (L1b-W2-5), worked by hand")
	-- Normal: residents 20 (as L1b's fixture), tents A 3 (2 fodder, a brute) + B 3 = 6, the boss
	-- room's room 30 - 3 = 27, the boss reserve 1 + 20 = 21: 74.
	-- Hard: 23 residents, tents 4 + 3 = 7 (the slinger joins), 27, 21: 78.
	-- Brutal: 24 residents, 7, 30 - 4 = 26, 21: 78.
	names("a crowd cap of 77", "on hard the population is 78, over ProvingGrounds.json crowd.maxAlive (77)", function() end, 77)
	names("a crowd cap of 77, Brutal", "on brutal the population is 78", function() end, 77)
	check(not has(problems(nil, nil, 77), "on normal"), "(Normal's 74 is under 77)")
	check(#problems(nil, nil, 78) == 0, "a crowd cap of 78 holds every difficulty")
	-- One level one body over 160: A's tent 82 fodder more makes Hard 160; 83 makes it 161.
	names("Hard one body over 160", "on hard the population is 161, over ProvingGrounds.json crowd.maxAlive (160)", function(level)
		level.camps[1].tent.units[1].count = 2 + 83
	end)
	local full = W2B.level()
	full.camps[1].tent.units[1].count = 2 + 82
	check(#problems(full) == 0, "and 82 more is 160 exactly: legal")
	local summoner = L1.copy(L1B.kinds)
	summoner.colossus = W2B.real.colossus
	local ok, list = pcall(W2B.Flow.Validate, W2B.level(), W2B.layout(), summoner, L1B.ranks, L1B.rules, 70)
	check(ok and #list == 0, `with the real colossus (1 + its 12 calls = 13) Hard is 23 + 7 + 27 + 13 = 70: under a cap of 70 ({if ok then list[1] or "none" else tostring(list)})`)
	ok, list = pcall(W2B.Flow.Validate, W2B.level(), W2B.layout(), summoner, L1B.ranks, L1B.rules, 69)
	check(ok and has(list, "on hard the population is 70, over ProvingGrounds.json crowd.maxAlive (69)"), "and over a cap of 69, naming the difficulty and both numbers")
end
L1.group("l1b w2 validateTests", W2B.validateTests)

-- BossReserve and Plan --------------------------------------------------------------------------

function W2B.planTests(): ()
	print(" BossReserve (L1b-W2-5)")
	local Flow = W2B.Flow
	local level = W2B.level()
	check(Flow.BossReserve(level, W2B.real) == 13, `the Colossus: 1 + its 12 calls = 13 ({Flow.BossReserve(level, W2B.real)})`)
	local warlord = W2B.level()
	warlord.stages[2].waves[2].boss.kind = "warlord"
	check(Flow.BossReserve(warlord, W2B.real) == 5, `the Warlord: 1 + his guard of 4 = 5 ({Flow.BossReserve(warlord, W2B.real)})`)
	local unknown = W2B.level()
	unknown.stages[2].waves[2].boss.kind = "dragon"
	check(Flow.BossReserve(unknown, W2B.real) == 1 and Flow.BossReserve(level, nil) == 1, "an unknown kind, or no kinds at all: 1, the boss alone")
	local none = W2B.level()
	none.stages[2].waves[2].boss = nil
	check(Flow.BossReserve(none, W2B.real) == 0, "no stage with a boss: 0")
	local two = W2B.level()
	table.insert(two.stages[2].waves, { groups = {}, boss = { kind = "warlord", at = { 0, 0 }, valor = 5 } })
	check(Flow.BossReserve(two, W2B.real) == 13, "two bosses: the larger reserve (13), not their sum")
	local calls = {
		boss = { radius = 3, attacks = { { shape = "ring", reach = 14 }, { shape = "summon", reach = 60, count = 3, summon = "fodder" }, { shape = "summon", reach = 60, count = 12, summon = "fodder" }, { shape = "lob", reach = 60, count = 40 } } },
	}
	local own = W2B.level()
	own.stages[2].waves[2].boss.kind = "boss"
	check(Flow.BossReserve(own, calls) == 13, `of two summons the largest count (12), and a lob's count is no call: 13 ({Flow.BossReserve(own, calls)})`)

	print(" Plan: tents, stock, the population (L1b-W2-5, -6)")
	local plan = W2B.plan()
	local tents = plan.tents
	check(#tents == 2 and tents[1].zone == 1 and tents[2].zone == 2, "one tent per open camp with a stock, in the layout's order; none for the boss room's marker")
	local a = tents[1]
	check(table.concat(a.kinds, " ") == "fodder fodder brute", `A on Normal: its units in file order, the Hard slinger left out ({table.concat(a.kinds, " ")})`)
	check(#a.posts == #a.kinds and a.every == 6 and tents[2].every == 4, "kinds and posts paired, one post a body; each its own every")
	local def = a.def
	check(def.id == "A.tent" and def.camp == "A" and def.floor == 1 and def.floorY == 8 and def.posture == "tent" and def.radius == 5 and def.held == false, "its group: A.tent, camp A's floor and height, posture tent, the layout's radius, never held")
	check(#def.points == 1 and L1.same(def.points[1], vec(10, 8, 110)) and def.rect.x == 0 and def.rect.z == 100 and def.rect.hx == 30 and def.rect.hz == 30, "its point the marker's centre at the floor's height, its rect the camp's floor")
	check(L1B.units(def) == "fodder 2, brute 1", `its units the stock's ({L1B.units(def)})`)
	local onRing = true
	for _, post in a.posts do
		onRing = onRing and near(vec(post.at.X - 10, 0, post.at.Z - 110).Magnitude, 5, 1e-6) and near(post.at.Y, 8)
	end
	check(onRing, "every post on the ring of radius 5 round the marker, on the floor")
	local hard = W2B.plan(nil, nil, "hard")
	check(table.concat(hard.tents[1].kinds, " ") == "fodder fodder slinger brute" and #hard.tents[1].posts == 4, "on Hard the slinger joins, in file order")
	check(#hard.tents[2].kinds == 3 and #W2B.plan(nil, nil, "brutal").tents[2].kinds == 3, "and countMult (Hard 1.25, Brutal 1.5) never scales a tent: B's 3 stay 3")
	local dropped = W2B.level()
	dropped.camps[2].tent.units[1].minDifficulty = "hard"
	check(#W2B.plan(dropped).tents == 1 and W2B.plan(dropped).zones[2].tentStock == 0, "a tent whose units all drop on Normal is left out (tentStock 0)")
	local marker = W2B.level()
	marker.camps[3].tent = { every = 6, units = { { kind = "fodder", count = 2 } }, pace = { seconds = 25, lead = 0.15 } }
	check(#W2B.plan(marker).tents == 2, "a boss room's tent stock is never planned (Validate refuses it)")

	local zones = plan.zones
	check(zones[1].tentStock == 3 and zones[2].tentStock == 3 and zones[3].tentStock == 0, "tentStock: A 3, B 3, C 0")
	-- L1b-W4-30: a zone's stock is its residents only; Fielded adds what the tent sent.
	check(W2B.stock(zones[1].stock) == "fodder 9", `A's stock, its 9 resident fodder, not its tent's ({W2B.stock(zones[1].stock)})`)
	check(W2B.stock(zones[2].stock) == "brute 1, fodder 5, slinger 2", `B's: 5 fodder, a brute, 2 slingers, not its tent's 3 fodder ({W2B.stock(zones[2].stock)})`)
	check(W2B.stock(zones[3].stock) == "fodder 3", `C's, the boss room: its residents only ({W2B.stock(zones[3].stock)})`)
	check(W2B.stock(hard.zones[1].stock) == "fodder 9, slinger 1", `A on Hard: the gate's slinger joins, the tent's does not ({W2B.stock(hard.zones[1].stock)})`)
	check(plan.population == 74 and hard.population == 78 and W2B.plan(nil, nil, "brutal").population == 78, `population by hand: Normal 74, Hard 78, Brutal 78 ({plan.population}, {hard.population})`)
	check(W2B.plan(nil, nil, nil, false).population == 74 - 21 + 1, "without kinds the boss reserve is 1: 54")
	check(W2B.plan(nil, nil, nil, W2B.real).population == 74 - 21 + 13, "with the real kinds, 13: 66")
	local wave1 = L1B.plan()
	check(#wave1.tents == 0 and wave1.zones[1].tentStock == 0 and W2B.stock(wave1.zones[1].stock) == "fodder 9", "a level with no tent plans none; its zones' stock is their residents")
end
L1.group("l1b w2 planTests", W2B.planTests)

-- Advance: a tent holds its camp's clear ---------------------------------------------------------

function W2B.advanceTests(): ()
	print(" Advance: an open camp clears when every body of its floor is dead, its tent never waited for (L1b-W4-29)")
	local Flow = W2B.Flow
	local plan = W2B.plan()
	local state = Flow.Begin(plan)
	local function names(over: any): string
		return L1.names(L1B.advance(plan, state, over))
	end
	check(names({ aliveByFloor = { 1, 8, 3 } }) == "" and not state.done[1], "A with one body of its floor alive (wherever it stands): no campClear")
	local actions = L1B.advance(plan, state, { aliveByFloor = { 0, 8, 3 } })
	check(L1.names(actions) == "campClear" and L1.get(actions, "campClear").zone == 1 and state.cleared == 1, "A's floor at 0 with its whole tent stock unsent: one campClear, zone 1 (the stock is forfeit)")
	check(names({ aliveByFloor = { 0, 8, 3 } }) == "", "never twice")
	check(names({ aliveByFloor = { 0, 1, 3 } }) == "", "B with one tent body alive out on the road: held")
	check(names({ aliveByFloor = { 0, 0, 3 } }) == "campClear" and state.cleared == 2, "B at 0: it clears")
	local locked = Flow.Begin(plan)
	check(L1.names(L1B.advance(plan, locked, { aliveByFloor = { 9, 8, 0 } })) == "", "the boss room never clears this way, its own floor empty or not")

	print(" a skipped boss room's open carries skipped (no bonus)")
	local skip = Flow.Begin(plan)
	local road = Flow.Skip(plan, skip, "stage", 0, L1B.rules, { 1 })
	local gate = Flow.Skip(plan, skip, "stage", 1, L1B.rules, { 1 })
	local drop = Flow.Skip(plan, skip, "stage", 2, L1B.rules, { 1 })
	check(L1.names(road) == "move gate" and L1.names(gate) == "close wave", `the road's skip moves to the boss room and starts its countdown, the countdown's closes it ({L1.names(road)}; {L1.names(gate)})`)
	check(L1.get(drop, "open").skipped == true and L1.names(drop) == "drop boundary open end", `a fight's skip: drop, boundary, open marked skipped ({L1.names(drop)})`)
end
L1.group("l1b w2 advanceTests", W2B.advanceTests)

-- Combat: the clear bonus and the dead fraction ----------------------------------------------------

function W2B.combatTests(): ()
	print(" Combat.ClearBonus (L1b-W2-21), WaveStock and DeadFraction (L1b-W2-26)")
	local Combat = W2B.Combat
	local rewards = L1B.level().crowd.rewards
	local function bonus(stock: any, mult: number, share: number): string
		local cash, materials = Combat.ClearBonus(stock, rewards, mult, share)
		return `{cash}/{materials}`
	end
	-- The fixture's A on Normal: 11 fodder (100, 0) and a brute (2000, 6): 3100 cash, 6
	-- materials; a tenth: 310 and 0.6 -> 1.
	check(bonus({ fodder = 11, brute = 1 }, 1, 0.1) == "310/1", `the fixture's A on Normal: 310 cash, 1 material ({bonus({ fodder = 11, brute = 1 }, 1, 0.1)})`)
	-- Hard's rewardMult 2 and its slingers (500, 1): (1100 + 2000 + 1000) x 2 = 8200, (6 + 2) x 2 = 16.
	check(bonus({ fodder = 11, brute = 1, slinger = 2 }, 2, 0.1) == "820/2", `on Hard (x2, the slingers): 820, 1.6 -> 2 ({bonus({ fodder = 11, brute = 1, slinger = 2 }, 2, 0.1)})`)
	check(bonus({ fodder = 11, brute = 1, slinger = 2 }, 4, 0.1) == "1640/3", `on Brutal (x4): 1640, 3.2 -> 3 ({bonus({ fodder = 11, brute = 1, slinger = 2 }, 4, 0.1)})`)
	check(bonus({ fodder = 11, brute = 1 }, 1, 0) == "0/0" and bonus({}, 4, 0.1) == "0/0", "a share of 0, or a stock of nothing: 0, 0")
	check(bonus({ fodder = 1, ghost = 40 }, 1, 0.1) == "10/0", "an unpriced kind adds nothing")
	local half = { fodder = { cash = 5, materials = 1 } }
	local cash, materials = Combat.ClearBonus({ fodder = 1 }, half, 1, 0.5)
	check(cash == 3 and materials == 1, `rounded to the nearest, .5 away from 0: 2.5 -> 3, 0.5 -> 1 ({cash}, {materials})`)
	cash = Combat.ClearBonus({ fodder = 3 }, { fodder = { cash = 1, materials = 0 } }, 1, 0.1)
	check(cash == 0, `0.3 -> 0 ({cash})`)
	-- KillReward rounds each kill first: 1.4 x 3 = 4.2 -> 4 each, 12 for 3, 1.2 -> 1.
	cash = Combat.ClearBonus({ fodder = 3 }, { fodder = { cash = 1.4, materials = 0 } }, 3, 0.1)
	check(cash == 1, `each kill priced as KillReward prices it (4.2 -> 4), the bonus rounded once (1.2 -> 1) ({cash})`)

	local stock: any = {}
	local spec = { groups = { { kind = "fodder", count = 16 }, { kind = "brute", count = 2 }, { kind = "fodder", count = 16 } }, boss = nil }
	Combat.WaveStock(stock, spec, nil)
	check(W2B.stock(stock) == "brute 2, fodder 32", `WaveStock: every group of the wave by kind ({W2B.stock(stock)})`)
	Combat.WaveStock(stock, { groups = { { kind = "slinger", count = 2 } }, boss = nil }, "armoured")
	check(W2B.stock(stock) == "armoured 1, brute 2, fodder 32, slinger 2", `a merged wave adds to it, with the director's elite ({W2B.stock(stock)})`)
	Combat.WaveStock(stock, { groups = {}, boss = { kind = "colossus", at = { 14, 0 }, valor = 10 } }, nil)
	check(stock.colossus == nil and W2B.stock(stock) == "armoured 1, brute 2, fodder 32, slinger 2", "the boss wave adds nothing: the boss is not in the stock")

	local dead = Combat.DeadFraction
	check(dead(0, 0) == 0 and dead(0, 5) == 0 and dead(-3, 0) == 0, "nothing spawned: 0")
	check(dead(10, 10) == 0 and dead(10, 14) == 0, "all alive, or more alive than spawned: 0")
	check(near(dead(10, 3), 0.7) and dead(10, 0) == 1 and dead(10, -4) == 1, "7 of 10 dead: 0.7; none alive: 1; never over 1")
	-- The boss room's floor holds 12: 5 of them residents. The waves spawned 10: 3 of 10 dead.
	check(near(dead(10, 12 - 5), 0.3), "the residents left out: 12 alive less 5 grouped of 10 spawned is 0.3, not 0")
end
L1.group("l1b w2 combatTests", W2B.combatTests)

-- LevelGeometry: the tent marker -------------------------------------------------------------------

function W2B.worldTests(): ()
	print(" LevelGeometry: one tent marker per tent block (L1b-W2-9)")
	local Geo = W2B.Geo
	local pieces = Geo.Pieces(W2B.layout(), L1W.sizes, 600)
	local tents: { any } = {}
	for _, piece in pieces or {} do
		if piece.role == "tent" then
			table.insert(tents, piece)
		end
	end
	check(pieces ~= nil and #tents == 3, `one per camp with a tent block, the boss room's marker included ({#tents})`)
	local a = tents[1] or {}
	check(a.name == "Camp_A_Tent" and a.look == "tent" and a.collide == false and a.camp == "A", "named for its camp, look tent, walked through (collide false)")
	check(a.box ~= nil and L1W.is(a.box, 10, 12, 110, 4, 8, 4), `the block's own centre and size ({a.box and L1W.show(a.box)})`)
	local without = Geo.Pieces(L1B.layout(), L1W.sizes, 600)
	check(without ~= nil and pieces ~= nil and #without == #pieces - 3, "a camp with no tent block builds none")
	check(Geo.TentBox(L1B.layout().camps[1]) == nil, "TentBox: nil with no block")
	local flat = W2B.layout()
	flat.camps[2].tent.sy = 0
	local refused, why = Geo.Pieces(flat, L1W.sizes, 600)
	check(refused == nil and type(why) == "string" and string.find(why, "Camp_B_Tent", 1, true) ~= nil, `a tent block of height 0 refuses the layout, by name ({tostring(why)})`)

	print(" the shipped Forest Road (Config/Levels/1_ForestRoad.json, Layouts/Levels/ForestRoad.json)")
	local file = L1.real.file("forestRoad")
	local layout = L1.real.layouts.ForestRoad
	if file == nil or layout == nil then
		check(false, "the shipped Forest Road's level and layout are there")
		return
	end
	local shipped = Geo.Pieces(layout, L1.real.sizes(), L1.real.rules.maxParts)
	local markers, blocks = 0, 0
	for _, piece in shipped or {} do
		if piece.role == "tent" then
			markers += 1
			check(piece.collide == false and piece.look == "tent", `{piece.name}: a marker only`)
		end
	end
	for _, camp in layout.camps do
		if camp.tent ~= nil then
			blocks += 1
		end
	end
	local count = if shipped ~= nil then #shipped else -1
	local gate = if L1.real.gate.parts ~= nil then L1.real.gate.parts.ForestRoad else nil
	print(`   Forest Road: {count} Parts, {markers} tent markers`)
	check(shipped ~= nil and markers == blocks and markers == 3, `one marker per tent block (A, B and C's) ({markers})`)
	check(count > 0 and count <= L1.real.rules.maxParts and count == gate, `its Part count is Pieces', at most levels.maxParts, and check_levels.py's ({count}, {tostring(gate)})`)
end
L1.group("l1b w2 worldTests", W2B.worldTests)

-- The shipped files ----------------------------------------------------------------------------------

-- The population of a level file at one difficulty, counted here from the files as the contract
-- words it (L1b-W2-5), apart from StageFlow: residents, every open camp's tent stock, the boss
-- room's room over its own residents, and the boss reserve `reserve`.
function W2B.counted(file: any, layout: any, difficulty: string, reserve: number): (number, { [string]: number })
	local ranks = L1.real.ranks()
	local rank = ranks[difficulty] or 0
	local function fielded(units: any): number
		local bodies = 0
		for _, unit in units or {} do
			local needs = unit.minDifficulty
			if needs == nil or (ranks[needs] ~= nil and ranks[needs] <= rank) then
				bodies += unit.count
			end
		end
		return bodies
	end
	local locks: { [string]: boolean } = {}
	for _, camp in layout.camps do
		locks[camp.id] = camp.locks == true
	end
	local residents: { [string]: number } = {}
	local total = 0
	for _, camp in file.camps or {} do
		local bodies = 0
		for _, group in camp.residents or {} do
			bodies += fielded(group.units)
		end
		residents[camp.id] = bodies
		total += bodies
		if camp.tent ~= nil and not locks[camp.id] then
			total += fielded(camp.tent.units)
		end
	end
	local room = 0
	for _, stage in file.stages do
		if stage.kind == "camp" then
			room = math.max(room, (stage.maxAlive or file.crowd.maxAlive) - (residents[stage.zone] or 0))
		end
	end
	return total + room + reserve, residents
end

function W2B.realTests(): ()
	print(" the shipped Forest Road: Validate clean, the population and the clear bonus by count")
	local file = L1.real.file("forestRoad")
	local layout = L1.real.layouts.ForestRoad
	if file == nil or layout == nil then
		check(false, "the shipped Forest Road's level and layout are there")
		return
	end
	local resolved = L1.real.resolve("forestRoad")
	local level = resolved.level
	if level == nil then
		check(false, "the shipped Forest Road resolves")
		return
	end
	local ok, problems = pcall(W2B.Flow.Validate, level, layout, L1.real.kinds, L1.real.ranks(), L1.real.rules, FIXTURES.proving.crowd.maxAlive)
	check(ok and #problems == 0, `Validate finds nothing ({if ok then problems[1] or "none" else tostring(problems)})`)
	-- Its boss is the Colossus, which calls 12: the reserve is 13.
	check(W2B.Flow.BossReserve(level, L1.real.kinds) == 13, "its boss reserve is the Colossus's 13")
	for _, difficulty in L1.real.map.difficulties do
		if level.difficulties[difficulty] == nil then
			continue
		end
		local plan = L1.real.plan(level, layout, difficulty, L1.real.bounds(layout))
		local counted = W2B.counted(file, layout, difficulty, 13)
		print(`   {difficulty}: population {plan and plan.population or "none"}`)
		check(plan ~= nil and plan.population == counted and counted <= FIXTURES.proving.crowd.maxAlive, `{difficulty}: Plan's population is the one counted from the files, within crowd.maxAlive ({plan and plan.population}, {counted})`)
		if plan == nil then
			continue
		end
		check(#plan.tents == 2 and plan.tents[1].def.id == "A.tent" and plan.tents[2].def.id == "B.tent", `{difficulty}: two tents, A's and B's, none for the Chief's Clearing`)
		-- The clear bonus of A, priced kill by kill from its stock.
		local zone = plan.zones[1]
		local scales = level.difficulties[difficulty]
		local share = level.crowd.clearBonus.share
		local cash, materials = 0, 0
		for kind, count in zone.stock do
			local reward = level.crowd.rewards[kind]
			if reward ~= nil then
				cash += count * math.round(reward.cash * scales.rewardMult)
				materials += count * math.round(reward.materials * scales.rewardMult)
			end
		end
		local paid, paidMaterials = W2B.Combat.ClearBonus(zone.stock, level.crowd.rewards, scales.rewardMult, share)
		print(`   {difficulty}: Pickets' clear bonus {paid} cash, {paidMaterials} {level.material} (stock {W2B.stock(zone.stock)})`)
		check(paid == math.round(share * cash) and paidMaterials == math.round(share * materials) and paid > 0, `{difficulty}: Pickets' bonus with nothing sent is {share} of its residents ({paid}, {paidMaterials})`)
		local tentBodies = 0
		for _, unit in file.camps[1].tent.units do
			tentBodies += unit.count
		end
		check(zone.tentStock == #plan.tents[1].kinds and zone.tentStock <= tentBodies, `{difficulty}: Pickets' tentStock is its tent's stock ({zone.tentStock})`)
	end
end
L1.group("l1b w2 realTests", W2B.realTests)

-- The fix round (docs/prompts/l1b-w2-fix-round.md, B-2 to B-4) ------------------------------------

function W2B.fixTests(): ()
	print(" fix round B-2: a ring's posts on its floor at every difficulty, not only the highest")
	local has = L1.has
	local problems = W2B.problems
	local function count(list: { string }, text: string): number
		local found = 0
		for _, line in list do
			if string.find(line, text, 1, true) ~= nil then
				found += 1
			end
		end
		return found
	end
	-- A's tent: 2 fodder and 2 brutes on Normal (4 posts: north, west, south, east), and 2
	-- slingers more from Hard (6 posts, none due east). Round x 24 at radius 4 the Normal east
	-- post is at x 28, past A's floor (ends x 30) less the brute's 2.2 = 27.8; Hard's easternmost
	-- is 24 + 4 sin 60 = 27.46, inside it.
	local tentLevel, tentLayout = W2B.level(), W2B.layout()
	tentLevel.camps[1].tent.units = { { kind = "fodder", count = 2 }, { kind = "brute", count = 2 }, { kind = "slinger", count = 2, minDifficulty = "hard" } }
	tentLayout.camps[1].tent.x = 24
	tentLayout.camps[1].tent.radius = 4
	local list = problems(tentLevel, tentLayout)
	check(has(list, "group A.tent: ring post 4 lies off its floor less 2.2"), `a tent ring that only Normal's 4 posts push past the floor is refused ({list[1] or "no problem"})`)
	local easier = W2B.layout()
	easier.camps[1].tent.x = 23.5
	easier.camps[1].tent.radius = 4
	check(not has(problems(tentLevel, easier), "ring post"), "(round x 23.5 Normal's east post is at 27.5: legal)")
	-- A's fire1: 4 fodder on Normal (west post at x - 4), 2 slingers more from Hard (6 posts,
	-- westernmost x - 3.46). Round x -25: Normal's west post at -29 is past -30 + 1.3 = -28.7.
	local fireLevel, fireLayout = W2B.level(), W2B.layout()
	table.insert(fireLevel.camps[1].residents[1].units, { kind = "slinger", count = 2, minDifficulty = "hard" })
	fireLayout.camps[1].spots[1].points[1].x = -25
	list = problems(fireLevel, fireLayout)
	check(has(list, "group A.fire1: post 2 lies off its floor less 1.3"), `a resident fire that only Normal's posts push past the floor is refused ({list[1] or "no problem"})`)
	-- A ring past the floor at every difficulty is told of once, at the highest.
	local always = W2B.layout()
	always.camps[1].tent.x = 25
	always.camps[1].tent.z = 100
	always.camps[1].tent.radius = 4.9
	list = problems(nil, always)
	check(count(list, "group A.tent: ring post") == 1 and has(list, "lies off its floor less 2.2"), `a ring off its floor at every difficulty is one line, not one a difficulty ({count(list, "group A.tent: ring post")})`)
	-- fire1's 4 fodder at every difficulty, round x -27: the west post at -31 on all three.
	local fireAlways = W2B.layout()
	fireAlways.camps[1].spots[1].points[1].x = -27
	list = problems(nil, fireAlways)
	check(count(list, "group A.fire1: post") == 1, `a fire off its floor at every difficulty is one line ({count(list, "group A.fire1: post")})`)

	print(" fix round B-3: a tent body sent while its camp fights is roused until its group is up")
	local Owes = W2B.Flow.TentOwesRouse
	check(Owes(true, true, false) == true, "owed, the camp busy, the group walking home or resting: still owed")
	check(Owes(true, true, true) == false, "the group is up (rise or fight): paid")
	check(Owes(true, false, false) == false, "the camp has gone quiet: nothing to join, dropped")
	check(Owes(false, true, false) == false, "never owed: stays not owed")

	print(" fix round B-4: a tent body steps out of its marker's side, facing its post")
	local Geo = W2B.Geo
	local box = { x = 10, y = 12, z = 110, sx = 10, sy = 8, sz = 10 }
	local x, z = Geo.TentDoor(box, 20, 110, 1.3)
	check(near(x, 16.3) and near(z, 110), `a post due east at 10: the east wall at 15, 1.3 clear (16.3, 110) ({x}, {z})`)
	x, z = Geo.TentDoor(box, 10 + 10 / math.sqrt(2), 110 - 10 / math.sqrt(2), 0)
	check(near(x, 15) and near(z, 105), `a post to the north-east: the box's corner (15, 105) ({x}, {z})`)
	x, z = Geo.TentDoor(box, 10 + 10 / math.sqrt(2), 110 - 10 / math.sqrt(2), 5)
	check(near(x, 10 + 10 / math.sqrt(2)) and near(z, 110 - 10 / math.sqrt(2)), "a clearance that would pass the post stops on the post")
	x, z = Geo.TentDoor(box, 13, 110, 1)
	check(x == 13 and z == 110, "a post inside the footprint is its own door")
	x, z = Geo.TentDoor(box, 10, 110, 1)
	check(x == 10 and z == 110, "a post at the centre is its own door")
	x, z = Geo.TentDoor(box, 20, 110, -3)
	check(near(x, 15), "a negative clearance is none: the wall itself")
	local long = { x = 0, y = 0, z = 0, sx = 14, sy = 10, sz = 6 }
	x, z = Geo.TentDoor(long, 0, -10, 0)
	local x2 = Geo.TentDoor(long, 10, 0, 0)
	check(near(x, 0) and near(z, -3) and near(x2, 7), `a 14 x 6 box: its north wall at z -3, its east wall at x 7 ({z}, {x2})`)
	local plan = W2B.plan()
	local a = plan.tents[1]
	check(#a.doors == #a.posts, "Plan pairs a door with every post")
	-- A's marker is 4 x 4 round (10, 110), its ring 5: post 1 (fodder) due north at (10, 105).
	check(L1.same(a.doors[1], vec(10, 8, 110 - 2 - 1.3)), "post 1 (a fodder due north): its door 1.3 past the north wall, on the floor")
	-- Post 3 (the brute) at bearing 240: out along (sin 60, cos 60), the east wall at 2 / sin 60.
	local d3 = a.doors[3]
	local p3 = a.posts[3].at
	local along = vec(d3.X - 10, 0, d3.Z - 110)
	local toPost = vec(p3.X - 10, 0, p3.Z - 110)
	check(near(along.Magnitude, 2 / math.sin(math.pi / 3) + 2.2, 1e-6) and near(along.X * toPost.Z - along.Z * toPost.X, 0, 1e-6) and along.X * toPost.X > 0 and near(d3.Y, 8), `post 3 (a brute, south-east): its door on the line to its post, the brute's 2.2 past the wall ({along.Magnitude})`)
	local bare = W2B.plan(nil, nil, nil, false)
	check(L1.same(bare.tents[1].doors[1], vec(10, 8, 108)), "Plan without kinds: the door on the wall itself")
end
L1.group("l1b w2 fixTests", W2B.fixTests)

-- SpawnSeed (the ui-engineer's pure module, tested here on the lead's routing) -------------------

function W2B.seedTests(): ()
	print(" SpawnSeed: a spawn info's body, read off the network (L1b-W2-11)")
	local Seed = load("SpawnSeed")
	local at = vec(4, 8, -2)
	local p, y, s = Seed.Read({ id = 1, kind = "fodder", maxHp = 10, at = at, yaw = 1.5, state = "rest" })
	check(p == at and y == 1.5 and s == "rest", "SpawnSeed: a resting body seeds where it rests, seated")
	local _, _, s2 = Seed.Read({ at = at, state = "windup" })
	check(s2 == "idle", "SpawnSeed: an attack state seeds standing")
	check(Seed.Read({ at = at, state = "dead" }) == nil, "SpawnSeed: a dead body is not seeded")
	check(Seed.Read({ id = 1, kind = "fodder" }) == nil, "SpawnSeed: no at, no seed (the range)")
	local _, y2 = Seed.Read({ at = at, yaw = math.huge })
	check(y2 == 0, "SpawnSeed: a bad yaw faces 0")
	local _, _, s3 = Seed.Read({ at = at, state = "move" })
	local _, _, s4 = Seed.Read({ at = at, state = "rise" })
	check(s3 == "move" and s4 == "rise", "SpawnSeed: walking and rising seed as they are")
	check(Seed.Read({ at = { X = 1, Y = 2, Z = 3 } }) == nil and Seed.Read({ at = vec(0 / 0, 0, 0) }) == nil, "SpawnSeed: an at that is no Vector3, or not finite, seeds nothing")
end
L1.group("l1b w2 seedTests", W2B.seedTests)

-- L1b Wave 4 (L1b-W4-32): touch auto-target takes every awake camp body wherever the player
-- stands; never a resting group's body, never a camp body in the countdown (CampAim).
do
	local Aim = load("CampAim")
	check(Aim.Takes(false, false, "travel"), "CampAim: a body with no camp floor is always taken")
	check(
		Aim.Takes(false, true, "gate"),
		"CampAim: a body with no camp floor is taken even in the gate, resting or not"
	)
	check(
		Aim.Takes(true, false, "travel"),
		"CampAim: an awake group's body is taken, wherever the player stands"
	)
	check(
		Aim.Takes(true, false, "fight"),
		"CampAim: after the close an awake body in the boss room is taken"
	)
	check(
		not Aim.Takes(true, true, "travel"),
		"CampAim: a resting group's body is never taken (the sneak on touch)"
	)
	check(
		not Aim.Takes(true, false, "gate"),
		"CampAim: in the gate no camp body is taken, awake or not"
	)
	check(
		not Aim.Takes(true, true, "gate"),
		"CampAim: in the gate a resting camp body is not taken either"
	)
	-- The fix round's R13 (the ui-engineer's cases): touch auto-fire holds while a refused body is
	-- on the shot's line within its hits (CampAim.ShotSpares).
	check(Aim.ShotSpares(nil, {}, 1), "CampAim R13: no refused body on the line, the shot fires")
	check(
		not Aim.ShotSpares(10, {}, 5),
		"CampAim R13: the first body on the line is refused, the shot holds"
	)
	check(
		Aim.ShotSpares(20, { 10 }, 1),
		"CampAim R13: a one-hit shot stops in the awake body before the refused one"
	)
	check(
		not Aim.ShotSpares(20, { 10 }, 5),
		"CampAim R13: a pierce through the awake raider into a resting member holds the shot"
	)
	check(
		Aim.ShotSpares(20, { 10, 12 }, 2),
		"CampAim R13: the shot spends its pierce on awake bodies before the refused one"
	)
	check(
		not Aim.ShotSpares(20, { 10, 30 }, 2),
		"CampAim R13: an awake body behind the refused one does not stop the shot"
	)
	check(
		not Aim.ShotSpares(10, { 10 }, 1),
		"CampAim R13: a tie between an awake and a refused body holds the shot"
	)
	check(
		Aim.ShotSpares(20, { 10 }, nil) and Aim.ShotSpares(20, { 10 }, 0),
		"CampAim R13: a missing or zero pierce is one hit"
	)
	check(
		Aim.ShotSpares(20, { 10, 12 }, 2.9),
		"CampAim R13: a fractional pierce is floored, as WeaponService's pierceOf"
	)
	check(
		not Aim.ShotSpares(10, {}, nil) and not Aim.ShotSpares(10, {}, 0),
		"CampAim R13: a missing or zero pierce still hits the refused body first in line"
	)
	-- The fix-diff round's R17 (the ui-engineer's cases): a shot that bursts where it stops is held
	-- while a refused body lies within the burst of the predicted stop span (CampAim.StopSpan,
	-- CampAim.BurstSpares).
	local f1, t1 = Aim.StopSpan({}, nil, 100)
	check(f1 == 0 and t1 == 100, "CampAim R17: no takeable body on the line, the shot may stop anywhere to its range")
	local f2, t2 = Aim.StopSpan({ 10 }, nil, 100)
	check(f2 == 10 and t2 == 10, "CampAim R17: a one-hit shell stops in the first takeable body")
	local f3, t3 = Aim.StopSpan({ 30, 10, 20 }, 2, 100)
	check(f3 == 20 and t3 == 20, "CampAim R17: a pierce stops in the body that spends it, nearest first")
	local f4, t4 = Aim.StopSpan({ 10, 20 }, 5, 110)
	check(f4 == 20 and t4 == 110, "CampAim R17: a pierce left over flies on from the last body it passes to its range")
	local f5, t5 = Aim.StopSpan({ 10 }, 0, 100)
	check(f5 == 10 and t5 == 10, "CampAim R17: a zero pierce stops in the first body")
	local f6, t6 = Aim.StopSpan({ 10, 20 }, 1.9, 100)
	check(f6 == 10 and t6 == 10, "CampAim R17: a fractional pierce is floored for the stop too")
	check(not Aim.BurstSpares(20, 20, 20, 5, 10), "CampAim R17: a refused body beside the stop point holds the shot (Launcher A)")
	check(not Aim.BurstSpares(20, 20, 12, 0, 10), "CampAim R17: a refused body on the line just before the stop is inside the burst")
	check(Aim.BurstSpares(20, 20, 35, 0, 10), "CampAim R17: a refused body beyond the burst does not hold the shot")
	check(not Aim.BurstSpares(20, 20, 28, 6, 10), "CampAim R17: a refused body exactly at the burst's reach holds the shot (a tie)")
	check(Aim.BurstSpares(20, 20, 28, 6, 9.99), "CampAim R17: just outside the reach, diagonally, the shot fires")
	check(not Aim.BurstSpares(20, 110, 60, 8, 10), "CampAim R17: a passing shot's burst may land anywhere on its span: a body beside the middle holds it")
	check(Aim.BurstSpares(20, 110, 5, 0, 10), "CampAim R17: a body behind the span's start, past the reach, is spared")
	check(Aim.BurstSpares(20, 110, 125, 0, 10), "CampAim R17: a body past the range, beyond the reach, is spared")
	check(not Aim.BurstSpares(20, 110, 115, 0, 10), "CampAim R17: a body past the range but within the reach of its end holds the shot")
end

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
