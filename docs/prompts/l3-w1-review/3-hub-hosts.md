# L3 W1 review, slice 3: the hub and the client hosts

Reviewer: roblox-reviewer (Opus), 2026-10-20. Branch `l3-armory` at a2628da in `tycoon-p5` (W1 build ff7a910 and
64a6b12). The diff is `git diff main...l3-armory`, limited to this slice's files:
- `src/server/Services/ArmoryService.luau`, `EconomyService.luau`, `HubRemotes.luau`;
- `src/client/Controllers/UIController.luau`, `src/client/UI/DebugPanel.luau`, `MapScreen.luau`;
- `src/combat/client/Controllers/CombatUIController.luau`, `src/combat/client/UI/DebugPanel.luau`, `SummaryCard.luau`;
- `combat.project.json`.

To compare against, I read:
- the combat place's handlers (`UnlockService.OnUpgradeWeapon` and `OnSetFamily`);
- the shared rules the hub calls (`Unlocks.LoadoutOf`, `SaveLoadout`, `FamilyVerdict`, `StarsOf`, `ResetArmory`,
  `TierLever`);
- the parts of `ArmoryScreen` the hosts drive (`setOpen`, `bindPadToggle`, `settleUpgrade`, `onWeaponResult`, the
  scrim).

Read only. No file was changed except this one.

**Count: 0 Critical, 0 Major, 2 Minor, 5 Suggestions.**

## Minor

### m1. The hub's service lines are under no gate, so the C0 copy bug that L3-14 fixed can come back silently

**Where:**
- `src/server/Services/EconomyService.luau:127-165` (`copyCombatProfile`);
- `EconomyService.luau:95-108` (`computeGearPower`);
- `src/server/Services/ArmoryService.luau:87-116` (`tryUpgradeWeapon`, `trySetFamily`).

**What is wrong:** No tool reads these lines.
- `grep -rln "copyCombatProfile\|computeGearPower\|ArmoryService\|EconomyService" tools` finds nothing but a marketing
  shot list.
- `run_harness.py` SOURCES holds no `src/server/Services` module.

The copy is correct today. All 16 keys of `ProfileSchema`'s template `combat` are written: the C0 nine, the four v7
maps and the three v8 fields, each nil-safe and unaliased. Power reads the held tiers. But the rule "every profile
field rides the Delta" lives only in the copy's own text. Its first version broke that rule: C0 dropped the v7 maps,
which the contract calls out (`EconomyService.luau:102-127` at 773f37d).

**Failure scenario:** the Castle wave adds a v9 field to `combat`, for example a relic map. The copy is not edited.
- Every hub Delta then replaces `current.state.combat` with a copy that lacks the field (UIController:1071-1073).
- On the first combat-dirty flush after the Snapshot, the hub's Armory screen loses it. Every gate stays green.

The same holds if `computeGearPower` reverts to `state.combat.gear`. The hub Power would freeze at the frozen slot
value whatever the player upgrades, and nothing would fail.

**Fix:**
- Move the copy into a pure shared function, for example `Combat.CopyProfile` (Combat.luau is already in the
  harness's world).
- Add a harness check that walks `ProfileSchema`'s template `combat` keys recursively. It asserts that each key
  survives the copy and that no copied table is the source's. The check then fails on the first unrouted field.
- Fold Power's two lines (`LoadoutOf`, then `HeldTiers`) into one pure `Armory.SavedPower(cfg, combat, weapons,
  loadout)`, pinned at 64 for a fresh profile.

### m2. A party invite that arrives while the hub's Armory is open is hidden under it

**Where:** `src/client/Controllers/UIController.luau:530` (the `PartyInviteToast` is built) and `:720` (the
`ArmoryScreen`, built later). Both roots sit at `Theme.ZINDEX_CARD`:
- `PartyInviteToast.luau:68`;
- `ArmoryScreen.luau:237`.

**What is wrong:** under `ZIndexBehavior.Sibling`, equal-ZIndex siblings draw in child order, so the later Armory
scrim and frame cover the invite card. The scrim is a full-screen `TextButton` that closes the screen on any tap. The
frame is opaque and centred: 682 × 313 design px fills a landscape phone, and 880 × 420 at about 1.6 on a 1080p monitor
reaches above the invite card's top position (margin + 56 + gap).

**Failure scenario:**
1. In the hub, a player browses the Armory (K or the bar key).
2. A friend sends a party invite (`coop.inviteSeconds` 30).
3. On a phone the card is wholly behind the frame. On a monitor it is dimmed under the 0.35 scrim, and a tap on Accept
   hits the scrim and closes the Armory instead. A gamepad cannot select it, because the selection is confined to the
   frame.
4. Anyone who stays in the Armory for 30 s loses the invite without ever seeing it.

The C0 Armory was a dock panel at the side, so the invite stayed on top. This is a regression of the hub's
non-blocking invite.

**Fix:** draw the invite card above the Armory. A Theme z between `ZINDEX_CARD` and `ZINDEX_DIALOG` works, because the
card is small and `Active`, so it takes its own taps. The other option is to close the Armory in `onPartyInvite`, but
that would yank the screen mid-browse.

## Suggestions

### s1. The hub's Armory key is decided once at boot from three things that may still be replicating

**Where:** `UIController.luau:439-459` and `:1572-1592`.
- `hasArmoryScreen` reads `Catalog.GetProvingGroundsConfig()` once at boot.
- `combatRemotesReady` keys on `RequestUpgradeWeapon` alone, and the ChildAdded listener disconnects once
  `combatWiringComplete()` holds. That predicate does not include `RequestSetFamily`.

**The race:**
- If ProvingGrounds had not arrived at boot, the Armory key hides for the session.
- If `RequestSetFamily` replicated after the last remote the predicate waits on, every hub Equip toasts "Try again".
  The intents are created in `pairs` order after the events (`RemoteService.luau:189-191`).

The screen itself re-reads its configs at every open for exactly this reason (`ArmoryScreen.luau:124-126`). The window
is near zero in practice, because RemoteService creates the whole set in one frame. The shape is the same as C0's
(RequestBuyGear / RequestAscend). It is one config file and one intent wider now.

**Cheap fix:**
- Resolve `requestSetFamily` / `requestUpgradeWeapon` with `FindFirstChild` at send time when they are nil.
- Re-check `provingConfig` in `refreshCombatKeys`.

### s2. The grant-star wildcard `"*"` is a protocol literal with four homes

**Where:**
- `src/client/UI/DebugPanel.luau:69`;
- `src/combat/client/UI/DebugPanel.luau:109`;
- `CombatUIController.luau:214`;
- `ArmoryService.luau:218`, plus the DebugService equivalent (slice 2).

**Also:** the caption "★ Forest Hard" is hard-coded in both strips, and both strips say it must change with the
Castle.

**Fix:**
- Give the wildcard one home beside `Unlocks.TierLever`, for example `Unlocks.ALL_STARS`.
- Build the caption from `Armory.BuiltBands` and the level names, so the Castle wave cannot leave a lever that does
  something other than its label.

### s3. `ARMORY_KEY` and `ARMORY_KEY_HINT` are duplicated in both hosts

**Where:** `UIController.luau:102-103` and `CombatUIController.luau:232-233`.

`ArmoryScreen` already exports `PAD_TOGGLE_NAME` and `PAD_TAB_NAMES` for the hosts. Exporting `KEY` and `KEY_HINT`
from it too keeps "the Armory is K in both places" (L3-22) in one file.

### s4. A comment in `Types.luau` is stale

**Where:** `src/shared/Types.luau:999-1001` (luau A's file). It still says the v7 maps are optional "because the hub
copies the profile it shows (EconomyService) without them". Since L3-14 the hub copies them.

### s5. Two leftovers worth one line to Ben or the lead

**The total Max HP readout is gone from the hub.**
- The C0 panel showed a Max HP row (`ARMORY_MAX_HP_HEIGHT`, deleted).
- Layout A shows only each slot's `ladder.hp` step ("HP +120 → +170").
- So the hub no longer says what a player's health will be in the dungeon.
- This is consistent with L3-19, but it is information the hub used to show.

**`m11-unlocks` (unmerged) still builds the C0 path.**
- It still builds `ArmoryPanel`, `RequestBuyGear` and its own schema migration (`git grep RequestBuyGear m11-unlocks
  -- src`).
- Its merge must re-key its Armory unlock gate onto `RequestUpgradeWeapon` and `ArmoryScreen`, and renumber past v8.

## Checked and clean

**Hub server**
- **Hub and combat handlers follow one rule.** Both call `Armory.Upgrade(cfg, combat, family, OwnsFamily(families,
  family, starters), gate, built)` and `Unlocks.FamilyVerdict` → `SaveLoadout`.
  - `built` comes from `Catalog.GetLevelIds()` in both places, read at Init. The hub build has `Config/Levels` (the
    sourcemap shows `0_RaiderArena` and `1_ForestRoad`).
  - The starters come from the same `loadout` (Tuning.Get returns the ProvingGrounds config, and
    `WeaponService.startingFamily` equals `loadout` on valid data).
  - The hub gate is `true`, as L3-14 rules.
- **Server authority in the hub.**
  - The validators are `n == 1`, a 1–24 byte family; and `n == 3`, a slot of melee/ranged, a family of 1–24 bytes and a
    style of 1–8 bytes, identical to the combat validator.
  - Both use the `calls` bucket.
  - No amount, tier or cost is sent.
  - Nothing yields between the verdict and the write, so there is no double spend.
  - A released profile (Depart) answers `unavailable`, because `Release` nils `profiles[player]` first
    (`DataService.luau:504`).
  - `RequestBuyGear` has no definition, handler or sender left.
- **Studio levers in the hub.**
  - `HandleDebug` returns outside Studio. `Start` polls only in Studio.
  - setTier, grantStar and resetArmory run before the amount check. The string and reset consumers reset their
    attributes.
  - `grantMaterials` pays `BuiltBands` materials (Timber).
  - The client strip is built only `if RunService:IsStudio()`.
- **Power.** It reads the held tiers of the saved loadout, and reads 64 at T1/T1 without ProvingGrounds. It is
  recomputed with every combat-dirty Delta and every Snapshot, and no hub path writes `combat.gear`.

**Hub client**
- **Readiness.** Before the change, the Armory key showed on `hasArmory and combatRemotesReady`. Now it shows on
  `hasArmoryScreen and combatRemotesReady`, which differs only by ProvingGrounds.json, which ships. The Expedition key
  and the Power readout keep their rules, and `RequestUpgradeWeapon` is created unconditionally, as `RequestBuyGear`
  was.
- **K and the bar key.**
  - Both go through `togglePanel("armory")`, gated on the screen existing, `model ~= nil` and the remotes. That is the
    same rule as the key's visibility.
  - `processed` and a focused TextBox are ignored.
  - Opening the screen closes the dock panel. Opening a dock panel closes the screen. The bar's active key follows.
  - The strip hides while the screen is open (it is a later ZINDEX_CARD sibling).
- **The Delta path.**
  - `pushArmory` runs on the Snapshot and on each Delta whose `combat` passes `isCombatProfile`, not on the cash tick.
  - An upgrade stays pending until a Delta shows the tier (`settleUpgrade`), and the copy now carries `tiers`, so the
    4 Hz flush cannot let a stale button double-buy.
  - An equip's `picked` hands over to the Delta's saved loadout.
- **Results.** `upgradeWeapon` and `setFamily` results go to `OnResult`, plus the hub's `insufficientFunds` sound.
  `buyGear` and `ascend` have no sender. A forged `ascend` falls through harmlessly.

**Combat client**
- **Lobby gate.**
  - `SetAvailable(phase == "lobby")`.
  - `SetGate(not live or waiting)` matches `WaveService.MayLeave` (`LIVE_PHASES` equals `isLive`, and `waiting` is
    read the same way).
  - K, the HUD button and M interplay as before. `HOLD_ARMORY` and the strip are handled in `onOpenChanged`.
- **Results.** `ARMORY_ACTIONS` routes all three to `OnResult` before `actionResultText`.
- **Studio keys.** T, U and L are behind `studio`, a missing remote, `processed`, the TextBox focus and `debounced()`.
  No other `Enum.KeyCode.T/U/L/K` binding and no config-driven key exists in `src`.
- **Summary card.** Every network field is type-checked, and the line is hidden unless the run gave a family or
  Valor > 0. The key is K, Y, or none on touch. MapScreen reads "T" .. `Format.Cash(tier)`.
- **Strips.**
  - Both strips' `setTier` buttons send `"<held family>=<tier+1>"`, which the server clamps.
  - The hub strip is 3 × 103 + 2 × 6 + 12 = 333, and its 11 buttons make 4 rows of 48 (44 physical px at
    MIN_SCALE).
  - Expanded on 667 × 375 under a 58 px inset, it takes 253 + 64 = 317 of 317 px. That is Studio only.

**Deleted panels and the project file**
- **No reader is left.** `ArmoryPanel`, `ArmoryWeapons` and `ArmoryAbilities` appear only in two history comments.
  None of the 32 Theme constants on ui B's dead list is defined or read in `src` or `tools`.
  `debugPanel.SetGear` has no caller.
- **`combat.project.json`.** It maps the seven `Armory*` files as explicit children of `Client.UI`. A rojo sourcemap
  shows 22 children with no duplicate name.
  - Every module the Armory files require is mapped (Create, Motion, Theme, the siblings, Shared).
  - `.proving.project.json` is gitignored and regenerated by the "Build proving" task, so its stale copy in the
    worktree (2026-10-16, no Armory files) is not shipped.

**Gates I ran**
- Both `rojo build`s.
- `luau-lsp analyze` on the hub tree (`src/server src/client src/shared`) and the combat tree (`src/combat src/shared`
  plus the mapped hub UI files), with fresh sourcemaps: no output, exit 0.
- `stylua --check` and `selene` on the nine Luau files: 0/0/0.
- 0 CR bytes.
- `py tools/check_compile.py`: PASS, 177 files, CombatUIController at 106.
- No `wait(`, `spawn(`, `delay(`, `_G` or parent argument; `--!strict` in all nine.
