--!strict
-- Pure hit geometry for the Proving Grounds (docs/INTERFACES.md "P1 contracts" → decision 2).
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

-- A flat horizontal slice (a sword swing): `arcDegrees` is the whole sweep, centred on the
-- flattened `forward`. The slice has no thickness of its own; pad + r is the vertical reach too.
function HitShapes.Arc(
	origin: Vector3,
	forward: Vector3,
	range: number,
	arcDegrees: number,
	pad: number,
	c: Vector3,
	r: number
): boolean
	local heading = flatten(forward)
	if heading == nil then
		return false
	end
	local offset = c - origin
	local reachTotal = r + pad
	if math.abs(offset.Y) > reachTotal then
		return false
	end
	-- The sphere's cross-section in the slice's plane.
	local reach = math.sqrt(reachTotal * reachTotal - offset.Y * offset.Y)
	local along = offset.X * heading.X + offset.Z * heading.Z
	local across = offset.Z * heading.X - offset.X * heading.Z
	return sectorOverlap(along, across, reach, range, math.rad(arcDegrees / 2))
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

-- The pellet pattern of a cone gun: `count` unit directions spread uniformly over the disc of
-- half-angle `spreadDegrees` around `direction`, fully determined by `seed` (the attack's seq),
-- so a client can draw the exact tracers the server resolved.
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
	local state = math.floor(math.abs(seed)) % (PM_MODULUS - 1) + 1
	local function nextUnit(): number
		state = (state * PM_MULTIPLIER) % PM_MODULUS
		return (state - 1) / (PM_MODULUS - 1)
	end
	local spread = math.rad(math.max(0, spreadDegrees))
	for _ = 1, math.floor(count) do
		-- sqrt keeps the density even across the disc instead of bunching at the centre.
		local tilt = spread * math.sqrt(nextUnit())
		local turn = FULL_TURN * nextUnit()
		local sideways = right * math.cos(turn) + up * math.sin(turn)
		table.insert(pellets, (axis * math.cos(tilt) + sideways * math.sin(tilt)).Unit)
	end
	return pellets
end

return HitShapes
