# L2 W3 fix-diff review (2026-10-19, `8112ff3..25528b7` in `tycoon-p5b`, branch `l2-w3-fix2`)

Scope: both fix rounds (`docs/prompts/l2-w3-fix-round.md`, `l2-w3-fix2.md`), against the findings in
`server.md`, `client.md` and `data-tools.md` and the contract's §14 Q1–Q4. Read-only. The tools ran on a
`git archive HEAD` (429a448) copy in the session scratchpad.

**Result: 0 Critical, 0 Major, 2 Minor, 2 Suggestions.**

Every finding of the three slices is fixed in the code, not only in its test (table below). Both Minors are side
effects of the fixes themselves:
- fd-m1 comes from d-m1's whole-cell cover;
- fd-m2 comes from d-m6's thickness of 4, with Q5's body rule judged on the server's copy.

## Minor

**fd-m1. `src/combat/server/Services/LevelGeometry.luau:796-813` (iceCells, d-m1's whole-cell cover) with
`src/shared/Layouts/Levels/ForestRoad.json:321` (ShrineIsland): two cells beside the island now have their south
face on the island's own south face.**
- **What.**
  - The island (z 120..136) ends exactly on a pond row line. The rows are 6.667 deep from z 96, so row 5 is
    129.33..136.
  - Before d-m1, the cells beside the island (columns 4 and 6, rows 4 and 5) were not built. Now they are.
  - The south faces of Pond (i 4, k 5) and (i 6, k 5) lie at z 136 and face +z. That is the island's own south
    face: 4.73 × 3.2 studs each (x −408..−403.27 and −396.73..−392, y −4..−0.8).
  - The probe compared the 136 pieces with every block (water included) and every secret. It found these two
    same-facing coplanar pairs and no others. Q6's inset cleared every water face.
- **Scenario.**
  - Ben crosses to the island, opens the chest and turns to look back north. The shoulder camera sits south of the
    island, over the pond.
  - His last swing froze (4, 5). The cell south of it, (4, 6), stayed water because it was outside the sector.
  - The opaque ice (150, 208, 245) and the grey island (108, 110, 116) then z-fight. In full view this is a
    0.2-stud strip at the waterline (y −1..−0.8). Over the 3 studs below it, it shows through the 0.2-transparent
    water.
  - This is the shimmer Q6 was written to remove, now on the island.
- **Why no gate sees it.**
  - The fill line counts area. check_stage_mirror compares boxes. Nothing compares faces.
  - Insetting that face in code would open a 1.82 × 0.05 slit where the cell runs past the island
    (x −409.82..−408). The fill line would rightly call that a hole.
- **Fix: data plus a gate.**
  - Move the island off the row line, for example z 128 → 128.5 (120.5..136.5). Then:
    - rows 4 and 5 of column 5 stay whole under the island;
    - row 6 becomes part-covered;
    - both of the island's z faces lie mid-row;
    - the chest's trigger (z 122.5..133.5) stays inside the island;
    - the sign-pad margin moves by 0.5.
  - Add a check_levels line, red on today's layout: no face of a built ice piece lies on a same-facing face of
    any block or secret. My probe is that rule in 40 lines over `sim_range.ice_cells`:
    `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\256ff021-038b-414c-a980-1bba37f320cf\scratchpad\w3fd\probe\coplanar.py`
    (it reports 2 pairs today).

**fd-m2. `src/combat/server/Services/LevelService.luau:654-709` (`bodies()` → `Freeze`) with
`src/shared/Config/Combat.json:163` (`thickness` 4): the body rule reads the server's copy of each body. That copy
trails the body's own screen by its round trip. At thickness 4 a body's root can end up wholly inside a fresh
cell; at thickness 1 it could not.**
- **What.**
  - `WorldReact.Holds` judges feet and height on the replicated root.
  - Take a body that went into the water within its round trip. On the server it still reads "on the edge" or
    "just under the top" (feet at or above −1.3, the first 0.115 s of a walk-off from the bank). So the cell
    freezes.
  - The cell turns solid on that body's screen one round trip later. By then the body has fallen further.
  - Probe `w3fd\probe\embed.py` (the root is 2 tall, at feet + 2..+4; the cell is −4.8..−0.8):

    | Round trip | Thickness 1 | Thickness 4 |
    |---|---|---|
    | 0.10 s | 1.0 stud of the root inside | 1.73 inside |
    | 0.15 s | 1.0 | 2.0: wholly inside |
    | 0.20 s | 1.0 | wholly inside |
    | 0.25 s | 0 | wholly inside |

- **Scenario 1, a teammate.**
  - B walks off the bank into the creek while A, grounded at the frozen edge, swings at that water.
  - The server's copy of B still reads feet −1.0, so the cell freezes.
  - With B's 150 ms round trip, the cell is solid around his whole root on his screen.
  - Q5's brief promises "a teammate in the water is never encased". That holds only at zero lag.
- **Scenario 2, the swinger (L2-65).**
  - A swings at the frozen edge and keeps walking onto his own ghost, which does not collide.
  - His server copy is still on the ice when the server freezes, so `Holds` sees nothing.
  - On a 0.15 to 0.25 s link, the cell arrives around his root. With d-m6's thickness, L2-65's "may fall" has
    become "may be encased".
  - Phones are mostly spared: auto-swing fires as soon as open water is within 13 studs, well before the edge.
- **What happens then is Studio's to say.**
  - The engine may push the root out (up onto the ice, down to the rescue, or sideways into open water), fling
    it, or leave it jittering.
  - Reset Character is off in the combat place. A body that stays stuck has only Abandon.
  - The fix2 report's Studio list checks only a swing made while falling, at zero lag.
- **Fix.**
  1. **Server lead.** Before `Holds`, lead each body's feet by its fall over the lag:
     - `BodyBox(..., drop)` with `drop = max(−vY, 0) · lag + ½ · g · lag²`;
     - only for a body that is not grounded this frame (WeaponService's `stood` is not its position);
     - `lag` = `Tuning.CommitLag(shooting, ping)`, capped like the claim slack.

     Probe `w3fd\probe\embed2.py`: this closes the teammate window fully up to a 0.15 s round trip. Add a harness
     case: feet −1.0, falling at 19.8, with lag 0.1, holds.
  2. **The swinger's own step-off.** A body still standing on the server when the swing lands cannot be led. Pick
     one:
     - Cap `thickness` under the root's height, for example 1.9, so the root never fits wholly inside. A slam at
       140 studs/s and 240 Hz moves 0.58 a step, so it still cannot tunnel. Record the ruling against d-m6's
       floorThickness rule.
     - Or keep 4 and add a PLAYTEST step with Studio's network simulator at 150 to 250 ms: "swing at the frozen
       edge and keep walking: you stand on the new ice or fall through to the landing, never stick".

## Suggestions

**fd-s1. `src/combat/client/Controllers/InputController.luau:1432` (`iceOnAuto`): the phone and the server ask
"airborne?" two different ways.**
- The phone asks the Humanoid (`FloorMaterial`). The server's Q5 verdict is SwingGate's footprint test at the
  claim. `autoIceStrike` (`:1401`) then states `airborne = false`.
- The two agree only while the Humanoid's floor sensor is no wider than the root's 2 × 1 footprint, which is a
  Studio unknown.
- If the sensor is wider, a phone standing on the bank's very lip (no footprint corner on the bank, the Humanoid
  still standing) auto-swings at the full rate. Every swing freezes nothing, and the first spends the jump's air
  swing.
- `AirSwing.Judge(root.Position, root, humanoid)` has no side effect at the client's lag of 0, and it is the
  server's own question. Use `if not allowed or inAir then return false`, and let the strike carry `inAir`.

**fd-s2. The 0.1-stud creek-to-pond seam shows as a grey line across the crossing.**
- The seam is Q6's inset on the faces the two ice blocks share. At the shoulder camera the line is about 2 to 3 px
  wide.
- The z-fight it prevents at that shared face would lie under the water's top, seen through 0.2-transparent water.
  At a face open to the void, the z-fight would be in full view.
- If Ben reads the seam as a crack (the fix2 report's Studio step 5), inset only the faces that meet open air or a
  block that is not ice.
- No body falls through the seam: the root is 2 × 1, and the footprint's corner rays always straddle 0.1.

## Each finding, answered in the code

| Finding | How it is fixed | Verdict |
|---|---|---|
| s-M1, Q3 | `trackAir` records `stood` on the footprint floor's grounded verdict, reusing the air gate's 5 rays. `rescueFallen` → `FallLanding(..., stood, outside)` tests the stood point first, then the current position. Any `collide == false` block with a landing is a water. | Fixed. Every server body move clears `stood` (see Verified). |
| s-m1, d-m5 | `SizesOf`/`IceOf` live in LevelGeometry, and the harness loads them with the shipped config. React's early guard is gone. `IceLook`, `Reactive` and `IceReach` are pure. The applying lines are source-checked, with a mutant each. | Fixed |
| s-s1 | Recorded as a known limit (fix-server, BALANCE). | Accepted |
| s-s2 | Validate, its mirror and the check_levels overlap line (touching is allowed). | Fixed |
| s-s3 | `WorldReact.ICE_ATTRIBUTE` is the only "Ice" in `src`. | Fixed |
| c-m1, c-s2 | Boxes cached at adopt, an open list kept by the `Ice` signal, the bounds early-out, and the callback stops the walk. | Fixed |
| c-m2 | Ghosts held by seq: the answer starts a 0.3 s grace, a refusal drops them, and a 2 s cap covers a lost answer. `finish` broadcasts every melee strike, so the answer always comes. | Fixed |
| c-m3 | `SwingStrike` is used in `resolveMelee` and in all three client copies. Source checks and mutants cover step, pad, airborne and the call arguments. | Fixed |
| c-m4 | No auto-swing at water while airborne. | Fixed (fd-s1) |
| c-s1, Q4 | One ring at 32. Shards are spaced by circumference (36, or 18 on low-end). One floor ray per shard, with both random draws before the test. | Fixed |
| d-m1 | Whole-cell cover. The fill line is exact and allows only the inset rim. | Fixed (fd-m1 is its side effect) |
| d-m2 | Targets 75 / 439. | Fixed |
| d-m3 | Leap Smash's fall term, with a red mutant and a green control. | Fixed |
| d-m4 | The island-at-48 mutant. | Fixed |
| d-m6 | Thickness 4, and `ice` in GROUND_LOOKS. | Fixed (fd-m2 is its side effect) |
| Data suggestions | Aliases followed. Bend, cave (closed half) and walled checks on the frozen layout. Shrine 60. | Done |
| Q1, Q2 | `iceAutoDegrees` 34. Frozen cells take the ground look's grip (SmoothPlastic). | Done |
| Q5, Q6 | Air swings never freeze; a held cell stays water; edge cells inset by 0.05. | Done (fd-m2, fd-s2) |

## Verified (safe to rely on)

- **Every server body move clears `stood`.**
  - `ArenaService.MoveMember` is the one move function. It covers the rescue, the N and B lever skips, the lobby,
    the stand-up and the start points. It calls the moved hook, which is `WeaponService.ForgetMotion`.
  - `moveFighters`' GateNudge `PivotTo` calls `ForgetMotion` itself.
  - `resetAir` and a vanished body clear it too.
  - A stale client frame after a lever move can re-record the old spot for a frame. The body stands at its new
    place before it can fall again, so this is harmless.
- **A claimed grounded spot buys nothing.**
  - Every landing is on Road2, behind the main path. Fight and breather never land.
  - By ruling there is no movement anti-cheat, so a cheating client already moves freely.
  - A diagonal overshoot from Road1 that falls inside CreekUp's margin lands on Road2. That is the one-jump gap a
    first run crosses anyway.
  - A walk-off at Road2's far end, or from the Road1 gap, still goes to the safe point.
- **Q5's airborne verdict is geometric.**
  - It is `SwingGate.Judge`'s `IsAir` at the clamped claim, tested against the footprint floor (worldParams). The
    "landing ahead" branch changes only `allowed`.
  - So the crossing's first swing from the bank lip (a footprint corner over Road2) is grounded on both sides, and
    it freezes.
- **`Holds` never holds a body standing on a top.** That covers the bank (0), the ice (−0.8), the island (0) and the
  part-covered cells under the island. The 0.5 sink keeps the cell beside a standing body freezable.
- **c-m2: refusals come only from RangeStats** (WeaponService's attack seq). AbilityService's `refusedSeq` rides its
  own remote, so an ability refusal never drops a swing's ghosts.
- **The ForEachIce quick test is Chills' own.** The band is `origin.Y ∈ [low, high + reachDown]` (plus 0.01), and the
  distance is measured to the rectangle of cell centres.
- **FrostQuake's floor rays** ignore the ArenaBarrier group. Water and open cells are CanQuery false. So shards stand
  only on the road, the bank and frozen ice.
- **INTERFACES** has the as-built lines for both rounds.

## Gates (scratch archive of HEAD 429a448)

| Gate | Result |
|---|---|
| Harness | PASS, 3,127 checks |
| `check_levels.py` | PASS, including the new lines: fall, overlap, fill, and inset and sink |
| `check_stage_mirror.py` | PASS (ice cells: 7 views compared box by box) |
| `py -3.12 sim_range.py --check` | PASS, 524 lines, 0 FAIL. Crossing 9 swings, 5.8 s ideal. Hammer 75 / 439. |
| `check_compile.py` | PASS, 174 files |
| luau-lsp | Combat and default sourcemaps both exit 0 |
| selene | 0 / 0 / 0 |
| stylua | Clean |
| `rojo build combat.project.json` | Builds |

Probes, in `C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\256ff021-038b-414c-a980-1bba37f320cf\scratchpad\w3fd\probe\`:
- `coplanar.py`: fd-m1;
- `embed.py`: fd-m2, by thickness and round trip;
- `embed2.py`: fd-m2, with the lead fix and thickness 1.9.
