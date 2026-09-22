--!strict
-- Expedition HUD (C0 contract, docs/INTERFACES.md "Combat client"). Top: mission name,
-- "Lobby" or "Wave 3 / 10", and the director's tempo as a coloured dot. Bottom-left: the
-- local character's HP, read from the Humanoid the server sized with Armory.MaxHp — the
-- client never computes max HP. Party rows mirror RunState.party. Ready exists in the lobby
-- only; Return is always there, because a player who cannot leave is stuck.
--
-- Display and input only: the two buttons fire RequestReady / RequestLeave with no payload.
-- No combat input exists in C0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = { onReady: () -> (), onLeave: () -> () }

export type CombatHudHandle = {
	SetMission: (name: string) -> (),
	SetRunState: (run: Types.RunState) -> (),
	SetHealth: (health: number, maxHealth: number) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

type PartyRow = { frame: Frame, nameLabel: TextLabel, fill: Frame }

local BLANK = "—"
local LOBBY_TEXT = "Lobby"

local CombatHud = {}

function CombatHud.new(parent: Instance, deps: Deps): CombatHudHandle
	local connections: { RBXScriptConnection } = {}
	local partyRows: { PartyRow } = {}

	local function bar(parentFrame: Frame, name: string, height: number): Frame
		local track = Create("Frame", {
			Name = name,
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, height),
			Parent = parentFrame,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = track })
		local fill = Create("Frame", {
			Name = "Fill",
			BackgroundColor3 = Theme.COLOR_ACCENT,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = track,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = fill })
		return fill
	end

	-- Top strip: same silhouette as the hub's top bar so the two places read as one game.
	local topFrame = Create("Frame", {
		Name = "RunHeader",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.SCREEN_MARGIN),
		Size = UDim2.fromOffset(Theme.TOP_BAR_WIDTH, Theme.TOP_BAR_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = topFrame })
	local topScale = Create("UIScale", { Parent = topFrame }) :: UIScale
	local missionLabel = Create("TextLabel", {
		Name = "Mission",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.new(1, -14 - Theme.COMBAT_TEMPO_DOT_SIZE - Theme.SCREEN_MARGIN * 3, 0, 24),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_LARGE,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = BLANK,
		Parent = topFrame,
	}) :: TextLabel
	local waveLabel = Create("TextLabel", {
		Name = "Wave",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 33),
		Size = UDim2.new(1, -14 - Theme.COMBAT_TEMPO_DOT_SIZE - Theme.SCREEN_MARGIN * 3, 0, 16),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = LOBBY_TEXT,
		Parent = topFrame,
	}) :: TextLabel
	local tempoDot = Create("Frame", {
		Name = "Tempo",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Theme.SCREEN_MARGIN * 2, 0.5, 0),
		Size = UDim2.fromOffset(Theme.COMBAT_TEMPO_DOT_SIZE, Theme.COMBAT_TEMPO_DOT_SIZE),
		BackgroundColor3 = Theme.COLOR_TEXT_DIM,
		BorderSizePixel = 0,
		Parent = topFrame,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = tempoDot })

	-- Party list: one row per member with the HP the server published for them.
	local partyFrame = Create("Frame", {
		Name = "Party",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.SCREEN_MARGIN, 0, Theme.SCREEN_MARGIN),
		Size = UDim2.fromOffset(Theme.COMBAT_PARTY_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local partyScale = Create("UIScale", { Parent = partyFrame }) :: UIScale
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ROW_SPACING),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = partyFrame,
	})

	-- Local HP: the one number the player watches, so it gets the bottom-left corner.
	local hpFrame = Create("Frame", {
		Name = "Health",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.SCREEN_MARGIN, 1, -Theme.PADDING),
		Size = UDim2.fromOffset(
			Theme.COMBAT_HP_BAR_WIDTH,
			Theme.COMBAT_HP_LABEL_HEIGHT + Theme.COMBAT_HP_BAR_HEIGHT
		),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local hpScale = Create("UIScale", { Parent = hpFrame }) :: UIScale
	local hpLabel = Create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_HP_LABEL_HEIGHT),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "HP " .. BLANK,
		Parent = hpFrame,
	}) :: TextLabel
	local hpTrack = Create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, Theme.COMBAT_HP_LABEL_HEIGHT),
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_HP_BAR_HEIGHT),
		BackgroundTransparency = 1,
		Parent = hpFrame,
	}) :: Frame
	local hpFill = bar(hpTrack, "Bar", Theme.COMBAT_HP_BAR_HEIGHT)

	local buttonRow = Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.SCREEN_MARGIN, 1, -Theme.PADDING),
		Size = UDim2.fromOffset(
			Theme.ROW_BUTTON_WIDTH * 2 + Theme.ROW_SPACING,
			Theme.ROW_BUTTON_HEIGHT
		),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local buttonScale = Create("UIScale", { Parent = buttonRow }) :: UIScale
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, Theme.ROW_SPACING),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttonRow,
	})

	local function actionButton(name: string, order: number, accent: boolean): TextButton
		local button = Create("TextButton", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.fromOffset(Theme.ROW_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = if accent then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_HEADER,
			TextColor3 = if accent then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT,
			Text = name,
			Parent = buttonRow,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = button })
		return button
	end

	local returnButton = actionButton("Return", 2, false)
	local readyButton = actionButton("Ready", 1, true)
	readyButton.Visible = false

	local function makePartyRow(index: number): PartyRow
		local frame = Create("Frame", {
			Name = "Member" .. tostring(index),
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, Theme.COMBAT_PARTY_ROW_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG,
			BackgroundTransparency = Theme.BG_TRANSPARENCY,
			BorderSizePixel = 0,
			Visible = false,
			Parent = partyFrame,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, Theme.BUTTON_TEXT_PAD),
			PaddingRight = UDim.new(0, Theme.BUTTON_TEXT_PAD),
			PaddingTop = UDim.new(0, Theme.BUTTON_TEXT_PAD),
			Parent = frame,
		})
		local nameLabel = Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, Theme.COMBAT_PARTY_NAME_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		local track = Create("Frame", {
			Name = "Track",
			Position = UDim2.fromOffset(0, Theme.COMBAT_PARTY_NAME_HEIGHT),
			Size = UDim2.new(1, 0, 0, Theme.COMBAT_PARTY_BAR_HEIGHT),
			BackgroundTransparency = 1,
			Parent = frame,
		}) :: Frame
		return {
			frame = frame,
			nameLabel = nameLabel,
			fill = bar(track, "Bar", Theme.COMBAT_PARTY_BAR_HEIGHT),
		}
	end

	local function setHealth(health: number, maxHealth: number): ()
		if maxHealth <= 0 then
			hpLabel.Text = "HP " .. BLANK
			hpFill.Size = UDim2.fromScale(0, 1)
			return
		end
		local fraction = math.clamp(health / maxHealth, 0, 1)
		hpLabel.Text = "HP " .. Format.Cash(health) .. " / " .. Format.Cash(maxHealth)
		hpFill.Size = UDim2.fromScale(fraction, 1)
		-- Colour is the warning, since a thin bar is hard to read on a phone.
		hpFill.BackgroundColor3 = if fraction <= 0.25
			then Theme.COLOR_ERROR
			elseif fraction <= 0.5 then Theme.COLOR_HIGHLIGHT
			else Theme.COLOR_ACCENT
	end

	local function setRunState(run: Types.RunState): ()
		local phase = run.phase
		waveLabel.Text = if phase == "lobby"
			then LOBBY_TEXT
			elseif phase == "summary" or phase == "ended" then "Run over"
			elseif phase == "breather" then "Breather — wave "
				.. tostring(run.wave)
				.. " / "
				.. tostring(run.waves)
			else "Wave " .. tostring(run.wave) .. " / " .. tostring(run.waves)
		readyButton.Visible = phase == "lobby"
		tempoDot.BackgroundColor3 = if run.tempo >= Theme.COMBAT_TEMPO_HOT
			then Theme.COLOR_ERROR
			elseif run.tempo <= Theme.COMBAT_TEMPO_CALM then Theme.COLOR_ACCENT_ALT
			else Theme.COLOR_ACCENT

		local shown = 0
		for _, member in run.party do
			if typeof(member) ~= "table" or typeof(member.name) ~= "string" then
				continue
			end
			shown += 1
			local row = partyRows[shown]
			if row == nil then
				row = makePartyRow(shown)
				partyRows[shown] = row
			end
			-- The lobby is the only phase where "ready" means anything to look at.
			row.nameLabel.Text = if phase == "lobby" and member.ready
				then member.name .. " ✓"
				else member.name
			local maxHp = member.maxHp
			row.fill.Size =
				UDim2.fromScale(if maxHp > 0 then math.clamp(member.hp / maxHp, 0, 1) else 0, 1)
			row.frame.Visible = true
		end
		for index = shown + 1, #partyRows do
			partyRows[index].frame.Visible = false
		end
	end

	table.insert(
		connections,
		readyButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onReady()
		end)
	)
	table.insert(
		connections,
		returnButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onLeave()
		end)
	)

	local handle: CombatHudHandle = {
		SetMission = function(name: string)
			missionLabel.Text = name
		end,
		SetRunState = setRunState,
		SetHealth = setHealth,
		SetLayout = function(scale: number, viewportSize: Vector2)
			topScale.Scale = scale
			partyScale.Scale = scale
			hpScale.Scale = scale
			buttonScale.Scale = scale
			-- UIScale multiplies size, not position offsets, so margins scale by hand.
			local margin = Theme.SCREEN_MARGIN * scale
			local bottom = Theme.PADDING * scale
			local landscape = viewportSize.X > viewportSize.Y
			if landscape then
				topFrame.AnchorPoint = Vector2.new(0, 0)
				topFrame.Position = UDim2.fromOffset(margin, margin)
			else
				topFrame.AnchorPoint = Vector2.new(0.5, 0)
				topFrame.Position = UDim2.new(0.5, 0, 0, margin)
			end
			-- Portrait centres the top strip, so the party list has to start below it;
			-- landscape parks it top-left and the list can sit beside it.
			local partyTop = if landscape
				then margin
				else (Theme.SCREEN_MARGIN * 2 + Theme.TOP_BAR_HEIGHT) * scale
			partyFrame.Position = UDim2.new(1, -margin, 0, partyTop)
			buttonRow.Position = UDim2.new(1, -margin, 1, -bottom)
			-- One line only when the HP block and both buttons actually fit side by side.
			local needed = Theme.COMBAT_HP_BAR_WIDTH
				+ Theme.COMBAT_HP_BUTTONS_GAP
				+ Theme.ROW_BUTTON_WIDTH * 2
				+ Theme.ROW_SPACING
				+ Theme.SCREEN_MARGIN * 2
			local fits = viewportSize.X / scale >= needed
			hpFrame.Position = if fits
				then UDim2.new(0, margin, 1, -bottom)
				else UDim2.new(
					0,
					margin,
					1,
					-bottom - (Theme.ROW_BUTTON_HEIGHT + Theme.ROW_SPACING) * scale
				)
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			topFrame:Destroy()
			partyFrame:Destroy()
			hpFrame:Destroy()
			buttonRow:Destroy()
		end,
	}
	return handle
end

return CombatHud
