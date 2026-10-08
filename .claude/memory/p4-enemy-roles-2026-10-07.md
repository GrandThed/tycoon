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

**Where:** worktree `C:\Users\benja\Desktop\tycoon-p4`, branch `p4-enemy-roles`.
- **Wave 1 is committed there (e14c4cb, 2026-10-07, local only):** review 2 Critical, 1 Major,
  10 Minor, all fixed or ruled; QA green; docs written (PLAN "P4", PLAYTEST and MANUAL_STEPS
  "P4 wave 1", a 10-step optional quick look that opens with the P3.1 melee check). Merged to
  `main` on 2026-10-08 under the gate protocol below; his look is optional and not yet reported.
- **Wave 2 ("roles") was handed to the same three agents right after**, resumed by id with
  their context: the keepAway brain, `shot` / `line` / `lob` / `lane`, the plate, a
  `ThreatFx/` client folder, the simulator's new players. Its contract is INTERFACES "Wave 2 —
  roles"; the lead's starting config for the four new kinds is uncommitted in the worktree.
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
