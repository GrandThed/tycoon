--!strict
-- Where a panel (Build / Legacy / Settings) sits for the current viewport. Portrait keeps
-- the M1 bottom sheet centered above the bottom bar; landscape (width > height) docks the
-- panel to a right-hand column of fixed design width spanning from the top margin down to
-- the bottom-bar zone, so the bottom bar can stay bottom-center without overlap. One
-- function so all three panels agree and UIController re-evaluates it on every resize.

local Theme = require(script.Parent:WaitForChild("Theme"))

export type Dock = {
	scale: number,
	landscape: boolean,
	anchor: Vector2,
	position: UDim2,
	size: UDim2, -- design px; the panel's UIScale multiplies it
	slideOffset: UDim2, -- where the open tween starts relative to `position`
}

local PanelDock = {}

function PanelDock.IsLandscape(viewportSize: Vector2): boolean
	return viewportSize.X > viewportSize.Y
end

function PanelDock.Compute(scale: number, viewportSize: Vector2, designHeight: number): Dock
	-- UIScale multiplies size, not position offsets, so margins scale by hand.
	local margin = Theme.SCREEN_MARGIN * scale
	local bottomZone = Theme.PANEL_BOTTOM_MARGIN * scale
	if PanelDock.IsLandscape(viewportSize) then
		local height =
			math.max((viewportSize.Y - margin - bottomZone) / scale, Theme.PANEL_MIN_HEIGHT)
		return {
			scale = scale,
			landscape = true,
			anchor = Vector2.new(1, 0),
			position = UDim2.new(1, -margin, 0, margin),
			size = UDim2.fromOffset(Theme.PANEL_WIDTH, height),
			slideOffset = UDim2.fromOffset(Theme.PANEL_SLIDE_OFFSET, 0),
		}
	end
	-- Portrait: derive the height from what fits between the top bar and the bottom bar
	-- (M1 review) instead of scaling the canvas down, which shrank tap targets.
	local topZone = (Theme.SCREEN_MARGIN * 2 + Theme.TOP_BAR_HEIGHT) * scale
	local budget = (viewportSize.Y - topZone - bottomZone) / scale
	local maxHeight = math.max(designHeight, Theme.PANEL_MIN_HEIGHT)
	local height = math.clamp(budget, Theme.PANEL_MIN_HEIGHT, maxHeight)
	return {
		scale = scale,
		landscape = false,
		anchor = Vector2.new(0.5, 1),
		position = UDim2.new(0.5, 0, 1, -bottomZone),
		size = UDim2.fromOffset(Theme.PANEL_WIDTH, height),
		slideOffset = UDim2.fromOffset(0, Theme.PANEL_SLIDE_OFFSET),
	}
end

return PanelDock
