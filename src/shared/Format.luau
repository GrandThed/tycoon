--!strict
-- Number formatting per docs/INTERFACES.md: plain floored integers below the grouping base,
-- then K/M/B/T and aa, ab, … suffixes. The constants below are part of the frozen algorithm,
-- not tunable game balance, which is why they live here and not in Config.

local GROUPING_BASE = 1000
local ONE_DECIMAL_BELOW = 100
local DECIMAL_SCALE = 10
local NAMED_SUFFIXES = { "K", "M", "B", "T" }
local LETTER_A_BYTE = string.byte("a")
local ALPHABET_SIZE = 26

local Format = {}

function Format.Cash(n: number): string
	if n < GROUPING_BASE then
		return tostring(math.floor(n))
	end

	local value = n
	local tier = 0
	while value >= GROUPING_BASE do
		value /= GROUPING_BASE
		tier += 1
	end

	local suffix = NAMED_SUFFIXES[tier]
	if suffix == nil then
		-- 0-based distance past the last named suffix: tier 5 => "aa", 6 => "ab", …
		local index = tier - #NAMED_SUFFIXES - 1
		suffix = string.char(LETTER_A_BYTE + math.floor(index / ALPHABET_SIZE))
			.. string.char(LETTER_A_BYTE + index % ALPHABET_SIZE)
	end

	if value < ONE_DECIMAL_BELOW then
		-- Floor to one decimal so 999,950 renders "999.9K", never rounding up into "1000.0K".
		local floored = math.floor(value * DECIMAL_SCALE) / DECIMAL_SCALE
		if floored == math.floor(floored) then
			-- Strip the trailing ".0" per the frozen formatting rules.
			return tostring(math.floor(floored)) .. suffix
		end
		return string.format("%.1f", floored) .. suffix
	end
	return tostring(math.floor(value)) .. suffix
end

return Format
