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
4. **Layout: the winding road** (`docs/prompts/l1b-w2-layout/winding.level.json` and
   `winding.layout.json`, report `layout.md`): about 1,055 studs west to east, the road along the
   north side of A and B, the sneak path inside the north fence. Asked with the ASCII maps and the
   page `long-road.html` (local, not published).
5. **Tents: 8 bodies, one every 6 s, then they run out**, joining their own camp's fight. Not
   destroyable. (A: 4 fodder, 2 slingers, 2 brutes; B: 2 fodder, 2 slingers, 4 brutes; C's tent is
   where its stage waves come out, no extra stock.)

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
2. **The layout report's 19 assumptions (`layout.md` "Assumptions the lead must confirm"):**
   all confirmed as written, with these readings:
   - (1) The join rule chains: a group woken by a neighbour wakes, in turn, its own resting
     neighbours within 2 × its own sight. Judged once per wake, from resting places, in a pure
     `CampBrain` function with harness cases and a mutation.
   - (4) Population rule: residents + Σ tent stock + the boss room's room + 13 ≤ 160, replacing
     the flat reserve of 21. `Validate` enforces it per difficulty.
   - (5) Clear bonus as ruling 2: `crowd.clearBonus.share` 0.1 of the camp's whole stock at the
     difficulty's price (residents, its tent's stock, C's waves, not the boss), paid and kept the
     moment the camp clears.
   - (6) A tent sends only while a group of its camp is awake, and pauses (stock kept) while the
     camp rests. **Once every resident of the camp is dead, the tent empties its remaining stock
     at its pace whatever the camp's state,** so a camp can always be cleared. A camp clears when
     its residents and every tent body are dead and the stock is spent.
   - (10) The 38 brutes stay as the draft. The economy-designer re-measures after the headshot rule
     (brutes now take head crits) and may swap brutes for fodder to hit the band. Timber per
     minute must land within ±10% of Wave 1's 42: `rewards.brute.materials` 6 → 4 is the
     designer's lever.
   - (14) Band: simulator first Normal clear 7–8 min at 2 / 2 (Ben about 9–10.5); Hard and Brutal
     gated again by the human-reaction player as L1; pay bands back.
   - (16) Post spacing becomes a real `check_levels` gate (every difficulty).

## Agents

| Task | Brief | Report |
|---|---|---|
| Headshot on big bodies (read-only) | `docs/prompts/l1b-w2-headshot.md` | `docs/prompts/l1b-w2-reports/headshot.md` |
| Long-road layout plan + arithmetic | `docs/prompts/l1b-w2-layout.md` | `docs/prompts/l1b-w2-reports/layout.md` |
