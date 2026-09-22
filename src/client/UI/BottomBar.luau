--!strict
-- Bottom bar (spec §10): Build / Armory / Expedition / Legacy / Shop / Settings as ≥ 44 px
-- tap targets, centered at the bottom in both orientations. Shop (M4), Armory and
-- Expedition (C0) are built but hidden until their config exists — an empty feature is the
-- same as a hidden one. Six keys no longer fit a 375 px portrait canvas at the M3 button
-- width, so a button is now an icon glyph over a word that scales down instead of
-- truncating, and the width is derived from how many keys are actually visible. Pure input:
-- every tap plays uiClick and reports its key; UIController decides which panel opens.

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type BarKey = "build" | "armory" | "expedition" | "legacy" | "shop" | "settings"

export type BottomBarDeps = { onTap: (key: BarKey) -> () }

export type BottomBarHandle = {
	SetActive: (key: BarKey?) -> (),
	-- M5: the whole bar stays hidden until a model exists (nothing to build, spend, or
	-- configure while a save is loading or failed to load).
	SetVisible: (visible: boolean) -> (),
	SetKeyVisible: (key: BarKey, visible: boolean) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

type Button = { root: TextButton, icon: TextLabel, label: TextLabel }

local BUTTONS: { { key: BarKey, icon: string, label: string } } = {
	{ key = "build", icon = "🔨", label = "Build" },
	{ key = "armory", icon = "⚔", label = "Armory" },
	{ key = "expedition", icon = "🗺", label = "Expedition" },
	{ key = "legacy", icon = "★", label = "Legacy" },
	{ key = "shop", icon = "🛒", label = "Shop" },
	{ key = "settings", icon = "⚙", label = "Settings" },
}

-- Keys whose feature has to be switched on by config before the button means anything.
local HIDDEN_UNTIL_CONFIGURED: { [string]: boolean } = {
	shop = true,
	armory = true,
	expedition = true,
}

local BottomBar = {}

function BottomBar.new(parent: Instance, deps: BottomBarDeps): BottomBarHandle
	local buttons: { [BarKey]: Button } = {}
	local connections: { RBXScriptConnection } = {}
	local activeKey: BarKey? = nil
	-- Last layout inputs, replayed whenever a key's visibility changes the button widths.
	local lastScale = 1
	local lastViewport = Vector2.new(Theme.DESIGN_WIDTH, Theme.DESIGN_HEIGHT)

	local root = Create("Frame", {
		Name = "BottomBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.PADDING),
		Size = UDim2.fromOffset(0, Theme.BOTTOM_BAR_BUTTON_HEIGHT),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	-- Center alignment lets a hidden button collapse without leaving a gap.
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, Theme.BOTTOM_BAR_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})

	local function paint(): ()
		for key, button in buttons do
			local active = key == activeKey
			button.root.BackgroundColor3 = if active
				then Theme.COLOR_ACCENT
				else Theme.COLOR_BG_LIGHT
			local textColor = if active then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT
			button.icon.TextColor3 = textColor
			button.label.TextColor3 = textColor
		end
	end

	-- The bar is centered and never wider than the viewport: with six keys on a 375 px
	-- portrait canvas each button lands at 54 design px, and the clamp floor keeps the tap
	-- target at 44 physical px on the narrowest phone Roblox ships on.
	local function relayout(): ()
		uiScale.Scale = lastScale
		-- UIScale multiplies size, not position offsets, so the margin scales by hand.
		root.Position = UDim2.new(0.5, 0, 1, -Theme.PADDING * lastScale)
		local visibleCount = 0
		for _, entry in BUTTONS do
			if buttons[entry.key].root.Visible then
				visibleCount += 1
			end
		end
		if visibleCount == 0 then
			root.Size = UDim2.fromOffset(0, Theme.BOTTOM_BAR_BUTTON_HEIGHT)
			return
		end
		local gaps = Theme.BOTTOM_BAR_GAP * (visibleCount - 1)
		local available = lastViewport.X / lastScale - Theme.SCREEN_MARGIN * 2
		local width = math.floor(
			math.clamp(
				(available - gaps) / visibleCount,
				Theme.BOTTOM_BAR_BUTTON_MIN_WIDTH,
				Theme.BOTTOM_BAR_BUTTON_WIDTH
			)
		)
		for _, entry in BUTTONS do
			buttons[entry.key].root.Size = UDim2.fromOffset(width, Theme.BOTTOM_BAR_BUTTON_HEIGHT)
		end
		root.Size = UDim2.fromOffset(width * visibleCount + gaps, Theme.BOTTOM_BAR_BUTTON_HEIGHT)
	end

	for index, entry in BUTTONS do
		local button = Create("TextButton", {
			Name = entry.label,
			LayoutOrder = index,
			Size = UDim2.fromOffset(Theme.BOTTOM_BAR_BUTTON_WIDTH, Theme.BOTTOM_BAR_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Text = "",
			Visible = not HIDDEN_UNTIL_CONFIGURED[entry.key],
			Parent = root,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = button })
		local icon = Create("TextLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, Theme.BOTTOM_BAR_ICON_Y),
			Size = UDim2.new(1, 0, 0, Theme.BOTTOM_BAR_ICON_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_HEADER,
			TextColor3 = Theme.COLOR_TEXT,
			Text = entry.icon,
			Parent = button,
		}) :: TextLabel
		local label = Create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, Theme.BOTTOM_BAR_LABEL_Y),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.BOTTOM_BAR_LABEL_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			-- "Expedition" is wider than a 54 px button at TEXT_SMALL; shrink the word
			-- (bounded) rather than cut a key's name in half.
			TextScaled = true,
			Text = entry.label,
			Parent = button,
		}) :: TextLabel
		Create("UITextSizeConstraint", {
			MinTextSize = Theme.BOTTOM_BAR_LABEL_MIN_TEXT,
			MaxTextSize = Theme.TEXT_SMALL,
			Parent = label,
		})
		buttons[entry.key] = { root = button, icon = icon, label = label }
		table.insert(
			connections,
			button.Activated:Connect(function()
				SoundController.Play("uiClick")
				deps.onTap(entry.key)
			end)
		)
	end
	paint()
	relayout()

	local handle: BottomBarHandle = {
		SetActive = function(key: BarKey?)
			activeKey = key
			paint()
		end,
		SetVisible = function(visible: boolean)
			root.Visible = visible
		end,
		SetKeyVisible = function(key: BarKey, visible: boolean)
			local button = buttons[key]
			if button == nil then
				return
			end
			button.root.Visible = visible
			relayout() -- one fewer key means wider buttons for everyone else
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			lastScale = scale
			lastViewport = viewportSize
			relayout()
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			root:Destroy()
		end,
	}
	return handle
end

return BottomBar
