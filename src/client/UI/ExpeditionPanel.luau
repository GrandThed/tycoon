--!strict
-- Party & runs (C0 contract, docs/INTERFACES.md "Hub client"; slimmed in L4 W3,
-- docs/prompts/l4-w3-contract.md section 2.4): the hub party, "Open to public" and the run list
-- a run can be joined from. Choosing and departing a level moved to the map (UI/HubMap, the
-- shared UI/MapScreen); its footer button "Party & runs" opens this panel, and the map's Depart
-- asks this panel whether the run is public (IsPublic). Join fires RequestJoinRun(hostUserId), an
-- intent with no entitlement in it: the server re-checks the run and teleports.
--
-- Everything degrades (C0 principle): with `Places.json combatPlaceId` still 0 the panel says so
-- and Join stays dark, and the runs list is empty until the server answers a RequestRunList. The
-- list is polled only while the panel is open, so a closed panel costs the server nothing.
--
-- C1: a tapped Join locks every Join button until UIController calls ClearDeparting from the
-- matching ActionResult — a teleport takes seconds, and a second tap in that window is either
-- wasted rate limit or a second reserved server.
--
-- C2 (co-op): a party strip at the top mirrors the server's PartyState (members, ★ leader,
-- pending invites counting down, Invite → a picker of the other players in this server,
-- Leave, Kick for the leader). Only the leader departs, so only the leader sees "Open to
-- public". The run list is grouped by the server's `relation` tag and names each run's level
-- and difficulty from Config/Expeditions.json. Leadership shown here is display only — the
-- server answers `notLeader` whatever this panel believes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local Create = require(script.Parent:WaitForChild("Create"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local PanelDock = require(script.Parent:WaitForChild("PanelDock"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = {
	placesConfig: Types.PlacesConfig,
	combatConfig: Types.CombatConfig,
	onJoin: (hostUserId: number) -> (),
	onRefreshRuns: () -> (),
	onPartyInvite: (userId: number) -> (),
	onPartyLeave: () -> (),
	onPartyKick: (userId: number) -> (),
	onClose: () -> (),
}

export type ExpeditionPanelHandle = {
	DesignHeight: number,
	SetRuns: (runs: { Types.RunListEntry }) -> (),
	-- The party the local player is a MEMBER of, or nil when solo (UIController filters out a
	-- PartyState that only lists the player as a pending invitee).
	SetParty: (party: Types.HubParty?) -> (),
	-- Drops the picker's "Sent" marks after a refused invite, so the row can be tapped again.
	ClearInviteSent: () -> (),
	ClearDeparting: () -> (),
	-- True while this player's own Join tap is waiting for its ActionResult.
	IsDeparting: () -> boolean,
	-- "Open to public" as it stands: the map's Depart sends it (RequestExpedition's third value).
	IsPublic: () -> boolean,
	SetOpen: (open: boolean) -> (),
	IsOpen: () -> boolean,
	SetLayout: (dock: PanelDock.Dock) -> (),
	Destroy: () -> (),
}

type RunRow = {
	frame: Frame,
	nameLabel: TextLabel,
	metaLabel: TextLabel,
	button: TextButton,
	hostUserId: number,
}

-- One pooled line of the party strip or the invite picker: a name and an optional button.
type LineRow = {
	frame: Frame,
	label: TextLabel,
	button: TextButton,
	userId: number,
}

type RunGroup = { relation: Types.RunRelation, header: TextLabel }

local NO_PLACE_MESSAGE = "Publish the Expeditions place first"
-- A run's state as the list shows it: the registry advertises a run as joinable only in its
-- lobby (wave 0, L1 ruling 6) and past joining once its party is in a level.
local IN_LOBBY_TEXT = "in the lobby"
local IN_LEVEL_TEXT = "in a level"

-- Display order and titles of the run-list groups (the server already sorts in this order).
local RUN_GROUPS: { { relation: Types.RunRelation, title: string } } = {
	{ relation = "server", title = "IN THIS SERVER" },
	{ relation = "friend", title = "FRIENDS" },
	{ relation = "public", title = "OPEN RUNS" },
}

local ExpeditionPanel = {}

function ExpeditionPanel.new(parent: Instance, deps: Deps): ExpeditionPanelHandle
	local connections: { RBXScriptConnection } = {}
	local runRows: { RunRow } = {}
	local lastActionTime = 0
	local combatConfig = deps.combatConfig
	-- Contract default; a Combat.json that predates the key reads as the shipped default.
	local public = combatConfig.coop.publicByDefault ~= false
	-- In-flight Join, and a token so an expired timeout never unlocks a newer tap.
	local departing = false
	local departToken = 0
	-- Forward declaration: the row handlers are built before the repaint helpers.
	local beginDeparting: () -> ()
	-- Generation token for the polling loop: closing the panel (or opening it again)
	-- invalidates every pending task.delay so only one loop is ever alive.
	local pollToken = 0
	local placeReady = deps.placesConfig.combatPlaceId ~= 0
	local localUserId = Players.LocalPlayer.UserId

	-- C2 party state as last pushed by the server, plus the local deadlines of its pending
	-- invites (expiresIn is relative to the push).
	local party: Types.HubParty? = nil
	local pendingDeadlines: { [number]: number } = {}
	local pickerOpen = false
	local inviteSent: { [number]: boolean } = {}
	-- PlayerRemoving fires while the leaver is still in GetPlayers(), so the picker skips
	-- these ids explicitly.
	local departedIds: { [number]: boolean } = {}
	local tickToken = 0
	local isOpen = false

	local function isLeader(): boolean
		local current = party
		return current == nil or current.leaderUserId == localUserId
	end

	local panel = Panel.new(parent, {
		name = "ExpeditionPanel",
		title = "Party & runs",
		designHeight = Theme.PANEL_HEIGHT,
		onClose = deps.onClose,
	})

	local scroll = Create("ScrollingFrame", {
		Name = "PartyAndRuns",
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

	local function makeListFrame(name: string): Frame
		local frame = Create("Frame", {
			Name = name,
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Parent = scroll,
		}) :: Frame
		Create("UIListLayout", {
			Padding = UDim.new(0, Theme.ROW_SPACING),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = frame,
		})
		return frame
	end

	local function makeButton(
		parentFrame: Instance,
		name: string,
		text: string,
		anchorX: number
	): TextButton
		local button = Create("TextButton", {
			Name = name,
			AnchorPoint = Vector2.new(anchorX, 0.5),
			Position = if anchorX == 1
				then UDim2.new(1, -Theme.ROW_SPACING, 0.5, 0)
				else UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(Theme.ROW_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
			Parent = parentFrame,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = button })
		return button
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

	-- Pinned-at-the-top note, visible only while the second place has no id: Join is dark and
	-- the map's Depart is refused, so the panel has to say why once, in words.
	local noPlaceLabel =
		makeLabel(scroll, "Notice", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_HIGHLIGHT)
	noPlaceLabel.Text = NO_PLACE_MESSAGE
	noPlaceLabel.Visible = not placeReady

	-- C2 party strip: header, one pooled line per member / pending invite, the action row
	-- (Invite, Leave) and the invite picker under it.
	local partyHeader =
		makeLabel(scroll, "PartyHeader", Theme.FONT_BOLD, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	partyHeader.Text = "PARTY"
	local partyHint =
		makeLabel(scroll, "PartyHint", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	partyHint.Text = "Invite players in this server to depart together."
	local partyList = makeListFrame("PartyMembers")
	local partyActions = Create("Frame", {
		Name = "PartyActions",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, Theme.ROW_BUTTON_HEIGHT),
		BackgroundTransparency = 1,
		Parent = scroll,
	}) :: Frame
	local inviteButton = makeButton(partyActions, "Invite", "Invite", 0)
	inviteButton.BackgroundColor3 = Theme.COLOR_ACCENT_ALT
	inviteButton.TextColor3 = Theme.COLOR_TEXT_DARK
	local leaveButton = makeButton(partyActions, "Leave", "Leave", 1)
	local pickerList = makeListFrame("InvitePicker")
	pickerList.Visible = false
	local pickerEmpty =
		makeLabel(pickerList, "Empty", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	pickerEmpty.Text = "No one else is in this server."
	pickerEmpty.LayoutOrder = 0 -- pooled picker rows take orders 1..n below it

	local function makeLineRow(listFrame: Frame, name: string, buttonText: string): LineRow
		local frame = Create("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 0, Theme.PARTY_ROW_HEIGHT),
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Visible = false,
			Parent = listFrame,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
		local label = Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, 0),
			Size = UDim2.new(
				1,
				-Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP,
				1,
				0
			),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		local button = makeButton(frame, "Action", buttonText, 1)
		return { frame = frame, label = label, button = button, userId = 0 }
	end

	local memberRows: { LineRow } = {}
	local pickerRows: { LineRow } = {}

	local function memberRow(index: number): LineRow
		local row = memberRows[index]
		if row == nil then
			local created = makeLineRow(partyList, "Member" .. tostring(index), "Kick")
			table.insert(
				connections,
				created.button.Activated:Connect(function()
					-- Kick is leader-only and never aimed at yourself; the server re-checks.
					if created.userId == 0 or created.userId == localUserId or not isLeader() then
						return
					end
					tryAction(function()
						deps.onPartyKick(created.userId)
					end)
				end)
			)
			memberRows[index] = created
			row = created
		end
		row.frame.LayoutOrder = index
		return row
	end

	local paintPicker: () -> ()

	local function pickerRow(index: number): LineRow
		local row = pickerRows[index]
		if row == nil then
			local created = makeLineRow(pickerList, "Player" .. tostring(index), "Invite")
			created.button.BackgroundColor3 = Theme.COLOR_ACCENT_ALT
			created.button.TextColor3 = Theme.COLOR_TEXT_DARK
			table.insert(
				connections,
				created.button.Activated:Connect(function()
					local userId = created.userId
					if userId == 0 or inviteSent[userId] then
						return
					end
					tryAction(function()
						inviteSent[userId] = true
						paintPicker()
						deps.onPartyInvite(userId)
					end)
				end)
			)
			pickerRows[index] = created
			row = created
		end
		row.frame.LayoutOrder = index
		return row
	end

	local function partyCount(): number
		local current = party
		if current == nil then
			return 1
		end
		return #current.members + #current.pending
	end

	local function canInvite(): boolean
		return isLeader() and partyCount() < combatConfig.coop.maxParty
	end

	paintPicker = function(): ()
		pickerList.Visible = pickerOpen
		if not pickerOpen then
			return
		end
		local excluded: { [number]: boolean } = { [localUserId] = true }
		local current = party
		if current ~= nil then
			for _, member in current.members do
				excluded[member.userId] = true
			end
			for _, invite in current.pending do
				excluded[invite.userId] = true
			end
		end
		local candidates: { Player } = {}
		for _, other in Players:GetPlayers() do
			if not excluded[other.UserId] and not departedIds[other.UserId] then
				table.insert(candidates, other)
			end
		end
		table.sort(candidates, function(a: Player, b: Player): boolean
			return a.DisplayName:lower() < b.DisplayName:lower()
		end)
		for index, other in candidates do
			local row = pickerRow(index)
			row.userId = other.UserId
			row.label.Text = other.DisplayName
			local sent = inviteSent[other.UserId] == true
			row.button.Text = if sent then "Sent" else "Invite"
			row.button.Active = not sent
			row.button.AutoButtonColor = not sent
			row.button.BackgroundTransparency = if sent then Theme.DIM_TRANSPARENCY else 0
			row.frame.Visible = true
		end
		for index = #candidates + 1, #pickerRows do
			pickerRows[index].frame.Visible = false
			pickerRows[index].userId = 0
		end
		pickerEmpty.Visible = #candidates == 0
	end

	local function pendingSeconds(userId: number): number
		local deadline = pendingDeadlines[userId]
		if deadline == nil then
			return 0
		end
		return math.max(math.ceil(deadline - os.clock()), 0)
	end

	local function paintParty(): ()
		local current = party
		local leader = isLeader()
		partyHint.Visible = current == nil
		local shown = 0
		if current ~= nil then
			for _, member in current.members do
				shown += 1
				local row = memberRow(shown)
				row.userId = member.userId
				local isSelf = member.userId == localUserId
				row.label.Text = (if member.userId == current.leaderUserId then "★ " else "")
					.. member.name
					.. (if isSelf then " (you)" else "")
				row.label.TextColor3 = Theme.COLOR_TEXT
				row.button.Visible = leader and not isSelf
				row.frame.Visible = true
			end
			for _, invite in current.pending do
				shown += 1
				local row = memberRow(shown)
				row.userId = 0 -- pending lines have no action
				row.label.Text = invite.name
					.. " · invited · "
					.. tostring(pendingSeconds(invite.userId))
					.. "s"
				row.label.TextColor3 = Theme.COLOR_TEXT_DIM
				row.button.Visible = false
				row.frame.Visible = true
			end
		end
		for index = shown + 1, #memberRows do
			memberRows[index].frame.Visible = false
			memberRows[index].userId = 0
		end
		partyList.Visible = shown > 0

		local inviteAllowed = canInvite()
		if not inviteAllowed then
			pickerOpen = false
		end
		inviteButton.Visible = inviteAllowed
		inviteButton.Text = if pickerOpen then "Done" else "Invite"
		leaveButton.Visible = current ~= nil
		partyActions.Visible = inviteButton.Visible or leaveButton.Visible
		paintPicker()
	end

	-- Repaints the pending countdowns once a second while the panel is open and something is
	-- pending; the loop ends itself otherwise.
	local function startTicker(): ()
		tickToken += 1
		local token = tickToken
		local function tick(): ()
			if token ~= tickToken or not isOpen then
				return
			end
			local current = party
			if current == nil or #current.pending == 0 then
				return
			end
			paintParty()
			task.delay(Theme.PARTY_TICK_SECONDS, tick)
		end
		task.delay(Theme.PARTY_TICK_SECONDS, tick)
	end

	local function makeToggleRow(
		name: string,
		text: string,
		labelColor: Color3
	): (Frame, TextButton)
		local row = Create("Frame", {
			Name = name,
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, -Theme.ROW_SPACING, 0, Theme.SETTINGS_ROW_HEIGHT),
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Parent = scroll,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = row })
		Create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.ROW_TEXT_LEFT, 0),
			Size = UDim2.new(
				1,
				-Theme.ROW_TEXT_LEFT - Theme.TOGGLE_WIDTH - Theme.ROW_TEXT_GAP,
				1,
				0
			),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_MEDIUM,
			TextColor3 = labelColor,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = text,
			Parent = row,
		})
		local toggle = Create("TextButton", {
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
			Parent = row,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = toggle })
		return row, toggle
	end

	local function paintToggleButton(toggle: TextButton, on: boolean, onColor: Color3): ()
		toggle.Text = if on then "ON" else "OFF"
		toggle.BackgroundColor3 = if on then onColor else Theme.COLOR_BG_LIGHT
		toggle.TextColor3 = if on then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT
	end

	-- Only the leader departs, so a non-leader never sees it; it rides with the map's Depart.
	local publicRow, publicToggle = makeToggleRow("Public", "Open to public", Theme.COLOR_TEXT)

	local function paintToggles(): ()
		paintToggleButton(publicToggle, public, Theme.COLOR_ACCENT)
	end

	local runsHeader =
		makeLabel(scroll, "RunsHeader", Theme.FONT_BOLD, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	runsHeader.Text = "JOIN A RUN"
	local runsEmptyLabel =
		makeLabel(scroll, "RunsEmpty", Theme.FONT, Theme.TEXT_SMALL, Theme.COLOR_TEXT_DIM)
	runsEmptyLabel.Text = "No runs to join right now."
	-- Rows are created lazily and reused: the list is re-sent every few seconds and must not
	-- leak a frame per poll. Group headers live in the same list and are re-ordered with them.
	local runsContainer = makeListFrame("Runs")
	local runGroups: { RunGroup } = {}
	for _, group in RUN_GROUPS do
		local header = Create("TextLabel", {
			Name = "Group_" .. group.relation,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, Theme.ROW_LINE_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_ACCENT_ALT,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = group.title,
			Visible = false,
			Parent = runsContainer,
		}) :: TextLabel
		table.insert(runGroups, { relation = group.relation, header = header })
	end

	local function makeRunRow(index: number): RunRow
		local frame = Create("Frame", {
			Name = "Run" .. tostring(index),
			Size = UDim2.new(1, 0, 0, Theme.EXPEDITION_RUN_ROW_HEIGHT),
			BackgroundColor3 = Theme.COLOR_ROW,
			BorderSizePixel = 0,
			Visible = false,
			Parent = runsContainer,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = frame })
		local textWidth = -Theme.ROW_TEXT_LEFT - Theme.ROW_BUTTON_WIDTH - Theme.ROW_TEXT_GAP
		local nameLabel = Create("TextLabel", {
			Name = "Level",
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
					beginDeparting()
					deps.onJoin(row.hostUserId)
				end)
			end)
		)
		return row
	end

	local function paintJoinButtons(): ()
		local joinable = placeReady and not departing
		for _, row in runRows do
			if row.frame.Visible then
				row.button.Active = joinable
				row.button.AutoButtonColor = joinable
				row.button.BackgroundTransparency = if joinable then 0 else Theme.DIM_TRANSPARENCY
			end
		end
	end

	local function isRunEntry(run: any): boolean
		return typeof(run) == "table"
			and typeof(run.hostUserId) == "number"
			and typeof(run.hostName) == "string"
			and typeof(run.levelId) == "string"
			and typeof(run.difficulty) == "string"
			and typeof(run.wave) == "number"
			and typeof(run.partySize) == "number"
			and (run.relation == "server" or run.relation == "friend" or run.relation == "public")
	end

	-- A run's level by the map node that names it, and its difficulty by the map's word for it;
	-- either falls back to its id (a level this build's map does not name).
	local function levelName(levelId: string): string
		local map = Catalog.GetExpeditionsConfig()
		if map ~= nil then
			for _, node in map.nodes do
				if node.level == levelId then
					return node.name
				end
			end
		end
		return levelId
	end
	local function difficultyName(difficulty: string): string
		local map = Catalog.GetExpeditionsConfig()
		return if map ~= nil then map.difficultyNames[difficulty] or difficulty else difficulty
	end

	local function setRuns(runs: { Types.RunListEntry }): ()
		local shown = 0
		local layoutOrder = 0
		for _, group in runGroups do
			layoutOrder += 1
			group.header.LayoutOrder = layoutOrder
			local inGroup = 0
			for _, run in runs do
				if not isRunEntry(run) or run.relation ~= group.relation then
					continue
				end
				inGroup += 1
				shown += 1
				layoutOrder += 1
				local row = runRows[shown]
				if row == nil then
					row = makeRunRow(shown)
					runRows[shown] = row
				end
				row.frame.LayoutOrder = layoutOrder
				row.hostUserId = run.hostUserId
				row.nameLabel.Text = levelName(run.levelId)
					.. " · "
					.. difficultyName(run.difficulty)
				row.metaLabel.Text = run.hostName
					.. " · "
					.. (if run.wave == 0 then IN_LOBBY_TEXT else IN_LEVEL_TEXT)
					.. " · "
					.. tostring(run.partySize)
					.. "/"
					.. tostring(combatConfig.coop.maxParty)
				row.frame.Visible = true
			end
			group.header.Visible = inGroup > 0
		end
		for index = shown + 1, #runRows do
			local row = runRows[index]
			row.frame.Visible = false
			row.hostUserId = 0
		end
		runsEmptyLabel.Visible = shown == 0
		paintJoinButtons()
	end

	-- Everything leadership touches: the strip and the public toggle.
	local function repaintParty(): ()
		paintParty()
		publicRow.Visible = isLeader()
	end

	local function setParty(nextParty: Types.HubParty?): ()
		party = nextParty
		table.clear(pendingDeadlines)
		-- The pending list now says who is invited, so the local "Sent" marks are stale.
		table.clear(inviteSent)
		if nextParty ~= nil then
			local now = os.clock()
			for _, invite in nextParty.pending do
				pendingDeadlines[invite.userId] = now + math.max(invite.expiresIn, 0)
			end
		end
		repaintParty()
		startTicker()
	end

	local function clearDeparting(): ()
		if not departing then
			return
		end
		departToken += 1
		departing = false
		paintJoinButtons()
	end

	-- C1: a Join is in flight until its ActionResult lands. The server always answers one,
	-- except when the rate limiter drops the intent silently, so the lock also expires on its
	-- own rather than stranding the panel.
	beginDeparting = function(): ()
		departToken += 1
		local token = departToken
		departing = true
		paintJoinButtons()
		task.delay(Theme.EXPEDITION_DEPART_TIMEOUT_SECONDS, function()
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
		publicToggle.Activated:Connect(function()
			public = not public
			paintToggles()
			SoundController.Play("uiClick")
		end)
	)
	table.insert(
		connections,
		inviteButton.Activated:Connect(function()
			if not canInvite() then
				return
			end
			SoundController.Play("uiClick")
			pickerOpen = not pickerOpen
			paintParty()
		end)
	)
	table.insert(
		connections,
		leaveButton.Activated:Connect(function()
			if party == nil then
				return
			end
			tryAction(deps.onPartyLeave)
		end)
	)
	-- The picker lists live players, so it follows joins and leaves while it is showing.
	local function onRoster(): ()
		if pickerOpen then
			paintPicker()
		end
	end
	table.insert(
		connections,
		Players.PlayerAdded:Connect(function(joining: Player)
			departedIds[joining.UserId] = nil
			onRoster()
		end)
	)
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(leaving: Player)
			inviteSent[leaving.UserId] = nil
			departedIds[leaving.UserId] = true
			onRoster()
		end)
	)

	paintToggles()
	repaintParty()
	setRuns({})

	local handle: ExpeditionPanelHandle = {
		DesignHeight = panel.DesignHeight,
		SetRuns = setRuns,
		SetParty = setParty,
		ClearInviteSent = function()
			table.clear(inviteSent)
			paintPicker()
		end,
		ClearDeparting = clearDeparting,
		IsDeparting = function()
			return departing
		end,
		IsPublic = function(): boolean
			return public
		end,
		SetOpen = function(open: boolean)
			panel.SetOpen(open)
			isOpen = open
			if open then
				startPolling()
				paintParty() -- countdowns went stale while the panel was closed
				startTicker()
			else
				pollToken += 1 -- invalidates the pending poll
				tickToken += 1
				pickerOpen = false
				paintParty()
			end
		end,
		IsOpen = panel.IsOpen,
		SetLayout = panel.SetLayout,
		Destroy = function()
			pollToken += 1
			tickToken += 1
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
