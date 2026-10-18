--!strict
-- L2 W2 (docs/prompts/l2-w2-contract.md, L2-34 and L2-35): the rules of the world's reactions.
-- Whether a resolved strike touches a reactive block, how many strikes of its element take it
-- away, and how far it has gone. Pure: numbers, tables and Vector3 values only, no service, no
-- Instance, no clock, so tools/crowd_harness tests the very rules LevelService runs. LevelService
-- holds the blocks and the heat, and only executes what is decided here.
--
-- Only a segment burns: a `capsule` (a flame stream, its reach cut at the first wall, so a stream
-- stopped by a bramble ends on its face) and a `ray`. Every other shape (arcs, spheres, cones:
-- Dragon's Breath's cones among them) touches nothing in W2; W3 adds the frost hammer's arc.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- What the rules read of a resolved strike (WeaponService's StrikeFx has these fields).
export type Strike = {
	shape: Types.HitShape,
	origin: Vector3,
	direction: Vector3,
	size: number,
	width: number?,
	endPoint: Vector3?,
}
-- An axis-aligned block: its centre and its size, studs.
export type Box = { x: number, y: number, z: number, sx: number, sy: number, sz: number }
-- Combat.json levels.react (Types.CombatReactConfig), as the rules read it.
export type Rules = { fireHits: number?, iceHits: number?, pad: number? }

local WorldReact = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function finitePoint(point: Vector3): boolean
	return finite(point.X) and finite(point.Y) and finite(point.Z)
end

-- A length that may be 0: a finite number of at least 0, else 0.
local function length(value: number?): number
	return if finite(value) and (value :: number) >= 0 then value :: number else 0
end

-- The segment a strike sweeps, start then end, for the shapes that burn; nil for every other
-- shape and for a strike whose numbers are not finite. A capsule runs `size` studs along its
-- direction; a ray ends at its endPoint when it has one (where it stopped), else `size` studs on.
function WorldReact.Segment(fx: Strike): (Vector3?, Vector3?)
	local shape = fx.shape
	if shape ~= "capsule" and shape ~= "ray" then
		return nil, nil
	end
	local origin = fx.origin
	if not finitePoint(origin) then
		return nil, nil
	end
	local finish = if shape == "ray" then fx.endPoint else nil
	if finish == nil then
		-- A size under 0 (or NaN) is no segment. A direction or a size that is not finite, and no
		-- direction at all (0 / 0), leave the end point not finite, which the check below refuses.
		local size = fx.size
		if not (size >= 0) then
			return nil, nil
		end
		local direction = fx.direction
		finish = origin + direction / direction.Magnitude * size
	end
	local stop = finish :: Vector3
	if not finitePoint(stop) then
		return nil, nil
	end
	return origin, stop
end

-- True when the strike's segment meets `box` grown on every side by the strike's width / 2 plus
-- `pad` (closed: grazing a grown face touches). A width or pad that is not a finite number of at
-- least 0 counts as 0; a box whose numbers are not finite, or whose size is not positive, is met
-- by nothing.
function WorldReact.Touches(fx: Strike, box: Box, pad: number): boolean
	local from, to = WorldReact.Segment(fx)
	if from == nil or to == nil then
		return false
	end
	if
		not (
			finite(box.x)
			and finite(box.y)
			and finite(box.z)
			and finite(box.sx)
			and finite(box.sy)
			and finite(box.sz)
			and box.sx > 0
			and box.sy > 0
			and box.sz > 0
		)
	then
		return false
	end
	local grow = length(fx.width) / 2 + length(pad)
	-- The slab test: the part of the segment (t from 0 to 1) inside each axis's span, narrowed
	-- axis by axis; empty on any axis = no touch.
	local low, high = 0, 1
	for _, axis in
		{
			{ from.X, to.X, box.x, box.sx },
			{ from.Y, to.Y, box.y, box.sy },
			{ from.Z, to.Z, box.z, box.sz },
		}
	do
		local a, b, centre, size = axis[1], axis[2], axis[3], axis[4]
		local min = centre - size / 2 - grow
		local max = centre + size / 2 + grow
		local delta = b - a
		if delta == 0 then
			if a < min or a > max then
				return false
			end
		else
			local enter = (min - a) / delta
			local leave = (max - a) / delta
			if enter > leave then
				enter, leave = leave, enter
			end
			low = math.max(low, enter)
			high = math.min(high, leave)
			if low > high then
				return false
			end
		end
	end
	return true
end

-- How many strikes of `element` take a block of that element away: Combat.json levels.react's
-- fireHits or iceHits, when it is a whole number of at least 1; nil otherwise (that element then
-- changes nothing), and for a word that is not an element.
function WorldReact.Need(rules: Rules?, element: string): number?
	if rules == nil then
		return nil
	end
	local hits: any = if element == "fire"
		then rules.fireHits
		elseif element == "ice" then rules.iceHits
		else nil
	if finite(hits) and hits >= 1 and hits % 1 == 0 then
		return hits
	end
	return nil
end

-- Combat.json levels.react's pad: a finite number of at least 0, else 0.
function WorldReact.Pad(rules: Rules?): number
	return length(if rules ~= nil then rules.pad else nil)
end

-- One more strike on a block that has taken `heat`: the new heat, and true when it reaches
-- `need` (the block goes). A need that is not a whole number of at least 1 adds nothing and
-- never takes the block.
function WorldReact.Heat(heat: number, need: number): (number, boolean)
	if not (finite(need) and need >= 1 and need % 1 == 0) then
		return heat, false
	end
	local now = heat + 1
	return now, now >= need
end

-- The share of the way a block has gone, 0 to 1 (its Part's `Heat` attribute).
function WorldReact.Share(heat: number, need: number): number
	if not (finite(need) and need >= 1) or not finite(heat) then
		return 0
	end
	return math.clamp(heat / need, 0, 1)
end

return WorldReact
