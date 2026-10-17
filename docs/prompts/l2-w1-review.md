# L2 W1 review (brief)

Read-only review of `main..l2-secrets` (HEAD at the commit after bf9cd47) in `C:\Users\benja\Desktop\tycoon-p5`.
Read first: `CLAUDE.md`, `docs/MISSIONS_DESIGN.md` §22 (decisions), `docs/prompts/l2-w1-contract.md` (rulings
L2-1..28, §10 and §11 the lead's), the reports in `docs/prompts/l2-w1-reports/`. Accepted deviations: no notch
(F1 + F2 instead), first-run band 4.0–5.75 min, `Types.UnlockAbilityDef`, optional profile maps, a `locked`
chest re-checked in the same run, the lobby picker deferred to W2.

Judge against what Ben must get: (1) a first run with only one jump; (2) buying Double Jump with 10 Valor in
the lobby, server-validated (type, id, owned, affordable, gate, rate limit; no yield between check and write;
DataStore safety); (3) the lookout chest pays once per player, only to an owner of the key, saved, and is out
of reach without Double Jump by every means (jumps, dash, every ability, wall tops, voids); (4) v7 is safe for
the live hub and the frozen live Expeditions place; (5) Studio levers inert outside Studio and in the range;
(6) phones (panel fits 667x375 and 375x667; touch button). Also: --!strict, constants only in config,
client/server and Luau/Python mirrors identical, tests that could be vacuous (prove with a mutation if in
doubt), nothing broken in L1/L1b/L1c.

Severity: Critical (breaks a requirement, data loss, exploit), Major (likely seen in play / wrong data),
Minor. Each finding: file:line, what, a concrete failure scenario, a proposed fix. Run any tool on a
`git archive HEAD` copy in your scratchpad, never in the worktree. Write findings to
`docs/prompts/l2-w1-review/<slice>.md` and end your reply with the same list. Commit nothing; kill only your
own PIDs; Python `py`; Bash `export PATH="$HOME/.rokit/bin:$PATH"`; harness luau
`C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
