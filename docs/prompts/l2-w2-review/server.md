# L2 W2 review: server slice (main..l2-w2, 0f78d30, 2026-10-18)

Reviewer: roblox-reviewer (server). Files: `src/shared/{Types,Unlocks,WorldReact,Tuning}.luau`; `src/combat/server/Services/{CombatRemotes,UnlockService,SecretFlow,WeaponService,AbilityService,LevelService,LevelGeometry,StageFlow,WaveService,DebugService}.luau`; `src/combat/server/Main.server.luau`.

Gates run on a `git archive HEAD` copy in the scratchpad: harness PASS (2,758 checks), `check_stage_mirror` PASS, `check_compile` PASS (172 files).

**Result: 0 Critical, 0 Major, 3 Minor.**

## Minor

**m1. The lines that decide "only fire burns" are not under any gate.**
- Where: `LevelService.luau:613` and `:631` (`Unlocks.ElementOf(config.weapons, weapon)` and `entry.react ~= element`), plus the wiring line `Main.server.luau:255`.
- What: WorldReact's geometry is tested and mutated well. The service lines that apply it are not, and the harness cannot load LevelService, WeaponService or Main. No file under `tools/` mentions `OnStrikeResolved`, `LevelService.React` or the element lookup.
- Failure scenario: an edit makes `element` a constant `"fire"`, or drops `entry.react ~= element`. Every Longbow arrow (a `ray` strike) then burns the brambles. A dropped wiring line means nothing ever burns. Harness, mutate, check_levels and sim_range all stay green either way. This is W1's pattern of verdict-acting service lines left unharnessed.
- Fix: move the loop body into a pure `WorldReact.Apply(entries, element, fx, pad, need) -> (gone, heated)`. Mutate its element test. Add a source check that `Main` wires `OnStrikeResolved(LevelService.React)` and that `finish` calls the listeners only when `not fx.abandoned`.

**m2. Nothing in React refuses ability strikes. Only the strike's shape keeps Dragon's Breath from burning.**
- Where: `LevelService.luau:606` (`_ability` unused) and `WeaponService.luau:2679`.
- What: L2-34 says Dragon's Breath does not burn brambles. Today that holds only because `launchSlugBurst` fires cones and `WorldReact.Segment` ignores cones. `WeaponService.Strike` builds ability capsules from `spec.endPoint or origin + heading × size`, with no `worldReach` cut.
- Failure scenario: a later fire or ice ability uses a capsule (the W3 hammer family gets an ability too). It would heat a bramble straight through the ridge walls and roof, because ability capsules ignore walls.
- Fix: in `LevelService.React`, return early when `_ability ~= nil`, matching the contract's rule. Add a harness case once m1's pure function exists.

**m3. Validate and the runtime read a bad shortcut size differently.**
- Where: `StageFlow.luau:973` and `SecretFlow.luau:241`.
- What: Validate accepts any finite `sx/sy/sz`, including 0 and negatives. `SecretFlow.Shortcuts` silently drops a negative size, and a size of 0 can never contain a root.
- Failure scenario: a typo such as `"sz": -10` passes Validate, check_stage_mirror and the build. The tunnel then can never be "found" and the leader's later runs keep the brambles, and nothing warns. This is W1's "two rules for one config entry" pattern.
- Fix: Validate refuses `sx`, `sy` or `sz` ≤ 0, mirrored in sim_range's Validate. Add a mutant.

## Checked and sound (no finding)

- **RequestSetFamily.** The validator takes exactly three arguments: slot ∈ {melee, ranged}, a family of 1–24 bytes and a variant of 1–8 bytes. It is in the `calls` bucket, ignored in the range in both Main and UnlockService, and the client sends no amounts.
  - The verdict order matches the contract: unavailable, then invalid (unknown family, a family that fills the other slot, unknown variant), then locked, then busy.
  - `busy` is `WaveService.MayLeave`: false for any member who is fighting in a live phase, true in the lobby, at the summary and while waiting in the lobby camp.
  - No other mission path changes a slot's family. `RequestRangeCommand` stays range- and Studio-only. `OnAttack` refuses a family the slot does not hold (`WeaponService.luau:2245`). The starters match `startingFamily`.
- **Keys come from ownership, not from the weapon carried.** `Unlocks.HoldsKey` checks owned abilities first, then `HasElement` over the profile's families and the starters. A word that is not an element fails closed. `tickSecrets` re-tests a `locked` chest through the same rule, so in one run lookout → Flamethrower → cache pays.
- **The cache pays once per owner.** `SecretFlow.Open` records `secrets[levelId].cache` and pays only when the verdict is `pay`. Each owner in a party is paid once from their own profile. A guest without fire sees the private "locked" card, even when the tunnel stands open.
- **The strike hook.**
  - Every resolved strike reaches `finish()`: swings, ranged shots, projectile hits, ability strikes and the slam.
  - Burning works only when a family's structural `element` matches and the shape is a segment. Today that means only the Flamethrower's capsule. Its reach is cut by `worldReach` (`RespectCanCollide`), and since a bramble collides, the segment ends on its face.
  - The slam (`weapon = "slam"`), Longbow rays and Dragon's Breath cones do not burn.
  - Abandoned end strikes are skipped. The listener runs under `pcall` and warns once.
  - React, its OnReacted chain and `RunFx.Push` never yield. React is safe from the Heartbeat timelines and from the remote threads.
- **The per-run reactive list.** `Build` makes a fresh list. A failed construct clears it. `Clear` (run end, before every Build, and a start that threw) empties it. Heat never carries over between runs. A destroyed Part leaves the list before it is destroyed.
- **The shortcut.**
  - A find needs a standing, fighting human in a live phase, checked every Heartbeat. The trigger box exactly fills the 12-wide exit mouth (x −86..−74), so any exit or entry passes through it.
  - Each find is recorded once per run per player, and `ForgetSecrets` clears it.
  - `startLevel` passes `FoundShortcuts` only after its `notLeader` check, and the proving auto-start passes the leader too. A level is built once per run, so a leader leaving mid-run changes nothing, and the next run reads the new leader's save.
  - A guest's find records only on the guest's own profile.
  - `Pieces` measures a clone, so `BlockBoxes` deepening never sees the dropped brambles. No ground block in the cave is thin enough to be deepened.
- **Levers.** `applyLever` returns in the range, and RequestDebug refuses outside Studio. `RemoveFamily` puts a held family back on the starter. Starters cannot be granted or removed.
- **Profile v7.** `shortcuts` is already in the template and in the migration fill, so W2 needs no schema step.
