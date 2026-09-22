--!strict
-- Owns the Expeditions place HUD (C0 contract, docs/INTERFACES.md "Combat client"). Same
-- shape as the hub's UIController: the client is a display and input device. It renders the
-- Snapshot and RunState the server pushes and sends Ready / Leave / RetryLoad intents with
-- no payload; it never decides a phase, a reward or a max HP. The Humanoid the server sized
-- with Armory.MaxHp is the only source for the HP bar.
--
-- Degrades like the hub: a profile that will not load shows the same safe-mode card instead
-- of a kick, a RunState that never arrives leaves the HUD in its lobby state, and the
-- summary card renders dashes rather than inventing numbers. C0 has no combat input, so
-- `CombatFx` is not connected yet (C1 owns it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local CombatHud = require(uiFolder:WaitForChild("CombatHud"))
local SummaryCard = require(uiFolder:WaitForChild("SummaryCard"))
local Toast = require(uiFolder:WaitForChild("Toast"))
local LoadScreen = require(uiFolder:WaitForChild("LoadScreen"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))

local HUMANOID_WAIT_SECONDS = 5

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

local function boot(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent
	local actionResult = remotesFolder:WaitForChild("ActionResult") :: RemoteEvent
	local runStateEvent = remotesFolder:WaitForChild("RunState") :: RemoteEvent
	local requestSnapshot = remotesFolder:WaitForChild("RequestSnapshot") :: RemoteEvent
	local requestRetryLoad = remotesFolder:WaitForChild("RequestRetryLoad") :: RemoteEvent
	local requestReady = remotesFolder:WaitForChild("RequestReady") :: RemoteEvent
	local requestLeave = remotesFolder:WaitForChild("RequestLeave") :: RemoteEvent

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
	})
	local summaryCard = SummaryCard.new(screenGui, {
		onReturn = function()
			fireIntent(requestLeave)
		end,
	})

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

	local function onRunState(payload: any): ()
		if not isRunState(payload) then
			return
		end
		local run = (payload :: any) :: Types.RunState
		-- The run carries an id; the human-readable name lives in the mission config both
		-- places share. A missing config degrades to the id, never to an error.
		local mission = Catalog.GetMissionById(run.missionId)
		hud.SetMission(if mission ~= nil then mission.name else run.missionId)
		hud.SetRunState(run)
		if run.phase == "summary" then
			summaryCard.Show(run.summary)
		else
			summaryCard.Hide()
		end
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
	end

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
