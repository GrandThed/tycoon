--!strict
-- L1b Wave 2 fix round, ui-2 (docs/prompts/l1b-w2-fix-round.md): which drawn bodies touch
-- auto-fire and auto-swing may take by themselves. A phone in auto-fire has no attack button, so
-- whatever this lets through is fired at the moment it sits in the reticle; a shot at a resting
-- camp wakes it (L1b-4) and the sneak (MISSIONS_DESIGN 16.3) could not be done on touch. A
-- phone player wakes a camp the "noisy way", by walking into its sight. Deliberate shots
-- (mouse, gamepad, a touch tap) never ask this. Pure: no Instance, no service.
--
-- In order, for a body that stands on a camp's floor (`centre` and `half` known):
--  1. the boss room's countdown (`gate`): never (L1b-W2-25: every body in reach is held);
--  2. its group rests (held and dormant included): never;
--  3. the player is engaged by a camp, or there are no camp rules: always;
--  4. else only while the root is in play for that floor (L1b-6's first clause: inside the
--     sight band, flat distance to the floor rectangle at most chaseMargin, so the corners are
--     rounded). Leaving out the keepAway reach clause only makes this stricter.
-- A body with no camp floor (the range, an arena) is always taken, as before Wave 1.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))

local CampAim = {}

-- centre/half = the body's camp floor (top centre, half extents; nil = no camp floor);
-- resting = its group is at rest; root = the local root; phase = the run phase; engaged = the
-- local PartyMember.engaged; camps = Combat.json `camps` (nil = not loaded).
function CampAim.Takes(
	centre: Vector3?,
	half: Vector3?,
	resting: boolean,
	root: Vector3,
	phase: string,
	engaged: boolean,
	camps: Types.CampRulesConfig?
): boolean
	if centre == nil or half == nil then
		return true
	end
	if phase == "gate" or resting then
		return false
	end
	if camps == nil or engaged then
		return true
	end
	if root.Y < centre.Y - camps.sightBelow or root.Y > centre.Y + camps.sightAbove then
		return false
	end
	return HitShapes.FlatToRect(root.X, root.Z, centre.X, centre.Z, half.X, half.Z)
		<= camps.chaseMargin
end

return CampAim
