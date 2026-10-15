# L1b Wave 2 fix round — luau-engineer A (the crowd)

## A-1: the new `SwingGate` API (LANDED, `src/shared/SwingGate.luau`)

For the ui-engineer (ui-1). Pure; the caller casts the rays.

```lua
export type State = {
	used: boolean, -- an airborne swing was taken since the last landing
	airborne: boolean, -- the last sample's verdict
	falling: boolean, -- in a fall that has neither landed nor turned
	lowest: number, -- lowest excess over the grounded band in that fall
	fallSpeed: number, -- fastest fall in it (studs/s, positive down)
	lastY: number?, -- the last sample's root Y
	ahead: boolean, -- a claim already took this fall's landing
}
SwingGate.AIR_MARGIN_STUDS: number -- 0.75 (unchanged)
SwingGate.TURN_WINDOW_SECONDS: number -- 0.1
SwingGate.STILL_SPEED: number -- 1 (studs/s)
SwingGate.FOOTPRINT: { { number } } -- { {0,0}, {1,1}, {1,-1}, {-1,1}, {-1,-1} }
SwingGate.PROBE_POINTS: number -- 5
SwingGate.New(): State
SwingGate.ProbePoint(index: number, x: number, z: number, rightX: number, rightZ: number, halfX: number, halfZ: number): (number, number)
SwingGate.Higher(floorY: number?, hitY: number?): number?
SwingGate.IsAir(height: number?, standOffset: number): boolean -- unchanged
SwingGate.Observe(state: State, y: number, vy: number, floorY: number?, standOffset: number, down: boolean): boolean
SwingGate.Judge(state: State, y: number, floorY: number?, standOffset: number, lagSeconds: number): (boolean, boolean) -- (allowed, airborne)
SwingGate.Allows(state: State, airborne: boolean): boolean -- unchanged
SwingGate.Took(state: State, airborne: boolean): () -- unchanged
SwingGate.Landed(state: State): () -- now a full reset (new character)
```

### How the server feeds it (do exactly the same on the client)

**The footprint probe**, at a point `p` (the root's position for a sample, the swing's origin for
a judge), for the root `root`:

```lua
local floorY: number? = nil
local right = root.CFrame.RightVector
local halfX, halfZ = root.Size.X / 2, root.Size.Z / 2
for index = 1, SwingGate.PROBE_POINTS do
	local x, z = SwingGate.ProbePoint(index, p.X, p.Z, right.X, right.Z, halfX, halfZ)
	local hit = Workspace:Raycast(
		Vector3.new(x, p.Y + HitShapes.GROUND_PROBE_LIFT, z),
		Vector3.new(0, -HitShapes.GROUND_PROBE_DEPTH, 0),
		params -- Exclude every player's character, RespectCanCollide = true (as today)
	)
	floorY = SwingGate.Higher(floorY, if hit ~= nil then hit.Position.Y else nil)
end
```

**Every frame** (server: Heartbeat in `trackAir`; client: one per frame, Heartbeat or
RenderStepped, either):

```lua
SwingGate.Observe(gate, root.Position.Y, root.AssemblyLinearVelocity.Y, floorY, standOffset, isDown)
```

- `standOffset` = `humanoid.HipHeight + root.Size.Y / 2` (as today).
- `isDown`: server `VitalsService.IsDown(player)`, client `MovementController.IsDown()`.
- With no root or Humanoid, skip the sample (the server resets with `Landed` on a new character).

**At a melee swing**, before it is predicted or sent, probe at the swing origin (the client:
the root's position, which it sends) and:

```lua
local allowed, airborne = SwingGate.Judge(gate, origin.Y, floorY, standOffset, 0) -- client: lag 0
if not allowed then drop the swing end
-- ... once sent / accepted:
SwingGate.Took(gate, airborne)
```

The server passes `lagSeconds = Tuning.CommitLag(config.shooting, player:GetNetworkPing())`.

**New character:** `SwingGate.Landed(gate)` (or a fresh `SwingGate.New()`).

**Drop the `Humanoid.StateChanged` → `Landed` clear** on the client: the rule's own samples clear
on every landing the server can see. A client that also clears on events the server cannot see is
the one way left to send a swing the server refuses.

## State: DONE (A-1, A-2, A-3, and the lead's ui-2 request)

### A-1, rule details the API above does not say
- Direction of a sample is its **height change** since the last sample; the vertical speed only
  when the height did not change. The server's copy is interpolated: its replicated speed still
  points down for a frame after the copy is already rising off the floor, which counted every
  20 Hz bounce twice when the speed came first (a harness case and a mutation pin it).
- A turn counts as a landing when the fall's lowest sample is within `fallSpeed x 0.1 s` of the
  grounded band (fastest fall of that fall only, not the rise). A double jump counts only that
  close to the floor: 10 studs up the fall it does not (case), about 6 studs at full fall speed
  it does (by design: it is a landing in all but name).
- **Lag (beyond the reviewer's fix):** the server's copy trails the client by the commit lag, so
  a swing sent just after a bounce reaches `OnAttack` while the copy is still falling. `Judge`
  with `lagSeconds` counts the landing "ahead" when the copy's fall is within
  `fallSpeed x (0.1 + lag)` of its floor; the copy's own later landing then does not clear a
  second time. Lenient only on the server; a cheating client can gain at most a swing in the
  last lag of a fall. **Corrected in the fix-diff round** (`fix-diff-round.md`, review M1): as
  shipped here the branch had no lag guard, so the client (lag 0) took it too and allowed a
  second swing late in every fall. It now acts only when `lagSeconds > 0`, and its reach counts
  gravity over the lag.
- `WeaponService`: new local `footprintFloor(position, root, params)` (5 rays); `trackAir` feeds
  `SwingGate.Observe` every Heartbeat with `VitalsService.IsDown(player)`, and no longer calls
  `SwingGate.Landed` (the slam's own peak/dive/landing tracking is unchanged, still on
  `floorBelow`); `OnAttack` probes the footprint at the clamped claim and calls `Judge` with
  `Tuning.CommitLag(config.shooting, player:GetNetworkPing())`.

### A-2
The dormant case now lets the patroller walk first (root 20 from its floor), checks it walks
(`move`), freezes it, and asserts `Crowd.Get(id).state == "idle"`: the field `refreshInfo` copies
(the infos case already pins that copy to a late joiner). The reviewer's mutation is caught.

### A-3
`tests_s2.luau`'s "a giant standing far away costs the packed crowd nothing" counts grid cells
the separation pass visits: new `CrowdService.SeparationCells(): number` (a counter `perf.cells`,
one add per body per step). 990 = 990; the existing mutation "separate: a giant widens what every
body scans" now reads 990 vs 2,750, deterministic. No timing left in the case.

### ui-2 (lead's routing of fix-ui.md "For the other owner" A) — DONE
- `Types.CrowdSpawnInfo.resting: boolean?`, verbatim from fix-ui.md.
- `refreshInfo` writes `resting = true` when the body's group is `held` or in `rest`, else nil.
- **Dormant bodies read resting: yes** (`CampBrain.Dormant` is true only for a group in `rest`).
- Re-announce: `queueEvent`, when `from == "rest" or to == "rest"`, queues the group's bodies in
  `camp.reannounce` / `camp.reannounceOrder` (in the `camp` table, so no new top-level local;
  never `pendingSpawnSet`); `flushLifecycle` sends them first in the batch (skipping removed, dead
  or still-pending ids) and now fires a batch that holds only re-announces; `forgetGroups`
  (so `Clear`) clears the queue.
- The same-step remove hazard fix-ui.md names cannot happen with today's code (the flush follows
  every simulate in the same Heartbeat, and nothing inside a step removes a living group member),
  so "queue through pendingSpawnSet" would be an equivalent mutant: not proposed. The case "a
  body removed while its re-announce is due gets its CrowdRemove" is kept as a guard. "resting
  ignores held" was also equivalent (a held group is always in `rest`) and is dropped.

## Gates (2026-10-14)
- `run_harness.py . <main checkout luau.exe>`: **PASS (1,969 checks)**.
- My 15 mutations below plus the existing giant one, on a scratch copy of the worktree: all
  caught (`mutate.py` not run: B's).
- `stylua --check` and `selene` clean on `SwingGate`, `Types`, `CrowdService`, `WeaponService`
  (harness case files are not stylua-formatted at HEAD either; left as they were).
- `luau-lsp analyze` of `src/combat` (fresh combat sourcemap) clean; `SwingGate`/`Types` against
  the hub sourcemap clean.
- `py tools/check_compile.py`: PASS, 156 files.

## For the other owner

**For B (`mutate.py`):** add to `MUTATIONS` (`SWING` and `CROWD` are already defined there):

```python
SWING = "src/shared/SwingGate.luau"
CROWD = "src/combat/server/Services/CrowdService.luau"

L1B_W2_FIX_A_MUTATIONS = {
    # A-1: SwingGate's one landing rule
    "l1b w2 fix A: a turn near the floor is no landing": (
        SWING,
        "if math.min(state.lowest, excess) <= reach then",
        "if false then",
    ),
    "l1b w2 fix A: a fall that ends grounded is no landing": (
        SWING,
        "if state.airborne or state.falling then\n\t\t\tlanded = true",
        "if false then\n\t\t\tlanded = true",
    ),
    "l1b w2 fix A: the fall's lowest sample not kept": (
        SWING,
        "state.lowest = math.min(state.lowest, excess)\n\t\t\tstate.fallSpeed",
        "state.lowest = state.lowest\n\t\t\tstate.fallSpeed",
    ),
    "l1b w2 fix A: direction from the replicated speed first": (
        SWING,
        "local sinking = step < 0 or (step == 0 and vy < -SwingGate.STILL_SPEED)",
        "local sinking = vy < -SwingGate.STILL_SPEED or (step < 0 and vy <= SwingGate.STILL_SPEED)",
    ),
    "l1b w2 fix A: the footprint is the centre only": (
        SWING,
        "SwingGate.FOOTPRINT = { { 0, 0 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }",
        "SwingGate.FOOTPRINT = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }",
    ),
    "l1b w2 fix A: Higher keeps the lower floor": (
        SWING,
        "return math.max(floorY, hitY)",
        "return math.min(floorY, hitY)",
    ),
    "l1b w2 fix A: ProbePoint's back axis not turned": (
        SWING,
        "local bx, bz = -rz, rx",
        "local bx, bz = rx, rz",
    ),
    "l1b w2 fix A: a down does not clear": (
        SWING,
        "if down then\n\t\tstate.used = false",
        "if down then\n\t\tstate.used = state.used",
    ),
    "l1b w2 fix A: the claim's landing ahead never taken": (
        SWING,
        "state.used = false\n\t\t\tstate.ahead = true",
        "state.used = true\n\t\t\tstate.ahead = true",
    ),
    "l1b w2 fix A: Judge without the lag": (
        SWING,
        "(SwingGate.TURN_WINDOW_SECONDS + lag)",
        "(SwingGate.TURN_WINDOW_SECONDS)",
    ),
    "l1b w2 fix A: a landing taken ahead counted again": (
        SWING,
        "if state.ahead then\n\t\tstate.ahead = false\n\telse",
        "if false then\n\t\tstate.ahead = false\n\telse",
    ),
    # A-2: the freeze-time reset (the reviewer's mutation)
    "l1b w2 fix A: a frozen patroller keeps its walking state": (
        CROWD,
        "body.state = CampBrain.Shows(brain, false) or body.state",
        "body.state = body.state",
    ),
    # ui-2: resting on the spawn info
    "l1b w2 fix A: no re-announce at a change to or from rest": (
        CROWD,
        'local restChanged = from == "rest" or to == "rest"',
        "local restChanged = false",
    ),
    "l1b w2 fix A: refreshInfo never writes resting": (
        CROWD,
        'info.resting = if group ~= nil and (group.brain.held or group.brain.state == "rest")',
        'info.resting = if false and (group.brain.held or group.brain.state == "rest")',
    ),
    "l1b w2 fix A: a batch of re-announces alone is never sent": (
        CROWD,
        "if #pendingSpawnOrder > 0 or #camp.reannounceOrder > 0 then",
        "if #pendingSpawnOrder > 0 then",
    ),
}
```

Existing SwingGate mutations ("Took ignores airborne", "Landed does nothing", "Allows ignores
used", "IsAir with >=") still match exactly once. The existing "separate: a giant widens what
every body scans" is now caught by a count, not a clock.

**For the lead / contract:** new exports not in the contract: `SwingGate.TURN_WINDOW_SECONDS`,
`STILL_SPEED`, `FOOTPRINT`, `PROBE_POINTS`, `ProbePoint`, `Higher`, `Observe`, `Judge`;
`CrowdService.SeparationCells()`; `CrowdSpawnInfo.resting`. `TURN_WINDOW_SECONDS` (0.1) is a
module constant like `AIR_MARGIN_STUDS`; propose a `Combat.json` key only if Ben should tune it.

## What to check in Studio
1. Held Space + held attack with a sword in `fight`: one swing per hop, no refusals in RangeStats,
   also with Studio's network simulator at 150-250 ms.
2. On the Road4 -> Road5 lip, the lookout ledge and a cover block's edge: every swing goes out.
3. A double jump high in a jump does not give a second swing.
4. Phone emulator, auto-fire on: the sneak past a resting camp fires at nobody; once it wakes it
   is taken; after it walks home and rests it is left alone again.
