# L3 W1 review — slice 2, the combat place server

Reviewer: roblox-reviewer, 2026-10-20. Branch `l3-armory` at a2628da (build ff7a910, follow-up 64a6b12), worktree
`C:\Users\benja\Desktop\tycoon-p5`. Read only. The probes are in the session scratchpad (`s2probe/`).

**Count: 0 Critical, 1 Major, 2 Minor, 1 Suggestion.**

## Major

**M1. `tools/sim_range.py:7076` (with `:2203-2206`, `:2238`, `:5259`): the simulators read a held family at its slot's
gear tier. The game reads `Armory.TierOf(family)`, so the gated L2 pair rows measure weapons the game does not field.**

- **What is wrong.**
  - `level_view` builds `_scales` per slot from `gear[slot]`. The level player takes `hit_scale`, `slam_scale`,
    `cast_scale` and each pair kit's `scale` from those per-slot entries. `gear_max_hp` builds the bar from the same
    gear.
  - Since L3-6 the game does something else. `WeaponService.damageScale` (`WeaponService.luau:641-668`) and `gearOf`
    (`:610-635`) read each family's own `TierOf`.
  - For a non-starter that was never upgraded, `TierOf` is its window start (L3-3): the Flamethrower T2 and the Frost
    Hammer T5, whatever the starters are at.
  - Before L3 the game scaled by the slot too, so this mirror was exact. It drifted with this wave. L3-27's mirror
    table does not list it.
- **Failure scenario.**
  - Forest Road Normal, a fresh profile at the proving gear (T1/T1).
  - With the Flamethrower held, the game hits ×2.475 and the bar is 165. The sim uses ×1.5 and 155.
  - With the Frost Hammer held (lever I), the game hits ×11.118 and the bar is 290. The sim uses ×1.5 and 155.
  - Probe: `s2probe/pair_scale.py`. It runs the shipped sim against the same runs with TierOf per family. Only the
    damage scales were changed; the bigger bar was left out, which favours the sim.

  | Row | Gate | Sim as shipped | Game rule | Result in the game |
  |---|---|---|---|---|
  | Frost Hammer + Longbow (`check_cave_runs`, L2 W3) | clear | 4.43–4.69 min | 2.22–2.30 min | FAIL |
  | | cash/min | ×0.95 | ×1.83 (limit ≤ 1.10) | FAIL |
  | | Colossus | ×1.08 | 13.9 s against 76.4 s, ×0.18 (limit ≥ 0.90) | FAIL |
  | Broadsword + Flamethrower (L2 W2) | clear | 4.06–4.24 min | 3.93–4.04 min; seed 23 is under the 4.0 floor | FAIL |
  | | cash/min | ×1.02 | ×1.07 | PASS |
  | | Colossus | ×0.99 | ×0.96 | PASS |
  | The cave sniper's Dragon's Breath (R8, L2-37) | — | — | identical either way | — |

  - So `sim_range --check` stays green on gates that the game breaks. They pass for the wrong reason.
  - The Flamethrower is live-reachable: the lookout pays it on Forest Road.
- **Fix (designer, then the lead).**
  1. The level player takes each held family's tier the way the game does. Use
     `sc.held_tiers(armory, {"tiers": {melee_starter: gear["melee"], ranged_starter: gear["ranged"]}}, melee, ranged)`:
     starters at the gear's tier, non-starters at their window start. Apply it to the hit, pair-kit, slam and
     cast/breath scales, and to `gear_max_hp`.
  2. Add the row to L3-27's table.
  3. The lead then rules on the two pair gates:
     - the Frost Hammer is now a T5 Castle weapon, so re-band its Forest rows or retire them until the Castle;
     - the Flamethrower pair's 4.0-minute floor.
  4. One line to Ben: in Studio, I now puts a T5 weapon into the Forest, and the Colossus falls in about 14 s.

## Minor

**m1. The service lines that apply L3's rules are under no gate: the L2 pattern, a fourth time.**

- **What is wrong.**
  - The harness tests the pure parts: `TierOf`, `Upgrade`, `LoadoutOf`, `FirstClear`, and the `Validate` lines.
  - No harness file loads `WeaponService`, `UnlockService` or `WaveService`.
  - `run_harness.py` has no L3 source check, and `mutate.py` has no entry on any of these lines.
- **Failure scenario.** A scratch `git archive` copy took four mutants at once:

  | Mutant | Line | Effect in the game |
  |---|---|---|
  | `damageScale(player, "melee", false)` | `WeaponService.luau:2592` (the slam) | The pre-L3 call shape. "melee" is no family, so the slam stays T1 at every tier. |
  | `tier = 1` | `WeaponService.luau:660` | No upgrade reaches a hit; only the bar moves. |
  | `true` in place of `gate ~= nil and gate(player)` | `UnlockService.luau:243` | Upgrades in the middle of a fight. |
  | `local given = nil` | `WaveService.luau:1349` | No Warhammer ever. |

  - Result: `HARNESS: PASS (3,539 checks)`.
  - Two more break by construction:
    - Dropping the profile branch of `starsOf` (`WaveService.luau:449-454`) keeps stars in session memory. The map then
      shows the Hard star, but `combat.stars` is never written, so `needsStar` never opens T4.
    - `readLevel`'s two new `Validate` arguments (`:1663-1664`).
- **Fix.**
  - Add text checks in `run_harness.py` for these six lines, in the `source.w3` pattern, plus `mutate.py` entries for
    each.
  - Alternatively, move the tier resolution into a pure, tested `Armory.StrikeTier(cfg, combat, overrideGear, slot,
    family)` that `damageScale` and `gearOf` call. The call-site arguments would still need checks (the W1 lesson).

**m2. `WaveService.luau:2356-2369` (`GrantStars`, the U lever): a lever star swallows that difficulty's first-clear
reward.**

- **What is wrong.**
  - `GrantStars` awards the Hard star but not its reward.
  - `EndRun` gives the reward only for a **new** star (`:1345-1349`).
- **Failure scenario.**
  - U, then a Hard clear: the card shows no new star and no Warhammer.
  - The shelf still reads "First Hard clear of Forest Road".
  - On a real Studio profile (with API access), the Warhammer stays out of reach until L empties the stars.
  - The plan collides with this:
    - L3-33 says "the playtest opens with T, U and L".
    - Owner B's Studio list (step 4: clear Hard, the summary reports the Warhammer) and the contract's test both expect
      a Hard clear to pay the Warhammer.
- **Fix (pick one).**
  - `GrantStars` hands each new star's `StageFlow.FirstClear` to `UnlockService.GrantFirstClear`, so there is one
    rule: a new star gives its reward.
  - Or PLAYTEST presses U only after the Hard clear and says why (docs-keeper, from the lead).

## Suggestion

**s1. `WeaponService.luau:654-657` and `gearOf` `:614-616`: the Studio override's slot tier is not held inside the
striking family's window.**

- **What is wrong.** G (T1) with the Flamethrower or the Frost Hammer fields them below their windows: T1 against 2–8
  and 5–12, for the hits and for the bar. The Armory screen shows T2 / T5 meanwhile.
- **Why it is a Suggestion.** The contract words it this way (L3-6, "the Studio override's tier for that family's
  slot"), and it is Studio only.
- **Fix, if wanted.** Clamp the override tier into `Armory.Window(cfg, family)` in `damageScale`, and do the same per
  held family in `gearOf`. Then G can never field a weapon below its window.

## Checked and clean

- **`damageScale` callers.** Every caller passes the striking family:
  - melee and ranged resolve pass `weapon`;
  - `Strike` and `FireProjectile` pass `c.family`, the held slot's family at cast;
  - the slam passes the held melee family.

  Projectiles and split children keep the scale from when they were fired. Heavy, plate and armour are unchanged:
  `StrikeTally` carries the scale beside the unscaled amount.
- **`gearOf`.**
  - The order is: the range's 1/1, then the override, then the held pair.
  - Before `AddPlayer`, `LoadoutOf` falls back to the same starters `AddPlayer` uses, so the bar agrees before and
    after admission.
  - Nothing in `src` reads `provingGear` any more.
- **`RefreshMaxHp`.**
  - It runs on every change to a held tier: an upgrade, a family switch, `setTier`, `resetArmory`, `removeFamily` of a
    held family, G and `setGear`.
  - `GrantFirstClear` changes no held family.
  - The lobby has mission rules from `Init`, so the lobby bar is the held pair's.
- **The saved loadout at admit.** The order is: load, then `Admit`, then `AddPlayer`. It reads the loaded profile
  before the first `PrepareCharacter`, and its variants are copied.
- **`OnUpgradeWeapon`.**
  - The range is ignored. A player not admitted, with no profile, or with no config gets `unavailable`.
  - The family arrives as a short string (`Unlocks.MAX_FAMILY_LENGTH`) on the `calls` bucket.
  - Nothing yields between the `MayLeave` gate, the verdict and the write. `MayLeave` is false for any fighting member
    in a live phase.
  - A profile that was just released reads nil, because `DataService.Release` clears it first.
- **`OnSetFamily`.** It saves only after `FamilyVerdict` returns nil (which checks the family's own slot) and only if
  the hold succeeded.
- **`RemoveFamily` and `ResetArmory`.** They save, or empty the save, and put the starters back.
- **First clears.**
  - A reward follows only a new star, in each member's own profile; bots are skipped.
  - The Valor goes into the profile and onto the card before `SetResults` and `BroadcastSummary`.
  - `CreditSummary` is display only.
  - `FirstClear` returns a fresh table, and `resolveLevel` passes `difficulties` through, so `firstClear` survives.
  - Nothing in `EndRun`'s new lines yields: it is a Heartbeat path.
- **Stars.** One table, the profile's, serves the map, the start gate, the summary and `needsStar`. Bots keep the
  session table.
- **Levers.**
  - `OnRequest` and `Start` are gated on Studio.
  - `applyLever` is off in the range, and `SetGearOverride` works only in Studio.
  - `RequestDebug` refuses NaN and inf.
  - Only `DebugService` calls `SetTier`, `ResetArmory`, `GrantStars` and `ForgetStars`.
  - The T, U and L attribute paths are consumed and optional.
- **`StageFlow`.** `FirstClear` and the `firstClear` lines of `Validate`. The `sim_range` and `stage_mirror` copies
  match.
- **Config data.**
  - Forest Road recommends T1 / T3 / T5. Hard is `hpScale` 4.25 with `rewardMult` 2 (§12.8, §12.9).
  - The first clears are the Warhammer (Hard) and 25 Valor (Brutal). The arena recommends T1.
  - The presets are T1 / T3 / T5, and `provingGear` is T1 (the simulators only).
  - The three attribute keys are present, and every `found` text is 40 characters or fewer.
- **Gates.**
  - `check_compile` PASS (177 files).
  - stylua and selene are clean on `src/combat/server`.
  - luau-lsp on the combat tree is clean.
  - Harness PASS (3,539 checks).
