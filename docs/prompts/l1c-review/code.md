# L1c review: code slice (roblox-reviewer, 2026-10-16)

Diff `main..2a58134` on `l1c-chief-clearing`: `WallClip.luau`, `Types.luau`, `WeaponService.luau`,
`WaveService.luau`, `CameraController.luau`, `CombatUIController.luau`, `InputController.luau`,
`run_harness.py`, `mutate.py`. I also read the unchanged run flow that the new data drives
(StageFlow Advance, Skip, FieldClear; WaveService close, queueWave, EndRun, moveFighters;
CrowdService WakeFloor, AliveOn, Damage; StrikeTally; FeedbackController).

Result: **1 Critical, 3 Major, 3 Minor.**

## Gates (run read-only, on a `git archive 2a58134` snapshot in the scratchpad)

| Gate | Result |
|---|---|
| Harness | PASS, 2,423 checks |
| `mutate.py "l1c:"` | 16 run, 0 not caught |
| `check_compile` | PASS, 158 files (InputController 151 top-level locals, CameraController 102) |
| `stylua --check` and `selene` on the seven files | clean |
| `luau-lsp` (combat sourcemap) on the seven files | clean |

## Confirmed: the run goes ambush, then Colossus, then the exit opens

- **The close.** It wakes C's held groups (`WakeFloor`) and queues wave 1. That wave is empty
  (`CampWave` gives total 0 and no boss, and no elite, because a level file has no `eliteKind`).
  So `spawningDone` is true at once.
- **The fight.** `alive = AliveOn(C)` counts the ten residents, so `fight` holds until the last
  one dies.
- **After the ambush.** In order: `clear`, `boundary` (stands up the downed, releases those
  waiting), the 3 s breather, then wave 2.
  - Wave 2 is the Colossus via `bossPending`.
  - When he dies, `leaveCamp` emits `open`, then `end cleared` in the same batch.
  - `open` calls `campCleared`, which calls `LevelService.SetCamp(C, "cleared")` and opens both gates.
- **A solo down during the ambush.** The field is not clear, so the run ends with `down`.
  `EndRun` then calls `clearField`, which removes every body before the summary.
- **A co-op down during the ambush.** The others fight on. The `boundary` after the ambush
  stands the downed player up.
- **Abandon.** It goes through `EndRun`, so the field is cleared.
- **Two players.** The first standing root starts the 3 s countdown. At the close,
  `moveFighters` puts every fighter outside the floor inset onto `entry`.
- **A solo reset during the countdown.** The camp is re-armed, and its groups stay held.
- **Client and server height rules are identical.**
  - The probes are the same: depth 250, lift 3, the root probe from the root, the same
    `RaycastParams`.
  - The fallbacks are the same: caster floor, else feet; target floor, else caster floor.
  - The rule is the same: `WallClip.TooHigh(casterFloor, floorY, WallClip.Rise(movement))`.
  - At the peak of a double jump, the 250-stud probe still finds the real floor.
- **Every camera path uses the clip.** Desktop, touch and gamepad differ only in how yaw, pitch
  and zoom are read. All of them place the camera in `update`, so all three go through the clip.

## Critical

### C1. `CameraController.luau:747-758` with `WallClip.luau:78-102`: the camera can sit in the gate's mouth from up to 13 studs back

**What.** The clip only keeps the camera *out of* the fenced rectangle. It does not stop the
camera from stopping just outside it.
- The open gate is fully transparent.
- From any eye within about 2.2 studs of the fence's outer face (2.8 for a brute's width), lines
  through the 16-wide opening reach the flank posts at z −22.5.
- The boom is 7 to 16 studs long. When the player faces away from or across the gate, the boom
  points toward the gate and ends in its mouth, with the root up to about 13 studs back.
- From there the side of the view frustum shows the flank through the opening. At FOV 72 the
  half-width is 52° on 16:9 and about 57° on a landscape phone.

**Scenario** (a 2D probe of the shipped layout; method below):
- Stand in the middle of leg 2, at (313.5, −32), 5 studs before the trigger line.
- Use the default zoom (11) and the start pitch (−12).
- Face north-east: roughly toward the upper part of GatehouseWallE, 35° right of straight back
  up the passage.
- The boom ends at (309.4, −27.1), 0.1 inside the gate's mouth.
- All six east ambushers are at the right of the screen, about 38 studs away, through the
  opening.

From that spot, about 50° of the 360° of turning show at least one post. Over root positions
and yaws across the width of leg 2:

| Root, studs before the trigger | Share of (x, yaw) samples that show a post (default zoom, pitch −15) |
|---|---|
| 1 | 25% |
| 5 | 11% |
| 9 | 2% |

At max zoom it still happens 13 studs back, in the corner square. Up to six posts show at once.

This breaks requirement 1 on every device, in plain play. It needs no exploit: just looking back
in the passage.

**Why the gates miss it.** The `check_levels` sight gate exempts camera points "within 2.5 studs
of the fenced rectangle and inside a gate's lane", on the ground that "one more step triggers".
The camera reaches those points from 13 studs away, so that reasoning does not hold. The 2.5 is
also smaller than a brute's 2.8.

**Fix (pick one; (a) is the code fix, (b) is the data fix, both is safest).**
- **(a) Keep the camera out of a zone around the camp, not just out of the camp.**
  - Give `Reach` a `margin`. The cut uses each rectangle grown by the margin. The "holds the
    root" test keeps the true fenced rectangle.
  - Set the margin to at least 3.5. That covers a brute (2.83), plus shake up to 0.35 studs
    sideways (`COMBAT_SHAKE_MAX_STUDS`, which today can already push the camera 0.15 past the
    0.2 pad), plus the pad.
  - Put it in Combat.json as `levels.cameraDoorway` (the name is a suggestion).
  - Once the root is inside the margin but outside the camp, the boom starts in the grown
    rectangle and comes to the head. What is left is the accepted doorway glimpse from the head
    itself, within about 2.8 studs of the trigger line.
  - Add harness cases and a mutation for the margin.
  - **Do not move the "root inside" test to the grown rectangle.** `data-tools.md` C1 proposes
    exactly that, and it would reopen the leak. A root standing 0–3 studs before the fence would
    then count as inside, the clip would be released, and the boom (7–16) could run through the
    open gate into the clearing. Only the cut uses the margin.
  - The `check_levels` doorway exemption must then be measured from the root (head) position,
    not from any camera point.
- **(b) A baffle (economy-designer).** Put a wall block inside the clearing, a few studs south of
  the north gate and wider than the gate's view fan, with no line to any post. Then nothing is
  visible through the doorway from any eye, and the clip is only a second guard. It fits "a bent
  passage". The flankers run round it at the close.

## Major

### M1. `CameraController.luau:680-683` (`rig == nil` → `deactivate`): Reset Character gives 8 s of the default camera with free orbit and 128-stud zoom

**What.** `localRig()` returns nil at `Health <= 0`, and `deactivate()` then hands the view to
the default Roblox camera with the dead humanoid as its subject.
- Roblox's Reset Character menu item is enabled. Nothing in `src` calls
  `SetCore("ResetButtonCallback", false)`.
- `respawnSeconds` is 8.
- `StarterPlayer.CameraMaxZoomDistance` is the default 128, because no project sets it.

The contract's "no rig only in the down state's narrow window" missed this: the down state is
1 HP, but a reset is 0 HP.

**Scenario.** Solo, with camps A and B cleared or sneaked (no group awake):
1. Walk into the gatehouse and press Esc → Reset Character.
2. `fallenReason` reads a wipe, but the field is clear, so the run goes on (ruling 17's "a clear
   field wins").
3. For 8 s, scroll out to 128 and orbit to look down over the 76-high wall: the ten ambushers
   stand at their posts.

In co-op, any member can do this at any time while others are on their feet.

**Fix.**
- `StarterGui:SetCore("ResetButtonCallback", false)` in the combat client. Retry on failure,
  since SetCore can throw before CoreGui is ready. Alternatively, a BindableEvent callback that
  asks for the rescue instead.
- As a backstop, `StarterPlayer.CameraMaxZoomDistance` = Combat.json `camera.maxZoom` in
  `combat.project.json`. This was the optional lead item in L1c-5.
- Optionally, keep the shoulder camera, with its clip, on a dead rig during a level instead of
  deactivating.

### M2. `CrowdService.luau:2049-2051` → `StrikeTally.luau:61` → `FeedbackController.luau:1725-1745`: ground abilities aimed over the wall write "BLOCKED ×N" over the hidden ambushers

**What.** §8 refuses a ground point only when the probe lands *on* a wall top.
- A point *beyond* the wall resolves to the camp floor (y 12), which is not too high, so it is
  accepted.
- Sphere and capsule strikes have no world occlusion (`WeaponService.Strike`, area candidates).
- A held resident answers `"blocked"`. StrikeTally makes it a `blocked` hit entry.
- The caster's client then draws an AlwaysOnTop "BLOCKED ×N" burst above the bodies' tops.

**Scenario.**
1. Stand in GatehouseWalk at about (275, −40).
2. Aim steeply up over GatehouseWallS. This works for Arrow Rain (castRange 90, radius 10), for
   Leap Smash (32, radius 14, landing at the server's point while the client's leap is stopped
   by the wall), Storm Coil (40, radius 16) and Blade Storm (30, radius 8).
3. The zone lands on the west posts 14–18 studs south, inside the wall.
4. "BLOCKED ×6" floats over the ambush, through two 64-stud walls.

This reveals the ambush from outside (requirement 1) on a deliberate blind cast. It is also the
last "BLOCKED" word that Ben asked to be rid of in Wave 4.

**Fix.**
- A held resident should answer as nothing at all. Return a verdict that StrikeTally drops, as
  it drops `"gone"`: either reuse `"gone"` or add `"held"` with the same drop. Then no hit
  entry, no word, no glint and no ×N.
- Add a harness case: a strike on a held group's bodies returns no hits. Add a mutation that
  restores `"blocked"`.

### M3. `StageFlow.luau:1775-1784` (unchanged; Combat.json `levels.gateSeconds` 3): stepping in does not shut the gate

**What.** The trigger starts a 3 s countdown. During it:
- the HUD reads "Gates close in 3" (`CombatHud.luau:1036-1037`);
- the gate stays open;
- the ten ambushers stand still, held and visible, along the inner north wall.

Only at the close do they rise.

**Scenario.** Every run. The player steps through the gate and sees ten statues and a countdown,
which spoils the surprise. They can walk 48 studs in that time, or step back out into leg 2
(they are moved to `entry` at the close anyway).

Ben's requirement 2 is "stepping in shuts the gate and the flank groups rush in".

**Fix.**
- Add a per-stage countdown, for example `stage.gateSeconds` in the level file, defaulting to
  `levels.gateSeconds`. Set it to 0 (or about 0.3) for the walled clearing.
- `gate()` reads the stage value.
- The Python mirror (sim_range / check_stage_mirror) follows. Add a harness case.
- This is a lead ruling, because the contract kept today's close. I rate it Major because it
  is seen in every run.

## Minor

### m1. `WallClip.luau:44-46` and `CameraController.luau:749,756`: the clip is released on X/Z alone, but the trigger also needs a standing root within `triggerHeight` (30) of the floor

**What.** At the top of a double jump the root is 33 above the floor.
- A player can drift into the gate's opening (the fence band, z −27..−26) at the apex. The
  camera is then free and sees the whole clearing from 35 studs up.
- They can then air-dash back out before the root falls back into the band (about 0.1 s).
- Nothing triggers.

The timing is tight, and the server's lag may trigger the camp anyway.

**Fix.** Release the clip only when the root is inside the rectangle and
`rootY - floor.y <= levels.triggerHeight`. RunFloor already carries `y`. This is the same
question StageFlow's `triggered` asks.

### m2. `InputController.luau:204-205`: `GROUND_AIMED` re-types AbilityService's `target = "ground"` set

The set is `leapSmash`, `bladeStorm`, `arrowRain` and `stormCoil`, a list that lives outside
config and is not mirrored.
- If a new ground ability is added on the server only, the server still refuses it. That is the
  safe direction, but the client then predicts a cast the server will refuse.
- No gate compares the two lists.

**Fix.** Either carry `target` in the ability's config (ProvingGrounds `ability.target`) and
read it on both sides, or add a harness or `check_stage_mirror` comparison of the two sets.

### m3. `StageFlow.luau:2082-2097` (Studio `B` lever): from the road, "next boss wave" fields the ambush and the Colossus together

**What.** `Skip("boss")` from travel arms C with `firstWave` 2. The close then wakes the held
ambush (`WakeFloor`) and queues the Colossus in the same frame.

**Effect.** A playtest step that uses B to "go to the boss" shows a fight the game never ships.

**Fix.** A one-line note for docs-keeper: reach the clearing with N, not B. Alternatively, have
`Skip("boss")` into a locking camp drop its residents (`ClearFloor`) when the boss wave is not
wave 1.

## Verified, no finding

- **`WallClip.Reach`.**
  - The slab entry is right on both axes.
  - The pad is applied along the flat boom and scaled back by the 3D length. That is correct,
    because `share × |boom|` keeps the flat distance to the edge equal to the pad.
  - A zero-length or vertical boom divides by zero only on the `at <= 0` path, which returns
    first.
  - A NaN root is held by nothing.
- **The `SetFloors` lifecycle.**
  - It is called only when the floors change. The lobby's `{}` and `Destroy` both clear it.
  - The range never calls it, so the range has no clip.
  - `locks` is compared by value in `applyFloors`.
  - The extra RunState cost is one boolean per floor. Sending nil for an open camp would save
    the field, but the cost is trivial.
- **The `castAbility` reorder.** `shotRay` reads only the camera aim ray, not the active slot, so
  taking it before `setActiveSlot` changes nothing.
- **A refused ground cast.** It spends no token, predicts no cooldown and starts no leap. The
  server refuses before the cooldown starts (`AbilityService:953-957`).
- **Leap Smash is a physics mover** (LinearVelocity with a capped correction), not a CFrame
  path, so a leap aimed beyond a wall stops at the wall.
- **What happens to the bodies when a run ends.** `EndRun` calls `clearField` before the summary,
  so the default camera in the `summary` and `ended` phases shows an empty clearing.
- **No yields in run loops, and every changed file is `--!strict`.** The only new tunables are
  read from config: `fenceThickness` and `movement`.

## Probe method (for re-running)

- **The scripts.** They are in the session scratchpad at `l1c/doorway.py`, `scan.py`, `scan2.py`,
  `eyes.py` and `ex.py`.
- **The world model.** A 2D model of leg 2 and the north gate:
  - GatehouseWallW, GatehouseWallE and GatehouseWallS;
  - the fence band at z −27..−26, with the 305.5–321.5 gap;
  - posts as discs of radius 1.3 (fodder) and 2.2 (brute).
- **The camera model:**
  - shoulder 1.75 to the right;
  - boom = zoom × cos(pitch) behind;
  - spherecast against the walls (radius 0.5, pad 0.2), then `Reach`'s rectangle cut with pad 0.2;
  - visibility = an unblocked segment within the horizontal half-FOV.
- **What it leaves out.** It is 2D only. Every wall here is 76 tall and the camera tops out at
  about 72, so the vertical cannot open a line.
- **Its finding.** The deepest eye that sees a post through the opening is 2.2 studs from the
  fence's outer face for fodder and 2.83 for a brute.
