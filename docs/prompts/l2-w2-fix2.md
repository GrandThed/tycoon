# L2 W2 second fix round (lead's rulings, 2026-10-18)

Findings: `docs/prompts/l2-w2-review/fix-diff.md` (m1–m3, s1). Read it in full, plus
`docs/prompts/l2-w2-reports/fix-server.md`, `fix-client.md`, `fix-data.md`. Work only in
`C:\Users\benja\Desktop\tycoon-p5b` (branch `l2-w2-fix2`); `tycoon-p5` runs the full mutation suite: never touch it.
You own every file this round needs (server, shared, client, layout/config, tools), alone.

- **m1 (forged origins through camp C's 1-stud fence):** a camp may set its own fence thickness
  (`fence.thickness` in the layout; default `levels.fenceThickness`); camp C (the walled camp) gets 2.5.
  LevelGeometry builds fences, gates and the barrier band from it; every tool that mirrors the fence (check_levels
  walled gate and sight rules, sim_range, check_stage_mirror if it reads it) reads the same value. Re-check the L1c
  sight margins (≥ `sightMargin` 1.5), the close's nudge and `inner`, the camera clip and the ceiling rule.
  Add a check_levels gate: `shooting.originWallChord` is under the thickness of every tall colliding piece the
  player can stand beside, generated fences included — red on today's data (fence 1) and green after; plus a
  mutate entry on `aimAllowed`'s chord argument (e.g. originPad in its place) and a harness/source check that
  catches it.
- **m2 (honest origins refused on fast travel):** also accept a clear line from the head advanced by the same lag
  slack the distance check grants (`head + rootVelocity × lag`, capped as that check caps it); a forged origin
  beyond a wall must still be refused. Harness cases for both.
- **m3:** continuous (stream) families take no bloom spread, on the client and in any server check that assumes
  it; the drawn flame and the phone burn test then match the server's capsule.
- **s1:** cache `streamReach`'s RaycastParams.

Done when: harness green (`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5b
C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`); mutate.py filtered to entries in files you changed, 0
uncaught, plus a stale-text count over all entries; check_levels; check_levels_mutants for the new and touched
cases (`--only`); check_stage_mirror; `py -3.12 tools/sim_range.py --check`; check_compile; stylua; selene;
luau-lsp (both sourcemaps). Commit nothing; kill only your own PIDs; Python `py`; Bash
`export PATH="$HOME/.rokit/bin:$PATH"`; LF. Report to `docs/prompts/l2-w2-reports/fix2.md`.
