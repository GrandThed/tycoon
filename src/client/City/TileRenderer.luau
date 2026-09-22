--!strict
-- Kit road tiles for an era whose config carries `road.tiles` (docs/INTERFACES.md "Wave 2a — Tile
-- streets"; Metropolis in wave 2a). RoadGraph still owns the network, the growth rule and which
-- stretches are visible; this module only rasterises those stretches onto the `tileStuds` lattice,
-- picks one prop per cell from that cell's *visible* connectivity, and lays the pavement.
--
-- Connectivity is "joined by a stretch", never "next to each other": two parallel streets one cell
-- apart share a lattice edge but no stretch runs between them, so neither grows an arm toward the
-- other. A cell whose piece changes (a street end becoming a tee) swaps its prop in place; a cell
-- that is new gets the dust puff, under the same rule as a baked path piece.
--
-- Everything is a pure function of the layout: the cell plan, its order and its budget are fixed
-- when the plot is built, so nothing already drawn moves when the next building is bought, and
-- every client rasterises the same cells.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local PropFactory = require(script.Parent:WaitForChild("PropFactory"))
local Dust = require(script.Parent:WaitForChild("Dust"))

local TILE_PART_NAME = "RoadTile"
local PAVEMENT_PART_NAME = "Pavement"
local QUARTER_TURN = math.pi / 2
local MIN_LENGTH = 0.05
-- Four samples per cell: a walk along a stretch can then never skip over a whole cell.
local SAMPLES_PER_CELL = 4
-- A zebra crossing only reads on a street with room for one: the run from the junction to the
-- next one must hold at least this many cells (geometry, not a tunable).
local CROSSING_MIN_RUN = 3
-- Two cells of one street are a pitch apart (plus float noise from the world transform); a jump of
-- more than this many pitches is a different street and ends the dust track.
local CELL_GAP_PITCHES = 1.5

-- Arms, in the order a quarter turn about Y moves them: CFrame.Angles(0, pi/2, 0) maps +X to -Z,
-- -Z to -X, and so on. Bit `n` (1-based) of a connectivity mask is ARM_STEPS[n], so rotating a
-- piece by one quarter turn is exactly rotating its mask left by one bit.
local ARM_COUNT = 4
local ARM_STEPS: { Vector2 } = { -- (di, dj) on the lattice
	Vector2.new(1, 0), -- +X
	Vector2.new(0, -1), -- -Z
	Vector2.new(-1, 0), -- -X
	Vector2.new(0, 1), -- +Z
}

local KIND_END = "end"
local KIND_STRAIGHT = "straight"
local KIND_BEND = "bend"
local KIND_TEE = "tee"
local KIND_CROSS = "cross"
local KIND_CROSSING = "crossing"

type Piece = { kind: string, quarters: number }

-- The one rotation table (docs/INTERFACES.md "Wave 2a", canonical orientation at rotationY 0:
-- `straight`/`crossing` along X, `end` open +X, `bend` joins -X <-> +Z, `tee` open -X/+X/+Z with
-- -Z closed, `cross` all four). Indexed by mask + 1, so every one of the 16 masks is covered:
-- 0 arms is an isolated cell (drawn as an `end`, which is the only piece that reads alone).
local PIECE_BY_MASK: { Piece } = {
	{ kind = KIND_END, quarters = 0 }, -- 0: isolated
	{ kind = KIND_END, quarters = 0 }, -- 1: +X
	{ kind = KIND_END, quarters = 1 }, -- 2: -Z
	{ kind = KIND_BEND, quarters = 2 }, -- 3: +X -Z
	{ kind = KIND_END, quarters = 2 }, -- 4: -X
	{ kind = KIND_STRAIGHT, quarters = 0 }, -- 5: +X -X
	{ kind = KIND_BEND, quarters = 3 }, -- 6: -Z -X
	{ kind = KIND_TEE, quarters = 2 }, -- 7: +X -Z -X
	{ kind = KIND_END, quarters = 3 }, -- 8: +Z
	{ kind = KIND_BEND, quarters = 1 }, -- 9: +X +Z
	{ kind = KIND_STRAIGHT, quarters = 1 }, -- 10: -Z +Z
	{ kind = KIND_TEE, quarters = 1 }, -- 11: +X -Z +Z
	{ kind = KIND_BEND, quarters = 0 }, -- 12: -X +Z
	{ kind = KIND_TEE, quarters = 0 }, -- 13: +X -X +Z
	{ kind = KIND_TEE, quarters = 3 }, -- 14: -Z -X +Z
	{ kind = KIND_CROSS, quarters = 0 }, -- 15: all four
}

export type Options = {
	folder: Instance,
	plotFrame: CFrame, -- the plot base's top-centre
	eraName: string,
	tiles: Types.CityEraTilesConfig,
	thickness: number, -- config.road.thickness
	roadWidth: number, -- the era's road width, which the pavement sits outside of
	-- The road's live look (a surface variant may repaint it): placeholder cells wear it and the
	-- dust puff is tinted with it, both read at draw time rather than copied.
	materialOf: () -> Enum.Material,
	colorOf: () -> Color3,
	pavementMaterial: Enum.Material?, -- nil when the era draws no pavement
	pavementColor: Color3?,
	budgetCells: number, -- CityDressing.json budget.tileCells
	dustSeconds: number?, -- nil disables the appear puff (a config without `paths`)
	near: boolean,
}

-- One spine stretch, already ranked from the plot entrance outward by RoadGraph.
export type Segment = { id: number, a: Vector3, b: Vector3 }

type Cell = {
	i: number,
	j: number,
	position: Vector3, -- plot-local centre, Y 0
	stretches: { number }, -- stretch ids covering this cell
	links: { [number]: { number } }, -- arm -> stretch ids that join this cell to that neighbour
}

type Placed = { instance: Instance, kind: string, quarters: number, placeholder: boolean }

export type Handle = {
	options: Options,
	destroyed: boolean,
	near: boolean,
	cells: { Cell }, -- allocation order, which is entrance outward
	cellByKey: { [string]: number },
	segments: { Segment }, -- the stretches inside the cell budget, in the same order
	placed: { [number]: Placed }, -- cell index -> its prop or placeholder Part
	pavement: { [number]: { Instance } }, -- stretch id -> its two kerb Parts
	dust: Dust.Handle,
}

local function armBit(arm: number): number
	return bit32.lshift(1, arm - 1)
end

local function hasArm(mask: number, arm: number): boolean
	return bit32.band(mask, armBit(arm)) ~= 0
end

local function oppositeArm(arm: number): number
	return (arm + 1) % ARM_COUNT + 1
end

local function keyFor(i: number, j: number): string
	return string.format("%d:%d", i, j)
end

local function cellAt(tileStuds: number, point: Vector3): Vector2
	return Vector2.new(math.round(point.X / tileStuds), math.round(point.Z / tileStuds))
end

-- The lattice cells one stretch crosses, in order. Streets of a tiles era are axis-aligned on the
-- lattice (the layout rule the street plan enforces), but a join can split a segment anywhere, so
-- the walk samples rather than assuming whole cells.
local function rasterise(tileStuds: number, a: Vector3, b: Vector3): { Vector2 }
	local path: { Vector2 } = { cellAt(tileStuds, a) }
	local length = (b - a).Magnitude
	local steps = math.max(1, math.ceil(length / (tileStuds / SAMPLES_PER_CELL)))
	for step = 1, steps do
		local cell = cellAt(tileStuds, a:Lerp(b, step / steps))
		if cell ~= path[#path] then
			table.insert(path, cell)
		end
	end
	return path
end

local function armFor(delta: Vector2): number?
	for arm = 1, ARM_COUNT do
		if delta == ARM_STEPS[arm] then
			return arm
		end
	end
	return nil
end

local function propFor(tiles: Types.CityEraTilesConfig, kind: string): string?
	local props = tiles.props
	if kind == KIND_STRAIGHT then
		return props.straight
	elseif kind == KIND_END then
		return props["end"]
	elseif kind == KIND_BEND then
		return props.bend
	elseif kind == KIND_TEE then
		return props.tee
	elseif kind == KIND_CROSS then
		return props.cross
	end
	return props.crossing
end

local function destroyAll(instances: { Instance }): ()
	for _, instance in instances do
		instance:Destroy()
	end
	table.clear(instances)
end

-- ------------------------------------------------------------------ drawing

-- A plain Part the size of the cell, so a plot whose tile props are not uploaded (or whose
-- templates have not replicated yet) still shows a street instead of nothing. Retried on every
-- update, so the real tile takes over as soon as its template exists.
local function placeholderCell(handle: Handle, cell: Cell): Part
	local options = handle.options
	local thickness = math.max(options.thickness, MIN_LENGTH)
	local part = Instance.new("Part")
	part.Name = TILE_PART_NAME
	part.Size = Vector3.new(options.tiles.tileStuds, thickness, options.tiles.tileStuds)
	part.CFrame = options.plotFrame * CFrame.new(cell.position.X, thickness / 2, cell.position.Z)
	part.Material = options.materialOf()
	part.Color = options.colorOf()
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	PropFactory.Seal(part)
	part.Parent = options.folder
	return part
end

local function spawnCell(handle: Handle, index: number, piece: Piece): Placed
	local options = handle.options
	local cell = handle.cells[index]
	local model = PropFactory.Spawn(
		options.eraName,
		propFor(options.tiles, piece.kind),
		0,
		options.plotFrame
			* CFrame.new(cell.position.X, 0, cell.position.Z)
			* CFrame.Angles(0, piece.quarters * QUARTER_TURN, 0),
		options.folder
	)
	if model ~= nil then
		return {
			instance = model,
			kind = piece.kind,
			quarters = piece.quarters,
			placeholder = false,
		}
	end
	return {
		instance = placeholderCell(handle, cell),
		kind = piece.kind,
		quarters = piece.quarters,
		placeholder = true,
	}
end

-- One kerb Part per side of a stretch. Same material and colour everywhere, so the overlaps where
-- two stretches meet are invisible; the top sits at road.thickness / 2, under the tile surface.
local function placePavement(handle: Handle, segment: Segment): ()
	local options = handle.options
	local pavement = options.tiles.pavement
	local material = options.pavementMaterial
	local color = options.pavementColor
	if pavement == nil or material == nil or color == nil then
		return
	end
	local delta = segment.b - segment.a
	local length = delta.Magnitude
	if length < MIN_LENGTH then
		return
	end
	local along = delta / length
	local right = along:Cross(Vector3.yAxis)
	local width = math.max(pavement.width, MIN_LENGTH)
	local thickness = math.max(options.thickness, MIN_LENGTH)
	local parts: { Instance } = {}
	for _, side in { 1, -1 } do
		local mid = (segment.a + segment.b) / 2 + right * (side * (options.roadWidth + width) / 2)
		local part = Instance.new("Part")
		part.Name = PAVEMENT_PART_NAME
		-- Overlapped by a width at each end, so the kerbs close around a corner.
		part.Size = Vector3.new(width, thickness, length + width)
		part.CFrame = options.plotFrame
			* CFrame.lookAt(
				Vector3.new(mid.X, 0, mid.Z),
				Vector3.new(mid.X + along.X, 0, mid.Z + along.Z)
			)
		part.Material = material
		part.Color = color
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CastShadow = false
		PropFactory.Seal(part)
		part.Parent = options.folder
		table.insert(parts, part)
	end
	handle.pavement[segment.id] = parts
end

local function clearPavement(handle: Handle): ()
	for id, parts in handle.pavement do
		destroyAll(parts)
		handle.pavement[id] = nil
	end
end

-- ------------------------------------------------------------------ connectivity

local function neighbourOf(handle: Handle, index: number, arm: number): number?
	local cell = handle.cells[index]
	local step = ARM_STEPS[arm]
	return handle.cellByKey[keyFor(cell.i + step.X, cell.j + step.Y)]
end

local function maskFor(handle: Handle, index: number, visible: { [number]: boolean }): number
	local cell = handle.cells[index]
	local mask = 0
	for arm = 1, ARM_COUNT do
		local link = cell.links[arm]
		if link == nil or neighbourOf(handle, index, arm) == nil then
			continue
		end
		for _, id in link do
			if visible[id] then
				mask = bit32.bor(mask, armBit(arm))
				break
			end
		end
	end
	return mask
end

-- Cells of the straight run starting at `index` and walking along `arm`, counted until the street
-- turns, ends or reaches the next junction.
local function runCells(
	handle: Handle,
	kinds: { [number]: string },
	masks: { [number]: number },
	index: number,
	arm: number
): number
	local count = 0
	local current: number? = index
	while current ~= nil and kinds[current] == KIND_STRAIGHT do
		count += 1
		if not hasArm(masks[current], arm) then
			break
		end
		current = neighbourOf(handle, current, arm)
	end
	return count
end

local TileRenderer = {}

-- The piece and rotation a connectivity mask asks for, shared with the highway ring so the arm
-- bits and the quarter turns are defined exactly once.
function TileRenderer.PieceForMask(mask: number): (string, number)
	local piece = PIECE_BY_MASK[bit32.band(mask, 15) + 1]
	return piece.kind, piece.quarters
end

function TileRenderer.ArmBit(arm: number): number
	return armBit(arm)
end

function TileRenderer.Create(options: Options): Handle?
	if options.tiles.tileStuds < MIN_LENGTH then
		return nil
	end
	return {
		options = options,
		destroyed = false,
		near = options.near,
		cells = {},
		cellByKey = {},
		segments = {},
		placed = {},
		pavement = {},
		dust = Dust.Create(
			options.folder,
			options.plotFrame,
			options.roadWidth,
			options.tiles.tileStuds * CELL_GAP_PITCHES
		),
	}
end

-- Rasterises the whole potential network once, nearest the entrance first, and stops at the first
-- stretch whose cells do not fit `budget.tileCells`: a truncated street beats a gap in the middle
-- of one. Returns the stretch ids that made it in, which RoadGraph uses for everything keyed off
-- "a piece this plot can ever draw" (row lamps, street lines).
function TileRenderer.Plan(handle: Handle, segments: { Segment }): { [number]: boolean }
	local allowed: { [number]: boolean } = {}
	local tileStuds = handle.options.tiles.tileStuds
	local remaining = math.max(math.floor(handle.options.budgetCells), 0)
	for _, segment in segments do
		local path = rasterise(tileStuds, segment.a, segment.b)
		local fresh = 0
		for _, cell in path do
			if handle.cellByKey[keyFor(cell.X, cell.Y)] == nil then
				fresh += 1
			end
		end
		if fresh > remaining then
			break
		end
		remaining -= fresh
		local indices: { number } = {}
		for _, cell in path do
			local key = keyFor(cell.X, cell.Y)
			local index = handle.cellByKey[key]
			if index == nil then
				table.insert(handle.cells, {
					i = cell.X,
					j = cell.Y,
					position = Vector3.new(cell.X * tileStuds, 0, cell.Y * tileStuds),
					stretches = {},
					links = {},
				})
				index = #handle.cells
				handle.cellByKey[key] = index
			end
			local record = handle.cells[index]
			if record.stretches[#record.stretches] ~= segment.id then
				table.insert(record.stretches, segment.id)
			end
			table.insert(indices, index)
		end
		for step = 2, #indices do
			local arm = armFor(path[step] - path[step - 1])
			if arm == nil then
				continue -- a diagonal step (never on a lattice street) joins nothing
			end
			local from = handle.cells[indices[step - 1]]
			local to = handle.cells[indices[step]]
			local out = from.links[arm] or {}
			table.insert(out, segment.id)
			from.links[arm] = out
			local back = to.links[oppositeArm(arm)] or {}
			table.insert(back, segment.id)
			to.links[oppositeArm(arm)] = back
		end
		table.insert(handle.segments, segment)
		allowed[segment.id] = true
	end
	return allowed
end

-- Draws exactly the cells the visible stretches cover. `animate` puffs the cells that are new
-- since the last call (a purchase on a near plot); a cell that only changes piece swaps silently.
function TileRenderer.Update(handle: Handle, visible: { [number]: boolean }, animate: boolean): ()
	if handle.destroyed then
		return
	end
	local due: { number } = {}
	local dueSet: { [number]: boolean } = {}
	local masks: { [number]: number } = {}
	local kinds: { [number]: string } = {}
	local quarters: { [number]: number } = {}
	for index, cell in handle.cells do
		local drawn = false
		for _, id in cell.stretches do
			if visible[id] then
				drawn = true
				break
			end
		end
		if not drawn then
			continue
		end
		table.insert(due, index)
		dueSet[index] = true
		local mask = maskFor(handle, index, visible)
		masks[index] = mask
		kinds[index], quarters[index] = TileRenderer.PieceForMask(mask)
	end

	-- Zebra mouths: a straight cell beside a junction, on a run long enough to hold one. Written
	-- to its own table so the pass reads the plain piece choice and never its own output.
	local crossing: { [number]: boolean } = {}
	if propFor(handle.options.tiles, KIND_CROSSING) ~= nil then
		for _, index in due do
			if kinds[index] ~= KIND_STRAIGHT then
				continue
			end
			for arm = 1, ARM_COUNT do
				if not hasArm(masks[index], arm) then
					continue
				end
				local neighbour = neighbourOf(handle, index, arm)
				local kind = if neighbour ~= nil then kinds[neighbour] else nil
				if
					(kind == KIND_TEE or kind == KIND_CROSS)
					and runCells(handle, kinds, masks, index, oppositeArm(arm))
						>= CROSSING_MIN_RUN
				then
					crossing[index] = true
					break
				end
			end
		end
	end

	local fresh: { number } = {}
	for _, index in due do
		local kind = if crossing[index] then KIND_CROSSING else kinds[index]
		local placed = handle.placed[index]
		local retry = placed ~= nil
			and placed.placeholder
			and PropFactory.Template(
					handle.options.eraName,
					propFor(handle.options.tiles, kind)
				)
				~= nil
		if
			placed ~= nil
			and placed.kind == kind
			and placed.quarters == quarters[index]
			and not retry
		then
			continue
		end
		if placed ~= nil then
			placed.instance:Destroy()
		else
			table.insert(fresh, index)
		end
		handle.placed[index] = spawnCell(handle, index, { kind = kind, quarters = quarters[index] })
	end
	for index, placed in handle.placed do
		if not dueSet[index] then
			placed.instance:Destroy()
			handle.placed[index] = nil
		end
	end

	-- Pavement follows the stretches, not the cells: one pair of kerbs per street, so a junction
	-- is never boxed in. Far plots do without it.
	if handle.near and handle.options.tiles.pavement ~= nil then
		for _, segment in handle.segments do
			if visible[segment.id] and handle.pavement[segment.id] == nil then
				placePavement(handle, segment)
			end
		end
	end

	local dustSeconds = handle.options.dustSeconds
	if not animate or not handle.near or #fresh == 0 or dustSeconds == nil then
		return
	end
	local points: { Vector3 } = {}
	for _, index in fresh do
		table.insert(
			points,
			handle.options.plotFrame:PointToWorldSpace(handle.cells[index].position)
		)
	end
	Dust.Burst(handle.dust, points, handle.options.colorOf(), dustSeconds)
end

-- Far plots drop the pavement (two Parts per street) and keep the tiles, which are what reads at
-- distance. The cells and the lane graph are untouched either way.
function TileRenderer.SetNear(handle: Handle, near: boolean, visible: { [number]: boolean }): ()
	if handle.destroyed or handle.near == near then
		return
	end
	handle.near = near
	if not near then
		Dust.Stop(handle.dust)
		clearPavement(handle)
		return
	end
	if handle.options.tiles.pavement == nil then
		return
	end
	for _, segment in handle.segments do
		if visible[segment.id] and handle.pavement[segment.id] == nil then
			placePavement(handle, segment)
		end
	end
end

function TileRenderer.Destroy(handle: Handle): ()
	if handle.destroyed then
		return
	end
	handle.destroyed = true
	Dust.Destroy(handle.dust)
	for index, placed in handle.placed do
		placed.instance:Destroy()
		handle.placed[index] = nil
	end
	clearPavement(handle)
end

return TileRenderer
