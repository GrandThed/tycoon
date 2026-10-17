--!strict
-- The L2 W1 second fix round's Minor 1: the inputs of an aimed ability's ground-point rule
-- (WallClip.GroundFloor), read in one place. WeaponService.GroundPoint (server) and
-- InputController.groundPoint (client) both call Floor and pass only what their own rays found,
-- so the movement heights and the reading of the bought double jump cannot drift between the
-- two. The first fix round left each side writing both inputs itself, and a review showed that
-- a client reading the attribute as `~= false` (every player an owner) or a server typing its
-- own heights passed every gate.
-- Reads Tuning and one Player attribute, never yields; tools/crowd_harness tests it with a stub
-- player.

local Tuning = require(script.Parent:WaitForChild("Tuning"))
local Unlocks = require(script.Parent:WaitForChild("Unlocks"))
local WallClip = require(script.Parent:WaitForChild("WallClip"))

local GroundRule = {}

-- Whether `player` owns the double jump as the server's UnlockService published it (L2-4): only
-- an attribute of exactly true counts, never a missing, false or forged value.
function GroundRule.OwnsAirJump(player: Player): boolean
	return player:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)) == true
end

-- WallClip.GroundFloor with the range's movement heights (ProvingGrounds.json `movement`) and
-- `player`'s own double jump. `probedCaster` / `probedTarget`: the floors the caller's rays found
-- under the caster and the aimed point (nil = a void); `feetY` the caster's feet. Returns
-- GroundFloor's two values: the ground point's floor (nil = refused) and the caster's floor.
function GroundRule.Floor(
	player: Player,
	probedCaster: number?,
	feetY: number,
	probedTarget: number?
): (number?, number)
	return WallClip.GroundFloor(
		probedCaster,
		feetY,
		probedTarget,
		Tuning.Get().movement,
		GroundRule.OwnsAirJump(player)
	)
end

return GroundRule
