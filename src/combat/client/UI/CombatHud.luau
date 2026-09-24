--!strict
-- Expedition HUD (C1 contract, docs/INTERFACES.md "Combat client"). Everything on it is a
-- render of server state: the wave line, alive/remaining and the tempo dot come from
-- RunState, the wallet strip from the Snapshot, the HP bar from the Humanoid the server
-- sized with Armory.MaxHp, and the ability cooldown rings from PartyMember.abilityReadyIn.
-- The client never computes a reward, a cooldown or a max HP; it only counts down between
-- the server's broadcasts so the numbers do not visibly step at combatStateHz.
--
-- Touch-first layout (checked at 375x667 portrait, 812x375 landscape and 1920x1080): the
-- controls are one right-thumb cluster — the attack button largest, the two abilities on an
-- arc left of and above it, the stance button between them — while HP and the Ready / Return
-- pair stay bottom-left. On touch the cluster keeps clear of Roblox's own jump button: it
-- sits left of it when that leaves the HP block alone (landscape, tablets) and above it
-- otherwise (portrait phones). Every control is at least 44 physical px at MIN_SCALE.
--
-- C2.5 reticle: a centre crosshair (its own ScreenGui that ignores the top-bar inset, so it
-- sits exactly on the camera's centre ray), a hit marker, and a ring of dots that fills with
-- the bow's draw. The attack button is hidden when the device has no touch screen: a click
-- anywhere attacks there, and a locked mouse could not press it anyway.
--
-- No radial cooldown image exists in this project, so a "ring" is a dark wipe that falls
-- across the round button plus the remaining whole seconds (reported as a deviation).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

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
	-- C2.5: the touch that pressed the attack button, so it can also steer the camera.
	onAttackInput: ((input: InputObject) -> ())?,
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
	-- C2.5 reticle: camera state, bow draw (nil = not drawing) and the hit marker.
	SetAiming: (shoulderCamera: boolean, cursorLocked: boolean) -> (),
	SetCharge: (fraction: number?) -> (),
	ShowHitMarker: (heavy: boolean, seconds: number) -> (),
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
local DIAGONAL = math.sqrt(0.5)
local ALT_HINT_LOCKED = "Alt · free cursor"
local ALT_HINT_FREE = "Alt · aim"

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

	-- Right-thumb cluster (C2.5). One frame with one UIScale holds every combat control, so
	-- the arc keeps its shape at any scale. Offsets are design px from the attack centre.
	local attackSize = Theme.COMBAT_ATTACK_BUTTON_SIZE
	local abilitySize = Theme.COMBAT_ABILITY_BUTTON_SIZE
	local stanceSize = Theme.COMBAT_STANCE_SIZE
	local abilityRadius = attackSize * 0.5 + Theme.COMBAT_CLUSTER_GAP + abilitySize * 0.5
	local stanceRadius = attackSize * 0.5 + Theme.COMBAT_CLUSTER_GAP + stanceSize * 0.5
	local reach =
		math.max(abilityRadius + abilitySize * 0.5, stanceRadius * DIAGONAL + stanceSize * 0.5)
	local clusterSize = reach + attackSize * 0.5
	local centre = Vector2.new(reach, reach)
	local touchDevice = UserInputService.TouchEnabled
	local keyHints = UserInputService.KeyboardEnabled

	local controls = Create("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(clusterSize, clusterSize),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}) :: Frame
	local controlsScale = Create("UIScale", { Parent = controls }) :: UIScale

	local function place(offset: Vector2): UDim2
		return UDim2.fromOffset(centre.X + offset.X, centre.Y + offset.Y)
	end

	-- Attack: press and hold, because charge bows and the machine gun both need the hold.
	local attackButton = Create("TextButton", {
		Name = "Attack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = place(Vector2.zero),
		Size = UDim2.fromOffset(attackSize, attackSize),
		BackgroundColor3 = Theme.COLOR_ACCENT,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		Text = "Attack",
		Visible = touchDevice,
		Parent = controls,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = attackButton })
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT,
		Thickness = Theme.STROKE_THICKNESS,
		Transparency = Theme.COMBAT_CLUSTER_STROKE_TRANSPARENCY,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = attackButton,
	})

	local function makeAbilityButton(slot: string, key: string, offset: Vector2): AbilityButton
		local button = Create("TextButton", {
			Name = slot,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = place(offset),
			Size = UDim2.fromOffset(abilitySize, abilitySize),
			BackgroundColor3 = Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Font = Theme.FONT_BOLD,
			Text = "",
			Visible = false,
			Parent = controls,
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
			Visible = keyHints,
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

	-- Melee ability on the left of the thumb, ranged above it, as L1 / R1 sit on a pad.
	abilityButtons[MELEE_SLOT] = makeAbilityButton(MELEE_SLOT, "Q", Vector2.new(-abilityRadius, 0))
	abilityButtons[RANGED_SLOT] =
		makeAbilityButton(RANGED_SLOT, "E", Vector2.new(0, -abilityRadius))

	local stanceButton = Create("TextButton", {
		Name = "Stance",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = place(Vector2.new(-stanceRadius * DIAGONAL, -stanceRadius * DIAGONAL)),
		Size = UDim2.fromOffset(stanceSize, stanceSize),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_STANCE_GLYPH_TEXT,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "⚔",
		Parent = controls,
	}) :: TextButton
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = stanceButton })
	local stanceCaption = Create("TextLabel", {
		Name = "Caption",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_ABILITY_KEY_HEIGHT),
		Font = Theme.FONT,
		TextSize = Theme.COMBAT_ABILITY_MIN_TEXT,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		Text = "Melee",
		Parent = stanceButton,
	}) :: TextLabel

	-- PC only: the one key that frees the pointer mid-fight, next to the buttons it unlocks.
	local altHint = Create("TextLabel", {
		Name = "CursorHint",
		Active = false,
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Theme.COMBAT_HP_BAR_WIDTH, Theme.COMBAT_ALT_HINT_HEIGHT),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = ALT_HINT_LOCKED,
		Visible = false,
		Parent = parent,
	}) :: TextLabel
	local altHintScale = Create("UIScale", { Parent = altHint }) :: UIScale

	-- Reticle: a separate ScreenGui with no top-bar inset, so (0.5, 0.5) is the exact
	-- viewport centre the camera's aim ray passes through. Nothing in it takes input.
	local reticleGui = Create("ScreenGui", {
		Name = "CombatReticle",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent.Parent,
	}) :: ScreenGui
	local reticle = Create("Frame", {
		Name = "Reticle",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.COMBAT_RETICLE_SIZE, Theme.COMBAT_RETICLE_SIZE),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = reticleGui,
	}) :: Frame
	local reticleScale = Create("UIScale", { Parent = reticle }) :: UIScale

	local function reticleBar(
		name: string,
		size: Vector2,
		offset: Vector2,
		rotation: number,
		color: Color3
	): Frame
		local piece = Create("Frame", {
			Name = name,
			Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, offset.X, 0.5, offset.Y),
			Size = UDim2.fromOffset(size.X, size.Y),
			Rotation = rotation,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = reticle,
		}) :: Frame
		Create("UIStroke", {
			Color = Theme.COLOR_TEXT_DARK,
			Thickness = 1,
			Transparency = Theme.COMBAT_RETICLE_STROKE_TRANSPARENCY,
			Parent = piece,
		})
		return piece
	end

	local armLength = Theme.COMBAT_CROSSHAIR_LENGTH
	local armThickness = Theme.COMBAT_CROSSHAIR_THICKNESS
	local armOffset = Theme.COMBAT_CROSSHAIR_GAP + armLength * 0.5
	local horizontal = Vector2.new(armLength, armThickness)
	local vertical = Vector2.new(armThickness, armLength)
	reticleBar("Left", horizontal, Vector2.new(-armOffset, 0), 0, Theme.COLOR_TEXT)
	reticleBar("Right", horizontal, Vector2.new(armOffset, 0), 0, Theme.COLOR_TEXT)
	reticleBar("Top", vertical, Vector2.new(0, -armOffset), 0, Theme.COLOR_TEXT)
	reticleBar("Bottom", vertical, Vector2.new(0, armOffset), 0, Theme.COLOR_TEXT)
	reticleBar("Dot", Vector2.new(armThickness, armThickness), Vector2.zero, 0, Theme.COLOR_TEXT)

	-- Hit marker: four short diagonal ticks around the crosshair.
	local markerBars: { Frame } = {}
	local markerOffset = Theme.COMBAT_HIT_MARKER_OFFSET * DIAGONAL
	for index, corner in
		{ Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) }
	do
		local tick = reticleBar(
			"Marker" .. tostring(index),
			Vector2.new(Theme.COMBAT_HIT_MARKER_LENGTH, armThickness),
			corner * markerOffset,
			if corner.X * corner.Y > 0 then 45 else -45,
			Theme.COLOR_TEXT
		)
		tick.BackgroundTransparency = 1
		local stroke = tick:FindFirstChildOfClass("UIStroke")
		if stroke ~= nil then
			stroke.Transparency = 1
		end
		table.insert(markerBars, tick)
	end

	-- Bow draw: a ring of dots that light up in order and turn gold when the draw is full.
	local chargeDots: { Frame } = {}
	local dotCount = Theme.COMBAT_CHARGE_RING_DOTS
	for index = 1, dotCount do
		local angle = (index - 1) / dotCount * 2 * math.pi
		local dot = Create("Frame", {
			Name = "Charge" .. tostring(index),
			Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			-- Clockwise from 12 o'clock, like every draw meter.
			Position = UDim2.new(
				0.5,
				math.sin(angle) * Theme.COMBAT_CHARGE_RING_RADIUS,
				0.5,
				-math.cos(angle) * Theme.COMBAT_CHARGE_RING_RADIUS
			),
			Size = UDim2.fromOffset(Theme.COMBAT_CHARGE_DOT_SIZE, Theme.COMBAT_CHARGE_DOT_SIZE),
			BackgroundColor3 = Theme.COLOR_TEXT,
			BackgroundTransparency = Theme.COMBAT_CHARGE_DOT_IDLE_TRANSPARENCY,
			BorderSizePixel = 0,
			Visible = false,
			Parent = reticle,
		}) :: Frame
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
		table.insert(chargeDots, dot)
	end
	local litDots = -1
	local fighting = false
	local shoulderCamera = false
	local cursorWasLocked = false
	local markerTweens: { Tween } = {}

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
		fighting = phase == "wave" or phase == "breather" or phase == "boss"
		controls.Visible = fighting
		reticle.Visible = fighting and shoulderCamera
		altHint.Visible = fighting and shoulderCamera and keyHints
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
	local onAttackInput = deps.onAttackInput
	if onAttackInput ~= nil then
		table.insert(
			connections,
			attackButton.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.Touch then
					onAttackInput(input)
				end
			end)
		)
	end
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
			stanceButton.Text = if stance == MELEE_SLOT then "⚔" else "➹"
			stanceCaption.Text = if stance == MELEE_SLOT then "Melee" else "Ranged"
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

			controlsScale.Scale = scale
			reticleScale.Scale = scale
			altHintScale.Scale = scale
			-- Roblox's touch jump button, mirrored from the PlayerModule's own sizing rule
			-- (small screens: 70 px, 95 px from the right, 90 px from the bottom).
			local clusterPx = clusterSize * scale
			local right = margin
			local lift = bottom
			if touchDevice then
				local small = math.min(viewportSize.X, viewportSize.Y)
					<= Theme.COMBAT_JUMP_SMALL_AXIS
				local jumpSize = if small
					then Theme.COMBAT_JUMP_SMALL_SIZE
					else Theme.COMBAT_JUMP_LARGE_SIZE
				local jumpRight = jumpSize * Theme.COMBAT_JUMP_RIGHT_FACTOR
					- Theme.COMBAT_JUMP_RIGHT_TRIM
				local jumpBottom = if small
					then jumpSize + Theme.COMBAT_JUMP_SMALL_BOTTOM_PAD
					else jumpSize * Theme.COMBAT_JUMP_LARGE_BOTTOM_FACTOR
				local hpRight = margin + Theme.COMBAT_HP_BAR_WIDTH * scale
				local besideRight = jumpRight + gap
				if viewportSize.X - besideRight - clusterPx >= hpRight + gap then
					right = besideRight
				else
					lift = jumpBottom + gap
				end
			end
			controls.Position = UDim2.new(1, -right, 1, -lift)

			hpFrame.Position = UDim2.new(0, margin, 1, -bottom)
			local hpHeight = (Theme.COMBAT_HP_LABEL_HEIGHT + Theme.COMBAT_HP_BAR_HEIGHT) * scale
			buttonRow.Position =
				UDim2.new(0, margin, 1, -(bottom + hpHeight + Theme.ROW_SPACING * scale))
			altHint.Position = UDim2.new(
				0,
				margin,
				1,
				-(bottom + hpHeight + (Theme.ROW_SPACING * 2 + Theme.ROW_BUTTON_HEIGHT) * scale)
			)
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
			controls:Destroy()
			altHint:Destroy()
			reticleGui:Destroy()
			waitingFrame:Destroy()
		end,
		SetAiming = function(nextShoulder: boolean, cursorLocked: boolean)
			if nextShoulder == shoulderCamera and cursorLocked == cursorWasLocked then
				return -- polled every frame; only a change touches the instances
			end
			shoulderCamera = nextShoulder
			cursorWasLocked = cursorLocked
			reticle.Visible = fighting and shoulderCamera
			altHint.Visible = fighting and shoulderCamera and keyHints
			altHint.Text = if cursorLocked then ALT_HINT_LOCKED else ALT_HINT_FREE
		end,
		SetCharge = function(fraction: number?)
			local lit = if fraction == nil
				then -1
				else math.floor(math.clamp(fraction, 0, 1) * dotCount)
			if lit == litDots then
				return -- written only when a dot changes, although it is polled every frame
			end
			litDots = lit
			local full = lit >= dotCount
			for index, dot in chargeDots do
				dot.Visible = lit >= 0
				local on = index <= lit
				dot.BackgroundColor3 = if full then Theme.COLOR_HIGHLIGHT else Theme.COLOR_TEXT
				dot.BackgroundTransparency = if on
					then 0
					else Theme.COMBAT_CHARGE_DOT_IDLE_TRANSPARENCY
			end
		end,
		ShowHitMarker = function(heavy: boolean, seconds: number)
			for _, tween in markerTweens do
				tween:Cancel()
			end
			table.clear(markerTweens)
			-- Fixed timing, not Motion: the marker is already a flicker.
			local info =
				TweenInfo.new(math.max(seconds, 0), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local color = if heavy then Theme.COLOR_HIGHLIGHT else Theme.COLOR_TEXT
			for _, tick in markerBars do
				tick.BackgroundColor3 = color
				tick.BackgroundTransparency = 0
				local tween = TweenService:Create(tick, info, { BackgroundTransparency = 1 })
				table.insert(markerTweens, tween)
				tween:Play()
				local stroke = tick:FindFirstChildOfClass("UIStroke")
				if stroke ~= nil then
					stroke.Transparency = Theme.COMBAT_RETICLE_STROKE_TRANSPARENCY
					local strokeTween = TweenService:Create(stroke, info, { Transparency = 1 })
					table.insert(markerTweens, strokeTween)
					strokeTween:Play()
				end
			end
		end,
	}
	handle.SetStance(MELEE_SLOT)
	return handle
end

return CombatHud
