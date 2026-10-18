# L2 W2: economy-designer report (2026-10-18)

Branch `l2-w2` in `tycoon-p5`. Nothing committed. Full numbers: `docs/BALANCE.md` "L2 W2".

## Files changed (all mine per contract §8)

- `src/shared/Config/ProvingGrounds.json`: `weapons.flamethrower` only.
- `src/shared/Config/Expeditions.json`: look `bramble`.
- `src/shared/Config/Combat.json`: `levels.react` `{fireHits 6, pad 0.5}`; `debug.grantFamilyAttribute` "DebugGrantFamily", `debug.removeFamilyAttribute` "DebugRemoveFamily".
- `src/shared/Config/Levels/1_ForestRoad.json`: `secrets.cache` 4 Valor, 60 Timber.
- `src/shared/Layouts/Levels/ForestRoad.json`: §5 Option 1 cave (28 blocks: 5 floors, 13 walls, 6 roofs, 2 brambles with `react` "fire", `opens` "cave", plus BendWall); CacheSpur and CacheSignPad removed (blocks and region cells); cache chest moved into the alcove; sign on Road4; `shortcuts`, `shortcutRoute`.
- `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/sim_range.py`, `docs/BALANCE.md`.

## Gates

- `py tools/check_levels.py`: PASS.
- `py -3.12 tools/sim_range.py --check`: PASS (64-bit 3.12, 11.8 min).
- `py -3.12 tools/sim_combat.py --check`: PASS, 23 of 23.
- `py tools/check_stage_mirror.py --luau ...`: PASS on my data (run read-only; the file is the luau-engineer's).
- `py tools/check_levels_mutants.py --luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`: every case as expected: 108 data cases, 4 stage-mirror cases and 1 simulator case (35 min). The full run went red only on three W1 s1 cases, which were written for the old 12-wide cache. They now judge the cave's (a); one is a control (green). Those three were re-run and pass.

## Constants that moved from the contract, and why

- Flamethrower stream: range 16, width 5 became **20 × 7**. At 16 × 5, crowd6 was 159 against the 280 target. At 20 × 7 it is 268–277.
- Dragon's Breath: damage 30 became **36** and killRefund 0.3 became **0.5**. At 30 the burst was 3.0 s, on the band's floor. At 0.3 the busy-crowd cooldown was 71% of base, outside the 40–60% band. It is now 3.7 s and 53%. Damage stays under heavyHit 40.
- Pair band. The contract compared the Flamethrower run with the Broadsword + Longbow run. The simulator's reacting player uses only the melee, so I added a pair player who swings whichever of his two weapons reaches.
  - With either ranged weapon the pair clears in about 4.2 min. So the clear band is L2 W1's 4.0–5.75, not 4.5–5.75.
  - The cash yardstick is the Longbow pair: Flamethrower pair 31,663 cash a minute against 30,688 (×1.03). Against the melee-only run it is ×1.20, but the Longbow pair alone is ×1.16 of that run.
  - **Lead to confirm.**

## Measured (details in BALANCE)

- **Flamethrower against the bosses (range, tier 1):** 0 hits taken in every fight. L2-39 is now a gate in `sim_range`.
  - Colossus: 110 s, 86 s with Dragon's Breath. Broadsword 75–77 s.
  - Warlord: 127 s, 112 s with Dragon's Breath. Broadsword 97–98 s. The plate breaks at 51 s with 11 ground slams.
- **Forest Road, Normal 2/2, Broadsword + Flamethrower pair:** 4.05 / 4.24 / 4.17 min, 0 downs. Its Colossus is ×0.96 the Longbow pair's.
- **Shortcut run, Normal:** 4.29–4.52 min, 37 s faster on average (the contract expected about 25 s). It pays 124,040 cash and 201 Timber, 5.6% less. Cash a minute ×1.07 (gate ×1.15).
- **Shortcut run, Hard 4/4:** 23 s faster (the contract expected 30–35 s), 9.6% less pay, cash a minute ×0.98. The human-reaction player has no downs on either difficulty.
- **Cache chest:** 60 Timber is 28% of a first clear's 211. 4 Valor.
- **Route:** the main route is unchanged at 1,079. The shortcut route is 350 studs and replaces 342 studs of the main route, skipping camp A.
- **Sniper re-pin, closed variant:** the old list less Secret_cache.
- **Sniper re-pin, open variant (tunnel found):** CaveMouth and CaveExit are added. Both are rated on Normal and Hard and earn well under the mission player.
  - The thinnest margin is Hard, CaveMouth, seed 23: 19,151 against 20,512 cash a minute.
- **The AB bend:** BendWall closes the gap and reaches the ridge. The largest hop saving left on the road is 49 studs (a corner); the rule's limit is 60.

## Needs the lead's decision

1. **"The exit's bend must leave no spot" cannot hold with an open mouth.** Under the contract's own R8 sight rule, a floor beside an open opening onto a region cell sees the road. No rusher can reach it (it is more than chaseMargin off the region). A body in a corridor past a corner always sees round it, so no single bend removes this.
   - The bend does keep every other cave floor clean. CaveExit, the floor block between the mouth and the turn, plus 9 studs of the exit leg, is the only exit spot.
   - The same holds at the west mouth (CaveMouth, which sits like Road4).
   - Both are pinned in `EXPECTED.sniperSpotsOpen` and gated by the sniper course. They need your OK as new Normal spots. Hard has no known limit; they pass there.
   - The alternative is making the cave a region leaf. Raiders would then follow into it and could walk through a closed bramble, since the crowd ignores geometry. Not proposed.
2. Confirm the two pair-band changes above.
3. The cache sign stands on Road4's north half, 2 studs from the route line. A pad off the road would become a new sniper-spot name.

## For other owners

- **luau-engineer:** `sim_range.react_problems` mirrors your `StageFlow.reactProblems`, with the same refusals and messages; ids are capped at Unlocks.MAX_ID_LENGTH. `check_stage_mirror` is green on this data.
  - The layout's `shortcutRoute` is tool-only. Validate should ignore it, as it does `route` and `sneak`.
  - Shortcut box `cave`: centre (−80, 14, −59), size 12 × 12 × 10. A player who burns the exit bramble from RoadAB5 and steps in records the shortcut without walking the tunnel. Is that acceptable as "found"? Design call for the lead.
- **ui-engineer:**
  - The stream is now **20** studs long and 7 wide, not 16 × 5. The phone auto-fire range check should read the config.
  - The tunnel is 12 wide and 14 high over floor 8, 22 high over the mouth stub at floor 0. Roof foot at y 22 everywhere.
  - The exit turns 90° 12 studs before its mouth, for the camera check.
- **Lead:** nothing in `Economy.luau`.

## check_levels changes in brief

- **Headroom:** `standable_points` counts a roofed top when there are 6 studs of headroom over it. `exposed()` drops tops with none (a bramble under its roof) from `unclimbable`, (b), the perches, lifts and reachability.
- **R8 sight:** a spot is kept only where a bow's line in plan reaches a cell. The line is stopped by walls and brambles that span both bodies; roofs do not stop it. The test is exact: critical-angle casting, with a raster room filter for speed.
- **(f), closed variant:** a compressed-grid 3D flood fill proves the cave sealed at any gap width. Every wall facing the sealed air must be unclimbable.
- **(f), open variant:** the shortcut route is walked with corridor width ≥ 12 measured between walls and a body's headroom (a climb's rise more). The sneak rule applies along it. The alcove must open onto the route. The open sniper list is pinned.
- **(a) for the cache:** its trigger is met only from its alcove floor and its own top.
- **(e) chain:** `key_chain` resolves doubleJump → lookout → flamethrower → fire. A chest's material must be 15–30% of the level's Normal stock. Valor must be under the price of the ability the chain starts from.
- **The bend rule (L2-47):** shortest path around unclimbable walls through their corners.
- **Lifts:** `fielded_lifts` now covers every family and `LIFT_KNOWN_LIMIT_W2` is gone. The lookout still has 0 lift routes.
- **Speed:** the walled gate now only considers walls within 200 studs of camp C. Run time is about 20 s.
