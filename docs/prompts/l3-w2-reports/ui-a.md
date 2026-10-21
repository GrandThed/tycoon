# L3 W2 — ui-engineer A report (the stage and the shelf icons)

Branch `l3-w2` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing is committed.

## Files changed

- `src/client/UI/ArmoryStage.luau`: L3-56.
  - It now holds a ViewportFrame behind the same API, plus `SetActive(active)`.
  - The model is cloned once per selection, anchored, and posed once with `PivotTo` in `selectFamily`.
  - The camera orbits the config's bounds sphere. The slow turn is one `RenderStepped` connection, made in `SetActive` behind `not Theme.lowEndDevice`.
  - Drag works on every device. The first activation warms the folder with `PreloadAsync`.
  - Unowned weapons show as a silhouette over the light band.
  - When a model shows, the text shrinks to a top line: the slot word and the chip.
- `src/client/UI/ArmoryShelf.luau`: L3-57.
  - Each card has an icon (`ImageLabel`) whose image id comes from `WeaponLook.IconId`.
  - `shape(card, withIcon)` places the parts in one of two layouts. Id 0 gives W1's text card: the same properties, now set in one function.
- `src/client/UI/ArmoryScreen.luau`: the two `SetActive` calls only.
- `src/client/UI/Theme.luau`:
  - every L3-58 constant, ui-engineer B's `COMBAT_HOLD_GRIP` / `COMBAT_HOLD_BACK` included;
  - `COMBAT_GRIP_FORWARD`, `COMBAT_GRIP_UP` and `COMBAT_GRIP_PITCH_DEGREES` removed (nothing reads them; checked by grep);
  - **two constants beyond L3-58** for the icon card's own layout, which L3-57 makes my call: `ARMORY_SCREEN_CARD_ICON_PAD = 3` and `ARMORY_SCREEN_CARD_ICON_TOP = 2`.

## Remotes and state consumed

- No remotes.
- The stage reads `Catalog.GetWeaponModelsConfig()`, `WeaponLook.Def` and the `bounds` in the config, plus `ReplicatedStorage.Assets.Props[<folder>][<model>]`. Lookups go one child at a time, never recursive and never waiting.
- The shelf reads `WeaponLook.IconId(Catalog.GetAssetsConfig(), Catalog.GetWeaponModelsConfig(), family)` on every paint.
- Both ArmoryModel `Card` fields are unchanged. `ArmoryModel` and `tests_l3_ui.luau` are untouched.

## Pinned lines (T14), checked against the shipped `run_harness.py`

The luau-engineer has already pinned these exact texts. The harness passes: `HARNESS: PASS (3,920 checks)`, with every T14 count at its expected value.

- `ArmoryStage.luau`:
  - `\t\tSetActive = function(active: boolean)` … `\t\tend,`
    - Inside it: `\t\t\tif not Theme.lowEndDevice then`
    - then `look.turn = RunService.RenderStepped:Connect(function(deltaTime: number)`. This is the file's only `RenderStepped:Connect(`.
  - `\tlocal function selectFamily(family: string): ()` … `\tend`
    - Inside it, the file's only `PivotTo`: `\t\tlocal pose = CFrame.Angles(math.rad(Theme.ARMORY_STAGE_TILT_DEGREES), 0, 0)` followed by `\t\tmodel:PivotTo(pose)`.
  - There is no `Theme.reducedMotion` anywhere. The header comment says "never reducedMotion".
  - The helper is named `selectFamily`, not `select`, because selene flags shadowing the builtin `select`.
- `ArmoryScreen.luau`:
  - `stage.SetActive(view.open and shown == "weapons")` is at the end of `paintTabs`. That covers open, the tab switches and init.
  - `stage.SetActive(false)` is in `setOpen`'s closing branch. That covers close, `SetAvailable(false)` and teardown.

## How the icons fit (design px; text measured in Montserrat Bold)

**Font.** Studio's font folder ships `Montserrat-Bold.ttf` and no Gotham file, so that is what `GothamBold` draws with. I measured with Pillow at em = TextSize, which is the upper bound. If Roblox scales glyphs to the line height instead, every width is about 0.82 of these.

The card size is unchanged in both orientations: 92 × 56 landscape and 68 × 56 portrait. The shelf heights are unchanged too: 64 in landscape, 180 in portrait. So the 682 × 313, 712 × 330 and 393 × 648 fits of L3-23 hold exactly as in W1.

**Placement in an icon card** (pad 3):

| Part | Where | Rule |
|---|---|---|
| Name | y 2 to 15, across the card's width less the pads | one line, size 11 shrinking to 8, never wraps |
| Icon | 40 × 40 at x 3 to 43, y 15 to 55 | `ScaleType.Fit` |
| Tier line | from the icon's middle (x 23) to the right pad, y 15 to 53 | right and bottom aligned, wraps at spaces, 14 owned / 11 unowned, down to 8 |
| Element dot | x 3 to 11, y 15 to 23 | sits on the icon's upper-left corner |
| Held bar, selection ring | as in W1 | |

I checked the corners on the 15 icons at 40 px. The upper-left 18 × 14 is 0 to 3% opaque in every icon, and the lower-right is 0 to 11% (Smg is the highest). So the dot and the tier text sit on empty art.

**Landscape, 92 × 56** (640 × 360, 667 × 375, and 1920 × 1080 where the frame caps at 880 × 420):
- The name is 86 wide. Every name fits at 11: the widest are "Frost Hammer" 83.1, "Flamethrower" 81.9 and "Piercing Rifle" 77.2.
- The tier line is 66 wide. "T20" at 14 is 26.4. "Not found" fits on one line at 11 (58.2).

**Portrait, 68 × 56** (375 × 667 → 393 × 648):
- The name is 62 wide. Sizes reached:
  - 8: "Frost Hammer" (60.5), "Flamethrower" (59.6), "Piercing Rifle" (56.1);
  - 9: "Warhammer" (60.1), "Broadsword" (57.7);
  - 10 to 11: every other name.
- No name goes below 8 and none breaks mid-word. W1's text card gives a 58-wide name, where "Flamethrower" at 8 (59.6) is borderline; the icon card's 62 clears it.
- The tier line is 42 wide. "T20" fits on one line at 14. "Not found" goes to two lines at 11 ("found" 34.2), sitting over the icon's empty lower-right corner.

**Touch.** Every card is at least 48 design px, which is 44 physical at `MIN_SCALE`.

**Unowned icons** use `ImageColor3 = ARMORY_STAGE_SILHOUETTE` on W1's dark card (22, 29, 50).

## The stage at each size

- **Sizes:** 220 × 173 at 682 × 313, 229 × 189 at 712 × 330, 377 × 223 in portrait, and 285 × 280 on a 1920 × 1080 monitor.
- **Distance:** `radius / sin(half-angle) × 1.15`.
  - At all four of those sizes the aspect is at least 1, so this is the contract's formula exactly.
  - On a desktop window where the stage is taller than wide (for example 267 × 280 at a 900 × 700 window), I use the narrower horizontal half-angle so the sphere never clips.
  - Broadsword example: radius 2.03, distance 9.0 studs. Side-on it spans about 64% of a landscape stage's width.
- **Drag direction:** dragging right turns the weapon's near side right. The slow turn goes the same way, so a rightward drag turns it faster. A drag pauses the slow turn, and the turn carries on from where the drag left it.
- **Yaw** resets to 35° on each new selection. Reopening the screen on the same weapon keeps its yaw.

## Assumptions

- The viewport and the icon draw one ZIndex below their siblings (`Theme.ZINDEX_CARD - 1`). Both ScreenGuis are `Sibling`, so this only orders them under the text and dot; there is no new constant for it.
- The light is fixed in the viewport's world. The camera orbits and the model never turns (L3-56), so the far side is lit by ambient only when the camera comes round.
- Unowned shelf icons stay on W1's dark card, not the sample's panel colour (30, 41, 70). The contrast is lower: about 1.10 against 1.29 in the approved "unowned 64" sample. If they don't read, there are two one-line Theme fixes: a lighter `ARMORY_SCREEN_CARD_DARK` (this also changes text cards) or a lighter `ARMORY_STAGE_SILHOUETTE`.
- If a template is missing, `Show` looks it up again on every paint. It is a few `FindFirstChild` calls, and it lets a late-replicated template appear.
- The warm-up runs once, on the first `SetActive(true)`, and only if the Weapons folder exists at that moment.
- The clone shows every child of the template. Per L3-55 a template has only `Stage0`; nothing filters other stages.

## Gates (my files)

| Gate | Result |
|---|---|
| `stylua --check src/client/UI` | clean |
| `selene` on my files | 0 / 0. The one warning in `src/client/UI` is pre-existing, in `LegacyPanel.luau`. |
| luau-lsp, default sourcemap (`src/client src/server src/shared`) | 0 errors |
| luau-lsp, combat sourcemap (`src/combat src/shared` plus my four files) | 0 errors |
| Typed-require probe | the shared requires resolve to `WeaponLook`, `Catalog` and `ArmoryModel` types on both sourcemaps (probe removed) |
| `py tools/check_compile.py` | PASS, 180 files; my modules are far under the cap |
| Harness | PASS, 3,920 checks |
| `rojo build`, both trees, into my scratchpad | builds |
| Line endings | LF, 0 CR bytes |

- Sourcemaps were regenerated into my scratchpad only.
- `InputController.luau`, `ArmoryModel.luau` and `tests_l3_ui.luau` are unchanged from `main`.
- `git diff src/shared/` matches L3-48 as built: `WeaponLook.Def`, `IconId`, `Catalog.GetWeaponModelsConfig` and the `AssetsConfig.icons` type.

## Required changes outside my files

None.

## What to check in Studio

1. **Before the paste** (no templates, no icons): press K in the lobby. The screen should be exactly W1's: the text stage and text cards. The same goes for the hub's Armory.
2. **After the paste:**
   - Select the Longbow. It stands tip-raised and turns slowly; a right drag turns it faster, and on release it carries on.
   - Switch to the Abilities tab: the turn stops. Close the screen: it stops too.
   - An unowned weapon (any of the 11 not yet found) is a black silhouette on the light band.
   - Text: the top line shows "RANGED" and the FIRE / ICE chip.
3. **Light** (L3-62): judge the palette read and send a screenshot if it is flat. Only Theme constants need tuning: `ARMORY_STAGE_AMBIENT`, `_LIGHT_COLOR`, `_LIGHT_DIRECTION`, `_FIT`, `_PITCH_DEGREES`, `_TILT_DEGREES`.
4. **Shelf:**
   - All 15 icons show, with the unowned ones as silhouettes.
   - Names stay on one line. "Flamethrower" and "Frost Hammer" must not truncate in portrait.
   - The tier line sits in the lower right, and the element dot on the icon's upper-left.
   - Silhouette contrast on the dark card is the point to judge (see Assumptions).
5. **Mobile emulator:**
   - 640 × 360 and 667 × 375 landscape (phones run landscape): the cards and stage fit, a touch drag turns the weapon, and the slow turn runs on a phone (it is gated on low-end only, not on touch).
   - Hub portrait, 375 × 667: the 5 × 3 grid of 68-wide cards, with "Not found" on two lines on the unowned ones.
6. **Graphics quality 1 to 3** (`lowEndDevice`): there is no slow turn and no pop, and a drag still turns the weapon.

## Addendum: lead ruling §11.6 (rest poses), applied 2026-10-21

In `src/client/UI/Theme.luau`, each constant has a one-line comment saying why. The names are exactly the ruling's:

- `COMBAT_HOLD_GRIP` is removed. In its place:
  - `COMBAT_HOLD_GRIP_MELEE = CFrame.Angles(math.rad(90), 0, 0)`
  - `COMBAT_HOLD_GRIP_RANGED = CFrame.identity`
- `COMBAT_HOLD_RANGED_RAISE_DEGREES = 80` is added.
- `COMBAT_HOLD_BACK` is now `CFrame.new(0, 0, 0.3) * CFrame.Angles(0, 0, math.rad(35)) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(90), 0, 0)`.

Gates after the change:
- `Theme.luau`: stylua, selene and LF are clean; `check_compile` passes.
- luau-lsp is clean on both sourcemaps for my four files.

**Expected until ui-engineer B lands.** luau-lsp on the combat tree reports one error, `HeldWeapons.luau:212`: `Key 'COMBAT_HOLD_GRIP' not found in table 'Theme'`. That file is B's; the error goes away when B codes against the new names. Nothing else reads the old name.
