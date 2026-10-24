# L4 W3 Part B: run cash by era (study)

Ben's ruling (MISSIONS_DESIGN §26.8): *"run cash grows with the city's era: still a fixed amount per kill, multiplied by
the era, set so a clear is worth a few minutes of that era's income; checked against the city's pacing in the
simulator."* Cash only; Timber and Valor unchanged. No Config, simulator or code was changed for this study.

**How the numbers were made.** `py tools/sim_economy.py` and `py tools/sim_combat.py [--check]` on branch `l4-w3`
(both carry `#!/usr/bin/env python`, so **Python 3.12 64-bit**). Scratch scripts in
`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\259ecf10-ad47-49f7-9d11-55e5c7db6b5a\scratchpad\l4-w3-b\`
(no shebang, so **Python 3.14 32-bit**) import `tools/sim_economy.py` unchanged: `curves.py` (the greedy lap's income
series), `runner.py` (a copy of `simulate_era`'s greedy loop with one hook: runs; with no runs it reproduces the four era
times to the second, 2,510 / 6,255 / 16,129 / 33,910 s), `grid.py`, `ceiling.py`, `tables.py`, `md.py` (the tables below),
`sens.py`, `rebirth.py`; outputs `*.out` beside them.

## 1. Today, re-measured

| Forest Road, solo (`sim_combat.py`) | Cash | Timber | Valor | Measured clears (mean) |
|---|---|---|---|---|
| Normal, gear 1/1 | 131,300 (camp bonuses 7,600 = 5.8%) | 211 | 10 | 5:09, 4:36, 4:57 (4:54) |
| Hard, gear 3/3 | 282,400 (x2.15) | 454 | 20 | 5:04, 5:16, 5:03 (5:08) |
| Brutal, gear 5/5 | 564,800 (x4.30) | 906 | 40 | 5:03, 5:16, 5:03 (5:07) |

`sim_combat.py --check` (all eleven PASS) assertion 4 today: *"131,300 cash = 0.92% of 14,280,000 the Village era still
owes at 20:55 (needs <= 25%)"*. The study report's 131,733 (§2) is now 131,300 (W2's Chief).

The greedy lap (`sim_economy.py`: 41:50, 1:44:15, 4:28:49, 9:25:10, all in band; income from `curves.py`):

| Era | Legacy in (x) | 24 slots at baseCost | Income at the first clear (4:54) | 25% | 50% | 75% | last second |
|---|---|---|---|---|---|---|---|
| Village | 0 (x1.00) | 15.0M | 508/s | 8,743/s | 64,490/s | 167,900/s | 698,700/s |
| Boomtown | 78 (x1.78) | 12.8B | 881K/s | 13.2M/s | 34.1M/s | 69.2M/s | 155M/s |
| Metropolis | 261 (x3.61) | 6.40T | 115M/s | 2.67B/s | 6.12B/s | 11.4B/s | 30.7B/s |
| Orbital Colony | 529 (x6.29) | 2.35e15* | 11.5B/s | 465B/s | 1.07T/s | 1.99T/s | 5.35T/s |

*`Format.Cash` shows it as "2.3aa". Inside one era income grows x39 to x127 from the first clear to the middle, and
x4.6 to x11 more by the end: a fixed multiplier per era can make "a few minutes" true at one moment only.

**Two facts that frame every option.**
- The city keeps earning at 100% while the player is in the dungeon (`Combat.json offline.expeditionEfficiency` 1.0), so
  a run adds its clear on top of the city's own income. A clear worth M minutes in a 4.9-minute run adds M / 4.9 to the
  city's pace for those minutes: **at M = 3 that is +61%, and wherever that holds, running is the fastest way to grow.**
- What a run costs the city is purchases delayed by ~5 minutes. Early in an era (the greedy buys every few seconds and
  compounds) that is expensive; late in an era it is almost free. With today's pay, back-to-back runs that buy only
  between runs finish Village 29% later than the city, Boomtown 22%, Metropolis 9%, Orbital 4% (`runner.py`, nonstop).

## 2. The mechanism and how the ratio behaves

Run cash per kill = level pay x `E[era]` x `Combat.CombatCashMult` (Legacy x Founder's, `Combat.luau:223-230`), credited
per member inside `Combat.SplitCarry` (`WaveService.luau:822`, `:826`, `:834`). The city's income is base x EraMult x Legacy x
Founder's x pass x Premium x neighbours (`Economy.luau:211-232`). So, at a given city state:
- **Legacy and Founder's cancel** (the softcap is inside `LegacyMult` on both sides). After a Rebirth the clear is worth
  the same minutes at the same point of an era (`rebirth.py`, lap 2 at legacy 887: Boomtown 25% 0.200 min against lap
  1's 0.198, 50% 0.077 against 0.077; the recommended (c) multipliers). But a reborn city runs each era 2.6 to 9.7 times faster
  (lap 2: Village 4:20, Boomtown 16:54, Metropolis 1:12:12, Orbital 3:39:40) while a clear still takes 5 minutes, so the
  first clear after an Advance lands further into the era and is worth less (Boomtown 0.19 min against 3.0; Metropolis
  0.60 against 2.3; Orbital 0.89 against 1.7) and back-to-back runs fall further behind (Hard: +82%, +14%, +5%). As a
  share of the era's slot cost the clear grows by LegacyMult (Boomtown 7.6% against 1.2%), over a much shorter era.
- **Passes, Premium and neighbours raise the city only** (Double Cash halves every "minutes" figure; all of them together
  divide it by up to 2 x 1.1 x 1.1 x 1.27 = 3.07). So do the city-only perks (Master Builders, Inheritance, Level Floor,
  Extra Milestone). A run never gets relatively stronger for a paying or reborn player.
- `E` must be read per member (each member's own era, inside `mults[userId]`), so a party mixes eras correctly.

## 3. The three anchors (Village is 1 in every option: a brand-new save keeps today's pay)

E_k = M x 60 x income(anchor) / (131,300 x LegacyMult_k), rounded down to two figures (`tables.py`, `md.py`).
- **(a) Start:** M minutes at the moment the first clear after an Advance lands (4:54 into the era). Village needs 0.70
  for M = 3, so its floor of 1 binds (a brand-new save's first clear is 4.3 minutes, as today).
- **(b) Middle:** M minutes at the era's middle second (`reference_second`, the moment assertion 4 already uses). Village
  would need x88 (its first clear would then pay 77% of Village's slots), so it stays at 1.
- **(c) Start, held under the city (judged better):** (a), but never above the **ceiling**: the largest E for which
  back-to-back Normal or Hard runs (buying only at each return, no overhead) never finish the era sooner than the greedy
  city (`ceiling.py`, bisection: Hard binds; Boomtown 1,021, Metropolis 34,320, Orbital 1,498,000; Village 5.76, unused).
  Rejected for (c): the geometric mean of income (reached at 37-41% of each era; first clear 6-32% of the era's slots,
  back-to-back Hard 14-51% faster than the city, `grid.py geo`); 10% or 25% of the era (Hard 11-40% faster past Village,
  `grid.py`); "N% of the next purchase" (the next slot at 5:00 costs 5-19 s of income, `curves.py`: even N = 100% pays
  seconds).

**Multipliers** (Village, Boomtown, Metropolis, Orbital Colony):

| | M = 2 | M = 3 | M = 5 |
|---|---|---|---|
| (a) start | 1, 450, 29,000, 1,600,000 | 1, 670, 43,000, 2,500,000 | 1, 1,100, 72,000, 4,100,000 |
| (b) middle | 1, 17,000, 1,500,000, 150,000,000 | 1, 26,000, 2,300,000, 230,000,000 | 1, 43,000, 3,800,000, 380,000,000 |
| (c) held | 1, 450, 29,000, 1,400,000 | 1, 670, 34,000, 1,400,000 | 1, 1,000, 34,000, 1,400,000 |

## 4. What a Normal clear is worth (M = 3; `md.py`)

Each cell: minutes of the city's income at that moment, then the share of the slot cost still owed before Advance (at
the last second that is the monument). A run's cash a minute against the city's = minutes / 4.9. Hard and Brutal pay
x2.15 and x4.30 of Normal at every point. "One run" = era minutes saved by one Normal run started there (negative =
the city lost more by waiting than the clear paid); "nonstop" = back-to-back runs against the greedy city (negative =
running is faster).

| (a) M=3 | Normal / Hard / Brutal | first clear | 25% | 50% | 75% | last |
|---|---|---|---|---|---|---|
| Village | 131.3K / 282.4K / 564.8K | 4.3 min, 0.88% | 15 s, 0.88% | 2.0 s, 0.92% | 0.8 s, 1.05% | 0.2 s, 5.05% |
| Boomtown | 156.6M / 336.8M / 673.6M | 3.0 min, 1.23% | 12 s, 1.25% | 4.6 s, 1.36% | 2.3 s, 1.76% | 1.0 s, 6.02% |
| Metropolis | 20.4B / 43.8B / 87.7B | 3.0 min, 0.32% | 7.6 s, 0.33% | 3.3 s, 0.34% | 1.8 s, 0.39% | 0.7 s, 1.63% |
| Orbital | 2.06T / 4.44T / 8.88T | 3.0 min, 0.09% | 4.4 s, 0.09% | 1.9 s, 0.09% | 1.0 s, 0.11% | 0.4 s, 0.45% |

One run (min saved) at Advance / 25 / 50 / 75%: Village +1.8 / -1.6 / -0.8 / -0.8; Boomtown +0.9 / 0.0 / 0.0 / -0.4;
Metropolis +0.4 / +0.1 / 0.0 / -0.2; Orbital -0.3 / +0.1 / 0.0 / -0.1. Nonstop Normal / Hard: Village +28.8% / +22.7%;
Boomtown +8.1% / +3.4%; **Metropolis +2.1% / -0.7%; Orbital +0.6% / -1.0%** (Hard runs beat the city by ~1%).

| (b) M=3 | Normal / Hard / Brutal | first clear | 25% | 50% | 75% | last |
|---|---|---|---|---|---|---|
| Village | 131.3K / 282.4K / 564.8K | 4.3 min, 0.88% | 15 s, 0.88% | 2.0 s, 0.92% | 0.8 s, 1.05% | 0.2 s, 5.05% |
| Boomtown | 6.08B / 13.1B / 26.1B | **1.9 h, 47.6%** | 7.7 min, 48.7% | 3.0 min, 52.8% | 1.5 min, 68.3% | 39 s, 234% |
| Metropolis | 1.09T / 2.34T / 4.69T | **2.6 h, 17.0%** | 6.8 min, 17.5% | 3.0 min, 18.4% | 1.6 min, 21.1% | 35 s, 87% |
| Orbital | 190T / 409T / 817T | **4.6 h, 8.1%** | 6.8 min, 8.3% | 3.0 min, 8.7% | 1.6 min, 10.0% | 35 s, 41% |

One run at Advance / 25 / 50 / 75%: Boomtown +18.7 / +5.6 / +2.6 / +0.8; Metropolis +31.1 / +6.4 / +2.8 / +1.2; Orbital
+48.3 / +6.6 / +2.9 / +1.3. Nonstop Normal / Hard: **Boomtown -38.9% / -50.8%; Metropolis -39.8% / -54.2%; Orbital
-41.9% / -56.4%**. A run out-earns the city a minute until 35-36% into each era (25%: x1.4 to x1.6).

| (c) M=3 | Normal / Hard / Brutal | first clear | 25% | 50% | 75% | last |
|---|---|---|---|---|---|---|
| Village | 131.3K / 282.4K / 564.8K | 4.3 min, 0.88% | 15 s, 0.88% | 2.0 s, 0.92% | 0.8 s, 1.05% | 0.2 s, 5.05% |
| Boomtown | 156.6M / 336.8M / 673.6M | 3.0 min, 1.23% | 12 s, 1.25% | 4.6 s, 1.36% | 2.3 s, 1.76% | 1.0 s, 6.02% |
| Metropolis | 16.1B / 34.7B / 69.3B | 2.3 min, 0.25% | 6.0 s, 0.26% | 2.6 s, 0.27% | 1.4 s, 0.31% | 0.5 s, 1.29% |
| Orbital | 1.16T / 2.49T / 4.97T | 1.7 min, 0.05% | 2.5 s, 0.05% | 1.1 s, 0.05% | 0.6 s, 0.06% | 0.2 s, 0.25% |

One run at Advance / 25 / 50 / 75%: Boomtown +0.9 / 0.0 / 0.0 / -0.4; Metropolis -0.2 / 0.0 / 0.0 / -0.2; Orbital
-1.9 / 0.0 / 0.0 / -0.1. Nonstop Normal / Hard: Village +28.8% / +22.7%; Boomtown +8.1% / +3.4%; Metropolis +3.9% /
+1.2%; Orbital +2.3% / +0.8% (never faster).

**M = 2 and M = 5** (first clear -> middle; first clear's share of the era's slots; nonstop Hard; `md.py`):
- (a) M=2: Boomtown 2.0 min -> 3.1 s, 0.82%, +8.3%; Metropolis 2.0 min -> 2.2 s, 0.21%, +1.2%; Orbital 1.9 min -> 1.2 s,
  0.06%, -0.1%. (a) M=5: Boomtown 4.9 min -> 7.5 s, 2.01%, -1.5%; Metropolis 5.0 min -> 5.6 s, 0.53%, -4.5%; Orbital
  4.9 min -> 3.2 s, 0.14%, -3.7%.
- (b) M=2: Boomtown 1.3 h -> 1.9 min, 31.1%, -40.9%; Metropolis 1.7 h -> 1.9 min, 11.1%, -46.5%; Orbital 3.0 h -> 1.9
  min, 5.3%, -47.3%. (b) M=5: Boomtown 3.2 h -> 4.9 min, 78.8%, -60.6%; Metropolis 4.4 h, 28.2%, -63.7%; Orbital 7.5 h,
  13.4%, -65.5%.
- (c) M=2: Boomtown 450 (2.0 min, +8.3%), Metropolis 29,000 (2.0 min, +1.2%), Orbital 1,400,000 (1.7 min, +0.8%).
  (c) M=5 is the bare ceiling: Boomtown 1,000 (4.4 min -> 6.9 s, 1.83%, +3.4%), Metropolis and Orbital as at M=3.

## 5. Constraints

1. **Village >= 1:** every option keeps Village at exactly 1 (today's 4.3-minute first clear of a new save).
2. **Never the fastest way through the city:** (b) fails everywhere past Village (back-to-back runs 39-56% faster, one
   run at Advance saves 19-48 min, the first clear pays 8-48% of the era). (a) fails by ~1% for Hard runs in Metropolis
   and Orbital. (c) holds. Its robustness (`sens.py`, back-to-back Hard against a city that buys only every K s; "+60"
   = a minute of teleport and countdown a run, which the sims cannot measure): K 1 s +3.4 / +1.2 / +0.8%; K 30 s +0.7 /
   +0.2 / +0.4%; K 60 s -2.0 / -0.7 / -0.0%, with +60 s +5.9 / +0.7 / +1.1% (Boomtown / Metropolis /
   Orbital): against a city bought only once a minute, Hard runs with no overhead tie or win by up to 2%; a minute of
   overhead restores the margin. The
   runner buys only at a return, so its era time moves in steps of one run (4.9% of Boomtown, 1.9% of Metropolis, 0.9%
   of Orbital): read every ceiling to one step, which is why (c) takes Boomtown at 670, not the 1,000 ceiling.
3. **Readable:** `Format.Cash` (`Format.luau:25-56`) prints at most four characters plus a suffix, with no upper limit:
   the largest first-lap (c) number is "4.9T" (Orbital Brutal), (b)'s "817T". Every clear is far below 2^53 (9.0e15),
   so whole units stay exact; the wallet's own size is the city's existing limit, not a new one.
4. **sim_combat.py assertions that change** (economy-designer, W3), values for (c) M=3:
   - **4 "cash vs era cost"** becomes every era: a Normal clear x E x the lap's LegacyMult is at most
     `RUN_CASH_CAP_FRACTION` (25%) of what the era still owes at its middle: Village 0.92%, Boomtown 1.36%, Metropolis
     0.27%, Orbital 0.05% ((b) fails: Boomtown 52.8%). Add: the first clear after an Advance is at most 2% of what the
     era still owes when it lands (0.88 / 1.23 / 0.25 / 0.05%; (b) 47.6%).
   - **new "never faster than building":** back-to-back Normal and Hard runs never finish an era before the greedy city:
     Normal +28.8 / +8.1 / +3.9 / +2.3%, Hard +22.7 / +3.4 / +1.2 / +0.8% ((a) fails: Metropolis -0.7%, Orbital -1.0%).
     Needs an optional pause hook in `sim_economy.simulate_era` (default output byte-identical) rather than a copy.
   - **new "a few minutes at the start":** Village E is exactly 1; the first clear after each Advance is worth 1-6
     minutes of that era's income (4.3 / 3.0 / 2.3 / 1.7).
   - **22 split carry:** widen the fuzz's cash multipliers from x1-x2 to era scale (up to 1.4M x 16.19, lap 2 Orbital's
     LegacyMult, about x2.3e7) so the whole-unit carry is proven at the sizes it will meet.
   - The spot check "CombatCashMult at legacy 261 (era 3 entry) -> x3.61" should set era 3: x3.61 x 34,000 = x122,740.
   - Unchanged if the factor is mirrored in `combat_cash_mult` (not in `level_pay`): 1, 2, 5, 6, 12, 13, 20, 21 (its
     131,300 is the base pay), 23; `sim_range.py` (cash a minute is base pay; R8 compares two runs at one multiplier).

## 6. Recommendation

**(c) at M = 3: Village 1, Boomtown 670, Metropolis 34,000, Orbital Colony 1,400,000.** The first clear after an Advance
is worth 4.3 / 3.0 / 2.3 / 1.7 minutes of the new era's income, the end screen's number is the wallet's own scale
(Boomtown +156.6M), and no way of running beats building. The honest cost: the reward fades to seconds of income a
quarter into each era (15 / 12 / 6 / 2.5 s), as Village's does today; a run then neither helps nor hurts the city's lap
(within two minutes either way) and its Timber and Valor are the reason to play. Keeping "a few minutes" true later in
an era (b) is incompatible with "never the fastest way" while the city earns 100% during a run.

**Risks.** Brutal under (c): back-to-back Brutal runs would beat the city by 1.8 / 2.9 / 1.3% (Boomtown / Metropolis /
Orbital; with +60 s, 0.3 / 2.2 / 0.4%; `runner.py`). Brutal needs T5 (Castle gear) by Ben's ruling, but a T4 Brutal
clear is unmeasured; re-run the ceiling with Brutal when T5 exists. Overheads, a real player's buying rhythm and party splits
(L5) are outside the sims.

## 7. Click-question preview for Ben (minutes of the city's income one Normal clear pays)

```
A  3 minutes at the start of each era
              first clear   mid-era   era's end   x per kill
 Village        4.3 min      2.0 s      0.2 s         1
 Boomtown       3.0 min      4.6 s      1.0 s       670
 Metropolis     3.0 min      3.3 s      0.7 s    43,000
 Orbital        3.0 min      1.9 s      0.4 s      2.5M
 Running back to back on Hard: about 1% faster than building in
 Metropolis and Orbital
```
```
B  3 minutes in the middle of each era
              first clear   mid-era   era's end   x per kill
 Village        4.3 min      2.0 s      0.2 s         1
 Boomtown       1.9 h        3.0 min    39 s     26,000
 Metropolis     2.6 h        3.0 min    35 s       2.3M
 Orbital        4.6 h        3.0 min    35 s       230M
 The first Boomtown clear buys 48% of the era's buildings;
 running back to back is 39-56% faster than building
```
```
C  a few minutes at the start, never faster than building   (recommended)
              first clear   mid-era   era's end   x per kill
 Village        4.3 min      2.0 s      0.2 s         1
 Boomtown       3.0 min      4.6 s      1.0 s       670
 Metropolis     2.3 min      2.6 s      0.5 s    34,000
 Orbital        1.7 min      1.1 s      0.2 s      1.4M
 No way of running beats building, on Normal or Hard
```
