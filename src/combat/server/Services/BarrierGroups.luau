--!strict
-- The collision groups of an invisible wall (docs/INTERFACES.md "L1 contracts" → "Server
-- modules" → "A — the world"). Moved out of ArenaService, where P5 Wave 1 built them for the
-- arena's fence, so that the range's arena (ArenaService) and a level's camps (LevelService)
-- share one registration.
--
-- An invisible wall must stop characters and nothing else: not the camera's boom, not a shot,
-- not the crosshair's ray. CanQuery = false cannot do that (the engine only honours it on a
-- part that is also non-colliding), so the wall gets a collision group that collides with ONE
-- other group, the one every member's character parts are put in. A ray or a shape cast runs in
-- the Default group, which the wall's group does not collide with, and passes through.
-- The players' group collides with exactly what Default does, group by group (every group
-- registered before this call), with one exception: a member's body never collides with another
-- member's (the L2 W1 fix round's d1). Standing on a partner's head would otherwise lift a player
-- without the double jump onto a ledge only an owner reaches, and two bodies put on one point (the
-- close's entry, a lobby spawn) would shove each other.

local PhysicsService = game:GetService("PhysicsService")

-- Names are engine plumbing.
local BARRIER_GROUP = "ArenaBarrier"
local PLAYER_GROUP = "ArenaPlayers"
local DEFAULT_GROUP = "Default"

-- nil = not tried yet; false = the engine refused the groups, so no wall is built anywhere.
local ready: boolean? = nil

local BarrierGroups = {}

-- The group every Part of an invisible wall is put in.
BarrierGroups.BARRIER = BARRIER_GROUP

-- Registers the two groups, once. false = the engine refused (pcall: the group API throws past
-- the engine's cap), told in one warn; every caller then builds no wall at all.
function BarrierGroups.Ensure(): boolean
	local known = ready
	if known ~= nil then
		return known
	end
	local ok, err = pcall(function()
		for _, name in { BARRIER_GROUP, PLAYER_GROUP } do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		for _, group in PhysicsService:GetRegisteredCollisionGroups() do
			local name: string = group.name
			if name ~= BARRIER_GROUP and name ~= PLAYER_GROUP then
				PhysicsService:CollisionGroupSetCollidable(
					PLAYER_GROUP,
					name,
					PhysicsService:CollisionGroupsAreCollidable(DEFAULT_GROUP, name)
				)
			end
			if name ~= PLAYER_GROUP then
				PhysicsService:CollisionGroupSetCollidable(BARRIER_GROUP, name, false)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, PLAYER_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(BARRIER_GROUP, PLAYER_GROUP, true)
	end)
	if not ok then
		warn(`[BarrierGroups] collision groups unavailable: {err}; there is no invisible wall`)
	end
	ready = ok
	return ok
end

-- Puts one part of a character in the players' group; connect it to DescendantAdded as well,
-- for the parts that arrive later. Does nothing when the groups could not be registered: a
-- part cannot be put in a group the engine does not know.
function BarrierGroups.JoinPlayers(instance: Instance): ()
	if instance:IsA("BasePart") and BarrierGroups.Ensure() then
		instance.CollisionGroup = PLAYER_GROUP
	end
end

return BarrierGroups
