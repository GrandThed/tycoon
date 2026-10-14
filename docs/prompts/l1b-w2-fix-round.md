# L1b Wave 2 — fix round (fresh agents)

Review of `main..f40509a`: **Critical 0, Major 2 (one found twice), Minor 9**, plus three
cross-slice notes the lead raised to fixes. Findings files: `docs/prompts/l1b-w2-review/`
(`crowd.md`, `run.md`, `client.md`, `data.md`). Worktree `C:\Users\benja\Desktop\tycoon-p5`,
branch `l1b-wave2`; every Bash call starts with `cd /c/Users/benja/Desktop/tycoon-p5 &&`.

**For every fixer:** read `docs/prompts/l1b-w2-build.md` (rules, reading list, verify list), the
findings files named in your section, and the contract sections they cite. You own only the
files of your role in the contract's Ownership table. Run `git status` and `git diff` first: the
work may be partly done. Write your report to `docs/prompts/l1b-w2-reports/fix-<role>.md` as you
go. Each fix that changes a pure rule gets a harness case and a mutation (mutations go to B by
exact text in your report). No git writes; kill only your own PIDs.

## Done by the lead

- **Major (client M1 = data Major): the checklist's headshot step woke Main Camp before the sneak.**
  Fixed in the contract: the headshot step moved into the Chief's Clearing (brutes, plated and the
  Colossus); step 1 reworded (the camp is seen at a jump's top or from the lookout step, client
  m1); step 2 asks for held-Space hops too; step 3 "steps out of the tent" (see B-4).

## A (luau-engineer, the crowd) — `crowd.md`

- **A-1 (Major M1 + crowd m1 + client m2): one landing rule for client and server.** Ruling: the
  "has landed" and "is grounded" questions become **one pure rule in `SwingGate`** that both
  `WeaponService.trackAir` and the client's `AirSwing` feed with the same samples (root position,
  vertical velocity, and the probe results), so they cannot disagree. It must:
  - count a landing when a fall turns into a rise near the floor, so a held-Space bunny hop with a
    one-frame contact always clears (an honest player is never refused);
  - judge grounded with a probe as wide as the root's footprint (several rays or a block cast,
    the same shape on both sides), so a ledge's lip, a fence top or a cover block reads grounded;
  - clear after a down and get-up (no air swing is held across a knockdown).
  A owns `SwingGate` and `WeaponService`; **A lands the new `SwingGate` API first and writes its
  exact signature into `fix-A.md`**, then the ui-engineer adopts it. Harness cases: the bunny hop
  sampled at the server's rate, the lip, the get-up; a mutation for each clause.
- **A-2 (crowd m2):** "its spawn info shows it standing where it froze" cannot fail. Make the
  patroller walk before it freezes, and prove it with the mutation the reviewer gave (delete the
  freeze-time reset at `CrowdService.luau:1070`).
- **A-3 (lead-routing, B's note):** the flaky timing case "a giant standing far away costs the
  packed crowd nothing" fails under load. Make it count work (cells scanned, pairs tested), not
  time; if it must stay timed, widen the margin and say why in the case.

## B (luau-engineer, the run) — `run.md`, cross-slice notes

- **B-1 (run m1):** a tent body sent into a group already fighting never becomes a threat for the
  safe point: in `tickTents`, append the new id to `run.awakeGroups[tent.group]` when it exists.
- **B-2 (run m2):** a tent's ring is checked against its floor at the highest difficulty only.
  Check at every difficulty (or the whole circle); the same for Wave 1's fire rings.
- **B-3 (crowd note):** a body a tent sends while its own group is walking home is not roused and
  stands at its post while the camp fights. Ruling: a tent body sent while any group of its camp
  is in `rise` or `fight` is roused at once (`CrowdService.RouseGroup` / `CampBrain.Rouse`, A's
  existing exports). If a change in A's file is needed, list it for the lead.
- **B-4 (data note): tent bodies pop in.** Ruling: a tent body comes out with the same rise the
  boss's summoned bodies use, at the tent marker's side facing its ring post, then walks to its
  post or into the fight. B owns the spawn call in `WaveService`; anything needed from A
  (`CrowdService`) or the client goes to the lead as an exact request.

## ui-engineer (the client) — `client.md`, cross-slice notes

- **ui-1 (A-1's client half):** `AirSwing` adopts A's `SwingGate` rule (same samples, same probe)
  and clears on everything the rule clears on. Wait for A's signature in `fix-A.md`; build the
  sampling meanwhile.
- **ui-2 (data note, raised to a fix): phone auto-fire wakes a sleeping camp,** so the sneak cannot
  be done on touch. Ruling: phone auto-fire and auto-swing **never target a body whose group is
  resting** (or dormant); they target only awake groups (rise, fight, home) and bodies with no
  group. A phone player wakes a camp by walking into sight, as the "noisy way". Keep it a pure
  predicate beside `InputController` with a harness case (B registers it) if it is more than a line.

## economy-designer (the data) — `data.md`

- **E-1 (data m1):** C's south guards stand in C's tent marker. Move C's tent (about 2 studs north)
  or end the south line, and extend `check_levels`' marker check to every post of the camp, every
  difficulty.
- **E-2 (data m2):** the `check_levels` line "every tent marker is walk-through" tests a key no
  layout has. Make it test what the game reads (the tent look's non-collision as LevelGeometry
  builds it) or drop it.
- **E-3 (data m3):** commit the mirror-mutant driver as `tools/crowd_harness/mirror_mutants.py` (from
  `C:\Users\benja\AppData\Local\Temp\claude\l1b-w2-econ\mirror_mutants.py`), runnable by QA, and
  point BALANCE's "39 of 39" at it.
- Re-run check_levels, both sims with `--check`, check_stage_mirror and the new driver at the end.

## After the fixes

One fresh reviewer on the fix diff, then qa-runner with the full gate list, then the merge.
