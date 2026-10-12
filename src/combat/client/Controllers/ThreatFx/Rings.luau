--!strict
-- ThreatFx child: the two circles a boss draws round itself, both from the crowd snapshot
-- alone, with no event (docs/INTERFACES.md "P4 contracts" -> "Stop 2 — the Colossus", `ring`
-- and `summon`). CrowdRenderer runs each attack's clock on server time; every frame ThreatFx
-- feeds this module the bodies that are winding one up.
--
-- The slam (`ring`). Through the windup the whole circle it will reach lies on the floor, as a
-- lob's circle does: a faint disc inside a bright rim, and a brighter disc that grows to meet
-- the rim exactly at the impact. The player reads how far to go. At the impact the growing
-- disc goes and a front leaves the body's feet: a low bright crest `width` thick, centred on
-- a circle that grows at speed x (server time now - impact) and never reaching past `radius`,
-- gone when that circle gets there. Behind the crest the floor is safe again, so nothing is
-- drawn there. It is low and flat on purpose: this is the attack that is jumped, and the
-- marksman's standing sheet is the one that is not.
--
-- From the impact the ring is its own thing. Its body may recover or wind up the next attack
-- of a chain; the front runs on regardless, as the server's does, and needs no more feeding.
-- Only its body's end ends it: the server drops a dead boss's rings, so a front whose body is
-- no longer alive goes at once. A windup that stops being fed before its impact was cancelled
-- and goes at once too.
--
-- The call (`summon`): only a rim, where the summoned will rise, pulsing, in a colour that is
-- not the danger's red. It hurts nobody and is gone at the impact; the bodies that come up
-- through the floor take over from there (CrowdRenderer).
--
-- The rim, the discs and the front are information and are never thinned; a low-end device
-- gets a coarser polygon.

local Theme = require(script.Parent.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Pool = require(script.Parent:WaitForChild("Pool"))

-- origin = the body's floor point. launchAt = the server time its front left the body, 0
-- while it is still a windup. laid = the rim and the discs stand at `origin` for `radius`.
type Ring = {
	id: number,
	harmless: boolean,
	seen: boolean,
	laid: boolean,
	origin: Vector3,
	radius: number,
	width: number,
	speed: number,
	launchAt: number,
	base: Part?,
	fill: Part?,
	rim: { Part },
	front: { Part },
	fillShown: number,
}

local TAU = 2 * math.pi
local UP = Vector3.yAxis
-- A Cylinder's axis is its X: turned a quarter about Z it lies flat as a disc.
local FLAT = CFrame.Angles(0, 0, math.pi / 2)
-- A blow first seen under way within this long of a front already running from the same body
-- is that front, not a second one (a boss's slam has seconds of cooldown).
local SAME_RING_SECONDS = 0.5
-- More fronts than this at once are not drawn: one boss throws one at a time.
local MAX_RUNNING = 8

local winding: { [number]: Ring } = {}
local running: { Ring } = {}
-- Unit vectors of each segment's middle, outward and along the rim, for this device's count.
local radial: { Vector3 } = {}
local tangent: { Vector3 } = {}

local Rings = {}

local function segments(): number
	local count = #radial
	if count > 0 then
		return count
	end
	count = if Theme.lowEndDevice
		then Theme.COMBAT_RANGE_RING_LOW_END_SEGMENTS
		else Theme.COMBAT_RANGE_RING_SEGMENTS
	count = math.max(math.floor(count), 3)
	local span = TAU / count
	for index = 1, count do
		local angle = span * (index - 0.5)
		radial[index] = Vector3.new(math.cos(angle), 0, math.sin(angle))
		tangent[index] = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	end
	return count
end

local function release(ring: Ring): ()
	local base = ring.base
	if base ~= nil then
		Pool.Give(base)
	end
	local fill = ring.fill
	if fill ~= nil then
		Pool.Give(fill)
	end
	for _, part in ring.rim do
		Pool.Give(part)
	end
	for _, part in ring.front do
		Pool.Give(part)
	end
	ring.base = nil
	ring.fill = nil
	table.clear(ring.rim)
	table.clear(ring.front)
end

local function open(id: number, harmless: boolean): Ring
	local color = if harmless then Theme.COMBAT_RANGE_CALL_COLOR else Theme.COMBAT_RANGE_TELL_COLOR
	local rim: { Part } = {}
	for _ = 1, segments() do
		table.insert(rim, Pool.Take(Enum.PartType.Block, color))
	end
	local ring: Ring = {
		id = id,
		harmless = harmless,
		seen = true,
		laid = false,
		origin = Vector3.zero,
		radius = 0,
		width = 0,
		speed = 0,
		launchAt = 0,
		base = nil,
		fill = nil,
		rim = rim,
		front = {},
		fillShown = -1,
	}
	if not harmless then
		ring.base = Pool.Take(Enum.PartType.Cylinder, color)
		ring.fill = Pool.Take(Enum.PartType.Cylinder, color)
	end
	return ring
end

-- Puts the rim and the discs down for the ring's origin and radius. They do not move again
-- unless the body is moved under its own windup.
local function lay(ring: Ring): ()
	ring.laid = true
	local origin = ring.origin
	local radius = ring.radius
	local count = #ring.rim
	local span = TAU / count
	local width = Theme.COMBAT_RANGE_TELL_EDGE_WIDTH
	-- Half a width longer than the chord, so neighbouring bars close the rim's corners.
	local size = Vector3.new(
		width,
		Theme.COMBAT_RANGE_TELL_EDGE_HEIGHT,
		2 * radius * math.sin(span / 2) + width / 2
	)
	local reach = radius * math.cos(span / 2)
	-- The disc, the growing disc and the rim each show a top face at a height of their own
	-- (Pool.MarkTop: every flat mark that can lie over another has one), the three slots after
	-- the lob circles'. Only the top faces are told apart; nothing is stacked, so the ring
	-- stays close to the floor.
	local slot = 2 * math.max(math.floor(Theme.COMBAT_RANGE_AREA_LEVELS), 1)
	local half = Theme.COMBAT_RANGE_TELL_THICKNESS / 2
	local edge = origin + UP * (Pool.MarkTop(slot + 3) - Theme.COMBAT_RANGE_TELL_EDGE_HEIGHT / 2)
	for index, part in ring.rim do
		local middle = edge + radial[index] * reach
		part.Size = size
		Pool.Place(part, CFrame.lookAt(middle, middle + tangent[index], UP))
	end
	local base = ring.base
	if base ~= nil then
		base.Size = Vector3.new(Theme.COMBAT_RANGE_TELL_THICKNESS, radius * 2, radius * 2)
		Pool.Place(base, CFrame.new(origin + UP * (Pool.MarkTop(slot + 1) - half)) * FLAT)
	end
	local fill = ring.fill
	if fill ~= nil then
		Pool.Place(fill, CFrame.new(origin + UP * (Pool.MarkTop(slot + 2) - half)) * FLAT)
	end
end

local function isRunning(id: number, at: number): boolean
	for _, ring in running do
		if ring.id == id and math.abs(ring.launchAt - at) < SAME_RING_SECONDS then
			return true
		end
	end
	return false
end

-- The windup is over and the front leaves: the growing disc goes, the crest's pieces come.
local function launch(ring: Ring, at: number): ()
	ring.launchAt = at
	local fill = ring.fill
	if fill ~= nil then
		Pool.Show(fill, 1)
	end
	local base = ring.base
	if base ~= nil then
		Pool.Show(base, Theme.COMBAT_RANGE_RING_BASE_RUNNING)
	end
	for _ = 1, #ring.rim do
		table.insert(ring.front, Pool.Take(Enum.PartType.Block, Theme.COMBAT_RANGE_TELL_COLOR))
	end
	table.insert(running, ring)
end

-- One body's slam (or, `harmless`, its call) this frame. `striking` = its blow is under way;
-- phaseAt = the server time that phase began; impactAt = the end of its windup; origin = the
-- body's floor point; radius = how far the ring reaches; width = the front's thickness;
-- speed = the front's, studs per second.
function Rings.Feed(
	id: number,
	harmless: boolean,
	striking: boolean,
	phaseAt: number,
	impactAt: number,
	origin: Vector3,
	radius: number,
	width: number,
	speed: number,
	serverNow: number
): ()
	if radius <= 0 then
		return
	end
	local leaving = striking or serverNow >= impactAt
	local leftAt = if striking then phaseAt else impactAt
	local known: Ring? = winding[id]
	if known == nil and leaving then
		-- Nothing was being drawn for it. A call is over at its impact. A slam's front may
		-- already be running from an earlier frame's feed; only a blow never seen winding up
		-- (this client joined in the middle of it) still needs one.
		if harmless or speed <= 0 or #running >= MAX_RUNNING or isRunning(id, leftAt) then
			return
		end
	end
	local ring: Ring = known or open(id, harmless)
	ring.seen = true
	if not ring.laid or ring.radius ~= radius or (origin - ring.origin).Magnitude > 0.05 then
		ring.origin = origin
		ring.radius = radius
		lay(ring)
	end
	ring.width = math.max(width, 0.1)
	ring.speed = speed
	if leaving then
		winding[id] = nil
		if harmless or speed <= 0 or #running >= MAX_RUNNING then
			release(ring)
		else
			launch(ring, leftAt)
		end
		return
	end
	winding[id] = ring

	if harmless then
		local wave = 0.5 + 0.5 * math.sin(serverNow * TAU * Theme.COMBAT_RANGE_CALL_PULSE_HZ)
		local least = Theme.COMBAT_RANGE_CALL_TRANSPARENCY
		local shown = least + (1 - least) * Theme.COMBAT_RANGE_CALL_PULSE * wave
		for _, part in ring.rim do
			Pool.Show(part, shown)
		end
		return
	end
	local windup = impactAt - phaseAt
	local u = if windup > 0 then math.clamp((serverNow - phaseAt) / windup, 0, 1) else 1
	local least = Theme.COMBAT_RANGE_TELL_MIN_FILL
	local reach = radius * (least + (1 - least) * u)
	local fill = ring.fill
	if fill ~= nil then
		if math.abs(reach - ring.fillShown) > 0.01 then
			ring.fillShown = reach
			fill.Size = Vector3.new(Theme.COMBAT_RANGE_TELL_THICKNESS, reach * 2, reach * 2)
		end
		Pool.Show(fill, Theme.COMBAT_RANGE_TELL_FILL_TRANSPARENCY)
	end
	local base = ring.base
	if base ~= nil then
		Pool.Show(base, Theme.COMBAT_RANGE_AREA_BASE_TRANSPARENCY)
	end
	for _, part in ring.rim do
		Pool.Show(part, Theme.COMBAT_RANGE_TELL_EDGE_TRANSPARENCY)
	end
end

-- After the frame's feeds: a windup nobody fed was cancelled and goes; every front that has
-- left its body is moved to where the server clock has it, and goes when it reaches the rim
-- or when `isAlive` says its body is gone.
function Rings.Step(serverNow: number, isAlive: (id: number) -> boolean): ()
	for id, ring in winding do
		if ring.seen then
			ring.seen = false
		else
			winding[id] = nil
			release(ring)
		end
	end
	local height = Theme.COMBAT_RANGE_RING_FRONT_HEIGHT
	for index = #running, 1, -1 do
		local ring = running[index]
		local reach = ring.speed * math.max(serverNow - ring.launchAt, 0)
		if reach >= ring.radius or not isAlive(ring.id) then
			release(ring)
			local last = #running
			running[index] = running[last]
			running[last] = nil
			continue
		end
		-- The band the server tests: half its width either side of the growing circle, and
		-- nobody beyond the rim. Each piece's outer face touches the band's outer circle at
		-- its middle and meets its neighbours' at the corners, so the drawn front is never
		-- inside the real one.
		local outer = math.min(reach + ring.width / 2, ring.radius)
		local inner = math.max(reach - ring.width / 2, 0)
		local thick = math.max(outer - inner, 0.05)
		local middle = (outer + inner) / 2
		local count = #ring.front
		local size = Vector3.new(thick, height, 2 * outer * math.tan(math.pi / count) + 0.05)
		local lifted = ring.origin + UP * (height / 2)
		for slot, part in ring.front do
			local centre = lifted + radial[slot] * middle
			part.Size = size
			Pool.Place(part, CFrame.lookAt(centre, centre + tangent[slot], UP))
			Pool.Show(part, Theme.COMBAT_RANGE_RING_FRONT_TRANSPARENCY)
		end
	end
end

-- Every ring goes (a dummy set was loaded: its boss and whatever it had thrown are gone).
function Rings.Clear(): ()
	for id, ring in winding do
		winding[id] = nil
		release(ring)
	end
	for index = #running, 1, -1 do
		release(running[index])
		running[index] = nil
	end
end

return Rings
