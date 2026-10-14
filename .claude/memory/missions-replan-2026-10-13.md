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

**L1 state, 2026-10-13 22:00.** Contract: INTERFACES "# L1 contracts — Forest Road in grey" (on the branch).
Built by four owners and committed on `l1-forest-road` (fc43816): the lobby camp, `StageFlow` (pure stage
rules), `LevelService` / `LevelGeometry` / `BarrierGroups`, the map screen (`src/client/UI/MapScreen.luau`),
Forest Road's layout and balance, `tools/check_levels.py`. Reviewed by four Opus reviewers in slices (the
run, the world, the client, the data and tests): **0 Critical, 9 Major, 44 Minor**. The whole fix list with
the lead's rulings is `docs/prompts/l1-fix-round.md` on the branch. The fix round was cut off by the
session limit minutes after it started; fresh agents continue from that file. **Nothing of L1 is on
`main`.** Rulings of the round: a camp triggers on its whole fenced rectangle; the invisible wall's inner
face is the floor's edge; cover in a camp is at most 3.5 studs (a taller block is a perch the boss cannot
hit); Abandon's key is Backspace twice; a skip pays nothing; everyone is healed in the lobby; the G presets
are 2/1, 4/4, 6/6; a third simulated player with a human reaction becomes the gate for Hard and Brutal
(the ideal one clears Hard at 2/1 in 16 minutes without a hit).

**L1 merged to `main` on 2026-10-14** (merge 736a98a; branch at ee6d9f7), the six place files rebuilt; waiting
on Ben's Studio playtest (PLAYTEST "L1 — Forest Road in grey", nine key-only steps; Abandon is Backspace twice).
The fix round: all four parts done by FRESH agents from `docs/prompts/l1-fix-round.md`; a check of the fix diff
found 0 Critical, 0 Major, 6 Minor, all fixed (the camera turned on the close's short nudge; the grace moved
players who were inside; a downed body re-armed a camp forever; the last clear pulled waiting members into the
level; the harness could read green from another checkout; `rearm` missing from the tests' list). Additions the
lead made during the round: the server tells the client when it moves a body (`Placed` / `PlacedSeq` on the
character) and the client turns the view only on a far move; at the end of a run nobody is put into the level;
the slinger swarm the designer added to make the human gate go down was reverted and the gate relaxed (one preset
below: down OR x1.8 the time on Hard, x1.4 on Brutal, the Colossus alone 135 s / 180 s). Gates at the merge:
harness 1,292 checks (its verdict line names the count and the folder), 417 mutations, `check_levels.py` 123,
`check_stage_mirror.py` about 5,600 comparisons of the real StageFlow / Combat / LevelGeometry against the
simulators, sims green. The publish freeze holds until L4. Next: Ben's look, then L2 (secrets, keys, bought
double jump) only on his word; the carried list with owners is PLAN "L1".

**Ben's verdict on L1, 2026-10-14** (a real Studio look: Studio's log shows the rebuilt `proving.rbxl`, one
Forest Road run on Normal, ended "down" in camp A about two minutes after boot; nothing past camp A was seen).
"looks good! [...] i was hopping for the enemies to already be there all the time, with bigger camp sites, and
longer roads [...] something i really didnt like is the fact that you are closed off from leaving when entering a
zone, i was ambisioning that the only zone that remainds closed is the final room with the boss so you cannot leave
the level nor the boss zone. [...] everything else was allright from a technical demo standpoing". So: resident
enemies, open camps, only the boss room locks, bigger camps, longer roads. It reverses his own 2026-10-13 ruling
"gates close until the camp is clear" (which the lead had recommended because the crowd has one floor per server
and because closed camps stop kiting). Next step **L1b "the living road"**, in a NEW session from
`docs/prompts/l1b-living-road.md` (study first: several live camps need a floor per body or group, a resting and
leashed brain, dormant far bodies, a codec range for longer roads; then his six decisions; then contracts).
Asked afterwards about going down in camp A, he said "balance feels good": L1's numbers are the starting point for L1b. Lesson: he judged the camp mechanic within two minutes of play, so a mock of how a camp BEHAVES (not only how the
level looks from above) would have caught this before the build: offer one for L1b.

**L1b decisions, 2026-10-14 (new session; Ben chose "decisions first", before the study):** recorded in
MISSIONS_DESIGN §16. Raiders chase to the camp edge, go home and heal; at rest all three mixed (guards,
patrols, fires; as foreseen, offered alternatives he took all); sneaking past allowed; **rewards per kill,
kept at once** (his own words "by the amount killed by the party, disregarding clearing status": L1's
"only a checkpoint pays" is dead); camps never refill; three camps twice L1's size on a ~1,000-stud road,
~10 min. Merge rule holds for L1b. Work on branch `l1b-living-road` in `tycoon-p5`; the study brief is
`docs/prompts/l1b-study.md`, its report `docs/prompts/l1b-study-report.md`.
