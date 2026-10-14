# Session prompt: L1b, the living road (after Ben's L1 verdict)

Paste this into a new Claude Code session opened in `C:\Users\benja\Desktop\tycoon`. Run the lead on
Opus; every subagent on Opus (`model: "opus"`), and a FRESH subagent for every task (see "How to
work").

---

You are the lead engineer on Era City Tycoon (see `CLAUDE.md`). We are continuing the Expeditions
re-plan. Read `CLAUDE.md` and every memory file it imports, above all
`.claude/memory/missions-replan-2026-10-13.md`, `.claude/memory/agent-context-cost-2026-10-13.md`
and `.claude/memory/p5-missions-2026-10-12.md`. Then read, in this order:

1. `docs/MISSIONS_DESIGN.md`: the plan of record for the mission layer, with Ben's L1 verdict in
   "§15 Ben's verdict on L1".
2. `docs/INTERFACES.md`: the section `# L1 contracts — Forest Road in grey` to the end, with its
   "Review round and state". Find it by grep; the file is about 11,000 lines, never read it whole.
3. `docs/PLAN.md` "L1 — Forest Road in grey" (what shipped, the gates, the Carried list with owners).
4. `docs/BALANCE.md` "L1" (how the numbers were measured, and their limits).
5. `docs/prompts/l1-fix-round.md`, only to see how the last round was run.

## Where things stand (2026-10-14)

- **L1 is merged to `main`** (merge `736a98a`, then `2603c65`) and the six place files are rebuilt.
  The dungeon place boots into a lobby camp with a path map. The leader departs to Forest Road: a
  road with one big raider camp in three parts (A pickets, B main camp, C the chief's clearing),
  the Colossus as a stand-in boss, three difficulties, a checkpoint at each camp's clear, a summary,
  and back to the lobby. Grey blocks only.
- **How a camp works in L1 (what Ben rejected):** a camp is empty until a fighter walks in; then a
  3-second countdown, the gates close, an invisible wall holds everyone in, and enemies arrive in
  bursts from the camp's edge. Only one camp is live at a time, because the crowd has ONE floor
  rectangle and ONE floor height per server (`CrowdService.SetBounds`, which refuses while a body
  lives).
- **Gates at the merge:** crowd harness 1,292 checks (its verdict line names the count and the
  folder: `HARNESS: PASS (1,292 checks, <folder>)`), `mutate.py` 417 mutations with 0 not caught,
  `tools/check_levels.py` 123 checks, `tools/check_stage_mirror.py` (the real `StageFlow`,
  `Combat` and `LevelGeometry` under `luau.exe` against the simulators, about 5,600 comparisons),
  `sim_economy`, `sim_combat` (21), `sim_range` (412) all green.
- **The worktree** `C:\Users\benja\Desktop\tycoon-p5` (with an `assets` junction) holds the merged
  branch `l1-forest-road`. Reuse the folder with a new branch from `main` (for example
  `l1b-living-road`), or make a new worktree; remove the junction first if you remove a worktree.
- **The publish freeze holds:** the Expeditions place must not be published from `main` until the
  step that makes the real forest and puts the map in the city (L4 in MISSIONS_DESIGN §14).
- `main` was 21 commits ahead of `origin/main` at the end of the last session. Check `git status
  -sb`; never report push status from memory.

## Ben's verdict on L1 (2026-10-14), in his words

> "looks good! one thing i was ambisioning that wasnt in this build is that i was hopping for the
> enemies to already be there all the time, with bigger camp sites, and longer roads, i mean, it
> is an experiment after all just saying, and something i really didnt like is the fact that you
> are closed off from leaving when entering a zone, i was ambisioning that the only zone that
> remainds closed is the final room with the boss so you cannot leave the level nor the boss zone.
> [...] everything else was allright from a technical demo standpoing"

Studio's log for that look: he opened `tycoon\build\proving.rbxl` at 00:22, played Forest Road on
Normal once, and the run ended "down" in stage 2 (camp A) about two minutes after boot. He did not
reach camp B, the boss, Hard, the Raider Arena or the phone check. Asked about it afterwards, he said
**"balance feels good"**: keep L1's numbers as the starting point for L1b's camps.

**What it means:**
1. **Enemies are already there.** A camp is inhabited when you arrive; you see the raiders before
   they see you. No empty camp that fills in bursts.
2. **Camps do not lock.** You walk in and out of every camp freely. **Only the boss's room locks**:
   once you enter it you cannot leave it, nor the level, until the boss falls or the run ends.
3. **Bigger camp sites and longer roads.**
4. Everything else in L1 stands: the lobby camp and the map, the difficulties, checkpoints banking
   rewards, the summary, the return to the lobby, the stage rules being pure and tested.

This reverses one of Ben's own rulings of 2026-10-13 ("fights happen inside flat camps whose gates
close until the camp is clear"). Say that back to him plainly, once.

## What it means technically (verify each in the code before you plan on it)

- **Several camps alive at once.** Today the crowd has one floor rectangle and one floor height for
  the whole server, set at each camp's trigger with no body alive. Resident enemies in camps at
  different heights need a floor and a rectangle per body or per group: `CrowdService` (clamp,
  integrate, spawn, summon), `CrowdBrain.BeginStep` (the floor, the arena centre and half-size for
  the runway and the retreat), `ThreatField` and `VitalsService` (`strike.floorY`), the client's
  `CrowdRenderer.SetFloor` (one floor today). This is the largest item and it touches the code the
  P4 and P5 reviews hardened.
- **Enemies that wait.** Every body today hunts the nearest player from the frame it spawns
  (`behaviour = "fight"`). Resident enemies need a resting state (guard, patrol, sitting at a fire)
  and a rule for waking (sight, distance, a shot, a neighbour waking), and a LEASH: the crowd walks
  through walls and stands only on its flat camp floor, so it cannot follow a player down a road with
  slopes and ledges.
- **Kiting comes back.** L1 closed the camps partly because running in a circle avoided every hit
  and healed. With open camps a player can run out, heal and come back. That needs Ben's rule
  (below), not a guess.
- **Bodies far from any player.** Several inhabited camps hold many more bodies than one live camp.
  `crowd.maxAlive` is 160 per server; snapshots are 64-entry packets at 15 Hz; the server step
  budget of 2 ms has never been measured with a boss. A dormant state (not stepped, not sent) for
  bodies far from every player is likely needed.
- **Longer roads.** Snapshots are encoded against the world origin as 16-bit numbers at 1/32 stud:
  about ±1,024 studs. Forest Road spans about 550. A longer road needs every camp to stay in range,
  or per-zone origins in the codec. `levels.maxParts` is 600 (Forest Road builds 73).
- **The stage flow.** `StageFlow` (pure, tested) is built around trigger, countdown, close, waves,
  clear. Without gates: what is a camp's "clear", what is a checkpoint, and what banks? The boss
  room keeps L1's close (trigger on the fenced rectangle, the wall at the floor's edge, the close
  moving anyone near the edge to the entry, the grace re-judge). The Raider Arena is a one-camp
  level that locks today; decide whether it keeps that.
- **The simulators and both checkers** (`check_levels.py`, `check_stage_mirror.py`) mirror the stage
  flow and the layout rules: they change with it, in the same wave.

## Decisions that are Ben's (ask with ASCII previews in the question tool; he decides in one click)

1. **Running away mid-fight:** the raiders chase to the camp's edge and go back and heal; or chase
   to the edge and stay angry; or follow you down the road (only possible on flat road).
2. **A cleared camp:** stays empty for the run; or refills after a while.
3. **What saves progress now that camps do not close:** a camp's last raider; a campfire or a flag
   you touch; only the boss.
4. **Raiders at rest:** standing guard; walking a patrol; sitting at fires and waking.
5. **Size:** how long a first clear on Normal should take (L1: about 6.5 minutes), how many camps,
   how big. Show him the arithmetic (bodies alive, the wire range, the Part count) next to it.
6. **Can you sneak past a camp?** If yes, what does clearing it give (rewards, the checkpoint,
   a secret)?

Offered alternatives in combat, he tends to take all of them ("lets make all of these", "Both, as
two bosses"): know what "all" costs before offering, and say it in the option.

## How to work (what the last two sessions taught)

- **Start with a read-only groundwork study, not with code.** One fresh Opus agent: what in the
  crowd, the brains, the vitals, the codec, the client renderer and `StageFlow` assumes one live
  camp; what resident, waiting, leashed enemies need; the body counts and bandwidth for a road of
  three to five camps; what the boss room keeps from L1. Then Ben's decisions, then contracts in
  `docs/INTERFACES.md` ("L1b contracts"), then waves with a playtest stop each.
- **Fresh agents, files first.** Never resume an agent that has done a long task; its whole
  transcript is replayed on every step, and four such agents hit the session limit at once on
  2026-10-13 (one near 1M tokens). Put every brief and every list of findings in a file in the
  repo (the contract, a fix-round file like `docs/prompts/l1-fix-round.md`), keep prompts short,
  and resume an agent only for a short follow-up on what it has just done.
- **Reviews:** four Opus reviewers in slices (the run, the world, the client, the data and tests)
  found 9 Majors in L1 that one reviewer would have missed, at a cost of about 1.9M tokens. Use
  slices at a milestone, one reviewer for a fix diff, and tell Ben the cost when you plan it.
- **Pure rules are tested; executors are read.** Every new rule goes in a pure module (`StageFlow`,
  `LevelGeometry`, or a new one) with a harness case and a mutation; `WaveService`, `ArenaService`
  and the client only execute. The reviews found the real bugs in the executors, which no test can
  load.
- **What Ben judges must be what Play opens on**, with a short key-only checklist (he does not use
  panels or long lists). Check Studio's log (`%LOCALAPPDATA%\Roblox\logs`: `open place`,
  `[Combat] booted`, `[WaveService] run ended`) before recording a verdict. His short answers
  approve what was just proposed; they are a Studio verdict only when he describes what he saw.
- **Merge rule:** each step that passes review and QA is merged to `main` and the six place files are
  rebuilt, so "Build all" gives it to him (his "Yes, start", 2026-10-13). Ask once whether it holds
  for L1b.
- **No sound in combat. No on-screen attack button on phones. Phones must work.**

## Gates (every QA pass)

`stylua --check src`; `selene src` (one old `LegacyPanel` warning); fresh sourcemaps and
`luau-lsp analyze` for the hub and for combat with `--definitions=tools/types/globalTypes.d.luau`;
`py tools/check_compile.py` (about 180 top-level locals per module at most);
`git diff --stat main -- src/server src/client` (the city hub stays untouched apart from shared UI);
the three rojo builds; `py tools/check_levels.py`; `py tools/check_stage_mirror.py`;
`py tools/sim_economy.py --check`, `py tools/sim_combat.py --check`, `py tools/sim_range.py --check`
(the gate is the Python its shebang picks, 3.12); `py tools/crowd_harness/run_harness.py <root>
<luau.exe>` then `py tools/crowd_harness/mutate.py <root> <luau.exe>`, never together (in a worktree
with no `tools/bin/luau.exe`, pass `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`). Every Bash
call of an agent working in a worktree starts with `cd <worktree> &&`: the shell's directory resets
to the main checkout, and a harness run from there reads another checkout's tests (it now refuses).
Give `qa-runner` the exact commands in batches and tell it that it must end with its report.

## Carried (the full list with owners is PLAN "L1")

Before any publish of the Expeditions place: the dash i-frame exploit (OnDash grants i-frames on the
request alone). Later steps: the lookout against Leap Smash and the bought double jump (L2, secrets
and keys); the Armory and the profile shape, Hard's and Brutal's rewards as placeholders (L3); the
arena's clear time and merged-wave bank, a better simulated human (it is only ever hit by slinger
shots), scenery and the Camp Chief, deleting dead code, phone measurements (L4); parties, revive,
joining late, leadership from an unverified hint, a gamepad key for the map and Abandon, a way out of
a boss fight on touch (L5).
