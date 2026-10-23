# L4 W3 review, slice 4: data, simulators and gates

Reviewer: roblox-reviewer (Opus), 2026-10-23. Diff `git diff dce50da..93eb8e9` restricted to `src/shared/Config/`
(`Combat.json`, `Armory.json`, `Expeditions.json`, `Levels/1_ForestRoad.json`, `Missions/` deleted), `tools/sim_combat.py`,
`tools/sim_economy.py`, `tools/check_stage_mirror.py`, `tools/crowd_harness/` (`run_harness.py`, `mutate.py`,
`mirror_mutants.py`, `stage_mirror.luau`, the changed `tests_*.luau`), `docs/BALANCE.md`. Read-only; probes ran on
`git archive` copies of 93eb8e9 and dce50da in the scratchpad's `l4-w3-rev4\` (`tree\`, `base\`, `bite\`, `notep\`,
`probes\`). No `mutate.py` / `mutate_shards.py` run.

Python used for every number: tools with the `#!/usr/bin/env python` line (`sim_combat.py`, `sim_economy.py`,
`check_stage_mirror.py`) and `py -3.12` (`check_levels.py`, my `probes\never_faster*.py`) ran on **3.12 64-bit**;
`run_harness.py`, `mirror_mutants.py` and my `stale.py` / `labels.py` / `mdiff.py` on **3.14 32-bit**.

**Count: 0 Critical, 0 Major, 2 Minor, 4 Suggestions.**

## Minor

### m1. Assertion 24 gates one way of running; BALANCE.md says "no way of running beats building", and the simulator refutes it

- `docs/BALANCE.md:7303` ("a clear is worth a few minutes ... and no way of running beats building") and `:7334`
  ("positive is slower, so running never beats building"); `tools/sim_combat.py:1996-2025` (assertion 24, label
  "24 never faster"). The cash study's click preview C (`docs/prompts/l4-w3-cash-study.md:211`, "No way of running beats
  building, on Normal or Hard") is the text Ben chose on.
- **What is right.** The gate compares like with like for the course it plays: the same `simulate_era` greedy rule on
  both sides, the same `legacy_in`, rebirth count 0, empty shop, no pass; zero teleport and countdown overhead for the
  runner (which favours running, so it is conservative); the city earning at `expeditionEfficiency` 1.0, which the
  assertion also enforces. It does not pass by construction: my bite (Metropolis 43,000, the rest shipped,
  `bite\`, `sim_combat.py --check`, 3.12) fails 24 alone, "Metropolis: hard back to back finishes in 4:26:56, before the
  city's 4:28:49", while 4 and 25 pass. The ruling as MISSIONS_DESIGN §30 records it ("back-to-back runs on Normal or
  Hard never finish an era sooner than building") is exactly what passes.
- **What is wrong.** The runner is one interleaving: back to back from second 0 to the era's end. A player who runs a
  few times right after an Advance and then stays to build finishes **every era sooner than the pure builder**, at the
  shipped multipliers. Probe `probes\never_faster.py <tree>` (the gate's own `run_pause` course, plus "k runs then build
  every second", min over k, and "build, one run at s0, build", min over s0; 3.12, about 6 min):

  | Era | Hard: k runs, then build | Normal: k runs, then build | Hard / Normal: one run at the best moment |
  |---|---|---|---|
  | Village (x1, today's pay) | k=1: 2,340 s vs 2,510 (-6.8%) | k=1: -4.3% | -169 s / -107 s |
  | Boomtown | k=1: 6,104 vs 6,255 (**-2.4%**) | k=1: -0.8% | -151 s / -51 s |
  | Metropolis | k=8: 15,899 vs 16,129 (**-1.4%**) | +0.1% | -133 s / -25 s |
  | Orbital Colony | k=12: 33,729 vs 33,910 (**-0.5%**) | +0.3% | -84 s / -26 s |

  The same probe reproduces the gate's own numbers exactly (+28.84 / +22.71 / +8.11 / +3.41 / +3.90 / +1.21 / +2.31 /
  +0.82%), and the Normal one-run figures equal the study's §4 (c) table ("one run at Advance: Village +1.8, Boomtown
  +0.9 min"), so the study had the fact and the click text dropped it.
- **Why it cannot be gated away.** A free player starts each simulated era with an empty wallet, so a run right after
  an Advance costs almost no purchases and brings back minutes of income while the city earns on at 100%. Any multiplier of at least 1 does this (Village shows it
  at today's pay). It is the "a few minutes at the start" Ben asked for, not a bug in the numbers.
- **The ranking Ben chose on still holds** on the mixed course: option (a) M = 3 (`MULTS=1,670,43000,2500000`,
  `probes\never_faster2.py`) gives Hard k-then-build -2.5% (Metropolis, k=15) and -2.1% (Orbital, k=32), against (c)'s
  -1.4% and -0.5%. So the pick stands; only the sentence is wrong.
- **Failure scenario.** Ben (or W4's publish notes) repeats "no way of running beats building"; a player who runs the
  first 8 Hard clears of each Metropolis era finishes it about 4 minutes sooner than one who never runs, and the
  balance record says that cannot happen.
- **Fix.** (1) Reword `BALANCE.md:7303, :7334` and assertion 24's comment and label to "back-to-back runs never finish
  an era before the greedy city"; add one sentence with the table above (running a few times after an Advance, then
  building, is 0.5-2.4% faster past Village, as Village already is by 4-7% today). (2) Print the "k runs, then build"
  best per era and difficulty as an ungated note line in 24 (its cost is about 2 min of the 5-min `--check`), so the
  honest number stays visible when multipliers move. (3) The lead tells Ben the corrected claim in the W3 report: his
  ruling as recorded holds; the click text's "no way" did not.

### m2. Validate's new `note` line has no Python twin: `check_levels.py` passes a level the game refuses

- `src/combat/server/Services/StageFlow.luau:1066-1084, 1809` (slice 2's code: a `note` that is not a string of 1 to 24
  bytes is a Validate problem, and a Validate problem makes `readLevel` return nil, so the level answers `unavailable`);
  `tools/sim_range.py:5835` (`level_problems`, the Python twin of Validate that `check_levels.py:2063` and
  `check_stage_mirror.py` read) has no `note` rule; `tools/check_stage_mirror.py` adds no "refuse alike" case for it.
  The earlier Validate lines each came with a twin and a broken-once family (ruling 6, L1b, L2-13, L2 W2/W3, L3-17).
- **Probe** (`notep\`: the shipped Brutal note set to "Castle gear and a long note", 27 bytes):
  `py -3.12 tools/check_levels.py` -> **CHECK: PASS** (0 FAIL); `check_stage_mirror.py` -> five DIFF families
  ("the shipped level is playable" 1 of 2, "ruling 6: refused alike" 1 of 48, L2 W2 4 of 21, L2 W3 7 of 18, L3 4 of 13): caught, but
  as "the mirror disagrees", which names neither the note nor the length.
- **Failure scenario.** In the Castle level the designer writes a 30-byte note ("Needs Castle gear (T5+)  "),
  iterates with `check_levels.py`, which is green; the game warns `[WaveService] difficulties.brutal.note ...` and the
  whole level is `unavailable` on every difficulty. Only the mirror run (or the harness's shipped-text pin) shows it,
  as a mirror fault.
- **Fix.** Add the rule to `sim_range.level_problems` (same text, `len(note.encode("utf-8")) > 24`, a non-string, ""),
  and one broken-once case (too long, empty, a number) in check_stage_mirror's ruling-6 family. Also worth the lead's
  ruling for slice 2: a display-only string refusing the whole level is the strictest possible degrade; dropping a bad
  note (the map shows none) would follow "missing data degrades, never errors".

## Suggestions

- **s1.** `tools/crowd_harness/tests_l3.luau:960` "HeldFamily is LoadoutOf's slot, over 36 saved shapes" now compares
  `Armory.HeldFamily` with itself: `Unlocks.LoadoutOf` (`src/shared/Unlocks.luau:247-248`) returns
  `Armory.HeldFamily(...)` for both slots. Before W3 the same loop also compared SavedPower, which was a real second
  reading. HeldFamily's rule is still pinned by `L3.loadoutTests` (explicit pairs, `tests_l3.luau:1470-1525`), so
  nothing is lost; relabel it "LoadoutOf hands out HeldFamily's slots" or drop it.
- **s2.** `tools/crowd_harness/tests_l4w3.luau:462` (slice 1's file, reading this slice's data): "no shipped upcoming
  ability can be bought" and "every shipped upcoming ability names a map node" loop over `upcoming or {}`, so both pass
  when `Expeditions.json abilities.upcoming` is deleted or emptied (no Glide row, no "next: Glide" on the card, §7's
  Valor purpose gone, every gate green). Add `#upcoming >= 1` to the second check.
- **s3.** Text the §6 deletions left behind (no behaviour): `tools/sim_range.py:5731` ("and of Config/Missions"),
  `:5775`, `:10735`, `:10786` (`Armory.HeldTiers`, deleted); `src/shared/Types.luau:976` ("Missions/*.json mirrors",
  slice 1's file); `tools/check_stage_mirror.py:2443` a blank line left inside `armory_cases`' dict where `gearPower` was.
- **s4.** The re-aimed `mutate.py` entry "l3fix2 F1: the dungeon's Snapshot returns before it is sent" now inserts
  `if snapshot.incomePerSecond > 0 then return end`, but the dungeon Snapshot sets `incomePerSecond = 0`
  (`src/combat/server/Main.server.luau:104`), so the mutant can never return at run time. It is still caught, by the
  text pin it exists for (`mainSnapshotExits`, one exit expected), so this is cosmetic; a condition that can be true
  (`if state.combat ~= nil then`) would keep it a real early return.

## Checked and clean

- **Ben's pick in the data:** `Combat.json rewards.eraCashMult = [1, 670, 34000, 1400000]` equals MISSIONS_DESIGN §30 and
  contract §5; `overdrive` and `debug.provingStartDelay` gone; `levels.departCountdownSeconds` 5,
  `debug.fakeDepartAttribute` / `cashEraAttribute` added; `provingAutoStart` true (Studio proving boot only, per the
  designer's relay; slice 2 owns the gate).
- **Mirror placement:** `sim_combat.era_cash_mult` / `combat_cash_mult(state, game, shop, rewards, era)` carry the factor;
  `level_pay` is untouched (not in the diff), `sim_range.py` is untouched. `era_cash_mult` agrees with
  `Combat.EraCashMult` case for case (no block, non-list, empty list, era 0 / negative / fractional / NaN / inf, entries
  under 1, NaN, inf, strings); Python guards `math.floor` behind `_finite`, so NaN and inf never raise.
- **`sim_combat.py --check`** (3.12, 5 min 12 s on `tree\`): PASS, all thirteen; assertion values equal the designer's
  table and the study's (4: 0.92 / 1.36 / 0.27 / 0.05% mid, 0.88 / 1.23 / 0.25 / 0.05% first; 24: +28.8 / +8.1 / +3.9 /
  +2.3% Normal, +22.7 / +3.4 / +1.2 / +0.8% Hard; 25: 4.3 / 3.0 / 2.3 / 1.7 min; 22 at x1 .. x22,663,113; spot check
  x3.61 x 34,000 = x122,740).
- **Assertion 22's new allowance** (`fsum` plus one ulp of (term + 1) per credit) is honest: at x2.3e7 and 116,000-cash
  pools a credit is ~2.6e12, an ulp ~5e-4, sixty of them ~0.03, far under the one unit an over-pay costs. Luau
  `SplitCarry` and Python `split_carry` compute `pool.cash * share * mult + held.cash` in the same order with the same
  `floor(x + 1e-9)`, so the Python proof at era scale carries to the Luau, though check_stage_mirror's SplitCarry
  sequences still use x1-x2 only.
- **`sim_economy.py`:** default output byte-identical to `l4-w3-qa\econ_base.txt` under 3.12 (`cmp`), and also under
  3.14 (head vs base copy, and against the 3.12 baseline); `--check` exit 0. The hook adds `pause=None`, cash lands
  before buying, `skip` blocks only that second's purchases; with `None` the loop is unchanged.
- **check_stage_mirror** (3.12, 9.5 s): PASS; 143 EraCashMult and 120 CombatCashMult cases; `special()` round-trips NaN
  and the infinities. **mirror_mutants `--only L4W3-7`** (3.14, 1 min 42 s): 9 of 9 caught, each with its own DIFF count.
- **Harness check names before and after** (`labels.py` over `run_harness.py` output on `base\` and `tree\`: PASS 4,713
  -> PASS 4,994): 37 labels left. 33 are Gear Power's (GearPower, SavedPower, HeldTiers, tierWeight and the twelve Power
  pins, `hubPower` body, `mainGearOf`, `hubFrozenGear`), all with their rule under L4B-6; "every file of Config/Levels
  and Config/Missions ..." is reworded to Config/Levels; three carry a table address or a scratch path and reappear
  under their new text. No map, secret or stage check was dropped: every `Flow.NodeState / MapState / Award` and
  `S.Sites / MapRow` call now reads `L1.Map.*` with its label unchanged.
- **`mutate.py`:** 2,224 entries, **0 stale** (my exec of the file up to "# Before anything runs", 3.14), no entry with
  old == new, every entry's file in `FILES`. Against dce50da: 22 dropped (all Gear Power: Armory 6, combat Main 7, hub
  EconomyService 9); 21 changed (16 MapRules re-points with identical texts; "MapState passes no rows" and the three
  Award entries re-spelled `MapRules.`; the snapshot entry's condition, s4); 117 new. B's 75 equal
  `luau-b-mutants.py` byte for byte. The `Config/Missions` glob is gone.
- **Deletions (§6):** `git grep` of `missionId|MissionUnlocked|RecommendedPower|GetMission|\boverdrive\b|SummaryCard|
  provingStartDelay|gearPower|SetPower` in `src` is empty; in `tools`, the deleted names (`GearPower`, `SavedPower`,
  `HeldTiers`, `gear_power`, `LADDER_POWER_T1`, `tierWeight`, `MissionConfig`, `Missions/`) appear only in "went in L4
  W3" notes, a test asserting their absence, and s3's comments. No tool reads `Armory.json power` or `Combat.json
  overdrive`.
- **Must not go:** counts in `src` unchanged from dce50da for `MissionRecord` 7, `overdriveBest` 3, `TouchHighestEra` 5,
  `fakeParty` 21, `fakeInvite` 10, `fakeRuns` 15, `MissionCrowd` 24, `SendRunList` 2; `combat.missions` in
  ProfileSchema and Types; `Armory.json legacy` kept. `highestEra` drops 16 -> 13: the three removed are the
  MissionUnlocked gate and its ExpeditionPanel / ExpeditionService readers, which §6 row 3 deletes.
- **Data files:** `Expeditions.json abilities.upcoming` (Glide, `with: "castle"`, a map node), `1_ForestRoad.json
  difficulties.brutal.note` "Castle gear" (11 bytes), `Missions/1_Village.json` deleted. `check_levels.py` (3.12, 29 s)
  PASS, output identical to dce50da's line for line. `sim_combat.py` without `--check` runs clean (exit 0) and prints
  the spot checks: era 1 x1.00, legacy 261 era 3 x122,740, EraCashMult by era 1..5 [1, 670, 34000, 1400000, 1400000],
  no block -> 1.
