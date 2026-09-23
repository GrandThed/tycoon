--!strict
-- Studio-only lever strip for the Expeditions place (C1 contract, docs/INTERFACES.md
-- "Combat client" → DebugPanel). Every button sends one `RequestDebug(lever, value)`; the
-- server ignores the remote outside Studio, and CombatUIController never builds this panel
-- unless `RunService:IsStudio()`, so a live client has no such GUI at all.
--
-- The panel holds no game knowledge: the wave it increments and the gear tier it raises
-- come from the RunState and the Snapshot that CombatUIController pushes in, and the spawn
-- keys come from the mission config. Nothing here is a constant that belongs in JSON.
--
-- Geometry matches the hub's DebugPanel: 48 design px buttons (the 44 physical px tap
-- target at MIN_SCALE) wrapped into two columns. A short landscape viewport makes the body
-- SCROLL rather than shrink, because a lever that is 27 px tall is a lever no one can hit.
-- It parks in the left column between the run header and the bottom-left controls, the one
-- band no other HUD element uses in either orientation, and collapses to a single tab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Deps = { onLever: (lever: string, value: any) -> () }

export type DebugPanelHandle = {
	SetMission: (mission: Types.MissionConfig?) -> (),
	SetWave: (wave: number) -> (),
	SetGear: (melee: number, ranged: number) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

-- Mirrors CombatHud's own stacking so the strip lands in the gap between them: the header
-- block it starts below, and the HP + Ready/Return column it must stay above.
local HEADER_BLOCK = Theme.TOP_BAR_HEIGHT
	+ Theme.COMBAT_WALLET_HEIGHT
	+ Theme.COMBAT_BOSS_LABEL_HEIGHT
	+ Theme.COMBAT_BOSS_BAR_HEIGHT
	+ Theme.SCREEN_MARGIN * 3
local BOTTOM_BLOCK = Theme.PADDING
	+ Theme.COMBAT_HP_LABEL_HEIGHT
	+ Theme.COMBAT_HP_BAR_HEIGHT
	+ Theme.ROW_SPACING
	+ Theme.ROW_BUTTON_HEIGHT
	+ Theme.COMBAT_CONTROL_GAP
local CELL_WIDTH = (
	Theme.COMBAT_DEBUG_WIDTH
	- Theme.COMBAT_DEBUG_GAP * 3
	- Theme.SCROLLBAR_THICKNESS
) / Theme.COMBAT_DEBUG_COLUMNS

local DebugPanel = {}

function DebugPanel.new(parent: Instance, deps: Deps): DebugPanelHandle
	local connections: { RBXScriptConnection } = {}
	local spawnButtons: { TextButton } = {}
	local wave = 0
	local meleeTier = 0
	local rangedTier = 0
	local godMode = false
	local bots = 0

	local root = Create("Frame", {
		Name = "DebugPanel",
		-- Inactive container: only the tab and the buttons take input, so the transparent
		-- area beside a collapsed tab never swallows a tap meant for the HUD behind it.
		Active = false,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(Theme.SCREEN_MARGIN, Theme.SCREEN_MARGIN),
		Size = UDim2.fromOffset(Theme.COMBAT_DEBUG_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = root }) :: UIScale
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = root,
	})

	-- ScrollingFrame, not an auto-sized Frame: SetLayout gives it whatever height the band
	-- allows and the canvas scrolls past that, so the buttons keep their full size.
	local body = Create("ScrollingFrame", {
		Name = "Body",
		LayoutOrder = 2,
		Active = true, -- the sheet behind the buttons sinks taps that miss a button
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_DEBUG_ROW_HEIGHT),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = root,
	}) :: ScrollingFrame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = body })
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		PaddingBottom = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		PaddingLeft = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		PaddingRight = UDim.new(0, Theme.COMBAT_DEBUG_GAP),
		Parent = body,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL_WIDTH, Theme.COMBAT_DEBUG_ROW_HEIGHT),
		CellPadding = UDim2.fromOffset(Theme.COMBAT_DEBUG_GAP, Theme.COMBAT_DEBUG_GAP),
		FillDirectionMaxCells = Theme.COMBAT_DEBUG_COLUMNS,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	local order = 0
	local function leverButton(text: string, onClick: (TextButton) -> ()): TextButton
		order += 1
		local button = Create("TextButton", {
			Name = "Lever" .. tostring(order),
			LayoutOrder = order,
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Font = Theme.FONT,
			TextSize = Theme.COMBAT_DEBUG_TEXT,
			TextColor3 = Theme.COLOR_TEXT,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
			ZIndex = Theme.ZINDEX_CARD,
			Parent = body,
		}) :: TextButton
		Create("UICorner", {
			CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS),
			Parent = button,
		})
		table.insert(
			connections,
			button.Activated:Connect(function()
				onClick(button)
			end)
		)
		return button
	end

	-- The tab stays a full tap target so a phone in the Studio emulator can open it.
	local toggle = Create("TextButton", {
		Name = "Toggle",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(Theme.COMBAT_DEBUG_TOGGLE_SIZE * 2, Theme.COMBAT_DEBUG_TOGGLE_SIZE),
		BackgroundColor3 = Theme.COLOR_HIGHLIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_DEBUG_TEXT,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "⚙ debug",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = root,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = toggle })
	table.insert(
		connections,
		toggle.Activated:Connect(function()
			body.Visible = not body.Visible
		end)
	)

	-- Labels are short because a cell is half the strip: the lever each one drives is named
	-- in the RequestDebug call, not in the caption.
	leverButton("Wave +1", function()
		deps.onLever("wave", wave + 1)
	end)
	-- Spawn buttons are created up front and named from the mission config, so the enemy
	-- keys stay in JSON where they belong.
	for _ = 1, Theme.COMBAT_DEBUG_MAX_SPAWN_KEYS do
		local button = leverButton("Spawn —", function(source: TextButton)
			local key = source:GetAttribute("EnemyKey")
			if typeof(key) == "string" then
				deps.onLever("spawn", key)
			end
		end)
		button.Visible = false
		table.insert(spawnButtons, button)
	end
	local godButton = leverButton("God: off", function(source: TextButton)
		godMode = not godMode
		source.Text = if godMode then "God: ON" else "God: off"
		deps.onLever("godMode", godMode)
	end)
	godButton.Name = "God"
	leverButton("Kill all", function()
		deps.onLever("killAll", 1)
	end)
	leverButton("Melee +1", function()
		deps.onLever("setGear", "melee=" .. tostring(meleeTier + 1))
	end)
	leverButton("Ranged +1", function()
		deps.onLever("setGear", "ranged=" .. tostring(rangedTier + 1))
	end)
	leverButton("Bots +1", function()
		bots += 1
		deps.onLever("bots", bots)
	end)
	leverButton("Bots −1", function()
		bots = math.max(bots - 1, 0)
		deps.onLever("bots", bots)
	end)
	leverButton("+" .. tostring(Theme.COMBAT_DEBUG_GRANT_MATERIALS) .. " mat", function()
		deps.onLever("grantMaterials", Theme.COMBAT_DEBUG_GRANT_MATERIALS)
	end)
	leverButton("+" .. tostring(Theme.COMBAT_DEBUG_GRANT_VALOR) .. " Valor", function()
		deps.onLever("grantValor", Theme.COMBAT_DEBUG_GRANT_VALOR)
	end)
	-- C2: runs the server's CheckAdmission for this player and toasts the verdict; nobody
	-- is sent home.
	leverButton("Admit check", function()
		deps.onLever("admitCheck", true)
	end)

	local handle: DebugPanelHandle = {
		SetMission = function(mission: Types.MissionConfig?)
			local keys: { string } = {}
			if mission ~= nil then
				for key in mission.enemies do
					table.insert(keys, key)
				end
				-- Sorted so the buttons never swap places between two identical sessions.
				table.sort(keys)
			end
			for index, button in spawnButtons do
				local key = keys[index]
				button.Visible = key ~= nil
				if key ~= nil then
					button:SetAttribute("EnemyKey", key)
					button.Text = "Spawn " .. key
				end
			end
		end,
		SetWave = function(nextWave: number)
			wave = nextWave
		end,
		SetGear = function(melee: number, ranged: number)
			meleeTier = melee
			rangedTier = ranged
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			uiScale.Scale = scale
			-- The band between the run header and the bottom-left controls, in design px.
			local designHeight = viewportSize.Y / scale
			local top = Theme.SCREEN_MARGIN + HEADER_BLOCK
			local band = designHeight - BOTTOM_BLOCK - top
			local rows = math.ceil(order / Theme.COMBAT_DEBUG_COLUMNS)
			local natural = rows * Theme.COMBAT_DEBUG_ROW_HEIGHT
				+ (rows - 1) * Theme.COMBAT_DEBUG_GAP
				+ Theme.COMBAT_DEBUG_GAP * 2
			local room = band - Theme.COMBAT_DEBUG_TOGGLE_SIZE - Theme.COMBAT_DEBUG_GAP
			-- One row is the floor: a viewport too short for even that scrolls the rest.
			local height =
				math.clamp(math.min(natural, room), Theme.COMBAT_DEBUG_ROW_HEIGHT, natural)
			body.Size = UDim2.new(1, 0, 0, height)
			root.Position = UDim2.fromOffset(Theme.SCREEN_MARGIN * scale, top * scale)
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
