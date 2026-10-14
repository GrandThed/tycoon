-- Cases for L1b Wave 2, the crowd and the hit shapes (docs/INTERFACES.md "Wave 2 — the long road"
-- -> "A — tools/crowd_harness/tests_l1b_w2_crowd.luau"): HitShapes.CrowdRay, RayUpright and
-- FlatToRect, Query's bounding sphere against the new shape, SwingGate, CampBrain's tent posture,
-- dormancy, gaps, join-in, rouse and tent rule, and CrowdService's dormancy, spawn infos, join-in,
-- RouseGroup, GroupAlive, GroupedOn and the [Perf] attribute. Appended after tests_l1b.luau by
-- run_harness.py, so every local of the earlier files is in scope (vec, check, near, load, config,
-- Crowd, player, root, step2, seen, fresh, risen, fired, players, services, modules, token,
-- requireStub, osStub, SOURCES, FIXTURES, L1BC...). Everything hangs off one table (the bundle's
-- 200-local limit), and every group runs behind L1BC.group, so one that throws fails a check and
-- the bundle goes on.

print("L1b Wave 2: the crowd and the hit shapes")

local W2A: any = {
	Shapes = load("HitShapes"),
	CB = load("CampBrain"),
	Codec = load("CrowdCodec"),
	ORIGIN = vec(0, 0, 0),
}

-- A Park–Miller stream of uniform draws in [0, 1), for seeded grids.
function W2A.stream(seed: number): () -> number
	local state = seed
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

-- Longbow A, as it ships: the width and pad of the headshot report's probe.
function W2A.bow(): (number, number, number)
	local variant = FIXTURES.proving.weapons.longbow.variants.A
	return variant.width, variant.pad, variant.range
end

function W2A.kinds(): { [string]: any }
	return FIXTURES.proving.crowd.kinds
end

-- The capsule's top (L1b-W2-16): the head's base, or today's sphere top when that is higher.
function W2A.top(def: any): number
	return math.max(def.height - 2 * def.headRadius, def.height / 2 + def.radius)
end

-- CrowdRay -----------------------------------------------------------------------------------------
function W2A.crowdRayTests(): ()
	local Shapes = W2A.Shapes
	print(" HitShapes.CrowdRay")
	local width, pad, reach = W2A.bow()
	local origin = vec(0, 5, 30)
	local feet = vec(0, 0, 0)
	local function aimAt(point: any): any
		return point - origin
	end
	local names = {}
	for name in W2A.kinds() do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local def = W2A.kinds()[name]
		local r, h, hr = def.radius, def.height, def.headRadius
		local function shoot(from: any, direction: any): (number?, boolean)
			return Shapes.CrowdRay(from, direction, reach, width, pad, feet, r, h, hr)
		end
		local head = vec(0, h - hr, 0)
		local a, aCrit = shoot(origin, aimAt(vec(0, h - 0.25 * hr, 0)))
		check(a ~= nil and aCrit, `{name} (a): aimed high in the head, an entry and a crit`)
		local b, bCrit = shoot(origin, aimAt(head))
		check(b ~= nil and bCrit, `{name} (b): at the head's centre, a crit`)
		local c, cCrit = shoot(origin, aimAt(vec(0, h + hr + width / 2 + pad + 0.3, 0)))
		check(c == nil and not cCrit, `{name} (c): over the head by its radius, the bow's reach and 0.3, nil`)
		local d, dCrit = shoot(origin, aimAt(vec(0, h / 2, 0)))
		check(d ~= nil and not dCrit, `{name} (d): at the body's centre, an entry, no crit`)
		-- Beside the head, inside the pad but outside the unpadded reach.
		local graze = vec(hr + width / 2 + pad / 2, h - hr, 0)
		local e, eCrit = shoot(vec(graze.X, graze.Y, 30), vec(0, 0, -1))
		check(e ~= nil and not eCrit, `{name} (e): grazing the head within the pad, an entry, no crit`)
		local f, fCrit = shoot(origin, aimAt(vec(0, 0.5, 0)))
		check(f ~= nil and not fCrit, `{name} (f): at the shins, an entry, no crit`)
		-- Level with the capsule's middle, straight along -Z, beside it by the grown radius + 0.01.
		local middle = W2A.top(def) / 2
		local g, gCrit = shoot(vec(r + width / 2 + pad + 0.01, middle, 30), vec(0, 0, -1))
		check(g == nil and not gCrit, `{name} (g): beside the capsule by 0.01 past its reach, nil`)
		-- (h) Flat along -Z at the capsule's top: both the body and the head are touched, the body
		-- first; straight down from above: the head first.
		local level = vec(0, W2A.top(def), 30)
		local bodyFirst = Shapes.RayUpright(level, vec(0, 0, -1), reach, width, pad, feet, r, W2A.top(def) - r, r)
		local headLater = Shapes.Ray(level, vec(0, 0, -1), reach, width, pad, head, hr)
		local h1 = shoot(level, vec(0, 0, -1))
		check(
			bodyFirst ~= nil and headLater ~= nil and bodyFirst < headLater and h1 ~= nil and near(h1, bodyFirst, 1e-9),
			`{name} (h): along -Z at the capsule's top the entry is the body's, the nearer ({h1} vs head {headLater})`
		)
		local above = vec(0, 40, 0)
		local headFirst = Shapes.Ray(above, vec(0, -1, 0), reach, width, pad, head, hr)
		local h2 = shoot(above, vec(0, -1, 0))
		check(h2 ~= nil and headFirst ~= nil and near(h2, headFirst, 1e-9), `{name} (h): straight down, the head's entry, the nearer`)
		-- (i) Every ray that hits today's body sphere hits the capsule: 360 seeded rays from a sphere
		-- of 30 round the body, aimed into its grown sphere, and 40 flat ones grazing its top.
		local draw = W2A.stream(1000 + #name * 7 + h * 13)
		local centre = vec(0, h / 2, 0)
		local grown = r + width / 2 + pad
		local held, hitToday = true, 0
		for index = 1, 400 do
			local from, direction
			if index <= 360 then
				local u, v = draw() * 2 - 1, draw() * 2 * math.pi
				local s = math.sqrt(1 - u * u)
				from = centre + vec(s * math.cos(v), u, s * math.sin(v)) * 30
				local aim = centre + vec(draw() * 2 - 1, draw() * 2 - 1, draw() * 2 - 1) * grown
				direction = aim - from
			else
				local k = index - 360
				local angle = 2 * math.pi * k / 40
				local lift = grown - 0.02 - 0.3 * (k % 4) / 4
				from = vec(30 * math.sin(angle), h / 2 + lift, 30 * math.cos(angle))
				direction = vec(-math.sin(angle), 0, -math.cos(angle))
			end
			if Shapes.Ray(from, direction, reach, width, pad, centre, r) ~= nil then
				hitToday += 1
				held = held and shoot(from, direction) ~= nil
			end
		end
		check(held and hitToday > 100, `{name} (i): every one of {hitToday} rays that hit today's sphere hits the capsule`)
	end
end
L1BC.group("crowd ray", W2A.crowdRayTests)

-- RayUpright and FlatToRect --------------------------------------------------------------------------
function W2A.uprightTests(): ()
	local Shapes = W2A.Shapes
	print(" HitShapes.RayUpright, FlatToRect")
	local draw = W2A.stream(4242)
	local same = true
	local hits = 0
	for _ = 1, 200 do
		local feet = vec(draw() * 6 - 3, draw() * 2, draw() * 6 - 3)
		local low = draw() * 4
		local radius = 0.5 + draw() * 2
		local from = vec(draw() * 40 - 20, draw() * 20 - 5, draw() * 40 - 20)
		local aim = feet + vec(draw() * 6 - 3, low + draw() * 6 - 3, draw() * 6 - 3)
		local width, pad, reach = draw(), draw(), 5 + draw() * 40
		local upright = Shapes.RayUpright(from, aim - from, reach, width, pad, feet, low, low, radius)
		local sphere = Shapes.Ray(from, aim - from, reach, width, pad, feet + vec(0, low, 0), radius)
		same = same and upright == sphere
		if sphere ~= nil then
			hits += 1
		end
	end
	check(same and hits > 20, `low == high answers exactly what Ray does, on 200 seeded rays ({hits} hits)`)
	local feet = vec(0, 0, 0)
	check(Shapes.RayUpright(vec(0.5, 3, 0), vec(1, 0, 0), 10, 0, 0, feet, 1, 5, 1) == 0, "a ray that starts inside answers 0")
	local down = Shapes.RayUpright(vec(0, 20, 0), vec(0, -1, 0), 50, 0, 0, feet, 2, 5, 1)
	check(down ~= nil and near(down, 14), `a vertical ray down the axis meets the top cap at 20 - (5 + 1) = 14 ({down})`)
	local up = Shapes.RayUpright(vec(0, -10, 0), vec(0, 1, 0), 50, 0, 0, feet, 2, 5, 1)
	check(up ~= nil and near(up, 11), `and one up the axis the bottom cap at 2 - 1 + 10 = 11 ({up})`)
	check(Shapes.RayUpright(vec(0, 3, 30), vec(0, 0, -1), 10, 0, 0, feet, 1, 5, 1) == nil, "a ray stopping short of reach is nil")
	local side = Shapes.RayUpright(vec(0, 3, 30), vec(0, 0, -1), 29.5, 0.4, 0.3, feet, 1, 5, 1)
	check(side ~= nil and near(side, 30 - 1.5), `the side is met at 30 - (1 + 0.2 + 0.3) ({side})`)
	local cap = Shapes.RayUpright(vec(0, 5.5, 30), vec(0, 0, -1), 50, 0, 0, feet, 1, 5, 1)
	check(cap ~= nil and near(cap, 30 - math.sqrt(0.75)), `a ray along the top cap, half a radius over the segment, enters it at 30 - sqrt(0.75) ({cap})`)
	local underCap = Shapes.RayUpright(vec(0, 0.5, 30), vec(0, 0, -1), 50, 0, 0, feet, 1, 5, 1)
	check(underCap ~= nil and near(underCap, 30 - math.sqrt(0.75)), "and one along the bottom cap the same")
	check(Shapes.RayUpright(vec(0, 6.01, 30), vec(0, 0, -1), 50, 0, 0, feet, 1, 5, 1) == nil, "over the top cap: nil")
	local slant = Shapes.RayUpright(vec(10, 3, 10), vec(-1, 0, -1), 50, 0, 0, feet, 1, 5, 1)
	check(slant ~= nil and near(slant, math.sqrt(200) - 1), "a slant ray meets the side at its flat distance less the radius")

	check(Shapes.FlatToRect(1, -2, 0, 0, 5, 3) == 0, "FlatToRect: inside, 0")
	check(Shapes.FlatToRect(5, 0, 0, 0, 5, 3) == 0 and Shapes.FlatToRect(-5, 1, 0, 0, 5, 3) == 0 and Shapes.FlatToRect(0, 3, 0, 0, 5, 3) == 0 and Shapes.FlatToRect(2, -3, 0, 0, 5, 3) == 0, "on each edge, 0")
	check(near(Shapes.FlatToRect(9, 1, 0, 0, 5, 3), 4) and near(Shapes.FlatToRect(1, -10, 0, 0, 5, 3), 7), "past an edge, the distance to it")
	check(near(Shapes.FlatToRect(18, 20, 10, 10, 5, 6), 5), "past a corner, 3-4-5: 5")
end
L1BC.group("upright", W2A.uprightTests)

-- Query holds the shape ------------------------------------------------------------------------------
function W2A.queryTests(): ()
	print(" CrowdService.Query holds the capsule and the head")
	local width, pad = W2A.bow()
	local inside = true
	for name, def in W2A.kinds() do
		local centre = vec(0, def.height / 2, 0)
		local bound = math.max(def.radius, def.height / 2)
		local top = W2A.top(def)
		local farthest = {
			vec(0, def.height, 0),
			vec(def.headRadius, def.height - def.headRadius, 0),
			vec(0, 0, 0),
			vec(def.radius, def.radius, 0),
			vec(def.radius, top - def.radius, 0),
			vec(0, top, 0),
		}
		for _, point in farthest do
			if (point - centre).Magnitude > bound + 1e-9 then
				inside = false
				print(`   {name}: {point.X}, {point.Y} lies outside Query's sphere`)
			end
		end
	end
	check(inside, "for every kind, the capsule's and the head's farthest points lie inside Query's bounding sphere")
	-- The real Query on the real kinds: a ray's broad phase at each kind's head top and shins.
	config.crowd.kinds = W2A.kinds()
	check(Crowd.SetBounds(vec(0, 0, 0), vec(500, 50, 500)) == true, "(one wide floor)")
	local found = true
	local x = 0
	for name, def in W2A.kinds() do
		x += 20
		local id = Crowd.Spawn(name, vec(x, 0, 0), "idle")
		step2()
		local body = Crowd.Get(id)
		if body == nil then
			found = false
			continue
		end
		local feet = body.position
		for _, point in { feet + vec(0, def.height, 0), feet + vec(def.radius, 0.1, 0) } do
			local hit = false
			for _, other in Crowd.Query(point, width / 2 + pad) do
				hit = hit or other == id
			end
			found = found and hit
		end
	end
	check(found, "Query finds every kind from its head's top and from its shins")
end
L1BC.crowdGroup("query", W2A.queryTests)

-- SwingGate -------------------------------------------------------------------------------------------
function W2A.swingTests(): ()
	print(" SwingGate")
	local Gate = load("SwingGate")
	check(Gate.AIR_MARGIN_STUDS == 0.75, "the margin is 0.75 (WeaponService's, moved)")
	check(not Gate.IsAir(3.75, 3) and Gate.IsAir(3.7501, 3) and Gate.IsAir(nil, 3), "IsAir: at the margin exactly grounded, just past it airborne, no floor airborne")
	local state = Gate.New()
	check(state.used == false, "a new state is clear")
	local sequence = {}
	local function swing(airborne: boolean): ()
		local allowed = Gate.Allows(state, airborne)
		table.insert(sequence, allowed)
		if allowed then
			Gate.Took(state, airborne)
		end
	end
	swing(false)
	swing(true)
	swing(true)
	Gate.Landed(state)
	swing(true)
	swing(false)
	swing(true)
	local want = { true, true, false, true, true, true }
	local same = #sequence == #want
	for index, value in want do
		same = same and sequence[index] == value
	end
	check(same, "ground swing, air (allowed), air (refused), Landed, air (allowed), ground (clears), air (allowed)")
	swing(true)
	check(sequence[#sequence] == false, "and the next air swing before a landing is refused")
end
L1BC.group("swing gate", W2A.swingTests)

-- SwingGate, fix round A-1: one landing rule for both sides --------------------------------------------
-- A jump of movement.jumpHeight 18 under the default gravity, a root standing 3 over a floor at 0,
-- integrated at the client's 240 Hz physics. A hop touches the floor for ONE physics step, then
-- jumps again (held Space); `dj` = { at = height over standing, into = jump height } double-jumps
-- once in the first hop's fall. Returns the steps { t, y, vy } and the bounce times.
W2A.G = 196.2
W2A.STAND = 3
W2A.DT = 1 / 240

function W2A.hops(count: number, dj: any?): ({ any }, { number })
	local v0 = math.sqrt(2 * W2A.G * 18)
	local steps, bounces = {}, {}
	local t, y, vy = 0, W2A.STAND, 0
	local function push(): ()
		table.insert(steps, { t = t, y = y, vy = vy })
	end
	for _ = 1, 24 do
		push()
		t += W2A.DT
	end
	local left = count
	local doubled = dj == nil
	vy = v0
	while left > 0 do
		vy -= W2A.G * W2A.DT
		y += vy * W2A.DT
		t += W2A.DT
		if not doubled and vy < 0 and y <= W2A.STAND + dj.at then
			doubled = true
			vy = math.sqrt(2 * W2A.G * dj.into)
		end
		if y <= W2A.STAND and vy < 0 then
			y, vy = W2A.STAND, 0
			push()
			table.insert(bounces, t)
			left -= 1
			if left > 0 then
				vy = v0
			end
		else
			push()
		end
	end
	for _ = 1, 48 do
		t += W2A.DT
		push()
	end
	return steps, bounces
end

-- The physics state at time `t`: the last step at or before it.
function W2A.at(steps: { any }, t: number): any
	local best = steps[1]
	for _, s in steps do
		if s.t <= t + 1e-9 then
			best = s
		else
			break
		end
	end
	return best
end

-- The same, replicated: snapshots every `every` seconds (from `offset`), read between two
-- snapshots by straight interpolation of the height and the vertical speed.
function W2A.replicated(steps: { any }, t: number, every: number, offset: number): any
	local k = math.floor((t - offset) / every)
	local a = W2A.at(steps, offset + k * every)
	local b = W2A.at(steps, offset + (k + 1) * every)
	local f = math.clamp((t - (offset + k * every)) / every, 0, 1)
	return { t = t, y = a.y + (b.y - a.y) * f, vy = a.vy + (b.vy - a.vy) * f }
end

-- Runs one sampler over a trajectory: Observe every 1/60 s, an airborne swing (lag 0) at the
-- first sample past each apex. Returns landings, swings refused, and swings taken.
function W2A.run(Gate: any, steps: { any }, sample: (number) -> any, phase: number): (number, number, number)
	local gate = Gate.New()
	local landings, refused, taken = 0, 0, 0
	local rising = false
	local last = steps[#steps].t
	local t = phase
	while t <= last do
		local s = sample(t)
		if Gate.Observe(gate, s.y, s.vy, 0, W2A.STAND, false) then
			landings += 1
		end
		if s.vy > 0 then
			rising = true
		elseif rising then
			rising = false
			local allowed, airborne = Gate.Judge(gate, s.y, 0, W2A.STAND, 0)
			if allowed then
				Gate.Took(gate, airborne)
				taken += 1
			else
				refused += 1
			end
		end
		t += 1 / 60
	end
	return landings, refused, taken
end

function W2A.landingTests(): ()
	print(" SwingGate: one landing rule (fix round A-1)")
	local Gate = load("SwingGate")
	local steps, bounces = W2A.hops(4)
	check(#bounces == 4, "(four hops, three one-step bounces and a landing)")
	local worst = { direct = "", slow = "" }
	local phases = 40
	for index = 0, phases - 1 do
		local phase = index / phases / 60
		local l, r, k = W2A.run(Gate, steps, function(t)
			return W2A.at(steps, t)
		end, phase)
		if worst.direct == "" and (l ~= 4 or r ~= 0 or k ~= 4) then
			worst.direct = `phase {index}: {l} landings, {r} refused, {k} taken`
		end
		local l2, r2, k2 = W2A.run(Gate, steps, function(t)
			return W2A.replicated(steps, t, 1 / 20, phase * 0.7)
		end, phase)
		if worst.slow == "" and (l2 ~= 4 or r2 ~= 0 or k2 ~= 4) then
			worst.slow = `phase {index}: {l2} landings, {r2} refused, {k2} taken`
		end
	end
	check(worst.direct == "", `a held-Space bunny hop sampled at 60 Hz: every bounce is one landing and every hop's swing is allowed, at all {phases} phases {worst.direct}`)
	check(worst.slow == "", `and the same copy replicated at 20 Hz and read between snapshots (height and speed interpolated) {worst.slow}`)

	-- A double jump is no landing: once just past the apex, once 10 studs up the fall.
	local high = { at = 17, into = 12 }
	local mid = { at = 10, into = 12 }
	local refusedHigh, refusedMid, landedEarly = 0, 0, 0
	for index = 0, phases - 1 do
		local phase = index / phases / 60
		for _, dj in { high, mid } do
			local djSteps = W2A.hops(1, dj)
			local l, r, k = W2A.run(Gate, djSteps, function(t)
				return W2A.at(djSteps, t)
			end, phase)
			if l ~= 1 then
				landedEarly += 1
			end
			if r == 1 and k == 1 then
				if dj == high then
					refusedHigh += 1
				else
					refusedMid += 1
				end
			end
		end
	end
	check(refusedHigh == phases and refusedMid == phases, `a double jump just past the apex and 10 studs up the fall: the second apex's swing is refused at every phase ({refusedHigh}, {refusedMid} of {phases})`)
	check(landedEarly == 0, `and only the final touchdown is a landing ({landedEarly} runs counted another)`)

	-- The server's copy trails the claim by the lag: a swing just after a bounce arrives first.
	local function lagged(lag: number, after: number): (number, number)
		local gate = Gate.New()
		local allowedAfter, refusedApex = 0, 0
		local swings = {}
		for index = 1, #bounces - 1 do
			local b = bounces[index]
			table.insert(swings, { t = b + after, apex = false })
			table.insert(swings, { t = b + math.sqrt(2 * 18 / W2A.G), apex = true })
		end
		table.insert(swings, 1, { t = bounces[1] - math.sqrt(2 * 18 / W2A.G), apex = true })
		local next = 1
		local t = 0
		while t <= steps[#steps].t do
			local copy = W2A.at(steps, t - lag)
			Gate.Observe(gate, copy.y, copy.vy, 0, W2A.STAND, false)
			local swing = swings[next]
			if swing ~= nil and t >= swing.t then
				next += 1
				local claim = W2A.at(steps, swing.t)
				local allowed, airborne = Gate.Judge(gate, claim.y, 0, W2A.STAND, lag)
				if allowed then
					Gate.Took(gate, airborne)
				end
				if not swing.apex and allowed then
					allowedAfter += 1
				elseif swing.apex and swing.t > bounces[1] and not allowed then
					refusedApex += 1
				end
			end
			t += 1 / 60
		end
		return allowedAfter, refusedApex
	end
	local after1, apex1 = lagged(0.15, 0.03)
	check(after1 == 3, `a swing 0.03 s after each bounce, the copy 0.15 s behind and still falling: the claim is the newest sample and finds the landing ({after1} of 3 allowed)`)
	check(apex1 == 3, `and the copy's own bounce later is not a second landing: the same hop's apex swing is refused ({apex1} of 3)`)
	local after2 = lagged(0.3, 0.17)
	check(after2 == 3, `with the lag at its 0.3 s ceiling and the swing 0.17 s after the bounce, both above the turn window alone ({after2} of 3)`)

	-- The landing ahead of the copy needs a copy falling within reach of its floor.
	local gate = Gate.New()
	Gate.Observe(gate, 20, -5, 0, W2A.STAND, false)
	Gate.Observe(gate, 19.9, -6, 0, W2A.STAND, false)
	Gate.Took(gate, true)
	check(not Gate.Judge(gate, 21, 0, W2A.STAND, 0.3), "a copy falling slowly far up (a double jump's claim) finds no landing: refused")
	gate = Gate.New()
	Gate.Observe(gate, 3.1, 10, 0, W2A.STAND, false)
	Gate.Observe(gate, 5, 60, 0, W2A.STAND, false)
	Gate.Took(gate, true)
	check(not Gate.Judge(gate, 8, 0, W2A.STAND, 0.3), "nor a copy still rising from the floor: refused")
	gate = Gate.New()
	Gate.Observe(gate, 14, -50, 0, W2A.STAND, false)
	Gate.Observe(gate, 13, -60, 0, W2A.STAND, false)
	Gate.Took(gate, true)
	check(not Gate.Judge(gate, 9, 0, W2A.STAND, 0 / 0), "a NaN lag reads as 0: 9.25 over the band at 60 studs/s is past the window alone")
	check(Gate.Judge(gate, 9, 0, W2A.STAND, 0.1), "and a lag of 0.1 s brings it within reach: allowed")
	Gate.Took(gate, true)
	check(not Gate.Judge(gate, 9, 0, W2A.STAND, 0.1), "once: the next swing before the copy's own landing is refused")
	Gate.Observe(gate, W2A.STAND, 0, 0, W2A.STAND, false)
	check(not Gate.Judge(gate, 9, 0, W2A.STAND, 0.1), "and that landing, taken ahead, does not clear it again")
end
L1BC.group("swing gate: landings", W2A.landingTests)

function W2A.footprintTests(): ()
	print(" SwingGate: the footprint and the get-up (fix round A-1)")
	local Gate = load("SwingGate")
	check(Gate.PROBE_POINTS == #Gate.FOOTPRINT and Gate.PROBE_POINTS == 5, "five probe points")
	local cx, cz = Gate.ProbePoint(1, 4, 7, 1, 0, 1, 0.5)
	check(cx == 4 and cz == 7, "the first is the centre")
	local function corners(rx: number, rz: number): string
		local seen = {}
		for index = 2, Gate.PROBE_POINTS do
			local x, z = Gate.ProbePoint(index, 0, 0, rx, rz, 1, 0.5)
			table.insert(seen, string.format("%.2f,%.2f", x + 0, z + 0))
		end
		table.sort(seen)
		return table.concat(seen, " ")
	end
	check(corners(1, 0) == "-1.00,-0.50 -1.00,0.50 1.00,-0.50 1.00,0.50", `facing -Z: the corners are the root's 2 x 1 rectangle ({corners(1, 0)})`)
	check(corners(0, -2) == "-0.50,-1.00 -0.50,1.00 0.50,-1.00 0.50,1.00", `turned a quarter (right = -Z, any length): the rectangle turns with it ({corners(0, -2)})`)
	check(corners(0, 0) == corners(1, 0), "a right vector with no flat part reads as facing +X")
	check(Gate.Higher(nil, nil) == nil and Gate.Higher(nil, 3) == 3 and Gate.Higher(2, nil) == 2 and Gate.Higher(2, 5) == 5 and Gate.Higher(5, 2) == 5, "Higher keeps the highest floor found")

	-- The probe as both sides cast it, against a made-up world.
	local function floorUnder(world: (number, number) -> number?, x: number, z: number, rx: number, rz: number): number?
		local floorY = nil
		for index = 1, Gate.PROBE_POINTS do
			local px, pz = Gate.ProbePoint(index, x, z, rx, rz, 1, 0.5)
			floorY = Gate.Higher(floorY, world(px, pz))
		end
		return floorY
	end
	local ledge = function(x: number, _z: number): number?
		return if x < 0 then 8 else 0
	end
	local fence = function(x: number, _z: number): number?
		return if math.abs(x) < 0.25 then 4 else 0
	end
	local lip = floorUnder(ledge, 0.6, 0, 1, 0)
	check(lip == 8, "a root whose centre is 0.6 past a ledge's lip still has the ledge under a corner")
	local gate = Gate.New()
	Gate.Observe(gate, 8 + W2A.STAND, 0, lip, W2A.STAND, false)
	local allowed, airborne = Gate.Judge(gate, 8 + W2A.STAND, lip, W2A.STAND, 0)
	check(allowed and not airborne, "standing on the lip is grounded on both questions")
	Gate.Took(gate, airborne)
	allowed, airborne = Gate.Judge(gate, 8 + W2A.STAND, lip, W2A.STAND, 0)
	check(allowed and not airborne, "and every swing there is a grounded one")
	check(floorUnder(ledge, 0.6, 0, 0, -1) == 0 and floorUnder(ledge, 0.4, 0, 0, -1) == 8, "turned a quarter the footprint is 1 wide across the lip: 0.6 past is off it, 0.4 past is on it")
	check(floorUnder(fence, 0.9, 0, 1, 0) == 4, "a fence top under one corner is the floor")

	-- A down clears the gate, and the get-up stands up clear.
	gate = Gate.New()
	Gate.Observe(gate, 12, 20, 0, W2A.STAND, false)
	Gate.Took(gate, true)
	check(not Gate.Allows(gate, true), "(an air swing taken)")
	Gate.Observe(gate, 10, -30, 0, W2A.STAND, true)
	check(Gate.Allows(gate, true), "a down clears it, while still in the air")
	Gate.Observe(gate, 1, 0, 0, W2A.STAND, true)
	Gate.Observe(gate, W2A.STAND, 0, 0, W2A.STAND, false)
	check(Gate.Allows(gate, true) and not gate.falling and not gate.ahead, "the get-up stands up with nothing spent and no fall held")
	Gate.Observe(gate, 12, 20, 0, W2A.STAND, false)
	Gate.Took(gate, true)
	Gate.Observe(gate, 14, 10, 0, W2A.STAND, true)
	Gate.Observe(gate, 14, 5, 0, W2A.STAND, false)
	check(Gate.Allows(gate, true), "a knockdown in the air and a get-up in the air: the next jump's swing is allowed")
	Gate.Took(gate, true)
	Gate.Landed(gate)
	check(Gate.Allows(gate, true) and gate.lastY == nil, "Landed (a new character) resets the samples too")
	check(Gate.Observe(gate, W2A.STAND, 0, 0, W2A.STAND, false) == false, "a first grounded sample is no landing")
end
L1BC.group("swing gate: footprint and get-up", W2A.footprintTests)

-- CampBrain --------------------------------------------------------------------------------------------
function W2A.rules(over: any?): any
	local rules = L1BC.rules()
	rules.dormantRadius = 120
	for key, value in over or {} do
		rules[key] = value
	end
	return rules
end

function W2A.campBrainTests(): ()
	local CB = W2A.CB
	print(" CampBrain: the tent posture, Problems")
	local tent = L1BC.def("tent", { vec(10, 3, 20) }, { radius = 6 })
	local posts = CB.Posts(tent, 8)
	local ring = #posts == 8
	for k, post in posts do
		local theta = 2 * math.pi * (k - 1) / 8
		local dx, dz = post.at.X - 10, post.at.Z - 20
		local wrapped = if theta > math.pi then theta - 2 * math.pi else theta
		ring = ring
			and near(post.at.Y, 8)
			and near(math.sqrt(dx * dx + dz * dz), 6, 1e-9)
			and near(dx, -math.sin(theta) * 6, 1e-9)
			and near(dz, -math.cos(theta) * 6, 1e-9)
			and near(post.yaw, wrapped, 1e-9)
			and post.yaw > -math.pi and post.yaw <= math.pi
			and near(-math.sin(post.yaw), dx / 6, 1e-9)
			and near(-math.cos(post.yaw), dz / 6, 1e-9)
			and post.leg == 0
	end
	check(ring, "a tent of 8: bearings 2π(k-1)/8 at its radius round the marker, on the floor, each facing away, yaw in (-π, π]")
	local group = CB.NewGroup(tent, 0)
	check(CB.Shows(group, false) == "idle" and CB.Shows(group, true) == "move", "a tent at rest stands (idle), and moves")
	group.held = true
	check(CB.Shows(group, false) == "idle", "held: idle")
	group.held = false
	group.state = "home"
	check(CB.Shows(group, false) == "idle" and CB.Shows(group, true) == "move", "home: idle, move")

	check(#CB.Problems(W2A.rules()) == 0, "the contract's rules have no problem")
	local noTent = W2A.rules()
	noTent.tent = nil
	local problems = CB.Problems(noTent)
	check(#problems == 1 and string.find(problems[1], "camps.tent", 1, true) ~= nil, "a missing tent is one line")
	local tentKeys = true
	for _, key in { "sight", "cone", "rise" } do
		local copy = W2A.rules()
		copy.tent[key] = nil
		tentKeys = tentKeys and #CB.Problems(copy) == 1
	end
	check(tentKeys, "each missing tent key is one line")
	check(#CB.Problems(W2A.rules({ joinFactor = 0 })) == 1 and #CB.Problems(W2A.rules({ joinFactor = -1 })) == 1, "a joinFactor of 0 or less is a problem")
	check(#CB.Problems(W2A.rules({ joinFactor = 0.01 })) == 0, "and any above 0 is not")
	local missing = W2A.rules()
	missing.joinFactor = nil
	missing.dormantRadius = nil
	check(#CB.Problems(missing) == 2, "joinFactor and dormantRadius missing: a line each")
	check(#CB.Problems(W2A.rules({ dormantRadius = 30 })) == 1, "a dormantRadius at the widest sight exactly (the guard's 30) is a problem")
	check(#CB.Problems(W2A.rules({ dormantRadius = 30.01 })) == 0, "just past it is not")
	check(#CB.Problems(W2A.rules({ dormantRadius = 20 })) == 3, "under the patrol's, the tent's and the guard's sight: three lines")
	local wideTent = W2A.rules({ dormantRadius = 31 })
	wideTent.tent.sight = 40
	check(#CB.Problems(wideTent) == 1, "the tent's sight counts too")
	check(#CB.Problems(W2A.rules({ dormantRadius = 0 / 0 })) == 1, "a NaN dormantRadius is one line")

	print(" CampBrain.Dormant, Gap")
	local rules = W2A.rules()
	local guard = CB.NewGroup(L1BC.def("guard", { vec(0, 8, 0) }), 0)
	check(not CB.Dormant(guard, { vec(150, 11, 0) }, rules), "a root at dormantRadius exactly (150 = 30 + 120) is near: not dormant")
	check(CB.Dormant(guard, { vec(150.01, 11, 0) }, rules), "just past it: dormant")
	check(not CB.Dormant(guard, { vec(150.01, 11, 0), vec(0, 11, 140) }, rules), "every root must be far: one near keeps it awake")
	check(CB.Dormant(guard, {}, rules), "no roots: dormant")
	check(not CB.Dormant(guard, { vec(30 + 72, 11, 30 + 96) }, rules) and CB.Dormant(guard, { vec(30 + 72.1, 11, 30 + 96.1) }, rules), "the distance is to the rectangle (a corner at 3-4-5 x 24)")
	guard.held = true
	check(CB.Dormant(guard, {}, rules), "a held rest is dormant")
	guard.held = false
	local never = true
	for _, state in { "rise", "fight", "home" } do
		guard.state = state
		never = never and not CB.Dormant(guard, {}, rules) and not CB.Dormant(guard, { vec(500, 0, 0) }, rules)
	end
	check(never, "rise, fight and home are never dormant")

	local function post(x: number, z: number): any
		return { at = vec(x, 8, z), yaw = 0, leg = 0 }
	end
	check(near(CB.Gap({ post(0, 0), post(10, 0) }, { post(13, 4), post(40, 40) }), 5), "Gap: the least flat distance between a post of each (3-4-5)")
	check(CB.Gap({}, { post(0, 0) }) == math.huge and CB.Gap({ post(0, 0) }, {}) == math.huge, "Gap with no posts on a side: math.huge")
	check(near(CB.Gap({ { at = vec(0, 0, 0), yaw = 0, leg = 0 } }, { { at = vec(3, 50, 4), yaw = 0, leg = 0 } }), 5), "Gap is flat: height plays no part")
end
L1BC.group("camp brain", W2A.campBrainTests)

-- JoinIn, Rouse, the tent rule ------------------------------------------------------------------------
-- Groups of one camp by posture, all at rest: index -> CampBrain.Group.
function W2A.groups(postures: { string }): { any }
	local list = {}
	for index, posture in postures do
		table.insert(list, W2A.CB.NewGroup(L1BC.def(posture, { vec(index * 100, 8, 0) }), 0))
	end
	return list
end

-- A symmetric gap table from { { a, b, gap } }.
function W2A.gaps(count: number, pairs: { { number } }): { [number]: { [number]: number } }
	local gaps = {}
	for index = 1, count do
		gaps[index] = {}
	end
	for _, pair in pairs do
		gaps[pair[1]][pair[2]] = pair[3]
		gaps[pair[2]][pair[1]] = pair[3]
	end
	return gaps
end

function W2A.list(values: { number }): string
	local parts = {}
	for _, value in values do
		table.insert(parts, tostring(value))
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

function W2A.joinTests(): ()
	local CB = W2A.CB
	local rules = W2A.rules()
	print(" CampBrain.JoinIn")
	-- 1 guard (sight 30, reach 60), 2 and 3 fires (16, reach 32), 4 a fire 45 from 3 only.
	local groups = W2A.groups({ "guard", "fire", "fire", "fire" })
	local living = { 2, 2, 2, 2 }
	local gaps = W2A.gaps(4, { { 1, 2, 50 }, { 1, 3, 70 }, { 2, 3, 30 }, { 3, 4, 45 }, { 1, 4, 100 }, { 2, 4, 75 } })
	local chain = CB.JoinIn(groups, living, gaps, { 1 }, rules)
	check(W2A.list(chain) == "{2, 3}", `a chain of three: 2 within the guard's 60, 3 within 2's own 32 only; 4 is 45 from 3, past a fire's 32 ({W2A.list(chain)})`)
	check(groups[2].state == "rest" and groups[3].state == "rest", "JoinIn mutates nothing")

	local directed = W2A.groups({ "fire", "guard" })
	local twoGaps = W2A.gaps(2, { { 1, 2, 40 } })
	check(#CB.JoinIn(directed, { 1, 1 }, twoGaps, { 1 }, rules) == 0, "directed: a fire (reach 32) does not bring in a guard 40 away")
	check(W2A.list(CB.JoinIn(directed, { 1, 1 }, twoGaps, { 2 }, rules)) == "{1}", "but that guard (reach 60) brings the fire in")

	local skipped = W2A.groups({ "guard", "guard", "guard", "guard", "guard", "guard" })
	skipped[2].held = true
	skipped[3].state = "home"
	skipped[5].state = "fight"
	local skipGaps = W2A.gaps(6, { { 1, 2, 10 }, { 1, 3, 10 }, { 1, 4, 10 }, { 1, 5, 10 } })
	-- 6 is of another camp: no gap is written between them (CrowdService writes none).
	check(#CB.JoinIn(skipped, { 1, 1, 1, 0, 1, 1 }, skipGaps, { 1 }, rules) == 0, "held, home, empty (no living member), fighting and other-camp groups never join")

	local edge = W2A.groups({ "fire", "fire", "fire" })
	local edgeGaps = W2A.gaps(3, { { 1, 2, 32 }, { 1, 3, 32 + 1e-9 } })
	check(W2A.list(CB.JoinIn(edge, { 1, 1, 1 }, edgeGaps, { 1 }, rules)) == "{2}", "the factor's edge: a gap of exactly 2 x 16 joins, a hair past it does not")
	local factor = W2A.rules({ joinFactor = 3 })
	check(#CB.JoinIn(edge, { 1, 1, 1 }, edgeGaps, { 1 }, factor) == 2, "and joinFactor is read (3 x 16 takes both)")

	local twice = W2A.groups({ "guard", "guard", "guard" })
	local twiceGaps = W2A.gaps(3, { { 1, 2, 5 }, { 1, 3, 5 }, { 2, 3, 5 } })
	local once = CB.JoinIn(twice, { 1, 1, 1 }, twiceGaps, { 1, 2 }, rules)
	check(W2A.list(once) == "{3}", `two wakers in reach of each other and of a third: the third once, neither waker ({W2A.list(once)})`)

	print(" CampBrain.Rouse")
	local roused = W2A.groups({ "tent", "tent", "tent", "tent", "tent" })
	roused[1].hit = true
	check(CB.Rouse(roused[1], 7) and roused[1].state == "rise" and roused[1].since == 7 and roused[1].hit == false, "rest: rise, since now, hit cleared, true")
	roused[2].held = true
	check(not CB.Rouse(roused[2], 7) and roused[2].state == "rest" and roused[2].held, "held: nothing, false")
	local unchanged = true
	for index, state in { [3] = "rise", [4] = "fight", [5] = "home" } do
		roused[index].state = state
		roused[index].since = 1
		unchanged = unchanged and not CB.Rouse(roused[index], 7) and roused[index].state == state and roused[index].since == 1
	end
	check(unchanged, "rise, fight, home: nothing, false")

	print(" CampBrain: the tent rule")
	check(CB.TentActive(true, 5) and CB.TentActive(false, 0) and CB.TentActive(false, -1) and not CB.TentActive(false, 3), "TentActive: busy, or no resident alive")
	local fresh = CB.NewTent(8)
	check(fresh.left == 8 and fresh.nextAt == -math.huge, "NewTent: the stock, the first body due at once")
	-- Busy 0..13, paused 13..40, busy 40..50, at rest with residents alive 50..60, residents all
	-- dead from 60 (the camp still at rest), to 100, at half-second ticks.
	local timeline = CB.NewTent(8)
	local sent = {}
	for tick = 0, 200 do
		local now = tick * 0.5
		local busy = now < 13 or (now >= 40 and now < 50)
		local residents = if now >= 60 then 0 else 4
		if CB.TentDue(timeline, CB.TentActive(busy, residents), now) then
			table.insert(sent, now)
			CB.TentSent(timeline, now, 6)
		end
	end
	check(W2A.list(sent) == "{0, 6, 12, 40, 46, 60, 66, 72}", `wake at 0: 0, 6, 12; paused 13 to 40, the next at 40; residents dead at rest: it keeps sending; then never ({W2A.list(sent)})`)
	check(timeline.left == 0, "the stock spent")
	local spent = CB.NewTent(1)
	CB.TentSent(spent, 0, 6)
	CB.TentSent(spent, 6, 6)
	check(spent.left == 0 and not CB.TentDue(spent, true, 1000), "a spent tent is never due, and its stock never goes under 0")
	check(not CB.TentDue(CB.NewTent(3), false, 0), "an inactive tent is not due")
	local onTime = CB.NewTent(3)
	CB.TentSent(onTime, 1, 6)
	check(onTime.nextAt == 7 and onTime.left == 2 and CB.TentDue(onTime, true, 7 - 1e-7) and not CB.TentDue(onTime, true, 6.99), "TentSent: nextAt = now + every; due at it (within the step's epsilon)")
end
L1BC.group("join", W2A.joinTests)

-- CrowdService -----------------------------------------------------------------------------------------
-- Two camp floors (L1BC.campFloors) with this wave's rules (dormantRadius 120), and every snapshot
-- of a step kept, not only the last one.
function W2A.enter(): ()
	check(
		Crowd.SetFloors({ { centre = vec(0, 8, 0), half = vec(30, 200, 30) }, { centre = vec(200, 12, 0), half = vec(30, 200, 30) } }) == true,
		"(two camp floors)"
	)
	Crowd.SetCampRules(W2A.rules())
	W2A.snaps = {}
	if W2A.realFire == nil then
		W2A.realFire = modules.RemoteService.FireAllUnreliable
		modules.RemoteService.FireAllUnreliable = function(name, payload)
			table.insert(W2A.snaps, payload)
			W2A.realFire(name, payload)
		end
	end
end

function W2A.leave(): ()
	if W2A.realFire ~= nil then
		modules.RemoteService.FireAllUnreliable = W2A.realFire
		W2A.realFire = nil
	end
end

-- Steps `count` times; true when `id` was in none of the snapshots sent meanwhile.
function W2A.absent(id: number, count: number): boolean
	table.clear(W2A.snaps)
	step2(count)
	for _, payload in W2A.snaps do
		for _, entry in W2A.Codec.Decode(payload, W2A.ORIGIN) do
			if entry.id == id then
				return false
			end
		end
	end
	return true
end

function W2A.crowdGroup(name: string, cases: () -> ()): ()
	L1BC.crowdGroup(name, function()
		local ok, problem = pcall(cases)
		W2A.leave()
		if not ok then
			error(problem)
		end
	end)
end

-- A group def with its units (so AddGroup works out its posts and gaps), placed with its bodies.
function W2A.place(posture: string, points: { any }, kinds: { string }, over: any?): (number, { number }, any)
	local units = {}
	for _, kind in kinds do
		table.insert(units, { kind = kind, count = 1 })
	end
	local options = { units = units }
	for key, value in over or {} do
		options[key] = value
	end
	local def = L1BC.def(posture, points, options)
	local index, ids = L1BC.place(def, kinds)
	return index, ids, def
end

function W2A.dormantTests(): ()
	print(" CrowdService: dormancy")
	W2A.enter()
	-- Something always on the wire, so a snapshot goes out every step.
	Crowd.Spawn("pawn", vec(-20, 8, -20), "idle")
	-- Fix round A-2: the patroller walks first (a root 20 from its floor, inside 120), so the
	-- freeze has a walking state to reset.
	root.Position = vec(150, 11, 0)
	local east = { floor = 2, floorY = 12, rect = { x = 200, z = 0, hx = 30, hz = 30 }, id = "B.loop", camp = "B" }
	local loop = { vec(190, 12, -10), vec(210, 12, -10), vec(210, 12, 10), vec(190, 12, 10) }
	local group, ids = W2A.place("patrol", loop, { "fodder", "fodder" }, east)
	local post = Crowd.Get(ids[1]).position
	step2(10)
	local walking = Crowd.Get(ids[1])
	check(walking.state == "move" and (walking.position.X ~= post.X or walking.position.Z ~= post.Z), `(awake to the wire, the patroller walks: {walking.state})`)
	root.Position = vec(0, 11, 0)
	step2()
	local before = Crowd.Get(ids[1]).position
	check(W2A.absent(ids[1], 30) and W2A.absent(ids[2], 1), "a group with every root beyond dormantRadius (170 > 120) is in no snapshot")
	local frozen = Crowd.Get(ids[1])
	check(frozen.position.X == before.X and frozen.position.Z == before.Z, `and is not integrated: a patroller does not move over 30 steps ({before.X}, {before.Z})`)
	check(frozen.state == "idle", `frozen mid-walk it shows idle, the state a late joiner's refreshed spawn info is copied from (the infos case pins the copy): {frozen.state}`)
	root.Position = vec(150, 11, 0)
	local present = not W2A.absent(ids[1], 1)
	step2(10)
	local moved = Crowd.Get(ids[1]).position
	check(present and (moved.X ~= before.X or moved.Z ~= before.Z), "a root walking within 120 (20 from the floor) wakes it into snapshots, and it walks its loop again")
	check(#L1BC.events() == 0, "(nobody saw anybody: the patrol is still at rest)")
	root.Position = vec(0, 11, 0)
	check(W2A.absent(ids[1], 2), "out again: dormant again")
	local dealt = Crowd.Damage(ids[2], 5, 0, nil, nil)
	check(dealt == 5, "a lever hit lands on a dormant body (it is still in the grid and judged as any resident)")
	step2()
	local events = L1BC.events()
	check(#events == 1 and events[1].group == group and events[1].from == "rest" and events[1].to == "rise", "and wakes its group")
	check(not W2A.absent(ids[1], 1), "which is then in the snapshots, far from everyone")
	local query = Crowd.Query(vec(190, 12, -10), 40)
	local inGrid = false
	for _, id in query do
		inGrid = inGrid or id == ids[1]
	end
	check(inGrid, "Query finds the group's bodies")
end
W2A.crowdGroup("dormant", W2A.dormantTests)

function W2A.infoTests(): ()
	print(" CrowdService: spawn infos")
	W2A.enter()
	root.Position = vec(-25, 11, -25)
	local fireGroup, fireIds = W2A.place("fire", { vec(-10, 8, 15) }, { "fodder", "fodder" }, { radius = 3 })
	local loop = { vec(10, 8, 10), vec(20, 8, 10), vec(20, 8, 20), vec(10, 8, 20) }
	local _, walkers = W2A.place("patrol", loop, { "fodder" }, { id = "A.loop" })
	step2()
	local firePosts = W2A.CB.Posts(L1BC.def("fire", { vec(-10, 8, 15) }, { radius = 3 }), 2)
	local byId = {}
	for _, entry in risen do
		byId[entry.id] = entry
	end
	local sitter = byId[fireIds[1]]
	check(
		sitter ~= nil and sitter.state == "rest" and sitter.at ~= nil and near(sitter.at.X, firePosts[1].at.X) and near(sitter.at.Z, firePosts[1].at.Z) and near(sitter.at.Y, 8) and sitter.yaw ~= nil and near(sitter.yaw, firePosts[1].yaw),
		"a resident's spawn info carries at (its post), yaw (its post's) and state (rest, seated)"
	)
	check(fireGroup == 1 and Crowd.GroupAlive(fireGroup) == 2, "(placed)")
	step2(20)
	local walker = Crowd.Get(walkers[1])
	local first = byId[walkers[1]]
	check(first ~= nil and walker ~= nil and (walker.position - first.at).Magnitude > 2, "(the patroller walked on from where it was announced)")
	-- A late joiner, through a second CrowdService of the same source whose PlayerAdded is caught.
	local hooked: any = {}
	local services2 = setmetatable({
		Players = {
			GetPlayers = function()
				return players
			end,
			PlayerAdded = {
				Connect = function(_self, fn)
					hooked.added = fn
				end,
			},
		},
		RunService = {
			Heartbeat = {
				Connect = function(_self, fn)
					hooked.beat = fn
				end,
			},
		},
	}, { __index = services })
	local game2 = {
		GetService = function(_self, name)
			return services2[name]
		end,
	}
	local second = (SOURCES :: any).CrowdService(
		game2,
		token("script"),
		requireStub,
		V,
		osStub,
		{ spawn = function(fn, ...)
			fn(...)
		end },
		print,
		{ new = function()
			return {}
		end },
		{ RaycastFilterType = { Exclude = 1 } }
	)
	check(second.SetFloors({ { centre = vec(0, 8, 0), half = vec(30, 200, 30) } }) == true, "(a second crowd, its own floor)")
	second.SetCampRules(W2A.rules())
	local def = L1BC.def("patrol", loop, { units = { { kind = "fodder", count = 1 } } })
	local index = second.AddGroup(def)
	local id = second.SpawnResident("fodder", index, W2A.CB.Posts(def, 1)[1])
	local function beat(count: number): ()
		for _ = 1, count do
			fakeNow += DT
			hooked.beat(DT)
		end
	end
	beat(1)
	local announced = nil
	for _, call in fired do
		if call.name == "CrowdSpawn" then
			for _, entry in call.payload do
				if entry.id == id then
					announced = { at = entry.at, yaw = entry.yaw, state = entry.state }
				end
			end
		end
	end
	beat(20)
	table.clear(fired)
	local newcomer = { UserId = 99, Parent = {} }
	hooked.added(newcomer)
	local late = nil
	for _, call in fired do
		if call.player == newcomer and call.name == "CrowdSpawn" then
			for _, entry in call.payload do
				if entry.id == id then
					late = entry
				end
			end
		end
	end
	local now = second.Get(id)
	check(
		announced ~= nil and late ~= nil and now ~= nil and late.at ~= nil and (late.at - announced.at).Magnitude > 2 and near(late.at.X, now.position.X) and near(late.at.Z, now.position.Z) and late.state == "move" and late.yaw ~= nil,
		"a late joiner's spawn info is refreshed: where the body stands now, walking, its yaw"
	)
	second.Clear()
	table.clear(fired)
	-- The second crowd shared CrowdBrain's floors: L1BC.leave's SetBounds puts the first crowd's back.
end
W2A.crowdGroup("infos", W2A.infoTests)

-- Fix round ui-2: `resting` on every spawn info, and a re-announce when a group goes to or from rest.
-- Read from what step2 gathered (risen, ended) right after each step: the stub keeps payloads by
-- reference, so values are copied at the time.
function W2A.clearSent(): ()
	table.clear(risen)
	table.clear(ended)
end

function W2A.sentSince(ids: { number }): ({ [number]: any }, boolean, boolean)
	local out = {}
	local other = false
	local wanted, removes = {}, {}
	for _, id in ids do
		wanted[id] = true
	end
	for _, entry in risen do
		if wanted[entry.id] then
			out[entry.id] = { resting = entry.resting, state = entry.state }
		else
			other = true
		end
	end
	for _, id in ended do
		removes[id] = true
	end
	local removed = true
	for _, id in ids do
		removed = removed and removes[id] == true
	end
	return out, other, removed
end

function W2A.restingTests(): ()
	print(" CrowdService: resting on the spawn info (fix round ui-2)")
	W2A.enter()
	root.Position = vec(0, 11, -100)
	W2A.clearSent()
	local wave = Crowd.Spawn("pawn", vec(-20, 8, -20), "idle")
	local group, ids = W2A.place("guard", { vec(10, 8, 10), vec(14, 8, 10) }, { "fodder", "fodder" })
	local _, heldIds = W2A.place("guard", { vec(210, 12, 0) }, { "fodder" }, { id = "B.held", camp = "B", floor = 2, floorY = 12, rect = { x = 200, z = 0, hx = 30, hz = 30 }, held = true })
	step2()
	local sent = W2A.sentSince({ wave, ids[1], ids[2], heldIds[1] })
	check(sent[ids[1]] ~= nil and sent[ids[1]].resting == true and sent[ids[2]] ~= nil and sent[ids[2]].resting == true, "a resident spawned at rest is announced resting")
	check(sent[heldIds[1]] ~= nil and sent[heldIds[1]].resting == true, "a held group's body is announced resting")
	check(sent[wave] ~= nil and sent[wave].resting == nil, "a wave body (no group) never carries resting")
	W2A.clearSent()
	Crowd.RouseGroup(group)
	step2()
	local roused, otherSent = W2A.sentSince(ids)
	check(roused[ids[1]] ~= nil and roused[ids[1]].resting == nil and roused[ids[2]] ~= nil and roused[ids[2]].resting == nil, "once its group wakes, the next batch re-announces it, not resting")
	check(not otherSent, "a batch of re-announces only goes out on its own (and the wave body and the held group are not sent again)")
	W2A.clearSent()
	Crowd.WakeFloor(2)
	step2()
	local released = W2A.sentSince(heldIds)
	check(released[heldIds[1]] ~= nil and released[heldIds[1]].resting == nil, "a held group released is re-announced, not resting")
	local rested = nil
	for _ = 1, 200 do
		W2A.clearSent()
		step2()
		local backToRest = false
		for _, event in L1BC.events() do
			backToRest = backToRest or (event.group == group and event.to == "rest")
		end
		if backToRest then
			rested = W2A.sentSince(ids)
			break
		end
	end
	check(rested ~= nil and rested[ids[1]] ~= nil and rested[ids[1]].resting == true and rested[ids[2]] ~= nil and rested[ids[2]].resting == true, "after home and rest it is re-announced resting again")
	-- A body that leaves before the re-announce is ended, not announced.
	W2A.clearSent()
	Crowd.Remove(ids[2])
	Crowd.RouseGroup(group)
	step2()
	local after, _, removed = W2A.sentSince({ ids[2] })
	check(removed and after[ids[2]] == nil, "a body removed while its group's re-announce is due gets its CrowdRemove and no announce")
	W2A.clearSent()
end
W2A.crowdGroup("resting", W2A.restingTests)

function W2A.joinCrowdTests(): ()
	print(" CrowdService: the join-in, RouseGroup, GroupAlive, GroupedOn")
	W2A.enter()
	root.Position = vec(25, 11, 25)
	local a = W2A.place("fire", { vec(-20, 8, -20) }, { "fodder", "fodder" }, { id = "A.a", radius = 2 })
	local b = W2A.place("fire", { vec(10, 8, -20) }, { "fodder", "fodder" }, { id = "A.b", radius = 2 })
	local c = W2A.place("fire", { vec(-20, 8, 20) }, { "fodder", "fodder" }, { id = "A.c", radius = 2 })
	local other = W2A.place("fire", { vec(190, 12, -20) }, { "fodder" }, { id = "B.x", camp = "B", floor = 2, floorY = 12, rect = { x = 200, z = 0, hx = 30, hz = 30 }, radius = 2 })
	-- A group of another camp on the same floor, 12 from A.a's posts: within reach, never joined.
	local stranger = W2A.place("fire", { vec(-20, 8, -36) }, { "fodder" }, { id = "Z.x", camp = "Z", radius = 2 })
	step2(2)
	check(#L1BC.events() == 0, "(four resting fires, nobody seen)")
	root.Position = vec(-20, 11, -5)
	step2()
	local events = L1BC.events()
	local byGroup = {}
	for _, event in events do
		byGroup[event.group] = (byGroup[event.group] or 0) + 1
	end
	check(
		#events == 2 and byGroup[a] == 1 and byGroup[b] == 1 and byGroup[c] == nil and byGroup[other] == nil and byGroup[stranger] == nil,
		`a wake by sight (A.a) brings in A.b (gap 30, within 2 x 16) and not A.c (36), nor Z.x of another camp (12): one GroupEvent each ({#events} events)`
	)
	local joined = nil
	for _, event in events do
		if event.group == b then
			joined = event
		end
	end
	check(joined ~= nil and joined.from == "rest" and joined.to == "rise" and joined.held == false and #joined.ids == 2, "the joined group's event: rest to rise, not held, its two ids")
	check(Crowd.Busy()[1] == true, "(the floor is busy)")

	fresh()
	W2A.enter()
	root.Position = vec(25, 11, 25)
	local tent, tentIds = W2A.place("tent", { vec(-10, 8, -10) }, { "fodder" }, { id = "A.tent", radius = 3 })
	step2(2)
	check(seen(tentIds[1]).state == "idle", "a tent's body stands at rest")
	Crowd.RouseGroup(tent)
	check(#L1BC.events() == 0, "(RouseGroup acts at the next step, not at once)")
	step2()
	local rose = L1BC.events()
	check(#rose == 1 and rose[1].group == tent and rose[1].from == "rest" and rose[1].to == "rise" and rose[1].held == false, "RouseGroup rises a resting tent group at the next step: one event")
	check(seen(tentIds[1]).state == "rise", "it shows rise")
	step2()
	check(L1BC.events()[1] ~= nil, "(a rise of 0: it fights the next step)")
	Crowd.RouseGroup(tent)
	step2()
	local again = L1BC.events()
	local wokeAgain = false
	for _, event in again do
		wokeAgain = wokeAgain or (event.from == "rest" and event.to == "rise")
	end
	check(not wokeAgain, "and does nothing to a fighting one")
	Crowd.RouseGroup(77)
	step2()
	check(true, "(an unknown group is ignored)")

	fresh()
	W2A.enter()
	root.Position = vec(25, 11, 25)
	local three, threeIds = W2A.place("guard", { vec(-20, 8, -20), vec(-16, 8, -20), vec(-12, 8, -20) }, { "fodder", "fodder", "fodder" }, { id = "A.g" })
	local _, eastIds = W2A.place("guard", { vec(200, 12, 0) }, { "fodder" }, { id = "B.g", camp = "B", floor = 2, floorY = 12, rect = { x = 200, z = 0, hx = 30, hz = 30 } })
	Crowd.Spawn("pawn", vec(0, 8, 10), "idle", nil, nil, 1)
	check(Crowd.GroupAlive(three) == 3 and Crowd.GroupedOn(1) == 3 and Crowd.GroupedOn(2) == 1 and Crowd.AliveOn(1) == 4, "GroupAlive and GroupedOn count the residents, not a free body on the floor")
	Crowd.Damage(threeIds[2], 100000, 0, nil, nil)
	check(Crowd.GroupAlive(three) == 2 and Crowd.GroupedOn(1) == 2 and Crowd.AliveOn(1) == 3, "a kill takes one off both")
	Crowd.Remove(eastIds[1])
	check(Crowd.GroupedOn(2) == 0 and Crowd.GroupAlive(2) == 0, "a removal too")
	check(Crowd.GroupAlive(99) == 0 and Crowd.GroupedOn(9) == 0, "an unknown group or floor: 0")
	fresh()
	check(Crowd.GroupedOn(1) == 0 and Crowd.GroupAlive(three) == 0, "Clear empties both")
end
W2A.crowdGroup("join crowd", W2A.joinCrowdTests)

function W2A.perfTests(): ()
	-- (No label below may hold the text "[Perf]": the print filter would swallow it.)
	print(" CrowdService: the Perf attribute")
	local set: { any } = {}
	local workspace = services.Workspace
	workspace.SetAttribute = function(_self, name, value)
		table.insert(set, { name = name, value = value })
	end
	local realPrint = print
	local lines = 0
	print = function(...)
		local text = tostring((...))
		if string.find(text, "[Perf]", 1, true) ~= nil then
			lines += 1
		else
			realPrint(...)
		end
	end
	local ok, problem = pcall(function()
		Crowd.Spawn("pawn", vec(10, 0, 30), "idle")
		Crowd.SetPerfLog(1, "CrowdPerfMs")
		step2(20)
		local first = lines
		local named = #set >= 1 and set[1].name == "CrowdPerfMs" and typeof(set[1].value) == "number" and set[1].value >= 0
		check(first == 1 and #set == first and named, `each Perf line sets the attribute to its p95 ({first} lines, {#set} sets)`)
		Crowd.SetPerfLog(1, nil)
		table.clear(set)
		step2(20)
		check(lines == first + 1 and #set == 0, `with no name the line prints and nothing is set ({lines - first} lines, {#set} sets, {Crowd.AliveCount()} alive)`)
		Crowd.SetPerfLog(0)
		step2(20)
		check(#set == 0, "off: nothing")
	end)
	print = realPrint
	Crowd.SetPerfLog(0)
	workspace.SetAttribute = nil
	if not ok then
		error(problem)
	end
end
W2A.crowdGroup("perf", W2A.perfTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
