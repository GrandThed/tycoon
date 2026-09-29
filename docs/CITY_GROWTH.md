# Growing city (M12, approved)

Status: **approved 2026-09-29.** This document is the plan of record for milestone
**M12 — Growing city** (M11 is the unmerged feature-unlocks milestone on branch `m11-unlocks`).
The contracts are in `docs/INTERFACES.md` "M12 contracts".

Ben's answers (2026-09-29): **go with growth layouts (mock B)**, and **Village gets the organic
street plan**, shown to him as renders before anything is built.

## Why this document exists

Ben (2026-09-28): improve the city grid so it feels **alive and like a growing city, not a grid
being filled**. New models, or all-new models, are fine. **The core gameplay stays.**

### Why today's plots read as a grid being filled

Renders of today's plots are in `assets/testfit/out/<Era>/`: `growth_today_tier2.png` and
`growth_today_full.png` for every era, and for Village also tier 1 and tier 3, next to the
proposal in `growthmockB_compare.png`. Six causes, in order of how much they hurt:

1. **An empty board.** Every era starts as one flat, tinted square with a hard edge, sitting on a
   default grey baseplate that fills the whole map between the plots. Nothing lives on the plot
   until you buy something, and at tier 2 most of it is still bare.
2. **Visible sockets.** Future building sites show before they are built. A Metropolis block slab
   is paved as soon as *any* slot on it is owned, so buying City Hall paves a 40×44 square whose
   other six buildings mostly arrive at tier 5; Orbital decking works the same way, and park
   strips mark every future street from tier 0. Boomtown's storefronts stand in evenly spaced
   pairs down Main Street. The player sees the form they are filling in.
3. **Isolated buildings.** Each purchase is one building alone in a 9×9 cell with bare ground
   around it. There is no street frontage, no neighbour, no yard.
4. **A sweep, not a spread.** Metropolis and Orbital fill their 4×4 lattice row by row from the
   front. Village jumps between the west campsite and the east farms.
5. **A sprinkle of filler.** Filler lots (8 to 21 per era) appear at fixed spots by tier, whatever
   was bought, and never change. Every prop pops in with no animation.
6. **Nothing reacts.** Buying or levelling a building changes that building and its path only, and
   only the owner sees the building's rise tween; everyone else sees it pop in.

(The offline renderer used to draw a pale pad in front of every *owned* building, which the game
does not: the game destroys a pad once its slot is bought. `tools/testfit/plotrender.py` is fixed
and now draws only the pads the game shows, and every `growth_today_*` render uses the fix.)

## 1. The idea

**You build the landmarks. The city grows around them.**

The 24 slots per era stay exactly what they are: the landmarks the player buys and levels. Around
them, a **city fabric** of ordinary houses, shops, workshops and fields grows by itself, the way a
zoned city grows in SimCity. The land starts wild, each purchase sets off building work nearby,
and the town spreads, thickens and pushes the wild back as the era goes on.

### Pillars

Every decision is checked against these. In a conflict, the earlier one wins.

1. **Core gameplay is untouched.** Same slots, order, prices, income, levels, milestones, pads,
   Build panel, Advance Era and Rebirth. What changes is where the landmarks stand (new layouts,
   §2.5) and everything the client draws around them, like today's city dressing.
2. **One town, growing from its heart.** The first purchases stand at the entrance and each later
   one extends the town along its streets, so the town spreads instead of filling a grid.
3. **The land is alive before you build.** Each era starts on its own wild land, not an empty
   board. Building pushes the wild back.
4. **Every purchase makes a ripple.** Buying or levelling a landmark starts construction on the
   lots around it: stakes and scaffolding first, then a house, then a bigger one.
5. **Dense heart, ragged edge.** The oldest part of town is the densest; the edge is building
   sites and wild land. You can always see where the city is growing.
6. **No sockets.** Nothing marks a future building site except the one pad you can buy next.
7. **Landmarks stay the stars.** Filler is lower and plainer than the landmarks near it and never
   copies a landmark's silhouette. The player finds their own buildings at a glance.

## 2. How it works

### 2.1 Wild land (level 0)

Each era gets a wild layer that covers the plot from the start and is cleared wherever the town
spreads: under landmarks and their yards, along drawn streets, and on developed lots.

| Era | Wild land | What replaces it |
|---|---|---|
| Village | Woods and meadow: trees, bushes, rocks, wildflowers | Cottages, gardens, fields, lanes |
| Boomtown | Prairie farmland: crop fields, fences, hay bales, a barn and silo, dirt tracks | Main Street shops, suburbs, yards |
| Metropolis | The old town: surface car parks, fenced vacant lots, old low brick buildings, billboards | Mid-rises and towers, redeveloped block by block |
| Orbital Colony | Raw regolith: craters, boulders, dust, survey beacons | Decking, modules, domes |

Today's Village tree zones become the woods and Orbital's rock zones become the regolith, so the
wild layer grows out of what already exists.

**Past the edge.** The map between plots is a grey baseplate. Each plot has free ground in its own
wedge of the ring: at least 58 studs behind it and 10 to 47 studs at each side (only 20 studs
separate neighbours at the front corners). The wild layer continues into that band, so a plot sits
in a landscape instead of on a board, and seen from the hub the ring of plots reads as ten towns in
the countryside. Far plots show the band as a few large merged clumps, which are cheap. (These
numbers are for today's 10-plot ring. The unmerged M11 moves the hub to 6 plots, 60° apart,
which only gives each plot more room.)

### 2.2 Parcels: the city fabric

- Each era gets **parcels**: lots that front a street, in a few sizes per era (6×6 and 8×8 studs
  in the Village mock, plus narrow 4-stud tower lots in Metropolis). A tool generates them from
  the street plan and the slot footprints and checks them like `tools/streetplan.py` checks
  streets today.
- A parcel can develop only once its street is drawn. Streets already grow with your buildings,
  so the fabric follows the roads you open.
- Each parcel has a **development level**:

  | Level | Looks like |
  |---|---|
  | 0 | Wild land |
  | 1 | Building site: stakes, fencing, scaffolding, materials |
  | 2 | Small building (a cottage, a bungalow, a low shop, a pod) |
  | 3 | Medium building |
  | 4 | Large building (the dense heart only) |

- The level comes from how much **pull** the nearby landmarks have: owned landmarks close to the
  parcel pull hardest, a landmark's pull grows with its milestone stage, and the plot's growth tier
  adds a little everywhere. So levelling up the tavern thickens the lanes around the tavern.
- **Districts.** Each landmark has a district tag (home, shop, craft, farm, civic and so on). A
  parcel grows the kind of building its strongest neighbour calls for: houses around the
  cottages, workshops by the smithy, fields around the farm, booths by the market. Neighbourhoods
  get a character instead of a random sprinkle.
- The level is a pure function of the owned slots, their stages and the growth tier, so every
  client sees the same town, nothing is saved, and the offline renderer can mirror it exactly.

### 2.3 The ripple: construction you can watch

- **Buying a landmark:** its site is staked and scaffolded, the building rises out of it with
  dust, and then nearby parcels start their own building work one after another, spreading out
  from it.
- **Construction takes a little while.** A site stands for a short, tunable time (on the order of
  10 to 30 seconds, staggered) before its building appears. Early purchases come every 30 to 90
  seconds, so during active play something is almost always being finished somewhere. This is
  local animation only: the end state is fixed, and a player who joins later simply sees the
  finished town.
- **A milestone** (levels 10, 25, 50, 100) wraps the landmark in scaffolding for a moment as its
  stage swaps, and the lots around it move up a level.
- **The frontier always has sites.** Level 1 is a real state, not only a transition, so the edge of
  town always shows work in progress: timber scaffolds in Village, wood framing and a cement mixer
  in Boomtown, **tower cranes on the Metropolis skyline**, robot gantries in Orbital. Cranes can
  slowly swing, and a worker figure can stand on a site, from the existing people kit.
- Income is not delayed by any of this. The server has already completed the purchase.

### 2.4 No sockets

- Only the pad you can buy next shows, as today. Its building site is staked out with string lines,
  so the next goal reads as "a plot about to be built", not an empty square.
- The pad itself is an unstyled default-grey Part today (nothing restyles it). The client dresses
  it per era as a plot marker: a wooden notice board in Village, a "LOT FOR SALE" sign in
  Boomtown, site hoarding in Metropolis, a landing beacon in Orbital. The server pad, its
  touch-to-buy and its name-and-price label stay exactly as they are.
- Paving, decking and yards appear **with development**, parcel by parcel, instead of covering the
  whole lattice from the start.

### 2.5 Growth layouts: the layout has to be built for growth

Two Village mocks settled this (renders in `assets/testfit/out/Village/`, compared side by side in
`growthmockB_compare.png`).

**Mock A kept today's layout. It looked better, but it did not grow.** Only 9% of the street-side
spots can take even a 6×6 lot, because landmarks, pads and junctions already use the frontage, so
the fabric could only fill leftover pockets. Growth started as two patches: the farm, the 4th
purchase, sits across the plot from the campsite. And nearly the whole trail network was drawn at
tier 1.

**Mock B relaid Village for growth, and it grew:**

- **One heart at the entrance.** Slots sit along the streets in purchase order: slot k is roughly
  k-th in distance from the entrance along the streets. At every tier the owned slots form one
  settlement that spreads outward, and at tier 1 only the first stretch of high street is drawn.
- **Frontage reserved.** Landmarks alternate with 1 to 3 lots on both sides of every street, so
  houses line the streets: 35 of 46 lots front a street, against 11 of 43 in mock A.
- **Pull along the streets.** Distance is measured along the drawn streets, not in a straight line,
  and a lot develops only next to an owned landmark or an already-built lot, so the town grows as
  one piece.
- **Filler never outgrows its landmark.** A lot's building may not be taller than the landmark
  pulling it, at that landmark's current stage, so the player's buildings stay on top.

So each era gets a **new layout designed for growth**, with the same slots, order and models.
Slot positions are not saved in player data, so nothing migrates. The costs:

- Village and Boomtown re-bake their paths, with one harvest paste each.
- Metropolis and Orbital first need a layout study, because each of their lattice blocks holds
  exactly one landmark. Their 16 block slots were fixed by the wave 2a contract; that rule gives
  way to this one.

### 2.6 Phones and performance

- Every parcel building, site and wild prop is one merged mesh, like today's props. Identical
  meshes are instanced by Roblox, so twenty copies of a cottage cost little more than one.
- Near plots show everything. Far plots keep developed parcels (they are the city's silhouette)
  and drop wild props, building-site details, yards and people.
- The parcel count replaces today's filler lots, and the wild layer replaces today's tree zones,
  so the new near-plot budget grows by a modest amount (numbers in §5). The frame-time target for
  moving things (cars, walkers, birds, cranes) stays under 0.3 ms, and Ben measures it in Studio.
- Players walk through filler buildings, as through every dressing part today (Ben's no-collision
  rule), so no lot can ever block a pad.

## 3. Per era

### Village: a village carved out of the woods

- **Wild:** woods over most of the plot, kept low and sparse near the front so the camera always
  sees the next pad, with a clearing at the entrance where the campsite starts.
- **Growth:** the campsite just inside the entrance is the seed. A high street runs from it to the
  castle keep at the far end, and the square with the well, fountain, market and tavern sits
  halfway along it. The farm stands at the edge of the heart, and its fields grow out along a farm
  lane. Woods cover everything else at the start and pull back as the village spreads.
- **Districts:** camp (tents, fire pits, log piles), home (cottage → timber house → two-storey
  house), craft (woodpile, shed, kiln, sawpit), farm (furrowed fields, fences, haystacks, a
  barn), market (booths, carts, awnings), civic (greens, benches).
- **Sites:** stakes and string, a timber scaffold, stacks of planks and logs.
- **Mock (2026-09-28):**
  - `growthmockB_compare.png` shows today, mock A and mock B at tier 1, tier 3 and full;
    `growthmockB_full_entrance.png` looks up the high street at the keep.
  - For speed, B was laid out as straight streets, and from above it reads a little like a grid.
    The real Village plan keeps B's growth rules but gives the streets an organic shape (a curving
    high street, a green, lanes at angles), drawn as meandering baked trails like today.
  - The stand-ins repeat a few cottages. The real models are about 20 to 26 new props: filler per
    district, fields, stalls, building sites and forest clumps.
  - The mock code and its scratch layout are kept in `assets/research/2026-09-28-growthmock/`.

### Boomtown: a crossroads that becomes a town

- **Wild:** prairie farmland: fields in rows, fences, hay bales, a barn and silo, telegraph poles.
- **Growth:** Main Street's mouth by the entrance is the seed. Small shops fill the gaps between
  the storefront landmarks until Main Street is one continuous frontage, suburbs spread down the
  side streets, sheds and tanks gather by the service lanes, and the farms retreat to the corners.
- **Layout:** relaid like Village's, with storefront landmarks spaced along Main Street so shop lots
  fit between them, and dead-end side streets for the suburbs (the plan must stay a tree).
- **Districts:** main street (low shop → two-storey shop with a sign), suburb (bungalow → house
  with garage → two-storey house), industry (shed → warehouse → works with a chimney), civic
  (a small park, a church, a school yard).
- **Sites:** timber framing, a cement mixer, cones and barriers.
- The "lower, wider" ruling holds: filler stays under the landmarks' height; only landmarks go tall.

### Metropolis: downtown rising

- **Wild:** the old town: surface car parks, fenced vacant lots, old low brick buildings and
  billboards.
- **Growth:** the entrance avenue and City Hall are the seed. As landmarks go up, the old town
  around them is redeveloped: low-rise, then mid-rise, then towers that **grow floor by floor**,
  with tower cranes on the skyline. The skyline still peaks at the Skyscraper.
- **Geometry, needs its own study:** every Metropolis block holds exactly one landmark, and a
  street leaves only 2 studs of verge, so there is no room for lots beside the streets. The fabric
  has to live in the 19-stud corridors that carry no street and in the outer band inside the ring
  (low under the deck), or the blocks get bigger. Either way the layout gets its own mock before
  contracts, and the growth order changes from front-row-first to outward from the entrance
  crossroads.
- **Districts:** residential, office, retail, civic (plazas, fountains).
- **Sites:** tower cranes (a generated kit if city-kit-commercial has none), scaffolding, hoarding.
- Ben's park strips in undrawn street cells stay: they are streets not yet built.

### Orbital Colony: an outpost that becomes a colony

- **Wild:** regolith: craters, boulders, dust, survey beacons (today's Rocks zones).
- **Growth:** the landing pad by the entrance is the seed. Pods and module clusters spread along
  the tubes, decking grows under them, and domes and towers take the dense heart. The monorail
  ring stays.
- **Districts:** habitat (pod → pod cluster → dome), industry (tanks, drills, refinery), science
  (dishes, labs), port (cargo pads, crates).
- **Sites:** robot gantries, cargo crates, a lander.
- Same lattice limits as Metropolis, so it gets the same kind of layout mock first. The "decking
  under clusters" ruling becomes "decking under development".

## 4. New models

This is where the new variety comes from. Per era, roughly:

| Kind | Blueprints per era | Stages | Notes |
|---|---|---|---|
| Parcel buildings | about 12 (4 districts × 3 variants, mixed sizes) | 3 (levels 2, 3, 4) | One blueprint grows in place, like a landmark |
| Building sites | 2 or 3 (small, medium; a crane in Metropolis) | 1 | Shared by every district |
| Wild land | 3 to 6 | 1 | Village reuses its trees, Orbital its rocks |

About 20 blueprints per era, 80 in all. The routine is the one that built the landmarks (M8):
Opus builders, strips that Ben approves before anything is uploaded, then merge, upload and one
harvest paste per era. Filler never reuses a landmark's signature pieces.

Where the pieces come from (from an inventory of the kits on disk, 2026-09-28):

| Era | Parcel buildings | Building sites | Wild land |
|---|---|---|---|
| Village | fantasy-town-kit wall and roof panels; storeys stack, so a cottage can grow in place | kit broken walls, timber poles, planks, log stacks; **generated** crates, ladder, hoist, stone pile | nature-kit trees, stumps, rocks, fences and crops (already in growth stages); **generated** haystacks |
| Boomtown | **generated** porches, garages and extra storeys around suburban and industrial bodies: every unused house type is already a landmark or a filler house, and kit houses cannot grow in place (their roofs leave a lip) | **generated** scaffold, timber, cement mixer, hoarding (the roads-kit cones are under 1 stud at scale 4) | **generated** farmland (crops, hay, logs, rocks, dirt) in the City Kit palette; suburban trees and fences |
| Metropolis | **generated** modular towers (base, floors, crown) in the commercial palette, so a tower grows floor by floor; kit low-detail blocks for the far skyline | **generated** tower crane, scaffold, hoarding | **generated** old town (car parks, vacant lots, chain-link, rubble, old low-rise). It may not borrow Boomtown's kits: each kit belongs to one era |
| Orbital Colony | space-kit corridors and hangars; domes nest small → medium → large | kit gantries, platforms, barrels; **generated** jib crane, cones, crates | space-kit craters, rocks and terrain (the Rocks prop already grows in stages) |

Generated kits are the project's normal answer when a Kenney kit lacks a piece (stadium, highway,
garage, metro, tube, monorail, garden and people kits); colours are sampled from the era kit's own
colormap so the new pieces keep the era palette. The construction pieces that do exist only in the
rejected retro kits are not reused.

## 5. Budget

Per plot, today's caps (`CityDressing.json budget`) against the proposal. Every instance is one
merged mesh.

| Category | Today | Proposed | Shown on |
|---|---|---|---|
| Filler lots (with plazas and junction lamps) | 45 | parcels up to 70 (plazas and lamps as today) | near and far (far: developed parcels only) |
| Trees | 40 | wild layer up to 100 inside the plot | near only |
| Landscape band past the edge | none | up to 12 merged clumps | near and far |
| Moving extras (swinging cranes, workers) | none | up to 6 per plot, on the 3 nearest plots | near only |
| Greenery, parked cars, cars, walkers, birds | 48, 32, 32, 8, 18 per map | unchanged | as today |

A player's own plot and its two neighbours are near (neighbouring plot centres are about 171 studs
apart, inside the 250-stud near radius); the other seven are far. That adds roughly 100 instances
on each near plot and 40 on each far plot, about 570 for the whole map, most of them instanced
copies of the same few meshes.

Mock B measured the Village plot (props, then plain parts): 111 + 17 at tier 1, 138 + 51 at tier 3
and 183 + 57 fully built, against 18, 53 and 85 props today. The woods fell from 101 instances at
tier 1 to 65 fully built (merged clumps), and the 46 lots used 87 stand-in props, which one merged
prop per lot level brings to 46.

The map-wide target (about 2600 static instances) was set before the living-city waves, whose
counts were never measured, so **wave 1 starts by measuring today's count in Studio**, and the
caps above are tuned from that measurement.

## 6. Engineering sketch

- **Layouts:** a new growth layout per era (slot positions and streets with frontage), a district
  tag per slot, and wild zones. Parcels are generated by a new tool into a data file per era and
  checked like streets; `tools/streetplan.py`'s lot, greenery, parking and zone rules are rewritten
  for parcels (an 8×8 lot kind, the distance to landmark footprints).
- **`src/shared/CityFabric.luau` (new, pure):** pull, level and district per parcel. A Python mirror
  keeps `tools/streetplan.py` and `tools/testfit/plotrender.py` showing exactly what the game shows.
- **Client:** a fabric renderer (parcels, sites, wild clearing, the ripple) inside the city
  dressing controller, and the building-site reveal in the plot visuals controller.
- **Server:** nothing. Every client can already read each building's stage from the single
  `Stage<n>` model under `Building_<slotId>`, so the stage-weighted pull needs no new attribute.
  No remote, data, economy or balance change.
- **Tools:** the parcel generator and checks, the plotrender mirror, and a parcel timeline in the
  economy sim for tuning.

## 6.1 What stays exactly the same

Slots and their order, prices, income, levels and milestones, the requires chain, pads and the
Build panel, landmark models and their growth stages, Advance Era, Rebirth, Legacy, data, remotes,
monetization, the rule that streets grow with your buildings, the approved baked-path look, the
Metropolis tiles, highway and subway, the Orbital tubes and monorail, cars, walkers and birds.
The street plans themselves are redrawn with each growth layout.

## 7. Decisions for Ben

1. **Go with growth layouts (mock B)?** Recommended. Each era is relaid so the town grows from its
   heart, with the same slots, order and models. The cheaper alternative, dressing today's
   layouts (mock A), brings the woods and the building sites, but the town still fills pockets
   instead of growing.
2. **Village street shape.** Recommended: B's growth rules on an organic plan (a curving high
   street, a green, lanes at angles), shown to you as a plot render before anything is built.
   The alternative is B's straight streets as rendered.

Defaults unless Ben says otherwise (all tunable in config after the Studio playtest):

- A building site stands 10 to 30 seconds, staggered, before its building appears.
- The wild landscape continues past the plot edge.
- Village goes first; Boomtown, Metropolis and Orbital follow, each with its own mock first.
- Players keep walking through filler buildings (the no-collision rule).

## 8. Plan

**M12 — Growing city**, one era per wave. **Village first**: every player sees it first, and the
woods story shows the idea most clearly.

1. **Wave 0 (this document):** two Village mocks; Ben approves the direction and answers §7.
2. **Wave 1, Village:**
   - Measure today's instance count in Studio (the budget baseline).
   - The new Village growth layout as a plot render for Ben's approval, then the path re-bake
     (one harvest paste).
   - Contracts in `docs/INTERFACES.md`; the parcel tool; `CityFabric` and its Python mirror; the
     client fabric renderer, the ripple and the pad marker.
   - Village parcel, site and wild models: strips for Ben before upload, then one harvest paste.
   - Studio playtest.
3. **Waves 2 to 4:** Boomtown, then Metropolis, then Orbital. Each starts with its own
   growth-layout mock (Metropolis and Orbital need the lattice study), then its models and
   tuning. The code is shared.
