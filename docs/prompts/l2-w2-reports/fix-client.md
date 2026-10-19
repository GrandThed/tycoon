# L2 W2 fix round: client report (ui-engineer, 2026-10-18)

Branch `l2-w2` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing is committed. I edited only `src/combat/client/**` and `src/client/UI/Theme.luau`.

From the server agent's shared diff I use `WorldReact.Wants`, `WorldReact.BoxOf` and `WorldReact.Pad`. I never edited its files. For a short while I had my own copy of the burn rule in `CampAim`. I reverted it once `Wants` landed, so `CampAim.luau` is unchanged.

## Findings

**c-M1: phones could not burn the bramble.**
- `InputController.luau:1334`: new `reactOnAuto`.
  - It walks every reactive Part with `ReactFx.ForEachPart`, which hands over each Part's `React` and `Heat`.
  - The element comes from `Unlocks.ElementOf(cfg.weapons, activeFamily)`.
  - The test is `WorldReact.Wants(element, react, heat, capsule, BoxOf(part), Pad(levels.react))`.
  - The capsule is built as the server builds it: from the shot origin along the look, with `size` = the reach cut at the wall, and the variant's width.
- `InputController.luau:1393`: the capsule branch of `targetOnAuto`.
  - It first cuts the reach (`streamReach`).
  - It then tests bodies. An awake body fires. A refused (resting) body in the capsule holds fire, including at a bramble.
  - Only when the capsule holds no body at all does it fall through to `reactOnAuto`.
- `InputController.luau:1327`: `enemyInReach` now sets `aimHeld = refused` instead of `found and refused`. Without this, after a raider died the stream's ride-out (`beamHoldUntil`) could keep firing into a resting body standing in the capsule. That flag is read only by continuous variants, so swings and cone guns behave as before.
- `ReactFx.luau:259`: new `ForEachPart`. It covers the reactive Parts already tracked from `Workspace.Level`. It is empty in the range and before Mount.
- Harness: the pure part is `WorldReact.Wants`, which belongs to the server agent and is in its tests. No client code sits outside it apart from the Instance reads.

**c-M2: the flame was drawn short.**
- `InputController.luau:2580` adds `ShotRay()`: `shotRay(localRig)`, the line `rangeAttack` sends. It returns nil, nil when there is no character.
- `InputController.luau:2590` adds `StreamReach(origin, look, range)`, the same wall cut auto-fire uses (`streamReach` :1111). It uses the world query moved up from the cast code: players excluded, RespectCanCollide on, the same as WeaponService's `worldReach`.
- `FlameFx.luau:286`: the local flame now gets its start and its tip from these two calls.
  - The tip is shot origin + look × reach. It is drawn from the hand: `reach = (tip − hand)·look`.
  - The camera ray, FlameFx's own `wallParams` and its `CameraController` require are gone.

**c-m1.** `CameraController.luau:441-447`: `openPivot` now runs `clearDistance(params, head, offset)`. That is the boom's own spherecast (radius 0.5) stopped 0.2 short. Header comment :86-98 updated. A correction to my W2 report: the cast runs on every frame where the pivot's height lags. That includes jumps, falls and slopes, not only "never in ordinary play". It is one cast a frame.

**c-m2: gamepad re-select.**
- `ArmoryPanel.luau:292` adds `reselect`. While the sheet is open and the last input was a pad, it moves the selection to `firstSelection()` if the current selection is nil, unselectable, or outside the sheet.
- It is called:
  - on every Weapons-page repaint, through the new optional `deps.onRepaint` (`ArmoryWeapons.luau:45`, :360). That covers the pick, the timeout, `OnResult`, `SetLoadout` and the rebuild;
  - after `SetState` (:460);
  - after an Abilities `OnResult` (:490).
- The first paint runs inside `new`, while the sheet is closed, so it is guarded (:204).

**c-m3.** `ArmoryWeapons.luau:579`: a `setFamily` answer frees the pending pick only when `slotId == pending.family`. A late answer still shows its toast.

**c-m5.** Both effects are now gated on `Theme.lowEndDevice`:
- `ReactFx.luau:180`: the bramble's ghost shrink. The header was updated.
- `FlameFx.luau:239`: the flame's flicker. The header was updated.

**c-m6.** `FlameFx.luau:313`: the local player's own server strikes only correct the width. The local stream lives on local shots alone, so it goes out one linger (2 intervals, at least 0.25 s) after release. `OnStrike` no longer touches `range`, and the dead `reach` seed in `onLocalShot` is removed.

**c-m7.** `Theme.luau:1344`: one constant, `ABILITIES_RESULT_TIMEOUT_SECONDS`, now commented as "both Armory tabs". `LOBBY_ARMORY_RESULT_TIMEOUT_SECONDS` is removed, and ArmoryWeapons uses the shared one (:383).

**c-m8.** Stale comments fixed:
- `CombatHud.luau:77-93`: Armory button, `deps.onArmory` and `deps.armoryKey`.
- `CombatUIController.luau:102-121`: K opens the Armory panel, Buy is on its Abilities tab.

## Gates
- `stylua --check` and `selene` on `src/combat/client` + Theme: clean (0/0).
- `py tools/check_compile.py`: PASS (172 files).
- Sourcemaps regenerated with rojo; they are unchanged.
- luau-lsp exit 0 in both runs:
  - combat sourcemap over `src/combat/client`, Theme and `src/shared`;
  - default sourcemap over `src/client` and `src/shared`.
- All files are LF.

## For other owners
- **Server agent (d-m3):** one legitimate shot the new origin check could refuse.
  - The shot origin is the camera line at the head's depth, which is the shoulder offset (about 1.5–2 studs) beside the head.
  - With the shoulder side against a thin wall's end, or at a bend of the 2-stud tunnel walls, the camera's shoulder spherecast pulls in. The line at head depth can still pass the corner on the far side of the wall's edge.
  - A head→origin ray would then cross the wall. The most likely place is the inner corner of a tunnel bend, while hugging it.
  - Please make the refusal answer with a reason I can see in Studio, or allow for the collision radius.
- **Lead / docs-keeper:** PLAYTEST needs a phone step: "667 × 375 emulator: equip the Flamethrower, face the bramble at Road4's mouth with no raider near; the stream fires by itself and burns it; with a resting raider inside the flame, it does not fire".
- No `Main` wiring is needed.

## What Ben must check in Studio
1. **Phone (emulator, 667 × 375):**
   - With the Flamethrower held, walk up to the tunnel's bramble and face it. The stream fires by itself and the bramble burns.
   - Do the same from RoadAB5 at the exit bramble.
   - Through a wall or fence, an awake raider 15 studs behind it must not start the stream.
2. **Flame length:** hold fire at a raider about 15 studs away. The drawn flame reaches it, and the tick numbers appear at its tip, not beyond. It looks the same at full zoom-out, in ADS, and as a partner sees it.
3. **Release:** let go while turning. The flame goes out at once and does not follow the camera for a moment.
4. **Gamepad, Armory Weapons tab:**
   - Press A on Flamethrower "Equip". The selection must land on a live button, or on the Weapons tab, and never on nothing. The left stick must not walk the character.
   - Do the same after F grants or removes the family.
   - Open question: does the engine itself drop a selection whose `Selectable` turns false?
5. **Phone / touch:** the bramble collapses (it shrinks, not only fades). On a low graphics level (1–3) it only fades and the flame does not flicker.
6. **Camera at the tunnel exit's inner corner after a Leap Smash:** the view never shows the outside of the ridge.
