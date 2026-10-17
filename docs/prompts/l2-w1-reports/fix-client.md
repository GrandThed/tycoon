# L2 W1 fix round: client agent

Branch `l2-secrets` in `tycoon-p5`. Nothing is committed. I edited only my own files, plus one new
one, `src/combat/client/UI/ActionRows.luau`. I coded against the server agent's diff as it
landed: `WallClip.GroundFloor`, `Unlocks.MAX_ID_LENGTH` / `MAX_FAMILY_LENGTH`, `Unlocks.Sellable`,
and the `coyoteSeconds: number` field it added to `Types.luau`.

## Findings

**c1: the lobby HUD row covered the health bar and the Dash button. I chose rows, not a capped
width.**
- What I did:
  - The bottom-left buttons now go in rows from the new pure module `ActionRows` (`Pack` and `Room`).
  - Each row ends one control gap (8 design px) before anything that stands in its own band.
  - Buttons that do not fit move up a row. Rows fill from the bottom up, so the list reads left to
    right and top to bottom.
  - The host passes in what stands at the bottom of the screen:
    - every button of the thumb cluster;
    - Roblox's jump button;
    - the health bar, using its own rule, now the pure `VitalsHud.BarPlace`;
    - the AbilityBar, whose `SetLayout` now returns its edges.
  - The key hints and the perf line sit above however many rows there are.
  - The range HUD passes nothing, so it keeps one row.
- Where:
  - `src/combat/client/UI/ActionRows.luau` (new): `Room` :36, `Pack` :57.
  - `src/combat/client/UI/CombatHud.luau`:
    - the `Obstacle` type :153;
    - `packActions` :822, called from `paintAbandon` and `SetLayout` :1529;
    - the UIListLayout is removed.
  - `src/combat/client/Controllers/CombatUIController.luau`: `bottomObstacles` :445; the mission
    `applyLayout` :2052 now builds the vitals layout and the AbilityBar edges before `hud.SetLayout`.
  - `src/combat/client/UI/VitalsHud.luau`: `BarPlace` :155. `applyLayout` draws by it.
  - `src/combat/client/UI/AbilityBar.luau`: :585 returns the bar's left, top and bottom
    (`math.huge, 0, 0` when hidden on touch).
- Layout chosen, measured at MIN_SCALE 0.917. I ran the real `ActionRows` under `luau.exe`, with
  the cluster and bar formulas copied from the Theme numbers. All values are screen px; the top bar
  inset is 58.

| Viewport | Rows (top to bottom) | Button x ranges | Nearest obstacle in the band |
|---|---|---|---|
| 667x375 | `[Map]` / `[Abilities][Return]` | Map 7.3-73.3, Abilities 7.3-88.0, Return 95.3-190.7 (y 320-364) | Health bar starts at x 241.8, so Return is 51.2 px clear (it was overlapping by 22 px) |
| 640x360 | `[Map]` / `[Abilities][Return]` | Same widths, y 305-349 | Health bar starts at x 228.3, so Return is 37.4 px clear |
| 375x667 | `[Map]` / `[Abilities]` / `[Return]` | Map 7.3-73.3, Abilities 7.3-88.0, Return 7.3-102.7 | Slot button starts at x 158.2, so Return is 55.5 px clear. Dash starts at 215.6 |
| 1920x1080 | One row | Return ends at x 441 | AbilityBar starts at x 758; health bar 807 |

- More on these layouts:
  - In portrait the top row (Map, y 509-553) sits under the health bar (y 490-507). They do not
    overlap, because the health bar starts at x 95.8 and Map ends at x 73.3.
  - With a 36 px inset, 667x375 gives the same layout as the 58 px inset.
  - `proving.rbxl` has no Return button. There, Map and Abilities fit in one row at 667x375 (right
    edge 161.3). In portrait they stack, Map above Abilities.

**c2: a gamepad can now open and use the Abilities panel.**
- What I did:
  - ButtonY toggles the panel. It is bound at High+1 only while the lobby is up. In a run, Y stays
    the weapon swap; the panel overrides Y only in the lobby.
  - When the panel opens after gamepad input, the first live Buy is selected, or the X button if no
    Buy is live.
  - The sheet is a SelectionGroup that stops at its edges, and the scrim cannot be selected.
  - ButtonB closes the panel. It is bound at High+1, above the dash's High, only while the panel is
    open. Closing also clears the selection.
  - The map now closes in the panel's `onOpenChanged`, so every way in (button, K, Y) closes it.
  - Hints on a gamepad:
    - the panel line reads "Y or B closes";
    - the first refused air jump says "(Y)";
    - on a console (gamepad, no keyboard, no touch) the HUD button reads "Abilities [Y]".
- Where:
  - `src/combat/client/UI/AbilitiesPanel.luau`: header; `PAD_TOGGLE_NAME` :107; SelectionGroup
    :192; `setOpen` :429; `bindPadToggle` :472; `SetLobby` and `Destroy` unbind.
  - `CombatUIController.luau`: hints :189 and :191; `onOpenChanged` closes the map :1485;
    `padToggle = true` :1500; `abilitiesKey` :1571.
  - `CombatHud.luau` :557.

**c3: walk-off grace.**
- What I did:
  - Added `movement.coyoteSeconds` = 0.12 (`src/shared/Config/ProvingGrounds.json:262`).
  - When the body leaves its floor, `noteTakeoff` (`MovementController.luau:287`) records:
    - the time;
    - the root's height;
    - whether it walked off: it rose at less than half a jump's take-off speed. A jump, an enemy
      launch past the window, or our own air jump all leave faster.
  - A press within `coyoteSeconds` of a walk-off is the ground jump (`jumpFromAir(jumpHeight)`,
    :298). This needs the root to be no higher than where it left the floor. The air jump stays
    unused (:492).
  - A press in the same frame as the take-off counts.
  - Any later press in a walk-off airtime never shows the "buy Double Jump" hint (:517). A late
    press after walking off is a late jump, not a second one. Owners still get the air jump as
    before.
- Why route rules do not change:
  - The grace jump starts at or below the floor walked off.
  - So its apex is at most `jumpHeight` above that floor, the same as an ordinary jump from it.
- The data agent still has to confirm that sim_range and check_levels need no change.

**c4 (client half): one shared ground rule.**
- `InputController.groundPoint` step 4 is now a single call to
  `WallClip.GroundFloor(floorHit(root), feetY, floorHit(point + lift), Tuning.Get().movement,
  LocalPlayer:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)))`
  (`src/combat/client/Controllers/InputController.luau:1871`).
- `WeaponService.GroundPoint` makes the same call with the server's own read of the attribute.
- The return values are unchanged: `(nil, casterFloor)` on a refusal, otherwise the point plus
  `casterFloor` for `Leap`.

**c5 (client half), plus s4 on the client: one cap and one rule for repeated ids.**
- What I did:
  - Removed the panel's own `MAX_ID_LENGTH = 32`.
  - `AbilitiesPanel.Offers` now reads `Unlocks.Sellable(expeditions)`
    (`AbilitiesPanel.luau:113`). The panel therefore offers exactly what `Find` and
    `UnlockService.Init` sell: the id cap, an empty `text`, and the first sellable entry of a
    repeated id.
  - `Offers` now takes `Types.ExpeditionsConfig?`.
- I found no length check on family ids anywhere in the client.

**c6: map key words.**
- `MAP_SECRET_KEY_TEXT` goes from 9 to 11 (`src/client/UI/Theme.luau:1357`).
- The 30 px row still fits: 16 icon + 11 + 3.
- "2× JUMP" is about 47 design px wide in GothamBold 11. The cell is 50, so there are about 3 px
  to spare.

**c7: the found card sits above the crosshair.**
- What I did:
  - `SecretFx.SetLayout(scale, crossY)` (:488). The host passes `viewport.Y / 2 - inset.Y`.
  - `placeCard` (:309) works out the card's height from the rows it shows this time.
  - The card's bottom sits one margin above the reticle's resting ticks (melee gap 10 + tick 9 +
    margin 8, design px).
  - The card's top never goes above the screen margin.
- Measured:

| Viewport | Card with two lines (88 px tall) | Card with the family note (106 px tall) |
|---|---|---|
| 667x375 | y 16.8-104.8; the resting ticks reach y 112.1 | Pinned at the margin, ends at 113.7: 1.6 px over the top tick, 15.8 px above the dot |
| 640x360 | y 9.2-97.2 | Ends 9 px over the top tick, 8.4 px above the dot |
| 375x667 | | y 144-251, under the notice line (ends 119) |
| 1920x1080 | Clear | Clear |

- Trade-off on landscape phones:
  - The card is 275 px wide and centred on the crosshair. For its 3 s it now overlaps the right end
    of the header and wallet, which run to x 330.
  - Before, it covered the aim point instead.
  - The card itself shows the "+N Valor" that the wallet's hidden Valor chip would show.

**Launch-stacking note:** answered by the data agent (closed, no change from me).

## Gates (all on my files, after the server agent's shared diff landed)
- stylua `--check`: clean.
- selene: 0 errors, 0 warnings.
- luau-lsp with `tools/types/globalTypes.d.luau`, after regenerating both sourcemaps with rojo:
  - combat map over `src/combat` and `src/shared`: exit 0;
  - hub map over `src/client` and `src/shared`: exit 0.
- `py tools/check_compile.py`: PASS, 165 files. Top levels: InputController 152, MovementController 109.
- `rojo build combat.project.json` to scratch: built.
- All files are LF. `sourcemap.combat.json` changed because ActionRows was added.

## For other owners
- **Server agent (done):** `Types.luau` `RangeMovementConfig.coyoteSeconds: number` is already in
  its diff. The harness case and mutation for `GroundFloor` are its job.
- **Data agent:** please confirm that `coyoteSeconds` needs no change to sim_range or check_levels.
  My reason: the grace jump starts at or below the floor walked off.
- **docs (later):** add a PLAYTEST note on the gamepad Y in the lobby and on the walk-off grace.

## What Ben must check in Studio
1. **Phone emulator at 667x375, a non-proving build so that Return shows.** In the lobby, Map sits
   above Abilities and Return. Return ends well short of the health bar, and nothing covers the bar.
   Also check 640x360, and a portrait 375x667: three stacked buttons, none on Dash or the slot
   button.
2. **PC:** Map, Abilities and Return stay in one row, with the Studio key line and the perf line
   above it.
3. **Gamepad.** The selected Buy must activate with A and must not also jump; I could only reason
   about this from Roblox's selection rules.
   - In the lobby, Y opens the panel and closes the map.
   - The first live Buy is highlighted, and A buys.
   - B closes the panel and does not dash.
   - In a run, Y swaps weapons as before.
4. **Walk-off.**
   - Walk off a ledge and press jump just after: you get a full jump, and no "buy Double Jump"
     toast.
   - A late press with no double jump does nothing and says nothing.
   - A deliberate second press after a real jump still shows the toast once.
5. **Map card:** the key words read at the larger size, and "2× JUMP" is not cut off.
6. **Lookout chest found in a run:** the card shows above the crosshair, not on it. On a landscape
   phone it briefly covers the right end of the header.
