-- Regression cases for P5 Wave 1, the crowd in a mission (docs/INTERFACES.md "P5 contracts"):
-- appended after tests_s3.luau by run_harness.py, so every local of the earlier files is in
-- scope. Everything hangs off the P5 table (the 200-local limit). The range rules are proven by
-- every earlier file, which runs with no SetMission; the last group here proves SetMission(nil)
-- puts them back.

print("P5 wave 1")

local P5: any = { infos = {} }

-- Every kill the crowd reports from here on, as the run's callback receives it.
Crowd.OnKilled(function(id: number, byUserId: number, info: any)
	table.insert(P5.infos, { id = id, by = byUserId, info = info })
end)

function P5.scaleTests(): ()
	print(" SetScales and hpMult")
	fresh()
	table.clear(P5.infos)
	root.Position = vec(0, 3, -90)
	Crowd.SetScales({ hp = 2, plate = 3 })
	local plated = Crowd.Spawn("plated", vec(20, 0, 20), "idle")
	local boosted = Crowd.Spawn("pawn", vec(-20, 0, 20), "idle", nil, 1.5)
	step2()
	check(Crowd.Get(plated).maxHp == 320 and Crowd.Get(boosted).maxHp == 120, "maxHp = hp x scales.hp x hpMult (160 x 2; 40 x 2 x 1.5)")
	local dealt, _killed, verdict = Crowd.Damage(plated, 50, 7, nil, nil)
	step2()
	check(verdict == "plate" and dealt == 50 and near(seen(plated).hpFraction, 220 / 270, 1 / 255), "the plate is plate x scales.plate (90 x 3): 50 off it leaves 220 of 270")
	Crowd.SetScales({ hp = 0 / 0, plate = -1 })
	local kept = Crowd.Spawn("pawn", vec(-30, 0, 20), "idle")
	check(Crowd.Get(kept).maxHp == 80, "a non-finite or negative scale keeps the old one")

	fresh()
	Vitals.ToggleGod(player)
	Crowd.SetScales({ hp = 2, plate = 1 })
	local boss = Crowd.Spawn("caller", vec(0, 0, 50), "fight", nil, 3)
	waitFor(boss, "attack", 60)
	step2(2)
	local summons = 0
	local allScaled = true
	for _, info in risen do
		if info.summonerId == boss then
			summons += 1
			allScaled = allScaled and info.maxHp == 80
		end
	end
	check(Crowd.Get(boss).maxHp == 6000, "a boss body takes its party factor (1000 x 2 x 3)")
	check(summons == 12 and allScaled, `its summons take scales.hp and no hpMult (40 x 2 = 80, {summons} of them)`)
	Vitals.ToggleGod(player)
	Crowd.SetScales({ hp = 1, plate = 1 })
	fresh()
	local plain = Crowd.Spawn("plated", vec(20, 0, 20), "idle")
	step2()
	check(Crowd.Get(plain).maxHp == 160 and near(seen(plain).hpFraction, 1, 1 / 255), "scales { 1, 1 } are the range's numbers")
end
P5.scaleTests()

function P5.damageTests(): ()
	print(" Damage with a tier scale (ruling 9)")
	fresh()
	root.Position = vec(0, 3, -90)
	local elite = Crowd.Spawn("armoured", vec(20, 0, 20), "idle")
	local dealt, killed, verdict = Crowd.Damage(elite, 30, 7, nil, nil, 4)
	check(near(dealt, 48) and near(Crowd.Get(elite).hp, 112) and not killed and verdict == nil, "armour on the tier-1 amount, then the HP loss scaled: (30 - 18) x 4 = 48")
	dealt = Crowd.Damage(elite, 10, 7, nil, nil, 4)
	check(near(dealt, 4) and near(Crowd.Get(elite).hp, 108), "under the armour a hit chips its floor x scale (1 x 4), never (40 - 18)")
	dealt = Crowd.Damage(elite, 30, 7, nil, nil, nil)
	check(near(dealt, 12), "scale nil = 1, as in the range")

	local platedBody = Crowd.Spawn("plated", vec(-20, 0, 20), "idle")
	local d, _k, v = Crowd.Damage(platedBody, 30, 7, nil, nil, 10)
	check(v == "blocked" and d == 0, "heavyHit judges the tier-1 amount: 30 at x10 is still blocked")
	d, _k, v = Crowd.Damage(platedBody, 50, 7, nil, nil, 10)
	step2()
	check(v == "plate" and d == 50 and near(seen(platedBody).hpFraction, 40 / 90, 1 / 255), "a plate hit takes and returns the unscaled amount (the number matches the bar)")
	d, _k, v = Crowd.Damage(platedBody, 40, 7, nil, nil, 10)
	check(v == "broke" and d == 40 and Crowd.Get(platedBody).hp == 160, "the break is unscaled too, HP untouched")

	fresh()
	local fighter = Crowd.Spawn("armoured", vec(0, 0, 5), "fight")
	check(waitFor(fighter, "windup", 40), "an elite winds up")
	step2(2)
	Crowd.Damage(fighter, 24, 7, vec(0, 0, 16), 4, 10)
	step2()
	check(seen(fighter).attack == 1, "the interrupt judges the tier-1 amount: a light hit at x10 does not cancel a heavy-only windup")
	fresh()
end
P5.damageTests()

function P5.killTests(): ()
	print(" OnKilled info, damageBy, KillAll (ruling 14)")
	fresh()
	table.clear(P5.infos)
	root.Position = vec(0, 3, -90)
	local body = Crowd.Spawn("plated", vec(20, 0, 20), "idle")
	Crowd.Damage(body, 50, 7, nil, nil, 2)
	Crowd.Damage(body, 60, 8, nil, nil, 2)
	Crowd.Damage(body, 25, 7, nil, nil, 2)
	local dealt, killed = Crowd.Damage(body, 200, 9, nil, nil, 2)
	check(killed and near(dealt, 390), "the killing blow still reports its whole number ((200 - 5) x 2)")
	local record = P5.infos[1]
	check(#P5.infos == 1 and record.id == body and record.by == 9 and record.info.byUserId == 9, "OnKilled hands (id, byUserId, info)")
	check(record.info.kind == "plated" and record.info.boss == false and near(record.info.position.X, 20), "info carries the kind, the boss flag and where it died")
	local by = record.info.damageBy
	check(near(by[7], 40) and near(by[9], 120) and by[8] == nil, "damageBy books HP removed: 40 for 7, the blow capped at the 120 left, nothing for the plate's breaker")

	fresh()
	table.clear(P5.infos)
	Vitals.ToggleGod(player)
	local boss = Crowd.Spawn("caller", vec(0, 0, 50), "fight")
	waitFor(boss, "attack", 60)
	step2(2)
	kill(boss + 1)
	kill(boss)
	local first = P5.infos[1]
	local second = P5.infos[2]
	check(#P5.infos == 2 and first.info.kind == "fodder" and first.info.boss == false, "a summon killed is a kill like any other")
	check(second ~= nil and second.id == boss and second.info.boss == true and second.info.kind == "caller", "the boss's kill says boss")
	check(Crowd.AliveCount() == 0, "its other summons went with it, and paid nothing (no callback)")
	Vitals.ToggleGod(player)

	fresh()
	table.clear(P5.infos)
	for index = 1, 3 do
		Crowd.Spawn("pawn", vec(10 * index, 0, 30), "idle")
	end
	local count = Crowd.KillAll(0)
	local byNobody = true
	for _, entry in P5.infos do
		byNobody = byNobody and entry.by == 0 and entry.info.byUserId == 0
	end
	check(count == 3 and #P5.infos == 3 and byNobody and Crowd.AliveCount() == 0, "KillAll: every living body dies through the death path, paid, credited to nobody")
	check(Crowd.KillAll(0) == 0 and #P5.infos == 3, "a body lying dead is not killed twice")
	step2(15)
	fresh()
end
P5.killTests()

function P5.missionTests(): ()
	print(" VitalsService in a mission")
	fresh()
	table.clear(granted)
	P5.judged = true
	P5.maxHp = 145
	P5.downs = {}
	P5.sentFirst = true
	local function rules(scale: number, share: number): any
		return {
			mayJudge = function(who: any): boolean
				return who ~= player or P5.judged
			end,
			onDown = function(who: any): ()
				-- The down must already have been sent when the run hears of it.
				local sent = false
				for _, call in fired do
					if call.player == player and call.name == "CombatFx" then
						for _, fx in call.payload do
							sent = sent or (fx.kind == "hurt" and fx.down == true)
						end
					end
				end
				P5.sentFirst = P5.sentFirst and sent
				table.insert(P5.downs, who)
			end,
			maxHpOf = function(): number
				return P5.maxHp
			end,
			damageScale = scale,
			regenShare = share,
		}
	end
	Vitals.SetMission(rules(1.5, 0))
	Vitals.PrepareCharacter(player, character)
	check(humanoid.MaxHealth == 145 and humanoid.Health == 145, "maxHpOf sizes the bar (ruling 11)")
	gather()
	table.clear(log)
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	gather()
	local hurt = of(log, "hurt")[1]
	check(humanoid.Health == 133 and hurt ~= nil and hurt.amount == 12, "damageScale: a lunge of 8 lands as 12")
	Vitals.SetMission(rules(0.01, 0))
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	check(humanoid.Health == 132, "a scaled hit never rounds to nothing (8 x 0.01 -> 1)")
	Vitals.SetMission(rules(0.3, 0))
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	check(humanoid.Health == 130, "and it is rounded (8 x 0.3 -> 2)")

	print(" mayJudge (ruling 13)")
	advance(1)
	gather()
	table.clear(log)
	P5.judged = false
	check(hooks.canTarget(player) == false, "a player the run rules out is no enemy's target")
	hooks.impact(arc(fakeNow))
	hooks.impact(arc(fakeNow, 8))
	advance(0.15)
	gather()
	check(humanoid.Health == 130 and #of(log, "hurt") == 0, "and no instant shape judges them, aimed at them or not")
	P5.judged = true
	local function lob(leaveFirst: boolean): number
		fresh()
		Vitals.SetMission(rules(1, 0))
		local before = humanoid.Health
		local lobber = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
		waitFor(lobber, "windup", 40)
		waitFx("area", 15)
		kill(lobber)
		table.clear(log)
		P5.judged = not leaveFirst
		advance(2.5)
		gather()
		P5.judged = true
		return before - humanoid.Health
	end
	check(lob(false) == 18, "(a lob thrown at a judged player lands: 18)")
	check(lob(true) == 0 and #of(log, "hurt") == 0, "one thrown at them lands on nobody once the run rules them out")

	print(" regen, down, StandUp")
	fresh()
	Vitals.SetMission(rules(1, 0.1))
	humanoid.Health = 50
	advance(5)
	local from = humanoid.Health
	advance(1)
	check(near(humanoid.Health - from, 14.5, 1.0), `regen is regenShare x MaxHealth a second (14.5; {string.format("%.1f", humanoid.Health - from)})`)
	Vitals.SetMission(rules(1, 0))
	advance(1)
	gather()
	table.clear(log)
	table.clear(P5.downs)
	humanoid.Health = 5
	hooks.impact(arc(fakeNow))
	advance(0.15)
	gather()
	local downFx = of(log, "hurt")
	local last = downFx[#downFx]
	check(Vitals.IsDown(player) and humanoid.Health == 1 and last ~= nil and last.down == true and last.upAt == nil, "a down in a mission carries no upAt")
	check(#P5.downs == 1 and P5.downs[1] == player and P5.sentFirst, "onDown is called once, after the batch with the down has gone")
	advance(10)
	check(Vitals.IsDown(player) and humanoid.Health == 1 and #P5.downs == 1, "a down never ends by itself, and onDown is not called again")
	check(hooks.canTarget(player) == false, "a downed player is no target")
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	check(humanoid.Health == 1 and #P5.downs == 1, "nor hit")
	Vitals.PrepareCharacter(player, character)
	check(Vitals.IsDown(player) and humanoid.Health == 1, "a new character stays down: only the run ends a down")
	table.clear(granted)
	Vitals.StandUp(player)
	check(not Vitals.IsDown(player) and humanoid.Health == 145 and hooks.canTarget(player), "StandUp: on their feet at full health")
	check(#granted == 1 and granted[1] == config.player.getUpIframes, "with the get-up i-frames")
	clearIframes()
	advance(1)

	print(" RefreshMaxHp, SetGod")
	humanoid.Health = 72.5
	P5.maxHp = 200
	Vitals.RefreshMaxHp(player)
	check(humanoid.MaxHealth == 200 and near(humanoid.Health, 100), "RefreshMaxHp keeps the share of the bar (half of 145 -> half of 200)")
	P5.maxHp = 145
	Vitals.RefreshMaxHp(player)
	gather()
	table.clear(log)
	Vitals.SetGod(player, true)
	local godFrom = humanoid.Health
	hooks.impact(arc(fakeNow))
	advance(0.15)
	gather()
	local voided = of(log, "hurt")[1]
	check(humanoid.Health == godFrom and voided ~= nil and voided.dodged == true, "SetGod voids hits as god does")
	Vitals.SetGod(player, false)
	local _taken, _downs, god = Vitals.Readout(player)
	check(god == false, "and SetGod false ends it")

	print(" back to the range's rules")
	Vitals.SetMission(nil)
	Vitals.PrepareCharacter(player, character)
	check(humanoid.MaxHealth == 130 and humanoid.Health == 130, "SetMission(nil): the tier-1 body again")
	advance(1)
	gather()
	table.clear(log)
	table.clear(P5.downs)
	humanoid.Health = 5
	hooks.impact(arc(fakeNow))
	advance(0.15)
	gather()
	local rangeDown = of(log, "hurt")[1]
	check(rangeDown ~= nil and rangeDown.down == true and rangeDown.upAt ~= nil and #P5.downs == 0, "a range down has its upAt and calls no run")
	advance(2.5)
	check(not Vitals.IsDown(player) and humanoid.Health == 130, "and gets up by itself")
	clearIframes()
	fresh()
end
P5.missionTests()

function P5.lostTests(): ()
	print(" ruling 18 from state: the last one standing goes")
	fresh()
	Vitals.SetMission({
		mayJudge = function(): boolean
			return true
		end,
		onDown = function(): () end,
		maxHpOf = function(): number
			return 145
		end,
		damageScale = 1,
		regenShare = 0,
	})
	Vitals.PrepareCharacter(player, character)
	join2(vec(30, 3, 30))
	local a: any = { userId = 7, player = player, waiting = false }
	local b: any = { userId = 8, player = player2, waiting = false }
	check(not Vitals.RunLost({ a, b }), "two standing: the run goes on")
	humanoid.Health = 5
	hooks.impact(arc(fakeNow))
	advance(0.15)
	gather()
	check(Vitals.IsDown(player) and not Vitals.IsDown(player2), "(A goes down, B stands)")
	check(not Vitals.RunLost({ a, b }), "A down while B stands: the run goes on")
	local lost, fallen = Vitals.RunLost({ a })
	check(lost and #fallen == 1 and fallen[1] == 7, "then B leaves: lost, A fallen")
	lost, fallen = Vitals.RunLost({ a }, true)
	check(not lost and #fallen == 1, "but a clear field wins: the same down with the wave's last body dead loses nothing")
	check((Vitals.RunLost({ a }, false)), "(and with a body still alive it is lost)")
	b.waiting = true
	lost, fallen = Vitals.RunLost({ a, b })
	check(lost and #fallen == 1 and fallen[1] == 7, "or B respawns onto the pad: lost, the waiting one is no fighter")
	b.waiting = false
	humanoid2.Health = 0
	lost, fallen = Vitals.RunLost({ a, b })
	check(lost and #fallen == 2, "or B dies outright (a reset): lost, both fallen")
	a.waiting = true
	b.waiting = true
	check(not Vitals.RunLost({ a, b }) and not Vitals.RunLost({}), "nobody in the fight (all on the pad, or nobody at all) is not a lost run")
	a.waiting = false
	b.waiting = false
	Vitals.StandUp(player)
	check(not Vitals.RunLost({ a, b }), "A standing again with B dead: the run goes on")
	humanoid2.Health = 130
	leave2()
	Vitals.SetMission(nil)
	clearIframes()
	fresh()
end
P5.lostTests()

function P5.reviewTests(): ()
	print(" a run does not start before every human has a body")
	fresh()
	local a: any = { userId = 7, player = player, waiting = false }
	local b: any = { userId = 8, player = player2, waiting = false }
	check(player2.Character == nil and not Vitals.AllHaveBodies({ a, b }), "a human whose character has not spawned: not yet")
	check((Vitals.RunLost({ b })), "(a run would read that missing body as fallen, and end in its first frame)")
	join2(vec(30, 3, 30))
	check(Vitals.AllHaveBodies({ a, b }), "every human has a living body: the run may start")
	humanoid2.Health = 0
	check(not Vitals.AllHaveBodies({ a, b }), "a dead body is no body")
	humanoid2.Health = 130
	leave2()
	check(Vitals.AllHaveBodies({}), "nobody never holds a start")

	print(" ClearThreats (the wave's clear, the run's end)")
	fresh()
	local lobber = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
	waitFor(lobber, "windup", 40)
	check(waitFx("area", 15) ~= nil, "(a lob is in the air)")
	kill(lobber)
	table.clear(log)
	Vitals.ClearThreats()
	advance(2.5)
	gather()
	check(humanoid.Health == 130 and #of(log, "hurt") == 0, "what was in the air lands on nobody once the threats are cleared")

	print(" the [Perf] line counts only steps with a living body")
	fresh()
	local lines: { string } = {}
	local realPrint = print
	print = function(...)
		local text = tostring((...))
		if string.find(text, "[Perf]", 1, true) ~= nil then
			table.insert(lines, text)
		else
			realPrint(...)
		end
	end
	Crowd.SetPerfLog(1)
	step2(45)
	local idle = #lines
	for index = 1, 3 do
		Crowd.Spawn("pawn", vec(10 * index, 0, 30), "idle")
	end
	step2(20)
	local busy = #lines
	Crowd.KillAll(0)
	step2(45)
	local after = #lines
	Crowd.SetPerfLog(0)
	print = realPrint
	local line = lines[1] or ""
	local steps = tonumber(string.match(line, "%((%d+) steps")) or 0
	check(idle == 0, "three seconds of an empty field print nothing")
	check(busy == 1 and string.find(line, "peak alive 3", 1, true) ~= nil and steps >= 15 and steps <= 17, `one line over a second of a living crowd ({line})`)
	check(after == busy, "and none once the field is empty again")
	fresh()
end
P5.reviewTests()

function P5.ringTests(): ()
	print(" PositionRing: the server's own reading of a player's speed (ruling 7)")
	local Ring = load("PositionRing")
	-- The speed half of PositionRing.Motion.
	local function speedOf(history: any, now: number, position: any, window: number, span: number): number
		local speed = Ring.Motion(history, now, position, window, span)
		return speed
	end
	local WINDOW = 0.3
	local FRAME = 1 / 60
	local T0 = 100
	local DASH = 20 / 0.15
	-- Where a body is at `frame`: a 20-stud dash of 0.15 s that starts at frame 0, or the spot.
	local function place(frame: number, still: boolean?): any
		return vec(if still then 0 else math.clamp(frame * FRAME, 0, 0.15) * DASH, 0, 0)
	end
	-- The reading at `frame` of a ring that recorded every frame from `first` to it. The times
	-- are built as T0 + frame * FRAME on purpose: at T0 = 100 six frames from frame 1 come out a
	-- hair under 0.1 s in doubles (so the anchor is the seventh, 19.05), while later ones come
	-- out at it. The server's clock behaves the same way; the expected values below are A's.
	local function reading(capacity: number, first: number, frame: number, span: number, still: boolean?): number
		local ring = Ring.New(capacity)
		for at = first, frame do
			Ring.Record(ring, T0 + at * FRAME, place(at, still))
		end
		return speedOf(ring, T0 + frame * FRAME, place(frame, still), WINDOW, span)
	end
	-- Do the readings at `frames` match `wanted` (1e-3)? Also returns them, for the label.
	local function match(capacity: number, first: number, span: number, frames: { number }, wanted: { number }, still: boolean?): (boolean, string)
		local ok = true
		local shown = {}
		for index, frame in frames do
			local got = reading(capacity, first, frame, span, still)
			ok = ok and near(got, wanted[index], 1e-3)
			table.insert(shown, string.format("%.4f", got))
		end
		return ok, table.concat(shown, " / ")
	end
	local RAMP = { 19.0476, 57.1429, 95.2381, 133.3333 }
	local AT = { 1, 3, 5, 9 }

	local ok, shown = match(120, -60, 0.1, AT, RAMP)
	check(ok, `1: a 20-stud, 0.15 s dash from standing reads 19.05 / 57.14 / 95.24 / 133.33 at frames 1 / 3 / 5 / 9 ({shown})`)
	check(reading(120, -60, 6, 0.1) < 130 and near(reading(120, -60, 7, 0.1), 133.3333, 1e-3), "   and reaches its 133.33 at frame 7")
	ok, shown = match(120, -60, 0.05, AT, { 33.3333, 100.0, 133.3333, 133.3333 })
	check(ok, `1b: over a span of 0.05 it reads 33.33 / 100 / 133.33 / 133.33 ({shown})`)
	ok, shown = match(120, -60, 0.1, { 1, 9, 60 }, { 0, 0, 0 }, true)
	check(ok, `2: standing still reads 0 ({shown})`)

	local young = Ring.New(120)
	Ring.Record(young, T0, vec(0, 0, 0))
	local early = speedOf(young, T0 + 0.01, vec(5, 0, 0), WINDOW, 0.1)
	check(near(early, 50, 1e-3), `3: a history shorter than the span under-reads: 5 studs in 0.01 s is 50, the divisor floored at the span ({string.format("%.1f", early)})`)
	ok, shown = match(120, 0, 0.1, AT, { 22.2222, 66.6667, 111.1111, 133.3333 })
	check(ok, `3b: a dash with no history before it reads 22.22 / 66.67 / 111.11 / 133.33 ({shown})`)

	local fallback = true
	local labels = {}
	for _, span in { 0, 0 / 0, -1, 0.5 } do
		local same, got = match(120, -60, span, { 1, 9, 18 }, { 7.0175, 66.6667, 66.6667 })
		fallback = fallback and same
		table.insert(labels, got)
	end
	check(fallback, `4: a span of 0, NaN, -1 or 0.5 falls back to the whole window: 7.02 / 66.67 / 66.67 ({labels[1]})`)

	ok, shown = match(120, -300, 0.1, AT, RAMP)
	check(ok, `5: a ring that has wrapped (300 samples through 120 slots) reads the same ({shown})`)
	ok, shown = match(30, -300, 0.1, AT, RAMP)
	check(ok, `5b: and so does one of 30 slots ({shown})`)

	ok, shown = match(120, -60, 0.1, { 9, 18, 27, 28, 33, 34, 40 }, { 133.3333, 133.3333, 133.3333, 111.1111, 19.0476, 0, 0 })
	check(ok, `6: the reading holds for the window after the dash and is gone by frame 34 ({shown})`)

	local blank = Ring.New(120)
	check(speedOf(blank, T0, vec(5, 0, 0), WINDOW, 0.1) == 0, "7: an empty history reads 0")
	check(speedOf(young, T0 + 0.01, vec(5, 0, 0), 0, 0.1) == 0 and speedOf(young, T0 + 0.01, vec(5, 0, 0), -1, 0.1) == 0 and speedOf(young, T0 + 0.01, vec(5, 0, 0), 0 / 0, 0.1) == 0, "7b: a window of 0, -1 or NaN reads 0")
	Ring.Clear(young)
	check(speedOf(young, T0 + 0.01, vec(5, 0, 0), WINDOW, 0.1) == 0 and young.count == 0, "8: Clear forgets every sample")
	check(Ring.New(0).capacity == 1 and Ring.New(2.9).capacity == 2, "9: the capacity is floored, and at least 1")

	-- The L2 W2 third fix round's m1: the way the fastest stretch went, which the aim rule leads by.
	local function wayAt(frame: number, still: boolean?): (number, any)
		local ring = Ring.New(120)
		for at = -60, frame do
			Ring.Record(ring, T0 + at * FRAME, place(at, still))
		end
		return Ring.Motion(ring, T0 + frame * FRAME, place(frame, still), WINDOW, 0.1)
	end
	local dashSpeed, dashWay = wayAt(9)
	check(near(dashSpeed, 133.3333, 1e-3) and near(dashWay.X, 1, 1e-9) and dashWay.Y == 0 and dashWay.Z == 0, `10: the dash's way is east, a unit vector, beside its 133.33 ({dashSpeed}; {dashWay.X}, {dashWay.Y}, {dashWay.Z})`)
	local _, stillWay = wayAt(9, true)
	local _, emptyWay = Ring.Motion(blank, T0, vec(5, 0, 0), WINDOW, 0.1)
	local _, shutWay = Ring.Motion(young, T0 + 0.01, vec(5, 0, 0), 0 / 0, 0.1)
	local function none(way: any): boolean
		return way.X == 0 and way.Y == 0 and way.Z == 0
	end
	check(none(stillWay) and none(emptyWay) and none(shutWay), "10b: standing still, an empty history or a NaN window: no way at all")
	-- A fast stretch east, then a slow one north: the way is the fast one's, the stretch the
	-- speed was read on.
	local turn = Ring.New(120)
	for at = 0, 6 do
		Ring.Record(turn, T0 + at * FRAME, vec(at * 2, 0, 0))
	end
	for at = 7, 12 do
		Ring.Record(turn, T0 + at * FRAME, vec(12, 0, (at - 6) * 0.2))
	end
	local turnSpeed, turnWay = Ring.Motion(turn, T0 + 12 * FRAME, vec(12, 0, 1.2), WINDOW, 0.1)
	check(turnSpeed > 100 and turnWay.X > 0.99 and math.abs(turnWay.Magnitude - 1) < 1e-9, `10c: east fast, then north slowly: the way is the fast stretch's, east ({turnSpeed}; {turnWay.X}, {turnWay.Z})`)

	print(" Tuning: shooting.originSpeedSeconds")
	config.shooting.originSpeedSeconds = 0.1
	local Tune = S2.Tuning
	check(Tune.Validate("shooting.originSpeedSeconds", 0.05) and Tune.Validate("shooting.originSpeedSeconds", 0.3), "the span may be anything positive up to originLagMaxSeconds")
	check(not Tune.Validate("shooting.originSpeedSeconds", 0) and not Tune.Validate("shooting.originSpeedSeconds", -0.1) and not Tune.Validate("shooting.originSpeedSeconds", 0.31) and not Tune.Validate("shooting.originSpeedSeconds", 0 / 0), "never 0, negative, NaN or longer than that window")
end
P5.ringTests()

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
