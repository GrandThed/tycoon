--!strict
-- The elevated ring highway of a tiles era (docs/INTERFACES.md "Wave 2a — Elevated highway").
-- Drawn only while the layout has a `highway` table and the era config's `requiresSlot` is owned;
-- everything else about it is derived from the layout, so every client builds the same ring.
--
-- The ring is one prop per lattice cell at half-extent `ring`: `deck` along each side, `corner` at
-- the four turns and one `junction` where the ramp leaves, with the whole ramp as a single prop
-- descending into the city. The rotation of each of those comes from TileRenderer's mask table, so
-- the kit's canonical orientations are written down exactly once.
--
-- Cars loop the deck on their own lane graph (RoadGraph.LoopLanes) driven by the one Traffic
-- Heartbeat; they never take the ramp, because the ramp is not in that graph. They ride at
-- `highway.deckHeight` from the config; without it the ring is drawn but stays empty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local PropFactory = require(script.Parent:WaitForChild("PropFactory"))
local RoadGraph = require(script.Parent:WaitForChild("RoadGraph"))
local TileRenderer = require(script.Parent:WaitForChild("TileRenderer"))

local QUARTER_TURN = math.pi / 2
local UP = Vector3.yAxis
local MIN_LENGTH = 0.05
-- Ring cells, in the order a quarter turn moves them, shared with TileRenderer's arm bits.
local ARM_VECTORS: { Vector3 } = {
	Vector3.new(1, 0, 0), -- +X
	Vector3.new(0, 0, -1), -- -Z
	Vector3.new(-1, 0, 0), -- -X
	Vector3.new(0, 0, 1), -- +Z
}
local ARM_NAMES: { string } = { "+X", "-Z", "-X", "+Z" }
local KIND_STRAIGHT = "straight"
local KIND_BEND = "bend"
-- A reveal slower than this would take minutes to close the ring; a config of 0 means "instant".
local MIN_REVEAL_RATE = 0.1

export type Options = {
	folder: Instance,
	plotFrame: CFrame, -- the plot base's top-centre
	eraName: string,
	config: Types.CityEraHighwayConfig,
	layout: Types.HighwayLayout,
	tileStuds: number,
	roadWidth: number,
	pavementWidth: number, -- the era's kerb width; the sign stands clear of it
	laneOffset: number, -- the same right-hand lane offset the streets use
	budgetCells: number, -- CityDressing.json budget.highwayCells
	near: boolean,
	-- Whether a square of `halfExtent` at a plot-local point is clear of everything else the plot
	-- builds (slots, pads, plazas, kiosks, roads and their kerbs). Nil means "place as measured".
	clearOf: ((position: Vector3, halfExtent: number) -> boolean)?,
	-- The ring finished building, so the caller can seat its cars on the completed loop.
	onReady: (() -> ())?,
}

type RingCell = { position: Vector3, kind: string, quarters: number }

export type Handle = {
	options: Options,
	destroyed: boolean,
	owned: boolean,
	ready: boolean,
	-- Bumped by every clear and every near/far flip, so a reveal started earlier stops quietly.
	generation: number,
	cells: { RingCell }, -- reveal order: the junction first, then outward both ways
	corners: { Vector3 }, -- plot-local ring corners, the lane graph's loop
	direction: Vector3, -- from the junction cell into the city
	junction: Vector3, -- the junction cell's centre, plot-local
	near: boolean,
	placed: { Instance },
	lanes: RoadGraph.Lanes?,
}

-- A half-written layout or config key must draw nothing, never throw in the middle of a sync.
local function numberOr(value: any, fallback: number): number
	return if type(value) == "number" and value == value then value else fallback
end

local function armIndexFor(name: string?): number?
	for index, candidate in ARM_NAMES do
		if candidate == name then
			return index
		end
	end
	return nil
end

local function armIndexOf(direction: Vector3): number
	local best, bestDot = 1, -math.huge
	for index, arm in ARM_VECTORS do
		local dot = arm:Dot(direction)
		if dot > bestDot then
			best, bestDot = index, dot
		end
	end
	return best
end

-- ------------------------------------------------------------------ measuring the ramp

-- How far a prop reaches from its anchor along each axis, measured on the template it is about to
-- be cloned from: the ramp's reach along +X is where its low end touches down, and the sign's
-- widest half-extent is how far it must stand off the road not to hang over it.
local function reachOf(handle: Handle, propName: string?): (number?, number?)
	local options = handle.options
	local anchor, parts = PropFactory.StageParts(options.eraName, propName, 0)
	if anchor == nil or #parts == 0 then
		return nil, nil
	end
	local frame = anchor :: CFrame
	local alongX, half = 0, 0
	for _, part in parts do
		local centre = frame:PointToObjectSpace(part.Position)
		local size = part.Size
		alongX = math.max(alongX, centre.X + size.X / 2)
		half = math.max(half, math.abs(centre.X) + size.X / 2, math.abs(centre.Z) + size.Z / 2)
	end
	return alongX, half
end

-- ------------------------------------------------------------------ plan

-- The ring's cells as a cycle, walked counter-clockwise from the (-half, -half) corner, plus the
-- four corner centres the lane graph loops through.
local function ringCycle(half: number, tileStuds: number): ({ Vector2 }, { Vector3 })
	local cycle: { Vector2 } = {}
	local function add(i: number, j: number): ()
		table.insert(cycle, Vector2.new(i, j))
	end
	for i = -half, half - 1 do
		add(i, -half)
	end
	for j = -half, half - 1 do
		add(half, j)
	end
	for i = half, -half + 1, -1 do
		add(i, half)
	end
	for j = half, -half + 1, -1 do
		add(-half, j)
	end
	local corners: { Vector3 } = {
		Vector3.new(-half * tileStuds, 0, -half * tileStuds),
		Vector3.new(half * tileStuds, 0, -half * tileStuds),
		Vector3.new(half * tileStuds, 0, half * tileStuds),
		Vector3.new(-half * tileStuds, 0, half * tileStuds),
	}
	return cycle, corners
end

local function kindFor(handle: Handle, kind: string): string?
	local props = handle.options.config.props
	if kind == KIND_STRAIGHT then
		return props.deck
	elseif kind == KIND_BEND then
		return props.corner
	end
	return props.junction
end

-- ------------------------------------------------------------------ drawing

local function place(handle: Handle, propName: string?, cframe: CFrame): ()
	if #handle.placed >= math.max(math.floor(handle.options.budgetCells), 0) then
		return
	end
	local model =
		PropFactory.Spawn(handle.options.eraName, propName, 0, cframe, handle.options.folder)
	if model ~= nil then
		table.insert(handle.placed, model)
	end
end

local function placeCell(handle: Handle, index: number): ()
	local cell = handle.cells[index]
	local options = handle.options
	place(
		handle,
		kindFor(handle, cell.kind),
		options.plotFrame
			* CFrame.new(cell.position.X, 0, cell.position.Z)
			* CFrame.Angles(0, cell.quarters * QUARTER_TURN, 0)
	)
end

-- The ramp hangs off the junction cell's inward edge and descends along `direction`; the optional
-- sign stands at its foot, on one side of the street, facing back up the ramp.
local function placeRamp(handle: Handle): ()
	local options = handle.options
	local direction = handle.direction
	local quarters = armIndexOf(direction) - 1
	local foot = handle.junction + direction * (options.tileStuds / 2)
	place(
		handle,
		options.config.props.ramp,
		options.plotFrame
			* CFrame.new(foot.X, 0, foot.Z)
			* CFrame.Angles(0, quarters * QUARTER_TURN, 0)
	)
	local signProp = options.config.props.sign
	if signProp == nil then
		return
	end
	-- The ramp's real low end (its geometry rarely fills whole cells), and the sign set down beside
	-- the street there: half the road, the kerb, and its own half-width, so nothing of it hangs
	-- over the asphalt.
	local descent = reachOf(handle, options.config.props.ramp)
	if descent == nil then
		return
	end
	local _, measured = reachOf(handle, signProp)
	-- An unmeasurable sign is assumed to fill a cell, so it is judged as the largest thing it
	-- could be rather than squeezed into a gap it does not fit.
	local signHalf = measured or options.tileStuds / 2
	local clearance = options.roadWidth / 2 + math.max(options.pavementWidth, 0) + signHalf
	local toe = foot + direction * descent
	local right = direction:Cross(UP)
	-- The kerb beside the ramp's foot, then the same spot across the street; if the plot has built
	-- on both (the corridors are narrow), the sign is simply left out -- a missing roadside sign
	-- beats one standing inside a building.
	local position: Vector3? = nil
	local clearOf = options.clearOf
	for _, side in { 1, -1 } do
		local candidate = toe + right * (side * clearance)
		if clearOf == nil or clearOf(candidate, signHalf) then
			position = candidate
			break
		end
	end
	if position == nil then
		return
	end
	local spot = position :: Vector3
	place(
		handle,
		signProp,
		options.plotFrame
			* CFrame.new(spot.X, 0, spot.Z)
			-- Front (-Z at rotation 0) turned to face back along the ramp.
			* CFrame.Angles(0, math.atan2(direction.X, direction.Z), 0)
	)
end

local function clear(handle: Handle): ()
	handle.generation += 1
	handle.ready = false
	handle.lanes = nil
	for _, instance in handle.placed do
		instance:Destroy()
	end
	table.clear(handle.placed)
end

local function finish(handle: Handle): ()
	handle.ready = true
	local onReady = handle.options.onReady
	if onReady ~= nil then
		onReady()
	end
end

local function placeAll(handle: Handle): ()
	-- The ramp first, so it holds its two pieces of the budget and the reveal has something to
	-- grow out of.
	placeRamp(handle)
	for index = 1, #handle.cells do
		placeCell(handle, index)
	end
	finish(handle)
end

-- Builds outward from the ramp in both directions (the cells are already in that order), so the
-- purchase reads as the ring growing from the thing the player just paid for.
local function reveal(handle: Handle, generation: number): ()
	local rate = math.max(numberOr(handle.options.config.revealCellsPerSecond, 0), MIN_REVEAL_RATE)
	local step = 1 / rate
	placeRamp(handle)
	for index = 1, #handle.cells do
		if handle.destroyed or handle.generation ~= generation then
			return
		end
		placeCell(handle, index)
		task.wait(step)
	end
	if handle.destroyed or handle.generation ~= generation then
		return
	end
	finish(handle)
end

-- ------------------------------------------------------------------ public

local Highway = {}

-- Nil when the layout cannot describe a ring (no `highway`, a ring inside one cell, a lattice of
-- zero): a plot with no highway, silently, like every other missing dressing key.
function Highway.Create(options: Options): Handle?
	local tileStuds = options.tileStuds
	if tileStuds < MIN_LENGTH then
		return nil
	end
	local half = math.round(numberOr(options.layout.ring, 0) / tileStuds)
	if half < 1 then
		return nil
	end
	local ramp = options.layout.ramp
	local requested = if type(ramp) == "table" then ramp.cell else nil
	-- Without a ramp cell there is no junction and no way down: no ring, silently.
	if typeof(requested) ~= "Vector3" then
		return nil
	end
	local cycle, corners = ringCycle(half, tileStuds)
	-- The layout gives the ramp cell in plot-local studs like every other layout position; taking
	-- the nearest ring cell also swallows a plan that named it by lattice index.
	local junctionIndex, bestDistance = 1, math.huge
	for index, cell in cycle do
		local centre = Vector3.new(cell.X * tileStuds, 0, cell.Y * tileStuds)
		local distance = (centre - Vector3.new(requested.X, 0, requested.Z)).Magnitude
		if distance < bestDistance then
			junctionIndex, bestDistance = index, distance
		end
	end
	local junction = cycle[junctionIndex]
	local junctionCentre = Vector3.new(junction.X * tileStuds, 0, junction.Y * tileStuds)
	local armIndex = armIndexFor(if type(ramp.direction) == "string" then ramp.direction else nil)
	-- An unknown direction points into the city, which is the only way a ramp can ever run.
	local direction = if armIndex ~= nil
		then ARM_VECTORS[armIndex]
		else ARM_VECTORS[armIndexOf(-junctionCentre)]

	-- Reveal order: the junction, then one cell each way around the cycle at a time.
	local order: { number } = { junctionIndex }
	local count = #cycle
	local seen: { [number]: boolean } = { [junctionIndex] = true }
	for offset = 1, count do
		local ahead = (junctionIndex - 1 + offset) % count + 1
		local behind = (junctionIndex - 1 - offset) % count + 1
		for _, index in { ahead, behind } do
			if not seen[index] then
				seen[index] = true
				table.insert(order, index)
			end
		end
	end

	local cells: { RingCell } = {}
	for _, index in order do
		local cell = cycle[index]
		local previous = cycle[(index - 2) % count + 1]
		local following = cycle[index % count + 1]
		local mask = 0
		for _, neighbour in { previous, following } do
			local delta = neighbour - cell
			for arm, step in ARM_VECTORS do
				if delta == Vector2.new(step.X, step.Z) then
					mask = bit32.bor(mask, TileRenderer.ArmBit(arm))
				end
			end
		end
		if index == junctionIndex then
			mask = bit32.bor(mask, TileRenderer.ArmBit(armIndexOf(direction)))
		end
		local kind, quarters = TileRenderer.PieceForMask(mask)
		table.insert(cells, {
			position = Vector3.new(cell.X * tileStuds, 0, cell.Y * tileStuds),
			kind = kind,
			quarters = quarters,
		})
	end

	return {
		options = options,
		destroyed = false,
		owned = false,
		ready = false,
		generation = 0,
		cells = cells,
		corners = corners,
		direction = direction,
		junction = junctionCentre,
		near = options.near,
		placed = {},
		lanes = nil,
	}
end

-- `owned` is the slot the era config names; `animate` is the caller's "this was a purchase just
-- now" flag. A purchase on a near plot builds the ring out from the ramp; joins, era rebuilds and
-- far plots get it in one frame.
function Highway.SetOwned(handle: Handle, owned: boolean, animate: boolean): ()
	if handle.destroyed or handle.owned == owned then
		return
	end
	handle.owned = owned
	clear(handle)
	if not owned then
		return
	end
	if animate and handle.near then
		local generation = handle.generation
		task.spawn(reveal, handle, generation)
		return
	end
	placeAll(handle)
end

-- A plot that goes far mid-reveal finishes at once: nobody is watching it grow, and a half ring
-- hanging in the air is worse than one that is simply there.
function Highway.SetNear(handle: Handle, near: boolean): ()
	if handle.destroyed or handle.near == near then
		return
	end
	handle.near = near
	if near or not handle.owned or handle.ready then
		return
	end
	clear(handle)
	placeAll(handle)
end

function Highway.Ready(handle: Handle): boolean
	return not handle.destroyed and handle.owned and handle.ready
end

-- The ring's lane loop at deck height, or nil while the ring is unfinished or the deck template
-- has not replicated (no measurable deck means no cars, never a guess).
function Highway.Lanes(handle: Handle): RoadGraph.Lanes?
	if not Highway.Ready(handle) then
		return nil
	end
	local cached = handle.lanes
	if cached ~= nil then
		return cached
	end
	-- The deck's driving height is config (`highway.deckHeight`), not a measurement: a merged kit
	-- prop is a single MeshPart, so nothing in the template tells the road surface from the top of
	-- its railing. Absent means no cars, never cars floating over the deck.
	local surface = handle.options.config.deckHeight
	if surface == nil or surface <= 0 then
		return nil
	end
	local lanes = RoadGraph.LoopLanes(
		handle.options.plotFrame,
		handle.corners,
		surface,
		handle.options.laneOffset
	)
	handle.lanes = lanes
	return lanes
end

function Highway.Destroy(handle: Handle): ()
	if handle.destroyed then
		return
	end
	handle.destroyed = true
	clear(handle)
end

return Highway
