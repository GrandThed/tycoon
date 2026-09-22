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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Armory = require(sharedFolder:WaitForChild("Armory"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local CombatHud = require(uiFolder:WaitForChild("CombatHud"))
local SummaryCard = require(uiFolder:WaitForChild("SummaryCard"))
local Toast = require(uiFolder:WaitForChild("Toast"))
local LoadScreen = require(uiFolder:WaitForChild("LoadScreen"))
local DebugPanel = require(uiFolder:WaitForChild("DebugPanel"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local WeaponController = require(script.Parent:WaitForChild("WeaponController"))
local CombatFxController = require(script.Parent:WaitForChild("CombatFxController"))

local HUMANOID_WAIT_SECONDS = 5
local MELEE_SLOT = "melee"
local RANGED_SLOT = "ranged"

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

local function boot(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local armoryConfig = Catalog.GetArmoryConfig()

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
		end
		-- The audio settings belong to the profile, not to the place (review of 2026-09-17):
		-- a player who muted music in the hub must arrive muted. Applied before the ambient
		-- starts, and on every snapshot, because the server stays authoritative.
		local settings = state.settings
		if
			typeof(settings) == "table"
			and typeof(settings.music) == "boolean"
			and typeof(settings.sfx) == "boolean"
		then
			SoundController.ApplySettings({ music = settings.music, sfx = settings.sfx })
		end
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
		hud.SetRunState(run)
		InputController.SetPhase(run.phase)
		if missionConfig ~= nil then
			CombatFxController.SetMaterial(missionConfig.material)
		end
		if debugPanel ~= nil then
			debugPanel.SetWave(run.wave)
			debugPanel.SetMission(missionConfig)
		end
		if run.phase == "summary" then
			if lastPhase ~= "summary" then
				SoundController.Play("runEnd")
			end
			summaryCard.Show(run.summary)
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
		if typeof(payload) ~= "table" or payload.ok ~= false then
			return
		end
		local reason = payload.reason
		local message: string
		if reason == "unavailable" then
			-- The one refusal a player can hit in C0: the hub place id is still 0, or Studio
			-- cannot teleport at all. Either way they stay, so say so.
			message = if RunService:IsStudio()
				then "Studio can't teleport — reopen build/test.rbxl for the hub"
				else "Can't travel right now — staying in the lobby"
		elseif reason == "locked" then
			message = "That expedition is locked for you"
		else
			message = "Can't do that right now"
		end
		toast.Show(message, Theme.TOAST_ERROR_SECONDS, true)
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

function CombatUIController.Init(): ()
	-- Everything needs replicated instances (Shared, Remotes, PlayerGui), so it happens in
	-- Start and Init stays yield-free per the boot contract.
end

function CombatUIController.Start(): ()
	task.spawn(boot)
end

return CombatUIController
