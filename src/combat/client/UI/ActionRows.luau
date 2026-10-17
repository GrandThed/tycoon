--!strict
-- The run layer's bottom-left buttons in rows (the L2 W1 fix round's c1). With Abilities between
-- Map and Return the lobby row grew to 280 design px, and on a phone it ran under the health bar
-- (landscape) or the Dash and slot buttons (portrait). Each row now ends a clearance short of
-- whatever stands in its own height band, and the buttons that do not fit go up a row.
--
-- Pure: numbers in, numbers out, no Instance; CombatHud lays the buttons out from the answer.
-- Rows count from the bottom. They fill from the bottom up with the LAST buttons first, so the
-- order reads left to right, top to bottom, and the bottom row is never the one left short.
-- A row always takes at least one button, even one wider than its room: there is nowhere else
-- for it to go.

local ActionRows = {}

-- Something on the same screen the rows must keep clear of, in the HUD's own px: its left edge
-- and its vertical extent (top above bottom).
export type Obstacle = { left: number, top: number, bottom: number }

-- How the rows sit: design px for the buttons (`gap` between buttons and between rows,
-- `rowHeight`), screen px for the rest (`margin` the rows' left edge, `bottom` the bottom row's
-- bottom edge, `clearance` how far the rows stay from an obstacle), and `scale` between them.
export type Layout = {
	scale: number,
	gap: number,
	rowHeight: number,
	margin: number,
	bottom: number,
	clearance: number,
}

-- One button's place: `row` (1 = bottom) and `x`, design px from the rows' left edge.
export type Place = { row: number, x: number }

-- Design px of row `row` (1 = bottom) left free by `obstacles`; math.huge when nothing stands in
-- its band.
function ActionRows.Room(layout: Layout, obstacles: { Obstacle }, row: number): number
	local step = (layout.rowHeight + layout.gap) * layout.scale
	local rowBottom = layout.bottom - (row - 1) * step
	local rowTop = rowBottom - layout.rowHeight * layout.scale
	local limit = math.huge
	for _, obstacle in obstacles do
		if
			obstacle.top - layout.clearance < rowBottom
			and obstacle.bottom + layout.clearance > rowTop
		then
			limit = math.min(limit, obstacle.left - layout.clearance)
		end
	end
	if limit == math.huge or layout.scale <= 0 then
		return math.huge
	end
	return (limit - layout.margin) / layout.scale
end

-- The place of each button of `widths` (design px, in reading order), how many rows they take
-- (0 for no buttons) and the widest row's width in design px.
function ActionRows.Pack(
	widths: { number },
	layout: Layout,
	obstacles: { Obstacle }
): ({ Place }, number, number)
	local places: { Place } = table.create(#widths)
	local last = #widths
	local rows = 0
	local widest = 0
	while last >= 1 do
		rows += 1
		local room = ActionRows.Room(layout, obstacles, rows)
		local first = last
		local used = widths[last]
		while first > 1 and used + layout.gap + widths[first - 1] <= room do
			first -= 1
			used += layout.gap + widths[first]
		end
		local x = 0
		for index = first, last do
			places[index] = { row = rows, x = x }
			x += widths[index] + layout.gap
		end
		widest = math.max(widest, used)
		last = first - 1
	end
	return places, rows, widest
end

return ActionRows
