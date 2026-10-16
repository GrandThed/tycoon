# L1b Wave 4 — luau-engineer B (the run): report

Branch `l1b-wave4`, worktree `tycoon-p5`.

## Built

**`src/combat/server/Services/StageFlow.luau`**
- Types: `Zone.stock` is the residents only; `Zone.region: Types.RegionGraph?`, `Zone.approach: Vector3?`;
  `PlanTent.pace: Types.LevelTentPace`; `State.approached: number`; `Input.tentLeft` gone; Action kind
  `"approach"` (with `zone`).
- `regionCells` (a region's cells: its camps' floors in the layout's camp order, then its road cells in file
  order), `regionReach` (widest body and longest reach over the region camps' resident and tent kinds at the
  level's highest difficulty; never throws on broken data), `rectGap` (rectangle-to-rectangle flat gap).
- `regionProblems` (called by `Validate` after `campProblems`): `regions` not a list; a region with no id, a
  duplicate id, a non-finite `y`, no camps; a region camp the layout lacks, a locking one, one in two regions,
  one off the region's `y` (1e-6), one without a finite floor; road cells not a list, a cell with no id, a
  non-finite value, a size ≤ 0, a cell past `WIRE_REACH`; then (cells sound) every `Region.Problems(cells,
  2 × widest + levels.doorSpare)` line prefixed with the region, and the lock clearance (every cell's
  rect-to-rect gap to every locking floor ≥ longest reach + `levels.regionLockMargin`, naming the cell, the
  camp and both numbers).
- `campProblems`: an approach that is not finite / past the wire / on a locking camp; a tent with no `pace`,
  `pace.seconds` not finite or ≤ 0, `pace.lead` not finite or outside [0, 1].
- `NEEDED.rules` gains `regionLockMargin`, `doorSpare`.
- `groupsOf` / `tentsOf` take the cells by camp id and put `region = graph.cells` on every def of a region
  camp; `tentsOf` carries `pace`.
- `Plan`: builds each region once (`Region.Build`), refuses with `(nil, "<level>: region <id>: <line>")` on a
  `Region.Problems` line (defensive), hangs the same graph on A's and B's zones, `zone.stock` = residents,
  `zone.approach` (nil on a locking camp). Population unchanged.
- `Begin`: `approached = 0`. `progress`: the open camp's clear is `aliveByFloor[i] == 0` only.
- `nextApproach` + `Skip "stage"` on the road: the first zone after `approached`, open, with an approach, not
  done, checkpoint not reached, before the armed locking camp → `{ kind = "approach", stage, zone }` and
  `approached = zone`; else Wave 2's `move` + `gate`.
- `StageFlow.Fielded(zone, tent, sent)`.

**`src/combat/server/Services/WaveService.luau`**
- Start: each crowd floor carries `region = zone.region`, each `RunFloor` `cells = zone.region.cells`.
- `tickTents`: `TentClock`, `residentsAlive`, `Ahead`, `TentActive(busy, residentsAlive, ahead)`, then Wave 2's
  executor unchanged. `boot.tentLeft` and the `tentLeft` input are gone.
- `close` also calls `CrowdService.ForgetOthers(zone.floor)`; `approach` moves the fighters to the zone's
  approach (`moveFighters(feet, nil)`; nothing without one); `campClear` pays on `StageFlow.Fielded`.

The lines the contract asks to be quoted:
- where a tent decides to send (WaveService `tickTents`):
  ```luau
  CampBrain.TentClock(tent.state, campBusy, now)
  local residentsAlive = CrowdService.AliveOn(floor) - CrowdService.GroupAlive(tent.group)
  ...
  local ahead = CampBrain.Ahead(residents - residentsAlive, residents, tent.state.busySeconds, planned.pace)
  local active = CampBrain.TentActive(campBusy, residentsAlive, ahead)
  if not CampBrain.TentDue(tent.state, active, now) then
  ```
- where a camp clears (StageFlow `progress`):
  `if zone.locks or zone.residents <= 0 or state.done[index] or byFloor[index] ~= 0 then continue end`
- where the bonus is priced (WaveService `execute`, `campClear`):
  `campCleared(cleared, false, StageFlow.Fielded(cleared, tent, sent))` with `tent` the plan tent of that zone
  and `sent = run.tents[t].sent`; `Fielded` adds `tent.kinds[1 .. min(sent, #kinds)]` to a clone of
  `zone.stock`.

**Harness** (`tools/crowd_harness/`)
- `run_harness.py`: `"Region"` in `SOURCES` right after `HitShapes`; `TESTS` gains `tests_l1b_w4_crowd.luau`
  (A's) then `tests_l1b_w4.luau`. The bundle stays one chunk: about 103 top-level locals of 200 (prelude 3,
  tests.luau 52, tests_w2.luau 38, every later file 1).
- `tests_l1b_w4.luau` (new): Validate (every new refusal on a broken fixture, none on the fixture, the door
  at 4.8 and at spare 0.7, a cycle, a gap, the clearance at 56/55, on a road cell, on a camp floor, on the
  diagonal, at Normal-only 40/39, margin 20; approaches; pace), Plan (one shared graph, A and B defs carry the
  same cells list, C none, the cells' order whatever order the region names its camps, `next`/`hops`,
  `zone.stock`, `approach`, `pace`, population unchanged, a refused region), Fielded (sent 0, 2, 3, past the
  stock, no tent, below 0, a new table, the bonus by hand), Advance (clear at 0 with the stock unsent, never
  twice, no residents never, a skip pays nothing), Skip (approach A, approach B, move + gate; A done; B's
  checkpoint reached; reached passed over; never back; no approach; Wave 2's N; gate/fight/boss as before),
  the shipped Forest Road (Validate clean, the plateau shared, defs, approaches, pace, stock, N from the
  trailhead "approach 1; approach 2; move gate", A done → B).
- Changed cases: listed below.
- `mutate.py`: listed below.

## Changed cases

- `tests_l1.luau`: `L1.rules` gains `regionLockMargin = 8, doorSpare = 0.5` (Validate now requires them).
- `tests_l1b_w2.luau`:
  - `W2B.level()` tents and the two boss-room tent fixtures gain `pace` (Validate requires it).
  - Plan's stock: A `"brute 1, fodder 11"` → `"fodder 9"`; B `"brute 1, fodder 8, slinger 2"` → `"brute 1,
    fodder 5, slinger 2"`; A on Hard `"brute 1, fodder 11, slinger 2"` → `"fodder 9, slinger 1"` (C unchanged).
  - Advance: the seven `tentLeft` cases (held with 2 / 1 left; clears once spent; never twice; B held with its
    stock; B held with a tent body alive; B clears; no `tentLeft` reads 0) → five: A held with a body of its
    floor alive; A clears at 0 with its whole stock unsent; never twice; B held with one tent body alive on the
    road; B clears at 0. The boss-room case keeps its expectation without `tentLeft`.
  - The shipped Pickets' bonus: same arithmetic, now on its residents (label says so).
  - CampAim: the ui-engineer's seven cases replace the twelve (client.md "For other owners").
- `tests_l1.luau` and `tests_l1b.luau`'s real-run and fixture `Skip` cases need no change: their layouts carry
  no approach, so N is Wave 2's there.

## Mutations (`mutate.py`)

- `FILES` gains `src/shared/Region.luau`.
- `CAMP_CLEAR` rewritten as the one-line clear; `"l1b: campClear twice"`, `"... for a zone with no
  residents"`, `"... for the locking zone"` follow it (same labels, same rules).
- `L1B_W4_RUN_REPLACED`: `"l1b: countMult applied to residents"` (new `groupsOf(..., cellsOf)` text).
- Retired, each with the entry holding the new rule:
  - `"l1b w2: campClear with tent stock left"` → `"l1b w4: progress waits for tent stock again"` (taken out
    of `W2_RUN_MUTATIONS`, so gate 17 finds no `tentLeft` in tools);
  - `"l1b w2: a zone's stock without its tent"` → `"l1b w4: zone.stock counts the tent again"`.
- The ui-engineer's: `W2_FIX_UI_MUTATIONS` (six) kept as the never-run record `W2_FIX_UI_REPLACED`, with the
  mapping in its comment; `W4_UI_MUTATIONS` (four, texts as given) added.
- B's new `L1B_W4_RUN_MUTATIONS` (21): progress waits for tent stock again; zone.stock counts the tent again;
  Fielded counts the whole stock; Fielded ignores sent; Plan gives B's zone its own copy of the graph; Plan
  gives each def its own copy of the cells; a locking camp allowed in a region; the lock clearance skipped;
  measured from the floor's centre; its reach at Normal only; doorSpare ignored; a road cell's wire check at
  its centre; a tent without pace passes; a pace lead over 1 passes; an approach on a locking camp passes;
  Plan keeps a locking camp's approach; Skip passes over the open camps (Wave 2's N); Skip takes a done camp;
  Skip takes a camp whose checkpoint was reached; Skip ignores approached; Skip forgets where it stopped.
- Run here with a filter (not the full run): `mutate.py … "l1b w4"` → `MUTATIONS: 25 run, 0 not caught`
  (B's 21 and the ui's 4); `"l1b: campClear"` → 3 run, 0 not caught; `"l1b: countMult applied to residents"`
  → 1 run, 0 not caught.
- A's (crowd_mutations.py, verbatim): `L1B_W4_CROWD_MUTATIONS` (53) and `L1B_W4_CROWD_REPLACED` (15). The
  three retired entries ("home takes damage", "home wakes on a hit", "a hit from out of play lands") are
  deleted from `L1B_CROWD_MUTATIONS` with a comment naming each successor; `L1B_W4_CROWD_RETIRED` stays as
  the record. Every Wave 4 table sits after `L1B_W2_FIX_DIFF_MUTATIONS`, the last earlier table, because the
  replaced tables re-aim labels defined in the Wave 2 tables.
- Totals: 691 mutations, 0 out of date (every text occurs once; checked without running the harness).
  Filtered runs here: A's 53 → 53 run, 0 not caught; A's 15 replaced (by their labels' filters) → 0 not
  caught; the full mutate.py run is QA's.

## Verify

- `stylua --check src`: clean. `selene src`: 0 errors, 1 warning (pre-existing, `src/client/UI/LegacyPanel.luau`
  shadowing, not this wave).
- `luau-lsp analyze` (combat sourcemap, `tools/types/globalTypes.d.luau`) on `src/combat`: no error.
- `py tools/check_compile.py`: `CHECK: PASS -- 157 files compile with Studio settings (-O1 -g2)`.
- `rojo build` of `combat.project.json` and `default.project.json` (to scratch): built.
- Harness: `HARNESS: PASS (2,248 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`.
- Gate 17: `tentLeft|IN_PLAY_STEP|tent_left` in `src` and `tools`: one hit left, in the designer's
  `tools/crowd_harness/mirror_mutants.py:98` (below). Gate 18: no `.inPlay` in `src/combat`.
- Gate 12: `git diff --stat main -- src/server src/client` is empty.
- The WaveService calls A asked me to confirm (`ForgetOthers(floor)`, `TentClock(tent, busy, now)`,
  `Ahead(killed, residents, busySeconds, pace)`, three-argument `TentActive`) match A's committed signatures
  and typecheck. WaveService is not harness-loaded; those lines are read by review, and their rules are A's
  CampBrain cases plus my StageFlow cases.

## For other owners

- **economy-designer:** gate 17 still finds `tentLeft` in `tools/crowd_harness/mirror_mutants.py:98`
  (the mutant "Advance: a campClear with tent stock left", text `or (tentLeft[index] or 0) ~= 0`). That text
  no longer exists in StageFlow; the mirror mutant for the Wave 4 clear could be e.g. replacing
  `byFloor[index] ~= 0 then` with `byFloor[index] ~= 0 or zone.tentStock > 0 then` (the text mutate.py's
  "l1b w4: progress waits for tent stock again" uses).
- **the lead:** `sourcemap.combat.json` is regenerated in the worktree (it now lists `Region`); it is
  nobody's file in the table, so I left it uncommitted.

## Found in the contract

1. **N and a checkpoint reached past an un-approached camp.** By L1b-W4-31 as written ("i > approached",
   not done, not reached), a party that walked past the Pickets to Main Camp's checkpoint without pressing N
   is sent back to the Pickets' approach by its first N, because `approached` is still 0. Implemented as
   written (the case "with A passed and B's checkpoint reached" sets `approached = 1`). If that reads wrong in
   Ben's look, the fix is one clause: skip zones before the furthest reached checkpoint.
2. **"comes before the armed locking camp's zone" with no armed camp:** taken as "no approach" (N then does
   nothing, as Wave 2 did there). It cannot happen on a validated level.
3. **The widest body and longest reach "at the highest difficulty"** are taken over the units fielded at the
   level's own highest rank, so a Hard-only unit counts on a level that offers Hard, and not on one that offers
   Normal alone (a case pins both).
