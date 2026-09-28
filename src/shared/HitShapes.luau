--!strict
-- Pure hit geometry for the Proving Grounds (docs/INTERFACES.md "P1 contracts" → decision 2;
-- P3 adds Scatter for cluster bomblets).
-- The server resolves every attack with these tests and the client draws the same shapes from
-- the same numbers, so what you see is what you hit. No Roblox globals beyond Vector3 maths.
--
-- Every test asks one question: does a sphere (c, r) overlap the shape grown by `pad` studs?
-- Growing the shape by pad and the enemy by r is the same Minkowski sum, so the forgiveness pad
-- simply adds to the reach in every direction.

local HitShapes = {}

-- Below this length a direction carries no heading; the shape is then treated as a miss rather
-- than guessing one.
local EPSILON = 1e-6
-- Park–Miller minimal standard generator: small enough that every product stays an exact
-- integer in a double, so the server and the client produce identical pellet patterns.
local PM_MODULUS = 2147483647
local PM_MULTIPLIER = 48271
local FULL_TURN = 2 * math.pi
-- Pellets are cosmetic tracers; a tuned count past this is clamped, never a frame-long loop.
local MAX_PELLETS = 64
-- Split arrows are real server projectiles; a tuned splitCount past this is clamped (exported
-- as HitShapes.MAX_FAN so the server budgets volleys with the same number).
local MAX_FAN = 16
-- The floor probe (P3 ruling 4 step 4, also the server's air tracking): a down-ray from this far
-- above a point, this far down. Exported so the server's GroundPoint and the client's mirror of
-- it probe the same floor.
local GROUND_PROBE_LIFT = 3
local GROUND_PROBE_DEPTH = 250

-- 2D: does the circle at (x, y) with radius `reach` overlap the sector with its apex at the
-- origin, its axis along +x, radius `range` and half-angle `halfAngle` (radians)? Both the flat
-- arc and the 3D cone reduce to this exactly (the cone by rotational symmetry about its axis).
local function sectorOverlap(
	x: number,
	y: number,
	reach: number,
	range: number,
	halfAngle: number
): boolean
	local side = math.abs(y)
	local distance = math.sqrt(x * x + side * side)
	if distance > range + reach then
		return false
	end
	if distance <= reach or halfAngle >= math.pi then
		return true
	end
	-- Inside the wedge: the nearest sector point lies on the same heading, at most `reach` away.
	if math.atan2(side, x) <= halfAngle then
		return true
	end
	-- Outside the wedge the nearest sector point is on the nearer straight edge (the arc's end
	-- is that edge's end), which also covers half-angles past 90 degrees.
	local edgeX = math.cos(halfAngle)
	local edgeY = math.sin(halfAngle)
	local along = math.clamp(x * edgeX + side * edgeY, 0, range)
	local dx = x - edgeX * along
	local dy = side - edgeY * along
	return dx * dx + dy * dy <= reach * reach
end

local function flatten(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < EPSILON then
		return nil
	end
	return flat.Unit
end

local function unitOf(vector: Vector3): Vector3?
	if vector.Magnitude < EPSILON then
		return nil
	end
	return vector.Unit
end

-- A seed as a Park–Miller state in [1, PM_MODULUS - 1]; any finite number is accepted.
local function seedState(seed: number): number
	return math.floor(math.abs(seed)) % (PM_MODULUS - 1) + 1
end

-- One Park–Miller step: the next state and a uniform draw in [0, 1].
local function advance(state: number): (number, number)
	local nextState = (state * PM_MULTIPLIER) % PM_MODULUS
	return nextState, (nextState - 1) / (PM_MODULUS - 1)
end

-- A horizontal sweep (a sword swing): `arcDegrees` is the whole sweep, centred on the flattened
-- `forward`. It is a slab, not a flat slice: the sphere counts if it overlaps the vertical band
-- from origin.Y - reachDown - pad to origin.Y + pad (so its centre may sit pad + r above or
-- reachDown + pad + r below the origin) and its circle, at full radius r + pad, overlaps the
-- sector in plan. reachDown (default 0) lets an airborne swing reach the crowd below.
function HitShapes.Arc(
	origin: Vector3,
	forward: Vector3,
	range: number,
	arcDegrees: number,
	pad: number,
	c: Vector3,
	r: number,
	reachDown: number?
): boolean
	local heading = flatten(forward)
	if heading == nil then
		return false
	end
	local offset = c - origin
	local down = math.max(reachDown or 0, 0)
	if offset.Y > pad + r or offset.Y < -(down + pad + r) then
		return false
	end
	local along = offset.X * heading.X + offset.Z * heading.Z
	local across = offset.Z * heading.X - offset.X * heading.Z
	return sectorOverlap(along, across, r + pad, range, math.rad(arcDegrees / 2))
end

function HitShapes.Sphere(
	center: Vector3,
	radius: number,
	pad: number,
	c: Vector3,
	r: number
): boolean
	return (c - center).Magnitude <= radius + pad + r
end

-- A thrust or charge line: every point within `radius` of the segment a–b.
function HitShapes.Capsule(
	a: Vector3,
	b: Vector3,
	radius: number,
	pad: number,
	c: Vector3,
	r: number
): boolean
	local segment = b - a
	local lengthSquared = segment:Dot(segment)
	local along = if lengthSquared < EPSILON
		then 0
		else math.clamp((c - a):Dot(segment) / lengthSquared, 0, 1)
	local closest = a + segment * along
	return (c - closest).Magnitude <= radius + pad + r
end

-- A spherical sector (a shotgun blast): apex at origin, `halfAngleDegrees` off the axis, out to
-- `range` from the apex.
function HitShapes.Cone(
	origin: Vector3,
	forward: Vector3,
	range: number,
	halfAngleDegrees: number,
	pad: number,
	c: Vector3,
	r: number
): boolean
	local axis = unitOf(forward)
	if axis == nil then
		return false
	end
	local offset = c - origin
	local along = offset:Dot(axis)
	local across = (offset - axis * along).Magnitude
	return sectorOverlap(along, across, r + pad, range, math.rad(halfAngleDegrees))
end

-- A bullet or beam with a thickness (`width` = diameter). Returns the distance along the ray at
-- which the padded ray first touches the sphere (0 when it starts inside), nil for a miss, so
-- callers can order pierce and pick the first thing a pellet meets.
function HitShapes.Ray(
	origin: Vector3,
	direction: Vector3,
	range: number,
	width: number,
	pad: number,
	c: Vector3,
	r: number
): number?
	local unit = unitOf(direction)
	if unit == nil or range <= 0 then
		return nil
	end
	local reach = width / 2 + pad + r
	local offset = c - origin
	local along = offset:Dot(unit)
	local nearest = math.clamp(along, 0, range)
	local miss = offset - unit * nearest
	if miss:Dot(miss) > reach * reach then
		return nil
	end
	local perpendicularSquared = math.max(0, offset:Dot(offset) - along * along)
	local entry = along - math.sqrt(math.max(0, reach * reach - perpendicularSquared))
	return math.clamp(entry, 0, range)
end

-- The cosmetic pellet pattern of a cone gun: `count` (at most MAX_PELLETS) unit directions
-- spread uniformly over the disc of half-angle `spreadDegrees` around `direction`, fully
-- determined by `seed` (the strike's `seq`), so every client draws the same tracers.
function HitShapes.Pellets(
	direction: Vector3,
	count: number,
	spreadDegrees: number,
	seed: number
): { Vector3 }
	local axis = unitOf(direction)
	local pellets: { Vector3 } = {}
	if axis == nil or count <= 0 then
		return pellets
	end
	local reference = if math.abs(axis.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local right = axis:Cross(reference).Unit
	local up = right:Cross(axis)
	local state = seedState(seed)
	local function nextUnit(): number
		local nextState, draw = advance(state)
		state = nextState
		return draw
	end
	local spread = math.rad(math.max(0, spreadDegrees))
	for _ = 1, math.min(math.floor(count), MAX_PELLETS) do
		-- sqrt keeps the density even across the disc instead of bunching at the centre.
		local tilt = spread * math.sqrt(nextUnit())
		local turn = FULL_TURN * nextUnit()
		local sideways = right * math.cos(turn) + up * math.sin(turn)
		table.insert(pellets, (axis * math.cos(tilt) + sideways * math.sin(tilt)).Unit)
	end
	return pellets
end

-- A split arrow's children: `count` (at most MAX_FAN) directions fanned evenly across
-- `arcDegrees` around `direction`, in the plane of `direction` and its horizontal
-- perpendicular, each nudged by HitShapes.Pellets(seed + index) jitter of up to `jitterShare`
-- (shooting.fanJitterShare; nil = none) of the gap between neighbours. Deterministic, so the
-- server and every client fan the same volley from the shot's seq and the same share.
function HitShapes.Fan(
	direction: Vector3,
	count: number,
	arcDegrees: number,
	seed: number,
	jitterShare: number?
): { Vector3 }
	local axis = unitOf(direction)
	local arrows: { Vector3 } = {}
	local total = math.min(math.floor(count), MAX_FAN)
	if axis == nil or total <= 0 then
		return arrows
	end
	local reference = if math.abs(axis.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local right = axis:Cross(reference).Unit
	local arc = math.rad(math.max(arcDegrees, 0))
	local gap = if total > 1 then arc / (total - 1) else 0
	local jitterDegrees = math.deg(gap) * math.max(jitterShare or 0, 0)
	for index = 1, total do
		local angle = if total > 1 then -arc / 2 + gap * (index - 1) else 0
		local base = (axis * math.cos(angle) + right * math.sin(angle)).Unit
		local nudged = HitShapes.Pellets(base, 1, jitterDegrees, seed + index)[1]
		table.insert(arrows, nudged or base)
	end
	return arrows
end

-- Cluster bomblets (P3 clusterShell): `count` (at most MAX_FAN) points evenly spaced on a flat
-- circle of radius `spacing` around `center`, the whole ring turned by ONE Park–Miller angle from
-- `seed` and nothing else, so the server and every client scatter the same bomblets.
function HitShapes.Scatter(
	center: Vector3,
	count: number,
	spacing: number,
	seed: number
): { Vector3 }
	local points: { Vector3 } = {}
	local total = math.min(math.floor(count), MAX_FAN)
	if not (total > 0) then
		return points
	end
	local _, draw = advance(seedState(seed))
	local turn = FULL_TURN * draw
	local gap = FULL_TURN / total
	for index = 0, total - 1 do
		local angle = turn + gap * index
		table.insert(
			points,
			center + Vector3.new(math.cos(angle) * spacing, 0, math.sin(angle) * spacing)
		)
	end
	return points
end

HitShapes.MAX_FAN = MAX_FAN
HitShapes.GROUND_PROBE_LIFT = GROUND_PROBE_LIFT
HitShapes.GROUND_PROBE_DEPTH = GROUND_PROBE_DEPTH

return HitShapes
