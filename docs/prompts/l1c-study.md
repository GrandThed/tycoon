# L1c study — the Chief's Clearing redone (brief)

You are the study-and-contract agent for a small fix wave. Work in the worktree
`C:\Users\benja\Desktop\tycoon-p5`, branch `l1c-chief-clearing` (already checked out). **Write no code.**
Your output is one file: `docs/prompts/l1c-contract.md`. Kill only your own PIDs.

## What Ben decided

Read `docs/MISSIONS_DESIGN.md` §21 (the decisions) and §15–§20 (how the living road works and why).
In short: the boss camp C ("The Chief's Clearing") gets a tall wall all round, a bent gatehouse
passage (one turn) instead of a gate on the road's line, no resident groups and no big waves; when
the player steps in, the gate shuts and a small group (about 8–10) rushes them from both flanks of the
entrance, where it waited out of sight; when that group is dead the Colossus comes. Nothing of the
clearing may be visible from outside, including from the top of a double jump.

## Read (summarise, don't paste)

- `CLAUDE.md` (code rules), `docs/INTERFACES.md` sections "# L1 contracts — Forest Road in grey" and the
  L1b waves (find them with grep; read only what touches camps, gates, locking, waves, spawns, residents).
- `src/shared/Config/Levels/1_ForestRoad.json`, `src/shared/Layouts/Levels/ForestRoad.json` (camp C,
  the blocks near x 229–380, `route`, `sneak`, `regions`), `Expeditions.json` `looks`.
- `src/combat/server/Services/LevelGeometry.luau`, `LevelService.luau`, `StageFlow.luau` (camp stages,
  lock trigger, wave spawning and where a group's bodies appear), `WaveService.luau`, `CampBrain.luau`,
  `Region.luau` — only what you need.
- The client side of what makes an enemy visible: crowd body rendering, any BillboardGui / Highlight /
  AlwaysOnTop marker, boss bar, hurt or threat pointers, minimap or off-screen arrows (grep
  `src/combat/client` and `src/client`). Anything that shows an enemy through a wall breaks the rule.
- Tests and tools that encode camp C today: `tools/check_levels.py`, `tools/check_stage_mirror.py`,
  `tools/sim_range.py`, `tools/crowd_harness/tests_*.luau`, `docs/BALANCE.md`.

## Answer in the contract

1. **Geometry (data first).** Can the wall, the gatehouse and the turn be built with today's layout keys
   (camp `fence.height`, `gates`, `blocks` of a wall look, `obstacles`)? If a key is missing, name the
   smallest code change. Give the numbers to start from: wall height that beats the camera at the peak of a
   jump + double jump from any reachable outside spot (state the jump numbers you used and where they come
   from), passage width that keeps the over-the-shoulder camera out of the walls, where the lock triggers
   (it must be past the turn), what shuts behind the player, the exit on the far side.
2. **The ambush.** The simplest correct mechanism with today's code: e.g. the stage's first wave spawned at
   two flank spawn points behind cover, or hidden residents that wake on lock. Say which, why, and what
   happens on each difficulty (`minDifficulty`, `countMult`). Bodies must not pop into view in front of the
   player; if spawning is instant, say where it happens relative to the sight line.
3. **Visibility.** Every client path that could show a clearing enemy from outside, and whether it does.
4. **Rewards and pace.** What the run loses in cash and time with the residents and the two waves gone;
   propose numbers for the ambush and any reward change so a Normal clear still sits near the targets in
   `1_ForestRoad.json` and `docs/BALANCE.md` (propose; Ben may say "about right" later).
5. **Gates to update.** Each test, check or simulator that will go red, and what its new expectation is.
6. **Owners.** Split into disjoint file sets: `economy-designer` (config, layout, sims, BALANCE),
   `luau-engineer` (server/shared code, harness tests), `ui-engineer` (client) — only the agents that have
   work. Each task gets a definition of done.
7. **Risks** in plain words, and anything Ben must decide (keep it to what truly needs him).

Keep the contract under about 250 lines. End your reply with a five-line summary and the path.
