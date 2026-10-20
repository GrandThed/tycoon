--!strict
-- The Armory screen's tier track (docs/prompts/l3-w1-contract.md, L3-20; Ben chose the full
-- ladder with the weapon's window lit, MISSIONS_DESIGN section 24): every tier of the ladder as
-- a pip, five bands of four, each band in its level's theme colour, so "tier 9" sits in the same
-- place for every weapon. A lit pip is held, an open one is in the window above the tier, a dim
-- one is outside the window. The window's start and top carry their numbers under the pip, and
-- the tier the family stands at has a gold ring. A relic is one pip.
--
-- The pips come from ArmoryModel.Pips; this only draws them. Pips stretch to the width it is
-- given, never past ARMORY_SCREEN_PIP_MAX_WIDTH, and the row stays left-aligned.

local ArmoryModel = require(script.Parent:WaitForChild("ArmoryModel"))
local Create = require(script.Parent:WaitForChild("Create"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Track = {
	frame: Frame,
	Show: (pips: { ArmoryModel.Pip }) -> (),
	SetWidth: (width: number) -> (),
	Destroy: () -> (),
}

type PipFrame = { frame: Frame, stroke: UIStroke, mark: TextLabel }

local ArmoryTrack = {}

-- The track's height in design px: the pips and the row of numbers under them.
function ArmoryTrack.Height(): number
	return Theme.ARMORY_SCREEN_PIP_HEIGHT
		+ Theme.ARMORY_SCREEN_PIP_MARK_GAP
		+ Theme.ARMORY_SCREEN_PIP_MARK_HEIGHT
end

local function colorOf(rgb: { number }?): Color3
	if
		rgb ~= nil
		and type(rgb[1]) == "number"
		and type(rgb[2]) == "number"
		and type(rgb[3]) == "number"
	then
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end
	return Theme.MAP_COLOR_OFF
end

function ArmoryTrack.new(parent: Instance): Track
	local frame = Create("Frame", {
		Name = "Track",
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, ArmoryTrack.Height()),
		ZIndex = Theme.ZINDEX_CARD,
		Parent = parent,
	}) :: Frame
	local pips: { PipFrame } = {}
	local shown: { ArmoryModel.Pip } = {}
	local view = { width = 0 }

	local function ensure(count: number): ()
		while #pips < count do
			local pip = Create("Frame", {
				Name = "Pip",
				Active = false,
				BorderSizePixel = 0,
				ZIndex = Theme.ZINDEX_CARD,
				Parent = frame,
			}) :: Frame
			Create(
				"UICorner",
				{ CornerRadius = UDim.new(0, Theme.ARMORY_SCREEN_PIP_CORNER), Parent = pip }
			)
			local stroke = Create("UIStroke", {
				Color = Theme.MAP_COLOR_GOLD,
				Thickness = Theme.STROKE_THICKNESS,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Enabled = false,
				Parent = pip,
			}) :: UIStroke
			local mark = Create("TextLabel", {
				Name = "Mark",
				Active = false,
				BackgroundTransparency = 1,
				Font = Theme.FONT_BOLD,
				TextSize = Theme.ARMORY_SCREEN_PIP_MARK_TEXT,
				TextColor3 = Theme.MAP_COLOR_DIM,
				Text = "",
				ZIndex = Theme.ZINDEX_CARD,
				Parent = frame,
			}) :: TextLabel
			table.insert(pips, { frame = pip, stroke = stroke, mark = mark })
		end
		for index, pip in pips do
			pip.frame.Visible = index <= count
			pip.mark.Visible = index <= count
		end
	end

	-- Pip width from the space: pips plus a small gap inside a band, a wider one between bands.
	local function place(): ()
		local count = #shown
		if count == 0 then
			return
		end
		local bands = 0
		local last = -1
		for _, pip in shown do
			if pip.band ~= last then
				bands += 1
				last = pip.band
			end
		end
		local gaps = (count - bands) * Theme.ARMORY_SCREEN_PIP_GAP
			+ (bands - 1) * Theme.ARMORY_SCREEN_PIP_BAND_GAP
		local width = math.clamp(
			math.floor((view.width - gaps) / count),
			Theme.ARMORY_SCREEN_PIP_MIN_WIDTH,
			Theme.ARMORY_SCREEN_PIP_MAX_WIDTH
		)
		local x = 0
		last = shown[1].band
		for index, pip in shown do
			if index > 1 then
				x += if pip.band ~= last
					then Theme.ARMORY_SCREEN_PIP_BAND_GAP
					else Theme.ARMORY_SCREEN_PIP_GAP
			end
			last = pip.band
			local entry = pips[index]
			entry.frame.Position = UDim2.fromOffset(x, 0)
			entry.frame.Size = UDim2.fromOffset(width, Theme.ARMORY_SCREEN_PIP_HEIGHT)
			entry.mark.Position = UDim2.fromOffset(
				x - Theme.ARMORY_SCREEN_PIP_MARK_SPILL,
				Theme.ARMORY_SCREEN_PIP_HEIGHT + Theme.ARMORY_SCREEN_PIP_MARK_GAP
			)
			entry.mark.Size = UDim2.fromOffset(
				width + Theme.ARMORY_SCREEN_PIP_MARK_SPILL * 2,
				Theme.ARMORY_SCREEN_PIP_MARK_HEIGHT
			)
			x += width
		end
		frame.Size = UDim2.fromOffset(x, ArmoryTrack.Height())
	end

	local track: Track = {
		frame = frame,
		Show = function(list: { ArmoryModel.Pip })
			shown = list
			ensure(#list)
			for index, pip in list do
				local entry = pips[index]
				local color = colorOf(pip.color)
				if pip.state == "lit" then
					entry.frame.BackgroundColor3 = color
					entry.frame.BackgroundTransparency = 0
				elseif pip.state == "open" then
					entry.frame.BackgroundColor3 = color
					entry.frame.BackgroundTransparency = Theme.ARMORY_SCREEN_PIP_OPEN_TRANSPARENCY
				else
					entry.frame.BackgroundColor3 = Theme.MAP_COLOR_LOCKED
					entry.frame.BackgroundTransparency = Theme.ARMORY_SCREEN_PIP_DIM_TRANSPARENCY
				end
				entry.stroke.Enabled = pip.current
				entry.mark.Text = pip.mark or ""
				entry.mark.TextColor3 = if pip.current
					then Theme.MAP_COLOR_GOLD
					else Theme.MAP_COLOR_DIM
			end
			place()
		end,
		SetWidth = function(width: number)
			view.width = width
			place()
		end,
		Destroy = function()
			table.clear(pips)
			frame:Destroy()
		end,
	}
	return track
end

return ArmoryTrack
