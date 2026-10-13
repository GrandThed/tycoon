--!strict
-- Owns the Expeditions place HUD (C1 contract, docs/INTERFACES.md "Combat client"). Same
-- shape as the hub's UIController: the client is a display and input device. It renders the
-- Snapshot and the RunState the server pushes, routes button presses into InputController,
-- and sends Ready / Leave / RetryLoad / Debug intents. It never decides a phase, a reward,
-- a cooldown or a max HP. The Humanoid the server sized with Armory.MaxHp is the only
-- source for the HP bar.
--
-- This module is the one place that reads the profile: it forwards the equipped gear to
-- InputController and WeaponController, the ability cooldowns to the HUD, and the mission
-- material to CombatFxController. Everything else is pushed, never pulled.
--
-- Degrades like the hub: a profile that will not load shows the same safe-mode card instead
-- of a kick, a RunState that never arrives leaves the HUD in its lobby state, and the
-- summary card renders dashes rather than inventing numbers.
--
-- P1 Proving Grounds (CameraController.IsRange, Studio only): a different, smaller HUD. No
-- CombatHud at all, because Ben's rule is no attack button in the range (touch attacks are
-- auto-fire / tap-fire in InputController) and the range has no run, wallet or HP to show.
-- It mounts the centre Crosshair and FeedbackController's overlay in an inset-free ScreenGui
-- (so the dot is the camera's true centre line), plus the Studio RangePanel, the toast and the
-- load card. Missions are unchanged.
--
-- P3: the range also mounts the AbilityBar (PC / gamepad cooldown tiles; hidden on touch, where
-- InputController's ability buttons show the same). It reads InputController's ability getters
-- and the loadout FeedbackController confirmed, and keeps clear of the RangePanel's column.
--
-- P4: enemies hit back, so the range does have HP to show after all. VitalsController's HUD
-- (health bar, hurt flash, direction pointer, down banner) is mounted in the same inset-free
-- ScreenGui as the crosshair and laid out here against the AbilityBar or, on touch, the thumb
-- cluster. The panel gains the `god` switch and its readouts from RangeStats.
--
-- P4 Stop 2: a boss has a bar. BossBar is mounted in the HUD ScreenGui (the one that keeps
-- under the top bar and inside the device's safe area, where the RangePanel also lives), fed
-- every frame from CrowdRenderer.GetBoss, and laid out here against the panel's column; the
-- pointer ring of the vitals HUD is told where the bar ends so it keeps under it.
--
-- P5 (docs/INTERFACES.md "P5 contracts", rulings 5, 19, 22 and 25): three boots, chosen once
-- from the shared CombatMode. The range bench (`bootRange`), a crowd mission (`bootMission`),
-- and the C1 mission HUD (`boot`) for a build without the range's combat. A crowd mission
-- mounts the range's HUD stack (crosshair, Feedback's overlay, AbilityBar, the vitals HUD,
-- BossBar; the touch buttons come with InputController and MovementController) under the run
-- layer of CombatHud with no Attack / stance / ability cluster: on a phone attacks are the
-- range's auto-fire and auto-swing. Wave banners, `bossDown` and `mentor` stay
-- CombatFxController's; there is no per-kill pop (ruling 23). The summary card path is C1's.
-- In Studio, B and N skip to the next boss wave and the next wave (RequestDebug "skip"), and a
-- corner line names the keys; the C1 lever strip stays, its spawn buttons naming crowd kinds.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Armory = require(sharedFolder:WaitForChild("Armory"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local CombatMode = require(sharedFolder:WaitForChild("CombatMode"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local CombatHud = require(uiFolder:WaitForChild("CombatHud"))
local SummaryCard = require(uiFolder:WaitForChild("SummaryCard"))
local Toast = require(uiFolder:WaitForChild("Toast"))
local LoadScreen = require(uiFolder:WaitForChild("LoadScreen"))
local DebugPanel = require(uiFolder:WaitForChild("DebugPanel"))
local Crosshair = require(uiFolder:WaitForChild("Crosshair"))
local RangePanel = require(uiFolder:WaitForChild("RangePanel"))
local AbilityBar = require(uiFolder:WaitForChild("AbilityBar"))
local BossBar = require(uiFolder:WaitForChild("BossBar"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))
local CombatFxController = require(script.Parent:WaitForChild("CombatFxController"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local FeedbackController = require(script.Parent:WaitForChild("FeedbackController"))
local MovementController = require(script.Parent:WaitForChild("MovementController"))
local VitalsController = require(script.Parent:WaitForChild("VitalsController"))
local ThreatFx = require(script.Parent:WaitForChild("ThreatFx"))
local CrowdRenderer = require(script.Parent:WaitForChild("CrowdRenderer"))
local Haptics = require(script.Parent:WaitForChild("Haptics"))

local HUMANOID_WAIT_SECONDS = 5
local DEFAULT_HIT_MARKER_SECONDS = 0.12
-- Cursor-hold reasons (CameraController.SetCursorHold): each modal frees the mouse by name.
local HOLD_LOAD = "load"
local HOLD_DEBUG = "debug"
local HOLD_RANGE_PANEL = "rangePanel"
local MELEE_SLOT = "melee"
local RANGED_SLOT = "ranged"
local ADMIT_CHECK_LEVER = "admitCheck"
-- P5, Studio missions only: the skip keys, the lever they send and the line that names them.
local SKIP_LEVER = "skip"
local SKIP_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.B] = "boss",
	[Enum.KeyCode.N] = "next",
}
local SKIP_HINT = "B boss · N next wave"
-- Run phases with nothing left to fight: the summary card has the screen.
local RUN_OVER_PHASES: { [string]: boolean } = { summary = true, ended = true }

local CombatUIController = {}

-- Only a table with the fields the HUD reads is trusted; RunState arrives from the network.
local function isRunState(payload: any): boolean
	return typeof(payload) == "table"
		and typeof(payload.phase) == "string"
		and typeof(payload.missionId) == "string"
		and typeof(payload.wave) == "number"
		and typeof(payload.waves) == "number"
		and typeof(payload.tempo) == "number"
		and typeof(payload.party) == "table"
end

-- Ability keys are config ids ("fanTheHammer"); the button shows them as words. Truncation
-- on the button handles the long ones — the Q / E letter is the real affordance.
local function prettify(key: string): string
	local spaced = key:gsub("(%l)(%u)", "%1 %2")
	return spaced:sub(1, 1):upper() .. spaced:sub(2)
end

-- RangeStats arrives from the network: only a table with every readout field is shown.
local function isRangeStats(payload: any): boolean
	return typeof(payload) == "table"
		and typeof(payload.lastHits) == "number"
		and typeof(payload.lastKills) == "number"
		and typeof(payload.dps) == "number"
		and (payload.clearSeconds == nil or typeof(payload.clearSeconds) == "number")
		and typeof(payload.alive) == "number"
		and typeof(payload.serverFrameMs) == "number"
		and (payload.refused == nil or typeof(payload.refused) == "boolean")
		and (payload.refusedSeq == nil or typeof(payload.refusedSeq) == "number")
		and (payload.ability == nil or typeof(payload.ability) == "string")
		and (payload.abilityHits == nil or typeof(payload.abilityHits) == "number")
		and (payload.abilityKills == nil or typeof(payload.abilityKills) == "number")
		-- P4: nil from a server without enemies that fight; the panel then shows dashes.
		and (payload.damageTaken == nil or typeof(payload.damageTaken) == "number")
		and (payload.downs == nil or typeof(payload.downs) == "number")
		and (payload.god == nil or typeof(payload.god) == "boolean")
end

-- The HUD's one scale for a ScreenGui of this size (nil before the first layout).
local function hudScale(size: Vector2): number?
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	return math.clamp(
		math.min(size.X / Theme.DESIGN_WIDTH, size.Y / Theme.DESIGN_HEIGHT),
		Theme.MIN_SCALE,
		Theme.MAX_SCALE
	)
end

-- The audio settings belong to the profile, not to the place (review of 2026-09-17): a player
-- who muted music in the hub must arrive muted. Applied on every snapshot.
local function applySettings(state: { [string]: any }): ()
	local settings = state.settings
	if
		typeof(settings) == "table"
		and typeof(settings.music) == "boolean"
		and typeof(settings.sfx) == "boolean"
	then
		SoundController.ApplySettings({ music = settings.music, sfx = settings.sfx })
	end
end

-- What an ActionResult tells the player (nil = nothing), and whether it reads as an error.
local function actionResultText(payload: any): (string?, boolean)
	if typeof(payload) ~= "table" then
		return nil, false
	end
	-- The Studio admitCheck lever answers with its verdict, success included, tagged by slotId
	-- so it never reads as a real refusal.
	if payload.slotId == ADMIT_CHECK_LEVER and RunService:IsStudio() then
		local verdict = if payload.ok == true
			then "ok"
			elseif typeof(payload.reason) == "string" then payload.reason
			else "?"
		return "Admit check: " .. verdict, payload.ok ~= true
	end
	if payload.ok ~= false then
		return nil, false
	end
	local reason = payload.reason
	if reason == "unavailable" then
		-- The one refusal a player can hit in C0: the hub place id is still 0, or Studio
		-- cannot teleport at all. Either way they stay, so say so.
		return if RunService:IsStudio()
			then "Studio can't teleport — reopen build/test.rbxl for the hub"
			else "Can't travel right now — staying in the lobby",
			true
	elseif reason == "locked" then
		return "That expedition is locked for you", true
	elseif reason == "full" then
		return "That run is full", true
	elseif reason == "over" then
		return "That run has moved past joining", true
	end
	return "Can't do that right now", true
end

-- The boss bar's second phase is felt as well as seen, where the device can and as strongly as
-- the tuned haptics layer says (0 = off), like every other pulse of the range's combat.
local function enragePulse(): ()
	local feedback = (Tuning.Get() :: any).feedback
	local layer = if typeof(feedback) == "table" then feedback.haptics else nil
	local strength = if typeof(layer) == "number" then math.max(layer, 0) else 1
	Haptics.Pulse(
		Theme.COMBAT_RANGE_HAPTIC_HEAVY * strength,
		Theme.COMBAT_RANGE_HAPTIC_HEAVY_SECONDS
	)
end

-- The PC / gamepad ability tiles (hidden on touch, where InputController's buttons show the
-- same).
local function newAbilityBar(screenGui: ScreenGui): AbilityBar.AbilityBarHandle
	return AbilityBar.new(screenGui, {
		getState = InputController.GetAbilityState,
		-- P4: knocked down veils the tiles as an ability in progress does; neither can cast.
		isBusy = function(): boolean
			return InputController.IsBusy() or MovementController.IsDown()
		end,
		getActiveSlot = InputController.GetActiveSlot,
		getLoadout = FeedbackController.GetLoadout,
	})
end

-- The touch thumb cluster (jump, dash, ADS, abilities, slot): the height it owns at the bottom
-- right, and (P4) its left and top edges for the health bar; 0, nil, nil without touch. ADS
-- sits above jump and is smaller than it, so one more jump size covers it; the leftmost buttons
-- are the melee ability (top row) and the slot button (bottom row).
local function touchCluster(): (number, number?, number?)
	local camera = Workspace.CurrentCamera
	if not UserInputService.TouchEnabled or camera == nil then
		return 0, nil, nil
	end
	local viewport = camera.ViewportSize
	local jumpTopLeft, jumpSize = MovementController.JumpButtonRect(viewport)
	local meleeCentre, meleeSize = MovementController.ClusterRect(viewport, "abilityMelee")
	local slotCentre, slotSize = MovementController.ClusterRect(viewport, "slot")
	return viewport.Y - jumpTopLeft.Y + jumpSize,
		math.min(meleeCentre.X - meleeSize / 2, slotCentre.X - slotSize / 2),
		meleeCentre.Y - meleeSize / 2
end

-- The C1 lever strip names its spawn buttons from `mission.enemies`. A crowd mission spawns
-- crowd kinds (ruling 25), every one of which has a `crowd.rewards` entry, so the strip is
-- handed a view of the mission whose `enemies` are those kinds.
local function leverMission(mission: Types.MissionConfig?): Types.MissionConfig?
	if mission == nil or mission.crowd == nil then
		return mission
	end
	local view = table.clone(mission)
	view.enemies = (mission.crowd :: Types.MissionCrowdConfig).rewards :: any
	return view
end

local function bootRange(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent
	local requestSnapshot = remotesFolder:WaitForChild("RequestSnapshot") :: RemoteEvent
	local requestRetryLoad = remotesFolder:WaitForChild("RequestRetryLoad") :: RemoteEvent
	-- Filled in once they replicate (see the end of this function), so a slow remote never
	-- holds the HUD back.
	local requestTune: RemoteEvent? = nil
	local requestCommand: RemoteEvent? = nil

	-- Above the range layer, so the panel and toasts always draw over the crosshair.
	local screenGui = Create("ScreenGui", {
		Name = "ExpeditionHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
		Parent = playerGui,
	}) :: ScreenGui
	local rangeGui = Create("ScreenGui", {
		Name = "RangeHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	local toast = Toast.new(screenGui)
	local loaded = false
	local loadScreen = LoadScreen.new(screenGui, {
		onRetry = function()
			requestRetryLoad:FireServer()
		end,
		onLeave = function()
			player:Kick("Rejoin to load your save.")
		end,
	})
	local crosshair = Crosshair.new(rangeGui)
	FeedbackController.Mount(rangeGui, crosshair)
	VitalsController.Mount(rangeGui)
	local bossBar = BossBar.new(screenGui, { onEnrage = enragePulse })

	-- One debounce window for the command buttons (not the sliders, which throttle
	-- themselves), so a double tap on Stress never becomes two spawns.
	local lastCommandAt = 0
	local panel = RangePanel.new(screenGui, {
		onTune = function(path: string, value: Types.TuneValue)
			local remote = requestTune
			if remote ~= nil then
				remote:FireServer(path, value)
			end
		end,
		onCommand = function(cmd: string, arg: string?)
			local remote = requestCommand
			local now = os.clock()
			if remote == nil or now - lastCommandAt < Theme.ACTION_DEBOUNCE_SECONDS then
				return
			end
			lastCommandAt = now
			remote:FireServer(cmd, arg)
			if cmd == "set" or cmd == "reset" or cmd == "stress" then
				-- The server drops every projectile with the crowd it replaces: the player's
				-- own in flight, and (P4 wave 2) the enemy's shots and circles.
				FeedbackController.ClearFlights()
				ThreatFx.Clear()
			end
			if cmd == "export" then
				toast.Show("Tuned values printed to Output", Theme.TOAST_ERROR_SECONDS, false)
			end
		end,
		onWireframe = function(on: boolean)
			FeedbackController.SetWireframe(on)
		end,
		getActiveSlot = InputController.GetActiveSlot,
		onToggle = function(open: boolean)
			-- The sheet needs the pointer; closing it hands the mouse back to the crosshair.
			CameraController.SetCursorHold(HOLD_RANGE_PANEL, open)
		end,
	})
	FeedbackController.SetTuneStateHandler(function()
		panel.SetLoadout(FeedbackController.GetLoadout())
	end)
	local abilityBar = newAbilityBar(screenGui)

	local function onStateChanged(payload: any): ()
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "snapshot" then
			if typeof(payload.state) ~= "table" then
				return
			end
			if not loaded then
				loaded = true
				loadScreen.Hide()
				-- There is no RunState in the range, so the first Snapshot is the only thing
				-- that ever frees a load hold.
				CameraController.SetCursorHold(HOLD_LOAD, false)
			end
			applySettings(payload.state)
		elseif payload.kind == "loadStatus" and not loaded then
			local phase = payload.phase
			if phase ~= "loading" and phase ~= "failed" then
				return
			end
			-- The range takes the pointer only when the card has buttons to press; a normal
			-- load never unlocks the crosshair.
			CameraController.SetCursorHold(HOLD_LOAD, phase == "failed")
			local attempt = payload.attempt
			local retryAvailableIn = payload.retryAvailableIn
			loadScreen.Apply({
				phase = phase,
				attempt = if typeof(attempt) == "number" then attempt else 1,
				retryAvailableIn = if typeof(retryAvailableIn) == "number"
					then retryAvailableIn
					else 0,
			})
		end
	end

	local function applyLayout(): ()
		local size = screenGui.AbsoluteSize
		local scale = hudScale(size)
		if scale == nil then
			return
		end
		crosshair.SetLayout(scale)
		FeedbackController.SetLayout(scale)
		-- On touch the jump / dash / ADS cluster owns the bottom-right; the panel stays above
		-- it. P4: the health bar goes beside that cluster or above it.
		local reserve, clusterLeft, clusterTop = touchCluster()
		local panelBottom = panel.SetLayout(scale, size, reserve)
		-- The panel docks right at the screen margin; the bar keeps out of that column.
		local rightReserve = Theme.COMBAT_RANGE_PANEL_WIDTH + Theme.SCREEN_MARGIN
		abilityBar.SetLayout(scale, size, rightReserve)
		-- Stop 2: the boss bar takes the top, beside that column or under its readouts.
		local bossBottom =
			bossBar.SetLayout(scale, size, size.X - rightReserve * scale, panelBottom)
		-- This ScreenGui starts under the top bar; the vitals HUD's does not.
		local inset = GuiService:GetGuiInset()
		VitalsController.SetLayout({
			scale = scale,
			rightReserve = rightReserve,
			clusterLeft = clusterLeft,
			clusterTop = clusterTop,
			topLimit = bossBottom + inset.Y,
		})
		loadScreen.SetScale(scale)
		toast.SetLayout(scale, size.X > size.Y, 0)
	end

	stateChanged.OnClientEvent:Connect(onStateChanged)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	applyLayout()
	-- The boss bar is pure display: CrowdRenderer knows the boss, this hands it over.
	RunService.RenderStepped:Connect(function(deltaTime: number)
		bossBar.Update(deltaTime, CrowdRenderer.GetBoss())
	end)
	requestSnapshot:FireServer()

	local waitSeconds = Theme.COMBAT_REMOTE_WAIT_SECONDS
	requestTune = remotesFolder:WaitForChild("RequestTune", waitSeconds) :: RemoteEvent?
	requestCommand = remotesFolder:WaitForChild("RequestRangeCommand", waitSeconds) :: RemoteEvent?
	local rangeStats = remotesFolder:WaitForChild("RangeStats", waitSeconds) :: RemoteEvent?
	if requestTune == nil or requestCommand == nil or rangeStats == nil then
		warn("[CombatUIController] a range remote is missing — the panel cannot tune")
	end
	if rangeStats ~= nil then
		rangeStats.OnClientEvent:Connect(function(payload: any)
			if isRangeStats(payload) then
				local stats = payload :: Types.RangeStats
				panel.SetStats(stats)
				if stats.refused == true then
					-- P3.1: the refusal names its attack, so only that swing is taken back.
					FeedbackController.OnRefused(stats.refusedSeq)
				end
			end
		end)
	end
end

local function boot(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local armoryConfig = Catalog.GetArmoryConfig()
	local combatConfig = Catalog.GetCombatConfig()
	local hitMarkerSeconds = if combatConfig ~= nil
		then combatConfig.feel.hitMarkerSeconds
		else DEFAULT_HIT_MARKER_SECONDS
	-- The load card needs the pointer until the profile arrives.
	CameraController.SetCursorHold(HOLD_LOAD, true)

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent
	local actionResult = remotesFolder:WaitForChild("ActionResult") :: RemoteEvent
	local runStateEvent = remotesFolder:WaitForChild("RunState") :: RemoteEvent
	local requestSnapshot = remotesFolder:WaitForChild("RequestSnapshot") :: RemoteEvent
	local requestRetryLoad = remotesFolder:WaitForChild("RequestRetryLoad") :: RemoteEvent
	local requestReady = remotesFolder:WaitForChild("RequestReady") :: RemoteEvent
	local requestLeave = remotesFolder:WaitForChild("RequestLeave") :: RemoteEvent
	-- C1 adds RequestDebug; an older server build simply has no lever strip.
	local requestDebug =
		remotesFolder:WaitForChild("RequestDebug", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?

	local screenGui = Create("ScreenGui", {
		Name = "ExpeditionHUD",
		ResetOnSpawn = false,
		-- Sibling, like the hub: the ZINDEX_* constants order the overlay roots only, so a
		-- scrim can never cover its own card and swallow the Return tap.
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	local loaded = false
	-- Two connections per character (Health and the MaxHealth the server sets on admit);
	-- both are dropped when the next character arrives so a respawn leaks nothing.
	local healthConnections: { RBXScriptConnection } = {}
	local applyLayout: () -> ()
	local mission: Types.MissionConfig? = nil

	-- Same client-side debounce as the hub's panels (review of 2026-09-17): ten taps on
	-- Return must not become ten RequestLeave intents against the rate limit. One window for
	-- all three buttons, exactly as a hub panel shares one per sheet.
	local lastIntentTime = 0
	local function fireIntent(remote: RemoteEvent): ()
		local now = os.clock()
		if now - lastIntentTime < Theme.ACTION_DEBOUNCE_SECONDS then
			return
		end
		lastIntentTime = now
		remote:FireServer()
	end

	local toast = Toast.new(screenGui)
	local loadScreen = LoadScreen.new(screenGui, {
		onRetry = function()
			requestRetryLoad:FireServer()
		end,
		onLeave = function()
			-- Kick, not RequestLeave: with no profile loaded the server has nothing to send
			-- home with, and rejoining lands the player back in the hub (the root place).
			player:Kick("Rejoin to load your save.")
		end,
	})
	local hud = CombatHud.new(screenGui, {
		onReady = function()
			fireIntent(requestReady)
		end,
		onLeave = function()
			fireIntent(requestLeave)
		end,
		onStance = function()
			InputController.ToggleStance()
		end,
		onAttackDown = function()
			InputController.AttackDown()
		end,
		onAttackUp = function()
			InputController.AttackUp()
		end,
		onAbility = function(slot: string)
			InputController.UseAbility(slot)
		end,
		onAttackInput = function(input: InputObject)
			CameraController.AdoptTouch(input)
		end,
	})
	local summaryCard = SummaryCard.new(screenGui, {
		onReturn = function()
			fireIntent(requestLeave)
		end,
	})
	-- Studio only, by contract: a live client never builds the strip at all, and the
	-- server ignores the remote even if one were forged.
	local debugPanel = if RunService:IsStudio()
		then DebugPanel.new(screenGui, {
			onLever = function(lever: string, value: any)
				if requestDebug ~= nil then
					requestDebug:FireServer(lever, value)
				end
			end,
			onToggle = function(open: boolean)
				CameraController.SetCursorHold(HOLD_DEBUG, open)
			end,
		})
		else nil

	-- The two ability buttons are named by the equipped weapons, so a tier change renames
	-- them. A starter weapon has no ability and hides its button.
	local function abilityInfo(slot: string, tier: number): CombatHud.AbilityInfo?
		local cfg = armoryConfig
		if cfg == nil then
			return nil
		end
		local tierDef = Armory.TierDef(cfg, slot, tier)
		if tierDef == nil or tierDef.ability == "" then
			return nil
		end
		local ability = Armory.AbilityDef(cfg, tierDef.ability)
		if ability == nil then
			return nil
		end
		return { name = prettify(tierDef.ability), cooldown = ability.cooldown }
	end

	local function onSnapshot(payload: { [string]: any }): ()
		local state = payload.state
		if typeof(state) ~= "table" then
			return
		end
		if not loaded then
			loaded = true
			loadScreen.Hide() -- permanent: the profile is here
			CameraController.SetCursorHold(HOLD_LOAD, false)
		end
		-- Applied before the ambient starts, and on every snapshot, because the server stays
		-- authoritative.
		applySettings(state)
		local eraName = payload.eraName
		if typeof(eraName) == "string" then
			-- The arena's era decides the ambient bed, exactly as the hub's plot does.
			SoundController.SetAmbientEra(eraName)
		end

		local combat = state.combat
		if typeof(combat) ~= "table" then
			return
		end
		local gear = combat.gear
		local ascension = combat.ascension
		if typeof(gear) == "table" and typeof(ascension) == "table" then
			InputController.SetGear(gear)
			WeaponController.SetGear(gear, ascension)
			hud.SetAbilities({
				melee = abilityInfo(MELEE_SLOT, gear.melee),
				ranged = abilityInfo(RANGED_SLOT, gear.ranged),
			})
			if debugPanel ~= nil then
				debugPanel.SetGear(gear.melee, gear.ranged)
			end
		end
		-- Wallet: cash and Valor are always shown; the material chip needs the mission, so
		-- it stays blank until the first RunState names one.
		local materials = combat.materials
		local materialName = if mission ~= nil then mission.material else ""
		local amount = 0
		if typeof(materials) == "table" and materialName ~= "" then
			local owned = materials[materialName]
			amount = if typeof(owned) == "number" then owned else 0
		end
		hud.SetWallet(
			if typeof(state.cash) == "number" then state.cash else 0,
			materialName,
			amount,
			if typeof(combat.valor) == "number" then combat.valor else 0
		)
	end

	local function onLoadStatus(payload: { [string]: any }): ()
		local phase = payload.phase
		if phase ~= "loading" and phase ~= "failed" then
			return
		end
		local attempt = payload.attempt
		local retryAvailableIn = payload.retryAvailableIn
		loadScreen.Apply({
			phase = phase,
			attempt = if typeof(attempt) == "number" then attempt else 1,
			retryAvailableIn = if typeof(retryAvailableIn) == "number" then retryAvailableIn else 0,
		})
	end

	local function onStateChanged(payload: any): ()
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "snapshot" then
			onSnapshot(payload)
		elseif payload.kind == "loadStatus" then
			onLoadStatus(payload)
		end
	end

	local lastPhase = ""
	local function onRunState(payload: any): ()
		if not isRunState(payload) then
			return
		end
		local run = (payload :: any) :: Types.RunState
		-- The run carries an id; the human-readable name lives in the mission config both
		-- places share. A missing config degrades to the id, never to an error.
		local hadMission = mission ~= nil
		mission = Catalog.GetMissionById(run.missionId)
		local missionConfig = mission
		if not hadMission and missionConfig ~= nil then
			-- The wallet's material chip needs the mission name, and the join Snapshot
			-- arrived before this first RunState named one. Ask once for a fresh one.
			requestSnapshot:FireServer()
		end
		hud.SetMission(if missionConfig ~= nil then missionConfig.name else run.missionId)
		CameraController.SetPhase(run.phase)
		hud.SetRunState(run)
		InputController.SetPhase(run.phase)
		if missionConfig ~= nil then
			CombatFxController.SetMaterial(missionConfig.material)
		end
		if debugPanel ~= nil then
			debugPanel.SetWave(run.wave)
			debugPanel.SetMission(missionConfig)
		end
		CombatFxController.SetParty(run.party)
		if run.phase == "summary" then
			if lastPhase ~= "summary" then
				SoundController.Play("runEnd")
			end
			local returnIn = run.returnIn
			summaryCard.Show(run.summary, {
				partySize = #run.party,
				returnIn = if typeof(returnIn) == "number" then returnIn else nil,
			})
		else
			summaryCard.Hide()
		end
		-- A wave clear is the moment the pool is flushed, so ask for the Snapshot that
		-- carries the new wallet instead of waiting for the next one.
		if lastPhase == "wave" and run.phase == "breather" then
			SoundController.Play("waveClear")
			requestSnapshot:FireServer()
		end
		lastPhase = run.phase
	end

	local function onActionResult(payload: any): ()
		local text, isError = actionResultText(payload)
		if text ~= nil then
			toast.Show(text, Theme.TOAST_ERROR_SECONDS, isError)
		end
	end

	-- The HP bar follows the Humanoid the server sized, across every respawn.
	local function bindCharacter(character: Model): ()
		for _, connection in healthConnections do
			connection:Disconnect()
		end
		table.clear(healthConnections)
		local humanoid = character:WaitForChild("Humanoid", HUMANOID_WAIT_SECONDS) :: Humanoid?
		if humanoid == nil then
			return -- a character without a Humanoid is not ours to render
		end
		local function push(): ()
			hud.SetHealth(humanoid.Health, humanoid.MaxHealth)
			CombatFxController.SetHealth(humanoid.Health, humanoid.MaxHealth)
		end
		table.insert(healthConnections, humanoid.HealthChanged:Connect(push))
		-- MaxHealth is set once by ArenaService on admit, which can land after this bind.
		table.insert(
			healthConnections,
			humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(push)
		)
		push()
	end

	applyLayout = function(): ()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return -- AbsoluteSize is zero before the first layout; the signal re-enters
		end
		local scale = math.clamp(
			math.min(size.X / Theme.DESIGN_WIDTH, size.Y / Theme.DESIGN_HEIGHT),
			Theme.MIN_SCALE,
			Theme.MAX_SCALE
		)
		hud.SetLayout(scale, size)
		summaryCard.SetScale(scale)
		loadScreen.SetScale(scale)
		toast.SetLayout(scale, size.X > size.Y, 0)
		if debugPanel ~= nil then
			debugPanel.SetLayout(scale, size)
		end
	end

	InputController.SetStanceChanged(function(stance: string)
		hud.SetStance(stance)
	end)
	CombatFxController.SetBannerHandler(function(title: string)
		-- The banner fades; the toast is the record of it for anyone looking elsewhere.
		toast.Show(title, Theme.TOAST_ERROR_SECONDS, false)
	end)
	CombatFxController.SetToastHandler(function(text: string)
		toast.Show(text, Theme.TOAST_ERROR_SECONDS, false)
	end)
	CombatFxController.SetHitMarkerHandler(function(heavy: boolean)
		hud.ShowHitMarker(heavy, hitMarkerSeconds)
	end)
	-- The reticle follows the camera and the bow every frame; the HUD writes only changes.
	RunService.RenderStepped:Connect(function()
		hud.SetAiming(CameraController.IsActive(), CameraController.IsAiming())
		hud.SetCharge(InputController.GetCharge())
	end)
	hud.SetStance(InputController.GetStance())

	stateChanged.OnClientEvent:Connect(onStateChanged)
	actionResult.OnClientEvent:Connect(onActionResult)
	runStateEvent.OnClientEvent:Connect(onRunState)
	player.CharacterAdded:Connect(bindCharacter)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	local character = player.Character
	if character ~= nil then
		bindCharacter(character)
	end
	applyLayout()
	-- One explicit request on boot: the server's join snapshot may have fired before this
	-- connection existed; duplicate snapshots are harmless by design.
	requestSnapshot:FireServer()
end

-- P5: a crowd mission (see the header). The run layer is C1's; the fight is the range's.
local function bootMission(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local studio = RunService:IsStudio()
	-- Ruling 19: a proving mission starts and loops by itself; there is nothing to be ready for
	-- and nowhere to return to (the Studio return kicks).
	local proving = CombatMode.IsProving()
	-- The load card needs the pointer until the profile arrives.
	CameraController.SetCursorHold(HOLD_LOAD, true)

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent
	local actionResult = remotesFolder:WaitForChild("ActionResult") :: RemoteEvent
	local runStateEvent = remotesFolder:WaitForChild("RunState") :: RemoteEvent
	local requestSnapshot = remotesFolder:WaitForChild("RequestSnapshot") :: RemoteEvent
	local requestRetryLoad = remotesFolder:WaitForChild("RequestRetryLoad") :: RemoteEvent
	local requestReady = remotesFolder:WaitForChild("RequestReady") :: RemoteEvent
	local requestLeave = remotesFolder:WaitForChild("RequestLeave") :: RemoteEvent
	local requestDebug =
		remotesFolder:WaitForChild("RequestDebug", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?

	-- Above the range layer, so the run layer, cards and toasts draw over the crosshair. The
	-- range layer ignores the top-bar inset, so its centre is the camera's centre line.
	local screenGui = Create("ScreenGui", {
		Name = "ExpeditionHUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
		Parent = playerGui,
	}) :: ScreenGui
	local rangeGui = Create("ScreenGui", {
		Name = "RangeHUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	}) :: ScreenGui

	local loaded = false
	local mission: Types.MissionConfig? = nil
	local arenaName = ""
	local lastPhase = ""
	-- One debounce window for Ready, Return and the skip keys (review of 2026-09-17).
	local lastIntentTime = 0
	local function debounced(): boolean
		local now = os.clock()
		if now - lastIntentTime < Theme.ACTION_DEBOUNCE_SECONDS then
			return false
		end
		lastIntentTime = now
		return true
	end
	local function fireIntent(remote: RemoteEvent): ()
		if debounced() then
			remote:FireServer()
		end
	end

	local toast = Toast.new(screenGui)
	local loadScreen = LoadScreen.new(screenGui, {
		onRetry = function()
			requestRetryLoad:FireServer()
		end,
		onLeave = function()
			-- Kick, not RequestLeave: with no profile loaded the server has nothing to send
			-- home with, and rejoining lands the player back in the hub (the root place).
			player:Kick("Rejoin to load your save.")
		end,
	})
	local crosshair = Crosshair.new(rangeGui)
	FeedbackController.Mount(rangeGui, crosshair)
	VitalsController.Mount(rangeGui)
	local bossBar = BossBar.new(screenGui, { onEnrage = enragePulse })
	local abilityBar = newAbilityBar(screenGui)
	-- The cluster's handlers are never pressed (it is not shown); they route to the range path
	-- like every other entry point, so a stray call still does the right thing.
	local hud = CombatHud.new(screenGui, {
		onReady = function()
			fireIntent(requestReady)
		end,
		onLeave = function()
			fireIntent(requestLeave)
		end,
		onStance = InputController.ToggleStance,
		onAttackDown = InputController.AttackDown,
		onAttackUp = InputController.AttackUp,
		onAbility = InputController.UseAbility,
		actions = false,
		runButtons = not proving,
		keyHint = if studio then SKIP_HINT else nil,
	})
	-- A proving mission restarts in place after the summary's countdown (ruling 19): no Return
	-- button, and the countdown names the next run.
	local summaryCard = SummaryCard.new(screenGui, {
		onReturn = function()
			fireIntent(requestLeave)
		end,
		nextRun = proving,
	})
	-- Studio only, by contract: a live client never builds the strip, and the server ignores
	-- the remote even if one were forged.
	local debugPanel = if studio
		then DebugPanel.new(screenGui, {
			onLever = function(lever: string, value: any)
				if requestDebug ~= nil then
					requestDebug:FireServer(lever, value)
				end
			end,
			onToggle = function(open: boolean)
				CameraController.SetCursorHold(HOLD_DEBUG, open)
			end,
		})
		else nil

	local function onSnapshot(payload: { [string]: any }): ()
		local state = payload.state
		if typeof(state) ~= "table" then
			return
		end
		if not loaded then
			loaded = true
			loadScreen.Hide() -- permanent: the profile is here
			CameraController.SetCursorHold(HOLD_LOAD, false)
		end
		applySettings(state)
		local eraName = payload.eraName
		if typeof(eraName) == "string" then
			SoundController.SetAmbientEra(eraName)
		end
		local combat = state.combat
		if typeof(combat) ~= "table" then
			return
		end
		local gear = combat.gear
		if debugPanel ~= nil and typeof(gear) == "table" then
			debugPanel.SetGear(gear.melee, gear.ranged)
		end
		-- Wallet: cash and Valor always; the material chip needs the mission, so it stays
		-- blank until the first RunState names one. Never predicted: every flush re-sends it.
		local materials = combat.materials
		local materialName = if mission ~= nil then mission.material else ""
		local owned = if typeof(materials) == "table" and materialName ~= ""
			then materials[materialName]
			else nil
		hud.SetWallet(
			if typeof(state.cash) == "number" then state.cash else 0,
			materialName,
			if typeof(owned) == "number" then owned else 0,
			if typeof(combat.valor) == "number" then combat.valor else 0
		)
	end

	local function onStateChanged(payload: any): ()
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "snapshot" then
			onSnapshot(payload)
		elseif payload.kind == "loadStatus" and not loaded then
			local phase = payload.phase
			if phase ~= "loading" and phase ~= "failed" then
				return
			end
			local attempt = payload.attempt
			local retryAvailableIn = payload.retryAvailableIn
			loadScreen.Apply({
				phase = phase,
				attempt = if typeof(attempt) == "number" then attempt else 1,
				retryAvailableIn = if typeof(retryAvailableIn) == "number"
					then retryAvailableIn
					else 0,
			})
		end
	end

	local function onRunState(payload: any): ()
		if not isRunState(payload) then
			return
		end
		local run = (payload :: any) :: Types.RunState
		local hadMission = mission ~= nil
		mission = Catalog.GetMissionById(run.missionId)
		local missionConfig = mission
		if missionConfig ~= nil then
			if not hadMission then
				-- The wallet's material chip needs the mission name, and the join Snapshot
				-- arrived before this first RunState named one. Ask once for a fresh one.
				requestSnapshot:FireServer()
			end
			if missionConfig.arena ~= arenaName then
				arenaName = missionConfig.arena
				CrowdRenderer.SetArena(arenaName)
			end
			CombatFxController.SetMaterial(missionConfig.material)
		end
		local phase = run.phase
		hud.SetMission(if missionConfig ~= nil then missionConfig.name else run.missionId)
		CameraController.SetPhase(phase)
		hud.SetRunState(run)
		InputController.SetPhase(phase)
		CombatFxController.SetParty(run.party)
		if debugPanel ~= nil then
			debugPanel.SetWave(run.wave)
			debugPanel.SetMission(leverMission(missionConfig))
		end
		local userId = player.UserId
		for _, member in run.party do
			if typeof(member) == "table" and member.userId == userId then
				VitalsController.SetServerDown(member.down == true)
				break
			end
		end
		local over = RUN_OVER_PHASES[phase] == true
		-- The summary card has the screen: no crosshair, health bar or banner under it.
		rangeGui.Enabled = not over
		if phase == "summary" then
			local returnIn = run.returnIn
			summaryCard.Show(run.summary, {
				partySize = #run.party,
				returnIn = if typeof(returnIn) == "number" then returnIn else nil,
			})
		else
			summaryCard.Hide()
		end
		if over and not RUN_OVER_PHASES[lastPhase] then
			-- The server ended the run: its crowd, threats and projectiles are gone (EndRun),
			-- and the run's pool was paid, so the wallet is asked for at once.
			ThreatFx.Clear()
			FeedbackController.ClearFlights()
			requestSnapshot:FireServer()
		elseif lastPhase == "wave" and phase == "breather" then
			-- A wave clear is the moment the pool is flushed.
			requestSnapshot:FireServer()
		end
		lastPhase = phase
	end

	local function onActionResult(payload: any): ()
		local text, isError = actionResultText(payload)
		if text ~= nil then
			toast.Show(text, Theme.TOAST_ERROR_SECONDS, isError)
		end
	end

	local function applyLayout(): ()
		local size = screenGui.AbsoluteSize
		local scale = hudScale(size)
		if scale == nil then
			return -- AbsoluteSize is zero before the first layout; the signal re-enters
		end
		local edges = hud.SetLayout(scale, size)
		summaryCard.SetScale(scale)
		loadScreen.SetScale(scale)
		toast.SetLayout(scale, size.X > size.Y, 0)
		if debugPanel ~= nil then
			debugPanel.SetLayout(scale, size)
		end
		crosshair.SetLayout(scale)
		FeedbackController.SetLayout(scale)
		local _, clusterLeft, clusterTop = touchCluster()
		-- No panel column: the tiles and the health bar sit bottom centre.
		abilityBar.SetLayout(scale, size, 0)
		-- The boss bar takes the top strip between the run header and the party list where
		-- it fits (a monitor), else it hangs under the header and wallet; CombatHud starts a
		-- portrait party list under that.
		local bossBottom =
			bossBar.SetLayout(scale, size, edges.partyLeft, edges.headerBottom, edges.headerRight)
		-- This ScreenGui starts under the top bar; the vitals HUD's does not.
		local inset = GuiService:GetGuiInset()
		VitalsController.SetLayout({
			scale = scale,
			rightReserve = 0,
			clusterLeft = clusterLeft,
			clusterTop = clusterTop,
			topLimit = bossBottom + inset.Y,
		})
	end

	-- Ruling 25 / the contract's keys: B = the next boss wave, N = the next wave. Studio only;
	-- the server ignores the lever anywhere else. The skip clears the crowd and its threats on
	-- the server without a word, so the client's circles and shots go at once.
	local function onSkipKey(input: InputObject, processed: boolean): ()
		local which = SKIP_KEYS[input.KeyCode]
		if processed or which == nil or requestDebug == nil then
			return
		end
		if not debounced() then
			return
		end
		requestDebug:FireServer(SKIP_LEVER, which)
		ThreatFx.Clear()
	end

	CombatFxController.SetBannerHandler(function(title: string)
		-- The banner fades; the toast is the record of it for anyone looking elsewhere.
		toast.Show(title, Theme.TOAST_ERROR_SECONDS, false)
	end)
	CombatFxController.SetToastHandler(function(text: string)
		toast.Show(text, Theme.TOAST_ERROR_SECONDS, false)
	end)

	stateChanged.OnClientEvent:Connect(onStateChanged)
	actionResult.OnClientEvent:Connect(onActionResult)
	runStateEvent.OnClientEvent:Connect(onRunState)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	if studio then
		UserInputService.InputBegan:Connect(onSkipKey)
	end
	-- Pure display every frame: the boss off CrowdRenderer, and the Alt hint's camera state.
	RunService.RenderStepped:Connect(function(deltaTime: number)
		bossBar.Update(deltaTime, CrowdRenderer.GetBoss())
		hud.SetAiming(CameraController.IsActive(), CameraController.IsAiming())
	end)
	applyLayout()
	-- One explicit request on boot: the server's join snapshot may have fired before this
	-- connection existed; duplicate snapshots are harmless by design.
	requestSnapshot:FireServer()

	-- RangeStats still comes in a mission, for the one thing a mission needs of it: a refused
	-- attack names its seq, so a swing drawn early is taken back (P3.1). Only those two fields
	-- are read: the bench's readouts (alive, server ms, ...) are the range's provider's, which a
	-- mission does not run.
	local rangeStats =
		remotesFolder:WaitForChild("RangeStats", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
	if rangeStats == nil then
		warn("[CombatUIController] RangeStats missing — refused swings are not taken back")
		return
	end
	rangeStats.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or payload.refused ~= true then
			return
		end
		local seq = payload.refusedSeq
		FeedbackController.OnRefused(if typeof(seq) == "number" then seq else nil)
	end)
end

function CombatUIController.Init(): ()
	-- Everything needs replicated instances (Shared, Remotes, PlayerGui), so it happens in
	-- Start and Init stays yield-free per the boot contract.
end

function CombatUIController.Start(): ()
	-- P5 ruling 5: the mode is decided once, before anything (CameraController.Init).
	task.spawn(
		if CameraController.IsRange()
			then bootRange
			elseif CameraController.IsCrowdCombat() then bootMission
			else boot
	)
end

return CombatUIController
