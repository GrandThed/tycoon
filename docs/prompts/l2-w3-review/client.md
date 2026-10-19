# L2 W3 review: client slice

Reviewed `main..l2-w3` (6db63ae) in `tycoon-p5`: FrostFx, AbilityFx/FrostQuake (+ init), ReactFx, InputController
(iceOnAuto, busySecondsOf), FeedbackController routing, ArmoryWeapons, CombatUIController (I key, strip), DebugPanel,
`src/client/UI/Theme.luau`, read against the server's `WeaponService.resolveMelee`/`finish`/`OnAttack`,
`LevelService.React`/`freeze`/`construct`, `WorldReact.Chills`/`Freeze`, `LevelGeometry` ice pieces and the config.
Q1 to Q4 are not re-reported.

**Result: 0 Critical, 0 Major, 4 Minor, 2 Suggestions.**

Gates on a `git archive HEAD` copy: `check_compile.py` PASS (174 files), `stylua --check` clean, `selene` 0/0,
`luau-lsp analyze` (combat sourcemap, `src/combat/client` + `src/shared` + Theme) exit 0.

## Minor

**c-m1. `InputController.luau:1394-1426` + `ReactFx.luau:394`: the phone's water test scans every ice cell every frame,
anywhere in the level.**
- What: `targetOnAuto` runs every frame on touch (`wantsRangeAttack`, :2305). With an ice family held and no body in
  the melee shape, `iceOnAuto` walks all 132 cells through `ForEachIce`. Per cell that is `Parent`, `GetAttribute`,
  `Position` and `Size` reads, a fresh `BoxOf` table, and `Chills` (a sqrt and a `cos(rad)`). `ForEachIce` cannot
  stop, so a hit on cell 1 still reads the other 131. Nothing gates on distance, so the scan also runs in camp B or C,
  300 studs from the water.
- Measured: the pure part alone (132 × `BoxOf` + `Chills`, nothing found) costs 143 µs a frame in the Luau CLI on the
  desktop. Roblox adds four bridge reads per cell, and the number allocates 132 tables a frame. On a low-end phone,
  expect about 0.5 to 1 ms a frame, for the whole run, for any phone player who equips the hammer.
- Fix:
  - Cells are anchored and never move, so make each cell's `Box` once in `adopt`.
  - Keep an array of unfrozen cells, updated from the `Ice` change signal. That also removes the per-frame
    `GetAttribute` calls.
  - Return early when the root is farther from the ice's bounding rect than `size + ahead` plus half a cell's
    diagonal. That is one rect test a frame away from the water.
  - Let the `ForEachIce` callback return true to stop.

**c-m2. `ReactFx.luau:316-342` (`ghostOn`), `FrostFx.luau:142`: a ghost's life is a clock, not the swing's answer.**
- What: a ghost lasts `COMBAT_FROST_GHOST_SECONDS` (0.5 s) whatever the server says.
- Scenario 1, a refusal: the server refuses the swing (`sendRefused` on rate credit, `mayAct`, a busy slot, a stale
  family switch). `FeedbackController.OnRefused` (:3502) takes the hitbox back, but the ice ghosts stand for another
  0.5 s. That is solid-looking ice on water that will never freeze, which is the "lie about walkable ice" the brief
  names.
- Scenario 2, a slow link: with a round trip over about 0.45 s (plus the server frame), the ghost goes before `Ice`
  turns true. The water reads open, then the real ice pops in, so you see ice, then water, then ice. L2-65 accepts the
  late collision, but not a flicker that tells the player the freeze failed.
- Fix: key ghosts by the swing's `seq`.
  - Drop them in `OnRefused(seq)`.
  - Otherwise hold them until that seq's strike arrives, plus a short grace for the attribute to replicate. Keep a
    long safety cap (e.g. 2 s) for a swing that is never answered (`COMBAT_RANGE_SWING_ANSWER_SECONDS` already
    exists).

**c-m3. `FrostFx.luau:72-80, 142-157`, `InputController.luau:1407-1417`: the client's copies of the server's swing
strike are under no gate.**
- What: the client rebuilds `resolveMelee`'s finish fx in two new places: `FrostFx.arcOf` + `OnSwing`, and
  `iceOnAuto`'s strike with `min(arc, finisher)`. FeedbackController's `PredictSwing` holds a third copy. The server's
  fx is `shape`, `origin` = clamped claim, `direction` = flattened heading, `size = range`, and the finisher arc on
  `step == #chain`.
- No tool reads any client file (`grep -r` in `tools/` finds none of FrostFx, iceOnAuto, PredictFreeze, ForEachIce).
  The harness tests `Chills` itself, but not the arguments these sites build.
- Scenario: a later edit sets `size = variant.range + variant.pad`, or drops `arcOf`'s finisher branch for a family
  with `finisherArcDegrees`. The ghost then shows ice the server never makes, and the phone auto-swings at water that
  never freezes, swinging forever at the rate with nothing changing. Every gate stays green. This is the W1 pattern:
  one shared pure function, but the call-site arguments are copies.
- Fix:
  - Add a pure `WorldReact.SwingStrike(variant, step, origin, heading): Strike`, called by `resolveMelee`'s `finish`
    fx and by both client sites (the phone passes the narrower arc as today, or both steps).
  - Add harness cases, and a mutant on `size` and on the finisher step.

**c-m4. `InputController.luau:1471` with `:1694-1706`: on a phone, an auto-swing at water fires on a take-off and while
falling. It spends the jump's air swing and stops the body for 0.3 s.**
- What: `Chills`' band is `top ≤ origin.Y ≤ top + reachDown`. For ice at −0.8 that is a root up to Y 5.2, while a
  grounded root stands at about 2.2 on ice and 3 on the bank.
- Scenario 1, a hop: a phone player hops on the ice edge toward open water. A due auto-swing in the first 2 to 3 studs
  of the rise passes `AirSwing.Judge` as airborne, spends the jump's one swing (`AirSwing.Took(true)`), and calls
  `MovementController.AirHang(0.3)`. That is a zero-velocity mover, so the jump stops dead mid-air. A crowd body that
  then comes into reach cannot be swung at until landing.
- Scenario 2, a fall: a phone player who walks off the bank gets the same 0.3 s hang over the water, plus a free
  freeze below him. A PC player gets neither unless he clicks.
- The rule is the server's own, so it is not a desync. It is a phone-only movement effect nobody chose.
- Fix (lead's call): `iceOnAuto` returns false while `MovementController.IsAirborne()`, because the freeze band was
  sized for a grounded origin (L2-54). Or a water-only auto-swing skips `AirHang`.

## Suggestions

**c-s1. `AbilityFx/FrostQuake.luau:66-67, 98, 133-150`: the shards were tuned for Earthquake's radius, not for 32.**
- Q4 makes the visual draw the configured count. But `shardsPerRing` 10 was set for Earthquake's radius 9. At radius 32
  the shards stand 20 studs apart.
- Every ring, shard and mark is planted at `groundOf(cast)`'s height. On Forest Road's 16-wide road, most of a
  32-radius ring therefore hangs in the air over the void or over the creek.
- Fix: scale the shard count with the circumference (with a cap), and drop any shard with no floor under it (one
  downward ray each, at build).

**c-s2. `ReactFx.luau:394`: `ForEachIce` has no way to stop early.** The callback could return true to stop. This
comes for free with c-m1's fix.

## Verified (safe to reuse)

- **The ghost matches the server's freeze.**
  - The client sends `rig.root.Position` and `flatCameraLook()`, and the ghost uses exactly those.
  - The server freezes with the clamped claim (`meleeOrigin`, equal for an honest client), the flattened heading,
    `size = range`, and the step's arc.
  - `arcOf` mirrors `resolveMelee`'s finisher rule. The hammer has no `finisherArcDegrees` today, so every step sweeps
    120°.
  - Cell boxes come from the same piece (float32 rounding is about 1e-7, far from any band edge).
  - Ghosts never go on frozen cells, because `ForEachIce` lists only cells with `Ice == false`.
  - The ghost is `CanCollide`/`CanQuery`/`CanTouch` false and 0.5 transparent, unlike the opaque look of the real
    ice.
- `finish` broadcasts, then runs the listeners on every melee swing (`fx.abandoned` is never set for melee), so a swing
  on the road reaches `freeze`.
- **The phone never swings past a resting body.**
  - `enemyInReach` tests the melee shape with `autoSwingPad + lagPad` on top of `variant.pad`, a superset of what the
    server hits.
  - A refused body inside it returns false before any water is asked.
  - Water up to 13 studs out wakes nothing: the swing hits only 9 + pad.
- `StreamingEnabled` is false in `combat.project.json`, so the client holds every cell the server holds.
- Low-end gating is correct:
  - the FrostFx puff, the ReactFx frost motes and FrostQuake's halved particles and shards all key on
    `Theme.lowEndDevice`;
  - ghosts and the glint draw on every device;
  - nothing new reads `reducedMotion`.
- `busySecondsOf` treats `frostQuake` like `earthquake`. `applyCast` needs nothing for a `floor` ability. Feedback has
  no other per-id table.
- **The I key and the strip:**
  - I sits behind `studio` and the remote check in `onKey`, after the M, K and Backspace returns;
  - nothing else binds `KeyCode.I`;
  - the strip button and `SetIceFamily` mirror the fire ones;
  - the F key still routes through `ELEMENT_FAMILY_KEYS`.
- **Armory:**
  - `HiddenWhere` now returns the whole line, and its only reader is the card's `line.Text`;
  - a `found` family that a secret also pays keeps "Hidden on ...";
  - the owned hammer drops `hidden`;
  - columns stay at most 2 cards each, so the W2 page height of 190 still fits.
- W1/W2 not regressed:
  - `adopt` returns early only for Parts with a boolean `Ice`, so a bramble's path is unchanged;
  - `targetOnAuto` gives a non-ice melee family the same result as before;
  - `forget` and `Destroy` clean up ghosts and cells.
