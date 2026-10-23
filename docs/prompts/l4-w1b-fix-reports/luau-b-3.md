# L4 W1b fix round 3 — luau-engineer B (H1: the clear waits for a held blow)

Worktree `tycoon-p5c`, branch `l4-w1b-fix2`, nothing committed. Rulings: `docs/prompts/l4-w1b-fix3.md` H1; finding m3:
`docs/prompts/l4-w1b-review/5-fix2-diff.md`. A's `VitalsService.HasWaiting(player: Player?): boolean` (luau-a-3.md)
is exactly the signature I coded against.

## Files changed

- `src/combat/server/Services/WaveService.luau`: H1.
- `tools/crowd_harness/tests_l4b_run.luau`: a new group "l4b H1 holdTests" (22 checks), and the Forest Road plan
  moved into a helper `L4R.forestPlan()` that `shippedTests` now calls (no change to what it checks).

## Contracts (signatures)

- `local function fieldHeld(plan: StageFlow.Plan, flow: StageFlow.State, input: StageFlow.Input, now: number, delta: number?): boolean` (new)
- `local function advance(combatConfig: Types.CombatConfig, delta: number?): ()` (was `advance(combatConfig)`)
- `local function tick(delta: number): ()` (was `tick()`); `WaveService.Boot`'s Heartbeat passes its `delta`.
- `WaveService.OnDown` unchanged: it calls `advance(combatConfig)`, so `delta` is nil there.
- New `Run` fields: `blowWaits: boolean` (false), `heldSince: number` (0). `freshRun` resets both.
- New require: `DashProof` (pure, already required by WeaponService). WaveService: 99 top-level locals.

## H1 as built (what the simulator mirrors)

1. **The rule.** While any fighter (ArenaService.IsFighting: not waiting, alive) has a decision in their
   `waiting` list, the field never reads clear. WaveService does this by setting `input.spawningDone = false`
   when the field would otherwise read clear (`StageFlow.FieldClear` reads it first). StageFlow is unchanged.
   - No clear runs, so no `ClearThreats` erases the blow. The `end` that follows the boss room's last clear waits too.
   - A down the blow causes is judged on a field that is not clear: `fallen` wins, so a lost solo run stays lost.
   - Merges are unaffected: they only run when the field is not clear.
2. **Every frame (the tick, `delta` = its frame).** `blowWaits` is refreshed from HasWaiting. `heldSince` is the
   first tick in a row whose clear field a waiting blow held; it goes back to 0 at any tick where nothing waits
   or the field would not be clear.
3. **The down's advance (`delta` nil), inside VitalsService.Step.** The release that downed the player has
   already emptied their list, so HasWaiting is false there (A's report says so; my test checks it). The field
   stays held on the last tick's finding: `(waits or run.blowWaits) and FieldClear`. Only the tick refreshes
   `blowWaits`.
4. **The cap.** The tick never holds a clear field longer than `lapse + delta` from `heldSince`. `lapse` is
   `DashProof.Rule(Tuning.Get().movement, Tuning.Get().shooting).lapse`, the rule WeaponService proves claims by
   (0 if there is no rule, and then no claim can ever wait).
   - Each list empties by its claim's lapse, so the cap never bites in correct play.
   - It stops a list that never empties from holding the run until its cap.
   - Why `+ delta`: with the tick first, the tick of the release frame runs before VitalsService releases. Frame
     jitter would otherwise let a cap of exactly one lapse expire a frame early and erase the blow.
5. **An honest claim proven.** VitalsService voids the held blow in that Step. The next tick sees nothing waiting
   and the clear goes through: in the proof's own frame (the proofs first) or the next one (the tick first).

## Rulings I took (for the lead)

- **R1. The hold applies to every field-clear verdict, not only the boss room's.**
  - On the road, a solo down from a held blow, released after the last awake raider fell, now loses the run, as
    it does with no dash. Before this, L1b-19's "a clear field wins" spared it: the same m3 class.
  - StandsUp waits with the field (at most a lapse).
  - `campClear` and its bonus are not touched: `progress` does not read `spawningDone`.
  - If you want the boss room only, replace two lines in `fieldHeld`:
    - Old: `\t\treturn (waits or run.blowWaits) and StageFlow.FieldClear(plan, flow, input)`
      New: `\t\treturn (waits or run.blowWaits) and flow.step == "fight" and StageFlow.FieldClear(plan, flow, input)`
    - Old: `\tif not waits or not StageFlow.FieldClear(plan, flow, input) then`
      New: `\tif not waits or flow.step ~= "fight" or not StageFlow.FieldClear(plan, flow, input) then`
- **R2. The Studio levers are not held.** The N/B skip and `wave` (`StageFlow.Skip`/`Force`) reach ClearThreats
  through `drop`, which pays nothing and is Studio only. `EndRun` (abandon, run cap), `backToLobby` and `Reset`
  still clear at once: they are ends, not clears.
- **R3. "Fighter" means ArenaService.IsFighting.** A waiting or dead member's list lands nothing: their next
  release drops it.

## Verification

- **Harness in the worktree:** `HARNESS: PASS (4,213 checks)`. It ran with A's edits as they stood; the new group
  is 22 checks, all ok.
  - A fresh scratch copy (src, tools, docs, project files) read the same.
- **The group "l4b H1 holdTests".**
  - Setup:
    - the real StageFlow on Forest Road's boss room in its last wave;
    - a real VitalsService of the file's own, with WeaponService's hooks and the mission's onDown;
    - the real DashProof.Step;
    - a line-for-line copy of `fieldHeld` and advance's use of it.
  - Every case runs in both Heartbeat orders (the tick first, the proofs first).
  - The cases:
    - **No dash:** down at 0.1, the run lost.
    - **A claim that never proves**, the boss dead at 0.3: the held slam lands as the claim lapses (0.467), downs
      him, and the run ends `down` with no clear. His list is already empty when that down is judged.
    - **Control, field never held:** the clear at the kill erases the slam and the solo run is won (m3 itself).
    - **Control, no latch:** the down meets a clear field and the run is won.
    - **An honest dash proven at 0.333**, after the kill at 0.2: dodged, nothing lost, the clear 0 or 1 frame
      after the proof, `cleared`.
    - **A slam that does not down:** it lands as the claim lapses, then the clear goes through.
    - **Co-op, a partner standing:** the held down loses nothing; cleared after it, as with no dash.
    - **The road (R1):** the held down after the last awake raider fell loses the solo run, as with no dash.
      Never held, the run goes on.
    - **A list that never empties (HasWaiting stubbed true):** the clear goes through 0.467 s after the hold
      began. Without the cap, never.
    - **Nothing waiting:** the clear on the kill's own frame, never held.
- **Static checks:**
  - `stylua --check` on both files: clean.
  - selene on WaveService: 0 errors, 0 warnings. On the case file, only the bundle-scope names (`check`, `load`,
    `FIXTURES`, ...), the class every case file has (A's `tests_l4b.luau` reads 191 of them).
  - luau-lsp on both sourcemaps (written to scratch, hub `src/client src/server src/shared`, combat
    `src/combat src/shared`): 0 diagnostics. A planted error in `fieldHeld` (scratch copy) was reported.
  - `py tools/check_compile.py`: PASS, 176 files.
- **mutate.py stale check (exec'd up to its baseline):** 1,795 entries, 2 stale, both A's (VitalsService, H2):
  - `l4b f1: settle drops a held entry`
  - `l4b g1: the release drops one that still waits`
  - None in WaveService.
- **Pins and mutants below:** pre-checked with `run_harness.py`'s own `luau_code` and `whole_lines` (scratch
  `premut.py`). All 25 pins and 2 orders read their expected counts, and 18 of 18 mutants move at least one pin.

## Known limits

1. **Co-op dashes in turn under steady attack while the field already reads clear** can outlast the cap. The cap
   counts from the first tick that held the field, so a later claim's blow could then be erased (the pre-fix
   behaviour for that one blow). This needs strikers alive on a clear field: another floor's body in the boss
   room, or a body outside every awake group on the road.
2. **A run that ends on its cap (or an abandon) with a down still waiting** reads `runCap` (or `abandoned`), not
   `down`, and marks nobody died. Never a win, no star.
3. **For a dash that never proves, the clear banner and the summary come up to a lapse (0.45 s) after the boss
   dies.** For an honest one, the proof's latency plus a frame. The HUD shows the boss room fighting meanwhile.

## For the other owners

### Designer: run_harness.py (new bodies, beside the other L4 W1b ones)

```python
FIELD_HELD_BODY = re.compile(r"(?ms)^local function fieldHeld\(.*?^end$")
ADVANCE_BODY = re.compile(r"(?ms)^local function advance\(.*?^end$")
TICK_BODY = re.compile(r"(?ms)^local function tick\(.*?^end$")
BOOT_BODY = re.compile(r"(?ms)^function WaveService\.Boot\(.*?^end$")
ON_DOWN_BODY = re.compile(r"(?ms)^function WaveService\.OnDown\(.*?^end$")
FRESH_RUN_BODY = re.compile(r"(?ms)^local function freshRun\(.*?^end$")
```

### Designer: run_harness.py `L4B_LINES` (add; expected count after each)

```python
    # H1 (docs/prompts/l4-w1b-fix3.md, luau-b-3.md), WaveService: the field is held while a blow waits.
    'h1Body': (WAVE_SERVICE, FIELD_HELD_BODY, 'text', '\tlocal waits = false\n\tfor _, member in ArenaService.GetMembers() do\n\t\tif ArenaService.IsFighting(member) and VitalsService.HasWaiting(member.player) then\n\t\t\twaits = true\n\t\t\tbreak\n\t\tend\n\tend\n\tif delta == nil then\n\t\treturn (waits or run.blowWaits) and StageFlow.FieldClear(plan, flow, input)\n\tend\n\trun.blowWaits = waits\n\tif not waits or not StageFlow.FieldClear(plan, flow, input) then\n\t\trun.heldSince = 0\n\t\treturn false\n\tend\n\tif run.heldSince == 0 then\n\t\trun.heldSince = now\n\tend\n\tlocal tuning = Tuning.Get()\n\tlocal rule = DashProof.Rule(tuning.movement, tuning.shooting)\n\tlocal lapse = if rule ~= nil then rule.lapse else 0\n\treturn now - run.heldSince <= lapse + delta\nend'),  # 1
    'h1Asks': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\t\tif ArenaService.IsFighting(member) and VitalsService.HasWaiting(member.player) then'),  # 1
    'h1DownKeeps': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\t\treturn (waits or run.blowWaits) and StageFlow.FieldClear(plan, flow, input)'),  # 1
    'h1Notes': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\trun.blowWaits = waits'),  # 1
    'h1ClearOnly': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\tif not waits or not StageFlow.FieldClear(plan, flow, input) then'),  # 1
    'h1Resets': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\t\trun.heldSince = 0'),  # 1
    'h1Starts': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\t\trun.heldSince = now'),  # 1
    'h1Rule': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\tlocal rule = DashProof.Rule(tuning.movement, tuning.shooting)'),  # 1
    'h1Lapse': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\tlocal lapse = if rule ~= nil then rule.lapse else 0'),  # 1
    'h1Cap': (WAVE_SERVICE, FIELD_HELD_BODY, 'lines', '\treturn now - run.heldSince <= lapse + delta'),  # 1
    'h1Writes': (WAVE_SERVICE, None, 'regex', r'\brun\.(?:blowWaits|heldSince)\s*=(?!=)'),  # 3
    'h1Defs': (WAVE_SERVICE, None, 'lines', 'local function fieldHeld('),  # 1
    'h1Calls': (WAVE_SERVICE, None, 'regex', r'\bfieldHeld\('),  # 2 (its definition and advance)
    'h1AdvanceDelta': (WAVE_SERVICE, None, 'lines', 'local function advance(combatConfig: Types.CombatConfig, delta: number?): ()'),  # 1
    'h1AdvanceHolds': (WAVE_SERVICE, ADVANCE_BODY, 'lines', '\tif fieldHeld(plan, flow, input, now, delta) then'),  # 1
    'h1AdvanceHoldWrites': (WAVE_SERVICE, ADVANCE_BODY, 'lines', '\t\tinput.spawningDone = false'),  # 1
    'h1SpawningWrites': (WAVE_SERVICE, None, 'regex', r'\binput\.spawningDone\s*=(?!=)'),  # 1
    'h1AdvanceCalls': (WAVE_SERVICE, None, 'regex', r'(?<![\w.])advance\(combatConfig[,)]'),  # 2 (tick and OnDown)
    'h1TickDelta': (WAVE_SERVICE, None, 'lines', 'local function tick(delta: number): ()'),  # 1
    'h1TickAdvance': (WAVE_SERVICE, TICK_BODY, 'lines', '\tadvance(combatConfig, delta)'),  # 1
    'h1DownAdvance': (WAVE_SERVICE, ON_DOWN_BODY, 'lines', '\t\tadvance(combatConfig)'),  # 1
    'h1BootTick': (WAVE_SERVICE, BOOT_BODY, 'lines', '\t\ttick(delta)'),  # 1
    'h1FreshBlowWaits': (WAVE_SERVICE, FRESH_RUN_BODY, 'lines', '\t\tblowWaits = false,'),  # 1
    'h1FreshHeldSince': (WAVE_SERVICE, FRESH_RUN_BODY, 'lines', '\t\theldSince = 0,'),  # 1
    'h1DashProof': (WAVE_SERVICE, None, 'lines', 'local DashProof = require(script.Parent:WaitForChild("DashProof"))'),  # 1
```

### Designer: run_harness.py `L4B_ORDER` (add)

```python
    'h1InputThenHold': (WAVE_SERVICE, ADVANCE_BODY, 'runCap = run.runEndsAt > 0 and now >= run.runEndsAt,', 'if fieldHeld(plan, flow, input, now, delta) then'),
    'h1HoldThenAdvance': (WAVE_SERVICE, ADVANCE_BODY, 'input.spawningDone = false', 'local actions = StageFlow.Advance(plan, flow, input, combatConfig.levels)'),
```

### Designer: tests_l3_w2.luau `L4BP` (LINES, then ORDER; counts as above, messages suggested)

```lua
		h1Body = { 1, "fieldHeld as one block: a waiting blow holds a clear field, the down keeps the tick's finding, the cap (H1)" },
		h1Asks = { 1, "fieldHeld asks HasWaiting of every fighter" },
		h1DownKeeps = { 1, "the down's advance keeps the last tick's finding (its list is already empty)" },
		h1Notes = { 1, "the tick notes what it found" },
		h1ClearOnly = { 1, "only a field that would read clear is held" },
		h1Resets = { 1, "the deferral starts over when nothing waits" },
		h1Starts = { 1, "the deferral's start is noted" },
		h1Rule = { 1, "the lapse is the rule WeaponService proves claims by" },
		h1Lapse = { 1, "no rule, no lapse (nothing can wait)" },
		h1Cap = { 1, "never held longer than a lapse and the frame" },
		h1Writes = { 3, "blowWaits and heldSince are written only in fieldHeld" },
		h1Defs = { 1, "fieldHeld is defined once" },
		h1Calls = { 2, "fieldHeld( twice: its definition and advance" },
		h1AdvanceDelta = { 1, "advance takes the frame (nil from OnDown)" },
		h1AdvanceHolds = { 1, "advance asks fieldHeld with the frame" },
		h1AdvanceHoldWrites = { 1, "a held field does not read clear" },
		h1SpawningWrites = { 1, "input.spawningDone is written only there" },
		h1AdvanceCalls = { 2, "advance is called by the tick and by OnDown" },
		h1TickDelta = { 1, "tick takes the Heartbeat's frame" },
		h1TickAdvance = { 1, "the tick passes its frame to advance" },
		h1DownAdvance = { 1, "OnDown passes none: the down keeps the tick's finding" },
		h1BootTick = { 1, "Boot's Heartbeat passes its frame to the tick" },
		h1FreshBlowWaits = { 1, "a run starts with no blow found" },
		h1FreshHeldSince = { 1, "and no deferral" },
		h1DashProof = { 1, "WaveService requires DashProof for the lapse" },
```

```lua
		h1InputThenHold = "advance: the hold reads the input it has built",
		h1HoldThenAdvance = "advance: the hold before StageFlow decides",
```

### Designer: mutate.py (a new `L4B_FIX3_MUTATIONS`, merged into MUTATIONS as the fix-2 set is)

| Label | Effect | Caught by |
|---|---|---|
| a waiting blow never found | m3 back: the clear erases the slam and a solo run with a held down is won (the case's `hold = false` control) | h1Body, h1Asks |
| the down's advance forgets the tick's finding | the down meets a clear field and the run is won (`latch = false` control) | h1Body, h1DownKeeps |
| the down's advance never holds | the same | h1Body, h1DownKeeps |
| the tick's finding never noted | `blowWaits` stays false: the same | h1Body, h1Notes, h1Writes |
| the deferral never starts over | every later hold in the run is past the cap at once: m3 from the second held clear on | h1Body, h1Resets, h1Writes |
| the deferral's start never noted | `heldSince` 0, never within the cap: the tick never holds, m3 back | h1Body, h1Starts, h1Writes |
| the deferral never capped | a list that never empties holds the run until its cap (`cap = false` control) | h1Body, h1Cap |
| the cap a frame short | the tick first, with frame jitter: the cap lapses before the release and erases the blow | h1Body, h1Cap |
| the cap at nothing | the hold lasts a frame: m3 back | h1Body, h1Lapse |
| a waiting blow holds a field that is not clear | merges wait while a blow waits, and the deferral counts from the wait (near-equivalent; pin only) | h1Body, h1ClearOnly |
| the hold never asked | m3 back | h1Calls, h1AdvanceHolds, h1InputThenHold |
| the hold changes nothing | m3 back | h1AdvanceHoldWrites, h1SpawningWrites, h1HoldThenAdvance |
| the hold after StageFlow decided | the clear is decided on the unheld input: m3 back | h1HoldThenAdvance |
| the tick passes no frame | the tick takes the down's path: `blowWaits` never written, no cap; the down meets a clear field | h1TickAdvance |
| the down's advance passes a frame | OnDown overwrites the finding with the emptied list: the run is won | h1DownAdvance |
| the tick told a frame of nothing | the cap is the lapse alone (as "a frame short") | h1BootTick |
| a run starts with the deferral spent | equivalent in play (the run's first tick resets it); pin only | h1FreshHeldSince |
| a run starts with a blow found | equivalent in play (the run's first tick refreshes it); pin only | h1FreshBlowWaits |

```python
    'l4b h1: a waiting blow never found': (WAVE_SERVICE, '\t\tif ArenaService.IsFighting(member) and VitalsService.HasWaiting(member.player) then\n', '\t\tif false then\n'),
    "l4b h1: the down's advance forgets the tick's finding": (WAVE_SERVICE, '\t\treturn (waits or run.blowWaits) and StageFlow.FieldClear(plan, flow, input)\n', '\t\treturn waits and StageFlow.FieldClear(plan, flow, input)\n'),
    "l4b h1: the down's advance never holds": (WAVE_SERVICE, '\t\treturn (waits or run.blowWaits) and StageFlow.FieldClear(plan, flow, input)\n', '\t\treturn false\n'),
    "l4b h1: the tick's finding never noted": (WAVE_SERVICE, '\trun.blowWaits = waits\n', ''),
    'l4b h1: the deferral never starts over': (WAVE_SERVICE, '\t\trun.heldSince = 0\n', ''),
    "l4b h1: the deferral's start never noted": (WAVE_SERVICE, '\t\trun.heldSince = now\n', ''),
    'l4b h1: the deferral never capped': (WAVE_SERVICE, '\treturn now - run.heldSince <= lapse + delta\n', '\treturn true\n'),
    'l4b h1: the cap a frame short': (WAVE_SERVICE, '\treturn now - run.heldSince <= lapse + delta\n', '\treturn now - run.heldSince <= lapse\n'),
    'l4b h1: the cap at nothing': (WAVE_SERVICE, '\tlocal lapse = if rule ~= nil then rule.lapse else 0\n', '\tlocal lapse = 0\n'),
    'l4b h1: a waiting blow holds a field that is not clear': (WAVE_SERVICE, '\tif not waits or not StageFlow.FieldClear(plan, flow, input) then\n', '\tif not waits then\n'),
    'l4b h1: the hold never asked': (WAVE_SERVICE, '\tif fieldHeld(plan, flow, input, now, delta) then\n', '\tif false then\n'),
    'l4b h1: the hold changes nothing': (WAVE_SERVICE, '\t\tinput.spawningDone = false\n', ''),
    'l4b h1: the hold after StageFlow decided': (WAVE_SERVICE, '\tif fieldHeld(plan, flow, input, now, delta) then\n\t\t-- StageFlow.FieldClear reads this first: the field does not read clear.\n\t\tinput.spawningDone = false\n\tend\n\tlocal actions = StageFlow.Advance(plan, flow, input, combatConfig.levels)\n', '\tlocal actions = StageFlow.Advance(plan, flow, input, combatConfig.levels)\n\tif fieldHeld(plan, flow, input, now, delta) then\n\t\t-- StageFlow.FieldClear reads this first: the field does not read clear.\n\t\tinput.spawningDone = false\n\tend\n'),
    'l4b h1: the tick passes no frame': (WAVE_SERVICE, '\tadvance(combatConfig, delta)\n', '\tadvance(combatConfig)\n'),
    "l4b h1: the down's advance passes a frame": (WAVE_SERVICE, '\t\tadvance(combatConfig)\n', '\t\tadvance(combatConfig, 0)\n'),
    'l4b h1: the tick told a frame of nothing': (WAVE_SERVICE, '\t\ttick(delta)\n', '\t\ttick(0)\n'),
    'l4b h1: a run starts with the deferral spent': (WAVE_SERVICE, '\t\theldSince = 0,\n', '\t\theldSince = 1,\n'),
    'l4b h1: a run starts with a blow found': (WAVE_SERVICE, '\t\tblowWaits = false,\n', '\t\tblowWaits = true,\n'),
```

Every old text occurs once in WaveService today. "the hold after StageFlow decided" carries the comment line inside
the `if`: mutate.py works on the raw text.

### Designer: sim_range.py

If the simulator models a boss room's clear, mirror H1 there:
- the field reads not clear while any fighter has a decision waiting;
- a down released then is judged on that unclear field (a lost run stays lost);
- the hold is capped at the lapse plus a frame from the first tick that held a clear field.

The WaveService text is held only by the pins above: the harness cannot load WaveService. `L4R.Wave` in
`tests_l4b_run.luau` is the line-for-line copy the cases run.

### luau-engineer A

Nothing required. The two stale mutate entries above come from your H2 edits.

## What to check in Studio

- **A normal boss room clear** (Forest Road, any difficulty, no dash at the end): the clear banner and the summary
  come as before. Output shows no new warning.
- **An honest dash through the Colossus's slam, then the kill** (or the kill-all lever right after the dash): the
  slam reads DODGED and the run clears at once.
- **Optional, the m3 case:** solo, dash into the boss room's wall as the slam lands for more than your health, then
  kill the boss within 0.4 s (the kill-all lever is the easy way). You go down about 0.45 s after the press and the
  run ends lost, with no clear banner first.
