--!strict
-- Which of a strike's candidates it lands on, and so which ones it chains from (the L1c second
-- fix round's F4). Pure: the caller strikes, this only walks the list, so tools/crowd_harness
-- tests the very loop WeaponService runs.
--
-- A held resident (a walled camp's ambush before the close) answers CrowdService.Damage with
-- "held": the hit does nothing and StrikeTally drops it. Counted as a landed body it would still
-- spend a slot of the strike's cap, seed a chain and be named in the strike's links, so a Storm
-- Coil cast over the wall drew bolts to the hidden posts. Here a candidate `land` refuses is
-- passed over: the cap goes to bodies that took the hit, and only those carry a chain on.

local StrikePick = {}

-- Strikes `eligible` in order through `land` until `cap` of them landed (math.huge = every one;
-- 0 = none). land(candidate) strikes it and answers false when the hit did not land (held).
-- Returns the landed candidates, in order, and the index in `eligible` of the one that spent the
-- cap (nil when it was never spent).
function StrikePick.Seeds<C>(eligible: { C }, cap: number, land: (C) -> boolean): ({ C }, number?)
	local seeds: { C } = {}
	if not (cap > 0) then
		return seeds, nil
	end
	for index, candidate in eligible do
		if land(candidate) then
			table.insert(seeds, candidate)
			if #seeds >= cap then
				return seeds, index
			end
		end
	end
	return seeds, nil
end

-- A chain's next jump: the first of `nearby` (nearest first) that `taken` does not hold and that
-- `land` lands on; nil = none. One `land` refuses is passed over and the next one is tried, so a
-- chain never jumps to, or on from, a body the hit did not reach.
function StrikePick.Next<C>(nearby: { C }, taken: (C) -> boolean, land: (C) -> boolean): C?
	for _, candidate in nearby do
		if not taken(candidate) and land(candidate) then
			return candidate
		end
	end
	return nil
end

return StrikePick
