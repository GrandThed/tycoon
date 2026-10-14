# Brief: draft the L1b Wave 2 contract ("the long road")

You are a fresh Opus agent drafting a contract for the lead engineer of Era City Tycoon (Roblox,
Luau, Rojo). Work in the worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave2`. Every
Bash call starts with `cd /c/Users/benja/Desktop/tycoon-p5 &&`. Python is `py`. You write one
thing: a new section **appended at the very end of `docs/INTERFACES.md`**, headed
`## Wave 2 — the long road (2026-10-14)`, with `###` subsections. You edit nothing else and
commit nothing. INTERFACES is ~12,800 lines: grep headings and read ranges, never the whole file.

## Read, in this order

1. `docs/prompts/l1b-w2-reports/lead-routing.md`: **every ruling there wins** over anything else.
2. `docs/MISSIONS_DESIGN.md` §15, §16, §17.
3. `docs/INTERFACES.md` from `# L1b contracts — the living road` (line ~11369) to the end. This is
   Wave 1's contract, its "Open for later" (the Wave 2 outline), its "Draft points", and "Review
   round and state" with its **Contract amendments**. Match its structure and voice. Also read
   the P1 contract's decision 1 on the ray hit rule (grep `P1` near line 4266), because Wave 2
   amends it.
4. `docs/prompts/l1b-w2-reports/headshot.md` (the cause, the `HitShapes.CrowdRay` rule, the
   harness cases and mutations) and `docs/prompts/l1b-w2-reports/layout.md` (the winding road,
   the arithmetic, the tent costs, the 19 assumptions). The chosen drafts are
   `docs/prompts/l1b-w2-layout/winding.level.json` and `winding.layout.json`.
5. `docs/PLAN.md` "## L1b — the living road" (the **Carried** list with owners) and
   `docs/BALANCE.md` "L1b".
6. `docs/prompts/l1b-study-report.md` §4 (population and the wire) and §8 (the wave plan).
7. The code, only as much as you need to name functions, files and types right: `CampBrain`,
   `CrowdService`, `HitShapes`, `WeaponService.rayCandidates`, `WaveService`, `LevelService`,
   `StageFlow`, `CrowdRenderer`, `InputController`, `src/shared/Types.luau`,
   `tools/check_levels.py`, `tools/check_stage_mirror.py`, `tools/sim_range.py`,
   `tools/crowd_harness/`. Grep; do not read 2,000-line files whole.

## What the contract must cover

**Wave 2 scope (all are Ben's or the lead's decisions; do not re-open them):**
1. The winding road becomes Forest Road (the drafts, adopted nearly as is), every camp inside
   the wire's ±1,000 studs; `check_levels` learns the Wave 2 sizes, the sneak-path gate (flat
   distance from `layout.sneak` to every resting place greater than its sight), the post-spacing
   gate, and the new population rule.
2. Tents (lead-routing rulings 5 and lead 2(6)): the pure rule in `CampBrain`, the executor in
   `WaveService`, the stock per difficulty, a walk-through marker look.
3. Dormancy for far resting camps (the outline's `Dormant` rule, not stepped, not sent), and
   spawn infos that carry position, yaw and state so the client draws a body with no snapshot.
4. **Nearby groups join in** (lead 2(1)): the chained 2 × sight wake as a pure rule.
5. **One sword swing per jump** (§17.1): the next melee swing needs a landing; the ground slam is
   unchanged. Say where it is judged (server, the strike gate) and how the client's auto-swing on
   phones respects it.
6. **The headshot fix** (lead 1): `HitShapes.CrowdRay`, body as a vertical capsule, the P1
   amendment, the mirror in `sim_range.py`, the crit-on-plate colour Minor for ui-engineer.
7. **Starting preset 2 / 2** (§17.3), no weapon-number change; the bosses re-checked.
8. **Clear bonus** (rulings 2 and lead 2(5)).
9. The bands (lead 2(14), 2(10)): first Normal clear, Hard and Brutal gates, pay and Timber per
   minute, `targetMinutes`, `runCapSeconds`.
10. The `[Perf]` line in the boss room that Ben reads (asked as a click question with ranges).
11. **The Carried list from PLAN "L1b"**, each item either taken into Wave 2 with an owner or
    explicitly left carried. At least: the shared pure flat-distance-to-rectangle helper (used by
    `CampBrain` and `InputController`), phone auto-fire at held residents during the boss room's
    countdown, `check_stage_mirror` comparing `StandsUp`, post spacing beyond fires, the
    director's merge test with residents alive, residents not scaling with party size (stays
    carried to L5), `OnDash` i-frames (before any publish).

**Sections to write** (as Wave 1's): rulings (numbered L1b-W2-n), Types (verbatim Luau for
`src/shared/Types.luau`), Config shapes (level, layout, ProvingGrounds, Expeditions looks),
Remotes (say "none new" if so), Balance bands, **Ownership** (disjoint files, the four owners:
luau-engineer A the crowd and hit shapes, luau-engineer B the run / level / tests, ui-engineer
the client, economy-designer the data, the sims, the checkers and BALANCE; name every file each
one touches, and who goes first if one needs another's change), Gates (Wave 1's 14 items plus
Wave 2's), Definition of done, a **Playtest checklist for Ben** (about 10 minutes, key-only, what
Play opens on; ends with the `[Perf]` click question and the bow question at 2 / 2), and
"Open for later".

**Close the section with `### Draft points for the lead`:** every decision you had to take that
the rulings did not cover, one line each, so the lead can confirm or change it before anyone
builds. Do not hide a decision in the body.

Pure rules are tested; executors are read. Every new rule goes in a pure module with a harness
case and a mutation; say which. No sound in combat. No on-screen attack button on phones. Phones
must work. Code rules: `--!strict`, no `wait/spawn/delay/_G`, constants only in
`src/shared/Config/*.json`, the server owns all state, `py tools/check_compile.py` (≤ ~180
top-level locals per module: tell owners of big modules to put new code in new modules).

End your turn with: the line range of your section, the number of rulings, and the draft points
list.
