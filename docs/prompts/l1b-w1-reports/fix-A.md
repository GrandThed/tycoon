# L1b Wave 1 fix round — luau-engineer A (the crowd)

Brief: `docs/prompts/l1b-w1-fix-round.md` "A — the crowd"; findings `docs/prompts/l1b-w1-review/crowd.md`.
Base `e2479c3`; nothing of A's was done when this round started.

## Files changed

- `src/shared/Types.luau`: `CampRulesConfig.engagedHoldSeconds: number` (that line only).
- `src/combat/server/Services/CampBrain.luau`: rounded `InPlay`; new pure `CampBrain.Engaged`;
  `engagedHoldSeconds` added to `RULE_KEYS`, so `Problems` reports it missing, non-finite or negative.
- `src/combat/server/Services/CrowdService.luau`: `camp.engaged` is now userId -> the step clock it was
  last in play for a group in rise or fight; pruned at the end of each camp step; `Engaged` asks
  `CampBrain.Engaged`.
- `tools/crowd_harness/tests_l1b_crowd.luau`: the cases below; `L1BC.rules()` gains
  `engagedHoldSeconds = 1.5`.
- `CrowdBrain.luau`: no change was needed.

## 1. Major: in play with rounded corners (done)

`CampBrain.InPlay` now measures the flat distance from the root to the floor rectangle (0 inside) and
compares it with `chaseMargin`, edge included:

```luau
local margin = rules.chaseMargin
local outX = math.max(math.abs(root.X - rect.x) - rect.hx, 0)
local outZ = math.max(math.abs(root.Z - rect.z) - rect.hz, 0)
if math.sqrt(outX * outX + outZ * outZ) <= margin then
```

The height band and the shooters' reach are unchanged. The line `local margin = rules.chaseMargin` stays,
so the existing mutation "in play ignores chaseMargin" still applies and is still caught.

Cases use a rect with half sizes 30 × 20 and margin 3:
- (33, 20) is in play: on the margin past the corner, straight out.
- (33, 20.01) and (30.01, 23) are not.
- (32.12, 22.12) is in play: 2.998 from the corner.
- (32.2, ±22.2) is not: 3.11 from the corner, though inside the old square.

## 2. Minor: engaged holds (done)

The pure rule:

```luau
function CampBrain.Engaged(lastAt: number?, now: number, rules: Types.CampRulesConfig): boolean
	return lastAt ~= nil and now - lastAt <= rules.engagedHoldSeconds + TIME_EPSILON
end
```

- `now` is the crowd's step clock (`simTime`), and the edge is included. With a hold of 0 the old
  behaviour returns: engaged at that step only.
- Each camp step stamps `engaged[userId] = simTime` for every userId in `inPlay` of a group with a
  living member in `rise`/`fight`, then drops the entries the rule no longer holds.
- `CrowdService.Engaged(userId)` = `rules ~= nil and CampBrain.Engaged(camp.engaged[userId], simTime, rules)`.
- With no camp rules (range, lobby) the map is cleared, as before. `forgetGroups` (`Clear`,
  `SetFloors`) clears it too.
- `ClearFloor` leaves it alone: after a skip's drop a player can stay engaged for at most 1.5 s.

`inPlay`, and with it L1b-7's damage rule, is not held.

Cases:
- **Pure:** nil; the same step; 1 s and 1.5 s after (true); 1.51 s (false); a hold of 0.
- **`Problems`:** a missing or negative `engagedHoldSeconds` is one line; 0 is fine.
- **Crowd, a fall out of a fight:** first out of the band, then under killY 8 steps later (0.6 s): still
  engaged.
- **Crowd, the wake test:**
  - out of play a step later: still engaged;
  - 22 steps (1.47 s): still engaged;
  - 23 steps (1.53 s): not.

## 3. Minor: `home` tested (done)

These are in `leashTests`, right after the group goes home:
- `Awake() == 1`;
- `Busy()[1] == nil`;
- the root walked back into play for one step during the walk home gives `not Engaged(7)`. The root
  then goes back out, so sight cannot wake the group when it rests.

## Gates (A's files)

- **Harness:** `HARNESS: PASS (1,547 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`, with
  the worktree's state at the time, which includes B's and the economy designer's edits in progress.
- **My own scratch run of A's 7 new mutations** (not mutate.py; a copy outside the repo): baseline PASS
  1,547, all 7 caught. My copy also needed `tools/check_levels.py` and `tools/sim_range.py`. Without them,
  5 "check_levels Part counts" checks fail in the copy. B: check that mutate.py's baseline still passes.
- **mutate.py's existing entries:** every entry's text still occurs exactly once (checked by reading its
  dict). No existing entry changed.
- **Format and compile:**
  - `stylua --check` and `selene` on Types, CampBrain, CrowdService and CrowdBrain: clean.
  - `py tools/check_compile.py`: PASS, 152 files.
- **luau-lsp** with `--definitions=tools/types/globalTypes.d.luau` and fresh sourcemaps (in scratch):
  - hub: clean;
  - combat: 0 errors in A's files. The 4 errors are all `StageFlow.luau:1596` ("Cannot call a value of
    type {CrowdAttackDef} in union {CrowdAttackDef} | {}"). That is B's in-progress edit. For B.

## Mutations for B (`mutate.py`, `L1B_CROWD_MUTATIONS`; CAMP and CROWD as in the file)

```python
    "l1b crowd: in play has square corners": (
        CAMP,
        "if math.sqrt(outX * outX + outZ * outZ) <= margin then",
        "if outX <= margin and outZ <= margin then",
    ),
    "l1b crowd: no engaged hold": (
        CAMP,
        "return lastAt ~= nil and now - lastAt <= rules.engagedHoldSeconds + TIME_EPSILON",
        "return lastAt ~= nil and now - lastAt <= TIME_EPSILON",
    ),
    "l1b crowd: the engaged hold never ends": (
        CAMP,
        "return lastAt ~= nil and now - lastAt <= rules.engagedHoldSeconds + TIME_EPSILON",
        "return lastAt ~= nil",
    ),
    "l1b crowd: Engaged reads the last step only": (
        CROWD,
        "return rules ~= nil and CampBrain.Engaged(camp.engaged[userId], simTime, rules)",
        "return rules ~= nil and camp.engaged[userId] == simTime",
    ),
    "l1b crowd: Awake leaves out a group walking home": (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and state ~= "rest" then',
        'if #group.bodies > 0 and not group.brain.held and (state == "rise" or state == "fight") then',
    ),
    "l1b crowd: Busy counts a group walking home": (
        CROWD,
        'if #group.bodies > 0 and not group.brain.held and (state == "rise" or state == "fight") then',
        'if #group.bodies > 0 and not group.brain.held and state ~= "rest" then',
    ),
    "l1b crowd: a group walking home engages": (
        CROWD,
        'if #members > 0 and (brain.state == "rise" or brain.state == "fight") then',
        'if #members > 0 and brain.state ~= "rest" then',
    ),
```

The last three are crowd.md Minor 2's three survivors.

## For the other owners

- **economy-designer (mirrors):**
  - `InPlay` is `hypot(max(|x−rx|−hx, 0), max(|z−rz|−hz, 0)) <= chaseMargin`, in the band, or within a
    shooter's reach.
  - `CampBrain.Engaged(lastAt, now, rules)` is `lastAt is not None and now − lastAt <= engagedHoldSeconds + 1e-6`.
  - `Problems` now lists `engagedHoldSeconds` among its rule keys (`CB_RULE_KEYS` in `sim_range.py`).
    `Combat.json` already has the key at 1.5.
- **B:** `WaveService` needs no change. `rescueFallen` and the Abandon read already go through
  `CrowdService.Engaged`, which now holds for 1.5 s.
