# L1b Wave 2 review: slice 3, client

Diff `main..f40509a` on `l1b-wave2`. Read in full: `CrowdRenderer.luau` (the seed path,
`pushSample`, `sampleAt`, `onSpawn`, `onRemove`, `step` and the public queries), `SpawnSeed.luau`,
`AirSwing.luau`, `InputController.luau` (`campInPlay`, `enemyInSights`, `dueShots`,
`wantsRangeAttack`, `rangeAttack`, `rangeStep`), `FeedbackController.luau` (`paintBurst`,
`onStrike`, `drawPellets`), `CombatHud.luau` (the perf line and the layout pass) and `Theme.luau`.
I also read the server halves they must agree with: `WeaponService` (`floorUnder`, `trackAir`,
`resetAir`, the `OnAttack` gate), `CrowdService` (`refreshInfo`, `sendSnapshot`), `HitShapes.CrowdRay`,
`MovementController`'s state changes, and `ForestRoad.json` with `1_ForestRoad.json` for the
checklist.

`py tools/check_compile.py --counts`: PASS. FeedbackController has 159 top-level locals,
CrowdRenderer 153 and InputController 148.

## Major

### M1. The checklist wakes Main Camp in step 4, then asks Ben to sneak past it in step 5

- **Where:** `docs/INTERFACES.md:13995` (step 4) and `:13998` (step 5).
- **What step 4 asks:** "In the next camp, shoot a brute in the head … shoot one in the legs … A
  plated raider's headshot is yellow too." After Pickets, the next camp is Main Camp (B). On
  Normal, A has no plated raider (`armoured` is `minDifficulty: hard` in every A group), and A's
  only brutes come out of its tent. So B is where the step can be done.
- **Failure from outside the camp:** Ben shoots from the road before B's gate. He is out of play,
  so every hit reads "BLOCKED" (L1b-7). He gets no yellow number and no "counts" on the legs,
  which are exactly the step's two "Bug" texts. The hit also wakes the brute's group (L1b-4), and
  the join-in (L1b-W2-12) wakes its neighbours.
- **Failure from inside the camp:** shooting from inside B wakes the same chain.
- **Result:** step 5 ("go in by the gate on the road … Nobody wakes") meets an awake camp. Ben
  reports "a '!' while you hug the fence" against the sneak path, which is the wave's headline
  rule, when the fault is the checklist's order.
- **Fix:** move the headshot step after step 6. Main Camp, once woken, has brutes and plated
  raiders on Normal. The Chief's Clearing also has both. Alternatively, say "after you leave Main
  Camp" and point it at B's or C's bodies.

## Minor

### m1. Step 1 promises raiders visible on arrival, but the plateau and fence hide them

- **Where:** `docs/INTERFACES.md:13983`.
- **Geometry:**
  - The start is at feet Y 0 (`ForestRoad.json` `start`).
  - Pickets' floor top is Y 8 (`camps[A].y`, a floor top by LevelGeometry `:14`/`:220`).
  - Its fence is solid boxes 4 tall from that top, so its top is at Y 12 (`sideBox`).
  - The shoulder camera's pivot is about root + 2.1 (Y ≈ 5). At the default zoom it sits under
    Y 11 at any pitch that still shows the horizon.
- **What Ben sees:**
  - Walking from the arrival point to the step at Road5, the line over the fence top runs above
    every body (fodder top ≈ 11.8, lower when seated).
  - Only the tent's roof shows above the fence (its block spans Y 8–16).
  - The bodies appear only at the top of a jump (18 studs), or once he stands on Road5's top
    (Y 8), 38 studs from the fence.
- **Result:** he will see "the camp is empty until you are close; raiders pop in", which is the
  step's own bug text, for a reason that is not a bug. Dormancy (camp A is 206 studs from the
  start against `dormantRadius` 120) never shows, because it is hidden the same way.
- **Fix:** reword step 1 ("jump on the road and you see the tent and the raiders behind the
  fence", or "from the step by the lookout"), or have the data slice confirm the sight line from
  the start in Studio.

### m2. The client clears `used` on a different event from the server, so its gate disagrees both ways

- **Where:** `src/combat/client/Controllers/AirSwing.luau:36-52`.
- **The two rules:** the client clears `used` only on `StateChanged → Landed`. The server clears
  it in `trackAir` (`WeaponService.luau:1823-1827`), when its probe from the root goes from over
  `standingOffset + 0.75` to under it.
- **Too strict, after a get-up:**
  - A player who is put down mid-jump after an air swing lies `PlatformStand` and lands with no
    `Landed` state (`MovementController.luau:532`). He then stands up through `GettingUp`
    (`:558`), again with no `Landed`.
  - This happens in the range's `fight` set (down 2 s, then up in place) and at a co-op revive.
  - The server saw the landing, by height, while he lay there.
  - So the first air swing of his next jump is dropped on the client, though the server would
    accept it. That holds unless he swings on the ground first.
- **Too lenient, on an edge:**
  - A player who lands with the root's centre past a ledge or fence edge gets `Landed` (the
    Humanoid stands on the edge of its footprint), and the client clears.
  - Both probes still read air there, so the server's `trackAir` never sees a landing.
  - His next jump's air swing is sent, drawn and then refused: the "shows and then vanishes"
    that step 2 lists as a bug.
- **Fix:** on the client, clear `used` on `Landed`, `Running` and `GettingUp` (or on
  `FloorMaterial` changing to non-Air). Do it only when one `Judge`-style probe at that moment
  reads grounded. That is still one ray per landing, never per frame, and it matches the server's
  "probe says grounded" rule.

## Checked and holding

- **The seed (L1b-W2-11):**
  - It is drawn at once, parented, held, and never extrapolated (one sample).
  - The first snapshot is always accepted: `before = min(seed, stamp − interval) < stamp`.
  - It blends, or snaps past `TELEPORT_STUDS`.
  - The tell clock, plate burst and enrage beat are all treated as a first sighting.
  - A refreshed info for a still-seeded body moves it in place.
  - A re-announced body that has snapshots is left alone (`spawnEntity`'s alive branch, then
    the `samples == 0 or seeded` test).
  - A dead state is not seeded.
  - `onRemove` fades a seeded body (vanish), never releases it mid-draw.
  - `seeded` is reset in `spawnEntity` for pooled entities.
  - Range bodies now carry `at` too: the seed lands within a frame of the first snapshot, and a
    summon's rise starts at the seed. The `fight`, `colossus` and `warlord` sets look as before.
  - The boss bar cannot appear early: the Colossus is a wave body, never a resident.
- **The wire (`CrowdService.refreshInfo`):** it writes `enemy.position`, `enemy.yaw` and
  `enemy.state`, the same values `sendSnapshot` encodes. So a seed and a snapshot are in one
  frame and one state vocabulary.
- **The air-swing gate (L1b-W2-14):**
  - `Judge` runs before the seq, pacing, combo and effect.
  - `dueShots` advances `nextShotAt` even when the swing is dropped, so a held button or the
    phone's auto-swing probes once per swing interval, not per frame.
  - A refused swing clears the queued tap.
  - The probe matches the server's `floorUnder`: lift, depth, `RespectCanCollide`, every
    character excluded, and the default collision group, so `ArenaBarrier` is skipped on both
    sides.
  - Every client-made Part is `CanCollide = false`, so the client's probe sees no floor the
    server lacks.
  - The double jump does not clear `used` (no `Landed`).
  - `AirSwing.Destroy` is called from `InputController.Destroy`.
- **The camp gate (L1b-W2-24/25):**
  - `campInPlay` equals Wave 1's rounded in-play.
  - The gate-phase rule is ahead of the engaged shortcut, so a camp body is skipped in `gate`,
    engaged or not.
  - Range bodies (no camp floor) are unchanged.
  - The client's sight test (body sphere plus head sphere) lies inside `CrowdRay`'s capsule plus
    head, so auto-fire is never looser than the server.
  - Cone pellets still use spheres, as the contract keeps for cones.
- **Plate crits (L1b-W2-19):** `StrikeHit.crit` is a required boolean. The plate and flesh
  numbers take their own crits. The lasting-merge path tones `plate` only when all of the damage
  came off plates, and keeps the strike's crit.
- **Perf line (L1b-W2-23):**
  - It is shown only in Studio, only in the five live phases, and only for a finite number ≥ 0.
  - `Active = false`, it is destroyed with the HUD, and its connection goes in `connections`.
  - It is placed above the hint stack, clear of the header, objective and boss bar.

## For other slices (one line each)

- **crowd (`WeaponService.trackAir`):** a held-Space bunny hop touches the ground for one or two
  frames at about 84 studs/s (jump 18). The 0.75 margin is crossed inside one frame, so the
  server's replicated root can skip the grounded sample. The server's `used` then stays set
  while the client's `Landed` cleared it, and every later hop's air swing is drawn and then
  refused (step 2's "shows and then vanishes"). Also count a landing when the fall turns to a
  rise within a stud or two of `standingOffset` over the floor, or when a swing's claimed origin
  reads grounded.
- **crowd + client together:** a player standing with the root's centre past a ledge or the
  1-stud fence top reads airborne on both probes, so he gets one swing and every later one is
  dropped until he moves. Fixing it, for example by probing the root's footprint corners, must
  land in `WeaponService.floorUnder` and `AirSwing` at once.

Critical 0, Major 1, Minor 2
