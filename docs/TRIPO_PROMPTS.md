# Tripo prompts — the Expeditions assets

Every asset the Expeditions place shows, as a Tripo 3D prompt in the style chosen on 2026-10-26
("low poly fantasy, some Breath of the Wild"). Generate in the order of the sections: the enemies
and their gear first, because a rigged enemy also needs `/animate` before it can be judged in Studio.

What stays generated and is **not** in this list: the level's ground, road, hills, slopes, canopy
masses and baked rock chunks (`tools/levels/forest.py` bakes them from the layout, and the walls and
collision depend on them), the weapon shelf icons (rendered from the weapon models), and the effects.

## How to prompt

**Style prefix**, at the start of every prompt (written `[prefix]` below):

```
Stylized low poly 3D game asset, Breath of the Wild inspired fantasy style, chunky readable silhouette, large flat faceted planes, hand-painted texture with soft baked gradients and ambient occlusion, muted pastel palette, matte surfaces, no photorealism, no metallic shine, no fine noisy detail, single object, centered, front view, neutral pose, plain background
```

**Negative prompt**, if the screen has the field:

```
realistic, photoreal, high detail noise, PBR chrome, glossy, cluttered, multiple objects, base platform, text
```

**Enemies** (section 1): Tripo's **Mixamo** skeleton preset, triangle topology. Every enemy prompt
already ends with the pose clause:

```
standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible, short hair and short cloth that do not cover the arms or back
```

Then run `/animate <file.glb> <role>`.

**Weapons and gear** (sections 2 and 3): a single object with no hand, lying flat, side view,
triangle topology. Weapons are never fused to a body: the game hangs every weapon from the hand.

**Props** (section 4): triangle topology, standing on its own base point (no ground plate).

**Keep each kind's cloth colour.** Players tell raiders apart in a fight by their cloth. These
colours are the game's (`ProvingGrounds.json` `color`), so keep them even if the style pulls the
palette softer:

| Kind | Cloth | Height in game |
|---|---|---|
| fodder | red-brown | 5 studs |
| slinger | yellow | 5 |
| lobber | green | 5 |
| marksman | purple | 5.4 |
| plated elite | steel blue | 6.5 |
| brute | rust | 7.5 |
| Camp Chief | dark crimson | 14 |

**Triangle targets** (Tripo's face limit). These matter because a level holds up to 160 raiders at
once:

| What | Target |
|---|---|
| fodder, slinger, lobber, marksman | about 3,000 |
| plated elite, brute | about 4,000 |
| Camp Chief | about 6,000 (the bandit test was 5,447) |
| weapon or gear piece | 1,500 to 3,000 |
| tree, tent | up to 2,000 |
| stone, clutter | 300 to 800 |

**The head rule.** The game scores a headshot on a ball at the top of each body. Horns, antlers and
crests that stick out of that ball are fine, but they don't count as head.

## 1. The raiders (one tribe)

All seven are one forest tribe in hide, fur, rope, bone, flint and war paint. They differ by gear,
size and cloth colour.

**Fodder** (role `fodder`):
```
[prefix], wiry forest raider, sleeveless tunic in red-brown cloth, cloth leg wraps, rawhide belt and bandolier, one wolf-fur pauldron, short fur cape, fang necklace, bone knife sheathed on the left hip, charcoal war-paint band across the eyes, short shaggy mane with two feathers, rawhide foot wraps, standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible, short hair and short cloth that do not cover the arms or back
```

**Slinger** (role `slinger`):
```
[prefix], lean forest raider stone slinger, sleeveless tunic and head wrap in yellow cloth, bag of stones on the left hip, bandolier of small leather pouches, rawhide belt, war paint, light upright build, standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible, short hair and short cloth that do not cover the arms or back
```

**Lobber** (role `lobber`):
```
[prefix], stocky forest raider fire thrower, green cloth scarf over nose and mouth, hide cap with ear flaps, leather apron, hide satchel of clay firepots on his back held by crossed straps, two clay pots at the belt, standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible, short hair and short cloth that do not cover the arms or back
```

**Marksman** (role `marksman`):
```
[prefix], tall lean forest raider crossbowman, long hooded coat in purple cloth split at the sides, quiver of bolts slung across the back, rawhide belt, bone toggles, war paint under the hood, standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible, coat ending above the knees, sleeves fitted
```

**Plated elite** (role `armoured`). The planks are generated separately (section 2), because the
game breaks the plate off mid-fight and the body underneath must still look whole:
```
[prefix], broad muscular forest raider warrior, steel-blue kilt and sleeves, tunic and leather harness over the chest, bare left arm, hair crest, war paint, fur boots, standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible, short hair and short cloth that do not cover the arms or back
```

**Brute** (role `brute`):
```
[prefix], huge hunched forest raider brute, bare barrel chest, rust-coloured kilt with a ragged hem and rust leg wraps, cloth sash, wolf-fur mantle on the shoulders only, rawhide belt with a bone skull buckle, fang necklace, fur boots, aurochs-skull cap with two horns, black beard, thick arms, standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible, short hair and short cloth that do not cover the arms or back
```

**Camp Chief** (role `chief`). This is the bandit test, written out; regenerate only if you want
him to match the others:
```
[prefix], tribal raider chieftain, bulky broad shoulders, bone skull mask with small horns over the face, short fur mantle on the shoulders only, dark crimson cloth kilt and sash, leather straps and bone ornaments, hair tied back and short, earthy browns and bone white with faded red war paint, standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible, short hair and short cloth that do not cover the arms or back
```

## 2. The raiders' gear

Each piece is hung from a hand (or the torso) the way player weapons are. The lit parts carry a
gameplay warning (the glowing pouch, the pot, the bolt tip), so keep them a clear, separate shape.

**The Chief's hammer.** He swings it in a wide sweep and slams it. In the game it is about 9 studs
long in his hand, so give it a boss's mass, not a player's:
```
[prefix], huge crude chieftain war hammer, massive rough stone head lashed to a thick gnarled log haft with rope in X bindings, bone spikes and an animal skull bound to the head, red ochre bands on the haft, leather-wrapped grip at the end, single weapon, no hands, lying flat, side view
```

**Fodder's club:**
```
[prefix], short one-handed wooden club with flint teeth set along the head, rope-bound leather grip, a feather tied below the head, single weapon, no hands, lying flat, side view
```

**Slinger's sling** (the stone pouch glows before he throws):
```
[prefix], leather sling with a round stone pouch in the middle and two sinew cords ending in a finger loop, small glowing amber stone in the pouch, single object, no hands, lying flat, top view
```

**Lobber's firepot** (thrown; it glows in the satchel before he throws):
```
[prefix], round fired-clay firepot with a cloth stopper tied with rope, glowing orange embers showing at the mouth, cracked clay, single object, side view
```

**Marksman's crossbow** (the bolt tip glows before he fires):
```
[prefix], heavy tribal crossbow, carved wooden stock, thick bow prod lashed on with rope, drawn sinew string, flint-headed bolt loaded with a glowing tip, single weapon, no hands, lying flat, side view
```

**Plated elite's axe:**
```
[prefix], long-hafted flint battle axe, one big knapped flint blade lashed to a wooden haft with rope, bone pommel, leather grip, single weapon, no hands, lying flat, side view
```

**Plated elite's plate** (one set: chest and back planks, two pauldrons, a forearm shield). Generate
it in one colour, because the game paints the plate itself (its health tint, the white glint on a
blocked hit, the burst when it breaks):
```
[prefix], set of wooden plank armour pieces laid out flat: a chest plate and a back plate of lashed planks bound by two rope lashings, two plank shoulder pauldrons, a small plank arm shield, all one plain light wood colour, no paint, separated pieces, top view
```

**Brute's log club** (two-handed):
```
[prefix], massive two-handed log club, thick tree trunk with rope lashings and bone spikes driven through, rough bark, worn grip, single weapon, no hands, lying flat, side view
```

## 3. The player weapons (15)

Each weapon belongs to the level where it is found, and each level has its own material family.
Keep a family's materials across its weapons.

### Forest (wood, bone, rope, flint, red ochre paint, a feather charm)

**Broadsword:**
```
[prefix], fantasy broadsword with a broad flint blade, knapped scalloped edges with pale bevels, bone crossguard, spiral leather grip bound with rope at both ends, flint pommel, red ochre war-paint band, hanging charm of fangs and an ochre feather, single weapon, no hands, lying flat, side view
```

**Longbow:**
```
[prefix], tall wooden longbow, pale wood limbs with red ochre bands, rope-bound leather grip, bone nocks at the tips, taut sinew string, hanging feather charm, single weapon, no hands, lying flat, side view
```

**Warhammer** (the player's; the Chief's hammer is in section 2):
```
[prefix], two-handed tribal warhammer, heavy flint stone head lashed with rope in an X binding to a thick wooden club haft, pale bone spikes on the head, two red ochre bands below the stone, spiral leather grip, hanging fang charm, single weapon, no hands, lying flat, side view
```

**Flamethrower.** The Forest's flamethrower is a bellows, not a tank:
```
[prefix], tribal bellows flamethrower, leather bellows between two carved wooden boards, fanged bone nozzle, clay ember pot on top heaped with glowing coals, rope lashings, bone knobs on the handles, single weapon, no hands, lying flat, side view
```

### Castle (forged steel with pale bevels, gold collars and rivets, red or blue cloth grips, heraldry)

**Greataxe:**
```
[prefix], two-handed knightly greataxe, broad crescent steel blade with a pale bevelled edge, long oak haft, gold collars and rivets, red cloth-wrapped grip, small crest shield charm on a blue ribbon, single weapon, no hands, lying flat, side view
```

**Frost Hammer:**
```
[prefix], knightly frost war hammer, faceted pale blue ice crystal head bound with steel and gold bands, octagonal steel haft with gold rings, blue cloth-wrapped grip, frosty white highlights painted on the edges, single weapon, no hands, lying flat, side view
```

**Splitbow** (a relic; it fires three arrows at once):
```
[prefix], ornate relic recurve bow, laminated steel and oak limbs, gold-capped steel tips, a heraldic crest on each side of the riser, gold three-way arrow guide on the riser, taut string, blue ribbon and tassel, the most ornate of the set, single weapon, no hands, lying flat, side view
```

### Underworld (black forged iron with light chamfered edges, glowing ember cracks, ash-white bone grips, a chain charm)

**Spear:**
```
[prefix], infernal spear, black iron leaf blade with light bevelled edges and glowing ember cracks along the ridge, iron shaft, ash-white bone vertebra grip, chain charm with an ember bead and a fang, single weapon, no hands, lying flat, side view
```

**Shotgun:**
```
[prefix], infernal blunderbuss shotgun, flared black forged iron barrel with chamfered light edges, glowing ember vents along the barrel, ash-white bone stock with an iron strap at the butt, riveted lock plate, chain charm, single weapon, no hands, lying flat, side view
```

**Rifle:**
```
[prefix], infernal long rifle, long black forged iron barrel, forged receiver with lock plates, glowing ember cracks, ash-white bone grip, cheek rest and crescent butt, chain charm with an ember bead, single weapon, no hands, lying flat, side view
```

### Planet (white alloy shells, grey rims, dark joints, glow strips, rubber grips, a cable tag)

**Launcher:**
```
[prefix], sci-fi shoulder rocket launcher, white alloy tube with grey rims and raised collars, yellow hazard band, cyan glow strips in dark channels, ribbed rubber grip, hanging tag on a cable, rounded friendly shapes, single weapon, no hands, lying flat, side view
```

**SMG:**
```
[prefix], compact sci-fi submachine gun, bevelled white alloy receiver with grey rims, short shroud, glowing green magazine, green glow strip, ribbed rubber grip, hanging tag on a cable, single weapon, no hands, lying flat, side view
```

**Beam:**
```
[prefix], sci-fi beam gun, bevelled white alloy shell, dark alloy vents, cyan glow strips and a glowing emitter at the muzzle, ribbed rubber grip, hanging tag on a cable, single weapon, no hands, lying flat, side view
```

### Dream (pearl bodies, pastel gold, faceted pastel crystal, violet edges, things that float)

**Chain Gun:**
```
[prefix], dreamlike chain gun, smooth pearl egg-shaped body, rotating barrel of pastel crystal rods, floating pastel-gold rings around the barrel not touching it, deep violet edges, crystal drop on a pink ribbon, single weapon, no hands, lying flat, side view
```

**Spinblade** (a relic):
```
[prefix], dreamlike relic sword, seven-faceted crystal blade in lilac and pale blue with pearl edge bands and a violet spine, pastel-gold guard, glowing gem pommel with a floating halo ring around it, crystal drop on a pink ribbon, the most ornate weapon of the set, single weapon, no hands, lying flat, side view
```

## 4. The Forest Road

The current pieces are in `tools/assets/forest_kit.py`. Keep the heights: a camp edge is at most
4 studs tall (players see over it), clutter inside a camp too, and the Chief's tent must stay open
to walk through.

### Trees and undergrowth

**Fir, background mass** (make two or three variants; about 26–31 studs tall):
```
[prefix], tall dark stylized fir tree, layered drooping branch tiers in deep blue-green, straight dark trunk, simple silhouette for a forest backdrop
```

**Fir, hero** (the trees beside the road):
```
[prefix], tall stylized fir tree with character, layered branch tiers with sun-touched yellow-green tips and darker inner green, thick trunk with exposed roots
```

**Broadleaf tree:**
```
[prefix], stylized broadleaf forest tree, thick curved trunk, foliage made of a few large soft faceted clumps, painted light-to-dark green gradient, sun-touched yellow-green tops
```

**Dead snag:**
```
[prefix], tall dead tree snag, bare grey trunk with broken branches and a jagged broken top, peeling bark
```

**Stump** (plain and mossy):
```
[prefix], low tree stump, flat cut top with rings, small roots, moss on one side
```

**Bush** (small and large):
```
[prefix], round leafy forest bush made of a few soft faceted clumps, green gradient
```

**Thicket** (a dense low hedge used as a camp edge):
```
[prefix], dense long low thicket of tangled shrubs and branches, dark green, as wide as three bushes, no taller than a person's chest
```

**Bramble** (the burnable cave mouth; the Flamethrower burns it away):
```
[prefix], thick tangle of thorny bramble vines with dry brown and dark green stems and long thorns, dense enough to block a doorway
```

**Fern and mushrooms:**
```
[prefix], low forest fern clump with a few long fronds
```
```
[prefix], small cluster of forest mushrooms, pale caps with faded red spots
```

### Stones and cliffs

Use image-to-3D with your rock references (`assets/research/2026-10-21-l4/ref_rocks_*.png`) and these
texts.

**Standing stones** (monolith 9 studs, tall, slim, leaning, broad):
```
[prefix], tall bevelled standing stone, chunky angular monolith with chamfered edges, moss on the top faces, warm grey and sandstone tones
```

**Rocks** (low chunky boulders, a flat slab, a small rock, scattered pebbles):
```
[prefix], low chunky bevelled boulder with chamfered edges, moss on top, warm grey tones
```

**Cliff cluster:**
```
[prefix], cluster of stacked bevelled stone blocks forming a small cliff, chunky angular rocks with chamfered edges, moss on top faces, warm grey and sandstone tones
```

### Camp edges (at most 4 studs tall, each about 7–9 studs long)

```
[prefix], short raider camp wall of stacked horizontal logs held by upright stakes and rope, chest high, about two metres long
```
```
[prefix], raider camp palisade of sharpened wooden stakes leaning outward, lashed with rope, chest high
```
```
[prefix], low camp wall of piled chunky rocks, chest high, moss in the gaps
```

### The camps

**Hide tent:**
```
[prefix], raider hide tent, animal hides stretched over crossed wooden poles, rope ties, an open front flap, bone ornaments on the poles
```

**Spawn tent** (raiders pour out of it; it must look like a doorway):
```
[prefix], large raider war tent with a wide open dark entrance, hides over a frame of poles, red cloth banner on top, skulls by the entrance
```

**The Chief's tent** (huge, about 27 studs across and 16 tall, open so players fight inside it):
```
[prefix], huge raider chieftain's pavilion, a ring of thick poles holding a high hide canopy, open on all sides so you can walk through, dark crimson cloth banners, skull trophies, a raised bone throne under the canopy
```

**Watchtower:**
```
[prefix], tall wooden raider watchtower, four log legs with rope cross bracing, a small platform with a hide roof, a ladder
```

**Gate post and banner:**
```
[prefix], tall carved wooden raider gate post topped with an animal skull and feathers
```
```
[prefix], tall raider war banner, red-brown cloth with a painted white skull on a wooden pole, tattered hem
```

**Camp clutter** (one prompt each):
```
[prefix], raider campfire, ring of stones around stacked burning logs with stylized orange flames
```
```
[prefix], lean-to shelter of branches and hides against two poles
```
```
[prefix], wooden drying rack with stretched animal hides
```
```
[prefix], wooden weapon rack holding crude clubs and spears
```
```
[prefix], neat stack of split firewood
```
```
[prefix], rolled fur bedroll on the ground
```
```
[prefix], pile of three tied burlap sacks
```
```
[prefix], low pile of animal bones and a skull
```
```
[prefix], wooden pole with an animal skull on top and hanging feathers
```
```
[prefix], simple log bench, a split log on two short stumps
```

### Secrets (today these are plain blocks)

**Treasure chest** (the lookout, the cave cache and the mountain summit):
```
[prefix], sturdy wooden treasure chest bound with iron straps and rope, bone clasp, lid closed, slightly worn
```

**Island shrine** (reached over frozen water):
```
[prefix], small ancient forest shrine, mossy stone plinth with a carved standing stone and an offering bowl, a few candles, vines
```

## Later (only if the Village arena returns)

The Raider Arena is hidden for the publish, so its bosses can wait.

**Colossus** (role `colossus`, 14 studs):
```
[prefix], giant hulking forest brute, massive arms and small head, mossy stone-like skin plates on shoulders and back, crude wooden and rope armour, standing in T-pose, arms straight out to the sides, legs slightly apart, empty open hands, nothing held, full body visible
```

**Warlord** (role `warlord`) and **his guard** (role `guard`): generate them when the arena is
planned again.
