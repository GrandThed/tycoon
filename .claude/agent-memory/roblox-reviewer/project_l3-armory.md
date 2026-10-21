---
name: l3-armory-review
description: L3 "the Armory" reviews (tiers per weapon family, profile v8 with a one-time refund, saved loadout, stars saved, the Armory screen) - W1 slice 1 saving 2026-10-20 0C/0M/6m (harness proves a COPY of the migration runner; validator rules shadowed by a second rule; Hard-only trophy; old servers after publish); W1 slice 2 combat server 0C/1M/2m/1s (per-family TierOf vs per-slot sim mirror, unharnessed service lines, a star lever eats a first-clear reward); W1 slice 3 hub + hosts 0C/0M/2m/5s (hub service lines under no gate; a full-screen card covers earlier same-ZIndex siblings like the party invite); W1 slice 4 screen 0C/0M/3m/7s (hub modal vs Roblox TouchGui at equal DisplayOrder; pad selection restored only on repaint; style-button pending gate unharnessed); W1 fix diff 0C/0M/2m/5s (text checks pin a call, not where its arguments come from or whether it is reached; a sibling lever in the other place keeps the bug the ruling fixed); W2 slice 1 pipeline 2026-10-21 0C/0M/3m/4s (manifest stale after an upload commit; turn proof blind to a rotated MeshPart; clients trust the template PrimaryPart Ref; harvest inner pivot = glTF origin on all axes; py shebang picks 3.12; W2 slice 2 server 2026-10-21 0C/0M/5m/4s (T8 per-function misses slotFamily/variantFor; reach of the character hook unpinned; word-level structure checks; lobby act gate freezes WeaponHeld; melee draws flip the look at 40/s); W2 slice 3 client 2026-10-21 0C/0M/3m/7s (cast fx broadcast before the WeaponHeld write: one-shot builders draw from the other slot's weapon; black silhouette on a navy card maxes at 1.26:1; teardown and driving signals unpinned; R15 attachment frames read from local morpherEditorR15.rbxmx); W2 fix diff 2026-10-21 0C/0M/3m/3s (a task.defer coalesce runs the hold listener after another player's SwingOther and cancels the first swing after a switch; a stick added to a modal also drives the world camera; pins miss Muzzle's flush order and the rig constructor flags))
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

## W2 slice 1, pipeline and data (2026-10-21, c79bec5 on `l3-w2`): 0 Critical, 0 Major, 3 Minor, 4 Suggestions

Brief: `docs/prompts/l3-w2-review.md` (three slices). Findings: `docs/prompts/l3-w2-review/1-pipeline.md`. The weapons
take the props route (`props.Weapons`, `templates/_props/Weapons`), and the icons are a v5 top-level `icons` block.

**Patterns:**
- **A pipeline-state doc that a gate diffs goes stale when an upload commit skips it.** The `ASSET_MANIFEST` Weapons
  table has uploaded and harvested columns. The lead committed `Assets.json` after the uploads without
  `gen_asset_manifest.py`, so `--check` is red on the branch until the post-harvest step.
  - Run `gen_asset_manifest.py --check` at every review, not only after a harvest.
- **A "turn proof" can only prove translation.** `weapon_frames.weapon_proof` reduces to
  `offset == (-cx, cy, -cz)` plus a size check per axis. A MeshPart that Studio reports `rotated` is only warned
  about in `merge_model` (`harvest.py:354`), and the flag is never stored, so the proof passes on it (probed).
- **The clients trust the template `PrimaryPart` Ref.** HeldWeapons and ArmoryStage do, while PlotService and
  PropFactory find `Base` by name (the M7 lesson). Grep every new template consumer for `.PrimaryPart`.

**Verified, safe to reuse:**
- The harvest's inner-model pivot is the glTF origin on all three axes. Evidence:
  - Valley `Clouds_1` offset y is 350.9 against size/2 of 94.8.
  - Village `BushA` has min y −0.2, and its harvested y 0.5208 equals the centre y.
  - Boomtown `LampPost` z −0.788 harvests as +0.7875.
- `assets_config.render_assets` round-trips the real `Assets.json` byte for byte. All six writers go through
  `cfg.save_assets`, and every version bump is a `max()`.
- `py` picks its interpreter from the shebang. A script that starts with `#!/usr/bin/env python` runs 3.12 64-bit,
  which has no Pillow; without one it runs 3.14 32-bit. Most `tools/*.py` have that shebang. This is also the
  32/64-bit drift noted in [[l1c-chief-clearing-review]].

**Recipes (all on scratch, never the real `Assets.json`):**
- **Post-paste chain with the real ids.** Rewrite the asset ids in `tools/assets/fixtures/harvest_weapons_sample.txt`
  to the real ones from `Assets.json`. Then run, all against scratch copies:
  1. `harvest.py --props --file <copy> --assets-json <scratch>`;
  2. `weapon_frames.py --check --require-harvest --assets-json <scratch>`;
  3. `gen_templates.py --props` and then `--check`, both with `--assets-json` and `--out <copy of templates>`.

  This reproduces MANUAL_STEPS steps 8 to 10 exactly.
- **Run `harvest.luau` under `luau.exe`.** Prepend about 70 lines of stubs: `game:GetService` for InsertService and
  HttpService, Vector3 with `__sub` and Magnitude, and instance tables with `IsA` and `GetDescendants`. Then add the
  script from `local ASSETS = {` on. A stubbed run proves that each record kind prints a line `harvest.py` parses.
  Large Bash heredocs with backticks failed here, so use the Write tool and then `sed -i 's/\r$//'`.

## W2 slice 2, server and shared (2026-10-21, c79bec5 on `l3-w2`): 0 Critical, 0 Major, 5 Minor, 4 Suggestions

Findings: `docs/prompts/l3-w2-review/2-server.md`. The code under review: WeaponLook (pure), plus the
`WeaponMelee`/`WeaponRanged`/`WeaponHeld` character attributes. They are written only by WeaponService's
`showWeapons`, from PrepareCharacter, SetFamily and `noteHeld`, and `noteHeld` runs on an accepted attack, draw or
cast. The server code was right. Every finding was about a gate or the docs.

**Patterns:**
- **A "no hit reads X" rule checked per named function leaves out the functions that pick the family, the variant
  and the slot.**
  - T8 covered 7 functions. Two mutants put a `.held` read into `slotFamily` and into `variantFor`, and both
    survive.
  - Ask for a file-wide count of the field's reads, plus a count of 0 in the other files.
- **"Reached" pinned as call text only.** These four all survive:
  - the hook line wrapped in an `if` (the count is file-wide, with no indentation);
  - ArenaService's `hook(player, character)` deleted. This breaks every mission respawn, the vitals included;
  - RangeService's respawn handler emptied;
  - AddPlayer's mode test flipped.

  Exact text that includes its tabs does catch a wrapping `if`.
- **Word-level structure checks:**
  - "the call is inside the branch" still passes with an inner `if false`;
  - "behind `not Theme.lowEndDevice`" still passes with `if true or not …`;
  - "seal sets five properties" still passes when a later line turns one back on.

  Pin whole lines with their indentation, and add a file-wide 0 count for re-enables.
- **An act gate makes "others see it at the next attack" mean "never" in the lobby.** In the dungeon lobby
  (`ArenaService.InRun()` false), every attack, draw and cast is refused. So a teammate's `WeaponHeld`, and the
  raised ranged arm with it, stay frozen at their last in-run slot. Check where each "shows at the next action" rule
  can actually act.
- **A remote that once carried nothing now drives a replicated look.** `RequestRangeDraw` accepts a melee family
  (only the Longbow has a charge variant). Alternating two draws flips `WeaponHeld` 40 times a second, inside the
  `rangeAttack` bucket. When a cheap intent starts writing a replicated attribute, check the intent's own rate and
  what it accepts.

**Verified, safe to reuse:**
- No server code reads character attributes (only `EnemyId`), and nothing on the server listens to attribute
  changes.
- Neither `held` (server) nor `rangeState.activeSlot` (client, written only by `setActiveSlot`) resets on a respawn.
- Every family change in the combat place goes through `WeaponService.SetFamily`:
  - the lobby equip;
  - `removeFamily` and `resetArmory`, via `holdStarter`;
  - the range's `weapon` command.

  `grantFamily` changes ownership only.
- Mutate's `FILES` covers every file that `L3W2_*` and `SOURCES` read. Check it by exec-ing `mutate.py` up to
  `MUTATIONS.update(L3W2_MUTATIONS)` with a fake argv.

**Recipes:**
- Use `scratchpad/l3w2s2/probe.py <probes.json>`. Each probe is `[label, [[file, old, new], ...]]`, so a probe can
  make several edits.
  - It applies each probe to a `git archive HEAD` copy and runs that copy's own `run_harness.py`, so `bundle.luau`
    lands in scratch, not in the worktree.
  - Each probe takes about 12 s.
  - Build the JSON with a small Python script, not by hand-escaping.
- To run `check_compile` on the copy, copy `luau-compile.exe` into `tree/tools/bin` first.
- luau-lsp: run `rojo sourcemap <project> -o <scratch>` from the worktree. Then run `luau-lsp analyze
  --sourcemap=<scratch> --definitions=tools/types/globalTypes.d.luau <files>`, without `--settings`: the worktree has
  no `.vscode`.

## W2 slice 3, the client (2026-10-21, c79bec5 on `l3-w2`): 0 Critical, 0 Major, 3 Minor, 7 Suggestions

Findings: `docs/prompts/l3-w2-review/3-client.md`. The code under review:
- HeldWeapons: welds from RightGripAttachment and BodyBackAttachment, `Muzzle`, `OnHold`;
- the rest poses in WeaponController (a raised ranged arm);
- the four muzzle copies folded into one;
- the ArmoryStage ViewportFrame and the shelf icons.

**Patterns:**
- **A remote event broadcast before the attribute that describes it.**
  - In `AbilityService.OnCast`, `broadcastFx(cast)` and `mechanic.launch` (instant strikes and shots) both run before
    `NoteHeld` writes `WeaponHeld`.
  - Under deferred signals the attribute's value is already set, but the AttributeChanged handler that updates the
    client's cache (`rig.inHand`) is queued after the remote handlers.
  - So builders that read once (Volley, StormCoil, BladeStorm, the blend in `onShot`) draw from the other slot's
    weapon.
  - For every new display attribute, list each broadcast that a client builds from it, and check it comes after the
    write.
- **A near-black silhouette on a dark card cannot reach the sample's contrast.**
  - On (22, 29, 50) it gives 1.14. Even pure black gives only 1.26. The approved sample sat on (30, 41, 70) at 1.32.
  - Compute the WCAG luminance against the shipped backdrop, not the sample's.
- **Text checks pin creation, not teardown or the signals that drive it.** Each of these survives alone:
  - `stop()` dropped from `SetActive(false)`;
  - `clear()` dropped from `selectFamily`;
  - the loadout-leave `Destroy` dropped;
  - `names.held` dropped from the watched names.
- **One server write of N attributes runs a client handler N times.** It needs coalescing (`task.defer` plus a
  flag), as the old RefreshCosmetics did. This matters more when slice 2's 40/s `WeaponHeld` flip is possible.

**Verified, safe to reuse:**
- **R15 attachment frames** come from `%LOCALAPPDATA%\Roblox\Versions\<v>\content\avatar\morpherEditorR15.rbxmx`. It
  is XML, so a regex reads it.
  - `RightGripAttachment` is at (0, −0.147, 0) with rows (1,0,0), (0,0,1), (0,−1,0). Its look runs down the arm, and
    its up is the hand's forward.
  - `BodyBackAttachment` is the identity at (0, −0.196, 0.5), with +Z out of the back.
  - The shoulder rig attachments are the identity. So `C0 * Rx(+θ)` raises an R15 arm forward.
  - R6's `Right Shoulder` C0 carries a 90° Y turn, so its X is the forward axis. The same pose there raises the arm
    sideways.
- **The combat place has `StreamingEnabled` false**, so remote characters arrive whole.
- **Downs keep `DOWN_HEALTH`** (VitalsService), so `Humanoid.Died` never fires for a down.
- **`WeaponService.finish` broadcasts every strike**, whiffs included.
- **`AbilityFx/init.onCast` builds on receipt.**
- **Only WeaponController writes a shoulder C0.**

**Recipes:**
- Mutants: `scratchpad/l3w2c/probe.py <tree> <luau> <probes.json>`, where each probe is `[label, file, old, new]`,
  run on a `git archive HEAD src tools combat.project.json default.project.json` copy. Each one takes about 11 s.
- Under this Git Bash, `grep -c $'\r'` counts every line. Count CR bytes with `py` instead. The Write tool wrote LF
  here.
- A long `cat <<'EOF'` heredoc failed with "unexpected EOF while looking for matching `''". Use Write for findings
  files.

## W2 fix diff (2026-10-21, `git diff 5c0958b 31b1947`): 0 Critical, 0 Major, 3 Minor, 3 Suggestions

Findings: `docs/prompts/l3-w2-fix-diff-review.md`. All 17 rulings (P1-P6, S1-S6, C1-C5) are done.

**Patterns:**
- **Coalescing an attribute handler (`task.defer` plus a pending flag) reorders it behind remote handlers queued
  in the same batch.**
  - The ui-engineer added a flush in `Muzzle` for the effects, but `FeedbackController.onStrike` calls
    `WeaponController.SwingOther` without `Muzzle`.
  - So the deferred show and its hold listener's `setRest` run after the swing has started. `setRest` raises
    `rig.token` and cancels the windup.
  - Result: another player's first swing after a ranged-to-melee switch never animates.
  - When a handler is deferred, list every remote handler that reads the state the handler sets, not only the ones
    the fix had in mind.
- **A feature that adds an input to a modal must check who else reads that input.**
  - C3 made the right stick turn the Armory stage.
  - The combat `CameraController` reads `Thumbstick2` from UIS with no `processed` or modal gate, and nothing in the
    hub sinks it for the PlayerModule camera.
  - So the world camera, and the character, swing behind the 0.35 scrim.
- **The same recurring pattern: pins hold call text, not order or constructor inputs.**
  - These survive: `Muzzle` reading `rig.inHand` above its pinned flush, and `bound = false` or `pending = true` in
    `bind`'s rig.
  - The stick's four lines and the ghost tone's value are also unpinned.

**Verified, safe to reuse:**
- The 15 icon `sha256` values are pixel hashes.
- Kenney kit folders carry `License.txt` and generated ones do not: `tower-kit` is generated (`tower_kit.py`).
- Every family's variant `kind` matches its slot, so only bows reach `startDraw`.
- `castAbility` calls `setActiveSlot` on the press.
- The combat `CameraController` handles `Thumbstick2` `InputEnded` (`:874`) as rest.
- While this review ran, a QA run in `tycoon-p5` modified `build/*.rbxl` and the sourcemaps. That was not the
  reviewer.

**Recipes:**
- `scratchpad/l3w2fd/probe.py probes.json` on `scratchpad/l3w2fd/tree`, a `git archive <sha>` copy. A probe is
  `[label, [[file, old, new], ...]]`, takes about 14 s, and `mkprobes.py` builds the JSON.
- `ghost.py <icons256 dir>` (`py`, Pillow) recomputes the shelf icon contrast.
- `icon_hash.py <repo>` checks the recorded icon hashes against `pixel_sha256`.

See [[l2-secrets-review]] and [[review-workflow]].
