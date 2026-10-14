# L1b groundwork study — report

Read-only study for L1b "the living road" (brief: `docs/prompts/l1b-study.md`). Worktree
`C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-living-road`, read on 2026-10-14. Ben's decisions
(MISSIONS_DESIGN §16) are taken as fixed. Every claim about the code carries `file:line` and is
marked **verified** (read in the code) or **estimated** (arithmetic or judgement, not run).
Paths are shortened: `Svc/` = `src/combat/server/Services/`, `Ctl/` = `src/combat/client/Controllers/`.

---

## 1. One live camp: what assumes one floor, and what per-group needs

### What is single today (verified)

| Where | What is global | Evidence |
|---|---|---|
| `Svc/CrowdService.luau` | one `boundsCenter` (its `.Y` is the floor) and one `boundsHalf` for the whole server | `:187`, `:194` |
| `clampToBounds` | every body clamped into that one rectangle and onto that one floor | `:259-279` |
| `gatherTargets` | a target's `standY` = `boundsCenter.Y` + hip height: "where the root is when they stand on the crowd's floor" | `:457` |
| `integrate` | `floorY = boundsCenter.Y` for grounding, gravity and the charge's carried Y | `:472`, `:493` |
| `simulate` | passes `boundsCenter.Y` to `CrowdBrain.BeginStep` once per step for every body | `:756-762` |
| `Spawn` | lifts a spawn to `max(position.Y, boundsCenter.Y)` | `:1070` |
| `summon` | raises summons at `boundsCenter.Y` | `:1172-1176` |
| `SetBounds` | sets the pair, pushes it to `CrowdBrain.SetArena`, **refused while `aliveCount > 0`** | `:983-999` |
| `Svc/CrowdBrain.luau` | one `stepFloorY` per step; one `arenaCenter` / `arenaHalf` | `:212-217`, `:727-745` |
| `inArena` (keepAway retreat) and `runway` (a lane's length) | bounded by the one rectangle | `:281-311`, used at `:930` and `:606` |
| `land` | every Strike's `floorY = stepFloorY` (the crowd's floor, not the body's) | `:580` |
| `Think` | target = `nearest(body.position)` over **every** target on the server; no range, no camp | `:879`, `:221-235` |
| `Svc/ThreatField.luau` | judges ground shapes as `who.feetY - strike.floorY > height` | `:298`, `:346` |
| `ThreatField.Below` / `Landing` | fall back to `floorY` when no ray hits; `Landing` casts from `floorY + 100` | `:416-430` |
| `Svc/VitalsService.luau` | `above = feet - strike.floorY` for the height rule; a lob moves `strike.floorY` to its landing | `:387`, `:575` |
| `src/shared/HitShapes.luau` | **nothing**: pure shape tests with no crowd floor in them | whole file; only `GROUND_PROBE_*` `:26-29` |
| `Ctl/CrowdRenderer.luau` | one `floor` (centre and half) for tell heights, threat origins and the lane clamp | `:440`, `:1334`, `:1598`, `:1858`, `laneReach` `:2032-2057`, `SetFloor` `:2468` |
| `Svc/WaveService.luau` | `setCrowdFloor`: `CrowdService.Clear()`, `VitalsService.ClearThreats()`, `SetBounds`, `run.floor`, `run.maxAlive` at every camp's `gate` | `:1097-1120`, called `:1137` |
| `WaveService` `fieldClear` | "nothing queued and `CrowdService.AliveCount() == 0`": a server-wide count | `:1246` |
| `WaveService.spawnBursts` | cap is `CrowdService.AliveCount() < stage.maxAlive`: server-wide count against a per-camp cap | `:828` |
| `Svc/StageFlow.luau` | one live stage; only the armed camp can trigger; `IsOut` boxes a closed camp | `:772-781`, `:1095-1112` |
| `WeaponService.SetArena` | a no-op today | `Svc/WeaponService.luau:1895` |

Things that are already per-body or floor-free (verified): separation compares body heights
(`CrowdService.luau:701`), the spatial grid is XZ-only and spans ±131k studs (`:281-285`),
`Query` is a sphere test (`:1250-1297`), the codec carries absolute Y (`CrowdCodec.luau:11-17`).

### Per-group is enough; nothing needs per-body (verified + estimated)

A body never leaves its camp (Ben: chase to the edge, walk home), so its floor and rectangle are
its **camp's**, fixed for its life. The smallest shape that works:

- **`CrowdService` keeps a table of floors**, set once per run with no body alive:
  `SetFloors({ { centre: Vector3, half: Vector3 } }) -> boolean` (index 1..n). `SetBounds(c, h)`
  stays as "one floor at index 1" for the range and the Raider Arena, so every P1-P4 set is
  byte-for-byte as today.
- **Each record gets `floor: number`** (an index), given at `Spawn` (new optional argument; a
  summon inherits its summoner's). `clampToBounds`, `integrate`, the `Spawn` lift and `summon`
  read `floors[enemy.floor]` instead of the two upvalues. Cost: one table index per body per step.
- **`CrowdBrain` takes the floor per body, not per step.** `BeginStep` loses `floorY`; `Body`
  gains `floorY` and a rect (or `Think` takes the floor as an argument). `inArena`, `runway` and
  `land`'s `strike.floorY` read the body's. `SetArena` goes.
- **`standY`** becomes a per-target root lift (`HipHeight + root.Size.Y / 2`, computed as today
  at `CrowdService.luau:457` minus the floor), and the brain adds the body's floor when it leads a
  shot (`ahead`, `CrowdBrain.luau:269-278`). This is the one place where "per target" meets "per
  body"; it stays one addition.
- **`ThreatField` and `VitalsService` need no change**: they read `strike.floorY`, which is
  already carried per Strike. With the brain filling it from the body's floor, every ground shape
  lies on its own camp's floor. `Landing`'s `floorY + 100` is per strike too. **Verified.**
- **`HitShapes`: no change.** **Verified.**
- **The client** needs every body's floor, not one: `RunState` (or a one-off event at the start)
  carries the level's floor list (`floors: { RunFloor }`), and `CrowdSpawnInfo` gains
  `floor: number?` (`Types.luau:2225`; reliable, sent once per body). `CrowdRenderer` replaces the
  one `floor` (`:440`) with a lookup by the entity's index at the four readers listed above.
  `SetFloor(c, h)` stays for the range as "floor 1". **Estimated:** a few dozen lines; the module
  is 2,795 lines and near the local limit (INTERFACES L1 "Client": "group its state").
- **`WaveService`**: `setCrowdFloor` disappears from the camp path; the floors are set once at
  `startLevel` after `CrowdService.Clear()` (which is already there, INTERFACES L1 "Start"). The
  `gate` action of the boss room no longer clears the crowd or the threats (residents of other
  camps may be alive and shooting). `fieldClear` and `spawnBursts`' cap become per camp (§2).
- **`StageFlow`**: see §5. `Plan` already builds one `Zone` per camp with `floorY` and `rect`
  (`StageFlow.luau:26-39`); the floor list is `plan`'s zones in order, so the index is the zone's.
- **`LevelGeometry`**: no change for floors; per-camp barriers (only the boss room has one) are §5.

Why not per-body: nothing in Ben's rulings moves a body between floors. A chaser stops at its
camp's edge, and the boss room locks. A per-body floor would only be needed for enemies that
follow you down the road, which Ben ruled out (§16.1). **Estimated.**

Why the floors must still be set "with nobody alive": the L1 guard (`CrowdService.luau:987-993`)
exists because moving a floor under living bodies clamps them into a rectangle they never stood
in. With a list set once per run, the guard stays, and it never fires in a level.

## 2. Resting, waking, leashing

### What exists (verified)

- **Behaviours** are per group, given at `Spawn` (`CrowdService.luau:1035-1067`): `idle`,
  `walk` (a pace line on Z round the anchor), `strafe`, `jump`, `chase` and `fight`
  (`:51`, `:390-441`). Only `fight` has a mind (`:1103`); the passive five are the range's dummies
  and **never attack**. Every mission and level body is spawned `fight` (`WaveService.luau:53`,
  `:804`, `:830`).
- **A `fight` body hunts at once.** `Think` takes the nearest target on the whole server
  (`CrowdBrain.luau:879`) with no distance limit; the only delay is `threat.spawnGrace` 1 s
  before its first windup (`:896`; `ProvingGrounds.json crowd.threat.spawnGrace` 1.0).
- **Turn-taking** (`perPlayer`): places are counted per kind per target player, server-wide,
  afresh each step (`CrowdBrain.luau:333-361`, `Commit` `:806-818`; fodder 2, the others 1).
  It does not care which camp a body is in. That is right for open camps: a player is in one
  fight at a time, and two camps on one player would still take turns. **Keep as is.**
- **`keepAway`** holds `bandMin..bandMax` from its target and retreats no further than its floor's
  edge (`:918-933`, `inArena` `:281-290`). A shooter whose target is off its floor walks to the
  edge (the clamp, `CrowdService.luau:259-279`) and shoots from there if it reaches (slinger
  reach 32, lobber 42, marksman 48). **This already gives Ben's "slingers still shoot while you
  are in range"** with no new rule, once a target off the floor stays a legal target (below).
- **Nothing rests, nothing has a post, nothing goes home, nothing heals.** No state, field or
  config key exists for any of it (`Mind`, `CrowdBrain.luau:113-160`; `Enemy`,
  `CrowdService.luau:55-103`). **Verified by reading both records whole.**
- Players regenerate out of combat (`VitalsService.luau:86`, `:472`; `regenShare` 0.077 of the
  bar a second in Forest Road), so "run out and heal" is already true for the player.

### What is needed

**A group** (Ben §16.2: groups wake separately) is a set of bodies of one camp with one posture
and one state. One state machine per group (**estimated**, the smallest that covers the rulings):

```
 rest --(sight | hit | a group-mate's wake)--> rise --(riseSeconds)--> fight
   ^                                                                    |
   |                            (no target in play for leashSeconds)    v
   +--------------(every living body at its post: full health)------- home
```

- **Postures** (per group, from the layout): `guard` (stands at its post, facing a heading),
  `patrol` (walks a closed loop of points at `walkPace`), `fire` (sits round a point, slow to
  stand: `riseSeconds` long, the first strike Ben asked for). A guard's and a patroller's
  `riseSeconds` are about 0, a sitter's about 1.5 s. **Estimated numbers.**
- **Waking:** (a) **sight**: a standing target within the posture's `sightRadius` of any body
  of the group, on the flat, between `triggerBelow` under and `triggerHeight` over the camp's
  floor, optionally inside a cone for guards; no ray, because the crowd's step may not raycast
  (`CrowdBrain.luau:44`), so raiders see through the palisade; (b) **hit**: `CrowdService.Damage`
  on a resting body marks its group, read at the next step (Damage runs outside the step,
  `CrowdService.luau:1366`); (c) **a group-mate's wake** is the group waking as a whole, which
  is all Ben's "a raider of their group wakes" needs. The tent (below) wakes with any group of
  its camp.
- **In play:** a target counts for a group while its root is inside the camp's floor rect grown
  by `chaseMargin`, or within the reach of one of the group's awake shooters. `Think` then picks
  the nearest **in-play** target, not the nearest on the server. This is the one change inside
  the existing brain's hot path; the in-play list is built once per group per step (about 15
  groups in a level, at most 4 targets). **Estimated cost: negligible.**
- **Leash and home:** no in-play target for `leashSeconds` → `home`: each body walks to its post
  (a patroller to its loop's nearest point), does not attack, and is healed to full on arrival
  (Ben: "walk back to their posts and heal"). The group is `rest` again once every living body is
  home. A charge in flight finishes first (`CrowdBrain.IsCharging`, `:319`).
- **The leash exploit, said plainly.** A player's sword reaches 12.8 studs (BALANCE "L1: who
  fits where"); a fodder's lunge 4.5 plus its radius 1.3. A body clamped at its floor's edge
  cannot reach a player standing 6 to 12 studs outside it, who can still hit it. If a hit re-wakes
  a body on its way home, a player can farm a camp from just outside its fence. Two answers:
  **(a) evade**: a body going home takes no damage and ignores sight and hits until it is at its
  post (the standard answer; it makes "running out resets the fight" literally true); **(b)** a
  `chaseMargin` larger than any melee reach, with the bodies still clamped to the floor. (b) alone
  does not stop it; (a) does. Lead's decision 3.
- **No refills** (Ben §16.5): a group never respawns; the dead stay dead; only `home` heals.
  The tent has a fixed stock per run.
- **Tent reinforcements:** once any group of its camp is in `fight`, a camp's tent raises up to
  `tent.count` bodies, `tent.every` seconds apart, at the tent's point, as a group of its own in
  `fight`. It pauses while the whole camp is at `rest` and resumes on the next wake from what is
  left of its stock. **Estimated shape.** It reuses `CrowdService.Spawn` as `spawnBursts` does
  (`WaveService.luau:813-845`).

### Where the state goes on the wire (verified + estimated)

- The codec's state byte has 4 bits of state index, and 8 of 16 values are used
  (`CrowdCodec.luau:13-15`, `:37-38`: "append new states (at most 16), never reorder"). **Two
  new states fit with no byte added:** `rest` (sitting) and `rise` (standing up). A guard at its
  post is `idle`; a patroller and a body going home are `move`. A third, `home`, is worth it only
  if the client must draw a body going home differently; its bar refills through `hpFraction`
  alone. **Entries stay 11 bytes.**
- A wake shows in the states themselves (`rest`/`idle` → `rise`/`move`), so no new event is
  needed. A "you were seen" cue (a `!` over the group) can be the client's reading of that
  transition, or a `CombatFx` `camp` effect with `event = "alert"` (`Types.CombatFxCamp` exists
  since L1). The second is clearer for a party; lead's choice.
- **Groups need no wire field.** The client never needs a body's group, only its floor (§1).

### Where the pure rules live (estimated; verified that the harness can load such a module)

A new pure module, **`Svc/CampBrain.luau`** (tables, numbers, and Vector3 within the harness
shim: `X Y Z + - * / Magnitude Unit Dot`, INTERFACES L1 "What the code says"):

```luau
CampBrain.NewGroup(def, floorIndex, posts): Group
CampBrain.Step(group, targets, now, rules): string?       -- the group's next state, or nil
CampBrain.InPlay(group, target, shooters, rules): boolean
CampBrain.Goal(group, body, now): (Vector3?, number)      -- where a resting or homing body walks
CampBrain.Wakes(group, target, rules): boolean            -- the sight test
CampBrain.Dormant(group, targets, rules): boolean         -- §4
```

`CrowdService` keeps the group records beside its bodies and calls `CampBrain.Step` once per group
at the start of each step. `CrowdBrain.Think` runs only for bodies whose group is in `fight`; the
others walk to `CampBrain.Goal` through the passive `seek` (`CrowdService.luau:373-388`). The
harness already loads `CrowdService`, `CrowdBrain`, `ThreatField` and `VitalsService` with stubs
(`tools/crowd_harness/run_harness.py:47-62`), so both the pure rules and their execution in the
crowd step can be tested there, with mutations in `mutate.py`. `sim_range.py` mirrors `CampBrain`
the way it mirrors `CrowdBrain` today (its "P4 threat" section).

## 3. Rewards per kill, kept at once

### How it works today (verified)

- **A kill pays into a pool.** `onCrowdKilled` adds the kind's `Combat.CampReward` to
  `run.pool`, adds each player's damage on that body to `run.damageTally`, counts the killer's
  kill, and adds the boss's Valor (`WaveService.luau:750-777`). It pays only in `wave`, `boss`
  and `breather` (`:753`): **a kill in `travel` pays nothing today**, which open camps would hit
  at once (every resident fight happens outside those phases).
- **Only a checkpoint banks.** `StageFlow.Advance` emits `bank` at a camp's last wave, or at every
  wave with `bankEachWave` (`StageFlow.luau:840-853`); `WaveService.execute` runs `flushPool`,
  `run.banked += 1`, `run.savedAt = stage.name` (`WaveService.luau:1164-1168`).
- **`flushPool`** (`:650-726`): the tally gets each member's floor share
  (`Combat.ContributionShares`, `contributionFloor` 0.1, `Combat.luau:489-514`), the pool is split
  with `math.floor` on cash, materials and Valor each (`Combat.SplitPool`, `:758-768`), cash is
  multiplied by `CombatCashMult` and floored again (`WaveService.luau:687-688`), then written into
  the in-memory profile state (`state.cash`, `state.combat.valor`, `materials`, `stats`), credited
  to the run and session summaries (`ArenaService.CreditSummary`, `ArenaService.luau:1336-1352`),
  and the whole wallet is re-sent (`ArenaService.SendSnapshot` → `Main.server.luau:86-112`,
  which fires `StateChanged` with the **whole `PlayerState`**).
- **Whatever ends the run drops what was not banked**: `EndRun` calls `dropPool()`
  (`WaveService.luau:1013`, `:740-745`); a skip's `drop` does too (`:1189-1192`).
- **The HUD and the card read the banks:** "Progress saved" when `RunState.banked` rises
  (`CombatHud.luau:1079-1084`); "Saved at: ..." on the summary (`SummaryCard.luau:327-328`).

### What changes so every kill is kept (estimated design, on verified code)

- **Flush per kill.** `onCrowdKilled` credits the kill at once, through the `flushPool` path, in
  every live phase (`travel` included). The split is the kill's own `info.damageBy` with the
  floor share: "the amount killed by the party", each kill shared by who hurt that body.
- **The rounding trap (verified arithmetic).** `SplitPool` floors each share. Per kill, in a party
  of two each share is 0.1 + 0.8 × that member's damage fraction, never above 0.9, so a slinger's
  1 Timber floors to **0 for both**; a fodder's 100 cash loses up to 1 per member per kill. Solo loses
  nothing (share 1). Fix: a **per-member carry** of the fractional part (cash, materials, Valor)
  kept for the run and added to the next credit, paid out whole. A pure function next to
  `SplitPool` (for example `Combat.SplitCarry(pool, shares, carry)`) so `sim_combat.py` mirrors
  it and the harness tests it. The run's end pays nothing more (the carry is under 1 of each).
- **`EndRun` no longer drops anything** (there is nothing unbanked). `dropPool` stays only for a
  Studio skip (ruling R5: a skip pays nothing), which now means "the skipped bodies are removed
  without a kill" rather than "the pool is emptied".
- **The boss** pays its Valor (and the Mentor bonus, `payMentors` `:596-645`) at its kill, as
  today; on a win only, by Ben's rule, which is already how it works: the boss's Valor is part of
  its kill.
- **The wallet send must be throttled.** One `StateChanged` with the whole profile per kill, to
  every member, is the one real cost: a fight kills 2 to 5 bodies a second (BALANCE L1: 313 kills
  in a 6.5-minute Normal run, peaks in camp B). Mark the player dirty and send at most once a
  second from the tick. **Estimated.**

### Profile writes and DataStore budget (verified)

- A credit is an **in-memory** change to the ProfileStore profile's data (`WaveService.luau:683-713`).
  Nothing in the dungeon place calls `DataService.SaveAsync` (grep: the only callers are the hub's
  `EconomyService.luau:463` and `MonetizationService.luau:278`).
- ProfileStore writes a profile with one `UpdateAsync` every **300 s** (`AUTO_SAVE_PERIOD`,
  `ServerPackages/.../ProfileStore.luau:170`) and at release. **Per-kill credit costs no
  DataStore request at all**; the budget is unchanged. What a crash loses is what it always lost:
  up to 300 s of everything.

### What a checkpoint still does once it banks nothing (estimated)

- It is a **respawn and rescue point**: `StageFlow.SafePoint` today returns the exit of the last
  cleared camp (`StageFlow.luau:1043-1062`). With sneaking allowed (Ben §16.3) "cleared" is the
  wrong test: the safe point becomes the last checkpoint **reached** (touched), never one inside
  a camp with a group in `fight`.
- It marks **progress for the summary** ("Camps cleared 2 / 3", where a camp is cleared when its
  residents and its tent's stock are dead) and, later, a **join point for co-op** (L5).
- **No bonus on a camp's clear** (Ben's words, "disregarding clearing status"): the banner
  "<name> cleared" stays as feedback only.
- `RunState.banked`, `RunResult.savedAt`, the "Progress saved" notice and "Saved at" go, or turn
  into "Checkpoint reached". `stats.wavesCleared` and `MarkWaveCleared` (`ArenaService.luau:1362`)
  have no waves to count outside the boss room and the arena: count camps cleared, or leave them
  to the boss room. Lead's decision 5.
- **The Raider Arena** banks at every wave today; under one rule it would credit per kill too, so
  a failed arena run keeps the wave in progress (as P5 did). Lead's decision 6.

## 4. Population and the wire

### The limits as they stand (verified)

| Limit | Value | Where |
|---|---|---|
| `crowd.maxAlive` | 160, server-wide; `Spawn` returns 0 past it, silently | `ProvingGrounds.json`; `CrowdService.luau:1054-1056` |
| Summons | top up to `count` (the Colossus: 12 fodder, cooldown 18 s), within `maxAlive` | `CrowdService.luau:1132-1188`; `ProvingGrounds.json` colossus |
| Step and snapshot rate | 15 Hz, one step = one snapshot | `crowd.snapshotHz`; `CrowdService.luau:872-880` |
| Snapshot | 10-byte header + 11 bytes per body, at most 64 bodies per packet (714 bytes), every body to every player | `CrowdCodec.luau:10-17`, `:94-96`; `CrowdService.luau:821-866` (`FireAllUnreliable`) |
| A body not in a snapshot | the client extrapolates 0.12 s, then **holds**; absence never removes | `CrowdRenderer.luau:13-15`; `CrowdCodec.luau:6-7` |
| A body never sampled | not drawn (`samples == 0`) | `CrowdRenderer.luau:1705` |
| Spawn info | `{ id, kind, maxHp, summonerId? }`, no position | `Types.luau:2225` |
| Wire range | i16 at 1/32 stud from the world origin: ±1,024, clamped not wrapped; `Validate` keeps every camp, and its floor + `crowdCeiling` (200), within 1,000 | `CrowdCodec.luau:16-17`; `StageFlow.luau:127-128`, `:425-426` |
| Parts | `levels.maxParts` 600; Forest Road builds 73 | `Combat.json`; BALANCE "L1: the layout" |
| Client pool | prewarmed to `Prewarm(run.maxAlive)`, capped at `crowd.maxAlive` | `CrowdRenderer.luau:2495-2501` |

### The level Ben asked for (estimated)

- **Floors.** "About twice L1's floor" read as twice the **area**: A about 85 × 85, B about
  141 × 133, C about 115 × 115 (L1: 60 × 60, 100 × 94, 81 × 81). The L1 density gate (area / 200)
  then allows 36, 94 and 65 bodies at once: 30 to 40 residents fit B and C easily, and A only up to
  36. Read as twice the **side** (×4 area), every camp fits and the road gets shorter for the same
  1,000 studs; the lead should say which (decision 8).
- **Wire range.** A 1,000-stud road laid straight from x −500 to x +500 keeps every camp inside the
  ±1,000 gate with room for 150-stud floors. Only camps need to be in range: a body never leaves
  its floor (§1), so the road itself carries no body. **No per-zone origin is needed.** The lobby
  (today at z −340) must stay 150 studs from the level's bounds (`check_levels.py`
  `LOBBY_CLEARANCE`).
- **Parts.** L1: 73 for 549 studs and three camps. Doubling the road (about 36 blocks), larger
  camps with more cover, a tent, fires and posts as grey markers (30 to 45 Parts a camp), three
  secrets and signs: **about 180 to 230 Parts**, under 600. Matches Ben's §16 estimate.
- **Bodies alive.** All residents are alive from the start of the run: 100 to 120 on Normal. Then:
  - `countMult` (Hard 1.2, Brutal 1.35, `1_ForestRoad.json`) applied to residents gives **144 and
    162**: Brutal is over `maxAlive` 160 **before** any tent or boss summon, and `Spawn` would
    refuse the excess without a word.
  - Reserve: the boss (1), its summons (12), a tent's bodies alive at once (about 8).
  - So at the highest difficulty the residents must stay under about 139 (160 − 21): **about 100
    on Normal** if `countMult` scales residents, or `maxAlive` must rise, or `countMult` applies
    to the tents and the boss room only (Hard and Brutal add groups through `minDifficulty`
    instead). Lead's decision 4. Whatever is chosen, `Validate` and `check_levels.py` must prove
    "residents × countMult + reserve ≤ maxAlive" for every difficulty.

### Bytes per second per player (estimated from the verified codec)

| Bodies in each snapshot | Packets | Bytes a snapshot | At 15 Hz |
|---|---|---|---|
| L1's peak (22 alive) | 1 | 252 | 3.8 KB/s |
| 40 (one awake camp) | 1 | 450 | 6.8 KB/s |
| 80 (two camps near) | 2 | 900 | 13.5 KB/s |
| 120 (every resident, sent every step) | 2 | 1,340 | 20.1 KB/s |
| 160 (the cap) | 3 | 1,790 | 26.9 KB/s |

Roblox's own transport overhead comes on top. 20 to 27 KB/s for the crowd alone is heavy for a
phone on a mobile network; it is also sent to every member (`FireAllUnreliable`), so a party of
four costs the server four times that.

### Stepped bodies (estimated; the step has never been measured)

- Every record is integrated every step (`CrowdService.luau:775-782`), then separated
  (`:660-745`), then clamped again (`:787-791`). A resting `fight` body today still calls
  `Think` and `nearest()`; with groups at rest only `seek` runs.
- Without dormancy: 100 to 160 bodies stepped at 15 Hz, most of them sitting still. With dormancy:
  one or two camps near a player, so **30 to 80 stepped**, plus any group going home.
- The `[Perf]` line (`CrowdService.luau:886-921`, on in Studio through `debug.perfLogSeconds`) is
  the only measurement there is, and nobody has read it with a boss or with more than 22 bodies.

### Is a dormant state needed? Yes (estimated), and it is cheap once groups exist

- **Rule** (pure, `CampBrain.Dormant`): a group is dormant when it is at `rest` **and** no living
  player's root is within `dormantRadius` of its camp's floor rect (on the flat). A group in
  `rise`, `fight` or `home` is never dormant. `dormantRadius` must exceed the largest
  `sightRadius` plus one snapshot of the fastest move (`Tuning.FastestMove`) so a group wakes
  before anyone can see it frozen. **About 100 to 150 studs.**
- **What dormant means:** the group's bodies are not integrated, not separated (they are still,
  and already apart) and not put in snapshots. A patroller freezes mid-loop, which nobody is near
  enough to see.
- **What the client needs for that:** a body must be drawn without a snapshot. Two ways: the spawn
  info carries the body's position, yaw and state (built fresh for a late joiner, as
  `onPlayerAdded` already rebuilds the list, `CrowdService.luau:953-964`), or a dormant body is
  sent once more in the snapshot of the step it goes dormant. The first is cleaner and also
  shows a whole camp at once on arrival: Ben's "you see the raiders before they see you".
- **Where it lives:** the rule in `CampBrain`; the skip in `CrowdService.simulate` and
  `sendSnapshot` behind one `if`. Both are loaded by the harness.

## 5. The boss room

### What stays as L1 built it (verified)

- **The trigger** on the whole fenced rectangle, between `triggerBelow` under and
  `triggerHeight` over the floor, standing bodies only (`StageFlow.triggered`, `StageFlow.luau:668-683`).
- **The countdown** (`gate`, `levels.gateSeconds`), the **close** (the move first, then gates and
  wall solid: `WaveService.luau:1140-1155`), `MustEnter` and the **grace re-judge** `Strayed`
  (`StageFlow.luau:1064-1077`; tick step 7, INTERFACES L1 "A run"), each fighter moved at most
  once per close (`WaveService.luau:951-976`), the **re-arm** of a countdown that ends with nobody
  standing (`StageFlow.luau:784-799`).
- **The wall** with its inner face on the floor's edge and closed corners
  (`LevelGeometry.BarrierBoxes`, `LevelGeometry.luau:291-330`), in the `ArenaBarrier` collision
  group so rays pass (`LevelService.luau:271-319`), turned solid by `SetCamp` (`:522-540`).
- **Rescue in a closed camp** keeps the body in the camp (`StageFlow.IsOut`, `:1095-1112`): the
  zone's rect plus `player.rescue.outside`, put back at the zone's entry.
- **Waves inside it** (the boss first, then bursts, breathers), the boss's Valor, the end
  `cleared` when its last wave clears (`StageFlow.luau:836-865`, `leaveCamp` `:730-748`).
- **"You cannot leave the level"** needs nothing more than the wall. Abandon (`RequestAbandon`,
  ruling 21) still ends the run; `RequestLeave` is already ignored from a fighting member of a live
  run (`WaveService.MayLeave`, `:1594-1600`; ruling 22); outside the boss room the level's box
  and the rescue already put a body that leaves the level's bounds back on the road (ruling 19).
  The road's far end is the boss room, so there is no other way out. **Verified.**

### What must change (verified that the current code does it; the fix is estimated)

1. **The `gate` action clears the whole crowd and every threat** (`setCrowdFloor`,
   `WaveService.luau:1104-1105`) and moves the one floor (`SetBounds`). With residents alive in
   the other camps (sneaking is allowed), entering the boss room would delete every other camp,
   and the shots of a slinger still firing at the player's back. The floors are set once at the
   start (§1); `gate` sets nothing on the crowd.
2. **`fieldClear` is server-wide**: "nothing queued and `CrowdService.AliveCount() == 0`"
   (`WaveService.luau:1246`). With a resident left alive anywhere, the boss room could never
   clear and the run never end `cleared`. It must count only the boss room's floor (a per-floor
   alive count in `CrowdService`, or the zone's group counts from `CampBrain`).
3. **`spawnBursts` is capped by the server-wide count** (`CrowdService.AliveCount() <
   stage.maxAlive`, `WaveService.luau:828`). A player who sneaked past 80 residents would meet a
   boss room whose bursts never spawn (80 ≥ C's `maxAlive` 30). Same per-floor count.
4. **Only the locking camp has a wall, gates and a stage machine.** Today every camp is a `camp`
   stage that triggers in turn (`armedCamp`, `StageFlow.luau:685-695`), `Validate` refuses a camp
   with no barrier (`:421-446`), and `LevelGeometry.Pieces` builds the barrier's four boxes for
   every camp from the layout-wide `layout.barrier` (`LevelGeometry.luau:646`, `:719-725`). The
   smallest change: a camp gets `locks: boolean` in the layout (the barrier and gates only where
   it is true); the level's stages become `travel` (the whole road and its open camps) then the
   locking camp. `Validate`, `Pieces`, `check_levels.py` and the part count follow.
5. **"A clear field wins" (ruling 17) needs a new meaning.** On the road the field was always
   clear in L1, so a reset there cost a respawn. With residents it is never clear. The rule
   that keeps L1's behaviour is "no group in `rise`, `fight` or `home`, and nothing queued": a
   reset on a quiet road costs a respawn, a down in a fight ends the solo run (Ben's rule).
6. **The Chief's own residents.** Ben's §16.6 gives every camp, the Chief's included, 30 to 40
   raiders in groups. In a room that locks on entry they are seen through the gate before the
   close (Ben §15.1) and wake at the close; the boss and the room's waves follow as in L1. This
   is the lead's ruling to make (decision 7); it costs nothing new beyond §2.
7. **The client:** `RunState.floor` (one) is replaced by the floor list (§1); the objective line
   reads "Follow the road" for the whole road and the boss room's name inside it; "Camp 2 / 3"
   becomes camps cleared, not camps passed (`CombatHud`, INTERFACES L1 "Client").

**The Raider Arena** is a one-camp level whose camp locks: it goes through the same path with
`locks = true`, one floor and no residents, and plays as today. It stays frozen until L4 as Ben's
§16 says (only its banking question is open, decision 6).

## 6. What the tools mirror today, and what each must learn

All verified by reading the tools; the "must learn" lists are estimated.

### `tools/sim_range.py` (6,472 lines)

- **Mirrors today:** `LevelRun` (`:5060`) plays `StageFlow.Advance` row for row, solo, **one camp
  environment at a time** (`self.frame`, "the live camp's centre", `:5084`; `camp_env`
  `:5803`), with the route walked at walk speed, the trigger at the fence line, the countdown,
  the close, bursts toward the camp's centre, breathers, merges, "only a checkpoint pays", "a
  clear field wins", the cap. Its players: reacting, human (0.55 s), never dodges, stands still
  (BALANCE "L1: how the numbers were measured").
- **Breaks:** residents alive from the start in every camp, groups that wake and leash, open
  camps with no trigger, several floors at once, per-kill credit, sneaking, dormancy.
- **Must learn:** a world of several floors with resident groups placed from the layout; a mirror
  of `CampBrain` (wake, rise, in play, leash, home and heal, the tent); the boss room as the only
  `StageFlow` camp; credit at every kill with the carry; the new phases of a run (a player who
  walks into a camp, fights a group, runs out and comes back). New player policies worth their
  cost: one that **sneaks** (keeps outside `sightRadius` where the road allows; it proves the
  road allows it), one that **kites out** (runs past the leash and back: what it costs and earns),
  one that **stands at the edge** (the leash exploit of §2: must earn nothing with evade on).
  The bands move: the 10-minute first clear, the Colossus 64-90 s (unchanged), "standing still"
  becomes "standing still in a woken group".

### `tools/sim_combat.py` (3,470 lines)

- **Mirrors today:** `CampWave`, `CampReward`, `BurstSeconds` (INTERFACES L1 "Balance bands");
  assertions 19 (arena adapter), 20 (level gates), 21 (what each difficulty pays, kill by kind).
- **Must learn:** the split with a carry (§3), mirrored exactly with its floors; resident
  composition per difficulty (`countMult` or `minDifficulty` groups, decision 4) and "residents
  × countMult + reserve ≤ `maxAlive`" as an assertion; 21 re-priced on residents + tents + boss.
  The band "only a checkpoint pays" goes.

### `tools/check_levels.py` (1,286 lines, 123 checks)

Gates that the rulings break (verified):
- Camp sizes for ForestRoad: A 60 × 60, B 100 × 94, C 81 × 81 ±10% (`:64-73`); route
  500-600 studs (`:68`).
- The barrier is layout-wide and checked for every camp (`:512-514`); the part count adds four
  barrier boxes per camp (`:263`).
- "Nothing stands beside a camp between its entry and its exit" (`:580-597`, ruling 10): it
  exists to stop a player going round a camp. **Sneaking is now allowed** (Ben §16.3): keep it
  for the locking camp only.
- Per-stage `maxAlive` ≤ floor area / 200 (`:928-931`): becomes a test of each camp's residents.
- Two gates per camp, four spawn points 12 studs from the entry (`:76-81`): spawn points become
  posts, loops, fires and a tent point.

Must learn: groups, posts, loops and fires on the floor and clear of cover; a tent point; per-camp
`locks`; the resident total per difficulty against `maxAlive` (decision 4); `dormantRadius` over
every `sightRadius` plus a margin; **a sneak path exists** past each open camp (the road, or a
side path, passes every resting group farther than its `sightRadius`), if Ben's "sneaking is
allowed" is meant to be a promise the layout keeps; the new route length (about 1,000).
`ORIGIN_LIMIT` (`:86`) and the kill-height gates stay.

### `tools/check_stage_mirror.py` (813 lines, about 5,600 comparisons)

- **Mirrors today:** `Resolve`, `Validate`, `Plan`, `BurstPoint`, `BossPoint` per level and
  difficulty; `CampWave`, `CampReward`; `BurstSeconds`, `Tempo`, `ShouldMerge`,
  `BreatherSeconds`; 28 scripted runs of `Advance`, `Skip`, `Force` tick for tick
  (`:369`, `:550-620`, `:764-769`); `Directs`, `StillClosing`, `EarnsStar`.
- **Breaks:** every scripted run (their stage shape is camp, camp, camp; each "approached from
  outside its fence", `:29`), every `Plan` comparison (per-camp `locks`, groups).
- **Must learn:** `CampBrain` on grids (`Wakes`, `InPlay`, `Dormant`, `Goal`) and scripted group
  timelines (rest → rise → fight → home → rest) against the Python mirror; the split with a carry;
  the scripted runs rebuilt for one road and one locking camp.

### `tools/crowd_harness/` (1,292 checks, 417 mutations)

Cases and mutations the rulings break (verified in `tests_l1.luau` and `mutate.py`):
- the `CrowdService` floor cases: `SetBounds` off the origin at height 12, refused with a body
  alive, the bounds back (`tests_l1.luau:839-867`, `:1305-1319`);
- the three-camp walk-through ("nothing triggers ... in a camp that is not the next"), "the clear
  emits `clear`, `bank`, `boundary`, `open`", the bank rules (INTERFACES L1 "tools/crowd_harness/");
- the fuzz's invariants (`tests_l1.luau:1324-1334`): "no `gate` ... on a field with a body alive
  or queued" (false by design once residents live), "no `bank` in a batch that ends the run",
  "a cleared run ... banked every wave exactly once";
- 33 of the 96 `l1:` mutations name a trigger, a bank, the pool, the bounds or the floor, among
  them "a camp that is not next triggers", "a camp clear without bank", "bankEachWave ignored",
  "an end that banks", "the run cap banks", "a skip that banks", "SetBounds accepted with a body
  alive", "the wire origin following the bounds" (`mutate.py`).

Must learn: a new `tests_l1b.luau` for `CampBrain` (each wake cause, rise, in play including a
shooter's reach off the floor, the leash, home, the heal on arrival, evade if chosen, dormancy and
its "never while awake", the tent's stock and pause); `CrowdService` with several floors (a body
stands on its own floor, is clamped to its own rect, a summon takes its summoner's floor, a
Strike's `floorY` is the attacker's floor, a dormant body is neither stepped nor sent, the
per-floor alive count); the split with a carry; the new `StageFlow` shape (one locking camp, the
road's "clear field" rule, the safe point at the last checkpoint reached). The L1 bank and
trigger-order mutations are replaced, not deleted silently: each L1b rule gets its own.

## 7. Risks

### Hardened code this touches (the ruling named)

- **P4 commit rule, and "a ground shape lies on the crowd's floor, not the attacker's feet"**
  (`CrowdBrain.luau:84-87`): the per-group floor keeps it (the body's camp floor, never its feet).
  A per-body floor taken from the feet would break the hit that did not cancel a windup. **Verified.**
- **P4 wave 2, a lane's length is cut at the floor's edge and the client must know that edge**
  (`CrowdBrain.runway` `:293-311`; `CrowdRenderer.laneReach` `:2025-2057`). With one client floor,
  a brute's charge tell in camp A would be cut at camp C's edge. The per-floor list on the client
  is not optional. **Verified.**
- **C1 lesson, nothing in a Heartbeat path yields** (`CrowdService.luau:10-11`; L1 ruling 35):
  `CampBrain.Step` runs inside the crowd step; group wakes from `Damage` must be flags read by the
  next step, not calls into the step. **Verified rule; the design is estimated.**
- **L1 ruling 11 and its guard** (`SetBounds` refused with a body alive, `CrowdService.luau:987-993`):
  replaced by floors set once per run with nobody alive. Its two mutations go; a new one must prove
  `SetFloors` is refused with a body alive.
- **L1 ruling 12, the wire origin is the world origin for good** (`CrowdService.luau:188-192`):
  kept. Its gate (`StageFlow.luau:127-128`, `check_levels.py:86`) is what keeps a 1,000-stud road
  legal.
- **L1 ruling 17 / P5 second review ruling, "a clear field wins"** (`StageFlow.luau:766-771`):
  its meaning changes (§5.5); the harness's "fallen wins on a clear field" mutation must follow.
- **L1 Major 1 and ruling 19, the rescue** (`StageFlow.Rescue`, `:1126-1146`;
  `WaveService.rescueFallen`, `:903-949`) and **the P5 carried item "the free rescue gives the
  get-up i-frames; any later level with enemies near an open edge needs a rescue cooldown"**
  (INTERFACES L1 "Open for later steps"). **L1b makes it live:** camps A and B stand at height 8
  with nothing beside them but the void down to `killY` −13 (BALANCE "L1: the layout"; the
  "nothing beside a camp" gate), and once open they have no wall. A player losing a fight steps off the
  edge, is put on the safe point with 1.5 s of i-frames (`ProvingGrounds.json
  player.getUpIframes`) and the group resets behind them. Lead's decision 10.
- **P5 carried, `OnDash` grants i-frames on the request alone** (before any publish): not made
  worse, but residents that chase make the dash the main escape. Still before L4.
- **L1 Majors 3 and 5 (Validate names every missing or zero value):** every new key (groups,
  posts, sight, leash, tent, `locks`) must join `Validate` and `check_levels.py` with a test each,
  or the Majors return.
- **The Stop 2 separation fix** (`crowd.largeRadius`, `CrowdService.luau:574-658`): unchanged;
  brutes (radius 2.2) stay under it.

### The server step (estimated; never measured)

- 2 ms budget, never read with a boss or more than 22 bodies (BALANCE L1 "Most bodies alive":
  14 to 22). L1b's worst moment is the boss room (Colossus + summons + the room's waves) with
  other camps resting: **dormancy is what keeps those out of the step.**
- Without dormancy, 100 to 160 records are integrated, separated, clamped twice and encoded
  every 1/15 s, plus `Think` for every awake one.
- `CrowdService.Query` scans the whole list when a query covers more cells than there are bodies
  (`:1279-1285`): a long shot's broadphase grows with the population.
- `CrowdService.Get` allocates a view per call (`:1299-1315`; P4 study fact), and weapons call it
  per candidate.
- A wallet `StateChanged` per kill (§3) if not throttled.
- **Mitigation:** dormancy, the throttle, and reading the `[Perf]` line at Ben's Stop with the
  boss up (he must read one number off Studio's output; ask for it as a click question with
  ranges, which is how he answers).

### Phones (estimated; none measured)

- Bytes: 20 to 27 KB/s for the crowd alone without dormancy (§4); 7 to 14 KB/s with it.
- Parts: about 200 for the level plus up to 160 pooled figures (`Prewarm` caps at
  `crowd.maxAlive`, `CrowdRenderer.luau:2495-2501`), with `StreamingEnabled` off (L1), so all of
  it is on the phone at once. "A 550-stud level's Parts on a phone" was already never measured
  (INTERFACES L1 "Never measured").
- Reading a resting camp at a distance on a small screen: the `rest` pose and an alert cue must
  read at 50+ studs. Sneaking depends on it.
- `CrowdRenderer.luau` is at **151 of about 180 top-level locals** (`py tools/check_compile.py
  --counts`); the floor list and two poses must go into its state tables or a new module.
  `FeedbackController.luau` is at 159.

### Others

- **Silent spawn refusals** past `maxAlive` (§4) would make a Brutal camp quietly smaller.
- **Sight through the palisade** (no ray in the step): raiders will see a player behind a wall.
  Say so to Ben with the sneak picture.
- **The simulated human is only hit by slingers' shots** (BALANCE "L1: flags for the owner"):
  any band about how much a resident camp hurts is weak until the better human model (owed before
  L4) exists.

## 8. Proposed wave plan

Two building waves and an optional third, each ending in a stop Ben judges by pressing Play in
`tycoon\build\proving.rbxl` and clicking Depart (`debug.provingLevel` stays `forestRoad`).

### Wave 1 — "the camp is alive" (on today's road and today's camp sizes)

What Ben sees: camps A and B inhabited when he arrives (raiders sitting at fires, guards at the
gates, one patrol); they see him at a distance, the group stands up and fights; he can walk out,
they chase to the edge, walk home and heal; he can walk back in; kills pay at once; only the
Chief's clearing locks (as in L1, with its residents visible through the gate). Short key-only
checklist (five steps).

| Owner | Files (disjoint) | Pure / executor |
|---|---|---|
| luau-engineer **A** (the crowd) | `src/shared/Types.luau` (first edit: crowd, level and RunState types), `src/shared/CrowdCodec.luau` (append `rest`, `rise`), new `Svc/CampBrain.luau`, `Svc/CrowdService.luau` (floors, groups, per-floor alive count), `Svc/CrowdBrain.luau` (per-body floor, in-play targets), new `tools/crowd_harness/tests_l1b_crowd.luau` | `CampBrain`, `CrowdCodec` pure; `CrowdService`, `CrowdBrain` executors the harness loads |
| luau-engineer **B** (the run) | `Svc/StageFlow.luau` (open camps, one locking camp, road clear-field rule, safe point at the last checkpoint reached), `src/shared/Combat.luau` (split with a carry), `Svc/LevelGeometry.luau` (`locks`), `Svc/LevelService.luau` (`locks`), `Svc/WaveService.luau` (residents placed at start, per-kill credit, throttled wallet, per-floor `fieldClear` and burst cap), `Svc/ArenaService.luau` (RunState floors), `Svc/DebugService.luau` (skips), `tools/crowd_harness/run_harness.py`, `mutate.py`, `tests_l1.luau`, new `tests_l1b.luau` | `StageFlow`, `LevelGeometry`, `Combat` pure; the rest executors read by review |
| ui-engineer | `Ctl/CrowdRenderer.luau` (floor list, `rest` and `rise` poses), `Ctl/CombatUIController.luau`, `Ctl/CombatFxController.luau` (alert cue), `src/combat/client/UI/CombatHud.luau`, `SummaryCard.luau`, `src/client/UI/Theme.luau` (add only) | executors |
| economy-designer | `Config/Combat.json` (camp rules: sight, rise, leash, chaseMargin), `Config/Levels/1_ForestRoad.json` (groups per camp), `Layouts/Levels/ForestRoad.json` (posts, loops, fires, `locks`), `tools/sim_range.py`, `tools/sim_combat.py`, `tools/check_levels.py`, `tools/check_stage_mirror.py`, `tools/crowd_harness/stage_mirror.luau`, `docs/BALANCE.md` "L1b" | data and mirrors |

A must land `Types.luau` before anyone builds, as B did in L1. B registers A's test file and
mutations, as in L1.

### Wave 2 — "the long road" (Ben's size)

What Ben sees: the 1,000-stud road, the three camps at their new size with 100 to 120 raiders,
the tents sending reinforcements once a camp is awake, a way to sneak past, a first clear of about
10 minutes on Normal; and, one number, the `[Perf]` line in the boss room.

| Owner | Files |
|---|---|
| luau-engineer A | `CampBrain` (dormancy, the tent's rule), `CrowdService` (dormant skip in step and snapshot, the spawn info with position), `tests_l1b_crowd.luau` |
| luau-engineer B | `StageFlow.Validate` (population against `maxAlive` per difficulty, every new key), `WaveService` (the tent executor), `tests_l1b.luau`, `mutate.py` |
| ui-engineer | `CrowdRenderer` (a body drawn from its spawn info, without a snapshot), the phone check |
| economy-designer | the new `ForestRoad.json` and `1_ForestRoad.json`, the population decision in config, `check_levels.py` (sneak path, route, part and population gates), `sim_range.py` bands, `BALANCE.md` |

### Wave 3 (only if Wave 2's stop asks for it) — tuning after Ben's look

Numbers only (sight, leash, rise, tent pace, camp mixes) by the economy-designer, plus whatever
review carried. No new mechanic.

**Review cost:** a four-slice Opus review (the crowd, the run, the client, the data and tests)
after each building wave, as in L1 (about 1.9M tokens a review); one reviewer for each fix diff.

## Decisions for the lead before contracts (Ben's are in MISSIONS_DESIGN §16)

1. **Per-group (per-camp) floors, not per-body.** Recommend: a floor index per body, set from its
   camp, a floor list set once per run (§1).
2. **The wire origin stays the world origin.** Recommend: lay the 1,000-stud road so every camp
   stays inside ±1,000; no per-zone origins (§4).
3. **The leash exploit.** Recommend: **evade** (a body going home takes no damage and ignores
   sight and hits until it is at its post), healed to full on arrival (§2).
4. **Population against `maxAlive` 160.** Recommend: `countMult` scales the tents' stock and the
   boss room's waves, not the residents; Hard and Brutal add resident groups through
   `minDifficulty`; `Validate` and `check_levels.py` prove "residents + reserve ≤ 160" at every
   difficulty. Raising `maxAlive` is the fallback (it also raises the client's pool on phones).
5. **What a checkpoint means.** Recommend: the safe point is the last checkpoint **reached**; a
   camp's clear gives no bonus and only a banner; "Progress saved" and "Saved at" go;
   `stats.wavesCleared` counts the boss room's waves and the camps cleared.
6. **The Raider Arena under per-kill credit.** Recommend: yes, one rule; it changes only what a
   failed arena run keeps (the wave in progress, as in P5). Its numbers stay frozen.
7. **The Chief's camp.** Recommend: residents visible through the gate, woken by the close; the
   boss and the room's waves as in L1.
8. **"About twice L1's floor."** Recommend: twice the area (A about 85 × 85, B about 141 × 133, C
   about 115 × 115), which keeps the density gate; show Ben the render before balance.
9. **Dormancy.** Recommend: yes, in Wave 2, by the rule of §4 (at rest and nobody within about
   120 studs of the camp; never while awake), with spawn infos that carry position.
10. **The rescue beside an open camp.** Recommend: while a group is in `fight` with that player in
    play, a rescue gives no get-up i-frames and puts them at the last checkpoint reached.
11. **The wake cue.** Recommend: a `CombatFx` `camp` effect with `event = "alert"` per group wake,
    so every member sees which group saw them.
12. **Sight without occlusion.** Recommend: distance (and a cone for guards) only; tell Ben that
    raiders see through the palisade.
13. **"A clear field wins" on the road.** Recommend: clear = no group in `rise`, `fight` or `home`
    and nothing queued.
14. **The split of a kill.** Recommend: by that body's own `damageBy` with the floor share, paid at
    once with a per-member carry of fractions.
15. **The wallet send.** Recommend: at most once a second per player.

## Lead's rulings (2026-10-14)

All fifteen recommendations above are taken as written, and the wave plan of §8 is the plan
(Wave 1 "the camp is alive" on today's road and camp sizes; Wave 2 "the long road" at Ben's size;
Wave 3 tuning only if his look asks). Two notes:
- Ruling 5 (a clear gives a banner, no bonus) follows Ben's "disregarding clearing status"; he was
  asked to confirm and may still want a small bonus. Keep the bonus a config number (0 by default)
  so his answer is a config change.
- Ruling 12 (sight through the palisade) is told to Ben with the Wave 1 stop.
