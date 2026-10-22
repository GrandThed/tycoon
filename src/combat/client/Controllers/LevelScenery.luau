--!strict
-- The dressed level on the client (docs/prompts/l4-w2-contract.md, sections 2.3, 2.4 and 8;
-- rulings L4W2-2, -3, -6, -7, -15). The M9 pattern: client-side, walk-through, no remote.
--
-- The server decides "dressed", all or nothing (LevelDress.Accept), before it hides anything: it
-- builds the level's Parts as always, makes every piece the scenery covers invisible (attribute
-- `Skinned`, collision and query unchanged), and LAST sets `Workspace.Level`'s attributes `Dress`
-- (the layout's name) and `DressHash` (its plan hash). Clear sets both to nil first. This module
-- builds the scenery only on that word, and only when its own copy of the dress file
-- (Catalog.GetLevelDress) carries the same plan hash:
--  * Into `Workspace.LevelScenery`, Theme.COMBAT_SCENERY_CLONES_PER_FRAME clones a frame: first the
--    mesh groups that cover hidden collision (ground, skin, camp, rock) so the floor is under the
--    player's feet soonest, then canopy, dress and backdrop, then the props, then the fires. A
--    generation counter stops a build the level outlived (a Clear or a new run mid-build).
--  * A mesh is a clone of `ReplicatedStorage.Assets.Levels.<layout>.<name>` parented with no
--    move: the template already holds the world shape (the pipeline's level_template_xml). Every
--    BasePart is anchored and nothing of it collides, queries or touches (Landscape.placeClone's
--    flags): the invisible Parts are the level's collision, the scenery is only drawn.
--  * A prop is a clone of `Assets.Props.<set>.<piece>` (the set per layout is
--    Theme.COMBAT_SCENERY_PROP_SETS), pivoted on its Base (the bottom centre) to the entry's point
--    and yaw, then scaled about that Base. A missing piece is left out with one warn, never a
--    refusal. A prop with `with` stands only while Workspace.Level has a child of that name: the
--    bramble burns (its block is destroyed) and a found shortcut never builds it.
--  * A fire (`effects`, kind "fire") is an invisible anchored Part with a ParticleEmitter and a
--    PointLight. Neither on a low-end device (L4W2-15: never on reducedMotion, which is every
--    touch device); the Campfire prop's modelled flames stay.
--  * If any mesh cannot be cloned (missing template, a refused hash, an error): one warn, the
--    folder is destroyed and every `Skinned` Part is shown locally (Transparency 0), so no
--    collision is ever left invisible; the mood goes back too. The level then reads as grey.
--
-- Mood B (2.4, L4W2-7): while a level is dressed, `Expeditions.json moods.<levelId>` is applied
-- to Lighting and an Atmosphere, on this client only. Every Lighting or Atmosphere property it
-- writes is recorded first, and whether it made the Atmosphere; Clear (or O) puts back exactly
-- those properties and destroys only an Atmosphere it made.
--
-- Studio only (8): Y cycles forest -> grey (the scenery hidden, the Skinned Parts shown) -> walls
-- (the forest, every invisible wall of the level drawn red) -> forest; O switches mood B and the
-- default light. Both are local and stay as chosen for the session, also across runs; the host
-- hands a toast (SetToastHandler) that says what each press did.
--
-- What it writes on the server's Parts (the Skinned Parts' transparency, a wall's colour) is
-- local and recorded, and put back on every change of view; a Part the server destroyed is
-- skipped. Nothing here yields on the Heartbeat: the build runs in its own thread.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local DrawClock = require(script.Parent:WaitForChild("DrawClock"))

type View = "forest" | "grey" | "walls"

-- A local write on one of the server's Parts, as it stood before (put back by restorePainted).
type Painted = { transparency: number, color: Color3, material: Enum.Material }

-- One step of a build, in the order it runs.
type Job = {
	kind: "mesh" | "prop" | "fire",
	mesh: Types.LevelDressMesh?,
	prop: Types.LevelDressProp?,
	effect: Types.LevelDressEffect?,
}

-- Names the server and the pipeline own. The client trees cannot require the server's modules,
-- so they are repeated here (as SecretFx's LEVEL_FOLDER and ReactFx's HEAT_ATTRIBUTE are).
local NAMES = {
	level = "Level", -- LevelService.LEVEL_FOLDER
	dress = "Dress", -- LevelService.Build's last two attributes on Workspace.Level
	dressHash = "DressHash",
	skinned = "Skinned", -- every piece the scenery covers (LevelService.construct)
	scenery = "LevelScenery",
	assets = "Assets", -- ReplicatedStorage.Assets (combat.project.json)
	levels = "Levels",
	props = "Props",
	base = "Base", -- a prop template's invisible bottom-centre anchor (gen_templates)
	frame = "level", -- the only dress frame the game reads: world studs
	fire = "fire", -- the only effect kind
	-- The engine's own collision group. In Workspace.Level the only other group a Part is ever put
	-- in is BarrierGroups.BARRIER (camp C's barrier and the dress's tree lines), so a Part out of
	-- this one is an invisible wall. Reading the group, not a name, also shows a wall that was
	-- built without its group (it would then stop rays): the walls view misses it.
	defaultGroup = "Default",
}

-- The mesh groups in build order: what covers hidden collision first. A group not listed comes
-- after these (its meshes are still built).
local GROUP_ORDER: { string } = { "ground", "skin", "camp", "rock", "canopy", "dress", "backdrop" }

local KEYS = {
	scenery = Enum.KeyCode.Y,
	mood = Enum.KeyCode.O,
}

local TEXT = {
	forest = "Scenery: forest",
	grey = "Scenery: grey (the collision blocks)",
	walls = "Scenery: forest + invisible walls in red",
	moodOn = "Light: the level's mood",
	moodOff = "Light: default",
	noMood = "Light: this level has no mood",
	notDressed = "This level is not dressed",
}

local NEXT_VIEW: { [View]: View } = { forest = "grey", grey = "walls", walls = "forest" }

local LevelScenery = {}

local state = {
	-- Workspace.Level once it exists (mission mode only; the range never has one).
	level = nil :: Folder?,
	-- Bumped on every change of the server's word; a build thread stops when it is not its own.
	generation = 0,
	-- The (Dress, DressHash) pair last acted on, "" for none.
	builtKey = "",
	-- The dress being shown; nil = grey (not dressed, or the client could not dress it).
	dress = nil :: Types.LevelDress?,
	folder = nil :: Folder?,
	-- Every step of the build has run (a `with` prop's block arriving earlier waits for it).
	built = false,
	-- The server dressed the level but this client could not: the Skinned Parts are shown.
	failed = false,
	-- Studio levers (Y, O), kept for the session.
	view = "forest" :: View,
	moodWanted = true,
	-- Props with `with`: the specs by the name they wait on, and the clones standing for each.
	withSpecs = {} :: { [string]: { Types.LevelDressProp } },
	withClones = {} :: { [string]: { Model } },
	-- What the prop clones come from while dressed (nil = the set is missing).
	propSet = nil :: Instance?,
	painted = {} :: { [BasePart]: Painted },
	-- Mood B: the Lighting and Atmosphere properties written, as they were before; the Atmosphere
	-- written to, and whether this module made it.
	mood = {
		applied = false,
		lighting = {} :: { [string]: any },
		atmosphere = nil :: Atmosphere?,
		atmosphereSaved = {} :: { [string]: any },
		madeAtmosphere = false,
	},
	warned = {} :: { [string]: boolean },
	toast = nil :: ((string) -> ())?,
	connections = {} :: { RBXScriptConnection },
	levelConnections = {} :: { RBXScriptConnection },
}

local function warnOnce(text: string): ()
	if state.warned[text] then
		return
	end
	state.warned[text] = true
	warn("[LevelScenery] " .. text)
end

local function say(text: string): ()
	local toast = state.toast
	if toast ~= nil then
		toast(text)
	else
		print("[LevelScenery] " .. text)
	end
end

local function finite(value: any): number?
	if
		typeof(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
	then
		return value
	end
	return nil
end

-- An RGB triple 0-255 as a Color3, nil when it is not one.
local function colorOf(value: any): Color3?
	if typeof(value) ~= "table" or #value ~= 3 then
		return nil
	end
	local r, g, b = finite(value[1]), finite(value[2]), finite(value[3])
	if r == nil or g == nil or b == nil then
		return nil
	end
	if r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

-- Every BasePart anchored, and nothing of the scenery collides, queries or touches.
local function seal(root: Instance): ()
	local function flags(part: BasePart): ()
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	if root:IsA("BasePart") then
		flags(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			flags(descendant)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Local writes on the server's Parts
----------------------------------------------------------------------------------------------

local function paint(part: BasePart, transparency: number, color: Color3?): ()
	if state.painted[part] == nil then
		state.painted[part] = {
			transparency = part.Transparency,
			color = part.Color,
			material = part.Material,
		}
	end
	part.Transparency = transparency
	if color ~= nil then
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
	end
end

local function restorePainted(): ()
	for part, was in state.painted do
		if part.Parent ~= nil then
			part.Transparency = was.transparency
			part.Color = was.color
			part.Material = was.material
		end
	end
	table.clear(state.painted)
end

local function isSkinned(child: Instance): boolean
	return child:IsA("BasePart") and child:GetAttribute(NAMES.skinned) == true
end

local function isWall(child: Instance): boolean
	return child:IsA("BasePart") and child.CollisionGroup ~= NAMES.defaultGroup
end

-- Shown as the grey level shows them: only what the server hid for the scenery.
local function showSkinned(child: Instance): ()
	if isSkinned(child) then
		paint(child :: BasePart, 0, nil)
	end
end

local function showWall(child: Instance): ()
	if isWall(child) then
		paint(
			child :: BasePart,
			Theme.COMBAT_SCENERY_WALL_TRANSPARENCY,
			Theme.COMBAT_SCENERY_WALL_COLOR
		)
	end
end

-- The view as it should stand now, from scratch: every local write is put back first.
local function applyView(): ()
	restorePainted()
	local level = state.level
	local folder = state.folder
	if level == nil then
		return
	end
	if state.failed then
		for _, child in level:GetChildren() do
			showSkinned(child)
		end
		return
	end
	if state.dress == nil or folder == nil then
		return -- not dressed: the level is the grey one as built, nothing hidden
	end
	local view = state.view
	folder.Parent = if view == "grey" then nil else Workspace
	for _, child in level:GetChildren() do
		if view == "grey" then
			showSkinned(child)
		elseif view == "walls" then
			showWall(child)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Mood B
----------------------------------------------------------------------------------------------

local LIGHTING_NUMBERS: { { key: string, property: string } } = {
	{ key = "clockTime", property = "ClockTime" },
	{ key = "geographicLatitude", property = "GeographicLatitude" },
	{ key = "brightness", property = "Brightness" },
	{ key = "exposureCompensation", property = "ExposureCompensation" },
}
local LIGHTING_COLORS: { { key: string, property: string } } = {
	{ key = "ambient", property = "Ambient" },
	{ key = "outdoorAmbient", property = "OutdoorAmbient" },
}
local ATMOSPHERE_NUMBERS: { { key: string, property: string } } = {
	{ key = "density", property = "Density" },
	{ key = "offset", property = "Offset" },
	{ key = "glare", property = "Glare" },
	{ key = "haze", property = "Haze" },
}
local ATMOSPHERE_COLORS: { { key: string, property: string } } = {
	{ key = "color", property = "Color" },
	{ key = "decay", property = "Decay" },
}

-- Writes one property, keeping what it was before the first write.
local function write(instance: Instance, saved: { [string]: any }, property: string, value: any): ()
	if saved[property] == nil then
		saved[property] = (instance :: any)[property]
	end
	(instance :: any)[property] = value
end

-- One config block's keys onto `instance` (an absent key leaves that property alone; a bad one is
-- warned once and left alone).
local function writeBlock(
	instance: Instance,
	saved: { [string]: any },
	block: { [string]: any },
	numbers: { { key: string, property: string } },
	colors: { { key: string, property: string } },
	path: string
): ()
	for _, entry in numbers do
		local value = block[entry.key]
		if value ~= nil then
			local number = finite(value)
			if number ~= nil then
				write(instance, saved, entry.property, number)
			else
				warnOnce(`{path}.{entry.key} is not a number; left as it was`)
			end
		end
	end
	for _, entry in colors do
		local value = block[entry.key]
		if value ~= nil then
			local color = colorOf(value)
			if color ~= nil then
				write(instance, saved, entry.property, color)
			else
				warnOnce(`{path}.{entry.key} is not an RGB triple (0-255); left as it was`)
			end
		end
	end
end

-- The level's mood block, or nil (no config, or no entry for this level).
local function moodOf(levelId: string): any
	local expeditions = Catalog.GetExpeditionsConfig()
	local moods = if expeditions ~= nil then expeditions.moods else nil
	return if moods ~= nil then moods[levelId] else nil
end

local function restoreMood(): ()
	local mood = state.mood
	if not mood.applied then
		return
	end
	mood.applied = false
	for property, value in mood.lighting do
		(Lighting :: any)[property] = value
	end
	table.clear(mood.lighting)
	local atmosphere = mood.atmosphere
	if atmosphere ~= nil then
		if mood.madeAtmosphere then
			atmosphere:Destroy()
		else
			for property, value in mood.atmosphereSaved do
				(atmosphere :: any)[property] = value
			end
		end
	end
	mood.atmosphere = nil
	mood.madeAtmosphere = false
	table.clear(mood.atmosphereSaved)
end

-- true when the level has a mood to apply.
local function applyMood(levelId: string): boolean
	restoreMood()
	local config = moodOf(levelId)
	if typeof(config) ~= "table" then
		return false
	end
	local mood = state.mood
	mood.applied = true
	local path = `Expeditions.json moods.{levelId}`
	if typeof(config.lighting) == "table" then
		writeBlock(
			Lighting,
			mood.lighting,
			config.lighting,
			LIGHTING_NUMBERS,
			LIGHTING_COLORS,
			path .. ".lighting"
		)
	end
	if typeof(config.atmosphere) == "table" then
		-- A place that already carries an Atmosphere has that one restyled: two under Lighting
		-- would leave the engine to pick one (Landscape.applyAtmosphere's rule).
		local existing = Lighting:FindFirstChildOfClass("Atmosphere")
		local atmosphere = existing or Instance.new("Atmosphere")
		mood.atmosphere = atmosphere
		mood.madeAtmosphere = existing == nil
		writeBlock(
			atmosphere,
			mood.atmosphereSaved,
			config.atmosphere,
			ATMOSPHERE_NUMBERS,
			ATMOSPHERE_COLORS,
			path .. ".atmosphere"
		)
		atmosphere.Parent = Lighting
	end
	return true
end

-- Mood B as the lever wants it, while dressed; the default light otherwise.
local function syncMood(): ()
	local dress = state.dress
	if dress ~= nil and not state.failed and state.moodWanted then
		applyMood(dress.level)
	else
		restoreMood()
	end
end

----------------------------------------------------------------------------------------------
-- Building
----------------------------------------------------------------------------------------------

local function childNamed(parent: Instance?, name: string): Instance?
	return if parent ~= nil then parent:FindFirstChild(name) else nil
end

local function propSetOf(layout: string): Instance?
	local setName = Theme.COMBAT_SCENERY_PROP_SETS[layout]
	if setName == nil then
		warnOnce(
			`Theme.COMBAT_SCENERY_PROP_SETS has no prop set for {layout}; its props are left out`
		)
		return nil
	end
	local set =
		childNamed(childNamed(ReplicatedStorage:FindFirstChild(NAMES.assets), NAMES.props), setName)
	if set == nil then
		warnOnce(
			`ReplicatedStorage.Assets.Props.{setName} is missing; {layout}'s props are left out`
		)
	end
	return set
end

-- One prop as the dress places it, or nil (a missing or failing piece: one warn each).
local function spawnProp(spec: Types.LevelDressProp, parent: Instance): Model?
	local set = state.propSet
	if set == nil then
		return nil
	end
	local template = set:FindFirstChild(spec.piece)
	if template == nil or not template:IsA("Model") then
		warnOnce(`prop {spec.piece} has no template; left out`)
		return nil
	end
	local ok, result = pcall(function(): Model?
		local clone = template:Clone() :: Model?
		if clone == nil then
			return nil
		end
		local base = clone:FindFirstChild(NAMES.base)
		if base ~= nil and base:IsA("BasePart") then
			clone.PrimaryPart = base
		end
		-- While the Base is the PrimaryPart, so the pivot and the scale's fixed point are both the
		-- bottom centre the dress measured from (PropFactory.Spawn's order).
		clone:PivotTo(CFrame.new(spec.x, spec.y, spec.z) * CFrame.Angles(0, math.rad(spec.yaw), 0))
		if spec.scale ~= 1 and spec.scale > 0 then
			clone:ScaleTo(spec.scale)
		end
		if base ~= nil then
			base:Destroy()
		end
		seal(clone)
		clone.Parent = parent
		return clone
	end)
	if not ok or result == nil then
		warnOnce(`prop {spec.piece} could not be placed ({tostring(result)}); left out`)
		return nil
	end
	return result
end

local function spawnFire(effect: Types.LevelDressEffect, parent: Instance): ()
	local part = Instance.new("Part")
	part.Name = "Fire"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Theme.COMBAT_SCENERY_FIRE_SIZE
	part.Position = Vector3.new(effect.x, effect.y, effect.z)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = Theme.COMBAT_SCENERY_FIRE_RATE
	emitter.Lifetime = NumberRange.new(
		Theme.COMBAT_SCENERY_FIRE_LIFETIME_MIN,
		Theme.COMBAT_SCENERY_FIRE_LIFETIME_MAX
	)
	emitter.Speed =
		NumberRange.new(Theme.COMBAT_SCENERY_FIRE_SPEED_MIN, Theme.COMBAT_SCENERY_FIRE_SPEED_MAX)
	emitter.SpreadAngle =
		Vector2.new(Theme.COMBAT_SCENERY_FIRE_SPREAD, Theme.COMBAT_SCENERY_FIRE_SPREAD)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Size = NumberSequence.new(Theme.COMBAT_SCENERY_FIRE_PARTICLE_SIZE, 0)
	emitter.Color =
		ColorSequence.new(Theme.COMBAT_SCENERY_FIRE_COLOR_HOT, Theme.COMBAT_SCENERY_FIRE_COLOR_COOL)
	emitter.LightEmission = Theme.COMBAT_SCENERY_FIRE_LIGHT_EMISSION
	emitter.Parent = part
	local light = Instance.new("PointLight")
	light.Color = Theme.COMBAT_SCENERY_FIRE_LIGHT_COLOR
	light.Range = Theme.COMBAT_SCENERY_FIRE_LIGHT_RANGE
	light.Brightness = Theme.COMBAT_SCENERY_FIRE_LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Parent = part
	part.Parent = parent
end

-- The `with` props waiting on `name`, built when the level holds a child of that name and none
-- stands yet.
local function raiseWith(name: string): ()
	local folder = state.folder
	local specs = state.withSpecs[name]
	local level = state.level
	if folder == nil or specs == nil or state.withClones[name] ~= nil or level == nil then
		return
	end
	if level:FindFirstChild(name) == nil then
		return
	end
	local clones: { Model } = {}
	for _, spec in specs do
		local clone = spawnProp(spec, folder)
		if clone ~= nil then
			table.insert(clones, clone)
		end
	end
	state.withClones[name] = clones
end

local function dropWith(name: string): ()
	local clones = state.withClones[name]
	if clones == nil then
		return
	end
	local level = state.level
	if level ~= nil and level:FindFirstChild(name) ~= nil then
		return -- another child of that name still stands
	end
	for _, clone in clones do
		clone:Destroy()
	end
	state.withClones[name] = nil
end

-- Everything this client drew for a level, gone; the light and the local writes put back.
local function teardown(): ()
	local folder = state.folder
	state.folder = nil
	if folder ~= nil then
		folder:Destroy()
	end
	state.dress = nil
	state.built = false
	state.failed = false
	state.propSet = nil
	table.clear(state.withSpecs)
	table.clear(state.withClones)
	restorePainted()
	restoreMood()
end

-- The server dressed the level and this client cannot: no collision may stay invisible.
local function fail(reason: string): ()
	warnOnce(`the level is grey on this client: {reason}`)
	teardown()
	state.failed = true
	applyView()
end

-- The steps of a build, in order (2.3): the meshes by group, the props, the fires.
local function jobsOf(dress: Types.LevelDress): { Job }
	local jobs: { Job } = {}
	local rank: { [string]: number } = {}
	for index, group in GROUP_ORDER do
		rank[group] = index
	end
	local meshes = table.clone(dress.meshes)
	-- Stable: the dress's own order inside a group.
	local position: { [Types.LevelDressMesh]: number } = {}
	for index, mesh in meshes do
		position[mesh] = index
	end
	table.sort(meshes, function(a: Types.LevelDressMesh, b: Types.LevelDressMesh): boolean
		local ra = rank[a.group] or #GROUP_ORDER + 1
		local rb = rank[b.group] or #GROUP_ORDER + 1
		if ra ~= rb then
			return ra < rb
		end
		return position[a] < position[b]
	end)
	for _, mesh in meshes do
		table.insert(jobs, { kind = "mesh", mesh = mesh })
	end
	for _, prop in dress.props do
		table.insert(jobs, { kind = "prop", prop = prop })
	end
	if not Theme.lowEndDevice then
		for _, effect in dress.effects do
			if effect.kind == NAMES.fire then
				table.insert(jobs, { kind = "fire", effect = effect })
			end
		end
	end
	return jobs
end

-- One step; false and why when a mesh could not be built (the whole scenery then goes).
local function runJob(job: Job, templates: Instance, folder: Folder): (boolean, string?)
	local mesh = job.mesh
	if mesh ~= nil then
		local template = templates:FindFirstChild(mesh.name)
		if template == nil then
			return false, `mesh {mesh.name} has no template`
		end
		local ok, problem = pcall(function(): string?
			local clone = template:Clone() :: Instance? -- nil when the template is not Archivable
			if clone == nil then
				return "its template cannot be cloned"
			end
			seal(clone)
			clone.Parent = folder
			return nil
		end)
		if not ok then
			return false, `mesh {mesh.name} failed ({tostring(problem)})`
		end
		if problem ~= nil then
			return false, `mesh {mesh.name}: {problem}`
		end
		return true, nil
	end
	local prop = job.prop
	if prop ~= nil then
		local with = prop.with
		if with ~= nil then
			local specs = state.withSpecs[with]
			if specs == nil then
				specs = {}
				state.withSpecs[with] = specs
			end
			table.insert(specs, prop)
		else
			spawnProp(prop, folder)
		end
		return true, nil
	end
	local effect = job.effect
	if effect ~= nil then
		spawnFire(effect, folder)
	end
	return true, nil
end

-- The build's own thread. Stops at the first step of a generation it no longer is.
local function build(generation: number, dress: Types.LevelDress, folder: Folder): ()
	if not game:IsLoaded() then
		game.Loaded:Wait() -- the templates are replicated with the place
	end
	if generation ~= state.generation then
		return
	end
	local templates = childNamed(
		childNamed(ReplicatedStorage:FindFirstChild(NAMES.assets), NAMES.levels),
		dress.layout
	)
	if templates == nil then
		fail(`ReplicatedStorage.Assets.Levels.{dress.layout} is missing`)
		return
	end
	state.propSet = propSetOf(dress.layout)
	local perFrame = math.max(1, math.floor(Theme.COMBAT_SCENERY_CLONES_PER_FRAME))
	local done = 0
	local started = os.clock()
	for _, job in jobsOf(dress) do
		local ok, problem = runJob(job, templates, folder)
		if not ok then
			DrawClock.Add(os.clock() - started)
			fail(problem or "a mesh failed")
			return
		end
		done += 1
		if done % perFrame == 0 then
			DrawClock.Add(os.clock() - started)
			task.wait()
			if generation ~= state.generation then
				return
			end
			started = os.clock()
		end
	end
	-- The `with` props whose block already stands; the rest wait on ChildAdded.
	state.built = true
	for name in state.withSpecs do
		raiseWith(name)
	end
	DrawClock.Add(os.clock() - started)
end

-- The server's word changed (or was first read): clear, and build when it says dressed.
local function evaluate(): ()
	local level = state.level
	if level == nil then
		return
	end
	local name = level:GetAttribute(NAMES.dress)
	local hash = level:GetAttribute(NAMES.dressHash)
	local key = if typeof(name) == "string" then `{name}\0{tostring(hash)}` else ""
	if key == state.builtKey then
		return
	end
	state.builtKey = key
	state.generation += 1
	teardown()
	if typeof(name) ~= "string" then
		applyView()
		return -- not dressed: the level as built, nothing hidden
	end
	if typeof(hash) ~= "string" then
		-- Build sets the hash right after the name; if it never comes, nothing stays invisible.
		fail(`Workspace.Level has Dress "{name}" but no DressHash`)
		return
	end
	local dress = Catalog.GetLevelDress(name)
	if dress == nil then
		fail(`Config/LevelDress/{name} is missing`)
		return
	end
	if dress.planHash ~= hash then
		fail(`Config/LevelDress/{name} has plan hash {dress.planHash}, the server dressed {hash}`)
		return
	end
	if dress.frame ~= NAMES.frame then
		fail(`Config/LevelDress/{name} has frame "{dress.frame}", not "{NAMES.frame}"`)
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = NAMES.scenery
	state.folder = folder
	state.dress = dress
	syncMood()
	applyView() -- parents the folder unless the view is grey
	task.spawn(build, state.generation, dress, folder)
end

local function onLevelChildAdded(child: Instance): ()
	if state.built and state.withSpecs[child.Name] ~= nil then
		raiseWith(child.Name)
	end
	if state.failed or (state.dress ~= nil and state.view == "grey") then
		showSkinned(child)
	elseif state.dress ~= nil and state.view == "walls" then
		showWall(child)
	end
end

local function onLevelChildRemoved(child: Instance): ()
	if state.withClones[child.Name] ~= nil then
		dropWith(child.Name)
	end
	if child:IsA("BasePart") then
		state.painted[child] = nil
	end
end

local function attachLevel(level: Instance): ()
	if state.level ~= nil or not level:IsA("Folder") then
		return
	end
	state.level = level :: Folder
	local function changed(): ()
		-- Deferred: Build sets the two attributes one after the other, and both are read together.
		task.defer(evaluate)
	end
	table.insert(
		state.levelConnections,
		level:GetAttributeChangedSignal(NAMES.dress):Connect(changed)
	)
	table.insert(
		state.levelConnections,
		level:GetAttributeChangedSignal(NAMES.dressHash):Connect(changed)
	)
	table.insert(state.levelConnections, level.ChildAdded:Connect(onLevelChildAdded))
	table.insert(state.levelConnections, level.ChildRemoved:Connect(onLevelChildRemoved))
	table.insert(
		state.levelConnections,
		level.AncestryChanged:Connect(function(_: Instance, parent: Instance?)
			if parent == nil then
				LevelScenery.Detach()
			end
		end)
	)
	evaluate() -- a late join: the level may already be dressed
end

----------------------------------------------------------------------------------------------
-- Studio levers
----------------------------------------------------------------------------------------------

local function cycleView(): ()
	if state.dress == nil then
		say(TEXT.notDressed)
		return
	end
	state.view = NEXT_VIEW[state.view]
	applyView()
	say(TEXT[state.view])
end

local function toggleMood(): ()
	local dress = state.dress
	if dress == nil then
		say(TEXT.notDressed)
		return
	end
	if moodOf(dress.level) == nil then
		say(TEXT.noMood)
		return
	end
	state.moodWanted = not state.moodWanted
	syncMood()
	say(if state.moodWanted then TEXT.moodOn else TEXT.moodOff)
end

local function onKey(input: InputObject, processed: boolean): ()
	if processed or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if input.KeyCode == KEYS.scenery then
		cycleView()
	elseif input.KeyCode == KEYS.mood then
		toggleMood()
	end
end

----------------------------------------------------------------------------------------------
-- Controller
----------------------------------------------------------------------------------------------

function LevelScenery.Init(): () end

function LevelScenery.Start(): ()
	if RunService:IsStudio() then
		table.insert(state.connections, UserInputService.InputBegan:Connect(onKey))
	end
	local level = Workspace:FindFirstChild(NAMES.level)
	if level ~= nil then
		attachLevel(level)
	end
	table.insert(
		state.connections,
		Workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == NAMES.level then
				attachLevel(child)
			end
		end)
	)
end

-- The host's toast for what a Studio lever did (nil = printed to the Output).
function LevelScenery.SetToastHandler(handler: ((string) -> ())?): ()
	state.toast = handler
end

-- The level folder went away: everything drawn for it goes, the light comes back.
function LevelScenery.Detach(): ()
	for _, connection in state.levelConnections do
		connection:Disconnect()
	end
	table.clear(state.levelConnections)
	state.generation += 1
	state.builtKey = ""
	teardown()
	state.level = nil
end

function LevelScenery.Destroy(): ()
	LevelScenery.Detach()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	state.toast = nil
end

return LevelScenery
