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
--    Part; here a flash of the box, a local ghost of it that shrinks away (only fades under
--    Theme.reducedMotion) and a puff of smoke (not on low-end devices). Every piece is anchored,
--    never collides, is never queried and is gone within Theme.REACT_SMOKE_SECONDS.
--
-- No sound (combat has none).

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))

type Heated = {
	part: BasePart,
	color: Color3,
	embers: ParticleEmitter?,
	connection: RBXScriptConnection,
}

-- Workspace.Level (LevelService.LEVEL_FOLDER) and the attribute the server writes.
local LEVEL_FOLDER = "Level"
local HEAT_ATTRIBUTE = "Heat"
local REACT_ATTRIBUTE = "React"
local FX_FOLDER = "ReactFx"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local MIN_SIZE = 0.05

local ReactFx = {}

local state = {
	mounted = false,
	parts = {} :: { [BasePart]: Heated },
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

-- Only the reactive Parts are watched (LevelService sets `React` before parenting them).
local function adopt(child: Instance): ()
	if
		not child:IsA("BasePart")
		or state.parts[child] ~= nil
		or child:GetAttribute(REACT_ATTRIBUTE) == nil
	then
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
	if not Theme.reducedMotion then
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
		or fx.event ~= "burnt"
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
	burnt(Vector3.new(fx.x, fx.y, fx.z), size)
end

function ReactFx.Destroy(): ()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
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
