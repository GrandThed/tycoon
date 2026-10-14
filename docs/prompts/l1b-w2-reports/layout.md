# L1b Wave 2 "the long road": layout plan and arithmetic (economy-designer)

Brief: `docs/prompts/l1b-w2-layout.md`. Nothing in `src/` or `tools/` changed and nothing is committed.
Everything is in `docs/prompts/l1b-w2-layout/`:

| File | What |
|---|---|
| `long-road.html` | The page for Ben, titled "The Long Road". For each layout: a whole-level SVG and three camp close-ups, all to scale, then the tables. After both layouts: the tent table and the ASCII maps. Light and dark themes. Checked at 1200 px and in a 360 px viewport: no page scroll, and tables scroll inside their own box. |
| `make_drafts.py` | Writes the four drafts below. Spots are written in camp-local studs. |
| `winding.level.json`, `winding.layout.json` | The recommended layout, in the shapes of `Config/Levels/1_ForestRoad.json` and `Layouts/Levels/ForestRoad.json`. |
| `switchback.level.json`, `switchback.layout.json` | The alternative layout, in the same shapes. Both use one level file: the same residents and the same spot ids. |
| `build_page.py` | Imports `tools/check_levels.py` and `tools/sim_range.py` read-only (no bytecode written). It runs check_levels' own gates on each draft as if it were Forest Road, then computes everything below and writes the page, `ascii.txt` and `numbers.json`. |

New keys in the drafts (the game reads none of them yet):
- level `crowd.clearBonus.share` 0.1. `cash` and `materials` stay at 0, so today's Validate passes.
- level `camps[].tent` `{ every, units }`.
- layout `camps[].tent` `{ x, y, z, sx, sy, sz }`: a walk-through marker block.
- layout `sneak`: a polyline for the Wave 2 sneak gate.

**Every check_levels gate passes on both drafts: 98 of 98.** The Wave 2 sizes were put into its `EXPECTED` table in memory only: camps 85 × 85, 141 × 133 and 115 × 115 (±10%), route 900–1,100 studs, residents A 30–36 and B 40–50. The gates cover:
- route continuity, the gap, the climbs and the creek;
- the lookout needing the double jump;
- C's "nothing beside" rule and its wall band;
- checkpoints unseen and out of shooter reach;
- `chaseMargin` and perches;
- posts, fires and patrols;
- the population rule as L1b-11 has it;
- the lobby's 150-stud clearance;
- the Parts count.

## The two layouts

**The winding road (recommended).** The road runs west to east and zigzags: the trailhead, the 12-stud gap, the creek bridge (the shrine's pond to the south), a jog north and the 8-stud climb by the lookout. Then it reaches the three camps with a shallow U-bend between each pair. Heights are 0, then 8, with a +4 climb before C. The road crosses A and B along their **north side** (gates at v −28 and v −46), so each camp spreads south of the road. A careless walker on the road is seen by the road-side fires. The **sneak path is the fence line**: a careful player hugs the inside of the north fence, 4 studs from it, and passes every resting eye beyond its sight. No extra Parts are needed. Each open camp **wakes in chunks**:
- A: the road fires (16 bodies), then the watch and the patrol by the tent (20 more).
- B: three clusters of 16, 17 and 17.

C sits at the east end, crossed through its middle as in L1.

**The switchback (alternative).** The road folds back on itself up a hillside in three terraces: 0, 8, 18 and 28.
1. East along the valley through A, entering by the west gate and leaving by the north gate.
2. A hairpin up and **west** to B on the middle terrace, entering by the east gate and leaving by the north gate.
3. A second hairpin up and **east** along the high road, which overlooks B's north side from 10 studs above. It ends at C at the top, which must be the level's east end for C's "nothing beside" gate.

A and B are crossed corner to corner. The sneak path is the inside of the fence past A, but past B it is a **goat track outside the fence**: two road blocks along B's east and north sides. That is allowed beside an open camp and is the real difference in feel. A sits 42 studs east of B so nobody hops from A's floor up into B. The wake clusters are the same as the winding road's.

## The arithmetic

"Computed" means read from the drafts and the configs with the game's own rules: `CampBrain.Posts` and `Sees` as `sim_range` mirrors them, and the Parts as `check_levels.part_count` counts them. "Estimate" is named where it applies.

### Bodies against the 160 cap (computed; the same in both layouts)

| | A | B | C | Residents | Tents' stock (A + B) | Boss room's room | Boss + 12 calls | **Worst case, every camp awake** | Wave 1's rule (reserve 21) |
|---|---|---|---|---|---|---|---|---|---|
| Normal | 30 | 46 | 36 | **112** | 8 + 8 | 42 − 36 = 6 | 13 | **147** | 139 |
| Hard | 36 | 50 | 38 | 124 | 16 | 42 − 38 = 4 | 13 | **157** | 149 |
| Brutal | 36 | 50 | 38 | 124 | 16 | 4 | 13 | **157** | 149 |

- Worst case = every resident alive, every tent's whole stock out and alive, the boss room's cap over its residents, and the Colossus with 12 calls.
- Residents never scale with `countMult` (L1b-10).
- The density caps (floor area / 200) are A 36, B 94 and C 66. **A is at its cap on Hard.**
- **The cap, not the wish, sets Hard's extras**: only 12 Hard-only units fit, so Brutal equals Hard as in Wave 1.
- Wave 1's reserve of 21 holds only 8 tent bodies, so two tents of 8 need the rule changed (assumption 4).

### Parts, the wire, the route (computed)

| | Winding | Switchback | Limit |
|---|---|---|---|
| Parts (check_levels' count + 1 marker per tent) | 79 + 3 = **82** | 74 + 3 = **77** | 600 |
| Furthest camp edge + wall from the origin | **379** | **278.5** | 1,000 (codec 1,024) |
| Furthest Part from the origin (the trailhead) | 482 | 482 | bodies never leave a floor |
| Route length | **1,055** (A 73, B 129, C 103 through the camps) | **1,088** (A 52, B 127, C 103) | about 1,000 |
| Sneak path length, all on solid ground (the gap jumped) | 967 | 1,037 | |
| Gaps between camp floors (for `dormantRadius` 100–150) | A–B 109, B–C 185 | A–B 42, B–C 132 | |
| Closest two resting posts of a camp, less r_a + r_b + 0.5 (BALANCE's carried gate) | +0.07 | +0.07 | ≥ 0 |
| Lobby clearance | passes (≥ 150) | passes | 150 |

### The estimated first Normal clear at gear 2 / 2 (winding; the switchback is within 10 s)

| Part | Seconds | How |
|---|---|---|
| Walking the route at 20 studs/s | 53 | computed |
| Walking from group to group in A and B | 14 | computed: a nearest-first tour of the group centres, less the camp leg |
| A: residents + tent (3,188 effective HP) | 32 | estimate: effective HP ÷ 100/s |
| B: residents + tent (12,288 HP) | 123 | estimate |
| C: residents + two waves (13,585 HP; 36 + 68 bodies) | 136 | estimate |
| The Colossus | 75 | measured in Wave 1 (73.7–75.6 s) |
| The countdown | 3 | `levels.gateSeconds` |
| **Simulator's reacting player** | **435 s = 7.3 min** | estimate |
| **Ben** (his fighting × 1.36) | **567 s = 9.4 min** | estimate |

- **The 100 HP/s rate** comes from BALANCE "L1b" at 2 / 1. Wave 1's A took ~9 s for 855 HP (95/s), B ~35 s of fighting for 3,428 HP (97/s), and C's wave plus residents ~37 s for 4,200 HP (113/s). Effective HP = hp × `hpScale` + plate.
- **The ×1.36** comes from Ben's own Wave 1 clear: about 4 min against the simulator's 3.05, with the walking the same for both.
- The 2 / 2 preset is taken as no faster than 2 / 1 for a melee-led player.
- **Tent pace adds waiting** at 6 s: A's 8 come out over 42 s against a 32 s fight. That is at most +10 s, not counted above.

### Pay (computed from the drafts: per kill, the 10% clear bonus, the Colossus and its 48 calls)

| | A kills + bonus | B kills + bonus | C kills + bonus | Colossus + calls | **Clear** |
|---|---|---|---|---|---|
| Normal | 11,200 + 1,120 | 50,400 + 5,040 | 46,600 + 4,660 | 33,800 | **152,820 cash, 373 Timber, 10 Valor** |
| Hard | 32,800 + 3,280 | 108,000 + 10,800 | 104,800 + 10,480 | 67,600 | 337,760, 797, 20 (×2.21 of Normal) |
| Brutal | 65,600 + 6,560 | 216,000 + 21,600 | 220,800 + 22,080 | 135,200 | 687,840, 1,621, 40 (×4.50) |

| Per minute on Normal | Simulator's clear | Ben's clear |
|---|---|---|
| This draft | **21,070 cash, 51 Timber** | 16,180 cash, 39 Timber |
| Wave 1 (simulator) | 19,800 cash, 42 Timber | |
| L1 (simulator) | 13,400 cash, 24 Timber | |

- Simulator to simulator, cash is +6% on Wave 1 and Timber +21%. Timber is +113% on L1. Wave 1 had already flagged Forest Road Normal as the fastest Timber in the game.
- **38 brutes on Normal carry two thirds of the Timber**:
  - 16 in B, 10 in C, 6 in the tents and 6 in C's waves;
  - each pays 2,000 cash and 6 Timber.
- **If a per-minute Timber band near Wave 1 is wanted:** Forest Road's `rewards.brute.materials` 6 → 4 gives about 43 a minute. It is a level-file number; I did not change it.
- The clear bonus is 7% of a Normal clear (10,820 cash, 27 Timber). It is 10% of each camp's whole stock at the difficulty's price, so sneaking past a camp loses its kills and its bonus but costs nothing more.

### The sneak path against every resting group (computed, highest difficulty; a patrol: anywhere on its loop)

Distances are to the sneak path, in studs. "Road" is the distance to the route. "Seen" uses `CampBrain.Sees` with the cone, at the root height of the ground there.

| Group | Rest | Bodies | Sight | Winding: sneak / road / seen | Switchback: sneak / road / seen | A wake here wakes (2 × sight chain) |
|---|---|---|---|---|---|---|
| A.fireW | fire | 8 | 16 | 27.9 / 25.0 / no | 32.1 / 28.2 / no | fireW, fireN (16) |
| A.fireN | fire | 8 | 16 | 23.0 / 12.5 / **yes** | 21.0 / 9.0 / **yes** | fireW, fireN (16) |
| A.watch | guard | 10 | 30 | 56.5 / 56.5 / no | 70.9 / 64.7 / no | all of A (36) |
| A.loop | patrol | 10 | 24 | 41.1 / 34.0 / no | 50.1 / 45.6 / no | all of A (36) |
| B.fire1 | fire | 8 | 16 | 22.1 / 13.5 / **yes** | 34.5 / 11.9 / **yes** | fire1, fire2 (16) |
| B.fire2 | fire | 8 | 16 | 31.0 / 14.5 / **yes** | 20.5 / 12.8 / **yes** | fire1, fire2 (16) |
| B.loop | patrol | 8 | 24 | 77.4 / 77.4 / no | 30.0 / 30.0 / no | loop, fire3 (17) |
| B.fire3 | fire | 9 | 16 | 105.0 / 88.5 / no | 63.0 / 63.0 / no | loop, fire3 (17) |
| B.eastWatch | guard | 8 | 30 | 45.3 / 38.0 / no | 39.6 / 38.0 / no | eastWatch, eastFire (17) |
| B.eastFire | fire | 9 | 16 | 71.8 / 60.5 / no | 43.0 / 23.2 / no | eastWatch, eastFire (17) |
| C.* (4 groups, held) | | 38 | | n/a: held until the close | n/a | released together at the close |

- **The sneak path clears every open-camp group's sight.**
  - Tightest: B.fire1 at 22.1 against 16 in the winding road, B.fire2 at 20.5 in the switchback, and the switchback's B.loop at 30.0 against 24 on the goat track.
- **A careless walker on the road wakes the road fires of A and B**, 16 bodies each, and nothing else.
- **The wake chain is directed**: X wakes Y when Y's nearest resting place is within 2 × X's sight of X's. Fires reach 32, patrols 48 and guards 60.
  - A's watch reaches the whole of A (85 wide), so attacking the tent's guards first wakes all of A.
  - Attacking A's road fires first wakes only those two fires.

## ASCII maps (each 60 columns or fewer, 30 rows or fewer; the legend line is 56)

```
The winding road (recommended), 1 char = 14 x 14 studs, north up
                                                  #########
                                                  #..gggg.#
                                                  #.......#
            =?==ssss==     ==ssssssss==           ||g.....c|
         =======....==c======........===c=    ====||g..*..||
         =    ==.f..==  == ==ffff....== ==    =   ||g.....||
     ~   =     fff..p   ==  #ffff.....# ==    =   #....ff.#
S==s=~====     f....p   ==  #........g# ?======   #C...ffT#
==   ~=        #A..Tp       #.......fg#           ####gggg#
     ~         ###ggg       #......ffg#
     ~                      #.ppff....#
     ~                      #Bppff..T.#
    ~~~                     ###########
    ~?~
    ~~~
=road s sneak g/f/p guard/fire/patrol T tent c chk *boss
```

```
The switchback (alternative), 1 char = 10 x 12 studs, north up
                                               ############
                                               #...ggggg..#
                                    ?          #..........#
                                    =          #..........#
                                    =         ||.g.......|c|
                       =======================||.g....*..|||
                       =   ===                ||.g.......|||
                      =c===========            #......ff..#
                    ##===#########s            #......ff..#
                    #.......ff....s            #C...ggggTg#
                    #.......ffff..s            ############
                    #.........ff..s
                    #.............s
                    #............==
                    #.ff.........==========
                    #fff.....ff..==       =
                    #........ff...#       c
                    #pppp.....gggg#   ###===###
                    #Bppp..T......#   sssss...#
       ~~           ###############   s.......#
==     ~~                            ==.ff....#
=S==ss=~~==============================..f...pp
       ~~=   =%?                     ==....T.pp
       ~~                             #Aff...pp
       ~~                             ######ggg
       ~~
     ~~~~~~
     ~~~~~~
     ~~?~~~
     ~~~~~~
=road s sneak g/f/p guard/fire/patrol T tent c chk *boss
```

## The tent question, costed

The drafts use **8 bodies per tent, one every 6 s**. A's tent holds 4 fodder, 2 slingers and 2 brutes. B's holds 2 fodder, 2 slingers and 4 brutes. C has no extra stock: its "tent" is where its waves come out.

**(a) Reinforcements per tent.** Hard's worst case on the cap is 124 residents + 2 × stock + 4 + 13.

| Stock | Hard worst case | Pay per Normal clear | Sim time | Notes |
|---|---|---|---|---|
| 4 | 149 | A −2,700, B −4,600 | about −17 s | barely felt |
| **8 (recommended)** | 157 | A's tent 5,400 cash and 14 Timber, B's 9,200 and 26 | +35 s in all | 3 spare under the cap |
| 12 | **165, 5 over the cap** | | | needs 5 Hard residents cut, or the boss room's `maxAlive` 42 → 38 and 1 resident |

No code difference between the three: a number in the level file. Balance risk grows with the stock, because every tent body is pay and Timber with no extra walking.

**(b) Pace.** A number (`tent.every`), with no code cost.
- 6 s: 8 out in 42 s. **Recommended.** It roughly matches A's ~32 s fight and is well inside B's ~2 min.
- 10 s: 70 s. A's tent outlasts A's residents, so the end of camp A becomes waiting at the tent.
- 15 s: 105 s. Most of the stock arrives after the camp's residents are dead.

The sims need the pace mirrored, in `sim_range.py` `LevelRun` beside the camp step.

**(c) Stopping it.**
- **Stops on its own once its stock is spent (recommended).**
  - Bodies on the cap: 0.
  - Code: the rule in `CampBrain` (pure; the outline already places it there) and the executor in `WaveService`.
  - Sims: `sim_range` mirrors the rule; `check_stage_mirror` compares it.
  - Risk: nothing new.
- **Destroyable, as a crowd body with no brain.** A new `tent` kind in `ProvingGrounds.json crowd.kinds`: radius ~5, hp, no attacks and no `brain`. `CrowdService` already lets "a kind without one stand", and a hit on it wakes its group like any hit.
  - Cap and wire: +1 body per tent on the cap and +11 bytes on the wire.
  - Rendering: `CrowdRenderer` needs a tent model, or it draws an R15 raider.
  - Hit shapes and crowd step: `HitShapes` works as is; a radius-5 body widens `separate()`'s scan, which `crowd.largeRadius` 2.5 handles.
  - Pay: it needs a reward entry.
  - Sims: `sim_range`'s policies must choose when to kill it. That moves the clear time a lot: a tent killed first is up to 8 fewer bodies.
- **Destroyable, as a Part the server tests.**
  - Bodies on the cap: 0.
  - Code: a second damage path in `WeaponService`. Melee sweeps and shot rays test crowd bodies through `HitShapes`, not Parts. `StrikeTally` and feedback for a Part target, plus a review of a new damage path.
  - Risk: the most code risk of the three.

**(d) Where they go.**
- **Join their own camp's fight (recommended).** The tent's bodies are a group of their own, posted at the tent. They go straight to `fight` against players in play for that camp, and they leash home to the tent like any group. Nothing new beyond the tent rule.
- **To wherever the fight is, past the fence.** A body would have to leave its floor, which breaks L1b-1 (one floor per body for life). Large risk.
- **"Only refills its camp"** (replacing dead residents at their posts) contradicts Ben's §16.5, "no refills". Not offered.

## Assumptions the lead must confirm (one line each)

1. **The 2 × sight rule:** a waking group wakes a resting group of its camp whose nearest resting place lies within 2 × the **waking** group's sight. It is judged once, at the wake, from resting places, and the chain is directed.
2. **The sneak rule as drawn:** flat distance from the sneak polyline to every resting place (a patrol: its whole loop) greater than sight, cones ignored. The cone-aware result is reported too.
3. **The sneak path is tool-only data** (`layout.sneak`) for a `check_levels.py` gate. The game ignores it.
4. **The population rule with tents:** residents + Σ tent stock + the boss room's room + 13 (boss and calls) ≤ 160. This replaces `populationReserve` 21's flat 8 for tents.
5. **Clear bonus:** `crowd.clearBonus.share` 0.1 of the camp's whole stock at the difficulty's price: residents, its tent's stock, and in C its waves but not the boss. Paid when the camp clears. The flat `cash` / `materials` stay at 0.
6. **An open camp clears only when its residents and its tent's bodies are dead and the stock is spent.** Otherwise a tent that pauses when its camp rests leaves the camp uncleared forever. The contract must also say whether a camp with stock left but no group awake sends it.
7. **C's tent is the source of its stage waves** (spawn points round it), with no separate stock.
8. **The tent marker is a walk-through block** (look `tent`, a 13th `Expeditions.json looks` key), so it is neither cover nor a perch.
9. **A keeps Ben's plan on Normal** (fodder and slingers only). Its brutes come from its tent.
10. **B and C are brute-heavy on Normal**: 38 brutes in the level against L1's 10. This is the main balance risk and the lever behind the ~10 minutes. If it reads as too much, fodder back in for brutes costs about 4.2 s of simulator time per swap.
11. **B has 2 lobbers** (Ben's plan said one) for its bigger floor. **C has 2 armoured** on Normal.
12. **Hard adds only 12 units, and Brutal equals Hard**, because the cap allows no more.
13. **The clear-time estimate:** 100 effective HP/s, the Colossus 75 s, Ben's fighting ×1.36, and 2 / 2 no faster than 2 / 1. The real band comes from `sim_range` after the contract.
14. **The draft band for the gate:** simulator 7–8 min on Normal (so Ben ~9–10.5). `targetMinutes` 9 and `runCapSeconds` 1,500 are drafted.
15. **check_levels' `EXPECTED["ForestRoad"]` for Wave 2:** camps 85 × 85, 141 × 133, 115 × 115; route 900–1,100; residents A 30–36, B 40–50; `partsL1` dropped (the 73 − 6 + fires formula no longer applies).
16. **The post-spacing gate** BALANCE carried (r_a + r_b + 0.5 between any two posts of a camp, every difficulty) holds in both drafts at +0.07. It should become a real gate.
17. **Checkpoints of A and B moved** onto the road past each exit, in both drafts.
18. **The switchback only:** C must stay the level's east end, and A sits 42 studs from B, so no hop from A's floor up into B.
19. **Both layouts keep L1's three secrets and its features**, moved: the lookout on its 26-stud ledge, the cache on a spur off the B-to-C road, the shrine in the pond, the 12-stud gap and the creek.
