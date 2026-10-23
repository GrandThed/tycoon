--!strict
-- The run's tally card (docs/prompts/l4-w3-contract.md §4.2; MISSIONS_DESIGN §26 item 7): one card
-- in both places. The dungeon place shows it at the end of every run and on the trip home, the
-- city shows the session's card over the plot after the trip home. It replaced the two text cards
-- that came before it in both places.
--
-- The card is a short show with a clear rhythm, then a still record:
--  1. it opens (a small grow);
--  2. one row per source of pay (RunSummary.lines: the raiders, each camp's bonus, the Chief, each
--     chest, the key, the first clear, the mentor's Valor) slides in and counts up, in turn; the
--     rows scroll to follow the counting row on a short screen;
--  3. coins fly from the rows' cash into the card's wallet line, which rolls from what the player
--     had before the run to what they have now; Timber logs fly from the rows into a pile beside
--     the material count, one log per landing; Valor rolls beside them with the next ability.
-- A tap on the card outside a button jumps to the end; the buttons answer at any moment.
--
-- Every number is the server's: the rows and the totals are RunSummary's, the wallet is the last
-- Snapshot's (SetWallet retargets the roll when a later one lands). Nothing is computed here but
-- the in-between values of a count.
--
-- Phones: every duration goes through Motion.Seconds (halved under Theme.reducedMotion, which is
-- true on every touch device), and under reducedMotion the easing is linear and nothing overshoots,
-- as Motion.Info does for tweens. The flight still runs there, shortened. How many icons fly
-- follows Theme.lowEndDevice only (the living-city lesson: gating them on reducedMotion would hide
-- them from every phone). No sound: the combat place's sound ids stay 0, and the card plays none.
--
-- Fit: the card must fit a 640 x 360 phone under a 58 px top bar (329 design px of height). A
-- parent shorter than LOOK.wideBelowHeight design px (and wide enough) gets two columns: the rows
-- on the left, the totals and the buttons on the right, so the rows keep about nine lines on that
-- phone. Anything taller gets one column. The rows area shows what fits and scrolls (a first full
-- Forest Road run is up to 11 lines, 12 in a party); the totals never scroll. The rows scroll by
-- drag and wheel on a clipped strip moved in design px, not a ScrollingFrame, so the follow and
-- the tap-or-drag test do not depend on how a canvas position reads under a UIScale.
--
-- Every presentation constant and every word the card owns is in LOOK below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent:WaitForChild("Motion"))

local LOOK = {
	-- Sizes, in design px of the 375 x 667 canvas (the host's scale stretches them).
	width = 372, -- one column
	wideWidth = 620, -- two columns
	wideTotalsWidth = 236, -- the right column of two
	columnGap = 16,
	-- Two columns when the parent is shorter than this and at least wideMinWidth wide.
	wideBelowHeight = 440,
	wideMinWidth = 560,
	maxHeight = 600,
	margin = Theme.SCREEN_MARGIN,
	padding = 14,
	corner = Theme.CORNER_RADIUS,
	strokeThickness = 1.5,
	kickerHeight = 14,
	kickerText = 11,
	titleHeight = 26,
	titleText = Theme.TEXT_LARGE,
	starWidth = 26,
	subtitleHeight = 16,
	subtitleText = Theme.TEXT_SMALL,
	headerGap = 8,
	rowPitch = 24,
	rowHeight = 22,
	rowText = 13,
	rowMinText = 9,
	rowInset = 8,
	rowCashWidth = 68,
	rowMaterialWidth = 52,
	rowValorWidth = 42,
	rowIconSize = 8,
	rowIconGap = 3,
	rowCorner = 6,
	rowSlide = 14, -- a row slides in from this far right
	rowsMinHeight = 48, -- two rows, however short the screen
	thumbWidth = 3,
	keyIconWidth = 16,
	walletHeight = 30,
	walletText = 20,
	lineHeight = 24,
	lineText = Theme.TEXT_MEDIUM,
	valorHeight = 22,
	smallHeight = 16,
	smallText = Theme.TEXT_SMALL,
	iconColumn = 40, -- the totals' icons stand in this column, the numbers after it
	lineGap = 4,
	blockGap = 8,
	buttonHeight = Theme.DIALOG_BUTTON_HEIGHT, -- 48 x MIN_SCALE = the 44 px tap target
	buttonText = 13,
	buttonGap = 8,
	coinSize = 16,
	coinText = 11,
	logWidth = 14,
	logHeight = 4,
	logGap = 1,
	pileColumns = 2,
	diamondSize = 11,
	arc = 46, -- how high a flight bows over the straight line
	sway = 16, -- and how far to the side, alternating
	spin = 70, -- a log's turn at launch, in degrees, unwinding as it lands
	wheelStep = 24,
	tapSlop = 10, -- px a press on the rows may travel and still be a tap
	-- Motion, in base seconds: Motion.Seconds shortens each one under reducedMotion.
	popSeconds = 0.22,
	popScale = 0.94,
	rowGapSeconds = 0.3,
	rowsMaxSeconds = 2.8, -- many rows share this, so a long run does not drag
	rowCountSeconds = 0.42,
	rowFadeShare = 0.45, -- of the count, spent fading the row in
	rowFlashSeconds = 0.3,
	flightPauseSeconds = 0.15,
	flightSeconds = 0.62,
	flightSpreadSeconds = 0.6,
	logDelaySeconds = 0.12,
	valorSeconds = 0.4,
	pulseSeconds = 0.18,
	pulseGrow = 0.25,
	flightGrow = 0.3,
	scrollRate = 10, -- per second, how fast the rows follow the counting row
	-- How many icons fly, by device (Theme.lowEndDevice, never reducedMotion).
	coins = 14,
	coinsLowEnd = 5,
	logs = 8,
	logsLowEnd = 4,
	-- Colours.
	rowColor = Theme.COLOR_ROW,
	rowTransparency = 0.3,
	rowFlashTransparency = 0,
	rowFlashColor = Theme.COLOR_BG_LIGHT,
	strokeColor = Theme.COLOR_HIGHLIGHT,
	strokeTransparency = 0.5,
	scrimTransparency = Theme.LOAD_SCRIM_TRANSPARENCY,
	modalScrimTransparency = Theme.SCRIM_TRANSPARENCY,
	dividerColor = Theme.COLOR_BG_LIGHT,
	cashColor = Theme.COLOR_ACCENT,
	valorColor = Theme.COLOR_HIGHLIGHT,
	gold = Color3.fromRGB(255, 200, 61),
	coinColor = Color3.fromRGB(255, 186, 46),
	coinRim = Color3.fromRGB(170, 112, 18),
	coinInk = Color3.fromRGB(96, 60, 8),
	logColor = Color3.fromRGB(150, 98, 54),
	logEnd = Color3.fromRGB(222, 178, 120),
	-- Words the card owns; the hosts own the title, the subtitle, the note and the buttons.
	star = "★",
	cash = "$",
	plus = "+",
	raiders = "Raiders",
	times = " ×",
	camp = "Camp",
	campSuffix = " bonus",
	boss = "The boss",
	chest = "A chest",
	key = "A key",
	keySuffix = " found",
	firstClear = "First ",
	firstClearSuffix = " clear",
	mentor = "Mentor bonus",
	empty = "Nothing earned this time",
	valorWord = " Valor",
	next = "next: ",
	nextSep = " · ",
	withThe = "with the ",
	with = "with ",
}

-- One display row (RunTally.Rows builds them from RunSummary.lines, so both hosts agree).
export type Row = {
	kind: string,
	label: string,
	cash: number,
	material: string,
	materials: number,
	valor: number,
}
export type Totals = { cash: number, material: string, materials: number, valor: number }
-- What the player owns now; `materials` is the amount of Totals.material.
export type Wallet = { cash: number, materials: number, valor: number }
export type Button = { id: string, text: string, accent: boolean? }
export type View = {
	kicker: string,
	title: string,
	subtitle: string?,
	star: boolean,
	lines: { Row },
	totals: Totals,
	wallet: Wallet,
	note: string?,
	nextAbility: string?,
	buttons: { Button },
}
export type Deps = {
	onButton: (id: string) -> (),
	-- True = the dim behind the card takes every tap (the city: a stray tap must not buy a
	-- building), and a tap on it skips like one on the card. False or nil = it takes none (the
	-- dungeon place: it must never swallow the camera drag behind it).
	modal: boolean?,
}
export type Handle = {
	Show: (view: View) -> (),
	SetWallet: (wallet: Wallet) -> (),
	SetCountdown: (text: string?) -> (),
	Skip: () -> (),
	Hide: () -> (),
	IsVisible: () -> boolean,
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

type RowUi = {
	frame: Frame,
	label: TextLabel,
	cash: TextLabel,
	material: TextLabel,
	valor: TextLabel,
	logIcon: Frame,
	diamond: Frame,
	row: Row,
	settled: boolean,
}
type Sprite = {
	gui: Frame,
	coin: boolean,
	row: number,
	slot: number,
	launch: number,
	land: number,
	sway: number,
	from: Vector2?,
	landed: boolean,
}
type Drag = { input: InputObject?, startY: number, startScroll: number, moved: number }

local RunTally = {}

local function clamp01(x: number): number
	return math.min(math.max(x, 0), 1)
end

-- Out-quad, or linear under reducedMotion (as Motion.Info does for tweens).
local function ease(x: number): number
	if Theme.reducedMotion then
		return x
	end
	return 1 - (1 - x) * (1 - x)
end

-- A flight leaves at once and speeds up into its target, so it reads as being collected.
local function easeIn(x: number): number
	if Theme.reducedMotion then
		return x
	end
	return 0.35 * x + 0.65 * x * x
end

-- How far through a window [from, to] the clock is, eased; a window of no length is a step.
local function windowAt(t: number, from: number, to: number): number
	if to <= from then
		return if t >= to then 1 else 0
	end
	return ease(clamp01((t - from) / (to - from)))
end

local function plusText(value: number, prefix: string): string
	if value <= 0 then
		return ""
	end
	return LOOK.plus .. prefix .. Format.Cash(value)
end

local function nodeName(nodeId: string): string
	local config = Catalog.GetExpeditionsConfig()
	if config ~= nil then
		for _, node in config.nodes do
			if node.id == nodeId then
				return node.name
			end
		end
	end
	return nodeId
end

-- "with the Castle": the words for an ability or a weapon that comes with a later map node. A
-- name that already starts with an article keeps its own ("with another Planet", "with the Dream").
function RunTally.WithText(nodeId: string): string
	local name = nodeName(nodeId)
	local first, rest = string.match(name, "^(%a+) (.+)$")
	if first == "The" and rest ~= nil then
		return LOOK.withThe .. rest
	end
	if (first == "A" or first == "An" or first == "Another") and rest ~= nil then
		return LOOK.with .. string.lower(first) .. " " .. rest
	end
	return LOOK.withThe .. name
end

-- The row words for each kind of line. A name the server sends empty takes the card's word.
function RunTally.Rows(lines: { Types.RunLine }?): { Row }
	local rows: { Row } = {}
	if lines == nil then
		return rows
	end
	local config = Catalog.GetExpeditionsConfig()
	for _, line in lines do
		local kind = line.kind
		local name = line.name
		local label: string
		if kind == "raiders" then
			label = (if name ~= "" then name else LOOK.raiders)
				.. (if line.count > 0 then LOOK.times .. Format.Cash(line.count) else "")
		elseif kind == "camp" then
			label = (if name ~= "" then name else LOOK.camp) .. LOOK.campSuffix
		elseif kind == "boss" then
			label = if name ~= "" then name else LOOK.boss
		elseif kind == "chest" then
			label = if name ~= "" then name else LOOK.chest
		elseif kind == "key" then
			label = (if name ~= "" then name else LOOK.key) .. LOOK.keySuffix
		elseif kind == "firstClear" then
			-- The id is "<levelId>:<difficulty>"; the difficulty's display name is the map's.
			local difficulty = string.match(line.id, ":([^:]+)$") or ""
			local word = if config ~= nil then config.difficultyNames[difficulty] else nil
			label = LOOK.firstClear .. (word or difficulty) .. LOOK.firstClearSuffix
		elseif kind == "mentor" then
			label = LOOK.mentor
		else
			label = if name ~= "" then name else kind
		end
		table.insert(rows, {
			kind = kind,
			label = label,
			cash = line.cash,
			material = line.material,
			materials = line.materials,
			valor = line.valor,
		})
	end
	return rows
end

-- The summary's totals, with its main material: the largest amount, ties by name (the table came
-- over the network, so its order is undefined and the same run must read the same twice).
function RunTally.Totals(summary: Types.RunSummary): Totals
	local material, amount = "", 0
	for name, value in summary.materials do
		if
			typeof(name) == "string"
			and typeof(value) == "number"
			and value > 0
			and (value > amount or (value == amount and name < material))
		then
			material, amount = name, value
		end
	end
	return { cash = summary.cash, material = material, materials = amount, valor = summary.valor }
end

-- What a profile's material map holds of `material` (0 for anything that is not a count).
function RunTally.Owned(materials: { [string]: any }?, material: string): number
	if materials == nil or material == "" then
		return 0
	end
	local value = materials[material]
	return if typeof(value) == "number" and value > 0 then value else 0
end

-- Valor's purpose on the card (contract §7): the first ability on sale the player does not own
-- ("next: Double Jump · 10 Valor"; what Unlocks.Sellable sells, by `order`), else the first coming
-- one ("next: Glide · with the Castle"), else nil (no Expeditions config, or everything is owned).
function RunTally.NextAbility(owned: { [string]: boolean }?): string?
	local config = Catalog.GetExpeditionsConfig()
	local best: Types.UnlockAbilityDef? = nil
	for _, def in (Unlocks.Sellable(config)) do
		if not Unlocks.Owns(owned, def.id) and (best == nil or def.order < best.order) then
			best = def
		end
	end
	if best ~= nil then
		return LOOK.next
			.. best.name
			.. LOOK.nextSep
			.. Format.Cash(best.price.valor)
			.. LOOK.valorWord
	end
	local abilities = if config ~= nil then config.abilities else nil
	local upcoming = if abilities ~= nil then abilities.upcoming else nil
	if upcoming ~= nil then
		for _, def in upcoming do
			if not Unlocks.Owns(owned, def.id) then
				return LOOK.next .. def.name .. LOOK.nextSep .. RunTally.WithText(def.with)
			end
		end
	end
	return nil
end

-- Every layer of the card sits on the card tier, so it orders the same under either ZIndex rule.
local function z(layer: number): number
	return Theme.ZINDEX_CARD + layer
end

local function text(
	name: string,
	parent: Instance,
	size: number,
	font: Enum.Font,
	color: Color3,
	align: Enum.TextXAlignment
): TextLabel
	return Create("TextLabel", {
		Name = name,
		Active = false,
		BackgroundTransparency = 1,
		Font = font,
		TextSize = size,
		TextColor3 = color,
		TextXAlignment = align,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		ZIndex = z(2),
		Parent = parent,
	}) :: TextLabel
end

local function round(parent: Instance, radius: UDim): ()
	Create("UICorner", { CornerRadius = radius, Parent = parent })
end

-- A coin: a gold disc with a rim and a "$".
local function newCoin(parent: Instance, size: number, layer: number): Frame
	local coin = Create("Frame", {
		Name = "Coin",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = LOOK.coinColor,
		BorderSizePixel = 0,
		ZIndex = z(layer),
		Parent = parent,
	}) :: Frame
	round(coin, UDim.new(0.5, 0))
	Create("UIStroke", {
		Color = LOOK.coinRim,
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = coin,
	})
	Create("TextLabel", {
		Name = "Mark",
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_BOLD,
		TextSize = math.floor(size * LOOK.coinText / LOOK.coinSize),
		TextColor3 = LOOK.coinInk,
		Text = LOOK.cash,
		ZIndex = z(layer),
		Parent = coin,
	})
	return coin
end

-- A log: a bark bar with a pale cut end.
local function newLog(parent: Instance, width: number, height: number, layer: number): Frame
	local log = Create("Frame", {
		Name = "Log",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = LOOK.logColor,
		BorderSizePixel = 0,
		ZIndex = z(layer),
		Parent = parent,
	}) :: Frame
	round(log, UDim.new(0.5, 0))
	local cut = Create("Frame", {
		Name = "Cut",
		Active = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, height, 1, 0),
		BackgroundColor3 = LOOK.logEnd,
		BorderSizePixel = 0,
		ZIndex = z(layer),
		Parent = log,
	}) :: Frame
	round(cut, UDim.new(0.5, 0))
	return log
end

-- Valor's badge: a turned square.
local function newDiamond(parent: Instance, size: number, layer: number): Frame
	return Create("Frame", {
		Name = "Valor",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = LOOK.valorColor,
		BorderSizePixel = 0,
		ZIndex = z(layer),
		Parent = parent,
	}) :: Frame
end

-- A level key drawn from Frames (the map's way, so it reads the same in every font): a ring for
-- the bow, a bar for the shaft, a short bar down for the bit.
local function newKeyIcon(parent: Instance, width: number, layer: number): Frame
	local icon = Create("Frame", {
		Name = "KeyIcon",
		Active = false,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(width, width / 2),
		BackgroundTransparency = 1,
		ZIndex = z(layer),
		Parent = parent,
	}) :: Frame
	local bow = Create("Frame", {
		Name = "Bow",
		Active = false,
		Size = UDim2.fromScale(0.5, 1),
		BackgroundTransparency = 1,
		ZIndex = z(layer),
		Parent = icon,
	}) :: Frame
	round(bow, UDim.new(0.5, 0))
	Create("UIStroke", {
		Color = LOOK.gold,
		Thickness = 1.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = bow,
	})
	for _, part in { { 0.5, 0.4, 0.5, 0.2 }, { 0.82, 0.4, 0.14, 0.55 } } do
		Create("Frame", {
			Name = "Bar",
			Active = false,
			Position = UDim2.fromScale(part[1], part[2]),
			Size = UDim2.fromScale(part[3], part[4]),
			BackgroundColor3 = LOOK.gold,
			BorderSizePixel = 0,
			ZIndex = z(layer),
			Parent = icon,
		})
	end
	return icon
end

local function labelColor(kind: string): Color3
	if kind == "boss" or kind == "firstClear" or kind == "key" then
		return LOOK.gold
	elseif kind == "mentor" then
		return Theme.COLOR_ACCENT_ALT
	elseif kind == "empty" then
		return Theme.COLOR_TEXT_DIM
	end
	return Theme.COLOR_TEXT
end

function RunTally.new(parent: Instance, deps: Deps): Handle
	local connections: { RBXScriptConnection } = {}
	local modal = deps.modal == true

	-- The dim behind the card. Not modal: a Frame that takes no input, so the camera drag behind
	-- it still works. Modal: a button that takes every tap (and skips).
	local scrimProps: { [string]: any } = {
		Name = "RunTally",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = if modal
			then LOOK.modalScrimTransparency
			else LOOK.scrimTransparency,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}
	if modal then
		scrimProps.Text = ""
		scrimProps.AutoButtonColor = false
	else
		scrimProps.Active = false
	end
	local scrim = Create(if modal then "TextButton" else "Frame", scrimProps) :: GuiObject

	local card = Create("Frame", {
		Name = "Card",
		Active = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(LOOK.width, LOOK.rowsMinHeight),
		BackgroundColor3 = Theme.COLOR_BG,
		BorderSizePixel = 0,
		ZIndex = z(0),
		Parent = scrim,
	}) :: Frame
	round(card, UDim.new(0, LOOK.corner))
	Create("UIStroke", {
		Color = LOOK.strokeColor,
		Transparency = LOOK.strokeTransparency,
		Thickness = LOOK.strokeThickness,
		Parent = card,
	})
	local uiScale = Create("UIScale", { Parent = card }) :: UIScale
	-- Under everything on the card: a tap anywhere that is not a button skips to the end.
	local catcher = Create("TextButton", {
		Name = "Skip",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		AutoButtonColor = false,
		ZIndex = z(1),
		Parent = card,
	}) :: TextButton

	local header = {
		kicker = text(
			"Kicker",
			card,
			LOOK.kickerText,
			Theme.FONT_BOLD,
			Theme.COLOR_TEXT_DIM,
			Enum.TextXAlignment.Left
		),
		countdown = text(
			"Countdown",
			card,
			LOOK.kickerText,
			Theme.FONT_BOLD,
			Theme.COLOR_ACCENT_ALT,
			Enum.TextXAlignment.Right
		),
		title = text(
			"Title",
			card,
			LOOK.titleText,
			Theme.FONT_BOLD,
			Theme.COLOR_TEXT,
			Enum.TextXAlignment.Left
		),
		star = text(
			"Star",
			card,
			LOOK.titleText,
			Theme.FONT_BOLD,
			LOOK.gold,
			Enum.TextXAlignment.Right
		),
		subtitle = text(
			"Subtitle",
			card,
			LOOK.subtitleText,
			Theme.FONT,
			Theme.COLOR_TEXT_DIM,
			Enum.TextXAlignment.Left
		),
	}
	header.star.Text = LOOK.star
	local starScale = Create("UIScale", { Parent = header.star }) :: UIScale

	-- The rows: a clipped window over a strip that moves (see the header for why not a canvas).
	local rowsClip = Create("Frame", {
		Name = "Rows",
		Active = true,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = z(2),
		Parent = card,
	}) :: Frame
	local strip = Create("Frame", {
		Name = "Strip",
		Active = false,
		BackgroundTransparency = 1,
		ZIndex = z(2),
		Parent = rowsClip,
	}) :: Frame
	local thumb = Create("Frame", {
		Name = "Thumb",
		Active = false,
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Theme.COLOR_TEXT_DIM,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = z(3),
		Parent = rowsClip,
	}) :: Frame
	round(thumb, UDim.new(0.5, 0))
	local divider = Create("Frame", {
		Name = "Divider",
		Active = false,
		BackgroundColor3 = LOOK.dividerColor,
		BorderSizePixel = 0,
		ZIndex = z(2),
		Parent = card,
	}) :: Frame

	-- The totals: the wallet, the material and its pile, Valor, the next ability, the note, the
	-- buttons. Never scrolled.
	local totalsFrame = Create("Frame", {
		Name = "Totals",
		Active = false,
		BackgroundTransparency = 1,
		ZIndex = z(2),
		Parent = card,
	}) :: Frame
	local totals = {
		coin = newCoin(totalsFrame, LOOK.walletHeight - 8, 2),
		wallet = text(
			"Wallet",
			totalsFrame,
			LOOK.walletText,
			Theme.FONT_BOLD,
			LOOK.cashColor,
			Enum.TextXAlignment.Left
		),
		walletGain = text(
			"WalletGain",
			totalsFrame,
			LOOK.lineText,
			Theme.FONT_BOLD,
			LOOK.cashColor,
			Enum.TextXAlignment.Right
		),
		pile = Create("Frame", {
			Name = "Pile",
			Active = false,
			BackgroundTransparency = 1,
			ZIndex = z(2),
			Parent = totalsFrame,
		}) :: Frame,
		material = text(
			"Material",
			totalsFrame,
			LOOK.lineText,
			Theme.FONT_BOLD,
			Theme.COLOR_TEXT,
			Enum.TextXAlignment.Left
		),
		materialGain = text(
			"MaterialGain",
			totalsFrame,
			LOOK.lineText,
			Theme.FONT_BOLD,
			Theme.COLOR_TEXT,
			Enum.TextXAlignment.Right
		),
		diamond = newDiamond(totalsFrame, LOOK.diamondSize, 2),
		valor = text(
			"Valor",
			totalsFrame,
			LOOK.lineText,
			Theme.FONT_BOLD,
			LOOK.valorColor,
			Enum.TextXAlignment.Left
		),
		valorGain = text(
			"ValorGain",
			totalsFrame,
			LOOK.lineText,
			Theme.FONT_BOLD,
			LOOK.valorColor,
			Enum.TextXAlignment.Right
		),
		nextLine = text(
			"Next",
			totalsFrame,
			LOOK.smallText,
			Theme.FONT,
			Theme.COLOR_TEXT_DIM,
			Enum.TextXAlignment.Left
		),
		note = text(
			"Note",
			totalsFrame,
			LOOK.smallText,
			Theme.FONT_BOLD,
			Theme.COLOR_HIGHLIGHT,
			Enum.TextXAlignment.Left
		),
		buttons = Create("Frame", {
			Name = "Buttons",
			Active = false,
			BackgroundTransparency = 1,
			ZIndex = z(2),
			Parent = totalsFrame,
		}) :: Frame,
	}
	totals.note.TextWrapped = true
	totals.note.TextTruncate = Enum.TextTruncate.None
	totals.note.TextYAlignment = Enum.TextYAlignment.Top
	local coinScale = Create("UIScale", { Parent = totals.coin }) :: UIScale
	local pileScale = Create("UIScale", { Parent = totals.pile }) :: UIScale
	local diamondScale = Create("UIScale", { Parent = totals.diamond }) :: UIScale
	local pileLogs: { Frame } = {}
	for index = 1, LOOK.logs do
		local column = (index - 1) % LOOK.pileColumns
		local level = math.floor((index - 1) / LOOK.pileColumns)
		local log = newLog(totals.pile, LOOK.logWidth, LOOK.logHeight, 2)
		log.AnchorPoint = Vector2.new(0, 1)
		log.Position = UDim2.new(
			0,
			column * (LOOK.logWidth + LOOK.logGap) + (level % 2) * LOOK.logGap * 2,
			1,
			-level * (LOOK.logHeight + LOOK.logGap)
		)
		log.Visible = false
		pileLogs[index] = log
	end

	-- Above everything: the flying coins and logs.
	local flyLayer = Create("Frame", {
		Name = "Flights",
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z(4),
		Parent = card,
	}) :: Frame

	-- Where things are, in design px of the card, from the last layout pass.
	local geo = {
		width = LOOK.width,
		height = LOOK.rowsMinHeight,
		rowsPos = Vector2.zero,
		rowsSize = Vector2.zero,
		rowWidth = 0, -- a row's width: the rows' less the scroll thumb's room when they overflow
		totalsPos = Vector2.zero,
		totalsWidth = 0,
		pileLocal = Vector2.zero, -- the pile's bottom-left, in the totals block
		pileOrigin = Vector2.zero, -- the same, in the card
		coinAt = Vector2.zero, -- the wallet coin's centre, in the card
	}
	-- What is being shown and how far the show has got.
	local live = {
		view = nil :: View?,
		rows = {} :: { RowUi },
		sprites = {} :: { Sprite },
		buttons = {} :: { TextButton },
		target = { cash = 0, materials = 0, valor = 0 } :: Wallet,
		clock = 0,
		rowStart = {} :: { number },
		rowCount = 0,
		open = 0,
		gainsAt = 0,
		walletAt = { 0, 0 },
		materialAt = { 0, 0 },
		valorAt = { 0, 0 },
		done = 0,
		logCount = 0,
		landedLogs = 0,
		walletPulse = -math.huge,
		pilePulse = -math.huge,
		scale = 1,
		viewport = Vector2.zero,
		scrollY = 0,
		userScrolled = false,
		drag = nil :: Drag?,
		stepper = nil :: RBXScriptConnection?,
	}

	local function rowsContent(): number
		return math.max(#live.rows, 1) * LOOK.rowPitch
	end

	local function maxScroll(): number
		return math.max(rowsContent() - geo.rowsSize.Y, 0)
	end

	local function applyScroll(): ()
		live.scrollY = math.min(math.max(live.scrollY, 0), maxScroll())
		strip.Position = UDim2.fromOffset(0, -live.scrollY)
		local content = rowsContent()
		local view = geo.rowsSize.Y
		thumb.Visible = content > view + 0.5
		if thumb.Visible then
			local height = math.max(view * view / content, LOOK.rowPitch)
			local range = math.max(maxScroll(), 1)
			thumb.Size = UDim2.fromOffset(LOOK.thumbWidth, height)
			thumb.Position = UDim2.new(1, 0, 0, (view - height) * live.scrollY / range)
		end
	end

	-- The note's height at the totals' width: wrapped, measured.
	local function noteHeight(width: number): number
		local view = live.view
		local note = if view ~= nil then view.note else nil
		if note == nil or note == "" or width <= 0 then
			return 0
		end
		local size = TextService:GetTextSize(
			note,
			LOOK.smallText,
			Theme.FONT_BOLD,
			Vector2.new(width, 10000)
		)
		return math.ceil(size.Y)
	end

	-- The totals block's height at a width, buttons included, and its pieces laid out.
	local function layoutTotals(width: number, height: number?): number
		local view = live.view
		local y = 0
		local labelX = LOOK.iconColumn
		local labelWidth = math.max(width - labelX, 0)
		local half = labelWidth / 2
		totals.coin.Position = UDim2.fromOffset(LOOK.iconColumn / 2 - 4, LOOK.walletHeight / 2)
		totals.wallet.Position = UDim2.fromOffset(labelX, 0)
		totals.wallet.Size = UDim2.fromOffset(labelWidth, LOOK.walletHeight)
		totals.walletGain.Position = UDim2.fromOffset(labelX + half, 0)
		totals.walletGain.Size = UDim2.fromOffset(half, LOOK.walletHeight)
		y += LOOK.walletHeight + LOOK.lineGap
		local hasMaterial = view ~= nil and view.totals.material ~= ""
		totals.pile.Visible = hasMaterial
		totals.material.Visible = hasMaterial
		totals.materialGain.Visible = hasMaterial
		if hasMaterial then
			local pileWidth = LOOK.pileColumns * (LOOK.logWidth + LOOK.logGap) + LOOK.logGap * 2
			totals.pile.Position = UDim2.fromOffset(0, y)
			totals.pile.Size = UDim2.fromOffset(pileWidth, LOOK.lineHeight)
			totals.material.Position = UDim2.fromOffset(labelX, y)
			totals.material.Size = UDim2.fromOffset(labelWidth, LOOK.lineHeight)
			totals.materialGain.Position = UDim2.fromOffset(labelX + half, y)
			totals.materialGain.Size = UDim2.fromOffset(half, LOOK.lineHeight)
			geo.pileLocal = Vector2.new(0, y + LOOK.lineHeight)
			y += LOOK.lineHeight + LOOK.lineGap
		end
		totals.diamond.Position =
			UDim2.fromOffset(LOOK.iconColumn / 2 - 4, y + LOOK.valorHeight / 2)
		totals.valor.Position = UDim2.fromOffset(labelX, y)
		totals.valor.Size = UDim2.fromOffset(labelWidth, LOOK.valorHeight)
		totals.valorGain.Position = UDim2.fromOffset(labelX + half, y)
		totals.valorGain.Size = UDim2.fromOffset(half, LOOK.valorHeight)
		y += LOOK.valorHeight
		local nextText = if view ~= nil then view.nextAbility else nil
		totals.nextLine.Visible = nextText ~= nil and nextText ~= ""
		if totals.nextLine.Visible then
			totals.nextLine.Text = nextText :: string
			totals.nextLine.Position = UDim2.fromOffset(labelX, y)
			totals.nextLine.Size = UDim2.fromOffset(labelWidth, LOOK.smallHeight)
			y += LOOK.smallHeight
		end
		local noteH = noteHeight(width)
		totals.note.Visible = noteH > 0
		if noteH > 0 then
			y += LOOK.lineGap
			totals.note.Position = UDim2.fromOffset(0, y)
			totals.note.Size = UDim2.fromOffset(width, noteH)
			y += noteH
		end
		local count = #live.buttons
		totals.buttons.Visible = count > 0
		if count > 0 then
			y += LOOK.blockGap
			-- Two columns pin the buttons to the bottom of the column; one column stacks them.
			local top = if height ~= nil then math.max(height - LOOK.buttonHeight, y) else y
			totals.buttons.Position = UDim2.fromOffset(0, top)
			totals.buttons.Size = UDim2.fromOffset(width, LOOK.buttonHeight)
			local each = (width - LOOK.buttonGap * (count - 1)) / count
			for index, item in live.buttons do
				item.Position = UDim2.fromOffset((index - 1) * (each + LOOK.buttonGap), 0)
				item.Size = UDim2.fromOffset(each, LOOK.buttonHeight)
			end
			y = top + LOOK.buttonHeight
		end
		return y
	end

	local function layoutRow(index: number, ui: RowUi, width: number): ()
		ui.frame.Size = UDim2.fromOffset(width, LOOK.rowHeight)
		local right = width - LOOK.rowInset
		ui.valor.Position = UDim2.fromOffset(right - LOOK.rowValorWidth, 0)
		ui.valor.Size = UDim2.fromOffset(
			LOOK.rowValorWidth - LOOK.rowIconSize - LOOK.rowIconGap,
			LOOK.rowHeight
		)
		ui.diamond.Position = UDim2.new(0, right - LOOK.rowIconSize / 2, 0.5, 0)
		right -= LOOK.rowValorWidth
		ui.material.Position = UDim2.fromOffset(right - LOOK.rowMaterialWidth, 0)
		ui.material.Size = UDim2.fromOffset(
			LOOK.rowMaterialWidth - LOOK.rowIconSize - LOOK.rowIconGap,
			LOOK.rowHeight
		)
		ui.logIcon.Position = UDim2.new(0, right - LOOK.rowIconSize / 2, 0.5, 0)
		right -= LOOK.rowMaterialWidth
		ui.cash.Position = UDim2.fromOffset(right - LOOK.rowCashWidth, 0)
		ui.cash.Size = UDim2.fromOffset(LOOK.rowCashWidth, LOOK.rowHeight)
		right -= LOOK.rowCashWidth
		local labelX = LOOK.rowInset + (if ui.row.kind == "key" then LOOK.keyIconWidth + 4 else 0)
		ui.label.Position = UDim2.fromOffset(labelX, 0)
		ui.label.Size = UDim2.fromOffset(math.max(right - labelX - 4, 0), LOOK.rowHeight)
		ui.frame.Position = UDim2.fromOffset(0, (index - 1) * LOOK.rowPitch)
	end

	-- The whole card at the parent's size: one column, or two on a short wide parent.
	local function relayout(): ()
		local scale = live.scale
		local viewport = live.viewport
		if (viewport.X <= 0 or viewport.Y <= 0) and parent:IsA("GuiBase2d") then
			-- Shown before the host's first layout pass: the parent's own size, at the scale so far.
			viewport = (parent :: GuiBase2d).AbsoluteSize
		end
		if scale <= 0 or viewport.X <= 0 or viewport.Y <= 0 then
			return
		end
		local availWidth = math.max(viewport.X / scale - 2 * LOOK.margin, 0)
		local availHeight =
			math.min(math.max(viewport.Y / scale - 2 * LOOK.margin, 0), LOOK.maxHeight)
		local wide = viewport.Y / scale < LOOK.wideBelowHeight and availWidth >= LOOK.wideMinWidth
		local pad = LOOK.padding
		local width = math.min(if wide then LOOK.wideWidth else LOOK.width, availWidth)
		local inner = math.max(width - 2 * pad, 0)
		local view = live.view
		local hasSubtitle = view ~= nil and view.subtitle ~= nil and view.subtitle ~= ""

		-- The header: kicker and countdown on one line, the title and its star, the subtitle.
		header.kicker.Position = UDim2.fromOffset(pad, pad)
		header.kicker.Size = UDim2.fromOffset(inner, LOOK.kickerHeight)
		header.countdown.Position = UDim2.fromOffset(pad, pad)
		header.countdown.Size = UDim2.fromOffset(inner, LOOK.kickerHeight)
		local titleY = pad + LOOK.kickerHeight
		header.title.Position = UDim2.fromOffset(pad, titleY)
		header.title.Size = UDim2.fromOffset(math.max(inner - LOOK.starWidth, 0), LOOK.titleHeight)
		header.star.Position = UDim2.fromOffset(pad + inner - LOOK.starWidth, titleY)
		header.star.Size = UDim2.fromOffset(LOOK.starWidth, LOOK.titleHeight)
		local headerBottom = titleY + LOOK.titleHeight
		header.subtitle.Visible = hasSubtitle
		if hasSubtitle then
			header.subtitle.Position = UDim2.fromOffset(pad, headerBottom)
			header.subtitle.Size = UDim2.fromOffset(inner, LOOK.subtitleHeight)
			headerBottom += LOOK.subtitleHeight
		end
		local bodyTop = headerBottom + LOOK.headerGap
		local content = rowsContent()

		local height: number
		if wide then
			local totalsWidth = LOOK.wideTotalsWidth
			local rowsWidth = math.max(inner - totalsWidth - LOOK.columnGap, 0)
			local totalsNeed = layoutTotals(totalsWidth, nil)
			height = math.min(bodyTop + math.max(content, totalsNeed) + pad, availHeight)
			local bodyHeight = math.max(height - bodyTop - pad, 0)
			geo.rowsPos = Vector2.new(pad, bodyTop)
			geo.rowsSize = Vector2.new(rowsWidth, bodyHeight)
			geo.totalsPos = Vector2.new(pad + rowsWidth + LOOK.columnGap, bodyTop)
			geo.totalsWidth = totalsWidth
			layoutTotals(totalsWidth, bodyHeight)
			divider.Position = UDim2.fromOffset(pad + rowsWidth + LOOK.columnGap / 2, bodyTop)
			divider.Size = UDim2.fromOffset(1, bodyHeight)
		else
			local totalsNeed = layoutTotals(inner, nil)
			local fixed = bodyTop + LOOK.blockGap * 2 + 1 + totalsNeed + pad
			local rowsHeight = math.min(
				content,
				math.max(availHeight - fixed, math.min(LOOK.rowsMinHeight, content))
			)
			height = fixed + rowsHeight
			geo.rowsPos = Vector2.new(pad, bodyTop)
			geo.rowsSize = Vector2.new(inner, rowsHeight)
			local dividerY = bodyTop + rowsHeight + LOOK.blockGap
			divider.Position = UDim2.fromOffset(pad, dividerY)
			divider.Size = UDim2.fromOffset(inner, 1)
			geo.totalsPos = Vector2.new(pad, dividerY + 1 + LOOK.blockGap)
			geo.totalsWidth = inner
		end
		geo.width = width
		geo.height = height
		card.Size = UDim2.fromOffset(width, height)
		rowsClip.Position = UDim2.fromOffset(geo.rowsPos.X, geo.rowsPos.Y)
		rowsClip.Size = UDim2.fromOffset(geo.rowsSize.X, geo.rowsSize.Y)
		strip.Size = UDim2.fromOffset(geo.rowsSize.X, content)
		totalsFrame.Position = UDim2.fromOffset(geo.totalsPos.X, geo.totalsPos.Y)
		totalsFrame.Size = UDim2.fromOffset(geo.totalsWidth, height - geo.totalsPos.Y - pad)
		geo.pileOrigin = geo.totalsPos + geo.pileLocal
		geo.coinAt = geo.totalsPos + Vector2.new(LOOK.iconColumn / 2 - 4, LOOK.walletHeight / 2)
		-- Leave room for the scroll thumb when the rows overflow.
		geo.rowWidth = geo.rowsSize.X
			- (if content > geo.rowsSize.Y + 0.5 then LOOK.thumbWidth + 2 else 0)
		for index, ui in live.rows do
			layoutRow(index, ui, geo.rowWidth)
		end
		applyScroll()
	end

	-- Where a sprite starts: its row's cash (a coin) or material (a log) cell, held inside the
	-- rows window when that row has scrolled out of it.
	local function sourcePoint(sprite: Sprite): Vector2
		local width = geo.rowWidth
		local x = if sprite.coin
			then width
				- LOOK.rowInset
				- LOOK.rowValorWidth
				- LOOK.rowMaterialWidth
				- LOOK.rowCashWidth / 2
			else width - LOOK.rowInset - LOOK.rowValorWidth - LOOK.rowMaterialWidth / 2
		local y = (sprite.row - 0.5) * LOOK.rowPitch - live.scrollY
		y = math.min(
			math.max(y, LOOK.rowHeight / 2),
			math.max(geo.rowsSize.Y - LOOK.rowHeight / 2, 0)
		)
		return geo.rowsPos + Vector2.new(x, y)
	end

	-- Where a sprite lands: the wallet's coin, or the log's own place in the pile.
	local function targetPoint(sprite: Sprite): Vector2
		if sprite.coin then
			return geo.coinAt
		end
		local column = (sprite.slot - 1) % LOOK.pileColumns
		local level = math.floor((sprite.slot - 1) / LOOK.pileColumns)
		return geo.pileOrigin
			+ Vector2.new(
				column * (LOOK.logWidth + LOOK.logGap)
					+ (level % 2) * LOOK.logGap * 2
					+ LOOK.logWidth / 2,
				-level * (LOOK.logHeight + LOOK.logGap) - LOOK.logHeight / 2
			)
	end

	local function clearSprites(): ()
		for _, sprite in live.sprites do
			sprite.gui:Destroy()
		end
		table.clear(live.sprites)
	end

	local function paintRow(index: number, ui: RowUi, t: number): ()
		if ui.settled then
			return
		end
		local start = live.rowStart[index] or 0
		local p = (t - start) / math.max(live.rowCount, 1e-3)
		if p < 0 then
			ui.frame.Visible = false
			return
		end
		ui.frame.Visible = true
		local fade = ease(clamp01(p / LOOK.rowFadeShare))
		local share = ease(clamp01(p))
		local row = ui.row
		ui.frame.Position =
			UDim2.fromOffset((1 - fade) * LOOK.rowSlide, (index - 1) * LOOK.rowPitch)
		local textFade = 1 - fade
		ui.label.TextTransparency = textFade
		ui.cash.TextTransparency = textFade
		ui.material.TextTransparency = textFade
		ui.valor.TextTransparency = textFade
		if row.kind ~= "key" and row.kind ~= "empty" then
			ui.cash.Text = plusText(row.cash * share, LOOK.cash)
			ui.material.Text = plusText(row.materials * share, "")
			ui.valor.Text = plusText(row.valor * share, "")
		end
		-- A row lands with a short flash of its background.
		local flash = (t - start - live.rowCount) / Motion.Seconds(LOOK.rowFlashSeconds)
		if flash >= 0 and flash < 1 and not Theme.reducedMotion then
			ui.frame.BackgroundColor3 = LOOK.rowFlashColor:Lerp(LOOK.rowColor, flash)
			ui.frame.BackgroundTransparency = LOOK.rowFlashTransparency
				+ (LOOK.rowTransparency - LOOK.rowFlashTransparency) * flash
		else
			ui.frame.BackgroundColor3 = LOOK.rowColor
			ui.frame.BackgroundTransparency = 1 - (1 - LOOK.rowTransparency) * fade
		end
		if p >= 1 and (flash >= 1 or Theme.reducedMotion) then
			ui.frame.Position = UDim2.fromOffset(0, (index - 1) * LOOK.rowPitch)
			ui.frame.BackgroundColor3 = LOOK.rowColor
			ui.frame.BackgroundTransparency = LOOK.rowTransparency
			ui.settled = true
		end
	end

	local function pulse(since: number): number
		if Theme.reducedMotion or since < 0 then
			return 1
		end
		local share = since / Motion.Seconds(LOOK.pulseSeconds)
		return if share < 1 then 1 + LOOK.pulseGrow * (1 - share) else 1
	end

	local function paintTotals(t: number): ()
		local view = live.view
		if view == nil then
			return
		end
		local target = live.target
		local sums = view.totals
		local gains = t >= live.gainsAt
		local cashRoll = windowAt(t, live.walletAt[1], live.walletAt[2])
		local cashFrom = math.max(target.cash - sums.cash, 0)
		totals.wallet.Text = LOOK.cash
			.. Format.Cash(cashFrom + (target.cash - cashFrom) * cashRoll)
		totals.walletGain.Text = if gains then plusText(sums.cash, LOOK.cash) else ""
		if sums.material ~= "" then
			local roll = windowAt(t, live.materialAt[1], live.materialAt[2])
			local from = math.max(target.materials - sums.materials, 0)
			totals.material.Text = Format.Cash(from + (target.materials - from) * roll)
				.. " "
				.. sums.material
			totals.materialGain.Text = if gains then plusText(sums.materials, "") else ""
			for index, log in pileLogs do
				log.Visible = index <= live.landedLogs
			end
		end
		local valorRoll = windowAt(t, live.valorAt[1], live.valorAt[2])
		local valorFrom = math.max(target.valor - sums.valor, 0)
		totals.valor.Text = Format.Cash(valorFrom + (target.valor - valorFrom) * valorRoll)
			.. LOOK.valorWord
		totals.valorGain.Text = if gains then plusText(sums.valor, "") else ""
		coinScale.Scale = pulse(t - live.walletPulse)
		pileScale.Scale = pulse(t - live.pilePulse)
		diamondScale.Scale = if valorRoll > 0 and valorRoll < 1 then pulse(0) else 1
	end

	local function paintSprites(t: number): ()
		for _, sprite in live.sprites do
			if sprite.landed then
				continue
			end
			if t < sprite.launch then
				sprite.gui.Visible = false
				continue
			end
			if t >= sprite.land then
				sprite.landed = true
				sprite.gui.Visible = false
				if sprite.coin then
					live.walletPulse = t
				else
					live.landedLogs = math.max(live.landedLogs, sprite.slot)
					live.pilePulse = t
				end
				continue
			end
			local from = sprite.from or sourcePoint(sprite)
			sprite.from = from
			local to = targetPoint(sprite)
			local u = easeIn(clamp01((t - sprite.launch) / (sprite.land - sprite.launch)))
			local control = (from + to) / 2 + Vector2.new(sprite.sway, -LOOK.arc)
			local a = from:Lerp(control, u)
			local b = control:Lerp(to, u)
			local at = a:Lerp(b, u)
			sprite.gui.Position = UDim2.fromOffset(at.X, at.Y)
			sprite.gui.Visible = true
			if not Theme.reducedMotion then
				local grow = 1 + LOOK.flightGrow * math.sin(math.pi * u)
				if sprite.coin then
					sprite.gui.Size = UDim2.fromOffset(LOOK.coinSize * grow, LOOK.coinSize * grow)
				else
					sprite.gui.Rotation = LOOK.spin * (1 - u) * (if sprite.sway > 0 then 1 else -1)
				end
			end
		end
	end

	-- The rows follow the counting row until the player scrolls them by hand.
	local function follow(t: number, dt: number): ()
		if live.userScrolled or live.drag ~= nil then
			return
		end
		local started = 0
		for index = 1, #live.rows do
			if t >= (live.rowStart[index] or 0) then
				started = index
			end
		end
		local goal = math.min(math.max(started * LOOK.rowPitch - geo.rowsSize.Y, 0), maxScroll())
		if Theme.reducedMotion then
			live.scrollY = goal
		else
			live.scrollY += (goal - live.scrollY) * math.min(dt * LOOK.scrollRate, 1)
		end
		applyScroll()
	end

	local function stopStepper(): ()
		local stepper = live.stepper
		if stepper ~= nil then
			stepper:Disconnect()
			live.stepper = nil
		end
	end

	local function paint(t: number, dt: number): ()
		local grow = if Theme.reducedMotion
			then 1
			else LOOK.popScale + (1 - LOOK.popScale) * ease(
				clamp01(t / math.max(live.open, 1e-3))
			)
		uiScale.Scale = live.scale * grow
		starScale.Scale = if t < live.open then grow else 1
		for index, ui in live.rows do
			paintRow(index, ui, t)
		end
		follow(t, dt)
		paintSprites(t)
		paintTotals(t)
	end

	-- The end state: every row settled (a last row's flash may outlast `done`, so the paint is
	-- at a clock past everything), every icon landed, every count at the server's number.
	local function finish(): ()
		live.clock = live.done
		for _, sprite in live.sprites do
			sprite.landed = true
			sprite.gui.Visible = false
		end
		live.landedLogs = live.logCount
		live.walletPulse = -math.huge
		live.pilePulse = -math.huge
		paint(math.huge, 0)
		stopStepper()
	end

	local function step(dt: number): ()
		live.clock += dt
		paint(live.clock, dt)
		if live.clock >= live.done then
			finish()
		end
	end

	-- When everything happens, in seconds from Show, every duration through Motion.Seconds.
	local function plan(view: View): ()
		local seconds = Motion.Seconds
		local rows = view.lines
		local count = #rows
		live.open = seconds(LOOK.popSeconds)
		local gap = seconds(math.min(LOOK.rowGapSeconds, LOOK.rowsMaxSeconds / math.max(count, 1)))
		live.rowCount = seconds(LOOK.rowCountSeconds)
		table.clear(live.rowStart)
		for index = 1, math.max(count, 1) do
			live.rowStart[index] = live.open + (index - 1) * gap
		end
		local rowsEnd = live.rowStart[math.max(count, 1)] + live.rowCount
		live.gainsAt = rowsEnd
		local flights = rowsEnd + seconds(LOOK.flightPauseSeconds)
		local flight = seconds(LOOK.flightSeconds)
		local spread = seconds(LOOK.flightSpreadSeconds)
		clearSprites()

		-- Icons leave the rows in proportion to what each row paid, top to bottom: the k-th of n
		-- leaves the row where the running total passes (k - 0.5) / n of the whole.
		local function launch(
			coin: boolean,
			wanted: number,
			offset: number
		): (number, number, number)
			local whole = 0
			for _, row in rows do
				whole += if coin then row.cash else row.materials
			end
			if whole <= 0 or wanted <= 0 then
				return flights, flights, 0
			end
			local first, last = math.huge, flights
			for k = 1, wanted do
				local mark = (k - 0.5) / wanted * whole
				local running, source = 0, 1
				for index, row in rows do
					running += if coin then row.cash else row.materials
					if running >= mark then
						source = index
						break
					end
				end
				local leaves = flights
					+ offset
					+ spread * (if wanted > 1 then (k - 1) / (wanted - 1) else 0)
				local gui = if coin
					then newCoin(flyLayer, LOOK.coinSize, 4)
					else newLog(flyLayer, LOOK.logWidth, LOOK.logHeight, 4)
				gui.Visible = false
				table.insert(live.sprites, {
					gui = gui,
					coin = coin,
					row = source,
					slot = k,
					launch = leaves,
					land = leaves + flight,
					sway = LOOK.sway * (if k % 2 == 0 then 1 else -1) * (1 + (k % 3) * 0.5),
					from = nil,
					landed = false,
				})
				first = math.min(first, leaves + flight)
				last = math.max(last, leaves + flight)
			end
			return first, last, wanted
		end

		local low = Theme.lowEndDevice
		-- Each count rolls from its first icon's landing to its last's; with no icon, after the rows.
		local coinFirst, coinLast, coins =
			launch(true, if low then LOOK.coinsLowEnd else LOOK.coins, 0)
		live.walletAt = if coins > 0
			then { coinFirst, coinLast }
			else { flights, flights + seconds(LOOK.valorSeconds) }
		local logs = 0
		if view.totals.material ~= "" and view.totals.materials > 0 then
			logs = math.min(if low then LOOK.logsLowEnd else LOOK.logs, LOOK.logs)
		end
		local logFirst, logLast, made = launch(false, logs, seconds(LOOK.logDelaySeconds))
		live.logCount = made
		live.materialAt = if made > 0
			then { logFirst, logLast }
			else { flights, flights + seconds(LOOK.valorSeconds) }
		local valorStart = flights + spread / 2
		live.valorAt = { valorStart, valorStart + seconds(LOOK.valorSeconds) }
		live.done = math.max(live.walletAt[2], live.materialAt[2], live.valorAt[2], rowsEnd)
		live.landedLogs = 0
		live.walletPulse = -math.huge
		live.pilePulse = -math.huge
		live.clock = 0
	end

	local function buildRows(view: View): ()
		for _, ui in live.rows do
			ui.frame:Destroy()
		end
		table.clear(live.rows)
		local rows = view.lines
		if #rows == 0 then
			rows = {
				{
					kind = "empty",
					label = LOOK.empty,
					cash = 0,
					material = "",
					materials = 0,
					valor = 0,
				},
			}
		end
		for index, row in rows do
			local frame = Create("Frame", {
				Name = "Row" .. index,
				Active = false,
				BackgroundColor3 = LOOK.rowColor,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = z(2),
				Parent = strip,
			}) :: Frame
			round(frame, UDim.new(0, LOOK.rowCorner))
			local label = text(
				"Label",
				frame,
				LOOK.rowText,
				Theme.FONT_BOLD,
				labelColor(row.kind),
				Enum.TextXAlignment.Left
			)
			label.Text = row.label
			label.TextScaled = true
			Create("UITextSizeConstraint", {
				MaxTextSize = LOOK.rowText,
				MinTextSize = LOOK.rowMinText,
				Parent = label,
			})
			local cash = text(
				"Cash",
				frame,
				LOOK.rowText,
				Theme.FONT_BOLD,
				LOOK.cashColor,
				Enum.TextXAlignment.Right
			)
			local material = text(
				"Material",
				frame,
				LOOK.rowText,
				Theme.FONT_BOLD,
				Theme.COLOR_TEXT,
				Enum.TextXAlignment.Right
			)
			local valor = text(
				"Valor",
				frame,
				LOOK.rowText,
				Theme.FONT_BOLD,
				LOOK.valorColor,
				Enum.TextXAlignment.Right
			)
			local logIcon = newLog(frame, LOOK.rowIconSize + 2, LOOK.rowIconSize / 2, 2)
			local diamond = newDiamond(frame, LOOK.rowIconSize * 0.8, 2)
			logIcon.Visible = row.materials > 0
			diamond.Visible = row.valor > 0
			if row.kind == "key" then
				local icon = newKeyIcon(frame, LOOK.keyIconWidth, 2)
				icon.Position = UDim2.new(0, LOOK.rowInset, 0.5, 0)
			end
			table.insert(live.rows, {
				frame = frame,
				label = label,
				cash = cash,
				material = material,
				valor = valor,
				logIcon = logIcon,
				diamond = diamond,
				row = row,
				settled = false,
			})
		end
	end

	local function buildButtons(view: View): ()
		for _, item in live.buttons do
			item:Destroy()
		end
		table.clear(live.buttons)
		for index, spec in view.buttons do
			local accent = spec.accent == true
			local item = Create("TextButton", {
				Name = spec.id,
				LayoutOrder = index,
				BackgroundColor3 = if accent then Theme.COLOR_ACCENT else Theme.COLOR_BG_LIGHT,
				BorderSizePixel = 0,
				Font = Theme.FONT_BOLD,
				TextSize = LOOK.buttonText,
				TextColor3 = if accent then Theme.COLOR_TEXT_DARK else Theme.COLOR_TEXT,
				TextWrapped = true,
				Text = spec.text,
				ZIndex = z(3),
				Parent = totals.buttons,
			}) :: TextButton
			round(item, UDim.new(0, Theme.ROW_CORNER_RADIUS))
			local id = spec.id
			item.Activated:Connect(function()
				deps.onButton(id)
			end)
			table.insert(live.buttons, item)
		end
	end

	local function skip(): ()
		if live.view ~= nil and live.stepper ~= nil then
			finish()
		end
	end

	local function show(view: View): ()
		stopStepper()
		live.view = view
		live.target = {
			cash = view.wallet.cash,
			materials = view.wallet.materials,
			valor = view.wallet.valor,
		}
		live.scrollY = 0
		live.userScrolled = false
		live.drag = nil
		header.kicker.Text = view.kicker
		header.title.Text = view.title
		header.subtitle.Text = view.subtitle or ""
		header.star.Visible = view.star
		totals.note.Text = view.note or ""
		buildRows(view)
		buildButtons(view)
		plan(view)
		relayout()
		paint(0, 0)
		scrim.Visible = true
		live.stepper = RunService.Heartbeat:Connect(step)
	end

	local function hide(): ()
		stopStepper()
		clearSprites()
		live.drag = nil
		scrim.Visible = false
	end

	-- A press on the rows is a drag (scroll) or a tap (skip); the wheel scrolls.
	table.insert(
		connections,
		rowsClip.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				live.drag = {
					input = if kind == Enum.UserInputType.Touch then input else nil,
					startY = input.Position.Y,
					startScroll = live.scrollY,
					moved = 0,
				}
			end
		end)
	)
	table.insert(
		connections,
		rowsClip.InputChanged:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseWheel and scrim.Visible then
				live.userScrolled = true
				live.scrollY -= input.Position.Z * LOOK.wheelStep
				applyScroll()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			local drag = live.drag
			if drag == nil then
				return
			end
			local matches = if drag.input ~= nil
				then input == drag.input
				else input.UserInputType == Enum.UserInputType.MouseMovement
			if not matches then
				return
			end
			local delta = input.Position.Y - drag.startY
			drag.moved = math.max(drag.moved, math.abs(delta))
			if drag.moved > LOOK.tapSlop then
				live.userScrolled = true
				live.scrollY = drag.startScroll - delta / math.max(live.scale, 1e-3)
				applyScroll()
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			local drag = live.drag
			if drag == nil then
				return
			end
			local matches = if drag.input ~= nil
				then input == drag.input
				else input.UserInputType == Enum.UserInputType.MouseButton1
			if not matches then
				return
			end
			live.drag = nil
			if drag.moved <= LOOK.tapSlop then
				skip()
			end
		end)
	)
	table.insert(connections, catcher.Activated:Connect(skip))
	if modal then
		table.insert(connections, (scrim :: TextButton).Activated:Connect(skip))
	end

	local handle: Handle = {
		Show = show,
		SetWallet = function(wallet: Wallet)
			live.target = { cash = wallet.cash, materials = wallet.materials, valor = wallet.valor }
			if live.view ~= nil and scrim.Visible then
				paintTotals(live.clock)
			end
		end,
		SetCountdown = function(line: string?)
			header.countdown.Visible = line ~= nil and line ~= ""
			header.countdown.Text = line or ""
		end,
		Skip = skip,
		Hide = hide,
		IsVisible = function(): boolean
			return scrim.Visible
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			if scale <= 0 then
				return
			end
			live.scale = scale
			live.viewport = viewportSize
			relayout()
			if live.stepper == nil then
				uiScale.Scale = scale
			end
		end,
		Destroy = function()
			hide()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			scrim:Destroy()
		end,
	}
	return handle
end

return RunTally
