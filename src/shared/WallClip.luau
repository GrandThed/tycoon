--!strict
-- L1c (docs/prompts/l1c-contract.md, L1c-5a and §8): two rules that keep a walled camp's inside
-- hidden from anyone outside it. Pure: no Instance, no clock; the callers cast the rays and read
-- the config, so tools/crowd_harness tests the very functions the game runs.
--
-- * Reach: the camera's boom. An open gate is CanQuery false, so the camera's spherecast passes
--   through it; a camera swung behind a player at a locking camp's gate would end inside the camp
--   and show what its wall hides. The boom is cut where it would enter the fenced rectangle of a
--   camp the local root is not inside. Walls elsewhere keep doing that job through the spherecast.
-- * TooHigh / Rise: an aimed ability's ground point. Leap Smash's target is a camera ray pulled
--   back to castRange and dropped onto the floor there, so a player who aims over a tall wall can
--   land the probe on the wall's top: a perch that sees everything. A ground point higher above
--   the caster's floor than a jump and a double jump reach is refused. WeaponService.GroundPoint
--   (server) and InputController.groundPoint (client) ask the same question with the same numbers.

-- A flat rectangle: centre and half sizes, studs (Types.CampRect's shape).
export type Rect = { x: number, z: number, hx: number, hz: number }

local WallClip = {}

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- A rectangle a caller built from bad data (NaN, infinite, a negative half) cannot be judged and
-- is skipped, as CrowdRenderer drops a malformed floor.
local function usable(rect: Rect): boolean
	return finite(rect.x)
		and finite(rect.z)
		and finite(rect.hx)
		and finite(rect.hz)
		and rect.hx >= 0
		and rect.hz >= 0
end

-- Closed: a root on the rectangle's edge is inside, as StageFlow's trigger counts one on the fence.
local function holds(rect: Rect, x: number, z: number): boolean
	return math.abs(x - rect.x) <= rect.hx and math.abs(z - rect.z) <= rect.hz
end

-- The first share t of the segment from (fromX, fromZ) along (dx, dz), 0 <= t <= 1, that lies in
-- the closed rectangle; nil = none of it. 0 = it starts inside.
local function entry(fromX: number, fromZ: number, dx: number, dz: number, rect: Rect): number?
	local first, last = 0, 1
	for axis = 1, 2 do
		local start = if axis == 1 then fromX else fromZ
		local step = if axis == 1 then dx else dz
		local low = if axis == 1 then rect.x - rect.hx else rect.z - rect.hz
		local high = if axis == 1 then rect.x + rect.hx else rect.z + rect.hz
		if step == 0 then
			if start < low or start > high then
				return nil
			end
		else
			local a, b = (low - start) / step, (high - start) / step
			if a > b then
				a, b = b, a
			end
			first = math.max(first, a)
			last = math.min(last, b)
			if first > last then
				return nil
			end
		end
	end
	return first
end

-- The share 0..1 of the flat boom from (fromX, fromZ) along (dx, dz) that stays outside every
-- rectangle of `rects` that does not hold the root (rootX, rootZ), pulled back `pad` studs along
-- the boom from the first edge it would cross. 0 when the boom starts inside such a rectangle;
-- 1 when nothing cuts it, or when the boom itself is not a number (nothing can be measured, so
-- the camera is left as it was). A NaN root is held by no rectangle: every one of them cuts.
function WallClip.Reach(
	fromX: number,
	fromZ: number,
	dx: number,
	dz: number,
	rects: { Rect },
	rootX: number,
	rootZ: number,
	pad: number
): number
	if not (finite(fromX) and finite(fromZ) and finite(dx) and finite(dz)) then
		return 1
	end
	local length = math.sqrt(dx * dx + dz * dz)
	local back = if pad > 0 and pad ~= math.huge then pad else 0
	local share = 1
	for _, rect in rects do
		if usable(rect) and not holds(rect, rootX, rootZ) then
			local at = entry(fromX, fromZ, dx, dz, rect)
			if at ~= nil then
				share = math.min(share, if at <= 0 then 0 else math.max(at - back / length, 0))
			end
		end
	end
	return share
end

-- How far above the caster's floor a ground point may stand: a jump and a double jump (the
-- range's ProvingGrounds.json `movement`, never re-typed).
function WallClip.Rise(movement: { jumpHeight: number, doubleJumpHeight: number }): number
	return movement.jumpHeight + movement.doubleJumpHeight
end

-- True when a ground point at targetY stands more than `rise` above the caster's floor at
-- floorY: the cast is refused. Exactly `rise` above is allowed.
function WallClip.TooHigh(floorY: number, targetY: number, rise: number): boolean
	return targetY - floorY > rise
end

return WallClip
