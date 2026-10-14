# L1b Wave 2 fix round — luau-engineer B (the run, the level, the tests)

Status: **done.** B-1, B-2, B-3 done. B-4 is done in my files: the door is planned and tested.
Its last line in `WaveService` waits for A's `SpawnResident` argument and the `rises` flag
(requests 1 and 2 below, not routed yet). Registered: the ui-engineer's `CampAim` source, its 12
cases and 6 mutations, and A's 15 mutations (`L1B_W2_FIX_A_MUTATIONS`, texts verbatim from
fix-A.md). The final runs were on the final state, after A's and econ's work was in the tree, one
after the other:

- `run_harness.py`: **`HARNESS: PASS (1,969 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`**
- `mutate.py`: **`MUTATIONS: 606 run, 0 not caught`** (its baseline is the same 1,969 PASS)
- `check_stage_mirror.py`: `CHECK: PASS` (econ mirrored `doors` and the every-difficulty check)

## Done

- **B-1 (run m1), `WaveService.tickTents`:** after a body is placed, its id is appended to
  `run.awakeGroups[tent.group]` when that entry exists (the group is in rise or fight), so a tent
  body that joins a group already up is a threat for `SafePoint` at once. The entry is the
  `table.clone` `onGroupEvent` made, so appending is safe.
- **B-2 (run m2), `StageFlow.Validate` (`campProblems`):** the post checks for resident groups
  (guards, patrols, fires) and for tent rings now run at **every difficulty the level offers**,
  highest rank first (each rank's own `groupsOf` / `tentsOf`, its own widest kind). A group is
  told of once (`told[id]`), at the highest difficulty it fails at; the problem texts are
  unchanged. Wave 1's fire rings are covered by the same loop.
- **B-3 (crowd note), `WaveService.tickTents` + new pure `StageFlow.TentOwesRouse(owed,
  campBusy, groupAwake): boolean` (= `owed and campBusy and not groupAwake`):** a body sent
  while a group of its camp is in rise or fight sets `tent.owed` unless its own group is already
  up; every tick an owed tent calls `CrowdService.RouseGroup(tent.group)` again, until the group
  is up (`run.awakeGroups[tent.group] ~= nil`) or the camp is quiet. With today's
  `CampBrain.Rouse` (rest only) a group walking home therefore rises the step it is back home,
  not at once; "at once" needs A's change below. Works either way: once the group has risen the
  debt is paid and nothing re-rouses it.
- **B-4 (data note), the door:**
  - new pure `LevelGeometry.TentDoor(box: Box, x: number, z: number, clear: number): (number,
    number)`: on the line from the marker's centre to the post at (x, z), `clear` studs past the
    footprint's edge (negative = 0), never past the post; a post inside the footprint or at its
    centre is its own door. Numbers only (LevelGeometry has no Vector3).
  - `StageFlow.PlanTent` gains `doors: { Vector3 }`, paired with `posts`, built in `tentsOf` from
    `LevelGeometry.TentBox(camp)` with the body's kind radius as `clear` (Plan's 7th argument
    `kinds`; without it the door is on the wall), at the post's Y. `tentsOf` gains an optional
    5th argument `crowdKinds`; Validate's calls do not pass it (it reads no door).
  - **Not yet used by `WaveService`:** `CrowdService.SpawnResident` has no start position. Once
    A lands it (request 1 below), my line in `tickTents` becomes
    `CrowdService.SpawnResident(kind, tent.group, post, planned.doors[following])`.
- **Harness:** `tests_l1b_w2.luau` gains `W2B.fixTests` (B-2: a tent ring and a resident fire
  that only Normal pushes past the floor, a legal near-miss, told once for a ring and a fire;
  B-3: `TentOwesRouse`'s four answers; B-4: `TentDoor` east, corner, capped at the post, inside,
  centre, negative clearance, a 14 x 6 box, and Plan's doors paired, by kind radius, on the line
  to the post, without kinds on the wall). `run_harness.py` gains `CampAim` in `SOURCES`;
  `tests_l1b_w2.luau` carries the ui-engineer's 12 cases verbatim before its verdict line.
- **`mutate.py`:** two stale texts fixed (B-2's loop added a tab): "l1b: Validate lets a post hang
  its widest kind over the edge" and "l1b w2: Validate lets a ring post hang its widest kind over
  the edge" (same rules, new indentation). New `W2_FIX_B_MUTATIONS` (13) and
  `W2_FIX_UI_MUTATIONS` (6, the ui-engineer's texts verbatim, `CAMP_AIM` appended to `FILES`).
  With A's 15 (`L1B_W2_FIX_A_MUTATIONS`, after `L1B_W2_CROWD_REPLACED`): 606 mutations, every
  text occurring exactly once.

## Gates (my files)

- stylua, selene on StageFlow, LevelGeometry, WaveService: clean.
- luau-lsp analyze (combat sourcemap in my scratch): exit 0, no error.
- `py tools/check_compile.py`: PASS (156 files).
- Harness mid-round: my cases and the ui-engineer's 12 all `ok`; 4 of A's SwingGate cases
  failed while A was still working. Green once A finished (final numbers above).
- `check_stage_mirror.py`: `FAIL (3)` on `.plan.tents[1].doors` before econ's mirror, `PASS` at
  the end.

## For the other owner

1. **luau-engineer A, `CrowdService.SpawnResident` (B-4):** an optional start position.

   ```luau
   -- One member of a group, standing on `post` (CampBrain.Posts), or coming out at `from` and
   -- walking to it (a tent's door, B-4): it fights (once its group does) on its group's floor.
   function CrowdService.SpawnResident(
   	kind: string,
   	group: number,
   	post: CampBrain.Post,
   	from: Vector3?
   ): number
   	...
   	local id = CrowdService.Spawn(kind, from or post.at, "fight", post.at, nil, record.floor)
   	...
   	if from ~= nil then
   		-- B-4: shown rising, as a boss's call is (Types.CrowdSpawnInfo.rises).
   		enemy.spawnInfo.rises = true
   	end
   ```

   A resting group walks a member off its post back to it (`CampBrain.Goal`), so nothing else is
   needed for "then walks to its post or into the fight". Harness: a resident spawned with `from`
   stands at `from`, its post is `post`, and at rest it walks to the post; mutation: `from` ignored.
2. **luau-engineer A, `Types.luau` `CrowdSpawnInfo`, and the ui-engineer, `CrowdRenderer`
   (B-4's rise):**

   ```luau
   -- The fix round's B-4: a tent body comes up through the floor at its door as a boss's call
   -- does; nil for every other body.
   rises: boolean?,
   ```

   ui-engineer, `CrowdRenderer` (where a first sighting starts a summoned body's rise):
   `if entity.summonerId ~= 0 then` becomes `if entity.summonerId ~= 0 or entity.rises then`,
   with `entity.rises` set in `spawnEntity` / `onSpawn` from `info.rises == true` (false on a
   fresh or pooled entity), exactly as `summonerId` is passed.
3. **luau-engineer A, `CampBrain.Rouse` + `CrowdService.campStep` (B-3 "at once"):** let a rouse
   bring a group walking home back up (JoinIn already skips home groups itself, so only the
   tent's rouse reaches this):

   ```luau
   -- A wake from outside Step and Release (a tent's rouse, a join-in): a resting or homeward,
   -- unheld group rises. True when it did; anything else is left as it is.
   function CampBrain.Rouse(group: Group, now: number): boolean
   	if group.held or (group.state ~= "rest" and group.state ~= "home") then
   		return false
   	end
   ```

   and in `campStep` the rouse's event names the state it left:

   ```luau
   		if rouse[index] then
   			local before: Types.CampGroupState = brain.state
   			if CampBrain.Rouse(brain, simTime) then
   				queueEvent(index, group, before, "rise", false)
   			end
   		end
   ```

   (`onGroupEvent` alerts only `from == "rest"`, so a home group roused back shows no second
   "!"; the JoinIn branch keeps its literal "rest".) Without this, B-3 still holds with a delay of
   the walk home.
4. **(The economy-designer has done this; kept for the record.) `tools/sim_range.py` and
   `tools/check_stage_mirror.py`, the mirror of B-2 and B-4:**
   - `sim_range.py`, a mirror of `LevelGeometry.TentDoor`:

     ```python
     def tent_door(box, x, z, clear):
         """LevelGeometry.TentDoor (the fix round's B-4): on the line from the marker's centre to
         the post at (x, z), `clear` past the footprint's edge (negative = 0), never past the post."""
         dx, dz = x - box["x"], z - box["z"]
         distance = math.sqrt(dx * dx + dz * dz)
         if not distance > 1e-6:
             return x, z
         ux, uz = dx / distance, dz / distance
         edge = math.inf
         if abs(ux) > 1e-9:
             edge = min(edge, box["sx"] / 2 / abs(ux))
         if abs(uz) > 1e-9:
             edge = min(edge, box["sz"] / 2 / abs(uz))
         out = min(edge + max(clear, 0), distance)
         return box["x"] + ux * out, box["z"] + uz * out
     ```

   - `tents_of(level, layout, rank, ranks, crowd_kinds=None)`: after `posts = cb_posts(defn,
     len(kinds))`, `doors = []`, and for each `k, post`: `clear = crowd_kinds[kinds[k]]["radius"]
     if crowd_kinds is not None and kinds[k] in crowd_kinds else 0`; `x, z = tent_door(block,
     post["at"][0], post["at"][2], clear)`; `doors.append((x, post["at"][1], z))`; the tent dict
     gains `"doors": doors`. `plan_level` passes its `kinds` as the 5th argument; the Validate
     calls pass none.
   - `check_stage_mirror.py` `tent_row`: add `"doors": [list(d) for d in tent["doors"]]`.
   - Validate's mirror (`sim_range.py` ~5355–5380): run the resident-post and tent-ring loops for
     every distinct rank of `level["difficulties"]`, highest first, each with
     `groups_of(level, layout, rank, ranks)` / `tents_of(level, layout, rank, ranks)`, and skip a
     group id already told of (one problem per group, at the highest rank that fails; texts as
     today). `check_levels.py`'s ring checks already loop every difficulty.
   - The mirror's refusal list could gain "a tent ring only Normal pushes off its floor" (A's tent:
     units fodder 2, brute 2, slinger 2 from Hard; marker at the floor's east edge less 6).

## Decisions the fix list did not take

- B-3 without A's file: a debt (`tent.owed`) re-rouses every tick until the group is up, not one
  rouse at the send; it is dropped the moment the camp has no group up, so a camp that went quiet
  is never woken by its tent.
- B-4: the door's clearance is the body's own kind radius, so a brute rises clear of the wall as
  a fodder does; a door never passes its post (a short ring keeps the post as the spot).
- B-2: Validate's problem texts do not name the difficulty (the harness and the mirror match them
  as they stand); the first failing rank, highest first, is the one reported.
