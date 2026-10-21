---
name: l3-armory-review
description: L3 "the Armory" reviews (tiers per weapon family, profile v8 with a one-time refund, saved loadout, stars saved, the Armory screen) - W1 slice 1 saving 2026-10-20 0C/0M/6m (harness proves a COPY of the migration runner; validator rules shadowed by a second rule; Hard-only trophy; old servers after publish); W1 slice 2 combat server 0C/1M/2m/1s (per-family TierOf vs per-slot sim mirror, unharnessed service lines, a star lever eats a first-clear reward); W1 slice 3 hub + hosts 0C/0M/2m/5s (hub service lines under no gate; a full-screen card covers earlier same-ZIndex siblings like the party invite); W1 slice 4 screen 0C/0M/3m/7s (hub modal vs Roblox TouchGui at equal DisplayOrder; pad selection restored only on repaint; style-button pending gate unharnessed); W1 fix diff 0C/0M/2m/5s (text checks pin a call, not where its arguments come from or whether it is reached; a sibling lever in the other place keeps the bug the ruling fixed)
metadata:
  type: project
---

L3 W1 is on branch `l3-armory` in worktree `tycoon-p5`. Brief: `docs/prompts/l3-w1-review.md` (four slices).
Findings go to `docs/prompts/l3-w1-review/<slice>.md`. Contract: `docs/prompts/l3-w1-contract.md`; its §12 rulings
override the text above them.

**Several slice reviewers may share this file. Re-read it and Edit only your own section. Never Write it whole.**
On 2026-10-17 an L2 reviewer overwrote another's section with Write.

**Why:** later L3 waves (W2 models, L4 publish, the Castle band) build on v8, the ladder and these gates.

**How to apply:** for any later schema step or validator, run the probes below before trusting "the harness proves it".

## W1 slice 1, saving and the shared rules (2026-10-20, a2628da): 0 Critical, 0 Major, 6 Minor

Findings: `docs/prompts/l3-w1-review/1-saving.md`.

**Patterns:**
- **A non-idempotent migration step makes the runner load-bearing, and the harness tests a copy of it.**
  - `Migrations[7]` refunds materials. It is the first step that is not if-nil.
  - The harness's `L2.migrate` (`tests_l2.luau:68`) is a hand copy of `DataService.runMigrations`. No gate loads
    DataService.
  - Probe: make the real loop call `migrate(state)` twice. Every gate stays green, and a 3/3 profile is paid twice.
  - Ask for a pure `ProfileSchema.Run(state)` that both DataService and the harness call, plus mutants. Recheck at
    every schema bump.
- **A validator check written as `#lines >= 1` per break is vacuous when the break trips two rules.**
  - "bandSize 3" also breaks the costs-per-position rule, "bandSize 0" breaks three rules, and melee[1] = −1 also
    breaks melee ≥ ranged.
  - So the bandSize rule, the bands-cover rule and the negative-HP rule are all unproven. The mirror's
    ARMORY_BREAKS shares the same cases.
  - Probe: replace one rule with `if false`, then run the harness and check_stage_mirror.
  - The isolating breaks are `bandSize 4.5`, removing one band, and `ranged[1] = -1`.
- **An expected value computed by the function under test** (`tests_l2:122` reads `LegacyRefund(...)` to build its
  expectation). Pin a number instead.
- **A trophy keyed on one difficulty.** `starHeld` reads `stars[level].hard` only, and `StageFlow.Award` stars only
  the difficulty cleared. So a Brutal clear in a party does not open T4.
- **A publish that refunds into a currency that old servers still sell.** Old servers keep running after a publish
  and still sell slot `gear` to a v8 profile, which then loses that Timber. Ask for "Shut down all servers" in the
  publish steps.

**Verified, safe to reuse:**
- `Armory.json` slot prices are 10 / 60 / 180 per band in every commit (ac46d13 … ff7a910, including live 2b15570), so
  `legacy.gearCosts` matches. The template `gear` has been 0/0 since C0. Only `tryBuyGear` and Studio levers write
  `gear`, both on live and on main.
- Live is 2b15570, at SCHEMA 6, with the ahead guard (d166a9a is an ancestor). No old code reads `combat.tiers`,
  `loadout` or `stars`.
- ProfileStore 1.0.3 deep-copies the template for new profiles (`ProfileStore.luau:1497, 1766`).
- `mirror_mutants.py` has no Armory entries yet; luau-a proposed four. The comparisons do bite: a strict funds edge
  gives "3 of 4 differ".

**Recipes:**
- Make a scratch copy with `git archive HEAD | tar -x -C <scratch>/tree`, because the worktree is clean when the
  branch is committed. Then use a `mut.py` that applies `str.replace` with `unicode_escape` args and asserts exactly
  one match.
- Run the harness on the copy with `run_harness.py <tree> <main>/tools/bin/luau.exe` (9 s). `check_stage_mirror.py
  --luau <luau.exe>` takes 6 s. `sim_combat.py --check` takes 3 min and passes 23/23.

## W1 slice 2, the combat place server (2026-10-20, a2628da): 0 Critical, 1 Major, 2 Minor, 1 Suggestion

Findings: `docs/prompts/l3-w1-review/2-combat-server.md`.

**Patterns:**
- **A per-family rule in the game against a per-slot mirror in the sim.** The game's `damageScale` and `gearOf` read
  `Armory.TierOf(family)`, and a non-starter that was never upgraded sits at its window START (Flamethrower T2,
  Frost Hammer T5). `sim_range`'s `level_view` `_scales`, the pair kits and `gear_max_hp` still read `gear[slot]`.
  - Every gated L2 pair row (`check_cave_runs`) then measures a weapon the game does not field.
  - Under the game rule the Frost Hammer pair clears in 2.2 min, earns ×1.83 the cash and kills the Colossus in
    13.9 s against 76.4 s: all three gates fail. The Flamethrower pair drops under the 4.0-minute floor on one seed.
  - Whenever a rule moves from slot to family, or a window or start tier is added, grep the sims for `gear[slot]` and
    for `scales.get(slot`.
- **The service lines again, for the fourth wave running.** Four mutants applied together all survive
  (`HARNESS: PASS 3,539`):
  - the slam's call reverted to `"melee"`;
  - `tier = 1` in `damageScale`;
  - the upgrade's gate replaced with `true`;
  - `GrantFirstClear` dropped from `EndRun`.

  No gate loads WeaponService, UnlockService or WaveService, and run_harness has no L3 source check.
- **A reward keyed on "new star" is consumed by a star lever.** U (`GrantStars`) stars without the reward, and the
  first clear then never fires. Check every lever that writes the state a reward is keyed on.

**Verified, safe to reuse:**
- In combat `runJoinSequence` the order is: load, then `Admit`, then `WeaponService.AddPlayer`, then the first
  `PrepareCharacter`. Before the shooter exists, `gearOf` uses `LoadoutOf` with the same starters, so the bar agrees.
- `WaveService.Init` sets the mission rules once, so the lobby bar is the held pair's, not `RangeHp`.
- `ArenaService.CreditSummary` is display only. The profile's Valor comes from the service that granted it.
- `StageFlow.Resolve` passes the level file's `difficulties` through, so any per-difficulty key survives into
  `run.level`.
- `DataService.Release` nils the profile before `EndSession`, so a handler after a release reads nil.

**Recipes:**
- Pair probe: `s2probe/pair_scale.py <repo> [game]`. It imports `tools/sim_range.py` (sys.path, no `-I`) and wraps
  `LevelRun.__init__` and `breath_step` to re-scale per family with `sc.tier_of`. It reruns `pairBow`, `pair`,
  `pairIce` and the cave sniper's breath on Normal. Use `py -3.12`; it takes about 3 min per mode, so run both modes
  in parallel.
- For a mutant copy, `git archive HEAD src tools combat.project.json default.project.json`. With only `src` and
  `tools/crowd_harness`, the harness fails seven unrelated checks (check_levels Part counts and the camera zoom).

## W1 slice 3, the hub and the client hosts (2026-10-20, a2628da): 0 Critical, 0 Major, 2 Minor, 5 Suggestions

Findings: `docs/prompts/l3-w1-review/3-hub-hosts.md`.

**Patterns:**
- **The hub's service lines are the least gated code in the repo.** No tool loads anything under
  `src/server/Services`: `run_harness.py` SOURCES lists no hub service, and grepping `tools` for
  `copyCombatProfile`, `computeGearPower` or `ArmoryService` finds nothing.
  - `EconomyService.copyCombatProfile` is the Delta's whole `combat`. C0's version dropped the v7 maps.
  - Ask for a pure `CopyProfile` plus a check that walks ProfileSchema's template `combat` keys. Recheck at every
    schema bump.
- **A full-screen card added to the hub covers every earlier sibling at the same ZIndex.** The hub's ScreenGui uses
  Sibling ZIndex, and equal ZIndex draws in child order.
  - The PartyInviteToast (ZINDEX_CARD, built earlier, 30 s TTL) sits under the Armory's scrim and frame.
  - A dock panel never covered it.
  - For any new full-screen card, list the earlier ZINDEX_CARD roots in `UIController` boot order: the welcome card,
    the invite toast, the debug strip. Ask which of them must stay on top.
- **The readiness pattern for one key plus a listener that disconnects.** `combatRemotesReady` keys on one intent.
  The ChildAdded listener stops once `combatWiringComplete()` holds, and that predicate covers events, not every
  intent. The risk is near zero, because RemoteService makes the whole set in one frame. A config read once at boot
  has the same shape.

**Verified, safe to reuse:**
- The hub and combat upgrade and equip rules match line for line:
  - `Armory.Upgrade` with `OwnsFamily(families, f, Starters(loadout))` and `built = Catalog.GetLevelIds()`, read at
    Init;
  - `Unlocks.FamilyVerdict`, then `SaveLoadout`;
  - the hub gate is `true`.
- The hub ScreenGui z ladder: CARD 15 (welcome, invite, Armory, summary, debug strip), DIALOG 20, LOAD 22,
  CEREMONY 25, TOAST 30.
- The hub delta flush runs at `remotes.stateDeltaHz` 4. The ActionResult always arrives before the Delta, so the
  screen's pending-until-the-state-shows-the-tier rule (`settleUpgrade`) is what stops a double buy in the hub.
- `.proving.project.json` is gitignored and regenerated by the "Build proving" task. A stale copy in a worktree is
  not a finding.
- `luau-lsp analyze` per tree works with fresh `rojo sourcemap`s into scratch: hub `src/server src/client src/shared`,
  and combat `src/combat src/shared` plus the mapped hub UI files. Both came back clean on a2628da.

## W1 slice 4, the Armory screen (2026-10-20, a2628da): 0 Critical, 0 Major, 3 Minor, 7 Suggestions

Findings: `docs/prompts/l3-w1-review/4-screen.md`.

**Patterns:**
- **A full-screen modal in the hub on touch can sit under Roblox's own TouchGui.**
  - Both ScreenGuis are DisplayOrder 0, and equal DisplayOrder has no defined draw order.
  - TouchGui is made lazily, once a humanoid exists and the preferred input is touch, so usually after the HUD.
  - The combat place is safe: `ExpeditionHUD` is DisplayOrder 1.
  - The jump button has two geometries:
    - classic: 70 px at (w − 95, h − 90);
    - AvatarAbilities flag: 72 px at (w − 136, h − 136), which lands on the middle of a bottom-right action button.
  - Fix pattern: `GuiService.TouchControlsEnabled = false` while the modal is open. ControlModule watches that
    property.
- **A gamepad selection restored only on repaint.**
  - A screen that sets `SelectedObject` only when it opens with `padLast()`, and fixes it only inside `paint`, has no
    selection after a K-open followed by picking up the pad.
  - A is sunk, so it does nothing, and the stick walks the character behind the scrim.
  - Ask for reselect on A, plus `LastInputTypeChanged` and `SelectedObject` listeners while open.
- **A pure model's branch behind a guard the screen also enforces survives mutation.** The style buttons'
  "one equip in flight" (`live = true`) still gives HARNESS PASS. Probe every `pending` gate per button kind, not
  per model function.

**Verified, safe to reuse:**
- The press router (A action, `padHeld` plus a 0.2 s release window, `lastAny`) dedupes engine and action presses in
  either order.
- `Instance.Destroying` fires for descendants, so a teardown on the root covers ScreenGui destruction.
- Both hosts' ScreenGuis are `ResetOnSpawn = false`.
- `Motion.Info` halves durations under `reducedMotion` and does not zero them.

**Recipes:**
- **Read the PlayerModule source locally.** It is at `%LOCALAPPDATA%\Roblox\Versions\<newest>\ExtraContent\scripts\
  PlayerScripts\StarterPlayer\PlayerModule\`: `ControlModule/init.lua` (TouchGui) and `TouchJump.lua` (jump
  geometry). This settles touch-control questions without Studio.
- **Port the layout to check a screen's fit.** A Python port of `ArmoryScreen.layout()` (the `l3w1-screen/layout.py`
  scratch file) reproduced ui-A's table and gives viewport rects to overlap against the jump button.
- **Review-only mutants.** Use a second `git archive` copy and a script that appends `PROBE_MUTATIONS` after
  `MUTATIONS.update(L3_UI_MUTATIONS)`. `mutate.py <copy> <luau> "probe:"` takes about 1 min for 4 mutants.

## W1 fix diff (2026-10-20, `git diff f6c426d 32d7893`): 0 Critical, 0 Major, 2 Minor, 5 Suggestions

Findings: `docs/prompts/l3-w1-fix-diff-review.md`. Every ruling R1-R11 and the taken suggestions were done; R12 is
docs-keeper's at the end of the wave.

**Patterns:**
- **A text check pins the call, not where its arguments come from.** R3/R4/R5/R7 counted each service line exactly,
  and every one does fail when its own text breaks. But review-only probes on the lines that FEED them all survive
  (`HARNESS: PASS 3,654`):
  - `local combat = nil` in `damageScale` (no upgrade ever reaches a hit) or in `gearOf`;
  - the pre-fix raw-override early return pasted back into either function (2-s1 undone; counts unchanged);
  - `runMigrations(profile.Data, player)` deleted from the load path (nothing ever migrates);
  - GrantStars' `local level = if false` (U pays nothing again), grantStar's difficulty `"normal"`;
  - SavedPower's `weapons` argument `nil` in Main and EconomyService (Power always the starters').
  - Ask for counts on the input lines, and a `return` count per checked body, so an early return cannot hide.
- **A sibling lever keeps the bug the ruling fixed.** R4 made the dungeon's U pay first clears; the hub's
  `grantStarTo` (strip button + `DebugGrantStar`) still stars without paying, now under the same caption.
  Grep every entry point of a lever, in both places, when a ruling changes what it does.
- **A "not vacuous" gate pooled over several courses proves only the course that fires.** sim_range's "the fire
  sniper casts at least once" collects every `" + "` course together: CaveExit casts (6 runs), CaveMouth's two
  courses never do, so their breath-tier check is empty. Read each course's own `armed` line, not the pooled count.
- **The zero-count text checks are spelling-dependent** (`== "*"`, `combat.gear`, `Migrations[`): `'*'`, a reversed
  compare or a local alias passes. Each file also has a positive check, so a missing file cannot pass vacuously.

**Verified, safe to reuse:**
- `Armory.luau` requires nothing, so `Unlocks -> Armory` is no cycle; both trees map `src/shared`; the harness,
  stage_mirror and `rojo` resolve it.
- `ProfileSchema.Run` is equivalent to the old while loop for nil/NaN/fraction/negative/ahead versions, and
  DataService's only caller (`DataService.luau:212`) runs after Reconcile, as before.
- RemoteEvent firing serializes, so the hub Delta's deep copy is defensive only; profiles have no cycles; cost is the
  old copy's.
- R9: no other code writes `GuiService.TouchControlsEnabled`; every close path (close, SetAvailable(false),
  teardown on `Destroying`) goes through `setOpen(false)`; one ArmoryScreen per place. ControlModule only toggles
  `TouchGui.Enabled` on that property (`ControlModule/init.lua:879-888`), it never destroys it.
- R10: no other client code sets `GuiService.SelectedObject`, so the deferred reselect cannot ping-pong.
- `mirror_mutants.py --only Armory`: 10 of 10 caught (2.5 min). `check_stage_mirror`, `check_levels` PASS.
  `sim_combat --check` 23/23 (~3 min); `sim_range --check --levels-only --level forest` PASS in ~20 min (157 PASS).
- luau-lsp needs the worktree's rokit.toml and Packages: run `rojo sourcemap` FROM the worktree with `-o` into
  scratch (writes nothing in the worktree), not from a git-archive copy.

**Recipes:**
- `scratchpad/l3fix/probe.py <probes.json>`: a list of `[label, file, old, new]`; applies each to a git-archive tree,
  runs the harness, restores, and prints CAUGHT/SURVIVES. Print with `errors="replace"` (the ★ in check text breaks
  cp1252 stdout).

See [[l2-secrets-review]] and [[review-workflow]].
