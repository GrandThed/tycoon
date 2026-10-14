--!strict
-- L1b-W2-13/14 (docs/INTERFACES.md "Wave 2 — the long road"): one melee swing per jump. The
-- server (WeaponService) and the client (AirSwing) feed this rule the same samples and ask it
-- the same questions, so the client never sends a swing the server would refuse. Pure: no
-- Instance, no clock; callers cast the rays.
--
-- Fix round A-1 (docs/prompts/l1b-w2-fix-round.md): "has landed" and "is grounded" are ONE rule.
-- * Grounded = the root within its standing height plus AIR_MARGIN_STUDS of the HIGHEST floor
--   under its footprint (the centre and the four corners of the root's own rectangle), so a
--   ledge's lip, a fence top or a cover block under any corner reads grounded.
-- * A landing is a fall that ends grounded, or a fall that turns into a rise close enough to the
--   floor that the samples may have stepped over the contact: a held-Space hop touches the floor
--   for one physics step, which a 60 Hz sample (or a copy replicated slower) can miss. "Close
--   enough" is the distance the fall covers in TURN_WINDOW_SECONDS at its fastest, so a double
--   jump high in the air (slow fall, far floor) is never a landing.
-- * A down clears the gate: nothing is held across a knockdown and its get-up.
-- * The server's copy of a character trails the client's screen by the lag, so a swing can
--   arrive before the copy has bounced. Judge then counts the landing the copy is about to show
--   when the copy's fall is within reach of its floor inside the lag. That landing is taken
--   "ahead" of the samples, and the copy's own turn later is not a second one.

export type State = {
	used: boolean, -- an airborne swing was taken since the last landing
	airborne: boolean, -- the last sample's verdict
	falling: boolean, -- in a fall that has neither landed nor turned
	lowest: number, -- the lowest excess over the grounded band seen in that fall (studs)
	fallSpeed: number, -- the fastest fall seen in it (studs/s, positive down)
	lastY: number?, -- the last sample's root Y
	ahead: boolean, -- a claim already took this fall's landing
}

local SwingGate = {}

-- How far over its standing height a root (or a swing's origin) may be and still count as
-- grounded. WeaponService's air tracking reads the same number.
SwingGate.AIR_MARGIN_STUDS = 0.75
-- A fall that turns within this long of its floor (at its fastest speed) is a landing. 0.1 s
-- covers a contact stepped over by samples at 10 Hz or faster, which is slower than any physics
-- replication; a double jump counts only when it is that close to touching down anyway.
SwingGate.TURN_WINDOW_SECONDS = 0.1
-- A sample's direction is its height change since the last one: the server's copy is
-- interpolated, and its replicated speed can still point down while the copy already rises off
-- the floor. With no height change, a vertical speed beyond this (studs/s) gives the direction.
SwingGate.STILL_SPEED = 1
-- The probe pattern, in half-sizes of the root along its right and back axes: the centre first.
SwingGate.FOOTPRINT = { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
SwingGate.PROBE_POINTS = 5

local DIRECTION_MIN = 1e-6

function SwingGate.New(): State
	return {
		used = false,
		airborne = false,
		falling = false,
		lowest = math.huge,
		fallSpeed = 0,
		lastY = nil,
		ahead = false,
	}
end

-- The flat (x, z) of footprint point `index` (1..PROBE_POINTS) under a root at (x, z) whose
-- right vector is (rightX, rightZ) on the flat, half-sizes halfX (right) and halfZ (back). A
-- root tipped so far its right vector has no flat part reads as facing +X.
function SwingGate.ProbePoint(
	index: number,
	x: number,
	z: number,
	rightX: number,
	rightZ: number,
	halfX: number,
	halfZ: number
): (number, number)
	local corner = SwingGate.FOOTPRINT[index]
	local length = math.sqrt(rightX * rightX + rightZ * rightZ)
	local rx = if length > DIRECTION_MIN then rightX / length else 1
	local rz = if length > DIRECTION_MIN then rightZ / length else 0
	-- The back axis is the right axis turned a quarter about Y (a CFrame's -LookVector).
	local bx, bz = -rz, rx
	local along = corner[1] * halfX
	local across = corner[2] * halfZ
	return x + rx * along + bx * across, z + rz * along + bz * across
end

-- Folds one probe's floor into the footprint's: the highest floor found wins.
function SwingGate.Higher(floorY: number?, hitY: number?): number?
	if floorY == nil then
		return hitY
	end
	if hitY == nil then
		return floorY
	end
	return math.max(floorY, hitY)
end

-- height = the root's (or origin's) Y over the footprint's floor (nil = no floor: airborne).
function SwingGate.IsAir(height: number?, standOffset: number): boolean
	if height == nil then
		return true
	end
	return height > standOffset + SwingGate.AIR_MARGIN_STUDS
end

-- How far over the grounded band a point is (math.huge with no floor).
local function excessOf(y: number, floorY: number?, standOffset: number): number
	if floorY == nil then
		return math.huge
	end
	return y - floorY - standOffset - SwingGate.AIR_MARGIN_STUDS
end

-- A landing clears `used`, unless a claim already took this fall's landing.
local function land(state: State): ()
	if state.ahead then
		state.ahead = false
	else
		state.used = false
	end
end

local function endFall(state: State): ()
	state.falling = false
	state.ahead = false
	state.lowest = math.huge
	state.fallSpeed = 0
end

-- One sample of the root, every frame (the server's Heartbeat, the client's own). y = the root's
-- Y, vy = its vertical velocity, floorY = the footprint's highest floor (nil = none), down =
-- the player is down. True when this sample counts a landing.
function SwingGate.Observe(
	state: State,
	y: number,
	vy: number,
	floorY: number?,
	standOffset: number,
	down: boolean
): boolean
	if down then
		state.used = false
		state.airborne = false
		state.lastY = y
		endFall(state)
		return false
	end
	local height = if floorY ~= nil then y - floorY else nil
	local airborne = SwingGate.IsAir(height, standOffset)
	local excess = excessOf(y, floorY, standOffset)
	local step = if state.lastY ~= nil then y - state.lastY else 0
	local sinking = step < 0 or (step == 0 and vy < -SwingGate.STILL_SPEED)
	local rising = step > 0 or (step == 0 and vy > SwingGate.STILL_SPEED)
	local landed = false
	if not airborne then
		if state.airborne or state.falling then
			landed = true
			land(state)
		end
		endFall(state)
	elseif sinking then
		if state.falling then
			state.lowest = math.min(state.lowest, excess)
			state.fallSpeed = math.max(state.fallSpeed, -vy)
		else
			state.falling = true
			state.lowest = excess
			state.fallSpeed = math.max(-vy, 0)
		end
	elseif rising and state.falling then
		-- The turn: a landing when the floor was within the fall's reach of the lowest sample.
		local reach = state.fallSpeed * SwingGate.TURN_WINDOW_SECONDS
		if math.min(state.lowest, excess) <= reach then
			landed = true
			land(state)
		end
		endFall(state)
	elseif state.falling then
		state.lowest = math.min(state.lowest, excess)
	end
	state.airborne = airborne
	state.lastY = y
	return landed
end

-- (allowed, airborne) for a melee swing from a point at height y over floorY (the footprint
-- probe at that point). lagSeconds = how far the samples trail the swing (the server: the
-- commit lag; the client: 0). A swing that is not allowed is the second airborne one of a jump.
function SwingGate.Judge(
	state: State,
	y: number,
	floorY: number?,
	standOffset: number,
	lagSeconds: number
): (boolean, boolean)
	local height = if floorY ~= nil then y - floorY else nil
	local airborne = SwingGate.IsAir(height, standOffset)
	if airborne and state.used and state.falling and not state.ahead then
		-- The samples are still falling, close enough to their floor to have touched it inside
		-- the lag: the swing may come from the next hop. A claim cannot tell a client that has
		-- bounced from one about to touch down, so both pass; an honest client's own gate
		-- refuses the second, so only the bounce is ever sent.
		-- A NaN lag fails every comparison, math.max included.
		local lag = if lagSeconds == lagSeconds then math.max(lagSeconds, 0) else 0
		if state.lowest <= state.fallSpeed * (SwingGate.TURN_WINDOW_SECONDS + lag) then
			state.used = false
			state.ahead = true
		end
	end
	return SwingGate.Allows(state, airborne), airborne
end

function SwingGate.Allows(state: State, airborne: boolean): boolean
	return not (airborne and state.used)
end

-- A grounded swing clears the gate; an airborne one spends it until the next landing (a double
-- jump is not a landing).
function SwingGate.Took(state: State, airborne: boolean)
	state.used = airborne
end

-- A fresh start (a new character): nothing spent, no fall in progress.
function SwingGate.Landed(state: State)
	state.used = false
	state.airborne = false
	state.lastY = nil
	endFall(state)
end

return SwingGate
