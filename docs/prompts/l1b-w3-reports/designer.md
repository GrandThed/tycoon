# L1b Wave 3, the bow: economy-designer report (2026-10-15; final after the amendment and the review)

**What ships: Longbow A 50 → 45 (x0.9, ruling 7) and B 44 → 42 (ruling 10).** With head aim the bow
now takes **x1.084** the sword's time, inside the amended band x1.05–x1.15. Every arrow stays heavy,
and all five commands pass. The first cut (x0.78, A 39 / B 34) was rejected; it is kept below as the
record.

Branch `l1b-wave3` in `C:\Users\benja\Desktop\tycoon-p5`. Files:
- `src/shared/Config/ProvingGrounds.json`: only the two Longbow `damage` values changed.
- `tools/sim_range.py`
- `docs/BALANCE.md`: section "L1b Wave 3: the bow".
- this report.

## How it was measured

New mode: `py tools/sim_range.py --bow` (about 2.5 min, information only, not in `--check`).
- Forest Road, Normal, gear 2 / 2, solo, seeds 11 / 23 / 37, policy `mission`.
- The time runs from the start point to the Colossus's rise, so the boss is excluded.
- Each camp is reported as seconds / hits taken / crits landed.

Two simulator changes, both kept by ruling 8:
1. **A ranged player steps inside a camp's fence before he shoots** (`LevelRun.wanted`,
   `IN_PLAY_STEP`). Before this, the Longbow stood 10 studs outside camp B, where every hit is
   blocked:
   - with body aim it never left camp B;
   - with head aim it read x1.18, but only by luck.

   Against `main`'s simulator, the only `--check` lines this moves are two information rows. No band
   moves.

   The step is a stated simplification (ruling 11). The game counts a player in play within
   `chaseMargin` 2.5 OUTSIDE the floor rectangle; the simulated bow walks 1 stud INSIDE it, so it is a
   little less safe than a real bow.

   It is now pinned by one `--check` expect: on Normal the Longbow alone clears camp B on every seed
   (244 / 229 / 271 s). Without the step it stood off B until the run cap. The pin adds three runs of
   a few seconds each.
2. **Crits are counted** (`World.crits`).

## Before (A 50, B 44)

| Mean time to the boss | Reacting player | Human's reaction (hits per seed) |
|---|---|---|
| Broadsword | 347.5 s (339.3 / 357.7 / 345.5), 0 hits | 327.5 s (11, 12, 10) |
| Longbow, body aim | 360.4 s = x1.037, 0 hits, 21–30 crits | 373.6 s = x1.141 (1, 1, 3) |
| Longbow, head aim | 359.3 s = x1.034, 0 hits, 374–383 crits | 358.0 s = x1.093 (4, 4, 6) |

The per-camp split is in BALANCE. On the clock the bow was even with the sword; its edge was
safety.

## Decision and the sweep (record)

The sweep changes A's damage only, because the simulator fires A. Each cell is the head-aim time
to the boss as a multiple of the sword's:

| A's damage | 50 | **45** | 43 | 42–40 | 39 (x0.78, rejected) | 38 | 35 | 32 |
|---|---|---|---|---|---|---|---|---|
| Head aim | 1.034 | **1.084** | 1.062 | 1.066 | 1.218 | 1.218 | 1.294 | 1.271 |
| Body aim | 1.037 | **1.128** | 1.095 | 1.186 | never clears B | never | never | never |

- Below `heavyHit` 40, a body shot no longer touches a plate and the bow stops interrupting heavy
  windups.
- x0.9 is the largest common cut that keeps a full draw of B heavy: under 0.909, B drops below 40.
- Ruling 10 gives B 2 more points, because damage scales with the draw.
  - B 42 is heavy from charge 0.90. At 40 it was heavy only at a full draw.
  - A 45 is heavy from 0.78.
- The sweep is not monotonic, and the ratio moves about 0.01 between Python 3.12 and 3.14 (x1.092
  on 3.14). That is seed noise, so read the ratio as "about 8%".

**heavyHit is compared with `>=`, so a hit at exactly 40 counts as heavy:**
- `src/combat/server/Services/CrowdService.luau:1926`: `if amount < crowd.heavyHit then return 0, false, "blocked"` (the plate);
- `src/combat/server/Services/CrowdBrain.luau:1006`: `(rule == "heavy" and amount >= heavyHit)` (the interrupt);
- `tools/sim_range.py:1962` and `:2027` mirror both.

## After (A 45, B 42)

The levels never fire B, so these numbers are the same at B 40 and B 42.

Each camp cell: seconds / hits taken / crits landed.

| Weapon, aim | Seed | A | B | C to the boss | To the boss | Colossus in the run |
|---|---|---|---|---|---|---|
| Broadsword | all | unchanged | | | 339.3 / 357.7 / 345.5 | 76.7 / 74.4 / 74.4 |
| Longbow, body | 11 | 63.2 / 0 / 0 | 180.7 / 0 / 16 | 150.6 / 0 / 5 | 394.5 | 132.3 |
| | 23 | 63.2 / 0 / 0 | 166.0 / 0 / 13 | 142.3 / 0 / 7 | 371.4 | 134.4 |
| | 37 | 62.1 / 0 / 0 | 208.9 / 0 / 14 | 138.9 / 0 / 9 | 409.8 | 140.7 |
| Longbow, head | 11 | 57.7 / 0 / 39 | 167.5 / 0 / 146 | 156.4 / 0 / 134 | 381.6 | 96.6 |
| | 23 | 57.6 / 0 / 37 | 156.9 / 0 / 138 | 154.2 / 0 / 126 | 368.8 | 88.2 |
| | 37 | 58.2 / 0 / 37 | 162.4 / 0 / 138 | 159.0 / 0 / 129 | 379.6 | 80.9 |

| Mean time to the boss | Reacting player | Human's reaction (hits per seed) |
|---|---|---|
| Broadsword | 347.5 s | 327.5 s (11, 12, 10) |
| Longbow, body aim | 391.9 s = x1.128 (reported) | 407.7 s = x1.245 (4, 7, 2) |
| Longbow, head aim | **376.6 s = x1.084** (band 1.05–1.15: PASS) | 372.4 s = x1.137 (6, 8, 6) |

**Bosses with the Longbow** (`slay`, no ability, seeds 11 / 23; ruling 4: reported, not tuned):

| Boss, where | Aim | Before (50/44) | After (45/42) | Rejected (39/34) |
|---|---|---|---|---|
| Colossus, range | body / head | 142.8 / 98.2 s | 161.2 / 113.9 s | 223.7 / 152.8 s |
| Warlord, range | body / head | 162.2 / 102.9 s | 182.2 / 116.5 s | 199.3 / 125.7 s |
| Colossus, Raider Arena 2/2 | body / head | 134.9 / 97.6 s | 154.4 / 108.1 s | 220.5 / 163.3 s |
| Warlord, Raider Arena 2/2 | body / head | 154.4 / 105.0 s | 173.8 / 117.6 s | 208.9 / 125.8 s |

- At 45 / 42 the bosses take the bow 11–16% longer.
- No boss lands a hit.
- The Warlord with the Longbow alone still finds a way through with no ground slam (guard down at
  86.6 s, plate broken at 96.1 s).
- Every melee boss band is unchanged.

**The Raider Arena at 2 / 2** is unchanged line for line (all melee):
- the Colossus 76.8 s, the Warlord 97.7 s;
- standing still, down at 11.0–11.1 s;
- clears at 10.19 / 10.35 / 11.97 min with 0 hits;
- worst hit 23.2%.

## Re-banded rows (ruling 5)

**None.** At 45 the Arrow Rain burst measures 4.6 s (was 4.2), inside its default band [3.0, 5.0].
The override table the x0.78 cut needed is removed (review Minor 3).

These rows moved and stayed green:
- Longbow A single / crowd DPS: 48 / 279 → 43 / 251;
- Longbow B: 80 / 182 → 76 / 174 at 42 (73 / 165 at 40);
- the P4 Longbow boss rows.

The plate list is the same as `main`'s.

## Commands (verdict lines; the gate's Python, 64-bit 3.12.10, A 45 / B 42)

| Command | Verdict |
|---|---|
| `py tools/sim_range.py --check` | `CHECK: PASS` |
| `py tools/sim_combat.py --check` | `CHECK: PASS -- all twenty-three assertions hold` |
| `py tools/check_levels.py` | `CHECK: PASS` |
| `py tools/check_stage_mirror.py` | `CHECK: PASS` |
| `py tools/crowd_harness/run_harness.py C:\Users\benja\Desktop\tycoon-p5 C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe` | `HARNESS: PASS (2,004 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)` |
| Gate 13: `git diff main -- src/shared/Config src/shared/Layouts` | only the two Longbow `damage` lines |

`py tools/sim_range.py --bow` was also run on the final tree. It prints the numbers above, and
reads x1.084 against ruling 7's band x1.05–x1.15.

`mutate.py` was not run; QA owns it.

## For the lead

- **Both variants sit near `heavyHit` 40.**
  - B 42 has 2 in hand and is heavy from a 90% draw.
  - A 45 has 5 in hand and is heavy from a 78% draw.

  PLAYTEST should state those draws.
- **Ruling 9:** if Ben still finds the bow stronger, the lever is its safety (range or stand-off),
  not its damage.
- **Nothing is needed from another owner:** no Luau, harness or mirror change.
