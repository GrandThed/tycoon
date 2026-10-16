# L1c third fix round: report (2026-10-16)

Worktree `C:\Users\benja\Desktop\tycoon-p5b`, branch `l1c-fix2`. Nothing is committed; every file is LF;
`tycoon-p5` was not touched (its own mutation run was left alone; only my own PIDs were stopped).

## Files changed

- `src/combat/server/Services/StageFlow.luau`: `GateNudge` rewritten (m3); `Lane`, `Zone.lanes`,
  `StageFlow.Lanes` removed (nothing else read them).
- `src/combat/server/Services/WaveService.luau`: the `moveFighters` comment only (the code already did
  MustEnter, then GateNudge, else the entry).
- `src/shared/Layouts/Levels/ForestRoad.json`: C's `entry` (313.5, −23) → **(309.5, −16)**; the route's
  (313.5, −44), (313.5, −23) → (309.5, −44), (309.5, −16); the sneak path's end → (309.5, −16).
- `tools/sim_range.py`: `gate_nudge` mirrors the new rule; `GATE_SIDES`, `gate_lanes` and the zones'
  `"lanes"` removed.
- `tools/check_stage_mirror.py`, `tools/crowd_harness/stage_mirror.luau`: no `lanes` in the zone rows or
  `NEEDED`; the GateNudge grid now covers the whole fenced rectangle (15 × 15 points: each axis's centre,
  inner's and the fence's edges, the band's middle, half a stud either side of each edge; six heights):
  2,700 cases over the two levels.
- `tools/check_levels.py`: new `NUDGE_CLEAR` 3 and the locking-camp rule "the close's nudge lands clear".
- `tools/check_levels_mutants.py`: m1 re-anchored; 5 data cases and 1 stage-mirror case added.
- `tools/crowd_harness/tests_l1c.luau`: `entryTests` rewritten for the new rule.
- `tools/crowd_harness/mutate.py`: the six lane-specific fix2 entries removed (their text is gone), five
  `l1c fix3` entries added.
- `tools/crowd_harness/mirror_mutants.py`: two lane entries replaced by three `L1c m3` entries.
- `docs/BALANCE.md`: new section "L1c third fix round".

## m1

`check_levels_mutants.py`'s "F1: sim_range's trigger asks triggerHeight again" now anchors on
`self.rules["triggerBelow"] <= above <= zone["ceiling"]` (once in `sim_range.py`, in `LevelFlow.triggered`)
and is caught: check_stage_mirror red, "StageFlow.Advance: scripted runs".

## m3: the nudge onto `inner`

```lua
function StageFlow.GateNudge(zone: Zone, position: Vector3, rules: Types.CombatLevelsConfig): Vector3?
```

- nil when the root's height over the floor is outside `[-triggerBelow, ceiling]`, or the root is outside
  `zone.trigger` (the fenced rectangle): the entry, as before.
- Otherwise the nearest point of `inner`: X and Z each clamped to it, Y kept. At most
  `fenceThickness + closeInset` (3) on an axis, 3√2 at a corner. A root already inside `inner` is
  returned as it is (WaveService only asks for roots MustEnter names).
- WaveService is unchanged: PivotTo by the offset, no `Placed`, ForgetMotion, `entered`.
- `sim_range.gate_nudge` is the line-for-line mirror; `on_close` already used it.

The nudge targets are now the whole perimeter of `inner`. C's two cover blocks are 19.5 or more inside
it, and the new check_levels rule holds every obstacle and tent of a locking camp 3 inside it.

Harness (`l1c fix2 entryTests`, 12 checks):
- a root anywhere on the north trigger line, at 3, 33 and 43, closes the gate in that tick and moves at most
  3 studs straight in;
- every root in the fenced rectangle outside `inner`, all four sides and the corners, on a quarter-stud
  grid across the band (33,984 samples): onto inner's nearest point, height kept, at most 3 on an axis
  (furthest 4.24);
- m2: no nudge lands within 3 studs of the entry (nearest 8.00);
- the reviewer's case: a diagonal dash first sampled in the strip beside the opening (gate edge + 2.1,
  0.4 outside `inner`) is nudged 0.4 onto inner's edge, X and height kept;
- the fence band beside the opening, the fenced corner (onto inner's corner), the east gate (along −X);
- nil over the ceiling, under triggerBelow, and half a stud out on the road past the fence's face, on Z
  and on X.

Mutations (`mutate.py`, `L1C_FIX3_MUTATIONS`), each caught by a named check:
- the fenced-rectangle (depth) test dropped: "half a stud out on the road" and the stage mirror;
- X not clamped; Z not clamped; inner swapped for the floor rect; the height dropped to the floor.
- The fix2 entry "the nudge ignores the height band" is kept (its text still stands).

Mirror mutants (`L1c m3`): the rectangle test dropped, X not clamped, `inner` swapped for the floor rect
(Luau side); `check_levels_mutants` has the Python-side one (`gate_nudge` without its rectangle test:
392 of 2,700 differ).

## m2: C's entry

Every nudge lands on `inner`'s edge (z −24 along the north side, wherever in the opening or beside it), so
the clearance is measured to that whole edge, not one lane width: the entry now stands **8** inside it
(and 4 west of the lane's centre line, 309.5 against 313.5).

New `check_levels` rule (locking camps): "the close's nudge lands clear": the entry and every obstacle and
tent stand `NUDGE_CLEAR` 3 inside the inset rectangle's edge. Shipped: entry 8, nearest cover 19.5.
Mutants: entry at (313.5, −23) red, (309.5, −22) red, (309.5, −21) green; cover at x 358 red, x 357 green.

Why 309.5 and not 317.5 (my first pick): at 317.5 the gate's 64-bit `sim_range --check` turned R8 red on
Hard (seed 11's mission player 26.5 Timber a minute against Road2's 26.6; the 32-bit interpreter passed).
I ran four candidates on the gate's interpreter: (313.5, −16), (313.5, −18) and (309.5, −16) pass (R8
Road2 27.5, 27.5, 27.4), (317.5, −16) fails.

Everything that reads `entry`, re-checked:
- route 1,079 studs (band 900–1,100); every walked leg on the blocks and 12 wide (the diagonal leg from
  (313.5, −44) to an off-centre entry was 10 wide, so the route turns at (309.5, −44));
- sneak path 1,059 studs, on standable ground, clear of every resting group's sight;
- entry 10 inside the north gate (at most 12), in line with its opening;
- nearest spawn 77 studs (needs 12); the Colossus rises 78 from the entry (spawnClear 12);
- Plan accepts it (inside `inner`); sim_range's route lookup, N's move and the colossus-alone run use it.

## Gates

| Gate | Result |
|---|---|
| `run_harness.py <p5b> <main luau>` | **PASS, 2,489 checks** |
| `mutate.py`, every entry in a changed file (StageFlow; WaveService has none) and every `l1c` entry: 236 | **236 run, 0 not caught** (baseline 2,489 checks); the fenced-rectangle mutation is caught by "half a stud out on the road" |
| stale-text count over ALL entries | **mutate.py 787 entries, 0 stale, 0 missing; mirror_mutants 104 entries, 0 stale** |
| `check_levels.py` | CHECK: PASS |
| `check_levels_mutants.py --luau` | MUTANTS: PASS (41 data cases, 4 stage-mirror cases) |
| `check_stage_mirror.py --luau` | CHECK: PASS (GateNudge 2,700 compared) |
| `mirror_mutants.py --only L1c` | **13 of 13 caught** (3 new `L1c m3`) |
| `sim_range.py --check` (full, 64-bit Python 3.12) | CHECK: PASS |
| `sim_combat.py --check` | PASS, 23 of 23 |
| `check_compile.py` | PASS, 159 files |
| `stylua --check` (StageFlow, WaveService, stage_mirror.luau) | clean |
| `selene` (StageFlow, WaveService) | 0 errors, 0 warnings |
| `luau-lsp analyze` (definitions file, `sourcemap.combat.json`) on `src/combat` and `src/shared` | clean |
| `rojo build combat.project.json` (scratch output) | OK |

`tests_l1c.luau` was not stylua-clean at HEAD either (no earlier round formatted it); my block follows
the file's own style. No source file was added or removed, so the sourcemap needs no regeneration.

## Numbers (BALANCE "L1c third fix round")

- Normal ambush 20.0 / 19.6 / 20.1 s; Hard 21.6 / 18.7 / 17.7 s; Brutal 21.6 / 18.7 / 19.9 s.
- Normal 2 / 2 clear 5.26 / 4.69 / 5.04 min; 25,104 / 28,041 / 26,091 cash and 40.1 / 45.0 / 41.9 Timber
  a minute.
- R8 Hard at 2 / 2: Road2 26.6 against 27.4 Timber a minute (+3.0%); LookoutLedge 18,313 against 18,614
  cash a minute (**+1.6%**, still the thinnest gate; it was +2.0%).
- sim_combat: Normal 131,733 cash, bonuses 5.8%, Hard ×2.15, Brutal ×4.32.

## Notes for the lead

- R8's Hard rows remain within a few percent and move with the route's last leg: the entry's X alone
  swung seed 11 by 4%. Any later change to the gatehouse route should be judged on the 64-bit gate run,
  not the 32-bit one (they disagreed here).
- The Village arena's zone also nudges now (it is a locking camp with a 4-stud fence). Its cover is
  frozen and ungated by check_levels; all eight blocks stand in the middle ring, far from the edge, and
  its entry is 41 inside `inner`. I did not add the rule to `check_arena_layout`.
- Two road players still land on one entry point (the reviewer's separate note; out of scope).

## What to check in Studio (`proving.rbxl`, N to the clearing)

1. Dash diagonally through the north gate's edge as it shuts: you go on from just inside, no sideways
   jump, no speed loss, the view does not turn.
2. With two players: one walks through the gate, the other waits on the gatehouse walk; at the close the
   waiting one lands well inside (about 8 studs past the nudge line, 4 west of the gate's centre), not on the other.
3. A jump in the opening still keeps its arc as the gate shuts.
