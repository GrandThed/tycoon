--!strict
-- Expedition summary card (C1 contract, docs/INTERFACES.md "Hub client (ui-engineer B)"):
-- the report a player reads back in the hub after a run, fired by the hub's
-- `ExpeditionSummary` event on the join sequence. Presentation only — the rewards were
-- credited in the combat place and are already in the profile this snapshot carries, so
-- nothing here is a source of truth and nothing here asks the server for anything.
--
-- The card is modal (full-screen scrim), so it must never be the thing covering another
-- one-shot message: UIController holds Show until the welcome-back card — which lands on
-- the same join and carries the session's single DoubleOffline offer — has been dismissed.
--
-- Same visual language as the era-advance screen and the welcome-back card: one dark card
-- with a highlight title, a stat row per line and a single Dismiss button. The card's
-- height follows the number of stat rows (a mission awards one material, but the shape
-- allows several), so the aspect constraint is recomputed on every Show the way
-- WelcomeBackCard does it with its offer row.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = { onClose: () -> () }

export type ExpeditionSummaryCardHandle = {
	Show: (summary: Types.RunSummary) -> (),
	Hide: () -> (),
	IsOpen: () -> boolean,
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

type StatRow = { frame: Frame, nameLabel: TextLabel, valueLabel: TextLabel }

-- Cash, Valor, Kills, Time plus one row per material band: four bands is the whole game,
-- so eight rows can never be reached by a real summary and the pool never grows past it.
local MAX_STAT_ROWS = 8
local KICKER_TEXT = "EXPEDITION REPORT"
local DIED_TEXT = "You fell — the rewards you earned are yours"

local ExpeditionSummaryCard = {}

-- A summary's material table is keyed by material name; iteration order of a network table
-- is undefined, so the rows are sorted to keep the card stable between two identical runs.
local function sortedMaterials(
	materials: { [string]: number }
): { { name: string, amount: number } }
	local rows: { { name: string, amount: number } } = {}
	for name, amount in materials do
		if typeof(name) == "string" and typeof(amount) == "number" and amount > 0 then
			table.insert(rows, { name = name, amount = amount })
		end
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	return rows
end

function ExpeditionSummaryCard.new(parent: Instance, deps: Deps): ExpeditionSummaryCardHandle
	local connections: { RBXScriptConnection } = {}
	local rows: { StatRow } = {}
	local cardHeight = 0

	local padding = Theme.DIALOG_PADDING
	local rowPitch = Theme.INFO_LINE_HEIGHT + Theme.INFO_LINE_GAP
	local headerHeight = Theme.ERA_KICKER_HEIGHT + Theme.ERA_TITLE_HEIGHT + rowPitch
	local footerHeight = Theme.DIALOG_BUTTON_TOP_GAP + Theme.DIALOG_BUTTON_HEIGHT

	-- Modal like the era screen: the run is over, the player has one thing to read, and a
	-- stray tap behind the card must not buy a building. Tapping the scrim dismisses.
	local scrim = Create("TextButton", {
		Name = "ExpeditionSummaryCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = Theme.SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: TextButton

	local card = Create("Frame", {
		Name = "Card",
		Active = true, -- sinks taps on the body so they never reach the scrim-dismiss
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.DIALOG_WIDTH, Theme.DIALOG_WIDTH),
		BackgroundColor3 = Theme.COLOR_BG,
		BorderSizePixel = 0,
		Parent = scrim,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = card })
	Create("UIStroke", {
		Color = Theme.COLOR_HIGHLIGHT,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = card,
	})
	local aspect = Create("UIAspectRatioConstraint", {
		AspectRatio = 1,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
		Parent = card,
	}) :: UIAspectRatioConstraint
	local uiScale = Create("UIScale", { Parent = card }) :: UIScale

	local function label(
		name: string,
		y: number,
		height: number,
		font: Enum.Font,
		textSize: number,
		color: Color3
	): TextLabel
		return Create("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(padding, y),
			Size = UDim2.new(1, -padding * 2, 0, height),
			Font = font,
			TextSize = textSize,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = card,
		}) :: TextLabel
	end

	local kickerLabel = label(
		"Kicker",
		padding,
		Theme.ERA_KICKER_HEIGHT,
		Theme.FONT,
		Theme.TEXT_SMALL,
		Theme.COLOR_TEXT_DIM
	)
	kickerLabel.Text = KICKER_TEXT
	local titleLabel = label(
		"Title",
		padding + Theme.ERA_KICKER_HEIGHT,
		Theme.ERA_TITLE_HEIGHT,
		Theme.FONT_BOLD,
		Theme.TEXT_LARGE,
		Theme.COLOR_HIGHLIGHT
	)
	local wavesLabel = label(
		"Waves",
		padding + Theme.ERA_KICKER_HEIGHT + Theme.ERA_TITLE_HEIGHT,
		Theme.INFO_LINE_HEIGHT,
		Theme.FONT,
		Theme.TEXT_MEDIUM,
		Theme.COLOR_TEXT
	)

	-- Rows are pooled: a second summary reuses the frames instead of leaking one set a run.
	local rowsContainer = Create("Frame", {
		Name = "Stats",
		Position = UDim2.fromOffset(padding, padding + headerHeight),
		Size = UDim2.new(1, -padding * 2, 0, rowPitch),
		BackgroundTransparency = 1,
		Parent = card,
	}) :: Frame
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.INFO_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rowsContainer,
	})

	local function makeRow(index: number): StatRow
		local frame = Create("Frame", {
			Name = "Stat" .. tostring(index),
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, Theme.INFO_LINE_HEIGHT),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = rowsContainer,
		}) :: Frame
		local nameLabel = Create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0.55, 1),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		local valueLabel = Create("TextLabel", {
			Name = "Value",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.45, 1),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		return { frame = frame, nameLabel = nameLabel, valueLabel = valueLabel }
	end

	local diedLabel =
		label("Died", 0, Theme.INFO_LINE_HEIGHT, Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_ERROR)
	diedLabel.Name = "Died"
	diedLabel.Text = DIED_TEXT
	diedLabel.TextWrapped = true
	diedLabel.Visible = false

	local dismissButton = Create("TextButton", {
		Name = "Dismiss",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -padding),
		Size = UDim2.new(1, -padding * 2, 0, Theme.DIALOG_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_ACCENT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "Nice",
		Parent = card,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = dismissButton }
	)

	local function setRow(index: number, name: string, value: string): number
		if index > MAX_STAT_ROWS then
			return index
		end
		local row = rows[index]
		if row == nil then
			row = makeRow(index)
			rows[index] = row
		end
		row.nameLabel.Text = name
		row.valueLabel.Text = value
		row.frame.Visible = true
		return index + 1
	end

	local function hide(): ()
		if not scrim.Visible then
			return
		end
		scrim.Visible = false
		deps.onClose()
	end

	local function show(summary: Types.RunSummary): ()
		-- `bestWave` and `died` are C1 additions to RunSummary: a summary written by an
		-- older combat place (or a hub that predates them) simply omits them, so they are
		-- read defensively rather than trusted off the type.
		local extra = summary :: any
		local bestWave = if typeof(extra.bestWave) == "number"
			then math.max(extra.bestWave, summary.wavesCleared)
			else summary.wavesCleared
		local died = extra.died == true

		local mission = Catalog.GetMissionById(summary.missionId)
		titleLabel.Text = if mission ~= nil then mission.name else summary.missionId
		if summary.overdrive then
			titleLabel.Text ..= " · Overdrive"
		end
		local waves = if mission ~= nil then mission.waves else 0
		wavesLabel.Text = "Waves cleared "
			.. Format.Cash(summary.wavesCleared)
			.. (if waves > 0 then " / " .. Format.Cash(waves) else "")
			.. " · best "
			.. Format.Cash(bestWave)

		local index = 1
		index = setRow(index, "Cash", "$" .. Format.Cash(summary.cash))
		for _, material in sortedMaterials(summary.materials) do
			index = setRow(index, material.name, Format.Cash(material.amount))
		end
		index = setRow(index, "Valor", Format.Cash(summary.valor))
		index = setRow(index, "Kills", Format.Cash(summary.kills))
		-- Format.Duration owns every duration in this project ("4m 12s"), so the card does
		-- not hand-roll an m:ss of its own.
		index = setRow(index, "Time", Format.Duration(summary.seconds))
		local shown = index - 1
		for spare = index, #rows do
			rows[spare].frame.Visible = false
		end

		rowsContainer.Size = UDim2.new(
			1,
			-padding * 2,
			0,
			shown * Theme.INFO_LINE_HEIGHT + math.max(shown - 1, 0) * Theme.INFO_LINE_GAP
		)
		local bodyHeight = headerHeight + rowsContainer.Size.Y.Offset
		diedLabel.Visible = died
		if died then
			diedLabel.Position =
				UDim2.fromOffset(padding, padding + bodyHeight + Theme.INFO_LINE_GAP)
			bodyHeight += Theme.INFO_LINE_GAP + Theme.INFO_LINE_HEIGHT
		end
		cardHeight = padding * 2 + bodyHeight + footerHeight
		card.Size = UDim2.fromOffset(Theme.DIALOG_WIDTH, cardHeight)
		aspect.AspectRatio = Theme.DIALOG_WIDTH / cardHeight

		scrim.Visible = true
		SoundController.Play("runEnd")
	end

	table.insert(
		connections,
		scrim.Activated:Connect(function()
			SoundController.Play("uiClick")
			hide()
		end)
	)
	table.insert(
		connections,
		dismissButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			hide()
		end)
	)

	local handle: ExpeditionSummaryCardHandle = {
		Show = show,
		Hide = hide,
		IsOpen = function()
			return scrim.Visible
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			-- Shrink below the HUD scale only when the card would not fit, and never below
			-- MIN_SCALE so Dismiss keeps its 44 physical px (spec §10).
			local height = if cardHeight > 0 then cardHeight else Theme.DIALOG_WIDTH
			local margin = Theme.SCREEN_MARGIN * 2 * scale
			local fit = math.min(
				scale,
				(viewportSize.Y - margin) / height,
				(viewportSize.X - margin) / Theme.DIALOG_WIDTH
			)
			uiScale.Scale = math.max(fit, Theme.MIN_SCALE)
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			table.clear(rows)
			scrim:Destroy()
		end,
	}
	return handle
end

return ExpeditionSummaryCard
