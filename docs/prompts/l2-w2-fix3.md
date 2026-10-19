# L2 W2 third fix round (lead's rulings, 2026-10-18)

Findings: `docs/prompts/l2-w2-review/fix2-diff.md` (m1, s1; s2 is docs only). Work only in
`C:\Users\benja\Desktop\tycoon-p5b` (branch `l2-w2-fix2`); never touch `tycoon-p5`.

- **m1:** the origin rule's lead goes along the server's own measured displacement (the PositionRing's direction
  over the same window as its speed), never the client's claimed velocity; the claimed velocity may only shorten
  it (use its component along the measured direction, floored at 0). Harness case: the reviewer's probe (a forged
  origin behind a free-standing 2.5 wall with a claimed (74, 0, 0) velocity) is refused; mutation that puts the
  client velocity back.
- **s1:** add the honest gatehouse case to `leadTests` (dash east hugging GatehouseWallS, turn into the passage:
  the head line refused, the lead hits WallE and is carried back, the line from there allowed) and mutate entries
  `then head` and `LEAD_STANDOFF = 50` that it must catch.

Done when: harness green (`py tools/crowd_harness/run_harness.py C:/Users/benja/Desktop/tycoon-p5b
C:/Users/benja/Desktop/tycoon/tools/bin/luau.exe`); mutate.py filtered to WorldReact and WeaponService entries,
0 uncaught, plus a stale-text count over all entries; check_stage_mirror; check_compile; stylua; selene; luau-lsp.
Commit nothing; kill only your own PIDs; Python `py`; LF. Report to `docs/prompts/l2-w2-reports/fix3.md`.
