--!strict
-- Combat feedback for the Expeditions place (C1 contract, docs/INTERFACES.md "Combat
-- client"). Everything here is presentation of something the server already decided: it
-- consumes the per-frame `CombatFx` batch and the two enemy attributes (`Attacking`,
-- `Dead`) and turns them into damage numbers, flashes, banners, a vignette and sound. It
-- never reads an HP, never decides a kill and never sends a remote.
--
-- floatText / flashHighlight / burst are copies of PlotVisualsController.luau (:497 / :546
-- / :357) adapted to a world position instead of a building instance, because the two
-- client trees never require across each other. Dedupe is a follow-up (see the report).
--
-- Two deliberate deviations from the contract's wording, both forced by replication:
--  * Hitstop is applied to the *attacker's* swing (WeaponController.Hitstop) plus a camera
--    kick, not to the enemy's rig. Enemy roots are owned by the server (SetNetworkOwner
--    nil) and their joints are tweened server-side during a windup, so a local freeze would
--    be overwritten every replication packet and read as a stutter, not as impact.
--  * The knockback nudge is a decaying *offset* re-applied on top of whatever pivot the
--    server last replicated, so a correction mid-nudge blends instead of fighting.
--
-- Reduce motion (Theme.reducedMotion: touch or low graphics, spec section 10) drops
-- particles, the camera kick, the knockback nudge and the ability ring; the text, the
-- banners and the sounds always play, because they carry information.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))

local ENEMIES_FOLDER = "Enemies"
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local ATTACKING_ATTRIBUTE = "Attacking"
local DEAD_ATTRIBUTE = "Dead"
local CAMERA_BIND_NAME = "CombatCameraKick"
-- Fallbacks for a build with no Combat.json: the feature still renders, just untuned.
local DEFAULT_HITSTOP = 0.05
local DEFAULT_CAMERA_KICK = 0.6
local DEFAULT_DAMAGE_SECONDS = 0.8
local DEFAULT_BANNER_SECONDS = 2
local DEFAULT_LOW_HP_FRACTION = 0.3
local DEFAULT_CORPSE_SECONDS = 0.6

type EnemyFx = {
	model: Model,
	highlight: Highlight,
	connections: { RBXScriptConnection },
	-- Sticky while the Attacking attribute is true; a hit flash rides over it and restores
	-- it on the way out, so a hit during a windup never clears the tell.
	tell: boolean,
	flash: Tween?,
}

local CombatFxController = {}

local combatConfig: Types.CombatConfig? = nil
local materialName = ""
local activeNumbers = 0
local cameraKickPitch = 0
local cameraKickYaw = 0
local lowHpActive = false
local vignetteRoot: Frame? = nil
local vignetteBars: { Frame } = {}
local bannerFrame: Frame? = nil
local bannerTitle: TextLabel? = nil
local bannerSub: TextLabel? = nil
local hurtFlash: Frame? = nil
local bannerToken = 0
local vignetteToken = 0
-- One record per live enemy. The Highlight is POOLED: Roblox renders only about 31
-- Highlights at once, and a whirlwind into a merged wave used to create one per hit on top
-- of one per windup, so flashes and attack tells were silently dropped exactly when the
-- screen was busiest. One instance per model (at most director.maxAlive) drives both.
local enemyFx: { [Instance]: EnemyFx } = {}
-- Hit fx name an enemy by id; a map beats re-scanning the folder for every number.
local enemiesById: { [number]: Model } = {}
local connections: { RBXScriptConnection } = {}
local onBanner: ((string) -> ())? = nil

local function feedback(): Types.CombatFeedbackConfig?
	local cfg = combatConfig
	return if cfg ~= nil then cfg.feedback else nil
end

local function hitstopSeconds(): number
	local fb = feedback()
	return if fb ~= nil then fb.hitstopSeconds else DEFAULT_HITSTOP
end

local function cameraKickDegrees(): number
	local fb = feedback()
	return if fb ~= nil then fb.cameraKickDegrees else DEFAULT_CAMERA_KICK
end

local function damageNumberSeconds(): number
	local fb = feedback()
	return if fb ~= nil then fb.damageNumberSeconds else DEFAULT_DAMAGE_SECONDS
end

local function bannerSeconds(): number
	local fb = feedback()
	return if fb ~= nil then fb.bannerSeconds else DEFAULT_BANNER_SECONDS
end

local function lowHpFraction(): number
	local fb = feedback()
	return if fb ~= nil then fb.lowHpFraction else DEFAULT_LOW_HP_FRACTION
end

local function corpseSeconds(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.player.corpseSeconds else DEFAULT_CORPSE_SECONDS
end

local function enemyModel(enemyId: number): Model?
	local model: Model? = enemiesById[enemyId]
	-- The map is fed by watchEnemy / forgetEnemy; a model destroyed between the server's
	-- fx batch and this frame is simply gone, which is not an error.
	if model ~= nil and model.Parent == nil then
		enemiesById[enemyId] = nil
		return nil
	end
	return model
end

-- COPY of PlotVisualsController.burst (:357): a one-shot emitter that destroys itself.
local function burst(origin: Instance, count: number, color: Color3): ()
	if Theme.reducedMotion then
		return
	end
	local emitter = Create("ParticleEmitter", {
		Name = "FxBurst",
		Rate = 0,
		Lifetime = NumberRange.new(Theme.PARTICLE_LIFETIME_MIN, Theme.PARTICLE_LIFETIME_MAX),
		Speed = NumberRange.new(Theme.PARTICLE_SPEED_MIN, Theme.PARTICLE_SPEED_MAX),
		SpreadAngle = Vector2.new(Theme.PARTICLE_SPREAD, Theme.PARTICLE_SPREAD),
		Size = NumberSequence.new(Theme.PARTICLE_SIZE, 0),
		Color = ColorSequence.new(color),
		Parent = origin,
	}) :: ParticleEmitter
	emitter:Emit(count)
	task.delay(Theme.PARTICLE_LIFETIME_MAX, function()
		emitter:Destroy()
	end)
end

-- An anchor for a BillboardGui / emitter at a bare world position. Terrain is a BasePart,
-- so an Attachment under it is the cheapest legal adornee that needs no part of our own.
local function worldAnchor(position: Vector3): Attachment
	return Create("Attachment", {
		Name = "FxAnchor",
		WorldPosition = position,
		Parent = Workspace.Terrain,
	}) :: Attachment
end

-- COPY of PlotVisualsController.floatText (:497), re-based on a world position: the fx
-- payload carries one, and an enemy that dies the same frame has no instance left to adorn.
local function floatText(position: Vector3, text: string, color: Color3, large: boolean): ()
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil or activeNumbers >= Theme.COMBAT_DAMAGE_MAX_ACTIVE then
		return -- a merged wave lands dozens of hits a frame; the cap keeps the frame budget
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
		TextSize = if large
			then Theme.COMBAT_DAMAGE_FINISHER_TEXT_SIZE
			else Theme.COMBAT_DAMAGE_TEXT_SIZE,
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

-- Resting state of a pooled Highlight: the attack tell when the enemy is winding up,
-- disabled otherwise. Never called while a hit flash owns the instance.
local function restHighlight(entry: EnemyFx): ()
	local highlight = entry.highlight
	if entry.tell then
		highlight.FillColor = Theme.COLOR_ERROR
		highlight.OutlineColor = Theme.COLOR_ERROR
		highlight.FillTransparency = Theme.COMBAT_TELL_HIGHLIGHT_FILL
		highlight.OutlineTransparency = 0
		highlight.Enabled = true
	else
		highlight.Enabled = false
	end
end

-- Adapted from PlotVisualsController.flashHighlight (:546): the same tween, but against
-- the enemy's own pooled Highlight instead of a fresh instance per call.
local function flashEnemy(entry: EnemyFx, color: Color3, seconds: number): ()
	local previous = entry.flash
	if previous ~= nil then
		previous:Cancel()
	end
	local highlight = entry.highlight
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = Theme.COMBAT_HIT_HIGHLIGHT_FILL
	highlight.OutlineTransparency = 0
	highlight.Enabled = true
	local tween = TweenService:Create(
		highlight,
		Motion.Info(seconds),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	)
	entry.flash = tween
	tween.Completed:Once(function()
		if entry.flash ~= tween then
			return -- a newer flash took the instance over
		end
		entry.flash = nil
		restHighlight(entry)
	end)
	tween:Play()
end

local function kickCamera(strength: number): ()
	if Theme.reducedMotion then
		return
	end
	local degrees = cameraKickDegrees() * strength
	cameraKickPitch += degrees
	cameraKickYaw += degrees * (if math.random() < 0.5 then -0.5 else 0.5)
end

-- A decaying offset applied after the default camera update, so the player keeps full
-- control of the camera while the kick rides on top of it.
local function updateCameraKick(deltaTime: number): ()
	if cameraKickPitch == 0 and cameraKickYaw == 0 then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		cameraKickPitch = 0
		cameraKickYaw = 0
		return
	end
	camera.CFrame = camera.CFrame
		* CFrame.Angles(math.rad(cameraKickPitch), math.rad(cameraKickYaw), 0)
	local decay = math.exp(-Theme.COMBAT_CAMERA_KICK_DECAY * deltaTime)
	cameraKickPitch *= decay
	cameraKickYaw *= decay
	if math.abs(cameraKickPitch) < 0.01 and math.abs(cameraKickYaw) < 0.01 then
		cameraKickPitch = 0
		cameraKickYaw = 0
	end
end

-- Client-only shove. The offset is re-applied every frame on top of the pivot the server
-- last sent and decays to zero, so replication corrects the enemy's real position the whole
-- time and the nudge simply fades out of the render.
local function nudge(model: Model, direction: Vector3): ()
	if Theme.reducedMotion or direction.Magnitude <= 0 then
		return
	end
	local seconds = Theme.COMBAT_KNOCKBACK_SECONDS
	local unit = direction.Unit * Theme.COMBAT_KNOCKBACK_STUDS
	local startedAt = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function(deltaTime: number)
		local alpha = (os.clock() - startedAt) / seconds
		if alpha >= 1 or model.Parent == nil then
			if connection ~= nil then
				connection:Disconnect()
			end
			return
		end
		model:PivotTo(model:GetPivot() + unit * (1 - alpha) * (deltaTime / seconds))
	end)
end

local function dissolve(model: Model): ()
	local seconds = corpseSeconds()
	local info = Motion.Info(seconds)
	for _, descendant in model:GetDescendants() do
		-- Parts and decals share the property name, so one tween goal covers both.
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			TweenService:Create(descendant, info, { Transparency = 1 }):Play()
		end
	end
end

local function setTell(entry: EnemyFx, attacking: boolean): ()
	if entry.tell == attacking then
		return
	end
	entry.tell = attacking
	if entry.flash == nil then
		restHighlight(entry) -- a live flash restores the new resting state when it ends
	end
end

local function forgetEnemy(model: Instance): ()
	local entry: EnemyFx? = enemyFx[model]
	enemyFx[model] = nil
	if entry == nil then
		return
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	local flash = entry.flash
	if flash ~= nil then
		flash:Cancel()
	end
	entry.highlight:Destroy()
	local id = model:GetAttribute(ENEMY_ID_ATTRIBUTE)
	if typeof(id) == "number" and enemiesById[id] == model then
		enemiesById[id] = nil
	end
end

local function watchEnemy(child: Instance): ()
	if not child:IsA("Model") or enemyFx[child] ~= nil then
		return
	end
	local model = child
	local entry: EnemyFx = {
		model = model,
		-- Created disabled: one pooled instance per enemy, reused by every hit flash and
		-- every windup tell for as long as the rig lives.
		highlight = Create("Highlight", {
			Name = "FxHighlight",
			FillColor = Theme.COLOR_ERROR,
			OutlineColor = Theme.COLOR_ERROR,
			FillTransparency = 1,
			OutlineTransparency = 1,
			Enabled = false,
			Parent = model,
		}) :: Highlight,
		connections = {},
		tell = false,
		flash = nil,
	}
	local function indexById(): ()
		local id = model:GetAttribute(ENEMY_ID_ATTRIBUTE)
		if typeof(id) == "number" then
			enemiesById[id] = model
		end
	end
	entry.connections = {
		model:GetAttributeChangedSignal(ATTACKING_ATTRIBUTE):Connect(function()
			setTell(entry, model:GetAttribute(ATTACKING_ATTRIBUTE) == true)
		end),
		model:GetAttributeChangedSignal(DEAD_ATTRIBUTE):Connect(function()
			if model:GetAttribute(DEAD_ATTRIBUTE) == true then
				setTell(entry, false)
				dissolve(model)
			end
		end),
		-- EnemyService may parent the rig a frame before it stamps the id.
		model:GetAttributeChangedSignal(ENEMY_ID_ATTRIBUTE):Connect(indexById),
	}
	enemyFx[model] = entry
	indexById()
	if model:GetAttribute(ATTACKING_ATTRIBUTE) == true then
		setTell(entry, true)
	end
end

local function watchEnemies(): ()
	task.spawn(function()
		local folder = Workspace:WaitForChild(ENEMIES_FOLDER, Theme.COMBAT_ARENA_WAIT_SECONDS)
		if folder == nil then
			return -- no arena in this session (safe mode); nothing to watch
		end
		for _, child in folder:GetChildren() do
			watchEnemy(child)
		end
		table.insert(connections, folder.ChildAdded:Connect(watchEnemy))
		table.insert(connections, folder.ChildRemoved:Connect(forgetEnemy))
	end)
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
	local handler = onBanner
	if handler ~= nil then
		handler(title)
	end
end

local function setVignetteTransparency(transparency: number, seconds: number?): ()
	for _, bar in vignetteBars do
		if seconds == nil then
			bar.BackgroundTransparency = transparency
		else
			TweenService
				:Create(bar, Motion.Info(seconds), { BackgroundTransparency = transparency })
				:Play()
		end
	end
end

-- Slow in-and-out breath while the local HP sits under feedback.lowHpFraction. Reduce
-- motion keeps the vignette but drops the pulse (Motion halves every leg anyway).
local function pulseVignette(): ()
	if not lowHpActive then
		return
	end
	vignetteToken += 1
	local token = vignetteToken
	task.spawn(function()
		local pulse = Theme.COMBAT_VIGNETTE_PULSE_SECONDS
		while token == vignetteToken and lowHpActive do
			setVignetteTransparency(1, pulse)
			task.wait(Motion.Seconds(pulse))
			if token ~= vignetteToken or not lowHpActive then
				break
			end
			setVignetteTransparency(Theme.COMBAT_VIGNETTE_TRANSPARENCY, pulse)
			task.wait(Motion.Seconds(pulse))
		end
	end)
end

local function flashHurt(): ()
	local flash = hurtFlash
	if flash == nil then
		return
	end
	flash.BackgroundTransparency = Theme.COMBAT_HURT_FLASH_TRANSPARENCY
	TweenService
		:Create(flash, Motion.Info(Theme.COMBAT_HURT_FLASH_SECONDS), { BackgroundTransparency = 1 })
		:Play()
end

local function abilityRing(position: Vector3, radius: number): ()
	if Theme.reducedMotion then
		return
	end
	local part = Create("Part", {
		Name = "FxAbilityRing",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = Theme.COLOR_ACCENT_ALT,
		Transparency = 0.4,
		-- A Cylinder's length runs along X, so it is laid flat by a quarter turn on Z.
		Size = Vector3.new(Theme.COMBAT_ABILITY_RING_HEIGHT, 1, 1),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = Workspace,
	}) :: Part
	local tween = TweenService:Create(part, Motion.Info(Theme.COMBAT_ABILITY_RING_SECONDS), {
		Size = Vector3.new(Theme.COMBAT_ABILITY_RING_HEIGHT, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		part:Destroy()
	end)
	tween:Play()
end

local function localUserId(): number
	return Players.LocalPlayer.UserId
end

-- The camera stands in for "where the player is": the local root can be missing for a
-- frame after a respawn, and a knockback only needs a direction.
local function camera(): Camera
	return Workspace.CurrentCamera or Workspace:WaitForChild("Camera") :: Camera
end

local function onHit(fx: { [string]: any }): ()
	local position = fx.position
	local amount = fx.amount
	if typeof(position) ~= "Vector3" or typeof(amount) ~= "number" then
		return
	end
	local mine = fx.byUserId == localUserId()
	local finisher = fx.finisher == true
	floatText(
		position,
		Format.Cash(amount),
		if finisher then Theme.COLOR_HIGHLIGHT else Theme.COLOR_TEXT,
		finisher
	)
	local model = if typeof(fx.enemyId) == "number" then enemyModel(fx.enemyId) else nil
	local entry: EnemyFx? = if model ~= nil then enemyFx[model] else nil
	if entry ~= nil then
		flashEnemy(entry, Theme.COLOR_ERROR, Theme.COMBAT_HIT_HIGHLIGHT_SECONDS)
	end
	if model ~= nil and finisher and mine then
		-- Away from the player who landed it, which is what a finisher looks like.
		nudge(model, position - camera().CFrame.Position)
	end
	if not mine then
		return -- another player's hit is worth a number and a flash, nothing more
	end
	SoundController.Play("enemyHit")
	WeaponController.Hitstop(hitstopSeconds())
	kickCamera(if finisher then 1.6 else 1)
end

local function onKill(fx: { [string]: any }): ()
	local position = fx.position
	if typeof(position) ~= "Vector3" then
		return
	end
	SoundController.Play("enemyDeath")
	if fx.byUserId ~= localUserId() then
		return
	end
	local cash = if typeof(fx.cash) == "number" then fx.cash else 0
	local materials = if typeof(fx.materials) == "number" then fx.materials else 0
	local text = "+$" .. Format.Cash(cash)
	if materials > 0 then
		text ..= " · +" .. Format.Cash(materials) .. " " .. materialName
	end
	floatText(position, text, Theme.COLOR_ACCENT, false)
	local anchor = worldAnchor(position)
	burst(anchor, Theme.COMBAT_KILL_PARTICLES, Theme.COLOR_ACCENT)
	task.delay(Theme.PARTICLE_LIFETIME_MAX, function()
		anchor:Destroy()
	end)
end

local function onPlayerHit(fx: { [string]: any }): ()
	if fx.userId ~= localUserId() then
		return
	end
	SoundController.Play("playerHit")
	flashHurt()
	kickCamera(1)
end

local function onAbility(fx: { [string]: any }): ()
	local position = fx.position
	if typeof(position) ~= "Vector3" then
		return
	end
	SoundController.Play("abilityCast")
	local radius = fx.radius
	if typeof(radius) == "number" and radius > 0 then
		abilityRing(position, radius)
	end
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

local function onPlayerDown(fx: { [string]: any }): ()
	if fx.userId ~= localUserId() then
		return
	end
	SoundController.Play("playerDown")
	local respawnIn = fx.respawnIn
	local sub = if typeof(respawnIn) == "number" and respawnIn > 0
		then "Back up in " .. Format.Duration(respawnIn)
		else "No one left standing"
	showBanner("You're down", sub, bannerSeconds())
end

local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" or typeof(fx.kind) ~= "string" then
		return
	end
	local payload = fx :: { [string]: any }
	local kind = payload.kind
	if kind == "hit" then
		onHit(payload)
	elseif kind == "kill" then
		onKill(payload)
	elseif kind == "playerHit" then
		onPlayerHit(payload)
	elseif kind == "ability" then
		onAbility(payload)
	elseif kind == "wave" then
		onWave(payload)
	elseif kind == "bossDown" then
		onBossDown(payload)
	elseif kind == "playerDown" then
		onPlayerDown(payload)
	end
	-- "refused" is deliberately silent: it answers an input the player already saw fail
	-- (a swing inside its own window), and a toast per mistimed tap would be noise.
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

	-- The vignette and the hurt flash must never eat a tap: Active stays false and neither
	-- holds a button, so every input falls through to the world and to the HUD beneath.
	local root = Create("Frame", {
		Name = "Vignette",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screenGui,
	}) :: Frame
	-- Four edge bars, each fading inward, stand in for a vignette image: the project owns
	-- no image asset, and four solid frames cost far less than a full-screen CanvasGroup.
	local thickness = Theme.COMBAT_VIGNETTE_THICKNESS
	local edges: {
		{
			name: string,
			size: UDim2,
			position: UDim2,
			anchor: Vector2,
			rotation: number,
			flip: boolean,
		}
	} =
		{
			{
				name = "Left",
				size = UDim2.new(0, thickness, 1, 0),
				position = UDim2.fromScale(0, 0),
				anchor = Vector2.new(0, 0),
				rotation = 0,
				flip = false,
			},
			{
				name = "Right",
				size = UDim2.new(0, thickness, 1, 0),
				position = UDim2.fromScale(1, 0),
				anchor = Vector2.new(1, 0),
				rotation = 0,
				flip = true,
			},
			{
				name = "Top",
				size = UDim2.new(1, 0, 0, thickness),
				position = UDim2.fromScale(0, 0),
				anchor = Vector2.new(0, 0),
				rotation = 90,
				flip = false,
			},
			{
				name = "Bottom",
				size = UDim2.new(1, 0, 0, thickness),
				position = UDim2.fromScale(0, 1),
				anchor = Vector2.new(0, 1),
				rotation = 90,
				flip = true,
			},
		}
	for _, edge in edges do
		local bar = Create("Frame", {
			Name = edge.name,
			Active = false,
			AnchorPoint = edge.anchor,
			Position = edge.position,
			Size = edge.size,
			BackgroundColor3 = Theme.COLOR_ERROR,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = root,
		}) :: Frame
		Create("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, if edge.flip then 1 else 0),
				NumberSequenceKeypoint.new(1, if edge.flip then 0 else 1),
			}),
			Parent = bar,
		})
		table.insert(vignetteBars, bar)
	end
	vignetteRoot = root

	hurtFlash = Create("Frame", {
		Name = "Hurt",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.COLOR_ERROR,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = screenGui,
	}) :: Frame

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
	bannerTitle = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_BANNER_TEXT + Theme.SCREEN_MARGIN),
		Font = Theme.FONT_BOLD,
		TextSize = Theme.COMBAT_BANNER_TEXT,
		TextColor3 = Theme.COLOR_TEXT,
		TextScaled = false,
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = banner,
	}) :: TextLabel
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = bannerTitle,
	})
	bannerSub = Create("TextLabel", {
		Name = "Sub",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, Theme.COMBAT_BANNER_TEXT + Theme.SCREEN_MARGIN),
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_BANNER_SUB_TEXT + Theme.SCREEN_MARGIN),
		Font = Theme.FONT,
		TextSize = Theme.COMBAT_BANNER_SUB_TEXT,
		TextColor3 = Theme.COLOR_TEXT_DIM,
		Text = "",
		ZIndex = Theme.ZINDEX_CARD,
		Parent = banner,
	}) :: TextLabel
	bannerFrame = banner
end

function CombatFxController.Init(): ()
	combatConfig = Catalog.GetCombatConfig()
end

function CombatFxController.Start(): ()
	task.spawn(function()
		buildOverlay()
		watchEnemies()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local combatFx =
			remotes:WaitForChild("CombatFx", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if combatFx == nil then
			warn("[CombatFxController] CombatFx missing — combat feedback is disabled")
			return
		end
		table.insert(connections, combatFx.OnClientEvent:Connect(onCombatFx))
	end)
	RunService:BindToRenderStep(
		CAMERA_BIND_NAME,
		Enum.RenderPriority.Camera.Value + 1,
		updateCameraKick
	)
end

-- The mission's material name, so a kill can read "+2 Timber" instead of "+2".
function CombatFxController.SetMaterial(name: string): ()
	materialName = name
end

-- Pushed by CombatUIController from the local Humanoid: the vignette is a health readout,
-- and the server never sends the local HP as an fx.
function CombatFxController.SetHealth(health: number, maxHealth: number): ()
	local root = vignetteRoot
	if root == nil then
		return
	end
	local low = maxHealth > 0 and health > 0 and health / maxHealth <= lowHpFraction()
	if low == lowHpActive then
		return
	end
	lowHpActive = low
	vignetteToken += 1
	if low then
		root.Visible = true
		setVignetteTransparency(Theme.COMBAT_VIGNETTE_TRANSPARENCY, nil)
		SoundController.Play("lowHp")
		pulseVignette()
	else
		root.Visible = false
		setVignetteTransparency(1, nil)
	end
end

-- CombatUIController mirrors every banner into the HUD's wave line, so a player who missed
-- the banner still sees what the director did.
function CombatFxController.SetBannerHandler(handler: (string) -> ()): ()
	onBanner = handler
end

function CombatFxController.Destroy(): ()
	RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for model in enemyFx do
		forgetEnemy(model)
	end
	table.clear(enemiesById)
end

return CombatFxController
