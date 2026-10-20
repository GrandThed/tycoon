--!strict
-- The Armory screen's stage (docs/prompts/l3-w1-contract.md, L3-18): the selected weapon shown
-- large. W1 has no models, so this is the placeholder the study asked for (no Part blockouts):
-- the family's name large, its slot, its element chip (FIRE / ICE), a big tier ("T3"), on a
-- lighter band behind it so a model judged on it later reads against the same ground. An
-- unowned family is drawn dark, its tier the one it arrives at.
--
-- W2 puts a ViewportFrame behind this same API (new, Show, SetSize, Destroy): the screen never
-- reaches inside. A new selection pops the text in, except on low-end devices (Theme.lowEndDevice,
-- never reducedMotion, which is true on every phone).

local TweenService = game:GetService("TweenService")

local ArmoryModel = require(script.Parent:WaitForChild("ArmoryModel"))
local Create = require(script.Parent:WaitForChild("Create"))
local Motion = require(script.Parent:WaitForChild("Motion"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Stage = {
	frame: Frame,
	-- nil = nothing selected (an empty stage).
	Show: (view: ArmoryModel.Card?) -> (),
	SetSize: (width: number, height: number) -> (),
	Destroy: () -> (),
}

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

	-- One column, centred: slot word, name, the element chip, the big tier.
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
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ARMORY_SCREEN_STAGE_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = column,
	})
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

	local shown: string? = nil
	local tween: Tween? = nil

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

	local stage: Stage = {
		frame = frame,
		Show = function(view: ArmoryModel.Card?)
			if view == nil then
				shown = nil
				slot.Text = ""
				name.Text = ""
				tier.Text = ""
				chip.Visible = false
				gradient.Color = Theme.ARMORY_SCREEN_STAGE_DARK_GRADIENT
				return
			end
			local owned = view.owned
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
			gradient.Color = if owned
				then Theme.ARMORY_SCREEN_STAGE_GRADIENT
				else Theme.ARMORY_SCREEN_STAGE_DARK_GRADIENT
			stroke.Color = if owned then Theme.MAP_COLOR_PANEL_SELECTED else Theme.MAP_COLOR_LOCKED
			if shown ~= view.family then
				shown = view.family
				popIn()
			end
		end,
		SetSize = function(width: number, height: number)
			frame.Size = UDim2.fromOffset(width, height)
		end,
		Destroy = function()
			local running = tween
			if running ~= nil then
				running:Cancel()
			end
			frame:Destroy()
		end,
	}
	return stage
end

return ArmoryStage
