# Image-generator prompts: Era City Tycoon thumbnails and icon

Prompts for an image model (Midjourney, GPT Image, Ideogram, Flux, Imagen). They describe the
game as it actually looks, taken from the Blender test-fit renders in `assets/testfit/out/`,
so the results stay honest to Roblox's "metadata must match the game" rule. Specs and upload
order are in `docs/DISCOVERY_CHECKLIST.md` §1–§3.

## How the game really looks (paste this block into every prompt)

> Low-poly 3D game art in the Kenney asset-kit style: flat-shaded geometry, no textures except
> simple colour blocks, soft ambient occlusion, crisp clean edges, toy-like proportions where a
> storey is short and buildings sit on small square lots. Bright, saturated but not neon
> colours. Isometric three-quarter camera from slightly above, 35 mm lens feel, soft warm key
> light from the upper left, pale blue sky, gentle shadows, no fog, no particles, no people.
> Everything sits on a flat plot of clean green grass. Roblox tycoon game screenshot look,
> not a photograph, not painterly.

Era palettes, from the shipped kits:

- **Village** (fantasy-town kit): sand and cream plaster walls, terracotta and orange-brown
  timber trim, cobalt-blue conical tower roofs on the castle, some green thatch, a stone well,
  windmill, chapel, tavern, market stalls, oak trees, wooden carts. Paths are narrow meandering
  dirt trails, warm brown with bold pale pebbles (roughly RGB 126, 99, 66), not cobbles.
- **Boomtown** (city-kit suburban + industrial): white and light-grey houses with bright green
  roofs, dark charcoal industrial blocks with rooftop vents, yellow accents (school bus,
  cranes, signs), red fire hydrants, neon diner sign, gas station canopy, a tall clock tower
  with green roof, a lattice radio mast, a fire station. Straight dark asphalt roads
  (RGB 72, 74, 82) in a grid, white streetlamps, small low-poly cars. Buildings are low and
  wide; only the clock tower, radio mast and fire station are tall.
- **Metropolis** (city-kit commercial, not built yet, use sparingly): glass-and-concrete
  office towers and skyscrapers in the same flat low-poly style, same palette family.
- **Orbital Colony** (space kit, not built yet, use sparingly): white and orange modular
  habitat domes, corridors, a launch tower and rocket, on grey regolith.

Growth is the core mechanic: a building starts as a small shack on its lot and gains storeys,
extensions, rooftop clutter and props through five stages. Every thumbnail should show that
things are built up, never a sad empty lot.

## Generator settings

| Model | Settings |
|---|---|
| Midjourney | `--ar 16:9 --style raw --stylize 100 --no people, text, watermark, photo, blur` ; icon `--ar 1:1` |
| GPT Image / DALL·E | ask for 1792×1024 landscape, "flat low-poly render, no text" (add text later) |
| Ideogram / Flux | the only ones that render short text reliably; keep to 2–3 words, otherwise add text after |
| Imagen | landscape 16:9, "3D render, low poly, isometric, game art" |

Generate at the largest size, upscale to 1920×1080, keep under 3 MB PNG. Keep the bottom 15%
free of anything important (Roblox overlays the title there). Add any text in an editor after
generation unless the model renders text well; text must be four words or fewer, one typeface
across the whole set.

## Thumbnail 1 — growth

> [style block] Split composition, same square lot on the left and right separated by a thin
> vertical gap. Left: a tiny one-room wooden shack with a single sapling on a green lot, stage
> one. Right: the same lot fully built into a tall three-storey white Boomtown bank with a
> green roof, rooftop vents, an awning, street lamps and two parked low-poly cars, stage five.
> A small gold coin icon floats above the built one. Feeling of before-and-after progress.

Text to add: `LEVEL UP YOUR CITY`

## Thumbnail 2 — eras

> [style block] Wide shot of two adjacent square city plots on green grass, divided by a thin
> asphalt road. Left plot: a medieval village in sand plaster and terracotta trim with a
> cobalt-roofed castle keep at the back, a windmill, chapel, tavern, market stalls, oak trees,
> winding brown dirt trails. Right plot: a 1950s American boomtown with white green-roofed
> houses, a charcoal factory with a smokestack, a diner with a neon sign, a tall clock tower,
> straight asphalt roads, streetlamps and small cars. Both plots at full build-out, clearly
> the same art style.

Text to add: `VILLAGE  →  BOOMTOWN` or `4 ERAS TO CONQUER`

## Thumbnail 3 — scale

> [style block] High wide shot, 24 mm feel, of one complete Boomtown plot at full build-out:
> a dense grid of about twenty low, wide buildings in white, light grey and charcoal with
> green roofs, a bowling alley, motel, gas station, car dealership, department store, a red
> fire station, a green-roofed clock tower and a lattice radio mast as the only tall shapes.
> Straight dark asphalt roads with white lamps, small yellow school bus, a few low-poly cars,
> a rooftop billboard, round trees along the streets. Busy, prosperous, orderly.

Text to add: `BUILD YOUR EMPIRE`

## Thumbnail 4 — social

> [style block, but allow two characters] Two blocky Roblox-style avatars standing together on
> a Village plot in front of a sand-and-terracotta tavern with a cobalt-blue roof, one avatar
> pointing at a building under construction, a floating green "+" upgrade icon above it.
> Oak trees, a stone well and a winding pebble dirt trail behind them. Friendly, cooperative
> mood, bright noon light.

Text to add: `PLAY WITH FRIENDS`

## Thumbnail 5 — combat (only after the Expeditions place exists)

> [style block, but allow characters] Two blocky Roblox-style avatars, one with a low-poly
> sword and one with a low-poly rifle, facing three simple low-poly enemy robots on a grey
> flat arena at the edge of a Boomtown city, buildings and a clock tower in the background.
> Clean readable action pose, no gore, no blood, no dark horror mood, bright daylight.

Text to add: `EXPEDITIONS`

## Icon (512×512)

> [style block] Centered single low-poly Boomtown clock tower with a bright green roof and a
> white clock face, a small white house at its base, on a tiny square of green grass, against
> a flat saturated sky-blue background with a soft radial glow behind the tower. Bold
> silhouette, no other objects, no text, square composition with generous margin so it reads
> at 64 pixels.

Alternative subject: the Village castle keep with cobalt-blue conical roofs on sand-coloured
walls, same framing.

## Rules the images must respect

- Only things the game has: no dragons, no roller coasters, no realistic cities, no weather
  effects, no UI mock-ups, no coins raining. Roblox demotes mismatched metadata.
- Do not copy another tycoon's icon layout or colour scheme; duplicates are demoted.
- No prices, "free", "Robux", "giveaway", arrows pointing at fake buttons, or fake UI.
- Keep every generated image in the same light and sky so the set reads as one game.
- Generate 3–4 variants of each, pick per `docs/DISCOVERY_CHECKLIST.md` §2 and let thumbnail
  personalization choose the winner.
