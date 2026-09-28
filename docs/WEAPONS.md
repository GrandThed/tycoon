# Weapons: roster, scaling and DPS (draft for Ben)

Status: **approved by Ben 2026-09-28** (all three decisions: families are a free choice per slot with the tier on the slot; era unlocks as listed; P2 adds Longbow, Splitbow, Greataxe, Spear to the range). It builds on `docs/COMBAT_DESIGN.md` and Ben's first range
playtest: "I really love all the alternatives, the combo melee is great, it lacks the bow."
Nothing here is built beyond the six range variants. The numbers are starting points for the range,
not final balance.

## 1. The idea in one paragraph

Every alternative Ben liked becomes its own **weapon family** with its own shape and feel. The
Armory keeps its two slots (melee and ranged) and its **tier ladder** (tiers 1–12, paid in era
materials and unlocked by city income, as today). The change is that the tier belongs to the
**slot**, not to one weapon:
- You pick any unlocked family for each slot.
- Your slot tier sets its power.
- Switching family is free, so you choose a playstyle, not a stat stick.

New families unlock era by era, so each era brings new toys.

## 2. Roster

Tier-1 numbers. **Single DPS** = damage per second on one target, with the combo averaged.
**Crowd DPS** = single DPS × the enemies a typical swing or shot hits in a packed crowd.

### Melee

| Family | Era | Shape | Damage | Rate /s | Single DPS | Crowd DPS | Feel |
|---|---|---|---|---|---|---|---|
| **Broadsword** (range sword A) | Village | wide arc 160°, up to 10 | 24 | 2.5 | 76 | ~460 (6 hit) | flowing all-rounder, 3rd hit ×1.8 |
| **Warhammer** (range sword C) | Village | shockwave ring r10, no cap | 44 | 1.3 | 73 | ~590 (8 hit) | slow, crushing, launches the crowd |
| **Spinblade** (range sword B) | Boomtown | arc 110°, 3rd hit a 360° spin | 16 | 3.4 | 83 | ~420 (5 hit) | fast, the spin clears everything around you |
| **Greataxe** | Boomtown | arc 200°, huge knockback, no cap | 40 | 1.4 | 73 | ~510 (7 hit) | sends crowds flying |
| **Spear** | Metropolis | thrust line 14 studs, pierces all | 30 | 2.0 | 72 | ~290 (4 hit) | reach; lines of enemies |

### Ranged

| Family | Era | Behaviour | Damage | Rate /s | Single DPS | Crowd DPS | Feel |
|---|---|---|---|---|---|---|---|
| **Longbow** | Village | charged arrow, pierces 5; a full charge explodes (r6) | 50 | ~1.0 | 50 | ~200 (4 hit) | hold, release, boom |
| **Splitbow** | Village | the arrow splits into 7 mid-flight | 18 ×7 | 1.6 | 29 | ~115 (4 hit) | fan of arrows into a crowd |
| **Shotgun** (range gun A) | Boomtown | cone 26°, everything inside | 55 | 1.1 | 61 | ~300 (5 hit) | close burst, big knockback |
| **Piercing Rifle** (range gun B) | Boomtown | line, pierces 8 | 42 | 2.4 | 101 | ~300 (3 hit) | precise; lines up crowds |
| **SMG** | Metropolis | spray, one enemy per bullet | 9 | 12 | 108 | ~108 (1 hit) | the boss and elite shredder |
| **Launcher** (range gun C) | Metropolis | shell, splash r10, no cap | 60 | 0.75 | 45 | ~315 (7 hit) | lob into the middle of a crowd |
| **Beam** | Orbital | continuous beam you sweep; hits everything it touches | 5 ×10 ticks | — | 50 | ~250 (5 hit) | paint the crowd |
| **Chain Gun** | Orbital | shot jumps across 5 enemies (×0.8 each jump) | 60 | 1.2 | 48 | ~240 (5 hit) | lightning through a pack |

The balance intent, per pillar 1 (crowds and numbers):
- **Melee** has the highest crowd DPS (~420–590), because you must stand in the crowd.
- **Ranged crowd weapons** sit at about half that (~200–320), paid for by safety.
- **Single-target specialists** (SMG, Piercing Rifle) have the highest single DPS (~100+) and
  the lowest crowd DPS. They're for bosses and armoured enemies.
- **Splitbow** looks low at 115 and is the first to try in the range. Proposal: 26 per arrow,
  about 210 crowd DPS.

### Abilities (one per family, on a cooldown that kills shorten)

- Broadsword: **Whirlwind**.
- Warhammer: **Earthquake**, three rings outward.
- Spinblade: **Blade Storm**.
- Greataxe: **Leap Smash**.
- Spear: **Impale Dash**.
- Longbow: **Arrow Rain** on a circle.
- Splitbow: **Volley**.
- Shotgun: **Slug Burst**.
- Rifle: **Overcharged Shot**, which pierces everything.
- SMG: **Mag Dump**.
- Launcher: **Cluster Shell**.
- Beam: **Overload Sweep**.
- Chain Gun: **Storm Coil**.

## 3. Scaling

### The tier ladder (unchanged from today's Armory)

A family's damage = its tier-1 damage × the **tier multiplier**. Shape, rate, reach and caps stay
the same at every tier, so a weapon always feels like itself.

| Tier | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Era (band) | Village | Village | Village | Boomtown | Boomtown | Boomtown | Metro | Metro | Metro | Orbital | Orbital | Orbital |
| Multiplier | ×1 | ×1.5 | ×2.2 | ×5 | ×7.5 | ×10.8 | ×25 | ×37.5 | ×54 | ×125 | ×183 | ×267 |

Each era's first tier is a big jump (about ×2.3 over the tier before it). The two tiers after it
are smaller steps. Costs and income gates stay as they are in `Armory.json`.

On top of the tier:
- **Ascension** (after a rebirth) multiplies damage by ×2 / ×3.5 / ×6.
- **Once per era**, each family also gains one small **feel perk** so the weapon evolves visibly:
  - Broadsword: +1 combo hit;
  - Warhammer: +2 ring radius;
  - Shotgun: +4° of cone;
  - Longbow: +1 pierce.

  The perks are exact values in config, tried in the range first.

### Sample: damage per hit / single DPS / crowd DPS by tier

| Family | Tier 1 | Tier 3 | Tier 5 | Tier 8 | Tier 11 | Tier 12 |
|---|---|---|---|---|---|---|
| Broadsword | 24 / 76 / 460 | 52 / 165 / 990 | 180 / 570 / 3.4K | 900 / 2.9K / 17K | 4.4K / 14K / 84K | 6.4K / 20K / 122K |
| Warhammer | 44 / 73 / 590 | 95 / 159 / 1.3K | 330 / 551 / 4.4K | 1.7K / 2.8K / 22K | 8.1K / 13K / 108K | 11.7K / 20K / 157K |
| Shotgun | 55 / 61 / 300 | 119 / 131 / 655 | 412 / 454 / 2.3K | 2.1K / 2.3K / 11K | 10K / 11K / 55K | 14.7K / 16K / 81K |
| Longbow | 50 / 50 / 200 | 108 / 108 / 433 | 375 / 375 / 1.5K | 1.9K / 1.9K / 7.5K | 9.2K / 9.2K / 37K | 13.3K / 13.3K / 53K |
| SMG | 9 / 108 / 108 | 20 / 234 / 234 | 68 / 810 / 810 | 338 / 4K / 4K | 1.7K / 20K / 20K | 2.4K / 29K / 29K |

With Ascension 3 (×6), a tier-12 Warhammer reaches about **940K crowd DPS**. Those are the
"game of numbers" figures the damage bursts will show.

### Does it fit the enemies? (hits to kill at each era's recommended tier, Broadsword)

| Era | Recommended tier | Hit | Fodder HP → hits | Brute HP → hits |
|---|---|---|---|---|
| Village | 2 | 36 | 52 → **2** | 176 → **5** |
| Boomtown | 5 | 180 | 194 → **2** | 658 → **4** |
| Metropolis | 8 | 900 | 854 → **1** | 2,892 → **4** |
| Orbital | 11 | 4,400 | 4,992 → **2** | 16,895 → **4** |

Fodder dies in 1–2 hits and brutes in 4–5 in every era, so the crowd-mowing feel holds all the
way up. An under-geared player (one era behind) needs about 5× the hits, which is the push to
upgrade.

## 4. Decisions for Ben

1. **Families are a free choice per slot, and the tier belongs to the slot.** Is that right? The
   alternative is upgrading each family separately, which is slower and grindier.
2. **Era unlocks:** is the assignment above right (Village: Broadsword, Warhammer, Longbow,
   Splitbow; Boomtown: Spinblade, Greataxe, Shotgun, Rifle; Metropolis: Spear, SMG, Launcher;
   Orbital: Beam, Chain Gun)? Or should everything unlock sooner?
3. **Next in the range (P2):** add the Longbow and Splitbow (the missing bows) plus the
   Greataxe and Spear, as A/B variants like before.
