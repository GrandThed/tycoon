--!strict
-- The dungeon place's run layer (P5 ruling 22, docs/INTERFACES.md "L1 contracts" -> Client).
-- Everything on it is a render of server state: the objective line, the camp count and the
-- tempo dot come from RunState, the wallet strip from the Snapshot, the party list's HP from
-- PartyMember. The client never computes a reward or a max HP; it only counts the run timer and
-- the countdowns down between the server's broadcasts so they do not visibly step at
-- combatStateHz.
--
-- The fight is the range HUD's (crosshair, health bar, boss bar, ability tiles, touch buttons;
-- CombatUIController mounts them), so this layer has no attack, stance or ability control and
-- no HP bar or reticle of its own: L4 W1b deleted that C1 action layer. Header, objective line,
-- wallet, party list, the run's buttons in the bottom-left corner and the waiting card are
-- what is left. A party member who is down reads " · DOWN" (PartyMember.down, P5 ruling 18).
--
-- L1 (docs/INTERFACES.md "L1 contracts" -> Client): the run is a level, not ten waves.
--  * The wave line is the OBJECTIVE line: "Camp" in the lobby, the stage's name on the road
--    ("Follow the road"), "Gates close in 3" while a camp counts down, "Pickets: 14 left" in a
--    camp of one wave and "Main Camp: wave 2 / 3" in one of several, the boss's name, "Next
--    wave in 6", "Run over". The two countdowns tick locally between RunStates.
--  * The dim line at the header's right reads "Camps cleared 1 / 3" (L1b: open camps count
--    too; a level of one camp shows what is left of the wave there instead).
--  * L1b: "Progress saved" is gone (every kill pays at once, nothing is banked). Its place
--    under the wallet is the notice line (ShowNotice): "Checkpoint" when one is reached.
--  * The bottom-left buttons. In the lobby: Map and Return to your city (`deps.runButtons =
--    false`, a proving build, hides only Return: the trip home kicks from Studio). In a run:
--    Abandon, for whoever ruling 21 lets abandon (the only human, else the leader); it asks
--    twice, with no dialog: the first press reads "Press again to abandon" for
--    Theme.COMBAT_ABANDON_CONFIRM_SECONDS. There is no Ready (the leader departs from the map)
--    and no Return in a run.
--  * On a touch device Abandon is not there while the local player fights in a `wave` or
--    `boss` phase (lead ruling, 2026-10-13), or is engaged by a resident camp group (L1b). That corner is the left thumb's: a thumb that
--    lands on the button to move does not move, lifts and presses the same spot again, and
--    the second press would abandon the run, so asking twice does not protect it. It shows on
--    the road, in a camp's countdown and in a breather, and all along for a player who is
--    waiting or down. Keyboard and gamepad keep it in every live phase.
--  * `fighting` covers the five live phases (travel, gate, wave, boss, breather). The old boss
--    frame went with RunState.boss: the boss bar is the range's.
--
-- L1 fix round (docs/prompts/l1-fix-round.md, part U; ruling 7 of that round):
--  * Abandon has a KEY. On a PC the cursor is locked at the screen's centre in every live
--    phase, so the button could not be clicked at all. The host binds a key and calls
--    PressAbandon, which is the button's own press: the first arms it ("Press again to abandon"
--    for Theme.COMBAT_ABANDON_CONFIRM_SECONDS), the second sends. On keyboard devices the button
--    names the key (`deps.abandonKey`). The key works wherever Abandon is allowed, also where
--    the touch rule above keeps the BUTTON away: a device with both (Studio's phone emulator)
--    then shows the armed line as a label that cannot be tapped, so the thumb rule holds.
--    `deps.onAbandonArmed` tells the host while it is armed (the camera keeps a freed cursor).
--  * The difficulty has a chip of its own at the right end of the title's row, and the level's
--    name shrinks to its room before it would truncate (a long name with " · Normal" did).
--  * The wallet's material chip is not shown where there is no material (the lobby read "0").
--  * `HudEdges.noticeBottom` is where the notice line ends, for the banner's place.
--
-- L1b Wave 2 (docs/INTERFACES.md "Wave 2 — the long road", L1b-W2-23): in Studio only, a dim
-- "Server 1.4 ms" line in every live phase: the crowd step's p95, which CrowdService writes
-- into the Workspace attribute Combat.json debug.perfAttribute names with each [Perf] line.
-- Hidden while the attribute is missing (a live server never sets it). It sits over the
-- bottom-left stack (the buttons, then the two key hints where a keyboard shows them), so it
-- is clear of the header, the objective line, "Camps 1 / 3", the notice line and the boss bar
-- at the top on a PC and on a 667 x 375 phone; it is a label, never a tap target.
--
-- L2 Wave 1 (docs/prompts/l2-w1-contract.md, L2-10), renamed in Wave 2: "Armory" between Map
-- and Return, in the lobby only, like Map (`deps.onArmory`; nil = no button). It is the phone's
-- way to the Armory panel; a keyboard also has K, a gamepad Y (`deps.armoryKey` names it).
--
-- The L2 W1 fix round's c1: Map, Armory and Return make a 280 design px row, which ran under
-- the health bar on a landscape phone and under the Dash and slot buttons in portrait. The
-- buttons are laid out in ROWS (ActionRows): the host hands SetLayout what stands at the bottom
-- of the screen (the health bar, the thumb cluster, the AbilityBar), each row ends a gap short
-- of whatever is in its own band, and what does not fit goes up a row. Measured at MIN_SCALE:
-- 667 x 375 and 640 x 360 give Map over Armory + Return (Return ends 51 and 38 px short of
-- the bar); 375 x 667 gives one button per row (Map, Armory, Return), right edge 103 px
-- against the slot button's 158; 1920 x 1080 keeps one row. The key hints and the perf line sit
-- over however many rows there are.
--
-- L2 Wave 2 (docs/prompts/l2-w2-contract.md, section 2): the Armory panel has Weapons and
-- Abilities tabs; its button keeps W1's slot and width, so the rows above do not change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local ActionRows = require(script.Parent:WaitForChild("ActionRows"))
local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local SoundController =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("SoundController"))

export type Deps = {
	-- L1: "Map" in the lobby; nil = no such button.
	onMap: (() -> ())?,
	-- L2: "Armory" in the lobby, beside Map; nil = no such button.
	onArmory: (() -> ())?,
	-- Fix round c2: the gamepad button that opens the panel, shown on the button where nothing
	-- else could press it (a console); nil = none shown.
	armoryKey: string?,
	-- "Return to your city" (RequestLeave), offered in the lobby.
	onLeave: () -> (),
	-- L1: "Abandon", after its second press (RequestAbandon); nil = no such button.
	onAbandon: (() -> ())?,
	-- Fix round: the name of the key the host binds to PressAbandon, shown on the button on
	-- keyboard devices; nil = the host binds none.
	abandonKey: string?,
	-- Fix round: Abandon was armed by its first press (true), or is armed no longer (false).
	onAbandonArmed: ((armed: boolean) -> ())?,
	-- false = no Return to your city (a proving build: leaving it from Studio would kick
	-- through the bridge). Map and Abandon stay.
	runButtons: boolean?,
	-- P5: a dim line over the bottom-left buttons on keyboard devices (the Studio keys).
	keyHint: string?,
}

-- P5: where the run layer's top blocks ended up, in px of the parent, for what must keep clear
-- of them (the range's boss bar): the header-and-wallet block's bottom and right edges, and the
-- party list's left edge. `noticeBottom` (fix round; L1b) is the bottom of the notice line,
-- which hangs under that block: what the banner must keep clear of.
export type HudEdges = {
	headerBottom: number,
	headerRight: number,
	partyLeft: number,
	noticeBottom: number,
}

-- Fix round c1: something at the bottom of the screen the bottom-left buttons keep clear of.
export type Obstacle = ActionRows.Obstacle

export type CombatHudHandle = {
	-- The header's title, and the difficulty for its chip (nil or "" = no chip: the lobby).
	SetMission: (name: string, difficulty: string?) -> (),
	-- Fix round: the host's Abandon key. The button's own press, without its click; it does
	-- nothing where Abandon is not allowed (not a live run, or not this player's to end).
	PressAbandon: () -> (),
	SetRunState: (run: Types.RunState) -> (),
	-- L1b: a short line under the wallet ("Checkpoint") for `seconds`; a newer one replaces it.
	ShowNotice: (text: string, seconds: number) -> (),
	SetWallet: (cash: number, material: string, amount: number, valor: number) -> (),
	-- `obstacles` (fix round c1): what the bottom-left buttons keep clear of, in this HUD's px;
	-- nil = nothing (one row).
	SetLayout: (
		scale: number,
		viewportSize: Vector2,
		obstacles: { ActionRows.Obstacle }?
	) -> HudEdges,
	-- The camera's state, for the Alt hint: whether the shoulder camera is up and whether it
	-- has the cursor locked.
	SetAiming: (shoulderCamera: boolean, cursorLocked: boolean) -> (),
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

local BLANK = "—"
local LOBBY_TEXT = "Camp"
local RUN_OVER_TEXT = "Run over"
local ROAD_TEXT = "Follow the road"
local MAP_TEXT = "Map"
local ARMORY_TEXT = "Armory"
local RETURN_TEXT = "Return to your city"
local ABANDON_TEXT = "Abandon"
local ABANDON_CONFIRM_TEXT = "Press again to abandon"
-- L1 ruling 8: the phases in which a member may act.
local LIVE_PHASES: { [string]: boolean } =
	{ travel = true, gate = true, wave = true, boss = true, breather = true }
local WAITING_TEXT = "You'll join at the next wave"
local HOST_MARK = "★ "
local PERCENT = 100
local ALT_HINT_LOCKED = "Alt · free cursor"
local ALT_HINT_FREE = "Alt · aim"
-- L1b-W2-23: the perf line reads in tenths of a millisecond; past this it drops the decimal.
local PERF_TENTHS_BELOW = 100

local CombatHud = {}

function CombatHud.new(parent: Instance, deps: Deps): CombatHudHandle
	local connections: { RBXScriptConnection } = {}
	local partyRows: { PartyRow } = {}
	local runEndsIn = 0
	local lastTickAt = os.clock()
	-- userIds seen fighting (not waiting) in a wave this session. A waiting member who has
	-- fought went down and is "back next wave"; anyone else just arrived and "joins next
	-- wave". PartyMember carries only the flag, so the history is ours.
	local seenFighting: { [number]: boolean } = {}
	-- L1: what the objective line and the notices are painted from. `gateAt` / `breatherAt` are
	-- os.clock stamps (nil = not counting) re-anchored by every RunState; `noticeUntil` is when
	-- the notice line goes; `abandonUntil` is until when a second press of Abandon confirms.
	-- Fix round: `mayAbandon` = the local player may end this run now (ruling 21), whether or
	-- not the button is on screen; `armed` = what the host was last told (onAbandonArmed).
	local objective = {
		run = nil :: Types.RunState?,
		gateAt = nil :: number?,
		breatherAt = nil :: number?,
		noticeUntil = 0,
		abandonUntil = 0,
		mayAbandon = false,
		armed = false,
	}

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
	-- The title's row: the level's name, and (fix round) the difficulty in a chip at the row's
	-- right end. The name has the whole row in the lobby and gives up the chip's width in a
	-- run; it shrinks to its room (never under COMBAT_HEADER_TITLE_MIN_TEXT) before it would
	-- truncate. Fixed rects, so nothing here waits on the engine to measure text. The row is the
	-- old 24 px label grown by a pixel above and below (the same centre line): scaled text is
	-- fitted to its box's height as well, and TEXT_LARGE must keep its full size in it.
	local titleLeft = 14
	local titleTop = 6
	local titleHeight = 26
	local titleWidth = Theme.TOP_BAR_WIDTH - titleLeft - headerRightInset
	local missionLabel = Create("TextLabel", {
		Name = "Mission",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(titleLeft, titleTop),
		Size = UDim2.fromOffset(titleWidth, titleHeight),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_LARGE,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = BLANK,
		Parent = topFrame,
	}) :: TextLabel
	Create("UITextSizeConstraint", {
		MinTextSize = Theme.COMBAT_HEADER_TITLE_MIN_TEXT,
		MaxTextSize = Theme.TEXT_LARGE,
		Parent = missionLabel,
	})
	local difficultyChip = Create("TextLabel", {
		Name = "Difficulty",
		Active = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromOffset(titleLeft + titleWidth, titleTop + titleHeight / 2),
		Size = UDim2.fromOffset(Theme.COMBAT_HEADER_CHIP_WIDTH, Theme.COMBAT_HEADER_CHIP_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG_LIGHT,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_HIGHLIGHT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Visible = false,
		Parent = topFrame,
	}) :: TextLabel
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = difficultyChip })
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

	-- A chip's value label and the chip itself (hidden where its number has nothing to count).
	local function walletChip(name: string, order: number, color: Color3): (TextLabel, Frame)
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
		local value = Create("TextLabel", {
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
		return value, chip
	end

	local cashChip = walletChip("Cash", 1, Theme.COLOR_ACCENT)
	local materialChip, materialFrame = walletChip("Material", 2, Theme.COLOR_TEXT)
	local valorChip = walletChip("Valor", 3, Theme.COLOR_HIGHLIGHT)

	-- L1b: the notice line, under the wallet ("Checkpoint"). Never a tap target.
	local noticeFrame = Create("Frame", {
		Name = "Notice",
		Active = false,
		Size = UDim2.fromOffset(
			Theme.COMBAT_CHECKPOINT_NOTICE_WIDTH,
			Theme.COMBAT_CHECKPOINT_NOTICE_HEIGHT
		),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = parent,
	}) :: Frame
	Create(
		"UICorner",
		{ CornerRadius = UDim.new(0, Theme.ROW_CORNER_RADIUS), Parent = noticeFrame }
	)
	local noticeScale = Create("UIScale", { Parent = noticeFrame }) :: UIScale
	local noticeLabel = Create("TextLabel", {
		Name = "Text",
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_ACCENT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = noticeFrame,
	}) :: TextLabel

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

	-- The run's buttons live bottom-left: the bottom-right belongs to the range HUD's thumb
	-- cluster. L1: Map and Return to your city in the lobby, Abandon in a run. Fix round c1:
	-- placed in rows by packActions, not by a list layout.
	local buttonRow = Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0, 1),
		Size = UDim2.fromOffset(Theme.COMBAT_RUN_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
		BackgroundTransparency = 1,
		Parent = parent,
	}) :: Frame
	local buttonScale = Create("UIScale", { Parent = buttonRow }) :: UIScale

	-- Two words wrap onto two lines, so a 104 px button holds "Return to your city".
	local function actionButton(
		name: string,
		text: string,
		order: number,
		width: number,
		accent: boolean
	): TextButton
		local button = Create("TextButton", {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.fromOffset(width, Theme.ROW_BUTTON_HEIGHT),
			BackgroundColor3 = if accent then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT,
			BorderSizePixel = 0,
			Font = Theme.FONT_BOLD,
			TextSize = Theme.COMBAT_RUN_BUTTON_TEXT,
			TextColor3 = if accent then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT,
			TextWrapped = true,
			Text = text,
			Visible = false,
			Parent = buttonRow,
		}) :: TextButton
		Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = button })
		return button
	end

	local mapButton = actionButton("Map", MAP_TEXT, 1, Theme.COMBAT_MAP_BUTTON_WIDTH, true)
	mapButton.TextSize = Theme.TEXT_HEADER
	local armoryKey = deps.armoryKey
	local armoryButton = actionButton(
		"Armory",
		if armoryKey ~= nil then ARMORY_TEXT .. "\n[" .. armoryKey .. "]" else ARMORY_TEXT,
		2,
		Theme.COMBAT_ABILITIES_BUTTON_WIDTH,
		true
	)
	local returnButton =
		actionButton("Return", RETURN_TEXT, 3, Theme.COMBAT_RUN_BUTTON_WIDTH, false)
	local abandonButton =
		actionButton("Abandon", ABANDON_TEXT, 4, Theme.COMBAT_RUN_BUTTON_WIDTH, false)
	-- Fix round: the armed line where the button itself is kept off the screen (a touch device
	-- in a fight, armed by the key). A label, not a button: the thumb that lands there to move
	-- must not be able to confirm with it, and it takes no touch from the thumbstick.
	local abandonPrompt = Create("TextLabel", {
		Name = "AbandonArmed",
		Active = false,
		LayoutOrder = 5,
		Size = UDim2.fromOffset(Theme.COMBAT_RUN_BUTTON_WIDTH, Theme.ROW_BUTTON_HEIGHT),
		BackgroundColor3 = Theme.COLOR_ERROR,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_RUN_BUTTON_TEXT,
		TextColor3 = Theme.COLOR_TEXT_DARK,
		TextWrapped = true,
		Text = ABANDON_CONFIRM_TEXT,
		Visible = false,
		Parent = buttonRow,
	}) :: TextLabel
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = abandonPrompt })

	local touchDevice = UserInputService.TouchEnabled
	local keyHints = UserInputService.KeyboardEnabled

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
	-- P5: the Studio keys, one line above the Alt hint.
	local keyHintText = deps.keyHint
	local keyHint = Create("TextLabel", {
		Name = "KeyHint",
		Active = false,
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Theme.COMBAT_HP_BAR_WIDTH, Theme.COMBAT_ALT_HINT_HEIGHT),
		Font = Theme.FONT,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.COLOR_HIGHLIGHT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = keyHintText or "",
		Visible = keyHintText ~= nil and keyHints,
		Parent = parent,
	}) :: TextLabel
	local keyHintScale = Create("UIScale", { Parent = keyHint }) :: UIScale
	-- L1b-W2-23: the Studio perf line (see the header). `name` = the Workspace attribute it
	-- reads, nil outside Studio or without the config: then it never shows.
	local perfConfig = Catalog.GetCombatConfig()
	local perf = {
		name = if RunService:IsStudio() and perfConfig ~= nil
			then perfConfig.debug.perfAttribute
			else nil :: string?,
		line = Create("TextLabel", {
			Name = "ServerPerf",
			Active = false,
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(Theme.COMBAT_PERF_WIDTH, Theme.COMBAT_PERF_HEIGHT),
			Font = Theme.FONT,
			TextSize = Theme.COMBAT_PERF_TEXT_SIZE,
			TextColor3 = Theme.COLOR_TEXT_DIM,
			TextTransparency = Theme.COMBAT_PERF_TRANSPARENCY,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			Visible = false,
			Parent = parent,
		}) :: TextLabel,
	}
	local perfScale = Create("UIScale", { Parent = perf.line }) :: UIScale

	-- Fix round c1: the bottom-left buttons in rows (ActionRows) and the hint stack over them.
	-- `scale`, `margin` (px from the left), `base` (px from the bottom to the rows' bottom edge),
	-- `height` (this HUD's height in px) and `obstacles` are the last SetLayout's; `shown` is the
	-- set of buttons last laid out (one bit each). The hints stand over at least one row, so they
	-- do not jump when Abandon comes and goes.
	local rowState = {
		scale = 0,
		margin = 0,
		base = 0,
		height = 0,
		obstacles = {} :: { ActionRows.Obstacle },
		shown = -1,
		buttons = { mapButton, armoryButton, returnButton, abandonButton, abandonPrompt } :: { GuiObject },
	}
	local function packActions(force: boolean): ()
		local scale = rowState.scale
		if scale <= 0 then
			return -- before the first SetLayout
		end
		local shown = 0
		for index, button in rowState.buttons do
			if button.Visible then
				shown = bit32.bor(shown, bit32.lshift(1, index))
			end
		end
		if shown == rowState.shown and not force then
			return
		end
		rowState.shown = shown
		local visible: { GuiObject } = {}
		local widths: { number } = {}
		for _, button in rowState.buttons do
			if button.Visible then
				table.insert(visible, button)
				table.insert(widths, button.Size.X.Offset)
			end
		end
		local places, rows, widest = ActionRows.Pack(widths, {
			scale = scale,
			gap = Theme.ROW_SPACING,
			rowHeight = Theme.ROW_BUTTON_HEIGHT,
			margin = rowState.margin,
			bottom = rowState.height - rowState.base,
			clearance = Theme.COMBAT_CONTROL_GAP * scale,
		}, rowState.obstacles)
		local count = math.max(rows, 1)
		local step = Theme.ROW_BUTTON_HEIGHT + Theme.ROW_SPACING
		buttonRow.Size = UDim2.fromOffset(
			math.max(widest, Theme.COMBAT_RUN_BUTTON_WIDTH),
			count * step - Theme.ROW_SPACING
		)
		for index, button in visible do
			local slot = places[index]
			button.Position = UDim2.fromOffset(slot.x, (count - slot.row) * step)
		end
		-- The Alt hint over the top row, the Studio keys over it, the perf line over both.
		local altBottom = rowState.base + count * step * scale
		altHint.Position = UDim2.new(0, rowState.margin, 1, -altBottom)
		local hintSlot = (Theme.COMBAT_ALT_HINT_HEIGHT + Theme.ROW_SPACING) * scale
		keyHint.Position = UDim2.new(0, rowState.margin, 1, -(altBottom + hintSlot))
		-- L1b-W2-23: over the stack, a slot above each key hint a keyboard can show.
		local hintSlots = if not keyHints then 0 elseif keyHintText ~= nil then 2 else 1
		perf.line.Position = UDim2.new(0, rowState.margin, 1, -(altBottom + hintSlot * hintSlots))
	end

	local fighting = false
	local shoulderCamera = false
	local cursorWasLocked = false

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

	-- Whole seconds left until an os.clock stamp, never under 0 (nil = 0).
	local function secondsUntil(at: number?): number
		return if at ~= nil then math.max(math.ceil(at - os.clock()), 0) else 0
	end

	-- L1: what the party is doing now, in one line (see the header).
	local function objectiveText(): string
		local run = objective.run
		if run == nil or run.phase == "lobby" then
			return LOBBY_TEXT
		end
		local phase = run.phase
		local stage = run.stageName
		if phase == "summary" or phase == "ended" then
			return RUN_OVER_TEXT
		elseif phase == "travel" then
			return if stage ~= "" then stage else ROAD_TEXT
		elseif phase == "gate" then
			return "Gates close in " .. Format.Cash(secondsUntil(objective.gateAt))
		elseif phase == "breather" then
			return "Next wave in " .. Format.Cash(secondsUntil(objective.breatherAt))
		elseif phase == "boss" then
			local bossName = run.bossName
			return if bossName ~= nil and bossName ~= "" then bossName else stage
		elseif run.waves <= 1 then
			return stage .. ": " .. Format.Cash(run.left) .. " left"
		elseif run.merged then
			return stage
				.. ": waves "
				.. Format.Cash(run.wave - 1)
				.. " + "
				.. Format.Cash(run.wave)
		end
		return stage .. ": wave " .. Format.Cash(run.wave) .. " / " .. Format.Cash(run.waves)
	end

	-- The dim line at the header's right: which camp of the level, or, in a level of one
	-- camp, what is left of the wave.
	local function campText(run: Types.RunState): string
		if not LIVE_PHASES[run.phase] then
			return ""
		elseif run.camps > 1 then
			-- "Camps cleared 1 / 3" overflows the 74 px label (fix round); this fits.
			return "Camps "
				.. Format.Cash(math.min(run.campsCleared, run.camps))
				.. " / "
				.. Format.Cash(run.camps)
		elseif run.phase == "wave" or run.phase == "boss" then
			return Format.Cash(run.left) .. " left"
		end
		return ""
	end

	-- On keyboard devices the button names the key the host bound: with the cursor locked at
	-- the centre the key is the only way to press it.
	local abandonKey = deps.abandonKey
	local abandonText = if keyHints and abandonKey ~= nil
		then ABANDON_TEXT .. "\n[" .. abandonKey .. "]"
		else ABANDON_TEXT

	local function paintAbandon(): ()
		local armed = os.clock() < objective.abandonUntil
		abandonButton.Text = if armed then ABANDON_CONFIRM_TEXT else abandonText
		abandonButton.BackgroundColor3 = if armed then Theme.COLOR_ERROR else Theme.COLOR_BG_LIGHT
		abandonButton.TextColor3 = if armed then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT
		-- Armed with the button off the screen: the label says it instead.
		abandonPrompt.Visible = armed and not abandonButton.Visible
		packActions(false)
		if armed ~= objective.armed then
			objective.armed = armed
			local onArmed = deps.onAbandonArmed
			if onArmed ~= nil then
				onArmed(armed)
			end
		end
	end

	-- One press of Abandon, from the button or the host's key. It asks twice, with no dialog:
	-- the first press arms it, and only a second inside the window sends.
	local function pressAbandon(): ()
		local onAbandon = deps.onAbandon
		if onAbandon == nil or not objective.mayAbandon then
			return
		end
		if os.clock() < objective.abandonUntil then
			objective.abandonUntil = 0
			paintAbandon()
			onAbandon()
		else
			objective.abandonUntil = os.clock() + Theme.COMBAT_ABANDON_CONFIRM_SECONDS
			paintAbandon()
		end
	end

	-- L1b-W2-23: shown in a live phase while the attribute holds a number, rounded to 0.1 ms.
	local function paintPerf(): ()
		local name = perf.name
		local value = if name ~= nil then Workspace:GetAttribute(name) else nil
		local shown = fighting
			and typeof(value) == "number"
			and value == value
			and value >= 0
			and value < math.huge
		perf.line.Visible = shown
		if not shown then
			return
		end
		local tenths = math.round(value * 10)
		perf.line.Text = if tenths < PERF_TENTHS_BELOW * 10
			then `Server {Format.Cash(tenths // 10)}.{tenths % 10} ms`
			else `Server {Format.Cash(math.round(value))} ms`
	end
	local perfName = perf.name
	if perfName ~= nil then
		table.insert(connections, Workspace:GetAttributeChangedSignal(perfName):Connect(paintPerf))
	end

	local function setRunState(run: Types.RunState): ()
		local phase = run.phase
		local live = LIVE_PHASES[phase] == true
		local gateIn = run.gateIn
		local breatherIn = run.breatherEndsIn
		objective.run = run
		objective.gateAt = if typeof(gateIn) == "number" then os.clock() + gateIn else nil
		objective.breatherAt = if typeof(breatherIn) == "number"
			then os.clock() + breatherIn
			else nil
		waveLabel.Text = objectiveText()
		fighting = live
		altHint.Visible = fighting and shoulderCamera and keyHints
		tempoDot.BackgroundColor3 = if run.tempo >= Theme.COMBAT_TEMPO_HOT
			then Theme.COLOR_ERROR
			elseif run.tempo <= Theme.COMBAT_TEMPO_CALM then Theme.COLOR_ACCENT_ALT
			else Theme.COLOR_ACCENT

		aliveLabel.Text = campText(run)
		runEndsIn = run.runEndsIn
		lastTickAt = os.clock()

		local localUserId = Players.LocalPlayer.UserId
		local localWaiting = false
		local localDown = false
		local localEngaged = false
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
			-- P5: a crowd mission's down keeps its Humanoid alive (read defensively: an older
			-- server build sends no `down`).
			local down = not member.alive or member.down == true
			if down and member.userId == localUserId then
				localDown = true
			end
			-- L1b: a resident camp's fight runs in `travel`, so the phase alone cannot say it.
			if member.engaged == true and member.userId == localUserId then
				localEngaged = true
			end
			row.nameLabel.Text = (if member.host == true then HOST_MARK else "")
				.. member.name
				.. (if down then " · DOWN" else "")
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
			row.nameLabel.TextColor3 = if down then Theme.COLOR_TEXT_DIM else Theme.COLOR_TEXT
			row.frame.BackgroundTransparency = if down
				then Theme.COMBAT_PARTY_DOWN_TRANSPARENCY
				else Theme.BG_TRANSPARENCY
			local maxHp = member.maxHp
			row.fill.Size =
				UDim2.fromScale(if maxHp > 0 then math.clamp(member.hp / maxHp, 0, 1) else 0, 1)
			row.frame.Visible = true
		end
		for index = shown + 1, #partyRows do
			partyRows[index].frame.Visible = false
		end
		waitingFrame.Visible = localWaiting
		-- L1: Map and Return in the lobby; Abandon in a run, for whoever may abandon (ruling
		-- 21: the only member, else the leader). The summary card has its own buttons.
		local inLobby = phase == "lobby"
		mapButton.Visible = inLobby and deps.onMap ~= nil
		armoryButton.Visible = inLobby and deps.onArmory ~= nil
		returnButton.Visible = inLobby and deps.runButtons ~= false
		-- No Abandon under the left thumb of a player in the middle of a fight (see the
		-- header). One who is waiting or down is not fighting, and may want to leave.
		local underThumb = touchDevice
			and (phase == "wave" or phase == "boss" or localEngaged)
			and not localWaiting
			and not localDown
		-- Fix round: who may abandon is one question and whether the button shows is another.
		-- The host's key works wherever the first is true.
		local mayAbandon = live
			and deps.onAbandon ~= nil
			and (shown <= 1 or run.leaderUserId == localUserId)
		local offered = mayAbandon and not underThumb
		objective.mayAbandon = mayAbandon
		abandonButton.Visible = offered
		if objective.abandonUntil > 0 and (not mayAbandon or not (offered or keyHints)) then
			-- A first press must not stay armed where no second press can follow: nobody may
			-- abandon any more, or the button is gone and there is no key to press instead.
			objective.abandonUntil = 0
		end
		-- Always: the armed label depends on whether the button is on screen. It also lays the
		-- buttons out again when the set shown changed.
		paintAbandon()
		if phase == "summary" or phase == "ended" then
			table.clear(seenFighting) -- nothing carries past a run
		end
		if phase == "summary" or phase == "ended" or inLobby then
			-- A checkpoint reached just before the end must not sit over the summary or the map.
			objective.noticeUntil = 0
			noticeFrame.Visible = false
		end
		paintPerf()
	end

	-- Between broadcasts (combatStateHz is 4) the run timer and the countdowns are counted
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
			-- L1: the two countdowns of the objective line, the notice and the armed Abandon
			-- all run out on this tick.
			local run = objective.run
			if run ~= nil and (run.phase == "gate" or run.phase == "breather") then
				waveLabel.Text = objectiveText()
			end
			if noticeFrame.Visible and os.clock() >= objective.noticeUntil then
				noticeFrame.Visible = false
			end
			if objective.abandonUntil > 0 and os.clock() >= objective.abandonUntil then
				objective.abandonUntil = 0
				paintAbandon()
			end
		end)
	)

	local onMap = deps.onMap
	if onMap ~= nil then
		table.insert(
			connections,
			mapButton.Activated:Connect(function()
				SoundController.Play("uiClick")
				onMap()
			end)
		)
	end
	local onArmory = deps.onArmory
	if onArmory ~= nil then
		table.insert(
			connections,
			-- No click sound: the Armory panel makes none (L2-10, Ben's 2026-09-24 ruling).
			armoryButton.Activated:Connect(onArmory)
		)
	end
	table.insert(
		connections,
		returnButton.Activated:Connect(function()
			SoundController.Play("uiClick")
			deps.onLeave()
		end)
	)
	local onAbandon = deps.onAbandon
	if onAbandon ~= nil then
		table.insert(
			connections,
			abandonButton.Activated:Connect(function()
				SoundController.Play("uiClick")
				pressAbandon()
			end)
		)
	end

	local handle: CombatHudHandle = {
		SetMission = function(name: string, difficulty: string?)
			local chip = difficulty ~= nil and difficulty ~= ""
			missionLabel.Text = name
			difficultyChip.Text = difficulty or ""
			difficultyChip.Visible = chip
			missionLabel.Size = UDim2.fromOffset(
				if chip
					then titleWidth - Theme.COMBAT_HEADER_CHIP_WIDTH - Theme.COMBAT_HEADER_CHIP_GAP
					else titleWidth,
				titleHeight
			)
		end,
		PressAbandon = pressAbandon,
		SetRunState = setRunState,
		ShowNotice = function(text: string, seconds: number)
			local run = objective.run
			if run ~= nil and not LIVE_PHASES[run.phase] then
				return -- a late event after the run ended (see setRunState)
			end
			noticeLabel.Text = text
			objective.noticeUntil = os.clock() + math.max(seconds, 0)
			noticeFrame.Visible = seconds > 0
		end,
		SetWallet = function(cash: number, material: string, amount: number, valor: number)
			cashChip.Text = "$" .. Format.Cash(cash)
			-- No material, no chip: with no level to name one (the lobby) it read a bare "0".
			materialFrame.Visible = material ~= ""
			materialChip.Text = Format.Cash(amount) .. " " .. material
			valorChip.Text = Format.Cash(valor) .. " Valor"
		end,
		SetLayout = function(
			scale: number,
			viewportSize: Vector2,
			obstacles: { ActionRows.Obstacle }?
		)
			topScale.Scale = scale
			walletScale.Scale = scale
			noticeScale.Scale = scale
			partyScale.Scale = scale
			buttonScale.Scale = scale
			waitingScale.Scale = scale
			-- UIScale multiplies size, not position offsets, so margins scale by hand.
			local margin = Theme.SCREEN_MARGIN * scale
			local bottom = Theme.PADDING * scale
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
			-- The notice line hangs under the wallet, on the header's side of the screen.
			local noticeTop = margin
				+ (
						Theme.TOP_BAR_HEIGHT
						+ Theme.SCREEN_MARGIN
						+ Theme.COMBAT_WALLET_HEIGHT
						+ Theme.SCREEN_MARGIN
					)
					* scale
			noticeFrame.AnchorPoint = if landscape then Vector2.new(0, 0) else Vector2.new(0.5, 0)
			noticeFrame.Position = if landscape
				then UDim2.fromOffset(margin, noticeTop)
				else UDim2.new(0.5, 0, 0, noticeTop)
			-- Portrait stacks header, wallet and boss down the middle, so the party list
			-- starts below all three; landscape parks them at the left and the list can
			-- sit beside them at the top-right corner. The boss row is the range's boss bar
			-- at its tallest (plate row included).
			local bossBlock = Theme.COMBAT_RANGE_BOSS_BAR_PLATE_HEIGHT
				+ Theme.COMBAT_RANGE_BOSS_BAR_PLATE_GAP
				+ Theme.COMBAT_RANGE_BOSS_BAR_HEIGHT
			local headerBlock = Theme.TOP_BAR_HEIGHT
				+ Theme.COMBAT_WALLET_HEIGHT
				+ bossBlock
				+ Theme.SCREEN_MARGIN * 3
			local partyTop = if landscape then margin else margin + headerBlock * scale
			partyFrame.Position = UDim2.new(1, -margin, 0, partyTop)

			altHintScale.Scale = scale
			buttonRow.Position = UDim2.new(0, margin, 1, -bottom)
			keyHintScale.Scale = scale
			perfScale.Scale = scale
			rowState.scale = scale
			rowState.margin = margin
			rowState.base = bottom
			rowState.height = viewportSize.Y
			rowState.obstacles = obstacles or {}
			packActions(true)
			local headerWidth = Theme.TOP_BAR_WIDTH * scale
			return {
				headerBottom = margin
					+ (Theme.TOP_BAR_HEIGHT + Theme.SCREEN_MARGIN + Theme.COMBAT_WALLET_HEIGHT)
						* scale,
				headerRight = if landscape
					then margin + headerWidth
					else (viewportSize.X + headerWidth) / 2,
				partyLeft = viewportSize.X - margin - Theme.COMBAT_PARTY_WIDTH * scale,
				noticeBottom = noticeTop + Theme.COMBAT_CHECKPOINT_NOTICE_HEIGHT * scale,
			}
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			topFrame:Destroy()
			walletFrame:Destroy()
			noticeFrame:Destroy()
			partyFrame:Destroy()
			buttonRow:Destroy()
			altHint:Destroy()
			keyHint:Destroy()
			perf.line:Destroy()
			waitingFrame:Destroy()
		end,
		SetAiming = function(nextShoulder: boolean, cursorLocked: boolean)
			if nextShoulder == shoulderCamera and cursorLocked == cursorWasLocked then
				return -- polled every frame; only a change touches the instances
			end
			shoulderCamera = nextShoulder
			cursorWasLocked = cursorLocked
			altHint.Visible = fighting and shoulderCamera and keyHints
			altHint.Text = if cursorLocked then ALT_HINT_LOCKED else ALT_HINT_FREE
		end,
	}
	return handle
end

return CombatHud
