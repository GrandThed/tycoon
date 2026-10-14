# L1b Wave 2 fix round, the tail (B-3 at once, B-4 rising tent bodies)

Status: **done in code, harness, mutations and mirrors; one gate red: `sim_range.py --check`
FAIL (1)**, a balance consequence of B-3 "at once" (below). Nothing tuned; that is the lead's
or the economy-designer's call.

## Done

- `src/shared/Types.luau`: `rises: boolean?` on `CrowdSpawnInfo`.
- `CrowdService.SpawnResident(kind: string, group: number, post: CampBrain.Post, from: Vector3?): number`:
  spawns at `from or post.at`; `post` stays the resident's post, which is its anchor (a resting
  group walks a member back to it through `CampBrain.Goal`); sets `spawnInfo.rises = true` when
  `from` is given. `flushLifecycle` clears `rises` on every info in a batch right after
  `fireAll`. `RemoteService.FireClient` is synchronous, so the payload has already been copied.
  The rise therefore shows once, at the first announce. A late joiner's info, or a re-announce,
  shows the body standing.
- `CampBrain.Rouse`: also rises an unheld group that is in `home` (the lead's ruling, B-3 "at
  once"). `JoinIn` still skips homeward groups itself. In `campStep`, the rouse's event now names
  the state the group left (`before`). So a homeward group that is roused back is not
  re-announced (`restChanged` false) and not alerted as a fresh wake (`onGroupEvent` alerts only
  `from == "rest"`).
- `WaveService.tickTents`: `CrowdService.SpawnResident(kind, tent.group, post, planned.doors[following])`.
  Comment updated.
- `CrowdRenderer`:
  - new `Entity.rises` field, false on a fresh entity;
  - `spawnEntity` gains a 6th argument `rises: boolean`, which `onSpawn` fills from
    `info.rises == true`;
  - a re-announce of a body that is already drawn leaves `rises` alone;
  - the first sighting rises on `entity.summonerId ~= 0 or entity.rises`.
- `tools/sim_range.py`: `cb_rouse` mirrors the new Rouse (`state not in ("rest", "home")`). The
  sim's rouse executor notes the state the group left.
- Harness, `tests_l1b_w2_crowd.luau`:
  - The pure Rouse case now expects `home` to rise (since now, hit cleared). Rise and fight are
    still left unchanged.
  - New group "tent door, rouse from home" covers B-4:
    - a resident spawned with `from` stands at its door, not on its post;
    - its first announce carries `rises` true and is off its post;
    - a resident placed on its post never rises;
    - the stored info has no `rises` after the send (the late-joiner and re-announce copy);
    - at rest it walks from the door to within `homeTolerance` of its post.
  - The same group covers B-3: a patrol that walked off its post leashes and goes home, and a
    `RouseGroup` then gives exactly one event, `home` to `rise`, at the next step. The body then
    shows `rise`.
- `mutate.py`:
  - Two texts re-aimed (same labels, same rules): "l1b w2 crowd: Rouse wakes a held group" and
    "l1b w2 crowd: a rouse is never executed".
  - New `L1B_W2_FIX_TAIL_MUTATIONS` (7):
    - SpawnResident ignores `from`;
    - the door taken as its post;
    - a body from its door never rises;
    - every resident rises;
    - the rise is never cleared after the announce;
    - Rouse leaves a homeward group home;
    - a rouse's event says it left rest.
- `mirror_mutants.py`: "Rouse wakes a held group" re-aimed, not deleted. New mutant "Rouse leaves
  a homeward group home".

## Gates (final state, run one after the other)

- stylua (format + `--check`) on the five source files: clean. selene: 0 errors, 0 warnings.
- luau-lsp analyze with `tools/types/globalTypes.d.luau`:
  - combat sourcemap (`src/combat` + `src/shared`): 0 errors;
  - default sourcemap on `Types.luau`: 0 errors. The combat files are not in the default
    sourcemap, so its unknown-require noise on them is expected.
- `py tools/check_compile.py`: `CHECK: PASS -- 156 files compile with Studio settings (-O1 -g2)`
- `run_harness.py`: **`HARNESS: PASS (1,983 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`**
- `mutate.py`: **`MUTATIONS: 613 run, 0 not caught`** (baseline the same 1,983 PASS)
- `check_stage_mirror.py`: `CHECK: PASS`
- `sim_range.py --check`: **`CHECK: FAIL (1)`**:
  `forest, Normal at gear 2/2: seed 37, the clear pays 37.8-46.2 Timber a minute (Wave 1's 42 +-10%): 37.1`.
  HEAD's `sim_range.py` (without the Rouse mirror) passes at 38.9.
- `mirror_mutants.py`: **`43 of 43 mutants caught`**

## Left over / for the lead

1. **The balance cost of B-3 "at once" (the sim_range FAIL).**
   - A tent group that is walking home is now roused back by the next body its tent sends. When
     no player is in play for it, it leashes again and walks home again. While it walks home it
     evades every hit.
   - Normal at 2/2:
     - seed 37: 3 leashes become 5, camp B clears at 255.5 s instead of 233.7 s, and the clear
       takes 7.60 min instead of 7.25;
     - seed 23: 5 leashes become 7, and the clear takes 7.38 min instead of 7.02;
     - Timber a minute becomes 39.3 / 38.2 / 37.1 (was 39.3 / 40.2 / 38.9).
   - Hard at 4/4 adds one leash per seed, with the clear times unchanged.
   - Options:
     - (a) accept, and widen the band or retune the forest (economy-designer);
     - (b) rouse from home only when the camp has a player in play for that group, which needs a
       new ruling;
     - (c) revert to rest-only Rouse. B's `tent.owed` debt still gives "rises once home".
2. **Stale comment, StageFlow (not my file):** `src/combat/server/Services/StageFlow.luau`
   around line 1873, the `TentOwesRouse` comment. Exact diff:
   ```
   --- a/src/combat/server/Services/StageFlow.luau
   +++ b/src/combat/server/Services/StageFlow.luau
   --- The fix round's B-3: whether a tent still owes its group a rouse. A body sent while its camp
   --- fights (a group of its floor in rise or fight) is roused, but a group walking home cannot rise
   --- until it is back (CampBrain.Rouse rises a resting group only), so the executor asks again every
   --- tick until the group is up, or until the camp has nobody up to join.
   +-- The fix round's B-3: whether a tent still owes its group a rouse. A body sent while its camp
   +-- fights (a group of its floor in rise or fight) is roused (CampBrain.Rouse rises a resting or
   +-- homeward group at the next step; a held one never), so the executor asks again every tick
   +-- until the group is up, or until the camp has nobody up to join.
   ```
3. **The sim's tent bodies still spawn on their posts** (`sim_range.py` around line 6289,
   `raise_body(... post["at"] ...)`), not at `tent["doors"]`. That is a 1 to 3 stud difference, it
   does not show in any gate, and it belongs to the economy-designer. The sim's single rouse at
   each send is equivalent to the server's `tent.owed` debt now that Rouse rises from home.
4. Studio: a tent body comes up through the floor at its door (the summoned-body rise and burst),
   then walks to its ring post or joins the fight. A player who joins later sees it standing. A
   tent group that was walking home turns back when its tent sends a body, with no second "!".
