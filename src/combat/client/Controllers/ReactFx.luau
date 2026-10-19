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
--  * PredictFreeze: on the local player's own ice swing, a ghost of ice (local, translucent,
--    never colliding or queried) on every unfrozen cell the server's own rule names
--    (WorldReact.Chills with Combat.json levels.react.ice), from the press frame. The real cell
--    replaces it when its `Ice` turns true; otherwise it goes after
--    Theme.COMBAT_FROST_GHOST_SECONDS (the server did not freeze it). A ghost is information, so
--    it draws on every device.
--  * Frozen (CombatFx `react`, event "frozen", the cell's box): a pale glint over the cell and a
--    burst of frost motes; a low-end device gets the glint alone.
--
-- No sound (combat has none).

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

-- A predicted ghost on one ice cell, and its wait for the server's `Ice`.
type Ghost = {
	part: Part,
	connection: RBXScriptConnection,
	token: number,
}

-- Workspace.Level (LevelService.LEVEL_FOLDER) and the attribute the server writes.
local LEVEL_FOLDER = "Level"
local HEAT_ATTRIBUTE = "Heat"
local REACT_ATTRIBUTE = "React"
-- L2-53: an ice cell's attribute, false until the server freezes it.
local ICE_ATTRIBUTE = "Ice"
local FX_FOLDER = "ReactFx"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MIN_SIZE = 0.05

local ReactFx = {}

local state = {
	mounted = false,
	parts = {} :: { [BasePart]: Heated },
	-- L2-53: every ice cell Part of the level, frozen or not (its `Ice` is read when asked).
	ice = {} :: { [BasePart]: true },
	ghosts = {} :: { [BasePart]: Ghost },
	ghostToken = 0,
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

-- Only the reactive Parts and the ice cells are watched (LevelService sets `React` or `Ice`
-- before parenting them).
local function adopt(child: Instance): ()
	if not child:IsA("BasePart") then
		return
	end
	if typeof(child:GetAttribute(ICE_ATTRIBUTE)) == "boolean" then
		state.ice[child] = true
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

local function dropGhost(cell: BasePart): ()
	local ghost = state.ghosts[cell]
	if ghost == nil then
		return
	end
	state.ghosts[cell] = nil
	ghost.connection:Disconnect()
	ghost.part:Destroy()
end

local function forget(child: Instance): ()
	if not child:IsA("BasePart") then
		return
	end
	state.ice[child] = nil
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

-- A ghost of ice on `cell` now (a second swing over the same cell only renews its wait).
local function ghostOn(cell: BasePart): ()
	state.ghostToken += 1
	local token = state.ghostToken
	local held = state.ghosts[cell]
	if held ~= nil then
		held.token = token
	else
		local part = fxPart("IceGhost", cell.CFrame, cell.Size, Theme.COMBAT_FROST_GHOST_COLOR)
		part.Material = Enum.Material.Ice
		part.Transparency = Theme.COMBAT_FROST_GHOST_TRANSPARENCY
		part.Parent = fxFolder()
		state.ghosts[cell] = {
			part = part,
			token = token,
			connection = cell:GetAttributeChangedSignal(ICE_ATTRIBUTE):Connect(function()
				if cell:GetAttribute(ICE_ATTRIBUTE) == true then
					dropGhost(cell)
				end
			end),
		}
	end
	task.delay(Theme.COMBAT_FROST_GHOST_SECONDS, function()
		local ghost = state.ghosts[cell]
		if ghost ~= nil and ghost.token == token then
			dropGhost(cell)
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

-- L2-55: each ice cell Part the level holds now that the server has not frozen (its `Ice` is
-- false). Empty until Mount, and in the range, which has no level.
function ReactFx.ForEachIce(callback: (part: BasePart) -> ()): ()
	for part in state.ice do
		if part.Parent ~= nil and part:GetAttribute(ICE_ATTRIBUTE) == false then
			callback(part)
		end
	end
end

-- L2-54: what WorldReact.Chills reads of Combat.json levels.react.ice (reachDown, ahead); nil
-- when the config has no ice block (the water is only deep: nothing freezes).
function ReactFx.IceReach(): (number?, number?)
	local combat = Catalog.GetCombatConfig()
	local react = if combat ~= nil then combat.levels.react else nil
	local ice = if react ~= nil then react.ice else nil
	if ice == nil then
		return nil, nil
	end
	return ice.reachDown, ice.ahead
end

-- L2-56: the local player's own ice swing as it was sent (the strike the server will build from
-- it). Every unfrozen cell WorldReact.Chills names gets a ghost of ice on this frame.
function ReactFx.PredictFreeze(swing: WorldReact.Strike): ()
	if not state.mounted then
		return
	end
	local reachDown, ahead = ReactFx.IceReach()
	if reachDown == nil or ahead == nil then
		return
	end
	ReactFx.ForEachIce(function(cell: BasePart)
		local box = WorldReact.BoxOf(cell.Position, cell.Size)
		if WorldReact.Chills(swing, box, reachDown, ahead) then
			ghostOn(cell)
		end
	end)
end

function ReactFx.Destroy(): ()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	for cell in state.ghosts do
		dropGhost(cell)
	end
	table.clear(state.ice)
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
