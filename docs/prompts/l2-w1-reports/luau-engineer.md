# L2 W1: luau-engineer report (2026-10-17)

Branch `l2-secrets` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing is committed.

## v7 forward compatibility (lead ruling §10): checked before the migration was written. Safe.

I checked what v6 code does when it loads a v7 profile.

- **Reconcile only adds keys.** `ServerPackages/_Index/lm-loleris_profilestore@1.0.3/profilestore/ProfileStore.luau:408-422`
  (`ReconcileTable`) copies a template key only when the profile's value is nil, and recurses into
  tables both sides have. It never deletes anything. A v6 template therefore keeps
  `combat.abilities`, `secrets`, `families` and `shortcuts`.
- **runMigrations keeps a newer profile as it is.** `src/server/Services/DataService.luau:103-108`:
  when `state.version > SCHEMA_VERSION`, it warns "profile v7 ... is ahead of v6" and returns. It
  does not reset the profile, lower the version or refuse to play. The guard has been there since
  the init commit (`d166a9a`), so every published build has it.
- **No v6 code replaces the combat table or the profile.**
  - Nothing assigns `profile.Data`.
  - `state.combat` is assigned only in `Migrations[4]`, and only when it is nil.
  - The writes to `combat.*` are single fields (ArmoryService:152, EconomyService:442-443,
    ExpeditionService:407-420, Combat.TouchHighestEra).
  - `EconomyService.copyCombatProfile` (102-127) builds the hub client's copy and drops the new
    fields there. It never writes the saved profile.
- **Publishing the hub from `main` after this merge:**
  - The hub becomes v7 (it shares ProfileSchema).
  - Each live player's v6 profile gains four empty maps on first load. Nothing else changes.
  - The live Expeditions place still runs old v6 code (frozen until L4). It loads those v7
    profiles, warns, plays and saves the four maps back unchanged.
  - Nobody loses or resets any data in either direction. `tests_l2` simulates "v6 Reconcile on a
    v7 profile" and checks this.

## Files created or changed

- **Created**
  - `src/shared/Unlocks.luau`
  - `src/combat/server/Services/SecretFlow.luau`
  - `src/combat/server/Services/UnlockService.luau`
  - `tools/crowd_harness/tests_l2.luau`
- **Changed**
  - `src/server/Services/ProfileSchema.luau`: v7, template, `Migrations[6]`.
  - `src/shared/Types.luau`
  - `src/shared/WallClip.luau`: `Rise` takes two arguments.
  - `CombatRemotes.luau`: `RequestBuyAbility`.
  - `WaveService.luau`: the chest tick, the map rows, the summary credit, `ForgetSecrets`.
  - `StageFlow.luau`: Resolve carries `secrets`, Validate's `secretProblems`, a `secrets` parameter
    on `NodeState`/`MapState`.
  - `WeaponService.luau`: the GroundPoint rise only.
  - `DebugService.luau`: the three levers, both entry points.
  - `tools/crowd_harness/run_harness.py`: new sources ProfileSchema, Unlocks, SecretFlow; case file
    `tests_l2`.
  - `tools/crowd_harness/tests_l1c.luau`: two-argument `Rise`.
  - `tools/crowd_harness/mutate.py`: the L1c Rise entry updated, plus 48 L2 entries.
  - `tools/check_stage_mirror.py`: `L2_REFUSALS`, 13 broken copies refused alike.

## The GroundPoint rise expression (L2-4, server)

`WeaponService.GroundPoint`:
```lua
local airJump = player:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)) == true
if WallClip.TooHigh(casterFloor, floorY, WallClip.Rise(Tuning.Get().movement, airJump)) then
```
UnlockService sets that attribute on the server. The rise is 18 without the double jump and 30
with it. It matches the ui-engineer's client line, which reads `Players.LocalPlayer` instead of
`player`.

## Public API (what the lead wires and calls)

- `Unlocks` (shared, pure):
  - `AIR_JUMP = "doubleJump"`
  - `Attribute(id): string`, which returns `"Ability_" .. id`
  - `Owns(abilities?, id): boolean`
  - `HasKey(abilities?, config?, needs): boolean`
  - `BuyVerdict(state?, def?, gateOpen): string?`, with reasons unavailable > invalid > owned >
    busy > insufficientFunds
  - New beyond the contract: `DefProblem(def): string?` and `Find(config?, id): UnlockAbilityDef?`.
    The ui-engineer's panel uses `DefProblem`.
- `SecretFlow` (pure):
  - Types `Site`, `Reward`, `Verdict`, and `Opening = { verdict, valor, materials, family? }`.
  - `Sites(layout, levelFileOrLevel)`
  - `Triggered(site, root, rules)`
  - `Decide(site, hasKey, found)`
  - `MapRow(sites, found?)`
- `UnlockService`:
  - `Configure(mode)`, `Init()`, `Start()` (empty)
  - `AddPlayer(player)`, `RemovePlayer(player)`
  - `SetShopGate(fn)`
  - `OnBuyAbility(player, id)`
  - `OpenSecret(player, levelId, site, material): SecretFlow.Opening`
  - `HoldsKey(player, needs)`
  - `GrantAbility(player, id): boolean`, `RemoveAbility(player, id): boolean`
  - `ResetSecrets(player?)`, `Admitted()`, `NameOf(id)`
- `WaveService.ForgetSecrets(player?)` is new. The resetSecrets lever calls it after
  `UnlockService.ResetSecrets`.
- `StageFlow.NodeState(..., nodeId, secrets?)` and `StageFlow.MapState(..., leaderUserId, secrets?)`.
  The new last parameter is optional, so existing callers are unchanged.

## For the lead

1. **Required change outside my files (blocks luau-lsp on the hub and combat trees).**
   `src/shared/Combat.luau:17-27` and `src/shared/Armory.luau:99-109` keep exact structural copies
   of `Types.CombatProfile`. The old solver rejects the new optional fields ("extra fields
   abilities, families, secrets, shortcuts"). This causes 14 errors, in ArmoryService,
   ExpeditionService, CombatService, combat Main:194, ArmoryPanel and ExpeditionPanel. The
   ui-engineer reported the same fix. Add these four lines after `stats` in **both** copies:
   ```diff
    	stats: { kills: number, wavesCleared: number, expeditions: number, cashFromCombat: number },
   +	abilities: { [string]: boolean }?,
   +	secrets: { [string]: { [string]: boolean } }?,
   +	families: { [string]: boolean }?,
   +	shortcuts: { [string]: { [string]: boolean } }?,
    }
   ```
   **Update at the end of my run: someone (not me) has applied exactly this diff in the
   worktree.** With both sourcemaps regenerated, luau-lsp now reports **0 errors on both trees**
   (hub: `src/server src/shared src/client` with `sourcemap.json`; combat: `src/combat` with
   `sourcemap.combat.json`). The change is types only, so sim_combat is unaffected.
2. **Main.server.luau wiring.** Use the contract's seven steps as written, with these notes:
   - UnlockService has `Init` and `Start`, so it fits `orderedServices`.
   - In the range branch, `AddPlayer` sets every ability attribute true.
   - The handler is
     `RemoteService.SetHandler("RequestBuyAbility", function(player, abilityId) if RangeService.IsActive() then return end UnlockService.OnBuyAbility(player, abilityId) end)`.
     `OnBuyAbility` also ignores the range by itself.
   - DebugService and WaveService already require UnlockService, and UnlockService requires
     neither, so there is no cycle.

## Assumptions

- **`AbilityDef` was renamed to `Types.UnlockAbilityDef`.** `Types.AbilityDef` already exists at
  line 1008 (the weapons' ability), so the contract's name would redefine it.
  `ExpeditionsConfig.abilities: { list: { UnlockAbilityDef } }?`.
- **`CombatFxSecret.event` is typed `string`** ("found" | "locked" in its comment). With a
  singleton union there, luau-lsp could no longer infer the existing `CombatFxCamp` literals
  inside `RunFx.Push`.
- **The four profile maps are optional in `Types.CombatProfile`, with values typed `boolean`.**
  - Optional, because EconomyService's hub copy and v6-saved profiles lack them.
  - `boolean`, because the old solver handles a `true` singleton badly.
  - Every writer stores `true`.
  - UnlockService creates a missing map when it writes.
- **The new Combat.json rules and debug keys are optional in the types, and code fails closed
  without them.**
  - `secretReach/secretBelow/secretAbove` are not added to Validate's `NEEDED.rules`.
    `SecretFlow.Triggered` returns false when any of them is missing or not a finite number. A
    missing key disables chests; it does not refuse every level.
  - The three `debug.*Attribute` keys are also optional. When one is missing, its attribute lever
    is off.
- **Secret validation (L2-13).**
  - Every layout secret needs an entry with a non-empty name.
  - `valor` and `materials`, when present, must be whole numbers ≥ 0. `family`, when present,
    must be a non-empty string of at most 24 characters (`StageFlow.MAX_FAMILY_LENGTH`, the
    remotes' family cap).
  - A non-table `secrets` block is refused.
  - An entry that no layout secret names is not refused.
  - The designer's `sim_range.secret_problems` mirrors these rules exactly, and check_stage_mirror
    confirms it.
- **What counts as a reward entry.** An entry is a "reward entry" when it has any of `valor`,
  `materials` or `family`, the same test as check_levels L2-18e. Missing amounts count as 0.
- **Once-per-run memory.** `run.secretSeen[userId][siteId]` stores the last verdict. A `locked`
  chest is asked again only once that player holds the key (`UnlockService.HoldsKey`), so a J
  toggle in the middle of a run can still open it. Any other verdict fires once per run.
- **`OpenSecret` records only on `pay`.**
  - A player without a profile gets `nothing`.
  - `nothing` (key held, no reward) writes nothing.
  - Materials go to the level's material. If the level has none (""), they are credited and
    reported as 0.
- **The purchase is refused `unavailable` until `AddPlayer` has run for that player.** This
  guarantees the attribute is published before the player can buy.
- **The shop gate.** With no gate wired, the shop answers `busy` (closed).
- **Where the levers notify.** Grant and remove notices go to every run member through RunFx
  ("Double Jump on" / "off"), as the existing `gear` lever does.

## Gates (run 2026-10-17, after the designer's configs landed)

- Harness: `py tools/crowd_harness/run_harness.py . C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`
  gives **HARNESS: PASS (2,570 checks)**. The count was 2,453 before L2; `tests_l2` adds the rest.
- mutate.py: the filter `"l2:"` gives **48 run, 0 not caught**, and `"l1c: Rise"` gives 1 run, 0
  not caught. A stale-text check over all 835 entries found every replaced text exactly once, so
  my StageFlow and WaveService edits invalidated no older entry.
- `py tools/check_stage_mirror.py`: **CHECK: PASS**, including "L2: Validate's secrets lines
  refuse alike: 13 compared".
- `py tools/check_compile.py`: **PASS** (164 files).
- stylua (`--check`) and selene: clean on all 11 owned Luau files.
- luau-lsp (`--definitions tools/types/globalTypes.d.luau`, both sourcemaps regenerated with
  rojo): **0 errors on my files, and 0 on both whole trees** now that the Combat/Armory diff is in.
- The harness case files are not stylua-formatted, by repo convention (HEAD's `tests_l1c` was not
  either). All files are LF.

**Re-run after the designer's layout lands.** The notch and the chest moved to z −57 were not yet
in `ForestRoad.json` when I ran the gates. `tests_l2`'s real-file cases read the chest from the
layout, so they should follow, but the harness and check_stage_mirror need one more run once the
layout is in.

## What to check in Studio

1. **Fresh session (mock store).** Air jump is refused. K → buy is refused for lack of Valor. V
   (+10 Valor) → Buy → "Double Jump learned!". The air jump now works, and the Snapshot's
   `combat.abilities.doubleJump` is true.
2. **Forest Road with Double Jump.** Climb to the lookout and stand by the chest. Expect +3 Valor
   and +50 Timber once, the gold chest, the card, and the map card's lookout icon filled. Standing
   there again in the same run does nothing.
3. **Without Double Jump (J off).** No chest reaches. Leap Smash cannot target the ledge from
   Road5. The sniper perches need the designer's notch.
4. **H.** The chest is unfound again (column back, map icon "?"), and families stay. J toggles the
   Double Jump notice for the caller.
5. **With API access on and a real v6 profile.** The profile loads as v7 with four empty maps and
   nothing else changed. Output shows no "ahead of" warning.
