# L2 W3 — ui-engineer report

Branch `l2-w3` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing is committed. This is the contract's §10 ui-engineer item, built against luau-engineer's `WorldReact` (`Strike.arcDegrees`, `Chills`) and `Types` (`CombatIceConfig`, `ExpeditionsConfig.found`) as they landed.

## Files

### New

- `src/combat/client/Controllers/FrostFx.luau`
  - `IsIce(weapon)`: true when the family's element is ice.
  - `OnSwing(swing)` runs on the local player's swing, on the frame it is sent:
    - a frost puff along the arc;
    - `ReactFx.PredictFreeze` with the strike the server builds: the root, the flat look, the variant's range, and the arc for that combo step (the finisher's arc on the chain's last step, as `resolveMelee` does).
  - `OnStrike(strike)`: the puff for other players' ice swings.
  - `Destroy`.
  - The puff is particles only, so it is skipped when `Theme.lowEndDevice` is set. The frost hitbox colour still shows the swing is ice.
- `src/combat/client/Controllers/AbilityFx/FrostQuake.luau`: L2-50.
  - Same timing as Earthquake: slam, a front that steps out ring by ring, and each exact ring flashing as it lands.
  - In the ice palette, with Ice-material shards that spring up round each ring and sink away (instead of cracks) and a frost mist burst.
  - Low-end devices get 5 shards per ring instead of 10, and the particles are halved through `Shared.particles`.

### Changed

- `src/combat/client/Controllers/ReactFx.luau`
  - Adopts every `Workspace.Level` Part whose `Ice` attribute is a boolean.
  - `ForEachIce(cb)` lists only the cells whose `Ice` is false.
  - `IceReach()` returns `reachDown` and `ahead` from `levels.react.ice`, or nil.
  - `PredictFreeze(strike)`: L2-56.
    - Puts a ghost on every unfrozen cell `WorldReact.Chills` names. The ghost is a local Ice-material Part: translucent, anchored, never colliding, queried or touched.
    - The ghost goes when that cell's `Ice` turns true, or after `COMBAT_FROST_GHOST_SECONDS` (0.5 s).
    - A second swing over the same cell only renews the timer.
    - Ghosts draw on every device, because they are information.
  - The `react` CombatFx with event `"frozen"` draws a glint over the cell, plus a frost-mote burst on devices that are not low-end.
  - `Destroy` clears the ghosts and the ice list.
- `src/combat/client/Controllers/InputController.luau`
  - `frostQuake` joins `earthquake` in `busySecondsOf`.
  - New `iceOnAuto` (L2-55). In `targetOnAuto`'s melee branch:
    - any body in the swing shape decides as before, whether takeable or refused;
    - with no body, an ice family swings when `WorldReact.Chills` holds for an unfrozen cell;
    - the check uses the strike the server builds: root, `flatCameraLook()`, `variant.range`, and the narrower of the arc and the finisher's arc, so the phone never swings where the server would freeze nothing.
  - No change to `SetSwingHandler`: FeedbackController stays the one handler and routes to FrostFx.
- `src/combat/client/Controllers/FeedbackController.luau` (routing only):
  - adds the `FrostFx` require (161 top-level locals);
  - an ice family's swing hitbox takes `COMBAT_FROST_HITBOX_COLOR` (crit and ability colours still win, so Frost Quake's strikes keep the ability colour);
  - `PredictSwing` calls `FrostFx.OnSwing` before `drawHitbox`, so the ghosts show even when `hitboxEffect` is 0;
  - other players' swings go to `FrostFx.OnStrike`;
  - `Destroy` calls `FrostFx.Destroy`.
- `src/combat/client/Controllers/AbilityFx/init.luau`: adds `frostQuake` to `BUILDERS`.
- `src/combat/client/UI/ArmoryWeapons.luau`
  - `HiddenWhere` now returns the whole line each locked card shows: "Hidden on <level>" for a family a secret pays, then the entry's `text` for a family Expeditions `found` names.
  - An unowned family is listed only when one of those two names it.
  - The Frost Hammer card is locked, shows the ICE chip and reads "Found in the Castle".
- `src/combat/client/Controllers/CombatUIController.luau`
  - `fireFamily` becomes `elementFamily(element)`, with `ELEMENT_FAMILY_KEYS` F = fire and I = ice.
  - The I key sends `grantFamily` or `removeFamily` with the first family (by id) whose element is ice.
  - `DEBUG_HINT` gains "· I frost hammer".
  - The strip gets `iceFamily`, and the snapshot updates `SetIceFamily`.
- `src/combat/client/UI/DebugPanel.luau`: `deps.iceFamily` adds a "Frost Hammer: ON/off (I)" button; `SetIceFamily` sets its caption.
- `src/client/UI/Theme.luau`: new `REACT_ICE_*` and `COMBAT_FROST_*` keys (hitbox, puff, ghost and Frost Quake colours).
- `sourcemap.combat.json`: regenerated with rojo; it picks up the two new files.

## Remotes, state and config consumed

No new remotes. The client reads:

- the `RequestDebug` levers `grantFamily` and `removeFamily` (W2);
- the `Ice` attribute on the `Workspace.Level` Parts;
- the CombatFx `react` event `"frozen"` with the box `x, y, z, sx, sy, sz`;
- the Snapshot's `combat.families`;
- the config: `ProvingGrounds.json` `weapons.*.element`, `arcDegrees` and `finisherArcDegrees`; `Combat.json` `levels.react.ice` (`reachDown`, `ahead`); `Expeditions.json` `found`.

## Gates

- `py tools/check_compile.py`: PASS, 174 files. FeedbackController has 161 top-level locals and InputController 157.
- stylua `--check` on `src/combat/client` and Theme: clean.
- selene on the same files: 0 errors, 0 warnings.
- luau-lsp (`--definitions=tools/types/globalTypes.d.luau`, both sourcemaps regenerated with rojo):
  - the combat sourcemap over `src/combat/client`, Theme, MapScreen and `src/shared`: exit 0, no diagnostics;
  - the default sourcemap over `src/client` and `src/shared`: exit 0, no diagnostics.
- `rojo build combat.project.json` to scratch: builds.
- All my files are LF.

## Must check (by reading and by a Python mirror of `Chills` on the designer's layout)

- **Phone auto-swing at the creek's edge.**
  - From the sign pad's west edge facing west, a swing freezes 4 cells; facing south, 3.
  - On ice it keeps firing at the next unfrozen cells ahead, which is how you freeze your way across.
  - A frozen cell never triggers, because `ForEachIce` lists only cells whose `Ice` is false.
  - A resting body inside the swing shape stops it before any water is asked, because `enemyInReach` reports it as refused first.
- **Road2 (the bridge). Flag for the lead.**
  - The 140° arc reaches range + ahead = 13 studs, so the creek's first row (cell centres at z 11.4) falls inside it from the road's south half.
  - Walking west with the camera along the road at z 0 to 7.5, the phone auto-swings while x is between about −405 and −381. Walking east, between about −419 and −395.
  - From z −2 and further north it never swings.
  - This is exactly the server's rule: those swings really do freeze 1 to 3 cells beside the bridge. They are harmless, but Ben may see the hammer swing on its own while crossing.
  - If he dislikes it, the fix is a lead ruling, not mine to invent: for example a narrower auto-only cone such as `controls.iceAutoDegrees`. That would only ever stop swings, never add a false one.
  - First-run players are not affected: the hammer is owned only through the Studio lever.
- **Armory card** (the W2 numbers hold):
  - A fresh profile now has 2 melee cards (Broadsword, plus the locked Frost Hammer) and 2 ranged cards (Longbow, plus the locked Flamethrower). The page is 190 design px, the same tallest column W2 measured.
  - 667×375: no scroll (235 design px of room).
  - 640×360: fits (219 design px of room).
  - 375×667 portrait: the sheet is 312 px wide.
  - The ICE chip is about 30 px wide and "Frost Hammer" about 96 px, which fits the 147 px card row. "Found in the Castle" fits on one line of the 48 px locked row, which wraps anyway.
  - Gamepad: a locked card has no button, so selection skips it, as with the Flamethrower in W2.
  - 1920×1080: unchanged from W2 (about 527 × 440 px).

## For other owners

- **luau-engineer:** nothing is needed. I rely on two things:
  - `Ice` is set before the cell is parented, which is true in today's `construct`;
  - the frozen event's box is the cell's.
- **Lead:**
  - the Road2 auto-swing note above;
  - the I key's hint line is one longer unwrapped Studio-only line (keyboard only), as F made it in W2.

## What Ben must check in Studio

1. Press I in the lobby. The strip button reads "Frost Hammer: ON (I)", and the Armory's melee column shows the hammer as owned with the ICE chip. Press I again: the card is locked again and reads "Found in the Castle". Check this also at 667×375 in the phone emulator.
2. Equip the hammer and walk to the sign pad by the creek.
   - Each swing turns the arc pale blue with frost mist and puts ghosts of ice on the water ahead at once.
   - The real ice replaces each ghost with a glint and frost motes. Is the replacement visible as a flicker?
   - About 9 swings should reach the island.
   - Ice must feel solid underfoot, with no slide.
3. In the phone emulator with the hammer: stand at the creek's edge facing the water and it swings by itself. Walk the bridge's south half: does the stray auto-swing at the creek's head bother you?
4. Press Q (Frost Quake, the melee ability): ice rings and shards, and the ability-coloured ring strikes on top.
5. Low graphics (quality ≤ 3): no puff and no motes, but the ghosts and the glint still show.
