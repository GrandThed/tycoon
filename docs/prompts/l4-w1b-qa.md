# L4 W1b QA (lead's summary; the qa-runner died on the account's weekly limit after its runs finished)

Run on `l4-w1b` f16515a in `tycoon-p5b`, logs in the session scratchpad `qa-w1b/`. Every gate green except the known R8
row (Road3, Hard, sword T1 / bow T4, x1.60; W2 judges it fairly, MISSIONS_DESIGN §27.5):

| Gate | Verdict |
|---|---|
| stylua, selene | clean (selene: 1 pre-existing warning in `src/client/UI/LegacyPanel.luau`, untouched) |
| luau-lsp, both sourcemaps | 0 diagnostics |
| `check_compile.py` | PASS, 176 files |
| rojo builds (six places) | built |
| harness | PASS (4,162 checks) |
| `check_stage_mirror.py`, `mirror_mutants.py` | PASS; 132 of 132 caught |
| `check_levels.py`, `check_levels_mutants.py` (3.12) | PASS; MUTANTS: PASS |
| `sim_range.py --check` (3.12) | FAIL (1): the known R8 row only |
| `sim_combat.py --check`, `sim_economy.py --check` | PASS, PASS |
| `mutate.py` full run | 1,764 run, 0 not caught |
| tripwire grep, CRLF | empty, 0 |

Fix rounds 2 and 3 (`l4-w1b-fix2`, c01348a, 7f43124) changed `VitalsService`, `WeaponService`, `WaveService`, the harness,
`mutate.py` and `sim_range.py`; each round's designer ran the harness (4,185, then 4,244), `sim_range --check` (only R8),
the stage mirror and its mutants, and `mutate.py` filtered to the changed files (260 and 278 run, 0 not caught) with the
stale check over all entries (1,795, then 1,830, 0 stale). The lead re-ran stylua, selene, `check_compile` and CRLF on
7f43124: clean.
