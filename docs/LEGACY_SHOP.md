# Legacy shop — Phase 2 design and pricing (proposal, nothing frozen)

Design document for spec §3's "Phase 2 Legacy shop". Ben decides; the lead then writes the M6
contracts. Every number below comes from `py tools/sim_economy.py --shop <model> --laps N`
(prototype flags added for this document — the perk table is **hardcoded in the sim** because
no `LegacyShop.json` exists yet; the default output and `--check` are byte-identical, diffed).
No game code and no config changed.

## 1. Recommendation in one paragraph

**Model C — "invest + softcap".** Legacy is never consumed (buying a perk deducts from a
spendable balance equal to Legacy earned minus Legacy spent; the passive multiplier keeps
reading the full total), **and** the passive multiplier `1 + 0.01 × legacy` becomes linear only
up to a `softcap` of 1000 Legacy, growing logarithmically above it. Lap 1 is untouched by the
softcap (the max Legacy at any lap-1 era entry is 529, the lap-1 total is 887) and stays in every
spec §4 band with the shop in use (15:19 total); laps 3+ stop collapsing: **16:20 → 4:15 → 2:29
→ 1:50 → 1:36 → 1:27** against today's 16:20 → 4:51 → 2:29 → 1:32 → 1:03 → 0:45 and Model B's
16:20 → 3:57 → 1:43 → 0:57 → 0:38 → 0:28. The perk set becomes the visible late-game
progression; the raw multiplier stops being the runaway engine. Model A (spend) is rejected
with numbers in §4.

## 2. Perk table (final numbers)

Value column: lap-1 total playthrough with that perk owned from the start, alone, vs 16:20:04
(`--perks <id>=<tier>`). Only greedy, solo, free player — the sim cannot see neighbours or
offline, so those two are priced as quality-of-life.

| Perk | Tiers | Effect per tier (final) | Tier costs (Legacy) | Total | Measured value | Rationale |
|---|---|---|---|---|---|---|
| Founder's Blessing | 5 | +5% income each, multiplicative (×1.276 at 5) | 80 / 160 / 300 / 400 / 550 | 1490 | −4.8% per tier; −21.6% at 5 | Best pacing value per Legacy at tier 1, so it is the first "real" perk; escalating price keeps tiers 3–5 in laps 2–4. |
| Master Builders | 3 | −10% level-up cost each (−30% total) | 200 / 400 / 650 | 1250 | −4.9% at 1; −15.4% at 3 | Same value as a Founder's tier but also buys ~1–4% more Legacy per era (greedy levels further), hence pricier. |
| Inheritance | 3 | enter every era with cash = first 3 / 5 / 8 slots' `baseCost` | 40 / 90 / 180 | 310 | −0.2% / −1.0% | Pure feel (skips the 1–4 minute era head). Cheapest perk in the shop: the first thing a lap-1 player can buy after Era 1. |
| Level Floor | 2 | new buildings start at level **5 / 8** (was 5 / 10) | 200 / 500 | 700 | −3.0% / −6.4% | **Tuned down from 10 to 8**: level 10 is a milestone, and a floor of 10 hands a fresh building ×4.16 income for one slot cost — the rusher's Era 1 went 15:10 → 3:42 (greedy only −14%). At 8 the rusher gets 8:17 and greedy −6%. |
| Extra Milestone | 1 | level 75 joins `milestoneLevels` (one more ×2) | 350 | 350 | −2.8% | Small for greedy (few buildings pass 75) but a "completionist" perk that changes what the level ladder shows; mid-shop price. |
| Good Neighbours | 1 | neighbour bonus 3% → 4% per player, cap 27% → 36% | 250 | 250 | not simulated (solo sim) | Up to +9% in a full 10-plot server, 0 alone. Social, so priced like a mid tier. |
| Long Memory | 3 | offline cap **+2h per tier**, added to the player's current cap (8h free, 24h OfflinePro); efficiency unchanged | 80 / 160 / 320 | 560 | not simulated (active-play sim) | Free player reaches 14h; pass owner 30h. Cheap tier 1 so a lap-1 player has a QoL buy in Era 3. |
| **All perks** | 18 tiers | | | **4910** | | |

Model-C rules kept: no perk touches `PassMult`/`PremiumMult` (paid stack stays 2.42× — verified:
`--shop softcap --laps 2 --passes doublecash,vip --premium` = 6:20:08 / 1:45:40 vs free 15:19:31 /
4:15:21, exactly 2.42× in both laps); Legacy is never sold; Long Memory stacks additively on top of
whichever cap the player has, so a free player can pass the pass's cap only by playing (§6 rule 1).

## 3. Cosmetics (pure sinks, zero pacing effect)

| Id | Item | Cost | Notes |
|---|---|---|---|
| `signTitle` | Plot-sign title ("Founder", "Magnate", …, picked from a fixed list) | 250 | Text on the existing plot sign; no new asset. |
| `nameTagColour` | Name-tag colour | 300 | Palette of ~6 colours; VIP's tag keeps its own style. |
| `monumentGlow` | Monument glow (PointLight + emissive) | 400 | Per era, on the monument slot only. |
| `advanceFireworks` | Fireworks on Advance Era / Rebirth | 500 | Particle burst at the monument; other players see it. |
| `goldenRoads` | Golden tint on unlock-type slots | 600 | Colour override on `unlock` models; does not touch VIP's skin set. |
| **All cosmetics** | | **2050** | |

**Whole shop: 6960 Legacy** (perks 4910 + cosmetics 2050). Legacy earned cumulatively: 887 after
lap 1, 2217 after lap 2, 3992 after lap 3, 6210 after lap 4, 8872 after lap 5.

## 4. Model comparison (sim, greedy, free, auto policy of §5)

Lap totals; per-era rows for the two live candidates below. "No shop" = today.

| Model | Lap 1 | Lap 2 | Lap 3 | Lap 4 | Lap 5 | Lap 6 | Lap 1 in band? | Contains lap 3+? |
|---|---|---|---|---|---|---|---|---|
| No shop (today) | 16:20:04 | 4:51:29 | 2:29:07 | 1:31:49 | 1:02:33 | 45:28 | yes | no (→ 0) |
| A spend, naive buyer | **51:32:06** | 33:22:04 | 23:30:23 | 14:23:29 | — | — | **no** (Era 4 = 39 h) | by breaking the game |
| A spend, rational buyer | 16:20:04 | 4:50:56 | 2:25:49 | 1:30:54 | 58:21 | 41:01 | yes | no — 10 buys in 6 laps, first one at lap 2 Era 4 |
| B invest | 15:19:31 | 3:57:19 | 1:43:27 | 56:49 | 38:21 | 27:49 | yes | no — worse than today |
| **C invest + softcap 1000** | **15:19:31** | **4:15:21** | **2:29:14** | **1:49:34** | **1:35:31** | **1:26:33** | **yes** | **yes — lap ratio 0.58 → 0.73 → 0.87 → 0.91, floor ≈ 1:15** |
| C, softcap 700 | 15:19:31 | 4:48:25 | 3:00:54 | 2:16:36 | 2:01:01 | 1:50:50 | yes | yes (slower plateau) |
| C, softcap 1500 | 15:19:31 | 3:58:22 | 2:03:47 | 1:26:57 | 1:14:02 | 1:06:04 | yes | weaker |

**Why A fails both ways.** At 1%/point a perk costing `c` at Legacy `L` gives up `c / (100 + L)` of
income. Founder's tier 1 (+5%, 80) is a net loss until L > 1500, Master Builders 1 until L > 3900,
Level Floor 2 until L > 4400 and every cosmetic forever. A player who buys anyway (naive) turns lap
1 into 51 hours; a player who does the arithmetic (rational, modelled: buy only when the loss is
below the perk's gain) buys nothing before lap 2 Era 4 and the laps run away exactly as today —
the shop is dead for its first eight hours of existence and never contains anything. AdCap-style
"spend your angels" only works when perks are worth many times their passive cost, which would
make the runaway worse, not better.

**Why B does not contain.** The passive is linear in Legacy, Legacy per lap grows ×1.5/×2/×2.5…
(`gainRebirthBonus`), and the perks stack ×1.28 × ~1.4 on top: lap 4 is under an hour, lap 6 under
half an hour, each with ~3,300 purchases — a clickfest.

**Why C works.** Above the softcap each *doubling* of Legacy adds only 693 effective points
(`S × ln 2`, i.e. +×6.9 on the multiplier), so laps 3–6 sit at ×19 → ×35 instead of ×23 → ×112, while the perk set (bought
out by lap 4 Era 3) provides the felt progression. Lap 2 (entry 887, under the cap) barely moves.
The plateau is a design knob: `softcap` 700 gives ~2 h laps, 1000 gives ~1.5 h, 1500 ~1.1 h.

Model C per era (softcap 1000, auto policy; "←" = bought on entering that era, cost in brackets):

| Lap | Era 1 Village | Era 2 Boomtown | Era 3 Metropolis | Era 4 Orbital Colony | Lap total |
|---|---|---|---|---|---|
| 1 | 41:50 (×1.00) | 1:44:06 (×1.78) ← Inheritance 1 (40) | 4:15:55 (×3.61) ← Founder's 1 (80), Long Memory 1 (80) | 8:37:40 (×6.29) ← Master Builders 1 (200), Inheritance 2 (90) | 15:19:31 |
| 2 | 3:21 (×9.91) ← Founder's 2 (160), Level Floor 1 (200) | 14:11 (×11.10) ← Long Memory 2 (160) | 1:00:37 (×13.52) ← Inheritance 3 (180) | 2:57:12 (×16.28) ← Master Builders 2 (400) | 4:15:21 |
| 3 | 1:33 (×19.10) ← Founder's 3 (300), Extra Milestone (350) | 7:04 (×19.79) | 33:20 (×21.24) ← Level Floor 2 (500) | 1:47:17 (×23.04) ← Founder's 4 (400) | 2:29:14 |
| 4 | 1:04 (×25.04) ← Master Builders 3 (650), Good Neighbours (250) | 4:52 (×25.53) | 23:05 (×26.59) ← Founder's 5 (550) | 1:20:33 (×27.96) ← Long Memory 3 (320), sign title (250) | 1:49:34 |
| 5 | 0:52 (×29.54) ← name-tag colour, monument glow, fireworks | 3:58 | 19:58 (×30.75) ← golden roads | 1:10:43 (×31.85) | 1:35:31 |

Bands, lap 1 with the shop: Era 2 1:44:06 (1:30–2:30), Era 3 4:15:55 (4:00–6:00), Era 4 8:37:40
(8:00–12:00) — all OK, with 16 and 37 minutes of margin on the two tight floors. Longest early
wait is unchanged (14 s). Same per-era table for Model B differs only from lap 2 Era 3 on
(59:06 / 2:40:41, then 1:17 / 5:36 / 24:34 / 1:12:00, then 0:40 / 2:52 / 12:41 / 40:36).

## 5. Price table, policy and affordability timeline

Purchase policy used by the sim (`PERK_POLICY`): buy in this order whenever the balance allows,
re-scanning from the top after each buy; purchases happen at era entry because Legacy only
changes on advance. Order = measured pacing value per Legacy, QoL after, cosmetics last.

| # | Purchase | Cost | Cumulative | Affordable at (Model C) | # | Purchase | Cost | Cumulative | Affordable at |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Inheritance 1 | 40 | 40 | lap 1 → Era 2 | 13 | Level Floor 2 | 500 | 2740 | lap 3 → Era 3 |
| 2 | Founder's 1 | 80 | 120 | lap 1 → Era 3 | 14 | Founder's 4 | 400 | 3140 | lap 3 → Era 4 |
| 3 | Long Memory 1 | 80 | 200 | lap 1 → Era 3 | 15 | Master Builders 3 | 650 | 3790 | lap 4 → Era 1 |
| 4 | Master Builders 1 | 200 | 400 | lap 1 → Era 4 | 16 | Good Neighbours | 250 | 4040 | lap 4 → Era 1 |
| 5 | Inheritance 2 | 90 | 490 | lap 1 → Era 4 | 17 | Founder's 5 | 550 | 4590 | lap 4 → Era 3 |
| 6 | Founder's 2 | 160 | 650 | lap 2 → Era 1 | 18 | Long Memory 3 | 320 | 4910 | lap 4 → Era 4 |
| 7 | Level Floor 1 | 200 | 850 | lap 2 → Era 1 | 19 | Sign title | 250 | 5160 | lap 4 → Era 4 |
| 8 | Long Memory 2 | 160 | 1010 | lap 2 → Era 2 | 20 | Name-tag colour | 300 | 5460 | lap 5 → Era 1 |
| 9 | Inheritance 3 | 180 | 1190 | lap 2 → Era 3 | 21 | Monument glow | 400 | 5860 | lap 5 → Era 1 |
| 10 | Master Builders 2 | 400 | 1590 | lap 2 → Era 4 | 22 | Advance fireworks | 500 | 6360 | lap 5 → Era 1 |
| 11 | Founder's 3 | 300 | 1890 | lap 3 → Era 1 | 23 | Golden roads | 600 | 6960 | lap 5 → Era 3 |
| 12 | Extra Milestone | 350 | 2240 | lap 3 → Era 1 | | | | | |

The sim's `SHOP:` line confirms 23 purchases, 6960 spent, 5450 unspent after lap 6. Against the
brief: lap 1 buys five tiers of four perks (490 of 887); laps 2–3 take the perks to 3140 (64% of
perk cost, 14 of 18 tiers); lap 4 finishes the perks; cosmetics are lap 4–5 prestige sinks. Under Model B the timeline is identical (Legacy earned does not depend
on the multiplier); under Model A almost nothing is ever affordable at a sane price.

## 6. Proposed `src/shared/Config/LegacyShop.json` schema (v1)

```json
{
  "version": 1,
  "perks": [
    {
      "id": "founders", "name": "Founder's Blessing", "cosmetic": false,
      "description": "Your legacy inspires everyone: +5% income per tier.",
      "effect": "incomeMult",
      "tiers": [ { "cost": 80, "value": 1.05 }, { "cost": 160, "value": 1.1025 },
                 { "cost": 300, "value": 1.1576 }, { "cost": 400, "value": 1.2155 },
                 { "cost": 550, "value": 1.2763 } ]
    },
    { "id": "builders",    "effect": "levelCostDiscount", "tiers": [ { "cost": 200, "value": 0.10 }, { "cost": 400, "value": 0.20 }, { "cost": 650, "value": 0.30 } ], "...": "..." },
    { "id": "inheritance", "effect": "startingSlots",     "tiers": [ { "cost": 40, "value": 3 }, { "cost": 90, "value": 5 }, { "cost": 180, "value": 8 } ], "...": "..." },
    { "id": "levelFloor",  "effect": "levelFloor",        "tiers": [ { "cost": 200, "value": 5 }, { "cost": 500, "value": 8 } ], "...": "..." },
    { "id": "milestone75", "effect": "extraMilestone",    "tiers": [ { "cost": 350, "value": 75 } ], "...": "..." },
    { "id": "neighbours",  "effect": "neighbours",        "tiers": [ { "cost": 250, "value": 0.04, "maxBonus": 0.36 } ], "...": "..." },
    { "id": "longMemory",  "effect": "offlineCapSeconds", "tiers": [ { "cost": 80, "value": 7200 }, { "cost": 160, "value": 14400 }, { "cost": 320, "value": 21600 } ], "...": "..." },
    { "id": "signTitle",   "cosmetic": true, "effect": "cosmetic", "tiers": [ { "cost": 250, "value": 0 } ], "...": "..." }
  ]
}
```

Rules: `value` is the **total** effect once that tier is owned (not per-tier), so a reader never
recomputes; `effect` is a closed enum and every tier of a perk shares it; `tiers` are bought in
order (server rejects anything but `ownedTier + 1`); `cosmetic: true` perks carry no gameplay
field and the client renders them from `id`; `id` is a persistence key like slot ids (never
renamed); a perk absent from the config but present in a profile is ignored, not an error. The
softcap is **not** here — it is `Game.json` → `legacy.softcap: 1000` (an `Economy` constant).

**PlayerState, schema v3 (additive):**

```lua
legacyShop: { spent: number, perks: { [string]: number } },  -- perkId -> tier owned (cosmetics: 1)
```

`spendable = legacy − legacyShop.spent`; `legacy` itself never decreases, so the HUD multiplier,
`LegacyGain` and every M5 table keep their meaning. Migration v2 → v3: `legacyShop = { spent = 0,
perks = {} }`. Should Ben later pick Model A after all, the migration is `legacy -= spent`, which
is why `spent` is stored rather than a second balance. New remote: `RequestBuyPerk(perkId)`
(intent only, rate-limited like `RequestBuy`; server validates tier order and balance). Analytics:
Sink, currency `legacy`, `Shop`, `itemSku = perk:<id>:<tier>`; Inheritance grant is a Source
`Gameplay`, `inheritance`.

## 7. `Economy.luau` changes needed (reported, not made)

| Function | Change |
|---|---|
| `LegacyMult(legacy, gameConfig)` | Softcap: `local s = gameConfig.legacy.softcap; local eff = if s ~= nil and legacy > s then s + s * math.log(legacy / s) else legacy; return 1 + incomePerPoint * eff`. Continuous and smooth at `s`; `softcap` optional so the current `Game.json` still typechecks and behaves identically. |
| `IncomePerSecond(slots, era, game, mults)` | `Multipliers` gains `perk: number` (Founder's Blessing), multiplied in like `legacy`; new pure `Economy.PerkIncomeMult(perks, shopConfig)`. `Types.Multipliers` changes with it. |
| `LevelUpCost` / `LevelUpCostTotal` | New trailing `discount: number?` (Master Builders; 0/nil today). Must be the **only** place the discount is applied so the Build panel preview and the server agree. |
| `SlotIncome(baseIncome, level, game)` | New trailing `milestoneLevels: { number }?` overriding `game.milestoneLevels` (Extra Milestone); `MilestoneMult` already takes the list. New pure `Economy.MilestoneLevels(perks, game, shopConfig)`. |
| `NeighborsMult(playerCount, game)` | New trailing `perPlayer: number?, maxBonus: number?` (Good Neighbours), defaults from `game.neighbors`. |
| `OfflineGrant` | Unchanged. The **caller** computes `capSeconds = (OfflinePro and capSecondsOfflinePro or capSeconds) + longMemorySeconds`; a pure `Economy.OfflineCapSeconds(passes, perks, game, shopConfig)` keeps the sim mirror honest. |
| new `Economy.InheritanceCash(eraConfig, slotCount)` | Sum of `baseCost` of the first `slotCount` slots in array order. Pure so the sim mirrors it. |
| new `Economy.LegacySpendable(state)` | `legacy − legacyShop.spent`. |
| `LegacyGain` | Unchanged. Level Floor levels count as levels (decision — see risks). |

`tools/sim_economy.py` then replaces its hardcoded `PERK_DEFS` with the config and `legacy_mult`
with the softcap formula; `--check` keeps judging the shop-less lap 1.

## 8. Risks and decisions for Ben

| Risk | Detail | Proposed handling |
|---|---|---|
| Inheritance vs the `requires` chain | Layouts branch (e.g. `flowerBed` and `houseSmallB` both require `well`), so "first N slots" is array order, not a chain. Granting *slots* would need chain logic and skip unlock beats. | Grant **cash only** (`InheritanceCash`) on era entry and on rebirth; the player still buys in order. Effect measured at ≤1% of lap 1. |
| Extra Milestone vs global `milestoneLevels` | `Game.json` is read directly by anything showing "next milestone" (Build panel, level-up prompt, HUD tooltips) and by `SlotIncome`. | Per-player list from `Economy.MilestoneLevels`, threaded through the snapshot so the client never reads `Game.milestoneLevels` for an owner's plot. |
| Level Floor at 10 | Milestone cliff: rusher Era 1 15:10 → 3:42, Era 4 14:40 → 2:21 — rushing becomes dominant from lap 3. | **Tier 2 = level 8** (rusher 8:17 / 5:45, greedy −6%). Floor levels count toward `LegacyGain` (greedy is unaffected — it ends above 8 anyway; a rusher gains +7 levels × 16 buildings, worth ~+11 Legacy per era, negligible). |
| Long Memory vs OfflinePro perceived value | Free player caps at 14 h at 50% (7 h of income); pass owner at 30 h at 100%. The pass is still 3.4× the free ceiling, and its copy ("24 hours instead of 8") stays literally true. | Shop copy says "+2 h on your offline cap", never a total; the welcome-back card already prints elapsed time so the sum is visible. Efficiency deliberately not sold (would erode the pass). |
| Softcap is a formula change one milestone after M5 | Lap 2 Era 3/4 move (1:10 → 1:00 with perks, 3:20 → 2:57); every M5 lap table gets a Model-C column. Lap 1, packs, paid deltas, rusher spread: unchanged. | Ship it with the shop, not before; `softcap` optional so M5 builds keep running. Knob: 700 for ~2 h late laps, 1000 (recommended) for ~1.5 h. |
| Runaway is contained, not stopped | Lap ratio under C tends to ~0.9; laps settle near 1:15 with the whole shop bought. Beyond lap 6 only cosmetics remain as sinks. | Acceptable for a four-era game; a fifth era or a second cosmetic wave is the long-run answer. |
| HUD honesty | Players will notice the multiplier slope changing past 1000 and Founder's Blessing must not look like a paid multiplier. | Multiplier breakdown row: `Legacy ×19.10 · Perks ×1.16 · Passes ×2.42`; softcap explained in the shop header. |
| Good Neighbours cap | `maxBonus` must scale with `perPlayer` (0.27 → 0.36) or the perk is worthless past 7 players. | Both values live on the tier (`value`, `maxBonus`). |
| Purchase timing | Legacy only moves on advance, so the shop is only "new" right after an advance/rebirth. | Open the shop tab once automatically after the advance ceremony (not a modal; §6 rule 3 is about Robux). |

## 9. Commands (prototype)

```
py tools/sim_economy.py --check                                  # unchanged, PASS
py tools/sim_economy.py --shop softcap --laps 6                  # Model C tables above
py tools/sim_economy.py --shop invest --laps 6                   # Model B
py tools/sim_economy.py --shop spend --laps 4                    # Model A, naive buyer
py tools/sim_economy.py --shop softcap --softcap 700 --laps 6    # plateau knob
py tools/sim_economy.py --perks levelfloor=2 --strategy rusher   # one perk, owned from the start
py tools/sim_economy.py --shop softcap --laps 2 --passes doublecash,vip --premium   # 2.42x check
```
