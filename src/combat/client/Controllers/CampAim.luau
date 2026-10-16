--!strict
-- Which drawn bodies touch auto-fire and auto-swing may take by themselves. A phone in
-- auto-fire has no attack button, so whatever this lets through is fired at the moment it sits
-- in the reticle, and a shot at a resting camp wakes it (L1b-4). Deliberate shots (mouse,
-- gamepad, a touch tap) never ask this. Pure: no Instance, no service.
--
-- L1b Wave 4 (docs/INTERFACES.md "L1b Wave 4 — no waits, no walls", L1b-W4-32): raiders now
-- chase out of their camp along the road and every hit on an awake one lands, so where the
-- player stands no longer matters (the in-play and engaged clauses are gone). Two rules stay,
-- for a body that stands on a camp's floor:
--  * the boss room's countdown (`gate`): never, since every body in reach then is a held
--    resident whose hit reads "BLOCKED" (L1b-W2-25);
--  * its group rests (held and dormant included): never, so a phone never wakes a camp by
--    itself and the sneak (MISSIONS_DESIGN 16.3) stays possible on touch; it wakes one only by
--    walking into its sight.
-- A body with no camp floor (the range, an arena, a floor not yet told) is always taken.

local CampAim = {}

-- onCampFloor = the body stands on a level camp's floor (CrowdRenderer.CampFloor answered one);
-- resting = its group is at rest; phase = the run phase.
function CampAim.Takes(onCampFloor: boolean, resting: boolean, phase: string): boolean
	if not onCampFloor then
		return true
	end
	return phase ~= "gate" and not resting
end

return CampAim
