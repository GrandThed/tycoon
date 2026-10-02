--!strict
-- The Proving Grounds' touch buttons that InputController owns (P1 aim toggle; P3 the two
-- ability buttons and the slot button, docs/INTERFACES.md "P3 contracts" rulings 1 and 9).
-- Split out of InputController so that file stays under Luau's 200 locals per function (a
-- module's top level is one function, and Studio compiles with every local kept).
--
-- This module only draws and reports presses. InputController decides everything: it hands in
-- the handlers once and pushes each frame's faces (SetAim / SetAbility / SetSlot), so no input
-- rule, cooldown or loadout lives here. There is no attack button, by Ben's rule.
--
-- Layout is MovementController.ClusterRect (one place for the whole right-thumb cluster):
--   top:     [melee ability] [ranged ability] [aim]
--   bottom:  [slot]          [dash]           [jump]
-- Every button fires on press (MouseButton1Down), never on release.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Types =
	require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Types"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local Create = require(uiFolder:WaitForChild("Create"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))

local RangeTouchButtons = {}

export type Slot = "melee" | "ranged"
export type Handlers = {
	onAim: () -> (),
	onCast: (slot: Slot) -> (),
	onToggleSlot: () -> (),
}

local MELEE_SLOT: Slot = "melee"
local RANGED_SLOT: Slot = "ranged"
-- Purely visual, so named here.
local COLOR_ADS_OFF = Color3.fromRGB(70, 74, 84)
local COLOR_ADS_ON = Color3.fromRGB(255, 200, 87)
local COLOR_ABILITY = Color3.fromRGB(150, 110, 235)
local COLOR_SLOT = Color3.fromRGB(80, 160, 150)
local COLOR_READY = COLOR_ADS_ON
-- Caption box inside a round button: wide at the middle chord, two lines tall.
local CAPTION_WIDTH = 0.9
local CAPTION_HEIGHT = 0.62
local SECONDS_TEXT_FRACTION = 0.42
local SECONDS_STROKE_TRANSPARENCY = 0.4
local BUSY_BUTTON_TRANSPARENCY = 0.75
local BUSY_TEXT_TRANSPARENCY = 0.55
local READY_PULSE_SECONDS = 0.35
local READY_PULSE_SCALE = 0.18
local READY_STROKE_THICKNESS = 4

type AbilityButton = {
	slot: Slot,
	key: MovementController.ClusterKey,
	button: TextButton,
	scale: UIScale,
	stroke: UIStroke?,
	strokeColor: Color3,
	strokeThickness: number,
	baseTransparency: number,
	nameLabel: TextLabel,
	nameConstraint: UITextSizeConstraint,
	fill: Frame,
	secondsLabel: TextLabel,
	shownName: string,
	shownSeconds: number,
	shownFill: number,
	dimmed: boolean,
	cooling: boolean,
	pulseAt: number?,
}
type SlotButton = {
	button: TextButton,
	label: TextLabel,
	constraint: UITextSizeConstraint,
	baseTransparency: number,
	shownName: string,
	dimmed: boolean,
}

local connections: { RBXScriptConnection } = {}
local rangeGui: ScreenGui? = nil
local adsButton: TextButton? = nil
local abilityButtons: { [string]: AbilityButton } = {}
local slotButton: SlotButton? = nil

-- A scaled, wrapped caption centred in a round button: at most two short lines, never below
-- COMBAT_ABILITY_MIN_TEXT and never above the button's own text size (set on layout).
local function makeCaption(
	button: TextButton,
	name: string,
	zIndex: number
): (TextLabel, UITextSizeConstraint)
	local label = Create("TextLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(CAPTION_WIDTH, CAPTION_HEIGHT),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		Text = "",
		TextColor3 = Theme.COLOR_TEXT,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = zIndex,
		Parent = button,
	}) :: TextLabel
	local constraint = Create("UITextSizeConstraint", {
		MinTextSize = Theme.COMBAT_ABILITY_MIN_TEXT,
		MaxTextSize = Theme.COMBAT_ABILITY_MIN_TEXT,
		Parent = label,
	}) :: UITextSizeConstraint
	return label, constraint
end

local function makeAbilityButton(
	gui: ScreenGui,
	slot: Slot,
	onCast: (slot: Slot) -> ()
): AbilityButton
	local melee = slot == MELEE_SLOT
	local button = MovementController.MakeTouchButton(
		if melee then "AbilityMelee" else "AbilityRanged",
		"",
		gui
	)
	button.BackgroundColor3 = COLOR_ABILITY
	button.Visible = false
	local scale = Create("UIScale", { Parent = button }) :: UIScale
	local nameLabel, nameConstraint = makeCaption(button, "Name", 1)
	-- The "shrinking fill": a dark disc that starts as the whole button and shrinks to nothing
	-- as the cooldown runs out. Round like the button, so no corner shows past its edge.
	local fill = Create("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0, 0),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.COMBAT_ABILITY_COOLDOWN_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 2,
		Parent = button,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = fill })
	local secondsLabel = Create("TextLabel", {
		Name = "Seconds",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		Text = "",
		TextColor3 = Theme.COLOR_TEXT,
		TextStrokeTransparency = SECONDS_STROKE_TRANSPARENCY,
		Visible = false,
		ZIndex = 3,
		Parent = button,
	}) :: TextLabel
	local stroke = button:FindFirstChildOfClass("UIStroke")
	local entry: AbilityButton = {
		slot = slot,
		key = if melee then "abilityMelee" else "abilityRanged",
		button = button,
		scale = scale,
		stroke = stroke,
		strokeColor = if stroke ~= nil then stroke.Color else Theme.COLOR_TEXT,
		strokeThickness = if stroke ~= nil then stroke.Thickness else 0,
		baseTransparency = button.BackgroundTransparency,
		nameLabel = nameLabel,
		nameConstraint = nameConstraint,
		fill = fill,
		secondsLabel = secondsLabel,
		shownName = "",
		shownSeconds = -1,
		shownFill = -1,
		dimmed = false,
		cooling = false,
		pulseAt = nil,
	}
	-- Press, not release: an ability that waits for the finger to lift is a late ability.
	table.insert(
		connections,
		button.MouseButton1Down:Connect(function()
			onCast(slot)
		end)
	)
	return entry
end

local function makeSlotButton(gui: ScreenGui, onToggleSlot: () -> ()): SlotButton
	local button = MovementController.MakeTouchButton("Slot", "", gui)
	button.BackgroundColor3 = COLOR_SLOT
	local label, constraint = makeCaption(button, "Family", 1)
	table.insert(connections, button.MouseButton1Down:Connect(onToggleSlot))
	return {
		button = button,
		label = label,
		constraint = constraint,
		baseTransparency = button.BackgroundTransparency,
		shownName = "",
		dimmed = false,
	}
end

-- Reduce motion (every touch device, spec section 10) keeps the pulse, shorter and smaller.
local function motionScale(): number
	return if Theme.reducedMotion then Theme.REDUCED_MOTION_FACTOR else 1
end

local function setDimmed(
	button: TextButton,
	label: TextLabel,
	baseTransparency: number,
	dimmed: boolean
): ()
	button.BackgroundTransparency = if dimmed then BUSY_BUTTON_TRANSPARENCY else baseTransparency
	label.TextTransparency = if dimmed then BUSY_TEXT_TRANSPARENCY else 0
end

local function placeButton(
	button: GuiObject,
	viewport: Vector2,
	key: MovementController.ClusterKey
): number
	local centre, size = MovementController.ClusterRect(viewport, key)
	button.Position = UDim2.fromOffset(centre.X, centre.Y)
	button.Size = UDim2.fromOffset(size, size)
	return size
end

local function captionMax(size: number): number
	return math.max(MovementController.TextSize(size), Theme.COMBAT_ABILITY_MIN_TEXT)
end

local function layout(): ()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local viewport = camera.ViewportSize
	local ads = adsButton
	if ads ~= nil then
		ads.TextSize = MovementController.TextSize(placeButton(ads, viewport, "aim"))
	end
	for _, entry in abilityButtons do
		local size = placeButton(entry.button, viewport, entry.key)
		entry.nameConstraint.MaxTextSize = captionMax(size)
		entry.secondsLabel.TextSize = math.floor(size * SECONDS_TEXT_FRACTION)
	end
	local slot = slotButton
	if slot ~= nil then
		slot.constraint.MaxTextSize = captionMax(placeButton(slot.button, viewport, "slot"))
	end
end

-- Builds the buttons on a touch device; a no-op anywhere else and when already built.
function RangeTouchButtons.Build(handlers: Handlers): ()
	if rangeGui ~= nil or not UserInputService.TouchEnabled then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Physical-pixel offsets mirrored off Roblox's jump button; no UIScale, by design.
	local gui = Instance.new("ScreenGui")
	gui.Name = "RangeInput"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	rangeGui = gui
	local button = MovementController.MakeTouchButton("Aim", "Aim", gui)
	button.Visible = false
	adsButton = button
	table.insert(connections, button.MouseButton1Down:Connect(handlers.onAim))
	-- P3: two ability buttons and the slot button join the thumb cluster. Still no attack
	-- button: attacks stay auto-fire / auto-swing / tap-fire.
	abilityButtons[MELEE_SLOT] = makeAbilityButton(gui, MELEE_SLOT, handlers.onCast)
	abilityButtons[RANGED_SLOT] = makeAbilityButton(gui, RANGED_SLOT, handlers.onCast)
	slotButton = makeSlotButton(gui, handlers.onToggleSlot)
	layout()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		table.insert(connections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
	end
end

-- False off touch: the caller skips working out the faces.
function RangeTouchButtons.IsBuilt(): boolean
	return rangeGui ~= nil
end

-- The aim toggle shows only for a ranged weapon and lights while aiming down sights.
function RangeTouchButtons.SetAim(visible: boolean, active: boolean): ()
	local button = adsButton
	if button == nil then
		return
	end
	if button.Visible ~= visible then
		button.Visible = visible
	end
	local color = if active then COLOR_ADS_ON else COLOR_ADS_OFF
	if button.BackgroundColor3 ~= color then
		button.BackgroundColor3 = color
	end
end

-- One ability button's face. `ability` nil = the slot's family has none (hidden); `remaining`
-- = seconds until the slot is ready (the server's clock, <= 0 when ready). Polled every frame,
-- so only a change touches an instance.
function RangeTouchButtons.SetAbility(
	slot: Slot,
	ability: Types.RangeAbilityDef?,
	remaining: number,
	abilities: Types.RangeAbilitiesConfig,
	busy: boolean
): ()
	local entry = abilityButtons[slot]
	if entry == nil then
		return
	end
	local button = entry.button
	local visible = ability ~= nil
	if button.Visible ~= visible then
		button.Visible = visible
	end
	if ability == nil then
		return
	end
	if entry.shownName ~= ability.name then
		entry.shownName = ability.name
		entry.nameLabel.Text = ability.name
	end
	local cooling = remaining > abilities.earlySeconds
	local total = math.max(ability.cooldownSeconds, 0) * math.max(abilities.cooldownScale, 0)
	local share = if cooling and total > 0 then math.clamp(remaining / total, 0, 1) else 0
	if share ~= entry.shownFill then
		entry.shownFill = share
		entry.fill.Visible = share > 0
		entry.fill.Size = UDim2.fromScale(share, share)
	end
	local seconds = if cooling then math.ceil(remaining) else 0
	if seconds ~= entry.shownSeconds then
		entry.shownSeconds = seconds
		entry.secondsLabel.Visible = seconds > 0
		entry.secondsLabel.Text = if seconds > 0 then tostring(seconds) else ""
		-- While it cools, the seconds are the face; the fixed position (Q left, E right)
		-- still says which ability it is.
		entry.nameLabel.Visible = seconds <= 0
	end
	if busy ~= entry.dimmed then
		entry.dimmed = busy
		setDimmed(button, entry.nameLabel, entry.baseTransparency, busy)
	end
	if entry.cooling and not cooling then
		entry.pulseAt = os.clock()
	end
	entry.cooling = cooling
	local scaleValue = 1
	local pulsing = false
	local pulseAt = entry.pulseAt
	if pulseAt ~= nil then
		local factor = motionScale()
		local t = (os.clock() - pulseAt) / (READY_PULSE_SECONDS * factor)
		if t >= 1 then
			entry.pulseAt = nil
		else
			pulsing = true
			scaleValue = 1 + READY_PULSE_SCALE * factor * math.sin(math.pi * t)
		end
	end
	if entry.scale.Scale ~= scaleValue then
		entry.scale.Scale = scaleValue
	end
	local stroke = entry.stroke
	if stroke ~= nil then
		local color = if pulsing then COLOR_READY else entry.strokeColor
		if stroke.Color ~= color then
			stroke.Color = color
			stroke.Thickness = if pulsing then READY_STROKE_THICKNESS else entry.strokeThickness
		end
	end
end

-- The slot button names the family it switches TO: the other slot's.
function RangeTouchButtons.SetSlot(name: string, busy: boolean): ()
	local entry = slotButton
	if entry == nil then
		return
	end
	if name ~= entry.shownName then
		entry.shownName = name
		entry.label.Text = name
	end
	if busy ~= entry.dimmed then
		entry.dimmed = busy
		setDimmed(entry.button, entry.label, entry.baseTransparency, busy)
	end
end

function RangeTouchButtons.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local gui = rangeGui
	rangeGui = nil
	adsButton = nil
	table.clear(abilityButtons)
	slotButton = nil
	if gui ~= nil then
		gui:Destroy()
	end
end

return RangeTouchButtons
