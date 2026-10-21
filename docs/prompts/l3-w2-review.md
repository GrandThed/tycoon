# L3 Wave 2 review — three slices (brief for three reviewers)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l3-w2`. The diff under review is `git diff main...l3-w2` (from
0fb03be) restricted to your slice. **Read only: change no file except your own findings file.** Kill only your own PIDs.
**Never run an upload, the real harvest, or a `--dry-run` against the real `src/shared/Config/Assets.json`**: the 15
models and 15 icons are already uploaded (084a14f, d1c2f59) and Ben's paste is pending; work on scratch copies. Tools:
`py`; `export PATH="$HOME/.rokit/bin:$PATH"`; the harness
`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5 C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`.

## Read first

- `docs/prompts/l3-w2-contract.md` (the contract of record; **§11 is the lead's rulings and overrides the text above it**:
  icons 256 px, `Stage0` for everyone, rest poses with `COMBAT_HOLD_GRIP_MELEE` / `_RANGED` and the raised ranged arm,
  the back hold turned 90°, T9 counted before the call).
- `CLAUDE.md` (code rules); the owners' reports in `docs/prompts/l3-w2-reports/` for your slice.

## Every slice looks for

Correctness against the contract; anything a hit, a balance or a level reads that moved (the contract says nothing does);
server authority (only the server writes the weapon attributes; nothing a client sends decides them); data safety (the
`Assets.json` v5 block survives every tool's save; nothing erases the props); missing assets degrade, never error; leaks
(connections, clones, weak caches on character removal, player leave, respawn); no per-frame work where the contract
forbids it; the compile budget; `--!strict`, no `wait`/`spawn`/`delay`, no parent argument in `Instance.new`, constants
in config or Theme; tests and text checks that pass for the wrong reason (vacuous); mirrors that drift.

## The slices

| Slice | Files | Focus |
|---|---|---|
| **1 Pipeline and data** | `tools/assets/weapon_frames.py`, `upload_icons.py`, `assets_config.py`, `harvest.py`, `gen_templates.py`, `upload_models.py`, `tools/assets/fixtures/*`, `tools/gen_asset_manifest.py`, `src/shared/Config/WeaponModels.json`, `src/shared/Config/Assets.json` (the 15 props, the v5 `icons`), `tools/assets/harvest.luau`, `docs/MANUAL_STEPS.md` "L3 W2", `tools/testfit/README.md` | The identity transform and "the pivot is the grip" (L3-47) against `gen_templates` and `harvest` as written; the turn proof can fail; `Assets.json` round-trips and no older save path drops `icons`; the harvest script's Luau (the Decal branch for `icon`, the 30 records) will run in Studio's Command Bar; idempotency and hashes; the 50-character names; the manifest; every MANUAL_STEPS command and flag is right |
| **2 Server and shared** | `src/shared/WeaponLook.luau`, `Types.luau`, `Catalog.luau`; `src/combat/server/Services/WeaponService.luau`, `AbilityService.luau`; `tools/crowd_harness/tests_l3_w2.luau`, `run_harness.py`, `mutate.py` | The attributes on every path (fresh character, respawn, family change in lobby and by lever, range, attack, draw, cast); nothing in a hit-deciding function; `WeaponLook`'s refusals; every text check pins its inputs and that it is reached (prove a few by a scratch mutant) |
| **3 The client** | `src/combat/client/Controllers/HeldWeapons.luau`, `WeaponController.luau`, `FeedbackController.luau`, `FlameFx.luau`, `AbilityFx/Shared.luau`, `AbilityFx/MagDump.luau`, `CombatUIController.luau`; `src/client/UI/ArmoryStage.luau`, `ArmoryShelf.luau`, `ArmoryScreen.luau`, `Theme.luau` | Decoration only (seal: no collide, query, touch, mass); the shot and melee origins untouched (`InputController.luau` unchanged); the one muzzle helper's fallback; attachment lookup only on direct children; the rest poses and the raised ranged arm on local and remote rigs (respawn, a swing after a switch, release, kicks), no per-frame work in HeldWeapons; the ViewportFrame's lifetime (one clone, destroyed on change and close, the turn connection only while active and never on `lowEndDevice`, drag); the shelf icons fit L3-23's sizes; W1 look with no templates and no icons |

## Output

Write `docs/prompts/l3-w2-review/<slice>.md` (`1-pipeline.md`, `2-server.md`, `3-client.md`), LF. Each finding:
**Critical / Major / Minor**, file:line, what is wrong, a concrete failure scenario, and the suggested fix. One line each
for what you checked and found clean. End your reply with the count by severity and the file path.
