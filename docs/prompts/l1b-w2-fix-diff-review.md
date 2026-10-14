# L1b Wave 2 — fix-diff review brief (one reviewer)

Read-only review of `git diff f40509a <HEAD named in your prompt>` in the worktree
`C:\Users\benja\Desktop\tycoon-p5` (branch `l1b-wave2`): the fix round after the four-slice review.
Every Bash call starts with `cd /c/Users/benja/Desktop/tycoon-p5 && `. Edit no source file. Write
findings to `docs/prompts/l1b-w2-review/fix-diff.md` as you go.

Read: `docs/prompts/l1b-w2-fix-round.md` (the findings and the lead's rulings),
`docs/prompts/l1b-w2-reports/lead-routing.md` (every ruling since, above all the fix-round routing:
one landing rule in `SwingGate`, the `resting` field and `CampAim.Takes`, rising tent bodies at
doors, `Rouse` from home and `TentRouse` only with a player in play), the fixers' reports
`fix-A.md`, `fix-B.md`, `fix-ui.md`, `fix-econ.md`, `fix-tail.md`, and the review findings in
`docs/prompts/l1b-w2-review/` that the fixes answer.

Look for: a fix that does not fix its finding; a fix that breaks something that worked (the range
sets `fight` / `colossus` / `warlord`, Wave 1's camp rules, the boss room, a late joiner); client and
server disagreeing on the landing rule (same samples, same probe, same clears; can an honest
bunny-hop, a lip, a get-up, a double jump, a 250 ms lag still be refused or get two swings); the
`resting` re-announce (a body removed and re-announced in one step, a dead body brought back on a
client, batches lost); a rising tent body (where it spawns, whether it can be hit while rising,
whether a late joiner sees it replay); a group stuck by the new rouse rules (a tent that can never
empty, a camp that can never clear); a test or mutation that cannot fail; a mirror that disagrees.
Severity as in `docs/prompts/l1b-w2-review.md`. Every finding: file:line, a concrete scenario, a
fix in one or two sentences. End the file with `Critical n, Major n, Minor n`.
