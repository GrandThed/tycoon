--!strict
-- The Expeditions place's remote definitions (docs/INTERFACES.md "C0 contracts" → "Remotes").
-- Handed to RemoteService.Configure by the combat Main before Init, so this place creates its
-- own remotes and none of the hub's.
--
-- L4 W1b deleted C1's five intents (ready, attack, fire, draw, ability) and their two buckets:
-- they had no handler since P5 and L1. Every attack is a range intent below.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))
local RemoteService =
	require(script.Parent.Parent:WaitForChild("Services"):WaitForChild("RemoteService"))

-- P3 range buckets, used when Combat.json is absent (the place then only ever shows the lobby):
-- a legal rate so the buckets still exist. Room for a Mag Dump SMG's buffed rate plus the other
-- slot, and for two slots' ability presses; RangeService and AbilityService enforce the real
-- per-weapon rate and cooldowns.
local DEFAULT_RANGE_ATTACK_CALLS_PER_SECOND = 40
local DEFAULT_RANGE_ABILITY_CALLS_PER_SECOND = 4
-- Caps on the debug intent, per contract: a lever name and a short scalar, nothing else.
local MAX_LEVER_LENGTH = 32
local MAX_LEVER_VALUE_LENGTH = 64
-- P1 range intents (docs/INTERFACES.md "P1 contracts" → "Remotes"): the contract's size caps.
local MAX_TUNE_PATH_LENGTH = 96
local MAX_TUNE_STRING_LENGTH = 32
local MAX_COMMAND_LENGTH = 24
local MAX_COMMAND_ARG_LENGTH = 32
-- P2: a weapon family id (broadsword, longbow, ...); RangeService checks it names a real family
-- that the player holds in that slot. One home, Unlocks (a secret's family is held to it too).
local MAX_FAMILY_LENGTH = Unlocks.MAX_FAMILY_LENGTH
-- L1 (docs/INTERFACES.md "L1 contracts" → "Remotes"): a level id and a difficulty key. Shape
-- only: WaveService.OnStartLevel resolves both against the level files and the map.
local MAX_LEVEL_ID_LENGTH = 32
local MAX_DIFFICULTY_LENGTH = 12
-- L2-7: an ability id ("doubleJump"). Shape only: UnlockService resolves it against
-- Expeditions.json `abilities` and prices it from there. One home, Unlocks (the Abilities panel
-- and Unlocks.DefProblem read the same cap).
local MAX_ABILITY_ID_LENGTH = Unlocks.MAX_ID_LENGTH
-- L2-32: a variant key ("A"). Shape only: UnlockService resolves the family and its variant.
local MAX_VARIANT_LENGTH = Unlocks.MAX_VARIANT_LENGTH

local combatConfig = Catalog.GetCombatConfig()

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

local function isDirection(value: any): boolean
	return isFiniteVector(value) and (value :: Vector3).Magnitude > 0
end

local function isSeq(value: any): boolean
	return typeof(value) == "number"
		and value == math.floor(value)
		and value >= 0
		and value < math.huge
end

local function isShortString(value: any, maxLength: number): boolean
	return typeof(value) == "string" and #(value :: string) > 0 and #(value :: string) <= maxLength
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
		-- L1: the leader picks what is played. Two names, nothing else: no amount, no position.
		RequestStartLevel = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 2
					and isShortString(args[1], MAX_LEVEL_ID_LENGTH)
					and isShortString(args[2], MAX_DIFFICULTY_LENGTH)
			end,
		},
		-- L2-7: buy an ability in the lobby. An id, never an amount.
		RequestBuyAbility = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 1 and isShortString(args[1], MAX_ABILITY_ID_LENGTH)
			end,
		},
		-- L2-32: hold a family (and one of its variants) in a slot, in the lobby. Three names, no
		-- amount: UnlockService checks the family exists, fills that slot, and is owned.
		RequestSetFamily = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 3
					and (args[1] == "melee" or args[1] == "ranged")
					and isShortString(args[2], MAX_FAMILY_LENGTH)
					and isShortString(args[3], MAX_VARIANT_LENGTH)
			end,
		},
		-- L3-12: raise one family a tier. A family id, never a tier or an amount: UnlockService
		-- derives the next tier, its cost and the star it needs from the profile.
		RequestUpgradeWeapon = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 1 and isShortString(args[1], MAX_FAMILY_LENGTH)
			end,
		},
		-- L1 ruling 21: end the live run with what was banked, or cut the summary's wait short.
		RequestAbandon = {
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
		-- P1 Proving Grounds, and since P5 every attack in a run too. Every range-only handler is
		-- inert outside the range (RangeService), and tune/command also outside Studio; these
		-- validators only keep malformed payloads out. P3: attacks and draws have their own
		-- bucket, so a held beam or SMG never starves the other intents' calls.
		RequestRangeAttack = {
			bucket = "rangeAttack",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 6
					and isShortString(args[1], MAX_FAMILY_LENGTH)
					and isSeq(args[2])
					and isFiniteVector(args[3])
					and isDirection(args[4])
					and typeof(args[5]) == "boolean"
					and isFiniteNumber(args[6])
					and args[6] >= 0
					and args[6] <= 1
			end,
		},
		-- P2: the bow's draw start. The server stamps its own clock; the charge the next attack
		-- claims is capped by the time since this stamp.
		RequestRangeDraw = {
			bucket = "rangeAttack",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 1 and isShortString(args[1], MAX_FAMILY_LENGTH)
			end,
		},
		-- P3: cast the ability of a slot along the camera ray. Which ability the slot holds, the
		-- aim origin and the cooldown are all the server's checks (AbilityService).
		RequestRangeAbility = {
			bucket = "rangeAbility",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 4
					and (args[1] == "melee" or args[1] == "ranged")
					and isSeq(args[2])
					and isFiniteVector(args[3])
					and isDirection(args[4])
			end,
		},
		RequestDash = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 1 and isDirection(args[1])
			end,
		},
		RequestSlam = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				return args.n == 0
			end,
		},
		RequestTune = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				if args.n ~= 2 or not isShortString(args[1], MAX_TUNE_PATH_LENGTH) then
					return false
				end
				local value = args[2]
				local valueType = typeof(value)
				if valueType == "boolean" then
					return true
				end
				if valueType == "number" then
					return isFiniteNumber(value)
				end
				return valueType == "string" and #(value :: string) <= MAX_TUNE_STRING_LENGTH
			end,
		},
		-- A trailing nil argument may or may not survive the wire, so both lengths are legal.
		RequestRangeCommand = {
			bucket = "calls",
			validate = function(args: RemoteService.PackedArgs): boolean
				if
					(args.n ~= 1 and args.n ~= 2) or not isShortString(args[1], MAX_COMMAND_LENGTH)
				then
					return false
				end
				return args[2] == nil or isShortString(args[2], MAX_COMMAND_ARG_LENGTH)
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
	-- CombatFx carries the run's own effects (RunFx: wave, boss down, mentor, camp, notice) and
	-- the fight's (AbilityService, VitalsService).
	-- P1 adds the crowd stream (CrowdSnapshot is unreliable: a lost snapshot is replaced by the
	-- next) and the range's TuneState / RangeStats; P3 the caster's cooldowns (RangeAbility).
	events = {
		"StateChanged",
		"ActionResult",
		"RunState",
		-- L1: the map's node states and the receiver's own stars (rulings 25 and 28).
		"MapState",
		"CombatFx",
		"CrowdSpawn",
		"CrowdRemove",
		"TuneState",
		"RangeStats",
		"RangeAbility",
	},
	unreliableEvents = { "CrowdSnapshot" },
	rates = {
		calls = Catalog.GetGameConfig().remotes.callsPerSecond,
		snapshot = Catalog.GetGameConfig().remotes.snapshotCallsPerSecond,
		rangeAttack = if combatConfig ~= nil
			then combatConfig.remotes.rangeAttackCallsPerSecond
			else DEFAULT_RANGE_ATTACK_CALLS_PER_SECOND,
		rangeAbility = if combatConfig ~= nil
			then combatConfig.remotes.rangeAbilityCallsPerSecond
			else DEFAULT_RANGE_ABILITY_CALLS_PER_SECOND,
	},
}

return CombatRemotes
