--!strict
-- Enemy attacks that travel (docs/INTERFACES.md "P4 contracts" -> "Wave 2 — roles" and its
-- review round, and "Stop 2 - the Colossus"): a slinger's `shot`, a brute's `lane` charge and
-- a boss's `ring`. An instant shape (a lunge, an arc, a line, a lob's landing) is frozen once
-- and judged once per player by VitalsService. These move, so they are judged every crowd step
-- instead, by the same commit rule turned round: the player's root now against where the shot,
-- the charging body or the ring's front was `lag` ago.
-- Each test sweeps the stretch it travelled since the last step, so nothing slips between two
-- steps, and reports the moment within that stretch at which it first reached the root: that
-- moment is the contact's impact time (what an i-frame must have covered, and when a downed
-- player was down).
--
-- This module owns no player. VitalsService hands in who is standing where for the step and
-- gets back, through `judge`, every contact to settle like any other hit, and every aimed miss
-- (ruling 26: the moment the attack reaches the point it was aimed at without having touched
-- its target).
--
-- It also holds the world queries of enemy attacks, one ray each and none per step: the world
-- is static, so a shot's whole path is cut once, when it is fired (Fire), a marksman's line at
-- its impact (Reach), and a lob finds the surface under its target (Below). Nothing here yields.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local CrowdBrain = require(script.Parent:WaitForChild("CrowdBrain"))

type Strike = CrowdBrain.Strike

-- A player on their feet this step: the root, the feet's height, and how far the server's copy
-- of them trails their own screen.
export type Standing = {
	player: Player,
	userId: number,
	position: Vector3,
	feetY: number,
	lag: number,
}
-- What VitalsService made of one player and one attack: it landed, or it was voided and they
-- were told so. nil = nothing was sent (down, gone, or a miss that is nobody's dodge).
export type Verdict = "landed" | "dodged"
-- held = the attack touched them; false = it passed the point it was aimed at without doing so.
export type Judge = (strike: Strike, player: Player, impactAt: number, held: boolean) -> Verdict?
export type Raise = (fx: Types.CombatFx) -> ()

type Shot = {
	id: number,
	strike: Strike,
	direction: Vector3,
	speed: number,
	radius: number,
	-- os.clock() at which the flight ends: its time, or the world geometry on its path, known
	-- from the one ray cast when it was fired.
	endsAt: number,
	-- os.clock() at which it reaches the point it was aimed at.
	aimAt: number,
	-- Still in the air. Once it is not, players are still judged against the flight it had,
	-- each at their own lag, before the record goes.
	flying: boolean,
	-- Players this shot has already sent an effect to: one attack, one effect each.
	done: { [number]: boolean },
	-- The aimed miss has been judged, or can no longer happen.
	missed: boolean,
}
type Charge = {
	strike: Strike,
	speed: number,
	-- os.clock(): when the body has run its length, and when it passes the point it was aimed at.
	endAt: number,
	aimAt: number,
	done: { [number]: boolean },
	missed: boolean,
}

-- A shockwave on the ground: its front left `strike.origin` at the strike's time and grows at
-- `speed` until it is `radius` out. The front is a band `halfWidth` either side of that.
type Ring = {
	strike: Strike,
	speed: number,
	radius: number,
	halfWidth: number,
	-- os.clock(): when the front is `radius` out, and when it passes where its target stood.
	endAt: number,
	aimAt: number,
	done: { [number]: boolean },
	missed: boolean,
}

local EPSILON = 1e-4
-- No ray of an enemy attack needs to be longer than this (the engine refuses very long ones):
-- a line aimed steeply up would otherwise ask for one.
local MAX_RAY_STUDS = 1000
local DOWN = Vector3.new(0, -1, 0)
-- A barrage's scattered circles come down from the sky: each lands on the first thing under
-- it from this far above the crowd's floor, which no range furniture reaches.
local SKY_STUDS = 100

local shots: { Shot } = {}
local charges: { Charge } = {}
local rings: { Ring } = {}
-- Shots still in flight.
local flying = 0
local lastId = 0
-- os.clock() of the last Step: where this step's sweeps begin.
local lastStepAt = 0
-- Scratch: the players one shot touched in one step, and when it reached each.
local touched: { Standing } = {}
local touchedAt: { [Standing]: number } = {}
-- Crowd enemies have no Instances, so a world query only has to skip the players. One params
-- object and one list serve every query.
local worldRay = RaycastParams.new()
worldRay.FilterType = Enum.RaycastFilterType.Exclude
worldRay.RespectCanCollide = true
local ignored: { Instance } = {}

local ThreatField = {}

local function world(): RaycastParams
	table.clear(ignored)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignored, character)
		end
	end
	worldRay.FilterDescendantsInstances = ignored
	return worldRay
end

local function shotAt(shot: Shot, clock: number): Vector3
	return shot.strike.origin + shot.direction * (shot.speed * (clock - shot.strike.at))
end

-- The charging body's centre at `clock`: on its lane, never past the end of its run.
local function chargeAt(charge: Charge, clock: number): Vector3
	local strike = charge.strike
	local run = math.clamp(charge.speed * (clock - strike.at), 0, strike.length or 0)
	return strike.origin + strike.facing * run
end

-- When something of `radius` that set out from `from` at `clock` and travelled to `to`, at
-- `speed`, first reached `point`; nil = it never did on that stretch.
local function reachedAt(
	from: Vector3,
	to: Vector3,
	radius: number,
	point: Vector3,
	clock: number,
	speed: number
): number?
	local stretch = to - from
	local length = stretch.Magnitude
	if length < EPSILON then
		return if (point - from).Magnitude <= radius then clock else nil
	end
	local entry = HitShapes.Ray(from, stretch, length, 2 * radius, 0, point, 0)
	return if entry ~= nil then clock + entry / speed else nil
end

-- Ruling 26 for an attack that travels: once the player it was aimed at has seen it reach the
-- point it was aimed at (their lag after `aimAt`) without it having sent them anything, they
-- are asked whether that was a dodge. Judged once. An attack that ended before that point
-- (cover, another player, the arena's edge, a kill) was dodged by nobody.
local function aimedMiss(
	strike: Strike,
	done: { [number]: boolean },
	aimAt: number,
	endedAt: number,
	now: number,
	standing: { Standing },
	maxLag: number,
	judge: Judge
): boolean
	if endedAt < aimAt then
		return true
	end
	local aimedAt = strike.targetUserId
	for _, who in standing do
		if who.userId == aimedAt then
			if now - who.lag < aimAt then
				return false
			end
			if not done[aimedAt] and judge(strike, who.player, aimAt, false) ~= nil then
				done[aimedAt] = true
			end
			return true
		end
	end
	-- Not on their feet: once every lag has passed there is nobody left to ask.
	return now - maxLag >= aimAt
end

-- One shot's step. Returns false when its record can go.
local function stepShot(
	shot: Shot,
	now: number,
	before: number,
	standing: { Standing },
	maxLag: number,
	judge: Judge,
	raise: Raise
): boolean
	local strike = shot.strike
	local firedAt = strike.at
	local endsAt = shot.endsAt
	if shot.flying and now >= endsAt then
		-- Its time, or the wall its one ray found: it ends without a word. Every client was told
		-- how long it flies and fizzles it on its own clock.
		shot.flying = false
		flying -= 1
	end

	-- Each player's root now against the stretch the shot flew, as it was their lag ago.
	table.clear(touched)
	table.clear(touchedAt)
	for _, who in standing do
		if shot.done[who.userId] then
			continue
		end
		local to = math.min(now - who.lag, endsAt)
		local from = math.max(before - who.lag, firedAt)
		if to < from then
			continue
		end
		local reached = reachedAt(
			shotAt(shot, from),
			shotAt(shot, to),
			shot.radius,
			who.position,
			from,
			shot.speed
		)
		if reached ~= nil then
			table.insert(touched, who)
			touchedAt[who] = reached
		end
	end
	if #touched > 1 then
		-- It stops in the first player it reached, not the first in the list.
		table.sort(touched, function(a: Standing, b: Standing): boolean
			return touchedAt[a] < touchedAt[b]
		end)
	end
	for _, who in touched do
		local verdict = judge(strike, who.player, touchedAt[who], true)
		if verdict ~= nil then
			shot.done[who.userId] = true
		end
		if verdict == "landed" then
			-- A hit a dodge or `god` voided lets the shot fly on; the one that lands ends it,
			-- and that end is told: the clients would fly the orb on for the rest of its time.
			if shot.flying then
				flying -= 1
				local along = math.max((who.position - strike.origin):Dot(shot.direction), 0)
				raise({
					kind = "enemyShotEnd",
					id = shot.id,
					at = strike.origin + shot.direction * along,
					hit = true,
				})
			end
			return false
		end
	end

	if not shot.missed then
		shot.missed = aimedMiss(strike, shot.done, shot.aimAt, endsAt, now, standing, maxLag, judge)
	end
	return now - maxLag < endsAt
end

-- One charge's step. The body hits every player it runs over, each once. Returns false when
-- its record can go.
local function stepCharge(
	charge: Charge,
	now: number,
	before: number,
	standing: { Standing },
	maxLag: number,
	judge: Judge
): boolean
	local strike = charge.strike
	local attack = strike.def
	-- A kill ends the charge where the body was.
	local endAt = math.min(charge.endAt, strike.endedAt or math.huge)
	local halfWidth = math.max(attack.width or 0, 0) / 2
	local height = attack.height
	local level = strike.origin.Y
	for _, who in standing do
		if charge.done[who.userId] then
			continue
		end
		local to = math.min(now - who.lag, endAt)
		local from = math.max(before - who.lag, strike.at)
		if to < from or (height ~= nil and who.feetY - strike.floorY > height) then
			continue
		end
		-- On the flat: the body's centre against the root, both at the lane's own level.
		local root = Vector3.new(who.position.X, level, who.position.Z)
		local reached = reachedAt(
			chargeAt(charge, from),
			chargeAt(charge, to),
			halfWidth,
			root,
			from,
			charge.speed
		)
		if reached ~= nil and judge(strike, who.player, reached, true) ~= nil then
			charge.done[who.userId] = true
		end
	end
	if not charge.missed then
		charge.missed =
			aimedMiss(strike, charge.done, charge.aimAt, endAt, now, standing, maxLag, judge)
	end
	return now - maxLag < endAt
end

-- One ring's step. Its front hits every player it passes on the ground, each once: a player
-- is in its way while they stand within `radius` of where it left, and it reaches them when
-- its band does. Returns false when its record can go.
local function stepRing(
	ring: Ring,
	now: number,
	before: number,
	standing: { Standing },
	maxLag: number,
	judge: Judge
): boolean
	local strike = ring.strike
	local origin = strike.origin
	local height = strike.def.height
	local speed = ring.speed
	local halfWidth = ring.halfWidth
	local leftAt = strike.at
	local endAt = ring.endAt
	for _, who in standing do
		if ring.done[who.userId] then
			continue
		end
		local to = math.min(now - who.lag, endAt)
		local from = math.max(before - who.lag, leftAt)
		if to < from or (height ~= nil and who.feetY - strike.floorY > height) then
			continue
		end
		local dx = who.position.X - origin.X
		local dz = who.position.Z - origin.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance > ring.radius then
			continue
		end
		-- The band covers their distance from the moment its leading edge gets there until its
		-- trailing edge has passed.
		local reached = leftAt + (distance - halfWidth) / speed
		local passed = leftAt + (distance + halfWidth) / speed
		if passed < from or reached > to then
			continue
		end
		if judge(strike, who.player, math.max(reached, from), true) ~= nil then
			ring.done[who.userId] = true
		end
	end
	if not ring.missed then
		ring.missed = aimedMiss(strike, ring.done, ring.aimAt, endAt, now, standing, maxLag, judge)
	end
	return now - maxLag < endAt
end

-- Keeps the records `step` still wants, in order, without a new table.
local function sweep<T>(list: { T }, step: (item: T) -> boolean): ()
	local count = #list
	local kept = 0
	for index = 1, count do
		local item = list[index]
		if step(item) then
			kept += 1
			list[kept] = item
		end
	end
	for index = kept + 1, count do
		list[index] = nil
	end
end

-- A marksman's line, its one ray. It is cast in 3D at the body the line locked on (`aim`), not
-- level at the marksman's chest: the block that body stands on then does not cut the lane in
-- front of it, and a wall between the two still does. Returns how far the lane runs on the flat
-- before world geometry stops it, at most `range`. `facing` = the lane's flat unit heading,
-- used when there is no body to aim at.
function ThreatField.Reach(origin: Vector3, aim: Vector3?, facing: Vector3, range: number): number
	if range <= 0 then
		return 0
	end
	local toward = if aim ~= nil then aim - origin else facing
	local length = toward.Magnitude
	local flat = math.sqrt(toward.X * toward.X + toward.Z * toward.Z)
	if flat < EPSILON then
		-- Straight up or down: there is no lane to cut that way.
		toward, length, flat = facing, 1, 1
	end
	-- Long enough to cover `range` on the flat.
	local cast = math.min(range / flat * length, MAX_RAY_STUDS)
	local result = Workspace:Raycast(origin, toward * (cast / length), world())
	if result == nil then
		return range
	end
	local reached = result.Position - origin
	return math.min(math.sqrt(reached.X * reached.X + reached.Z * reached.Z), range)
end

-- The surface under `point` (a lob's target at the throw): one ray straight down, world
-- geometry only. The crowd's floor, at `floorY`, when it finds nothing.
function ThreatField.Below(point: Vector3, floorY: number): Vector3
	local result = Workspace:Raycast(point, DOWN * HitShapes.GROUND_PROBE_DEPTH, world())
	return if result ~= nil then result.Position else Vector3.new(point.X, floorY, point.Z)
end

-- Where a barrage's scattered circle lands: the highest surface at `point` (a ray from the
-- sky, world geometry only), so one that falls on a block lies on the block's top. Its target
-- was not there, so there is no root to probe from as Below does. The crowd's floor, at
-- `floorY`, when it finds nothing.
function ThreatField.Landing(point: Vector3, floorY: number): Vector3
	local from = Vector3.new(point.X, floorY + SKY_STUDS, point.Z)
	local reach = SKY_STUDS + HitShapes.GROUND_PROBE_DEPTH
	local result = Workspace:Raycast(from, DOWN * reach, world())
	return if result ~= nil then result.Position else Vector3.new(point.X, floorY, point.Z)
end

-- A fresh id for an enemy shot or a ground area: one counter, so no two effects share one.
function ThreatField.NextId(): number
	lastId += 1
	return lastId
end

-- A slinger's shot leaves at the strike's time, from its origin toward its aim. Its one ray is
-- cast here, along the whole path: what it meets cuts the flight short, and the `seconds` sent
-- is the cut one, so every client ends the orb at the wall on its own clock. Returns the
-- effect that announces it (`serverOffset` = server time minus os.clock()), or nil for a shot
-- that could never fly.
function ThreatField.Fire(strike: Strike, serverOffset: number): Types.CombatFxEnemyShot?
	local attack = strike.def
	local speed = attack.speed or 0
	local seconds = attack.seconds or 0
	if speed <= 0 or seconds <= 0 then
		return nil
	end
	local reach = if strike.aim ~= nil then strike.aim - strike.origin else strike.facing
	local direction = if reach.Magnitude > EPSILON then reach.Unit else strike.facing
	local path = math.min(speed * seconds, MAX_RAY_STUDS)
	local result = Workspace:Raycast(strike.origin, direction * path, world())
	if result ~= nil then
		seconds = (result.Position - strike.origin).Magnitude / speed
	end
	local shot: Shot = {
		id = ThreatField.NextId(),
		strike = strike,
		direction = direction,
		speed = speed,
		radius = math.max(attack.radius or 0, 0),
		endsAt = strike.at + seconds,
		aimAt = strike.at + (if strike.aim ~= nil then reach.Magnitude / speed else seconds),
		flying = true,
		done = {},
		missed = false,
	}
	table.insert(shots, shot)
	flying += 1
	return {
		kind = "enemyShot",
		id = shot.id,
		enemyKind = strike.enemyKind,
		enemyId = strike.bodyId,
		from = strike.origin,
		velocity = direction * speed,
		radius = shot.radius,
		firedAt = strike.at + serverOffset,
		seconds = seconds,
	}
end

-- A brute's charge begins at the strike's time. The brain carries the body; this judges it.
function ThreatField.Charge(strike: Strike): ()
	local speed = strike.def.speed or 0
	local length = strike.length or 0
	local feet = strike.feet
	if speed <= 0 or length <= 0 or feet == nil then
		return
	end
	-- It was aimed at where its target stood when the windup locked the facing.
	local toAim = if strike.aim ~= nil then strike.aim - feet else Vector3.zero
	local along = math.clamp(toAim.X * strike.facing.X + toAim.Z * strike.facing.Z, 0, length)
	table.insert(charges, {
		strike = strike,
		speed = speed,
		endAt = strike.at + length / speed,
		aimAt = strike.at + along / speed,
		done = {},
		missed = false,
	})
end

-- A boss's ring leaves its feet at the strike's time. The body stays where it is; this judges
-- the front as it grows.
function ThreatField.Ring(strike: Strike): ()
	local attack = strike.def
	local speed = attack.speed or 0
	local radius = math.max(attack.radius or 0, 0)
	if speed <= 0 or radius <= 0 then
		return
	end
	-- Ruling 26: it was aimed at where its target stood when the windup began.
	local toAim = if strike.aim ~= nil then strike.aim - strike.origin else Vector3.zero
	local aimed = math.sqrt(toAim.X * toAim.X + toAim.Z * toAim.Z)
	table.insert(rings, {
		strike = strike,
		speed = speed,
		radius = radius,
		halfWidth = math.max(attack.width or 0, 0) / 2,
		endAt = strike.at + radius / speed,
		aimAt = strike.at + aimed / speed,
		done = {},
		missed = false,
	})
end

-- Is there anything in the air or on the run? (Step is not worth calling otherwise.)
function ThreatField.Busy(): boolean
	return #shots > 0 or #charges > 0 or #rings > 0
end

-- Enemy shots still flying: the brain's cap counts these.
function ThreatField.ShotsAlive(): number
	return flying
end

-- One crowd step: `now` = the frame's os.clock(), `standing` = the players on their feet,
-- `maxLag` = the longest lag any of them is judged at.
function ThreatField.Step(
	now: number,
	standing: { Standing },
	maxLag: number,
	judge: Judge,
	raise: Raise
): ()
	local before = lastStepAt
	lastStepAt = now
	local shotCount = #shots
	if shotCount > 0 then
		local kept = 0
		for index = 1, shotCount do
			local shot = shots[index]
			if stepShot(shot, now, before, standing, maxLag, judge, raise) then
				kept += 1
				shots[kept] = shot
			end
		end
		for index = kept + 1, shotCount do
			shots[index] = nil
		end
	end
	local chargeCount = #charges
	if chargeCount > 0 then
		local kept = 0
		for index = 1, chargeCount do
			local charge = charges[index]
			if stepCharge(charge, now, before, standing, maxLag, judge) then
				kept += 1
				charges[kept] = charge
			end
		end
		for index = kept + 1, chargeCount do
			charges[index] = nil
		end
	end
	local ringCount = #rings
	if ringCount > 0 then
		local kept = 0
		for index = 1, ringCount do
			local ring = rings[index]
			if stepRing(ring, now, before, standing, maxLag, judge) then
				kept += 1
				rings[kept] = ring
			end
		end
		for index = kept + 1, ringCount do
			rings[index] = nil
		end
	end
end

-- The bodies in `ids` are gone for good (a boss has died, and what it summoned with it): their
-- shots, charges and rings end here and hit nobody. A shot in the air is told, as at a set load.
function ThreatField.Drop(ids: { [number]: boolean }, raise: Raise): ()
	local now = os.clock()
	sweep(shots, function(shot: Shot): boolean
		if not ids[shot.strike.bodyId] then
			return true
		end
		if shot.flying then
			flying -= 1
			raise({
				kind = "enemyShotEnd",
				id = shot.id,
				at = shotAt(shot, math.min(now, shot.endsAt)),
				hit = false,
			})
		end
		return false
	end)
	sweep(charges, function(charge: Charge): boolean
		return not ids[charge.strike.bodyId]
	end)
	sweep(rings, function(ring: Ring): boolean
		return not ids[ring.strike.bodyId]
	end)
end

-- A dummy set was loaded: every shot in the air ends where it is, and is told (the clients
-- would fly it on), and every charge is forgotten.
function ThreatField.Clear(raise: Raise): ()
	local now = os.clock()
	for _, shot in shots do
		if shot.flying then
			raise({
				kind = "enemyShotEnd",
				id = shot.id,
				at = shotAt(shot, math.min(now, shot.endsAt)),
				hit = false,
			})
		end
	end
	table.clear(shots)
	table.clear(charges)
	table.clear(rings)
	flying = 0
end

return ThreatField
