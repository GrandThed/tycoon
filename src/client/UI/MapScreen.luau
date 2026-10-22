--!strict
-- The expeditions map and its level card (docs/INTERFACES.md "L1 contracts" -> Client;
-- docs/MISSIONS_DESIGN.md section 4). One screen for every level: a path of nodes, each in its
-- theme's colour, its stars above it and a padlock on it while it is closed; beside it the card
-- of the selected node, with one button per difficulty, the party and Depart.
--
-- Shared by both places: the dungeon place mounts it in L1 and the hub in L4. So it knows
-- nothing about the combat client. It is handed the map's config, is told the state the server
-- computed (which nodes are open, whose stars, who leads) and reports three things back through
-- Deps: a departure, that it opened or closed, and "Return to your city". It never decides
-- whether a level may start: the server answers RequestStartLevel, and Depart only stays quiet
-- where the answer is certain to be no (a closed node, not the leader, a start already asked).
-- What a difficulty asks and pays (`recommendedTier`, `rewardMult`) is read from the level file
-- for display only. It makes no sound call.
--
-- L1 fix round (docs/prompts/l1-fix-round.md, part U, item 4): the server refuses a start for a
-- short while after a party comes back, and a Depart pressed in that while used to do nothing
-- at all. The host now says how long the rest is (Rest); a Depart pressed inside it is HELD,
-- reads "Departing...", and is sent when the rest ends. Picking another level or difficulty,
-- or closing the map, takes the held Depart back: nothing starts that was not confirmed as
-- it stands.
--
-- Laid out for a landscape phone first (checked at 640x360 and 667x375 with top insets of 36
-- and 58, and at 1280x720 and 1920x1080): the map on the left, the card on the right, both in
-- one frame under one UIScale. Every node, difficulty button, Depart, Return and the close
-- button is at least 48 design px, which is 44 physical px at Theme.MIN_SCALE. Portrait is not
-- laid out (carried from P5).
--
-- L2 Wave 1 (docs/prompts/l2-w1-contract.md, L2-15): the card's secrets row. A MapNodeState may
-- carry `secrets` (the receiver's own finds, by level): one icon per secret, filled with a
-- check when found and an outline with "?" when not, and under each the key it needs ("2×
-- JUMP", "FIRE", "ICE": Theme.MAP_SECRET_KEY_WORDS). It shows with the open node's rows, when
-- the node has any. 30 design px tall: the open card still fits 667 x 375 (see Theme).
--
-- A node stands where the config puts it (x and y are 0..1 of the map), and then the nodes are
-- SPREAD: a phone's map is small against a 48 px tap target, and positions that read well on a
-- monitor put one node on another there. Each node is a footprint (its ring, its stars above,
-- its name below); wherever two footprints overlap, or one covers the close button, they are
-- pushed apart along the shorter way, a bonus node giving way to a level node. On a monitor
-- nothing overlaps and nothing moves. The path is laid after the spread. The map carries no
-- title of its own: on a phone that corner is a node's.
--
-- The host binds the keys (arrows, Enter) and calls Step and Confirm; `deps.keyHint` is the
-- line that names them, shown at the foot of the card when the host passes one.
--
-- L3 Wave 1 (docs/prompts/l3-w1-contract.md, L3-15, L3-16): tiers belong to each weapon on one
-- ladder of 20, and the Armory shows them as "T3", so a difficulty's recommended tier reads the
-- same way here (Hard's "T3" read "tier 4+" on the old slot ladder). Hard's x2.5 is data: the
-- rewards line already reads it from the level file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Format = require(sharedFolder:WaitForChild("Format"))

local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))
local Motion = require(script.Parent:WaitForChild("Motion"))

export type Deps = {
	onDepart: (levelId: string, difficulty: string) -> (),
	onOpenChanged: (open: boolean) -> (),
	-- "Return to your city"; nil = no button.
	onReturn: (() -> ())?,
	-- The line naming the keys the host bound to Step and Confirm; nil = no line.
	keyHint: string?,
}

export type MapScreenHandle = {
	SetState: (state: Types.MapState) -> (),
	SetParty: (party: { Types.PartyMember }, localUserId: number, leaderUserId: number) -> (),
	-- Selects a node, and a difficulty of it when one is named and the node offers it.
	Select: (nodeId: string, difficulty: string?) -> (),
	-- dx: the node before (-1) or after (+1) in config order. dy: an easier (-1) or a harder
	-- (+1) difficulty of the selected node. Both stop at the ends.
	Step: (dx: number, dy: number) -> (),
	-- Depart, when it is allowed (an open node, the leader, not busy).
	Confirm: () -> (),
	Open: () -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	-- Busy = Depart stays quiet: a start was asked and not yet answered. Confirm sets it; the
	-- host clears it.
	SetBusy: (busy: boolean) -> (),
	-- The party has only just come back and no start is taken for `seconds`: a Depart pressed
	-- before they are over is held and sent when they are (0 = no rest).
	Rest: (seconds: number) -> (),
	-- scale = the HUD's UI scale; viewportSize = the parent ScreenGui's size in px.
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

-- One difficulty a level offers, as the card shows it.
type Difficulty = { id: string, name: string, tier: number, rewardMult: number }

-- One secret on the card (MapSecretState), as checked off the network.
type SecretMark = { id: string, name: string, needs: string, found: boolean }

type SecretCell = { frame: Frame, icon: Frame, glyph: TextLabel, stroke: UIStroke, key: TextLabel }

type NodeView = {
	node: Types.MapNode,
	size: number,
	color: Color3,
	holder: Frame,
	button: TextButton,
	ring: Frame,
	fill: Frame,
	label: TextLabel,
	lock: Frame,
	pop: UIScale,
	stars: { TextLabel },
	difficulties: { Difficulty },
	state: Types.MapNodeState?,
	secrets: { SecretMark },
	centre: Vector2,
}

type DifficultyButton = {
	button: TextButton,
	stroke: UIStroke,
	name: TextLabel,
	tier: TextLabel,
	mult: TextLabel,
}

-- A node's footprint while the map is laid out, in design px: its centre, half its width, and
-- how far it reaches above (its stars) and below (its name). `fixed` = the close button, which
-- never moves.
type Footprint = {
	x: number,
	y: number,
	half: number,
	up: number,
	down: number,
	fixed: boolean,
	yields: boolean,
}

type CardView = {
	frame: Frame,
	chip: TextLabel,
	stars: { TextLabel },
	name: TextLabel,
	reason: TextLabel,
	difficultyRow: Frame,
	difficulties: { DifficultyButton },
	rewardsRow: Frame,
	rewards: TextLabel,
	partyRow: Frame,
	partyCaption: TextLabel,
	party: TextLabel,
	secretsRow: Frame,
	secretsList: Frame,
	secretCells: { SecretCell },
	depart: TextButton,
	back: TextButton?,
}

local STAR = "★"
local CLOSE_GLYPH = "X"
local LEADER_MARK = "★ "
local BONUS_KIND = "bonus"
local DEPART_TEXT = "Depart"
-- Depart was pressed and stands: held until the rest is over, or sent and not yet answered.
local DEPARTING_TEXT = "Departing..."
local RETURN_TEXT = "Return to your city"
local NO_LEADER_TEXT = "the leader"
-- L3-15: a recommended tier on the weapons' one ladder, as the Armory names a tier.
local TIER_PREFIX = "T"
-- A locked node says why (MapNodeState.reason; `needs` is a node's name or a number of stars).
local REASON_NOT_BUILT = "notBuilt"
local REASON_NEEDS_NODE = "needsNode"
local REASON_NEEDS_STARS = "needsStars"
local SECRET_FOUND_GLYPH = "✓"
local SECRET_UNFOUND_GLYPH = "?"
-- Design px of overlap the spread takes for none.
local SPREAD_EPSILON = 0.25

local MapScreen = {}

-- Pushes two overlapping footprints apart along the shorter way. A fixed one never moves, one
-- that yields (a bonus node) moves alone against one that does not, and two equals share it.
-- Returns true when it moved anything.
local function separate(a: Footprint, b: Footprint, gap: number): boolean
	local overlapX = a.half + b.half + gap - math.abs(b.x - a.x)
	local overlapY = math.min(a.y + a.down, b.y + b.down) - math.max(a.y - a.up, b.y - b.up) + gap
	-- Under a hair of overlap is none: the passes close a chain of pushes geometrically, and
	-- chasing the last hundredth of a pixel would use them all.
	if overlapX <= SPREAD_EPSILON or overlapY <= SPREAD_EPSILON then
		return false
	end
	local shareA, shareB = 0.5, 0.5
	if a.fixed or (b.yields and not a.yields and not b.fixed) then
		shareA, shareB = 0, 1
	elseif b.fixed or (a.yields and not b.yields) then
		shareA, shareB = 1, 0
	end
	if overlapX <= overlapY then
		local way = if b.x >= a.x then 1 else -1
		a.x -= way * overlapX * shareA
		b.x += way * overlapX * shareB
	else
		-- Centres are not what decides up from down here: the stars reach less than the name.
		local way = if b.y - b.up + b.y + b.down >= a.y - a.up + a.y + a.down then 1 else -1
		a.y -= way * overlapY * shareA
		b.y += way * overlapY * shareB
	end
	return true
end

-- The spread (see the header): passes over every pair until nothing overlaps or the passes run
-- out, each footprint kept inside the map after every pass. `prints` holds the nodes first, in
-- order, then the fixed ones.
local function spread(prints: { Footprint }, width: number, height: number): ()
	local edge = Theme.MAP_NODE_PAD_EDGE
	for _ = 1, Theme.MAP_SPREAD_PASSES do
		local moved = false
		for first = 1, #prints do
			for second = first + 1, #prints do
				local a, b = prints[first], prints[second]
				if not (a.fixed and b.fixed) and separate(a, b, Theme.MAP_SPREAD_GAP) then
					moved = true
				end
			end
		end
		for _, item in prints do
			if not item.fixed then
				-- Not math.clamp: on a map too small for a node the bounds cross, and
				-- math.clamp throws. This cannot (crossed, the upper bound is the answer).
				item.x = math.min(math.max(item.x, edge + item.half), width - edge - item.half)
				item.y = math.min(math.max(item.y, edge + item.up), height - edge - item.down)
			end
		end
		if not moved then
			break
		end
	end
end

local function colorOf(rgb: { number }?, fallback: Color3): Color3
	if rgb == nil then
		return fallback
	end
	local r, g, b = rgb[1], rgb[2], rgb[3]
	if typeof(r) ~= "number" or typeof(g) ~= "number" or typeof(b) ~= "number" then
		return fallback
	end
	return Color3.fromRGB(r, g, b)
end

local function rounded(instance: Instance, radius: UDim): ()
	Create("UICorner", { CornerRadius = radius, Parent = instance })
end

local function label(name: string, size: number, color: Color3, parent: Instance): TextLabel
	return Create("TextLabel", {
		Name = name,
		Active = false,
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = size,
		TextColor3 = color,
		Text = "",
		Parent = parent,
	}) :: TextLabel
end

-- A star is the glyph, outlined in the map's ink so it reads on every theme's colour.
local function star(parent: Instance, order: number): TextLabel
	local item = label("Star" .. tostring(order), Theme.MAP_STAR_TEXT, Theme.MAP_COLOR_OFF, parent)
	item.LayoutOrder = order
	item.Size = UDim2.fromOffset(Theme.MAP_STAR_SIZE, Theme.MAP_STAR_SIZE)
	item.Text = STAR
	Create("UIStroke", {
		Color = Theme.MAP_COLOR_INK,
		Thickness = Theme.STROKE_THICKNESS / 2,
		Parent = item,
	})
	return item
end

local function starRow(
	parent: Instance,
	count: number,
	alignment: Enum.HorizontalAlignment
): (Frame, { TextLabel })
	local row = Create("Frame", {
		Name = "Stars",
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(count * Theme.MAP_STAR_SIZE, Theme.MAP_STAR_SIZE),
		Parent = parent,
	}) :: Frame
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = alignment,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local items: { TextLabel } = {}
	for index = 1, count do
		table.insert(items, star(row, index))
	end
	return row, items
end

-- What a level offers, in the map's difficulty order. No file (a node not built yet), or a file
-- with no difficulty table, offers nothing.
local function difficultiesOf(map: Types.ExpeditionsConfig, node: Types.MapNode): { Difficulty }
	local out: { Difficulty } = {}
	local levelId = node.level
	local file = if levelId ~= nil then Catalog.GetLevelFile(levelId) else nil
	local defs = if file ~= nil then file.difficulties else nil
	if defs == nil then
		return out
	end
	for _, id in map.difficulties do
		local def = defs[id]
		if def ~= nil then
			table.insert(out, {
				id = id,
				name = map.difficultyNames[id] or id,
				tier = def.recommendedTier,
				rewardMult = def.rewardMult,
			})
		end
	end
	return out
end

local function hasStar(state: Types.MapNodeState?, difficulty: string): boolean
	return state ~= nil and table.find(state.stars, difficulty) ~= nil
end

local function reasonText(state: Types.MapNodeState?): string
	if state == nil then
		return "Waiting for the map"
	end
	local needs = state.needs
	if state.reason == REASON_NOT_BUILT then
		return "Not built yet"
	elseif state.reason == REASON_NEEDS_NODE and needs ~= nil then
		return "Clear " .. needs .. " first"
	elseif state.reason == REASON_NEEDS_STARS and needs ~= nil then
		return needs .. " stars needed"
	end
	return "Locked"
end

-- A padlock from two frames (the project owns no image asset): a body, and a ring behind it
-- whose lower half the body hides.
local function padlock(parent: Instance, size: number): Frame
	local lock = Create("Frame", {
		Name = "Lock",
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 2,
		Parent = parent,
	}) :: Frame
	local shackle = Create("Frame", {
		Name = "Shackle",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(size * 0.3, size * 0.3),
		BackgroundTransparency = 1,
		Parent = lock,
	}) :: Frame
	rounded(shackle, UDim.new(0.5, 0))
	Create("UIStroke", {
		Color = Theme.MAP_LOCK_COLOR,
		Thickness = math.max(size * 0.06, Theme.STROKE_THICKNESS),
		Parent = shackle,
	})
	local body = Create("Frame", {
		Name = "Body",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(size * 0.46, size * 0.34),
		BackgroundColor3 = Theme.MAP_LOCK_COLOR,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = lock,
	}) :: Frame
	rounded(body, UDim.new(0, Theme.ROW_CORNER_RADIUS / 2))
	return lock
end

-- One node: a holder at the node's centre (placed by the layout), with the button on it, the
-- stars above and the name below. `mark` is what an open node shows on itself.
local function buildNode(
	parent: Instance,
	node: Types.MapNode,
	mark: string,
	color: Color3,
	starCount: number
): NodeView
	local size = if node.kind == BONUS_KIND then Theme.MAP_BONUS_NODE_SIZE else Theme.MAP_NODE_SIZE
	local reach = size / 2 + Theme.MAP_NODE_RING + Theme.MAP_NODE_GAP
	local holder = Create("Frame", {
		Name = "Node_" .. node.id,
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 3,
		Parent = parent,
	}) :: Frame
	local button = Create("TextButton", {
		Name = "Button",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Parent = holder,
	}) :: TextButton
	local pop = Create("UIScale", { Parent = button }) :: UIScale
	local ring = Create("Frame", {
		Name = "Ring",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size + Theme.MAP_NODE_RING * 2, size + Theme.MAP_NODE_RING * 2),
		BackgroundColor3 = Theme.MAP_COLOR_INK,
		BorderSizePixel = 0,
		Parent = button,
	}) :: Frame
	rounded(ring, UDim.new(0.5, 0))
	local fill = Create("Frame", {
		Name = "Fill",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.MAP_COLOR_LOCKED,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = button,
	}) :: Frame
	rounded(fill, UDim.new(0.5, 0))
	Create("UIStroke", {
		Color = Theme.MAP_COLOR_INK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = fill,
	})
	local markLabel = label("Mark", math.floor(size * 0.45), Theme.MAP_COLOR_INK, fill)
	markLabel.Size = UDim2.fromScale(1, 1)
	markLabel.Text = mark
	markLabel.ZIndex = 2
	local lock = padlock(fill, size)

	local row, stars = starRow(holder, starCount, Enum.HorizontalAlignment.Center)
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.fromOffset(0, -reach)

	local name = label("Name", Theme.MAP_NODE_NAME_TEXT, Theme.MAP_COLOR_TEXT, holder)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromOffset(0, reach)
	name.Size = UDim2.fromOffset(Theme.MAP_NODE_NAME_WIDTH, Theme.MAP_NODE_NAME_HEIGHT)
	name.TextWrapped = true
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.Text = node.name
	Create("UIStroke", {
		Color = Theme.MAP_COLOR_INK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = name,
	})

	return {
		node = node,
		size = size,
		color = color,
		holder = holder,
		button = button,
		ring = ring,
		fill = fill,
		label = markLabel,
		lock = lock,
		pop = pop,
		stars = stars,
		difficulties = {},
		state = nil,
		secrets = {},
		centre = Vector2.zero,
	}
end

-- A MapNodeState's `secrets`, kept only where every field the card reads is there.
local function readSecrets(list: any): { SecretMark }
	local marks: { SecretMark } = {}
	if typeof(list) ~= "table" then
		return marks
	end
	for _, entry in list do
		if
			typeof(entry) == "table"
			and typeof(entry.id) == "string"
			and typeof(entry.name) == "string"
			and typeof(entry.needs) == "string"
			and typeof(entry.found) == "boolean"
		then
			table.insert(
				marks,
				{ id = entry.id, name = entry.name, needs = entry.needs, found = entry.found }
			)
		end
	end
	return marks
end

-- One secret's cell on the card: a round icon, its key under it.
local function secretCell(parent: Instance, order: number): SecretCell
	local size = Theme.MAP_SECRET_ICON_SIZE
	local frame = Create("Frame", {
		Name = "Secret" .. tostring(order),
		Active = false,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, Theme.MAP_SECRET_CELL_WIDTH, 1, 0),
		Visible = false,
		Parent = parent,
	}) :: Frame
	local icon = Create("Frame", {
		Name = "Icon",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Theme.MAP_COLOR_GOLD,
		BorderSizePixel = 0,
		Parent = frame,
	}) :: Frame
	rounded(icon, UDim.new(0.5, 0))
	local stroke = Create("UIStroke", {
		Color = Theme.MAP_COLOR_GOLD,
		Thickness = Theme.STROKE_THICKNESS / 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = icon,
	}) :: UIStroke
	local glyph = label("Glyph", Theme.MAP_SECRET_ICON_TEXT, Theme.MAP_COLOR_INK, icon)
	glyph.Size = UDim2.fromScale(1, 1)
	local key = label("Key", Theme.MAP_SECRET_KEY_TEXT, Theme.MAP_COLOR_DIM, frame)
	key.AnchorPoint = Vector2.new(0.5, 1)
	key.Position = UDim2.fromScale(0.5, 1)
	key.Size = UDim2.new(1, 0, 0, Theme.MAP_SECRET_ROW_HEIGHT - size)
	key.TextTruncate = Enum.TextTruncate.AtEnd
	return { frame = frame, icon = icon, glyph = glyph, stroke = stroke, key = key }
end

-- One line of the card: a dim caption and its value.
local function infoRow(parent: Instance, name: string, order: number): (Frame, TextLabel, TextLabel)
	local row = Create("Frame", {
		Name = name,
		Active = false,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.MAP_CARD_ROW_HEIGHT),
		Parent = parent,
	}) :: Frame
	local caption = label("Caption", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, row)
	caption.Font = Theme.FONT
	caption.Size = UDim2.new(0, Theme.MAP_CARD_LABEL_WIDTH, 1, 0)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	local value = label("Value", Theme.TEXT_SMALL, Theme.MAP_COLOR_TEXT, row)
	value.Position = UDim2.fromOffset(Theme.MAP_CARD_LABEL_WIDTH, 0)
	value.Size = UDim2.new(1, -Theme.MAP_CARD_LABEL_WIDTH, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextTruncate = Enum.TextTruncate.AtEnd
	return row, caption, value
end

local function difficultyButton(parent: Instance, order: number, count: number): DifficultyButton
	local gap = Theme.MAP_CARD_LINE_GAP
	local button = Create("TextButton", {
		Name = "Difficulty" .. tostring(order),
		LayoutOrder = order,
		-- `count` buttons share the row with a gap between neighbours.
		Size = UDim2.new(1 / count, -gap * (count - 1) / count, 1, 0),
		BackgroundColor3 = Theme.MAP_COLOR_PANEL_LIGHT,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		Parent = parent,
	}) :: TextButton
	rounded(button, UDim.new(0, Theme.ROW_CORNER_RADIUS))
	local stroke = Create("UIStroke", {
		Color = Theme.MAP_COLOR_GOLD,
		Thickness = Theme.STROKE_THICKNESS,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Transparency = 1,
		Parent = button,
	}) :: UIStroke
	Create("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = button,
	})
	local name = label("Name", Theme.MAP_DIFFICULTY_NAME_TEXT, Theme.MAP_COLOR_TEXT, button)
	name.LayoutOrder = 1
	name.Size = UDim2.new(1, 0, 0, Theme.MAP_DIFFICULTY_NAME_TEXT + 3)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local tier = label("Tier", Theme.MAP_DIFFICULTY_SUB_TEXT, Theme.MAP_COLOR_DIM, button)
	tier.Font = Theme.FONT
	tier.LayoutOrder = 2
	tier.Size = UDim2.new(1, 0, 0, Theme.MAP_DIFFICULTY_SUB_TEXT + 2)
	local mult = label("Rewards", Theme.MAP_DIFFICULTY_SUB_TEXT, Theme.MAP_COLOR_GOLD, button)
	mult.LayoutOrder = 3
	mult.Size = UDim2.new(1, 0, 0, Theme.MAP_DIFFICULTY_SUB_TEXT + 2)
	return { button = button, stroke = stroke, name = name, tier = tier, mult = mult }
end

local function cardButton(parent: Instance, name: string, order: number, height: number): TextButton
	local button = Create("TextButton", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.MAP_COLOR_PANEL_LIGHT,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_SMALL,
		TextColor3 = Theme.MAP_COLOR_TEXT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		Parent = parent,
	}) :: TextButton
	rounded(button, UDim.new(0, Theme.ROW_CORNER_RADIUS))
	return button
end

-- The card, top to bottom: theme chip and stars, the name, then either the reason a node is
-- closed, or the difficulties, what they pay, the party and Depart. Return and the key line
-- close it. A list layout stacks them, so a hidden row leaves no hole.
local function buildCard(parent: Instance, difficultyCount: number, deps: Deps): CardView
	local frame = Create("Frame", {
		Name = "Card",
		Active = true,
		BackgroundColor3 = Theme.MAP_COLOR_PANEL,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	rounded(frame, UDim.new(0, Theme.CORNER_RADIUS))
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.MAP_CARD_PADDING),
		PaddingBottom = UDim.new(0, Theme.MAP_CARD_PADDING),
		PaddingLeft = UDim.new(0, Theme.MAP_CARD_PADDING),
		PaddingRight = UDim.new(0, Theme.MAP_CARD_PADDING),
		Parent = frame,
	})
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.MAP_CARD_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})

	local header = Create("Frame", {
		Name = "Header",
		Active = false,
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.MAP_CARD_CHIP_HEIGHT),
		Parent = frame,
	}) :: Frame
	local chip = label("Theme", Theme.TEXT_SMALL, Theme.MAP_COLOR_INK, header)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromScale(0, 1)
	chip.BackgroundTransparency = 0
	chip.BackgroundColor3 = Theme.MAP_COLOR_OFF
	rounded(chip, UDim.new(0.5, 0))
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, Theme.MAP_CARD_PADDING),
		PaddingRight = UDim.new(0, Theme.MAP_CARD_PADDING),
		Parent = chip,
	})
	local row, stars = starRow(header, difficultyCount, Enum.HorizontalAlignment.Right)
	row.AnchorPoint = Vector2.new(1, 0.5)
	row.Position = UDim2.fromScale(1, 0.5)

	local name = label("Name", Theme.TEXT_HEADER, Theme.MAP_COLOR_TEXT, frame)
	name.LayoutOrder = 2
	name.Size = UDim2.new(1, 0, 0, Theme.MAP_CARD_NAME_HEIGHT)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local reason = label("Reason", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, frame)
	reason.Font = Theme.FONT
	reason.LayoutOrder = 3
	reason.Size = UDim2.new(1, 0, 0, Theme.MAP_CARD_REASON_HEIGHT)
	reason.TextWrapped = true
	reason.TextXAlignment = Enum.TextXAlignment.Left
	reason.TextYAlignment = Enum.TextYAlignment.Top

	local difficultyRow = Create("Frame", {
		Name = "Difficulties",
		Active = false,
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.MAP_DIFFICULTY_HEIGHT),
		Parent = frame,
	}) :: Frame
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, Theme.MAP_CARD_LINE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = difficultyRow,
	})
	local difficulties: { DifficultyButton } = {}
	for index = 1, difficultyCount do
		table.insert(difficulties, difficultyButton(difficultyRow, index, difficultyCount))
	end

	local rewardsRow, rewardsCaption, rewards = infoRow(frame, "Rewards", 5)
	rewardsCaption.Text = "Rewards"
	local partyRow, partyCaption, party = infoRow(frame, "Party", 6)

	-- L2: the secrets row, the caption column like an info row and the icons beside it.
	local secretsRow = Create("Frame", {
		Name = "Secrets",
		Active = false,
		LayoutOrder = 7,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.MAP_SECRET_ROW_HEIGHT),
		Visible = false,
		Parent = frame,
	}) :: Frame
	local secretsCaption = label("Caption", Theme.TEXT_SMALL, Theme.MAP_COLOR_DIM, secretsRow)
	secretsCaption.Font = Theme.FONT
	secretsCaption.Size = UDim2.fromOffset(Theme.MAP_CARD_LABEL_WIDTH, Theme.MAP_SECRET_ICON_SIZE)
	secretsCaption.TextXAlignment = Enum.TextXAlignment.Left
	secretsCaption.Text = "Secrets"
	local secretsList = Create("Frame", {
		Name = "Icons",
		Active = false,
		Position = UDim2.fromOffset(Theme.MAP_CARD_LABEL_WIDTH, 0),
		Size = UDim2.new(1, -Theme.MAP_CARD_LABEL_WIDTH, 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = secretsRow,
	}) :: Frame
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = secretsList,
	})

	local depart = cardButton(frame, "Depart", 8, Theme.MAP_DEPART_HEIGHT)
	depart.TextSize = Theme.TEXT_HEADER

	local back: TextButton? = nil
	if deps.onReturn ~= nil then
		local button = cardButton(frame, "Return", 9, Theme.MAP_RETURN_HEIGHT)
		button.Text = RETURN_TEXT
		button.AutoButtonColor = true
		back = button
	end
	local keyHint = deps.keyHint
	if keyHint ~= nil then
		local hint = label("Keys", Theme.MAP_CARD_HINT_TEXT, Theme.MAP_COLOR_DIM, frame)
		hint.Font = Theme.FONT
		hint.LayoutOrder = 10
		hint.Size = UDim2.new(1, 0, 0, Theme.MAP_CARD_HINT_HEIGHT)
		hint.TextTruncate = Enum.TextTruncate.AtEnd
		hint.Text = keyHint
	end

	return {
		frame = frame,
		chip = chip,
		stars = stars,
		name = name,
		reason = reason,
		difficultyRow = difficultyRow,
		difficulties = difficulties,
		rewardsRow = rewardsRow,
		rewards = rewards,
		partyRow = partyRow,
		partyCaption = partyCaption,
		party = party,
		secretsRow = secretsRow,
		secretsList = secretsList,
		secretCells = {},
		depart = depart,
		back = back,
	}
end

function MapScreen.new(parent: Instance, map: Types.ExpeditionsConfig, deps: Deps): MapScreenHandle
	local connections: { RBXScriptConnection } = {}
	local views: { NodeView } = {}
	local byId: { [string]: NodeView } = {}
	local dots: { Frame } = {}
	-- What is shown. `wanted` is the difficulty the player last picked; `difficulty` is the one
	-- in force, which is `wanted` where the selected node offers it and its first otherwise, so
	-- stepping across a closed node does not forget the pick. `restUntil` is the os.clock stamp
	-- before which a Depart is held instead of sent, `held` that one is, and `heldToken` names
	-- the hold, so a timer left over from a hold that was taken back sends nothing.
	local view = {
		open = false,
		busy = false,
		restUntil = 0,
		held = false,
		heldToken = 0,
		selected = 1,
		wanted = "",
		difficulty = "",
		localUserId = 0,
		leaderUserId = 0,
		leaderName = "",
		partyText = "",
		partySize = 0,
		partyKey = "",
	}

	-- The scrim takes every tap that misses the screen: the world and the HUD under an open
	-- map are not played through it.
	local root = Create("Frame", {
		Name = "MapScreen",
		Active = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_SCRIM,
		BackgroundTransparency = Theme.MAP_SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	local panel = Create("Frame", {
		Name = "Panel",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = root,
	}) :: Frame
	local uiScale = Create("UIScale", { Parent = panel }) :: UIScale

	local mapArea = Create("Frame", {
		Name = "Map",
		Active = true,
		BackgroundColor3 = Theme.MAP_COLOR_INK,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = panel,
	}) :: Frame
	rounded(mapArea, UDim.new(0, Theme.CORNER_RADIUS))

	-- One band per theme, in the order the level nodes first name them, behind the path.
	local themes: { string } = {}
	for _, node in map.nodes do
		if node.kind ~= BONUS_KIND and table.find(themes, node.theme) == nil then
			table.insert(themes, node.theme)
		end
	end
	for index, theme in themes do
		local def = map.themes[theme]
		Create("Frame", {
			Name = "Band_" .. theme,
			Active = false,
			Position = UDim2.fromScale((index - 1) / #themes, 0),
			Size = UDim2.fromScale(1 / #themes, 1),
			BackgroundColor3 = colorOf(if def ~= nil then def.color else nil, Theme.MAP_COLOR_OFF),
			BackgroundTransparency = Theme.MAP_BAND_TRANSPARENCY,
			BorderSizePixel = 0,
			Parent = mapArea,
		})
	end

	local close = Create("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.MAP_NODE_PAD_EDGE, 0, Theme.MAP_NODE_PAD_EDGE),
		Size = UDim2.fromOffset(Theme.MAP_CLOSE_SIZE, Theme.MAP_CLOSE_SIZE),
		BackgroundColor3 = Theme.MAP_COLOR_PANEL,
		BorderSizePixel = 0,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.TEXT_HEADER,
		TextColor3 = Theme.MAP_COLOR_TEXT,
		Text = CLOSE_GLYPH,
		ZIndex = 4,
		Parent = mapArea,
	}) :: TextButton
	rounded(close, UDim.new(0.5, 0))

	-- Level nodes are numbered along the path; a bonus node shows its initial.
	local levelNumber = 0
	for _, node in map.nodes do
		local mark: string
		if node.kind == BONUS_KIND then
			mark = string.upper(string.sub(node.name, 1, 1))
		else
			levelNumber += 1
			mark = tostring(levelNumber)
		end
		local def = map.themes[node.theme]
		local nodeView = buildNode(
			mapArea,
			node,
			mark,
			colorOf(if def ~= nil then def.color else nil, Theme.MAP_COLOR_OFF),
			#map.difficulties
		)
		table.insert(views, nodeView)
		byId[node.id] = nodeView
	end

	local card = buildCard(panel, math.max(#map.difficulties, 1), deps)

	-- A level file may still be replicating when the screen is built, so what a node offers
	-- is asked again until there is an answer.
	local function offered(nodeView: NodeView): { Difficulty }
		if #nodeView.difficulties == 0 then
			nodeView.difficulties = difficultiesOf(map, nodeView.node)
		end
		return nodeView.difficulties
	end

	local function selectedView(): NodeView?
		return views[view.selected]
	end

	local function fitDifficulty(): ()
		local current = selectedView()
		local list: { Difficulty } = if current ~= nil then offered(current) else {}
		view.difficulty = if list[1] ~= nil then list[1].id else ""
		for _, entry in list do
			if entry.id == view.wanted then
				view.difficulty = entry.id
				break
			end
		end
	end

	local function isOpen(nodeView: NodeView?): boolean
		local state = if nodeView ~= nil then nodeView.state else nil
		return state ~= nil and state.open
	end

	local function isLeader(): boolean
		return view.leaderUserId ~= 0 and view.localUserId == view.leaderUserId
	end

	local function canDepart(): boolean
		local current = selectedView()
		return current ~= nil
			and isOpen(current)
			and current.node.level ~= nil
			and view.difficulty ~= ""
			and isLeader()
			and not view.busy
	end

	local function paintNode(nodeView: NodeView): ()
		local open = isOpen(nodeView)
		nodeView.fill.BackgroundColor3 = if open then nodeView.color else Theme.MAP_COLOR_LOCKED
		nodeView.label.Visible = open
		nodeView.lock.Visible = not open
		nodeView.ring.BackgroundColor3 = if nodeView == selectedView()
			then Theme.MAP_COLOR_GOLD
			else Theme.MAP_COLOR_INK
		local list = offered(nodeView)
		for index, item in nodeView.stars do
			local entry = list[index]
			item.Visible = entry ~= nil
			if entry ~= nil then
				item.TextColor3 = if hasStar(nodeView.state, entry.id)
					then Theme.MAP_COLOR_GOLD
					else Theme.MAP_COLOR_OFF
			end
		end
	end

	-- L2: the selected node's secrets (none = no row). Cells are made as a level first needs
	-- them and shared by every node; they split the row's width when there are more than fit.
	local function paintSecrets(marks: { SecretMark }): ()
		card.secretsRow.Visible = #marks > 0
		local cells = card.secretCells
		while #cells < #marks do
			table.insert(cells, secretCell(card.secretsList, #cells + 1))
		end
		local room = Theme.MAP_CARD_WIDTH - Theme.MAP_CARD_PADDING * 2 - Theme.MAP_CARD_LABEL_WIDTH
		local width = math.min(Theme.MAP_SECRET_CELL_WIDTH, room / math.max(#marks, 1))
		for index, cell in cells do
			local mark = marks[index]
			cell.frame.Visible = mark ~= nil
			if mark ~= nil then
				cell.frame.Size = UDim2.new(0, width, 1, 0)
				cell.icon.BackgroundTransparency = if mark.found then 0 else 1
				cell.glyph.Text = if mark.found then SECRET_FOUND_GLYPH else SECRET_UNFOUND_GLYPH
				cell.glyph.TextColor3 = if mark.found
					then Theme.MAP_COLOR_INK
					else Theme.MAP_COLOR_GOLD
				cell.key.Text = Theme.MAP_SECRET_KEY_WORDS[mark.needs] or string.upper(mark.needs)
				cell.key.TextColor3 = if mark.found
					then Theme.MAP_COLOR_GOLD
					else Theme.MAP_COLOR_DIM
			end
		end
	end

	local function paintCard(): ()
		local current = selectedView()
		if current == nil then
			return
		end
		local node = current.node
		local open = isOpen(current)
		local list = offered(current)
		card.chip.Text = string.upper(if node.kind == BONUS_KIND then BONUS_KIND else node.theme)
		card.chip.BackgroundColor3 = current.color
		card.name.Text = node.name
		for index, item in card.stars do
			local entry = list[index]
			item.Visible = entry ~= nil
			if entry ~= nil then
				item.TextColor3 = if hasStar(current.state, entry.id)
					then Theme.MAP_COLOR_GOLD
					else Theme.MAP_COLOR_OFF
			end
		end
		card.reason.Visible = not open
		card.reason.Text = reasonText(current.state)
		card.difficultyRow.Visible = open
		card.rewardsRow.Visible = open
		card.partyRow.Visible = open
		card.depart.Visible = open
		paintSecrets(if open then current.secrets else {})
		if not open then
			return
		end
		local picked: Difficulty? = nil
		for index, item in card.difficulties do
			local entry = list[index]
			item.button.Visible = entry ~= nil
			if entry ~= nil then
				local chosen = entry.id == view.difficulty
				if chosen then
					picked = entry
				end
				item.name.Text = entry.name
				item.tier.Text = TIER_PREFIX .. Format.Cash(entry.tier)
				item.mult.Text = "×" .. Format.Rate(entry.rewardMult)
				item.stroke.Transparency = if chosen then 0 else 1
				item.button.BackgroundColor3 = if chosen
					then Theme.MAP_COLOR_PANEL_SELECTED
					else Theme.MAP_COLOR_PANEL_LIGHT
			end
		end
		card.rewards.Text = if picked ~= nil
			then "×" .. Format.Rate(picked.rewardMult) .. " cash and drops"
			else ""
		-- Solo, the rule that matters is the one that ends the run (ruling 5 of Ben's).
		local solo = view.partySize <= 1
		card.partyCaption.Text = if solo then "Solo" else "Party"
		card.party.Text = if solo then "A down ends the run" else view.partyText
		-- A Depart that was pressed and stands (held for the rest, or sent and unanswered) says
		-- so: the press must never look as if it did nothing.
		local pressed = view.held or view.busy
		local live = canDepart() and not view.held
		card.depart.Text = if not isLeader()
			then "Waiting for " .. (if view.leaderName ~= ""
				then view.leaderName
				else NO_LEADER_TEXT)
			elseif pressed then DEPARTING_TEXT
			else DEPART_TEXT
		card.depart.Active = live
		card.depart.BackgroundColor3 = if live
			then Theme.MAP_COLOR_GOLD
			elseif pressed then Theme.MAP_COLOR_PANEL_SELECTED
			else Theme.MAP_COLOR_PANEL_LIGHT
		card.depart.TextColor3 = if live
			then Theme.MAP_COLOR_INK
			elseif pressed then Theme.MAP_COLOR_GOLD
			else Theme.MAP_COLOR_DIM
	end

	local function paint(): ()
		for _, nodeView in views do
			paintNode(nodeView)
		end
		paintCard()
	end

	-- Takes a held Depart back (the caller repaints).
	local function dropHeld(): ()
		if view.held then
			view.held = false
			view.heldToken += 1
		end
	end

	local function choose(index: number, difficulty: string?): ()
		local target = views[index]
		if target == nil then
			return
		end
		local changed = index ~= view.selected
		local before = view.difficulty
		view.selected = index
		if difficulty ~= nil then
			view.wanted = difficulty
		end
		fitDifficulty()
		if changed or view.difficulty ~= before then
			-- The held Depart was for what stood selected when it was pressed.
			dropHeld()
		end
		paint()
		if changed then
			target.pop.Scale = Theme.MAP_SELECT_POP_SCALE
			TweenService
				:Create(target.pop, Motion.Info(Theme.MAP_SELECT_POP_SECONDS), { Scale = 1 })
				:Play()
		end
	end

	-- Sends the departure for what is selected now, where it is still allowed.
	local function send(): ()
		local current = selectedView()
		local levelId = if current ~= nil then current.node.level else nil
		if levelId == nil or not canDepart() then
			return
		end
		view.busy = true
		paintCard()
		deps.onDepart(levelId, view.difficulty)
	end

	local function confirm(): ()
		local current = selectedView()
		if current == nil or current.node.level == nil or not canDepart() or view.held then
			return
		end
		local rest = view.restUntil - os.clock()
		if rest <= 0 then
			send()
			return
		end
		-- The party has only just come back (Rest): the press is kept and sent when the rest is
		-- over. `send` asks again whether it is allowed then (the leader may have changed).
		view.held = true
		view.heldToken += 1
		local token = view.heldToken
		paintCard()
		task.delay(rest, function()
			if token ~= view.heldToken or not view.held then
				return
			end
			view.held = false
			send()
			paintCard()
		end)
	end

	local function setOpen(open: boolean): ()
		if open == view.open then
			return
		end
		view.open = open
		root.Visible = open
		if open then
			fitDifficulty()
			paint()
		else
			dropHeld()
		end
		deps.onOpenChanged(open)
	end

	local function newDot(): Frame
		local dot = Create("Frame", {
			Name = "Path",
			Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(Theme.MAP_PATH_DOT_SIZE, Theme.MAP_PATH_DOT_SIZE),
			BackgroundColor3 = Theme.MAP_COLOR_PATH,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = mapArea,
		}) :: Frame
		rounded(dot, UDim.new(0.5, 0))
		table.insert(dots, dot)
		return dot
	end

	-- The path: a row of dots from each node to the node it comes `from`, ring to ring.
	local function layPath(): ()
		local used = 0
		local ring = Theme.MAP_NODE_RING + Theme.MAP_PATH_CLEARANCE
		for _, nodeView in views do
			local fromId = nodeView.node.from
			local from = if fromId ~= nil then byId[fromId] else nil
			if from ~= nil then
				local span = nodeView.centre - from.centre
				local length = span.Magnitude
				local first = from.size / 2 + ring
				local last = length - nodeView.size / 2 - ring
				if length > 0 and last >= first then
					local heading = span / length
					local count = math.floor((last - first) / Theme.MAP_PATH_DOT_SPACING) + 1
					local step = if count > 1 then (last - first) / (count - 1) else 0
					for index = 0, count - 1 do
						used += 1
						local dot = dots[used] or newDot()
						local at = from.centre + heading * (first + step * index)
						dot.Position = UDim2.fromOffset(at.X, at.Y)
						dot.Visible = true
					end
				end
			end
		end
		for index = used + 1, #dots do
			dots[index].Visible = false
		end
	end

	for index, nodeView in views do
		table.insert(
			connections,
			nodeView.button.Activated:Connect(function()
				choose(index, nil)
			end)
		)
	end
	for index, item in card.difficulties do
		table.insert(
			connections,
			item.button.Activated:Connect(function()
				local current = selectedView()
				local entry = if current ~= nil then offered(current)[index] else nil
				if entry ~= nil then
					choose(view.selected, entry.id)
				end
			end)
		)
	end
	table.insert(connections, card.depart.Activated:Connect(confirm))
	table.insert(
		connections,
		close.Activated:Connect(function()
			setOpen(false)
		end)
	)
	local back = card.back
	local onReturn = deps.onReturn
	if back ~= nil and onReturn ~= nil then
		table.insert(connections, back.Activated:Connect(onReturn))
	end

	fitDifficulty()
	paint()

	local handle: MapScreenHandle = {
		SetState = function(state: Types.MapState)
			if typeof(state) ~= "table" or typeof(state.nodes) ~= "table" then
				return
			end
			-- Only an entry with the fields the screen reads is taken: it comes off the network.
			for _, entry in state.nodes do
				if
					typeof(entry) == "table"
					and typeof(entry.id) == "string"
					and typeof(entry.open) == "boolean"
					and typeof(entry.stars) == "table"
				then
					local nodeView = byId[entry.id]
					if nodeView ~= nil then
						nodeView.state = entry
						-- L2: read loosely, so a server without the field shows no row.
						nodeView.secrets = readSecrets((entry :: any).secrets)
					end
				end
			end
			if typeof(state.leaderUserId) == "number" then
				view.leaderUserId = state.leaderUserId
			end
			fitDifficulty()
			paint()
		end,
		SetParty = function(
			party: { Types.PartyMember },
			localUserId: number,
			leaderUserId: number
		)
			view.localUserId = localUserId
			view.leaderUserId = leaderUserId
			view.leaderName = ""
			local names: { string } = {}
			for _, member in party do
				if typeof(member) == "table" and typeof(member.name) == "string" then
					if member.userId == leaderUserId then
						view.leaderName = member.name
						table.insert(names, 1, LEADER_MARK .. member.name)
					else
						table.insert(names, member.name)
					end
				end
			end
			local text = table.concat(names, ", ")
			-- Pushed with every RunState: only a change repaints.
			local key = text .. "|" .. tostring(localUserId) .. "|" .. tostring(leaderUserId)
			if key == view.partyKey then
				return
			end
			view.partyKey = key
			view.partyText = text
			view.partySize = #names
			paintCard()
		end,
		Select = function(nodeId: string, difficulty: string?)
			for index, nodeView in views do
				if nodeView.node.id == nodeId then
					choose(index, difficulty)
					return
				end
			end
		end,
		Step = function(dx: number, dy: number)
			if dx ~= 0 then
				local index =
					math.min(math.max(view.selected + (if dx > 0 then 1 else -1), 1), #views)
				choose(index, nil)
			end
			if dy ~= 0 then
				local current = selectedView()
				local list: { Difficulty } = if current ~= nil then offered(current) else {}
				local at = 0
				for index, entry in list do
					if entry.id == view.difficulty then
						at = index
						break
					end
				end
				local entry = list[math.min(math.max(at + (if dy > 0 then 1 else -1), 1), #list)]
				if entry ~= nil then
					choose(view.selected, entry.id)
				end
			end
		end,
		Confirm = confirm,
		Open = function()
			setOpen(true)
		end,
		Close = function()
			setOpen(false)
		end,
		IsOpen = function(): boolean
			return view.open
		end,
		SetBusy = function(busy: boolean)
			if busy ~= view.busy then
				view.busy = busy
				paintCard()
			end
		end,
		Rest = function(seconds: number)
			-- A new rest is a new return: a Depart held for the last one does not carry over.
			dropHeld()
			view.restUntil = os.clock() + math.max(seconds, 0)
			paintCard()
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			if scale <= 0 then
				return
			end
			uiScale.Scale = scale
			local margin = Theme.SCREEN_MARGIN
			local width =
				math.max(math.min(viewportSize.X / scale - 2 * margin, Theme.MAP_MAX_WIDTH), 0)
			local height =
				math.max(math.min(viewportSize.Y / scale - 2 * margin, Theme.MAP_MAX_HEIGHT), 0)
			panel.Size = UDim2.fromOffset(width, height)
			local mapWidth = math.max(width - Theme.MAP_CARD_WIDTH - Theme.MAP_GAP, 0)
			mapArea.Size = UDim2.fromOffset(mapWidth, height)
			card.frame.Position = UDim2.fromOffset(mapWidth + Theme.MAP_GAP, 0)
			card.frame.Size = UDim2.fromOffset(Theme.MAP_CARD_WIDTH, height)
			-- A node's x and y are 0..1 of the room its centre may use: what is left once the
			-- largest node, its stars above and its name below are kept inside the map.
			local reach = Theme.MAP_NODE_SIZE / 2 + Theme.MAP_NODE_RING + Theme.MAP_NODE_GAP
			local left = Theme.MAP_NODE_PAD_X
			local top = Theme.MAP_NODE_PAD_EDGE + Theme.MAP_STAR_SIZE + reach
			local spanX = math.max(mapWidth - 2 * left, 0)
			local spanY = math.max(
				height - top - reach - Theme.MAP_NODE_NAME_HEIGHT - Theme.MAP_NODE_PAD_EDGE,
				0
			)
			local prints: { Footprint } = {}
			for _, nodeView in views do
				local own = nodeView.size / 2 + Theme.MAP_NODE_RING + Theme.MAP_NODE_GAP
				table.insert(prints, {
					x = left + math.clamp(nodeView.node.x, 0, 1) * spanX,
					y = top + math.clamp(nodeView.node.y, 0, 1) * spanY,
					half = math.max(
						nodeView.size / 2 + Theme.MAP_NODE_RING,
						Theme.MAP_NODE_NAME_WIDTH / 2
					),
					up = own + Theme.MAP_STAR_SIZE,
					down = own + Theme.MAP_NODE_NAME_HEIGHT,
					fixed = false,
					yields = nodeView.node.kind == BONUS_KIND,
				})
			end
			-- The close button holds its corner (top right).
			local edge = Theme.MAP_NODE_PAD_EDGE
			table.insert(prints, {
				x = mapWidth - (edge + Theme.MAP_CLOSE_SIZE) / 2,
				y = 0,
				half = (edge + Theme.MAP_CLOSE_SIZE) / 2,
				up = 0,
				down = edge + Theme.MAP_CLOSE_SIZE,
				fixed = true,
				yields = false,
			})
			spread(prints, mapWidth, height)
			for index, nodeView in views do
				local centre = Vector2.new(prints[index].x, prints[index].y)
				nodeView.centre = centre
				nodeView.holder.Position = UDim2.fromOffset(centre.X, centre.Y)
			end
			layPath()
		end,
		Destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			table.clear(views)
			table.clear(byId)
			table.clear(dots)
			root:Destroy()
		end,
	}
	return handle
end

return MapScreen
