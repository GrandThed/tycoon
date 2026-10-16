# L1c contract — the Chief's Clearing redone (draft for the lead, 2026-10-16)

Branch `l1c-chief-clearing` in `C:\Users\benja\Desktop\tycoon-p5`. Ben's decisions are in
`docs/MISSIONS_DESIGN.md` §21: there is a tall wall all round the clearing and a gatehouse passage
with one turn. The clearing has no residents and no big waves. When the gate shuts, a group of
about 8 to 10 rushes the player from both flanks, and when that group is dead the Colossus comes.
Nothing inside may be seen from outside, not even from the top of a double jump. Rulings are
numbered **L1c-n**. Every number is a starting value that the economy-designer measures and may
move within the rule that it serves.

## What today's code already gives us (checked 2026-10-16)

- **Held residents are the ambush, with no code change.** A locking camp's resident groups start
  **held** (L1b-13, `StageFlow.groupsOf` `held = camp.locks`). They rest, do not wake by sight or
  by a hit, and cannot be damaged. They are drawn from the run's start. The close calls
  `CrowdService.WakeFloor` (WaveService:1323), which releases every held group of the camp to
  `rise`. Posture `guard` has `rise` 0, so they charge at once. Residents ignore `countMult` and
  party size (L1b-10). Only `minDifficulty` adds units.
- **The close is today's close.** A standing root inside the trigger rectangle starts `gate`. The
  trigger rectangle is the floor grown by `levels.fenceThickness` 1. Then come `levels.gateSeconds`
  3 and `close`. At the close, anyone outside the floor inset by `closeInset` 2 is moved to `entry`
  (`moveFighters`). The gate boxes turn solid, and so does the 80-stud invisible wall, 8 deep
  outward from the floor's edge. Wave 1 is queued at the same moment.
- **An empty wave is legal.** `StageFlow.Validate` and the Python mirror (sim_range:5213) accept
  `{"groups": []}` with no boss. In `fight`, a wave clears on `spawningDone and alive == 0`, and
  `alive` is `CrowdService.AliveOn(floor)`, residents included. `Combat.Tempo` guards a total of 0.
  So wave 1 = `[]` clears exactly when the ambush is dead. After that come the breather
  (`breatherSeconds`) and then wave 2, the Colossus.
- **Gates may face any side.** LevelGeometry, Validate and check_levels' `gate_rect` all handle
  north, south, west and east. A locking camp needs no tent.
- **The wall can be the camp's own fence.** `fence.height` is free in LevelGeometry. `GateBoxes`
  are as tall as the fence, so a closed gate is as tall as the wall. The fence stands outside the
  floor, so the trigger, the band, the close and the barrier stay as they are.

## 1. Geometry (data first)

**L1c-1. Jump and camera numbers. The wall must be taller than any camera, not only any jump.**
| Item | Studs above the outside surface | Source |
|---|---|---|
| Feet at the double-jump peak | 18 + 12 = 30 | ProvingGrounds.json `movement.jumpHeight`, `doubleJumpHeight` |
| Root (R15) | +3 → 33 | sim_range `ROOT_HEIGHT` |
| Leap Smash cast at that peak (apex = start + `height`) | +10 → 43 | ProvingGrounds `leapSmash.height`; MovementController.Leap |
| Camera pivot and shoulder | +1.5 +0.6 → 45.1 | Theme `COMBAT_CAMERA_PIVOT_HEIGHT`; Combat.json `camera.shoulderOffset[2]` |
| Boom at `maxZoom` 16 and the lowest pitch −70° | +16·sin 70° = 15.04 → 60.1 | Combat.json `camera.maxZoom`; Theme `COMBAT_CAMERA_MIN_PITCH_DEGREES` |
| Shake | +0.35 → **60.5** | Theme (shake budget) |
- The pivot's height lag never takes it above the peak root.
- **Wall height 64 above the floor (`fence.height` 64; tops at y 76).** That is 3.5 of margin, it
  is under the 80-stud barrier, and every outside surface near C is at or below the floor's y 12.
- Nobody can climb it: the most anyone reaches is 43 + `STEP_UP` 3 = 46.
- The gatehouse walls are just as tall. Distant spots cannot see in: from the lookout (y 38, about
  600 studs away) a ray over a 76-high wall falls 64 studs only after about 1,400 studs.

**L1c-2. Layout (economy-designer; `ForestRoad.json`). Starting numbers, shown as boxes
x0..x1 / z0..z1, all floors topped at y 12.**
- **Move camp C south and turn it.** Its centre goes to (313.5, 12, 31.5), size 115 × 115, so
  the floor is x 256..371 / z −26..89. The north face is the entry and the east face is the exit.
  - The x0 of 256 is unchanged, which keeps the region margin (RoadBC3/4 stay 58 from C, need 56).
    It also keeps check_stage_mirror:294's road cell valid.
  - It leaves the lobby clearance alone. Moving C north instead would fail it: the lobby must
    stay 150 from the layout's box, and that move gives 124.
- **The wall.** Set `fence.height` to 64. The gates are
  `[{side "north", at 0, width 16}, {side "east", at −41.5, width 16}]`, so the entry opening is
  x 305.5..321.5 and the exit opening is z −18..−2.
  - `entry` is (313.5, −16), 10 inside.
  - `exit` is (361, −10), 10 inside.
  - The exit faces east, and nothing anyone can reach lies east of it.
- **The gatehouse.** It is six blocks: two `path` floors and four `wall` blocks, each 64 tall
  (y 12..76, block y 44, sy 64).
  - **Leg 1 (heading east).** `GatehouseWalk` is the path at x 256..321.5 / z −52..−36, carrying
    on from RoadBC6's end at x 256.
  - **The turn.** The corner square is x 305.5..321.5 / z −52..−36.
  - **Leg 2 (heading south).** `GatehouseTurn` is the path at x 305.5..321.5 / z −36..−26, running
    up to the floor's edge as RoadBC6 does today.
  - **The four walls:**
    - `GatehouseWallN`: x 256..323.5 / z −54..−52
    - `GatehouseWallS`: x 256..305.5 / z −36..−34
    - `GatehouseWallE`: x 321.5..323.5 / z −54..−27
    - `GatehouseWallW`: x 303.5..305.5 / z −36..−27
  - With these, any line from the road or from leg 1 to the entry opening crosses WallS or WallW.
    Only leg 2 and the corner look at the gate.
- **Width 16** for both legs, the same as the road and the gate (`ROAD_MIN_WIDTH` 12).
  - Walking the centreline, the camera's shoulder point (1.75 to the right, plus a collision
    radius of 0.5 + 0.2) keeps 5.5 studs from either wall.
  - The corner is square, so the boom never meets a diagonal.
- **The lock triggers past the turn.** It fires when a standing root reaches z ≥ −27, the
  fence's outer face. That is 9 studs after the corner square ends.
- **What shuts behind the player.**
  - `Gate_C_1` closes: 16 wide, 64 tall, the gate look.
  - The barrier band turns solid. It runs 8 deep over z −34..−26, which covers leg 2's last 8 studs.
  - `moveFighters` puts anyone not inside onto `entry`.
- **The exit.** `Gate_C_2` is on the east face. `TrailEnd` moves to x 371..387 / z −18..−2.
- **The route and the sneak.**
  - Route tail: (229,8,−44) → (231,12,−44, climb) → (313.5,12,−44) → (313.5,12,−16) →
    (361,12,−10, via camp). It comes to about 1,079 studs (band 900–1,100).
  - Sneak tail: … (250,−44) → (313.5,−44) → (313.5,−16), which is the new entry.
- **Inside the camp.**
  - Delete the spots `gate`, `chiefFire`, `north` and `south`, and delete C's `tent` block.
  - Add two `guard` spots, each on the line z −22 (a brute's 2.2 + `POST_SPARE` 1 inside the north
    edge, plus a little). Each faces the entry, using CampBrain's convention (0 faces −Z, yaw =
    atan2(−dx, −dz)):
    - `ambushW`: five posts at x 263.5..283.5
    - `ambushE`: five posts at x 343.5..363.5
  - Every post is **at least 30 studs sideways from the gate's centreline** (see L1c-4).
  - Four `spawns` at least 12 from the entry; the gate requires them, though no wave uses them:
    (313.5, 75), (265, 75), (362, 75), (362, 40).
  - The `checkpoint` goes at (313.5, −6).
  - The two existing covers (at most 3.5 tall) are re-placed at least 12 from the entry and out of
    the flank lanes.
- **Part count.** It goes from 82 to about 86 (+6 gatehouse, −C's tent marker, −C's fire marker),
  against a maximum of 600.

**L1c-3. Smallest code changes for the geometry.** These are all in tools; the game builds
everything from the data above.
- **`check_levels.py`, "unclimbable wall".** A `wall`-look block, or a camp fence, whose top stands
  at least `CLIMB_MAX` = jumpHeight + doubleJumpHeight + max ability `height` (Leap Smash 10) +
  `STEP_UP` = 43 above every standable surface within `stray_reach` is not standable ground.
  That applies in five places:
  - the fence-height rule (577: today it requires ≤ triggerHeight − 3 = 27; a fence like this is
    exempt instead);
  - the band rule (668–706: GatehouseWallE and GatehouseWallW stand in the band);
  - the beside rule;
  - `sniper_spots`;
  - the perch gate.
- **`check_levels.py`, beside rule (644–663).** Count only solids within `stray_reach(move, 0)`
  (about 46.6) of the fenced rectangle. That is what the rule's own message says it measures.
  Skip `path` blocks that run through the camp's own gates, as the band rule already does. Today
  the rule counts every solid in the layout that overlaps the crossing span, which fails a camp
  south of the road and an east exit off a north entry.
- **New gate in `check_levels.py`, "walled camp":** `EXPECTED.ForestRoad.walled = ["C"]`.
  - **Height.** `fence.height` ≥ the camera top of L1c-1 (60.5) + 3.
  - **Gatehouse.** Every wall block within `stray_reach` of the fenced rectangle has its top at or
    above the fence top.
  - **Floors.** Every standable surface within 200 studs is at or below the floor's y.
  - **Sight (2D, since the walls are taller than any camera).**
    - Eye points: every 2 studs on every outside standable top.
    - Camera points: every 2 studs within maxZoom + 2 = 18 of an eye point. Leave out points
      inside a wall footprint or inside a locking camp's fenced rectangle (the camera clip,
      L1c-5).
    - Targets: the centre ± radius (perpendicular to the line) of each body at each resident post.
    - No segment from a point to a target may avoid every wall footprint and the fence (cut at its
      gates).
    - **Doorway exemption:** points within 2.5 studs of the fenced rectangle and inside a gate's
      lane.
  - **Plates.** A walled camp's residents field no plated kind (`armoured`, `guard`) at any
    difficulty (see L1c-6).
  - Each new rule must be shown to fail on a mutated scratch copy of the layout (the vacuous-rule
    lesson).

## 2. The ambush

**L1c-4. Held flank residents. Stage waves = [empty, Colossus].** This is the simplest correct
mechanism: it needs no spawn at the close, so nothing appears out of thin air.
- The ten bodies stand at their posts from the start of the run. They are hidden by the north
  wall: a post at 30 sideways and about 4 inside can be seen only from the doorway, within about
  2 studs of the trigger line.
- At the close they rise and charge about 35 studs, roughly 3 s at fodder speed 12, from left and
  right.
- Wave 1 (empty) clears when the last one dies. After `breatherSeconds` 3, wave 2 places the
  Colossus at `at` [0, 30], which is (313.5, 61.5), 77 from the entry (`spawnClear` needs 12).
- Spawning at the close was the alternative. It was rejected because bodies would pop into view
  for anyone who had turned round, and the 8-per-burst cap would bring the last two in 3.5 s late.
- **Units** (`1_ForestRoad.json`, `camps` C). Only rushers: no shooter would rush, and no plate
  (L1c-6).
  - `ambushW`: fodder 4, brute 1, plus brute 1 at `minDifficulty: "hard"`.
  - `ambushE`: the same.

  | Difficulty | Bodies | Made of | Notes |
  |---|---|---|---|
  | Normal | 10 | 8 fodder, 2 brutes | |
  | Hard | 12 | 8 fodder, 4 brutes | hp × 5.2 |
  | Brutal | 12 | 8 fodder, 4 brutes | hp × 11.5 |

  `countMult` reads nothing here: residents are never scaled, and the empty wave has no group.
- **Stage** "The Chief's Clearing":
  `waves: [{"groups": []}, {"groups": [], "boss": {"kind": "colossus", "at": [0, 30], "valor": 10}}]`,
  with `breatherSeconds` 3 and `maxAlive` 42 (room 32 for the Colossus's calls).
  `targetWaveSeconds` stays; it is unused while `merge` is false.

## 3. Visibility

**L1c-5. Every client path, checked 2026-10-16. A path matters only before the close: after it,
every fighter is inside and the waiting members are in the lobby, more than 300 studs away.**
| Path | Outside, before the close? | L1c ruling |
|---|---|---|
| Crowd bodies (`CrowdRenderer`, anchored Parts, no cull) | Hidden by opaque walls, which are taller than the Colossus (14) | none |
| Plate bar (`ThreatFx/PlateBar`, `AlwaysOnTop`, `MaxDistance` 160) | **Yes**, through the wall for any plated resident | L1c-6 (data) |
| CampFx "!" on wake (`AlwaysOnTop`, 200) | Fires at the close only, when nobody fighting is outside | none |
| Marksman line, slam ring, lob circle | The residents are held (they never attack); nobody is outside during the fight | none |
| Boss bar, HUD counts (`GetBoss`, `CombatHud`) | The Colossus spawns after the close | none |
| Touch auto-fire (`CampAim` refuses held groups) | No | none |
| Legacy `FxHighlight`, `floatText` (AlwaysOnTop) | Only on legacy `Enemies` rigs, which this level never uses | none |
| Snapshots to every client (`FireAllUnreliable`) | Positions reach every client: an exploit could read them, but they are never drawn | accepted |
| **Camera**: spherecast through the open gate (open gates are CanQuery false) | **Yes**: from the last ~10 studs of leg 2, a swung camera goes through the gap and looks along the inner wall | **L1c-5a** (code) |
| Default Roblox camera when there is no rig | Only in a narrow window (the down state is 1 HP) | optional: `CameraMaxZoomDistance` 16 in `combat.project.json` (lead) |

- **L1c-5a. Camera clip (the only code needed for sight).**
  - The behaviour: the camera's boom never enters the fenced rectangle (floor + `fenceThickness`)
    of a locking camp unless the local root is inside that rectangle. It is pulled back to the
    rectangle's edge minus `COMBAT_CAMERA_COLLISION_PAD`.
  - The clip lives in a new pure module, `src/shared/WallClip.luau`, so the harness can test it:
    `WallClip.Reach(fromX, fromZ, dx, dz, rects: {Rect}, rootX, rootZ, pad): number` returns the
    share 0..1 of the flat boom that stays outside every rect that does not hold the root. The
    client already has floor rects: `RunFloor` gains `locks: boolean?`, which WaveService sets from
    `zone.locks`.
  - Walls outside a camp keep doing their job through the spherecast.
- **L1c-6. No plated resident in a walled camp.** Data rule, with a check_levels gate. It avoids
  changing the plate bar's `AlwaysOnTop` for every camp. If Ben later wants armoured ambushers,
  the plate bar must first hide while its group is held.

## 4. Rewards and pace (proposals; Ben may say "about right" at his look)

**L1c-7.** Normal at 2/2, from BALANCE L1b's fix round:
- Today a clear takes 6.33 min (band 345–420 s) and pays 155,130 cash, 258 Timber and 10 Valor.
- C's residents and waves are 46,600 cash and 66 Timber, plus its bonus of 4,660. Before the boss,
  C takes about 110 s.
- The ambush pays 4,800 cash and 6 Timber, plus a bonus of 480, and takes about 20–25 s. With the
  breather, C before the boss is about 28 s.

| Normal at 2/2 | Today | After, unchanged pay | After, with the proposal |
|---|---|---|---|
| Clear time | 6.33 min | **about 4.9 min** | about 4.9 min |
| Cash | 155,130 | about 109,000 | **about 121,000** |
| Cash per minute | 24.5k | 22.2k (−10%) | 24.7k |
| Timber per minute | — | about 40 (in its 37.8–46.2 band) | about 40 |

- **Proposal: keep cash per minute, not total cash.**
  - Colossus `cash` 29,000 → **41,000**; Timber 70 and Valor 10 unchanged.
  - `targetMinutes` 6 → **5**.
  - sim_range `FOREST_CLEAR_SECONDS` (345, 420) → re-measured. Expected about (255, 330).
- **Checks.**
  - The bonus share is about 5.7% (sim_combat band 5–10%).
  - The Hard ×2–3 and Brutal ×4–6 pay ratios hold, since `rewardMult` is uniform.
  - The ambush itself is banded at 15–35 s on Normal 2/2 and at most 60 s on Hard 4/4 and Brutal
    6/6. If Hard's four brutes take longer, the designer moves one Hard brute to fodder 2.
  - The Colossus fight (64–90 s) is unchanged, and so are the boss gates.

## 5. Gates to update

| Gate | Goes red because | New expectation |
|---|---|---|
| check_levels:577 fence rule | fence 64 | exempt as an unclimbable wall (L1c-3) |
| check_levels:644–663 beside | the camp now lies south of the road; east exit | reach-based, own-gate paths skipped (L1c-3) |
| check_levels:668–706 band | GatehouseWallE and GatehouseWallW | unclimbable walls are not ground |
| check_levels:82–86 `lockedResidentsMin` 4 | stale | `lockedResidents` (8, 12) at every difficulty |
| check_levels:92 `sniperSpots` | GatehouseWalk and GatehouseTurn are new standable tops near the region | add both; sim_range rates them; add them to `SNIPER_KNOWN_LIMIT_L4` only if over the limit (Ben accepted perches until L4) and say so |
| check_levels walled gate | new | L1c-3 |
| sim_range `FOREST_CLEAR_SECONDS` 4990 | clear is about 4.9 min | re-measured band (L1c-7); BALANCE says why |
| sim_range scene walls (7466) | only fence strips | also every colliding `wall` block, so the gatehouse cuts sniper and sight lines |
| sim_range Timber/min, `HUMAN_BELOW_SLOWER` | shorter clear | re-measure; they must stay green |
| sim_combat `targetMinutes` check | follows the level file | green at 5 |
| tests_l1.luau:2041–2058 "each wave fields a body or a boss" | empty wave 1 | an empty wave is allowed only as wave 1 of a locking camp with residents; assert C's waves are [empty, Colossus] |
| tests_l1b_w2.luau:390 `markers == 3` | C's tent gone | 2, "A's and B's" |
| check_stage_mirror.py:229–230 | `chiefFire` gone (StopIteration) | aim the refusal at `ambushW`, raised to ≥ maxAlive − 5 |
| check_stage_mirror.py:294 | none (x0 still 256) | stays; re-run |
| tests_l1.luau:909–940 labels | stale text | relabel only |
| New `tests_l1c.luau` | — | `WallClip.Reach` (root inside / outside, gate gap, corner, pad, NaN); `LevelGeometry.Pieces` on the shipped layout (gate boxes 64 tall, no `Camp_C_Tent`, gatehouse blocks built colliding); `Plan` (C's residents held, 10/12/12, stage waves 2) |
| BALANCE.md lines 4287–4289, 4321–4330, 4406, 4467–4473, 4767–4773, 4827, 4860–4867, 4972–4973 | C's old residents, tent, sneak, fence tops and sniper rows | new "L1c" section; old lines marked superseded |

## 6. Owners (disjoint; one wave; the gates run after all three)

- **economy-designer:** `src/shared/Layouts/Levels/ForestRoad.json`,
  `src/shared/Config/Levels/1_ForestRoad.json`, `tools/check_levels.py`, `tools/sim_range.py`,
  `docs/BALANCE.md`.
  - Done when: L1c-2, -4 and -7 are in the data, and L1c-3's three tool changes and the walled gate
    are in.
  - Every new rule has been shown to fail on a mutated scratch copy.
  - `py tools/check_levels.py` is green with the sight gate's tightest margin reported.
  - `py tools/sim_range.py` is green on the Forest Road course, the sniper course and the ambush
    band.
  - BALANCE has an "L1c" section with measured numbers.
- **luau-engineer:** `src/shared/Types.luau` (`RunFloor.locks`),
  `src/combat/server/Services/WaveService.luau` (one field in `runFloors`),
  `src/shared/WallClip.luau` (new, pure, `--!strict`), `tools/crowd_harness/tests_l1.luau`,
  `tests_l1b_w2.luau`, new `tests_l1c.luau` (registered wherever the harness lists its suites),
  `tools/check_stage_mirror.py`, and `mutate.py` entries for WallClip and the new tests.
  - Done when the harness and check_stage_mirror are green against the designer's data. If the
    data is not in yet, run against a scratch copy and re-run once it is.
  - `py tools/check_compile.py` passes.
  - No other server code changes.
- **ui-engineer:** `src/combat/client/Controllers/CameraController.luau`, and
  `src/combat/client/Controllers/CombatUIController.luau` only where it hands RunState floors on
  (next to `CrowdRenderer.SetFloors`, line 1679).
  - Done when the boom is clipped by `WallClip.Reach` per L1c-5a, using the API above (code
    against the signature; luau-engineer ships the module).
  - Nothing else in the camera changes.
  - CameraController stays under check_compile's top-level local cap (it is 1,054 lines: group
    the new state into a table).
- **Lead:** this section goes into INTERFACES as "# L1c contracts". Optional:
  `CameraMaxZoomDistance` in `combat.project.json`. Then review (one or two slices: data and tools,
  code), QA (stylua, selene, luau-lsp with `tools/types/globalTypes.d.luau`, rojo build,
  check_compile, harness, mutate, check_levels, check_stage_mirror, sim_range, sim_combat), docs.

## 7. Risks, and what Ben must decide

- **Leap Smash onto a wall top.** The leap's target is a camera ray pulled back to `castRange` 32
  on the flat, then probed downward from 3 studs above. A player who stands about 32 studs from a
  wall and aims over it can land the probe on the 1–2-stud top and leap up, which is a perch that
  sees everything. The window is narrow, and it applies to any tall wall.
  - The reviewer confirms whether a family with `leapSmash` can be carried into Forest Road.
  - If it can, the fix is one rule in both mirrors (`RangeService.GroundPoint`,
    `InputController.groundPoint`): a target more than jump + double jump above the caster's floor
    is refused. It goes to the fix round.
  - Glide and jetpack (later levels) must also be off near a walled camp.
- **The doorway glimpse.** From within about 2 studs of the trigger line (in the gate itself), the
  eye sees the nearest flank posts. One more step triggers the camp, so this is accepted.
- **Inside the clearing the camera now meets a 64-stud wall** where it used to pass over a
  4-stud fence. When the player backs into the wall, the boom pulls in close.
- **The run is about 1.4 minutes shorter** and C is half as long. The Colossus pay raise keeps
  cash per minute.
- **Co-op.** The ambush does not scale with party size (L1b-10), so four players flatten it. That
  is for L5.
- **For Ben (not blocking):** at his look, ask whether the shorter clear and the bigger Colossus
  pay are "about right". Nothing else needs him.

## 8. Lead's rulings (2026-10-16, after reading the draft)

- **Accepted as written:** camp C moved south, the 64-stud fence as the wall, the one-turn gatehouse into a
  north gate, the held flank groups as the ambush (10 Normal / 12 Hard and Brutal, no armoured or guard
  units in a walled camp), waves [empty, Colossus], Colossus cash 41,000, `targetMinutes` 5, the doorway
  glimpse, the camera clip.
- **Leap Smash wall-top perch is fixed in THIS wave, not the fix round** (any tall wall makes it reachable,
  and later levels will have more): a leap target more than `jumpHeight + doubleJumpHeight` above the
  caster's floor is refused, by one rule mirrored on both sides. Owners: **luau-engineer** adds it to
  `RangeService.GroundPoint` (server, `src/combat/server/Services/RangeService.luau`), **ui-engineer** to
  `InputController.groundPoint` (client). The limit is read from config, never re-typed. Add a harness
  case for the server rule. Both report the exact expression so the lead can compare.
- Every agent: `git status` / `git diff` first (work may be partly done), commit nothing, kill only your own
  PIDs, write your report to `docs/prompts/l1c-reports/<role>.md` as well as replying.
