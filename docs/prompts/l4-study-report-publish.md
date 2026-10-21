# L4 study, Part C: the hub map, rewards, the end screen and the publish

Brief: `docs/prompts/l4-study.md` (Part C). Worktree `tycoon-p5`, branch `l4-real-forest` at `0b30e45`. No code or
repo file changed except this report.

**Measured** (this session): `py tools/sim_economy.py` (greedy lap, 16:20:04, every era band OK); `py tools/sim_combat.py
--check` (64-bit 3.12, "all twenty-three assertions hold"); a scratch script that reads both simulators and sets the
city's income at six points of each era against a Forest Road clear (`scratchpad\l4-publish\income_vs_run.py`, output
`income_vs_run.txt`). **Read only:** everything else, with file:line below. Nothing was run in Studio or on the live pair.

## 1. The map in the hub

### 1.1 What the hub does today

- **The panel** (`src/client/UI/ExpeditionPanel.luau:1-23`) is C0/C2: one tile per `Config/Missions/*.json` (Village,
  Boomtown, Metropolis, Orbital; `:587-699`), each with Gear Power against `recommendedPower` and a lock "Reach era n in
  your city first" (`:802-861`), an Overdrive toggle, the hub party strip (invite / leave / kick) and the run list. Depart
  fires `RequestExpedition(missionId, overdrive, public)` (`HubRemotes.luau:174-182`, prompt bucket).
- **The server** (`src/server/Services/ExpeditionService.luau:643-749`): leader only (`PartyService.IsLeader`), then
  `Combat.MissionUnlocked` (era <= `highestEra`, `Combat.luau:374-387`), `ReserveServer`, a server-only `RunTicket`
  {accessCode, privateServerId, missionId, overdrive, public, expected} in the `...Codes` MemoryStore hash map (`:188-208`,
  `:722-738`), then `handOff` (`:460-577`): release every profile first, then ONE `TeleportAsync` with teleport data
  {missionId, overdrive, hostUserId} (`:550-560`). In Studio the teleport is replaced by the bridge's handoff record and a
  kick (`:480-527`); every failure path re-joins the player (`TeleportInitFailed`, `:938-960`, connected at `:946`).
- **The dungeon side ignores the choice.** `src/combat/server/Main.server.luau:133-179` reads the hint (teleport data,
  then the Studio record) and says "the hint chooses nothing here; it is the key the hub's ticket is verified against";
  `ArenaService.OpenSession` (`ArenaService.luau:1124-1162`) checks the ticket by (host, missionId, overdrive)
  (`RunRegistry.luau:236-286`) and every arrival lands in the lobby camp, where the leader starts a level with
  `RequestStartLevel` (`WaveService.luau:1832-1990`; node open by the leader's saved stars, `:446-461`).
- **So after a publish today, all four era tiles land in the same lobby.** Three of them lock behind a city era for no
  reason, and none says "Forest Road".
- **`MapScreen.luau` is already shared** (`:1-14`: "the dungeon place mounts it in L1 and the hub in L4"): it takes a
  `MapState`, reports `onDepart(levelId, difficulty)`, has `SetParty`, `Select(nodeId, difficulty)`, `Rest`, and keys via
  the host (`:65-100`). The combat place maps it from `src/client/UI` (`combat.project.json` "MapScreen").
- **What the hub lacks to drive it:** the node rules. `StageFlow.NodeState` / `MapState` (`StageFlow.luau:2841-2910`) and
  `SecretFlow.Sites` / `MapRow` (`SecretFlow.luau:79`, `:321`) live in `src/combat/server/Services`, which the hub's
  `default.project.json` does not map. The data is there: levels, layouts and `Expeditions.json` are shared Config, and
  the hub client holds the whole combat profile (stars, secrets) through `ProfileCopy.Combat` (`ProfileCopy.luau:30-37`).

### 1.2 What "the map in the hub" changes (all three options share the first five)

1. One pure shared module for the node rules (move `NodeState`, `MapState`, `Award`, the secret row into e.g.
   `src/shared/MapRules.luau`; the combat side calls it; `check_stage_mirror.py` follows the move).
2. Hub server: `RequestExpedition(levelId, difficulty, public)` replaces `(missionId, overdrive, public)`; validated
   against the leader's saved stars with the same rule the dungeon uses at `RequestStartLevel`.
3. `RunTicket`, the teleport hint and `StudioBridge.TeleportHint` carry `levelId` + `difficulty` (no `overdrive`).
   An old-shape ticket is refused safely (`RunRegistry.luau:269-276`: "run stays private").
4. Hub client: `MapScreen` replaces the tiles; the party strip stays; the run list stays as is (joining a live run is
   L5; admission only lets non-expected players in while the phase is `lobby`, `ArenaService.luau:1166-1175`).
   `UIController.luau` is 1,660 lines: mount the map from its own module (the 200-locals gate).
5. The four era tiles, `Combat.MissionUnlocked`, `RecommendedPower`, `highestEra` as a gate, the hub's Overdrive toggle
   and the TopBar's Gear Power chip (`UIController.luau:954`) go. Missions 2-4 have no crowd block (sim_combat
   assertion 15: "refused in game") and are deleted; `1_Village.json` holds the Raider Arena's numbers (ruling 27,
   `WaveService.luau:1634`), so it is deleted only after they move into the arena's own files.
6. The option's own step (below): auto-start (A) or a pre-selected node (B).

**The Raider Arena node** (`Expeditions.json:28`) has no `requires`, so it is open from the first visit
(`StageFlow.luau:2841-2892`). It pays 144,250 cash, 258 Timber, 35 Valor in 10.6 min (sim_combat 16, 17): **half
Forest Road's cash and Timber a minute, but more Valor a run (35 against 10)**. It is the ten-wave fenced square, the
look Ben called "really lazy" (MISSIONS_DESIGN §19.2), and its numbers are what keeps `Config/Missions` alive.

## 2. Rewards balanced: the whole lap (measured)

| Forest Road, solo | Cash | Timber | Valor | Clear | Source |
|---|---|---|---|---|---|
| Normal T1 | 131,733 (raiders ~81k, camp bonuses 7,600 = 5.8%, the Colossus 42,900 = 33%) | 211 | 10 | 5.0 min | sim_combat 21 |
| Hard T3 (x2) | 283,800 (x2.15) | 454 (414 by the tunnel) | 20 | 5.22 min (4.84 by the tunnel) | sim_combat 2, 21; BALANCE L3 W1 |
| Brutal T5 (x4) | 568,933 (x4.32) | 906 | 40 (+25 first clear) | 5.24 min | sim_combat 21, BALANCE L3 W1 |
| Chests (once each) | - | lookout 50, cache 60, shrine 60 | 3 / 4 / 6 | - | `1_ForestRoad.json` |
| Raider Arena T1 | 144,250 | 258 | 35 | 10.6 min | sim_combat 16, 17 |

Combat cash goes straight into the city's cash, times the permanent Legacy and Founder's multipliers only
(`Combat.luau:504-511`, `WaveService.luau:787-822`). The city keeps 100% offline income while the player is away
(sim_combat 6).

**Against the city (scratch script on the greedy lap):**

| City moment | City income | A Normal clear is worth |
|---|---|---|
| Village 0:00 / 4:10 | 3 / 251 a second | 12 h / 9 min of city income (the run earns 439 a second) |
| Village 10:27 (25%) | 8,743 a second | 15 s |
| Village 20:54 (50%) | 64,488 a second | 2 s; 0.92% of the 14.28M still owed |
| Boomtown 50% (x1.78) | 34.1M a second | 0.007 s; 0.002% of what is owed |
| Metropolis, Orbital | 6.1B, 1.07T a second at mid-era | nothing |

A brand-new city reaches 131,733 of cumulative income at 6:41, so for the first ~6 minutes a run beats tending the city;
after ~10 minutes of Village it is noise, and from Boomtown on it is invisible. This is C0's "garnish" rule working
(assertion 4: 1.01% of what Village still owes) and Ben's ruling that cash is fixed per enemy (no income-scaled pay,
memory "combat 2026-09-17"). It also means **the biggest number on the end screen means nothing to almost every player.**

**The climb (sim_combat 2):** both starters T1 to T4 in 6 runs, 24.6 min of clears. All four Forest families to their
band top take 2,950 Timber (Broadsword and Longbow 850 each, Flamethrower T2 to T4 750, Warhammer T3 to T4 500), about
9-10 runs and ~40-45 min of clears with the real overheads. After that the dungeon has nothing left to spend on.

**Numbers that look wrong, and proposed targets (economy-designer owns them):**
1. **Valor has no sink after Double Jump** (10 Valor; the only entry in `Expeditions.json:7-10`) while every clear pays
   10-40 and the arena 35. Target: nothing to change in pay; give the pile a purpose on screen (the next ability shown
   locked, "with the Castle"), a lead ruling.
2. **The arena out-earns Forest Road on Valor** (3.3 a minute against 2.0) and loses on everything else. Target, if it
   stays: Forest Road's cash and Timber a minute and at most its Valor a minute, measured by sim_range on the moved files.
3. **Brutal cannot be geared for in a one-level game:** recommended T5, band 1 tops at T4, T5 costs Iron no level pays
   (BALANCE L3 W1 ladder). Ben's ruling ("waits for Castle gear") stands; the card must say so; BALANCE L3 W1 reports
   Brutal only at T5 and T3, so whether a T4 pair clears it is unmeasured.
4. **Content length:** ~45 min of dungeon progression, then nothing (cash, Timber, Valor all idle; the shrine needs the
   Castle's Frost Hammer). Not a number to tune; a risk to say to Ben before he calls it publishable.
5. **Ascension is unreachable** (Steel, Circuits, Alloy; PLAN L3 carried). Nothing shows it in either UI today (grep
   finds no Ascension view in `src/client/UI` or `src/combat/client/UI`), so it does not block the publish.
6. The per-camp bonus is 5.8% of a clear (band 5-10%): fine, but too small to read unless it gets its own line.

What the sims can measure: per-difficulty pay, clear time, the climb, pay bands, R8 snipers, the boss's call pay
(sim_combat 2, 4, 16-23; sim_range `--check`). What they cannot: the overheads (lobby, map, loading, chest detours), party
splits in a level (L5), and whether a reward *feels* like one.

## 3. The end screen

**Today.** `SummaryCard.luau` (combat, 439 lines): title, how it ended, camps n / 3, "Kills n · time", one line "+$cash ·
n Valor", one materials line, the first-clear line, Back to camp / Return (`:1-27`, `:247-300`). Every number is the
server's: `RunSummary` is one accumulator per player, `ArenaService.CreditSummary` (`ArenaService.luau:1349-1365`), so the
kills, the camp bonuses (`WaveService.luau:876-895`), the boss and the chests are already summed and cannot be told apart.
It must fit 640x360 under a 58 px top bar: 329 design px, a party's card already ~326 (`SummaryCard.luau:16-27`). The
hub's `ExpeditionSummaryCard.luau` shows the session's totals on the way home and still names the mission through
`Catalog.GetMissionById` (`:274`), which breaks when `Config/Missions` goes.

**What "coins entering your inventory, items piling up" needs:**
- **Server (luau-engineer B):** `RunSummary.lines`, one entry per source (raiders, each camp's bonus, the boss, each
  chest, the first clear) with cash / materials / Valor, credited at the same call sites. This is also the carried
  "per-camp bonus on screen". The card can roll the wallet from (wallet - run) to wallet with no other server change.
- **Client (ui-engineer):** rows that count up in turn, icons that fly from each row into the wallet chips
  (`CombatHud.luau:389-436`), Timber logs and Valor badges that stack. No sound (combat ids stay 0).
- **Phones:** `Theme.reducedMotion` is true on every touch device (`Theme.luau:1637`) and `Motion.Info` halves and
  linearises every tween (`Motion.luau:10-27`); the flight must still run there, shortened. Gate the number of flying
  icons on `Theme.lowEndDevice`, never on `reducedMotion` (the living-city lesson). A tap skips to the end. The card
  height cannot grow: rows replace the two lines, a party's damage share moves into the header.
- The hub's card becomes the same tally into the city's cash counter, named from the map, not the mission.

## 4. Everything carried into L4

| Item | Owner | What it needs | Blocks publish |
|---|---|---|---|
| `OnDash` grants i-frames on the request alone (`WeaponService.luau:2573-2588`) | luau-engineer A | judge the dash against `PositionRing` at hit time; harness + mutants | **Yes** ("before any publish", PLAN L1 carried) |
| Rescue i-frames near an open edge | lead + designer | closed by L1b-20 (no i-frames while engaged, INTERFACES:11641); re-check on the dressed forest's new drops | Yes if a new drop sits beside a fight |
| Sniper perches, `SNIPER_KNOWN_LIMIT_L4` Normal + Hard | designer + lead | Part A's re-placement; R8 green on every spot | **Yes** (Ben) |
| Natural barriers instead of fenced squares | lead, A, designer | Part A | **Yes** (promised for L4) |
| Scenery; the Camp Chief | lead + kit builders | Parts A and B | **Yes** (L4's scope) |
| The map in the hub; the hub's mission tiles replaced | luau + ui | §1 | **Yes**: today's tiles mislead |
| The end screen; per-camp bonus on screen; per-kill pops | ui + luau B | §3 | Yes (L4's scope) |
| Rewards and difficulties balanced; a better simulated human | designer | §2; slow on several threats, misreads tells | Yes (L4's scope) |
| Arena: 12-seed clear time, merged waves banking once | designer | moot if the arena is hidden (§6 D2) | Only if it stays |
| Delete dead code: `EnemyService` (2,264 lines), `CombatService` (745), the four old remotes and `RequestReady` (`CombatRemotes.luau:124`), C1 paths in `InputController`/`CombatHud`/`CombatUIController.boot`, bots, `PartyMember.ready`, `WeaponService.SetArena`, `director.maxAlive`, `debug.missionAttribute`/`overdriveAttribute`, `Combat.json overdrive`, the old `enemies`/`waveTable`/`bosses` blocks, `Layouts/Arenas/*`, `Config/Missions`, both arena adapters, C1 `onSwing` (L3-53), `Armory.json slots` and `WeaponTierDef.model` (L3-54) | luau + ui + designer | INTERFACES:11154-11172; `ArenaService.luau:37` and `BarrierGroups.luau:20` still require `EnemyService` | No, but do it before the publish: dead paths are live attack surface (remotes with handlers) |
| RunState resends `floors[i].cells` every send (`ArenaService.luau:649`, `WaveService.luau:348`) | luau B | send once per run; with the snapshot-bytes measure | No (bytes on phones) |
| A shot at a seated raider's drawn head; aim assist to standing height | ui + A | Part B's models | No, but visible |
| Sight through walls (no ray in the crowd's step) | A | needed if barriers must hide (Part A) | Only for walled/natural cover |
| The Theme round (grip, back, stage light, ghost tone) | lead + ui | Ben's first screenshot | No |
| Phone fits with icons; phone measurements | Ben + lead | a real phone (only the emulator so far) | **Yes, in practice** ("phones must work") |
| The two-client weapons check | Ben, a second account | a friend in Studio or live | No (live check) |
| The run cap: Forest Road 1,500 s (`1_ForestRoad.json`), arena 1,800 s (`Combat.json:34`); Ben's first L3 run ended "Out of time" in stage 1 | lead | keep; say it in the HUD hint before it fires | No |
| R15-only avatar setting | lead → Ben | MANUAL_STEPS L4-0 | **Yes** |
| "Shut down all servers" after both publish | lead → Ben | MANUAL_STEPS L4-4 | **Yes** |
| Valor without a sink; Ascension unreachable | lead + designer | §2 | No |
| Gamepad gaps (party invite under the Armory; A on Buy/Equip jumping) | ui | only if Ben minds; keep Console off until a pad pass (DISCOVERY §8) | No |
| L5 items (parties in a level, revive, ambush scaling, shortcut leader, Timber split, latecomer, member-body wait timeout) | lead + luau | L5 | No: solo-first publish, say it |

## 5. The publish

**What is live (read):** the last recorded publish of both places is M9 wave 2b, schema v6, ~2026-09-23
(`MANUAL_STEPS.md:1098`, `:1224-1229` ticked; the C2 republish `:1384-1391` is not; commit `2b15570`). So the live hub is
v6 and the live Expeditions place runs C0/C1 code with no `RunTicket`. **The live round trip has never been run**
(`MANUAL_STEPS.md:1247`, C0 §9, unticked). Place ids: hub `140344407905104`, Expeditions `74210626673425`
(`Places.json`). Live name "Era Tycoon: Village to Space (BETA)" (Spanish display "Pueblo al Espacio"); audience reach:
account cleared for all ages, experience still "16+" until its own Audience Reach card is met (memory "audience reach").

**What v8 does to live saves (read):** the first load on new code runs v6 -> v7 -> v8 once (`ProfileSchema.luau:184-200`);
step 7 refunds slot-tier Timber at the frozen prices (at most 500 per profile, `:146-175`); `gear` stays for old code. Old
code on a v8 profile: `Reconcile` only fills nil keys and `Run` answers "ahead" and plays it untouched
(`DataService.luau:91-108`, `:211`). During the window before servers restart, an old hub server could sell slot tiers
with the refunded Timber into frozen `gear`: lost to the player, never paid twice (the version stamp). With Studio API
access on, a Studio session's profile is the real one (`DataService.luau:148-149`), so Ben's own live profile may
already be ahead of v6; harmless either way.

**Checklist (in order):**
1. [lead] Every L4 wave merged, QA green, `py tools/check_compile.py` green, the six place files rebuilt from `main` in the
   main checkout; `git status -sb` clean.
2. [lead] The "before any publish" rows of §4 closed (OnDash, perches, rescue re-check).
3. [Ben, Studio] PLAYTEST for L4 passed, including the hub map -> bridge -> level -> Return in Studio, and one phone pass.
4. [Ben, Creator Hub] **L4-0**: avatar type R15 for the experience (both places).
5. [Ben, Creator Hub] Re-answer the maturity questionnaire for the new combat (Mild, Repeated: DISCOVERY §7).
6. [Ben] Optional, recommended (§6 D4): the same two builds published to a private staging experience first, and the
   round trip run there (Depart, lobby, level, Return, the welcome-back card, a second account's join).
7. [Ben, Studio] **L4-1** hub `build\test.rbxl` -> start place -> Overwrite; **L4-2** `build\combat.rbxl` -> "Expeditions"
   -> Overwrite (read the place name twice); same sitting, never one alone.
8. [Ben, Creator Hub] **L4-3** both rows show today's date; **L4-4** Restart servers at once.
9. [Ben, live] The live checks below on his own account, then a second account.
10. [lead] Record the publish (commit, date, schema v8) in MANUAL_STEPS so the next study does not have to infer it.

**Only checkable on the live pair:** a real `ReserveServer` + group `TeleportAsync` both ways; the ProfileStore session
handed between servers (release before teleport, load on arrival); the real `ActiveRuns` / `...Codes` MemoryStore maps
(a no-op in Studio); `TeleportInitFailed` recovery; real v6 profiles converting (Ben's own first, his Timber refund and
city intact); R15 forced on real avatars with layered clothing and the weapons on their attachments; real phone frame time
and snapshot bytes; two real clients seeing each other's weapons; Restart servers moving everyone to v8 code.

**Studio note:** in Team Create the cloud copy of the start place takes saves ("Studio saved to the live experience
during the paste", INTERFACES:8699-8702). Publishing a rebuilt local file over it is the plan; never publish from that
cloud session.

## 6. Decisions for Ben, risks, and the wave split

**D1. The map in the city: what Depart does.** (cost: §1.2 items 1-5 in every option)

```
 CITY  [Expeditions]
 +--------------------------------------+
 | (1) FOREST ROAD *--( 2 ) CASTLE  lock |
 |      |   Forest Road                  |
 |  [Arena] (o) Normal  T1  x1           |
 |          ( ) Hard    T3  x2           |
 |          ( ) Brutal  T5  x4  (Castle)   |
 |  Party: Ben*, Ana        [ DEPART ]   |
 +--------------------------------------+
     | one loading screen (teleport)
 A:  v lobby camp "Forest Road starts in 3"
     v Forest Road, Normal          (rec.)
 B:  v lobby camp, map open on Forest Road,
       Normal picked: press Depart again
 C:  city has only [Go to the Expeditions]
```
- **A (recommended):** land in the lobby and the level starts by itself once the expected party stands there (cap
  `coop.lobbyWaitSeconds` 30); any refusal falls back to B. Cost: an auto-start from the ticket (the proving build's
  `provingAutoStart` path, `WaveService.luau:1999-2023`, generalised) plus the ticket fields; luau ~1 wave-slice.
- **B:** cheapest real map: `MapScreen.Select` on arrival; one more click and walk.
- **C:** no map in the city; cheapest; not what L4 promised.

**D2. The Raider Arena.** A: **hide it for the publish (recommended)**: it is the fenced square, it pays half, and hiding
it lets `Config/Missions`, both adapters and the C1 data go; a bonus node can come back as a real level. B: keep it, opened
by the Forest Road star, its pay re-set to Forest Road's per minute (designer moves its numbers into its own files). C:
keep as is (open from the start, Valor-rich).

**D3. The end screen.** (preview, illustrative numbers: rows count up, icons fly to the wallet, logs pile)
```
 +--------------------------------------+
 | FOREST ROAD . NORMAL      CLEARED *   |
 |  Raiders x112        +$81,233  +128 T |
 |  Pickets, Main, Chief  +$7,600   +7 T |
 |  The Camp Chief      +$42,900   +76 T |
 |  The Lookout chest              +50 T |
 | ------------------------------------- |
 |  $ 1,204,511 -> 1,336,244   o o o >>  |
 |  Timber [|||||||||||  ] 261  (pile)   |
 |  Valor  +10   next: Glide (Castle)    |
 |  [ Back to camp ]  [ Return to city ] |
 +--------------------------------------+
```
A: **tally rows + flight into the wallet + a pile (recommended)**; luau B for `RunSummary.lines`, ui for the card.
B: a separate full-screen spoils scene after the card (more motion, more phone risk, one more screen to wait through).
C: count-up numbers on today's card only (no source rows; the per-camp bonus stays invisible).

**D4. How to publish.** A: **a private staging experience first (recommended)**: Ben makes a second experience with two
places, the builds go there with its ids, the round trip is run with no live save at risk, then the live pair. Cost: ten
minutes in Creator Hub and a small change so the place ids follow the experience (e.g. `Places.json` keyed by
`game.GameId`; a per-file override does not work in Rojo, memory "co-op"). B: straight to the live pair, then Restart
servers. C: the live pair under "Limitado" for a day (hides the game from today's players).
Also his: whether "(BETA)" stays in the name and Beta Mode stays off (DISCOVERY §0, §12 advise testing under Limitado,
then Público without Beta).

**Lead rulings, no Ben needed:** the next ability shown locked "with the Castle" so Valor has a purpose on screen; the
Brutal card says "Castle gear"; the TopBar Gear Power chip goes; the run list stays untouched until L5; solo-first publish
(L5's party rules said plainly in the publish note).

**Risks, said plainly:**
1. The first real teleport, server reservation, MemoryStore ticket and cross-place save hand-off will happen on the live
   game with real saves, unless D4-A. No live round trip is recorded (MANUAL_STEPS:1247 unticked).
2. Between "Publish" and "Restart servers" old servers keep running old save rules on converted profiles (no loss, no
   double pay, refunded Timber can be wasted). Restart at once.
3. One level is ~45 minutes of progression; then the dungeon has nothing to buy, Brutal is out of reach, the shrine
   needs a weapon that does not exist yet. Players who finish will see "coming with the Castle" everywhere.
4. Cash from a level is meaningless past Village's first ten minutes; the end screen's flying coins celebrate it anyway.
5. Phones are unmeasured with scenery, 100+ bodies, held weapons and the end screen's motion; only the emulator so far.
6. The hub map touches both places' shared code (`Types`, the ticket, `ProfileSchema` readers): it is the one wave that
   cannot be judged in `proving.rbxl` alone; it needs the Studio bridge (API access on) or the live pair.

**Wave split for all of L4** (each playable alone in Studio; the forest first, it needs Ben's pictures and an upload):

| Wave | Scope | Owners | Ben |
|---|---|---|---|
| L4-0 Pictures | dressed Forest Road plan + player-eye views (Part A), the Camp Chief sheet (Part B), the hub map and end screen as previews (above) | kit builder, lead | decides Parts A/B/C questions |
| W1 The real forest | scenery, natural barriers, re-placed perches (R8 green, `SNIPER_KNOWN_LIMIT_L4` empty), camp C dressed; one upload + one harvest paste | kit builder(s), economy-designer (layout, gates), luau-engineer A (Region/barriers), ui-engineer (client dressing if client-side) | strips, paste, Studio look |
| W1b Cleanup (parallel; file-disjoint from W1, so `LevelGeometry.FromArena` goes with whoever owns `LevelGeometry` in W1) | the dead-code list of §4, `Config/Missions` (after D2), `RequestReady`, `OnDash` against the ring, RunState cells sent once | luau-engineer A + B, ui-engineer (client C1 paths), designer (gates that pinned the old data) | "still plays" look |
| W2 The Camp Chief and the raiders' looks | Part B: new numbers on the Colossus rules, models on crowd bodies, the seated head; second paste only if not ready for W1's | kit builder, economy-designer, ui-engineer, luau-engineer A | strips, paste, look |
| W3 The city map, rewards, the end screen | §1.2 + D1, `MapRules` shared, ticket/hint fields, auto-start; `RunSummary.lines`, the tally card in both places; reward targets of §2, the better simulated human | luau-engineer (hub + combat), ui-engineer, economy-designer | Studio look through the bridge |
| W4 Publish readiness | Theme round, phone fits, PLAYTEST end to end, the publish checklist (§5), staging (D4) | lead, ui-engineer, docs-keeper | the publish and the live checks |
