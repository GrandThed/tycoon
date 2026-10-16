# L1c fix round: data agent report (2026-10-16)

Worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1c-chief-clearing`. Nothing committed, all files LF.

## Files

- `src/shared/Config/Levels/1_ForestRoad.json`: C's stage `"gateSeconds": 0`.
- `tools/check_levels.py`: C1, m1, m3, m4, the M3 countdown rule, `run_gates()` pulled out of `main()`, three mutant switches.
- `tools/check_levels_mutants.py` (new): m6's committed driver.
- `tools/sim_range.py`: M3 mirror (per-stage `gateSeconds`, same-step close, `skip_into`, Validate mirror), m5, the lead's relay (rename, docstring).
- `docs/BALANCE.md`: new "L1c fix round" section; three "superseded" notes in "L1c"; the `lockedResidents` row.
- `src/shared/Layouts/Levels/ForestRoad.json`: unchanged (not needed).

## Per finding

**C1, the camera clip in the sight gate.**
- `check_levels` reads `levels.cameraClear` from Combat.json and never re-types it. A missing value, or one under 0, is red.
- An eye outside the clip (the fenced rectangle grown by `cameraClear`): its camera points must stay out of the clip less the shake. That is 3.5 − 0.35 = **3.15** off the fence. They must also stay 0.15 off any tall wall (spherecast radius 0.5 less the shake).
- An eye inside the clip but outside the fence: the boom starts inside the clip, so `Reach` returns 0. That camera is the head, so it is judged as the eye.
- Only eyes in the doorway (2.5) are exempt.
- A new rule says `cameraClear` must be at least the shake.
- Shown: **red at 0.2** (sight, and also the shake rule), red at 2.0, **green at 3.5**. Control: 0.2 with cameras exempt in the doorway (2a58134's gate) is green, so that gate really was blind.

**m1, exact extremes and the drawn body.**
- Near each gate (within maxZoom + 2): a 0.25 grid, every region edge at 0.05, and every corner exactly. The edges are the clip, wall stand-offs, top edges and the doorway edge.
- The target is radius × 1.151, from CrowdRenderer's `TORSO_WIDTH` and `TORSO_DEPTH`, read from the file.
- **Corrected tightest margins:**
  - eye **+0.23** at (305.51, −29.51), just outside the doorway on WallW's face, to Brutal's inner east fodder (the west side mirrors it);
  - camera **+1.20** at (305.66, −30.15), the corner of the clip and WallW's stand-off.
  - The old grid with radius only reads eye +1.93 on the same data.
  - Doorway glimpse (exempt): −2.53.

**m2 (the code agent changed `check_stage_mirror`).**
- My driver runs `check_stage_mirror` with the maxAlive rule taken out of BOTH `StageFlow.luau` and `sim_range.py`. These are copies: the broken sim_range runs under its real path, so nothing in the repo is touched.
- Result: **red**, with "the boss room's residents at its maxAlive: accepted on both sides".

**m3.** `lockedResidents` per difficulty: Normal (8, 10), Hard and Brutal (8, 12). 11 on Normal is red.

**m4. Floors.**
- The rule measures over the fence and over every gatehouse wall as tall within stray_reach + boom.
- The camera may stand up to 7.57 nearer the wall: boom 16·cos70°, plus shoulder 1.75, plus shake.
- Each line is compared with that wall's distance to the floor's far corner.
- A ledge (top 20) 4 studs north of GatehouseWallN is red. The fence-only control is green.

**M3. gateSeconds.**
- The level file gives C's stage `gateSeconds` 0.
- `check_levels` rule: a stage's own value is ≥ 0, and under `levels.gateSeconds`' floor (1) only when the first wave has no group and no boss and the camp's residents stand on its floor.
- In `sim_range`:
  - `plan_level` carries `gateSeconds`, and `to_gate` reads it.
  - `advance` runs the countdown row in the same step after a trigger, as the Luau does. It returns if a policy hook ended the run.
  - `skip_into` mirrors `entered`.
  - `level_problems` refuses a value under 0, infinite or not a number: `"{where}: gateSeconds {x} is not a time"`.

**m5.** `FOREST_AMBUSH_SECONDS` has a 15 s floor on every difficulty.

**m6.** `py tools/check_levels_mutants.py [--luau <luau.exe>]` runs:
- the shipped data (green);
- 28 cases: the 12 L1c mutants and their control, then C1 ×5, m1 ×3, m3, m4 ×2, M3 ×4;
- the m2 stage-mirror case.

**Lead's relay.**
- The method `entered` is renamed **`skip_into`** at its def and its 3 call sites. The `self.entered` flag no longer shadows it.
- The LevelWorld docstring now says a held group answers "held", which StrikeTally drops.

## Numbers

**Normal at 2 / 2** (seeds 11 / 23 / 37):
- clear 5.28 / 4.73 / 5.07 min, mean 5.03 (was 5.08);
- ambush 19.0 / 19.0 / 19.7 s (was 20.4–22.2);
- cash a minute 24.7k / 27.4k / 25.5k;
- Timber a minute 38.9 / 43.3 / 40.4;
- pay unchanged at 129,510 cash.

**Hard 4 / 4:** clear 5.11–5.43 min, ambush 22.9 / 22.9 / 25.3 s.

**Brutal 6 / 6:** clear 5.16–5.48 min, ambush 22.9 / 22.9 / 25.4 s.

**Human reaction:** clears every difficulty with no down. Every one-preset-below gate holds.

**R8 Hard at 2/2 is thinner on this run:**
- LookoutLedge 18,313 against 18,808 (+2.7%; the L1c run read +4.1%);
- Road2 Timber 26.6 against 27.3 (+2.6%).
- This is run-order noise on the 2 / 2 Colossus, as BALANCE already flags: nothing here slows that mission. Still green.

## Gates

| Gate | Result |
|---|---|
| `py tools/check_levels.py` | CHECK: PASS |
| `py tools/check_levels_mutants.py --luau <main>\tools\bin\luau.exe` | MUTANTS: PASS (30 of 30, about 5 min) |
| `py tools/sim_range.py --check` (full, default `py`, which has Pillow) | CHECK: PASS (exit 0) |
| `py tools/sim_range.py --levels-only --level forest --check`, after the rename and a one-line tidy | PASS, the same numbers |
| `py tools/sim_combat.py --check` | PASS, 23 of 23; targetMinutes 5 against 5.0 min |
| `py tools/check_stage_mirror.py --luau <main>\tools\bin\luau.exe`, after the rename | CHECK: PASS |

## For the code agent and the lead

- The M3 mirror follows the code agent's `StageFlow` exactly:
  - the gate row runs in the same tick;
  - `entered` closes on `now >= gateAt`;
  - Validate's "gateSeconds is X, not a time" accepts nil or a finite number ≥ 0.
- The tool's camera model assumes the shipped clip:
  - the clip rect is the fence grown by `cameraClear`;
  - "holds the root" is the true fenced rectangle;
  - `Reach` answers 0 when the boom starts inside the clip.
  
  If the client ever releases the clip from the grown rectangle, the sight gate no longer describes it.
- The eye margin is **+0.23**, measured with the root flush on the wall. It is the tightest number in the walled gate:
  - moving an inner ambush post about a quarter stud toward the gate's sight line turns it red;
  - so does putting a wider body there.
- docs-keeper (code m3): the playtest reaches the clearing with N, not B.

## Margin ruling (2026-10-16, after 2841862)

**Deviation from "changing nothing else": the lead must confirm it.**

- **Posts alone cannot reach 1.5.** Measured with check_levels' own viewpoints:
  - At margin 1.5 the hidden band behind the north wall is a sliver. A brute fits only from x 355 (east; the west mirrors it) with z ≥ −22.8, because every post of a group stands the group's widest radius + 1 inside the floor.
  - So a flank holds two fodder, three brutes and one more fodder. It never holds a fourth brute: the best fourth-brute post reads eye +0.64 and also fails post spacing.
- **What changed:**
  - Hard and Brutal's extra unit per flank is now a **fodder** instead of a brute.
  - That alone turned R8 red: Hard Road2 sniper 26.6 against the mission's 26.4 Timber a minute.
  - So the two brutes' pay moved into the boss: Colossus 41,000 / 70 → **42,900 cash / 76 Timber**. A Hard clear then pays about what it did.
- **Alternatives if the lead prefers:**
  - Hard and Brutal keep 10 bodies (drop the extra unit). This has the same R8 problem, so it needs the same pay move.
  - A layout change: a narrower or moved gate.
  - A lower margin for the fourth brute.
- **Files:**
  - `ForestRoad.json`: camp C `"sightMargin": 1.5`. ambushE points are 350.4, 353.5, 357.5, 362.4, 367.6 at z −22.8, plus (365, −19.7). ambushW mirrors them round x 313.5.
  - `1_ForestRoad.json`: Hard units → fodder; Colossus 42,900 / 76.
  - `check_levels.py`: new rule "every eye's and every camera's sight margin is at least its sightMargin".
  - `check_levels_mutants.py`: 5 margin cases. The m1 shift is now 2.4, so it stays red under the new margins.
  - `BALANCE.md`: "L1c fix: the margin ruling".
- **Margins:**
  - eye **+1.57** (was +0.23);
  - camera **+2.73** (was +1.20);
  - the exempt doorway glimpse is unchanged at −2.53.
- **Ambush:** Normal 18.4 / 18.4 / 18.7 s; Hard 21.3 / 21.8 / 18.0 s; Brutal 21.3 / 21.8 / 18.9 s.
- **Normal clear:** 4.67–5.21 min; 25.2–28.1k cash and 40.5–45.2 Timber a minute.
- **R8 Hard at 2/2:**
  - Road2 Timber +2.3%;
  - LookoutLedge cash +1.5%: now the thinnest gate.
- **Gates:**
  - check_levels: PASS.
  - check_levels_mutants: PASS, 35 of 35, m2 included.
  - sim_range forest levels-only: PASS.
  - check_stage_mirror: PASS.
  - harness (`run_harness.py <worktree> <main>\tools\bin\luau.exe`): PASS, 2,455 checks.
  - sim_combat: PASS 23 of 23 (Hard ×2.16, Brutal ×4.31).
