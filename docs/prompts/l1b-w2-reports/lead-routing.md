# L1b Wave 2 "the long road" — lead routing

Branch `l1b-wave2` in the worktree `C:\Users\benja\Desktop\tycoon-p5`, made from `main` at 1fc4612
(2026-10-14). Rulings are written here the moment they are taken; agents read this file first.

## Ben's rulings this session

1. **Start (2026-10-14):** "Headshot + layout": two fresh agents in parallel, nothing built, then
   the layout picture and the tent questions before any contract.
2. **Camp clear bonus: a small bonus**, about 10% of what that camp's raiders paid, on top of the
   per-kill pay. A config number. To be fixed in the contract: what "paid" means (the camp's
   stock at full price for the difficulty, not what this party happened to kill, so sneaking
   past nobody is not cheaper), and when it pays (the moment the camp's last body falls, kept
   at once like a kill).
3. **Merge rule (assumed, said once to Ben):** as Wave 1, each step that passes review and QA is
   merged to `main` and the six place files rebuilt.

## Lead rulings

1. **Headshot (report `headshot.md`, 2026-10-14):** the cause is the hit rule, not the drawing: a
   ray must first touch the body sphere (top at `height/2 + radius`), so on tall kinds the upper
   head is a total miss (Colossus 63% of head aims miss). Wave 2 adopts the report's fix as a pure
   rule `HitShapes.CrowdRay` (body OR head, padded; crit on the unpadded head), called from
   `WeaponService.rayCandidates`, mirrored in `sim_range.py`, with the report's harness cases and
   three mutations. **The body also becomes a vertical capsule** (ground to the head's base), so
   the Colossus's legs are hittable: the same complaint ("what I see does not get hit"). INTERFACES
   P1 decision 1 is amended in the Wave 2 contract. Boss times will drop with bows and rifles;
   the economy-designer re-reads them with no weapon-number change, and the Colossus / Warlord
   bands are re-checked at 2 / 2. Phone auto-fire then agrees with the server on heads.
   Carried as Minor for ui-engineer: a crit on a plate shows in the plate colour (make it crit
   yellow). Not in Wave 2: rewinding enemies for shots; the lean of the drawn head in a windup.

## Agents

| Task | Brief | Report |
|---|---|---|
| Headshot on big bodies (read-only) | `docs/prompts/l1b-w2-headshot.md` | `docs/prompts/l1b-w2-reports/headshot.md` |
| Long-road layout plan + arithmetic | `docs/prompts/l1b-w2-layout.md` | `docs/prompts/l1b-w2-reports/layout.md` |
