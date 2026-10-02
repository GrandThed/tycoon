--!strict
-- M13 wave 2: where the Valley's river runs, for the one rule the client keeps about it
-- (docs/INTERFACES.md "Client — skirt entries in the river"). A plot's skirt dressing stands on the
-- world ground past the plot's edges, the river runs through two of the gaps between neighbouring
-- plots, and a skirt entry that would stand in the water is not drawn. The river itself is the
-- server's meshes; this module only reads the channel the generator wrote to Valley.json and never
-- recomputes it.
--
-- The answer for a point is a pure function of Valley.json, World.json and what the server built
-- at boot (the ring of plots, and whether it placed the Valley meshes), none of which change during
-- a session, so every client agrees on it. Config modules and instances can replicate after the
-- first client frame: until the plan, the world config, a ring of the plan's size and the server's
-- Valley folder are all there, nothing is blocked and nothing is kept, so a later call tries again.
-- Once the test is built it stays for the session.
--
-- Deliberately not mirrored by tools/cityfabric.py or plotrender.py: the rule depends on where a
-- plot sits in the world, which a single-plot render does not have.
--
-- Hub only: the combat place maps neither src/client/City nor a ring of plots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

-- PlotService's names (Workspace/Plots/Plot_<i>), as CityDressingController reads them.
local PLOTS_FOLDER = "Plots"
local PLOT_NAME_PATTERN = "^Plot_%d+$"
-- Landscape's names (Workspace/Landscape/Valley): the folder it parents only when it places the
-- Valley meshes. In every fallback to the wave 1 world it does not exist, and neither does a river.
local LANDSCAPE_FOLDER = "Landscape"
local VALLEY_FOLDER = "Valley"
-- Segments are boxed in runs of this many, in polyline order, so a point is only measured against
-- the stretch of river beside it. A lookup aid, not a tunable: any run length gives the same answer.
local RUN_LENGTH = 16

type Box = { minX: number, maxX: number, minZ: number, maxZ: number }

-- One stretch of the centreline from (ax, az), `dx`, `dz` long. `inverse` is 1 / length squared
-- (0 for two samples on one spot, which then act as a disc). `reach` is how close a point may
-- come: the channel's halfWidth plus the margin.
type Segment = {
	ax: number,
	az: number,
	dx: number,
	dz: number,
	inverse: number,
	reach: number,
}

type Run = { box: Box, first: number, last: number }

type River = { box: Box, segments: { Segment }, runs: { Run } }

local river: River? = nil

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- A box holding nothing: every point is outside it.
local function emptyBox(): Box
	return { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
end

local function include(box: Box, other: Box): ()
	box.minX = math.min(box.minX, other.minX)
	box.maxX = math.max(box.maxX, other.maxX)
	box.minZ = math.min(box.minZ, other.minZ)
	box.maxZ = math.max(box.maxZ, other.maxZ)
end

-- Whether a disc of radius `extra` about (x, z) lies wholly outside the box.
local function outside(box: Box, x: number, z: number, extra: number): boolean
	return x < box.minX - extra
		or x > box.maxX + extra
		or z < box.minZ - extra
		or z > box.maxZ + extra
end

-- Valley.json is generated, so a wrong sample is a generator bug rather than a typo. It is checked
-- all the same: a bad sample costs the two segments it ends, never an error.
local function validSample(sample: any): boolean
	return type(sample) == "table"
		and finite(sample[1])
		and finite(sample[2])
		and finite(sample[3])
		and sample[3] >= 0
end

local function livePlotCount(): number
	local plots = Workspace:FindFirstChild(PLOTS_FOLDER)
	if plots == nil then
		return 0
	end
	local count = 0
	for _, child in plots:GetChildren() do
		if string.match(child.Name, PLOT_NAME_PATTERN) ~= nil then
			count += 1
		end
	end
	return count
end

-- Whether the server placed the Valley meshes. Without its templates (a checkout between the bake
-- and the harvest), on a ring of another size or after a failed build it shows the wave 1 world,
-- where no river is drawn and the woods must stand whole.
local function valleyStands(): boolean
	local landscape = Workspace:FindFirstChild(LANDSCAPE_FOLDER)
	return landscape ~= nil and landscape:FindFirstChild(VALLEY_FOLDER) ~= nil
end

-- Builds the test, or returns nil while it cannot be decided yet. The meshes are baked for one
-- plotCount and the server keeps the wave 1 world on any other ring, so there is no river to keep
-- clear of until the live ring is the plan's and the Valley stands; a world still replicating
-- looks the same as one without them, which is why a "no" is never remembered.
local function build(): River?
	local plan: any = Catalog.GetValleyPlan()
	local world: any = Catalog.GetWorldConfig()
	if type(plan) ~= "table" or type(world) ~= "table" then
		return nil
	end
	-- The cheap test first: in every wave 1 fallback this runs on each call, and counting the plots
	-- walks the whole ring.
	if not valleyStands() or livePlotCount() ~= plan.plotCount then
		return nil
	end
	local valley = world.valley
	-- No margin in World.json is no extra room round the channel, not no rule.
	local margin = if type(valley) == "table" and finite(valley.skirtMargin)
		then valley.skirtMargin
		else 0
	local built: River = { box = emptyBox(), segments = {}, runs = {} }
	local samples = plan.river
	for index = 2, if type(samples) == "table" then #samples else 0 do
		local a = samples[index - 1]
		local b = samples[index]
		if not (validSample(a) and validSample(b)) then
			continue
		end
		-- The wider end's halfWidth for the whole segment: where the channel widens or narrows the
		-- rule errs toward one tree too few on the bank, never toward a tree in the water.
		local reach = math.max(a[3], b[3]) + margin
		if reach <= 0 then
			continue
		end
		local dx = b[1] - a[1]
		local dz = b[2] - a[2]
		local lengthSquared = dx * dx + dz * dz
		table.insert(built.segments, {
			ax = a[1],
			az = a[2],
			dx = dx,
			dz = dz,
			inverse = if lengthSquared > 0 then 1 / lengthSquared else 0,
			reach = reach,
		})
		local count = #built.segments
		local run = built.runs[#built.runs]
		if run == nil or count - run.first >= RUN_LENGTH then
			run = { box = emptyBox(), first = count, last = count }
			table.insert(built.runs, run)
		end
		run.last = count
		include(run.box, {
			minX = math.min(a[1], b[1]) - reach,
			maxX = math.max(a[1], b[1]) + reach,
			minZ = math.min(a[2], b[2]) - reach,
			maxZ = math.max(a[2], b[2]) + reach,
		})
	end
	for _, boxed in built.runs do
		include(built.box, boxed.box)
	end
	river = built
	return built
end

local WorldBlock = {}

-- Whether world point (worldX, worldZ) lies in the river: within the wider end's halfWidth plus
-- World.json `valley.skirtMargin` of a segment of Valley.json `river`. `extraRadius` widens that
-- for something with a body of its own (a clump's quarter of trees about its centre). False with
-- no plan, no river, a live ring that is not the plan's, or a server that placed no Valley.
function WorldBlock.Blocked(worldX: number, worldZ: number, extraRadius: number?): boolean
	local current = river or build()
	local extra = if extraRadius ~= nil and finite(extraRadius) then math.max(extraRadius, 0) else 0
	if current == nil or outside(current.box, worldX, worldZ, extra) then
		return false
	end
	local segments = current.segments
	for _, run in current.runs do
		if outside(run.box, worldX, worldZ, extra) then
			continue
		end
		for index = run.first, run.last do
			local segment = segments[index]
			local px = worldX - segment.ax
			local pz = worldZ - segment.az
			local along = math.clamp((px * segment.dx + pz * segment.dz) * segment.inverse, 0, 1)
			local offX = px - along * segment.dx
			local offZ = pz - along * segment.dz
			local reach = segment.reach + extra
			if offX * offX + offZ * offZ <= reach * reach then
				return true
			end
		end
	end
	return false
end

return WorldBlock
