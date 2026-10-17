-- Cases for L1c, the Chief's Clearing redone (docs/prompts/l1c-contract.md): the pure WallClip
-- (the camera boom kept out of a locking camp, L1c-5a; the ground point's height rule, §8), then
-- the shipped Forest Road's walled clearing as LevelGeometry builds it and StageFlow plans it
-- (L1c-2, L1c-4, L1c-6). Appended last by run_harness.py, so every local of the earlier files is
-- in scope (vec, check, near, load, L1). Everything hangs off the L1C table (the 200-local
-- limit), and every group runs behind L1.group, so one that throws fails a check and the bundle
-- goes on to its verdict. WeaponService.GroundPoint and WaveService cannot be loaded here: the
-- first asks WallClip.TooHigh and WallClip.Rise (tested below), the second copies `zone.locks`.

print("L1c: the Chief's Clearing (WallClip, the walled camp)")

local L1C: any = {
	Clip = load("WallClip"),
	-- Theme.COMBAT_CAMERA_COLLISION_PAD as it stands; Reach takes any pad.
	PAD = 0.2,
	-- A 20 x 20 rectangle at the origin: x and z -10..10, its floor at y 0.
	box = { x = 0, y = 0, z = 0, hx = 10, hz = 10 },
	NAN = 0 / 0,
}

-- Reach with nothing grown and a root inside at any height (the first L1c clip): the cases of the
-- cut itself. The fix round's margin and height have their own group below.
function L1C.reach(fromX: number, fromZ: number, dx: number, dz: number, rects: { any }, rootX: number, rootZ: number, pad: number): number
	return L1C.Clip.Reach(fromX, fromZ, dx, dz, rects, rootX, 0, rootZ, { pad = pad, margin = 0, height = math.huge })
end

function L1C.reachTests(): ()
	print(" WallClip.Reach: the boom stops short of a camp the root is not in (L1c-5a)")
	local reach = L1C.reach
	local box = L1C.box
	local pad = L1C.PAD
	-- From 20 south of the box's middle, a 30-stud boom north: it meets the edge at z -10, a third
	-- of the way, and is pulled back the pad along itself.
	check(near(reach(0, -30, 0, 30, { box }, 0, -30, pad), (20 - pad) / 30), `a boom into the box from outside stops the pad short of the edge it would cross ((20 - {pad}) / 30, {reach(0, -30, 0, 30, { box }, 0, -30, pad)})`)
	check(near(reach(0, -30, 0, 30, { box }, 0, -30, 0), 20 / 30), "with no pad, exactly at the edge")
	check(reach(0, -30, 0, 30, { box }, 0, 0, pad) == 1 and reach(0, 5, 0, 30, { box }, 0, 5, pad) == 1, "a root inside the box: it never cuts, wherever the boom starts or goes")
	check(reach(0, -12, 0, 30, { box }, 0, -10, pad) == 1 and reach(0, -12, 0, 30, { box }, 10, 3, pad) == 1, "a root on its edge (or its corner's side) is inside: closed, as the trigger counts one on the fence")
	check(near(reach(0, -12, 0, 30, { box }, 0, -10.01, pad), (2 - pad) / 30), "a hundredth of a stud outside, it cuts")
	check(reach(0, -30, 0, -16, { box }, 0, -30, pad) == 1 and reach(-30, 0, -16, 0, { box }, -30, 0, pad) == 1, "a boom pointing away from the box is whole")
	check(reach(0, -30, 0, 16, { box }, 0, -30, pad) == 1, "one that ends 4 short of the edge is whole")
	check(near(reach(0, -26, 0, 16, { box }, 0, -26, pad), 1 - pad / 16), "one that ends exactly on the edge touches it (closed): pulled back the pad")
	check(reach(0, -5, 0, 16, { box }, 0, -15, pad) == 0 and reach(0, 5, 0, -30, { box }, 0, -15, pad) == 0, "a boom that starts inside a box the root is not in has nothing outside: 0, whichever way it points")
	check(reach(0, -5, 0, 0, { box }, 0, -15, pad) == 0 and reach(0, -15, 0, 0, { box }, 0, -15, pad) == 1, "a boom of no length: 0 inside the box, whole outside it")
	-- The gate's gap: the box is the fenced rectangle; a root just outside a gate with the camera
	-- swung behind it (into the camp) is cut at the fence line whatever the opening.
	check(near(reach(0, -11, 0, 16, { box }, 0, -11, pad), (1 - pad) / 16), "through a gate's gap (the box is the fenced rectangle: openings do not count): cut at the fence line")
	check(reach(0, -10.1, 0, 16, { box }, 0, -10.1, pad) == 0, "a root a tenth of a stud from it: less than the pad, so the camera comes to the pivot, never inside")
	-- The corner: a diagonal boom meets both slabs at once.
	local diagonal = 10 * math.sqrt(2)
	check(near(reach(-15, -15, 10, 10, { box }, -15, -15, pad), 0.5 - pad / diagonal), `a diagonal into the corner stops the pad short of it (0.5 - {pad} / {diagonal})`)
	check(reach(-20, -5, 10, -10, { box }, -20, -5, pad) == 1, "a diagonal that passes the corner outside is whole")
	check(reach(-15, -15, 30, 0, { box }, -15, -15, pad) == 1 and reach(15, -30, 0, 60, { box }, 15, -30, pad) == 1, "a boom parallel to an edge and beside the box is whole, however far it runs past it")
	check(near(reach(-15, -9, 10, 0, { box }, -15, -9, 0), 0.5) and near(reach(-15, 9, 10, 0, { box }, -15, 9, 0), 0.5), "a boom along the box a stud inside either long edge enters at its short edge")
	check(near(reach(-15, -10, 10, 0, { box }, -15, -10, 0), 0.5), "and one along the edge itself counts as entering (closed)")
	check(near(reach(-15, -14, 20, 8, { box }, -15, -14, 0), 0.5), "a slant whose x enters first is cut where z enters (the later slab)")
	-- The pad.
	check(reach(0, -11, 0, 16, { box }, 0, -11, 5) == 0, "a pad longer than the way to the edge: 0, never negative")
	check(reach(0, -11, 0, 16, { box }, 0, -11, -5) == reach(0, -11, 0, 16, { box }, 0, -11, 0) and reach(0, -11, 0, 16, { box }, 0, -11, L1C.NAN) == reach(0, -11, 0, 16, { box }, 0, -11, 0) and reach(0, -11, 0, 16, { box }, 0, -11, math.huge) == reach(0, -11, 0, 16, { box }, 0, -11, 0), "a negative, NaN or infinite pad is no pad")
	-- Several rectangles: the nearest cut wins, and the one that holds the root is skipped.
	local far = { x = 0, y = 0, z = 40, hx = 10, hz = 10 }
	check(near(reach(0, -30, 0, 80, { far, box }, 0, -30, 0), 20 / 80) and near(reach(0, -30, 0, 80, { box, far }, 0, -30, 0), 20 / 80), "two boxes ahead: the nearer cuts, in either order")
	check(near(reach(0, 5, 0, 40, { box, far }, 0, 5, 0), 25 / 40), "the root in one box: only the other cuts")
	check(reach(0, -30, 0, 30, {}, 0, -30, pad) == 1, "no boxes: whole")
	-- Not a number.
	local nan = L1C.NAN
	check(reach(nan, -30, 0, 30, { box }, 0, -30, pad) == 1 and reach(0, nan, 0, 30, { box }, 0, -30, pad) == 1 and reach(0, -30, nan, 30, { box }, 0, -30, pad) == 1 and reach(0, -30, 0, nan, { box }, 0, -30, pad) == 1 and reach(0, -30, 0, math.huge, { box }, 0, -30, pad) == 1, "a boom that is not a number (or is infinite) cannot be measured: whole, the camera left as it was")
	check(near(reach(0, -30, 0, 30, { box }, nan, nan, pad), (20 - pad) / 30), "a root that is not a number is in no box: every box cuts")
	local broken = { { x = nan, y = 0, z = 0, hx = 10, hz = 10 }, { x = 0, y = 0, z = 0, hx = -1, hz = 10 }, { x = 0, y = 0, z = 0, hx = 10, hz = math.huge } }
	check(reach(0, -30, 0, 30, broken, 0, -30, pad) == 1, "a box that is not a number, has a negative half or an infinite one is skipped")
	check(reach(-30, 0, 60, 0, { broken[2] }, -30, 0, 0) == 1 and reach(0, -30, 0, 60, { { x = 0, y = 0, z = 0, hx = 10, hz = -1 } }, 0, -30, 0) == 1, "even a boom straight across where a negative half would put it")
	check(near(reach(0, -30, 0, 30, { broken[1], box }, 0, -30, pad), (20 - pad) / 30), "and the boxes beside it still cut")
end
L1.group("l1c reachTests", L1C.reachTests)

-- The L1c fix round's C1 and m1: the cut uses each rectangle grown by the margin; the root is
-- inside only on the TRUE rectangle and no higher than `height` over its floor.
function L1C.marginTests(): ()
	print(" WallClip.Reach: the margin and the height (the L1c fix round's C1 and m1)")
	local Clip = L1C.Clip
	local nan = L1C.NAN
	local box = L1C.box
	local raised = { x = 0, y = 12, z = 0, hx = 10, hz = 10 }
	local clip = { pad = 0.2, margin = 3.5, height = 30 }
	local function reach(fromX: number, fromZ: number, dx: number, dz: number, rects: { any }, rootX: number, rootY: number, rootZ: number, how: any?): number
		return Clip.Reach(fromX, fromZ, dx, dz, rects, rootX, rootY, rootZ, how or clip)
	end
	check(near(reach(0, -30, 0, 30, { box }, 0, 0, -30), (16.5 - 0.2) / 30), `a boom toward the box stops the pad short of the GROWN edge, 3.5 out from the fence ((16.5 - 0.2) / 30, {reach(0, -30, 0, 30, { box }, 0, 0, -30)})`)
	check(near(reach(-20, -20, 20, 20, { box }, -20, 0, -20, { pad = 0, margin = 3.5, height = 30 }), 6.5 / 20), "a diagonal meets the grown corner")
	check(reach(0, -30, 0, 16, { box }, 0, 0, -30) == 1 and reach(0, -30, 0, 16.6, { box }, 0, 0, -30) < 1, "one that ends short of the grown edge is whole; one that reaches into the margin is cut")
	check(reach(0, -12, 0, -16, { box }, 0, 0, -12) == 0 and reach(0, -13.4, 0, -16, { box }, 0, 0, -13.4) == 0, "a root in the margin, outside the fence: the boom starts in the grown rectangle, so the camera comes to the pivot, whichever way it points")
	check(reach(0, -10.5, 0, 16, { box }, 0, 0, -10.5) == 0, "and the margin never frees it: a root half a stud outside the fence is not inside (the release is the true rectangle)")
	check(reach(0, -10, 0, 16, { box }, 0, 0, -10) == 1 and reach(0, -9, 0, -16, { box }, 0, 0, -9) == 1, "a root on the true fence line or inside is inside: nothing cuts")
	-- The L1c second fix round's F1: a rectangle's own ceiling (RunFloor.ceiling, a walled camp's
	-- fence top) is the band; `height` only stands in for a rectangle that names none.
	local walled = { x = 0, y = 0, z = 0, hx = 10, hz = 10, ceiling = 64 }
	check(reach(0, -9, 0, -16, { walled }, 0, 33, -9) == 1 and reach(0, -9, 0, -16, { walled }, 0, 43, -9) == 1, "inside a walled rectangle (ceiling 64) at 33 and 43 over its floor, a double jump from cover and a leap off it: held, nothing cut (F1: it was cut above `height`, the camera snapped to the head)")
	check(reach(0, -9, 0, -16, { walled }, 0, 64, -9) == 1 and reach(0, -9, 0, -16, { walled }, 0, 64.01, -9) == 0, "exactly its ceiling is inside; a hundredth over it is not, and cuts")
	check(reach(0, -9, 0, -16, { box }, 0, 30, -9) == 1 and reach(0, -9, 0, -16, { box }, 0, 30.01, -9) == 0, "a rectangle that names no ceiling: `height` (exactly is inside, over it cuts)")
	local odd = { { x = 0, y = 0, z = 0, hx = 10, hz = 10, ceiling = nan }, { x = 0, y = 0, z = 0, hx = 10, hz = 10, ceiling = math.huge } }
	check(reach(0, -9, 0, -16, { odd[1] }, 0, 30, -9) == 1 and reach(0, -9, 0, -16, { odd[1] }, 0, 30.01, -9) == 0 and reach(0, -9, 0, -16, { odd[2] }, 0, 30.01, -9) == 0, "a ceiling that is NaN or infinite is none: `height`")
	check(reach(0, -9, 0, -16, { { x = 0, y = 12, z = 0, hx = 10, hz = 10, ceiling = 64 } }, 0, 76, -9) == 1 and reach(0, -9, 0, -16, { { x = 0, y = 12, z = 0, hx = 10, hz = 10, ceiling = 64 } }, 0, 76.1, -9) == 0, "the ceiling is measured from the rectangle's own floor (y 12: 76)")
	check(reach(0, -9, 0, -16, { raised }, 0, 41.9, -9) == 1 and reach(0, -9, 0, -16, { raised }, 0, 42.1, -9) == 0, "the height is measured from the rectangle's own floor (y 12), not the world's zero")
	check(reach(0, -9, 0, -16, { raised }, 0, 2, -9) == 1, "a root under the floor (sunk for a frame) is still inside: only a ceiling")
	check(reach(0, -9, 0, -16, { box }, 0, nan, -9) == 0, "a root height that is not a number is inside nothing")
	local plain = reach(0, -30, 0, 30, { box }, 0, 0, -30, { pad = 0.2, margin = 0, height = 30 })
	check(near(plain, (20 - 0.2) / 30), "with no margin the cut is at the fence line")
	check(reach(0, -30, 0, 30, { box }, 0, 0, -30, { pad = 0.2, margin = -3, height = 30 }) == plain and reach(0, -30, 0, 30, { box }, 0, 0, -30, { pad = 0.2, margin = nan, height = 30 }) == plain and reach(0, -30, 0, 30, { box }, 0, 0, -30, { pad = 0.2, margin = math.huge, height = 30 }) == plain, "a negative, NaN or infinite margin is no margin")
	check(reach(0, -30, 0, 30, { { x = 0, y = nan, z = 0, hx = 10, hz = 10 } }, 0, 0, -30) == 1, "a box whose floor height is not a number is skipped")
	-- The shipped numbers: Combat.json levels.cameraClear, and the camera's own pad.
	local levels = FIXTURES.combat.levels
	local clear = levels.cameraClear
	check(type(clear) == "number" and clear >= 0 and clear < math.huge, `Combat.json levels.cameraClear is a distance ({tostring(clear)})`)
	if type(clear) ~= "number" then
		return
	end
	local shipped = { pad = 0.2, margin = clear, height = levels.triggerHeight }
	-- A fenced rectangle like camp C's, and every root of a 16-wide passage up to it from the
	-- north: no boom of up to camera.maxZoom, in any flat direction, ends nearer the fence than
	-- cameraClear, or than the root itself where the root stands in the margin (the camera then
	-- comes to the pivot).
	local fenced = { x = 0, y = 12, z = 0, hx = 58.5, hz = 58.5 }
	local boom = FIXTURES.combat.camera.maxZoom
	local worst = math.huge
	for x = -8, 8, 2 do
		for back = 0.05, 14, 0.5 do
			local rootZ = -fenced.hz - back
			for heading = 0, 355, 5 do
				local a = math.rad(heading)
				local dx, dz = boom * math.sin(a), boom * math.cos(a)
				local share = Clip.Reach(x, rootZ, dx, dz, { fenced }, x, 15, rootZ, shipped)
				local endX, endZ = x + dx * share, rootZ + dz * share
				local gap = math.max(math.abs(endX - fenced.x) - fenced.hx, math.abs(endZ - fenced.z) - fenced.hz)
				worst = math.min(worst, gap - math.min(back, clear))
			end
		end
	end
	check(worst >= -1e-9, `with the shipped cameraClear ({clear}) no camera from a root outside the fence comes nearer it than that, or than the root (worst {worst})`)
end
L1.group("l1c marginTests", L1C.marginTests)

function L1C.riseTests(): ()
	print(" WallClip.TooHigh and Rise: the ground point's height rule (L1c §8; per player since L2-4)")
	local Clip = L1C.Clip
	local movement = FIXTURES.proving.movement
	-- The owner of the double jump: the worst case every L1c rule was built for.
	local rise = Clip.Rise(movement, true)
	check(rise == movement.jumpHeight + movement.doubleJumpHeight and rise > 0, `for an owner of the double jump the limit is ProvingGrounds.json movement.jumpHeight + doubleJumpHeight ({movement.jumpHeight} + {movement.doubleJumpHeight} = {rise})`)
	check(Clip.Rise({ jumpHeight = 7, doubleJumpHeight = 5 }, true) == 12 and Clip.Rise({ jumpHeight = 7, doubleJumpHeight = 5 }, false) == 7, "read from whatever movement it is given, never a typed number")
	check(not Clip.TooHigh(12, 12 + rise, rise) and Clip.TooHigh(12, 12 + rise + 0.001, rise), "exactly a jump and a double jump above the caster's floor is allowed; a thousandth more is refused")
	check(not Clip.TooHigh(12, 12, rise) and not Clip.TooHigh(38, 12, rise) and not Clip.TooHigh(12, -200, rise), "level, and any depth below, is allowed")
	check(not Clip.TooHigh(-5, 20, 30) and Clip.TooHigh(-5, 25.5, 30), "measured from the caster's floor, wherever it is")
end
L1.group("l1c riseTests", L1C.riseTests)

-- The L1c fix round's m2 and M1, read from source text by run_harness.py (FIXTURES.source).
function L1C.sourceTests(): ()
	print(" The client's ground-aimed list and the place's zoom cap (the L1c fix round's m2 and M1)")
	local source = FIXTURES.source or {}
	local client, server = source.groundClient or {}, source.groundServer or {}
	check(#client > 0 and #server > 0 and table.concat(client, " ") == table.concat(server, " "), `InputController's GROUND_AIMED lists exactly AbilityService's target = "ground" mechanics (client {table.concat(client, ", ")}; server {table.concat(server, ", ")})`)
	local cap = source.zoomCap
	check(cap ~= nil and cap == FIXTURES.combat.camera.maxZoom, `combat.project.json StarterPlayer.CameraMaxZoomDistance is Combat.json camera.maxZoom ({tostring(cap)}, {tostring(FIXTURES.combat.camera.maxZoom)}): the default camera a dead rig hands over to zooms no further than the shoulder camera`)
end
L1.group("l1c sourceTests", L1C.sourceTests)

-- The L1c fix round's M3: a stage's own gateSeconds; 0 shuts the gates in the tick it triggers.
function L1C.gateTests(): ()
	print(" StageFlow: a camp's own countdown, and one of 0 (the L1c fix round's M3)")
	local Flow = L1.Flow
	local function levelWith(seconds: { [number]: any }): any
		local level = L1.level()
		for index, value in seconds do
			level.stages[index].gateSeconds = value
		end
		return level
	end
	-- Pickets (stage 2) at 0, Main Camp (4) at 1.5, the Clearing (6) as the rules say.
	local level = levelWith({ [2] = 0, [4] = 1.5 })
	check(#L1.problems(level) == 0, `a stage's gateSeconds of 0 or 1.5 is accepted ({table.concat(L1.problems(level), "; ")})`)
	for _, bad in { -1, "3", L1C.NAN, math.huge } do
		check(L1.has(L1.problems(levelWith({ [2] = bad })), "gateSeconds"), `a gateSeconds of {type(bad)} {tostring(bad)} is refused`)
	end
	local plan = L1.plan(level)
	check(plan.stages[2].gateSeconds == 0 and plan.stages[4].gateSeconds == 1.5 and plan.stages[6].gateSeconds == nil, "Plan carries each camp's own countdown, nil where the stage names none")
	-- Stepping into the Pickets: gate, close and its first wave in one tick.
	local state = Flow.Begin(plan)
	local actions = L1.advance(plan, state, { now = 5, roots = { L1.inCamp(plan, 2) } })
	check(L1.names(actions) == "gate close wave" and state.step == "fight" and state.wave == 1 and state.closedAt == 5 and L1.get(actions, "gate").at == 5, `a countdown of 0 closes in the tick the camp triggers ({L1.names(actions)}, step {state.step})`)
	-- Nobody standing when it would close: armed again in the same tick.
	local down = Flow.Begin(plan)
	local again = L1.advance(plan, down, { now = 5, roots = { L1.inCamp(plan, 2) }, fallen = "down", fieldClear = true })
	check(L1.names(again) == "gate rearm" and down.step == "armed", `with the fallen on a clear field it is armed again at once ({L1.names(again)})`)
	-- The Main Camp counts its own 1.5, a stage that names none the rules' 3.
	local main = Flow.Begin(plan)
	main.step = "travel"
	main.stage = 3
	local mainGate = L1.advance(plan, main, { now = 20, roots = { L1.inCamp(plan, 4) } })
	check(L1.names(mainGate) == "gate" and near(main.gateAt, 21.5), `a stage's own countdown (1.5): the gate at 21.5 ({main.gateAt})`)
	local plain = L1.plan(levelWith({}))
	local ruled = Flow.Begin(plain)
	L1.advance(plain, ruled, { now = 5, roots = { L1.inCamp(plain, 2) } })
	check(ruled.step == "gate" and near(ruled.gateAt, 5 + L1.rules.gateSeconds), "a stage that names none counts levels.gateSeconds")
	-- The Studio skips into a camp of 0 close in the same batch (no RunState in a countdown of 0).
	local skipped = Flow.Begin(plan)
	local skip = Flow.Skip(plan, skipped, "stage", 7, L1.rules)
	check(L1.names(skip) == "move gate close wave" and skipped.step == "fight", `N into a camp of 0: moved, shut and fighting at once ({L1.names(skip)})`)
	local bossPlan = L1.plan(levelWith({ [6] = 0 }))
	local bossed = Flow.Begin(bossPlan)
	local boss = Flow.Skip(bossPlan, bossed, "boss", 7, L1.rules)
	local last = L1.at(boss, #boss)
	check(bossed.step == "fight" and bossed.stage == 6 and bossed.wave == 2 and last.kind == "wave" and last.wave == 2 and L1.find(boss, "close") ~= nil, `B into a boss camp of 0: shut and on its boss wave at once ({L1.names(boss)})`)
	local armed = Flow.Begin(bossPlan)
	armed.step = "armed"
	armed.stage = 6
	local armedBoss = Flow.Skip(bossPlan, armed, "boss", 9, L1.rules)
	check(L1.names(armedBoss) == "move gate close wave" and armed.wave == 2, `B in a camp of 0 that is armed: the same ({L1.names(armedBoss)})`)
end
L1.group("l1c gateTests", L1C.gateTests)

-- The shipped Forest Road ---------------------------------------------------------------------------

function L1C.shipped(): (any, any, any)
	local resolved = L1.real.resolve("forestRoad")
	local layout = L1.real.layouts.ForestRoad
	local camp = nil
	for _, candidate in (if layout ~= nil then layout.camps else {}) do
		if candidate.id == "C" then
			camp = candidate
		end
	end
	return resolved, layout, camp
end

function L1C.wallTests(): ()
	print(" The walled clearing as it is built (L1c-1, L1c-2)")
	local _resolved, layout, camp = L1C.shipped()
	if layout == nil or camp == nil then
		check(false, "the shipped Forest Road layout and its camp C are there")
		return
	end
	local pieces, why = L1.real.pieces(layout)
	if pieces == nil then
		check(false, `Pieces builds Forest Road ({tostring(why)})`)
		return
	end
	-- The worst case is the owner of the double jump (L2-5: camp barriers unchanged).
	local rise = L1C.Clip.Rise(FIXTURES.proving.movement, true)
	local top = camp.y + camp.fence.height
	check(camp.locks == true and camp.tent == nil, "camp C locks and has no tent")
	local gates, fences, tents, lows = 0, 0, 0, {}
	for _, piece in pieces do
		if piece.camp == "C" then
			local pieceTop = piece.box.y + piece.box.sy / 2
			if piece.role == "gate" then
				gates += 1
				if not piece.collide or not near(pieceTop, top) then
					table.insert(lows, piece.name)
				end
			elseif piece.role == "fence" then
				fences += 1
				if not piece.collide or not near(pieceTop, top) then
					table.insert(lows, piece.name)
				end
			elseif piece.role == "tent" then
				tents += 1
			end
		end
	end
	check(gates == #camp.gates and gates == 2 and fences > 0 and #lows == 0, `its {gates} gates and {fences} fence pieces are solid and stand to the wall's top, y {top} (a closed gate is as tall as the wall){L1.real.list(lows)}`)
	check(tents == 0, "no Camp_C_Tent")
	check(L1C.Clip.TooHigh(camp.y, top, rise), `the wall's top is refused as a ground point from the clearing's own floor height (y {camp.y}, top {top}, limit {rise})`)
	local built: { [string]: any } = {}
	for _, piece in pieces do
		built[piece.name] = piece
	end
	local missing, soft, short = {}, {}, {}
	for _, name in { "GatehouseWalk", "GatehouseTurn", "GatehouseWallN", "GatehouseWallS", "GatehouseWallE", "GatehouseWallW" } do
		local piece = built[name]
		if piece == nil then
			table.insert(missing, name)
			continue
		end
		if not piece.collide or piece.role ~= "block" then
			table.insert(soft, name)
		end
		local pieceTop = piece.box.y + piece.box.sy / 2
		if string.find(name, "Wall", 1, true) ~= nil and (piece.look ~= "wall" or pieceTop < top or not L1C.Clip.TooHigh(camp.y, pieceTop, rise)) then
			table.insert(short, name)
		end
	end
	check(#missing == 0, `the gatehouse's six blocks are built{L1.real.list(missing)}`)
	check(#soft == 0, `each is a solid block (walked on, stopped at){L1.real.list(soft)}`)
	check(#short == 0, `its four walls look like walls and stand to the wall's top or above, out of a leap's reach{L1.real.list(short)}`)
end
L1.group("l1c wallTests", L1C.wallTests)

function L1C.planTests(): ()
	print(" The ambush as the run plans it (L1c-4, L1c-6)")
	local resolved, layout = L1C.shipped()
	local level = resolved.level
	if level == nil or layout == nil then
		check(false, `the shipped Forest Road resolves ({tostring(resolved.why)})`)
		return
	end
	local stageDef = nil
	for _, candidate in resolved.file.stages do
		if candidate.zone == "C" then
			stageDef = candidate
		end
	end
	local waves = if stageDef ~= nil then stageDef.waves else {}
	local first, second = waves[1] or {}, waves[2] or {}
	check(#waves == 2 and #(first.groups or { 0 }) == 0 and first.boss == nil, "the Chief's Clearing's waves: an empty first wave (the ambush the close releases)")
	check(#(second.groups or { 0 }) == 0 and second.boss ~= nil and second.boss.kind == "colossus", "then the Colossus alone")
	check(stageDef ~= nil and stageDef.gateSeconds == 0, `stepping in shuts the gate: the Chief's Clearing's gateSeconds is 0 (the L1c fix round's M3; {tostring(if stageDef ~= nil then stageDef.gateSeconds else nil)})`)
	local bounds = L1.real.bounds(layout)
	local expected = { normal = 10, hard = 12, brutal = 12 }
	local plated = { armoured = true, guard = true }
	for _, difficulty in { "normal", "hard", "brutal" } do
		local plan, why = L1.real.plan(level, layout, difficulty, bounds)
		if plan == nil then
			check(false, `{difficulty}: Forest Road plans ({tostring(why)})`)
			continue
		end
		local zone = nil
		for _, candidate in plan.zones do
			if candidate.id == "C" then
				zone = candidate
			end
		end
		local stage = nil
		for _, candidate in plan.stages do
			if candidate.zone == zone and zone ~= nil then
				stage = candidate
			end
		end
		if zone == nil or stage == nil then
			check(false, `{difficulty}: the plan has camp C and its stage`)
			continue
		end
		local bodies, loose, armour, sides = 0, {}, {}, {}
		for _, group in plan.groups do
			if group.camp == "C" then
				sides[group.id] = true
				if not group.held or group.posture ~= "guard" then
					table.insert(loose, group.id)
				end
				for _, unit in group.units do
					bodies += unit.count
					if plated[unit.kind] then
						table.insert(armour, `{group.id} {unit.kind}`)
					end
				end
			end
		end
		check(zone.locks and zone.residents == expected[difficulty] and bodies == expected[difficulty], `{difficulty}: camp C locks and holds {expected[difficulty]} residents ({zone.residents}, its groups {bodies})`)
		check(sides["C.ambushW"] == true and sides["C.ambushE"] == true and #loose == 0, `{difficulty}: both flanks, every group a held guard (asleep until the close){L1.real.list(loose)}`)
		check(#armour == 0, `{difficulty}: no plated kind in a walled camp: its bar would show through the wall (L1c-6){L1.real.list(armour)}`)
		check(stage.waves == 2 and stage.boss[2] == true and stage.boss[1] ~= true and zone.tentStock == 0, `{difficulty}: two waves, the boss in the second, no tent stock`)
		-- The empty wave clears on the field alone: with a body of the ambush alive it holds, and
		-- the tick it is dead the breather starts, then the Colossus.
		local ok, state = pcall(L1.toFight, plan, table.find(plan.stages, stage) or 0)
		if not ok then
			check(false, `{difficulty}: the run reaches the clearing's fight ({tostring(state)})`)
			continue
		end
		local now = state.closedAt or 0
		local held = L1.advance(plan, state, { now = now + 1, alive = 1, awake = 1, aliveByFloor = { [zone.floor] = 1 } })
		check(L1.find(held, "clear") == nil and state.step == "fight" and state.wave == 1, `{difficulty}: wave 1 holds while an ambusher lives ({L1.names(held)})`)
		local cleared = L1.advance(plan, state, { now = now + 2 })
		check(L1.find(cleared, "clear") ~= nil and state.step == "breather", `{difficulty}: and clears the tick the last one is dead: the breather ({L1.names(cleared)})`)
		local boss = L1.advance(plan, state, { now = state.breatherUntil or now + 99 })
		local wave = L1.get(boss, "wave")
		check(wave.wave == 2 and state.wave == 2, `{difficulty}: then wave 2, the Colossus ({L1.names(boss)})`)
	end
end
L1.group("l1c planTests", L1C.planTests)

-- The L1c second fix round (docs/prompts/l1c-fix2.md) -------------------------------------------

-- The shipped Forest Road planned on Normal, its camp C's zone and the stage index that names it.
function L1C.clearing(): (any, any, number, any)
	local resolved, layout, camp = L1C.shipped()
	if resolved.level == nil or layout == nil or camp == nil then
		return nil, nil, 0, nil
	end
	local plan = L1.real.plan(resolved.level, layout, "normal", L1.real.bounds(layout))
	if plan == nil then
		return nil, nil, 0, camp
	end
	for index, stage in plan.stages do
		if stage.zone ~= nil and stage.zone.id == "C" then
			return plan, stage.zone, index, camp
		end
	end
	return plan, nil, 0, camp
end

-- F1 and F3: a walled camp triggers, and holds the camera's root, up to its fence's top.
function L1C.ceilingTests(): ()
	print(" StageFlow.Ceiling and the walled clearing's band (the L1c second fix round's F1, F3)")
	local Flow = L1.Flow
	local rules = L1.real.rules
	local height = rules.triggerHeight
	local nan = L1C.NAN
	local function camp(locks: boolean?, fence: any?): any
		return { id = "X", locks = locks, fence = fence }
	end
	check(Flow.Ceiling(camp(true, { height = 64 }), 30) == 64, "a locking camp fenced 64 high: its fence top, 64")
	check(Flow.Ceiling(camp(true, { height = 4 }), 30) == 30 and Flow.Ceiling(camp(true, { height = 30 }), 30) == 30, "a locking camp whose fence is no higher than triggerHeight: triggerHeight")
	check(Flow.Ceiling(camp(nil, { height = 64 }), 30) == 30 and Flow.Ceiling(camp(false, { height = 64 }), 30) == 30, "an open camp, however tall its fence: triggerHeight")
	check(Flow.Ceiling(camp(true, nil), 30) == 30, "a locking camp with no fence: triggerHeight")
	check(Flow.Ceiling(camp(true, { height = nan }), 30) == 30 and Flow.Ceiling(camp(true, { height = math.huge }), 30) == 30 and Flow.Ceiling(camp(true, { height = "64" }), 30) == 30, "a fence height that is NaN, infinite or not a number: triggerHeight")

	local plan, zone, index, shipped = L1C.clearing()
	if plan == nil or zone == nil or shipped == nil then
		check(false, "the shipped Forest Road plans on Normal with camp C's stage")
		return
	end
	local top = shipped.fence.height
	check(top > height and zone.ceiling == top, `camp C's zone carries its wall's top as its ceiling ({zone.ceiling}, fence {top}, triggerHeight {height})`)
	local others = {}
	for _, other in plan.zones do
		if other.id ~= "C" and other.ceiling ~= height then
			table.insert(others, `{other.id} {other.ceiling}`)
		end
	end
	check(#others == 0, `every other camp keeps triggerHeight{L1.real.list(others)}`)

	-- The north gate's opening, across the trigger rectangle's band: the way in.
	local gate = shipped.gates[1]
	local gateX = shipped.x + gate.at
	local edge = zone.trigger.z - zone.trigger.hz
	local floor = zone.floorY
	local function armed(): any
		local state = Flow.Begin(plan)
		state.step = "armed"
		state.stage = index
		return state
	end
	local missed = {}
	for _, rise in { height + 0.5, 33, 36.5, 43, top } do
		for _, z in { edge, edge + rules.fenceThickness / 2, zone.rect.z - zone.rect.hz } do
			local state = armed()
			local actions = L1.advance(plan, state, { now = 5, roots = { vec(gateX, floor + rise, z) } })
			if L1.find(actions, "gate") == nil then
				table.insert(missed, `{rise} at z {z}`)
			end
		end
	end
	check(#missed == 0, `a root in the north gate's opening at the top of a jump (30.5 up to the wall's top over the floor) triggers C (F3: over 30 it saw the flanks and triggered nothing){L1.real.list(missed)}`)
	local over = armed()
	check(#L1.advance(plan, over, { now = 5, roots = { vec(gateX, floor + top + 0.5, edge) } }) == 0 and over.step == "armed", "over the wall's top, nothing")

	-- The camera: inside C at 33 to 43 over the floor, the boom is held whole in every direction
	-- (the rectangle and the clip exactly as CameraController builds them from RunState.floors).
	local fence = rules.fenceThickness
	local rect = { x = zone.rect.x, y = floor, z = zone.rect.z, hx = zone.rect.hx + fence, hz = zone.rect.hz + fence, ceiling = zone.ceiling }
	local clip = { pad = 0.2, margin = FIXTURES.combat.levels.cameraClear, height = height }
	local boom = FIXTURES.combat.camera.maxZoom
	local cut = {}
	for _, rise in { 33, 36.5, 40, 43 } do
		for _, at in { { 0, 0 }, { -0.9, -0.9 }, { 0.9, 0.9 }, { -0.98, 0.5 }, { 0.5, -0.98 }, { 0, -1 } } do
			local rootX, rootZ = rect.x + at[1] * zone.rect.hx, rect.z + at[2] * zone.rect.hz
			for heading = 0, 350, 10 do
				local a = math.rad(heading)
				local share = L1C.Clip.Reach(rootX, rootZ, boom * math.sin(a), boom * math.cos(a), { rect }, rootX, floor + rise, rootZ, clip)
				if share ~= 1 then
					table.insert(cut, `{rise} at ({rootX}, {rootZ}) heading {heading}: {share}`)
					break
				end
			end
		end
	end
	check(#cut == 0, `a root 33 to 43 over C's floor inside the fence keeps the whole boom (F1: no snap into the head){L1.real.list(cut)}`)
end
L1.group("l1c fix2 ceilingTests", L1C.ceilingTests)

-- F2 and m3: with C's countdown of 0 the close comes in the trigger's own tick, with the root still
-- in the fenced rectangle. The lead's rulings (the second round's code option a, then the third
-- round's m3): a fighter anywhere in the fenced rectangle, in the trigger's band, is only nudged
-- onto the nearest point of `inner` (StageFlow.GateNudge); only one outside it goes to the entry,
-- which stands clear of every point a nudge lands on (m2, co-op: a road player is placed there).
function L1C.entryTests(): ()
	print(" The Chief's Clearing's close on the trigger's tick: the nudge onto inner (the L1c fix rounds' F2 and m3)")
	local Flow = L1.Flow
	local rules = L1.real.rules
	local plan, zone, index, shipped = L1C.clearing()
	if plan == nil or zone == nil or shipped == nil then
		check(false, "the shipped Forest Road plans on Normal with camp C's stage")
		return
	end
	local gate = shipped.gates[1]
	local gateX = shipped.x + gate.at
	local edge = zone.trigger.z - zone.trigger.hz
	local inner = zone.inner
	local depth = rules.fenceThickness + rules.closeInset
	local limit = depth + 0.05
	local quiet, wrong, worst = {}, {}, 0
	for _, rise in { 3, 33, 43 } do
		for step = 0, gate.width * 2 do
			local x = gateX - gate.width / 2 + step / 2
			local position = vec(x, zone.floorY + rise, edge)
			local state = Flow.Begin(plan)
			state.step = "armed"
			state.stage = index
			local actions = L1.advance(plan, state, { now = 5, roots = { position } })
			if L1.find(actions, "close") == nil then
				table.insert(quiet, `x {x} at {rise}`)
			end
			-- WaveService.moveFighters at the close: MustEnter, then the nudge, else the entry.
			local to = if Flow.MustEnter(zone, position) then Flow.GateNudge(zone, position, rules) else position
			if to == nil then
				table.insert(wrong, `x {x} at {rise}: sent to the entry`)
				continue
			end
			local moved = to.Z - position.Z
			worst = math.max(worst, moved)
			if to.X ~= position.X or to.Y ~= position.Y or moved < 0 or moved > limit or Flow.MustEnter(zone, to) then
				table.insert(wrong, `x {x} at {rise}: to ({to.X}, {to.Y}, {to.Z})`)
			end
		end
	end
	check(#quiet == 0, `a root anywhere on the north gate's trigger line (z {edge}), standing or at the top of a jump, shuts the gate in that tick{L1.real.list(quiet)}`)
	check(#wrong == 0, `and the close only nudges it inside along the gate's inward normal, X and height kept, at most fenceThickness + closeInset ({depth}) + 0.05 (worst {string.format("%.2f", worst)}){L1.real.list(wrong)}`)
	-- m3: every root in the fenced rectangle outside `inner` (the fence band and the inset strip
	-- on all four sides, the corners too), on a quarter-stud grid across the band and a half-stud
	-- one along it: onto the nearest point of inner, height kept, at most `depth` on an axis.
	local trigger = zone.trigger
	local bad, far, nearest, samples = {}, 0, math.huge, 0
	local function judge(x: number, z: number): ()
		for _, rise in { 3, 33, 43 } do
			local position = vec(x, zone.floorY + rise, z)
			if not Flow.MustEnter(zone, position) then
				continue
			end
			samples += 1
			local to = Flow.GateNudge(zone, position, rules)
			if to == nil then
				table.insert(bad, `({x}, {z}) at {rise}: sent to the entry`)
				continue
			end
			local wantX = math.min(math.max(x, inner.x - inner.hx), inner.x + inner.hx)
			local wantZ = math.min(math.max(z, inner.z - inner.hz), inner.z + inner.hz)
			local dx, dz = math.abs(to.X - x), math.abs(to.Z - z)
			far = math.max(far, math.sqrt(dx * dx + dz * dz))
			nearest = math.min(nearest, math.sqrt((to.X - zone.entry.X) ^ 2 + (to.Z - zone.entry.Z) ^ 2))
			if
				not near(to.X, wantX)
				or not near(to.Z, wantZ)
				or to.Y ~= position.Y
				or dx > limit
				or dz > limit
				or Flow.MustEnter(zone, to)
			then
				table.insert(bad, `({x}, {z}) at {rise}: to ({to.X}, {to.Y}, {to.Z})`)
			end
		end
	end
	local bands = math.floor(depth * 4 + 0.5)
	for step = 0, math.floor(trigger.hx * 4 + 0.5) do
		local x = trigger.x - trigger.hx + step / 2
		for k = 0, bands do
			judge(x, trigger.z - trigger.hz + k / 4)
			judge(x, trigger.z + trigger.hz - k / 4)
		end
	end
	for step = 0, math.floor(trigger.hz * 4 + 0.5) do
		local z = trigger.z - trigger.hz + step / 2
		for k = 0, bands do
			judge(trigger.x - trigger.hx + k / 4, z)
			judge(trigger.x + trigger.hx - k / 4, z)
		end
	end
	check(samples > 0 and #bad == 0, `every root in C's fenced rectangle outside inner ({samples} samples, all four sides and the corners) is nudged onto inner's nearest point, height kept, at most {depth} on an axis (furthest move {string.format("%.2f", far)}){L1.real.list(bad)}`)
	check(nearest >= 3, `m2: no nudge lands within 3 studs of the entry, where a road player is placed in the same close (nearest {string.format("%.2f", nearest)})`)
	-- The reviewer's m3: a 45-degree dash past the gate's east edge, first sampled in the inset
	-- strip beside the opening, goes on from inner's edge 0.4 studs in, not 10 sideways.
	local dash = vec(gateX + gate.width / 2 + 2.1, zone.floorY + 3, inner.z - inner.hz - 0.4)
	local fromDash = if Flow.MustEnter(zone, dash) then Flow.GateNudge(zone, dash, rules) else nil
	check(fromDash ~= nil and fromDash.X == dash.X and near(fromDash.Z, inner.z - inner.hz) and fromDash.Y == dash.Y, "m3: a diagonal dash seen in the strip beside the opening is nudged 0.4 onto inner's edge, X and height kept")
	local beside = vec(gateX + gate.width / 2 + 2, zone.floorY + 3, edge)
	local fromBeside = Flow.GateNudge(zone, beside, rules)
	check(fromBeside ~= nil and fromBeside.X == beside.X and near(fromBeside.Z, inner.z - inner.hz), "a root in the fence band beside the opening: onto inner's edge too")
	local corner = vec(trigger.x + trigger.hx, zone.floorY + 3, trigger.z - trigger.hz)
	local fromCorner = Flow.GateNudge(zone, corner, rules)
	check(fromCorner ~= nil and near(fromCorner.X, inner.x + inner.hx) and near(fromCorner.Z, inner.z - inner.hz), `the fenced rectangle's corner: onto inner's corner ({depth} on each axis)`)
	-- Outside the band or the rectangle: the entry, as before.
	local above = vec(gateX, zone.floorY + zone.ceiling + 0.5, edge)
	local below = vec(gateX, zone.floorY - rules.triggerBelow - 0.5, edge)
	check(Flow.GateNudge(zone, above, rules) == nil and Flow.GateNudge(zone, below, rules) == nil, "not one over the camp's ceiling or under triggerBelow")
	local road = vec(gateX, zone.floorY + 3, edge - 0.5)
	local side = vec(trigger.x + trigger.hx + 0.5, zone.floorY + 3, shipped.z)
	check(Flow.GateNudge(zone, road, rules) == nil and Flow.GateNudge(zone, side, rules) == nil, "nor one half a stud out on the road past the fence's outer face, on Z or on X")
	-- An east gate: the move is along -X, Z and height kept.
	local east = shipped.gates[2]
	if east ~= nil and east.side == "east" then
		local eastZ = shipped.z + east.at
		local outside = vec(trigger.x + trigger.hx, zone.floorY + 3, eastZ)
		local to = Flow.GateNudge(zone, outside, rules)
		check(to ~= nil and near(to.X, inner.x + inner.hx) and to.Z == eastZ and to.Y == outside.Y, "through the east gate: along -X onto inner's east edge, Z and height kept")
	end
end
L1.group("l1c fix2 entryTests", L1C.entryTests)

-- F4: a held resident is passed over by a strike's cap and seeds, and by a chain's jumps.
function L1C.pickTests(): ()
	print(" StrikePick: the cap, the seeds and the chain pass over a held body (the L1c second fix round's F4)")
	local Pick = load("StrikePick")
	-- A `land` that records what it struck, in order, and refuses the ids in `held`.
	local function striker(held: { [number]: boolean }): (any, { [number]: boolean }, { number })
		local struck: { [number]: boolean } = {}
		local order: { number } = {}
		local function land(candidate: any): boolean
			struck[candidate.id] = true
			table.insert(order, candidate.id)
			return not held[candidate.id]
		end
		return land, struck, order
	end
	local function ids(list: { any }): string
		local out = {}
		for _, candidate in list do
			table.insert(out, tostring(candidate.id))
		end
		return table.concat(out, " ")
	end
	local five = { { id = 1 }, { id = 2 }, { id = 3 }, { id = 4 }, { id = 5 } }
	local held = { [2] = true, [4] = true }
	local allHeld = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true }
	local land, struck = striker(held)
	local seeds, spent = Pick.Seeds(five, 2, land)
	check(ids(seeds) == "1 3" and spent == 3, `a cap of 2 over 1 to 5 with 2 and 4 held: seeds 1 3, the cap spent on the third ({ids(seeds)}, spent {tostring(spent)})`)
	check(struck[1] and struck[2] and struck[3] and not struck[4] and not struck[5], "the held one before the cap is struck (a no-op) and passed over; nothing past the cap is struck")
	local every, never = Pick.Seeds(five, math.huge, (striker(held)))
	check(ids(every) == "1 3 5" and never == nil, `no cap: every body that took the hit, the cap never spent ({ids(every)})`)
	local exact, last = Pick.Seeds(five, 3, (striker(held)))
	check(ids(exact) == "1 3 5" and last == 5, `a cap met on the last candidate: spent at 5, so a ray does not stop short ({tostring(last)})`)
	local landZero, struckZero = striker({})
	local zero = Pick.Seeds(five, 0, landZero)
	local nanSeeds = Pick.Seeds(five, L1C.NAN, (striker({})))
	check(#zero == 0 and next(struckZero) == nil and #nanSeeds == 0, "a cap of 0 (or NaN) strikes nobody")
	local hidden, hiddenSpent = Pick.Seeds(five, 2, (striker(allHeld)))
	check(#hidden == 0 and hiddenSpent == nil, "over held bodies only: no seed, the cap never spent")

	local function takenOf(set: { [number]: boolean }): (any) -> boolean
		return function(candidate: any): boolean
			return set[candidate.id] == true
		end
	end
	local landNext, _, order = striker(held)
	local target = Pick.Next(five, takenOf({ [1] = true }), landNext)
	check(target ~= nil and target.id == 3 and table.concat(order, " ") == "2 3", `a jump passes over a taken body without striking it, and over a held one: it lands on 3 ({tostring(target and target.id)}; struck {table.concat(order, " ")})`)
	check(Pick.Next(five, takenOf({ [1] = true }), (striker(allHeld))) == nil, "with every free body held: no jump")

	-- Storm Coil over the posts (targets 2, chain 3) with every body under it held, linked as
	-- WeaponService links them (each seed from the origin, each jump from the last): nothing.
	local links = {}
	for _, seed in (Pick.Seeds(five, 2, (striker(allHeld)))) do
		table.insert(links, 0)
		table.insert(links, seed.id)
		for _ = 1, 3 do
			local jump = Pick.Next(five, takenOf({ [seed.id] = true }), (striker(allHeld)))
			if jump == nil then
				break
			end
			table.insert(links, seed.id)
			table.insert(links, jump.id)
		end
	end
	check(#links == 0, `a coil cast over held bodies only makes no link ({#links // 2} links)`)
end
L1.group("l1c fix2 pickTests", L1C.pickTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
