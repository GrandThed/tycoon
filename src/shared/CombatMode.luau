--!strict
-- What the Expeditions place is this session: the Proving Grounds bench ("range") or a mission
-- (docs/INTERFACES.md "P5 contracts", ruling 5). Decided once and cached: flipping an attribute
-- mid-session must not turn a live mission into a range. Server and client compute it with this
-- one function, so both always agree.
--
-- Not pure (RunService, Workspace) and deliberately not required by CrowdService or
-- VitalsService: the crowd harness loads those two without any of this.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Types = require(script.Parent:WaitForChild("Types"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Tuning = require(script.Parent:WaitForChild("Tuning"))

local RANGE_BOOT = "range"
-- Typed once: the old solver widens a returned literal to `string`.
local RANGE: Types.CombatMode = "range"
local MISSION: Types.CombatMode = "mission"

-- Decided once: nil until the first Get.
local cached: boolean? = nil

local CombatMode = {}

-- Studio, and the place was built with the proving switch baked in (tools/proving_project.py).
function CombatMode.IsProving(): boolean
	if not RunService:IsStudio() then
		return false
	end
	local cfg = Catalog.GetCombatConfig()
	if cfg == nil then
		return false
	end
	return Workspace:GetAttribute(cfg.debug.provingAttribute) == true
end

-- True when this session is the range.
local function decide(): boolean
	if not RunService:IsStudio() then
		return false
	end
	local cfg = Catalog.GetCombatConfig()
	if cfg == nil then
		return false
	end
	if RunService:IsClient() and not game:IsLoaded() then
		-- Workspace attributes arrive with the first replication; only Studio ever waits here.
		game.Loaded:Wait()
	end
	-- The key is new in P5: a Combat.json without it boots the mission, the P5 default.
	local boots = (cfg.debug :: any).provingBoots
	return CombatMode.IsProving() and boots == RANGE_BOOT and Tuning.IsAvailable()
end

-- Yields once on a Studio client until the game has loaded; never on a server or a live client.
function CombatMode.Get(): Types.CombatMode
	local range = cached
	if range == nil then
		range = decide()
		cached = range
	end
	return if range then RANGE else MISSION
end

return CombatMode
