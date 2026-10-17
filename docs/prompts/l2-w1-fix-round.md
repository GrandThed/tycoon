# L2 W1 fix round (lead's rulings, 2026-10-17)

Findings: `docs/prompts/l2-w1-review/server.md` (s1–s4), `client.md` (c1–c7), `data-tools.md` (d1–d4), all Minor.
Read the file(s) for your slice in full, then the contract `docs/prompts/l2-w1-contract.md` (§10, §11). Branch
`l2-secrets` in `C:\Users\benja\Desktop\tycoon-p5`.

## Rulings

- **s1 + d2 (the cache can never trigger):** a chest's trigger measures the flat distance to its block's
  footprint (the axis-aligned rectangle of the secret's block), not its centre; `Site` carries `sx`/`sz`.
  The designer re-tunes `levels.secretReach` (and band) so the lookout still triggers only on the ledge and
  on the chest, and the cache would trigger from beside it once it has a key. check_levels rule (a) runs for
  EVERY secret (sold key or not), mirrored in Python, with a mutant that puts the centre rule back.
- **s2, c5, d4 (duplicated caps and drifts):** one home for the family-id cap and the ability-id cap (in
  `Unlocks` or Config; every reader uses it); `Unlocks.DefProblem` refuses an empty `text`; family length is
  counted the same way (bytes) on both sides.
- **s3:** a pure `Unlocks.Apply` (and the same for the secret write) that the services call, with harness
  cases and a mutation that sells at 0.
- **s4:** `Init` and `Find` pick the same entry for a repeated id (first valid, or first; one rule).
- **c4:** one pure `WallClip.GroundFloor(...)` (or equivalent) called by both `WeaponService.GroundPoint` and
  `InputController.groundPoint`; harness case + mutation.
- **c1:** the lobby HUD row never covers the health bar or the Dash button at 667x375, 640x360 or 375x667
  (second row or a capped width; say which).
- **c2:** gamepad can open and use the panel: a lobby-only gamepad toggle, the first live Buy selected on open
  after gamepad input, ButtonB closes it above the dash's priority.
- **c3:** a walk-off grace window: a jump pressed within `movement.coyoteSeconds` (new key in
  `ProvingGrounds.json`, e.g. 0.12) after walking off an edge is the ground jump; no "buy Double Jump" hint for
  such presses. sim_range and check_levels must not need a change (the jump's height above the floor walked
  off is unchanged); the designer confirms.
- **c6:** map key words at least 11 (`MAP_SECRET_KEY_TEXT`). **c7:** the found card sits above the crosshair.
  The launch-stacking note is answered by data-tools (closed; no change).
- **d1 (stacking):** players do not collide with players in the dungeon place (`BarrierGroups`); check every
  rule that relied on player-player collision (L1c's entry clearance, the lobby) and report. The "owners only"
  labels stay; add a PLAYTEST note later via docs.
- **d3:** the L2-20 one-jump gate counts every place an air jump is dropped (the timed jump, the hop), with a
  mutant that turns an air jump back on and must turn the gate red.
- **d4 BALANCE:** label the 937-route row as "before F1 + F2".

## Owners (disjoint)

- **Server agent (luau-engineer):** `src/shared/Unlocks.luau`, `WallClip.luau`, `Types.luau`,
  `src/combat/server/Services/SecretFlow.luau`, `UnlockService.luau`, `StageFlow.luau`, `CombatRemotes.luau`,
  `WeaponService.luau`, `BarrierGroups.luau` (wherever it lives), `tools/crowd_harness/**`,
  `tools/check_stage_mirror.py`. (s1 code, s2, s3, s4, c4 server half and the shared function, c5 server half,
  d1.)
- **Client agent (ui-engineer):** `src/combat/client/**`, `src/client/UI/Theme.luau`, `src/client/UI/MapScreen.luau`,
  `src/shared/Config/ProvingGrounds.json` (`movement.coyoteSeconds` only). (c1, c2, c3, c4 client half, c5
  client half, c6, c7.) Code against the server agent's `GroundFloor` and cap names; agree them by reading its
  diff as it lands (poll `git diff`), never by writing its files.
- **Data agent (economy-designer):** `src/shared/Config/Combat.json` (`secretReach`/band), layout or level JSON
  if needed, `tools/check_levels.py`, `tools/check_levels_mutants.py`, `tools/sim_range.py`, `docs/BALANCE.md`.
  (s1 tuning and mirror, d2, d3, d4 Python halves, the c3 confirmation.)

Each agent: `git status`/`git diff` first; commit nothing; kill only your own PIDs; changes needed in another's
files go in your report. Report to `docs/prompts/l2-w1-reports/fix-<server|client|data>.md`. Gates as in the
contract §8 for your role (harness, filtered mutate + stale count, check_levels + mutants, check_stage_mirror,
sim_range --check on 64-bit, check_compile, stylua, selene, luau-lsp).
