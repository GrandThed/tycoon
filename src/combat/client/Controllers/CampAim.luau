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

-- The total enemies one shot hits, at least 1, as WeaponService's pierceOf.
local function hitsOf(pierce: number?): number
	return math.max(1, math.floor(pierce or 0))
end

-- onCampFloor = the body stands on a level camp's floor (CrowdRenderer.CampFloor answered one);
-- resting = its group is at rest; phase = the run phase.
function CampAim.Takes(onCampFloor: boolean, resting: boolean, phase: string): boolean
	if not onCampFloor then
		return true
	end
	return phase ~= "gate" and not resting
end

-- R13 (L1b Wave 4 fix round): a touch shot flies the crosshair line and pierces, so it would wake
-- a refused body that the line meets within the shot's hits even when the trigger was an awake
-- one. True when the shot spends its hits before it reaches the nearest refused body.
-- refusedEntry = the entry distance of the nearest refused body on the line (nil: none);
-- takenEntries = the entry distances of the bodies auto-fire may take; pierce = the variant's
-- (the total enemies one shot hits, at least 1, as WeaponService's pierceOf). A tie counts
-- against the shot: the server's order between equal entries is not the client's to guess.
function CampAim.ShotSpares(
	refusedEntry: number?,
	takenEntries: { number },
	pierce: number?
): boolean
	if refusedEntry == nil then
		return true
	end
	local hits = hitsOf(pierce)
	local before = 0
	for _, entry in takenEntries do
		if entry < refusedEntry then
			before += 1
		end
	end
	return before >= hits
end

-- R17 (L1b Wave 4 fix-diff round): a shot that bursts where it stops (Launcher A's splashRadius,
-- a full-draw Longbow A's blastRadius) wakes a refused body near that point even when nothing
-- refused is on its line. Where it stops, as a span of entry distances along the crosshair line:
-- in the takeable body that spends its hits; with fewer takeable bodies on the line than hits,
-- anywhere from the last one it passes to its range, since the client knows neither the ground
-- nor a wall the shot may meet first. Sorts takenEntries in place (the caller reuses the table).
function CampAim.StopSpan(
	takenEntries: { number },
	pierce: number?,
	range: number
): (number, number)
	local spent = hitsOf(pierce)
	table.sort(takenEntries)
	local count = #takenEntries
	if count >= spent then
		local stop = takenEntries[spent]
		return stop, stop
	end
	return if count > 0 then takenEntries[count] else 0, range
end

-- R17: true when a refused body's sphere, `along` the line and `off` it, lies farther than `reach`
-- (the burst radius + the sphere's radius + the variant's pad + the lag pad) from every point of
-- the stop span from..to. A tie counts against the shot, as the server's sphere test includes it.
function CampAim.BurstSpares(
	from: number,
	to: number,
	along: number,
	off: number,
	reach: number
): boolean
	local gap = math.max(0, from - along, along - to)
	return gap * gap + off * off > reach * reach
end

return CampAim
