# L4 W3 fix round, relay from luau-engineer A: the three shared functions, word for word

Written before the code (fix round "Order" 1). Every signature below is what lands in `src/shared/**`; if anything has
to change while building it, this file is edited first and the change is named at the top of
`docs/prompts/l4-w3-fix-reports/luau-a.md`.

## 1. `RunLines.ReadSummary` (F7; for ui A's `UIController.readRunSummary`, and A's `StudioBridge.readSummary`)

`src/shared/RunLines.luau`, required as today (`require(sharedFolder:WaitForChild("RunLines"))`).

```lua
-- One run card off the wire (teleport data, the Studio handoff record, ExpeditionSummary), or nil.
-- nil drops the WHOLE summary (never shown); only a bad line inside `lines` costs just that line.
function RunLines.ReadSummary(value: any): Types.RunSummary?
```

The rule, in this order (any failure answers nil):

| Field | Kept when | Absent |
|---|---|---|
| (the value) | a table | nil |
| `title` | a string of 1 to `RunLines.MAX_TEXT` (48) bytes | nil |
| `wavesCleared`, `kills` | a count: a finite number, >= 0, whole | nil |
| `cash`, `valor`, `seconds` | a total: a finite number, >= 0 | nil |
| `bestWave` | a count | `wavesCleared` (the hub card's old fallback) |
| `mentorValor`, `damageShare` | a total | 0 |
| `died` | `== true` reads true, anything else false | false |
| `materials` | a table of at most `RunLines.MAX` (16) entries, each key a string of 1 to 48 bytes, each amount a total | nil |
| `lines` | `RunLines.Read(raw.lines)` (bad lines dropped, the rest in order; not a table = `{}`) | `{}` |

The answer is a fresh table with every `Types.RunSummary` field filled (`materials` and `lines` fresh copies), so a
caller can hand it on as it stands. A present-but-malformed optional field (`bestWave = -1`, `damageShare = 0/0`) is a
forged field and drops the summary; only an ABSENT one takes its default.

ui A: `readRunSummary(payload)` becomes `return RunLines.ReadSummary(payload)` (or the call inline). The hub server
already forwards what `StudioBridge` read through the same function, so the client's read is a second net.

## 2. `MapRules.SecretRows` (F9; for luau B's `WaveService.secretRows`, and A's `ExpeditionService.SendMap`)

`src/shared/MapRules.luau`.

```lua
-- Every built level's secret row for one player, by level id: MapRules.SecretRow of `sitesOf(levelId)`
-- against `opened[levelId]`, for each key of `built`; a level with no chests has no row (nil, not {}).
-- `sitesOf` is the caller's cached reader (it holds the pcall, the per-level cache and the warn,
-- because it reads Catalog); it must not throw or yield. `opened` = the player's profile
-- `combat.secrets` (nil = nothing opened, every chest unfound).
function MapRules.SecretRows(
	built: { [string]: boolean },
	sitesOf: (levelId: string) -> { Site },
	opened: { [string]: { [string]: boolean } }?
): { [string]: { Types.MapSecretState } }
```

luau B, `WaveService.secretRows` keeps its signature and becomes:

```lua
local function secretRows(
	player: Player,
	built: { [string]: boolean }
): { [string]: { Types.MapSecretState } }
	local profile = DataService.GetState(player)
	return MapRules.SecretRows(built, sitesOf, if profile ~= nil then profile.combat.secrets else nil)
end
```

`sitesOf` (WaveService's, with `boot.sitesByLevel` and its pcall) stays where it is; `MapRules.SecretRows` reads it
only through the argument. (`SecretFlow.Site` = `MapRules.Site`, so WaveService's `sitesOf` type-checks as the
argument unchanged.)

## 3. `MapRules.FirstPick` (F13 support; for ui A's `MapScreen` / `HubMap` and ui B's `CombatUIController`)

`src/shared/MapRules.luau`, moved verbatim from `MapScreen.FirstPick` (`src/client/UI/MapScreen.luau:225-249` at
`36b54c0`), same name, same signature, same body:

```lua
-- The pick a session's first MapState opens the map on: the first open node, in config order,
-- that has no star, at its lowest difficulty (nil); failing that the first open node with a
-- difficulty still to clear, at the lowest such, else at its first. nil = no node is open.
-- `difficulties` = the map's, easiest first.
function MapRules.FirstPick(difficulties: { string }, state: Types.MapState): (string?, string?)
```

ui A: delete `MapScreen.FirstPick` (or leave a one-line forward if you prefer, your call) and call
`MapRules.FirstPick` from `HubMap.luau:233`. ui B: `CombatUIController.luau:1558` calls `MapRules.FirstPick` (both
places load `src/shared`, so `MapRules` is at `ReplicatedStorage.Shared.MapRules` in both; no project-file change).

## 4. F4: no new DataService function

`DataService.IsMockMode(): boolean` already exists (`src/server/Services/DataService.luau:329-334`, the one
`DataService` both places run): `true` while ProfileStore writes to its in-memory mock (`DataStoreState ~= "Access"`,
i.e. Studio with API access off, or no internet). Already read by the combat `Main.server.luau:538`,
`RunRegistry.luau:65`, `ExpeditionService.luau:153` and `StudioBridge.luau:71`.

luau B: refuse `cashEra` unless `RunService:IsStudio() and DataService.IsMockMode()`. One caveat checked in
ProfileStore 1.0.3: `IsMockMode()` also reads true during the boot window while the store is still `"NotReady"`, but no
profile can be loaded in that window (`StartSessionAsync` waits in `WaitForStoreReady` until the state settles), and P
pays only into a loaded member's profile, so the reader is exact wherever P can act. `DataService` is unchanged in
this round.
