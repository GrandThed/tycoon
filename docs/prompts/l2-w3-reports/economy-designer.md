# L2 W3: economy-designer report (2026-10-19)

Branch `l2-w3` in `tycoon-p5`. Nothing committed. Full numbers: `docs/BALANCE.md` "L2 W3".

## Files changed (all mine per contract §10)

- `src/shared/Config/ProvingGrounds.json`: `weapons.frostHammer` only.
- `src/shared/Config/Expeditions.json`: look `ice` (Ice, 150 / 208 / 245); `found.frostHammer` (castle, "Found in the Castle").
- `src/shared/Config/Combat.json`: `levels.react.ice` `{ cell 7, lift 0.2, thickness 1, reachDown 6, ahead 4 }` (no `iceHits`).
- `src/shared/Config/Levels/1_ForestRoad.json`: `secrets.shrine` 6 Valor, 63 Timber.
- `src/shared/Layouts/Levels/ForestRoad.json`: §5 Option A. CreekUp (x −410..−390, z −30..8, deep, no react);
  Creek (z 8..96) and Pond (x −436..−364, z 96..156), deep, `react` "ice", `landing` (−385, 0, 2); ShrineIsland
  16 × 4 × 16, top 0, at (−400, 128); the shrine chest 6 × 4 × 6 on it. Island kept where the contract drew it.
- `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/sim_range.py`, `docs/BALANCE.md`.

## Gates

- `py tools/check_levels.py`: PASS (about 30 s).
- `py -3.12 tools/sim_range.py --check` (64-bit 3.12): PASS, 523 checks, 0 FAIL, 11.6 min (the first run found the chest gate reading a map node's price as None; fixed with `check_levels.chain_price`).
- `py -3.12 tools/sim_combat.py --check`: PASS, 23 of 23.
- `py tools/check_stage_mirror.py --luau ...`: PASS on the luau-engineer's lines (run read-only).
- `py tools/check_levels_mutants.py --luau C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`: PASS: every case as expected (176 data cases, the 8 stage-mirror cases, the 1 simulator case; about 1.5 h, run alongside the simulator). The W3 cases are listed in BALANCE "L2 W3"; the one W2 case re-aimed is "the shrine names a family", which now also drops `found`.
- The gates ran on the working tree with the luau-engineer's and ui-engineer's edits in progress; re-run them in QA.

## Constants that moved from the contract, and why

1. **Frost Hammer swing: damage 36 → 38, rate 1.5 → 1.55, arc 140° → 120°.** At the contract's numbers the
   Colossus took 87.3–94.2 s (melee band 60–90). The boss kill follows the dodge rhythm, not DPS in a line:
   damage 40 makes every swing heavy (the contract wants only the finisher heavy) and drops the Colossus to
   76.6 s, under the Broadsword's slowest 77.2 (L2-39). 38 at 1.55 gives 83.2–84.9 s. The narrower arc brings
   crowd6 from 469 (0.5% under the ceiling) to 439, and it does not move the boss rows. Single is 75 against the
   target 68 (+10%, inside ±15%).
2. **Frost Quake: damage 50 → 30, count 3 → 1, radius 8 → 32.** It is still the Earthquake launcher. L2-39 also
   holds the kill *with* the ability. Earthquake's three rings all land on a boss standing at the caster's feet
   (128.6 per cast), so the contract's Frost Quake made the Colossus 72.9–76.6 s, faster than the Broadsword's
   slowest. One wide ring keeps the crowd burst (it reaches more bodies) while a boss takes 30 per cast:
   - burst 3.5 s (band 3–5);
   - busy-crowd cooldown 55% (band 40–60%);
   - floor 42% (band 30–45%);
   - on the bosses it no longer shortens the kill.

   **ui-engineer: the FrostQuake visual must draw one ring of radius 32.**

Everything else is as the contract wrote it: ice config, 6 Valor and 63 Timber, the landing, Option A.

## Measured

- **Frost Hammer vs bosses (range, tier 1), 0 hits taken:**
  - Colossus: 83.2–84.9 s; with Frost Quake 83.7–90.5 s. Broadsword 75.4–77.2 s.
  - Warlord: 102.9–107.1 s; with Frost Quake 101.0–105.3 s. Broadsword 97.3–98.1 s.
  - Warlord siege 45%. Plate phase 18.9 s, 45 studs. Plate breaks in 6 hits (2 combos).
  - L2-39 margins: +6.0 / +6.5 s on the Colossus; +4.8 / **+2.9 s** on the Warlord. Tight: any hammer number
    change re-runs the boss rows.
- **Forest Road, Frost Hammer + Longbow, Normal 2/2:** clears in 4.46 / 4.69 / 4.43 min, 0 downs.
  - Cash: 29,178 a minute, ×0.95 the Broadsword + Longbow pair (gate ≤ ×1.10).
  - Colossus in the run: 80.6–84.4 s, ×1.07 the Longbow pair's (gate ≥ ×0.90).
- **The crossing:** 9 swings, 109 studs, 38 cells frozen, a 16-cell chain.
  - Ideal (no lag, no reaction): **5.8 s**.
  - A human (0.15 s round trip, 0.25 s reaction per swing): **9.0 s**. This is gated in the lead's 8–20 s band.
- **The shrine chest:** 6 Valor and 63 Timber.
  - 63 is 30% of a first Normal clear's 211 Timber (top of the 15–30% band), and 29% of the Normal stock of 220.
  - Valor is held under Double Jump's 10, the dearest sold ability, because the chain starts at a map node.
- **Falls and the landing:**
  - A fall into the Creek or the Pond (footprint + `rescue.outside` 4) comes back to Road2 at (−385, 0, 2).
    That is 6 studs from the ice's first row, after a 12.2-stud fall (0.35 s) plus the rescue's own step.
  - A slip off Road2's **north** edge falls into CreekUp, which has no landing (only ice may carry one). That
    player goes to `SafePoint` (the trailhead on a first run).
- **Island reach without ice (g):**
  - The tightest top is ShrineSignPad, 102.0 studs from the island.
  - Reaches: the jumps 49.3; Leap Smash after the jumps and a dash 71.0; Impale Dash held in the air 80.6.
  - Margin **+21.5** (rule: ICE_MARGIN 15).
- **Frozen (h):** the island is reached and the chest opens from it.
  - Every one of the 31 unclimbable walls stays unclimbable.
  - The lookout's (a)–(d) hold.
  - killY is 12.2 under the ice.
  - The frozen sheets are floor, not walls, for the shot-origin chord gate (the thinnest tall piece is still
    CaveBrambleE, 2).
  - The bend rule (L2-47) does not change: the ice touches only Road2, the sign pad and the island, and no road
    block lies beyond it.
- **Parts:** 248 (132 ice pieces); maxParts 600.
- **Sniper re-pin (R8):**
  - Creek leaves `sniperSpots` and `sniperSpotsOpen`.
  - `sniperSpotsFrozen` and `sniperSpotsOpenFrozen` are the same lists plus Creek, and no other name.
  - The frozen Creek's spot is at (−391, 9), 99.7 off the region. It earns 0 / 0 on Normal and Hard; sim_range
    rates it with R8's course.
  - `SNIPER_KNOWN_LIMIT_L4` is unchanged.

## Needs the lead's decision

1. **The crossing's ideal pace (5.8 s) is under the 8–20 s band.** Only the human pace (9.0 s, 1 s of margin) is
   in it, and that is what I gate. A swing freezes about 13.5 studs, which a walking player covers in the swing's
   own 0.65 s, so walking sets the crossing. To slow it you would need a shorter freeze (smaller `ahead` and
   `cell`, so more pieces) or a slower swing. I left it alone.
2. **A slip into CreekUp (north of the bridge) goes to SafePoint, not the landing.** Giving CreekUp ice and a
   landing would add a frozen floor by Road3 and a new sniper-spot name. I did not do it.
3. Confirm the Frost Quake reshape (one ring, radius 32) and the hammer's single DPS of 75 against the target 68.

## For other owners

- **luau-engineer:**
  - `sim_range.react_problems` mirrors your `StageFlow.reactProblems` lines. These are the same strings:
    - "is ice and collides"
    - "is ice and opens"
    - "reacts and does not collide" (non-ice)
    - "has a landing and is not ice"
    - "landing is X, not a point"
    - "landing.K is V, not a number"
  - `check_stage_mirror` is green on my data.
  - The two mirror mutants look for your labels "a pool that collides" and "plain water with a landing".
  - **Ice pieces (`sim_range.ice_cells`, counted by `check_levels.part_count`):**
    - `ceil(side / cell)` cells per axis, the footprint divided evenly.
    - A cell gets no piece when its centre lies inside (edges included) the footprint of a colliding block
      (not the water block itself) or a secret whose top is above the water's top.
    - Forest Road: 132 pieces; part_count 248. The harness should agree.
- **ui-engineer:**
  - Frost Quake is now **count 1, radius 32, damage 30**.
  - The swing is now **120°, damage 38, rate 1.55** (range 9 unchanged).
  - Phone `iceOnAuto` reads range and arc from config, so it follows.
- **Lead:** nothing in `Economy.luau`.
- **INTERFACES:** L2-49's numbers and the targets text now differ from the data (see above).
