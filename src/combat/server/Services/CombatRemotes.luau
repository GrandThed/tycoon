--!strict
-- The Expeditions place's remote definitions (docs/INTERFACES.md "C0 contracts" → "Remotes").
-- Handed to RemoteService.Configure by the combat Main before Init, so this place creates its
-- own remotes and none of the hub's.
--
-- RequestAttack/RequestAbility exist from C0 with their validators and their own tight buckets;
-- C1 owns their handlers (hit resolution is server-side raycasts against the live wave).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local RemoteService =
	require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("RemoteService"))

-- Used when Combat.json is absent (the place then only ever shows the lobby): a legal rate so
-- the buckets still exist.
local DEFAULT_ATTACK_CALLS_PER_SECOND = 8
local DEFAULT_ABILITY_CALLS_PER_SECOND = 2
-- A swing can never legitimately name more targets than the director allows alive at once; the
-- ceiling stops a forged payload from making the server walk a huge list.
local DEFAULT_MAX_TARGETS = 24
-- Caps on the debug intent, per contract: a lever name and a short scalar, nothing else.
local MAX_LEVER_LENGTH = 32
local MAX_LEVER_VALUE_LENGTH = 64

local combatConfig = Catalog.GetCombatConfig()
local maxTargets = if combatConfig ~= nil
	then combatConfig.director.maxAlive
	else DEFAULT_MAX_TARGETS

-- Shape only: every id is re-resolved against the live wave by the C1 handler, which owns
-- range, arc and cooldown. An out-of-range id is a miss, never an error.
local function isTargetList(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end
	local list = value :: { any }
	if #list > maxTargets then
		return false
	end
	for _, id in list do
		if typeof(id) ~= "number" or id ~= math.floor(id) or id <= 0 then
			return false
		end
	end
	return true
end

-- NaN and infinity would survive every downstream comparison and land in a Raycast; the client
-- has no legitimate reason to send either.
local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function isFiniteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local vector = value :: Vector3
	return isFiniteNumber(vector.X) and isFiniteNumber(vector.Y) and isFiniteNumber(vector.Z)
end

local CombatRemotes: RemoteService.RemoteDefs = {
	intents = {
		RequestSnapshot = {
			bucket = "snapshot",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 0
			end,
		},
		RequestRetryLoad = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				-- Shape only; the real throttle is DataService's retry cooldown (M5 safe mode).
				return args.n == 0
			end,
		},
		RequestReady = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 0
			end,
		},
		RequestLeave = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 0
			end,
		},
		-- swingSeq is the client's own swing counter: the server uses it to drop replays of a
		-- swing it has already resolved, never to trust the damage.
		RequestAttack = {
			bucket = "attack",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 2
					and typeof(args[1]) == "number"
					and args[1] == math.floor(args[1])
					and args[1] >= 0
					and isTargetList(args[2])
			end,
		},
		-- C1: the aim ray. Origin and direction are re-checked against the shooter's head and
		-- the class range by CombatService; `charge` is clamped there against the real hold
		-- time, so a claim of 1.0 on the first frame buys nothing.
		RequestFire = {
			bucket = "attack",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 4
					and typeof(args[1]) == "number"
					and args[1] == math.floor(args[1])
					and args[1] >= 0
					and isFiniteVector(args[2])
					and isFiniteVector(args[3])
					and (args[3] :: Vector3).Magnitude > 0
					and typeof(args[4]) == "number"
					and args[4] == args[4]
					and args[4] >= 0
					and args[4] <= 1
			end,
		},
		RequestAbility = {
			bucket = "ability",
			validate = function(args: RemoteService.PackedArgs): boolean
				-- C1: the slot, because the two weapons carry one ability each. Which ability
				-- that slot holds is still the server's lookup, never the client's claim.
				return args.n == 1 and (args[1] == "melee" or args[1] == "ranged")
			end,
		},
		-- Studio levers. The handler refuses everything outside Studio; this validator only
		-- keeps a malformed payload out of it.
		RequestDebug = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				if args.n ~= 2 or typeof(args[1]) ~= "string" then
					return false
				end
				if #(args[1] :: string) > MAX_LEVER_LENGTH then
					return false
				end
				local value = args[2]
				local valueType = typeof(value)
				if value == nil or valueType == "boolean" then
					return true
				end
				if valueType == "number" then
					return value == value and value ~= math.huge and value ~= -math.huge
				end
				return valueType == "string" and #(value :: string) <= MAX_LEVER_VALUE_LENGTH
			end,
		},
	},
	-- CombatFx exists from C0 so the client can WaitForChild it; C1 fills it with hit, death and
	-- ability presentation.
	events = { "StateChanged", "ActionResult", "RunState", "CombatFx" },
	rates = {
		calls = Catalog.GetGameConfig().remotes.callsPerSecond,
		snapshot = Catalog.GetGameConfig().remotes.snapshotCallsPerSecond,
		attack = if combatConfig ~= nil
			then combatConfig.remotes.attackCallsPerSecond
			else DEFAULT_ATTACK_CALLS_PER_SECOND,
		ability = if combatConfig ~= nil
			then combatConfig.remotes.abilityCallsPerSecond
			else DEFAULT_ABILITY_CALLS_PER_SECOND,
	},
}

return CombatRemotes
