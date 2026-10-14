# L1b Wave 2 review — slice 4, data and tests

Diff `main..f40509a` (branch `l1b-wave2`, worktree `tycoon-p5`). Files: `src/shared/Config/*.json`,
`Layouts/Levels/ForestRoad.json`, `tools/sim_range.py`, `tools/sim_combat.py`, `tools/check_levels.py`,
`tools/check_stage_mirror.py`, `tools/crowd_harness/stage_mirror.luau`, `docs/BALANCE.md` "L1b Wave 2".

Gates run read-only on f40509a, all green: `check_levels.py` CHECK PASS (137 PASS lines; gate 16 prints
147 / 157 / 157, Parts 82, route 1,055, sneak 979 with B.fire1 tightest at +6.1);
`check_stage_mirror.py` CHECK PASS; `sim_combat.py --check` 23 of 23; `sim_range.py --check` CHECK PASS.
Gate 13 diff is empty. Gate 15 finds no `populationReserve`. Every Config and Layout JSON parses.

What I checked and found sound:
- **CrowdRay / RayUpright / FlatToRect.** `hs_ray_upright`, `hs_crowd_ray` and `hs_flat_to_rect` copy
  the Luau line for line: `sphereSpan`, `firstIn`, `earlier`, the cylinder slab, `top = max(h − 2hr,
  h/2 + r)`, and the crit taken unpadded. Both the `"ray"` shape and `path_candidates` build feet as
  `body − body_y`.
- **Tents.** `send_tents` follows `tickTents`:
  - Busy is taken once per tick;
  - `alive_on − own` stands for `AliveOn − GroupAlive`;
  - a refusal still counts as sent;
  - the rouse lands at the next camp step, after `Step`.
- **Join-in.** `cb_join_in` matches JoinIn: breadth first, the waker's own sight, held / home / empty
  groups skipped. Gaps come from post to post, in both directions.
- **Dormancy.** It runs after the step, the join-in and the rouse, as `campStep` orders them.
- **ClearBonus.** `luau_round` rounds half away from zero, like `math.round`.
- **WaveStock.** The sim leaves the elite out. `check_levels` refuses any level file that has an
  `eliteKind`.
- **Population (L1b-W2-5).** I checked the rule against the executor:
  - the boss room's queue is held to `AliveOn(floor) < stage.maxAlive`, residents counted;
  - the Colossus's calls top up to 12;
  - `aliveCount` drops at death (`noteGone`), not when the record is removed;
  - nothing else spawns on the road.

  So 147 / 157 is a true peak bound.
- **Refusals.** I ran all 43 `L1B_REFUSALS` through `sr.level_problems`. Every one is refused, so no
  "refuse alike" comparison passes because both sides missed.
- **Chain table.** It is identical on Normal, Hard and Brutal.
- **The layout against the checklist:**
  - the road through A wakes A.fireN (12.5 studs from the road), and A.fireW joins in;
  - the tents sit 40 or more studs off the road;
  - on the road into B, B.fire1 first sees a root 12 studs past the gate line (x −58), so "turn left
    at once" has room;
  - the sneak passes 54 or more from B.eastWatch and 31 from B.fire2.

## Major

- **`docs/INTERFACES.md:13995-14000` — playtest steps 4 and 5 contradict each other on the shipped
  layout.**
  - Step 4 says "In the next camp, shoot a brute in the head … A plated raider's headshot is yellow
    too". After the Pickets, "the next camp" is the Main Camp.
  - Step 5 then says "Main Camp, the quiet way … Nobody wakes. *Bug: a "!" while you hug the fence*".
  - The Pickets cannot host step 4 on Normal:
    - A holds no plated raider below Hard (`1_ForestRoad.json`: every A `armoured` unit is
      `minDifficulty` hard);
    - its only brutes are the last two tent bodies, which step 3 already had him kill.
  - So Ben must shoot in B. A shot from the road outside B's floor is blocked: no crit number (L1b-7),
    and it still wakes the group. A shot from inside B wakes B.fire1, and B.fire2 joins in (the brutes
    nearest the west gate are B.fire1's 2 brutes and 2 plated).
  - Either way, Main Camp is awake, chasing or walking home, when step 5 asks for a silent pass. That
    is a false "!" bug report, or a skipped headshot test.
  - Fix (the lead's checklist, copied to PLAYTEST by docs-keeper): move step 4 into the Chief's
    Clearing, after the close. On Normal, C has 10 brutes and 2 plated raiders, and the Colossus is
    the headshot Ben's bow question is about. Or put step 4 after step 6, "then wake it".

## Minor

- **`src/shared/Layouts/Levels/ForestRoad.json:255` (C.south) and `:273` (C's tent) — three of C's
  resting guards stand with their centre on the tent marker's wall.**
  - C's tent marker spans x 346.5–360.5, z −6…6, and is opaque Fabric, 10 high.
  - C.south's posts 9–11 are (347.5, 6), (352.5, 6) and (357.5, 6): two lobbers on every difficulty,
    and the plated raider on Hard. Each stands 0.0 studs from the marker, so 1.4–1.7 studs of each
    body is inside the box.
  - Before the close they are seen through the gate half sunk in the tent.
  - `check_levels` checks only a tent's own ring against its marker (`check_levels.py:1414`). The
    resident posts are checked against obstacles only, and the marker is not an obstacle.
  - Fix: move C's tent 2 studs north (z 0 → −2, so the wall stands at z 4 and every body clears it),
    or end the south line at x 342.5. Extend the marker clearance check in `check_wave2` to every
    post of the camp.
- **`tools/check_levels.py:1423` — the "every tent marker is walk-through" line cannot fail.**
  - It tests `camp.tent.collide is not True`, but no layout tent block carries `collide`
    (`LevelTentBlock` has no such field). LevelGeometry decides the flag.
  - The line therefore passes for any layout and proves nothing about the marker. What does guard it
    is B's harness case and mutation, "the tent marker built colliding".
  - Fix: drop the line, or reword it to say the marker is never in `solids_of`, which is what keeps
    it out of the cover and perch gates. Name B's harness case as the real guard.
- **`docs/BALANCE.md:4472` — "39 of 39 Luau mutants caught" cannot be re-run.**
  - The mutant driver is `C:/Users/benja/AppData/Local/Temp/claude/l1b-w2-econ/mirror_mutants.py`
    (`build-econ.md`), outside the repo.
  - Gate 10 says every new comparison is "proved by its mutant", but QA, the next wave and this review
    can only run the comparisons. A later edit that makes a comparison vacuous would go unnoticed.
  - Fix: commit the driver next to `check_stage_mirror.py`, for example
    `tools/crowd_harness/mirror_mutants.py` with its 39 text pairs, and add it to gate 10's command
    list.

## For other slices (one line each)

- **client:**
  - `InputController.campInPlay` (`:1089`) lets phone auto-fire take any drawn body of a camp the
    player is in play for. A phone player on the sneak path inside B auto-shoots a resting resident
    the moment one is in the reticle, so the sneak (Ben §16.3) cannot be done on touch.
  - Separately, a tent body is drawn the instant it spawns on its ring post, 2.9–5 studs from the tent
    wall. There is no rise and no burst, because only `summonerId` bodies rise. Step 3 promises "walks
    out of the tent", and step 1 lists "raiders pop in" as a bug.

Critical 0, Major 1, Minor 3
