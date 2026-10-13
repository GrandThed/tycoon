-- Scratch tests for P4 Stop 3, the Warlord and his guard (never shipped): appended after
-- tests_s2.luau by run_harness.py. Everything hangs off the S2 table (the 200-local limit).

print("Stop 3")

do
	local kinds = config.crowd.kinds
	local function guardArc(): any
		return { shape = "arc", reach = 6, windup = 0.8, recover = 1.2, damage = 26, knockback = 30, launch = 3, range = 7.5, arcDegrees = 120, height = 6, interrupt = "heavy" }
	end
	kinds.guard = { radius = 1.7, headRadius = 0.8, height = 6.5, speed = 9, hp = 120, armor = 0, knockbackMult = 0.35, brain = "rush", perPlayer = 2, plate = 40, attacks = { guardArc() } }
	-- The lead's shape, on numbers that fall on the 15 Hz grid.
	kinds.warlord = {
		radius = 2.6, headRadius = 1.1, height = 9, speed = 11, hp = 2600, armor = 0, knockbackMult = 0,
		brain = "keepAway", bandMin = 30, bandMax = 46, perPlayer = 1, boss = true, name = "Warlord",
		plate = 240, guarded = true,
		enrage = { at = 1, windupScale = 1, recoverScale = 1, chain = 2, brain = "rush" },
		attacks = {
			{ shape = "summon", reach = 80, windup = 1.2, recover = 1.0, damage = 0, count = 4, summon = "guard", radius = 9, uses = 1, calm = true, interrupt = "none" },
			{ shape = "lob", reach = 60, windup = 0.8, recover = 2.2, damage = 18, knockback = 14, launch = 3, radius = 5, seconds = 1.6, count = 3, spread = 12, height = 4, cooldown = 5, calm = true, interrupt = "none" },
			{ shape = "arc", reach = 9, windup = 0.8, recover = 1.4, damage = 30, knockback = 30, launch = 3, range = 11, arcDegrees = 180, height = 6, cooldown = 3, enraged = true, interrupt = "none" },
			{ shape = "lane", reach = 34, windup = 1.0, recover = 1.8, damage = 30, knockback = 30, launch = 3, range = 36, width = 7, speed = 60, height = 6, cooldown = 7, enraged = true, interrupt = "none" },
			{ shape = "lob", reach = 60, windup = 0.8, recover = 1.4, damage = 18, knockback = 14, launch = 3, radius = 5, seconds = 1.6, count = 4, spread = 12, height = 4, cooldown = 9, enraged = true, interrupt = "none" },
		},
	}
	-- A plated summoner that is not `guarded`: its plate breaks whoever lives.
	-- Guarded kinds whose call is not a single one: no limit, and a limit of two.
	local function recall(uses: number?): any
		return { shape = "summon", reach = 80, windup = 1.2, recover = 1.0, damage = 0, count = 2, summon = "guard", radius = 9, uses = uses, cooldown = 3, interrupt = "none" }
	end
	kinds.warden = { radius = 2.6, headRadius = 1.1, height = 9, speed = 0, hp = 500, armor = 0, knockbackMult = 0, brain = "rush", boss = true, plate = 240, guarded = true, attacks = { recall(nil) } }
	kinds.marshal = { radius = 2.6, headRadius = 1.1, height = 9, speed = 0, hp = 500, armor = 0, knockbackMult = 0, brain = "rush", boss = true, plate = 240, guarded = true, attacks = { recall(2) } }
	kinds.captain = { radius = 2.6, headRadius = 1.1, height = 9, speed = 0, hp = 500, armor = 0, knockbackMult = 0, brain = "rush", boss = true, plate = 240, attacks = { { shape = "summon", reach = 80, windup = 1.2, recover = 1.0, damage = 0, count = 2, summon = "guard", radius = 9, interrupt = "none" } } }
end

-- The indices of the windups an enemy's snapshots show over `count` steps, in order.
function S2.windups(id: number, count: number): string
	local out = {}
	for _, mark in S2.trace(id, count) do
		if mark.state == "windup" then
			table.insert(out, tostring(mark.attack))
		end
	end
	return table.concat(out, "")
end

-- A plated body takes one blow for its plate and one for its life.
function S2.slay(id: number): ()
	kill(id)
	kill(id)
end

function S2.brainTests(): ()
	print(" calm and uses, on the brain alone")
	local kinds = config.crowd.kinds
	local function blow(extra: any): any
		local attack: any = { shape = "arc", reach = 10, windup = 0.2, recover = 0.2, damage = 1, range = 5, arcDegrees = 120, height = 5, interrupt = "none" }
		for key, value in extra do
			attack[key] = value
		end
		return attack
	end
	local function run(sim: any, seconds: number): string
		local from = #sim.strikes
		for _ = 1, math.floor(15 * seconds + 0.5) do
			stepSim(sim)
		end
		local out = {}
		for index = from + 1, #sim.strikes do
			table.insert(out, tostring(sim.strikes[index].attack))
		end
		return table.concat(out, "")
	end
	local function arena(kind: string, userId: number): (any, any)
		local sim = newSim()
		sim.now = 5
		table.insert(sim.targets, { userId = userId, position = vec(0, 3, 0) })
		local body = spawn(sim, kind, 0, 5)
		body.mind.bornAt = 0
		return sim, body
	end

	kinds.moody = { radius = 1.3, headRadius = 0.7, height = 5, speed = 0, hp = 100, armor = 0, knockbackMult = 1, brain = "rush", enrage = { at = 0.5, windupScale = 1, recoverScale = 1, chain = 1 }, attacks = { blow({ calm = true }), blow({ enraged = true }), blow({ uses = 2 }) } }
	local sim, body = arena("moody", 91)
	local calm = run(sim, 6)
	local thirds = select(2, string.gsub(calm, "3", ""))
	check(#calm >= 8 and string.find(calm, "2") == nil and string.sub(calm, 1, 4) == "1313", `before the second phase the calm attack and the limited one take turns, the enraged one never ({calm})`)
	check(thirds == 2 and string.sub(calm, 5) == string.rep("1", #calm - 4), "`uses` 2: it lands twice in the body's life and is never chosen again, though it is ready and in reach")
	body.hp = 40
	local angry = run(sim, 4)
	check(#angry >= 5 and angry == string.rep("2", #angry), `in the second phase a calm attack is never chosen again ({angry})`)

	-- `uses` is counted at the impact: a windup that was cancelled has used nothing.
	kinds.oneShot = { radius = 1.3, headRadius = 0.7, height = 5, speed = 0, hp = 100, armor = 0, knockbackMult = 1, brain = "rush", attacks = { blow({ uses = 1, windup = 0.4, interrupt = "stagger" }) } }
	sim, body = arena("oneShot", 92)
	for _ = 1, 3 do
		stepSim(sim)
	end
	hit(sim, body, 1)
	check(body.mind.phase == "recover" and #sim.strikes == 0, "a `uses` 1 attack is cancelled in its windup")
	local later = run(sim, 4)
	check(later == "1", `it is still owed: it lands once, and then never again ({later})`)
	local fresh2
	sim, fresh2 = arena("oneShot", 93)
	check(run(sim, 3) == "1" and fresh2.mind.landed[1] == 1, "a new body has its uses back")
	-- With nothing left to use, a rusher has no reach to close to and stands.
	check(fresh2.mind.phase == "approach", "(with every attack used up it waits)")
end
S2.brainTests()

function S2.warlordTests(): ()
	print(" the Warlord: the siege")
	local Tally = load("StrikeTally")
	local function tallied(id: number, amount: number): (any, any)
		local tally = Tally.New()
		local dealt, killed, verdict = Crowd.Damage(id, amount, 7, vec(0, 0, 300), 20)
		Tally.Add(tally, id, dealt, false, killed, verdict)
		return tally.hits[1], verdict
	end
	local function guards(boss: number): { number }
		local out = {}
		for _, info in risen do
			if info.kind == "guard" and (info :: any).summonerId == boss then
				table.insert(out, info.id)
			end
		end
		return out
	end

	fresh()
	Vitals.ToggleGod(player)
	local boss = Crowd.Spawn("warlord", vec(0, 0, 40), "fight")
	check(waitFor(boss, "windup", 40) and seen(boss).attack == 1, "the Warlord's first act is to call his guard")
	-- He is guarded from the moment he spawns: the guard he has yet to call counts.
	local hit, verdict = tallied(boss, 100)
	check(verdict == "guarded" and hit.blocked == true and hit.guarded == true and seen(boss).hpFraction == 1, "before his guard has risen a heavy hit is already `guarded`: there is no open plate at the start")
	waitFor(boss, "attack", 40)
	step2(2)
	local guard = guards(boss)
	local plated = #guard == 4 and Crowd.AliveCount() == 5
	for _, id in guard do
		plated = plated and seen(id).plated == true
	end
	check(plated, "four plated guards rise, and each spawn names its summoner (the client's count of the living guard)")
	check((risen[1] :: any).summonerId == nil, "(a body nobody summoned names none)")

	-- Guarded: every hit on his plate does nothing, heavy or not.
	local home = Crowd.Get(boss).position
	local stateBefore = seen(boss).state
	hit, verdict = tallied(boss, 100)
	step2()
	local entry = seen(boss)
	check(verdict == "guarded" and hit.amount == 0 and hit.blocked == true and (hit :: any).guarded == true and hit.plate == nil, "while his guard lives a heavy hit on his plate is blocked, and the hit says it was the guard's doing")
	check(entry.plated and entry.hpFraction == 1 and (Crowd.Get(boss).position - home).Magnitude < 1.0 and entry.state ~= "stagger" and entry.state ~= "airborne" and kills == 0, `and it does nothing at all: the plate is whole, no push, no hop, no stagger ({stateBefore} -> {entry.state})`)
	hit, verdict = tallied(boss, 10)
	check(verdict == "guarded" and (hit :: any).guarded == true, "a light hit says the same")
	hit, verdict = tallied(boss, 0)
	check(verdict == "guarded" and hit.blocked == true and hit.guarded == true, "and so does a hit of 0 (a damage slider at 0): never a plain hit that would read as the guard being gone")
	local _zero, _dead, plain = Crowd.Damage(guard[1], 0, 7, nil, nil)
	check(plain == nil, "(a hit of 0 on any other body is still nothing)")

	-- The siege: he keeps away, throws his calm barrage, and never calls again.
	local farthest = 0
	local nearest = math.huge
	local order = {}
	for _, mark in S2.trace(boss, 15 * 14) do
		if mark.state == "windup" then
			table.insert(order, tostring(mark.attack))
		end
	end
	for _ = 1, 15 do
		step2()
		local distance = flatTo(Crowd.Get(boss).position, vec(0, 0, 0))
		farthest = math.max(farthest, distance)
		nearest = math.min(nearest, distance)
	end
	local sequence = table.concat(order, "")
	check(#sequence >= 2 and sequence == string.rep("2", #sequence), `calm, he throws only the calm barrage ({sequence}); the call has landed its one use`)
	check(nearest >= 30 - 1e-6 and farthest <= 46 + 1e-6 and #of(log, "area") >= 6, `and keeps his distance in his band ({string.format("%.1f", nearest)} to {string.format("%.1f", farthest)} studs, {#of(log, "area")} circles)`)
	-- Walked up on, he backs off: that is the kind's own brain, keepAway.
	root.Position = vec(0, 3, 20)
	local backedOff = false
	for _ = 1, 15 * 5 do
		step2()
		backedOff = backedOff or flatTo(Crowd.Get(boss).position, root.Position) >= 30 - 1e-3
	end
	check(backedOff, "calm, he fights by his kind's brain: walked up on, he backs off to his band")
	root.Position = vec(0, 3, 0)
	step2(15 * 3)
	local most = 0
	for _ = 1, 15 * 4 do
		step2()
		local busy = 0
		for _, id in guard do
			local state = seen(id).state
			if state == "windup" or state == "attack" then
				busy += 1
			end
		end
		most = math.max(most, busy)
	end
	check(most == 2, `the guard fights under its kind's turn rule (perPlayer 2: at most {most} at once)`)
	local behind = 0
	for index, id in guard do
		local info = Crowd.Get(id)
		if info ~= nil and index == 3 then
			behind = info.position.Z
		end
	end
	check(behind < 20, "the guards that rose behind him have run past him to the player: none is stuck at his back")

	-- The guard falls: three dead, still guarded; the fourth, and the plate is open at once.
	for index = 1, 3 do
		S2.slay(guard[index])
	end
	step2(12)
	hit, verdict = tallied(boss, 100)
	check(verdict == "guarded" and Crowd.AliveCount() == 2, "one guard left: still guarded, and nobody is called in their place")
	S2.slay(guard[4])
	hit, verdict = tallied(boss, 100)
	check(verdict == "plate" and hit.plate == true and hit.blocked == nil and (hit :: any).guarded == nil and hit.amount == 100, "the last guard dies: the very next heavy hit goes to his plate, though that body still lies there")
	hit, verdict = tallied(boss, 10)
	check(verdict == "blocked" and (hit :: any).guarded == nil, "and a light hit is an ordinary block again")
	local later = S2.windups(boss, 15 * 6)
	check(Crowd.AliveCount() == 1 and string.find(later, "1") == nil, `with the guard dead he calls no new one ({later})`)

	-- The turn: the plate breaks, he reels, and when the reel is over he is enraged and closes in.
	print(" the Warlord: the turn")
	waitFor(boss, "windup", 120)
	local calmWindup = seen(boss).attack
	local areasBefore = #of(log, "area")
	step2(3)
	Crowd.Damage(boss, 100, 7, vec(0, 0, 300), 20)
	local _dealt, _killed, broke = Crowd.Damage(boss, 100, 7, vec(0, 0, 300), 20)
	local brokeAt = fakeNow
	local stoodAt = Crowd.Get(boss).position
	step2()
	entry = seen(boss)
	check(broke == "broke" and entry.plated == false and entry.hpFraction == 1, "the plate breaks: unplated on the wire, health share 1, which is at or under `enrage.at` 1")
	check(calmWindup == 2 and entry.state == "stagger" and entry.attack == 0, "the breaking hit reels him, though nothing else staggers him, and cancels the calm barrage he was winding up (`interrupt = none` or not): stagger, attack index 0")
	check((Crowd.Get(boss).position - stoodAt).Magnitude == 0, "it does not push or launch him")
	-- plateBreakSeconds is 1.0 here: staggered through it, and no windup inside it.
	local marks = S2.trace(boss, 15 * 14)
	local turned = S2.names(marks)
	local reelEnds = brokeAt + 1.0
	local firstWindup: any = nil
	local reeled: any = nil
	local after = {}
	for _, mark in marks do
		if mark.state == "windup" then
			firstWindup = firstWindup or mark
			table.insert(after, tostring(mark.attack))
		elseif mark.state ~= "stagger" and reeled == nil then
			reeled = mark
		end
	end
	local afterwards = table.concat(after, "")
	check(reeled ~= nil and reeled.at >= reelEnds - 1e-6 and reeled.at < reelEnds + 2 * DT, "he reels for plateBreakSeconds, staggered on the wire like any reeling elite")
	local thrownInReel = 0
	for index, area in of(log, "area") do
		if index > areasBefore and area.startsAt - SERVER_OFFSET < brokeAt + 2.2 - 1e-6 then
			thrownInReel += 1
		end
	end
	check(thrownInReel == 0, "the cancelled barrage throws nothing")
	-- The cancelled windup's recover (2.2 s from the break) outlasts the reel: he stands in it.
	check(reeled ~= nil and reeled.state == "recover" and reeled.attack == calmWindup, "after the reel the snapshot shows the cancelled attack's recover, as a cancelled elite's does")
	check(firstWindup ~= nil and firstWindup.attack >= 3 and firstWindup.at >= brokeAt + 2.2 - 1e-6, `his first duel windup comes when the reel and that recover are both over ({string.format("%.2f", (firstWindup or { at = 0 }).at - brokeAt)} s after the break)`)
	check(#afterwards >= 3 and string.find(afterwards, "[12]") == nil, `from then on only enraged attacks ({afterwards}): the arc, the charge, the bigger barrage`)
	check(string.find(turned, "stagger0 recover2", 1, true) ~= nil, `the wire from the break on: {string.sub(turned, 1, 60)}`)
	check(flatTo(Crowd.Get(boss).position, vec(0, 0, 0)) < 30 - 1, `and he fights with enrage.brain: a rusher now, inside the band he kept ({string.format("%.1f", flatTo(Crowd.Get(boss).position, vec(0, 0, 0)))} studs)`)
	check(string.find(afterwards, "3") ~= nil or string.find(afterwards, "4") ~= nil, "close enough for the arc or the charge")
	-- An ordinary hit still never staggers him, heavy or not.
	local standing = seen(boss).state
	Crowd.Damage(boss, 100, 7, vec(0, 0, 300), 20)
	step2()
	check(seen(boss).state ~= "stagger" and seen(boss).state ~= "airborne", `an ordinary heavy hit still never staggers him ({standing} -> {seen(boss).state})`)
	-- A rusher stands exposed through its recover; a shooter would back away from a player this
	-- close. That standing recover is the duel's punish window.
	local exposed = false
	local wasRecovering = true
	for _ = 1, 15 * 30 do
		step2()
		local now = seen(boss)
		-- A recover that has just begun, so it lasts through the steps below.
		if now.state == "recover" and now.attack >= 3 and not wasRecovering then
			exposed = true
			break
		end
		wasRecovering = now.state == "recover"
	end
	local stood = Crowd.Get(boss).position
	root.Position = stood + vec(0, 3, -3)
	step2(10)
	check(exposed and seen(boss).state == "recover" and (Crowd.Get(boss).position - stood).Magnitude == 0, "enraged he recovers as a rusher does: standing where he is, though the player is three studs away")
	root.Position = vec(0, 3, 0)

	-- Killed and spawned again: a new body calls a new guard.
	kill(boss)
	step2(12)
	local second = Crowd.Spawn("warlord", vec(0, 0, 40), "fight")
	waitFor(second, "attack", 60)
	step2(2)
	check(#guards(second) == 4 and Crowd.AliveCount() == 5, "a Warlord spawned again calls a new guard: `uses` belongs to the body")
	local third = Crowd.Spawn("warlord", vec(40, 0, 40), "fight")
	hit, verdict = tallied(third, 100)
	check(verdict == "guarded", "and a fresh Warlord is guarded again from his first moment")
	Crowd.Remove(third)
	-- Removed, not killed: they leave his guard all the same.
	for _, id in guards(second) do
		Crowd.Remove(id)
	end
	hit, verdict = tallied(second, 100)
	check(verdict == "plate", "guards that are removed rather than killed stop guarding too")
	Vitals.ToggleGod(player)

	-- Broken while he is not winding anything up: the reel, and his first duel windup right after.
	fresh()
	Vitals.ToggleGod(player)
	boss = Crowd.Spawn("warlord", vec(0, 0, 40), "fight")
	waitFor(boss, "attack", 60)
	step2(2)
	for _, id in guards(boss) do
		S2.slay(id)
	end
	waitFor(boss, "windup", 120)
	waitFor(boss, "recover", 60)
	waitFor(boss, "idle", 120)
	Crowd.Damage(boss, 100, 7, nil, nil)
	Crowd.Damage(boss, 100, 7, nil, nil)
	Crowd.Damage(boss, 100, 7, nil, nil)
	local idleBreak = fakeNow
	local path = S2.trace(boss, 15 * 3)
	local early: any = nil
	for _, mark in path do
		if mark.state == "windup" and early == nil then
			early = mark
		end
	end
	check(path[1].state == "stagger" and early ~= nil and early.attack >= 3 and early.at >= idleBreak + 1.0 - 1e-6 and early.at < idleBreak + 1.0 + 2 * DT, `broken between attacks: he winds up nothing during the reel, and his first enraged windup starts as it ends ({S2.names(path)})`)
	Vitals.ToggleGod(player)

	-- One strike that kills the last guard and then reaches him: one entry, no longer guarded.
	fresh()
	Vitals.ToggleGod(player)
	boss = Crowd.Spawn("warlord", vec(0, 0, 40), "fight")
	waitFor(boss, "attack", 60)
	step2(2)
	guard = guards(boss)
	for index = 1, 3 do
		S2.slay(guard[index])
	end
	local tally = Tally.New()
	local function strike(id: number, amount: number): ()
		local dealt, killed, verdictOf = Crowd.Damage(id, amount, 7, nil, nil)
		Tally.Add(tally, id, dealt, false, killed, verdictOf)
	end
	strike(boss, 100)
	local first = tally.hits[1]
	local wasGuarded = first.blocked == true and (first :: any).guarded == true
	strike(boss, 10)
	wasGuarded = wasGuarded and #tally.hits == 1 and (first :: any).guarded == true
	strike(guard[4], 100000)
	strike(guard[4], 100000)
	strike(boss, 100)
	check(wasGuarded and #tally.hits == 3 and first.blocked == nil and (first :: any).guarded == nil and first.plate == true and first.amount == 100, "a strike that is guarded, kills the last guard and then lands: his entry ends as a plate hit, the guarded mark gone")
	Vitals.ToggleGod(player)

	-- He is a large body (crowd.largeRadius 2.5, his radius 2.6): nothing smaller pushes him.
	fresh()
	root.Position = vec(0, 3, -90)
	boss = Crowd.Spawn("warlord", vec(0, 0, 40), "idle")
	local pawn = Crowd.Spawn("pawn", vec(2, 0, 40), "idle")
	step2()
	check(Crowd.Get(boss).position.X == 0 and near(Crowd.Get(pawn).position.X, 3.9, 1e-6), "the Warlord is large: a smaller body gives way to him by the whole overlap")
	-- And one that does not fight has no guard to call: its plate is a plate.
	hit, verdict = tallied(boss, 100)
	check(verdict == "plate", "a `guarded` kind in a passive set will never call a guard, so it is not guarded")

	-- The call is not always a single one.
	local function calls(kind: string): number
		fresh()
		Vitals.ToggleGod(player)
		local id = Crowd.Spawn(kind, vec(0, 0, 40), "fight")
		return id
	end
	local function fallAll(id: number): ()
		for _, info in risen do
			if info.summonerId == id and Crowd.Get(info.id) ~= nil then
				S2.slay(info.id)
			end
		end
	end
	local warden = calls("warden")
	hit, verdict = tallied(warden, 100)
	local before = verdict
	waitFor(warden, "attack", 60)
	step2(2)
	hit, verdict = tallied(warden, 100)
	local during = verdict
	fallAll(warden)
	hit, verdict = tallied(warden, 100)
	check(before == "guarded" and during == "guarded" and verdict == "plate", "a call with no `uses` limit: guarded until it has first been made, then only while its summons live (it will call again, and be guarded again)")
	Vitals.ToggleGod(player)
	local marshal = calls("marshal")
	waitFor(marshal, "attack", 60)
	step2(2)
	fallAll(marshal)
	hit, verdict = tallied(marshal, 100)
	local between = verdict
	waitFor(marshal, "recover", 120)
	waitFor(marshal, "attack", 200)
	step2(2)
	fallAll(marshal)
	hit, verdict = tallied(marshal, 100)
	check(between == "guarded" and verdict == "plate", "a call with `uses` 2: still guarded with the first guard dead and a call left; open once the second has been called and is dead")
	Vitals.ToggleGod(player)

	-- A plated summoner that is not `guarded` is not protected by what it summons.
	fresh()
	Vitals.ToggleGod(player)
	boss = Crowd.Spawn("captain", vec(0, 0, 40), "fight")
	waitFor(boss, "attack", 60)
	step2(2)
	hit, verdict = tallied(boss, 100)
	check(Crowd.AliveCount() == 3 and verdict == "plate", "a plated summoner without `guarded` is not protected by its summons")
	Vitals.ToggleGod(player)

	local Tune = S2.Tuning
	check(Tune.Validate("crowd.kinds.warlord.enrage.brain", "keepAway") and not Tune.Validate("crowd.kinds.warlord.enrage.brain", "fly"), "Tuning: enrage.brain must be a brain")
	check(Tune.Validate("crowd.kinds.warlord.attacks.1.uses", 2) and not Tune.Validate("crowd.kinds.warlord.attacks.1.uses", -1), "and `uses` may not go below 0")
end
S2.warlordTests()

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
