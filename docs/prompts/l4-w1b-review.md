# L4 W1b review — three slices (brief for three reviewers)

Worktree `C:\Users\benja\Desktop\tycoon-p5b`, branch `l4-w1b` (commit 1ae8bfb). The diff under review is
`git diff l4-real-forest...l4-w1b` (from the merge base 1d3b0d2) restricted to your slice. **Read only: change no file
except your own findings file.** Kill only your own PIDs. Tools: `py`; `export PATH="$HOME/.rokit/bin:$PATH"`; the Luau
CLI `C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe` (this worktree has none: pass it to the harness as the second
argument and to `check_stage_mirror.py` as `--luau`); the harness
`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5b C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`.
Scratch work goes in your own scratch folder, never in the repo.

## Read first

- `docs/prompts/l4-w1b-contract.md` (the contract of record, rulings L4B-1..9; §7 is the lead's worktree amendment) and
  `docs/prompts/l4-w1b-reports/lead-routing.md` (VitalsService to A; `Sounds.json` to the designer; the low-HP vignette's
  removal accepted). The designer also trimmed `tools/audio_map.json` (accepted).
- `CLAUDE.md` (code rules); the owners' reports in `docs/prompts/l4-w1b-reports/` for your slice.

## Every slice looks for

Correctness against the contract; **a deletion that left a live path dangling** (a require, a remote, a config key read
with no default, a type field still written or read, a Theme constant, a client branch waiting for a CombatFx kind that
no longer comes); behaviour that moved where the contract says nothing does (the range bench, the Forest Road run, the
lobby, abandon, the summary, the map); server authority (nothing a client sends opens i-frames or decides a hit); the
compile budget; `--!strict`, no `wait`/`spawn`/`delay`, no parent argument in `Instance.new`; tests and text checks that
pass for the wrong reason (vacuous: prove a few by a scratch mutant); retired tests whose rule still exists; mirrors that
drift.

## The slices

| Slice | Files | Focus |
|---|---|---|
| **1 Server and shared** | `src/combat/server/Services/` (`WeaponService`, `DashProof` new, `PositionRing`, `VitalsService`, `CombatRemotes`, `DebugService`, `StageFlow`, `LevelGeometry`, `LevelService`, `BarrierGroups`, `RunFx`, `Main.server`), `src/shared/` (`Combat`, `Armory`, `Catalog`, `Types`, `RunFloors` new), `tools/crowd_harness/tests_l4b.luau` | **The dash proof (L4B-7)**: a real dash on a 20 Hz bunched ring is proven in time for a hit decided at T + lag; a still or walking client never is; the window opens from the request; no path still opens i-frames on the request alone; claims cleared on reset, death, leave; nothing yields in Heartbeat. **`RunFloors` (L4B-8)** as pure shared code. Every deleted module's last reader really gone (grep the whole `src`) |
| **2 The run and the client** | `src/combat/server/Services/ArenaService.luau`, `WaveService.luau`, `tools/crowd_harness/tests_l4b_run.luau`; `src/combat/client/**` (`InputController`, `CombatUIController`, `CombatFxController`, `CameraController`, `WeaponController`, `CombatHud`, `DebugPanel`, `Main.client`), `src/client/UI/MapScreen.luau`, `Theme.luau` | **Cells once**: the first RunState of each seq to each member carries cells, a rejoin and a return to the lobby get them again, the client never loses a region (merge by index is safe?), `floorsSeq` missing reads 0; the bots' and `ready`'s removal changed no live member path (`player` no longer nil); the HUD and range input still work on PC, touch and gamepad (no stray binds, no dead buttons, abandon); the map shows no arena; every Theme constant deleted had no reader |
| **3 Data, simulators and gates** | `src/shared/Config/` (`Combat.json`, `Armory.json`, `Expeditions.json`, `ProvingGrounds.json`, `Sounds.json`, `Missions/`), `src/shared/Layouts/`, `tools/sim_combat.py`, `tools/sim_range.py`, `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/check_stage_mirror.py`, `tools/audio_map.json`, `tools/crowd_harness/` (`run_harness.py`, `mutate.py`, `stage_mirror.luau`, every changed `tests_*.luau`), `docs/BALANCE.md` | Each retired test's rule is really gone and each re-pointed fixture still exercises the rule it guarded (merge, breather, gateless locking camp); the dash in the simulator mirrors `DashProof`; no key a live reader needs was removed (grep `src` for every removed key); the hub stub `1_Village.json` still serves the hub's Expeditions panel and Depart (read `src/client/UI/ExpeditionPanel.luau`, `src/server/Services/ExpeditionService.luau`); `audio_map.json` and `Sounds.json` agree; the R8 row unchanged |

## Output

Write `docs/prompts/l4-w1b-review/<slice>.md` (`1-server.md`, `2-run-client.md`, `3-data.md`), LF. Each finding:
**Critical / Major / Minor**, file:line, what is wrong, a concrete failure scenario, and the suggested fix. One line each
for what you checked and found clean. End your reply with the count by severity and the file path.
