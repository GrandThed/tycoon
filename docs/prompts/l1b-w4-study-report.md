# L1b Wave 4 groundwork study — report

Read-only study for L1b Wave 4 "no waits, no walls" (brief: `docs/prompts/l1b-wave4.md`). Worktree
`C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave4` (identical to `main`), read on 2026-10-15.
Ben's decisions (MISSIONS_DESIGN §19) are fixed and win over L1b-6, L1b-7, L1b-8, L1b-W2-7 and
L1b-W2-8. Every claim about the code carries `file:line` and is marked **verified** (read in the
code, or measured from the layout or a simulator run) or **estimated** (arithmetic or judgement,
not run). A **guess** is a number nobody has measured yet. Paths are shortened:
`Svc/` = `src/combat/server/Services/`, `Ctl/` = `src/combat/client/Controllers/`.

The one tool run of this study (scratch, nothing written in the repo): `sim_range.LevelRun` with
the `mission` policy on Forest Road, Normal, three seeds, at 2 / 2 and at 4 / 4, with the tents
as shipped and with both tents removed in memory (`scratchpad/w4study/pace.py`). Its numbers are
in §5 and are **verified** for today's chase rules (bodies clamped to their floors).

---

## 0. Recommendations, one line each

1. **Floors:** keep one height per camp. Each open camp gets a **chase region**: its floor plus a few authored road **cells** at the same height. No per-body floor and no road reshaping: the road beside A and B is already flat at their height 8 (§1).
2. **Navigation:** the U-bends need waypoints. Add a pure `src/shared/Region.luau` (clamp into the cells, a lane's runway, and the next **door** toward a goal) used by the crowd, the brain, the renderer and the mirror (§1).
3. **Fences:** keep them. Chasers leave through the gates, because cells meet a floor only inside a gate span (measured). No fence change (§2).
4. **Chase rule:** a group knows a player it sees within `camps.chaseSight` or who hit it within `camps.hitMemorySeconds`. It follows him anywhere in its region and goes home after `leashSeconds` with no known player it can reach (§3).
5. **In play:** becomes "reachable": the region, not the floor rectangle, plus a shooter's reach. It no longer gates damage. BLOCKED stays only for the Chief's held residents and for plates (§3).
6. **Home:** a homeward group takes hits. It turns back only for a player it can reach, and it still heals at its posts (§3).
7. **Phone auto-fire:** drop CampAim's in-play clause; keep "never a resting body" and "never in the countdown" (§3).
8. **Exploits:** territories never overlap and stay out of reach of the boss room. Shooters answer high ground. Sniping from out of reach is slow and bounded by "no refills", and a simulator policy proves it pays less per minute than fighting (§4).
9. **Tent:** sends only while the camp is **ahead of its clock** (kills against the camp's own target seconds, measured while it is awake), one body every `every` s. It never sends once the residents are dead. The camp clears when its floor is empty; stock left is forfeit (§5).
10. **Clear bonus:** a share of what the camp **fielded** (residents plus tent bodies sent), not of its whole stock (§5).
11. **Bands:** the Normal first clear drops from 7.0–7.2 to about 6.2–6.4 min at 2 / 2 (measured with no tents). Re-band to 5.75–7 min. Timber per minute stays in band (§5).
12. **Camp state off the camp:** clears, dormancy, `fieldClear`, the population and the snapshot need no change. At the boss room's close, every other camp's awake group loses the players (§6).
13. **Ben's look:** **N** steps to the next camp, open ones included: Depart → A → N (B's approach, for the sneak) → N (the Chief's countdown). No panel, no new config switch (§8).

---

## 1. Floors

### The road, measured from `Layouts/Levels/ForestRoad.json` (verified)

Route arc length `s` is measured from the trailhead. The road is a strip of path blocks 16 studs
wide, with void beside it down to `killY` −13.

| Feature | Where | Height (top) | Distance to the nearest camp |
|---|---|---|---|
| Trailhead, Road1 | x −482…−436 | 0 | — |
| **The gap** (12 studs) | x −436…−424, s 34–46 | 0 → 0 | 204 west of A's edge |
| **The creek bridge** (Road2 over Creek x −410…−390) | s 60–80 | 0 (water −1) | about 170 west of A |
| Road3, Road4 (jog north) | x −356…−302 | 0 | — |
| **The climb by the lookout** (Road4 → Road5) | x −302, s 212 | **0 → 8** | **38 studs** west of A's west edge (s 250) |
| Road5, LookoutSignPad | x −306…−264 | 8 | adjoins A's west gate |
| Lookout ledge | x −295…−271, z −66…−52 | **34** | its south face is on Road5's north edge, 7 studs from A |
| **Camp A**, the Pickets | x −264…−179, z −58.5…26.5 | 8 | gates W and E at z −52…−36 (16 wide) |
| RoadAB1–5 (U-bend south) | x −179…−70, bends at x −130 and −108 | 8 | A east edge s 335 → B west edge s 532: **197 walked**, midpoint s 433.5 ≈ (−124.5, 0) |
| **Camp B**, Main Camp | x −70…71, z −64.5…68.5 | 8 | gates W and E at z −52…−36 |
| RoadBC1–5, CacheSpur, CacheSignPad | x 71…230, bends at x 120 and 190 | 8 | B east edge s 673 → the step s 920: 247 walked |
| Cache secret block | centre (100, 13, −4), 12 × 10 × 12 | **18** | on the spur, in B's road half |
| **The step to C** (BC5 → BC6) | x 230, s 920 | **8 → 12** | 26 studs west of C's edge (s 946) |
| **Camp C**, the Chief's Clearing (locks) | x 256…371, z −101.5…13.5 | 12 | gates W and E at z −52…−36 |

**One plateau at height 8 runs from x −302 to x 230.** It holds A, B and every block between
them: Road5, LookoutSignPad, RoadAB1–5, RoadBC1–5, CacheSpur and CacheSignPad (all top 8).
- The road near the two open camps is already flat at their floor's height, and wide enough
  (16 studs, wider than any body's 4.4).
- The only height changes near an open camp are the climb 38 studs west of A and two perches:
  the lookout ledge (+26) and the cache block (+10).
- C locks, and its residents never leave its floor, so C's step does not matter.
- `py tools/check_levels.py --plan-only` prints the plan and the route's side view that this
  table was read from.

### What the code assumes (verified)

- A floor is one rectangle at one height: `Types.CrowdFloor = { centre, half }`
  (`src/shared/Types.luau:2258`).
- A body is clamped into its floor's rectangle (`Svc/CrowdService.luau:353-376`). The clamp runs
  in `integrate` (`:661`, `:696`) and again after separation (`:1155-1159`).
- `CrowdBrain.inArena` (a keepAway retreat) and `runway` (a brute's lane length) cut at that
  rectangle (`Svc/CrowdBrain.luau:301-337`, used at `:653` and `:953-957`).
- Ground shapes lie on `floorOf(body).centre.Y` (`:596`, `:609`). `ThreatField` and
  `VitalsService` read only `strike.floorY`, as the L1b study verified.
- The client mirrors the rectangle in `CrowdRenderer`:
  - the floor list is at `Ctl/CrowdRenderer.luau:475`;
  - tells and threat origins take their height from it (`:531`, `:1397`, `:1676`, `:2000`);
  - `laneReach` cuts a lane at the floor's edge (`:2171-2185`).
- The run sends the floors as `RunFloor = {x, y, z, hx, hz}` (`Types.luau:2684`), built in
  `Svc/WaveService.luau:1725-1749`.
- The wire carries absolute feet at 1/32 stud within ±1,024 (`src/shared/CrowdCodec.luau:10-17`).
  The plateau's furthest point is x −306, so **the codec needs nothing**.

### Options

| | (a) A chase region per camp, one height | (b) A per-body floor from the road under it | (c) Reshape the road |
|---|---|---|---|
| What | `CrowdFloor` gains `cells: { CampRect }?`. A body is clamped into the union of its floor and its cells, all at the floor's height | every body samples the top of the block under it each step | flatten and widen the road near each camp |
| `CrowdService` | clamp into the union of rects (`Region.Clamp`), and route a goal through doors (`Region.Toward`) in `integrate` | a height lookup per body per step, grounding to it, and falling when it walks off a drop | none |
| `CrowdBrain` | `inArena` and `runway` call `Region` | the same, plus `land`'s `floorY` from the feet. That breaks the rule "a ground shape lies on the attacker's own floor, not its feet" (`CrowdBrain.luau:89-91`) | none |
| `CrowdCodec` | none | none | none |
| `CrowdRenderer` | `laneReach` and `CampFloor` read the cells (from `RunFloor.cells`); heights unchanged | per-body floor heights for every tell; the client has no height map of the level | none |
| Mirrors | `sim_range` body clamp (`tools/sim_range.py:6257-6262`) plus a `Region` mirror; `check_stage_mirror` compares `Region` | all of (a) and a heightfield | `check_levels` route and sneak gates, and the bands move |
| Data | each open camp lists its cells; `check_levels` proves them | none | Ben's approved road changes |
| Needed for Forest Road? | **yes** | no: one plateau already | no: A and B already sit at the road's height |

**Recommendation: (a), with the cells authored in the layout** (`camp.chase: [{ x, z, sx, sz }]`;
the floor is implicit as cell 1). No reshaping, and no per-body floor. **Estimated.**

Authored cells rather than a flood fill in Luau:
- They are reviewable data, and `check_levels.py` proves them.
- The territory border (§3) is a choice, not a fact of the geometry.

### Navigation is needed either way (verified + estimated)

A chaser on RoadAB2 whose target is on RoadAB4, at the far arm of the U-bend:
- The straight line to the target crosses void.
- Clamped to the union, the chaser presses on RoadAB2's east edge and stays there.

The fix is pure and small:
- Consecutive cells **overlap** (a door). The **next hop** from any cell to any other is worked
  out once at `SetFloors`; with about six cells a camp, the table is tiny.
- `Region.Toward(region, from, goal)` answers the goal itself when both points share a cell, and
  otherwise the centre of the door to the next cell.
- `CrowdService.integrate` applies it to every resident's goal: the brain's chase or keepAway
  goal (`:648-680`) and `CampBrain.Goal`'s home walk (`:635-647`). A goal routed through a door
  seeks with stop distance 0.
- The same table brings a homeward group back through the gate.

**The cell rule** (a `check_levels.py` gate and a `StageFlow.Validate` refusal):
- every cell lies on standable tops at the floor's height;
- consecutive cells overlap by at least 2 × the widest resident radius + 0.5 (brute 2.2 → 4.9),
  so a body inset by its radius can pass the door;
- the cells form a tree with the floor at its root.

## 2. Fences

### What stands there (verified)

- An open camp's fence is cut at its gates and has no gate Parts and no wall
  (`Svc/LevelGeometry.luau:669-671`, `:737-748`).
- The fence stands **outside** the floor's edge, `fenceThickness` (1) deep
  (`LevelGeometry.luau:161-193`). It is built `collide = true` (`:725-735`), so it also stops
  shots and camera rays.
- **Every road block meets an open camp's floor only inside a gate span:**
  - Road5 and RoadAB1 span z −52…−36, A's gate span (A centre z −16, gate `at` −28, width 16);
  - RoadAB5 and RoadBC1 span z −52…−36, B's gate span (B centre z 2, `at` −46).
  - Nothing else outside a fence is standable at the floor's height.

So with chase cells, a chaser can only leave a camp through a gate, and **never walks through the
palisade**, because no cell lies beyond a fence anywhere but at a gate. A brute (radius 2.2) on
the road cell stands at z −49.8…−38.2, clear of the posts.

### Options

| | (a) Keep the fences, exits through the gates | (b) Wide openings | (c) No fences in grey |
|---|---|---|---|
| What Ben sees | a camp's raiders pour out of its gate and up the road | a camp open on its road side | open floors over the void |
| Cost | none beyond §1's doors | layout + `FenceBoxes` gate widths + `check_levels` | layout + gates; the sneak path and the sight gates change |
| Reads as | a real palisade: the gate is the bottleneck (a sword holds it) | the fence is decoration | a plinth, not a camp |
| Shots | the palisade still stops arrows, except through the gates and from the road inside the camp | more open lines from the road | every line open: more sniping from the road |

**Recommendation: (a).** It costs nothing new, reads best, and the funnel at the gate is good
drama. Natural barriers are L4's (Ben, §19). **Estimated.**

One thing for Ben's look (verified geometry, estimated aim):
- From Road5 west of A, the fence top (y 12) stops an arrow to A.fireW: the line crosses the fence
  at z ≈ −24, outside the gate.
- A.fireN is hittable through the west gate, and every group near the road is hittable from the
  road's stretch inside the camp (z −44, inside A's floor).
- PLAYTEST should say "shoot through the gate, or from the road inside the camp".

## 3. The chase rule

### What stands today (verified)

| Piece | Where | What it does |
|---|---|---|
| `CampBrain.InPlay` | `Svc/CampBrain.luau:317-339` | in the band, and within `chaseMargin` (2.5) of the **floor rectangle** (rounded corners), or within a keepAway member's reach |
| `Step`, fight | `:403-410` | `quietSince` resets while any target is in play; after `leashSeconds` (3) with none, and not striking → `home` |
| `Struck` | `:450-456` | an evading group (held or home) records nothing; otherwise `hit = true`, and the damage lands **only** from a player in play or `byUserId == 0` (**L1b-7**) |
| `Evades` | `:443-445` | held, or `home` |
| `Damage` | `Svc/CrowdService.luau:1896-1903` | asks `Struck` first; false → `(0, false, "blocked")` |
| `Think`'s `allowed` | `CrowdService.luau:652`; `CrowdBrain.luau:238-255`, `:909` | a fighting resident goes for the nearest target **in play** |
| The body clamp | `CrowdService.luau:353-376` | the chase stops at the floor's edge |
| `engaged` | `CrowdService.luau:1097-1108`, `CampBrain.Engaged` `:346-348` | in play for a group in rise or fight, held 1.5 s; feeds the rescue's i-frames (L1b-20) and Abandon's hide on touch |
| Phone auto-fire | `Ctl/CampAim.luau:41-51`, `Ctl/InputController.luau:1090-1102` | never in the countdown, never a resting body, else only while in play (clause 4) |
| Sight | `CampBrain.Sees` `:286-310` | distance and band (and a guard's cone), no ray: raiders see through walls and bends |
| Home | `CampBrain.Goal` `:485-490`; the heal at the post `CrowdService.luau:1020-1022`, `:933-938` | each member walks to its post, evades, and is healed on arrival |
| Join-in | `CampBrain.JoinIn` `:550-593` | a wake by sight or a hit brings in resting groups within `joinFactor` × the waker's sight |

### The new rule (recommended; numbers are guesses for the simulator)

Per group, per player, two facts:

1. **Known.** The player is seen within `camps.chaseSight` (all round, in the sight band) of any
   living member, or hit a member within `camps.hitMemorySeconds`.
   - The hit memory is what makes Ben's first scenario work: a bow hit from 80 studs is outside
     any sight, and the group must still come.
   - `Group.inPlay` becomes `known: { [userId]: number }`, the clock of the last sight or hit.
2. **Reachable.** `InPlay` with the floor rectangle replaced by the **region** (floor and cells,
   `chaseMargin` 2.5, rounded corners, the band), or within a keepAway member's reach, as today.

In each state:
- **rest:** unchanged (posture sight, cone, a hit, the join-in).
- **rise:** unchanged.
- **fight:**
  - members go for the nearest **known** player, reachable or not. One out of reach is walked
    toward until the region's edge stops them, so they come to the drop and stand there;
  - `quietSince` resets only while a **known and reachable** player exists;
  - after `leashSeconds` without one, and not striking → `home`.
  - So "out of sight for a few seconds" (Ben) is `leashSeconds` after the last sight or hit.
- **home:** the group walks home along the region's doors and **takes hits** (no evade, no
  BLOCKED). It heals at its posts as today. It turns back (`rise`, 0 s) only for a reachable
  player seen within its posture's sight, or a hit from a reachable player.
- **held** (the Chief's residents): unchanged. They evade and read BLOCKED until the close (L1b-13).
  Ben's "works as before".
- **patrol:** unchanged. Home is its post, then its loop.
- **join-in:** unchanged.

**What goes, stays, replaces:**

| Today | Wave 4 |
|---|---|
| L1b-7: damage only from a player in play | **goes.** `Struck` → true unless held; it records the hitter's clock in `known` |
| L1b-6: the chase stops at the floor's edge | **replaced** by the region (floor + cells, §1) |
| `InPlay` on the floor rectangle | **becomes "reachable"** on the region; the same rounded-margin code |
| `chaseMargin` 2.5 | **stays** (the region's rounded edge) |
| BLOCKED from a resident | **gone**, except held residents (and plates, which are not camp rules) |
| L1b-8: home evades | **amended:** home takes hits and turns back only for a reachable player |
| `Think`'s `allowed` = in play | **= known** |
| `engaged` | **stays**, fed by "known and reachable for a group in rise or fight", with the 1.5 s hold. The rescue grace (L1b-20) and Abandon's hide read it as today |
| CampAim clause 4 (in play) | **goes.** Clauses 1–3 stay: never in the countdown, never a resting body. A phone still never wakes a camp by itself, and once a group is up it is fair game anywhere |
| `check_levels` chaseMargin ≤ reach − √2·radius (`tools/check_levels.py:1226-1247`) | **goes** (it guarded L1b-7's farm) |
| The perch gate (`check_levels.py:1250-1279`) | **extended** to the region (§4) |

**The chase, timed** (estimated: speeds from `ProvingGrounds.json`, player walk 20; fodder 12,
slinger 11, brute 10, plated 9; `chaseSight` 40, `leashSeconds` 3; the lead's mock for Ben):

```
 A player who walks out of A's east gate with fodder 3 studs behind him, and keeps running:

 t = 0 s     gate ......... he at  0, fodder at  -3      (the gap grows 8 studs/s)
 t = 4.6 s   he at 92, fodder at 55: out of the fodder's 40 → nobody sees him
 t = 7.6 s   3 s unseen → the group turns home, the fodder at about 91 studs out,
             just short of A's border at the U-bend (98 walked, option (a) below)
 t ≈ 15 s    back at their posts, healed; the dead stay dead

 West instead: they stop where the road drops 8 studs (38 out), he is below their sight band
 (4 under the floor), unseen at once, and they turn home 3 s later.
```

## 4. Exploits once BLOCKED goes

No refills (Ben §16.5) bounds every exploit: the worst a player can do is clear a camp slowly
and safely. It can never farm money. That changes the question from "can it pay forever" to
"does it pay more per minute than fighting", which `sim_range.py` can measure.

| Exploit | Rule (recommended) |
|---|---|
| **Sniping from where rushers cannot reach:** the lookout ledge (+26 over Road5, in band since `sightAbove` is 30), the cache block (+10), below A's west drop (−8), past the territory's border, and the 3.5-stud cover blocks | Hits land (Ben). Rushers come to the region's edge, can do nothing, and go home after `leashSeconds`; they turn back only for a reachable player. **Shooters answer high ground:** a slinger's shot reaches a player on a block (P4 ruling). A gate keeps every standable top over the band's melee height inside the region's margin within a slinger's reach (32) of some region point. The lookout ledge and the cache pass (both touch the road). Proof: a new `sim_range` policy, "the sniper", stands below the drop and on the ledge with the Longbow, and must earn less per minute than the `mission` player |
| **Kiting** (he runs at 20, nothing follows faster than 12) | Kept, as a known limit (P4: "kiting a big circle avoids everything"). The hit memory pulls the group after an archer; its slingers follow and shoot. Bounded by no refills. Proof: the existing `kite` policy measures the pay per minute |
| **Kiting between two camps, dragging a camp into the next** | **Territories:** two camps' regions share at most a border and never overlap, and no region holds another camp's floor. A's raiders can never reach B's floor; at the border a player fights both, which is honest. A gate on the cells |
| **Shooting into the boss room from outside** | Every open camp's region stays at least the longest resident reach (marksman 48 on Hard) + 8 from a locking camp's floor rectangle (a gate). At the boss room's close, every awake group of every other camp loses every player (its `known` is cleared), so it goes home |
| **Pulling one group at a time** | Allowed: it is the bow's job, and the join-in (`joinFactor` 2) already brings neighbours. No rule |
| **Holding the gate** (a sword in the 16-stud gap while the camp funnels out) | Allowed. Separation keeps the funnel honest |
| **A fall off the road to escape** | Unchanged: the rescue gives no i-frames while engaged (L1b-20) and puts him on the safe point |

### The question this leaves for Ben

Ben's rule "a hit from anywhere lands" fixes the hit. It does not say what raiders do when they
cannot reach the shooter. See Q2 in §9.

## 5. The tent as a pace reserve

### What stands (verified)

- **Active** while the camp is busy, **or** once no resident lives (`CampBrain.TentActive`,
  `Svc/CampBrain.luau:633-635`). One body every `every` (6 s) from the first wake
  (`TentDue` / `TentSent`, `:638-645`). The executor is `WaveService.tickTents`
  (`Svc/WaveService.luau:1599-1644`).
- **An open camp clears** only when its floor is empty **and** its tent's stock is spent
  (`Svc/StageFlow.luau:1546-1562`, `Input.tentLeft`; fed at `WaveService.luau:1395-1405`).
- **The clear bonus** is `share` × the whole stock, residents and tent
  (`Combat.ClearBonus`, `src/shared/Combat.luau:867-881`; `WaveService.campCleared`, `:773-791`).
- **The director's tempo** is kills inside `director.windowSeconds` (10) against the wave's
  budgeted kill rate, clamped to [0.7, 2.0] (`WaveService.updateTempo` `:461-477`,
  `Combat.Tempo` `Combat.luau:553-564`).

### Measured (verified, sim_range `mission` policy, Normal, seeds 11, 23, 37)

| | Tents as shipped (2 / 2) | No tents (2 / 2) | No tents (4 / 4) |
|---|---|---|---|
| First clear | 6.93–7.17 min | **6.17–6.41 min** | 3.59–3.84 min |
| A: first wake → clear | 46.7 s (the 8th tent body at +42 s sets it) | **20.5–22.5 s** (30 residents) | 13.0–13.9 s |
| B: first wake → clear | 141–160 s | **118–131 s** (46 residents) | 55–65 s |
| Paid | 171,080 cash, 282 Timber | 155,020 cash, 258 Timber | 151,420, 258 |
| Timber a minute | 39.3–40.7 | **40.2–41.8** (band 37.8–46.2) | — |
| Cash a minute | 23.9–24.7k | 24.2–25.1k | — |

So "no waits" costs about 0.6 minutes of the simulated first clear, and nothing per minute. These
runs use today's chase rule (bodies clamped to their floors); the new one brings bodies to the
player and will move them a little.

### How to measure "clearing too fast"

| | (a) The camp's clock **[recommended]** | (b) The director's window |
|---|---|---|
| Rule | the camp's clock runs only while the camp is busy. It is ahead when `killed / residents − busySeconds / pace.seconds ≥ pace.lead` | `Combat.Tempo(kills in the last windowSeconds, windowSeconds, residents / pace.seconds)` ≥ `pace.tempo` |
| Bursts | smooth: a fire group of eight cleaved in 3 s does not trip it unless the whole camp is ahead | a group wipe spikes it: eight kills in 10 s is tempo 0.67 against A's 1.2 kills/s, but 2.3 against B's 0.35/s, so in B it would send after every quick group |
| A player who leaves and comes back | the clock stops while the camp rests | the window empties |
| Cost | one pure function and a busy clock per camp | reuses `Combat.Tempo` |

**Recommendation: (a)**, a guess about which reads better. The designer runs both in scratch and
reports. Keys per open camp in the level file: `tent: { every, units, pace: { seconds, lead } }`.

The pure rule is `CampBrain.TentActive(busy, residentsAlive, ahead)`:
`busy and residentsAlive > 0 and ahead`.
- It never sends once the residents are dead (§19: "a camp is cleared as soon as its raiders are
  dead").
- `TentDue` and `TentSent` are unchanged: one body every `every` from the moment the camp is first
  ahead. The stock (8) is the most it ever sends.

**Targets (guess, from the table):** A `pace.seconds` 25, B 130, `lead` 0.15. The bands that prove
them, in `sim_range --check`:
- the `mission` player at the recommended gear: each tent sends at most 1 body, every seed;
- the same player one preset **above** (Normal at 4 / 4): A's tent sends at least 2 bodies and
  B's at least 4;
- Hard and Brutal at their recommended gear: at most 1 (their clears ran within ±1 min of Normal's
  in Wave 2, BALANCE "L1b W2: results"; a per-difficulty `paceScale` only if this fails).

**The clear:** an open camp is cleared when nothing lives on its floor. That counts the tent
bodies already out, wherever they are on the road, because a body keeps its floor index for life.
- The `tentLeft` clause goes from `StageFlow.progress` (`:1555`) and from `Input`.
- Stock left is forfeit.

**The clear bonus** (Ben's "about 10% of what that camp's raiders pay"):

| | (i) What the camp fielded **[recommended]** | (ii) As today, the whole stock | (iii) What the party killed |
|---|---|---|---|
| Rule | residents + the tent bodies sent | residents + the full stock, sent or not | the camp's kills |
| A normal pace | residents only | pays for 16 bodies he never saw | = (i) at a clear (a cleared camp killed everything it fielded) |
| A fast clear | gains on its extra kills | the same as anyone | = (i) |
| Change | `WaveService.campCleared` passes residents + sent | none | the same as (i) in practice |

At a clear, (i) and (iii) are the same number, because a cleared camp has killed all it fielded.
(i) is the cheaper to write.

**Bands this moves:**
- **Normal first clear:** `FOREST_CLEAR_SECONDS` (390, 480) at `tools/sim_range.py:4890` fails at
  about 370–385 s. Re-band to **345–420 s** (5.75–7 min). Ben at about ×1.36 is about 8.4–8.7 min.
  The lead's ruling: the time removed was waiting, which is what Ben asked to lose.
- **Timber a minute 37.8–46.2:** holds (measured 40.2–41.8).
- **Bonus 5–10% of the clear:** re-measure (it shrinks with (i)).
- **`targetMinutes`:** 7 → 6 by Wave 1's rule (the mean, rounded).
- **`runCapSeconds` 1500:** holds.
- **The `tentAlone` and the "tents 8 of 8, 6.0 s apart" scenarios:** replaced by the pace bands
  above.

## 6. Camp state off the camp

All verified in the code; "no change" means the existing code is right once bodies walk the road.

| Piece | Where | Wave 4 |
|---|---|---|
| A body's floor index for life | `CrowdService.luau:111` (`floor`) | the region rides on it: no new index |
| A camp's alive count | `CrowdService.AliveOn` `:2189`, kept per floor at spawn and death | **no change**: a raider on the road is still its camp's |
| An open camp's clear | `StageFlow.progress` `:1546-1562` | only the `tentLeft` clause goes (§5) |
| Dormancy | `CampBrain.Dormant` `:516-528`: only at `rest`, judged by the distance to the **floor rectangle** | **no change**: a group out on the road is never at rest, and a resting group stands at its posts |
| `fieldClear` on the road | `StageFlow.FieldClear` `:1385-1391`: nothing awake anywhere | **no change**: a solo down mid-chase still ends the run (Ben's rule); a quiet road still costs a respawn |
| Busy, threats, the safe point | `CrowdService.Busy` `:2206`; `StageFlow.SafePoint` `:1903-1937` (threats from **positions**) | **no change**: A's checkpoint (x −150) lies in A's region and is skipped while A is busy or a shooter reaches it. The `check_levels` gate "checkpoint out of every resident shooter's reach" (`check_levels.py:1187-1191`) still holds for resting posts and stays |
| Population | `StageFlow.BossReserve`, `populationOf` | **no change**: a chase spawns nothing. Two camps out at once is the same bodies. The tent now sends fewer, so the gate's left side is an upper bound |
| Snapshot bytes | every non-dormant body, 11 bytes (`CrowdCodec.luau:10-17`) | **no change**: the same bodies; at most two camps awake |
| The Chief's Clearing | held groups (`CampBrain.Step` `:387-391`); the gate does nothing on the crowd (L1b-14) | its region is **its floor only** (no cells; `Validate` refuses cells on a locking camp). Held residents read BLOCKED before the close, as before. **New:** at the close, every other camp's awake group loses every player (`known` cleared), so nothing waits at B's border |
| The rescue | `StageFlow.IsOut` `:1970-1996` (the level box outside the boss room) | **no change** |
| Engaged, Abandon | `CrowdService.Engaged` `:2219-2222`; `CombatHud` hides Abandon on touch | fed by known and reachable (§3) |

## 7. The simulators and the tools

| Tool | Goes | Changes | New |
|---|---|---|---|
| `tools/sim_range.py` | `IN_PLAY_STEP` and its use in `LevelRun.wanted` (`:333`, `:6637-6650`); the `cb_struck` gate in `LevelWorld.damage` (`:6067-6077`); the `edge` scenario's "0 paid" (`edge_runs` `:7537`) | `body_box` (`:6257-6262`) clamps into the region; the bodies' goals route through doors; `cb_in_play` uses the region; `cb_step` with known and hit memory; `LevelRun.steer`'s `near`/`awake_in` (`:6524-6534`) accept a fight on the road; the tent (`send_tents` `:6300`) runs on the pace rule; `FOREST_CLEAR_SECONDS` (`:4890`) | a `Region` mirror; scenarios: **the road archer** (Ben's scenario 1: hit from the road; the group wakes, comes out, reaches him or loses him), **the walk-out** (his scenario 2), **the lose** (scenario 3: home and healed within N s), **the sniper** (below the drop, on the ledge: pays less per minute than `mission`), **the pace** (tent sends at recommended gear and one preset above) |
| `tools/check_stage_mirror.py` | the `InPlay`, `Struck` grids on the floor rectangle (`:1113-1180`) | `Step`, `Struck`, `InPlay`, `Rouse`, `Engaged` on the new rule; `TentActive` | `Region` (`Clamp`, `Contains`, `Runway`, `Toward`, the next-hop table) on grids; the pace function; `ClearBonus` on the fielded stock |
| `tools/crowd_harness/` | cases that read BLOCKED from out of play or from home (`tests_l1b_crowd.luau:298`, `:680-681`, `:744`); mutations on in play, `Struck` and CampAim (`mutate.py:1896`, `:2058`, `:2692`, `:2887`) | `tests_l1b_crowd`, `tests_l1b_w2_crowd`, `tests_l1b_w2` (tent active, the clear with stock left) | `tests_l1b_w4_crowd.luau` (A) and `tests_l1b_w4.luau` (B), and a mutation per new rule. `mirror_mutants.py` gains the `Region` and pace mutants. `mutate.py` is about two hours: background it |
| `tools/check_levels.py` | chaseMargin ≤ reach − √2·radius (`:1226-1247`) | the perch gate (`:1250-1279`) over the region; the sneak gate untouched (resting sight is unchanged) | the cells: standable at the floor's height, door overlap ≥ 2·rmax + 0.5, a tree, disjoint territories, out of every other camp's floor, ≥ longest reach + 8 from a locking floor, none on a locking camp; every high top in a region within 32 of a region point; the pace keys |
| `tools/sim_combat.py` | — | `level_pay` with the fielded bonus | — |

## 8. Ben's look without the panel

He uses Play and keys only; Play must open on the thing to judge (memory, P4).

- **Today:** N on the road moves the party to the next **locking** camp's entry and starts its
  countdown (L1b-22; `Ctl/CombatUIController.luau:156`, `Svc/StageFlow.luau:1706-1805`). B goes
  to the boss's wave, and G cycles gear (`:157-158`).
  - So the Chief's Clearing is one key away already.
  - The sneak past B is not: it needs a walk through A first.

| | (a) N steps through every camp **[recommended]** | (b) `debug.provingStart` | (c) A new key |
|---|---|---|---|
| What | N on the road moves the party to the next camp's **approach**, open or locking: a route point outside every resting sight (B: (−108, 8, −44), 61 studs from B.fire1). At a locking camp it starts the countdown as today | Play departs and places the party at a named camp's approach | e.g. J = the next open camp's approach |
| Ben's path | Depart → A (the bow, the chase, the tent) → N → B's approach (sneak along the inside of the north fence, z −60.5) → N → the Chief's countdown | the config decides one stop per build | one more key to remember |
| Cost | `StageFlow.Skip`'s road branch; `DebugService`; harness skip cases; PLAYTEST | `Combat.json`, `WaveService` | `CombatUIController`, `DebugService` |

**Recommendation: (a).** One key he already knows. **Estimated.**

## 9. Questions for Ben (recommendation first)

### Q1. How far do the raiders follow you?

```
(a) HALFWAY TO THE NEXT CAMP  [recommended]
     drop 8                                     U-bend                     
  ...._|=====[  A  ]==============+     +============[  B  ]=================+ ...
       |  38     gate      98     | A|B |     98       gate        136       |  (C is 247 on)
       <- A's ->         <-- A's road -->< B's road >          <-- B's road -->
   they stop at the drop;   they follow to the middle of the road, then go home
   in practice they lose you (3 s unseen) about 90 studs out, before the border binds

(b) THE STRAIGHT STRETCH ONLY
  ...._|=====[  A  ]=====+                   +=====[  B  ]=====+ ...
       |  38       49   ^bend               bend^ 38        49  ^bend
   they stop at the first bend, often while you are still in sight

(c) ANYWHERE ON THE ROAD
  ...._|=====[  A  ]======================================[  B  ]=====> ...
   A's raiders can follow you to B's gate and fight beside B's
```

### Q2. You shoot raiders from a spot they cannot reach (a ledge, below a drop). What do they do?

```
(a) THEY GIVE UP  [recommended]
   [ A ]=====XXXX|        X = raiders at the edge of the drop (8 studs up)
                 |__ you  every hit lands; they stand 3 s, walk home, heal; the dead stay dead
   (slow, safe, and pays less per minute than fighting; the simulator proves it)

(b) THEY SHRUG IT OFF
   [ A ]=====XXXX|
                 |__ you  once they cannot reach you, every hit reads EVADE until they are home
   (no cheese at all, but it is the BLOCKED he asked to remove, in a new word)
```

Fences (§2), the tent's measure (§5), the bonus (§5) and N (§8) are technical. They are the lead's
decisions with the recommendations above, said to Ben with the chase mock (§3) at the same time.

## 10. Owners and the wave plan

### Owners (disjoint)

| Owner | Files | Pure / executor |
|---|---|---|
| **luau-engineer A** (the crowd) | `src/shared/Types.luau` (first edit, before anyone builds: `CrowdFloor.cells`, `RunFloor.cells`, `CampGroupDef.region`, `CampRulesConfig` new keys, `LevelCamp.chase`, the tent's `pace`); new `src/shared/Region.luau`; `Svc/CampBrain.luau` (known, reachable, the fight and home rules, `Struck`, `TentActive` with `ahead`, the pace function); `Svc/CrowdService.luau` (region clamp, door routing in `integrate`, the hit memory in `Damage`, `known` in `campStep`, `Engaged`, `LoseAll` at the close); `Svc/CrowdBrain.luau` (`inArena`, `runway` on the region); `tools/crowd_harness/tests_l1b_crowd.luau`, `tests_l1b_w2_crowd.luau`, new `tests_l1b_w4_crowd.luau` | `Region`, `CampBrain` pure; `CrowdService`, `CrowdBrain` executors the harness loads |
| **luau-engineer B** (the run) | `Svc/StageFlow.luau` (`Plan`: zones and defs carry the region; `Validate`: cells and pace keys; `progress` without `tentLeft`; `Skip`: N steps through every camp); `Svc/LevelGeometry.luau` (cell boxes for `Validate` and the bounds; no Parts); `Svc/WaveService.luau` (`SetFloors` with cells, `RunFloor.cells`, `tickTents` on the pace rule, `campCleared` on the fielded stock, `LoseAll` at `close`); `Svc/DebugService.luau` (N); `src/shared/Combat.luau` (only if `ClearBonus` takes the fielded stock as an argument); `tools/crowd_harness/run_harness.py`, `mutate.py`, `tests_l1b.luau`, `tests_l1b_w2.luau`, `tests_l1.luau` (the skip cases), new `tests_l1b_w4.luau` | `StageFlow`, `LevelGeometry`, `Combat` pure; the rest executors |
| **ui-engineer** | `Ctl/CrowdRenderer.luau` (`SetFloors` with cells, `laneReach` through `Region`, no new top-level local: it is at 152); `Ctl/CampAim.luau` (clause 4 goes); `Ctl/InputController.luau` (only if `CampAim`'s signature changes); `Ctl/CombatUIController.luau` (N's label); `Ctl/FeedbackController.luau` only if Ben picks Q2 (b) | executors |
| **economy-designer** | `Config/Combat.json` (`camps.chaseSight`, `camps.hitMemorySeconds`); `Config/Levels/1_ForestRoad.json` (`tent.pace`, `targetMinutes`); `Layouts/Levels/ForestRoad.json` (`chase` cells for A and B by Q1); `tools/sim_range.py`, `tools/sim_combat.py`, `tools/check_levels.py`, `tools/check_stage_mirror.py`, `tools/crowd_harness/stage_mirror.luau`, `tools/crowd_harness/mirror_mutants.py`; `docs/BALANCE.md` "L1b Wave 4" | data and mirrors |

A lands `Types.luau` and `Region.luau`'s signatures first (as in every L1b wave). B registers A's
test files and mutations.

### Wave plan

One building wave, as the brief says, then Ben's look:
1. **Before the contract:** Ben answers Q1 and Q2 by click questions, with the chase mock of §3
   (and the Q1 sketch) as the picture.
2. **The contract** "Wave 4 — no waits, no walls" in `docs/INTERFACES.md`, drafted by one Opus
   agent and checked by the lead, with the rulings L1b-W4-n mapped against §3's table.
3. **Four owners in parallel** (above), each from a brief file.
4. **A four-slice Opus review** (the crowd, the run, the client, the data and tools).
5. **Fresh fix agents** from a fix-list file.
6. **One fix-diff reviewer**, then QA. `mutate.py` takes about two hours: background it, and
   expect qa-runner's 15-turn limit (resume it by id for the report).
7. **docs-keeper:** PLAN, PLAYTEST "L1b Wave 4", about eight key-only steps:
   - the bow from the road through A's gate;
   - walk in, wake, walk out;
   - run until they lose you;
   - a normal clear with no tent;
   - G to 4 / 4, then a fast clear with the tent;
   - N to B's approach and the sneak;
   - N to the Chief's Clearing (the Colossus, the headshots);
   - the Server number;
   - click questions at the end.
8. **Merge** (the L1b merge rule) and rebuild the six place files.

A numbers-only Wave 4b runs only if his look asks for one.

### Review cost (estimated)

- **The slice review:** four Opus slices, about 1.9M tokens (the cost recorded on L1, memory
  "agent-context-cost").
- **The fix-diff review:** about 0.3–0.5M.
- **The four builders:** comparable to L1b Wave 2's.
- Say the total to Ben when planning: the review alone is a large share of a session.

## 11. Decisions for the lead before the contract

1. A region per camp at one height, authored `chase` cells, no reshaping, no per-body floor (§1).
2. A pure `Region` module with door routing, shared by the server, the client and the mirror (§1).
3. Keep the fences; exits through the gates (§2).
4. The chase: known (`chaseSight` about 40, `hitMemorySeconds` about 8, both guesses) and
   reachable (the region). `leashSeconds` 3 is the "few seconds" (§3).
5. Home takes hits and turns back only for a reachable player; held residents unchanged (§3).
6. CampAim loses its in-play clause (§3).
7. Territories disjoint, out of other camps' floors, at least the longest reach + 8 from a locking
   floor. At the close, every other camp loses every player (§4, §6).
8. The tent on the camp's clock (A 25 s, B 130 s, lead 0.15: guesses), never after the residents
   are dead; the clear when the floor is empty (§5).
9. The bonus on what the camp fielded (§5).
10. The Normal first-clear band 345–420 s; `targetMinutes` 6 (§5).
11. N steps through every camp (§8).

### Rulings this wave overturns or amends (for the contract's map)

| Ruling | Fate |
|---|---|
| L1b-6 | in play → reachable on the region; the chase leaves the floor |
| L1b-7 | gone |
| L1b-8 | home takes hits, turns back for a reachable player, still heals |
| L1b-1 | a floor gains cells (same height, same index) |
| L1b-13 | kept |
| L1b-20 | kept, fed by known and reachable |
| L1b-22 | N steps through every camp |
| L1b-W2-7 | the tent sends only while busy, ahead and with residents alive |
| L1b-W2-8 | gone: the floor empty is the clear |
| L1b-W2-21 | the bonus on the fielded stock |
| L1b-W2-25 | kept |
| Wave 1 Major 1 | its chaseMargin gate goes; the rounded margin stays |
| Wave 1 Major 3 | CampAim clause 4 goes |
| Wave 1 data Minor 1 | the resting-shooter checkpoint gate stays |
| Wave 3 | `IN_PLAY_STEP` goes |
