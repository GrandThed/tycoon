--!strict
-- The hub place's remote definitions (docs/INTERFACES.md "Remotes" + "C0 contracts"). Moved out
-- of RemoteService at C0 so the Expeditions place can hand it a different set; the validators
-- below are the M1–M6 ones verbatim plus the four combat intents.
--
-- A validator guarantees SHAPE only. Ids, keys and affordability are resolved by the owning
-- service, which refuses unknown values with an ActionResult.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))
local RemoteService = require(script.Parent:WaitForChild("RemoteService"))

local isStudio = RunService:IsStudio()

-- Used when Combat.json is absent: the Expeditions feature is hidden then, so RequestRunList is
-- never sent, and its bucket only needs a legal rate.
local DEFAULT_RUN_LIST_CALLS_PER_SECOND = 1
-- A mission id is a short config key ("village"); anything longer is a malformed payload, not a
-- lookup worth making.
local MAX_MISSION_ID_LENGTH = 64
-- RequestDebug (C1, Studio only): a lever name is a short identifier and its value is a number,
-- a flag or a tiny string like "melee=3"; anything larger is a malformed payload. The handler
-- ignores the whole intent outside Studio, so these bounds only keep the validator honest.
local MAX_DEBUG_LEVER_LENGTH = 32
local MAX_DEBUG_VALUE_LENGTH = 64

local function isCountInRange(value: any): boolean
	if typeof(value) ~= "number" or value ~= math.floor(value) then
		return false
	end
	-- Contract range is 1..100 with maxLevel = 100; bound by config so they cannot drift apart.
	return value >= 1 and value <= Catalog.GetGameConfig().maxLevel
end

local function isWeaponSlot(value: any): boolean
	return value == "melee" or value == "ranged"
end

-- A real host id is always positive. The Studio fake runs (C1 `fakeRuns` lever) host themselves
-- on negative ids so Join can be refused on one, and ONLY Studio widens the rule: live, a
-- negative id would buy a client a MemoryStore GetAsync on an arbitrary key at the prompt rate.
local function isHostUserId(value: any): boolean
	if typeof(value) ~= "number" or value ~= math.floor(value) then
		return false
	end
	if value > 0 then
		return true
	end
	return value < 0 and isStudio
end

-- Same rule as CombatRemotes' RequestDebug validator: NaN and ±inf are not lever values, and a
-- number that survives into a grant would corrupt a persisted field.
local function isDebugValue(value: any): boolean
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" then
		return true
	end
	if kind == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge
	end
	return kind == "string" and #value <= MAX_DEBUG_VALUE_LENGTH
end

local remotesConfig = Catalog.GetGameConfig().remotes
local combatConfig = Catalog.GetCombatConfig()

-- RequestPrompt opens a modal OS purchase dialog rather than performing a game action, so it
-- gets its own much tighter budget (Game.json v1.4); RequestSnapshot answers with a full state
-- snapshot, the most expensive reply the server makes, so it gets its own too (v1.5).
-- RequestRunList reads the MemoryStore run registry, so it gets the registry's own rate (C0).
-- Every other remote shares callsPerSecond.
local HubRemotes: RemoteService.RemoteDefs = {
	intents = {
		RequestSnapshot = {
			bucket = "snapshot",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 0
			end,
		},
		RequestBuy = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 1 and typeof(args[1]) == "string"
			end,
		},
		RequestLevelUp = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 2 and typeof(args[1]) == "string" and isCountInRange(args[2])
			end,
		},
		RequestAdvanceEra = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 0
			end,
		},
		RequestRebirth = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 0
			end,
		},
		RequestPrompt = {
			bucket = "prompt",
			validate = function(args: RemoteService.PackedArgs): boolean
				-- The key itself is resolved (and unknown keys dropped) by MonetizationService,
				-- which owns the pass/product tables; the validator only guarantees the shape.
				return args.n == 1 and typeof(args[1]) == "string"
			end,
		},
		RequestSetSetting = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				-- Only the Types.SettingKey values exist; anything else is a silent drop.
				return args.n == 2
					and (args[1] == "music" or args[1] == "sfx" or args[1] == "vipSkins" or args[1] == "cityDetail")
					and typeof(args[2]) == "boolean"
			end,
		},
		RequestRetryLoad = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				-- Shape only; the real throttle is DataService's retry cooldown (M5 safe mode).
				return args.n == 0
			end,
		},
		RequestBuyPerk = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				-- The perk id is resolved (and unknown ids refused) by LegacyShopService, which
				-- owns the purchase chain; shared callsPerSecond bucket (M6 — earned currency,
				-- no dialog).
				return args.n == 1 and typeof(args[1]) == "string"
			end,
		},
		-- C0. The client never sends a tier, a cost or a material: the slot is the whole intent,
		-- and ArmoryService derives the next tier from the profile.
		RequestBuyGear = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 1 and isWeaponSlot(args[1])
			end,
		},
		RequestAscend = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 1 and isWeaponSlot(args[1])
			end,
		},
		-- Departing reserves a server and teleports, so it shares the prompt budget rather than
		-- the gameplay one.
		RequestExpedition = {
			bucket = "prompt",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 2
					and typeof(args[1]) == "string"
					and #args[1] <= MAX_MISSION_ID_LENGTH
					and typeof(args[2]) == "boolean"
			end,
		},
		RequestJoinRun = {
			bucket = "prompt",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 1 and isHostUserId(args[1])
			end,
		},
		RequestRunList = {
			bucket = "runList",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 0
			end,
		},
		-- C1. The Studio DebugPanel's buttons; ArmoryService.HandleDebug drops every call
		-- outside Studio, so this is shape-checking a remote that does nothing in production.
		RequestDebug = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 2
					and typeof(args[1]) == "string"
					and #args[1] <= MAX_DEBUG_LEVER_LENGTH
					and isDebugValue(args[2])
			end,
		},
	},
	-- FxEvent (M3), RunList (C0) and ExpeditionSummary (C1) are server → client only:
	-- presentation events and the run registry answer, owner only, never on bulk restore.
	events = { "StateChanged", "ActionResult", "FxEvent", "RunList", "ExpeditionSummary" },
	rates = {
		calls = remotesConfig.callsPerSecond,
		prompt = remotesConfig.promptCallsPerSecond,
		snapshot = remotesConfig.snapshotCallsPerSecond,
		runList = if combatConfig ~= nil
			then combatConfig.remotes.runListCallsPerSecond
			else DEFAULT_RUN_LIST_CALLS_PER_SECOND,
	},
}

return HubRemotes
