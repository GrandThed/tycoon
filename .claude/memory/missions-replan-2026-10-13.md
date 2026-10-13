---
name: missions-replan-2026-10-13
description: Ben restarted the plan for the mission layer on 2026-10-13 (levels as camps along a path, a path map, secrets, bought abilities, per-weapon tiers); the fighting is kept; plan in docs/MISSIONS_DESIGN.md
metadata:
  type: project
---

On 2026-10-13, after P5 Wave 1 and its Opus review were merged, Ben said: "what we have until now looks
great, but i would like to start over with the plans for the missions themself". The fighting (weapons,
enemies, bosses, health) is kept; the mission layer is re-planned. **P5 Waves 2 to 4 are suspended.** The
draft plan is `docs/MISSIONS_DESIGN.md` (not approved as a whole yet; marks [Ben] / [proposed] / [open]).

**What he asked for, in his words:** a "tree like ui, candy crush style menu, where you select the missions in
a path"; "metroidvania style secrets and progression"; "more linear levels where the player itself select the
dificulty of the level with a boss at the end, and different dificulty rewards"; "buyable abilities for the
player, like double jump, fly as a really advance feature, a way breack ice with a flamethrower or freeze
wather with ice weapons"; "a more contemplative armory ui ... 20 tiers for weapons, where you can upgrade
your weapons so they are usable even when you progress ... not all unlocking at tier 1 ... some startign at
top tier and staying there"; "plan here at least 5 missions, and a focus on replaying those missions when you
unlock gear". His example: "the forrest level with a path and a camp with enemies, like a really big camp
along the path and an improvice tent with a big boss".

**Ben's rulings (click questions, 2026-10-13):**
- **Camps along a path:** fights inside flat camps whose gates close; the path between is for exploring and
  secrets. (Forced by the crowd tech: enemies stand on one flat floor and ignore geometry.)
- **Elements come from the weapon you bring:** Flamethrower and a frost weapon are new families (15 in all).
- **Tiers are per weapon, 20 of them, each weapon with a start tier.** Reverses "the tier belongs to the
  slot" (2026-09-28).
- **Five levels, five themes, in order: forest, castle, "something like hell", another planet, "some kind of
  dreamy place". "lets do just the first one for now"**: only the forest is planned in detail and built.
  The themes are his own answer (the lead had offered "all five in a forest world" or "spread over the eras").

**Second round (same day, click questions):** solo, **a down ends the run** (the lead proposed tries from the
last checkpoint; he kept his 2026-10-12 rule, checkpoints still bank rewards); **double jump is the first
cheap purchase**; **flight = glide first, then a jetpack with fuel**, off inside a live camp; **the map is
its own path** (a level opens when the previous one is cleared; not tied to the city's eras, against the
lead's recommendation). Consequence still open: whether city income keeps gating weapon tiers (the lead
proposes dropping it).

**Lead's proposals in the doc, not yet ruled on:** the ten-wave Village arena stays as a bonus node; stars per
difficulty (Normal / Hard / Brutal, Overdrive above); secrets visible before reachable, about three per level,
some are a second exit that opens a side node; abilities paid with Valor; five bands of four tiers, one band
per level, the band's last tier needs the boss trophy from Hard; the Armory is a screen with a 3D weapon, not
a room; work order L0 pictures, L1 Forest Road in grey, L2 secrets and keys, L3 Armory, L4 real forest and
map, L5 co-op.

**Facts checked:** local kits include `nature-kit`, `castle-kit`, `space-kit`, `space-station-kit`,
`fantasy-town-kit`, `retro-fantasy-kit`, `tower-kit`; nothing for a hell or a dream theme (generated). Today's
Armory is 12 tiers per slot in four bands of three (costs 10 / 60 / 180 of the band's material, gated by the
city's income per second). A hell theme may touch Roblox's maturity label: check before that level, and say
it plainly first (the lesson of the EditableMesh gate).

**Why:** a fresh session would otherwise continue P5 Wave 2 (the slot-tier Armory picker) or build the other
three eras' ten-wave missions, both of which are dead.

**How to apply:** read `docs/MISSIONS_DESIGN.md` first; ask Ben with previews; pictures before contracts, as
for every city layout. See [[p5-missions-2026-10-12]], [[feel-pass-2026-09-23]], [[combat-2026-09-17]].

**L0 pictures (2026-10-13):** a clickable mock page of the map, Forest Road from above and the Armory:
https://claude.ai/artifact/9iGAoSonw48U8VpV17MTA4 (private to Ben; source kept in
`assets/research/2026-10-13-missions/expeditions-mockups.html`, gitignored). Three asks are on the page and
unanswered: one map screen or one per theme; one big camp in three parts or separate camps; the Armory as a
screen or a walk-in room. In the mock the Flamethrower is the first Hard clear of Forest Road and the frost
weapon is found in the Castle, so the forest's ice secret is the first reason to return from a later level.
Pillow is not installed, so the old PNG sheet tools cannot run: an HTML page was the way to show pictures.

**Third round (2026-10-13, after the pictures):** "1. yes" (one map screen for all five levels), "2. looks
good" (one big camp in three parts), "3. a screen in both experiences" (the Armory is a screen, in the city
and in the dungeon place), and a new requirement: **"make all the dungeos in one roblox place and teleport
the player to the destination inside the place"**. Asked with previews, he then chose: **after a level you
stay in the dungeon place** (a lobby camp with the map and the Armory; Return goes to the city), **one party
per server**, and **"Yes, start"** for L1, with the P5 merge rule (each step that passes review and QA is
merged to `main`). "Experiences" is his word for the two places.

**L1 "Forest Road in grey" started 2026-10-13** on branch `l1-forest-road` (worktree folder
`C:/Users/benja/Desktop/tycoon-p5`, reused; the merged branch `p5-missions` is deleted). Lead rulings for
L1: level progress (stars) lives in server memory for the session, no profile schema change until the Armory
step designs the whole shape once; the hub is untouched (its Depart lands in the dungeon lobby and the
ticket's mission is ignored for choosing); the stand-in boss is the Colossus; the ten-wave Village arena
becomes a node on the map; secret sites are marked blocks that do nothing yet; double jump stays free in L1
but the main path must be passable with one jump and the dash.
