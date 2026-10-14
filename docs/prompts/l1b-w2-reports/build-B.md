# L1b Wave 2 build — luau-engineer B (the run, the level, the tests)

Status: built; harness green (1,897 checks with A's and my case files). Waiting for A's mutation
list and A's replacements for its four stale mutations, then the full `mutate.py` run. A fresh
agent continues from "Left".

## Done

- `StageFlow.luau`: `Zone.stock`, `Zone.tentStock`, `PlanTent`, `Plan.tents`, `Input.tentLeft`;
  `StageFlow.BossReserve(level, kinds?)`; `Plan`'s 7th argument `kinds`; tents built by one local
  `tentsOf`, read by both Plan and Validate, so they never build a tent differently; population =
  residents + Σ tent stock + the boss room's room + the boss reserve; `levels.populationReserve`
  gone from `NEEDED` and every reader; Validate's new lines (tent `every`, units, a stock on a
  locking camp, no layout block, no residents at a difficulty, layout block finite / sizes /
  radius / centre on floor, ring posts on the floor less the widest kind at the highest
  difficulty, `clearBonus` share in [0, 1], the population at every difficulty); `Advance` holds
  `campClear` while `tentLeft[i] > 0`.
- `Combat.luau`: `ClearBonus`, `DeadFraction`, and a helper `WaveStock` (see Decisions).
- `LevelGeometry.luau`: `TentBox(camp)` and one `Camp_<id>_Tent` piece per layout tent block
  (role `tent`, look `tent`, `collide = false`), after the fire markers.
- `LevelService.luau`: **no change needed.** Every `collide = false` piece already gets
  `CanCollide/CanTouch/CanQuery = false`, and the look comes from `Expeditions.json looks.tent`.
- `WaveService.luau`: `run.tents`, `run.waveStock`, `run.warnedTent`; `placeTents` after
  `placeResidents`; `tickTents` before `advance`; `tentLeft` in the input; the merge test; the
  clear bonus; `StageFlow.Plan(..., Tuning.Get().crowd.kinds)`.
- Harness: `SwingGate` and `SpawnSeed` in `SOURCES`; a `typeof` stub in `wrap` (answers
  `"Vector3"` for the shim, else the interpreter's `typeof`; it changed no existing case);
  `tests_l1b_w2_crowd.luau` (A's) then `tests_l1b_w2.luau` (mine) in `TESTS`.
- `mutate.py`: the Wave 1 mutations my edits made stale are rewritten (below); 26 new
  (`W2_RUN_MUTATIONS`, 24 mine and the ui-engineer's two for `SpawnSeed`); `SwingGate.luau` and
  `SpawnSeed.luau` added to `FILES`. All 26 checked caught in a scratch mutant run (a copy of
  mutate.py's own loop).

Where a tent sends (`WaveService.tickTents`, before `advance` in the tick):

```luau
local residentsAlive = CrowdService.AliveOn(floor) - CrowdService.GroupAlive(tent.group)
local active = CampBrain.TentActive(busy[floor] == true, residentsAlive)
if not CampBrain.TentDue(tent.state, active, now) then
	continue
end
...
local id = if kind ~= nil and post ~= nil
	then CrowdService.SpawnResident(kind, tent.group, post)
	else 0
if id ~= 0 then
	CrowdService.RouseGroup(tent.group)
elseif not run.warnedTent then ... warn once ...
end
CampBrain.TentSent(tent.state, now, planned.every)
tent.sent = following
```

Where the bonus is paid (`WaveService.execute` → `campCleared`):

```luau
-- "open" (the locking camp): zone.stock plus everything its waves queued
local stock = table.clone(zone.stock)
for queuedKind, count in run.waveStock do
	stock[queuedKind] = (stock[queuedKind] or 0) + count
end
campCleared(zone, action.skipped == true, stock)
-- "campClear" (an open camp)
campCleared(cleared, false, cleared.stock)
-- in campCleared, after `if skipped then return end`:
local cash, materials =
	Combat.ClearBonus(stock, level.crowd.rewards, scales.rewardMult, bonus.share)
if cash > 0 or materials > 0 then
	credit({ cash = cash, materials = materials, valor = 0, kills = 0 }, evenTally(), 0)
end
```

`run.waveStock` is emptied on `close`; `queueWave` adds each wave through
`Combat.WaveStock(run.waveStock, spec, if tookElite then elite else nil)`.

## Gates run (on my files)

- stylua, selene: clean on StageFlow, LevelGeometry, WaveService, Combat.
- luau-lsp analyze, combat sourcemap (written to my scratch, not the root): no error in my files;
  the only errors are `CrowdService.luau` (2062, 2063: a `string` where a `CrowdState` is
  expected), A's file. Hub sourcemap: exit 0.
- `py tools/check_compile.py`: PASS (155 files); my files are each under 100 top-level locals.
- Harness: `HARNESS: PASS (1,897 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`.
  The bundle's chunk holds about 101 top-level locals (prelude 3, tests.luau 52, tests_w2 38, one
  table per later file).
- Full `mutate.py`: not yet (see Left).

## Left

- A's mutations and A's four stale ones (`l1b crowd: in play ignores chaseMargin`, `l1b crowd: a
  fire's sitters face away from it`, `l1b crowd: in play has square corners`, `l1b crowd: a group
  walking home engages`): their texts are no longer in CampBrain / CrowdService. Add A's texts
  to `mutate.py` when A hands them over, then run `py tools/crowd_harness/mutate.py . <luau.exe>`
  in full (about 540 mutations, ~30 min), after the harness, never in parallel.

## Decisions the contract did not take

- `BossReserve(level, nil)` counts each boss as 1 (as an unknown kind), 0 with no boss: the
  contract's "nil = a reserve of 1 (the boss)" for a level with a boss. A lob's `count` is not a
  call: only `shape == "summon"` counts.
- `Combat.WaveStock(stock, spec, elite?)` is a new pure helper. WaveService adds each queued
  wave's groups (and the director's elite when it took one) to `run.waveStock` through it, never
  the boss. It gives the mutation "ClearBonus counts the boss" a pure place to live (ClearBonus
  only sees a stock). A group of an unknown kind is counted there though `add` drops it; Validate
  refuses unknown kinds, so the two cannot differ on a valid level.
- `DeadFraction` is handed `queuedAlive` with the grouped bodies already taken out by WaveService,
  so "DeadFraction counts residents" cannot be a mutation of the pure function. Its mutations are
  the clamp under 0 and the nothing-spawned guard; the residents rule is the WaveService line
  `alive - CrowdService.GroupedOn(live.floor)`, read by review.
- A tent whose crowd group was refused (`AddGroup` answered 0) gets `NewTent(0)`: nothing to send,
  so its camp can still clear. A refused body spawn counts as sent (contract) and rouses nothing.
- "A tent stock on a camp with no residents" is judged per difficulty ("on normal camp A has a
  tent stock of 3 and no residents"), since residents can all be `minDifficulty`.
- The real-file cases check the population and Pickets' bonus against a count made in the test
  from the raw JSON, not literals, because the economy-designer is still tuning the stock. On the
  files as of this writing: population Normal 147, Hard 157, Brutal 157 (the draft's numbers);
  Pickets' bonus Normal 1,120 cash / 2 Timber, Hard 3,280 / 6, Brutal 6,560 / 12; Forest Road 82
  Parts with 3 tent markers. The synthetic fixture carries the literal hand-worked numbers
  (74 / 78 / 78; with the real Colossus, Hard 70).

## For the other owner

- **luau-engineer A:** four of A's Wave 1 mutations are stale (texts in "Left"); please hand B
  their replacement texts with A's new mutations. `CrowdService.luau` 2062-2063 fail luau-lsp
  (`string` passed where `CrowdState` is expected; the `refreshInfo` `state` probably needs a
  cast).
- **luau-engineer A / the lead (flaky, not mine):** the timing case "a giant standing far away
  costs the packed crowd nothing" (1.2 ms vs 1.6 ms a step) failed twice in my scratch mutation
  runs while four agents loaded the machine, on mutants that do not touch the crowd. It can make
  `mutate.py`'s baseline fail at random under load.
- **economy-designer, `tools/crowd_harness/stage_mirror.luau`:** `Flow.Plan(...)` takes a 7th
  argument `kinds` (`data.proving.crowd.kinds`) for the boss reserve; without it every boss
  counts 1. `sim_combat.py` may mirror `Combat.WaveStock` if it models C's bonus. Note
  `ClearBonus` rounds with Luau `math.round` (half away from zero), not Python's `round`.
- (Resolved during the build: `check_levels.py` now counts the tent markers, 82 = Pieces.)
- **economy-designer, gate 15:** `tools/check_levels.py` lines 1814 and 1816 still name
  `populationReserve` (a check that it is absent); `rg -n "populationReserve" src tools` then finds
  it. Rewording that check (e.g. building the name from parts, or naming it in a comment-free
  constant elsewhere) is the designer's call; my files no longer name it.

## Wave 1 cases and mutations changed or replaced

Cases:
- `tests_l1.luau`: `L1.rules` loses `populationReserve`; the real-files "Combat.json holds every
  number" list loses `levels.populationReserve`; `L1.real.plan` passes `L1.real.kinds` (as
  WaveService does).
- `tests_l1b.luau`:
  - `L1B.kinds.colossus` gains one summon of 20, so its boss reserve is 21 = Wave 1's
    `populationReserve`; every hand-worked population (68 / 71 / 71) stands. `L1B.plan` passes
    `L1B.kinds`.
  - The fixture's `clearBonus` `{ cash 0, materials 0 }` → `{ share = 0.1 }`.
  - "with no reserve Hard's left side is 50" → "a colossus that calls nobody reserves 1, itself:
    Hard's left side is 51".
  - "Combat.json levels without populationReserve" and "a populationReserve of -1": removed with
    the key (gate 15: the name appears nowhere in `src` or `tools`; I dropped a case that set it to
    99, so the name is not left in the harness either).
  - "a clear bonus of -5 cash" / "with no materials" → "a clear bonus share of -0.1" and "a clear
    bonus of Wave 1's shape (cash and materials, no share)", both "crowd.clearBonus needs a share
    from 0 to 1".
  - "and L1's 73 Parts less 6 per open camp plus one per fire" (`L1_PARTS`) → "and at most
    levels.maxParts, with its two open camps" (L1b-W2-2 drops the formula).
- `tests_l1_world.luau`: unchanged.

Mutations (`mutate.py`):
- `CAMP_CLEAR` is now the five-clause block; "l1b: campClear twice", "... for a zone with no
  residents", "... for the locking zone" each drop their own clause from it (same rules).
- "l1b: countMult applied to residents": anchor `local groups, residents, residentStocks =
  groupsOf(...)` (same rule).
- "l1b: the population gate without the reserve": `return placed + tents + room + reserve` →
  `return placed + tents + room` (the reserve is now the boss reserve; same rule).
- "l1b: Validate lets a post hang its widest kind over the edge": anchored on the resident loop
  (`for index, post in posts :: { CampBrain.Post } do ...`), since the tent loop has the same line;
  the tent's own is "l1b w2: Validate lets a ring post hang its widest kind over the edge".
- "l1b: Validate takes a negative populationReserve" → **replaced** by "l1b w2: Validate takes a
  clear bonus share under 0" (the key is gone; the reserve's rule is held by "l1b w2: BossReserve
  reads the smallest summon" and "... leaves the boss out").
