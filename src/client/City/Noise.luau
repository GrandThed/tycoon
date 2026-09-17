--!strict
-- Pure, order-free randomness for city dressing (docs/INTERFACES.md "Wave 1b — natural paths").
-- Scatter's seed hash and the road meander both live here, so a path's wobble is a function of
-- (plot seed, line key, arc length) alone: it never depends on how many Random draws came
-- before or on which stretches of road happen to be visible yet.

local HASH_MULTIPLIER = 31
local HASH_MODULUS = 16777216 -- 2^24 keeps every intermediate exact in a double
local FULL_TURN = 2 * math.pi
-- The second sine runs at an irrational ratio of the first, so the sum never visibly repeats.
local SECOND_WAVE_RATIO = math.sqrt(2)

export type Phases = { number }

local Noise = {}

-- Small pure string hash (31-multiplier over bytes, mod 2^24): identical on every client.
function Noise.Hash(text: string): number
	local hash = 0
	for index = 1, #text do
		hash = (hash * HASH_MULTIPLIER + string.byte(text, index)) % HASH_MODULUS
	end
	return hash
end

-- Four phases in [0, 2pi): two for the lateral wave, two for the width wave.
function Noise.Phases(key: string): Phases
	local phases: Phases = {}
	for index = 1, 4 do
		table.insert(phases, Noise.Hash(`{key}#{index}`) / HASH_MODULUS * FULL_TURN)
	end
	return phases
end

-- Two summed sines, normalised to [-1, 1].
function Noise.Wave(arc: number, wavelength: number, phaseA: number, phaseB: number): number
	local base = FULL_TURN * arc / wavelength
	return (math.sin(base + phaseA) + math.sin(base / SECOND_WAVE_RATIO + phaseB)) / 2
end

return Noise
