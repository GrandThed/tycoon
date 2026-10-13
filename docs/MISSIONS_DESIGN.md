# Expeditions: levels, secrets and the Armory (design)

**Status: draft for Ben, 2026-10-13. Nothing in this document is built.** It becomes the plan of
record for the mission side once Ben approves it. `docs/COMBAT_DESIGN.md` stays the plan of record
for the fighting itself (weapons, enemies, bosses, health), which is kept.

Marks used below: **[Ben]** = decided by Ben on 2026-10-13. **[proposed]** = the lead's proposal,
not yet approved. **[open]** = a question for Ben, listed again in §11.

## 1. The idea in one paragraph

Missions stop being ten waves in one fenced arena. An expedition becomes a **level**: a path
through a place, with enemy camps along it and a boss at the end. You choose the level on a
**path map** (Candy Crush style) and you choose its **difficulty**, and harder pays better. Levels
hide **secrets** you can see but not reach on your first visit; you come back after buying an
**ability** (double jump, later flight) or with the right **weapon** (fire melts ice, ice freezes
water). The **Armory** becomes a place to look at your weapons and upgrade each one, over 20
tiers, so a weapon you like stays usable for the whole game.

## 2. What Ben decided (2026-10-13)

1. **A level is camps along a path.** Fights happen inside flat camps whose gates close until the
   camp is clear. The path between camps is for exploring, jumping and secrets.
2. **Fire and ice come from the weapon you bring.** A Flamethrower and a frost weapon are new
   weapon families. No gadget slot, no new button.
3. **Tiers are per weapon, 20 of them, each weapon with its own start tier.** This replaces "the
   tier belongs to the slot" (approved 2026-09-28).
4. **Five levels, five themes, in this order:** a forest, a castle, something like hell, another
   planet, a dreamy place. **Only the first one, the forest, is planned in detail and built now.**
5. Also from his message: a boss at the end of every level; the player picks the difficulty and
   harder difficulties pay differently; abilities are bought (double jump; flight as a very
   advanced one); replaying a level after unlocking gear is the point; the Armory should be
   "contemplative".

Rulings this replaces: one ten-wave skeleton for every era (2026-10-12); one mission per city era;
the slot tier ladder of 12. P5 Waves 2 to 4 as planned are suspended.

## 3. What is kept, what changes, what is new

| | |
|---|---|
| **Kept as built** | The 13 weapon families with their styles and abilities; the six enemy roles; the Colossus and the Warlord; health, i-frames, going down; the camera, aim, auto-fire on phones; `WeaponService`, `CrowdService`, `VitalsService`, the crowd harness, `sim_range.py`. |
| **Reused with changes** | The wave code (bursts, rewards per enemy kind, the tempo director) runs one camp instead of one mission. The arena builder builds a level from a layout: each camp is a flat zone with the invisible wall and the rescue from P5 Wave 1. Difficulty is the mission scales P5 Wave 1 added (enemy health, damage, count). |
| **Replaced** | The mission list in the hub (`ExpeditionPanel`) by the map. The Armory panel and `Armory.json`'s slot tiers. `Config/Missions/*.json` by level files. |
| **New** | The level layout and its scenery; gates and checkpoints; secrets and what they give; bought abilities; elements and the things in the world that react to them; two weapon families; one boss; the map screen; saved progress per level. |

**The ten-wave Village arena built in P5 Wave 1 stays** as a bonus node on the map ("Raider
Arena"), because it is finished and costs nothing to keep. **[proposed]**

## 4. The map

```
   (1) FOREST ---- (2) CASTLE ---- (3) UNDERWORLD ---- (4) OTHER PLANET ---- (5) DREAM
        |  \
        |   +-- [Raider Arena]   bonus: opens with stars
        +------ [???]            opens from a secret exit inside the Forest
```

- One screen, a winding path, one node per level, drawn in that level's colours. **[Ben: path map]**
- A node shows: its stars, how many secrets are found, and an icon for what each missing secret
  needs (a wing for double jump, a flame, a snowflake). So you know what to bring. **[proposed]**
- **Stars:** one per difficulty cleared (three per level). The next level opens on any clear.
  Bonus nodes open with a total of stars. **[proposed]**
- **Branches:** some secrets are a second way out of a level, and that exit opens a side node on
  the map (the Super Mario World idea). This is what makes the map a tree. **[proposed]**
- Tapping a node opens a level card: difficulty buttons with the recommended tier and the rewards
  of each, the party, and Depart.

## 5. A level

```
 START --path--> [ CAMP A ] --path--> [ CAMP B ] --path--> [ BOSS ]
                  gate closes           gate closes          gate closes
                  checkpoint after      checkpoint after     rewards, stars
```

- **Camps are flat and closed.** When you enter, the gates shut; enemies arrive in bursts as they do
  today; the last kill opens the gates. Enemies never leave a camp. This is forced by how the
  enemies work (they stand on one flat floor and do not walk around walls), and it also ends the
  old problem of running in a circle. Only one camp is live at a time.
- **Paths are for the player.** Slopes, ledges, gaps, water, side caves. Few or no enemies. This is
  where abilities and secrets live.
- **A checkpoint after each camp** banks what you earned so far. **[proposed]**
- **Length:** about 6 to 8 minutes on a first clear at the first difficulty, shorter than today's
  12-minute arena, because levels are meant to be replayed. **[proposed]**
- **Going down:** in a party, a teammate standing near you revives you (Ben, 2026-10-12). Solo is
  **[open]**: see §11.

## 6. Difficulty

| | Normal | Hard | Brutal |
|---|---|---|---|
| Enemies | the level's basic mix | tougher, more of them, harder roles join the camps | tougher again; the boss gains its second phase earlier |
| Recommended | the level's first tier | two tiers higher | four tiers higher |
| Rewards | ×1 | ×2 | ×4 |
| First clear | a star | a star + the boss's trophy | a star + a reward only Brutal gives |

- All numbers are placeholders for the balance pass. **[proposed]**
- **Overdrive** (after a Rebirth) stays as a fourth setting above Brutal.
- What scales is what the game can already scale: enemy health, enemy damage, enemy count, spawn
  speed, rewards.

## 7. Secrets and coming back

- **You always see a secret before you can reach it.** A ledge too high, an ice wall with a chest
  behind it, an island across the water. The first visit plants the reason to return.
- About **three secrets per level**, each needing a different key. **[proposed]**
- **Two kinds of key:**
  - **Abilities you buy** and keep for ever (§8).
  - **Elements on weapons** you bring (§9).
- **What a secret gives:** a weapon you cannot get anywhere else, upgrade materials, a second way
  out that opens a side node on the map, or a shortcut that makes the level faster on later runs.
- Secrets are saved per player. In a party each player opens their own.

## 8. Abilities you buy

| Ability | What it does | When |
|---|---|---|
| **Double Jump** | a second jump in the air | the first unlock, cheap **[open: or free, as today]** |
| **Glide** | hold jump in the air to fall slowly and cross long gaps | middle of the game |
| **Flight** | **[open]** the lead proposes a jetpack with fuel that refills on the ground and is switched off inside a camp while enemies are alive | very late, the big prize |

- Jump, dash and the ground slam stay free: they are the feel Ben approved.
- Today double jump is free in the test range. If it becomes a purchase, the first minutes of the
  game have less movement; the lead proposes it is the reward for the very first clear, so it is
  missed only once.
- Free flight with no limit would pass every wall, reach every secret and float over every ground
  enemy, so levels could not be designed around it. Hence the fuel and the rule inside camps.
- More candidates for later, none planned: wall climb, grapple, a heavy push for boulders.
- **Paid with Valor**, the boss currency that exists today, so buying abilities means beating
  bosses. **[proposed]**

## 9. Elements

- A weapon family may carry an element: **fire** or **ice**. Two new families bring the count to
  fifteen: a **Flamethrower** (ranged, a short stream that hits everything in it) and a **frost
  weapon** (melee or ranged, **[open]**, a detail for later).
- Things in the world react when such a weapon hits them:

| In the world | Fire | Ice |
|---|---|---|
| Ice wall | melts, the way opens | |
| Bramble thicket | burns away | |
| Water | | the surface freezes and you can walk on it |

- **Elements are keys first.** Burning or freezing enemies is left out for now, because both bosses
  are balanced tightly against today's weapon numbers. It can come later as its own step.
- The weapon is chosen before the level (switching is only allowed outside fights), so the map's
  icons (§4) tell you what to bring.
- The server owns every door, wall and frozen sheet; the client only draws them.

## 10. The Armory

**Tiers.** One ladder of 20 tiers for every weapon, so "tier 9" means the same strength whatever
the weapon. Each weapon enters at its own tier and can be upgraded to 20. **[Ben]**

```
Longbow       T1  [####................]  free at the start
Broadsword    T1  [###.................]  free at the start
Flamethrower  T3    [#.................]  found in the Forest
Castle weapon T5      [................]  found in the Castle
...
A relic       T20                   [#]  found in a hard secret, already at the top
```

- **Five bands of four tiers, one band per level.** Tiers 1 to 4 are paid with what the Forest
  drops, 5 to 8 with the Castle's, and so on. So "my bow goes from tier 1 to tier 4 in the
  forest" is exactly the first band. The last tier of a band also needs the boss's trophy from
  Hard. This is today's system (bands of three tiers, one material per band) stretched to five
  bands of four. **[proposed]**
- **Strength:** the weapon's own numbers × the tier. In code the tier is already applied in one
  place (P5 Wave 1), so per-weapon tiers are a small change there.
- **Health** still comes from the two weapons you carry, by their tiers.
- **The cost of this choice:** switching to a weapon you have not upgraded makes you weaker. Start
  tiers soften it: a weapon found late arrives near your level.

**The screen.** One weapon shown large, in 3D, turning slowly. Beside it: its tier track, what the
next tier gives, what it costs and **which level drops it**, its styles (A and B) and its ability.
Below, a shelf of every weapon: the ones you own, and dark outlines of the ones you do not, each
with a hint of where it is found. A second tab for abilities. **[proposed: a screen, not a room
you walk into]**

- This needs real weapon models. Today weapons are placeholders. No Kenney weapon kit exists
  locally, so they are generated, as the buildings' missing pieces were.

## 11. Questions for Ben

1. **Solo, what does going down mean in a level?** Proposed: you restart from the last checkpoint,
   with a number of tries that depends on the difficulty (three, two, one). The 2026-10-12 ruling
   (solo, the first down ends the run) was made for the arena.
2. **Double jump:** the first, cheap unlock (proposed), or free as today?
3. **Flight:** a jetpack with fuel, off inside camps (proposed), or true free flight?
4. **Are the five levels tied to the city?** Proposed: Forest with the Village, Castle with
   Boomtown, Underworld with Metropolis, the other planet with the Orbital Colony, the dream place
   after the first Rebirth. The map shows the lock ("Reach Boomtown").
5. **The Armory: a screen (proposed) or a room in the hub you walk into?**
6. **The frost weapon:** melee, ranged, or one of each later?
7. **Players who already own tiers in the live game** need a rule for what they get in the new
   system. The balance pass proposes one.

## 12. The five levels

Only the first is planned. The other four are a line each, to fix the order and the mood.

### 1. Forest Road (planned)

Ben's picture: a path through the forest, a really big raider camp along it, and an improvised
tent with a big boss.

```
 TRAILHEAD ~~forest path~~> [ A  PICKETS ] ~~> [ B  MAIN CAMP ] ~~> [ C  CHIEF'S TENT ]
     |            |              palisade           tents, fires         the boss
     |            +-- ledge above the path (DOUBLE JUMP): a lookout with a chest
     |                                 +-- bramble cave (FIRE): the raiders' cache,
     |                                     and a second way out to a side node
     +-- creek bend (ICE): freeze the water, cross to an island shrine
```

- **One camp in three parts**, so it reads as a single big camp: the pickets at its edge, the main
  camp, the chief's clearing.
- **Enemies:** A = fodder and slingers. B = fodder, slingers, brutes, one lobber. Hard adds
  marksmen and plated elites.
- **Boss: the Camp Chief.** A giant brute in front of his tent: a charge, a slam, and a call for
  raiders. He is built from the boss rules that exist (the Colossus's attacks, new numbers, a new
  model), not a new boss system.
- **Secrets:** the lookout (double jump), the cache with the second exit (fire), the island shrine
  (ice). The ice one cannot be opened until a later level gives the frost weapon: the forest is
  the first place you return to.
- **Scenery:** `nature-kit` (the Village's trees and rocks) plus generated pieces for tents,
  palisades and the chief's tent.
- **Drops:** the Forest material for tiers 1 to 4; the Chief's trophy on Hard.

### 2. Castle
Walls, gates and courtyards: camps are courtyards, paths are battlements and towers.
`castle-kit` exists locally. The Warlord and his guard fit a keep.

### 3. Underworld ("something like hell")
Lava, basalt, ash. Fire and ice are the mechanic of the place: freeze a lava crust to cross, melt
black ice. Scenery is generated. **Before this level is built, check Roblox's content rules:**
the look and the name can change the experience's maturity label. Not a concern for the Forest.

### 4. Another planet
Low gravity sections for the glide, craters, a crashed ship. `space-kit` exists locally. The
Colossus fits here.

### 5. The dream place
Floating pieces, paths that only exist from one side, a level built for flight. The one new boss
of the five. Scenery is generated.

## 13. Risks, said plainly

1. **Levels are scenery, and the lead cannot see Studio.** Each level is an asset job with a
   harvest paste, like the city eras. So every level gets a picture for Ben before it is built.
2. **Enemies only fight on flat ground inside camps.** A fight on stairs, a bridge or a slope is
   not possible without new enemy movement. The design above never asks for one.
3. **A boss per level is the most expensive item.** Of five: two exist, the Camp Chief and one
   more are variants, one is new.
4. **Phones:** a longer level with more scenery, and precise jumping on a touch screen, are both
   unmeasured.
5. **Co-op in a level** (who must be inside before a gate closes, where a friend who joins late
   appears) is not designed yet. It is the last step.
6. **This is three systems** (levels, abilities and elements, the Armory). Built in steps with a
   playable stop after each, never together.

## 14. Order of work (proposed)

| Step | What Ben gets to look at |
|---|---|
| **L0. Pictures** | A picture of the map screen, a top-down plan of Forest Road, a picture of the Armory screen. No code. |
| **L1. Forest Road in grey** | Play opens on the level: path, three camps with gates, checkpoints, a stand-in boss, the difficulty choice. Plain blocks, today's enemies. |
| **L2. Secrets and keys** | Double jump as a purchase and the lookout; the Flamethrower and the bramble cave; the frost weapon and the creek. |
| **L3. The Armory** | Per-weapon tiers, the upgrade loop with Forest drops, the new screen, weapon models. |
| **L4. The real forest** | Scenery, the Camp Chief, the map in the hub, rewards balanced. First version that can be published. |
| **L5. Friends** | Parties and revive in a level. |

Then the Castle, as its own plan.

**Until L4 the Expeditions place must not be published from `main`:** the old combat is unmounted
and only the Village arena can be played.
