--!strict
-- The expeditions map in the city (docs/prompts/l4-w3-contract.md section 2.4; MISSIONS_DESIGN
-- section 26 item 5): the host that mounts the shared UI/MapScreen in the hub's ScreenGui, the
-- way CombatUIController mounts it in the dungeon's lobby. The bottom bar's Expedition key opens
-- it. It is a display and an intent, nothing else:
--
--  * State: the hub PULLS it (L4W3-2). Opening the map fires RequestMapState, and so does every
--    PartyState while it is open (the leader, whose stars open the nodes, may have changed) and
--    every refused Depart. The server answers MapState to this player only: which nodes are open
--    for the party's leader, the leader's stars, this player's own secrets.
--  * The party: the hub's PartyState (a HubParty, nil = solo) becomes MapScreen.SetParty's list,
--    so the card reads "Solo · A down ends the run" or names the party with its leader, and a
--    member who is not the leader sees "Waiting for <leader>" on Depart.
--  * Depart sends RequestExpedition(levelId, difficulty, public), `public` being Party & runs'
--    "Open to public" toggle (deps.isPublic). The server checks the level against the leader's
--    own profile (MapRules.Startable) and answers on action `expedition`; Depart stays busy until
--    that answer (OnAnswer) or Theme.EXPEDITION_DEPART_TIMEOUT_SECONDS, whichever comes first.
--  * The footer button reads "Party & runs" and opens that panel (deps.onPartyAndRuns).
--  * Keys while open: the arrows (and the d-pad) pick a level and a difficulty, Enter (and A)
--    departs, Escape (and B) closes. Bound above the movement keys and sunk, so an arrow does not
--    also walk the character; a key already down when the map opened stays the character's
--    until it is let go. Roblox's menu takes Escape itself, so its press is watched whether or
--    not it was processed, and the menu opening closes the map too (as ArmoryScreen does).
--
-- The MapScreen is built on the first open, from Config/Expeditions as Catalog reads it then: the
-- Config folder may still be replicating when the HUD boots. Without it the key answers with a
-- toast (the fix round's F16), never a dead tap. No sound (L4 W3: none for the map).
--
-- The fix round's F11: Roblox's touch controls step aside while the map is open (UI/TouchHold;
-- the hub's HUD and the TouchGui share DisplayOrder 0, so the jump button could take a tap on
-- Depart). On open the host's onOpenChanged runs first, so the Armory's own R9 toggle has given
-- back the controls before this hold puts their value aside; on close the hold goes first.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local MapRules = require(sharedFolder:WaitForChild("MapRules"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local MapScreen = require(script.Parent:WaitForChild("MapScreen"))
local TouchHold = require(script.Parent:WaitForChild("TouchHold"))

export type Deps = {
	-- ReplicatedStorage.Remotes: RequestMapState, RequestExpedition and MapState are looked up
	-- in it when first needed (RemoteService creates them with the rest of the combat set).
	remotes: Instance,
	-- Party & runs' "Open to public", read at the press.
	isPublic: () -> boolean,
	-- The footer button: the map closes and Party & runs opens.
	onPartyAndRuns: () -> (),
	-- Opening: the host closes its other sheets here (the Armory first), before the touch hold.
	onOpenChanged: (open: boolean) -> (),
	-- An error toast (F16: the key pressed without Config/Expeditions).
	toast: (text: string) -> (),
}

export type Handle = {
	-- Opens the map (closes it when open). Nothing happens without Config/Expeditions.
	Toggle: () -> (),
	Open: () -> (),
	Close: () -> (),
	IsOpen: () -> boolean,
	-- The party this player is a member of (nil = solo), as UIController reads PartyState.
	SetParty: (party: Types.HubParty?) -> (),
	-- The `expedition` ActionResult: Depart is live again, and a refusal asks for the map anew.
	OnAnswer: (ok: boolean) -> (),
	-- True while this player's own Depart waits for its answer.
	IsDeparting: () -> boolean,
	-- scale = the HUD's UI scale; viewportSize = the hub ScreenGui's AbsoluteSize.
	SetLayout: (scale: number, viewportSize: Vector2) -> (),
	Destroy: () -> (),
}

local RETURN_TEXT = "Party & runs"
local UNAVAILABLE_TEXT = "Expeditions are unavailable"
-- This host's reason in UI/TouchHold's count.
local TOUCH_HOLD = "hubMap"
local KEY_HINT = "← → level · ↑ ↓ difficulty · Enter depart"
local KEY_ACTION = "HubMapKeys"
-- The keys bound while the map is open. A step is (dx, dy): dx the node before or after in
-- config order, dy an easier or a harder difficulty (Up is harder, as in the dungeon).
local STEP_KEYS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.Up] = Vector2.new(0, 1),
	[Enum.KeyCode.Down] = Vector2.new(0, -1),
	[Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
	[Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
	[Enum.KeyCode.DPadUp] = Vector2.new(0, 1),
	[Enum.KeyCode.DPadDown] = Vector2.new(0, -1),
}
local CONFIRM_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.KeypadEnter] = true,
	[Enum.KeyCode.ButtonA] = true,
}
-- Escape is not bindable (the menu takes it); the pad's B is.
local CLOSE_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.ButtonB] = true }
-- Which of the bound keys are a gamepad's: whether one is down is asked of the pad.
local PAD_KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.ButtonB] = true,
	[Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.DPadRight] = true,
	[Enum.KeyCode.DPadUp] = true,
	[Enum.KeyCode.DPadDown] = true,
}
local BOUND_KEYS: { Enum.KeyCode } = {}
for key in STEP_KEYS do
	table.insert(BOUND_KEYS, key)
end
for key in CONFIRM_KEYS do
	table.insert(BOUND_KEYS, key)
end
for key in CLOSE_KEYS do
	table.insert(BOUND_KEYS, key)
end

local HubMap = {}

-- The bound keys that are down right now: an action bound over a key already down must not sink
-- it, or its release would never reach the binding under it (a character walking on an arrow
-- when the map opened would walk on for good).
local function keysDown(): { [Enum.KeyCode]: boolean }
	local held: { [Enum.KeyCode]: boolean } = {}
	for _, key in BOUND_KEYS do
		local down = if PAD_KEYS[key]
			then UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
			else UserInputService:IsKeyDown(key)
		if down then
			held[key] = true
		end
	end
	return held
end

-- True when this input is a key that was down at the bind (the handler passes it on); the key
-- leaves the set when it is let go, and its next press is the map's. A press of a key still in
-- the set means its release was never seen (focus left with it down): that press is the map's.
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

-- MapScreen.SetParty reads a member's id and name only; the run fields of a PartyMember mean
-- nothing in the city and are neutral here.
local function member(userId: number, name: string, leaderUserId: number): Types.PartyMember
	return {
		userId = userId,
		name = name,
		hp = 0,
		maxHp = 0,
		alive = true,
		host = userId == leaderUserId,
		waiting = false,
		damageShare = 0,
		down = false,
	}
end

function HubMap.new(parent: Instance, deps: Deps): Handle
	local player = Players.LocalPlayer
	local localUserId = player.UserId
	local connections: { RBXScriptConnection } = {}
	-- `screen` is built on the first open; `layout` is the last SetLayout, applied when it is.
	-- `held` are the keys that were down at the bind; `departToken` names the Depart in flight,
	-- so the timeout of an answered one frees nothing. `seeded` = the first MapState picked what
	-- the map opens on; later the pick is the player's.
	local view = {
		screen = nil :: MapScreen.MapScreenHandle?,
		missing = false,
		open = false,
		keysBound = false,
		held = {} :: { [Enum.KeyCode]: boolean },
		departing = false,
		departToken = 0,
		seeded = false,
		party = nil :: Types.HubParty?,
		layout = nil :: { scale: number, size: Vector2 }?,
		mapEvent = nil :: RBXScriptConnection?,
	}

	local function remote(name: string): RemoteEvent?
		local found = deps.remotes:FindFirstChild(name)
		return if found ~= nil and found:IsA("RemoteEvent") then found else nil
	end

	local function requestState(): ()
		local request = remote("RequestMapState")
		if request ~= nil then
			request:FireServer()
		end
	end

	local function pushParty(): ()
		local screen = view.screen
		if screen == nil then
			return
		end
		local party = view.party
		local list: { Types.PartyMember } = {}
		local leaderUserId = localUserId
		if party == nil then
			table.insert(list, member(localUserId, player.DisplayName, localUserId))
		else
			leaderUserId = party.leaderUserId
			for _, entry in party.members do
				table.insert(list, member(entry.userId, entry.name, leaderUserId))
			end
		end
		screen.SetParty(list, localUserId, leaderUserId)
	end

	local function onMapState(payload: any): ()
		local screen = view.screen
		if
			screen == nil
			or typeof(payload) ~= "table"
			or payload.kind ~= "map"
			or typeof(payload.nodes) ~= "table"
		then
			return
		end
		local state = payload :: Types.MapState
		screen.SetState(state)
		local map = Catalog.GetExpeditionsConfig()
		if not view.seeded and map ~= nil then
			local nodeId, difficulty = MapRules.FirstPick(map.difficulties, state)
			if nodeId ~= nil then
				view.seeded = true
				screen.Select(nodeId, difficulty)
			end
		end
	end

	-- MapState comes with the combat remotes; connected the first time it is there.
	local function connectMapEvent(): ()
		if view.mapEvent ~= nil then
			return
		end
		local event = remote("MapState")
		if event ~= nil then
			view.mapEvent = event.OnClientEvent:Connect(onMapState)
		end
	end

	local function freeDepart(): ()
		view.departToken += 1
		view.departing = false
		local screen = view.screen
		if screen ~= nil then
			screen.SetBusy(false)
		end
	end

	-- MapScreen set itself busy before it called this.
	local function depart(levelId: string, difficulty: string): ()
		local request = remote("RequestExpedition")
		if request == nil then
			warn("[HubMap] RequestExpedition is missing: Depart cannot be sent")
			freeDepart()
			return
		end
		request:FireServer(levelId, difficulty, deps.isPublic())
		view.departToken += 1
		view.departing = true
		local token = view.departToken
		task.delay(Theme.EXPEDITION_DEPART_TIMEOUT_SECONDS, function()
			if token == view.departToken then
				freeDepart()
			end
		end)
	end

	local function onKey(
		_action: string,
		state: Enum.UserInputState,
		input: InputObject
	): Enum.ContextActionResult
		if passesHeld(view.held, state, input) then
			return Enum.ContextActionResult.Pass
		end
		local screen = view.screen
		if state == Enum.UserInputState.Begin and screen ~= nil then
			local step: Vector2? = STEP_KEYS[input.KeyCode]
			if step ~= nil then
				screen.Step(step.X, step.Y)
			elseif CLOSE_KEYS[input.KeyCode] then
				screen.Close()
			elseif CONFIRM_KEYS[input.KeyCode] then
				screen.Confirm()
			end
		end
		return Enum.ContextActionResult.Sink
	end

	local function bindKeys(bound: boolean): ()
		if bound == view.keysBound then
			return
		end
		view.keysBound = bound
		if bound then
			view.held = keysDown()
			ContextActionService:BindActionAtPriority(
				KEY_ACTION,
				onKey,
				false,
				Enum.ContextActionPriority.High.Value + 1,
				table.unpack(BOUND_KEYS)
			)
		else
			ContextActionService:UnbindAction(KEY_ACTION)
		end
	end

	local function onOpenChanged(open: boolean): ()
		view.open = open
		bindKeys(open)
		if open then
			deps.onOpenChanged(true)
			TouchHold.Hold(TOUCH_HOLD)
			connectMapEvent()
			requestState()
		else
			TouchHold.Release(TOUCH_HOLD)
			deps.onOpenChanged(false)
		end
	end

	-- The screen, built on first need; nil while Config/Expeditions is not here (warned once).
	local function ensureScreen(): MapScreen.MapScreenHandle?
		local existing = view.screen
		if existing ~= nil then
			return existing
		end
		local map = Catalog.GetExpeditionsConfig()
		if map == nil then
			if not view.missing then
				view.missing = true
				warn("[HubMap] Config/Expeditions is missing: the map cannot open")
			end
			return nil
		end
		local screen = MapScreen.new(parent, map, {
			onDepart = depart,
			onOpenChanged = onOpenChanged,
			onReturn = function()
				local current = view.screen
				if current ~= nil then
					current.Close()
				end
				deps.onPartyAndRuns()
			end,
			returnText = RETURN_TEXT,
			keyHint = if UserInputService.KeyboardEnabled then KEY_HINT else nil,
		})
		view.screen = screen
		local layout = view.layout
		if layout ~= nil then
			screen.SetLayout(layout.scale, layout.size)
		end
		pushParty()
		return screen
	end

	local function close(): ()
		local screen = view.screen
		if screen ~= nil then
			screen.Close()
		end
	end

	local function open(): ()
		local screen = ensureScreen()
		if screen ~= nil then
			screen.Open()
		else
			deps.toast(UNAVAILABLE_TEXT)
		end
	end

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape and view.open then
				close()
			end
		end)
	)
	table.insert(connections, GuiService.MenuOpened:Connect(close))

	local handle: Handle = {
		Toggle = function()
			if view.open then
				close()
			else
				open()
			end
		end,
		Open = open,
		Close = close,
		IsOpen = function(): boolean
			return view.open
		end,
		SetParty = function(party: Types.HubParty?)
			view.party = party
			pushParty()
			if view.open then
				requestState()
			end
		end,
		OnAnswer = function(ok: boolean)
			freeDepart()
			if not ok and view.open then
				requestState()
			end
		end,
		IsDeparting = function(): boolean
			return view.departing
		end,
		SetLayout = function(scale: number, viewportSize: Vector2)
			view.layout = { scale = scale, size = viewportSize }
			local screen = view.screen
			if screen ~= nil then
				screen.SetLayout(scale, viewportSize)
			end
		end,
		Destroy = function()
			view.departToken += 1
			bindKeys(false)
			-- MapScreen.Destroy reports no close, so an open map gives the controls back here.
			TouchHold.Release(TOUCH_HOLD)
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			local event = view.mapEvent
			if event ~= nil then
				event:Disconnect()
				view.mapEvent = nil
			end
			local screen = view.screen
			if screen ~= nil then
				view.screen = nil
				screen.Destroy()
			end
		end,
	}
	return handle
end

return HubMap
