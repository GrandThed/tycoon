--!strict
-- Being hit in the Proving Grounds (docs/INTERFACES.md "P4 contracts": rulings 4, 6, 7 and 14;
-- docs/COMBAT_DESIGN.md section 4). Until P4 nothing in the range could hurt a player. Now
-- the server sends one `hurt` effect for every enemy attack that reaches one, batched once
-- per crowd step on the existing CombatFx event, and this module turns it into what the
-- player sees and feels. There is no sound: it is the screen, the camera and the motors.
--
-- For the local player's own hurt:
--  * a hit that landed drops the health bar, flashes the screen's edges (as strong as the
--    share of max health it took), points at where it came from, kicks and shakes the camera,
--    pulses the motors, and pops the number lost over the character;
--  * a hit an i-frame voided (`dodged`: a dash, the get-up window, the panel's god switch)
--    shows "DODGED" and nothing else, so the dash reads as a dodge;
--  * `push` / `launch` move the character through MovementController.ApplyKnock;
--  * `down` lays it on the floor (MovementController.SetDown) until `upAt`, with the HUD's
--    banner counting the time; then it stands up where it lies and shimmers green for
--    player.getUpIframes, the time the server keeps it untouchable.
-- Another player's hurt only flashes their character: their screen is theirs.
--
-- The client decides nothing: the amounts, the dodge, the push and the get-up time are the
-- server's. Health is read from the Humanoid, which replicates. The one thing timed here is
-- the get-up, because the server sends no second effect for it: it happens at `upAt`.
--
-- FeedbackController is not involved (it is at its limit of top-level locals and handles the
-- player's OWN hits); it and CombatFxController ignore the `hurt` kind. The two share only
-- the Haptics module, because they drive the same motors. Everything animates from the one
-- RenderStepped connection below; billboards and highlights are pooled.
--
-- Nothing here is gated on Theme.reducedMotion (true on every touch device) or
-- lowEndDevice: all of it is information. CameraController already halves the kick and the
-- shake under reducedMotion on its own.
--
-- P5 (docs/INTERFACES.md "P5 contracts", rulings 18 and 22): missions are hurt the same way.
-- The one difference is the down: a mission's `hurt` with `down` carries no `upAt`, because a
-- down there never ends by itself. The player lies down under a "DOWN" banner with no count
-- until the server stands them up (a wave boundary, a new run), which no effect announces:
-- the RunState's PartyMember.down is that word, pushed in through SetServerDown. It counts in
-- both directions: a member the server holds down whom this client shows standing (a new
-- character: the server keeps the down across a respawn) is laid down again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local VitalsHud = require(uiFolder:WaitForChild("VitalsHud"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))
local Haptics = require(script.Parent:WaitForChild("Haptics"))

type Rig = { character: Model, humanoid: Humanoid, root: BasePart }

-- One pooled number over the local character. `side` alternates so two numbers in a row
-- drift apart; `dodge` = it reads "DODGED" (and rides its own row); `total` = the health lost
-- that it shows, summed over the hits it took in; `popAt` = when it last popped.
type Number = {
	gui: BillboardGui,
	scale: UIScale,
	label: TextLabel,
	stroke: UIStroke,
	startedAt: number,
	popAt: number,
	side: number,
	dodge: boolean,
	total: number,
	active: boolean,
}

-- One pooled flash on another player's character.
type Flinch = { highlight: Highlight, startedAt: number, active: boolean }

local FX_FOLDER = "RangeVitalsFx"
local DODGED_TEXT = "DODGED"
-- Slack on the get-up, both ways. The server's get-up time is trusted, but never past the
-- configured down time by more than this: a clock gone wrong must not leave the player on
-- the floor. And the bar waits at most this long for the server's heal to replicate.
local DOWN_SLACK_SECONDS = 1

local VitalsController = {}

local started = false
local connections: { RBXScriptConnection } = {}
local cachedRig: Rig? = nil
local fxFolder: Folder? = nil
local hud: VitalsHud.VitalsHudHandle? = nil
local layoutScale = 1
local numbers: { Number } = {}
local numberSide = 1
local flinches: { Flinch } = {}
-- Server time the local player gets up; nil = standing; math.huge = a mission's down, held
-- until the server stands the player up (SetServerDown).
local downUntil: number? = nil
-- P5: a held down, as the RunState has reported it. `seen` = a RunState has said "down" since
-- it began, `at` = the os.clock it began; together they keep a RunState sent before the down
-- reached the server from standing the player up again. `upAt` = the os.clock of the last
-- stand-up the RunState ordered, which keeps a RunState sent before it from undoing it.
local held = { seen = false, at = 0, upAt = -math.huge }
-- The get-up heal on its way: until os.clock() reaches healBy, or the replicated Health moves
-- off staleHealth (what it read at the get-up), the bar shows full. 0 = not waiting.
local healBy = 0
local staleHealth = 0
-- The get-up shimmer: one Highlight, on until this server time.
local shimmer: Highlight? = nil
local shimmerUntil = 0

-- The local character's parts. Asked every frame, so the record is kept until the character
-- or one of the two parts changes; a steady frame allocates nothing.
local function localRig(): Rig?
	local character = Players.LocalPlayer.Character
	local known = cachedRig
	if
		known ~= nil
		and known.character == character
		and known.humanoid.Parent == character
		and known.root.Parent == character
	then
		return known
	end
	cachedRig = nil
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local found: Rig = { character = character, humanoid = humanoid, root = root }
	cachedRig = found
	return found
end

local function feedbackStrength(layer: string): number
	local feedback = (Tuning.Get() :: any).feedback
	local value = if typeof(feedback) == "table" then feedback[layer] else nil
	return if typeof(value) == "number" then math.max(value, 0) else 1
end

-- Numbers --------------------------------------------------------------------------------

local function newNumber(playerGui: Instance): Number
	local gui = Create("BillboardGui", {
		Name = "RangeHurtNumber",
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = false,
		Parent = playerGui,
	}) :: BillboardGui
	local scale = Create("UIScale", { Parent = gui }) :: UIScale
	local label = Create("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_BOLD,
		Text = "",
		Parent = gui,
	}) :: TextLabel
	local stroke = Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = label,
	}) :: UIStroke
	return {
		gui = gui,
		scale = scale,
		label = label,
		stroke = stroke,
		startedAt = 0,
		popAt = 0,
		side = 1,
		dodge = false,
		total = 0,
		active = false,
	}
end

-- A free number, or the oldest recycled, so a crowd's lunges never pile up more than
-- MAX_ACTIVE billboards.
local function takeNumber(): Number?
	local oldest: Number? = nil
	for _, number in numbers do
		if not number.active then
			return number
		end
		if oldest == nil or number.startedAt < oldest.startedAt then
			oldest = number
		end
	end
	if #numbers < Theme.COMBAT_RANGE_HURT_NUMBER_MAX_ACTIVE then
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui ~= nil then
			local number = newNumber(playerGui)
			table.insert(numbers, number)
			return number
		end
	end
	return oldest
end

-- The live number of that kind that is still young enough to take one more hit in.
local function youngNumber(dodge: boolean, now: number): Number?
	for _, number in numbers do
		if
			number.active
			and number.dodge == dodge
			and now - number.startedAt <= Theme.COMBAT_RANGE_HURT_NUMBER_MERGE_SECONDS
		then
			return number
		end
	end
	return nil
end

-- A pooled number started afresh over `rig`'s head, on its kind's row: losses on the lower
-- row, "DODGED" one row of its own height above them, so the two never cover each other
-- (SizeOffset is in units of the billboard's own size, so a row is a row at any distance).
local function startNumber(rig: Rig, dodge: boolean, now: number): Number?
	local number = takeNumber()
	if number == nil then
		return nil
	end
	local textSize = if dodge
		then Theme.COMBAT_RANGE_HURT_DODGE_TEXT
		else Theme.COMBAT_RANGE_HURT_NUMBER_TEXT
	numberSide = -numberSide
	number.side = numberSide
	number.startedAt = now
	number.dodge = dodge
	number.total = 0
	number.active = true
	number.gui.Adornee = rig.root
	number.gui.Size = UDim2.fromOffset(
		Theme.COMBAT_RANGE_HURT_NUMBER_WIDTH * layoutScale,
		Theme.COMBAT_RANGE_HURT_NUMBER_HEIGHT * layoutScale
	)
	number.gui.SizeOffset = Vector2.new(0, if dodge then 1 else 0)
	number.gui.StudsOffset = Vector3.zero
	number.gui.StudsOffsetWorldSpace =
		Vector3.new(0, Theme.COMBAT_RANGE_HURT_NUMBER_HEAD_CLEARANCE, 0)
	number.label.TextColor3 = if dodge
		then Theme.COMBAT_RANGE_DODGE_COLOR
		else Theme.COMBAT_RANGE_HURT_COLOR
	number.label.TextSize = textSize * layoutScale
	number.label.TextTransparency = 0
	number.stroke.Transparency = 0
	number.gui.Enabled = true
	return number
end

-- Shows one hit over the local character's head: the health it took, or "DODGED" (`amount`
-- nil) for a hit an i-frame voided. It rises and fades from the frame step.
-- Hits that land together must not pile up on one spot: a knock arrives with every other hit
-- of that moment voided (contract ruling 18), and two lunges can land in one frame. So a hit
-- inside MERGE_SECONDS of a live number of its kind joins that number, which pops again where
-- it is: several dodges are one "DODGED", several losses one total.
local function showNumber(amount: number?): ()
	local rig = localRig()
	if rig == nil then
		return
	end
	local now = os.clock()
	local dodge = amount == nil
	local number = youngNumber(dodge, now) or startNumber(rig, dodge, now)
	if number == nil then
		return
	end
	number.popAt = now
	number.scale.Scale = Theme.COMBAT_RANGE_HURT_NUMBER_POP_SCALE
	if amount ~= nil then
		number.total += amount
		number.label.Text = "−" .. Format.Cash(number.total)
	else
		number.label.Text = DODGED_TEXT
	end
end

local function stepNumbers(now: number): ()
	for _, number in numbers do
		if not number.active then
			continue
		end
		local age = now - number.startedAt
		local u = age / Theme.COMBAT_RANGE_HURT_NUMBER_SECONDS
		if u >= 1 then
			number.active = false
			number.gui.Enabled = false
			continue
		end
		local popLeft =
			math.max(0, 1 - (now - number.popAt) / Theme.COMBAT_RANGE_HURT_NUMBER_POP_SECONDS)
		number.scale.Scale = 1 + (Theme.COMBAT_RANGE_HURT_NUMBER_POP_SCALE - 1) * popLeft
		-- World space for the rise, so a body lying on its back still sends the number up.
		number.gui.StudsOffsetWorldSpace = Vector3.new(
			0,
			Theme.COMBAT_RANGE_HURT_NUMBER_HEAD_CLEARANCE + Theme.COMBAT_RANGE_HURT_NUMBER_RISE * u,
			0
		)
		number.gui.StudsOffset =
			Vector3.new(number.side * Theme.COMBAT_RANGE_HURT_NUMBER_DRIFT * u, 0, 0)
		local fadeFrom = Theme.COMBAT_RANGE_HURT_NUMBER_FADE_FROM
		local fade = if u <= fadeFrom then 0 else (u - fadeFrom) / (1 - fadeFrom)
		number.label.TextTransparency = fade
		number.stroke.Transparency = fade
	end
end

-- Highlights -----------------------------------------------------------------------------

local function newHighlight(name: string, color: Color3, depth: Enum.HighlightDepthMode): Highlight
	-- Parented to this module's folder and aimed with Adornee, never into a character: a
	-- respawn must not take a pooled Highlight with it.
	return Create("Highlight", {
		Name = name,
		FillColor = color,
		OutlineColor = color,
		FillTransparency = 1,
		OutlineTransparency = 1,
		DepthMode = depth,
		Enabled = false,
		Parent = fxFolder,
	}) :: Highlight
end

-- Another player was hit: a short red flash on their character.
local function flinch(userId: number): ()
	local player = Players:GetPlayerByUserId(userId)
	local character = if player ~= nil then player.Character else nil
	if character == nil then
		return
	end
	local chosen: Flinch? = nil
	local oldest: Flinch? = nil
	for _, entry in flinches do
		-- A second hit on the same character renews its flash instead of taking another.
		if entry.active and entry.highlight.Adornee == character then
			chosen = entry
			break
		end
		if not entry.active then
			chosen = chosen or entry
		elseif oldest == nil or entry.startedAt < oldest.startedAt then
			oldest = entry
		end
	end
	if chosen == nil and #flinches < Theme.COMBAT_RANGE_FLINCH_POOL then
		local entry: Flinch = {
			highlight = newHighlight(
				"Flinch",
				Theme.COMBAT_RANGE_HURT_COLOR,
				Enum.HighlightDepthMode.Occluded
			),
			startedAt = 0,
			active = false,
		}
		table.insert(flinches, entry)
		chosen = entry
	end
	local entry = chosen or oldest
	if entry == nil then
		return
	end
	entry.startedAt = os.clock()
	entry.active = true
	entry.highlight.Adornee = character
	entry.highlight.Enabled = true
end

local function stepFlinches(now: number): ()
	for _, entry in flinches do
		if not entry.active then
			continue
		end
		local u = (now - entry.startedAt) / Theme.COMBAT_RANGE_FLINCH_SECONDS
		if u >= 1 then
			entry.active = false
			entry.highlight.Enabled = false
			entry.highlight.Adornee = nil
			continue
		end
		entry.highlight.FillTransparency = 1 - (1 - Theme.COMBAT_RANGE_FLINCH_FILL) * (1 - u)
		entry.highlight.OutlineTransparency = u
	end
end

local function endShimmer(): ()
	shimmerUntil = 0
	local highlight = shimmer
	if highlight ~= nil and highlight.Enabled then
		highlight.Enabled = false
		highlight.Adornee = nil
	end
end

-- The get-up i-frames, made visible: the character pulses green until they run out.
local function stepShimmer(serverNow: number): ()
	if shimmerUntil <= 0 then
		return
	end
	local rig = localRig()
	if rig == nil or serverNow >= shimmerUntil then
		endShimmer()
		return
	end
	-- One Highlight for the life of the module, made the first time anyone gets up.
	local highlight: Highlight = shimmer
		or newHighlight(
			"GetUp",
			Theme.COMBAT_RANGE_DODGE_COLOR,
			Enum.HighlightDepthMode.AlwaysOnTop
		)
	shimmer = highlight
	local wave = 0.5 + 0.5 * math.sin(serverNow * 2 * math.pi * Theme.COMBAT_RANGE_GETUP_PULSE_HZ)
	highlight.FillTransparency = Theme.COMBAT_RANGE_GETUP_FILL_MIN
		+ (Theme.COMBAT_RANGE_GETUP_FILL_MAX - Theme.COMBAT_RANGE_GETUP_FILL_MIN) * wave
	highlight.OutlineTransparency = 0
	if highlight.Adornee ~= rig.character then
		highlight.Adornee = rig.character
	end
	if not highlight.Enabled then
		highlight.Enabled = true
	end
end

-- Down and up ----------------------------------------------------------------------------

-- Stands the local player up. `real` = the get-up itself, when the server heals to full and
-- opens player.getUpIframes; false = the down state is only being dropped (a new character,
-- the module going away).
local function standUp(real: boolean): ()
	local upAt = downUntil
	if upAt == nil then
		return
	end
	downUntil = nil
	MovementController.SetDown(false)
	local mounted = hud
	if mounted ~= nil then
		mounted.SetDown(nil, 0)
	end
	if not real then
		return
	end
	-- A held down's get-up is now: the server stood the player up as the RunState said so.
	local upFrom = if upAt == math.huge then Workspace:GetServerTimeNow() else upAt
	shimmerUntil = upFrom + math.max(Tuning.Get().player.getUpIframes, 0)
	-- The heal happens on the server at this same moment but replicates half a ping later:
	-- until it does, the Humanoid still reads the sliver it was held at while down, and the
	-- bar must not show that as the health the player got up with (see step).
	local rig = localRig()
	staleHealth = if rig ~= nil then rig.humanoid.Health else 0
	healBy = os.clock() + DOWN_SLACK_SECONDS
	Haptics.Pulse(
		Theme.COMBAT_RANGE_HAPTIC_LIGHT * feedbackStrength("haptics"),
		Theme.COMBAT_RANGE_HAPTIC_SECONDS
	)
end

-- `upAt` = the server time of the get-up; `away` = the way the blow was travelling. In a
-- mission no `upAt` comes: the down is held (P5 ruling 18). In the range a missing one still
-- falls back to player.downSeconds, as in P4.
local function goDown(upAt: number?, away: Vector3?): ()
	local serverNow = Workspace:GetServerTimeNow()
	local seconds = math.max(Tuning.Get().player.downSeconds, 0)
	local latest = serverNow + seconds + DOWN_SLACK_SECONDS
	local at = if upAt ~= nil and upAt == upAt
		then math.min(upAt, latest)
		elseif CameraController.IsRange() then serverNow + seconds
		else math.huge
	downUntil = at
	held.seen = false
	held.at = os.clock()
	healBy = 0
	endShimmer()
	MovementController.SetDown(true, away)
	local mounted = hud
	if mounted ~= nil then
		mounted.SetDown(at, if at == math.huge then 0 else math.max(at - serverNow, seconds))
	end
end

-- Hurt -----------------------------------------------------------------------------------

local function onLocalHurt(fx: Types.CombatFxHurt): ()
	if fx.dodged == true then
		-- Ruling 7: a voided hit says so, and only that.
		showNumber(nil)
		return
	end
	local rig = localRig()
	local maxHealth = if rig ~= nil then rig.humanoid.MaxHealth else 0
	local amount = math.max(fx.amount, 0)
	local share = if maxHealth > 0 then math.clamp(amount / maxHealth, 0, 1) else 1
	local strength = math.clamp(
		share / Theme.COMBAT_RANGE_HURT_FLASH_FULL_SHARE,
		Theme.COMBAT_RANGE_HURT_FLASH_MIN,
		1
	)
	local mounted = hud
	if mounted ~= nil then
		mounted.Hurt(share)
		mounted.Point(fx.from)
	end
	showNumber(amount)
	local shake = feedbackStrength("shake")
	CameraController.Kick(Theme.COMBAT_RANGE_HURT_KICK_DEGREES * strength * shake)
	CameraController.Shake(Theme.COMBAT_RANGE_HURT_SHAKE * strength * shake)
	local heavy = fx.down == true or fx.push ~= nil or fx.launch ~= nil
	Haptics.Pulse(
		(if heavy then Theme.COMBAT_RANGE_HAPTIC_HEAVY else Theme.COMBAT_RANGE_HAPTIC_LIGHT)
			* feedbackStrength("haptics"),
		if heavy then Theme.COMBAT_RANGE_HAPTIC_HEAVY_SECONDS else Theme.COMBAT_RANGE_HAPTIC_SECONDS
	)
	local push = fx.push
	if fx.down == true then
		-- Down first: it ends every move in progress, so the blow's own knock is not refused
		-- as it would be mid-dash.
		local away = push
		if away == nil and rig ~= nil then
			away = rig.root.Position - fx.from
		end
		goDown(fx.upAt, away)
	end
	if push ~= nil or fx.launch ~= nil then
		MovementController.ApplyKnock(push or Vector3.zero, fx.launch or 0)
	end
end

-- Only a table with the contract's fields, each of its type, is acted on.
local function parseHurt(raw: { [string]: any }): Types.CombatFxHurt?
	if
		typeof(raw.userId) ~= "number"
		or typeof(raw.amount) ~= "number"
		or raw.amount ~= raw.amount
		or typeof(raw.from) ~= "Vector3"
		or (raw.push ~= nil and typeof(raw.push) ~= "Vector3")
		or (raw.launch ~= nil and typeof(raw.launch) ~= "number")
		or (raw.dodged ~= nil and typeof(raw.dodged) ~= "boolean")
		or (raw.down ~= nil and typeof(raw.down) ~= "boolean")
		or (raw.upAt ~= nil and typeof(raw.upAt) ~= "number")
	then
		return nil
	end
	return {
		kind = "hurt",
		userId = raw.userId,
		amount = raw.amount,
		from = raw.from,
		enemyKind = if typeof(raw.enemyKind) == "string" then raw.enemyKind else "",
		attack = if typeof(raw.attack) == "number" then raw.attack else 0,
		push = raw.push,
		launch = raw.launch,
		dodged = raw.dodged,
		down = raw.down,
		upAt = raw.upAt,
	}
end

local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" or fx.kind ~= "hurt" then
		return
	end
	local hurt = parseHurt(fx :: { [string]: any })
	if hurt == nil then
		return
	end
	if hurt.userId == Players.LocalPlayer.UserId then
		onLocalHurt(hurt)
	elseif hurt.dodged ~= true then
		flinch(hurt.userId)
	end
end

-- CombatFx carries a batch (an array of effects); a lone effect table is accepted too.
local function onCombatFx(payload: any): ()
	if typeof(payload) ~= "table" then
		return
	end
	if payload.kind ~= nil then
		applyFx(payload)
		return
	end
	for _, fx in payload :: { any } do
		applyFx(fx)
	end
end

-- Per frame ------------------------------------------------------------------------------

local function step(deltaTime: number): ()
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	if downUntil ~= nil and serverNow >= downUntil then
		standUp(true)
	end
	local rig = localRig()
	if downUntil == math.huge and rig ~= nil then
		-- P5: a held down outlives its body. MovementController forgets the pose with the old
		-- character, so the new one is laid down as soon as it is whole (a no-op otherwise).
		MovementController.SetDown(true, nil)
	end
	local mounted = hud
	if mounted ~= nil then
		if rig ~= nil then
			local maxHealth = rig.humanoid.MaxHealth
			local health = rig.humanoid.Health
			if downUntil ~= nil then
				-- The server holds a sliver of health while the player is down (0 would kill
				-- the Humanoid); the bar shows that as empty.
				health = 0
			elseif healBy > 0 then
				-- Just up: the bar shows the full health the server has already given, until
				-- the Humanoid's own value moves off the sliver (the heal has arrived, with
				-- anything that happened after it) or the slack runs out.
				if health ~= staleHealth or now >= healBy then
					healBy = 0
				else
					health = maxHealth
				end
			end
			mounted.SetHealth(health, maxHealth)
		end
		mounted.Step(deltaTime, if rig ~= nil then rig.root.Position else nil)
	end
	stepNumbers(now)
	stepFlinches(now)
	stepShimmer(serverNow)
end

-- Public API -----------------------------------------------------------------------------

function VitalsController.Init(): ()
	-- Remotes and PlayerGui are replicated instances: everything happens in Start.
end

-- Inert unless the range's combat runs (the range and, since P5, every crowd mission); a build
-- without it keeps CombatFxController's C1 hurt feedback.
function VitalsController.Start(): ()
	if started or not CameraController.IsCrowdCombat() then
		return
	end
	started = true
	fxFolder = Create("Folder", { Name = FX_FOLDER, Parent = Workspace }) :: Folder
	Haptics.Detect()
	table.insert(connections, RunService.RenderStepped:Connect(step))
	-- A new body is standing: whatever the old one was in the middle of is over. P5: all but
	-- a mission's held down, which the server keeps on the new body too; `step` lays it down
	-- again, and only the RunState ends it.
	table.insert(
		connections,
		Players.LocalPlayer.CharacterAdded:Connect(function()
			if downUntil ~= math.huge then
				standUp(false)
			end
			endShimmer()
			healBy = 0
		end)
	)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local combatFx =
			remotes:WaitForChild("CombatFx", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if not started then
			return -- destroyed while waiting
		end
		if combatFx == nil then
			warn("[VitalsController] CombatFx missing — hurt feedback is disabled")
			return
		end
		table.insert(connections, combatFx.OnClientEvent:Connect(onCombatFx))
	end)
end

-- CombatUIController mounts the HUD half into the range's inset-free ScreenGui (the one the
-- crosshair lives in, so the pointer ring is centred on it).
function VitalsController.Mount(screenGui: ScreenGui): ()
	if hud == nil then
		hud = VitalsHud.new(screenGui)
	end
end

function VitalsController.SetLayout(layout: VitalsHud.Layout): ()
	layoutScale = layout.scale
	local mounted = hud
	if mounted ~= nil then
		mounted.SetLayout(layout)
	end
end

-- P5: the local player's PartyMember.down from every RunState of a mission: the server's word
-- on the down, in both directions.
--  * "standing" ends a held down (the server's StandUp sends no effect). It only counts once a
--    RunState has shown the down, or the down is older than the slack: one sent just before
--    the blow reached the server must not stand the player straight back up.
--  * "down" while this client shows the player standing lays them down, held. That is a down
--    whose `hurt` this client never acted on, and a body the server kept down across a respawn
--    this client did not carry it through. The same slack guards the stand-up just ordered.
-- Never called in the range, whose downs are timed.
function VitalsController.SetServerDown(down: boolean): ()
	if not started or CameraController.IsRange() then
		return
	end
	local now = os.clock()
	if downUntil == math.huge then
		if down then
			held.seen = true
		elseif held.seen or now - held.at >= DOWN_SLACK_SECONDS then
			held.upAt = now
			standUp(true)
		end
	elseif down and downUntil == nil and now - held.upAt >= DOWN_SLACK_SECONDS then
		goDown(nil, nil)
		held.seen = true
	end
end

function VitalsController.Destroy(): ()
	started = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	Haptics.Stop()
	standUp(false)
	for _, number in numbers do
		number.gui:Destroy()
	end
	table.clear(numbers)
	table.clear(flinches)
	shimmer = nil
	shimmerUntil = 0
	healBy = 0
	cachedRig = nil
	local mounted = hud
	hud = nil
	if mounted ~= nil then
		mounted.Destroy()
	end
	local folder = fxFolder
	fxFolder = nil
	if folder ~= nil then
		folder:Destroy()
	end
end

return VitalsController
