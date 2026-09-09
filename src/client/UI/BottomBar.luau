--!strict
-- Bottom bar (spec §10): Build / Legacy / Shop / Settings as four ≥ 44 px tap targets,
-- centered at the bottom in both orientations. Shop is built but hidden until M4 wires
-- monetization ids (an empty shop is the same as a hidden one). Pure input: every tap
-- plays uiClick and reports its key; UIController decides which panel opens.

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type BarKey = "build" | "legacy" | "shop" | "settings"

export type BottomBarDeps = { onTap: (key: BarKey) -> () }

export type BottomBarHandle = {
	SetActive: (key: BarKey?) -> (),
	SetShopVisible: (visible: boolean) -> (),
	SetScale: (scale: number) -> (),
	Destroy: () -> (),
}

local BUTTONS: { { key: BarKey, label: string } } = {
	{ key = "build", label = "Build" },
	{ key = "legacy", label = "Legacy" },
	{ key = "shop", label = "Shop" },
	{ key = "settings", label = "Settings" },
}

local BottomBar = {}

function BottomBar.new(parent: Instance, deps: BottomBarDeps): BottomBarHandle
	local buttons: { [BarKey]: TextButton } = {}
	local shopButton: TextButton? = nil
	local connections: { RBXScriptConnection } = {}
	local activeKey: BarKey? = nil

	local width = Theme.BOTTOM_BAR_BUTTON_WIDTH * #BUTTONS + Theme.BOTTOM_BAR_GAP * (#BUTTONS - 1)
	local root = Create("Frame", {
		Name = "BottomBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.PADDING),
		Size = UDim2.fromOffset(width, Theme.BOTTOM_BAR_BUTTON_HEIGHT),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	-- Center alignment lets the hidden Shop button collapse without leaving a gap.
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
			button.BackgroundColor3 = if active then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT
			button.TextColor3 = if active then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT
		end
	end

	for index, entry in BUTTONS do
		local button = Create("TextButton", {
			Name = entry.label,
			LayoutOrder = index,
			Size = UDim2.fromOffset(Theme.BOTTOM_BAR_BUTTON_WIDTH, Theme.BOTTOM_BAR_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			Text = entry.label,
			Visible = entry.key ~= "shop",
			Parent = root,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = button })
		buttons[entry.key] = button
		if entry.key == "shop" then
			shopButton = button
		end
		table.insert(
			connections,
			button.Activated:Connect(function()
				SoundController.Play("uiClick")
				deps.onTap(entry.key)
			end)
		)
	end
	paint()

	local handle: BottomBarHandle = {
		SetActive = function(key: BarKey?)
			activeKey = key
			paint()
		end,
		SetShopVisible = function(visible: boolean)
			if shopButton ~= nil then
				shopButton.Visible = visible
			end
		end,
		SetScale = function(scale: number)
			uiScale.Scale = scale
			-- UIScale multiplies size, not position offsets, so the margin scales by hand.
			root.Position = UDim2.new(0.5, 0, 1, -Theme.PADDING * scale)
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
