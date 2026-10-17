--!strict
-- L1c (docs/prompts/l1c-contract.md, L1c-5a and §8): two rules that keep a walled camp's inside
-- hidden from anyone outside it. Pure: no Instance, no clock; the callers cast the rays and read
-- the config, so tools/crowd_harness tests the very functions the game runs.
--
-- * Reach: the camera's boom. An open gate is CanQuery false, so the camera's spherecast passes
--   through it; a camera swung behind a player at a locking camp's gate would end inside the camp
--   and show what its wall hides. The boom is cut where it would come within a margin of the
--   fenced rectangle of a camp the local root is not inside (Clip below). Walls elsewhere keep
--   doing that job through the spherecast.
-- * TooHigh / Rise: an aimed ability's ground point. Leap Smash's target is a camera ray pulled
--   back to castRange and dropped onto the floor there, so a player who aims over a tall wall can
--   land the probe on the wall's top: a perch that sees everything. A ground point higher above
--   the caster's floor than the caster's own jumps reach is refused: a jump, plus the double jump
--   for a player who owns it (L2-4). WeaponService.GroundPoint (server) and
--   InputController.groundPoint (client) ask the same question with the same numbers.
-- * CasterFloor / LeapApex (L2 W1 §11, F2 and F1): the two holes that let a player without the
--   double jump leap onto a ledge his jumps cannot reach. Over a void the caster's floor was his
--   own feet, so a jump off a cliff made ground a jump above the road a legal target; and a leap
--   cast at the top of a jump stacked its height on the jump. Both callers above and
--   MovementController.Leap use these, so client and server share one rule. The two ground-point
--   callers go through GroundFloor, which is the whole of their step 4, by way of GroundRule.Floor
--   (which reads its movement and double-jump inputs, so neither caller writes them).

-- A locking camp's fenced rectangle: centre and half sizes on the flat, and `y` its floor's top
-- (Types.RunFloor's numbers, the halves grown by the fence), studs. `ceiling`: how far above `y` a
-- root still counts as inside (RunFloor.ceiling, the camp's trigger band: a walled camp's fence
-- top); nil, or not a finite number, = the clip's `height`.
export type Rect = { x: number, y: number, z: number, hx: number, hz: number, ceiling: number? }
-- How a boom is cut (the L1c fix round's C1 and m1):
-- * pad: studs short of the edge the boom would cross (COMBAT_CAMERA_COLLISION_PAD);
-- * margin: studs each rectangle is grown by for the cut alone (Combat.json levels.cameraClear).
--   A boom swung back toward an open gate would otherwise end in its mouth, from where the sides
--   of the view see along the inner wall; grown, it stops that far short of the fence line;
-- * height: a root is inside a rectangle only up to this far above its floor (levels.triggerHeight)
--   when the rectangle names no ceiling of its own. A rectangle's ceiling is the band StageFlow's
--   trigger asks of that camp (the L1c second fix round's F1): up to a walled camp's fence top, so
--   a fighter inside who double-jumps from cover keeps the boom, and a root in the gate's opening
--   at the top of a jump has triggered the camp.
-- Whether the root is inside is always judged on the true rectangle, never the grown one: a root
-- standing in the margin would otherwise free the boom to run through the gate into the camp.
export type Clip = { pad: number, margin: number, height: number }

local WallClip = {}

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- A pad or margin that is not a positive finite number is none.
local function length(value: number): number
	return if value > 0 and value ~= math.huge then value else 0
end

-- A rectangle a caller built from bad data (NaN, infinite, a negative half) cannot be judged and
-- is skipped, as CrowdRenderer drops a malformed floor.
local function usable(rect: Rect): boolean
	return finite(rect.x)
		and finite(rect.y)
		and finite(rect.z)
		and finite(rect.hx)
		and finite(rect.hz)
		and rect.hx >= 0
		and rect.hz >= 0
end

-- Closed: a root on the rectangle's edge is inside, as StageFlow's trigger counts one on the fence;
-- and no higher than the rectangle's ceiling (else `height`) above its floor. A root that is not a
-- number is in none.
local function holds(rect: Rect, x: number, y: number, z: number, height: number): boolean
	local ceiling = rect.ceiling
	local top = if ceiling ~= nil and finite(ceiling) then ceiling else height
	return math.abs(x - rect.x) <= rect.hx and math.abs(z - rect.z) <= rect.hz and y - rect.y <= top
end

-- The first share t of the segment from (fromX, fromZ) along (dx, dz), 0 <= t <= 1, that lies in
-- the closed rectangle centred on (cx, cz) with halves (hx, hz); nil = none of it. 0 = it starts
-- inside. Numbers, not a table, so the camera's frame allocates nothing.
local function entry(
	fromX: number,
	fromZ: number,
	dx: number,
	dz: number,
	cx: number,
	cz: number,
	hx: number,
	hz: number
): number?
	local first, last = 0, 1
	for axis = 1, 2 do
		local start = if axis == 1 then fromX else fromZ
		local step = if axis == 1 then dx else dz
		local low = if axis == 1 then cx - hx else cz - hz
		local high = if axis == 1 then cx + hx else cz + hz
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
-- rectangle of `rects` that does not hold the root (rootX, rootY, rootZ), each grown by
-- clip.margin, pulled back clip.pad studs along the boom from the first edge it would cross. 0
-- when the boom starts inside such a grown rectangle; 1 when nothing cuts it, or when the boom
-- itself is not a number (nothing can be measured, so the camera is left as it was). A root that
-- is not a number is held by no rectangle: every one of them cuts.
function WallClip.Reach(
	fromX: number,
	fromZ: number,
	dx: number,
	dz: number,
	rects: { Rect },
	rootX: number,
	rootY: number,
	rootZ: number,
	clip: Clip
): number
	if not (finite(fromX) and finite(fromZ) and finite(dx) and finite(dz)) then
		return 1
	end
	local boom = math.sqrt(dx * dx + dz * dz)
	local back = length(clip.pad)
	local grow = length(clip.margin)
	local share = 1
	for _, rect in rects do
		if usable(rect) and not holds(rect, rootX, rootY, rootZ, clip.height) then
			local at = entry(fromX, fromZ, dx, dz, rect.x, rect.z, rect.hx + grow, rect.hz + grow)
			if at ~= nil then
				share = math.min(share, if at <= 0 then 0 else math.max(at - back / boom, 0))
			end
		end
	end
	return share
end

-- How far above the caster's floor a ground point may stand: a jump, and the double jump on top
-- when the caster owns it (L2-4, `airJump`: the server reads its own Player attribute). The
-- heights are the range's ProvingGrounds.json `movement`, never re-typed.
function WallClip.Rise(
	movement: { jumpHeight: number, doubleJumpHeight: number },
	airJump: boolean
): number
	return movement.jumpHeight + (if airJump then movement.doubleJumpHeight else 0)
end

-- True when a ground point at targetY stands more than `rise` above the caster's floor at
-- floorY: the cast is refused. Exactly `rise` above is allowed.
function WallClip.TooHigh(floorY: number, targetY: number, rise: number): boolean
	return targetY - floorY > rise
end

-- F2: the floor a ground point is measured from. `probed`, the floor a ray found under the caster,
-- when there is one; over a void (nil) the caster's feet less his own rise, so nobody targets
-- ground above the height his jumps would have carried him from wherever he stood.
function WallClip.CasterFloor(probed: number?, feetY: number, rise: number): number
	return if probed ~= nil then probed else feetY - rise
end

-- Step 4 of an aimed ability's ground point, whole (the fix round's c4): the one call
-- WeaponService.GroundPoint and InputController.groundPoint both make, so no copy of it can drift.
-- `probedCaster` / `probedTarget`: the floors a ray found under the caster and under the aimed
-- point (nil = a void); `feetY` the caster's feet; `airJump` the raw `Ability_doubleJump`
-- attribute, of which only `true` counts as owned. Returns the ground point's floor (the probed
-- one, else level with the caster's floor) or nil when it is higher above the caster's floor than
-- his rise (refused), and that caster's floor (F2), from which the leap's apex is measured (F1).
function WallClip.GroundFloor(
	probedCaster: number?,
	feetY: number,
	probedTarget: number?,
	movement: { jumpHeight: number, doubleJumpHeight: number },
	airJump: unknown
): (number?, number)
	local rise = WallClip.Rise(movement, airJump == true)
	local casterFloor = WallClip.CasterFloor(probedCaster, feetY, rise)
	local floorY = if probedTarget ~= nil then probedTarget else casterFloor
	if WallClip.TooHigh(casterFloor, floorY, rise) then
		return nil, casterFloor
	end
	return floorY, casterFloor
end

-- F1: a leap's apex, as root heights. `fromY` the root at the cast, `toY` the root standing on the
-- target, `floorY` the caster's floor (CasterFloor) and `standing` the root's height over a floor
-- it stands on. The lift goes over the higher of the target and the caster's floor, never over an
-- airborne root, so a cast at the top of a jump does not add `height` on top of the jump; cast
-- from the ground, the root stands at floorY + standing and the apex is what it always was. A
-- height that is not a positive number lifts nothing.
function WallClip.LeapApex(
	fromY: number,
	toY: number,
	floorY: number,
	standing: number,
	height: number
): number
	local lift = if height > 0 then height else 0
	return math.max(fromY, toY + lift, floorY + standing + lift)
end

return WallClip
