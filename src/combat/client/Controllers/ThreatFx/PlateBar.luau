--!strict
-- ThreatFx child, drawn by CrowdRenderer: the two-row bar over a body whose kind carries a
-- plate (docs/INTERFACES.md "P4 contracts" -> "Wave 2", "The plate"). The top row is the
-- plate, in the plate's colour; the row under it is the health. While the plate is on, its
-- row runs down and the health row stands full (health cannot change under a plate); when it
-- breaks, the plate row is empty and the health row starts to run down. So the player reads
-- "break this first, then that" off one glance, and sees why light fire does nothing.
--
-- The snapshot carries one fraction: the plate's while the body is plated, the health's
-- after. CrowdRenderer hands both shares over; nothing here knows the wire.
--
-- Billboards are pooled (a set has a handful of plated bodies), sized in pixels so a bar is
-- as readable at forty studs on a phone as up close, and always on top, because a plated
-- elite is usually standing in a crowd.

local Players = game:GetService("Players")

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))

export type Bar = {
	gui: BillboardGui,
	plate: Frame,
	health: Frame,
	plateShown: number,
	healthShown: number,
}

local free: { Bar } = {}
local all: { Bar } = {}

local PlateBar = {}

local function row(parent: Instance, order: number, color: Color3): Frame
	local track = Create("Frame", {
		Name = "Row",
		Active = false,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, Theme.COMBAT_RANGE_PLATE_BAR_HEIGHT),
		BackgroundColor3 = Theme.COLOR_BG,
		BackgroundTransparency = Theme.COMBAT_RANGE_PLATE_BAR_BG_TRANSPARENCY,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	return Create("Frame", {
		Name = "Fill",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = track,
	}) :: Frame
end

local function build(playerGui: Instance): Bar
	local gui = Create("BillboardGui", {
		Name = "RangePlateBar",
		Active = false,
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		MaxDistance = Theme.COMBAT_RANGE_PLATE_BAR_MAX_DISTANCE,
		Size = UDim2.fromOffset(
			Theme.COMBAT_RANGE_PLATE_BAR_WIDTH,
			Theme.COMBAT_RANGE_PLATE_BAR_HEIGHT * 2 + Theme.COMBAT_RANGE_PLATE_BAR_GAP
		),
		Enabled = false,
		Parent = playerGui,
	}) :: BillboardGui
	Create("UIListLayout", {
		Padding = UDim.new(0, Theme.COMBAT_RANGE_PLATE_BAR_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gui,
	})
	local bar: Bar = {
		gui = gui,
		plate = row(gui, 1, Theme.COMBAT_RANGE_PLATE_COLOR),
		health = row(gui, 2, Theme.COMBAT_RANGE_ENEMY_HEALTH_COLOR),
		plateShown = 1,
		healthShown = 1,
	}
	table.insert(all, bar)
	return bar
end

-- A bar over `adornee` (the body's head), `rise` studs above its centre. nil before the
-- PlayerGui exists.
function PlateBar.Take(adornee: BasePart, rise: number): Bar?
	local pooled = table.remove(free)
	local bar: Bar
	if pooled ~= nil then
		bar = pooled
	else
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui == nil then
			return nil
		end
		bar = build(playerGui)
	end
	bar.gui.Adornee = adornee
	bar.gui.StudsOffsetWorldSpace = Vector3.new(0, rise, 0)
	bar.gui.Enabled = true
	return bar
end

-- Shares 0-1 of the plate and of the health. Writes only what changed.
function PlateBar.Set(bar: Bar, plate: number, health: number): ()
	if math.abs(plate - bar.plateShown) > 0.002 then
		bar.plateShown = plate
		bar.plate.Size = UDim2.fromScale(math.clamp(plate, 0, 1), 1)
	end
	if math.abs(health - bar.healthShown) > 0.002 then
		bar.healthShown = health
		bar.health.Size = UDim2.fromScale(math.clamp(health, 0, 1), 1)
	end
end

function PlateBar.Give(bar: Bar): ()
	bar.gui.Enabled = false
	table.insert(free, bar)
end

function PlateBar.Destroy(): ()
	for _, bar in all do
		bar.gui:Destroy()
	end
	table.clear(all)
	table.clear(free)
end

return PlateBar
