# L2 Wave 2 contract (brief for the drafting agent)

Write `docs/prompts/l2-w2-contract.md` (under about 350 lines) in the worktree `C:\Users\benja\Desktop\tycoon-p5`,
branch `l2-w2`. **Write no code.** Kill only your own PIDs.

Read: `CLAUDE.md`; `docs/MISSIONS_DESIGN.md` §7–§9, §12.1, §21, **§22 (decisions)**; the study
`docs/prompts/l2-study-report.md` (§1, §5, §6, §7, §8, §11 W2; verify every file:line you rely on — W1 changed
code since); the W1 contract `docs/prompts/l2-w1-contract.md` with its §10/§11 and the two fix rounds
(`l2-w1-fix-round.md`, `l2-w1-fix2.md`) for the shape and the rulings W2 must keep (L2-27: honour
`families.flamethrower`; `check_levels.fielded_lifts` must read profile families once a picker exists);
INTERFACES "# L2 W1 contracts" and the L1c section; `docs/WEAPONS.md`.

## Wave 2 scope: fire, the Flamethrower, the cave and the shortcut

1. **The Flamethrower family**: ranged, short held stream (capsule, `continuous`), hits everything in it;
   variants A/B if the house style needs two; its ability (map onto an existing launcher where possible);
   `element = "fire"`; numbers sized with `sim_range` against the Colossus and on Forest Road (it must not beat
   the Broadsword on the bosses, which are tightly tuned); the flame visual and the ability visual.
2. **Owning and choosing weapons**: `combat.families` (W1 records the Flamethrower at the lookout chest) plus
   the two starters; a lobby **loadout picker** (`RequestSetFamily(slot, family, variant)`, refused outside the
   lobby / for an unowned family / wrong slot, rate-limited), how the choice persists (session or profile —
   recommend), the panel on phones and gamepad (reuse W1's ActionRows and the Abilities panel's patterns), a
   Studio lever to grant a family.
3. **World reactions**: layout entries with `react = "fire"`; the server's per-run reactive list; the hit test
   in `WeaponService.finish()` (or wherever every resolved shape passes) against reactive boxes for a fire
   family; what happens on burn (bramble removed, a burn cue to clients); reset per run; a pure, harness-tested
   rule.
4. **The cave and the shortcut** (Ben: "a hidden path skips ahead to Main Camp; once found, later runs are
   faster"; his picture showed the cave between camp A and Main Camp, while today's cache sits between Main Camp
   and the clearing): propose the cave's placement (move the cache, or keep it), a roofed cave behind a bramble
   mouth, its chest (what it pays), the shortcut's exit, and how "found" is saved (`combat.shortcuts`) and
   applied (whose save decides a party's layout: the leader's, as for the map). Make the layout change concrete
   with an **ASCII top-down plan of the whole road** (today vs proposed, 2 options if the placement is a real
   choice) that the lead can show Ben. Check every gate it moves: R8 sniper pins (the cave removes the cache
   perch), route length band 900–1,100, sneak path, `stray_reach`, check_levels reach rules (the cave must be
   unreachable without fire by any means), the one-jump first run.
5. **Studio levers** (grant a family, reset shortcuts) in both entry points.
6. **Balance**: Flamethrower rows in sim_range, the shortcut run's time and pay, the cave chest against a clear.
7. **Owners** (disjoint files, definitions of done) for luau-engineer, ui-engineer, economy-designer; the
   exact `Main.server.luau` wiring the lead does.
8. **Risks** and what truly needs Ben (the cave placement if it is a real choice; anything else only if it must).

End your reply with a ten-line summary, the ASCII plan(s), and the path.
