-- Cases for L4 W1b's dash proof (docs/prompts/l4-w1b-contract.md §4, L4B-7, and the fix round's F1,
-- docs/prompts/l4-w1b-fix-round.md): a dash's i-frames count only once the server's own ring of
-- positions has seen the dash, and VitalsService holds a hit a pending claim would cover until the
-- claim is proven (voided) or lapses (it lands). DashProof.Step on rings sampled by a 60 Hz
-- Heartbeat from replication at 60 Hz, 20 Hz and 20 Hz bunched, (a) to (f) and the edges; Open and
-- Pending on their own; RunFloors' promise that every floor it returns is new; (g) the real
-- VitalsService, started here a second time with a claim hook, run frame by frame in
-- WeaponService's order (ring sample, Step, VitalsService.Step) over pings, replication, phases and
-- press times, and fix round 2's G1 (docs/prompts/l4-w1b-fix2.md: a held hit keeps the knock rules,
-- and a player's later decisions wait behind it, so a claim that never proves costs what no claim
-- costs); (h) the shipped ProvingGrounds.json. Appended by run_harness.py after tests.luau, so
-- its locals are in scope (check, near, load, vec, config, FIXTURES, fakeNow, fired,
-- player, beats, walls, blocks, threatHooks, hooks, Crowd, SOURCES, gameStub, token, requireStub, V,
-- osStub).
-- Everything hangs off the L4B table (the bundle's 200-local limit) and every group runs behind
-- L4B.group, so a throw is one failing check. WeaponService (OnDash's claim, trackAir's call, the
-- one Heartbeat) cannot be loaded here: run_harness.py reads those lines as text.

print("L4 W1b: the dash proof (DashProof, L4B-7, F1)")

local L4B: any = {
	Proof = load("DashProof"),
	Ring = load("PositionRing"),
	Floors = load("RunFloors"),
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
	-- A course's clock starts here; Heartbeat frames are whole multiples of 1/60 from it.
	BASE = 100,
	HZ = 60,
	-- Replication as the server receives a client's root: per update, or two updates in one frame.
	MODES = {
		{ hz = 60, bunched = false, label = "60 Hz" },
		{ hz = 20, bunched = false, label = "20 Hz" },
		{ hz = 20, bunched = true, label = "20 Hz bunched" },
	},
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

function L4B.claimant(claimAt: number?): any
	return { dashClaimAt = claimAt, iframesFrom = 0, iframesUntil = 0, iframesWasFrom = 0, iframesWasUntil = 0 }
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

-- The newest replication update the server holds at server time `t`: updates are sent at `hz` from
-- `sendFrom` and arrive `u` later; `bunched`: every odd one waits for the next and arrives with it.
-- Returns when that update was sent (on the client's true path).
function L4B.sentAt(t: number, hz: number, bunched: boolean?, u: number, sendFrom: number): number
	local newest = math.floor((t - u - sendFrom) * hz + 1e-9)
	if bunched and newest % 2 == 1 then
		newest -= 1
	end
	return sendFrom + newest / hz
end

-- The server's Heartbeat samples of a true path over `seconds` from BASE: one per 1/60 s, each the
-- root as the newest replication update had it (sent at `hz`, `phase` into its cycle, no network
-- delay). `bunched`: two updates arrive in one frame, so the copy moves every other update period.
function L4B.samples(path: (t: number) -> any, hz: number, seconds: number, bunched: boolean?, phase: number?): { any }
	local out = {}
	local frames = math.floor(seconds * L4B.HZ + 0.5)
	local sendFrom = L4B.BASE - 1 + (phase or 0)
	for k = 0, frames do
		local t = L4B.BASE + k / L4B.HZ
		table.insert(out, { t = t, position = path(L4B.sentAt(t, hz, bunched, 0, sendFrom)) })
	end
	return out
end

-- WeaponService's trackAir on those samples, through the real DashProof.Step: each frame records
-- its sample; the claim is made on the first frame at or after `claimAt` and stepped from then on
-- until it is over. Returns the verdict, the frame it came on (nil = still pending), and the
-- claimant (its i-frame windows).
function L4B.judge(samples: { any }, claimAt: number, rule: any): (string, number?, any)
	local history = L4B.Ring.New(120)
	local claimant = L4B.claimant(nil)
	local made = false
	for _, sample in samples do
		L4B.Ring.Record(history, sample.t, sample.position)
		if not made and sample.t >= claimAt - 1e-9 then
			made = true
			claimant.dashClaimAt = claimAt
		end
		if claimant.dashClaimAt ~= nil then
			local verdict = L4B.Proof.Step(claimant, history, sample.t, sample.position, rule, L4B.movement.dashIframes)
			if verdict ~= "pending" then
				return verdict, sample.t, claimant
			end
		end
	end
	return "pending", nil, claimant
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
	check(L4B.Proof.Rule(L4B.movement, { originLagMaxSeconds = -1 }) == nil, "a negative lookback is none (it would end the window before the claim)")
end
L4B.group("dash proof: Rule", L4B.ruleTests)

-- The edges of Verdict, on numbers a binary clock holds exactly: a proof of 64 studs/s (0.5 x 16 /
-- 0.125) over 1/16 s, a lookback of 1/4 and a lapse of 3/8, frames of 1/64 s from 64.
function L4B.edgeTests(): ()
	print(" Verdict's edges: exactly the proof speed, and a proof on the frame the claim lapses")
	local Proof = L4B.Proof
	local rule = Proof.Rule({ dashDistance = 16, dashSeconds = 0.125, dashProofShare = 0.5, dashProofSeconds = 0.0625 }, { originLagMaxSeconds = 0.25 })
	check(rule ~= nil and rule.speed == 64 and rule.span == 0.0625 and rule.lapse == 0.375, "the exact rule: 64 studs/s over 1/16 s, lapse 3/8")
	local function ring(points: { any }): any
		local history = L4B.Ring.New(64)
		for _, point in points do
			L4B.Ring.Record(history, point[1], point[2])
		end
		return history
	end
	local at = ring({ { 64, vec(0, 3, 0) }, { 64.0625, vec(4, 3, 0) } })
	check(Proof.Verdict(at, 64.0625, vec(4, 3, 0), 64.0625, rule) == "proven", "4 studs in 1/16 s is exactly 64 studs/s: proven (the line is reached, not passed)")
	local under = 4 - 2 ^ -20
	local below = ring({ { 64, vec(0, 3, 0) }, { 64.0625, vec(under, 3, 0) } })
	check(Proof.Verdict(below, 64.0625, vec(under, 3, 0), 64.0625, rule) == "pending", "a hair under it: pending")

	-- Still until the lapse, then a stall's catch-up lands 10 studs on the very frame the claim
	-- would lapse (64 + 25/64 is the first frame past 64 + 3/8).
	local history = L4B.Ring.New(64)
	local claimant = L4B.claimant(64)
	local last, lastAt = nil, nil
	for k = 0, 25 do
		local t = 64 + k / 64
		local position = if k < 25 then vec(0, 3, 0) else vec(10, 3, 0)
		L4B.Ring.Record(history, t, position)
		last, lastAt = Proof.Step(claimant, history, t, position, rule, 0.25), t
		if last ~= "pending" then
			break
		end
	end
	check(last == "proven" and lastAt == 64 + 25 / 64, `a claim first proven on the frame it lapses is proven ("a proof wins over a lapse"): {last} at {lastAt}`)
	check(claimant.dashClaimAt == nil and claimant.iframesFrom == 64 and claimant.iframesUntil == 64.25, "and its window opens from the request")
end
L4B.group("dash proof: edges", L4B.edgeTests)

-- DashProof.Step: what a frame does to the claimant.
function L4B.stepTests(): ()
	print(" Step: one frame of a pending claim")
	local Proof = L4B.Proof
	local rule = L4B.rule()
	local history = L4B.Ring.New(8)
	L4B.Ring.Record(history, 10, vec(0, 3, 0))
	local idle = L4B.claimant(nil)
	check(Proof.Step(idle, history, 10, vec(0, 3, 0), rule, 0.25) == nil and idle.iframesUntil == 0, "no claim: nothing (nil), nothing opens")
	local pending = L4B.claimant(10)
	check(Proof.Step(pending, history, 10, vec(0, 3, 0), rule, 0.25) == "pending" and pending.dashClaimAt == 10 and pending.iframesUntil == 0, "pending: the claim stays, nothing opens")
	local lapsed = L4B.claimant(10)
	check(Proof.Step(lapsed, history, 10.46, vec(0, 3, 0), rule, 0.25) == "lapsed" and lapsed.dashClaimAt == nil and lapsed.iframesUntil == 0 and lapsed.iframesWasUntil == 0, "lapsed: the claim is over and no window opens")
	L4B.Ring.Record(history, 10.05, vec(10, 3, 0))
	local proven = L4B.claimant(10)
	check(Proof.Step(proven, history, 10.05, vec(10, 3, 0), rule, 0.25) == "proven" and proven.dashClaimAt == nil and proven.iframesFrom == 10 and near(proven.iframesUntil, 10.25), "proven: the claim is over and the window opens from the request, for dashIframes")
	local noRule = L4B.claimant(10)
	check(Proof.Step(noRule, history, 10.05, vec(10, 3, 0), nil, 0.25) == "lapsed" and noRule.dashClaimAt == nil and noRule.iframesUntil == 0, "no rule: the claim is over unproven, whatever moved")

	local from, untilClock, lapseAt = Proof.Pending(10, rule, 0.25)
	check(from == 10 and near(untilClock, 10.25) and near(lapseAt, 10.45), "Pending: the window a proof would open, and the claim's lapse")
	local a, b, c = Proof.Pending(nil, rule, 0.25)
	local d, e, f = Proof.Pending(10, nil, 0.25)
	check(a == 0 and b == 0 and c == 0 and d == 0 and e == 0 and f == 0, "Pending: 0, 0, 0 with no claim or no rule (nothing to wait for)")
end
L4B.group("dash proof: Step", L4B.stepTests)

-- (a) A real dash: proven within one replication update of the copy's first move.
function L4B.realDashTests(): ()
	print(" (a) a real dash is proven within one update period (+ a frame) of the first moving sample")
	local rule = L4B.rule()
	for _, mode in L4B.MODES do
		local period = (if mode.bunched then 2 else 1) / mode.hz
		local worst = 0
		local ok = true
		-- The motion's start swept over one whole update cycle, in 24 steps.
		for step = 0, 23 do
			local lead = period * step / 24
			local claimAt = L4B.BASE + 0.1
			local samples = L4B.samples(L4B.dash(claimAt + lead), mode.hz, 1, mode.bunched)
			local verdict, at = L4B.judge(samples, claimAt, rule)
			local moving = L4B.firstMoving(samples)
			if verdict ~= "proven" or at == nil or moving == nil then
				ok = false
			else
				worst = math.max(worst, at - moving)
			end
		end
		check(ok and worst <= period + 1 / L4B.HZ + 1e-9, `(a) {mode.label}: proven at worst {string.format("%.3f", worst)} s after the first moving sample (bound {string.format("%.3f", period + 1 / L4B.HZ)})`)
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
		local verdict, at, claimant = L4B.judge(samples, claimAt, rule)
		check(verdict == "lapsed" and at ~= nil and at >= claimAt + 0.45 - 1e-9 and at <= claimAt + 0.45 + 1 / 60 + 1e-9 and claimant.iframesUntil == 0, `(b) a claim {offset} s in: lapsed at {if at ~= nil then string.format("%.3f", at - claimAt) else "never"} s, the first frame past 0.45, nothing opened`)
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
	for _, mode in L4B.MODES do
		local verdict = L4B.judge(L4B.samples(walk, mode.hz, 2, mode.bunched), L4B.BASE + 0.5, rule)
		check(verdict == "lapsed", `(c) walking at 20 studs/s, {mode.label}: {verdict}`)
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
	for _, mode in L4B.MODES do
		local verdict = L4B.judge(L4B.samples(L4B.dash(claimAt, 2), mode.hz, 2, mode.bunched), claimAt, rule)
		check(verdict == "lapsed", `(f) 2 studs then a wall, {mode.label}: {verdict}`)
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

-- RunFloors' own promise (its header): every list it returns is new and so is every floor in it,
-- while a floor's cells list is the one it was given (shared, never copied or cleared).
function L4B.floorsTests(): ()
	print(" RunFloors: every floor returned is new, its cells shared")
	local Floors = L4B.Floors
	local cells = { { x = 1, z = 2, hx = 3, hz = 4 } }
	local run = {
		{ x = 0, y = 8, z = 0, hx = 10, hz = 10, locks = false, cells = cells },
		{ x = 40, y = 0, z = 0, hx = 6, hz = 6, locks = true },
	}
	local first, went = Floors.Attach(run, 3, nil)
	check(went and first ~= run and first[1] ~= run[1] and first[2] ~= run[2] and first[1].cells == cells, "Attach with cells: a new list of new floors, the cells list the run's own")
	local steady = Floors.Attach(run, 3, 3)
	check(steady[1] ~= run[1] and steady[1].cells == nil and run[1].cells == cells and steady[1].hx == 10, "Attach without cells: a new floor without them, and the run's own floor keeps its cells")
	local held = Floors.Merge({}, nil, first, 3)
	local merged = Floors.Merge(held, 3, steady, 3)
	check(merged[1] ~= steady[1] and merged[1] ~= held[1] and merged[1].cells == cells and steady[1].cells == nil, "Merge: a new floor that takes the held cells, the incoming floor untouched")
	check(held[1] ~= first[1] and held[2] ~= first[2], "Merge on a new seq: every floor new as well")
end
L4B.group("RunFloors: new floors", L4B.floorsTests)

-- (g) The real VitalsService (a second instance of tests.luau's module, with its own claim hook),
-- run frame by frame as WeaponService's Heartbeat runs it: the ring sample, DashProof.Step on a
-- pending claim, then VitalsService.Step. Its player (userId 41) is not tests.luau's; its effects
-- reach tests.luau's player 7 like every batch, and are read there.
L4B.ID = 41
L4B.shippedMove = FIXTURES.proving.movement
L4B.shippedRule = L4B.Proof.Rule(FIXTURES.proving.movement, FIXTURES.proving.shooting)

function L4B.body(): ()
	L4B.root = {
		Position = vec(0, 3, 0),
		Size = vec(2, 2, 1),
		IsA = function(_self, class)
			return class == "BasePart"
		end,
	}
	L4B.humanoid = { Health = 100, MaxHealth = 100, HipHeight = 2 }
	L4B.character = {
		Parent = {},
		FindFirstChild = function(_self, name)
			return if name == "HumanoidRootPart" then L4B.root else nil
		end,
		FindFirstChildOfClass = function(_self, class)
			return if class == "Humanoid" then L4B.humanoid else nil
		end,
		GetChildren = function()
			return {}
		end,
		ChildAdded = {
			Connect = function(_self, _fn)
				return { Disconnect = function() end }
			end,
		},
	}
	L4B.player = {
		UserId = L4B.ID,
		Character = L4B.character,
		Parent = {},
		GetNetworkPing = function()
			return L4B.ping
		end,
	}
end

-- The claim hook as WeaponService's pendingDash answers it, on this file's claimant.
function L4B.pendingDash(who: any): (number, number, number)
	if who ~= L4B.player then
		return 0, 0, 0
	end
	return L4B.Proof.Pending(L4B.claim.dashClaimAt, L4B.shippedRule, L4B.shippedMove.dashIframes)
end

function L4B.startVitals(): ()
	L4B.body()
	L4B.ping = 0
	L4B.claim = L4B.claimant(nil)
	L4B.history = L4B.Ring.New(120)
	L4B.dashClaim = L4B.pendingDash
	local connected = #beats
	L4B.vitals = SOURCES.VitalsService(gameStub, token("script"), requireStub, V, osStub, {
		spawn = function(fn, ...)
			fn(...)
		end,
	}, print, {
		new = function()
			return {}
		end,
	}, { RaycastFilterType = { Exclude = 1 } })
	L4B.vitals.Start({
		iframeWindow = function(who)
			if who ~= L4B.player then
				return 0, 0, 0, 0
			end
			local w = L4B.claim
			return w.iframesFrom, w.iframesUntil, w.iframesWasFrom, w.iframesWasUntil
		end,
		-- WeaponService.GrantIframes: a window from now, or from `from` when that is earlier (G1).
		grantIframes = function(who, seconds, from)
			if who == L4B.player and seconds > 0 then
				L4B.Proof.Open(L4B.claim, math.min(from or fakeNow, fakeNow), seconds)
			end
		end,
		dashClaim = function(who)
			return L4B.dashClaim(who)
		end,
	})
	check(#beats == connected, "F1: VitalsService connects no Heartbeat of its own (WeaponService's runs VitalsService.Step after the proofs)")
	L4B.threat = threatHooks
	L4B.vitals.AddPlayer(L4B.player)
	L4B.regen = config.player.regenPerSecond
	config.player.regenPerSecond = 0
end

-- A fresh run: full health, no claim, no window, an empty ring and queue, a clock on whole seconds.
function L4B.fresh(ping: number): ()
	L4B.ping = ping
	fakeNow = math.floor(fakeNow) + 5
	L4B.vitals.ClearThreats()
	L4B.claim = L4B.claimant(nil)
	L4B.history = L4B.Ring.New(120)
	L4B.dashClaim = L4B.pendingDash
	L4B.root.Position = vec(0, 3, 0)
	L4B.vitals.PrepareCharacter(L4B.player, L4B.character)
	L4B.vitals.Step(1 / 60)
	table.clear(fired)
end

-- The hurt effects for player 41 sent since the last read (and every shot's end, into L4B.ends).
function L4B.hurts(): { any }
	local out = {}
	for _, call in fired do
		if call.player == player and call.name == "CombatFx" then
			for _, fx in call.payload do
				if fx.kind == "hurt" and fx.userId == L4B.ID then
					table.insert(out, fx)
				elseif fx.kind == "enemyShotEnd" and L4B.ends ~= nil then
					table.insert(L4B.ends, fx)
				end
			end
		end
	end
	table.clear(fired)
	return out
end

-- One Heartbeat in WeaponService's order, the server's copy of the root at `position`.
function L4B.frame(position: any): { any }
	L4B.root.Position = position
	L4B.Ring.Record(L4B.history, fakeNow, position)
	if L4B.claim.dashClaimAt ~= nil then
		L4B.Proof.Step(L4B.claim, L4B.history, fakeNow, position, L4B.shippedRule, L4B.shippedMove.dashIframes)
	end
	L4B.vitals.Step(1 / L4B.HZ)
	return L4B.hurts()
end

-- An enemy hit no move escapes: the shape holds the root wherever the dash takes it, so only
-- i-frames decide it. `knockback` > 0 knocks.
function L4B.strike(at: number, knockback: number?, bodyId: number?): any
	return {
		at = at,
		enemyKind = "fodder",
		attack = 1,
		def = { shape = "arc", range = 1000, arcDegrees = 360, damage = 8, knockback = knockback },
		targetUserId = L4B.ID,
		origin = vec(-30, 3, 0),
		floorY = 0,
		facing = vec(1, 0, 0),
		bodyId = bodyId or 1,
	}
end

-- Did the window [from, untilClock) meet [impact, limit]? (VitalsService's own test.)
function L4B.met(from: number, untilClock: number, impact: number, limit: number): boolean
	return untilClock > math.max(from, impact) and from <= limit
end

-- One course of the timing study, in server time. The impact is at T (a Heartbeat), decided at
-- T + lag (lag = ping + originLagSeconds, capped). The client presses dash at T + d: the remote
-- and its root's motion both arrive ping / 2 later, the motion through `mode`'s replication,
-- `phase` into its cycle; the claim is made on the first Heartbeat after the remote arrives.
-- `kind`: "dash" (20 studs), "still" (a forged dash), "wall" (2 studs, then a wall). Returns
-- whether the hit was dodged, the frame its effect left on, the claim's time, the impact's and the
-- decision's.
function L4B.course(kind: string, mode: any, ping: number, phase: number, d: number): (boolean?, number?, number?, number, number)
	L4B.fresh(ping)
	local F = fakeNow
	local u = ping / 2
	local T = F + 1
	local pressAt = T + d
	local speed = L4B.shippedMove.dashDistance / L4B.shippedMove.dashSeconds
	local reach = if kind == "dash" then L4B.shippedMove.dashDistance elseif kind == "wall" then 2 else 0
	local sendFrom = F - 1 + phase
	local lag = math.min(ping + config.shooting.originLagSeconds, config.shooting.originLagMaxSeconds)
	local claimAt: number? = nil
	local first = L4B.HZ + math.floor((math.min(d, 0) - 0.15) * L4B.HZ)
	for k = first, L4B.HZ * 3 do
		fakeNow = F + k / L4B.HZ
		if k == L4B.HZ then
			L4B.threat.impact(L4B.strike(fakeNow))
		end
		if claimAt == nil and fakeNow >= pressAt + u - 1e-9 then
			claimAt = fakeNow
			L4B.claim.dashClaimAt = fakeNow
		end
		local sent = L4B.sentAt(fakeNow, mode.hz, mode.bunched, u, sendFrom)
		local x = math.min(math.max(sent - pressAt, 0) * speed, reach)
		local out = L4B.frame(vec(x, 3, 0))
		if #out > 0 then
			return out[1].dodged == true, fakeNow, claimAt, T, T + lag
		end
	end
	return nil, nil, claimAt, T, T + lag
end

-- The study for one kind of dash. One check per replication mode and ping, over every phase and
-- press time. "dash": dodged exactly when the request's own window met the hit's span, as before
-- W1b (the window opened at the request then), and every press at or before the impact whose
-- window still runs at it dodges; a held hit waits no longer than the claim's lapse. "still" and
-- "wall": never dodged, and a hit the claim would have covered lands on the frame it lapses.
function L4B.study(kind: string, step: number, phases: number): ()
	local I = L4B.shippedMove.dashIframes
	local lapse = L4B.shippedRule.lapse
	for _, mode in L4B.MODES do
		local cycle = (if mode.bunched then 2 else 1) / mode.hz
		for _, ping in { 0, 0.1 } do
			local runs, dodges, holds, wrong = 0, 0, 0, nil
			for q = 0, phases - 1 do
				local phase = cycle * q / phases
				local d = -0.3
				while d <= 0.25 + 1e-9 do
					local dodged, at, claimAt, impact, decideAt = L4B.course(kind, mode, ping, phase, d)
					runs += 1
					-- Before W1b the window opened at the request: did it meet the hit's span?
					local before = claimAt ~= nil and L4B.met(claimAt, claimAt + I, impact, decideAt)
					local problem: string? = nil
					if dodged == nil or at == nil then
						problem = "no effect"
					elseif kind == "dash" then
						if dodged ~= before then
							problem = `dodged {dodged}, before W1b {before}`
						elseif d <= 1e-9 and claimAt ~= nil and claimAt + I > impact and not dodged then
							problem = "pressed at or before the impact, window open at it, not dodged"
						elseif at > decideAt + 1 / L4B.HZ + 1e-9 and (claimAt == nil or at > claimAt + lapse + 1 / L4B.HZ + 1e-9) then
							problem = "held past the claim's lapse"
						end
					else
						if dodged then
							problem = "dodged"
						elseif before and claimAt ~= nil and not (at > claimAt + lapse - 1e-9 and at <= claimAt + lapse + 1 / L4B.HZ + 1e-9) then
							problem = `held, but landed {string.format("%.3f", at - claimAt)} s after the claim, not on the frame it lapsed`
						elseif not before and not (at >= decideAt - 1e-9 and at < decideAt + 1 / L4B.HZ + 1e-9) then
							problem = `not held, but landed {string.format("%.3f", at - decideAt)} s after its decision`
						end
					end
					if dodged then
						dodges += 1
					end
					if at ~= nil and at > decideAt + 1 / L4B.HZ + 1e-9 then
						holds += 1
					end
					if problem ~= nil and wrong == nil then
						wrong = `phase {string.format("%.4f", phase)}, press {string.format("%+.3f", d)}: {problem}`
					end
					d += step
				end
			end
			local label = `(g) {kind}, {mode.label}, ping {ping}`
			if kind == "dash" then
				check(wrong == nil and dodges > 0 and dodges < runs and holds > 0, `{label}: dodged exactly as before W1b, every press at or before the impact among them ({dodges} of {runs} courses dodged, {holds} held for the proof){if wrong ~= nil then "; first wrong: " .. wrong else ""}`)
			else
				check(wrong == nil and dodges == 0 and holds > 0, `{label}: never dodged, a hit it would have covered lands as it lapses ({runs} courses, {holds} held){if wrong ~= nil then "; first wrong: " .. wrong else ""}`)
			end
		end
	end
end

function L4B.studyTests(): ()
	print(" (g) the timing study: the real VitalsService and DashProof.Step, in WeaponService's order")
	L4B.study("dash", 0.005, 4)
	L4B.study("still", 0.01, 3)
	L4B.study("wall", 0.01, 3)
end

-- Frames of 1/60 s from now on a path of time since `from` (nil = still at the origin); `impacts`
-- = strikes raised at their own `at` (times since `from`). Returns every hurt with its frame.
function L4B.play(path: ((t: number) -> any)?, impacts: { any }, seconds: number, from: number, onFrame: ((since: number) -> ())?): { any }
	local out = {}
	local due = table.clone(impacts)
	local frames = math.floor(seconds * L4B.HZ + 0.5)
	for _ = 1, frames do
		fakeNow += 1 / L4B.HZ
		local since = fakeNow - from
		while due[1] ~= nil and due[1].at <= since + 1e-9 do
			local raise = table.remove(due, 1)
			L4B.threat.impact(L4B.strike(from + raise.at, raise.knockback, raise.bodyId))
		end
		if onFrame ~= nil then
			onFrame(since)
		end
		for _, fx in L4B.frame(if path ~= nil then path(since) else vec(0, 3, 0)) do
			table.insert(out, { fx = fx, at = since })
		end
	end
	return out
end

-- The server's copy starts the dash `late` seconds after the claim.
function L4B.dashFrom(late: number): (t: number) -> any
	local speed = L4B.shippedMove.dashDistance / L4B.shippedMove.dashSeconds
	return function(t: number): any
		return vec(math.min(math.max(t - late, 0) * speed, L4B.shippedMove.dashDistance), 3, 0)
	end
end

function L4B.claimNow(): number
	L4B.claim.dashClaimAt = fakeNow
	return fakeNow
end

function L4B.casesTests(): ()
	print(" (g) the hold, case by case (ping 0.05: the commit lag 0.1 s)")
	local lapse = L4B.shippedRule.lapse
	L4B.fresh(0.05)
	local start = L4B.humanoid.Health
	-- Claim at 0, motion seen from 0.15, proof by about 0.18; the impact at 0 is decided at 0.1,
	-- before the proof: held, and dodged once the proof comes, on that frame.
	local claimAt = L4B.claimNow()
	local out = L4B.play(L4B.dashFrom(0.15), { { at = 0 } }, 0.6, claimAt)
	check(#out == 1 and out[1].fx.dodged == true and out[1].at > 0.1 + 1 / 60 and out[1].at < 0.25 and L4B.humanoid.Health == start, `an impact decided before the proof is held and dodged when the proof comes ({#out} effect, at {if out[1] then string.format("%.3f", out[1].at) else "-"} s, health {start} -> {L4B.humanoid.Health})`)
	check(L4B.claim.iframesFrom == claimAt and near(L4B.claim.iframesUntil, claimAt + L4B.shippedMove.dashIframes), "and the proof opened the dash's whole window, from the request")

	L4B.fresh(0.05)
	start = L4B.humanoid.Health
	-- Proven late (motion from 0.1): the window runs from the request, so an impact at 0.27 (past the
	-- request's 0.25) lands, while one at 0.2 is dodged.
	claimAt = L4B.claimNow()
	out = L4B.play(L4B.dashFrom(0.1), { { at = 0.2 }, { at = 0.27 } }, 0.8, claimAt)
	check(#out == 2 and out[1].fx.dodged == true and out[2].fx.dodged ~= true and L4B.humanoid.Health == start - 8, `the window starts at the request, not the proof: an impact at 0.2 dodged, one at 0.27 lands (health {start} -> {L4B.humanoid.Health})`)

	L4B.fresh(0.05)
	start = L4B.humanoid.Health
	-- A forged dash: the request, no motion. Every impact in what would have been its window waits
	-- for the claim, and lands on the frame it lapses.
	claimAt = L4B.claimNow()
	out = L4B.play(nil, { { at = 0 }, { at = 0.1 }, { at = 0.2 } }, 0.8, claimAt)
	local together = #out == 3
	for _, entry in out do
		together = together and entry.fx.dodged ~= true and entry.at > lapse - 1e-9 and entry.at <= lapse + 1 / 60 + 1e-9
	end
	check(together and L4B.humanoid.Health == start - 24, `a dash that never moved shields nothing: 3 hits held, all landing as the claim lapses (health {start} -> {L4B.humanoid.Health})`)

	L4B.fresh(0.05)
	start = L4B.humanoid.Health
	-- The hold never outlasts the lapse, even were the claim never resolved: a hook that reports
	-- the claim pending forever (no Step runs).
	claimAt = fakeNow
	L4B.dashClaim = function(who: any): (number, number, number)
		if who ~= L4B.player then
			return 0, 0, 0
		end
		return claimAt, claimAt + L4B.shippedMove.dashIframes, claimAt + lapse
	end
	out = L4B.play(nil, { { at = 0 } }, 0.8, claimAt)
	check(#out == 1 and out[1].fx.dodged ~= true and out[1].at > lapse - 1e-9 and out[1].at <= lapse + 1 / 60 + 1e-9, `a hold ends at the claim's lapse at the latest, whatever the hook says after it (landed at {if out[1] then string.format("%.3f", out[1].at) else "never"} s)`)
	L4B.dashClaim = L4B.pendingDash

	L4B.fresh(0.05)
	start = L4B.humanoid.Health
	-- G1: a forged claim, a hit held for it, then a knocking hit its window would not have covered
	-- (an impact 0.27 after the claim) falls due while the first waits. It waits behind it, and both
	-- are released on the frame the claim lapses in the order they fell due, the held hit first:
	-- the knock came after it, so both land, as with no claim.
	claimAt = L4B.claimNow()
	out = L4B.play(nil, { { at = 0.05 }, { at = 0.27, knockback = 10 } }, 0.8, claimAt)
	local inTurn = #out == 2 and out[1].fx.push == nil and out[2].fx.push ~= nil
	for _, entry in out do
		inTurn = inTurn and entry.fx.dodged ~= true and entry.at > lapse - 1e-9 and entry.at <= lapse + 1 / 60 + 1e-9
	end
	check(inTurn and L4B.humanoid.Health == start - 16, `G1: a knock due while a hit is held waits behind it: both land as the claim lapses, the held hit first (health {start} -> {L4B.humanoid.Health})`)

	L4B.fresh(0.05)
	start = L4B.humanoid.Health
	-- A forged claim, a hit held for it, then the boss that struck dies: the held hit still lands.
	claimAt = L4B.claimNow()
	out = L4B.play(nil, { { at = 0, bodyId = 77 } }, 0.8, claimAt, function(since: number)
		if math.abs(since - 0.2) < 0.5 / 60 then
			L4B.threat.gone({ [77] = true })
		end
	end)
	check(#out == 1 and out[1].fx.dodged ~= true and L4B.humanoid.Health == start - 8, `a held hit outlives its striker's death: it lands at the lapse ({#out} effect)`)

	L4B.fresh(0.05)
	-- A knocking hit held for a forged claim, the root walking aside (+Z at walkSpeed, which never
	-- proves a claim) meanwhile: it lands as it was decided, pushed away from the origin (x -30)
	-- from where the root was at the decision (0.1 s: z 2, push Z 0.67 of 10), not from where it
	-- walked to by the lapse (z 8, push Z 2.6).
	claimAt = L4B.claimNow()
	out = L4B.play(function(since: number): any
		return vec(0, 3, math.min(since, 0.4) * L4B.shippedMove.walkSpeed)
	end, { { at = 0, knockback = 10 } }, 0.8, claimAt)
	local push = if out[1] ~= nil then out[1].fx.push else nil
	check(#out == 1 and out[1].fx.dodged ~= true and push ~= nil and push.Z > 0.5 and push.Z < 1, `a held hit is pushed from the root it was decided on, not the one it lands on (push {if push then string.format("%.2f, %.2f", push.X, push.Z) else "none"})`)

	L4B.fresh(0.05)
	-- A forged claim, a hit held for it, then a respawn: the new body is not hit by it.
	claimAt = L4B.claimNow()
	local body = L4B.humanoid
	local fresh = { Health = 130, MaxHealth = 130, HipHeight = 2 }
	out = L4B.play(nil, { { at = 0 } }, 0.8, claimAt, function(since: number)
		if math.abs(since - 0.2) < 0.5 / 60 then
			L4B.humanoid = fresh
		end
	end)
	check(#out == 0 and fresh.Health == 130, `a hit held for the last body is dropped with it ({#out} effects, the new body at {fresh.Health})`)
	L4B.humanoid = body
end

-- A ring or a shot (ThreatField, judged at the crowd step) reaches the player while a claim is
-- pending: ThreatField is answered "dodged" (done with them), and the queue decides it once the
-- claim resolves. Crowd steps every fourth frame (15 Hz); the attack leaves 10 studs from the root
-- at 40 studs/s, its edge (half width or radius 1) reaches it 0.225 s later, and the step at
-- 0.333 s judges that (lag 0.1). `aim` = where it was aimed (default the root). The root the
-- attack reads stays put; the claim's ring of positions is fed `seen` (nil = still).
function L4B.travel(claim: boolean, seen: ((since: number) -> any)?, shape: string?, aim: any?, before: ((from: number) -> ())?): ({ any }, number?)
	L4B.fresh(0.05)
	local from = fakeNow
	if before ~= nil then
		before(from)
	end
	if claim then
		L4B.claimNow()
	end
	local strike = L4B.strike(from)
	strike.def = if shape == "shot"
		then { shape = "shot", speed = 40, seconds = 1, radius = 1, damage = 8 }
		else { shape = "ring", speed = 40, radius = 30, width = 2, damage = 8, height = 5 }
	strike.origin = vec(0, 3, 10)
	strike.aim = aim or vec(0, 3, 0)
	strike.facing = vec(0, 0, -1)
	L4B.ends = {}
	L4B.threat.impact(strike)
	local out = {}
	local provenAt: number? = nil
	for k = 1, 60 do
		fakeNow = from + k / L4B.HZ
		local since = fakeNow - from
		if k % 4 == 0 then
			L4B.threat.step(fakeNow)
		end
		local position = if seen ~= nil then seen(since) else vec(0, 3, 0)
		L4B.Ring.Record(L4B.history, fakeNow, position)
		if L4B.claim.dashClaimAt ~= nil then
			local verdict = L4B.Proof.Step(L4B.claim, L4B.history, fakeNow, position, L4B.shippedRule, L4B.shippedMove.dashIframes)
			if verdict == "proven" then
				provenAt = since
			end
		end
		L4B.vitals.Step(1 / L4B.HZ)
		for _, fx in L4B.hurts() do
			table.insert(out, { fx = fx, at = since })
		end
	end
	return out, provenAt
end

function L4B.travelTests(): ()
	print(" (g) a travelling attack held for a claim")
	local lapse = L4B.shippedRule.lapse
	local out = L4B.travel(false, nil)
	check(#out == 1 and out[1].fx.dodged ~= true and near(out[1].at, 20 / 60, 1e-6), `no claim: the ring lands at the crowd step that finds it (at {if out[1] then string.format("%.3f", out[1].at) else "-"} s)`)
	out = L4B.travel(true, nil)
	check(#out == 1 and out[1].fx.dodged ~= true and out[1].at > lapse - 1e-9 and out[1].at <= lapse + 1 / 60 + 1e-9, `a forged claim: held, and it lands once, as the claim lapses (at {if out[1] then string.format("%.3f", out[1].at) else "-"} s)`)
	-- An honest claim whose dash the ring of positions sees only from 0.34 s, after that step.
	local provenAt
	out, provenAt = L4B.travel(true, L4B.dashFrom(0.34))
	check(#out == 1 and out[1].fx.dodged == true and provenAt ~= nil and provenAt > 20 / 60 and near(out[1].at, provenAt), `an honest claim proven after the step that found them: held, then dodged on the proof's frame (proven at {if provenAt then string.format("%.3f", provenAt) else "never"} s)`)
	-- Aimed 4 studs short of them (where they stood at the windup): the step at 0.267 s asks
	-- whether passing that point was a dodge, before the front reaches them. Answered at once
	-- (no, silently), so the ring stays live: at 0.333 s it reaches them, is held, and lands.
	out = L4B.travel(true, nil, "ring", vec(0, 3, 4))
	check(#out == 1 and out[1].fx.dodged ~= true and out[1].at > lapse - 1e-9 and out[1].at <= lapse + 1 / 60 + 1e-9, `an aimed miss is never held: the ring stays live, reaches them, and lands as the claim lapses ({#out} effect)`)
	-- A window that ended after the ring left (0.05 s) but before it reached them (0.225 s): the
	-- held hit is judged at its own impact, so that window covers nothing and the hit lands.
	out = L4B.travel(true, nil, "ring", nil, function(from: number)
		L4B.Proof.Open(L4B.claim, from - 0.2, 0.25)
	end)
	check(#out == 1 and out[1].fx.dodged ~= true and out[1].at > lapse - 1e-9, `a held travelling hit is judged at its impact, not when it left: an earlier window that ended between the two covers nothing ({#out} effect, dodged {if out[1] then tostring(out[1].fx.dodged == true) else "-"})`)
	-- Ruling 18 for an attack that travels: a knock's window voids what is decided inside it, even
	-- a contact whose own span ended before the knock (so the knock's i-frames cannot cover it). A
	-- ring leaves 3 studs off: its contact (0.05 s) is judged at the step of 0.2 s, span [0.05,
	-- 0.15]; a knocking hit lands at 0.183 s, between the two.
	L4B.fresh(0.05)
	local from = fakeNow
	local near3 = L4B.strike(from)
	near3.def = { shape = "ring", speed = 40, radius = 30, width = 2, damage = 8, height = 5 }
	near3.origin = vec(0, 3, 3)
	near3.aim = vec(0, 3, 0)
	L4B.threat.impact(near3)
	out = {}
	for k = 1, 30 do
		fakeNow = from + k / L4B.HZ
		if k == 4 then
			L4B.threat.impact(L4B.strike(from + 0.07, 10))
		end
		if k % 4 == 0 then
			L4B.threat.step(fakeNow)
		end
		for _, fx in L4B.frame(vec(0, 3, 0)) do
			table.insert(out, { fx = fx, at = fakeNow - from })
		end
	end
	check(#out == 2 and out[1].fx.dodged ~= true and out[2].fx.dodged == true and near(out[2].at, 0.2, 1e-6), `a knock's window voids a travelling hit decided inside it ({#out} effects, the ring's dodged {if out[2] then tostring(out[2].fx.dodged == true) else "-"})`)
	-- A shot held for a forged claim flies on, as past a dodge: it is not ended on them, and the hit
	-- still lands from the queue.
	local walls0, blocks0 = table.clone(walls), table.clone(blocks)
	table.clear(walls)
	table.clear(blocks)
	out = L4B.travel(true, nil, "shot")
	local stopped = 0
	for _, ended in L4B.ends do
		if ended.hit == true then
			stopped += 1
		end
	end
	check(#out == 1 and out[1].fx.dodged ~= true and out[1].at > lapse - 1e-9 and stopped == 0, `a held shot is told "dodged" and flies on ({stopped} ended on a body), then lands as the claim lapses ({#out} effect)`)
	out = L4B.travel(false, nil, "shot")
	stopped = 0
	for _, ended in L4B.ends do
		if ended.hit == true then
			stopped += 1
		end
	end
	check(#out == 1 and out[1].fx.dodged ~= true and stopped == 1, `and with no claim it lands at once and ends on them ({stopped} ended on a body)`)
	for _, wall in walls0 do
		table.insert(walls, wall)
	end
	for _, box in blocks0 do
		table.insert(blocks, box)
	end
	L4B.ends = nil
end

-- G1 (docs/prompts/l4-w1b-fix2.md): a claim that never proves costs exactly what no claim costs.
-- A queue of strikes (times after the claim, ping 0.05: the commit lag 0.1) played from a fresh
-- run, with no claim or with a claim made at 0 that never proves (a still root). Returns the health
-- lost, every hurt with its frame, and the run's start. `setup` runs after the fresh run, `onFrame`
-- (a fresh one per run) each frame before it is stepped; `ping` (default 0.05) sets the lag.
function L4B.queue(claim: boolean, impacts: { any }, setup: (() -> ())?, onFrame: ((since: number) -> ())?, seconds: number?, ping: number?): (number, { any }, number)
	L4B.fresh(ping or 0.05)
	if setup ~= nil then
		setup()
	end
	local start = L4B.humanoid.Health
	local from = fakeNow
	if claim then
		L4B.claimNow()
	end
	local out = L4B.play(nil, impacts, seconds or 0.9, from, onFrame)
	return start - L4B.humanoid.Health, out, from
end

-- "landed dodged ...": what each hurt said, in the order they left.
function L4B.pattern(out: { any }): string
	local parts = {}
	for _, entry in out do
		table.insert(parts, if entry.fx.dodged then "dodged" else "landed")
	end
	return table.concat(parts, " ")
end

-- The same queue with no claim and with one that never proves: the same loss (`lost`), the same
-- landings and dodges in the same order, and with the claim the first `waited` effects (default
-- all) on the frame it lapses: each waited, held for the claim or behind a decision that was.
function L4B.sameAsNoClaim(label: string, impacts: { any }, lost: number, waited: number?): ()
	local lapse = L4B.shippedRule.lapse
	local lostFree, free = L4B.queue(false, impacts)
	local lostHeld, held = L4B.queue(true, impacts)
	local atLapse = #held == #free
	for index, entry in held do
		if index <= (waited or #held) then
			atLapse = atLapse and entry.at > lapse - 1e-9 and entry.at <= lapse + 1 / 60 + 1e-9
		end
	end
	check(lostFree == lost and lostHeld == lostFree and L4B.pattern(held) == L4B.pattern(free) and atLapse, `G1: {label}: no claim lost {lostFree} ({L4B.pattern(free)}), a claim that never proves lost {lostHeld} ({L4B.pattern(held)}), the waiting ones as it lapsed {atLapse}`)
end

-- A knocking hit at 0 and a ring that leaves 12 studs off at 0: it reaches the root at 0.275, after
-- the claim's window ([0, 0.25)), and the crowd step of 0.4 finds it (ThreatField, steps every fourth
-- frame), while the knock (decided at 0.1) is still held for the claim.
-- `distance` (default 12): how far off the ring leaves.
function L4B.ringQueue(claim: boolean, distance: number?): (number, { any })
	L4B.fresh(0.05)
	local start = L4B.humanoid.Health
	local from = fakeNow
	if claim then
		L4B.claimNow()
	end
	L4B.threat.impact(L4B.strike(from, 10))
	local ring = L4B.strike(from)
	ring.def = { shape = "ring", speed = 40, radius = 30, width = 2, damage = 8, height = 5 }
	ring.origin = vec(0, 3, distance or 12)
	ring.aim = vec(0, 3, 0)
	ring.facing = vec(0, 0, -1)
	L4B.threat.impact(ring)
	local out = {}
	for k = 1, 54 do
		fakeNow = from + k / L4B.HZ
		if k % 4 == 0 then
			L4B.threat.step(fakeNow)
		end
		for _, fx in L4B.frame(vec(0, 3, 0)) do
			table.insert(out, { fx = fx, at = fakeNow - from })
		end
	end
	return start - L4B.humanoid.Health, out
end

-- Runs `cases` with config.player's `key` at `value`, and puts it back whatever happens.
function L4B.withPlayer(key: string, value: number, cases: () -> ()): ()
	local was = config.player[key]
	config.player[key] = value
	local ok, problem = pcall(cases)
	config.player[key] = was
	if not ok then
		error(problem, 0)
	end
end

function L4B.knockTests(): ()
	print(" (g) knocks among held hits (G1): a claim that never proves costs what no claim costs")
	local lapse = L4B.shippedRule.lapse
	-- The review's three queues (docs/prompts/l4-w1b-review/4-fix-diff.md M1), 8 a hit, knockIframes 0.4.
	L4B.sameAsNoClaim("a knocking hit at 0, a plain one at 0.05", { { at = 0, knockback = 10 }, { at = 0.05 } }, 8)
	L4B.sameAsNoClaim("two knocking hits in one step, at 0", { { at = 0, knockback = 10 }, { at = 0, knockback = 10 } }, 8)
	L4B.sameAsNoClaim("a held knocking hit at 0.05, then one at 0.27 its claim would not cover", { { at = 0.05, knockback = 10 }, { at = 0.27 } }, 8)
	-- The released knock's windows run from its moment (0.1), not from the release: a hit at 0.5,
	-- after them (and after the lapse), lands, as with no claim.
	L4B.sameAsNoClaim("a knocking hit at 0, a plain one at 0.5 after its window", { { at = 0, knockback = 10 }, { at = 0.5 } }, 16, 1)

	-- What travels waits behind a held decision too: the ring's contact, which the claim would not
	-- cover, is judged as of its own step (0.4) once the knock before it is released, so the knock's
	-- window voids it, as with no claim.
	local lostFree, free = L4B.ringQueue(false)
	local lostHeld, held = L4B.ringQueue(true)
	local behind = held[2] ~= nil and held[2].at > lapse - 1e-9 and held[2].at <= lapse + 1 / 60 + 1e-9
	check(lostFree == 8 and lostHeld == 8 and L4B.pattern(free) == "landed dodged" and L4B.pattern(held) == "landed dodged" and behind, `G1: a ring's contact found while a knock is held waits behind it and is voided by it: no claim lost {lostFree} ({L4B.pattern(free)}), held lost {lostHeld} ({L4B.pattern(held)})`)

	-- A knock voids what was waiting at its moment only: a hit whose impact came before the knock but
	-- that a late step raised after it (at 0.2, its impact -0.1) was not among them. With knockIframes
	-- 0.05 neither knock window covers it either: with no claim it lands, and held behind the knock it
	-- lands too.
	L4B.withPlayer("knockIframes", 0.05, function()
		local function lateHit(): (since: number) -> ()
			local raised = false
			return function(since: number)
				if not raised and since > 0.2 - 1e-9 then
					raised = true
					L4B.threat.impact(L4B.strike(fakeNow - since - 0.1))
				end
			end
		end
		local lostA, outA = L4B.queue(false, { { at = 0, knockback = 10 } }, nil, lateHit())
		local lostB, outB = L4B.queue(true, { { at = 0, knockback = 10 } }, nil, lateHit())
		check(lostA == 16 and lostB == 16 and L4B.pattern(outA) == "landed landed" and L4B.pattern(outB) == "landed landed", `G1: a knock does not void a hit that joined the queue after its moment: no claim lost {lostA} ({L4B.pattern(outA)}), held lost {lostB} ({L4B.pattern(outB)})`)
	end)
	-- The same late hit with knockIframes 0.3: its moment (0.2) is inside the knock's window from the
	-- knock's moment (to 0.4), so ruling 18 voids it, held or not, though that window has closed by
	-- the release (0.47).
	L4B.withPlayer("knockIframes", 0.3, function()
		local function lateHit(): (since: number) -> ()
			local raised = false
			return function(since: number)
				if not raised and since > 0.2 - 1e-9 then
					raised = true
					L4B.threat.impact(L4B.strike(fakeNow - since - 0.1))
				end
			end
		end
		local lostLateFree, lateFree = L4B.queue(false, { { at = 0, knockback = 10 } }, nil, lateHit())
		local lostLateHeld, lateHeld = L4B.queue(true, { { at = 0, knockback = 10 } }, nil, lateHit())
		check(lostLateFree == 8 and lostLateHeld == 8 and L4B.pattern(lateFree) == "landed dodged" and L4B.pattern(lateHeld) == "landed dodged", `G1: a waiting hit decided inside a released knock's window (from its moment) is voided: no claim lost {lostLateFree} ({L4B.pattern(lateFree)}), held lost {lostLateHeld} ({L4B.pattern(lateHeld)})`)
	end)

	-- With knockIframes 0 a knock opens no window and `knockUntil` voids nothing after its own moment:
	-- only ruling 18's "struck and waiting" voids what was decided with it. So here each half of it
	-- shows: what waits behind the knock is voided by it (two knocking hits in one step); what joined
	-- the queue after the knock's moment is not, whether it is an impact a late step raised that is
	-- not yet due at the release (ping 0.25: lag 0.3; the knock decided on the frame of 0.42, the late
	-- hit struck at 0.3, raised at 0.43, decided at 0.6) or a ring's contact (it reaches the root at 0.05, before the
	-- knock's moment, and the step of 0.2 finds it, after it).
	L4B.withPlayer("knockIframes", 0, function()
		L4B.sameAsNoClaim("knockIframes 0, two knocking hits in one step", { { at = 0, knockback = 10 }, { at = 0, knockback = 10 } }, 8)
		local function lateDue(): (since: number) -> ()
			local raised = false
			return function(since: number)
				if not raised and since > 0.43 then
					raised = true
					L4B.threat.impact(L4B.strike(fakeNow - since + 0.3))
				end
			end
		end
		local lostP, outP = L4B.queue(false, { { at = 0.1, knockback = 10 } }, nil, lateDue(), 0.9, 0.25)
		local lostQ, outQ = L4B.queue(true, { { at = 0.1, knockback = 10 } }, nil, lateDue(), 0.9, 0.25)
		check(lostP == 16 and lostQ == 16 and L4B.pattern(outP) == "landed landed" and L4B.pattern(outQ) == "landed landed", `G1: knockIframes 0, a late hit not yet due at the release is not voided by the knock: no claim lost {lostP} ({L4B.pattern(outP)}), held lost {lostQ} ({L4B.pattern(outQ)})`)
		local lostR, outR = L4B.ringQueue(false, 3)
		local lostS, outS = L4B.ringQueue(true, 3)
		check(lostR == 16 and lostS == 16 and L4B.pattern(outR) == "landed landed" and L4B.pattern(outS) == "landed landed", `G1: knockIframes 0, a ring's contact found after a held knock's moment is judged at its own step: no claim lost {lostR} ({L4B.pattern(outR)}), held lost {lostS} ({L4B.pattern(outS)})`)
	end)

	-- A down from a held hit starts at its moment: stood up at 0.5 (StandUp), a hit that struck at
	-- 0.45, inside the down, is the down's and is dropped, as with no claim.
	local function lowAgain(): ()
		L4B.humanoid.Health = 8
	end
	local function standUp(): (since: number) -> ()
		return function(since: number)
			if math.abs(since - 0.5) < 0.5 / 60 then
				L4B.vitals.StandUp(L4B.player)
			end
		end
	end
	local _, upFree = L4B.queue(false, { { at = 0 }, { at = 0.45 } }, lowAgain, standUp())
	local _, upHeld = L4B.queue(true, { { at = 0 }, { at = 0.45 } }, lowAgain, standUp())
	check(L4B.pattern(upFree) == "landed" and L4B.pattern(upHeld) == "landed", `G1: a held hit's down runs from its moment: a hit inside it, decided after a stand-up, is dropped (no claim: {L4B.pattern(upFree)}; held: {L4B.pattern(upHeld)})`)

	-- ClearThreats takes the waiting too: a hit held for a claim, then the threats cleared (a camp's
	-- clear, a run's end), lands on nobody.
	local _, cleared = L4B.queue(true, { { at = 0 } }, nil, function(since: number)
		if math.abs(since - 0.2) < 0.5 / 60 then
			L4B.vitals.ClearThreats()
		end
	end)
	check(#cleared == 0, `G1: ClearThreats drops a decision that waits ({#cleared} effects)`)

	-- A released hit is taken at its moment: one that puts the player down tells the same get-up
	-- and stands them up at the same time as with no claim, though its effect leaves at the lapse.
	local function low(): ()
		L4B.humanoid.Health = 8
	end
	local function watchUp(log: { [string]: boolean }): (since: number) -> ()
		return function(since: number)
			if math.abs(since - 2.05) < 0.5 / 60 then
				log.downAt205 = L4B.vitals.IsDown(L4B.player)
			elseif math.abs(since - 2.15) < 0.5 / 60 then
				log.downAt215 = L4B.vitals.IsDown(L4B.player)
			end
		end
	end
	local logFree, logHeld = {}, {}
	local _, downFree, fromFree = L4B.queue(false, { { at = 0 } }, low, watchUp(logFree), 2.3)
	local _, downHeld, fromHeld = L4B.queue(true, { { at = 0 } }, low, watchUp(logHeld), 2.3)
	local a, b = downFree[1], downHeld[1]
	local sameUp = a ~= nil and b ~= nil and a.fx.down == true and b.fx.down == true and a.fx.upAt ~= nil and b.fx.upAt ~= nil and math.abs((a.fx.upAt - fromFree) - (b.fx.upAt - fromHeld)) < 1e-6
	check(sameUp and b.at > lapse - 1e-9 and logFree.downAt205 == true and logHeld.downAt205 == true and logFree.downAt215 == false and logHeld.downAt215 == false, `G1: a held hit that puts them down is a down from its moment: the same upAt and the same get-up (2.1 s) as with no claim (down at 2.05: {tostring(logFree.downAt205)} / {tostring(logHeld.downAt205)}, at 2.15: {tostring(logFree.downAt215)} / {tostring(logHeld.downAt215)})`)

	-- And regen waits regenDelay from its moment (0.1): 0.35 s after that, both runs have healed about
	-- as much (to a regen step), where a delay counted from the release (0.47) would not have begun.
	-- At the shipped regenPerSecond (the fixture's own is 0 by now, set by earlier groups).
	local sampleAt = 0.1 + config.player.regenDelay + 0.35
	L4B.withPlayer("regenPerSecond", FIXTURES.proving.player.regenPerSecond, function()
		local function sample(log: { number }): (since: number) -> ()
			return function(since: number)
				if math.abs(since - sampleAt) < 0.5 / 60 then
					table.insert(log, L4B.humanoid.Health)
				end
			end
		end
		local healthFree, healthHeld = {}, {}
		L4B.queue(false, { { at = 0 } }, nil, sample(healthFree), sampleAt + 0.1)
		L4B.queue(true, { { at = 0 } }, nil, sample(healthHeld), sampleAt + 0.1)
		-- A fresh run starts at full health; the hit took 8, so more than 2 back is regen begun.
		local hit = L4B.humanoid.MaxHealth - 8
		local hFree, hHeld = healthFree[1], healthHeld[1]
		check(hFree ~= nil and hHeld ~= nil and hFree > hit + 2 and hHeld > hit + 2 and math.abs(hFree - hHeld) <= 1.5, `G1: regen waits from a held hit's moment: health {string.format("%.2f", sampleAt)} s in {hFree} with no claim, {hHeld} held (both from {hit})`)
	end)

	-- An honest dash proven late against the third queue: the held knock is dodged on the proof's
	-- frame, and the later hit, with nothing left waiting before it, lands at its own moment (0.38),
	-- as before L4.
	L4B.fresh(0.05)
	local start = L4B.humanoid.Health
	local claimAt = L4B.claimNow()
	local out = L4B.play(L4B.dashFrom(0.15), { { at = 0.05, knockback = 10 }, { at = 0.27 } }, 0.9, claimAt)
	check(#out == 2 and out[1].fx.dodged == true and out[1].at < 0.25 and out[2].fx.dodged ~= true and out[2].at > 0.37 - 1e-9 and out[2].at < 0.37 + 1 / 60 + 1e-9 and L4B.humanoid.Health == start - 8, `G1: a dash proven late: the held knock dodged at {if out[1] then string.format("%.3f", out[1].at) else "-"} s, the later hit landed at its own moment {if out[2] then string.format("%.3f", out[2].at) else "-"} s (health {start} -> {L4B.humanoid.Health})`)
end

function L4B.vitalsTests(): ()
	L4B.startVitals()
	L4B.group("dash proof: (g) study", L4B.studyTests)
	L4B.group("dash proof: (g) cases", L4B.casesTests)
	L4B.group("dash proof: (g) travelling", L4B.travelTests)
	L4B.group("dash proof: (g) knocks among held hits (G1)", L4B.knockTests)
	config.player.regenPerSecond = L4B.regen
	L4B.vitals.ClearThreats()
	-- tests.luau's VitalsService takes the crowd's hooks back.
	Crowd.SetThreatHooks(hooks)
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
