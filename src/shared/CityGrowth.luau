--!strict
-- Plot growth tier for M9 city dressing (docs/INTERFACES.md "Growth tier"). Pure: no Roblox
-- globals, so tools/sim_economy.py mirrors it 1:1; every tunable arrives as an argument from
-- CityDressing.json.

local CityGrowth = {}

-- Owning a slot outweighs levelling one so a fresh purchase visibly grows the town.
function CityGrowth.Score(ownedCount: number, totalLevels: number, ownedWeight: number): number
	return ownedCount * ownedWeight + totalLevels
end

-- Counting (rather than walking until the first miss) keeps the tier monotonic in score even if
-- a hand-edited config lists the thresholds out of order.
function CityGrowth.TierFor(score: number, thresholds: { number }): number
	local tier = 0
	for _, threshold in thresholds do
		if threshold <= score then
			tier += 1
		end
	end
	return tier
end

return CityGrowth
