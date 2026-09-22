--!strict
-- Expedition panel (C0 contract, docs/INTERFACES.md "Hub client"): one tile per mission in
-- era order with the recommended Gear Power beside the player's own, an Overdrive toggle
-- once Rebirth has unlocked it, and the "Active runs" list a friend's run can be joined
-- from. Depart fires RequestExpedition(missionId, overdrive) and Join fires
-- RequestJoinRun(hostUserId) — intents with no entitlement in them: the server re-checks
-- the mission's era against the profile, reserves the server and teleports.
--
-- Everything degrades (C0 principle): with `Places.json combatPlaceId` still 0 every tile
-- is disabled and says so, a mission above `highestEra` is locked, and the runs list is
-- empty until the server answers a RequestRunList. The list is polled only while the panel
-- is open, so a closed panel costs the server nothing.
--
-- C1: a tapped Depart (or Join) locks every tile and Join button until UIController calls
-- ClearDeparting from the matching ActionResult — a teleport takes seconds, and a second
-- tap in that window is either wasted rate limit or a second reserved server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Combat = require(sharedFolder:WaitForChild("Combat"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local PanelDock = require(script.Parent:WaitForChild("PanelDock"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = {
	missions: { Types.MissionConfig },
	placesConfig: Types.PlacesConfig,
	combatConfig: Types.CombatConfig,
	onDepart: (missionId: string, overdrive: boolean) -> (),
	onJoin: (hostUserId: number) -> (),
	onRefreshRuns: () -> (),
	onClose: () -> (),
}

export type ExpeditionPanelHandle = {
	DesignHeight: number,
	Refresh: (state: Types.PlayerState, gearPower: number) -> (),
	SetRuns: (runs: { Types.ActiveRun }) -> (),
	ClearDeparting: () -> (),
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

type MissionTile = {
	mission: Types.MissionConfig,
	frame: Frame,
	metaLabel: TextLabel,
	powerLabel: TextLabel,
	button: TextButton,
	buttonTitle: TextLabel,
	enabled: boolean,
}

type RunRow = {
	frame: Frame,
	nameLabel: TextLabel,
	metaLabel: TextLabel,
	button: TextButton,
	hostUserId: number,
}

local NO_PLACE_MESSAGE = "Publish the Expeditions place first"
local DEPARTING_TITLE = "…"
-- C1: a Depart/Join tap is in flight until its ActionResult lands. The server always answers
-- one, except when the rate limiter drops the intent silently, so the lock also expires on
-- its own rather than stranding the panel.
local DEPART_TIMEOUT_SECONDS = 8

local ExpeditionPanel = {}

function ExpeditionPanel.new(parent: Instance, deps: Deps): ExpeditionPanelHandle
	local connections: { RBXScriptConnection } = {}
	local tiles: { MissionTile } = {}
	local runRows: { RunRow } = {}
	local lastState: Types.PlayerState? = nil
	local lastPower = 0
	local lastActionTime = 0
	local overdrive = false
	-- In-flight departure: which tile was tapped (nil for a Join), and a token so an expired
	-- timeout never unlocks a newer tap.
	local departingMissionId: string? = nil
	local departing = false
	local departToken = 0
	-- Forward declaration: the tile/row handlers are built before the repaint helpers.
	local beginDeparting: (missionId: string?) -> ()
	-- Generation token for the polling loop: closing the panel (or opening it again)
	-- invalidates every pending task.delay so only one loop is ever alive.
	local pollToken = 0
	local combatConfig = deps.combatConfig
	local placeReady = deps.placesConfig.combatPlaceId ~= 0

	local panel = Panel.new(parent, {
		name = "ExpeditionPanel",
		title = "Expeditions",
		designHeight = Theme.PANEL_HEIGHT,
		onClose = deps.onClose,
	})

	local scroll = Create("ScrollingFrame", {
		Name = "Missions",
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

	local function makeLabel(
		parentFrame: Instance,
		name: string,
		font: Enum.Font,
		size: number,
		color: Color3
	): TextLabel
		return Create("TextLabel", {
			Name = name,
			LayoutOrder = nextOrder(),
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = font,
			TextSize = size,
			TextColor3 = color,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			Parent = parentFrame,
		}) :: TextLabel
	end

	-- Small client-side debounce so double-taps don't burn the server rate limit.
	local function tryAction(action: () -> ()): ()
		local now = os.clock()
		if now - lastActionTime < Theme.ACTION_DEBOUNCE_SECONDS then
			return
		end
		lastActionTime = now
		SoundController.Play("uiClick")
		action()
	end

	-- Pinned-at-the-top note, visible only while the second place has no id: the tiles
	-- below it are all disabled, so the panel has to say why once, in words.
	local noPlaceLabel =
		makeLabel(scroll, "Notice", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_HIGHLIGHT)
	noPlaceLabel.Text = NO_PLACE_MESSAGE
	noPlaceLabel.Visible = not placeReady

	local overdriveRow = Create("Frame", {
		Name = "Overdrive",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.SETTINGS_ROW_HEIGHT),
		BackgroundColor3 = Theme.COLOR_ROW,
		BorderSizePixel = 0,
		Visible = false,
		Parent = scroll,
	}) :: Frame
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = overdriveRow }
	)
	Create("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, 0),
		Size = UDim2.new(1, -Theme.ROW_TEXT_LEFT - Theme.TOGGLE_WIDTH - Theme.ROW_TEXT_GAP, 1, 0),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_HIGHLIGHT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "Overdrive",
		Parent = overdriveRow,
	})
	local overdriveToggle = Create("TextButton", {
		Name = "Toggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -Theme.ROW_SPACING, 0.5, 0),
		Size = UDim2.fromOffset(Theme.TOGGLE_WIDTH, Theme.TOGGLE_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "OFF",
		Parent = overdriveRow,
	}) :: TextButton
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = overdriveToggle }
	)

	local function makeTile(mission: Types.MissionConfig): ()
		local frame = Create("Frame", {
			Name = mission.id,
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Parent = scroll,
		}) :: Frame
		Create("UIPadding", {
			PaddingBottom = UDim.new(0, Theme.EXPEDITION_TILE_PAD_BOTTOM),
			Parent = frame,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })

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
			Text = mission.name,
			Parent = frame,
		})
		local metaLabel = Create("TextLabel", {
			Name = "Meta",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.EXPEDITION_META_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		-- The readiness line wraps under the button: "Recommended ⚔ 40 — you ⚔ 52" plus a
		-- lock or unavailable reason is longer than the text column at TEXT_SMALL.
		local powerLabel = Create("TextLabel", {
			Name = "Power",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.EXPEDITION_POWER_Y),
			Size = UDim2.new(1, -Theme.ROW_TEXT_LEFT * 2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = "",
			Parent = frame,
		}) :: TextLabel

		local button = Create("TextButton", {
			Name = "Depart",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.ROW_NAME_Y),
			Size = UDim2.fromOffset(Theme.ROW_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Text = "",
			Parent = frame,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		local buttonTitle = Create("TextLabel", {
			Name = "Title",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.BUTTON_TEXT_PAD, 0),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 1, 0),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "Depart",
			Parent = button,
		}) :: TextLabel

		local tile: MissionTile = {
			mission = mission,
			frame = frame,
			metaLabel = metaLabel,
			powerLabel = powerLabel,
			button = button,
			buttonTitle = buttonTitle,
			enabled = false,
		}
		table.insert(tiles, tile)

		table.insert(
			connections,
			button.Activated:Connect(function()
				if not tile.enabled or departing then
					return
				end
				tryAction(function()
					beginDeparting(mission.id)
					deps.onDepart(mission.id, overdrive)
				end)
			end)
		)
	end

	-- Built once: the mission list is static for the life of the server.
	for _, mission in deps.missions do
		makeTile(mission)
	end

	local runsHeader =
		makeLabel(scroll, "RunsHeader", Theme.FONT_BOLD, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	runsHeader.Text = "ACTIVE RUNS"
	local runsEmptyLabel =
		makeLabel(scroll, "RunsEmpty", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	runsEmptyLabel.Text = "No friends on an expedition right now."
	-- Rows are created lazily and reused: the list is re-sent every few seconds and must not
	-- leak a frame per poll.
	local runsContainer = Create("Frame", {
		Name = "Runs",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, -Theme.ROW_SPACING, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = scroll,
	}) :: Frame
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.ROW_SPACING),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = runsContainer,
	})

	local function makeRunRow(index: number): RunRow
		local frame = Create("Frame", {
			Name = "Run" .. tostring(index),
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, Theme.EXPEDITION_RUN_ROW_HEIGHT),
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Visible = false,
			Parent = runsContainer,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
		local textWidth = -Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP
		local nameLabel = Create("TextLabel", {
			Name = "Host",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.ROW_NAME_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_NAME_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		local metaLabel = Create("TextLabel", {
			Name = "Meta",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, Theme.EXPEDITION_META_Y),
			Size = UDim2.new(1, textWidth, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		local button = Create("TextButton", {
			Name = "Join",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Theme.ROW_SPACING, 0.5, 0),
			Size = UDim2.fromOffset(Theme.ROW_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_ACCENT,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT_DARK,
			Text = "Join",
			Parent = frame,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })

		local row: RunRow = {
			frame = frame,
			nameLabel = nameLabel,
			metaLabel = metaLabel,
			button = button,
			hostUserId = 0,
		}
		table.insert(
			connections,
			button.Activated:Connect(function()
				if row.hostUserId == 0 or not placeReady or departing then
					return
				end
				tryAction(function()
					beginDeparting(nil)
					deps.onJoin(row.hostUserId)
				end)
			end)
		)
		return row
	end

	local function paintToggle(): ()
		overdriveToggle.Text = if overdrive then "ON" else "OFF"
		overdriveToggle.BackgroundColor3 = if overdrive
			then Theme.COLOR_HIGHLIGHT
			else Theme.COLOR_BG_LIGHT
		overdriveToggle.TextColor3 = if overdrive then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT
	end

	local function paintTile(tile: MissionTile, state: Types.PlayerState, gearPower: number): ()
		local mission = tile.mission
		local minutes = math.max(math.round(mission.targetMinutes), 1)
		tile.metaLabel.Text = "Era "
			.. tostring(mission.era)
			.. " · "
			.. tostring(mission.waves)
			.. " waves · ~"
			.. tostring(minutes)
			.. " min · "
			.. mission.material
		-- Both numbers come from the shared pure module the server uses; Overdrive changes
		-- the recommendation, which is why the line repaints on every toggle.
		local recommended = Combat.RecommendedPower(mission, overdrive, combatConfig)
		local unlocked = Combat.MissionUnlocked(state, mission, overdrive, combatConfig)
		local ratio = if recommended > 0 then gearPower / recommended else Theme.POWER_READY_RATIO
		tile.powerLabel.Text = "Recommended ⚔ "
			.. Format.Cash(recommended)
			.. " — you ⚔ "
			.. Format.Cash(gearPower)
		tile.powerLabel.TextColor3 = if ratio >= Theme.POWER_READY_RATIO
			then Theme.COLOR_ACCENT
			elseif ratio >= Theme.POWER_RISKY_RATIO then Theme.COLOR_HIGHLIGHT
			else Theme.COLOR_ERROR

		local enabled = unlocked and placeReady and not departing
		local title = if departing and mission.id == departingMissionId
			then DEPARTING_TITLE
			else "Depart"
		if not placeReady then
			title = "Soon"
			tile.powerLabel.Text ..= " · " .. NO_PLACE_MESSAGE
			tile.powerLabel.TextColor3 = Theme.COLOR_TEXT_DIM
		elseif not unlocked then
			title = "Locked"
			-- Overdrive is the other lock this tile can carry; say which one it is.
			local reason = if mission.era > state.combat.highestEra
				then "Reach era " .. tostring(mission.era) .. " in your city first"
				else "Overdrive needs Rebirth " .. tostring(
					combatConfig.overdrive.requiresRebirth
				)
			tile.powerLabel.Text ..= " · " .. reason
			tile.powerLabel.TextColor3 = Theme.COLOR_HIGHLIGHT
		end
		tile.enabled = enabled
		tile.buttonTitle.Text = title
		tile.buttonTitle.TextColor3 = if enabled
			then Theme.COLOR_TEXT_DARK
			else Theme.COLOR_TEXT_DIM
		tile.button.Active = enabled
		tile.button.AutoButtonColor = enabled
		tile.button.BackgroundColor3 = if enabled then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT
		tile.button.BackgroundTransparency = if enabled then 0 else Theme.DIM_TRANSPARENCY
		tile.frame.BackgroundColor3 = if unlocked then Theme.COLOR_ROW else Theme.COLOR_ROW_LOCKED
	end

	local function refresh(state: Types.PlayerState, gearPower: number): ()
		lastState = state
		lastPower = gearPower
		local requiresRebirth = combatConfig.overdrive.requiresRebirth
		local canOverdrive = state.rebirthCount >= requiresRebirth
		overdriveRow.Visible = canOverdrive
		if not canOverdrive and overdrive then
			overdrive = false -- a Rebirth-gated choice must not survive a state that lost it
			paintToggle()
		end
		if state.combat == nil then
			-- A server that predates the combat profile: no mission can be judged, so show
			-- the tiles locked rather than guess an era.
			for _, tile in tiles do
				tile.enabled = false
				tile.buttonTitle.Text = "Soon"
				tile.button.Active = false
				tile.button.BackgroundTransparency = Theme.DIM_TRANSPARENCY
			end
			return
		end
		for _, tile in tiles do
			paintTile(tile, state, gearPower)
		end
	end

	local function setRuns(runs: { Types.ActiveRun }): ()
		local shown = 0
		for _, run in runs do
			if typeof(run) ~= "table" or typeof(run.hostUserId) ~= "number" then
				continue
			end
			shown += 1
			local row = runRows[shown]
			if row == nil then
				row = makeRunRow(shown)
				runRows[shown] = row
			end
			row.hostUserId = run.hostUserId
			row.nameLabel.Text = run.hostName
			local mission = run.missionId
			row.metaLabel.Text = mission
				.. " · Wave "
				.. tostring(run.wave)
				.. " · "
				.. tostring(run.partySize)
				.. "/"
				.. tostring(combatConfig.coop.maxParty)
				.. (if run.overdrive then " · Overdrive" else "")
			row.frame.Visible = true
			local joinable = placeReady and not departing
			row.button.Active = joinable
			row.button.AutoButtonColor = joinable
			row.button.BackgroundTransparency = if joinable then 0 else Theme.DIM_TRANSPARENCY
		end
		for index = shown + 1, #runRows do
			local row = runRows[index]
			row.frame.Visible = false
			row.hostUserId = 0
		end
		runsEmptyLabel.Visible = shown == 0
	end

	-- Repaints everything the in-flight lock touches: the tiles through the usual paint
	-- path, the Join rows directly (their text does not change).
	local function paintDeparting(): ()
		local state = lastState
		if state ~= nil then
			refresh(state, lastPower)
		end
		local joinable = placeReady and not departing
		for _, row in runRows do
			if row.frame.Visible then
				row.button.Active = joinable
				row.button.AutoButtonColor = joinable
				row.button.BackgroundTransparency = if joinable then 0 else Theme.DIM_TRANSPARENCY
			end
		end
	end

	local function clearDeparting(): ()
		if not departing then
			return
		end
		departToken += 1
		departing = false
		departingMissionId = nil
		paintDeparting()
	end

	beginDeparting = function(missionId: string?): ()
		departToken += 1
		local token = departToken
		departing = true
		departingMissionId = missionId
		paintDeparting()
		task.delay(DEPART_TIMEOUT_SECONDS, function()
			if token == departToken then
				clearDeparting()
			end
		end)
	end

	-- RequestRunList on open and on the interval while open; the loop dies with the panel.
	local function startPolling(): ()
		pollToken += 1
		local token = pollToken
		local schedule: () -> ()
		schedule = function()
			task.delay(Theme.EXPEDITION_RUNS_REFRESH_SECONDS, function()
				if token ~= pollToken then
					return
				end
				deps.onRefreshRuns()
				schedule()
			end)
		end
		deps.onRefreshRuns()
		schedule()
	end

	table.insert(
		connections,
		overdriveToggle.Activated:Connect(function()
			overdrive = not overdrive
			paintToggle()
			SoundController.Play("uiClick")
			local state = lastState
			if state ~= nil then
				refresh(state, lastPower) -- the recommendation moves with Overdrive
			end
		end)
	)
	paintToggle()
	setRuns({})

	local handle: ExpeditionPanelHandle = {
		DesignHeight = panel.DesignHeight,
		Refresh = refresh,
		SetRuns = setRuns,
		ClearDeparting = clearDeparting,
		SetOpen = function(open: boolean)
			panel.SetOpen(open)
			if open then
				startPolling()
			else
				pollToken += 1 -- invalidates the pending poll
			end
		end,
		IsOpen = panel.IsOpen,
		SetLayout = panel.SetLayout,
		Destroy = function()
			pollToken += 1
			departToken += 1 -- invalidates the pending in-flight timeout
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			panel.Destroy()
		end,
	}
	return handle
end

return ExpeditionPanel
