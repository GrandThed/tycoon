# L2 study — secrets and keys (brief)

You are the groundwork study agent for milestone L2 of a Roblox project. Work in the worktree
`C:\Users\benja\Desktop\tycoon-p5`, branch `l2-secrets`. **Write no code.** Your output is one file:
`docs/prompts/l2-study-report.md` (under about 300 lines). Kill only your own PIDs.

## What L2 is

`docs/MISSIONS_DESIGN.md` §7 (secrets), §8 (bought abilities), §9 (elements), §12.1 (Forest Road), §14 (order
of work: "L2. Secrets and keys: double jump as a purchase and the lookout; the Flamethrower and the bramble
cave; the frost weapon and the creek"), and §15–§21 for how the level works today. Read `CLAUDE.md` (rules),
`docs/WEAPONS.md` (families), and the INTERFACES sections for L1, L1b and L1c (grep the headings; read only
what touches secrets, movement, weapons, saving and the lobby).

## Answer, with file:line evidence

1. **The three secret sites today:** where they are in `src/shared/Layouts/Levels/ForestRoad.json`
   (`secrets`, `blocks`, `route`, `sneak`), what they look like, what code builds or reads them
   (LevelGeometry, check_levels, sim_range: the perch/sniper rules name the lookout and the cache). Can a
   player reach each one today with jump + dash only, with double jump, with nothing? Which simulator gates
   (R8 sniper spots) depend on them.
2. **Double jump today:** where it is granted (always on?), client and server (MovementController,
   ProvingGrounds `movement`, any server check of air jumps), and what it takes to make it owned/unowned per
   player with the server authoritative. Which L1/L1b/L1c rules assume it (e.g. L1c's `WallClip.Rise`, the
   wall-climb rule in check_levels, "the main path must be passable with one jump and the dash").
3. **Saving:** the profile schema version and shape today (`combat` block, Types), how L1 keeps stars
   (session memory), what a schema bump costs (migration, ProfileStore, the live game; the publish freeze on
   Expeditions until L4). What saving bought abilities + opened secrets per player would need.
4. **Currency and a place to buy:** Valor today (earned where, stored where, spent on anything?), the lobby
   camp (what UI exists there: map screen, anything else), whether the hub has a fitting screen. The smallest
   honest "buy double jump" flow with server validation and rate limits.
5. **New weapon families:** what adding a family costs end to end (Armory config, WeaponService,
   AbilityService, client fx, sim_range families, `crowd_harness`, check_stage_mirror, range dummies,
   loadout picker in the lobby), using the most recent family addition as the measuring stick. Sketch what
   a Flamethrower (short stream, hits everything in it) and a frost weapon (melee or ranged — open) would
   reuse (Beam? Spear? SMG?).
6. **World reactions:** the cleanest server-owned way for a fire hit to remove a bramble block and an ice
   hit to freeze a water strip into a walkable sheet (which hit paths exist: strikes, rays, ability areas;
   how blocks are tagged; how the crowd floor/Region would treat a new walkable surface; replication to the
   client; reset per run).
7. **The second exit / side node:** what the map screen and level list support today; the cheapest version
   of "a second way out that opens a side node" vs a shortcut on later runs vs loot only.
8. **Decisions for Ben** — only what truly needs him, each with 2–4 options, the lead-style recommendation
   and the cost of each. **Risks** in plain words. A proposed **wave split** (each wave playable on its own
   in Studio) and the owners per wave (`luau-engineer`, `ui-engineer`, `economy-designer`).

End your reply with a ten-line summary and the report path.
