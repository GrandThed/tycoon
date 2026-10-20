# L3 Wave 1 review — four slices (brief for four reviewers)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-armory`. The diff under review is `git diff main...l3-armory`
restricted to your slice's files (W1's build commit is ff7a910, its follow-up 64a6b12; earlier commits on the branch are
docs and the weapon kit, out of scope). **Read only: change no file except your own findings file.** Kill only your own
PIDs. Tools: `py`; `export PATH="$HOME/.rokit/bin:$PATH"`; the Luau CLI is
`C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`; the harness is
`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`.
You may run any gate or a scratch Luau/Python script (in your own scratchpad folder) to prove a finding.

## Read first

- `docs/prompts/l3-w1-contract.md` (the contract of record; **§12 is the lead's rulings and overrides the text above it**:
  `provingGear` out of `gearOf`; Hard is ×2, data only; R8 on Hard is a known limit until L4; Combat.luau type copies).
- `CLAUDE.md` (code rules), `docs/MISSIONS_DESIGN.md` §10 and §24 (Ben's decisions).
- The owners' reports in `docs/prompts/l3-w1-reports/` for your slice.

## What to look for (every slice)

Correctness against the contract and Ben's decisions; server authority (the client sends intents only, every remote
validated and rate-limited, no client-decided tier, cost or state); exploit surface (spam, races between the verdict and
the write, a yield in between, a double spend, a mid-fight change, a forged family or style); data safety (the v7 → v8
migration exactly once, no aliasing of template tables, nothing lost on old or new code, the frozen `gear`); Studio-only
levers inert in the live game; the 180-local compile budget; `--!strict`, no `wait`/`spawn`/`delay`, no parent argument
in `Instance.new`, constants only in config; mirrors that drift from what they mirror; tests that pass for the wrong
reason (a vacuous check).

## The slices

| Slice | Files | Focus |
|---|---|---|
| **1 Saving and the shared rules** | `src/shared/Armory.luau`, `Unlocks.luau`, `Types.luau`, `Combat.luau`; `src/server/Services/ProfileSchema.luau`; `src/shared/Config/Armory.json`; `tools/crowd_harness/tests_l3.luau`, `tests_l2.luau`, `stage_mirror.luau`, `tools/check_stage_mirror.py`; the Armory mirror in `tools/sim_combat.py` | The refund and the step running once (through `DataService`'s runner), a v8 profile on v7 and v6 code, `TierOf` clamps, `UpgradeVerdict`'s order, `Upgrade`'s write, the ladder and HP numbers against L3-1/L3-2, the legacy price list, `LoadoutOf` fallbacks |
| **2 The combat place server** | `src/combat/server/Services/WeaponService.luau`, `UnlockService.luau`, `WaveService.luau`, `StageFlow.luau`, `VitalsService.luau`, `DebugService.luau`, `CombatRemotes.luau`; `src/combat/server/Main.server.luau`; `Config/Levels/1_ForestRoad.json`, `0_RaiderArena.json`, `Config/Combat.json` (`debug`), `Config/Expeditions.json`; `tools/crowd_harness/tests_l3_run.luau` | `damageScale` by the striking family (every caller), `gearOf` and the bar (`RefreshMaxHp` on every change), the saved loadout at admit, upgrade validation and rate limits, first clears (once, to the right player, Valor credited before the summary), stars from the profile, the levers, heavy/plate/armour still unscaled |
| **3 The hub and the client hosts** | `src/server/Services/ArmoryService.luau`, `EconomyService.luau`, `HubRemotes.luau`; `src/client/Controllers/UIController.luau`, `src/client/UI/DebugPanel.luau`, `MapScreen.luau`; `src/combat/client/Controllers/CombatUIController.luau`, `src/combat/client/UI/DebugPanel.luau`, `SummaryCard.luau`; `combat.project.json` | The hub's handlers against the combat place's (one rule), `copyCombatProfile`, Power, the hub's readiness key (nothing it showed before is hidden), K and the bottom-bar key, the Delta path, results routed, levers gated on Studio, the deleted panels leave no reader |
| **4 The screen** | the seven `src/client/UI/Armory*.luau`, `src/client/UI/Theme.luau` (the diff), `tools/crowd_harness/tests_l3_ui.luau` | Layout A and the full-ladder track against L3-19/L3-20, the fit at 682 × 313, 712 × 330 and 375 × 667 (touch minimum 44 physical px), buttons that never decide (`ArmoryModel` matches the shared rules), pending presses, gamepad (A sunk, selection confined, B/LB/RB), no sound, `lowEndDevice` not `reducedMotion`, cleanup on close and destroy, what each place may require (both trees) |

The data and simulator files (`tools/sim_range.py`, `tools/check_levels.py`, `check_levels_mutants.py`, `docs/BALANCE.md`)
are read by slice 1 (the Armory mirror) and slice 2 (the level data) only where they mirror your code.

## Output

Write `docs/prompts/l3-w1-review/<slice>.md` (`1-saving.md`, `2-combat-server.md`, `3-hub-hosts.md`, `4-screen.md`), LF.
Each finding: **Critical / Major / Minor**, file:line, what is wrong, a concrete failure scenario (inputs or state →
wrong result), and the fix you suggest. Say what you checked and found clean, in one line each. End your reply with the
count by severity and the file path.
