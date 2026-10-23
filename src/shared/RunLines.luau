--!strict
-- L4 W3 (docs/prompts/l4-w3-contract.md §4.1, L4W3-5): the end screen's rows. A run's summary
-- carries, besides its totals, one line per SOURCE of what it paid (the raiders, each camp, the
-- boss, each chest, the key, the first clear, the mentor bonus), merged as the credits come in.
-- The lines are display only: the totals stay the truth, and nothing reads a line to pay.
--
-- Add is the server's (ArenaService.CreditSummary, CreditMentor); Read is every receiver's (the
-- Studio bridge's and the hub's ReturnData, the hub client's ExpeditionSummary), because a summary
-- crosses teleport data, which a client can forge. Pure: no service, no Instance, no clock, so
-- tools/crowd_harness tests the very functions both places run. The Types require is for
-- annotations alone.

local Types = require(script.Parent:WaitForChild("Types"))

-- Wire caps: lines per summary (a full party's four summaries of 16 lines stay a few KB of
-- teleport data), and bytes of a line's id, name and material. Past MAX, Add drops new lines and
-- the summary's totals still count what they paid.
local MAX = 16
local MAX_TEXT = 48
-- The seven sources (Types.RunLineKind); Read drops a line of any other kind.
local KINDS: { [string]: Types.RunLineKind } = {}
KINDS.raiders = "raiders"
KINDS.camp = "camp"
KINDS.boss = "boss"
KINDS.chest = "chest"
KINDS.key = "key"
KINDS.firstClear = "firstClear"
KINDS.mentor = "mentor"
table.freeze(KINDS)

local RunLines = {}

RunLines.MAX = MAX
RunLines.MAX_TEXT = MAX_TEXT

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function amount(value: any): number
	return if finite(value) and value >= 0 then value else 0
end

-- At most MAX_TEXT bytes, cut back to a character boundary so a long config name is shortened,
-- never dropped by Read and never left as a broken UTF-8 sequence on the wire.
local function clip(text: string): string
	if #text <= MAX_TEXT then
		return text
	end
	local cut = MAX_TEXT
	-- A continuation byte (10xxxxxx) at cut + 1 means the character there began at or before cut.
	while cut > 0 do
		local nextByte = string.byte(text, cut + 1)
		if nextByte == nil or nextByte < 0x80 or nextByte >= 0xC0 then
			break
		end
		cut -= 1
	end
	return string.sub(text, 1, cut)
end

-- One credit into the line of its source: the line of the same kind and id, else a new line at
-- the end while there are fewer than MAX. The line keeps its first name, and its material is the
-- first non-empty one credited.
function RunLines.Add(
	lines: { Types.RunLine },
	key: Types.RunLineKey,
	count: number,
	cash: number,
	material: string,
	materials: number,
	valor: number
): ()
	local id = clip(key.id)
	local given = clip(material)
	for _, line in lines do
		if line.kind == key.kind and line.id == id then
			line.count += amount(count)
			line.cash += amount(cash)
			line.materials += amount(materials)
			line.valor += amount(valor)
			if line.material == "" then
				line.material = given
			end
			return
		end
	end
	if #lines >= MAX then
		return
	end
	table.insert(lines, {
		kind = key.kind,
		id = id,
		name = clip(key.name),
		count = amount(count),
		cash = amount(cash),
		material = given,
		materials = amount(materials),
		valor = amount(valor),
	})
end

local function text(value: any): boolean
	return type(value) == "string" and #value <= MAX_TEXT
end

-- A line list as a receiver may trust it: the first MAX entries only, each kept as a fresh copy
-- when every field has its shape, dropped otherwise; anything that is not a list reads as none.
function RunLines.Read(value: any): { Types.RunLine }
	local lines: { Types.RunLine } = {}
	if type(value) ~= "table" then
		return lines
	end
	for index = 1, MAX do
		local raw: any = value[index]
		if type(raw) ~= "table" then
			continue
		end
		local kind: Types.RunLineKind? = if type(raw.kind) == "string" then KINDS[raw.kind] else nil
		if
			kind == nil
			or not text(raw.id)
			or not text(raw.name)
			or not text(raw.material)
			or not (finite(raw.count) and raw.count >= 0)
			or not (finite(raw.cash) and raw.cash >= 0)
			or not (finite(raw.materials) and raw.materials >= 0)
			or not (finite(raw.valor) and raw.valor >= 0)
		then
			continue
		end
		table.insert(lines, {
			kind = kind,
			id = raw.id,
			name = raw.name,
			count = raw.count,
			cash = raw.cash,
			material = raw.material,
			materials = raw.materials,
			valor = raw.valor,
		})
	end
	return lines
end

return RunLines
