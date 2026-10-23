# L4 W2 fix round: ui-engineer B (report)

Worktree `tycoon-p5`, branch `l4-w2`. Nothing committed. Rulings K1-K5 and suggestions s1-s3 of
`docs/prompts/l4-w2-fix-round.md`. Python numbers are from `py -3.12` (64-bit) unless said.

## Files changed

- `src/combat/client/Controllers/Raiders/RaiderPose.luau` (K1 slide, K4 `Lean` and the anchor transform)
- `src/combat/client/Controllers/Raiders/Figures.luau` (K3 pools, K4 glue, K5 head check, s2 grip, s3 constants)
- `src/combat/client/Controllers/CrowdRenderer.luau` (K3 swap and per-frame build, s3 `SETTLE_EPSILON` handed in)
- `src/combat/client/Controllers/InputController.luau` (s1 the dropped body sphere, three lines)
- `src/combat/client/Controllers/CombatUIController.luau` (comment only: prewarm in any phase)
- `src/client/UI/Theme.luau` (`COMBAT_WEAPON_SHOWN_STAGE = "Stage0"`, s3)
- `tools/testfit/raiderpose.py` (K1 slide and gate, K2 in-arc and sector gate, K4 `lean_parts`, `head_rule_offset`, the sweep frames)
- `tools/assets/out/RaiderModels.json` and `src/shared/Config/RaiderModels.json` (`rig.slideShare`, the fodder's
  strike key, the Chief's arc keys, both kinds' `posedReach` and `notes.inHead`; the shared file was rewritten by
  `py tools/assets/raider_frames.py`, which then says `CHECK: PASS ... up to date; turn proof holds`)
- Cues.luau: unchanged (the slide moves the pieces it rides).
- Renders (gitignored, the shared `assets` junction): `assets/testfit/out/Raiders/RaiderFodder_strip.png`,
  `RaiderChief_strip.png`; the previous two kept in `assets/testfit/out/Raiders/_before_l4w2_fix/`.

## K1: the lunge's drawn reach

- **The arm alone cannot reach the placeholder's front.** I searched every strike key (pitch 0-3, yaw -1 to 1, roll
  -0.8 to 0.8). The best the fodder's club reaches forward at the impact is **2.27** (flat 2.42). The forward lean
  (0.5 at the impact) bends the torso about the neck, and that moves the shoulder back. The step moves only a leg.
- **So the body slides in the strike window.** The ruling allows it.
  - New rig number `slideShare` 0.6. The slide is `max(thrust, 0) x slideShare` along the facing, in
    `RaiderPose.Rig` and `raiderpose.rig` alike.
  - The thrust is forward only from late in the windup's snap through the blow, and it is back to 0 by the
    recover. The coil, which draws back, never slides.
  - Every piece is translated. The trailing foot's target lies `slide` behind, so it stays where it stood as far
    as the leg reaches. The leading foot steps as before.
  - The anchor (the invisible `Head`, the scored head) never slides, because the server never moves it.
  - **The head rule is waived for the slide alone.** `raiderpose.head_rule_offset` judges the drawn head against
    the anchor carried by the slide. The vertical clamp still holds in the window.
- **Fodder strike key** 0.85 → **1.1** (pitch). The club comes up toward level at the blow, where 0.85 hung it
  down.
- **Results:**
  - At the impact the club reaches **3.86** flat, against the floor 3.44 and the ceiling 5.5.
  - The body slides 1.55 studs (0.6 of the placeholder's 2.59).
  - `posedReach.out` goes 2.66 → **3.86**.
  - The in-head check passes at **0.76 hr** (was 0.79; the gate is 0.75). It is the torso's back passing under
    the unslid scored head while the slide decays: inherent to any slide, the same at shares 0.5-0.7.
- **The gate:** for every attack shape in `NO_TELL_SHAPES = ("lunge",)`, the weapon's flat reach at the impact
  must be ≥ `placeholder_front`. That is the placeholder torso's front face at the impact, upright: thrust +
  radius x `TORSO_DEPTH`/2 = **3.44**, the review's measure. `TORSO_DEPTH` is now read from CrowdRenderer.
- **Decision for the lead: the placeholder's real front was 5.35, not 3.44.**
  - At the impact the placeholder is also tipped 0.5 rad forward at its feet, so its head reached **5.35**.
  - `--check` prints that number beside the floor.
  - Holding the model to 5.35 would leave a 0.15 band under the 5.5 ceiling. It needs a slide of about 1.2 x the
    placeholder's own, and it puts the fodder's `posedReach.out` near 5.4.
  - **That turns camp C's sight gate red**: the margin goes from +2.93 to about +0.2, against `sightMargin` 1.5.
    The gate never counted the placeholder's own slide either: a placeholder is radius x 1.151 there.
  - With 3.86, `check_levels.py` passes: **eyes +1.73, cameras +2.84** (to brutal `C.ambushE` fodder).
  - Moving to 5.35 later is `rig.slideShare` plus a regenerated `posedReach`, *if* the sight gate first stops
    counting the strike window, which only happens with a player in reach.

## K2: the Chief's sweep

- **`impact_reach` now:**
  - samples the strike 120 times, not 10;
  - measures an arc **inside its wedge only**, for the ceiling;
  - prints every arc's farthest reach per 15° sector;
  - fails `SWEEP_FLOOR_KINDS = ("chief",)` when any sector is under range − 0.5.
- **17 cannot be drawn across the wedge.** Geometrically, with the shoulder 2.96 off the axis, weapon points at
  most 14.07 from the shoulder and the rig's twist capped at ±37.5° (Theme `ARC_TWIST_SHARE`), the farthest any
  sector can reach is:

  | sector (deg, + = his right) | −75..−60 | −60..−45 | −45..−30 | −30..−15 | −15..0 | 0..15 | 15..30 | 30..45 | 45..120 |
  |---|---|---|---|---|---|---|---|---|---|
  | most it can reach | 12.46 | 13.14 | 13.90 | 14.68 | 15.45 | 16.12 | 16.64 | 16.95 | 17.03 |

  So 16.5 is drawable only from about +15° to his right.
- **New keys**, found by a search, every number in config:
  - arc `coil` [−0.12, 0.86, 1.07], `follow` [−0.19, 1.71, 1.69], `steady: true`; `strike` is unchanged and unused
    by arcs.
  - The hammer is held out to his right in the windup, swept low across his front and rising to his left.
  - The whole 150° wedge is swept: per sector from his left **12.4 12.9 13.0 13.0 12.8 12.7 12.5 12.4 12.6 13.0**.
    Before, the two left sectors were never swept and the rest ran 12.9-16.4.
  - In-arc maximum **13.03**. `steady` cut the hammer's jump at the impact from about 6-8 to about 1.5 studs: the
    arc's lean flips from −0.45 to +0.5 there.
  - `posedReach.out` 17.1 → **14.53**. `up` stays 24.13, so camp C's `tallest` is unchanged.
- **For D1: the range that passes both bounds is 12.53 ≤ range ≤ 12.90. I suggest 12.7** (proved: 12.6, 12.7 and
  12.8 PASS on a patched copy).
  - The angle stays 150.
  - The sweep's `reach` 14 (when the AI starts it) is then above its `range`. Lower it to at most the range.
  - Then re-measure the bands.
  - **Until D1 changes it, `raiderpose.py --check` exits 1 on this one row, by design.** Everything else passes.

## K3: pools filled before a run, never in a remote's handler

- **`Figures.Take` never builds**; it answers nil when the kind's pool is empty.
- **`CrowdRenderer.dressFigure`** then keeps or puts on the placeholder and marks the body `wants`.
  - Each frame `wear` puts the model on through `applyKind`, once `Figures.Ready`, with the cues and the bar again,
    as X re-dresses.
  - Until then it counts the body with `Figures.Wait`.
- **`Figures.Build()`** runs at the top of every step, before the "no bodies" return, so it also runs in the lobby
  camp. Each frame it builds up to `COMBAT_RAIDER_PREWARM_PER_FRAME` (4): first for waiting bodies beyond their
  kind's spares, then toward the goals, one per kind per round. Its time goes to DrawClock.
- **`Figures.Prewarm(counts, cap)`** no longer yields. It sets the goals from the last plan.
  - Over the cap, each kind gets floor(count x cap / total).
  - The largest remainders take the rest, then the larger count, then the name. **Never alphabetical.**
  - Already-built figures are never undone.
- `CombatUIController` already hands over `RunState.prewarm` in any phase.
- **The lobby fill needs one server change** (below): the lobby's RunState carries no `prewarm` today. Without it
  the first run still never builds 95 models in one frame. Its bodies show as placeholders for about a second
  while 4 a frame are built, then swap.

## K4, K5, suggestions

- **K4:**
  - `RaiderPose.Lean(yaw, x, z) -> (along, across)` replaces Figures' `leanParts`.
  - `RigOut.anchor` (12 numbers: the scored head, unturned, never slid) is laid by the same loop as the pieces
    (`frameOf`).
  - `RigOut.slide` is new.
  - Python has `raiderpose.lean_parts` and `Rigged.anchor_frame()` / `Rigged.slide`.
- **K5:** `Figures.lookOf` refuses a head point more than 0.01 from (0, height − headRadius, 0) on any axis. That
  kind becomes a placeholder, with one warning. All seven shipped kinds are exact.
- **s1:** in the assist, auto-fire and melee tests the body sphere sits at `math.max(height * HALF - drop, radius)`.
  Standing that is unchanged; seated it is the server's foot sphere (fodder 0-2.6).
- **s2:** the Warhammer's offsets are taken from `base.CFrame * CFrame.new(grip * scale)`, where `grip` is
  `WeaponLook.Point(def, "grip")` of the WeaponModels.json entry whose `model` it is. With no usable entry it is
  drawn without the hammer, with one warning. Today's grip is [0, 0, 0], so the look is unchanged.
- **s3:**
  - `SETTLE` is CrowdRenderer's `SETTLE_EPSILON`, handed in by `Figures.Configure`.
  - The held stage is `Theme.COMBAT_WEAPON_SHOWN_STAGE`. HeldWeapons should read it too (diff below).

## Gates (mine)

| Gate | Result |
|---|---|
| `stylua --check`, `selene` on my 7 Luau files | clean, 0 / 0 / 0 |
| luau-lsp (scratch sourcemaps), `src/combat src/shared` on the combat sourcemap | exit 0, no diagnostics |
| luau-lsp, `src/client src/server src/shared` on the hub sourcemap | exit 0, no diagnostics |
| `py tools/check_compile.py` | PASS, 182 files; CrowdRenderer **165** top-level locals (was 164; budget 180) |
| `py tools/check_raider_mirror.py --luau <luau> --mutants` | CHECK: PASS, 16,806 cases, worst 7.11e-15; MUTANTS: PASS 14 of 14 |
| `py tools/assets/raider_frames.py --check --require-harvest` | PASS |
| `py -3.12 tools/testfit/raiderpose.py --check` | every rule PASS except the Chief's arc sector floor (17 vs 12.4-13.0), waiting on D1's range; fodder lunge 3.86 ≥ 3.44 and ≤ 5.5 |
| `py -3.12 tools/check_levels.py` | CHECK: PASS (camp C eyes +1.73, cameras +2.84) |
| Harness | **HARNESS: FAIL, 18 of 4,472**, all in LevelService / LevelDress pins (`buildDress`, `dressAccept`, `piecesThenDress`...: luau-engineer A's K7 rewrite in progress, for D2 to re-aim). Its InputController and CombatUIController checks pass. |

- Every file is LF.

## For the other owners

### D1

- Chief sweep (`ProvingGrounds.json` crowd.kinds.chief, attack 4):
  - `range` 17 → a value in **[12.53, 12.90]**, 12.7 suggested; `arcDegrees` stays 150;
  - `reach` 14 → at most the new range;
  - then the bands.
- `raiderpose.py --check` goes green with it. Change the range, never the keys: any key change moves both ends of
  the band.

### D2: `tools/check_raider_mirror.py`

**New Rig outputs.** `Rigged.slide` (Python) is `RigOut.slide`. `Rigged.anchor_frame()` is `RigOut.anchor`, 12
numbers.
- `RIG_FIELDS += ("slide",) + tuple(f"anchor[{i}]" for i in range(1, 13))`
- `rig_values` appends `r.slide` and `cframe_numbers(r.anchor_frame())`
- DRIVER's rig branch appends `o.slide` and `o.anchor[1..12]`

The Rig cases already exercise the slide: `sweep_poses`' lunge poses carry the thrust. The slide is compared
through every piece today.

**A Lean case.** `RaiderPose.Lean(yaw, x, z)` against `rp.lean_parts(yaw, x, z)`. For example, YAWS x lean vectors
(0, 0), (0.3, −0.2), (−0.5, 0.1), (0.07, 0.4). DRIVER branch:

```
elseif c.f == "lean" then
	local a, b = RaiderPose.Lean(c.yaw, c.x, c.z)
	emit(i, { a, b })
```

**MUTANTS to add.** The first four I ran against the mirror as it stands, and each turns it red: 144, 48, 144 and 32
differences.
- `("Rig: the strike window's slide gone", "local slide = math.max(pose.thrust, 0) * rig.slideShare", "local slide = 0")`
- `("Rig: the trailing foot slides with the body", 'if lead == "legR" then step else -slide,', 'if lead == "legR" then step else 0,')`
- `("Rig: the slide runs backward", "local sx, sz = -sinYaw * slide, -cosYaw * slide", "local sx, sz = sinYaw * slide, cosYaw * slide")`
- `("Rig: the coil slides back too", "local slide = math.max(pose.thrust, 0) * rig.slideShare", "local slide = pose.thrust * rig.slideShare")`
- after the Lean case: `("Lean: along and across swapped", "return leanX * -s + leanZ * -c, leanX * c + leanZ * -s", "return leanX * c + leanZ * -s, leanX * -s + leanZ * -c")`
- after the anchor fields: `("Rig: the anchor rides the drop", "write(o.anchor, 0, o.anchorY, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)", "write(o.anchor, 0, o.anchorY - drop, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)")`

All 14 old mutant texts are unchanged.

**raiderpose.py's names.**
- `RENDERER_NAMES` gains `"TORSO_DEPTH"`, so it is in `consts_table`; harmless.
- `RIG_DEFAULTS` gains `slideShare`. `raider_frames.py` follows it (its `rig.<key>` checks), and both configs carry
  it.

### D2: pins and mutate (K7)

The InputController drop lines, whole, with their tabs.

- **CrowdRay's argument**, line 653, 4 tabs (unchanged): `\t\t\t\tdrop`
- **The refused spheres**, lines 664-665, 7 tabs:

  ```
  \t\t\t\t\t\t\tthen math.max(height * HALF - drop, radius)
  \t\t\t\t\t\t\telse height - headRadius - drop
  ```

- **The assist cone** (taken bodies), lines 681-682, 3 tabs, after `\t\t\tif found then\n\t\t\t\treturn\n\t\t\tend\n`:

  ```
  \t\t\tlocal body = position + Vector3.new(0, math.max(height * HALF - drop, radius), 0)
  \t\t\tlocal head = position + Vector3.new(0, height - headRadius - drop, 0)
  ```

- **The melee reach**, lines 761-762, the same two lines, after
  `\t\t\tif taken and found then\n\t\t\t\treturn\n\t\t\tend\n`.
- The two `local body` / `local head` pairs occur twice. Aim mutants with the preceding `if` block, or count them
  (2 each).
- **Suggested mutants:**
  - `- drop, radius)` → `, radius)` (sphere not lowered);
  - `- headRadius - drop, 0)` → `- headRadius, 0)` (head standing);
  - `math.max(height * HALF - drop, radius)` → `height * HALF - drop` (sinks under the ground).
- **CrowdRenderer ForEach's drop**, line 3063, 4 tabs (unchanged):
  `\t\t\t\tHitShapes.SeatDrop(entity.height, entity.seat, poseConsts.restDrop)`. Mutant: → `\t\t\t\t0`.
- **Optional pins in Figures.**
  - K5's test: `\t\tmath.abs(head[1]) > HEAD_EPSILON` / `\t\tor math.abs(head[2] - scored) > HEAD_EPSILON`, with
    `\tlocal scored = def.height - def.headRadius`.
  - K4's anchor: `\tframes[count] = root * frameOf(rigOut.anchor)`.
  - The split: `\tpose.lean, pose.leanSide = RaiderPose.Lean(yaw, lean.X, lean.Z)`.
- **mutate.py:** please run `files:InputController.luau,CombatUIController.luau`. A grep of `mutate.py` shows no entry
  on the lines I changed.

### Generator owner (route via the lead): `tools/assets/raider_kit.py`

Without these, the next generator run brings the old keys back. `slideShare` comes from `raiderpose.RIG_DEFAULTS`
by itself.

- line 188 (fodder):
  - old `"lunge": {"coil": [1.85, 0.25, 0.25], "strike": [0.85, -0.15, -0.1], "follow": [0.1, -0.1, 0.0]},`
  - new `"lunge": {"coil": [1.85, 0.25, 0.25], "strike": [1.1, -0.15, -0.1], "follow": [0.1, -0.1, 0.0]},`
- line 565 (Chief):
  - old `"arc": {"coil": [0.1, -0.9, 1.45], "strike": [0.4, -0.3, 1.45], "follow": [0.3, 1.1, 1.35]},`
  - new `"arc": {"coil": [-0.12, 0.86, 1.07], "strike": [0.4, -0.3, 1.45], "follow": [-0.19, 1.71, 1.69], "steady": True},`

### Owner of `tools/testfit/raiderview.py` (route via the lead; I did not edit it)

The fodder's blow frame now reads "head 2.24 hr off the scored head (RULE BROKEN)". The lunge's slide is waived, but
raiderview measures without the waiver. Line 624:
- old `        off = rp.v_len(rp.v_sub(drawn, r.anchor)) / hr`
- new `        off = rp.head_rule_offset(r, fr.pose, head_mesh_centre, hr)`

Then re-render `--model RaiderFodder`. The cyan circle stays on the scored head, as it should.

### HeldWeapons owner (s3, one constant)

`src/combat/client/Controllers/HeldWeapons.luau:50`:
- old `local SHOWN_STAGE = "Stage0"`
- new `local SHOWN_STAGE = Theme.COMBAT_WEAPON_SHOWN_STAGE`

It already requires Theme (line 42).

### WaveService owner (K3's lobby fill; route via the lead)

The lobby RunState must carry the plan's kinds. A sketch:
1. Add `lobbyPrewarm = nil :: { [string]: number }?` to `boot`.
2. Add `lobbyPrewarm()`:
   - for each id of `builtLevels()` x each name in `map.difficulties`, run `resolveLevel` and then, in `pcall`,
     `StageFlow.Plan(level, layout, difficulty, combatConfig.levels, LevelGeometry.Bounds(layout,
     combatConfig.levels.floorThickness), difficultyRanks(map), Tuning.Get().crowd.kinds)`;
   - keep the per-kind maximum of `plan.kinds`;
   - cache it in `boot`.
3. In `pushRunFields`:
   `prewarm = if run.prewarm ~= nil then run.prewarm elseif phase == "lobby" then lobbyPrewarm() else nil,`

The client splits it under `crowd.maxAlive`, so an envelope over levels is safe.

### Lead: one finding for later

The plated elite's axe sweep draws **0.0 0.0 3.9 4.4 4.4 4.6 4.8 5.0** per 15° against its 7.5-stud, 120° wedge.
Its left 30° is never swept, and nowhere does it reach 7. It is the same family as K2. It is printed by `--check`
and not gated, because the ruling names the Chief only (`SWEEP_FLOOR_KINDS`).

## Assumptions

- K1's floor is the upright torso face (3.44, the review's figure), not the tipped head (5.35); reasons above.
- The strike window is "the thrust is forward" (snap through the blow). Sliding only from the impact would jump the
  body 1.5 studs in one frame.
- The in-head rule stays judged against the real, unslid scored head.

## Remotes and state consumed

- CrowdSpawn, CrowdSnapshot and CrowdRemove, unchanged.
- RunState `prewarm` (any phase) and `maxAlive`.
- Config `RaiderModels.json` (`rig.slideShare`).
- `WeaponModels.json` (the Warhammer's grip).
- ProvingGrounds crowd kinds.

## What to check in Studio

1. **N** to the Main Camp: a fodder's lunge slides it and its club forward together, about 1.5 studs, then back. The
   back foot stays planted. The club meets a player standing about 4 studs away.
2. **N** to the clearing (never B): the Chief winds the hammer out to his right, sweeps it low across his front
   and finishes high on his left. The hammer no longer jumps at the impact. The ground wedge is still 17 until D1
   changes it.
3. First Depart of a session:
   - with the server change: no hitch at the trailhead, because the pools fill in the lobby;
   - without it: bodies appear as placeholders for about a second and turn into models a few a frame, with no
     hitch;
   - **X** still swaps everything.
4. Seated raiders: auto-fire on a phone triggers on the seated body, not above it.
5. Emulator 667 x 375 and 375 x 667: nothing on screen changed; the frame time while models fill shows in "Draw N
   ms".
