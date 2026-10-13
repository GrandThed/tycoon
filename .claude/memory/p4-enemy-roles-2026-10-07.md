P4 "enemies that fight back, in the range", started 2026-10-07 on Ben's "feels good, lets start".
Contract: `docs/INTERFACES.md` "P4 contracts" (on the branch until its first merge).

**Ben's rulings (2026-10-07, asked with ASCII previews in the question tool):**
- Armoured elites carry a **breakable plate**: only heavy hits damage it, and once it shatters
  every weapon hurts in full. This settles the P3 "SMG against armour" flag.
- Shooters: offered three attacks to pick one from, he answered **"lets make all of these"**.
  Read as three shooter enemies: slinger (slow glowing shots), marksman (warning line, then an
  instant hit), lobber (arcing shot, ground circle). Same pattern as P1 ("love all the
  alternatives"): offered alternatives for combat, he tends to keep them all, so know what
  "all" costs before offering.

**Lead's rulings, every number tunable in `ProvingGrounds.json` (Ben has not objected):**
- Two playtest stops: Stop 1 = health plus fodder, the three shooters, brute, plated elite
  (wave 1 "they hurt you", wave 2 "roles"); Stop 2 = the boss, under its own contract.
- Health is `Humanoid.Health` with `Armory.MaxHp`, as missions. It never reaches 0 in the range:
  the player goes down 2 s, then up in place. Fodder attackers per player capped at 4. One
  meaning of "heavy" (`crowd.heavyHit`, 40) for plates and interrupts. A jump dodges ground
  shapes. A `god` toggle. Passive P1 to P3 sets stay passive (behaviour `fight` runs the AI).
- The commit rule: an enemy's shape freezes at impact time T and each player is tested at
  T + lag against the server's root (where their own screen had them at T); an i-frame that
  covered any of that window voids the hit; no client-claimed dodge position.

**Session closed 2026-10-12; P5 starts in a NEW session from `docs/prompts/p5-missions.md`.**
- Everything of P4 is on `main`. The worktree `tycoon-p4` is removed and the branch
  `p4-enemy-roles` deleted (fully merged); P5 gets a new worktree.
- **Stop 3 (the Warlord) was merged but never played:** Studio's log shows no session on that
  build when the session ended, and Ben said "we are continuing to P5 in a new session". P4's
  last box is open; ask him first thing. The `fight` set is also unseen.
- The server engineer's scratch harness is kept as `tools/crowd_harness/` (`run_harness.py`,
  492 checks on the real crowd modules under `tools/bin/luau.exe`; `mutate.py` proves them).
  It is a gate from P5 on. The other agents' scratch (the client's models, the designer's
  probes) went with the session.

**Where it was built:** worktree `C:\Users\benja\Desktop\tycoon-p4`, branch `p4-enemy-roles` (gone).
- **Wave 1 is committed there (e14c4cb, 2026-10-07, local only):** review 2 Critical, 1 Major,
  10 Minor, all fixed or ruled; QA green; docs written (PLAN "P4", PLAYTEST and MANUAL_STEPS
  "P4 wave 1", a 10-step optional quick look that opens with the P3.1 melee check). Merged to
  `main` on 2026-10-08 under the gate protocol below; his look is optional and not yet reported.
- **Wave 2 ("roles") is built, reviewed, QA green and merged to `main` (2026-10-08, 893fc8a
  through the merge 2df322b); the place files are rebuilt.** The same three agents built it,
  resumed by id (they were cut off once by the session limit and resumed with nothing lost):
  the keepAway brain, `shot` / `line` / `lob` / `lane`, the plate, the `ThreatFx/` client
  folder, the simulator's five player policies (176 checks). Review 0 Critical, 1 Major, 7
  Minor. Contract: INTERFACES "Wave 2 — roles" with its rulings and review round.
- **Stop 1 waits for Ben's playtest** (PLAYTEST "P4 Stop 1", 16 steps, about 15 minutes; it
  stands alone and opens with the P3.1 melee check, because he never reported the optional
  wave 1 look; Studio was not opened between the two merges). Asked of him: which role is most
  fun and most annoying, any tell hard to read, soft or hard, how the plate feels, and the
  **Server N ms** readout in `fight` (budget 2 ms; nobody else can run Studio).
- **2026-10-12, Ben: "okey, everything feels great now, lets proceed".** Studio's log for that
  day: he ran "Build all", opened the new `proving.rbxl`, played once for six minutes with no
  script error, and **only the default set `crowd30` was ever loaded**: the passive dummies. So
  that verdict covers the build loading, the health bar and the P3.1 melee fix (its first
  real Studio look: confirmed), and **not** the fighting enemies. Told to him plainly. Two
  consequences: `defaultSet` is now `fight`, so Play alone shows P4 (he does not use the panel
  or the checklists: anything he must see has to be what Play opens on); and Stop 2 was
  started on his word, with Stop 1's enemies still unjudged by him.
- **Stop 2 rulings (Ben, 2026-10-12, asked with previews):** "Both, as two bosses" — the
  **Colossus** first (Stop 2: slam ring, charge, summon, an enraged barrage), then the
  **Warlord and his guard** (Stop 3, its own contract) — and **two phases** (enrage at half
  health). As foreseen, offered alternatives he took both. Contract: INTERFACES "Stop 2 — the
  Colossus". **Built, reviewed (0 Critical, 0 Major, 7 Minor), QA green and merged to `main`
  the same day (e9b8031 through the merge 3a94031); the place files are rebuilt and
  `defaultSet` is `colossus`, so Play opens on the boss.** Stop 2 waits for Ben's playtest
  (PLAYTEST "P4 Stop 2", 12 steps, the first nine need only Play and the keys). Numbers: 4,700
  HP; a reacting player kills it in 64 to 82 s with any melee family and takes no hit;
  standing still is down in under 9 s; the bows take minutes (a weapon question for Ben);
  boss health does not scale with players in the range. Rules: attack choice by cooldown,
  reach, phase and least recent use; a boss's death takes back everything it had in the air;
  a call tops up; `crowd.largeRadius`; `area` and `enemyShot` carry `enemyId`.
- **Stop 2 signed off 2026-10-12.** "i completed the playtest": Studio's log shows a
  six-minute session in the `colossus` set with no script error. Asked with three click
  questions: "Great, on to the Warlord"; "Nothing, all clear" on the tells; "About right" on
  the length. No Server ms number. **What worked: Play opened on the thing to judge, and the
  verdict was asked as click questions right after the log showed he had played.** The
  shooters, brutes and plated elites (the `fight` set) are still unseen by him.
- **Stop 3, the Warlord and his guard, started the same day** (contract: INTERFACES "Stop 3"):
  a siege then a duel — he keeps away, calls a guard of four plated elites once, throws
  barrages, and his plate cannot be damaged while any guard lives (`guarded`); when his plate
  breaks he enrages (`enrage.at` 1, the existing latch) and closes in (`enrage.brain`). New
  general keys: `calm`, `uses`, `guarded`, `enrage.brain`. **Built, reviewed (0 Critical,
  0 Major, 5 Minor), QA green and merged to `main` the same day (92413bd through the merge
  56329e6); the place files are rebuilt and `defaultSet` is `warlord`, so Play opens on him.**
  Stop 3 waits for Ben's playtest (PLAYTEST "P4 Stop 3", 11 steps, the first eight key-only);
  **P4 is complete when he signs it off; P5 (back into the missions) only on his word.**
  Numbers: guard 4 × 1,400 HP with one-hit plates, his plate 385 and 3,650 HP; a reacting
  melee player wins in 77 to 101 s (guard about 26 s, plate under 20 s, duel about 55 s);
  SMG and Beam need the ground slam and are slow; the bows take minutes. Rulings: guarded from
  his first moment until the guard is called and dead; a plate break always reels (also for
  `knockbackMult` 0); `summonerId` on spawns; `crowd.largeRadius` 2.5. The first balance pass
  met its own bands with a two-minute fight whose middle was 38 s of hitting a retreating
  plate: the lead retargeted to the length Ben called "about right" on the Colossus. **Check
  a designer's result against what the owner said felt right, not only against the bands.**
  The tuning is tight (Spear floor, Beam ceiling, Broadsword plate phase): any weapon-number
  change means re-tuning this boss.
- `main` was fully on origin on 2026-10-12 18:16 (the editor's sync had pushed it).
- A lesson from the simulator, three times now: its reacting player judged jumps a frame off
  from the server and "passed" or "failed" by luck. When a longer tell makes the simulated
  player get hit, suspect the planner before the fight.
- Wave 2 rulings worth knowing before touching the code: enemies of one kind take turns
  (`CrowdKindDef.perPlayer`: fodder 2, the others 1; it replaced
  `crowd.threat.attackersPerPlayer`); a locked facing is snapped to the wire's yaw step; a
  slinger's aim is led over flight plus the player's lag in six passes (`lead` 1 = where they
  will be); the marksman's line has no height rule and locks 0.55 s before the hit; high
  ground protects from melee and ground shapes only (shots, the line's 3D ray and the lob's
  floor all reach a player on a block); a shot's path is cut by one ray at fire; plate and
  health are separate entries on a strike.
- Known limits told to Ben: kiting a big circle avoids everything and heals (P5: objectives);
  elites are a time tax for a player who keeps swinging; enemies walk through cover; the
  marksman's wall is drawn through cover; shots at a brute in mid-charge are judged up to 3.7
  studs behind where it is drawn. Not in the simulator: cover and the stairs.
- The branch `p4-enemy-roles` and worktree `tycoon-p4` stay for Stop 2 (the branch now holds
  a merge of `main`, so the next merge to `main` is a fast-forward).
- Rulings added on the way (16–26 in the contract): fodder cap 2 (not 4), lunge windup 0.6,
  range health pinned at tier 1 (130), a knock voids the other hits decided with it, `reach`
  on the flat, a due impact is never lost, `hurt` leaves in its own frame, a dash away from an
  attack aimed at you reads as "DODGED". Expected at the look: you only lose health when you
  stop attacking, and hopping avoids most fodder hits (the shooters are the answer).
- Stop 2 (the boss) gets its own contract after Ben's Stop 1 verdict.

**Gate protocol, authorized by Ben on 2026-10-08:** asked with three options, he chose **"Merge
each ready wave"**: every P4 wave that has passed review and QA is merged to `main` and the
place files rebuilt, without asking again, so "Build all" always gives him the newest version
(he opens `tycoon\build\proving.rbxl` by habit). This covers P4's waves in the range; it is not
a general licence to merge other work. The first P4 look opens with the P3.1 melee check he
never confirmed in Studio.

**Facts from the groundwork study (no need to re-derive):**
- The crowd steps and sends at 15 Hz; 11 bytes per enemy; the snapshot header carries server
  time, so tells can be drawn against it. `CrowdService.Get` allocates per call.
- `RangeService.broadcastFx` sends one remote call per effect per player: batch threat effects.
- `separate()` scans more cells the wider the widest living body is: fix before the boss.
- `FeedbackController` is at 166 top-level locals: new behaviour goes in new modules.
- `CombatFxController` runs in the range and handles the mission kinds `telegraph`, `playerHit`,
  `playerDown` with mission visuals: the range uses new kinds (`hurt`, `enemyShot`, `area`).
- The crowd ignores world geometry (enemies walk through cover).
- A dash is accepted every 0.64 s, up to 39% i-frame uptime.
- No server step time has ever been recorded; only Ben can read it off the panel (budget 2 ms).

**Why:** a fresh session would otherwise re-ask the two questions, re-run the study, or hand Ben
a build in a folder he does not open.

**How to apply:** read the P4 contract first; check the worktree's `git status` for what is
done. See [[feel-pass-2026-09-23]], [[studio-compile-gate-2026-10-02]], [[combat-2026-09-17]].
