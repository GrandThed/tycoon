# Combat design (draft for Ben's review)

Status: **draft, 2026-09-24.** Nothing below is built yet. Once Ben approves it, this document is
the plan of record for combat, and `docs/INTERFACES.md` contracts are written from it.

## Why this document exists

The first attempts (C1 and C2.5 Stop 1) were built fast, tuned in a simulator, and played only at
the end. Ben judged the result awful: static, weak hits, dull enemies, bad sound. This time the
order is reversed. We agree on the feel first, build a test range to try it, and scale up only what
feels good in that range.

Ben's rulings (2026-09-24):

- **Keep everything that exists and modify it.** That covers the Expeditions place, co-op
  parties, joining runs, rewards into the tycoon, the Armory, Ascension, Overdrive and missions.
  Only the fight itself is reworked.
- **No sound for now.** All combat sound ids stay 0.
- **Dynamic.** Big jumps and movement that matters in a fight.
- **Forgiving melee.** Hitboxes are generous, and you can see them as a slash or shockwave effect.
- **Great-feeling ranged weapons.** Bows with strong effects and a diverse set of guns.
- **A game of numbers.** Most weapons hit several enemies at once. Big crowds, big damage numbers.
- **A test range.** Dummies and weapon alternatives, so each system can be tried and refined.

Ben's answers to the open questions (2026-09-24):

- **Camera:** over-the-shoulder stays. **Ranged weapons shoot like Fortnite.**
- **What was wrong:** enemy tracking was OK, but there was **no feedback**. Having to **press an
  on-screen button to attack on a phone is unacceptable**.
- **Role:** for this feature, combat is **the main draw**, and it gets the time that deserves.
- **Phones:** everything must **work on phones from the first playable step (P1)**.

## 1. Pillars

Every combat decision is checked against these five. In a conflict, the earlier one wins.

1. **Crowds and numbers.** The fun is mowing through many enemies at once. A weapon that hits
   one target at a time is the exception and must pay for it with huge single-target damage.
2. **What you see is what you hit.** The effect you see is the hitbox. A slash arc, a shockwave
   ring or a beam shows exactly the area that deals damage, and that area is a little *more*
   generous than it looks, never less.
3. **Movement is part of combat.** Jumping, dashing and landing are attacks and dodges, not just
   travel.
4. **Every weapon feels different.** Different shape, rhythm and effect, not just different numbers.
5. **Tried in the range before it ships.** No weapon, enemy or move reaches a mission until it
   has been played against dummies and Ben has approved it.

## 2. Movement

| Move | What it does | Why |
|---|---|---|
| **High jump** | Much higher than a normal Roblox jump (tunable). | The "big jumps" Ben asked for; lets you get above a crowd. |
| **Double jump** | A second jump in the air. | Air control and escape. |
| **Dash** | A quick burst in the move direction, on the ground or in the air, with short invulnerability. | Dodging telegraphed attacks; closing distance. |
| **Ground slam** | Attack while falling after a jump to crash down and deal damage in a ring. | Turns every big jump into a crowd attack (pillar 1 + 3). |
| **Air attacks** | Melee and ranged work in the air; melee briefly holds you in place. | Lets you fight above the crowd. |

All distances, heights and cooldowns live in config. Every one of them can be changed live in
the test range (section 8).

## 3. Controls

### Shooting (Fortnite style)

- Over-the-shoulder camera with a **centre crosshair**. Shots go from the camera to what is under
  the crosshair. The gun's muzzle is only where the tracer starts, so what you aim at is what you
  hit, even around the character's shoulder.
- **Bloom:** the crosshair widens while you move, jump or fire fast, and tightens when you stand
  still. The **first shot** after a pause is accurate.
- **Aim down sights** (right mouse / left trigger / a touch toggle): the camera zooms in, the
  character slows, and spread tightens.
- **Hitscan** for bullets and beams (instant). **Projectiles** for bows, launchers and grenades,
  which fly visibly and can arc.
- **Weak points:** hits on an enemy's head or glowing core deal critical damage, shown with a
  different number colour, as in Fortnite.

### Phones: no attack button

Ben's rule: tapping an on-screen button to attack is not acceptable. On touch:

- **Left thumb** moves (Roblox thumbstick). **Right thumb** drags to aim the camera anywhere on
  the right half.
- **Attacks fire on their own:**
  - a ranged weapon fires while the crosshair (plus a small assist) is on an enemy;
  - a melee weapon swings while an enemy is inside its hitbox.

  This is the "auto-fire" mode of mobile shooters. Holding the aim is the attack.
- **Alternative to compare in the range:** tap-to-fire anywhere on the right half, so no fixed
  button is needed.
- Jump, dash and abilities keep small buttons, because those are choices, not the constant
  action. Ground slam is jump then dash-down (or a swipe down) while airborne.
- PC and gamepad keep normal click / trigger attacks.

## 4. Feedback (the top priority, with no sound)

The version Ben played tracked enemies fine but gave no feedback. With sound off, every hit has
to be **seen**, in layers that stack:

1. **Crosshair:** a hit marker on every hit, a bigger one for a crit, and an X for a kill. The
   crosshair "kicks" on hit.
2. **Damage numbers:** Fortnite-style pop and fall, white for normal and yellow for crit,
   combined into one burst when an attack hits a crowd.
3. **The enemy:**
   - a white flash on hit;
   - a squash / flinch;
   - knockback or a launch;
   - a death burst or ragdoll that flies away from the hit.
4. **The hitbox effect:** the slash arc, shockwave or beam drawn over the exact area hit.
5. **The screen:**
   - hit-stop, scaled by the number of enemies hit;
   - camera shake on heavy hits;
   - a brief edge flash on crowd kills;
   - vibration on gamepads and phones that support it (HapticService).
6. **Counters:** a combo counter, and a "×N" for enemies hit by one attack.

Each layer has its own strength value, so the range can turn it up, down or off.

## 5. How hits work

- **The server still decides every hit**, as today. The client only draws effects, so cheating stays
  hard.
- **Hit shapes.** Every attack uses one of five shapes:
  - **arc**: a sword swing, a flat slice in front of you;
  - **sphere**: a slam or explosion;
  - **capsule**: a thrust or charge line;
  - **cone**: a shotgun blast;
  - **ray**: a bullet or beam, with a thickness.
- **Forgiveness.** Each shape is checked a little larger than it is drawn, by a configurable pad
  in studs. Enemies are hit if any part of their body overlaps, not only their centre.
- **Hitbox effect.** Every attack draws its exact shape as a visual effect for a moment: a glowing
  arc, a ring on the ground, a cone flash or a beam. A debug toggle in the test range also draws
  the true hitbox wireframe, to check that the two match.
- **Target caps.** Each attack states how many enemies it can hit, from 1 to unlimited. Most
  weapons sit between 5 and unlimited (pillar 1).
- **Big numbers.** Damage numbers from one attack that hits many enemies combine into one
  readable burst, instead of 30 overlapping numbers. A combo counter and a kills-per-attack count
  reward hitting crowds.
- **Impact.** Enemies are knocked back and launched, so light enemies fly. Hit-stop scales with the
  number of enemies hit, and the screen shakes on big hits. Every one of these can be tuned in the
  range.

## 6. Weapons (first proposal, to refine in the range)

The Armory keeps its slots, bands and tiers. What changes is what each weapon **class** does.
Each class gets alternatives (A/B/C) to compare in the range.

### Melee

| Class | Shape | Hits | Feel |
|---|---|---|---|
| Sword | wide arc; the combo's third hit is a spin | 6–10 | fast, flowing, the all-rounder |
| Axe | very wide arc, heavy knockback | unlimited in the arc | slow, crushing, sends crowds flying |
| Spear | long capsule thrust that pierces the whole line | unlimited on the line | reach, lines of enemies |
| Hammer | sphere on impact plus a ground shockwave ring | unlimited in the ring | best with ground slam from a jump |

### Bows

| Class | Behaviour | Hits |
|---|---|---|
| Longbow | charged arrow that pierces; a full charge explodes at the end | pierce 3–5 + blast |
| Split bow | one arrow that splits into a fan mid-flight | 3–7 arrows |
| Rain bow (ability) | arrows rain on a marked circle | unlimited in the circle |

Arrows are visible, fast and leave a trail. Hits spark, and a full charge flashes.

### Guns

| Class | Behaviour | Hits |
|---|---|---|
| Shotgun | cone of pellets with big knockback | everything in the cone |
| Rifle | piercing round through a line | pierce 5+ |
| SMG / machine gun | fast spray; each bullet hits one enemy, but volume wins | 1 per bullet |
| Launcher | explosive shell with splash | unlimited in the splash |
| Beam / laser | continuous beam you sweep across a crowd | everything the beam touches |
| Chain gun | a shot that jumps from enemy to enemy | 3–8 chains |

Guns get muzzle flashes, tracers, shell ejection and recoil kick. The feel comes from rhythm and
visuals, since there's no sound.

### Abilities

Each weapon keeps one ability on a cooldown, redesigned around crowds: whirlwind, shockwave,
arrow rain, grenade, overcharged beam. Kills shorten the cooldown, as today.

## 7. Enemies: built for crowds

- **Many cheap enemies, a few tough ones.** Waves become crowds of weak "fodder" plus a few
  elites and a boss. Fodder dies in one to three hits from a crowd weapon.
- **Performance is the hard limit.** Today every enemy is a full Roblox Humanoid, which is
  expensive, and the cap is 24 alive. A game of numbers needs far more. The plan is lightweight
  enemies with no Humanoid: the server moves simple positions and hitboxes, and each client draws
  and animates the bodies. The goal is 80–150 fodder on screen. Proving this in the range comes
  before anything else, because every other choice depends on it.
- **Enemy roles:**
  - Fodder rush you.
  - Shooters stay back.
  - Brutes charge, with a telegraph, as today.
  - A few elites have armour that needs a heavy hit.
  - Bosses keep telegraphed patterns.
- Knockback and launches apply to fodder fully, to elites partly, and to bosses not at all.

## 8. The test range ("Proving Grounds")

A Studio-first space for building and judging every system above. It's the first thing we build.

- **Where:** a separate arena in the Expeditions place, chosen with a debug lever. It uses the
  same combat code as real missions, so what is tuned there is what ships.
- **Dummies:**
  - rows at 10, 25, 50 and 100 studs for ranged testing;
  - packed crowds of 10, 30 and 100 for multi-hit testing;
  - moving dummies (walkers, strafers, jumpers);
  - armoured dummies;
  - a boss dummy with a big HP bar;
  - dummies that respawn.
- **Tuning panel** (Studio only):
  - switch weapon class and alternative (A/B/C);
  - change any number live (damage, arc, pad, knockback, jump height) without restarting;
  - toggle hitbox wireframes;
  - reset the dummies.
- **Readouts:** damage per second, enemies hit per attack, kills per attack, time to clear a crowd,
  frame time with N enemies.
- **Saving a winner:** when a variant feels right, a button prints its values in `Combat.json`
  format so they can be committed as the new default.

## 9. What changes in what exists

| System | Change |
|---|---|
| Expeditions place, co-op, joining runs, rewards, Mentor, Armory, Ascension, Overdrive | **Kept.** Only the damage they feed on changes. |
| Missions and waves | Kept as structure, re-tuned for crowds (much higher counts, cheaper fodder). |
| Enemy system | Rebuilt as lightweight crowd enemies (section 7). Humanoid rigs stay only for bosses, if needed. |
| Weapon classes and abilities | Redesigned per section 6; config shape extended with hit shapes and caps. |
| Camera | **Over-the-shoulder, kept.** Shooting reworked to Fortnite style (section 3). |
| Touch controls | **Attack button removed.** Auto-fire and auto-swing (section 3). |
| Sound | Off. |
| C2.5 Stop 1 code | Reused where it fits (telegraphs, ragdolls, impact effects, steering ideas). The rest is replaced as each piece is rebuilt. |

## 10. Build order (each step ends with Ben playing it in the range)

1. **P0: this document**, approved.
2. **P1: Proving Grounds, movement, controls and the crowd-enemy prototype.**
   - The range, dummies, the tuning panel and the readouts.
   - High jump, double jump, dash and ground slam.
   - Phone controls with auto-fire and auto-swing.
   - The feedback layers on one placeholder gun and one placeholder sword.
   - A lightweight-enemy stress test up to 150.
   - Gate: movement and feedback feel good **on PC and on a phone**, and 100+ enemies run smoothly.
3. **P2: first two weapons**, the sword and the shotgun, each with A/B/C variants and the hit
   shapes, hitbox effects and multi-hit numbers. Gate: Ben picks winners.
4. **P3: the remaining weapon classes and abilities**, in batches, each judged in the range.
5. **P4: enemy roles and bosses** against the new weapons, in the range.
6. **P5: back into the missions.** Crowd waves, rebalanced rewards, co-op checks, all four eras.
7. **P6: looks.** Detailed enemy and weapon models and arena dressing (the old Stop 2).

## 11. Decided

All four open questions are answered (see the top). Every remaining choice is made by
comparing alternatives in the range:

- auto-fire vs tap-to-fire on phones;
- bloom and aim-down-sights values;
- feedback layer strengths;
- weapon variants A/B/C.
