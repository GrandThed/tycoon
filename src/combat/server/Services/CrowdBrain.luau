--!strict
-- The AI of crowd enemies that fight (docs/INTERFACES.md "P4 contracts"; docs/COMBAT_DESIGN.md
-- §7). Only an enemy whose group's behaviour is `fight` has a mind. CrowdService calls Think for
-- it inside the crowd step, in place of the passive steering, and hands over its record by
-- reference (CrowdService.Get would allocate a view per enemy per step).
--
-- One attack is a fixed timeline: windup (the tell: the body stands, its facing locked) ->
-- impact (the shape is frozen and queued as a Strike) -> attack (the visible thrust,
-- crowd.threat.strikeSeconds) -> recover (exposed, attack.recover) -> approach. Every client
-- draws the tells from the snapshot alone and times them with the same config numbers, so the
-- durations here are exact: a phase ends at phaseUntil whichever step notices it, and the next
-- phase is measured from that moment, not from the step. Only a cancelling hit or death ends a
-- windup early: a stagger or a hop from a hit that does not cancel leaves its clock running.
-- And only before its impact time: once that has come the blow is owed, because every client
-- has drawn it, even if the step that would notice it has not run yet (ruling 22).
--
-- The brain's clock is os.clock() as CrowdService read it for the frame, the same moment it
-- stamps that frame's snapshot with. A windup's impact is therefore exactly the stamp of the
-- first snapshot that shows it + windup, also when one frame runs several catch-up steps.
--
-- Rules that shape the module:
-- * Nothing here yields, raycasts or builds a path: the crowd ignores world geometry (ruling 15).
-- * A Strike is only queued. CrowdService drains the queue after its step, so nothing a hit
--   does can reach back into a step that is still walking the crowd.
-- * Numbers come from the config CrowdService read for the step. An attack's own def is frozen
--   when its windup starts, so a slider applies to the next attack, never to one in the air.
-- * Wave 1 knows the `rush` brain and the `lunge` and `arc` shapes. A kind with any other
--   brain, or none, stands; an attack of any other shape is never started.
-- * tools/sim_range.py mirrors these rules one by one (its "P4 threat" section): change both.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local CrowdCodec = require(sharedFolder:WaitForChild("CrowdCodec"))

type CrowdConfig = typeof((({} :: any) :: Types.ProvingGroundsConfig).crowd)
type ThreatConfig = typeof((({} :: any) :: CrowdConfig).threat)

export type Phase = "approach" | "windup" | "attack" | "recover"

export type Mind = {
	phase: Phase,
	-- os.clock() at which the phase ends; a windup's end is its impact. Unused while approaching.
	phaseUntil: number,
	-- 1-based index into the kind's `attacks` from the windup's start to the recover's end; 0
	-- while approaching.
	attack: number,
	-- That attack, frozen at the windup's start.
	def: Types.CrowdAttackDef?,
	-- The player the windup was started against: the attacker cap is counted per target.
	targetUserId: number,
	-- Flat unit heading. It follows the target while approaching and is locked from the
	-- windup's start to the recover's end.
	facing: Vector3,
	bornAt: number,
}

-- The fields of a CrowdService enemy record that the brain reads. `position` is the feet.
export type Body = {
	kind: string,
	position: Vector3,
}

-- One enemy attack at its impact: everything VitalsService needs to judge it later, with
-- nothing left pointing at the enemy (which may be dead or gone by then).
export type Strike = {
	-- os.clock() of the impact: the T of the commit rule.
	at: number,
	enemyKind: string,
	-- 1-based index into the kind's `attacks`.
	attack: number,
	def: Types.CrowdAttackDef,
	-- The player the attack was aimed at: the brain's target when the windup started. The
	-- shape may still catch someone else; only this player can be said to have dodged it.
	targetUserId: number,
	-- The attacker's body centre: the shape's origin.
	origin: Vector3,
	-- The floor a ground shape lies on. It is the crowd's floor, not the attacker's feet: a hit
	-- that did not cancel the windup may have it in the air at the impact.
	floorY: number,
	-- Flat unit heading, as locked when the windup started.
	facing: Vector3,
}

type Target = { userId: number, position: Vector3 }

-- A phase that ends exactly on a step (0.8 s at 15 Hz is 12 steps) must not wait a 13th because
-- the summed step times came out a hair short.
local TIME_EPSILON = 1e-6
-- The walk stops exactly at the reach; rounding must not leave the body a hair outside it for
-- good.
local REACH_EPSILON = 1e-3
local FACING_EPSILON = 1e-4
-- Where a body faces before it has ever seen a target: yaw 0, as every enemy spawns.
local FORWARD = Vector3.new(0, 0, -1)
local KNOWN_SHAPES: { [string]: boolean } = { lunge = true, arc = true }

-- Living, standing players this step, reused across steps (records and all).
local targets: { Target } = {}
local targetCount = 0
-- Ruling 8: lunging enemies in windup or attack, per target player. Counted afresh over the
-- crowd before each step thinks (Commit), then kept as windups start and thrusts end, so a place
-- freed in a step can be taken in it and a death or a cancel between steps frees its place too.
local lunging: { [number]: number } = {}
local strikes: { Strike } = {}
local stepNow = 0
local stepFloorY = 0

local CrowdBrain = {}

local function nearest(position: Vector3): Target?
	local best: Target? = nil
	local bestDistance = math.huge
	for index = 1, targetCount do
		local target = targets[index]
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

-- From the windup's start to the thrust's end: the part of an attack that still has its blow to
-- show. Such a body is planted (crowd separation does not move it, or a facing locked at the
-- windup's start would miss a player who never moved), and the snapshot keeps its attack index
-- even under a stagger or a hop.
function CrowdBrain.IsStriking(mind: Mind): boolean
	return mind.phase == "windup" or mind.phase == "attack"
end

-- Does the mind hold one of its target's lunge places?
local function isLunging(mind: Mind): boolean
	local attack = mind.def
	return attack ~= nil and attack.shape == "lunge" and CrowdBrain.IsStriking(mind)
end

-- Only so many lunges may be under way against one player; the others wait in reach. A sweep
-- or a shot is not a lunge and is never held back.
local function admit(attack: Types.CrowdAttackDef, userId: number, threat: ThreatConfig): boolean
	if attack.shape ~= "lunge" then
		return true
	end
	local held = lunging[userId] or 0
	if held >= math.floor(threat.attackersPerPlayer) then
		return false
	end
	lunging[userId] = held + 1
	return true
end

-- Has the mind's windup reached its impact time?
local function isDue(mind: Mind, now: number): boolean
	return mind.phase == "windup" and now >= mind.phaseUntil - TIME_EPSILON
end

-- The windup's end. The shape is frozen here, at the body's place now (the crowd or a hit may
-- have moved it since the windup began) and the heading the windup locked.
local function land(body: Body, mind: Mind, def: Types.CrowdKindDef, threat: ThreatConfig): ()
	local attack = mind.def
	local impactAt = mind.phaseUntil
	if attack ~= nil then
		table.insert(strikes, {
			-- Not the time of this step: it may notice the impact up to one step late.
			at = impactAt,
			enemyKind = body.kind,
			attack = mind.attack,
			def = attack,
			targetUserId = mind.targetUserId,
			origin = body.position + Vector3.new(0, def.height / 2, 0),
			floorY = stepFloorY,
			facing = mind.facing,
		})
	end
	mind.phase = "attack"
	mind.phaseUntil = impactAt + math.max(threat.strikeSeconds, 0)
end

-- The thrust is over: the body stands exposed, and a lunge gives its place back.
local function spend(mind: Mind): ()
	local attack = mind.def
	if isLunging(mind) then
		lunging[mind.targetUserId] = math.max((lunging[mind.targetUserId] or 0) - 1, 0)
	end
	mind.phase = "recover"
	mind.phaseUntil += if attack ~= nil then math.max(attack.recover, 0) else 0
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
	}
end

-- Opens a crowd step: `now` is the frame's os.clock() (every catch-up step of one frame gets
-- the same) and `floorY` the crowd's floor. Targets and commits are added after this, before
-- the first Think.
function CrowdBrain.BeginStep(now: number, floorY: number): ()
	stepNow = now
	stepFloorY = floorY
	targetCount = 0
	table.clear(lunging)
end

-- A player the fighting crowd may go for this step: alive and not down. `position` = the root.
function CrowdBrain.AddTarget(userId: number, position: Vector3): ()
	targetCount += 1
	local target = targets[targetCount]
	if target == nil then
		targets[targetCount] = { userId = userId, position = position }
	else
		target.userId = userId
		target.position = position
	end
end

-- Once per living fighting enemy, before the step's first Think: counts the lunge it has under
-- way against its target.
function CrowdBrain.Commit(mind: Mind): ()
	if isLunging(mind) then
		lunging[mind.targetUserId] = (lunging[mind.targetUserId] or 0) + 1
	end
end

-- One living fighting enemy's step. `free` = on the ground and not staggered: only then may it
-- walk or start a windup (a stagger or a launch suspends the brain); the timeline of an attack
-- already under way runs on regardless. Returns the point to walk to and how far short of it,
-- on the flat, to stop; nil to stand.
function CrowdBrain.Think(
	body: Body,
	mind: Mind,
	def: Types.CrowdKindDef,
	crowd: CrowdConfig,
	free: boolean
): (Vector3?, number)
	local now = stepNow
	local threat = crowd.threat
	if isDue(mind, now) then
		land(body, mind, def, threat)
	end
	if mind.phase == "attack" and now >= mind.phaseUntil - TIME_EPSILON then
		spend(mind)
	end
	if mind.phase == "recover" and now >= mind.phaseUntil - TIME_EPSILON then
		rest(mind)
	end
	if mind.phase ~= "approach" or not free then
		return nil, 0
	end

	local attacks = def.attacks
	if def.brain ~= "rush" or attacks == nil then
		-- No brain this wave knows, or nothing to attack with: a dummy that stands.
		return nil, 0
	end
	local target = nearest(body.position)
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
	local ready = now - mind.bornAt >= threat.spawnGrace
	local shortest = math.huge
	for index, attack in attacks do
		if index > CrowdCodec.MAX_ATTACK then
			-- The snapshot cannot name a later attack, so its tell could never be drawn.
			break
		end
		if not KNOWN_SHAPES[attack.shape] then
			continue
		end
		shortest = math.min(shortest, attack.reach)
		if
			ready
			and distance <= attack.reach + REACH_EPSILON
			and admit(attack, target.userId, threat)
		then
			mind.phase = "windup"
			mind.phaseUntil = now + math.max(attack.windup, 0)
			mind.attack = index
			mind.def = attack
			mind.targetUserId = target.userId
			return nil, 0
		end
	end
	if shortest == math.huge then
		return nil, 0
	end
	-- Rush: it closes until its shortest attack reaches, then stands there; one the cap or its
	-- spawn grace holds back waits in reach.
	return target.position, math.max(shortest, 0)
end

-- A hit this fighting enemy survives, after CrowdService.Damage has applied its push, launch
-- and stagger. Rulings 9 and 10: `stagger` = any hit that staggers this kind cancels the
-- windup; `heavy` = only a hit whose amount before armour is crowd.heavyHit or more; `none` =
-- nothing does. A cancelled windup goes to recover, its attack index still set. A windup whose
-- impact time has come is past cancelling: the next step lands it.
function CrowdBrain.OnHit(
	mind: Mind,
	amount: number,
	staggers: boolean,
	heavyHit: number,
	now: number
): ()
	local attack = mind.def
	if mind.phase ~= "windup" or attack == nil or isDue(mind, now) then
		return
	end
	local rule = attack.interrupt
	if (rule == "stagger" and staggers) or (rule == "heavy" and amount >= heavyHit) then
		mind.phase = "recover"
		mind.phaseUntil = now + math.max(attack.recover, 0)
	end
end

-- The hit that kills this fighting enemy, called before CrowdService marks it dead. Killing it
-- before its impact time cancels the blow; at or after it the blow is owed, and no later step
-- will think for a dead body, so it is raised here.
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
