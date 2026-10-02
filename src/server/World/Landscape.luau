--!strict
-- The static world around the plots (M13, docs/INTERFACES.md "M13 contracts"). It is the same for
-- every player and never changes with game state, so PlotService.buildWorld builds it once at boot
-- and there is nothing to Init or Start. It lives outside Services because the combat place mounts
-- that folder and must never grow a hub world.
--
-- Wave 1 look: sky and haze, the ground, the hub with its earth ring, and a dirt road from the hub
-- to each plot's front edge, all Parts. Every look and size comes from World.json; only derived
-- geometry lives here. Without the file the ground and hub come out exactly as before M13 and
-- nothing else is touched, and a missing block switches only its own feature off.
--
-- Wave 2, "mesh mode": when the generated Valley.json and its templates are both present and fit
-- the live ring, the baked Valley meshes replace the earth ring and the roads (the basin mesh
-- carries both), each plot gets its apron, and the few things a player can touch (the wall, the
-- bridges, the stepping stones) are invisible Parts built from the generator's data. Meshes are
-- only ever looked at: the Ground Part stays the one floor. Anything missing falls back to the
-- wave 1 look.
--
-- Levels are frozen: plot tops and the hub top are at Y = 0 and the ground top is at -plotSize.Y
-- (the client's dressing and the plot renderers assume it). The wave 1 parts never share a visible
-- plane with a neighbour: each is centred on the ground top, so it sinks as far into the ground as
-- it stands above it.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local WorldPlan = require(sharedFolder:WaitForChild("WorldPlan"))

-- A Part's material and colour as World.json asks for them; nil keeps the Part default.
type Look = { material: Enum.Material?, color: Color3? }

-- World.json is hand-edited and read inside the server's boot, where an error would leave the game
-- without plots. So every value is checked before use: a wrong one costs a warning and its own
-- property or feature, never the world. Build runs once per boot and reads each value once, which
-- is what makes these warnings once-only.
local function warnBad(path: string, expected: string): ()
	warn(`[Landscape] World.json {path} is not {expected}; ignored`)
end

local function blockOf(value: any, path: string): any?
	if value == nil or type(value) == "table" then
		return value
	end
	warnBad(path, "an object")
	return nil
end

-- The checks above cover what a config can get wrong. This covers what nobody foresaw: Build runs
-- before the spawn, the plots and the remote handlers exist, so each M13 feature runs under it and
-- an error costs that feature and a warning, not the boot. Ground and Hub are deliberately left
-- out: they are the pre-M13 path and must fail as loudly as they always did. Returns whether the
-- feature was built, for callers that have something to undo or to fall back to.
local function guarded(feature: string, build: () -> ()): boolean
	-- The wrapper returns nil so pcall's result tuple carries the error message; a zero-return
	-- call would make `pcall` a single-value expression.
	local ok, message = pcall(function(): any?
		build()
		return nil
	end)
	if not ok then
		warn(`[Landscape] {feature} failed and was left out: {message}`)
	end
	return ok
end

local function numberOf(value: any, path: string): number?
	if type(value) == "number" then
		return value
	end
	if value ~= nil then
		warnBad(path, "a number")
	end
	return nil
end

local function colorOf(value: any): Color3?
	if type(value) ~= "table" then
		return nil
	end
	local channels: { number } = {}
	for index = 1, 3 do
		local channel = value[index]
		if type(channel) ~= "number" or channel < 0 or channel > 255 then
			return nil
		end
		channels[index] = channel
	end
	return Color3.fromRGB(channels[1], channels[2], channels[3])
end

-- Scanned rather than indexed: Enum.Material[name] raises on an unknown name.
local function materialOf(value: any): Enum.Material?
	if type(value) ~= "string" then
		return nil
	end
	for _, item in Enum.Material:GetEnumItems() do
		if item.Name == value then
			return item
		end
	end
	return nil
end

local function lookOf(block: any, path: string): Look
	local material = materialOf(block.material)
	if material == nil then
		warn(
			`[Landscape] World.json {path}.material is not an Enum.Material name; using the Part default`
		)
	end
	local color = colorOf(block.color)
	if color == nil then
		warn(
			`[Landscape] World.json {path}.color is not an RGB triple (0-255); using the Part default`
		)
	end
	return { material = material, color = color }
end

local function applyLook(part: BasePart, look: Look): ()
	if look.material ~= nil then
		part.Material = look.material
	end
	if look.color ~= nil then
		part.Color = look.color
	end
end

-- Lighting, Atmosphere and Clouds are written by property name so two checked setters serve all
-- three. An absent key leaves the property as the place file (or the engine) set it.
local function setNumber(instance: Instance, property: string, value: any, path: string): ()
	local number = numberOf(value, path)
	if number ~= nil then
		(instance :: any)[property] = number
	end
end

local function setColor(instance: Instance, property: string, value: any, path: string): ()
	if value == nil then
		return
	end
	local color = colorOf(value)
	if color ~= nil then
		(instance :: any)[property] = color
	else
		warnBad(path, "an RGB triple (0-255)")
	end
end

local function applyLighting(config: Types.WorldLightingConfig): ()
	setNumber(Lighting, "ClockTime", config.clockTime, "lighting.clockTime")
	setNumber(
		Lighting,
		"GeographicLatitude",
		config.geographicLatitude,
		"lighting.geographicLatitude"
	)
	setNumber(Lighting, "Brightness", config.brightness, "lighting.brightness")
	setColor(Lighting, "Ambient", config.ambient, "lighting.ambient")
	setColor(Lighting, "OutdoorAmbient", config.outdoorAmbient, "lighting.outdoorAmbient")
	setNumber(
		Lighting,
		"ExposureCompensation",
		config.exposureCompensation,
		"lighting.exposureCompensation"
	)
end

-- A place file that already carries an Atmosphere has that one restyled: two under Lighting would
-- leave the engine to pick one.
local function applyAtmosphere(config: Types.WorldAtmosphereConfig): ()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	setNumber(atmosphere, "Density", config.density, "atmosphere.density")
	setNumber(atmosphere, "Offset", config.offset, "atmosphere.offset")
	setColor(atmosphere, "Color", config.color, "atmosphere.color")
	setColor(atmosphere, "Decay", config.decay, "atmosphere.decay")
	setNumber(atmosphere, "Glare", config.glare, "atmosphere.glare")
	setNumber(atmosphere, "Haze", config.haze, "atmosphere.haze")
	atmosphere.Parent = Lighting
end

local function applyClouds(config: Types.WorldCloudsConfig): ()
	-- Clouds only render under Terrain, and a Rojo-built place has none until the engine adds it.
	-- A sky without clouds is still a sky, so that case is skipped without a word.
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain == nil then
		return
	end
	local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	setNumber(clouds, "Cover", config.cover, "clouds.cover")
	setNumber(clouds, "Density", config.density, "clouds.density")
	setColor(clouds, "Color", config.color, "clouds.color")
	clouds.Parent = terrain
end

-- One optional sky block: absent is off, and a failure costs only that block.
local function applySky(world: any, key: string, apply: (any) -> ()): ()
	guarded(key, function()
		local block = blockOf(world[key], key)
		if block ~= nil then
			apply(block)
		end
	end)
end

local function newDisc(name: string, radius: number, thickness: number, centre: Vector3): Part
	local disc = Instance.new("Part")
	disc.Name = name
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.Size = Vector3.new(thickness, radius * 2, radius * 2)
	-- A cylinder's axis is X; stand it upright so the flat face is the floor.
	disc.CFrame = CFrame.new(centre) * CFrame.Angles(0, 0, math.rad(90))
	return disc
end

local function buildGround(
	ring: WorldPlan.Ring,
	plotSize: Vector3,
	config: Types.WorldGroundConfig?
): ()
	local wantedSide: number? = nil
	if config ~= nil then
		wantedSide = numberOf(config.side, "ground.side")
	end
	local side = WorldPlan.GroundSide(ring, plotSize.Z, wantedSide)

	-- Ground plane so players can walk from the hub to any plot; bases rest on its top and all
	-- walkable tops sit at Y = 0 (attachment Y in layouts is a ground-level offset).
	local ground = Instance.new("Part")
	ground.Name = "Ground"
	ground.Anchored = true
	ground.Size = Vector3.new(side, plotSize.Y, side)
	ground.CFrame = CFrame.new(0, -plotSize.Y - plotSize.Y / 2, 0)
	if config ~= nil then
		applyLook(ground, lookOf(config, "ground"))
	end
	ground.Parent = Workspace
end

local function buildHub(hubRadius: number, plotSize: Vector3, config: Types.WorldHubConfig?): ()
	local hub = newDisc("Hub", hubRadius, plotSize.Y, Vector3.new(0, -plotSize.Y / 2, 0))
	if config ~= nil then
		applyLook(hub, lookOf(config, "hub"))
	end
	hub.Parent = Workspace
end

local function buildSurround(
	hubRadius: number,
	plotSize: Vector3,
	config: Types.WorldHubSurroundConfig
): Part?
	local radius: any, height: any = config.radius, config.height
	if
		type(radius) ~= "number"
		or type(height) ~= "number"
		or radius <= hubRadius
		or height <= 0
		or height >= plotSize.Y
	then
		warn(
			`[Landscape] World.json hub.surround needs radius > hubRadius ({hubRadius}) and`
				.. ` 0 < height < plotSize.Y ({plotSize.Y}); surround skipped`
		)
		return nil
	end
	-- Centred on the ground top: the hub hides its middle, its top stays below the hub's and the
	-- plots', and its bottom ends inside the ground rather than on either of the ground's faces.
	local surround = newDisc("HubSurround", radius, 2 * height, Vector3.new(0, -plotSize.Y, 0))
	-- A flat patch of colour lying on the ground gains nothing from casting.
	surround.CastShadow = false
	applyLook(surround, lookOf(config, "hub.surround"))
	return surround
end

-- Where a strip really starts. On the hub wall a flat end touches the round wall only on the
-- centreline and leaves a sliver of ground at each corner, so there the strip starts where its
-- corners meet the wall instead; the extra length lies inside the hub. A strip wider than the hub
-- has no such point and keeps its planned end, as does one that starts further out.
local function innerEnd(road: WorldPlan.Road, hubRadius: number): number
	local halfWidth = road.width / 2
	if road.innerRadius > hubRadius or halfWidth > hubRadius then
		return road.innerRadius
	end
	return math.sqrt(hubRadius * hubRadius - halfWidth * halfWidth)
end

-- `surroundHeight` is the height of the surround that was built, nil when none was.
local function buildRoads(
	ring: WorldPlan.Ring,
	hubRadius: number,
	plotSize: Vector3,
	config: Types.WorldRoadsConfig,
	surroundHeight: number?
): { Part }
	local strips: { Part } = {}
	local width: any, lift: any = config.width, config.lift
	if
		type(width) ~= "number"
		or type(lift) ~= "number"
		or width <= 0
		or lift <= 0
		or lift >= plotSize.Y
	then
		warn(
			`[Landscape] World.json roads needs width > 0 and 0 < lift < plotSize.Y ({plotSize.Y});`
				.. " no roads built"
		)
		return strips
	end
	-- A strip starts at the hub wall and runs under the surround. With equal tops the two z-fight
	-- in that band, and a higher road lies on the ring: no road is better than either.
	if surroundHeight ~= nil and lift >= surroundHeight then
		warn(
			`[Landscape] World.json roads.lift ({lift}) must be lower than hub.surround.height`
				.. ` ({surroundHeight}); no roads built`
		)
		return strips
	end
	local look = lookOf(config, "roads")
	-- WorldPlan returns the roads in plot order, so the list index is the plot's.
	for index, road in WorldPlan.Roads(ring, hubRadius, width) do
		local innerRadius = innerEnd(road, hubRadius)
		local midRadius = (innerRadius + road.outerRadius) / 2
		local position = Vector3.new(
			math.cos(road.angle) * midRadius,
			-plotSize.Y,
			math.sin(road.angle) * midRadius
		)
		local strip = Instance.new("Part")
		strip.Name = "Road_" .. index
		strip.Anchored = true
		-- Paint on the ground, not a floor: players stand on the ground beneath it, and a strip
		-- that answered raycasts or touches would get between them and everything under it.
		strip.CanCollide = false
		strip.CanQuery = false
		strip.CanTouch = false
		strip.CastShadow = false
		strip.TopSurface = Enum.SurfaceType.Smooth
		strip.BottomSurface = Enum.SurfaceType.Smooth
		strip.Size = Vector3.new(road.width, 2 * lift, road.outerRadius - innerRadius)
		-- lookAt lays local Z along the radial: the same turn as the plot base the road runs to.
		strip.CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
		applyLook(strip, look)
		table.insert(strips, strip)
	end
	return strips
end

-- The surround and the roads in a folder that is NOT parented yet: the caller parents it as its
-- last step, so a failure part-way leaves nothing in Workspace. nil when there is nothing to hold,
-- so a world without either (no World.json, or neither block) has exactly the pre-M13 Workspace
-- children.
local function buildLandscapeFolder(
	ring: WorldPlan.Ring,
	hubRadius: number,
	plotSize: Vector3,
	hubConfig: Types.WorldHubConfig?,
	roadsConfig: Types.WorldRoadsConfig?
): Folder?
	local parts: { Part } = {}
	local surroundHeight: number? = nil
	local surroundConfig: Types.WorldHubSurroundConfig? = if hubConfig ~= nil
		then blockOf(hubConfig.surround, "hub.surround")
		else nil
	if surroundConfig ~= nil then
		local surround = buildSurround(hubRadius, plotSize, surroundConfig)
		if surround ~= nil then
			table.insert(parts, surround)
			surroundHeight = surroundConfig.height
		end
	end
	if roadsConfig ~= nil then
		for _, strip in buildRoads(ring, hubRadius, plotSize, roadsConfig, surroundHeight) do
			table.insert(parts, strip)
		end
	end
	if #parts == 0 then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Landscape"
	for _, part in parts do
		part.Parent = folder
	end
	return folder
end

-- ------------------------------------------------------------------ wave 2: the Valley meshes

-- ServerStorage.Assets.World.Valley: the template set Rojo maps from templates/_world/Valley.
local ASSETS_FOLDER_NAME = "Assets"
local WORLD_FOLDER_NAME = "World"
local VALLEY_SET_NAME = "Valley"
-- Published on every plot folder by PlotService (docs/INTERFACES.md "attributes only").
local ERA_NAME_ATTRIBUTE = "EraName"
-- Valley.json `tint` -> the key of World.json `valley.aprons.<EraName>` holding that colour.
local TINT_APRON_KEYS: { [string]: string } = { apronInner = "inner", apronOuter = "outer" }
-- Per entry kind: the keys that only have to be numbers, then the keys that must also be > 0.
local BRIDGE_PLACE_KEYS = { "x", "z", "yaw" }
local BRIDGE_SIZE_KEYS = { "length", "width", "deckTop", "deckThickness", "rampLength" }
local STONE_PLACE_KEYS = { "x", "z" }
local STONE_SIZE_KEYS = { "radius", "top" }
local WALL_PLACE_KEYS: { string } = {}
local WALL_SIZE_KEYS = { "height", "thickness", "segments" }
-- Fewer slabs than a triangle's enclose nothing.
local MIN_WALL_SEGMENTS = 3
-- A WedgePart's slope rises toward its local +Z: its one upright face is its Back face. Every ramp
-- takes its facing from this sign, so if ramps ever come out backwards this is the only edit.
local WEDGE_UPHILL_Z = 1
local UP = Vector3.new(0, 1, 0)

type ValleyMeshTemplate = { name: string, template: Model, tint: string? }
-- tint name -> era name -> colour.
type Tints = { [string]: { [string]: Color3 } }
-- `shown` is the transparency the template gave the part, put back when its era has a colour.
type TintedPart = { part: BasePart, tint: string, shown: number }
type ValleyState = {
	folder: Folder,
	plotMeshes: { ValleyMeshTemplate },
	tints: Tints,
	plotHeight: number,
}

-- Set by Build once the Valley stands in Workspace, and read by AttachPlot: the plots are built
-- after the landscape, one by one, and each needs to know whether there is a Valley to join.
local activeValley: ValleyState? = nil

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- Valley.json is generated, so a wrong number in it is a generator bug rather than a typo. It is
-- checked all the same: one bad entry should cost that bridge or stone, not the Valley.
local function hasNumbers(entry: any, placeKeys: { string }, sizeKeys: { string }): boolean
	if type(entry) ~= "table" then
		return false
	end
	for _, key in placeKeys do
		if not isFinite(entry[key]) then
			return false
		end
	end
	for _, key in sizeKeys do
		if not isFinite(entry[key]) or entry[key] <= 0 then
			return false
		end
	end
	return true
end

-- World structures (docs/INTERFACES.md wave 2, "What collides"): solid to characters and nothing
-- else. Invisible because the mesh standing over each is what players see, and deaf to raycasts
-- and touches so no camera, pad or prompt ever notices them.
local function makeCollider(part: BasePart): ()
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- A template holds its mesh at generator coordinates around an identity pivot, so pivoting the
-- clone to a frame's origin puts the mesh where the generator drew it in that frame. The pivot is
-- reset first in case a template was saved with another, and the flags are forced on every part
-- because nothing may ever come to depend on a MeshPart's collision geometry.
local function placeClone(template: Model, frame: CFrame): Model
	local clone = template:Clone()
	clone.WorldPivot = CFrame.identity
	clone:PivotTo(frame)
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	return clone
end

local function valleyTemplates(): Instance?
	local assets = ServerStorage:FindFirstChild(ASSETS_FOLDER_NAME)
	local worldSets = if assets ~= nil then assets:FindFirstChild(WORLD_FOLDER_NAME) else nil
	return if worldSets ~= nil then worldSets:FindFirstChild(VALLEY_SET_NAME) else nil
end

local function templateOf(set: Instance, name: any): Model?
	if type(name) ~= "string" then
		return nil
	end
	local template = set:FindFirstChild(name)
	if template ~= nil and template:IsA("Model") then
		return template
	end
	return nil
end

-- Every apron colour resolved once at boot, so recolouring a plot later is a table lookup that
-- can neither warn nor fail. An era, or one band of it, that is absent here is hidden on that
-- era's plots.
local function tintsOf(valleyConfig: any): Tints
	local tints: Tints = {}
	for tint in TINT_APRON_KEYS do
		tints[tint] = {}
	end
	local aprons = if valleyConfig ~= nil
		then blockOf(valleyConfig.aprons, "valley.aprons")
		else nil
	if aprons == nil then
		return tints
	end
	for eraName, entry in aprons do
		if type(eraName) ~= "string" or type(entry) ~= "table" then
			warnBad(`valley.aprons.{eraName}`, "an object")
			continue
		end
		for tint, key in TINT_APRON_KEYS do
			local color = colorOf(entry[key])
			if color ~= nil then
				tints[tint][eraName] = color
			else
				warnBad(`valley.aprons.{eraName}.{key}`, "an RGB triple (0-255)")
			end
		end
	end
	return tints
end

-- An era with no colour for a band hides it rather than destroying it, so a plot that later moves
-- to an era that has one shows it again.
local function applyTints(parts: { TintedPart }, tints: Tints, eraName: any): ()
	for _, tinted in parts do
		local color: Color3? = if type(eraName) == "string"
			then tints[tinted.tint][eraName]
			else nil
		if color ~= nil then
			tinted.part.Color = color
			tinted.part.Transparency = tinted.shown
		else
			tinted.part.Transparency = 1
		end
	end
end

local function buildWall(wallRadius: any, config: any, groundTop: number, parent: Instance): ()
	if
		not isFinite(wallRadius)
		or wallRadius <= 0
		or not hasNumbers(config, WALL_PLACE_KEYS, WALL_SIZE_KEYS)
		or config.segments < MIN_WALL_SEGMENTS
		or config.segments % 1 ~= 0
	then
		warn(
			"[Landscape] the Valley wall needs Valley.json wallRadius > 0 and World.json valley.wall"
				.. ` with height > 0, thickness > 0 and a whole number of segments >= {MIN_WALL_SEGMENTS};`
				.. " no wall built"
		)
		return
	end
	local height: number, thickness: number, segments: number =
		config.height, config.thickness, config.segments
	local halfStep = math.pi / segments
	-- The inner faces are the sides of the regular polygon drawn around the wall circle, each
	-- 2 * wallRadius * tan(halfStep) long and touching the circle at its middle. Slabs of exactly
	-- that width would meet only along a line at the inner corners and gape at the outer ones, so
	-- each runs on to the outer polygon's corner: 2 * thickness * tan(halfStep) more. The surplus
	-- lies inside its neighbours, and past a corner an inner face only leaves the circle.
	local side = 2 * (wallRadius + thickness) * math.tan(halfStep)
	local distance = wallRadius + thickness / 2
	for index = 1, segments do
		local angle = (index - 1) / segments * 2 * math.pi
		local position = Vector3.new(
			math.cos(angle) * distance,
			groundTop + height / 2,
			math.sin(angle) * distance
		)
		local slab = Instance.new("Part")
		slab.Name = "Wall_" .. index
		makeCollider(slab)
		slab.Size = Vector3.new(side, height, thickness)
		-- lookAt lays local Z along the radial, so the slab's depth is its thickness.
		slab.CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
		slab.Parent = parent
	end
end

local function buildBridge(index: number, entry: Types.ValleyBridge, groundTop: number): Model
	-- The long axis straight from the contract's definition of yaw (0 = +X, turning toward +Z),
	-- handed to the CFrame as its X column. That is CFrame.Angles(0, -yaw, 0): Roblox's positive
	-- turn about +Y takes +X toward -Z, the other way, and writing the axis out leaves no sign
	-- to get wrong.
	local along = Vector3.new(math.cos(entry.yaw), 0, math.sin(entry.yaw))
	local centre = Vector3.new(entry.x, groundTop, entry.z)

	local bridge = Instance.new("Model")
	bridge.Name = "Bridge_" .. index

	local deck = Instance.new("Part")
	deck.Name = "Deck"
	makeCollider(deck)
	deck.Size = Vector3.new(entry.length, entry.deckThickness, entry.width)
	deck.CFrame =
		CFrame.fromMatrix(centre + UP * (entry.deckTop - entry.deckThickness / 2), along, UP)
	deck.Parent = bridge

	-- One ramp beyond each end of the deck, standing on the ground top with its high edge on the
	-- deck's top edge. Ramp_1 is at the end the long axis points to.
	for rampIndex, side in { 1, -1 } do
		local uphill = along * -side
		local zAxis = uphill * WEDGE_UPHILL_Z
		local ramp = Instance.new("WedgePart")
		ramp.Name = "Ramp_" .. rampIndex
		makeCollider(ramp)
		ramp.Size = Vector3.new(entry.width, entry.deckTop, entry.rampLength)
		ramp.CFrame = CFrame.fromMatrix(
			centre
				+ along * (side * (entry.length + entry.rampLength) / 2)
				+ UP * (entry.deckTop / 2),
			UP:Cross(zAxis),
			UP,
			zAxis
		)
		ramp.Parent = bridge
	end
	return bridge
end

-- The wall, the bridges and the stepping stones, in a folder that is not parented yet.
local function buildCollision(plan: any, valleyConfig: any, groundTop: number): Folder
	local collision = Instance.new("Folder")
	collision.Name = "Collision"
	buildWall(
		plan.wallRadius,
		if valleyConfig ~= nil then valleyConfig.wall else nil,
		groundTop,
		collision
	)

	local skipped: { string } = {}
	if type(plan.bridges) == "table" then
		for index, entry in plan.bridges do
			if hasNumbers(entry, BRIDGE_PLACE_KEYS, BRIDGE_SIZE_KEYS) then
				buildBridge(index, entry, groundTop).Parent = collision
			else
				table.insert(skipped, `Bridge_{index}`)
			end
		end
	end
	if type(plan.stones) == "table" then
		for index, entry in plan.stones do
			if hasNumbers(entry, STONE_PLACE_KEYS, STONE_SIZE_KEYS) then
				local stone = newDisc(
					"Stone_" .. index,
					entry.radius,
					entry.top,
					Vector3.new(entry.x, groundTop + entry.top / 2, entry.z)
				)
				makeCollider(stone)
				stone.Parent = collision
			else
				table.insert(skipped, `Stone_{index}`)
			end
		end
	end
	if #skipped > 0 then
		warn(
			"[Landscape] Valley.json entries with a missing or non-positive number got no collision: "
				.. table.concat(skipped, ", ")
		)
	end
	return collision
end

-- Decides mesh mode and, in it, returns the whole Valley in a `Landscape` folder that is NOT
-- parented yet, with the state AttachPlot needs. nil means the wave 1 look: silently when
-- Valley.json or the template set is simply not there (a checkout before the bake), and with one
-- warning naming the condition when they are there but do not fit.
local function assembleValley(
	ring: WorldPlan.Ring,
	plotSize: Vector3,
	valleyConfig: Types.WorldValleyConfig?
): (Folder?, ValleyState?)
	local plan: any = Catalog.GetValleyPlan()
	if plan == nil then
		return nil, nil
	end
	local set = valleyTemplates()
	if set == nil then
		return nil, nil
	end
	if type(plan) ~= "table" or type(plan.meshes) ~= "table" then
		warn("[Landscape] Valley.json has no meshes list; building the wave 1 world")
		return nil, nil
	end
	-- The meshes are baked around one ring; around another they would miss every plot.
	if plan.plotCount ~= ring.plotCount then
		warn(
			`[Landscape] Valley.json was baked for {plan.plotCount} plots and the ring has`
				.. ` {ring.plotCount}; building the wave 1 world`
		)
		return nil, nil
	end

	local worldMeshes: { ValleyMeshTemplate } = {}
	local plotMeshes: { ValleyMeshTemplate } = {}
	local missingRequired: { string } = {}
	local leftOut: { string } = {}
	for index, entry in plan.meshes do
		local item: any = if type(entry) == "table" then entry else {}
		local template = templateOf(set, item.name)
		local frame = item.frame
		if template == nil or (frame ~= "world" and frame ~= "plot") then
			local label = if type(item.name) == "string" then item.name else `meshes[{index}]`
			table.insert(if item.required == true then missingRequired else leftOut, label)
		elseif frame == "world" then
			table.insert(worldMeshes, { name = template.Name, template = template })
		else
			local tint: string? = nil
			if item.tint ~= nil then
				if TINT_APRON_KEYS[item.tint] ~= nil then
					tint = item.tint
				else
					warn(
						`[Landscape] Valley.json mesh {template.Name} names an unknown tint;`
							.. " left as templated"
					)
				end
			end
			table.insert(plotMeshes, { name = template.Name, template = template, tint = tint })
		end
	end
	if #missingRequired > 0 then
		warn(
			"[Landscape] required Valley meshes have no Model template under"
				.. ` ServerStorage.{ASSETS_FOLDER_NAME}.{WORLD_FOLDER_NAME}.{VALLEY_SET_NAME}`
				.. ` (or no "world"/"plot" frame): {table.concat(missingRequired, ", ")};`
				.. " building the wave 1 world"
		)
		return nil, nil
	end
	if #leftOut > 0 then
		warn(
			`[Landscape] Valley meshes left out (no Model template, or no "world"/"plot" frame):`
				.. ` {table.concat(leftOut, ", ")}`
		)
	end

	local groundTop = -plotSize.Y
	local landscape = Instance.new("Folder")
	landscape.Name = "Landscape"

	local valleyFolder = Instance.new("Folder")
	valleyFolder.Name = "Valley"
	-- Generator Y = 0 is the ground top, and its X and Z are already world studs.
	local worldFrame = CFrame.new(0, groundTop, 0)
	for _, mesh in worldMeshes do
		placeClone(mesh.template, worldFrame).Parent = valleyFolder
	end
	valleyFolder.Parent = landscape

	buildCollision(plan, valleyConfig, groundTop).Parent = landscape

	local state: ValleyState = {
		folder = valleyFolder,
		plotMeshes = plotMeshes,
		tints = tintsOf(valleyConfig),
		plotHeight = plotSize.Y,
	}
	return landscape, state
end

local Landscape = {}

function Landscape.Build(
	ring: WorldPlan.Ring,
	layout: Types.EraLayout,
	gameConfig: Types.GameConfig
): ()
	-- No World.json reads as a file with no blocks: every M13 feature off.
	local world: any = blockOf(Catalog.GetWorldConfig(), "(the whole file)") or {}

	-- Sky before any part is parented (the contract's order), so the styled ground never exists
	-- under the default light.
	applySky(world, "lighting", applyLighting)
	applySky(world, "atmosphere", applyAtmosphere)
	applySky(world, "clouds", applyClouds)

	local plotSize = layout.plotSize
	local hubRadius = gameConfig.hubRadius
	buildGround(ring, plotSize, blockOf(world.ground, "ground"))
	local hubConfig: Types.WorldHubConfig? = blockOf(world.hub, "hub")
	buildHub(hubRadius, plotSize, hubConfig)

	local valleyConfig: Types.WorldValleyConfig? = blockOf(world.valley, "valley")
	guarded("the Valley", function()
		local landscape, valley = assembleValley(ring, plotSize, valleyConfig)
		if landscape ~= nil and valley ~= nil then
			-- Parented whole and only then remembered: a failure anywhere before this line leaves
			-- nothing in Workspace and no mesh mode, and the wave 1 look below takes over.
			landscape.Parent = Workspace
			activeValley = valley
		end
	end)
	if activeValley ~= nil then
		-- The basin mesh carries the earth ring and the roads; the Parts would lie under it.
		return
	end

	local roadsConfig: Types.WorldRoadsConfig? = blockOf(world.roads, "roads")
	guarded("hub surround and roads", function()
		local folder = buildLandscapeFolder(ring, hubRadius, plotSize, hubConfig, roadsConfig)
		if folder ~= nil then
			folder.Parent = Workspace
		end
	end)
end

-- PlotService.buildWorld calls this once per plot, after the plot folder has its attributes. In
-- mesh mode it gives the plot its own copy of every plot-frame mesh (aprons, entrance) and keeps
-- the tinted ones in the colour of the plot's era; outside mesh mode it does nothing. It runs
-- inside the plot loop at boot, so it never yields and never throws.
function Landscape.AttachPlot(plotFolder: Folder, base: BasePart): ()
	local valley = activeValley
	if valley == nil then
		return
	end
	local clones: { Model } = {}
	local attached = guarded(`the Valley meshes of {plotFolder.Name}`, function()
		-- The plot frame: the plot's centre and facing, dropped from the base's middle to the
		-- ground top (generator Y = 0).
		local frame = base.CFrame * CFrame.new(0, -valley.plotHeight / 2, 0)
		local tinted: { TintedPart } = {}
		for _, mesh in valley.plotMeshes do
			local clone = placeClone(mesh.template, frame)
			clone.Name = `{mesh.name}_{plotFolder.Name}`
			table.insert(clones, clone)
			local tint = mesh.tint
			if tint ~= nil then
				for _, descendant in clone:GetDescendants() do
					if descendant:IsA("BasePart") then
						table.insert(
							tinted,
							{ part = descendant, tint = tint, shown = descendant.Transparency }
						)
					end
				end
			end
		end
		applyTints(tinted, valley.tints, plotFolder:GetAttribute(ERA_NAME_ATTRIBUTE))
		for _, clone in clones do
			clone.Parent = valley.folder
		end
		if #tinted > 0 then
			-- Never disconnected: plots are built once and live as long as the server does.
			plotFolder:GetAttributeChangedSignal(ERA_NAME_ATTRIBUTE):Connect(function()
				applyTints(tinted, valley.tints, plotFolder:GetAttribute(ERA_NAME_ATTRIBUTE))
			end)
		end
	end)
	if not attached then
		-- Some of this plot's meshes may already stand in Workspace: all or none.
		for _, clone in clones do
			clone:Destroy()
		end
	end
end

return Landscape
