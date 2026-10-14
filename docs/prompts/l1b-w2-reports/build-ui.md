# L1b Wave 2 — ui-engineer build report

Status: **code done; Studio checks not done** (I cannot run Studio). Built against A's landed
`Types.luau`, `HitShapes.FlatToRect` and `SwingGate.luau`.

## Done (every point of INTERFACES "Wave 2" -> "Client")

- **`CrowdRenderer.luau`** (L1b-W2-11), with the new pure module **`Controllers/SpawnSeed.luau`**:
  - A spawn info with `at` seeds the body's first sample. The sample is `at`, `yaw` and the state,
    with a full bar (the plate's when the kind has one), stamped at the client's render time. The
    body is drawn at once and held there.
  - An info without `at` (the range) keeps the old rule.
  - **The first real snapshot takes over as a second sighting.** The seed's stamp is pulled to
    `min(seed, stamp - interval)`, so the move blends and a packet older than the seed is never
    refused.
  - Every effect timed off a sighting treats that snapshot as the first sighting:
    - the tell clock (`previous`);
    - the plate-break burst: none for a plate that broke before this client saw the body;
    - the enrage beat: none.
  - A refreshed info for a body still drawn from its seed only moves it in place: no rise or burst
    again.
  - A dormant body simply gets no snapshot. "Extrapolate 0.12 s, then hold" stands, and absence
    never removes a body.
  - `rest` draws seated; a tent group's `idle` draws standing (the existing first-sample rule).
  - New entity field `seeded`; no new top-level state. Top-level locals 152 -> 153 (the `SpawnSeed`
    require).
- **`InputController.luau`**, with the new executor module **`Controllers/AirSwing.luau`**:
  - `campInPlay` measures with `HitShapes.FlatToRect` (L1b-W2-24).
  - In phase `gate`, auto-target takes no body with a camp floor, whether engaged or not
    (L1b-W2-25). Range bodies have no camp floor, so the range is unchanged.
  - **Air-swing gate (L1b-W2-14).** For a melee variant, `rangeAttack` asks `AirSwing.Judge`
    **before anything moves**: the seq, the pacing stamp, the combo prediction, the early effect.
    - `Judge` casts one ray per swing attempt, from origin + `GROUND_PROBE_LIFT` down
      `GROUND_PROBE_DEPTH`.
    - The probe respects CanCollide and skips every character, as `WeaponService.floorUnder` does.
    - The answer is `SwingGate.IsAir(height, HipHeight + root.Y/2)`.
    - A refused swing returns with nothing sent or drawn and clears a queued tap. Nothing is queued
      for the landing.
    - `AirSwing.Took(airborne)` runs after the send.
    - `used` clears on a grounded swing and on the local Humanoid's `StateChanged -> Landed`. A new
      character starts clear.
  - The touch auto-swing runs through the same path. It waits through the gate and swings again at
    its rate once the player is grounded. No attack button. Abilities and shots are not gated.
  - Top-level locals 147 -> 148 (the `AirSwing` require). `AirSwing.Destroy()` is called from
    `InputController.Destroy`.
- **`FeedbackController.luau`** (L1b-W2-19):
  - `paintBurst`: tone `plate` with `crit` draws in `COMBAT_RANGE_CRIT_COLOR`. The size was
    already the crit size, because the text-size branch reads `crit`.
  - The plate number and the flesh number now take their crit from their own hits (`plateCrit`,
    `fleshCrit`, both function locals). A crit on one body no longer colours the other number.
  - Top-level locals still 159.
- **`CombatHud.luau`** (L1b-W2-23):
  - In Studio only, a dim `Server 1.4 ms` line shows in every live phase. It reads the Workspace
    attribute named by `Catalog.GetCombatConfig().debug.perfAttribute`.
  - It repaints on `GetAttributeChangedSignal` and on every RunState.
  - The value is rounded to 0.1; the whole milliseconds go through `Format.Cash`. At 100 ms or
    more the decimal is dropped.
  - It is hidden while the attribute is missing or not a finite number >= 0, and never set on a
    live server.
  - `Active = false`, its own UIScale, destroyed with the HUD. The locals in `new()` are grouped
    in a `perf` table.
- **`Theme.luau`** (add only): `COMBAT_PERF_TEXT_SIZE` 12, `COMBAT_PERF_TRANSPARENCY` 0.35,
  `COMBAT_PERF_WIDTH` 140, `COMBAT_PERF_HEIGHT` 16.

## Layout read (no Studio)

The perf line sits bottom-left, over the run's buttons, with one slot of 24 design px above it for
each key hint a keyboard can show (the Alt hint, then the Studio key hint).

- **667 x 375 landscape** (GUI 667 x 339 under the inset; scale = MIN_SCALE 0.917):
  - The header, wallet and notice block ends at y ~ 119. The boss bar fits the top strip (strip
    168 >= 128).
  - The perf line spans y ~ 262-277, or y ~ 218-233 when the emulator reports a keyboard. It runs
    x 7-136; the health bar and ability tiles at the bottom centre run x 241-425.
  - It covers none of the boss bar, the objective line or "Camps 1 / 3". It sits in the left-thumb
    area, but as a label it never takes a touch.
- **1920 x 1080** (scale 1.565): the perf line's bottom is ~181 px above the screen's bottom, far
  from the header and the boss bar.

## Gates run (on my files)

- `stylua --check` on the seven files: clean. `selene`: 0 errors, 0 warnings.
- `rojo sourcemap` for both projects, written to my scratch.
- `luau-lsp analyze`:
  - `src/combat` on the combat sourcemap: **no diagnostics in `src/combat/client`**.
  - `src/shared src/server src/client` on the hub sourcemap: none in `src/client`.
  - The remaining errors are in other owners' files, which were being edited at the time:
    `HitShapes.luau:289-290` (`firstIn` argument count), `CrowdService.luau:2062-2063`,
    `StageFlow.luau:572`.
- `py tools/check_compile.py`: PASS, 155 files. FeedbackController 159, CrowdRenderer 153,
  InputController 148.
- `rojo build` of `combat.project.json` and `default.project.json`: both build (output to my
  scratch). I did not run the proving build, because `proving_project.py` writes a shared file at
  the repo root; QA should run it.
- Gate 12, `git diff --stat main -- src/server src/client`: lists only `src/client/UI/Theme.luau`.

## Not done (needs Studio)

- The three screenshots, on a PC and at 667 x 375: a whole camp drawn on arrival from spawn infos
  alone, the perf line, and a crit on a plate.
- The phone frame time with every resident drawn, on the road between A and B and inside B. No
  culling was added.

## For the other owner

- **luau-engineer A (`CrowdService`):**
  - The client reads `info.at` as the body's **feet in world coordinates**, in the same frame as
    the snapshot decode (`WIRE_ORIGIN` zero). It reads `info.yaw` in radians, like the record's
    yaw, and `info.state` as the wire's state string.
  - The perf attribute must be a number **in milliseconds**.
  - A tent group at rest must arrive as `idle`: the client seats only `rest`.
- **luau-engineer B (harness), optional, for the lead to decide:**
  - `SpawnSeed` is pure and can get a case if `run_harness.py` adds
    `"SpawnSeed": "src/combat/client/Controllers/SpawnSeed.luau"` to `SOURCES`.
  - Caveat: the module checks `typeof(at) == "Vector3"`. The harness's Vector3 shim is a table, so
    the wrapper would also need a `typeof` stub that answers `"Vector3"` for the shim.
  - Cases, for `tests_l1b_w2.luau`:
    ```luau
    do
    	local Seed = load("SpawnSeed")
    	local at = Vector3.new(4, 8, -2)
    	local p, y, s = Seed.Read({ id = 1, kind = "fodder", maxHp = 10, at = at, yaw = 1.5, state = "rest" })
    	check(p == at and y == 1.5 and s == "rest", "SpawnSeed: a resting body seeds where it rests, seated")
    	local _, _, s2 = Seed.Read({ at = at, state = "windup" })
    	check(s2 == "idle", "SpawnSeed: an attack state seeds standing")
    	check(Seed.Read({ at = at, state = "dead" }) == nil, "SpawnSeed: a dead body is not seeded")
    	check(Seed.Read({ id = 1, kind = "fodder" }) == nil, "SpawnSeed: no at, no seed (the range)")
    	local _, y2 = Seed.Read({ at = at, yaw = math.huge })
    	check(y2 == 0, "SpawnSeed: a bad yaw faces 0")
    end
    ```
  - Mutations, on `src/combat/client/Controllers/SpawnSeed.luau`:
    - "seed of a dead body": replace `if state == "dead" then` with `if false then`.
    - "seed keeps an attack": replace
      `\telseif state == "rise" then\n\t\tpose = "rise"\n\tend` with
      `\telseif state == "rise" then\n\t\tpose = "rise"\n\telseif typeof(state) == "string" then\n\t\tpose = state :: any\n\tend`.

## Decisions the contract did not take

1. **A seed is a pose, never an attack.**
   - Only `idle`, `move`, `rest` and `rise` seed as they are. `windup`, `attack`, `recover`,
     `stagger` and `airborne` seed as `idle`, and a `dead` body is not seeded.
   - The reason: an info is a still picture of unknown age, so a tell started from it would run on
     a guessed clock. The first snapshot names the real state.
2. **The first snapshot of a seeded body blends from the seed**, but every timed effect treats it
   as the first sighting.
3. **The landing is detected by `StateChanged -> Landed` only**, not by `FloorMaterial`:
   - FloorMaterial can lag take-off by a frame, and at jump speed the 0.75-stud margin is crossed
     within that frame.
   - A stale non-Air reading would clear `used` just after the air swing and let a second swing
     through for the server to refuse.
4. **The probe's RaycastParams are built per swing attempt** (per swing, not per frame), so they
   always see the characters present now.
5. **A dropped air swing also clears a queued tap**, so a tap made in the air never fires on
   landing.
6. **Each number takes its crit from its own hits** (plate or flesh). The merge path for lasting
   hits keeps the strike's crit; it tones the number `plate` only when all of the damage came off
   plates.
7. **Perf text** is the whole milliseconds through `Format.Cash` plus one tenths digit.
   `Format.Rate` would floor 2.3 x 100 to 229 and show "2.29".
