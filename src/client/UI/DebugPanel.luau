--!strict
-- Studio-only debug strip (C1 contract, docs/INTERFACES.md "Hub client (ui-engineer B)").
-- It is a remote control for the levers `ArmoryService` already exposes as Workspace
-- attributes: every button fires RequestDebug(lever, value) and the server ignores the
-- intent outside Studio, so this panel carries no entitlement and grants nothing by itself.
-- UIController only builds it when RunService:IsStudio(), so a live client never has it.
--
-- Collapsed to a single "⚙ debug" tab by default: the hub HUD is the thing being tested,
-- and an expanded strip must not be what the tester is looking at. It sits above the bottom
-- bar on the left, clear of the top bar in both orientations.

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = { onLever: (lever: string, value: any) -> () }

export type DebugPanelHandle = {
	SetForceTeleportFailure: (value: boolean) -> (),
	SetLayout: (scale: number) -> (),
	Destroy: () -> (),
}

-- Design-pixel geometry. These live here rather than in Theme because the strip exists only
-- in Studio: no shipped layout depends on them (see the report's routing note if they ever
-- need to move).
local STRIP_WIDTH = 224
local TAB_WIDTH = 104
local BUTTON_WIDTH = 109 -- two columns inside STRIP_WIDTH with BUTTON_GAP between them
local BUTTON_HEIGHT = 48 -- x Theme.MIN_SCALE = the 44 physical px tap target
local BUTTON_GAP = 6
local COLUMNS = 2

-- Grant sizes are the Studio levers' own values, named in the labels so a tester never has
-- to guess what a button did. They are debug amounts, not game balance.
local CASH_GRANT = 10000
local MATERIAL_GRANT = 25
local VALOR_GRANT = 10
local FAKE_RUNS = 3

local DebugPanel = {}

function DebugPanel.new(parent: Instance, deps: Deps): DebugPanelHandle
	local connections: { RBXScriptConnection } = {}
	local expanded = false
	local forceTeleportFailure = false

	local root = Create("Frame", {
		Name = "DebugPanel",
		-- Inactive container: only the tab and the buttons take input, so the transparent
		-- area beside a collapsed tab never swallows a tap meant for the HUD behind it.
		Active = false,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.SCREEN_MARGIN, 1, -Theme.PANEL_BOTTOM_MARGIN),
		Size = UDim2.fromOffset(STRIP_WIDTH, BUTTON_HEIGHT),
		BackgroundTransparency = 1,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale

	local body = Create("Frame", {
		Name = "Body",
		Active = true, -- the sheet behind the buttons sinks taps that miss a button
		Size = UDim2.new(1, 0, 1, -BUTTON_HEIGHT - BUTTON_GAP),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = body })
	Create("UIPadding", {
		PaddingTop = UDim.new(0, BUTTON_GAP),
		PaddingBottom = UDim.new(0, BUTTON_GAP),
		PaddingLeft = UDim.new(0, BUTTON_GAP),
		PaddingRight = UDim.new(0, BUTTON_GAP),
		Parent = body,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(BUTTON_WIDTH - BUTTON_GAP, BUTTON_HEIGHT),
		CellPadding = UDim2.fromOffset(BUTTON_GAP, BUTTON_GAP),
		FillDirectionMaxCells = COLUMNS,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	local tab = Create("TextButton", {
		Name = "Tab",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(TAB_WIDTH, BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		Text = "⚙ debug",
		Parent = root,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = tab })

	local buttonCount = 0
	local function makeButton(text: string, onTap: () -> ()): TextButton
		buttonCount += 1
		local button = Create("TextButton", {
			Name = "Lever" .. tostring(buttonCount),
			LayoutOrder = buttonCount,
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextWrapped = true,
			TextScaled = true,
			Text = text,
			Parent = body,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		-- TextScaled keeps a long label inside a 109 px cell; the floor stops it going
		-- unreadable on a phone.
		Create("UITextSizeConstraint", {
			MinTextSize = Theme.ARMORY_CHIP_MIN_TEXT,
			MaxTextSize = Theme.TEXT_SMALL,
			Parent = button,
		})
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.BUTTON_TEXT_PAD),
			PaddingRight = UDim.new(0, Theme.BUTTON_TEXT_PAD),
			Parent = button,
		})
		table.insert(
			connections,
			button.Activated:Connect(function()
				SoundController.Play("uiClick")
				onTap()
			end)
		)
		return button
	end

	makeButton("Grant $10K", function()
		deps.onLever("grantCash", CASH_GRANT)
	end)
	-- The server pays the band material of the player's CURRENT era (Timber in the Village,
	-- which is the only era C1 has a mission for); the label names the common case.
	makeButton("Grant 25 Timber", function()
		deps.onLever("grantMaterials", MATERIAL_GRANT)
	end)
	makeButton("Grant 10 Valor", function()
		deps.onLever("grantValor", VALOR_GRANT)
	end)
	makeButton("Fake runs ×3", function()
		deps.onLever("fakeRuns", FAKE_RUNS)
	end)

	local teleportButton: TextButton
	local function paintTeleportButton(): ()
		teleportButton.Text = if forceTeleportFailure then "Tele fail: ON" else "Tele fail: OFF"
		teleportButton.BackgroundColor3 = if forceTeleportFailure
			then Theme.COLOR_ERROR
			else Theme.COLOR_ROW
	end
	teleportButton = makeButton("Tele fail: OFF", function()
		forceTeleportFailure = not forceTeleportFailure
		paintTeleportButton()
		deps.onLever("forceTeleportFailure", forceTeleportFailure)
	end)
	paintTeleportButton()

	local rowCount = math.ceil(buttonCount / COLUMNS)
	local bodyHeight = rowCount * BUTTON_HEIGHT
		+ math.max(rowCount - 1, 0) * BUTTON_GAP
		+ BUTTON_GAP * 2
	local expandedHeight = bodyHeight + BUTTON_GAP + BUTTON_HEIGHT

	local function setExpanded(value: boolean): ()
		expanded = value
		body.Visible = value
		root.Size = UDim2.fromOffset(STRIP_WIDTH, if value then expandedHeight else BUTTON_HEIGHT)
		tab.Text = if value then "⚙ debug ▾" else "⚙ debug"
	end
	setExpanded(false)

	table.insert(
		connections,
		tab.Activated:Connect(function()
			SoundController.Play("uiClick")
			setExpanded(not expanded)
		end)
	)

	local handle: DebugPanelHandle = {
		-- The server consumes (and resets) the teleport-failure attribute on the next
		-- Depart, so the strip is told to drop the toggle rather than lie about it.
		SetForceTeleportFailure = function(value: boolean)
			if forceTeleportFailure == value then
				return
			end
			forceTeleportFailure = value
			paintTeleportButton()
		end,
		SetLayout = function(scale: number)
			uiScale.Scale = scale
			-- UIScale multiplies size, not position offsets, so the offsets scale by hand;
			-- PANEL_BOTTOM_MARGIN is what keeps the strip clear of the bottom bar.
			root.Position =
				UDim2.new(0, Theme.SCREEN_MARGIN * scale, 1, -Theme.PANEL_BOTTOM_MARGIN * scale)
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

return DebugPanel
