# L2 W2 luau-engineer report (2026-10-18)

Branch `l2-w2` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing is committed. Contract:
`docs/prompts/l2-w2-contract.md` (§10 applied: Option 1, session-only loadout).

## Files

New:
- `src/shared/WorldReact.luau`: pure rules for reactive blocks (L2-34, L2-35).
- `tools/crowd_harness/tests_l2w2.luau`: the W2 cases.

Changed:
- `src/shared/Types.luau`
- `src/shared/Unlocks.luau`
- `src/shared/Tuning.luau`
- `src/combat/server/Services/CombatRemotes.luau`
- `src/combat/server/Services/UnlockService.luau`
- `src/combat/server/Services/SecretFlow.luau`
- `src/combat/server/Services/WeaponService.luau`
- `src/combat/server/Services/AbilityService.luau`
- `src/combat/server/Services/LevelService.luau`
- `src/combat/server/Services/LevelGeometry.luau`
- `src/combat/server/Services/StageFlow.luau`
- `src/combat/server/Services/WaveService.luau`
- `src/combat/server/Services/DebugService.luau`
- `tools/crowd_harness/run_harness.py`: adds `WorldReact` to SOURCES and `tests_l2w2.luau` to TESTS.
- `tools/crowd_harness/mutate.py`: adds 57 `l2w2:` entries and `WorldReact` to FILES. It also re-aims
  one older entry, "world: Pieces builds the ground as the layout writes it", because Pieces now
  measures a variable named `measured`.
- `tools/check_stage_mirror.py`: adds the L2 W2 Validate cases (4 must be accepted, 13 must be
  refused). A new `must_accept` set flags a sound tunnel that both sides refuse.
- `tools/crowd_harness/tests_l2.luau`: one W1 real-file case updated for the cache's W2 reward.
- `sourcemap.combat.json`: regenerated with rojo. `sourcemap.json` was changed by another agent.

## What changed, by ruling

- **L2-29.**
  - `Types.RangeWeaponDef.element: Element?`, where `Types.Element = "fire" | "ice"`.
  - `Tuning`: `weapons.*.element` is in STRUCTURAL_PATHS. It also has an enum entry (fire/ice) so a
    later change to the structural list cannot let any other word through.
  - `WeaponService`: the arc/capsule branch sets `tick = true` for a `continuous` variant, the same
    way the ray branch does.
  - `AbilityService`: `MECHANICS.dragonBreath = MECHANICS.slugBurst`. Both names point at the same
    entry.
- **L2-30, L2-31.** New in `Unlocks`:
  - `Starters(loadout)`: the set of starter families.
  - `OwnsFamily(families, id, starters)`.
  - `ElementOf(weapons, family)`: fails closed on any word other than fire/ice.
  - `HasElement(families, weapons, starters, element)`.
  - `HoldsKey(combat, expeditions, weapons, starters, needs)`: abilities first, then elements.

  `HasKey` is unchanged (abilities only), so W1's cases still hold. `UnlockService.HoldsKey` and
  `OpenSecret` both go through `Unlocks.HoldsKey`. The result: `fire` counts as held once the profile
  owns the Flamethrower, whichever weapon the player carries.
- **L2-32.**
  - New remote `RequestSetFamily(slot, family, variant)`, bucket `calls`, with `args.n == 3`. The
    variant may be at most `Unlocks.MAX_VARIANT_LENGTH` (8) bytes.
  - `Unlocks.FamilyVerdict` returns, in this order: unavailable, invalid, locked, busy, then nil.
  - `UnlockService.OnSetFamily` does nothing in the range. Otherwise it gets the verdict, then calls
    `WeaponService.SetVariant` followed by `SetFamily`. It answers with
    `ActionResult { action = "setFamily", slotId = family }`. If a set fails after the verdict (no
    shooter), the answer is `unavailable`.
  - `Types.ActionResult.action` now includes `"setFamily"`.
- **L2-33.** The loadout is kept in session memory only (WeaponService). There is no profile write.
- **L2-34.** Layout and validation:
  - `Types.LevelBlock` gains `react` and `opens`. `Types.LevelShortcut` is new.
  - `LevelLayout` gains `shortcuts` and `shortcutRoute`. `shortcutRoute` is for tools only.
  - `Types.CombatLevelsConfig.react: CombatReactConfig?` (`fireHits`, `iceHits`, `pad`).
  - `StageFlow.Validate` adds a `reactProblems` step. It checks:
    - `react` is "fire" or "ice", and the block collides;
    - `opens` names a `layout.shortcuts` id;
    - `shortcuts` is a list;
    - each shortcut id is a non-empty string of at most `Unlocks.MAX_ID_LENGTH` (32) bytes, and unique;
    - `x, y, z, sx, sy, sz` are finite numbers.
- **WorldReact.**
  - `Segment(fx)`: works only for `capsule` and `ray`. A ray uses its endPoint; otherwise the segment
    runs `size` studs along the unit direction.
  - `Touches(fx, box, pad)`: a closed slab test against the box grown by `width / 2 + pad`. Every
    other shape returns false, so Dragon's Breath cones never burn.
  - `Need(rules, element)`: `fireHits` or `iceHits`, accepted only as a whole number ≥ 1.
  - `Pad(rules)`, `Heat(heat, need)` and `Share(heat, need)`.
- **L2-35.**
  - `WeaponService.OnStrikeResolved(listener)`: called at the end of `finish()`, after the strike's fx
    is queued, as `(player, weapon, fx, abilityId?)`. Abandoned-projectile end strikes are skipped
    (`StrikeFx.abandoned`, which is never sent to clients). Each listener runs under `pcall`, and a
    failure is warned once.
  - `LevelService`:
    - `Build(layout, map, rules, open?)` records each reactive block it builds and sets attributes
      on its Part: `React` (the element) and `Heat` (0).
    - `React(player, weapon, fx, abilityId?)`: when the weapon's element matches the block and the
      strike touches it, the block gains heat. `Heat` is updated as `Share`, and at `Need` the Part
      is destroyed and `OnReacted({ name, react, box })` fires.
    - `Clear` empties the list.
  - `WaveService` registers `OnReacted` in Init. It broadcasts
    `CombatFx { kind = "react", event = "burnt" ("frozen" for ice), name, react, x, y, z, sx, sy, sz }`.
  - `Types.CombatFxReact` is added to the union.
- **L2-36.**
  - New in `SecretFlow`: `Shortcuts(layout)`, `InShortcut(box, root)` (closed),
    `RecordShortcut(combat, levelId, id)` (true when the find is new), `FoundShortcuts(combat, levelId)`
    (returns a copy) and `FamiliesOf`.
  - `LevelGeometry.Pieces(layout, sizes, maxParts, open?)` drops blocks whose `opens` is in `open`.
    It does this on a cloned layout before any block is measured. Other pieces carry `react` and
    `opens`.
  - `WaveService.startLevel` builds the level with `UnlockService.FoundShortcuts(leader, levelId)`.
  - `tickSecrets` tests each standing fighter against each shortcut box, once per run per player
    (`run.shortcutSeen`). For a new find, `UnlockService.FindShortcut` records it and RunFx pushes
    `CombatFxSecret { event = "shortcut", userId = finder, secretId = id, name, needs = "", valor = 0,
    materials = 0 }` to every member.
- **L2-38.**
  - Levers `grantFamily` and `removeFamily` (value: a family id) work both through RequestDebug and
    through the `grantFamilyAttribute` / `removeFamilyAttribute` attributes. Both are off outside
    Studio and in the range.
  - `UnlockService.GrantFamily` / `RemoveFamily` refuse starters and unknown ids. Removing a family
    that is currently held puts that slot back on the config loadout's starter.
  - Notices read "Flamethrower is yours" and "Flamethrower removed".
  - `resetSecrets` also clears `run.shortcutSeen`. Its notice now reads "Secrets and shortcuts reset
    (from the next run)".

## Public API the lead wires (Main.server.luau)

```lua
-- 1. RequestSetFamily handler
if RangeService.IsActive() then return end
UnlockService.OnSetFamily(player, slot, family, variant)
-- signature: UnlockService.OnSetFamily(player: Player, slot: string, family: string, variant: string): ()

-- 2. after both are required, before the Init loop
WeaponService.OnStrikeResolved(LevelService.React)
-- WeaponService.OnStrikeResolved(callback: (Player, string, WorldReact.Strike, string?) -> ())
-- LevelService.React(_player: Player, weapon: string, fx: WorldReact.Strike, _ability: string?): ()
```

These typecheck together. The listener type is written in terms of `WorldReact.Strike`, and
WeaponService passes its own `StrikeFx`. `WorldReact.Strike.shape` is `Types.HitShape`, which keeps
the old solver happy.

## Confirmations

- **TuneState reaches the client after OnSetFamily in a mission.** I checked this by reading the code:
  - `WeaponService.SetVariant` and `SetFamily` each call `tuneStateFor(shooter)`. In a mission that
    function sends `TuneState({}, loadoutPayload)`, and the family's TuneState goes out last.
  - On the client, FeedbackController is the only TuneState listener. It connects whenever
    `CameraController.IsCrowdCombat()` is true, which covers missions, and `onTuneStateEvent` passes
    the loadout to `InputController.SetLoadout`.
  - Not tested in Studio.
- **No require cycle.**
  - New requires:
    - UnlockService requires WeaponService and Tuning.
    - LevelService requires Tuning, Unlocks and WorldReact.
    - WeaponService requires WorldReact.
    - WorldReact requires only Types.
  - WeaponService requires nothing that requires UnlockService, LevelService or WaveService. Its
    requires are Armory, Catalog, CombatMode, GroundRule, HitShapes, SwingGate, Tuning, WorldReact,
    DataService, RemoteService, CrowdService, PositionRing, StrikePick, StrikeTally and VitalsService.
  - LevelService requires no service.
- **check_compile.** WeaponService and WaveService only gained calls. WeaponService now has one more
  top-level local (WorldReact).

## Gates (run against the designer's landed data: ForestRoad.json tunnel, Combat.json `react`, the Flamethrower)

- **Harness.** `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`
  → `HARNESS: PASS (2,758 checks)`.
  - `tests_l2w2.luau` covers:
    - every FamilyVerdict reason, in order;
    - OwnsFamily, Starters, ElementOf, HasElement and HoldsKey;
    - Segment and Touches at each face, side, top, bottom and the far face, with pad, width and slant;
    - Need, Pad, Heat and Share;
    - Shortcuts, InShortcut on each face, RecordShortcut twice, FoundShortcuts and FamiliesOf;
    - Pieces with and without `open`;
    - Validate's 14 refusals and 4 acceptances;
    - the element as a structural path;
    - the shipped files: cache behind fire, the brambles, the cave, Pieces closed and open.
  - One W1 case in `tests_l2.luau` changed: "the cache and the shrine have no reward entry in W1" no
    longer holds now that W2 gives the cache its reward. That case now checks the shrine only, and
    `tests_l2w2.luau` checks the cache.
- **mutate.py.**
  - Filter `l2`: 149 run, 0 not caught. That covers W1's `l2:`, `l2 fix`, `l2 fix2` and the 57 new
    `l2w2:` entries.
  - Filter `world: Pieces builds the ground as the layout writes it` (the re-aimed entry): 1 run, 0
    not caught.
  - Stale text over every entry: 936 entries, 0 stale.
  - The first run found two `l2w2` mutants nothing caught. Both were redundant guards in
    `WorldReact.Segment`, because a zero direction or a NaN size already gives an end point that is
    not finite. I removed the guards, and the entries became "the direction is not made a unit" and
    "a negative size sweeps".
- **check_stage_mirror.** `CHECK: PASS`, including
  `L2 W2: Validate's react, opens and shortcuts lines refuse alike: 17 compared`. The designer has
  mirrored the lines in sim_range.
- **`py tools/check_compile.py`.** `CHECK: PASS -- 172 files compile with Studio settings (-O1 -g2)`.
- **stylua --check and selene on my 14 Luau files.** Clean: 0 errors, 0 warnings.
- **luau-lsp analyze** (`--definitions tools/types/globalTypes.d.luau`, `sourcemap.combat.json`
  regenerated with rojo after the ui files landed). 0 diagnostics in `src/combat` and `src/shared`.
- **Line endings.** Every file I touched is LF.

## For other owners / for the lead

- **economy-designer (sim_range.level_problems, the Validate mirror).** This is done:
  check_stage_mirror passes. For the record, the Python side must refuse when any of these holds:
  - `layout["shortcuts"]` is present and is not a list. In Luau, "not a table" means a non-list here.
  - A shortcut entry that is not a dict, or whose `id` is not a non-empty string of at most 32 UTF-8
    bytes. Count bytes, as the secrets lines do.
  - A repeated shortcut id.
  - Any of `x, y, z, sx, sy, sz` missing or not a finite number.
  - A block whose `react` is present and is neither "fire" nor "ice".
  - A block with `react` and `collide` false.
  - A block whose `opens` is present and is not a string naming a shortcut id.

  These are not refused: `opens` without `react`, and `react` without `opens`. A shortcut size of 0 is
  not refused either; it is only never found.
- **ui-engineer.**
  - A reactive block's Part carries the attributes `React` ("fire" / "ice") and `Heat` (0 to 1,
    updated each strike). It is a direct child of `Workspace.Level`.
  - A burn arrives as `CombatFx { kind = "react", event = "burnt", name, react, x, y, z, sx, sy, sz }`.
  - A shortcut find is `CombatFxSecret { event = "shortcut", userId = finder, secretId, name }`, sent to
    every member. Show the card when `userId` is the local player's id, and a toast otherwise.
  - `setFamily` results carry `slotId = family`. Possible reasons: unavailable, invalid, locked, busy.
  - Owned families come from the snapshot's `state.combat.families`, plus the starters. The levers
    resend the snapshot.
  - The family levers are `RequestDebug("grantFamily", id)` and `RequestDebug("removeFamily", id)`.
- **Lead.**
  - The two wiring steps above.
  - Regenerate `sourcemap*.json` at the merge. The combat sourcemap is current as of my last
    typecheck.

## What to check in Studio

- Forest Road, Normal, with the Flamethrower granted (F, or the `DebugGrantFamily` attribute):
  - Hold fire on `CaveBrambleW`. It should go after about 0.6 s (six ticks). Its `Heat` attribute
    should rise 0 → 1 in Properties before it disappears, and every client should see the burn.
  - Dragon's Breath on a bramble does nothing.
  - A Longbow shot on a bramble does nothing.
- Walk the tunnel. Entering the shortcut box at the exit should show the card once, and no card on a
  second visit in the same run.
- Start the next run as the same leader. Both bramble mouths should be gone. As a guest leader, they
  should still stand.
- Press H (reset). The next run builds the brambles again.
- Lobby Armory: picking the Flamethrower while locked answers `locked`. After the grant it equips, and
  the HUD and input follow (TuneState).
- Remove the Flamethrower (F again) while it is held. The ranged slot goes back to the Longbow.

