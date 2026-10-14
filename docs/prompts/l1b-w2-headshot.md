# Brief: why no headshot lands on big bodies (L1b Wave 2, read-only)

You are a fresh agent on Era City Tycoon (Roblox, Luau, Rojo). Work in the worktree
`C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave2`. Every Bash call starts with
`cd /c/Users/benja/Desktop/tycoon-p5 &&`. **Do not edit any file under `src/`, `tools/` or
`docs/` except your report.** Scratch goes in your own folder
`C:\Users\benja\AppData\Local\Temp\claude\l1b-w2-headshot\`. Kill only your own PIDs, never by image
name.

## The complaint

Ben, after his Studio run of Forest Road on Normal (2026-10-14): *"i couldn't land a single
headshot to the big guys"* (brutes, and the Colossus boss). Smaller raiders do take headshots.
He played Broadsword tier 2 and Longbow tier 1, shooting with the over-the-shoulder camera
(camera-ray aim, Fortnite-style; crits on the head).

## What to find (an explanation with evidence, not a fix)

1. **Where the server decides a hit is a head hit on a crowd body.** Start from `HitShapes`
   (`src/shared/...` or `src/combat/...`, grep for it), the strike / shot resolution in
   `WeaponService` / `RangeService`, and how a crowd kind's size reaches the shape (the kinds'
   definitions in `src/shared/Config/ProvingGrounds.json` and `Combat.json`, `CrowdService`,
   `crowd.largeRadius`). Write down the head shape's centre height and radius for: a raider
   (fodder), a brute, a plated elite, the Colossus, the Warlord.
2. **How the client draws those bodies.** `CrowdRenderer` (and any model scale per kind): where
   the drawn head actually is, in studs above the body's ground point, for the same five kinds.
3. **Compare.** Is the server's head where the drawn head is? Other suspects to rule in or out,
   each with file:line:
   - the shot ray is judged against the body capsule before the head (order of tests, first hit
     wins), so the head is never reached on a wide body;
   - a crit is refused for kinds with a plate, or while the plate stands, or for bosses;
   - the client's crit marker / number only shows for some kinds (the hit is a crit but the
     feedback says it is not);
   - the head test uses the radius of a small body for every kind;
   - the camera-ray aim point and the muzzle ray differ, and for a tall body the muzzle ray
     passes under the head;
   - melee: does a sword ever crit? (probably by design not: say so).
4. **Prove it numerically if you can.** `tools/crowd_harness/run_harness.py` runs the real crowd
   modules under `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe` (pass that path as its second
   argument). You may write a scratch Luau probe in your scratch folder that requires the real
   `HitShapes` module and fires rays at a brute's drawn head height, then reports what the server
   would call it. Do not add it to the repo.

## Report

Write `docs/prompts/l1b-w2-reports/headshot.md` (in the worktree; commit nothing):
- **Cause** in two or three sentences, with file:line, and how sure you are (verified by a probe /
  by reading only).
- A table: kind, server head centre and radius, drawn head centre, gap.
- **The fix you propose** (which file, which owner: luau-engineer A owns the crowd and the hit
  shapes, ui-engineer the client renderer, economy-designer the configs), the pure rule it
  should become, and the harness case and mutation that would pin it.
- Anything else wrong you met on the way, one line each.

End your turn with a short summary of the cause and the path of your report.
