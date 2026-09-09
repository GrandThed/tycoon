--!strict
-- Shop panel (M4 contract, spec §6): Passes then Packs, in Monetization.json array order,
-- skipping every item whose id is 0 (not created yet) and every product marked
-- shopVisible = false (DoubleOffline lives on the welcome-back card, nowhere else).
-- A tap fires RequestPrompt(key) and does nothing else: no optimistic grant, no spinner,
-- no blocking modal. Pack rows preview the grant with the same pure Economy.PackGrant the
-- server uses at receipt time; the preview is display-only and the server's number wins.
-- The preview runs against the snapshot's PERSISTED income rate, never the reported one:
-- the reported rate carries the neighbors bonus and the Studio debug multiplier, so
-- previewing against it overstated the grant by up to 27% in a full server (wave-2
-- ruling 4). The client never reconstructs that rate; the server publishes it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Economy = require(sharedFolder:WaitForChild("Economy"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local PanelDock = require(script.Parent:WaitForChild("PanelDock"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = {
	monetization: Types.MonetizationConfig,
	onPrompt: (key: string) -> (),
	onClose: () -> (),
}

export type ShopPanelHandle = {
	DesignHeight: number,
	Refresh: (
		state: Types.PlayerState,
		persistedIncomePerSecond: number,
		eraConfig: Types.EraConfig?
	) -> (),
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

-- One row type for both sections: `minutes` is nil on passes, which is also what marks a
-- row as a pass for the Owned state. `capFraction` is the pack's own anti-skip ceiling,
-- already resolved against the config default.
type Row = {
	key: string,
	minutes: number?,
	capFraction: number,
	button: TextButton,
	grantLabel: TextLabel,
}

local SECONDS_PER_MINUTE = 60
local MINUTES_PER_HOUR = 60

-- "30m" / "2h", not Format.Duration's "30m 0s" / "2h 0m": pack lengths are whole and the
-- trailing zero unit reads like precision the label does not have.
local function packDurationLabel(minutes: number): string
	if minutes < MINUTES_PER_HOUR or minutes % MINUTES_PER_HOUR ~= 0 then
		return `{minutes}m`
	end
	return `{minutes // MINUTES_PER_HOUR}h`
end

local ShopPanel = {}

function ShopPanel.new(parent: Instance, deps: Deps): ShopPanelHandle
	local connections: { RBXScriptConnection } = {}
	local rows: { Row } = {}
	local lastPromptTime = 0
	local monetization = deps.monetization

	local panel = Panel.new(parent, {
		name = "ShopPanel",
		title = "Shop",
		designHeight = Theme.PANEL_HEIGHT,
		onClose = deps.onClose,
	})

	local scroll = Create("ScrollingFrame", {
		Name = "ItemList",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = Theme.SCROLLBAR_THICKNESS,
		ScrollBarImageColor3 = Theme.COLOR_TEXT_DIM,
		Parent = panel.Content,
	}) :: ScrollingFrame
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ROW_SPACING),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local function addSection(title: string): ()
		Create("TextLabel", {
			Name = title,
			LayoutOrder = nextOrder(),
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.SHOP_SECTION_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.upper(title),
			Parent = scroll,
		})
	end

	local function addRow(
		key: string,
		name: string,
		description: string,
		minutes: number?,
		capFraction: number
	): ()
		-- Height follows the description; only the bottom pad is added, because a
		-- top/left UIPadding would shift the absolutely positioned lines above it.
		local row = Create("Frame", {
			Name = key,
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Parent = scroll,
		}) :: Frame
		Create("UIPadding", {
			PaddingBottom = UDim.new(0, Theme.SHOP_ROW_PAD_BOTTOM),
			Parent = row,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = row })

		local textWidth = -Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP
		Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.ROW_NAME_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_NAME_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = name,
			Parent = row,
		})
		Create("TextLabel", {
			Name = "Description",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.SHOP_DESC_Y),
			-- Full row width: the button sits above this line, not beside it, so long
			-- config copy wraps instead of clipping on a narrow panel. AutomaticSize.Y
			-- lets copy of any length grow the row rather than being cut off.
			Size = UDim2.new(1, -Theme.ROW_TEXT_LEFT * 2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = description,
			Parent = row,
		})
		local grantLabel = Create("TextLabel", {
			Name = "Grant",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.SHOP_GRANT_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_ACCENT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Visible = minutes ~= nil,
			Parent = row,
		}) :: TextLabel

		local button = Create("TextButton", {
			Name = "Buy",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.ROW_NAME_Y),
			Size = UDim2.fromOffset(Theme.ROW_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_ACCENT,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT_DARK,
			Text = "Buy",
			Parent = row,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })

		table.insert(rows, {
			key = key,
			minutes = minutes,
			capFraction = capFraction,
			button = button,
			grantLabel = grantLabel,
		})
		table.insert(
			connections,
			button.Activated:Connect(function()
				if not button.Active then
					return -- owned pass: the row is a status, not an offer
				end
				-- Debounce only guards double taps; the server rate-limits for real.
				local now = os.clock()
				if now - lastPromptTime < Theme.ACTION_DEBOUNCE_SECONDS then
					return
				end
				lastPromptTime = now
				SoundController.Play("uiClick")
				deps.onPrompt(key)
			end)
		)
	end

	-- Built once: Monetization.json is static for the life of the server.
	local passRows = 0
	for _, pass in monetization.passes do
		if pass.id ~= 0 then
			if passRows == 0 then
				addSection("Passes")
			end
			passRows += 1
			addRow(
				pass.key,
				pass.name,
				pass.description,
				nil,
				monetization.packCapFractionOfEraSlotCost
			)
		end
	end
	local packRows = 0
	for _, product in monetization.products do
		if product.id ~= 0 and product.shopVisible then
			if packRows == 0 then
				addSection("Packs")
			end
			packRows += 1
			-- Per-pack cap (contract AMENDED mid-wave): each pack carries its own ceiling
			-- so the three packs stay differentiated; the config value is the fallback.
			addRow(
				product.key,
				product.name,
				product.description,
				product.minutes,
				product.capFraction or monetization.packCapFractionOfEraSlotCost
			)
		end
	end

	-- Same dim placeholder pattern the Legacy panel uses for its Phase 2 line: with every
	-- id still 0 the Shop button is hidden too, so this is only ever seen in the odd case
	-- where the only created product is the welcome-back offer.
	local emptyLabel = Create("TextLabel", {
		Name = "EmptyState",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -Theme.PADDING * 2, 0, Theme.EMPTY_LABEL_HEIGHT),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextWrapped = true,
		Text = "Nothing here yet",
		Visible = #rows == 0,
		Parent = panel.Root,
	}) :: TextLabel
	scroll.Visible = #rows > 0

	local function paintOwned(button: TextButton, owned: boolean): ()
		button.Active = not owned
		button.AutoButtonColor = not owned
		button.Text = if owned then "Owned" else "Buy"
		button.BackgroundColor3 = if owned then Theme.COLOR_BG_LIGHT else Theme.COLOR_ACCENT
		button.TextColor3 = if owned then Theme.COLOR_TEXT_DIM else Theme.COLOR_TEXT_DARK
	end

	local function refresh(
		state: Types.PlayerState,
		persistedIncomePerSecond: number,
		eraConfig: Types.EraConfig?
	): ()
		-- The cap is era-relative (contract: capFraction × the era's TOTAL slot cost), so
		-- the preview needs the current era config; without it we show the copy alone.
		local eraSlotCostTotal = if eraConfig ~= nil then Economy.EraSlotCostTotal(eraConfig) else 0
		for _, row in rows do
			local minutes = row.minutes
			if minutes == nil then
				paintOwned(row.button, state.passes[row.key] == true)
			else
				if eraConfig == nil then
					row.grantLabel.Text = packDurationLabel(minutes) .. " of income"
				else
					local grant = Economy.PackGrant(
						minutes,
						persistedIncomePerSecond,
						eraSlotCostTotal,
						row.capFraction
					)
					-- Say which of the two limits actually produced this number. The cap binds
					-- for most of an era (about four minutes into Era 2), and a "30 minutes"
					-- label on a capped grant overstates the time bought by orders of
					-- magnitude — the player sees a number that is nothing like 30 minutes of
					-- their income. Whichever limit is smaller is the one describing the sale.
					local uncapped = minutes * SECONDS_PER_MINUTE * persistedIncomePerSecond
					local cap = row.capFraction * eraSlotCostTotal
					local limit = if cap < uncapped
						then string.format("%d%% of this era", math.round(row.capFraction * 100))
						else packDurationLabel(minutes) .. " of income"
					row.grantLabel.Text = limit .. " — $" .. Format.Cash(grant)
				end
			end
		end
		emptyLabel.Visible = #rows == 0
	end

	local handle: ShopPanelHandle = {
		DesignHeight = panel.DesignHeight,
		Refresh = refresh,
		SetOpen = panel.SetOpen,
		IsOpen = panel.IsOpen,
		SetLayout = panel.SetLayout,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			panel.Destroy()
		end,
	}
	return handle
end

return ShopPanel
