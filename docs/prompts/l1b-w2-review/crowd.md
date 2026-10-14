# L1b Wave 2 review — slice "crowd"

Diff `git diff main f40509a` (branch `l1b-wave2`). Files: `src/shared/Types.luau` (Wave 2 block),
`src/shared/HitShapes.luau`, `src/shared/SwingGate.luau`, `CampBrain.luau`, `CrowdService.luau`,
`WeaponService.luau` (diff), `Main.server.luau` (diff), `tests_l1b_w2_crowd.luau`,
`tests_l1b_crowd.luau`. Harness rebuilt from the worktree's cases and sources into a scratch
bundle (nothing written in the worktree): **PASS, 1,896 checks**.

## Major

### M1. The server clears the air swing only if one Heartbeat sample catches the landing, so a bunny-hop can get an honest air swing refused
`src/combat/server/Services/WeaponService.luau:1806` and `:1827` (`trackAir`), against `:2212–2216` (`OnAttack`).
- **How each side clears `used`.** The client clears it on an event: `AirSwing.luau:48–54`,
  `StateChanged` → `Landed`, which fires on every touchdown. The server clears it only when a
  Heartbeat sample of its replicated root reads within `standingOffset + 0.75` of the floor
  (`trackAir`'s airborne-to-grounded branch).
- **Why the server can miss it.** A jump of `movement.jumpHeight` 18 at the default gravity
  (196.2) lands at about 84 studs/s. So the root is inside the 0.75-stud band for about 9 ms
  going down and 9 ms going up, plus the ground contact. With jump held (or spammed on a phone
  while auto-swing runs), that contact is about one client physics frame. The server samples a
  copy fed by physics replication (≤ 60 Hz, interpolated) once per 16.7 ms, so it can step
  straight over that window.
- **Failure.** Jump, swing in the air: `used` is set on both sides. Land and jump again at once:
  the client sees `Landed` and clears, the server's samples never read grounded and do not clear.
  Swing in the second jump: the client allows and sends it, and the server refuses it
  (`sendRefused`). The swing the player saw is taken back and does no damage.
- **Contract and rules.** The contract's claim "an honest player is never refused" (L1b-W2-13)
  does not hold for jump-spam. Jump-spam is exactly how Ben met the one-swing-per-jump issue
  (§17.1). No gate covers it: `WeaponService` is not in the harness.
- **Fix.** Make the server's clear not depend on catching the touchdown in one sample. Either:
  - in `trackAir`, treat a fall turning into a rise between two samples as a landing when the
    lower sample is within margin + |Δy| of the floor (a double jump turns far above it); or
  - also clear on a replicated `Humanoid.StateChanged` → `Landed` on the server, if it arrives.

  Confirm in Studio with jump held plus attack held, watching for `RangeStats` refusals, or by
  logging the lowest sampled height of each airtime.

## Minor

### m1. The air test probes one ray under the root's centre, so a player standing on a ledge's lip is "airborne" to both sides and gets one swing
`src/combat/server/Services/WeaponService.luau:2207–2212`; the client mirror is
`AirSwing.luau:76–83` (client slice).
- **Why the test disagrees with the Humanoid.** A Humanoid stands on any contact under its
  footprint, but the gate's single ray hits the lower floor, or nothing (nil = airborne), once
  the centre is past an edge.
  - Lips that exist on Forest Road: Road4 → Road5 is an 8-stud step, the LookoutLedge, and the
    top of cover blocks.
- **Failure.** Every swing there counts as airborne.
  - The first swing is allowed. Then the client drops every later swing: the Humanoid stays in
    Running, so no `Landed` ever fires.
  - When the player steps back onto the block, the server's `trackAir` sees a "landing" but the
    client does not. The client then also drops the first air swing of the next jump, unless a
    grounded swing came first.
- **Fix.** Probe with a cast the width of the root on both sides
  (`Workspace:Spherecast`/`Blockcast` from `GROUND_PROBE_LIFT`), or clear `used` on both sides
  when the Humanoid's `FloorMaterial` is not `Air`.

### m2. "its spawn info shows it standing where it froze" does not pin the freeze-time state reset
`tools/crowd_harness/tests_l1b_w2_crowd.luau:539–551`, against
`src/combat/server/Services/CrowdService.luau:1066–1071`.
- **Why the case cannot fail.** The patroller under test is dormant from its first step: the root
  is 170 from the floor and the radius is 120. So it never walks before it freezes.
- **Why the state reads "idle" anyway.** Its stored info already read `idle` from `SpawnResident`.
  The harness stub also stores payloads by reference, so `risen` reads the live table.
- **Concrete mutation.** Delete `body.state = CampBrain.Shows(brain, false) or body.state`
  (A's decision 3). The case still passes. Nothing else pins the reset, so a late joiner could be
  told a frozen patroller is walking (`move`) and nothing would go red.
- **Fix.** Start the root inside 120 so the patroller walks, then move it out. Assert the stored
  info's `state` is `idle` after the next late-join refresh, the way the infos case copies values
  at the time.

## Checked and holding

- **`RayUpright` and `CrowdRay`.**
  - The capsule is the union of the two grown end spheres and the grown finite cylinder.
  - `firstIn` on the span matches `Ray`'s segment-to-sphere test exactly, including the far
    endpoint's cap and a start inside.
  - No shipped kind is squat (`top − radius > radius` for all ten), so the `low == high` path is
    never taken. The capsule contains today's sphere. `Query`'s bound holds the capsule and the head.
  - The crit is the unpadded head only. The entry is the nearer of body and head.
- **`gather`.** It hands `enemy.position` as the feet, so a launched body's capsule rises with it.
  The arrow steps, beam ticks and ability rays all go through `rayCandidates`.
- **Dormancy.**
  - A dormant group is still stepped, so sight is judged every step. `dormantRadius` affects only
    the drawing, never a wake.
  - A hit on a dormant body is blocked or landed through `Struck`, and either way wakes it.
  - A death clears `dormant`, so the corpse is sent.
  - `forgetGroups` and `campStep` with rules nil clear dormancy and `rouse`.
  - Separation skips dormant bodies on both sides. Only a group of the same camp walking home can
    pass through one, out of every player's 120.
- **Tent group with no member.** It may stay in `fight` (an empty `Step` changes nothing), but
  `Busy`, `Awake` and the engaged stamp all require a living member. A new tent body that joins
  it simply fights or leashes. No stuck state.
- **`JoinIn`.** It is breadth first with a `taken` set, so it terminates. Same camp only, from
  `AddGroup`'s gaps. It skips held, home, fighting and empty groups. It is directed by each
  waker's own sight. Only `Step`'s rest → rise starts it, never a release or a rouse.
- **`GroupedOn` and `GroupAlive`.** They follow `SpawnResident`, `noteGone` (deaths and
  removals) and `forgetGroups`.
- **The population cap.** `Spawn` counts living bodies. A summon tops up to `count` and never
  past it, so the boss reserve of 1 + 12 is the real ceiling.
- **The air-swing gate in `OnAttack`.** It runs after the ranged checks and the credit, and before
  anything is spent. A refusal spends no seq, credit or combo step. `RequestRangeAttack` keeps
  its rate bucket, so refused spam costs at most one ray per allowed call.
  - The client probes exactly like the server: every character excluded, `RespectCanCollide`,
    the same lift, depth, offset and margin.
- **Types.** The Types block is verbatim. `Main` passes `debug.perfAttribute`, which
  `Combat.json` carries.

## For other slices (one line each)

- **client:** `AirSwing` clears only on `Landed`. A fall taken while knocked down
  (`PlatformStand`) or a stand-up never fires it, so the first air swing after a knockdown is
  dropped unless a grounded swing came first. Also clear on `FloorMaterial ~= Air` (see m1).

Critical 0, Major 1, Minor 2
