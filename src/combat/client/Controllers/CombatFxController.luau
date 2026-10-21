--!strict
-- The run's banners and notices for the dungeon place. Everything here is presentation of
-- something the server already decided: it consumes the `CombatFx` batch and turns the run's
-- events into a banner, a toast or a floating line. It never reads an HP, never decides a
-- reward and never sends a remote.
--
-- What it still reads of the batch (L4 W1b, docs/prompts/l4-w1b-contract.md row 7): `wave`
-- (a wave of a camp starts), `bossDown`, `mentor` (Valor for carrying a party), `camp` (the
-- boss room's gates closed, a camp cleared, and CampFx's alerts and checkpoint) and `notice` (a
-- Studio lever's line). The C1 kinds (hits, kills, telegraphs, swings, party effects, refusals)
-- went with the services that sent them; the range's own effects are FeedbackController's,
-- VitalsController's and ThreatFx's.
--
-- floatText is a copy of PlotVisualsController.floatText (:497) adapted to a world position,
-- because the two client trees never require across each other. Dedupe is a follow-up.
--
-- Device gating (spec section 10): banners, notices and sounds always play, because they carry
-- information; the floating line rides a tween that Motion shortens on touch and low-end devices.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Format = require(sharedFolder:WaitForChild("Format"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local Motion = require(uiFolder:WaitForChild("Motion"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
-- L1b: the camp cues (the "!" over a woken group, the checkpoint notice) live there.
local CampFx = require(script.Parent:WaitForChild("CampFx"))

-- Fallbacks for a build with no Combat.json: the feature still renders, just untuned.
local DEFAULT_DAMAGE_SECONDS = 0.8
local DEFAULT_BANNER_SECONDS = 2

local CombatFxController = {}

local combatConfig: Types.CombatConfig? = nil
local activeNumbers = 0
local bannerFrame: Frame? = nil
local bannerTitle: TextLabel? = nil
local bannerSub: TextLabel? = nil
-- L1 fix round: the banner's own scale, and the frame its host last gave it (SetBannerLayout),
-- kept so a layout that arrives before the overlay is built is not lost.
local bannerScale: UIScale? = nil
local bannerLayout: { scale: number, centreX: number, top: number, width: number }? = nil
local bannerToken = 0
local connections: { RBXScriptConnection } = {}
local onToast: ((string) -> ())? = nil

local function feedback(): Types.CombatFeedbackConfig?
	local cfg = combatConfig
	return if cfg ~= nil then cfg.feedback else nil
end

local function damageNumberSeconds(): number
	local fb = feedback()
	return if fb ~= nil then fb.damageNumberSeconds else DEFAULT_DAMAGE_SECONDS
end

local function bannerSeconds(): number
	local fb = feedback()
	return if fb ~= nil then fb.bannerSeconds else DEFAULT_BANNER_SECONDS
end

-- An anchor for a BillboardGui at a bare world position. Terrain is a BasePart, so an
-- Attachment under it is the cheapest legal adornee that needs no part of our own.
local function worldAnchor(position: Vector3): Attachment
	return Create("Attachment", {
		Name = "FxAnchor",
		WorldPosition = position,
		Parent = Workspace.Terrain,
	}) :: Attachment
end

-- COPY of PlotVisualsController.floatText (:497), re-based on a world position.
local function floatText(position: Vector3, text: string, color: Color3): ()
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil or activeNumbers >= Theme.COMBAT_DAMAGE_MAX_ACTIVE then
		return
	end
	activeNumbers += 1
	local jitter = Theme.COMBAT_DAMAGE_JITTER
	local anchor = worldAnchor(
		position + Vector3.new((math.random() - 0.5) * jitter, 0, (math.random() - 0.5) * jitter)
	)
	local gui = Create("BillboardGui", {
		Name = "FxDamage",
		Adornee = anchor,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(
			Theme.COMBAT_DAMAGE_BILLBOARD_WIDTH,
			Theme.COMBAT_DAMAGE_BILLBOARD_HEIGHT
		),
		Parent = playerGui,
	}) :: BillboardGui
	local label = Create("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_DAMAGE_FINISHER_TEXT_SIZE,
		TextColor3 = color,
		Text = text,
		Parent = gui,
	}) :: TextLabel
	local stroke = Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = label,
	}) :: UIStroke

	local info = Motion.Info(damageNumberSeconds())
	local rise = TweenService:Create(
		gui,
		info,
		{ StudsOffsetWorldSpace = Vector3.new(0, Theme.COMBAT_DAMAGE_RISE, 0) }
	)
	rise.Completed:Once(function()
		activeNumbers -= 1
		gui:Destroy()
		anchor:Destroy()
	end)
	rise:Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
end

-- The banner in the frame its host gave it: scaled like the rest of the HUD, at that place and
-- no wider than that. Without one it keeps its design size, centred near the top.
local function applyBannerLayout(): ()
	local frame = bannerFrame
	local uiScale = bannerScale
	local layout = bannerLayout
	if frame == nil or uiScale == nil or layout == nil then
		return
	end
	uiScale.Scale = layout.scale
	frame.Position = UDim2.fromOffset(layout.centreX, layout.top)
	frame.Size = UDim2.fromOffset(layout.width / layout.scale, Theme.COMBAT_BANNER_HEIGHT)
end

local function showBanner(title: string, sub: string, seconds: number): ()
	local frame = bannerFrame
	local titleLabel = bannerTitle
	local subLabel = bannerSub
	if frame == nil or titleLabel == nil or subLabel == nil then
		return
	end
	bannerToken += 1
	local token = bannerToken
	titleLabel.Text = title
	subLabel.Text = sub
	subLabel.Visible = sub ~= ""
	frame.Visible = true
	task.delay(seconds, function()
		if token == bannerToken then
			frame.Visible = false
		end
	end)
end

local function localUserId(): number
	return Players.LocalPlayer.UserId
end

local function onWave(fx: { [string]: any }): ()
	local wave = fx.wave
	if typeof(wave) ~= "number" then
		return
	end
	if fx.boss == true then
		SoundController.Play("bossStart")
		showBanner("Boss wave", "Wave " .. tostring(wave), bannerSeconds())
	elseif fx.merged == true then
		SoundController.Play("waveStart")
		showBanner(
			"Waves " .. tostring(wave - 1) .. " + " .. tostring(wave),
			"The director merged them",
			bannerSeconds()
		)
	else
		SoundController.Play("waveStart")
		showBanner("Wave " .. tostring(wave), "", bannerSeconds())
	end
end

local function onBossDown(fx: { [string]: any }): ()
	local name = if typeof(fx.name) == "string" then fx.name else "Boss"
	local valor = if typeof(fx.valor) == "number" then fx.valor else 0
	SoundController.Play("bossDown")
	showBanner(name .. " down", "+" .. Format.Cash(valor) .. " Valor", bannerSeconds())
end

local function toast(text: string): ()
	local handler = onToast
	if handler ~= nil then
		handler(text)
	end
end

local function onMentor(fx: { [string]: any }): ()
	local valor = fx.valor
	if fx.userId ~= localUserId() or typeof(valor) ~= "number" then
		return
	end
	local text = "+" .. Format.Cash(valor) .. " Valor · Mentor"
	SoundController.Play("mentor")
	toast(text)
	local rig = Players.LocalPlayer.Character
	local head = if rig ~= nil then rig:FindFirstChild("Head") else nil
	if head ~= nil and head:IsA("BasePart") then
		floatText(head.Position, text, Theme.COLOR_HIGHLIGHT)
	end
end

-- L1: the boss room's gates closed behind the party (the banner is its name) or a camp was
-- cleared. L1b: a group woke (`alert`: a "!" over each of `ids`) or a checkpoint was reached
-- (`checkpoint`: the HUD's notice); both are CampFx's. Nothing is saved any more (every kill
-- pays at once), so a clear is the banner alone. No sound: the banner and the marks are the cue.
local function onCamp(fx: { [string]: any }): ()
	local event = fx.event
	if event == "alert" then
		CampFx.Alert(fx.ids)
		return
	elseif event == "checkpoint" then
		CampFx.Checkpoint()
		return
	end
	local name = fx.name
	if typeof(name) ~= "string" or name == "" then
		return
	end
	if event == "closed" then
		showBanner(name, "", bannerSeconds())
	elseif event == "cleared" then
		showBanner(name .. " cleared", "", bannerSeconds())
	end
end

-- L1: a line from a Studio lever (the gear the G key just set).
local function onNotice(fx: { [string]: any }): ()
	local text = fx.text
	if typeof(text) == "string" and text ~= "" then
		toast(text)
	end
end

local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" or typeof(fx.kind) ~= "string" then
		return
	end
	local payload = fx :: { [string]: any }
	local kind = payload.kind
	if kind == "wave" then
		onWave(payload)
	elseif kind == "bossDown" then
		onBossDown(payload)
	elseif kind == "mentor" then
		onMentor(payload)
	elseif kind == "camp" then
		onCamp(payload)
	elseif kind == "notice" then
		onNotice(payload)
	end
end

local function onCombatFx(batch: any): ()
	if typeof(batch) ~= "table" then
		return
	end
	for _, fx in batch :: { any } do
		applyFx(fx)
	end
end

local function buildOverlay(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = Create("ScreenGui", {
		Name = "CombatFx",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	-- Never a tap target: Active stays false, so every input falls through to the HUD beneath.
	local banner = Create("Frame", {
		Name = "Banner",
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, Theme.COMBAT_BANNER_TOP_FRACTION),
		Size = UDim2.fromOffset(Theme.COMBAT_BANNER_WIDTH, Theme.COMBAT_BANNER_HEIGHT),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = Theme.ZINDEX_CARD,
		Parent = screenGui,
	}) :: Frame
	bannerScale = Create("UIScale", { Parent = banner }) :: UIScale
	-- The title is scaled to its frame: at its design size wherever that fits, smaller for a
	-- long camp name or a narrow frame, so it never runs out of the frame over the HUD.
	local title = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_BANNER_TEXT + Theme.SCREEN_MARGIN),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_BANNER_TEXT,
		TextColor3 = Theme.COLOR_TEXT,
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = banner,
	}) :: TextLabel
	Create("UITextSizeConstraint", {
		MinTextSize = Theme.COMBAT_BANNER_MIN_TEXT,
		MaxTextSize = Theme.COMBAT_BANNER_TEXT,
		Parent = title,
	})
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = title,
	})
	bannerTitle = title
	bannerSub = Create("TextLabel", {
		Name = "Sub",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, Theme.COMBAT_BANNER_TEXT + Theme.SCREEN_MARGIN),
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_BANNER_SUB_TEXT + Theme.SCREEN_MARGIN),
		Font = Theme.FONT,
		TextSize = Theme.COMBAT_BANNER_SUB_TEXT,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = banner,
	}) :: TextLabel
	bannerFrame = banner
	applyBannerLayout()
end

function CombatFxController.Init(): ()
	combatConfig = Catalog.GetCombatConfig()
end

function CombatFxController.Start(): ()
	task.spawn(function()
		buildOverlay()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local combatFx =
			remotes:WaitForChild("CombatFx", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if combatFx == nil then
			warn("[CombatFxController] CombatFx missing — combat feedback is disabled")
			return
		end
		table.insert(connections, combatFx.OnClientEvent:Connect(onCombatFx))
	end)
end

-- L1 fix round, item 5. The host's frame for the banner, in px of the viewport (this overlay
-- ignores the top-bar inset): `scale` is the HUD's UI scale, `centreX` and `top` where the
-- banner's top centre goes, `width` the most it may take. The mission HUD keeps it clear of
-- the run header's column on a short landscape screen.
function CombatFxController.SetBannerLayout(
	scale: number,
	centreX: number,
	top: number,
	width: number
): ()
	if scale <= 0 then
		return
	end
	bannerLayout = { scale = scale, centreX = centreX, top = top, width = math.max(width, 0) }
	applyBannerLayout()
end

-- C2 personal notices (your Mentor Valor, a Studio lever's line) go to the HUD toast only;
-- they are not wave events, so they never take the banner.
function CombatFxController.SetToastHandler(handler: (string) -> ()): ()
	onToast = handler
end

function CombatFxController.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	CampFx.Destroy()
end

return CombatFxController
