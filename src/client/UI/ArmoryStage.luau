--!strict
-- The Armory screen's stage (docs/prompts/l3-w1-contract.md, L3-18; docs/prompts/l3-w2-contract.md,
-- L3-56): the selected weapon shown large.
--
-- With its model (WeaponModels.json names it, Assets/Props/<folder>/<model> holds it) the weapon
-- stands in a ViewportFrame over the lighter band: cloned once per selection, posed once with its
-- tip raised, and from then on only the camera moves. The clone's Base is found by name and made
-- its PrimaryPart before the pose (a template's PrimaryPart ref can arrive nil in a live session,
-- and a model without one pivots about its bounding box); a template with no Base counts as
-- missing. The camera orbits the model's bounds (from the config, never measured), framing their
-- sphere so no turn changes the framing. While the screen is open on the Weapons tab (SetActive)
-- with a model shown, and only then, it turns slowly, except on low-end devices
-- (Theme.lowEndDevice, never reducedMotion, which is true on every phone); a drag turns it on
-- every device. The gamepad's right stick does not: the world camera behind the screen reads it
-- unsunk, so it would turn the lobby and the character too. A drag ends on its own release, on
-- the window losing focus, and whenever the stage stops (close, the Abilities tab, no model). An
-- unowned weapon is a near-black silhouette over the same lighter band. The name and the big
-- tier (the detail column shows both) give way to a small top line: the slot word and the
-- element chip.
--
-- Without a model (no config, no entry, no template: before the harvest paste, L3-59) it is W1's
-- placeholder exactly: the family's name large, its slot, its element chip (FIRE / ICE), a big
-- tier ("T3"), an unowned family dark, its tier the one it arrives at. A new selection pops the
-- text in, except on low-end devices.
--
-- The screen (UI/ArmoryScreen) calls new, Show, SetSize, SetActive and Destroy, and never reaches
-- inside.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Types = require(sharedFolder:WaitForChild("Types"))
local WeaponLook = require(sharedFolder:WaitForChild("WeaponLook"))

local ArmoryModel = require(script.Parent:WaitForChild("ArmoryModel"))
local Create = require(script.Parent:WaitForChild("Create"))
local Motion = require(script.Parent:WaitForChild("Motion"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Stage = {
	frame: Frame,
	-- nil = nothing selected (an empty stage).
	Show: (view: ArmoryModel.Card?) -> (),
	SetSize: (width: number, height: number) -> (),
	-- true while the screen is open on the Weapons tab; false on close, on the Abilities tab and
	-- on Destroy. Only then may the model turn or be dragged.
	SetActive: (active: boolean) -> (),
	Destroy: () -> (),
}

type Drag = {
	-- The press that started it: a touch is followed by its own InputObject, a mouse by any
	-- movement until the button's release.
	input: InputObject,
	x: number,
	connections: { RBXScriptConnection },
}

local WHITE = Color3.new(1, 1, 1)
local TEMPLATE_BASE_NAME = "Base"

local ArmoryStage = {}

local function label(name: string, size: number, font: Enum.Font, parent: Instance): TextLabel
	return Create("TextLabel", {
		Name = name,
		Active = false,
		BackgroundTransparency = 1,
		Font = font,
		TextSize = size,
		TextColor3 = Theme.MAP_COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: TextLabel
end

local function vector(list: { number }): Vector3
	return Vector3.new(list[1], list[2], list[3])
end

-- The props folder the config names, looked up child by child (never recursively, never
-- waiting): nil until the templates exist.
local function weaponsFolder(models: Types.WeaponModelsConfig): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = if assets ~= nil then assets:FindFirstChild("Props") else nil
	return if props ~= nil then props:FindFirstChild(models.folder) else nil
end

-- The family's template and its entry; nil without a config, a valid entry, or a template with
-- its Base.
local function templateOf(family: string): (Model?, Types.WeaponModelDef?)
	local models = Catalog.GetWeaponModelsConfig()
	local def = WeaponLook.Def(models, family)
	if models == nil or def == nil then
		return nil, nil
	end
	local folder = weaponsFolder(models)
	local template = if folder ~= nil then folder:FindFirstChild(def.model) else nil
	if template == nil or not template:IsA("Model") then
		return nil, nil
	end
	local base = template:FindFirstChild(TEMPLATE_BASE_NAME)
	if base == nil or not base:IsA("BasePart") then
		return nil, nil
	end
	return template, def
end

-- The first time the screen opens: the weapon meshes and textures start loading in the
-- background, so the first selections do not pop in. Nothing waits on it.
local function warm(): ()
	local models = Catalog.GetWeaponModelsConfig()
	local folder = if models ~= nil then weaponsFolder(models) else nil
	if folder == nil then
		return
	end
	local target: Instance = folder
	task.spawn(function()
		local ok, problem = pcall(ContentProvider.PreloadAsync, ContentProvider, { target })
		if not ok then
			warn(`[ArmoryStage] preloading the weapon models failed: {problem}`)
		end
	end)
end

function ArmoryStage.new(parent: Instance): Stage
	local frame = Create("Frame", {
		Name = "Stage",
		Active = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
	-- The lighter band behind the weapon (the L0 picture's radial, as a linear UIGradient).
	local gradient = Create("UIGradient", {
		Rotation = 90,
		Color = Theme.ARMORY_SCREEN_STAGE_GRADIENT,
		Parent = frame,
	}) :: UIGradient
	local stroke = Create("UIStroke", {
		Color = Theme.MAP_COLOR_PANEL_SELECTED,
		Thickness = Theme.STROKE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	}) :: UIStroke

	-- The weapon: transparent over the gradient, under the text (one ZIndex below its siblings),
	-- never a gamepad selection. Active, so a drag on it is the stage's alone.
	local viewport = Create("ViewportFrame", {
		Name = "Weapon",
		Active = true,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Theme.ARMORY_STAGE_AMBIENT,
		LightColor = Theme.ARMORY_STAGE_LIGHT_COLOR,
		LightDirection = Theme.ARMORY_STAGE_LIGHT_DIRECTION,
		ImageColor3 = WHITE,
		Selectable = false,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD - 1,
		Parent = frame,
	}) :: ViewportFrame
	local camera = Create("Camera", {
		FieldOfView = Theme.ARMORY_STAGE_FOV,
		Parent = viewport,
	}) :: Camera
	viewport.CurrentCamera = camera

	-- One column, centred: slot word, name, the element chip, the big tier. With a model it is a
	-- line at the top: the slot word beside the chip.
	local column = Create("Frame", {
		Name = "Column",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -Theme.ARMORY_SCREEN_PADDING * 2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = frame,
	}) :: Frame
	local list = Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ARMORY_SCREEN_STAGE_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = column,
	}) :: UIListLayout
	local pop = Create("UIScale", { Parent = column }) :: UIScale

	local slot = label("Slot", Theme.ARMORY_SCREEN_STAGE_SLOT_TEXT, Theme.FONT_BOLD, column)
	slot.LayoutOrder = 1
	slot.Size = UDim2.new(1, 0, 0, Theme.ARMORY_SCREEN_STAGE_SLOT_TEXT + 2)
	local name = label("Name", Theme.ARMORY_SCREEN_STAGE_NAME_TEXT, Theme.FONT_BOLD, column)
	name.LayoutOrder = 2
	name.Size = UDim2.fromScale(1, 0)
	name.AutomaticSize = Enum.AutomaticSize.Y
	name.TextWrapped = true
	local chip = label("Element", Theme.ARMORY_SCREEN_CHIP_TEXT, Theme.FONT_BOLD, column)
	chip.LayoutOrder = 3
	chip.BackgroundTransparency = 0
	chip.TextColor3 = Theme.MAP_COLOR_INK
	chip.Size = UDim2.fromOffset(0, Theme.ARMORY_SCREEN_CHIP_HEIGHT)
	chip.AutomaticSize = Enum.AutomaticSize.X
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, Theme.ARMORY_SCREEN_CHIP_PAD),
		PaddingRight = UDim.new(0, Theme.ARMORY_SCREEN_CHIP_PAD),
		Parent = chip,
	})
	Create("UICorner", {
		CornerRadius = UDim.new(0, Theme.ARMORY_SCREEN_CHIP_HEIGHT // 2),
		Parent = chip,
	})
	local tier = label("Tier", Theme.ARMORY_SCREEN_STAGE_TIER_TEXT, Theme.FONT_BOLD, column)
	tier.LayoutOrder = 4
	tier.Size = UDim2.new(1, 0, 0, Theme.ARMORY_SCREEN_STAGE_TIER_TEXT + 4)

	local tween: Tween? = nil
	local look = {
		-- The family last shown (nil = an empty stage) and its model, when it has one.
		family = nil :: string?,
		model = nil :: Model?,
		-- The posed model's bounds: the camera's target and the radius of their sphere.
		centre = Vector3.zero,
		radius = 0,
		yaw = Theme.ARMORY_STAGE_START_YAW_DEGREES,
		width = 0,
		height = 0,
		active = false,
		warmed = false,
		-- Live only while the screen is open on Weapons with a model shown (syncTurn): the slow
		-- turn (never on a low-end device), and the window's focus listener.
		turn = nil :: RBXScriptConnection?,
		focus = nil :: RBXScriptConnection?,
		drag = nil :: Drag?,
	}

	local function popIn(): ()
		if Theme.lowEndDevice then
			return
		end
		local running = tween
		if running ~= nil then
			running:Cancel()
		end
		pop.Scale = Theme.ARMORY_SCREEN_STAGE_POP_SCALE
		local made = TweenService:Create(
			pop,
			Motion.Info(Theme.ARMORY_SCREEN_STAGE_POP_SECONDS),
			{ Scale = 1 }
		)
		tween = made
		made:Play()
	end

	-- The camera on its orbit: yaw from the weapon's right side (+X) toward its tip (-Z), pitch
	-- above, far enough that the bounds' sphere fits the narrower of the two view angles.
	local function place(): ()
		if look.model == nil then
			return
		end
		local half = math.rad(Theme.ARMORY_STAGE_FOV) / 2
		local aspect = if look.height > 0 then look.width / look.height else 1
		local fit = math.atan(math.tan(half) * math.min(1, aspect))
		local distance = look.radius / math.sin(fit) * Theme.ARMORY_STAGE_FIT
		local yaw = math.rad(look.yaw)
		local pitch = math.rad(Theme.ARMORY_STAGE_PITCH_DEGREES)
		local direction = Vector3.new(
			math.cos(pitch) * math.cos(yaw),
			math.sin(pitch),
			-math.cos(pitch) * math.sin(yaw)
		)
		camera.CFrame = CFrame.lookAt(look.centre + direction * distance, look.centre)
	end

	-- Turns the view by `degrees`: positive turns the weapon's near side right (the camera goes
	-- left), as a drag to the right does.
	local function turnBy(degrees: number): ()
		look.yaw = (look.yaw - degrees) % 360
		place()
	end

	local function clear(): ()
		local model = look.model
		if model ~= nil then
			look.model = nil
			model:Destroy()
		end
	end

	-- A selection: the old model goes, the family's template is cloned once, anchored and posed
	-- once (the tip rising, as on the icons); from then on only the camera moves.
	local function selectFamily(family: string): ()
		clear()
		look.family = family
		local template, def = templateOf(family)
		if template == nil or def == nil then
			return
		end
		local low = vector(def.bounds.min)
		local high = vector(def.bounds.max)
		local radius = (high - low).Magnitude / 2
		if radius <= 0 then
			return
		end
		local model = template:Clone() :: Model
		local base = model:FindFirstChild(TEMPLATE_BASE_NAME)
		if base == nil or not base:IsA("BasePart") then
			model:Destroy()
			return
		end
		model.PrimaryPart = base
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		-- The template's pivot is the grip and its frame the generator's (L3-47), so the bounds
		-- in the config turn with the model.
		local pose = CFrame.Angles(math.rad(Theme.ARMORY_STAGE_TILT_DEGREES), 0, 0)
		model:PivotTo(pose)
		model.Parent = viewport
		look.model = model
		look.centre = pose:PointToWorldSpace((low + high) / 2)
		look.radius = radius
		look.yaw = Theme.ARMORY_STAGE_START_YAW_DEGREES
		place()
	end

	local function endDrag(): ()
		local drag = look.drag
		if drag == nil then
			return
		end
		look.drag = nil
		for _, connection in drag.connections do
			connection:Disconnect()
		end
	end

	local function stop(): ()
		local turn = look.turn
		if turn ~= nil then
			look.turn = nil
			turn:Disconnect()
		end
		local focus = look.focus
		if focus ~= nil then
			look.focus = nil
			focus:Disconnect()
		end
		endDrag()
	end

	-- Called whenever the screen's state or the shown model changes: the stage's listener and
	-- its per-frame turn exist only while the screen is open on Weapons with a model shown
	-- (3-s2); otherwise everything stops, any drag included.
	local function syncTurn(): ()
		if not look.active or look.model == nil then
			stop()
			return
		end
		if look.focus == nil then
			-- A release the window never saw (focus lost mid-drag) must not leave a drag running.
			look.focus = UserInputService.WindowFocusReleased:Connect(endDrag)
		end
		if look.turn == nil and not Theme.lowEndDevice then
			look.turn = RunService.RenderStepped:Connect(function(deltaTime: number)
				if look.drag ~= nil then
					return
				end
				turnBy(Theme.ARMORY_STAGE_TURN_DEGREES_PER_SECOND * deltaTime)
			end)
		end
	end

	-- The stage's own text: W1's centred column without a model, the small top line with one.
	local function dress(withModel: boolean): ()
		name.Visible = not withModel
		tier.Visible = not withModel
		if withModel then
			column.AnchorPoint = Vector2.new(0.5, 0)
			column.Position = UDim2.new(0.5, 0, 0, Theme.ARMORY_SCREEN_PADDING)
			list.FillDirection = Enum.FillDirection.Horizontal
			list.VerticalAlignment = Enum.VerticalAlignment.Center
			slot.AutomaticSize = Enum.AutomaticSize.X
			slot.Size = UDim2.fromOffset(0, Theme.ARMORY_SCREEN_STAGE_SLOT_TEXT + 2)
		else
			column.AnchorPoint = Vector2.new(0.5, 0.5)
			column.Position = UDim2.fromScale(0.5, 0.5)
			list.FillDirection = Enum.FillDirection.Vertical
			list.VerticalAlignment = Enum.VerticalAlignment.Top
			slot.AutomaticSize = Enum.AutomaticSize.None
			slot.Size = UDim2.new(1, 0, 0, Theme.ARMORY_SCREEN_STAGE_SLOT_TEXT + 2)
		end
	end

	-- A press on the weapon drags it round; the slow turn waits until the release and carries on
	-- from there. Each drag event places the camera once (no per-frame work on a low-end device).
	-- The drag ends on any end of the press that started it, on a mouse movement with the button
	-- no longer down (its release was lost), and whenever the stage stops.
	viewport.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		if not look.active or look.model == nil or look.drag ~= nil then
			return
		end
		local drag: Drag = { input = input, x = input.Position.X, connections = {} }
		look.drag = drag
		local touch = kind == Enum.UserInputType.Touch
		table.insert(
			drag.connections,
			UserInputService.InputChanged:Connect(function(moved: InputObject)
				local follows = if touch
					then moved == input
					else moved.UserInputType == Enum.UserInputType.MouseMovement
				if not follows then
					return
				end
				if not touch and not UserInputService:IsMouseButtonPressed(kind) then
					endDrag()
					return
				end
				local x = moved.Position.X
				turnBy((x - drag.x) * Theme.ARMORY_STAGE_DRAG_DEGREES_PER_PIXEL)
				drag.x = x
			end)
		)
		table.insert(
			drag.connections,
			UserInputService.InputEnded:Connect(function(ended: InputObject)
				if ended == input or (not touch and ended.UserInputType == kind) then
					endDrag()
				end
			end)
		)
	end)

	local stage: Stage = {
		frame = frame,
		Show = function(view: ArmoryModel.Card?)
			if view == nil then
				clear()
				look.family = nil
				syncTurn()
				viewport.Visible = false
				dress(false)
				slot.Text = ""
				name.Text = ""
				tier.Text = ""
				chip.Visible = false
				gradient.Color = Theme.ARMORY_SCREEN_STAGE_DARK_GRADIENT
				return
			end
			local fresh = view.family ~= look.family
			-- A family whose template was missing is looked up again (it may have replicated).
			if fresh or look.model == nil then
				selectFamily(view.family)
				syncTurn()
			end
			local withModel = look.model ~= nil
			local owned = view.owned
			viewport.Visible = withModel
			viewport.ImageColor3 = if owned then WHITE else Theme.ARMORY_STAGE_SILHOUETTE
			dress(withModel)
			slot.Text = string.upper(view.slotWord)
			slot.TextColor3 = Theme.MAP_COLOR_DIM
			name.Text = view.name
			name.TextColor3 = if owned then Theme.MAP_COLOR_TEXT else Theme.MAP_COLOR_DIM
			tier.Text = view.tierText
			tier.TextColor3 = if owned then Theme.MAP_COLOR_GOLD else Theme.MAP_COLOR_OFF
			local element = view.element
			chip.Visible = element ~= nil
			if element ~= nil then
				chip.Text = Theme.SECRET_NEED_WORDS[element] or string.upper(element)
				local color = Theme.ARMORY_SCREEN_ELEMENT_COLORS[element] or Theme.MAP_COLOR_GOLD
				chip.BackgroundColor3 = color
				chip.BackgroundTransparency = if owned then 0 else Theme.ARMORY_SCREEN_DARK_CHIP
			end
			-- A silhouette needs the lighter band to read; the dark one stays for the text.
			gradient.Color = if owned or withModel
				then Theme.ARMORY_SCREEN_STAGE_GRADIENT
				else Theme.ARMORY_SCREEN_STAGE_DARK_GRADIENT
			stroke.Color = if owned then Theme.MAP_COLOR_PANEL_SELECTED else Theme.MAP_COLOR_LOCKED
			if fresh then
				popIn()
			end
		end,
		SetSize = function(width: number, height: number)
			frame.Size = UDim2.fromOffset(width, height)
			look.width = width
			look.height = height
			place()
		end,
		SetActive = function(active: boolean)
			if active == look.active then
				return
			end
			look.active = active
			if not active then
				stop()
				return
			end
			if not look.warmed then
				look.warmed = true
				warm()
			end
			syncTurn()
		end,
		Destroy = function()
			look.active = false
			stop()
			local running = tween
			if running ~= nil then
				running:Cancel()
			end
			clear()
			frame:Destroy()
		end,
	}
	return stage
end

return ArmoryStage
