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
	-- A 20 x 20 rectangle at the origin: x and z -10..10.
	box = { x = 0, z = 0, hx = 10, hz = 10 },
	NAN = 0 / 0,
}

function L1C.reach(fromX: number, fromZ: number, dx: number, dz: number, rects: { any }, rootX: number, rootZ: number, pad: number): number
	return L1C.Clip.Reach(fromX, fromZ, dx, dz, rects, rootX, rootZ, pad)
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
	local far = { x = 0, z = 40, hx = 10, hz = 10 }
	check(near(reach(0, -30, 0, 80, { far, box }, 0, -30, 0), 20 / 80) and near(reach(0, -30, 0, 80, { box, far }, 0, -30, 0), 20 / 80), "two boxes ahead: the nearer cuts, in either order")
	check(near(reach(0, 5, 0, 40, { box, far }, 0, 5, 0), 25 / 40), "the root in one box: only the other cuts")
	check(reach(0, -30, 0, 30, {}, 0, -30, pad) == 1, "no boxes: whole")
	-- Not a number.
	local nan = L1C.NAN
	check(reach(nan, -30, 0, 30, { box }, 0, -30, pad) == 1 and reach(0, nan, 0, 30, { box }, 0, -30, pad) == 1 and reach(0, -30, nan, 30, { box }, 0, -30, pad) == 1 and reach(0, -30, 0, nan, { box }, 0, -30, pad) == 1 and reach(0, -30, 0, math.huge, { box }, 0, -30, pad) == 1, "a boom that is not a number (or is infinite) cannot be measured: whole, the camera left as it was")
	check(near(reach(0, -30, 0, 30, { box }, nan, nan, pad), (20 - pad) / 30), "a root that is not a number is in no box: every box cuts")
	local broken = { { x = nan, z = 0, hx = 10, hz = 10 }, { x = 0, z = 0, hx = -1, hz = 10 }, { x = 0, z = 0, hx = 10, hz = math.huge } }
	check(reach(0, -30, 0, 30, broken, 0, -30, pad) == 1, "a box that is not a number, has a negative half or an infinite one is skipped")
	check(reach(-30, 0, 60, 0, { broken[2] }, -30, 0, 0) == 1 and reach(0, -30, 0, 60, { { x = 0, z = 0, hx = 10, hz = -1 } }, 0, -30, 0) == 1, "even a boom straight across where a negative half would put it")
	check(near(reach(0, -30, 0, 30, { broken[1], box }, 0, -30, pad), (20 - pad) / 30), "and the boxes beside it still cut")
end
L1.group("l1c reachTests", L1C.reachTests)

function L1C.riseTests(): ()
	print(" WallClip.TooHigh and Rise: the ground point's height rule (L1c §8)")
	local Clip = L1C.Clip
	local movement = FIXTURES.proving.movement
	local rise = Clip.Rise(movement)
	check(rise == movement.jumpHeight + movement.doubleJumpHeight and rise > 0, `the limit is ProvingGrounds.json movement.jumpHeight + doubleJumpHeight ({movement.jumpHeight} + {movement.doubleJumpHeight} = {rise})`)
	check(Clip.Rise({ jumpHeight = 7, doubleJumpHeight = 5 }) == 12, "read from whatever movement it is given, never a typed number")
	check(not Clip.TooHigh(12, 12 + rise, rise) and Clip.TooHigh(12, 12 + rise + 0.001, rise), "exactly a jump and a double jump above the caster's floor is allowed; a thousandth more is refused")
	check(not Clip.TooHigh(12, 12, rise) and not Clip.TooHigh(38, 12, rise) and not Clip.TooHigh(12, -200, rise), "level, and any depth below, is allowed")
	check(not Clip.TooHigh(-5, 20, 30) and Clip.TooHigh(-5, 25.5, 30), "measured from the caster's floor, wherever it is")
end
L1.group("l1c riseTests", L1C.riseTests)

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
	local rise = L1C.Clip.Rise(FIXTURES.proving.movement)
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

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
