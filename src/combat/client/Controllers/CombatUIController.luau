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
-- and the C1 mission HUD (`boot`) for a build without the range's combat. That last one is
-- unreachable while ProvingGrounds.json ships and cannot fight any more (the server dropped
-- the C1 attack handlers in Wave 1); it warns if it is ever taken, and Wave 3 deletes it. A
-- crowd mission
-- mounts the range's HUD stack (crosshair, Feedback's overlay, AbilityBar, the vitals HUD,
-- BossBar; the touch buttons come with InputController and MovementController) under the run
-- layer of CombatHud with no Attack / stance / ability cluster: on a phone attacks are the
-- range's auto-fire and auto-swing. Wave banners, `bossDown` and `mentor` stay
-- CombatFxController's; there is no per-kill pop (ruling 23). The summary card and the Studio
-- keys are L1's (below); the C1 lever strip stays, its spawn buttons naming crowd kinds.
--
-- Mission layout (review of 2026-10-13; the ScreenGui is the viewport less the top inset):
--  * The boss bar sits in the top strip between the run header and the party list, shrunk to
--    it down to Theme.COMBAT_MISSION_BOSS_BAR_MIN_WIDTH (a 640 px landscape phone). Hung under
--    the header it would lie on the crosshair of a short landscape screen, so it only hangs
--    where that clears the crosshair box (portrait); on anything narrower still it goes under
--    the header at the left, ending short of the box.
--  * The vitals HUD's pointer ring is pulled in under the bar only while a boss is on show.
--
-- L1 (docs/INTERFACES.md "L1 contracts" -> Client; rulings 7, 8, 20 to 22, 25, 28, 30, 32, 33):
-- the dungeon place boots into a lobby camp with the MAP, and every run ends in a summary and
-- then the lobby again, never the city.
--  * `bootMission` mounts UI/MapScreen (a shared module: the hub mounts it in L4). It opens
--    whenever the phase becomes `lobby` and closes when the phase leaves it; M opens and closes
--    it in the lobby; while it is open the arrows pick a level and a difficulty and Enter
--    departs (RequestStartLevel). The first open is seeded (a proving build: the config's
--    level and difficulty; else the first open node with no star), so one click or one key
--    departs. Only the leader's Depart is live; a refusal frees it and says why.
--  * The level, not the mission: the header shows RunState.levelName and the difficulty, the
--    wallet's material chip is RunState.material, CrowdRenderer is handed the level's cap and,
--    whenever it changes, the crowd's floors (L1b: RunState.floors, one per camp).
--  * The summary card shows for a RunState that carries a `result`; Enter (or its button) is
--    "Back to camp" (RequestAbandon), and Abandon in a live run is the same intent.
--  * Studio keys: N finishes the stage, B jumps to the boss, G steps the gear (RequestDebug).
--  * The C1 `boot` is still unreachable and still cannot fight; it is kept typechecking against
--    the level's RunState until L4 deletes it.
--
-- L1 fix round (docs/prompts/l1-fix-round.md, part U), all in `bootMission`:
--  * Abandon's key is Backspace, pressed twice (CombatHud.PressAbandon), in every live phase
--    and never while a text box has the keyboard. While it is armed the camera keeps a cursor
--    the player freed with Alt.
--  * A body the server has placed (CameraController.OnPlaced, from the server's own signal on
--    the character) faces the way forward: along the level's route from the point the server
--    named, or to the lobby camp's centre. It is turned as soon as the word arrives, not when
--    the body does. The same is done again when a RunState names a new level while that word
--    is still news, because the two arrive in either order.
--  * A Depart pressed during the server's start cooldown after a return is held by the map and
--    sent when the cooldown ends (MapScreen.Rest); it no longer does nothing.
--  * One message per event: a banner is not mirrored into a toast, and the banner is given a
--    frame that keeps clear of the run header's column (placeBanner).
--  * A key that was already down when the map's or the summary's keys were bound is not sunk,
--    so its release still reaches the movement keys under them.
--  * The Studio strip is off the screen while the map is open, and a client with no MapState
--    asks for its snapshot again, a few times.
--
-- L1b (docs/INTERFACES.md "L1b contracts — the living road" -> Client), in `bootMission`:
--  * The crowd has a floor per camp: RunState.floors is handed to CrowdRenderer.SetFloors
--    whenever it differs from what was handed last (`{}` in the lobby). The one-floor
--    `applyFloor` of L1 is gone.
--  * Nothing is banked any more: the server sends the wallet itself, at most once a second, as
--    kills pay. Only the end of a run still asks for a fresh Snapshot.
--  * CampFx's "Checkpoint" notice is the HUD's notice line under the wallet.

local ContextActionService = game:GetService("ContextActionService")
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
local VitalsHud = require(uiFolder:WaitForChild("VitalsHud"))
local MapScreen = require(uiFolder:WaitForChild("MapScreen"))
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
local CampFx = require(script.Parent:WaitForChild("CampFx"))
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
-- L1 ruling 33, Studio only: the keys, the lever each sends and the line that names them.
-- L1b-W4-31: on the road N stops at the next open camp's approach before the boss room.
local DEBUG_KEYS: { [Enum.KeyCode]: { lever: string, value: string } } = {
	[Enum.KeyCode.N] = { lever = "skip", value = "stage" },
	[Enum.KeyCode.B] = { lever = "skip", value = "boss" },
	[Enum.KeyCode.G] = { lever = "gear", value = "next" },
}
local DEBUG_HINT = "N next camp · B boss · G gear"
-- Run phases with nothing left to fight: the summary card has the screen.
local RUN_OVER_PHASES: { [string]: boolean } = { summary = true, ended = true }
-- L1 ruling 8: the five phases in which a member may act.
local LIVE_PHASES: { [string]: boolean } =
	{ travel = true, gate = true, wave = true, boss = true, breather = true }
-- L1, the map. Its keys are bound only while it is open (the arrows and Enter; the d-pad and A
-- on a gamepad), M opens and closes it in the lobby, and Enter on the summary card is "Back to
-- camp". Up is the harder difficulty.
local HOLD_MAP = "map"
local DEFAULT_MAP_NAME = "Expeditions"
-- RunResult.reason of the trip home, whose card shows whatever the phase.
local LEAVE_REASON = "leave"
local MAP_ACTION = "ExpeditionMapKeys"
local SUMMARY_ACTION = "ExpeditionSummaryKeys"
local MAP_TOGGLE_KEY = Enum.KeyCode.M
local MAP_KEY_HINT = "← → level · ↑ ↓ difficulty · Enter depart"
local MAP_STEP_KEYS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.Up] = Vector2.new(0, 1),
	[Enum.KeyCode.Down] = Vector2.new(0, -1),
	[Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
	[Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
	[Enum.KeyCode.DPadUp] = Vector2.new(0, 1),
	[Enum.KeyCode.DPadDown] = Vector2.new(0, -1),
}
local CONFIRM_KEYS: { Enum.KeyCode } =
	{ Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonA }
local MAP_KEYS: { Enum.KeyCode } = table.clone(CONFIRM_KEYS)
for key in MAP_STEP_KEYS do
	table.insert(MAP_KEYS, key)
end
-- Which of those are a gamepad's: whether one is down is asked of the pad, not the keyboard.
local PAD_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.DPadRight] = true,
	[Enum.KeyCode.DPadUp] = true,
	[Enum.KeyCode.DPadDown] = true,
}
-- Fix round, ruling 7: Abandon's key, pressed twice. A gamepad has none yet (carried).
local ABANDON_KEY = Enum.KeyCode.Backspace
-- What a refused RequestStartLevel tells the player (ActionResult.reason).
local START_ACTION = "startLevel"
local START_REFUSALS: { [string]: string } = {
	notLeader = "Only the leader can depart",
	busy = "Not ready yet",
	locked = "That level is locked",
	unavailable = "Can't start that level",
}

local CombatUIController = {}

-- Only a table with the fields the HUD reads is trusted; RunState arrives from the network.
local function isRunState(payload: any): boolean
	return typeof(payload) == "table"
		and typeof(payload.phase) == "string"
		and typeof(payload.levelId) == "string"
		and typeof(payload.levelName) == "string"
		and typeof(payload.difficulty) == "string"
		and typeof(payload.material) == "string"
		and typeof(payload.stage) == "number"
		and typeof(payload.stageName) == "string"
		and typeof(payload.camps) == "number"
		and typeof(payload.campsCleared) == "number"
		and typeof(payload.left) == "number"
		and typeof(payload.floors) == "table"
		and typeof(payload.leaderUserId) == "number"
		and typeof(payload.wave) == "number"
		and typeof(payload.waves) == "number"
		and typeof(payload.tempo) == "number"
		and typeof(payload.party) == "table"
end

-- L1: a RunState's `result`, for the summary card; nil and anything malformed show no card.
local function isRunResult(payload: any): boolean
	return typeof(payload) == "table"
		and typeof(payload.levelName) == "string"
		and typeof(payload.difficulty) == "string"
		and typeof(payload.reason) == "string"
		and typeof(payload.campsCleared) == "number"
		and typeof(payload.camps) == "number"
		and typeof(payload.star) == "boolean"
end

-- L1: the crowd kinds a level rewards, which are the kinds it can field: what the Studio
-- strip's spawn buttons name. A level file that names a `mission` (the Raider Arena) takes
-- them from that mission's crowd block. No level (the lobby) has none.
local function rewardedKinds(levelId: string): { string }
	local kinds: { string } = {}
	local file = if levelId ~= "" then Catalog.GetLevelFile(levelId) else nil
	if file == nil then
		return kinds
	end
	local crowd = file.crowd
	local rewards = if crowd ~= nil then crowd.rewards else nil
	local missionId = file.mission
	if rewards == nil and missionId ~= nil then
		local mission = Catalog.GetMissionById(missionId)
		local block = if mission ~= nil then mission.crowd else nil
		rewards = if block ~= nil then block.rewards else nil
	end
	if rewards ~= nil then
		for kind in rewards do
			table.insert(kinds, kind)
		end
	end
	return kinds
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
		-- P5: or anything else that stops a cast (a mission's idle phases, the wait on the
		-- pad). One rule, InputController's, so a tile never looks ready while Q does nothing.
		isBusy = function(): boolean
			return InputController.IsBusy() or not InputController.CanAct()
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

-- Where a mission's boss bar goes, in px of the HUD ScreenGui (see the header's layout notes).
-- `cross` = the crosshair's centre in the same px. Returns the bar's bottom edge when the bar
-- stands over the crosshair's column (what the pointer ring must then keep under), nil when it
-- stands to the left of it.
local function placeMissionBoss(
	bossBar: BossBar.BossBarHandle,
	scale: number,
	size: Vector2,
	edges: CombatHud.HudEdges,
	cross: Vector2
): number?
	local margin = Theme.SCREEN_MARGIN * scale
	local width = Theme.COMBAT_RANGE_BOSS_BAR_WIDTH * scale
	local strip = edges.partyLeft - edges.headerRight - 2 * margin
	if strip >= Theme.COMBAT_MISSION_BOSS_BAR_MIN_WIDTH * scale then
		width = math.min(width, strip)
		-- Not math.clamp: squeezed to the strip the two bounds are the same number, and
		-- rounding can leave the lower one a hair above the upper, which math.clamp throws
		-- on. This cannot: crossed by a hair, either bound is the answer.
		local centreX = math.min(
			math.max(size.X / 2, edges.headerRight + margin + width / 2),
			edges.partyLeft - margin - width / 2
		)
		return bossBar.SetRect(scale, centreX, margin, width)
	end
	local top = edges.headerBottom + margin
	local boxHalf = Theme.COMBAT_RANGE_CROSSHAIR_SIZE / 2 * scale
	local bottom = bossBar.SetRect(scale, size.X / 2, top, math.min(width, size.X - 2 * margin))
	if bottom + margin <= cross.Y - boxHalf then
		return bottom -- portrait: the whole bar is clear above the crosshair box
	end
	-- A landscape screen too narrow for the strip: under the header, short of the box.
	width = math.max(math.min(width, cross.X - boxHalf - 2 * margin), 0)
	bossBar.SetRect(scale, margin + width / 2, top, width)
	return nil
end

-- Fix round, item 5. Where the banner goes, in px of the viewport (CombatFxController's overlay
-- ignores the top-bar inset; `size`, `edges` and `bossBottom` are the HUD ScreenGui's, which
-- starts under it). Centred near the top, as it always was, wherever that is clear of the run
-- header's block (header, wallet, the notice line): any monitor. Where it is not:
--  * landscape (a phone): the block is a column at the left, and the banner takes the room to
--    the right of it and of the crosshair's box (on a screen that short the banner reaches down
--    to the box);
--  * portrait: the block spans the top, and the banner goes under it.
-- Wherever it lands it starts under the boss bar, when that stands over the middle of the
-- screen (`bossBottom`): on a monitor the bar is far above it already.
local function placeBanner(
	scale: number,
	size: Vector2,
	viewport: Vector2,
	inset: Vector2,
	edges: CombatHud.HudEdges,
	bossBottom: number?
): ()
	local margin = Theme.SCREEN_MARGIN * scale
	local width = math.min(Theme.COMBAT_BANNER_WIDTH * scale, math.max(size.X - 2 * margin, 0))
	local centreX = size.X / 2
	local top = viewport.Y * Theme.COMBAT_BANNER_TOP_FRACTION
	local blockBottom = inset.Y + edges.noticeBottom + margin
	if top < blockBottom and centreX - width / 2 < edges.headerRight + margin then
		if size.X > size.Y then
			local boxRight = viewport.X / 2 + Theme.COMBAT_RANGE_CROSSHAIR_SIZE / 2 * scale
			local left = math.max(edges.headerRight, boxRight) + margin
			width = math.max(math.min(width, size.X - margin - left), 0)
			centreX = left + width / 2
		else
			top = blockBottom
		end
	end
	if bossBottom ~= nil then
		top = math.max(top, inset.Y + bossBottom + margin)
	end
	CombatFxController.SetBannerLayout(scale, centreX, top, width)
end

-- Fix round, item 7. The keys of `keys` that are down right now. An action bound over a key
-- that is already down must not sink it: the release would never reach the binding under it,
-- and a character walking on an arrow key when the map opened would walk on for good.
local function keysDown(keys: { Enum.KeyCode }): { [Enum.KeyCode]: boolean }
	local held: { [Enum.KeyCode]: boolean } = {}
	for _, key in keys do
		local down = if PAD_KEYS[key]
			then UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
			else UserInputService:IsKeyDown(key)
		if down then
			held[key] = true
		end
	end
	return held
end

-- True when this input is one of those keys (the handler then passes it on untouched); the
-- key leaves the set when it is let go, and from its next press it is the action's own. A
-- press of a key still in the set means its release was never seen (the window lost focus
-- with it down): that press is a new one, and the action's.
local function passesHeld(
	held: { [Enum.KeyCode]: boolean },
	state: Enum.UserInputState,
	input: InputObject
): boolean
	if held[input.KeyCode] ~= true then
		return false
	end
	if state == Enum.UserInputState.Begin then
		held[input.KeyCode] = nil
		return false
	end
	if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		held[input.KeyCode] = nil
	end
	return true
end

-- Fix round, item 2. The way forward along a level's route from `position`, as a point to look
-- at, and the flat distance from `position` to the route (so the caller can tell a body in the
-- level from one in the lobby camp). Forward is the route's own way where the body stands: on
-- the nearest stretch, toward that stretch's end, or, within COMBAT_FORWARD_NEAR_STUDS of that
-- end, the way the next stretch runs. So a body put beside the road looks along it, not across
-- it at the nearest point. nil = the route has no stretch.
local function routeForward(route: { Types.LevelRoutePoint }, position: Vector3): (Vector3?, number)
	local nearest = 0
	local distance = math.huge
	local onward = Vector3.zero
	for index = 1, #route - 1 do
		local a, b = route[index], route[index + 1]
		local span = Vector3.new(b.x - a.x, 0, b.z - a.z)
		local lengthSquared = span:Dot(span)
		if lengthSquared > 0 then
			local offset = Vector3.new(position.X - a.x, 0, position.Z - a.z)
			local share = math.clamp(offset:Dot(span) / lengthSquared, 0, 1)
			local gap = (offset - span * share).Magnitude
			if gap < distance then
				nearest = index
				distance = gap
				onward = span * (1 - share)
			end
		end
	end
	if nearest == 0 then
		return nil, math.huge
	end
	if onward.Magnitude < Theme.COMBAT_FORWARD_NEAR_STUDS then
		-- At the stretch's end: the next stretch with any length says which way; with none
		-- left (the last camp), forward stays the way this one ran.
		local last = route[nearest]
		local ended = route[nearest + 1]
		onward = Vector3.new(ended.x - last.x, 0, ended.z - last.z)
		for index = nearest + 1, #route - 1 do
			local a, b = route[index], route[index + 1]
			local span = Vector3.new(b.x - a.x, 0, b.z - a.z)
			if span.Magnitude > 0 then
				onward = span
				break
			end
		end
	end
	return position + onward, distance
end

-- Fix round, item 2. What a body the server has just put at `position` should face: the way
-- forward in the level being played, or the lobby camp's centre, whichever of the two places it
-- stands in (a member who waits in the camp while a run is live is in the camp). nil = nothing
-- to turn to.
local function forwardPoint(
	map: Types.ExpeditionsConfig?,
	levelId: string,
	position: Vector3
): Vector3?
	local lobbyAt: Vector3? = nil
	local lobbyDistance = math.huge
	local lobby = if map ~= nil then Catalog.GetLevelLayout(map.lobby.layout) else nil
	-- A layout is a JSON file: what is read from it is checked, because this runs inside the
	-- camera's frame and the RunState handler, and neither may stop on a file's mistake.
	if lobby ~= nil and typeof(lobby.start) == "table" then
		local centre = Vector3.new(lobby.start.x, lobby.start.y, lobby.start.z)
		lobbyAt = centre
		lobbyDistance = Vector3.new(centre.X - position.X, 0, centre.Z - position.Z).Magnitude
	end
	if levelId == "" then
		return lobbyAt -- no level is live: the lobby camp is all there is
	end
	local file = Catalog.GetLevelFile(levelId)
	local layout = if file ~= nil then Catalog.GetLevelLayout(file.layout) else nil
	local target: Vector3? = nil
	local distance = math.huge
	if layout ~= nil and layout.arena ~= nil then
		-- A layout that names an arena holds nothing else. The server turns the arena into one
		-- camp centred on the world origin (LevelGeometry.FromArena, ruling 13): forward is
		-- its middle, and the body is in it when it is over its floor.
		local arena = Catalog.GetArenaLayout(layout.arena)
		if arena ~= nil then
			target = Vector3.zero
			distance = math.max(
				math.abs(position.X) - arena.size.x / 2,
				math.abs(position.Z) - arena.size.z / 2,
				0
			)
		end
	elseif layout ~= nil and typeof(layout.route) == "table" then
		target, distance = routeForward(layout.route, position)
	end
	if target == nil then
		-- A live level with no way forward to read: where the body stands cannot be told, so
		-- nothing is turned.
		return nil
	end
	return if distance <= lobbyDistance then target else lobbyAt
end

-- A boot's first layout pass. It must never take the boot down with it: the snapshot request
-- and the remote wiring come after it, and a HUD laid out wrong is still a HUD.
local function firstLayout(applyLayout: () -> ()): ()
	-- Cast: the analyzer wants a second value from pcall of a function that returns none.
	local ok, message = pcall(applyLayout :: () -> any)
	if not ok then
		warn("[CombatUIController] the HUD's first layout failed: " .. tostring(message))
	end
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
	firstLayout(applyLayout)
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

-- The C1 HUD. Unreachable while ProvingGrounds.json ships, and it cannot fight (see the header
-- and CameraController.IsCrowdCombat); kept reading the level's RunState until L4 deletes it.
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
	local material = ""

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
		onBack = function() end,
		onReturn = function()
			fireIntent(requestLeave)
		end,
		canReturn = true,
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
		-- Wallet: cash and Valor are always shown; the material chip needs the level, so it
		-- stays blank until a RunState names one.
		local materials = combat.materials
		local materialName = material
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
		if run.material ~= material then
			-- The wallet's material chip is the level's, and the Snapshot in hand was read
			-- before this RunState named it. Ask for a fresh one.
			material = run.material
			CombatFxController.SetMaterial(material)
			requestSnapshot:FireServer()
		end
		hud.SetMission(if run.levelName ~= "" then run.levelName else DEFAULT_MAP_NAME)
		CameraController.SetPhase(run.phase)
		hud.SetRunState(run)
		InputController.SetPhase(run.phase)
		if debugPanel ~= nil then
			debugPanel.SetWave(run.wave)
			debugPanel.SetKinds(rewardedKinds(run.levelId))
		end
		CombatFxController.SetParty(run.party)
		local result = run.result
		if isRunResult(result) and result ~= nil then
			if lastPhase ~= "summary" and run.phase == "summary" then
				SoundController.Play("runEnd")
			end
			local returnIn = run.returnIn
			summaryCard.Show(run.summary, result, {
				partySize = #run.party,
				returnIn = if typeof(returnIn) == "number" then returnIn else nil,
				canBack = false,
				waves = run.waves,
				difficultyName = run.difficulty,
				mapName = DEFAULT_MAP_NAME,
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

-- The dungeon place (L1): a lobby camp with the map, a level, a summary, and the lobby again.
-- The run layer is CombatHud's; the fight is the range's. See the header for what is mounted.
-- One function, so its state lives in tables: Studio gives a function 200 local registers.
local function bootMission(): ()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local studio = RunService:IsStudio()
	-- A proving build never goes to the city: the trip home kicks from Studio (ruling 22).
	local proving = CombatMode.IsProving()
	local combatConfig = Catalog.GetCombatConfig()
	local expeditions = Catalog.GetExpeditionsConfig()
	-- The load card needs the pointer until the profile arrives.
	CameraController.SetCursorHold(HOLD_LOAD, true)

	-- Every remote is made at the server's boot, so the waits with a timeout return at once;
	-- the timeout only keeps a client of an older server build from hanging here.
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local timeout = Theme.COMBAT_REMOTE_WAIT_SECONDS
	local remotes = {
		stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent,
		actionResult = remotesFolder:WaitForChild("ActionResult") :: RemoteEvent,
		runState = remotesFolder:WaitForChild("RunState") :: RemoteEvent,
		requestSnapshot = remotesFolder:WaitForChild("RequestSnapshot") :: RemoteEvent,
		requestRetryLoad = remotesFolder:WaitForChild("RequestRetryLoad") :: RemoteEvent,
		requestLeave = remotesFolder:WaitForChild("RequestLeave") :: RemoteEvent,
		mapState = remotesFolder:WaitForChild("MapState", timeout) :: RemoteEvent?,
		requestStartLevel = remotesFolder:WaitForChild("RequestStartLevel", timeout) :: RemoteEvent?,
		requestAbandon = remotesFolder:WaitForChild("RequestAbandon", timeout) :: RemoteEvent?,
		requestDebug = remotesFolder:WaitForChild("RequestDebug", timeout) :: RemoteEvent?,
	}

	-- Above the range layer, so the run layer, the map, cards and toasts draw over the
	-- crosshair. The range layer ignores the top-bar inset, so its centre is the camera's
	-- centre line.
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

	-- What the last RunState, Snapshot and MapState said, as far as the next one is compared
	-- against it. `departToken` names the latest reason Depart is busy, so an older timer
	-- cannot free a newer wait. `floors` are the crowd's floors as last handed to CrowdRenderer
	-- (L1b: one RunFloor per camp, copied, so the next RunState is compared by value).
	-- Fix round: `mapStateSeen` = a MapState has arrived (until then the snapshot is asked for
	-- again); `mapHeld` and `summaryHeld` are the keys that were down when those actions were
	-- bound, which pass through until let go (keysDown); `placedPoint` / `placedAt` are the last
	-- feet point the server said it put the body at, and the os.clock() it said so.
	local st = {
		placedPoint = nil :: Vector3?,
		placedAt = 0,
		loaded = false,
		phase = "",
		wave = 0,
		stage = 0,
		levelId = "",
		material = "",
		prewarmed = 0,
		mapSeeded = false,
		mapStateSeen = false,
		departToken = 0,
		lastIntentTime = 0,
		mapKeys = false,
		summaryKeys = false,
		mapHeld = {} :: { [Enum.KeyCode]: boolean },
		summaryHeld = {} :: { [Enum.KeyCode]: boolean },
		bossShown = false,
		bossLimit = nil :: number?,
		vitalsLayout = nil :: VitalsHud.Layout?,
		floors = {} :: { Types.RunFloor },
		wallet = { cash = 0, valor = 0, materials = {} :: { [string]: any } },
	}
	local mapName = if expeditions ~= nil then expeditions.name else DEFAULT_MAP_NAME

	-- One debounce window for every button and key that sends an intent (review of
	-- 2026-09-17): ten taps must not become ten intents against the rate limit.
	local function debounced(): boolean
		local now = os.clock()
		if now - st.lastIntentTime < Theme.ACTION_DEBOUNCE_SECONDS then
			return false
		end
		st.lastIntentTime = now
		return true
	end
	local function leave(): ()
		if debounced() then
			remotes.requestLeave:FireServer()
		end
	end
	-- Ruling 21: in a live run this ends it (every kill is already paid); in the summary it ends the
	-- wait. The server drops it from anyone who may not.
	local function abandon(): ()
		local remote = remotes.requestAbandon
		if remote ~= nil and debounced() then
			remote:FireServer()
		end
	end

	local toast = Toast.new(screenGui)
	local loadScreen = LoadScreen.new(screenGui, {
		onRetry = function()
			remotes.requestRetryLoad:FireServer()
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
	local mapScreen: MapScreen.MapScreenHandle? = nil

	-- Depart is busy until `seconds` pass, unless something newer made it busy or free first.
	local function busyFor(seconds: number): ()
		local screen = mapScreen
		if screen == nil then
			return
		end
		st.departToken += 1
		local token = st.departToken
		screen.SetBusy(true)
		task.delay(seconds, function()
			if token == st.departToken then
				screen.SetBusy(false)
			end
		end)
	end
	local function freeDepart(): ()
		st.departToken += 1
		local screen = mapScreen
		if screen ~= nil then
			screen.SetBusy(false)
		end
	end

	-- While the map is open the arrows pick a level and a difficulty and Enter departs. Bound
	-- above the movement keys and sunk, so an arrow does not also turn the camera. A key that
	-- was down before the map opened is not the map's until it is let go.
	local function onMapKey(
		_action: string,
		state: Enum.UserInputState,
		input: InputObject
	): Enum.ContextActionResult
		if passesHeld(st.mapHeld, state, input) then
			return Enum.ContextActionResult.Pass
		end
		local screen = mapScreen
		if state == Enum.UserInputState.Begin and screen ~= nil then
			local step: Vector2? = MAP_STEP_KEYS[input.KeyCode]
			if step ~= nil then
				screen.Step(step.X, step.Y)
			else
				screen.Confirm()
			end
		end
		return Enum.ContextActionResult.Sink
	end
	local function bindMapKeys(bound: boolean): ()
		if bound == st.mapKeys then
			return
		end
		st.mapKeys = bound
		if bound then
			st.mapHeld = keysDown(MAP_KEYS)
			ContextActionService:BindActionAtPriority(
				MAP_ACTION,
				onMapKey,
				false,
				Enum.ContextActionPriority.High.Value + 1,
				table.unpack(MAP_KEYS)
			)
		else
			ContextActionService:UnbindAction(MAP_ACTION)
		end
	end
	-- On the summary card Enter is "Back to camp", for whoever may end the wait.
	local function onSummaryKey(
		_action: string,
		state: Enum.UserInputState,
		input: InputObject
	): Enum.ContextActionResult
		if passesHeld(st.summaryHeld, state, input) then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			abandon()
		end
		return Enum.ContextActionResult.Sink
	end
	local function bindSummaryKeys(bound: boolean): ()
		if bound == st.summaryKeys then
			return
		end
		st.summaryKeys = bound
		if bound then
			st.summaryHeld = keysDown(CONFIRM_KEYS)
			ContextActionService:BindActionAtPriority(
				SUMMARY_ACTION,
				onSummaryKey,
				false,
				Enum.ContextActionPriority.High.Value + 1,
				table.unpack(CONFIRM_KEYS)
			)
		else
			ContextActionService:UnbindAction(SUMMARY_ACTION)
		end
	end

	-- Studio only, by contract: a live client never builds the strip, and the server ignores
	-- the remote even if one were forged. Built before the map, which takes it off the screen
	-- while it is open.
	local debugPanel = if studio
		then DebugPanel.new(screenGui, {
			onLever = function(lever: string, value: any)
				local remote = remotes.requestDebug
				if remote ~= nil then
					remote:FireServer(lever, value)
				end
			end,
			onToggle = function(open: boolean)
				CameraController.SetCursorHold(HOLD_DEBUG, open)
			end,
		})
		else nil

	if expeditions ~= nil then
		mapScreen = MapScreen.new(screenGui, expeditions, {
			onDepart = function(levelId: string, difficulty: string)
				local remote = remotes.requestStartLevel
				if remote == nil then
					freeDepart()
					toast.Show(START_REFUSALS.unavailable, Theme.TOAST_ERROR_SECONDS, true)
					return
				end
				remote:FireServer(levelId, difficulty)
				-- The answer is a refusal or the phase leaving the lobby. Should neither come,
				-- Depart is live again after a while rather than dead for the session.
				busyFor(Theme.MAP_DEPART_TIMEOUT_SECONDS)
			end,
			onOpenChanged = function(open: boolean)
				CameraController.SetCursorHold(HOLD_MAP, open)
				bindMapKeys(open)
				-- The strip's tab drew over the map in the phone emulator (both are sheets of
				-- one ZIndex tier): it is away while the map has the screen.
				if debugPanel ~= nil then
					debugPanel.SetVisible(not open)
				end
			end,
			onReturn = if proving then nil else leave,
			keyHint = if UserInputService.KeyboardEnabled then MAP_KEY_HINT else nil,
		})
	else
		warn(
			"[CombatUIController] Config/Expeditions is missing: no map, the lobby is all there is"
		)
	end
	local function openMap(): ()
		local screen = mapScreen
		if screen ~= nil and st.phase == "lobby" then
			screen.Open()
		end
	end

	-- The cluster's handlers are never pressed (it is not shown); they route to the range path
	-- like every other entry point, so a stray call still does the right thing.
	local hud = CombatHud.new(screenGui, {
		onMap = if mapScreen ~= nil then openMap else nil,
		onLeave = leave,
		onAbandon = abandon,
		-- Fix round: Abandon has a key, named on its button, and while it waits for its second
		-- press the camera keeps a cursor the player freed with Alt to click it.
		abandonKey = if UserInputService.KeyboardEnabled then ABANDON_KEY.Name else nil,
		onAbandonArmed = CameraController.KeepAltFree,
		onStance = InputController.ToggleStance,
		onAttackDown = InputController.AttackDown,
		onAttackUp = InputController.AttackUp,
		onAbility = InputController.UseAbility,
		actions = false,
		runButtons = not proving,
		keyHint = if studio then DEBUG_HINT else nil,
	})
	local summaryCard = SummaryCard.new(screenGui, {
		onBack = abandon,
		onReturn = leave,
		canReturn = not proving,
	})

	-- A proving build opens on the level and the difficulty the config names (ruling 32), so
	-- one click or one key departs. Any other build is seeded by its first MapState.
	if proving and mapScreen ~= nil and expeditions ~= nil and combatConfig ~= nil then
		local level = combatConfig.debug.provingLevel
		local difficulty = combatConfig.debug.provingDifficulty
		for _, node in expeditions.nodes do
			if node.level ~= nil and node.level == level then
				-- An unknown difficulty is no pick: the map then keeps the node's first.
				mapScreen.Select(node.id, difficulty)
				st.mapSeeded = true
				break
			end
		end
	end

	-- Fix round, item 2: a body the server has placed looks the way forward (see forwardPoint).
	-- The camera says when and where; this only knows which level is live. The look starts at
	-- `position`, where the body is or is about to be, never at wherever it happens to stand.
	local function faceFrom(position: Vector3): ()
		local target = forwardPoint(expeditions, st.levelId, position)
		if target ~= nil then
			CameraController.LookToward(target, position)
		end
	end
	-- The feet point of the last move the server announced, while that is still news.
	local function recentPlace(): Vector3?
		local point = st.placedPoint
		if point ~= nil and os.clock() - st.placedAt <= Theme.COMBAT_PLACED_TIMEOUT_SECONDS then
			return point
		end
		return nil
	end
	CameraController.OnPlaced(function(position: Vector3, signalled: boolean, far: boolean)
		if signalled then
			-- A short nudge (a camp's close putting the player at its entry, a few studs) leaves
			-- the view alone: a player who turned round to watch the gates shut must not be
			-- swung down the road as the wave starts. Only a far move is a new place to face
			-- from, and only that is remembered for a RunState that names the level after it.
			if far then
				-- The server's word: turn now, from the point it named. The body follows.
				st.placedPoint = position
				st.placedAt = os.clock()
				faceFrom(position)
			end
		elseif recentPlace() == nil then
			-- A body the camera has only just picked up, and no word about it (a server that
			-- sends none, or one that did not move it): forward from where it stands. With
			-- a word still fresh that look is the better one, and the camera has taken it.
			faceFrom(position)
		end
	end)

	-- Wallet: cash and Valor always; the material chip is the level's (RunState.material), so
	-- it is blank in the lobby. Never predicted: every bank re-sends the Snapshot it shows.
	local function paintWallet(): ()
		local wallet = st.wallet
		local owned = if st.material ~= "" then wallet.materials[st.material] else nil
		hud.SetWallet(
			wallet.cash,
			st.material,
			if typeof(owned) == "number" then owned else 0,
			wallet.valor
		)
	end

	local function onSnapshot(payload: { [string]: any }): ()
		local state = payload.state
		if typeof(state) ~= "table" then
			return
		end
		if not st.loaded then
			st.loaded = true
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
		local wallet = st.wallet
		wallet.cash = if typeof(state.cash) == "number" then state.cash else 0
		wallet.valor = if typeof(combat.valor) == "number" then combat.valor else 0
		wallet.materials = if typeof(combat.materials) == "table" then combat.materials else {}
		paintWallet()
	end

	local function onStateChanged(payload: any): ()
		if typeof(payload) ~= "table" then
			return
		end
		if payload.kind == "snapshot" then
			onSnapshot(payload)
		elseif payload.kind == "loadStatus" and not st.loaded then
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

	-- The first MapState of a session picks what the map opens on: the first open node, in
	-- config order, that has no star, at its lowest difficulty; failing that the first open
	-- node with a difficulty still to clear, at the lowest such. Later the selection is the
	-- player's.
	local function seedMap(state: Types.MapState): ()
		local screen = mapScreen
		if screen == nil or expeditions == nil or st.mapSeeded then
			return
		end
		local fallback: Types.MapNodeState? = nil
		for _, node in state.nodes do
			if typeof(node) == "table" and node.open == true and typeof(node.stars) == "table" then
				if #node.stars == 0 then
					st.mapSeeded = true
					screen.Select(node.id, nil)
					return
				end
				fallback = fallback or node
			end
		end
		if fallback ~= nil then
			st.mapSeeded = true
			for _, difficulty in expeditions.difficulties do
				if table.find(fallback.stars, difficulty) == nil then
					screen.Select(fallback.id, difficulty)
					return
				end
			end
			screen.Select(fallback.id, nil)
		end
	end

	local function onMapState(payload: any): ()
		local screen = mapScreen
		if
			screen == nil
			or typeof(payload) ~= "table"
			or payload.kind ~= "map"
			or typeof(payload.nodes) ~= "table"
		then
			return
		end
		local state = payload :: Types.MapState
		st.mapStateSeen = true
		screen.SetState(state)
		seedMap(state)
	end

	-- L1b: the crowd's floors, one per camp in floor-index order, handed on whenever they
	-- differ from the last ones by value (a RunState comes four times a second and carries them
	-- every time). The lobby's `{}` empties them. A malformed entry ends the list there, as
	-- CrowdRenderer.SetFloors reads it. L1b Wave 4: a floor's chase-region `cells` travel with
	-- it (read by CrowdRenderer.ReadCells, so a malformed list is dropped the same way) and are
	-- compared by value too: they bound the drawn charge (L1b-W4-33). L1c-5a: so does `locks`,
	-- and the same list goes to the camera, which keeps its boom out of a locking camp.
	local function sameCells(a: { Types.CampRect }?, b: { Types.CampRect }?): boolean
		if a == nil or b == nil then
			return a == b
		end
		if #a ~= #b then
			return false
		end
		for index, rect in a do
			local other = b[index]
			if
				rect.x ~= other.x
				or rect.z ~= other.z
				or rect.hx ~= other.hx
				or rect.hz ~= other.hz
			then
				return false
			end
		end
		return true
	end

	local function applyFloors(list: { any }): ()
		local held = st.floors
		local fresh: { Types.RunFloor } = {}
		for _, entry in list do
			if
				typeof(entry) ~= "table"
				or typeof(entry.x) ~= "number"
				or typeof(entry.y) ~= "number"
				or typeof(entry.z) ~= "number"
				or typeof(entry.hx) ~= "number"
				or typeof(entry.hz) ~= "number"
			then
				break
			end
			table.insert(fresh, {
				x = entry.x,
				y = entry.y,
				z = entry.z,
				hx = entry.hx,
				hz = entry.hz,
				cells = CrowdRenderer.ReadCells(entry.cells),
				locks = if entry.locks == true then true else nil,
				ceiling = if typeof(entry.ceiling) == "number" then entry.ceiling else nil,
			})
		end
		local same = #fresh == #held
		if same then
			for index, floor in fresh do
				local old = held[index]
				if
					floor.x ~= old.x
					or floor.y ~= old.y
					or floor.z ~= old.z
					or floor.hx ~= old.hx
					or floor.hz ~= old.hz
					or floor.locks ~= old.locks
					or floor.ceiling ~= old.ceiling
					or not sameCells(floor.cells, old.cells)
				then
					same = false
					break
				end
			end
		end
		if same then
			return
		end
		st.floors = fresh
		CrowdRenderer.SetFloors(fresh)
		CameraController.SetFloors(fresh)
	end

	local function onRunState(payload: any): ()
		if not isRunState(payload) then
			return
		end
		local run = (payload :: any) :: Types.RunState
		local phase = run.phase
		local last = st.phase
		local live = LIVE_PHASES[phase] == true
		local over = RUN_OVER_PHASES[phase] == true

		-- The level, not the mission: its kinds for the Studio strip, its pool of bodies, its
		-- material for the wallet and the reward pops, its floor for the crowd.
		if run.levelId ~= st.levelId then
			st.levelId = run.levelId
			st.prewarmed = 0
			if debugPanel ~= nil then
				debugPanel.SetKinds(rewardedKinds(run.levelId))
			end
			-- A new level (or the lobby again) comes with a move of the body, and the server's
			-- word of the move and this RunState arrive in either order: a word that came first
			-- was read against the level before. Face forward again from the point it named,
			-- now that the level is known.
			local placed = recentPlace()
			if placed ~= nil then
				faceFrom(placed)
			end
		end
		if last == "" and recentPlace() == nil then
			-- The first RunState. This HUD booted after the camera picked the body up, so it
			-- heard neither the server's word nor the pick-up; the body stands where it was
			-- put, and forward is told from there.
			local character = player.Character
			local root = if character ~= nil
				then character:FindFirstChild("HumanoidRootPart")
				else nil
			if root ~= nil and root:IsA("BasePart") then
				faceFrom(root.Position)
			end
		end
		if typeof(run.maxAlive) == "number" and run.maxAlive > st.prewarmed then
			st.prewarmed = run.maxAlive
			CrowdRenderer.Prewarm(run.maxAlive)
		end
		if run.material ~= st.material then
			st.material = run.material
			CombatFxController.SetMaterial(run.material)
			paintWallet()
		end
		applyFloors(run.floors)

		local difficultyName = run.difficulty
		if expeditions ~= nil then
			difficultyName = expeditions.difficultyNames[run.difficulty] or run.difficulty
		end
		-- The level's name is the title; the difficulty has a chip of its own beside it.
		if run.levelName == "" then
			hud.SetMission(mapName, nil)
		else
			hud.SetMission(run.levelName, difficultyName)
		end
		CameraController.SetPhase(phase)
		hud.SetRunState(run)
		CombatFxController.SetParty(run.party)
		if debugPanel ~= nil then
			debugPanel.SetWave(run.wave)
		end

		local userId = player.UserId
		local humans = 0
		local waiting = false
		for _, member in run.party do
			if typeof(member) ~= "table" then
				continue
			end
			if not member.bot then
				humans += 1
			end
			if member.userId == userId then
				VitalsController.SetServerDown(member.down == true)
				-- Waiting in the lobby camp for the next boundary (ruling 18): the server
				-- refuses every attack, so none is sent. CombatHud reads the flag the same way.
				waiting = member.waiting == true and live
			end
		end
		InputController.SetPhase(phase, waiting)

		-- The map opens whenever the phase becomes `lobby` (the first RunState and every
		-- return) and closes when the phase leaves it. On a return the server refuses a start
		-- for its own cooldown: the map holds a Depart pressed inside it and sends it when it
		-- ends, so the press is never lost and never refused.
		local screen = mapScreen
		if screen ~= nil then
			screen.SetParty(run.party, userId, run.leaderUserId)
			if phase == "lobby" and last ~= "lobby" then
				freeDepart()
				screen.Rest(
					if last ~= "" and combatConfig ~= nil
						then combatConfig.levels.startCooldownSeconds
						else 0
				)
				screen.Open()
			elseif phase ~= "lobby" and screen.IsOpen() then
				freeDepart()
				screen.Close()
			end
		end

		-- The summary card, for a RunState that carries a result. It has the screen: no
		-- crosshair, health bar or banner under it, and no map beside it (the trip home shows
		-- its card whatever the phase).
		rangeGui.Enabled = not over
		local result = run.result
		-- Only where a card belongs: a result still riding on a lobby RunState must not keep
		-- the map shut.
		if isRunResult(result) and result ~= nil and (over or result.reason == LEAVE_REASON) then
			local returnIn = run.returnIn
			if screen ~= nil then
				screen.Close()
			end
			summaryCard.Show(run.summary, result, {
				partySize = #run.party,
				returnIn = if typeof(returnIn) == "number" then returnIn else nil,
				canBack = humans <= 1 or run.leaderUserId == userId,
				waves = run.waves,
				difficultyName = difficultyName,
				mapName = mapName,
			})
		else
			summaryCard.Hide()
		end
		bindSummaryKeys(summaryCard.CanBack())

		-- What the server dropped without a word goes from the screen here. Three things take
		-- the enemy's circles and shots AND the players' projectiles with them:
		--  * the run ended (its crowd, threats and projectiles are gone);
		--  * the stage changed (a camp was cleared, or a Studio skip moved the party on);
		--  * the wave changed in mid-fight with no breather and no merge (a Studio lever the
		--    server carried out: a forced wave, a skip to this camp's boss; one it refuses
		--    changes nothing).
		-- A wave clear inside a camp (entering a breather) takes the enemy's alone: a shot is
		-- ended by its own effect, but a lob's circle and a ground area get none and would
		-- "land" on nothing, while the players' own projectiles fly on.
		local ended = (over or phase == "lobby") and LIVE_PHASES[last] == true
		local staged = run.stage ~= st.stage
		local forced = (phase == "wave" or phase == "boss")
			and (last == "wave" or last == "boss")
			and run.wave ~= st.wave
			and not run.merged
		if ended or staged or forced then
			ThreatFx.Clear()
			FeedbackController.ClearFlights()
		elseif phase == "breather" and last ~= "breather" then
			ThreatFx.Clear()
		end
		-- The run ended: ask for the wallet now (L1b-16: the server also sends every dirty
		-- wallet at the end; a duplicate Snapshot is harmless). Kills during the run need no
		-- ask: the server sends the wallet itself, at most once a second.
		if over and not RUN_OVER_PHASES[last] then
			remotes.requestSnapshot:FireServer()
		end
		st.phase = phase
		st.wave = run.wave
		st.stage = run.stage
	end

	local function onActionResult(payload: any): ()
		if typeof(payload) == "table" and payload.action == START_ACTION then
			-- The server's answer to Depart: only a refusal comes back (a start changes the
			-- phase instead), and it frees the button and says why.
			if payload.ok == false then
				freeDepart()
				toast.Show(
					START_REFUSALS[payload.reason] or START_REFUSALS.unavailable,
					Theme.TOAST_ERROR_SECONDS,
					true
				)
			end
			return
		end
		local text, isError = actionResultText(payload)
		if text ~= nil then
			toast.Show(text, Theme.TOAST_ERROR_SECONDS, isError)
		end
	end

	-- The pointer ring keeps under the boss bar only while a boss is on show: with no bar there
	-- the limit would squeeze the ring on a short screen in every wave for nothing.
	local function applyVitalsLayout(): ()
		local layout = st.vitalsLayout
		if layout ~= nil then
			layout.topLimit = if st.bossShown then st.bossLimit else nil
			VitalsController.SetLayout(layout)
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
		local screen = mapScreen
		if screen ~= nil then
			screen.SetLayout(scale, size)
		end
		crosshair.SetLayout(scale)
		FeedbackController.SetLayout(scale)
		local _, clusterLeft, clusterTop = touchCluster()
		-- No panel column: the tiles and the health bar sit bottom centre.
		abilityBar.SetLayout(scale, size, 0)
		-- This ScreenGui starts under the top bar; the crosshair's and the vitals HUD's does
		-- not, so the crosshair's centre is the viewport's, less the inset.
		local inset = GuiService:GetGuiInset()
		local camera = Workspace.CurrentCamera
		local viewport = if camera ~= nil then camera.ViewportSize else size + inset
		local bossBottom = placeMissionBoss(bossBar, scale, size, edges, viewport / 2 - inset)
		st.bossLimit = if bossBottom ~= nil then bossBottom + inset.Y else nil
		placeBanner(scale, size, viewport, inset, edges, bossBottom)
		st.vitalsLayout = {
			scale = scale,
			rightReserve = 0,
			clusterLeft = clusterLeft,
			clusterTop = clusterTop,
		}
		applyVitalsLayout()
	end

	-- M opens and closes the map in the lobby. Backspace is Abandon, pressed twice (the HUD
	-- says whether it may: a live run, and this player's to end). Studio (ruling 33): N
	-- finishes the stage, B jumps to the boss, G steps the gear; the server ignores the levers
	-- anywhere else, and a skip it carries out shows as a new stage or wave, which is what
	-- clears the screen. None of them while a text box has the keyboard: `processed` says so
	-- for the chat, and the focus is asked as well, because Backspace is what one types there.
	local function onKey(input: InputObject, processed: boolean): ()
		if processed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == ABANDON_KEY then
			hud.PressAbandon()
			return
		end
		if input.KeyCode == MAP_TOGGLE_KEY then
			local screen = mapScreen
			if screen ~= nil and st.phase == "lobby" then
				if screen.IsOpen() then
					screen.Close()
				else
					screen.Open()
				end
			end
			return
		end
		local lever = if studio then DEBUG_KEYS[input.KeyCode] else nil
		local remote = remotes.requestDebug
		if lever ~= nil and remote ~= nil and debounced() then
			remote:FireServer(lever.lever, lever.value)
		end
	end

	-- No banner handler here: a banner mirrored into a toast was a second message for one
	-- event, and with the notice line a third in one band of a landscape phone. The objective
	-- line is the record of where the run stands. Personal notices keep the toast.
	CombatFxController.SetToastHandler(function(text: string)
		toast.Show(text, Theme.TOAST_ERROR_SECONDS, false)
	end)
	-- L1b: "Checkpoint" goes on the notice line under the wallet, the place the banner already
	-- keeps clear of (placeBanner), not into the toast with the personal notices.
	CampFx.SetNoticeHandler(hud.ShowNotice)

	remotes.stateChanged.OnClientEvent:Connect(onStateChanged)
	remotes.actionResult.OnClientEvent:Connect(onActionResult)
	remotes.runState.OnClientEvent:Connect(onRunState)
	-- The map rides with the snapshot (the server sends both for RequestSnapshot), and it is
	-- also sent at every admit. Should none have come (this client asked before it was
	-- admitted and the admit's own was lost), the snapshot is asked for again, a few times.
	local function askForMap(asked: number): ()
		task.delay(Theme.MAP_STATE_RETRY_SECONDS, function()
			if st.mapStateSeen then
				return
			end
			if asked >= Theme.MAP_STATE_RETRIES then
				warn("[CombatUIController] no MapState came: the map shows every level closed")
				return
			end
			remotes.requestSnapshot:FireServer()
			askForMap(asked + 1)
		end)
	end
	local mapStateEvent = remotes.mapState
	if mapStateEvent ~= nil then
		mapStateEvent.OnClientEvent:Connect(onMapState)
		if mapScreen ~= nil then
			askForMap(0)
		end
	else
		warn("[CombatUIController] MapState missing: the map shows every level closed")
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	UserInputService.InputBegan:Connect(onKey)
	-- Pure display every frame: the boss off CrowdRenderer, and the Alt hint's camera state.
	RunService.RenderStepped:Connect(function(deltaTime: number)
		local boss = CrowdRenderer.GetBoss()
		bossBar.Update(deltaTime, boss)
		if (boss ~= nil) ~= st.bossShown then
			st.bossShown = boss ~= nil
			applyVitalsLayout()
		end
		hud.SetAiming(CameraController.IsActive(), CameraController.IsAiming())
	end)
	-- One explicit request on boot: the server's join snapshot may have fired before this
	-- connection existed; duplicate snapshots are harmless by design. Sent before the layout
	-- pass, which is guarded as well: neither this nor the wiring below waits on it.
	remotes.requestSnapshot:FireServer()
	firstLayout(applyLayout)

	-- RangeStats still comes in a mission, for the one thing a mission needs of it: a refused
	-- attack names its seq, so a swing drawn early is taken back (P3.1). Only those two fields
	-- are read: the bench's readouts (alive, server ms, ...) are the range's provider's, which a
	-- mission does not run.
	local rangeStats = remotesFolder:WaitForChild("RangeStats", timeout) :: RemoteEvent?
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
	if CameraController.IsRange() then
		task.spawn(bootRange)
	elseif CameraController.IsCrowdCombat() then
		task.spawn(bootMission)
	else
		-- Start runs once, so this is said once.
		warn(
			"[CombatUIController] Config/ProvingGrounds is missing: booting the C1 mission HUD,"
				.. " which cannot fight since P5 Wave 1 (the server has no C1 attack handlers)"
		)
		task.spawn(boot)
	end
end

return CombatUIController
