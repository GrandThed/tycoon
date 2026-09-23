--!strict
-- Expedition HUD (C1 contract, docs/INTERFACES.md "Combat client"). Everything on it is a
-- render of server state: the wave line, alive/remaining and the tempo dot come from
-- RunState, the wallet strip from the Snapshot, the HP bar from the Humanoid the server
-- sized with Armory.MaxHp, and the ability cooldown rings from PartyMember.abilityReadyIn.
-- The client never computes a reward, a cooldown or a max HP; it only counts down between
-- the server's broadcasts so the numbers do not visibly step at combatStateHz.
--
-- Touch-first layout (checked at 375x667 portrait and 812x375 landscape): the attack button
-- owns the bottom-right thumb arc, the two ability buttons stack immediately left of it and
-- the stance pill sits above them, while HP and the Ready / Return pair stay bottom-left.
-- Every control is at least 44 physical px at MIN_SCALE.
--
-- No radial cooldown image exists in this project, so a "ring" is a dark wipe that falls
-- across the round button plus the remaining whole seconds (reported as a deviation).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = {
	onReady: () -> (),
	onLeave: () -> (),
	onStance: () -> (),
	onAttackDown: () -> (),
	onAttackUp: () -> (),
	onAbility: (slot: string) -> (),
}

export type AbilityInfo = { name: string, cooldown: number }
export type AbilitySet = { melee: AbilityInfo?, ranged: AbilityInfo? }

export type CombatHudHandle = {
	SetMission: (name: string) -> (),
	SetRunState: (run: Types.RunState) -> (),
	SetHealth: (health: number, maxHealth: number) -> (),
	SetWallet: (cash: number, material: string, amount: number, valor: number) -> (),
	SetStance: (stance: string) -> (),
	SetAbilities: (abilities: AbilitySet) -> (),
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

type PartyRow = {
	frame: Frame,
	nameLabel: TextLabel,
	shareLabel: TextLabel,
	-- A waiting member's HP is not in play, so its bar gives way to a status line.
	track: Frame,
	statusLabel: TextLabel,
	fill: Frame,
}
type AbilityButton = {
	button: TextButton,
	nameLabel: TextLabel,
	wipe: Frame,
	timerLabel: TextLabel,
	cooldown: number,
	readyIn: number,
}

local BLANK = "—"
local LOBBY_TEXT = "Lobby"
local WAITING_TEXT = "You'll join at the next wave"
local HOST_MARK = "★ "
local PERCENT = 100
local MELEE_SLOT = "melee"
local RANGED_SLOT = "ranged"

local CombatHud = {}

-- CombatFxController toasts the same words when the server refuses a waiting player's tap.
CombatHud.WAITING_TEXT = WAITING_TEXT

function CombatHud.new(parent: Instance, deps: Deps): CombatHudHandle
	local connections: { RBXScriptConnection } = {}
	local partyRows: { PartyRow } = {}
	local abilityButtons: { [string]: AbilityButton } = {}
	local runEndsIn = 0
	local lastTickAt = os.clock()
	local stance = MELEE_SLOT
	-- userIds seen fighting (not waiting) in a wave this session. A waiting member who has
	-- fought went down and is "back next wave"; anyone else just arrived and "joins next
	-- wave". PartyMember carries only the flag, so the history is ours.
	local seenFighting: { [number]: boolean } = {}

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

	local headerRightInset = Theme.COMBAT_TEMPO_DOT_SIZE
		+ Theme.SCREEN_MARGIN * 2
		+ Theme.COMBAT_HEADER_TIMER_WIDTH
	local missionLabel = Create("TextLabel", {
		Name = "Mission",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 7),
		Size = UDim2.new(1, -14 - headerRightInset, 0, 24),
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
		Size = UDim2.new(1, -14 - headerRightInset, 0, 16),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = LOBBY_TEXT,
		Parent = topFrame,
	}) :: TextLabel

	local function headerRight(name: string, y: number, font: Enum.Font, color: Color3): TextLabel
		return Create("TextLabel", {
			Name = name,
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -(Theme.COMBAT_TEMPO_DOT_SIZE + Theme.SCREEN_MARGIN * 2), 0, y),
			Size = UDim2.fromOffset(Theme.COMBAT_HEADER_TIMER_WIDTH, 16),
			Font = font,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = topFrame,
		}) :: TextLabel
	end

	local timerLabel = headerRight("Timer", 11, Theme.FONT_BOLD, Theme.COLOR_TEXT)
	local aliveLabel = headerRight("Alive", 33, Theme.FONT, Theme.COLOR_TEXT_DIM)

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

	-- Wallet strip: the three numbers a run pays out, straight from the Snapshot the server
	-- pushes after every wave flush. Never predicted locally.
	local walletFrame = Create("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(Theme.COMBAT_WALLET_WIDTH, Theme.COMBAT_WALLET_HEIGHT),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local walletScale = Create("UIScale", { Parent = walletFrame }) :: UIScale
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.COMBAT_WALLET_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = walletFrame,
	})

	local function walletChip(name: string, order: number, color: Color3): TextLabel
		local chip = Create("Frame", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.new(1 / 3, -Theme.COMBAT_WALLET_GAP, 1, 0),
			BackgroundColor3 = Theme.COLOR_BG,
			BackgroundTransparency = Theme.BG_TRANSPARENCY,
			BorderSizePixel = 0,
			Parent = walletFrame,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = chip })
		return Create("TextLabel", {
			Name = "Value",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = color,
			TextScaled = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = BLANK,
			Parent = chip,
		}) :: TextLabel
	end

	local cashChip = walletChip("Cash", 1, Theme.COLOR_ACCENT)
	local materialChip = walletChip("Material", 2, Theme.COLOR_TEXT)
	local valorChip = walletChip("Valor", 3, Theme.COLOR_HIGHLIGHT)

	-- Boss block: only visible while RunState carries a boss.
	local bossFrame = Create("Frame", {
		Name = "Boss",
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(
			Theme.COMBAT_BOSS_WIDTH,
			Theme.COMBAT_BOSS_LABEL_HEIGHT + Theme.COMBAT_BOSS_BAR_HEIGHT
		),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}) :: Frame
	local bossScale = Create("UIScale", { Parent = bossFrame }) :: UIScale
	local bossLabel = Create("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_BOSS_LABEL_HEIGHT),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_ERROR,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = bossFrame,
	}) :: TextLabel
	local bossTrack = Create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, Theme.COMBAT_BOSS_LABEL_HEIGHT),
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_BOSS_BAR_HEIGHT),
		BackgroundTransparency = 1,
		Parent = bossFrame,
	}) :: Frame
	local bossFill = bar(bossTrack, "Bar", Theme.COMBAT_BOSS_BAR_HEIGHT)
	bossFill.BackgroundColor3 = Theme.COLOR_ERROR

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

	-- Ready / Return live bottom-left above the HP bar: the bottom-right belongs to combat.
	local buttonRow = Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0, 1),
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
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
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

	local readyButton = actionButton("Ready", 1, true)
	local returnButton = actionButton("Return", 2, false)
	readyButton.Visible = false

	-- Attack: press and hold, because charge bows and the machine gun both need the hold.
	local attackButton = Create("TextButton", {
		Name = "Attack",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(Theme.COMBAT_ATTACK_BUTTON_SIZE, Theme.COMBAT_ATTACK_BUTTON_SIZE),
		BackgroundColor3 = Theme.COLOR_ACCENT,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "Attack",
		Visible = false,
		Parent = parent,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = attackButton })
	local attackScale = Create("UIScale", { Parent = attackButton }) :: UIScale

	local abilityFrame = Create("Frame", {
		Name = "Abilities",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(
			Theme.COMBAT_ABILITY_BUTTON_SIZE,
			Theme.COMBAT_ABILITY_BUTTON_SIZE * 2 + Theme.COMBAT_CONTROL_GAP
		),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}) :: Frame
	local abilityScale = Create("UIScale", { Parent = abilityFrame }) :: UIScale
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.COMBAT_CONTROL_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = abilityFrame,
	})

	local function makeAbilityButton(slot: string, order: number, key: string): AbilityButton
		local button = Create("TextButton", {
			Name = slot,
			LayoutOrder = order,
			Size = UDim2.fromOffset(
				Theme.COMBAT_ABILITY_BUTTON_SIZE,
				Theme.COMBAT_ABILITY_BUTTON_SIZE
			),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Font = Theme.FONT_BOLD,
			Text = "",
			Visible = false,
			Parent = abilityFrame,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = button })
		Create("TextLabel", {
			Name = "Key",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 4),
			Size = UDim2.new(1, 0, 0, Theme.COMBAT_ABILITY_KEY_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.COMBAT_ABILITY_MIN_TEXT,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			Text = key,
			Parent = button,
		})
		local nameLabel = Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.new(1, -Theme.BUTTON_TEXT_PAD * 2, 0, Theme.COMBAT_ABILITY_NAME_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextScaled = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = button,
		}) :: TextLabel
		-- The "ring": a dark wipe that falls from the top as the cooldown burns down.
		local wipe = Create("Frame", {
			Name = "Cooldown",
			BackgroundColor3 = Theme.COLOR_BG,
			BackgroundTransparency = Theme.COMBAT_ABILITY_COOLDOWN_TRANSPARENCY,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 0),
			ZIndex = 2,
			Parent = button,
		}) :: Frame
		local timer = Create("TextLabel", {
			Name = "Seconds",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, 0, 0, Theme.COMBAT_ABILITY_KEY_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_HIGHLIGHT,
			Text = "",
			ZIndex = 3,
			Parent = button,
		}) :: TextLabel
		return {
			button = button,
			nameLabel = nameLabel,
			wipe = wipe,
			timerLabel = timer,
			cooldown = 0,
			readyIn = 0,
		}
	end

	abilityButtons[MELEE_SLOT] = makeAbilityButton(MELEE_SLOT, 1, "Q")
	abilityButtons[RANGED_SLOT] = makeAbilityButton(RANGED_SLOT, 2, "E")

	local stanceButton = Create("TextButton", {
		Name = "Stance",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(Theme.COMBAT_STANCE_WIDTH, Theme.COMBAT_STANCE_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "Melee ⚔",
		Visible = false,
		Parent = parent,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = stanceButton })
	local stanceScale = Create("UIScale", { Parent = stanceButton }) :: UIScale

	-- C2: shown while the local player is `waiting` (arrived or went down mid-wave). Mid
	-- screen, below the tallest party list, because both thumb corners are taken; inactive,
	-- so it never swallows a camera drag.
	local waitingFrame = Create("Frame", {
		Name = "Waiting",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, Theme.COMBAT_WAITING_TOP_FRACTION),
		Size = UDim2.fromOffset(Theme.COMBAT_WAITING_WIDTH, Theme.COMBAT_WAITING_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = waitingFrame })
	local waitingScale = Create("UIScale", { Parent = waitingFrame }) :: UIScale
	Create("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_MEDIUM,
		TextColor3 = Theme.COLOR_TEXT,
		Text = WAITING_TEXT,
		Parent = waitingFrame,
	})

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
		-- The name gives up the right edge to the damage share; the share never truncates.
		local nameLabel = Create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -Theme.COMBAT_PARTY_SHARE_WIDTH, 0, Theme.COMBAT_PARTY_NAME_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = frame,
		}) :: TextLabel
		local shareLabel = Create("TextLabel", {
			Name = "Share",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(Theme.COMBAT_PARTY_SHARE_WIDTH, Theme.COMBAT_PARTY_NAME_HEIGHT),
			Font = Theme.FONT_BOLD,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_HIGHLIGHT,
			TextXAlignment = Enum.TextXAlignment.Right,
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
		local statusLabel = Create("TextLabel", {
			Name = "Status",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, Theme.COMBAT_PARTY_NAME_HEIGHT),
			Size = UDim2.new(1, 0, 0, Theme.COMBAT_PARTY_STATUS_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.TEXT_SMALL,
			TextColor3 = Theme.COLOR_ACCENT_ALT,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Visible = false,
			Parent = frame,
		}) :: TextLabel
		return {
			frame = frame,
			nameLabel = nameLabel,
			shareLabel = shareLabel,
			track = track,
			statusLabel = statusLabel,
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

	local function paintAbility(entry: AbilityButton): ()
		if entry.cooldown <= 0 or entry.readyIn <= 0 then
			entry.wipe.Size = UDim2.fromScale(1, 0)
			entry.timerLabel.Text = ""
			return
		end
		entry.wipe.Size = UDim2.fromScale(1, math.clamp(entry.readyIn / entry.cooldown, 0, 1))
		entry.timerLabel.Text = tostring(math.ceil(entry.readyIn))
	end

	local function waveText(run: Types.RunState): string
		local phase = run.phase
		if phase == "lobby" then
			return LOBBY_TEXT
		elseif phase == "summary" or phase == "ended" then
			return "Run over"
		end
		local boss = run.boss
		if phase == "boss" and boss ~= nil then
			return "Boss — " .. boss.name
		elseif phase == "breather" then
			return "Breather — wave " .. tostring(run.wave) .. " / " .. tostring(run.waves)
		elseif run.merged then
			return "Waves " .. tostring(run.wave - 1) .. " + " .. tostring(run.wave)
		end
		return "Wave " .. tostring(run.wave) .. " / " .. tostring(run.waves)
	end

	local function setRunState(run: Types.RunState): ()
		local phase = run.phase
		waveLabel.Text = waveText(run)
		readyButton.Visible = phase == "lobby"
		local fighting = phase == "wave" or phase == "breather" or phase == "boss"
		attackButton.Visible = fighting
		abilityFrame.Visible = fighting
		stanceButton.Visible = fighting
		tempoDot.BackgroundColor3 = if run.tempo >= Theme.COMBAT_TEMPO_HOT
			then Theme.COLOR_ERROR
			elseif run.tempo <= Theme.COMBAT_TEMPO_CALM then Theme.COLOR_ACCENT_ALT
			else Theme.COLOR_ACCENT

		aliveLabel.Text = if phase == "lobby"
			then ""
			else "Alive " .. tostring(run.alive) .. " · Left " .. tostring(run.remaining)
		runEndsIn = run.runEndsIn
		lastTickAt = os.clock()

		local boss = run.boss
		bossFrame.Visible = boss ~= nil
		if boss ~= nil then
			bossLabel.Text = boss.name
			bossFill.Size = UDim2.fromScale(
				if boss.maxHp > 0 then math.clamp(boss.hp / boss.maxHp, 0, 1) else 0,
				1
			)
		end

		local localUserId = Players.LocalPlayer.UserId
		local localWaiting = false
		-- A share only means something with company; solo it would always read 100%.
		local showShare = #run.party > 1 and phase ~= "lobby"
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
			-- Fields C2 added are read defensively, so an older server build renders as C1.
			local waiting = member.waiting == true and fighting
			if fighting and not waiting and member.alive then
				seenFighting[member.userId] = true
			end
			if waiting and member.userId == localUserId then
				localWaiting = true
			end
			local suffix = if phase == "lobby" and member.ready
				then " ✓"
				elseif not member.alive then " · DOWN"
				elseif member.bot then " · BOT"
				else ""
			row.nameLabel.Text = (if member.host == true then HOST_MARK else "")
				.. member.name
				.. suffix
			local share = member.damageShare
			row.shareLabel.Text = if showShare and typeof(share) == "number"
				then Format.Cash(math.round(math.clamp(share, 0, 1) * PERCENT)) .. "%"
				else ""
			row.track.Visible = not waiting
			row.statusLabel.Visible = waiting
			if waiting then
				row.statusLabel.Text = if seenFighting[member.userId]
					then "back next wave"
					else "joins next wave"
			end
			row.nameLabel.TextColor3 = if member.alive
				then Theme.COLOR_TEXT
				else Theme.COLOR_TEXT_DIM
			row.frame.BackgroundTransparency = if member.alive
				then Theme.BG_TRANSPARENCY
				else Theme.COMBAT_PARTY_DOWN_TRANSPARENCY
			local maxHp = member.maxHp
			row.fill.Size =
				UDim2.fromScale(if maxHp > 0 then math.clamp(member.hp / maxHp, 0, 1) else 0, 1)
			row.frame.Visible = true
			if member.userId == localUserId then
				for slot, entry in abilityButtons do
					entry.readyIn = if slot == MELEE_SLOT
						then member.abilityReadyIn.melee
						else member.abilityReadyIn.ranged
					paintAbility(entry)
				end
			end
		end
		for index = shown + 1, #partyRows do
			partyRows[index].frame.Visible = false
		end
		waitingFrame.Visible = localWaiting
		if phase == "summary" or phase == "ended" then
			table.clear(seenFighting) -- nothing carries past a run
		end
	end

	-- Between broadcasts (combatStateHz is 4) the run timer and the cooldowns are counted
	-- down locally so they read smoothly; every RunState overwrites them with the truth.
	local tickAccumulator = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(deltaTime: number)
			tickAccumulator += deltaTime
			if tickAccumulator < Theme.COMBAT_TIMER_TICK_SECONDS then
				return
			end
			local elapsed = os.clock() - lastTickAt
			lastTickAt = os.clock()
			tickAccumulator = 0
			runEndsIn = math.max(runEndsIn - elapsed, 0)
			timerLabel.Text = if runEndsIn > 0 then Format.Duration(runEndsIn) else ""
			for _, entry in abilityButtons do
				if entry.readyIn <= 0 then
					continue
				end
				entry.readyIn = math.max(entry.readyIn - elapsed, 0)
				paintAbility(entry)
			end
		end)
	)

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
	table.insert(
		connections,
		stanceButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onStance()
		end)
	)
	-- MouseButton1Down/Up also fire for a touch on a GuiButton, so one pair covers both
	-- devices; MouseLeave releases a finger that slid off the button mid-hold.
	table.insert(connections, attackButton.MouseButton1Down:Connect(deps.onAttackDown))
	table.insert(connections, attackButton.MouseButton1Up:Connect(deps.onAttackUp))
	table.insert(connections, attackButton.MouseLeave:Connect(deps.onAttackUp))
	for slot, entry in abilityButtons do
		table.insert(
			connections,
			entry.button.Activated:Connect(function()
				deps.onAbility(slot)
			end)
		)
	end

	local handle: CombatHudHandle = {
		SetMission = function(name: string)
			missionLabel.Text = name
		end,
		SetRunState = setRunState,
		SetHealth = setHealth,
		SetWallet = function(cash: number, material: string, amount: number, valor: number)
			cashChip.Text = "$" .. Format.Cash(cash)
			materialChip.Text = Format.Cash(amount)
				.. (if material ~= "" then " " .. material else "")
			valorChip.Text = Format.Cash(valor) .. " Valor"
		end,
		SetStance = function(nextStance: string)
			stance = nextStance
			stanceButton.Text = if stance == MELEE_SLOT then "Melee ⚔" else "Ranged ➹"
			attackButton.Text = if stance == MELEE_SLOT then "Attack" else "Fire"
			attackButton.BackgroundColor3 = if stance == MELEE_SLOT
				then Theme.COLOR_ACCENT
				else Theme.COLOR_ACCENT_ALT
		end,
		SetAbilities = function(abilities: AbilitySet)
			for slot, entry in abilityButtons do
				local info = if slot == MELEE_SLOT then abilities.melee else abilities.ranged
				if info == nil then
					entry.button.Visible = false
					entry.cooldown = 0
				else
					entry.button.Visible = true
					entry.nameLabel.Text = info.name
					entry.cooldown = info.cooldown
				end
				paintAbility(entry)
			end
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			topScale.Scale = scale
			walletScale.Scale = scale
			bossScale.Scale = scale
			partyScale.Scale = scale
			hpScale.Scale = scale
			buttonScale.Scale = scale
			attackScale.Scale = scale
			abilityScale.Scale = scale
			stanceScale.Scale = scale
			waitingScale.Scale = scale
			-- UIScale multiplies size, not position offsets, so margins scale by hand.
			local margin = Theme.SCREEN_MARGIN * scale
			local bottom = Theme.PADDING * scale
			local gap = Theme.COMBAT_CONTROL_GAP * scale
			local landscape = viewportSize.X > viewportSize.Y
			if landscape then
				topFrame.AnchorPoint = Vector2.new(0, 0)
				topFrame.Position = UDim2.fromOffset(margin, margin)
				walletFrame.AnchorPoint = Vector2.new(0, 0)
				walletFrame.Position = UDim2.fromOffset(
					margin,
					margin + (Theme.TOP_BAR_HEIGHT + Theme.SCREEN_MARGIN) * scale
				)
			else
				topFrame.AnchorPoint = Vector2.new(0.5, 0)
				topFrame.Position = UDim2.new(0.5, 0, 0, margin)
				walletFrame.AnchorPoint = Vector2.new(0.5, 0)
				walletFrame.Position = UDim2.new(
					0.5,
					0,
					0,
					margin + (Theme.TOP_BAR_HEIGHT + Theme.SCREEN_MARGIN) * scale
				)
			end
			local bossTop = margin
				+ (
						Theme.TOP_BAR_HEIGHT
						+ Theme.SCREEN_MARGIN
						+ Theme.COMBAT_WALLET_HEIGHT
						+ Theme.SCREEN_MARGIN
					)
					* scale
			bossFrame.Position = UDim2.new(0.5, 0, 0, bossTop)
			-- Portrait stacks header, wallet and boss down the middle, so the party list
			-- starts below all three; landscape parks them at the left and the list can
			-- sit beside them at the top-right corner.
			local headerBlock = Theme.TOP_BAR_HEIGHT
				+ Theme.COMBAT_WALLET_HEIGHT
				+ Theme.COMBAT_BOSS_LABEL_HEIGHT
				+ Theme.COMBAT_BOSS_BAR_HEIGHT
				+ Theme.SCREEN_MARGIN * 3
			local partyTop = if landscape then margin else margin + headerBlock * scale
			partyFrame.Position = UDim2.new(1, -margin, 0, partyTop)

			attackButton.Position = UDim2.new(1, -margin, 1, -bottom)
			abilityFrame.Position = UDim2.new(
				1,
				-(margin + (Theme.COMBAT_ATTACK_BUTTON_SIZE * scale) + gap),
				1,
				-bottom
			)
			local abilityHeight = (Theme.COMBAT_ABILITY_BUTTON_SIZE * 2 + Theme.COMBAT_CONTROL_GAP)
				* scale
			stanceButton.Position = UDim2.new(1, -margin, 1, -(bottom + abilityHeight + gap))

			hpFrame.Position = UDim2.new(0, margin, 1, -bottom)
			local hpHeight = (Theme.COMBAT_HP_LABEL_HEIGHT + Theme.COMBAT_HP_BAR_HEIGHT) * scale
			buttonRow.Position =
				UDim2.new(0, margin, 1, -(bottom + hpHeight + Theme.ROW_SPACING * scale))
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			topFrame:Destroy()
			walletFrame:Destroy()
			bossFrame:Destroy()
			partyFrame:Destroy()
			hpFrame:Destroy()
			buttonRow:Destroy()
			attackButton:Destroy()
			abilityFrame:Destroy()
			stanceButton:Destroy()
			waitingFrame:Destroy()
		end,
	}
	handle.SetStance(MELEE_SLOT)
	return handle
end

return CombatHud
