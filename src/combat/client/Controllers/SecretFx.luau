--!strict
-- Secrets as chests, on the client (docs/prompts/l2-w1-contract.md, L2-14). The server decides
-- every find and pays it (SecretFlow, UnlockService); this draws the chests and says what
-- happened. CombatUIController hands it the level being played (RunState.levelId), the finds
-- the profile holds (Snapshot `combat.secrets`) and the `secret` CombatFx events.
--
--  * Every `Secret_<id>` Part the server builds under Workspace.Level carries a tall
--    translucent light column above it until the local player has found it, so a chest is seen
--    before it is reached (MISSIONS_DESIGN section 7). The column never collides and is never
--    queried: no ray (camera, aim, the ground probe) and no touch meets it. It is a child of
--    the chest Part, so a level cleared by the server takes it along.
--  * Found by the local player (the Snapshot, or the `found` event before it): the chest takes
--    Expeditions.json's `secretOpen` look (client-local; the fallback is a gold tint) and the
--    column goes. A Studio reset of the secrets puts both back.
--  * `found`, local player: a burst (not on low-end devices, spec section 10) and a centre card
--    for Theme.SECRET_CARD_SECONDS ("THE LOOKOUT FOUND", "+3 Valor", "+50 Timber", and a family
--    it records: nothing equips in W1). Someone else's find: a toast. `locked` (sent to that
--    player only): a toast naming the key ("Needs DOUBLE JUMP").
--
-- The card is Active = false and takes no tap; no sound (combat has none).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local Format = require(sharedFolder:WaitForChild("Format"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))

export type Toast = (text: string, seconds: number, isError: boolean) -> ()

-- One chest the server built: its Part, its id, how it looked as built (to put it back), and
-- its column while it shows.
type Chest = {
	part: BasePart,
	id: string,
	color: Color3,
	material: Enum.Material,
	transparency: number,
	column: Part?,
	open: boolean,
}

type Card = {
	frame: Frame,
	scale: UIScale,
	title: TextLabel,
	lines: { TextLabel },
	note: TextLabel,
}

-- Workspace.Level (LevelService.LEVEL_FOLDER) and the name of a chest Part in it.
local LEVEL_FOLDER = "Level"
local CHEST_PATTERN = "^Secret_(.+)$"
local SIGN_SUFFIX = "_Sign"
local OPEN_LOOK = "secretOpen"
local FOUND_SUFFIX = " FOUND"
local LATER_NOTE = " is yours: you can carry it in a later update"
local SOMEONE = "Someone"

local SecretFx = {}

local state = {
	gui = nil :: ScreenGui?,
	card = nil :: Card?,
	cardToken = 0,
	toast = nil :: Toast?,
	levelId = "",
	-- The profile's finds (Snapshot), and the local finds announced since (the next Snapshot
	-- carries them too).
	found = {} :: { [string]: { [string]: boolean } },
	announced = {} :: { [string]: { [string]: boolean } },
	chests = {} :: { [BasePart]: Chest },
	connections = {} :: { RBXScriptConnection },
}

local function isFound(id: string): boolean
	local level = state.levelId
	local saved = state.found[level]
	local seen = state.announced[level]
	return (saved ~= nil and saved[id] == true) or (seen ~= nil and seen[id] == true)
end

-- The `secretOpen` look, or nil (the fallback tint is used). Read each time: a config that is
-- still replicating at boot is read again on the next find.
local function openLook(): (Color3, Enum.Material?, number?)
	local expeditions = Catalog.GetExpeditionsConfig()
	local look = if expeditions ~= nil then expeditions.looks[OPEN_LOOK] else nil
	if look == nil then
		return Theme.SECRET_OPEN_FALLBACK_COLOR, nil, nil
	end
	local rgb = look.color
	local color = Theme.SECRET_OPEN_FALLBACK_COLOR
	if
		typeof(rgb) == "table"
		and typeof(rgb[1]) == "number"
		and typeof(rgb[2]) == "number"
		and typeof(rgb[3]) == "number"
	then
		color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	local material: Enum.Material? = nil
	for _, item in Enum.Material:GetEnumItems() do
		if item.Name == look.material then
			material = item
			break
		end
	end
	return color, material, look.transparency
end

local function newColumn(chest: Chest): Part
	local part = chest.part
	local height = Theme.SECRET_COLUMN_HEIGHT
	local column = Instance.new("Part")
	column.Name = "SecretColumn"
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.CastShadow = false
	column.Massless = true
	column.Material = Enum.Material.Neon
	column.Color = Theme.SECRET_COLUMN_COLOR
	column.Transparency = Theme.SECRET_COLUMN_TRANSPARENCY
	column.Size = Vector3.new(Theme.SECRET_COLUMN_WIDTH, height, Theme.SECRET_COLUMN_WIDTH)
	column.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + height / 2, 0))
	column.Parent = part
	return column
end

local function paint(chest: Chest): ()
	local open = isFound(chest.id)
	if open == chest.open and (open or chest.column ~= nil) then
		return
	end
	chest.open = open
	local part = chest.part
	if open then
		local column = chest.column
		if column ~= nil then
			column:Destroy()
			chest.column = nil
		end
		local color, material, transparency = openLook()
		part.Color = color
		if material ~= nil then
			part.Material = material
		end
		if transparency ~= nil then
			part.Transparency = transparency
		end
	else
		part.Color = chest.color
		part.Material = chest.material
		part.Transparency = chest.transparency
		if chest.column == nil then
			chest.column = newColumn(chest)
		end
	end
end

local function paintAll(): ()
	for _, chest in state.chests do
		paint(chest)
	end
end

local function adopt(child: Instance): ()
	if not child:IsA("BasePart") or state.chests[child] ~= nil then
		return
	end
	local name = child.Name
	if string.sub(name, -#SIGN_SUFFIX) == SIGN_SUFFIX then
		return
	end
	local id = string.match(name, CHEST_PATTERN)
	if id == nil then
		return
	end
	local chest: Chest = {
		part = child,
		id = id,
		color = child.Color,
		material = child.Material,
		transparency = child.Transparency,
		column = nil,
		open = false,
	}
	state.chests[child] = chest
	paint(chest)
end

local function forget(child: Instance): ()
	if child:IsA("BasePart") then
		state.chests[child] = nil
	end
end

local function watchLevel(): ()
	local folder = Workspace:WaitForChild(LEVEL_FOLDER, Theme.COMBAT_REMOTE_WAIT_SECONDS)
	if folder == nil then
		warn("[SecretFx] Workspace.Level never came: chests show no column")
		return
	end
	table.insert(state.connections, folder.ChildAdded:Connect(adopt))
	table.insert(state.connections, folder.ChildRemoved:Connect(forget))
	for _, child in folder:GetChildren() do
		adopt(child)
	end
end

local function cardLabel(
	name: string,
	size: number,
	color: Color3,
	order: number,
	parent: Instance
): TextLabel
	return Create("TextLabel", {
		Name = name,
		Active = false,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 6),
		Font = Theme.FONT_BOLD,
		TextSize = size,
		TextColor3 = color,
		TextWrapped = true,
		Text = "",
		Parent = parent,
	}) :: TextLabel
end

local function buildCard(gui: ScreenGui): Card
	local frame = Create("Frame", {
		Name = "SecretCard",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Theme.SECRET_CARD_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.MAP_COLOR_PANEL,
		BackgroundTransparency = Theme.SECRET_CARD_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = gui,
	}) :: Frame
	Create("UICorner", { CornerRadius = UDim.new(0, Theme.CORNER_RADIUS), Parent = frame })
	Create("UIStroke", {
		Color = Theme.MAP_COLOR_GOLD,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = frame,
	})
	local pad = Theme.SECRET_CARD_PADDING
	Create("UIPadding", {
		PaddingTop = UDim.new(0, pad),
		PaddingBottom = UDim.new(0, pad),
		PaddingLeft = UDim.new(0, pad),
		PaddingRight = UDim.new(0, pad),
		Parent = frame,
	})
	Create("UIListLayout", {
		Padding = UDim.new(0, 2),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	local scale = Create("UIScale", { Parent = frame }) :: UIScale
	local title = cardLabel("Title", Theme.SECRET_CARD_TITLE_TEXT, Theme.MAP_COLOR_GOLD, 1, frame)
	local lines = {
		cardLabel("Valor", Theme.SECRET_CARD_LINE_TEXT, Theme.MAP_COLOR_TEXT, 2, frame),
		cardLabel("Materials", Theme.SECRET_CARD_LINE_TEXT, Theme.MAP_COLOR_TEXT, 3, frame),
	}
	local note = cardLabel("Family", Theme.SECRET_CARD_NOTE_TEXT, Theme.MAP_COLOR_DIM, 4, frame)
	note.Font = Theme.FONT
	note.AutomaticSize = Enum.AutomaticSize.Y
	return { frame = frame, scale = scale, title = title, lines = lines, note = note }
end

-- A family's name from the weapons config, else its id with a capital.
local function familyName(id: string): string
	local def = Tuning.Get().weapons[id]
	if def ~= nil and typeof(def.name) == "string" and def.name ~= "" then
		return def.name
	end
	return string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2)
end

local function showCard(
	name: string,
	valor: number,
	materials: number,
	material: string,
	family: string?
): ()
	local card = state.card
	if card == nil then
		return
	end
	card.title.Text = string.upper(name) .. FOUND_SUFFIX
	local valorLine, materialLine = card.lines[1], card.lines[2]
	valorLine.Text = "+" .. Format.Cash(valor) .. " Valor"
	valorLine.Visible = valor > 0
	materialLine.Text = "+" .. Format.Cash(materials) .. " " .. material
	materialLine.Visible = materials > 0 and material ~= ""
	card.note.Text = if family ~= nil then familyName(family) .. LATER_NOTE else ""
	card.note.Visible = family ~= nil
	card.frame.Visible = true
	state.cardToken += 1
	local token = state.cardToken
	task.delay(Theme.SECRET_CARD_SECONDS, function()
		if token == state.cardToken then
			card.frame.Visible = false
		end
	end)
end

-- Sparks off the chest's top. Particles are skipped on low-end devices (spec section 10).
local function burst(id: string): ()
	if Theme.lowEndDevice then
		return
	end
	for _, chest in state.chests do
		if chest.id ~= id then
			continue
		end
		local part = chest.part
		local attachment = Instance.new("Attachment")
		attachment.Name = "SecretBurst"
		attachment.Position = Vector3.new(0, part.Size.Y / 2, 0)
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 0
		emitter.Color = ColorSequence.new(Theme.SECRET_BURST_COLOR)
		emitter.LightEmission = 1
		emitter.Lifetime =
			NumberRange.new(Theme.SECRET_BURST_SECONDS * 0.5, Theme.SECRET_BURST_SECONDS)
		emitter.Speed = NumberRange.new(Theme.SECRET_BURST_SPEED * 0.5, Theme.SECRET_BURST_SPEED)
		emitter.SpreadAngle = Vector2.new(Theme.SECRET_BURST_SPREAD, Theme.SECRET_BURST_SPREAD)
		emitter.Size = NumberSequence.new(Theme.SECRET_BURST_SIZE, 0)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Parent = attachment
		attachment.Parent = part
		emitter:Emit(Theme.SECRET_BURST_COUNT)
		task.delay(Theme.SECRET_BURST_SECONDS, function()
			attachment:Destroy()
		end)
	end
end

local function needWord(needs: string): string
	return Theme.SECRET_NEED_WORDS[needs] or string.upper(needs)
end

local function say(text: string, isError: boolean): ()
	local toast = state.toast
	if toast ~= nil then
		toast(text, Theme.SECRET_TOAST_SECONDS, isError)
	end
end

-- Mission HUD only: `gui` holds the card, `toast` says the short lines.
function SecretFx.Mount(gui: ScreenGui, toast: Toast): ()
	if state.gui ~= nil then
		return
	end
	state.gui = gui
	state.toast = toast
	state.card = buildCard(gui)
	task.spawn(watchLevel)
end

-- RunState.levelId ("" in the lobby): whose finds the chests standing now are judged by.
function SecretFx.SetLevel(levelId: string): ()
	if levelId == state.levelId then
		return
	end
	state.levelId = levelId
	paintAll()
end

-- The Snapshot's `combat.secrets` ({ [levelId]: { [secretId]: true } }), read defensively. The
-- local announcements are dropped: the profile is the truth again.
function SecretFx.SetFound(secrets: any): ()
	table.clear(state.found)
	table.clear(state.announced)
	if typeof(secrets) == "table" then
		for levelId, ids in secrets do
			if typeof(levelId) == "string" and typeof(ids) == "table" then
				local set: { [string]: boolean } = {}
				for id, value in ids do
					if typeof(id) == "string" and value == true then
						set[id] = true
					end
				end
				state.found[levelId] = set
			end
		end
	end
	paintAll()
end

-- One CombatFx of kind `secret` (CombatFxSecret), read defensively: it comes off the network.
function SecretFx.OnFx(fx: any): ()
	if
		typeof(fx) ~= "table"
		or fx.kind ~= "secret"
		or typeof(fx.userId) ~= "number"
		or typeof(fx.levelId) ~= "string"
		or typeof(fx.secretId) ~= "string"
		or typeof(fx.name) ~= "string"
		or typeof(fx.needs) ~= "string"
	then
		return
	end
	local mine = fx.userId == Players.LocalPlayer.UserId
	if fx.event == "locked" then
		if mine then
			say("Needs " .. needWord(fx.needs), true)
		end
		return
	end
	if fx.event ~= "found" then
		return
	end
	if not mine then
		local player = Players:GetPlayerByUserId(fx.userId)
		say((if player ~= nil then player.DisplayName else SOMEONE) .. " found " .. fx.name, false)
		return
	end
	local seen = state.announced[fx.levelId]
	if seen == nil then
		seen = {}
		state.announced[fx.levelId] = seen
	end
	seen[fx.secretId] = true
	paintAll()
	burst(fx.secretId)
	showCard(
		fx.name,
		if typeof(fx.valor) == "number" then fx.valor else 0,
		if typeof(fx.materials) == "number" then fx.materials else 0,
		if typeof(fx.material) == "string" then fx.material else "",
		if typeof(fx.family) == "string" and fx.family ~= "" then fx.family else nil
	)
end

-- The HUD's UI scale.
function SecretFx.SetLayout(scale: number): ()
	local card = state.card
	if card ~= nil and scale > 0 then
		card.scale.Scale = scale
	end
end

function SecretFx.Destroy(): ()
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
	for _, chest in state.chests do
		local column = chest.column
		if column ~= nil then
			column:Destroy()
		end
	end
	table.clear(state.chests)
	local card = state.card
	if card ~= nil then
		card.frame:Destroy()
	end
	state.card = nil
	state.gui = nil
	state.toast = nil
end

return SecretFx
