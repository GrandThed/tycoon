# L2 W2 — ui-engineer report (2026-10-18)

Branch `l2-w2` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing committed. Only files on the contract's §8 ui-engineer list were edited.

## What changed

New files:
- `src/combat/client/UI/ArmoryPanel.luau`. W1's Abilities panel grown into the Armory sheet.
  - Header: two tabs, **Weapons** and **Abilities** (48 px tall), plus the close button. The tabs take the place of the title row, so the sheet did not get taller.
  - Opening, from K, the pad's Y or the HUD button:
    - It opens on the tab it was last left on.
    - On the first open it picks Abilities if something can be bought right now, and Weapons otherwise.
  - Gamepad: LB and RB switch tabs, and B closes. Both are bound at High+1 only while the panel is open. Y toggles the panel in the lobby (W1 behaviour).
  - Esc, the X button, a tap on the scrim and the menu opening all close it.
  - Selection stays inside the sheet. The first live button is selected, or the tab button if none is live.
- `src/combat/client/UI/ArmoryWeapons.luau`. The Weapons tab.
  - Pure `Columns(weapons, starters, families, hidden)`, using `Unlocks.OwnsFamily` and `Unlocks.ElementOf`.
  - `HiddenWhere()` scans the Config/Levels secrets for families they pay.
  - Two columns, Melee and Ranged, with one card per owned family:
    - the card shows the name and a "FIRE" chip for an element;
    - a one-variant family has an "Equip" / "Equipped" button;
    - a family with two variants has one button per variant, labelled with the variant's label;
    - the held family has a gold outline and its held button is gold.
  - An unowned family is listed only if some level's secret pays it. It appears locked, reading "Hidden on Forest Road". Today that is only the Flamethrower.
  - A tap sends `RequestSetFamily(slot, family, variant)`. Every button greys until the `setFamily` result arrives, or for 3 s at most.
  - On `ok`, the pick shows as held at once. The next TuneState loadout replaces it.
  - Refusal toasts: locked "Not yours yet", busy "Only in the lobby", invalid "Can't equip that", otherwise "Try again".
- `src/combat/client/UI/ArmoryAbilities.luau`. W1's ability rows, unchanged in behaviour, now a tab page. The Valor balance is the page's first line.
- `src/combat/client/Controllers/FlameFx.luau`. The held stream, one per shooter.
  - `IsStream(variant)` is true for a continuous variant that is not a ray, so the Beam keeps its own beam.
  - Other players' streams follow their strikes:
    - drawn from the hand to `origin + direction × size`, the server's cut at the wall;
    - as wide as the strike's `width`;
    - out 2 intervals after the last tick (0.25 s at the least).
  - The local stream starts on the frame the shot is sent, through the new `InputController.SetStreamHandler`. It follows the live camera ray, cut by a local wall ray (RespectCanCollide) up to the family's range. Server strikes only keep it alive and correct its width.
  - Look:
    - fire particles in a widening cone: speed = reach / 0.3 s, spread = atan(width/2 / reach), end size = width × 0.55;
    - over a tapered core Beam (0.6 → width);
    - a PointLight at the tip.
  - Low-end devices draw only the core, more opaque, with no particles and no light.
  - The core's flicker is off under `reducedMotion`.
- `src/combat/client/Controllers/ReactFx.luau`. Watches `Workspace.Level` for Parts carrying the `React` attribute, which LevelService sets at build.
  - On `Heat` changes it tints the Part toward charcoal and runs ember particles at a rate that follows the heat. Low-end devices get 10/s at full heat instead of 36.
  - On a `react` / `burnt` CombatFx it plays:
    - a Neon flash of the box;
    - a ghost of the box that shrinks to the floor (it only fades under reducedMotion);
    - smoke (not on low-end).
  - All of these pieces are anchored, have CanCollide/CanQuery/CanTouch off, and are gone within 1.6 s.
- `src/combat/client/Controllers/AbilityFx/DragonBreath.luau`. One gout of flame per cone at (k−1)·tickSeconds, the same rhythm as Slug Burst. Fire particles fill the cone out to its range, with a muzzle flash, smoke and a light. FeedbackController still draws each cone's exact area.

Changed:
- `UI/AbilitiesPanel.luau` **deleted**; ArmoryPanel replaces it.
- `Controllers/CombatUIController.luau`:
  - Mounts ArmoryPanel, always now, because the Weapons tab has content even without ability offers.
  - Adds the `requestSetFamily` remote.
  - Routes `setFamily` ActionResults to the panel.
  - Sets `FeedbackController.SetTuneStateHandler` to call `armoryPanel.SetLoadout`, and seeds it once at boot.
  - Feeds the Snapshot's `combat.families` to the panel.
  - `ReactFx.Mount()`, and CombatFx `react` → `ReactFx.OnFx`.
  - Passes `SecretFx.Mount(..., armoryKey)`.
  - Studio key **F**: `grantFamily` / `removeFamily` for the config's family whose element is "fire", read from the Snapshot's families. Also a strip button and `DEBUG_HINT`.
  - The air-jump hint now reads "buy it in the lobby's Armory (K)".
- `UI/CombatHud.luau`: the button reads **"Armory"** (deps renamed to `onArmory` and `armoryKey`). Same slot and same 88 px width, so W1's ActionRows packing is unchanged.
- `UI/DebugPanel.luau`: adds "Flamethrower: ON/off (F)" (`deps.fireFamily`, `SetFireFamily`).
- `Controllers/SecretFx.luau`:
  - The family note reads "Flamethrower is yours: equip it in the Armory (K)". On a gamepad it names (Y); on a phone it names no key.
  - Event `shortcut`: the finder sees the card "SHORTCUT FOUND / Raiders' Tunnel stays open on runs you lead"; everyone else gets the toast "<Name> found Raiders' Tunnel".
  - The card rows are filled by `setRow` and `revealCard`. The measured heights from W1's fix are kept.
- `Controllers/FeedbackController.luau` (routing only, +1 local, now 160):
  - In `onStrike`, a stream variant goes to `FlameFx.OnStrike` instead of `feedBeam`.
  - Start and Destroy call `FlameFx.Start` and `FlameFx.Destroy`.
- `Controllers/InputController.luau`:
  - `dragonBreath` now shares `slugBurst`'s branch in `busySecondsOf`.
  - Auto-fire for a **capsule** ranged variant uses `enemyInReach`, the server's exact capsule from the shot origin. It fires only when a body is inside the stream's reach, never at range-assist distance.
  - New `StreamHandler` type and `SetStreamHandler`, called from `rangeAttack` for continuous shots.
- `Controllers/AbilityFx/init.luau`: `dragonBreath` builder.
- `Controllers/CameraController.luau`: `openPivot` (see the camera finding below).
- `src/client/UI/Theme.luau`:
  - new `LOBBY_ARMORY_*`, `COMBAT_FLAME_*` and `REACT_*` constants;
  - the `LOBBY_` prefix is there because the hub's ArmoryPanel already owns the `ARMORY_*` names; selene caught a duplicate `ARMORY_CHIP_HEIGHT`.
- `sourcemap.json` and `sourcemap.combat.json` regenerated with rojo.

## The camera in the tunnel (L2-44)

**The roof needs no new code.** The tunnel's walls, roof and brambles are colliding, queried Parts in the Default group. CameraController's two spherecasts stop at them like any wall (radius 0.5 + pad 0.2: the camera's centre stays ≥ 0.7 under the roof).

Measured against the 12 × 14 interior:
- pivot ≈ floor + 3 (root) + 1.5 = floor + 4.5, so 9.5 studs of headroom;
- the default 11-stud boom reaches the roof only when pitched more than about 60° down, and then it is shortened, never pushed through;
- the head bump caps the root at about floor + 11.5, and the pivot never rises above the highest root it has seen + 1.5 (≈ floor + 13 < 14), so the spherecasts never start inside the roof;
- at a bend, or looking across the 12-wide tunnel, the boom shortens to about 5.3 studs (as against any wall outdoors); the existing shoulder pull-in still keeps it out of the side wall.

**Found and fixed: the pivot itself could start inside rock.**
- The pivot's height lags the root by up to `movement.cameraMaxLag` (3), and during a Leap Smash or Impale Dash its flat position trails by up to 3 as well.
- Dashing or leaping off the +8 step toward the low side can leave the pivot over the high floor but below its top (8). Cutting a bend's inner corner can do the same with a wall.
- A spherecast that starts inside a Part does not see that Part. The camera would then be placed behind the rock (a see-through view out of the ridge).
- Fix: `openPivot` raycasts from the head point (root + pivot height, always open because the body stands there) to the lagged pivot, and pulls the pivot back to 0.7 short of any hit.
- With no lag the two points coincide and nothing is cast, so ordinary play costs nothing. The case is rare: about the 0.3 s after a motion ability at the step or a bend.
- The fix also covers the same case outdoors (cover blocks, fences).

Not checked here, Studio only: how dark the tunnel reads under default Lighting.

## Remotes and state consumed

- Sent:
  - `RequestSetFamily(slot, family, variant)`;
  - `RequestBuyAbility(id)` (W1);
  - `RequestDebug("grantFamily" | "removeFamily", familyId)`.
- Read:
  - `ActionResult` with `setFamily` (slotId = family) and `buyAbility`;
  - `TuneState` loadout, through `FeedbackController.GetLoadout`;
  - Snapshot `combat.families`, `combat.abilities`, `combat.valor`;
  - CombatFx `react` (event `burnt`, box);
  - CombatFx `secret` with event `shortcut` (`name`, `userId`);
  - strike fx for stream variants (`origin`, `direction`, `size`, `width`, `tick`);
  - the Part attributes `React` and `Heat` under `Workspace.Level`.
- Config: `ProvingGrounds.json` `weapons` (`name`, `slot`, `era`, `element`, `variants[*].label`, `default`, `continuous`, `shape`, `range`, `width`, `rate`) and `loadout`; `Config/Levels/*` `secrets[*].family` and the level `name`.

## Gates (my files)

- `stylua --check` on `src/combat/client` and Theme: clean. selene: 0 errors, 0 warnings.
- luau-lsp (`tools/types/globalTypes.d.luau`):
  - combat sourcemap over `src/combat/client` + Theme + MapScreen: exit 0;
  - default sourcemap over `src/client`: exit 0.
  - The whole of `src` under the combat sourcemap shows only the hub's `PlotService` Landscape require, which is expected because that file is not in the combat place.
- `py tools/check_compile.py`: PASS (172 files). FeedbackController 160, InputController 151, CombatUIController 107 top-level locals.
- `rojo build combat.project.json` to a scratch file: builds. No CRLF in my files.

## Layouts checked mentally (MIN_SCALE 0.917 on phones)

- **667 × 375** (58 px top bar):
  - the sheet is 312 px wide;
  - on the Weapons tab: 284 design px = 260 px tall, against 235 design px of page room for a 190 px page, so no scroll;
  - on the Abilities tab: 188 design px;
  - tabs 99 × 44 px, close 44, Equip 135 × 44, variant buttons 66 × 44.
- **640 × 360**: page room is 219 design px for 190, so it fits. Below that height the page scrolls; its minimum is one 48 px row.
- **375 × 667 portrait**: the sheet is 312 of 375 px wide, and the height fits easily.
- **1920 × 1080**: the sheet is about 527 × 440 px.
- **HUD**: "Armory" takes "Abilities"' slot at the same 88 px width, so W1's packing (two rows on landscape phones, three in portrait) is unchanged.
- **Cards**: the 155 px columns fit "Flamethrower" + the FIRE chip (about 95 + 4 + 38 of 147).

## For other owners

1. **luau-engineer:** nothing required.
   - I depend on LevelService setting `React` at build, before the Part is parented, which your diff does. ReactFx adopts only Parts that carry it.
   - The shortcut and react CombatFx shapes match `Types.CombatFxSecret` / `CombatFxReact` as landed.
2. **Lead:** no `Main.client.luau` change is needed. FlameFx is started by FeedbackController, and ReactFx and ArmoryPanel by CombatUIController.
3. **docs-keeper:** W1's PLAYTEST and MANUAL_STEPS steps say "Abilities button" and "Abilities panel". They now read "Armory" with Weapons and Abilities tabs. The air-jump hint text changed too.
4. **economy-designer (FYI):** the contract's 16-stud / 5-wide stream is 20 / 7 in your config. Auto-fire and FlameFx read the config, so nothing on my side changes.

## Assumptions

- Unowned families are shown locked only when a level's secret pays them. This generalises the contract's "only the Flamethrower" and gives the same result today; a W3 frost hammer with no secret would stay hidden.
- `F` flips the first family by id whose element is "fire", so the client holds no family id constant.
- A stream is a continuous variant that is not a ray (the Flamethrower's capsule). The Beam's held ray keeps FeedbackController's beam.
- The Armory panel exists only in the lobby phase, as W1's did.

## What Ben must check in Studio (`build/proving.rbxl`, Play)

1. **Lobby, K:**
   - The **Armory** opens. With Valor to spend it opens on Abilities, otherwise on Weapons.
   - The Weapons tab shows Broadsword under Melee, and under Ranged Longbow (two variant buttons) and **Flamethrower, locked, "Hidden on Forest Road"**, with a FIRE chip.
   - Clicking the tabs switches; K or Esc closes.
2. **Press F** (Studio): the Flamethrower card becomes "Equip". Click it: the toast reads "Flamethrower equipped" and the card turns gold. Fire in a level and see the flame stream from the hand. Press F again: the card goes back to locked and the ranged slot is the Longbow again.
3. **Flame feel:** the stream reaches about 20 studs, stops at walls, and shows from the first frame you fire. Dragon's Breath (the ranged ability) throws four gouts of fire.
4. **The bramble:** burn it at the tunnel mouth. It darkens and throws embers, then flashes and collapses, with smoke. The tunnel is then open.
5. **The tunnel:**
   - Walk through and look up and around at the step and both bends. The camera must never show the outside of the ridge or the sky through the roof.
   - Try a Leap Smash or an Impale Dash off the step and round the exit bend.
   - The exit card reads "SHORTCUT FOUND / Raiders' Tunnel stays open on runs you lead".
6. **Phone emulator** (667 × 375, 640 × 360, portrait 375 × 667):
   - the "Armory" button is where "Abilities" was;
   - the sheet fits with tabs and 44 px buttons and no scrolling on the Weapons tab;
   - with the Flamethrower equipped, auto-fire fires only when a raider is inside the flame's reach.
7. **Gamepad:** Y opens, LB/RB switch tabs, A equips, B closes and does not dash.
