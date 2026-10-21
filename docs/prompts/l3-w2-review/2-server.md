# L3 W2 review, slice 2: server and shared

Reviewer: roblox-reviewer (Opus), 2026-10-21. Branch `l3-w2` at c79bec5, `git diff main...l3-w2` restricted to
`src/shared/WeaponLook.luau`, `Types.luau`, `Catalog.luau`, `src/combat/server/Services/WeaponService.luau`,
`AbilityService.luau`, and `tools/crowd_harness/tests_l3_w2.luau`, `run_harness.py`, `mutate.py`.
Read against `docs/prompts/l3-w2-contract.md` (its §11 rulings first) and `docs/prompts/l3-w2-reports/luau.md`.

**Verdict: 0 Critical, 0 Major, 5 Minor, 4 Suggestions.** The server code is right on every path the brief lists. The
attributes are written only by `showWeapons`, from server state only. Nothing a hit reads moved. Every finding is
either a gate that passes for the wrong reason (proved by review-only mutants on a `git archive` copy) or something
the docs and the lead need to know.

## Minor

**m1. T8 lists seven functions, so a hit can read `.held` from any other function and pass every gate.**
- Where: `tools/crowd_harness/run_harness.py:791` and `:973`; `tests_l3_w2.luau:685-691`.
- What is wrong: L3-50's rule is "no hit ever reads it". T8 counts `.held`, `showWeapons`, `noteHeld` and `WeaponLook`
  only inside `damageScale`, `meleeOrigin`, `aimAllowed`, `claimSlack`, `resolveMelee`, `resolveRanged` and `strike`.
  Many other functions decide whether and how a hit happens, and none of them is counted: `slotFamily`, `variantFor`,
  `slotLocked`, `activeBuff`, `shotCredit`, `resolveCharge`, `gearOf`, `WeaponService.Strike`, `FireProjectile` and the
  projectile step. No other gate loads WeaponService.
- Failure, probed (both give `HARNESS: PASS 3,950`):
  - P1: `slotFamily` returns `""` when `slot ~= shooter.held`. Every ranged attack from a fresh shooter is then refused
    as "a stale switch", so the server's `held` never becomes ranged. The player can never shoot until a ranged cast.
  - P2: `variantFor` drops the chosen style while `shooter.held == "ranged"`.
- Fix:
  - Add a file-wide count of `\.held\b` on `luau_code` for WeaponService, expected 3: the read in the `Values` call,
    `noteHeld`'s compare and its write.
  - Add a count of 0 for AbilityService.
  - Keep the seven per-function rows. Add P1 and P2 as `l3w2 T8` mutants.

**m2. T2 pins the three call texts, not that they are reached.**
- Where:
  - `run_harness.py:807-811`;
  - `WaveService.luau:2452`;
  - `ArenaService.luau:1243-1246`;
  - `RangeService.luau:318-325`;
  - `WeaponService.luau:2244-2251`.
- What is wrong: the luau report says T2 is reached in three places, and each place is pinned as text only:
  - `missionHook` is counted on the whole file with no indentation;
  - nothing pins ArenaService's call of the hook;
  - nothing pins RangeService.AddPlayer's two `prepareCharacter` calls;
  - `addPrepares` pins the inner call but not the `if state.mode == "mission" then` that gates it.
- Failure, probed (each gives `HARNESS: PASS 3,950`):
  - P3: the hook line wrapped in `if boot.proving then … end`. Live missions never prepare a later character.
  - P4: ArenaService's `hook(player, character)` replaced by `local _ = character`. Every respawn in a mission loses
    its weapons, and also `resetAir` and `VitalsService.PrepareCharacter`.
  - P5: RangeService's CharacterAdded handler no longer calls `prepareCharacter`. A range respawn holds nothing and
    stands where it fell.
  - P6: AddPlayer's `state.mode == "mission"` flipped to `"range"`. The first character after admission holds nothing
    until a respawn.

  P4 and P6 also break the vitals. That is older reach, but T2's "reached" claim rests on it.
- Fix: pin each of these as exact text with its tabs:
  - ArenaService's `local hook = hooks.character` / `if hook ~= nil then` / `hook(player, character)` block, inside
    Admit's CharacterAdded handler;
  - `hooks.character = hook` in `SetCharacterHook`;
  - `missionHook` inside `WaveService.Init`'s body with its leading tab, and `Init`'s exits counted (its one early
    return is the range's);
  - RangeService.AddPlayer's two `prepareCharacter(player, character)` lines;
  - the `\tif state.mode == "mission" then\n` line in AddPlayer, together with `addPrepares`.

  Add P3 to P6 as mutants.

**m3. T9, T12 and T14 check for words, not structure, so a dead inner branch or a later undo passes.**
- Where:
  - `run_harness.py:1001-1003` and `:1027-1036` (T9 `otherInBranch`, T14 `gatedFrames`);
  - `run_harness.py:978` (T12).
- What is wrong:
  - `otherInBranch` counts the call text anywhere in the block. An inner `if false then` is still inside the block.
  - `LOW_END_GATE` accepts any `if` line that contains `not Theme.lowEndDevice`, so `if true or not
    Theme.lowEndDevice then` matches.
  - T12 counts the five property lines inside `seal`, but nothing pins that no later line in HeldWeapons turns one of
    them back.
- Failure, probed (each gives `HARNESS: PASS 3,950`):
  - P7: `SwingOther` wrapped in `if false then … end` inside the branch. No teammate's arm ever moves.
  - P8: the gate reads `if true or not Theme.lowEndDevice then`. Low-end phones turn the stage every frame, which
    L3-56 forbids.
  - P13: `base.CanQuery = true` added after `seal(model)` in `modelFor`. The Base is in every client query again,
    which L3-52 forbids.
- Fix:
  - T9: require the call as a whole line at exactly two tabs inside the branch, and no `if` line between the branch
    head and the call.
  - T14: pin the exact `\t\t\tif not Theme.lowEndDevice then\n\t\t\t\tlook.turn = RunService.RenderStepped:Connect(`
    text. T4 and T6 already pin their lines this way, and control mutant C1 (the cast's call wrapped in an `if`) is
    caught by `castHeld`, so the method works.
  - T12: add a HeldWeapons file-wide count of 0 for
    `\.(?:CanCollide|CanQuery|CanTouch|Anchored)\s*=\s*true|\.Massless\s*=\s*false`.

  Add P7, P8 and P13 as mutants.

**m4. In the lobby `WeaponHeld` never changes, so teammates see a frozen slot (and a raised arm) for the whole stay.**
- Where: `WeaponService.luau:2435`, `:2556-2562` and `AbilityService.luau:919`, the act gate `WaveService.luau:394-396`
  (`ArenaService.InRun()`); the luau report's "What to check in Studio".
- What is wrong:
  - Outside a run, every attack, draw and cast is refused before its acceptance. A pure switch tells the server
    nothing (L3-65).
  - So in the dungeon lobby a teammate always shows the slot of their last accepted action in the previous run. A
    fresh arrival shows melee.
  - Under ruling 6 that includes the right arm held raised at 80° with the bow, if their last action was a shot, while
    their own screen shows the sword.
  - Only an Armory equip (`SetFamily`) changes what others see there.
- Failure scenario:
  - `proving.rbxl` boots into the lobby.
  - Ben runs the two-client teammate check (L3-61) there, or follows the luau report's "A shot or a bow draw flips
    WeaponHeld to ranged".
  - Nothing flips, and it reads as a bug.
- Fix:
  - Route to docs-keeper: PLAYTEST's teammate step and the attribute check happen inside a level, and the lobby shows
    each teammate's last in-run slot.
  - The lead may tell Ben in one line. A lobby fix would need a stance intent, which L3-61 rules out.

**m5. A forged client can flip `WeaponHeld` 40 times a second with draws of a melee family.**
- Where: `WeaponService.luau:2544-2567` (`OnDraw`, `noteHeld` at `:2566`); `CombatRemotes.luau:245-250`
  (`RequestRangeDraw` on the `rangeAttack` bucket, 40/s, `Combat.json:19`).
- What is wrong:
  - `OnDraw` accepts any family the player holds in that family's slot, a melee one included, with no rate check of its
    own. The only charge variants are the Longbow's, so an honest client draws only a ranged family.
  - Before W2 a melee draw was harmless. Now each accepted draw is a `noteHeld`.
- Failure scenario:
  - A modified client alternates `RequestRangeDraw("broadsword")` and `RequestRangeDraw("longbow")`.
  - The server flips `WeaponHeld` up to 40 times a second, inside the bucket.
  - Each flip replicates to every client. Each client re-welds both models and tells the hold listener, which eases the
    remote arm between hanging and raised.
  - The result is visual jitter on every screen (no crash, no hit change), and it defeats L3-60's premise that a
    re-hang is rare.

  Attacks cannot do this, because each is held to its weapon's rate by the credit check.
- Fix (smallest):
  - Refuse a draw whose family is not in the ranged slot, beside the existing refusals at `:2556-2562`, e.g. `or
    def.slot ~= "ranged"`.
  - `drawExits` stays 3 (no new `return`), and the T5 texts are untouched.
  - Add a mutant that removes the new clause.

## Suggestions

**s1. Several counts depend on spelling (the W1 pattern again).** Each of these passes the harness:
- P9: `shooter["held"] = "ranged"` in `OnDash`, a second writer that `heldWrites`' `\.held\s*=` does not see;
- P10: `body:SetAttribute("WeaponHeld", "ranged")` in `OnDash`, a second attribute writer that never touches
  `WeaponLook.`;
- P12: `shooter.loadout = { melee = family, … }` in `SetVariant`, a pair change that is never shown and that
  `loadoutWrites` does not count.

Add three counts:
- 0 `"Weapon(?:Melee|Ranged|Held)"` string literals anywhere under `src` outside `WeaponLook.luau`;
- 0 `\[\s*"held"\s*\]` in WeaponService;
- `\.loadout\s*=(?!=)` = 0 in WeaponService (the constructor writes `loadout = loadout` with no dot).

**s2. T4 and T6 say "none after the acceptance" but count every exit.**
- `attackExits` 12 and `castExits` 9 (`tests_l3_w2.luau:665, 673`) are totals for the whole function.
- P11 moves OnAttack's credit refusal from before `noteHeld` to after it, keeping 12 exits. It passes, and then a
  refused shot flips the look and burns its seq.
- Do as ruling 7 did for T9: count the exits after the noted line, expecting 0 in both bodies (true today: none
  follow `:2504` or AbilityService `:1036`).

**s3. The bounds slack exists twice.**
- `WeaponLook.luau:30` `BOUNDS_SLACK = 0.01` mirrors `weapon_frames.py:68` `POINT_SLACK = 0.01`.
- A point between two different slacks would be written by one and warned about by the other. Today the harness's
  shipped-file `Problems` check would catch it.
- Either write the slack into `WeaponModels.json` (one number, read by both), or name the pair in each file's comment
  so a change to one finds the other.

**s4. `Problems` is not "sorted by family" across its two passes.**
- `WeaponLook.luau:186-233`: the weapons-side faults (missing families) come first, then the file-side ones.
- "spear: no model entry" therefore precedes "broadsword: its tip lies outside its bounds".
- The test (`tests_l3_w2.luau:569-582`) puts both faults in the second pass, so it cannot see this.
- Either `table.sort(problems)` before returning, or reword the comment.

## Checked and clean

- **Write points.** The attributes come from `showWeapons` only (`WeaponService.luau:2153-2161`), from
  `shooter.loadout` and `shooter.held`. It is called by:
  - `PrepareCharacter` (`:2283`), on every fresh character: mission arrival via AddPlayer, mission respawn via the
    ArenaService hook, range spawn and respawn via `RangeService.prepareCharacter`;
  - `SetFamily` (`:2699`): the lobby equip (`UnlockService.OnSetFamily:292-293`), `removeFamily` and `resetArmory`
    through `holdStarter` (`:133`), and the range's `weapon` command;
  - `noteHeld`, after each accepted attack (`:2504`), draw (`:2566`) and cast (`AbilityService:1036`, after
    `mechanic.launch` succeeded).
  `grantFamily` changes ownership, not the loadout. The only writes of `shooter.loadout.melee/ranged` are in
  `SetFamily`.
- **Server authority.** No client value decides a value:
  - families come from the server loadout, which is checked by `Unlocks.LoadoutOf` / `FamilyVerdict`;
  - the slot comes from the family def (attack, draw) or from the server-validated slot word (cast);
  - client `SetAttribute` on a character does not replicate.
  No server code reads `GetAttribute` on a character, and nothing listens to these attributes on the server.
- **Hits.** Nothing a hit reads moved:
  - `git diff main...l3-w2` touches only `WeaponService` (+52/−3, all of it new lines) and one `AbilityService` line on
    the server;
  - no other server or shared file changed except `Catalog`, `Types`, `WeaponLook` and the two configs;
  - `InputController.luau`, `Armory.json`, `Combat.json`, `ProvingGrounds.json`, `Levels` and `Layouts` are unchanged.
- **Respawn and timing.** `held` lasts across a respawn, and so does the client's `rangeState.activeSlot` (only
  `setActiveSlot` writes it, `InputController.luau:1859-1868`), so the two agree on a new body. No yield sits between
  Admit and AddPlayer.
- **`WeaponLook`.** It is pure: one require (`Types`), no Instance or service, `--!strict`. `Def` refuses everything
  the contract lists, `IconId` returns 0 on every malformed path, and `Values`/`Read` normalise the slot word. The
  pure tests check each refusal with a case of its own, and the shipped-file case reads the real
  `WeaponModels.json` (15 entries, `Problems` empty, every tip ≥ 0.3 from its grip).
- **`Catalog.GetWeaponModelsConfig`** mirrors `GetAssetsConfig` (optional, cached once found). The server never
  calls it.
- **`Types`.** `AssetIcon` and the optional `AssetsConfig.icons` match the shipped `Assets.json` v5 block (15 entries
  of `assetId`/`imageId`/`sha256`, `imageId` 0 until the paste). `WeaponModelDef`/`WeaponModelsConfig` match
  `WeaponModels.json` (15 families = ProvingGrounds' 15).
- **Gates.**
  - `mutate.py` `FILES` holds every file `L3W2_*` and `SOURCES` read, with no duplicates; there are 138 `l3w2`
    entries.
  - The `l3w2 T2` filter run on the scratch copy: 5 of 5 caught (1 min).
- **No leaks, no per-frame work, no yields** on the server. The new calls run in remote handlers, never in a
  Heartbeat loop.
- **Toolchain.**
  - Harness on a `git archive` copy: `HARNESS: PASS (3,950 checks)`.
  - `check_compile.py`: PASS, 180 files; WeaponService is under 105 top-level locals.
  - luau-lsp on the slice files against fresh combat and hub sourcemaps: 0 diagnostics.
  - selene: 0/0/0. stylua `--check`: clean.

## Probe record

Review-only mutants, applied one at a time to a `git archive HEAD` copy and run through that copy's own harness. They
are not in `mutate.py`.

| # | Mutant | Result |
|---|---|---|
| P1 | `slotFamily` returns `""` for the slot not in use | survives |
| P2 | `variantFor` drops the style while `held == "ranged"` | survives |
| P3 | WaveService's hook line wrapped in `if boot.proving then` | survives |
| P4 | ArenaService's `hook(player, character)` removed | survives |
| P5 | RangeService's respawn handler drops `prepareCharacter` | survives |
| P6 | AddPlayer's `state.mode == "mission"` flipped | survives |
| P7 | `SwingOther` in an inner `if false` | survives |
| P8 | `if true or not Theme.lowEndDevice then` | survives |
| P9 | `shooter["held"] = "ranged"` in `OnDash` | survives |
| P10 | `SetAttribute("WeaponHeld", "ranged")` in `OnDash` | survives |
| P11 | OnAttack's credit refusal moved after `noteHeld` | survives |
| P12 | `SetVariant` swaps the whole loadout table | survives |
| P13 | `base.CanQuery = true` after `seal(model)` | survives |
| C1 | control: the cast's `NoteHeld` wrapped in `if slotName == "melee"` | caught (`castHeld`) |
