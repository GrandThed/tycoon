# L2 W2 fix round (lead's rulings, 2026-10-18)

Findings: `docs/prompts/l2-w2-review/server.md` (s-m1..m3), `client.md` (c-M1, c-M2, c-m1..m8), `data-tools.md`
(d-M1, d-m1..m4). Read the file(s) for your slice in full, then the contract `docs/prompts/l2-w2-contract.md`
(§10, §11). Branch `l2-w2` in `C:\Users\benja\Desktop\tycoon-p5`.

## Rulings

- **c-M1 (phones cannot burn):** in autoFire mode the stream also fires at a `Workspace.Level` Part whose `React`
  equals the held family's element (`Unlocks.ElementOf`), whose `Heat` < 1, and that the shared
  `WorldReact.Touches` says the capsule touches — the capsule cut at the first wall (c-m4) and padded by
  `levels.react.pad`. Resting bodies still never trigger auto-fire. Harness check where pure.
- **c-M2 (flame drawn short):** the local flame and its wall ray start at the shot origin, not the camera: expose
  one `InputController.ShotRay()` (or equivalent) used by both, never a copied formula.
- **c-m1:** `openPivot` uses a spherecast from the head minus the pad. **c-m2:** re-select after result,
  SetLoadout and rebuild when the last input was a gamepad. **c-m3:** match a `setFamily` answer on `slotId`.
  **c-m5:** the bramble collapse and the flame flicker gate on `Theme.lowEndDevice`, never `reducedMotion` (true on
  every touch device; living-city lesson). **c-m6:** the local flame stops on release (own server strikes do not
  keep it alive). **c-m7:** one result-timeout constant. **c-m8:** fix the stale comments.
- **s-m1:** the React loop becomes a pure `WorldReact.Apply(entries, element, fx, pad, need)` with harness cases and
  mutations (element constant, `react ~= element` dropped); a harness source check for the Main wiring
  `OnStrikeResolved(LevelService.React)` and for `finish`'s abandoned skip.
- **s-m2:** ability strikes never burn (`React` returns when an ability is set); harness case.
- **s-m3:** Validate refuses a shortcut size ≤ 0 (mirrored in sim_range; mutant).
- **d-m3 (forged origin through thin walls):** the server refuses a shot origin with a wall between the
  player's head and it (one ray, the same parts list the server already uses), for weapons and abilities;
  harness case if pure. Report any legitimate shot it would refuse (camera at the shoulder in a tunnel).
- **d-M1 (cave roof from the ledge):** every 64-high cave piece within reach of the lookout ledge or the chest
  goes to 84 (split blocks as needed); `check_cave` runs `lift_routes` with the double jump's height against every
  wall of `shut.boundary()`; a mutant with today's (64) data must turn red. Re-check the camera clearance and
  the tunnel's look are unaffected.
- **d-m1:** the ridge rule's reach includes the walk-off grace (`walkSpeed × coyoteSeconds`, 49.3).
- **d-m2:** recorded as a known limit until L3 (an ability arc can cut the BC bend, ~4 s, no camp skipped; no
  lifting family is owned by a W2 save); check_levels reports it as such and goes red once a lifting family can
  be owned without a lever.
- **d-m4:** rate CaveExit (and CaveMouth) with the Flamethrower's ability too; if either out-earns the mission
  player on Normal or Hard, move the corridor more than its reach from the road except at the mouth.

## Owners (disjoint)

- **Server agent (luau-engineer):** `src/shared/WorldReact.luau`, `Unlocks.luau`, `Types.luau`,
  `src/combat/server/Services/LevelService.luau`, `WeaponService.luau`, `AbilityService.luau`, `StageFlow.luau`,
  `tools/crowd_harness/**`, `tools/check_stage_mirror.py`. (s-m1..m3, d-m3, the pure half of c-M1 if it lands in
  WorldReact.)
- **Client agent (ui-engineer):** `src/combat/client/**`, `src/client/UI/Theme.luau`. (c-M1, c-M2, c-m1..m8.) Code
  against the server agent's WorldReact names by reading its diff as it lands.
- **Data agent (economy-designer):** `src/shared/Layouts/Levels/ForestRoad.json`, configs if needed,
  `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/sim_range.py`, `docs/BALANCE.md`. (d-M1, d-m1,
  d-m2, d-m4, the s-m3 mirror.)

Each agent: `git status`/`git diff` first; commit nothing; kill only your own PIDs; changes needed in another's
files go in your report. Report to `docs/prompts/l2-w2-reports/fix-<server|client|data>.md`. Gates as the
contract §8 for your role (harness `py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5
C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`, filtered mutate + stale count, check_levels + mutants,
check_stage_mirror, `py -3.12` sim_range --check, check_compile, stylua, selene, luau-lsp).
