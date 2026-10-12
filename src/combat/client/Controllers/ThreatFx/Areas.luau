--!strict
-- ThreatFx child: ground circles that land at a set time (docs/INTERFACES.md "P4 contracts"
-- -> "Wave 2", `lob`; boss rings at Stop 2 arrive as the same `area` effect). The server sends
-- the circle once, with the server times it opens and lands at; every client draws it against
-- that clock.
--
-- The circle's whole reach shows from its first frame (a faint disc inside a bright rim), and
-- a brighter disc grows inside it to meet the rim exactly at the landing, as the elite's wedge
-- fills to its outline. With `from`, the lobbed shot itself arcs from the lobber to the centre
-- and arrives at the same moment. On landing the disc flashes at its brightest and fades. It is
-- a flat mark, like every ground shape a jump clears; only the line stands up.
--
-- The mark lies wherever the server puts it. A lob's floor is the surface under its target at
-- the throw, so `center` carries a real height: a player on a block gets the circle on the
-- block's top. Both discs, the rim, the arc's landing point and the landing flash are all at
-- that point as sent; nothing here is put on the arena floor.
--
-- The rim, both discs and the shot are information. A low-end device only gets a coarser rim.

local Theme = require(script.Parent.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Area = {
	id: number,
	-- The crowd id of the body that threw it (nil = not said): a boss's death takes its own
	-- circles with it (Drop).
	owner: number?,
	centre: Vector3,
	radius: number,
	startsAt: number,
	endsAt: number,
	from: Vector3?,
	apex: number,
	base: Part,
	fill: Part,
	rim: { Part },
	shot: Part?,
	fillShown: number,
}

local TAU = 2 * math.pi
local UP = Vector3.yAxis
-- A Cylinder's axis is its X: turned a quarter about Z it lies flat as a disc.
local FLAT = CFrame.Angles(0, 0, math.pi / 2)
-- The same guard as for shots: far above anything the server sends at once.
local MAX_DRAWN = 32
-- Ids that run on from one another (a barrage's) take levels this many apart. It shares no
-- factor with Theme.COMBAT_RANGE_AREA_LEVELS, so as many circles as there are levels, thrown
-- together, each get one of their own.
local LEVEL_STRIDE = 7

local areas: { Area } = {}

local Areas = {}

local function release(index: number): ()
	local area = areas[index]
	Pool.Give(area.base)
	Pool.Give(area.fill)
	for _, part in area.rim do
		Pool.Give(part)
	end
	local shot = area.shot
	if shot ~= nil then
		Pool.Give(shot)
	end
	local last = #areas
	areas[index] = areas[last]
	areas[last] = nil
end

local function disc(part: Part, radius: number): ()
	part.Size = Vector3.new(Theme.COMBAT_RANGE_TELL_THICKNESS, radius * 2, radius * 2)
end

-- `area`: a circle of `radius` round `centre` (a point on the surface it lands on, at that
-- surface's own height) that opens at `startsAt` and lands at `endsAt`, both server time.
-- `from` = where the lobbed shot left, when there is one; `enemyId` = the crowd id of the
-- body that threw it, when the effect says.
function Areas.Open(
	id: number,
	centre: Vector3,
	radius: number,
	startsAt: number,
	endsAt: number,
	from: Vector3?,
	enemyId: number?
): ()
	for index, area in areas do
		if area.id == id then
			release(index)
			break
		end
	end
	if #areas >= MAX_DRAWN or radius <= 0 then
		return
	end
	local color = Theme.COMBAT_RANGE_TELL_COLOR
	-- Circles overlap (a barrage is several at once, thrown close together), and two flat
	-- discs whose top faces share a height would fight for the same pixels. Each circle takes
	-- a level of its own by its id (a barrage's ids run on from one another), and only the top
	-- faces are told apart (Pool.MarkTop): the faint discs' on the first slots, the growing
	-- discs' on the next, every rim's on the one after. Nothing is stacked, so the whole mark
	-- stays close to the surface it lies on.
	local levels = math.max(math.floor(Theme.COMBAT_RANGE_AREA_LEVELS), 1)
	local level = (id * LEVEL_STRIDE) % levels
	local half = Theme.COMBAT_RANGE_TELL_THICKNESS / 2
	local floor = centre + UP * (Pool.MarkTop(level) - half)
	local base = Pool.Take(Enum.PartType.Cylinder, color)
	disc(base, radius)
	Pool.Place(base, CFrame.new(floor) * FLAT)
	local fill = Pool.Take(Enum.PartType.Cylinder, color)
	Pool.Place(fill, CFrame.new(centre + UP * (Pool.MarkTop(levels + level) - half)) * FLAT)
	local edge = centre + UP * (Pool.MarkTop(2 * levels) - Theme.COMBAT_RANGE_TELL_EDGE_HEIGHT / 2)

	local segments = if Theme.lowEndDevice
		then Theme.COMBAT_RANGE_AREA_LOW_END_SEGMENTS
		else Theme.COMBAT_RANGE_AREA_SEGMENTS
	local width = Theme.COMBAT_RANGE_TELL_EDGE_WIDTH
	local span = TAU / segments
	-- Half a width longer than the chord, so neighbouring bars close the rim's corners.
	local size = Vector3.new(
		width,
		Theme.COMBAT_RANGE_TELL_EDGE_HEIGHT,
		2 * radius * math.sin(span / 2) + width / 2
	)
	local rim: { Part } = {}
	for index = 1, segments do
		local a = span * (index - 1)
		local b = a + span
		local pa = edge + Vector3.new(math.cos(a), 0, math.sin(a)) * radius
		local pb = edge + Vector3.new(math.cos(b), 0, math.sin(b)) * radius
		local part = Pool.Take(Enum.PartType.Block, color)
		part.Size = size
		Pool.Place(part, CFrame.lookAt((pa + pb) / 2, pb, UP))
		table.insert(rim, part)
	end

	local shot: Part? = nil
	local apex = 0
	if from ~= nil then
		local ball = Pool.Take(Enum.PartType.Ball, color)
		ball.Size = Vector3.one * Theme.COMBAT_RANGE_LOB_BALL_SIZE
		shot = ball
		local flat = Vector3.new(centre.X - from.X, 0, centre.Z - from.Z).Magnitude
		apex = math.clamp(
			flat * Theme.COMBAT_RANGE_LOB_APEX_SHARE,
			Theme.COMBAT_RANGE_LOB_APEX_MIN,
			Theme.COMBAT_RANGE_LOB_APEX_MAX
		)
	end
	table.insert(areas, {
		id = id,
		owner = enemyId,
		centre = floor,
		radius = radius,
		startsAt = startsAt,
		endsAt = math.max(endsAt, startsAt),
		from = from,
		apex = apex,
		base = base,
		fill = fill,
		rim = rim,
		shot = shot,
		fillShown = -1,
	})
end

function Areas.Step(serverNow: number): ()
	local landSeconds = Theme.COMBAT_RANGE_AREA_LAND_SECONDS
	for index = #areas, 1, -1 do
		local area = areas[index]
		local sinceLanding = serverNow - area.endsAt
		if sinceLanding >= landSeconds then
			release(index)
			continue
		end
		local shot = area.shot
		if sinceLanding >= 0 then
			-- Landed: the whole circle at its brightest, fading out.
			local left = 1 - sinceLanding / landSeconds
			if area.fillShown ~= area.radius then
				area.fillShown = area.radius
				disc(area.fill, area.radius)
			end
			Pool.Show(area.fill, 1 - (1 - Theme.COMBAT_RANGE_TELL_STRIKE_TRANSPARENCY) * left)
			Pool.Show(area.base, 1)
			local rimShown = 1 - (1 - Theme.COMBAT_RANGE_TELL_EDGE_TRANSPARENCY) * left
			for _, part in area.rim do
				Pool.Show(part, rimShown)
			end
			if shot ~= nil then
				Pool.Show(shot, 1)
			end
			continue
		end
		local length = area.endsAt - area.startsAt
		local u = if length > 0 then math.clamp((serverNow - area.startsAt) / length, 0, 1) else 1
		local least = Theme.COMBAT_RANGE_TELL_MIN_FILL
		local reach = area.radius * (least + (1 - least) * u)
		if math.abs(reach - area.fillShown) > 0.01 then
			area.fillShown = reach
			disc(area.fill, reach)
		end
		Pool.Show(area.fill, Theme.COMBAT_RANGE_TELL_FILL_TRANSPARENCY)
		Pool.Show(area.base, Theme.COMBAT_RANGE_AREA_BASE_TRANSPARENCY)
		for _, part in area.rim do
			Pool.Show(part, Theme.COMBAT_RANGE_TELL_EDGE_TRANSPARENCY)
		end
		local from = area.from
		if shot ~= nil and from ~= nil then
			-- Straight from the lobber to the centre, lifted by an arc that is zero at both ends.
			local along = from:Lerp(area.centre, u)
			Pool.Place(shot, CFrame.new(along + UP * (area.apex * 4 * u * (1 - u))))
			Pool.Show(shot, 0)
		end
	end
end

-- The boss with this crowd id died or was taken away, and its death takes back everything it
-- had in the air: its own circles go at once, with no landing. (An ordinary enemy's lob still
-- lands after its lobber dies; nobody calls this for those.)
function Areas.Drop(enemyId: number): ()
	for index = #areas, 1, -1 do
		if areas[index].owner == enemyId then
			release(index)
		end
	end
end

-- Every circle goes (a dummy set was loaded: its lobs land on nobody).
function Areas.Clear(): ()
	for index = #areas, 1, -1 do
		release(index)
	end
end

return Areas
