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
