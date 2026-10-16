-- Scratch tests for P4 Stop 2, the Colossus (never shipped): appended after tests_w2.luau by
-- run_harness.py, so every local of the two earlier files is in scope. Each group runs in its
-- own function, and this file adds as few top-level locals as it can (the 200-local limit).

print("Stop 2")

local S2: any = { Shapes = load("HitShapes"), Tuning = load("Tuning") }

do
	local kinds = config.crowd.kinds
	local function ringAttack(cooldown: number?): any
		return { shape = "ring", reach = 14, windup = 1.0, recover = 1.6, damage = 26, knockback = 24, launch = 3, radius = 26, speed = 34, width = 3, height = 4, cooldown = cooldown, interrupt = "none" }
	end
	local function summonAttack(): any
		return { shape = "summon", reach = 60, windup = 1.4, recover = 1.2, damage = 0, count = 12, summon = "fodder", radius = 12, cooldown = 18, interrupt = "none" }
	end
	local function barrage(): any
		return { shape = "lob", reach = 42, windup = 0.5, recover = 3.0, damage = 18, knockback = 14, launch = 3, radius = 5, seconds = 1.4, height = 4, count = 5, spread = 14, interrupt = "stagger" }
	end
	local function giant(extra: any): any
		local def: any = { radius = 4, headRadius = 1.6, height = 14, speed = 0, hp = 1000, armor = 0, knockbackMult = 0 }
		for key, value in extra do
			def[key] = value
		end
		return def
	end
	-- The lead's shape, on numbers that fall on the 15 Hz grid where a test reads a state's length.
	kinds.colossus = giant({
		speed = 7, hp = 6000, brain = "rush", perPlayer = 1, boss = true, name = "Colossus",
		enrage = { at = 0.5, windupScale = 0.75, recoverScale = 0.6, chain = 2 },
		attacks = {
			ringAttack(6),
			{ shape = "lane", reach = 40, windup = 1.0, recover = 2.0, damage = 30, knockback = 36, launch = 3, range = 44, width = 10, speed = 60, height = 6, cooldown = 8, interrupt = "none" },
			summonAttack(),
			{ shape = "lob", reach = 60, windup = 0.8, recover = 1.4, damage = 18, knockback = 14, launch = 3, radius = 5, seconds = 1.6, count = 5, spread = 14, height = 4, cooldown = 10, enraged = true, interrupt = "none" },
		},
	})
	-- One attack each, so a case meets it alone. `ringer` and `herald` are no boss: ruling 22.
	kinds.ringer = giant({ brain = "rush", attacks = { ringAttack(nil) } })
	kinds.ringBoss = giant({ brain = "rush", boss = true, attacks = { ringAttack(nil) } })
	kinds.caller = giant({ brain = "rush", boss = true, attacks = { summonAttack() } })
	kinds.herald = giant({ brain = "rush", attacks = { summonAttack() } })
	kinds.recaller = giant({ brain = "rush", boss = true, attacks = { summonAttack() } })
	kinds.recaller.attacks[1].cooldown = 3
	kinds.bomber = { radius = 1.4, headRadius = 0.7, height = 5, speed = 0, hp = 60, armor = 0, knockbackMult = 0.8, brain = "keepAway", bandMin = 22, bandMax = 40, attacks = { barrage() } }
	kinds.bomberBoss = { radius = 1.4, headRadius = 0.7, height = 5, speed = 0, hp = 60, armor = 0, knockbackMult = 0.8, brain = "keepAway", bandMin = 22, bandMax = 40, boss = true, attacks = { barrage() } }
	kinds.titan = giant({ speed = 6, hp = 10000 })
	kinds.pawn = { radius = 1.3, headRadius = 0.7, height = 5, speed = 12, hp = 40, armor = 0, knockbackMult = 1.0 }
	kinds.bulwark = { radius = 1.7, headRadius = 0.8, height = 6.5, speed = 9, hp = 160, armor = 5, knockbackMult = 0, plate = 90 }
end

-- Steps until the next step is the first whose clock is at or after `at`.
function S2.runTo(at: number): ()
	while fakeNow + DT < at - 1e-9 do
		step2()
	end
end

-- The changes of (state, attack) an enemy's snapshots show over `count` steps, each with the
-- stamp of the first snapshot that showed it.
function S2.trace(id: number, count: number): { any }
	local marks = {}
	local last = ""
	for _ = 1, count do
		step2()
		local entry = seen(id)
		local key = entry.state .. entry.attack
		if key ~= last then
			last = key
			table.insert(marks, { state = entry.state, attack = entry.attack, at = stamp(), position = entry.position })
		end
	end
	return marks
end

function S2.names(marks: { any }): string
	local out = {}
	for _, mark in marks do
		table.insert(out, mark.state .. mark.attack)
	end
	return table.concat(out, " ")
end

function S2.hurtsOf(list: { any }, userId: number): { any }
	local out = {}
	for _, fx in list do
		if fx.kind == "hurt" and fx.userId == userId then
			table.insert(out, fx)
		end
	end
	return out
end

-- A lob's landing: the Vitals frames up to a little past `at` + lag.
function S2.land(at: number): ()
	while fakeNow < at + LAG + 0.05 do
		advance(1 / 60)
	end
	gather()
end

function S2.chooseTests(): ()
	print(" choosing an attack")
	local kinds = config.crowd.kinds
	local function blow(reach: number, cooldown: number?, enraged: boolean?): any
		return { shape = "arc", reach = reach, windup = 0.2, recover = 0.2, damage = 1, range = 5, arcDegrees = 120, height = 5, cooldown = cooldown, enraged = enraged, interrupt = "none" }
	end
	local function still(attacks: { any }, enrage: any?): any
		return { radius = 1.3, headRadius = 0.7, height = 5, speed = 0, hp = 100, armor = 0, knockbackMult = 1, brain = "rush", attacks = attacks, enrage = enrage }
	end
	local function arena(kind: string, userId: number, distance: number): (any, any, any)
		local sim = newSim()
		sim.now = 5
		local target = { userId = userId, position = vec(0, 3, 0) }
		table.insert(sim.targets, target)
		local body = spawn(sim, kind, 0, distance)
		body.mind.bornAt = 0
		return sim, body, target
	end
	local function run(sim: any, seconds: number): ()
		for _ = 1, math.floor(15 * seconds + 0.5) do
			stepSim(sim)
		end
	end
	local function list(sim: any, from: number?): string
		local out = {}
		for index = from or 1, #sim.strikes do
			table.insert(out, tostring(sim.strikes[index].attack))
		end
		return table.concat(out, "")
	end

	-- Three attacks: 1 and 3 always ready, 2 on a two-second cooldown. All in reach.
	kinds.chooser = still({ blow(10, nil), blow(10, 2.0), blow(30, nil) })
	local sim, _body, target = arena("chooser", 81, 5)
	run(sim, 8)
	-- The rule, written again here: among the ready ones that are not the last, the oldest impact.
	local used: { [number]: number } = {}
	local previous = 0
	local agrees = #sim.strikes >= 12
	local twice = false
	local gapsOfTwo: { number } = {}
	for _, strike in sim.strikes do
		local chosenAt = strike.at - 0.2
		local best = 0
		local bestAt = math.huge
		local again = false
		for index = 1, 3 do
			if index ~= 2 or used[2] == nil or chosenAt >= used[2] + 2.0 - 1e-6 then
				if index == previous then
					again = true
				elseif (used[index] or -math.huge) < bestAt then
					best = index
					bestAt = used[index] or -math.huge
				end
			end
		end
		if best == 0 and again then
			best = previous
		end
		agrees = agrees and best == strike.attack
		twice = twice or strike.attack == previous
		if strike.attack == 2 and used[2] ~= nil then
			table.insert(gapsOfTwo, strike.at - used[2])
		end
		used[strike.attack] = strike.at
		previous = strike.attack
	end
	check(string.sub(list(sim), 1, 3) == "123", `attacks never used are taken in the list's order ({list(sim)})`)
	check(agrees, "among the attacks off cooldown and in reach, the one used longest ago is chosen")
	check(not twice, "never the same one twice running while another is ready")
	local cooled = #gapsOfTwo >= 2
	for _, gap in gapsOfTwo do
		cooled = cooled and gap >= 2.2 - 1e-6 and gap < 2.8
	end
	check(cooled, `a cooldown runs from that attack's impact: it is chosen again at the first choice 2 s after it, never before ({#gapsOfTwo} gaps)`)
	-- Only attack 3 reaches 20 studs.
	local had = #sim.strikes
	target.position = vec(0, 3, -15)
	run(sim, 0.7)
	had = #sim.strikes
	run(sim, 3)
	local far = list(sim, had + 1)
	check(#far >= 4 and far == string.rep("3", #far), `an attack out of reach is never chosen, and the only one in reach repeats ({far})`)

	-- A windup that was cancelled never reached its impact, yet it is not started again at once.
	local function jab(): any
		return { shape = "arc", reach = 10, windup = 0.4, recover = 0.2, damage = 1, range = 5, arcDegrees = 120, height = 5, interrupt = "stagger" }
	end
	kinds.fickle = still({ jab(), jab() })
	local fickle: any
	sim, fickle = arena("fickle", 88, 5)
	run(sim, 0.2)
	local first = fickle.mind.attack
	hit(sim, fickle, 1)
	local cancelled = fickle.mind.phase == "recover"
	local nextOne = 0
	for _ = 1, 30 do
		stepSim(sim)
		if fickle.mind.phase == "windup" then
			nextOne = fickle.mind.attack
			break
		end
	end
	check(first == 1 and cancelled and nextOne == 2 and #sim.strikes == 0, "not the same one twice running, also after a windup that was cancelled: the other attack is taken")

	-- One attack with a cooldown waits for it.
	kinds.patient = still({ { shape = "lunge", reach = 4.5, windup = 0.5, recover = 1.5, damage = 8, range = 5, width = 3, height = 5, cooldown = 3, interrupt = "stagger" } })
	sim = arena("patient", 82, 4)
	run(sim, 9)
	local gap = if #sim.strikes >= 2 then sim.strikes[2].at - sim.strikes[1].at else 0
	check(#sim.strikes >= 2 and gap >= 3.5 - 1e-6 and gap < 3.5 + DT, `a single attack obeys its cooldown too: the next windup starts 3 s after the impact (impacts {string.format("%.3f", gap)} s apart, 2.2 without it)`)

	-- An `enraged` attack waits for the second phase, which is read off the health byte.
	kinds.phased = still({ blow(10, nil), blow(10, nil, true) }, { at = 0.5, windupScale = 0.5, recoverScale = 0.5, chain = 1 })
	local body: any
	sim, body = arena("phased", 83, 5)
	body.maxHp = 1000
	body.hp = 1000
	run(sim, 3)
	check(#sim.strikes >= 4 and list(sim) == string.rep("1", #sim.strikes), "an `enraged` attack is never chosen in the first phase")
	had = #sim.strikes
	body.hp = 499
	run(sim, 3)
	check(list(sim, had + 1) == string.rep("1", #sim.strikes - had), "a share of 0.499 is 128/255 on the wire, above 0.5: not enraged (the server asks the byte the client reads)")
	had = #sim.strikes
	body.hp = 498
	run(sim, 3)
	check(string.find(list(sim, had + 1), "2") ~= nil, `a share of 0.498 is 127/255, under 0.5: enraged, and the attack unlocks ({list(sim, had + 1)})`)
	sim, body = arena("phased", 84, 5)
	body.maxHp = 1000
	body.hp = 100
	body.plate = 50
	run(sim, 3)
	check(#sim.strikes >= 4 and list(sim) == string.rep("1", #sim.strikes), "under a plate the bar is the plate's: no second phase")

	-- The chain and the scales, on the brain alone.
	kinds.soloist = still({ { shape = "arc", reach = 10, windup = 0.4, recover = 1.2, damage = 1, range = 5, arcDegrees = 120, height = 5, interrupt = "none" } }, { at = 0.5, windupScale = 0.5, recoverScale = 0.5, chain = 3 })
	sim = arena("soloist", 85, 5)
	run(sim, 6)
	local calm = #sim.strikes >= 3
	for index = 2, #sim.strikes do
		calm = calm and near(sim.strikes[index].at - sim.strikes[index - 1].at, 1.8, 1e-6)
	end
	check(calm, "before the second phase: windup, attack, recover, every time (impacts 0.4 + 0.2 + 1.2 apart)")
	sim, body = arena("soloist", 86, 5)
	body.hp = 40
	run(sim, 6)
	local times = sim.strikes
	check(#times >= 7 and near(times[2].at - times[1].at, 0.4, 1e-6) and near(times[3].at - times[2].at, 0.4, 1e-6), "enraged: `chain` attacks follow each other with no recover between, on windups x windupScale (0.2 + 0.2 apart)")
	check(#times >= 7 and near(times[4].at - times[3].at, 1.0, 1e-6) and near(times[5].at - times[4].at, 0.4, 1e-6) and near(times[7].at - times[6].at, 1.0, 1e-6), "the chain's last attack recovers in full, x recoverScale (0.2 + 0.6 + 0.2), and the next chain is three again")
	kinds.soloist.attacks[1].cooldown = 5
	sim, body = arena("soloist", 87, 5)
	body.hp = 40
	run(sim, 12)
	check(#sim.strikes >= 2 and sim.strikes[2].at - sim.strikes[1].at >= 5.2 - 1e-6, "a chain follows only with an attack that can start at once: with none ready the body recovers")
	check(body.mind.phase ~= "attack", "(and it is not left in its attack state)")
end
S2.chooseTests()

function S2.ringTests(): ()
	print(" ring")
	-- A ringer at (0, 0, 12) winds up on the first player at (0, 3, 0); returns its id and T.
	local function wind(kind: string?): (number, number)
		local id = Crowd.Spawn(kind or "ringer", vec(0, 0, 12), "fight")
		waitFor(id, "windup", 40)
		return id, stamp() + 1.0
	end
	-- The same, stepped to the frame of the impact and the ringer killed: the ring travels on.
	local function slam(): number
		local id, T = wind()
		S2.runTo(T)
		step2()
		kill(id)
		return T
	end

	fresh()
	local boss, T = wind()
	local home = Crowd.Get(boss).position
	local marks = S2.trace(boss, 6)
	S2.runTo(T)
	local marksAt = S2.trace(boss, 5)
	local reached = T + (12 - 1.5) / 34
	S2.runTo(reached + LAG)
	local ringStrike = struck[1]
	check(#struck == 1 and ringStrike.def.shape == "ring" and near(ringStrike.at, T, 1e-9) and ringStrike.bodyId == boss, "the ring leaves at the windup's first stamp + windup, and names its body")
	check(near(ringStrike.origin.X, 0) and near(ringStrike.origin.Z, 12) and near(ringStrike.aim.Z, 0), "from where the body stands, aimed at where its target stood when the windup began")
	check(S2.names(marks) == "windup1" and S2.names(marksAt) == "attack1 recover1" and near(marksAt[2].at - marksAt[1].at, 0.2, 1e-9), `the snapshot shows windup, then attack for strikeSeconds, then recover, with the attack's index ({S2.names(marksAt)})`)
	check(humanoid.Health == 130 and #log == 0, "nothing is decided before the front reached them a lag ago (it is tested against where it was)")
	step2()
	local hurts = of(log, "hurt")
	check(humanoid.Health == 104 and #hurts == 1 and hurts[1].amount == 26 and hurts[1].enemyKind == "ringer", "then the front lands: 130 -> 104")
	check(near(hurts[1].push.X, 0) and near(hurts[1].push.Z, -24) and hurts[1].launch == 3, "pushed outward from where it left, and launched")
	check(seen(boss).state == "recover" and (Crowd.Get(boss).position - home).Magnitude == 0, "the body stays where it is and is already recovering: the ring travels on by itself")
	kill(boss)
	step2(20)
	check(#of(log, "hurt") == 1 and humanoid.Health == 104, "at most once per ring per player, and the ring outlives a ringer that is no boss (ruling 22)")
	check(#of(log, "enemyShot") == 0 and #of(log, "area") == 0 and rays == 0, "no effect but `hurt` and no ray: the ring is drawn from the snapshot")
	check(Field.Busy() == false, "and its record is gone when it has run")

	-- A jump clears it; a hop under its height does not.
	fresh()
	T = slam()
	root.Position = vec(0, 3 + 4.5, 0)
	S2.runTo(T + (12 + 1.5) / 34 + LAG + 3 * DT)
	root.Position = vec(0, 3, 0)
	step2(12)
	check(humanoid.Health == 130 and #log == 0, "feet above its height while the front passes: a jump clears the ring, and landing behind it is safe")
	fresh()
	T = slam()
	root.Position = vec(0, 3 + 3.5, 0)
	step2(12)
	check(humanoid.Health == 104, "feet under its height: hit")
	fresh()
	T = slam()
	root.Position = vec(0, 3 - 8, 0)
	step2(12)
	check(humanoid.Health == 130 and #log == 0, "R15: its height is measured from the crowd's floor, above and below: feet 8 under the floor are missed")

	-- The front is `width` thick: its leading edge is what arrives, and landing inside the band
	-- is still a hit.
	fresh()
	T = slam()
	root.Position = vec(0, 3, 1)
	step2(5)
	check(humanoid.Health == 130, "11 studs out, five steps on: the leading edge was not there yet a lag ago")
	step2()
	check(humanoid.Health == 104, "the sixth step: it was (width / 2 ahead of the front's middle, which was not)")
	for _, landsOn in { 7, 8 } do
		fresh()
		T = slam()
		root.Position = vec(0, 3 + 6, 2.5)
		step2(landsOn - 1)
		root.Position = vec(0, 3, 2.5)
		step2(6)
		if landsOn == 7 then
			check(humanoid.Health == 104, "9.5 studs out, landing while the band is still over that spot (its middle has passed, its trailing edge has not): hit")
		else
			check(humanoid.Health == 130 and #log == 0, "landing one step later, behind the band: clear")
		end
	end

	-- Its reach.
	fresh()
	T = slam()
	root.Position = vec(0, 3, -15)
	step2(20)
	check(humanoid.Health == 130 and #log == 0, "outside its radius (27 of 26): never reached, and walking out is no dodge")
	fresh()
	T = slam()
	root.Position = vec(0, 3, -13.9)
	reached = T + (25.9 - 1.5) / 34
	S2.runTo(reached + LAG)
	check(humanoid.Health == 130, "near its edge (25.9 of 26) the front arrives late: not yet")
	step2()
	check(humanoid.Health == 104, "and then it does: the front is tested where it is, stud by stud")

	-- Two players, each pushed their own way.
	fresh()
	join2(vec(10, 3, 12))
	T = slam()
	step2(12)
	local mine = S2.hurtsOf(log, 7)
	local theirs = S2.hurtsOf(log, 8)
	check(#mine == 1 and #theirs == 1 and humanoid.Health == 104 and humanoid2.Health == 104, "everyone it passes is hit once")
	check(near(theirs[1].push.X, 24) and near(theirs[1].push.Z, 0) and near(mine[1].push.Z, -24), "each pushed outward from the ring's origin")
	leave2()

	-- I-frames, and ruling 26.
	fresh()
	T = slam()
	reached = T + (12 - 1.5) / 34
	iframes.from = reached - 0.01
	iframes.untilClock = reached + 0.05
	step2(15)
	hurts = of(log, "hurt")
	check(humanoid.Health == 130 and #hurts == 1 and hurts[1].dodged == true and hurts[1].amount == 0, "an i-frame while the front passes: one `dodged`, and the ring does not come back for them")
	fresh()
	T = slam()
	root.Position = vec(0, 3, -15)
	local passes = T + 12 / 34
	iframes.from = passes - 0.02
	iframes.untilClock = passes + 0.2
	step2(20)
	hurts = of(log, "hurt")
	check(humanoid.Health == 130 and #hurts == 1 and hurts[1].dodged == true, "ruling 26: its target, out of its reach under an i-frame when the front passes where they stood: dodged")
end
S2.ringTests()

function S2.summonTests(): ()
	print(" summon")
	local function expected(centre: any, yaw: number, index: number, count: number): any
		-- No place straight behind the summoner: an even count is turned half a step.
		local angle = yaw + (index - 1 + (if count % 2 == 0 then 0.5 else 0)) / count * 2 * math.pi
		return vec(centre.X - math.sin(angle) * 12, 0, centre.Z - math.cos(angle) * 12)
	end

	fresh()
	Vitals.ToggleGod(player)
	local boss = Crowd.Spawn("caller", vec(30, 0, 40), "fight")
	check(waitFor(boss, "windup", 40) and seen(boss).attack == 1, "a caller winds up from 50 studs")
	local T = stamp() + 1.4
	local yaw = seen(boss).yaw
	S2.runTo(T)
	local announced = #risen
	step2()
	local born = fakeNow
	local placed = Crowd.AliveCount() == 13 and #struck == 0
	for index = 1, 12 do
		local view = Crowd.Get(boss + index)
		placed = placed and view ~= nil and view.kind == "fodder" and (view.position - expected(vec(30, 0, 40), yaw, index, 12)).Magnitude < 1e-6
	end
	check(placed, "at the impact `count` bodies of the `summon` kind stand evenly on a circle of `radius` round the summoner, turned from its facing so that none is straight behind it")
	check(#risen == announced, "they are raised after the step, so their CrowdSpawn waits for the next batch")
	step2()
	local told = #risen == announced + 12
	for index = 1, 12 do
		local info = risen[announced + index]
		told = told and info ~= nil and info.id == boss + index and info.kind == "fodder" and info.maxHp == 40
	end
	check(told and seen(boss + 1).state ~= "gone", "which carries all of them, like any spawn, and the snapshot shows them")

	-- They fight, after their grace, by their kind's turn rule.
	local early = false
	local most = 0
	for _ = 1, 15 * 7 do
		step2()
		local busy = 0
		for index = 1, 12 do
			local state = seen(boss + index).state
			if state == "windup" or state == "attack" then
				busy += 1
				early = early or fakeNow < born + 1.0 - 1e-6
			end
		end
		most = math.max(most, busy)
	end
	local lunges = 0
	for _, strike in struck do
		if strike.enemyKind == "fodder" and strike.targetUserId == 7 then
			lunges += 1
		end
	end
	check(lunges >= 4 and not early, `they fight (their kind's brain): {lunges} lunges at the player, none wound up inside spawnGrace`)
	check(most == 4, `and they take turns as their kind does (perPlayer 4 here: at most {most} at once)`)
	check(Crowd.AliveCount() == 13 and seen(boss).state ~= "windup", "the call is on its cooldown: no second one yet")

	-- One of them dies like any enemy; the rest go with their summoner.
	local before = kills
	kill(boss + 3)
	check(kills == before + 1 and Crowd.AliveCount() == 12, "a summoned body dies like any other")
	step2(12)
	check(Crowd.AliveCount() == 12, "and nothing brings it back")
	table.clear(ended)
	table.clear(log)
	table.clear(struck)
	kill(boss)
	check(Crowd.AliveCount() == 0, "the summoner's death removes what it summoned, at once")
	step2()
	local gone = #ended == 11
	for _, id in ended do
		gone = gone and id > boss and id <= boss + 12 and id ~= boss + 3
	end
	check(gone and seen(boss + 1).state == "gone", "with a CrowdRemove for each in the next batch")
	step2(20)
	check(#struck == 0, "and none of their attacks is raised after that")
	Vitals.ToggleGod(player)

	-- Only what fits under maxAlive.
	fresh()
	config.crowd.maxAlive = 6
	boss = Crowd.Spawn("caller", vec(0, 0, 50), "fight")
	waitFor(boss, "windup", 40)
	T = stamp() + 1.4
	S2.runTo(T)
	step2()
	local fits = Crowd.AliveCount() == 6
	for index, place in { 0, 2, 4, 7, 9 } do
		local view = Crowd.Get(boss + index)
		fits = fits and view ~= nil and (view.position - expected(vec(0, 0, 50), 0, place + 1, 12)).Magnitude < 1e-6
	end
	check(fits and Crowd.Get(boss + 6) == nil, "a call that would pass maxAlive summons only what fits, spread evenly through its twelve places (0, 2, 4, 7, 9)")
	config.crowd.maxAlive = 160

	-- A call tops up: it raises what is missing of `count`, on the places left free.
	fresh()
	Vitals.ToggleGod(player)
	boss = Crowd.Spawn("recaller", vec(0, 0, 50), "fight")
	local function nextCall(): number
		waitFor(boss, "recover", 200)
		waitFor(boss, "windup", 200)
		return stamp() + 1.4
	end
	waitFor(boss, "attack", 60)
	check(Crowd.AliveCount() == 13, "the first call raises twelve")
	local fallen = { 2, 5, 6, 9, 12 }
	T = nextCall()
	S2.runTo(T - 0.2)
	for _, index in fallen do
		kill(boss + index)
	end
	check(Crowd.AliveCount() == 8, "five of them are killed, a moment before the next call")
	S2.runTo(T)
	step2()
	local topped = Crowd.AliveCount() == 13 and Crowd.Get(boss + 18) == nil
	for index, was in fallen do
		local view = Crowd.Get(boss + 12 + index)
		topped = topped and view ~= nil and view.kind == "fodder" and (view.position - expected(vec(0, 0, 50), 0, was, 12)).Magnitude < 1e-6
	end
	check(topped, "the next call raises five, on the five places left free (the just-killed are not living, though their bodies still lie there)")
	T = nextCall()
	local marks = S2.trace(boss, 15 * 2)
	check(Crowd.AliveCount() == 13 and Crowd.Get(boss + 18) == nil, "with all twelve alive the call raises none")
	check(string.find(S2.names(marks), "attack1 recover1", 1, true) ~= nil, `and the attack still plays: windup, attack state, recover ({S2.names(marks)})`)
	-- `count` tuned down under living summons: never more living than `count`.
	for index = 13, 17 do
		kill(boss + index)
	end
	kill(boss + 1)
	config.crowd.kinds.recaller.attacks[1].count = 6
	T = nextCall()
	S2.runTo(T)
	step2()
	check(Crowd.AliveCount() == 7 and Crowd.Get(boss + 18) == nil, "(a `count` lowered to 6 with six still alive on other places: none is raised)")
	config.crowd.kinds.recaller.attacks[1].count = 12
	table.clear(ended)
	kill(boss)
	step2()
	check(Crowd.AliveCount() == 0 and #ended == 6, "the boss dies: all of them go")
	Vitals.ToggleGod(player)

	-- Inside the arena.
	fresh()
	root.Position = vec(50, 3, 0)
	boss = Crowd.Spawn("caller", vec(96, 0, 0), "fight")
	waitFor(boss, "windup", 40)
	T = stamp() + 1.4
	S2.runTo(T)
	step2()
	local inside = Crowd.AliveCount() == 13
	local atEdge = 0
	for index = 1, 12 do
		local view = Crowd.Get(boss + index)
		inside = inside and view ~= nil and view.position.X <= 98.7 + 1e-9
		if view ~= nil and near(view.position.X, 98.7, 1e-9) then
			atEdge += 1
		end
	end
	check(inside and atEdge >= 3, `they rise inside the arena: the ones past its edge stand at it ({atEdge} of 12)`)

	-- A summoner dead before its call is handed over raises nothing.
	for _, kind in { "caller", "herald" } do
		fresh()
		boss = Crowd.Spawn(kind, vec(0, 0, 50), "fight")
		waitFor(boss, "windup", 40)
		T = stamp() + 1.4
		S2.runTo(T)
		fakeNow = T + 0.001
		kill(boss)
		step2(3)
		local orphans = 0
		for _, info in risen do
			if info.kind == "fodder" then
				orphans += 1
			end
		end
		check(Crowd.AliveCount() == 0 and orphans == 0, `a {kind} killed at its impact, before the step that would hand the call over, raises nothing`)
	end
end
S2.summonTests()

function S2.barrageTests(): ()
	print(" barrage")
	local attack = config.crowd.kinds.bomber.attacks[1]
	-- A bomber at (0, 0, 30) throws at the first player where they stand; returns the areas and
	-- the landing time. The bomber is killed at the throw: its circles land all the same.
	local function volley(kind: string?): ({ any }, number, number)
		local id = Crowd.Spawn(kind or "bomber", vec(0, 0, 30), "fight")
		waitFor(id, "windup", 40)
		local thrown = stamp() + 0.5
		waitFx("area", 15)
		if kind == nil then
			kill(id)
		end
		return of(log, "area"), thrown + 1.4, id
	end
	local function farthest(areas: { any }, from: any): number
		local best = 2
		for index = 3, #areas do
			if flatTo(areas[index].center, from) > flatTo(areas[best].center, from) then
				best = index
			end
		end
		return best
	end

	-- The pure scatter.
	local points = S2.Shapes.Barrage(vec(1, 3, 2), 5, 14, 77)
	local even = #points == 5 and (points[1] - vec(1, 3, 2)).Magnitude == 0
	local turns = {}
	for index = 2, 5 do
		local offset = points[index] - points[1]
		even = even and offset.Magnitude <= 14 + 1e-9 and offset.Y == 0
		turns[index] = math.atan2(offset.Z, offset.X)
	end
	for index = 3, 5 do
		local gap = (turns[index] - turns[index - 1]) % (2 * math.pi)
		even = even and near(gap, math.pi / 2, 1e-9)
	end
	local again = S2.Shapes.Barrage(vec(1, 3, 2), 5, 14, 77)
	local other = S2.Shapes.Barrage(vec(1, 3, 2), 5, 14, 78)
	check(even, "HitShapes.Barrage: the first point is the centre, the others stand evenly round it, each within `spread`")
	check((again[3] - points[3]).Magnitude == 0 and (other[3] - points[3]).Magnitude > 1e-3, "and the same seed gives the same scatter, another seed another")
	local nearest = math.huge
	local furthest = 0
	for index = 2, 5 do
		nearest = math.min(nearest, flatTo(points[index], points[1]))
		furthest = math.max(furthest, flatTo(points[index], points[1]))
	end
	check(furthest - nearest > 1, `each at its own distance ({string.format("%.1f", nearest)} to {string.format("%.1f", furthest)} of 14)`)
	check(#S2.Shapes.Barrage(vec(0, 0, 0), 40, 14, 1) == S2.Shapes.MAX_FAN and #S2.Shapes.Barrage(vec(0, 0, 0), 0, 14, 1) == 0, "(at most MAX_FAN points, none for a count of 0)")

	-- What a barrage sends.
	fresh()
	root.Position = vec(1, 3, 2)
	local seed = Field.NextId() + 1
	local areas, lands, thrower = volley()
	points = S2.Shapes.Barrage(vec(1, 3, 2), 5, 14, seed)
	local sent = #areas == 5 and areas[1].id == seed
	for _, area in areas do
		sent = sent and area.enemyId == thrower
	end
	local ids: { [number]: boolean } = {}
	for index, area in areas do
		sent = sent and not ids[area.id] and area.enemyKind == "bomber" and near(area.radius, 5)
		sent = sent and area.startsAt == areas[1].startsAt and area.endsAt == areas[1].endsAt and near(area.endsAt - area.startsAt, 1.4, 1e-9)
		sent = sent and near(area.center.X, points[index].X, 1e-9) and near(area.center.Z, points[index].Z, 1e-9) and area.center.Y == 0
		sent = sent and near(area.from.Z, 30) and near(area.from.Y, 2.5)
		ids[area.id] = true
	end
	check(sent, "a lob with `count` 5 raises five `area` effects at T, in one batch: distinct ids, one start and one landing time, the first under the target, the others where HitShapes.Barrage puts them from the first one's id")
	check(#struck == 1 and rays == 5, `one strike from the brain, one ray down per circle ({rays})`)
	-- In the farthest circle, two studs out from its centre.
	local outer = farthest(areas, vec(1, 0, 2))
	local away = (areas[outer].center - vec(1, 0, 2)).Unit
	root.Position = areas[outer].center + away * 2 + vec(0, 3, 0)
	S2.land(lands)
	local hurts = of(log, "hurt")
	check(humanoid.Health == 112 and #hurts == 1 and hurts[1].amount == 18, "each circle lands as a lob: a player in an outer one is hit (130 -> 112)")
	check(hurts[1].push ~= nil and near((hurts[1].push - away * 14).Magnitude, 0, 1e-6), "and pushed away from that circle's own centre")

	-- One player, at most one circle.
	fresh()
	root.Position = vec(1, 3, 2)
	attack.spread = 3
	attack.knockback = 0
	attack.launch = 0
	areas, lands = volley()
	S2.land(lands)
	attack.spread = 14
	attack.knockback = 14
	attack.launch = 3
	hurts = of(log, "hurt")
	check(#areas == 5 and humanoid.Health == 112 and #hurts == 1 and hurts[1].dodged == nil, "standing under all five (spread 3, and no knock to void the rest): one hit, and one effect")

	-- Ruling 26: the barrage is one attack, and only its first circle was thrown at anyone.
	fresh()
	root.Position = vec(1, 3, 2)
	areas, lands = volley()
	root.Position = vec(60, 3, 2)
	iframes.from = lands - 0.02
	iframes.untilClock = lands + 0.2
	S2.land(lands)
	hurts = of(log, "hurt")
	check(humanoid.Health == 130 and #hurts == 1 and hurts[1].dodged == true, "ruling 26: its target, out of every circle under an i-frame, dodged once, not five times")
	fresh()
	root.Position = vec(1, 3, 2)
	areas, lands = volley()
	root.Position = vec(60, 3, 2)
	S2.land(lands)
	check(humanoid.Health == 130 and #of(log, "hurt") == 0, "and walking out of all of them says nothing")

	-- Each circle on the surface under its own centre.
	fresh()
	root.Position = vec(1, 3, 2)
	seed = Field.NextId() + 1
	points = S2.Shapes.Barrage(vec(1, 3, 2), 5, 14, seed)
	local raisedIndex = 2
	for index = 3, 5 do
		if flatTo(points[index], vec(1, 0, 2)) > flatTo(points[raisedIndex], vec(1, 0, 2)) then
			raisedIndex = index
		end
	end
	local top = points[raisedIndex]
	table.insert(blocks, { min = vec(top.X - 1.5, 0, top.Z - 1.5), max = vec(top.X + 1.5, 8, top.Z + 1.5) })
	areas, lands = volley()
	local levels = #areas == 5 and areas[1].id == seed
	for index, area in areas do
		levels = levels and area.center.Y == (if index == raisedIndex then 8 else 0)
	end
	check(levels, "each circle lies on the surface under its own centre: the one over a block lies on the block")
	root.Position = vec(top.X, 3 + 8, top.Z)
	S2.land(lands)
	check(humanoid.Health == 112, "and lands on a player standing on that block")

	-- A count of 1 is the plain lob.
	fresh()
	attack.count = 1
	areas, lands = volley()
	attack.count = 5
	S2.land(lands)
	check(#areas == 1 and near(areas[1].center.X, 0) and near(areas[1].center.Z, 0) and humanoid.Health == 112, "`count` 1 is the lob as it was: one circle on the target")
end
S2.barrageTests()

function S2.enrageTests(): ()
	print(" the Colossus: its attacks in order, and the second phase")
	local function strikes(shape: string): { any }
		local out = {}
		for _, strike in struck do
			if strike.def.shape == shape then
				table.insert(out, strike)
			end
		end
		return out
	end
	local function mark(marks: { any }, name: string): any
		for _, entry in marks do
			if entry.state .. entry.attack == name then
				return entry
			end
		end
		return { at = -1, state = "missing", attack = -1 }
	end

	-- The first phase.
	fresh()
	Vitals.ToggleGod(player)
	local boss = Crowd.Spawn("colossus", vec(0, 0, 12), "fight")
	local marks = S2.trace(boss, 15 * 10)
	local order = S2.names(marks)
	check(string.find(order, "windup1 attack1 recover1 windup2 attack2 recover2 windup3 attack3 recover3", 1, true) ~= nil, `ring, then charge, then call: the oldest of what is ready and in reach, a recover after each ({order})`)
	local w1 = mark(marks, "windup1").at
	local w2 = mark(marks, "windup2").at
	local w3 = mark(marks, "windup3").at
	local ring = strikes("ring")[1]
	local lane = strikes("lane")[1]
	check(ring ~= nil and near(ring.at, w1 + 1.0, 1e-9) and lane ~= nil and near(lane.at, w2 + 1.0, 1e-9), "each impact is its windup's first stamp + windup")
	check(near(w2 - w1, 1.0 + 0.2 + 1.6, 1e-9), "the ring's states last windup, strikeSeconds and recover")
	check(near(mark(marks, "recover2").at - mark(marks, "attack2").at, 44 / 60, 1e-9) and near(w3 - mark(marks, "recover2").at, 2.0, 1e-9), "the charge's attack state lasts range / speed, then its recover")
	check(#strikes("lob") == 0 and #of(log, "area") == 0 and string.find(order, "4", 1, true) == nil, "the `enraged` barrage is never used in the first phase")
	check(Crowd.AliveCount() == 13, "(and the call raised its twelve)")
	check(near(Crowd.Get(boss).position.Z, 12 - 44, 1e-6), "the charge carried it 44 studs; the ring and the call left it where it stood")

	-- Crossing half health inside a windup: that attack is still a first-phase one.
	fresh()
	boss = Crowd.Spawn("colossus", vec(0, 0, 12), "fight")
	waitFor(boss, "windup", 40)
	w1 = stamp()
	step2(3)
	local home = Crowd.Get(boss).position
	local yaw = seen(boss).yaw
	Crowd.Damage(boss, 3100, 7, vec(0, 0, 500), 20)
	step2()
	local entry = seen(boss)
	check(entry.state == "windup" and entry.attack == 1 and entry.yaw == yaw and (Crowd.Get(boss).position - home).Magnitude == 0, "nothing moves the Colossus: a heavy hit with a push and a launch leaves it in its windup, where it stood, facing as it did")
	check(entry.hpFraction <= 0.5, "(it is under half health on the wire now)")
	marks = S2.trace(boss, 15 * 9)
	order = S2.names(marks)
	ring = strikes("ring")[1]
	check(ring ~= nil and near(ring.at, w1 + 1.0, 1e-9), "the second phase is not entered inside a windup: the ring it was winding up keeps its full windup")
	check(string.find(order, "attack1 recover1 windup2 attack2 windup3 attack3 recover3 windup4 attack4 recover4", 1, true) ~= nil, `enraged at the ring's end: that attack still recovers, then attacks follow each other in chains of two ({order})`)
	w2 = mark(marks, "windup2").at
	w3 = mark(marks, "windup3").at
	local w4 = mark(marks, "windup4").at
	lane = strikes("lane")[1]
	local lob = strikes("lob")[1]
	local firstRecover = w1 + 1.0 + 0.2 + 1.6 * 0.6
	check(w2 >= firstRecover - 1e-9 and w2 < firstRecover + DT, "the attack the phase began in ends in a recover, and it is an enraged one: recover x recoverScale (1.6 x 0.6)")
	check(lane ~= nil and near(lane.at, w2 + 0.75, 1e-9), "an enraged windup lasts windup x windupScale, from its first stamp (1.0 x 0.75)")
	local chargeEnds = lane.at + 44 / 60
	check(w3 >= chargeEnds - 1e-9 and w3 < chargeEnds + DT, "the chained windup starts when the attack state ends: no recover between")
	local chainRecovers = w3 + 1.4 * 0.75 + 0.2 + 1.2 * 0.6
	check(w4 >= chainRecovers - 1e-9 and w4 < chainRecovers + DT, "the chain's last attack recovers for recover x recoverScale (the call: 1.2 x 0.6)")
	local areas = of(log, "area")
	check(lob ~= nil and #areas == 5 and near(areas[1].startsAt - SERVER_OFFSET, w4 + 0.8 * 0.75, 1e-9) and near(areas[1].endsAt - areas[1].startsAt, 1.6, 1e-9), "the barrage unlocks, and opens a chain of its own: five circles at its windup's first stamp + 0.8 x 0.75, landing `seconds` later")
	Vitals.ToggleGod(player)

	-- The phase is the byte's.
	fresh()
	Vitals.ToggleGod(player)
	boss = Crowd.Spawn("colossus", vec(0, 0, 12), "fight")
	Crowd.Damage(boss, 3006, 7, nil, nil)
	waitFor(boss, "windup", 40)
	w1 = stamp()
	local share = seen(boss).hpFraction
	marks = S2.trace(boss, 15 * 2)
	ring = strikes("ring")[1]
	check(share > 0.5 and Crowd.Get(boss).hp / 6000 < 0.5, "2994 of 6000 is 0.499, and 128/255 on the wire")
	check(ring ~= nil and near(ring.at, w1 + 1.0, 1e-9) and string.find(S2.names(marks), "attack1 recover1", 1, true) ~= nil, "so it is not enraged: a full windup, and a recover after it")
	Crowd.Damage(boss, 6, 7, nil, nil)
	marks = S2.trace(boss, 15 * 3)
	w2 = mark(marks, "windup2").at
	lane = strikes("lane")[1]
	check(seen(boss).hpFraction <= 0.5 and near(w2, w1 + 1.0 + 0.2 + 1.6, 1e-9), "2988 is 127/255: the recover that began before it keeps its full length")
	check(lane ~= nil and near(lane.at, w2 + 0.75, 1e-9), "and the next windup is an enraged one")
	Vitals.ToggleGod(player)
end
S2.enrageTests()

function S2.immovableTests(): ()
	print(" nothing moves it")
	fresh()
	Vitals.ToggleGod(player)
	local boss = Crowd.Spawn("colossus", vec(0, 0, 12), "fight")
	waitFor(boss, "windup", 40)
	local T = stamp() + 1.0
	local home = Crowd.Get(boss).position
	local yaw = seen(boss).yaw
	local unmoved = true
	for index = 1, 10 do
		local dealt = Crowd.Damage(boss, if index % 2 == 0 then 60 else 10, 7, vec(300, 0, 300), 30)
		step2()
		local entry = seen(boss)
		unmoved = unmoved and dealt > 0 and entry.state == "windup" and entry.attack == 1 and entry.yaw == yaw
		unmoved = unmoved and (Crowd.Get(boss).position - home).Magnitude == 0
	end
	check(unmoved, "light and heavy hits with a push and a launch, all through its windup: it takes the damage and nothing else (no shove, no hop, no stagger, no turn)")
	S2.runTo(T)
	step2()
	check(#struck == 1 and near(struck[1].at, T, 1e-9), "and `interrupt = none` holds: the blow lands on its time")
	Vitals.ToggleGod(player)

	fresh()
	root.Position = vec(0, 3, -90)
	local wall = Crowd.Spawn("bulwark", vec(0, 0, 20), "idle")
	step2()
	Crowd.Damage(wall, 50, 7, vec(0, 0, 100), 10)
	local _dealt, _killed, verdict = Crowd.Damage(wall, 50, 7, vec(0, 0, 100), 10)
	step2()
	check(verdict == "broke" and seen(wall).state == "stagger" and near(Crowd.Get(wall).position.Z, 20) and Crowd.Get(wall).position.Y == 0 and seen(wall).plated == false, "a plated kind that nothing moves still reels when its plate breaks (Stop 3), and is not pushed or launched by that hit")
	step2(14)
	check(seen(wall).state == "stagger", "it reels for plateBreakSeconds (1.0 here): still reeling 14 steps on")
	step2(2)
	Crowd.Damage(wall, 50, 7, vec(0, 0, 100), 10)
	step2()
	check(seen(wall).state == "idle" and near(Crowd.Get(wall).position.Z, 20), "and after it an ordinary hit does not stagger or move it, as before")
end
S2.immovableTests()

function S2.separateTests(): ()
	print(" large bodies in separate()")
	fresh()
	root.Position = vec(0, 3, -90)
	local big = Crowd.Spawn("titan", vec(0, 0, 40), "idle")
	local small = Crowd.Spawn("pawn", vec(3, 0, 40), "idle")
	step2()
	local at = Crowd.Get(big).position
	check(at.X == 0 and at.Z == 40 and near(Crowd.Get(small).position.X, 5.3, 1e-6), "a small body overlapping a large one gives way by the whole overlap; the large one is not moved at all")
	step2(10)
	at = Crowd.Get(big).position
	check(at.X == 0 and at.Z == 40 and Crowd.Get(small).position.X >= 5.3 - 1e-6, "(and it stays so while the small one keeps pressing home)")

	-- The line between small and large is crowd.largeRadius, read every step.
	fresh()
	root.Position = vec(0, 3, -90)
	config.crowd.largeRadius = 5
	big = Crowd.Spawn("titan", vec(0, 0, 40), "idle")
	small = Crowd.Spawn("pawn", vec(3, 0, 40), "idle")
	step2()
	check(Crowd.Get(big).position.X < -0.1 and Crowd.Get(small).position.X < 5.2, "largeRadius 5: a radius-4 body is not large, and shares the overlap by mass like any pair")
	fresh()
	root.Position = vec(0, 3, -90)
	config.crowd.largeRadius = 2
	big = Crowd.Spawn("brute", vec(0, 0, 40), "idle")
	small = Crowd.Spawn("pawn", vec(2, 0, 40), "idle")
	step2()
	check(Crowd.Get(big).position.X == 0 and near(Crowd.Get(small).position.X, 3.5, 1e-6), "largeRadius 2: a radius-2.2 body is large now, and a smaller one gives way to it by the whole overlap")
	config.crowd.largeRadius = 2.5

	-- Two large bodies are a pair like any other.
	fresh()
	root.Position = vec(0, 3, -90)
	big = Crowd.Spawn("titan", vec(0, 0, 40), "idle")
	local twin = Crowd.Spawn("titan", vec(5, 0, 40), "idle")
	step2()
	check(near(Crowd.Get(big).position.X, -1.5, 1e-6) and near(Crowd.Get(twin).position.X, 6.5, 1e-6), "two large bodies split their overlap between them")

	-- A large body walks through the crowd as if it were not there.
	local function march(crowded: boolean): number
		fresh()
		root.Position = vec(0, 3, -60)
		local walker = Crowd.Spawn("titan", vec(0, 0, 40), "chase")
		if crowded then
			for index = 1, 8 do
				Crowd.Spawn("pawn", vec((index - 4.5) * 2.5, 0, 34), "idle")
			end
		end
		step2(30)
		return Crowd.Get(walker).position.Z
	end
	local alone = march(false)
	local through = march(true)
	check(alone < 30 and through == alone, `a large body pushes small ones aside and is never slowed or turned by them (z {string.format("%.3f", through)} either way)`)

	-- A small body planted in its windup is not shoved either: the two overlap until it has struck.
	fresh()
	local lunger = Crowd.Spawn("fodder", vec(0, 0, 4), "fight")
	check(waitFor(lunger, "windup", 40), "a fodder winds up")
	local spot = Crowd.Get(lunger).position
	big = Crowd.Spawn("titan", vec(2, 0, 4), "idle")
	step2(3)
	local stood = (Crowd.Get(lunger).position - spot).Magnitude == 0 and Crowd.Get(big).position.X == 2
	check(stood and seen(lunger).state == "windup", "a small body planted in its windup keeps its place against a large one, and the large one is not pushed: they overlap")
	waitFor(lunger, "recover", 30)
	step2(2)
	check(Crowd.Get(big).position.X == 2 and flatTo(Crowd.Get(lunger).position, vec(2, 0, 4)) >= 5.3 - 1e-6, "once it has struck it gives way")

	-- The cost: one giant alive must not widen what every other body scans. Fix round A-3: counted
	-- in grid cells visited (CrowdService.SeparationCells), not timed: a clock under load made
	-- this case fail at random and could turn the mutation baseline red.
	local function scanned(giantAlive: boolean): number
		fresh()
		root.Position = vec(0, 3, -95)
		for index = 1, 110 do
			Crowd.Spawn("pawn", vec(((index - 1) % 11 - 5) * 2.2, 0, 40 + (index - 1) // 11 * 2.2), "idle")
		end
		if giantAlive then
			Crowd.Spawn("titan", vec(-80, 0, -80), "idle")
		end
		step2(10)
		fakeNow += DT
		crowdBeat(DT)
		local cells = Crowd.SeparationCells()
		gather()
		return cells
	end
	local without = scanned(false)
	local with = scanned(true)
	check(without >= 110 * 9 and with == without, `a giant standing far away costs the packed crowd nothing: {without} grid cells scanned a step without it, {with} with it`)
end
S2.separateTests()

function S2.cleanupTests(): ()
	print(" a boss's death and a set load leave nothing behind")
	-- A ring in flight.
	local function ringAt(kind: string): number
		fresh()
		local id = Crowd.Spawn(kind, vec(0, 0, 12), "fight")
		waitFor(id, "windup", 40)
		local T = stamp() + 1.0
		S2.runTo(T)
		step2()
		root.Position = vec(0, 3, -13)
		step2(2)
		kill(id)
		local busy = Field.Busy()
		step2(20)
		return if busy then 1 else 0
	end
	local left = ringAt("ringBoss")
	check(left == 0 and humanoid.Health == 130 and #log == 0, "a boss killed with its ring on the way: the ring is gone with it and hits nobody")
	left = ringAt("ringer")
	check(left == 1 and humanoid.Health == 104, "(a kind that is no boss: its ring travels on, as ruling 22 has it)")

	-- An impact its death had queued (the kill came after the impact time, before the step).
	fresh()
	local late = Crowd.Spawn("ringBoss", vec(0, 0, 12), "fight")
	waitFor(late, "windup", 40)
	local due = stamp() + 1.0
	S2.runTo(due)
	fakeNow = due + 0.001
	kill(late)
	step2(20)
	check(#struck == 0 and humanoid.Health == 130 and not Field.Busy(), "a boss killed after its impact time, before the step that would raise it: the blow is taken back, where another kind's would still land")

	-- Its shot in the air.
	fresh()
	local slinger = table.clone(config.crowd.kinds.slinger)
	slinger.boss = true
	config.crowd.kinds.slingerBoss = slinger
	local gunner = Crowd.Spawn("slingerBoss", vec(0, 0, 25), "fight")
	waitFx("enemyShot", 60)
	step2(3)
	table.clear(log)
	kill(gunner)
	step2(30)
	local stopped = of(log, "enemyShotEnd")
	check(#stopped == 1 and stopped[1].hit == false and Field.ShotsAlive() == 0 and humanoid.Health == 130, "a boss killed with a shot in the air: the shot ends where it is, and is told")

	-- A barrage in the air.
	fresh()
	root.Position = vec(1, 3, 2)
	local id = Crowd.Spawn("bomberBoss", vec(0, 0, 30), "fight")
	waitFor(id, "windup", 40)
	local lands = stamp() + 0.5 + 1.4
	waitFx("area", 15)
	kill(id)
	S2.land(lands)
	check(#of(log, "area") == 5 and humanoid.Health == 130 and #of(log, "hurt") == 0, "a boss killed with its barrage in the air: the five circles land on nobody")

	-- A charge under way.
	fresh()
	Vitals.ToggleGod(player)
	local boss = Crowd.Spawn("colossus", vec(0, 0, 30), "fight")
	waitFor(boss, "attack", 60)
	step2(2)
	check(Field.Busy(), "the Colossus charges from 30 studs")
	kill(boss)
	check(not Field.Busy(), "killed in its charge: nothing is left on the run")
	Vitals.ToggleGod(player)

	-- A summoned body's lunge still waiting for its decision.
	fresh()
	root.Position = vec(0, 3, 38)
	boss = Crowd.Spawn("caller", vec(0, 0, 50), "fight")
	waitFor(boss, "windup", 40)
	S2.runTo(stamp() + 1.4)
	step2()
	local lunged = false
	for _ = 1, 15 * 4 do
		fakeNow += DT
		crowdBeat(DT)
		if #struck > 0 then
			lunged = true
			break
		end
		vitalsBeat(DT)
		gather()
	end
	-- The lunge struck in this crowd frame; the player is in it and has not been judged yet.
	kill(boss)
	vitalsBeat(DT)
	gather()
	step2(10)
	check(lunged and humanoid.Health == 130 and #of(log, "hurt") == 0, "a summoned body's blow that had struck but not yet been decided goes with it when its summoner dies")

	-- A set load.
	fresh()
	root.Position = vec(1, 3, 2)
	Crowd.Spawn("ringer", vec(1, 0, 14), "fight")
	Crowd.Spawn("bomber", vec(0, 0, 30), "fight")
	boss = Crowd.Spawn("caller", vec(40, 0, 30), "fight")
	waitFor(boss, "attack", 60)
	step2()
	check(Crowd.AliveCount() == 15 and #of(log, "area") == 5 and Field.Busy(), "a ring on the way, a barrage in the air and twelve summoned bodies")
	-- The barrage's first circle is on the player and lands half a second from now.
	local health = humanoid.Health
	table.clear(ended)
	table.clear(log)
	Crowd.Clear()
	Vitals.OnSetLoaded()
	check(Crowd.AliveCount() == 0 and not Field.Busy(), "a set load: no body and no ring left")
	step2(40)
	check(humanoid.Health == health and #of(log, "hurt") == 0 and #ended == 15, `and nothing lands afterwards; every body was ended on the wire ({#ended})`)

	-- An impact still queued in the brain when the set is loaded.
	fresh()
	id = Crowd.Spawn("ringer", vec(0, 0, 12), "fight")
	waitFor(id, "windup", 40)
	local T = stamp() + 1.0
	S2.runTo(T)
	fakeNow = T + 0.001
	kill(id)
	Crowd.Clear()
	Vitals.OnSetLoaded()
	step2(20)
	check(#struck == 0 and humanoid.Health == 130, "an impact a kill had queued is dropped by the set load too")
end
S2.cleanupTests()

function S2.tallyTests(): ()
	print(" the strike that kills a boss")
	local Tally = load("StrikeTally")
	fresh()
	Vitals.ToggleGod(player)
	local boss = Crowd.Spawn("caller", vec(0, 0, 50), "fight")
	waitFor(boss, "attack", 60)
	step2(2)
	-- One strike's list, as RangeService walks it: the boss first, then six of its summons.
	local tally = Tally.New()
	local function hit(id: number, amount: number): ()
		local dealt, killed, verdict = Crowd.Damage(id, amount, 7, nil, nil)
		Tally.Add(tally, id, dealt, false, killed, verdict)
	end
	hit(boss + 1, 10)
	hit(boss, 100000)
	for index = 2, 7 do
		hit(boss + index, 10)
	end
	check(Crowd.AliveCount() == 0, "the blow that kills the boss removes its summons under the same strike")
	check(#tally.hits == 2 and tally.enemies == 2 and tally.kills == 1 and tally.hits[1].id == boss + 1 and tally.hits[2].id == boss, `the strike books the one it hit before and the boss, not the six it removed ({#tally.hits} entries, {tally.enemies} enemies)`)
	local _dealt, _killed, verdict = Crowd.Damage(boss + 2, 10, 7, nil, nil)
	local _d2, _k2, dead = Crowd.Damage(boss, 10, 7, nil, nil)
	check(verdict == "gone" and dead == nil, "Damage says `gone` of a body that is no longer there, and nothing of one that lies dead")
	Vitals.ToggleGod(player)
end
S2.tallyTests()

function S2.tuningTests(): ()
	print(" Tuning")
	local Tune = S2.Tuning
	check(Tune.Validate("crowd.kinds.colossus.attacks.1.shape", "summon") and Tune.Validate("crowd.kinds.colossus.attacks.3.shape", "ring") and not Tune.Validate("crowd.kinds.colossus.attacks.1.shape", "wave"), "the two new shapes are legal values of an attack's shape")
	check(Tune.Validate("crowd.kinds.colossus.attacks.3.summon", "armoured") and not Tune.Validate("crowd.kinds.colossus.attacks.3.summon", "nobody"), "`summon` must name a kind of the base config")
	check(Tune.Validate("crowd.kinds.colossus.enrage.at", 0.3) and not Tune.Validate("crowd.kinds.colossus.enrage.windupScale", -0.5) and not Tune.Validate("crowd.kinds.colossus.enrage.chain", -1), "the enrage numbers may not go below 0")
	check(Tune.Validate("crowd.largeRadius", 2.5) and not Tune.Validate("crowd.largeRadius", -1), "crowd.largeRadius is tunable and may not go below 0")
	check(Tune.Validate("crowd.kinds.colossus.attacks.1.cooldown", 0) and not Tune.Validate("crowd.kinds.colossus.attacks.1.cooldown", -1) and not Tune.Validate("crowd.kinds.colossus.attacks.4.spread", -1), "nor an attack's cooldown, count or spread")
end
S2.tuningTests()

function S2.costNote(): ()
	fresh()
	Vitals.ToggleGod(player)
	root.Position = vec(0, 3, 0)
	local boss = Crowd.Spawn("colossus", vec(0, 0, 50), "fight")
	local worst = 0
	local total = 0
	local steps = 15 * 20
	for _ = 1, steps do
		local began = os.clock()
		step2()
		local took = (os.clock() - began) * 1000
		worst = math.max(worst, took)
		total += took
	end
	Vitals.ToggleGod(player)
	print(`  note  the colossus set for 20 s ({Crowd.AliveCount()} alive at the end, boss {if Crowd.Get(boss) ~= nil then "alive" else "gone"}): {string.format("%.2f", total / steps)} ms a step on average, {string.format("%.2f", worst)} ms at worst (not Studio's number)`)
end
S2.costNote()

