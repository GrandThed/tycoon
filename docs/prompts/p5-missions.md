# Session prompt: combat P5 (back into the missions)

Paste this into a new Claude Code session opened in `C:\Users\benja\Desktop\tycoon`. Run the lead on
Opus; every subagent on Opus (`model: "opus"`).

---

You are the lead engineer on Era City Tycoon (see `CLAUDE.md`). We are continuing the combat
rework. Read `CLAUDE.md` and every memory file it imports, especially
`.claude/memory/p4-enemy-roles-2026-10-07.md` and `.claude/memory/feel-pass-2026-09-23.md`. Then
read, in this order:

1. `docs/COMBAT_DESIGN.md`: the plan of record. P5 is §10 step 6; §9 says what of the old
   mission code is kept, re-tuned or replaced.
2. `docs/WEAPONS.md`: the roster, and how families, tiers and eras are meant to fit together.
3. `docs/INTERFACES.md`: the sections "P1 contracts", "P2 contracts", "P3 contracts", "P3.1" and
   "P4 contracts" (with "Wave 2 — roles", "Stop 2 — the Colossus", "Stop 3 — the Warlord and his
   guard"). Find them by grep; the file is very large. Then the older "C0", "C1", "C2" and "C2.5 +
   C3" contracts, for the mission side P5 lands on.
4. `docs/PLAN.md`: sections "P1" to "P4" (what shipped, known limits, the "Carried" lists).
5. `docs/BALANCE.md`: "P1" to "P4", above all "What scales with weapon tier" and the two boss parts.

## Where things stand (2026-10-12)

- **P1 to P4 are built, reviewed, QA green and on `main`.** Everything lives in the Studio-only
  test range, the Proving Grounds (`build/proving.rbxl`, `DebugProving` baked in by
  `tools/proving_project.py`; Ctrl+Shift+B "Build all"). Missions still run the OLD combat
  (`EnemyService`, `WaveService`, `CombatService`, `CombatFxController`), untouched since C2.5.
- **In the range:** 13 weapon families with A/B variants and an ability each; the P3.1 melee rule
  (a swing resolves where the client stood, the hitbox effect is drawn at once and follows);
  crowd enemies with no Humanoid (fodder, slinger, marksman, lobber, brute, plated elite); the
  player's health, i-frames, going down and getting up; two bosses with two phases (the Colossus,
  the Warlord and his guard).
- **Ben's verdicts:** P3 "i love all the wapons, we can find a way to integrate them all" (all 13
  families stay); P3.1 confirmed in Studio on 2026-10-12; the Colossus signed off the same day
  ("Great", "Nothing, all clear" on the tells, "About right" on the length, about 76 s with the
  default sword).
- **Not judged by him yet. Ask before building on them:**
  - **Stop 3, the Warlord:** merged on 2026-10-12, and Play opens on him. Studio had not been
    opened on that build when the session ended. PLAYTEST "P4 Stop 3". P4 is complete when he
    signs it off.
  - **The Stop 1 `fight` set:** the three shooters, the brutes and the plated elites. He has only
    fought fodder (the Colossus's summons). It is behind the panel: P → fight.
- **Open questions for him:** A or B for SMG, Beam and Chain Gun; whether melee kills should
  shorten the ranged ability's cooldown (cross-slot refunds); favourite and weakest ability; the
  bows on bosses (Longbow about 2.5 minutes and Splitbow about 3.5 on either boss, against under a
  minute for the rifle or SMG on the Colossus); the Server N ms readout during a boss fight or the
  `fight` set (budget 2 ms; only he can run Studio).

## How to work with Ben (learned the hard way; see the two memory files)

- **He opens `tycoon\build\proving.rbxl` after "Build all" in the main checkout, by habit.** A
  full path to another folder did not change that. So: build on a worktree branch, and merge a
  wave to `main` once it has passed review and QA, before asking him to look. He authorised that
  for P4's waves ("Merge each ready wave"); ask once whether it holds for P5.
- **He does not use the panel or follow long checklists.** Whatever he must judge has to be what
  Play opens on (`defaultSet` in the range; find the equivalent switch for missions), with a short
  key-only checklist.
- **His short answers ("it works", "good!", "feels good") approve what was just proposed; they are
  a Studio verdict only when he describes something he saw.** Studio's own log says what he ran:
  `%LOCALAPPDATA%\Roblox\logs`, the lines `open place (identifier = …)`, `loaded set "…"` and
  `Created play solo Server tab`. Check it before recording a verdict.
- **Ask with pictures and clicks.** ASCII previews in the question tool get a decision in one
  click. Offered alternatives for combat, he tends to take all of them ("lets make all of these",
  "Both, as two bosses"): know what "all" costs before offering.
- His Studio is in Spanish and menu steps are hard for him: prefer baked-in switches and keys.
- **No sound** in combat. **No on-screen attack button on phones.** Phones must work.

## P5 scope (COMBAT_DESIGN §10 step 6: "back into the missions")

Crowd waves, rebalanced rewards, co-op checks, all four eras: the range's combat replaces the old
mission combat. It is the largest step of the rework and touches persistence, rewards and
co-op, so **start with a groundwork study and Ben's decisions, not with code**:

1. A read-only study (as P4's): what the mission side is today (waves, the director, rewards and
   the damage-share split, RunTicket and admission, the Studio bridge and its levers, the Armory
   and its tiers) and what each needs so that `CrowdService`, `CrowdBrain`, `VitalsService`,
   `ThreatField` and the range's client controllers can run a mission instead of `EnemyService`
   and `CombatFxController`. Which old modules die, which are kept (COMBAT_DESIGN §9).
2. Decisions that are Ben's, asked with previews: how the 13 families and their A/B variants are
   earned and chosen ("integrate them all"); how waves and bosses are composed per era; what
   going down means in a mission (the range just stands the player up); whether the range stays
   as a place players can visit.
3. Then contracts, then waves with a playtest stop each.

**Carried into P5 from the earlier milestones** (the full lists are in PLAN):
- Enemy damage, regen, `crowd.heavyHit` and plates are flat while health grows ×17 over the weapon
  tiers; health in missions comes from the profile again (range rulings 17 and 20).
- Boss health must scale with party size, as missions already do (C2).
- Kiting a big circle avoids everything and heals: it needs an objective, a timer, a smaller arena
  or a faster enemy.
- The melee slack still trusts a capped replicated speed; before missions it must use the
  server's own position history (the slinger's led aim already does).
- Early drawing of the player's own shots and ability visuals; a cooldown carried across a family
  switch; refunds re-measured against chasing crowds; melee abilities still resolve at the
  server's position.
- `FeedbackController` is at 159 of about 180 top-level locals: group its state into tables
  before adding to it. `CrowdRenderer` is at 151.
- The follow of melee effects and the ground marks have no phone measurement.
- Cover and the stairs are not in the simulator; the crowd walks through world geometry.
- Both bosses are tuned tightly against today's weapon numbers: any weapon change means
  re-tuning them (`tools/sim_range.py --check`, 353 checks).

## Gates (run them in every QA pass)

`stylua --check src`; `selene src` (one old `LegacyPanel` warning); `luau-lsp analyze` for the hub
and for combat with fresh sourcemaps; `py tools/check_compile.py` (Studio's 200-locals limit);
the hub, combat and proving builds; `py tools/sim_economy.py --check`, `py tools/sim_combat.py
--check`, `py tools/sim_range.py --check`; and **`py tools/crowd_harness/run_harness.py`** (the
crowd server's regression harness: 492 checks on the real modules under a plain Luau
interpreter; `mutate.py` beside it proves the cases are not vacuous). Give `qa-runner` the exact
commands in three batches and tell it that it must end with its report.

## How to work (unchanged; it worked for P1 to P4)

- Contracts first, in `docs/INTERFACES.md` ("P5 contracts"), with the Types and the config's shape
  yourself. Then fan out with disjoint ownership: `luau-engineer` (server and shared),
  `ui-engineer` (client), `economy-designer` (values, simulator, BALANCE). Resume the same agent
  by `SendMessage` across waves: it keeps what it measured. A new session starts with fresh
  agents, so hand them the P1 to P4 contracts.
- Relay each engineer's "for the other owner" section yourself: the server and the client were
  built in parallel against the contract, and the differences were found by comparing reports.
- Review, then QA, then docs, then merge, then ask. The reviewer found the real problems each time
  (stacked knock hits, the hopping player, immunity on the range's furniture).
- When the simulator's reacting player gets hit by a LONGER tell, suspect its planner before the
  fight: it happened three times.
- Check a designer's result against what Ben said felt right, not only against the bands: the
  Warlord's first pass met every band with a two-minute fight he would not have liked.
