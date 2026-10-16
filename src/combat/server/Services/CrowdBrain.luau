--!strict
-- The AI of crowd enemies that fight (docs/INTERFACES.md "P4 contracts" and its "Wave 2 —
-- roles"; docs/COMBAT_DESIGN.md §7). Only an enemy whose group's behaviour is `fight` has a
-- mind. CrowdService calls Think for it inside the crowd step, in place of the passive steering,
-- and hands over its record by reference (CrowdService.Get would allocate a view per enemy per
-- step).
--
-- One attack is a fixed timeline: windup (the tell: the body stands, its facing locked) ->
-- impact (the attack is frozen and queued as a Strike) -> attack (the visible thrust,
-- crowd.threat.strikeSeconds; a lane's charge, range / speed) -> recover (exposed,
-- attack.recover) -> approach. Every client draws the tells from the snapshot alone and times
-- them with the same config numbers, so the durations here are exact: a phase ends at phaseUntil
-- whichever step notices it, and the next phase is measured from that moment, not from the
-- step. Only a cancelling hit or death ends a windup early: a stagger or a hop from a hit that
-- does not cancel leaves its clock running. And only before its impact time: once that has come
-- the blow is owed, because every client has drawn it, even if the step that would notice it
-- has not run yet (ruling 22).
--
-- The brain's clock is os.clock() as CrowdService read it for the frame, the same moment it
-- stamps that frame's snapshot with. A windup's impact is therefore exactly the stamp of the
-- first snapshot that shows it + windup, also when one frame runs several catch-up steps.
--
-- Two brains. `rush` closes until its shortest attack reaches and stands through its recover.
-- `keepAway` holds bandMin..bandMax from its target, also while it recovers, and keeps facing
-- it. Eight shapes: lunge, arc and line are judged from the Strike alone; a shot and a lob carry
-- the point they were aimed at; a lane is a charge, and the brain carries the body down it; a
-- ring leaves the body's feet and travels on by itself; a summon only names its summoner.
--
-- Stop 2 ("Stop 2 - the Colossus"). An enemy with several attacks takes, among those off their
-- cooldown, in reach and allowed in its phase, the one it used longest ago (choose). A kind with
-- `enrage` enters its second phase for good once its health share, as the snapshot carries it,
-- is at or under `enrage.at`: asked whenever it is about to choose an attack and whenever an
-- attack state ends, never inside a windup or an attack. Enraged, windups and recovers are
-- scaled, `enraged` attacks unlock, and up to `chain` attacks follow each other with no recover
-- between them (the attack the phase began in is not the first of a chain: it recovers). The
-- client reads the same phase off the same byte: it latches it at the first snapshot whose
-- share is at or under `enrage.at` while the body is not in a windup or an attack, or is in a
-- windup it was not in the snapshot before.
--
-- Stop 3 ("Stop 3 - the Warlord and his guard"). An attack marked `calm` is only chosen before
-- the second phase, the mirror of `enraged`; one with `uses` lands at most that often in the
-- body's life (usable). Enraged, a kind with `enrage.brain` moves by that brain instead of its
-- own: a commander who kept away closes in.
--
-- L1b ("L1b contracts — the living road", ruling L1b-1): the crowd has a list of floors, one per
-- camp, and every body stands on its own (Body.floor). Its ground shapes lie on that floor, a
-- retreat and a charge stop at that floor's edge, and a falling target is led down to it. A
-- camp's resident in a fight goes only for the targets in play for its group (Think's `allowed`).
-- L1b Wave 4 (L1b-W4-17): a floor with a chase region cuts a retreat and a charge at the region's
-- edge (Region.Clamp, Region.Runway), so a raider's run carries on through a door onto the road;
-- `allowed` is its group's known set.
--
-- Rules that shape the module:
-- * Nothing here yields, raycasts or builds a path: the crowd ignores world geometry (ruling 15).
-- * A Strike is only queued. CrowdService drains the queue after its step, so nothing a hit
--   does can reach back into a step that is still walking the crowd.
-- * Numbers come from the config CrowdService read for the step. An attack's own def is frozen
--   when its windup starts, so a slider applies to the next attack, never to one in the air.
-- * A fodder's step must stay cheap (a hundred of them fight at once): what only a shooter or a
--   brute needs is behind a test of its attack's shape.
-- * tools/sim_range.py mirrors these rules one by one (its "P4 threat" section): change both.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local CrowdCodec = require(sharedFolder:WaitForChild("CrowdCodec"))
local Region = require(sharedFolder:WaitForChild("Region"))

type CrowdConfig = typeof((({} :: any) :: Types.ProvingGroundsConfig).crowd)
type ThreatConfig = typeof((({} :: any) :: CrowdConfig).threat)

export type Phase = "approach" | "windup" | "attack" | "recover"

-- One enemy attack at its impact: everything needed to judge it later, with nothing left
-- pointing at the enemy (which may be dead or gone by then).
export type Strike = {
	-- os.clock() of the impact: the T of the commit rule. (VitalsService moves a lob's on to
	-- its landing.)
	at: number,
	enemyKind: string,
	-- The attacker's crowd id. It is never followed back to a record to judge the attack: it
	-- names the summoner of a `summon`, and lets a boss's death take its attacks with it.
	bodyId: number,
	-- 1-based index into the kind's `attacks`.
	attack: number,
	def: Types.CrowdAttackDef,
	-- The player the attack was aimed at: the brain's target when the windup started. The
	-- shape may still catch someone else; only this player can be said to have dodged it.
	targetUserId: number,
	-- The attacker's body centre: the shape's origin.
	origin: Vector3,
	-- The floor a ground shape lies on. It is the top of the attacker's own floor (L1b-1), not
	-- its feet: a hit that did not cancel the windup may have it in the air at the impact.
	floorY: number,
	-- Flat unit heading: as locked for a lunge, an arc, a line and a lane; the way a shot
	-- flies and a lob was thrown.
	facing: Vector3,
	-- shot: the point it flies at (the led aim). lob: its target's root at the throw, which
	-- VitalsService drops to the surface below: where the circle lands. line: the body it
	-- locked on (its one ray is cast at it). lane and ring: where its target stood when the
	-- windup began.
	aim: Vector3?,
	-- lane: the body's feet when the charge began.
	feet: Vector3?,
	-- A barrage's circles share this: the players one of them has already sent an effect to.
	volley: { [number]: boolean }?,
	-- lane: how far the charge really runs (cut short at the arena's edge). line: how far it
	-- reaches before world geometry stops it (VitalsService fills that in at the impact).
	length: number?,
	-- lane: os.clock() at which the charging body was killed, which ends the charge.
	endedAt: number?,
}

export type Mind = {
	phase: Phase,
	-- os.clock() at which the phase ends; a windup's end is its impact. Unused while approaching.
	phaseUntil: number,
	-- 1-based index into the kind's `attacks` from the windup's start to the recover's end; 0
	-- while approaching.
	attack: number,
	-- That attack, frozen at the windup's start.
	def: Types.CrowdAttackDef?,
	-- The player the windup was started against: its kind's places are counted per target.
	targetUserId: number,
	-- Flat unit heading. It follows the target while the body is free, and is locked from the
	-- windup's start (a line: from its lock) until a rusher's recover ends.
	facing: Vector3,
	bornAt: number,
	-- line: the facing has been frozen (T - lockSeconds has come).
	locked: boolean,
	-- The target's root as last seen during the windup: what a shot or a lob falls back on when
	-- the target is gone at the impact, and where a lane was aimed.
	aim: Vector3,
	-- lane: the charge under way. The Strike is shared with whoever judges it, so a kill can
	-- end the charge by writing its endedAt.
	charge: Strike?,
	-- keepAway: the body keeps facing its target while it walks.
	watch: boolean,
	-- os.clock() of each attack's last impact, by its index: its cooldown runs from there, and
	-- the one used longest ago is chosen first.
	usedAt: { number },
	-- The attack the last windup was for: not chosen again while another is ready.
	last: number,
	-- How often each attack has landed, by its index: `uses` is counted at the impact.
	landed: { number },
	-- The second phase (the kind's `enrage`), entered for good.
	enraged: boolean,
	-- How many attacks the chain under way has started; a fresh windup is the first.
	chained: number,
}

-- The fields of a CrowdService enemy record that the brain reads. `position` is the feet.
-- `floor` = its index in the crowd's floor list (SetFloors).
export type Body = {
	id: number,
	kind: string,
	position: Vector3,
	hp: number,
	maxHp: number,
	plate: number,
	floor: number,
}

-- A player the fighting crowd may go for, kept from step to step so their motion can be read.
type Target = {
	userId: number,
	-- The root, as of the frame at `clock`.
	position: Vector3,
	clock: number,
	-- The root's displacement over the last crowd step, never the replicated velocity, and no
	-- faster than the fastest legal move: a client that jitters its root buys no miss.
	velocity: Vector3,
	-- How far the root is above the floor they stand on (HipHeight + half the root's height): a
	-- fall is led down to the attacker's floor + this.
	lift: number,
	-- How far the server's copy of them trails their own screen (Tuning.CommitLag): the commit
	-- rule judges a shot against them that long after it gets there.
	lag: number,
	-- still = it neither rose nor fell over the last step. resting = nor over the one before:
	-- standing or walking on something, wherever that is (the apex of a jump is still for one
	-- step only). restY = the root's height when it last rested: the surface it stood on.
	still: boolean,
	resting: boolean,
	restY: number,
}

-- A phase that ends exactly on a step (0.8 s at 15 Hz is 12 steps) must not wait a 13th because
-- the summed step times came out a hair short.
local TIME_EPSILON = 1e-6
-- The walk stops exactly at the reach; rounding must not leave the body a hair outside it for
-- good.
local REACH_EPSILON = 1e-3
local FACING_EPSILON = 1e-4
-- A root that rises or falls slower than this (studs/s) over a step is not moving vertically:
-- standing or walking, with room for replication jitter. A jump passes through it in one step.
local STILL_SPEED = 2
-- A player unseen for longer than this (down, respawning) has no motion to lead a shot by.
local TRACK_GAP_SECONDS = 0.25
-- How often a shot's aim is refined. The flight time depends on the point aimed at, so each pass
-- aims at where the target will be after the flight to the last pass's point. Two left a
-- walk-speed strafer 2 studs behind the shot; six leave a fifth of a stud. It runs once per shot.
-- (tools/sim_range.py SHOT_AIM_PASSES mirrors it.)
local AIM_PASSES = 6
-- Where a body faces before it has ever seen a target: yaw 0, as every enemy spawns.
local FORWARD = Vector3.new(0, 0, -1)

-- Living, standing players this step, reused across steps (records and all).
local targets: { Target } = {}
local targetCount = 0
local tracks: { [number]: Target } = {}
-- Ruling 8 as the wave 2 review round widened it: enemies of one kind take turns. The places
-- taken, by kind and then by target player. An enemy holds one from its windup's start to the
-- end of its attack state, a brute's charge included; a recover holds none, and neither does a
-- shot in the air or a lob on its way. Counted afresh over the crowd before each step thinks
-- (Commit), then kept as windups start and attacks end, so a place freed in a step can be taken
-- in it and a death or a cancel between steps frees its place too.
local places: { [string]: { [number]: number } } = {}
-- Enemy shots in the air plus the shot windups under way: a new one starts only while this is
-- under threat.maxShots, so the cap holds at the moment each is fired.
local shotsHeld = 0
local strikes: { Strike } = {}
local stepNow = 0
local stepGravity = 0
local stepFastest = 0
-- Each floor's top centre and half extents, by floor index: a body's charge stops at its own
-- floor's edge and a retreat ends there. Before SetFloors: one floor at the origin, effectively
-- unbounded sideways.
local DEFAULT_FLOOR: Types.CrowdFloor = { centre = Vector3.zero, half = Vector3.new(1024, 0, 1024) }
local floors: { Types.CrowdFloor } = { DEFAULT_FLOOR }

local CrowdBrain = {}

-- A body's own floor. One whose index is not in the list (it cannot happen while SetFloors is
-- refused with a body alive) stands on the first.
local function floorOf(body: Body): Types.CrowdFloor
	return floors[body.floor] or floors[1] or DEFAULT_FLOOR
end

-- The nearest target, among those in `allowed` when it is given (a resident's group's known
-- set); every target otherwise.
local function nearest(position: Vector3, allowed: { [number]: boolean }?): Target?
	local best: Target? = nil
	local bestDistance = math.huge
	for index = 1, targetCount do
		local target = targets[index]
		if allowed ~= nil and not allowed[target.userId] then
			continue
		end
		local dx = target.position.X - position.X
		local dz = target.position.Z - position.Z
		local distance = dx * dx + dz * dz
		if distance < bestDistance then
			bestDistance = distance
			best = target
		end
	end
	return best
end

local function find(userId: number): Target?
	for index = 1, targetCount do
		local target = targets[index]
		if target.userId == userId then
			return target
		end
	end
	return nil
end

local function flatUnit(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < FACING_EPSILON then
		return nil
	end
	return flat.Unit
end

-- A facing as the wire will carry it. The snapshot holds yaw in 1/256 of a turn, and every
-- client draws a tell along that yaw: at 50 studs one step is most of a stud, against a line
-- 1.6 wide. So a facing is snapped to the wire's step when it locks, and the attack is judged
-- along the very line that is drawn. (Yaw as CrowdService.yawToward has it: 0 looks down -Z.)
local function snapped(facing: Vector3): Vector3
	local yaw = CrowdCodec.SnapYaw(math.atan2(-facing.X, -facing.Z))
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- Where a target will be `seconds` on if it keeps moving as it did over the last crowd step:
-- straight on the flat, at the height it is at. Only one that is rising or falling is led down
-- a fall under gravity, as far as the surface it last stood on, or the attacker's floor
-- (`floorY`) once it is below that (it stepped off). A player standing on a block is aimed at
-- where they stand: how high the root is says nothing about whether it is in the air.
local function ahead(from: Vector3, target: Target, seconds: number, floorY: number): Vector3
	local velocity = target.velocity
	local y = from.Y
	if not target.resting then
		local floor = if y >= target.restY then target.restY else floorY + target.lift
		local fallen = y + velocity.Y * seconds - 0.5 * stepGravity * seconds * seconds
		y = math.max(floor, fallen)
	end
	return Vector3.new(from.X + velocity.X * seconds, y, from.Z + velocity.Z * seconds)
end

-- Where a point may stand on a floor: a body of `radius` stays wholly on it, or wholly in its
-- region when it has one.
local function inArena(point: Vector3, radius: number, floor: Types.CrowdFloor): Vector3
	local region = floor.region
	if region ~= nil then
		return Region.Clamp(region.cells, point, radius)
	end
	local arenaCenter = floor.centre
	local limitX = math.max(floor.half.X - radius, 0)
	local limitZ = math.max(floor.half.Z - radius, 0)
	return Vector3.new(
		math.clamp(point.X, arenaCenter.X - limitX, arenaCenter.X + limitX),
		point.Y,
		math.clamp(point.Z, arenaCenter.Z - limitZ, arenaCenter.Z + limitZ)
	)
end

-- How far a body of `radius` can run from `from` along the flat unit `heading` before its
-- floor's edge, or its region's (through the doors) when it has one.
local function runway(
	from: Vector3,
	heading: Vector3,
	radius: number,
	floor: Types.CrowdFloor
): number
	local region = floor.region
	if region ~= nil then
		return Region.Runway(region.cells, from, heading, radius)
	end
	local arenaCenter = floor.centre
	local limitX = math.max(floor.half.X - radius, 0)
	local limitZ = math.max(floor.half.Z - radius, 0)
	local room = math.huge
	if heading.X > 0 then
		room = math.min(room, (arenaCenter.X + limitX - from.X) / heading.X)
	elseif heading.X < 0 then
		room = math.min(room, (arenaCenter.X - limitX - from.X) / heading.X)
	end
	if heading.Z > 0 then
		room = math.min(room, (arenaCenter.Z + limitZ - from.Z) / heading.Z)
	elseif heading.Z < 0 then
		room = math.min(room, (arenaCenter.Z - limitZ - from.Z) / heading.Z)
	end
	return math.max(room, 0)
end

-- From the windup's start to the thrust's end: the part of an attack that still has its blow to
-- show. Such a body is planted (crowd separation does not move it, or a facing locked at the
-- windup's start would miss a player who never moved), and the snapshot keeps its attack index
-- even under a stagger or a hop.
function CrowdBrain.IsStriking(mind: Mind): boolean
	return mind.phase == "windup" or mind.phase == "attack"
end

-- A brute in its charge: nothing cancels or moves it (hits still hurt it, and a kill ends it).
function CrowdBrain.IsCharging(mind: Mind): boolean
	return mind.charge ~= nil and mind.phase == "attack"
end

-- The places enemies of `kind` hold, by target player.
local function placesOf(kind: string): { [number]: number }
	local held = places[kind]
	if held == nil then
		held = {}
		places[kind] = held
	end
	return held
end

-- May this enemy start `attack` against that player now? Only `perPlayer` enemies of its kind
-- may be winding up or attacking one player at once: the others wait their turn, moving as their
-- brain has it, so a kind's hits come as a rhythm and never as one volley. And only so many
-- enemy shots may be in the air at all (a slinger at that cap waits too). Both are asked before
-- either is taken.
local function admit(
	body: Body,
	def: Types.CrowdKindDef,
	attack: Types.CrowdAttackDef,
	userId: number,
	threat: ThreatConfig
): boolean
	local held = placesOf(body.kind)
	local taken = held[userId] or 0
	local cap = def.perPlayer
	if cap ~= nil and taken >= math.floor(cap) then
		return false
	end
	if attack.shape == "shot" then
		if shotsHeld >= math.floor(threat.maxShots) then
			return false
		end
		shotsHeld += 1
	end
	held[userId] = taken + 1
	return true
end

-- The second phase begins once the health share is at or under `enrage.at`, as the snapshot
-- will carry it: the same byte the client reads the phase from. Under a plate the bar is the
-- plate's and health cannot have moved.
local function enrage(body: Body, mind: Mind, def: Types.CrowdKindDef): ()
	local phase = def.enrage
	if phase == nil or mind.enraged or body.plate > 0 then
		return
	end
	if CrowdCodec.SnapHp(body.hp / math.max(body.maxHp, 1)) <= phase.at then
		mind.enraged = true
	end
end

-- A windup's or a recover's length in the mind's phase.
local function paced(mind: Mind, def: Types.CrowdKindDef, seconds: number, recover: boolean): number
	local phase = def.enrage
	if phase == nil or not mind.enraged then
		return math.max(seconds, 0)
	end
	local scale = if recover then phase.recoverScale else phase.windupScale
	return math.max(seconds, 0) * math.max(scale, 0)
end

-- May the mind still use this attack at all? Not an `enraged` one before the second phase, not
-- a `calm` one in it, and not one that has landed its `uses`.
local function usable(mind: Mind, index: number, attack: Types.CrowdAttackDef): boolean
	if attack.enraged == true and not mind.enraged then
		return false
	end
	if attack.calm == true and mind.enraged then
		return false
	end
	local uses = attack.uses
	return uses == nil or (mind.landed[index] or 0) < math.floor(uses)
end

-- Has the mind a call still to make? A `summon` attack it may use that either has `uses` left
-- or, with no limit, has never landed. Until then a `guarded` body's guard is on its way, and
-- its plate is as safe as when the guard stands (CrowdService.Damage).
function CrowdBrain.OwesCall(mind: Mind, def: Types.CrowdKindDef): boolean
	local attacks = def.attacks
	if attacks == nil then
		return false
	end
	for index, attack in attacks do
		if index > CrowdCodec.MAX_ATTACK then
			break
		end
		if
			attack.shape == "summon"
			and usable(mind, index, attack)
			and (attack.uses ~= nil or (mind.landed[index] or 0) == 0)
		then
			return true
		end
	end
	return false
end

-- Which attack next? Among those off their cooldown, within `distance` and allowed in the
-- mind's phase (`refused` = a bit per index already turned away this step), the one whose last
-- impact is oldest; one never used counts as oldest, and the list's order breaks a tie. The
-- attack of the last windup is only taken when no other is ready. 0 = none.
local function choose(
	mind: Mind,
	attacks: { Types.CrowdAttackDef },
	distance: number,
	now: number,
	refused: number
): number
	local best = 0
	local bestAt = math.huge
	local again = false
	local usedAt = mind.usedAt
	for index, attack in attacks do
		if index > CrowdCodec.MAX_ATTACK then
			-- The snapshot cannot name a later attack, so its tell could never be drawn.
			break
		end
		if bit32.btest(refused, bit32.lshift(1, index)) then
			continue
		end
		if not usable(mind, index, attack) or distance > attack.reach + REACH_EPSILON then
			continue
		end
		local used = usedAt[index]
		if used ~= nil and now < used + math.max(attack.cooldown or 0, 0) - TIME_EPSILON then
			continue
		end
		if index == mind.last then
			again = true
		elseif (used or -math.huge) < bestAt then
			best = index
			bestAt = used or -math.huge
		end
	end
	return if best == 0 and again then mind.last else best
end

-- Fix round R14: can this attack hit the target at all? A ground shape judged from the crowd's
-- floor (a lunge, an arc, a lane, a ring: not a line, a lob or a shot) hits feet within its
-- `height` of that floor, above or below (R6). The feet are those of the surface the target last
-- stood on, so a player jumping over the floor is still wound up at (ruling 21) while one on a
-- ledge, or at the foot of a drop below the region's lip, is not: a windup at someone the blow
-- cannot reach would only hold its group's leash.
local function reaches(body: Body, attack: Types.CrowdAttackDef, target: Target): boolean
	local height = attack.height
	local shape = attack.shape
	if
		height == nil
		or not (shape == "lunge" or shape == "arc" or shape == "lane" or shape == "ring")
	then
		return true
	end
	local above = target.restY - target.lift - floorOf(body).centre.Y
	return above <= height and above >= -height
end

-- Fix round R5: does a lane get its run? On a region floor (no longer convex: the U-bend's arms
-- stand 22 apart across a void) only when the region's runway along the facing it would lock is at
-- least the flat distance to the target less the lane's width; otherwise the brute walks the
-- routed way round. Every other attack, and a lane on a floor with no region, always does.
local function laneRuns(
	body: Body,
	mind: Mind,
	def: Types.CrowdKindDef,
	attack: Types.CrowdAttackDef,
	distance: number
): boolean
	if attack.shape ~= "lane" then
		return true
	end
	local floor = floorOf(body)
	if floor.region == nil then
		return true
	end
	local room = runway(body.position, snapped(mind.facing), def.radius, floor)
	return room >= distance - math.max(attack.width or 0, 0)
end

-- Starts a windup against `target` if an attack is ready and admitted. The facing the caller
-- turned to the target is locked here. `chained` = this attack's place in its chain.
local function begin(
	body: Body,
	mind: Mind,
	def: Types.CrowdKindDef,
	attacks: { Types.CrowdAttackDef },
	threat: ThreatConfig,
	target: Target,
	distance: number,
	now: number,
	chained: number
): boolean
	local refused = 0
	while true do
		local index = choose(mind, attacks, distance, now, refused)
		if index == 0 then
			return false
		end
		local attack = attacks[index]
		if
			reaches(body, attack, target)
			and laneRuns(body, mind, def, attack, distance)
			and admit(body, def, attack, target.userId, threat)
		then
			mind.phase = "windup"
			mind.phaseUntil = now + paced(mind, def, attack.windup, false)
			mind.attack = index
			mind.def = attack
			mind.last = index
			mind.chained = chained
			mind.targetUserId = target.userId
			-- Locked from here (a line: a provisional aim, until its own lock).
			mind.facing = snapped(mind.facing)
			mind.locked = false
			mind.aim = target.position
			return true
		end
		if #attacks == 1 then
			return false
		end
		refused = bit32.bor(refused, bit32.lshift(1, index))
	end
end

-- Has the mind's windup reached its impact time?
local function isDue(mind: Mind, now: number): boolean
	return mind.phase == "windup" and now >= mind.phaseUntil - TIME_EPSILON
end

-- During the windup of a shot, a lob or a line: keeps the target's last seen place, and turns a
-- line's facing after it until the lock. The lock is T - lockSeconds exactly: the step that
-- first passes it takes the target back along its motion to that moment, so the lock never
-- comes early by the step's length. A locked line looks no further: `aim` stays the body it
-- locked on.
local function follow(body: Body, mind: Mind, attack: Types.CrowdAttackDef, now: number): ()
	local line = attack.shape == "line"
	if line and mind.locked then
		return
	end
	local target = find(mind.targetUserId)
	if target == nil then
		return
	end
	local seen = target.position
	if line then
		local lockAt = mind.phaseUntil - math.max(attack.lockSeconds or 0, 0)
		if now >= lockAt then
			mind.locked = true
			seen -= target.velocity * (now - lockAt)
		end
		local heading = flatUnit(seen - body.position)
		if heading ~= nil then
			mind.facing = if mind.locked then snapped(heading) else heading
		end
	end
	mind.aim = seen
end

-- A shot's aim: the target's body where it will be when the shot is judged against it, `lead`
-- of the way from where it is. The commit rule tests the root against where the shot was that
-- player's lag ago, so by then the root has moved on for the flight and for the lag as well: led
-- over the flight alone, a shot always trails a strafer by their lag. Refined AIM_PASSES times,
-- because the flight time depends on the point aimed at.
local function ledAim(
	origin: Vector3,
	here: Vector3,
	target: Target,
	attack: Types.CrowdAttackDef,
	floorY: number
): Vector3
	local speed = attack.speed or 0
	local lead = attack.lead or 0
	if speed <= 0 or lead <= 0 then
		return here
	end
	local aim = here
	for _ = 1, AIM_PASSES do
		local flight = (aim - origin).Magnitude / speed
		aim = here + (ahead(here, target, flight + target.lag, floorY) - here) * lead
	end
	return aim
end

-- The windup's end. The attack is frozen here: at the body's place now (the crowd or a hit may
-- have moved it since the windup began), on the heading the windup locked.
local function land(body: Body, mind: Mind, def: Types.CrowdKindDef, threat: ThreatConfig): ()
	local attack = mind.def
	local impactAt = mind.phaseUntil
	local lasts = math.max(threat.strikeSeconds, 0)
	if attack ~= nil then
		local shape = attack.shape
		local origin = body.position + Vector3.new(0, def.height / 2, 0)
		local floor = floorOf(body)
		-- Its cooldown runs from the impact, and the impact is what `uses` counts.
		mind.usedAt[mind.attack] = impactAt
		mind.landed[mind.attack] = (mind.landed[mind.attack] or 0) + 1
		local strike: Strike = {
			-- Not the time of this step: it may notice the impact up to one step late.
			at = impactAt,
			enemyKind = body.kind,
			bodyId = body.id,
			attack = mind.attack,
			def = attack,
			targetUserId = mind.targetUserId,
			origin = origin,
			floorY = floor.centre.Y,
			facing = mind.facing,
		}
		if shape == "line" then
			-- A lock that falls on the impact itself has not been taken yet. And one whose
			-- target was gone before the lock never was: the facing it last followed is locked
			-- here, on the wire's step like every other.
			follow(body, mind, attack, stepNow)
			if not mind.locked then
				mind.locked = true
				mind.facing = snapped(mind.facing)
			end
			strike.facing = mind.facing
			strike.aim = mind.aim
		elseif shape == "shot" or shape == "lob" then
			-- Aimed now, not when the windup began. The target's place is taken back to the
			-- impact's own time, which this step may have passed.
			local target = find(mind.targetUserId)
			local here = mind.aim
			if target ~= nil then
				here = target.position - target.velocity * (stepNow - impactAt)
			end
			if shape == "lob" then
				strike.aim = here
			else
				strike.aim = if target ~= nil
					then ledAim(origin, here, target, attack, floor.centre.Y)
					else here
			end
			-- The body turns to its throw.
			local heading = flatUnit((strike.aim :: Vector3) - origin)
			if heading ~= nil then
				mind.facing = snapped(heading)
				strike.facing = mind.facing
			end
		elseif shape == "lane" then
			local speed = attack.speed or 0
			local range = math.max(attack.range or 0, 0)
			if speed > 0 then
				lasts = range / speed
			end
			strike.feet = body.position
			strike.aim = mind.aim
			strike.length = if speed > 0
				then math.min(range, runway(body.position, mind.facing, def.radius, floor))
				else 0
			mind.charge = strike
		elseif shape == "ring" then
			-- The shockwave leaves the feet and travels on by itself; the body stands.
			strike.feet = body.position
			strike.aim = mind.aim
		end
		table.insert(strikes, strike)
	end
	mind.phase = "attack"
	mind.phaseUntil = impactAt + lasts
end

-- The attack state is over: its place goes back to its kind.
local function release(body: Body, mind: Mind): ()
	if mind.def ~= nil then
		local held = placesOf(body.kind)
		held[mind.targetUserId] = math.max((held[mind.targetUserId] or 0) - 1, 0)
	end
end

-- The body stands exposed for its attack's recover, measured from the attack state's own end.
local function expose(mind: Mind, def: Types.CrowdKindDef): ()
	local attack = mind.def
	mind.phase = "recover"
	mind.phaseUntil += if attack ~= nil then paced(mind, def, attack.recover, true) else 0
end

-- Enraged, an attack may follow the one that has just ended with no recover between them, up
-- to `enrage.chain` in a row. It follows only if it can start in this very step (ready, in
-- reach, admitted); otherwise the chain is over and the body recovers. Its windup is an
-- ordinary one, timed from this step like any other.
local function chain(
	body: Body,
	mind: Mind,
	def: Types.CrowdKindDef,
	threat: ThreatConfig,
	now: number,
	allowed: { [number]: boolean }?
): boolean
	local phase = def.enrage
	local attacks = def.attacks
	if
		phase == nil
		or attacks == nil
		or not mind.enraged
		or mind.chained >= math.floor(phase.chain)
	then
		return false
	end
	-- A charge that has just run leaves the body at its lane's end: CrowdService sets it down
	-- there after this step's thinking, so the next attack is aimed from there.
	local here = body.position
	local charge = mind.charge
	if charge ~= nil and charge.feet ~= nil then
		here = charge.feet + charge.facing * (charge.length or 0)
	end
	local target = nearest(here, allowed)
	if target == nil then
		return false
	end
	local offset = target.position - here
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	local kept = mind.facing
	if distance > FACING_EPSILON then
		mind.facing = flat.Unit
	end
	if begin(body, mind, def, attacks, threat, target, distance, now, mind.chained + 1) then
		return true
	end
	mind.facing = kept
	return false
end

local function rest(mind: Mind): ()
	mind.phase = "approach"
	mind.attack = 0
	mind.def = nil
	mind.targetUserId = 0
end

function CrowdBrain.NewMind(now: number): Mind
	return {
		phase = "approach",
		phaseUntil = 0,
		attack = 0,
		def = nil,
		targetUserId = 0,
		facing = FORWARD,
		bornAt = now,
		locked = false,
		aim = Vector3.zero,
		charge = nil,
		watch = false,
		usedAt = {},
		last = 0,
		landed = {},
		enraged = false,
		chained = 0,
	}
end

-- The crowd's floors, by floor index, as CrowdService.SetFloors has them: each one's top centre
-- and half extents (X and Z are read here).
function CrowdBrain.SetFloors(list: { Types.CrowdFloor }): ()
	floors = list
end

-- Opens a crowd step: `now` is the frame's os.clock() (every catch-up step of one frame gets
-- the same), `gravity` the world's, `shotsAlive` the enemy shots in the air and `fastest` the
-- fastest legal move of a player (Tuning.FastestMove). Targets and commits are added after this,
-- before the first Think.
function CrowdBrain.BeginStep(now: number, gravity: number, shotsAlive: number, fastest: number): ()
	stepNow = now
	stepGravity = gravity
	stepFastest = fastest
	targetCount = 0
	shotsHeld = shotsAlive
	for _, held in places do
		table.clear(held)
	end
end

-- A player the fighting crowd may go for this step: alive and not down. `position` = the root,
-- `lift` = the root's height over whatever they stand on (HipHeight + half the root's height),
-- `lag` = their commit lag (Tuning.CommitLag). Returns their restY, the height CampBrain.Melee
-- judges them at (R16).
function CrowdBrain.AddTarget(userId: number, position: Vector3, lift: number, lag: number): number
	local target = tracks[userId]
	if target == nil then
		target = {
			userId = userId,
			position = position,
			clock = stepNow,
			velocity = Vector3.zero,
			lift = lift,
			lag = lag,
			still = true,
			resting = true,
			restY = position.Y,
		}
		tracks[userId] = target
	elseif stepNow > target.clock then
		-- Once per frame: the catch-up steps of one frame see the same root.
		local gap = stepNow - target.clock
		local velocity = Vector3.zero
		local still = true
		local resting = true
		if gap <= TRACK_GAP_SECONDS then
			velocity = (position - target.position) / gap
			local speed = velocity.Magnitude
			if speed ~= speed then
				velocity = Vector3.zero
			elseif speed > stepFastest then
				velocity *= stepFastest / speed
			end
			still = math.abs(velocity.Y) <= STILL_SPEED
			resting = still and target.still
		end
		target.velocity = velocity
		target.still = still
		target.resting = resting
		if resting then
			target.restY = position.Y
		end
		target.position = position
		target.clock = stepNow
	end
	target.lift = lift
	target.lag = lag
	targetCount += 1
	targets[targetCount] = target
	return target.restY
end

-- Once per living fighting enemy, before the step's first Think: counts the place it holds
-- against its target, and a shot it is winding up.
function CrowdBrain.Commit(body: Body, mind: Mind): ()
	local attack = mind.def
	if attack == nil or not CrowdBrain.IsStriking(mind) then
		return
	end
	local held = placesOf(body.kind)
	held[mind.targetUserId] = (held[mind.targetUserId] or 0) + 1
	if attack.shape == "shot" and mind.phase == "windup" then
		shotsHeld += 1
	end
end

-- One living fighting enemy's step. `free` = on the ground and not staggered: only then may it
-- walk or start a windup (a stagger or a launch suspends the brain); the timeline of an attack
-- already under way runs on regardless. Returns the point to walk to and how far short of it,
-- on the flat, to stop; nil to stand. `allowed` (L1b-6): only the targets whose userId is in it
-- may be chosen (a resident's group's known set, L1b-W4-21); nil = every target.
function CrowdBrain.Think(
	body: Body,
	mind: Mind,
	def: Types.CrowdKindDef,
	crowd: CrowdConfig,
	free: boolean,
	allowed: { [number]: boolean }?
): (Vector3?, number)
	local now = stepNow
	local threat = crowd.threat
	if isDue(mind, now) then
		land(body, mind, def, threat)
	end
	if mind.phase == "attack" and now >= mind.phaseUntil - TIME_EPSILON then
		release(body, mind)
		-- A chain is made of second-phase attacks. The attack the phase began in ends in a
		-- recover, an enraged one: the first thing every client sees of the phase is that
		-- shorter recover, never a windup it could not have known was a chained one.
		local chains = mind.enraged
		enrage(body, mind, def)
		if not (chains and free and chain(body, mind, def, threat, now, allowed)) then
			expose(mind, def)
		end
	end
	if mind.phase == "recover" and now >= mind.phaseUntil - TIME_EPSILON then
		rest(mind)
	end

	local phase = mind.phase
	if phase == "windup" then
		local attack = mind.def
		if attack ~= nil then
			local shape = attack.shape
			if shape == "shot" or shape == "lob" or shape == "line" then
				follow(body, mind, attack, now)
			end
		end
		return nil, 0
	end
	if phase == "attack" then
		return nil, 0
	end
	-- Neither winding up nor attacking: the moment the second phase may begin, whether or not
	-- the body is free and has a target (every client latches it off the same snapshot).
	enrage(body, mind, def)
	local phaseDef = def.enrage
	local brain = def.brain
	if mind.enraged and phaseDef ~= nil and phaseDef.brain ~= nil then
		brain = phaseDef.brain
	end
	-- Booleans, not the string: the checker narrows a compared union across these returns.
	local rusher = brain == "rush"
	local shooter = brain == "keepAway"
	local attacks = def.attacks
	-- A rusher stands exposed through its recover; a shooter keeps its distance through it.
	if not free or (phase == "recover" and not shooter) then
		return nil, 0
	end
	if attacks == nil or not (rusher or shooter) then
		-- No brain, or nothing to attack with: a dummy that stands.
		return nil, 0
	end
	local target = nearest(body.position, allowed)
	if target == nil then
		return nil, 0
	end
	-- Ruling 21: an attack's reach is measured on the flat, so the crowd gathers and winds up
	-- under a player in the air and a landing is not free. Whether the blow then finds them is
	-- the hit test's business (the `height` rule).
	local offset = target.position - body.position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local distance = flat.Magnitude
	if distance > FACING_EPSILON then
		mind.facing = flat.Unit
	end
	local ready = phase == "approach" and now - mind.bornAt >= threat.spawnGrace
	if ready and begin(body, mind, def, attacks, threat, target, distance, now, 1) then
		return nil, 0
	end
	local shortest = math.huge
	for index, attack in attacks do
		if index > CrowdCodec.MAX_ATTACK then
			break
		end
		if usable(mind, index, attack) then
			shortest = math.min(shortest, attack.reach)
		end
	end
	if shortest == math.huge then
		return nil, 0
	end
	if rusher then
		-- It closes until its shortest attack reaches, then stands there; one the cap or its
		-- spawn grace holds back waits in reach.
		mind.watch = false
		return target.position, math.max(shortest, 0)
	end
	-- keepAway: in when the target is beyond the band (never so far out that nothing reaches),
	-- straight back when it is inside it, and no further than the arena's edge: there it stops
	-- and fights from where it stands.
	mind.watch = true
	local bandMax = math.max(math.min(def.bandMax or shortest, shortest), 0)
	local bandMin = math.min(math.max(def.bandMin or 0, 0), bandMax)
	if distance > bandMax then
		return target.position, bandMax
	elseif distance < bandMin then
		return inArena(
			body.position - mind.facing * (bandMin - distance),
			def.radius,
			floorOf(body)
		),
			0
	end
	return nil, 0
end

-- Where a charging body is this step: the brain carries it down its lane at the charge's own
-- pace, so every snapshot shows it where the players are judged against. nil = not charging.
-- The charge's last stretch falls between two steps: the step that finds it over puts the body
-- at the end of its run, once, and lets it go.
function CrowdBrain.Carried(mind: Mind): Vector3?
	local charge = mind.charge
	if charge == nil then
		return nil
	end
	local feet = charge.feet
	local length = charge.length or 0
	if feet == nil then
		mind.charge = nil
		return nil
	end
	if mind.phase ~= "attack" then
		mind.charge = nil
		return feet + charge.facing * length
	end
	local run = math.clamp((stepNow - charge.at) * (charge.def.speed or 0), 0, length)
	return feet + charge.facing * run
end

-- A hit this fighting enemy survives, after CrowdService.Damage has applied its push, launch
-- and stagger. Rulings 9 and 10: `stagger` = any hit that staggers this kind cancels the
-- windup; `heavy` = only a hit whose amount before armour is crowd.heavyHit or more; `none` =
-- nothing does. `reels` = the hit emptied its plate and it reels: that cancels any windup,
-- whatever the rule (Stop 3). A cancelled windup goes to recover, its attack index still set.
-- A windup whose impact time has come is past cancelling: the next step lands it.
function CrowdBrain.OnHit(
	mind: Mind,
	def: Types.CrowdKindDef,
	amount: number,
	staggers: boolean,
	reels: boolean,
	heavyHit: number,
	now: number
): ()
	local attack = mind.def
	if mind.phase ~= "windup" or attack == nil or isDue(mind, now) then
		return
	end
	local rule = attack.interrupt
	if reels or (rule == "stagger" and staggers) or (rule == "heavy" and amount >= heavyHit) then
		mind.phase = "recover"
		mind.phaseUntil = now + paced(mind, def, attack.recover, true)
	end
end

-- The hit that kills this fighting enemy, called before CrowdService marks it dead. Killing it
-- before its impact time cancels the blow; at or after it the blow is owed, and no later step
-- will think for a dead body, so it is raised here. A charge ends with its brute: what it has
-- run so far still counts.
function CrowdBrain.OnKilled(
	body: Body,
	mind: Mind,
	def: Types.CrowdKindDef,
	crowd: CrowdConfig,
	now: number
): ()
	if isDue(mind, now) then
		land(body, mind, def, crowd.threat)
	end
	local charge = mind.charge
	if charge ~= nil then
		charge.endedAt = now
	end
end

-- What the body shows for the mind's phase; nil while it approaches (it then reads as move or
-- idle, like any walker).
function CrowdBrain.StateOf(mind: Mind): Types.CrowdState?
	local phase = mind.phase
	if phase == "windup" then
		return "windup"
	elseif phase == "attack" then
		return "attack"
	elseif phase == "recover" then
		return "recover"
	end
	return nil
end

-- Takes back the queued impacts of the bodies in `ids` (a boss that has died, the bodies it
-- summoned): nothing of theirs is handed over at the next drain.
function CrowdBrain.Recall(ids: { [number]: boolean }): ()
	local count = #strikes
	local kept = 0
	for index = 1, count do
		local strike = strikes[index]
		if not ids[strike.bodyId] then
			kept += 1
			strikes[kept] = strike
		end
	end
	for index = count, kept + 1, -1 do
		strikes[index] = nil
	end
end

-- Hands every impact the steps since the last drain raised to `handler`, oldest first, and
-- empties the queue. With no handler the impacts are dropped: nobody is there to be hit.
function CrowdBrain.DrainStrikes(handler: ((strike: Strike) -> ())?): ()
	if #strikes == 0 then
		return
	end
	local raised = strikes
	strikes = {}
	if handler ~= nil then
		for _, strike in raised do
			handler(strike)
		end
	end
end

return CrowdBrain
