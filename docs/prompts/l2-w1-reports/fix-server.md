# L2 W1 fix round: server agent report (2026-10-17)

Branch `l2-secrets` in `C:\Users\benja\Desktop\tycoon-p5`. Nothing is committed.

## Files changed

- `src/shared/Unlocks.luau`
  - Adds the caps `MAX_ID_LENGTH` and `MAX_FAMILY_LENGTH`.
  - Adds `Sellable`, `AbilitiesOf` and `Apply`.
  - `Find` now uses the "first sound entry" rule.
  - `DefProblem` now refuses an empty `text` and an id longer than the cap.
- `src/shared/WallClip.luau`: adds `GroundFloor`.
- `src/shared/Types.luau`: adds `RangeMovementConfig.coyoteSeconds: number`, for the client agent's c3.
- `src/combat/server/Services/SecretFlow.luau`
  - `Site` gains `sx` and `sz`.
  - `Triggered` measures the flat distance to the chest's footprint.
  - Adds a pure `Open`.
- `src/combat/server/Services/UnlockService.luau`
  - `Init` uses `Unlocks.Sellable`.
  - `OnBuyAbility` uses `Unlocks.Apply`.
  - `OpenSecret` uses `SecretFlow.Open`.
  - Its local map helpers are gone.
- `src/combat/server/Services/CombatRemotes.luau`: both caps now read `Unlocks`.
- `src/combat/server/Services/StageFlow.luau`: the secret family check reads `Unlocks.MAX_FAMILY_LENGTH`. Its own copy of the constant is gone.
- `src/combat/server/Services/WeaponService.luau`: `GroundPoint`'s step 4 is now one `WallClip.GroundFloor` call.
- `src/combat/server/Services/BarrierGroups.luau`: `ArenaPlayers` no longer collides with itself (d1).
- `tools/crowd_harness/run_harness.py`: `source_reading` gains `groundFloor`. For each side it counts the `WallClip.GroundFloor(` calls, and the `Rise(`, `TooHigh(` and `CasterFloor(` calls made outside it.
- `tools/crowd_harness/tests_l2.luau`
  - New groups: `openTests` and `groundFloorTests`.
  - Updated groups: unlock, secret and real tests.
- `tools/crowd_harness/mutate.py`
  - Two stale entries re-pointed: "Find returns a malformed entry" and "a family of any length".
  - New `L2_FIX_MUTATIONS` (30 entries).
  - `WeaponService` is now in `FILES`.
- `tools/check_stage_mirror.py`: `Unlocks` is added to `MODULES`, because StageFlow now requires it.

## Contracts (for the client and data agents)

```lua
-- src/shared/Unlocks.luau
Unlocks.MAX_ID_LENGTH = 32      -- ability id, bytes (#); CombatRemotes' RequestBuyAbility cap
Unlocks.MAX_FAMILY_LENGTH = 24  -- weapon family id, bytes (#); remotes + StageFlow secrets
Unlocks.Sellable(config: Types.ExpeditionsConfig?): ({ Types.UnlockAbilityDef }, { string })
Unlocks.Find(config: Types.ExpeditionsConfig?, id: string): Types.UnlockAbilityDef?
Unlocks.AbilitiesOf(combat: Types.CombatProfile): { [string]: boolean }
Unlocks.Apply(state: Types.PlayerState?, def: Types.UnlockAbilityDef?, gateOpen: boolean): string?

-- src/shared/WallClip.luau
WallClip.GroundFloor(
	probedCaster: number?, feetY: number, probedTarget: number?,
	movement: { jumpHeight: number, doubleJumpHeight: number },
	airJump: unknown  -- the raw Ability_doubleJump attribute; only `true` owns
): (number?, number)  -- (floorY or nil when refused, casterFloor)

-- src/combat/server/Services/SecretFlow.luau
Site = { id, needs, x, z, sx, sz, floorY, name, reward? }
SecretFlow.Triggered(site, root: Vector3, rules): boolean
SecretFlow.Open(combat: Types.CombatProfile, levelId: string, site: Site, hasKey: boolean,
	material: string): Opening
```

**`Triggered` (s1), for the Python mirror in `check_levels`:**
- Compute `dx = max(|root.X − x| − sx/2, 0)` and `dz = max(|root.Z − z| − sz/2, 0)`.
- The flat test is `dx² + dz² ≤ secretReach²`. It is closed, and gives 0 anywhere inside the footprint.
- The band is unchanged: `−secretBelow ≤ root.Y − floorY ≤ secretAbove`, closed.
- Rules that are not finite open nothing.
- `Sites` skips a secret whose `sx` or `sz` is missing, not finite, or negative.

**One rule for a repeated id (s4).** The rule is the first entry of an id that `DefProblem` accepts:
- A malformed entry is skipped. It no longer hides a sound entry after it.
- `Sellable` keeps exactly the entries `Find` returns, in list order, each id once (a list that holds one table twice still sells it once).
- `Sellable` gives one problem line per entry it leaves out.
- `UnlockService.Init` warns those lines. The panel uses `Sellable` too; the client agent already does.

**`DefProblem` (s2, c5)** now also refuses:
- an empty `text`;
- an id longer than `MAX_ID_LENGTH`, measured in bytes. `check_levels.check_abilities` already requires a non-empty text and its `ABILITY_ID_MAX` 32.

**`Apply` (s3).**
- It returns `BuyVerdict`'s reason and leaves the profile untouched.
- Or it returns nil, and has then taken `price.valor` from `combat.valor` and set `abilities[id] = true` (creating the map if it is missing).
- `UnlockService.OnBuyAbility` now only sets the attribute, answers and sends the snapshot.

**`Open` (s3).** It writes nothing unless the verdict is "pay". On "pay" it credits:
- Valor;
- the material, unless `material` is "" (then 0 is reported);
- the family;
- `secrets[levelId][id]`.

It creates each map a profile lacks and keeps the maps a profile has. `UnlockService.OpenSecret` reads the key from the profile with `Unlocks.HasKey` and calls it.

## d1: players do not collide with players (BarrierGroups)

`Ensure` now sets `CollisionGroupSetCollidable(ArenaPlayers, ArenaPlayers, false)`. Before, it copied Default/Default, which is true. Every other pair is unchanged:
- ArenaPlayers against everything else still copies Default's answer;
- the barrier still collides only with ArenaPlayers.
- Rays and the camera run in Default, which still collides with ArenaPlayers, so shots, the crosshair and the boom still see other players.

**Who is in `ArenaPlayers`.** Every admitted member's character, whether in the lobby, waiting or fighting. `ArenaService.watchCharacter` puts them there at admit and on every `CharacterAdded`.

**Who is not:**
- **A player between join and admit** (profile loading, the admission check, a refused player before the kick). That body is in Default, which still collides with ArenaPlayers. It stands at the lobby SpawnLocation for those seconds, and the lobby has no ledge, so nothing can be reached from it.
- **The range (Studio bench).** Range players are not admitted members, so they stay in Default and still collide with each other, as before.
- **Debug bots.** Their rigs are never put in the group, so they stay in Default and still collide with players, as before.
- **When the engine refuses the groups** (`Ensure` false, warned once). Nobody joins the group and players collide as before. That place also builds no invisible wall.

**Rules that relied on player-player collision:**
- **L1c's close.**
  - `WaveService.moveFighters` sends every road fighter to the same entry point (`ArenaService.MoveMember(member, feet)`, one point for all of them). Before, two bodies put on one point shoved each other apart, which could pop one onto the other's head or against the fence. Now they overlap harmlessly and walk apart.
  - check_levels' `NUDGE_CLEAR` rule says "a road player never lands on a nudged one". That half no longer guards a physical clash. It stays true and harmless. The other half (no nudge lands in cover) is still needed.
- **The same applies elsewhere:**
  - `standUpOnRoad` (every downed member goes to one safe point);
  - the rescue to a spawn;
  - the lobby SpawnLocation when several players spawn or respawn together.

  In each case bodies now overlap instead of pushing.
- **Body-blocking in camps and gates is gone for co-op.** One player can no longer plug a gate gap for a partner. No rule or gate in the repo depends on body-blocking: crowd separation is CrowdService's, between enemies only.
- **The stacking route to the lookout** (data-tools Minor 1) is closed for admitted members. The single-player margin (fence top 12, 1 stud) and the wall hop are unchanged and stay as PLAYTEST items.

d1 is checked by reading only. BarrierGroups does not load in the harness, and Studio is the only test of the physics.

## Gates (run on this checkout, then on a snapshot for the mutations)

- **Harness:** `HARNESS: PASS (2,625 checks, C:\Users\benja\Desktop\tycoon-p5\tools\crowd_harness)`, run with
  `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`. It was 2,586 at the review. It is green again on the live
  tree, with the client's and data agent's edits (`secretReach` 2.5).
- **mutate.py, filtered to my files.** Every entry whose file is Unlocks, WallClip, SecretFlow, StageFlow or WeaponService,
  plus every "l2 fix" entry.
  - Run on a snapshot of the working tree's tracked files in the scratchpad, so its `mutant/` root never touched
    this checkout.
  - Result: `MUTATIONS: 301 run, 0 not caught`. The baseline was `HARNESS: PASS (2,625 checks)`.
  - The 30 new "l2 fix" entries are all caught. My files did not change after the snapshot.
- **Stale-text count over all entries:** 870 entries, 0 stale.
- **check_stage_mirror** (`--luau` the main checkout's): `CHECK: PASS`.
- **check_compile:** `CHECK: PASS -- 165 files compile with Studio settings (-O1 -g2)`.
- **stylua --check** and **selene** on my nine Luau files: clean (0 errors, 0 warnings).
- **luau-lsp analyze**
  - Run with `--definitions=tools/types/globalTypes.d.luau`.
  - The combat tree (`--sourcemap=sourcemap.combat.json`, regenerated, `src/combat src/shared`) has no errors.
  - So does the hub (`sourcemap.json`, `src/server src/shared src/client`).
  - `sourcemap.combat.json` shows as modified because I regenerated it. It now includes the client's new `ActionRows.luau`.

## Required changes outside my files

- **Data agent, `tools/sim_range.py` (about line 5275).** `SECRET_FAMILY_MAX`'s comment names `StageFlow.MAX_FAMILY_LENGTH`, which no longer exists. It should name `Unlocks.MAX_FAMILY_LENGTH`. Its length test should count bytes (`len(family.encode("utf-8"))`), as StageFlow's `#family` does (the ruling on d4).
- **Data agent, `tools/check_levels.py`.** Its copy of `Triggered` must use the footprint formula above. Rule (a) must run for every secret. `ABILITY_ID_MAX` should cite `Unlocks.MAX_ID_LENGTH`.
- **Client agent: nothing more is needed.** It codes against `Unlocks.Sellable` and `WallClip.GroundFloor`. The `RangeMovementConfig.coyoteSeconds` it reads is now in Types. luau-lsp is clean on its files as of my last run.
- **The harness reads InputController.** `groundFloorTests` requires the client's `groundPoint` to call `WallClip.GroundFloor(` exactly once and none of the parts. Its text `local floorY, casterFloor = WallClip.GroundFloor(` is the target of the mutation "l2 fix c4: the client's ground point keeps its own copy". If the client rewords that line, that entry goes stale.

## What to check in Studio

- **Two players, one without Double Jump.** Standing on a partner's head at the ledge face no longer lifts anyone. Bodies pass through each other in the lobby, on the road and in camps.
- **Two road players brought in by the Chief's Clearing close.** They land on the entry together without shoving each other.
- **Buying Double Jump.** Valor drops by 10 once. A second press answers "Already yours".
- **The lookout.** It still opens on the ledge and on the chest, and never from Road5.
- **A leap aimed at the ledge from Road5 without Double Jump.** It is refused on both sides, with no client-only move.
