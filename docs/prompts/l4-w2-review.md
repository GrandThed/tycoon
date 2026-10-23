# L4 W2 review — four slices (brief for four reviewers)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l4-w2`. The diff under review is `git diff 37ccfe4..<the wave's
commit, named in your prompt>` (37ccfe4 is `l4-real-forest` with W1b merged) restricted to your slice. **Read only: change
no file except your own findings file.** Kill only your own PIDs; scratch work in your own scratch folder (a `git archive`
copy for probes); never run `mutate.py` or an asset tool in a worktree. Tools: `py` (`py -3.12` for `sim_range.py` and
`check_levels*`); `export PATH="$HOME/.rokit/bin:$PATH"`; Luau CLI `C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`;
the harness `py tools/crowd_harness/run_harness.py <root> <luau>`.

## Read first

- `docs/prompts/l4-w2-contract.md` (rulings L4W2-1..15; **§0 is the lead's amendments and overrides the rest**) and
  `docs/prompts/l4-w2-kickoff.md` (what changed since the draft: the assets are harvested; the mountain and the Castle Key).
- MISSIONS_DESIGN §26-§28 and the notes after them (R8 judged against the same gear, as built).
- The owners' reports in `docs/prompts/l4-w2-code-reports/` for your slice (`luau-a.md`, `ui-a.md`, `ui-b.md`, `d1.md`,
  `d2.md`); the lead accepted luau-a's decisions 1-7, ui-a's prop-set map in Theme, ui-b's assumptions.
- `CLAUDE.md` (code rules; the 180-locals compile gate).

## Every slice looks for

Correctness against the contract; **missing assets degrade, never error** (no template, a bad dress, a kind without a model:
grey level or placeholder, one warn); server authority (the client dresses only on the server's word; nothing a client sends
decides a hit, a dress or a key); leaks (clones, connections, pools on level change, run end, respawn, leave, a late join);
per-frame cost on a phone (`Theme.lowEndDevice`, never `reducedMotion`); hit shapes that disagree with what is drawn (the
seated head, the windup lean, the Chief's reach); `--!strict`, no `wait`/`spawn`/`delay`, no parent argument in
`Instance.new`, constants in config or Theme; tests and pins that pass for the wrong reason (vacuous: prove a few by a
scratch mutant); mirrors that drift.

## The slices

| Slice | Files | Focus |
|---|---|---|
| **1 Server and shared** | `src/combat/server/Services/` (`LevelDress` new, `LevelService`, `WaveService`, `ArenaService`, `StageFlow`, `CrowdService`, `WeaponService`, `DebugService`, `SecretFlow`), `src/shared/` (`Types`, `Catalog`, `HitShapes`, `Unlocks`, `Tuning`), `tools/crowd_harness/tests_l4w2.luau` | `Accept`'s refusals and the all-or-nothing grey fallback (a wall left collidable with no skin; a hidden Part with no mesh over it); the walls collide for characters only (rays and the camera pass); `Dress`/`DressHash` set last and cleared first; the seat stepped on the server exactly as the client steps it, and every hit-deciding path lowers the head by the drop (strikes, abilities, auto-aim); `Plan.kinds` and `prewarm` sent once with the cells; the Castle Key: a chest that gives only a key pays, the key is the opened secret, `HasLevelKey` reads the level files; the `dressFail` lever is Studio-only |
| **2 The scenery client** | `src/combat/client/Controllers/LevelScenery.luau` (new), `DrawClock.luau` (new), `SecretFx.luau`, `src/combat/client/Main.client.luau`, `src/combat/client/UI/CombatHud.luau`, `src/client/UI/MapScreen.luau` | Builds only on the server's word with the same hash; the per-frame clone budget; the generation counter; the undo when a clone fails (no collision left invisible); mood B records and restores exactly what it wrote (and only its own Atmosphere), never in the lobby or the hub; Y/O/Z are Studio-only and restore every local write; bramble props follow their block; fires off on `lowEndDevice`; the key line and the map's key glyph on phones (375×667, 667×375) |
| **3 The raiders and the pose** | `src/combat/client/Controllers/Raiders/RaiderPose.luau` and `Figures.luau` (new), `CrowdRenderer.luau`, `ThreatFx/Cues.luau`, `InputController.luau`, `CombatUIController.luau`, `src/client/UI/Theme.luau`; `tools/testfit/raiderpose.py`, `tools/check_raider_mirror.py` | Every tell still reads on a model (windup heat, flash, dull, enraged, the plate's glint and break, the cues); TextureID cleared on every painted part; the drawn head stays on the scored head in every pose (the head rule) and seated; pools per kind and the prewarm cap; X restores placeholders and back; the Chief's Warhammer (missing → no hammer, one warn); the walk only near the camera; CrowdRenderer under the compile gate; the mirror is live and covers the arm rules (whirl, steady, throw path), the walk and the paint |
| **4 Data, simulators and gates** | `src/shared/Config/` (`ProvingGrounds.json` the `chief` kind and `crowd` keys, `Levels/1_ForestRoad.json`, `Expeditions.json` moods and keys, `Combat.json`, `RaiderModels.json` new, `LevelDress/ForestRoad.json`), `tools/sim_range.py`, `tools/check_stage_mirror.py`, `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/assets/raider_frames.py` (new), `tools/levels/*`, `tools/crowd_harness/` (`run_harness.py`, `mutate.py`, `mirror_mutants.py`, `stage_mirror.luau`, changed `tests_*.luau`), `docs/BALANCE.md` | The Chief's numbers inside the bands and his hit shapes 14 / 4 / 1.6 (his model's); the sweep's range against the hammer's posed reach; R8 as ruled (against the same gear; "road" resume) and its mutants red; the walls in every "can" gate and every wall top unclimbable; `raider_frames.py --check --require-harvest` really proves the config through the harvested frames; the mirrors call the real Luau; no pin or mutant vacuous; the hub untouched |

## Output

Write `docs/prompts/l4-w2-review/<slice>.md` (`1-server.md`, `2-scenery.md`, `3-raiders.md`, `4-data.md`), LF. Each finding:
**Critical / Major / Minor**, file:line, what is wrong, a concrete failure scenario, and the suggested fix. One line each
for what you checked and found clean. End your reply with the count by severity and the file path.
