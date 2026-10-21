-- Cases for L4 W1b's dash proof (docs/prompts/l4-w1b-contract.md §4, L4B-7): a dash's i-frames
-- count only once the server's own ring of positions has seen the dash. DashProof.Verdict on built
-- rings sampled at 60 Hz and 20 Hz, with bunched updates (a) to (f); DashProof.Open's windows run
-- through the real VitalsService commit rule (g); the shipped ProvingGrounds.json's proof speed
-- (h); DashProof.Rule and Open on their own. Appended by run_harness.py after tests.luau, so its
-- locals are in scope (check, near, load, vec, config, FIXTURES, fakeNow, the VitalsService
-- fixture: Vitals, player, character, root, humanoid, iframes, hooks, lunge, vitalsBeat, drain).
-- Everything hangs off the L4B table (the bundle's 200-local limit) and every group runs behind
-- L4B.group, so a throw is one failing check. WeaponService (OnDash's claim, trackAir's call,
-- openIframes' attribute) cannot be loaded here: run_harness.py reads those lines as text.

print("L4 W1b: the dash proof (DashProof, L4B-7)")

local L4B: any = {
	Proof = load("DashProof"),
	Ring = load("PositionRing"),
	-- The contract's numbers (§4): a dash of 20 studs in 0.15 s (133 studs/s), the walk 20 studs/s,
	-- a proof of half the dash's speed (66.7 studs/s) over 0.05 s, the lookback 0.3 s.
	movement = {
		walkSpeed = 20,
		dashDistance = 20,
		dashSeconds = 0.15,
		dashIframes = 0.25,
		dashProofShare = 0.5,
		dashProofSeconds = 0.05,
	},
	shooting = { originLagSeconds = 0.05, originLagMaxSeconds = 0.3 },
	-- A course's clock starts here; frames are whole multiples of 1 / hz from it.
	BASE = 100,
}

function L4B.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `{name} stopped: {tostring(problem)}`)
	end
end

function L4B.rule(): any
	return L4B.Proof.Rule(L4B.movement, L4B.shooting)
end

-- A dash's true path: from x = 0 at `startAt`, `distance` studs along +X at the dash's speed, then
-- still (a wall: `distance` short of the dash's 20).
function L4B.dash(startAt: number, distance: number?): (t: number) -> any
	local speed = L4B.movement.dashDistance / L4B.movement.dashSeconds
	local reach = distance or L4B.movement.dashDistance
	return function(t: number): any
		local x = math.min(math.max(t - startAt, 0) * speed, reach)
		return vec(x, 3, 0)
	end
end

-- The server's samples of a true path over `seconds` from BASE: one per frame at `hz`. `bunched`:
-- every other frame holds the frame before's position, so two updates arrive in one frame.
function L4B.samples(path: (t: number) -> any, hz: number, seconds: number, bunched: boolean?): { any }
	local out = {}
	local frames = math.floor(seconds * hz + 0.5)
	for k = 0, frames do
		local t = L4B.BASE + k / hz
		local seen = if bunched and k % 2 == 1 then L4B.BASE + (k - 1) / hz else t
		table.insert(out, { t = t, position = path(seen) })
	end
	return out
end

-- WeaponService's trackAir on those samples: each frame records its sample, and from the frame of
-- the claim on asks Verdict until it is not pending. Returns the verdict and the time it came, or
-- "pending" and nil.
function L4B.judge(samples: { any }, claimAt: number, rule: any): (string, number?)
	local history = L4B.Ring.New(120)
	for _, sample in samples do
		L4B.Ring.Record(history, sample.t, sample.position)
		if sample.t >= claimAt - 1e-9 then
			local verdict = L4B.Proof.Verdict(history, sample.t, sample.position, claimAt, rule)
			if verdict ~= "pending" then
				return verdict, sample.t
			end
		end
	end
	return "pending", nil
end

-- The first sample that has moved from the first one's place.
function L4B.firstMoving(samples: { any }): number?
	local start = samples[1].position
	for _, sample in samples do
		if (sample.position - start).Magnitude > 1e-6 then
			return sample.t
		end
	end
	return nil
end

function L4B.ruleTests(): ()
	print(" Rule: from movement and shooting")
	local rule = L4B.rule()
	check(rule ~= nil and near(rule.speed, 200 / 3, 1e-9), "the proof speed is dashProofShare x dashDistance / dashSeconds (66.7)")
	check(rule ~= nil and rule.span == 0.05 and rule.lookback == 0.3 and near(rule.lapse, 0.45, 1e-9), "span dashProofSeconds, lookback originLagMaxSeconds, lapse dashSeconds + lookback (0.45)")
	local missing = table.clone(L4B.movement)
	missing.dashProofShare = nil
	check(L4B.Proof.Rule(missing, L4B.shooting) == nil, "no rule without dashProofShare")
	local zero = table.clone(L4B.movement)
	zero.dashProofShare = 0
	check(L4B.Proof.Rule(zero, L4B.shooting) == nil, "nor with a share of 0 (a still body would prove it)")
	local nan = table.clone(L4B.movement)
	nan.dashProofSeconds = 0 / 0
	check(L4B.Proof.Rule(nan, L4B.shooting) == nil, "nor with a NaN span")
	check(L4B.Proof.Rule(L4B.movement, { originLagMaxSeconds = 0 }) ~= nil, "a lookback of 0 is a rule")
end
L4B.group("dash proof: Rule", L4B.ruleTests)

-- (a) A real dash, its motion seen from the claim on.
function L4B.realDashTests(): ()
	print(" (a) a real dash is proven within 0.05 s of its first moving sample")
	local rule = L4B.rule()
	for _, case in { { hz = 60, bunched = false }, { hz = 60, bunched = true }, { hz = 20, bunched = false }, { hz = 20, bunched = true } } do
		for _, lead in { 0, 0.02 } do
			local claimAt = L4B.BASE + 0.1
			local samples = L4B.samples(L4B.dash(claimAt + lead), case.hz, 1, case.bunched)
			local verdict, at = L4B.judge(samples, claimAt, rule)
			local moving = L4B.firstMoving(samples)
			local label = `{case.hz} Hz{if case.bunched then ", bunched" else ""}, motion {lead} s after the claim`
			check(verdict == "proven" and at ~= nil and moving ~= nil and at - moving <= 0.05 + 1e-9, `(a) {label}: proven {if at ~= nil and moving ~= nil then string.format("%.3f", at - moving) else "never"} s after the first moving sample`)
		end
	end
end
L4B.group("dash proof: (a)", L4B.realDashTests)

-- (b) A still body: a forged dash.
function L4B.stillTests(): ()
	print(" (b) a still body is never proven, and lapses at 0.45 s")
	local rule = L4B.rule()
	local samples = L4B.samples(function(_t: number): any
		return vec(4, 3, -2)
	end, 60, 3)
	for _, offset in { 0, 0.37, 1.13 } do
		local claimAt = L4B.BASE + offset
		local verdict, at = L4B.judge(samples, claimAt, rule)
		check(verdict == "lapsed" and at ~= nil and at >= claimAt + 0.45 - 1e-9 and at <= claimAt + 0.45 + 1 / 60 + 1e-9, `(b) a claim {offset} s in: lapsed at {if at ~= nil then string.format("%.3f", at - claimAt) else "never"} s, the first frame past 0.45`)
	end
end
L4B.group("dash proof: (b)", L4B.stillTests)

-- (c) Walking, the fastest a body goes without a dash.
function L4B.walkTests(): ()
	print(" (c) a walk at walkSpeed is never proven, bunched or not")
	local rule = L4B.rule()
	local walk = function(t: number): any
		return vec((t - L4B.BASE) * L4B.movement.walkSpeed, 3, 0)
	end
	for _, case in { { hz = 60, bunched = true }, { hz = 20, bunched = true }, { hz = 60, bunched = false } } do
		local verdict = L4B.judge(L4B.samples(walk, case.hz, 2, case.bunched), L4B.BASE + 0.5, rule)
		check(verdict == "lapsed", `(c) walking at 20 studs/s, {case.hz} Hz{if case.bunched then " bunched" else ""}: {verdict}`)
	end
end
L4B.group("dash proof: (c)", L4B.walkTests)

-- (d) A fall far faster than the proof speed.
function L4B.fallTests(): ()
	print(" (d) a fall at 120 studs/s is never proven (flat)")
	local rule = L4B.rule()
	local fall = function(t: number): any
		return vec(1, 300 - (t - L4B.BASE) * 120, 1)
	end
	local verdict = L4B.judge(L4B.samples(fall, 60, 1, true), L4B.BASE + 0.2, rule)
	check(verdict == "lapsed", `(d) a fall of 120 studs/s: {verdict}`)
end
L4B.group("dash proof: (d)", L4B.fallTests)

-- (e) Motion that replicated before the remote arrived.
function L4B.lookbackTests(): ()
	print(" (e) motion before the claim proves it within the lookback, and never past it")
	local rule = L4B.rule()
	local claimAt = L4B.BASE + 1
	-- The dash ended 0.1 s before the claim: well inside the lookback (0.3).
	local inside = L4B.samples(L4B.dash(claimAt - 0.25), 60, 2)
	local verdict, at = L4B.judge(inside, claimAt, rule)
	check(verdict == "proven" and at ~= nil and at <= claimAt + 1 / 60 + 1e-9, `(e) a dash that ended 0.1 s before the claim: {verdict} at {if at ~= nil then string.format("%.3f", at - claimAt) else "never"} s`)
	-- Ended 0.2 s before the claim: still inside.
	verdict = L4B.judge(L4B.samples(L4B.dash(claimAt - 0.35), 60, 2), claimAt, rule)
	check(verdict == "proven", `(e) one that ended 0.2 s before: {verdict}`)
	-- Ended 0.45 s before: past the lookback and its stretch.
	verdict = L4B.judge(L4B.samples(L4B.dash(claimAt - 0.6), 60, 2), claimAt, rule)
	check(verdict == "lapsed", `(e) one that ended 0.45 s before: {verdict}`)
	verdict = L4B.judge(L4B.samples(L4B.dash(claimAt - 0.6), 20, 2, true), claimAt, rule)
	check(verdict == "lapsed", `(e) and the same at 20 Hz, bunched: {verdict}`)
end
L4B.group("dash proof: (e)", L4B.lookbackTests)

-- (f) A dash into a wall.
function L4B.wallTests(): ()
	print(" (f) a dash stopped by a wall after 2 studs is never proven")
	local rule = L4B.rule()
	local claimAt = L4B.BASE + 0.5
	for _, case in { { hz = 60, bunched = false }, { hz = 60, bunched = true }, { hz = 20, bunched = false } } do
		local verdict = L4B.judge(L4B.samples(L4B.dash(claimAt, 2), case.hz, 2, case.bunched), claimAt, rule)
		check(verdict == "lapsed", `(f) 2 studs then a wall, {case.hz} Hz{if case.bunched then " bunched" else ""}: {verdict}`)
	end
	-- 6 studs then a wall is a dash the ring saw: over the 3.3 a stretch of 0.05 s needs, and the
	-- 4.4 of one of 0.067 s (a 60 Hz ring's anchor may sit four frames back).
	local verdict = L4B.judge(L4B.samples(L4B.dash(claimAt, 6), 60, 2), claimAt, rule)
	check(verdict == "proven", `(f) 6 studs then a wall is proven: {verdict}`)
end
L4B.group("dash proof: (f)", L4B.wallTests)

-- DashProof.Open on its own: the two windows VitalsService reads.
function L4B.openTests(): ()
	print(" Open: the latest window and the one before it")
	local Proof = L4B.Proof
	local w = { iframesFrom = 0, iframesUntil = 0, iframesWasFrom = 0, iframesWasUntil = 0 }
	Proof.Open(w, 10, 0.25)
	check(w.iframesFrom == 10 and near(w.iframesUntil, 10.25) and w.iframesWasUntil == 0, "a first window opens at its `from`")
	Proof.Open(w, 10.1, 0.5)
	check(w.iframesFrom == 10 and near(w.iframesUntil, 10.6) and w.iframesWasUntil == 0, "one that meets it lengthens it")
	Proof.Open(w, 10.2, 0.1)
	check(near(w.iframesUntil, 10.6), "a shorter one never shortens it")
	Proof.Open(w, 11, 0.25)
	check(w.iframesWasFrom == 10 and near(w.iframesWasUntil, 10.6) and w.iframesFrom == 11 and near(w.iframesUntil, 11.25), "one after it lapsed steps it back")
	-- A grant at 12 (an ability), then a dash requested at 11.9 and proven after: they meet.
	Proof.Open(w, 12, 0.4)
	Proof.Open(w, 11.9, 0.25)
	check(near(w.iframesFrom, 11.9) and near(w.iframesUntil, 12.4) and w.iframesWasFrom == 11, "a dash proven late that meets a later grant joins it, from the request")
	-- A grant at 13.5, then a dash requested at 13.1 proven after it: the dash's window ended first.
	Proof.Open(w, 13.5, 0.4)
	Proof.Open(w, 13.1, 0.25)
	check(near(w.iframesFrom, 13.5) and near(w.iframesUntil, 13.9) and near(w.iframesWasFrom, 13.1) and near(w.iframesWasUntil, 13.35), "one that ended before a later grant began takes the earlier slot")
	Proof.Open(w, 13.0, 0.05)
	check(near(w.iframesWasFrom, 13.1), "and an older, shorter one does not replace it")
end
L4B.group("dash proof: Open", L4B.openTests)

-- (g) Through the real VitalsService: WeaponService's frame as the claim, the proof and Open play
-- it, against tests.luau's fixture (player 7, a fodder lunge of 8, the commit lag 0.1 s).
function L4B.reset(): ()
	Vitals.SetMission(nil)
	Vitals.SetGod(player, false)
	clearIframes()
	root.Position = vec(0, 3, 0)
	advance(1)
	Vitals.PrepareCharacter(player, character)
	drain()
end

-- Frames of 1/60 s for `seconds`: each moves the server's ring along `path` (time from the claim),
-- judges the claim, opens the window from the request when it is proven (copied into the fixture's
-- i-frame clock), then runs VitalsService's frame. `impacts` = times after the claim at which a
-- fodder lunge lands on the player. Returns when the claim was proven, after it (nil = never), and
-- the claim's own time.
function L4B.play(path: (t: number) -> any, impacts: { number }, seconds: number): (number?, number)
	local rule = L4B.rule()
	local history = L4B.Ring.New(120)
	local windows = { iframesFrom = 0, iframesUntil = 0, iframesWasFrom = 0, iframesWasUntil = 0 }
	local claimAt = fakeNow
	local pendingClaim = true
	local provenAt: number? = nil
	local due = table.clone(impacts)
	local frames = math.floor(seconds * 60 + 0.5)
	for _ = 1, frames do
		fakeNow += 1 / 60
		local since = fakeNow - claimAt
		while due[1] ~= nil and due[1] <= since + 1e-9 do
			hooks.impact(lunge(claimAt + table.remove(due, 1)))
		end
		local position = path(since)
		L4B.Ring.Record(history, fakeNow, position)
		if pendingClaim then
			local verdict = L4B.Proof.Verdict(history, fakeNow, position, claimAt, rule)
			if verdict == "proven" then
				pendingClaim = false
				provenAt = fakeNow - claimAt
				L4B.Proof.Open(windows, claimAt, L4B.movement.dashIframes)
				iframes.from = windows.iframesFrom
				iframes.untilClock = windows.iframesUntil
				iframes.wasFrom = windows.iframesWasFrom
				iframes.wasUntil = windows.iframesWasUntil
			elseif verdict == "lapsed" then
				pendingClaim = false
			end
		end
		vitalsBeat(1 / 60)
	end
	return provenAt, claimAt
end

-- The server's copy starts the dash `late` seconds after the claim.
function L4B.dashFrom(late: number): (t: number) -> any
	local speed = L4B.movement.dashDistance / L4B.movement.dashSeconds
	return function(t: number): any
		return vec(math.min(math.max(t - late, 0) * speed, L4B.movement.dashDistance), 3, 0)
	end
end

function L4B.vitalsTests(): ()
	print(" (g) VitalsService: a hit decided after the proof is dodged, one decided before lands")
	local regen = config.player.regenPerSecond
	config.player.regenPerSecond = 0
	L4B.reset()
	local start = humanoid.Health
	-- Claim at 0, motion seen from 0.03, proof by about 0.07; the impact at 0.02 is decided at 0.12.
	local proven = L4B.play(L4B.dashFrom(0.03), { 0.02 }, 0.6)
	local fx = drain()
	check(proven ~= nil and proven < 0.12 and humanoid.Health == start and #fx == 1 and fx[1].dodged == true, `(g) an impact between the claim and the proof, decided after it: dodged (proven at {proven}, health {humanoid.Health})`)

	L4B.reset()
	start = humanoid.Health
	-- Motion seen only from 0.15: the impact at 0 is decided at 0.1, before the proof.
	local claimAt
	proven, claimAt = L4B.play(L4B.dashFrom(0.15), { 0 }, 0.6)
	fx = drain()
	check(proven ~= nil and proven > 0.1 and humanoid.Health == start - 8 and fx[1] ~= nil and fx[1].dodged ~= true, `(g) one decided before the proof lands (proven at {proven}, health {start} -> {humanoid.Health})`)
	check(iframes.from == claimAt and near(iframes.untilClock, claimAt + L4B.movement.dashIframes), "and the proof still opened the dash's whole window, from the request")

	L4B.reset()
	start = humanoid.Health
	-- Proven late (motion from 0.1): the window runs from the request, so an impact at 0.27 (past the
	-- request's 0.25) lands, while one at 0.2 is dodged.
	proven = L4B.play(L4B.dashFrom(0.1), { 0.2, 0.27 }, 0.8)
	fx = drain()
	local dodged = 0
	for _, entry in fx do
		if entry.dodged == true then
			dodged += 1
		end
	end
	check(proven ~= nil and proven > 0.1 and dodged == 1 and humanoid.Health == start - 8, `(g) the window starts at the request, not the proof: an impact at 0.2 dodged, one at 0.27 lands (health {start} -> {humanoid.Health}, {dodged} dodged)`)

	L4B.reset()
	start = humanoid.Health
	-- A forged dash: the request, no motion. Every impact in what used to be its window lands.
	proven = L4B.play(function(_t: number): any
		return vec(0, 3, 0)
	end, { 0, 0.1, 0.2 }, 0.8)
	fx = drain()
	check(proven == nil and humanoid.Health == start - 24 and #fx == 3, `(g) a dash that never moved shields nothing: 3 lunges land (health {start} -> {humanoid.Health})`)

	L4B.reset()
	config.player.regenPerSecond = regen
end
L4B.group("dash proof: (g)", L4B.vitalsTests)

-- (h) The shipped numbers.
function L4B.shippedTests(): ()
	print(" (h) the shipped ProvingGrounds.json")
	local movement = FIXTURES.proving.movement
	local rule = L4B.Proof.Rule(movement, FIXTURES.proving.shooting)
	check(rule ~= nil, "(h) ProvingGrounds.json names a sound dashProofShare and dashProofSeconds")
	if rule == nil then
		return
	end
	local dashSpeed = movement.dashDistance / movement.dashSeconds
	check(rule.speed >= 2 * movement.walkSpeed, `(h) the proof speed ({string.format("%.1f", rule.speed)}) is at least twice walkSpeed ({movement.walkSpeed})`)
	check(rule.speed <= 0.8 * dashSpeed, `(h) and at most 0.8 of a dash's ({string.format("%.1f", dashSpeed)})`)
	check(rule.span < movement.dashSeconds, `(h) its span ({rule.span}) is shorter than the dash itself ({movement.dashSeconds})`)
end
L4B.group("dash proof: (h)", L4B.shippedTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
