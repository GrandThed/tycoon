-- Scratch tests (never shipped). SOURCES.<name>(game, script, require, Vector3, os) are the real
-- module bodies, prepended by run_harness.py.

-- Vector3 shim ----------------------------------------------------------------------------------
local meta = {}
local function vec(x: number, y: number, z: number): any
	return setmetatable({ X = x, Y = y, Z = z }, meta)
end
meta.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		return vec(self.X / m, self.Y / m, self.Z / m)
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	end
	return nil
end
meta.__add = function(a, b)
	return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
meta.__sub = function(a, b)
	return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
meta.__mul = function(a, b)
	if type(a) == "number" then
		return vec(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return vec(a.X * b, a.Y * b, a.Z * b)
	end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
meta.__div = function(a, b)
	return vec(a.X / b, a.Y / b, a.Z / b)
end
meta.__unm = function(a)
	return vec(-a.X, -a.Y, -a.Z)
end
local V: any = {
	new = function(x, y, z)
		return vec(x or 0, y or 0, z or 0)
	end,
	zero = vec(0, 0, 0),
	yAxis = vec(0, 1, 0),
	xAxis = vec(1, 0, 0),
}

-- Stubs -------------------------------------------------------------------------------------------
local fakeNow = 100
local SERVER_OFFSET = 5000
local beats: { any } = {}
local vitalsBeat: any = nil
local crowdBeat: any = nil
local lastSnapshot: any = nil
local walls: { any } = {}
local blocks: { any } = {}
local rays = 0
-- Where the segment origin -> origin + direction enters a box, as a share of it; nil = never
-- (a segment that starts inside does not hit the box it is in).
local function intoBox(box: any, origin: any, direction: any): number?
	local enter = 0
	local leave = 1
	for _, axis in { "X", "Y", "Z" } do
		local from = origin[axis]
		local along = direction[axis]
		local low = box.min[axis]
		local high = box.max[axis]
		if along == 0 then
			if from < low or from > high then
				return nil
			end
		else
			local a = (low - from) / along
			local b = (high - from) / along
			if a > b then
				a, b = b, a
			end
			enter = math.max(enter, a)
			leave = math.min(leave, b)
			if enter > leave then
				return nil
			end
		end
	end
	return if enter > 0 then enter else nil
end
local threatHooks: any = nil
local fired: { any } = {}
local players: { any } = {}

local fodderAttack = {
	shape = "lunge",
	reach = 4.5,
	windup = 0.5,
	recover = 1.5,
	damage = 8,
	range = 5,
	width = 3,
	height = 5,
	interrupt = "stagger",
}
local arcAttack = {
	shape = "arc",
	reach = 6,
	windup = 0.8,
	recover = 1.2,
	damage = 30,
	knockback = 30,
	launch = 6,
	range = 7.5,
	arcDegrees = 120,
	height = 6,
	interrupt = "heavy",
}
local config: any = {
	crowd = {
		kinds = {
			fodder = { radius = 1.3, headRadius = 0.7, height = 5, speed = 12, hp = 40, armor = 0, knockbackMult = 1.0, brain = "rush", perPlayer = 4, attacks = { fodderAttack } },
			armoured = { radius = 1.7, headRadius = 0.8, height = 6.5, speed = 9, hp = 160, armor = 18, knockbackMult = 0.35, brain = "rush", attacks = { arcAttack } },
			dummy = { radius = 1.3, height = 5, speed = 12, knockbackMult = 1.0 },
			unarmed = { radius = 1.3, height = 5, speed = 12, knockbackMult = 1.0, brain = "rush" },
		},
		behaviour = { walkLength = 20, strafeWidth = 8, strafePeriod = 1.1, hopHeight = 7, hopPeriod = 1.6, chaseStandoff = 2, homePace = 0.5, homeTolerance = 0.75, walkPace = 0.6 },
		snapshotHz = 15,
		maxAlive = 160,
		deadSeconds = 0.6,
		knockFriction = 75,
		knockMax = 140,
		armorFloor = 0.1,
		heavyHit = 40,
		largeRadius = 2.5,
		staggerSeconds = 0.25,
		threat = { spawnGrace = 1.0, spawnClear = 12, maxShots = 24, strikeSeconds = 0.2 },
	},
	player = { downSeconds = 2, getUpIframes = 1.5, regenDelay = 4, regenPerSecond = 10, knockIframes = 0.4 },
	shooting = { originLagSeconds = 0.05, originLagMaxSeconds = 0.3 },
	movement = { walkSpeed = 20, dashDistance = 20, dashSeconds = 0.15, slamFallSpeed = 140 },
}

local modules: { [string]: any } = {
	Types = {},
	Catalog = {
		GetArmoryConfig = function()
			return ARMORY
		end,
		GetProvingGroundsConfig = function()
			return config
		end,
	},
	RemoteService = {
		FireClient = function(player, name, payload)
			table.insert(fired, { player = player, name = name, payload = payload })
		end,
		FireAllUnreliable = function(_name, payload)
			lastSnapshot = payload
		end,
	},
}

local function token(name: string): any
	local t: any = { __module = name }
	t.WaitForChild = function(_self, child)
		return token(child)
	end
	t.Parent = t
	return t
end

local services: any = {
	Players = {
		GetPlayers = function()
			return players
		end,
		PlayerAdded = {
			Connect = function() end,
		},
	},
	ReplicatedStorage = token("ReplicatedStorage"),
	HttpService = {},
	RunService = {
		Heartbeat = {
			Connect = function(_self, fn)
				table.insert(beats, fn)
			end,
		},
	},
	Workspace = {
		Gravity = 196.2,
		Raycast = function(_self, origin, direction, _params)
			rays += 1
			local best: any = nil
			local bestShare = math.huge
			for _, wall in walls do
				local from = if wall.axis == "X" then origin.X else origin.Z
				local along = if wall.axis == "X" then direction.X else direction.Z
				if along ~= 0 then
					local share = (wall.at - from) / along
					if share >= 0 and share <= 1 and share < bestShare then
						bestShare = share
						best = origin + direction * share
					end
				end
			end
			for _, box in blocks do
				local share = intoBox(box, origin, direction)
				if share ~= nil and share < bestShare then
					bestShare = share
					best = origin + direction * share
				end
			end
			return if best ~= nil then { Position = best } else nil
		end,
		GetServerTimeNow = function()
			return fakeNow + SERVER_OFFSET
		end,
	},
}
local gameStub: any = {
	GetService = function(_self, name)
		return services[name]
	end,
}
local osStub: any = {
	clock = function()
		return fakeNow
	end,
}
local load: any
local function requireStub(t: any): any
	return load(t.__module)
end
load = function(name: string): any
	if modules[name] == nil then
		local source = (SOURCES :: any)[name]
		assert(source, "no source for " .. name)
		local taskStub = {
			spawn = function(fn, ...)
				fn(...)
			end,
		}
		local rayParams = {
			new = function()
				return {}
			end,
		}
		local enumStub = { RaycastFilterType = { Exclude = 1 } }
		modules[name] = source(gameStub, token("script"), requireStub, V, osStub, taskStub, print, rayParams, enumStub)
	end
	return modules[name]
end

local failures = 0
local function check(ok: boolean, label: string): ()
	if ok then
		print("  ok    " .. label)
	else
		failures += 1
		print("  FAIL  " .. label)
	end
end
local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

-- Codec -------------------------------------------------------------------------------------------
print("CrowdCodec v2")
do
	local Codec = load("CrowdCodec")
	local states = { "idle", "move", "windup", "stagger", "airborne", "dead", "attack", "recover" }
	local entries = {}
	for index, state in states do
		table.insert(entries, {
			id = index * 7,
			position = vec(index, 0.5 * index, -index),
			yaw = 0.3 * index - 1,
			state = state,
			hpFraction = index / 8,
			plated = index % 2 == 0,
			attack = (index - 1) % 8,
		})
	end
	local data = Codec.Encode(entries, vec(0, 0, 0), 1234.5)
	check(buffer.readu8(data, 0) == 2, "version byte is 2")
	check(buffer.len(data) == 10 + 11 * #entries, "entry is still 11 bytes")
	local decoded = Codec.Decode(data, vec(0, 0, 0))
	local same = #decoded == #entries
	for index, entry in entries do
		local got = decoded[index]
		same = same
			and got.id == entry.id
			and got.state == entry.state
			and got.plated == entry.plated
			and got.attack == entry.attack
			and near(got.position.X, entry.position.X, 1 / 32)
			and near(got.hpFraction, entry.hpFraction, 1 / 255)
	end
	check(same, "Decode round-trips state, plated, attack for all eight states")
	local seen = 0
	local eachOk = Codec.DecodeEach(data, vec(0, 0, 0), function(id, _x, _y, _z, _yaw, state, _hp, plated, attack)
		seen += 1
		local entry = entries[seen]
		if id ~= entry.id or state ~= entry.state or plated ~= entry.plated or attack ~= entry.attack then
			eachOk = false
		end
	end)
	check(eachOk and seen == #entries, "DecodeEach hands plated and attack last")
	-- state byte layout: recover (7) | plated | attack 5
	local one = Codec.Encode({ { id = 1, position = vec(0, 0, 0), yaw = 0, state = "recover", hpFraction = 1, plated = true, attack = 5 } }, vec(0, 0, 0), 0)
	check(buffer.readu8(one, 10 + 9) == 7 + 16 + 5 * 32, "state byte = low nibble state, bit 4 plated, bits 5-7 attack")
	local old = buffer.create(21)
	buffer.writeu8(old, 0, 1)
	buffer.writeu8(old, 1, 1)
	check(#Codec.Decode(old, vec(0, 0, 0)) == 0 and Codec.ReadTime(old) == nil, "a v1 packet is dropped")
end

-- Brain -------------------------------------------------------------------------------------------
local Brain = load("CrowdBrain")
local DT = 1 / 15

-- A minimal copy of CrowdService's use of the brain: seek + Think + the state priority.
local function seek(from: any, goal: any, speed: number, stop: number, dt: number): any
	local dx = goal.X - from.X
	local dz = goal.Z - from.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance <= stop or speed <= 0 then
		return vec(0, 0, 0)
	end
	local travel = math.min(speed, (distance - stop) / dt)
	return vec(dx / distance * travel, 0, dz / distance * travel)
end

type Sim = { now: number, clock: number, bodies: { any }, targets: { any }, strikes: { any } }
local function newSim(): Sim
	return { now = 0, clock = 1000, bodies = {}, targets = {}, strikes = {} }
end
local function spawn(sim: Sim, kind: string, x: number, z: number): any
	local body = {
		id = #sim.bodies + 1,
		hp = 100,
		maxHp = 100,
		plate = 0,
		kind = kind,
		position = vec(x, 0, z),
		mind = Brain.NewMind(sim.now),
		alive = true,
		staggerUntil = 0,
		state = "idle",
	}
	table.insert(sim.bodies, body)
	return body
end
local function stepSim(sim: Sim): ()
	sim.now += DT
	sim.clock += DT
	Brain.BeginStep(sim.now, 0, 196.2, 0, 140)
	for _, target in sim.targets do
		Brain.AddTarget(target.userId, target.position, 3, target.lag or 0)
	end
	for _, body in sim.bodies do
		if body.alive then
			Brain.Commit(body, body.mind)
		end
	end
	for _, body in sim.bodies do
		if not body.alive then
			continue
		end
		local def = config.crowd.kinds[body.kind]
		local free = sim.now >= body.staggerUntil
		local goal, stop = Brain.Think(body, body.mind, def, config.crowd, free)
		if goal ~= nil then
			body.position = body.position + seek(body.position, goal, def.speed, stop, DT) * DT
		end
		body.state = if sim.now < body.staggerUntil then "stagger" else (Brain.StateOf(body.mind) or "idle")
	end
	Brain.DrainStrikes(function(strike)
		table.insert(sim.strikes, strike)
	end)
end
local function hit(sim: Sim, body: any, amount: number): ()
	local def = config.crowd.kinds[body.kind]
	local stagger = config.crowd.staggerSeconds * def.knockbackMult
	body.staggerUntil = math.max(body.staggerUntil, sim.now + stagger)
	Brain.OnHit(body.mind, def, amount, stagger > 0, false, config.crowd.heavyHit, sim.now)
end

print("CrowdBrain: one fodder")
do
	local sim = newSim()
	table.insert(sim.targets, { userId = 7, position = vec(0, 3, 0) })
	local body = spawn(sim, "fodder", 0, 20)
	local windupAt: number? = nil
	local windupClock = 0
	local attackSeenAt: number? = nil
	local recoverSeenAt: number? = nil
	local approachAgainAt: number? = nil
	local earliestWindup = math.huge
	for _ = 1, 15 * 8 do
		stepSim(sim)
		if body.state == "windup" and windupAt == nil then
			windupAt = sim.now
			windupClock = sim.now
			earliestWindup = sim.now
		end
		if windupAt ~= nil and attackSeenAt == nil and body.state == "attack" then
			attackSeenAt = sim.now
		end
		if attackSeenAt ~= nil and recoverSeenAt == nil and body.state == "recover" then
			recoverSeenAt = sim.now
		end
		if recoverSeenAt ~= nil and approachAgainAt == nil and body.state ~= "recover" then
			approachAgainAt = sim.now
		end
	end
	local flat = math.abs(body.position.Z)
	check(near(flat, 4.5, 2e-3), `stops at its reach on the flat ({string.format("%.4f", flat)})`)
	check(windupAt ~= nil and earliestWindup >= 1.0 - 1e-6, "no windup inside spawnGrace")
	check(#sim.strikes >= 1, "an impact was raised")
	local strike = sim.strikes[1]
	check(strike ~= nil and near(strike.at, windupClock + 0.5, 1e-6), "impact time = windup start + windup, exactly")
	check(attackSeenAt ~= nil and near(attackSeenAt :: number, (windupAt :: number) + 8 * DT, 1e-6), "attack shows at the first step at or after the impact (0.5 s = 7.5 steps -> step 8)")
	check(recoverSeenAt ~= nil and near(recoverSeenAt :: number, (windupAt :: number) + 11 * DT, 1e-6), "recover shows at impact + strikeSeconds (0.7 s -> step 11)")
	check(approachAgainAt ~= nil and near(approachAgainAt :: number, (windupAt :: number) + 33 * DT, 1e-6), "recover ends at impact + strikeSeconds + recover (2.2 s = step 33)")
	check(strike ~= nil and near(strike.origin.Y, 2.5) and strike.floorY == 0 and near(strike.facing.Z, -1), "strike: body centre origin, crowd floor, locked facing toward the target")
	check(strike ~= nil and strike.attack == 1 and strike.enemyKind == "fodder", "strike names the kind and the 1-based attack")
end

print("CrowdBrain: a player in the air (ruling 21)")
do
	local sim = newSim()
	sim.now = 5
	table.insert(sim.targets, { userId = 7, position = vec(0, 3 + 18, 0) })
	local fodder = spawn(sim, "fodder", 0, 12)
	fodder.mind.bornAt = 0
	for _ = 1, 30 do
		stepSim(sim)
	end
	check(near(math.abs(fodder.position.Z), 4.5, 2e-3), "it gathers under a player 18 studs up, at its reach on the flat")
	check(#sim.strikes >= 1, "and winds up there: reach is not measured in 3D")
end

print("CrowdBrain: the cap")
do
	local sim = newSim()
	sim.now = 5
	table.insert(sim.targets, { userId = 7, position = vec(0, 3, 0) })
	for index = 1, 16 do
		local angle = index / 16 * 2 * math.pi
		local body = spawn(sim, "fodder", math.cos(angle) * 4, math.sin(angle) * 4)
		body.mind.bornAt = 0
	end
	local most = 0
	local short = 0
	local longestShort = 0
	for stepIndex = 1, 15 * 6 do
		stepSim(sim)
		local busy = 0
		for _, body in sim.bodies do
			if body.mind.phase == "windup" or body.mind.phase == "attack" then
				busy += 1
			end
		end
		most = math.max(most, busy)
		if stepIndex > 2 then
			short = if busy < 4 then short + 1 else 0
			longestShort = math.max(longestShort, short)
		end
	end
	check(most == 4, `at most 4 lunges under way against one player (saw {most})`)
	check(longestShort <= 1, `a freed place is taken in the same step, or the next when the taker is walked first (longest shortfall {longestShort} step)`)
	check(#sim.strikes >= 32, `sixteen keep four places busy ({#sim.strikes} impacts in 6 s; 4 per 0.733 s = 32)`)
end

print("CrowdBrain: interrupts")
do
	local sim = newSim()
	sim.now = 5
	table.insert(sim.targets, { userId = 7, position = vec(0, 3, 0) })
	local fodder = spawn(sim, "fodder", 0, 4)
	fodder.mind.bornAt = 0
	stepSim(sim)
	check(fodder.mind.phase == "windup", "fodder winds up in reach")
	hit(sim, fodder, 1)
	check(fodder.mind.phase == "recover" and fodder.mind.attack == 1, "any staggering hit cancels a `stagger` windup into recover")
	local before = #sim.strikes
	for _ = 1, 15 do
		stepSim(sim)
	end
	check(#sim.strikes == before, "a cancelled windup lands nothing")

	local sim2 = newSim()
	sim2.now = 5
	table.insert(sim2.targets, { userId = 7, position = vec(0, 3, 0) })
	local elite = spawn(sim2, "armoured", 0, 5)
	elite.mind.bornAt = 0
	stepSim(sim2)
	check(elite.mind.phase == "windup", "elite winds up in reach")
	hit(sim2, elite, 39)
	check(elite.mind.phase == "windup", "a 39 does not cancel a `heavy` windup")
	for _ = 1, 13 do
		stepSim(sim2)
	end
	check(#sim2.strikes == 1 and sim2.strikes[1].def.shape == "arc", "the arc still lands, through the stagger")
	for _ = 1, 15 * 2 do
		stepSim(sim2)
	end
	check(elite.mind.phase == "windup", "elite winds up again after recover")
	hit(sim2, elite, 40)
	check(elite.mind.phase == "recover", "a 40 cancels it")
end

print("CrowdBrain: dummies and unknown shapes")
do
	local sim = newSim()
	sim.now = 5
	table.insert(sim.targets, { userId = 7, position = vec(0, 3, 0) })
	local dummy = spawn(sim, "dummy", 0, 10)
	local shooter = spawn(sim, "unarmed", 0, 12)
	for _ = 1, 30 do
		stepSim(sim)
	end
	check(near(dummy.position.Z, 10) and dummy.mind.phase == "approach", "a kind without a brain stands")
	check(near(shooter.position.Z, 12) and shooter.mind.phase == "approach" and #sim.strikes == 0, "a kind with a brain and no attacks stands too")
	sim.targets = {}
	local fodder = spawn(sim, "fodder", 0, 10)
	for _ = 1, 30 do
		stepSim(sim)
	end
	check(near(fodder.position.Z, 10), "with no target (everyone down) a fodder stands")
end

-- Vitals ------------------------------------------------------------------------------------------
print("VitalsService")
local Vitals = load("VitalsService")
-- The real CrowdService (VitalsService required it); only its hook setter is tapped.
local Crowd = load("CrowdService")
local setThreatHooks = Crowd.SetThreatHooks
Crowd.SetThreatHooks = function(hooks)
	threatHooks = hooks
	setThreatHooks(hooks)
end
-- RangeService's i-frame clock, as openIframes keeps it: the latest window and the one before.
local iframes = { from = 0, untilClock = 0, wasFrom = 0, wasUntil = 0 }
local granted: { number } = {}
local function clearIframes(): ()
	iframes.from, iframes.untilClock, iframes.wasFrom, iframes.wasUntil = 0, 0, 0, 0
end
Vitals.Start({
	-- The clock is the first player's; the second (wave 2's bystander) never has i-frames.
	iframeWindow = function(who)
		if who.UserId ~= 7 then
			return 0, 0, 0, 0
		end
		return iframes.from, iframes.untilClock, iframes.wasFrom, iframes.wasUntil
	end,
	grantIframes = function(who, seconds)
		if not (seconds > 0) or who.UserId ~= 7 then
			return
		end
		table.insert(granted, seconds)
		if fakeNow >= iframes.untilClock then
			iframes.wasFrom = iframes.from
			iframes.wasUntil = iframes.untilClock
			iframes.from = fakeNow
		end
		iframes.untilClock = math.max(iframes.untilClock, fakeNow + seconds)
	end,
})
check(threatHooks.flush == nil, "ruling 23: the crowd step no longer flushes the effects")
local regenScript: any = {
	Name = "Health",
	Enabled = true,
	IsA = function(_self, class)
		return class == "Script"
	end,
}
local root: any = {
	Position = vec(0, 3, 0),
	Size = vec(2, 2, 1),
	IsA = function(_self, class)
		return class == "BasePart"
	end,
}
-- A profile body, as Roblox hands it over.
local humanoid: any = { Health = 100, MaxHealth = 100, HipHeight = 2 }
local character: any = {
	Parent = {},
	FindFirstChild = function(_self, name)
		return if name == "HumanoidRootPart" then root else nil
	end,
	FindFirstChildOfClass = function(_self, class)
		return if class == "Humanoid" then humanoid else nil
	end,
	GetChildren = function()
		return { regenScript }
	end,
	ChildAdded = {
		Connect = function(_self, _fn)
			return { Disconnect = function() end }
		end,
	},
}
local player: any = {
	UserId = 7,
	Character = character,
	Parent = {},
	GetNetworkPing = function()
		return 0.05
	end,
}
vitalsBeat = beats[#beats]
table.insert(players, player)
table.insert(players, { UserId = 8, Parent = {} })
Vitals.AddPlayer(player)
Vitals.PrepareCharacter(player, character)
check(regenScript.Enabled == false, "Roblox's Health script is disabled")
check(humanoid.MaxHealth == 130 and humanoid.Health == 130, "ruling 17: the body is the tier-1 body (130 from the real Armory.json), whatever it came with")
local hooks = threatHooks
local function lunge(at: number, from: any?, facing: any?): any
	return { at = at, enemyKind = "fodder", attack = 1, def = fodderAttack, targetUserId = 7, origin = from or vec(0, 2.5, 4), floorY = 0, facing = facing or vec(0, 0, -1) }
end
local function arc(at: number, aimedAt: number?): any
	return { at = at, enemyKind = "armoured", attack = 1, def = arcAttack, targetUserId = aimedAt or 7, origin = vec(0, 3.25, 5), floorY = 0, facing = vec(0, 0, -1) }
end
local function advance(seconds: number): ()
	local frames = math.floor(seconds * 60 + 0.5)
	for _ = 1, frames do
		fakeNow += 1 / 60
		vitalsBeat(1 / 60)
	end
end
-- The hurt effects sent to the first player since the last drain, and in how many remote calls.
local function drain(): ({ any }, number)
	local out = {}
	local calls = 0
	for _, call in fired do
		if call.player == player and call.name == "CombatFx" then
			calls += 1
			for _, fx in call.payload do
				table.insert(out, fx)
			end
		end
	end
	table.clear(fired)
	return out, calls
end

do
	-- lag = ping 0.05 + 0.05 = 0.1
	hooks.impact(lunge(fakeNow))
	advance(0.08)
	check(humanoid.Health == 130, "nothing is decided before T + lag")
	advance(0.04)
	check(humanoid.Health == 122, "the lunge lands at T + lag: 130 -> 122")
	local sentTo = #fired
	local batch, calls = drain()
	check(calls == 1 and sentTo == 2, "ruling 23: the hurt left in the frame that decided it, one call per player, no crowd step run")
	local fx = batch[1]
	check(#batch == 1 and fx.kind == "hurt" and fx.userId == 7 and fx.amount == 8 and fx.attack == 1 and fx.enemyKind == "fodder", "hurt carries victim, amount, kind, attack")
	check(fx.push == nil and fx.launch == nil and fx.dodged == nil and fx.down == nil, "a fodder hit moves nobody")
	advance(0.1)
	check(#fired == 0, "frames that decide nothing send nothing")

	-- Moved out during the lag: the root at T + lag decides.
	hooks.impact(lunge(fakeNow))
	root.Position = vec(4, 3, 0)
	advance(0.15)
	check(humanoid.Health == 122 and #drain() == 0, "out of the capsule at T + lag: a silent miss")
	root.Position = vec(0, 3, 0)

	-- The capsule's tip ends `range` from the body centre: 5 studs, not 6.5.
	hooks.impact(lunge(fakeNow, vec(0, 2.5, 5.2)))
	advance(0.15)
	check(humanoid.Health == 122, "5.2 studs along the thrust is out of a 5-stud lunge")
	hooks.impact(lunge(fakeNow, vec(0, 2.5, 4.9)))
	advance(0.15)
	check(humanoid.Health == 114, "4.9 studs along it is in")
	drain()

	-- A jump: feet above the shape's height.
	root.Position = vec(0, 3 + 5.1, 0)
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	check(humanoid.Health == 114 and #drain() == 0, "feet 5.1 above the floor clear a height-5 lunge")
	root.Position = vec(0, 3, 0)

	-- A dash that covered the impact but is over by the decision.
	iframes.from = fakeNow - 0.2
	iframes.untilClock = fakeNow + 0.02
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	local dodge = drain()
	check(humanoid.Health == 114 and #dodge == 1 and dodge[1].dodged == true and dodge[1].amount == 0, "an i-frame over the impact voids it: dodged, amount 0")
	-- A dash that began inside the lag.
	hooks.impact(lunge(fakeNow))
	advance(0.05)
	iframes.from = fakeNow
	iframes.untilClock = fakeNow + 0.25
	advance(0.1)
	dodge = drain()
	check(humanoid.Health == 114 and #dodge == 1 and dodge[1].dodged == true, "a dash begun inside [T, T + lag] voids it too")
	-- A window that ended before the impact does not.
	advance(0.5)
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	check(humanoid.Health == 106, "a window that lapsed before the impact voids nothing")
	drain()

	-- Ruling 24b: the dash covered the impact, lapsed, and a later window replaced it before the
	-- strike was even raised.
	clearIframes()
	local replaced = fakeNow
	iframes.wasFrom = replaced - 0.2
	iframes.wasUntil = replaced + 0.01
	iframes.from = replaced + 0.12
	iframes.untilClock = replaced + 0.5
	fakeNow = replaced + 0.13
	hooks.impact(lunge(replaced))
	advance(0.05)
	local kept = drain()
	check(humanoid.Health == 106 and #kept == 1 and kept[1].dodged == true, "ruling 24b: the window before the current one still voids the hit it covered")
	clearIframes()
	advance(1)

	-- Ruling 26: a dash carries the player out of the shape, and still reads as a dodge.
	local dashed = fakeNow
	iframes.from = dashed - 0.05
	iframes.untilClock = dashed + 0.2
	hooks.impact(lunge(dashed))
	root.Position = vec(14, 3, 0)
	advance(0.15)
	local out, outCalls = drain()
	check(humanoid.Health == 106 and #out == 1 and outCalls == 1, "ruling 26: a dash out of a lunge aimed at you sends one effect")
	check(out[1] ~= nil and out[1].dodged == true and out[1].amount == 0 and out[1].push == nil and out[1].launch == nil and near(out[1].from.Z, 4), "it is `dodged`: amount 0, no push or launch, from the attacker")
	clearIframes()
	advance(1)
	-- Walking out is not a dodge.
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	check(humanoid.Health == 106 and #drain() == 0, "ruling 26: walking out of it, with no i-frame, sends nothing")
	-- Jumping over it under an i-frame is one.
	root.Position = vec(0, 3 + 5.1, 0)
	iframes.from = fakeNow - 0.05
	iframes.untilClock = fakeNow + 0.2
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	local over = drain()
	check(humanoid.Health == 106 and #over == 1 and over[1].dodged == true, "ruling 26: clearing it in the air under an i-frame is a dodge too")
	-- A bystander an arc aimed at someone else did not reach dodged nothing.
	root.Position = vec(14, 3, 0)
	iframes.from = fakeNow - 0.05
	iframes.untilClock = fakeNow + 0.2
	hooks.impact(arc(fakeNow, 8))
	advance(0.15)
	check(humanoid.Health == 106 and #drain() == 0, "ruling 26: a bystander missed by an arc aimed at someone else gets nothing, i-frame or not")
	-- But the same arc still catches a bystander who stands in it.
	root.Position = vec(0, 3, 0)
	clearIframes()
	advance(1)
	hooks.impact(arc(fakeNow, 8))
	advance(0.15)
	local caught = drain()
	check(humanoid.Health == 76 and #caught == 1 and caught[1].dodged == nil, "an arc aimed at someone else still hits a bystander inside it (106 -> 76)")
	humanoid.Health = 106
	advance(1)
	clearIframes()

	-- god
	Vitals.ToggleGod(player)
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	local godFx = drain()
	local _taken, _downs, god = Vitals.Readout(player)
	check(humanoid.Health == 106 and god == true and #godFx == 1 and godFx[1].dodged == true, "god voids the hit and still sends it as dodged")
	Vitals.ToggleGod(player)

	-- The elite's arc: push away from the attacker, launch, knock i-frames.
	table.clear(granted)
	hooks.impact(arc(fakeNow))
	advance(0.15)
	local knock = drain()
	check(humanoid.Health == 76 and #knock == 1 and knock[1].launch == 6, "the arc lands: 106 -> 76, launch 6")
	check(knock[1].push ~= nil and near(knock[1].push.Z, -30) and near(knock[1].push.X, 0) and knock[1].push.Y == 0, "push = away from the attacker x knockback, flat")
	check(#granted == 1 and granted[1] == 0.4, "knockIframes granted")
	-- Outside the 120 degree wedge.
	advance(1)
	root.Position = vec(6, 3, 5 - 1)
	hooks.impact(arc(fakeNow))
	advance(0.15)
	check(humanoid.Health == 76, "beside the elite, outside the 120 degree arc: missed")
	root.Position = vec(0, 3, 0)

	-- Regen after regenDelay unhurt.
	advance(2.5)
	check(humanoid.Health == 76, "no regen inside regenDelay")
	advance(1.5)
	check(humanoid.Health > 76 and humanoid.Health < 100, `regen runs after 4 s unhurt (now {string.format("%.1f", humanoid.Health)})`)

	-- Ruling 18: hits decided together do not stack through a knock.
	config.player.regenPerSecond = 0
	humanoid.Health = 130
	clearIframes()
	drain()
	local together = fakeNow
	hooks.impact(arc(together))
	hooks.impact(arc(together))
	hooks.impact(lunge(together))
	advance(0.15)
	local stack, stackCalls = drain()
	check(humanoid.Health == 100, "ruling 18: three hits with one impact time, the first a knock: only it lands (130 -> 100)")
	check(#stack == 3 and stack[1].dodged == nil and stack[2].dodged == true and stack[3].dodged == true, "the other two are sent as dodged")
	check(stackCalls == 1, "ruling 23: all three in one batch, one call")
	-- The second gap: an impact noticed late, whose own T + lag came before the knock was decided.
	advance(1)
	clearIframes()
	local first = fakeNow
	hooks.impact(arc(first))
	advance(0.15)
	check(humanoid.Health == 70, "a knock lands (100 -> 70)")
	hooks.impact(arc(first - 0.02))
	advance(0.05)
	local gap = drain()
	check(humanoid.Health == 70 and #gap == 2 and gap[2].dodged == true, "ruling 18: an impact raised after that knock but due before it is voided by the knock's window")
	-- With no knock window at all, the hits waiting at the knock are still voided.
	advance(1)
	clearIframes()
	config.player.knockIframes = 0
	local bare = fakeNow
	hooks.impact(arc(bare))
	hooks.impact(arc(bare))
	advance(0.15)
	check(humanoid.Health == 40, "ruling 18: even at knockIframes 0, two knocks decided together land once (70 -> 40)")
	config.player.knockIframes = 0.4
	-- And once the window is over the next knock lands as ever.
	advance(1)
	humanoid.Health = 130
	hooks.impact(arc(fakeNow))
	advance(0.15)
	check(humanoid.Health == 100, "after the window a knock lands again")
	config.player.regenPerSecond = 10
	advance(1)
	drain()
	Vitals.OnSetLoaded()

	-- Down and up.
	humanoid.Health = 20
	table.clear(granted)
	hooks.impact(arc(fakeNow))
	advance(0.15)
	local down = drain()
	local taken, downs = Vitals.Readout(player)
	check(humanoid.Health == 1 and Vitals.IsDown(player), "the hit that would empty the bar puts the player down at 1 HP")
	check(#down == 1 and down[1].down == true and near(down[1].upAt, fakeNow + SERVER_OFFSET + 2, 0.06), "hurt.down with upAt = server time + downSeconds")
	check(downs == 1 and taken == 30, `the readout counts the downing hit in full ({taken}) and the down`)
	check(#granted == 0, "no knock i-frames for the downing hit")
	check(hooks.canTarget(player) == false, "enemies stop targeting a downed player")
	local downAt = fakeNow
	local upClock = down[1].upAt - SERVER_OFFSET
	hooks.impact(lunge(fakeNow))
	advance(0.5)
	check(humanoid.Health == 1 and #drain() == 0, "a downed player takes no further hits")
	advance(1.5)
	check(humanoid.Health == 130 and not Vitals.IsDown(player), "up after downSeconds at full health")
	check(#granted == 1 and hooks.canTarget(player), "getUpIframes granted; targetable again")
	check(near(iframes.untilClock, upClock + 1.5, 1e-9), "the get-up window ends exactly getUpIframes after upAt")
	check(downAt < upClock, "(the down was timed from its decision)")

	-- Ruling 24a: an impact that fell while they were down, raised only after the get-up.
	hooks.impact(arc(upClock - 0.15))
	advance(0.1)
	local ghost = drain()
	check(humanoid.Health == 130 and #ghost == 0, "ruling 24a: a player who was down at the impact's time is skipped, though up when it is raised")
	-- Ruling 26 does not change that: aimed at them, missed, the get-up window open, still nothing.
	root.Position = vec(14, 3, 0)
	hooks.impact(lunge(upClock - 0.15))
	advance(0.1)
	check(#drain() == 0, "ruling 26: down at the impact's time, an aimed miss under the get-up window sends nothing")
	-- While one that fell after the get-up, and missed, is their dodge.
	hooks.impact(lunge(upClock + 0.02))
	advance(0.1)
	local upDodge = drain()
	check(#upDodge == 1 and upDodge[1].dodged == true, "ruling 26: a miss aimed at a player inside their get-up window reads as a dodge")
	root.Position = vec(0, 3, 0)
	hooks.impact(arc(upClock + 0.01))
	advance(0.1)
	local risen = drain()
	check(humanoid.Health == 130 and #risen == 1 and risen[1].dodged == true, "an impact after the get-up is judged, and dodged by the get-up window")

	Vitals.OnSetLoaded()
	local resetTaken, resetDowns = Vitals.Readout(player)
	check(resetTaken == 0 and resetDowns == 0, "a set load resets damage taken and downs")

	-- Down ends on the clock, not on the frame that stands the player up.
	advance(2)
	humanoid.Health = 5
	hooks.impact(lunge(fakeNow))
	advance(0.15)
	check(Vitals.IsDown(player) and humanoid.Health == 1, "down again")
	local again = drain()
	fakeNow = again[1].upAt - SERVER_OFFSET - 0.001
	check(Vitals.IsDown(player), "still down a millisecond before upAt")
	fakeNow = again[1].upAt - SERVER_OFFSET + 0.001
	check(not Vitals.IsDown(player) and humanoid.Health == 1, "not down a millisecond after upAt, before the frame that restores health")
	check(hooks.canTarget(player) == false, "but still no target and no hits until that frame")
	vitalsBeat(1 / 60)
	check(humanoid.Health == 130 and hooks.canTarget(player), "that frame stands them up")
	advance(2)
	drain()
end

-- The real crowd step ---------------------------------------------------------------------------
print("CrowdService + CrowdBrain + VitalsService together")
do
	local Codec = load("CrowdCodec")
	clearIframes()
	humanoid.Health = 130
	root.Position = vec(0, 3, 0)
	config.player.regenPerSecond = 0
	Crowd.SetBounds(vec(0, 0, 0), vec(100, 50, 100))
	crowdBeat = beats[#beats]
	local function crowdStep(count: number?): ()
		for _ = 1, count or 1 do
			fakeNow += DT
			crowdBeat(DT)
			vitalsBeat(DT)
		end
	end
	local function shown(id: number): any
		for _, entry in Codec.Decode(lastSnapshot, vec(0, 0, 0)) do
			if entry.id == id then
				return entry
			end
		end
		return { state = "gone", attack = -1 }
	end
	local function untilState(id: number, state: string, limit: number): boolean
		for _ = 1, limit do
			crowdStep()
			if shown(id).state == state then
				return true
			end
		end
		return false
	end
	local function overlaid(entry: any): boolean
		return entry.state == "airborne" or entry.state == "stagger"
	end

	local landed: { any } = {}
	local impactHook = threatHooks.impact
	threatHooks.impact = function(strike)
		table.insert(landed, strike)
		impactHook(strike)
	end

	print(" the stamp of a windup's first snapshot")
	local timed = Crowd.Spawn("armoured", vec(0, 0, 5), "fight")
	check(untilState(timed, "windup", 40), "an elite winds up")
	local stamp = Codec.ReadTime(lastSnapshot)
	check(untilState(timed, "recover", 30) and #landed == 1, "its arc lands once")
	check(near(landed[1].at + SERVER_OFFSET, stamp + 0.8, 1e-9), "impact = the stamp of the first snapshot that shows the windup + windup, exactly")
	check(landed[1].targetUserId == 7, "ruling 26: the strike names the player its windup was started against")
	Crowd.Clear()
	crowdStep()
	table.clear(landed)
	local hitched = Crowd.Spawn("armoured", vec(0, 0, 20), "fight")
	local arrived = false
	for _ = 1, 60 do
		crowdStep()
		if Crowd.Get(hitched).position.Z <= 6.001 then
			arrived = true
			break
		end
	end
	check(arrived and shown(hitched).state ~= "windup", "it has just walked into reach, its grace long over")
	-- One frame that runs three catch-up steps: the windup starts in the first of them.
	fakeNow += 3 * DT
	crowdBeat(3 * DT)
	vitalsBeat(3 * DT)
	check(shown(hitched).state == "windup", "a hitch frame: the windup starts in a catch-up step")
	local hitchStamp = Codec.ReadTime(lastSnapshot)
	check(untilState(hitched, "recover", 30) and #landed == 1, "its arc lands once")
	check(near(landed[1].at + SERVER_OFFSET, hitchStamp + 0.8, 1e-9), "and still exactly its first stamp + windup")
	Crowd.Clear()
	crowdStep()
	humanoid.Health = 130
	clearIframes()

	print(" a due impact is never lost (ruling 22)")
	-- A fodder's windup is 0.5 s here: 7.5 steps. After 7 its impact is 33 ms away.
	local function dueFodder(): (number, number)
		Crowd.Clear()
		crowdStep(8)
		table.clear(landed)
		clearIframes()
		humanoid.Health = 130
		local id = Crowd.Spawn("fodder", vec(0, 0, 4), "fight")
		assert(untilState(id, "windup", 40), "fodder never wound up")
		local impactAt = Codec.ReadTime(lastSnapshot) - SERVER_OFFSET + 0.5
		crowdStep(7)
		assert(shown(id).state == "windup" and #landed == 0, "not one step short of the impact")
		return id, impactAt
	end
	local early = dueFodder()
	Crowd.Damage(early, 1, 7, nil, nil)
	crowdStep(6)
	check(#landed == 0 and humanoid.Health == 130, "a hit before the impact time cancels the lunge, as ever")
	local hitDue, hitAt = dueFodder()
	fakeNow = hitAt + 0.001
	Crowd.Damage(hitDue, 1, 7, nil, nil)
	crowdStep(4)
	check(#landed == 1 and near(landed[1].at, hitAt, 1e-9), "a hit after the impact time, before the step that notices it: the impact is still raised, at its own time")
	check(humanoid.Health == 122, "and it lands on the player")
	local killEarly = dueFodder()
	Crowd.Damage(killEarly, 100000, 7, nil, nil)
	crowdStep(6)
	check(#landed == 0 and humanoid.Health == 130, "a kill before the impact time cancels it")
	local killDue, killAt = dueFodder()
	fakeNow = killAt + 0.001
	Crowd.Damage(killDue, 100000, 7, nil, nil)
	check(shown(killDue).state == "windup", "(killed between two steps)")
	crowdStep(4)
	check(shown(killDue).state == "dead" and #landed == 1 and near(landed[1].at, killAt, 1e-9), "a kill after the impact time: the dead body's impact is still raised")
	check(humanoid.Health == 122, "and it lands on the player")
	Crowd.Clear()
	crowdStep(8)
	table.clear(landed)
	humanoid.Health = 130
	clearIframes()

	print(" the attack index under an overlay")
	local elite = Crowd.Spawn("armoured", vec(0, 0, 5), "fight")
	check(untilState(elite, "windup", 40) and shown(elite).attack == 1, "elite: windup on the wire with attack index 1")
	crowdStep(2)
	local healthBefore = humanoid.Health
	Crowd.Damage(elite, 24, 7, vec(0, 0, 16), 4)
	crowdStep()
	local light = shown(elite)
	check(overlaid(light) and light.attack == 1, `a light hit: {light.state} with the index still set (windup runs on underneath)`)
	local everySet = true
	local overlays = 1
	for _ = 1, 30 do
		crowdStep()
		local entry = shown(elite)
		if entry.state == "recover" then
			break
		end
		if overlaid(entry) then
			overlays += 1
			everySet = everySet and entry.attack == 1
		end
	end
	check(everySet and overlays >= 2, `the index is set in every overlay snapshot until the blow ({overlays} of them)`)
	check(humanoid.Health == healthBefore - 30, "and the arc lands on time")

	check(untilState(elite, "windup", 60), "elite winds up again")
	crowdStep(2)
	Crowd.Damage(elite, 40, 7, vec(0, 0, 16), 4)
	crowdStep()
	local heavy = shown(elite)
	check(overlaid(heavy) and heavy.attack == 0, `a heavy hit: {heavy.state} with index 0 (cancelled)`)
	local allZero = true
	local sawRecover = false
	for _ = 1, 20 do
		crowdStep()
		local entry = shown(elite)
		if entry.state == "recover" then
			sawRecover = true
			break
		end
		allZero = allZero and (not overlaid(entry) or entry.attack == 0)
	end
	check(allZero and sawRecover and shown(elite).attack == 1, "index 0 under the whole overlay, then recover with the index set")
	check(humanoid.Health == healthBefore - 30, "the cancelled arc lands nothing")

	check(untilState(elite, "windup", 60), "elite winds up a third time")
	Crowd.Damage(elite, 100000, 7, nil, nil)
	crowdStep()
	local dead = shown(elite)
	check(dead.state == "dead" and dead.attack == 0, "dead with a windup underneath: index 0")

	local fodder = Crowd.Spawn("fodder", vec(0, 0, -4), "fight")
	check(untilState(fodder, "windup", 40) and shown(fodder).attack == 1, "fodder: windup with index 1")
	Crowd.Damage(fodder, 1, 7, nil, nil)
	crowdStep()
	local cut = shown(fodder)
	check(cut.state == "stagger" and cut.attack == 0, "fodder cancelled by any hit: stagger with index 0")
	check(untilState(fodder, "recover", 10) and shown(fodder).attack == 1, "then recover with the index set")

	print(" planted bodies")
	Crowd.Clear()
	crowdStep()
	humanoid.Health = 130
	local p1 = Crowd.Spawn("fodder", vec(30, 0, 30), "idle")
	local p2 = Crowd.Spawn("fodder", vec(31, 0, 30), "idle")
	crowdStep()
	check(near(Crowd.Get(p1).position.X, 29.2, 1e-9) and near(Crowd.Get(p2).position.X, 31.8, 1e-9), "a passive pair still splits its overlap evenly")

	-- An idle body with a lower id whose home is the lunger's spot: it keeps walking into it.
	local presser = Crowd.Spawn("fodder", vec(6, 0, 4.2), "idle", vec(0, 0, 4.2))
	local lunger = Crowd.Spawn("fodder", vec(0, 0, 4.2), "fight")
	crowdStep(13)
	check(Crowd.Get(lunger).position.X < -0.1, `before its windup the body is shoved like any other (x {string.format("%.2f", Crowd.Get(lunger).position.X)})`)
	check(untilState(lunger, "windup", 20), "it winds up")
	local planted = Crowd.Get(lunger).position
	-- And one with a higher id, dropped half on top of it from the other side.
	local late = Crowd.Spawn("fodder", vec(planted.X - 1, 0, planted.Z), "idle")
	local moved = false
	for _ = 1, 6 do
		crowdStep()
		local now = Crowd.Get(lunger).position
		moved = moved or now.X ~= planted.X or now.Z ~= planted.Z
	end
	local pressed = Crowd.Get(presser).position
	check(not moved, "planted: six steps of a neighbour walking into it move it not at all")
	check(near((pressed - planted).Magnitude, 2.6, 1e-9), "the neighbour takes the whole overlap")
	check(near((Crowd.Get(late).position - planted).Magnitude, 2.6, 1e-9), "so does one with a higher id")
	check(untilState(lunger, "recover", 12), "the thrust ends")
	check(humanoid.Health == 122, "the lunge it locked at the windup's start lands on the player who never moved")
	crowdStep(3)
	local loose = (Crowd.Get(lunger).position - planted).Magnitude
	check(loose > 0.05, `in recover its neighbours shove it again ({string.format("%.2f", loose)} studs in 3 steps)`)

	Crowd.Clear()
	crowdStep()
	local left = Crowd.Spawn("armoured", vec(0, 0, 5.5), "fight")
	local right = Crowd.Spawn("armoured", vec(0, 0, -5.5), "fight")
	check(untilState(left, "windup", 40) and shown(right).state == "windup", "two elites wind up together")
	local leftAt = Crowd.Get(left).position
	local rightAt = Crowd.Get(right).position
	Crowd.Damage(left, 24, 7, vec(0, 0, -400), 0)
	crowdStep()
	local through = Crowd.Get(left).position
	local held = Crowd.Get(right).position
	check(through.Z < leftAt.Z - 5, `a player's shove still moves a planted body (z {string.format("%.1f", leftAt.Z)} -> {string.format("%.1f", through.Z)})`)
	check(math.abs(through.Z - held.Z) < 3.4, "it now overlaps the other planted body")
	check(held.X == rightAt.X and held.Z == rightAt.Z, "two planted bodies leave each other where they are")
	check(shown(left).attack == 1 and overlaid(shown(left)), "and the shoved one keeps its index under the stagger")
end

