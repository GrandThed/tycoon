--!strict
-- Expedition panel (C0 contract, docs/INTERFACES.md "Hub client"): one tile per mission in
-- era order with the recommended Gear Power beside the player's own, an Overdrive toggle
-- once Rebirth has unlocked it, and the run list a run can be joined from. Depart fires
-- RequestExpedition(missionId, overdrive, public) and Join fires RequestJoinRun(hostUserId)
-- — intents with no entitlement in them: the server re-checks the mission against the
-- leader's profile, reserves the server and teleports.
--
-- Everything degrades (C0 principle): with `Places.json combatPlaceId` still 0 every tile
-- is disabled and says so, a mission above `highestEra` is locked, and the runs list is
-- empty until the server answers a RequestRunList. The list is polled only while the panel
-- is open, so a closed panel costs the server nothing.
--
-- C1: a tapped Depart (or Join) locks every tile and Join button until UIController calls
-- ClearDeparting from the matching ActionResult — a teleport takes seconds, and a second
-- tap in that window is either wasted rate limit or a second reserved server.
--
-- C2 (co-op): a party strip at the top mirrors the server's PartyState (members, ★ leader,
-- pending invites counting down, Invite → a picker of the other players in this server,
-- Leave, Kick for the leader). Only the leader departs, so a non-leader's tiles are
-- disabled with the reason; the "Open to public" toggle rides with the Depart intent. The
-- run list is grouped by the server's `relation` tag. Leadership shown here is display
-- only — the server answers `notLeader` whatever this panel believes.

local Players = game:GetService("Players")
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
	onDepart: (missionId: string, overdrive: boolean, public: boolean) -> (),
	onJoin: (hostUserId: number) -> (),
	onRefreshRuns: () -> (),
	onPartyInvite: (userId: number) -> (),
	onPartyLeave: () -> (),
	onPartyKick: (userId: number) -> (),
	onClose: () -> (),
}

export type ExpeditionPanelHandle = {
	DesignHeight: number,
	Refresh: (state: Types.PlayerState, gearPower: number) -> (),
	SetRuns: (runs: { Types.RunListEntry }) -> (),
	-- The party the local player is a MEMBER of, or nil when solo (UIController filters out a
	-- PartyState that only lists the player as a pending invitee).
	SetParty: (party: Types.HubParty?) -> (),
	-- Drops the picker's "Sent" marks after a refused invite, so the row can be tapped again.
	ClearInviteSent: () -> (),
	ClearDeparting: () -> (),
	-- True while this player's own Depart/Join tap is waiting for its ActionResult.
	IsDeparting: () -> boolean,
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

-- One pooled line of the party strip or the invite picker: a name and an optional button.
type LineRow = {
	frame: Frame,
	label: TextLabel,
	button: TextButton,
	userId: number,
}

type RunGroup = { relation: Types.RunRelation, header: TextLabel }

local NO_PLACE_MESSAGE = "Publish the Expeditions place first"
local NOT_LEADER_MESSAGE = "Your party leader picks the mission"
local DEPARTING_TITLE = "…"
-- C1: a Depart/Join tap is in flight until its ActionResult lands. The server always answers
-- one, except when the rate limiter drops the intent silently, so the lock also expires on
-- its own rather than stranding the panel.
local DEPART_TIMEOUT_SECONDS = 8

-- Display order and titles of the run-list groups (the server already sorts in this order).
local RUN_GROUPS: { { relation: Types.RunRelation, title: string } } = {
	{ relation = "server", title = "IN THIS SERVER" },
	{ relation = "friend", title = "FRIENDS" },
	{ relation = "public", title = "OPEN RUNS" },
}

local ExpeditionPanel = {}

function ExpeditionPanel.new(parent: Instance, deps: Deps): ExpeditionPanelHandle
	local connections: { RBXScriptConnection } = {}
	local tiles: { MissionTile } = {}
	local runRows: { RunRow } = {}
	local lastState: Types.PlayerState? = nil
	local lastPower = 0
	local lastActionTime = 0
	local overdrive = false
	local combatConfig = deps.combatConfig
	-- Contract default; a Combat.json that predates the key reads as the shipped default.
	local public = combatConfig.coop.publicByDefault ~= false
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

	local missionNames: { [string]: string } = {}
	for _, mission in deps.missions do
		missionNames[mission.id] = mission.name
	end

	local function isLeader(): boolean
		local current = party
		return current == nil or current.leaderUserId == localUserId
	end

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

	-- Pinned-at-the-top note, visible only while the second place has no id: the tiles
	-- below it are all disabled, so the panel has to say why once, in words.
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

	local overdriveRow, overdriveToggle =
		makeToggleRow("Overdrive", "Overdrive", Theme.COLOR_HIGHLIGHT)
	overdriveRow.Visible = false
	-- Beside Overdrive because both ride on the same Depart intent; only the leader departs,
	-- so a non-leader never sees it.
	local publicRow, publicToggle = makeToggleRow("Public", "Open to public", Theme.COLOR_TEXT)

	local function paintToggles(): ()
		paintToggleButton(overdriveToggle, overdrive, Theme.COLOR_HIGHLIGHT)
		paintToggleButton(publicToggle, public, Theme.COLOR_ACCENT)
	end

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
					deps.onDepart(mission.id, overdrive, public)
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
			Name = "Mission",
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

		local leader = isLeader()
		local enabled = unlocked and placeReady and leader and not departing
		local title = if departing and mission.id == departingMissionId
			then DEPARTING_TITLE
			else "Depart"
		if not placeReady then
			title = "Soon"
			tile.powerLabel.Text ..= " · " .. NO_PLACE_MESSAGE
			tile.powerLabel.TextColor3 = Theme.COLOR_TEXT_DIM
		elseif not leader then
			-- The gate is the leader's own unlocks (host-gated), so this player's lock state
			-- would only mislead here.
			tile.powerLabel.Text ..= " · " .. NOT_LEADER_MESSAGE
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
		tile.frame.BackgroundColor3 = if unlocked or not leader
			then Theme.COLOR_ROW
			else Theme.COLOR_ROW_LOCKED
	end

	local function refresh(state: Types.PlayerState, gearPower: number): ()
		lastState = state
		lastPower = gearPower
		local requiresRebirth = combatConfig.overdrive.requiresRebirth
		local canOverdrive = state.rebirthCount >= requiresRebirth
		overdriveRow.Visible = canOverdrive
		if not canOverdrive and overdrive then
			overdrive = false -- a Rebirth-gated choice must not survive a state that lost it
			paintToggles()
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
			and typeof(run.missionId) == "string"
			and typeof(run.wave) == "number"
			and typeof(run.partySize) == "number"
			and typeof(run.overdrive) == "boolean"
			and (run.relation == "server" or run.relation == "friend" or run.relation == "public")
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
				row.nameLabel.Text = missionNames[run.missionId] or run.missionId
				row.metaLabel.Text = run.hostName
					.. " · Wave "
					.. tostring(run.wave)
					.. " · "
					.. tostring(run.partySize)
					.. "/"
					.. tostring(combatConfig.coop.maxParty)
					.. (if run.overdrive then " · Overdrive" else "")
				row.metaLabel.TextColor3 = if run.overdrive
					then Theme.COLOR_HIGHLIGHT
					else Theme.COLOR_TEXT_DIM
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

	-- Everything leadership touches: the strip, the public toggle and the tiles.
	local function repaintParty(): ()
		paintParty()
		publicRow.Visible = isLeader()
		local state = lastState
		if state ~= nil then
			refresh(state, lastPower)
		end
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

	-- Repaints everything the in-flight lock touches: the tiles through the usual paint
	-- path, the Join rows directly (their text does not change).
	local function paintDeparting(): ()
		local state = lastState
		if state ~= nil then
			refresh(state, lastPower)
		end
		paintJoinButtons()
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
			paintToggles()
			SoundController.Play("uiClick")
			local state = lastState
			if state ~= nil then
				refresh(state, lastPower) -- the recommendation moves with Overdrive
			end
		end)
	)
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
		Refresh = refresh,
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
