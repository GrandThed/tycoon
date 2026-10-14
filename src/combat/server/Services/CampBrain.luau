--!strict
-- The rules of a camp's resident groups (docs/INTERFACES.md "L1b contracts — the living road",
-- rulings L1b-3 to L1b-9 and L1b-13; MISSIONS_DESIGN §16.1, §16.2 and §16.5). A group is a set of
-- bodies of one camp with one posture (guard, patrol, fire) and one state (rest, rise, fight,
-- home): its whole membership changes state together, which is what "a raider of their group
-- wakes" means. CrowdService keeps the groups and executes what this module decides.
--
-- Pure on purpose, as StageFlow is: tables, numbers and Vector3 values within the harness shim
-- (X Y Z, + - * /, unary minus, Magnitude, Unit, Dot); no service, no Instance, no clock of its
-- own (every time is an argument) and no yield, so tools/crowd_harness loads it as it stands,
-- mutate.py mutates it, and tools/sim_range.py mirrors it rule by rule. It mutates only the Group
-- and Resident tables it is handed. The Types require is for annotations alone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

export type Post = {
	-- feet, on the group's floor (y = def.floorY)
	at: Vector3,
	-- facing at rest, radians, CrowdService.yawToward's convention (0 faces -Z)
	yaw: number,
	-- patrol: the loop point (1-based) it walks to next; 0 for guard and fire
	leg: number,
}
-- Kept on the crowd body; leg starts at post.leg.
export type Resident = { group: number, post: Post, leg: number }
-- A target this step: alive, not down.
export type Seen = { userId: number, root: Vector3 }
-- A living keepAway member: feet, its longest attack reach.
export type Shooter = { at: Vector3, reach: number }
-- A living member: feet, its post.
export type Member = { at: Vector3, post: Post }
export type StepInput = {
	now: number,
	members: { Member },
	targets: { Seen },
	shooters: { Shooter },
	-- a member is between a windup's start and its attack's end, a charge included
	striking: boolean,
}
export type Group = {
	def: Types.CampGroupDef,
	state: Types.CampGroupState,
	held: boolean,
	-- the clock the state began
	since: number,
	-- fight: no target has been in play since this clock
	quietSince: number,
	-- a member was struck since the last Step (Struck sets it)
	hit: boolean,
	-- the userIds in play at the last Step
	inPlay: { [number]: boolean },
}

-- A rise or a leash that ends exactly on a step must not wait one more because the summed step
-- times came out a hair short (CrowdBrain's TIME_EPSILON).
local TIME_EPSILON = 1e-6
-- A target this close to a member is in front of it whatever its cone.
local CONE_NEAR = 0.001
-- The cone's edge is included; acos of a facing built from sin and cos lands a hair either side.
local CONE_EPSILON_DEGREES = 1e-6
-- A patrol member whose arc length falls this close to a vertex stands on it (and takes the next).
local ARC_EPSILON = 1e-9

local POSTURES: { Types.CampPosture } = { "guard", "patrol", "fire" }
local POSTURE_KEYS = { "sight", "cone", "rise" }
local RULE_KEYS = {
	"sightBelow",
	"sightAbove",
	"chaseMargin",
	"leashSeconds",
	"homePace",
	"patrolPace",
	"homeTolerance",
	"engagedHoldSeconds",
}

local CampBrain = {}

local function isFinite(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function yawToward(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

local function flatDistance(a: Vector3, b: Vector3): number
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function onFloor(point: Vector3, floorY: number): Vector3
	return Vector3.new(point.X, floorY, point.Z)
end

local function postureRules(
	def: Types.CampGroupDef,
	rules: Types.CampRulesConfig
): Types.CampPostureRules
	local posture = def.posture
	if posture == "patrol" then
		return rules.patrol
	elseif posture == "fire" then
		return rules.fire
	end
	return rules.guard
end

-- The height band of sight and of play: from sightBelow under the camp's floor to sightAbove over
-- it, both edges included.
local function inBand(def: Types.CampGroupDef, root: Vector3, rules: Types.CampRulesConfig): boolean
	return root.Y >= def.floorY - rules.sightBelow and root.Y <= def.floorY + rules.sightAbove
end

-- One line per key of Combat.json `camps` that is missing, not a number, not finite or negative;
-- a `sight` of 0 or less; a `cone` outside (0, 360]; a `homeTolerance` of 0 or less. nil = one line.
function CampBrain.Problems(rules: Types.CampRulesConfig?): { string }
	local problems: { string } = {}
	if typeof(rules) ~= "table" then
		table.insert(problems, "camps: missing")
		return problems
	end
	local given = rules :: any
	for _, posture in POSTURES do
		local entry = given[posture]
		if typeof(entry) ~= "table" then
			table.insert(problems, `camps.{posture}: missing`)
			continue
		end
		for _, key in POSTURE_KEYS do
			local value = entry[key]
			if not isFinite(value) then
				table.insert(problems, `camps.{posture}.{key}: missing or not a finite number`)
			elseif value < 0 then
				table.insert(problems, `camps.{posture}.{key}: negative ({value})`)
			elseif key == "sight" and value <= 0 then
				table.insert(problems, `camps.{posture}.sight: must be above 0 ({value})`)
			elseif key == "cone" and (value <= 0 or value > 360) then
				table.insert(problems, `camps.{posture}.cone: must be in (0, 360] ({value})`)
			end
		end
	end
	for _, key in RULE_KEYS do
		local value = given[key]
		if not isFinite(value) then
			table.insert(problems, `camps.{key}: missing or not a finite number`)
		elseif value < 0 then
			table.insert(problems, `camps.{key}: negative ({value})`)
		elseif key == "homeTolerance" and value <= 0 then
			table.insert(problems, `camps.homeTolerance: must be above 0 ({value})`)
		end
	end
	return problems
end

function CampBrain.NewGroup(def: Types.CampGroupDef, now: number): Group
	return {
		def = def,
		state = "rest",
		held = def.held == true,
		since = now,
		quietSince = now,
		hit = false,
		inPlay = {},
	}
end

-- Where `count` members of a group stand at rest. Every post is on the floor (y = def.floorY).
-- guard: member k on points[k], all facing def.yaw. patrol: spaced evenly by arc length round
-- the closed loop from points[1], each walking to the end of the leg it stands on (one exactly on
-- a vertex walks to the next point) and facing it. fire: evenly round the circle of def.radius
-- about points[1], the first north of the centre, each facing the centre.
function CampBrain.Posts(def: Types.CampGroupDef, count: number): { Post }
	local posts: { Post } = {}
	local points = def.points
	local floorY = def.floorY
	local n = #points
	if n == 0 then
		-- Validate refuses a spot with no points; a body still gets somewhere to stand.
		local centre = Vector3.new(def.rect.x, floorY, def.rect.z)
		for _ = 1, count do
			table.insert(posts, { at = centre, yaw = def.yaw, leg = 0 })
		end
		return posts
	end
	local posture = def.posture
	if posture == "patrol" then
		local total = 0
		for index = 1, n do
			total += flatDistance(points[index], points[index % n + 1])
		end
		for k = 1, count do
			local s = total * (k - 1) / count
			local at = onFloor(points[1], floorY)
			local leg = if n > 1 then 2 else 1
			local walked = 0
			for index = 1, n do
				local from = points[index]
				local to = points[index % n + 1]
				local length = flatDistance(from, to)
				if length > ARC_EPSILON and s < walked + length - ARC_EPSILON then
					local share = (s - walked) / length
					at = Vector3.new(
						from.X + (to.X - from.X) * share,
						floorY,
						from.Z + (to.Z - from.Z) * share
					)
					leg = index % n + 1
					break
				end
				walked += length
			end
			local goal = points[leg]
			local dx = goal.X - at.X
			local dz = goal.Z - at.Z
			local yaw = if dx * dx + dz * dz > ARC_EPSILON then yawToward(dx, dz) else def.yaw
			table.insert(posts, { at = at, yaw = yaw, leg = leg })
		end
	elseif posture == "fire" then
		local centre = points[1]
		for k = 1, count do
			local theta = 2 * math.pi * (k - 1) / count
			local at = Vector3.new(
				centre.X - math.sin(theta) * def.radius,
				floorY,
				centre.Z - math.cos(theta) * def.radius
			)
			local yaw = theta + math.pi
			while yaw > math.pi do
				yaw -= 2 * math.pi
			end
			while yaw <= -math.pi do
				yaw += 2 * math.pi
			end
			table.insert(posts, { at = at, yaw = yaw, leg = 0 })
		end
	else
		for k = 1, count do
			-- Validate guarantees count <= #points; past that the posts are shared, not missing.
			table.insert(
				posts,
				{ at = onFloor(points[(k - 1) % n + 1], floorY), yaw = def.yaw, leg = 0 }
			)
		end
	end
	return posts
end

-- Does this member see that target? Distance only, with no ray: raiders see through the palisade
-- and through cover (ruling L1b-4). A guard's cone is about its post's facing.
function CampBrain.Sees(
	def: Types.CampGroupDef,
	member: Member,
	target: Seen,
	rules: Types.CampRulesConfig
): boolean
	local root = target.root
	if not inBand(def, root, rules) then
		return false
	end
	local posture = postureRules(def, rules)
	local dx = root.X - member.at.X
	local dz = root.Z - member.at.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > posture.sight then
		return false
	end
	if posture.cone >= 360 or distance < CONE_NEAR then
		return true
	end
	local yaw = member.post.yaw
	local cosine = (-math.sin(yaw) * dx - math.cos(yaw) * dz) / distance
	local angle = math.deg(math.acos(math.clamp(cosine, -1, 1)))
	return angle <= posture.cone / 2 + CONE_EPSILON_DEGREES
end

-- Is this target in play for the group: in the height band, and within chaseMargin (flat) of the
-- camp's floor rectangle, or within reach of one of its living keepAway members?
-- The margin is a distance to the rectangle, so its corners are round: a rusher clamped in a
-- floor's corner stands √2 × its radius from it, and a square corner would leave a player who can
-- hit it out of its reach (L1b-7; the gate is chaseMargin ≤ reach − √2 × radius).
function CampBrain.InPlay(
	def: Types.CampGroupDef,
	target: Seen,
	shooters: { Shooter },
	rules: Types.CampRulesConfig
): boolean
	local root = target.root
	if not inBand(def, root, rules) then
		return false
	end
	local rect = def.rect
	local margin = rules.chaseMargin
	local outX = math.max(math.abs(root.X - rect.x) - rect.hx, 0)
	local outZ = math.max(math.abs(root.Z - rect.z) - rect.hz, 0)
	if math.sqrt(outX * outX + outZ * outZ) <= margin then
		return true
	end
	for _, shooter in shooters do
		if flatDistance(shooter.at, root) <= shooter.reach then
			return true
		end
	end
	return false
end

-- Is a player still engaged (L1b-20) at `now`, the crowd's step clock, when `lastAt` is the last
-- step that found them in play for a group in rise or fight (nil = never)? True for
-- engagedHoldSeconds after it, edge included: a fall out of a fight leaves the height band a few
-- steps before it reaches killY and must still get no get-up i-frames, and a player on a camp's
-- edge must not flicker in and out (the phone's Abandon button reads it).
function CampBrain.Engaged(lastAt: number?, now: number, rules: Types.CampRulesConfig): boolean
	return lastAt ~= nil and now - lastAt <= rules.engagedHoldSeconds + TIME_EPSILON
end

function CampBrain.AtPost(post: Post, at: Vector3, rules: Types.CampRulesConfig): boolean
	return flatDistance(post.at, at) <= rules.homeTolerance
end

local function anySeen(group: Group, input: StepInput, rules: Types.CampRulesConfig): boolean
	local def = group.def
	for _, member in input.members do
		for _, target in input.targets do
			if CampBrain.Sees(def, member, target, rules) then
				return true
			end
		end
	end
	return false
end

-- One step of a group: at most one transition. Returns the new state (already written into the
-- group), or nil when it did not change. `hit` is cleared at the end of every call.
function CampBrain.Step(
	group: Group,
	input: StepInput,
	rules: Types.CampRulesConfig
): Types.CampGroupState?
	if #input.members == 0 then
		-- An empty group never changes state.
		return nil
	end
	local now = input.now
	local inPlay = group.inPlay
	table.clear(inPlay)
	local anyInPlay = false
	for _, target in input.targets do
		if CampBrain.InPlay(group.def, target, input.shooters, rules) then
			inPlay[target.userId] = true
			anyInPlay = true
		end
	end
	if group.held then
		-- Held until the close: neither sight nor a hit wakes it (ruling L1b-13).
		group.hit = false
		return nil
	end
	local changed: Types.CampGroupState? = nil
	local state = group.state
	if state == "rest" then
		if group.hit or anySeen(group, input, rules) then
			changed = "rise"
		end
	elseif state == "rise" then
		if now - group.since >= postureRules(group.def, rules).rise - TIME_EPSILON then
			changed = "fight"
			group.quietSince = now
		end
	elseif state == "fight" then
		if anyInPlay then
			group.quietSince = now
		elseif
			now - group.quietSince >= rules.leashSeconds - TIME_EPSILON and not input.striking
		then
			changed = "home"
		end
	elseif state == "home" then
		local home = true
		for _, member in input.members do
			if not CampBrain.AtPost(member.post, member.at, rules) then
				home = false
				break
			end
		end
		if home then
			changed = "rest"
		end
	end
	if changed ~= nil then
		group.state = changed
		group.since = now
	end
	group.hit = false
	return changed
end

-- The close: a held group goes to rise. No-op for a group that is not held.
function CampBrain.Release(group: Group, now: number): ()
	if not group.held then
		return
	end
	group.held = false
	group.state = "rise"
	group.since = now
end

-- A held group, or one walking home: it takes no damage, no knock and no stagger, and ignores
-- sight and hits.
function CampBrain.Evades(group: Group): boolean
	return group.held or group.state == "home"
end

-- A hit on a member. An evading group records nothing (false). Otherwise the group is woken by
-- it, and the damage lands only from a player in play at the last step, or from nobody (a Studio
-- lever): ruling L1b-7.
function CampBrain.Struck(group: Group, byUserId: number): boolean
	if CampBrain.Evades(group) then
		return false
	end
	group.hit = true
	return byUserId == 0 or group.inPlay[byUserId] == true
end

-- Where a member that is not fighting walks, and its pace (x its kind's speed); nil = it stands.
-- The executor seeks the goal with a stop distance of rules.homeTolerance.
function CampBrain.Goal(
	group: Group,
	resident: Resident,
	at: Vector3,
	rules: Types.CampRulesConfig
): (Vector3?, number)
	local post = resident.post
	local state = group.state
	if group.held or state == "rest" then
		local def = group.def
		local points = def.points
		local n = #points
		if def.posture ~= "patrol" or n == 0 then
			-- A shoved guard or sitter drifts back to its post.
			return post.at, rules.homePace
		end
		if resident.leg < 1 or resident.leg > n then
			resident.leg = 1
		end
		local goal = onFloor(points[resident.leg], def.floorY)
		if flatDistance(goal, at) <= rules.homeTolerance then
			resident.leg = resident.leg % n + 1
			goal = onFloor(points[resident.leg], def.floorY)
		end
		return goal, rules.patrolPace
	elseif state == "home" then
		if CampBrain.AtPost(post, at, rules) then
			-- Back on its loop where it was put.
			resident.leg = post.leg
		end
		return post.at, rules.homePace
	end
	return nil, 0
end

-- The wire state of a member that is not fighting; nil = the brain's (fight). `moving` is the
-- executor's: a flat speed over its move threshold this step.
function CampBrain.Shows(group: Group, moving: boolean): Types.CrowdState?
	local state = group.state
	if group.held or state == "rest" then
		if moving then
			return "move"
		end
		return if group.def.posture == "fire" then "rest" else "idle"
	elseif state == "home" then
		return if moving then "move" else "idle"
	elseif state == "rise" then
		return "rise"
	end
	return nil
end

return CampBrain
