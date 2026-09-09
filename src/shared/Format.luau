--!strict
-- Number formatting per docs/INTERFACES.md: plain floored integers below the grouping base,
-- then K/M/B/T and aa, ab, … suffixes; per-second rates with bounded decimals; humanized
-- durations. The constants below are part of the frozen algorithms, not tunable game balance,
-- which is why they live here and not in Config.

local GROUPING_BASE = 1000
local ONE_DECIMAL_BELOW = 100
local DECIMAL_SCALE = 10
local NAMED_SUFFIXES = { "K", "M", "B", "T" }
local LETTER_A_BYTE = string.byte("a")
local ALPHABET_SIZE = 26

-- Rate tiers (M3): two decimals below the first bound, one below the second, Cash beyond.
local RATE_TWO_DECIMALS_BELOW = 10
local RATE_ONE_DECIMAL_BELOW = 1000
local RATE_LOW_DECIMALS = 2
local RATE_MID_DECIMALS = 1

local SECONDS_PER_MINUTE = 60
local MINUTES_PER_HOUR = 60

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

-- Floor (never round) to `decimals` places, then drop trailing zeros and a dangling point, so
-- 2.5 renders "2.5" and 7 renders "7" at the same tier. Same floor-then-scale approach as
-- Format.Cash so both share one rounding behavior.
local function floorToDecimals(n: number, decimals: number): string
	local scale = DECIMAL_SCALE ^ decimals
	local floored = math.floor(n * scale) / scale
	local text = string.format("%." .. decimals .. "f", floored)
	if string.find(text, ".", 1, true) ~= nil then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- Per-second values: sub-10 rates keep two decimals so a 0.35/s starter never renders "0/s".
-- The UI appends "/s" itself.
function Format.Rate(n: number): string
	if n < RATE_TWO_DECIMALS_BELOW then
		return floorToDecimals(n, RATE_LOW_DECIMALS)
	end
	if n < RATE_ONE_DECIMAL_BELOW then
		return floorToDecimals(n, RATE_MID_DECIMALS)
	end
	return Format.Cash(n)
end

-- "3h 12m" / "12m 5s" / "45s"; the two largest non-empty units only, so the welcome-back card
-- stays one short line. Negative or zero ⇒ "0s".
function Format.Duration(seconds: number): string
	if seconds <= 0 then
		return "0s"
	end
	local whole = math.floor(seconds)
	local secondsPerHour = SECONDS_PER_MINUTE * MINUTES_PER_HOUR
	local hours = math.floor(whole / secondsPerHour)
	local minutes = math.floor((whole % secondsPerHour) / SECONDS_PER_MINUTE)
	local remainder = whole % SECONDS_PER_MINUTE
	if hours > 0 then
		return `{hours}h {minutes}m`
	end
	if minutes > 0 then
		return `{minutes}m {remainder}s`
	end
	return `{remainder}s`
end

return Format
