-- Cases for the L4 W3 fix round, ui-engineer A's (docs/prompts/l4-w3-fix-round.md F11; the review's
-- slice 3 m1): UI/TouchHold, the one count that keeps Roblox's touch controls off while the city's
-- map or run report is up. The module reads GuiService.TouchControlsEnabled through `game`, so the
-- cases hand it a fake GuiService (tests.luau's `services`) before the first load. What they prove:
-- off while any hold is out, back to what the FIRST hold found when the last one goes, a reason
-- counted once, a release of a reason never held a no-op; and, against a stand-in for
-- ArmoryScreen's own R9 toggle (save on open, restore on close), that the hub's order (close the
-- Armory before a hold is taken, release the map's hold before the Armory opens) gives the controls
-- back in every hand-off, while the other order leaves them off for good. That order lives in
-- UIController and HubMap, which need `game` to load: run_harness.py reads those lines as text.
-- Appended by run_harness.py after the earlier case files, so every local of theirs is in scope
-- (services, load, check). Everything hangs off the L4H table (the 200-local limit), and every
-- group runs behind L4H.group, so a group that throws fails one check and the bundle goes on.

print("L4 W3 fix round: the city's touch hold (TouchHold)")

local L4H: any = {
	gui = { TouchControlsEnabled = true },
}
services.GuiService = L4H.gui
L4H.Hold = load("TouchHold")

function L4H.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `l4w3 hub group "{name}" threw: {tostring(problem)}`)
	end
	-- Every group leaves no hold out and the controls on, so the next one starts clean.
	for _, reason in { "hubMap", "runReport", "other" } do
		L4H.Hold.Release(reason)
	end
	L4H.gui.TouchControlsEnabled = true
end

-- A stand-in for ArmoryScreen's R9 toggle (ArmoryScreen.luau's setOpen): it puts the value aside
-- when it opens and gives it back when it closes, knowing nothing of TouchHold.
function L4H.armory(): any
	local armory: any = { saved = nil }
	function armory.open(): ()
		if armory.saved == nil then
			armory.saved = L4H.gui.TouchControlsEnabled
			L4H.gui.TouchControlsEnabled = false
		end
	end
	function armory.close(): ()
		if armory.saved ~= nil then
			L4H.gui.TouchControlsEnabled = armory.saved
			armory.saved = nil
		end
	end
	return armory
end

function L4H.countTests(): ()
	local Hold = L4H.Hold
	local gui = L4H.gui
	Hold.Hold("hubMap")
	check(gui.TouchControlsEnabled == false, "touch hold: one hold turns the touch controls off")
	Hold.Release("hubMap")
	check(gui.TouchControlsEnabled == true, "touch hold: its release turns them back on")

	Hold.Hold("hubMap")
	Hold.Hold("runReport")
	Hold.Release("hubMap")
	check(gui.TouchControlsEnabled == false, "touch hold: off while a second hold is still out")
	Hold.Release("runReport")
	check(gui.TouchControlsEnabled == true, "touch hold: on once the last hold goes")

	Hold.Hold("hubMap")
	Hold.Hold("hubMap")
	Hold.Release("hubMap")
	check(gui.TouchControlsEnabled == true, "touch hold: a reason held twice counts once")

	Hold.Hold("hubMap")
	Hold.Release("runReport")
	check(
		gui.TouchControlsEnabled == false,
		"touch hold: releasing a reason never held changes nothing"
	)
	Hold.Release("hubMap")
	Hold.Release("hubMap")
	check(
		gui.TouchControlsEnabled == true,
		"touch hold: a second release of one reason changes nothing"
	)

	gui.TouchControlsEnabled = false
	Hold.Hold("hubMap")
	Hold.Release("hubMap")
	check(gui.TouchControlsEnabled == false, "touch hold: controls already off come back off")

	gui.TouchControlsEnabled = true
	Hold.Hold("hubMap")
	Hold.Hold("runReport") -- finds them off (the first hold's doing)
	Hold.Release("runReport")
	Hold.Release("hubMap")
	check(
		gui.TouchControlsEnabled == true,
		"touch hold: a later hold never puts aside the value it found (only the first hold does)"
	)
end

function L4H.handOffTests(): ()
	local Hold = L4H.Hold
	local gui = L4H.gui

	-- The Armory open, then the map: HubMap runs the host's closes (the Armory) before its hold.
	local armory = L4H.armory()
	armory.open()
	armory.close()
	Hold.Hold("hubMap")
	check(gui.TouchControlsEnabled == false, "hand-off Armory -> map: off while the map is open")
	Hold.Release("hubMap")
	check(gui.TouchControlsEnabled == true, "hand-off Armory -> map: on after the map closes")

	-- The map open, then the Armory: togglePanel closes the map before the Armory's toggle.
	Hold.Hold("hubMap")
	Hold.Release("hubMap")
	armory.open()
	check(gui.TouchControlsEnabled == false, "hand-off map -> Armory: off while the Armory is open")
	armory.close()
	check(gui.TouchControlsEnabled == true, "hand-off map -> Armory: on after the Armory closes")

	-- Armory -> map -> Armory, the reviewer's case, in the hub's order.
	armory.open()
	armory.close()
	Hold.Hold("hubMap")
	Hold.Release("hubMap")
	armory.open()
	armory.close()
	check(gui.TouchControlsEnabled == true, "hand-off Armory -> map -> Armory: on at the end")

	-- The report over the map and the Armory: both close before the report's hold.
	armory.open()
	Hold.Hold("hubMap")
	Hold.Release("hubMap")
	armory.close()
	Hold.Hold("runReport")
	check(gui.TouchControlsEnabled == false, "report: off while the report is up")
	Hold.Release("runReport")
	check(gui.TouchControlsEnabled == true, "report: on after Dismiss")
end

-- Why the order is pinned: with the Armory's toggle and a hold both holding a value at once, the
-- one that lets go second restores the other's "off". These checks describe the stand-ins, not
-- the hub: they pass because the wrong order fails.
function L4H.wrongOrderTests(): ()
	local Hold = L4H.Hold
	local gui = L4H.gui
	local armory = L4H.armory()
	armory.open()
	Hold.Hold("hubMap") -- the hold taken before the Armory closed
	armory.close()
	Hold.Release("hubMap")
	check(
		gui.TouchControlsEnabled == false,
		"wrong order (hold before the Armory closes) leaves the controls off: why HubMap closes first"
	)
	gui.TouchControlsEnabled = true
	Hold.Hold("hubMap")
	armory.open() -- the Armory opened before the map let go
	Hold.Release("hubMap")
	check(
		gui.TouchControlsEnabled == true,
		"wrong order (Armory opens before the map lets go) shows the controls over the Armory"
	)
	armory.close()
	check(
		gui.TouchControlsEnabled == false,
		"wrong order then leaves them off after the Armory closes: why togglePanel closes the map first"
	)
end

L4H.group("count", L4H.countTests)
L4H.group("handOff", L4H.handOffTests)
L4H.group("wrongOrder", L4H.wrongOrderTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
