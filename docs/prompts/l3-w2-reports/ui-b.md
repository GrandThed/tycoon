# L3 W2: ui-engineer B report (held weapons, the one muzzle, other players' arms, rest poses)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-w2`. Nothing is committed. I edited only the files in my row.
Section 11 ruling 6 (rest poses, 33ec9dc) is built; see "Rest poses" below.

## Files created or changed

- **New: `src/combat/client/Controllers/HeldWeapons.luau`** (L3-51, L3-52, ruling 6). API: `Start`,
  `SetLocalStance(slot)`, `Muzzle(userId) -> (Vector3?, boolean)`, `OnHold(listener?)`, `Destroy`.
  - Watches every Player's character (local one included): `PlayerAdded`, `CharacterAdded`, `CharacterRemoving`,
    `PlayerRemoving`.
  - Reads `WeaponLook.Read` on the character, again on `GetAttributeChangedSignal` of each of the three names. The
    local character's slot in use is the local stance.
  - Cache `models[character][family]` (weak-keyed). `modelFor` clones `Assets/Props/<folder>/<Def.model>` once.
    It keeps `Stage0` only, seals the clone, welds the other parts to `Base` with WeldConstraints, makes one `Weld`
    (Part1 `Base`, C1 identity) and parents the clone as `HeldWeapon_<family>`.
  - A switch only re-points the two welds:
    - a melee weapon in the hand: `attachment.CFrame * Theme.COMBAT_HOLD_GRIP_MELEE * CFrame.new(-grip)`;
    - a ranged weapon in the hand: the same with `Theme.COMBAT_HOLD_GRIP_RANGED`;
    - on the back: `attachment.CFrame * Theme.COMBAT_HOLD_BACK * CFrame.new(-holster)`.
  - Attachments are looked up as direct children of `RightHand`/`Right Arm` and `UpperTorso`/`Torso`.
    `ChildAdded` covers parts and attachments that arrive late. A slot whose attachment is missing takes its model
    off the character until the attachment appears.
  - A family that leaves the loadout is destroyed. `Humanoid.Died` and `CharacterRemoving` destroy the rest.
  - `OnHold(listener)` tells WeaponController when a character's hand starts or stops holding a ranged **model**:
    `(character, isLocal, raised)`, on change only. Setting the listener replays every character already raised.
    No model (before the paste, or a missing attachment) means not raised, so the arm hangs exactly as in W1.
  - No RunService. Nothing runs per frame.
- **`WeaponController.luau`** (L3-54, ruling 6): removed `gear`, `SetGear`, `slotTier`, `tierDefFor`,
  `propFolderFor`, `refreshWeapon`, `attachTo`, `gripCFrame`, `clearWeapon`, `weapon`, `armoryConfig`, `WEAPON_NAME`,
  the `Armory` require and the `SlotTiers` export.
  - `Start` calls `HeldWeapons.OnHold(onHold)` then `HeldWeapons.Start()`. `Destroy` calls `HeldWeapons.Destroy()`
    and lets every arm hang again.
  - `SetStance` cancels the pose, then calls `HeldWeapons.SetLocalStance(nextStance)`.
  - `muzzlePoint` is the helper call.
  - The rest poses are described below.
- **`FeedbackController.luau`**: `muzzleOf` is gone. Its seven sites call `(HeldWeapons.Muzzle(...))`. It now
  requires HeldWeapons and WeaponController. The L3-53 line is added, and the header gets a short L3 W2 paragraph.
  It has **163** top-level locals (cap 163).
- **`FlameFx.luau`**: `muzzleOf(userId, aim)` = the helper's point, plus `aim * MUZZLE_FORWARD` only when the point
  is not from a model.
- **`AbilityFx/Shared.luau`**: `muzzleOf(userId, aim, fallback)` keeps its signature. It uses the helper's point,
  pushed forward only when the point is not from a model, and `fallback` when there is no character. `handOf` is
  unchanged.
- **`AbilityFx/MagDump.luau`**: both `muzzle =` lines call `muzzleOf(`. The hand glow still uses `handOf`.
- **`CombatUIController.luau`**: removed the `WeaponController.SetGear(gear, ascension)` line, the require, and the
  header's mention of WeaponController.
- `CombatFxController.luau` and `InputController.luau` are unchanged (`git diff --quiet main` on both).

## Rest poses (ruling 6), as built in WeaponController

- Each shoulder record (`PoseRig`) has a `rest`, in degrees from `base` (the hanging arm). It is
  `Theme.COMBAT_HOLD_RANGED_RAISE_DEGREES` (80) while HeldWeapons says a ranged model is in that hand, else 0.
- Which characters are raised is kept in a weak-keyed `raisedRigs`, apart from the pose records. The news can come
  before a character's shoulder is found: on respawn, or when another player's arm arrives late.
- **Local character:** the rest follows the local stance through `HeldWeapons.SetLocalStance` → `OnHold`. When
  `bindCharacter` finds the shoulder it reads the rest and sets it at once.
- **Other characters:** the rest follows their `WeaponHeld` through `OnHold`, using one helper, `remotePoseFor`, for
  both the hold and `SwingOther`. A record made while that hand already holds a ranged model starts raised.
- **A rest change eases** over `COMBAT_SWING_SETTLE_SECONDS` (`setRest`: it supersedes any pose still running,
  because the rest changes only on a slot switch, which ends a pose anyway).
- **Every pose returns to the rest:**
  - `cancelRig` snaps to the rest, where it used to snap to `base`.
  - A swing's settle leg goes to the rest.
  - `Release` goes to the rest.
  - The shot kick is `rest + COMBAT_SHOOT_KICK_DEGREES`.
- **The draw keeps its absolute angle** (`COMBAT_DRAW_DEGREES` from the hanging arm, 80, the same as the raise).
  - It starts from the raised arm, so a bow held ready is already at full draw height.
  - My reading of "measured from that raised arm": the tween starts there. Adding 80 to the raise would point the
    arm at the sky (160°).
  - With no model in the hand the rest is 0, and the draw lifts the arm from hanging as in W1.
- **A melee family in the hand:** the rest is 0, and the swing angles (windup, strike, finisher) are unchanged.
- **Cost:** no new per-frame work. A rest change is one tween, and the swing, draw and kick tweens are the existing
  ones.
- **Limit:** if another player's shoulder Motor6D has not arrived when their hand is raised, their arm stays hanging
  until their next hold change or swing. The hand and the shoulder normally replicate together.

## Remotes and state fields consumed

- No new remote. HeldWeapons reads the character attributes `WeaponMelee`, `WeaponRanged` and `WeaponHeld`
  (through `WeaponLook.ATTRIBUTES` and `WeaponLook.Read`).
- The existing `CombatFxStrike` fields `userId` and `step`, for SwingOther.
- Configs: `Catalog.GetWeaponModelsConfig()` (`folder`, `Def`, the points `grip`, `tip` and `holster`), and
  `Catalog.GetProvingGroundsConfig().weapons`, used only by `WeaponLook.Problems`, which is warned once at Start.
- Theme: `COMBAT_HOLD_GRIP_MELEE`, `COMBAT_HOLD_GRIP_RANGED`, `COMBAT_HOLD_BACK`,
  `COMBAT_HOLD_RANGED_RAISE_DEGREES` (ui A's values).
- Templates: `ReplicatedStorage.Assets.Props.Weapons.<Model>`.

## Pinned lines (T9 to T13), as written

All of these pass in the harness.

- **T9:** `		WeaponController.SwingOther(strike.userId, strike.step or 1)` inside `	elseif swing and not mine then`,
  after `FrostFx.OnStrike(strike)`.
- **T10:**
  - FeedbackController: `(HeldWeapons.Muzzle(strike.userId))` 5×, `(HeldWeapons.Muzzle(fx.userId))`,
    `(HeldWeapons.Muzzle(userId))`.
  - FlameFx and Shared: `local point, fromModel = HeldWeapons.Muzzle(userId)`.
  - MagDump: `local muzzle = muzzleOf(cast.userId, look, cast.origin + look * MUZZLE_FORWARD)` and
    `muzzle = muzzleOf(cast.userId, look, muzzle)`.
  - WeaponController: `return HeldWeapons.Muzzle(Players.LocalPlayer.UserId) or fallback`.
  - **Differs from §9 in shape:** HeldWeapons names `"RightHand"` once, in `local HAND_PARTS = { "RightHand",
    "Right Arm" }`. That list is both the grip-mount list and the start of the fallback chain, which then tries
    `ROOT_PART = "HumanoidRootPart"`.
- **T11:** `local model = template:Clone()` in `modelFor`, after `local cached = ...`.
- **T12:** `part.Anchored = false`, `part.CanCollide = false`, `part.CanQuery = false`, `part.CanTouch = false`,
  `part.Massless = true` in `seal`. `seal(model)` comes before `model.Parent = character`.
- **T13:** no recursive lookups.
- **New lines from ruling 6, if the lead wants them pinned** (none touches a hit):
  - HeldWeapons `hang`: `local hold = if not inHand then Theme.COMBAT_HOLD_BACK elseif ranged then
    Theme.COMBAT_HOLD_GRIP_RANGED else Theme.COMBAT_HOLD_GRIP_MELEE` (stylua splits it over four lines).
  - HeldWeapons `show`: `local raised = rangedInUse and rig.inHand ~= nil`.
  - WeaponController:
    - `restOf` returns `Theme.COMBAT_HOLD_RANGED_RAISE_DEGREES` when `raisedRigs[rigModel] == true`, else 0;
    - `cancelRig` ends with `motor.C0 = restFrame(rig)`;
    - the swing's settle is `rigPoseTo(rig, rig.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)`;
    - `Release` is `poseTo(localPose.rest, Theme.COMBAT_SWING_SETTLE_SECONDS, Enum.EasingStyle.Quad)`;
    - the kick is `localPose.rest + Theme.COMBAT_SHOOT_KICK_DEGREES`;
    - `Start` has `HeldWeapons.OnHold(onHold)`.

## Gates (after ruling 6)

- stylua and selene are clean on my seven files. luau-lsp (`tools/types/globalTypes.d.luau`, sourcemaps
  regenerated into my scratchpad) is clean on both trees: combat `src/combat src/shared`, and hub
  `src/client src/server src/shared`.
- `check_compile` PASS (180 files); FeedbackController has 163 top-level locals.
- `rojo build` of `combat` and `.proving` to scratch succeeds. My files are LF.
- **Harness: PASS, 3,921 checks.**

## Assumptions made

- When `WeaponHeld` is missing on another player's character but both families are present, the weapon in use is
  melee (the server's starting value), so the arm hangs.
- A template child named `Stage<n>` other than `Stage0` is destroyed at clone time, so W2 shows one look (L3-55).
- An unknown family warns once a session, only when the config exists. A missing template is silent: that is the
  state before the paste.
- On `Humanoid.Died` the character's weapons are destroyed, so they do not drop through the floor when joints break.
- If the game is not loaded at Start, every rig is shown again on `game.Loaded`, in case a template replicated late.
- An attachment's CFrame is read when the weapon is hung. A body scale change after that is not followed.
- The raise uses the same shoulder X turn as the W1 draw, so "forward" is whatever the draw already showed.

## Required changes outside my files

- None now. The back-hold fix is ruling 6 (ui A applies it).
- The T9 exit count is ruling 7, and the harness passes with it.

## What to check in Studio (after the paste; without it, hands stay empty, arms hang and Output shows no HeldWeapons line)

1. **Load and failure path.** Open `proving.rbxl` before the paste. Hands should be empty and arms hanging exactly as
   in W1, with no error and no `[HeldWeapons]` warning. After the paste, Output should show no `[HeldWeapons]` line
   either: a line there means WeaponModels.json and ProvingGrounds disagree.
2. **Lobby, one client, rest poses** (a screenshot of each for the Theme round):
   - With the sword: the arm hangs and the sword points forward from the hand, clear of the floor.
   - Press 2 for the bow: the arm rises forward over about 0.1 s and the bow points ahead, limbs upright. The sword
     goes to the back.
   - Press 1: the arm eases down and the bow returns to the back, lying across the shoulders with no limb through
     the chest.
   - Check the Spear, the Greataxe and the hammers at rest, and the raised arm in front of the over-the-shoulder
     camera (does it cover the crosshair?).
3. **Poses from the raised arm:**
   - A bow's draw holds the raised arm, and the release stays raised.
   - A hitscan gun kicks up from the raised arm and settles back to it.
   - The Beam, the Flamethrower and the Launcher stay raised while firing.
   - A melee swing after switching back (1) starts from the hanging arm and ends hanging.
4. **Shots.** Fire every ranged family:
   - The tracer, bolt, arrow flight, Beam and Chain Gun links start at the weapon's tip, ahead of the raised hand.
   - The Flamethrower's flame leaves the nozzle.
   - Mag Dump's heat glow sits at the gun's tip and the hand glow at the hand.
   - The ability effects (Overcharged Shot, Volley, Slug Burst, Dragon's Breath, Blade Storm, Storm Coil) start at
     the tip.
5. **Nothing a hit is judged on moves.**
   - Shots, swings and early hitbox effects land exactly as before.
   - The camera never stops on or pops in front of a held weapon.
   - Hold a long weapon against a wall: nothing collides.
6. **Lever F (Flamethrower).** The bow on the back becomes the flamethrower. Equip it and switch to it: it moves to
   the raised hand.
7. **Respawn or level change.** A new character gets its weapons back, and its arm starts raised if it respawned
   with the ranged slot in use. No weapon is left stuck in the world.
8. **Two clients** (Test → Clients and Servers, 2 players; Prueba → Clientes y servidores):
   - Player 2 sees player 1's sword in hand and bow on back, with player 1's arm hanging.
   - Player 1 presses 2: player 2 sees the swap and the raised arm only at player 1's next shot, draw or cast
     (L3-65); player 1 sees it at once.
   - Player 1 fires: player 2 sees the arm stay raised. Player 1 switches back and swings: player 2 sees the arm
     drop, then the swing with the trail.
   - The debug bots hold nothing and never raise an arm.
9. **Phone emulator (375×667 class and 1920×1080).** No GUI of mine changes, and I added no tap targets. The models
   are world objects welded once. A rest change is one short tween, which Motion shortens under reduced motion.
   Check frame time with two players in a mission (at most 8 models, about 1,700 to 3,500 triangles each).
