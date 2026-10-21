# L3 W1, economy-designer report (2026-10-20)

Worktree `tycoon-p5`, branch `l3-armory`. Nothing committed. Full write-up with every table: `docs/BALANCE.md` "L3 W1".

## Two things are red, and both need the lead (neither is data I own)

1. **R8 on Hard: four rows red** in `sim_range --check`. All four are the lookout perch above Pickets:
   - LookoutLedge at T1/T1;
   - LookoutLedge, LookoutSignPad and Secret_lookout with sword T1 and bow T4.

   L3-35 foresaw this. The T1 row was green by 2.5% at hpScale 5.2, and Hard's lower hpScale tips it over. No
   hpScale inside the clock band saves it (probe below). The bow-T4 rows out-earn by x1.8 to x4.4. They are
   structural: a x6.74 bow beats a x1.5 sword from any perch that sees a camp, and the pair player (sword and bow)
   is out-earned too. No layout change was made (L3-35).
   - **Option 1 (data, one line in `sim_range.py`):** extend Ben's Normal known limit to Hard until L4:
     `SNIPER_KNOWN_LIMIT_L4 = {"normal": ("LookoutLedge", "Secret_lookout"), "hard": ("LookoutLedge", "LookoutSignPad", "Secret_lookout")}`.
     The gate already reads the key per difficulty.
   - **Option 2:** re-place the lookout perch now, which is L4's work brought forward.
2. **The climb's minutes: 19.8 min against the 25-40 target (missed; the run count is met).** Assertion 2 of
   `sim_combat --check` is red on this alone. The 31 minutes Ben was quoted counted every run at 5 min. Measured,
   every upgrade shortens the next clear, and Hard at x2.5 buys a T4 in one run.
   - With Hard at x2, the same model gives 6 runs and 24.6 min.
   - The levers are Ben's prices (100 / 250 / 500) and the lead's x2.5, so I changed neither.
   - Simulated clears leave out the lobby, loading and the chest detours: about +0.5 to 1 min a run in real play.

## Files changed

- `src/shared/Config/Armory.json`: `ladder`, `windows`, `legacy`, `power.tierWeight`.
- `src/shared/Config/Combat.json` (`debug`): `provingGear`, `gearPresets`, and the three attributes.
- `src/shared/Config/Expeditions.json`: `found`, 12 entries.
- `src/shared/Config/Levels/1_ForestRoad.json`: recommendedTier 1 / 3 / 5, Hard hpScale 4.25 and rewardMult 2.5,
  both `firstClear` entries.
- `src/shared/Config/Levels/0_RaiderArena.json`: recommendedTier 1.
- `tools/sim_combat.py`:
  - the Armory mirror per L3-5, aligned with A's Armory.luau guard for guard, including `set_tier` and `built_bands`;
  - assertion 1 is now the ladder and assertion 2 the climb;
  - the C1 model keeps its own `c1_*` slot arithmetic;
  - the income gate is retired and assertion 4 is anchored at mid-era;
  - `LEVEL_REWARD_MULT` hard is 2.5;
  - the ladder report replaces the unlock table.
- `tools/sim_range.py`:
  - range body `range_hp`, `gear_max_hp`, `level_view` by tier, `MISSION_GEAR_DEFAULT` T1;
  - the `first_clear` and `first_clear_problems` mirrors (B's five lines, in order);
  - R8's bow-T4 rows and `r8_gate`;
  - the L3-29 clock gate (`L3_CLOCK_SECONDS`);
  - the sniper reach comes from check_levels.
- `tools/check_levels.py`:
  - `ownable_families` (starters + secrets + firstClear), computed before the level-file gates;
  - `sniper_reach` (replaces `longbow_range`);
  - two hint rules;
  - Validate's weapons and starters;
  - presets T1 / T3 / T5, and `DEBUG_UNLOCK_KEYS` gains the three L3-28 keys.
- `tools/check_levels_mutants.py`: 21 new cases and 2 new SIM_CASES.
- `docs/BALANCE.md`: the "L3 W1" section.

## Final values

- **Ladder:** `1.5 x 1.65^(t-1)`, from x1.5 to x20,336.9677.
- **HP:**
  - melee 35 50 80 120 170 250 350 480 700 950 1300 | 1750 2350 3150 4250 5700 7700 10400 14000 19000;
  - ranged 20 30 50 80 110 160 230 320 450 620 850 | 1150 1550 2100 2800 3800 5100 6900 9300 12500;
  - MaxHp 155 / 230 / 380 at T1 / T3 / T5 (31,600 at T20); rangeHp 130.
- **Gear Power:** 64 at T1/T1 (tierWeight 11).
- **Bands:**
  - Forest Timber, then Castle Iron, Underworld Ember, Planet Glowstone, Dream Crystal (the last four are placeholders);
  - costs [100, 100, 250, 500] by position, with T4 / T8 / ... needing the Hard star.
- **Windows:** L3-3 as drawn.
- **Hard's re-measured hpScale: 4.25.** The arithmetic gives 5.2 x 4.0837 / 5 = 4.247.
  - Probe: at 4.45 the clock is +16.8% and at 4.6 +11.9%, and LookoutLedge still out-earns at both.

## Clock table (the reacting player, seeds 11 / 23 / 37)

| | Clears (min) | Mean | Today's | Gate |
|---|---|---|---|---|
| Normal T1 | 5.26 / 4.69 / 5.04 | 5.00 | 5.00 at 2/2 | byte-identical (every row, diffed) |
| Hard T3 | 5.12 / 5.34 / 5.20 | 5.22 | 5.21 at 4/4 | +0.1%, 0 downs |
| Brutal T5 | 5.10 / 5.43 / 5.20 | 5.24 | 5.19 at 6/6 | +1.0%, 0 downs |
| Raider Arena T1 | 10.08 / 10.35 / 11.49 | 10.64 | identical | Colossus 76.8 s, Warlord 97.7 s |

- **Colossus alone:** Hard T3 81.7 s (79.8-83.6; today 81.6), Normal 81.2 s, Brutal 83.8 s.
- **Hard human gate at T1:** a down, x2.38 and x2.46 (needs a down or x1.8); the Colossus is not killed in 240 s.
- **Brutal at T3:** down on every seed.

## Runs for both starters, T1 to T4

| Run | Gear and route | Clear | Bought after |
|---|---|---|---|
| 1 | Normal T1, 211 Timber | 4.99 min | both starters T2, and Double Jump |
| 2 | Normal T2, with the lookout | 3.75 min | sword T3 |
| 3 | Normal T3/T2, Flamethrower into the tunnel, the cache | 2.63 min | bow T3 |
| 4 | Hard T3, tunnel, 539 Timber | 4.84 min | sword T4; the Hard star and the Warhammer |
| 5 | Hard T4/T3 | 3.57 min | bow T4 |

**5 runs, 19.8 min.**
- First clear: 211 Timber (needs at least 200).
- A Hard clear pays 25 Valor; the Brutal first clear pays 25 Valor.
- Hard pays 354,750 cash and 595 Timber (x2.69 / x2.82 of Normal).

## R8 rows

| Row | Result |
|---|---|
| Normal T1/T1 | green (LookoutLedge and Secret_lookout reported, known limit) |
| Normal T1/T4 | green (known two up to x1.37 and x1.66, reported) |
| Hard T1/T1 | **LookoutLedge red** (40.0K / 54.9 against 30.9K / 48.8 on seed 11); every other spot green |
| Hard T1/T4 | **LookoutLedge x3.6, LookoutSignPad x1.8 and Secret_lookout x3.6-4.4 red**; every other spot green |

## Gates (all on the final tree; the long ones run under the launcher's 64-bit 3.12)

| Gate | Result |
|---|---|
| `py tools/check_levels.py` | **PASS** |
| `py tools/sim_range.py --check` | **FAIL (4)**: the four R8 Hard rows above, 545 PASS (14.8 min) |
| `py tools/sim_combat.py --check` | **22 of 23**: assertion 2, the climb's minutes |
| `py tools/sim_combat.py` (the report) | runs clean |
| `py tools/check_stage_mirror.py --luau <main>/tools/bin/luau.exe` | **PASS**, after aligning the mirror and adding `first_clear` |
| `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 <main>/tools/bin/luau.exe` | **PASS**, 3,539 checks, against my data |
| `py tools/sim_economy.py --check` | **PASS** (unchanged) |

**Mutants: filtered runs first, then the full run (its result is the last item).**
- `check_levels_mutants.py --only "L3-"`: 21 of 21 as expected. The rifle-reach case first came out NOT, which
  exposed a real ordering bug: the region rules list the sniper spots before the owned families were computed. That
  is fixed, and the case is re-run ok.
- `--only "L3-29:"` and `--only "L3-26:"` (the two new SIM_CASES): both red as expected, 13.4 min each.
- `--only "W3 L2-5"` and `--only "d-m2"` (the found, shrine-pay and bend cases nearest my changes): **PASS**, 31
  cases. One stage-mirror case was skipped because that run had no `--luau`; it is not one of mine.
- sim_combat's assertions 1 and 2: 20 + 11 hand mutants in a scratch script, all red; the shipped data and a
  six-run climb are green.
- **The full `check_levels_mutants.py --luau <main>/tools/bin/luau.exe` finished after the hand-off: MUTANTS: PASS**,
  256 ok, none NOT, none skipped (131.8 min, started 11:36 on the final tree). Two edits came after it started:
  the removal of dead helpers from sim_combat (only unused definitions deleted) and these report notes. Neither
  changes what the run tested, so the result stands. QA's own full run is still the gate of record.

## Hand-offs (for the other owners)

- **To luau A and B, the three Workspace attribute names** in `Combat.json debug`:
  - `setTierAttribute` = `"DebugSetTier"`;
  - `grantStarAttribute` = `"DebugGrantStar"`;
  - `resetArmoryAttribute` = `"DebugResetArmory"`.
- **To A:**
  - The mirror now follows Armory.luau guard for guard. `check_stage_mirror` passes, including the 20 Problems cases.
  - New Python names: `set_tier`, `built_bands`, `ladder_size`, `window`, `tier_of`, `held_tiers`, `multiplier`,
    `damage_scale(cfg, tier, asc, ability)`, `weapon_hp`, `max_hp`, `range_hp`, `gear_power`, `band_of`,
    `next_tier(cfg, combat, family)`, `tier_cost(cfg, tier)`, `preview`, `upgrade_verdict`, `upgrade`,
    `legacy_refund`, `problems`.
  - Removed: `can_buy`, `tier_unlock_rate` and `band_material`.
  - The top-level `bands` (era bands) stays in Armory.json for the C1 readers and the type.
- **To B:** `sim_range.first_clear` and `first_clear_problems` mirror `StageFlow.FirstClear` and your five Validate
  lines word for word. `check_stage_mirror` compares them (13 + 10 cases, ok). Your relay is included:
  - `starsOf` reads the profile;
  - `GrantStars` / `ForgetStars`;
  - `damageScale` uses the striking family's TierOf;
  - `gearOf` reads the held tiers;
  - `RangeHp`.
- **To the lead:**
  - the two red items above;
  - check_levels' bend gate still reports its known limit: no family that carries can be owned in L3.
