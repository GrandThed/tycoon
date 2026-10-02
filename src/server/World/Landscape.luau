--!strict
-- The static world around the plots (M13 wave 1, docs/INTERFACES.md "M13 contracts"): sky and
-- haze, the ground, the hub with its earth ring, and a dirt road from the hub to each plot's
-- front edge. It is the same for every player and never changes with game state, so
-- PlotService.buildWorld builds it once at boot and there is nothing to Init or Start. It lives
-- outside Services because the combat place mounts that folder and must never grow a hub world.
--
-- Every look and size comes from World.json; only derived geometry lives here. Without the file
-- the ground and hub come out exactly as before M13 and nothing else is touched, and a missing
-- block switches only its own feature off.
--
-- Levels are frozen: plot tops and the hub top are at Y = 0 and the ground top is at -plotSize.Y
-- (the client's dressing and the plot renderers assume it). New parts never share a visible plane
-- with a neighbour: each is centred on the ground top, so it sinks as far into the ground as it
-- stands above it.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
-- out: they are the pre-M13 path and must fail as loudly as they always did.
local function guarded(feature: string, build: () -> ()): ()
	-- The wrapper returns nil so pcall's result tuple carries the error message; a zero-return
	-- call would make `pcall` a single-value expression.
	local ok, message = pcall(function(): any?
		build()
		return nil
	end)
	if not ok then
		warn(`[Landscape] {feature} failed and was left out: {message}`)
	end
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

local function newDisc(name: string, radius: number, thickness: number, centreY: number): Part
	local disc = Instance.new("Part")
	disc.Name = name
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.Size = Vector3.new(thickness, radius * 2, radius * 2)
	-- A cylinder's axis is X; stand it upright so the flat face is the floor.
	disc.CFrame = CFrame.new(0, centreY, 0) * CFrame.Angles(0, 0, math.rad(90))
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
	local hub = newDisc("Hub", hubRadius, plotSize.Y, -plotSize.Y / 2)
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
	local surround = newDisc("HubSurround", radius, 2 * height, -plotSize.Y)
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

	local roadsConfig: Types.WorldRoadsConfig? = blockOf(world.roads, "roads")
	guarded("hub surround and roads", function()
		local folder = buildLandscapeFolder(ring, hubRadius, plotSize, hubConfig, roadsConfig)
		if folder ~= nil then
			folder.Parent = Workspace
		end
	end)
end

return Landscape
