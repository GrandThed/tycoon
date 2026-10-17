# L2 Wave 1 contract — the bought double jump and the lookout (draft for the lead, 2026-10-17)

Branch `l2-secrets` in `C:\Users\benja\Desktop\tycoon-p5`. Ben's decisions are in `docs/MISSIONS_DESIGN.md` §22 (they
override the study `docs/prompts/l2-study-report.md` wherever the two differ). W1 delivers this: the first run has one
jump; a Normal clear pays 10 Valor; Double Jump is bought in the lobby; it reaches the lookout, whose chest pays and
records the Flamethrower. Rulings are numbered **L2-n**. Every number is a starting value that its owner measures, and
it may move within the rule it serves.

## What today's code gives us (checked 2026-10-17)

- **The profile is v6** (`ProfileSchema.luau:14`, template 20–46). Migrations are add-only, and Reconcile runs
  **before** them, so a step must patch a table that already exists (88–92). The runner is `DataService.luau:90-109`.
  A profile ahead of the code warns and plays untouched.
- **The whole `PlayerState` reaches the client** in every Snapshot (`Main.server.luau:80-108`). WaveService refreshes
  it through `run.walletDirty` → `ArenaService.SendSnapshot`. ProfileStore saves the mutated table by itself, and
  "dirty" here only means "send the wallet".
- **Double jump is client-only and always on** (`MovementController.onJumpRequest` 428–457). The server never counts
  air jumps.
- **The ground-aim rule** is `WallClip.TooHigh(casterFloor, floorY, WallClip.Rise(movement))`, and `Rise` is jump +
  double = 30. It is used in `WeaponService.GroundPoint:2560` and `InputController.groundPoint:1868`, and tested in
  `tests_l1c.luau:145-147, 245`. A refused ground point refuses the whole cast (`AbilityService.luau:954-958`).
- **Leap Smash's arc** is `apex = max(from.Y, to.Y) + height` on a LinearVelocity mover that collides
  (`MovementController.Leap` 903–929, `stepMotion` 324–355). A dash cannot interrupt a leap (`dashOrSlam` 394).
- **Every mission is played with Broadsword + Longbow** (`ProvingGrounds.json:200`). No family that has Leap Smash can
  enter a level in W1. W2's picker changes that, so W1 already closes the Leap route.
- **The three secret sites** are at `ForestRoad.json:314-348`. The lookout chest is at (−283, 36, −59) on
  `LookoutLedge` (x −295..−271, z −66..−52, top 34), 26 above `Road5` (top 8). `secret.needs` is read by nothing.
- **Studio levers** go through `DebugService.applyLever` (remote) and `pollAttributes` (Workspace). `grantValor`,
  `GrantValor` and the DebugPanel's "+10 Valor" already exist. Studio's debug keys are `CombatUIController.DEBUG_KEYS`
  (N, B, G).
- **Free keys** in the combat client: H, J, K, V. M, G, N, B, P, C, E, Q and Backspace are taken.

## 1. Saving: profile v7 (add-only)

**L2-1. Four maps, every value `true`, keyed by id.** Stars stay in session memory (Ruling 25).
| Field | Shape | Default | Written by |
|---|---|---|---|
| `combat.abilities` | `{ [abilityId]: true }` | `{}` | purchase, lever |
| `combat.secrets` | `{ [levelId]: { [secretId]: true } }` | `{}` | chest, lever (reset) |
| `combat.families` | `{ [familyId]: true }`; Broadsword and Longbow stay implicit (never written) | `{}` | chest |
| `combat.shortcuts` | `{ [levelId]: { [shortcutId]: true } }` | `{}` | nothing in W1 (W2's cave) |

- `SCHEMA_VERSION` 7; the template's `combat` and `Types.CombatProfile` gain the four fields. `Migrations[6]` adds each
  only when nil, on the existing `state.combat`, never assigning a template table (aliasing); safe to run twice.
- **Only the combat place writes them.** The hub reads the profile and never touches them; it shares `ProfileSchema`,
  so both places publish together (the Expeditions freeze until L4 already forces that). A v6 server that loads a v7
  profile warns and plays untouched.
- **Studio:** `proving.rbxl` runs ProfileStore's mock, so every Studio session starts at a fresh v7 template, with no
  double jump and no secrets, and nothing survives. That is why the levers in L2-19 exist. With "Enable Studio Access
  to API Services" a real v6 profile migrates on load. The harness tests the migration (§8, `tests_l2`).

## 2. Double jump becomes owned

**L2-2. The server owns it, and a Player attribute carries it.** `src/shared/Unlocks.luau` is new, pure and
`--!strict`. It is the one home of:
- `Unlocks.AIR_JUMP = "doubleJump"`: the ability id the air jump keys on. It is structural, like a family's `slot`.
- `Unlocks.Attribute(abilityId): string` = `"Ability_" .. abilityId`. This is infrastructure, like `PLACED_ATTRIBUTE`.
- `Unlocks.Owns(abilities: { [string]: boolean }?, id: string): boolean`.
- `Unlocks.HasKey(abilities, config: Types.ExpeditionsConfig, needs: string): boolean`. An ability id listed in
  `config.abilities.list` is held when owned. Anything else (`fire`, `ice`, an unknown word) is **false in W1**: W2
  and W3 add elements. It fails closed.
- `Unlocks.BuyVerdict(state: Types.PlayerState?, def: Types.AbilityDef?, gateOpen: boolean): string?` returns nil
  (ok), `"unavailable"`, `"invalid"`, `"owned"`, `"busy"` or `"insufficientFunds"`, in that order (L2-9).

`UnlockService` (L2-8) sets `player:SetAttribute(Unlocks.Attribute(id), true|false)` for every configured ability at
admit, on a purchase and on a lever. A Player attribute survives respawn. **In the range every ability is set true**,
so the P1 bench feels as it does today.

**L2-3. The client refuses the air jump without it.** `onJumpRequest` adds
`LocalPlayer:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)) ~= true` to its refusals. The check comes before
`airJumpUsed` is set, so a refused press costs nothing.
Once per session the first refused air press toasts "Double Jump: buy it in the lobby (K)" (never in the range).
Phones use the stock jump button, the same `JumpRequest`.

**L2-4. Per-player rise for the ground-aim rule, on both sides.** `WallClip.Rise(movement, airJump: boolean): number`
= `jumpHeight + (if airJump then doubleJumpHeight else 0)`, which is **18 / 30**.
Server: `WeaponService.GroundPoint` passes `player:GetAttribute(Unlocks.Attribute(Unlocks.AIR_JUMP)) == true` (set by
the server itself: authoritative). Client: `InputController.groundPoint` passes the local attribute. Both owners report
the exact expression (the L1c rule). A non-owner's Leap Smash can no longer target the ledge (26 > 18) from Road5 or
any fence top.

**L2-5. Every rule that assumed the double jump, sorted.**
| Rule | Where | W1 |
|---|---|---|
| Air jump | `MovementController` | **per player** (L2-3) |
| Ground-aim rise | `WallClip.Rise`, GroundPoint ×2, `tests_l1c` | **per player** (L2-4) |
| Lookout band (21 < rise ≤ 26) | `check_levels.py:926-963` | **per player: the key** (L2-18) |
| Route climbs ≤ 10, gaps ≤ 15; the sneak path; "the main path never needs it" | `check_levels.py:107-108, 555-583, 2701-2742`; INTERFACES 11145 | already one jump; **now binding** |
| Camp barriers, `stray_reach` 46.6, `climb_max` 43, `unclimbable`, walled camp (wall 64) | `check_levels.py:392-440, 2259-2317` | **worst case = owner, unchanged** |
| Camp trigger ceiling (`triggerHeight` 30, walled `ceiling`) | `StageFlow.luau:61-65`, `Ceiling` | **worst case = owner, unchanged** |
| Camera boom clip height | `CameraController.luau:79` | **worst case = owner, unchanged** |
| Sniper course "a double jump costs nothing more" | `sim_range.py:6668` | **worst case = owner**; LookoutLedge and Secret_lookout rows are labelled "owners only" |
| Threat dodges (`jump_clear` on `jumpHeight`) | `sim_range.py:1599, 3697...` | already one jump; **made explicit** (L2-20) |

## 3. Buying

**L2-6. Config** (`Config/Expeditions.json`, new block):
```json
"abilities": { "list": [
  { "id": "doubleJump", "name": "Double Jump", "text": "A second jump in the air.", "price": { "valor": 10 }, "order": 1 }
] }
```
Glide and Jetpack are not listed in W1. `price.valor` is a whole number > 0; a bad entry is warned at Init and cannot
be bought (degrades, never throws). Types: `AbilityDef = { id, name, text, price: { valor: number }, order: number }`,
`ExpeditionsConfig.abilities: { list: { AbilityDef } }?`.

**L2-7. Remote `RequestBuyAbility(abilityId)`** (`CombatRemotes.luau`): bucket `calls`; validator `args.n == 1 and
isShortString(args[1], MAX_ABILITY_ID_LENGTH)` (32, a code constant like `MAX_LEVEL_ID_LENGTH`). An id, never an amount.

**L2-8. `src/combat/server/Services/UnlockService.luau`** (new): `Configure(mode)`; `Init()` (reads and validates
`abilities`); `AddPlayer(player)` / `RemovePlayer(player)` (attributes in, per-session state out); `SetShopGate(fn:
(Player) -> boolean)`; `OnBuyAbility(player, id)`; `OpenSecret(player, levelId, site, material): SecretFlow.Opening`
with `Opening = { verdict, valor, materials, family: string? }` (L2-12); `GrantAbility`, `RemoveAbility`,
`ResetSecrets(player?)` for the levers. It requires neither WaveService nor DebugService (the gate is a hook: no cycle).

**L2-9. The purchase, with no yield between the check and the write.**
1. The range is active: ignored (everything is owned there).
2. `Unlocks.BuyVerdict(DataService.GetState(player), def, gate(player))`. The gate is `WaveService.MayLeave`: true in
   the lobby, on the summary, and for a member waiting in the lobby camp; false for a fighter in a live run.
3. Ok: `valor -= price.valor`, then `abilities[id] = true`, the attribute is set, `ActionResult { action =
   "buyAbility", slotId = id, ok = true }`, and `ArenaService.SendSnapshot`.
4. Refused: the same ActionResult with `ok = false` and the reason.

Types: `ActionResult.action` gains `"buyAbility"`, and `reason` gains `"owned"`.

**L2-10. The Abilities panel** (`src/combat/client/UI/AbilitiesPanel.luau`, new):
- Opens with **K** or an **"Abilities" button** beside Map on the CombatHud, both lobby only like Map (phones get the
  button); closes on K, Esc or its close button. No sound (Ben, 2026-09-24); Theme's touch minimums; in L3 it becomes
  the Armory's second tab (MISSIONS_DESIGN §10).
- Lists `abilities.list` by `order` from the latest Snapshot (`combat.valor`, `combat.abilities`): name, text, "10
  Valor", and **Owned** / **Buy** / "Need N more Valor".
- Buy sends the intent and disables itself until the `buyAbility` ActionResult (3 s at most). Ok: toast "Double Jump
  learned!", row Owned. Refused: owned "Already yours", busy "Only in the lobby", insufficientFunds "Not enough
  Valor", else "Try again".

## 4. Secrets as chests

**L2-11. `src/combat/server/Services/SecretFlow.luau`** (new, pure, `--!strict`, a sibling of StageFlow):
- `Sites(layout, levelFile): { Site }`. A Site is `{ id, needs, x, z, floorY (block bottom), name, reward? }`, built
  from `layout.secrets` and `levelFile.secrets[id]`.
- `Triggered(site, root: Vector3, rules): boolean`: the flat distance from (x, z) is ≤ `levels.secretReach`, and
  `root.Y − floorY` is in [−`secretBelow`, `secretAbove`].
  - Starting values are 5 / 1 / 9. The chest is 6 wide, the body radius is 1 and the root stands 3 over the feet, so
    standing on the ledge gives 3 and standing on the chest gives 7. A root on Road5 is at −23, and the top of a
    non-owner's jump from Road5 is at −5.
- `Decide(site, hasKey: boolean, found: boolean): "known" | "locked" | "nothing" | "pay"`, in that order: already
  found → known; no key → locked; no reward entry → nothing; otherwise pay.
- `MapRow(sites, found: { [string]: true }?): { Types.MapSecretState }`.

**No secret pays without its key:** `HasKey` fails closed for `fire`/`ice` in W1; the cache and the shrine carry **no
reward entry** in W1 (check_levels, L2-18e); `Decide` checks the key before the reward.

**L2-12. The run loop** (WaveService, every tick in a live phase, after `advance`):
- Tested: each admitted human who is fighting and standing (not down), against `run.secretSites` (bots and waiting
  members skipped); `run.secretSeen[userId][siteId]` makes each verdict fire once per run.
- On `Triggered`, `UnlockService.OpenSecret(player, levelId, site, level.material)` reads the key from the profile
  (`combat.abilities`, never the attribute). On `pay` it writes `valor += reward.valor`, `materials[material] +=
  reward.materials`, `families[reward.family] = true`, `secrets[levelId][id] = true`; WaveService then calls
  `ArenaService.CreditSummary(userId, 0, material, materials, valor, 0)`, sets `run.walletDirty[userId]`, pushes RunFx
  `{ kind = "secret", event = "found", ... }` to every member and resends that player's MapState. On `locked`, a
  private CombatFx `{ event = "locked" }` to that player only; `known` and `nothing` send nothing.
- Chests pay flat (no `rewardMult`, any difficulty), kept at once like per-kill pay (Abandon keeps it). In a party
  each player opens their own chest with their own Double Jump.
- Type: `CombatFxSecret = { kind: "secret", event: "found" | "locked", userId: number, levelId: string, secretId:
  string, name: string, needs: string, valor: number, materials: number, material: string, family: string? }`.

**L2-13. The lookout's reward** (`Config/Levels/1_ForestRoad.json`, new `secrets` block):
```json
"secrets": {
  "lookout": { "name": "The Lookout", "valor": 3, "materials": 50, "family": "flamethrower" },
  "cache":   { "name": "Raiders' Cache" },
  "shrine":  { "name": "Island Shrine" }
}
```
- Sized against a Normal 2 / 2 clear (BALANCE L1c fix 3: about 5.0 min, about 210 Timber, 10 Valor): Timber about
  25% of a clear (band 15–30%); Valor at least 2 and below the Double Jump price.
- `family` is recorded in W1 though `weapons.flamethrower` arrives in W2: **W2 must honour
  `combat.families.flamethrower`**. The card names it from `weapons[family].name`, else the capitalised id.
- `StageFlow.Validate` checks the block (every layout secret has an entry with a name; `valor`, `materials` whole ≥ 0;
  `family` a short string); a problem refuses the level like any other, and the Python mirror (`sim_range`) matches.

**L2-14. Chest look and cue (client, `src/combat/client/Controllers/SecretFx.luau`, new):**
- Unfound: a tall translucent light column above every `Secret_<id>` part (non-colliding, `CanQuery`/`CanTouch`
  false), so a chest is seen before it is reached (§7). Found by the local player (Snapshot `combat.secrets`): tinted
  with the new look `secretOpen` (Expeditions.json `looks`, gold, client-local) and the column removed.
- `found`, local player: a burst (gated on `Theme.lowEndDevice`) and a 3 s centre card: "THE LOOKOUT FOUND", "+3
  Valor", "+50 Timber", "Flamethrower is yours: you can carry it in a later update" (nothing equips in W1). Someone
  else: toast "<Name> found The Lookout". `locked`: toast "Needs DOUBLE JUMP" (check_levels' `NEED_WORDS`).

**L2-15. The map card's secrets row.**
`Types.MapNodeState` gains `secrets: { MapSecretState }?`, `MapSecretState = { id, name, needs, found: boolean }`.
`StageFlow.MapState` gains the receiver's rows by level, built by WaveService with `SecretFlow.MapRow` from the
receiver's own `combat.secrets` (sites cached per level at boot; layouts are static). `MapScreen.luau` (its line 27
says "icons are L2") draws one icon per secret: found = filled with a check, not found = outline with "?", and under
each its key ("2× JUMP", "FIRE", "ICE").

## 5. The lookout must need the double jump

**L2-16. The study's Leap route is real, and the per-player rise alone does not close it.**
With rise 18 a non-owner cannot *target* the ledge, but a Leap Smash cast at the top of one jump from Road5 has its
feet apex at 8 + 18 + 10 = 36. Aimed past the ledge at the void behind it (no floor, so the target sits level with the
caster's floor: legal), the arc crosses the front edge at about 36 and drops below 34 about 17 studs in, over the
ledge, where the colliding mover stands the player on top. Raising the ledge cannot fix it: that needs a rise over 31
(jump + leap + step up) while the owner's band ends at 26.

**L2-17. Fix by data: the ledge becomes a three-sided notch.**
- Three `wall` blocks overlap the ledge's west, east and back edges by 4 studs, leaving only the face toward Road5
  open: `LookoutCliffW` x −295..−291 / z −66..−52, `LookoutCliffE` x −275..−271 / z −66..−52, `LookoutCliffN`
  x −295..−271 / z −66..−62. Tops at **84** from y −4 (block y 40, sy 88): ≥ chest top 38 + `climb_max` 43 + 3, so
  `unclimbable` even from the ledge or the chest. The chest moves to z −57 (spans −60..−54); its sign and
  `LookoutSignPad` stay (the west wall leaves them clear). The rise stays 26, so the owner's band holds.
- Why it closes every route: a ray that would carry an arc over the ledge ends on a wall face over it, whose floor
  probe lands on the ledge top and is refused (26 > 18); every legal target lies on the road's side; an arc from the
  sign pad or A's fence meets a wall before the usable top.
- Side effect to measure: the east wall cuts the ledge's line into camp A, which may drop `LookoutLedge` and
  `Secret_lookout` from `SNIPER_KNOWN_LIMIT_L4`. Another shape is fine if L2-18 proves it.

**L2-18. `check_levels.py`: "a secret is out of reach without its key, within reach with it".** The rule generalises
926–963.
- **(a) With the key:** the owner's band stays (21 < rise ≤ 26). The chest's trigger (L2-11, values from Combat.json)
  holds a standable point on the ledge or the chest.
- **(b) Without the key, jump + step + dash:** the existing test, which now skips `unclimbable` walls. Otherwise the
  new walls read as "reachable", because they are higher than the ledge.
- **(c) Without the key, every lifting ability** (every family's ability with a `height`, worst case, not today's
  fixed loadout; today Leap Smash 10, castRange 32). Take-offs: every standable top within `castRange + stray_reach`
  of the ledge on a 2-stud grid, cast on the ground and at the top of one jump. Targets: every point within
  `castRange` on the flat (2-stud grid plus the rim); its floor is the highest top under it (a solid's top inside its
  footprint, the take-off's floor over a void), refused when more than `Rise(movement, false)` = 18 over the take-off.
  The arc is `MovementController.Leap`'s formula, sampled every 0.5 stud and stopped at the first solid whose top is
  above the feet. **Red** if the feet come within `STEP_UP` of the ledge top (or above it) at any sample within the
  body radius (1) of its usable top (the part no wall covers).
- **(d) The trigger is not met from anywhere else:** no standable top other than the ledge and the chest puts a root
  inside the trigger band.
- **(e) Rewards follow keys:** a `levelFile.secrets` entry with `valor`, `materials` or `family` is allowed only when
  its `needs` is an id in `Expeditions.json abilities.list`. In W1 the cache and the shrine must have none. W2 and W3
  lift this by naming the element's family.
- Mutants in `check_levels_mutants.py`: delete `LookoutCliffN` → (c) red; LookoutCliffE top 60 → `unclimbable` and
  (b) red; cache `valor: 1` → (e) red; chest at z −45 → (d) red; a control stays green.
- Re-pin what moves: R8 `sniperSpots` and `sniper_spots` (98–101, 1852–1863), the perches (1808–1851), `maxParts` (+3
  Parts).

## 6. Studio levers (both entry points; inert outside Studio and in the range)

**L2-19.**
| Lever (`RequestDebug`) | Workspace attribute (Combat.json `debug`) | Effect |
|---|---|---|
| `grantAbility`, value an id | `grantAbilityAttribute`: `"DebugGrantAbility"` (string, consumed; everyone admitted) | owned + attribute + Snapshot; notice "Double Jump on" |
| `removeAbility`, value an id | `removeAbilityAttribute`: `"DebugRemoveAbility"` (string, consumed) | cleared + attribute false; notice "Double Jump off" |
| `resetSecrets` | `resetSecretsAttribute`: `"DebugResetSecrets"` (number > 0, consumed) | clears `combat.secrets`, `combat.shortcuts` and the run's `secretSeen`; MapState resent; families stay |
| `grantValor` (exists) | `GrantValor` (exists) | unchanged |

Studio keys in `DEBUG_KEYS`: **J** toggles Double Jump for the caller (grant or remove, from its own attribute), **H**
resets the caller's secrets, **V** grants `Theme.COMBAT_DEBUG_GRANT_VALOR` (10); `DEBUG_HINT` names them. The
DebugPanel gains "Double Jump on/off" and "Reset secrets". With API access the levers write the real profile, as
GrantValor does today.

## 7. Balance

**L2-20.** `sim_range.py`:
- Every reacting policy gets an explicit `airJump` (default **False**). The planner must never issue an air jump when
  it is False. Today's dodges already use `jumpHeight` only, so confirm it by a check, not by reading.
- The **first run** is the `human` policy at 2 / 2, one jump, on Normal. It must clear Forest Road without going down,
  inside the L1c clear band (4.5–5.75 min). That is the new gate.
- The sniper course keeps the owner as its worst case and labels the rows that need the double jump. No weapon or
  boss number changes.
- `docs/BALANCE.md` "L2 W1": the first-run row, the chest against a clear, and "one solo Normal clear = 10 Valor =
  Double Jump" (a duo splits the boss's Valor by damage share: about two clears each, L2-24).

## 8. Owners (disjoint; one wave; the gates run after all three)

- **luau-engineer** owns `src/server/Services/ProfileSchema.luau`; `src/shared/Types.luau`, `Unlocks.luau` (new),
  `WallClip.luau` (`Rise`); in `src/combat/server/Services/`: `SecretFlow.luau` and `UnlockService.luau` (new),
  `CombatRemotes.luau`, `WaveService.luau` (chest tick, map rows, summary credit), `StageFlow.luau` (`MapState`
  parameter, `Validate` for `secrets`), `WeaponService.luau` (GroundPoint rise only), `DebugService.luau` (levers);
  `tools/crowd_harness/` (`tests_l1c` for the two-argument `Rise`; new `tests_l2.luau` registered in
  `run_harness.py`; `mutate.py` entries for Unlocks, SecretFlow and the new tests; `stage_mirror.luau` if `MapState`
  or `Validate` is mirrored) and `tools/check_stage_mirror.py` if touched. `tests_l2`: `Migrations[6]` (fresh,
  reconciled, twice, no aliasing); `BuyVerdict` every reason in order; `HasKey` (`fire`, `ice`, unknown false);
  `Triggered` at each band edge and at `secretReach`; `Decide` every branch; `MapRow`; `Rise(m, false/true)` = 18 /
  30; `Sites` on the shipped layout (the lookout pays, the cache and the shrine have no reward). Done when the harness and `check_stage_mirror` are green against the designer's data (or a scratch copy, re-run
  afterwards), `py tools/check_compile.py` passes (WaveService grows by a call or two; the logic lives in the new
  modules), and nothing else on the server changes. Report the exact GroundPoint rise expression.
- **ui-engineer** owns, in `src/combat/client/`: `Controllers/MovementController.luau` (L2-3),
  `Controllers/InputController.luau` (the rise mirror only), `Controllers/CombatUIController.luau` (K, the HUD hook,
  `buyAbility` results, CombatFx `secret` routing, `DEBUG_KEYS` J/H/V), `UI/CombatHud.luau` (Abilities button,
  `deps.onAbilities`), `UI/DebugPanel.luau`, new `UI/AbilitiesPanel.luau` and `Controllers/SecretFx.luau`; and
  `src/client/UI/MapScreen.luau` (secrets row), `src/client/UI/Theme.luau` (new constants). Code against the types and the API above; the luau-engineer ships them. Done when every new file stays under
  check_compile's top-level cap (CombatUIController is 2,049 lines, so new behaviour goes in the new modules), stylua,
  selene and luau-lsp are clean, and the rise expression is reported.
- **economy-designer** owns `src/shared/Config/Expeditions.json` (`abilities`, look `secretOpen`), `Config/Combat.json`
  (`levels.secretReach`/`secretBelow`/`secretAbove`, the three `debug` attributes), `Config/Levels/1_ForestRoad.json`
  (`secrets`), `src/shared/Layouts/Levels/ForestRoad.json` (notch, chest), `tools/check_levels.py`,
  `tools/check_levels_mutants.py`, `tools/sim_range.py` (`airJump`, the first-run gate, the validate mirror, re-pins),
  `docs/BALANCE.md`. Done when L2-6, L2-13, L2-17, L2-18 and L2-20 are in; every new rule fails on its mutant; `py tools/check_levels.py`
  and `py tools/sim_range.py` are green; and BALANCE has measured numbers and the sniper re-pin result.
- **Lead** (INTERFACES "# L2 W1 contracts", from this file). The combat `Main.server.luau` wiring, exactly:
  1. `local UnlockService = require(combatFolder:WaitForChild("UnlockService"))`.
  2. `UnlockService.Configure(mode)` beside `WeaponService.Configure(mode)`.
  3. `UnlockService.SetShopGate(WaveService.MayLeave)` beside `ArenaService.SetSnapshotSender`.
  4. `UnlockService` in `orderedServices` after `AbilityService` and before `waveBoot`.
  5. In `runJoinSequence`, `UnlockService.AddPlayer(player)` before `sendSnapshot(player)`, in **both** the range
     branch and the mission branch (the mission one after `AbilityService.AddPlayer`).
  6. `UnlockService.RemovePlayer(player)` in `releasePlayer`.
  7. The handler `RequestBuyAbility`: `if RangeService.IsActive() then return end; UnlockService.OnBuyAbility(player,
     abilityId)`.

  Then review (slices: server and saving; client; data and tools); QA (stylua, selene, luau-lsp with
  `tools/types/globalTypes.d.luau`, rojo build, `check_compile`, the harness, `mutate` in the background (about 2 h),
  `check_levels` with its mutants, `check_stage_mirror`, `sim_range`, `sim_combat`); then docs. Every agent: `git status` / `git diff` first, commit nothing, kill only your own PIDs, and write your report to
  `docs/prompts/l2-w1-reports/<role>.md` as well as replying.

## 9. Risks, and what needs Ben

- **L2-21. The first run loses the double jump everywhere:** hops, dodging lobs and the boss feel all change. The sim
  gate (L2-20) is the only measure until Ben plays camp A with one jump. That is the first step of the W1 playtest.
- **L2-22. §22 lists "the lobby loadout picker" in W1. This contract leaves it in W2**, with the Flamethrower, because
  no second family exists in W1 for it to offer. **Lead to confirm.**
- **L2-23. A cheater can double-jump on the client.** He gains nothing: the key is checked at the reward, from the
  profile. No movement anti-cheat (§22).
- **L2-24. A party splits the boss's 10 Valor**, so two players need about two clears each for Double Jump. Accepted
  for W1; party rules are L5. Worth one line to Ben.
- **L2-25. The notch moves the sniper pins and may remove the lookout perch.** Re-pinning is the designer's. Any
  future secret ledge needs the L2-18(c) rule, which covers glide and jetpack too once they lift a body.
- **L2-26. Studio resets everything every session** (the mock store). The levers J, H and V exist so that Ben never
  has to clear a level twice to see the chest. PLAYTEST must say this plainly.
- **L2-27. W2 must honour `families.flamethrower` recorded in W1.** This contract promises it.
- **L2-28. Phones:** the double jump up the ledge on touch is unmeasured (26 of 30, plus a 3-stud step up).
- **For Ben (not blocking):** at his look, ask whether the one-jump first run and the chest's pay are "about right".
  Nothing else needs him.

## 10. Lead's rulings (2026-10-17, after reading the draft)

- **Accepted as written**, including L2-22: the lobby loadout picker moves to W2 with the Flamethrower.
- **Forward compatibility of v7 (added).** `ProfileSchema.luau` is shared with the live hub, and the live
  Expeditions place still runs older code on the same ProfileStore. luau-engineer must check, with file:line,
  what v6 code does when it loads a v7 profile (keeps unknown keys? refuses a newer version? resets?), and state
  in the report exactly what publishing the hub from `main` after this merge would do to live players. If v6
  code would lose or reset data, stop and report before writing the migration.
- The lead does the seven `Main.server.luau` wiring steps after the engineers report, and writes INTERFACES.
- Reports go to `docs/prompts/l2-w1-reports/<role>.md`.

## 11. Lead's ruling on the leap finding (2026-10-17)

The designer's report (`l2-w1-reports/economy-designer.md`, "Finding") shows the L2-17 notch cannot close the
Leap Smash route to the lookout; two formula changes together do (0 routes), each alone leaves hundreds.
**Ruling: no notch; F1 + F2 in W1**, as pure functions in `src/shared/WallClip.luau` shared by client and
server:
- **F2 (caster's floor over a void):** with no floor hit below the caster, the floor is the feet minus the
  player's own rise (`WallClip.Rise(movement, airJump)`), on both `WeaponService.GroundPoint` and
  `InputController.groundPoint`.
- **F1 (the leap's peak):** a leap's apex is `max(from.Y, to.Y + lift, casterFloor + standingOffset + lift)`
  with `lift = max(height, 0)` in `MovementController.Leap` (and any server mirror of the leap's arc), so a
  leap cast at the top of a jump no longer stacks its height on the jump.
- Harness cases for both functions and a mutation each; `LIFT_MODEL = "floor"` in `tools/check_levels.py`
  once both land, with check_levels and its mutants green. Ground-launched leaps must be unchanged.
