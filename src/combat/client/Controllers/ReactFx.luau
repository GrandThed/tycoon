--!strict
-- The world's reactions on the client (docs/prompts/l2-w2-contract.md, L2-34 and L2-35). The
-- server decides every burn (LevelService.React); this shows it happening. CombatUIController
-- mounts it in a mission and hands it the `react` CombatFx events.
--
--  * Heating: a reactive block's Part carries `React` (its element, set when the level is built)
--    and the server writes its `Heat` (0 to 1) as strikes of that element land on it. Such a Part
--    darkens toward charcoal by it (a client-local tint) and throws embers whose rate follows it. A low-end device keeps a
--    few embers (they say how close the burn is), never the full rate.
--  * Burnt (CombatFx `react`, event "burnt", the box as it stood): the server has destroyed the
--    Part; here a flash of the box, a local ghost of it that shrinks away and a puff of smoke. A
--    low-end device gets the ghost's fade alone and no smoke (spec section 10); the gate is never
--    Theme.reducedMotion, which every touch device has (the living-city lesson), and the shrink is
--    the one-off cue that the way is open. Every piece is anchored, never collides, is never
--    queried and is gone within Theme.REACT_SMOKE_SECONDS.
--  * The Parts it watches are also the targets of touch auto-fire's stream (ForEachPart, c-M1).
--
-- L2 Wave 3 (docs/prompts/l2-w3-contract.md, L2-53 to L2-56): the water's ice cells.
--  * An ice cell is a Part LevelService built with the level, invisible and walk-through, whose
--    `Ice` attribute turns true when the server freezes it (it then shows it and makes it
--    collide). ForEachIce hands the unfrozen ones to touch auto-swing (InputController) and to
--    the predicted ghost; nothing here decides a freeze.
--  * Fix round c-m1: touch auto-swing asks on every frame an ice family is held, anywhere in the
--    level, so nothing it reads crosses into the engine. A cell's box is read once when it is
--    adopted (cells are anchored and never move), the unfrozen cells are a list kept by each
--    cell's `Ice` signal, and ForEachIce answers "no water within reach" from one rectangle (the
--    cells' centres) and one band (their tops) before any cell is looked at, then hands on only
--    the cells within the swing's reach and band. It stops at the first cell its callback takes
--    (c-s2).
--  * PredictFreeze: on the local player's own ice swing, a ghost of ice (local, translucent,
--    never colliding or queried) on every unfrozen cell the server's own rule names
--    (WorldReact.Chills with Combat.json levels.react.ice), from the press frame. The real cell
--    replaces it when its `Ice` turns true. Fix round c-m2: otherwise the swing's answer decides
--    (ghosts are held by the swing's seq): a refusal takes them at once (RefuseFreeze), the
--    strike that answers the seq lets them stand Theme.COMBAT_FROST_GHOST_GRACE_SECONDS more for
--    `Ice` to replicate (AnswerFreeze: the server broadcasts the strike before it freezes), and
--    a swing never answered loses them after Theme.COMBAT_RANGE_SWING_ANSWER_SECONDS, the time
--    after which input counts it dropped. A cell two swings named keeps its ghost while either
--    holds it. A ghost is information, so it draws on every device. The second fix round's Q5: no
--    ghost for a swing made in the air (its strike's `airborne`, Chills) nor on a cell a player's
--    body stands in (WorldReact.Holds over Bodies, with levels.react.ice's sink): the server
--    freezes neither.
--  * Frozen (CombatFx `react`, event "frozen", the cell's box): a pale glint over the cell and a
--    burst of frost motes; a low-end device gets the glint alone.
--
-- No sound (combat has none).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local WorldReact = require(sharedFolder:WaitForChild("WorldReact"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))

type Heated = {
	part: BasePart,
	color: Color3,
	embers: ParticleEmitter?,
	connection: RBXScriptConnection,
}

-- L2-53: one ice cell of the level as adopted. Its box, frame and size are read once (c-m1), with
-- its centre in plan and its top for ForEachIce's quick test; `open` is its index in state.open
-- while its `Ice` is false, else 0.
type IceCell = {
	part: BasePart,
	box: WorldReact.Box,
	frame: CFrame,
	size: Vector3,
	x: number,
	z: number,
	top: number,
	open: number,
	connection: RBXScriptConnection,
}

-- A predicted ghost on one ice cell and the swings (by seq) that hold it (c-m2).
type Ghost = {
	part: Part,
	holders: { [number]: true },
}

-- One predicted swing: the cells it put ghosts on, and whether its strike has come.
type Prediction = {
	cells: { BasePart },
	answered: boolean,
}

-- What ForEachIce tests first: the rectangle of the cells' centres and the band of their tops.
type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number, low: number, high: number }

-- Workspace.Level (LevelService.LEVEL_FOLDER) and the attributes the server writes. An ice
-- cell's is WorldReact.ICE_ATTRIBUTE, named only there (s-s3).
local LEVEL_FOLDER = "Level"
local HEAT_ATTRIBUTE = "Heat"
local REACT_ATTRIBUTE = "React"
local FX_FOLDER = "ReactFx"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MIN_SIZE = 0.05
-- Studs ForEachIce's quick test is wider than Chills' own reach and band, so a float rounding
-- at an edge can never skip a cell Chills would name (the test only spares Chills the rest).
local NEAR_SLACK = 0.01

local ReactFx = {}

local state = {
	mounted = false,
	parts = {} :: { [BasePart]: Heated },
	-- L2-53: every ice cell of the level, frozen or not, and the unfrozen ones as a list (c-m1).
	ice = {} :: { [BasePart]: IceCell },
	open = {} :: { IceCell },
	-- nil until asked after a cell came or went (ForEachIce rebuilds it then).
	bounds = nil :: Bounds?,
	ghosts = {} :: { [BasePart]: Ghost },
	predictions = {} :: { [number]: Prediction },
	connections = {} :: { RBXScriptConnection },
	folder = nil :: Folder?,
}

local function fxFolder(): Folder
	local folder = state.folder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = FX_FOLDER
	made.Parent = Workspace
	state.folder = made
	return made
end

local function newEmbers(part: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "ReactEmbers"
	emitter.Texture = SPARK_TEXTURE
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Color = ColorSequence.new(Theme.REACT_EMBER_COLOR)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new(0.3, 0)
	emitter.Transparency = NumberSequence.new(0, 0.6)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(2, 5)
	emitter.Acceleration = Vector3.new(0, 6, 0)
	emitter.Rate = 0
	emitter.Parent = part
	return emitter
end

local function paintHeat(heated: Heated): ()
	local value = heated.part:GetAttribute(HEAT_ATTRIBUTE)
	local heat = if typeof(value) == "number" then math.clamp(value, 0, 1) else 0
	heated.part.Color = heated.color:Lerp(Theme.REACT_CHAR_COLOR, heat)
	if heat <= 0 then
		local embers = heated.embers
		if embers ~= nil then
			embers.Rate = 0
		end
		return
	end
	local embers = heated.embers or newEmbers(heated.part)
	heated.embers = embers
	embers.Rate = heat
		* (if Theme.lowEndDevice then Theme.REACT_EMBER_LOW_END_RATE else Theme.REACT_EMBER_RATE)
end

local function dropGhost(cell: BasePart): ()
	local ghost = state.ghosts[cell]
	if ghost == nil then
		return
	end
	state.ghosts[cell] = nil
	ghost.part:Destroy()
end

-- state.open is unordered: a cell leaves it by taking the last one's place.
local function openCell(cell: IceCell): ()
	if cell.open ~= 0 then
		return
	end
	table.insert(state.open, cell)
	cell.open = #state.open
end

local function closeCell(cell: IceCell): ()
	local at = cell.open
	if at == 0 then
		return
	end
	local open = state.open
	local last = open[#open]
	open[at] = last
	last.open = at
	open[#open] = nil
	cell.open = 0
end

-- A cell's `Ice` changed: false keeps it open; true (the server froze it) closes it, and the
-- real cell now stands where its ghost was.
local function iceChanged(cell: IceCell): ()
	if cell.part:GetAttribute(WorldReact.ICE_ATTRIBUTE) == false then
		openCell(cell)
		return
	end
	closeCell(cell)
	dropGhost(cell.part)
end

local function adoptIce(part: BasePart): ()
	if state.ice[part] ~= nil then
		return
	end
	local position, size = part.Position, part.Size
	local cell: IceCell = {
		part = part,
		box = WorldReact.BoxOf(position, size),
		frame = part.CFrame,
		size = size,
		x = position.X,
		z = position.Z,
		top = position.Y + size.Y / 2,
		open = 0,
		connection = part:GetAttributeChangedSignal(WorldReact.ICE_ATTRIBUTE):Connect(function()
			local entry = state.ice[part]
			if entry ~= nil then
				iceChanged(entry)
			end
		end),
	}
	state.ice[part] = cell
	state.bounds = nil
	if part:GetAttribute(WorldReact.ICE_ATTRIBUTE) == false then
		openCell(cell)
	end
end

-- Only the reactive Parts and the ice cells are watched (LevelService sets `React` or `Ice`
-- before parenting them).
local function adopt(child: Instance): ()
	if not child:IsA("BasePart") then
		return
	end
	if typeof(child:GetAttribute(WorldReact.ICE_ATTRIBUTE)) == "boolean" then
		adoptIce(child)
		return
	end
	if state.parts[child] ~= nil or child:GetAttribute(REACT_ATTRIBUTE) == nil then
		return
	end
	local part = child
	local heated: Heated = {
		part = part,
		color = part.Color,
		embers = nil,
		connection = part:GetAttributeChangedSignal(HEAT_ATTRIBUTE):Connect(function()
			local entry = state.parts[part]
			if entry ~= nil then
				paintHeat(entry)
			end
		end),
	}
	state.parts[part] = heated
	if part:GetAttribute(HEAT_ATTRIBUTE) ~= nil then
		paintHeat(heated)
	end
end

local function forget(child: Instance): ()
	if not child:IsA("BasePart") then
		return
	end
	local cell = state.ice[child]
	if cell ~= nil then
		cell.connection:Disconnect()
		closeCell(cell)
		state.ice[child] = nil
		state.bounds = nil
	end
	dropGhost(child)
	local heated = state.parts[child]
	if heated ~= nil then
		heated.connection:Disconnect()
		state.parts[child] = nil
	end
end

local function watchLevel(): ()
	local folder = Workspace:WaitForChild(LEVEL_FOLDER, Theme.COMBAT_REMOTE_WAIT_SECONDS)
	if folder == nil then
		warn("[ReactFx] Workspace.Level never came: brambles show no heat")
		return
	end
	table.insert(state.connections, folder.ChildAdded:Connect(adopt))
	table.insert(state.connections, folder.ChildRemoved:Connect(forget))
	for _, child in folder:GetChildren() do
		adopt(child)
	end
end

local function fxPart(name: string, cframe: CFrame, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	return part
end

local function burnt(centre: Vector3, size: Vector3): ()
	local folder = fxFolder()
	local frame = CFrame.new(centre)
	local flash = fxPart("ReactFlash", frame, size + Vector3.one * 0.4, Theme.REACT_FLASH_COLOR)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.2
	flash.Parent = folder
	TweenService:Create(flash, TweenInfo.new(Theme.REACT_FLASH_SECONDS), { Transparency = 1 })
		:Play()
	local ghost = fxPart("ReactGhost", frame, size, Theme.REACT_CHAR_COLOR)
	ghost.Material = Enum.Material.Slate
	ghost.Transparency = Theme.REACT_GHOST_TRANSPARENCY
	ghost.Parent = folder
	local goal: { [string]: any } = { Transparency = 1 }
	if not Theme.lowEndDevice then
		local shrunk = Vector3.new(size.X, MIN_SIZE, size.Z)
		goal.Size = shrunk
		goal.CFrame = frame - Vector3.new(0, (size.Y - MIN_SIZE) / 2, 0)
	end
	TweenService:Create(
		ghost,
		TweenInfo.new(Theme.REACT_GHOST_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		goal
	):Play()
	local smoke: Part? = nil
	if not Theme.lowEndDevice then
		local holder = fxPart("ReactSmoke", frame, size, Theme.REACT_CHAR_COLOR)
		holder.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = SMOKE_TEXTURE
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Color = ColorSequence.new(Color3.fromRGB(70, 66, 64))
		emitter.Size = NumberSequence.new(1.5, 5)
		emitter.Transparency = NumberSequence.new(0.35, 1)
		emitter.Lifetime =
			NumberRange.new(Theme.REACT_SMOKE_SECONDS * 0.6, Theme.REACT_SMOKE_SECONDS)
		emitter.Speed = NumberRange.new(3, 7)
		emitter.Acceleration = Vector3.new(0, 4, 0)
		emitter.RotSpeed = NumberRange.new(-40, 40)
		emitter.Rate = 0
		emitter.Parent = holder
		holder.Parent = folder
		emitter:Emit(Theme.REACT_SMOKE_COUNT)
		smoke = holder
	end
	task.delay(math.max(Theme.REACT_GHOST_SECONDS, Theme.REACT_FLASH_SECONDS), function()
		flash:Destroy()
		ghost:Destroy()
	end)
	if smoke ~= nil then
		local holder = smoke
		task.delay(Theme.REACT_SMOKE_SECONDS, function()
			holder:Destroy()
		end)
	end
end

-- L2-56: a cell the server froze (its box as built): a glint, and frost motes off its top.
local function frozen(centre: Vector3, size: Vector3): ()
	local folder = fxFolder()
	local frame = CFrame.new(centre)
	local flash = fxPart("IceFlash", frame, size + Vector3.one * 0.2, Theme.REACT_ICE_FLASH_COLOR)
	flash.Material = Enum.Material.Neon
	flash.Transparency = Theme.REACT_ICE_FLASH_TRANSPARENCY
	flash.Parent = folder
	TweenService:Create(flash, TweenInfo.new(Theme.REACT_ICE_FLASH_SECONDS), { Transparency = 1 })
		:Play()
	task.delay(Theme.REACT_ICE_FLASH_SECONDS, function()
		flash:Destroy()
	end)
	if Theme.lowEndDevice then
		return
	end
	local holder = fxPart("IceBurst", frame, size, Theme.REACT_ICE_BURST_COLOR)
	holder.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Color = ColorSequence.new(Theme.REACT_ICE_BURST_COLOR)
	emitter.LightEmission = 0.6
	emitter.LightInfluence = 0.2
	emitter.Size = NumberSequence.new(0.45, 0)
	emitter.Transparency = NumberSequence.new(0.1, 0.8)
	emitter.Lifetime =
		NumberRange.new(Theme.REACT_ICE_BURST_SECONDS * 0.5, Theme.REACT_ICE_BURST_SECONDS)
	emitter.Speed = NumberRange.new(1.5, 4)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Acceleration = Vector3.new(0, -2, 0)
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = folder
	emitter:Emit(Theme.REACT_ICE_BURST_COUNT)
	task.delay(Theme.REACT_ICE_BURST_SECONDS, function()
		holder:Destroy()
	end)
end

-- A ghost of ice on `cell` now, held by the swing `seq` (a cell another swing already holds
-- keeps its one ghost).
local function ghostOn(cell: IceCell, seq: number): ()
	local held = state.ghosts[cell.part]
	if held ~= nil then
		held.holders[seq] = true
		return
	end
	local part = fxPart("IceGhost", cell.frame, cell.size, Theme.COMBAT_FROST_GHOST_COLOR)
	part.Material = Enum.Material.Ice
	part.Transparency = Theme.COMBAT_FROST_GHOST_TRANSPARENCY
	part.Parent = fxFolder()
	state.ghosts[cell.part] = { part = part, holders = { [seq] = true } }
end

-- The swing `seq` lets go of its ghosts; a ghost no swing holds any more goes.
local function release(seq: number): ()
	local prediction = state.predictions[seq]
	if prediction == nil then
		return
	end
	state.predictions[seq] = nil
	for _, cell in prediction.cells do
		local ghost = state.ghosts[cell]
		if ghost ~= nil then
			ghost.holders[seq] = nil
			if next(ghost.holders) == nil then
				dropGhost(cell)
			end
		end
	end
end

-- Releases `seq` after `seconds`, unless it was released (or predicted anew) meanwhile.
local function releaseAfter(seq: number, prediction: Prediction, seconds: number): ()
	task.delay(seconds, function()
		if state.predictions[seq] == prediction then
			release(seq)
		end
	end)
end

-- Mission HUD only: starts watching the level's Parts for heat.
function ReactFx.Mount(): ()
	if state.mounted then
		return
	end
	state.mounted = true
	task.spawn(watchLevel)
end

-- One CombatFx of kind `react` (CombatFxReact), read defensively: it comes off the network.
function ReactFx.OnFx(fx: any): ()
	if
		typeof(fx) ~= "table"
		or fx.kind ~= "react"
		or (fx.event ~= "burnt" and fx.event ~= "frozen")
		or typeof(fx.x) ~= "number"
		or typeof(fx.y) ~= "number"
		or typeof(fx.z) ~= "number"
		or typeof(fx.sx) ~= "number"
		or typeof(fx.sy) ~= "number"
		or typeof(fx.sz) ~= "number"
	then
		return
	end
	local size = Vector3.new(fx.sx, fx.sy, fx.sz)
	if size.X <= 0 or size.Y <= 0 or size.Z <= 0 then
		return
	end
	local centre = Vector3.new(fx.x, fx.y, fx.z)
	if fx.event == "frozen" then
		frozen(centre, size)
	else
		burnt(centre, size)
	end
end

-- c-M1: each reactive Part the level holds now, with its `React` and `Heat` attributes as read
-- (InputController's touch auto-fire asks, on the frames a stream family is held). Empty until
-- Mount, and in the range, which has no level.
function ReactFx.ForEachPart(callback: (part: BasePart, react: any, heat: any) -> ()): ()
	for part in state.parts do
		if part.Parent ~= nil then
			callback(part, part:GetAttribute(REACT_ATTRIBUTE), part:GetAttribute(HEAT_ATTRIBUTE))
		end
	end
end

local function boundsOf(): Bounds?
	local bounds = state.bounds
	if bounds ~= nil then
		return bounds
	end
	local made: Bounds? = nil
	for _, cell in state.ice do
		local x, z, top = cell.x, cell.z, cell.top
		if made == nil then
			made = { minX = x, maxX = x, minZ = z, maxZ = z, low = top, high = top }
		else
			made.minX = math.min(made.minX, x)
			made.maxX = math.max(made.maxX, x)
			made.minZ = math.min(made.minZ, z)
			made.maxZ = math.max(made.maxZ, z)
			made.low = math.min(made.low, top)
			made.high = math.max(made.high, top)
		end
	end
	state.bounds = made
	return made
end

-- c-m1: false when no ice cell can lie within `reach` of `origin` in plan (the rectangle of the
-- cells' centres) or in WorldReact.Chills' band (a top from origin.Y down to `reachDown` under
-- it). One rectangle a frame is all a swing far from the water costs.
local function nearBounds(origin: Vector3, reach: number, reachDown: number): boolean
	if #state.open == 0 then
		return false
	end
	local bounds = boundsOf()
	if bounds == nil then
		return false
	end
	local y = origin.Y
	if
		not (
			reach >= 0
			and y >= bounds.low - NEAR_SLACK
			and y <= bounds.high + reachDown + NEAR_SLACK
		)
	then
		return false
	end
	local dx = math.max(bounds.minX - origin.X, 0, origin.X - bounds.maxX)
	local dz = math.max(bounds.minZ - origin.Z, 0, origin.Z - bounds.maxZ)
	local far = reach + NEAR_SLACK
	return dx * dx + dz * dz <= far * far
end

-- L2-55: each ice cell the level holds now that the server has not frozen (its `Ice` is false)
-- and that WorldReact.Chills could name for a swing from `origin` reaching `reach` in plan (its
-- size + ahead) and `reachDown` down: the cell's centre within `reach` of the origin in plan and
-- its top in the band. That is only Chills' own distance and band, a little wider, so no cell it
-- skips could chill; the callback asks Chills itself. It goes on until `callback` answers true
-- (c-s2) and returns whether one did; no order. c-m1: far from the water this is one rectangle,
-- by it a few arithmetic steps a cell (the boxes are cached), and Chills only for the few cells
-- within reach. Empty until Mount, and in the range, which has no level.
function ReactFx.ForEachIce(
	origin: Vector3,
	reach: number,
	reachDown: number,
	callback: (part: BasePart, box: WorldReact.Box) -> boolean
): boolean
	if not nearBounds(origin, reach, reachDown) then
		return false
	end
	local x, y, z = origin.X, origin.Y, origin.Z
	local far = reach + NEAR_SLACK
	local farSquared = far * far
	local low = y - reachDown - NEAR_SLACK
	local high = y + NEAR_SLACK
	for _, cell in state.open do
		local top = cell.top
		if top >= low and top <= high then
			local dx, dz = cell.x - x, cell.z - z
			if dx * dx + dz * dz <= farSquared and callback(cell.part, cell.box) then
				return true
			end
		end
	end
	return false
end

-- L2-54: what WorldReact.Chills reads of Combat.json levels.react.ice (reachDown, ahead), read
-- by the server's own reader (WorldReact.IceReach, d-m5); nil when the config has no ice block
-- (the water is only deep: nothing freezes).
function ReactFx.IceReach(): (number?, number?)
	local combat = Catalog.GetCombatConfig()
	local react = if combat ~= nil then combat.levels.react else nil
	return WorldReact.IceReach(if react ~= nil then react.ice else nil)
end

-- The second fix round's Q5: levels.react.ice's sink, read by the server's own reader
-- (WorldReact.IceSink); nil = no body is judged (as on the server).
function ReactFx.IceSink(): number?
	local combat = Catalog.GetCombatConfig()
	local react = if combat ~= nil then combat.levels.react else nil
	return WorldReact.IceSink(if react ~= nil then react.ice else nil)
end

-- The second fix round's Q5: every player's body as this client sees it now (its own root, the
-- others' replicated ones), as LevelService reads them for the freeze: WorldReact.BodyBox of the
-- root Part and the Humanoid. A character with no root Part or no Humanoid has none.
function ReactFx.Bodies(): { WorldReact.Box }
	local found: { WorldReact.Box } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root ~= nil and root:IsA("BasePart") and humanoid ~= nil then
			table.insert(
				found,
				WorldReact.BodyBox(
					root.Position,
					root.CFrame.RightVector,
					root.Size,
					humanoid.HipHeight
				)
			)
		end
	end
	return found
end

-- L2-56: the local player's own ice swing `seq` as it was sent (WorldReact.SwingStrike: the
-- strike the server will build from it). Every unfrozen cell WorldReact.Chills names gets a
-- ghost of ice on this frame, held by `seq` until AnswerFreeze's grace, RefuseFreeze, or
-- Theme.COMBAT_RANGE_SWING_ANSWER_SECONDS with no answer (c-m2). The second fix round's Q5: a
-- cell a player's body stands in gets none (WorldReact.Holds, the bodies read once a cell chills).
function ReactFx.PredictFreeze(swing: WorldReact.Strike, seq: number): ()
	if not state.mounted then
		return
	end
	local reachDown, ahead = ReactFx.IceReach()
	if reachDown == nil or ahead == nil then
		return
	end
	local sink = ReactFx.IceSink()
	local bodies: { WorldReact.Box }? = nil
	local named: { BasePart } = {}
	ReactFx.ForEachIce(
		swing.origin,
		swing.size + ahead,
		reachDown,
		function(part: BasePart, box: WorldReact.Box): boolean
			if not WorldReact.Chills(swing, box, reachDown, ahead) then
				return false
			end
			local around = bodies
			if around == nil then
				around = ReactFx.Bodies()
				bodies = around
			end
			if not WorldReact.Holds(box, around, sink) then
				table.insert(named, part)
			end
			return false
		end
	)
	if #named == 0 then
		return
	end
	-- A seq is never sent twice; should one come back, its old ghosts go first.
	release(seq)
	local prediction: Prediction = { cells = named, answered = false }
	for _, part in named do
		local cell = state.ice[part]
		if cell ~= nil then
			ghostOn(cell, seq)
		end
	end
	state.predictions[seq] = prediction
	releaseAfter(seq, prediction, Theme.COMBAT_RANGE_SWING_ANSWER_SECONDS)
end

-- c-m2: the strike that answers the local swing `seq` has come. The server freezes right after
-- it broadcasts that strike, so the cells it froze turn `Ice` true within a replication step;
-- the ghosts it did not freeze go after the grace.
function ReactFx.AnswerFreeze(seq: number): ()
	local prediction = state.predictions[seq]
	if prediction == nil or prediction.answered then
		return
	end
	prediction.answered = true
	releaseAfter(seq, prediction, Theme.COMBAT_FROST_GHOST_GRACE_SECONDS)
end

-- c-m2: the server refused the local attack `seq` (RangeStats.refusedSeq): its ghosts go now. A
-- refused shot's seq holds none.
function ReactFx.RefuseFreeze(seq: number): ()
	release(seq)
end

function ReactFx.Destroy(): ()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	table.clear(state.predictions)
	for cell in state.ghosts do
		dropGhost(cell)
	end
	for _, cell in state.ice do
		cell.connection:Disconnect()
	end
	table.clear(state.ice)
	table.clear(state.open)
	state.bounds = nil
	for _, heated in state.parts do
		heated.connection:Disconnect()
	end
	table.clear(state.parts)
	local folder = state.folder
	if folder ~= nil then
		folder:Destroy()
	end
	state.folder = nil
	state.mounted = false
end

return ReactFx
