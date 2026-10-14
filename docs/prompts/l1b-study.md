# L1b groundwork study — brief

Read-only study for L1b "the living road". **No code changes.** Write the report to
`docs/prompts/l1b-study-report.md` in this worktree (`C:\Users\benja\Desktop\tycoon-p5`, branch
`l1b-living-road`) and commit nothing. Write findings to the report as you go, section by section,
so a cut-off loses nothing.

## Read first

- `CLAUDE.md` (code rules) and `.claude/memory/missions-replan-2026-10-13.md`.
- `docs/MISSIONS_DESIGN.md` §5, §12 (Forest Road), §15 (Ben's verdict) and **§16 (Ben's L1b
  decisions: these are fixed; plan to them, do not re-open them)**.
- `docs/INTERFACES.md` from `# L1 contracts — Forest Road in grey` to the end (grep for the
  heading; the file is about 11,000 lines, never read it whole).
- `docs/BALANCE.md` sections starting `## L1:` (layout, values, results, rewards).
- `docs/prompts/l1b-living-road.md` "What it means technically".

## Questions to answer, each with file:line evidence

1. **One live camp.** Everything that assumes one floor rectangle and one floor height per server:
   `CrowdService` (`SetBounds`, clamp, integrate, spawn, summon), `CrowdBrain.BeginStep` (floor,
   arena centre and half-size for runway and retreat), `ThreatField`, `VitalsService`
   (`strike.floorY`), `HitShapes`, the client's `CrowdRenderer.SetFloor`, and `StageFlow` /
   `LevelService` / `WaveService` / `LevelGeometry`. For each: what changes for a floor and a
   rectangle **per group** (a camp part), and the smallest shape that works. Is per-group enough,
   or does anything need per-body?
2. **Resting, waking, leashing.** What exists today (`behaviour`, brains, `perPlayer` turn-taking,
   `keepAway`) and what is needed for: guards at posts, patrols on loops, raiders sitting at fires
   (a state the client can draw, slow to stand), waking on sight within a radius / on being hit /
   when a group-mate wakes, chasing to the camp's edge and walking home to heal. Where the state
   bits go on the wire (`CrowdCodec`, 11 bytes per enemy today). Where the pure rules should live
   so the harness can test them (a new pure module is preferred).
3. **Rewards per kill, kept at once.** How rewards are pooled and banked today (the stage pool,
   checkpoints, `bankEachWave`, the summary, the profile write path) and what changes so every
   kill is kept the moment it falls, for the party ("by the amount killed by the party"). How
   often that writes to the profile, and whether that is safe for DataStore budgets. What a
   checkpoint still does once it banks nothing.
4. **Population and the wire.** For three camps each about twice L1's floor (A 60 × 60, B about
   104 × 88, C about 84 × 72 in L1), 30 to 40 raiders per camp in groups plus a reinforcement
   tent, about 100 to 120 raiders in the level, a road about 1,000 studs: bodies alive, bodies
   that must be stepped, bytes per second per player with dormant far bodies not stepped and not
   sent, against `crowd.maxAlive` 160, the 64-entry packets at 15 Hz, the codec's ±1,024 studs,
   `levels.maxParts` 600. Is a dormant state needed; if so, the rule (distance to every player,
   awake groups never dormant) and where it lives.
5. **The boss room.** What of L1's close (trigger on the fenced rectangle, the wall at the floor's
   edge, the close moving anyone near the edge to the entry, the grace re-judge) can stay as is
   when every other camp is open, and what must change. Does "you cannot leave the level" need
   anything beyond the boss room's wall (Abandon still works)?
6. **What the simulators, `check_levels.py`, `check_stage_mirror.py` and the crowd harness
   (`tools/crowd_harness/`) mirror today** that these rulings break, and what each must learn.
7. **Risks.** Code the P4/P5/L1 reviews hardened that this touches (name the review ruling);
   anything that looks expensive on the server step (budget 2 ms, never measured with a boss);
   phones.
8. **A proposed wave plan** for L1b: two to four waves, each with a playable stop Ben judges by
   pressing Play in `build/proving.rbxl` (he does not use panels or long checklists), and the
   owner split (luau-engineer server/shared, ui-engineer client, economy-designer configs, layout
   and balance) with disjoint files per wave. Say what is pure (tested) and what is an executor.

## Shape of the report

Short sections numbered as above. Plain sentences, numbers with units, file:line for every claim
about the code. Mark each conclusion **verified** (read in the code) or **estimated**. End with a
list of the decisions the lead must take before contracts (not Ben's: his are in §16), each with
a recommendation.

## Environment

Bash: `cd /c/Users/benja/Desktop/tycoon-p5 && ...` at the start of every call (the shell resets to
the main checkout). Python is `py`. Do not run the harness, uploads or builds; reading and grep
only (running `py tools/check_levels.py` is fine if a number needs it). Kill only your own PIDs.
