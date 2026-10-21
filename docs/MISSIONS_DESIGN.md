# Expeditions: levels, secrets and the Armory (design)

**Status (2026-10-13): the plan of record for the mission side, approved by Ben in pieces (§2).
L1 (Forest Road in grey) is merged 2026-10-14 and Ben has played it (§15); L1b reworks its camps. Nothing after L1 is
built.** `docs/COMBAT_DESIGN.md` stays the plan of record for the fighting itself (weapons,
enemies, bosses, health), which is kept.

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

6. **Second round of answers, the same day:**
   - **Solo, a down ends the run.** You keep what the checkpoints banked. (The lead had proposed
     tries from the last checkpoint; Ben kept his 2026-10-12 rule.)
   - **Double jump is the first cheap purchase**, not free.
   - **Flight is a glide first, then a jetpack with fuel** that is off inside a live camp.
   - **The map is its own path.** A level opens when the previous one is cleared. Levels are not
     tied to the city's eras.

7. **Third round, after the pictures (https://claude.ai/artifact/9iGAoSonw48U8VpV17MTA4):**
   - **One map screen** for all five levels.
   - **One big camp in three parts** for Forest Road ("looks good").
   - **The Armory is a screen, in both places** (the city and the dungeons).
   - **All dungeons are in one Roblox place, and the player is moved to the level inside that
     place.** No level gets a place of its own.
   - **After a level you stay in the dungeon place**, in a small lobby camp where the map and the
     Armory open; a Return button goes back to the city.
   - **One party per server.** One level runs at a time in a server.
   - **Go for L1** (Forest Road in grey blocks). Each step that passes review and QA is merged to
     `main`, as in P5.

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

- One screen for all five levels, a winding path, one node per level, drawn in that level's
  colours. **[Ben]**
- A node shows: its stars, how many secrets are found, and an icon for what each missing secret
  needs (a wing for double jump, a flame, a snowflake). So you know what to bring. **[proposed]**
- **Stars:** one per difficulty cleared (three per level). The next level opens on any clear.
  Bonus nodes open with a total of stars. **[proposed]**
- **Branches:** some secrets are a second way out of a level, and that exit opens a side node on
  the map (the Super Mario World idea). This is what makes the map a tree. **[proposed]**
- Tapping a node opens a level card: difficulty buttons with the recommended tier and the rewards
  of each, the party, and Depart.

### Where it runs

```
CITY --teleport--> DUNGEON PLACE (one server per party)
                     [ lobby camp ]   the map and the Armory open here
                        |  moved inside the place: no loading screen
                        v
                     [ the level ]
                        |  the level ends, or everyone is down
                        +--> back to the lobby camp: pick again, or Return to the city
```

- The dungeon place is today's Expeditions place. It holds every level; the server builds the one
  that was picked and removes it when the run ends, so only one level exists at a time.
- The party leader picks the level and the difficulty on the map.
- A replay never crosses between places: that teleport is the slow step and the one that can fail.

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
- **Going down:** in a party, a teammate standing near you revives you (Ben, 2026-10-12). **Solo,
  a down ends the run [Ben]**, wherever it happens, the boss included; you keep what the
  checkpoints banked.

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
| **Double Jump** | a second jump in the air | the first purchase, cheap: about what the first boss pays **[Ben]** |
| **Glide** | hold jump in the air to fall slowly and cross long gaps | middle of the game **[Ben]** |
| **Jetpack** | flight with fuel that refills on the ground; switched off inside a camp while enemies are alive | very late, the big prize **[Ben]** |

- Jump, dash and the ground slam stay free: they are the feel Ben approved.
- Today double jump is free in the test range. As a purchase, the first run of the game has only
  the jump and the dash; the price is set so one clear of Forest Road pays for it.
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
the weapon. **Each weapon has its own window on the ladder: its own start tier and its own top tier.**
Not every weapon starts at 1 and not every weapon reaches 20; some start at the top and stay there.
**[Ben, 2026-10-13; restated 2026-10-20: "we are not starting every weapon with tier 1 nor ending every
weapon to tier 20"]** (The picture below was drawn before the restatement: its bars run to 20.)

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
with a hint of where it is found. A second tab for abilities. **[Ben: a screen, and it opens in both places, the city and the
dungeon place's lobby]**

- This needs real weapon models. Today weapons are placeholders. No Kenney weapon kit exists
  locally, so they are generated, as the buildings' missing pieces were.

## 11. Questions for Ben

Answered on 2026-10-13 and moved to §2: solo downs, double jump, flight, the city link.

1. **What still ties combat to the city?** Today a weapon tier can only be bought once the city
   earns enough per second. With the map as its own path, the lead proposes dropping that gate:
   tiers are limited by what the levels drop. The city still receives the cash a level pays.
2. **The frost weapon:** melee, ranged, or one of each later?
3. **Players who already own tiers in the live game** need a rule for what they get in the new
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

- **One camp in three parts [Ben]**, so it reads as a single big camp: the pickets at its edge, the main
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
| **L1. Forest Road in grey** | Play opens in the dungeon place's lobby camp with the map; one node is playable. Forest Road in plain blocks: path, the three camp parts with gates, checkpoints, a stand-in boss, the difficulty choice, and back to the lobby at the end. Today's enemies. Stars last for the session only. **Merged 2026-10-14; Ben's verdict in §15.** |
| **L1b. The living road** | Ben's L1 verdict (§15): enemies already in their camps, camps that do not lock (only the boss's room does), bigger camps and longer roads. Starts in a new session from `docs/prompts/l1b-living-road.md`: a groundwork study, Ben's decisions, contracts, waves. |
| **L2. Secrets and keys** | Double jump as a purchase and the lookout; the Flamethrower and the bramble cave; the frost weapon and the creek. |
| **L3. The Armory** | Per-weapon tiers, the upgrade loop with Forest drops, the new screen, weapon models. |
| **L4. The real forest** | Scenery, the Camp Chief, the map in the hub, rewards balanced. First version that can be published. |
| **L5. Friends** | Parties and revive in a level. |

Then the Castle, as its own plan.

**Until L4 the Expeditions place must not be published from `main`:** the old combat is unmounted
and only the Village arena can be played.

## 15. Ben's verdict on L1 (2026-10-14)

Studio's log: he opened the rebuilt `proving.rbxl` at 00:22, played Forest Road on Normal once, and
the run ended "down" in stage 2 (camp A) about two minutes after boot. He did not reach camp B, the
boss, Hard, the Raider Arena or the phone check. Asked afterwards: **"balance feels good"**.

In his words: *"looks good! one thing i was ambisioning that wasnt in this build is that i was
hopping for the enemies to already be there all the time, with bigger camp sites, and longer roads,
i mean, it is an experiment after all just saying, and something i really didnt like is the fact
that you are closed off from leaving when entering a zone, i was ambisioning that the only zone that
remainds closed is the final room with the boss so you cannot leave the level nor the boss zone.
[...] everything else was allright from a technical demo standpoing"*

**What changes [Ben], for the next step, L1b "the living road":**
1. **Enemies are already there.** A camp is inhabited when you arrive; you see the raiders before
   they see you.
2. **Camps do not lock.** You walk in and out of every camp freely. **Only the boss's room locks**:
   once inside you cannot leave it, nor the level, until the boss falls or the run ends.
3. **Bigger camp sites and longer roads.**
4. Everything else in L1 stands as a technical base: the lobby camp and the map, the difficulties,
   checkpoints banking rewards, the summary and the return to the lobby, the tested stage rules.

This replaces ruling 1 of §2 ("fights happen inside flat camps whose gates close until the camp is
clear") for every camp except the boss's. §5 and §12 describe L1 as built and are to be rewritten in
L1b. Open questions for Ben (resting raiders, running away, what saves progress, refilling camps,
size, sneaking past a camp) and the technical consequences are in `docs/prompts/l1b-living-road.md`,
the prompt for the session that builds L1b.

## 16. Ben's L1b decisions (2026-10-14)

Asked with click questions after the L1 verdict, before any study (he chose "decisions first").

1. **Running away:** raiders chase to the camp's edge, then walk back to their posts and heal.
   Running out resets that fight; slingers still shoot while you are in range. **[Ben]**
2. **At rest:** all three, mixed per camp: guards at posts, patrols walking loops, groups sitting
   at fires (slow to stand, so a first strike). They wake on seeing a player near, on being hit,
   or when a raider of their group wakes. **[Ben; the waking rule is the lead's, in the question]**
3. **Sneaking past a camp is allowed.** **[Ben]**
4. **Rewards come from kills**, "by the amount killed by the party, disregarding clearing status",
   and **every kill is kept the moment it falls**: a down loses nothing already earned. The boss
   still pays its own reward on a win. This replaces L1's ruling 15 ("only a checkpoint pays"):
   a checkpoint no longer banks anything. **[Ben]**
5. **A camp stays as you left it** for the rest of the run: the dead stay dead, survivors heal.
   No refills, so a camp cannot be farmed. **[Ben]**
6. **Size: three camps (Pickets, Main Camp, the Chief), each about twice L1's floor, a road of
   about 1,000 studs, a first clear on Normal of about 10 minutes.** A camp holds 30 to 40 raiders
   in groups that wake separately, plus a tent that sends reinforcements once the camp is awake;
   about 100 to 120 raiders in the level, most resting. Estimates before the study: inside the
   wire's ±1,024 studs, the 160-body cap and about 200 of 600 Parts. **[Ben]**
7. The merge rule holds for L1b: each step that passes review and QA is merged to `main` and the
   place files rebuilt. **[Ben]**

Still standing from §15: only the boss's room locks (L1's close: the trigger on the fenced
rectangle, the wall at the floor's edge, the grace re-judge). **The lead's open points for the
contract:** whether a camp's clear gives anything at all (Ben's words suggest no bonus); what a
checkpoint still means (nothing banks there now; it may only mark progress for the summary and
for co-op later); the Raider Arena stays a closed one-camp node with its own numbers, frozen until
L4.

## 17. Ben's verdict on L1b Wave 1 (2026-10-14)

Studio's log: "Build all" at 11:12 on `main` (the merge), `proving.rbxl` opened at 11:13, one Forest
Road run on Normal, **cleared** in about four minutes. His words: *"feels really good right now!"*
Notes he gave, and how they were settled (click questions, same day):

1. *"you should be able to swing just once in a jump"*: **one sword swing per jump**; the next needs
   a landing; the ground slam is unchanged. **[Ben]**
2. *"i coundnt land a single headshot to the big guys"*: a bug to find (likely the head hit shape
   against the drawn model of brutes and the Colossus). **[lead, Wave 2]**
3. *"the bow seems way to underpower compared to the sword"*: he played at gear 2 / 1 (Broadsword
   tier 2, Longbow tier 1). **The starting preset becomes 2 / 2**; weapon numbers stay, so the bosses
   keep their tuning; he judges the bow again after. **[Ben]**
4. *"the agro range needs to be at least double if you are already agroed"*: read with him as
   **nearby groups join in**: when a group wakes, every resting group of the same camp within twice
   its own sight wakes too. **[Ben]**
5. *"we can do better with the end screen, animating coins entering your inventory, items piling
   up"*: good enough for a prototype; **moved to L4** (the polish step). **[Ben]**

**All of 1–4 are folded into Wave 2 "the long road"** (his choice over a separate small wave).
**Clear bonus (asked at the start of the Wave 2 session, same day): a small bonus**, about 10% of
what that camp's raiders pay, on top of the per-kill pay; a config number. **[Ben]**

## 18. Ben's verdict on L1b Wave 2 (2026-10-15)

Studio's log: "Build all" at 00:07, the rebuilt `proving.rbxl` opened at 00:08, one Forest Road run on
Normal of about 2.5 minutes, the crowd going from 112 to 54 alive (the Pickets and into Main Camp), no
script error. The server's crowd step read p95 0.31–0.58 ms with 54–112 alive (budget 2 ms). His words:
*"everything looks good! lets close it"*. **L1b Wave 2 is closed.** **[Ben]**

Not seen in that run: the Chief's Clearing (the Colossus with the new headshots), the sneak past Main
Camp, the bow at 2 / 2. The checklist's five click questions (road length, tents, one swing per jump,
the Server number with the Colossus up, the bow) are unanswered. Next: Wave 3 (numbers only) or L2
(secrets, keys, the bought double jump), only on his word.

**The Wave 2 click questions, answered 2026-10-15 (start of the Wave 3 session):** the road's length
**about right**; the tents (8, one every 6 s) **about right**; the camps on Normal (sight, group
sizes, hits) **about right**; at 2 / 2 the bow is **stronger** than the sword, so lower it a little.
One swing per jump and the Server number were not asked again. **Wave 3 is that one change: the
Longbow's shot damage, cut a little** (INTERFACES "Wave 3 — the bow"). **[Ben]**

## 19. Ben's verdict on L1b Wave 3, and Wave 4 (2026-10-15)

After his look at Wave 3: *"it feels right"*, *"the bow feels right"*, *"everything else feels good"*.
**Wave 3 is closed.** **[Ben]** Two requests, settled by click questions the same day:

1. *"the game has some unnecessary pauses, like waiting for enemies to spawn on tents"*. Only the tents
   felt slow (not the boss room's waves, the fires' rise or the countdowns). **The tent becomes a pace
   reserve:** it sends raiders only while the player clears the camp faster than the camp's target
   pace ("so it makes enemies spawn only if the player is clearing it too fast"). At a normal pace it
   sends none; a camp is cleared as soon as its raiders are dead, whatever the tent still holds.
   Nobody ever waits for a tent. **[Ben]**
2. *"the fact that the fighting areas are so well defined is really lazy [...] we cannot just block the
   attacks of the enemies outside the battling area, we need to make it so if the player attacks enemies
   outside of the area they follow it, if it means to make the paths a certain way, so be it"*.
   - **No BLOCKED any more:** a hit from anywhere lands and wakes its group, which comes after the
     player. This replaces the "damage only from a player in play" rule (L1b-7). **[Ben]**
   - **One rule for both:** any awake raider follows the player out of the camp, whether hit from the
     road or after the player walked in and left; the camp's edge stops nobody. **[Ben]**
   - **They give up when they lose the player:** out of sight for a few seconds, they walk home and
     heal, as today. **[Ben]**
   - The road may be reshaped (flat at a camp's height near it, wider) so chases work. **[Ben]**
   - **Natural barriers instead of fenced squares** (paths that hinder the enemies' passage) are for
     later: with the real forest, L4. **[Ben]**

**What closes L1:** Wave 4 "no waits, no walls" (the two requests), then Ben's look, which must also
reach what he has never seen in Studio: the Chief's Clearing (the Colossus, the headshots) and the sneak
past Main Camp. Everything else carried (the dash check before any publish, phones, two players, the
end screen) belongs to L4 and L5. Brief: `docs/prompts/l1b-wave4.md`.

**Wave 4, after the study (2026-10-15, click questions with sketches):** the raiders may follow the player
**anywhere on the road** (A's raiders may follow him to B's gate and fight beside B's; the lead's "halfway
to the next camp" was not taken); a player shooting from a spot they cannot reach (the lookout ledge,
below the drop) **makes them give up**: every hit lands, the melee raiders wait 3 s at the edge and walk
home to heal, their shooters still shoot back. **[Ben]**

**Wave 4 fix round (2026-10-16):** sniping from the lookout ledge, the secret lookout and the cache block
on Normal pays 1.0–1.7× the fighting player's cash per minute (no data lever fixed it; camps never refill,
so only the pace changes). Ben: **accept for L1, fix in L4** when the real forest re-places the perches;
the simulator gate must pass on every spot before L4 ships. **[Ben]**

## 20. L1 closed (2026-10-16)

After the Wave 4 merge Ben said *"okey, lets close L1"*. **L1 (Forest Road in grey, with L1b's living road) is
closed on his word.** **[Ben]** Studio's log shows no session on the Wave 4 build, so Wave 4 (raiders following
out of the camps, the tent as a pace reserve, N through every camp) and the Chief's Clearing (the Colossus with
headshots), never reached in any of his runs, are unplayed by him. PLAYTEST "L1b Wave 4" opens his first L2
look. Carried to L4: the three Normal perch snipers, the phone auto-fire check in Studio, the per-camp bonus on
screen, RunState's resent cells, natural barriers instead of fenced squares. Next: L2 (secrets, keys, the bought
double jump), only on his word.

## 21. The Chief's Clearing, redone before L2 (2026-10-16)

Before starting L2 Ben said the boss camp "feels wrong": *"it should have an entrance where you dont see any
enemies, and after you enter the camp you are ganked by a small group of enemies, the player should not be able
to see the enemies from the outside of the camp"*. Today it is an open square with a 4-stud fence, a gate on the
road's line, nine guards facing the player at that gate and three more groups in view from the road, then two
waves of about 35 and the Colossus. Settled by click questions the same day (the lead's recommendation each time):

- **Ambush, then the boss.** A small group (about 8 to 10) jumps the player as the gate shuts; when it is dead
  the Colossus comes. The two big waves and every resident group of the clearing are gone. **[Ben]**
- **From both flanks.** The ambushers wait behind cover on either side of the entrance, out of sight of the
  passage, and rush in from left and right as the player steps in. **[Ben]**
- **A bent passage.** A tall wall all round the clearing; the road reaches it through a short gatehouse that
  turns once, so nothing inside is visible until the player is through the turn. Grey blocks now; the real
  forest (L4) dresses it. **[Ben]**

Lead's reading: nothing of the clearing (bodies, their markers, the Colossus) may be visible from the road or
from any spot a player can reach outside it, including at the top of a double jump. This is a fix of L1, done
before L2 on its own branch (`l1c-chief-clearing`), merged under the same rule once review and QA pass.

## 22. L2 "secrets and keys": decisions (2026-10-17)

Ben: *"just start L2"* (the L1c clearing is merged but unplayed; its playtest opens the first L2 look). Click
questions the same day, after a groundwork study (`docs/prompts/l2-study-report.md`):

- **A chain of secrets.** Clear Forest Road, buy **Double Jump** with the boss's Valor, reach the **lookout**:
  its chest holds the **Flamethrower**, which burns the bramble mouth of the **cave**. Each key opens the next.
  **[Ben]** (The study's "first Hard clear" was not taken.)
- **The frost weapon: "one of any ice or frost weapon"**, the kind left to the lead. **Lead: melee**, a frost
  hammer whose swings freeze the water in front of the player (freeze your way across). It takes the melee
  slot, so it and the Flamethrower can be carried together.
- **Built now, found later.** The frost weapon and the frozen creek are built and testable in Studio through a
  lever; in the game the weapon stays locked until the Castle, so the creek is the first reason to come back.
  **[Ben]**
- **The cave is a shortcut on later runs.** A hidden path through the cave skips ahead to Main Camp; once the
  player has found it, it stays open on their later runs. No new level. **[Ben]** (The study's "the cache opens
  the Raider Arena" was not taken.)

Lead rulings (from the study's §8): bought abilities, opened secrets, owned weapon families and found
shortcuts are **saved** (one add-only profile step, v7); stars stay in session memory. Keys are checked on the
server where a reward is given, per player (a cheater can double-jump on the client; he gains nothing). A
per-player jump rise (18 without double jump, 30 with it) for the ground-aim height rule. No movement
anti-cheat. The cache becomes a roofed cave behind a bramble mouth. Water becomes deep (a fall gets the free
rescue) and the pond grows so the island shrine is out of reach without ice. Double Jump costs **10 Valor**
(one Normal clear), bought from an **Abilities panel in the lobby** (later the Armory's second tab). Waves:
W1 the bought double jump and the lookout (with the Flamethrower in its chest and the lobby loadout picker);
W2 fire, the cave and the shortcut; W3 ice, the frost hammer and the creek. Each wave is playable alone.

**W2 decisions (2026-10-18, click questions with plans):** the cave is the **Pickets bypass** — its bramble
mouth under the lookout, a roofed tunnel behind a ridge past camp A with the Raiders' Cache in an alcove, out
onto the road into Main Camp; once found, later runs skip the Pickets (~25 s on Normal, ~5% of the pay given
up) **[Ben]**. The lobby weapon choice is kept **for this visit** only; L3 designs the saved loadout **[Ben]**.
The 6-stud gap at the road's U-bend that players could hop is **closed now** **[Ben]**.

**W3 decisions (2026-10-19, click questions with plans):** the frost hammer freezes **a patch per swing** (freeze
your way across), the ice **lasts the whole run**, and the water is **the creek into a pond** with the island shrine
in the pond, ~100 studs from any ground **[Ben]**. The water becomes deep (a fall comes back to the road by the
creek). The shrine pays the most of the three chests.

## 23. L2 closed (2026-10-20)

After playing the L1c clearing and L2 Waves 1–3 in Studio, Ben: *"okey, i tested everything and it felt really
good"*. Studio's log shows one session of about 6½ minutes on the rebuilt `proving.rbxl` (a Forest Road Normal clear,
then a second run; no script error; crowd step p95 under 0.6 ms). **L1c and L2 are closed on his word.** **[Ben]** His
answers to the waves' click questions were this one line, read as "about right" for the one-jump first run, the
Flamethrower, the tunnel's trade, the frost crossing and the three chests' pay. Next: L3, the Armory (per-weapon
tiers, the upgrade loop with Forest drops, the new screen, weapon models), only on his word.

## 24. L3 "the Armory": decisions (2026-10-20)

Ben: *"we are starting L3"*, then mid-turn *"we are not starting every weapon with tier 1 nor ending every weapon to
tier 20"* (recorded in §10). Two groundwork studies (`docs/prompts/l3-study-report-systems.md`,
`l3-study-report-screen.md`), then click questions with sketches; he took the lead's recommendation on all eight:

- **The windows, as drawn** (systems report §2.3): Broadsword and Longbow 1–12, Flamethrower 2–8 (the lookout),
  Warhammer 3–16 (the Forest's first Hard clear), Frost Hammer 5–12, Greataxe 6–18, Splitbow 8–8 (a relic), Spear 9–20,
  Shotgun 9–16, Piercing Rifle 11–18, Launcher 13–20, SMG 14–20, Beam 16–20, Chain Gun 17–20, Spinblade 20–20 (a relic).
  Five bands of four tiers, one per level; a band's top tier also needs that level's Hard star (the trophy). **[Ben]**
- **Three Forest runs take one weapon from tier 1 to tier 4** (Timber 100 / 250 / 500 for T2 / T3 / T4; both starters
  in about 31 minutes; the first clear buys T2 for both). **[Ben]**
- **The city's income no longer gates tiers.** Levels and their drops do; the city keeps a level's cash and 100%
  offline income while the player is in the dungeon. **[Ben]** This answers §11.1.
- **Brutal Forest waits for Castle gear** (recommended T5, tuning unchanged). **[Ben]**
- **The screen: A, "Showcase"** (the L0 order: the big turning weapon, its details and the shelf on one screen), the
  **tier track as the full ladder of 20 with the weapon's window lit**, **all 15 models with one look each** (looks that
  grow with the tier can follow later as content only), **dressed by the level where each weapon is found** (Forest wood,
  bone, rope, flint; Castle steel, crests, gold; Underworld black iron, embers; Planet alloy, glow strips; Dream crystal,
  pastels). **[Ben]**

Lead rulings told to Ben the same day (he may overrule): tier 1 is the 2/2 he has always played (no one has played a
fresh 0/0 profile); live players' Timber spent on tiers is refunded when their profile converts (§11.3); other players
see your weapons (the one in use in the right hand, the other on the back); the loadout is saved and changes in the
lobby or the city, never inside a fight.

**The weapon models (2026-10-20):** Ben approved the Broadsword and Longbow prototypes ("Yes, build the other 13"), then
**all 15 models** on the overview (`assets/testfit/out/Weapons/_overview.png`): one look each, dressed by the level where
each is found. They are uploaded with their 15 shelf icons at the start of Wave 2 (one harvest paste). **[Ben]**
Lead rulings after the Wave 1 measure: Hard pays ×2 (×2.5 made the climb faster than his "three runs a weapon"); the
lookout perches that out-earn on Hard join Normal's "fix in L4" known limit.

**Wave 2 started (2026-10-20):** after the W1 merge Ben said *"lets do wave 2, i will test later"*. W2 puts the 15 models
in the game (the turning stage, the shelf icons, weapons in hand that other players see), with one harvest paste; his
Studio look covers W1 and W2 together. **[Ben]**

## 25. L3 closed (2026-10-21)

After the W2 merge and his harvest paste, Ben played and said *"everything feels good, lets close it"*. Studio's log
shows one session of about 49 minutes on the rebuilt `proving.rbxl` with three Forest Road runs on Normal and no script
error. **L3 (the Armory: tier windows per weapon, the upgrade loop with Forest Timber, the saved loadout and stars, the
Armory screen in both places, the 15 weapon models in hand and on the stage) is closed on his word.** **[Ben]** His line is
read as "about right" for the checklists' click questions (T2 a step, three runs a weapon, the screen, the turning
weapon, the weapons in hand and on the back, the icons). Next: L4 (the real forest, the Camp Chief, the map in the hub,
rewards balanced; the first version that may be published), only on his word.
