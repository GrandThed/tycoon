# L1b Wave 3, the bow: economy-designer report (2026-10-15)

I cut the Longbow by x0.78: **A 50 → 39, B 44 → 34**. That puts the head-aim bow at **x1.218** of the
sword, inside ruling 2's band, and all five gates pass. But the band can only be reached by taking
the arrow below `crowd.heavyHit` (40). That changes what the bow is, not just how fast it is (flag 1).

Branch `l1b-wave3` in `C:\Users\benja\Desktop\tycoon-p5`. Files:
- `src/shared/Config/ProvingGrounds.json`: only the two Longbow `damage` values changed.
- `tools/sim_range.py`
- `docs/BALANCE.md`: new section "L1b Wave 3: the bow".
- this report.

## How it was measured

New mode: `py tools/sim_range.py --bow` (about 2.5 min, information only, not in `--check`).
- Forest Road, Normal, gear 2 / 2, solo, seeds 11 / 23 / 37, policy `mission`.
- The time runs from the start point to the Colossus's rise, so the boss is excluded.
- Each camp is reported as seconds / hits taken / crits landed.

Two simulator changes, both in `tools/sim_range.py`:
1. **A ranged player now steps inside a camp's fence before he shoots** (`LevelRun.wanted`,
   `IN_PLAY_STEP`). Before this, the Longbow stood 24 studs off. In camp B that is 10 studs outside
   the fence, where every hit is blocked (L1b-7):
   - with body aim it never left camp B (200 blocked hits, the 25-minute run cap);
   - with head aim it read x1.18, but only by luck.

   Against `main`'s simulator with `main`'s config, the only `--check` lines that move are two
   information rows (Hard and Brutal, the bow alone through camp A: 65–86 s → 61–64 s). No band
   moves.
2. **Crits are counted** (`World.crits`, filled by `hit(..., crit)`).

## Before (A 50, B 44)

Per camp: seconds / hits / crits.

| | A | B | C to the boss | To the boss (mean) | vs the sword |
|---|---|---|---|---|---|
| Broadsword (seeds 11/23/37) | 59.8 / 59.3 / 59.5 s; 0 hits; 0 crits | 154.6 / 173.7 / 163.9; 0; 0 | 124.8 / 124.7 / 122.1; 0; 0 | 339.3 / 357.7 / 345.5 = **347.5 s** | |
| Longbow, body aim | 61.1 ×3; 0; 0 | 122.7 / 180.7 / 216.0; 0; 15 / 17 / 15 | 123.2 / 122.9 / 132.4; 0; 11 / 13 / 6 | 307.0 / 364.6 / 409.5 = 360.4 s | **x1.037** |
| Longbow, head aim | 57.7 / 57.6 / 58.2; 0; 39 / 37 / 37 | 148.6 / 159.0 / 147.7; 0; 133 / 133 / 131 | 147.2 / 153.9 / 148.0; 0; 122 / 127 / 126 | 353.4 / 370.5 / 354.0 = 359.3 s | **x1.034** |

- The reacting player takes 0 hits with either weapon.
- With a human's reaction, the hits taken per seed are:
  - sword: 11 / 12 / 10 (327.5 s);
  - bow, head aim: 4 / 4 / 6 (x1.093);
  - bow, body aim: 1 / 1 / 3 (x1.141).

So on the clock the bow is even with the sword. What it adds is **safety**, about half the hits
taken, and about 375 head crits a run. It also kills the Colossus in the run as fast as the sword:
77–88 s, against 74–77 s.

## Decision

Ruling 3's stop does not apply: the head-aim bow is at x1.034, under 1.10. So I tuned by ruling 1.

The sweep below changes A's damage only, because the simulator fires the default variant, A. Each
cell is the head-aim time to the boss as a multiple of the sword's:

| A | 50 | 45 | 43 | 42 | 41 | 40 | 39 | 38 | 35 | 32 |
|---|---|---|---|---|---|---|---|---|---|---|
| Head aim | 1.034 | 1.084 | 1.062 | 1.066 | 1.066 | 1.066 | **1.218** | 1.218 | 1.294 | 1.271 |
| Body aim | 1.037 | 1.128 | 1.095 | 1.186 | 1.186 | 1.186 | never clears B | never | never | never |

- Between 50 and 40 the time barely moves:
  - the tents set camp A's clear;
  - a head crit still one-shots fodder and slingers;
  - every arrow is still heavy.
- At 39 the arrow drops under `heavyHit` 40, and the time jumps.
- So the smallest cut inside the band is **factor 0.78: A 39, B 34** (34.32 rounded).

## After (A 39, B 34)

| | A | B | C to the boss | To the boss (mean) | vs the sword |
|---|---|---|---|---|---|
| Broadsword | unchanged | | | 347.5 s | |
| Longbow, body aim | 66.4 / 66.3 / 66.3; 0; 0 | **never cleared** (plates ignore body shots under 40) | – | run cap | – |
| Longbow, head aim | 58.7 / 58.7 / 59.6; 0; 44 / 43 / 44 | 187.4 / 186.5 / 185.4; 0; 173 / 171 / 170 | 178.5 / 180.3 / 174.6; 0; 149 / 150 / 147 | 424.6 / 425.4 / 419.5 = 423.2 s | **x1.218** (band 1.10–1.25: PASS) |

- With a human's reaction:
  - bow, head aim: x1.292, hits 7 / 6 / 10;
  - bow, body aim: x2.94, hits 10 / 14 / 11, and seed 37 hit the run cap.
- The Colossus in the run, head aim: 109–117 s (it was 77–88).

**Bosses with the Longbow** (`slay`, no ability, seeds 11 / 23). Ruling 4: reported, not tuned.

| Boss, where | Aim | Before | After | At x0.9 (45 / 40) |
|---|---|---|---|---|
| Colossus, range | body | 142.8 s | 223.7 s | 161.2 s |
| | head | 98.2 s | 152.8 s | 113.9 s |
| Warlord, range | body | 162.2 s | 199.3 s | 182.2 s |
| | head | 102.9 s | 125.7 s | 116.5 s |
| Colossus, Raider Arena 2 / 2 | body | 134.9 s | 220.5 s | 154.4 s |
| | head | 97.6 s | 163.3 s | 108.1 s |
| Warlord, Raider Arena 2 / 2 | body | 154.4 s | 208.9 s | 173.8 s |
| | head | 105.0 s | 125.8 s | 117.6 s |
| Colossus, Forest boss spot | body / head | 133.9 / 95.0 s | 211.6 / 139.1 s | |

- With Arrow Rain: the Colossus goes 110.2 → 154.6 s, the Warlord 150.7 → 181.4 s.
- The Warlord's plate now needs the slam (11 slams, plate phase 16.6 s ≤ 20: PASS).
- Every melee boss band is unchanged.

**The Raider Arena at 2 / 2** is unchanged line for line, because it is all melee:
- the Colossus 76.8 s, the Warlord 97.7 s;
- standing still, down at 11.0–11.1 s;
- clears at 10.19 / 10.35 / 11.97 min with 0 hits;
- worst hit 23.2%.

## Re-banded rows (ruling 5)

| Row | Old value | New value | Old band | New band |
|---|---|---|---|---|
| `arrowRain` burst (seconds of the Longbow's own crowd DPS), `BURST_SECONDS_BY_ABILITY` in `tools/sim_range.py` | 4.2 s | 5.4 s | [3.0, 5.0] | [3.0, 6.0] |

These Longbow rows moved but stayed green, with no re-band:
- Longbow A single / crowd DPS: 48 / 279 → 37 / 218;
- Longbow B: 80 / 182 → 62 / 141;
- the loadout's thinning: 4.8 → 3.8 kills/s;
- the P4 Longbow boss rows (kill times above; still no boss hit lands);
- the plate list, which now includes Longbow A and B.

No non-Longbow row moved.

## Commands (verdict lines)

The gate's Python, 64-bit 3.12.10, on the final tree.

| Command | Verdict |
|---|---|
| `py tools/sim_range.py --check` | `CHECK: PASS`. Before the re-band it was `CHECK: FAIL (1)`, on `arrowRain: burst 5.4 s of crowd DPS in [3.0, 5.0]` |
| `py tools/sim_combat.py --check` | `CHECK: PASS -- all twenty-three assertions hold` |
| `py tools/check_levels.py` | `CHECK: PASS` |
| `py tools/check_stage_mirror.py` | `CHECK: PASS` |
| `py tools/crowd_harness/run_harness.py C:\Users\benja\Desktop\tycoon-p5 C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe` | `HARNESS: PASS (2,004 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)` |
| Gate 13: `git diff main -- src/shared/Config src/shared/Layouts` | only the two Longbow `damage` lines |

`mutate.py` was not run; QA owns it.

## For the lead

1. **The cut crosses `crowd.heavyHit` 40.** That is a change of role, not "a little":
   - **Plates:** a body shot no longer touches a plate.
   - **Interrupts:** the bow no longer stops a heavy windup (brute lane, armoured arc, boss attacks).
   - **Camp B:** the bow alone cannot clear the Main Camp unless it aims at heads.
   - **Bosses:** they take the bow 22–67% longer.
   - **Hard and Brutal:** the bow alone at the proving gear stalls even in camp A on some seeds
     (an information row).
   - **Thresholds:** any common factor under 0.909 takes B under 40, and any under 0.8 takes A
     under 40.

   In play, Ben has the sword on key 1 for plates, so "the sword for plates" may be the intended
   answer. That is your call, and maybe Ben's.
2. **The "a little" alternative is x0.9: A 45, B 40.** It keeps every arrow heavy:
   - head aim x1.084, body aim x1.128;
   - a human x1.137 with head aim, x1.245 with body aim;
   - bosses +11–16%.

   It needs ruling 2's band moved to about x1.08. Swapping is two numbers in
   `ProvingGrounds.json` plus putting `BURST_SECONDS_BY_ABILITY` back to the default band (at 45
   the arrowRain burst should sit near 4.7). I measured it with `--bow --config`; the full
   `--check` was not run at 45 / 40.
3. **What makes the bow feel stronger is safety, not speed.** If Ben still finds it stronger after
   either cut, the lever is the bow's safety (range, or how far it lets him stand), which ruling 1
   does not cover.
4. Nothing is needed from another owner: no Luau, harness or mirror change.
