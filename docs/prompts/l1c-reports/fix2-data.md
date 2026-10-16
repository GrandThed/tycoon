# L1c second fix round: data agent report (2026-10-16)

Worktree `C:\Users\benja\Desktop\tycoon-p5b`, branch `l1c-fix2`. Nothing committed; every file LF.

## Files

- `src/shared/Layouts/Levels/ForestRoad.json`: C's `entry` (313.5, −16) → **(313.5, −23)**, with the route
  point before C's camp leg and the sneak path's last point.
- `tools/sim_range.py`: new `trigger_ceiling(camp, trigger_height)` (mirrors `StageFlow.Ceiling`); plan
  zones carry `"ceiling"`; `LevelFlow.triggered` reads `zone["ceiling"]`. Checkpoints keep `triggerHeight`.
- `tools/check_levels.py`: a new walled-camp rule, "the trigger's ceiling", and a `WALLED_CEILING` switch.
- `tools/check_levels_mutants.py`: 3 new data cases and 2 new stage-mirror cases. The m2 runner is now
  table-driven (`MIRROR_CASES`).
- `docs/BALANCE.md`: a new section, "L1c second fix round", and a "superseded in part" note in "L1c".

## F1 + F3 (mirror of the code agent's rule)

The Python matches the Luau exactly: a locking camp whose `fence.height` is a finite number over
`triggerHeight` uses that height (C: 64); every other camp uses `triggerHeight` (30).
`check_stage_mirror` compares 12 `Ceiling` cases and the zone rows' `ceiling`. Green.

The new `check_levels` rule takes the highest root a player gets in C's fenced rectangle:
- from any standable surface within `stray_reach`, excluding unclimbable walls;
- plus jump 18, double jump 12, the highest ability lift 10 and the root 3.

It requires the ceiling to be at least that root. Result: **64 against 46.5 (C's 3.5 cover), +17.5**. So a
root inside the rectangle has always triggered, and the doorway exemption's "one more step triggers" holds
at every reachable height.

New mutants:
- `WALLED_CEILING` off (C at 30): red.
- Cover 22 high (root 65): red. Over 21 the cover also makes the walls climbable, since 64 = 21 + 43; the
  rule is red either way.
- Control, cover 21 (root 64): green.
- The Python trigger reading `triggerHeight` again: `check_stage_mirror` red ("StageFlow.Advance: scripted
  runs", 12 of 20).
- `trigger_ceiling` ignoring the fence: `check_stage_mirror` red ("StageFlow.Ceiling", 3 of 12).

## F2: data cannot meet "moved under 1 stud"

A root first seen in the trigger rectangle stands in the fence band (z −27 to −26). That is at least 3 studs
outside `inner` (z ≥ −24): fence 1 + `closeInset` 2. The entry must stand inside `inner`, or Plan refuses
the level. So no entry point moves a root on the trigger line by less than 3 studs.

I put the entry at −23: `closeInset` 2 plus `check_levels`' 1-stud `CLOSE_SPARE`. A root on the line z −27
now moves:
- **4.0 studs** in the lane's centre (was 11.0);
- **up to 8.9** at the edge of the 16-wide opening (was 13.6), because the entry is a single point.

Since F1, a root up to 46.5 over the floor in the opening also triggers. The close then puts it on the floor:
**a drop of up to 43.5 studs**.

**The code agent's new `entryTests` case (`worst <= 1`) will therefore stay red on data alone.** Two code
options, for the lead to choose:
- **(a)** At the close, move a fighter who stands in a gate's lane only to the nearest point of `inner`,
  keeping X and the height. That is 3.0 studs straight in on the trigger line, so the 1-stud bound would
  also have to become about 3.
- **(b)** Make a 0 s camp trigger on `inner` itself. Nothing then moves. But the fence band plus the 2-stud
  strip become a 3-stud mouth that does not trigger, so the sight gate's doorway premise must be restated
  for that mouth.

What reads `entry`, re-checked and all green:
- `check_levels`: the entry stands 3 inside the north gate (at most 12) and 3 inside the floor (closeInset
  2 + 1). The nearest spawn is 80 studs away (was 74). The Colossus rises 84 from the entry (was 78; at
  least spawnClear 12). The route is 1,074 studs (band 900–1,100) and the sneak path 1,051. The camp leg
  runs from the entry to the exit.
- `sim_range`: the route index lookup, the close move, N's move and the colossus-alone run all start from
  the entry.
- In the game, N's move and the safe point during C's fight both use the entry, which is now 3 studs inside
  the closed north gate.

## Numbers (moved; BALANCE updated)

- Sight margins are unchanged: eyes **+1.57**, cameras **+2.73** (sightMargin 1.5). The exempt doorway
  glimpse is still −2.53.
- Ambush, with the player put 7 studs nearer the gate:
  - Normal 16.4 / 16.4 / 18.9 s (was 18.4 / 18.4 / 18.7);
  - Hard 19.0 / 19.0 / 21.0 s;
  - Brutal 19.0 / 19.0 / 19.0 s.
- Normal 2 / 2 clear: 5.16 / 4.64 / 5.09 min, mean 4.96. Cash a minute 25,460 / 28,321 / 25,935; Timber a
  minute 40.9 / 45.5 / 41.4.
- R8 on Hard at 2 / 2: LookoutLedge 18,313 against 18,685 cash a minute (**+2.0%**, still the thinnest
  gate; was +1.5%). Road2 26.6 against 27.5 Timber a minute (+3.4%).
- `sim_combat` is unchanged: Normal 131,767 cash, bonuses 5.8%, Hard ×2.16.

## Gates

| Gate | Result |
|---|---|
| `py tools/check_levels.py` | CHECK: PASS |
| `py tools/check_levels_mutants.py --luau <main>\tools\bin\luau.exe` | MUTANTS: PASS: shipped data green, 36 data cases, 3 stage-mirror cases |
| `py tools/sim_range.py --levels-only --level forest --check` | CHECK (levels only): PASS (about 6 min) |
| `py tools/check_stage_mirror.py --luau ...` (with the code agent's Ceiling cases) | CHECK: PASS |
| `py tools/sim_combat.py --check` | PASS, 23 of 23 |
