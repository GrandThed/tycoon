# L1b Wave 2 fix round — ui-engineer report

Status: **ui-1 done. ui-2 is done on the client, but it needs one server change from A before it
takes effect** (see "For the other owner").

## ui-2: phone auto-target never takes a resting group's body

### What the client cannot know today

The client does not know which bodies rest:

- A spawn info carries `floor`, `at`, `yaw` and `state`, and nothing about the body's group.
- A resting guard shows `idle` and a resting patrol `move`. An awake body shows the same states.
- A wave body (camp C, the boss room) has a camp floor and no group, so "camp floor and never
  alerted" cannot stand for "resting".
- The `alert` cue marks a wake, but nothing marks a group's return to rest (home, then rest).
  A tent body sent into a group that is already fighting gets no alert either (B-1).

So the server has to say it. The smallest change is one field on the spawn info. It needs a
re-announce when a group goes to or from rest, and it covers late joiners. See "For the other
owner" A.

### Done (my files)

- **New pure module `src/combat/client/Controllers/CampAim.luau`.** `CampAim.Takes(centre, half,
  resting, root, phase, engaged, camps)` holds the whole auto-target camp rule. It checks, in order:
  1. no camp floor: always taken (the range, an arena);
  2. phase `gate`, or the body's group rests: never;
  3. engaged, or no camp rules loaded: always;
  4. otherwise only while the root is in play: inside the sight band and within `FlatToRect`
     ≤ `chaseMargin`.

  Wave 1's `campInPlay` rules are moved there unchanged, and clause 2 adds the resting test. A
  resting body is refused **even while the player is engaged**, because the engagement can come
  from another group of the same camp.
- **`CrowdRenderer.luau`:**
  - The entity has a new field `resting`. It is false on a fresh or pooled entity.
  - `onSpawn` sets it from **every** info, `info.resting == true`, including a re-announce of a
    body that is already drawn. So the newest info always wins.
  - `CrowdRenderer.CampFloor(id)` now also returns `resting` as a third value. It is false when the
    body has no camp floor.
  - No new top-level local.
- **`InputController.luau`:** `campInPlay` now only calls `CampAim.Takes`. Top-level locals go
  from 148 to 149 (the `CampAim` require).
- **Until A's field lands**, `info.resting` is nil, so every body reads as awake. That is exactly
  today's behaviour.

### Harness case and mutations (for B, by exact text)

**`run_harness.py` `SOURCES`**, after the `SpawnSeed` line:

```python
    "CampAim": "src/combat/client/Controllers/CampAim.luau",
```

**Cases**, appended to `tests_l1b_w2.luau` before its verdict line. I ran them in a scratch copy of
the harness: PASS, 1,908 checks, all 12 new ones `ok`. Each of the six mutations below was caught.

```luau
-- L1b Wave 2 fix round, ui-2: touch auto-target never takes a resting group's body (CampAim).
do
	local Aim = load("CampAim")
	local camps: any = { sightBelow = 6, sightAbove = 12, chaseMargin = 2.5 }
	local centre = vec(100, 8, 0)
	local half = vec(20, 0, 15)
	local inside = vec(105, 11, 3)
	check(
		Aim.Takes(nil, nil, false, inside, "travel", false, camps),
		"CampAim: a body with no camp floor is always taken"
	)
	check(
		Aim.Takes(nil, nil, true, inside, "gate", false, camps),
		"CampAim: a body with no camp floor is taken even in the gate"
	)
	check(
		Aim.Takes(centre, half, false, inside, "travel", false, camps),
		"CampAim: an awake group's body is taken in play"
	)
	check(
		not Aim.Takes(centre, half, true, inside, "travel", false, camps),
		"CampAim: a resting group's body is never taken (the sneak on touch)"
	)
	check(
		not Aim.Takes(centre, half, true, inside, "travel", true, camps),
		"CampAim: engaged by another group, a resting body is still not taken"
	)
	check(
		not Aim.Takes(centre, half, false, inside, "gate", true, camps),
		"CampAim: in the gate no camp body is taken, engaged or not"
	)
	check(
		Aim.Takes(centre, half, false, vec(400, 8, 0), "travel", true, camps),
		"CampAim: engaged, an awake body is taken from out of play"
	)
	check(
		Aim.Takes(centre, half, false, vec(122, 8, 0), "travel", false, camps),
		"CampAim: within chaseMargin of an edge is in play"
	)
	check(
		not Aim.Takes(centre, half, false, vec(122, 8, 17), "travel", false, camps),
		"CampAim: past the rounded corner is out of play"
	)
	check(
		not Aim.Takes(centre, half, false, vec(105, 1, 0), "travel", false, camps),
		"CampAim: under the sight band is out of play"
	)
	check(
		not Aim.Takes(centre, half, false, vec(105, 21, 0), "travel", false, camps),
		"CampAim: over the sight band is out of play"
	)
	check(
		Aim.Takes(centre, half, false, vec(400, 8, 0), "travel", false, nil),
		"CampAim: with no camp rules loaded an awake body is taken"
	)
end
```

**`mutate.py`**: add `CAMP_AIM = "src/combat/client/Controllers/CampAim.luau"` to `FILES`, then
these six entries. Every one was caught in my scratch run.

```python
CAMP_AIM = "src/combat/client/Controllers/CampAim.luau"
    "l1b w2 ui: a resting body is taken": (
        CAMP_AIM, 'if phase == "gate" or resting then', 'if phase == "gate" then'),
    "l1b w2 ui: the gate takes camp bodies": (
        CAMP_AIM, 'if phase == "gate" or resting then', "if resting then"),
    "l1b w2 ui: engaged takes a resting body": (
        CAMP_AIM,
        '\tif phase == "gate" or resting then\n\t\treturn false\n\tend\n\tif camps == nil or engaged then\n\t\treturn true\n\tend\n',
        '\tif phase == "gate" then\n\t\treturn false\n\tend\n\tif camps == nil or engaged then\n\t\treturn true\n\tend\n\tif resting then\n\t\treturn false\n\tend\n',
    ),
    "l1b w2 ui: auto-target corners square": (
        CAMP_AIM,
        "return HitShapes.FlatToRect(root.X, root.Z, centre.X, centre.Z, half.X, half.Z)\n\t\t<= camps.chaseMargin",
        "return math.max(math.abs(root.X - centre.X) - half.X, math.abs(root.Z - centre.Z) - half.Z)\n\t\t<= camps.chaseMargin",
    ),
    "l1b w2 ui: auto-target has no sight band": (
        CAMP_AIM,
        "if root.Y < centre.Y - camps.sightBelow or root.Y > centre.Y + camps.sightAbove then",
        "if false then",
    ),
    "l1b w2 ui: a body with no camp floor is refused": (
        CAMP_AIM,
        "if centre == nil or half == nil then\n\t\treturn true",
        "if centre == nil or half == nil then\n\t\treturn false",
    ),
```

## ui-1: one landing rule (done, against A's API in `fix-A.md`)

`src/combat/client/Controllers/AirSwing.luau` is rewritten. It feeds `SwingGate` exactly what
`WeaponService.trackAir` / `OnAttack` feed it.

- **Every Heartbeat**, for the local character:
  - `SwingGate.Observe(gate, root.Y, root.AssemblyLinearVelocity.Y, footprintFloor(root.Position),
    HipHeight + root.Size.Y / 2, MovementController.IsDown())`;
  - no sample while there is no root or Humanoid.
- **The footprint probe is the server's `footprintFloor`, line for line:**
  - `SwingGate.PROBE_POINTS` rays at `SwingGate.ProbePoint(i, p.X, p.Z, right.X, right.Z,
    Size.X/2, Size.Z/2)`, where `right` is `root.CFrame.RightVector`;
  - each ray from `p.Y + GROUND_PROBE_LIFT`, down `GROUND_PROBE_DEPTH`;
  - Exclude every player's character, with `RespectCanCollide`;
  - the results folded with `SwingGate.Higher`.
- **At a swing:** `SwingGate.Judge(gate, origin.Y, footprintFloor(origin), standOffset, 0)`, where
  the origin is the root's position, which is what gets sent. Then `Took` after the send, as
  before.
- **The `StateChanged` → `Landed` clear is gone**, as A asked. The rule's own samples clear on a
  landing, a bunny-hop turn and a down. A new character resets with `SwingGate.Landed`.
- **Decisions I took:**
  1. The Heartbeat sampler starts at the first `Judge`, with one sample taken at once. Without that
     first sample, a first swing made just before touchdown would miss the next frame's landing,
     because `state.airborne` would still be false.
  2. The probe's character filter is rebuilt at most every 0.25 s, not every frame.
  3. The cost is 5 rays a frame for the local player only.
- **Not harness-tested:** `AirSwing` is an executor that casts rays. The rule itself is A's
  `SwingGate`, which has A's cases. The mirror of `footprintFloor` is checked by reading only.

## Gates run (my files: `AirSwing`, `CampAim`, `InputController`, `CrowdRenderer`)

- `stylua --check`: clean. `selene`: 0 errors, 0 warnings.
- `luau-lsp analyze` of `src/combat` on a fresh combat sourcemap (scratch): no diagnostics.
- `py tools/check_compile.py --counts`: PASS, 156 files. `CrowdRenderer` is at 153 and
  `InputController` at 149.
- `rojo build` of `combat.project.json` and `default.project.json` to my scratch folder: both
  build.
- Harness, in a scratch copy with `CampAim` registered: PASS, 1,908 checks. All 6 `CampAim`
  mutations were caught.
- Gate 12, `git diff --stat -- src/server src/client`: empty.
- No UI layout changed, so the 375 × 667 and 1920 × 1080 reads in `build-ui.md` stand.

## What to check in Studio

1. **Held Space plus held attack with a sword:** one swing per hop and none refused.
   `RangeStats` should show no refusals.
2. **Standing on the Road4 → Road5 step's lip, the lookout ledge or a cover block's edge:**
   every swing goes out.
3. **In the `fight` set, put down after an air swing:** after the get-up, the first air swing
   goes out.
4. **Phone emulator at 667 × 375, auto-fire on:**
   - walking the sneak path inside B's north fence fires at nobody;
   - walking into a group's sight wakes it, and from then on auto-fire takes it.

   This check needs A's `resting` field.

## For the other owner

### luau-engineer A (`Types.luau`, `CrowdService.luau`), for ui-2

1. **`Types.luau`, `CrowdSpawnInfo`:** add a field.

   ```luau
   -- L1b Wave 2 fix round (ui-2): true while the body's camp group is at rest (held and dormant
   -- included); nil for an awake group (rise, fight, home) or a body with no group. Clients'
   -- touch auto-target never takes a resting body.
   resting: boolean?,
   ```

2. **`CrowdService.refreshInfo`:** write the field at every send.

   ```luau
   local resident = enemy.resident
   local record = if resident ~= nil then camp.groups[resident.group] else nil
   info.resting = if record ~= nil and (record.brain.held or record.brain.state == "rest")
   	then true
   	else nil
   ```

   This is the same test `CampBrain.Shows` uses for "shown at rest".

3. **Re-announce a group's bodies when it changes to or from `rest`.** Do it in `queueEvent`, when
   `from == "rest" or to == "rest"`, so that a close's release, a wake, a join-in, a rouse and a
   return home are all covered.
   - **Use a separate queue, not `pendingSpawnSet`.** The remove path treats a body in
     `pendingSpawnSet` as never announced and sends no `CrowdRemove`, so a re-announced body
     that died in the same step would stay on every client for good.
   - Suggested shape:
     - `pendingReannounce: { [number]: true }` and `pendingReannounceOrder: { number }`, both
       cleared in `Clear`.
     - In `queueEvent`, for each `body` of the group that is not in `pendingSpawnSet`, mark it
       and append its id.
     - In `flushLifecycle`, after the spawn loop, append `refreshInfo(enemy)` for each queued id
       whose enemy still exists and has `deadAt == nil`. Then clear both tables, and fire the
       batch if it is not empty. A plain re-announce batch with no new spawns must still go out.
   - The client already handles a re-announce of a drawn body: `spawnEntity`'s alive branch
     keeps its motion, and a still-seeded body moves in place.
   - Cost: one batch of a group's infos per change of state, a handful a minute.

4. **Harness cases, A's:**
   - a resident spawned at rest is announced with `resting == true`;
   - after its group wakes, the next batch re-announces it with `resting == nil`;
   - after home → rest, it is re-announced with `resting == true` again;
   - a wave body (no group) never carries `resting`;
   - a body that was queued for a re-announce and then removed in the same step still gets its
     `CrowdRemove`.

   Mutations to pair with them:
   - drop the re-announce in `queueEvent`;
   - write `info.resting = nil` in `refreshInfo`;
   - queue the re-announce through `pendingSpawnSet`, which the last case catches.

### luau-engineer B (harness)

The `CampAim` source line, the 12 cases and the 6 mutations above.

### Note for the lead

`CampAim` refuses a resting body even while the player is engaged. Fodder in B may be fighting
him while a fire group of B still sits there; a phone must not wake the fire group by itself.
