# L1b Wave 2 fix round, the tail (B-3 at once, B-4 rising tent bodies)

Status: **done. Every gate is green.** The lead's ruling (i) is built, and with it
`sim_range --check` passes with no data retune. So `1_ForestRoad.json` and `docs/BALANCE.md`
are untouched.

## Round 1 (committed as the WIP 3386d4d): rising tent bodies

- `Types.luau`: `rises: boolean?` on `CrowdSpawnInfo`.
- `CrowdService.SpawnResident(kind: string, group: number, post: CampBrain.Post, from: Vector3?): number`:
  - spawns at `from or post.at`; `post` stays the resident's post (its anchor);
  - sets `spawnInfo.rises = true` when `from` is given;
  - `flushLifecycle` clears `rises` right after `fireAll`, so the rise is shown once. A late
    joiner or a re-announce sees the body standing.
- `campStep`: the rouse's event names the state the group left (`before`).
- `WaveService.tickTents`: passes `planned.doors[following]` as `from`.
- `CrowdRenderer`:
  - `Entity.rises`, set by `spawnEntity`'s 6th argument from `info.rises == true`;
  - the first sighting rises on `summonerId ~= 0 or entity.rises`.

## Round 2 (committed as the WIP 5079298): ruling (b)

- `CampBrain.Rouse(group: Group, now: number, inPlay: boolean): boolean`:

  ```luau
  if group.held then
  	return false
  end
  if group.state ~= "rest" and not (group.state == "home" and inPlay) then
  	return false
  end
  ```

  The join-in still uses it, and JoinIn returns resting groups only.
- `sim_range.py`:
  - tent bodies come out at their doors;
  - the tent's rouse debt (`TentOwesRouse`, helpers `tent_owes_rouse` and `group_up`) is now
    mirrored; the sim had never had it.

## Round 3: ruling (i), every rouse a tent causes needs a player in play

- **New pure `CampBrain.TentRouse(group: Group, now: number, inPlay: boolean): boolean`**:

  ```luau
  if not inPlay then
  	return false
  end
  return CampBrain.Rouse(group, now, inPlay)
  ```

  This is where the decision is made. `campStep`'s rouse branch, which serves every
  `RouseGroup` (the rouse at the send and the owed rouse alike), calls
  `CampBrain.TentRouse(brain, simTime, next(brain.inPlay) ~= nil)`. The argument is the
  group's in-play set from this step's Step, the set engagement reads.
- **Unchanged:** wakes by sight and by a hit go through `Step`; the join-in chain goes through
  `Rouse` and only ever picks resting groups. The owed debt in `WaveService` is unchanged: it
  keeps calling `RouseGroup` each tick while the camp is busy and the group is not up, and the
  rouse acts on the first tick a player is in play.
- **Comments rewritten:** StageFlow's `TentOwesRouse`, WaveService's `tickTents`, and
  CrowdService's `RouseGroup` and campStep.
- **`sim_range.py`:** new `cb_tent_rouse(group, now, in_play)`. The sim's rouse executor
  (`rouse_pending`) uses it. Its `send_tents` docstring is updated.
- **`check_stage_mirror.py` + `stage_mirror.luau`:**
  - `TentRouse` added to the `CampBrain` list of functions the mirror must find;
  - new op `tentRouse`, run for every state × held × `playerInPlay` (10 cases), beside Rouse's 10.
- **Harness, `tests_l1b_w2_crowd.luau`:**
  - **Pure `CampBrain.TentRouse` cases:**
    - rest, nobody in play: nothing;
    - rest, a player in play: rise (since now, hit cleared);
    - home, nobody in play: nothing;
    - home, a player in play: rise;
    - held: nothing;
    - fight: nothing.
  - **CrowdService:** a resting patrol with nobody in play is not roused by `RouseGroup` (no
    event). A lever hit then wakes it, so sight and hits are untouched. The two home cases from
    round 2 follow.
  - **The `resting` group:** it used `RouseGroup` as a wake lever with nobody in play, which the
    ruling now makes a no-op. It wakes its group with a lever hit (`Crowd.Damage(id, 1, 0)`)
    instead; same assertions.
  - **The join-in group's tent cases:** unchanged; the root is inside the camp, so a player is
    in play.
- **Mutations, `mutate.py`:**
  - Two re-aimed at the new call (same labels and rules): "the tent's rouse is told a player is
    always in play" and "… nobody is ever in play".
  - New:
    - "TentRouse with nobody in play rouses";
    - "TentRouse never lifts a homeward group";
    - "the tent's rouse is a plain Rouse".
  - None deleted.
- **`mirror_mutants.py`:** new "TentRouse with nobody in play rouses" and "TentRouse never lifts
  a homeward group".

## Balance (step 2)

`sim_range --check` passes with no retune.
- Timber a minute on Normal at 2/2, seeds 11 / 23 / 37: **40.7 / 39.2 / 40.3**. The floor is
  37.8; HEAD read 39.3 / 40.2 / 38.9.
- Seed 11 clears in 6.93 min with 2 leashes. Under (b) it took 7.74 min with 9: ruling (i) ended
  the tent's rest → rise → leash cycles.
- No change to `Config/Levels/1_ForestRoad.json` or `docs/BALANCE.md`.

## Gates (final state, run one after the other)

- stylua (format + `--check`) on Types, CrowdService, CampBrain, WaveService, StageFlow and
  CrowdRenderer: clean. selene: 0 errors, 0 warnings.
- luau-lsp analyze, combat sourcemap (`src/combat` + `src/shared`): 0 errors. Default sourcemap
  on `Types.luau`: 0 errors.
- check_compile: `CHECK: PASS -- 156 files compile with Studio settings (-O1 -g2)`
- harness: **`HARNESS: PASS (1,995 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`**
- mutate: **`MUTATIONS: 619 run, 0 not caught`** (baseline the same 1,995 PASS)
- check_stage_mirror: `CHECK: PASS`
- sim_range --check: `CHECK: PASS`
- sim_combat --check: `CHECK: PASS -- all twenty-three assertions hold`
- check_levels: `CHECK: PASS`
- mirror_mutants: **`46 of 46 mutants caught`**

## Left over

- Nothing in code. Round 3 is uncommitted, on top of 5079298; I made no git writes.
- Studio:
  - a tent body comes up through the floor at its door and walks to its post, or joins the
    fight; a late joiner sees it standing;
  - a tent never wakes its group while nobody is in that camp;
  - with a player in the camp, a tent group walking home turns back, with no second "!".
