# L4 W1b — go for the designer

W1 track D (the lookout at the trailhead) is committed on `l4-real-forest` (5744df9) and merged into `l4-w1b` (1d3b0d2).
The designer may now touch every file §6 gives it, including `check_levels.py`, `check_levels_mutants.py`,
`sim_range.py`, `tests_l2.luau` and `mutate.py`. Read track D's report first: `docs/prompts/l4-w1-reports/lookout.md`
(it removed `SNIPER_KNOWN_LIMIT_L4` and re-aimed mutants).

**Known open row, not yours to fix:** `sim_range.py --check` fails one R8 row (Road3, Hard, sword T1 / bow T4, x1.60 on
seed 11); it was red at HEAD on 12 of 30 seeds and is waiting on Ben's ruling. Your definition of done is every gate
green except that one row, unchanged in value by your edits (say its number before and after).

Relays to apply on top of the contract: `docs/prompts/l4-w1b-reports/luau-a.md`, `luau-b.md`, `ui.md` (each has a
"For the other owners" section) and `lead-routing.md` (Sounds.json joins your files).
