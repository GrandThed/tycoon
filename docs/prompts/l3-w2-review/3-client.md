# L3 W2 review, slice 3: the client (hands, muzzle, stage, shelf)

Reviewer: roblox-reviewer (Opus), 2026-10-21, branch `l3-w2` at c79bec5, diff `git diff main...l3-w2` on HeldWeapons,
WeaponController, FeedbackController, FlameFx, AbilityFx/Shared, AbilityFx/MagDump, CombatUIController, ArmoryStage,
ArmoryShelf, ArmoryScreen and Theme. Contract `docs/prompts/l3-w2-contract.md` with §11; reports `ui-a.md`, `ui-b.md`.
Review-only mutants ran on a `git archive` copy in my scratchpad (each one applied alone, the copy's own harness run,
then restored). No file in the worktree was changed except this one.

**0 Critical, 0 Major, 3 Minor, 7 Suggestions.**

## Minor

**m1. A teammate's ability effect starts at the tip of the weapon in the other slot.**
`src/combat/server/Services/AbilityService.luau:997` (`broadcastFx(fx)`, the cast) runs before `:1036`
(`WeaponService.NoteHeld(player, slotName)`). `mechanic.launch` (`:1025`) also runs before it, and it fires the
instant strikes and shots. So every other client gets the cast fx, then any instant shot or strike, and only after
those the `WeaponHeld` change. With deferred signals the attribute's value is already set when the handlers run.
But `HeldWeapons.Muzzle` reads `rig.inHand` (`HeldWeapons.luau:464-468`), and the AttributeChanged handler that
updates `rig.inHand` (`show`) is queued after the remote handlers.
The builders that read the muzzle once, when the effect is built, keep the stale point:
- Volley (`AbilityFx/Volley.luau:71`, run by `AbilityFx/init.luau:200` on receipt);
- Storm Coil (`StormCoil.luau:139`);
- Blade Storm (`BladeStorm.luau:116`);
- a shot's blend (`FeedbackController.luau:2458`).

The attack path has no such gap: `OnAttack` calls `noteHeld` before it resolves and broadcasts the strike.

Scenario with two clients:
1. P1 holds the Broadsword (`WeaponHeld` = melee) and presses E (Volley on the Longbow).
2. On P1's screen the bow is raised at once, because the local stance switches on the press.
3. On P2's screen the gold flash, the fan of streaks and the arrows' blend start at P1's sword tip (forward from
   the hanging hand). The bow appears in the raised hand a frame later.

The reverse case: Blade Storm cast while a gun is in hand throws the shuriken from the gun's muzzle.

Before W2 every one of these started at the hand, so W2 makes this worse.

Fix (server, one line moved): call `WeaponService.NoteHeld(player, slotName)` just before `broadcastFx(fx)` at
`:997`. The only refusal after that point is the projectile budget (`:1025-1033`). The caster's own client has
already switched its stance on the press whatever the verdict, so showing the slot then matches what the caster
sees. T6's pinned text, its mutant and the contract line in L3-50 move with it (luau-engineer's).
A client-only alternative: AbilityFx and `onShot` derive the slot from `fx.weapon`, and HeldWeapons takes a slot
hint for that caster. That is more code.

**m2. An unowned shelf icon cannot read on the dark card.**
`src/client/UI/ArmoryShelf.luau:289` with `:292`, and `Theme.luau:1503`. The silhouette (14, 16, 22) sits on
`ARMORY_SCREEN_CARD_DARK` (22, 29, 50).
- The WCAG contrast is 1.14. The approved "unowned 64" sample on the panel colour (30, 41, 70) is 1.32.
- Even pure black on that card only reaches 1.26, so no darker silhouette can match the sample.
- ui A flagged it as an assumption (about 1.10 against 1.29).

Scenario: Ben opens the hub Armory on a phone in daylight. The 11 unfound weapons' cards show only the name and "Not
found" on a plain navy card. The silhouettes that L3-57 promises (and that the sample sheet showed him) are not
visible.

Fix (ui A, Theme and one line), for the lead to pick:
- (a) Unowned cards that have an icon take the sample's panel colour as their background, or as the icon's own
  `BackgroundColor3` with a small corner.
- (b) A shelf-only silhouette lighter than the card (a ghost: a dim blue-grey around 2.0:1 against
  (22, 29, 50)), leaving `ARMORY_STAGE_SILHOUETTE` for the stage's light band.

Either way it is a Theme round, not a re-upload.

**m3. T11-T14 pin how the clones and the turn are made, not how they are torn down or driven.**
`tools/crowd_harness/run_harness.py:795-1000` (L3W2_LINES and PATTERNS). Each of these review-only mutants, applied
alone, leaves `HARNESS: PASS (3,950 checks)`. The first four break a sentence of the contract:
- `ArmoryStage.luau:451-454`: `stop()` dropped from `SetActive(false)`. The RenderStepped turn keeps running after
  close or after the Abilities tab (L3-56: "dropped in SetActive(false)").
- `ArmoryStage.luau:281`: `clear()` dropped from `selectFamily`. Every selection stacks another clone in the
  viewport (L3-56: "the previous clone is destroyed").
- `HeldWeapons.luau:251`: `entry.model:Destroy()` dropped from `show`'s cleanup. After an Armory family change, the
  old weapon stays welded on the back beside the new one (L3-51: "A family that leaves the loadout is destroyed").
- `HeldWeapons.luau:317`: `names.held` dropped from the watched names. A teammate's slot switch never shows, and
  neither does their raised arm (L3-51: "again on GetAttributeChangedSignal of each of the three names").
- Also surviving:
  - `show(rig)` dropped at the end of `bind` (`:351`) and in `SetLocalStance` (`:451`);
  - the PlayerAdded watch (`:417`);
  - the mount re-show (`:330`);
  - `setRest`'s ease (`WeaponController.luau:388`: the rest changes but the arm stays until the next pose);
  - `remotePoseFor`'s raised write (`:473`);
  - unowned drawn in colour on the stage (`ArmoryStage.luau:415`) and on the shelf (`ArmoryShelf.luau:289`). This
    one shows unfound weapons in full.

The controls bite: `part.CanQuery = true` in `seal` is caught by T12. This is the recurring pattern: a text check pins
a call, but not the lines around it that make it happen or undo it.

Fix (luau-engineer, `run_harness.py` + `mutate.py`): L3W2_LINES entries for these six texts, each with an `l3w2:`
mutant:
- `stop()` in SetActive's `if not active then` branch;
- `clear()` as `selectFamily`'s first line;
- the cleanup's `cache[family] = nil` + `entry.model:Destroy()`;
- the three-name list in `bind`;
- `show(rig)` in `SetLocalStance`;
- `setRest`'s `rigPoseTo(rig, degrees, …)`.

The rest are wiring that Studio shows at once, so Ben's look covers them.

## Suggestions

- **s1.** `WeaponController.luau:784-790`, the draw. With a ranged model in hand the rest is 80 and
  `COMBAT_DRAW_DEGREES` is 80, so `Draw` tweens 80 to 80: a bow's draw has no arm motion at all.
  - ui B read ruling 6's "measured from that raised arm" as "starts there". Adding 80 to the raise would point the arm
    at the sky, so that reading is right.
  - The lead should say so in §11. If a draw cue is wanted, add a small Theme pull: a few degrees further, or a twist.
- **s2.** `ArmoryStage.luau:459-467`. Before the paste (no template) the RenderStepped callback runs every frame while
  the Weapons tab is open, and returns at once. It is harmless, but L3-60 says per-frame "only while it turns".
  Connect it in `selectFamily` when a model exists, or accept the no-op.
- **s3.** `ArmoryStage.luau:359-389`, the drag.
  - A mouse drag follows any `MouseMovement` until a MouseButton1 `InputEnded`. If that release is lost (focus
    change mid-drag), moving the mouse with no button turns the weapon, and `look.drag` freezes the slow turn until
    the screen closes.
  - Check `UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)` in the InputChanged handler, or end
    the drag on `UserInputService.WindowFocusReleased`.
- **s4.** Gamepad on a low-end device has no way to turn the stage (no slow turn, drag is mouse or touch). A
  right-stick yaw while the screen is open would cover it. The contract only asks for mouse and touch.
- **s5.** `WeaponController.luau:321-328` (`restFrame`), the R6 arm. The raise rotates about the shoulder C0's X.
  - R15 is right: checked against `RightShoulderRigAttachment` and `RightGripAttachment` in the local
    `content/avatar/morpherEditorR15.rbxmx`. Rx(+80) swings the hanging arm to (0, −0.17, −0.98), forward. The grip's
    look runs down the arm and its up is the hand's forward, so the melee hold Rx(90) points the tip forward and the
    ranged identity points it ahead once raised.
  - R6's `Right Shoulder` C0 carries a 90° Y turn, so its X is the torso's forward axis. An R6 avatar would hold every
    ranged weapon out to the side. The W1 draw and swing already did this, but only for a moment.
  - Confirm the experience is R15-only (Game Settings → Avatar), or skip the raise when the shoulder is `Right Shoulder`.
- **s6.** `Theme.luau:437`: `COMBAT_WEAPON_WAIT_SECONDS`'s comment still says "and the prop folder". Only the
  shoulder wait reads it now.
- **s7.** `HeldWeapons.luau:317-324`: `show(rig)` runs once per attribute change.
  - One server write (`showWeapons` sets three attributes) runs `show` three times on every client. Each run makes
    the two weld writes and may start a `setRest` tween.
  - Slice 2 found that `RequestRangeDraw` can flip `WeaponHeld` 40 times a second. Every other client then re-hangs
    and re-tweens that arm at 40/s.
  - The fix belongs on the server (slice 2). As defence in depth, coalesce on the client: a per-rig `pending` flag
    and one `task.defer(show, rig)`. That gives one `show` per frame per character, whatever the burst.

## Checked and clean

- **Seal:** `seal` sets Anchored false, CanCollide, CanQuery and CanTouch false, and Massless true on every BasePart
  of the clone (Base included). It runs before the first parent, and CastShadow is untouched. T12 pins it, and a
  CanQuery mutant is caught.
- **Hit origins:** the shot and melee origins did not move.
  - `InputController.luau` and `CombatFxController.luau` have no diff, and `PredictSwing` is unchanged.
  - `drawPellets` still casts from the strike origin. Only the tracer's start moved.
  - No client code sends the muzzle.
- **Muzzle:** returns the tip only while the model in the hand is parented to that character; otherwise RightHand,
  then Right Arm, then the root, all direct children, then nil.
  - FlameFx and Shared push along the aim only when the point is not from a model. FeedbackController never pushed,
    as before. WeaponController returns `Muzzle or fallback`.
  - Bots (negative ids) fall back as in W1.
  - `Shared.muzzleOf` equals the old rule when no model is in hand.
- **Mounts:** `mountOf` and `firstPart` look up direct children only, and T13 holds. A late part or attachment
  re-shows through `ChildAdded`. Combat has `StreamingEnabled` false, so remote characters arrive whole.
- **Weld maths:** C0 = `attachment.CFrame * hold * CFrame.new(-point)` puts the grip or holster point on the
  attachment. It matches L3-47 (Base at the identity, the template frame = the generator's).
  - The back hold leaves the tip up-left, the model's Y in the back plane and its X into the body, so a bow lies flat
    (ruling 6).
- **Rest poses, traced on the code:**
  - local switch both ways: `cancelPose` snaps to the old rest, then `setRest` eases;
  - a swing after a switch: `cancelRig` snaps to rest 0, then the windup;
  - `Release` returns to the rest;
  - a kick goes to rest + 25, then the delayed `Release`;
  - local respawn works in either order of the two CharacterAdded handlers;
  - a remote raise before the shoulder exists;
  - remote respawn with the ranged slot in use (snapped raised in `remotePoseFor`);
  - `Destroy` lets every arm hang;
  - only WeaponController writes a shoulder C0.
- **Other players' arms:** `SwingOther` runs only for `swing and not mine` (no ability, no tick, a melee variant).
  - Whiffs are broadcast too (`WeaponService.finish` always sends), so remote swings show on misses.
  - The attack path writes `WeaponHeld` before the strike broadcast, so the arm drops before the swing plays.
  - T9's single exit before the call is the empty-flight return, which a melee swing never takes.
- **No per-frame work in HeldWeapons:** no RunService, no task loop. FlameFx and `stepBeams` call Muzzle per frame, a
  table lookup like the old helper.
- **Leaks:** checked on death, respawn, removal and leave, and none found.
  - Rig connections and the mount parts' ChildAdded are dropped in `unbind`, which runs on Died, CharacterRemoving,
    a rebind and PlayerRemoving. Player connections go on PlayerRemoving.
  - Models are destroyed in `unbind`.
  - The weak caches (`models`, `remotePoses`, `raisedRigs`, `rigTracks`) are keyed by characters that `rigs` holds
    strongly only while they are bound.
  - Downs never kill the Humanoid (VitalsService keeps `DOWN_HEALTH`), so `Died` cannot strip a downed player's
    weapons.
- **Stage:**
  - one clone per selection, destroyed on a change, on `Show(nil)` and on `Destroy`;
  - it stays hidden (not rendered) while the screen is closed;
  - the turn runs only from `SetActive(true)`, behind `not Theme.lowEndDevice`, and is dropped on close, on the
    Abilities tab and on teardown;
  - a drag ends on release or close, and on a low-end device each drag event places the camera once;
  - the camera distance fits the bounds sphere on the narrower axis;
  - Base is invisible in the viewport.
- **Screen:** `paintTabs` (open, tab switch, init) and `setOpen(false)`, which close, `SetAvailable(false)` and
  teardown all pass through, are the only `SetActive` callers.
- **Shelf:**
  - card sizes are unchanged (92 × 56 and 68 × 56), so L3-23's three fits hold, and touch stays ≥ 48;
  - with id 0, `shape(false)` restores every W1 property: name position, size and wrap; tier anchor, position,
    alignment and wrap; dot anchor and position;
  - `Assets.json` v5 icons are uploaded with `imageId` 0 before the paste, so every card is W1's text card.
- **W1 look without templates:** the stage's `dress(false)` path and its gradient rule equal W1's. HeldWeapons is
  silent with no templates (it warns only on a config fault or an unknown family), and arms hang because no ranged
  model means no raise.
- **Removed API:** nothing references `WeaponController.SetGear`, `SlotTiers` (its export), `COMBAT_GRIP_*` or
  `COMBAT_HOLD_GRIP`.
- **Requires:** no cycle. HeldWeapons requires only shared modules, Create and Theme; Shared and FeedbackController
  require it.
- **Gates:**
  - `check_compile` PASS (180 files, FeedbackController 163);
  - stylua and selene are clean on the 11 files;
  - all are `--!strict`, with no `wait`, `spawn` or `delay` and no parent argument;
  - the harness passes 3,950 on the archive copy.
