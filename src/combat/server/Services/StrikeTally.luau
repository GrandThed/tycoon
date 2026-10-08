--!strict
-- The hits of one resolved attack, as its CombatFxStrike lists them (docs/INTERFACES.md "P1
-- contracts" for the strike; "P4 contracts" -> "Wave 2 — roles" for the plate). Every weapon
-- strike, projectile, chain jump and ability strike or tick of the range adds its hits here,
-- so this is the one place a StrikeHit is built.
--
-- An enemy struck more than once by one attack (a chain that comes back, a multi-hit ability)
-- is one entry, with one exception the client draws as two numbers: what went to its plate and
-- what went to its health are separate entries (lead ruling B, wave 2). So an enemy has at most
-- a plate entry (`plate`, and `broke` if this attack emptied the plate) and a plain one.
-- `blocked` marks an entry whose whole amount a plate stopped: it is a hit of 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

-- What CrowdService.Damage said of the hit besides its number.
export type Verdict = "blocked" | "plate" | "broke"

export type Tally = {
	hits: { Types.StrikeHit },
	-- Distinct enemies among `hits`: what the readouts count (an enemy whose plate broke under
	-- this attack has two entries and is still one enemy hit).
	enemies: number,
	kills: number,
	-- Plate damage counts as damage dealt; a blocked hit adds nothing.
	dealt: number,
}

local StrikeTally = {}

function StrikeTally.New(): Tally
	return { hits = {}, enemies = 0, kills = 0, dealt = 0 }
end

-- One hit of the attack on enemy `id`: `dealt` and `killed` as CrowdService.Damage returned
-- them, `verdict` its third value.
function StrikeTally.Add(
	tally: Tally,
	id: number,
	dealt: number,
	crit: boolean,
	killed: boolean,
	verdict: Verdict?
): ()
	local blocked = verdict == "blocked"
	local onPlate = verdict == "plate" or verdict == "broke"
	tally.dealt += dealt
	if killed then
		tally.kills += 1
	end
	-- The entry this hit joins: the enemy's entry of the same kind (plate or health). A blocked
	-- hit adds nothing and joins whatever entry the enemy has; a real hit takes over an entry
	-- that so far was only blocked.
	local known = false
	local entry: Types.StrikeHit? = nil
	for _, hit in tally.hits do
		if hit.id == id then
			known = true
			if blocked or hit.blocked == true or (hit.plate == true) == onPlate then
				entry = hit
				break
			end
		end
	end
	if entry == nil then
		table.insert(tally.hits, {
			id = id,
			amount = dealt,
			crit = crit,
			killed = killed,
			blocked = if blocked then true else nil,
			plate = if onPlate then true else nil,
			broke = if verdict == "broke" then true else nil,
		})
		if not known then
			tally.enemies += 1
		end
		return
	end
	entry.amount += dealt
	entry.crit = entry.crit or crit
	entry.killed = entry.killed or killed
	if not blocked then
		entry.blocked = nil
		entry.plate = if onPlate then true else nil
		if verdict == "broke" then
			entry.broke = true
		end
	end
end

return StrikeTally
