# L1b Wave 4 fix round: luau-engineer B (the run), report

Branch `l1b-wave4`, worktree `tycoon-p5`. Rulings R10, R11, R12, R7's WaveService call, and the
`mutate.py` registration for every owner.

## Commits

| Commit | What |
|---|---|
| `6fe388b` | R10 to R12: StageFlow, WaveService, cases and 5 mutations, with one entry re-aimed |
| `713e6f8` | R13 harness: the ui-engineer's 10 CampAim cases and 6 mutations |
| `b05e5a9` | R7: WaveService `tickTents` / `placeTents` on A's new signatures |
| `8d5a647` | A's R1 to R7 mutations (16) and replaced texts (4); `1c: every ground shape has an under side` retired; `UNDER` dropped |
| `90c211e` | A's R14 mutations (5) and its replaced text (1) |
| `6ffd491` | A's R15 mutations (2) and replaced texts (2); `RING_HEIGHT` dropped |

## Fixes (file : function)

### R10: the safe point judges region zones by position

**`StageFlow.luau` : `SafePoint`**
- The `busy[index]` clause now applies only to a zone with no `region`:
  `local quiet = zone.region ~= nil or busy == nil or busy[index] ~= true`
- A region zone is judged only by the threats' positions.

**`StageFlow.luau` : new `StageFlow.Threatening(state: Types.CampGroupState): boolean`**
- Returns true for rise, fight or home.
- It is pure, so the harness can pin the "home is a threat" rule.

**`WaveService.luau`**
- `run.awakeGroups` is now `{ [number]: boolean }` for rise or fight. Only the tent's owed rouse reads it.
- The new `run.threatGroups: { [number]: { number } }` is set in `onGroupEvent` whenever `StageFlow.Threatening(event.to)`. It holds the ids at the change, and `tickTents` appends each tent body sent into a listed group.
- `threats()` iterates `threatGroups`, so groups walking home are threats.
- I used the group events rather than a crowd query, because CrowdService has no group-state accessor. Every transition is queued as an event, home included, and the `ForgetOthers` sends home too.

### R11: two untested rules

These are cases only; the code is unchanged.
- **The door and lock clearance come from the tent alone.** In the fixture, B's resident brute is removed and B's armoured is moved into A's tent.
- **N stops before the locking camp.** The fixture has a fourth zone D: open, with an approach, after the locking camp C.

### R12: a refused tent spawn is not priced

**`StageFlow.Fielded`** takes an optional fourth argument:
```luau
StageFlow.Fielded(zone: Zone, tent: PlanTent?, sent: number, refused: { [number]: boolean }?): { [string]: number }
```
It skips stock indexes in `refused`. The three-argument calls are unchanged.

**`WaveService.luau`**
- Each tent record gains `refused: { [number]: boolean }`. `tickTents` books a refused spawn there and still moves `sent` on.
- `campClear` passes the record's `refused` to `Fielded`.
- The warning now reads "skipped and not priced".

### R7: the WaveService side

**`tickTents`**
- Reads `CrowdService.Stirred()` once per tick.
- Computes `residentsAlive` before the clock, then calls `CampBrain.TentClock(clock, campBusy, now, stirred[floor] ~= true, residentsAlive)`.
- Then calls `CampBrain.Ahead(clock.residents - residentsAlive, clock.residents, clock.busySeconds, planned.pace)`.

**`placeTents`** calls `CampBrain.NewTent(stock, zone.residents)`.

## Cases (`tests_l1b_w4.luau`, three new groups)

### `safeTests` (R10)
- **(a)** A busy, its group chasing 116 studs off on R2: the safe point is A's checkpoint, not the trailhead.
- A region zone's busy flag alone never refuses its checkpoint.
- A zone with no region keeps the busy rule.
- **(b)** `Threatening` is true for rise, fight and home, and false for rest. Homeward members on A's checkpoint send the player to the start.
- With B's checkpoint reached and B busy far away, the answer is B's checkpoint.

### `untestedTests` (R11)
- A door of 4.8 is refused under 4.9 only through A's tent brute, and passes with no brute anywhere.
- The lock clearance of 48 + 8 = 56 comes only through A's tent armoured.
- With the four-zone fixture, N goes "approach 1; approach 2; move gate", and moves from past B to C's gate.

### `refusedTests` (R12)
- Refusing the second or the third body.
- Nothing refused: both an empty set and nil.
- A refusal past `sent`.
- The bonus by hand: 110.

### Other cases
- `tests_l1b_w2.luau`: the ui-engineer's 10 `CampAim.ShotSpares` cases, verbatim, in the CampAim block.

## Mutations registered (`mutate.py`), filtered runs here

All runs used the filters below; none was a full run. The total is now **724 mutations, 0 out of date** (every text occurs exactly once, checked without running).

### Mine: `L1B_W4_FIX_RUN_MUTATIONS` (5)
- "l1b w4 fix: a region floor judged by its busy flag"
- "... a homeward group is no threat"
- "... regionReach ignores the tent"
- "... N carries the party past the locking camp"
- "... Fielded prices a refused tent spawn"

Run: 5 run, 0 not caught.

### Mine: `L1B_W4_FIX_RUN_REPLACED` (1)
- "l1b: SafePoint returns a busy floor's checkpoint" now has the text `busy == nil or busy[index] ~= true` → `true`.

The filter "SafePoint" ran 7, 0 not caught; "Fielded" ran 3, 0 not caught.

### The ui-engineer's: `W4_FIX_UI_MUTATIONS` (6), verbatim
Run: 6 run, 0 not caught.

### A's, verbatim from `crowd_mutations.py`

| Table | Run | Caught |
|---|---|---|
| `L1B_W4_FIX_CROWD_MUTATIONS` (16) | 16 | all |
| `L1B_W4_FIX_CROWD_REPLACED` (4) | 4 (in two batches, the two "stood-down rusher" entries re-run once A's R14 edit had settled) | all |
| R3's "l1b crowd: a group walking home engages" | 1 | yes |
| `L1B_W4_FIX_CROWD_R14_MUTATIONS` (5) | 5 | all |
| `L1B_W4_FIX_CROWD_R14_REPLACED` (1), "Melee ignores meleeAbove" | 1 | yes |
| `L1B_W4_FIX_CROWD_R15_MUTATIONS` (2) | 2 | all |
| `L1B_W4_FIX_CROWD_R15_REPLACED` (2), "lane/ring: it has no height" | 2 | all |

How the old constants were handled:
- **"1c: every ground shape has an under side"** is deleted, with a comment naming its successor "l1b w4 fix crowd: only a lob has an under side (R6)".
- **"1c: the lob reaches under its floor"** has its text rewritten in place, which let me drop the `UNDER` constant.
- **"ring: it has no height"** is rewritten in place, which let me drop the `RING_HEIGHT` constant.
- **A's REPLACED tables** follow them verbatim; the repeated entries carry identical values.
- **A's R15 table** has its redundant `FIELD =` line left out, because `mutate.py` already defines `FIELD` with the same path.

## Verify (final tree, `6ffd491`)

- `stylua --check src`: clean.
- `selene src`: 0 errors, 1 warning (the old `LegacyPanel.luau` shadowing, not this round's).
- `luau-lsp analyze` (combat sourcemap, `tools/types/globalTypes.d.luau`) on `src/combat`: no diagnostics.
- `py tools/check_compile.py`: `CHECK: PASS -- 157 files compile with Studio settings (-O1 -g2)`.
- Harness: `HARNESS: PASS (2,337 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`. This includes the lead's `tests_w2` (cef3d38) and `tests_s2` (de66b13) updates for R6 and R15.

## For other owners

### Economy-designer
- **R12.** `sim_range.py`'s tent executor must stop pricing a refused spawn, as the ruling says. Mirror it as a `refused` set that `fielded` skips; `sent` still moves on.
- **The mirror check.** `check_stage_mirror.py` calls `Fielded` with three arguments, which is still valid. A case with `refused` would cover the new argument.
- **R10.** If the simulator mirrors `SafePoint`, it needs both changes:
  - region zones ignore `busy`;
  - threats include groups walking home.

### The lead
`WaveService` is not loaded by the harness, so these lines are covered by review only:
- `threatGroups`, kept from group events;
- the `refused` booking;
- R7's `Stirred` call.

Their rules are pinned in the pure modules: StageFlow's `Threatening` and `Fielded`, and A's `CampBrain` cases.

## Assumptions

- The tent's pace counts residents from `zone.residents` at the start, as A's NewTent comment asks. A resident that the crowd refused at the start would read as an early kill until the first rest restarts the count; that was also true before this round.
- A tent body spawned into a group walking home is added to `threatGroups` at once, as for rise and fight.

## What to check in Studio

- Run out of the Pickets' east gate, wake a group and fall off at the U-bend while it chases: you land at the Pickets' checkpoint, not the trailhead.
- Fall again while the group walks home over that checkpoint: you are not placed among them.
