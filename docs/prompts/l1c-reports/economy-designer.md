# L1c economy-designer report (2026-10-16)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1c-chief-clearing`. Nothing committed.

## What changed

- `src/shared/Layouts/Levels/ForestRoad.json` (L1c-2)
  - Camp C moved to (313.5, 12, 31.5), 115 × 115, fence 64. Gates: north at 0 and east at −41.5, both 16 wide.
  - Entry (313.5, −16), exit (361, −10), checkpoint (313.5, −6), spawns as the contract, two 3.5-high covers out of the flank lanes.
  - Spots `ambushW` / `ambushE`: guard, one row at z −22.5, 6 points each, facing ∓98°. The innermost post is 32 studs off the gate's centreline; brutes stand on the outside.
  - Spots `gate`, `chiefFire`, `north`, `south` and C's tent block are deleted.
  - Gatehouse: `GatehouseWalk` and `GatehouseTurn` (paths, top 12) and `GatehouseWallN/S/E/W` (look `wall`, top 76).
    - Deviation: the walls run y 0..76 (block y 38, sy 76) instead of the contract's y 12..76, so no wall floats over the drop. Only the top matters to the rules.
  - `TrailEnd` moved to (379, −10).
  - Route and sneak tails now go through the gatehouse. The route is 1,079 studs and there are 86 Parts.
- `src/shared/Config/Levels/1_ForestRoad.json` (L1c-4, L1c-7)
  - C's residents: `ambushW` and `ambushE` each have **fodder 2 + brute 3**, plus **brute 1 at `minDifficulty` hard**. That is 10 / 12 / 12 (Normal 4 F + 6 B; Hard and Brutal 4 F + 8 B).
  - Stage waves: `[{groups: []}, {groups: [], boss: colossus at [0, 30], valor 10}]`, with breather 3 and maxAlive 42.
  - Colossus cash 29,000 → **41,000** (materials 70 unchanged). `targetMinutes` 6 → **5**.
- `tools/check_levels.py` (L1c-3)
  - `unclimbable()`: a `wall` block or fence whose top is ≥ 43 over every standable top within 46.6 of it. That is jump 18 + double 12 + Leap Smash 10 + step 3. It is exempted from the fence-height rule, the band rule, the beside rule, `sniper_spots` and the perch gate.
  - Beside rule: it now counts only solids within `stray_reach` of the fenced rectangle, and skips path blocks through the camp's own gates (`gate_road`).
  - New `check_walled` gate, with five parts:
    - height ≥ the highest camera + 3 (Theme numbers parsed from `Theme.luau`);
    - the gatehouse walls as tall as the fence;
    - no plated resident;
    - floors (shadow form);
    - sight in plan (exact angular windows through each gate less the wall shadows; eye points on reachable outside tops; camera points whose boom no wall cuts; doorway exemption 2.5).
  - `lockedResidents` (8, 12) at every difficulty, replacing `lockedResidentsMin`.
  - `GatehouseTurn` and `GatehouseWalk` added to the pinned sniper list.
  - The plan legend now shows `-` for N/S gates.
- `tools/sim_range.py`
  - `FOREST_CLEAR_SECONDS` (345, 420) → **(270, 345)**.
  - New `FOREST_AMBUSH_SECONDS` (Normal 15–35, Hard / Brutal ≤ 60), `ambush_seconds()`, a gated check and a printed row.
  - `scene_walls` adds colliding `wall` blocks.
  - `sniper_spots_of` passes movement and ability height.
- `docs/BALANCE.md`
  - New "L1c" section.
  - Seven "Superseded for camp C by L1c" notes on the old L1b lines.

### Why the Normal mix differs from the contract

- The contract's 4 F + 1 B a side clears in 12.0–12.7 s, which is under the lead's 15–35 s band.
- 2 F + 3 B a side clears in 20.4–22.2 s.
- With Colossus 37,000, Normal's cash a minute equals L1b's exactly, but then the R8 row "Hard at the proving gear: LookoutLedge sniper vs mission" fails: 18,313 against 17,921.
- Keeping the lead's 41,000 and the contract's Hard-only brute passes that row by +4.1%. Normal pays +4% a minute over L1b.

## Measured (`py tools/sim_range.py --levels-only --level forest --check`, seeds 11 / 23 / 37)

- **Normal 2/2 clear:** 5.27 / 4.86 / 5.12 min, mean 5.08 (L1b 6.33). Band 4.5–5.75.
- **Cash a minute:** 24,578 / 26,666 / 25,285 (L1b 23.8–25.9k).
- **Timber a minute:** 38.9 / 42.2 / 40.0 (band 37.8–46.2).
- **Pay per clear:** 129,510 cash, 205 Timber, 10 Valor.
- **Ambush (close to last ambusher down):**
  - Normal 20.4 / 22.2 / 21.7 s
  - Hard 4/4 26.5 / 26.7 / 26.4 s
  - Brutal 6/6 26.4 / 26.6 / 26.7 s
- **Colossus in the run:** 77–84.5 s.
- **Human reaction:** clears with no down on all difficulties (Normal 4.24–4.35 min).
- **Hard / Brutal clears:** 5.22–5.54 / 5.27–5.57 min.
- **Sight gate's tightest margin: +1.31 studs.** It is the camera at (306, −30) to Brutal's innermost east fodder. The doorway glimpse is −1.64, exempt.
- **Highest camera:** 60.49, under the wall top's 64 (+3.51).

## Gates run

- `py tools/check_levels.py` → CHECK: PASS.
- 12 of 12 new-rule mutants red on in-memory copies. There is also a control case: a ledge 58 off stays green.
- `py tools/sim_range.py --levels-only --level forest --check` → PASS (exit 0, about 6 min).
- `py tools/sim_combat.py --check` → PASS, all 23 assertions:
  - Normal 130,133 cash; bonuses 5.8%.
  - Hard ×2.22 and Brutal ×4.45.
  - `targetMinutes` 5 against a 5.1-min mean.
- `py tools/check_stage_mirror.py --luau <main checkout>\tools\bin\luau.exe` → PASS against this data (run once, with the other owners' work in progress in the tree).
- Not run: the harness and `mutate.py`. They belong to luau-engineer and QA.

## For other owners

- **luau-engineer**
  - `tests_l1c.luau` and `check_stage_mirror.py` should expect 10 / 12 / 12, made of Normal 4 fodder + 6 brutes and Hard / Brutal 4 fodder + 8 brutes (not the contract's 8 F + 2 B and 8 F + 4 B).
  - Spots are `ambushW` and `ambushE`, 6 points each, z −22.5.
  - Boss at [0, 30]; Colossus cash 41,000.
  - Gatehouse wall blocks are y 38 / sy 76 (top 76). If a test pins the contract's y 44 / sy 64, change it to the top only.
- **Lead**
  - Accept or overrule the Normal mix (2 F + 3 B a side) and the resulting +4% Normal cash a minute.
  - The Hard-at-2/2 R8 rows are the thinnest gate (+4.1%) and swing with the simulator's run order, about ±10% on the 2/2 Colossus.
  - "Floors" uses a shadow form rather than the contract's literal "≤ floor y within 200". The literal rule fails on `Secret_cache` (top 18, 149 off), which cannot see in.
