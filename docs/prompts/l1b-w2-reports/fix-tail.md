# L1b Wave 2 fix round, the tail (B-3 at once, B-4 rising tent bodies)

Status: **done, with the lead's ruling (b) built. One gate is still red:
`sim_range.py --check` FAIL (1).** This time seed 11 fails, not seed 37. The cause is set out
below; it is not the home clause. I tuned nothing.

## Round 1 (committed as the WIP 3386d4d)

- `Types.luau`: `rises: boolean?` on `CrowdSpawnInfo`.
- `CrowdService.SpawnResident(kind: string, group: number, post: CampBrain.Post, from: Vector3?): number`:
  - spawns at `from or post.at`; `post` stays the resident's post (its anchor);
  - sets `spawnInfo.rises = true` when `from` is given;
  - `flushLifecycle` clears `rises` right after `fireAll`, so a rise is shown once, at the first
    announce. A late joiner or a re-announce sees the body standing.
- `campStep`: the rouse's event names the state the group left (`before`). A homeward group
  that is roused is therefore not re-announced, and not alerted as a fresh wake.
- `WaveService.tickTents`: `CrowdService.SpawnResident(kind, tent.group, post, planned.doors[following])`.
- `CrowdRenderer`:
  - `Entity.rises`, false on a fresh entity;
  - `spawnEntity` gains a 6th argument `rises: boolean`, from `info.rises == true`; a
    re-announce leaves it alone;
  - the first sighting rises on `summonerId ~= 0 or entity.rises`.
- Harness, the group "tent door, rouse from home": a body at its door, its first announce rises,
  a post-placed body never rises, the stored info is cleared after the send, and at rest the body
  walks to its post.

## Round 2: the lead's ruling (b)

- **`CampBrain.Rouse(group: Group, now: number, inPlay: boolean): boolean`**. The test is two
  clauses:

  ```luau
  if group.held then
  	return false
  end
  if group.state ~= "rest" and not (group.state == "home" and inPlay) then
  	return false
  end
  ```

  From `rest` it works as before (`inPlay` is ignored). From `home` the group rises only with
  `inPlay`. Held, rise and fight are never roused.
- **`CrowdService`:** both calls pass `next(brain.inPlay) ~= nil`. That is the group's in-play
  set written by this step's `CampBrain.Step` (`CampBrain.InPlay` per target), the same set the
  engagement stamp reads. The tent rouse runs after the Step, so the set is current. The join-in
  passes it too; JoinIn returns only resting groups, so it makes no difference there.
  `RouseGroup`'s comment is updated.
- **`StageFlow.luau`:** the stale `TentOwesRouse` comment is replaced. It now says a homeward
  group rises only while a player is in play for it, and a held one never. **`WaveService`:**
  the comment on `tickTents` is updated the same way.
- **`sim_range.py`:**
  - `cb_rouse(group, now, in_play)` mirrors both clauses. Both callers pass
    `any(group["inPlay"].values())`.
  - **Tent bodies spawn at their doors.** Each tent carries `doors` from the plan; the body comes
    out at its door, its post is still its resident post, and it walks to the post.
  - **The tent's rouse debt (B-3, `StageFlow.TentOwesRouse`) is mirrored.** New helpers
    `tent_owes_rouse` and `group_up` (= `run.awakeGroups[g] ~= nil`: the group is in rise or
    fight and not held). Every tick an owed tent re-rouses its group. At a send, owed =
    `TentOwesRouse(true, busy, up)`. The sim had never mirrored that debt: before, it roused only
    once, at each send.
- **`check_stage_mirror.py` + `stage_mirror.luau`:** the Rouse cases now run every state with
  `playerInPlay` both false and true, so 10 cases instead of 5. The Luau side passes
  `case.playerInPlay == true`.
- **Harness, `tests_l1b_w2_crowd.luau`:**
  - **Pure cases:**
    - rest rises with or without a player in play;
    - held: nothing;
    - rise and fight: nothing either way;
    - **home with nobody in play: nothing**;
    - **home with a player in play: rise** (since now, hit cleared);
    - held and home: nothing.
  - **CrowdService:** a patrol walking home is first sent `RouseGroup` with the root outside the
    camp: **no rise**. Then the root steps into the camp and `RouseGroup` again: **one event,
    `home` to `rise`**, and the body shows rise.
- **Mutations, `mutate.py`:**
  - Re-aimed, same label and rule: "l1b w2 crowd: Rouse wakes a held group" (the held test is
    now its own clause) and "l1b w2 fix tail: Rouse leaves a homeward group home".
  - New:
    - "Rouse lifts a homeward group with nobody in play";
    - "the tent's rouse is told a player is always in play";
    - "the tent's rouse is told nobody is ever in play".
  - The tail's set is 10 mutations in all; nothing deleted.
- **`mirror_mutants.py`:** "Rouse wakes a held group" and "Rouse leaves a homeward group home"
  are re-aimed. New: "Rouse lifts a homeward group with nobody in play".

## Gates (final state, run one after the other)

- stylua (format + `--check`) on Types, CrowdService, CampBrain, WaveService, StageFlow and
  CrowdRenderer: clean. selene: 0 errors, 0 warnings.
- luau-lsp analyze, combat sourcemap (`src/combat` + `src/shared`): 0 errors. Default sourcemap
  on `Types.luau`: 0 errors.
- `check_compile.py`: `CHECK: PASS -- 156 files compile with Studio settings (-O1 -g2)`
- harness: **`HARNESS: PASS (1,987 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`**
- mutate: **`MUTATIONS: 616 run, 0 not caught`** (baseline the same 1,987 PASS)
- `check_stage_mirror.py`: `CHECK: PASS`
- `sim_range.py --check`: **`CHECK: FAIL (1)`**. The failing line:
  `forest, Normal at gear 2/2: seed 11, the clear pays 37.8-46.2 Timber a minute (Wave 1's 42 +-10%): 36.4; cash 22,107 a minute`
- `sim_combat.py --check`: `CHECK: PASS -- all twenty-three assertions hold`
- `check_levels.py`: `CHECK: PASS`
- mirror_mutants: **`44 of 44 mutants caught`**

## The sim_range FAIL: what it is

Timber a minute on Normal at 2/2, seeds 11 / 23 / 37 (band floor 37.8). Each variant was run as a
temporary swap of `sim_range.py`, and the file was restored and checked byte for byte:

| sim variant | 11 | 23 | 37 |
|---|---|---|---|
| HEAD (one rouse per send, rest only, bodies on posts) | 39.3 | 40.2 | 38.9 |
| round 1 (home always) | 39.3 | 38.2 | **37.1** |
| (b) + the debt, bodies on posts | 39.3 | **37.7** | 39.0 |
| (b) + the debt + doors (**as shipped**) | **36.4** | 39.2 | 39.7 |
| as shipped, but the debt pays only with a player in play | **36.4** | 38.2 | 39.7 |

A trace of seed 11's events (`B.tent`) shows where the time goes:
- The tent group is roused **from rest with nobody in play** at each send. That is Wave 2's
  L1b-W2-7 rouse-at-send, which your ruling leaves as it was.
- It rises at 73.1, 88.7, 97.1 and 103.1 s, and leashes 9 to 22 s after each rise. That is four
  rest → rise → fight → home cycles in camp B, between 73 and 125 s.
- HEAD has the same pattern (7 leashes in seed 11). B clears at 272.8 s against 234.7 at HEAD.

**My reading:** the home clause is no longer the cost. The camps run the same ping-pong from
**rest**, and the Normal 2/2 seeds sit just above the floor (38.9 to 40.2 at HEAD), so moving
bodies to their doors pushes one seed under it. Hard and Brutal pass.

Options for you:
- (i) apply the same in-play condition to a tent's rouse from rest. That would be a new ruling
  ("from rest it works as before" would change), and it touches `CampBrain.Rouse`'s rest clause or
  the tent's call;
- (ii) widen or re-centre the band, or retune the forest (economy-designer);
- (iii) accept seed 11 as noise near the edge.

## Left over

- The ruling decision above. Nothing else is left: StageFlow's comment and the sim's doors and
  rouse debt are done.
- Studio:
  - a tent body comes up through the floor at its door, then walks to its post or joins the
    fight; a late joiner sees it standing;
  - a tent group walking home turns back with no second "!", but only while someone is in its
    camp;
  - with nobody in the camp, it carries on home.
