# L1b Wave 3 — the bow (brief for the economy-designer)

You work in the worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave3` (from `main`).
Never touch the main checkout `C:\Users\benja\Desktop\tycoon` except to run its
`tools\bin\luau.exe`. Kill only your own processes, never by image name.

Environment: Bash `export PATH="$HOME/.rokit/bin:$PATH"`; Python is `py` (not `python`). Files you
write must be LF.

## Read first

1. `docs/INTERFACES.md` "Wave 3 — the bow (2026-10-15)" (the last section): rulings L1b-W3-1…6,
   ownership, gates. It is the contract and it wins over this brief.
2. `docs/INTERFACES.md` "Wave 2 — the long road", only "Balance bands" and "Gates".
3. `docs/BALANCE.md` "L1b W2: the bow at 2 / 2" and the L1b Wave 2 results (how the bow and sword
   were measured; reuse that method and those seeds).
4. `docs/SPEC.md` §1 and the combat balance section only if you need context.

## The task

Ben played Forest Road at gear 2 / 2 and says the Longbow is stronger than the Broadsword; he chose
"lower the bow's numbers a little".

1. **Measure before changing anything:** Longbow alone (head aim where it can, and body aim) and
   Broadsword alone, at 2 / 2, Normal, solo, policy `mission`, over Forest Road's three camps:
   time, hits taken, crits landed, per camp and total. If `sim_range.py` cannot isolate this, add
   the smallest reporting mode that can (you own `tools/sim_range.py`).
2. **Apply ruling 3 (the stop):** if the head-aim bow already takes ≥ 1.10× the sword's time, stop.
   Change no number; write the measurement into BALANCE "L1b Wave 3: the bow" and report.
3. **Otherwise tune by ruling 1** to hit ruling 2's band (1.10–1.25×). Prefer the smallest cut
   that lands inside the band; give the factor and both new `damage` values.
4. Report the bosses by ruling 4 and re-band only what ruling 5 allows. List every re-banded row.
5. Run: `py tools/sim_range.py --check`, `py tools/sim_combat.py --check`, `py tools/check_levels.py`,
   `py tools/check_stage_mirror.py`, and `py tools/crowd_harness/run_harness.py <worktree root>
   C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`. Do not run `mutate.py` (QA runs it). If the
   harness or a mirror fails because of the new number, do not edit Luau: report the file, line
   and assertion.
6. Commit on `l1b-wave3` with a one-line message ending with the line
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Report (write it to `docs/prompts/l1b-w3-reports/designer.md`, then reply with the same text)

- Before: bow and sword times, hits, crits (table).
- Decision: stopped by ruling 3, or the factor and new values.
- After: the same table, the bosses before/after, the Raider Arena at 2 / 2.
- Every re-banded row (old value, new value, old band, new band).
- Each command's verdict line.
- Anything for another owner, with file and line.
