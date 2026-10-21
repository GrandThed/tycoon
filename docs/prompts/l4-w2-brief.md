# L4 W2 — the forest and the raiders in the game (brief for the contract drafter)

You draft a contract; you write no code. Read in `C:\Users\benja\Desktop\tycoon-p5` (branch `l4-real-forest`) and in
`C:\Users\benja\Desktop\tycoon-p5b` (branch `l4-w1b`: the old mission code being removed right now; **W2 starts from that
branch once it merges**, so read the game code there). Edit no repo file except
`C:\Users\benja\Desktop\tycoon-p5\docs\prompts\l4-w2-contract.md` (LF). Do not commit. Kill only your own PIDs. Tools:
`py` only; `export PATH="$HOME/.rokit/bin:$PATH"`; the Luau CLI is `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
A raider kit builder and a pipeline engineer work in `tycoon-p5` now; read their files, never edit them.

## What W2 is

Ben's decisions: `docs/MISSIONS_DESIGN.md` §26 and §27 (the forest as shown, mood B, the Chief look A, the raider style,
R8 judged fairly). W1 made everything on paper: read `docs/prompts/l4-w1-reports/forest.md` (it ends with a proposed W2
contract for the forest: what the server and the client must do, the data file, the 62 invisible walls, the plan hash),
`raiders.md` (the rig rules as numbers, the colour route, the config `tools/assets/out/RaiderModels.json`),
`lookout.md`, `lead-notes.md`; the study reports `docs/prompts/l4-study-report-forest.md` and `-chief.md` (§2 the Chief
as a data kind, §3 the renderer changes and the head rule); `docs/prompts/l4-w2-raiders.md` and `l4-w2-pipeline.md` (the
two asset tracks running now: their outputs feed W2, and the lead's ruling on where assets land is in the pipeline brief);
`docs/prompts/l4-w1b-contract.md` (what is gone after W1b). `CLAUDE.md` for the rules (the 180-locals compile gate:
`CrowdRenderer` is near it, new behaviour goes in new modules).

W2 puts in the game, in one wave after one harvest paste:
1. **The forest:** the server builds the invisible walls (character-only, rays and camera pass), hides every skinned
   layout Part while keeping its collision, applies the proposed looks, and checks the plan hash with an all-or-nothing
   fallback to today's grey level; the client clones the baked meshes and props when the level appears, attaches the
   fires, drops a bramble's props when it burns. Where the game reads the generated data file (today
   `tools/levels/out/ForestRoad.dress.json`) and how a missing template degrades (CLAUDE.md: placeholders, never errors).
   **Mood B** as dungeon-place config (Lighting / Atmosphere set by code in the combat place only; the lobby and the hub
   untouched); its numbers come from the W1 renders and are tuned in Studio.
2. **The raiders' models** on crowd bodies: per-kind pools pre-warmed from the level, the figure module (placeholder
   fallback for any kind without a model), the walk cycle from distance travelled (only near the camera), the
   weapon-arm keys, the head rule, the tint route (clear TextureID, paint cloth/skin/glow as today), the plate role, the
   Chief's Warhammer (the harvested L3 template scaled at runtime), the smaller chest core, and a mirror check that
   the client's poses equal `tools/testfit/raiderpose.py`.
3. **The Camp Chief** as a crowd kind `chief` in data (the Colossus's attacks and numbers as the start, the war-club
   sweep as an `arc`, the call for raiders), at camp C; the Colossus stays for the range. Every gate and simulator that
   names the Colossus at camp C moves to `chief`; camp C's sight gate uses the posed reach from the raider config.
4. **Seated hit shapes drop** with the seated pose (server), so the head rule holds seated.
5. **R8 judged fairly** (MISSIONS_DESIGN §27.5): the rule, where it lives in `sim_range.py`, its mutants; the Road3 Hard
   row must pass under it or the contract says what happens.
6. **The walls in the movement gates:** `check_levels.py` (hops, lifts, the sneak, the unclimbable list, L2-18's lift
   model) learns the 62 walls; any new standable top is rated.

## What the contract must settle

Owners with disjoint files (luau-engineer A: server and shared; ui-engineer: `src/combat/client/**`, `src/client/**`;
economy-designer: Config, Layouts, simulators, gates, harness texts, `docs/BALANCE.md`; lead: project files), every
relay named; the data shapes (types, the dress file's fields as the game reads them, the raider config as the game reads
it, where both files live under `src/shared`); the order (what waits for the harvest paste, what can be built and tested
before it with placeholders); the Studio levers Ben needs (key-only; Ben's Studio is in Spanish); the phone rules
(`Theme.lowEndDevice` gating, not `reducedMotion`, which is on for every touch device); a definition of done with every
gate command (the W1b contract's §8 list plus `py tools/levels/forest.py check`, `py tools/testfit/raiderpose.py --check`
and the new mirror check); risks, including what Ben must judge in Studio (frame time on a phone, the mood, the walk cycle,
whether dodging still feels the same after W1b's dash change).

Keep it under about 300 lines, every claim with file:line. Write it as you go. End your reply with a ten-line summary and
the contract path.
