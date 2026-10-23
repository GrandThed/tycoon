# L4 study, Part B: the Camp Chief and the raiders' looks

Part B of `docs/prompts/l4-study.md`. Worktree `tycoon-p5`, branch `l4-real-forest` (0b30e45). No code was written.
**Measured** = I ran it here (§7); **read** = taken from the file at the line given. Python numbers come from `py`
3.12.10 64-bit, the interpreter the gates' shebang picks.

## 0. In short

- **Today's raiders are placeholders:** four pooled Parts each (block legs, block torso, ball head, visor) plus a
  few role "cue" Parts. No arms, no walk cycle, no LOD, no culling. Every resident is drawn from the run's start:
  86 on Normal, 98 on Hard, plus the tents' stock.
- **The Camp Chief can be a new crowd kind in data, `chief`.** No Luau code names the Colossus, and the brain
  already has the charge (`lane`), the slam (`ring`) and the call (`summon`). Only `sim_range.py` and one harness
  check name it. The Colossus stays in the Raider Arena. What does not work as it stands: a call raising two kinds,
  and a call of more than 15 (the population cap).
- **Detailed raider models are client-only work** (the server never reads a drawn body) and can reach the client by
  the props route the weapons used, with no pipeline change.
- **Two technical risks, found by reading, each needing a ruling before any model is built:** (1) the tells and the
  hit flash recolour the body, and a textured MeshPart ignores `Color`; (2) every windup tips the whole figure back
  0.45 rad about its feet, which puts the drawn head 2.7 to 3.5 head radii off the head the server scores.
- **Recommendation:** models in L4 for the six Forest kinds plus the Chief; the Chief carries the Warhammer that
  beating him on Hard gives you; his signature is a war-club sweep (an existing `arc`).

## 1. The raiders today, as drawn

**The figure** (read). `CrowdRenderer.buildTemplate` builds one Model of four anchored SmoothPlastic Parts with no
collide, query or touch: `Legs` (block), `Torso` (block, the only shadow caster), `Head` (ball), `Visor` (block)
(`src/combat/client/Controllers/CrowdRenderer.luau:545-576`). `applyKind` sizes them from the kind's numbers: torso
`radius x 1.9` wide and `x 1.3` deep, legs 42% of the neck, the head a ball of `2 x headRadius` centred at
`height - headRadius` (`:431-437`, `:920-994`). The colour is the kind's `color`, legs darkened, the head pulled 60%
toward warm yellow "so the crit point reads at a glance" (`:440-443`, `:991-993`); the visor goes neon orange through
a windup. "The figure has no arms" (`:78`).

**Cost** (read). One template for every kind: a spawn takes any pooled body and resizes it (`:1123`, `:2761`),
pre-warmed 16 a frame up to the run's `maxAlive` (`:450`, `:2589-2600`, `:2739-2746`,
`CombatUIController.luau:2032-2034`). One Heartbeat and one `BulkMoveTo` (`:2768`, `:2575`); a body whose pose did
not change is skipped (`:2455-2466`), so a resting crowd costs almost nothing and a moving body 4 CFrames plus its
cues. No LOD and no distance culling (a search for cull, LOD or distance finds none). Residents are drawn on arrival
from their spawn info (`:83-92`, `SpawnSeed.luau`).

**How many at once** (measured, `check_levels.py`): population 147 / 157 / 157 of the crowd's 160 on Normal / Hard /
Brutal; residents 86 on Normal (A 30, B 46, C 10) and 98 on Hard (A 36, B 50, C 12), tents' stock 16, the boss room's
cap 30-32, a boss reserve of 13. By kind on Normal: fodder 30, brute 26, slinger 20, armoured 8, lobber 2; Hard adds 2
fodder, 2 slingers, 5 armoured, 3 marksmen. Tent stock: fodder 6, slinger 4, brute 6. **The Forest fields six kinds
plus its boss**; the guard and the Warlord appear only in the Raider Arena (`Missions/1_Village.json:73-78`).

**What each kind shows** (read, `ThreatFx/Cues.luau:1-30`, `:123-430`). One cue per kind, picked from its **first**
attack's shape (`:137`), never its name. The lit pieces swell and redden through the windup; for a slinger or a
lobber they are the whole tell (`:22-27`).

| Kind | Height / radius / head r. | Colour | Cue |
|---|---|---|---|
| fodder | 5 / 1.3 / 0.7 | red-brown | none: the tint and the lunge are its tell |
| slinger | 5 / 1.2 / 0.65 | yellow | a lit orb in the right hand |
| marksman | 5.4 / 1.2 / 0.65 | purple | a dark barrel with a lit tip, plus ThreatFx's warning line |
| lobber | 5 / 1.4 / 0.7 | green | a pack on the back, a lit round on top |
| brute | 7.5 / 2.2 / 0.9 | rust | horns; its charge drawn ahead on the server clock (`CrowdRenderer.luau:2230`) |
| armoured | 6.5 / 1.7 / 0.8 | steel blue | a metal shell while plated (glints, bursts on the break), the plate bar |
| colossus | 14 / 4 / 1.6 | wine | shoulders, 3-spike crown, spines, a chest core that charges; lit red enraged |

**Poses and tells** (read, `CrowdRenderer.luau:1846-1925`, `:2049-2183`). All whole-body and procedural: windup
lean, lunge thrust, arc twist, the slam (up on the toes, then squashed flat), the call (head back, shaking), spent
slump, the seat at a fire (`COMBAT_REST_DROP` 0.35 of the height, `Theme.luau:1303`), flinch, knockback, launch, the
death fling. **Tells are colour too:** the windup tints the body red in 8 steps, the blow goes neon, a hit flashes
white, a spent body dulls, an enraged boss stays red (`:721-758`, `Theme.luau:854-859`, `CrowdRenderer.luau:986-990`).
**Markers:** the plate bar (`ThreatFx/PlateBar.luau:1-13`, `AlwaysOnTop` `:60`) and CampFx's "!" (`CampFx.luau:7-12`,
`:177`) hang on the head part, so a model must keep one.

**Hit shapes** (read, `src/shared/HitShapes.luau:332-366`). A ray hits a body when it touches an **upright capsule**
of `radius` from the feet to `max(height - 2 x headRadius, height/2 + radius)`, or the **head sphere** (centre
`height - headRadius`, radius `headRadius`); it crits only when the unpadded ray touches the head. The server never
reads the drawn body; aim assist and auto-fire read the same config numbers (`InputController.luau:1206`, `:1307`).
**A model agrees when its head fills that sphere and nothing else does**; horns or a crest outside it are misses by
design. Two places disagree today:
- **The windup lean** (computed from the code's numbers). `rootFrame` tips the whole figure about its feet
  (`:1905-1923`); every windup ends tipped back 0.45 rad (`:2074`, `:2113`, `Theme.luau:863`), the blow and the call
  lean 0.5 (`Theme.luau:864`, `:1098`). The server's head never moves. Drawn head off the scored one, at a windup's
  end / in a blow or call: fodder 1.9 / 2.1 studs (head r 0.7, 2.7x), brute 3.0 / 3.3 (r 0.9), Colossus 5.5 / 6.1
  (r 1.6, 3.5x). Less from the front, where most of the move runs along the line of sight. Ben's "I couldn't land a
  single headshot to the big guys" (MISSIONS_DESIGN §17.2) was fixed in the hit rule; the lean was not looked at.
  Placeholder balls hide it; a detailed head invites aiming.
- **The seated head** (PLAN.md:3242-3243, INTERFACES.md:12792, :13141). The server's shapes do not sit
  (`CrowdRenderer.luau:81-82`): the drawn seated head is 0.35 x height (2.5 to 3 head radii) under the scored one.
  The fix is on the server: bodies in `rest` lower the head sphere and capsule top by the drop, the drop moves from
  `Theme` into `ProvingGrounds.json` (both sides read it), `CrowdRay` and aim assist take it, `sim_range` mirrors it.
  Owners ui-engineer + luau-engineer A (PLAN). The same fix with or without models.

**A gate reads the drawn body:** `check_levels.py`'s walled-camp sight gate takes the drawn reach as the torso's
half-diagonal, 1.151 radii, from `TORSO_WIDTH`/`TORSO_DEPTH` in the renderer (`tools/check_levels.py:345`,
`:3165-3172`). A model must hand it its own reach, from bounds in config.

## 2. The Camp Chief

**Camp C's boss today** (read). Wave 2 of the Chief's Clearing is `{ "kind": "colossus", "at": [0, 30], "valor": 10 }`,
after an empty wave 1 and the two flank ambush groups (`Levels/1_ForestRoad.json:59-72`, `:196-215`). It pays 42,900
cash and 76 Timber (`:55`), a third of a Normal clear's 131,733 / 211 (`docs/BALANCE.md:6273`). The kind: height 14,
radius 4, head 1.6, speed 9, hp 4,700, no knockback, `rush`, `boss`; at 50% health windups x0.8, recovers x0.7,
chains of 2. Attacks in order: **`ring`** the slam (reach 14, 26 damage, a 40-stud front at 70/s, height 4, cooldown
6), **`lane`** the charge (reach 30, 32 damage, 44 x 10, cooldown 8), **`summon`** the call (12 fodder on a ring of
16, cooldown 18), **`lob`** a barrage of 5 circles of 18 (enraged only). HP = `hp x hpScale x party factor`
(`CrowdService.luau:1714`, `WaveService.luau:1033-1034`): 7,050 Normal, 19,975 Hard, 54,050 Brutal, solo. Choice:
off cooldown, in reach, allowed in the phase, longest unused first (`CrowdBrain.luau:28-37`, `:464-500`).

**Measured** (`sim_range.py --levels-only --level forest --check`, 9.6 min, PASS 164 / FAIL 0): alone in camp C
against the Broadsword it falls in 81.2 s (79.3-82.3) on Normal T1, 81.7 s Hard T3, 83.8 s Brutal T5, 0 hits taken;
one preset below it is not killed in 240 s (gates 135 / 180 s). **The call raises 56-60 fodder in that fight** (it
tops its 12 back up every 18 s). **The charge is the worst hit in the level** at every difficulty: 36 = 23.2% of the
bar on Normal (gate 25%), 64 = 27.8% Hard, 107 = 28.2% Brutal (gates 30%). **Any Chief attack of 33 base damage or
less keeps `FOREST_HIT_SHARE`.**

**"A charge, a slam, and a call for raiders" reuses all three as they are.** No Luau code names the Colossus
(`grep -ri colossus src --include=*.luau` finds nothing): the bar's name is `def.name` (`CrowdRenderer.luau:956`), the
summary's `run.bossName` (`WaveService.luau:681`), the boss cues come from `boss = true` (`Cues.luau:341`). So the
Chief is **a new kind `chief` in `ProvingGrounds.json`** and one word in the level file. The Colossus stays as it is:
the Raider Arena's wave 5 (`Missions/1_Village.json:73`) and the range's `colossus` set use it with their own bands
(`sim_range.py:247`, `:5106`); MISSIONS_DESIGN §12.4 gives it the Planet.

**What does not come free:**
- **A call that raises two kinds.** `summon` names one kind (`CrowdService.luau:1791`), and a call tops the
  summoner's living summons **of any kind** up to its `count` (`:1799-1818`): two summon attacks share one count
  (with 8 fodder alive, a call for 4 brutes raises nothing).
- **A bigger call.** Hard and Brutal are at 157 of 160 with a boss reserve of 1 + 12 (measured); the reserve is 1 +
  the largest summon count (`sim_range.py:5856-5868`), so **the Chief may call at most 15** unless the level shrinks
  elsewhere.
- **More than seven attacks** (the wire carries the index in 3 bits, `CrowdCodec.luau:36`, `:99-100`).

**New numbers** (proposal; the economy-designer tunes them against the bands): name "Camp Chief"; **the Colossus's
size and HP** (14 / 4 / 1.6, 4,700), so every geometry line of camp C stays as it is (he rises on the floor less his
radius, 78 studs from the entry; cover stays 0.5 under the lowest ground attack at 4); **the same pay** 42,900 / 76 /
10 Valor (Double Jump's price, the L3 climb and the chest shares hang on it, `sim_range.py:5119-5137`); a call of 10
to 12 fodder; **one signature attack in place of the barrage** (a giant brute does not throw fire), decision B2.

**Three signature candidates, only shapes and keys that exist:**
1. **The war-club sweep:** an `arc`, about reach 14 / range 16 / 150° / height 6. The Warlord already fights with an
   arc (`ProvingGrounds.json` warlord attack 3). Drawn as a ground wedge that fills to the impact
   (`CrowdRenderer.luau:886-918`, `:1946-2047`), a tell the Colossus never shows; a jump clears it.
2. **The rampage:** enraged, a second `lane` marked `enraged` with a short cooldown and `enrage.chain` 3, so he
   charges back and forth (`enraged`, `calm`, `chain`: `CrowdBrain.luau:39-42`, `:426-436`).
3. **Out of his tent:** his `at` inside the chief's tent (walk-through scenery, Part A), so his first steps come out
   of its door. Pairs with either.

**What pins camp C's boss** (read):
- `tools/sim_range.py`: `FOREST_BOSS = "colossus"` (`:5118`) drives every Forest boss row: `FOREST_BOSS_SECONDS` 64-90
  / 64-100 / 64-100 alone and in the run with no hit taken (`:5147`, `:10533-10566`); the clear bands that include the
  fight, `FOREST_CLEAR_SECONDS` (`:5124`) and `L3_CLOCK_SECONDS` ±5% (`:5170-5171`); one preset below,
  `FOREST_BELOW_BOSS` (`:5174`) and the human gate (`:5157`, `:5172-5173`); `FOREST_HIT_SHARE` (`:5151`); the pair rows
  (`PAIR_BOSS_SHARE`, `:311`); the bow report (`BOW_KINDS`, `:5141`); the pay bands (`:5133`, `:5137`). It mirrors the
  brain shape by shape (`CrowdBrain.luau:61`), so existing shapes need a constant renamed, not mirror code.
- `tools/crowd_harness/tests_l1c.luau:314`, `:374` expect `colossus` in the real level's wave 2.
- `check_levels.py`, `check_stage_mirror.py`: generic; their camp C lines come from the boss's radius, height,
  attacks and summon count (`check_stage_mirror.py:2419-2422`, `:2509-2511`).
- `check_levels_mutants.py`, `mutate.py`, `mirror_mutants.py`: re-aim any entry whose text quotes the Colossus.

## 3. Models for the raiders

**Do they belong in L4?** Yes, in my reading. L4 is "the first version that can be published" (MISSIONS_DESIGN §14);
Ben called the old combat "like a child's project" and chose **detailed models over chunky low-poly** for enemies
(memory `feel-pass-2026-09-23`: Stop 2, suspended with the reset, never built). Ball-headed blocks walking a dressed
forest would undo the scenery. **Minimum set: seven looks**, the six Forest kinds plus the Chief. The guard, the
Warlord and the Colossus appear only in the Raider Arena: models only if Part C keeps the arena on the published map,
else the placeholder, which stays the fallback for any kind without a model (CLAUDE.md).

**Scale** (read). A player is about 5 studs (R15 root at 3.0, head centre 1.5 above it: `sim_range.py:317`,
`check_levels.py:277`). Fodder and slingers are his height (5), the marksman 5.4, the armoured x1.3 (6.5), the brute
x1.5 (7.5), the Colossus x2.8 (14). Keep these: they are the hit shapes every band was measured on. testfit's weapon
view already stands a 5-stud R15 silhouette beside a model (`tools/testfit/weaponview.py:10-11`).

**The route** (precedents `people_kit.py`, the L3 weapon kit). A generator `tools/assets/raider_kit.py` (Blender)
writes GLBs into `assets/kenney3d/raider-kit/` (the folder is the registration, `weapon_kit_mesh.py:6-13`), colours
through `palette.py` from the forest palette Part A settles, blueprints in `tools/testfit/blueprints/_props/Raiders/`,
then `merge_stages.py --props`, `upload_models.py --props`, **one harvest paste**, `gen_templates.py --props`. Both
project files already map `templates/_props` into `ReplicatedStorage.Assets.Props` (`combat.project.json:14-19`),
where the client clones from (`ServerStorage.Enemies`, `:43-46`, belongs to the dead `EnemyService`).

**Posing without Humanoids = rigid pieces, as today.** The merge makes one MeshPart per kit per stage
(`merge_stages.py:1-12`), and a piece with `stage` k and `untilStage` k is in stage k only
(`tools/testfit/blueprint.py:73-79`). So **one prop per kind with rigid piece k in stage k** gives `Stage0..Stage4` =
head, torso, weapon arm, left leg, right leg, **with no pipeline change** (a `part` field per piece would be cleaner,
optional). The generator writes each piece's pivot and the kind's bounds to config, the `WeaponModels.json` pattern
(`HeldWeapons.luau:13-16`): the client never measures. The client keeps every pose it draws today on the model's root
and adds a **walk cycle** from distance travelled (stride fits the speed; a resting body still costs nothing) and
**one weapon-arm channel** for the blows (jab, sweep, two-hand slam, the call, the sling's whirl). **Rule for the
rig:** the lean bends the body below the neck and the head stays within half its radius of the scored head in every
pose before a hit lands (the fix for §1's lean). Not recommended: skinned meshes with Bones, an AnimationController and
uploaded animations (skinned upload through Open Cloud is unverified, animations are made in Studio where Ben finds
menu work hard, memory `feel-pass`, and it means an Animator on each of 100+ bodies).

**Renderer changes** (read): one pool per kind, pre-warmed from the level's make-up, in place of the single template
(`:1123`, `:2761`); a head part kept for the bar and the "!"; the plain cue pieces (horns, pack, barrel, shoulders)
dropped for kinds with a model, **the lit pieces and the shell kept as they are** (they are the tells); the sight
gate's reach fed from the model's bounds. CrowdRenderer has 154 top-level locals against the compile gate's 180
(counted by grep; `tools/check_compile.py:41-42`): the model code goes in a new module beside `Cues` and `SpawnSeed`.

**The colour risk.** The tells repaint `Color` and `Material` (`CrowdRenderer.luau:721-758`). A merged prop is
textured with its palette PNG (`merge_stages.py:20-24`) and its template writes Color white (`gen_templates.py:191-192`).
As I understand Roblox, **a textured MeshPart ignores `Color` except where the texture is transparent**: not verified
here, check in Studio first. Three ways through: **(a)** a see-through cloth swatch in the palette, so the cloth takes
the kind's config colour and every tint (one palette, no extra parts); **(b)** the cloth as a second MeshPart in each
stage whose TextureID the client clears (writable at runtime) and paints as today (certain; twice the parts); **(c)**
pre-tinted palette images swapped through TextureID (about 20 uploads; last resort). The prototype carries (a) and (b)
on the fodder, so one paste and one Studio look decide.

**Triangle budget** (proposal; measured for comparison with `glbtris.py` over the built GLBs: the L3 weapons are
1,702-3,490 triangles each, the city walkers 216-288):

| Kind | Budget | Normal residents + tent stock | Hard residents |
|---|---|---|---|
| fodder | 600 | 30 + 6 (+12 a call) | 32 |
| slinger, marksman, lobber | 800, gear included | 22 + 4 | 27 |
| armoured | 1,000, plate included | 8 | 13 |
| brute | 1,200 | 26 + 6 | 26 |
| the Chief | 4,000, plus the Warhammer's 3,142 | 1 | 1 |

Every resident drawn at once is about **75k triangles on Normal and 85k on Hard**, before Roblox's distance LOD
(props keep RenderFidelity Automatic; only world meshes are pinned to Precise, `gen_templates.py:87-89`). A full
Metropolis plot is about 62k (memory `metropolis-growth`). Phones are unmeasured; a cheap guard is to run the walk
cycle only near the camera, and measure before culling anything (Ben wants raiders seen before they see you, §15.1).

**Weapons in raiders' hands.** Not the L3 models: they would triple the budget and they are the player's rewards.
Raider gear belongs to the raider kit at 100-300 triangles: club or knife (fodder), sling, heavy crossbow (the
marksman's "line"), a satchel of firepots (lobber), log club (brute), lashed-plank plates that burst in splinters
(armoured). **The exception: the Chief carries the Warhammer**, already harvested
(`templates/_props/Weapons/Warhammer.rbxmx`), scaled with `Model:ScaleTo` (precedent `PropFactory.luau:284-288`);
beating him on Hard gives you that hammer (`Levels/1_ForestRoad.json:30`). No upload.

**Uploads and looks.** 35 stage uploads at five pieces a kind, about 25 if the four 5-stud kinds share one body. **One
harvest paste**, shareable with Part A's scenery run. Ben's looks before upload, as for the weapons: a prototype sheet
(fodder, brute, the Chief) with a pose strip each (rest, two walk frames, windup, blow, seated, spent) beside the R15
silhouette on a dark ground, then an overview of all seven. The strips must pose with the client's own maths, ported
to Python like `check_mirror`, or the pictures will not match the game.

## 4. Decisions for Ben

**B1. Raider models before the publish?** **A (recommended): all seven looks in L4** (about 25-35 uploads, one paste
shared with the forest, two looks, one client wave). **B: the Chief only**, the raiders stay blocks (cheaper, but the
enemies are the one undressed thing in a dressed forest). **C: none in L4**, models after the publish.

**B2. The Chief's signature move**, from above (C = the Chief, p = you). Each keeps the charge, slam and call; all
are data only.
```
 A SWEEP (recommended)  B RAMPAGE           C KEEP THE BARRAGE
     .--------.           C=====>  p          o    o
    / ////////\\              <=====C      o   C   o
   | ///C////  |  p       =====>               o
    wedge fills: jump    2-3 charges back    5 fire pots land in
    it or step out       and forth, enraged  circles, enraged
```

**B3. The Chief's look**, front view (o = you, 5 studs, to scale). **A (recommended):** a fur-cloaked chieftain in a
skull mask with the hammer that beating him on Hard gives you. **B:** war-painted, antler crown, log club. **C:** a
tree-armoured giant (risks reading as a creature, not a raider chief).
```
  A SKULL-MASK CHIEF    B ANTLER CROWN      C BARK GIANT
     \_/\__/\_/          \ |/  \| /            .^^^^^.
     ( O    O )           (  ==  )            {#######}
    /|=\____/=|\        /|  ||   |\          /#########\
   | |~ fur ~~| |=#    | |~~||~~~| |  |     |#|#######|#|
   | |~~~~~~~~| | #    | |  ||   | |  |     |#|#######|#|
     | |    | |   #      | |    | |  ##       |##| |##|
    _| |_  _| |_  #     _| |_  _| |_ club    _|##| |##|_   o
   Warhammer, scaled    log club, paint     no weapon: a creature
```

**B4. Telling raiders apart at 50 studs on a phone.** **A (recommended):** each kind keeps today's colour on its
cloth, beside its gear (a tell he already learned). **B:** one tribe palette, told apart by gear and size alone.
```
  A COLOUR + GEAR (rec.)               B ONE TRIBE, GEAR ONLY
  red   yellow purple green  rust      brown brown brown brown brown
   o      o*     o-    o#     O         o     o*    o-    o#    O
  fodder sling  xbow  pots  brute      (told apart by gear and size)
```

## 5. Risks, said plainly

1. **Tells may vanish on textured meshes:** if `Color` does not show on a model, windups, flashes and the enrage stop
   reading. A Studio check before the first model.
2. **Headshots disagree with what is drawn:** windup leans put the drawn head 2.7-3.8 head radii off the scored one,
   and a seated head sits lower. Detailed heads make both visible, so both fixes ride with the models.
3. **Phone frame time is unmeasured:** about 80k triangles of raiders, plus the forest, plus held weapons. Only Ben,
   on a real phone, can measure it.
4. **The asset job is bigger than L3's:** fifteen rigid weapons took a kit lead, three builders and two looks;
   articulated raiders that read at 50 studs on a phone are harder.
5. **Renaming the boss is a gate round:** sim constants, a harness check and mutant texts, then the full gates (about
   2 hours of `mutate.py`).
6. **The call matters to balance:** about 56-60 fodder a fight feed the pay and the population; a bigger call breaks
   160 on Hard.
7. **Part A's chief's tent:** taller than 3.5 studs it must be walk-through or unstandable (the cover rule) and unseen
   from outside (the sight gate); always-on-top markers still draw through walls, so walled camps keep "no plated
   residents".
8. **A published Raider Arena** needs three more looks (guard, Warlord, Colossus) or shows placeholders.

## 6. Owners for Part B's work

- **kit lead + builders (Opus):** `raider_kit.py`, a testfit raider view, pose strips with a Python mirror of the poses.
- **ui-engineer:** per-kind pools and the model figure module (placeholder fallback), the walk cycle, the head rule,
  the tint route, the drawn reach for `check_levels`.
- **luau-engineer A:** the seated hit shapes and `restDrop` into config.
- **economy-designer:** the `chief` kind and the level file, the `sim_range` constants and bands, the harness text.
- **lead:** Ben's Studio checks (tint, alpha, Neon on a textured MeshPart) and the shared harvest paste.
- **pipeline engineer (optional):** a blueprint `part` field.

## 7. What I measured, and what I only read

- **`py tools/check_levels.py`:** PASS; population 147 / 157 / 157; 252 Parts; camp C's boss lines.
- **`py tools/sim_range.py --levels-only --level forest --check`:** 9 min 38 s, CHECK PASS, 164 PASS / 0 FAIL: the
  Colossus's fight times, the summoned counts, the worst-hit shares.
- **`py -I <scratch>/glbtris.py`** over `assets/build/stages/_props/Weapons/*_S0.glb` and the people kit: triangles
  and bounding boxes.
- **`py -c`** over the level file and `ProvingGrounds.json` (the kinds per difficulty, sizes) and with the code's
  constants (the head offsets in §1); **`grep -c "^local "`** for CrowdRenderer's locals.
- **Everything else is read**, including all Roblox engine behaviour (a textured MeshPart's `Color`, instancing,
  LOD), which is unverified here.
