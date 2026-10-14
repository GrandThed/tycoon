You are the lead engineer on Era City Tycoon (see `CLAUDE.md`). We are continuing L1b, "the living
road": Wave 1 is merged and Ben liked it; this session builds **Wave 2, "the long road"**. Read
`CLAUDE.md` and every memory file it imports, above all `.claude/memory/missions-replan-2026-10-13.md`
(its L1b paragraphs at the end) and `.claude/memory/agent-context-cost-2026-10-13.md`. Then read, in
this order:

1. `docs/MISSIONS_DESIGN.md` §15, §16 (Ben's L1b decisions) and **§17 (his verdict on Wave 1 and
   the four notes folded into Wave 2)**.
2. `docs/INTERFACES.md`: the section `# L1b contracts — the living road` to the end (Wave 1's
   contract, then "Open for later" with the Wave 2 outline, then "Review round and state
   (2026-10-14)"). Find it by grep; the file is about 12,800 lines, never read it whole.
3. `docs/PLAN.md` "## L1b — the living road" (what shipped, the gates, **the Carried list with
   owners**, Next).
4. `docs/BALANCE.md` "L1b" (how Wave 1 was measured, the residents table, the Timber flag).
5. `docs/prompts/l1b-study-report.md` §4 (population and the wire), §8 (the wave plan) and the
   lead's rulings at its end. Only those parts.
6. `docs/prompts/l1b-w1-fix-round.md` and `docs/prompts/l1b-w1-reports/lead-routing.md`, only to see
   how the last round was run and what was carried.

## Where things stand (2026-10-14)

- **Wave 1 is on `main`** (merge `5423937`, the place files rebuilt; verdict recorded in `973b41b`).
  On L1's road and camp sizes: resident groups (guard / patrol / fire), waking by sight or a hit,
  the chase to the camp's edge, the walk home (evading) and the heal, per-kill pay kept at once,
  only the Chief's Clearing locks. A Normal clear takes about 3 minutes (band 2.5–4, the lead's
  ruling for Wave 1).
- **Ben's look (Studio's log: one run on Normal, cleared in about four minutes): "feels really good
  right now!"** His notes, settled by click questions and all **folded into Wave 2** (his choice):
  1. **One sword swing per jump**; the next needs a landing; the ground slam is unchanged.
  2. **No headshot lands on the big guys** (brutes, the Colossus): a bug to find before fixing.
     First suspect: the head hit shape against the drawn model of large kinds.
  3. **The bow felt weak, but he played at 2 / 1** (Broadsword tier 2, Longbow tier 1). The starting
     preset becomes **2 / 2**. Weapon numbers do not change, so the Colossus and the Warlord keep
     their tuning. He judges the bow again after.
  4. **"Agro range double" = nearby groups join in:** when a group wakes, every resting group of the
     same camp within twice its own sight wakes too (a new pure rule in `CampBrain`, with harness
     cases and mutations).
  5. The end screen (coins flying in, items piling up) is **L4**, not this wave.
- **Wave 2 itself** (the outline in the contract's "Open for later", decided by Ben in §16):
  - the 1,000-stud road, every camp inside the wire's ±1,000 studs;
  - camps of about twice L1's area (A about 85 × 85, B about 141 × 133, C about 115 × 115);
  - 100 to 120 residents on Normal;
  - a reinforcement tent per camp once it is awake;
  - dormancy for far resting camps (not stepped, not sent);
  - a sneak path that a careful player can take;
  - a first Normal clear of about 10 minutes, with Hard and Brutal gated again and the pay bands
    back;
  - the `[Perf]` number in the boss room, which only Ben can read.
- **Carried into Wave 2 with owners:** PLAN "L1b" Carried. Among them:
  - a shared pure flat-distance-to-rectangle helper, used by `CampBrain` and `InputController`;
  - the auto-fire at held residents during the boss room's countdown;
  - `check_stage_mirror` comparing `StandsUp`;
  - post spacing gated beyond fires;
  - the director's merge test with residents alive;
  - parties: residents do not scale with party size.
- **The worktree** `C:\Users\benja\Desktop\tycoon-p5` (with an `assets` junction) holds the merged
  branch `l1b-living-road`. Make a new branch from `main` there (for example `l1b-wave2`), or a new
  worktree; remove the junction first if you remove a worktree.
- **The publish freeze holds:** the Expeditions place must not be published from `main` until L4.
- Check `git status -sb` for push status; never report it from memory.

## Decisions that are Ben's (ask with ASCII previews in the question tool; he decides in one click)

1. **The layout before any balance:** a top-down render or ASCII plan of the 1,000-stud road with
   the three bigger camps, the tents, the sneak path and where each group rests. Pictures before
   contracts, as for every city layout. Show the arithmetic beside it: residents per difficulty
   against the 160 cap, Parts against 600, the wire range.
2. **The tents:** how many reinforcements, how fast, and whether a tent can be destroyed to stop
   them. Know what "all" costs before offering alternatives: offered several, he takes all of them.
3. **A camp's clear bonus:** still unanswered (0 today; a config number).
4. **The merge rule:** it held for Wave 1 ("each step that passes review and QA is merged to
   `main`"). Assume it holds, and say so once.

## How to work (what the last sessions taught)

- **Investigate the headshot first,** read-only, with one fresh agent: where the server judges a
  head on a crowd body (`HitShapes`, the strike path, the kinds' sizes) against how
  `CrowdRenderer` draws a brute and the Colossus, and why no crit landed. Its answer goes into the
  Wave 2 contract.
- **Contract next.** One fresh Opus agent drafts `## Wave 2` under the L1b section of
  `docs/INTERFACES.md` from these files. The lead reads its rulings, Types, ownership and checklist
  before anyone builds, and confirms or changes every point the draft flags. This worked for Wave 1.
- **Fresh agents, files first.** Never resume an agent that has done a long task. Put every brief,
  list of findings and routing ruling in a file in the repo. Two Wave 1 agents died on the session
  limit and fresh agents continued from `docs/prompts/l1b-w1-continue.md` with nothing lost. Keep a
  `lead-routing.md` for the wave and write rulings into it as they are taken.
- **Owners as Wave 1** (luau-engineer A the crowd, B the run, ui-engineer the client,
  economy-designer the data, the sims, the checkers and BALANCE), disjoint files. Small one-file
  fixes the lead may do itself (Wave 1's Types field, the ReturnService line, the clear band, the
  two fix-diff minors).
- **Reviews:** four Opus reviewers in slices (crowd, run, client, data and tests), about 1.9M
  tokens. Wave 1's found 0 Critical, 4 Major and 15 Minor. Then one reviewer on the fix diff. Tell
  Ben the cost when you plan it.
- **Pure rules are tested; executors are read.** Every new rule goes in a pure module with a
  harness case and a mutation.
- **What Ben judges must be what Play opens on**, with a short key-only checklist. Check Studio's
  log (`%LOCALAPPDATA%\Roblox\logs`: `open place`, `[Combat] booted`, `[WaveService] run ended`)
  before recording a verdict. His short answers approve what was just proposed; they are a Studio
  verdict only when he describes what he saw.
- **No sound in combat. No on-screen attack button on phones. Phones must work.**

## Gates (every QA pass)

The list in INTERFACES "L1b contracts" → "Gates" (14 items), plus whatever Wave 2 adds:
- `stylua`, `selene`, both sourcemaps and `luau-lsp analyze` (hub and combat) with the committed
  definitions;
- `py tools/check_compile.py`;
- the three rojo builds;
- `check_levels`, `check_stage_mirror`, and the three sims with `--check`;
- the crowd harness, then `mutate.py`, never together (in the worktree pass
  `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`);
- the hub and the range untouched;
- `gen_asset_manifest --check`.

Every Bash call of an agent in a worktree starts with `cd <worktree> &&`. Give `qa-runner` the
exact commands in batches, with `; echo "EXIT=$?"`, and tell it that it must end with its report.
After a merge, rebuild the six place files on `main`: test, combat, proving (`py
tools/proving_project.py` first), boomtown, metropolis, orbital.
