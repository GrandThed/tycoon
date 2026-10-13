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
	local a: any = { userId = 7, player = player, bot = false, waiting = false }
	local b: any = { userId = 8, player = player2, bot = false, waiting = false }
	local bot: any = { userId = -1001, player = nil, bot = true, waiting = false }
	check(not Vitals.RunLost({ a, b, bot }), "two standing: the run goes on")
	humanoid.Health = 5
	hooks.impact(arc(fakeNow))
	advance(0.15)
	gather()
	check(Vitals.IsDown(player) and not Vitals.IsDown(player2), "(A goes down, B stands)")
	check(not Vitals.RunLost({ a, b, bot }), "A down while B stands: the run goes on")
	local lost, fallen = Vitals.RunLost({ a, bot })
	check(lost and #fallen == 1 and fallen[1] == 7, "then B leaves: lost, A fallen")
	b.waiting = true
	lost, fallen = Vitals.RunLost({ a, b, bot })
	check(lost and #fallen == 1 and fallen[1] == 7, "or B respawns onto the pad: lost, the waiting one is no fighter")
	b.waiting = false
	humanoid2.Health = 0
	lost, fallen = Vitals.RunLost({ a, b, bot })
	check(lost and #fallen == 2, "or B dies outright (a reset): lost, both fallen")
	a.waiting = true
	b.waiting = true
	check(not Vitals.RunLost({ a, b, bot }) and not Vitals.RunLost({ bot }), "nobody in the fight (all on the pad, or bots alone) is not a lost run")
	a.waiting = false
	b.waiting = false
	Vitals.StandUp(player)
	check(not Vitals.RunLost({ a, b, bot }), "A standing again with B dead: the run goes on")
	humanoid2.Health = 130
	leave2()
	Vitals.SetMission(nil)
	clearIframes()
	fresh()
end
P5.lostTests()

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
