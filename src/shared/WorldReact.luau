--!strict
-- L2 W2 (docs/prompts/l2-w2-contract.md, L2-34 and L2-35): the rules of the world's reactions.
-- Whether a resolved strike touches a reactive block, how many strikes of its element take it
-- away, and how far it has gone. Pure: numbers, tables and Vector3 values only, no service, no
-- Instance, no clock, so tools/crowd_harness tests the very rules LevelService runs. LevelService
-- holds the blocks and the heat, and only executes what is decided here (StrikeElement, then
-- Apply); phone auto-fire asks Wants whether a reactive Part is worth holding the stream on.
-- WeaponService's aim rule asks OriginClear and AimClear whether a shot origin lies on the head's
-- side of the walls (fix round d-m3, second fix round m2).
--
-- Only a segment burns: a `capsule` (a flame stream, its reach cut at the first wall, so a stream
-- stopped by a bramble ends on its face) and a `ray`. Every other shape (arcs, spheres, cones:
-- Dragon's Breath's cones among them) touches nothing of fire.
--
-- L2 W3 (docs/prompts/l2-w3-contract.md, L2-53 and L2-54): only an arc freezes. Deep water is cut
-- into cells built with the level (Cells); a frost swing freezes each cell whose top it reaches
-- down to and whose centre lies in its sector, a patch ahead of the swinger (Chills, Freeze). The
-- server runs Freeze on every resolved strike; the phone's auto-swing and the swinger's predicted
-- ghost ask Chills of the same cells, so the three never disagree on which water a swing takes.
-- The W3 fix round puts the rest of that agreement here too: the strike a swing makes
-- (SwingStrike, c-m3), the two config numbers Freeze reads (IceReach, d-m5), how a cell shows
-- (IceLook), which blocks are reactive (Reactive) and the cell's attribute name (ICE_ATTRIBUTE,
-- s-s3), so a copy on one side cannot drift from the other unseen (s-m1).

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
	-- An arc's whole sweep, degrees (360 or more = all round); nil for the other shapes.
	arcDegrees: number?,
	width: number?,
	endPoint: Vector3?,
}
-- An axis-aligned block: its centre and its size, studs.
export type Box = { x: number, y: number, z: number, sx: number, sy: number, sz: number }
-- Combat.json levels.react (Types.CombatReactConfig), as the rules read it.
export type Rules = Types.CombatReactConfig
-- L2-53: one ice cell of the built level as Freeze reads it: its piece's box and whether it has
-- frozen (Freeze writes it; it stays frozen until the run ends).
export type IceCell = { box: Box, frozen: boolean }
-- One reactive block as Apply reads it: the element that takes it away, its box, and how many
-- strikes of that element it has taken (Apply writes the new count back).
export type Entry = { react: string, box: Box, heat: number }
-- AimClear's world: the first solid on the segment from `from` to `to`, as a distance from `from`
-- (nil = none). Like a Roblox ray, it does not see a part that holds `from`.
export type Cast = (from: Vector3, to: Vector3) -> number?
-- How an ice cell's Part shows (IceLook): its transparency, whether bodies, rays and the camera
-- meet it (CanCollide and CanQuery), whether it casts a shadow, and its ICE_ATTRIBUTE.
export type IceLook = { transparency: number, collide: boolean, shadow: boolean, frozen: boolean }

local WorldReact = {}

-- The fix round's s-s3: an ice cell Part's attribute, false as built and true once frozen. Infrastructure,
-- like a remote's name: LevelService writes it, ReactFx and the phone's auto-swing find the cells by it,
-- and both read it from here, so a rename on one side cannot hide every cell from the other.
WorldReact.ICE_ATTRIBUTE = "Ice"

-- Studs a carried head (AimClear) stops short of the first solid on its way: under the R15 head's
-- half width (0.6), so it is a place a head can be and a ray from it still sees that solid.
local LEAD_STANDOFF = 0.5

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

-- How many strikes of fire take a fire block away: Combat.json levels.react's fireHits, when it
-- is a whole number of at least 1; nil otherwise (fire then changes nothing), and for every other
-- word: ice is never counted (L2-54, Freeze takes a cell at its first chill).
function WorldReact.Need(rules: Rules?, element: string): number?
	if rules == nil then
		return nil
	end
	local hits: any = if element == "fire" then rules.fireHits else nil
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

-- The fix round's s-m1: is a block with this `react` one LevelService lists as reactive (a Part
-- with `React` and `Heat`, taken away strike by strike: Apply)? Any word but "ice": an ice block is
-- deep water, and its cells are what freezes (L2-53), so ReactFx and the phone's stream never see
-- it as a block to burn. No react: none.
function WorldReact.Reactive(react: string?): boolean
	return react ~= nil and react ~= "ice"
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

-- L2-53: how many cells a block's footprint is cut into, along X and along Z: ceil(side / cell)
-- each, so no cell is wider than `cell`. 0, 0 for a cell that is not a finite number above 0, or a
-- footprint whose size is not.
function WorldReact.CellGrid(box: Box, cell: number): (number, number)
	if
		not (
			finite(cell)
			and cell > 0
			and finite(box.sx)
			and finite(box.sz)
			and box.sx > 0
			and box.sz > 0
		)
	then
		return 0, 0
	end
	return math.ceil(box.sx / cell), math.ceil(box.sz / cell)
end

-- L2-53: the block's footprint divided evenly into CellGrid's cells, X fastest then Z (the k-th
-- cell is the piece Ice_<block>_<k>). Each keeps the block's y and sy; LevelGeometry sets the
-- piece's own height. Empty for no grid, or a centre that is not finite.
function WorldReact.Cells(box: Box, cell: number): { Box }
	local cells: { Box } = {}
	local nx, nz = WorldReact.CellGrid(box, cell)
	if nx == 0 or nz == 0 or not (finite(box.x) and finite(box.z)) then
		return cells
	end
	local wide, deep = box.sx / nx, box.sz / nz
	local west, north = box.x - box.sx / 2, box.z - box.sz / 2
	for j = 1, nz do
		for i = 1, nx do
			table.insert(cells, {
				x = west + (i - 0.5) * wide,
				y = box.y,
				z = north + (j - 0.5) * deep,
				sx = wide,
				sy = box.sy,
				sz = deep,
			})
		end
	end
	return cells
end

-- The fix round's c-m3: the strike a melee swing hands to WeaponService's finish() and its
-- listeners, built in one place for the server (resolveMelee) and for the two client copies that
-- predict it (the frost ghost and the phone's auto-swing at water): the variant's shape, the
-- origin, `heading` as given (the server's is flat), `size` = the variant's range (never range +
-- pad: the pad forgives a body, the water's reach is Chills' `ahead`), its width, and the arc of
-- combo `step`: the chain's last step sweeps finisherArcDegrees when the variant has one, every
-- other step (and a variant with no chain) its arcDegrees.
function WorldReact.SwingStrike(
	variant: Types.RangeWeaponVariant,
	step: number,
	origin: Vector3,
	heading: Vector3
): Strike
	local chain = variant.chain
	local arcDegrees = variant.arcDegrees
	if chain ~= nil and step == #chain and variant.finisherArcDegrees ~= nil then
		arcDegrees = variant.finisherArcDegrees
	end
	return {
		shape = variant.shape,
		origin = origin,
		direction = heading,
		size = variant.range,
		arcDegrees = arcDegrees,
		width = variant.width,
	}
end

-- The fix round's d-m5: the two numbers of Combat.json levels.react.ice that Freeze and Chills
-- read, `reachDown` then `ahead`, each only when it is a number (nil otherwise: nothing freezes).
-- One reading for the server's freeze and the client's copies, so no caller can swap them.
function WorldReact.IceReach(ice: any): (number?, number?)
	if type(ice) ~= "table" then
		return nil, nil
	end
	local reachDown: number? = if type(ice.reachDown) == "number" then ice.reachDown else nil
	local ahead: number? = if type(ice.ahead) == "number" then ice.ahead else nil
	return reachDown, ahead
end

-- The fix round's s-m1: how an ice cell's Part shows. Water (as built): hidden, met by nothing,
-- no shadow, ICE_ATTRIBUTE false. Frozen: floor in its look's transparency `shown`, met by bodies,
-- rays and the camera, a shadow, ICE_ATTRIBUTE true.
function WorldReact.IceLook(frozen: boolean, shown: number): IceLook
	if frozen then
		return { transparency = shown, collide = true, shadow = true, frozen = true }
	end
	return { transparency = 1, collide = false, shadow = false, frozen = false }
end

-- L2-54: does this resolved strike freeze the ice cell `box`? Only an `arc` (a melee swing) does,
-- when the cell's top lies from the swing's origin down to `reachDown` under it (a swing from
-- the bank reaches over the edge; one from a high jump or a plateau does not), and the cell's
-- centre lies, in plan, within the swing's size + `ahead` of the origin and within half its
-- arcDegrees of its flat direction (360 or more = all round; a centre right under the origin is
-- in every sector). An arc of 0 or less, no arcDegrees, a direction with no flat part and any
-- number that is not finite: false.
function WorldReact.Chills(fx: Strike, box: Box, reachDown: number, ahead: number): boolean
	if fx.shape ~= "arc" then
		return false
	end
	local origin, direction, arc = fx.origin, fx.direction, fx.arcDegrees
	if
		not (
			finitePoint(origin)
			and finitePoint(direction)
			and finite(fx.size)
			and finite(arc)
			and finite(reachDown)
			and finite(ahead)
			and finite(box.x)
			and finite(box.y)
			and finite(box.z)
			and finite(box.sy)
		)
	then
		return false
	end
	local sweep = arc :: number
	if not (sweep > 0) then
		return false
	end
	local top = box.y + box.sy / 2
	if not (top <= origin.Y and top >= origin.Y - reachDown) then
		return false
	end
	local dx, dz = box.x - origin.X, box.z - origin.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	if not (distance <= fx.size + ahead) then
		return false
	end
	if sweep >= 360 or distance == 0 then
		return true
	end
	local hx, hz = direction.X, direction.Z
	local heading = math.sqrt(hx * hx + hz * hz)
	if not (heading > 0) then
		return false
	end
	local cosine = (dx * hx + dz * hz) / (distance * heading)
	return cosine >= math.cos(math.rad(sweep / 2))
end

-- L2-54: one strike of `element` on the level's ice cells. With "ice", every cell not yet frozen
-- that Chills names is set frozen; returns their indices, ascending. Any other element, or none
-- (an ability's strike: StrikeElement), changes nothing and returns none.
function WorldReact.Freeze(
	cells: { IceCell },
	element: string?,
	fx: Strike,
	reachDown: number,
	ahead: number
): { number }
	local frozen: { number } = {}
	if element ~= "ice" then
		return frozen
	end
	for index, cell in cells do
		if not cell.frozen and WorldReact.Chills(fx, cell.box, reachDown, ahead) then
			cell.frozen = true
			table.insert(frozen, index)
		end
	end
	return frozen
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

-- The L2 W2 second fix round's m2: the server's copy of the head trails a fast player by the lag
-- the aim rule's distance test excuses, so round a corner or off an edge an honest origin's line
-- from it crossed the wall. LeadHead carries the head `lag` seconds along `motion`, the way the
-- position ring's fastest stretch went (PositionRing.Motion), at `speed`: claimSlack's, that
-- stretch's speed capped at Tuning.FastestMove. So the lead never lies further from the head than
-- the slack the distance test grants. The third fix round's m1: the way is the server's own
-- measure, never the client's: a character's replicated `velocity` is whatever its client says,
-- and led along it a forger reached round a wall's end. That velocity may only shorten the lead
-- (its part along `motion`, floored at 0), so a player who has stopped is not carried on. A head,
-- way or velocity that is not finite, no way at all, or a speed or lag that is not a finite
-- number above 0, leads nowhere: the head itself.
function WorldReact.LeadHead(
	head: Vector3,
	motion: Vector3,
	velocity: Vector3,
	speed: number,
	lag: number
): Vector3
	if not (finitePoint(head) and finitePoint(motion) and finitePoint(velocity)) then
		return head
	end
	local magnitude = motion.Magnitude
	if not (magnitude > 0) then
		return head
	end
	local way = motion / magnitude
	local along = math.max(velocity:Dot(way), 0)
	return head + way * (math.min(along, length(speed)) * length(lag))
end

-- OriginClear on the line from `from` to `to`: the ray forward and, only when it hit, the ray back.
local function lineClear(from: Vector3, to: Vector3, tolerance: number, cast: Cast): boolean
	local forward = cast(from, to)
	local backward = if forward ~= nil then cast(to, from) else nil
	return WorldReact.OriginClear((to - from).Magnitude, forward, backward, tolerance)
end

-- The aim rule whole (fix round d-m3, second fix round m2). A shot origin is allowed when the line
-- from the server's `head` to it is clear (OriginClear: up to `tolerance` studs of solid), or else
-- when the line from the carried head is. The carried head is `lead` (LeadHead) cut back
-- LEAD_STANDOFF short of the first solid on the way from the head, so it always stands on the
-- head's side of every wall: a forged origin beyond a wall thicker than `tolerance` stays refused
-- however the velocity was claimed, while an honest player rounding a bend at a dash is judged from
-- about where his own screen had him. `cast` is the world (WeaponService casts Roblox rays through
-- its world query; the harness a box caster).
function WorldReact.AimClear(
	head: Vector3,
	lead: Vector3,
	origin: Vector3,
	tolerance: number,
	cast: Cast
): boolean
	if lineClear(head, origin, tolerance, cast) then
		return true
	end
	local reach = lead - head
	local distance = reach.Magnitude
	if not (distance > 0 and finite(distance)) then
		return false
	end
	local hit = cast(head, lead)
	local carried = if hit ~= nil
		then head + reach * (math.max(hit - LEAD_STANDOFF, 0) / distance)
		else lead
	return lineClear(carried, origin, tolerance, cast)
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
