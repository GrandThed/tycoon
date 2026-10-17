# L2 W1 fix-diff review (2026-10-17)

Diff `a21f153..d6b3777` (the W1 fix round) in `tycoon-p5`, branch `l2-secrets`, HEAD 613e736 (the brief on top).
Read: the whole diff of every code and tool file, the three findings files, the rulings, the three reports, plus
the unchanged code each fix leans on (MovementController's jump, knock and isAirborne; SwingGate's header;
WeaponService.worldParams/floorBelow; BarrierGroups with EnemyService's groups; CombatUIController's map and
summary bindings, applyLayout and touchCluster; InputController's Y bindings; SecretFlow.Sites; the
ForestRoad layout around the three chests).

Gates, all on a `git archive HEAD` copy in my scratchpad (never in the worktree):
- harness `HARNESS: PASS (2,625 checks)`;
- `check_levels.py` PASS (the three L2-18a lines, (b), (c), (d) all green);
- `check_stage_mirror.py --luau <main>` PASS;
- `check_compile.py` PASS (165 files);
- luau-lsp on `src/combat src/shared` clean; stylua and selene clean on ActionRows, Unlocks, WallClip,
  MovementController and the client UI folder.
- Two probes of my own, below: a mutated call-site copy run through the harness, and a Python port of
  `ActionRows.Pack` with the real cluster, jump and vitals formulas. The port reproduces the client report's
  table to the tenth with an origin of (0, 58).

**Verdict: 0 Critical, 1 Major, 3 Minor.**

## Fixed and checked

- **s1 + d2, the footprint trigger.** `Triggered` and `secret_triggered` agree term for term. `Sites` drops a
  secret with no footprint or a negative one, and the layout carries `sx`/`sz` for all three.
  - At `secretReach` 2.5, the ground within reach of the lookout's 6 × 6 footprint is x −288.5..−277.5,
    z −64.5..−53.5. That lies wholly on LookoutLedge.
  - Road5 roots are at least 5 off on the flat and −23 (−5 at a jump's top) in height.
  - Airborne roots are the case (d) must cover. The only one that reaches the band's floor of 33 is the
    apex from camp A's fence top (12 + 18 + 3 = 33). It is held 7.5 or more off the footprint, because
    the ledge's east face blocks a body whose feet are under 34.
  - The cache opens from the CacheSpur end (z −12.5..−11, a dead-end spur) and not from its top (rise 13).
  - The shrine opens from the Pond and from its own top.
  - (a) now runs for every secret, with a red mutant for the centre rule.
- **s2, c5, d4, the caps.** Each cap has one home, Unlocks. CombatRemotes, StageFlow and the panel (through
  `Sellable`) read it, and so do `sim_range` and `check_levels`, through a regex on the `local MAX_… = n`
  line. No other copy is left in `src` or `tools`. Lengths are counted in bytes on both sides, and an empty
  `text` is refused on both sides.
- **s3.**
  - `Unlocks.Apply` and `SecretFlow.Open` are pure and never yield.
  - `OnBuyAbility` evaluates the gate as an argument, then calls Apply. Nothing between the check and the
    write can yield.
  - `OpenSecret` reads the key from the profile, then calls Open.
  - A mutated service line can now at most set the attribute without ownership. The chest key is read from
    the profile, so no reward leaks.
  - The mutations "sells at 0" and "Open pays whatever the verdict" are in.
- **s4.** `Find`, `Sellable`, `HasKey` and the panel all read the first sound entry of an id. A list that
  holds the same table twice sells it once.
- **c3, the walk-off grace.**
  - **Bounded height.** The grace needs `takeoff.walkedOff`, a press within 0.12 s of leaving a floor, and
    the root no higher than where it left. So its apex is at most one jump over a surface the Humanoid
    actually stood on (FloorMaterial not Air).
  - **No extra jump.** It cannot fire twice in one airtime: `walkedOff` is cleared on use, and only a new
    take-off sets it again.
  - **No chain.** It leaves `airJumpUsed` alone, so an owner gets jump plus double jump, as from the edge,
    and a non-owner gets one jump.
  - **The lookout stays out of reach.** The highest surface near it is the fence top at 12, still 1 stud
    short.
  - **A dash off an edge:** the dash travels up to 0.12 s before the jump. That is inside what a native
    ground jump made during a ground dash already gives, and inside check_levels' "dash anywhere at the
    apex" envelope.
  - **A leap or lunge that ends in the air:** gated by `motion ~= nil`, then by the 0.12 s window from
    the take-off, which a leap outlasts.
  - **Server paths:** SwingGate's client turn window (0.05 s) stays a subset of the server's (0.1 s), so
    no rule changes there.
- **c4.**
  - Both sides make one `WallClip.GroundFloor` call.
  - The source check counts that call and the parts, and is not vacuous: an empty fixture fails it, and so
    do the two "keeps its own copy" mutants.
  - Its limit is in Minor 1.
- **d1, players pass through players.**
  - `ArenaPlayers` against itself is false. Every other pair still copies Default.
  - Rays run in Default, so shots and the camera are unchanged.
  - WeaponService's world probes exclude every character, so a body standing inside a partner never reads
    the partner's legs as its floor.
  - L1c's close, `standUpOnRoad`, the rescue and the lobby spawn now overlap instead of shoving, which also
    removes the old pop onto a head.
  - The range is unchanged (its players are never admitted).
  - Debug bots stay in Default and are still solid to members, so a head stand on a bot works in Studio
    only. That is not a live path.
- **c2, the gamepad panel.**
  - Y is bound at High+1 only while `SetLobby(true)`, above InputController's Y (STANCE and RANGE_SWAP at
    High), and sinks.
  - B is bound at High+1 only while the panel is open, above MovementController's dash at High.
  - The map's A, d-pad and confirm binding (High+1) is gone, because every way of opening the panel now
    closes the map (`onOpenChanged`).
  - `openMap` closes the panel, so the map's A and the panel's selected Buy are never both live.
  - Selection starts on the first live Buy after gamepad input and cannot leave the sheet. Closing clears
    it.
  - Whether A on a selected button also jumps is the engine's call: GUI selection normally consumes A. It
    stays on the client's Studio list.
- **c6, c7, d3.** Done as ruled.
  - **d3.** `take_off` now sees the timed press and the hop's press. The hop policy is not in any level row
    the gate sums, so the hop change cannot turn the gate red by itself.

## Major

1. **The c1 rows use `screenGui.AbsolutePosition` as the HUD's offset in the viewport, and in Roblox that
   reads (0, 0). So on a landscape phone the original c1 overlap comes back unchanged.**
   - Where: `src/combat/client/Controllers/CombatUIController.luau:2077` passes the origin;
     `bottomObstacles`, from 445, subtracts it from viewport-px rects.
   - **Why it is wrong.**
     - `GuiObject.AbsolutePosition` is measured from the origin under the top bar. That is the same space
       as `Camera:WorldToScreenPoint` and `InputObject.Position`, not `GetMouseLocation`.
     - So a default ScreenGui such as ExpeditionHUD has AbsolutePosition (0, 0). An IgnoreGuiInset one
       reads (0, −inset).
     - The same function converts the crosshair with `viewport.Y / 2 - inset.Y` (line 2097, for SecretFx
       and the boss bar). It therefore assumes two different origins for one ScreenGui.
     - The client agent's numbers match only an origin of (0, 58). My port of `ActionRows.Pack` with the
       real formulas gives the report's table exactly with 58, and the overlap with 0.
   - **Scenario (origin 0).**
     - At 667x375 the health bar's real rect (viewport y 349.3–365.8) is compared against row 1 as if it
       were 58 px lower in the HUD. It falls outside the band, so Map, Abilities and Return stay in one
       row.
     - Return then spans x 168.7–264.0, y 320–364, over the bar's left 22 px (the bar starts at 241.8).
       That is the m1 case the ruling says must never happen.
     - 640x360 is the same: Return reaches x 264.0 over a bar that starts at 228.0.
     - Portrait 375x667 comes out the same either way (three stacked rows), so the Dash misfire does not
       come back.
     - `proving.rbxl` hides Return, so Ben's emulator look there cannot show it.
   - **Fix.**
     - Pass the inset the function already holds: `Vector2.new(inset.X, inset.Y)` (`GetGuiInset()` is the
       HUD's top-left in the viewport), the same convention as line 2097.
     - Re-run the probe.
     - Or confirm in Studio with one print of `screenGui.AbsolutePosition` in the phone emulator before
       keeping it.

## Minor

1. **c4: the arguments at the two call sites are still copies that no gate compares**
   (`InputController.luau:1871-1877`, `WeaponService.luau:2563-2569`).
   - What: the source check counts one `GroundFloor(` per side and no parts. The attribute read, the
     movement table and the feet expression are written twice.
   - **Probe.** On a snapshot I made two edits:
     - the client's last argument became `GetAttribute(...) ~= false`, m4's own first example, which makes
       every player an owner on the client;
     - the server's movement became `{ jumpHeight = 30, doubleJumpHeight = 0 }`, which gives every player
       30 of rise on the server.
     - The harness still read `HARNESS: PASS (2,625 checks)`.
     - The server edit would let a non-owner's Leap Smash target the ledge once a lifting family enters a
       level. The chest still pays only to profile owners.
   - **Fix.** Either of:
     - make the check compare the two calls' argument texts for the movement and attribute arguments
       (normalised: both must read `Tuning.Get().movement` and `…:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP))`),
       plus two mutants;
     - or move the attribute read and the `Tuning` read into one shared helper that takes the Player.
   - Also: `parts == 0` over the whole of WeaponService makes any future legitimate `WallClip.Rise` call in
     that 2,800-line file fail the harness. Scope the count to the GroundPoint function's body.

2. **c7: the lookout's card always carries a family note that wraps, and `placeCard` counts it as one line**
   (`SecretFx.luau:240-244` fixed-height `TextWrapped` labels; `placeCard` from 309; `LATER_NOTE` at 68).
   - What: the note is "Flamethrower is yours: you can carry it in a later update", 57 characters. In bold
     at 12 that is about 340 px, against 276 px of room (card 300, less 2 × 12 padding), so it takes two
     lines in an 18-px label.
   - The label is not clipped. The text block (about 28 px) overflows its label by about 5 px each way:
     - the top line overlaps the "+50 Timber" line;
     - the bottom spills into the card's padding.
   - The overlap itself was there before the fix round. c7's height model (and the report's "106 px tall"
     row) uses the one-line height. W1's only paying chest is exactly this case.
   - Fix: give the note label `AutomaticSize.Y` (or measure it with `TextService:GetTextSize` at
     `SECRET_CARD_WIDTH − 2·padding`), and have `placeCard` read the measured height. Check 667x375 again
     against the top tick.

3. **c3: an enemy launch counts as a walk-off, contrary to the client report**
   (`MovementController.luau:86`, `:291`; `ApplyKnock` at 1101).
   - What: every launch in `ProvingGrounds.json` is 3 studs, which is `jumpSpeed(3)` = 34.3 studs/s. The
     walk-off test is under half a jump's take-off speed: 0.5 × `jumpSpeed(18)` = 42.0. The report says a
     launch leaves faster.
   - Effects (no height gained):
     - The first deliberate air press after any launch never shows the "buy Double Jump" hint.
     - A press in the launch's own frame, while the root is still at the take-off height, turns the launch
       into a full ground jump.
   - Record only. Either correct the comment and the report line, or have `ApplyKnock` set
     `takeoff.walkedOff = false` when it lifts.

## Studio-only (cannot be settled offline; already on the reports' lists)

- Whether the Humanoid's floor sensor respects the `ArenaPlayers` pair. If it does not, a head stand still
  "lands", and d1 does not close the stacking route. Two players, one without Double Jump, at the ledge face.
- Whether A on a selected Buy also jumps. Whether the engine's own B (leave selection) eats the first B press
  before the panel's binding sees it.
