-- Scratch tests for wave 2 (never shipped): appended to tests.luau by run_harness.py, so every
-- local of that file is in scope here. Each group runs in its own function (the 200-local limit).

config.crowd.plateBreakSeconds = 1.0
config.crowd.kinds.slinger = {
	radius = 1.2, headRadius = 0.65, height = 5, speed = 11, hp = 50, armor = 0, knockbackMult = 1.0,
	brain = "keepAway", bandMin = 18, bandMax = 30,
	attacks = { { shape = "shot", reach = 32, windup = 0.6, recover = 2.2, damage = 12, speed = 28, radius = 1.0, seconds = 2.5, lead = 0.7, interrupt = "stagger" } },
}
config.crowd.kinds.marksman = {
	radius = 1.2, headRadius = 0.65, height = 5.4, speed = 10, hp = 45, armor = 0, knockbackMult = 1.0,
	brain = "keepAway", bandMin = 28, bandMax = 45,
	-- `height` is on this line only so the harness can prove it is ignored.
	attacks = { { shape = "line", reach = 48, windup = 1.0, lockSeconds = 0.25, recover = 3.0, damage = 22, range = 60, width = 1.6, height = 5, interrupt = "stagger" } },
}
config.crowd.kinds.lobber = {
	radius = 1.4, headRadius = 0.7, height = 5, speed = 9, hp = 60, armor = 0, knockbackMult = 0.8,
	brain = "keepAway", bandMin = 22, bandMax = 40,
	attacks = { { shape = "lob", reach = 42, windup = 0.5, recover = 3.0, damage = 18, knockback = 14, launch = 3, radius = 5, seconds = 1.4, height = 4, interrupt = "stagger" } },
}
config.crowd.kinds.brute = {
	radius = 2.2, headRadius = 0.9, height = 7.5, speed = 10, hp = 320, armor = 0, knockbackMult = 0.35,
	brain = "rush",
	attacks = { { shape = "lane", reach = 22, windup = 0.8, recover = 1.5, damage = 28, knockback = 40, launch = 3, range = 30, width = 5, speed = 55, height = 5, interrupt = "heavy" } },
}
config.crowd.kinds.runner = {
	radius = 2.2, headRadius = 0.9, height = 7.5, speed = 10, hp = 320, armor = 0, knockbackMult = 1.0,
	brain = "rush", attacks = config.crowd.kinds.brute.attacks,
}
config.crowd.kinds.plated = { radius = 1.7, headRadius = 0.8, height = 6.5, speed = 9, hp = 160, armor = 5, knockbackMult = 0.35, plate = 90 }
config.crowd.kinds.platedFodder = {
	radius = 1.3, headRadius = 0.7, height = 5, speed = 12, hp = 40, armor = 0, knockbackMult = 1.0, plate = 90,
	brain = "rush", attacks = { fodderAttack },
}

local Codec2 = load("CrowdCodec")
local Field = load("ThreatField")
local ORIGIN = vec(0, 0, 0)
local LAG = 0.1 -- the stub players' ping 0.05 + originLagSeconds 0.05
local PASSES = 6 -- CrowdBrain.AIM_PASSES: how often a shot's aim is refined

-- Every strike the crowd raises from here on, as the brain handed it over.
local struck: { any } = {}
do
	local inner = threatHooks.impact
	threatHooks.impact = function(strike)
		table.insert(struck, strike)
		inner(strike)
	end
end
local kills = 0
Crowd.OnKilled(function()
	kills += 1
end)

-- A second player with a body, for bystanders and "the first on its path".
local root2: any = {
	Position = vec(0, 3, 0),
	Size = vec(2, 2, 1),
	IsA = function(_self, class)
		return class == "BasePart"
	end,
}
local humanoid2: any = { Health = 130, MaxHealth = 130, HipHeight = 2 }
local character2: any = {
	Parent = {},
	FindFirstChild = function(_self, name)
		return if name == "HumanoidRootPart" then root2 else nil
	end,
	FindFirstChildOfClass = function(_self, class)
		return if class == "Humanoid" then humanoid2 else nil
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
local player2: any = players[2]
player2.GetNetworkPing = function()
	return 0.05
end
local function join2(position: any): ()
	root2.Position = position
	humanoid2.Health = 130
	player2.Character = character2
	Vitals.AddPlayer(player2)
	Vitals.PrepareCharacter(player2, character2)
end
local function leave2(): ()
	Vitals.RemovePlayer(player2)
	player2.Character = nil
end

-- Everything sent to the first player (and, apart, the second) since the log was cleared.
local log: { any } = {}
local log2: { any } = {}
local risen: { any } = {}
local ended: { number } = {}
local function gather(): ()
	for _, call in fired do
		if call.player == player and call.name == "CrowdSpawn" then
			for _, info in call.payload do
				table.insert(risen, info)
			end
		elseif call.player == player and call.name == "CrowdRemove" then
			for _, id in call.payload do
				table.insert(ended, id)
			end
		end
		if call.name == "CombatFx" then
			local into = if call.player == player then log elseif call.player == player2 then log2 else nil
			if into ~= nil then
				for _, fx in call.payload do
					table.insert(into, fx)
				end
			end
		end
	end
	table.clear(fired)
end
-- A loop that waits on a snapshot that never comes must fail, not hang.
local watchdog = 0
local function step2(count: number?): ()
	for _ = 1, count or 1 do
		watchdog += 1
		if watchdog > 40000 then
			error("harness watchdog: a test loop does not end")
		end
		fakeNow += DT
		crowdBeat(DT)
		vitalsBeat(DT)
		gather()
	end
end
local function seen(id: number): any
	for _, entry in Codec2.Decode(lastSnapshot, ORIGIN) do
		if entry.id == id then
			return entry
		end
	end
	return { state = "gone", attack = -1, position = ORIGIN, yaw = 0, hpFraction = -1, plated = false }
end
local function stamp(): number
	return Codec2.ReadTime(lastSnapshot) - SERVER_OFFSET
end
local function waitFor(id: number, state: string, limit: number): boolean
	for _ = 1, limit do
		step2()
		if seen(id).state == state then
			return true
		end
	end
	return false
end
local function of(list: { any }, kind: string): { any }
	local out = {}
	for _, fx in list do
		if fx.kind == kind then
			table.insert(out, fx)
		end
	end
	return out
end
-- Steps until an effect of `kind` has reached the first player; returns it.
local function waitFx(kind: string, limit: number): any
	for _ = 1, limit do
		step2()
		local found = of(log, kind)
		if found[1] ~= nil then
			return found[1]
		end
	end
	return nil
end
local function fresh(): ()
	Crowd.Clear()
	Vitals.OnSetLoaded()
	step2(2)
	table.clear(walls)
	table.clear(blocks)
	clearIframes()
	humanoid.Health = 130
	root.Position = vec(0, 3, 0)
	config.player.regenPerSecond = 0
	advance(1)
	gather()
	table.clear(struck)
	table.clear(log)
	table.clear(log2)
	table.clear(risen)
	table.clear(ended)
	rays = 0
	kills = 0
end
local function flatTo(a: any, b: any): number
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end
local function kill(id: number): ()
	Crowd.Damage(id, 100000, 7, nil, nil)
end

print("Wave 2")

local function plateTests(): ()
	print(" the plate")
	fresh()
	root.Position = vec(0, 3, -90)
	local id = Crowd.Spawn("plated", vec(0, 0, 20), "idle")
	step2()
	local entry = seen(id)
	check(entry.plated == true and near(entry.hpFraction, 1, 1 / 255), "a kind with a plate spawns plated, in a passive set too: the bit is set and the bar is the plate's, full")
	local dealt, killed, verdict = Crowd.Damage(id, 39, 7, vec(0, 0, 100), 10)
	step2()
	entry = seen(id)
	local place = Crowd.Get(id).position
	check(dealt == 0 and killed == false and verdict == "blocked" and kills == 0, "a hit under heavyHit is blocked: dealt 0, no kill")
	check(entry.state == "idle" and near(place.Z, 20) and place.Y == 0 and near(entry.hpFraction, 1, 1 / 255), "and does nothing at all: no push, no launch, no stagger, the plate untouched")
	dealt, killed, verdict = Crowd.Damage(id, 50, 7, vec(0, 0, 100), 0)
	step2()
	entry = seen(id)
	check(dealt == 50 and verdict == "plate" and Crowd.Get(id).hp == 160, "a heavy hit takes its amount off the plate, never off HP")
	check(entry.plated and near(entry.hpFraction, 40 / 90, 1 / 255), "the bar shows what is left of the plate (40 of 90)")
	check(entry.state == "stagger" and Crowd.Get(id).position.Z > 20.5, "and otherwise it acts as any hit: it shoves and staggers")
	step2(4)
	dealt, killed, verdict = Crowd.Damage(id, 60, 7, nil, nil)
	check(dealt == 60 and verdict == "broke" and killed == false and Crowd.Get(id).hp == 160, "the hit that empties it breaks it: the excess is lost, HP untouched")
	local reeling = 0
	local clearAtOnce = false
	for index = 1, 20 do
		step2()
		local now = seen(id)
		if index == 1 then
			clearAtOnce = now.plated == false and near(now.hpFraction, 1, 1 / 255)
		end
		if now.state == "stagger" then
			reeling += 1
		end
	end
	check(reeling >= 14 and reeling <= 15, `it reels, staggered, for plateBreakSeconds ({reeling} steps of 15)`)
	check(clearAtOnce, "from the break on the bit is clear and the bar is HP again")
	dealt, killed, verdict = Crowd.Damage(id, 20, 7, nil, nil)
	check(dealt == 15 and verdict == nil, "after that the kind's armor applies (20 - 5)")
	Crowd.Remove(id)
	local again = Crowd.Spawn("plated", vec(0, 0, 20), "idle")
	step2()
	check(seen(again).plated == true and near(seen(again).hpFraction, 1, 1 / 255), "a respawned one is plated again")

	fresh()
	local fighter = Crowd.Spawn("platedFodder", vec(0, 0, 4), "fight")
	check(waitFor(fighter, "windup", 40), "a plated fighter winds up")
	local _, _, blocked = Crowd.Damage(fighter, 39, 7, vec(0, 0, 60), 6)
	step2()
	check(blocked == "blocked" and seen(fighter).state == "windup" and seen(fighter).attack == 1, "a blocked hit does not interrupt, stagger or move a windup")
	waitFor(fighter, "recover", 20)
	step2(3)
	check(humanoid.Health == 122, "and its lunge lands")
	check(waitFor(fighter, "windup", 60), "it winds up again")
	local _, _, heavy = Crowd.Damage(fighter, 45, 7, nil, nil)
	step2()
	check(heavy == "plate" and seen(fighter).state == "stagger" and seen(fighter).attack == 0, "a heavy hit on the plate interrupts like any hit")
end
plateTests()

local function keepAwayTests(): ()
	print(" the keepAway brain")
	fresh()
	local far = Crowd.Spawn("slinger", vec(0, 0, 60), "fight")
	local firedFrom: number? = nil
	for _ = 1, 15 * 6 do
		step2()
		if firedFrom == nil and #struck > 0 then
			firedFrom = flatTo(Crowd.Get(far).position, root.Position)
		end
	end
	check(firedFrom ~= nil and (firedFrom :: number) <= 32.01 and (firedFrom :: number) > 30, `it walks in and attacks as soon as its reach covers the target (fired from {string.format("%.2f", firedFrom or -1)})`)
	check(flatTo(Crowd.Get(far).position, root.Position) <= 30.01, "then goes on to its band's far edge while it recovers")

	fresh()
	local close = Crowd.Spawn("slinger", vec(0, 0, 8), "fight")
	step2(6)
	check(Crowd.Get(close).position.Z > 11, "it backs off when the target is inside its band")
	check(math.abs(seen(close).yaw) < 0.05, "and keeps facing the target as it goes")
	step2(12)
	check(near(flatTo(Crowd.Get(close).position, root.Position), 18, 0.02), "as far as bandMin, no further")
	local held = Crowd.Get(close).position
	check(seen(close).state == "windup", "then winds up")
	local presser = Crowd.Spawn("fodder", vec(held.X + 1, 0, held.Z), "idle")
	step2(3)
	check(Crowd.Get(close).position.X == held.X and Crowd.Get(close).position.Z == held.Z and Crowd.Get(presser) ~= nil, "planted in its windup like any body")

	fresh()
	root.Position = vec(0, 3, 92)
	local cornered = Crowd.Spawn("slinger", vec(0, 0, 96), "fight")
	step2(10)
	check(near(Crowd.Get(cornered).position.Z, 98.8, 1e-6), "at the arena's edge it stops (z 98.8)")
	check(seen(cornered).state == "idle", "and stands there instead of walking into the wall")
	table.clear(struck)
	step2(20)
	check(#struck >= 1 and struck[1].def.shape == "shot", "and fights from where it stands")
end
keepAwayTests()

local function shotTests(): ()
	print(" shot")
	fresh()
	local slinger = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	check(waitFor(slinger, "windup", 40), "a slinger in its band winds up")
	local impact = stamp() + 0.6
	local raysBefore = rays
	local shot = waitFx("enemyShot", 15)
	check(shot ~= nil and near(stamp(), impact, 1e-9), "enemyShot leaves in the frame of its impact")
	check(shot.enemyKind == "slinger" and shot.enemyId == slinger and shot.id > 0 and near(shot.radius, 1) and near(shot.seconds, 2.5), "it names the kind, the body that fired it, an id, the radius and the lifetime")
	check(near(shot.firedAt, impact + SERVER_OFFSET, 1e-9), "firedAt = the windup's first stamp + windup, in server time")
	check(near(shot.from.X, 0) and near(shot.from.Y, 2.5) and near(shot.from.Z, 25), "from the body centre")
	local aimed = (vec(0, 3, 0) - shot.from).Unit
	check(near(shot.velocity.Magnitude, 28, 1e-9) and near((shot.velocity.Unit - aimed).Magnitude, 0, 1e-9), "at `speed`, straight at the root of a target standing still")
	kill(slinger)
	-- The sphere (radius 1) reaches the root 24.005 studs on: T + 0.857. It is judged a lag later.
	local flown = 0
	while fakeNow + DT < impact + 0.857 + LAG - 1e-9 do
		step2()
		flown += 1
	end
	check(humanoid.Health == 130 and (fakeNow - impact) * 28 > 25.5, "the root is tested against where the shot was a lag ago: it has flown past and nothing is decided yet")
	step2()
	flown += 1
	local hurts = of(log, "hurt")
	local ends = of(log, "enemyShotEnd")
	check(humanoid.Health == 118 and #hurts == 1 and hurts[1].amount == 12 and hurts[1].push == nil and hurts[1].enemyKind == "slinger", "then it lands: 130 -> 118, and moves nobody")
	check(near((hurts[1].from - shot.from).Magnitude, 0), "hurt.from is where the slinger stood")
	check(#ends == 1 and ends[1].id == shot.id and ends[1].hit == true and flatTo(ends[1].at, root.Position) < 0.01, "enemyShotEnd: hit, at the point of its path where it met them")
	check(rays - raysBefore == 1 and flown == 15, `its path is cut once, at fire: one world ray for the whole flight ({rays - raysBefore} ray in {flown} steps)`)
	check(Field.ShotsAlive() == 0, "and the shot is gone")
	step2(30)
	check(#of(log, "hurt") == 1 and #of(log, "enemyShotEnd") == 1 and kills == 1, "a slinger killed after its shot left: the shot flew on (ruling 22)")

	-- The lead.
	fresh()
	local leader = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	local x = 0
	local led: any = nil
	for _ = 1, 60 do
		x += 15 * DT
		root.Position = vec(x, 3, 0)
		step2()
		led = of(log, "enemyShot")[1]
		if led ~= nil then
			break
		end
	end
	local here = vec(x, 3, 0)
	local velocity = vec(15, 0, 0)
	local aim = here
	for _ = 1, PASSES do
		aim = here + velocity * ((aim - led.from).Magnitude / 28 + LAG) * 0.7
	end
	check(led ~= nil and near((led.velocity.Unit - (aim - led.from).Unit).Magnitude, 0, 1e-6), "it leads a walking target by `lead` of its motion over the flight, taken from the root's displacement")
	kill(leader)

	-- Review 1a: standing on an 8-stud block is standing. The shot is aimed at the root where
	-- it is, and clears the block's edge; led down to the floor it would fly into its side.
	fresh()
	table.insert(blocks, { min = vec(-4, 0, -4), max = vec(4, 8, 4) })
	root.Position = vec(0, 3 + 8, 0)
	local onBlock = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	local high = waitFx("enemyShot", 60)
	kill(onBlock)
	check(high ~= nil and near((high.velocity.Unit - (vec(0, 11, 0) - high.from).Unit).Magnitude, 0, 1e-9), "review 1a: a player standing on a block is aimed at where they stand, not led down a fall")
	check(near(high.seconds, 2.5), "and the path to them is clear of the block they stand on")
	step2(20)
	check(humanoid.Health == 118, "so the shot reaches them up there (130 -> 118)")

	-- A slinger's shot at a root that plays `heightAt` step by step, from `hold` steps into the
	-- windup: the shot, the root's height when it left, and the step before.
	local function shootAt(hold: number, heightAt: (air: number) -> number): (any, number, number)
		local id = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
		waitFor(id, "windup", 40)
		step2(hold)
		local air = 0
		local height = root.Position.Y
		local last = height
		local shot: any = nil
		for _ = 1, 20 do
			air += DT
			last = height
			height = heightAt(air)
			root.Position = vec(0, height, 0)
			step2()
			shot = of(log, "enemyShot")[1]
			if shot ~= nil then
				break
			end
		end
		kill(id)
		return shot, height, last
	end
	-- The brain's lead, by hand: a fall from `height` (the step before: `last`), stopped at `floor`.
	local function fallsTo(shot: any, height: number, last: number, floor: number): boolean
		local rising = (height - last) / DT
		local up = vec(0, height, 0)
		local led = up
		for _ = 1, PASSES do
			local flight = (led - shot.from).Magnitude / 28 + LAG
			local landed = math.max(floor, height + rising * flight - 0.5 * 196.2 * flight * flight)
			led = up + (vec(0, landed, 0) - up) * 0.7
		end
		return near((shot.velocity.Unit - (led - shot.from).Unit).Magnitude, 0, 1e-6)
	end
	local lift = math.sqrt(2 * 196.2 * 18)

	-- A jump is led under gravity, down to the surface it left.
	fresh()
	local leaping, height, last = shootAt(3, function(air)
		return math.max(3, 3 + lift * air - 0.5 * 196.2 * air * air)
	end)
	check(leaping ~= nil and height > 8 and fallsTo(leaping, height, last, 3), `a target in the middle of a jump is led under gravity, down to the floor it left (fired at {string.format("%.1f", height)} up)`)

	-- From a block, that surface is the block.
	fresh()
	table.insert(blocks, { min = vec(-4, 0, -4), max = vec(4, 8, 4) })
	root.Position = vec(0, 3 + 8, 0)
	leaping, height, last = shootAt(3, function(air)
		return math.max(11, 11 + lift * air - 0.5 * 196.2 * air * air)
	end)
	check(leaping ~= nil and height > 16 and fallsTo(leaping, height, last, 11), `review 1a: a jump off a block is led down to the block, the surface they last stood on (fired at {string.format("%.1f", height)} up)`)

	-- Stepped off what they stood on: led down to the crowd's floor.
	fresh()
	root.Position = vec(0, 3 + 8, 0)
	leaping, height, last = shootAt(6, function(air)
		return math.max(3, 11 - 0.5 * 196.2 * air * air)
	end)
	check(leaping ~= nil and height < 11 and height > 3 and fallsTo(leaping, height, last, 3), `review 1a: below the surface they last stood on, a fall is led down to the crowd's floor (fired at {string.format("%.1f", height)} up)`)

	-- One step without rising or falling is the top of a jump, not rest: rest takes two. A root
	-- that climbs every other step is caught on a still step in one of these two runs.
	local stillSteps = 0
	for phase = 0, 1 do
		fresh()
		local index = phase
		local climbed = 3
		leaping, height, last = shootAt(1, function(_air)
			index += 1
			if index % 2 == 1 then
				climbed += 4
			end
			return climbed
		end)
		local label = "a root caught mid-climb is led down a fall"
		if height == last then
			stillSteps += 1
			label = "review 1a: one step without rising or falling is not rest (a jump's top): still led down"
		end
		check(leaping ~= nil and height > 8 and fallsTo(leaping, height, last, 3), label)
	end
	check(stillSteps == 1, "(one of the two runs fired on a still step)")

	-- Review minor 6: a root that moves faster than any legal move is not believed.
	fresh()
	local jitter = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	check(waitFor(jitter, "windup", 40), "a slinger winds up on a root about to jitter")
	local far = 0
	local wild: any = nil
	for _ = 1, 20 do
		far += 30
		root.Position = vec(far, 3, 0)
		step2()
		wild = of(log, "enemyShot")[1]
		if wild ~= nil then
			break
		end
	end
	kill(jitter)
	local there = vec(far, 3, 0)
	local capped = there
	for _ = 1, PASSES do
		capped = there + vec(140, 0, 0) * ((capped - wild.from).Magnitude / 28 + LAG) * 0.7
	end
	check(wild ~= nil and near((wild.velocity.Unit - (capped - wild.from).Unit).Magnitude, 0, 1e-6), "review minor 6: the lead trusts no speed above the fastest legal move (450 studs/s read, 140 used)")

	-- World geometry.
	fresh()
	table.insert(walls, { axis = "Z", at = 10 })
	local blocked = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	local toWall = waitFx("enemyShot", 60)
	kill(blocked)
	step2(30)
	check(humanoid.Health == 130 and #of(log, "hurt") == 0, "world geometry stops a shot")
	local toTheWall = (15 / math.abs(toWall.velocity.Z)) 
	check(toWall ~= nil and near(toWall.seconds, toTheWall, 1e-9) and toWall.seconds < 0.6, `review 2: enemyShot.seconds is cut to the wall on its path ({string.format("%.3f", toWall.seconds)} s, not 2.5)`)
	check(#of(log, "enemyShotEnd") == 0 and Field.ShotsAlive() == 0, "and it ends there without a word: no enemyShotEnd for a wall")

	-- It runs out; walking out of its way is not a dodge.
	fresh()
	local missed = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	local wide = waitFx("enemyShot", 60)
	kill(missed)
	root.Position = vec(12, 3, 0)
	step2(45)
	check(humanoid.Health == 130 and #of(log, "hurt") == 0, "walking out of a shot's way sends nothing")
	check(near(wide.seconds, 2.5) and #of(log, "enemyShotEnd") == 0 and Field.ShotsAlive() == 0, "review 2: it runs its `seconds` out and no enemyShotEnd is sent for that")

	-- Ruling 26: the same, under an i-frame, is a dodge.
	fresh()
	local dodged = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	local past = waitFx("enemyShot", 60)
	kill(dodged)
	local reach = past.firedAt - SERVER_OFFSET + (vec(0, 3, 0) - past.from).Magnitude / 28
	root.Position = vec(12, 3, 0)
	iframes.from = reach - 0.05
	iframes.untilClock = reach + 0.05
	step2(45)
	local dodges = of(log, "hurt")
	check(humanoid.Health == 130 and #dodges == 1 and dodges[1].dodged == true and dodges[1].amount == 0, "ruling 26: a dash out of the way of a shot aimed at you is one `dodged`")

	-- A voided contact lets it fly on.
	fresh()
	local through = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	local ghost = waitFx("enemyShot", 60)
	kill(through)
	iframes.from = fakeNow
	iframes.untilClock = fakeNow + 3
	step2(45)
	check(ghost ~= nil and humanoid.Health == 130 and #of(log, "hurt") == 1 and of(log, "hurt")[1].dodged == true, "a shot that passes through an i-frame is dodged, once")
	check(#of(log, "enemyShotEnd") == 0, "and flies on: no end is sent")

	-- The first player on its path.
	fresh()
	join2(vec(0, 3, 6))
	local pair = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	waitFx("enemyShot", 60)
	kill(pair)
	step2(30)
	check(struck[1].targetUserId == 8 and humanoid2.Health == 118 and humanoid.Health == 130, "it stops in the first player on its path")
	check(#of(log, "hurt") == 1 and #of(log2, "hurt") == 1, "and both players are told of that one hit")
	leave2()

	-- The cap.
	fresh()
	config.crowd.threat.maxShots = 1
	local left = Crowd.Spawn("slinger", vec(-6, 0, 25), "fight")
	local right = Crowd.Spawn("slinger", vec(6, 0, 25), "fight")
	local most = 0
	for _ = 1, 15 * 8 do
		step2()
		local held = Field.ShotsAlive()
		if seen(left).state == "windup" then
			held += 1
		end
		if seen(right).state == "windup" then
			held += 1
		end
		most = math.max(most, held)
	end
	check(most == 1, `never more than maxShots in the air or being wound up (most {most})`)
	check(#of(log, "enemyShot") >= 3, "the slingers take turns under the cap")
	config.crowd.threat.maxShots = 24

	-- A set load.
	fresh()
	Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	waitFx("enemyShot", 60)
	step2(3)
	table.clear(log)
	Crowd.Clear()
	Vitals.OnSetLoaded()
	step2(40)
	local cleared = of(log, "enemyShotEnd")
	check(#cleared == 1 and cleared[1].hit == false and #of(log, "hurt") == 0 and humanoid.Health == 130 and Field.ShotsAlive() == 0, "a set load ends the shots in the air where they are")

	-- Ruling 24a for an attack that travels: down while the shot passed through them, up
	-- again when that stretch of its flight is judged.
	fresh()
	local passing = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	local overDown = waitFx("enemyShot", 60)
	kill(passing)
	local leftAt = overDown.firedAt - SERVER_OFFSET
	config.player.downSeconds = 0.14
	humanoid.Health = 5
	-- Decided, and so down, at the step 0.8 s after it left; the shot meets them at 0.857.
	hooks.impact(lunge(leftAt + 12 * DT - LAG - 0.01))
	step2(20)
	config.player.downSeconds = 2
	local whileDown = of(log, "hurt")
	check(#whileDown == 1 and whileDown[1].down == true and humanoid.Health == 130, "ruling 24a: a shot that passed through a downed player is not theirs, though they are up when it is judged")

	-- Killed in its windup: no shot.
	fresh()
	local early = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
	waitFor(early, "windup", 40)
	step2(3)
	kill(early)
	step2(30)
	check(#struck == 0 and #of(log, "enemyShot") == 0, "a slinger killed in its windup never fires")
end
shotTests()

local function lineTests(): ()
	print(" line")
	fresh()
	local marksman = Crowd.Spawn("marksman", vec(0, 0, 35), "fight")
	local x = 0
	local function walk(): ()
		x += 40 * DT
		root.Position = vec(x, 3, 0)
		step2()
	end
	-- Standing until the windup starts, then off at 40 studs a second.
	local wound = waitFor(marksman, "windup", 60)
	local started = stamp()
	local impact = started + 1.0
	local lockAt = impact - 0.25
	local startX = x
	local before: { number } = {}
	local after: { number } = {}
	local raysAtImpact = 0
	local raysElsewhere = 0
	while stamp() < impact - 1e-9 do
		local had = rays
		walk()
		if near(stamp(), impact, 1e-9) then
			raysAtImpact += rays - had
		else
			raysElsewhere += rays - had
		end
		table.insert(if stamp() < lockAt then before else after, seen(marksman).yaw)
	end
	-- The yaw byte is 1/256 of a turn, about one step of this walk: judge the whole turn.
	local followed = math.abs(before[#before] - before[1]) > 0.15
	for index = 2, #before do
		followed = followed and before[index] <= before[index - 1]
	end
	local frozen = true
	for index = 2, #after do
		frozen = frozen and after[index] == after[1]
	end
	check(wound and #before >= 5 and followed, "until the lock its facing follows the target")
	check(#after >= 3 and frozen, "from T - lockSeconds it is frozen")
	local lockX = startX + 40 * (lockAt - started)
	local toLock = (vec(lockX, 0, 0) - vec(0, 0, 35)).Unit
	local lockYaw = Codec2.SnapYaw(math.atan2(-toLock.X, -toLock.Z))
	local expected = vec(-math.sin(lockYaw), 0, -math.cos(lockYaw))
	local line = struck[1]
	check(line ~= nil and near((line.facing - expected).Magnitude, 0, 1e-9), "the lock is taken at T - lockSeconds exactly, not at the step that passed it")
	local wire = after[#after]
	check(near((line.facing - vec(-math.sin(wire), 0, -math.cos(wire))).Magnitude, 0, 1e-9) and near((line.facing - toLock).Magnitude, 0, 0.02) and (line.facing - toLock).Magnitude > 1e-6, "ruling A: the locked facing it is judged along is the wire's own yaw, a step of 1/256 turn")
	check(raysAtImpact == 1 and raysElsewhere == 0, `one world ray, at the impact ({raysAtImpact} then, {raysElsewhere} otherwise)`)
	step2(6)
	check(humanoid.Health == 130 and #of(log, "hurt") == 0, "moving on after the lock takes the target out of the lane")
	for _, fx in log do
		check(fx.kind == "hurt", "a line sends nothing but hurt")
	end
	check(#log == 0, "(and here nothing at all)")

	-- The canonical dodge: stand, and step aside once it has locked.
	fresh()
	local aimer = Crowd.Spawn("marksman", vec(0, 0, 35), "fight")
	check(waitFor(aimer, "windup", 40), "a marksman winds up on a standing target")
	local locksAt = stamp() + 1.0 - 0.25
	while fakeNow < locksAt + DT do
		step2()
	end
	root.Position = vec(5, 3, 0)
	step2(8)
	check(seen(aimer).state == "recover" and humanoid.Health == 130 and #log == 0, "a step aside after the lock is out of the lane: the facing does not follow any more")

	-- Standing in it, in the air: a line has no height rule.
	fresh()
	root.Position = vec(0, 3 + 20, 0)
	local sniper = Crowd.Spawn("marksman", vec(0, 0, 35), "fight")
	check(waitFor(sniper, "windup", 40), "a marksman winds up")
	local shotAt = stamp() + 1.0
	while fakeNow + DT < shotAt + LAG - 1e-9 do
		step2()
	end
	check(humanoid.Health == 130, "an instant shot is still judged a lag after T")
	step2()
	local hit = of(log, "hurt")
	check(humanoid.Health == 108 and #hit == 1 and hit[1].amount == 22, "a line has no height rule: 20 studs up in the lane is hit (130 -> 108)")
	check(#of(log, "enemyShot") == 0 and #of(log, "area") == 0 and #log == 1, "and only hurt is sent")

	-- World geometry cuts it short.
	fresh()
	table.insert(walls, { axis = "Z", at = 10 })
	local walled = Crowd.Spawn("marksman", vec(0, 0, 35), "fight")
	waitFor(walled, "recover", 60)
	step2(4)
	check(humanoid.Health == 130 and #log == 0 and near(struck[1].length, 25, 1e-6), "world geometry cuts the line short of the target")

	-- Review 1b: the target stands on a block. A level ray from the marksman's chest would
	-- stop at the block's face, four studs in front of them.
	fresh()
	table.insert(blocks, { min = vec(-4, 0, -4), max = vec(4, 8, 4) })
	-- Behind them, 59 studs along the lane: the ray climbs, and must still be long enough to
	-- cover the lane's whole range on the flat.
	table.insert(walls, { axis = "Z", at = -24 })
	root.Position = vec(0, 3 + 8, 0)
	local uphill = Crowd.Spawn("marksman", vec(0, 0, 35), "fight")
	waitFor(uphill, "recover", 60)
	step2(4)
	check(struck[1].aim ~= nil and near(struck[1].aim.Y, 11) and near(struck[1].length, 59, 1e-9), "review 1b: the line's ray is cast at the body it locked on, over the edge of the block they stand on, and on to the end of its range")
	check(humanoid.Health == 108, "so a player standing on a block is hit by the line (130 -> 108)")
	check(rays == 1, "still exactly one ray for the line")
	fresh()
	table.insert(blocks, { min = vec(-4, 0, -4), max = vec(4, 8, 4) })
	table.insert(walls, { axis = "Z", at = 10 })
	root.Position = vec(0, 3 + 8, 0)
	local shut = Crowd.Spawn("marksman", vec(0, 0, 35), "fight")
	waitFor(shut, "recover", 60)
	step2(4)
	check(humanoid.Health == 130 and near(struck[1].length, 25, 1e-9), "a wall between the two still cuts it, at the flat distance of the ray's hit (25, not the 25.7 the ray flew)")

	-- Review 3: its target gone before the lock, it still fires along a facing on the wire's step.
	fresh()
	root.Position = vec(7.3, 3, 1.1)
	local blind = Crowd.Spawn("marksman", vec(-3.1, 0, 35), "fight")
	check(waitFor(blind, "windup", 40), "a marksman winds up off the axes")
	for index = 1, 4 do
		root.Position = vec(7.3 + index * 2.7, 3, 1.1)
		step2()
	end
	player.Character = nil
	waitFor(blind, "recover", 30)
	player.Character = character
	local loose = struck[1].facing
	local looseYaw = Codec2.SnapYaw(math.atan2(-loose.X, -loose.Z))
	local followed = (vec(7.3 + 4 * 2.7, 0, 1.1) - vec(-3.1, 0, 35)).Unit
	check(near((loose - vec(-math.sin(looseYaw), 0, -math.cos(looseYaw))).Magnitude, 0, 1e-12), "review 3: a line whose target was gone before the lock still fires along a snapped facing")
	check((loose - followed).Magnitude < 0.02 and (loose - followed).Magnitude > 1e-6, "(the one it last followed, on the wire's step)")

	-- Killed before T.
	fresh()
	local dead = Crowd.Spawn("marksman", vec(0, 0, 35), "fight")
	waitFor(dead, "windup", 40)
	step2(10)
	kill(dead)
	step2(20)
	check(#struck == 0 and humanoid.Health == 130, "a marksman killed before T does not fire")
end
lineTests()

local function lobTests(): ()
	print(" lob")
	fresh()
	root.Position = vec(1, 3 + 6, 2)
	local lobber = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
	check(waitFor(lobber, "windup", 40), "a lobber winds up")
	local thrown = stamp() + 0.5
	local raysBefore = rays
	local area = waitFx("area", 15)
	check(area ~= nil and area.enemyKind == "lobber" and area.enemyId == lobber and area.id > 0 and near(area.radius, 5), "area names the kind, the body that threw it, an id and the radius")
	check(near(area.startsAt, thrown + SERVER_OFFSET, 1e-9) and near(area.endsAt, thrown + 1.4 + SERVER_OFFSET, 1e-9), "startsAt = T, endsAt = T + seconds, in server time")
	check(near(area.center.X, 1) and area.center.Y == 0 and near(area.center.Z, 2), "its centre is the floor point under the target at T")
	check(near(area.from.Y, 2.5) and near(area.from.Z, 30), "from the lobber's body centre")
	kill(lobber)
	-- Two studs off the centre, on the ground, when it lands.
	root.Position = vec(3, 3, 2)
	local landing = thrown + 1.4
	while fakeNow + 1 / 60 < landing + LAG - 1e-9 do
		advance(1 / 60)
	end
	gather()
	check(humanoid.Health == 130, "nothing lands before endsAt + lag")
	table.clear(granted)
	advance(2 / 60)
	gather()
	local hurts = of(log, "hurt")
	check(humanoid.Health == 112 and #hurts == 1 and hurts[1].amount == 18, "the lob lands on a player in its circle: 130 -> 112 (and its lobber was dead: ruling 22)")
	check(near(hurts[1].push.X, 14) and near(hurts[1].push.Z, 0) and hurts[1].launch == 3 and #granted == 1, "pushed away from the centre, launched, with the knock window")
	check(rays == raysBefore + 1, "a lob casts one ray, straight down from its target")

	local function throw(): number
		fresh()
		local id = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
		waitFor(id, "windup", 40)
		local at = stamp() + 0.5
		waitFx("area", 15)
		kill(id)
		table.clear(log)
		return at + 1.4
	end
	local function land(at: number): ()
		while fakeNow < at + LAG + 0.05 do
			advance(1 / 60)
		end
		gather()
	end

	local lands = throw()
	root.Position = vec(6, 3, 0)
	land(lands)
	check(humanoid.Health == 130 and #log == 0, "out of the circle when it lands: nothing")
	lands = throw()
	root.Position = vec(0, 3 + 4.5, 0)
	land(lands)
	check(humanoid.Health == 130 and #log == 0, "feet above its height when it lands: nothing")
	lands = throw()
	root.Position = vec(6, 3, 0)
	iframes.from = lands - 0.02
	iframes.untilClock = lands + 0.2
	land(lands)
	check(humanoid.Health == 130 and #of(log, "hurt") == 1 and of(log, "hurt")[1].dodged == true, "ruling 26: the player it was thrown at, out of it under an i-frame: dodged")

	-- A bystander's miss says nothing; a bystander inside it is hit.
	fresh()
	join2(vec(40, 3, 30))
	local shared = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
	waitFor(shared, "windup", 40)
	local sharedAt = stamp() + 0.5 + 1.4
	waitFx("area", 15)
	kill(shared)
	root2.Position = vec(2, 3, 0)
	root.Position = vec(20, 3, 0)
	iframes.from = sharedAt - 0.02
	iframes.untilClock = sharedAt + 0.2
	table.clear(log)
	table.clear(log2)
	land(sharedAt)
	check(struck[1].targetUserId == 7 and humanoid2.Health == 112, "a lob catches whoever is in its circle")
	check(#of(log, "hurt") == 2, "the thrown-at player's own dodge and the bystander's hurt both reach them")
	leave2()
	fresh()
	join2(vec(40, 3, 30))
	local other = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
	waitFor(other, "windup", 40)
	local otherAt = stamp() + 0.5 + 1.4
	waitFx("area", 15)
	kill(other)
	table.clear(log2)
	land(otherAt)
	local mine = 0
	for _, fx in log2 do
		if fx.kind == "hurt" and fx.userId == 8 then
			mine += 1
		end
	end
	check(humanoid.Health == 112 and mine == 0, "a bystander it never reached is sent nothing of their own")
	leave2()

	-- Review 1c: it lands on the block the player stands on.
	fresh()
	table.insert(blocks, { min = vec(-4, 0, -4), max = vec(4, 8, 4) })
	table.insert(walls, { axis = "Z", at = 15 })
	root.Position = vec(1, 3 + 8, 0)
	local uphill = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
	waitFor(uphill, "windup", 40)
	local upAt = stamp() + 0.5 + 1.4
	local raised = waitFx("area", 15)
	kill(uphill)
	check(raised ~= nil and near(raised.center.X, 1) and near(raised.center.Y, 8, 1e-9) and near(raised.center.Z, 0), "review 1c: area.center is the surface under the target, its height included (the block's top)")
	land(upAt)
	check(humanoid.Health == 112, "and the lob lands on a player standing on that block: `height` is measured from it (and a wall between did not stop it)")
	fresh()
	table.insert(blocks, { min = vec(-4, 0, -4), max = vec(4, 8, 4) })
	root.Position = vec(1, 3 + 8, 0)
	local uphill2 = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
	waitFor(uphill2, "windup", 40)
	local upAt2 = stamp() + 0.5 + 1.4
	waitFx("area", 15)
	kill(uphill2)
	root.Position = vec(1, 3 + 8 + 4.5, 0)
	land(upAt2)
	check(humanoid.Health == 130, "a jump off that block's top still clears it: 4.5 above the block is above its height")

	-- The lead's addition to 1c: a lob holds feet within `height` of its floor, above or below.
	local function beside(onBlock: boolean): (number, number)
		fresh()
		if onBlock then
			table.insert(blocks, { min = vec(-4, 0, -4), max = vec(4, 8, 4) })
			root.Position = vec(1, 3 + 8, 0)
		else
			root.Position = vec(1, 3, 0)
		end
		join2(vec(40, 3, 30))
		local id = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
		waitFor(id, "windup", 40)
		local at = stamp() + 0.5 + 1.4
		waitFx("area", 15)
		kill(id)
		-- On the arena floor, off the block's side, 4.5 studs from the circle's centre.
		root2.Position = vec(5.5, 3, 0)
		table.clear(log2)
		land(at)
		local told = 0
		for _, fx in log2 do
			if fx.kind == "hurt" and fx.userId == 8 then
				told += 1
			end
		end
		leave2()
		return humanoid2.Health, told
	end
	local health2, told2 = beside(true)
	check(humanoid.Health == 112, "a lob thrown at a player on a block: the player on the block is hit")
	check(health2 == 130 and told2 == 0, "and a player on the arena floor beside the block, inside its radius, is under the circle: missed, and told nothing")
	health2, told2 = beside(false)
	check(humanoid.Health == 112 and health2 == 112 and told2 == 1, "a lob on the open floor is unchanged: both players in its circle are hit")

	-- L1b Wave 4 fix round R6: every ground shape has the lob's lower bound (a region floor ends at a drop).
	fresh()
	root.Position = vec(0, 3 - 8, 0)
	hooks.impact(arc(fakeNow))
	advance(0.25)
	gather()
	check(humanoid.Health == 130, "R6: an arc measures from the crowd's floor with both bounds (feet 8 under it: missed)")

	-- A set load.
	lands = throw()
	Crowd.Clear()
	Vitals.OnSetLoaded()
	land(lands)
	check(humanoid.Health == 130 and #of(log, "hurt") == 0, "a set load clears the lobs in the air")

	-- Killed in its windup: nothing is thrown.
	fresh()
	local early = Crowd.Spawn("lobber", vec(0, 0, 30), "fight")
	waitFor(early, "windup", 40)
	step2(3)
	kill(early)
	step2(40)
	check(#struck == 0 and #of(log, "area") == 0 and humanoid.Health == 130, "a lobber killed in its windup throws nothing")

	-- Ruling 18 leaves a lob still in the air alone.
	lands = throw()
	hooks.impact(arc(lands - 1.0))
	land(lands)
	check(humanoid.Health == 130 - 30 - 18, "a knock a second before it lands does not void a lob still in the air")

	-- Ruling 24a at the landing, not at the throw.
	lands = throw()
	config.player.downSeconds = 0.05
	humanoid.Health = 5
	hooks.impact(lunge(lands - 0.02 - LAG))
	land(lands)
	config.player.downSeconds = 2
	local sent = of(log, "hurt")
	check(#sent == 1 and sent[1].down == true and humanoid.Health == 130, "ruling 24a: down when it landed, up again when it is judged: the lob is not theirs")
end
lobTests()

local function laneTests(): ()
	print(" lane")
	fresh()
	local brute = Crowd.Spawn("brute", vec(0, 0, 20), "fight")
	check(waitFor(brute, "windup", 40), "a brute in reach winds up")
	local from = Crowd.Get(brute).position
	local impact = stamp() + 0.8
	local raysBefore = rays
	local onPath = true
	local charging = 0
	local hitAtStep = 0
	for index = 1, 40 do
		step2()
		local entry = seen(brute)
		if entry.state == "attack" then
			charging += 1
			local run = math.min(55 * (stamp() - impact), 30)
			local place = Crowd.Get(brute).position
			onPath = onPath and near(place.X, from.X, 1e-9) and near(place.Z, from.Z - run, 1e-6)
		end
		if hitAtStep == 0 and humanoid.Health < 130 then
			hitAtStep = index
		end
		if entry.state == "recover" then
			break
		end
	end
	check(charging == 9 and onPath, `its attack state lasts range / speed and the body is carried down the lane at the charge's pace ({charging} snapshots)`)
	check(near(Crowd.Get(brute).position.Z, from.Z - 30, 1e-6), "it ends its run `range` on")
	local hurts = of(log, "hurt")
	check(humanoid.Health == 102 and #hurts == 1 and hurts[1].amount == 28 and hurts[1].launch == 3, "a player in the lane is hit once: 130 -> 102")
	check(near(hurts[1].push.Z, -40) and near(hurts[1].push.X, 0), "pushed along the charge")
	-- The body is 2.5 from the root 17.5 studs on: T + 0.318; judged a lag later: T + 0.418,
	-- seen by the step at T + 0.467 (the 7th of the charge, the 19th since the windup began).
	check(hitAtStep == 12 + 7, `judged against the body as it was a lag ago (step {hitAtStep})`)
	check(rays == raysBefore, "a charge casts no ray")
	step2(30)
	check(#of(log, "hurt") == 1, "and never twice")

	-- The arena's edge.
	fresh()
	root.Position = vec(0, 3, -95)
	local edged = Crowd.Spawn("brute", vec(0, 0, -80), "fight")
	waitFor(edged, "windup", 40)
	local edgeImpact = stamp() + 0.8
	local stopped = 0
	local stillAttack = true
	while stamp() < edgeImpact + 30 / 55 - DT do
		step2()
		if stamp() >= edgeImpact - 1e-9 then
			stillAttack = stillAttack and seen(edged).state == "attack"
			if near(Crowd.Get(edged).position.Z, -97.8, 1e-6) then
				stopped += 1
			end
		end
	end
	check(stopped >= 3 and stillAttack, "it stops at the arena's edge, and its attack state still lasts range / speed")
	check(near(struck[1].length, 17.8, 1e-6), "(its run was cut to the edge)")

	-- Nothing stops or moves it; hits still hurt it.
	fresh()
	local hard = Crowd.Spawn("runner", vec(0, 0, 20), "fight")
	waitFor(hard, "attack", 60)
	local start = stamp()
	local dealt = Crowd.Damage(hard, 60, 7, vec(200, 0, 0), 12)
	step2()
	local place = Crowd.Get(hard).position
	check(dealt == 60 and Crowd.Get(hard).hp == 260 and seen(hard).state == "attack" and place.X == 0 and place.Y == 0, "a heavy hit in the charge hurts it and neither shoves, lifts nor staggers it")
	while seen(hard).state == "attack" do
		Crowd.Damage(hard, 1, 7, nil, nil)
		step2()
	end
	local after = seen(hard).state
	step2()
	check(after == "recover" and seen(hard).state == "recover" and stamp() - start < 0.7, "and hits during the charge leave no stagger behind it")

	-- A kill ends it.
	fresh()
	join2(vec(0, 3, -8))
	local doomed = Crowd.Spawn("brute", vec(0, 0, 20), "fight")
	waitFor(doomed, "attack", 60)
	step2(5)
	kill(doomed)
	check(near(Crowd.Get(doomed).position.Z, 20 - 55 * 5 * DT, 1e-6), "(killed 18 studs into its run: over the first player, short of the second)")
	step2(20)
	check(struck[1].targetUserId == 7 and humanoid.Health == 102, "what it ran over before the kill still counts")
	check(humanoid2.Health == 130 and seen(doomed).state ~= "attack", "a kill ends the charge: the player further down the lane is not hit")
	leave2()

	-- Jumping it; ruling 26.
	local function charge(): number
		fresh()
		local id = Crowd.Spawn("brute", vec(0, 0, 20), "fight")
		waitFor(id, "windup", 40)
		return stamp() + 0.8
	end
	local chargeAt = charge()
	root.Position = vec(0, 3 + 5.5, 0)
	step2(30)
	check(humanoid.Health == 130 and #log == 0, "feet above its height: the charge passes under")
	chargeAt = charge()
	step2(2)
	root.Position = vec(8, 3, 0)
	step2(30)
	check(humanoid.Health == 130 and #log == 0, "walking out of the lane sends nothing")
	chargeAt = charge()
	step2(2)
	root.Position = vec(8, 3, 0)
	-- It passes where its target stood (20 studs on) at T + 0.364.
	iframes.from = chargeAt + 0.364 - 0.02
	iframes.untilClock = chargeAt + 0.364 + 0.05
	step2(30)
	check(humanoid.Health == 130 and #of(log, "hurt") == 1 and of(log, "hurt")[1].dodged == true, "ruling 26: a dash out of a charge aimed at you is one `dodged`")
end
laneTests()

local function rulingTests(): ()
	print(" the lead's rulings on the finished wave")
	local function ofWire(id: number): any
		local yaw = seen(id).yaw
		return vec(-math.sin(yaw), 0, -math.cos(yaw))
	end
	-- A: off the axes, so the snap is visible.
	fresh()
	root.Position = vec(1.7, 3, 0.4)
	local elite = Crowd.Spawn("armoured", vec(4.3, 0, 4.1), "fight")
	check(waitFor(elite, "windup", 40), "an elite off the axes winds up")
	local drawn = ofWire(elite)
	local yawBefore = seen(elite).yaw
	Crowd.Damage(elite, 24, 7, vec(0, 0, 80), 0)
	step2()
	check(seen(elite).state ~= "windup" and seen(elite).attack == 1 and seen(elite).yaw == yawBefore, "ruling A: a shove that does not cancel leaves the wire yaw of a locked facing alone")
	waitFor(elite, "recover", 30)
	local exact = (vec(1.7, 0, 0.4) - vec(4.3, 0, 4.1)).Unit
	check(#struck == 1 and near((struck[1].facing - drawn).Magnitude, 0, 1e-9), "ruling A: an arc is judged along the yaw the snapshot carried")
	check((struck[1].facing - exact).Magnitude > 1e-6 and (struck[1].facing - exact).Magnitude < 0.02, "(which is the exact heading snapped to the wire's step)")
	fresh()
	root.Position = vec(-9, 3, 2)
	local charger = Crowd.Spawn("brute", vec(6, 0, 9.5), "fight")
	check(waitFor(charger, "windup", 40), "a brute off the axes winds up")
	local lane = ofWire(charger)
	local began = Crowd.Get(charger).position
	waitFor(charger, "recover", 40)
	local ended = Crowd.Get(charger).position
	check(near((struck[1].facing - lane).Magnitude, 0, 1e-9) and near(((ended - began).Unit - lane).Magnitude, 0, 1e-6), "ruling A: a charge runs down the lane the snapshot's yaw draws")

	-- B: the entries of one strike, with the real Damage.
	local Tally = load("StrikeTally")
	fresh()
	root.Position = vec(0, 3, -90)
	local shell = Crowd.Spawn("plated", vec(0, 0, 20), "idle")
	local bare = Crowd.Spawn("fodder", vec(10, 0, 20), "idle")
	step2()
	local tally = Tally.New()
	local function hit(id: number, amount: number, crit: boolean?): ()
		local dealt, killed, verdict = Crowd.Damage(id, amount, 7, nil, nil)
		Tally.Add(tally, id, dealt, crit == true, killed, verdict)
	end
	hit(shell, 20)
	check(#tally.hits == 1 and tally.hits[1].blocked == true and tally.hits[1].amount == 0 and tally.enemies == 1 and tally.dealt == 0, "a blocked hit is an entry of 0, and still an enemy hit")
	hit(shell, 50)
	check(#tally.hits == 1 and tally.hits[1].blocked == nil and tally.hits[1].plate == true and tally.hits[1].amount == 50, "a plate hit on the same enemy takes that entry over: no longer blocked")
	hit(shell, 30)
	check(#tally.hits == 1 and tally.hits[1].plate == true and tally.hits[1].amount == 50, "a later blocked part adds nothing to it")
	hit(shell, 60)
	check(#tally.hits == 1 and tally.hits[1].amount == 110 and tally.hits[1].broke == true, "the part that empties the plate marks that entry broke")
	hit(shell, 30)
	hit(shell, 30, true)
	local plain = tally.hits[2]
	check(#tally.hits == 2 and tally.hits[1].amount == 110 and tally.hits[1].plate == true, "ruling B: what then goes to its health is a second entry; the plate's is untouched")
	check(plain ~= nil and plain.id == shell and plain.amount == 50 and plain.plate == nil and plain.broke == nil and plain.blocked == nil and plain.crit == true, "and that entry is plain: 2 x (30 - armor 5), no plate flags")
	check(tally.enemies == 1 and tally.dealt == 160 and tally.kills == 0, "one enemy hit; plate damage counts as damage dealt")
	hit(bare, 30)
	hit(bare, 30)
	check(#tally.hits == 3 and tally.hits[3].amount == 60 and tally.hits[3].killed == true and tally.enemies == 2 and tally.kills == 1, "an unplated enemy struck twice is still one entry")
end
rulingTests()

local function turnTests(): ()
	print(" enemies of one kind take turns")
	local kinds = config.crowd.kinds
	local function striking(id: number): boolean
		local state = seen(id).state
		return state == "windup" or state == "attack"
	end
	-- Steps `count` times; the most of `ids` that were winding up or attacking at once.
	local function watch(ids: { number }, count: number, each: (() -> ())?): number
		local most = 0
		for _ = 1, count do
			step2()
			local busy = 0
			for _, id in ids do
				if striking(id) then
					busy += 1
				end
			end
			most = math.max(most, busy)
			if each ~= nil then
				each()
			end
		end
		return most
	end
	local function trio(): { number }
		return {
			Crowd.Spawn("marksman", vec(-6, 0, 35), "fight"),
			Crowd.Spawn("marksman", vec(0, 0, 35), "fight"),
			Crowd.Spawn("marksman", vec(6, 0, 35), "fight"),
		}
	end

	-- The new key's floor, through the real Tuning.
	local RealTuning = load("Tuning")
	check(RealTuning.Validate("crowd.kinds.fodder.perPlayer", 2) and RealTuning.Validate("crowd.kinds.fodder.perPlayer", 0) and not RealTuning.Validate("crowd.kinds.fodder.perPlayer", -1), "Tuning: crowd.kinds.<k>.perPlayer is tunable and may not go below 0")
	check(not RealTuning.Validate("crowd.threat.attackersPerPlayer", 2), "and the old key is gone")

	-- No perPlayer, no cap: what the balance report found.
	fresh()
	Vitals.ToggleGod(player)
	local volley = trio()
	local together = watch(volley, 15 * 3)
	check(together == 3 and #struck == 3 and struck[1].at == struck[3].at, "a kind with no perPlayer is uncapped: three marksmen wind up and fire as one")

	-- perPlayer 1: one at a time.
	fresh()
	kinds.marksman.perPlayer = 1
	local turns = trio()
	local resting = false
	local most = watch(turns, 15 * 9, function()
		local recovering = false
		local winding = false
		for _, id in turns do
			local state = seen(id).state
			recovering = recovering or state == "recover"
			winding = winding or state == "windup"
		end
		resting = resting or (recovering and winding)
	end)
	local closest = math.huge
	local shooters = 0
	local fired: { [number]: boolean } = {}
	for index, strike in struck do
		if index > 1 then
			closest = math.min(closest, strike.at - struck[index - 1].at)
		end
		local from = math.floor(strike.origin.X + 0.5)
		if not fired[from] then
			fired[from] = true
			shooters += 1
		end
	end
	check(most == 1, `perPlayer 1: three marksmen on one player wind up one at a time (most at once: {most})`)
	check(#struck >= 5 and shooters == 3, `and each takes its turn ({#struck} lines in 9 s, from {shooters} marksmen)`)
	check(closest >= 1.2 - 1e-6, `their hits come as a rhythm: never closer than windup + strikeSeconds ({string.format("%.3f", closest)} s)`)
	check(near(struck[2].at - struck[1].at, 1.2, 1e-6) and near(struck[3].at - struck[2].at, 1.2, 1e-6), "a place freed in a step is taken in that step by a body walked after it")
	check(resting, "a recover holds no place: one winds up while another recovers")

	-- A place freed by a death or a cancelled windup is free at once.
	fresh()
	local line = trio()
	local function winding(): number?
		for _, id in line do
			if seen(id).state == "windup" then
				return id
			end
		end
		return nil
	end
	local first: number? = nil
	for _ = 1, 40 do
		step2()
		first = winding()
		if first ~= nil then
			break
		end
	end
	step2(3)
	kill(first :: number)
	step2(2)
	local second = winding()
	check(first ~= nil and second ~= nil and second ~= first, "a place freed by a death is taken within two steps, not after the dead one's attack")
	Crowd.Damage(second :: number, 5, 7, nil, nil)
	step2(2)
	local third = winding()
	check(third ~= nil and third ~= second and third ~= first, "and so is one freed by a cancelled windup")

	-- A second player has their own places.
	fresh()
	join2(vec(80, 3, 0))
	local mine = Crowd.Spawn("marksman", vec(0, 0, 35), "fight")
	local alsoMine = Crowd.Spawn("marksman", vec(6, 0, 35), "fight")
	local theirs = Crowd.Spawn("marksman", vec(80, 0, 35), "fight")
	local both = false
	local onMe = watch({ mine, alsoMine }, 15 * 4, function()
		both = both or (striking(theirs) and (striking(mine) or striking(alsoMine)))
	end)
	local aimedAt: { [number]: number } = {}
	for _, strike in struck do
		aimedAt[strike.targetUserId] = (aimedAt[strike.targetUserId] or 0) + 1
	end
	check(onMe == 1 and both, "a second player gets their own places: a marksman on each winds up at the same time, never two on one")
	check((aimedAt[7] or 0) >= 1 and (aimedAt[8] or 0) >= 1, "(both players were fired at)")
	leave2()

	-- Places are per kind.
	fresh()
	kinds.slinger.perPlayer = 1
	kinds.lobber.perPlayer = 1
	local mixed = {
		Crowd.Spawn("slinger", vec(0, 0, 25), "fight"),
		Crowd.Spawn("lobber", vec(0, 0, 30), "fight"),
		Crowd.Spawn("marksman", vec(0, 0, 35), "fight"),
	}
	check(watch(mixed, 15 * 2) == 3, "places are per kind: a slinger, a lobber and a marksman wind up on one player at once")

	-- A shot in the air holds no place.
	fresh()
	local pair = { Crowd.Spawn("slinger", vec(-6, 0, 25), "fight"), Crowd.Spawn("slinger", vec(6, 0, 25), "fight") }
	local underFire = false
	local slingers = watch(pair, 15 * 6, function()
		local windingUp = seen(pair[1]).state == "windup" or seen(pair[2]).state == "windup"
		underFire = underFire or (Field.ShotsAlive() >= 1 and windingUp)
	end)
	check(slingers == 1 and #of(log, "enemyShot") >= 3, `two slingers at perPlayer 1 take turns ({#of(log, "enemyShot")} shots in 6 s)`)
	check(underFire, "a shot in the air does not hold its slinger's place: the next one winds up under it")

	-- A brute holds its place through its charge.
	fresh()
	kinds.brute.perPlayer = 1
	local brutes = { Crowd.Spawn("brute", vec(-8, 0, 20), "fight"), Crowd.Spawn("brute", vec(8, 0, 20), "fight") }
	local charged = false
	local bulls = watch(brutes, 15 * 5, function()
		charged = charged or seen(brutes[1]).state == "attack" or seen(brutes[2]).state == "attack"
	end)
	check(bulls == 1 and charged and #struck >= 2, `a brute holds its place through its charge: the second winds up only when the first has run ({#struck} charges)`)
	Vitals.ToggleGod(player)

	-- Fodder is the same rule with more places (the brain alone, as in wave 1).
	for _, cap in { 2, 4 } do
		kinds.fodder.perPlayer = cap
		local sim = newSim()
		sim.now = 5
		table.insert(sim.targets, { userId = 77, position = vec(0, 3, 0) })
		for index = 1, 16 do
			local angle = index / 16 * 2 * math.pi
			local body = spawn(sim, "fodder", math.cos(angle) * 4, math.sin(angle) * 4)
			body.mind.bornAt = 0
		end
		local busiest = 0
		for _ = 1, 15 * 4 do
			stepSim(sim)
			local busy = 0
			for _, body in sim.bodies do
				if body.mind.phase == "windup" or body.mind.phase == "attack" then
					busy += 1
				end
			end
			busiest = math.max(busiest, busy)
		end
		check(busiest == cap, `fodder at perPlayer {cap}: {busiest} lunge at once`)
	end
	kinds.fodder.perPlayer = 4
	kinds.marksman.perPlayer = nil
	kinds.slinger.perPlayer = nil
	kinds.lobber.perPlayer = nil
	kinds.brute.perPlayer = nil
end
turnTests()

local function lagTests(): ()
	print(" a shot is led over its flight plus the player's lag")
	local attack = config.crowd.kinds.slinger.attacks[1]
	local ping = 0.05
	player.GetNetworkPing = function()
		return ping
	end
	attack.lead = 1
	attack.radius = 0.5
	-- A strafer at `pace` studs a second from x = `start`, from the windup's start until well
	-- after the shot.
	local function strafe(netPing: number, allowance: number, pace: number, start: number): (any, any, number)
		fresh()
		ping = netPing
		config.shooting.originLagSeconds = allowance
		local id = Crowd.Spawn("slinger", vec(0, 0, 25), "fight")
		waitFor(id, "windup", 40)
		root.Position = vec(start, 3, 0)
		local x = start
		local shot: any = nil
		local firedAt = vec(start, 3, 0)
		for _ = 1, 50 do
			x += pace * DT
			root.Position = vec(x, 3, 0)
			step2()
			if shot == nil then
				shot = of(log, "enemyShot")[1]
				if shot ~= nil then
					firedAt = vec(x, 3, 0)
					kill(id)
				end
			end
		end
		return shot, firedAt, humanoid.Health
	end
	for _, case in { { 0, 0, 0 }, { 0.05, 0.05, 0.1 }, { 0.1, 0.05, 0.15 }, { 0.5, 0.05, 0.3 } } do
		local shot, at, health = strafe(case[1], case[2], 8, 0)
		local lag = case[3]
		local aim = at
		for _ = 1, PASSES do
			aim = at + vec(8, 0, 0) * ((aim - shot.from).Magnitude / 28 + lag)
		end
		local ms = math.floor(lag * 1000 + 0.5)
		check(shot ~= nil and near((shot.velocity.Unit - (aim - shot.from).Unit).Magnitude, 0, 1e-6), `at {ms} ms lag the aim leads a strafer over the flight plus that lag (ping {case[1]}, allowance {case[2]}, ceiling 0.3)`)
		check(health == 118, `and the shot lands on them (radius 0.5; led over the flight alone it would trail by {string.format("%.1f", 8 * lag)} studs)`)
	end
	-- Six passes: `lead` 1 is where they will be, also at walk speed. The strafer crosses in
	-- front of the slinger and is 25 studs from it when the shot leaves; two passes left the
	-- shot 1.8 to 2.6 studs behind them.
	for _, case in { { 0, 0, 0 }, { 0.05, 0.05, 0.1 }, { 0.1, 0.05, 0.15 } } do
		local shot, at, health = strafe(case[1], case[2], 20, -12)
		local lag = case[3]
		local aim = at
		for _ = 1, PASSES do
			aim = at + vec(20, 0, 0) * ((aim - shot.from).Magnitude / 28 + lag)
		end
		-- How close the shot comes to the root it is judged against (the root a lag later).
		local toRoot = at + vec(20, 0, 0) * lag - shot.from
		local closing = vec(20, 0, 0) - shot.velocity
		local when = math.max(-(toRoot.X * closing.X + toRoot.Y * closing.Y + toRoot.Z * closing.Z) / (closing.Magnitude ^ 2), 0)
		local gap = (toRoot + closing * when).Magnitude
		local ms = math.floor(lag * 1000 + 0.5)
		check(shot ~= nil and near(at.X, 0, 1e-6) and near((shot.velocity.Unit - (aim - shot.from).Unit).Magnitude, 0, 1e-6), `a walk-speed strafer at {ms} ms lag: the aim is the six-pass one`)
		check(health == 118 and gap < 0.3, `and the shot lands on them: it passes {string.format("%.2f", gap)} studs from the root it is judged against (radius 0.5)`)
	end
	attack.lead = 0.7
	attack.radius = 1.0
	config.shooting.originLagSeconds = 0.05
	ping = 0.05
end
lagTests()

local function budgetTests(): ()
	print(" the fight set")
	fresh()
	root.Position = vec(0, 3, 0)
	local grid = 0
	for index = 1, 100 do
		grid += 1
		Crowd.Spawn("fodder", vec(((index - 1) % 10 - 4.5) * 3, 0, 45 + (index - 1) // 10 * 3), "fight")
	end
	for index = 1, 3 do
		Crowd.Spawn("slinger", vec(-30 + index * 6, 0, 70), "fight")
		Crowd.Spawn("marksman", vec(index * 6, 0, 85), "fight")
		Crowd.Spawn("brute", vec(-40 + index * 12, 0, 50), "fight")
		Crowd.Spawn("plated", vec(30 + index * 8, 0, 50), "idle")
	end
	Crowd.Spawn("lobber", vec(24, 0, 70), "fight")
	Crowd.Spawn("lobber", vec(30, 0, 70), "fight")
	Vitals.ToggleGod(player)
	local worst = 0
	local total = 0
	local mostRays = 0
	local fewestRays = 0
	local shapes: { [string]: number } = {}
	local steps = 15 * 12
	for _ = 1, steps do
		local had = rays
		local linesBefore = (shapes.line or 0) + (shapes.shot or 0) + (shapes.lob or 0)
		local began = os.clock()
		step2()
		local took = (os.clock() - began) * 1000
		for _, strike in struck do
			shapes[strike.def.shape] = (shapes[strike.def.shape] or 0) + 1
		end
		table.clear(struck)
		worst = math.max(worst, took)
		total += took
		-- The budget: one ray per shot, line and lob, at its impact; none per step.
		local allowed = (shapes.line or 0) + (shapes.shot or 0) + (shapes.lob or 0) - linesBefore
		mostRays = math.max(mostRays, rays - had - allowed)
		fewestRays = math.min(fewestRays, rays - had - allowed)
	end
	Vitals.ToggleGod(player)
	check(mostRays == 0 and fewestRays == 0, "the raycast budget holds with all 114 fighting: exactly one ray per shot, line and lob, at its impact, and none per step")
	check((shapes.lunge or 0) > 0 and (shapes.shot or 0) > 0 and (shapes.line or 0) > 0 and (shapes.lob or 0) > 0 and (shapes.lane or 0) > 0, "every role attacks in the full set")
	print(`  note  114 enemies under the plain interpreter with a table Vector3: {string.format("%.2f", total / steps)} ms a step on average, {string.format("%.2f", worst)} ms at worst (not Studio's number)`)
end
budgetTests()

