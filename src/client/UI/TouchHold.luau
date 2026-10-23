--!strict
-- The L4 W3 fix round's F11 (review slice 3 m1): Roblox's touch thumbstick and jump button step
-- aside while a city sheet covers the world. The hub's EraCityHUD and Roblox's TouchGui share
-- DisplayOrder 0, which sets no order between them, so on a phone the jump button could sit over
-- the map's Depart or the report's Dismiss and take the tap: the character jumps behind the scrim
-- and nothing departs.
--
-- One count for every holder in the city (UI/HubMap, the run report in UIController): touch
-- controls are off while any hold is out, and when the last one goes they come back to what they
-- were when the first one was taken, never to a value a later holder saw. A reason holds at most
-- once, so a repeated Hold or Release of the same reason changes nothing.
--
-- ArmoryScreen keeps its own R9 toggle (the combat place maps it too, and this module is the
-- hub's). That toggle and this count must never both have a value put aside, or the one that lets
-- go second restores the other's "off". The hub keeps them apart by order: it closes the Armory
-- before a hold is taken (HubMap's onOpenChanged runs the host's closes first; the report closes
-- it before its Show) and releases the map's hold before the Armory opens (UIController's
-- togglePanel), so whichever opens second puts aside the value the first one restored.

local GuiService = game:GetService("GuiService")

local TouchHold = {}

local holds = {
	reasons = {} :: { [string]: boolean },
	count = 0,
	-- GuiService.TouchControlsEnabled as the first hold found it; nil while no hold is out.
	saved = nil :: boolean?,
}

function TouchHold.Hold(reason: string): ()
	if holds.reasons[reason] == true then
		return
	end
	holds.reasons[reason] = true
	holds.count += 1
	if holds.count == 1 then
		holds.saved = GuiService.TouchControlsEnabled
		GuiService.TouchControlsEnabled = false
	end
end

function TouchHold.Release(reason: string): ()
	if holds.reasons[reason] ~= true then
		return
	end
	holds.reasons[reason] = nil
	holds.count -= 1
	if holds.count == 0 then
		local saved = holds.saved
		holds.saved = nil
		if saved ~= nil then
			GuiService.TouchControlsEnabled = saved
		end
	end
end

return TouchHold
