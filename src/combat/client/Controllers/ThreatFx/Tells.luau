--!strict
-- ThreatFx child: the two tells that are drawn from the crowd snapshot alone, with no event
-- (docs/INTERFACES.md "P4 contracts" -> "Wave 2", `lane` and `line`). CrowdRenderer runs each
-- attack's clock on server time; every frame ThreatFx feeds this module the bodies that are
-- winding one up or throwing it, and a tell that is no longer fed is gone the same frame.
--
-- Lane (the brute's charge): a flat mark on the floor along the facing locked at the windup's
-- start. The server hits whoever comes within half the lane's `width` of the charging body's
-- centre, so the real shape is a disc of that radius swept along the run: `range` long between
-- the two centres, with a round end beyond each. It is drawn as exactly that, two discs and
-- the strip between them, so the mark is never smaller than what hits and no larger. Both
-- discs and the strip's sides show the whole reach from the first frame, and the fill grows
-- from the brute to the far disc exactly at the impact. During the charge the near disc rides
-- with the brute on the server clock and the fill is the lane still AHEAD of it, so what
-- stays lit is what can still hit.
--
-- Line (the marksman's shot): a vertical plane, which a jump does not clear, so it is drawn
-- standing up. Until the lock (lockSeconds before the impact) the aim still follows its
-- target: only a thin strip on the floor and a thin beam at chest height, turning with it.
-- At the lock the strip widens to the shot's true width and a sheet as thick as that width
-- rises over it in three bands, each fainter than the one below and the top one well above a
-- double jump: a wall, fading into the sky. At the impact all of it flashes as the shot and
-- fades. The line is drawn to its full range: the client cannot know where a wall cuts it.
--
-- Both are information: nothing here is thinned on any device.

local Theme = require(script.Parent.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Pool = require(script.Parent:WaitForChild("Pool"))

-- `mode` (line): 0 = following, 1 = locked, 2 = the shot; -1 = not laid yet. `range`, `width`
-- and `reach` are what the parts were last sized for.
type Tell = {
	shape: string,
	parts: { Part },
	seen: boolean,
	yaw: number,
	mode: number,
	range: number,
	width: number,
	reach: number,
}

local TAU = 2 * math.pi
local UP = Vector3.yAxis
-- A Cylinder's axis is its X: turned a quarter about Z it lies flat as a disc.
local FLAT = CFrame.Angles(0, 0, math.pi / 2)
-- Lane: fill, two sides, far disc, near disc. Line: floor strip, beam, three bands of sheet.
local PARTS = 5
-- The first of a lane's two discs: its parts from here on are Cylinders.
local LANE_DISCS = 4

local tells: { [number]: Tell } = {}

local Tells = {}

local function lookOf(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function along(part: Part, centre: Vector3, forward: Vector3): ()
	Pool.Place(part, CFrame.lookAt(centre, centre + forward, UP))
end

local function feedLane(
	tell: Tell,
	striking: boolean,
	phaseAt: number,
	impactAt: number,
	origin: Vector3,
	yaw: number,
	range: number,
	width: number,
	strikeSeconds: number,
	serverNow: number
): ()
	local parts = tell.parts
	if striking and serverNow - phaseAt >= strikeSeconds then
		-- The run is over. Where the arena's edge cut it short the attack state still runs on
		-- for the full range's time, but nothing here can hit any more: the mark goes dark.
		for _, part in parts do
			Pool.Show(part, 1)
		end
		return
	end
	local thickness = Theme.COMBAT_RANGE_TELL_THICKNESS
	if tell.range ~= range or tell.width ~= width then
		tell.range = range
		tell.width = width
		local side = Vector3.new(
			Theme.COMBAT_RANGE_TELL_EDGE_WIDTH,
			Theme.COMBAT_RANGE_TELL_EDGE_HEIGHT,
			range
		)
		-- The body's own hit disc, at the two ends of its run.
		local disc = Vector3.new(thickness, width, width)
		parts[2].Size = side
		parts[3].Size = side
		parts[4].Size = disc
		parts[5].Size = disc
	end
	local forward = lookOf(yaw)
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local floor = origin + UP * Theme.COMBAT_RANGE_TELL_LIFT
	local middle = floor + forward * (range / 2)
	along(parts[2], middle - right * (width / 2), forward)
	along(parts[3], middle + right * (width / 2), forward)

	local from = 0
	local to = range
	if striking then
		-- The charge covers the lane in strikeSeconds: what is behind the brute goes dark.
		from = range
			* (
				if strikeSeconds > 0
					then math.clamp((serverNow - phaseAt) / strikeSeconds, 0, 1)
					else 1
			)
	else
		local windup = impactAt - phaseAt
		local u = if windup > 0 then math.clamp((serverNow - phaseAt) / windup, 0, 1) else 1
		local least = Theme.COMBAT_RANGE_TELL_MIN_FILL
		to = range * (least + (1 - least) * u)
	end
	local reach = math.max(to - from, 0.05)
	if math.abs(reach - tell.reach) > 0.01 then
		tell.reach = reach
		parts[1].Size = Vector3.new(width, thickness, reach)
	end
	along(parts[1], floor + forward * ((from + to) / 2), forward)
	-- A hair above the strip, so where a disc lies over it the two never fight for the same
	-- pixels. The far disc marks where the run ends; the near one is where the body is now.
	local raised = floor + UP * thickness
	Pool.Place(parts[4], CFrame.new(raised + forward * range) * FLAT)
	Pool.Place(parts[5], CFrame.new(raised + forward * from) * FLAT)
	local lit = if striking
		then Theme.COMBAT_RANGE_TELL_STRIKE_TRANSPARENCY
		else Theme.COMBAT_RANGE_TELL_FILL_TRANSPARENCY
	Pool.Show(parts[1], lit)
	Pool.Show(parts[2], Theme.COMBAT_RANGE_TELL_EDGE_TRANSPARENCY)
	Pool.Show(parts[3], Theme.COMBAT_RANGE_TELL_EDGE_TRANSPARENCY)
	Pool.Show(parts[4], lit)
	Pool.Show(parts[5], lit)
end

local function feedLine(
	tell: Tell,
	striking: boolean,
	phaseAt: number,
	impactAt: number,
	origin: Vector3,
	yaw: number,
	range: number,
	width: number,
	lockSeconds: number,
	strikeSeconds: number,
	serverNow: number,
	deltaTime: number
): ()
	local parts = tell.parts
	local mode = if striking then 2 elseif serverNow >= impactAt - lockSeconds then 1 else 0
	if mode > 0 or tell.mode < 0 then
		-- Locked, the aim is the wire's own yaw with nothing laid over it.
		tell.yaw = yaw
	else
		-- Following: the wire's yaw comes in steps of 1/256 turn at snapshot rate, which at
		-- this length would tick along the floor; eased, it sweeps.
		local turn = (yaw - tell.yaw + math.pi) % TAU - math.pi
		tell.yaw += turn * (1 - math.exp(-Theme.COMBAT_RANGE_TELL_LINE_FOLLOW_RATE * deltaTime))
	end
	local low = Theme.COMBAT_RANGE_TELL_LINE_LOW_TOP
	local mid = Theme.COMBAT_RANGE_TELL_LINE_MID_TOP
	local high = Theme.COMBAT_RANGE_TELL_LINE_HIGH_TOP
	if mode ~= tell.mode or tell.range ~= range or tell.width ~= width then
		tell.mode = mode
		tell.range = range
		tell.width = width
		local beam = if mode == 0
			then Theme.COMBAT_RANGE_TELL_LINE_BEAM_THIN
			elseif mode == 1 then Theme.COMBAT_RANGE_TELL_LINE_BEAM_LOCKED
			else Theme.COMBAT_RANGE_TELL_LINE_BEAM_SHOT
		parts[1].Size = Vector3.new(
			if mode == 0 then Theme.COMBAT_RANGE_TELL_LINE_THIN_WIDTH else width,
			Theme.COMBAT_RANGE_TELL_THICKNESS,
			range
		)
		parts[2].Size = Vector3.new(beam, beam, range)
		parts[3].Size = Vector3.new(width, low, range)
		parts[4].Size = Vector3.new(width, mid - low, range)
		parts[5].Size = Vector3.new(width, high - mid, range)
	end
	local forward = lookOf(tell.yaw)
	local middle = origin + forward * (range / 2)
	along(parts[1], middle + UP * Theme.COMBAT_RANGE_TELL_LIFT, forward)
	along(parts[2], middle + UP * Theme.COMBAT_RANGE_TELL_LINE_BEAM_HEIGHT, forward)
	along(parts[3], middle + UP * (low / 2), forward)
	along(parts[4], middle + UP * ((low + mid) / 2), forward)
	along(parts[5], middle + UP * ((mid + high) / 2), forward)

	if mode == 0 then
		Pool.Show(parts[1], Theme.COMBAT_RANGE_TELL_LINE_THIN_TRANSPARENCY)
		Pool.Show(parts[2], Theme.COMBAT_RANGE_TELL_LINE_THIN_TRANSPARENCY)
		Pool.Show(parts[3], 1)
		Pool.Show(parts[4], 1)
		Pool.Show(parts[5], 1)
		return
	end
	-- Locked: solid. The shot: the same wall at its brightest, fading out over the strike.
	local seen = 1
	local lift = 0
	if mode == 2 then
		seen = if strikeSeconds > 0
			then 1 - math.clamp((serverNow - phaseAt) / strikeSeconds, 0, 1)
			else 0
		lift = Theme.COMBAT_RANGE_TELL_LINE_SHOT_LIFT
	end
	Pool.Show(parts[1], 1 - (1 - Theme.COMBAT_RANGE_TELL_EDGE_TRANSPARENCY) * seen)
	Pool.Show(parts[2], 1 - seen)
	Pool.Show(parts[3], 1 - (1 - Theme.COMBAT_RANGE_TELL_LINE_LOW_TRANSPARENCY + lift) * seen)
	Pool.Show(parts[4], 1 - (1 - Theme.COMBAT_RANGE_TELL_LINE_MID_TRANSPARENCY + lift) * seen)
	Pool.Show(parts[5], 1 - (1 - Theme.COMBAT_RANGE_TELL_LINE_HIGH_TRANSPARENCY + lift) * seen)
end

-- One body's lane or line this frame. `striking` = its blow is under way (the charge, the
-- shot); phaseAt = the server time that phase began; impactAt = the end of its windup;
-- origin = the body's floor point; yaw = its facing as the wire last gave it.
function Tells.Feed(
	id: number,
	shape: string,
	striking: boolean,
	phaseAt: number,
	impactAt: number,
	origin: Vector3,
	yaw: number,
	range: number,
	width: number,
	lockSeconds: number,
	strikeSeconds: number,
	serverNow: number,
	deltaTime: number
): ()
	if range <= 0 or width <= 0 or (shape ~= "lane" and shape ~= "line") then
		return
	end
	local tell: Tell? = tells[id]
	-- The same body under another attack: its old tell's parts are not this shape's.
	if tell ~= nil and tell.shape ~= shape then
		for _, part in tell.parts do
			Pool.Give(part)
		end
		tell = nil
	end
	local current: Tell
	if tell ~= nil then
		current = tell
	else
		local parts: { Part } = {}
		for index = 1, PARTS do
			local round = shape == "lane" and index >= LANE_DISCS
			table.insert(
				parts,
				Pool.Take(
					if round then Enum.PartType.Cylinder else Enum.PartType.Block,
					Theme.COMBAT_RANGE_TELL_COLOR
				)
			)
		end
		current = {
			shape = shape,
			parts = parts,
			seen = true,
			yaw = yaw,
			mode = -1,
			range = 0,
			width = 0,
			reach = 0,
		}
		tells[id] = current
	end
	current.seen = true
	if shape == "lane" then
		feedLane(
			current,
			striking,
			phaseAt,
			impactAt,
			origin,
			yaw,
			range,
			width,
			strikeSeconds,
			serverNow
		)
	else
		feedLine(
			current,
			striking,
			phaseAt,
			impactAt,
			origin,
			yaw,
			range,
			width,
			lockSeconds,
			strikeSeconds,
			serverNow,
			deltaTime
		)
	end
end

-- After the frame's feeds: a tell nobody fed belongs to an attack that is over or was
-- cancelled, and goes at once.
function Tells.Sweep(): ()
	for id, tell in tells do
		if tell.seen then
			tell.seen = false
		else
			for _, part in tell.parts do
				Pool.Give(part)
			end
			tells[id] = nil
		end
	end
end

function Tells.Clear(): ()
	for id, tell in tells do
		for _, part in tell.parts do
			Pool.Give(part)
		end
		tells[id] = nil
	end
end

return Tells
