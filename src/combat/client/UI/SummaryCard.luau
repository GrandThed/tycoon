--!strict
-- Run summary card (C1 contract, docs/INTERFACES.md "Combat client"): shown when RunState
-- arrives with phase "summary". Waves cleared, best wave, cash, materials, Valor, kills,
-- time, and a "died" line when the run ended on the floor. Every number is the server's —
-- rewards were already flushed to the profile at each wave clear, so this card only reads
-- the RunSummary back. Nothing is computed here; a missing summary renders dashes rather
-- than inventing numbers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = { onReturn: () -> () }

export type SummaryCardHandle = {
	Show: (summary: Types.RunSummary?) -> (),
	Hide: () -> (),
	IsVisible: () -> boolean,
	SetScale: (scale: number) -> (),
	Destroy: () -> (),
}

local BLANK = "—"

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
		Padding = UDim.new(0, Theme.DIALOG_LINE_GAP),
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

	local titleLabel = line("Title", Theme.FONT_BOLD, Theme.TEXT_LARGE, Theme.COLOR_TEXT)
	titleLabel.Text = "Expedition over"
	local wavesLabel = line("Waves", Theme.FONT, Theme.TEXT_MEDIUM, Theme.COLOR_TEXT)
	local killsLabel = line("Kills", Theme.FONT, Theme.TEXT_MEDIUM, Theme.COLOR_TEXT)
	local rewardLabel = line("Reward", Theme.FONT, Theme.TEXT_MEDIUM, Theme.COLOR_ACCENT)
	local materialsLabel = line("Materials", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	-- Only shown when the run ended with the player down: it explains why the summary
	-- arrived early, and the rewards above it are kept either way.
	local diedLabel = line("Died", Theme.FONT_BOLD, Theme.TEXT_SMALL, Theme.COLOR_ERROR)

	local returnButton = Create("TextButton", {
		Name = "Return",
		LayoutOrder = 1000,
		Size = UDim2.new(1, 0, 0, Theme.DIALOG_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_ACCENT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "Return to your city",
		Parent = card,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = returnButton }
	)

	local function show(summary: Types.RunSummary?): ()
		if summary == nil then
			wavesLabel.Text = "Waves cleared " .. BLANK
			killsLabel.Text = ""
			rewardLabel.Text = ""
			materialsLabel.Text = ""
			diedLabel.Visible = false
		else
			wavesLabel.Text = "Waves cleared "
				.. Format.Cash(summary.wavesCleared)
				.. " · Best wave "
				.. Format.Cash(summary.bestWave)
			killsLabel.Text = "Kills "
				.. Format.Cash(summary.kills)
				.. " · "
				.. Format.Duration(summary.seconds)
			rewardLabel.Text = "+$"
				.. Format.Cash(summary.cash)
				.. " · "
				.. Format.Cash(summary.valor)
				.. " Valor"
				.. (if summary.overdrive then " · Overdrive" else "")
			diedLabel.Text = "You went down — the rewards above are already banked"
			diedLabel.Visible = summary.died
			-- Sorted BY MATERIAL NAME, the same ordering the hub's ExpeditionSummaryCard
			-- uses: the table arrives over the network, so its iteration order is
			-- undefined and the same run would otherwise read differently twice. Sorting
			-- the rendered strings instead would order by the leading digit of the amount.
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
			materialsLabel.Text = if #parts > 0
				then table.concat(parts, " · ")
				else "No materials this run"
		end
		scrim.Visible = true
	end

	table.insert(
		connections,
		returnButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onReturn()
		end)
	)

	local handle: SummaryCardHandle = {
		Show = show,
		Hide = function()
			scrim.Visible = false
		end,
		IsVisible = function()
			return scrim.Visible
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
