--!strict
-- The world of the dungeon place (docs/INTERFACES.md "L1 contracts" → "Server modules" → "A —
-- the world", rulings 18, 19, 29 and 31): the lobby camp, built once at boot, and the one level
-- a run is played in, built from its layout when the run starts and removed when it ends. Both
-- are plain anchored Parts in the looks of Expeditions.json: no mesh, no upload.
--
-- This service owns every Instance of the lobby and of the level and nothing else. It moves no
-- body and knows nothing of the run: WaveService tells it which camp closes and which is
-- cleared (SetCamp). It does no arithmetic either: LevelGeometry says which Parts a layout
-- becomes and where each stands, and the harness tests that list. What is left here, and can
-- only be checked in Studio, is turning a piece into a Part.
--
-- A camp's invisible wall is in BarrierGroups' collision group, so only characters meet it;
-- the camera and every ray pass. Build and Clear never yield. Build runs in the remote's own
-- thread; WaveService defers Clear out of its tick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local BarrierGroups = require(script.Parent:WaitForChild("BarrierGroups"))
local LevelGeometry = require(script.Parent:WaitForChild("LevelGeometry"))

type Looks = { [string]: Types.LevelLook }
-- What SetCamp changes of one camp.
type CampParts = {
	gates: { BasePart },
	-- A closed gate shows at its look's transparency.
	gateTransparency: number,
	barriers: { BasePart },
	checkpoint: BasePart?,
}

local CONST = {
	LOBBY_FOLDER = "Lobby",
	LEVEL_FOLDER = "Level",
	-- As ArenaService's LobbySpawn was: invisible and walked through, so its size only says
	-- where the engine's own respawn puts a body.
	SPAWN_NAME = "LobbySpawn",
	SPAWN_SIZE = Vector3.new(6, 1, 6),
	-- A block's text goes on its four side faces.
	TEXT_FACES = table.freeze({
		Enum.NormalId.Front,
		Enum.NormalId.Back,
		Enum.NormalId.Left,
		Enum.NormalId.Right,
	}),
}

local state = {
	lobbyFolder = nil :: Folder?,
	levelFolder = nil :: Folder?,
	lobbyBuilt = false,
	lobbySpawn = nil :: SpawnLocation?,
	-- Feet points of the lobby, handed out round-robin.
	lobbyPoints = {} :: { Vector3 },
	lobbyCursor = 0,
	lobbyBounds = nil :: LevelGeometry.Bounds?,
	built = false,
	camps = {} :: { [string]: CampParts },
	-- The looks the level was built in (SetCamp recolours a checkpoint from them).
	looks = nil :: Looks?,
	warned = {} :: { [string]: boolean },
}

local LevelService = {}

local function warnOnce(key: string, message: string): ()
	if state.warned[key] then
		return
	end
	state.warned[key] = true
	warn(message)
end

local function colorOf(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

-- nil for a name the engine does not know: the Part then keeps the material it has.
local function materialOf(name: string): Enum.Material?
	local material = (Enum.Material :: any)[name]
	if typeof(material) == "EnumItem" then
		return material :: Enum.Material
	end
	warnOnce(`material:{name}`, `[LevelService] unknown material "{name}"; left as it was`)
	return nil
end

-- A missing look leaves the Part as the engine made it: a placeholder, never an error.
local function applyLook(part: BasePart, looks: Looks?, name: string): ()
	local look = if looks ~= nil then looks[name] else nil
	if look == nil then
		warnOnce(`look:{name}`, `[LevelService] Expeditions.json has no look "{name}"`)
		return
	end
	local material = materialOf(look.material)
	if material ~= nil then
		part.Material = material
	end
	part.Color = colorOf(look.color)
	part.Transparency = look.transparency or 0
end

-- A config size, { x, y, z } studs. nil when the key is absent or is not three positive
-- numbers: no size lives in code, so the Part it sizes is then not built.
local function sizeOf(value: { number }?): LevelGeometry.Size?
	if value == nil then
		return nil
	end
	local sx, sy, sz = value[1], value[2], value[3]
	local function positive(number: number?): boolean
		return number ~= nil and number > 0 and number < math.huge
	end
	if positive(sx) and positive(sy) and positive(sz) then
		return { sx = sx, sy = sy, sz = sz }
	end
	return nil
end

-- What LevelGeometry needs beyond the layout, all of it from the config: the fence's thickness
-- and a checkpoint marker's size (Combat.json levels), a secret's sign's size (Expeditions.json
-- sign).
local function sizesOf(
	expeditions: Types.ExpeditionsConfig?,
	rules: Types.CombatLevelsConfig?
): LevelGeometry.Sizes
	return {
		fence = if rules ~= nil then rules.fenceThickness else 0,
		checkpoint = sizeOf(if rules ~= nil then rules.checkpointSize else nil),
		sign = sizeOf(if expeditions ~= nil then expeditions.sign.size else nil),
	}
end

-- Says once which Parts a layout asks for and the config gives no size for.
local function warnUnsized(layout: Types.LevelLayout, sizes: LevelGeometry.Sizes): ()
	if sizes.checkpoint == nil then
		-- A lobby file may leave `camps` out.
		local camps: { Types.LevelCamp } = layout.camps or {}
		for _, camp in camps do
			if camp.checkpoint ~= nil then
				warnOnce(
					"size:checkpoint",
					"[LevelService] Combat.json levels.checkpointSize is missing or not three "
						.. "positive numbers; no checkpoint marker is built"
				)
				break
			end
		end
	end
	if sizes.sign == nil and layout.secrets ~= nil and #layout.secrets > 0 then
		warnOnce(
			"size:sign",
			"[LevelService] Expeditions.json sign.size is missing or not three positive "
				.. "numbers; no secret's sign is built"
		)
	end
end

-- LevelGeometry.Pieces behind a pcall: a layout file with a key of the wrong type must refuse
-- the level, not throw in the remote's thread.
local function piecesOf(
	layout: Types.LevelLayout,
	sizes: LevelGeometry.Sizes,
	maxParts: number
): ({ LevelGeometry.Piece }?, string?)
	local ok, pieces, problem = pcall(LevelGeometry.Pieces, layout, sizes, maxParts)
	if not ok then
		return nil, `the layout could not be read: {pieces}`
	end
	return pieces :: { LevelGeometry.Piece }?, problem :: string?
end

local function addText(part: BasePart, text: string, expeditions: Types.ExpeditionsConfig): ()
	local sign = expeditions.sign
	for _, face in CONST.TEXT_FACES do
		local gui = Instance.new("SurfaceGui")
		gui.Name = `Text_{face.Name}`
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		if sign.pixelsPerStud > 0 then
			gui.PixelsPerStud = sign.pixelsPerStud
		end
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = colorOf(sign.textColor)
		label.TextScaled = true
		label.TextWrapped = true
		label.Parent = gui
		gui.Parent = part
	end
end

local function campOf(camps: { [string]: CampParts }, id: string): CampParts
	local camp = camps[id]
	if camp == nil then
		camp = { gates = {}, gateTransparency = 0, barriers = {}, checkpoint = nil }
		camps[id] = camp
	end
	return camp
end

-- A gate stands open as built and between fights: not there for a body, a ray or the eye.
local function setGate(gate: BasePart, closed: boolean, shown: number): ()
	gate.Transparency = if closed then shown else 1
	gate.CanCollide = closed
	gate.CanQuery = closed
	gate.CastShadow = closed
end

-- Every piece as a Part under `folder`. Returns what SetCamp will need of each camp.
local function construct(
	folder: Folder,
	pieces: { LevelGeometry.Piece },
	expeditions: Types.ExpeditionsConfig?
): { [string]: CampParts }
	local looks: Looks? = if expeditions ~= nil then expeditions.looks else nil
	local camps: { [string]: CampParts } = {}
	local walls = BarrierGroups.Ensure()
	for _, piece in pieces do
		local isBarrier = piece.role == "barrier"
		if isBarrier and not walls then
			-- The engine refused the groups (BarrierGroups said so once): a wall in the Default
			-- group would stop the camera and every shot, so there is none.
			continue
		end
		local box = piece.box
		local part = Instance.new("Part")
		part.Name = piece.name
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(box.sx, box.sy, box.sz)
		part.Position = Vector3.new(box.x, box.y, box.z)
		local look = piece.look
		if look ~= nil then
			applyLook(part, looks, look)
		end
		local ownMaterial = piece.material
		if ownMaterial ~= nil then
			local material = materialOf(ownMaterial)
			if material ~= nil then
				part.Material = material
			end
		end
		local ownColor = piece.color
		if ownColor ~= nil then
			part.Color = colorOf(ownColor)
		end
		if not piece.collide then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
		local campId = piece.camp
		if isBarrier then
			-- The group is what lets the camera and rays through, never CanQuery. Off as built.
			part.CollisionGroup = BarrierGroups.BARRIER
			part.Transparency = 1
			part.CanTouch = false
			part.CastShadow = false
			part.CanCollide = false
			if campId ~= nil then
				table.insert(campOf(camps, campId).barriers, part)
			end
		elseif piece.role == "gate" then
			local shown = part.Transparency
			setGate(part, false, shown)
			if campId ~= nil then
				local camp = campOf(camps, campId)
				camp.gateTransparency = shown
				table.insert(camp.gates, part)
			end
		elseif piece.role == "checkpoint" and campId ~= nil then
			campOf(camps, campId).checkpoint = part
		end
		local text = piece.text
		if text ~= nil and text ~= "" and expeditions ~= nil then
			addText(part, text, expeditions)
		end
		part.Parent = folder
	end
	return camps
end

local function newFolder(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	return folder
end

-- The two folders (Workspace.Lobby, Workspace.Level) and the wall's collision groups.
-- Idempotent. Mission mode only: the range builds its own arena through ArenaService.
function LevelService.Init(): ()
	if state.lobbyFolder ~= nil then
		return
	end
	state.lobbyFolder = newFolder(CONST.LOBBY_FOLDER)
	state.levelFolder = newFolder(CONST.LEVEL_FOLDER)
	BarrierGroups.Ensure()
end

-- The lobby's layout: the file Expeditions.json names, else the stand-in pad (one warn).
local function lobbyLayout(expeditions: Types.ExpeditionsConfig?): Types.LevelLayout
	local name = if expeditions ~= nil then expeditions.lobby.layout else nil
	local layout = if name ~= nil then Catalog.GetLevelLayout(name) else nil
	if layout ~= nil and layout.arena == nil and layout.start ~= nil then
		return layout
	end
	warn(`[LevelService] no lobby layout (Layouts/Levels/{name or "?"}); using the bare pad`)
	return LevelGeometry.BareLobby()
end

-- Once, after Init: the lobby camp and its SpawnLocation. Never yields.
function LevelService.BuildLobby(): ()
	local folder = state.lobbyFolder
	if folder == nil then
		warn("[LevelService] BuildLobby before Init; no lobby was built")
		return
	end
	if state.lobbyBuilt then
		return
	end
	state.lobbyBuilt = true
	local expeditions = Catalog.GetExpeditionsConfig()
	local combat = Catalog.GetCombatConfig()
	local rules = if combat ~= nil then combat.levels else nil
	local sizes = sizesOf(expeditions, rules)
	local maxParts = if rules ~= nil then rules.maxParts else math.huge
	local layout = lobbyLayout(expeditions)
	local pieces, problem = piecesOf(layout, sizes, maxParts)
	if pieces == nil then
		warn(`[LevelService] the lobby layout cannot be built ({problem}); using the bare pad`)
		layout = LevelGeometry.BareLobby()
		pieces = piecesOf(layout, sizes, math.huge)
	end
	if pieces ~= nil then
		construct(folder, pieces, expeditions)
	end
	warnUnsized(layout, sizes)
	state.lobbyBounds = LevelGeometry.Bounds(layout)

	local start = layout.start
	local points: { Vector3 } = {}
	local spawns: { { x: number, y: number, z: number } } = layout.spawns or {}
	for _, point in spawns do
		table.insert(points, Vector3.new(point.x, point.y, point.z))
	end
	if #points == 0 then
		table.insert(points, Vector3.new(start.x, start.y, start.z))
	end
	state.lobbyPoints = points

	-- A real SpawnLocation: Roblox respawns a dead player at Player.RespawnLocation, which
	-- only accepts one. It rests on the lobby's floor at the layout's start.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = CONST.SPAWN_NAME
	spawn.Size = CONST.SPAWN_SIZE
	spawn.Position = Vector3.new(start.x, start.y + CONST.SPAWN_SIZE.Y / 2, start.z)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = folder
	state.lobbySpawn = spawn
end

-- nil before BuildLobby.
function LevelService.LobbySpawn(): SpawnLocation?
	return state.lobbySpawn
end

-- Where a body stands in the lobby (feet): the layout's `spawns` in turn, so a party does not
-- arrive on one spot. Before BuildLobby it is the stand-in pad's start.
function LevelService.LobbyPoint(): Vector3
	local points = state.lobbyPoints
	if #points == 0 then
		local start = LevelGeometry.BareLobby().start
		return Vector3.new(start.x, start.y, start.z)
	end
	state.lobbyCursor = state.lobbyCursor % #points + 1
	return points[state.lobbyCursor]
end

-- The box of the lobby's blocks (the rescue judges a waiting or lobby body against it).
function LevelService.LobbyBounds(): LevelGeometry.Bounds
	return state.lobbyBounds or LevelGeometry.Bounds(LevelGeometry.BareLobby())
end

-- Builds `layout` under Workspace.Level, every camp open. false with one warn, and nothing
-- built, when a level is already standing, before Init, or when LevelGeometry.Pieces refuses
-- the layout (it still names an arena, gates with no fence, a bad size, over levels.maxParts).
-- Never yields.
function LevelService.Build(
	layout: Types.LevelLayout,
	expeditions: Types.ExpeditionsConfig,
	rules: Types.CombatLevelsConfig
): boolean
	local folder = state.levelFolder
	if folder == nil then
		warn("[LevelService] Build before Init; nothing was built")
		return false
	end
	if state.built then
		warn("[LevelService] a level is already built; Clear it first")
		return false
	end
	local sizes = sizesOf(expeditions, rules)
	local pieces, problem = piecesOf(layout, sizes, rules.maxParts)
	if pieces == nil then
		warn(`[LevelService] the level was not built: {problem}`)
		return false
	end
	warnUnsized(layout, sizes)
	state.camps = construct(folder, pieces, expeditions)
	state.looks = expeditions.looks
	state.built = true
	return true
end

-- Destroys every Instance of the level. Idempotent; never yields.
function LevelService.Clear(): ()
	local folder = state.levelFolder
	if folder ~= nil then
		folder:ClearAllChildren()
	end
	state.camps = {}
	state.looks = nil
	state.built = false
end

function LevelService.IsBuilt(): boolean
	return state.built
end

-- "open" (as built): the gates are not there and the invisible wall is off. "closed": the gates
-- stand, visible and solid, and the wall holds every character in. "cleared": as open, and the
-- checkpoint marker takes the look `checkpointDone`. An unknown camp or state changes nothing.
function LevelService.SetCamp(zoneId: string, campState: string): ()
	local camp = state.camps[zoneId]
	if camp == nil then
		warn(`[LevelService] SetCamp: no camp "{zoneId}" in the level that is built`)
		return
	end
	if campState ~= "open" and campState ~= "closed" and campState ~= "cleared" then
		warn(`[LevelService] SetCamp: unknown state "{campState}" for camp {zoneId}`)
		return
	end
	local closed = campState == "closed"
	for _, gate in camp.gates do
		setGate(gate, closed, camp.gateTransparency)
	end
	for _, barrier in camp.barriers do
		barrier.CanCollide = closed
	end
	local checkpoint = camp.checkpoint
	if checkpoint ~= nil and not closed then
		applyLook(
			checkpoint,
			state.looks,
			if campState == "cleared" then "checkpointDone" else "checkpoint"
		)
	end
end

return LevelService
