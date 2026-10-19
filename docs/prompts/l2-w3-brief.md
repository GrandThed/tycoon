# L2 Wave 3 contract (brief for the drafting agent)

Write `docs/prompts/l2-w3-contract.md` (under about 350 lines) in the worktree `C:\Users\benja\Desktop\tycoon-p5`,
branch `l2-w3`. **Write no code.** Kill only your own PIDs.

Read: `CLAUDE.md`; `docs/MISSIONS_DESIGN.md` §7–§9, §12.1, §21, **§22 with its W2 paragraph (decisions: the frost
weapon is a melee frost hammer whose swings freeze the water ahead; built now, found later: a Studio lever until
the Castle exists)**; the study `docs/prompts/l2-study-report.md` §1, §5, §6, §11 W3; the W2 contract
`docs/prompts/l2-w2-contract.md` with §10/§11 and its three fix rounds (`l2-w2-fix-round.md`, `l2-w2-fix2.md`,
`l2-w2-fix3.md`) and their reports — W3 reuses W2's machinery (`WorldReact`, the strike hook, `LevelService.React`,
the Armory panel, phone auto-target for world objects, check_levels' reach/lift/sight rules, the shot-origin rule);
INTERFACES "# L2 W1/W2 contracts" with the as-built notes; `docs/WEAPONS.md`. Verify every file:line you rely on.

## Wave 3 scope: ice, the frost hammer, deep water and the island shrine

1. **The frost hammer family**: melee (arc or capsule — pick from the existing melee shapes), `element = "ice"`,
   its ability (map onto an existing launcher), numbers sized with `sim_range` (never beats the Broadsword on the
   bosses; a forest run with it), visuals. It is owned only through a Studio lever until the Castle; how the
   Armory shows it before then (locked, "Found in the Castle"), given W2's rule that an unowned family shows locked
   only when a secret pays it.
2. **Freezing water**: what a swing does to `react = "ice"` water (a walkable ice disc/sheet per hit vs the whole
   strip; how long it lasts — the run, or melts after N s; refreeze), server-owned, reset per run, a pure
   harness-tested rule (extend `WorldReact`); collision of the new sheets (players only; the crowd's floors are
   fixed per run and never reach the creek); phones (auto-target for water like W2's brambles); the rule on what
   counts as a hit on water (a melee arc reaching down over the edge).
3. **Deep water**: the creek and pond stop being solid; a fall below `killY` gets the free rescue; the creek
   crossing on the main path must still be passable with one jump (bridge/stepping stones as today?) — check the
   one-jump first run; the pond grows (or the shrine moves) so the island is out of reach without ice by every
   means (jump 18/30, dash, walk-off grace, every lifting ability's arc, stacking is already off); `check_levels`
   rules (the shrine needs ice; the creek rule and sniper pins rewritten).
4. **The shrine chest**: what it pays (the design says the shrine is the biggest of the three), key `ice`.
5. **ASCII plan** of the creek/pond area today vs proposed, for the lead to show Ben, with options if the shape is a
   real choice. Also list the 2–3 design choices that truly need Ben (e.g. disc-per-hit vs whole strip; melt or
   stay) with a recommendation each.
6. **Studio levers** (grant the frost hammer — K-style key like F for fire; reset) in both entry points.
7. **Balance**, **owners** (disjoint files, definitions of done) for luau-engineer, ui-engineer, economy-designer;
   the exact `Main.server.luau` wiring for the lead (if any).
8. **Risks.**

End your reply with a ten-line summary, the ASCII plan(s), the questions for Ben with recommendations, and the path.
