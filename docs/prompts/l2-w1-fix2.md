# L2 W1 second fix round (lead's rulings, 2026-10-17)

Findings: `docs/prompts/l2-w1-review/fix-diff.md` (Major 1, Minor 1–3). Read it in full, plus
`docs/prompts/l2-w1-reports/fix-client.md` and `fix-server.md`. Work only in `C:\Users\benja\Desktop\tycoon-p5b`
(branch `l2-w1-fix2`); `tycoon-p5` runs the full mutation suite: never touch it.

- **Major 1 (HUD offset):** `bottomObstacles` takes the HUD's offset from the GUI inset
  (`GuiService:GetGuiInset()`), the same way the crosshair does, not `screenGui.AbsolutePosition`. Re-run the
  real `ActionRows.Pack` under luau.exe with the corrected offset and report the rows and clearances at
  667x375, 640x360 and 375x667 (Return must clear the health bar and Dash).
- **Minor 1 (GroundFloor arguments):** one shared helper builds the call's inputs (attribute read `== true`,
  movement from `Tuning.Get().movement`) so client and server cannot drift; the harness source check is limited
  to the GroundPoint / groundPoint functions and catches the reviewer's two mutations (add them to mutate.py).
- **Minor 2 (card wrap):** the found card measures its text (or auto-sizes) and `placeCard` places it from the
  real height; the family note never overlaps the reward line.
- **Minor 3 (launch as walk-off):** `ApplyKnock` clears the walk-off flag; fix the comment.

Done when: harness green (run_harness.py with C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe); mutate.py
filtered to entries in files you changed, 0 uncaught, plus a stale-text count over all entries; check_compile;
stylua; selene; luau-lsp (both sourcemaps, regenerated with rojo). Commit nothing; kill only your own PIDs;
Python `py`; Bash `export PATH="$HOME/.rokit/bin:$PATH"`; LF. Report to `docs/prompts/l2-w1-reports/fix2.md`.
