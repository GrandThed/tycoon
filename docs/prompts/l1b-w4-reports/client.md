# L1b Wave 4 — ui-engineer report (client)

Branch `l1b-wave4`, worktree `C:\Users\benja\Desktop\tycoon-p5`. Contract: INTERFACES "L1b Wave 4
— no waits, no walls" -> "Client (ui-engineer)", rulings L1b-W4-32 and -33, gate 4's counts.

## What I built

All four files are under `src/combat/client/Controllers/`.

| File | Function | Change |
|---|---|---|
| `CampAim.luau` | `CampAim.Takes(onCampFloor, resting, phase)` | New signature (L1b-W4-32). Not on a camp floor: true. On one: `phase ~= "gate" and not resting`. The in-play clause (4) and the engaged clause (3) are gone, and so are the `centre`, `half`, `root`, `engaged` and `camps` arguments. The module no longer requires `Types` or `HitShapes`. The header comment is rewritten. |
| `InputController.luau` | `autoMayTake(id)` (was `campInPlay(id, root)`) | Calls `CampAim.Takes(centre ~= nil, resting, missionState.phase)`, with `centre` and `resting` taken from `CrowdRenderer.CampFloor(id)`. The root, `engaged` and `camps` are no longer read there. |
| `InputController.luau` | `enemyInSights`, `enemyInReach`, `targetOnAuto` | The `root` parameter is dropped from the first two, because its only use was the camp rule. `targetOnAuto` still uses the root as the melee origin. |
| `InputController.luau` | `RangeState.engaged`, `InputController.SetPhase(phase, waiting)` | The `engaged` field and the third `SetPhase` argument are removed, because nothing reads them any more. Both callers are mine, so no dead field is left behind. No top-level local was added. |
| `CrowdRenderer.luau` | `Region` require (the one new top-level local the contract allows) | |
| `CrowdRenderer.luau` | `type Floor` | Gains `cells: { Types.CampRect }?`. |
| `CrowdRenderer.luau` | new export `CrowdRenderer.ReadCells(raw): { CampRect }?` | Returns a fresh copy when `raw` is a non-empty dense list of rects where every `x z hx hz` is a finite number and `hx`, `hz` are above 0. Otherwise it returns nil. It is a module field, not a top-level local. |
| `CrowdRenderer.luau` | `SetFloors` | Each floor record keeps `cells = ReadCells(entry.cells)`. A malformed `cells` leaves that floor with its rectangle and does not end the list. A malformed floor entry still ends the list, as before. |
| `CrowdRenderer.luau` | `laneReach` | When the floor has `cells`: `max(min(reach, Region.Runway(cells, Region.Clamp(cells, origin, radius), heading, radius)), 0)`. Otherwise it is today's rectangle cut. The radius is the config kind's, as before. |
| `CrowdRenderer.luau` | `CampFloor` | Same answers. Only its comment changed. |
| `CombatUIController.luau` | `DEBUG_HINT` | Now `"N next camp · B boss · G gear"`. The keys are unchanged, and a one-line comment on `DEBUG_KEYS` cites L1b-W4-31. |
| `CombatUIController.luau` | `applyFloors` (+ nested `sameCells`) | **Required for -33 to work at all, and not named in the contract.** `applyFloors` copied only `x y z hx hz` into the `RunFloor` it hands to `CrowdRenderer.SetFloors`, so the server's `cells` were dropped before they reached the renderer. It now copies `cells = CrowdRenderer.ReadCells(entry.cells)` and also compares cells by value: a RunState comes 4 times a second, and the floors are handed on only when they differ. |
| `CombatUIController.luau` | the RunState party loop | `engaged` is no longer computed or passed to `InputController.SetPhase`. `CombatHud` still reads `member.engaged` itself (line 1195), and that is untouched. |

### Contract rule -> code

- **L1b-W4-32, true when not on a camp floor:** `CampAim.Takes` has `if not onCampFloor then return true`. InputController passes `centre ~= nil`, and `CampFloor` answers nil for the range's arena, for an unknown body and for a floor that has not arrived. All three are taken, as before Wave 1.
- **L1b-W4-32, false in `gate` or for a resting group's body:** `return phase ~= "gate" and not resting`. `resting` is `CampFloor`'s third value, which is `entity.resting` (held and dormant included). A phone still never wakes a camp by itself.
- **L1b-W4-32, true otherwise:** there is no other clause. An awake raider on the road outside its camp, or in another open camp, is taken wherever the local root stands.
- **L1b-W4-32, "the root, engaged and camps are no longer read there":** `autoMayTake` reads only `CampFloor(id)` and `missionState.phase`.
- **L1b-W4-33, the drawn charge cut by `Region.Runway` over `RunFloor.cells` when the floor has them:** `laneReach`'s `cells ~= nil` branch. Both callers use it: `stepRush` (where the body runs to) and `ForEachThreat` (the lane's drawn length and how long it lasts). With no cells, the rectangle cut is byte-identical to before. That covers the Chief's Clearing, the range and the arena.
- **Why the Clamp before Runway (my addition, presentation only):** `threatOrigin` is decoded off the wire at 1/32 stud. A brute standing on the region's inset edge (the server clamps it there, `Region.Clamp`) can decode up to 1/64 stud outside it. `Region.Runway` answers 0 from outside, so the whole lane would vanish. The server's body is inside, so pulling the decoded point back in measures from where the server measured. It allocates nothing (Vector3 values only). The drawn lane still starts at `threatOrigin`.
- **`SetFloors` keeps cells and ignores a malformed list:** `ReadCells` -> `cells = nil`. The `break` is still only for a malformed floor.
- **`CampFloor(id)` keeps its answers:** the code is unchanged.
- **`CombatUIController` `DEBUG_HINT`:** done.
- **Not changed, as the contract lists:** FeedbackController, CombatFxController, CampFx, CombatHud, SummaryCard, MapScreen, MovementController, CameraController, ThreatFx/*, SpawnSeed, Theme.

### Layout

The only visible change is the Studio key line. It is a `TextLabel` 200 px wide at `TEXT_SMALL` 12. "N next camp · B boss · G gear" is 29 characters, about 185 px, so it fits at 1920×1080. It is shown only where `KeyboardEnabled` and only in Studio, so it never appears on a 375×667 or 667×375 phone. No layout, tap target, `UIScale` or `UIAspectRatioConstraint` changed. Reduced motion is not touched.

## Commits

- `f33a72b` L1b Wave 4 client: the four controllers. This report is in the commit after it.

## Verify

- `stylua --check src/combat/client src/shared`: clean. Whole `src`, at my commit: the only diff is in B's in-progress `StageFlow.luau` (three long lines), not mine.
- `selene src`: 0 errors, 2 warnings. One is the expected `LegacyPanel` warning. The other is `shadowing variable need` in B's in-progress `StageFlow.luau:869`. Neither is in my files.
- `py tools/check_compile.py --counts`: `CHECK: PASS -- 157 files compile with Studio settings (-O1 -g2)`. CrowdRenderer is at 154 (the limit is 154) and InputController at 149 (the limit is 149).
- `luau-lsp analyze` (combat sourcemap, `--definitions=tools/types/globalTypes.d.luau`) on `src/combat/client`, with A's Region committed: no diagnostics.
- Gate 12, `git diff --stat main -- src/server src/client`: empty.
- Gate 18 on the client, `rg -n "\.inPlay\b" src/combat/client`: nothing.
- CampAim's new cases and mutations, run against the real file under `tools\bin\luau.exe` in my scratch: the real file passes all 7 cases, and each of the 4 mutations fails 1 or 2 cases.

## Screenshots (Definition of done)

I cannot run Studio, so none are attached. They are the lead's or Ben's to take in `build/proving.rbxl`, on PC and in the 667×375 emulator:
1. A brute's charge telegraph along RoadAB1 into the bend, cut where the road ends. To get it, wake a group of A, walk out of the east gate, and stand on RoadAB1 or RoadAB2 so a brute charges along the road. The lane should end where the road's union ends at the U-bend, not at A's floor edge.
2. A phone auto-firing at an awake raider on the road outside its camp. In the emulator (touch, `autoFire`), wake A, walk out onto Road5 or RoadAB1, and put a chasing raider in the reticle. It fires with no button.

## For other owners

### luau-engineer B: `tools/crowd_harness/tests_l1b_w2.luau`

Replace the whole `CampAim` block (the `do ... end` after "L1b Wave 2 fix round, ui-2: touch auto-target never takes a resting group's body (CampAim).", today's lines 606-662) with this one. Every old case passes the old 7-argument call and goes.

```luau
-- L1b Wave 4 (L1b-W4-32): touch auto-target takes every awake camp body wherever the player
-- stands; never a resting group's body, never a camp body in the countdown (CampAim).
do
	local Aim = load("CampAim")
	check(Aim.Takes(false, false, "travel"), "CampAim: a body with no camp floor is always taken")
	check(
		Aim.Takes(false, true, "gate"),
		"CampAim: a body with no camp floor is taken even in the gate, resting or not"
	)
	check(
		Aim.Takes(true, false, "travel"),
		"CampAim: an awake group's body is taken, wherever the player stands"
	)
	check(
		Aim.Takes(true, false, "fight"),
		"CampAim: after the close an awake body in the boss room is taken"
	)
	check(
		not Aim.Takes(true, true, "travel"),
		"CampAim: a resting group's body is never taken (the sneak on touch)"
	)
	check(
		not Aim.Takes(true, false, "gate"),
		"CampAim: in the gate no camp body is taken, awake or not"
	)
	check(
		not Aim.Takes(true, true, "gate"),
		"CampAim: in the gate a resting camp body is not taken either"
	)
end
```

Old expectation -> new:
- "a body with no camp floor is always taken": unchanged (true).
- "...taken even in the gate": unchanged (true), now with resting true as well.
- "an awake group's body is taken in play" -> "...taken, wherever the player stands" (true, with no root).
- "a resting group's body is never taken": unchanged (false).
- "engaged by another group, a resting body is still not taken": **gone**, because engaged is no longer an argument. The resting case covers it.
- "in the gate no camp body is taken, engaged or not" -> "...awake or not" (false), plus a resting-in-gate case.
- "engaged, an awake body is taken from out of play": **gone**. An awake body is always taken.
- "within chaseMargin of an edge is in play", "past the rounded corner is out of play", "under the sight band", "over the sight band", "with no camp rules loaded an awake body is taken": **gone**, because clause 4 and the `camps` argument are gone (L1b-W4-32).
- New: "after the close an awake body in the boss room is taken" (phase `fight`).

### luau-engineer B: `tools/crowd_harness/mutate.py`

The six `W2_FIX_UI_MUTATIONS` entries (`mutate.py` :2682-2711) are all stale: their texts no longer exist in `CampAim.luau`. Move them to a `…_REPLACED` table (as `L1B_W2_CROWD_REPLACED` does), replaced by these four. The texts are exact, with tabs as `\t`. `CAMP_AIM` stays in `FILES`.

```python
W4_UI_MUTATIONS = {
    # L1b-W4-32 clause 2 dropped (replaces "l1b w2 ui: a resting body is taken" and
    # "l1b w2 ui: engaged takes a resting body")
    "l1b w4 ui: a resting body is taken": (
        CAMP_AIM,
        'return phase ~= "gate" and not resting',
        'return phase ~= "gate"',
    ),
    # L1b-W4-32 clause 1 dropped (replaces "l1b w2 ui: the gate takes camp bodies")
    "l1b w4 ui: the gate takes camp bodies": (
        CAMP_AIM,
        'return phase ~= "gate" and not resting',
        "return not resting",
    ),
    # an awake camp body refused, as the old in-play clause did off the floor (replaces
    # "l1b w2 ui: auto-target corners square" and "l1b w2 ui: auto-target has no sight band")
    "l1b w4 ui: an awake camp body is refused": (
        CAMP_AIM,
        'return phase ~= "gate" and not resting',
        "return false",
    ),
    # replaces "l1b w2 ui: a body with no camp floor is refused"
    "l1b w4 ui: a body with no camp floor is refused": (
        CAMP_AIM,
        "if not onCampFloor then\n\t\treturn true",
        "if not onCampFloor then\n\t\treturn false",
    ),
}
MUTATIONS.update(W4_UI_MUTATIONS)
```

Proven in my scratch against the real file under `luau.exe`: the four mutations fail 1, 1, 2 and 2 of the 7 cases.

### luau-engineer B: `run_harness.py`

`CampAim` stays in `SOURCES` where it is. It now requires nothing, so its position no longer matters.

### Nobody else

There is no server change for the client. `RunState.floors[i].cells` is read as B's `WaveService` sends it (`cells = zone.region.cells`, Types `RunFloor.cells`).

## Found in the contract

1. **Client, a missing point:** `CombatUIController.applyFloors` drops every field but `x y z hx hz` before calling `CrowdRenderer.SetFloors`. As written ("CrowdRenderer: SetFloors also reads cells"), L1b-W4-33 would have done nothing in the game. I fixed it in my own file (above).
2. **"InputController takes none" (no new top-level local):** held, at 149. The `engaged` field and argument are gone too, because a field set but never read would be dead code.
3. **`CampAim.Takes(..., phase)` on a body with no camp floor in `gate`:** the contract's order ("true when not on a camp floor" first) keeps Wave 2's behaviour. A range or arena body is taken in any phase. I kept that order.
