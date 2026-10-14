-- Cases for L1b Wave 1, the crowd (docs/INTERFACES.md "L1b contracts — the living road" -> "A —
-- the crowd"): the pure CampBrain, CrowdService with a floor per camp, and CrowdService with
-- resident groups. Appended after tests_l1.luau by run_harness.py, so every local of the earlier
-- files is in scope (vec, check, near, load, config, Crowd, Vitals, player, root, step2, seen,
-- fresh, struck, join2, leave2...). Everything hangs off the L1BC table (the 200-local limit), and
-- every group runs behind L1BC.group, so one that throws fails a check and the bundle goes on.
-- The crowd cases swap in a crowd config of their own and put the old one back, so neither an
-- earlier file's tuning nor a later one's depends on them.

print("L1b: the crowd (CampBrain, floors, groups)")

local L1BC: any = {
	CB = load("CampBrain"),
	Codec = load("CrowdCodec"),
	kills = {},
}

Crowd.OnKilled(function(id: number, byUserId: number, info: any)
	table.insert(L1BC.kills, { id = id, by = byUserId, info = info })
end)

function L1BC.group(name: string, cases: () -> ()): ()
	local ok, problem = pcall(cases)
	if not ok then
		check(false, `L1b crowd group "{name}" threw: {problem}`)
	end
end

-- Combat.json `camps` as the contract starts it.
function L1BC.rules(): any
	return {
		guard = { sight = 30, cone = 140, rise = 0 },
		patrol = { sight = 24, cone = 360, rise = 0 },
		fire = { sight = 16, cone = 360, rise = 1.5 },
		sightBelow = 4,
		sightAbove = 30,
		chaseMargin = 3,
		leashSeconds = 3,
		homePace = 1,
		patrolPace = 0.5,
		homeTolerance = 1,
		engagedHoldSeconds = 1.5,
	}
end

-- A group def on floor `floor` (default 1) at floorY 8, its floor 60 x 60 round the origin.
function L1BC.def(posture: string, points: { any }, over: any?): any
	local def: any = {
		id = "A." .. posture,
		camp = "A",
		floor = 1,
		floorY = 8,
		rect = { x = 0, z = 0, hx = 30, hz = 30 },
		posture = posture,
		points = points,
		yaw = 0,
		radius = 0,
		held = false,
		units = {},
	}
	for key, value in over or {} do
		def[key] = value
	end
	return def
end

function L1BC.member(at: any, yaw: number?, leg: number?): any
	return { at = at, post = { at = at, yaw = yaw or 0, leg = leg or 0 } }
end

function L1BC.input(now: number, members: { any }, targets: { any }?, shooters: { any }?, striking: boolean?): any
	return { now = now, members = members, targets = targets or {}, shooters = shooters or {}, striking = striking == true }
end

function L1BC.seen(userId: number, x: number, y: number, z: number): any
	return { userId = userId, root = vec(x, y, z) }
end

-- The point `distance` from `from` on the flat at yaw `yaw` (0 faces -Z).
function L1BC.toward(from: any, yaw: number, distance: number, y: number): any
	return vec(from.X - math.sin(yaw) * distance, y, from.Z - math.cos(yaw) * distance)
end

-- Posts --------------------------------------------------------------------------------------------
function L1BC.postsTests(): ()
	local CB = L1BC.CB
	print(" CampBrain.Posts")
	local guard = L1BC.def("guard", { vec(-10, 0, -20), vec(10, 3, -20), vec(0, 8, 5) }, { yaw = 1.0 })
	local posts = CB.Posts(guard, 2)
	check(
		#posts == 2
			and near(posts[1].at.X, -10) and near(posts[1].at.Z, -20)
			and near(posts[2].at.X, 10) and near(posts[2].at.Z, -20),
		"guard: member k stands on points[k]"
	)
	check(posts[1].at.Y == 8 and posts[2].at.Y == 8, "guard: every post at floorY, whatever the point's own height")
	check(posts[1].yaw == 1.0 and posts[2].yaw == 1.0 and posts[1].leg == 0 and posts[2].leg == 0, "guard: every yaw is def.yaw, leg 0")

	local square = { vec(0, 8, 0), vec(12, 8, 0), vec(12, 8, 12), vec(0, 8, 12) }
	local patrol = L1BC.def("patrol", square)
	local three = CB.Posts(patrol, 3)
	local function facing(post: any, x: number, z: number): boolean
		local dx = x - post.at.X
		local dz = z - post.at.Z
		local length = math.sqrt(dx * dx + dz * dz)
		return near(-math.sin(post.yaw), dx / length, 1e-9) and near(-math.cos(post.yaw), dz / length, 1e-9)
	end
	check(near(three[1].at.X, 0) and near(three[1].at.Z, 0) and three[1].leg == 2, "patrol of 3 on a square of 48: the first at points[1], walking to points[2]")
	check(near(three[2].at.X, 12) and near(three[2].at.Z, 4) and three[2].leg == 3, `the second 16 along the loop, on the second leg (({three[2].at.X}, {three[2].at.Z}) leg {three[2].leg})`)
	check(near(three[3].at.X, 4) and near(three[3].at.Z, 12) and three[3].leg == 4, `the third 32 along, on the third leg (({three[3].at.X}, {three[3].at.Z}) leg {three[3].leg})`)
	check(facing(three[1], 12, 0) and facing(three[2], 12, 12) and facing(three[3], 0, 12), "each faces the point it walks to")
	check(three[1].at.Y == 8 and three[2].at.Y == 8 and three[3].at.Y == 8, "patrol: every post at floorY")
	local two = CB.Posts(patrol, 2)
	check(near(two[2].at.X, 12) and near(two[2].at.Z, 12) and two[2].leg == 4, "a member exactly on a vertex (24 of 48) takes the next point")
	local long = L1BC.def("patrol", { vec(0, 8, 0), vec(30, 8, 0), vec(30, 8, 6), vec(0, 8, 6) })
	local spaced = CB.Posts(long, 3)
	check(
		near(spaced[2].at.X, 24) and near(spaced[2].at.Z, 0) and spaced[2].leg == 2
			and near(spaced[3].at.X, 18) and near(spaced[3].at.Z, 6) and spaced[3].leg == 4,
		"on an uneven loop of 72 the members are 24 apart by arc length, not one per point"
	)

	local fire = L1BC.def("fire", { vec(5, 8, -3) }, { radius = 4 })
	local ring = CB.Posts(fire, 6)
	local ok = #ring == 6
	for k, post in ring do
		local theta = 2 * math.pi * (k - 1) / 6
		ok = ok
			and near(post.at.X, 5 - math.sin(theta) * 4, 1e-9)
			and near(post.at.Z, -3 - math.cos(theta) * 4, 1e-9)
			and post.at.Y == 8
			and post.leg == 0
			and post.yaw > -math.pi
			and post.yaw <= math.pi
			and facing(post, 5, -3)
	end
	check(ok, "fire of 6: on the circle of radius 4 at bearings 2pi(k-1)/6, each facing the centre, yaw in (-pi, pi]")
	check(near(ring[1].at.X, 5) and near(ring[1].at.Z, -7) and near(ring[1].yaw, math.pi), "the first sits north of the centre, facing south (yaw pi)")
end
L1BC.group("posts", L1BC.postsTests)

-- Sees and InPlay ------------------------------------------------------------------------------------
function L1BC.sightTests(): ()
	local CB = L1BC.CB
	local R = L1BC.rules()
	print(" CampBrain.Sees")
	local guard = L1BC.def("guard", { vec(0, 8, 0) })
	local member = L1BC.member(vec(0, 8, 0), 0)
	local function sees(x: number, y: number, z: number, def: any?, who: any?): boolean
		return CB.Sees(def or guard, who or member, L1BC.seen(7, x, y, z), R)
	end
	check(sees(0, 10, -30), "a root at exactly sight (30) is seen")
	check(not sees(0, 10, -30.01), "one just past it is not")
	check(sees(0, 4, -10) and not sees(0, 3.99, -10), "the band's lower edge: sightBelow (4) under the floor is seen, a hair lower not")
	check(sees(0, 38, -10) and not sees(0, 38.01, -10), "the band's upper edge: sightAbove (30) over the floor is seen, a hair higher not")
	local edge = L1BC.toward(vec(0, 8, 0), math.rad(70), 10, 10)
	local past = L1BC.toward(vec(0, 8, 0), math.rad(71), 10, 10)
	local other = L1BC.toward(vec(0, 8, 0), math.rad(-70), 10, 10)
	check(sees(edge.X, edge.Y, edge.Z) and sees(other.X, other.Y, other.Z), "a guard's cone of 140: a root at 70 degrees either side is seen")
	check(not sees(past.X, past.Y, past.Z), "and one at 71 degrees is not")
	check(not sees(0, 10, 10), "a guard does not see behind itself")
	local turned = L1BC.member(vec(0, 8, 0), math.pi / 2)
	check(sees(-10, 10, 0, nil, turned) and not sees(0, 10, -10, nil, turned), "the cone is about the member's post's yaw")
	local patrol = L1BC.def("patrol", { vec(0, 8, 0), vec(10, 8, 0) })
	check(sees(0, 10, 10, patrol), "a 360 cone sees behind the body")
	check(not sees(0, 10, 24.01, patrol), "within its own posture's sight only (patrol 24)")
	check(sees(0, 9, 0), "a target at distance 0 is seen whatever the cone")

	print(" CampBrain.InPlay")
	local rect = L1BC.def("guard", { vec(0, 8, 0) }, { rect = { x = 0, z = 0, hx = 30, hz = 20 } })
	local function inPlay(x: number, y: number, z: number, shooters: { any }?): boolean
		return CB.InPlay(rect, L1BC.seen(7, x, y, z), shooters or {}, R)
	end
	check(inPlay(33, 10, 0) and inPlay(-33, 10, 0), "the floor grown by chaseMargin (3) on X, edges included")
	check(not inPlay(33.01, 10, 0) and not inPlay(-33.01, 10, 0), "and not past it")
	check(inPlay(0, 10, 23) and inPlay(0, 10, -23), "on Z too")
	check(not inPlay(0, 10, 23.01) and not inPlay(0, 10, -23.01), "and not past it")
	check(not inPlay(0, 38.01, 0) and not inPlay(0, 3.99, 0), "a root over or under the band is not in play, on the floor or not")
	-- The margin is a distance to the rectangle (30 x 20 half), so its corners are round.
	check(inPlay(33, 10, 20) and inPlay(-33, 10, -20), "past a corner straight out along X: at the margin exactly, in play")
	check(not inPlay(33, 10, 20.01) and not inPlay(30.01, 10, 23), "a hair round the corner from either edge's end: not (a square corner says yes)")
	check(inPlay(32.12, 10, 22.12) and inPlay(-32.12, 10, 22.12), "off a corner on the diagonal 2.998 from it: in play")
	check(not inPlay(32.2, 10, 22.2) and not inPlay(32.2, 10, -22.2), "off a corner on the diagonal 3.11 from it: not, though inside the square grown by 3")
	local shooters = { { at = vec(50, 8, 0), reach = 12 } }
	check(inPlay(62, 10, 0, shooters), "within a shooter's reach exactly: in play")
	check(not inPlay(62.01, 10, 0, shooters), "just past it: not")

	print(" CampBrain.Engaged (the hold)")
	check(not CB.Engaged(nil, 10, R), "never in play: not engaged")
	check(CB.Engaged(10, 10, R), "in play at this step: engaged")
	check(CB.Engaged(10, 11, R) and CB.Engaged(10, 11.5, R), "for engagedHoldSeconds (1.5) after it, edge included")
	check(not CB.Engaged(10, 11.51, R), "and not past it")
	local none = L1BC.rules()
	none.engagedHoldSeconds = 0
	check(CB.Engaged(10, 10, none) and not CB.Engaged(10, 10 + 1 / 15, none), "a hold of 0: engaged at that step only")
end
L1BC.group("sight", L1BC.sightTests)

-- Step ---------------------------------------------------------------------------------------------------
function L1BC.stepTests(): ()
	local CB = L1BC.CB
	local R = L1BC.rules()
	print(" CampBrain.Step")
	local function guardGroup(held: boolean?): (any, { any })
		local def = L1BC.def("guard", { vec(0, 8, -10), vec(4, 8, -10) }, { held = held == true })
		local members = { L1BC.member(vec(0, 8, -10), 0), L1BC.member(vec(4, 8, -10), 0) }
		return CB.NewGroup(def, 0), members
	end
	local sighted = { L1BC.seen(7, 0, 10, -25) }
	local nobody: { any } = {}

	local g, members = guardGroup()
	check(g.state == "rest" and g.held == false and g.since == 0 and g.quietSince == 0 and g.hit == false, "NewGroup: at rest, not held, both clocks at now")
	check(CB.Step(g, L1BC.input(1, members, nobody), R) == nil and g.state == "rest", "nobody near: it rests")
	check(CB.Step(g, L1BC.input(2, members, sighted), R) == "rise" and g.state == "rise" and g.since == 2, "a target in sight wakes it: rise, since = now")
	check(CB.Step(g, L1BC.input(2.01, members, sighted), R) == "fight", "a rise of 0 lasts exactly one step")

	local once = guardGroup()
	local _, onceMembers = guardGroup()
	check(CB.Step(once, L1BC.input(5, onceMembers, sighted), R) == "rise" and once.state == "rise", "one transition per call: a rise of 0 is not skipped in the step that wakes")

	local struck = guardGroup()
	check(CB.Struck(struck, 9) == false and struck.hit == true, "a hit from a player not in play: no damage, but it is recorded")
	check(CB.Step(struck, L1BC.input(1, members, nobody), R) == "rise" and struck.hit == false, "a hit wakes it with nobody in sight, and the flag is cleared")

	local held = guardGroup(true)
	check(held.held == true, "a held def starts held")
	check(CB.Step(held, L1BC.input(1, members, sighted), R) == nil and held.state == "rest", "a held group ignores sight")
	check(held.inPlay[7] == true, "but its in-play set is rebuilt all the same")
	held.hit = true
	check(CB.Step(held, L1BC.input(2, members, nobody), R) == nil and held.state == "rest" and held.hit == false, "and ignores a hit (the flag is cleared)")
	check(CB.Struck(held, 7) == false and held.hit == false, "a held group evades: nothing is recorded")
	CB.Release(held, 3)
	check(held.held == false and held.state == "rise" and held.since == 3, "Release: a held group goes to rise at now")
	local loose = guardGroup()
	CB.Release(loose, 3)
	check(loose.state == "rest" and loose.since == 0, "Release does nothing to a group that was not held")

	local fireDef = L1BC.def("fire", { vec(0, 8, 0) }, { radius = 4 })
	local fire = CB.NewGroup(fireDef, 0)
	local sitters = { L1BC.member(vec(0, 8, -4)), L1BC.member(vec(0, 8, 4)) }
	local close = { L1BC.seen(7, 0, 10, 10) }
	check(CB.Step(fire, L1BC.input(10, sitters, close), R) == "rise", "a fire group wakes")
	check(CB.Step(fire, L1BC.input(11.4, sitters, close), R) == nil and fire.state == "rise", "a rise of 1.5: still rising after 1.4 s")
	check(CB.Step(fire, L1BC.input(11.5, sitters, close), R) == "fight" and fire.since == 11.5 and fire.quietSince == 11.5, "and fighting at 1.5 s; since = quietSince = now")

	print(" the leash")
	local function fighting(at: number): (any, { any })
		local group, list = guardGroup()
		CB.Step(group, L1BC.input(at - 0.2, list, sighted), R)
		CB.Step(group, L1BC.input(at - 0.1, list, sighted), R)
		CB.Step(group, L1BC.input(at, list, sighted), R)
		return group, list
	end
	local leash, list = fighting(20)
	check(leash.state == "fight" and leash.quietSince == 20, "(a group fighting with a target in play at 20)")
	check(CB.Step(leash, L1BC.input(22.9, list, nobody), R) == nil and leash.state == "fight", "nobody in play for 2.9 s: it keeps fighting")
	check(CB.Step(leash, L1BC.input(23, list, nobody), R) == "home" and leash.since == 23, "at leashSeconds exactly it goes home")
	local busy, busyList = fighting(20)
	check(CB.Step(busy, L1BC.input(23, busyList, nobody, nil, true), R) == nil and busy.state == "fight", "not while a member is striking")
	check(CB.Step(busy, L1BC.input(23.5, busyList, nobody), R) == "home", "and as soon as none is")
	local back, backList = fighting(20)
	CB.Step(back, L1BC.input(21, backList, nobody), R)
	CB.Step(back, L1BC.input(22, backList, sighted), R)
	check(back.quietSince == 22, "a target back in play resets the leash's clock")
	check(CB.Step(back, L1BC.input(24.9, backList, nobody), R) == nil, "so 4.9 s after it last fought nobody, it is still 2.9 s quiet")
	check(CB.Step(back, L1BC.input(25, backList, nobody), R) == "home", "and goes home 3 s after the target left")

	print(" home")
	local home, homeList = fighting(20)
	CB.Step(home, L1BC.input(23, homeList, nobody), R)
	local away = { L1BC.member(vec(0, 8, -10), 0), { at = vec(4, 8, -20), post = homeList[2].post } }
	check(CB.Struck(home, 7) == false and home.hit == false, "home evades every hit, a player's in play or not")
	check(CB.Struck(home, 0) == false, "and the levers' (byUserId 0)")
	home.hit = true
	check(CB.Step(home, L1BC.input(24, away, sighted), R) == nil and home.state == "home", "home ignores a hit and sight while a member is away from its post")
	local almost = { L1BC.member(vec(0, 8, -10), 0), { at = vec(4, 8, -11.01), post = homeList[2].post } }
	check(CB.Step(home, L1BC.input(25, almost, nobody), R) == nil, "one member 1.01 from its post: still home")
	local there = { L1BC.member(vec(0, 8, -10), 0), { at = vec(4, 8, -11), post = homeList[2].post } }
	check(CB.Step(home, L1BC.input(26, there, sighted), R) == "rest" and home.since == 26, "every member within homeTolerance: at rest again")
	check(CB.Step(home, L1BC.input(27, there, sighted), R) == "rise", "and it can wake again")

	local empty = guardGroup()
	empty.hit = true
	check(CB.Step(empty, L1BC.input(1, {}, sighted), R) == nil and empty.state == "rest", "an empty group never changes, hit and target or not")

	print(" CampBrain.Struck")
	local open, openList = fighting(30)
	check(open.inPlay[7] == true and open.inPlay[9] == nil, "(7 is in play at the last step, 9 is not)")
	open.hit = false
	check(CB.Struck(open, 7) == true and open.hit == true, "in play: the damage lands, and the hit is recorded")
	check(CB.Struck(open, 9) == false, "out of play: blocked")
	check(CB.Struck(open, 0) == true, "byUserId 0 (a Studio lever): lands")
	check(CB.Evades(open) == false and CB.Evades(home) == false and CB.Evades(held) == false, "(only held or home evades)")
	local holding = guardGroup(true)
	check(CB.Evades(holding) == true, "a held group evades")
	local _ = openList
end
L1BC.group("step", L1BC.stepTests)

-- Goal, AtPost, Shows, Problems --------------------------------------------------------------------
function L1BC.goalTests(): ()
	local CB = L1BC.CB
	local R = L1BC.rules()
	print(" CampBrain.Goal, AtPost, Shows")
	local guardDef = L1BC.def("guard", { vec(3, 8, -10) })
	local guard = CB.NewGroup(guardDef, 0)
	local guardPost = { at = vec(3, 8, -10), yaw = 0, leg = 0 }
	local guardResident = { group = 1, post = guardPost, leg = 0 }
	local goal, pace = CB.Goal(guard, guardResident, vec(5, 8, -14), R)
	check(goal == guardPost.at and pace == R.homePace, "rest, guard: a shoved body drifts back to its post at homePace")

	local square = { vec(0, 8, 0), vec(12, 8, 0), vec(12, 8, 12), vec(0, 8, 12) }
	local patrol = CB.NewGroup(L1BC.def("patrol", square), 0)
	local walker = { group = 1, post = { at = vec(0, 8, 0), yaw = 0, leg = 2 }, leg = 2 }
	local far, farPace = CB.Goal(patrol, walker, vec(3, 8, 0), R)
	check(far ~= nil and near(far.X, 12) and near(far.Z, 0) and farPace == R.patrolPace and walker.leg == 2, "rest, patrol: walks to the loop point resident.leg at patrolPace")
	local next = CB.Goal(patrol, walker, vec(11.5, 8, 0.5), R)
	check(walker.leg == 3 and next ~= nil and near(next.X, 12) and near(next.Z, 12), "within homeTolerance of it, the leg steps to the next point, which is the goal")
	walker.leg = 4
	local wrapped = CB.Goal(patrol, walker, vec(0.5, 8, 12), R)
	check(walker.leg == 1 and wrapped ~= nil and near(wrapped.X, 0) and near(wrapped.Z, 0), "the last point wraps to the first")
	check(next ~= nil and next.Y == 8, "a loop point is on the floor")

	local riser = CB.NewGroup(guardDef, 0)
	riser.state = "rise"
	local none, nonePace = CB.Goal(riser, guardResident, vec(5, 8, -14), R)
	check(none == nil and nonePace == 0, "rise: it stands")
	riser.state = "fight"
	check(CB.Goal(riser, guardResident, vec(5, 8, -14), R) == nil, "fight: the brain's")
	local heldGroup = CB.NewGroup(L1BC.def("patrol", square, { held = true }), 0)
	local heldWalker = { group = 1, post = { at = vec(0, 8, 0), yaw = 0, leg = 2 }, leg = 2 }
	check(CB.Goal(heldGroup, heldWalker, vec(3, 8, 0), R) ~= nil, "held: walks as at rest")

	local going = CB.NewGroup(L1BC.def("patrol", square), 0)
	going.state = "home"
	local returning = { group = 1, post = { at = vec(12, 8, 4), yaw = 0, leg = 3 }, leg = 1 }
	local homeGoal, homePace = CB.Goal(going, returning, vec(0, 8, 9), R)
	check(homeGoal == returning.post.at and homePace == R.homePace and returning.leg == 1, "home: to its post at homePace, the leg untouched on the way")
	CB.Goal(going, returning, vec(12.5, 8, 4.5), R)
	check(returning.leg == 3, "once at its post, its leg is the post's again")

	check(CB.AtPost(guardPost, vec(4, 8, -10), R) and not CB.AtPost(guardPost, vec(4.01, 8, -10), R), "AtPost: within homeTolerance (1) on the flat, edge included")
	check(CB.AtPost(guardPost, vec(3, 40, -10), R), "AtPost is flat")

	local fireRest = CB.NewGroup(L1BC.def("fire", { vec(0, 8, 0) }, { radius = 3 }), 0)
	check(CB.Shows(fireRest, false) == "rest" and CB.Shows(fireRest, true) == "move", "Shows: a fire group at rest sits, and moves when moving")
	check(CB.Shows(guard, false) == "idle" and CB.Shows(patrol, false) == "idle" and CB.Shows(patrol, true) == "move", "guard and patrol at rest: idle, or move")
	local fireHeld = CB.NewGroup(L1BC.def("fire", { vec(0, 8, 0) }, { radius = 3, held = true }), 0)
	check(CB.Shows(fireHeld, false) == "rest", "held: as at rest")
	fireRest.state = "home"
	check(CB.Shows(fireRest, false) == "idle" and CB.Shows(fireRest, true) == "move", "home: idle or move, a fire group's too")
	fireRest.state = "rise"
	check(CB.Shows(fireRest, false) == "rise" and CB.Shows(fireRest, true) == "rise", "rise: rise")
	fireRest.state = "fight"
	check(CB.Shows(fireRest, false) == nil, "fight: nil (the brain's state)")

	print(" CampBrain.Problems")
	check(#CB.Problems(R) == 0, "the contract's rules have no problem")
	check(#CB.Problems(nil) == 1, "nil: one line")
	local keys = { "sightBelow", "sightAbove", "chaseMargin", "leashSeconds", "homePace", "patrolPace", "homeTolerance", "engagedHoldSeconds" }
	local each = true
	for _, key in keys do
		local copy = L1BC.rules()
		copy[key] = nil
		each = each and #CB.Problems(copy) == 1
	end
	for _, posture in { "guard", "patrol", "fire" } do
		for _, key in { "sight", "cone", "rise" } do
			local copy = L1BC.rules()
			copy[posture][key] = nil
			each = each and #CB.Problems(copy) == 1
		end
		local copy = L1BC.rules()
		copy[posture] = nil
		each = each and #CB.Problems(copy) == 1
	end
	check(each, "each missing key, and each missing posture, is one line")
	local function with(posture: string?, key: string, value: any): number
		local copy = L1BC.rules()
		if posture ~= nil then
			copy[posture][key] = value
		else
			copy[key] = value
		end
		return #CB.Problems(copy)
	end
	check(with("guard", "cone", 0) == 1 and with("guard", "cone", 361) == 1 and with("guard", "cone", 360) == 0, "a cone of 0 and of 361 are problems; 360 is not")
	check(with("fire", "sight", 0) == 1 and with(nil, "homeTolerance", 0) == 1, "a sight or a homeTolerance of 0 is a problem")
	check(with(nil, "chaseMargin", -1) == 1 and with(nil, "leashSeconds", 0 / 0) == 1 and with(nil, "homePace", "1") == 1 and with(nil, "sightAbove", math.huge) == 1, "negative, NaN, a string, infinite: each a problem")
	check(with(nil, "chaseMargin", 0) == 0 and with("guard", "rise", 0) == 0 and with(nil, "engagedHoldSeconds", 0) == 0, "0 is fine where 0 means something")
	check(with(nil, "engagedHoldSeconds", -1) == 1, "a negative engagedHoldSeconds is a problem")
end
L1BC.group("goal", L1BC.goalTests)

-- The crowd, with a config of its own ---------------------------------------------------------------
function L1BC.enter(): ()
	L1BC.saved = { crowd = config.crowd, player = config.player, shooting = config.shooting, movement = config.movement }
	local lunge = { shape = "lunge", reach = 4.5, windup = 0.5, recover = 1.5, damage = 8, range = 5, width = 3, height = 5, interrupt = "stagger" }
	config.crowd = {
		kinds = {
			fodder = { radius = 1.3, headRadius = 0.7, height = 5, speed = 12, hp = 40, armor = 0, knockbackMult = 1.0, brain = "rush", perPlayer = 2, attacks = { lunge } },
			slinger = {
				radius = 1.2, headRadius = 0.65, height = 5, speed = 11, hp = 50, armor = 0, knockbackMult = 1.0, brain = "keepAway", bandMin = 18, bandMax = 30, perPlayer = 1,
				attacks = { { shape = "shot", reach = 32, windup = 0.6, recover = 2.2, damage = 12, speed = 28, radius = 1.0, seconds = 2.5, lead = 0.7, interrupt = "stagger" } },
			},
			brute = {
				radius = 2.2, headRadius = 0.9, height = 7.5, speed = 10, hp = 320, armor = 0, knockbackMult = 0.35, brain = "rush", perPlayer = 1,
				attacks = { { shape = "lane", reach = 22, windup = 0.8, recover = 1.5, damage = 28, knockback = 40, launch = 3, range = 30, width = 5, speed = 55, height = 5, interrupt = "heavy" } },
			},
			armoured = {
				radius = 1.7, headRadius = 0.8, height = 6.5, speed = 9, hp = 160, armor = 18, knockbackMult = 0.35, brain = "rush", plate = 90, perPlayer = 1,
				attacks = { { shape = "arc", reach = 6, windup = 0.8, recover = 1.2, damage = 30, knockback = 30, launch = 6, range = 7.5, arcDegrees = 120, height = 6, interrupt = "heavy" } },
			},
			platedFodder = { radius = 1.3, headRadius = 0.7, height = 5, speed = 12, hp = 40, armor = 0, knockbackMult = 1.0, brain = "rush", plate = 90, perPlayer = 2, attacks = { lunge } },
			caller = {
				radius = 1.3, headRadius = 0.7, height = 5, speed = 0, hp = 400, armor = 0, knockbackMult = 0, brain = "rush", perPlayer = 1,
				attacks = { { shape = "summon", reach = 60, windup = 0.3, recover = 1.0, damage = 0, count = 2, summon = "pawn", radius = 5, cooldown = 100, interrupt = "none" } },
			},
			pawn = { radius = 1.3, headRadius = 0.7, height = 5, speed = 12, hp = 40, armor = 0, knockbackMult = 1.0 },
		},
		behaviour = { walkLength = 20, strafeWidth = 8, strafePeriod = 1.1, hopHeight = 7, hopPeriod = 1.6, chaseStandoff = 2, homePace = 0.5, homeTolerance = 0.75, walkPace = 0.6 },
		snapshotHz = 15, maxAlive = 160, deadSeconds = 0.6, knockFriction = 75, knockMax = 140, armorFloor = 0.1,
		heavyHit = 40, largeRadius = 2.5, staggerSeconds = 0.25, plateBreakSeconds = 1.0,
		threat = { spawnGrace = 1.0, spawnClear = 12, maxShots = 24, strikeSeconds = 0.2 },
	}
	config.player = { downSeconds = 2, getUpIframes = 1.5, regenDelay = 4, regenPerSecond = 0, knockIframes = 0.4 }
	config.shooting = { originLagSeconds = 0.05, originLagMaxSeconds = 0.3 }
	config.movement = { walkSpeed = 20, dashDistance = 20, dashSeconds = 0.15, slamFallSpeed = 140 }
	L1BC.other = players[2].Character
	players[2].Character = nil
	local _, _, god = Vitals.Readout(player)
	L1BC.wasGod = god == true
	Vitals.SetGod(player, true)
	Crowd.SetScales({ hp = 1, plate = 1 })
	Crowd.SetCampRules(nil)
	fresh()
end

function L1BC.leave(): ()
	fresh()
	Crowd.SetCampRules(nil)
	Crowd.SetBounds(vec(0, 0, 0), vec(100, 50, 100))
	Vitals.SetGod(player, L1BC.wasGod)
	players[2].Character = L1BC.other
	config.crowd, config.player, config.shooting, config.movement = L1BC.saved.crowd, L1BC.saved.player, L1BC.saved.shooting, L1BC.saved.movement
end

-- Runs `cases` inside enter and leave, even when it throws.
function L1BC.crowdGroup(name: string, cases: () -> ()): ()
	L1BC.enter()
	L1BC.group(name, cases)
	pcall(L1BC.leave)
end

-- The P4 range set that the wave must not change: eight bodies (four fighting kinds, three passive)
-- for 30 steps on the range's one floor. Hashed over every entry's bytes but the header's time,
-- with each id taken relative to the first (ids and the clock depend on the cases before).
-- RANGE_HASH was recorded on the code before L1b (2026-10-14), from this very function.
L1BC.RANGE_HASH = 2948329570
L1BC.RANGE_BYTES = 2400
function L1BC.rangeBytes(): (number, number)
	Crowd.SetBounds(vec(0, 0, 0), vec(100, 50, 100))
	root.Position = vec(0, 3, 0)
	local first = Crowd.Spawn("fodder", vec(0, 0, 14), "fight")
	Crowd.Spawn("fodder", vec(6, 0, 12), "fight")
	Crowd.Spawn("slinger", vec(-20, 0, 18), "fight")
	Crowd.Spawn("brute", vec(18, 0, -16), "fight")
	Crowd.Spawn("armoured", vec(-9, 0, -9), "fight")
	Crowd.Spawn("pawn", vec(30, 0, 30), "idle")
	Crowd.Spawn("pawn", vec(-30, 0, 20), "chase")
	Crowd.Spawn("pawn", vec(40, 0, -40), "idle", vec(36, 0, -40))
	local hash = 5381
	local bytes = 0
	for _ = 1, 30 do
		step2()
		local data = lastSnapshot
		for index = 0, buffer.readu8(data, 1) - 1 do
			local offset = 10 + index * 11
			local values = { buffer.readu16(data, offset) - first }
			for byte = 2, 10 do
				table.insert(values, buffer.readu8(data, offset + byte))
			end
			for _, value in values do
				hash = (hash * 33 + value) % 4294967296
				bytes += 1
			end
		end
	end
	return hash, bytes
end

function L1BC.floorTests(): ()
	print(" CrowdService with two floors")
	local Codec = L1BC.Codec
	local A = { centre = vec(-36, 8, -36), half = vec(30, 200, 30) }
	local B = { centre = vec(88, 12, -36), half = vec(40, 200, 40) }
	check(Crowd.SetFloors({ A, B }) == true, "two floors are set with nobody alive")
	root.Position = vec(0, 3, 300)
	local onA = Crowd.Spawn("pawn", vec(-36, 0, -36), "idle", nil, nil, 1)
	local onB = Crowd.Spawn("pawn", vec(88, 0, -36), "idle", nil, nil, 2)
	local defaulted = Crowd.Spawn("pawn", vec(-30, 0, -30), "idle")
	local wideB = Crowd.Spawn("pawn", vec(200, 12, -36), "idle", nil, nil, 2)
	local wideA = Crowd.Spawn("pawn", vec(200, 8, -36), "idle", nil, nil, 1)
	check(Crowd.Spawn("pawn", vec(0, 0, 0), "idle", nil, nil, 3) == 0, "a floor index the list does not hold is refused")
	step2(2)
	check(near(Crowd.Get(onA).position.Y, 8) and near(Crowd.Get(onB).position.Y, 12), "each body stands on its own floor (8 and 12)")
	check(near(Crowd.Get(defaulted).position.Y, 8), "a spawn with no floor is on floor 1")
	check(near(Crowd.Get(wideB).position.X, 126.7) and near(Crowd.Get(wideA).position.X, -7.3), `each is clamped to its own rectangle ({Crowd.Get(wideB).position.X}, {Crowd.Get(wideA).position.X})`)
	local infoFloor: { [number]: number } = {}
	for _, info in risen do
		infoFloor[info.id] = info.floor
	end
	check(infoFloor[onA] == 1 and infoFloor[onB] == 2 and infoFloor[defaulted] == 1, "its spawn info names its floor, always")
	check(Crowd.AliveOn(1) == 3 and Crowd.AliveOn(2) == 2 and Crowd.AliveOn(3) == 0, "AliveOn counts per floor")
	Crowd.Damage(onB, 100000, 7, nil, nil)
	check(Crowd.AliveOn(2) == 1 and Crowd.AliveOn(1) == 3, "a kill lowers its own floor's count only")
	Crowd.Remove(wideA)
	check(Crowd.AliveOn(1) == 2 and Crowd.AliveOn(2) == 1, "and so does a removal")
	check(Crowd.SetFloors({ A }) == false and Crowd.SetBounds(vec(0, 0, 0), vec(100, 50, 100)) == false, "SetFloors and SetBounds are refused with a body alive")
	step2()
	check(near(Crowd.Get(onA).position.Y, 8) and near(Crowd.Get(wideB).position.Y, 12), "(and nothing moved)")

	-- A strike lies on its attacker's floor.
	table.clear(struck)
	root.Position = vec(88, 15, -36)
	local fighter = Crowd.Spawn("fodder", vec(88, 12, -31), "fight", nil, nil, 2)
	waitFor(fighter, "windup", 60)
	for _ = 1, 20 do
		if #struck > 0 then
			break
		end
		step2()
	end
	check(#struck > 0 and struck[1].floorY == 12, `a strike's floorY is its attacker's floor: 12 ({if struck[1] ~= nil then struck[1].floorY else "no strike"})`)

	-- A summon takes its summoner's floor.
	local caller = Crowd.Spawn("caller", vec(80, 12, -40), "fight", nil, nil, 2)
	local raised: { any } = {}
	for _ = 1, 60 do
		step2()
		for _, info in risen do
			if info.summonerId == caller then
				table.insert(raised, info)
			end
		end
		if #raised > 0 then
			break
		end
	end
	local summonOk = #raised > 0
	for _, info in raised do
		local body = Crowd.Get(info.id)
		summonOk = summonOk and info.floor == 2 and body ~= nil and near(body.position.Y, 12)
	end
	check(summonOk, `a summon stands on its summoner's floor (2, y 12): {#raised} raised`)

	local beforeA = Crowd.AliveOn(1)
	Crowd.ClearFloor(2)
	check(Crowd.AliveOn(2) == 0 and Crowd.AliveOn(1) == beforeA and Crowd.Get(onA) ~= nil and Crowd.Get(caller) == nil, "ClearFloor removes that floor's bodies and leaves the other floor alone")
	check(Crowd.SetFloors({}) == false, "an empty floor list is refused")
	check(Crowd.SetFloors({ { centre = vec(0 / 0, 0, 0), half = vec(1, 1, 1) } }) == false, "and a non-finite one")

	fresh()
	check(Crowd.SetBounds(vec(10, 4, 10), vec(20, 50, 20)) == true, "SetBounds with nobody alive")
	local one = Crowd.Spawn("pawn", vec(10, 0, 10), "idle")
	check(one ~= 0 and Crowd.Spawn("pawn", vec(10, 0, 10), "idle", nil, nil, 2) == 0, "SetBounds is one floor, at index 1")
	step2()
	check(near(Crowd.Get(one).position.Y, 4), "and a body stands on it")

	fresh()
	local hash, bytes = L1BC.rangeBytes()
	check(hash == L1BC.RANGE_HASH and bytes == L1BC.RANGE_BYTES, `a P4 range set's snapshot bytes over 30 steps are those before L1b (hash {hash}, {bytes} bytes)`)

	local entries = {
		{ id = 1, position = vec(1, 2, 3), yaw = 0.5, state = "rest", hpFraction = 1, plated = true, attack = 0 },
		{ id = 2, position = vec(-1, 0, 4), yaw = -0.5, state = "rise", hpFraction = 0.5, plated = false, attack = 0 },
	}
	local data = Codec.Encode(entries, vec(0, 0, 0), 1)
	local decoded = Codec.Decode(data, vec(0, 0, 0))
	check(#decoded == 2 and decoded[1].state == "rest" and decoded[2].state == "rise" and decoded[1].plated == true, "the codec round-trips rest and rise")
	check(buffer.readu8(data, 0) == 2 and buffer.len(data) == 10 + 22, "still version 2, 11 bytes an entry")
	check(bit32.band(buffer.readu8(data, 10 + 9), 15) == 8 and bit32.band(buffer.readu8(data, 21 + 9), 15) == 9, "rest is index 8 and rise index 9, appended")
end
L1BC.crowdGroup("floors", L1BC.floorTests)

-- Groups ------------------------------------------------------------------------------------------------
-- One floor at y 8, 60 x 60 round the origin (floor 1), and one far east at y 12 (floor 2).
function L1BC.campFloors(): ()
	check(
		Crowd.SetFloors({ { centre = vec(0, 8, 0), half = vec(30, 200, 30) }, { centre = vec(200, 12, 0), half = vec(30, 200, 30) } }) == true,
		"(two camp floors)"
	)
	Crowd.SetCampRules(L1BC.rules())
end

-- A group of `units` (kinds in order) at the posts CampBrain gives it; returns its index and ids.
function L1BC.place(def: any, units: { string }): (number, { number })
	local index = Crowd.AddGroup(def)
	local posts = L1BC.CB.Posts(def, #units)
	local ids = {}
	for k, kind in units do
		table.insert(ids, Crowd.SpawnResident(kind, index, posts[k]))
	end
	return index, ids
end

function L1BC.events(): { any }
	local out = {}
	Crowd.DrainGroupEvents(function(event)
		table.insert(out, event)
	end)
	return out
end

function L1BC.restTests(): ()
	print(" CrowdService with groups: rest, the wake, the rise")
	L1BC.campFloors()
	root.Position = vec(0, 11, 25)
	local fire = L1BC.def("fire", { vec(0, 8, 0) }, { radius = 4 })
	local index, ids = L1BC.place(fire, { "fodder", "fodder", "fodder" })
	check(index == 1 and ids[1] ~= 0 and ids[3] ~= 0, "a fire group of three is placed")
	check(Crowd.AddGroup(L1BC.def("guard", { vec(0, 8, 0) }, { floor = 5 })) == 0, "AddGroup refuses a floor the list lacks")
	check(Crowd.AddGroup(L1BC.def("guard", { vec(0 / 0, 8, 0) })) == 0, "and a non-finite point")
	check(Crowd.SpawnResident("fodder", 9, { at = vec(0, 8, 0), yaw = 0, leg = 0 }) == 0, "SpawnResident refuses an unknown group")
	local seated = true
	local wound = false
	for _ = 1, 30 do
		step2()
		for _, id in ids do
			local state = seen(id).state
			seated = seated and state == "rest"
			wound = wound or state == "windup"
		end
	end
	check(seated and not wound, "a resting fire group with a target beyond its sight (21 > 16) stays seated on the wire and never winds up")
	check(#L1BC.events() == 0 and Crowd.Awake() == 0, "no event, nothing awake")
	local post = L1BC.CB.Posts(fire, 3)[1]
	local body = Crowd.Get(ids[1])
	check(near(body.position.X, post.at.X) and near(body.position.Z, post.at.Z) and near(seen(ids[1]).yaw, post.yaw, 2 * math.pi / 256), "a sitter stands on its post facing the fire")

	root.Position = vec(0, 11, 12)
	step2()
	local woke = L1BC.events()
	check(#woke == 1 and woke[1].group == 1 and woke[1].floor == 1 and woke[1].from == "rest" and woke[1].to == "rise" and woke[1].held == false and #woke[1].ids == 3, "walking into sight wakes it: one GroupEvent, rest to rise, with its three ids")
	local rising = 1
	while rising < 40 and seen(ids[1]).state == "rise" do
		step2()
		rising += 1
	end
	check(rising >= 22 and rising <= 24, `it shows rise for 1.5 s ({rising} steps at 15 Hz)`)
	local fought = L1BC.events()
	check(#fought == 1 and fought[1].to == "fight", "then one event, rise to fight")
	check(Crowd.Awake() == 1 and Crowd.Busy()[1] == true and Crowd.Busy()[2] == nil and Crowd.Engaged(7), "a fighting group: awake, its floor busy, the player engaged")
	-- A fall off the floor's edge mid-fight: out of the band (4 under the top at y 8) at once,
	-- then under killY. Engaged holds, so the rescue grants no get-up i-frames.
	root.Position = vec(0, 3.5, 34)
	step2()
	local fell = Crowd.Engaged(7)
	root.Position = vec(0, -14, 34)
	step2(8)
	check(fell and Crowd.Engaged(7), "a fall out of the fight (out of the band, then under killY 0.6 s later) is still engaged")
end
L1BC.crowdGroup("rest", L1BC.restTests)

function L1BC.allowedTests(): ()
	print(" CrowdService with groups: in play")
	L1BC.campFloors()
	join2(vec(40, 11, 0))
	root.Position = vec(-20, 11, 0)
	local guard = L1BC.def("guard", { vec(25, 8, 0) }, { yaw = math.pi / 2 })
	local _, ids = L1BC.place(guard, { "fodder" })
	step2(2)
	local blocked, dead, verdict = Crowd.Damage(ids[1], 10, 8, vec(0, 0, 40), 4)
	check(blocked == 0 and dead == false and verdict == "blocked", "a hit from a player out of play answers blocked")
	check(Crowd.Get(ids[1]).hp == 40, "and does nothing")
	step2()
	check(#L1BC.events() == 1, "but wakes the group")
	step2(3)
	local start = Crowd.Get(ids[1]).position.X
	step2(15)
	local now = Crowd.Get(ids[1]).position.X
	check(now < start - 4, `a fighting member goes for the nearer target in play (player 1, west), not a nearer one out of play (x {start} -> {now})`)
	check(Crowd.Engaged(7) and not Crowd.Engaged(8), "Engaged: the player in play, not the one outside it")
	leave2()
end
L1BC.crowdGroup("allowed", L1BC.allowedTests)

function L1BC.leashTests(): ()
	print(" CrowdService with groups: the leash, home and the heal")
	L1BC.campFloors()
	root.Position = vec(0, 11, -60)
	local guard = L1BC.def("guard", { vec(-4, 8, -10), vec(0, 8, -10), vec(4, 8, -10) })
	local _, ids = L1BC.place(guard, { "fodder", "platedFodder", "fodder" })
	local posts = L1BC.CB.Posts(guard, 3)
	step2(2)
	root.Position = vec(0, 11, -25)
	step2(3)
	local woke = L1BC.events()
	check(#woke >= 2 and woke[1].to == "rise" and woke[2].to == "fight", "the guards see the player and fight")
	local dealt = Crowd.Damage(ids[1], 10, 7, nil, nil)
	check(dealt > 0 and Crowd.Get(ids[1]).hp == 30, "a player in play hurts a fighting resident")
	local _, _, plate = Crowd.Damage(ids[2], 50, 7, nil, nil)
	local _, _, broke = Crowd.Damage(ids[2], 50, 7, nil, nil)
	check(plate == "plate" and broke == "broke" and seen(ids[2]).plated == true, "(the plated one's plate is broken; the wire shows it next step)")
	step2()
	check(seen(ids[2]).plated == false, "its plate is gone on the wire")
	-- They chase the player for a while, so the walk home takes several steps.
	step2(20)
	check(Crowd.Get(ids[1]).position.Z < -16, `(the chasers have left their posts: z {Crowd.Get(ids[1]).position.Z})`)
	Crowd.Damage(ids[3], 100000, 7, nil, nil)
	check(Crowd.AliveOn(1) == 2, "one is killed")
	root.Position = vec(0, 11, -60)
	local wentHome = false
	for _ = 1, 120 do
		step2()
		for _, event in L1BC.events() do
			if event.to == "home" then
				wentHome = true
			end
		end
		if wentHome then
			break
		end
	end
	check(wentHome, "with nobody in play for leashSeconds the group goes home")
	check(Crowd.Awake() == 1, "a group walking home is awake (L1b-19: the field is not clear)")
	check(Crowd.Busy()[1] == nil, "but its floor is not busy (the safe point may use it)")
	-- Back into play while they walk home, and out again before they rest (sight would wake them).
	root.Position = vec(0, 11, -25)
	step2()
	check(not Crowd.Engaged(7), "a player in play for a group walking home is not engaged")
	root.Position = vec(0, 11, -60)
	local before = Crowd.Get(ids[1])
	local value, killed, verdict = Crowd.Damage(ids[1], 30, 7, vec(0, 0, 60), 6)
	local zero, _, leverVerdict = Crowd.Damage(ids[1], 30, 0, nil, nil)
	step2()
	check(value == 0 and not killed and verdict == "blocked" and zero == 0 and leverVerdict == "blocked", "walking home it evades: every hit, the levers' too, answers blocked")
	check(#L1BC.events() == 0, "and a hit on the way home wakes nobody")
	local after = Crowd.Get(ids[1])
	check(after.hp >= before.hp and after.velocity.Y <= 0.001, "no damage and no launch")
	local rested = false
	for _ = 1, 120 do
		step2()
		for _, event in L1BC.events() do
			if event.to == "rest" then
				rested = true
			end
		end
		if rested then
			break
		end
	end
	check(rested, "once every survivor is at its post, the group rests")
	local atPosts = near(Crowd.Get(ids[1]).position.X, posts[1].at.X, 1.001) and near(Crowd.Get(ids[2]).position.X, posts[2].at.X, 1.001)
	check(atPosts, "the survivors stand at their posts")
	check(Crowd.Get(ids[1]).hp == 40 and Crowd.Get(ids[2]).hp == 40, "healed to full")
	step2()
	check(seen(ids[2]).plated == true and near(seen(ids[2]).hpFraction, 1, 1 / 255), "the broken plate is whole again")
	check(Crowd.Get(ids[3]) == nil or seen(ids[3]).state == "dead" or seen(ids[3]).state == "gone", "the one killed before stays dead")
	check(Crowd.AliveOn(1) == 2, "no refill")
	table.clear(L1BC.kills)
	Crowd.Damage(ids[1], 100000, 0, nil, nil)
	local record = L1BC.kills[1]
	check(record ~= nil and record.info.damageBy[7] == nil, "the heal emptied the damage book (player 7's 10 before the leash is gone)")
end
L1BC.crowdGroup("leash", L1BC.leashTests)

function L1BC.wakeTests(): ()
	print(" CrowdService with groups: WakeFloor, held, Awake, Busy, Engaged")
	L1BC.campFloors()
	root.Position = vec(0, 11, -200)
	local heldEast = L1BC.def("guard", { vec(200, 12, -10) }, { floor = 2, floorY = 12, rect = { x = 200, z = 0, hx = 30, hz = 30 }, held = true })
	local openEast = L1BC.def("guard", { vec(210, 12, 20) }, { floor = 2, floorY = 12, rect = { x = 200, z = 0, hx = 30, hz = 30 }, yaw = math.pi })
	local heldWest = L1BC.def("guard", { vec(0, 8, -10) }, { held = true })
	local g1, east = L1BC.place(heldEast, { "fodder" })
	local g2, open = L1BC.place(openEast, { "fodder" })
	local g3, west = L1BC.place(heldWest, { "fodder" })
	check(g1 == 1 and g2 == 2 and g3 == 3, "AddGroup numbers groups 1..n in call order")
	step2(2)
	root.Position = vec(0, 11, -20)
	step2(2)
	check(#L1BC.events() == 0 and seen(west[1]).state == "idle", "a held group does not wake on sight")
	local _, _, verdict = Crowd.Damage(west[1], 10, 7, nil, nil)
	check(verdict == "blocked" and Crowd.Get(west[1]).hp == 40, "nor can it be hurt before the close")
	step2()
	check(#L1BC.events() == 0, "nor does a hit wake it")
	root.Position = vec(200, 15, 0)
	Crowd.WakeFloor(2)
	step2()
	local released = L1BC.events()
	check(#released == 1 and released[1].group == 1 and released[1].held == true and released[1].from == "rest" and released[1].to == "rise", "WakeFloor releases only the held group of that floor (one event, held)")
	check(seen(east[1]).state == "rise", "it shows rise for its step")
	check(seen(open[1]).state == "idle" and seen(west[1]).state == "idle", "the open group on that floor and the held one on the other are untouched")
	check(Crowd.Awake() == 1 and Crowd.Busy()[2] == true and Crowd.Busy()[1] == nil, "Awake 1, floor 2 busy, floor 1 not")
	check(Crowd.Engaged(7), "the player on floor 2 is engaged")
	step2()
	check(#L1BC.events() == 1 and seen(east[1]).state ~= "rise", "a released guard rises for one step, then fights")
	root.Position = vec(0, 11, -200)
	step2()
	check(Crowd.Engaged(7), "out of play for every awake group a step later: still engaged (the hold)")
	step2(21)
	check(Crowd.Engaged(7), "22 steps (1.47 s) after the last in play: still engaged")
	step2()
	check(not Crowd.Engaged(7), "23 steps (1.53 s, past engagedHoldSeconds 1.5): not engaged")
	Crowd.ClearFloor(2)
	check(Crowd.Awake() == 0 and Crowd.Busy()[2] == nil, "a group with no living member is neither awake nor busy")
end
L1BC.crowdGroup("wake", L1BC.wakeTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
