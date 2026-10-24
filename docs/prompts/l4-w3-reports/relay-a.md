# L4 W3 relay from luau-engineer A: the shared APIs and Types, word for word

Written before the code (contract §11). Every signature below is what lands in `src/shared/**` and the hub server; if
anything has to change while building it, this file is edited first and the change is named at the top of
`luau-a.md`. Config key names are the designer's, as already in `Combat.json`, `Expeditions.json` and
`Levels/1_ForestRoad.json` on the branch.

## 1. `src/shared/MapRules.luau` (new, pure, requires `Types` only)

Required as `require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapRules"))` (it sits beside Types).
Moved verbatim from `StageFlow.luau` (the map section, `export type Stars`) and `SecretFlow.luau` (`Reward`, `Site`,
`finite`, `whole`, `rewardOf`, `Sites`, `MapRow` renamed `SecretRow`); behaviour unchanged. `nodeOf`, `hasStar`,
`starCount`, `finite`, `whole` and `rewardOf` stay local (not exported).

```lua
-- levelId -> difficulty -> cleared
export type Stars = { [string]: { [string]: boolean } }
export type Reward = { valor: number, materials: number, family: string?, key: string? }
export type Site = {
	id: string,
	needs: string,
	x: number,
	z: number,
	sx: number,
	sz: number,
	floorY: number,
	name: string,
	reward: Reward?,
}
export type StartVerdict = "ok" | "locked" | "unavailable"

MapRules.MAX_LEVEL_ID_LENGTH = 32   -- moved from CombatRemotes.luau:34-37: both places' validators read these
MapRules.MAX_DIFFICULTY_LENGTH = 12

function MapRules.NodeState(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leader: Stars,
	own: Stars,
	nodeId: string,
	secrets: { [string]: { Types.MapSecretState } }?
): Types.MapNodeState?
function MapRules.MapState(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leader: Stars,
	own: Stars,
	leaderUserId: number,
	secrets: { [string]: { Types.MapSecretState } }?
): Types.MapState
function MapRules.Award(stars: Stars, levelId: string, difficulty: string): boolean
-- `levelFile`: anything with `secrets: { [string]: Types.LevelSecretConfig }?` (LevelFile and LevelConfig both fit)
function MapRules.Sites(layout: Types.LevelLayout, levelFile: { secrets: { [string]: Types.LevelSecretConfig }? }?): { Site }
function MapRules.SecretRow(sites: { Site }, found: { [string]: boolean }?): { Types.MapSecretState }

-- New. WaveService's builtLevels rule (ruling 28): a node is built when a level file names it.
function MapRules.Built(levelIds: { string }): { [string]: boolean }

-- New. The one start rule for the hub's Depart and the dungeon's RequestStartLevel, in this order:
--   "locked"      no node of `map.nodes` names `levelId` (the FIRST node whose `level == levelId` is the one
--                 judged), or NodeState(map, built, leaderStars, leaderStars, thatNode.id) is not open;
--   "unavailable" `difficulty` is not an entry of `map.difficulties`, or `levelDifficulties[difficulty]` is not a
--                 table (nil `levelDifficulties` = unavailable);
--   "ok"          otherwise.
-- Pass the level FILE's `difficulties` (Catalog.GetLevelFile(levelId).difficulties). Pure, no yield.
function MapRules.Startable(
	map: Types.ExpeditionsConfig,
	built: { [string]: boolean },
	leaderStars: Stars,
	levelId: string,
	difficulty: string,
	levelDifficulties: { [string]: any }?
): StartVerdict
```

For **B**: `StageFlow` loses the map section (`nodeOf` .. `Award`) and `export type Stars`; `SecretFlow` loses
`Reward`, `Site`, `whole`, `rewardOf`, `Sites`, `MapRow` and adds `export type Site = MapRules.Site` (and
`export type Reward = MapRules.Reward` if you want the name). SecretFlow still needs its own local `finite` for
`Triggered` and `Shortcuts` (MapRules does not export one). `StageFlow.Stars` → `MapRules.Stars`;
`SecretFlow.Sites` → `MapRules.Sites`; `SecretFlow.MapRow` → `MapRules.SecretRow`; `StageFlow.MapState` /
`NodeState` / `Award` → `MapRules.*`; `startLevel`'s node loop → `MapRules.Startable(map, builtLevels(),
leaderStars, levelId, difficulty, <level file>.difficulties)` with `"locked"` → `"locked"` and `"unavailable"` →
`"unavailable"`; `builtLevels()` may become `MapRules.Built(Catalog.GetLevelIds())`.

## 2. `src/shared/RunLines.luau` (new, pure, requires `Types` only)

```lua
RunLines.MAX = 16        -- lines per summary on the wire; past it Add drops new lines (the totals still count)
RunLines.MAX_TEXT = 48   -- bytes, for id / name / material

-- Merges into the line of the same `kind` + `id` (first-credit order): count, cash, materials and valor add; the
-- line keeps its first `name`; its `material` is the first non-empty one credited. A new line is appended only
-- while #lines < MAX. A number that is not finite and >= 0 adds 0; id / name / material longer than MAX_TEXT are
-- cut to MAX_TEXT bytes at a UTF-8 character boundary (so Read never drops a line the server built). Mutates
-- `lines`; returns nothing.
function RunLines.Add(
	lines: { Types.RunLine },
	key: Types.RunLineKey,
	count: number,
	cash: number,
	material: string,
	materials: number,
	valor: number
): ()

-- Validates a line list off the wire: not a table -> {}; reads indices 1..MAX only (a longer list is cut, holes and
-- non-table entries skipped); a line is kept when `kind` is one of the seven kinds, `id`, `name`, `material` are
-- strings of at most MAX_TEXT bytes (empty allowed), and `count`, `cash`, `materials`, `valor` are finite numbers
-- >= 0; every kept line is a fresh copy (never aliased). A bad line is dropped, the rest kept in order.
function RunLines.Read(value: any): { Types.RunLine }
```

Credit keys (contract §4.1, B's call sites): `{ kind = "raiders", id = "raiders", name = "" }`, `{ kind = "camp",
id = zone.id, name = zone.name }`, `{ kind = "boss", id = info.kind, name = run.bossName or info.kind }`,
`{ kind = "firstClear", id = levelId .. ":" .. difficulty, name = "" }` (32 + 1 + 12 = 45 bytes at most),
`{ kind = "chest", id = site.id, name = site.name }`, `{ kind = "key", id = key, name = keys[key].name or key }`,
`{ kind = "mentor", id = "mentor", name = "" }`.

## 3. `src/shared/Combat.luau`

```lua
-- Combat.json `rewards`, structural copy of Types.CombatRewardsConfig
type CombatRewardsConfig = { eraCashMult: { number } }

-- The run-cash factor of a city era (L4W3-7): `rewards.eraCashMult[era]`.
--   rewards nil, or eraCashMult not a table, or an empty list            -> 1
--   era not a finite number                                               -> 1
--   index = math.min(math.max(math.floor(era), 1), #list)                 (an era past the list takes the last)
--   list[index] not a finite number >= 1                                  -> 1
--   otherwise                                                             -> list[index]
function Combat.EraCashMult(rewards: CombatRewardsConfig?, era: number): number

-- Legacy x Founder's x EraCashMult(rewards, era). Its one caller (WaveService.credit) passes
-- `combatConfig.rewards` and the member's `RunMember.cashEra`.
function Combat.CombatCashMult(
	state: CashOwner,                 -- unchanged: { legacy: number, legacyShop: LegacyShopState }
	gameConfig: GameConfig,
	shopConfig: LegacyShopConfig,
	rewards: CombatRewardsConfig?,
	era: number
): number
```

Gone from Combat.luau: `Combat.MissionUnlocked`, `Combat.RecommendedPower`, the `MissionConfig` and
`CombatOverdriveConfig` copies; `CombatRules` is `{ coop: CombatCoopConfig }`. `TouchHighestEra` stays.
For the designer: `sim_combat.era_cash_mult(rewards, era)` mirrors EraCashMult exactly as tabulated above
(`math.floor` toward minus infinity; Luau `#list` = Python `len(list)` on a JSON array).

## 4. `src/shared/Armory.luau` (row 6, L4B-5)

After row 6 no `src` file reads `Armory.SavedPower` or `Armory.GearPower` (the hub's `computeGearPower` goes here;
the combat `Main.server.luau:110` Snapshot field is B's row 6 part). Both go, and with them `ArmoryConfig.power`
(Types and Armory.luau's copy) and `Armory.Validate`'s `power.tierWeight` line, whose last reader was GearPower.
Added while building: `Armory.HeldTiers` goes too (its last `src` reader was SavedPower; WeaponService uses
`StrikeTier`).
**B: remove the `gearPower = ...Armory.SavedPower(...)` field from combat `Main.server.luau`** (the Snapshot type no
longer has it, and the function is gone).

## 5. Types (`src/shared/Types.luau`)

New, in one `-- L4 W3` block at the end of the file:

```lua
export type RunLineKind = "raiders" | "camp" | "boss" | "chest" | "key" | "firstClear" | "mentor"
export type RunLineKey = { kind: RunLineKind, id: string, name: string }
-- RunLineKey's three fields plus the amounts (written flat, not as an intersection, for the old solver)
export type RunLine = {
	kind: RunLineKind,
	id: string,
	name: string,
	count: number,
	cash: number,
	material: string,
	materials: number,
	valor: number,
}
export type RunDepartState = "waiting" | "counting" | "picked"
export type RunDepart = {
	levelId: string,
	difficulty: string,
	state: RunDepartState,
	startsIn: number?,
	waitIn: number?,
}
export type CombatRewardsConfig = { eraCashMult: { number } }
export type UnlockUpcomingDef = { id: string, name: string, text: string, with: string }
```

Changed in place:

```lua
export type Snapshot = { ... }        -- gearPower: number   REMOVED
export type Delta = { ... }           -- gearPower: number?  REMOVED

export type CombatDebugConfig = {
	...                                -- provingStartDelay: number  REMOVED
	fakeDepartAttribute: string?,      -- NEW (§9 R; "DebugFakeDepart", a string, consumed; nil = off)
	cashEraAttribute: string?,         -- NEW (§9 P; "DebugCashEra", a number, consumed; nil = off)
}
export type CombatConfig = {
	...                                -- overdrive: CombatOverdriveConfig  REMOVED (CombatOverdriveConfig REMOVED)
	rewards: CombatRewardsConfig?,     -- NEW (absent = x1 everywhere)
}
export type CombatLevelsConfig = {
	...
	departCountdownSeconds: number,    -- NEW (§3)
}
-- MissionConfig  REMOVED

export type RunMember = {
	userId: number,
	name: string,
	player: Player,
	character: Model?,
	humanoid: Humanoid?,
	waiting: boolean,
	incomeRate: number,
	cashEra: number,                   -- NEW: the member's own profile `era` at ArenaService.Admit
}
export type RunSummary = {
	title: string,                     -- NEW, replaces missionId (the level's name for a run, the map's for a session)
	wavesCleared: number,              -- overdrive: boolean  REMOVED
	bestWave: number,
	died: boolean,
	cash: number,
	materials: { [string]: number },
	valor: number,
	kills: number,
	seconds: number,
	mentorValor: number,
	damageShare: number,
	lines: { RunLine },                -- NEW (display, merged by source; the totals stay the truth)
}
export type RunState = {
	...
	depart: RunDepart?,                -- NEW: nil once `done` and outside the lobby
}
export type ActiveRun = {
	hostUserId: number,
	hostName: string,
	levelId: string,                   -- replaces missionId
	difficulty: string,                -- replaces overdrive; era REMOVED
	wave: number,
	partySize: number,
	accessCode: string,
	public: boolean,
	memberIds: { number },
}
export type RunTicket = {
	accessCode: string,
	privateServerId: string,
	levelId: string,                   -- replaces missionId
	difficulty: string,                -- replaces overdrive
	public: boolean,
	expected: { number },
}
export type RunListEntry = {
	hostUserId: number,
	hostName: string,
	levelId: string,                   -- replaces missionId
	difficulty: string,                -- replaces overdrive
	wave: number,
	partySize: number,
	relation: RunRelation,
}
export type LevelDifficulty = {
	...
	note: string?,                     -- NEW (§7; StageFlow.Validate accepts an optional string <= 24, B)
}
export type ExpeditionsConfig = {
	...
	abilities: { list: { UnlockAbilityDef }, upcoming: { UnlockUpcomingDef }? }?,   -- `upcoming` NEW
}
```

Unchanged and still there: `MapState`, `MapNodeState`, `MapSecretState`, `MissionRecord` (with `overdriveBest`),
`combat.missions`, `combat.gear`, `combat.highestEra`, `MissionCrowd*`, `CombatMode`.

## 6. Hub remotes and `StudioBridge` (for B, ui A)

- `RequestExpedition(levelId: string, difficulty: string, public: boolean)`: `args.n == 3`, `levelId` 1..32 bytes,
  `difficulty` 1..12 bytes (MapRules caps), `public` boolean; bucket `prompt`. Refusals answer `ActionResult` with
  `action = "expedition"`, `slotId = levelId`, `reason` `"locked"` / `"unavailable"` / `"notLeader"` / `"busy"`.
- `RequestMapState()`: `args.n == 0`, bucket `calls`. The answer is the event **`MapState`** (`Types.MapState`, the
  same shape the dungeon sends), to that player only: nodes open by the hub party leader's stars (the player when
  solo; a Studio fake leader or one without a profile counts no stars), the player's own stars and own secret rows.
  No answer while the player has no profile or `Config/Expeditions` is missing.
- `RunList` rows are `Types.RunListEntry` above (`levelId`, `difficulty`; no `missionId`, no `overdrive`).
- Teleport data on departure: `{ levelId: string, difficulty: string, hostUserId: number }`.
- `StudioBridge.TeleportHint = { levelId: string, difficulty: string, hostUserId: number, accessCode: string? }`;
  `ReadArrival` answers nil (and warns) unless `levelId` is a non-empty string of at most 32 bytes, `difficulty` a
  string of at most 12 bytes and `hostUserId` an id. `ParseReturnData`'s summaries require `title: string` (in place
  of `missionId`; no `overdrive`) and read `lines` through `RunLines.Read`.
