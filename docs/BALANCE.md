# BALANCE — final (M6)

Produced by `py tools/sim_economy.py` (mirrors `src/shared/Economy.luau` function-for-function
and reads the real configs — regenerate any table below by rerunning the commands in the last
section). The sim's greedy player buys the cheapest affordable thing (slots and level-ups)
every second; `--strategy rusher` buys slots only; `--laps K` rebirths between laps;
`--rebirth N` starts as a reborn player. `--check` (used by QA) exits nonzero if any era of
**lap 1** of the default greedy run misses its spec §4 band.

## Status at M5

- **Lap 1 (spec §4 bands): in band, unchanged since M2.** 41:50 / 1:44:15 / 4:28:49 / 9:25:10,
  longest early-game wait 14 s. The M5 sim additions produce byte-identical default, rusher,
  paid, packs and `--check` output (diffed before and after).
- **Second balance pass: no era config value moved, no `Game.json` change requested.** The
  evidence and the lap-2 decision are in "M5 — rebirth laps" below.
- **Lap 2: 4:51:29 (0.30× lap 1), lap 3: 2:29:07.** Adopted target and the alternative the lead
  can pick instead are both documented with numbers.
- **Paid stack 2.42×, packs capped at ≤ half an era, pricing ladder 1 : 2.2 : 4.2** — all
  unchanged from M4 and restated below.
- **M6 Legacy shop (Model C, softcap 1000): lap 1 with the shop 15:19:31, still in every band;
  laps 2–6 4:15 / 2:29 / 1:50 / 1:36 / 1:27.** Lap 1 without perks is byte-identical to M2;
  laps 2+ without perks move (softcap only) — see "M6 — Legacy shop" at the end.

---

# M2 — first full balance pass (lap 1, still current)

## Default run (greedy, legacy carried across advances)

| Era | Legacy in (mult) | Completed | Band | Longest wait | Wait ≤ 10 min | Legacy gained |
|-----|------------------|-----------|------|--------------|----------------|---------------|
| 1 Village | 0 (×1.00) | 41:50 | 30:00–45:00 OK | 14 s | 14 s | +78 (681 levels) |
| 2 Boomtown | 78 (×1.78) | 1:44:15 | 1:30–2:30 OK | 22 s | 5 s | +183 (815 levels) |
| 3 Metropolis | 261 (×3.61) | 4:28:49 | 4:00–6:00 OK | 58 s | 9 s | +268 (795 levels) |
| 4 OrbitalColony | 529 (×6.29) | 9:25:10 | 8:00–12:00 OK | 121 s | 14 s | +358 (795 levels) |

Total first playthrough: **16:20:04**, final legacy **887** (rebirth multiplier ×9.87 into the
second lap). No wait in any era's first ten minutes exceeds 14 s (pillar limit is 90 s).

Unlock beats (greedy): Era 1 — 7:16 / 18:18 / 29:30 / 41:25; Era 2 — 3:04 / 20:22 / 50:49 /
1:41:01; Era 3 — 4:54 / 50:04 / 2:20:50 / 4:22:54; Era 4 — 9:31 / 1:46:39 / 4:54:12 / 9:12:42.
Each era gets four pacing beats spread across its whole run.

## Rusher spread (slots only, legacy carried)

| Era | Rusher | Greedy | Spread |
|-----|--------|--------|--------|
| 1 Village | 15:10 | 41:50 | 2.76× faster |
| 2 Boomtown | 1:07:57 | 1:44:15 | 1.53× faster |
| 3 Metropolis | 5:05:52 | 4:28:49 | 0.88× (slower) |
| 4 OrbitalColony | 14:40:35 | 9:25:10 | 0.64× (much slower) |

M1 carry-over item: Era 1 rusher spread was 10:44 vs 40:29 (3.79×); it is now 15:10 vs 41:50
(**2.76×**). Pushing further would need either early slot costs high enough to break the
30–90 s early-purchase pillar or level-ups so dominant that greedy leaves band, so 2.76× is
where I stopped. Note the rusher only "wins" in Era 1 — from Era 2 on, skipping level-ups
means skipping the milestone income that funds the steep slot tails, so rushing is neutral in
Era 3 and strictly worse in Era 4. The exploit is confined to the shortest era and costs the
rusher ~85% of the legacy a greedy run banks (122 vs 887 after a full lap).

## What was tuned and why

**Greedy's pace ceiling is the most expensive slot, not the monument.** Cheapest-first means
every level-up cheaper than a slot gets bought before it, so an era's length is governed by
its cost tail. All tail tuning below exploits this: the tail sets greedy's grind, while the
same numbers divided by base (unleveled) income set the rusher's grind.

**Game.json:** `levelIncomeBonus` 0.10 → 0.12 and `levelCost.factor` 0.25 → 0.22. Both make
the leveling layer (which only a player who levels enjoys) more rewarding. This is what let
Era 1's slot costs steepen against the rusher while greedy stayed in band. All other Game.json
values are spec defaults.

**Era 1 (ids frozen, values retuned):** slot costs from `windmill` onward roughly doubled
(windmill 100K … chapel 1.2M, manor 1.6M), tail compressed to stables 2.0M / watchtower 2.2M /
wall 2.4M, monument 3.6M → 2.6M. Net: greedy 40:29 → 41:50 (still in band), rusher 10:44 →
15:10.

**Eras 2–4:** `baseIncome` is exactly ×100 per era (spec §4 magnitudes). Base costs are ×100
at the head of each era but the tails are progressively steeper — Era 2 tops out at 2.6B
(≈ ×1000 of Era 1's tail), Era 3 at 1.25T, Era 4 at 460T. This is deliberate: carried legacy
multiplies income ×1.78 / ×3.61 / ×6.29 into eras 2–4, and a uniform ×100 curve would collapse
under it (the raw drafts simulated at 24 min for Era 3 and 26 min for Era 4). Tails were scaled
until the default run sat mid-band **with** the carried legacy — eras must never be tuned in
isolation (`--era N --legacy 0` will read slow by design).

## Deviations from spec defaults

- **Costs are not uniformly ×100 per era** (incomes are). Required to outpace the legacy
  feedback loop while keeping era heads affordable in the first minutes; spec §4 says
  "roughly", and this is the roughly.
- **Monument cheaper than spec's implied top step in Era 1** (2.6M, just above the town wall).
  Consequence of the tail-compression that keeps greedy in band; the monument is still the
  final and most expensive slot in every era.
- **`levelCost.minBase` (100) is global**, so each era's free starter slot has Era 1-priced
  level-ups: the first minutes of eras 2–4 are a cheap "max the starter" burst (a maxed starter
  is ~3% of era income, so it is a fun spike, not a balance hole). If the feel is wrong in
  playtest, the fix is a per-era or per-slot minBase — that is an `Economy.luau`/schema change
  and is *not* made here.
- **Cash packs:** flagged at M2, resolved at M4 - see "Cash packs and the era cap" below.

---

# M4 — monetization pass (numbers still current)

Nothing in the M2 tables above changed at M4 or M5: no era, layout or `Game.json` value was
touched, and `py tools/sim_economy.py` produces byte-identical default output before and after
the M4 and M5 sim additions (diffed). All monetization constants live in
`src/shared/Config/Monetization.json`; the sim reads that file rather than restating any of it.

## Paid multiplier stack (spec section 6 rule 5)

| Source | Key | Multiplier | Applies to |
|--------|-----|-----------|------------|
| Game pass | `DoubleCash` | x2.0 | live, reported and persisted income |
| Game pass | `VIP` | x1.1 | live, reported and persisted income |
| Roblox Premium | - | x1.1 | live, reported and persisted income |
| Game pass | `OfflinePro` | x1 (income) | offline cap 8h -> 24h, efficiency 50% -> 100% |

`Economy.PassMult` x `Economy.PremiumMult` for a player who owns everything:

```
2.0 x 1.1 x 1.1 = 2.42
```

**2.42x, within the "<= ~2.4x" of rule 5** - the spec itself spells the stack as "2x pass x VIP
1.1 x Premium 1.1", so 2.42 is the intended number, not drift. `OfflinePro` deliberately carries
no income multiplier, which is what keeps the stack at 2.42 instead of compounding a third tier.
Nothing else in the game multiplies income for Robux; legacy and neighbours are earned.

## Paid vs. free pacing - convenience, never a gate

```
py tools/sim_economy.py                                     # free
py tools/sim_economy.py --passes doublecash,vip --premium   # fully paid
```

| Era | Free (default run) | Fully paid (x2.42) | Delta |
|-----|--------------------|--------------------|-------|
| 1 Village | 41:50 | 17:20 | -24:30 |
| 2 Boomtown | 1:44:15 | 43:09 | -1:01:06 |
| 3 Metropolis | 4:28:49 | 1:51:08 | -2:37:41 |
| 4 OrbitalColony | 9:25:10 | 3:53:36 | -5:31:34 |
| **Total** | **16:20:04** | **6:45:13** | **2.42x faster** |

The paid run finishes the whole game exactly 2.42x faster - income is linear in the multiplier
and an era's cost total is fixed, so the speed-up equals the stack and nothing else. A paying
player sees the same 24 slots, the same unlock beats and the same legacy (887 either way); they
just see them sooner. Legacy gain depends only on levels bought, so paying never buys prestige
power. The paid run reports `MISS` against the spec section 4 bands by design - the bands
describe the free player, and `--check` refuses to run with `--passes`/`--premium` so QA can
never accidentally band-check a paid run.

Longest early-game wait, fully paid: 5s / 4s / 6s / 8s (free: 14s / 5s / 9s / 14s) - well inside
the 90 s pillar either way.

Re-checked at M5 across two laps (`--laps 2 --passes doublecash,vip --premium`): the paid
player's lap 2 is 1:51 / 7:02 / 29:11 / 1:22:36 = **2:00:40** against the free player's 4:51:29
- again exactly 2.42x. The stack compresses time by the same constant in every era of every
lap and never changes what is built or the legacy banked, so the "convenience, never a progress
gate" reading holds after rebirth as well as before it.

## Cash packs and the era cap (replaces the M2 heads-up)

**Decision (lead ruling, INTERFACES.md M4 "Pack grant" + "Per-pack caps"):** packs stay priced
in minutes of the player's *current* income and are additionally capped as a fraction of the
current era's **total** slot cost. The cap fraction is **per pack**:

| Pack | `minutes` | `capFraction` | Largest possible single grant |
|------|-----------|---------------|-------------------------------|
| `Cash30m` | 30 | 0.10 | a tenth of the era's slot cost |
| `Cash2h` | 120 | 0.25 | a quarter of the era's slot cost |
| `Cash8h` | 480 | 0.50 | half of the era's slot cost |

`packCapFractionOfEraSlotCost` (**0.25**) stays in the config as the family default for any pack
that omits `capFraction`; today all three declare one, so the default is only a fallback for
packs added later. Packs are visible in every era - the M2 alternative of hiding
`Cash2h`/`Cash8h` before Era 3 is **dropped**. Capping against era *total* (not *remaining*)
cost is what stops a late-era purchase degrading to Robux-for-nothing.

```
capFraction = def.capFraction or cfg.packCapFractionOfEraSlotCost   -- caller side
PackGrant   = clamp(minutes x 60 x incomePerSecond, 0, capFraction x EraSlotCostTotal)
```

`Economy.PackGrant` itself is unchanged; only its callers (the server at receipt time, the
client's shop preview) pick the fraction. The income used is the server's **persisted-rate**
flavour (no Studio debug multiplier, neighbours pinned to 1), computed at receipt time, so
neither a client nor a Studio playtest can inflate a grant.

**Why per-pack, and not one global 0.25** (this is the M4 finding that produced the ruling):
with a single 0.25 cap, all three packs delivered the *identical* amount past roughly the first
10-20% of every era - a player paying the `Cash8h` price received exactly what `Cash30m` buys.
Splitting the ceiling 0.10 / 0.25 / 0.50 restores a real 1 : 2.5 : 5 ordering for the whole
capped phase while keeping every pack honestly described by its copy.

`py tools/sim_economy.py --packs` - grants at the free greedy player's income at the halfway
point of each era (unchanged at M5, re-run and diffed):

| Era | Era length | Total slot cost | Mid-era income | Pack | Cap | Uncapped value | Delivered | % of era | Real minutes |
|-----|-----------|-----------------|----------------|------|-----|----------------|-----------|----------|--------------|
| 1 Village | 41:50 | 14.97M | 64.49K/s | Cash30m | 1.50M | 116.08M | 1.50M | 10.0% | 0.4 |
| | | | | Cash2h | 3.74M | 464.33M | 3.74M | 25.0% | 1.0 |
| | | | | Cash8h | 7.49M | 1.86B | 7.49M | 50.0% | 1.9 |
| 2 Boomtown | 1:44:15 | 12.77B | 34.07M/s | Cash30m | 1.28B | 61.32B | 1.28B | 10.0% | 0.6 |
| | | | | Cash2h | 3.19B | 245.28B | 3.19B | 25.0% | 1.6 |
| | | | | Cash8h | 6.38B | 981.12B | 6.38B | 50.0% | 3.1 |
| 3 Metropolis | 4:28:49 | 6.40T | 6.12B/s | Cash30m | 639.96B | 11.01T | 639.96B | 10.0% | 1.7 |
| | | | | Cash2h | 1.60T | 44.04T | 1.60T | 25.0% | 4.4 |
| | | | | Cash8h | 3.20T | 176.15T | 3.20T | 50.0% | 8.7 |
| 4 OrbitalColony | 9:25:10 | 2345.61T | 1.07T/s | Cash30m | 234.56T | 1918.24T | 234.56T | 10.0% | 3.7 |
| | | | | Cash2h | 586.40T | 7672.95T | 586.40T | 25.0% | 9.2 |
| | | | | Cash8h | 1172.80T | 30691.81T | 1172.80T | 50.0% | 18.3 |

**The cap does the work, and spec section 6 rule 6 holds.** Uncapped, `Cash8h` bought mid-Era-1
would hand over 1.86B against a 14.97M era - **124x the entire era**, i.e. Era 1 and most of Era
2 in one tap. Capped, the largest single purchase possible anywhere in the game is **half** an
era's slot cost, so no pack skips an era at any income in any era, and the two smaller packs are
strictly further from doing so. This is independent of legacy and rebirth: the cap is a fraction
of a fixed cost total, so a reborn player with x9.87 income hits the cap sooner and gets exactly
the same ceiling.

**Why "minutes of income" inflates so hard here:** income grows exponentially inside an era
while the era's cost total is fixed, so past the first few minutes a player earns an era's worth
of cash in a few minutes. At mid-era, the *whole* of Era 1 is about 4 minutes of income. That is
why a nominal 30-minute pack delivers well under a real minute of income at mid-Era-1 and about
3.7 real minutes at mid-Era-4 - hence the mandatory honest copy: every pack row names whichever
limit produced its number (`30m of income - $4.5M` while minutes bind, `10% of this era -
$1.2B` once the cap does; INTERFACES.md M4 amendment 8).

Where each pack starts hitting its own cap in the free default run:

| Era | `Cash30m` (0.10) capped from | `Cash2h` (0.25) | `Cash8h` (0.50) |
|-----|-----------------------------|-----------------|-----------------|
| 1 Village | 5:48 (14% in) | 4:56 (12%) | 4:14 (10%) |
| 2 Boomtown | 4:28 (4%) | 3:09 (3%) | 1:49 (2%) |
| 3 Metropolis | 12:47 (5%) | 9:50 (4%) | 4:54 (2%) |
| 4 OrbitalColony | 49:48 (9%) | 38:23 (7%) | 20:00 (4%) |

(Both tables come from `py tools/sim_economy.py --packs`; the cap-onset table is the same
simulation read at every second instead of only at the halfway point.)

**Is the value ordering honest for the whole era? Yes - no two packs ever deliver the same
amount.** `delivered = min(minutes x 60 x ips, capFraction x eraTotal)`, and both arguments are
strictly increasing across the three packs (30 < 120 < 480 minutes, 0.10 < 0.25 < 0.50), so the
minimum of them is strictly increasing too - there is no income, and therefore no era phase, at
which two packs tie. Only the *ratio* changes with era phase:

| Phase | When | Delivered ratio `Cash30m : Cash2h : Cash8h` |
|-------|------|--------------------------------------------|
| Uncapped (early era) | first 2-14% of an era (table above) | 1 : 4 : 16 (the nominal minutes) |
| Capped (rest of the era) | the remaining 86-98% | 1 : 2.5 : 5 (the cap fractions) |

## Pricing-ladder note for Ben (unchanged at M5)

Robux prices are not set by any config; when pricing the three developer products on Creator
Hub, price the packs no steeper than the ratio that holds for almost the whole era, i.e.
`Cash2h` at most 2.5x and `Cash8h` at most 5x the `Cash30m` price. Roughly **1 : 2.2 : 4.2** is
the honest choice - it keeps the usual "bigger bundle is slightly better value" shape instead of
inverting it, in every era phase. A price ladder steeper than 1 : 2.5 : 5 (for example 1 : 4 :
16, matching the nominal minutes) would make the big packs worse value than the small one for
86-98% of every era, which the pack copy alone would not excuse. Nothing in the M5 pass changes
this: the delivered ratios depend only on `minutes` and `capFraction`, neither of which moved.

## Analytics taxonomy (what shows up on the dashboards)

`AnalyticsService` wraps Roblox's `AnalyticsService`; every call is inside `pcall` and degrades
to a no-op. Currency names are exactly `cash` and `legacy`; balances are integers. Income ticks
are **never** logged (1 Hz per player would swamp the quota), and one `RequestLevelUp` granting
`n` levels logs **one** event.

| Event | Flow | Currency | Transaction type | `itemSku` |
|-------|------|----------|------------------|-----------|
| Slot bought | Sink | cash | `Shop` | `slot:<eraName>:<slotId>` |
| Level-up (per action) | Sink | cash | `Shop` | `level:<eraName>:<slotId>` |
| Offline grant | Source | cash | `TimedReward` | `offline` |
| Product grant | Source | cash | `IAP` | `product:<productKey>` |
| Legacy on advance/rebirth | Source | legacy | `Gameplay` | `era:<eraIndex>` |

Progression: one `LogProgressionEvent` per era advance and per rebirth, category
`EraProgression`, level = the completed era index.

How to read them: sink SKUs show which slots and which levels absorb cash (compare with the cost
tails in the M2 section); `product:*` sources against the pack table above show whether real
purchases land where the cap predicts; `offline` volume against session count shows whether
`OfflinePro` earns its price. The four `EraProgression` levels should produce drop-off steps
matching the free pacing column, with paying players arriving at each step about 2.42x earlier.
A second `era:1` legacy source for the same player marks a rebirth; the lap-2 table below
predicts how much sooner each `EraProgression` step should recur.

## Monetization constants and why

| Constant | Value | Reason |
|----------|-------|--------|
| `multipliers.doubleCash` | 2.0 | Spec section 6 pass table. |
| `multipliers.vip` | 1.1 | Spec section 6 pass table (+10% income). |
| `multipliers.premium` | 1.1 | Spec section 6 Premium. Stack = 2.42, rule 5 satisfied. |
| `packCapFractionOfEraSlotCost` | 0.25 | Family default for any pack without its own `capFraction`; all three current packs declare one. |
| `capFraction` 0.10 / 0.25 / 0.50 | per pack | Anti-skip ceiling per pack. Uncapped, `Cash8h` is 124x Era 1; a single global 0.25 made all three packs deliver the identical amount past ~10-20% into an era. |
| `receiptHistoryLimit` | 200 | FIFO idempotency window - far beyond any plausible Roblox retry horizon, and small in the profile. |
| `minutes` 30 / 120 / 480 | spec section 6 | Nominal, pre-cap; the UI copy names whichever limit binds. |
| every `id` | Creator Hub ids | Pasted 2026-09-09; an `id` of `0` hides the item everywhere (spec section 6 implementation notes). |

---

# M5 — rebirth laps and the second balance pass

## Sim additions

- `--rebirth N` (default 0): starting `rebirthCount`, fed to `legacy_gain` exactly as the server
  passes `state.rebirthCount` to `Economy.LegacyGain` (M2 carry-over: the sim hardcoded 0).
- `--laps K` (default 1): K consecutive laps of eras 1..4, rebirthing between laps (era → 1,
  `rebirthCount += 1`, legacy kept — what `RequestRebirth` does), printing the per-era block for
  every lap plus per-lap and grand totals. Lap headers appear only when `--laps > 1` or
  `--rebirth > 0`, so the plain run is untouched.
- `--check` still judges **lap 1 only** (the spec §4 bands describe a first playthrough) and
  refuses `--rebirth` (it would change lap 1's legacy carry).
- Verified: default, `--strategy rusher`, `--passes doublecash,vip --premium`, `--packs` and
  `--check` outputs captured before the change and diffed after — all five byte-identical.

## Lap 2 and lap 3 (`py tools/sim_economy.py --laps 3`)

Lap 1 is the M2 table above (identical). Rebirth carries 887 legacy and `rebirthCount` 1 into
lap 2, 2217 and `rebirthCount` 2 into lap 3.

| Lap 2 | Legacy in (mult) | Completed | vs lap 1 | Longest wait | Wait ≤ 10 min | Legacy gained |
|-------|------------------|-----------|----------|--------------|----------------|---------------|
| 1 Village | 887 (×9.87) | 4:20 | 9.65× faster | 2 s | 2 s | +117 (681 levels) |
| 2 Boomtown | 1004 (×11.04) | 16:54 | 6.17× faster | 4 s | 4 s | +274 (815 levels) |
| 3 Metropolis | 1278 (×13.78) | 1:10:29 | 3.81× faster | 16 s | 5 s | +402 (795 levels) |
| 4 OrbitalColony | 1680 (×17.80) | 3:19:46 | 2.83× faster | 43 s | 7 s | +537 (795 levels) |
| **Lap 2 total** | | **4:51:29** | **3.36× faster** | | | legacy 2217 |

Lap-2 unlock beats: Era 1 — 0:47 / 1:56 / 3:04 / 4:17; Era 2 — 0:33 / 3:21 / 8:16 / 16:23;
Era 3 — 1:19 / 13:10 / 36:57 / 1:08:56; Era 4 — 3:24 / 37:44 / 1:44:01 / 3:15:22.

| Lap 3 | Legacy in (mult) | Completed | vs lap 1 | Longest wait | Wait ≤ 10 min | Legacy gained |
|-------|------------------|-----------|----------|--------------|----------------|---------------|
| 1 Village | 2217 (×23.17) | 1:54 | 22.0× faster | 1 s | 1 s | +156 |
| 2 Boomtown | 2373 (×24.73) | 7:35 | 13.7× faster | 2 s | 2 s | +366 |
| 3 Metropolis | 2739 (×28.39) | 34:16 | 7.8× faster | 8 s | 5 s | +537 |
| 4 OrbitalColony | 3276 (×33.76) | 1:45:22 | 5.4× faster | 23 s | 6 s | +716 |
| **Lap 3 total** | | **2:29:07** | **6.6× faster** | | | legacy 3992 |

Three laps back to back: **23:40:40**, final legacy 3992, `rebirthCount` 3. The legacy gained
per era grows ×1.5 / ×2.0 per lap from `gainRebirthBonus` (0.5), which is why lap 3 compresses
faster than lap 2 did.

## The lap-2 decision

**Adopted target:** lap 2 finishes in a quarter to a half of lap 1's time, every era is at
least 2.5× faster than lap 1 (so the rebirth is felt in every era, not just the Village), the
purchase set and therefore the legacy gained are identical to lap 1 (rebirth does not change
what the player builds, only how fast), and the 90 s early-wait pillar holds. **Met:** 0.30× of
lap 1, per-era 9.65× / 6.17× / 3.81× / 2.83×, 681 / 815 / 795 / 795 levels in every lap, longest
early wait 7 s.

**The recommended stricter target ("no era under half its lap-1 band floor": ≥ 15:00 / 45:00 /
2:00:00 / 4:00:00) is not met and cannot be met by the era configs.** Greedy buys the same
purchases in the same order in every lap (the set of things cheaper than the monument depends
only on cost ordering), so an era's time is its fixed cost total divided by income, and income
is linear in the legacy multiplier. Lap-2 ÷ lap-1 time per era is therefore just
`legacyMult(lap-1 entry) ÷ legacyMult(lap-2 entry)` — ×1.00 ÷ ×9.87 for Era 1, ×6.29 ÷ ×17.80
for Era 4 — and both laps read the same `Eras/*.json`, so no `baseCost`/`baseIncome`/
`multiplier` value can move that ratio; it only moves lap 1 and lap 2 together. Meeting the
stricter target needs the legacy multiplier itself to shrink, which is `Game.json`.

**The `Game.json` route, quantified (not applied — for the lead to choose):** in-memory runs
with the sim's own functions, `legacy.incomePerPoint` overridden and Era 2–4 `baseCost`s
uniformly scaled (uniform scaling preserves purchase order, hence legacy):

| `incomePerPoint` | Era 2–4 cost scale to keep lap 1 mid-band | Lap-1 legacy mults (E2/E3/E4) | Lap 1 | Lap 2 (E1 / E2 / E3 / E4) | Lap 3 |
|---|---|---|---|---|---|
| 0.01 (current) | 1 / 1 / 1 | ×1.78 / ×3.61 / ×6.29 | 41:50 / 1:44 / 4:29 / 9:25 | 4:20 / 16:54 / 1:10 / 3:20 | 1:54 / 7:35 / 34:16 / 1:45 |
| 0.005, no retune | — | ×1.39 / ×2.30 / ×3.65 | 41:50 / 2:13 / **7:01** / **16:15** (out of band) | 7:47 / 30:54 / 2:11 / 6:18 | — |
| 0.002, no retune | — | ×1.16 / ×1.52 / ×2.06 | 41:50 / **2:40** / **10:37** / **28:47** (out of band) | 15:09 / 1:01:44 / 4:32 / 13:35 | — |
| **0.002, retuned** | 0.745 / 0.470 / 0.347 | ×1.16 / ×1.52 / ×2.06 | 41:50 / 2:00 / 5:00 / 10:00 | **15:09 / 46:10 / 2:08 / 4:43** | 7:47 / 24:14 / 1:10 / 2:43 |

`incomePerPoint` must drop to **0.002** (the exact threshold: 41:50 ÷ 15:00 = 2.79 = 1 + 887 ×
0.002) before Era 1 of lap 2 clears 15 minutes; 0.005 does not get there. That change is
mechanically simple — one key plus scaling every Era 2/3/4 `baseCost` by 0.745 / 0.470 / 0.347 —
but its cost is the point of legacy inside lap 1: a finished Village would show "×1.16" on the
HUD instead of "×1.78", and a whole first playthrough's legacy would be worth ×2.06 into Era 4
instead of ×6.29. It also re-baselines every table in this file (packs, cap onset, paid deltas,
rusher spread) and the Studio-playtested feel of eras 2–4 one milestone before ship, and lap 3
lands back where lap 2 is today (7:47 Village) — it delays the collapse by one lap rather than
removing it.

**My call as designer: keep 0.01 and the current era files for the MVP.** The first lap is the
product spec §4's bands describe and it is in band; the second lap is a victory lap whose
Village and Boomtown fly by (4 and 17 minutes, no wait over 4 s, the same unlock beats and
legacy), while Metropolis and the Orbital Colony still take 1:10 and 3:20 — a reborn player's
evening. The runaway across laps is real (lap 3 at 2:29, lap 4 would be near an hour) but it is
the `gainRebirthBonus` term of the spec's own formula doing what it says, and the MVP has four
eras and no Legacy shop to spend into; the Phase 2 Legacy shop (spec §3) is the natural place
to turn accumulated legacy into perks instead of raw multiplier, which is the durable fix for
lap 3+. If Ben wants the stricter lap-2 shape now, the exact change is
**`legacy.incomePerPoint` 0.01 → 0.002 in `Game.json`** plus the Era 2–4 cost scaling above;
the harness is ready and it is a one-session job that re-baselines `--check`.

## Rusher spread after rebirth

Unchanged in structure: the rusher's ratio to greedy is independent of the legacy multiplier
(both players' times scale by the same factor), so lap-2 rusher times are the M2 spread divided
by the same ×9.87 / ×6.20 / ×3.82 / ×2.83 factors — the Era 1 exploit is about 1:34 against
greedy's 4:20 in lap 2, and rushing stays neutral-to-worse from Era 3 on.

## Early-wait pillar across laps

Longest wait in the first ten minutes: lap 1 14 s / 5 s / 9 s / 14 s, lap 2 2 s / 4 s / 5 s /
7 s, lap 3 1 s / 2 s / 5 s / 6 s (limit 90 s). Longest wait anywhere in an era: lap 1 14 s /
22 s / 58 s / 121 s (the 121 s is Era 4's `launchTower`, past the nine-hour mark — the one
wait the greedy player ever sees above two minutes), lap 2 2 s / 4 s / 16 s / 43 s.

## Commands used

```
py tools/sim_economy.py                                      # lap 1 (M2 tables), default run
py tools/sim_economy.py --check                              # lap 1 band check, exits 0
py tools/sim_economy.py --strategy rusher                    # rusher spread
py tools/sim_economy.py --packs                              # pack grants and caps per era
py tools/sim_economy.py --passes doublecash,vip --premium    # fully-paid lap 1
py tools/sim_economy.py --laps 3                             # laps 1-3, rebirth between laps
py tools/sim_economy.py --laps 2 --passes doublecash,vip --premium   # fully-paid two laps
py tools/sim_economy.py --rebirth 1 --era 1 --legacy 887     # Era 1 as a first-rebirth player
py tools/gen_asset_manifest.py --check                       # era configs still valid
```

---

# M6 — Legacy shop (Model C "invest + softcap", numbers from the real config)

Everything below is `py tools/sim_economy.py --perks auto --laps 6` and friends reading
`src/shared/Config/LegacyShop.json` and `Game.json` (`legacy.softcap = 1000`). The prototype
tables in `docs/LEGACY_SHOP.md` were re-derived from the shipped config and reproduce to the
second: the config carries exactly the §2/§3 numbers, and the sim's hardcoded `PERK_DEFS` is gone.

## Sim changes (mirrors `docs/INTERFACES.md` "Economy.luau — exact signatures")

- `legacy_mult` softcaps: `eff = s + s·ln(legacy / s)` when `legacy > s`, `s = legacy.softcap`
  (absent key ⇒ linear). `slot_income` / `income_per_second` take a trailing `milestone_levels`;
  `level_up_cost` / `level_up_cost_total` a trailing `discount` — applied inside `level_up_cost`
  only, never at a call site; `neighbors_mult` trailing `per_player, max_bonus`; `mults["perk"]` is
  multiplied in beside `legacy`.
- New mirrors, same names in snake_case: `perk_tier, perk_value, perk_income_mult,
  level_cost_discount, level_floor, milestone_levels, neighbors_params, offline_cap_seconds,
  inheritance_cash, legacy_spendable, next_perk_tier`. `load_legacy_shop_config` returns
  `{version 1, perks []}` when the file is missing (Catalog's behaviour) and validates the v1 schema
  (closed `effect` enum, cosmetic ⇔ one tier at value 0, `maxBonus` on `neighbours`, description
  ≤ 90 chars) so a broken config fails `--check` loudly.
- CLI: `--shop` and the spend/invest models are gone (their numbers stay in LEGACY_SHOP.md §4).
  `--perks auto` runs the purchase policy at every era entry; `--perks id=tier,...` owns perks from
  the start at no cost (ids are the frozen camelCase ids); `--softcap N` overrides `Game.json` for
  exploration (`0` = linear). `--check` refuses both.
- **Byte-identity, diffed before/after:** default, `--packs`, `--strategy rusher`, `--strategy
  rusher --laps 2`, `--passes doublecash,vip --premium`, `--era 2 --legacy 50`, `--rebirth 1 --era
  1` and `--check` are identical. **`--laps 2+` without perks is NOT** — the softcap now lives in
  `Economy.LegacyMult` itself and lap 2 Era 2 enters at 1004 Legacy, so from lap 2 Era 3 on the
  passive multiplier is lower than the M5 tables (lap 2 4:51:29 → 5:13:06, lap 3 2:29:07 → 3:33:29,
  lap 6 45:28 → 2:18:18). That is the design working, not drift; the M5 lap tables above are the
  pre-softcap baseline and are kept for the comparison.

## Lap 1–6 per era, greedy, free, auto policy (`--perks auto --laps 6`)

"←" = bought on entering that era (cost in brackets). Multiplier = `LegacyMult` of the Legacy
carried in; Founder's Blessing is on top of it.

| Lap | Era 1 Village | Era 2 Boomtown | Era 3 Metropolis | Era 4 Orbital Colony | Lap total | Legacy after |
|---|---|---|---|---|---|---|
| 1 | 41:50 (×1.00) | 1:44:06 (×1.78) ← Inheritance 1 (40) | 4:15:55 (×3.61) ← Founder's 1 (80), Long Memory 1 (80) | 8:37:40 (×6.29) ← Master Builders 1 (200), Inheritance 2 (90) | **15:19:31** | 891 |
| 2 | 3:21 (×9.91) ← Founder's 2 (160), Level Floor 1 (200) | 14:11 (×11.10) ← Long Memory 2 (160) | 1:00:37 (×13.52) ← Inheritance 3 (180) | 2:57:12 (×16.28) ← Master Builders 2 (400) | **4:15:21** | 2247 |
| 3 | 1:33 (×19.10) ← Founder's 3 (300), Extra Milestone (350) | 7:04 (×19.79) | 33:20 (×21.24) ← Level Floor 2 (500) | 1:47:17 (×23.04) ← Founder's 4 (400) | **2:29:14** | 4071 |
| 4 | 1:04 (×25.04) ← Master Builders 3 (650), Good Neighbours (250) | 4:52 (×25.53) | 23:05 (×26.59) ← Founder's 5 (550) | 1:20:33 (×27.96) ← Long Memory 3 (320), Sign Title (250) | **1:49:34** | 6387 |
| 5 | 0:52 (×29.54) ← Name-Tag Colour (300), Monument Glow (400), Advance Fireworks (500) | 3:58 (×29.92) | 19:58 (×30.75) ← Golden Roads (600) | 1:10:43 (×31.85) | **1:35:31** | 9167 |
| 6 | 0:48 (×33.16) | 3:33 (×33.47) | 17:59 (×34.15) | 1:04:13 (×35.07) | **1:26:33** | 12410 |

Lap 1 bands with the shop: Era 1 41:50 (30–45 min), Era 2 1:44:06 (1:30–2:30), Era 3 4:15:55
(4–6 h), Era 4 8:37:40 (8–12 h) — all in band, 16 and 38 minutes of margin on the two tight floors.
Longest early-game wait is unchanged at 14 s (Era 1 and Era 4); longest wait anywhere 113 s
(Era 4 `launchTower`, was 121 s). Lap ratios 0.28 → 0.58 → 0.73 → 0.87 → 0.91; the plateau is
about 1:15 with the whole shop bought. `SHOP:` line: 23 purchases, 6960 spent, 5450 spendable
after lap 6, passive ×36.19.

Same six laps with the softcap but **no perks** (`--laps 6`): 16:20:04 / 5:13:06 / 3:33:29 /
2:54:29 / 2:32:38 / 2:18:18 — the perks are worth roughly a third of each late lap, which is the
felt progression the shop exists to provide.

## Purchase timeline (auto policy, as the sim bought them)

| # | Purchase | Cost | Cum. | Bought at | # | Purchase | Cost | Cum. | Bought at |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Inheritance 1 | 40 | 40 | lap 1 → Era 2 | 13 | Level Floor 2 | 500 | 2740 | lap 3 → Era 3 |
| 2 | Founder's 1 | 80 | 120 | lap 1 → Era 3 | 14 | Founder's 4 | 400 | 3140 | lap 3 → Era 4 |
| 3 | Long Memory 1 | 80 | 200 | lap 1 → Era 3 | 15 | Master Builders 3 | 650 | 3790 | lap 4 → Era 1 |
| 4 | Master Builders 1 | 200 | 400 | lap 1 → Era 4 | 16 | Good Neighbours | 250 | 4040 | lap 4 → Era 1 |
| 5 | Inheritance 2 | 90 | 490 | lap 1 → Era 4 | 17 | Founder's 5 | 550 | 4590 | lap 4 → Era 3 |
| 6 | Founder's 2 | 160 | 650 | lap 2 → Era 1 | 18 | Long Memory 3 | 320 | 4910 | lap 4 → Era 4 |
| 7 | Level Floor 1 | 200 | 850 | lap 2 → Era 1 | 19 | Sign Title | 250 | 5160 | lap 4 → Era 4 |
| 8 | Long Memory 2 | 160 | 1010 | lap 2 → Era 2 | 20 | Name-Tag Colour | 300 | 5460 | lap 5 → Era 1 |
| 9 | Inheritance 3 | 180 | 1190 | lap 2 → Era 3 | 21 | Monument Glow | 400 | 5860 | lap 5 → Era 1 |
| 10 | Master Builders 2 | 400 | 1590 | lap 2 → Era 4 | 22 | Advance Fireworks | 500 | 6360 | lap 5 → Era 1 |
| 11 | Founder's 3 | 300 | 1890 | lap 3 → Era 1 | 23 | Golden Roads | 600 | 6960 | lap 5 → Era 3 |
| 12 | Extra Milestone | 350 | 2240 | lap 3 → Era 1 | | | | | |

The policy (`PERK_POLICY` in the sim, tool-only) is ordered by measured pacing value per Legacy,
QoL after, cosmetics last in config order. Lap 1 buys five tiers (490 of 891); laps 2–3 reach 14 of
18 perk tiers; lap 4 finishes the perks; cosmetics are lap 4–5 prestige sinks.

## Paid stack re-verification with perks (`--perks auto --laps 2 --passes doublecash,vip --premium`)

| | Free | DoubleCash + VIP + Premium | Ratio |
|---|---|---|---|
| Lap 1 | 15:19:31 | 6:20:08 (17:20 / 43:04 / 1:45:47 / 3:33:57) | 2.419× |
| Lap 2 | 4:15:21 | 1:45:40 (1:26 / 5:54 / 25:05 / 1:13:15) | 2.417× |

No perk touches `PassMult` / `PremiumMult`, and the perk purchase timeline is identical for the
paid player (Legacy earned does not depend on the multiplier), so the paid stack stays exactly
2.42× with the shop in play. Convenience, never a gate (spec §6 rule 5).

## Softcap knob (`--softcap N`, `--perks auto --laps 6`)

| `legacy.softcap` | Lap 1 | Lap 2 | Lap 3 | Lap 4 | Lap 5 | Lap 6 | Passive after lap 6 |
|---|---|---|---|---|---|---|---|
| 700 | 15:19:31 | 4:48:25 | 3:00:54 | 2:16:36 | 2:01:01 | 1:50:50 | ×28.13 |
| **1000 (shipped)** | **15:19:31** | **4:15:21** | **2:29:14** | **1:49:34** | **1:35:31** | **1:26:33** | **×36.19** |
| 1500 | 15:19:31 | 3:58:22 | 2:03:47 | 1:26:57 | 1:14:02 | 1:06:04 | ×47.70 |

Lap 1 never sees the cap (max Legacy at any lap-1 era entry is 529; lap-1 total 891). 700 gives
~2 h late laps, 1000 ~1.5 h, 1500 ~1.1 h — a one-key change in `Game.json` if Studio play says the
plateau is wrong.

## Rusher with the shop

`--perks levelFloor=2 --strategy rusher`: Era 1 8:17 (greedy 41:50, no-perk rusher 15:10) —
the reason Level Floor tier 2 is 8, not 10 (LEGACY_SHOP.md §8). `--perks auto --laps 2 --strategy
rusher`: the rusher earns too little Legacy to buy anything before lap 2 (122 after lap 1) and
finishes lap 2 in 10:03:09 against greedy's 4:15:21 — rushing stays worse from Era 3 on.

## Config decisions and deviations from LEGACY_SHOP.md

- **Founder's `value`s are exact powers of 1.05** (1.157625, 1.21550625, 1.2762815625) rather than
  the 4-decimal roundings in §6, so the HUD breakdown (`Perks ×1.28`) and the sim agree to the bit.
- **Long Memory `value`s are total seconds** (7200 / 14400 / 21600) per the contract ("value = total
  effect"); the description says "+2 h on your offline cap per tier" and never a total.
- **Level Floor 5 / 8** as approved; **Good Neighbours `value` 0.04 with `maxBonus` 0.36** on the tier.
- Cosmetic colours: `nameTagColour` `#2FB8D9` (teal, clearly not VIP gold), `goldenRoads` `#E3B341`
  (warm gold). `signTitle.titles`: Founder, Magnate, Tycoon, Sovereign, Eternal.
- Nothing else deviates: costs, tiers, ids and display order are the §2/§3 tables verbatim.
- Not changed: `Game.json` values other than the lead's `legacy.softcap = 1000`; every `Eras/*.json`
  and `Layouts/**` is frozen and untouched, which is why lap 1 without perks is byte-identical.

## Commands used

```
py tools/sim_economy.py --check                                        # lap 1 bands, exits 0
py tools/sim_economy.py --perks auto --laps 6                          # Model C tables above
py tools/sim_economy.py --laps 6                                       # softcap, no perks
py tools/sim_economy.py --perks auto --laps 6 --softcap 700            # knob table
py tools/sim_economy.py --perks auto --laps 6 --softcap 1500
py tools/sim_economy.py --perks auto --laps 2 --passes doublecash,vip --premium   # 2.42x
py tools/sim_economy.py --perks levelFloor=2 --strategy rusher         # Level Floor cliff check
py tools/sim_economy.py --perks auto --laps 2 --strategy rusher
py tools/gen_asset_manifest.py --check                                 # era configs still valid
```

---

# M9 — City growth tiers

`py tools/sim_economy.py` now mirrors `CityGrowth.Score` (`owned × ownedWeight + Σ levels`) and
`CityGrowth.TierFor` (count of thresholds ≤ score) 1:1, reading `tier` from
`src/shared/Config/CityDressing.json`. Every era line gains `city growth tiers`: the first second
the greedy player reaches each tier 1–5. The line shows it as a % of that run's completion (`run`)
and of the band midpoint in spec §4 (`tgt`). The score is re-evaluated after every slot buy and
level-up, which is exactly when the server republishes `GrowthTier`. Nothing else in the output
moved, and `--check` still passes.

Tuning target (INTERFACES M9): tier 1 on the first purchase, tier 3 by ~40 % and tier 5 by ~80 %
of the era.

## Applied (Ben, 2026-09-16): `ownedWeight 50`, thresholds `[50, 400, 950, 1350, 1600]`

Lap 1 greedy, % of the run:

| Era | length | T1 | T2 | T3 | T4 | T5 |
|-----|--------|----|----|----|----|----|
| Village | 41:50 | 0:00 | 7:16 (17 %) | 18:18 (44 %) | 29:30 (71 %) | 36:33 (87 %) |
| Boomtown | 1:44:15 | 0:00 | 2:03 (2 %) | 15:18 (15 %) | 39:52 (38 %) | 1:13:48 (71 %) |
| Metropolis | 4:28:49 | 0:00 | 2:44 (1 %) | 35:53 (13 %) | 1:48:30 (40 %) | 3:23:13 (76 %) |
| OrbitalColony | 9:25:10 | 0:00 | 4:54 (1 %) | 1:14:58 (13 %) | 3:47:47 (40 %) | 7:06:20 (75 %) |

## Why v1 was replaced

v1 was `ownedWeight 10`, thresholds `[10, 80, 250, 600, 1200]`:

| Era | T1 | T2 | T3 | T4 | T5 |
|-----|----|----|----|----|----|
| Village | 0:00 | 3:51 (9 %) | 8:27 (20 %) | 23:43 (57 %) | never |
| Boomtown | 0:00 | 0:19 (0 %) | 3:04 (3 %) | 24:35 (24 %) | never |
| Metropolis | 0:00 | 0:02 (0 %) | 3:35 (1 %) | 1:03:13 (24 %) | never |
| OrbitalColony | 0:00 | 0:01 (0 %) | 6:41 (1 %) | 2:11:48 (23 %) | never |

- **Tier 5 was unreachable.** An era ends at a score of 921 (Village) to 1055 (Boomtown), below
  1200, so the last spine, the last lots and every tree's final stage never showed. Tiers 2–3 also
  landed in the first minutes of Eras 2–4.
- **The first purchase still lands tier 1.** It scores `ownedWeight + 1`, so `T1 = ownedWeight` is
  reached on the first purchase in every era.
- **Tier 5 is now reachable everywhere, at 71–87 %.**
- **A heavier owned weight is the lever.** Slot purchases are spread across an era by their costs,
  while level-ups bunch up in the early minutes of Eras 2–4. A grid search over weights 10–1000
  (fitting each threshold to the target across all four eras) improves up to about 50 and flattens
  after that. At weight 10 the best global fit still puts Village tier 5 at 96 %.
- **The residual miss is structural.** With one global list, Village (no Legacy) and Eras 2–4
  (Legacy carried) climb the score curve at different rates. Tier 3 lands at 44 % in Village but
  13–15 % later. The early tiers only add roads, lots and saplings, so arriving early in later eras
  reads as "a returning mayor builds fast" and is acceptable.
- **Per-era thresholds: considered and deferred.** `eras.<Era>.tier.thresholds` at weight 10 would
  hit the target almost exactly (Village `[10, 235, 460, 610, 740]`, Boomtown
  `[10, 560, 740, 810, 935]`, Metropolis/Orbital `[10, 560, 730, 790, 915]`). It needs a schema and
  `CityGrowth` caller change, so Ben kept one global list.
- Laps 2+ compress all of this proportionally. Tiers are cosmetic, so nothing gates on them.

## Commands used

```
py tools/sim_economy.py                  # tier timeline on every era line
py tools/sim_economy.py --check          # bands still pass, exits 0
py tools/sim_economy.py --laps 2         # tier timeline per lap
py tools/streetplan.py                   # street plans vs clearance rules (P1/P2), PNGs per era
```

# C0 — Armory unlocks and the Village expedition

New tool: `tools/sim_combat.py`. It mirrors `src/shared/Armory.luau` and `src/shared/Combat.luau`
function for function (same names in snake_case, each with the Luau name in its docstring) from
`docs/INTERFACES.md` "C0 contracts", reads the four real configs (`Armory.json`, `Combat.json`,
`Places.json`, `Missions/*.json`), and **imports `sim_economy`** — `simulate_era(..., record_ips=True)`
run era by era with Legacy carried, exactly as `run_full`/`run_packs` do — so the tycoon income
curve is never re-derived and the two tools can never disagree. `--check` prints one verdict line
per assertion and exits 1 on any failure; the default run prints the unlock ladder, the modelled
Village run at recommended / 2× / 0.6× power, the cash-vs-era-cost ratio, a survivability estimate
and spot checks of the helpers that have no table (`ContributionShares`, `AwayEfficiency`,
`MentorBonus`, `Tempo`, `AscensionCap`, `CombatCashMult`, `CanBuy`, `CanAscend`).
`--era N`, `--power P`, `--party N` and `--overdrive` override the modelled run.

## The income curve the Armory gates ride on

`unlockRate` is compared against `EconomyService.GetPersistedIncomePerSecond`, i.e. the city's
live rate (Legacy, Founder's Blessing, passes and Premium in; neighbours pinned to 1). That rate
is **not monotonic across the run**: advancing an era starts a fresh plot, so income collapses and
climbs again much faster. Greedy, free, Legacy carried:

| Era | length | start | median | peak |
|-----|--------|-------|--------|------|
| Village | 41:50 | 3/s | 64.49K/s | 698.65K/s |
| Boomtown | 1:44:15 | 534/s | 34.07M/s | 155.42M/s |
| Metropolis | 4:28:49 | 108.30K/s | 6.12B/s | 30.73B/s |
| OrbitalColony | 9:25:10 | 18.87M/s | 1.07T/s | 5.35T/s |

Two consequences drove every `unlockRate` below:

1. **A band's entry tier must sit above the previous era's peak**, or the greedy player crosses it
   in the previous era and the "new era, new weapons" beat is lost. That is why band 2 opens at
   800K/s (Village peaks at 698.65K/s), band 3 at 200M/s (Boomtown peaks at 155.42M/s) and band 4
   at 40B/s (Metropolis peaks at 30.73B/s).
2. **Income per era grows ≈ ×200, not ×100.** The spec's "×100 per era" describes base costs and
   incomes; the compounded curve (level-ups + Legacy) ends each era ≈ 200× above the previous one,
   so the unlock ladder had to be spread over 12 decades of rate, not 8.

## Unlock ladder (applied; melee and ranged ladders are identical per tier)

Crossing times are the first second the greedy player's persisted rate reaches the gate; "run
clock" is the same moment on the whole-playthrough clock.

| tier | band | cost | unlockRate | crossed in | at | % of era | run clock | power (t/t) | modelled DPS |
|------|------|------|-----------|------------|----|----------|-----------|-------------|--------------|
| 1 | 1 Timber | 10 | 0/s | Village | 0:00 | 0 % | 0:00 | 48 | 33.5 |
| 2 | 1 Timber | 60 | 15K/s | Village | 12:21 | 30 % | 12:21 | 64 | 50.3 |
| 3 | 1 Timber | 180 | 120K/s | Village | 26:45 | 64 % | 26:45 | 84 | 72.9 |
| 4 | 2 Steel | 10 | 800K/s | Boomtown | 4:28 | 4 % | 46:18 | 151 | 155.3 |
| 5 | 2 Steel | 60 | 20M/s | Boomtown | 35:14 | 34 % | 1:17:04 | 230 | 216.5 |
| 6 | 2 Steel | 180 | 70M/s | Boomtown | 1:18:34 | 75 % | 2:00:24 | 321 | 312.2 |
| 7 | 3 Circuits | 10 | 200M/s | Metropolis | 9:41 | 4 % | 2:35:46 | 602 | 1165.6 |
| 8 | 3 Circuits | 60 | 4B/s | Metropolis | 1:34:15 | 35 % | 4:00:20 | 696 | 1698.4 |
| 9 | 3 Circuits | 180 | 15B/s | Metropolis | 3:33:41 | 79 % | 5:59:46 | 990 | 2458.9 |
| 10 | 4 Alloy | 10 | 40B/s | OrbitalColony | 20:00 | 4 % | 7:14:54 | 2650 | 4600.0 |
| 11 | 4 Alloy | 60 | 700B/s | OrbitalColony | 3:17:47 | 35 % | 10:12:41 | 3834 | 6726.7 |
| 12 | 4 Alloy | 180 | 2.5T/s | OrbitalColony | 7:30:04 | 80 % | 14:24:58 | 6250 | 9337.8 |

Shape of the ladder: **entry tier at ~4 % of its era, second tier at ~35 %, third at ~75–80 %**.
Village is deliberately earlier (0 % / 30 % / 64 %) because it is the onboarding era and the first
two upgrades should land while the player is still learning the loop.

`power (t/t)` is `Armory.GearPower` with both slots at that tier and no Ascension. It is the number
the Expedition panel compares with `recommendedPower`.

## Materials and cost: a flat currency, one ladder per band

Every band charges **10 / 60 / 180** of its own era material. Materials deliberately **do not
inflate ×100 per era** the way cash does: each era's material is a separate currency whose only
source is that era's mission, and a full run of any mission is designed to yield ~250–350 units.
So the same ladder is the same number of runs in every band, and the ×100 cash curve stays the
tycoon's business alone.

Village yields **282 Timber** per full run, against **500 Timber** for the whole of band 1 in both
slots (2 × (10 + 60 + 180)). That is the intended ~2 runs for a full band, with the income gates,
not the materials, setting the calendar. Tier 1 stays at **10** so the Studio definition of done
("buy Wooden Sword with 10 Timber via the `GrantMaterials` lever") still reads true, and so the
first purchase is nearly free.

Ascension (unchanged) costs 200 / 500 / 1200 of **all four** materials plus 50 / 120 / 250 Valor,
i.e. roughly 1 / 2 / 4 runs of each era's mission per level, with Valor (35 per Village run, bosses
only) the tighter half. At the top tier it multiplies Gear Power ×1.96 / ×3.40 / ×5.79.

## Village expedition — the modelled run

`Raider Woods`, 10 waves, bosses on 5 and 10, `recommendedPower 60`, `targetMinutes 8`,
`targetWaveSeconds 30`. Recommended power resolves to the **tier 2/2** loadout (Iron Sword +
Hunter Bow, power 64, max HP 155, modelled DPS 50.3 = 37.8 melee + 12.5 ranged).

| wave | count | avg HP | TTK | wave s | cash | Timber | boss |
|------|-------|--------|-----|--------|------|--------|------|
| 1 | 5 | 115 | 2.29 | 11.4 | 1,500 | 5.0 | |
| 2 | 6 | 124 | 2.47 | 14.8 | 1,980 | 6.0 | |
| 3 | 6 | 120 | 2.38 | 14.3 | 2,396 | 6.0 | archers enter |
| 4 | 7 | 130 | 2.58 | 18.0 | 3,072 | 7.0 | |
| 5 | 7 | 140 | 2.78 | 79.6 | 22,122 | 36.0 | Raider Chief 3,024 hp / 60 s / 10 Valor |
| 6 | 8 | 151 | 3.01 | 24.1 | 4,250 | 16.0 | |
| 7 | 9 | 229 | 4.55 | 40.9 | 8,369 | 24.8 | brutes enter |
| 8 | 9 | 247 | 4.92 | 44.2 | 9,208 | 26.1 | |
| 9 | 10 | 267 | 5.31 | 53.1 | 11,252 | 30.5 | |
| 10 | 10 | 288 | 5.74 | 178.3 | 87,831 | 124.5 | Warlord 6,081 hp / 121 s / 25 Valor |

- **Total 7:58 of combat** (479 s) + 54 s of breathers = **8:52 wall clock**, against the 8 min
  target (band 4:00–12:00). Ordinary waves average **29.8 s** against `targetWaveSeconds 30`;
  the longest ordinary wave is 57.4 s and the shortest 11.4 s.
- **Bosses are 38 % of the run** (60 s + 121 s) and **62 % of the cash**. That is deliberate: the
  boss is the payday, so leaving at wave 9 costs most of the reward.
- Full-run rewards: **151,981 cash, 282 Timber, 35 Valor, 79 kills**. Fits the 1200 s run cap with
  668 s to spare.

Other power levels and party sizes (same tables, `--power` / `--party` / `--overdrive`):

| variant | loadout | DPS | combat time | verdict |
|---------|---------|-----|-------------|---------|
| 0.6× power (34) | starter Stick + Sling | 21.8 | 18:24 (+54 s) = 19:18 | fits the 1200 s cap with 41 s to spare — a first-ever run is viable, and reaching wave 5 (5:19) already pays 31,070 cash and 60 Timber |
| recommended (60) | tier 2/2 | 50.3 | 7:58 | on target |
| 2× power (120 → tier 4/4) | Hatchet + Revolver | 155.3 | 2:35 | 3× faster; band-2 gear trivialises Village, as intended |
| party 4, recommended | tier 2/2 | 50.3 each | 4:13 | 217 kills, 255,828 cash total ≈ 64K each — co-op is faster but pays less per player |
| Overdrive (rebirth 1+, recommended 180 → tier 4/4) | Hatchet + Revolver | 155.3 | 10:14 | 728,065 cash (×4.8), 1,488 Timber, 140 Valor; fits the cap |

## Cash vs the tycoon (assertion 4)

The reference moment is the second the greedy player's rate reaches the recommended loadout's gate
(15K/s at **12:21** into Village) — the first moment they can actually field recommended gear.

| quantity | value |
|----------|-------|
| full-run cash | 151,981 |
| Village slot cost still owed at 12:21 | 14,900,000 |
| ratio | **1.02 %** (cap 25 %) |
| ratio mid-era (20:55, 14,280,000 owed) | 1.06 % |
| in income terms | ~2 s of the era's median rate (64.49K/s) |

The 25 % ceiling is very loose here, and the real constraint is the opposite one: because the
tycoon curve is exponential while a mission's cash is fixed per enemy, combat cash can only ever
be a garnish. The values were chosen for **≈ 1 % of the era's total slot cost per full run**, which
is a meaningful boost early (~5 minutes of income at the 5-minute mark, ~17 s of it at the 10-minute mark) and irrelevant
by the monument — and ten repeat runs (~80 min) still only buy 10 % of the era, so grinding the
mission can never beat building the city. Enemy `cash` therefore still scales ×100 per era for
missions 2–4 (C3), while materials do not.

## The DPS model and its assumptions

Fixed by the contract, and the sim mirrors it exactly:

```
melee DPS  = damage × mean(chain) / mean(windows) × 0.7      (hit rate)
ranged DPS = damage / cooldown × 0.5                          (uptime)
TTK        = hp / DPS
wave time  = count × TTK / party
```

What that means, and what it leaves out:

- `mean(chain) / mean(windows)` is the sustained damage rate of an **uninterrupted** three-hit
  combo. Nothing models combo resets, travel time between targets, or the cleave on the finisher.
- **Abilities are not in the model at all.** Every tier carries one (2.0–6.0× damage on a 10–16 s
  cooldown), and `killCooldownRefundSeconds 0.5` shortens it further, so real DPS will be higher
  than modelled — 15–30 % on a rough pass. Wave times are therefore an upper bound.
- `chargeSeconds` is **not** in the ranged term, so a charge weapon (bow: 0.8 s charge + 0.6 s
  cooldown) is modelled as if it fired every 0.6 s. The 0.5 uptime factor is absorbing that; for
  semi/auto classes the same 0.5 is instead absorbing aim time and reloads. This is the least
  trustworthy part of the model.
- **Party size divides wave time but boss HP is untouched** (`WaveSpec` scales count only, by
  design), so a 4-player party kills a boss 4× faster. Fine at C0 where nothing is fought; C2 has
  to decide whether bosses get a party multiplier.
- Breathers, respawns, the tempo director's wave merging and `maxAlive 24` are outside the model.
  Breather time is reported beside the combat time, never inside it.

Survivability is printed but **not asserted** — there is no hit-rate data yet. Under "one enemy in
contact landing 10 % of its attacks for the whole run", the tier-2/2 player takes 1,186 damage,
regenerates 540 across nine breathers and dies ~4 times (33 s of respawn). At 25 % contact it is
~16 deaths, which would be unplayable. Village enemy `damage` was therefore left at the contract's
8 / 6 / 18 rather than guessed at.

## Values changed, and why

`src/shared/Config/Armory.json` (values only; keys frozen):

| value | from | to | why |
|-------|------|----|-----|
| `unlockRate` tiers 1–12 | 0, 30, 120, 1K, 4K, 12K, 100K, 400K, 1.2M, 10M, 40M, 120M | 0, 15K, 120K, 800K, 20M, 70M, 200M, 4B, 15B, 40B, 700B, 2.5T | The old ladder was calibrated ~200× low: the greedy player passes 120M/s in the first 15 minutes of Metropolis, so **every** tier unlocked inside Village or Boomtown and the band-to-era mapping collapsed. The new ladder puts each band's entry just above the previous era's peak and spaces the rest at ~35 % / ~75 % of the era. |
| tier `cost` | 10/30/80, 20/60/150, 40/120/300, 80/240/600 | 10/60/180 in every band | Material supply does not inflate across eras (each era's material comes only from that era's mission, ~250–350 per run), so an escalating ladder would price bands 3–4 out of reach while band 1 stayed free. One ladder per band = the same ~2 runs per band everywhere. Tier 1 stays at 10 for the Studio definition of done. |

`src/shared/Config/Missions/1_Village.json`:

| value | from | to | why |
|-------|------|----|-----|
| `recommendedPower` | 40 | 60 | Must match `Armory.GearPower` at the tier the income gate hands out mid-Village. Tier 2/2 = 64, tier 1/1 = 48, tier 3/3 = 84; 60 sits just under tier 2/2 so the panel reads "recommended 60 — you 64" (green) with the gear the player actually owns at the era's median rate, and starter gear (34) reads red at 0.57. |
| `raider.hp` / `archer.hp` / `brute.hp` | 60 / 40 / 240 | 115 / 75 / 390 | Total run HP is what sets the run length, and the old values left it well under target. ×1.9 on the base HP puts the ordinary waves at a 29.8 s mean (`targetWaveSeconds 30`) and the whole run at 7:58. |
| `raider.cash` / `archer.cash` / `brute.cash` | 15 / 20 / 80 | 300 / 400 / 1600 | ×20, to bring a full run from 0.05 % to ~1 % of Village's slot cost — from unnoticeable to a real early-game boost, still 25× under the contract's 25 % ceiling. |
| `waveTable.baseCount` | 4 | 5 | With `countPerWave` cut (below), wave 1 needed a floor that does not read as empty; 5 enemies × 2.29 s TTK = an 11 s opening wave. |
| `waveTable.countPerWave` | 1 | 0.6 | Count growth (2.8× over 10 waves) plus HP growth plus the composition shift made wave 10 eight times wave 1 — an 11 s opener forced a 70 s closer. At 0.6 the count runs 5→10 and the wave-time spread is 5× instead of 8×. |
| `waveTable.hpGrowth` | 0.12 | 0.08 | Same reason: 1.12^9 = 2.77 was too steep once enemy HP doubled. 1.08^9 = 2.00 keeps the last wave under 2× `targetWaveSeconds`. |
| `bosses.5.hpMult` | 4.0 | 5.7 | "First boss ≈ 60 s at recommended DPS": 390 × 1.3605 (wave 5) × 5.7 = 3,024 HP ÷ 50.3 DPS = 60.1 s. |
| `bosses.10.hpMult` | 8.0 | 7.8 | The Warlord is deliberately **twice** the Chief, not more: 6,081 HP = 121 s. With the higher base HP, 8.0 overshot. |

Unchanged and why: `damageGrowth 0.08`, `rewardGrowth 0.1`, all enemy `damage`, `speed`, `reach`,
`attackCooldown`, `materials`, the wave `composition` breakpoints (1 / 3 / 7), both bosses'
`damageMult`, `cashMult`, `materialsMult` and `valor`, `waves 10`, `bossWaves [5, 10]`,
`targetMinutes 8`, `targetWaveSeconds 30`, and every `Armory.json` `damage`, `hp`, class, ability
and Ascension number. Nothing in `Combat.json` or `Places.json` was touched.

## What C1 must re-check

1. **Real hit rates.** The 0.7 melee / 0.5 ranged coefficients are placeholders. Once C1 can
   measure swings-that-land and shots-that-land, re-run `--check`; if measured melee is below ~0.5
   the Village run breaks the 12-minute ceiling.
2. **Abilities in the DPS term.** They are 15–30 % of real DPS and completely absent here. Adding
   them shortens every run; enemy HP, not the wave table, is the lever to put it back.
3. **Survivability.** Pick a contact model from telemetry and add a seventh assertion ("≤ 4 deaths
   at recommended power"). If contact lands above ~10 %, either Village enemy `damage` comes down
   or weapon `hp` goes up — one or the other, not both.
4. **Charge weapons.** If the bow's real cycle is `chargeSeconds + cooldown`, the ranged term needs
   a class-aware denominator and the whole band-1 DPS column drops ~40 %.
5. **Boss HP vs party size** (C2) and **missions 2–4** (C3): enemy `cash` ×100 per era, enemy `hp`
   × the gear-damage ladder (≈ ×2.3 per band), materials flat.

## One boss per boss wave (settled during C0 review)

Every number above assumes the narrow reading of the boss multipliers: the wave body is ordinary
even on a boss wave, and only the single boss entity takes `hpMult` / `damageMult` / `cashMult` /
`materialsMult`. It matters because Village wave 10 is the one wave where the two readings differ —
brutes enter at wave 7 and the Warlord is built from `brute`, so buffing the whole key would turn
~1.5 ordinary brutes into Warlords: wave 10 57 s → 5:36, the run 7:58 → 10:37 and run cash
151,981 → 259,502, all of it **still inside both assertions**, i.e. invisible to `--check`.
`Combat.EnemyStats(mission, key, spec, isBoss)` now takes the flag and gates on
`isBoss and boss ~= nil and boss.enemy == key`; `tools/sim_combat.py` gates on exactly the same two
conditions, so the sim and the server agree. If a later mission ever wants a wave of mini-bosses,
that is a new config shape, not this flag.

## Commands used

```
py tools/sim_combat.py                   # unlock ladder + Village run at 1x / 2x / 0.6x power
py tools/sim_combat.py --check           # the six C0 assertions, exits 0
py tools/sim_combat.py --party 4         # co-op wave counts and per-player cash
py tools/sim_combat.py --overdrive       # Overdrive run at its scaled recommended power
py tools/sim_combat.py --power 84        # tier 3/3 spot check
py tools/sim_economy.py --check          # unchanged: every era still in band
```

# C1 — The Village run simulator, and the pacing director

`tools/sim_combat.py` keeps every C0 mirror and adds the nine C1 "Pure additions"
(`wave_composition`, `spawn_interval`, `breather_seconds`, `should_merge`, `melee_damage`,
`ranged_damage`, `ability_damage`, `ability_cooldown`, `split_pool`). Assertion 3's closed-form
DPS model is **gone**: in its place `simulate_run` plays the whole run at `DT = 0.1 s`, exactly as
`WaveService` is contracted to — trickle spawns at `SpawnInterval`, `maxAlive`, tempo from the
kills in the last `windowSeconds` (pinned to 1.0 for `tempoWarmupSeconds`), a merge decision when
a wave finishes spawning, `BreatherSeconds` with regen, the boss prepended to its wave, the elite
rule at `eliteTempo`, pools flushed through `ContributionShares` + `SplitPool` at every wave
clear, and the run ending on wave 10, `runCapSeconds` or death. `--trace` prints the wave
timeline (it is the table below). Nothing is random; two runs of the same inputs are identical.

Cash follows the server's **double floor**: `SplitPool` floors `pool.cash × share`, then the
caller floors that share again against `Combat.CombatCashMult`. Every number below is at legacy 0
with no Founder's Blessing, so that second multiplier is ×1.00 and only the first floor bites.

## What the simulator assumes (and where it is pessimistic)

| term | value | why |
|------|-------|-----|
| player DPS | melee `chain/windows x 0.7` + ranged `damage/cooldown x 0.5` | the C0 coefficients, unchanged, now expressed through `melee_damage` / `ranged_damage` |
| abilities | cast the instant they are ready, AoE hits the field, kills refund `killCooldownRefundSeconds` | they were **absent** from the C0 model; here they are 10 % of the HP destroyed |
| target priority | ordinary enemies before the boss, squishiest first, oldest to break ties | the greedy player, and the analogue of `sim_economy`'s greedy buyer |
| melee reach | the melee term only lands once the target is inside `class.range + hitDistancePad` | an enemy walking in from the rim is bow-only damage for its first seconds |
| `SPAWN_DISTANCE` 45 studs | rim spawn to a player fighting near the middle of the 110x110 arena | sets travel time, i.e. how long an enemy lives before it can hit anything, and it is a big part of the kill lag the tempo measures |
| `MELEE_CONTACT_SLOTS` 4 | how many rigs fit on a reach-5 ring; the rest queue and do not swing | without it a wave-10 scrum would all connect at once |
| enemy land rate | melee `min(speed / 16, 1)`, ranged `0.5` | the player moves: a speed-8 brute lands half its swings, a speed-14 raider seven eighths. This is what makes enemy `speed` a balance lever and a slow boss genuinely kitable |
| player movement | **stands still** otherwise | every damage number below is an **upper bound**; a kiting player takes less |

The one thing the model still cannot see is skill. It is calibrated so that a *mediocre* player at
recommended gear finishes wave 10 at 15 % HP; a good one should finish comfortably.

## How the director actually behaves (and why `windowSeconds` moved)

`Tempo` measures kills per second against `count / targetWaveSeconds`, but `SpawnInterval`
divides by that same tempo — so the stream the director measures is the stream the director
controls. In steady state a party can only kill as fast as the spawner delivers, which means
**tempo is a measure of the party's kill *lag*, not of its kill rate**, and it lives or dies on
how the kills quantise inside `windowSeconds`:

- At the contracted `windowSeconds 15`, with `targetWaveSeconds 30` and counts of 5–8, the window
  is wide enough to hold the same number of kills whatever the lag. Measured at the merge check:
  **0.50–0.80 at recommended power and 0.50–1.00 at twice recommended** — indistinguishable, both
  parked near `tempoMin`, and `mergeTempo` unreachable for anyone. Waves ran 45–55 s against a
  30 s target and the director was, in effect, switched off.
- At **`windowSeconds 10`** the window holds one kill or two depending on the lag, and that is
  exactly the fast/slow discriminator. Measured at the merge check: **0.70–0.87 at recommended
  power, 1.20 → 1.50 → 1.71 → 2.00 at twice recommended** (it climbs because merged waves really
  do double the kill rate), and **0.75–1.00 for the under-geared player**, who burns a backlog in
  bursts and therefore reads *higher* than the recommended player on wave 1 — the one place the
  metric is counter-intuitive, and the reason `mergeTempo` has to sit above that burst at 1.25.

With that, the whole director is live and does what it says: `tempoMin 0.7` lets the stream slow
for a party that is behind, `BreatherSeconds` stretches to its full `breatherMaxSeconds 14` at
that floor and shrinks back to `breatherSeconds 6` once tempo reaches 1, and `ShouldMerge` needs
**both** a fast party (`tempo ≥ 1.25`) and a cleared field (`deadFraction ≥ 0.7`). Measured
merges: **0 at recommended power, 5 at twice recommended, 1 under-geared** (the backlog
burst on wave 5 merges wave 6 into it, which is the wave they die on).

Two notes for C2, neither blocking:

1. **Tempo would be more robust measured directly as lag** — mean seconds from spawn to death
   against `targetWaveSeconds / count` — instead of as a rate inside a window whose width has to
   be tuned against the wave count. The signature could stay; only what `WaveService` feeds it
   would change. As it stands, `windowSeconds` is load-bearing for missions 2–4 too: each new
   mission must re-check that its counts and `targetWaveSeconds` still quantise usefully.
2. **The merge check is continuous** (`MERGE_CHECK_CONTINUOUS = True`): once a wave has finished
   spawning the sim re-reads `deadFraction` every tick until the wave ends, which is what
   `WaveService` does. The tool carries the read-once reading behind the same flag and **every
   assertion and every number in this section holds under both** — the only difference is the
   under-geared player dying on wave 6 (continuous, the shipped reading) instead of wave 5. So the
   reading is not load-bearing, but the two implementations agree.

## Wave timeline at recommended power (`py tools/sim_combat.py --era 1 --trace`)

Recommended power 60 resolves to **tier 2/1, Iron Sword + Short Bow** — the C1 rule is "the
highest tiers whose summed power <= target, melee first", which is the strongest legal loadout at
that power (tier 2/2 is 64 and over budget). Power 57, max HP 145, 46.1 DPS + abilities.

| wave | start | end | length | n | flags | tempo | damage in | cash | Timber | HP left |
|------|-------|-----|--------|---|-------|-------|-----------|------|--------|---------|
| 1 | 0.0 | 25.1 | 25.1 | 5 | | 0.99 | 0 | 1,500 | 5 | 145/145 |
| 2 | 39.1 | 76.4 | 37.3 | 5 | | 0.75 | 0 | 1,650 | 5 | 145/145 |
| 3 | 90.5 | 129.5 | 39.0 | 6 | | 0.77 | 1 | 2,420 | 6 | 144/145 |
| 4 | 143.6 | 182.9 | 39.3 | 6 | | 0.79 | 1 | 2,660 | 6 | 144/145 |
| 5 | 197.0 | 237.0 | 40.0 | 7 | **BOSS** | 0.83 | 47 | 21,668 | 35 | 98/145 |
| 6 | 243.1 | 276.7 | 33.6 | 7 | | 0.86 | 3 | 3,703 | 14 | 142/145 |
| 7 | 290.7 | 325.4 | 34.7 | 7 | | 0.87 | 10 | 6,376 | 19 | 136/145 |
| 8 | 339.4 | 374.1 | 34.7 | 7 | | 0.87 | 10 | 7,016 | 20 | 136/145 |
| 9 | 388.1 | 422.8 | 34.7 | 7 | | 0.87 | 12 | 7,716 | 21 | 132/145 |
| 10 | 436.8 | 506.5 | 69.7 | 9 | **BOSS** | 0.78 | 124 | 84,648 | 117 | 22/145 |

- **8:26 wall clock** (507 s, 118 s of it breathers) against the 8 min target, band 4:00–12:00.
  Ordinary waves average 38.8 s against `targetWaveSeconds 30`: the recommended player is keeping
  up but never ahead, so the director holds tempo near 0.8 and hands them the long breather. The
  trickle, not the player's DPS, sets every wave length in this table.
- **No merges at recommended power** — merging is what the player earns by out-pacing the stream,
  and at 2x power it fires five times and compresses the run to 5:41 (see the scenarios).
- **Bosses are 22 % of the run and 76 % of the cash.** Wave 10 is the fight: 69.7 s, 124 damage,
  and the player finishes at 22/145 (15 %) — below the `feedback.lowHpFraction 0.3` vignette for
  the last half minute, which is exactly the intended ending.
- Waves 1–4 and 6–9 cost 0–12 HP. Deliberate: at 46 DPS a 52-HP raider dies inside its own 0.3 s
  windup plus 2.0 s cooldown, so on a slow stream it mostly never swings. The run's danger is
  concentrated in the two boss waves, which is where the payday is too.

**Kills per key:** 66 kills — raider 44, archer 16, brute 6 (of which 2 are the bosses).
**Rewards:** 139,357 cash, 248 Timber, 35 Valor. Total damage taken 206, i.e. 1.4 health bars.

## Run cash vs the era (assertion 4, unchanged rule)

| quantity | value |
|----------|-------|
| full-run cash | 139,357 |
| Village slot cost still owed at 12:21 (the recommended loadout's income gate) | 14,900,000 |
| ratio | **0.94 %** (cap 25 %) |
| ratio mid-era (20:55, 14,280,000 owed) | 0.98 % |
| in income terms | ~2 s of the era's median rate 64.49K/s |

C0's "about 1 % of the era per full run" target is preserved (it was 1.02 %), so nothing about the
tycoon curve moves; `sim_economy.py --check` is byte-identical before and after this milestone.

## The power scenarios

| scenario | loadout | power | DPS | HP | result | cash |
|----------|---------|-------|-----|----|--------|------|
| 0.6x (36) | Stick + Sling | 34 | 22 | 100 | **dies on wave 6**, 4:03, killed by the Raider Chief in the merged wave 5 + 6 after four clean waves (13–14 HP each) | 8,230 |
| recommended (60) | Iron Sword + Short Bow | 57 | 46 | 145 | clears 10/10 in 8:26, 0 merges, HP floor 15 % | 139,357 |
| 2x (120) | Hatchet + Hunter Bow | 115 | 104 | 200 | clears in 5:41, **5 merges** from wave 6 on, tempo climbing 1.20 to 2.00, HP floor 32 % | 152,512 |
| party 2, recommended | same | 57 | 46 each | 145 | 8:23, 102 kills | 169,314 pot, about 84,657 each |
| party 4, recommended | same | 57 | 46 each | 145 | 8:39, 181 kills | 222,968 pot, about 55,742 each |
| Overdrive at its recommended power (180) | Fire Axe + Longbow | 162 | 155 | 250 | **dies on wave 5** (1:10) with no Ascension (corrected at C2; the tool has always said 5) | 48,716 |
| Overdrive at 180 **+ Ascension 1** | same gear | 289 | 310 | 325 | clears in 3:02 | ≈ 706K–722K (elite count varies with merges) |
| Overdrive at 3x recommended (540) | Machete + Marshal Rifle | 507 | 881 | 460 | clears in 2:11 | 721,553 (x5.18) |

Co-op is faster per kill and pays less per head, as at C0. **Overdrive at exactly
`Combat.RecommendedPower` is lethal without Ascension and comfortable with Ascension 1** — and
both gates are the same rebirth, so the panel's number is honest for anyone who can actually
select Overdrive. That is why `Combat.json overdrive.*` was left alone, and why assertion 10's
fixture is three times the *Overdrive* recommendation (540), which is what "Overdrive at
recommended x 3" resolves to once `RecommendedPower` has already applied `hpMult`.

## Values changed, and why

`src/shared/Config/Missions/1_Village.json` (values only; keys frozen):

| value | from | to | why |
|-------|------|----|-----|
| `raider.hp` / `archer.hp` / `brute.hp` | 115 / 75 / 390 | 52 / 34 / 176 | C0 doubled these to stretch the run, because its model priced a wave at `count x TTK`. Under the real director the **trickle** sets wave length (`targetWaveSeconds / count / tempo`), so enemy HP no longer buys time — it only buys *pressure*, because an enemy that lives longer stands in contact longer, and it buys kill *lag*, which is what the tempo metric reads. At the old HP the recommended player was at their DPS ceiling from wave 7 on, half of every late wave was alive at once, and the run died at wave 5. +20 % on these numbers already costs the merge behaviour and drops the HP floor to 3 %; +40 % kills the run. |
| `raider.damage` / `archer.damage` / `brute.damage` | 8 / 6 / 18 | 3 / 2 / 5 | C0 flagged this explicitly ("either Village enemy damage comes down or weapon `hp` goes up — one or the other"). Damage came down: it is a one-file change, where raising weapon `hp` would move `GearPower`, `recommendedPower` and the whole C0 unlock table. At 145 max HP an 18-damage brute killed the recommended player in 8 hits; it now takes about 29, and a full run costs 206 damage = 1.4 health bars. |
| `raider.attackCooldown` / `archer` / `brute` | 1.2 / 1.8 / 1.6 | 2.0 / 3.0 / 2.6 | The other half of the same budget, and the better half: a slower swing keeps the *per-hit number* readable (a raider still hits for 3–4, not 1) and leaves room for the `enemy.attackWindupSeconds 0.3` tell to matter. Sustained damage per enemy in contact: raider 1.31/s, archer 0.33/s, brute 0.96/s. |
| `brute.speed` | 10 | 8 | Brutes and both bosses are built from this row, and a slow enemy is kitable: the land rate is `speed / 16`, so a brute now lands half its swings instead of five eighths. It is the only lever that makes a **long** boss fight survivable without making the boss's per-hit number silly, and "lumbering brute" is what the model wants anyway. |
| `waveTable.countPerWave` | 0.6 | 0.3 | Counts run 5 to 8 instead of 5 to 10. Wave 10 with 10 bodies *plus* the Warlord was unsurvivable for the recommended player in every combination of the other values (the search tried 648 of them): the adds alone out-damaged the health bar. 0.5 still kills the run at wave 10 today. |
| `waveTable.hpGrowth` | 0.08 | 0.03 | 1.08^9 = 2.0 on top of a growing count made wave 10 four times wave 1 in HP; since the wave window is fixed, that is four times the fraction of the wave spent in contact. 1.03^9 = 1.30 keeps the "busy fraction" between 40 % (wave 1) and 90 % (wave 10). |
| `waveTable.damageGrowth` | 0.08 | 0.03 | Same argument on the other axis, and it is the knob that decides where the under-geared player dies: at 0.02 they survived to wave 9 (outside the 6 +- 2 assertion), at 0.03 the Chief kills them on wave 6. |
| `bosses.5.hpMult` / `damageMult` | 5.7 / 1.5 | 5.0 / 1.0 | The Raider Chief is 990 HP, a 25 s fight and the gate that ends an under-geared run. Its *damage* multiplier is 1.0 because a boss is in contact for the **whole wave** (the player kills the adds first), so every point of boss damage is multiplied by about 40 s of exposure: 1.5 made it 130 damage, and no combination of the other values then left the recommended player alive at wave 10. A boss's identity here is its HP bar and its payday (`cashMult 8`), not its per-hit number. |
| `bosses.10.hpMult` / `damageMult` | 7.8 / 2.0 | 8.0 / 1.0 | Warlord 1,837 HP — still "twice the Chief" as C0 intended (x1.86), and the longest fight in the run at 69.7 s. Same argument for `damageMult`; with the wave-10 `damageGrowth` on top it still hits harder per swing than the Chief (7 vs 6). |

`src/shared/Config/Combat.json` (values only):

| value | from | to | why |
|-------|------|----|-----|
| `director.windowSeconds` | 15 | 10 | The whole director hangs off this. At 15 s the kill window holds the same number of kills for a fast party and a slow one, so tempo read 0.5–0.8 for **everybody**, `mergeTempo` was unreachable at any value above 1, and waves ran 45–55 s against a 30 s target. At 10 s the window holds one kill or two depending on the party's kill lag, which is the discriminator the director was designed around: recommended power reads 0.70–0.87 and never merges, 2x reads 1.20–2.00 and merges five times. |
| `director.tempoMin` | 0.5 | 0.7 | 0.5 let the stream run at half the design pace, which is where it parked: a 60 s wave with the player idle between spawns. 0.7 bounds the stretch at 43 s while still letting the director visibly slow down for a party that is behind — and, because `BreatherSeconds` ramps on `(1 − tempo) / (1 − tempoMin)`, a party sitting at this floor gets the full `breatherMaxSeconds 14` breather, which is the regen that keeps the recommended run alive. |
| `director.mergeTempo` | 1.3 | 1.25 | The under-geared player burns their backlog in bursts and momentarily reads 1.20 on wave 1; the 2x player reads 1.50 at the wave-5 check. 1.25 is the gap between them. 1.3 also works today but leaves no room under the 1.50 reading if mission 2–4 counts shift. |

Unchanged and why: every `Armory.json` number (no weapon `damage`, `hp`, `cost` or `unlockRate`
moved, so the C0 unlock ladder and its era mapping are untouched); `director.{tempoMax,
mergeThreshold, eliteTempo, breatherSeconds, breatherMaxSeconds, maxAlive, runCapSeconds,
tempoWarmupSeconds}` — `mergeThreshold 0.7` and `breatherSeconds 6` are the C0 values and the run
is identical with `breatherSeconds` anywhere in 6–10; `overdrive.*` (see the scenarios table);
`coop.*`; `player.*` including `breatherRegenPerSecond 10` (12 and 16 made no difference — the
player is topped up either way); every `enemy.*` and `feedback.*` key; the mission's `waves 10`,
`bossWaves`, `baseCount 5`, `rewardGrowth 0.1`, `recommendedPower 60`, `targetMinutes 8`,
`targetWaveSeconds 30`, the composition breakpoints (1 / 3 / 7), all enemy `cash` / `materials` /
`reach`, and both bosses' `cashMult` / `materialsMult` / `valor`.

## The ten assertions, as measured

| # | assertion | measured |
|---|-----------|----------|
| 1 | unlock ladder monotonic, every band entry inside its era | b1t1 Village 0 %, b2t4 Boomtown 4 %, b3t7 Metropolis 4 %, b4t10 OrbitalColony 4 % |
| 2 | gear at the era's median rate meets `recommendedPower` | Village median 64.49K/s gives tier 2/2, power 64 vs 60 |
| 3 | recommended power clears 10 waves inside `targetMinutes` +-50 % | 10/10 in **8:26** vs 8 min (4:00-12:00), HP floor 15 % |
| 4 | run cash <= 25 % of the era's remaining slot cost | **0.94 %** of 14,900,000 |
| 5 | `ContributionShares`, 10:1 duo, veteran >= 75 % | 82.7 % |
| 6 | `AwayEfficiency` endpoints | 0 s gives 0.50, whole absence gives 1.00 |
| 7 | 2 x recommended triggers >= 1 merge | **5 merges**, run 5:41 |
| 8 | 0.6 x recommended dies at wave 6 +- 2 | **died wave 6** at 4:03 |
| 9 | `WaveComposition` returns exactly `count` keys, each within 1 of its share | 80 wave x party (1-4) x overdrive combinations, all exact |
| 10 | Overdrive at recommended x 3 pays >= 3 x the normal run | 721,553 vs 139,357 = **x5.18** |

Robustness: the whole set passes with `breatherSeconds` at 6, 7, 8, 9 and 10, and under **both**
readings of the merge check, with the HP floor at 15 % and the run between 8:27 and 8:32
throughout.

## What C2 should re-check

1. **Tempo as lag rather than rate**, and with it the `windowSeconds` dependency on wave count.
2. **Enemy land rate.** `speed / 16` and a flat 0.5 for ranged are the sim's invention. Once the
   real thing is played, measure hits-taken per enemy per life and replace them.
3. **`MELEE_CONTACT_SLOTS`.** Four rigs on the ring is a guess with real balance weight — at 3 the
   late waves lose a quarter of their damage. Count what actually connects in Studio.
4. **Missions 2-4 (C3)** inherit this shape, not C0's: enemy `cash` x100 per era, materials flat,
   enemy `hp` sized so a wave is 60-90 % of what the era's recommended DPS clears in
   `targetWaveSeconds`, enemy `damage` sized so a full run costs 1.5-2 health bars, boss
   `damageMult` at 1.0 until something shortens a boss's time in contact, and a fresh check that
   the mission's counts still quantise usefully against `windowSeconds`.
5. **The quiet waves.** Waves 1-4 and 6-9 cost the recommended player 0-12 HP; the danger is all
   in the two boss waves. If playtest says the middle of the run reads as empty, the fix is
   `baseCount` (more bodies per wave, same total), not enemy damage.

## Commands used

```
py tools/sim_combat.py --check           # the ten C0+C1 assertions, exits 0
py tools/sim_combat.py --era 1 --trace   # the wave timeline at 1x / 2x / 0.6x power
py tools/sim_combat.py --party 4         # co-op wave counts and per-player cash
py tools/sim_combat.py --overdrive       # Overdrive run at its scaled recommended power
py tools/sim_economy.py --check          # unchanged, byte for byte, before and after
```

# C2 — Co-op: boss HP by party size, the Mentor bonus, party effects

`tools/sim_combat.py` now simulates each party member separately. A member is
`{gear, ascension, rate, bot, idle}`, and each one has its own DPS, abilities and cooldowns.
Every point of damage is credited to whoever dealt it, both into a run-wide map and into the
per-flush tally, which is drained at every group clear (`CombatService.TakeDamageTally`). The
pot is split by that tally's `ContributionShares`, and bots' shares are discarded. A kill
refunds **only the killer's** cooldowns, as `CombatService.onEnemyKilled` does; C1 refunded
everyone. At the flush of a group that held a boss, each human **whose own raw tally share is at least
`coop.mentorMinDamageShare`** (lead ruling, C2 review) earns `MentorBonus` over the other members
whose raw tally share clears the same floor. An idle or waiting high-income player earns nothing. HP is still the C1
model: one pooled bar at the members' mean max HP, taking `incoming / party`. A rally therefore
heals (n − 1)/n of its fraction into that bar.

Solo runs are **byte-identical** to C1, so assertions 1–10 did not move. Equal parties move by
about 1 % because the refund now goes to the killer only (party 2 at `bossHpPerExtraPlayer 0`:
8:17 against C1's 8:24). The C1 "party 2 / party 4" rows are superseded by the table below.

## Boss HP mirror (must match `Combat.luau` exactly)

```
extras     = max(partySize, 1) - 1                      -- same extras as the count term
bossHpMult = 1 + coop.bossHpPerExtraPlayer * extras     -- WaveSpec
hp (boss)  = round(enemy.hp * spec.hpMult * boss.hpMult * spec.bossHpMult)   -- left to right
hp (other) = round(enemy.hp * spec.hpMult)
```

The sim multiplies in the Luau's left-to-right order. If the factors are regrouped, a product
can cross .5 by one ulp and the rounded HP would disagree.

## The party table (`py tools/sim_combat.py --era 1`, everyone at recommended power 60)

| party | result | run | Chief alive | Warlord alive | boss HP (w5 / w10) | cash / player | Timber / player | Valor / player | HP floor |
|---|---|---|---|---|---|---|---|---|---|
| 1 | cleared | 8:26 | 39.8 s | 69.6 s | 990 / 1,837 | 139,357 | 248 | 35.0 | 15 % |
| 2 | cleared | 8:36 | 34.2 s | 62.7 s | 1,733 / 3,215 | 84,654 | 159 | 16.5 | 68 % |
| 3 | cleared | 8:45 | 33.7 s | 63.3 s | 2,476 / 4,593 | 64,774 | 128 | 11.0 | 77 % |
| 4 | cleared | 8:52 | 32.6 s | 61.4 s | 3,219 / 5,971 | 55,741 | 114 | 8.0 | 85 % |

Boss **waves** (start to clear, which is what assertion 11 measures) run 40.0 / 69.7 s solo
and range from x0.88 to x1.08 of that at party 2–4. They sit well inside the ±35 % band
because the trickle, not DPS, sets a wave's length (C1). A four-player party kills the Warlord
about 12 % sooner than a solo player. Four players bring four times the DPS, while the boss has
only 3.25 times the HP.

## Values changed, and why

| value | from | to | why |
|---|---|---|---|
| `Combat.json coop.bossHpPerExtraPlayer` | 0.75 | **0.75** (kept) | Swept 0.5 / 0.6 / 0.75 / 0.9 / 1.0. At 1.0 the boss lives exactly as long as solo; at 0.5 the Warlord dies 21 % sooner at party 4. The sim assumes **perfect focus fire**: every member hits the same target with no travel and no spread. That is its most generous party assumption, so the real co-op boss fight runs longer than the sim's. At 0.75 the modelled boss lives 9–18 % shorter than solo, which in play should land at about solo length. A party should feel stronger, not punished for grouping. Studio DoD check: two bots give 1 + 0.75 × 2 = **2.5×** solo HP. |
| `Combat.json coop.mentorRatio` | 0.1 | **0.125** | The contract's own fixture, a 10:1 income duo, sits **exactly on the threshold** at 0.1. `MentorBonus` tests `rate < hostRate × mentorRatio` strictly, so 10,000 × 0.1 = 1,000 is not `<` 1,000, and assertion 12 failed. Whether 10:1 qualifies would come down to float rounding (64,490 × 0.1 happens to be 6,449.000000000001). At 0.125 a mentor is anyone whose city earns **8× or more**, and 10:1 has margin. A same-era newbie (Village early game at ~1K/s against a veteran at the 64K/s median) qualifies either way. |
| `Combat.json coop.mentorMinDamageShare` | 0.02 | **0.01** | The floor exists to stop an **idle alt** from farming Valor. Idle means 0 % of the tally, so any positive floor blocks it. Measured lowest boss-flush share for a Stick + Sling newbie: 27 % beside one recommended veteran, 5.4 % beside three 2x veterans, but **1.4 %** at the Warlord beside three veterans at 2x the Overdrive recommendation. Guests may join the host's Overdrive runs (missions are host-gated), so that is a real carry. At 0.02 it paid on wave 5 and not on wave 10; at 0.01 it pays both. 1 % of a four-player boss flush is about 10 s of starter-weapon damage, so it still demands actual fighting. Beside **3x**-Overdrive veterans the newbie deals 0.4–0.5 %; no floor that means anything can include that, and that player is spectating, not being mentored. |
| `Armory.json partyEffects.rally.healFraction` | 0.25 | **0.15** | See party effects below. |
| `Armory.json partyEffects.warcry` | 1.25 / 6 s / 20 | kept | See party effects below. |
| `Armory.json partyEffects.rally.radius` | 20 | kept | This is at least the 16-stud `bladeStorm` radius, so anyone fighting inside the caster's AoE is covered. |

`mentorValor 5`, `countPerExtraPlayer 0.6`, `contributionFloor 0.1`, `joinUntilWave 9`,
`maxParty 4` and every timing key (`inviteSeconds`, `lobbyWaitSeconds`, `returnGroupSeconds`,
`reformSeconds`) are unchanged. The timing keys are UX, not balance.

## Mentor Valor per run (host 10K/s, newbie 1K/s, Village, recommended power)

| party | Mentor Valor per run | notes |
|---|---|---|
| veteran + starter-gear newbie | **10** to the veteran (5 at the Chief, 5 at the Warlord) | veteran total 32 Valor against 17 in an equal duo |
| veteran + equal-rate friend | 0 | assertion 12's negative case |
| 2x veteran + three newbies | **30** to the veteran | 46 Valor total, 1.3x a solo run's 35 |
| three 2x veterans + one newbie | **10** to each veteran | newbie at 5 % of the boss flush |
| veteran + idle alt | 0 | the alt is at 0 % of the tally; it still collects 3 Valor via `contributionFloor` (see C3) |
| idle veteran + fighting newbie | 0 | the mentor floor (lead ruling): the veteran is at 0 % of the tally, so the qualifying newbie earns it nothing |

Mentoring is worth 10 Valor per mentee per run, 20 % of Ascension 1's 50 Valor. It is enough to
be a reason to carry a friend, while a veteran with three mentees stays below 1.5x a solo run.

## Party effects (band 4 only: tiers 10–11 `rally`, tier 12 `warcry`)

No Orbital mission exists yet, so the effects were measured on a **proxy**: Village Overdrive at
its recommended power (180, tier 5/3), which solo players die in. The leader is forced to carry
the effect, and it triggers on the leader's melee ability (`groundSlam`, 14 s cooldown, standing
in for `bladeStorm`'s 16 s). The sim puts every ally inside the radius on every cast, so the
effects' real value is **lower** than this.

| party 4, Overdrive 180 | result | run | HP floor | healed |
|---|---|---|---|---|
| no effect | died wave 10 | 2:36 | 0 % | 0 |
| rally 0.10 | cleared | 3:06 | 44 % | 187 |
| **rally 0.15** | cleared | 3:06 | **56 %** | 254 |
| rally 0.25 | cleared | 3:06 | 70 % | 291 = **all** damage taken |
| **warcry 1.25 × 6 s** | cleared | 2:33 | **12 %** | — |
| warcry 1.15 × 6 s | died wave 10 | 2:33 | 0 % | — |

- **Rally 0.25 → 0.15.** At 0.25 the rally healed back every point the party took, and the
  allies' health bars stopped mattering. At 0.15 it still turns a wipe into a clear with a
  56 % floor. With real spacing it lands closer to the 0.10 row, which still clears.
- **Warcry kept at 1.25× for 6 s.** On a 16 s `bladeStorm` cooldown it is up about 40 % of the
  time, so allies deal about +10 % damage. That is far below a tier step (tier 11 → 12 is +45 %
  damage), so it never replaces gear. At 1.15 it no longer changed the outcome. Tier 12 swaps
  rally for warcry, trading survival for speed: the warcry run is 33 s faster with a lower HP
  floor. Neither dominates, so the upgrade never feels like a loss.

## The three new assertions, as measured

| # | assertion | measured |
|---|---|---|
| 11 | boss wave at party 2/3/4 (equal recommended power) within ±35 % of solo | solo 40.0 / 69.7 s; p2 x1.07 / x0.90, p3 x1.08 / x0.91, p4 x1.05 / x0.88 |
| 12 | 10:1-rate duo pays the mentor exactly `mentorValor` at a boss clear; equal duo pays 0 | 5 to the mentor and 0 to the mentee at the wave-5 clear; the equal duo pays 0 all run |
| 13 | a member under `mentorMinDamageShare` earns its mentor nothing, and a mentor under it earns nothing | idle mentee at 0.0 % pays 0; an idle mentor beside a fighting 1:10 mentee is paid 0; positive control: a starter-gear newbie at 5.4 % beside three 2x veterans pays each veteran 10 |

## What C3 should re-check

1. **Per-head rewards fall steeply in co-op.** A four-player party earns 40 % of the solo cash
   and 23 % of the solo Valor per player. Boss pots are 76 % of run cash and all of the
   non-Mentor Valor, and they do not scale with party size. Suggested formula change for the
   lead, not needed for C2: scale a boss's `cash`/`materials` in `EnemyStats` and `BossValor`
   by `spec.bossHpMult`. Per-head boss reward would then be (1 + 0.75(n − 1)) / n, which is
   81 % at four players.
2. **Co-op is much safer than solo.** The HP floor is 68–85 % at party 2–4 against 15 % solo,
   because the pooled bar splits incoming damage by n while enemy count grows only 0.6 per
   extra player. Measure real per-player damage taken in the published two-account test before
   touching `countPerExtraPlayer`.
3. **The idle alt still collects `contributionFloor` (10 %) of every pot**, 3 Valor per run
   here. Mentor pays it nothing, but the floor predates C2. A share floor that requires
   `damage > 0` would close it (Luau change in `ContributionShares`).
4. **Overdrive party outcomes are not monotonic** at exactly the recommended power: party 3
   clears in 3:19, while parties 2 and 4 die (merges and count rounding). Recheck once
   Ascension players exist, since without Ascension that power is lethal by design (C1).
5. **Party effects on a real band-4 mission.** Re-run the proxy table on Orbital's mission with
   `bladeStorm`, and count in Studio how often allies are actually inside 20 studs.
6. **Studio DoD note.** "Bots at income 0 make the player earn the Mentor Valor" needs the
   player's persisted `incomeAtSave` > 0 (at 0 the test is 0 < 0). Buy anything in the hub
   before departing.

## Commands used

```
py tools/sim_combat.py --check              # thirteen assertions, exits 0
py tools/sim_combat.py --era 1              # adds the Co-op section: party table + Mentor per run
py tools/sim_combat.py --era 1 --overdrive  # the same tables under Overdrive
py tools/sim_economy.py --check             # unchanged, byte for byte, before and after
```

# C2.5 — One evolving horde: missions 2–4 (draft), chargers, boss patterns

Every mission now has the same three roles, a melee **grunt**, a ranged **shooter** and a
**charger** brute (the elite), plus two bosses on waves 5 and 10 built from the charger key. Each
era upgrades their gear (HP and damage) and their numbers (count per wave). Village keeps its keys
(`raider`, `archer`, `brute`). Missions 2–4 are **draft balance**: placeholder rigs, the C1 run
model, and no playtest data. Stop 3 re-balances them.

## The four missions at recommended power (`py tools/sim_combat.py`)

| mission | rec. power (loadout) | counts w1→w10 | run | HP floor | damage taken | cash | material | Valor | 0.6x dies | party 4 run |
|---|---|---|---|---|---|---|---|---|---|---|
| Raider Woods (village) | 60 (2/1, 57) | 5 → 8 | 8:32 | 23 % | 173 = 1.2 bars | 142,185 | 256 Timber | 35 | wave 6 (4:11) | 8:59 |
| Rail Yard Outlaws (boomtown) | 220 (6/3, 212) | 6 → 9 | 8:29 | 15 % | 372 = 1.2 bars | 14,721,166 | 271 Steel | 35 | wave 6 (4:16) | 9:07 |
| Blackout Blocks (metropolis) | 680 (8/6, 677) | 7 → 11 | 8:21 | 31 % | 556 = 1.0 bars | 1.65B | 313 Circuits | 35 | wave 7 (4:03) | 9:03 |
| Crater Breach (orbital) | 3400 (11/10, 3400) | 7 → 11 | 8:37 | 31 % | 1,514 = 1.0 bars | 167.2B | 323 Alloy | 35 | wave 7 (2:21) | 9:18 |

Numbers are measured under the combat server's final Stop 1 rules, mirrored exactly in the model
table below.

- **Recommended power** sits just under the symmetric tier that the era's median income unlocks
  (assertion 2): Boomtown 5/5 = 230, Metropolis 8/8 = 696, Orbital 11/11 = 3834. This is the
  Village rule (60 under 64). Orbital is set lower, at 3400, so the melee-first fixture resolves
  to a sensible Ion Blade + Laser Pistol. At 3600–3800 the same rule picks Nova Blade + a band-2
  rifle.
- **Enemy HP** = the Village row × (era recommended DPS ÷ Village recommended DPS) × a per-era
  factor (Boomtown 0.8, Metropolis 0.6, Orbital 0.7). **Enemy damage** = the Village row × (era
  max HP ÷ Village max HP) × (0.85 / 0.85 / 0.6). The factors are below 1 because each era fields
  more bodies. The run model's rule still holds: the trickle, not HP, sets wave length (C1), so
  HP and damage only buy pressure.
- **Cash** is the Village row × 100 per era (contract). **Materials** stay flat: 1 / 1 / 4 per
  enemy, 256–323 per run, so a band always costs about 2 runs. `speed`, `reach`, grunt and shooter
  `attackCooldown`, the wave `composition` breakpoints (3 / 7), growth rates and every boss
  `hpMult` / `cashMult` / `materialsMult` / `valor` are the Village values.
- **Charger `attackCooldown` is 4.0 in every mission** (Village 2.6 → 4.0). Under the review
  rules it is the recovery between charges, not a ring swing. At 2.6, the Village brutes
  charging on repeat from outside the ring killed the recommended player on wave 10 (floor 0 %).
  With it went **Village brute `damage` 5 → 6**: each charge now hits harder and comes less
  often (floor 18 % at the time; 23 % under the final rules above). **Boomtown brute `damage` 9 → 13 and grunt 5 → 7**: the band-2
  axes carry `groundSlam`, whose stun now cancels boss wind-ups, so the 0.6x player (4/3,
  Hatchet) survived to wave 10 until these rose. Metropolis and Orbital needed only the
  cooldown.
- Run cash as a share of the era's remaining slot cost falls from **0.95 %** (Village) to **0.17 % /
  0.03 % / 0.01 %**. The tycoon's era cost grows about ×600, ×700 and ×370 per era, and combat cash
  grows ×100. The 25 % cap is nowhere near binding. Whether combat cash should stay a garnish in
  late eras is a Stop 3 decision.

## Chargers and boss patterns, and how the sim models them

| mission | Chief (wave 5) | Warlord (wave 10) |
|---|---|---|
| village | slam 10 s / 1.0 s windup / r10 / ×2.0; charge 14 s / 0.9 s / ×2.5 | slam 9 s / r12 / ×2.0; charge 14 s / ×2.5; summon 2 raiders / 24 s / 1.5 s |
| boomtown | as Village | slam 9 s / r12; charge 13 s; summon 2 grunts / 24 s |
| metropolis | charge 12 s / ×2.5; slam 10 s / r11 / ×2.0 | slam 9 s / r12; charge 12 s; summon 2 shooters / 24 s |
| orbital | slam 9 s / r12 / ×2.0; charge 13 s / ×2.5 | slam 8 s / r14; charge 12 s / 0.8 s; summon 3 grunts / 22 s |

Every boss `damageMult` went from **1.0 to 0.5**. The boss's plain swing is now weak, and the
telegraphed slam and charge (×2.0 / ×2.5 of the halved number, i.e. ×1.0 / ×1.25 of the old swing)
carry the danger. Danger now sits in the readable wind-ups that Stop 1 is about, and a player who
dodges takes less than before. With patterns on top of a ×1.0 boss, Village wave 10 killed the
recommended player in every combination tried (floor −4 % with only a slam; measured under the
first C2.5 model, before the review rules).

Model (`tools/sim_combat.py`). It mirrors the combat server's final Stop 1 rules in
`EnemyService` / `WaveService`; every `ai.*` key below is read from `Combat.json`.

| term | model |
|---|---|
| melee ring | `ai.maxMeleeAttackers` (3) slots per party member, bosses first; the rest do not swing. **Chargers are never slotted.** Moving 4 → 3 changed no C1 number |
| enemy windup | every ring swing lands `ai.telegraphSeconds` (0.45) after arrival in reach. `enemy.attackWindupSeconds` is gone and is not read |
| charger | ready when t ≥ `nextAttackAt` (spawn time at first). Charges when the target is within `[reach, chargeDistance × chargeTriggerFraction]` (6–23.4 studs; LOS assumed); walks in if further, backs out if closer. Winds up `chargeWindupSeconds`, dashes `chargeDistance` at speed × `chargeSpeedMult`, and hits the target once as the dash crosses it, for `damage × CHARGE_LAND_RATE` (0.5; the lane width `chargeLaneHalfWidth × bodyScale + memberRadius` is what the land rate stands in for). Then `nextAttackAt` = dash end + `attackCooldown`, circling toward `holdRadius`. At recovery end, if the target is in reach and the charger has not struck since its last charge, it strikes once (`telegraphSeconds`, `damage × land`), leaving `nextAttackAt = now`. Standing still, the player is never in reach at recovery end (the charger is out at `holdRadius`), so in the sim that strike never fires |
| charger cancel | a stun in windup, dash or strike cancels the action: `nextAttackAt = max(nextAttackAt, now + attackCooldown × cancelCooldownFraction)`. Stagger also cancels a **non-elite** charger's windup, but every mission's charger is elite and stagger is not modelled |
| boss built from the charger key | walks in like melee and takes a ring slot; it charges **only** through its `charge` pattern |
| boss patterns | first use at spawn + `cooldown`. One action at a time: round-robin from after the last pattern used, the first one ready and viable fires and sets `readyAt = now + windupSeconds + cooldown`. After it lands, the plain swing waits `max(nextAttack, now + postPatternAttackDelay)` (0.8). The boss keeps its plain swing during a windup (the rules do not suspend it); it does not swing mid-dash |
| slam | viable when the target is within `(radius or defaultSlamRadius) + slamTriggerMargin`. On landing it hits members within `radius + memberRadius`, for `damage × damageMult × PATTERN_LAND_RATE` (0.5), on **every** party member |
| charge pattern | viable when the target is within `[reach, chargeDistance × chargeTriggerFraction]`. After the windup the boss really dashes `chargeDistance`: it hits once as it crosses the target, ends past it, and walks back into the ring |
| summon | viable when the key exists. Accepted = clamp(`count` or `defaultSummonCount`, 0, `maxAlive − alive − queued`); overflow is **dropped**. The bodies spawn on the next tick with the current wave's stats, count toward the boss's group, and pay normal rewards |
| stun | an ability with `stunSeconds` (`groundSlam`) stuns enemies **inside its radius**. A boss pattern in its windup is cancelled and `readyAt −= cooldown × stunPatternRefundFraction`; a boss mid-dash stops, with no refund; a boss that dies mid-action cancels it. Damage keeps the C1 "an AoE covers the fight" assumption, but the stun does not: freezing a rig at the rim would park it outside a standing player's melee for good |
| not modelled | stagger (`staggerSeconds`, `staggerShove`, `bossStaggerMult`) delaying or shoving enemies, which makes the numbers pessimistic; `retargetHysteresis` and `dashTimeoutPad` (single-target, open-lane sim); positions beyond one dimension |

**Summons only on the last boss wave** (assertion 14). Summoned kills land in the tempo window,
which is sized for the wave's count. On the Chief's wave, two raiders per 15 s pushed tempo to
1.46 and merged waves 6 and 7 into a live boss fight: the recommended player died on wave 7 at
4:16. On Orbital, a wave-5 summon pushed the party-2 boss wave to ×1.41 of solo (assertion 11's
band is ±35 %). Both were measured under the first C2.5 model; the rule stands under the review
rules because it depends only on the tempo window. After wave 10 nothing can merge, so a summon there only lengthens the fight.

## The director and missions 2–4 (`windowSeconds 10`)

The expected kills per 10 s window are count ÷ 3: Village 1.7–2.7, Boomtown 2.0–3.0, Metropolis
and Orbital 2.3–3.7. More kills per window means finer tempo steps (0.27–0.5 instead of 0.37–0.59),
and the recommended player reads 0.72–1.01 in every mission, with **no merges**, as in C1.

**At 2x power, missions 2–4 never merge**, so assertion 7 is now asserted for Village only. The
others are printed with "(draft, reported)". The cause is the formula, not these configs.
`SpawnInterval` divides by the same tempo it is measured by, so a player who kills everything on
arrival keeps tempo wherever it already is, and at `tempoMin` that is a fixed point. The only
escape is a kill **burst**: an AoE that clears a backlog built up behind a boss. Village's 2x
loadout carries `groundSlam` (hits the whole field) and merges five times. Boomtown's and
Metropolis's 2x loadouts carry `dashStrike` (2 targets) and never burst. Across about 250 settings per era of
HP, damage, count, `targetWaveSeconds` and boss HP, Boomtown and Metropolis merged at 2x only where the
recommended player died. Orbital's 2x (12/12, `bladeStorm`) merged only at count 5, which undoes
the "more numbers" of the horde. The reverse also happens: the **under-geared** Orbital player
(10/9, `bladeStorm`) merges six times and dies sooner because of it.

This is the C1 note "tempo as lag rather than rate" becoming load-bearing. It is a change in
`Combat.Tempo` / `WaveService`, reported to the lead, and not something to tune around in
mission files.

## Tool changes

- `MELEE_CONTACT_SLOTS` is gone; the ring reads `Combat.json ai.maxMeleeAttackers`.
- The sim reads every new `ai` key directly from `Combat.json` (`memberRadius`,
  `cancelCooldownFraction`, `chargeTriggerFraction`, `slamTriggerMargin`, `defaultSlamRadius`,
  `defaultSummonCount`, `postPatternAttackDelay`, `stunPatternRefundFraction`); no fallbacks.
- `loadout_for_power` = `gear_for_power`, plus Ascension levels (melee first) once both slots
  are at tier 12. The Orbital 2x fixture (6800) and every band-3/4 Overdrive × 3 fixture ask for
  more than 12/12 carries (Orbital Overdrive: 30,600 → 12/12 + Ascension 3/2). Below tier 12 it
  is exactly `gear_for_power`, so no Village number moved.
- Assertion 13's newbie is the **0.6x fixture's loadout**: Stick + Sling in Village (unchanged), the
  previous band's gear elsewhere. A Stick in an Orbital run deals 0.1 % of the damage, which C2
  already ruled is spectating.
- **Assertion 14 (new), horde shape:** exactly one melee, one ranged and one elite charger key;
  bosses on [5, 10], built from the charger; 2–3 patterns each; summons name a mission key and
  sit on the last boss wave; a full run at recommended power yields 250–350 of the era material.

## The fourteen assertions, as measured

| # | assertion | measured |
|---|---|---|
| 1 | unlock ladder | unchanged (bands enter at 0 / 4 / 4 / 4 %) |
| 2 | power at median ≥ recommended | 64 ≥ 60, 230 ≥ 220, 696 ≥ 680, 3834 ≥ 3400 |
| 3 | run length at recommended, ±50 % of 8 min | 8:32, 8:29, 8:21, 8:37, all 10/10 |
| 4 | run cash ≤ 25 % of the era still owed | 0.95 %, 0.17 %, 0.03 %, 0.01 % |
| 5, 6 | shares, away efficiency | unchanged |
| 7 | 2x merges (Village asserted) | Village 5; the others 0 (reported) |
| 8 | 0.6x dies on wave 6 ± 2 | 6, 6, 7, 7 |
| 9 | composition | 320 combinations exact |
| 10 | Overdrive at 3x its recommended power pays ≥ 3x | ×5.07, ×5.10, ×4.92, ×4.85, all cleared |
| 11 | party boss waves within ±35 % | ×0.74–×1.14 across all missions and parties 2–4 |
| 12 | 10:1 mentor duo | 5 / 0 in every mission |
| 13 | mentee floor | idle 0 %; 0.6x newbie 5.4 / 5.1 / 7.7 / 10.6 % → paid 10 |
| 14 | horde shape | all four; materials 256 / 271 / 313 / 323 |

`sim_economy.py --check` output is byte-identical before and after.

## What Stop 3 must re-check

1. **The director at 2x.** Once tempo measures lag, restore assertion 7 for every mission
   (`MERGE_ASSERTED_MISSIONS`) and re-read the Orbital under-geared merges.
2. **Pattern land rates.** `CHARGE_LAND_RATE` and `PATTERN_LAND_RATE` (0.5) are guesses. Measure
   dodges per telegraph in Studio. Most of the recommended player's wave-10 damage comes from
   patterns, so these two numbers move the HP floor more than any enemy `damage`.
3. **The charger cycle.** Recharges are modelled, and the charger `attackCooldown` (4.0) is
   the main brute lever. Measure how often the lane really crosses a player. The sim lands every
   crossing at 0.5 and never sees the post-recovery strike, because the charger is out at
   `holdRadius`. A player who closes on a recovering brute gets struck, which the sim does not
   see.
4. **Stun is strong.** A `groundSlam` stun cancels a boss wind-up and refunds only half its
   cooldown. That is what kept the Boomtown 0.6x player alive until the brute and grunt damage
   rose. Watch the band-2 axes against every boss.
5. **Late-era cash** (0.17 / 0.03 / 0.01 % of the era). This is a design call: keep it a garnish,
   or scale enemy `cash` by the era's cost growth instead of ×100.
6. **Missions 2–4 in play.** Nothing here has been fought. The mission files are drafts, and the
   per-era HP/damage factors are the first things to move.
7. **Co-op safety** is unchanged from C2 (party 4 floors 73–97 %), and the Orbital party floors
   are the highest. Re-check together with the per-head reward carry-overs.

## Commands used

```
py tools/sim_combat.py --check              # fourteen assertions, exits 0
py tools/sim_combat.py                      # all four missions: 1x / 2x / 0.6x, cash, co-op
py tools/sim_combat.py --era 4 --overdrive  # one mission under Overdrive
py tools/sim_economy.py --check             # unchanged, byte for byte
```

# P1 — Proving Grounds starting values

Starting points for the test range (`Config/ProvingGrounds.json`, arena
`Layouts/Arenas/ProvingGrounds.luau`). Every number is live-tunable from the RangePanel; these
are the values Ben meets on the first Play, chosen against `docs/COMBAT_DESIGN.md` pillars 1
(crowds and numbers), 3 (movement is combat) and 4 (every weapon feels different). Hit counts
assume the crowd kinds below and no crits. Armour is a **flat per-hit cut** (lead ruling):
`dealt = max(amount − armor, amount × 0.1)`, so small hits are worth little against it and heavy
hits break through.

## The range

- 220 × 220, light grey SmoothPlastic floor (160, 161, 166), 4-stud concrete fence. The lobby pad
  is at **(0, 90)**, near the +Z edge; the spawn faces −Z down the dummy lane.
- `dummySets[*].at` are **arena coordinates**: a row d studs in front of the spawn sits at
  z = 90 − d. Rows are at z 80 / 65 / 40 / −10 (10 / 25 / 50 / 100 studs).
- Distance lines: 0.2-stud Neon strips across the lane (|x| ≤ 20) with tally posts outside it
  (1 post = 10, 2 = 25, 3 = 50, 4 = 100). Colours white, yellow, cyan, violet.
- Jump staircase left of the spawn (8 / 16 / 24 tall, adjacent, 8×8 tops), stand-alone 16 and 24
  pillars right of it, six concrete cover pieces on the right flank (x 28–53, z 31–79), and a 10-tall
  backstop at 120 studs (rifle range). The lane itself stays flat.
- Armoured recoloured steel blue (70, 100, 150): the lead's grey (120, 128, 140) vanished on a grey
  floor. Fodder is a warmer red (205, 86, 64).

## Crowd kinds

| Kind | HP | Armour | Knockback × | Speed | Why |
|---|---|---|---|---|---|
| fodder | 40 | 0 | 1.0 | 12 | Dies in 1–3 hits from every crowd weapon; slower than the player (20) so kiting works. |
| armoured | 160 | 18 (flat) | 0.35 | 9 | Light hits shrink to 1.6–6 damage, and heavy hits keep most of their damage (Shockwave 26–52, Launcher 42, rifle 24, or 66 on a head). Heavy weapons kill it in 4–7 hits (2.5–4 s). Light ones need 14–18 hits and live on their finisher. Barely moved by light hits. |
| boss | 10 000 | 0 | 0 | 6 | A DPS sponge: 1–2 minutes of sustained fire at 75–100 DPS, so the 5 s DPS window settles. |

## Weapons

| Variant | Shape | Rate/s | Cap | Damage | Fodder hits | Armoured hits (flat 18) | Boss DPS | Feel |
|---|---|---|---|---|---|---|---|---|
| Sword A Wide arc | arc 160°, 10 | 2.5 | 10 | 24, chain 1/1/1.8 | 2 / 2 / 1 | 14 (6, 6, 25) | 76 | The all-rounder: wide sweep, finisher one-shots. |
| Sword B Spin finisher | arc 110°, 9; finisher 360° | 3.4 | 8 | 16, chain 1/1/2.6 | 3 / 3 / 1 | 18 (1.6, 1.6, 24) | 83 | Fast light flurry that pays off on a full spin. Lowest knockback (8) keeps the crowd in reach. Cap raised 6 → 8 for the spin (below). |
| Sword C Shockwave | sphere 10 | 1.3 | ∞ | 44, chain 1/1.25/1.6 | 1 | 5 (26, 37, 52) | 73 | Slow crushing ring: every hit clears fodder, launch 10 throws them. |
| Gun A Shotgun | cone 26°, 24, 8 pellets | 1.1 | ∞ | 22/pellet | 2 pellets | 5 shots (32 each) | 194 point-blank | Close burst, knockback 28. The single-target outlier, paid for by a 24-stud range. |
| Gun B Piercing rifle | ray 120, width 0.8 | 2.4 | 8 | 42 | 1 | 7 (3 on heads) | 101 (202 on heads) | Lines of enemies: one shot kills everything on the line, up to 8. |
| Gun C Launcher | sphere splash 10, speed 110 | 0.75 | ∞ | 60 | 1 | 4 | 45 | Visible slow shell, launch 16: the "crowds fly" weapon. Weak on a single target by design. |

Every variant differs on at least three of shape, rhythm (0.75–3.4 attacks/s), cap and knockback
(8–34). Fodder at 40 HP sits just under the 42/44 one-shot values, so the rifle, Shockwave and
Launcher one-shot and the others need 2–3 hits. Keep that margin: a one-shot tuned to exactly the HP
fails on any rounding.

Sword B's finisher is a full 360° spin (`finisherArcDegrees`, lead). Its single-target DPS does not
change. Surrounded, though, the spin now reaches enemies behind you. Cap 6 would leave a visibly
struck ring half untouched (pillar 2), so the cap is 8. Chain 2.6 stays: the spin's 41.6 is just
over fodder's 40.

Slam against armoured deals 27, so 6 slams. It stays a crowd tool, not an armour breaker.

## Movement

| Key | Value | Why |
|---|---|---|
| jumpHeight | 18 | 2.5× Roblox's 7.2. Airtime 0.86 s, 17 studs of horizontal travel at walk speed. A 16 platform clears by 2 studs. |
| doubleJumpHeight | 12 | Total reach 30, so the 24 tower needs the double jump and the 16 tower doesn't. That's the range's height ladder. |
| walkSpeed | 20 | Faster than fodder (12) and armoured (9), so moving works as a dodge. |
| dash | 20 studs in 0.15 s, 0.8 s cooldown, 0.25 s i-frames | 133 studs/s reads as a snap, not a slide. The i-frames outlast the dash so its end is safe. |
| slam | min 5, radius 12, 45 damage, 1.8 s cooldown, fall 140 | A slam from any real jump one-shots fodder in a 24-stud circle. The cooldown stops slam-spamming from outclassing Shockwave. |
| airAttackHangSeconds | 0.3 | Long enough to string an air combo above a crowd. |

## Shooting and controls

- Bloom goes from 0.4° to 7°: +1.5° per shot, +10°/s while moving, recovering at 9°/s. The first
  shot after 0.3 s idle is exact. This is Fortnite's shape: tap-fire is accurate, spraying on the
  move is not.
- ADS: FOV 50, bloom ×0.35, speed ×0.55.
- `critMult` 2.0 (was 1.75): a yellow number that is exactly double reads at a glance.
- `autoFireAssistDegrees` 5 (was 4): on a phone thumb, a 1.3-stud fodder at 50 studs subtends
  about 3°, so 4° left almost no assist at range.
- Feedback layers all start at 1.
- `snapshotHz`, `maxAlive` and `stressCount` are unchanged (the contract budget).

# P2 — new families

Tier-1 starting values for the four new families in `Config/ProvingGrounds.json`: greataxe, spear,
longbow and splitbow. The six P1 families (broadsword, warhammer, spinblade, shotgun, rifle,
launcher) are unchanged, because Ben approved them; they appear below as the reference.
Targets are from `docs/WEAPONS.md`: melee crowd DPS ~420–590, ranged crowd ~200–320, splitbow ~210.

## How the numbers were measured

A scratch simulator mirrors `HitShapes` (padded sector, capsule, ray and sphere tests, fodder body
radius 1.3) and `RangeService` (cap, pierce, chain, the finisher arc, flat armour 18 with the 0.1
floor). It places a crowd in a square grid:

- **Melee:** you stand at the crowd's front edge.
- **Ranged:** the crowd's front is 20 studs away (8 for the shotgun).
- **Aim:** lateral offset and aim are randomised.

At **6-stud spacing** (a loose, chasing crowd), the six approved families land within about ±20% of
their WEAPONS.md "typical hits" figures. The rifle is the exception: pierce 8 fills up on any line.
So 6 studs is the crowd DPS in the table. The range's own dummy crowds (`crowd30`, `crowd100`)
are packed at **3 studs**, where uncapped shapes roughly triple: Warhammer 1 606, Greataxe A 2 031,
Spear ~1 350, Longbow A full 738. Expect Ben to see those bigger bursts on the dummies.

Bow cadence:
- **Full charge:** one shot per `max(chargeSeconds, 1/rate) + 0.05` s of release/redraw slack.
- **Tap:** one shot per `1/rate` at `minChargeFraction`.

## Tier 1, all ten families

"Surr." = standing inside the crowd. Fodder 40 HP, armoured 160 HP with flat armour 18.

| Family | Var | Era | Single DPS | Crowd DPS (edge / surr.) | Fodder hits | Armoured hits | Feel |
|---|---|---|---|---|---|---|---|
| Broadsword | A | 1 | 76 | 543 / 622 | 2 (finisher 1) | 14 | approved |
| Warhammer | A | 1 | 73 | 495 / 990 | 1 | 5 | approved |
| Spinblade | A | 2 | 83 | 499 / 562 | 3 (finisher 1) | 18 | approved |
| **Greataxe** | A Wide cleave | 2 | 71 | 563 / 722 | 1 | 5 | 200°, slow (1.3/s), knockback 40: shoves the crowd away |
| **Greataxe** | B Fast chop | 2 | 86 | 525 / 545 | 2 (finisher 1) | 6 | 110°, 1.9/s, knockback 10 + launch 14: pops them up in reach |
| **Spear** | A Pike thrust | 3 | 86 | 378 / 532 | 1 | 6 | 14 × 4.4 line, heavy (42), 1.7/s |
| **Spear** | B Long lunge | 3 | 96 | 348 / 532 | 2 (finisher 1) | 9 | 18 × 2.0 needle, 2.4/s, pushes the line back (22) |
| **Longbow** | A Pierce + blast | 1 | 48 full / 40 tap | 275 full / 150 tap | 1 full / 2 tap | 5 full / 23 tap | 1.0 s draw, pierce 5, full charge bursts r5 for 25 |
| **Longbow** | B Quick shot | 1 | 80 full / 44 tap | 185 / 102 | 1 / 2 | 7 / 40 | 0.4 s draw, 2/s, pierce 3, flat and fast (200, g 12): the single-target bow |
| **Splitbow** | A Fan of 7 | 1 | 31 | 210 | 2 volleys | 20 volleys | 7 × 26 over 40°, 1.2/s: a dense fan that spreads damage |
| **Splitbow** | B Wide fan of 5 | 1 | 42 | 200 | 1 volley | 7 volleys | 5 × 42 over 70°, splits at 6, 1.0/s: every arrow a kill |
| Shotgun | A | 2 | 61 | 346 | 1 | 5 | approved |
| Piercing Rifle | A | 2 | 101 | 556 | 1 | 7 | approved |
| Launcher | A | 3 | 45 | 312 | 1 | 4 | approved |

## Why these values

- **Greataxe A:** damage 40 → 42. At 40, a fodder died only if the kill check used `<= 0`; 42 is a
  safe one-shot. Rate 1.4 → 1.3 keeps crowd DPS inside the band at 563.
- **Greataxe B:** the lead's B was a narrower, faster copy of A with the same shove. It is now the
  **launcher axe**: 110°, knockback 10, launch 14. The pair then plays differently (A clears space,
  B juggles) at about the same crowd DPS. B's single DPS is higher (86) to pay for the smaller arc.
- **Spear:** it sits at the bottom of the melee band (348–378 edge) on purpose. Its 14–18 stud
  reach hits the crowd from outside it, which WEAPONS.md already priced lower (~290).
  - A is the heavy pike: width 4.4, 42 damage, one-shots fodder.
  - B is the long needle: width 2.0, 30 damage, faster, pushes the whole line back.
  - Raising both damages ~15% would put them in the band, if Ben finds the spear weak.
- **Longbow A:**
  - **Charge:** `minChargeFraction` 0.4 → 0.5 and `chargeSeconds` 0.8 → 1.0. A full shot now deals
    2× a tap's arrow damage (50 vs 25) plus the burst, 3.1× a tap's damage per shot on a crowd.
  - **Burst:** r6 × 0.6 → r5 × 0.5, which keeps full-charge crowd DPS at 275 (it was 360+).
  - **Fodder:** a full shot one-shoots it, a tap needs 2.
  - **Armour:** it shows the point of charging. A tap is cut to 7, so 23 hits; a full shot takes 5.
- **Longbow B:**
  - Damage 38 → 44: at 38 a full-charge B could not one-shot fodder.
  - Pierce 2 → 3, so its crowd DPS (185) isn't negligible.
  - The flatter, faster arrow and 0.4 s draw make it the precision alternative (single DPS 80).
- **Splitbow A:** 26 per arrow as WEAPONS.md proposed. On any crowd wider than the fan, all 7
  children land, so rate 1.6 → 1.2 brings it to 210. A volley never hits one enemy twice
  (RangeService's shared `Volley`), so single DPS is one arrow's worth, 31. That makes splitbow the
  purest crowd weapon in the roster.
- **Splitbow B:** 5 arrows × 42, no pierce, 70° fan, splitting at 6 studs, 1.0/s: 200 crowd DPS.
  Every arrow kills a fodder, so a volley reads "×5 kills". A's 26-damage arrows need two volleys.
  Against armour, B needs 7 volleys (24 each) and A needs 20 (8 each). Neither is for elites.

## Flags for the lead

- **Rifle (approved, unchanged):** 556 crowd DPS at 6-stud spacing, above the ranged band.
  WEAPONS.md assumed 3 hits a shot; pierce 8 through any real line gives ~5.5. It's not mine to
  retune (Ben approved it). If it outclasses the bows in the range, `pierce` 8 → 5 is the knob.
- **Arrow semantics, as RangeService implements them:**
  - an arrow hits `1 + pierce` enemies, and the volley `cap` limits that;
  - split children share one cap and skip enemies the volley already hit.

  Longbow A's pierce 5 / cap 5 therefore hits 5, and B's pierce 3 / cap 3 hits 3; the cap is the
  real limit in both. The hitscan rifle instead hits `max(1, pierce)`, so `pierce` means one fewer
  enemy on a hitscan ray than on an arrow. Worth unifying before P3 adds more piercers.

# P3 — abilities and the SMG / Beam / Chain Gun families

Tier-1 values for the 13 `ability` blocks and the new families `smg`, `beam` and `chaingun` in
`Config/ProvingGrounds.json`. The ten P1/P2 families are unchanged; no P3 rule touches their
numbers. Targets come from `docs/WEAPONS.md` §2 and the P3 brief:
- SMG ~108 single and ~108 crowd;
- Beam ~250 crowd;
- Chain Gun ~240 crowd;
- one cast = 3–5 s of the family's own crowd DPS;
- kill refunds bring a busy crowd's cooldown to 40–60% of base, never below the floor.

## How the numbers were measured

`py tools/sim_range.py` is the P2 scratch simulator made permanent. `--check` exits 1 when a
shipped value leaves a band, and the bands are constants at the top of the script. It reads
`ProvingGrounds.json` and mirrors the server as built:

- **HitShapes, in 3D:** the arc slab, sphere, capsule, cone, ray entry, Fan and Scatter.
- **RangeService:** gather, then nearest-first, then cap. Pierce is the TOTAL number of enemies.
  Split volleys share one hit set. Chains jump body centre to body centre, to the nearest live
  enemy not yet hit, for base damage × falloff^jump. Armour is flat.
- **AbilityService:** `ceil(duration / tick − 1e-6)` ticks (Whirlwind 8, Blade Storm 12, Arrow
  Rain 12, Storm Coil 8). Overload slices fire at `(i−1)·duration/count` with one exclude.
  Overcharged cap is 0 and Storm Coil cap is `targets`. The Mag Dump pierce ignores the SMG's cap
  of 1. Refunds apply only while cooling down, and the floor is `min(minCooldown, cooldown)`.

Method:
- **Crowd:** a square grid of `crowd.stressCount` fodder (12 × 12) at 6-stud and 3-stud spacing.
  The P2 placement and aim are kept: melee stands 2.6–3.6 studs from the front, ranged 20 studs
  away (cone guns 8), and the lateral phase and ±1.5 aim are random. Rays fly level at chest
  height, so only a ray wide enough to reach the heads crits. Knockback and Blade Storm's pull
  are ignored.
- **Crowd DPS:** damage per attack on immortal fodder × rate, the WEAPONS.md basis.
- **Damage / cast:** the whole timeline on immortal fodder, the same basis. Kills are counted on
  real 40-HP fodder.
- **Ability geometry:**
  - Zones and Leap Smash aim at the crowd's centre, clamped to `castRange`.
  - Whirlwind walks straight in at walkSpeed × moveSpeedMult.
  - Earthquake and Impale Dash start at the melee front.
- **Burst:** damage / cast ÷ the default variant's 6-stud crowd DPS, floored at single DPS.
  WEAPONS.md defines crowd DPS as single DPS × enemies hit, so it can't be lower.
- **Effective cooldown:** a 90 s fight on the 6-stud grid. Dummies respawn after the stress set's
  3 s. The family attacks whenever the busy lock allows and casts the moment the server would
  accept it. Every kill refunds the ability. The `rng3` column repeats the fight on the range's
  own `crowd100` (3-stud, 4 s respawn).
- **Ground fallback:** a shell that touches no body before the crowd's first row bursts on the
  floor there, as P2 did. The real aim ray falls into the crowd, while the sim's level ray can
  slip between aligned columns.

The approved families reproduce the P2 table within 4% at the edge or front: broadsword 545,
warhammer 493, spinblade 503, greataxe 556 / 530, spear 384 / 338, longbow 279 / 182,
splitbow 211 / 200, shotgun 351, rifle 538, launcher 321. Only the "surrounded" melee column
moved (spear 406 / 361, where P2 had 532). P2's surround placement kept the rows half a cell off the aim line, which put
two lines in every thrust. The placement is now uniform.

## New families (tier 1)

| Family | Var | Era | Single | Crowd 6 | Crowd 3 | Feel |
|---|---|---|---|---|---|---|
| SMG | A Spray | 3 | 108 | 108 (grid 75) | 108 | 9 × 12/s, bloom ×0.35: a steady, accurate hose |
| SMG | B Heavy | 3 | 112 | 112 (grid 74) | 112 | 16 × 7/s, bloom ×0.6, knockback 6: punchier, kicks, rewards short bursts |
| Beam | A Sweep | 4 | 50 | 257 | 1 038 | 1.4 wide, reach 55, pierce 30, 5/tick: paint the crowd; best in a packed crowd |
| Beam | B Lance | 4 | 120 | 225 | 360 | 0.5 wide, reach 100, pierce 3, 12/tick: a long line, melts a boss |
| Chain Gun | A Chain lightning | 4 | 72 | 232 | 242 | 60 × 1.2/s, 4 jumps (r12, ×0.8): slow heavy bolts that reach a loose crowd |
| Chain Gun | B Arc storm | 4 | 72 | 246 | 248 | 30 × 2.4/s, 3 jumps (r9, ×0.9): rapid, even arcs that need a tight pack |

The SMG's "grid" figure is lower because a 0.5-wide level bullet slips between aligned 6-stud
columns 35% of the time. That comes from the grid, not the gun. On the packed grid, and in any real
crowd, every bullet finds one body, so its crowd DPS equals its single DPS, as WEAPONS.md intends.

## Abilities (tier 1, final)

"Hits" counts every hit, one per tick per enemy. "Kills" is on 40-HP fodder. "Eff" is the mean
time between casts in the busy crowd, and "rng3" is the same on `crowd100`.

| Ability | Basis | Dmg / cast | Burst | Busy | Hits | Kills | Dmg (3-stud) | Base | Floor | Refund | Eff | Eff % | rng3 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Whirlwind | 545 | 2 293 | 4.2 s | 2.4 | 104 | 28 | 8 088 | 10 | 4 | 0.15 | 5.0 | 50% | 3.9 |
| Earthquake | 493 | 2 029 | 4.1 s | 0.2 | 42 | 24 | 6 595 | 12 | 5 | 0.25 | 5.7 | 47% | 4.9 |
| Blade Storm | 503 | 1 952 | 3.9 s | — | 122 | 10 | 7 104 | 11 | 4.5 | 0.3 | 5.4 | 49% | 4.4 |
| Leap Smash | 556 | 2 150 | 3.9 s | 0.55 | 24 | 24 | 8 679 | 10 | 4 | 0.15 | 4.8 | 48% | 4.4 |
| Impale Dash | 338 | 1 370 | 4.1 s | 0.25 | 11 | 11 | 5 266 | 8 | 3 | 0.35 | 3.8 | 47% | 3.2 |
| Arrow Rain | 279 | 1 166 | 4.2 s | — | 146 | 12 | 4 660 | 12 | 5 | 0.2 | 6.2 | 52% | 4.9 |
| Volley | 211 | 838 | 4.0 s | — | 20 | 20 | 781 | 9 | 3.5 | 0.125 | 4.5 | 50% | 4.5 |
| Slug Burst | 351 | 1 282 | 3.7 s | 0.45 | 29 | 10 | 4 974 | 9 | 3.5 | 0.4 | 4.7 | 52% | 3.5 |
| Overcharged Shot | 538 | 3 876 | 7.2 s (boss 3.4 s) | 0.35 | 11 | 11 | 7 888 | 10 | 4 | 0.3 | 4.7 | 47% | 4.0 |
| Cluster Shell | 321 | 1 233 | 3.8 s | — | 25 | 10 | 4 082 | 11 | 4.5 | 0.45 | 5.3 | 48% | 4.4 |
| Mag Dump | 108 | +721 | 6.7 s (boss 4.0 s) | lock, fire allowed | 96 | 9 | +1 296 | 10 | 4 | 0.5 | 5.0 | 50% | 3.9 |
| Overload Sweep | 257 | 993 | 3.9 s | 1.0 | 22 | 22 | 2 667 | 12 | 5 | 0.2 | 6.0 | 50% | 4.9 |
| Storm Coil | 232 | 1 039 | 4.5 s | — | 64 | 16 | 1 039 | 12 | 5 | 0.15 | 5.8 | 48% | 5.6 |

Mag Dump's damage is its gain over the same 2 s of normal fire. On the boss: Overcharged deals
340 on the body and 680 on the head, 3.4 s of the rifle's 101 single DPS. Mag Dump adds 432, 4.0 s
of the SMG's 108.

## Where the starting values missed

With the lead's values, `--check` failed 22 times:

- **Too weak:**
  - Blade Storm 2.4 s, Leap Smash 2.7 s, Impale Dash 1.6 s.
  - Whirlwind 3.1 s beat its own 2.4 s channel by only 0.7 s, so swinging would nearly match it.
  - Overcharged dealt 150 to a boss, 1.5 s of rifle DPS.
- **Too strong:**
  - Arrow Rain 7.3 s, Volley 6.3 s.
  - Overload Sweep 15.2 s, hitting 79 enemies at 55 each.
  - Storm Coil 15.0 s: 3 zaps × 4 jumps × 10 ticks.
  - Mag Dump 8.6 s on a crowd.
- **Refunds:** 0.3 s per kill put Whirlwind, Leap Smash, Volley, Overload and Storm Coil on their
  floors (32–39%). The slow killers sat above 60% (Impale Dash 65%, Mag Dump 62%). Busy-crowd kill
  rates run from about 2 to 8 per second, so one refund size can't fit every family.
- **Families:**
  - Beam B crowd was 150. With pierce 2 its thin ray averages 1.2 enemies a tick.
  - Chain Gun A was 196 and B 161. A's 0.8-wide bolt missed a column about 19% of the time, and
    B's 2 jumps gave only 81 damage a shot.
- **Volley:** 15 arrows × 30 never killed a fresh fodder. One hit per enemy per volley at 30 is
  under 40 HP.

## Why these values

- **Floors = 40% of base, rounded to 0.5 s** (Earthquake, Arrow Rain, Overload and Storm Coil
  4 → 5; Blade Storm and Cluster 4 → 4.5; Volley and Slug 3 → 3.5). The floor is now the bottom of
  the 40–60% band. The lead's floors (33–37% on the 9–12 s abilities) let a 12 s ability come back
  every 4 s. On the packed `crowd100`, where kills pour in, the final values settle at 39–50%.
- **Refunds per ability** land each at about 50% in the busy crowd: 0.125–0.5 s per kill. The
  size follows each family's kill rate, which also includes the ability's own kills. Fast killers
  (Whirlwind, Leap Smash, Volley, Storm Coil) get 0.125–0.15. Slow single-hit families (Slug 0.4,
  Cluster 0.45, Mag Dump 0.5) get more.
- **Whirlwind** damage 16 → 22: 4.2 s, beating the 2.4 s channel by 1.8 s. That assumes you walk
  it into the crowd. Standing still at the crowd's edge it deals 55% of that (1 258, 2.3 s),
  which is less than swinging for the same 2.4 s. It pays when walked in or cast surrounded.
- **Earthquake** damage 50 → 60 and falloff 0.8 → 0.85. At 0.8 the third ring dealt 39.7 against
  40 HP, leaving the outer fodder alive on 0.3 HP. Now the rings deal 60 / 51 / 43, all one-shots
  (P2's ≥ 42 margin).
- **Blade Storm** damage 10 → 16: 3 ticks kill a fodder, 3.9 s.
- **Leap Smash** radius 12 → 14 and damage 80 → 90. It's a crowd move, so the landing grows rather
  than the per-hit overkill: 24 kills.
- **Impale Dash** range 24 → 30, width 5 → 7, damage 70 → 125: 11 in a line, 4.1 s. The dash is
  now 30 studs in 0.25 s (120 studs/s, against the dash's 133).
- **Arrow Rain** damage 14 → 8: 12 ticks at r10, where 5 ticks kill a fodder.
- **Volley** 15 × 30 (pierce 3) → 10 × 42 (pierce 2): every arrow one-shots, so a cast reads
  "×20 kills" at 4.0 s.
- **Overcharged Shot** width 3.5 → 2.0 and damage 150 → 340. At 3.5 a chest-height shot also
  crossed every fodder's head sphere (crit reach 1.75 + 0.7 ≥ the 1.8 gap), so every hit was a
  crit. Below width 2.2 a crit needs head aim. It's judged on the boss (3.4 s). Its crowd figure
  (7.2 s) is mostly overkill in one line: 11 kills, half of Whirlwind's or Leap Smash's.
- **Mag Dump** rateMult 2.5 → 3.0 and pierce 3 → 2. The boss gains 4.0 s of single DPS. The crowd
  gain drops from 8.6 s to 6.7 s, under the 8 s ceiling for the two single-target abilities.
- **Overload Sweep** range 60 → 34 and damage 55 → 45: 22 one-shot kills across 120°, 3.9 s.
- **Storm Coil** targets 3 → 2, count 4 → 3, damage 30 → 22, duration 5 → 4: 8 ticks of 2 zaps +
  3 jumps, 4.5 s.
- **Beam A** range 60 → 55: 257. **Beam B** pierce 2 → 3: 225.
- **Chain Gun** width 0.8 → 2.0 on both: a hit never misses the column it's aimed at, so the sim
  matches play. **B** chainCount 2 → 3: 246.

## Flags for the lead

- **Refunds cross slots.** The fight counts only the family's own kills, but ruling 2 refunds
  both slots on every kill. A melee weapon killing 6–7 per second therefore keeps the big-refund
  ranged abilities (Mag Dump 0.5, Cluster 0.45, Slug 0.4) on their 40% floors while you melee. The
  floor is the backstop. If it feels spammy, "a slot is refunded only by kills from its own family
  and ability" would decouple them. That's a contract change, not a value.
- **Busy crowd model.** The fight's crowd is a static grid that respawns in place, as the range's
  sets do. Chasing mission crowds (P5) will feed melee faster, which pushes cooldowns toward the
  floor. Re-measure in P5.
- **Armour (flat 18).** Ticking abilities barely scratch armoured enemies: Arrow Rain 8 → 0.8,
  Blade Storm 16 → 1.6, Whirlwind 22 → 4, Storm Coil 22 → 4. Single hits break it: Impale 125 →
  107, Leap 90 → 72, Overcharged 340 → 322, Slug 45 → 27. That matches P1's "crowd tools, not
  armour breakers".
- **The SMG isn't an elite shredder against armour.** Both bullets (9 and 16) fall under armour 18
  and are cut to the 10% floor: about 11 DPS against an armoured dummy, against the rifle's 58. It
  does shred bosses (108 single, and Mag Dump 4.0 s). The Beam's ticks (5 and 12) are the same
  story. If "elite" means armoured, the Heavy SMG needs bullets well above 18: for example 26 ×
  4.3/s keeps 112 single and gives 34 DPS against armour. That's a design call, so I left it.
- **Visual changes for AbilityFx and Feedback:**
  - Overcharged beam is 2.0 wide (was 3.5).
  - Chain Gun bolts are 2.0 wide.
  - Leap Smash ring is r14.
  - Impale Dash capsule is 30 × 7.
  - Overload Sweep reach is 34.
  - Beam A reach is 55.
- **Storm Coil doesn't scale with density.** It deals the same damage on the 3-stud grid as on the
  6-stud one (1 039). Its hits are capped by count (2 zaps + 3 jumps each = 8 enemies a tick), not
  by area. It's the one crowd ability that doesn't explode on packed dummies.
- **Whirlwind needs movement.** Cast standing at a crowd's edge, it loses to plain swings over the
  same 2.4 s (see above). If Ben casts it standing still in the range, it'll feel weak.

# P4 — enemies that fight back

Starting values for the enemies that attack and for the player's body in the range
(`Config/ProvingGrounds.json`; contract: `docs/INTERFACES.md` "P4 contracts"). This part is
**wave 1, "they hurt you"**: the fodder's lunge, the armoured elite's arc, health, going down and
getting up. **Wave 2, "roles"** (the three shooters, the brute, the plate) starts at "Wave 2 —
roles" below.

The wave 1 tables were measured again with wave 2's simulator. It follows rulings 21 (`reach` on
the flat) and 22 (a due impact is never lost), the wave 2 review's rule that enemies of one kind
take turns, and the server as built. So some wave 1 numbers differ from the first version of
this page, the elites' most of all. No wave 1 value changed. One key was renamed:
`crowd.threat.attackersPerPlayer` is now `perPlayer` on each kind, and the fodder's is still 2.

Targets from the contract, all at tier-1 health (130 = `Armory.MaxHp`, 100 + 20 + 10), where the
range pins every player (ruling 17):
- no single hit takes more than 25% of health;
- a player standing still in `fodderRush` goes down in 6 to 12 s;
- a player who keeps moving and dodges every telegraphed hit takes damage only from fodder.

## How the numbers were measured

`py tools/sim_range.py` has a new THREAT section, and `--check` guards its bands. It is the first
part of the simulator where the crowd moves. It mirrors the contract's rules, each named in the
code where it is applied, and follows `CrowdBrain`, `VitalsService` and
`MovementController.ApplyKnock` where the contract leaves a choice:

- **The crowd:** one step per `snapshotHz`. A rusher walks at its kind's speed until its attack's
  `reach`, measured on the flat (ruling 21), and bodies shove each other apart as
  `CrowdService.separate` does. A body in windup or attack is planted. Nothing shoves the crowd
  off the player.
- **An attack:** windup (the facing locks) → impact → `strikeSeconds` → `recover`. At most
  `perPlayer` enemies of one kind are in windup or attack against one player at once: 2 fodder,
  1 elite. An impact that is due still lands when its enemy is hit before the step that would
  notice it (ruling 22).
- **A hit:** the shape is frozen at the impact and tested against the player's root, with no pad,
  `originLagSeconds` later. An i-frame over any moment of that window voids it.
- **Hits decided together** (ruling 18): when a hit that knocks back lands, every other hit on
  that player still waiting for its decision at that moment, or falling inside the
  `knockIframes` it opens, is voided and shows as "dodged".
- **The player:** health, down for `downSeconds` (nobody's target meanwhile), up full with
  `getUpIframes`, regen after `regenDelay`. A knock is a slide that starts at `knockback` studs
  a second and bleeds off at `player.knockFriction`, with `knockIframes` from the hit.
- **His hits:** the default melee family through the same strike code as the tables above, plus
  what `CrowdService.Damage` does to a living enemy: shove, launch, stagger. A hit that staggers
  cancels a `stagger` windup, and a hit of `heavyHit` or more cancels a `heavy` one.

Every run starts when the set loads, with the player on the lobby pad (0, 90), and lasts 60 s.
Three seeds move his start by ±1.5 studs. Health, the dash's server tolerance and the arena come
from `Armory.json`, `Combat.json` and the arena's layout module, so nothing is copied.

Three facts about the sim's player are assumptions, not tunables:
- he reacts 0.25 s after a tell shows, and the sums allow one more crowd step (0.07 s) for a
  lost snapshot;
- he has no ping, so the lag in the commit rule is `originLagSeconds` alone (0.05 s);
- when he fights he always turns to the nearest enemy. A real player turns slower.

## Values

Three values changed from the lead's first set. Everything else holds against the sums below.

| Key | Lead | Now | Why |
|---|---|---|---|
| `fodder.perPlayer` (was `crowd.threat.attackersPerPlayer`) | 4 | **2** | 12 fodder stand in reach of a still player, so four lunge places are never empty: 4.9 hits/s, 39 damage/s, down at 5.5 s. With two: 2.5 hits/s, 20 damage/s, down at 8.7 s. Ruling 16. |
| `armoured.attacks[0].launch` | 6 | **3** | A launch of 6 lifts his feet over the 4-stud fence and keeps him in the air 0.49 s, longer than `knockIframes` (0.40 s). At 3 he is up 0.35 s and stays under the fence. |
| `fodder.attacks[0].windup` | 0.5 | **0.6** | At 0.5 a phone player who reacts in 0.35 s has 0.01 s to step out. At 0.6 he has 0.11 s, and a 0.25 s reaction has 0.21 s. Ruling 19. |
| `fodder.attacks[0]`, the rest (reach 4.5, recover 1.5, damage 8, range 5, width 3, height 5) | | same | 8 is 6% of health: 17 hits to go down. The tell is in the table below. |
| `armoured.attacks[0]`, the rest (reach 6, windup 0.8, recover 1.2, damage 30, knockback 30, range 7.5, arc 120°, height 6) | | same | 30 is 23% of health. |
| `player.knockFriction` | 75 | same | The slide I want is 6 studs in 0.40 s. See "The knock" below. |
| `crowd.heavyHit` | 40 | same | It equals fodder's HP: a heavy hit is one that one-shots a fodder. The nearest damage values are 41.6 above and 38.4 below. |
| `threat.spawnGrace`, `spawnClear`, `strikeSeconds` | 1.0, 12, 0.2 | same | A fresh enemy cannot land a hit for 1.6 s. 12 is over the longest lunge or arc reach (6) and under the pad's distance to the nearest slot, so sets refill. That distance is 24 studs in wave 1's sets and 17 in `fight`. |
| `player.downSeconds`, `getUpIframes` | 2, 1.5 | same | Seeing, reacting and walking out of a pack of 30 takes 0.69 s (1.0 s for wave 2's 100). |
| `player.regenDelay`, `regenPerSecond` | 4, 10 | same | One fodder alone attacks every 2.3 s and one elite every 2.2 s, so the delay never runs out in reach. An empty bar is full 17 s after the last hit. |
| `player.knockIframes` | 0.4 | same | Covers the 0.35 s in the air and the 0.40 s slide. |
| `dummySets.fodderRush`, `elites` | 30 at (0, 60); 3 at (0, 60) | same | First lunge lands at 2.2 s, first arc at 3.5 s. |

`threat.maxShots` belongs to wave 2 and is in its table.

**Why the cap is 2, and why the recover does not help.** A lunge place is held for windup +
strike, 0.8 s, so a swarm lands at most cap ÷ 0.8 lunges a second: 5.0 at cap 4, 2.5 at cap 2. A
fodder's own cycle is 2.3 s, so the 1.5 s recover only spaces attacks out when fewer than about
6 (cap 2) or 12 (cap 4) fodder stand in reach. In a rush there are 12, and a recovering fodder is
replaced at once. For the 6–12 s band the swarm may deal 13 to 34 damage a second. Cap 4 deals 39
and goes down at 5.5 s. Cap 3 deals 30 and goes down at 6.4 s, on the edge. Cap 2 deals 20 and
sits in the middle.

**The knock.** `knockback` 30 against `player.knockFriction` 75 is a slide of 30² ÷ (2 × 75) =
6.0 studs that lasts 30 ÷ 75 = 0.40 s.
- It ends exactly when `knockIframes` do. Any lower friction is a slide that outlasts them
  (60 gives 7.5 studs in 0.50 s).
- 6 studs is the arc's `reach`. Wherever in the arc he stood, he ends outside the reach of the
  elite that hit him, and it must step before it can wind up again.
- It carries him out of a second elite's arc from up to 102° round him, so elites that came from
  one side cannot chain. More friction loses that: 90 gives 5.0 studs and 94°, 120 gives 3.8
  studs and 82°.
- It cannot throw him out. The launch keeps his feet under the fence, and from the pad the
  fourth knock is the first one the back fence cuts short.
- Clearing a flanking elite too needs 9.6 studs. That is knockback 40, friction 80 and
  `knockIframes` 0.5 together. I have not taken it: it is three values for a case wave 1's set
  cannot produce.

**Heavy hits** (`heavyHit` 40, before armour). They cancel the elite's windup now and break the
plate in wave 2.
- Every hit: Warhammer, Greataxe A, Spear A, Shotgun, Rifle, Launcher, Chain Gun A, Splitbow B,
  and a full-charge Longbow.
- Finisher only: Broadsword (43.2), Spinblade (41.6), Greataxe B, Spear B.
- Never, even on a crit: SMG, Beam. Chain Gun B and Splitbow A only on a head.

## The tells against the player's moves

| | Fodder lunge | Elite arc |
|---|---|---|
| Damage | 8 (6%) | 30 (23%) |
| Tell | 0.60 s | 0.80 s |
| Walking out needs | 0.39 s: 0.07 step + 0.25 reaction + 1.5 studs at 20/s | 0.49 s: the same + 3.5 studs |
| Margin left | 0.21 s (0.11 s for a 0.35 s thumb) | 0.31 s (0.21 s) |
| Jumping | clear from 0.06 s to 0.79 s after take-off | clear from 0.08 s to 0.78 s |
| Dashing | 0.30 s to press in (i-frames 0.25 + lag 0.05); the 20 studs also leave the shape | the same |
| Walking on without reacting | covers 12 studs; the longest way out is 6.7 | covers 16; the longest way out is 11.7 |
| Enemy speed against the walk (20) | 12 | 9 |

- **A walker is never hit.** Walking on through the tell leaves either shape, whichever way he
  walks, and both enemies are slower than the walk.
- **The dash is an escape more than a shield.** The server accepts a dash every 0.64 s (0.80 s
  from an honest client), so spam is invulnerable 39% (31%) of the time. A player who could not
  leave would still take six lunges in ten. What saves him is the 20 studs: fodder need 1.3 s to
  close them, longer than the cooldown.

## Results (tier 1, Broadsword, mean of three seeds, per 60 s)

| Set | Player | First hit | Down at | Downs | Hits | Dodged | Missed | Worst burst | Kills |
|---|---|---|---|---|---|---|---|---|---|
| fodderRush | stands still | 2.2 s | **8.7 s** (8.6–8.8) | 5.0 | 96 | 20 | 0 | 16 | 0 |
| fodderRush | walks away | never | never | 0 | 0 | 0 | 0 | 0 | 0 |
| fodderRush | stands to half health, then walks | 2.2 s | never | 0 | 10 | 0 | 2 | 16 | 0 |
| fodderRush | fights, dashes when threatened | never | never | 0 | 0 | 0 | 0 | 0 | 338 |
| fodderRush | stands to half health, then fights | 2.2 s | never | 0 | 9 | 0 | 2 | 16 | 290 |
| elites | stands still | 3.5 s | 9.8 s | 5.0 | 28 | 5 | 0 | 30 | 0 |
| elites | walks away | never | never | 0 | 0 | 0 | 0 | 0 | 0 |
| elites | stands to half health, then walks | 3.5 s | never | 0 | 3 | 0 | 0 | 30 | 0 |
| elites | fights, dashes when threatened | never | never | 0 | 0 | 0 | 0 | 0 | 18 |
| elites | stands to half health, then fights | 3.5 s | never | 0 | 3 | 0 | 4 | 30 | 12 |

"Dodged" is a hit the i-frames of a dash, a knock or the get-up voided. "Missed" is an attack
whose shape no longer held him. "Worst burst" is the most damage inside one dash i-frame window
(0.25 s). The elites carry wave 2's plate in these rows.

- **Standing still:** 2.5 lunges land a second (20 damage/s) and none misses. No lull is longer
  than 0.9 s, so regen never starts. He is down five times a minute.
- **Walking away:** nobody comes nearer than 13 studs. Caught at half health, he walks out with
  at most one more hit, a lunge that was already winding up, and is full again about 12 s later.
- **Fighting:** nothing lands, and he never needs the dash. The set feeds him 5.6 fodder a second
  and he kills them all. In the busy crowd of the abilities table the Broadsword kills 6.6/s and
  the Longbow 4.8/s, so a bow alone falls behind a rush and has to kite.
- **Elites:** they take turns, one arc at a time, a second apart at the least. Every arc lands on
  a still player: 0.6 hits/s, 17 damage/s, still less than the fodder's 20. Before the turn rule
  three swung together, one arc landed and ruling 18 voided the others (0.5 hits/s, down at
  11.7 s).

## Bands (`--check`)

| Band | Value | Now |
|---|---|---|
| One hit, and one volley of the cap | ≤ 25% of health | 23% (arc), 12% (two lunges) |
| Still in `fodderRush`: down at | 6–12 s, every seed | 8.7 s (8.6–8.8) |
| The same with every lunge place taken the moment it frees | ≥ 6 s | 8.6 s |
| Lunges landing on a still, swarmed player | 1.5–3.5 per second | 2.5 |
| Worst burst inside one dash window, any still row | ≤ 25% | 12% (fodder), 23% (elites) |
| Longest lull in the rush; one enemy's own cycle | < `regenDelay` (4 s) | 0.9 s; 2.3 s and 2.2 s |
| A tell beyond step + reaction + the walk out | ≥ 0.05 s | 0.21 s (lunge), 0.31 s (arc) |
| A jump clears the shape before the impact | yes | yes |
| An attack reaches past where it starts; its enemy is slower than the walk | yes | yes |
| Telegraphed hit: walking on covers the longest way out | yes | 16 ≥ 11.7 |
| Launch under the fence | yes | 3 < 4 |
| Flight and slide inside `knockIframes` | ≤ 0.40 s | 0.35 s; 0.40 s |
| The knock clears a second arc from this far round him | ≥ 90° | 102° |
| Dash spam invulnerable | 20–50% of the time | 39% |
| Dash: press window; distance against the longest way out | ≥ 0.2 s; ≥ | 0.30 s; 20 ≥ 11.7 |
| `getUpIframes` against walking out of the biggest pack | ≥ | 1.5 ≥ 1.00 s (`fight`'s 100 fodder) |
| `spawnClear` between the longest lunge or arc reach and the pad's distance to a slot | yes | 6 < 12 < 17 |
| `spawnGrace` at least a step + the reaction | ≥ 0.32 s | 1.0 s |
| Walks away in `fodderRush` and `elites`: damage; nearest enemy | 0; beyond the longest reach | 0; 13 studs |
| Caught at half health, then walks: more hits; downs; full again | ≤ the cap; 0; yes | 1; 0; yes |
| Telegraphed hits on any player who acts | 0 | 0 |

Each band was proved by changing a value until it failed. With the lead's first values (cap 4,
launch 6, windup 0.5) five fail: the fence, the flight, the time down (5.2 s), its floor (4.9 s)
and the rhythm (5.3 hits/s).

## What scales with weapon tier

In the range nothing does: weapon numbers are tier-1 values and ruling 17 pins health at 130.
P5 returns to the profile's own health, and there enemy damage, regen and `heavyHit` are still
flat (ruling 20). This is what the same enemies would do to each tier's bar:

| Gear | Health | Arc | Still in `fodderRush`: down at | Still in `elites`: down at | Empty bar full in |
|---|---|---|---|---|---|
| starter | 100 | 30% | 7.1 s | 8.7 s | 14 s |
| tier 1 | 130 | 23% | 8.7 s | 9.8 s | 17 s |
| tier 2 | 155 | 19% | 9.6 s | 11.7 s | 20 s |
| tier 3 | 180 | 17% | 11.1 s | 11.7 s | 22 s |
| tier 4 | 230 | 13% | 13.6 s | 14.1 s | 27 s |
| tier 6 | 380 | 8% | 21 s | 23 s | 42 s |
| tier 12 | 2 250 | 1% | 116 s | 96 s | 229 s |

The `fodderRush` band would hold from starter gear to tier 3 and nowhere above, and on starter
gear the arc is over 25%. For P5:
- **Enemy damage needs a scale per mission**, close to health's: ×1.8 at tier 4, ×3.9 at tier 7,
  ×9.6 at tier 10, ×17 at tier 12. Weapon damage grows ×267 over the same ladder, so enemy HP and
  enemy damage need two different scales.
- **Regen should be a share of the bar.** A flat 10/s is 7.7% a second at tier 1 and 0.4% at
  tier 12.
- **`heavyHit` must follow enemy HP.** At ×2.2 (tier 3) every Broadsword swing is over 40, and
  the plate would stop nothing.

## Where the server or the client can move these numbers

The simulator's reading comes first in each line.

- **Hits decided together.** Ruling 18, as written above. The server follows it since the wave 1
  review. Without it, elites that wind up in the same step land every arc (see the first flag).
- **When a lunge place frees.** At the end of `attack`, as ruling 8 says and `CrowdBrain` does. If
  a lunger held its place through `recover`, a still player would last about 20 s and the band
  would fail.
- **What the cap counts.** Each kind has its own count since the wave 2 review (`perPlayer`), so
  fodder do not wait for elites nor elites for fodder. Before it only lunges were counted.
- **Where a rusher stops.** At `reach`, measured on the flat since ruling 21 (it was measured in
  space, and a hopping player voided five lunges in six). Any rule that leaves 6 or more fodder
  in reach keeps both places busy and changes nothing.
- **The shapes.** The lunge is a capsule whose tip is `range` from the body centre, and the player
  is a point, as `VitalsService.inPlan` has it. If the player gets a body radius, every way out
  grows by it: 1 stud takes 0.05 s off each tell's margin.
- **Who takes a free place.** The lowest id waiting in reach. Any other order lands the same
  number of lunges from other sides.
- **Lag.** The sim's player has no ping. Real ping only widens the dash's press window.

## Flags for the owner

- **Ruled (18): hits decided together do not stack through a knock.** When a hit that knocks
  back lands, every other hit on that player still waiting for its decision at that moment, or
  falling inside the `player.knockIframes` it opens, is voided and sent as `dodged`. The
  simulator does exactly this, and its "worst burst" band (23%) depends on it. What I found in
  `VitalsService.settle` before the ruling: the knock i-frames a first arc grants start at
  `os.clock()` in that pass, later than the `decideAt` of the entries still to be judged in it,
  so they were not covered. Enemies that wind up in one crowd step share one impact time, so two
  or three elites dealt 60 or 90 at once (46% or 69% of the bar), most of all after a get-up.
  Since the turn rule elites no longer swing together, and the ruling matters for unlike kinds:
  a charge and an arc, or a lob and a charge.
- **Ruled (16): the cap is 2, not the 4 the owner was first told.** The reason is in "Why the cap
  is 2" above. The key is `fodder.perPlayer` now.
- **Ruled (17): the bar in the range is pinned at 130.** It used to be the profile's: 100 on a
  fresh Studio profile, where the arc is 30%, and 2 250 at tier 12, where nothing here is felt.
  The tier table above is now P5's problem (ruling 20).
- **Ruled (19): the lunge's windup is 0.6 s.** It was my phone flag. A 0.35 s thumb now has
  0.11 s to step out, and every band holds (down at 8.7 s, 2.5 hits/s).
- **Nothing in wave 1 hurts a player who keeps swinging.** All five melee families take no hit
  in 60 s in either set, even when they start surrounded at half health.
  - Fodder: the sword reaches 12.8 studs and the lunge starts at 4.5. A swing hits the 10 nearest,
    throws each about 8 studs and staggers it. Swings come every 0.4 s and the tell lasts 0.6 s,
    so any lunge that starts is cancelled (ruling 9).
  - Elite: the Broadsword's finisher (43.2) is a heavy hit and cancels the arc. Its shove also
    carries the elite out of its own range, because only 1.5 studs separate `reach` and `range`.
  - So in the wave 1 playtest the bar moves only while Ben is not attacking. To see the lunge,
    "dodged" and the down, he has to stand in the rush with his hands off.
  - The levers that would change it are rulings, not values: the fodder's `interrupt`, or a longer
    reach. Wave 2's shooters, lobber and brute are the roles that reach a player who is busy.
  - The sim's fighter turns to the nearest enemy at once. A real player, and a phone's
    auto-swing, will take some hits from behind.
  - **Wave 2:** `fight`, `brutes` and `shooters` now hurt him. `elites` still does not, plate or
    no plate. See "Wave 2: flags for the owner".
- **The pad is 20 studs from the back fence.** Elites come up the lane and knock a still player
  toward it. After three knocks the fence stops the slide, and arcs then land a second apart,
  the length of an elite's turn. With the lead's launch of 6 a knock near the fence could have
  carried him over it.
- **The elite is soft until it has a plate.** It never hits a walker, and a still player loses
  less to three elites than to the fodder. **Wave 2:** it has the plate now and is soft in the
  same two ways. The plate makes it last longer, not hit more.
- **Two lungers at a time may look thin** with 12 fodder standing round the player. The numbers
  leave little room: cap 3 goes down at 6.4 s and lands 3.8 hits a second, and cap 3 with damage
  6 holds the time (7.9 s) but lands 3.7 hits a second of 5% each.
- **Kiting heals.** Fodder cannot stop a walker from regenerating a full bar in 17 s. Wave 2's
  shooters are what interrupts that. **Wave 2:** they interrupt a player who stays in the fight,
  not one who leaves it. See the wave 2 flags.
- **The stairs are safe ground.** A player on the 8-stud step is above both shapes (heights 5 and
  6), and the crowd stays on the floor (known limit 15). Wave 2's shooters and lobber reach it.
  **Wave 2:** since the wave 2 review a shot, a line and a lob reach him there (the lob lands on
  the surface he stands on). The lunge, the arc and the lane do not.

## Wave 2 — roles

The slinger, the marksman, the lobber, the brute and the elite's plate (contract:
`docs/INTERFACES.md` "Wave 2 — roles" and its review round). Everything is still measured at
tier-1 health, 130.

Targets, from the contract and the lead's brief:
- no single hit takes more than 25% of health;
- a player standing still in `fight` goes down in 4 to 8 s;
- a player who reacts to every tell takes damage from fodder only;
- a player who hops on the spot, and one who strafes one way, are both hit by slingers often
  enough to matter, also at 100 and 150 ms of ping;
- each of the three shooters has its own job and none is strictly better;
- the brute's lane can be sidestepped, jumped and dashed inside its windup, and its recover is a
  real opening;
- the lob's circle can be walked out of, from its centre, during the flight;
- every melee family breaks the plate within two combos, an SMG then kills the elite in at most
  2 s, and the reel covers a slot switch plus the first second of that kill;
- no instant takes most of the bar from a still player in `fight` (the review round's target).

## Wave 2: what the simulator gained

`py tools/sim_range.py` prints four more tables (ROLES, TURNS, SHOOTERS ALONE, PLATE) and more
rows in THREAT. The new parts follow the server as built, the review round included:

- **keepAway:** the band is the flat distance to the target. The shooter walks in to `bandMax`
  or its `reach`, whichever is shorter, backs straight off to `bandMin`, and stays in the arena.
  It moves while it approaches and recovers, never in windup or attack.
- **turns:** at most `perPlayer` enemies of one kind are in windup or attack against one player.
  A place is held from the windup's start to the end of `attack` (a brute's through its charge).
  A shot or a lob in the air holds none, and neither does `recover`. The others wait in reach,
  or in their band, and take a freed place.
- **shot:** aimed when the windup ends, from the body centre, at `lead` of the way to where the
  target will be after the flight plus his lag, which is when the hit is judged. The target's
  motion is its displacement over the last step, capped at the fastest legal move. A target that
  is rising or falling is led down its fall, as far as the surface it last stood on. The flight
  time is refined six times. Each step the stretch the shot flew `lag` ago is tested against the
  root as a point, within `radius`, in 3D.
- **line:** the facing follows the target until `lockSeconds` before the hit, then freezes,
  snapped to the snapshot's 1/256 of a turn. It is a rectangle with no height rule.
- **lob:** the circle is centred on the target's place when the windup ends, on the surface
  under him. It lands `seconds` later on anyone inside it whose feet are within `height` of
  that surface.
- **lane:** the facing locks when the windup starts. The charge runs `range`, or to the arena's
  edge if that is nearer. It hits a root within half its `width` of the body's centre, feet
  under `height`. Nothing but a killing blow stops it.
- **the plate:** a hit under `heavyHit` does nothing at all. A heavy hit takes its full amount
  off the plate and the excess is lost. The hit that empties it cancels the elite's windup and
  starts the reel.
- **`maxShots`:** shots in the air plus shot windups under way, on top of the turns.

New players:
- **Hops on the spot:** holds jump. He is on the floor 0.1 s between jumps, which is an
  assumption.
- **Strafes one way:** walks one way and turns back after 22, 30 and 38 studs in turn, so his
  turns never fall in step with a shooter's cycle.
- **Reacts to every tell:** 0.25 s plus one crowd step after a tell shows, he takes the cheapest
  move that avoids everything he can see. The moves are: stand, a step of 0.1 to 1.0 s in one of
  twelve directions, a jump, a jump with a step, and a dash when it is off cooldown. He judges
  each move the way the server will judge the hit, and keeps 0.4 studs spare.
- **Swings, never dodges** and **swings and reacts**, for the question wave 1 left open.

Two more measurements:
- One shooter of each kind, alone, for 300 s against a player who cannot go down. This gives a
  clean landing rate per kind. The slinger is also watched at 100 and 150 ms of ping.
- The plate matrix. It is arithmetic on the weapon numbers: normal attacks, body hits, none
  missing.

Limits:
- Cover and the stairs are not modelled.
- The player has no ping, so the lag is 0.05 s, except in the slinger's ping rows.
- `fight` runs 30 s, the other sets 60 s.
- The swinging player does not chase. In `shooters` nothing comes into his reach, so he is the
  still player there.
- **`fight` is sensitive to the last bit of the arithmetic.** A hundred bodies shove each other,
  and the rows of that set move by a few percent between Python builds. `py tools/sim_range.py`
  runs on Python 3.12, which the launcher picks from the file's first line. A script with no
  such line runs on 3.14. The two give 39.7 and 40.7 hits on the still player from the same
  seeds. Every band holds on both and on ten seeds. The numbers here are the tool's own.

## Wave 2: values

Eight values differ from the lead's starting set, and the three sets were laid out again.
`lead`, `radius` and `lockSeconds` were set once more after the review round, and the list
shows where they ended.

| Key | Lead | Now | Why |
|---|---|---|---|
| `slinger.attacks[0].lead` | 0.7 | **1.0** | At 0.7 no shot ever hits a strafer. The aim is led over the flight plus the player's lag, in six passes, so 1.0 is where he will be: a strafer is hit by every shot at 0, 100 and 150 ms of ping. The value has room on both sides: 0.9 lands 90% and 1.2 lands 34%. |
| `slinger.attacks[0].radius` | 1.0 | **1.5** | The strafer is hit at any radius from 1.0 up. The hopper sets it, because he is only in reach near the floor. At 0, 100 and 150 ms a radius of 1.0 lands 25%, 22% and 15% of shots on him; 1.25 lands 31%, 25% and 16%; 1.5 lands 33%, 28% and 22%. 1.5 is the smallest that keeps a fifth at 150 ms. Stepping out needs 1.5 studs: 0.39 s of the 0.64 s the shortest flight gives. |
| `slinger.hp` | 50 | **45** | The Broadsword's first two swings deal 48. They now kill a slinger as they kill a marksman (45). No band reads this value. |
| `marksman.attacks[0].lockSeconds` | 0.25 | **0.55** | After the lock a player needs 0.36 s to see it, react and step 0.8 studs. A lock of 0.25 s gave him 0.30 s. 0.55 s gives 0.60 s, which leaves a 0.35 s phone thumb 0.14 s (ruled in the review round; I had 0.45). The line still follows him for 0.45 s first. |
| `marksman.attacks[0].recover` | 3.0 | **4.0** | At 3.0 one marksman deals 5.2 damage a second to a still player and to a hopper alike. That beats the lobber (4.8) wherever the lobber lands, so the lobber led nowhere. At 4.0 it deals 4.3. |
| `brute.attacks[0].knockback` | 40 | **30** | 40 is a slide of 10.7 studs that lasts 0.53 s, longer than `knockIframes` (0.40 s). 30 is the elite's knock: 6.0 studs in 0.40 s. |
| `armoured.plate` | 90 | **80** | Two Broadsword finishers deal 86.4 and two Spinblade finishers 83.2. At 90 both families need a third combo. The plate must also stay above the biggest single body hit (Greataxe A's finisher, 75.6), so it can be 76 to 83. |
| `crowd.plateBreakSeconds` | 1.0 | **1.5** | A reaction (0.25 s) plus the first second of the SMG's kill is 1.25 s. 1.5 leaves a quarter second for the switch itself. Above 2.0 the elite would rarely fight again. |
| `fodder.perPlayer` | 2 | same | Wave 1's cap under its new name. Two lunges are 16, 12% of health. |
| `armoured`, `slinger`, `marksman`, `lobber`, `brute` `.perPlayer` | 1 | same | One turn of a kind then costs what one hit may: 30, 12, 22, 18 and 28. Two marksmen at once would be 44 (34%), and three slingers 36 (28%). See "Turns" below. |
| `slinger`, the rest (band 18–30, reach 32, speed 11, windup 0.6, recover 2.2, damage 12, shot speed 28, seconds 2.5) | | same | 12 is 9% of health. A slower shot is easier to step out of and, under this aim rule, hits a hopper more often. |
| `marksman`, the rest (band 28–45, reach 48, speed 10, hp 45, windup 1.0, damage 22, range 60, width 1.6) | | same | 22 is 17% of health. Half the width (0.8) is more than the 0.59 studs the snapped facing can be off at its reach. |
| `lobber`, all of it (band 22–40, reach 42, speed 9, hp 60, windup 0.5, recover 3.0, damage 18, knockback 14, launch 3, radius 5, seconds 1.4, height 4) | | same | 18 is 14% of health. Walking out from the centre takes 0.57 s of the 1.4 s flight. The knock is 1.3 studs. |
| `brute`, the rest (reach 22, speed 10, hp 320, windup 0.8, recover 1.5, damage 28, launch 3, range 30, width 5, charge speed 55, height 5) | | same | 28 is 22% of health. The tell and the opening are in the tables below. |
| `threat.maxShots` | 24 | same | At most 3 shots are in the air in `fight` and 2 in `shooters`, so that cap never silences a slinger for one player. |

**The sets.** Counts, spacing and respawn times are the lead's. The positions are new.

| Set | Lead | Now | Why |
|---|---|---|---|
| `shooters` | slingers (−14, 60), marksmen (0, 75), lobbers (14, 60) | slingers (−10, 70), marksmen (0, 50), lobbers (12, 62) | Each kind now starts inside its own band, measured from the pad at (0, 90): 22, 40 and 31 studs. The lead's marksmen stood 15 studs from the pad, under their `bandMin`, and began by backing off. |
| `brutes` | one row of three at (0, 60) | three singles at (0, 62), (−18, 52), (18, 44) | They are 28, 42 and 49 studs from the pad and arrive one after another. A still player is down at 8.3 s. |
| `fight` | slingers (−24, 70), marksmen (0, 85), lobbers (24, 70), brutes (−30, 50), elites (30, 50) | slingers (−30, 55), marksmen (0, 2), lobbers (26, 34), brutes (−56, 46), elites (−10, 26) | The roles reach a player on the pad in turn: fodder at 1.7 s, slingers at about 3 s, lobbers at 4.3 s, marksmen at 5.3 s, brutes at 5.7 s, elites after 7 s. The lead's layout had every role within 35 studs of the pad, and a still player was down at 2.8 s. His marksmen also stood 5 studs from the pad, inside `spawnClear`, so that slot never refilled. |

In `fight` the marksmen stand at the far end of the lane, the lobbers beside the cover on the
right flank, the slingers on the open left, and the brutes far left with a full runway.

## Wave 2: turns

Enemies of one kind take turns (`perPlayer`, ruled in the review round). A place is held from
the windup's start to the end of the attack.

| Kind | Places | A place is held | Its own cycle | One turn costs | In `fight` | Attacks a second there | Without turns |
|---|---|---|---|---|---|---|---|
| Fodder | 2 | 0.80 s | 2.30 s | 16 (12%) | 100 | 2.50 | 43.5 |
| Elite | 1 | 1.00 s | 2.20 s | 30 (23%) | 3 | 1.00 | 1.36 |
| Slinger | 1 | 0.80 s | 3.00 s | 12 (9%) | 3 | 1.00 | 1.00 |
| Marksman | 1 | 1.20 s | 5.20 s | 22 (17%) | 3 | 0.58 | 0.58 |
| Lobber | 1 | 0.70 s | 3.70 s | 18 (14%) | 2 | 0.54 | 0.54 |
| Brute | 1 | 1.35 s | 2.85 s | 28 (22%) | 3 | 0.74 | 1.05 |

- **The three shooters lose nothing.** Three turns of a slinger or a marksman fit inside one of
  their own cycles. They now fire one after another and no longer as one.
- **Brutes and elites attack less often and land more.** Three brutes share one place of 1.35 s
  and three elites one of 1.0 s. But ruling 18 used to void most of what they threw together.
  A still player in `brutes` now takes 30 charges a minute where he took 14, and in `elites` 28
  arcs where he took 24.
- **The worst instant.** One turn of every kind that does not knock (two lunges, a shot, a
  line: 50), plus the hardest knock (the arc's 30), is 80, 62% of the bar. Ruling 18 lets only
  one knock land. That is the most one instant can cost in `fight` by the rules alone. It needs
  four kinds inside a quarter second with the knock last, and it has not happened on thirty
  seeds.

The worst quarter second a still player takes, before the rule and now:

| Set | Before | Now | What it is now |
|---|---|---|---|
| `fight` | 102 (78%), and 112 (86%) on ten seeds | **66 (51%)**, and 68 (52%) at most on thirty seeds | two lunges, a line and a charge |
| `shooters` | 46 (35%) | 40 (31%) | a line and a lob |
| `brutes` | 28 (22%) | 28 (22%) | one charge |
| `elites` | 30 (23%) | 30 (23%) | one arc |

"Before" is my last report: three lines and three shots in one tenth of a second. With today's
values and the rule switched off, `fight` reads 82 (63%).

**The ceiling.** Two bands, because one number cannot do both jobs.
- **Measured: the still player's worst quarter second in `fight` is at most 55% of the bar.**
  The target is that no instant takes most of the bar. What meets in one instant is one turn of
  three kinds: the fodder pair (16), a line (22) and a knock (28 or 30). That is 66 to 68, half
  the bar. A ceiling of exactly 50% would hang on one point of damage, so the band has the
  weight of one lunge to spare. It fails the behaviour before the rule.
- **By the rules: the most one instant can cost in any set is at most two thirds of the bar.**
  More than a third is then always left, so one more hit of any size the 25% rule allows does
  not finish a bar that was full. `fight` is at 62%. This is the band that pins each
  `perPlayer`: two marksmen make it 78%, three slingers 80%, three fodder 68%.

## Wave 2: the roles

| Kind | Job | Threat | Counter |
|---|---|---|---|
| Slinger | Punishes blind movement. Its shot leads a walker. | 12 (9%) every 3.0 s. It lands on every shot at a still player or a strafer, and on 33% at a hopper. | Step 1.5 studs aside once it has thrown, or dash. Two sword swings kill it. A wall stops the shot. |
| Marksman | Punishes standing and hopping. Its line has no height rule. | 22 (17%) every 5.2 s, from 28 to 45 studs. It always lands on a still player and on a hopper. | Step 0.8 studs off the line after it locks, or keep walking: a strafer takes 1% of them. A jump does nothing. A wall stops it. |
| Lobber | Hits whoever stays put, also behind cover. It is the hardest hitter on a still player. | 18 (14%) and a short knock every 3.7 s, in a circle 5 studs in radius. | Walk out of the circle. Any walker does: a strafer takes 8%, a hopper 22%. |
| Brute | Breaks the player's position, and soaks damage (320 HP). | 28 (22%) and a 6-stud knock. The charge covers 30 studs in 0.55 s, 5 wide. One alone attacks every 2.85 s. | Sidestep 2.5 studs, jump, or dash through. It then stands open for 1.5 s. A heavy hit cancels its windup, and nothing stops the charge. |
| Elite | Holds the front. Light hits do nothing to it until the plate breaks. | 30 (23%) and a knock every 2.2 s, in reach 6. Plate 80 over 160 HP. | Two heavy hits break the plate, then it reels 1.5 s. Walk out of the arc. |

The tells against the player's moves, as wave 1's table has them for the lunge and the arc:

| | Slinger shot | Marksman line | Lobber lob | Brute lane |
|---|---|---|---|---|
| What the player answers | the flight: 0.64 s from the near edge of its band, 1.07 s from the far edge | the lock: 0.60 s | the flight: 1.40 s | the windup: 0.80 s |
| Stepping out needs | 0.39 s (1.5 studs) | 0.36 s (0.8 studs) | 0.57 s (5 studs, from the centre) | 0.44 s (2.5 studs) |
| Margin left | 0.25 s (0.15 s for a 0.35 s thumb) | 0.24 s (0.14 s) | 0.83 s (0.73 s) | 0.36 s (0.26 s) |
| Jumping | clears it if he is over 1.5 studs up when it arrives; the aim follows a fall, not a later jump | does nothing | clear from 0.05 s to 0.81 s after take-off | clear from 0.06 s to 0.79 s, longer than the whole charge |
| Dashing | 0.25 s of i-frames | the same | the same | the lane passes in 0.09 s |
| Its speed against the walk (20) | 11 | 10 | 9 | 10 |
| Knock | none | none | 1.3 studs in 0.19 s | 6.0 studs in 0.40 s |

- **The brute's opening.** A reaction and one full Broadsword combo take 1.05 s. The recover is
  1.5 s.
- **The lob and the lane launch him 3 studs,** under the 4-stud fence, for 0.35 s in the air.
  Both slides end inside `knockIframes`.
- **The line shows for 0.45 s before it locks.** That is more than a step and a reaction
  (0.32 s), so the player has seen it before he must move.

**One shooter of each kind, alone** (300 s, three seeds, the player cannot go down):

| Kind | Stands still | Hops on the spot | Strafes one way |
|---|---|---|---|
| Slinger | 100% land, 4.0 damage/s | 33%, 1.3 | 100%, **4.0** |
| Marksman | 100%, 4.3 | 100%, **4.3** | 1%, 0.0 |
| Lobber | 100%, **4.8** | 22%, 1.1 | 8%, 0.4 |

Each shooter is the hardest hitter against one of the three players, so none is strictly
better. Counted for `fight`'s three slingers, a hopper is hit every 3.1 s and a strafer every
1.0 s.

**"Often enough to matter".** I set two conditions for the slinger against blind movement.
- It lands at least 20% of its shots on a hopper and 50% on a strafer, at 0, 100 and 150 ms of
  ping.
- At that rate `fight`'s slingers alone hit him more often than his regen can answer. Regen
  needs `regenDelay` plus the time to heal one shot: 4 + 12 ÷ 10 = 5.2 s between hits.

| The slinger alone, by the player's ping | 0 ms | 100 ms | 150 ms |
|---|---|---|---|
| Shots landing on a hopper | 33% | 28% | 22% |
| Shots landing on a strafer | 100% | 100% | 100% |

The hopper's 33% is a long-run rate, which is why the shooters are watched for 300 s. The hits
come in runs, because the slinger's 3.0 s cycle drifts slowly against the 0.96 s hop: over 60 s
the same slinger lands 25%, and over 90 s 36%. Inside a set it lands far less, 6% in `shooters`
and 5% in `fight`, because every get-up starts the crowd again in step with his first hop. A
person does not hop that evenly, so I take the long-run rate as the fair one. In both sets it
is the marksmen who punish the hopper.

## Wave 2: the plate

Plate 80 over 160 HP. A hit of 40 or more is heavy. The elite reels 1.5 s when the plate breaks.
Times run from the weapon's first hit.

| Weapon | Breaks the plate in | Then kills in | Total | No plate |
|---|---|---|---|---|
| Broadsword A | 6 hits, 2.00 s | 2.40 s | 4.40 s | 2.00 s |
| Warhammer A | 2 hits, 0.77 s | 2.31 s | 3.08 s | 1.54 s |
| Spinblade A | 6 hits, 1.47 s | 2.06 s | 3.53 s | 1.76 s |
| Greataxe A | 2 hits, 0.77 s | 2.31 s | 3.08 s | 1.54 s |
| Greataxe B | 6 hits, 2.63 s | 2.11 s | 4.74 s | 1.58 s |
| Spear A | 2 hits, 0.59 s | 2.35 s | 2.94 s | 1.76 s |
| Spear B | 6 hits, 2.08 s | 2.08 s | 4.17 s | 1.67 s |
| Longbow A | 2 hits, 1.05 s | 4.20 s | 5.25 s | 3.15 s |
| Longbow B | 2 hits, 0.55 s | 2.20 s | 2.75 s | 1.65 s |
| Splitbow A | never (on the head: 0.83 s) | | | 5.00 s |
| Splitbow B | 2 hits, 1.00 s | 4.00 s | 5.00 s | 3.00 s |
| Shotgun A | 2 hits, 0.91 s | 2.73 s | 3.64 s | 1.82 s |
| Piercing Rifle A | 2 hits, 0.42 s | 1.67 s | 2.08 s | 1.25 s |
| Launcher A | 2 hits, 1.33 s | 4.00 s | 5.33 s | 2.67 s |
| SMG A | never | | | 1.42 s |
| SMG B | never | | | 1.29 s |
| Beam A | never | | | 3.10 s |
| Beam B | never | | | 1.30 s |
| Chain Gun A | 2 hits, 0.83 s | 2.50 s | 3.33 s | 1.67 s |
| Chain Gun B | never (on the head: 0.42 s) | | | 2.08 s |
| Ground slam | 2 slams, 1.80 s | | | |

- **Every melee family breaks it within two combos.** The Warhammer, Greataxe A and Spear A
  break it in two swings. The Broadsword, Spinblade, Greataxe B and Spear B have one heavy hit
  per combo, the finisher, and need exactly two combos.
- **These cannot break it alone:** Splitbow A, SMG A and B, Beam A and B, Chain Gun B. No body
  hit of theirs reaches 40. Splitbow A and Chain Gun B break it with head shots.
- **What such a loadout does.** Break it with the melee slot, or with two ground slams (45
  each), then switch. Every loadout has a melee slot and the slam, so none is stuck.
- **After the break an SMG kills the elite in 1.42 s (A) or 1.29 s (B).** With a 0.25 s reaction
  the kill ends 0.17 s after the reel for A and 0.04 s after it for B. The elite's windup is
  0.8 s, so it gets no arc off.
- **No weapon that breaks the plate also kills inside the reel.** The fastest is the Piercing
  Rifle at 1.67 s. So a player who does not switch meets the elite again.
- **The plate costs a Broadsword 2.4 s more per elite** (4.40 s against 2.00 s), and a break
  followed by an SMG switch about 3.7 s in all.

## Wave 2: results (tier 1, Broadsword, mean of three seeds)

Per 60 s. `fight` is per 30 s.

| Set | Player | First hit | Down at | Downs | Damage | Hits | Dodged | Missed | Worst burst | Kills |
|---|---|---|---|---|---|---|---|---|---|---|
| fodderRush | hops on the spot | 3.6 s | 28.9 s | 1.3 | 275 | 34 | 0 | 103 | 16 | 0 |
| elites | reacts to every tell | never | never | 0 | 0 | 0 | 0 | 51 | 0 | 0 |
| elites | swings, never dodges | never | never | 0 | 0 | 0 | 0 | 0 | 0 | 18 |
| shooters | stands still | 2.1 s | 7.3 s | 7.0 | 986 | 61 | 10 | 2 | 40 | 0 |
| shooters | walks away | never | never | 0 | 0 | 0 | 0 | 5 | 0 | 0 |
| shooters | hops on the spot | 2.1 s | 11.6 s | 4.0 | 584 | 29 | 3 | 54 | 40 | 0 |
| shooters | strafes one way | 2.4 s | 22.5 s | 2.0 | 325 | 26 | 1 | 58 | 22 | 0 |
| shooters | reacts to every tell | never | never | 0 | 0 | 0 | 0 | 93 | 0 | 0 |
| brutes | stands still | 2.3 s | 8.3 s | 6.0 | 840 | 30 | 5 | 0 | 28 | 0 |
| brutes | walks away | never | never | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| brutes | hops on the spot | 3.8 s | 39.5 s | 1.0 | 289 | 10 | 0 | 22 | 28 | 0 |
| brutes | strafes one way | 17.5 s | two seeds in three | 0.7 | 205 | 7 | 0 | 29 | 28 | 0 |
| brutes | reacts to every tell | never | never | 0 | 0 | 0 | 0 | 41 | 0 | 0 |
| brutes | swings, never dodges | 2.3 s | 15.6 s | 2.0 | 439 | 16 | 0 | 2 | 28 | 11 |
| fight | stands still | 1.7 s | **5.8 s** (5.7–5.8) | 4.0 | 587 | 40 | 40 | 26 | 66 | 0 |
| fight | walks away | never | never | 0 | 0 | 0 | 0 | 3 | 0 | 0 |
| fight | hops on the spot | 2.5 s | 9.9 s | 3.0 | 415 | 26 | 7 | 79 | 50 | 0 |
| fight | strafes one way | 3.2 s | 17.1 s | 1.0 | 231 | 16 | 1 | 102 | 50 | 0 |
| fight | reacts to every tell | never | never | 0 | 0 | 0 | 0 | 151 | 0 | 0 |
| fight | swings, never dodges | 2.8 s | 6.6 s | 4.0 | 556 | 32 | 17 | 29 | 62 | 277 |
| fight | swings and reacts | never | never | 0 | 0 | 0 | 0 | 97 | 0 | 397 |

The still player's time down in each set: `fodderRush` 8.7 s, `elites` 9.8 s, `shooters` 7.3 s,
`brutes` 8.3 s, `fight` 5.8 s. On thirty seeds `fight` runs from 5.1 to 5.8 s.

Damage by kind:

| Set, player | Fodder | Slinger | Marksman | Lobber | Brute | Elite |
|---|---|---|---|---|---|---|
| shooters, stands still | | 312 | 242 | 432 | | |
| shooters, hops | | 24 | 440 | 120 | | |
| shooters, strafes | | 300 | 7 | 18 | | |
| fight, stands still | 133 | 96 | 51 | 90 | 196 | 20 |
| fight, hops | 93 | 12 | 147 | 60 | 103 | 0 |
| fight, strafes | 16 | 116 | 22 | 30 | 47 | 0 |
| fight, swings, never dodges | 53 | 128 | 51 | 54 | 149 | 120 |

- **The reacting player takes no hit in any set,** fodder included, on ten seeds. The target
  allows him fodder damage. He needs none of it.
- **Blind movement is not a free pass, and each kind is answered by a different shooter.** A
  hopper avoids most lobs and shots, and the marksmen take him down in 11.6 s. A strafer walks
  out of lines and lobs, and the slingers take him down in 22.5 s.
- **Hopping in the rush.** One lunge in four lands on a hopper. He is down at 28.9 s, against
  8.7 s standing still.
- **Brutes.** A still player is down at 8.3 s, six times a minute. One charge in three lands on
  a hopper, 289 damage a minute, and he is down at 39.5 s. In `brutes` nothing else answers
  him. In `fight` the marksmen do.
- **`fight`, standing still: down at 5.8 s.** Brutes, fodder, slingers and lobbers do most of
  it.
- **Swinging without dodging in `fight` is down at 6.6 s.** The sword kills 277 enemies in 30 s
  and it does not save him: the brutes, the slingers and the elites reach him all the same. The
  other four melee families go down between 6.4 and 8.2 s.
- **Swinging and reacting takes nothing** and kills 397.
- **Walking away takes nothing in any set.** See the flags.

## Wave 2: bands (`--check`)

| Band | Value | Now |
|---|---|---|
| One hit of each new attack | ≤ 25% of health | 9%, 17%, 14%, 22% |
| One turn of each kind (`perPlayer` × damage) | ≤ 25% of health | 12%, 23%, 9%, 17%, 14%, 22% |
| The most one instant can cost by the rules, in every set | ≤ two thirds of the bar | 62% in `fight`, 40% in `shooters` |
| Still in `fight`: the worst quarter second | ≤ 55% of the bar | 51% |
| What each tell leaves beyond a step, a reaction and the walk out | ≥ 0.05 s | 0.25, 0.24, 0.83, 0.36 s |
| Each new kind is slower than the walk | yes | 11, 10, 9, 10 against 20 |
| A shooter's band lies inside its reach | yes | 18–30 in 32, 28–45 in 48, 22–40 in 42 |
| The shot flies at least its reach | yes | 70 ≥ 32 |
| The line shows before it locks; it is at least as long as its reach | ≥ 0.32 s; yes | 0.45 s; 60 ≥ 48 |
| Half the line's width against the snapped facing's error at its reach | > | 0.80 > 0.59 studs |
| Lob and lane: launch under the fence, flight and slide inside `knockIframes` | yes | 3 < 4; 0.35 s; 0.19 s and 0.40 s |
| A jump clears the lob; one jump clears the whole charge | yes | yes; 0.73 s ≥ 0.55 s |
| Dash against the lane: i-frames outlast its passing; distance clears it | yes | 0.25 s against 0.09 s; 20 ≥ 2.5 |
| The charge runs past where it starts | yes | 30 > 22 |
| The brute's recover against a reaction and one full combo | ≥ 0.05 s more | 1.5 s against 1.05 s |
| Slinger alone against a hopper: shots landing; seconds between hits from `fight`'s three | ≥ 20%; < 5.2 s | 33%; 3.1 s |
| Slinger alone against a strafer: the same | ≥ 50%; < 5.2 s | 100%; 1.0 s |
| Slinger alone against a hopper at 100 and 150 ms of ping | ≥ 20% | 28%, 22% |
| Slinger alone against a strafer at 100 and 150 ms of ping | ≥ 50% | 100%, 100% |
| Marksman alone against a hopper | ≥ 90% | 100% |
| Each shooter is the hardest hitter per head against one of the three players | yes | lobber: still; marksman: hopper; slinger: strafer |
| Shots in the air in any set | < `maxShots` (24) | 3 |
| Still in `fight`: down at | 4–8 s, every seed | 5.8 s (5.7–5.8) |
| Telegraphed hits on a player who reacts, in `elites`, `shooters`, `brutes` and `fight` | 0 | 0 |
| Swings, never dodges, in `fight` | goes down | at 6.6 s |
| Every melee family breaks the plate | within 2 combos | 2 to 6 hits |
| The plate against the biggest body hit of any family | more | 80 > 75.6 |
| After the break an SMG kills the elite | ≤ 2 s | 1.42 s and 1.29 s |
| The reel | 1.25–2.0 s | 1.5 s |
| The ground slam breaks the plate | in ≤ 2 slams | 2 |

Each band was proved by a value that makes it fail. Wave 1's bands and printed lines are all
still there. Its kiting-distance band stays on `fodderRush` and `elites`: wave 2's kinds attack
from further away than a walker keeps off.

**Where the starting values missed.** With the lead's first wave 2 set, before the review
round, eleven bands failed:
- the spawn clearance, because the pad was 5 studs from a slot;
- `fight` standing still, down at 2.8 s;
- the reacting player, hit by two shots in `shooters`;
- the marksman's lock (0.30 s against 0.36 s);
- the brute's slide (0.53 s);
- the slinger against the hopper (8%) and the strafer (0%), and with them "each shooter leads
  somewhere";
- the Broadsword and the Spinblade on the plate (9 hits);
- the reel (1.0 s).

## Wave 2: where the server can move these numbers

The simulator copies each of these. A change on the server moves the numbers named.

- **The shot is led over its flight plus the player's lag, in six passes.** That is what lets
  `lead` be 1.0 and the strafer be hit at any ping. With two passes a walker crossing at
  mid-band was missed by 1.8 studs, and the radius had to cover it.
- **The target's motion is one step's displacement.** A player who turns between two steps is
  led the wrong way for that shot. That is the slinger's counter and I have left it.
- **Only a root that is rising or falling is led down a fall,** as far as the surface it last
  stood on. The hopper's rate hangs on this rule and on how long he touches the floor.
- **The root is a point.** A body radius for the player would widen every shape by it: each
  margin loses 0.05 s for each stud.
- **The line locks on where he was at the lock.** If it locked on his led position, a strafer
  would be hit and the marksman would do the slinger's job as well.
- **The facing is snapped to 1/256 of a turn.** At 48 studs that is up to 0.59 studs off. A
  line narrower than 1.2 would miss a still player at some bearings.
- **The lob's centre is fixed when the windup ends.** If it were led, a walker would no longer
  be safe from it.
- **A place frees at the end of `attack`.** If `recover` held it too, three brutes would charge
  once every 2.85 s between them, and three marksmen once every 5.2 s.
- **Each kind has its own count.** A count shared by all shooters would let one slinger silence
  a marksman.
- **The charge stops at the arena's edge.** A brute standing against the fence has no runway
  toward a player who stands nearer that fence than the brute's own radius allows (2.2 studs).
  Its charge then has no length and cannot hit him.
- **Ruling 18 voids only what a knocking hit covers.** A line, a shot and two lunges can land
  with one knock. That is the 62% in "Turns".
- **Blocked hits do nothing.** If a blocked hit staggered or shoved, the plate would stop being
  a wall against a crowd weapon.

## Wave 2: flags for the owner

Ruled in the review round:
- **Enemies of one kind take turns.** It was my first flag: three marksmen fired as one, 66 at
  once, and the worst quarter second in `fight` took 78% of the bar. It is 51% now. See "Turns".
- **A shot is led over its flight plus the player's lag,** and in six passes. It was my P5
  flag. `lead` is 1.0 and the orb went from 4 studs across to 3.
- **The marksman's lock is 0.55 s,** for the phone thumb.
- **The contract's Roles table** names the new lock.

Known limits, for the owner:
- **Kiting still heals.** A player who runs a lap of the arena takes no damage in `shooters`,
  `brutes` or `fight`. In 60 s the six shooters get five attacks off at him and all miss. Every
  kind is slower than the walk, the shot flies at 28 against his 20, and the arena is 220 studs
  across. Wave 2's shooters punish a player who stays in the fight and moves blindly. They do
  not hold a player who leaves. That is P5's: a reason to stay (an objective, a timer), a
  smaller arena, or an enemy faster than the walk.
- **The elites are a time tax on a player who keeps swinging.** In `elites` he takes nothing
  with four melee families of five, and the Spear takes one or two arcs a minute. Every combo
  has a heavy hit, and a heavy hit cancels the arc. The plate costs the Broadsword 2.4 s more
  per elite. Everywhere else swinging alone no longer saves him: in `fight` every family is
  down between 6.4 and 8.2 s, and in `brutes` between 8.5 and 18.1 s.

Still open:
- **Slingers and the hopper.** A slinger alone lands 33% on him, and 22% at 150 ms of ping. In
  the sets it is 6% and 5%, because every get-up starts the crowd in step with his hop. The
  marksman is his real answer. The 33% also depends on my guess of 0.1 s on the floor between
  jumps: with none it is 15%.
- **Hopping is the cheapest defence against everything on the ground.** A hopper takes one
  lunge in four, one charge in three and one lob in four or five. If Ben finds that holding
  jump is too safe in `fodderRush` or `brutes`, the answer is a marksman in those sets, or a
  rule.
- **The turn rule made `brutes` and `elites` harder on a player who stands.** Fewer of their
  hits are voided. A still player in `brutes` takes 840 damage a minute where he took 392, and
  goes down six times a minute where it was two.
- **`fight` is hard on a player who does not dodge, and free for one who does.** A player who
  swings and never dodges is down at 6.6 s, and one who only strafes at 17.1 s. Expect Ben's
  first try to end somewhere in that span. The set is tuned to the contract's band for a still
  player, and I have no band between the two extremes.
- **The worst instant is half the bar, not under it.** 66 of 130 is 51%. Getting it under 50%
  for certain would take a fifth off the damage of several kinds, and the other bands with it.
  I set the band at 55% and say so here.
- **Six weapon variants cannot break a plate alone** (the list is under the matrix). In a
  loadout the melee slot or two slams always can. If Ben wants every ranged weapon to have its
  own answer, that is a weapon number or a ruling, and I have changed neither.
- **Not modelled:** cover, and the stairs. By the contract a wall stops shots and lines and not
  lobs, and the lobbers in `fight` stand by the cover for that reason. On high ground the three
  shooters reach a player and the ground shapes do not. The simulator's floor is flat, so none
  of this is measured.
- **Flat values (ruling 20) now include the plate.** `plate` 80 sits between two finishers of
  the tier-1 Broadsword and one of the Greataxe. P5 must scale it with `heavyHit` and enemy HP.
