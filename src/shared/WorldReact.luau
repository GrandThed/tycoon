--!strict
-- L2 W2 (docs/prompts/l2-w2-contract.md, L2-34 and L2-35): the rules of the world's reactions.
-- Whether a resolved strike touches a reactive block, how many strikes of its element take it
-- away, and how far it has gone. Pure: numbers, tables and Vector3 values only, no service, no
-- Instance, no clock, so tools/crowd_harness tests the very rules LevelService runs. LevelService
-- holds the blocks and the heat, and only executes what is decided here (StrikeElement, then
-- Apply); phone auto-fire asks Wants whether a reactive Part is worth holding the stream on.
--
-- Only a segment burns: a `capsule` (a flame stream, its reach cut at the first wall, so a stream
-- stopped by a bramble ends on its face) and a `ray`. Every other shape (arcs, spheres, cones:
-- Dragon's Breath's cones among them) touches nothing in W2; W3 adds the frost hammer's arc.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

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
-- One reactive block as Apply reads it: the element that takes it away, its box, and how many
-- strikes of that element it has taken (Apply writes the new count back).
export type Entry = { react: string, box: Box, heat: number }

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

-- The element a resolved strike carries to the world: its family's (Unlocks.ElementOf) for an
-- attack, none for an ability's strike. L2-34 says Dragon's Breath burns nothing, and an
-- ability's capsule is built from its end point without the wall cut an attack's stream gets,
-- so a later capsule ability would otherwise heat a bramble through the ridge (fix round s-m2).
function WorldReact.StrikeElement(
	weapons: { [string]: Types.RangeWeaponDef }?,
	weapon: string,
	ability: string?
): Types.Element?
	if ability ~= nil then
		return nil
	end
	return Unlocks.ElementOf(weapons, weapon)
end

-- One strike of `element` on the level's reactive blocks (fix round s-m1: LevelService.React's
-- loop, here so the harness holds it). Every entry whose `react` is that element and whose box
-- the strike touches (Touches, grown by `pad`) takes one strike (Heat with `need`), written back
-- to its `heat`. Returns the indices of the entries that go (`gone`, highest first, so removing
-- them in that order leaves the others' indices right) and of those that only heated (`heated`,
-- highest first). Read `heated` before removing `gone`. No element, or a need that is not a count,
-- changes nothing.
function WorldReact.Apply(
	entries: { Entry },
	element: string?,
	fx: Strike,
	pad: number,
	need: number
): ({ number }, { number })
	local gone: { number } = {}
	local heated: { number } = {}
	if element == nil then
		return gone, heated
	end
	for index = #entries, 1, -1 do
		local entry = entries[index]
		if entry.react ~= element or not WorldReact.Touches(fx, entry.box, pad) then
			continue
		end
		local heat, done = WorldReact.Heat(entry.heat, need)
		if heat == entry.heat then
			continue
		end
		entry.heat = heat
		table.insert(if done then gone else heated, index)
	end
	return gone, heated
end

-- An axis-aligned Part's box (level blocks are never turned, LevelGeometry).
function WorldReact.BoxOf(position: Vector3, size: Vector3): Box
	return { x = position.X, y = position.Y, z = position.Z, sx = size.X, sy = size.Y, sz = size.Z }
end

-- Fix round d-m3: whether a shot's origin (a client's claim, already within reach of the head)
-- lies on the head's side of the walls. `distance` is head to origin; `forward` is where a ray
-- from the head toward the origin first met a solid (nil = nothing: clear); `backward` is where
-- the reverse ray, from the origin toward the head, first met one (nil while `forward` hit = the
-- origin sits inside a solid, where a shot would leave through the far face). Between the two
-- hits lies solid, or open ground between two solids; up to `tolerance` studs of it is allowed,
-- because the honest origin sits 1.5 to 2 studs to the shoulder side of the head and its line
-- cuts the edge of a wall the player hugs at an inner corner. A wall thicker than `tolerance`
-- still refuses every origin beyond it (the line crosses at least its thickness). Numbers that are not finite refuse.
function WorldReact.OriginClear(
	distance: number,
	forward: number?,
	backward: number?,
	tolerance: number
): boolean
	if forward == nil then
		return true
	end
	if backward == nil or not (finite(distance) and finite(forward) and finite(backward)) then
		return false
	end
	local chord = distance - (backward :: number) - (forward :: number)
	return chord <= length(tolerance)
end

-- Fix round c-M1: whether phone auto-fire holds the stream on a reactive Part. Its `React`
-- attribute (`react`) must name `element`, the held family's (one of the two words); its `Heat`
-- attribute (`heat`, 0 to 1, nil before the first strike) must be under 1; and the stream's
-- capsule, cut at the first wall, must touch its box grown by the pad. Resting bodies are the
-- auto-fire's own rule, not this one.
function WorldReact.Wants(
	element: string?,
	react: any,
	heat: any,
	fx: Strike,
	box: Box,
	pad: number
): boolean
	if not Unlocks.IsElement(element) or react ~= element then
		return false
	end
	local share = if heat == nil then 0 elseif finite(heat) then heat :: number else 1
	return share < 1 and WorldReact.Touches(fx, box, pad)
end

return WorldReact
