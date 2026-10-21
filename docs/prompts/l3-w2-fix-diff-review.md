# L3 W2 fix diff review (`git diff 5c0958b 31b1947`), 2026-10-21

The reviewer was read-only. It wrote this file and nothing else in the worktree. Mutants and scripts ran on a
`git archive 31b1947 src tools combat.project.json default.project.json` copy in the reviewer's scratchpad, never in
`tycoon-p5` or `tycoon-p5b`.

**0 Critical, 0 Major, 3 Minor, 3 Suggestions.**

All seventeen rulings are done. The fix round brought in one new defect, m1. C4's deferral reorders the hold
listener behind another player's swing, so the first swing after a ranged-to-melee switch never shows on other
clients. C3 brought in m3, a side effect of the right stick.

While this review ran, `git status` in `tycoon-p5` showed `build/*.rbxl` and both `sourcemap*.json` as modified.
The reviewer did not make those changes; the QA run in the same worktree is the likely source.

## Minor

**m1. Since C4, another player's first swing after a switch from ranged to melee does not animate.**
The files involved:
- `src/combat/client/Controllers/HeldWeapons.luau:297-303` (`queueShow`);
- `src/combat/client/Controllers/FeedbackController.luau:2869-2873`;
- `src/combat/client/Controllers/WeaponController.luau:374-392` (`setRest`) and `:431-434` (the swing's token check).

What happens:
- `OnAttack` writes `WeaponHeld` (noteHeld, right after acceptance), then broadcasts the strike. On the other client,
  the attribute handler and the strike handler are queued in that order.
- Before C4, the attribute handler ran `show` at once. The hold listener's `setRest(0)` lowered the raised arm,
  then `SwingOther` began the swing: `cancelRig` snaps the arm to rest 0, then the windup runs.
- Now the attribute handler only defers a flush, and that flush goes to the back of the queue. `onStrike` runs
  first and calls `SwingOther`. The swing starts from the raised rest, because `raisedRigs` is still true.
- Then the flush runs `show`, and the hold listener calls `setRest(0)`. That raises `rig.token`, cancels the windup
  tween and eases the arm to 0. The windup's `task.delay` continuation sees a stale token and returns, so the strike
  leg never plays.

`Muzzle` flushes first, but nothing on the swing path calls `Muzzle`. This branch is the one ordering-sensitive
reader that the C4 report's `Muzzle` flush does not cover.

**Scenario:** two players.
1. P1 holds the Longbow (arm raised), presses 1 and swings the Broadsword at once.
2. On P2's screen, P1's arm drops from the raise to hanging over `COMBAT_SWING_SETTLE_SECONDS`, with no windup and no
   strike. The trail still flashes.
3. Every later swing animates normally.

This happens on every ranged-to-melee switch that ends in a swing, which is the usual way into melee in co-op. It is
display only.

**Fix (ui-engineer, plus the harness owner for the pin):**
- Make the flush public, for example `HeldWeapons.Flush(userId)`, which `Muzzle` calls as well.
- Call it as the first line of the `elseif swing and not mine then` branch, before `SwingOther`. A plain call opens
  no block, so T9's `otherBlocks` stays 0.
- Pin it as a whole line with an `l3w2` mutant that drops it.
- Add a step to PLAYTEST's two-client check (see s3).
- The alternative is to have `onHold` update only `rig.rest` while a swing token is live, because the settle leg
  already reads `rig.rest`. That changes `setRestEase`, so the flush is the smaller change.

**m2. C4's new pins hold the calls, not the order and inputs that make them work.**
The files involved:
- `run_harness.py`: `muzzleFlushes`, `queueOnce`, `flushShows`;
- `HeldWeapons.luau:351-352` and `:505-509`.

Each of these review-only mutants, applied alone, leaves `HARNESS: PASS (4,024 checks)`:
- **`Muzzle` reads `rig.inHand` on the line above the flush.** The three pinned lines are unchanged. This is exactly
  3-m1 coming back: a teammate's cast or shot leaves from the weapon before the switch.
- **`bound = false,` in `bind`'s new rig.** Every queued show is dropped, so no attribute change, late mount part or
  late attachment ever shows. Only bind, the local switch and `Muzzle` still show.
- **`pending = true,` in `bind`'s new rig.** `queueShow` never defers, which has the same effect.

This is the recurring pattern: the pins count the call text, not where it stands or what its inputs start as.

**Fix (luau-engineer, harness and mutate):**
- An `L3W2_ORDER` entry `("heldMuzzle", "flush(rig)", "rig.inHand")`.
- Whole-line pins for `\t\tpending = false,\n\t\tbound = true,\n` in `bind`.
- One `l3w2 fix` mutant each.

**m3. With C3, the right stick turns the world camera, and the character, behind the screen as well as the stage.**
The files involved:
- `src/client/UI/ArmoryStage.luau:369-382` and `:393`;
- `src/combat/client/Controllers/CameraController.luau:860-864` and `:517-523`;
- `src/client/UI/ArmoryScreen.luau:748-773`, where only B, the tab keys and A are bound.

What happens:
- C3 asks the player to use the right stick on the Weapons tab. Nothing stops that same stick from driving the
  camera behind the screen.
- **Dungeon lobby:** `CameraController.onInputChanged` takes `Thumbstick2` into `gamepadLook` from
  UserInputService. It does not check `processed`, a modal or a cursor hold, and `consumeLookInput` applies it
  every frame.
- **Hub:** the PlayerModule camera reads the stick through its own input actions, and nothing sinks it.

**Scenario:** gamepad, dungeon lobby. Open the Armory with Y and hold the right stick to turn the Broadsword.
- Behind the 0.35 scrim (`ARMORY_SCREEN_SCRIM_TRANSPARENCY`) the whole lobby swings round, and the over-the-shoulder
  camera turns the character with it.
- When the screen closes, the player faces wherever the stick left them.

In W1 the right stick did nothing on this screen, so nobody had a reason to touch it.

**Fix (ui-engineer, with whoever owns CameraController):**
- While `look.inputs` is live, bind a sink for `Thumbstick2` at `PAD_PRIORITY`, for the hub camera. Confirm in
  Studio that `UserInputService.InputChanged` still reaches `onStick` under the sink.
- In the combat place, have the open Armory set a hold that `consumeLookInput` honours for `gamepadLook`. For
  example, a `SetCursorHold` reason that also gates the stick.

## Suggestions

**s1. Two C3/C2 sentences have no gate.**
Each of these review-only mutants survives alone (`HARNESS: PASS (4,024)`):
- **C3, the stick:**
  - `local rate = if false` in `syncTurn` (`ArmoryStage.luau:409`): the stick does nothing except on a low-end
    device;
  - `look.stickX = stickX` dropped from `onStick` (`:380`): the stick does nothing anywhere;
  - the stick's sign flipped;
  - the dead zone removed (`:374`).
- **C2, the tone:** `ARMORY_SCREEN_ICON_GHOST` set to (12, 14, 20) (`Theme.luau:1514`). The shelf's unowned icons
  are near-black again. `shelfGhost` pins only the name.

A pure stick step, or whole-line pins plus mutants, would cover the first. A Python check of the Theme value would
cover the second: flat contrast against `ARMORY_SCREEN_CARD_DARK` of at least 1.5, or, where the icons exist, the
multiplied median the ui report used. Ben rarely plays with a pad, so his look will not cover the stick.

**s2. Zero the stick on `InputEnded` and when the gamepad disconnects.**
`CameraController.luau:874` treats a `Thumbstick2` `InputEnded` as rest. `onStick` listens only to `InputChanged`.
- If the last event the stage saw was off-centre (an `InputEnded`, or `GamepadDisconnected`), `look.stickX` keeps
  its value. Off low-end, the stage then spins at up to 120 degrees per second until the stick moves again or the
  window loses focus.
- Two more listeners in `look.inputs` close it.

**s3. Add two items to PLAYTEST's two-client step:**
- "P1 holds the bow, presses 1 and swings at once: on P2's screen the arm swings" (m1);
- "with the Weapons tab open, the right stick turns the weapon and the world behind the scrim stays still" (m3).

## Rulings verified done

- **P1:** `gen_asset_manifest.py --check` PASS. MANUAL_STEPS steps 5 and 8 regenerate the manifest beside each
  `Assets.json` commit, and so does the rule line.
- **P2:**
  - `merge_model` refuses a `props/Weapons` record with any `rotated` part and does not merge it.
  - It runs after the asset id check, saves everything else, prints `ROTATED:` and returns 1. `--force` does not
    bypass it.
  - The import of `weapon_frames.FOLDER` adds no cycle: nothing imports `harvest`, and `weapon_frames` pulls no
    Pillow.
  - Other props and buildings keep the warning.
  - Step 8 says "No `rotated` warning".
- **P3:**
  - Steps 3 to 6 are ticked with 084a14f, d1c2f59 and 4154715.
  - The "none of the 15" line is corrected.
  - A repeat emits fewer than 30, and steps 7 and 8 count against step 6.
  - Step 9 says how to stop.
- **P4:**
  - `pixel_sha256` hashes the size and the decoded RGBA rows.
  - All 15 recorded values in `Assets.json` equal `pixel_sha256` of the files in `assets/testfit/out/Weapons/
    icons256` (15 of 15, rechecked here).
  - The diff is 15 `sha256` lines and nothing else: every `assetId` and `imageId` is unchanged.
  - No other tool reads an icon's `sha256`: `harvest.py`'s sha256 is the world bake's.
- **P5:** the proof line now names one offset check and one size check per weapon. `weapon_frames.py --check` PASS.
- **P6:**
  - `kenney_kit` reads `assets/kenney3d/<kit>/License.txt`.
  - The 14 folders that have the file are Kenney's, and every generated kit lacks it, `tower-kit` included (it comes
    from `tower_kit.py`).
  - The CC0 credit appears only when every kit is Kenney's.
- **S1:** `heldReads` is 3, `abilityHeld` is 0, and T8 uses the spelling-robust pattern. The review's P1 and P2 and the
  AbilityService read each have a mutant.
- **S2:**
  - The four callers are pinned as whole lines in their own bodies.
  - `initExits`, `rangeAddExits`, `rangePrepareExits`, `addExits`, `hookWrites` and `hookSetters` are all in place.
  - The 12 mutants are present.
- **S3:**
  - `whole_lines` and `whole_line_at` count only line-starting, line-ending text, so a pinned line wrapped in a new
    block indented further stops counting. One known limit: a wrapper left at the same depth is the formatter's to
    catch.
  - `sealUndone` is 0.
  - All six named lines and the other client lines from 3-m3 are pinned with mutants: `stageStops`,
    `selectClears`, `heldCleanup`, `heldWatched`, `bindShows`, `stanceShows`, `playerWatch`, `heldMountShows`,
    `setRestEase`, `remoteSnap`, `stageSilhouette`, `shelfGhost`.
  - The three stale T14 mutants are re-aimed.
- **S4:**
  - `OnDraw` refuses `def.slot ~= "ranged"`, pinned as `drawRanged`; `drawExits` stays 3.
  - No honest client sends a melee draw. `startDraw` is reached only through `isCharge` (variant `kind == "ranged"`
    with `chargeSeconds`), and every family's variant kind matches its slot (all 15 checked in `ProvingGrounds.json`).
  - No ability calls `OnDraw`.
- **S5:**
  - `lookLiterals`, `heldIndexed` and `loadoutWhole` are 0, and `loadoutWrites` counts the pair by index.
  - `attackExitsAfter` is 0 and `castExitsAfter` is 1, built with `moved_down`/`moved_up`.
  - `Problems` sorts the whole list. Every family message starts with the family, so the faults group as the comment
    says.
- **S6:**
  - `NoteHeld` stands on the line before `broadcastFx(fx)`.
  - After it, only `mechanic.launch` can refuse, through `FireProjectile`'s budget, a speed of 0, an inactive service
    or a zero direction. That refusal keeps the flip, which matches the caster's own client: `castAbility` calls
    `setActiveSlot` on the press.
- **2-s3 (not taken):** each side's comment names the other (`WeaponLook.BOUNDS_SLACK`,
  `weapon_frames.POINT_SLACK`).
- **C1:**
  - Both `templateOf` functions need a `Base` BasePart.
  - Both clones re-find it, destroy the clone if it is missing, and set `PrimaryPart` before the welds (HeldWeapons)
    or before `PivotTo` (stage).
  - No `.PrimaryPart` reads remain.
  - Templates put `Base` directly under the Model (`gen_templates.py` docstring).
- **C2:**
  - `ARMORY_SCREEN_ICON_GHOST` is (140, 155, 190), at 6.01 against `CARD_DARK`.
  - The ui report's per-icon medians were reproduced: Spear 1.59 to Chaingun 3.56, at 40 px with alpha
    compositing.
  - The stage keeps `ARMORY_STAGE_SILHOUETTE`.
- **C3:**
  - `syncTurn` makes the RenderStepped turn, the stick listener and the focus listener only while the stage is active
    with a model shown.
  - `stop()` drops all three, zeroes the stick and ends the drag. It runs on SetActive(false), Show(nil), a missing
    model and Destroy.
  - A drag ends on its own `InputEnded`, a lost mouse release or focus loss.
  - Low-end gets per-event stick turns and no per-frame work.
  - A phone gets no `Thumbstick2` events without a pad, and TouchControls are off while the screen is open (R9).
- **C4:**
  - `queueShow` and `flush` are correct for bursts.
  - A flush of an unbound rig (Died, CharacterRemoving, Destroy) does nothing.
  - `Muzzle` flushes only its own current character, and per-frame Muzzle calls cost one boolean test.
  - The ordering gap is m1.
- **C5:** the comment is fixed.

## Gates and probes run

- Harness on the archive copy of 31b1947: `HARNESS: PASS (4,024 checks)`.
- 11 review-only mutants, run with `scratchpad/l3w2fd/probe.py`:
  - 8 survive: m2's three and s1's five;
  - 3 controls are caught: flush order, the `drawRanged` clause, and the note after the send.
- `gen_asset_manifest.py --check`: PASS.
- `weapon_frames.py --check`: PASS (0 of 15 harvested; the harvest paste is pending).
- `gen_templates.py --check`: PASS, 554 templates.
- Icon pixel hashes: 15 of 15 match.
- Ghost contrast: reproduced.
