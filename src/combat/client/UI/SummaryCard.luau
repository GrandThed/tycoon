--!strict
-- Run summary card (C1 contract, docs/INTERFACES.md "Combat client"), rewritten for levels
-- (docs/INTERFACES.md "L1 contracts" -> Client). Shown for a RunState that carries a `result`:
-- the level and its difficulty, how the run ended, how far it got, what it paid, and where the
-- party goes next. Every number is the server's. L1b: every kill pays the moment it falls, so
-- the rows are every kill of the run, a lost run included, and there is no "Saved at" line.
-- Nothing is computed here; a missing summary renders dashes rather than inventing numbers.
--
-- Every run ends in the lobby camp, never in the city (ruling 20): the countdown reads "Back
-- to camp in 8". Back to camp ends the wait at once (the leader or a solo player; ruling 21),
-- and Return to your city goes home alone (ruling 22; not offered in a proving build, where
-- the trip home kicks from Studio).
--
-- A result whose reason is `leave` is the trip home itself: the title is the map's name, the
-- rows are the session's totals, and there is no countdown and no button.
--
-- The card must fit a 640x360 phone under a 58 px top bar (329 design px of height), with a
-- party's two extra lines: so the lines sit COMBAT_SUMMARY_LINE_GAP apart and the two buttons
-- share one row. On that phone a solo card is about 250 design px tall and a party's 292
-- (L1b took the "Saved at" line out).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = {
	-- "Back to camp": RequestAbandon during the summary.
	onBack: () -> (),
	-- "Return to your city": RequestLeave.
	onReturn: () -> (),
	-- false = no Return button (a proving build).
	canReturn: boolean,
}

-- What the RunState round the result adds. `canBack` = the local player may end the wait (the
-- leader, or the only human). `waves` = the waves of the level's one camp, for a level whose
-- progress is counted in waves. `difficultyName` and `mapName` are the map's display names.
export type ShowInfo = {
	partySize: number,
	returnIn: number?,
	canBack: boolean,
	waves: number,
	difficultyName: string,
	mapName: string,
}

export type SummaryCardHandle = {
	Show: (summary: Types.RunSummary?, result: Types.RunResult, info: ShowInfo) -> (),
	Hide: () -> (),
	IsVisible: () -> boolean,
	-- True while Back to camp is offered: the host's Enter key asks before it sends.
	CanBack: () -> boolean,
	SetScale: (scale: number) -> (),
	Destroy: () -> (),
}

local BLANK = "—"
local PERCENT = 100
local STAR = "★ "
local BACK_TEXT = "Back to camp"
local RETURN_TEXT = "Return to your city"
local COUNTDOWN_TEXT = "Back to camp in "
-- Keyboards only, and only for whoever may end the wait: the key the host binds to it.
local BACK_KEY_HINT = " · Enter to go now"
local LEAVE_REASON = "leave"
-- How a run ended, in the player's words. An unknown reason shows nothing rather than a guess.
local REASON_TEXT: { [string]: string } = {
	cleared = "Cleared",
	down = "You went down",
	wipe = "You went down",
	abandoned = "Abandoned",
	runCap = "Out of time",
}

local SummaryCard = {}

function SummaryCard.new(parent: Instance, deps: Deps): SummaryCardHandle
	local connections: { RBXScriptConnection } = {}

	-- A Frame, not a TextButton: the dim must never swallow the camera drag behind it.
	local scrim = Create("Frame", {
		Name = "SummaryCard",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = Theme.LOAD_SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame

	local card = Create("Frame", {
		Name = "Card",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.COMBAT_SUMMARY_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.COLOR_BG,
		BorderSizePixel = 0,
		Parent = scrim,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = card })
	local uiScale = Create("UIScale", { Parent = card }) :: UIScale
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingBottom = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingLeft = UDim.new(0, Theme.DIALOG_PADDING),
		PaddingRight = UDim.new(0, Theme.DIALOG_PADDING),
		Parent = card,
	})
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.COMBAT_SUMMARY_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = card,
	})

	local order = 0
	local function line(name: string, font: Enum.Font, size: number, color: Color3): TextLabel
		order += 1
		return Create("TextLabel", {
			Name = name,
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			Parent = card,
		}) :: TextLabel
	end

	-- Both buttons share one row at the foot of the card; one alone takes all of it.
	local buttonRow: Frame
	local function button(name: string, slot: number, accent: boolean): TextButton
		local item = Create("TextButton", {
			Name = name,
			LayoutOrder = slot,
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = if accent then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.COMBAT_RUN_BUTTON_TEXT,
			TextColor3 = if accent then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT,
			TextWrapped = true,
			Text = "",
			Visible = false,
			Parent = buttonRow,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = item })
		return item
	end

	local titleLabel = line("Title", Theme.FONT_BOLD, Theme.TEXT_LARGE, Theme.COLOR_TEXT)
	local outcomeLabel = line("Outcome", Theme.FONT_BOLD, Theme.TEXT_MEDIUM, Theme.COLOR_TEXT)
	local progressLabel = line("Progress", Theme.FONT, Theme.TEXT_MEDIUM, Theme.COLOR_TEXT)
	local killsLabel = line("Kills", Theme.FONT, Theme.TEXT_MEDIUM, Theme.COLOR_TEXT)
	local rewardLabel = line("Reward", Theme.FONT, Theme.TEXT_MEDIUM, Theme.COLOR_ACCENT)
	local materialsLabel = line("Materials", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	-- C2 lines, each hidden when it does not apply.
	local shareLabel = line("Share", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT)
	local mentorLabel = line("Mentor", Theme.FONT_BOLD, Theme.TEXT_SMALL, Theme.COLOR_HIGHLIGHT)
	local countdownLabel =
		line("Countdown", Theme.FONT_BOLD, Theme.TEXT_SMALL, Theme.COLOR_ACCENT_ALT)
	order += 1
	buttonRow = Create("Frame", {
		Name = "Buttons",
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.DIALOG_BUTTON_HEIGHT),
		Visible = false,
		Parent = card,
	}) :: Frame
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.DIALOG_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = buttonRow,
	})
	local backButton = button("Back", 1, true)
	backButton.Text = BACK_TEXT
	local returnButton = button("Return", 2, false)
	returnButton.Text = RETURN_TEXT
	local keyHint = if UserInputService.KeyboardEnabled then BACK_KEY_HINT else ""
	local canBack = false

	local function showButtons(back: boolean, home: boolean): ()
		canBack = back
		backButton.Visible = back
		returnButton.Visible = home
		buttonRow.Visible = back or home
		local size = if back and home
			then UDim2.new(0.5, -Theme.DIALOG_LINE_GAP / 2, 1, 0)
			else UDim2.fromScale(1, 1)
		backButton.Size = size
		returnButton.Size = size
	end

	-- os.clock() the party is due back in the camp; nil while no return is pending. The
	-- countdown ticks locally between RunStates and every RunState re-anchors it.
	local returnAt: number? = nil
	local tickAccumulator = 0

	local function paintCountdown(): ()
		local dueAt = returnAt
		if dueAt == nil then
			countdownLabel.Visible = false
			return
		end
		local left = math.max(math.ceil(dueAt - os.clock()), 0)
		countdownLabel.Text = COUNTDOWN_TEXT
			.. Format.Duration(left)
			.. (if canBack then keyHint else "")
		countdownLabel.Visible = true
	end

	local function paintRewards(summary: Types.RunSummary?, partySize: number): ()
		if summary == nil then
			killsLabel.Text = "Kills " .. BLANK
			rewardLabel.Text = ""
			materialsLabel.Text = ""
			shareLabel.Visible = false
			mentorLabel.Visible = false
			return
		end
		-- C2 fields are read defensively so an older server's summary still renders.
		local share = (summary :: any).damageShare
		shareLabel.Visible = partySize > 1 and typeof(share) == "number"
		if typeof(share) == "number" then
			shareLabel.Text = "Your damage share "
				.. Format.Cash(math.round(math.clamp(share, 0, 1) * PERCENT))
				.. "%"
		end
		local mentorValor = (summary :: any).mentorValor
		local mentoring = typeof(mentorValor) == "number" and mentorValor > 0
		mentorLabel.Visible = mentoring
		if mentoring then
			mentorLabel.Text = "Mentor bonus +"
				.. Format.Cash(mentorValor)
				.. " Valor (included above)"
		end
		killsLabel.Text = "Kills "
			.. Format.Cash(summary.kills)
			.. " · "
			.. Format.Duration(summary.seconds)
		rewardLabel.Text = "+$"
			.. Format.Cash(summary.cash)
			.. " · "
			.. Format.Cash(summary.valor)
			.. " Valor"
		-- Sorted BY MATERIAL NAME, the same ordering the hub's ExpeditionSummaryCard uses: the
		-- table arrives over the network, so its iteration order is undefined and the same
		-- run would otherwise read differently twice.
		local names: { string } = {}
		for material, amount in summary.materials do
			if typeof(material) == "string" and typeof(amount) == "number" and amount > 0 then
				table.insert(names, material)
			end
		end
		table.sort(names)
		local parts: { string } = {}
		for _, material in names do
			table.insert(parts, Format.Cash(summary.materials[material]) .. " " .. material)
		end
		materialsLabel.Text = if #parts > 0 then table.concat(parts, " · ") else "No materials"
	end

	local function show(summary: Types.RunSummary?, result: Types.RunResult, info: ShowInfo): ()
		local leaving = result.reason == LEAVE_REASON
		paintRewards(summary, info.partySize)
		if leaving then
			-- The trip home: the session's totals under the map's name, and nothing to press.
			titleLabel.Text = info.mapName
			outcomeLabel.Visible = false
			progressLabel.Visible = false
			returnAt = nil
			showButtons(false, false)
			paintCountdown()
			scrim.Visible = true
			return
		end
		titleLabel.Text = if info.difficultyName ~= ""
			then result.levelName .. " · " .. info.difficultyName
			else result.levelName
		local cleared = result.reason == "cleared"
		local reasonText = REASON_TEXT[result.reason]
		outcomeLabel.Visible = reasonText ~= nil
		if reasonText ~= nil then
			outcomeLabel.Text = if result.star then STAR .. reasonText else reasonText
			outcomeLabel.TextColor3 = if cleared
				then (if result.star then Theme.COLOR_HIGHLIGHT else Theme.COLOR_ACCENT)
				elseif result.reason == "down" or result.reason == "wipe" then Theme.COLOR_ERROR
				else Theme.COLOR_TEXT_DIM
		end
		-- A level of several camps counts camps; a level of one camp (the arena) counts waves.
		progressLabel.Visible = true
		if result.camps > 1 then
			progressLabel.Text = "Camps cleared "
				.. Format.Cash(result.campsCleared)
				.. " / "
				.. Format.Cash(result.camps)
		elseif summary ~= nil and info.waves > 0 then
			progressLabel.Text = "Waves cleared "
				.. Format.Cash(summary.wavesCleared)
				.. " / "
				.. Format.Cash(info.waves)
		else
			progressLabel.Text = "Waves cleared " .. BLANK
		end
		local returnIn = info.returnIn
		returnAt = if typeof(returnIn) == "number" and returnIn > 0
			then os.clock() + returnIn
			else nil
		showButtons(info.canBack, deps.canReturn)
		paintCountdown()
		scrim.Visible = true
	end

	table.insert(
		connections,
		backButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onBack()
		end)
	)
	table.insert(
		connections,
		returnButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onReturn()
		end)
	)
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(deltaTime: number)
			if returnAt == nil or not scrim.Visible then
				return
			end
			tickAccumulator += deltaTime
			if tickAccumulator < Theme.COMBAT_TIMER_TICK_SECONDS then
				return
			end
			tickAccumulator = 0
			paintCountdown()
		end)
	)

	local handle: SummaryCardHandle = {
		Show = show,
		Hide = function()
			scrim.Visible = false
			returnAt = nil
		end,
		IsVisible = function()
			return scrim.Visible
		end,
		CanBack = function()
			return scrim.Visible and canBack
		end,
		SetScale = function(scale: number)
			uiScale.Scale = scale
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			scrim:Destroy()
		end,
	}
	return handle
end

return SummaryCard
