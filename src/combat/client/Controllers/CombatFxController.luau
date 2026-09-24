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
-- C2.5 impact: sparks fly along `CombatFxHit.direction`, the shoulder camera shakes
-- (`feel.shakeLight` per hit, `shakeHeavy` for a finisher or a hit taken), the HUD flashes a
-- hit marker, and a hit from a shot still in the air is presented when the shot arrives
-- (WeaponController.ArrivalDelay). Telegraphs draw BEFORE the blow: a glow and a "!" on the
-- striker, a filling red ring for a slam, a filling red lane for a charge. Their fill is timed
-- by `seconds` with a fixed TweenInfo, never Motion, because reduce motion halving the fill
-- would lie about when the hit lands. A kill ragdolls server-side for `feel.ragdollSeconds`;
-- the corpse fades during its last `player.corpseSeconds`.
--
-- Device gating (spec section 10, living-city ruling): Theme.reducedMotion is true on every
-- touch device, so it only shrinks things (fewer sparks, a smaller shake, no nudge, rings
-- that fade without growing). Particles and lights drop on Theme.lowEndDevice. Text,
-- banners, telegraphs and sounds always play, because they carry information.
--
-- C2 co-op fx follow a finer split, because reducedMotion is true on EVERY touch device and
-- a party buff is information, not decoration: the rally / war cry ring still shows on a
-- phone (at full size, fading, no growth) and drops only on Theme.lowEndDevice; the pulse on
-- each target is a short Highlight flash, never particles.

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
local CombatHud = require(uiFolder:WaitForChild("CombatHud"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))

local ENEMIES_FOLDER = "Enemies"
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local ATTACKING_ATTRIBUTE = "Attacking"
local DEAD_ATTRIBUTE = "Dead"
local TELEGRAPH_NAME = "FxTelegraph"
-- Fallbacks for a build with no Combat.json: the feature still renders, just untuned.
local DEFAULT_HITSTOP = 0.05
local DEFAULT_CAMERA_KICK = 0.6
local DEFAULT_DAMAGE_SECONDS = 0.8
local DEFAULT_BANNER_SECONDS = 2
local DEFAULT_LOW_HP_FRACTION = 0.3
local DEFAULT_CORPSE_SECONDS = 0.6
local DEFAULT_FEEL: Types.CombatFeelConfig = {
	shakeLight = 0.25,
	shakeHeavy = 0.8,
	hitMarkerSeconds = 0.12,
	trailSeconds = 0.15,
	arrowSpeed = 180,
	ragdollImpulse = 35,
	ragdollSeconds = 1.2,
	hitSparkCount = 6,
}
local DEFAULT_CHARGE_DISTANCE = 26
-- The HUD's waiting banner words, so a refused tap and the banner agree.
local WAITING_TEXT = CombatHud.WAITING_TEXT

type EnemyFx = {
	model: Model,
	highlight: Highlight,
	connections: { RBXScriptConnection },
	-- Sticky while the Attacking attribute is true; a hit flash rides over it and restores
	-- it on the way out, so a hit during a windup never clears the tell.
	tell: boolean,
	-- C2.5: true from a strike telegraph until its blow lands; outranks the plain tell.
	telegraph: boolean,
	telegraphToken: number,
	-- The ring / lane / "!" of the live telegraphs, so a cancel or a death can clear them.
	visuals: { Instance },
	flash: Tween?,
}

local CombatFxController = {}

local combatConfig: Types.CombatConfig? = nil
local armoryConfig: Types.ArmoryConfig? = nil
local materialName = ""
local activeNumbers = 0
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
local onToast: ((string) -> ())? = nil
local onHitMarker: ((boolean) -> ())? = nil
-- userId -> display name from the last RunState party, so a buff can say who cast it
-- (bots have negative ids and no Player to ask).
local partyNames: { [number]: string } = {}
local lastWaitingToastAt = -math.huge

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

local function feel(): Types.CombatFeelConfig
	local cfg = combatConfig
	return if cfg ~= nil then cfg.feel else DEFAULT_FEEL
end

local function chargeDistance(): number
	local cfg = combatConfig
	return if cfg ~= nil then cfg.ai.chargeDistance else DEFAULT_CHARGE_DISTANCE
end

-- Particle counts shrink on touch (reduce motion) and vanish on low-end devices.
local function particleCount(count: number): number
	if Theme.lowEndDevice then
		return 0
	end
	return if Theme.reducedMotion
		then math.max(math.floor(count * Theme.REDUCED_MOTION_FACTOR), 1)
		else count
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
-- C2.5 gates it on lowEndDevice (via particleCount) instead of reducedMotion.
local function burst(origin: Instance, count: number, color: Color3): ()
	local emitted = particleCount(count)
	if emitted <= 0 then
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
	emitter:Emit(emitted)
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
	if entry.telegraph then
		-- The strike glow: brighter and warmer than the plain tell, so "about to hit you"
		-- reads apart from "busy attacking someone".
		highlight.FillColor = Theme.COMBAT_TELEGRAPH_COLOR
		highlight.OutlineColor = Theme.COMBAT_TELEGRAPH_COLOR
		highlight.FillTransparency = Theme.COMBAT_TELEGRAPH_HIGHLIGHT_FILL
		highlight.OutlineTransparency = 0
		highlight.Enabled = true
	elseif entry.tell then
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

-- The kick and the shake live in CameraController, which rebuilds the view every frame, so
-- neither can drift the camera the way a kick written over the default camera did.
local function impactCamera(strength: number, shake: number): ()
	CameraController.Kick(cameraKickDegrees() * strength)
	CameraController.Shake(shake)
end

-- Sparks spraying out of the enemy along the blow. The emitter's Top points along the hit
-- direction, so the spray reads as coming off the far side of the target.
local function sparks(position: Vector3, direction: Vector3, heavy: boolean): ()
	local count = particleCount(feel().hitSparkCount * (if heavy then 2 else 1))
	if count <= 0 or direction.Magnitude <= 0 then
		return
	end
	local unit = direction.Unit
	local anchor = Create("Attachment", {
		Name = "FxSparks",
		WorldCFrame = CFrame.lookAlong(position - unit * Theme.COMBAT_SPARK_SURFACE_OFFSET, unit)
			* CFrame.Angles(-math.pi / 2, 0, 0),
		Parent = Workspace.Terrain,
	}) :: Attachment
	local emitter = Create("ParticleEmitter", {
		Name = "Sparks",
		Rate = 0,
		EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(
			Theme.COMBAT_SPARK_LIFETIME_MIN,
			Theme.COMBAT_SPARK_LIFETIME_MAX
		),
		Speed = NumberRange.new(Theme.COMBAT_SPARK_SPEED_MIN, Theme.COMBAT_SPARK_SPEED_MAX),
		SpreadAngle = Vector2.new(Theme.COMBAT_SPARK_SPREAD, Theme.COMBAT_SPARK_SPREAD),
		Acceleration = Vector3.new(0, -Theme.COMBAT_SPARK_GRAVITY, 0),
		Drag = Theme.COMBAT_SPARK_DRAG,
		LightEmission = 1,
		Size = NumberSequence.new(Theme.COMBAT_SPARK_SIZE, 0),
		Color = ColorSequence.new(Theme.COLOR_TEXT, Theme.COLOR_HIGHLIGHT),
		Parent = anchor,
	}) :: ParticleEmitter
	emitter:Emit(count)
	task.delay(Theme.COMBAT_SPARK_LIFETIME_MAX, function()
		anchor:Destroy()
	end)
end

-- A quick bright pop where a kill landed: a neon ball that swells and fades.
local function killPop(position: Vector3): ()
	if Theme.lowEndDevice then
		return
	end
	local startSize = Theme.COMBAT_KILL_POP_START
	local ball = Create("Part", {
		Name = "FxKillPop",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Shape = Enum.PartType.Ball,
		Material = Enum.Material.Neon,
		Color = Theme.COLOR_HIGHLIGHT,
		Transparency = Theme.COMBAT_KILL_POP_TRANSPARENCY,
		Size = Vector3.one * startSize,
		CFrame = CFrame.new(position),
		Parent = Workspace,
	}) :: Part
	local tween = TweenService:Create(
		ball,
		Motion.Info(Theme.COMBAT_KILL_POP_SECONDS),
		{ Size = Vector3.one * Theme.COMBAT_KILL_POP_END, Transparency = 1 }
	)
	tween.Completed:Once(function()
		ball:Destroy()
	end)
	tween:Play()
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

-- The server ragdolls a kill for feel.ragdollSeconds and stamps `Dead` corpseSeconds before
-- it removes the body, so fading from the stamp shows the whole fall at full opacity.
local function dissolve(model: Model): ()
	local info = Motion.Info(corpseSeconds())
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

-- Glow the striker until its blow lands. The token drops a stale reset when a second
-- telegraph arrives before the first one's blow.
local function glowFor(entry: EnemyFx, seconds: number): ()
	entry.telegraphToken += 1
	local token = entry.telegraphToken
	entry.telegraph = true
	if entry.flash == nil then
		restHighlight(entry)
	end
	task.delay(seconds, function()
		if token ~= entry.telegraphToken then
			return
		end
		entry.telegraph = false
		if entry.flash == nil then
			restHighlight(entry)
		end
	end)
end

-- A cancelled windup (seconds = 0: stagger, stun) or a death drops the glow and every
-- ring, lane and "!" at once, so no telegraph promises a blow that will not come.
local function clearTelegraph(entry: EnemyFx): ()
	entry.telegraphToken += 1
	entry.telegraph = false
	if entry.flash == nil then
		restHighlight(entry)
	end
	for _, visual in entry.visuals do
		visual:Destroy()
	end
	table.clear(entry.visuals)
end

local function forgetEnemy(model: Instance): ()
	local entry: EnemyFx? = enemyFx[model]
	enemyFx[model] = nil
	if entry == nil then
		return
	end
	clearTelegraph(entry)
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
		telegraph = false,
		telegraphToken = 0,
		visuals = {},
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
				clearTelegraph(entry)
				setTell(entry, false)
				dissolve(model)
			end
		end),
		-- EnemyService may parent the rig a frame before it stamps the id.
		model:GetAttributeChangedSignal(ENEMY_ID_ATTRIBUTE):Connect(indexById),
	}
	-- `Dead` is stamped only near the end of the ragdoll, so the death itself clears first.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		table.insert(
			entry.connections,
			humanoid.Died:Connect(function()
				clearTelegraph(entry)
			end)
		)
	end
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

-- The ring an ability leaves at its centre. C2.5: shown on phones too (at full size, only
-- fading, like the party ring), and dropped on low-end devices only.
local function abilityRing(position: Vector3, radius: number): ()
	if Theme.lowEndDevice or radius <= 0 then
		return
	end
	local diameter = radius * 2
	local startDiameter = if Theme.reducedMotion then diameter else 1
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
		Transparency = Theme.COMBAT_ABILITY_RING_TRANSPARENCY,
		-- A Cylinder's length runs along X, so it is laid flat by a quarter turn on Z.
		Size = Vector3.new(Theme.COMBAT_ABILITY_RING_HEIGHT, startDiameter, startDiameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = Workspace,
	}) :: Part
	local tween = TweenService:Create(part, Motion.Info(Theme.COMBAT_ABILITY_RING_SECONDS), {
		Size = Vector3.new(Theme.COMBAT_ABILITY_RING_HEIGHT, diameter, diameter),
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

-- Telegraphs -----------------------------------------------------------------------------

-- The arena floor under a point. Slam positions are the boss's root, so the ring is dropped
-- to whatever the ray meets first below it, ignoring every rig and every fx part.
local function groundUnder(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = {}
	local enemies = Workspace:FindFirstChild(ENEMIES_FOLDER)
	if enemies ~= nil then
		table.insert(ignored, enemies)
	end
	for _, player in Players:GetPlayers() do
		local rig = player.Character
		if rig ~= nil then
			table.insert(ignored, rig)
		end
	end
	params.FilterDescendantsInstances = ignored
	local probe = Theme.COMBAT_TELEGRAPH_GROUND_PROBE
	local result = Workspace:Raycast(
		position + Vector3.new(0, probe * 0.5, 0),
		Vector3.new(0, -probe * 2, 0),
		params
	)
	if result ~= nil then
		return result.Position
	end
	return Vector3.new(position.X, Theme.COMBAT_TELEGRAPH_FLOOR_Y, position.Z)
end

local function telegraphPart(name: string, color: Color3, transparency: number): Part
	return Create("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = transparency,
		Size = Vector3.one,
	}) :: Part
end

-- The fill runs on a fixed TweenInfo over exactly `seconds`, never Motion: the moment it is
-- full IS the moment the blow lands, on every device.
local function fillOver(part: Part, seconds: number, goal: { [string]: any }): ()
	TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Linear), goal):Play()
end

-- Both parts vanish together shortly after the blow; the brief linger shows where it hit.
local function retire(folder: Instance, seconds: number): ()
	task.delay(seconds + Theme.COMBAT_TELEGRAPH_LINGER_SECONDS, function()
		folder:Destroy()
	end)
end

-- Slam: a faint disc at full radius (where it will hit) and a bright disc growing to meet
-- its edge (when it will hit).
local function slamRing(position: Vector3, radius: number, seconds: number, color: Color3): Instance
	local ground = groundUnder(position)
	local flat = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
	local height = Theme.COMBAT_TELEGRAPH_THICKNESS
	local diameter = radius * 2
	local folder = Create("Folder", { Name = TELEGRAPH_NAME, Parent = Workspace })
	local area = telegraphPart("Area", color, Theme.COMBAT_TELEGRAPH_AREA_TRANSPARENCY)
	area.Shape = Enum.PartType.Cylinder
	area.Size = Vector3.new(height, diameter, diameter)
	area.CFrame = flat + Vector3.new(0, Theme.COMBAT_TELEGRAPH_LIFT, 0)
	area.Parent = folder
	local fill = telegraphPart("Fill", color, Theme.COMBAT_TELEGRAPH_FILL_TRANSPARENCY)
	fill.Shape = Enum.PartType.Cylinder
	fill.Size =
		Vector3.new(height, Theme.COMBAT_TELEGRAPH_MIN_SIZE, Theme.COMBAT_TELEGRAPH_MIN_SIZE)
	fill.CFrame = flat + Vector3.new(0, Theme.COMBAT_TELEGRAPH_LIFT * 2, 0)
	fill.Parent = folder
	fillOver(fill, seconds, { Size = Vector3.new(height, diameter, diameter) })
	retire(folder, seconds)
	return folder
end

-- Charge: the lane the charger will run, drawn on the floor; a bright bar fills it from the
-- charger's end to the far end over `seconds`.
local function chargeLane(
	position: Vector3,
	direction: Vector3,
	halfWidth: number,
	seconds: number
): Instance?
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude <= 0 then
		return nil
	end
	local unit = flatDirection.Unit
	local length = chargeDistance()
	local width = halfWidth * 2
	local ground = groundUnder(position)
	local height = Theme.COMBAT_TELEGRAPH_THICKNESS
	local folder = Create("Folder", { Name = TELEGRAPH_NAME, Parent = Workspace })
	local lane = telegraphPart("Area", Theme.COLOR_ERROR, Theme.COMBAT_TELEGRAPH_AREA_TRANSPARENCY)
	lane.Size = Vector3.new(width, height, length)
	lane.CFrame = CFrame.lookAlong(ground + unit * (length * 0.5), unit)
		+ Vector3.new(0, Theme.COMBAT_TELEGRAPH_LIFT, 0)
	lane.Parent = folder
	local start = ground + Vector3.new(0, Theme.COMBAT_TELEGRAPH_LIFT * 2, 0)
	local fill = telegraphPart("Fill", Theme.COLOR_ERROR, Theme.COMBAT_TELEGRAPH_FILL_TRANSPARENCY)
	fill.Size = Vector3.new(width, height, Theme.COMBAT_TELEGRAPH_MIN_SIZE)
	fill.CFrame = CFrame.lookAlong(start, unit)
	fill.Parent = folder
	fillOver(fill, seconds, {
		Size = Vector3.new(width, height, length),
		CFrame = CFrame.lookAlong(start + unit * (length * 0.5), unit),
	})
	retire(folder, seconds)
	return folder
end

-- Strike: the striker glows and a "!" hangs over its head until the blow.
local function strikeMark(model: Model, seconds: number): Instance?
	local head = model:FindFirstChild("Head")
	local adornee: Instance? = if head ~= nil and head:IsA("BasePart")
		then head
		else model.PrimaryPart
	if adornee == nil then
		return nil
	end
	local gui = Create("BillboardGui", {
		Name = TELEGRAPH_NAME,
		Adornee = adornee,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(Theme.COMBAT_TELEGRAPH_MARK_SIZE, Theme.COMBAT_TELEGRAPH_MARK_SIZE),
		StudsOffsetWorldSpace = Vector3.new(0, Theme.COMBAT_TELEGRAPH_MARK_RISE, 0),
		Parent = adornee,
	}) :: BillboardGui
	local label = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.FONT_BOLD,
		TextScaled = true,
		TextColor3 = Theme.COMBAT_TELEGRAPH_COLOR,
		Text = "!",
		Parent = gui,
	}) :: TextLabel
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Parent = label,
	})
	task.delay(seconds, function()
		gui:Destroy()
	end)
	return gui
end

-- Summon (boss): a violet circle that fills around the boss while the adds are called.
local function summonCircle(position: Vector3, seconds: number): Instance
	return slamRing(
		position,
		Theme.COMBAT_TELEGRAPH_SUMMON_RADIUS,
		seconds,
		Theme.COMBAT_TELEGRAPH_SUMMON_COLOR
	)
end

local function onTelegraph(fx: { [string]: any }): ()
	local seconds = fx.seconds
	if typeof(seconds) ~= "number" then
		return
	end
	local model = if typeof(fx.enemyId) == "number" then enemyModel(fx.enemyId) else nil
	local entry: EnemyFx? = if model ~= nil then enemyFx[model] else nil
	if seconds <= 0 then
		-- The server's cancel: the windup was interrupted, so nothing is coming.
		if entry ~= nil then
			clearTelegraph(entry)
		end
		return
	end
	local position = fx.position
	local attack = fx.attack
	if typeof(position) ~= "Vector3" or typeof(attack) ~= "string" then
		return
	end
	if entry ~= nil then
		glowFor(entry, seconds)
	end
	local radius = if typeof(fx.radius) == "number" then fx.radius else nil
	local visual: Instance? = nil
	if attack == "slam" then
		visual = slamRing(
			position,
			radius or Theme.COMBAT_TELEGRAPH_DEFAULT_RADIUS,
			seconds,
			Theme.COLOR_ERROR
		)
	elseif attack == "charge" then
		local direction = fx.direction
		if typeof(direction) == "Vector3" then
			visual = chargeLane(
				position,
				direction,
				radius or Theme.COMBAT_TELEGRAPH_DEFAULT_HALF_WIDTH,
				seconds
			)
		end
	elseif attack == "summon" then
		visual = summonCircle(position, seconds)
	elseif model ~= nil then
		visual = strikeMark(model, seconds)
	end
	if entry ~= nil and visual ~= nil then
		-- Drop the ones that already retired on their own before remembering the new one.
		for index = #entry.visuals, 1, -1 do
			if entry.visuals[index].Parent == nil then
				table.remove(entry.visuals, index)
			end
		end
		table.insert(entry.visuals, visual)
	end
end

-- Hits and kills -------------------------------------------------------------------------

local function presentHit(fx: { [string]: any }, position: Vector3, amount: number): ()
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
	-- nil for damage-over-time ticks: a burn does not spark or shove.
	local direction: Vector3? = if typeof(fx.direction) == "Vector3" then fx.direction else nil
	if direction ~= nil then
		sparks(position, direction, finisher)
	end
	if model ~= nil and finisher and mine then
		-- Away from the player who landed it, which is what a finisher looks like.
		nudge(model, direction or (position - camera().CFrame.Position))
	end
	if not mine then
		return -- another player's hit is worth a number, a flash and sparks, nothing more
	end
	SoundController.Play("enemyHit")
	WeaponController.Hitstop(hitstopSeconds())
	local f = feel()
	if finisher then
		impactCamera(Theme.COMBAT_FINISHER_KICK_MULT, f.shakeHeavy)
	else
		impactCamera(1, f.shakeLight)
	end
	local marker = onHitMarker
	if marker ~= nil then
		marker(finisher)
	end
end

-- Presented at once, or when the local shot that caused it reaches the enemy.
local function afterArrival(fx: { [string]: any }, position: Vector3, present: () -> ()): ()
	local delaySeconds = if fx.byUserId == localUserId()
		then WeaponController.ArrivalDelay(position)
		else 0
	if delaySeconds > 0 then
		task.delay(delaySeconds, present)
	else
		present()
	end
end

local function onHit(fx: { [string]: any }): ()
	local position = fx.position
	local amount = fx.amount
	if typeof(position) ~= "Vector3" or typeof(amount) ~= "number" then
		return
	end
	afterArrival(fx, position, function()
		presentHit(fx, position, amount)
	end)
end

local function presentKill(fx: { [string]: any }, position: Vector3): ()
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
	killPop(position)
	local anchor = worldAnchor(position)
	burst(anchor, Theme.COMBAT_KILL_PARTICLES, Theme.COLOR_ACCENT)
	task.delay(Theme.PARTICLE_LIFETIME_MAX, function()
		anchor:Destroy()
	end)
	local marker = onHitMarker
	if marker ~= nil then
		marker(true)
	end
end

local function onKill(fx: { [string]: any }): ()
	local position = fx.position
	if typeof(position) ~= "Vector3" then
		return
	end
	afterArrival(fx, position, function()
		presentKill(fx, position)
	end)
end

local function onPlayerHit(fx: { [string]: any }): ()
	if fx.userId ~= localUserId() then
		return
	end
	SoundController.Play("playerHit")
	flashHurt()
	impactCamera(1, feel().shakeHeavy)
end

local function onAbility(fx: { [string]: any }): ()
	local position = fx.position
	if typeof(position) ~= "Vector3" then
		return
	end
	-- The caster already heard it on the key press (InputController), so only others play it.
	if fx.userId ~= localUserId() then
		SoundController.Play("abilityCast")
	end
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

local function toast(text: string): ()
	local handler = onToast
	if handler ~= nil then
		handler(text)
	end
end

local function nameOf(userId: number): string
	local known = partyNames[userId]
	if known ~= nil then
		return known
	end
	local player = Players:GetPlayerByUserId(userId)
	return if player ~= nil then player.DisplayName else "an ally"
end

local function onSwing(fx: { [string]: any }): ()
	local userId = fx.userId
	local step = fx.step
	if typeof(userId) ~= "number" or typeof(step) ~= "number" or userId == localUserId() then
		return
	end
	WeaponController.SwingOther(userId, math.clamp(math.floor(step), 1, 3))
end

-- Radius ring at the caster. Unlike abilityRing it survives reducedMotion (see the header):
-- on a touch device it appears at full size and only fades.
local function partyRing(position: Vector3, radius: number, color: Color3): ()
	if Theme.lowEndDevice or radius <= 0 then
		return
	end
	local diameter = radius * 2
	local startDiameter = if Theme.reducedMotion then diameter else 1
	local part = Create("Part", {
		Name = "FxPartyRing",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = Theme.COMBAT_PARTY_RING_TRANSPARENCY,
		Size = Vector3.new(Theme.COMBAT_ABILITY_RING_HEIGHT, startDiameter, startDiameter),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = Workspace,
	}) :: Part
	local tween = TweenService:Create(part, Motion.Info(Theme.COMBAT_PARTY_RING_SECONDS), {
		Size = Vector3.new(Theme.COMBAT_ABILITY_RING_HEIGHT, diameter, diameter),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		part:Destroy()
	end)
	tween:Play()
end

-- A short Highlight flash on an ally's character. At most coop.maxParty per cast, so a
-- fresh instance per pulse stays far below the engine's Highlight budget.
local function pulseCharacter(userId: number, color: Color3): ()
	local player = Players:GetPlayerByUserId(userId)
	local rig = if player ~= nil then player.Character else nil
	if rig == nil then
		return
	end
	local highlight = Create("Highlight", {
		Name = "FxPartyPulse",
		FillColor = color,
		OutlineColor = color,
		FillTransparency = Theme.COMBAT_PARTY_PULSE_FILL,
		OutlineTransparency = 0,
		DepthMode = Enum.HighlightDepthMode.Occluded,
		Parent = rig,
	}) :: Highlight
	local tween = TweenService:Create(
		highlight,
		Motion.Info(Theme.COMBAT_PARTY_PULSE_SECONDS),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	)
	tween.Completed:Once(function()
		highlight:Destroy()
	end)
	tween:Play()
end

local function onPartyEffect(fx: { [string]: any }): ()
	local position = fx.position
	local key = fx.key
	local casterId = fx.userId
	if typeof(position) ~= "Vector3" or typeof(key) ~= "string" or typeof(casterId) ~= "number" then
		return
	end
	-- The effect's kind comes from the shared Armory config; the key is the fallback so an
	-- unknown key still reads as something rather than nothing.
	local cfg = armoryConfig
	local def = if cfg ~= nil then cfg.partyEffects[key] else nil
	local kind = if def ~= nil then def.kind else key
	local rally = kind == "rally"
	local color = if rally then Theme.COLOR_ACCENT else Theme.COLOR_HIGHLIGHT
	local radius = fx.radius
	partyRing(position, if typeof(radius) == "number" then radius else 0, color)

	local targets = fx.targetIds
	if typeof(targets) ~= "table" then
		return
	end
	local me = localUserId()
	for _, targetId in targets :: { any } do
		if typeof(targetId) ~= "number" then
			continue
		end
		pulseCharacter(targetId, color)
		if targetId == me then
			SoundController.Play(if rally then "partyRally" else "partyWarcry")
			toast((if rally then "Rally from " else "War cry from ") .. nameOf(casterId))
		end
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
		floatText(head.Position, text, Theme.COLOR_HIGHLIGHT, true)
	end
end

-- Only "waiting" speaks: the other refusals answer an input the player already saw fail (a
-- swing inside its own window), but a waiting player tapping Attack needs to know why
-- nothing happens. Throttled, because every tap of a held button is refused again.
local function onRefused(fx: { [string]: any }): ()
	if fx.reason ~= "waiting" then
		return
	end
	local now = os.clock()
	if now - lastWaitingToastAt < Theme.COMBAT_WAITING_TOAST_COOLDOWN then
		return
	end
	lastWaitingToastAt = now
	toast(WAITING_TEXT)
end

local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" or typeof(fx.kind) ~= "string" then
		return
	end
	local payload = fx :: { [string]: any }
	local kind = payload.kind
	if kind == "hit" then
		onHit(payload)
	elseif kind == "telegraph" then
		onTelegraph(payload)
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
	elseif kind == "swing" then
		onSwing(payload)
	elseif kind == "partyEffect" then
		onPartyEffect(payload)
	elseif kind == "mentor" then
		onMentor(payload)
	elseif kind == "refused" then
		onRefused(payload)
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
	armoryConfig = Catalog.GetArmoryConfig()
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

-- C2 personal notices (a buff landed on you, your Mentor Valor, a waiting refusal) go to
-- the HUD toast only; they are not wave events, so they never take the banner.
function CombatFxController.SetToastHandler(handler: (string) -> ()): ()
	onToast = handler
end

-- Pushed from every RunState so a caster is named even when it is a debug bot.
function CombatFxController.SetParty(party: { Types.PartyMember }): ()
	table.clear(partyNames)
	for _, member in party do
		if
			typeof(member) == "table"
			and typeof(member.userId) == "number"
			and typeof(member.name) == "string"
		then
			partyNames[member.userId] = member.name
		end
	end
end

-- C2.5: the HUD's hit marker. `heavy` is a finisher or a kill.
function CombatFxController.SetHitMarkerHandler(handler: (heavy: boolean) -> ()): ()
	onHitMarker = handler
end

function CombatFxController.Destroy(): ()
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
