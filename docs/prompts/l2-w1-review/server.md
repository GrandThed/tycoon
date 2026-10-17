# L2 W1 review: server slice (2026-10-17)

Diff `main..l2-secrets` at e39215b (the review brief 6feb088 on top). Files read in full or the whole diff:
ProfileSchema.luau with DataService's load and migration path, Types.luau, Unlocks.luau, WallClip.luau,
Armory.luau and Combat.luau (type copies), SecretFlow.luau, UnlockService.luau, CombatRemotes.luau,
WaveService.luau, StageFlow.luau, WeaponService.luau (GroundPoint), DebugService.luau, combat
Main.server.luau. I also read InputController.groundPoint and MovementController.Leap for the shared F1/F2 rule.

Gates run on a `git archive HEAD` copy: harness `HARNESS: PASS (2,586 checks)`, `check_compile` PASS (164
files), stylua and selene clean on the 12 slice files, luau-lsp on the combat tree with no errors.

**Verdict: 0 Critical, 0 Major, 4 Minor.**

## What holds (checked, not only read)

- **v7 forward compatibility.**
  - ProfileStore 1.0.3 `ReconcileTable` only fills nil string keys, using deep copies, and never deletes.
  - The `state.version > SCHEMA_VERSION` guard in `DataService.runMigrations` (103-108) warns and leaves the
    profile untouched. It has been there since d166a9a (`git log -S`), so every published build has it.
  - No hub or combat code reassigns `state.combat` outside `Migrations[4]`'s nil branch.
    `EconomyService.copyCombatProfile` builds only the client copy.
  - So after a hub publish, live v6 profiles gain four empty maps. The frozen live Expeditions place loads
    them, warns, plays and saves them back. Nothing is lost in either direction.
  - `Migrations[6]` adds each map only when it is nil, always as a fresh table. `[4]`'s nil branch and
    Reconcile both guarantee that `state.combat` exists when it runs.
- **Purchase.**
  - Type and length are checked by the `RequestBuyAbility` validator (`calls` bucket).
  - The id comes from the config through `Unlocks.Find`, and the price comes from the config.
  - `BuyVerdict` checks in order: profile, valid def, owned, gate (`WaveService.MayLeave`), Valor.
  - `state.players` refuses anyone `AddPlayer` has not seen.
  - Nothing between the check and the write yields: `MayLeave` → `GetMemberFor`, `FireClient` and
    `SendSnapshot` all come after the write. A second request therefore reads "owned".
  - Leaving mid-buy cannot interleave. Return releases the profile, so `GetState` is nil and the answer is
    "unavailable".
  - Valor and the ability live in one table, so autosave and release keep them together. No receipt is
    involved.
- **Chest.**
  - `OpenSecret` reads the key from the profile (`Unlocks.HasKey` → `Find` + `Owns`), never from the
    attribute.
  - `Decide` checks found before key before reward. A pay writes Valor, materials, family and
    `secrets[levelId][id]` in one call with no yield.
  - `run.secretSeen` makes each verdict fire once per run. A "locked" verdict is asked again only once the
    key is held.
  - The tick skips bots, waiting members and anyone down, and runs only in a live phase, after `advance`.
  - `freshRun` resets `secretSeen` at every start and return. `startLevel` sets `secretSites` after the
    `freshRun`.
  - A teleport or a cheat that puts the root on the ledge gains nothing without the key in the profile
    (L2-23).
- **Map rows.** Each member gets their own `combat.secrets` row (`secretRows(player, built)` inside the
  per-member loop). The sites are cached per level. The opener's map is resent on pay, and the target's on
  reset.
- **Levers.**
  - `DebugService.OnRequest` returns unless the place is in Studio.
  - The attribute poll is connected only in Studio and returns in the range.
  - `applyLever` refuses every lever in the range.
  - `OnBuyAbility` ignores the range, as does Main's handler.
  - Range `AddPlayer` sets every ability true, so the bench keeps rise 30 and the air jump.
- **The shared rule.**
  - `WallClip.CasterFloor` and `LeapApex` are pure. The server's GroundPoint and the client's groundPoint
    use the same probe (`GROUND_PROBE_DEPTH` 250 from the root, no lift), the same standing offset
    (`HipHeight + Size.Y/2`), and the same rise from the same attribute. The server reads the copy it set
    itself, and a client-set Player attribute does not replicate.
  - F2 is strictly tighter than before (feet − rise against the old feet) and applies only when nothing is
    under the caster. A caster on the ground is unchanged.
  - F1 at ground level gives `max(from, to) + lift`, as before. With `up` = `down` = 0 the gravity is 0,
    not a division by zero.
  - `MovementController.Leap` has one caller, and it passes the floor.
- **Main wiring.** All seven steps are done as the contract asks: require, Configure, SetShopGate,
  `orderedServices`, `AddPlayer` in both branches before `sendSnapshot`, `RemovePlayer` in
  `releasePlayer`, and the handler.

## Minor

1. **`src/combat/server/Services/SecretFlow.luau:112-116`: the Raiders' Cache can never trigger.**
   - What: `Triggered` measures the flat distance from the root to the chest's centre (≤ `secretReach` 5)
     and the height from its foot (≤ `secretAbove` 9). The cache (`ForestRoad.json:327-335`) is a
     collidable 12 × 12 × 10 block (`LevelGeometry` 821-828, `collide = true`) standing on Road top 8.
     - A root beside it is at least 6 + 1 = 7 from the centre.
     - A root on its top is 21 − 8 = 13 over its foot.
     - Neither passes.
   - How it shows:
     - In W1 the contract's `locked` cue (L2-14, "Needs FIRE") never fires at the cache, though a player
       who climbs onto it (a known sniper perch) expects one.
     - In W2 or W3, when the cache gets a fire reward, no player can ever open it.
     - No gate sees this: `check_levels` L2-18(a) "the trigger holds a standable point" runs only for
       secrets whose `needs` is a sold ability.
     - The shrine (12 × 12 × 3) works, because a root on its 2-high top is 6 over its foot.
   - Fix: measure the flat distance to the chest's footprint rectangle instead of its centre. Put `sx` and
     `sz` on `Site`, compute `max(|dx| − sx/2, 0)` and the same for z, and set the reach to about 2. Or
     keep the model and run L2-18(a) for every secret, not only sold keys. Then mutate a large chest and
     see the gate go red. MISSIONS_DESIGN §22 already rebuilds the cache as a cave in W2, so add "the
     trigger is reachable" to that wave's checks either way.

2. **`src/combat/server/Services/StageFlow.luau:252-253`: a constant is duplicated.**
   - What: `MAX_FAMILY_LENGTH = 24` is a second copy of `CombatRemotes.luau:40`
     (`MAX_FAMILY_LENGTH = 24`). Its comment says it is "the remotes' family id cap". CLAUDE.md says never
     to duplicate a constant in code.
   - How it shows: W2 widens the remotes' cap for a longer family id but misses this copy. Validate then
     refuses a Forest Road file whose secret names that family, and the whole level is locked.
   - Fix: keep one home and have the other read it. For example, export it from StageFlow and have
     CombatRemotes require it (CombatRemotes already requires shared modules), or move both to a small
     shared limits module. `sim_range`'s mirror then follows the one value.

3. **`src/combat/server/Services/UnlockService.luau:184-202`: the purchase's use of its verdict is untested.**
   - What: `tests_l2` proves `Unlocks.BuyVerdict`. The 15 lines that act on it (refuse unless the verdict
     is nil, debit Valor, set owned, set the attribute, send the snapshot) cannot load in the harness, and
     no mutation reaches them.
   - How it shows: an edit such as `if verdict == "owned" then` would sell Double Jump to someone with 0
     Valor (Valor goes negative), and every gate would stay green.
   - Fix:
     - Option A: move the decide-and-apply into a pure `Unlocks.Apply(state, def, gateOpen): string?`, which
       writes `combat` on success and returns the verdict. `OnBuyAbility` then only sets the attribute and
       answers. Add harness cases for "debited once, owned, a second call reads owned" and a mutation.
     - Option B: accept it as checked by reading.
     - The same applies to `OpenSecret`'s write (lines 235-244). Today it is checked only by reading.

4. **`src/shared/Unlocks.luau:61-71` against `UnlockService.luau:147-159`: two rules for a repeated id.**
   - What: Init skips a malformed entry and still accepts a later valid entry with the same id, because
     `seen` marks only valid ones. `Find` returns the first entry with that id and gives nil when it is
     malformed.
   - How it shows: if a config has a broken first `doubleJump` and a good second one, `publish` sets the
     attribute from the good entry, while `Find` makes every purchase "invalid" and `HasKey` false.
     Config-only and unlikely.
   - Fix: have `Find` skip malformed entries and keep looking, or have Init mark the id seen even when the
     entry is malformed. Then both read the same entry.

## Not findings (looked at and ruled out)

- **F2 over a void.** It also lowers a void target's Y by the caster's rise. The strike lands where no
  floor and no enemy exist, so nothing changes in play.
- **Stale `Ability_` attribute between a Return's release and a failed-teleport re-admit.** `abortFor`
  re-runs the join sequence, and `AddPlayer` republishes.
- **Per-tick cost of `tickSecrets`.** It is members × 3 sites. `HoldsKey` runs only for "locked" sites.
- **The resetSecrets lever with API access lets the lookout pay again into a real profile.** It is
  Studio-only, the same as GrantValor.
