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
roles" below, **Stop 2, the Colossus** (the first boss) at "Stop 2 — the Colossus", and
**Stop 3, the Warlord** (the boss with a guard) at "Stop 3 — the Warlord".

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

## Stop 2 — the Colossus

The first boss (contract: `docs/INTERFACES.md` "Stop 2 — the Colossus"): a giant with four
attacks, two phases, and fodder it calls. Solo, at tier-1 health (130).

Targets, from the contract and the lead's brief:
- a player who reacts to every tell kills it in 60 to 90 s with any melee family and takes no hit;
- a player who only ever jumps the ring and sidesteps the charge survives the fight;
- a player standing still is down inside 10 s;
- no hit over 25% of health, and no instant over the Stop 1 ceilings;
- each attack leaves a window of at least a second, in both phases;
- every tell clears a 0.25 s reaction, and a 0.35 s phone thumb, also when it is the second
  attack of a chain;
- the ring can be jumped at any distance inside its radius, and walked out of only from far out;
- what it calls matters and does not decide the fight;
- a ranged-only loadout can kill it too.

## Stop 2: what the simulator gained

`py tools/sim_range.py` prints a BOSS table and `--check` guards its bands. The boss is a crowd
enemy like the others, so everything of Stop 1 applies to it. The new parts follow the server
as built:

- **Several attacks and the choice.** Among the attacks allowed in the phase, in reach and off
  cooldown, the one whose last impact is oldest. One never used counts as oldest, and the
  list's order breaks a tie. The attack of the last windup is taken only when no other is
  ready. A cooldown runs from the attack's impact. The body closes to its shortest reach.
- **The ring.** At the impact a front leaves the body's feet and grows to `radius` at `speed`.
  Its band is `width` wide round the front. A player within `radius` is hit once, when the
  band reaches him with his feet under `height`. The body's own attack lasts `strikeSeconds`.
- **The call.** Fodder rise on a circle of `radius` round the boss, as many as bring its living
  summons to `count`. They fight, wait out `spawnGrace`, never respawn and fall with the boss.
- **The barrage.** `count` lobs at once: the first on the target, the rest at even angles
  round him, each up to `spread` away. A player takes at most one circle of a barrage.
- **Enrage.** At half health, asked when an attack ends and before each choice: windups and
  recovers are scaled, the barrage unlocks, and up to `chain` attacks follow each other with no
  recover between. The attack the phase began in is not part of a chain.
- **The giant** is never pushed by a smaller body.

The players of a boss fight:
- **Stands still.**
- **Jumps the ring, sidesteps the charge:** he answers those two tells and no other. He does
  attack: what the boss called while it is on him, then the boss.
- **Reacts to every tell, attacks:** the Stop 1 planner, holding his ground. He takes a short
  step, then a jump he times, before any long walk or dash, and walks back into reach when
  nothing threatens. He is run with each of the 13 families, without abilities and with them.

Assumptions of the model, not tunables:
- Attacks go on while he moves or jumps. A ranged weapon fires along the aim ray at the body,
  so it never crits.
- An ability is cast at the boss whenever it is ready, on its base cooldown, with no refunds,
  and its whole damage lands at the cast. He does not cast one that deals less than his own
  attacks would in the time it locks him: Whirlwind and Overload Sweep are for crowds.
- He can move sideways in the air.

**Why `windupScale` 0.8 failed at first.** A longer tell got the reacting player hit, and that
was the planner's error, not the fight. He judged a jump against a landing circle and a
passing charge at moments of his own, a thirtieth of a second apart, while the server decides
on a frame. A jump coming down loses over a stud a frame. So he took a plan that cleared a
circle 4 studs high by 0.4 studs on paper and was 0.8 under it when it was decided, and one
that cleared the charge's 6 studs by 0.7 and was 0.4 under. At 0.75 no landing fell on those
frames; at 0.8 a barrage or a charge chained after a ring put one there. He now follows both
frame by frame and allows himself a frame either way. With that, 0.8 passes every band and
no family takes a hit on nine seeds. Stop 1's tables did not move.

## Stop 2: values

| Key | Lead | Now | Why |
|---|---|---|---|
| `colossus.hp` | 6000 | **4700** | With the lead's set the five melee families take 78 to 105 s. At 4700 they take 64 to 82 s, and 63 to 85 s over nine seeds. |
| `colossus.speed` | 7 | **9** | It walks back to the player sooner after its own charge. It is one of the things that put a still player down inside 10 s. An elite walks at 9 too. |
| `enrage.recoverScale` | 0.6 | **0.7** | At 0.6 the enraged ring leaves 0.94 s and the enraged charge 0.88 s. At 0.7 they leave 1.10 s and 1.08 s. |
| `enrage.windupScale` | 0.75 | **0.8** | Phones first, as ruling 19 and the marksman's lock. At 0.75 the enraged charge left a 0.35 s thumb 0.08 s to sidestep. At 0.8 it leaves 0.13 s. |
| `enrage.at`, `chain` | 0.5, 2 | same | Half health, and two attacks in a row. |
| ring `radius`, `speed` | 26, 34 | **40, 70** | At the lead's values a player could walk out of the ring from anywhere inside it: the front was barely faster than the walk. Now walking out works only from 15.3 studs or further, and the boss starts the ring within 14. So the player it is aimed at has to jump. |
| ring `windup` | 1.1 | **1.0** | Every tenth of windup is two more studs of walking out. 1.0 s still clears a reaction by 0.63 s. |
| ring, the rest (reach 14, recover 1.6, damage 26, knockback 24, launch 3, width 3, height 4, cooldown 6) | | same | 26 is 20% of health. The band is on one spot for 0.11 s and a jump is above it for 0.76 s. |
| lane `reach` | 40 | **30** | With the boss 42 studs off, only the call is in reach when the fight opens. See "The opening". |
| lane `damage` | 30 | **32** | 24.6% of health, the most the rule allows. It takes half a second off the still player's time. |
| lane `knockback` | 36 | **30** | 36 is a slide of 0.48 s, longer than `knockIframes` (0.40 s). The same change as the brute's. |
| lane, the rest (windup 1.0, recover 2.0, range 44, width 10, speed 60, height 6, cooldown 8) | | same | A sidestep is 5 studs: 0.57 s of the 1.0 s tell. A jump or a dash clears it too. |
| summon `windup`, `recover`, `radius` | 1.4, 1.2, 12 | **1.0, 1.0, 16** | The fodder are up 0.4 s sooner and 4 studs nearer. The call still leaves the longest window, 2.2 s. |
| summon, the rest (count 12, cooldown 18, reach 60) | | same | Twelve fodder cost a Broadsword 2.8 s of the fight. |
| lob, all of it (windup 0.9, recover 1.4, damage 18, knockback 14, radius 5, seconds 1.6, count 5, spread 14, cooldown 10) | | same | One circle of the five can land: 18, 14% of health. A straight walk begun on a reaction covers 26 studs before they land, and every circle lies within 19. |
| `dummySets.colossus` position | (0, 60) | **(0, 48)** | 42 studs from the pad. See "The opening". |
| `defaultSet` | `fight` | **`colossus`** | The lead's ruling: Play opens on the boss. |

**The opening.** A still player has to be down inside 10 s, and the boss alone cannot do it.
With no call he lasts 28 s: the cooldowns allow one slam in six seconds and one charge in eight.
Even with no cooldowns it needs five hits of 25%, and an attack with a readable tell and a
one-second window after it takes 2 s: 11 s in all. The fodder make the difference: two lunges
every 0.8 s, 20 damage a second. So the fight has to open with the call. With the boss 42
studs off and the charge's reach at 30, the call is the only attack in reach when `spawnGrace`
ends. The still player is then down at 8.6 s (8.4 to 8.7 s over ten seeds): lunges from 3.8 s,
the charge at 5.1 s, the ring at 8.6 s. With the lead's layout the charge came first and he
was down at 14.0 s.

## Stop 2: the attacks

| Attack | Phase | Damage | Tell | The answer needs | For a 0.35 s thumb | Window after it |
|---|---|---|---|---|---|---|
| Ring (slam) | calm | 26 (20%) | 1.00 s | 0.37 s: a jump | 0.47 s | 1.58 s |
| Ring | enraged | 26 | 0.80 s | 0.37 s | 0.47 s | 1.10 s |
| Lane (charge) | calm | 32 (25%) | 1.00 s | 0.57 s: 5 studs aside | 0.67 s | 1.68 s |
| Lane | enraged | 32 | 0.80 s | 0.57 s | 0.67 s | 1.08 s |
| Summon (call) | calm | none | | none needed | | 2.20 s |
| Summon | enraged | none | | none needed | | 1.70 s |
| Lob barrage | enraged only | 18 (14%) | 1.60 s (the flight) | 0.57 s: 5 studs out of a circle | 0.67 s | 1.18 s |

- **Tell** is the time the attack gives. **Needs** is a crowd step, the reaction and the move.
- **Window** is how long after its danger the boss does nothing. In the enraged phase a window
  follows the last attack of a chain, and there is none between the two.
  - Ring: from the moment the band has passed a player at the boss's standoff (14 studs).
  - Lane: its recover, less the 0.32 s a melee player needs to be back in reach of where the
    charge ended. A ranged player has the whole recover: 2.0 s and 1.4 s.
  - Summon: there is no danger, so its windup counts too.
  - Barrage: from the throw. The circles are still in the air for part of it.
- **A chain's second attack** has its whole windup, and it starts when the first attack ends.
  The tightest is a charge after a ring: 0.80 s against 0.57 s, and 0.13 s to spare for a thumb.
- **The ring and the jump.** The front crosses its 40 studs in 0.57 s. The band is on one spot
  for 0.11 s, and a jump holds the feet above it for 0.76 s, so the jump has over half a
  second of room at any distance.
- **The ring and walking.** On foot it can be left only from 15.3 studs or further (19.3 when
  enraged). With a dash it can be left from anywhere, and a dash's i-frames also carry him
  through the front.
- **The most one instant can cost** is 48, 37% of health: two lunges and the charge. Every
  attack of the boss knocks, so ruling 18 lets only one of its own land at a time.

## Stop 2: results (tier 1, mean of three seeds; two for the ranged families)

These are the numbers Stop 2 shipped with. In Stop 3 the server moved where summons rise, and
the Colossus's rows moved by up to 4 s: today's are in "Stop 3: the Colossus again".

| Player | Weapon | Kill | Fastest to slowest | Enraged at | Hits of the boss | Lunges | Damage taken |
|---|---|---|---|---|---|---|---|
| Stands still | | never; down at **8.6 s** | | never | 5 | 33 | 404 in 30 s |
| Jumps the ring, sidesteps the charge | Broadsword | 73.5 s | 73.1–73.9 | 37.7 s | 4 | 0 | 86, no down |
| Reacts to every tell | Broadsword | **76.3 s** | 75.4–76.8 | 37.7 s | 0 | 0 | 0 |
| Reacts to every tell | Warhammer | **81.7 s** | 81.3–82.4 | 39.9 s | 0 | 0 | 0 |
| Reacts to every tell | Spinblade | **69.5 s** | 68.1–71.8 | 34.6 s | 0 | 0 | 0 |
| Reacts to every tell | Greataxe | **79.2 s** | 77.8–80.7 | 38.8 s | 0 | 0 | 0 |
| Reacts to every tell | Spear | **64.4 s** | 62.8–65.6 | 34.1 s | 0 | 0 | 0 |
| Reacts, and the boss calls nothing | Broadsword | 73.5 s | 73.3–73.8 | 37.4 s | 0 | 0 | 0 |

Kill times for every family, without its ability and with it:

| Family | Kill | With its ability | |
|---|---|---|---|
| Broadsword | 76.3 s | 76.3 s | Whirlwind is not cast at a lone boss. |
| Warhammer | 81.7 s | 67.7 s | |
| Spinblade | 69.5 s | 55.4 s | |
| Greataxe | 79.2 s | 71.0 s | |
| Spear | 64.4 s | 56.3 s | |
| Piercing Rifle | 55.0 s | 38.3 s | |
| SMG | 58.5 s | 37.5 s | |
| Chain Gun | 77.1 s | 61.0 s | |
| Shotgun | 93.8 s | 72.9 s | |
| Launcher | 115.3 s | 66.6 s | |
| Beam | 118.4 s | 118.4 s | Overload Sweep is not cast at a lone boss. |
| Longbow | 142.3 s | 117.6 s | |
| Splitbow | 225.8 s | 180.9 s | One arrow of seven finds a single target. |

- **The reacting player takes no hit with any of the 13 families.**
- **The jump-and-sidestep player survives.** He takes four hits of the boss in the worst seed:
  lobs he does not walk out of, and one charge that lands while a lob's knock has him. That is
  86 damage in all. No fodder touches him, because he kills them. He never goes down, on ten
  seeds. He is also 3 s faster than the player who reacts to everything: walking out of
  circles costs sword time.
- **What it calls costs a Broadsword 4%** of the fight: 76.3 s against 73.5 s with no call.
  The arc kills the fodder as it turns to them.
- **Ranged-only loadouts all kill it.** Rifle and SMG are faster than any melee family. Six of
  the eight are inside two minutes. The Longbow takes 142 s and the Splitbow 226 s.
- **A second player.** The boss's health does not scale in the range, so two players of the
  same family finish in about half the time: 32 to 41 s for two melee players. That is under
  the 60 s floor.

## Stop 2: bands (`--check`)

| Band | Value | Now |
|---|---|---|
| One hit of each attack | ≤ 25% of health | 20%, 25%, 14% |
| Each tell beyond a step, a 0.25 s reaction and the answer | ≥ 0.05 s | 0.63 and 0.43 s (ring), 0.43 and 0.23 s (lane), 1.03 s (barrage) |
| Each tell against a 0.35 s thumb | ≥ 0.12 s | the tightest: enraged lane, 0.13 s |
| A chain's second tell against a thumb | ≥ 0.12 s | 0.13 s |
| The window after each attack, each phase | ≥ 1 s | 1.08 to 2.20 s |
| Each knock: launch under the fence, flight and slide inside `knockIframes` | yes | 3 < 4; 0.35 s; 0.32, 0.40 and 0.19 s |
| Ring: a jump's time above it against the band's time on one spot | more, by 0.05 s | 0.76 s against 0.11 s |
| Ring: it reaches past where it starts | yes | 40 > 14 |
| Ring: the nearest point walking out works from | ≥ its reach (14) | 15.3 studs; 19.3 enraged |
| Lane: a jump clears it; a dash's i-frames outlast its passing | yes | yes; 0.25 s against 0.17 s |
| Barrage: a straight walk covers every circle's reach before they land | yes | 26 ≥ 19 studs |
| The most one instant can cost by the rules | ≤ two thirds of the bar | 37% |
| Standing still: down | inside 10 s, every seed | 8.6 s (8.4–8.7) |
| Standing still: the worst quarter second | ≤ 55% of the bar | 37% |
| Jumps the ring, sidesteps the charge | no down, and the boss falls | 0 downs; 73.5 s |
| Reacting, each melee family, no ability: the kill | 60–90 s, every seed | 62.8 to 82.4 s |
| Reacting, each melee family: hits taken | 0 | 0 |
| Reacting, every family, with or without its ability: hits of the boss | 0 | 0 |
| What it calls lengthens the default melee's kill by | 3% to 30% | 4% |

Each band was proved by a value that makes it fail. All of Stop 1's bands and printed lines are
still there, with the same numbers.

**Where the starting values missed.** With the lead's set thirteen bands fail: the enraged
charge's thumb margin (0.08 s, alone and in a chain), the enraged ring's
window (0.70 s) and the enraged charge's (0.88 s), the charge's slide (0.48 s), walking out of
the ring (possible from anywhere, in both phases), standing still (14.0 s), the kill with the
Spinblade (90 s), the Broadsword (94 s), the Greataxe (96 s) and the Warhammer (105 s), and
what the call costs (under 3%).

## Stop 2: rules these numbers hang on

The simulator follows the server's report. These are the rules a change would move most.

- **The body closes to its shortest reach, and attacks on its way in.** The opening hangs on
  this: at 42 studs only the call reaches.
- **The ring's `attack` state lasts `strikeSeconds`.** If it lasted the front's 0.57 s of
  travel, every ring's window would be 0.37 s longer and a chained attack would start later.
- **A chained attack starts on the step the one before it ends, aimed from where a charge set
  the body down.**
- **A call tops up.** If calls stacked, a player who left the fodder alive would face 24 and
  then 36. With the cap of two lunges at a time his damage would not change, only the crowd.
- **A player takes one circle of a barrage.** Circles that overlapped on him would otherwise add up, to 90 at the most.
- **The player can move sideways in the air.** Without it, a charge chained after a ring leaves
  a player who jumped late no time on the ground to sidestep.
- **Attacks go on while he moves.** If a jump or a step stopped his swing, every kill time
  would grow by the time he spends dodging.
- **One thing the simulator does not copy:** a body refused its place is not offered a second
  choice in the same step. With one boss and a free place it changes no number. (Until Stop 3
  its summons also rose from angle 0 round the caller; they now rise where the server puts
  them.)

## Stop 2: flags for the owner

- **The fight opens with the call, and that is what puts a still player down in time.** It
  works because the boss starts 42 studs from the pad. A player who walks at it gets the charge
  or the slam first. If the boss should open with a slam at arm's length, the 10 s target has
  to give: with the lead's layout a still player lasted 14.0 s, and with no call 28 s.
- **"Walked out of only from near its edge" cannot be literal.** A one-second tell is 13.7
  studs of walking before the ring even leaves. What the values give is that the player it is
  aimed at cannot walk out (15.3 against 14). With a dash he can, from anywhere, and that costs
  him his place at the boss.
- **Abilities take a melee kill under the floor.** With its ability the Spinblade takes 55.4 s
  and the Spear 56.3 s. The 60 to 90 s band is measured without abilities, as the brief has it.
- **Reacting to everything is slower than ignoring the barrage.** The player who only jumps and
  sidesteps wins 3 s sooner and loses 86 health in all. It says the barrage is the gentlest of
  the four.
- **The Warhammer has the least room: 85.2 s at the slowest of nine seeds.** The Spear is the
  other end at 62.8 s. The band holds both, with about 3 s under the Spear and 5 s over the
  Warhammer.
- **What it calls costs the Broadsword 4%,** and the band's floor is 3%. The arc kills the
  fodder almost for free. A single-target weapon pays more.
- **The charge is 32, which is 24.6%.** There is no room left under the 25% rule.
- **Not modelled:** crits (a ranged player who aims at the head is faster), kill refunds on
  abilities, the fodder under a crowd ability, cover, and the stairs.

Known limits, for the owner (ruled by the lead):
- **Boss health does not scale with players in the range.** Two melee players finish in 32 to
  41 s. Missions scale it (C2).
- **The bows are slow on a boss:** the Splitbow takes 226 s (181 s with its ability) and the
  Longbow 142 s. The Splitbow deals 31 damage a second to one target. A weapon-number question.
- **Kiting works here too.** The boss walks at 9 and its slam reaches 14. A ranged player who
  keeps 31 studs off meets only the call and, when it is enraged, the barrage. P5's.

## Stop 3 — the Warlord

The second boss (contract: `docs/INTERFACES.md` "Stop 3 — the Warlord and his guard"): a siege,
then a duel. Calm, he keeps his distance, calls a guard of four plated elites once and throws
barrages; while his guard lives his plate takes nothing. When the plate breaks he reels, and
then he turns: he closes in and fights with a wide arc, a charge and a bigger barrage, chained.
Solo, at tier-1 health (130).

Targets, from the contract and the lead's retarget after the first round (the first round
aimed at 90 to 150 s; the owner called the Colossus's 76 s "about right", so the fight was
shortened and its middle cut):
- a player who reacts to every tell wins in **75 to 115 s** with any melee family and takes no hit;
- the plate phase (guard dead to plate broken) is at most 20 s for the default sword and for
  the ground slam, and he gives no more than about 60 studs of ground in it;
- the siege (start to plate broken) is 35 to 55% of the fight for every melee family;
- every loadout has a way through the guard's plates and his (the ground slam counts);
- the guard is not a slog for single-target weapons: every ranged family that can win does so
  inside 150 s (the bows are a known weapon question, flagged and not fixed);
- a player who ignores the guard and chases him gets nowhere and is punished;
- a player standing still is down inside 10 s;
- no hit over 25% of health, and no instant over the Stop 1 ceilings;
- every tell clears a 0.25 s reaction and a 0.35 s phone thumb by at least 0.12 s;
- each of his duel attacks leaves a window of at least a second.

## Stop 3: what the simulator gained

The BOSS part of `py tools/sim_range.py` now prints the Warlord after the Colossus, with three
more tables (the guard, the way through the plates, the siege), and `--check` guards his bands.
The new rules follow the server as built and the lead's rulings:

- **`calm`** is the mirror of `enraged`: a calm attack is only chosen before the second phase.
- **`uses`** is counted at the impact, in the body's life. An attack the body may no longer
  use (wrong phase, or out of uses) stops counting toward the reach it walks to.
- **`guarded`.** His plate takes nothing, heavy or not, from the moment he spawns until his
  guard has been called and is dead. "Called" is the summon's impact. Only the plate is guarded.
- **The reel.** The hit that empties a plate reels the body for `plateBreakSeconds` (1.5 s)
  whatever its `knockbackMult`; only a charge under way runs on. A windup it was in is
  cancelled whatever its `interrupt` (one whose impact time has come still lands) and recovers
  in full from the break.
- **The turn.** `enrage.at` is 1, so he is enraged at the step the plate breaks, or when the
  attack he was in ends. The phase is now asked in every step outside a windup and an attack.
  From then he moves by `enrage.brain` (`rush`): he closes to 9 studs, the reach of the arc,
  and stands through his recovers.
- **Summons rise on the caller's facing,** half a step off it for an even count, and a call
  tops up the places none of its living summons rose on.
- **`crowd.largeRadius`** is read from the config (2.5): the Warlord, at 2.6, is never pushed
  by his guard.

The players of this fight:
- **Stands still.**
- **Ignores the guard, chases him:** he walks at the Warlord and swings at him and at nothing
  else, and answers no tell. Watched for 90 s.
- **The same, and reacts to every tell.** Watched for 90 s.
- **Reacts to every tell, attacks:** the Stop 2 player. While the plate is guarded he goes for
  the nearest of the guard, wherever it is; then for the Warlord. He is run with each of the 13
  families, without abilities and with them.

Assumptions of the model, added to Stop 2's:
- **The ground slam.** A family none of whose hits is heavy (SMG, Beam, Splitbow) breaks plates
  with the slam: he walks into its reach and slams whenever it is ready, 45 damage every 1.8 s
  to every body in its radius, and his weapon is still for 0.4 s each time. A family with a
  heavy hit never slams, though a real player could do both.
- **An ability is cast only once the plate is broken,** at the Warlord. It is never spent on
  the guard, where a crowd ability would do most. So the ranged families' time on the guard
  is the worst case.
- Before the call, the reacting player walks at the Warlord and his hits are warded. It costs
  him nothing: the guard rises 9 studs from the Warlord, where he then stands.

**One planner error fixed.** A blow is decided on the first frame at or after its time, after
the player has moved in that frame. The planner dropped a blow whose time fell inside the
current frame, and could then step into it. It showed once: a rifleman stepped into a guard's
arc in one seed of nine. The boss-fight player now counts such a blow where this frame's move
puts him. The Stop 1 player is unchanged.

**What moved in the earlier tables.**
- Stop 1 and wave 2: nothing. Every line is printed with the same numbers. The guard appears
  as one more kind in the attack table and the turns table.
- The turns band now says what ruling 18 already meant (accepted by the lead): when a kind's
  attack knocks, a turn of several costs one hit, because the first knock voids the rest. With
  one place a kind's line reads as before. The guard's reads "2 guard at once, of which the
  first knock voids the rest, = 28 = 22%".
- The Colossus's measured rows moved, by 4 s at the most, and only because its fodder now rise
  where the server puts them. With the old places put back the rows are the Stop 2 numbers to
  the last digit. They are in "Stop 3: the Colossus again" below. Every Stop 2 band still passes.

## Stop 3: values

| Key | Lead | Now | Why |
|---|---|---|---|
| `guard.hp` | 120 | **1400** | Four guards of 120 fall to a cleave in 3 s, and the siege was a quarter of the fight. At 1400 the guard lasts a melee family 23 to 27 s. It is also what holds the two hammers' siege over 35%: at 1200 theirs is 34.9%. |
| `guard.speed` | 9 | **11** | The guard has to be faster than the Warlord backs off, or it never reaches a player who is at him. |
| guard arc `damage` | 26 | **28** | 22% of health. Four arcs and one barrage circle put a still player down; at 26 it takes five arcs. |
| guard arc `knockback` | 30 | **26** | A knock of 30 throws the still player 6 studs, out of the barrage circle already in the air (radius 5), so the barrage never landed on him. 26 throws him 4.5. It is also the least that keeps the Stop 1 rule that a second arc from the same side cannot chain (90 degrees). |
| guard, the rest (plate 40, 2 at a time, arc windup 0.8, recover 1.2, reach 6, range 7.5, 120 degrees) | | same | One heavy hit or one ground slam breaks a guard's plate, and it reels 1.5 s. The 0.8 s tell leaves a thumb 0.21 s. |
| `warlord.hp` | 2600 | **3650** | The duel: 40 to 59 s for a melee family. At 3300 the Spear's fastest seed is 73.7 s, under the floor; at 3900 the Beam needs 151.7 s, over the ranged ceiling. |
| `warlord.plate` | 240 | **385** | Counted in hits: nine Broadsword finishers (9 × 43.2 = 388.8), nine slams, eight hits of either hammer, seven Spear finishers. From 389 the Broadsword needs a tenth finisher, and its plate phase passes 20 s (20.3 s at 390 in one seed of six, 20.5 s at 450). Under 383 the Warhammer needs one hit fewer and its siege loses about half a point. |
| `warlord.speed` | 11 | **3** | He backs away from any player inside 24 studs. At 3 he gives 44 studs in the plate phase; at 5 he gives 69, over the 60. Under 2 the chaser gets through: see "His speed" below. Enraged he has the charge (reach 34) to close. |
| `warlord.bandMin`, `bandMax` | 30, 46 | **24, 40** | He stands 28 studs from the pad. With 30 he opened by backing off. |
| summon `windup` | 1.2 | **1.0** | As the Colossus's call. The guard is up at 2.05 s. |
| summon, the rest (count 4, radius 9, recover 1.0, uses 1) | | same | Four is what the owner was shown. |
| calm lob, all of it (windup 0.9, recover 2.2, damage 18, radius 5, seconds 1.6, count 3, spread 12, cooldown 5) | | same | One barrage every 5.9 s. One circle of the three can land: 14% of health. |
| arc `windup` | 0.8 | **0.9** | At 0.8 a 0.35 s thumb had 0.11 s to walk the 5.5 studs out of a half circle, under the 0.12 s floor. At 0.9 it has 0.21 s. |
| arc, the rest (reach 9, range 11, 180 degrees, recover 1.4, damage 30, knockback 30, cooldown 3) | | same | 23% of health. |
| lane, all of it (reach 34, range 36, width 7, speed 60, windup 0.9, recover 1.8, damage 30, cooldown 7) | | same | A sidestep is 3.5 studs: a thumb has 0.31 s to spare. |
| enraged lob, all of it (windup 0.8, recover 1.4, count 4, spread 12, cooldown 9) | | same | |
| `enrage` (at 1, scales 1 and 1, chain 2, brain `rush`) | | same | |
| `dummySets.warlord` position | (0, 62) | same | 28 studs from the pad. |
| `crowd.largeRadius` | 2.5 (lead) | same | Confirmed. Only the Warlord (2.6) lies between 2.5 and 3, so no Stop 1 or Stop 2 number moves. |
| `defaultSet` | `colossus` | **`warlord`** | The contract: Play opens on the Warlord. |

The first round shipped `guard.hp` 1300, `warlord.hp` 4100, `plate` 850 and `speed` 5 for the
90 to 150 s target: 124.6 s with the Broadsword, 38 s of it on the plate, 160 studs of ground.

**His speed: the chaser against the ground he gives.** These two do pull against each other,
and only through his speed. The plate phase's length hardly depends on it (with a plate of
450: 20.5 s at speed 1, 22.6 s at 3, 21.3 s at 5); the ground he gives does: 44 studs at 3, 69
at 5. The chaser needs him to keep backing off. When he all but stands (speed 1), the guard
gathers round the player at his feet, the player's arc kills it without meaning to, and the
plate breaks, in every seed of six. At 1.5 a chaser who dodges everything broke through in one
seed of three. From 2 up no chaser does. So the values leave a window from 2 to about 4, and
3 sits in it: no rule is needed. If the Warlord should give no ground at all in the plate phase, the rule "he
stops backing off once his guard is dead" does it, and costs the chaser band nothing, because
that band is about the time the guard lives.

## Stop 3: the attacks

| Attack | Phase | Damage | Tell | The answer needs | For a 0.35 s thumb | Window after it |
|---|---|---|---|---|---|---|
| Summon (the call) | calm, once | none | | none needed | | 2.20 s |
| Lob barrage, 3 circles | calm | 18 (14%) | 1.60 s (the flight) | 0.57 s: 5 studs out of a circle | 0.67 s | 2.40 s |
| Arc | duel | 30 (23%) | 0.90 s | 0.59 s: 5.5 studs out of it | 0.69 s | 1.60 s |
| Lane (charge) | duel | 30 (23%) | 0.90 s | 0.49 s: 3.5 studs aside | 0.59 s | 1.52 s |
| Lob barrage, 4 circles | duel | 18 (14%) | 1.60 s (the flight) | 0.57 s | 0.67 s | 1.60 s |
| The guard's arc | siege | 28 (22%) | 0.80 s | 0.49 s: 3.5 studs out of it | 0.59 s | its recover, 1.2 s |

- **The tightest tell** is 0.21 s over a thumb's need: the Warlord's arc and the guard's arc.
  In a chain the second attack's windup is whole and starts when the first attack ends.
- **The arc** is a half circle of 11 studs round him, started when the player is within 9. A
  jump clears it from 0.08 to 0.78 s after take-off. Every melee family reaches him from
  outside it (the shortest, the Spinblade, from 13.1 studs), so a player who steps out is in
  reach at once: the whole 1.6 s is his.
- **The charge** runs 36 studs in 0.6 s. A melee player is back in reach 0.28 s into its
  recover.
- **The most one instant can cost** is 30, 23% of health. Every attack of his and the guard's
  arc knock, so ruling 18 lets one land at a time.
- **Two guards at a time.** Their arcs land one at a time for the same reason. A still player
  takes a guard's arc about every 1.5 s.
- **The reel at the turn.** From the break to his first duel windup is 1.5 s, or 2.2 s when
  the plate breaks inside the calm barrage's windup (that windup is cancelled and recovers in
  full). The first duel blow lands 2.4 s after the break at the soonest. Before the ruling the
  median pause was 0.05 s: in 29 fights of 45 his first duel windup began in the step after
  the shatter. The reel costs him 2 to 3% of his health and moves no kill by a second.

## Stop 3: the fight, second by second

The default loadout (Broadsword), a player who reacts to every tell, seed 11. Means of three
seeds in brackets.

| At | What happens |
|---|---|
| 0 s | The set loads. He stands 28 studs from the pad. His plate is guarded from the start. |
| 1.05 s | He raises the call (windup 1.0 s). |
| 2.05 s | Four guards rise 9 studs round him and rush the player. |
| 3.25 s | The first barrage: three circles land 2.5 s later. One follows every 5.9 s, seven in the siege. |
| 22.1 to 24.5 s | The four guards fall, within 2.4 s of each other: the arc hits them together. (25.9 s) |
| 24.5 to 42.6 s | The plate: nine finishers in 18.1 s, with three barrages to step out of. He backs off at 3 studs a second. |
| 42.6 s | The plate breaks. He reels for 1.5 s and is enraged. (43.1 s) |
| 44.2 s | His first duel windup: a charge. |
| 44.2 to 98.1 s | The duel: 7 arcs, 7 charges, 6 barrages, in chains of two. |
| 98.1 s | He falls. (97.7 s; 94.9 to 101.1 s over nine seeds) |

On the three-seed means: 25.9 s of guard, 17.2 s of plate, 54.6 s of duel. The siege is 44% of
the fight. Over the whole siege he walks 45 to 54 studs, so the duel begins near the middle of
the arena.

## Stop 3: results (tier 1, mean of three seeds; two for the ranged families)

| Player | Weapon | Outcome |
|---|---|---|
| Stands still | | Down at **9.0 s** (8.8 to 9.4 s over twelve seeds). First hit at 4.4 to 4.8 s; 17 hits in 30 s. |
| Ignores the guard, chases him | Broadsword | After 90 s: plate **100%**, guard alive, 187 swings warded. Down first at **17.8 s** (11.7 to 21.6 s over nine seeds), 5 to 8 times in the 90 s; up to 40 hits, 780 health lost at the least. |
| The same, and reacts to every tell | Broadsword | After 90 s: plate 100%, guard alive, 175 swings warded. He takes no hit and gets nowhere. |
| Reacts to every tell, attacks | every melee family | Kill in **79.1 to 97.7 s**, no hit taken. |

**How the chaser is punished.** His swings at the Warlord are warded, all of them. The guard
walks 8 studs a second faster than the Warlord backs off, so it is on him at once, and each
arc throws him 4.5 studs off his target. He takes an arc every 3 s or so and goes down every
15 s: six health bars or more in the 90 s. A chaser who dodges everything loses nothing and still
breaks nothing.

Kill times per melee family, without its ability:

| Family | Guard dead | Plate broken | Plate phase, longest | Ground given | Kill | Fastest to slowest | Siege | Duel | With its ability |
|---|---|---|---|---|---|---|---|---|---|
| Broadsword | 25.9 s | 43.1 s | **18.1 s** | 44 studs | **97.7 s** | 97.3–98.1 | 44% | 54.6 s | 97.7 s (Whirlwind is not cast at a lone boss) |
| Warhammer | 26.7 s | 35.7 s | 10.3 s | 24 | **95.1 s** | 93.3–96.2 | 38% | 59.4 s | 84.4 s |
| Spinblade | 22.6 s | 36.6 s | 14.5 s | 34 | **89.8 s** | 87.5–92.0 | 41% | 53.2 s | 78.1 s |
| Greataxe | 26.1 s | 34.7 s | 9.5 s | 20 | **92.9 s** | 91.6–94.0 | 37% | 58.2 s | 86.0 s |
| Spear | 26.7 s | 39.3 s | 13.0 s | 22 | **79.1 s** | 77.4–82.3 | 50% | 39.7 s | 72.8 s |

Over nine seeds the five families take 77.4 to 101.1 s, none takes a hit, the Broadsword's
plate phase is 18.6 s at the longest and its siege shares run from 37.0% (Greataxe) to 50.5%
(Spear).

Ranged families (none of them takes a hit either):

| Family | Guard dead | What it pays for the guard | Plate broken | Kill | With its ability | Way through the plates |
|---|---|---|---|---|---|---|
| Piercing Rifle | 34.0 s | 8 s | 38.1 s | 74.4 s | 64.5 s | its hits |
| Chain Gun | 30.8 s | 5 s | 36.7 s | 87.5 s | 78.3 s | its hits |
| SMG | 55.9 s | 30 s | 73.4 s | 107.5 s | 95.5 s | the slam: 11 slams, 17.5 s |
| Shotgun | 46.9 s | 21 s | 53.9 s | 116.1 s | 103.0 s | its hits |
| Launcher | 39.3 s | 13 s | 48.7 s | 130.0 s | 99.3 s | its hits |
| Beam | 54.8 s | 29 s | 72.5 s | **145.8 s** (146.7 at the slowest) | 145.8 s | the slam: 11 slams, 17.8 s |
| Longbow (a bow) | 73.5 s | 48 s | 81.9 s | 158.6 s | 147.0 s | its hits |
| Splitbow (a bow) | 74.4 s | 49 s | 91.2 s | 208.3 s | 191.6 s | the slam: 11 slams, 17.6 s |

"What it pays for the guard" is its time to the last guard's fall, less the Broadsword's 25.9 s.

- **The guard is 5600 health in four bodies.** A melee arc hits them together and is through
  in 23 to 27 s. The Chain Gun, the Rifle and the Launcher pay 5 to 13 s more. The Shotgun
  pays 21 s. The SMG and the Beam pay 29 to 30 s: the guard is half of the SMG's fight and
  over a third of the Beam's. The bows pay 48 s.
- **Every ranged family that is not a bow wins inside 150 s.** The Beam is the slowest at
  146 s. The Longbow takes 159 s and the Splitbow 208 s: the Stop 2 weapon-number question.
- **The guard cannot be made lighter for them with values.** Each 100 off a guard's health
  saves the SMG and the Beam 2 to 4 s and costs the hammers' siege about a point: at 1200 it
  is 34.9%, and the Spear's fastest seed is 72.9 s.

**The way through the plates** (default variants; a hit of 40 or more is heavy):

| Family | Heaviest hit | A guard's plate (40) | His plate (385), never missing | In the fight, longest |
|---|---|---|---|---|
| Broadsword | 43.2 (the finisher) | 1 finisher | 9 heavy hits, 10.4 s | 18.1 s |
| Warhammer | 70.4 | 1 hit | 8, 5.4 s | 10.3 s |
| Spinblade | 41.6 (the finisher) | 1 finisher | 10, 8.5 s | 14.5 s |
| Greataxe | 75.6 | 1 hit | 8, 5.4 s | 9.5 s |
| Spear | 60.0 (the finisher) | 1 finisher | 7, 8.3 s | 13.0 s |
| Longbow | 50.0 | 1 arrow | 8, 7.4 s | 8.4 s |
| Shotgun | 55.0 | 1 shot | 7, 5.5 s | 7.6 s |
| Piercing Rifle | 42.0 | 1 shot | 10, 3.8 s | 4.2 s |
| Launcher | 60.0 | 1 shell | 7, 8.0 s | 9.3 s |
| Chain Gun | 60.0 | 1 hit | 7, 5.0 s | 5.8 s |
| SMG, Beam, Splitbow | 9, 5, 26: none heavy | 1 slam | 9 slams, 14.4 s | 17.5 to 17.8 s |

- **Every loadout has a way through.** One slam breaks the plate of every guard within its
  radius. Against his plate the slam is as fast as the Broadsword's finishers.
- **The Broadsword's phase is twice its count:** nine finishers are 10.4 s of swinging, and
  the phase is 18 s. The walk to him, three barrages to step out of, and a combo that starts
  again when a step takes him out of reach make the rest.

## Stop 3: bands (`--check`)

| Band | Value | Now |
|---|---|---|
| One hit of each of his attacks, and of the guard's arc | ≤ 25% of health | 14%, 23%, 23%; the guard 22% |
| Each tell beyond a step, a 0.25 s reaction and the answer | ≥ 0.05 s | 0.31 s (arc), 0.41 s (lane), 1.03 s (barrages); the guard 0.31 s |
| Each tell against a 0.35 s thumb | ≥ 0.12 s | the tightest: 0.21 s (his arc, the guard's arc) |
| A chain's second tell against a thumb | ≥ 0.12 s | 0.21 s |
| The window after each attack | ≥ 1 s | 1.52 to 2.40 s |
| Each knock: launch under the fence, flight and slide inside `knockIframes` | yes | 3 < 4; 0.35 s; 0.40, 0.40 and 0.19 s |
| Arc: a jump clears it; it reaches past where it starts | yes | yes; 11 > 9 |
| Lane: a jump clears it; a dash's i-frames outlast its passing | yes | yes; 0.25 s against 0.12 s |
| Barrage: a straight walk covers every circle's reach before they land | yes | 26 ≥ 17 studs |
| The most one instant can cost by the rules | ≤ two thirds of the bar | 23% |
| The guard is faster than he backs off | yes | 11 against 3 |
| The ground slam is a heavy hit | ≥ `heavyHit` | 45 against 40 |
| The slam breaks a guard's plate in | ≤ 2 slams | 1 |
| Standing still: down | inside 10 s, every seed | 9.0 s (8.8–9.2) |
| Standing still: the worst quarter second | ≤ 55% of the bar | 22% |
| Ignores the guard, chases him, after 90 s | plate whole, guard alive, down at least once, ≥ 3 bars lost | 100%; alive; down at 17.8 s; 780 health (6 bars) at the least |
| The same, reacting, after 90 s | plate whole, guard alive | 100%; alive |
| Reacting, each melee family, no ability: the kill | **75–115 s**, every seed | 77.4 to 98.1 s |
| Reacting, each melee family: hits taken | 0 | 0 |
| Reacting, every family, with or without its ability: hits of his or the guard's | 0 | 0 |
| Every family: the plate breaks in every seed | yes | yes; the slam for three of them |
| The siege's share of the kill, every melee family | **35% to 55%** | 37% to 50% |
| The plate phase, default melee and each slam family, every seed | **≤ 20 s** | 18.1 s; 17.5 to 17.8 s |
| The ground he gives in it, the same rows | **≤ 60 studs** | 44; 39 to 40 |
| Each ranged family that is not a bow, no ability: the kill, slowest seed | **≤ 150 s** | 77.5 to 146.7 s |
| The guard, as any kind (the Stop 1 bands) | all | all; its knock clears a second arc from 90 degrees, the floor |
| A kind's turn (several knocking attacks at once cost one) | ≤ 25% of health | the guard: 22% |

Each band was proved by a value that makes it fail. `--check` now makes 353 checks (239 before
Stop 3), on both interpreters.

**Four targets bind at once, and the room between them is small.**

| Target | Now | Room | What breaks it |
|---|---|---|---|
| Every melee kill ≥ 75 s | Spear, 77.4 s at the fastest of nine seeds | 2.4 s | `warlord.hp` 3300: 73.7 s |
| Every melee siege ≥ 35% | Greataxe 37.0%, Warhammer 37.1% (nine seeds) | 2 points | `guard.hp` 1200: 34.9% |
| Ranged, not a bow, ≤ 150 s | Beam, 146.7 s at the slowest | 3.3 s | `warlord.hp` 3900: 151.7 s |
| Plate phase ≤ 20 s | Broadsword, 18.6 s at the longest of nine seeds | 1.4 s | `plate` 450: 20.5 s |

More health for him helps the Spear's floor and the Beam breaks the ceiling; a heavier guard
helps the hammers' share and the Beam and the SMG pay it four times; a bigger plate would help
both floors and the Broadsword's phase passes 20 s. The Spear (reach 18, the fastest family on
any boss) and the Beam (the slowest gun on one target) are the two ends, and both are
weapon-number questions.

**Where the starting values missed.** With the lead's set nineteen of these bands fail: the
arc's thumb margin (0.11 s, alone and in a chain), the guard slower than the Warlord, standing
still (12.6 s), the chaser (not one down in 90 s), the reacting chaser (he broke half the
plate: the guard of 120 died under swings meant for the Warlord), the kill with every melee
family (44 to 61 s), the siege's share for four of them (26% to 34%), and the ground given in
the plate phase by the default sword and the three slam families (123 to 131 studs).

## Stop 3: the Colossus again

The Colossus's fodder now rise where the server puts them (on its facing, half a step off for
twelve), and its fights moved a little. Three seeds; Stop 2's numbers in brackets.

| Player | Weapon | Kill | With its ability |
|---|---|---|---|
| Stands still | | down at 8.6 s (8.6) | |
| Jumps the ring, sidesteps the charge | Broadsword | 74.7 s (73.5), 5 hits (4), no down | |
| Reacts to every tell | Broadsword | 76.3 s (76.3) | 76.3 s |
| Reacts to every tell | Warhammer | 83.0 s (81.7) | 67.7 s (67.7) |
| Reacts to every tell | Spinblade | 71.0 s (69.5) | 55.7 s (55.4) |
| Reacts to every tell | Greataxe | 75.3 s (79.2) | 69.3 s (71.0) |
| Reacts to every tell | Spear | 64.9 s (64.4) | 54.2 s (56.3) |
| Reacts, and the boss calls nothing | Broadsword | 73.5 s (73.5) | |

Over nine seeds the five melee families take 61.5 to 85.2 s (63.1 to 85.2 before), inside 60
to 90. The ranged families moved by 4 s at the most. One fodder lunge (8 damage) now lands on
the Splitbow player in one seed of two.

## Stop 3: rules these numbers hang on

- **Guarded from the spawn.** If the plate were open before the call, a rifleman at the pad
  would take over half of it (five shots of 42) in the two seconds before the guard rises.
- **He backs straight away, slowly, and the guard goes for the player.** The chaser's outcome
  hangs on both, as "His speed" says. If he held his ground, or the guard stayed at his side,
  a cleave meant for him would kill the guard.
- **One turn in two for the guard** (`perPlayer` 2) and ruling 18. Without the void, two arcs
  at once would cost 56, 43% of health.
- **The reel cancels a windup into its full recover.** If the cancelled barrage did not
  recover, the pause at the turn would be 1.5 s always, never 2.2 s.
- **Enraged, he closes to 9 and stands through his recovers.** If he kept backing off in the
  duel, the arc would never be thrown, and a melee player's 1.5 to 1.6 s windows would be
  spent walking.
- **A chained attack starts on the step the one before it ends.** As for the Colossus.
- **The combo starts again after `comboResetSeconds` out of reach.** It is why the Broadsword's
  nine finishers take 18 s and not 10. A longer reset would shorten its plate phase.
- **The slam is a sphere round the player's standing root,** 13.5 studs plus the body's radius
  to its centre. If it were measured on the floor, the Warlord (centre 4.5 studs up) would be
  in reach from 15.4 studs instead of 16.0.
- **The player's attacks go on while he moves.** If a step or a jump stopped his swing, every
  time here would grow by the time he spends dodging: 7 calm barrages and 20 duel attacks in
  the default fight.

## Stop 3: flags for the owner

- **The fight is 98 s with the default sword,** against the Colossus's 76 s: 26 s of guard,
  17 s of plate, 55 s of duel. A real player, who is hit and misses, takes longer.
- **The four targets leave little room** (the table above). No single value buys room: a
  guard of 1200 saves the SMG 8 s, and takes the hammers' siege to 34.9% and the Spear's
  fastest seed to 72.9 s.
- **With its ability the Spear wins in 72.8 s,** under the 75 s floor. The band is measured
  without abilities, as for the Colossus. The Spinblade with its ability takes 78.1 s.
- **The SMG spends half its fight on the guard** (56 s of 108) and the Beam over a third (55 s
  of 146). The model never casts an ability at the guard, so a real player with Overload Sweep
  or Mag Dump is quicker than this.
- **The bows:** the Longbow takes 159 s (147 s with its ability) and the Splitbow 208 s. Not
  fixed here.
- **The plate is counted in the Broadsword's finishers.** 385 is nine of them. Any change to
  the Broadsword's damage or its finisher moves the plate phase by a whole finisher (2 s).
- **He is slow: 3 studs a second, in the duel too.** He closes with the charge. A player who
  walks away from him is never caught on foot; the charge reaches 34 studs and the barrage 60.
- **A chaser with the default sword goes down every 15 s,** and a chaser who dodges gets
  nowhere. Both hold only while he backs off at 2 studs a second or more.
- **The duel is gentle on a player who keeps his distance.** Every melee family reaches him
  from outside his arc (11 studs), and the sim's player stands at the edge of his own reach, so
  the arc only threatens when the Warlord has walked in to 9. A player who hugs him meets it
  far more.
- **A barrage never lands on a still player while a knock of 6 studs has him:** the circle is
  aimed 1.6 s before. That is why the guard's knock is 26 here. The armoured elite's is still
  30.
- **The Spear has the least room under the Colossus's floor now:** 61.5 s at the fastest of
  nine seeds, against 60.
- **Not modelled:** crits, kill refunds, abilities on the guard, a melee player who also
  slams, cover, and the stairs.

# P5 — back into the missions

## Wave 1 — the Village crowd (Raider Woods)

Raider Woods now plays the range's crowd, not the C1 Humanoid waves. It uses the range's
weapons, enemy kinds and bosses, scaled by the mission's `crowd` block (contract:
`docs/INTERFACES.md` "P5 contracts" → "Wave 1 — crowd in a mission"). Every number below is
measured at the recommended power: gear 2/1 (Combat.json `debug.provingGear`), ascension 0,
the range's loadout (Broadsword + Longbow), solo, no Overdrive. At that gear the bar is
`Armory.MaxHp` = 100 + 35 + 10 = **145**. The player's HP loss is ×1.5 on melee (18 ÷ 12) and
×1 on ranged (tier 1).

Targets, from the contract and the lead's brief:
- a whole run pays 142,185 cash and 256 Timber, each within ±10%, and exactly 35 Valor. These
  are the C1 run's numbers at power 57. Boss summons count at the number `sim_range.py` reports;
- a player who reacts to every tell clears all ten waves in 10 to 15 minutes, breathers included;
- the Colossus takes 64 to 90 s with the default sword, and the Warlord 77 to 101 s. Neither may
  get there with a dull middle;
- no enemy hit is over 25% of the bar;
- a player standing still in a fodder wave goes down in 6 to 12 s;
- `regenShare` is close to the range's 10/130 a second.

## P5: how the numbers were measured

**`py tools/sim_range.py`** has a MISSION section, and `--check` adds eleven mission checks to
the 352 range checks. The range checks print the same lines as at Stop 3, to the character: the
mission view is a copy of the config, and the HP-loss scale is 1 wherever no view sets it. The
section reads the mission, `Armory.json`, `Combat.json` and the arena layout, so it copies no
number. `--mission-only` runs just this section. What it mirrors:
- **The scales (ruling 10).** Every body's HP is ×`hpScale`, summons included. Plates are
  ×`plateScale`. Every enemy hit is `max(round(damage × damageScale), 1)`, as `VitalsService`
  rounds it. Regen is `regenShare × MaxHealth` a second after `regenDelay`.
- **The tier (rulings 8 and 9).** Only the HP loss of the player's hits is scaled: a weapon by
  its slot, the ground slam as melee, an ability by its slot's ability scale. Heavy hits,
  plates, interrupts and armour read the tier-1 amount.
- **The queue and the director (rulings 15 to 18).** These follow `WaveService` as engineer B
  wrote it (checked against the file on 2026-10-12):
  - groups are queued in order, as bursts of up to `burst`;
  - a burst rises at the next `enemySpawns` point, round-robin over the run, from the first
    entry;
  - its grid has ceil(√n) columns across the line to the arena centre, with rows stepping inward;
  - a burst held by `maxAlive` places what it can and waits at the head of the queue;
  - the boss is placed outside the queue, at `boss.at`;
  - tempo comes from crowd kills against `spec.total / targetWaveSeconds`, held at 1 for
    `tempoWarmupSeconds`;
  - a wave that has finished spawning merges the next one in when `Combat.ShouldMerge` says so,
    never into or out of a boss wave;
  - at each clear, what the dead still had in the air (a lob, a shot, a ring) is cleared with
    them (`VitalsService.ClearThreats`), so nothing lands in the breather;
  - after each clear comes the `Combat.BreatherSeconds` breather, with no healing but regen;
  - solo, a down ends the run, unless the field is already clear ("a clear field wins", the
    lead's ruling): a down decided when the wave's last body is dead does not lose the run. The
    player stands up at that wave's boundary, and on wave 10 the run ends cleared. The reason: at
    near-zero ping a dying enemy's blow could end the run on an empty field, even on wave 10.
    Neither simulated player goes down on a clear field, so no number here depends on it.
- **The player of the whole run** reacts to every tell (the Stop 2 planner). He attacks with the
  Broadsword only, with no bow and no ability, and goes for the nearest body. While a boss lives
  he follows the boss-fight rules of Stop 2 and Stop 3. Between waves he stands where the last
  body fell. A second player, for information only, does the same but never dodges.
- **The bosses alone:** the Stop 2 and Stop 3 "reacts to every tell, attacks" player with the
  default sword. The boss stands at its `boss.at` and the player starts on the Village pad
  (0, 0). Three seeds each.

**`py tools/sim_combat.py`** gains the pure mirrors `Combat.CrowdWave`, `Combat.CrowdReward`,
`Combat.BurstInterval` and `Armory.DamageScale`, and four assertions (15 to 18). For both bosses
and the whole run it imports `sim_range.py`. A mission with a `crowd` block no longer plays the
C1 waves (the Wave 1 boot refuses every other kind), and its `targetWaveSeconds` was re-tuned.
So the legacy run assertions 3, 7, 8, 10, 11 and 14 skip it and say so. Assertion 4 (cash
against the era) reads the crowd run's cash. The economy, split and Mentor assertions (1, 2, 5,
6, 9, 12, 13) are unchanged and pass.

**The clear time is measured, not estimated.** The contract named a per-wave spawn-against-kill
estimate. A run through the real director gives a different answer, for three reasons:
- the tempo follows kills, which arrive in bunches as each burst reaches the player;
- the director merges waves when the tempo spikes;
- after every breather the window is empty, so the next wave's first bursts come at
  `tempoMin` (0.7), 1.43 times further apart.

An estimate at tempo 1 came to about 10 minutes. The measured run is the same bursts and the
same director, with kills from the same strike code as the DPS tables.

**Two interpreters.** `py tools/sim_*.py` runs Python 3.12, which the shebang selects; `py -`
runs 3.14. A ten-minute crowd run is chaotic: a last-digit float difference can move a merge.
Every gate passes on both. With `burst` 12 they differed by up to half a minute.

**Corrected in the L1 fix round (2026-10-13).** This paragraph said that at the shipped values
the two give the same clear times to 0.01 min. They do not: the other Python is a 32-bit build,
and the same seed differs by up to 0.08 min (the arena's seed 11: 10.19 and 10.27 min). The
gate is the 64-bit 3.12, and its numbers are the ones written here. See "Which Python" in the
L1 part.

**Corrected in L1 (2026-10-13).** The three seeds this part reports (11.5 to 11.8 min) did not
merge their early waves, and that was luck. Over twelve seeds the same simulator gives 10.1 to
11.8 min. See "L1: the Raider Arena" at the end of this file.

## P5: values

`src/shared/Config/Missions/1_Village.json`:

| Key | Was | Now | Why |
|---|---|---|---|
| `crowd.hpScale` | — | **1.5** | The melee `DamageScale` at gear 2/1 (18 ÷ 12). Every sword hit kills what it killed in the range, so both bosses are the range's fights to the second (76.8 s and 97.7 s, against 76.3 s and 97.7 s in the range). At 1.25 the Colossus falls in 63.3 s; at 1.6 the Warlord takes up to 106.3 s. |
| `crowd.plateScale` | — | **1** | Plates are counted in heavy hits (ruling 9), so 1 keeps the range's counts: one finisher per guard, nine for the Warlord. |
| `crowd.damageScale` | — | **1.12** | The bar grows from 130 to 145 (×1.115), so a bar that went down in so many hits in the range goes down in the same number here. The lunge is 9 (6.2%, as 8 of 130), and a still player needs 17 lunges in both. The ceiling is the Colossus's charge: 32 × 1.14 rounds to 36 (24.8%), and 1.15 gives 37 (25.5%). |
| `crowd.regenShare` | — | **0.077** | 10/130 = 0.0769: 11.2 a second on 145, so an empty bar is full 13 s after `regenDelay`, as in the range. |
| `crowd.maxAlive` | — | **60** | The reacting player never sees more than 26 to 30 alive. 60 holds a slower player's backlog and a party's larger waves, and it is under the crowd's 160. The lead reads the server's step time from the `[Perf]` line. |
| `crowd.burst` | — | **10** | 5 to 18 bursts a wave, each arriving as a block. With 12 the kills bunched, the director merged more and the clear fell to 10.6 min on one interpreter. 10 gives the same clears on both. At 4 a still player lasts 11.8 s; at 2, 12.6 s. |
| `crowd.burstSpacing` | — | **3.5** | Over the widest common body (fodder 2.6, slinger 2.4). A 10-body burst is 4 across (10.5 studs) and 3 rows deep. |
| `crowd.waves` | — | the table below | On `crowdSkeleton`. Groups alternate, so shooters, brutes and elites arrive inside a wave, not after the fodder. |
| `crowd.rewards` | — | the table below | Hits the C1 run's cash and Timber. Fodder pay only cash. |
| `crowd.eliteKind` | — | absent | Optional. The director adds no extra elite in Wave 1. |
| `targetWaveSeconds` | 30 | **45** | The contract re-tunes it for crowds. At 30 the reacting player clears in 10.4 to 10.7 min, under half a minute above the floor, while merges move a run by about ±0.5 min. At 45 he takes 11.5 to 11.8 min. A struggling player's tempo falls toward 0.7 and stretches a wave toward 45 ÷ 0.7 = 64 s, which I estimate puts his run near 15 min. At 120 the reacting player needs 23 min. |
| `targetMinutes` | 8 | **12** | The hub's Expedition panel shows it. The reacting player takes 11.5 to 11.8 min, and a real player longer. Its meaning is unchanged. |
| Colossus `boss.at` | — | **(0, 40)** | 40 studs from the pad, as the range's 42. The fight opens with the call when the player starts at the pad. |
| Warlord `boss.at` | — | **(0, 28)** | The range's 28 studs. He has 24 studs to the fence behind him and gives less ground than in the range; the fight takes the same 97.7 s. |
| `valor` | — | **10, 25** | 35, the C1 run's Valor. |

`Combat.json`: `crowdSkeleton` as the contract has it, and the debug keys `provingBoots`
"mission", `provingMission` "village", `provingStartWave` 1, `provingStartDelay` 3,
`provingGear` {2, 1} and `perfLogSeconds` 10. `director.runCapSeconds` goes from 1200 to
**1800** (the next part). Two keys were added for the server engineers after the review
("P5: keys added for the server" below). No kind or weapon number in `ProvingGrounds.json`
changed.

## P5: the run cap

`director.runCapSeconds` ends a run that will never finish: a party that has stopped fighting,
or one too weak to kill a boss. It is not a difficulty lever, so it must not cut off a run that
is only slow.

- **It was 1200 s since C1,** when a mission targeted 8 minutes: 2.5 times the target. Village
  now targets 12 minutes, so 1200 s was 1.67 times.
- **It is 1800 s now:** 2.5 times 12 minutes again.

| Player (reacts to every tell) | Clears in | At 1200 s | At 1800 s |
|---|---|---|---|
| Broadsword only | 11.5–11.8 min | clears | clears |
| Longbow only (the tier-1 bow of gear 2/1) | 19.2–20.0 min | one seed of two is cut off in wave 10, seconds before the Warlord falls | clears |

The bow-only player is the slowest one the simulator can still play to the end. His bosses
take 276 s (the Colossus, 270 to 281) and 227 s (the Warlord, 226 to 229), with no hit taken.

**What value would break which band:**
- **700 s or less** cuts the reacting sword player off in wave 10: two seeds of three at 700,
  all three at 690. That fails the clear band in `sim_range.py` and in `sim_combat.py` 17.
- **Under 900 s** the cap lies inside the 10–15 minute band itself.
- **Under 1440 s** (twice `targetMinutes`) fails the new gate in `sim_combat.py` 17: the cap
  must leave at least twice the time the hub panel promises. 1200 fails it at ×1.67, and 1430
  at ×1.99.

**The key is shared with the missions still on the C1 model** (Boomtown, Metropolis, Orbital).
None of their numbers moves: every legacy run, solo, at party 2 and 4 and under Overdrive,
already ended inside 1200 s. `--check` and the reports differ only in the cap's own label and
in assertion 17's line. Those missions are refused in the game until Wave 3. One cap will then
serve all four eras, so either each era keeps a target near 12 minutes or the cap becomes a
per-mission key, which the config's shape does not have today.

## P5: keys added for the server

Neither key is read by a simulator, and no band depends on either.

| Key | Value | What it is for |
|---|---|---|
| `Combat.json` `player.rescue.below` | **8** | A player who leaves the arena floor is put back on a spawn. It is not a down and costs nothing. `below` is how many studs under the floor the root must be. A standing root is about 3 above it, so 8 is 11 studs of falling: no jump, knock or slam on the floor reaches it. |
| `Combat.json` `player.rescue.outside` | **4** | How many studs past the floor's edge the root must be. The fence is 1 stud thick, so 4 is clear of a body leaning on it. Without the `rescue` block nobody is rescued. |
| `ProvingGrounds.json` `shooting.originSpeedSeconds` | **0.1** | The stretch over which the server measures a player's own speed for the claim slack: the fastest average over about that long within the last `originLagMaxSeconds` (0.3). It must be positive and no longer than that. |

**Why 0.1 and not 0.05** (engineer B's measurements of a 20-stud dash, read at server frames
1, 3 and 5):

| `originSpeedSeconds` | Frame 1 | Frame 3 | Frame 5 |
|---|---|---|---|
| 0.05 | 33 studs/s | 100 | 133 |
| 0.1 | 19 | 57 | 95 |

0.05 ramps twice as fast, so an honest dash gets its slack sooner. The price is that a shaking
root reads about twice as fast too, under the same cap (`Tuning.FastestMove`). 0.1 is the
slower ramp and the steadier reading. The simulator's player has no client and claims no
position, so this number moves nothing in `sim_range.py`.

**Mirroring `ClearThreats` moved no number.** The server now clears what is in the air at
every wave clear. With the same clear in the simulator's mission run, every printed line of
`sim_range.py --check` and `sim_combat.py --check` is the same as before, on both
interpreters: neither simulated player had anything land on him in a breather.

## P5: the waves (solo)

| Wave | Bodies | Bursts | Holds | Cash | Timber | Valor |
|---|---|---|---|---|---|---|
| 1 | 48 | 5 | 48 fodder | 2,880 | 0 | 0 |
| 2 | 72 | 8 | 72 fodder | 4,320 | 0 | 0 |
| 3 | 78 | 11 | 72 fodder, 6 slingers | 6,120 | 6 | 0 |
| 4 | 82 | 13 | 72 fodder, 4 brutes, 6 slingers | 10,920 | 22 | 0 |
| 5 | 1 | 0 | the Colossus (+48 fodder called) | 20,880 | 30 | 10 |
| 6 | 85 | 15 | 72 fodder, 4 marksmen, 4 lobbers, 3 slingers, 2 brutes | 10,420 | 19 | 0 |
| 7 | 108 | 15 | 96 fodder, 3 marksmen, 3 lobbers, 3 slingers, 3 brutes | 12,360 | 21 | 0 |
| 8 | 86 | 14 | 72 fodder, 6 armoured, 2 marksmen, 3 lobbers, 3 slingers | 15,970 | 38 | 0 |
| 9 | 127 | 18 | 108 fodder, 6 armoured, 3 marksmen, 3 lobbers, 3 brutes, 4 slingers | 22,380 | 52 | 0 |
| 10 | 1 | 0 | the Warlord (+4 guards called) | 38,000 | 70 | 25 |
| **Run** | 688 (+52 called) | | | **144,250** | **258** | **35** |

Rewards per kill, and each kind's share of the run's cash:

| Kind | Cash | Timber | Kills a run | Share of cash |
|---|---|---|---|---|
| fodder | 60 | 0 | 660 (48 called by the Colossus) | 27% |
| slinger | 300 | 1 | 25 | 5% |
| marksman | 350 | 1 | 12 | 3% |
| lobber | 350 | 1 | 13 | 3% |
| brute | 1,200 | 4 | 12 | 10% |
| armoured | 1,500 | 5 | 12 | 12% |
| guard | 2,000 | 5 | 4 | 6% |
| colossus | 18,000 | 30 | 1 | 12% |
| warlord | 30,000 | 50 | 1 | 21% |

- **The run pays 144,250 cash (+1.5%), 258 Timber (+0.8%) and 35 Valor.** The measured
  kills of the reacting player's three runs pay 144,410 and 258. They differ only in how many
  fodder the Colossus calls during a run.
- **Pay rises through the run.** Waves 1 to 4 pay 24k, the Colossus 21k, waves 6 to 9 61k and
  the Warlord 38k. A player who goes down in wave 7 keeps about 67k.
- **Cash per minute falls.** The C1 run paid 142,185 in 8:32. The crowd pays 144,250 in about
  12 minutes, about a quarter less a minute. The run is still under 1% of what the Village era
  costs at that point (assertion 4).
- **Calling is not a farm.** A Colossus left alive calls 12 fodder every 18 s: 40 cash a second,
  against the run's 205.

## P5: results (sim_range on the gate's Python, the 64-bit 3.12)

Enemy hits at the mission's scale, on a bar of 145:

| Kind | Attack | Range | Mission | Share |
|---|---|---|---|---|
| fodder | lunge | 8 | 9 | 6.2% |
| slinger | shot | 12 | 13 | 9.0% |
| marksman | line | 22 | 25 | 17.2% |
| lobber, Colossus and Warlord | lob | 18 | 20 | 13.8% |
| brute | lane | 28 | 31 | 21.4% |
| guard | arc | 28 | 31 | 21.4% |
| armoured, Warlord | arc | 30 | 34 | 23.4% |
| Warlord | lane | 30 | 34 | 23.4% |
| Colossus | ring | 26 | 29 | 20.0% |
| Colossus | lane | 32 | 36 | **24.8%** |

| Player | Outcome |
|---|---|
| Stands still in wave 1 | First lunge at 3.6 to 3.8 s (the first burst walks in from the rim). Down at **10.6 to 10.8 s** from the wave's start. |
| Reacts to every tell, the Colossus alone, Broadsword | **76.8 s** (75.4 to 77.7). No hit; 48 fodder called. |
| Reacts to every tell, the Warlord alone, Broadsword | **97.7 s** (96.9 to 98.4). No hit; the guard falls at 25.5 s and the plate breaks at 43.0 s. |
| Reacts to every tell, the whole run | **Cleared in 11.67, 11.81 and 11.53 min** (seeds 11, 23, 37). No down. One slinger shot (13) in one seed. Peak alive 26 to 30. Breathers 81 to 86 s in all. |
| The same, never dodging (information) | Down in wave 5, at 4.4 to 4.5 min, after 16 hits, mostly brute charges and the Colossus. |

The whole run, seed 11:

| Wave | Bodies | Start | Spawned by | Clear | Length |
|---|---|---|---|---|---|
| 1 | 48 | 0.0 | 37.2 | 39.4 | 39.4 s |
| 2 | 72 | 45.4 | 101.8 | 103.7 | 58.3 s |
| 3 | 78 | 116.3 | 169.8 | 172.2 | 55.9 s |
| 4 | 82 | 183.3 | 235.2 | 239.8 | 56.5 s |
| 5 | the Colossus | 245.8 | | 326.9 | 81.0 s |
| 6 | 85 | 340.9 | 390.9 | 395.5 | 54.6 s |
| 7 | 108 | 409.5 | 461.0 | 466.3 | 56.8 s |
| 8 + 9 (merged) | 86 + 127 | 472.3 | 577.2 | 588.0 | 115.8 s |
| 10 | the Warlord | 602.0 | | 700.1 | 98.1 s |

- **In the run the bosses take 81 s and 98 s.** The player starts each boss wave where the
  last body fell, not on the pad, so the Colossus's opening varies.
- **A wave is paced by its bursts, not by the sword.** The reacting Broadsword kills each burst
  as it arrives: 26 to 30 alive at the most, and almost nothing lands on him. A real player is
  slower, his tempo drops, and his waves stretch toward 64 s. The playtest asks Ben whether
  wave 9 is too easy, about right or too hard.
- **A player who never dodges does not see the Warlord.** Brute charges (31) and the Colossus
  put him down in wave 5. The pressure is real once brutes arrive, but only for a player who
  stops answering tells.

## P5: bands (`--check`)

| Band | Where | Value | Now | Fails at |
|---|---|---|---|---|
| Every kind the mission fields: one hit | sim_range | ≤ 25% of the bar | 24.8% (the Colossus's charge) | `damageScale` 1.15: 25.5% |
| `regenShare` close to 10/130 | sim_range | ±10% | 0.077 | 0.085 |
| Still in wave 1: down, every seed | sim_range | 6–12 s | 10.6–10.8 s | `burst` 2: 12.6 s; `damageScale` 0.9: 12.2–12.5 s |
| The Colossus alone, Broadsword, every seed | sim_range | 64–90 s | 75.4–77.7 s | `hpScale` 1.25: 63.3 s |
| The Warlord alone, Broadsword, every seed | sim_range | 77–101 s | 96.9–98.4 s | `hpScale` 1.6: 106.3 s |
| Both bosses: hits taken by the reacting player | sim_range | 0 | 0 | |
| The whole run, reacting, every seed | sim_range, sim_combat 17 | 10–15 min | 11.5–11.8 min | `burst` 20: 9.9 min; `targetWaveSeconds` 120: 23 min; `runCapSeconds` 700: cut off in wave 10 |
| `targetMinutes` in the band and within 1.5 min of the mean clear | sim_combat 17 | | 12 against 11.7 | |
| `runCapSeconds` against `targetMinutes` | sim_combat 17 | ≥ ×2 | ×2.5 (1800 s) | 1200: ×1.67; 1430: ×1.99 |
| `maxAlive` ≤ the crowd's 160 | sim_range, sim_combat 15 | | 60 | 200 |
| Skeleton, `#waves`, `bossWaves`, rewards for every kind that can be fielded, `boss.at` on the floor | sim_combat 15 | | all | a slinger in wave 2; wave 8 without armoured; `boss.at` (0, 52); no `guard` reward; `bossWaves` [5]; a swapped skeleton boss |
| Run cash and Timber; Valor | sim_combat 16 | ±10%; exact | +1.5%, +0.8%; 35 | fodder cash 80: +10.7%; armoured 8 Timber: +14.8% |
| The `CrowdWave` mirror against the config, party 1–4, Overdrive | sim_combat 18 | | 80 combinations | |

## P5: rules these numbers hang on

- **`hpScale` equals the melee scale, so the ranged slot falls behind.** At gear 2/1 the bow is
  a tier behind the sword, and every body has 1.5 times its range HP. The Longbow alone takes
  276 s on the mission's Colossus (142 s in the range) and 227 s on the Warlord (159 s). A
  bow-only run takes 19.2 to 20.0 min.
- **After a boss wave the breather is the longest, 14 s.** A boss wave's `spec.total` is 0, so
  the expected kill rate is 0 and `Combat.Tempo` returns `tempoMin`. So the breather after a
  boss wave is always `director.breatherMaxSeconds`, however fast the boss fell, and the next
  wave opens at `tempoMin`. Wave 5's is the one a run plays; wave 10 ends the run.
  - **Wave 1: intended.** It is a fixed rest after the boss, and no value was tuned against it.
  - **A question for Wave 3,** when every era has both bosses: should the rest after a boss be
    its own number, or follow how the boss fight went? Today it is a side effect of a guard
    against dividing by zero.
- **Mag Dump scales as an attack, every other ability as an ability.** Its bullets are ordinary
  attacks under a fire-rate buff, so they take the Ascension level's `damageMult`. Every other
  ability takes `abilityMult`. At Ascension 0 both are 1, so no Wave 1 number depends on it.
  At Ascension 1 it is ×2.0 against ×1.5, at Ascension 2 ×3.5 against ×2.0, and at Ascension 3
  **×6.0 against ×2.8**. The simulator follows the server. **A question for Wave 3:** is Mag
  Dump meant to out-scale the other twelve abilities, by more than twice at the top?
- **Merges come from bunched kills.** A burst dies together, the 10-second window spikes, and
  the tempo passes `mergeTempo` (1.25). A bigger `burst` merges more and shortens the run.
- **Rewards are whole numbers per kill** (`Combat.CrowdReward` rounds). Fodder therefore pay no
  Timber: a single Timber each would be 660 a run.
- **The summon count is the reacting player's.** A slower player lets the Colossus call more
  (a call tops up every 18 s), and each extra fodder pays 60.

## P5: flags for the owner

- **The sim's player is ideal.** He reacts in 0.25 s and his weapon never misses, so almost
  nothing hits him in a whole run. A real player will be hit and will be slower. The 10–15
  minute band is met at 11.5–11.8 min, which leaves room above for that.
- **Legacy assertions retired for Village.** 3, 7, 8, 10, 11 and 14 now skip a crowd mission.
  With `targetWaveSeconds` 45 the C1 model of Village clears 8 of 10 waves and pays 52,945,
  but that model no longer runs in the game. Boomtown, Metropolis and Orbital are judged by it
  until Wave 3.
- **Party scaling is untested in play.** With `countPerExtraPlayer` 0.6, four players make wave
  9 hold 354 bodies, and `maxAlive` 60 queues the rest. That is Wave 4's check.
- **Overdrive is wired and not tuned.** The mirror shows it scales HP and damage, not plates or
  regen.
- **Bows on bosses** are slower still in a mission (see the rules above). It is the open P3
  question.

# L1 — Forest Road in grey

A mission is now a **level**: a road, flat camps along it whose gates close for the fight, a
boss in the last camp, and three difficulties the player picks (contract: `docs/INTERFACES.md`
"L1 contracts"; plan: `docs/MISSIONS_DESIGN.md` §5, §6, §12). This part covers Forest Road, the
first level, built in grey blocks from `Layouts/Levels/ForestRoad.json`, and what moved for the
ten-wave Village arena, which stays playable as the level "Raider Arena".

Normal is measured as in P5: gear melee 2 / ranged 1 (a bar of 145), no Ascension, the
Broadsword, solo. Hard and Brutal are measured at their recommended gear, which is the Studio
gear preset of their `recommendedTier`: melee 4 / ranged 4 (a bar of 230) and melee 6 / ranged 6
(a bar of 380). "One preset below" is the preset before it: 2/1 for Hard, 4/4 for Brutal.

**This part was revised in the L1 fix round (2026-10-13 and 14, `docs/prompts/l1-fix-round.md`,
part E).** What moved is marked "fix round". In short: cover in the camps is low, the lookout
is 2 studs higher and the fences 1 lower, the signs stand on ground, a fall is short, Hard and
Brutal keep their share of the larger bars, and the bands now include players who can be hit.
The enemies of every camp are as they were before the round.

Targets, from the contract and the lead's rulings in the fix round:
- Normal, a first clear: 6 to 8 minutes from the start point to the Colossus's fall, walking
  and countdowns included;
- the Colossus in camp C: 64 to 90 s (Ben called about 76 s "about right");
- no enemy hit over 25% of the bar; standing still in camp A, down in 6 to 12 s from the gates'
  closing;
- a Normal clear pays 87,000 cash and 155 Timber, each within ±10%, and exactly 10 Valor;
- Hard and Brutal pay ×2 and ×4 per kill, and ×2 to ×3 and ×4 to ×6 for the whole clear;
- Hard and Brutal are clearable at their recommended gear (6 to 9 minutes, the Colossus in 64
  to 100 s, no hit over 30% of that gear's bar, and a player with a human's reaction clears
  without going down);
- Hard and Brutal are **clearly beyond the gear below**: one preset below, the human either
  goes down or is much slower, and the Colossus alone outlasts a time. An under-geared player
  who plays well and clears slowly is fine.

## L1: how the numbers were measured

**`py tools/check_levels.py`** proves the layouts on paper, because nobody sees a level in
Studio before the owner does. It walks each level's `route` over the layout's boxes as a player
with one jump would, checks every gate of the contract's constraint table, and prints a plan
and a side view of each level in plain characters. It makes 123 checks (109 before the fix
round). Each gate was proved by a layout or config broken for it: 68 such changes in the first
pass, and 49 more for the gates the fix round added or changed. Every one is caught.

**`py tools/sim_range.py`** plays a level instead of a mission. `LevelRun` mirrors
`StageFlow.Advance` row for row and fights each camp on that camp's own floor: its rectangle,
its spawn points, bursts whose rows step toward its centre.
- The player walks the route at walk speed. A camp triggers when his root is inside its whole
  fenced rectangle, the floor grown by `levels.fenceThickness`, edges included (fix round,
  ruling 1; it was the floor inset by 4 studs). `levels.gateSeconds` later the gates close.
- At the close a fighter outside the floor inset by `levels.closeInset` is put on the entry
  point; the tempo goes back to 1, the kill stamps are cleared, and the director's warmup
  counts from that moment. For `levels.closeGraceSeconds` after it the same question is asked
  again, once per fighter (fix round). The simulator's player is never outside in that window:
  in every gated run the grace moved him 0 times.
- One spawn cursor runs over the whole run, round-robin over each camp's own points.
- **The director keeps its tempo for as long as a camp is closed, through its breathers as
  well as its fights** (fix round: P5's behaviour, which L1 had lost). On every such tick,
  before the spawns and before `Advance` is asked, kill stamps older than the window go and
  the tempo is computed against the wave queued last; through a breather that is still the
  wave just cleared. The tick's merge, the breather's length at a clear and a finished burst's
  interval all read that one value.
- Between two waves of a camp comes the stage's `breatherSeconds`, or the director's breather
  when the stage names none; waves merge only in a stage with `merge`.
- A countdown that ends with nobody on his feet arms the camp again; nothing closes and
  nothing spawns (fix round). It cannot happen to the simulator's player, who is never hit on
  the road.
- Only a checkpoint pays: a camp's clear banks the pool, and a stage with `bankEachWave` banks
  at every wave clear; whatever else ends the run drops what was not banked.
- A level with no run cap of its own runs under the director's.

Two things are the simulator's own choice. During a camp's countdown the reacting player walks
on to the camp's middle, and the player who stands still stops where he triggered it (now the
fence line, so the close puts him on the entry point). After a camp he walks from where its
last body fell to its exit and on.

**Four players (fix round).** The first is the one every earlier band used.

| Player | What he does | What his runs can tell |
|---|---|---|
| Reacting (`mission`) | moves 0.25 s after a tell shows; his planner tries every step, jump and dash against the server's exact shapes, with every threat known | how long a level is. He takes no hit, so nothing about how hard it hits |
| Human's reaction (`human`) | the same player and the same planner, but he moves **0.55 s** after a tell shows | whether slingers at a difficulty's damage fit a gear: see below |
| Never dodges (`rampage`) | attacks the nearest, answers no tell | the floor: he must not clear |
| Stands still (`stand`) | nothing | the first camp's opening |

**The human is only ever hit by slingers' shots at close range.** In every run measured, at
every difficulty and gear, each hit he took was a slinger's shot fired from under about 17
studs: at 28 studs a second it lands inside his 0.55 s. He still cuts the fodder down before
they lunge, dashes out of an elite's swing, sidesteps the brutes, is never where a marksman's
line locked, and takes nothing from the boss. So his gates measure **slingers times
`damageScale`, and nothing else**. They do not say that a level's lunges, swings, charges or
boss are right for a gear. **A better human model is owed before the real balance pass (L4):**
one that is slow to answer several threats at once, that sometimes misreads a tell, and that
is hit by melee.

For information the report also plays the default ranged family, the Longbow, on its own.

**`py tools/sim_combat.py`** mirrors `Combat.CampWave`, `Combat.CampReward` and
`Combat.BurstSeconds`, and has three L1 assertions: the Raider Arena's adapter gives the
mission's own waves (19), the level gates (20), and what each difficulty pays (21).

**`py tools/check_stage_mirror.py` (new in the fix round)** runs the real `Combat.luau`,
`StageFlow.luau` and `LevelGeometry.luau` under the Luau interpreter on the shipped files and
compares them, value by value, with the Python mirrors the two simulators measure on:
- `Resolve`, `Validate`, `Plan`, `BurstPoint` and `BossPoint` for every level and difficulty;
- `CampWave` and `CampReward` for every wave, difficulty and party of 1 to 4;
- `BurstSeconds`, `Tempo`, `ShouldMerge` and `BreatherSeconds` on grids;
- 28 scripted runs through `Advance`, `Skip` and `Force`, tick for tick, against
  `LevelRun.advance`, `skip` and `force`: clean clears, a down, the run cap, a countdown that
  ends with nobody on his feet, and the Studio levers pressed on the road, in a countdown, in a
  fight and in a breather;
- on every tick of those runs, `Directs` and `StillClosing`; at each run's end, `EarnsStar`.

It makes about 5,600 comparisons in under a second, and **it is green: nothing is expected to
differ.** It was proved with 53 changes, 33 to the Luau alone and 20 to the Python alone: all
are caught. The Studio levers are mirrored only to be compared: the simulator's own runs never
skip. The pool a skip empties is `WaveService.dropPool`, which no tool can load; the simulator's
copy of it is four lines, checked by reading.

**Seeds.** The gates use the three seeds of P5. Forest Road was also run over twelve seeds, and
those spreads are given beside the three-seed numbers.

**Which Python (fix round).** The gate is `py tools/sim_range.py --check`. The launcher follows
the file's first line to the **64-bit Python 3.12**, and every number in this part is that
build's. The machine's other Python is 3.14, a 32-bit build: `py -`, a script with no such
line, and whatever imports the simulator from one all run on it. A level run is chaotic, and a
sum whose last digit rounds differently can move a kill by a frame. The same seed then differs
between the two builds:
- by up to 0.08 min in a clear (the arena's seed 11: 10.19 and 10.27 min; Forest Road at most
  0.06 min);
- by up to 4.2 s in a boss fight inside a run.

Every band passes on both. `--check` prints the interpreter it ran on and says when it is not
the gate's. The first pass of this part said the two agree "to within 0.1 min", and the P5 part
said "to 0.01 min": the second was wrong.

## L1: the layout

North is up; one character is 4 studs across and 8 down. `=` road, `%` the lookout's ledge,
`~` water, `.` camp floor, `#` fence, `|` gate, `x` spawn point, `o` cover, `c` checkpoint,
`?` secret site, `i` sign, `S` start, `B` the boss's spot.

```
  x -272      -232      -192      -152      -112      -72       -32       8         48        88        128       168       208       248
 -88                                                                              ##########################
 -80                                                                              #.........x.......x......#         #####################
 -72                                                    ################          #...oooo...........ooo...#         #.......x.....oooo..#
 -64                                           %%%%%%   #.oo...x.......#          #....oo............ooo...#         #.............ooooo.#
 -56                                        =i=%%??%%   #............x.#          #......................x.#         #.............oooo..#
 -48                            ===============%%%%%%===|.............c|==========|.......................c|=========|..................c|====
 -40                            ========================|.......A....x.|==========|............B...........|=========|.........C...B.....|====
 -32                     ~~~~~~ ========================|..............|==========|........................|=========|...................|====
 -24                     ~~~~~~ =====                   #..............#          #........................#  ===    #................x..#
 -16 =====i              ~~~~~~ =====                   #.oo...x.....x.#          #....oo............ooo.x.#  ====i  #...................#
  -8 =====i========  ================                   ################          #...oooo...........ooo...#  ???    #.......x........x..#
   0 ===S==========  ================                                             #.........x.......x......#  ???    #####################
   8 ======              ~~~~~=i=                                                 ##########################  ???
  16                     ~~~~~~==
  24 to 48               ~~~~~~              (the creek runs on south)
  56                 ~~~~~~~~~~~~~~
  64                 ~~~~~~~~~~~~~~
  72                 ~~~~~????~~~~~          (the island shrine in its pond)
  80                 ~~~~~????~~~~~
  88                 ~~~~~~~~~~~~~~
```

The route from the side, one column per 4 studs walked and one row per 4 studs of height
(`_` the gap, `^` a climb, `.` inside a camp):

```
  12                                                                                                                    ^=====.................
   8                                             ^==============............==============......................========#######################
   4                                             ##############################################################################################
   0 ==========   ===============================##############################################################################################
```

| Piece | Number | Why |
|---|---|---|
| Route | 549 studs: 308 on the road, 205 through the camps, 36 on the camps' aprons | Inside the contract's 500–600. |
| Road | 16 wide everywhere | Four studs over the 12 the contract asks; a gate is 16 wide too. |
| The gap | 12 studs, 42 studs from the start, landing level | One jump carries 17.1 studs, so the take-off has 5 studs of room. It comes first so that a fall costs a 2-second walk back from the start, not the whole road. |
| The creek | a bridge of road over water 1 stud lower, 20 studs wide, with a pond to the south | The road stays continuous. The island shrine stands in the pond, 82 studs south of the road. Water is solid in L1. |
| The first ledge | 8 studs up, 50 studs before camp A's gate | One jump (18) clears it. It puts camps A and B on a floor at height 8, which tests a crowd floor that is not at height 0. |
| The second ledge | 4 studs up, between B and C | Camp C stands at height 12: a second floor height. |
| The lookout (fix round) | a ledge whose top is at 34: **26** studs above the road beside it, 15 studs off the route. It was 24 | A body steps up about 2 studs and the air dash holds its height, so every "needs the double jump" test now gives a single jump 3 studs more: 18 + 3 = 21. The ledge must stay under jump plus double jump less 4, which is 26. At 24 a jump from camp A's fence top reached it. |
| Camp fences (fix round) | **4** studs high. They were 5 | A player may stand on a fence while its camp is open. From a fence top at 12 a jump and the step-up reach 33, one stud under the lookout. At 5 they reach 34. |
| Cover in the camps (fix round) | every block **3.5** studs tall. They were 5 in A, 7 in B and 12 in C | Ruling 3. A ground attack misses feet more than its `height` above the floor. The lowest each camp fields is 5 in A (the fodder's lunge) and 4 in B and C (the lobber's lob; the Colossus's ring and barrage). Cover keeps half a stud under it, so a player on a block is still hit. |
| The invisible wall (fix round) | its inner face is the floor's edge; 8 studs deep | Ruling 2. In a closed camp nobody stands on a fence, which is why a fence is not held to the cover's height. |
| The cache | a marked block at the end of a 26-stud spur off the B-to-C road | "Off camp B" in the owner's picture. With the wall starting at the floor's edge, the spur is 2 studs past the outer face of camp B's wall (it was 1), and the cache's sign pad is 2 past camp C's. Nothing stands beside a camp. |
| The three signs (fix round) | each on a pad of road: 10 × 10 beside the lookout's ledge, 8 × 8 beside the cache spur, 10 × 10 on the creek's south bank | They floated over the void. A sign's block is 6 × 6, and the gate now asks that all of it stands on solid ground at its own height. |
| Camp entry and exit points | 6 studs inside each gate | Clear of `closeInset` (2) with room to spare; `StageFlow.Plan` refuses a level whose entry is not. |
| Spawn points | 5 in A, 6 in B, 4 in C, 31 studs or more from the entry | They sit 6 to 13 studs inside the fence, on the sides and the far end, never by the entry. |
| `killY` (fix round) | **−13** in Forest Road and **−12** in the lobby. Both were −40 | 12 studs under the lowest ground (the creek's top at −1; the lobby's floor at 0). A fall from the road takes 0.40 s, not 0.66 s, and from camp C's floor 0.53 s. The gate: 8 to 16 under the lowest standable surface, and under every Part's bottom. |
| Ground depth (fix round) | the creek, the pond and the lobby's floor are 4 studs deep. They were 2 | `levels.floorThickness`: a rescued faller arrives fast, and thin ground lets him through. The tops did not move. Every other ground block was 4 deep or more already. |
| The lobby | 48 × 48 at z −340 | 224 studs from Forest Road's bounds and 252 from the arena's. |
| Parts | 73 | Of `levels.maxParts` 600. Three more than before: the sign pads. |

`Combat.json levels`: `gateSeconds` 3, `triggerBelow` 4, `triggerHeight` 30, `closeInset` 2,
`closeGraceSeconds` 0.5, `crowdCeiling` 200, `floorThickness` 4, `startSpacing` 4,
`startCooldownSeconds` 2, `fenceThickness` 1, `boxMargin` 40, `maxParts` 600, `checkpointSize`
[2, 10, 2]. `triggerInset` is gone. `debug.gearPresets` are 2/1, 4/4 and 6/6 (they were 2/1,
4/3 and 6/5). `coop.returnGroupSeconds` 15 → 10 (the summary's length). `Expeditions.json
sign.size` [6, 4, 6].

**The Raider Arena's cover is not held to this.** Its tallest boulder is 4 studs, and its
lowest ground attack is the Colossus's ring at 4: a body on that boulder is still hit, with no
margin at all. The arena's numbers are frozen until L4; `check_levels.py` prints this as a note.

## L1: values

`Config/Levels/1_ForestRoad.json`:

| Key | Normal | Hard | Brutal | Why |
|---|---|---|---|---|
| `hpScale` | 1.5 | 5.2 | 11.5 | Normal is the arena's: the melee scale at 2/1, so the Colossus is the range's fight. Hard and Brutal sit 4% and 6% over the melee scale of their recommended tier (×5 and ×10.83), so the same fight takes 79 s and 81 s there. Unchanged: the presets moved the ranged tier only. |
| `damageScale` | 1.12 | **2.0** (was 1.8) | **3.35** (was 3.1) | Normal is the arena's. The bars of the recommended gear grew with the presets (210 → 230, 350 → 380), so the same share of the bar needs a larger scale: the Colossus's charge is 27.8% and 28.2% of the bar, as it was at 4/3 and 6/5 (27.6% and 28.3%). The ceiling is 30%: 2.17 on Hard and 3.57 on Brutal. |
| `plateScale` | 1 | 1 | 1 | Plates are counted in heavy hits, whatever the tier. |
| `countMult` | 1 | 1.2 | 1.35 | With the Hard-only groups, the bodies are ×1.21 and ×1.37 of Normal. Higher values take the whole clear's pay over ×3 and ×6. |
| `rewardMult` | 1 | 2 | 4 | The contract's. Valor is 10, 20, 40. |
| `recommendedTier` | 2 | 4 | 6 | The contract's placeholders. Each is the melee tier of a gear preset, which `check_levels.py` now gates. |

| Key | Value | Why |
|---|---|---|
| `crowd.regenShare` | 0.077 | The arena's and the range's: 10/130 of the bar a second. |
| `crowd.burst`, `burstSpacing` | 8, 3.5 | Camp A holds 16 at once, so a burst is half of that. |
| `maxAlive` | A 16, B 40, C 30 | Under each floor's area ÷ 200 (18, 47, 32). The reacting player never sees more than 15 alive on Normal and 22 on Brutal. |
| `targetWaveSeconds` | A 36, B 36, C 34 | Camp B's length is set by killing brutes and chasing shooters, not by this. A's and C's follow it. |
| `breatherSeconds` | 3 in every camp | A short beat between two waves of one camp. |
| `targetMinutes` | 7 | The mean measured clear is 6.6 min; a real player is slower. |
| `runCapSeconds` | 1050 | 2.5 times the target, the ratio P5 settled on. It is not a difficulty lever (see "the run cap" in the P5 part), and the fix round did not use it as one. |
| Colossus `boss.at` | (14, 0) from camp C's centre | In front of where the chief's tent stands, 48 studs from the entry. |

**The waves.** Counts are Normal's. *Hard* marks a group only Hard and Brutal field.

| Camp | Wave | Groups, in order |
|---|---|---|
| A, Pickets | 1 | 16 fodder, *Hard: 2 slingers*, 8 fodder |
| | 2 | 8 fodder, *Hard: 1 armoured*, 3 slingers, 16 fodder |
| | 3 | 16 fodder, *Hard: 2 armoured*, 4 slingers, 8 fodder |
| B, Main Camp | 1 | 16 fodder, 3 slingers, 16 fodder |
| | 2 | 16 fodder, 2 brutes, 3 slingers, 16 fodder |
| | 3 | 16 fodder, 2 brutes, 1 lobber, 4 slingers, *Hard: 2 marksmen*, 16 fodder |
| | 4 | 16 fodder, 3 brutes, 4 slingers, *Hard: 3 armoured*, *Hard: 2 marksmen*, 16 fodder |
| C, The Chief's Clearing | 1 | 16 fodder, 2 brutes, *Hard: 2 armoured*, 16 fodder, 1 brute |
| | 2 | the Colossus (it calls 48 fodder in the fight) |

This is the owner's plan: A is fodder and slingers; B is fodder, slingers, brutes and one
lobber; Hard adds marksmen and plated elites. Camp C's first wave, the chief's guard, is mine.

**Tried in the fix round and taken back (the lead's ruling).** A first gate said that the
human must go DOWN one preset below. At the damage ceiling 3 seeds of 12 still cleared Hard at
2/1, so I put 26 slingers in Hard's Pickets (7 on Normal) and cut Brutal's `countMult` to 1.2
for its pay. That made the gate pass, 20 seeds of 20 on Hard. It also bent the level to a quirk
of the simulated human, who is hit by nothing but slingers. The lead ruled the gate too strict,
not the level too soft: the roster and Brutal's `countMult` are as they were, and the gate is
now "goes down, or is much slower" (see the bands).

## L1: who fits where

The lead asked that every ranged kind be checked against its camp's short side. The contract's
gate (a kind's `bandMin` at most 0.45 of the short side) passes for all of them: slingers (18)
in A (27), and slingers, the lobber (22) and marksmen (28) in B (42). Marksmen are kept out of
A, and no ranged kind stands in C. The gate is not the whole answer, so the first pass measured
what the shooters do in the reacting player's runs. **These rows were not measured again in the
fix round** (Hard was then at gear 4/3):

| Floor | Kind | Lives | Inside its `bandMin` | Jammed on the fence |
|---|---|---|---|---|
| Raider Arena, 110 × 110 | slinger | 13.8 s | 18% of its life | 2% |
| | marksman | 15.3 s | 22% | 4% |
| | lobber | 12.8 s | 31% | 5% |
| Camp B, 100 × 94, Normal | slinger | 10.7 s | 23% | 4% |
| | lobber | 16.6 s | 11% | 1% |
| Camp B, Hard at 4/3 | marksman | 18.2 s | 16% | 3% |
| Camp A, 60 × 60, Normal | slinger | **0.9 s** | 100% | **33%** |
| Camp A, Hard at 4/3 | slinger | 2.4 s | 57% | 18% |

- **Camp B has room.** Its shooters behave as in the arena.
- **Order matters more than size.** With the lobber's group after the fodder it lived 1.9 s:
  it arrived alone and the player walked straight at it. Placed right after the brutes it
  lives 16.6 s, because the player is busy. The marksmen on Hard are placed the same way.
- **Camp A is too small for a shooter to keep its distance,** and no allowed size changes
  that. From the middle of a 60-stud yard every spawn point is within 28 studs, and the sword
  reaches 12.8, so a slinger is under a second from a player who walks at it.
- **What I chose:** camp A stays 60 × 60 with the owner's mix. Its slingers are sentries at the
  fence that a player runs down, which suits the first yard of the first level. On Hard they
  come behind the plated elites and live nearly three times as long, and at gear 2/1 they are
  what puts a human down there, in 7 seeds of 12. The playtest should ask whether camp A is
  too easy.

## L1: results

Three seeds, with twelve seeds in brackets where they were run.

| | Normal at 2/1 | Hard at 4/4 | Brutal at 6/6 |
|---|---|---|---|
| The reacting player's clear | **6.30–6.79 min** (the same over twelve) | 7.52–7.68 min (7.20–7.68) | 7.38–7.53 min (7.37–7.65) |
| Hits he took | 0 | 0 | 0 |
| **The human's clear** | 6.50–6.69 min (6.47–6.69) | 7.26–7.29 min (7.21–7.33) | 7.15–7.26 min (7.15–7.38) |
| Hits the human took, all slingers' shots | 6–8 (5–9), 65–117 damage | 5–15 (5–17), 120–408 damage | 9–15 (7–15), 280–600 damage |
| Times the human went down | 0 in twelve seeds | 0 in twelve seeds | 0 in twelve seeds |
| The player who never dodges | down in the Main Camp at 3.7–4.4 min | down in the Main Camp at 3.4 min | down in the Main Camp at 3.3–3.4 min |
| The Colossus alone in camp C | **76.3 s** (75.0–77.6) | 79.3 s (77.9–80.1) | 80.8 s (79.5–81.6) |
| The Colossus in the run | 74.8–75.8 s (73.9–76.0) | 77.8–79.9 s (75.4–79.9) | 77.8–80.6 s (76.4–81.9) |
| The worst hit | 36 = 24.8% | 64 = 27.8% | 107 = 28.2% |
| Most bodies alive at once | 14 (15) | 21 (21) | 19 (22) |
| Bodies killed | 313 | 380 | 430 |

A Normal run, seed 11:

| Part | Gates close | Cleared | Length | Waves |
|---|---|---|---|---|
| The road to camp A | | | 11.5 s + 3 s countdown | the gap, the creek, the ledge |
| A, Pickets | 14.5 s | 107.6 s | 93.1 s | 24 in 26.4 s, 27 in 32.0 s, 28 in 28.7 s |
| B, Main Camp | 114.0 s | 257.7 s | 143.6 s | 35 in 34.1 s, 37 in 40.5 s, 39 in 30.1 s, 39 in 30.0 s |
| C, The Chief's Clearing | 264.7 s | 378.3 s | 113.6 s | the guard, 35 in 35.5 s; the Colossus in 75.1 s |

- **The owner's timeline was 1.5, 2.5 and 2 minutes for the three camps.** Over twelve seeds
  the camps take 92–93 s, 144–174 s and 112–114 s. Camp B is most of the spread.
- **On Hard** the camps take 118–119 s, 171–196 s and 114–119 s.
- **The walking is 501 studs in all** (the road, into each camp's middle, back to each exit):
  25 s, plus 9 s of countdowns. The countdown now starts at the fence line, 5 studs earlier.
- **Standing still in camp A:** first hit at 2.5 s, down at **9.8 s** from the gates' closing
  (9.8–9.9 s over twelve seeds).
- **A player who never dodges, Normal:** down in the Main Camp, to brute charges. He keeps
  camp A's 10,700 cash and loses the 20,200 to 24,900 he had earned in B: the checkpoint rule.

**One preset below, and against gear 2/1:**

| | Hard | Brutal |
|---|---|---|
| One preset below | 2/1, a bar of 145, melee scale ×1.5 against ×5 | 4/4, a bar of 230, melee scale ×5 against ×10.83 |
| **The human there, three seeds** | **down** in the Pickets at 1.7 and 2.4 min; one seed clears in 14.73 min, **×2.02** of his slowest clear at 4/4 | **down** in the Pickets at 2.1 and 2.2 min; one seed clears in 11.20 min, **×1.54** of his slowest clear at 6/6 |
| The same, twelve seeds | 8 down (7 in the Pickets, 1 in the Main Camp); 4 clear in 14.7–15.2 min, ×2.0–2.1 | 7 down (5 in the Pickets, 2 in the Main Camp); 5 clear in 11.0–11.3 min, ×1.5 |
| **The Colossus alone there** | not killed inside 240 s; 31% of its health left (332 s when watched to the end) | 196.6 s (196.5–202.9 over three seeds) |
| The reacting player there | clears in 15.3–15.8 min with no hit | clears in 11.4–11.7 min with no hit |
| At 2/1: the worst hit on a bar of 145 | 64 = 44% | 107 = 74% |
| At 2/1: the Colossus alone | as above | not killed inside 240 s; 79% left |
| At 2/1: the player who never dodges | down in camp A at 1.3–1.4 min | down in camp A at 0.6–0.7 min |

**Skill beats gear, and the gate says so on purpose.** The reacting player clears Hard at 2/1
in 15.3 to 15.8 minutes without taking a hit; with `damageScale` 0.01 his run is the same run
to the frame. No band on his runs can see how hard a difficulty hits. A human who plays well
at 2/1 can also clear Hard: one seed in three does, in twice the time. That is fine, by the
lead's ruling: at 2/1 everything on Hard takes about 3.3 times as long to kill.

**The Longbow on its own, for information** (the reacting player, the bow of that gear's
ranged tier, no sword):

| | Normal at 2/1 | Hard at 4/4 | Brutal at 6/6 |
|---|---|---|---|
| The Pickets, gates' closing to clear | 100–106 s (the sword: 93 s) | 128–129 s (119 s) | 131 s (120 s) |
| The Colossus alone | not killed inside 240 s; 9% of its health left | 167 s (161–173) | 143 s (139–148) |
| Hits taken in either | 0 | 0 | 0 |

A camp's basic mix costs a bow about a tenth more time. The boss costs it twice the sword's
time at tiers 4 and 6 and more than three times at 2/1, where the bow is tier 1. That is the
open P3 question about bows and bosses, unchanged.

## L1: rewards

| Kind | Cash | Timber | | Normal | Hard | Brutal |
|---|---|---|---|---|---|---|
| fodder | 100 | 0 | kills | 280 | 325 | 367 |
| slinger | 500 | 1 | | 21 | 29 | 30 |
| brute | 2,000 | 6 | | 10 | 11 | 14 |
| lobber | 700 | 4 | | 1 | 1 | 1 |
| marksman | 600 | 1 | | 0 | 4 | 6 |
| armoured | 1,200 | 2 | | 0 | 9 | 11 |
| colossus | 29,000 | 70 | | 1 | 1 | 1 |

| | Normal | Hard | Brutal |
|---|---|---|---|
| Camp A | 10,700 cash, 7 Timber | 35,600, 34 | 82,800, 80 |
| Camp B | 34,500, 60 | 96,200, 164 | 222,800, 384 |
| Camp C | 43,000, 88, 10 Valor | 92,000, 184, 20 Valor | 199,200, 400, 40 Valor |
| **The clear** | **88,200 cash, 155 Timber, 10 Valor** | **223,800, 382, 20** | **504,800, 864, 40** |
| Against Normal | +1.4% and +0.0% of the targets | ×2.54 cash, ×2.46 Timber | ×5.72 cash, ×5.57 Timber |
| A slow clear, one preset below (measured) | | 255,000–259,800: ×2.89–×2.95 | 538,400: ×6.10 |

- The fodder count includes the 48 the Colossus calls in the reacting player's fight, at every
  difficulty. Every cleared run banked exactly these totals, which assertion 21 now checks
  against the file, kill by kind.
- **A slow clear banks more than the band, and that is fine (fix round, item 11).** The
  review measured ×6.10 for Brutal at gear 4/3, over the ×6 ceiling; at 4/4 it is ×6.10 still.
  The cause is the boss: a weaker player's fight lasts longer, and the Colossus calls 12 more
  fodder every 18 s (124 at 4/4 against 48 at 6/6). The band is the recommended gear's clear.
  What matters is that under-gearing never pays better, and it does not: by the minute the
  slow clear pays 16,400–16,700 against 29,500 on Hard, and 46,200–47,200 against 67,700 on
  Brutal. `sim_range.py` now holds that as a band.
- **Standing in front of the boss to farm its calls never pays.** The calls are worth 67, 133
  and 267 cash a second; the clear is worth 223, 491 and 1,128. Assertion 21 keeps the calls
  under half of the clear's rate.
- **Where the cash is banked on Normal:** 12% in camp A, 39% in B and 49% in C. A player who
  falls to the boss keeps half the run's cash and no Valor.
- **The Hard-only elites are priced under the brutes** (1,200 against 2,000). They pay ×2 and
  ×4 on top of the count, and at the brute's price Brutal's Timber passes ×6.
- **Cash per minute** is 13,400 on Normal. The arena pays 144,250 in 10.2 to 12.0 minutes:
  12,000 to 14,100.

## L1: bands (`--check`)

"Fails at" values marked † were measured in the first pass and not again.

| Band | Where | Value | Now | Fails at |
|---|---|---|---|---|
| Normal: no hit over | sim_range | 25% of 145 | 24.8% | `damageScale` 1.15: 25.5% † |
| Still in camp A: down | sim_range | 6–12 s from the close | 9.8 s | camp A opening with 4 fodder: 12.1 s; `maxAlive` 4: 12.3 s † |
| Normal: the Colossus alone, every seed | sim_range | 64–90 s | 75.0–77.6 s | `hpScale` 1.25: 63.7 s; 1.8: 91–95 s † |
| Normal: the Colossus in the run, every seed | sim_range | 64–90 s | 74.8–75.8 s | |
| Normal: the clear, every seed | sim_range | 6–8 min | 6.30–6.79 min | camp B without its last two waves: 5.2 min; its waves twice over: 8.7 min † |
| `regenShare` | sim_range | within 10% of 10/130 | 0.077 | 0.09 |
| Hard at 4/4, Brutal at 6/6: no hit over | sim_range | 30% of the bar | 27.8%, 28.2% | `damageScale` 2.18: 30.4%; 3.58: 30.3% |
| The same: the Colossus alone | sim_range | 64–100 s | 77.9–80.1 s, 79.5–81.6 s | Hard `hpScale` 7: 115.8 s † |
| The same: the clear, every seed | sim_range | 6–9 min | 7.52–7.68, 7.38–7.53 | |
| **New: the human clears without going down, at the recommended gear, every seed** | sim_range | Normal, Hard, Brutal | 6–8, 5–15 and 9–15 hits, no down | Hard `damageScale` 2.8 and Brutal 6.0: one seed goes down in the Main Camp. Normal still passes at 3.0: on Normal this band does not bind |
| **New: the player who never dodges does not clear, at the recommended gear, every seed** | sim_range | Normal, Hard, Brutal | down in the Main Camp | too low a `damageScale`: 0.4 on Normal, 0.6 on Hard, 0.9 on Brutal (he clears) |
| At 2/1: never dodging, down in camp A (**now Brutal too**) | sim_range | Hard, Brutal, every seed | all three | Hard `damageScale` 0.6: he reaches the Main Camp. Brutal: still camp A at 0.3 |
| **New: clearly beyond the gear below, the human** | sim_range | one preset below he goes down, or takes ×1.8 (Hard) and ×1.4 (Brutal) as long as his slowest clear at the recommended gear | Hard: down, down, ×2.02. Brutal: down, down, ×1.54 | a kill speed nearer the recommended gear's: `hpScale` cannot move it, the presets' melee scales do |
| **New: clearly beyond the gear below, the Colossus alone** | sim_range | not killed inside 135 s (Hard at 2/1) and 180 s (Brutal at 4/4) | not killed in 240 s; 196.6 s | Brutal `hpScale` 10.5: about 179 s (computed, not run) |
| At 2/1: the Colossus alone takes over | sim_range | 135 s (Hard), 200 s (Brutal) | not killed in 240 s, both | `hpScale` 2.5: 128 s; 3.5: 197 s † |
| **New: under-gearing never pays better** | sim_range | one preset below, the reacting player's clear pays less cash a minute | 16,700 against 29,500; 47,200 against 67,700 | fodder priced so that the boss's calls out-pay the level |
| **New: only a checkpoint pays** | sim_range | each run banked what the kills of its cleared camps pay, and dropped what the kills of the camp it ended in pay | 12, 18 and 18 runs; 6, 8 and 8 of them lost | priced from the level file per camp, not from the run's pool |
| The arena behind its adapter is its mission | sim_combat 19 | 40 wave and party specs | each equal to the mission's wave worked by hand | a change to `camp_wave` or to `crowd_wave` alone |
| Level gates | sim_combat 20 | | both levels | as before, and the fix round's ruling 6 |
| Normal pays | sim_combat 21 | 87,000 and 155 ±10%; Valor 10 | +1.4%, +0.0%; 10 | fodder at 140: +14%; brutes at 9 Timber: +19%; a boss Valor of 12 † |
| Hard and Brutal pay | sim_combat 21 | ×2–×3; ×4–×6; Valor 20, 40 | ×2.54 and ×2.46; ×5.72 and ×5.57 | Hard `countMult` 1.5: ×3.16; Brutal 1.6: ×6.44; elites at 5 Timber: ×6.43 † |
| **New: the measured runs banked what the file pays** | sim_combat 21 | nine cleared runs | exact | |
| **New: the boss's calls pay under half the clear's rate** | sim_combat 21 | | 30% on Normal, 27% on Hard, 24% on Brutal | fodder at about 320 cash (Normal's pay band fails long before) |
| The layout | check_levels | the contract's table and the fix round's | 123 checks | 68 + 49 changes, each caught |
| **New: the mirrors are the Luau** | check_stage_mirror | about 5,600 comparisons | all equal | 53 changes, each caught |

**Two numbers of the lead's "clearly beyond" gate hold on Hard and not on Brutal, and I set
Brutal's.** The lead ruled ×1.8 for the human's time and "not killed in 135 s (Hard at 2/1) and
200 s (Brutal at 4/4)" for the Colossus. Hard meets both with room: ×2.0 and over 240 s.
Brutal cannot, and not for want of tuning:
- The two presets of Hard are ×3.33 apart in melee scale. Brutal's are ×2.17 apart.
- About a third of a clear is gear-blind: the walking, the countdowns, and the bursts that
  arrive over `targetWaveSeconds` however fast they die. So ×2.17 in kill speed is ×1.5 in
  clear time (11.0–11.3 min against 7.2–7.4), measured over twelve seeds.
- The Colossus alone at 4/4 falls in 196.5 to 202.9 s: 81 s × 2.17, plus what it calls.

Brutal's bands are therefore ×1.4 and 180 s. The 200 s is 2% away: Brutal `hpScale` 12.3
would hold it with room, and make the Colossus 86 s at 6/6 instead of 81 s and the clear about
7.8 min. I did not move a boss to meet a gate without being asked. Nothing in the level file
reaches ×1.8. Brutal at 2/1 keeps the contract's 200 s, with room. **The lead should confirm
or change these two numbers.**

**Which bands see `damageScale` now.** Too high: the 30% ceiling, then the human at the
recommended gear. Too low: the player who never dodges, at the recommended gear (all three
difficulties) and at 2/1 in camp A (Hard). The human's "clearly beyond" band no longer sees
it, by design: a slow clear passes whatever the damage.

**Two assertions were removed or replaced because they could not fail** (fix round, item 12).
- "No camp without a boss ever holds more than its `maxAlive`" is gone. The simulator's queue
  is what holds the count, so it tested itself. A camp's density is `check_levels.py`'s gate.
- "A cleared run banks once per camp and drops nothing" became "only a checkpoint pays",
  which prices every camp's kills from the level file and holds the lost runs to it too.
- `sim_combat.py` 19 compared two calls of one Python function. It now works each wave out by
  hand from the mission file. Assertion 21 printed what the runs banked and compared nothing;
  it now compares.

## L1: the Raider Arena

Its numbers stay where they are (`Missions/1_Village.json`, `Layouts/Arenas/Village.luau`). It
is read through mirrors of the two adapters, and its P5 checks pass: the bosses alone (76.8 s
and 97.7 s), the hit shares, the still player (10.6–10.8 s) are the same to the digit.

| | P5's simulator | L1, first pass | After the fix round |
|---|---|---|---|
| The three gated seeds | 11.5–11.8 min | 10.19, 10.35, 11.97 min | 10.19, 10.35, 11.97 min |
| Twelve seeds | 10.1–11.8 min, mean 11.0 | 9.9–12.0 min, mean 10.5 | 9.93–11.97 min, mean 10.49 |
| Seeds under the 10-minute floor | 0 | 1 | 1 (seed 53, 9.93 min) |
| Seeds that fold waves 2 to 4 into wave 1 | 6 of 12 | not counted | 10 of 12 |

- **The fix round moved nothing in the arena,** neither the trigger rule (its start point is
  inside its floor and triggers it at once either way) nor the tempo running through the
  breather again.
- **Why the restored tempo moves no number.** Three things read the director's tempo. The
  merge is asked only in a fight, on that tick's own value. The breather's length is taken at
  the clear, in a fight tick. The third is the extra elite, which reads the tempo at the
  moment a wave is queued, and that is the only reader of the value a breather leaves behind.
  No shipped mission or level names an `eliteKind`, so it never runs. In the game the restored
  rule changes what the HUD shows through a breather and nothing else; it will matter the day
  a level names an elite, and `check_levels.py` refuses one in a level file until the
  simulator mirrors it.
- **So the gap to P5 is L1's, not the fix round's.** The arena is about half a minute faster
  than in P5's simulator, and merges its early waves more often, since the first pass of L1.
  The first pass put that down to the 3-second countdown, which shifts every later frame of a
  chaotic run; it was not taken apart further and is still not.
- **A run begins with the 3-second countdown.** The gates close 3 s after the start, and
  wave 1 begins then.
- **Ruling 15: only a checkpoint pays.** The arena banks at every wave clear. A cleared run
  banks all 144,250 cash, 258 Timber and 35 Valor, as before. A failed run no longer pays for
  the wave in progress.
- **A merged group banks once, when it is beaten.** When the director folds waves 2, 3 and 4
  into wave 1, the four clear together. The player who never dodges then goes down in wave 4
  with nothing banked and 16,800 cash dropped. So "it loses at most one wave's kills" holds
  only for waves that did not merge.
- **Whether a wave merges turns on its last swing:** if it kills every body left, the wave
  clears; if it leaves one, the tempo that swing just raised passes `mergeTempo` and the next
  wave folds in.
- **What that means.** The arena's 10-minute floor is met by the gate's seeds and not by every
  seed. Nothing in L1 may change it: the arena's numbers and the director are frozen. When its
  numbers move into its level file (L4), either the merge rule or `targetWaveSeconds` should
  be re-tuned, or the floor lowered to 9.5.
- **On the other Python** its seed 11 clears at 10.27 min and its Warlord, inside the run,
  takes 98.3 s instead of 94.8 s. The Warlord alone is banded (97.7 s in 77–101) and does not
  move; the one inside the run is not banded.

## L1: rules these numbers hang on

- **The warmup counts from each camp's close.** If it counted from the run's start, every camp
  after the first would open at `tempoMin` and its first bursts would come 1.43 times further
  apart.
- **A camp's bursts take the next spawn point of a cursor that runs over the whole run.** Which
  point a camp's first burst rises at depends on how many bursts came before it.
- **The reacting player walks to the camp's middle during the countdown.** A player who stops
  at the gate meets the first burst about a second later.
- **A group arrives one burst interval after the group before it, at another spawn point.** That
  is why order decides how long a shooter lives.
- **The Colossus calls the same 48 fodder at every difficulty** in the reacting player's fight,
  because the fight lasts about as long. A slower player lets it call more, at 100 cash each.
- **A camp triggers at its fence line** (fix round). The countdown starts 5 studs earlier than
  it did, which moved Normal's clears by up to 0.2 min either way.
- **The human's gates hang on one number of the simulator, 0.55 s,** and on the slinger's shot
  flying 28 studs a second: a shot from under 17 studs lands inside that reaction.
- **Enemies of one kind take turns** (`perPlayer` 1 for a slinger). More slingers do not shoot
  faster; they keep the shooting going.
- **At the end of a run nobody is put into the level,** and everyone is healed in the lobby
  (fix round, `StageFlow.Rescue`). Neither is in the simulator, and neither touches a band: a
  run's clock stops at the last camp's clear.
- **The Luau and the mirrors are one rule set,** as of the fix round's end:
  `check_stage_mirror.py` compares them and is a gate.

## L1: flags for the owner

- **The simulated human is only ever hit by slingers' shots at close range.** His gates
  measure slingers times `damageScale` and nothing else. A real first clear will cost more
  health than his 6 to 8 hits on Normal, from lunges and swings he never takes. **A better
  human model is owed before the real balance pass (L4).**
- **Two of the lead's numbers for "clearly beyond" are not met on Brutal,** and I set ×1.4
  and 180 s there instead of ×1.8 and 200 s: see the bands. Brutal's two presets are closer
  together than Hard's.
- **One preset below, a human does clear sometimes:** 4 seeds of 12 on Hard at 2/1 (in 15
  minutes) and 5 of 12 on Brutal at 4/4 (in 11). The lead ruled that fine.
- **A slow Brutal clear banks ×6.10 of Normal,** over the ×6 the band names for the
  recommended gear. It pays 30% less by the minute, so it is no way to farm.
- **The run cap sits 1.7 min over the reacting player's slowest Hard clear at 2/1** (15.8 of
  17.5 min). It is not used as a gate.
- **Camp A is the level's soft spot on Normal:** its slingers die on arrival. See "who fits
  where".
- **The lookout opens to Leap Smash.** One jump and a Leap Smash rise 28 studs, and with the
  step-up 31; the ledge is 26 above the road. L2 has to rule on it; no height fixes both.
- **The Raider Arena has a boulder as tall as its lowest ground attack** (4 studs, the
  Colossus's ring). A body on it is hit by the rule as written, with no margin.
- **A boss's second phase cannot come earlier on Brutal.** The plan asks for it, and `enrage.at`
  is a number of the kind, not of the difficulty. Brutal is tougher by health, damage and
  count only.
- **A camp cannot set its own burst size.** `crowd.burst` is the level's. Eight suits camp A;
  camp B could take twelve.
- **The director's extra elite is not in the simulator.** No shipped file names one. The day
  a level does, the tempo a breather leaves behind decides it, and both tools must learn it
  first.
- **Recommended tiers and every reward are placeholders,** as the contract says. The Armory of
  L3 decides what tiers 4 and 6 mean.
- **Never measured, as the contract lists:** the gap on a touch screen, the crowd on a floor at
  height 8 and 12 in play, the camera at a camp's wall.

## L1b: the living road, Wave 1 (2026-10-14)

Contract: `docs/INTERFACES.md` "L1b contracts — the living road". Today's road and camp sizes;
camps A and B are open and inhabited, only C (the Chief's Clearing) locks. Measured as L1: gear
2/1, Broadsword + Longbow, solo, the reacting player of `sim_range.py` (policy `mission`), three
seeds, the gate's Python (64-bit 3.12). L1's numbers are the starting point (Ben, after L1:
"balance feels good").

### L1b: values

| Key | Value | Why |
|---|---|---|
| `camps.guard` | sight 30, cone 140°, rise 0 | contract start; a guard faces the way in |
| `camps.patrol` | sight 24, cone 360°, rise 0 | contract start |
| `camps.fire` | sight 16, cone 360°, rise 1.5 s | sitters are slow to stand: the first strike lands 1.3–1.5 s before any windup |
| `sightBelow` / `sightAbove` | 4 / 30 | contract start |
| `chaseMargin` | **3 → 2.5** (fix round) | in-play now has rounded corners (CampBrain.InPlay: flat distance to the floor ≤ chaseMargin); a rusher clamped in a corner stands √2 × radius from it, so the gate is reach − √2 × radius for every resident rusher at every difficulty: fodder 4.5 − 1.84 = **2.66** (`check_levels.py`) |
| `leashSeconds` | 3 | contract start; the kiting player finds a group at rest again 4.5 s after he steps out |
| `homePace` / `patrolPace` / `homeTolerance` | 1 / 0.5 / 1 | contract start |
| `engagedHoldSeconds` | **1.5** (new, fix round) | `CrowdService.Engaged` holds this long after he was last in play for a rising or fighting group: a fall from a fight reaches `killY` in 0.4–0.6 s, so the rescue sees him engaged (no get-up i-frames), and the phone Abandon button stops flickering at a camp's edge |
| `levels.checkpointReach` | 8 | contract start |
| `levels.populationReserve` | 21 (fixed) | the boss, 12 summons, 8 for Wave 2's tents |
| `levels.walletSendSeconds` | 1 (fixed) | L1b-16 |
| `levels.fireMarkerSize` | 3 × 1 × 3 | a grey-box marker per fire |
| `looks.fire` | Neon (255, 150, 30) | a warm colour that reads at 60 studs |
| Forest Road `targetMinutes` | **7 → 3** | the contract sets it to the measured first clear (mean 3.1 min) |
| Forest Road `runCapSeconds` | 1050 (unchanged) | ×5.8 of the target, ×3.3 of the slowest clear |
| `crowd.clearBonus` | 0 / 0 (now written in `1_ForestRoad.json`) | Ben's "disregarding clearing status"; a config change if he asks for one. Both simulators now pay it on every `campClear` and on the locking camp's `open` (not on a skip); a scratch run at 1,000 cash / 5 Timber kept `sim_combat` 21 green (+3,000 cash, +15 Timber on Normal: A, B and C) |

Nothing else moved: the difficulties, rewards, `regenShare`, `burst` and C's stage are L1's
(C keeps its one wave of 35 and the Colossus at `[14, 0]`, Valor 10).

### L1b: who lives where

| Camp | Group | Posture | Normal | Hard and Brutal add |
|---|---|---|---|---|
| A, Pickets | fire1 (r 4) | fire | 4 fodder, 1 slinger | 1 slinger |
| | eastGate | guard, faces west | 4 fodder | 1 plated elite |
| | fire2 (r 5) | fire | 4 fodder, 1 slinger | 1 plated elite, 1 slinger |
| B, Main Camp | fire1 (r 4) | fire | 4 fodder, 1 slinger | 1 plated elite |
| | loop (32 × 36) | patrol | 5 fodder | |
| | southWatch (7 points) | guard, faces north | 2 slingers, 2 fodder, 1 brute | 2 marksmen |
| | fire3 (r 6, at (100, −64.5)) | fire | 1 brute, 3 fodder, 1 slinger, 1 lobber | 1 marksman |
| | fire2 (r 5) | fire | 4 fodder, 1 slinger | |
| | eastGate | guard, faces west | 2 brutes | 2 plated elites |
| C, Chief's Clearing (held) | gate | guard, faces west | 4 fodder | |
| | chiefFire (r 4) | fire | 1 brute, 2 fodder | 1 plated elite |

| | Normal | Hard | Brutal |
|---|---|---|---|
| Residents A / B / C | 14 / 28 / 7 = 49 | 18 / 34 / 8 = 60 | 18 / 34 / 8 = 60 |
| Bands at the highest difficulty | | A 12–18, B 30–40, C ≥ 4 and < 30 | (the same) |
| **Population (L1b-11)** | **93** = 49 + 23 + 21 | **103** = 60 + 22 + 21 | **103** |
| `crowd.maxAlive` | 160 | 160 | 160 |

- Residents never scale with `countMult` or the party (L1b-10): Hard and Brutal differ only by
  their `minDifficulty` units, so Brutal's residents equal Hard's; C's wave still scales.
- **Parts: 67** = L1's 73, less 6 for each open camp (two gates, four barrier boxes), plus six
  fire markers. `check_levels.py` holds that sum.
- The checkpoints of A and B stand on the road beyond each exit, (16, −42) and (150, −42), on
  ground whose top is 8 = the floors' height. The nearest resting eye is a guard of the east
  gate, 28.1 and 20.1 studs off, inside its sight but behind its 140° cone (gated: no resting
  member sees a checkpoint, a patrol anywhere on its loop).
- **Fix round: no resting shooter reaches a checkpoint** (new gate: farther than every keepAway
  resident's longest reach from its post, a patrol's from its loop, every difficulty). Both
  checkpoints failed it: A's (16, −42) lay 44.6 from B.fire1's Hard marksman (48); B's (150, −42)
  37.0 from B.fire2's lobber (42) and 33.8 from its Hard marksman. Neither checkpoint can move far
  enough (RoadAB is 44 long between A.fire2's slinger and B.fire1's marksman; RoadBC1 ends at x
  164), so B's shooters moved inward: B.fire1's marksman and B.fire2's to the south watch, the
  lobber to fire3 (radius 6 for seven on Hard), and the patrol's plated elite to B.fire1 (one pace on
  the loop, no conga line). Totals unchanged. Nearest now: 40.0 from A.fire2's slinger (32) and 34.1
  from B.fire2's slinger (32). Where a fighting shooter has walked to is `StageFlow.SafePoint`'s
  business (B: it skips a checkpoint a rising or fighting body reaches).

### L1b: results

| | Normal at 2/1 | Hard at 4/4 | Brutal at 6/6 |
|---|---|---|---|
| **The reacting player's first clear** | **3.00–3.13 min** (band 2.5–4, the lead's ruling: **PASS**) | 3.46–3.49 min (reported) | 3.47–3.52 min (reported) |
| Hits he took | 0 | 0 | 0 |
| The human's clear (reported) | 2.93–3.02 min, 1–3 hits | 3.31–3.39 min, 5–7 hits | 3.34–3.39 min, 5–7 hits |
| The player who never dodges | down in the Main Camp at 0.66–0.83 min | down in the Main Camp at 0.71–0.75 min | the same |
| The Colossus alone in camp C | **76.3 s** (75.0–77.6) | 79.3 s | 80.8 s |
| The Colossus in the run | 73.7–75.6 s | 76.7–79.0 s | 78.6–80.6 s |
| The worst hit | the Colossus's lane, 36 = **24.8%** | 64 = 27.8% | 107 = 28.2% |
| Bodies killed | 131–133 | | 160 |
| Most alive at once | 15 | | 16 |

A Normal run, seed 11: the road and camp A 19.7 s (A's 14 residents fall in about 9 s), B
cleared at 59.5 s, C's gates close at 66.9 s and it clears at 178.8 s (its wave of 35, then the
Colossus in 74.6 s). 422 studs walked outside the fights = 21 s.

**The Wave 1 scenarios, Normal, every seed:**
- **Standing still where a group first wakes** (A's fire1, as he crosses the Pickets): woken at
  11.7–11.8 s, down **9.7–9.8 s** later (band 6–12 s).
- **A first strike**, each of the five fire groups of A and B alone, walked up to from the
  road: woken by sight, his first hit 0.12–0.17 s after the wake, their first windup 1.4–1.6 s
  after it (one seed of A.fire2 never wound up). Passes.
- **The leash** (`kite`: two kills in A, out to the road, wait, back): out at 12.6–13.5 s with
  11–12 alive (2–3 hurt), the groups at rest again 4.5 s later, back in after 2.3 s: every
  survivor whole, the dead still dead, one leash each; then a normal clear. Passes.
- **The edge** (`edge`, 2.6 studs outside A's east edge by its gate guards, 30 s; was 3.1 before
  the fix round's chaseMargin 2.5): 228 hits, every one "blocked", 0 kills, 0 paid. Passes.
- The numbers above are the fix round's re-run (chaseMargin 2.5, B's shooters moved inward,
  `engagedHoldSeconds` 1.5): the clear moved by hundredths, the pay not at all (the same bodies).

### L1b: what a clear pays (reported, not banded)

| | Normal | Hard | Brutal |
|---|---|---|---|
| Residents of A | 2,200 cash, 2 Timber | 11,200, 16 | 22,400, 32 |
| Residents of B | 13,000, 33 | 36,800, 84 | 73,600, 168 |
| Residents of C | 2,600, 6 | 7,600, 16 | 15,200, 32 |
| C's wave, the Colossus and its 48 calls | 43,000, 88, 10 Valor | 92,000, 184, 20 Valor | 199,200, 400, 40 Valor |
| **The clear** | **60,800 cash, 129 Timber, 10 Valor** | **147,600, 300, 20** | **310,400, 632, 40** |
| Against L1's Normal (88,200 / 155 / 10) | −31.1% cash, −16.8% Timber | ×2.43 cash, ×2.33 Timber of Normal | ×5.11, ×4.90 |

- Every run of every policy was paid exactly the sum of its kills' rewards (solo, the carry never
  holds a fraction at a multiplier of 1), and every lost run kept every kill (`sim_range.py`,
  33 Normal runs, 18 each on Hard and Brutal). Valor is exactly 10, 20 and 40.
- **By the minute the clear pays more than L1:** about 19,800 cash a minute on Normal against
  L1's 13,400, because the residents' fights have no `targetWaveSeconds` spreading them.
- The boss's calls pay 67 cash/s against the clear's 330 on Normal (20%): standing at the boss
  to farm its calls still never pays.

### L1b: bands (`--check`)

| Band | Where | Value | Now |
|---|---|---|---|
| **Normal: the first clear, every seed** | sim_range | **2.5–4 min** (the lead's ruling, option c, for Wave 1's size) | **3.00–3.13 min: PASS** |
| Normal: the Colossus alone / in the run | sim_range | 64–90 s | 75.0–77.6 / 73.7–75.6 s |
| Normal: no hit over | sim_range | 25% of 145 | 24.8% |
| Still in a woken group of camp A | sim_range | 6–12 s from the wake | 9.7–9.8 s |
| A first strike on every fire group | sim_range | his hit before any windup | 15 of 15 |
| The leash (`kite`) | sim_range | whole on return, the dead dead, paid only for kills | 3 of 3 |
| The edge (`edge`) | sim_range | 0 from that group | 0, 228 blocked |
| Every kill paid once, at once; Valor exact | sim_range, sim_combat 21 | solo exact | exact |
| Hard and Brutal: hit ceiling, the Colossus | sim_range | 30%; 64–100 s | 27.8%, 28.2%; 76.7–80.6 s |
| Hard and Brutal: the clears, the human gates | sim_range | reported (draft point 8) | above |
| SplitCarry fuzz | sim_combat 22 | never over the shares, never a unit under, carry < 1 | 400 runs × 60 kills |
| Population = Validate's | sim_combat 23 | by hand = Plan, ≤ 160 | 93, 103, 103 |
| The Wave 1 layout table | check_levels | the contract's table | pass; 22 of 23 data mutations caught (the miss left B inside its band) |
| chaseMargin, perches, checkpoints (fix round) | check_levels | margin ≤ reach − √2 × radius (2.66); any standable top within the margin and in the band ≤ lowest rusher ground height − 0.5 (4.5; the fence is 4); no resting shooter reaches a checkpoint | pass; proved by mutation (margin 2.7; a 5-tall block 1 off A; a block 2.12 off A's corner; the old B shooters) |
| The mirrors are the Luau | check_stage_mirror | CampBrain, KillReward, SplitCarry, FieldClear, SafePoint, Plan's zones, groups and population, the L1b refusals, scripted runs with checkpoints and open camps; fix round: InPlay's rounded corners, `Engaged`'s hold, SafePoint's threats, `open`'s `skipped` | all equal; 28 of 28 Luau mutants caught, and the fix round's 5 (square corners, no hold, `<` for `<=` on a threat, threats ignored, a stage skip not `skipped`) |

### L1b: the Raider Arena

Its numbers are frozen and every L1 band holds: the Colossus alone 76.8 s, the Warlord 97.7 s,
still in wave 1 down at 10.6–10.8 s, clears at 10.19, 10.35 and 11.97 min, the worst hit 24.8%.
**What moves is L1b-15: a failed arena run now keeps every kill** (the player who never dodges
keeps 16,800 to 24,960 cash where L1 dropped the wave in progress). A cleared run pays the same
144,250 cash, 258 Timber and 35 Valor: solo at a cash multiplier of 1 the carry changes nothing.

### L1b: flags for the owner

- **Ruled (the lead, option c): Wave 1's Normal first-clear band is 2.5–4 min.** L1's camp sizes
  cap the residents (A 18, B 40), so a reacting player clears in about 3 min (road 21 s, A 9 s, B
  40 s, C 112 s); Wave 2's bigger camps bring the ~10 min band back. `sim_range.py`
  `FOREST_CLEAR_SECONDS` (150, 240); its label now prints "2.5-4 min".
- **For Ben: replaying Forest Road Normal roughly doubles Timber per minute until Wave 2.** A Normal
  clear pays 129 Timber in about 3.1 min, **~42 Timber a minute against L1's ~24 (+~75%)**, and
  ~19,800 cash a minute against 13,400 (+46%). That makes Forest Road Normal the fastest Timber for
  the Armory today. Wave 2 should carry a per-minute pay band, not only a per-clear one.
- **The pay drops with the time:** 60,800 cash on Normal against L1's 88,200, though more by the
  minute. It returns with Wave 2's residents.
- **The simulated player is never hit by a resident** on Normal. Residents rise into a fight he
  starts; real play will cost more than the 2–3 slinger hits his human twin takes.
- **The edge player's blocked hits wake the gate guards 10 times in 30 s**, each wake a 3-second
  leash and a walk home, each a "!" on his screen. Ben may find that noisy.
- **Hard and Brutal residents are the same 60 bodies.** Brutal differs in the open camps only by
  health and damage. Wave 2 can give Brutal its own `minDifficulty` units.
- **The fix round moved B's shooters inward** (see "who lives where"): the south watch now holds
  two slingers and, on Hard, two marksmen; fire3 a lobber. Expect the Main Camp's long shots from
  the south and the middle, not from the fires by the gates.

### L1b: open, carried to Wave 2

- **Post spacing gated beyond fires.** `check_levels.py` keeps neighbours round a fire 2 radii +
  0.5 apart, but not guard points, patrol posts, or posts of different groups in one camp (data.md
  Minor 7). Two posts within about a stud keep both bodies off their posts and the group in `home`
  for good. Wave 1's closest pair is 1.4 studs clear (the two new south-watch points are 5.66 from
  their neighbours); Wave 2's bigger camps need the gate: every pair of posts of a camp at every
  difficulty at least r_a + r_b + 0.5 apart, a patrol's loop included.
- A per-minute pay band (the Timber flag above).

## L1b: the long road, Wave 2 (2026-10-14)

Contract: `docs/INTERFACES.md` "Wave 2 — the long road" (with "Lead's answers to the draft points")
and `docs/prompts/l1b-w2-reports/lead-routing.md`. The layout is the winding road Ben picked
(`docs/prompts/l1b-w2-layout/winding.*.json`). Measured as Wave 1, but at **gear 2 / 2**
(`debug.provingGear`): Broadsword + Longbow, solo, the reacting player of `sim_range.py` (policy
`mission`, melee only), three seeds, the gate's Python (64-bit 3.12). Every mirror was in place,
and `check_stage_mirror.py` held it equal to the Luau, before any band was read. The mirrors cover
the ray rule, the tents, the join-in, dormancy, the clear bonus, `DeadFraction` and `StandsUp`.

### L1b W2: values

| Key | Value | Why |
|---|---|---|
| `camps.tent` | sight 24, cone 360°, rise 0 | contract; a tent's group stands (idle) round its marker |
| `camps.joinFactor` | 2 (fixed) | Ben's "at least double" |
| `camps.dormantRadius` | 120 | contract start. It is gated at ≥ every sight + FastestMove / snapshotHz = 30 + 140 / 15 = 39.3. The floors are 109 and 185 apart |
| `levels.populationReserve` | **removed** | L1b-W2-5: the boss reserve is derived (1 + the Colossus's 12 calls = 13) |
| `debug.provingGear`, `gearPresets` | 2 / 2; 2 / 2, 4 / 4, 6 / 6 | L1b-W2-20 (fixed) |
| `debug.perfAttribute` | `"CrowdPerfMs"` | L1b-W2-23 |
| `looks.tent` | Fabric (222, 184, 120) | a canvas tan, not the fire's orange. It is a colour look (channel spread 102 > 80) |
| Forest Road `crowd.clearBonus` | `{ share 0.1 }` | Ben's "a small bonus" (LR 2) |
| Forest Road tents | 8 bodies, **one every 6 s** (Ben's, LR 5) | the lead's ruling after the build: the pace stays, the clear band moves (below) |
| Forest Road `rewards.brute.materials` | **6 → 3** | the Timber-a-minute band. At 6 a Normal clear paid 53–57 Timber a minute, and at 4 it paid 44–50 (the fast seed over 46.2). 3 is one step past the contract's named 4, which the lead's ruling allows ("the Timber of brutes") |
| Forest Road B's residents | 14 fodder swapped (see "who lives where") | levers 1 and 4: the Main Camp is the part of the clear the mix moves |
| Forest Road A's watch | 2 fodder → 2 slingers | a little Timber, and the variant with the widest margins on both bands (below) |
| Forest Road `targetMinutes` | **9 → 7** | the measured mean first clear (7.2 min), as Wave 1's rule |
| Forest Road `runCapSeconds` | 1500 (the draft's) | ≥ 2 × the human's slowest Normal clear (7.09 min → 851 s) and ≥ 1260 |
| Layout: A's tent | moved 6 studs west, (−201.5, 6) → (−207.5, 6) | at the draft's place its ring stood 1 stud from A.loop's patrol, so post spacing failed by 2.9. The patrol and the picture are unchanged |
| Layout: tents' `radius` | 10 (A and B; C's tent is a marker only) | clears its 10 × 10 marker by ≥ 2.9 (≥ every ring body's radius) and every other post |
| Layout: C's tent | moved 2 studs north, (353.5, 0) → (353.5, −2) | at z 0 its south wall (z 6) ran through the centres of C.south's last three guards (two lobbers, and the plated raider on Hard): each stood 1.4–1.7 studs inside the opaque marker. Now the wall is at z 4 and the tightest, Hard's plated raider, clears it by 0.30. C's spawns and every number are unchanged (the marker is where C's stage waves come out) |
| Layout: `sneak` | gained its last point (262, −44), C's entry | the gate runs the path to the boss room's entry. The draft stopped at (250, −44) |

No `ProvingGrounds.json` number moved (gate 13). C's stage, the difficulties and every other reward
are unchanged too.

> **Superseded for camp C by L1c** (below): C's tent marker is gone, C moved south behind a gatehouse, and the sneak path now ends at C's new entry (313.5, −16).

### L1b W2: the Normal clear band (the lead's ruling)

- The contract's band for the reacting player was 7–8 min.
- At Ben's 6-second tents no mix met it on every seed without breaking the Timber band:
  - The Broadsword's cleave takes a camp's bodies in crowds, so mix swaps move the Main Camp's clear
    by about ±15 s of seed noise.
  - Every brute added pays Timber.
  - The tents set the floor of each open camp's clear. A clears the moment its 8th tent body falls.
- A trial at one body every 8 s reached 7.23–7.51 min. The lead kept Ben's own pick instead,
  because at 8 s the player waits about 32 s for the last tent bodies in camp A.
- **The band is now 6.5–8 min** (`sim_range.py` `FOREST_CLEAR_SECONDS` (390, 480)). Ben, at about
  ×1.36 of the simulator, takes 8.8–10.9 minutes.

### L1b W2: who lives where (Normal; Hard and Brutal add the draft's 12 `minDifficulty` units)

| Camp | Group | Posture | Normal |
|---|---|---|---|
| A, Pickets (85 × 85) | fireW, fireN, loop | as the draft | fireW 5 fodder 2 slingers; fireN 6 fodder 1 slinger; loop 6 fodder 2 slingers |
| | watch | guard | **4 fodder, 4 slingers** (draft 6 fodder, 2 slingers) |
| | tent (8, one every 6 s) | tent | 4 fodder, 2 slingers, 2 brutes |
| B, Main Camp (141 × 133) | fire1 | fire | **2 fodder, 2 plated**, 1 slinger, 2 brutes (draft 4 fodder) |
| | fire2 | fire | **1 fodder, 2 plated**, 2 slingers, **2 brutes** (draft 4 fodder, 1 brute) |
| | loop | patrol | **2 plated, 5 brutes**, 1 slinger (draft 4 fodder, 3 brutes) |
| | fire3 | fire | **1 fodder, 3 slingers**, 1 lobber, 3 brutes (draft 3 fodder, 1 slinger) |
| | eastWatch | guard | 4 brutes, 2 plated, 1 slinger, 1 lobber (as the draft) |
| | eastFire | fire | **1 fodder, 3 slingers, 4 brutes** (draft 4 fodder, 1 slinger, 3 brutes) |
| | tent (8, one every 6 s) | tent | 2 fodder, 2 slingers, 4 brutes |
| C, Chief's Clearing (held) | gate, chiefFire, north, south | as the draft | 18 fodder, 10 brutes, 4 slingers, 2 lobbers, 2 plated |

| | Normal | Hard | Brutal |
|---|---|---|---|
| Residents A / B / C | 30 / 46 / 36 = 112 | 36 / 50 / 38 = 124 | 124 |
| Tents' stock | 8 + 8 | 8 + 8 | 8 + 8 |
| **Population (L1b-W2-5)** | **147** = 112 + 16 + room 6 + boss 13 | **157** = 124 + 16 + 4 + 13 | **157** |
| Brutes in the level (residents, tents, C's waves) | 42 (draft 38) | | |

> **Superseded for camp C by L1c** (below): C's residents, the population rows and the parts and route figures above describe the old clearing; L1c has 10 / 12 / 12 ambushers, 86 Parts and a 1,079-stud route.

- **Parts 82** (79 + 3 tent markers). The route is 1,055 studs (750 outside the camps), and every
  camp lies within 379 studs of the origin.

- **Post spacing** (new gate, L1b-W2-4): the tightest pair is inside B.fire1's ring on Hard, with
  +0.07 to spare (the fire rule's own case).
- **The sneak path** is 979 studs, with its gap jumped and two climbs. The tightest margins against
  sight:
  - B.fire1 +6.1 (sight 16), A.fireN +7.0, A.fireW +11.9, B.fire2 +15.0;
  - B.eastWatch +15.3 (+28.1 in its cone), A.loop +17.1.
- **The join-in from rest** (check_levels' chain table, on Normal; a tent has sent nobody yet):
  - A.fireW ↔ A.fireN (14 bodies);
  - A.watch → fireW, fireN, loop (30); A.loop → fireN, watch, fireW (30);
  - B.fire1 ↔ B.fire2 (14); B.loop ↔ B.fire3 (16); B.eastWatch ↔ B.eastFire (16);
  - once out: A.tent → all of A (30); B.tent → fire3, eastWatch, eastFire, loop (32).

### L1b W2: results

| | Normal at 2 / 2 | Hard at 4 / 4 | Brutal at 6 / 6 |
|---|---|---|---|
| **The reacting player's first clear** | **7.02–7.25 min** (band 6.5–8: **PASS**) | 7.14–8.13 min (reported) | 7.35–8.21 min (reported) |
| The human (0.55 s) | 6.54–7.09 min, 0 downs, 11–14 hits (**PASS**) | 6.88–7.74 min, 0 downs (**PASS**) | 6.95–7.82 min, 0 downs (**PASS**) |
| The player who never dodges | down at 1.41–1.43 min (**PASS**) | down in the Pickets at 0.45–0.47 min (**PASS**) | the same (**PASS**) |
| The Colossus alone | **80.5 s** (79.4–82.7; band 64–90) | 83.2 s (64–100) | 86.1 s (64–100) |
| The Colossus in the run | 74.4–76.5 s | 77.7–80.0 s | 80.0–81.3 s |
| The worst hit | the Colossus's lane 36 = **23.2%** (25%) | 64 = 27.8% (30%) | 107 = 28.2% (30%) |
| Most alive at once | 113 | 125 | 125 |

**One preset below the recommended gear** (all **PASS**):

| | Hard at 2 / 2 | Brutal at 4 / 4 |
|---|---|---|
| The human | down twice; one clear at ×2.65 | down in every seed |
| The Colossus alone | not killed in 240 s (gate: > 135) | 209.6 s (gate: > 180) |
| Cash a minute, the reacting player | 19.5–21.0k against 46.6–53.1k | 44.3–50.3k against 94.9–106.0k |

**The scenarios on Normal, every seed** (all **PASS**):
- **Still:** standing in the first woken group of A, he is down 6.9–7.2 s after its wake (band 6–12).
- **A first strike** on each of the six fire groups of A and B: his hit lands 0.13–0.95 s after the
  wake, before any windup.
- **The kite:** he is out at 14.5 s with 28 alive; the camp is at rest again 7 s later and he is back
  in 2 s after that. Every survivor is whole, the dead are dead, and **the tent's stock left is the
  same as when the camp went home**.
- **The edge:** 0 paid.
- **The sneak:** 972 studs, wakes nobody.
- **The join-in:** each camp's first wake brings in exactly the chain from rest (A.fireW → A.fireN,
  B.fire1 → B.fire2).
- **The tents:** 8 of 8, 6.0 s apart from the wake. With no resident alive and the camp at rest,
  all 8 come out at 0, 6, …, 42 s, then never again.

Also, reported:
- **The careless road:** walking the road through A and B wakes their road fires (A.fireN and
  B.fire1 by sight, A.fireW and B.fire2 by the join-in) and both tents. He is past before any of it
  reaches him (no down in 47 s).
- **Dormancy:** about 175,000 body-steps of a Normal run were dormant (not integrated, separated or
  clamped).

**How the mix was chosen.** At 6-second tents and brutes at 3 Timber, `sim_range` ran nine small
mixes of camp A. Each swaps fodder for slingers (fireW, fireN, watch, loop; one or two each). Every
mix was scored by its worst margin on the two bands:

| Mix | Times (min) | Timber a minute | Worst margin |
|---|---|---|---|
| Unchanged | 6.52–7.37 | 38.0–42.9 | +0.02 |
| **watch +2 slingers (shipped)** | 7.02–7.25 | 38.9–40.2 | **+0.52** |
| loop +2 | 6.97–7.14 | 39.5–40.5 | +0.47 |
| fireN +1, watch +1 | 6.95–7.16 | 39.4–40.6 | +0.45 |
| loop +1 | 6.94–7.90 | 35.6–40.5 | −2.22 |

The spread from mix to mix is seed chaos in the Main Camp, not the slingers themselves.

### L1b W2: what a clear pays

| | Normal | Hard | Brutal |
|---|---|---|---|
| **The clear** | **171,347 cash, 282 Timber, 10 Valor** | 381,253 (×2.23), 619 (×2.20), 20 | 783,587 (×4.57), 1,265 (×4.49), 40 |
| Against the draft's arithmetic (152,820 / 373 / 10) | +12.1% cash, −24.4% Timber | band ×2–×3: **PASS** | band ×4–×6: **PASS** |
| **A minute** | **23.6–24.4k cash** (+19% to +23% of Wave 1's 19,800); **38.9–40.2 Timber** (band 37.8–46.2: **PASS**) | 46.6–53.1k, 76–87 Timber | 94.9–106.0k, 154–172 Timber |
| The camps' clear bonuses (seed 11) | A 1,200 / 2, B 6,620 / 11, C 4,660 / 7 = 12,480 cash = **7.3%** of the clear (band 5–10%: **PASS**) | A 3,440, B 13,960, C 10,920 | A 6,880, B 27,920, C 23,720 |

- Every kill is paid once, at once. Every bonus equals `Combat.ClearBonus` on the camp's whole stock
  by hand (sim_combat 21: 9 cleared runs exact). No bonus is paid on a skip.
- The boss's calls pay 67 cash/s against the clear's 399 on Normal (17%; the gate is under 50%).

> **Superseded for camp C by L1c** (below): C's bonus and the pay rows above are the old clearing's.

### L1b W2: the bow at 2 / 2 (reported for Ben's question)

The Longbow alone against one body at the boss's spot in C, the reacting player, two seeds:

| Target | Body aim, old rule | Body aim, new rule | Head aim, old rule | Head aim, new rule |
|---|---|---|---|---|
| Brute | 6.3 s | 6.3 s | 3.1 s | 3.1 s |
| Plated elite | 5.2 s | 5.2 s | 2.1 s | 2.1 s |
| **Colossus** | 141.8 s | 133.9 s | 124.9 s | **95.0 s** |

- **Brutes and plated elites:** the aim ray from chest height to the head already crossed the old
  body sphere, so the new rule changes nothing there.
- **The Colossus:** a head shot used to miss the body sphere outright (63% of head aims, report
  `headshot.md`). With the capsule and the head both counted it crits, and the bow kills the Colossus
  in 95 s against the sword's 80. Nothing was re-tuned (L1b-W2-20).

The ray rule moved the range's own rows a little against `main`; all of the range's passes stay
green:

| Row | `main` | Now |
|---|---|---|
| Splitbow B, crowd DPS | 200 | 215 |
| Volley | 211 | 212 |
| P4 Colossus, Longbow | 143.9 s | 142.8 s |
| P4 Colossus, Splitbow | 225.4 s | 195.4 s |
| P4 Colossus, Piercing Rifle | 54.8 s | 53.3 s |
| P4 Colossus, Beam | 116.1 s | 112.6 s |
| Warlord, Longbow | 158.6 s | 162.2 s |
| Warlord, Splitbow | 208.3 s | 203.2 s |

Projectiles now crit as the game's do (`path_candidates` carries the crit). Body aims never touched
a head, so no earlier number moved because of that.

### L1b W2: the Raider Arena at 2 / 2

Its files are frozen, and every band holds:
- the Colossus alone 76.8 s, the Warlord 97.7 s;
- standing still in wave 1, down at 11.0–11.1 s;
- clears at 10.19, 10.35 and 11.97 min with no hit;
- the worst hit 23.2%;
- paid 144,250 cash, 258 Timber and 35 Valor.

### L1b W2: bands (`--check`)

| Band | Where | Now |
|---|---|---|
| Normal first clear **6.5–8 min** (the lead's ruling), every seed | sim_range | 7.02–7.25: PASS |
| Timber a minute 37.8–46.2, every seed | sim_range | 38.9–40.2: PASS |
| Colossus 64–90 (Normal), 64–100 (Hard, Brutal) | sim_range | 80.5 / 83.2 / 86.1: PASS |
| Hit ceilings 25% / 30% / 30% | sim_range | 23.2 / 27.8 / 28.2%: PASS |
| The human clears and the never-dodger does not, every difficulty | sim_range | PASS |
| Beyond the gear below (down or ×1.8 / ×1.4; Colossus > 135 / 180 s; less cash a minute) | sim_range | PASS |
| Still, first strike, kite (+ tent paused), edge, sneak, join-in, tents | sim_range | PASS |
| Pay ×2–×3 and ×4–×6; bonus 5–10%; Valor exact; calls under half | sim_combat 21 | PASS |
| Population = Validate's, ≤ 160 | sim_combat 23 | 147 / 157 / 157: PASS |
| The Wave 2 table | check_levels | PASS. Post spacing proved on the draft's tent (fails by 2.9); the marker clearance on C's tent at z 0 (fails, the two lobbers 1.40 inside) |
| The mirrors | check_stage_mirror | all equal; **42 of 42 Luau mutants caught** by `py tools/crowd_harness/mirror_mutants.py` (below; about 2.5 min) |

The Wave 2 table covers sizes, route, residents, sneak, post spacing, population, tents, markers,
looks, `dormantRadius`, `joinFactor`, and checkpoints with tents. Since the fix round, every
resident post and patrol loop of a camp with a tent block (C's included) must clear the marker
by its body's radius at every difficulty. The old line "every tent marker is walk-through"
tested a `collide` key no layout has and could not fail, so it is gone: the marker is built
walk-through by `LevelGeometry`, and the harness's mutation "l1b w2: the tent marker built
colliding" is the guard.

> **Superseded for camp C by L1c** (below): C has no tent marker any more; the marker rules now hold on A's and B's only.

**The Luau mutants.** Each is one text change, run through `check_stage_mirror.py --module`. The
driver is `tools/crowd_harness/mirror_mutants.py` (`--list`, `--only <label>`); a mutant whose
text no longer occurs once reports STALE and fails, so a module edit must re-aim it.

| Module | Mutants caught |
|---|---|
| HitShapes | CrowdRay: the head dropped, the crit padded, the body a sphere again, `top` without its max; RayUpright without its top cap; FlatToRect with square corners |
| SwingGate | IsAir with `>=`; Took ignoring `airborne`; Landed doing nothing; Allows ignoring `used`; another margin |
| CampBrain | Dormant true while home; Dormant ignoring `dormantRadius`; Gap taking the largest; JoinIn not chaining, using the first waker's sight, joining a held group, excluding the factor's edge; Rouse waking a held group; TentActive ignoring the dead residents; TentDue ignoring `active`; TentSent not moving `nextAt`; a tent's posts facing its centre; a tent seated at rest; Problems passing a joinFactor of 0 and a dormantRadius at a sight |
| Combat | ClearBonus flooring; ClearBonus ignoring rewardMult; DeadFraction not clamped at 0; WaveStock ignoring the elite |
| StageFlow | StandsUp outside the countdown; BossReserve without the boss; Plan leaving the tents out of the population, a tent's ring one post more, a tent body counted twice in the stock; Validate passing a share over 1, leaving the tents out of the population, passing a tent on the boss room; Advance clearing a camp with tent stock left; (fix round) Validate judging the posts at the highest difficulty only, Plan's tent door on the wall whatever the kind |
| LevelGeometry | (fix round) TentDoor with no clearance past the wall |

A first "DeadFraction not clamped at 1" was equivalent (the fraction can never exceed 1) and was
replaced. The fix round added three (39 → 42) for B's B-2 and B-4, which the mirrors now follow: Validate
checks the posts at every difficulty (the new refusal "a tent ring post only Normal pushes off its
floor" is refused by both sides, and the Luau before B-2 passed it), and a tent body's door
(`LevelGeometry.TentDoor`, its kind's radius past the marker's wall) is compared in every plan.
"TentDoor past the post" would survive on the shipped data (every door stands short of its post),
so its cap is left to the harness's own TentDoor cases. The driver refuses to judge anything while
the unmutated mirror is red, so a standing DIFF cannot pass for a catch.

### L1b W2: flags for the owner

- **Brutes pay 3 Timber on Forest Road** (6 everywhere else, and in the draft). The contract named
  4. At Ben's 6-second tents, 4 put the fastest seed's Timber a minute over its band.
- **The Main Camp is plated and brute-heavy now:** on Normal it holds 8 plated (draft 2), 20 brutes,
  11 slingers and 5 fodder. Expect it to feel tougher than the Pickets by more than the draft did.
- **The simulator's clears sit near the band's bottom** and swing about ±15 s with the seed. A mix
  change anywhere moves the Main Camp more than its own arithmetic suggests. Re-run all three seeds
  after any change.
- **The human-reaction player is about as fast as the reacting player** (6.5–7.1 against
  7.0–7.3 min on Normal). He takes 11–14 hits where the reacting player dodges.
- **Hard and Brutal clear in about the same 7.1–8.2 minutes as Normal**, because the gear rises with
  them. They pay ×2.2 and ×4.6.
- **The tent keeps sending while the player is out kiting.** It pauses only once the camp is at rest.
  The kite band compares the stock at rest with the stock at his return, as the contract asks. Bodies
  sent during the chase are new survivors, not refills.
- **Not measured:** the crowd step with 110–160 bodies (`[Perf]`, Ben's number) and the phone frame.

### L1b W2: open

- The careless road wakes both road fires and both tents within 47 s. In the simulator nothing
  reaches a player walking at full speed; real play may differ.
- The bow question: 95 s on the Colossus with head shots and 134 s with body shots, against the
  sword's 80 s.

## L1b Wave 3: the bow (2026-10-15)

Contract: `docs/INTERFACES.md` "Wave 3 — the bow" (rulings L1b-W3-1…11: 7–9 win over 1–2, and 10
sets B). Ben, at gear 2 / 2: the
bow is stronger than the sword; "lower the bow's numbers a little". Measured with the new
`py tools/sim_range.py --bow`: Forest Road, Normal, gear 2 / 2, solo, seeds 11 / 23 / 37, the
gate's Python (64-bit 3.12). The time runs from the start point to the Colossus's rise, so the
boss is excluded (L1b-W3-2). The reacting player (policy `mission`) is the band's player. The
human's reaction (0.55 s) is listed for hits taken. "Crits" are hits that landed with the crit
multiplier.

### L1b W3: two simulator changes (`tools/sim_range.py`)

- **A ranged player steps onto the camp's floor before he shoots** (`LevelRun.wanted`,
  `IN_PLAY_STEP` 1). Before this, the Longbow stood 24 studs from its target. In camp B that was
  10 studs outside the fence, where every hit is blocked (L1b-7, damage only from a player in
  play). The group woke, leashed home and woke again for the rest of the run:
  - Body aim never left camp B on any seed (25-minute run cap, 200 blocked hits on `B.fire1`).
  - Head aim got out by luck, at x1.18 of the sword.
  - A real player steps in when his arrows do nothing, so the simulator now does too. The change
    touches only a ranged weapon clearing an open camp. Against `main`'s simulator, with `main`'s
    config, the only `--check` lines that move are the Hard and Brutal "ranged, for information"
    rows (camp A with the Longbow alone at the proving gear): 65–69 s → 64 s and 78–86 s →
    61–62 s. Every band reads the same.
- **Crits are counted** (`World.crits`, filled by `hit(..., crit)`), and the `--bow` mode reports
  them per camp. The mode is information only and is not in `--check`.

### L1b W3: before (Longbow A 50, B 44)

| Weapon, aim | Seed | A (s / hits / crits) | B | C to the boss | To the boss | The Colossus in the run |
|---|---|---|---|---|---|---|
| Broadsword | 11 | 59.8 / 0 / 0 | 154.6 / 0 / 0 | 124.8 / 0 / 0 | 339.3 | 76.7 |
| | 23 | 59.3 / 0 / 0 | 173.7 / 0 / 0 | 124.7 / 0 / 0 | 357.7 | 74.4 |
| | 37 | 59.5 / 0 / 0 | 163.9 / 0 / 0 | 122.1 / 0 / 0 | 345.5 | 74.4 |
| Longbow, body | 11 | 61.1 / 0 / 0 | 122.7 / 0 / 15 | 123.2 / 0 / 11 | 307.0 | 122.9 |
| | 23 | 61.1 / 0 / 0 | 180.7 / 0 / 17 | 122.9 / 0 / 13 | 364.6 | 115.5 |
| | 37 | 61.1 / 0 / 0 | 216.0 / 0 / 15 | 132.4 / 0 / 6 | 409.5 | 120.8 |
| Longbow, head | 11 | 57.7 / 0 / 39 | 148.6 / 0 / 133 | 147.2 / 0 / 122 | 353.4 | 76.7 |
| | 23 | 57.6 / 0 / 37 | 159.0 / 0 / 133 | 153.9 / 0 / 127 | 370.5 | 88.2 |
| | 37 | 58.2 / 0 / 37 | 147.7 / 0 / 131 | 148.0 / 0 / 126 | 354.0 | 79.8 |

| Mean time to the boss | Reacting player | Human's reaction (hits taken per seed) |
|---|---|---|
| Broadsword | 347.5 s | 327.5 s (11, 12, 10) |
| Longbow, body aim | 360.4 s = **x1.037** | 373.6 s = x1.141 (1, 1, 3) |
| Longbow, head aim | 359.3 s = **x1.034** | 358.0 s = x1.093 (4, 4, 6) |

- **Ruling 3 does not stop the tuning:** the head-aim bow is at x1.034, under 1.10 (the band later became x1.05–x1.15 by ruling 7). (`main`'s
  simulator read x1.18, but only because of the stand-off above.)
- **What makes the bow feel stronger.** On the clock it is even with the sword. The bow is much
  safer, though: a human takes 4–6 hits with it against 10–12 with the sword. With head aim it
  also lands about 375 crits a run, and it kills the Colossus in the run as fast as the sword
  does (77–88 s against 74–77 s).
- Camp A takes the same ~58–61 s with any weapon: its tent sends one body every 6 s, and that
  sets the floor of the camp's clear.

### L1b W3: how the cut was chosen (ruling 1, then the lead's amendment, rulings 7–9)

The player in the simulator fires the default variant, A. Each cell is the mean time to the boss
as a multiple of the sword's 347.5 s, by A's damage:

| A's damage | 50 | **45** | 43 | 42 | 41 | 40 | 39 | 38 | 35 | 32 |
|---|---|---|---|---|---|---|---|---|---|---|
| Head aim | x1.034 | **x1.084** | x1.062 | x1.066 | x1.066 | x1.066 | x1.218 | x1.218 | x1.294 | x1.271 |
| Body aim | x1.037 | **x1.128** | x1.095 | x1.186 | x1.186 | x1.186 | never clears B | never | never | never |

**The time does not fall smoothly with the damage.** From 50 down to 40 the head-aim bow barely
slows, for three reasons:
- the tents set A's clear;
- a crit on a head still kills fodder and slingers in one arrow;
- every arrow is still a heavy hit (`crowd.heavyHit` 40).

Below 40 the arrow is no longer heavy, and two things change:
- plates block every body shot;
- the bow can no longer interrupt a brute's lane, an armoured raider's arc or the bosses' heavy
  attacks.

The time jumps from x1.07 to x1.22. The first cut met the contract's first band (x1.10–x1.25) at
**x0.78 (A 39, B 34)**, and the lead rejected it. The record of that rejected cut:
- the body-aim bow never cleared camp B;
- a human with body aim needed x2.94 and hit the run cap once;
- the bosses took the bow 20–67% longer (range Colossus 142.8 → 223.7 s with body aim, 98.2 →
  152.8 s with head aim; the Arrow Rain burst 5.4 s, out of its band).

**What ships: A 50 → 45 (x0.9, ruling 7) and B 44 → 42 (ruling 10).** The band is now x1.05–x1.15
with head aim.
- x0.9 is the largest common cut that keeps a full draw of B heavy: under 0.909, B drops below 40.
- Damage scales with the draw: `minChargeFraction + (1 − min) · charge`, with min 0.5. So an arrow
  is heavy from charge `80 / damage − 1`:
  - A 45 is heavy from 0.78 (was 0.60 at 50);
  - B at 40 would have been heavy only at a full draw (was 0.82 at 44).
- Ruling 10 therefore gives B 2 points over the common factor: **B 42 is heavy from charge 0.90**.
  No level band fires B (the simulator's player fires the default, A), so only the range's B rows
  move.
- The simulator fires only full or minimum draws, so it cannot see these thresholds.

**The sweep is not monotonic** (43 → x1.062, 45 → x1.084, 40–42 → x1.066). The ratio also moves by
about 0.01 between Python 3.12 and 3.14: on 3.14, 32-bit, head aim reads x1.092. The PASS sits
inside seed noise, so read it as "about 8%", not a measured 8.4%.

A hit at exactly 40 counts as heavy. The code compares with `>=` (a plate blocks only
`amount < heavyHit`):
- `src/combat/server/Services/CrowdService.luau:1926`: `if amount < crowd.heavyHit then` (the plate
  block);
- `src/combat/server/Services/CrowdBrain.luau:1006`: `(rule == "heavy" and amount >= heavyHit)` (the
  interrupt);
- `tools/sim_range.py` mirrors both (lines 1962 and 2027).

### L1b W3: after (Longbow A 45, B 42)

B is never fired in a level, so these are the same at B 40 and B 42.

Each camp cell: seconds / hits taken / crits landed.

| Weapon, aim | Seed | A | B | C to the boss | To the boss | The Colossus in the run |
|---|---|---|---|---|---|---|
| Broadsword | all | unchanged | | | 339.3 / 357.7 / 345.5 | 76.7 / 74.4 / 74.4 |
| Longbow, body | 11 | 63.2 / 0 / 0 | 180.7 / 0 / 16 | 150.6 / 0 / 5 | 394.5 | 132.3 |
| | 23 | 63.2 / 0 / 0 | 166.0 / 0 / 13 | 142.3 / 0 / 7 | 371.4 | 134.4 |
| | 37 | 62.1 / 0 / 0 | 208.9 / 0 / 14 | 138.9 / 0 / 9 | 409.8 | 140.7 |
| Longbow, head | 11 | 57.7 / 0 / 39 | 167.5 / 0 / 146 | 156.4 / 0 / 134 | 381.6 | 96.6 |
| | 23 | 57.6 / 0 / 37 | 156.9 / 0 / 138 | 154.2 / 0 / 126 | 368.8 | 88.2 |
| | 37 | 58.2 / 0 / 37 | 162.4 / 0 / 138 | 159.0 / 0 / 129 | 379.6 | 80.9 |

| Mean time to the boss | Reacting player | Human's reaction (hits taken per seed) |
|---|---|---|
| Broadsword | 347.5 s | 327.5 s (11, 12, 10) |
| Longbow, body aim | 391.9 s = x1.128 (reported) | 407.7 s = x1.245 (4, 7, 2) |
| Longbow, head aim | **376.6 s = x1.084** (band 1.05–1.15: **PASS**) | 372.4 s = x1.137 (6, 8, 6) |

- The bow is still the safer weapon, with 2–8 hits against the sword's 10–12. It is now a little
  slower on the clock in every column, where before it was even.
- The Colossus in the run with head aim: 81–97 s (was 77–88).

### L1b W3: the bosses with the Longbow (ruling 4: reported, not tuned)

The `slay` player, abilities off, seeds 11 / 23:

| Boss, where | Aim | Before (50 / 44) | After (45 / 42) | Rejected x0.78 (39 / 34) |
|---|---|---|---|---|
| Colossus, the range (P4 scales) | body | 142.8 s | 161.2 s | 223.7 s |
| | head | 98.2 s | 113.9 s | 152.8 s |
| Warlord, the range | body | 162.2 s | 182.2 s | 199.3 s |
| | head | 102.9 s | 116.5 s | 125.7 s |
| Colossus, Raider Arena at 2 / 2 | body | 134.9 s | 154.4 s | 220.5 s |
| | head | 97.6 s | 108.1 s | 163.3 s |
| Warlord, Raider Arena at 2 / 2 | body | 154.4 s | 173.8 s | 208.9 s |
| | head | 105.0 s | 117.6 s | 125.8 s |

- At 45 / 42 the bosses take the bow 11–16% longer. These rows fire A, so B 40 or 42 reads the
  same.
- No boss lands a hit in any row.
- Every melee boss band is unchanged and green.

### L1b W3: re-banded rows (ruling 5)

None at 45 / 42. In `sim_range.py --check` the Arrow Rain burst measures 4.6 s (was 4.2), inside its
default band [3.0, 5.0]. The per-ability override that the x0.78 cut needed ([3.0, 6.0] for 5.4 s) is
removed.

These Longbow rows move with the damage and stay green without a re-band:
- the family DPS, single / crowd:
  - A 48 / 279 → 43 / 251;
  - B 80 / 182 → 76 / 174 at 42 (73 / 165 at 40);
- the P4 Longbow boss rows above.

The loadout's thinning stays at 4.8 kills/s.

The plate list is the same as `main`'s: the Longbow still breaks plates on its own. The Warlord row
with the Longbow alone still finds a way through with no ground slam (guard down at 86.6 s, plate
broken at 96.1 s).

### L1b W3: the Raider Arena at 2 / 2

Its section of `--check` is line for line the same as before the cut, because everything in it is
melee:
- the Colossus alone 76.8 s, the Warlord 97.7 s;
- standing still in wave 1, down at 11.0–11.1 s;
- clears at 10.19, 10.35 and 11.97 min with no hit;
- the worst hit 23.2%.

### L1b W3: flags for the lead

- The bow's damage sits near `heavyHit` 40:
  - B (42) has 2 in hand and is heavy from a 90% draw;
  - A (45) has 5 in hand and is heavy from a 78% draw.

  Any later cut to the bow, or any raise of `heavyHit`, moves those draws. PLAYTEST should say: "B
  is heavy from a 90% draw, A from 78%".
- The in-play step is a simplification of the game's rule. The simulated bow walks 1 stud inside
  the floor rectangle, while the game already counts a player within `chaseMargin` 2.5 outside it.
  So the simulated bow is a little less safe than a real one.
- `--check` pins the step: on Normal the Longbow alone clears camp B on every seed (244 / 229 /
  271 s). Without the step it stood off camp B until the run cap.
- What made the bow feel stronger was mostly safety. Ruling 9: if Ben still finds it stronger, the
  next lever is its range or how far off it lets him stand, which is a question for Ben.

## L1b Wave 4: no waits, no walls (2026-10-15)

Contract: `docs/INTERFACES.md` "L1b Wave 4 — no waits, no walls". Measured with the gate's Python
(64-bit 3.12, `py tools/sim_range.py --check`), Normal at gear 2 / 2 (Broadsword, the reacting
`mission` player, solo) unless a row says otherwise. Seeds 11 / 23 / 37.

### L1b W4: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `Combat.json camps.chaseSight` | — | 40 | The study's value held. 36 and 32 lose the walk-out at once (the fodder never leave the gate); 38 and 40 both turn the group at the U-bend. See "the lose" below. |
| `camps.hitMemorySeconds` | — | 8 | The study's value; no band moved it. It is what pulls a group after an archer it cannot see. |
| `camps.meleeAbove` | — | 7.5 | The top of its gate's range [7, 7.5]: max(cover 3.5, fence 4) + root 3, and the rushers' lowest ground height 5 − 0.5 + 3. |
| `levels.regionLockMargin`, `levels.doorSpare` | — | 8, 0.5 | Fixed by the contract. |
| `1_ForestRoad.json` A `tent.pace` | — | 15 s, lead 0.2 (fix round: 12 s, 0.2) | Chosen from the residents' own kill curve (tents silenced, scratch probe): at 2 / 2 the Pickets are never 0.2 ahead of a 15-s clock (worst 0.09–0.17), at 4 / 4 they are (0.29–0.32) for long enough to send 2. |
| B `tent.pace` | — | 90 s, lead 0.15 (fix round: 35 s, 0.2) | Main Camp is busy 100–135 s at 2 / 2 (never ahead of 90 s) and 50–55 s at 4 / 4 (ahead from about 1 min in: 7, 7, 8 sent). The study's 130 s would send at 2 / 2 on a fast seed. |
| `targetMinutes` | 7 | 6 | Wave 1's rule: the mean first Normal clear, 6.26 min, rounded. |

`runCapSeconds` 1,500 holds: the human's slowest Normal clear is 6.04 min (724 s doubled), and 1,500 ≥ 1,260.
No resident, stock, `every`, reward, weapon, kind or `ProvingGrounds.json` number moved.

### L1b W4: the region

One region, `plateau`, y 8, camps A and B; 15 cells (floors first, then the road cells in file order):

| Cell | x | z | Door(s) |
|---|---|---|---|
| A floor | −264 … −179 | −58.5 … 26.5 | Road5 8 × 16, RoadAB1 8 × 16 |
| B floor | −70 … 71 | −64.5 … 68.5 | RoadAB5 8 × 16, RoadBC1 8 × 16 |
| Road5 | −302 … −256 | −52 … −36 | LookoutSignPad 6 × 6 |
| LookoutSignPad | −302 … −296 | −62 … −46 | |
| RoadAB1 | −187 … −122 | −52 … −36 | RoadAB2 16 × 16 |
| RoadAB2 | −138 … −122 | −52 … 8 | RoadAB3 16 × 16 |
| RoadAB3 | −138 … −100 | −8 … 8 | RoadAB4 16 × 16 |
| RoadAB4 | −116 … −100 | −52 … 8 | RoadAB5 16 × 16 |
| RoadAB5 | −116 … −62 | −52 … −36 | |
| RoadBC1 | 63 … 128 | −52 … −36 | CacheSpur 12 × 6, RoadBC2 16 × 16 |
| CacheSpur | 94 … 106 | −42 … −10 | CacheSignPad 6 × 8 |
| CacheSignPad | 100 … 112 | −34 … −26 | touches RoadBC2 (no door) |
| RoadBC2 | 112 … 128 | −52 … 8 | RoadBC3 16 × 16 |
| RoadBC3 | 112 … 198 | −8 … 8 | RoadBC4 16 × 16 |
| RoadBC4 | 182 … 198 | −52 … 8 | |

- The tree has 14 doors for 15 cells; the narrowest is 6 (the minimum is 2 × 2.2 + 0.5 = 4.9).
- Every crossing of a fence line is inside a gate span (z −52 … −36 at all four gates).
- The lock clearance: the tightest is RoadBC3 and RoadBC4, 58 studs from the Chief's Clearing (needs
  the marksman's 48 + 8 = 56). RoadBC5 (x 198 … 230) is outside the region.
- Sniper perches (in the band, over `meleeAbove`, within `dormantRadius`): the lookout ledge (its
  farthest point 14 studs from the region) and the cache block (12), both inside the slinger's 32.
  The Chief's Clearing's fence tops and its cover block are listed but not gated: see the flags.
- N's stops: A (−322, 0, −44), 55.8 studs past the nearest resting sight; B (−108, 8, −44), 39.7
  past it (Hard's B.fire1); then the Chief's countdown.

> **Superseded for camp C by L1c** (below): C's fence tops and cover are no longer perches: the fence is a 64-stud unclimbable wall (L1c-3), and C's cover is inside it.

### L1b W4: the first clear

| Seed | Clear | A cleared | B cleared | C closed | the Colossus | Timber / min | cash / min |
|---|---|---|---|---|---|---|---|
| 11 | 6.37 min | 35.6 s | 182.2 s | 202.9 s | 73.2 s | 40.5 | 24,337 |
| 23 | 6.42 min | 34.4 s | 188.9 s | 210.2 s | 74.2 s | 40.2 | 24,134 |
| 37 | 5.99 min | 33.1 s | 154.2 s | 175.4 s | 75.9 s | 43.1 | 25,891 |

- Mean 375.6 s, inside the stop rule's 360–405 s and the band 345–420 s. About 45 s of it is walking
  (908 studs). Every run took 0 hits and paid 155,020 cash, 258 Timber, 10 Valor (229 kills; the
  tents send nobody at this pace).
- The human's reaction (0.55 s) clears in 5.46 / 6.04 / 5.62 min with no down.

### L1b W4: the tents

| Run | A sent | B sent |
|---|---|---|
| Normal 2 / 2 (band: at most 1) | 0, 0, 0 | 0, 0, 0 |
| Normal 4 / 4 (band: A ≥ 2, B ≥ 4) | 2, 2, 2 (at 16 and 22 s) | 7, 7, 8 (from 62–69 s, 6 s apart) |
| Hard 4 / 4 (at most 1) | 0, 0, 0 | 0, 0, 0 |
| Brutal 6 / 6 (at most 1) | 0, 0, 0 | 0, 0, 0 |

Nobody waits: in every `mission` run each open camp clears on the tick its last body falls (0.00 s
from the last body's fall; the last resident was the last body in every run at pace).

### L1b W4: the chase scenes (Normal, 2 / 2)

- **The walk-out**: out of A's east gate at 6.1 s; a woken rusher stands on RoadAB1 2.40–2.70 s later
  (band ≤ 5 s).
- **The lose** [draft band 60–110 studs, back home healed within 25 s]: A.fireN follows him out and
  turns home with its farthest body 109 / 108 / 108 studs past A's east edge, at rest 12.1 s later,
  healed. A.fireW (woken by the join-in) never knew him and went home at once, from inside A. The
  turn always falls at the U-bend (RoadAB3): sight is flat and all round, so a fodder on RoadAB2 sees
  him on RoadAB4 across the 22-stud void and keeps the chase alive until he leaves the bend.
- **The road archer** (Longbow from Road5, sees only through the west gate): every hit lands. The
  Pickets fall in 60 s with no hit on him (30–32 kills, 6,600–7,480 cash); on two seeds bodies came
  out of the gate first (7.3 s, 4.7 s), on the third the bow felled them in the gate's funnel.
- **The sniper** (one arrow through the gate, then below the drop, then the lookout ledge): every hit
  lands; he clears the Pickets in 25–27 s and earns 16,183–17,565 cash and 22.3–24.2 Timber a minute
  of his own time, against the mission's 24,134–25,891 and 40.2–43.1 (band: less of both, every
  seed). **Corrected in the fix round:** that "about 70%" came from a script that idled 10 s below
  the drop before it climbed. A straight course to the ledge earns about 1.4 times the mission's cash
  a minute (see "L1b W4 fix round: the sniper"). Below the drop he takes 1,500–1,600 cash before nothing is in sight; the rushers come to the
  lip and leash (2–3 leashes). On the ledge the Longbow kills A's rushers (Normal's are fodder) before
  any could stand down, so the stand-down is not seen in this run (the mirror's Step timeline proves
  the rule).
- **The kite**: out with 27 alive, at rest again 17 s later, all whole, the dead still dead.
- The sneak wakes nobody; the still player is down 6.9–7.2 s after the wake; every first strike lands
  first; the join-in matches the chain table.

### L1b W4: pay

- The clear bonus on what each camp fielded: Normal A 660, B 5,700, C 4,660 cash = 7.1% of the run's
  cash (Wave 2's band 5–10%); Hard 7.3%, Brutal 7.4%. `sim_combat.py --check` 21: Normal 155,287
  cash, 258 Timber, 10 Valor; Hard x2.25 / x2.21, Brutal x4.63 / x4.53 (bands x2–x3, x4–x6); the
  bonuses 11,020 cash = 7.1%.
- Hard 4 / 4 and Brutal 6 / 6: every band holds (no hit over 30%; the Colossus alone 83.2 s and
  86.1 s; the human clears with no down; the never-dodger does not; one preset below is clearly
  beyond; under-gearing pays less a minute).
- The Raider Arena: unchanged (Colossus 75.4–77.7 s, Warlord 96.9–98.4 s, clears 10.14 / 10.44 /
  11.84 min, the worst hit 23.2%).

> **Superseded for camp C by L1c** (below): the pay and bonus figures above are the old clearing's.

### L1b W4: how the simulator models it

- `LevelRun` clamps a region body into the union of its inset cells (`rg_clamp`), routes every goal
  through `rg_toward` (a door at stop 0; a goal clamped to the edge keeps
  `max(stop − |goal − clamped|, 0)`), cuts a lane by `rg_runway`, stamps `closing` for a thinking
  rusher that walked, lets a stood-down rusher finish an attack it began, and runs the forget before
  the camp step's `Step` at the close (A's notes 1–4).
- The scenes use the simulator's only line of sight: a camp's fence (less its gates) and the
  plateau's lip block a straight line from his chest to a body's head. Nothing else in the
  simulator, and nothing in the game's crowd, is ray-blocked.
- `check_stage_mirror.py` compares `Region`, the Wave 4 `CampBrain` and `StageFlow.Fielded`, Plan's
  regions and approaches, Validate's 20 new refusals (and the two new `levels` keys) and N through both approaches;
  `mirror_mutants.py` catches 79 of 79 Luau mutants (31 new for Wave 4, 8 re-aimed).

### L1b W4: flags for the lead

- **The lookout ledge sniper is fast.** From the ledge the Longbow (pierce 5, range 110) clears the
  Pickets in about 25 s with no hit taken, at about 70% of the mission's cash a minute and 57% of its
  Timber (**wrong, corrected in the fix round:** the course idled below the drop; straight, it is
  about 1.4 times the mission's cash a minute). It passes ruling 10's band, but by less than the old blocks did. Normal's A has only fodder
  rushers, so nothing stands down on the ledge before it dies. Levers, if Ben finds it cheap: more
  shooters in A, a slinger reach that covers the ledge from further, or the bow's pierce. None is
  mine to move.
- **RoadBC5 and the step to C stand outside the region** (the lock clearance stops it at x 198). From
  RoadBC6 (y 12, 32 studs past the region) no raider of B can reach him and no slinger can answer;
  bounded by no refills, as the study says. Not gated: the sniper-perch gate covers tops over
  `meleeAbove` only.
- **The perch gate skips the boss room's own pieces.** C's fence tops (16) and a cover block (15.5)
  stand 57–86 studs from the region, in the band and over `meleeAbove`, and are out of every slinger's
  reach. Read literally the gate fails on them; they are the "Shooting out of the boss room" item of
  "Open for later", so `check_levels.py` lists them and does not gate them. The lead's ruling.
> **Superseded for camp C by L1c** (below): C's fence is now an unclimbable wall, so it is no longer standable; the boss-room list in the perch row is empty.

- **The lose band is tight at its top** (108–109 against 110), because the turn happens at the
  U-bend whatever `chaseSight` is (see above). A wall-aware sight (A, L4) would end it earlier.
- **The archer and the sniper's stand-down are reported, not gated**: the Longbow kills Normal's A
  before the rushers can reach the gate or stand down on two of the three counts. Every hit landing
  (the gated part) holds in every run.

## L1b W4 fix round (2026-10-16)

Rulings: `docs/prompts/l1b-w4-fix-round.md`. Same gate, Normal at gear 2 / 2, seeds 11 / 23 / 37.

### L1b W4 fix round: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `Combat.json camps.meleeBelow` | — | 1.5 | R14 (A's value). It must lie in [0, min(`sightBelow` 4, the lowest rusher ground height 5 − root 3 − cover margin 0.5)] = [0, 1.5]. That is a new `check_levels` gate. A step down of up to 4.5 studs (feet) stays melee-reachable. The foot of the climb (feet 8 under) does not. |
| A `tent.pace` | 15 s, lead 0.2 | 12 s, 0.2 | R7 restarts the measure whenever the whole camp is at rest. A player who wipes one group before waking the next restarts it once per group, so every later group looks like a fresh, small camp that is easy to be "ahead" of. Under 15 / 0.2, at 2 / 2 the tent sent 1–2 (band ≤ 1). Under 12 / 0.2 it sends 1, 1, 1; at 4 / 4 it sends 2, 2, 2. |
| B `tent.pace` | 90 s, 0.15 | 35 s, 0.2 | Under R7, 90 / 0.15 sent 4–8 at 2 / 2 and 0–8 on Hard (band ≤ 1). A grid of 27 settings (seconds 15–90, lead 0.05–0.4) never made B send 4 at 4 / 4 without also sending 2 or more at pace. 35 / 0.2 sends 0 at pace on every difficulty and 3 at 4 / 4. |
| `sim_range.py TENT_FAST["B"]` (contract band "B at least 4") | 4 | 3 | Follows from the line above. Accepted by the lead (2026-10-16): "the tent when fast: B at least 3". |

No resident, post, stock, `every`, reward, weapon, kind or `ProvingGrounds.json` number moved.
The resident posts tried for R8 below were scratch experiments and are not shipped.

### L1b W4 fix round: the mirrors

- `sim_range.py` mirrors the round's rules:
  - **R1:** `closing` is progress against `goal_gap`, kept by every seek. A rusher seeks inside its reach too, as `Think` gives it.
  - **R2:** home rests only when no member strikes.
  - **R4:** the heal latch.
  - **R5:** `lane_runs`.
  - **R6 and R15:** `in_band` with both bounds, from the strike's floor, for queued shapes, charges and rings.
  - **R7:** `TentClock` with `rested` (`stirred()`, once per tick) and `NewTent` counting residents.
  - **R9:** heights are measured from the crowd's floor: `stand_y + feet − floor_y`, the planner included. A keepAway retreat is routed through `rg_toward`.
  - **R10:** `SafePoint` ignores `busy` for a region zone, and `Threatening` counts home.
  - **R12:** `fielded(…, refused)`. The tent books refused stock indices and never prices them. `sim_combat.level_pay` takes `refused` too.
  - **R14:** `Melee`'s `meleeBelow`, and `reaches` in `begin`. `begin` now walks the next choice when an attack is turned down, as the Luau's loop does, chained attacks included.
- `check_stage_mirror.py` adds four cases:
  - the tent timeline with R7's restart and WaveService's `Ahead` call;
  - `meleeBelow` at both edges, plus four `Problems` lines;
  - a home group all at its posts that rests only once nobody strikes;
  - `Fielded` with `refused` (300 compared) and `Threatening`.
- `mirror_mutants.py` gains 11 mutants: R2, four R7, three R14, R12, two R10. The stale "Melee ignores meleeAbove" mutant is re-aimed at `above <= rules.meleeAbove`. R1, R4, R5, R6 and R15 live in modules that `check_stage_mirror` does not run, so `mutate.py` holds their mutants (A's texts).
- **R16** (Melee on the surface last stood on): `cb_melee` reads the target's `rest` (CrowdBrain's `restY`; `LevelRun` passes its ground plus the track's `restY`), the band and the region distance still read the live root. `check_stage_mirror` adds the mid-hop and mid-jump rows (floor 8: root 10 / rest 3 not melee, root 21 / rest 11 melee) and an R16 Step timeline; `mirror_mutants.py` catches 91 of 91. `sim_range.py --check` output is identical line for line to the run before R16: no band moved.

### L1b W4 fix round: the first clear

| Seed | Clear | Cash / min | Timber / min | Kills | Paid |
|---|---|---|---|---|---|
| 11 | 6.51 min | 23,835 | 39.6 | 230 | 155,130 cash, 258 Timber, 10 Valor |
| 23 | 5.98 min | 25,946 | 43.2 | 230 | same |
| 37 | 6.49 min | 23,891 | 39.7 | 230 | same |

- The mean is 6.33 min, inside the band of 5.75–7 min.
- With a human's reaction, the clears take 5.43 / 5.59 / 5.61 min, with no down.
- The Colossus falls in the run in 72.5–74.8 s.
- Hard 4 / 4 clears in 6.36–6.78 min. Brutal 6 / 6 clears in 6.44–6.89 min.
- The clear bonuses are 7.1% of the run's cash on Normal, 7.3% on Hard and 7.4% on Brutal.
- `sim_combat.py --check` passes all 23 assertions.

### L1b W4 fix round: the tents

| Run | A sent | B sent |
|---|---|---|
| Normal 2 / 2 (band: at most 1) | 1, 1, 1 | 0, 0, 0 |
| Normal 4 / 4 (band: A ≥ 2, B ≥ 3) | 2, 2, 2 | 3, 3, 3 |
| Hard 4 / 4 (at most 1) | 0, 0, 1 | 0, 0, 0 |
| Brutal 6 / 6 (at most 1) | 0, 0, 1 | 0, 0, 0 |
| **R7, the checklist's order at 4 / 4** (band: A sends in the clear) | 1, 1, 1 | — |

The checklist's order means the walk-out, the lose, every group home and at rest by 31.6–32.3 s, then back in through the east gate and a clear of the Pickets, which stops at 51–53 s. With R7 switched off in a scratch run (`rested` always false), A sends 0, 0, 0 in that clear, so the band fails without the rule. A fresh 4 / 4 clear without R7 sends A 1 (band ≥ 2).

### L1b W4 fix round: the cliff and the foot of the climb

- **R6's `check_levels` gate.** A rusher's ground shape can reach a cell's edge by its flat reach less the body's radius: fodder lunge 3.9, armoured arc 5.8, brute lane 0.3. The gate asks that no standable ground below the region lie within that distance where the shape's height rule still holds while the player there is out of melee reach.
  - It passes on Forest Road.
  - With the under side switched off (`UNDER_SIDE = False`), it fails at Road4 (x −307 and −305): the foot of the climb.
- **The foot of the climb (Road4) as a sniper spot.** He earns 1,067–1,601 cash a minute and takes 2–3 hits from the lip's shooters. No lunge lands through the cliff.
- **The bosses (R14's `reaches`).** Every Colossus and Warlord band holds.
  - The reacting Broadsword kills the Colossus in 76.3 s (Warhammer 83.0, Spinblade 71.0, Greataxe 75.3, Spear 63.8), with no hit taken.
  - It kills the Warlord in 97.7 s (95.1 / 89.8 / 92.9 / 79.1).
  - Standing still, the player is down in 8.6 s (Colossus) and 9.0 s (Warlord).

### L1b W4 fix round: the sniper (R8)

`check_levels` lists every standable top where no rusher can reach a player (`CampBrain.Melee` is false) and that lies within the Longbow's 110 studs of the plateau region. The list is pinned (11 spots), and boss-room pieces are left out as before.

`sim_range` runs a straight course from each spot:
- He starts on the road by the camp's gate nearer the spot.
- If a resident can be seen from the spot, he goes straight there. Otherwise one arrow wakes them first.
- He crosses to the spot in a straight line at walk speed 20. A climb or a double jump costs no extra time.
- He then shoots until no hit has landed for 10 s.
- His minutes run to his last landed hit, and never less than his arrival plus 10 s. A course that ends in a down is timed to the down.

Cash and Timber a minute, seeds 11 / 23 / 37, against the `mission` player on the same seed, both at 2 / 2:

| Spot | Normal cash / min | Normal Timber / min | Hard cash / min | Hard Timber / min | Verdict |
|---|---|---|---|---|---|
| `mission` | 23,835 / 25,946 / 23,891 | 39.6 / 43.2 / 39.7 | 19,646 / 20,835 / 20,229 | 30.0 / 32.1 / 30.8 | — |
| Road2 | 17,286 / 6,649 / 6,649 | 26.6 / 8.9 / 8.9 | 17,730 ×3 | 26.6 ×3 | pass |
| Creek | 0 | 0 | 0 | 0 | pass |
| ShrineSignPad | 0 | 0 | 0 | 0 | pass |
| Road3 | 22,957 / 11,938 / 11,938 | 32.1 / 13.8 / 13.8 | 13,535 / 18,365 / 18,365 | 17.5 / 27.5 / 27.5 | pass (seed 11 at 96%) |
| Road4 (the foot of the climb) | 1,601 / 1,067 / 1,067 | 0 | 0 | 0 | pass |
| **LookoutLedge** | **33,664 ×3** | **44.1 ×3** | 18,313 / 17,756 / 15,846 | 9.6 / 17.8 / 9.9 | **Normal: known limit, L4 (reported)** |
| LookoutSignPad (the strip) | 13,494 ×3 | 15.6 ×3 | 7,306 / 10,025 / 12,457 | 0 / 9.1 / 8.3 | pass |
| RoadBC5 | 0 | 0 | 0 | 0 | pass |
| RoadBC6 | 0 | 0 | 0 | 0 | pass |
| **Secret_lookout** (top 38) | **39,541 / 41,395 / 41,395** | **53.7 / 56.2 / 56.2** | 11,218 / 11,412 / 5,397 | 10.2 / 10.4 / 0 | **Normal: known limit, L4 (reported)** |
| **Secret_cache** (top 18) | **27,153 / 23,702 / 24,236** | **42.7 / 36.9 / 40.5** | 0 | 0 | **Normal: known limit, L4 (reported)** |

- **The ledge and the lookout on Normal.** He kills 29–31 of the Pickets' residents within 11 s of arriving and takes no hit. Normal's slingers die in the first volleys: the Longbow's pierce 5 and blast go through fire circles and the watch line.
  - Tried: the watch group (4 slingers) moved to stand within 13 studs of the ledge (shift −40, −70). The ledge then earned 28,145 / 38,266 / 35,566, the lookout 38,951–41,395, with 0–2 hits on him.
  - The other data levers in R8 do not touch this spot. `sightAbove` only lets shooters answer once they are within reach. The cells cannot bring a rusher 26 studs up.
  - On Hard the residents live long enough to shoot. He is down within 12–14 s and earns less than the mission.
- **The cache on Normal.** From the cache top (one jump up from CacheSpur) he shoots B's east side at rest. B's shooters answer: 8–10 hits, and he is down by 20–23 s on two seeds. Brutes and armoured are worth so much that 6–7 kills before the down beat the mission's minute.
  - Tried: the eastWatch line moved back 25 or 40 studs, and eastFire moved to the east gate (dx +10, dz −50).
  - Results: 15,828–38,486, 24,359–38,033 and 29,039–46,317 a minute. The noise was larger than the effect, and the band was never green on every seed.
  - On Hard he is down in 12–14 s with no kill.
- **The other spots never pay.** Road2 and Road3 sit 38–47 studs below and off the region. Their pay is the opening arrow into a sleeping fire circle (14 kills) and the rushers he can see at the lip. Nothing can be seen from the Creek, ShrineSignPad, RoadBC5 and RoadBC6. RoadBC6's lure (the review's Minor 1) did not bring B's group into his sight within the course.
- **The levers left are not data.**
  - The Longbow's pierce or blast is a weapon number, and every boss is tuned on it.
  - Moving the ledge would move the double-jump secret.
  - A sight rule that blocks the lip and fences for the crowd and the bow is L4's wall-aware sight.
  - The lead asks Ben.

**Ben's ruling (2026-10-16): accepted for L1, fixed in L4.**
- On Normal at 2 / 2, the LookoutLedge, Secret_lookout and Secret_cache snipers out-earn the mission: ×1.0–1.7 its cash a minute.
- Camps never refill, so a sniper's total pay is bounded by what the camp fields. The spot only clears a camp faster; it does not farm it.
- `sim_range.py` reports those three Normal rows as "known limit, L4" (`SNIPER_KNOWN_LIMIT_L4`) and gates only that every hit of his lands. Every other spot, and every Hard row, stays gated. `check_levels`' spot list stays pinned.
- L4 re-places the perches. The gate must pass on every spot, with `SNIPER_KNOWN_LIMIT_L4` empty, before L4 ships.

## L1c: the Chief's Clearing redone (2026-10-16)

Contract: `docs/prompts/l1c-contract.md` (its §8 holds the lead's rulings); Ben's decisions:
`docs/MISSIONS_DESIGN.md` §21. Same gate as L1b: Normal at gear 2 / 2, Hard 4 / 4, Brutal 6 / 6,
seeds 11 / 23 / 37.

### L1c: what changed, and why

> **Superseded in part by the second fix round** (below): C's entry is (313.5, −23), the route
> 1,074 studs and the sneak 1,051; the Colossus rises 84 studs from the entry.

| Key | Was | Now | Why |
|---|---|---|---|
| Layout: camp C | (313.5, 12, −44), gates west / east, fence 4 | (313.5, 12, 31.5), gates **north** (at 0) / **east** (at −41.5), **fence 64** | L1c-1 / L1c-2. The wall's top (y 76) is 3.5 over the highest camera (60.49 over the floor, below). C's west edge stays at x 256, which keeps the region's lock clearance (RoadBC3 58 from C, needs 56). |
| Layout: the gatehouse | — | `GatehouseWalk` (x 256…321.5, z −52…−36), `GatehouseTurn` (x 305.5…321.5, z −36…−26), four `wall` blocks (N, S, E, W) | L1c-2. One turn, 16 wide. The walls run from y 0 to 76 (the contract's y 12…76, taken down to the road blocks' foot so no wall floats over the drop; the tools read only the top). |
| Layout: C's residents' spots | gate, chiefFire, north, south; a tent marker | **ambushW**, **ambushE** (guard, one row at z −22.5, facing the entry, ∓98°); no tent marker | L1c-2 / L1c-4. The innermost post stands 32 studs off the gate's centreline (contract: at least 30). The brutes stand outside the fodder: the sight margin is set by the body nearest the centreline, and a brute is the wider body. |
| Layout: C's spawns, checkpoint, cover | — | spawns (313.5, 75), (265, 75), (362, 75), (362, 40); checkpoint (313.5, −6); cover 18 × 12 at (340.5, 20) and 12 × 8 at (285.5, 34) | L1c-2. Spawns 74+ studs from the entry, cover out of the flank lanes, 3.5 high. |
| Layout: route and sneak tails | …(262, −44) → (365, −44) camp | …(313.5, −44) → (313.5, −16) → camp → (361, −10) | Through the gatehouse. The route is 1,079 studs (band 900–1,100); the sneak ends at the new entry. `TrailEnd` moved to (379, −10), on the east gate's lane. Parts 82 → 86. |
| Level: C's residents | 36 / 38 / 38 (gate, chiefFire, north, south) | **ambushW, ambushE: 2 fodder + 3 brutes each, + 1 brute each from Hard** = 10 / 12 / 12 | L1c-4 and its band (below). |
| Level: C's stage | 3 waves (about 35, about 35, the Colossus at [14, 0]) | `[{groups: []}, {groups: [], boss: colossus at [0, 30]}]` | L1c-4: the empty wave 1 clears when the last ambusher falls, then `breatherSeconds` 3 and the Colossus, 78 studs from the entry. |
| `crowd.rewards.colossus.cash` | 29,000 | **41,000** | L1c-7 and the lead's ruling: keep cash a minute. |
| `targetMinutes` | 6 | **5** | L1c-7. `sim_combat` 21: the mean clear is 5.1 min. |
| `check_levels.py` | — | the unclimbable-wall rule, the reach-based beside rule, the walled-camp gate, `lockedResidents` (8, 12) at every difficulty (the fix round: per difficulty, Normal 8–10), the two gatehouse floors in the pinned sniper list | L1c-3, L1c-6 (below). |
| `sim_range.py` | clear band 345–420 s | **270–345 s**; the ambush band (`FOREST_AMBUSH_SECONDS`); colliding `wall` blocks cut scene sight lines; the sniper list reads the unclimbable rule | L1c-7, contract §5. |

**The one departure from the contract's mix.** The contract's Normal ambush (4 fodder + 1 brute a
side) is killed in 12.0–12.7 s, under the lead's band of 15–35 s. Moving two fodder to brutes on
Normal (2 + 3 a side) gives 20.4–22.2 s. The Hard-only unit stays the contract's brute, so Hard and
Brutal field 4 fodder + 8 brutes. The ambush then pays 7,600 more cash a Normal clear than the
contract's mix, so Normal's cash a minute ends 4% over L1b's. Measured before settling:

| Variant (each side; Hard adds) | Normal ambush | Hard 4 / 4 ambush | Hard at 2 / 2: mission cash a minute, seed 11 | Normal cash a minute |
|---|---|---|---|---|
| The contract: 4 F + 1 B, + 1 B; Colossus 41,000 | 12.0–12.7 s: **fails** | 17.1–19.7 s | — | 23.6–26.1k |
| 3 F + 2 B, + 1 F; Colossus 41,000 | 15.2–18.0 s (15.2 at the floor) | 15.4–17.6 s | — | 23.9–26.9k |
| 2 F + 3 B, + 1 F; Colossus 37,000 (cash a minute held to L1b's) | 19.6–20.6 s | — | **17,921** (16.51 min) against the LookoutLedge sniper's 18,313: **fails** | 23.8–26.5k |
| **2 F + 3 B, + 1 B; Colossus 41,000 (shipped)** | **20.4–22.2 s** | **26.4–26.7 s** | **19,063** (16.18 min): +4.1% | **24.6–26.7k** |

- Why the Hard-at-proving-gear row binds: at 2 / 2 on Hard the Colossus takes about five minutes
  and pays 2 × its cash, the slowest money in the run; L1b's two big waves paid faster. The R8 gate
  compares that player with the LookoutLedge sniper on Hard (18,313 cash a minute: a burst of 12–15
  kills in 12 s before he is stood down). The shipped mix holds it by 4.1%.
- That row is noisy: the same data gives seed 11 14.6 or 16.5 minutes depending on which runs went
  before it in the process, because the long 2 / 2 Colossus fight swings by about ±10%. The numbers
  here are the gate's own run (`sim_range.py --levels-only --level forest --check`).

### L1c: the walled camp (`check_levels.py`)

- **The highest camera** (L1c-1), read from the files: feet at the double jump's peak 30 + root 3 +
  Leap Smash's lift 10 + pivot 1.5 + shoulder 0.6 + the boom at `maxZoom` 16 and pitch −70°
  (15.04) + shake 0.35 = **60.49** studs over the surface it took off from. Theme's three numbers
  are parsed from `src/client/UI/Theme.luau`; a missing one fails the gate.
- **Unclimbable** (L1c-3): a `wall` block or a camp fence whose top stands at least jump + double
  jump + the highest ability lift + `STEP_UP` = **43** over every standable surface within
  `stray_reach` (46.6) of it. C's four fence strips and the four gatehouse walls are; A's and B's
  4-stud fences are not. An unclimbable wall is not ground for the fence-height rule (C's fence is
  exempt from "at most triggerHeight − 3"), the band, the beside rule, the sniper spots and the perch gate.
- **Beside** now counts only solids within `stray_reach` of the fenced rectangle, and skips the
  path blocks that run through the camp's own gates (`TrailEnd`, `GatehouseTurn`).
- **The walled gate** (`EXPECTED.ForestRoad.walled = ["C"]`):

| Rule | Shipped |
|---|---|
| Height: fence ≥ the highest camera + 3 | 64 ≥ 63.49 |
| Every wall block within 46.6 of the fenced rectangle is as tall as the fence | 4 of 4 at y 76 |
| No plated resident at any difficulty (L1c-6) | 12 posts, none plated |
| Floors: from every outside surface the highest camera stays under the wall's top, or its line over the top passes over the tallest body (the Colossus, 14) across the whole floor | under the top: the highest is RoadBC6, 3.51 under; over it: Secret_lookout (camera 98.5, 536 off), whose line meets a head 1,191 studs past the wall |
| Sight in plan: eye points every 2 studs on every outside top a player reaches without entering C; camera points within `maxZoom` + 2 of one, outside every wall and locking camp, whose boom no wall cuts; targets the bodies (centre ± radius) at every post, every difficulty | 6,207 eye and 6,499 camera points, 12 posts. **Tightest margin +1.31 studs**: the camera at (306, −30), 3 studs short of the north fence in leg 2, to Brutal's innermost east fodder |
| The doorway (within 2.5 of the fence in a gate's lane) is exempt | the glimpse there: −1.64 at (306, −28) to a Brutal east brute (accepted by the contract) |

> **Superseded by the L1c fix round** (below): the sight row's "+1.31" was a 2-stud grid value against the
> radius, and the doorway exempted camera points too. The client now keeps the camera `levels.cameraClear`
> 3.5 off the fence; only eyes are exempt; near the gates the points are fine and exact at the corners; the
> target is the drawn torso. The Floors row now also measures to each gatehouse wall.

- "Floors" departs from the contract's literal "every standable surface within 200 studs at or
  under the floor's y": the cache secret (top 18, 149 studs off) would fail it, while its line over
  the wall cannot fall to a head for 1,000+ studs. The shadow form above is what the literal rule was
  for, and it still fails a 40-high tower 53 studs off (the mutant below).
- Reach for the eye points is a graph over standable tops (a jump, double jump and dash between them,
  at most 43 up, walls ignored): `TrailEnd`, behind the exit, is not reached (50.1 from the turn).
- Sight is exact in plan because every wall is over every camera; each point's view through a gate is
  the angular window of the gate's two faces less every wall's shadow, and a body's margin is its
  perpendicular distance to the nearest visible ray less its radius.

> **Superseded by the L1c fix round** (below): these mutants are now committed and re-run by
> `py tools/check_levels_mutants.py`, with the fix round's own cases.

**Every new rule red on a mutated copy** (in memory; 0 failures on the shipped data):

| Mutation | Rule that fails |
|---|---|
| C's fence 40 (climbable) | the fence-height rule (no longer exempt) |
| GatehouseWallW top 50 (climbable) | the band |
| GatehouseWallN top 50 (climbable) | the pinned sniper list (it becomes a spot) |
| a ledge 9 studs east of the floor, off the gates | beside (a ledge 58 off stays green: the reach filter) |
| `TrailEnd` moved off the east gate's lane | beside |
| C's fence 60 (still unclimbable) | walled: height (60 < 63.49) |
| GatehouseWallS top 70 (still unclimbable) | walled: the gatehouse |
| a 40-high tower 53 studs north of the fence | walled: floors |
| GatehouseWallE removed | walled: sight (the boom reaches past leg 2 and sees through the north gate) |
| the innermost east fodder moved to 16 off the centreline | walled: sight |
| an armoured added to ambushW on Hard | walled: plates |
| 3 more fodder in ambushW on Hard (15) | `lockedResidents` (8–12 at every difficulty) |

### L1c: the first clear (Normal, 2 / 2)

| Seed | Clear | The ambush | The Colossus | Cash / min | Timber / min | Paid |
|---|---|---|---|---|---|---|
| 11 | 5.27 min | 20.4 s | 77.1 s | 24,578 | 38.9 | 129,510 cash, 205 Timber, 10 Valor |
| 23 | 4.86 min | 22.2 s | 80.5 s | 26,666 | 42.2 | same |
| 37 | 5.12 min | 21.7 s | 77.7 s | 25,285 | 40.0 | same |

- Mean clear **5.08 min** (L1b: 6.33). Band 4.5–5.75 min (270–345 s), re-measured: 15 s under the
  fastest seed and 28 s over the slowest, the same shape as L1b's band.
- Cash a minute 24.6–26.7k (L1b 23.8–25.9k, +4%); Timber a minute 38.9–42.2 (band 37.8–46.2).
- With a human's reaction: 4.24–4.35 min, no down. The sneak still wakes nobody (1,047 studs to the
  entry). The tents, the kite, the lose, the walk-out and the first strikes are unchanged.
- The clear bonuses are 5.9% of the run's cash (C's is now 1,240); `sim_combat` 21: 5.8% (band 5–10%).
- `sim_combat.py --check`: Normal 130,133 cash, 205 Timber, 10 Valor; Hard 289,360 (×2.22), 455
  Timber; Brutal 578,720 (×4.45), 909 Timber; `targetMinutes` 5 against a mean clear of 5.1 min; all
  23 assertions hold.

> **Superseded by the L1c fix round** (below): C's gate now shuts on the step in (`gateSeconds` 0); the
> clear, ambush, Hard, Brutal and sniper rows were re-measured there.

### L1c: Hard and Brutal

| | Clear | The ambush (band ≤ 60 s) | The Colossus | Cash / min |
|---|---|---|---|---|
| Hard 4 / 4 | 5.22 / 5.54 / 5.32 min | 26.5 / 26.7 / 26.4 s | 78.9–80.4 s | 51.8–55.1k |
| Brutal 6 / 6 | 5.27 / 5.57 / 5.30 min | 26.4 / 26.6 / 26.7 s | 80.8–84.5 s | 103.1–109.8k |
| Hard at 2 / 2 (one preset below) | 16.18 / 15.07 / 15.86 min | — | — | 19,063 / 20,549 / 19,586 |
| Brutal at 4 / 4 (one preset below) | 9.85 / 10.22 / 10.70 min | — | — | — |

- The human clears Hard in 4.83–5.02 min and Brutal in 4.80–5.07 min, no down. One preset below he
  still goes down or takes ×2.77 (Hard) and goes down (Brutal); the Colossus alone one preset below
  is not killed inside 240 s (Hard) and takes 215.4 s (Brutal). Every L1b band holds.

### L1c: the sniper (R8)

The gatehouse adds two spots to the pinned list, `GatehouseWalk` and `GatehouseTurn` (13 spots).
Both pay 0–1,648 cash a minute on Normal and 0 on Hard: the gatehouse walls cut every line to B
(`sim_range` now counts colliding `wall` blocks as scene walls). Neither needs `SNIPER_KNOWN_LIMIT_L4`.
Every other row is as in the L1b W4 fix round, against the new mission rates: Normal 24,578 /
26,666 / 25,285 cash and 38.9 / 42.2 / 40.0 Timber; Hard at 2 / 2 19,063 / 20,549 / 19,586 cash and
28.1 / 30.2 / 28.7 Timber. The tightest gated rows: Hard LookoutLedge cash 18,313 against 19,063
(+4.1%), Hard Road2 Timber 26.6 against 28.1 (+5.6%). The three Normal known limits stand
(LookoutLedge up to ×1.37 the mission's cash a minute, Secret_lookout, Secret_cache).

### L1c: flags for the lead

- **The Normal mix and the cash a minute** (above): 2 fodder + 3 brutes a side instead of 4 + 1,
  for the 15–35 s band; Normal pays 4% more a minute than L1b. The lead's Colossus 41,000 is what
  keeps the Hard-at-2/2 sniper row green; 37,000 would hold Normal's minute exactly and fail that row.
- **The Hard-at-2/2 R8 rows are the thinnest gate here** (+4.1%), and they move with the
  simulator's run order (about ±10% on the 2 / 2 Colossus). Judge any later change to C's pay on the
  gate's own run.
- **Leap Smash onto a wall top** (contract §7, ruled in §8): not a data matter; the tools already
  count the 10-stud lift in the camera's height and in "unclimbable".
- **Not gated:** the Colossus is not a resident, so the sight gate does not see it; it rises after
  the close, when nobody fighting is outside.

## L1c fix round (2026-10-16)

Rulings: `docs/prompts/l1c-fix-round.md` (findings in `docs/prompts/l1c-review/code.md` and
`data-tools.md`). Same gate as L1c: Normal 2 / 2, Hard 4 / 4, Brutal 6 / 6, seeds 11 / 23 / 37.

### L1c fix: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| C's stage `gateSeconds` (level file) | none (`levels.gateSeconds` 3) | **0** | M3: stepping in shuts the gate and the ambush rises in the same step; no 3 s of statues. `StageFlow` reads a stage's own countdown, `sim_range` mirrors it (and the same-step close, and a skip's), and both refuse one under 0 or not a number. |
| `check_levels.py` sight gate | doorway exempted eyes **and** cameras; 2-stud grid; target = radius | the client's camera clip (`levels.cameraClear`, read from Combat.json); only eyes in the doorway exempt; near each gate a 0.25 grid, every region edge at 0.05 and every corner exactly; target = the drawn torso, radius × 1.151 (CrowdRenderer's `TORSO_WIDTH` 1.9 × `TORSO_DEPTH` 1.3, read from the file) | C1 and m1. |
| `check_levels.py` Floors | the line over the fence only | over the fence **and** every gatehouse wall as tall within `stray_reach` + the boom of the fenced rectangle, the camera up to 7.57 nearer the wall than its surface | m4: a line over a gatehouse wall falls through the open gate, not over the fence. |
| `check_levels.py` `lockedResidents` | (8, 12) at every difficulty | Normal (8, 10), Hard and Brutal (8, 12) | m3: Ben's "8 to 10". |
| `check_levels.py` a stage's own `gateSeconds` | — | 0 or more; under `levels.gateSeconds`' floor of 1 only on a first wave with no group and no boss, in a camp whose residents stand on its floor | M3: the floor of 1 is there so the client learns a floor before its first body; C's bodies are residents, drawn from the run's start. |
| `sim_range.py` `FOREST_AMBUSH_SECONDS` | Hard / Brutal (0, 60) | **(15, 60)** | m5: an ambush that never happened would have read 0 s and passed. |
| `tools/check_levels_mutants.py` | the 12 mutants were run in memory | committed, 28 cases plus the stage-mirror case | m6. |

### L1c fix: the walled camp's sight, re-measured

**The camera model the gate now holds the layout to** (the client after C1):
- An eye (a root) outside the clip, the fenced rectangle grown by `cameraClear` 3.5: its camera is
  anywhere within `maxZoom` + 2 = 18 its boom reaches past no tall wall, but never inside the clip.
  The shake (0.35) can move a clipped camera that far in, so the gate keeps cameras **3.15** off the
  fence; and the spherecast's radius (0.5) less the shake keeps them 0.15 off any wall.
- An eye inside the clip but not inside the fence: the boom starts inside the clip, so the camera comes
  to the head (`WallClip.Reach` answers 0). That camera is the eye, judged with it.
- Only eyes in the doorway (within 2.5 of the fence, in a gate's lane) are exempt. Before, cameras there
  were too, and the client let a camera into the gate's mouth from a root 9 to 15 studs back (C1).

| What | Shipped (`cameraClear` 3.5) |
|---|---|
| Points | 16,448 eyes (1,599 inside the clip), 8,040 camera points on the 2-stud grid and 30,089 fine ones near the gates, 12 posts |
| **Tightest eye** (superseded: the margin ruling below, +1.57) | **+0.23 studs**: (305.51, −29.51), just outside the doorway against WallW's face, to Brutal's innermost east fodder (the west side mirrors it: (321.49, −29.51), +0.23) |
| **Tightest camera** (superseded: +2.73) | **+1.20 studs**: (305.66, −30.15), the corner of the clip and WallW's stand-off, to the same fodder |
| The doorway glimpse (exempt eyes) | −2.53 at (305.51, −27.75) to a Brutal east brute |
| Floors | under every top: the highest camera is RoadBC6's, 3.51 under; over one: Secret_lookout (camera 98.5) over the fence, its line meets a head 1,012 studs past the floor's far corner |

- The old "+1.31" was a 2-stud grid value against the radius. On the same data the 2-stud grid with the
  radius reads +1.93 for eyes (the `m1` control below shows that gate passing a layout this one fails).
- (Superseded by the margin ruling below.) The eye margin, +0.23, is the one to watch: a post moved toward the gate's sight line by about a
  quarter of a stud, or a wider body at the innermost post, turns it red. It is measured against a root
  standing flush on the wall's face; a real root stands about a body's width off it.

**`py tools/check_levels_mutants.py`** (every case below as expected; the shipped data green; about
5 minutes):

| Case | Rule | Expected |
|---|---|---|
| The 12 L1c mutants (above) and the control ledge 58 off | as listed above | red / control green |
| `levels.cameraClear` 0.2 (2a58134's client) | walled: sight (and "at least the shake") | red |
| `levels.cameraClear` 2 (over the shake, under a body's width) | walled: sight | red |
| `levels.cameraClear` missing | walled: the sight gate reads its numbers | red |
| control: 0.2 with cameras exempt in the doorway (2a58134's gate) | walled: sight | green: that gate was blind to C1 |
| ambushE's two inner fodder 0.8 studs off the north wall | walled: sight | red |
| control: the same on the 2-stud grid, radius only (2a58134's gate) | walled: sight | green: that gate was blind to m1 |
| CrowdRenderer's torso keys missing | walled: the sight gate reads its numbers | red |
| 11 residents on Normal | `lockedResidents` | red |
| a ledge (top 20) 4 studs north of GatehouseWallN | walled: Floors | red |
| control: the same ledge measured to the fence alone (2a58134's rule) | walled: Floors | green: that rule was blind to m4 |
| `gateSeconds` 0 on a first wave that brings bodies | a stage's own countdown | red |
| `gateSeconds` −1 | a stage's own countdown, and Validate's mirror | red |
| control: `gateSeconds` 0.5 on the shipped (empty) first wave | a stage's own countdown | green |
| m2: the "residents under the boss room's maxAlive" rule taken out of **both** `StageFlow.luau` and `sim_range.py` (copies) | `check_stage_mirror.py` "the boss room's residents at its maxAlive: accepted on both sides" | red |

### L1c fix: the clear, re-measured

> **Superseded by the margin ruling** (below): the posts moved, Hard's extra unit is a fodder and the
> Colossus pays 42,900 cash and 76 Timber; every row here was measured again there.

| Normal 2 / 2 | Clear | The ambush | Cash / min | Timber / min |
|---|---|---|---|---|
| seed 11 | 5.28 min | 19.0 s | 24,714 | 38.9 |
| seed 23 | 4.73 min | 19.0 s | 27,438 | 43.3 |
| seed 37 | 5.07 min | 19.7 s | 25,542 | 40.4 |

| | Clear | The ambush (band 15–60 s) | Cash / min |
|---|---|---|---|
| Hard 4 / 4 | 5.11 / 5.43 / 5.28 min | 22.9 / 22.9 / 25.3 s | 52.8–56.3k |
| Brutal 6 / 6 | 5.16 / 5.48 / 5.24 min | 22.9 / 22.9 / 25.4 s | 105.3–112.1k |
| Hard at 2 / 2 (one preset below) | about 14.3–15.3 min | — | 18,808 / 20,118 / 19,775 |
| Brutal at 4 / 4 (one preset below) | — | — | 57,034–60,274 |

- The ambush is 1–3 s shorter on Normal (19.0–19.7 s against 20.4–22.2) and 1–4 s shorter on Hard and
  Brutal (measured: the gates now shut, and the simulated player is put on the entry point, the step he
  comes in, instead of 3 s later wherever he has walked to). Every band holds: Normal 15–35 s, Hard and Brutal 15–60 s.
- Normal's mean clear is 5.03 min (L1c 5.08); band 4.5–5.75 min unchanged. Pay per clear unchanged
  (129,510 cash, 205 Timber, 10 Valor). `sim_combat.py --check`: all 23 hold, `targetMinutes` 5 against a
  mean clear of 5.0 min, bonuses 5.8%.
- The human clears Normal in 4.25–4.28 min, Hard in 4.82–5.08 and Brutal in 4.84–5.06, no down. One
  preset below he still goes down (Hard at 2 / 2: Pickets 1.43 min, Main Camp 7.46 min, or ×2.92 on seed
  37; Brutal at 4 / 4: Pickets in under a minute); the Colossus alone one preset below is not killed in
  240 s (Hard) and takes 215.4 s (Brutal).
- **R8 on Hard at 2 / 2 is thinner on this run:** LookoutLedge 18,313 cash a minute against the mission's
  18,808 (+2.7%; L1c's run read +4.1%), Road2 26.6 Timber a minute against 27.3 (+2.6%; was +5.6%). Nothing
  in this round changes Hard at 2 / 2 but the 3 s countdown, which makes the mission faster, not slower:
  the difference is the run-order swing on the long 2 / 2 Colossus that L1c's flags describe. Green, and
  the thinnest gate in the forest.
- The gatehouse spots still pay 0–1,648 cash a minute on Normal and 0 on Hard. The three Normal known
  limits stand (LookoutLedge up to ×1.36 the mission's cash a minute).

### L1c fix: the margin ruling (2026-10-16)

The lead's ruling: +0.23 is too thin for "can't see them from outside". Animation, swinging arms
and held weapons reach past the torso box. Every eye's and every camera's margin must be at least
the camp's own **`sightMargin` 1.5** (layout key on camp C; check_levels reads it and types no
number). Mutants (in `check_levels_mutants.py`, all as expected):
- the innermost fodder back on its old post: red;
- `sightMargin` 2: red;
- `sightMargin` missing: red;
- Hard's extra unit a brute again: red;
- control, the inner fodder 0.05 off the wall: green.

**A fourth brute a flank has no hidden post.** The constraint:
- Through the north gate, the eye at the doorway's edge (305.51 or 321.49, −29.51) looks along a line
  that rises 0.219 studs south per stud east.
- A guard post stands its group's widest radius + 1 inside the floor: z ≥ −22.8 and x ≤ 367.8 (east).
- So the hidden band, at margin 1.5, is a sliver along the north wall:
  - a brute fits from x 355.0, with z up to −22.77 + 0.218 (x − 355);
  - a fodder fits from x 350.0 at z −22.8.

It holds:
- two fodder, three brutes 4.9 apart, and one more body only behind and between the last two brutes;
- that sixth post fits a fodder (4.0 from each brute) but never a brute (4.9).

So Hard and Brutal's extra unit per flank is now a **fodder** (it was a brute). Moving only the posts
cannot meet 1.5 with L1c's mix: the best sixth post for a brute reads eye +0.64, and fails post spacing.

**The pay.** A fodder for a brute on Hard took 12 Timber and 7,600 cash out of a Hard clear. That
turned R8 red: Hard Road2's sniper made 26.6 Timber a minute against the mission's 26.4 on seed 11,
and LookoutLedge's cash was +0.3%. Those two brutes' pay moves into the boss, so the run pays as before:

| Key | Was | Now |
|---|---|---|
| ambushW and ambushE posts (layout) | x 345.5–367.7 (east), all at z −22.5 | east 350.4, 353.5 (fodder), 357.5, 362.4, 367.6 (brutes) at z −22.8, and (365, −19.7) for Hard's extra; the west mirrors them round x 313.5 |
| Hard and Brutal's extra unit per flank | brute | **fodder** |
| `crowd.rewards.colossus` | 41,000 cash, 70 Timber | **42,900 cash, 76 Timber** |
| camp C `sightMargin` (layout) | — | **1.5** |

**Measured:**

| Gate | Value |
|---|---|
| check_levels: tightest eye | **+1.57** (321.49, −29.51) to the innermost west fodder (the east mirrors it) |
| check_levels: tightest camera | **+2.73** (305.66, −30.15) |
| Normal ambush | 18.4 / 18.4 / 18.7 s |
| Hard ambush | 21.3 / 21.8 / 18.0 s |
| Brutal ambush | 21.3 / 21.8 / 18.9 s |
| Normal 2 / 2 clear | 5.21 / 4.67 / 5.04 min, mean 4.97 |
| Normal 2 / 2 cash a minute | 25,208 / 28,121 / 26,094 |
| Normal 2 / 2 Timber a minute (band 37.8–46.2) | 40.5 / 45.2 / 41.9 |
| Normal pay a clear | 132,033 cash, 211 Timber |
| Hard 4 / 4 | 5.11–5.48 min; 282,620–284,800 cash (×2.16), 454 Timber |
| Brutal 6 / 6 | 5.09–5.50 min; ×4.31 cash |
| R8, Hard at 2 / 2 | Road2 26.6 Timber a minute against 27.2 (+2.3%); LookoutLedge 18,313 cash against 18,592 (+1.5%) |
| The human | clears every difficulty, no down; one preset below still goes down |
| `sim_combat` 21 | green: bonuses 5.8%, Hard ×2.16, Brutal ×4.31 |

The R8 Hard rows are now the thinnest gates in the forest (+1.5% cash). The run-order swing that
L1c's flags describe is about ±10%, so a future change to C's pay or the 2 / 2 Colossus must be judged
on the gate's own run.

## L1c second fix round (2026-10-16)

Rulings: `docs/prompts/l1c-fix2.md` (findings F1–F4 in `docs/prompts/l1c-review/fix-diff.md`). Same
gate: Normal 2 / 2, Hard 4 / 4, Brutal 6 / 6, seeds 11 / 23 / 37.

### L1c fix 2: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| Camp C `entry` (layout), the route point before C's camp leg and the sneak path's end | (313.5, −16) | **(313.5, −23)** | F2: with `gateSeconds` 0 the close runs in the step the root first stands in the trigger rectangle (the fence band, z −27 to −26), which is always outside `inner` (z ≥ −24), so the close moves it to the entry. −23 is the nearest the entry may stand: `closeInset` 2 + `check_levels`' `CLOSE_SPARE` 1 inside the floor. |
| `sim_range.trigger_ceiling` (new), plan zones' `ceiling`, `LevelFlow.triggered` | a root triggers up to `levels.triggerHeight` 30 | a locking camp whose fence is over `triggerHeight` triggers up to its fence's top (C: **64**); every other camp 30; checkpoints keep 30 | F1 and F3: mirrors `StageFlow.Ceiling` and `triggered` exactly. |
| `check_levels.py` walled camp: the trigger's ceiling | — | the ceiling stands over the highest root a player gets in the fenced rectangle: the highest standable surface within `stray_reach` (the unclimbable walls are none) + jump 18 + double jump 12 + the highest ability lift 10 + root 3 | F1 and F3: a root inside the rectangle has always triggered, a fighter inside keeps his boom at the top of any jump, and the doorway exemption's "one more step triggers" holds at every height. Switch `WALLED_CEILING` for the mutants. |
| `check_levels_mutants.py` | 33 cases + m2 | 36 cases + 3 stage-mirror cases (m2 and two for F1) | Below. |

**F2 cannot be met by data.** The lead's bound was "moved under 1 stud". A root first seen in the fence
band is at least 3 studs outside `inner` (fence 1 + `closeInset` 2), and the entry must stand inside
`inner` (StageFlow.Plan refuses the level otherwise), so no entry point moves it under 3. With the entry
at −23, a root first seen on the trigger line (z −27) moves:
- 4.0 studs in the lane's centre (was 11.0);
- up to 8.9 at the edge of the 16-wide opening (was 13.6), because the entry is one point;
- and, since F1, a root up to 46.5 over the floor (a double jump plus Leap Smash in the opening) now
  triggers and is put on the floor: a drop of up to 43.5 studs.

Under 1 stud needs code (the lead's call): either the close moves a fighter in a gate's lane only to the
nearest point of `inner`, keeping X and the height (3.0 studs on the line, 0 lateral), or a 0 s camp
triggers on `inner` itself (no move at all, but the fence band and the 2-stud strip become a 3-stud
mouth that does not trigger, so the sight gate's doorway premise would have to be restated for it).

### L1c fix 2: measured

| Gate | Value |
|---|---|
| check_levels: the trigger's ceiling | 64 over the floor against the highest root 46.5 (C's cover, 3.5): **+17.5** |
| check_levels: tightest eye / camera | **+1.57 / +2.73** (unchanged; sightMargin 1.5); the exempt doorway glimpse −2.53 |
| Route / sneak | 1,074 studs (was 1,079; band 900–1,100) / 1,051 (was 1,058) |
| C: the Colossus from the entry / the nearest spawn | 84 studs (was 78) / 80 (was 74) |
| Normal ambush (band 15–35 s) | 16.4 / 16.4 / 18.9 s (was 18.4 / 18.4 / 18.7) |
| Hard / Brutal ambush (band 15–60 s) | 19.0 / 19.0 / 21.0 s; 19.0 / 19.0 / 19.0 s |
| Normal 2 / 2 clear (band 4.5–5.75) | 5.16 / 4.64 / 5.09 min, mean 4.96 |
| Normal 2 / 2 cash / Timber a minute (band 37.8–46.2) | 25,460 / 28,321 / 25,935; 40.9 / 45.5 / 41.4 |
| Hard 4 / 4 | 5.03–5.36 min; 282,400–285,020 cash |
| R8, Hard at 2 / 2 | Road2 26.6 Timber a minute against 27.5 (+3.4%; was +2.3%); LookoutLedge 18,313 cash against 18,685 (**+2.0%**, still the thinnest; was +1.5%) |
| One preset below | Hard at 2 / 2: down in Pickets 1.43 min, Main Camp 7.46 min, or ×2.89; Brutal's Colossus alone at 4 / 4 214.1 s |
| The human | clears every difficulty, no down |
| `sim_combat` 23 | green: Normal pays 131,767 cash, bonuses 5.8%, Hard ×2.16 |

The simulated player is now put 7 studs nearer the gate at the close. The ambush is 2–3 s shorter on
most seeds and up to 3 s longer on one (Hard seed 37: 18.0 to 21.0 s); every band holds. Pay per clear
moves only by the extra kills a seed happens to take (Normal seed 37: 143 kills, 132,110 cash, against
136 and 131,410).

**`check_levels_mutants.py`, new cases** (all as expected; 36 data cases and 3 stage-mirror cases, about 6
minutes):

| Case | Rule | Expected |
|---|---|---|
| C judged at `levels.triggerHeight` 30 (`WALLED_CEILING` off: the first fix round's rule) | walled: the trigger's ceiling | red (30 under 46.5) |
| C's first cover 22 high: a root 65 over the floor (over 21 the cover is also a step onto the walls: 64 = 21 + 43) | walled: the trigger's ceiling | red |
| control: C's first cover 21 high, a root 64 at the fence's top | walled: the trigger's ceiling | green |
| `sim_range`'s trigger asks `triggerHeight` again (Python alone) | `check_stage_mirror` "StageFlow.Advance: scripted runs" | red (12 of 20) |
| `sim_range.trigger_ceiling` ignores the fence (Python alone) | `check_stage_mirror` "StageFlow.Ceiling" | red (3 of 12) |

## L1c third fix round (2026-10-16)

Rulings: `docs/prompts/l1c-fix3.md` (findings m1–m3 in `docs/prompts/l1c-review/fix2-diff.md`). Same gate:
Normal 2 / 2, Hard 4 / 4, Brutal 6 / 6, seeds 11 / 23 / 37, `py tools/sim_range.py --check` on the gate's
64-bit Python 3.12.

### L1c fix 3: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `StageFlow.GateNudge` / `sim_range.gate_nudge` | a root in a gate's lane (the opening held to `inner`'s span) is moved along the gate's normal onto `inner`'s edge; any other root outside `inner` goes to the entry | **any** root in the fenced rectangle, in the trigger's band, goes to the nearest point of `inner` (X and Z each held to it, height kept: at most 3 on an axis, 4.24 at a corner); only roots outside the fenced rectangle go to the entry. `Zone.lanes`, `StageFlow.Lanes` and `gate_lanes` are gone | m3: a diagonal dash first sampled in the strip beside the opening was in no lane and was sent to the entry, about 10 studs sideways |
| Camp C `entry` (layout), the route's last two points before C's camp leg, the sneak path's end | (313.5, −23); route through (313.5, −44) | **(309.5, −16)**; route through **(309.5, −44)** | m2: a road player placed on the entry in the same close as a nudged one landed 1 stud from him. Every nudge lands on `inner`'s edge (z −24 on the north side), so the entry now stands 8 inside it, 4 off the lane's centre line |
| `check_levels.py` | — | locking camp: "the close's nudge lands clear": the entry and every obstacle (and tent) stand `NUDGE_CLEAR` 3 inside the inset rectangle's edge | m2 and m3 |
| `check_levels_mutants.py` | 36 data cases, 3 stage-mirror cases (one stale, m1) | 41 data cases, 4 stage-mirror cases | m1 re-anchored on `self.rules["triggerBelow"] <= above <= zone["ceiling"]`; new cases below |

**Why x 309.5, not 317.5.** Both are 8 inside the nudge line and 4 off the lane's centre. At 317.5 the gate's
64-bit run turned R8 red on Hard: seed 11's mission player made 26.5 Timber a minute against Road2's sniper
26.6, because the route's last leg moved and seed 11's clear came out about 4% slower (the 32-bit
interpreter passed the same data). At 309.5 the row is 27.4 against 26.6. (313.5, −16) and (313.5, −18) gave
27.5, the second round's number, since the nudge, not the entry, decides where the simulated player starts
the fight.

### L1c fix 3: measured

| Gate | Value |
|---|---|
| check_levels: the nudge lands clear | entry **8** inside the inset edge, nearest cover 19.5 (needs 3) |
| check_levels: tightest eye / camera | +1.57 / +2.73 (unchanged) |
| Route / sneak | 1,079 studs (band 900–1,100) / 1,059 |
| C: the Colossus from the entry / the nearest spawn | 78 / 77 studs |
| Normal ambush (band 15–35 s) | 20.0 / 19.6 / 20.1 s |
| Hard / Brutal ambush (band 15–60 s) | 21.6 / 18.7 / 17.7 s; 21.6 / 18.7 / 19.9 s |
| Normal 2 / 2 clear (band 4.5–5.75) | 5.26 / 4.69 / 5.04 min |
| Normal 2 / 2 cash / Timber a minute | 25,104 / 28,041 / 26,091; 40.1 / 45.0 / 41.9 |
| Hard 4 / 4 | 5.11–5.33 min; 282,400–285,020 cash |
| Brutal 6 / 6 | 5.10–5.36 min; 564,800–570,040 cash |
| R8, Hard at 2 / 2 | Road2 26.6 Timber a minute against 27.4 (**+3.0%**); LookoutLedge 18,313 cash against 18,614 (**+1.6%**, the thinnest) |
| One preset below | Hard at 2 / 2: down in Pickets 1.43 min, Main Camp 7.46 min, or ×2.94; Brutal's Colossus alone at 4 / 4 211.2 s |
| `sim_combat` 23 | green: Normal pays 131,733 cash, bonuses 5.8%, Hard ×2.15, Brutal ×4.32 |

**`check_levels_mutants.py`, new cases** (all as expected):

| Case | Rule | Expected |
|---|---|---|
| C's entry back at (313.5, −23), 1 inside the inset edge | the nudge lands clear | red |
| C's entry at (309.5, −22), 2 inside | the nudge lands clear | red |
| control: (309.5, −21), exactly 3 inside | the nudge lands clear | green |
| C's first cover at x 358, 2 off the inset east edge | the nudge lands clear | red |
| control: the same cover at x 357, 3 off | the nudge lands clear | green |
| `sim_range.gate_nudge` without its fenced-rectangle test (Python alone) | `check_stage_mirror` "StageFlow.GateNudge" | red (392 of 2,700) |

## L2 W1: the bought double jump and the lookout (2026-10-17)

Contract: `docs/prompts/l2-w1-contract.md` (L2-6, L2-13, L2-17, L2-18, L2-20). Same gate as L1c fix 3:
Normal 2 / 2, Hard 4 / 4, Brutal 6 / 6, seeds 11 / 23 / 37, `py tools/sim_range.py --check` judged on the
gate's 64-bit Python 3.12 (the 32-bit run gives the same verdict).

### L2 W1: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `Expeditions.json abilities.list` | — | `doubleJump`, "Double Jump", **10 Valor**, order 1 | L2-6. One solo Normal clear pays exactly 10 (the Colossus's 10 × rewardMult 1): the first clear buys it. A duo splits the boss's Valor by damage share, so about two clears each (L2-24) |
| `Expeditions.json looks.secretOpen` | — | SmoothPlastic (240, 190, 40) | L2-14: a found chest, gold. `check_levels` holds it to the colour looks |
| `Combat.json levels.secretReach / secretBelow / secretAbove` | — | **5 / 1 / 9** | L2-11. Standing on the ledge the root is 3 over the chest's foot, on the chest 7; on Road5 it is −23, at the top of a jump from there −5 |
| `Combat.json debug` | — | `DebugGrantAbility`, `DebugRemoveAbility`, `DebugResetSecrets` | L2-19, the three Workspace levers |
| `1_ForestRoad.json secrets` | — | lookout: **3 Valor, 50 Timber, the Flamethrower**; cache and shrine: a name only | L2-13. 50 Timber is 24% of a first clear's 211 (band 15–30%); 3 Valor is at least 2 and under the price, so the chest never buys its own key |
| `ForestRoad.json` (the lookout notch, L2-17) | — | **not built**; the ledge and the chest are as L1c left them (chest at z −59) | The notch does not close the Leap route, and the formula change that does close it makes the notch unneeded (below). Sniper pins, Parts (86) and the route are unchanged |
| `check_levels.py` | the lookout band and one-jump test | L2-18 (a)–(e), abilities, secret numbers, levers, `secretOpen` | below |
| `sim_range.py` | — | `airJump` on every reacting policy; `take_off`; the first-run gate; the chest gate; Resolve/Validate mirror of `secrets`; "owners only" sniper rows | L2-20, L2-13 |

### L2 W1: the first run (Normal, 2 / 2, one jump)

| Gate | Value |
|---|---|
| First run: the human (0.55 s reaction), one jump | **4.23 / 4.25 / 4.31 min**, 0 downs, 8 / 10 / 8 hits taken, 104–130 damage |
| The reacting player (unchanged) | 5.26 / 4.69 / 5.04 min, 0 hits |
| One jump (L2-20) | Normal 78 runs, Hard 18, Brutal 18: all `airJump` False, **0** jumps asked for in the air |
| What a first clear pays | 131,300–131,410 cash, **211 Timber, 10 Valor** |
| Double Jump | **10 Valor = one solo Normal clear** |
| The lookout's chest | 50 Timber = **24%** of the clear, 3 Valor (30% of the price) |

**The first-run band is 4.0–5.75 min, not the contract's 4.5–5.75.** The human clears 0.2–0.5 min sooner than the
reacting player on every seed with the same kills and pay: his slower reaction leaves him standing and swinging
where the ideal player steps aside. Nothing changed with the double jump: the simulator never modelled one, its
dodges use `jumpHeight` alone, and the new `take_off` count proves it (0 in every run). Slowing the human into
the old band would need a camp or weapon change, which the contract rules out.

The simulator now refuses a timed jump that a knock's launch overtook (nobody jumps off the air without the
double jump). No number moved: every Normal, Hard and Brutal line is identical to L1c fix 3.

### L2 W1: the lookout and every lifting ability (L2-18 c)

`check_levels.py` models every family's lifting ability worst case (today: the Greataxe's Leap Smash, height
10, castRange 32), not today's loadout: take-offs on every standable top within reach, on the ground, at the
top of one jump, and off each top's edge at a jump's top (with an air dash); targets as `GroundPoint` finds
them; the arc as `MovementController.Leap` flies it. Take-offs from which some arc puts the feet within a step
up (3) of the ledge's top, over it. The table is the study **before F1 + F2**: its first row is `main`
before e39215b, not the code that ships, which is the last row (`LIFT_MODEL "floor"`, 0 routes).

| Lift model (before F1 + F2) | The shipped ledge | With the contract's notch |
|---|---|---|
| **Before F1 + F2** (`LIFT_MODEL "today"`): apex = height over the higher of the root and the target; over a void the caster's floor is his feet | **937** | **429** |
| F1 alone: apex = height over the higher of the target and the caster's floor | 443 | 159 |
| F2 alone: over a void the caster's floor is his feet less his jump rise (18) | 653 | 258 |
| **F1 + F2** | **0** | **0** |

Two holes, neither closed by geometry:
- **Off a void.** Jump off Road4's or Road5's edge (an air dash carries him on), and at the jump's top
  `GroundPoint` takes his feet (18 or 26) as his floor, so the ledge's top (34) is within 18 and a legal target.
- **At a jump's top.** The leap adds its 10 over an airborne root: 26 + 10 = 36 feet, over the ledge. Aimed at the
  sky over the notch's walls, the target is pulled back to castRange over the void behind them and sits level with
  his floor (legal); the arc crosses the ledge's open face at feet 36 and drops onto the ledge. With the notch, 164
  take-offs are at a jump's top over a standing surface (the sign pad among them), not off an edge.

**Not a W1 risk:** every mission is played with Broadsword and Longbow (`ProvingGrounds.json loadout`), neither
lifts, so `check_levels` reports the routes as a known limit until W2 (`LIFT_KNOWN_LIMIT_W2`) and goes red the
moment a lifting family can enter a level. With F1 + F2 the margin is camp A's fence: a target on its top (12)
lifts an arc to 12 + height, so the lookout holds up to a Leap height of 18 (mutants at 18 green, 20 red).

### L2 W1: the sniper (R8)

No layout change, so `sniperSpots` and the perches are as L1c left them. The Normal known limits stay: the
LookoutLedge row (up to ×1.34 the mission's cash a minute) and Secret_lookout (×1.59) are now labelled "owners of
doubleJump only", since nobody without it stands there. Hard at 2 / 2 is unchanged: LookoutLedge 18,313 / 17,756 /
15,846 cash a minute against the mission's 18,614 / 20,512 / 19,397 (the thinnest, +1.6%); Road2 26.6 Timber
against 27.4 (+3.0%). `sim_combat.py --check`: 23 of 23.

**`check_levels_mutants.py`, new cases** (25, all as expected; 66 data cases and 4 stage-mirror cases in all):

| Case | Rule | Expected |
|---|---|---|
| today's Leap Smash, the known limit off | L2-18c | red (40+ take-offs) |
| a Greataxe in the loadout | L2-18c | red |
| control: the floor model (F1 + F2), the known limit off | L2-18c | green |
| Leap height 24 / 20 under the floor model | L2-18c | red / red (a target on A's fence) |
| control: Leap height 18 under the floor model | L2-18c | green |
| a ledge (top 14) west of the sign pad | L2-18b | red |
| control: an unclimbable wall (84) on the ledge's east side | L2-18b | green |
| the same wall 60 high | L2-18b | red |
| the ledge 6 higher | L2-18a band | red |
| the chest at the ledge's front edge (z −54) | L2-18d | red |
| secretBelow 25 and secretReach 8 | L2-18d | red (a root on Road5) |
| control: the chest at z −61 | L2-18d | green |
| the cache pays 1 Valor; the shrine names a family | L2-18e | red; red |
| the lookout pays 10 Valor | L2-13 | red |
| control: the lookout pays 2 Valor | L2-13 | green |
| Double Jump's price 0; 10.5; no doubleJump in the list | L2-6 | red ×3 |
| Double Jump's price 11 | over one Normal clear | red |
| levels.secretReach missing; secretBelow −1 | L2-11 | red; red |
| resetSecretsAttribute named GrantValor | L2-19 | red |
| secretOpen grey | the looks | red |

### L2 W1 fix round: the chest's trigger, every secret, and the one-jump gate (2026-10-17)

Rulings: `docs/prompts/l2-w1-fix-round.md` (s1 + d2, d3, d4, c3).

| Key | Was | Now | Why |
|---|---|---|---|
| `SecretFlow.Triggered` (server) | flat distance to the chest's **centre** | flat distance to its block's **footprint** (sx × sz, 0 over it) | s1: the Raiders' Cache (12 × 12 × 10, collidable) could never trigger: a root beside it is 7 or more from the centre, one on its top 13 over its foot |
| `Combat.json levels.secretReach` | 5 | **2.5** | Measured from the footprint now. A body pressed against a chest has its root at least its radius (1) off the face; 2.5 leaves 1.5 for a side-on body (arms) and an Rthro rig. The lookout: the ground within 2.5 of its 6 × 6 chest (x −288.5..−277.5, z −64.5..−53.5) lies inside the ledge (x −295..−271, z −66..−52), 1.5 inside the front edge and the back edge. A root on Road5 against the ledge's face is 5 off the footprint on the flat and 23 under its foot; camp A's fence corner is 16 off |
| `secretBelow / secretAbove` | 1 / 9 | 1 / 9 (unchanged) | The ledge's root is 3 over the chest's foot, the chest's 7; the cache's road 3. The band holds without a change |
| `check_levels.py` (a) | only for a secret whose key is sold, from the centre | for **every** secret: some standable top puts a standing root inside the trigger (a body on a top under the chest's keeps its radius off the side); with a sold key, on the ledge or the chest | d2: a chest whose key is sold later is never one nobody can open |
| `check_levels.py` (d) | the reach's circle | the ground within the reach of the footprint, the same rule | s1 mirrored |
| `sim_range.py` timed jump and hop | dropped an air press unseen | every press goes through `take_off`, which counts it | d3 (a press a knock's launch overtook is still lost) |

Where the trigger is met on Forest Road (0.5-stud scan of every standable top, a standing root):

| Secret | Opens from | Not from |
|---|---|---|
| The Lookout (needs Double Jump) | LookoutLedge against the chest (root 3 over its foot), the chest's top (7) | Road5 (−23; −5 at a jump's top), the sign pad, camp A's fence |
| Raiders' Cache (fire, not sold) | CacheSpur beside the chest (3 over its foot) | its top (13 over: over secretAbove 9) |
| Island Shrine (ice, not sold) | the Pond beside it (3), its top (6) | — |

The cache still pays nothing (no reward entry, `HasKey` fails closed for fire); when W2 sells fire, its trigger is
already reachable and `check_levels` (a) keeps it so. MISSIONS_DESIGN §22 rebuilds the cache as a cave in W2: (a)
then judges the cave. For W3: the shrine needs a "without ice" reach rule and a pond that is not solid (a PLAN note, routed to docs).

**The sim numbers do not move.** `sim_range.py --check --levels-only --level forest` is byte-identical before and
after (the first run 4.23 / 4.25 / 4.31 min; 78 / 18 / 18 runs with 0 air presses). No reacting policy plans a
jump in the air, so the new count is 0 in every shipped run; the knock path still loses the overtaken press.

**The one-jump gate can fail now (d3).** With the planner's `can_jump` guard removed (the reviewer's mutant),
a timed jump planned in the air leaves while he is airborne, `take_off` counts it, and the forest check goes red:
"forest, Normal: one jump (L2-20) ... asked for 1 jump(s) in the air". Before the fix the same mutant stayed
green (`airAsked` 0). Only one press in 78 Normal runs turns it: the planner rarely prefers a jump planned in
mid-air, so the mutant is thin but deterministic (fixed seeds). It is `check_levels_mutants.py`'s SIM_CASES
entry and runs the whole forest check (about five minutes).

**One home for the id caps (s2, d4).** `sim_range.SECRET_FAMILY_MAX` and `check_levels.ABILITY_ID_MAX` read
`Unlocks.luau`'s `MAX_FAMILY_LENGTH` (24) and `MAX_ID_LENGTH` (32) from the file, and count bytes as Luau's `#`
does (they counted code points; the same for ASCII ids).

**c3, the walk-off grace (`movement.coyoteSeconds` 0.12): no tool change.** The client takes the grace jump
only while the root is no higher than where it left the floor, so a jump's height over the floor walked off is
never more than `jumpHeight`, and every vertical rule (the lookout's 1-stud margin at camp A's fence, the
unclimbable walls' `climb_max`, L2-18 b and c) is unchanged. It does carry further on the flat: the jump can
leave up to `walkSpeed × coyoteSeconds` = 2.4 studs past the edge and 1.4 lower, which lengthens the reach a
jump, a double jump and a dash cover (`stray_reach`) from 46.6 to 49.3 studs. A dash off an edge gains nothing
the models do not already count (a dash's 20 studs are counted once either way; a ground dash drives the plane
only, so the body falls). Every `check_levels` verdict was re-run with that longer reach: 168 of 168 the same
(camp C's walls and "nothing beside camp C" still pass). `sim_range` has no edges to walk off (a player's floor
under him changes in the frame he crosses it, and he jumps only from the floor), so nothing there changes. If a
later layout comes within 3 studs of a `stray_reach` line, model the grace in `stray_reach` and `reach_at_rise`.

**d1 (no player-player collision), the Python side:** no rule in `check_levels.py` or `sim_range.py` relied on
it. Every reach rule models one body; `startSpacing` only spaces a party's spawns; `check_secret_reach`'s
docstring now says why stacking is not modelled. The "owners of doubleJump only" sniper labels stay.

`check_levels_mutants.py`, new and changed cases (all as expected; 73 data cases, 4 stage-mirror cases, 1
simulator case in all):

| Case | Rule | Expected |
|---|---|---|
| the centre rule back (TRIGGER_MODEL centre, secretReach 5: W1 as shipped) | (a), the cache | red |
| the centre rule at secretReach 2.5 | (a), the cache | red |
| secretReach 0.9 (under a body's radius) | (a), the cache | red |
| the cache's chest raised 5 off the road | (a), the cache | red |
| control: the footprint rule | (a), the cache | green (CacheSpur) |
| control: the centre rule keeps the lookout | (a), the lookout | green (its chest's top) |
| control: the chest 1.5 further back (z −60.5; was "2 further back, z −61") | L2-18d | green |
| the chest 2 further back (z −61): the trigger over the void behind the ledge | L2-18d | red |
| the planner may jump in the air (`can_jump` always true) | sim_range, one jump (L2-20) | red |

## L2 W2: fire, the Flamethrower, the cave and the shortcut (2026-10-18)

Contract: `docs/prompts/l2-w2-contract.md` (L2-29 to L2-47, its §10: §5 Option 1, the Pickets bypass, and the AB
bend closed now). Gear: Normal 2 / 2, Hard 4 / 4, Brutal 6 / 6, seeds 11 / 23 / 37; `py -3.12 tools/sim_range.py
--check` on the gate's 64-bit Python 3.12 (PASS, 491 lines, 11.8 min); `py tools/check_levels.py` PASS;
`py -3.12 tools/sim_combat.py --check` 23 of 23.

### L2 W2: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `ProvingGrounds.json weapons.flamethrower` | — | ranged, era 1, `element` "fire", one variant: capsule **range 20, width 7**, pad 0.8, damage 5, rate 10, continuous | L2-29. The contract's 16 × 5 measured crowd6 **159** against the target 280 (the stream reached one row of the 6-stud grid); 20 × 7 gives 268–277, inside FAMILY_TOLERANCE. Range was preferred to width so the capsule stays a stream (a 9-wide capsule from the muzzle hits bodies beside the player like a sweep). Single 50 (= Beam A) |
| `weapons.flamethrower.ability` (Dragon's Breath) | contract: damage 30, killRefund 0.3 | **damage 36, killRefundSeconds 0.5**; count 4, tick 0.15, range 20, arc 50, cooldown 10, floor 4 | At 30 the burst was 833 / 277 = 3.0 s, on the band's floor; 36 gives 3.7 s. At refund 0.3 the busy-crowd cooldown was 71% of base (band 40–60%); 0.5 gives 53%. 36 stays under `heavyHit` 40: no flame hit opens a plate (the slam does) |
| `Expeditions.json looks.bramble` | — | LeafyGrass (96, 132, 38) | A colour look (spread 94); `check_levels` holds it with the colour looks |
| `Combat.json levels.react` | — | `{ fireHits 6, pad 0.5 }` | L2-34 as written (0.6 s of flame burns a bramble) |
| `Combat.json debug` | — | `grantFamilyAttribute` "DebugGrantFamily", `removeFamilyAttribute` "DebugRemoveFamily" | L2-38 |
| `1_ForestRoad.json secrets.cache` | a name only | **4 Valor, 60 Timber** | §7 as written: 60 = 28% of a first clear's 211 (band 15–30%; 27% of the level's Normal stock of 220), 4 Valor under Double Jump's 10, the price its chain starts from |
| `ForestRoad.json` | the cache on CacheSpur | the cave (below); CacheSpur and CacheSignPad gone (blocks and region cells); `shortcuts` [cave], `shortcutRoute`; **BendWall** | §5 Option 1, L2-47 |
| `check_levels.py` | — | headroom rule, `exposed`, R8's sight, (e) chain, (f) cave, the bend rule, `fielded_lifts` = every family, `levels.react` and the two levers | below |
| `sim_range.py` | — | `flamethrower` target, a capsule fires from 8 studs (as cones), `dragonBreath` = Slug Burst, L2-39, the pair player, the tunnel runs, open-tunnel sniper courses, the Validate mirror of `react` / `opens` / `shortcuts`, `Secret_cache` out of the known limits | below |

### L2 W2: the cave (grey blocks)

The mouth (CaveMouth, floor 0, x −340..−328) opens on Road4's north edge under the lookout; one step of +8 at
z −86 onto the long leg (CaveTunnel, floor 8, interior z −98..−86, x −340..−116), the alcove (CaveAlcove,
x −218..−206, z −110..−98) with the Raiders' Cache (6 × 4 × 6 at (−212, 10, −104)), the exit leg (CaveExitLeg,
x −116..−104) south to CaveExit, which turns east and opens on RoadAB5's north edge at x −86..−74, by Main
Camp's west gate. Every leg is 12 wide; the roof's foot is 22 everywhere (14 over the long leg, 22 over the
mouth so the step has headroom). Walls and roof are `wall` blocks: **84** within a stray jump (49.3 with the
walk-off grace) of the lookout's ledge and its chest (top 38), **64** beyond; every one is at least 46 over
every surface within 49.3 (the contract's 43 + 3). The alcove sits 2 studs further east than first drawn so its
64-high walls stay 51 off the ledge. Brambles (`react` fire, `opens` cave) fill both mouths flush with the road,
half a stud into the walls. Sign: "RAIDERS' CACHE - needs FIRE" on Road4 at (−322, 0, −49), beside the mouth.
The trigger box (shortcut `cave`) stands in the exit at (−80, 14, −59). Not a region cell: raiders never enter.
Parts: **112** (maxParts 600).

| Measure | Value |
|---|---|
| Main route | **1,079 studs** (unchanged; band 900–1,100) |
| Shortcut route (Road4 → mouth → step → long leg → exit leg → exit → RoadAB5) | **350 studs**, in place of **342** of the main route, camp A skipped; 1 climb (+8) |
| Sneak rule along it | tightest Normal B.fire1, **+14.0** past its sight (16); Pickets fireN 60 away |
| Sealed with the brambles standing | 891 floor points of the five cave floors and every point of the cache's trigger: no way in at any width |
| The cache's trigger | met from CaveAlcove (root 3 over the chest's foot) and the chest's top (7) only |
| The AB bend (L2-47) | BendWall x −122..−116, z −82..−8, top 64, meets the ridge: the most any hop between two walked road blocks now saves is **49** studs (a corner; rule ceiling 60; the open bend saved about 115) |

### L2 W2: the Flamethrower (range, tier 1)

| Row | Value |
|---|---|
| Single / crowd6 / crowd3 | **50 / 268 / 1,025** (targets 50 / 280, ±15%) |
| Dragon's Breath | burst **3.7 s** of crowd DPS (3–5), busy 0.6, net 3.1, busy-crowd cooldown **5.3 s = 53%**, floor 4 s = 40% |
| Colossus, Broadsword (reacting) | 75.4–77.2 s |
| Colossus, Flamethrower / with Dragon's Breath | **110.2–110.4 s / 86.0–86.7 s**, 0 hits taken |
| Warlord, Broadsword | 97.3–98.1 s |
| Warlord, Flamethrower / with Dragon's Breath | **126.6–127.1 s / 111.8 s**, 0 hits; guard down 33.8 s, plate broken at 51.4 s by **11 ground slams** (plate phase 17.6 s, 42 studs) |

L2-39 is a gate now: an elemental family's fastest seed is never faster than the Broadsword's slowest (margins
+11% Colossus with the ability, +14% Warlord), within RANGED_KILL_SECONDS 150, no hit landing.

### L2 W2: Forest Road with the Flamethrower (Normal 2 / 2)

The simulator plays one weapon per run, so a **pair player** was added: he carries the melee and a ranged family
and fights each swing with the one that reaches (the melee within its reach, else the ranged; no switch time,
the most a pair can earn); he closes on a boss to his melee's reach.

| Run | Clear (min) | Cash a minute | Colossus in the run |
|---|---|---|---|
| Broadsword alone (the band's reacting player) | 5.26 / 4.69 / 5.04 | 26,412 | 80.3 / 76.0 / 77.4 s |
| Pair: Broadsword + Longbow (today's loadout) | 4.20 / 4.32 / 4.32 | 30,688 | 77.9 / 75.6 / 77.8 s |
| Pair: Broadsword + Flamethrower | **4.05 / 4.24 / 4.17**, 0 downs | **31,663 = ×1.03 the Longbow pair** (×1.20 the Broadsword alone) | **74.4 / 73.6 / 75.3 s** (×0.96) |
| Flamethrower alone, the Pickets only | A cleared 29.4 / 30.6 / 29.9 s (the Broadsword: 35.8 / 37.3 / 38.8) | — | — |

**Two bands moved from the contract (the lead's to confirm).** (1) The cash yardstick is the Longbow pair, not
the melee-only run: carrying any ranged weapon speeds this player up by about 16% (the Longbow pair is ×1.16 the
Broadsword alone), so against the melee-only run the gate measured "a second weapon", not the Flamethrower.
Against the same player with today's loadout the Flamethrower adds 3%. (2) The clear band is L2 W1's first-run
band, **4.0–5.75 min** (not 4.5): the pair clears in about 4.2 min with either ranged weapon. The Flamethrower
alone clears the Pickets faster than the Broadsword (the stream reaches the slingers) but cannot open a plate, so
a flame-only player stalls in Main Camp: information, not a band.

### L2 W2: the shortcut run (the tunnel found)

| | Normal 2 / 2 | Hard 4 / 4 |
|---|---|---|
| Full run, reacting player | 5.26 / 4.69 / 5.04 min, 131,410–132,110 cash, 211 Timber | 5.11 / 5.33 / 5.20 min, 282,400–285,020 cash, 454 Timber |
| Tunnel, reacting player | **4.34 / 4.29 / 4.52 min** (−37 s on average), 124,040 cash (−5.6%), 201 Timber | **4.95 / 4.83 / 4.72 min** (−23 s), 256,440–258,440 cash (−9.6%), 414 Timber |
| Tunnel, a human's reaction | 4.02 / 4.17 / 4.31 min, 0 downs | 4.55 / 4.35 / 4.29 min, 0 downs |
| Cash a minute, tunnel / full | **×1.07** (gate ≤ ×1.15) | **×0.98** |

The saving is larger on Normal (37 s; the contract expected about 25) and smaller on Hard (23 s; expected
30–35). Camp A's residents are given up (about 7,400 cash and 10 Timber on Normal, 26,000 and 40 on Hard).

### L2 W2: R8, the sniper spots

`standable_points` counts a roofed top when a body has headroom (6) over it, and R8 now keeps a spot only where
a bow's line in plan reaches a region cell (walls and brambles that rise from under both feet to over both heads
stop it; a roof does not). Closed variant (the brambles standing): the pinned list less **Secret_cache**; nothing
in the cave is a spot. **Open variant (a leader who found the tunnel): CaveMouth and CaveExit join.** Any open
mouth onto the region leaves a floor that sees the road and that no rusher reaches (a body in a corridor past a
corner always sees round it, so no bend can remove this); the exit's bend keeps every other cave floor clean (the
exit block runs 9 studs up the exit leg to hold the deepest point that sees out, z −73.5). Both are rated, Normal
and Hard, and earn far less than fighting:

| Spot (tunnel open) | Normal cash / Timber a minute (mission 25,104–28,041 / 40–45) | Hard at 2 / 2 (mission 18,614–20,512 / 27–30) |
|---|---|---|
| CaveMouth | 1,436 / 7,181 / 958; 0–9.6 | 0 / **19,151** / 0; 0–28.7 (seed 23: −6.6% cash, −5.6% Timber, the thinnest) |
| CaveExit | 2,825 / 2,825 / 565; 0–5.6 | 0 / 0 / 0 |

`SNIPER_KNOWN_LIMIT_L4.normal` is now LookoutLedge and Secret_lookout. The two open-variant spots need the lead's
OK (pinned in `EXPECTED.sniperSpotsOpen`).

### L2 W2: `check_levels_mutants.py`, new and changed cases

| Case | Rule | Expected |
|---|---|---|
| a 1-stud gap beside the west bramble | (f) sealed | red |
| control: the bramble flush with the wall's face | (f) sealed | green |
| a 0.2-stud slit under the east bramble | (f) sealed | red |
| the long leg's roof 3 short of the alcove wall | (f) sealed | red |
| the ridge 60 high by the ledge | (f) unclimbable ridge | red |
| control: that wall 81 (43 over the lookout chest's 38) | (f) unclimbable ridge | green |
| the alcove's roof down to 13 (no headroom) | (a) the cache | red |
| the long leg 11 wide | (f) shortcut route | red |
| the step 11 high | (f) shortcut route | red |
| the cave 52 south (14 from fireN's fire) | sneak rule on the shortcut | red |
| control: the cave 30 south | sneak rule on the shortcut | green |
| the exit without its turn | R8, open | red (CaveExitLeg, CaveTunnel join) |
| no sight rule (W1's R8) | R8, closed | red |
| the cache pays 10 Valor / control 9 | (e) | red / green |
| the cache pays 70 Timber (32%) | (e) | red |
| the lookout pays nothing; the Flamethrower carries no element | (e) chain | red; red |
| control: the lookout pays 2 Valor and the Flamethrower only | (e) chain | green |
| a bramble opens no shortcut; reacts to water; does not collide; the shortcut id twice | Validate | red ×4 |
| levels.react.fireHits 0; grantFamilyAttribute named DebugGrantAbility; bramble grey | config | red ×3 |
| the bend wall removed; only between the roads (a hop round its end) | L2-47 | red; red |
| control: the bend wall 4 short of the ridge (the way round is 58) | L2-47 | green |
| L2-18c: today's Leap Smash; with the Greataxe in the loadout; control: the floor model | (c), every family fielded | red; red; green |
| the cache's chest raised 8 off its alcove floor | (a) the cache | red |
| s1: the centre rule at secretReach 2.5; secretReach 0.9 (now judged by the cave's (a): a root on the alcove floor) | (a) the cache | red; red |
| s1 control: the centre rule at secretReach 5 (was red on the 12-wide cache; the 6-wide chest opens from 4 off its centre) | (a) the cache | green |

The full driver: 108 data cases, the 4 stage-mirror cases and the 1 simulator case, all as expected (35 min).

## L2 W2 fix round: the ridge, the grace, the bend and the fire sniper (2026-10-18)

Rulings: `docs/prompts/l2-w2-fix-round.md` (d-M1, d-m1, d-m2, d-m4 and the s-m3 mirror; findings in
`docs/prompts/l2-w2-review/data-tools.md`). Gates: `py tools/check_levels.py` PASS (about 20 s);
`py -3.12 tools/sim_range.py --check` on 64-bit 3.12 PASS (498 checks, 10.4 min); `py -3.12 tools/sim_combat.py
--check` 23 of 23; `py tools/check_stage_mirror.py` PASS with the server's s-m3 line in.

### L2 W2 fix: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `ForestRoad.json` CaveWallS2 | x −221..−118, top 64 | **x −221..−180, top 84**, and **CaveWallS3** x −180..−118, top 64 | d-M1: a Double Jump owner's lift or air dash from the lookout ledge ended on it (below) |
| `ForestRoad.json` CaveRoofE | x −221..−102, top 64 | **x −221..−180, top 84**, and **CaveRoofE2** x −180..−102, top 64 | the same |
| CaveWallAlcoveW / E / N, CaveRoofAlcove | top 64 | **top 84** | the ruling: every 64-high piece within reach of the ledge or its chest (the alcove is 60 off the ledge) |
| `check_levels.py` (f), the ridge | `unclimbable` only | plus **no ability that carries a Double Jump owner onto a wall facing the sealed air**: `lift_routes(air=True)` (take-offs at jump + double jump, 18.0 studs of carry and a dash, a void's floor his feet less 30, a target up to 30 over it) and Impale Dash held in the air over its 30 studs (`dashing_abilities`, `air_carry`) | d-M1, and the reviewer's Spear follow-up: the Spear does the same as the Greataxe |
| `check_levels.py` `unclimbable` and the walled gate's reach | `stray_reach` 46.6 | **`wall_reach_of` 49.3** (2.4 studs walked off the edge and 1.4 lower first, BALANCE "L2 W1" c3) | d-m1: the contract and this file promised 49.3 |
| `check_levels.py` L2-47 | jumps and a dash only | plus a second rule: the same with the longest carrying ability's travel (32) is a **known limit until L3** while no carrying family can be owned without a lever; red once one can | d-m2 |
| `check_levels.py` `sniper_spots` | the nearest point that sees the region | also `near`, the nearest point of all (seen or not) | d-m4: where a cone that ignores walls is cast from |
| `sim_range.py` `react_problems` | finite numbers | **a shortcut `sx`, `sy` or `sz` of 0 or below is refused**, `shortcut "<id>": <key> is <n>, not a size above 0` | s-m3, the server's StageFlow line mirrored |
| `sim_range.py` the open-tunnel snipers | the bow only | each spot also with the Flamethrower carried, **Dragon's Breath** cast through walls at the nearest body its cones reach, from the spot's point and from its nearest point; he waits out the cooldown (idle 10 s + 10 s) | d-m4 |

No config number moved. Parts 112 → **114** (maxParts 600). Main route 1,079 and the shortcut route 350 are
unchanged; so is everything `sim_range` measured before (the pair, the tunnel runs, L2-39, every bow sniper row).

### L2 W2 fix: the ridge (d-M1)

Where the 84-high ridge must end for the rule to hold (the split between CaveWallS2 / S3 and CaveRoofE / E2;
the alcove at 84 in every row):

| Split at x | Leap Smash (Greataxe) | Impale Dash held in the air (Spear) |
|---|---|---|
| −221 (W2 as shipped: everything east of S1 at 64) | **10 take-offs** off the ledge's edge over the void, feet 68 over CaveWallS2 | reaches |
| −210 | 3 take-offs onto CaveWallS3 | reaches |
| −205 | clean | **onto CaveWallS3, 67.9 off the ledge** (41.5 carry + 30 + a body) |
| −195 | clean | clean |
| **−180 (shipped)** | clean, about 25 studs to spare | clean, about 20 studs to spare |

The reviewer's estimate (about −195) holds for the Leap; the Spear's air dash reaches about 5 studs further,
which is why the ridge runs to −180. The 84 tops stand 50 over the ledge (34) and 46 over its chest (38), over
the most a lift adds (30 + 10 + a 3-stud step). Nothing inside changes: every roof's foot is still 22, the
tunnel's 12 × 14 section, the camera clearance and the sight rule are as before (only tops moved). From outside
the step from 84 to 64 sits 41 studs further east than in W2.

The rule took the gate from 14 s to 2 min on first writing; two bounds that change no answer (a surface none of
whose take-offs can lift the feet to the lowest key, then only the keys within castRange of a take-off and the
solids each line crosses) bring the whole `check_levels` run back to about 20 s. The lookout's L2-18 (c) answers
are unchanged.

### L2 W2 fix: the bend with an ability (d-m2, known limit until L3)

No family that carries (Greataxe, Spear) can be owned without a lever today (owned: Broadsword, Longbow, and the
Flamethrower from the lookout). With an ability's 32 studs on top of the jumps and a dash:

| Hop | Length | Road saved |
|---|---|---|
| RoadAB1 / AB2 → RoadAB5, round BendWall's south end | 80.4–80.8 | 61–63 studs (about 3 s) |
| RoadBC1 / BC2 → RoadBC4 | 54.0 | 104 studs (about 5 s) |
| RoadBC1 / BC2 → RoadBC5 | 70.0 | 96 studs |

No camp is skipped. The AB rows are new against the review (which named the BC bend only): BendWall is a wall
to the ridge in the north, but its south end at z −8 lets a carried hop go round it. Both close with data when L3
sells a carrying family (a wall at BC; BendWall run south), or the rule goes red on its own.

### L2 W2 fix: the fire sniper (d-m4)

Cash / Timber a minute against the mission player on the same seeds (11 / 23 / 37); every hit landing:

| Spot (tunnel open) | Normal (mission 25,104–28,041 / 40–45) | Hard at 2 / 2 (mission 18,614–20,512 / 27–30) |
|---|---|---|
| CaveExit, bow (W2) | 2,825 / 2,825 / 565 | 0 / 0 / 0 |
| CaveExit + Dragon's Breath | 2,037 / 2,037 / 582 | 1,355 / 1,646 / 1,623 |
| CaveExit + Dragon's Breath, behind ExitS (nearest point, 3 off the road) | 1,947 / 1,947 / 556 | 1,197 / 1,201 / 1,041 |
| CaveMouth, bow (W2) | 1,436 / 7,181 / 958 | 0 / **19,151** / 0 |
| CaveMouth + Dragon's Breath | 799 / 3,994 / 533 | 0 / 10,651 / 0 |
| CaveMouth + Dragon's Breath, nearest point | 795 / 530 / 530 | 0 / 0 / 0 |

From behind CaveWallExitS the cones do land (two casts, 14 to 27 hits), but the rushers at the road's edge
stand down or go home before the third, and on Hard the shooters put him down in about 20 s. CaveMouth's nearest
point is 27 off the region, past the cones' 20.8 and a body: no cast. **Neither spot out-earns the mission player
with the fire family's ability (the best is 8% of it), so the corridor stays where it is.** The thinnest margin
is still the bow's Hard CaveMouth seed 23 (−6.6%).

### L2 W2 fix: `check_levels_mutants.py`, new cases

| Case | Rule | Expected |
|---|---|---|
| the ridge by the ledge back at 64 (W2's data) | d-M1 | red |
| the 84 ridge ends at x −205 (the Spear's air dash) / control at −195 | d-M1 | red / green |
| no air dash, the ridge ends at x −210 (Leap Smash) / control at −205 | d-M1 | red / green |
| a perch at 34, 48 off CaveWallS3 (inside 49.3, outside 46.6) / control 50 off | d-m1, the ridge | red / green |
| the cache pays the Spear (a carrying family owned without a lever) / control: the Longbow | d-m2 | red / green |
| the shortcut's sz 0; its sx −12 / control: its sy 0.01 | s-m3, Validate | red; red / green |
| sim_range's size rule out (the mirror alone) | check_stage_mirror | red |

The full driver: 114 data cases, the 5 stage-mirror cases and the 1 simulator case, all as expected (40 min).

## L2 W3: ice, the Frost Hammer, deep water and the island shrine (2026-10-19)

Contract: `docs/prompts/l2-w3-contract.md` (L2-49 to L2-68; its §13: §5 Option A, the creek into a pond, a patch
per swing, the ice for the whole run). Gear: Normal 2 / 2, Hard 4 / 4, Brutal 6 / 6, seeds 11 / 23 / 37;
`py -3.12 tools/sim_range.py --check` on the gate's 64-bit Python 3.12 (PASS, 523 checks, 11.6 min); `py tools/check_levels.py` PASS;
`py -3.12 tools/sim_combat.py --check` 23 of 23; `py tools/check_stage_mirror.py` PASS on the server's lines.

### L2 W3: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `ProvingGrounds.json weapons.frostHammer` | — (contract: arc 9 / **140°**, damage **36**, rate **1.5**) | melee, era 1, `element` "ice", one variant: arc range 9, **120°**, pad 1.5, cap 8, **damage 38, rate 1.55**, knockback 22, launch 6, chain 1 / 1 / 1.8 | L2-49's numbers failed the boss gates: the Colossus took **87.3–94.2 s** (band 60–90). The boss fight is set by the dodging rhythm, so the kill does not move with DPS in a line: damage 40 makes every swing a heavy hit (the contract wants only the finisher heavy) and drops the Colossus to 76.6 s, under the Broadsword's slowest 77.2 (L2-39); 38 at 1.55 gives **83.2–84.9 s**, inside both. At 120° instead of 140° crowd6 falls from 469 (0.5% under its ceiling 471) to **439**; a boss is one body in front, so its rows do not move. Single **75** (target 68, +10%, in band); the finisher 68.4 is the only heavy hit (38 < `heavyHit` 40) |
| `weapons.frostHammer.ability` (Frost Quake) | contract: damage **50**, count **3**, radius **8**, spacing 6 | **damage 30, count 1, radius 32**; cooldown 12, floor 5, refund 0.25, delay 0.25, knockback 18, launch 8 (still the Earthquake launcher, L2-50) | L2-39 holds the kill *with* the ability too. Earthquake's three rings all land on a boss at the caster's feet (128.6 a cast), so the contract's Frost Quake took the Colossus to **72.9–76.6 s** and the Warlord to 100.8 (the Broadsword's slowest: 77.2 and 98.1). With the swing above, the window left the ability about 4% of a boss kill. One wide ring keeps the crowd burst (it reaches more bodies) while a boss takes one 30 a cast: burst **3.5 s** of crowd DPS (3–5), busy-crowd cooldown **6.6 s = 55%**, floor 42%. On the bosses it no longer shortens the kill (below) |
| `Expeditions.json looks.ice` | — | Ice, **(150, 208, 245)** | A colour look (spread 95), in `REQUIRED_LOOKS` and `COLOUR_LOOKS` |
| `Expeditions.json found` | — | `frostHammer`: node `castle`, "Found in the Castle" | L2-51 |
| `Combat.json levels.react.ice` | — | `{ cell 7, lift 0.2, thickness 1, reachDown 6, ahead 4 }` | L2-53 as written: cell 7 <= (9 + 4 − 1) / 1.5 = 8 (two rows a swing); reachDown 6 >= Road2's root over the water, 0 + 3 − (−1) = 4 |
| `1_ForestRoad.json secrets.shrine` | a name only | **6 Valor, 63 Timber** | L2-59 as written: the biggest of the three chests |
| `ForestRoad.json` | Creek 20 × 90 and Pond 52 × 44, solid; the shrine a 12 × 3 × 12 slab on the pond | **CreekUp** (x −410..−390, z −30..8, deep, no react); **Creek** (z 8..96) and **Pond** (x −436..−364, z 96..156), deep, `react` "ice", `landing` (−385, 0, 2); **ShrineIsland** 16 × 4 × 16, top 0, at (−400, 128); the shrine a 6 × 4 × 6 chest on it | §5 Option A as drawn; the island's position kept (the reach rule holds with +21.5 to spare) |
| `check_levels.py` | the W1 creek rule | deep water, landings, (g) dry, (h) frozen, the frozen layout's walls / lookout / R8 / chord / killY, `found` (map and chain), ice look and config, ice pieces in the Part count | below |
| `sim_range.py` | — | `frostHammer` target, `frostQuake` = Earthquake, Validate's ice and landing lines, `ice_cells`, `frozen_layout`, the Frost Hammer + Longbow pair, R8 on the frozen spots, the crossing, the chest gate's price from a map node | below |

### L2 W3: the water and the island (grey blocks)

The route still crosses the creek on Road2 (the bridge, top 0; the water's top −1, 1 under it; 21 route samples
over water). A fall into the Creek or the Pond (their footprints grown by `rescue.outside` 4) comes back to
Road2 at (−385, 0, 2), 6 studs from the ice's first row; from the ice's top to `killY` −13 is a 12.2-stud fall,
0.35 s, before the rescue's own step. **A slip off Road2's north edge falls into CreekUp, which has no landing
(only ice may carry one, L2-58): that player goes back to `SafePoint`** (on a first run before camp A, the
trailhead, about 70 studs). Giving CreekUp ice and a landing would add a frozen floor north of the road, a new
sniper spot by Road3: not done; the lead's call.

| Measure | Value |
|---|---|
| Ice pieces | Creek 3 × 13 = 39, Pond 11 × 9 = 99, 6 under the island: **132**; Parts **248** of 600 |
| The island with the water as built (g) | not reached by the jumps, a dash and the walk-off grace (49.3), by Leap Smash after the jumps and a dash (71.0) or by Impale Dash held in the air (80.6); the tightest top, ShrineSignPad, is **102.0** away: **+21.5** over the farthest (rule: ICE_MARGIN 15) |
| The island frozen (h) | reached from the start; the chest opens from the island; the shortest chain of cells from a bank to the island **16 cells** (4 cells touch a bank, 6 the island) |
| The trigger | met from ShrineIsland and the chest's top only; the ground within 2.5 of the chest lies over the island (2.5 to spare each side) |
| With the ice frozen | every one of the 31 unclimbable walls stays so; the lookout's (a) to (d) hold; killY 12.2 under the ice; the frozen sheets are floor, never walls, for the shot-origin chord (the thinnest tall piece is still CaveBrambleE, 2) |

### L2 W3: the crossing (Frost Hammer, a patch a swing)

The simulator's model (`ice_crossing`): he stands on the bank where the shortest chain starts, swings at the
next unfrozen cell of the chain (WorldReact.Chills: range + ahead = 13 from his root, 60° either side, the cell
within reachDown under his root), walks to the far edge of the last frozen chain cell (his root a stud back), and
swings again once the swing is ready and the ice has shown; then onto the island to the chest's trigger.

| | Swings | Seconds | Studs | Cells frozen |
|---|---|---|---|---|
| Ideal (no lag, no reaction) | 9 | **5.8** | 109 | 38 |
| A human (0.15 s round trip, 0.25 s reaction each swing) | 9 | **9.0** | 109 | 38 |

The lead's band is 8–20 s; the human's crossing is in it (gate `ICE_CROSSING_SECONDS`), **the ideal is under
it**: a swing freezes about 13.5 studs, which a walking player covers in the swing's own 0.65 s, so the crossing
is set by walking 109 studs. A slower crossing needs a shorter freeze (smaller `ahead` and a smaller `cell`, more
pieces) or a slower swing; not changed (Ben's "freeze your way across" reads as walking with it).

### L2 W3: the Frost Hammer (range, tier 1)

| Row | Value |
|---|---|
| Single / crowd6 / surround6 / crowd3 | **75 / 439 / 396 / 597** (targets 68 / 410 ±15%; the Broadsword 76 / 545) |
| Frost Quake | burst **3.5 s** (3–5), busy 0.25, net 3.2, busy-crowd cooldown **6.6 s = 55%**, floor 5 s = 42% |
| Plate (armoured, 80) | 6 hits, 3.23 s (2 combos; the finisher is the heavy hit) |
| Colossus, Broadsword (reacting) | 75.4–77.2 s |
| Colossus, Frost Hammer / with Frost Quake | **83.2–84.9 s / 83.7–90.5 s**, 0 hits taken (the cast costs as much as it gives) |
| Warlord, Broadsword | 97.3–98.1 s |
| Warlord, Frost Hammer / with Frost Quake | **102.9–107.1 s / 101.0–105.3 s**, 0 hits; guard down 30.0 s, plate broken at 47.8 s (siege **45%**, plate phase 18.9 s, 45 studs) |

L2-39 margins (the hammer's fastest seed over the Broadsword's slowest): Colossus +6.0 s, with Frost Quake
+6.5 s; Warlord +4.8 s, with Frost Quake **+2.9 s** (the thinnest). **These are tight: any hammer number change
re-runs the boss rows** (L2-62).

### L2 W3: Forest Road with the Frost Hammer (Normal 2 / 2)

| Run | Clear (min) | Cash a minute | Colossus in the run |
|---|---|---|---|
| Broadsword alone (reacting) | 5.26 / 4.69 / 5.04 | 26,376 | 78.5 / 76.0 / 77.4 s |
| Pair: Broadsword + Longbow | 4.14 / 4.32 / 4.32 | 30,859 | 75.7 / 75.6 / 77.8 s |
| Pair: **Frost Hammer + Longbow** | **4.46 / 4.69 / 4.43**, 0 downs | **29,178 = ×0.95 the Longbow pair** (gate ≤ ×1.10) | **80.6 / 84.4 / 81.5 s** (×1.07 the Longbow pair's; gate ≥ ×0.90) |

### L2 W3: the shrine chest

6 Valor and 63 Timber behind ice (its chain starts at the Castle node, `found:castle`; held under the dearest sold
ability, Double Jump's 10). 63 is **30%** of a first Normal clear's 211 Timber (the band's top, 15–30%) and 29%
of the level's Normal stock of 220. The three chests: lookout 3 + 50 + the Flamethrower, cache 4 + 60, shrine
6 + 63.

### L2 W3: R8, the sniper spots

With the water deep, **Creek leaves** both pinned lists (`sniperSpots`, `sniperSpotsOpen`). With the ice frozen
(both bramble variants) the lists are the same **plus Creek** (`sniperSpotsFrozen`, `sniperSpotsOpenFrozen`); no
other name, the pond and the island lie beyond the Longbow's 110. The frozen Creek's nearest point that sees the
region is (−391, 9), 99.7 off it (the solid Creek reached z −30 and was nearer). Its straight course earns
**0 / 0** cash / Timber a minute on Normal and on Hard at 2 / 2 (the mission player 24,986–28,047 and
18,789–20,513). `SNIPER_KNOWN_LIMIT_L4` unchanged.

### L2 W3: `check_levels_mutants.py`, new and changed cases

| Case | Rule | Expected |
|---|---|---|
| the Creek solid again; the Pond reacts to nothing; the water 0.25 under the bridge; the pond 1 under the creek / control: 0.5 under | deep water | red ×4 / green |
| an ice block that collides; an ice block that opens the cave; a landing on CreekUp (not ice); a landing whose y is a string | Validate | red ×4 |
| the Creek's landing over the void; a stud over Road2; on camp A's floor / control: on ShrineSignPad | L2-58 | red ×3 / green |
| the island 45 from the sign pad / control 52 | (g) the jumps | red / green |
| no air dash, the island 65 / control 75 | (g) Leap Smash | red / green |
| the island 75 / control 85 | (g) Impale Dash held in the air | red / green |
| the island 85 / control 96 | (g) ICE_MARGIN | red / green |
| the chest 6 east on the island / control 1.5 east | (a), (d) | red / green |
| ice.cell 12 / control 8; ice.reachDown 3.5 / control 4; the Frost Hammer carries no element | (h) the swing | red / green; red / green; red |
| the creek ends 16 short of the pond; a wall across the creek covering a row | (h) the chain | red; red |
| the island 66 south of the pond | (h) frozen, reached | red |
| a pond 17 high by the lookout ledge / control 6 high | the lookout, frozen | red / green |
| a pond 42 high 4 off CaveWallS1 | the walls, frozen | red |
| a pond south of Road4; the same with the brambles burnt | R8, frozen | red; red |
| found names no node; text 41 / control 40; the Broadsword found; a family no weapon has; the cache also pays the Frost Hammer | L2-51 | red; red / green; red ×3 |
| the shrine pays 10 Valor / control 9; 67 Timber; no `found` (nothing holds ice) | L2-59, (e) | red / green; red; red |
| levels.react.ice.cell 0; missing; iceHits back | L2-53 | red ×3 |
| sim_range's ice-collides line out; its landing-not-ice line out (the mirror alone) | check_stage_mirror | red ×2 |
| changed: "the shrine names a family" now also drops `found` (ice would resolve through the Castle otherwise) | (e) | red |

The full driver: 176 data cases, the 8 stage-mirror cases and the 1 simulator case, all as expected (about 1.5 h
beside a full simulator run).

## L2 W3 fix round: falls, the slits, the frozen gates and the shrine's pay (2026-10-19)

Rulings: `docs/prompts/l2-w3-fix-round.md` (review findings in `docs/prompts/l2-w3-review/`). The server agent
changed the rules in Luau (LevelGeometry's whole-cell cover, StageFlow's landing and overlap lines, the rescue's
"where it last stood"); this section is the data and the tools' side. Gates: `py tools/check_levels.py` PASS (about
42 s, was 34); `py -3.12 tools/sim_range.py --check` PASS (524 checks, exit 0); `py -3.12 tools/sim_combat.py --check`
23 of 23; `py tools/check_stage_mirror.py` PASS; `py tools/check_levels_mutants.py`: every case as expected (below).

### L2 W3 fix: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `ProvingGrounds.json controls.iceAutoDegrees` | — | **34** | Q1: a phone's auto-swing at water uses a cone narrower than the swing (120°), so it can only remove swings. The lead's figure from the client agent's measurement (`fix-client.md`, Q1): at 60 a phone on Road2's outer 2.5 studs still swings at the creek beside it; at 34 or less never, and a player facing the water from the sign pad's edge still swings |
| `Combat.json levels.react.ice.thickness` | 1 | **4** | d-m6: a frozen sheet is the floor under a slam (140 studs/s) and under a fall from the jumps' apex, and E5's depth rule (`levels.floorThickness` 4) was written against 1-stud floors. Config only: the piece's top stays at −0.8 and it now reaches −4.8, inside the water block (−1..−5). check_levels now holds it to the rule (look `ice` in `GROUND_LOOKS`) |
| `1_ForestRoad.json secrets.shrine.materials` | 63 | **60** | s3: 63 was 30.0% of a first Normal clear's 211 Timber, the band's very top (`SECRET_MATERIAL_SHARE` 15–30%), with 0.5% of slack, so any Timber change elsewhere would have turned the chest red. 60 is 28% (the cache's share) and 27% of the Normal stock of 220; still the biggest chest by Valor (6 against the cache's 4 and the lookout's 3) |
| `ForestRoad.json CreekUp.landing` | — | **(−385, 0, −2)** | Q3: any deep water may carry a landing. On Road2 by the creek, 5 east of its line and 6 in from the road's north edge (the Creek's and the Pond's stay (−385, 0, 2)) |
| `sim_range.py FAMILY_TARGETS.frostHammer` | single 68, crowd6 410 | **75, 439** | d-m2: the measured rows of the shipped swing, 38 × 1.267 (the chain's mean) × 1.55. Bands now 64–86 and 373–505 |
| `sim_range.py ice_cells` | a cover holding a cell's centre | a cover holding the **whole** cell (to `GEOMETRY_SEAM` 1e-6) | d-m1, mirrors `LevelGeometry.iceCells` |
| `sim_range.py react_problems` | a landing only on ice | a landing on any block that does not collide (`"<where> has a landing and collides"`); `"<a> and <b> are ice and overlap"` (`ice_overlap` = `LevelGeometry.Overlap`) | Q3 and s-s2, mirrors `StageFlow.reactProblems` |
| `check_levels.py` | — | the fall line, the overlap line, the fill line, Leap Smash's fall, the alias reader, the frozen bend / cave / walled runs, `ice` a ground look | below |

### L2 W3 fix: falls (s-M1, Q3)

The rescue now asks two points (StageFlow.Landing): where the body last stood (`WeaponService.LastGround`, the
root the server saw grounded, sampled every Heartbeat) and then where it is, each against a water's footprint
grown by `player.rescue.outside` 4. A walk-off from the ice's side carries a body about 9 studs before it is
judged and a dash-off about 29, so the stood point is what lands them.

The data and the gate (check_levels' new line in `check_deep_water`, on the water as built and frozen):
- every deep water block within a dash-off's carry of a top a player stands on has a landing (the carry is
  `dashDistance` + `walkSpeed` over the fall from that top to killY + a body's radius: 29.1 from a top at 0);
- where such a top meets a landing water's footprint, `rescue.outside` is at least one server frame of the dash
  (20 / 0.15 / 60 = **2.22**; it is 4): a body leaving that edge was last seen no farther back than that.

| Water | Landing | Met by (the stood test) | Within a dash-off |
|---|---|---|---|
| CreekUp | (−385, 0, −2) on Road2 | Road2 (over it), ShrineSignPad (corner), the frozen Creek | Road1, 26 off |
| Creek | (−385, 0, 2) on Road2 | Road2, ShrineSignPad, its own and the Pond's sheets | — |
| Pond | (−385, 0, 2) on Road2 | ShrineIsland, the chest, its own and the Creek's sheets | — |

What the line does not promise: a dash-off from a top that does not meet the water, that crosses only a corner of a
footprint and is more than 4 past it when judged, goes to the safe point as before (the position test is all it
has). Nothing on Forest Road is shaped that way: Road1's dash-off into CreekUp ends inside it.

### L2 W3 fix: the ice pieces (d-m1)

| Measure | Before | Now |
|---|---|---|
| Pieces | 132 (6 skipped: every cell whose centre lay under the island) | **136**: Creek 39, Pond 97 (only the 2 cells of column 5 lie wholly under the island) |
| Parts | 248 of 600 | **252** of 600 |
| Water no swing can close | 48.5 studs², two slits 1.82 × 13.33 beside the island | **none** (check_levels' new fill line: the pieces and the covers fill every ice block, cut along every edge, exact) |
| The crossing | 9 swings, 9.0 s human / 5.8 s ideal, 109 studs, 38 cells | 9 swings, **9.0 s / 5.8 s**, 109 studs, **39** cells (the part-covered cell beside the island now freezes too) |

A built cell that a cover holds in part has its top (−0.8) inside the cover (the island's top is 0), so nothing is
drawn twice and nothing z-fights. `frozen_layout` still freezes each block whole; the fill line is what makes that
true.

### L2 W3 fix: the island's reach (d-m3, d-m4)

- **Leap Smash's fall (d-m3).** The lift branch of `island_reach` now adds the walk-speed carry of the fall from where
  the leap lands (over a void: the take-off top) down to the key top less a step: from a top at 0 onto the island
  +3.5 (74.5), from LookoutLedge's 34 +12.3. The worst is still the Spear's Impale Dash held in the air, **80.6**;
  ShrineSignPad 102.0 away, margin **+21.5** (unchanged).
- **The walk-off grace (d-m4).** The jumps reach 46.6 without the grace and 49.3 with it; a case at 48 now proves the
  grace term (red only with it).
- **Aliases (s1).** `dashing_abilities` also reads `MECHANICS.<id> = MECHANICS.<other>` lines (an alias of an alias
  too), so a family whose ability aliases Impale Dash is an air dash for (g), the cave's carry and the bend. Today's
  aliases (`dragonBreath` = slug burst, `frostQuake` = earthquake) carry nobody.

### L2 W3 fix: the frozen layout (s2, d-m6)

check_ice already ran the walls, the lookout, R8, the chord and killY on the frozen layout. It now also runs:

| Gate | On the frozen layout | Forest Road |
|---|---|---|
| Floor depth (E5) | every frozen sheet ≥ `levels.floorThickness` | 4 deep: PASS |
| The bend (L2-47) | the sheets are walked ground joined to the road they touch (side to side, at most a step), carrying its samples; only pairs with a sheet are judged (two road blocks are the dry run's, unchanged) | the most a hop from the ice saves: **20** (Creek to Road3, a hop of 48.1; rule 60) |
| The cave, closed half | sealed air, the ridge's walls unclimbable, no carry onto them, the cache's trigger (the open variant's sniper list stays check_ice's) | as dry: 5 floors, 891 points, 22 walls |
| The walled camp | the ceiling, the gatehouse, plates and the cameras over the walls run whole; the sight lines judge only the eye points on the tops the frozen layout reaches and the dry one does not (exact, given the dry run: a sheet is no wall and no keep-out, so every other eye's lines are the dry run's) | the new tops are Creek, Pond, ShrineIsland and the chest, none in a gate's outside half-plane: no eye |

Cost: `check_levels.py` 34 s → about 42 s, so the full mutant driver grows with it. Judging every eye again on the
frozen layout cost 11 s more a run; the incremental sight run costs under 2.

**Known limit (the server review's s-s1, kept):** a cover is a colliding block or a secret judged by its top only.
Camp floors, fences and cover never cover water, and a high bridge's bottom is not judged (water 30 under a bridge
would stay unfrozen). Nothing on Forest Road is affected; a later level with a camp or a high bridge by water needs
the rule (LevelGeometry and `sim_range.ice_cells` together).

### L2 W3 fix: `check_levels_mutants.py`, new and changed cases

| Case | Rule | Expected |
|---|---|---|
| CreekUp has no landing; `rescue.outside` 2 / control 2.5 | the fall line (s-M1, Q3) | red; red / green |
| CreekUp's landing over the void | L2-58 | red |
| a landing on Road2 (it collides) — replaces "a landing on CreekUp (not ice)" | Validate | red |
| an ice block that collides now has its landing taken too (else the landing line alone keeps it red) | Validate | red |
| the Pond 1 into the Creek (check_levels' line; Validate's mirror) / control 1 short | s-s2 | red ×2 / green |
| `sim_range.ice_cells` on a copy with the old centre rule (the `sr` switch, `swapped_sim`) | the fill line (d-m1) | red |
| no air dash, a 34-high tower 92 south of the island / control 99 | ICE_MARGIN with Leap Smash's fall (d-m3; +21.0 without the term) | red / green |
| the island 48 from the sign pad | (g) the jumps' grace (d-m4) | red |
| `ice.thickness` 1 | the frozen floor depth (d-m6) | red |
| Frost Quake, range 70, aliased to Impale Dash / control on the Earthquake alias | (g) the air dash through an alias (s1) | red / green |
| a frozen bay x −436..−356, z −60..−52 (a hop from it to Road1 saves 84) | the frozen bend (s2) | red |
| a pond 42 high 4 off CaveWallS1 | the cave's frozen ridge (s2) | red |
| a pond 40 high 26 north of the gatehouse | the walled camp's frozen cameras (s2) | red |
| TrailEnd off the east gate's lane, reached over a frozen sheet only / control with no sheet | the walled camp's frozen sight, on the tops the ice adds (s2) | red / green |
| sim_range's landing-collides line out; its overlap line out (the mirror alone) | check_stage_mirror | red ×2 |
| sim_range's ice-collides line out now names the mirror case "a pool that collides, with no landing" | check_stage_mirror | red |
| re-aimed by d-m1: the dam across the creek holds row 6 whole (z 48..56) and is 50 high (a low dam the row lies beside is a bank the chain starts from again) / control: the first dam (z 50..54) holds no cell whole | (h) the chain | red / green |

The full driver (196 data cases, 9 stage-mirror cases, 1 simulator case; about 2 h 10 min): every case as
expected but the old dam case, which d-m1 made green and which was re-aimed above; the re-aimed case and its new
control were then run alone (red / green). The server agent named its stage-mirror refusal "a pool that
collides, with no landing" for the ice-collides mirror case.

## L2 W3 third fix round: the island off the grid, a sheet thinner than a root, the creek's mouth (2026-10-19)

Rulings: `docs/prompts/l2-w3-fix3.md`. The findings (fd-m1, fd-m2, fd-s1, fd-s2) are in
`docs/prompts/l2-w3-review/fix-diff.md`; the round's report is `docs/prompts/l2-w3-reports/fix3.md`.

Gates:
- `py tools/check_levels.py` PASS;
- `py -3.12 tools/sim_range.py --check` PASS (523 PASS lines, 0 FAIL, on Python 3.12.10 64-bit);
- `py tools/check_stage_mirror.py` PASS (ice cells: 9 views compared box by box);
- `py tools/check_levels_mutants.py --only "W3"`: every case as expected: 92 data cases (67 red, 25 green) and 7 stage-mirror cases, the shipped data green.

### L2 W3 fix3: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `Combat.json levels.react.ice.thickness` | 4 | **1.9** | fd-m2. The server judges a body on its own copy, which trails that player's screen by a round trip, and a cell frozen now turns solid on his screen a round trip later. At 4 a body's 2-stud root could end up wholly inside a fresh cell (a teammate walking into the creek at a 0.15 s round trip; the swinger stepping onto his own ghost). Under the root's height it never can. The lead's ruling replaces d-m6's: a sheet is not a camp floor (below) |
| `ForestRoad.json ShrineIsland` | z 128 (z 120..136) | **z 128.5** (z 120.5..136.5); the chest stays at z 128 | fd-m1. The island's south face lay on the pond's row line z 136, so the cells beside it, (4, 5) and (6, 5), had their south faces on its own: frozen, the opaque ice and the grey island z-fight. Both its z faces are now mid-row (rows 3 and 6); its x faces (−408, −392) were already mid-column |
| `check_levels.py` floor depth | every frozen sheet ≥ `levels.floorThickness` 4 (d-m6) | the frozen sheets are judged by the new sheet line; the floor line still judges every other block of the frozen layout | fd-m2 |
| `check_levels.py` | — | the coplanar line (`ice_coplanar`), the sheet line (`sheet_bounds`; `PHYSICS_HZ` 240, `ROOT_TALL` 2) | fd-m1, fd-m2 |
| `check_levels.py` fill line | the block shrunk by the inset on every side | a rim only along the cell sides that are inset (`ice_side_met`, check_levels' own statement of fd-s2) | fd-s2: where the creek meets the pond the sheets must meet |
| `sim_range.py ice_cells` | every cell side on the block's own face inset | not a side another ice block meets whole at the same top (`ice_meets`) | fd-s2, mirrors `LevelGeometry.meetsIce` |

### L2 W3 fix3: the island (fd-m1)

| Measure | Before | Now |
|---|---|---|
| Faces of an ice piece within the inset (0.05) of a same-facing face of a solid | **2** (cells (4, 5) and (6, 5), on the island's south face) | **0** (136 pieces against 86 solids) |
| ShrineSignPad to the island | 102.0 | **102.5** |
| Margin over the farthest reach (the Spear's Impale Dash held in the air, 80.6) | +21.5 | **+22.0** (`ICE_MARGIN` 15) |
| The chest's trigger (z 122.5..133.5, x −405.5..−394.5) over the island | 2.5 to spare each side | 2.0 north, **3.0** south; 2.5 east and west |
| Ice pieces / Parts | 136 / 252 | 136 / 252: column 5's rows 4 and 5 still lie wholly under the island; rows 3 and 6 are part-covered |
| Chain from a bank to the island | 16 cells (4 by a bank, 10 by the island) | unchanged |
| The crossing | 9 swings, 9.0 s human / 5.8 s ideal, 108.7 studs, 39 cells | unchanged |

### L2 W3 fix3: the sheet (fd-m2)

The sheet line (check_ice, on the frozen layout) holds two bounds:
- **Thicker than the fastest fall onto it moves in one physics step.** That fall is the faster of the slam's dive
  (`movement.slamFallSpeed` 140) and a free fall from the jumps' apex over the highest top reached on the frozen layout
  down to the lowest sheet: 68.8 studs, **164.3 studs/s**. At 240 Hz that is **0.685** a step. The 240 Hz is an
  assumption about Roblox physics: if adaptive stepping drops a falling character to 60 Hz, a slam moves 2.33 a step.
- **Thinner than the R15 root** (`ROOT_TALL` 2), so a root never lies wholly inside a sheet.

1.9 passes both. killY on the frozen layout is unchanged (12.2 under the ice); the lowest Part's bottom is now −4 (the
island's), was −4.8 (the sheets').

The server's side (`LevelService` bodies):
- Every body the air tracking last found off its floor (`WeaponService.FallSpeed`) has its feet led by
  `WorldReact.FallDrop`: fall × lag + g × lag² / 2.
  - The fall is the larger of the replicated velocity and the position's change, capped at `Tuning.FastestMove` 140.
  - The lag is `Tuning.CommitLag`: that player's ping plus 0.05, at most 0.3.
  - A standing body is not led.
- The review's case: feet at −1.0 falling at 19.8 with a lag of 0.1 is led 2.96, so the cell is held.
- A teammate walking off the bank at a 0.15 s round trip (lag 0.2):
  - no part of his root is in the cell when it turns solid on his screen;
  - unled, it would hold 1.9 of his root.
- Off the frozen edge at a 0.15 s round trip, his last standing frame cannot be led: at most **0.21** of his root, never
  the whole of it.

### L2 W3 fix3: the creek's mouth (fd-s2)

Six cell sides now lie on their water's face, with no inset:
- the Creek's last row: its 3 south sides;
- the Pond's first row, columns 4 to 6: their north sides.

The 0.1 seam across the crossing is gone. The Pond's columns 3 and 7 meet the Creek over 0.18 studs only, so they keep
their inset. Every other side on a water's face keeps it too: 72 sides by the faces in all, 6 of them met.

### L2 W3 fix3: `check_levels_mutants.py`, new and changed cases

| Case | Rule | Expected |
|---|---|---|
| the island back at z 128; the island at x −401.818 (its west face on a column line) / control: z 128.05 (the inset off the line) | the coplanar line (fd-m1) | red ×2 / green |
| `ice.thickness` 0.6 / control 0.7; 2; 4; `slamFallSpeed` 480 | the sheet line (fd-m2) | red / green; red; red; red |
| re-aimed d-m6: Road2 2 deep, nothing under it / control `ice.thickness` 1 | the frozen layout's floor line | red / green |
| `sim_range.ice_cells` insets the creek's mouth too / control: the Pond's top 0.5 under the Creek's | the fill line (fd-s2) | red / green |
| `sim_range.ice_meets` ignores the top; takes a side met in part (the mirror alone) | check_stage_mirror | red ×2 |
| re-aimed: the Q6 west-twice swap and the Q6 mirror case on the new lines; d-m3's towers 0.5 south with the island | as before | as before |

## L3 W1: tiers per weapon, and the Forest on the new ladder (2026-10-20)

Contract: `docs/prompts/l3-w1-contract.md` (L3-1 to L3-39; its §12, the lead's rulings: Hard `rewardMult` 2.5 is data
only, `provingGear` is T1 for the simulators only, every non-starter family has a shelf hint). Ben's decisions:
`docs/MISSIONS_DESIGN.md` §10 and §24. Gear: Normal T1, Hard T3, Brutal T5, the Raider Arena T1; seeds 11 / 23 / 37.
Measured with `py tools/sim_range.py --check` (the launcher's 64-bit Python 3.12, the gate's; about 14 min),
`py tools/sim_combat.py --check` (about 4 min), `py tools/check_levels.py` and `py tools/check_levels_mutants.py`.
The "today" numbers are the same commands on a clean copy of `d9e7ad1` (the branch before this wave).

**Red at hand-off, for the lead (both are rulings, not data I own):** R8 on Hard (four rows, §R8 below) and the
climb's minutes (19.8 min against 25-40, §the climb). Everything else is green.

### L3 W1: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `Armory.json ladder.damage` | — | 20 values, `1.5 x 1.65^(t-1)` to 4 decimals (x1.5 .. x20,336.9677) | L3-1: T1 = the 2/2 every band was tuned at |
| `ladder.hp.melee` / `.ranged` | — | T1-T11 = the old slot tiers 2-12; T12-T20 melee 1,750 2,350 3,150 4,250 5,700 7,700 10,400 14,000 19,000, ranged 1,150 1,550 2,100 2,800 3,800 5,100 6,900 9,300 12,500 | L3-2. T12-T20 are mine: the old ladder's last steps grew about x1.36 a tier, so I carried x1.35 on, rounded, melee above ranged at every tier. Health grows slower than damage (x1.65) as it always has; later levels set their `damageScale` against MaxHp at their tier |
| `ladder.rangeHp` | (MaxHp of slot tiers 1/1) | **130** | L3-2: the range's own body, the old 100 + 20 + 10 |
| `ladder.bandSize`, `bands` | — | 4; `forestRoad` Timber, `castle` **Iron**, `underworld` **Ember**, `planet` **Glowstone**, `dream` **Crystal** | L3-4. **The four later materials are placeholders**, named after each level's dressing (§24) and kept apart from the C1 materials (Steel, Circuits, Alloy) so that a later level never pays into Ascension by accident; Ben names them with each level. They are never shown (L3-21) |
| `ladder.costs` | — | **[100, 100, 250, 500]** by position | Ben's Timber 100 / 250 / 500 for T2 / T3 / T4. Position 1 is never charged in band 1; **position 1 of bands 2-5 (100) is a placeholder** (Ben decides it with the Castle) |
| `ladder.starDifficulty` | — | `hard` | L3-4: the Hard star is the trophy |
| `Armory.json windows` | — | L3-3's table for all 15 families | Ben, as drawn |
| `Armory.json legacy.gearCosts` | — | the 12 frozen slot prices: Timber 10 / 60 / 180, then Steel, Circuits, Alloy the same | L3-8: the v8 refund; a 3/3 profile gets 500 Timber back |
| `Armory.json power.tierWeight` | — | **11** | L3-6: T1/T1 reads (1.5 + 1.5) x 11 + 155 x 0.2 = **64**, today's 2/2 value, so the hub's Village tile (60) still reads ready |
| `Combat.json debug.provingGear` | 2 / 2 | **1 / 1** | L3-11: the simulators' first-run gear only |
| `debug.gearPresets` | "2 / 2", "4 / 4", "6 / 6" | **"T1", "T3", "T5"** (melee = ranged = 1, 3, 5) | L3-15 |
| `debug.setTierAttribute`, `grantStarAttribute`, `resetArmoryAttribute` | — | `DebugSetTier`, `DebugGrantStar`, `DebugResetArmory` | L3-28 |
| `Expeditions.json found` | the Frost Hammer only | 12 entries: the Warhammer on `forestRoad` ("First Hard clear of Forest Road"), and the Castle, Underworld, Planet and Dream families of L3-3 ("Found in ..." for a level's own weapon, "Hidden in ..." for its secret's) | L3-25 as ruled: every non-starter family has a shelf hint; the Flamethrower keeps its secret's |
| `1_ForestRoad.json` Normal / Hard / Brutal `recommendedTier` | 2 / 4 / 6 | **1 / 3 / 5** | L3-15 |
| Hard `hpScale` | 5.2 | **4.25** | L3-15, re-measured (below): Hard's clock at T3 is today's at 4/4 |
| Hard `rewardMult` | 2 | **2** (2.5 measured, then reverted) | L3-16 then §12.8 (the lead's ruling after this measure): at ×2.5 the climb took 5 runs and 19.8 min, faster than Ben's "three runs a weapon"; ×2 gives 6 runs and about 24.6 min. A Hard clear pays 20 Valor |
| Hard `firstClear` | — | `{ family: "warhammer" }` | L3-17: arrives at T3, its window's start and Hard's tier |
| Brutal `firstClear` | — | `{ valor: 25 }` | L3-17 |
| `0_RaiderArena.json recommendedTier` | 2 | **1** | L3-15 |

### L3 W1: the ladder

| Tier | x range numbers | HP melee | HP ranged | MaxHp T/T | Gear Power T/T | Band | Price |
|---|---|---|---|---|---|---|---|
| T1 | x1.5000 | 35 | 20 | 155 | 64 | 1 forestRoad | - |
| T2 | x2.4750 | 50 | 30 | 180 | 90 | 1 forestRoad | 100 Timber |
| T3 | x4.0837 | 80 | 50 | 230 | 136 | 1 forestRoad | 250 Timber |
| T4 | x6.7382 | 120 | 80 | 300 | 208 | 1 forestRoad | 500 Timber + Hard star |
| T5 | x11.1180 | 170 | 110 | 380 | 321 | 2 castle | 100 Iron |
| T6 | x18.3447 | 250 | 160 | 510 | 506 | 2 castle | 100 Iron |
| T7 | x30.2688 | 350 | 230 | 680 | 802 | 2 castle | 250 Iron |
| T8 | x49.9435 | 480 | 320 | 900 | 1,279 | 2 castle | 500 Iron + Hard star |
| T9 | x82.4068 | 700 | 450 | 1,250 | 2,063 | 3 underworld | 100 Ember |
| T10 | x135.9711 | 950 | 620 | 1,670 | 3,325 | 3 underworld | 100 Ember |
| T11 | x224.3524 | 1,300 | 850 | 2,250 | 5,386 | 3 underworld | 250 Ember |
| T12 | x370.1814 | 1,750 | 1,150 | 3,000 | 8,744 | 3 underworld | 500 Ember + Hard star |
| T13 | x610.7994 | 2,350 | 1,550 | 4,000 | 14,238 | 4 planet | 100 Glowstone |
| T14 | x1,007.8190 | 3,150 | 2,100 | 5,350 | 23,242 | 4 planet | 100 Glowstone |
| T15 | x1,662.9013 | 4,250 | 2,800 | 7,150 | 38,014 | 4 planet | 250 Glowstone |
| T16 | x2,743.7872 | 5,700 | 3,800 | 9,600 | 62,283 | 4 planet | 500 Glowstone + Hard star |
| T17 | x4,527.2488 | 7,700 | 5,100 | 12,900 | 102,179 | 5 dream | 100 Crystal |
| T18 | x7,469.9606 | 10,400 | 6,900 | 17,400 | 167,819 | 5 dream | 100 Crystal |
| T19 | x12,325.4350 | 14,000 | 9,300 | 23,400 | 275,840 | 5 dream | 250 Crystal |
| T20 | x20,336.9677 | 19,000 | 12,500 | 31,600 | 453,733 | 5 dream | 500 Crystal + Hard star |

MaxHp (T1,T1) 155, (T3,T3) 230 and (T5,T5) 380 are today's 2/2, 4/4 and 6/6, so no `damageScale` moves. Every
cost from T5 up, and every material after Timber, is a placeholder until its level is built (the screen hides an
unbuilt band's price, L3-21).

### L3 W1: Forest Road on the ladder

| Difficulty, gear | Multiplier (melee / ranged) | Was | The reacting player's clears (min) | Mean | Today's mean | Gate |
|---|---|---|---|---|---|---|
| Normal T1 | x1.5 / x1.5 | 2/2: x1.5 / x1.5 | 5.26, 4.69, 5.04 | 5.00 | 5.00 | byte-identical |
| Hard T3, hpScale **4.25** | x4.0837 | 4/4: x5.0 / x4.5, hpScale 5.2 | 5.12, 5.34, 5.20 | **5.22** | 5.21 (306.7 / 319.9 / 311.8 s) | **+0.1%**, 0 downs (±5%) |
| Brutal T5, hpScale 11.5 | x11.118 | 6/6: x10.83 / x11.5 | 5.10, 5.43, 5.20 | **5.24** | 5.19 (305.7 / 321.5 / 307.2 s) | **+1.0%**, 0 downs (±5%) |
| Raider Arena T1 | x1.5 / x1.5 | 2/2 (P5 tuned it at 2/1; it has run at 2/2 since Ben's start preset, L1b Wave 2) | 10.08, 10.35, 11.49 | 10.64 | the same | identical |

- **Normal at T1 is byte-identical** to today's 2/2: diffing the two whole `sim_range --check` outputs with the gear
  labels made equal, the Normal and arena sections differ in no row. The only changes are labels, the new L3-26
  block, and Normal's "fast" row one preset up, which is now T3 (x4.08) instead of 4/4 (x5.0). Its tents still
  send (A 2, B 3; gate `TENT_FAST` green).
- **Hard's hpScale.** Every melee kill time is HP / multiplier, so 5.2 x 4.0837 / 5.0 = **4.247** keeps them all.
  4.25 keeps the clock at +0.1%. The bow gets relatively stronger on Hard (x4.08 against today's x4.5, on 18% less
  HP), which shows in R8 below. I probed above 4.25 to see whether a higher hpScale could save R8's Hard row inside
  the clock band. It cannot: at **4.45** the clock is **+16.8%** and at **4.6 +11.9%** (the clock is steep and
  not monotonic just above 4.25; tents and plates change with it), and LookoutLedge still out-earns at both.
- **The Colossus alone** (Broadsword, every seed): Normal T1 81.2 s (79.3-82.3), **Hard T3 81.7 s (79.8-83.6)**
  (today 81.6), Brutal T5 83.8 s (82.8-84.3) (today 84.2); the arena's Colossus 76.8 s and Warlord 97.7 s (bands
  64-90 and 77-101). The range's bosses are unchanged (scale 1, 130 HP).
- **The human gate, one preset below.** Hard at T1: seed 11 down in Pickets; seeds 23 and 37 clear at x2.38 and
  x2.46 his slowest T3 clear (needs a down or x1.8). The Colossus alone at T1 is not killed in 240 s (gate 135 s).
  Brutal at T3: down on all three seeds (needs a down or x1.4); its Colossus is not killed in 240 s (gate 180 s).
  Brutal's two presets are now x2.72 apart (they were x2.17), so its gate holds with room to spare.

### L3 W1: what a clear pays (L3-16, data only)

| | Cash | Timber | Valor | As times Normal |
|---|---|---|---|---|
| Normal | 131,733 | 211 | 10 | — |
| Hard (x2.5) | **354,750** | **595** | **25** | x2.69 cash, x2.82 Timber (band x2-x3) |
| Brutal (x4) | 568,933 | 906 | 40, and 25 more on the first clear | x4.32 / x4.29 |

KillReward rounds each kill half up, so x2.5 on 1-, 3- and 7-Timber kinds pays a little more than x2.5. Hard's cash
is 2.5% of the 14.28M the Village still costs at mid-era (the reference moment of assertion 4 since L3, below):
the "+25% of 0.9%" the lead accepted.

### L3 W1: the climb, both starters T1 to T4 (assertion 2)

The greedy solo player. Each run is measured by sim_range at the gear he holds then (the reacting player, sword
only; mean of the three seeds). He plays Normal until both starters reach Hard's recommendedTier (T3), then Hard.
Double Jump is bought with the first Valor that covers it. The next run takes the lookout's chest (50 Timber, 3
Valor and the Flamethrower). The run after carries the Flamethrower into the tunnel (the cache's 60 Timber, and
the shortcut is found), and he takes the tunnel ever after (it pays a little less a run and more a minute). After
each run he buys, cheapest first, every starter tier `Armory.UpgradeVerdict` allows.

| Run | Difficulty, gear | Clear | Timber | Bought after | Left |
|---|---|---|---|---|---|
| 1 | Normal T1/T1 | 4.99 min | 211 | Broadsword T2, Longbow T2 (and Double Jump, 10 Valor) | 11 |
| 2 | Normal T2/T2 | 3.75 min | 262 (lookout) | Broadsword T3 | 23 |
| 3 | Normal T3/T2, Flamethrower, tunnel | 2.63 min | 262 (cache) | Longbow T3 | 35 |
| 4 | Hard T3/T3, tunnel | 4.84 min | 539 (+ Hard star, Warhammer at T3) | Broadsword T4 | 74 |
| 5 | Hard T4/T3, tunnel | 3.57 min | 539 | Longbow T4 | 113 |

**5 runs (target 5-7: met), 19.8 min of clears (target 25-40: MISSED by 5.2 min).** The 31 minutes Ben was quoted
came from the study's model, which counted every run at 5 minutes. Measured, each upgrade shortens the next clear
(Normal at T2 takes 3.75 min, the tunnel at T3 2.63), and Hard at x2.5 pays 539-595 Timber, so one Hard run buys
T4 for one weapon. Before that ruling it took two. With Hard at x2, the same model gives **6 runs, 24.6 min** (runs
4 and 5 at 414 Timber each, then one more). That is Ben's "three runs per weapon", still 0.4 min under the band. The
simulated clock leaves out the lobby, the map, the loading, the detours to the two chests and the burning of the
brambles, so real play is about half a minute to a minute longer a run. The levers are Ben's prices (100 / 250 /
500) and the lead's x2.5, so the gate stays red and is reported. The first Normal clear pays **211 Timber** (needs
200), a Hard clear **25 Valor** and the Brutal first clear **25** (met).

### L3 W1: R8, the sniper (L3-26)

On Normal and Hard, two gears: the proving gear (T1/T1, as before) and **sword T1 with bow T4** (only the bow
upgraded), against the mission player at the same gear. He fights with the sword alone, so he is the comparison
the contract names. The pair player (sword and bow) is reported beside him. The known limit is unchanged
(`SNIPER_KNOWN_LIMIT_L4`: on Normal, LookoutLedge and Secret_lookout).

| Row | Spot | Sniper, cash / Timber a minute (seeds 11 / 23 / 37) | Mission player | Verdict |
|---|---|---|---|---|
| Normal, T1/T1 | every spot but the known two | under | 25.0K / 40.1, 28.0K / 45.0, 26.1K / 41.9 | green |
| Normal, T1 sword / T4 bow | every spot but the known two | under (the best LookoutSignPad 13.5K / 15.6) | the same (the pair player: 38.9K-39.9K / 63-65) | green; LookoutLedge up to x1.37 and Secret_lookout up to x1.66 (known limit, reported) |
| **Hard, T1/T1** | **LookoutLedge** (Double Jump owners) | **40.0K / 54.9, 34.3K / 41.2, 30.8K / 29.5** | 30.9K / 48.8, 29.2K / 45.7, 26.7K / 41.8 | **RED** (it was green by 2.5% at hpScale 5.2) |
| **Hard, T1 sword / T4 bow** | **LookoutLedge** | **110.1K / 190, 89.0K / 153.5, 110.1K / 190** | the same (the pair player: 45.6K-48.9K / 73-78) | **RED, x3.6** |
| **Hard, T1 sword / T4 bow** | **LookoutSignPad** | **55.8K / 88.2** every seed | the same | **RED, x1.8** |
| **Hard, T1 sword / T4 bow** | **Secret_lookout** (Double Jump owners) | **111.4K / 192.2, 118.5K / 204.5, 118.5K / 204.5** | the same | **RED, x3.6-4.4** |

All four red rows stand on the lookout's ledge or its sign pad above Pickets, and every hit of the sniper lands.
They are Normal's known limit appearing on Hard. Camps never refill, so the pay is bounded: a sniper from the
lookout earns, over a minute or two, only what the residents he can see are worth, and then has to come down and
fight. No hpScale inside the clock band fixes the T1 row (probe above). The bow-T4 rows are structural: a x6.74
bow against a x1.5 sword out-earns from any perch that sees a camp. L3-35 says no layout change in W1 without the
lead, so these rows are reported, not fixed. The lead's options:

1. Extend the known limit to Hard until L4 re-places the perches. This is data only in `sim_range.py`:
   `SNIPER_KNOWN_LIMIT_L4 = {"normal": ("LookoutLedge", "Secret_lookout"), "hard": ("LookoutLedge",
   "LookoutSignPad", "Secret_lookout")}`. The gate already reads the key per difficulty. It is Ben's ruling of
   2026-10-16 carried to Hard.
2. A layout change at the lookout (L4's re-placement, early).

### L3 W1: the income gate is retired (L3-4, Ben 2026-10-20)

`unlockRate` is no longer read by the tier path, so sim_combat's C0 unlock table and assertions "1 unlock ladder"
and "2 power at median" are gone. Assertions 1 and 2 are now L3's (the ladder, the climb). Assertion 4 ("run cash
at most 25% of what the era still costs") was anchored at the moment the city's income reached the recommended
gear's unlockRate. With no gate, a run can come at any time, so it is anchored at mid-era: the Raider Arena's
144,250 cash is **1.01%** of the 14.28M left at 20:55 (it was 0.97% at 12:21). The C1 Humanoid missions' run model
keeps the slot tiers' own health and power (`c1_max_hp`, `c1_gear_power`: the scale `Missions/*.json
recommendedPower` was written on), so assertions 3 and 5-14 are unchanged to the digit. The slot ladder's
`unlockRate` values stay in Armory.json, unread, until L4 deletes `slots` with its last C1 reader.

### L3 W1: new gates and their mutants

| Gate | Where | Shown red by |
|---|---|---|
| Assertion 1, the ladder: Armory.Problems (Armory.luau's lines, mirrored) and the shipped values against L3-1..L3-4 and L3-8 | sim_combat | 20 hand mutants in a scratch run: a damage value off the curve or falling, 19 entries, an HP value off the old slot tier, ranged over melee, a falling HP row, rangeHp 120, tierWeight 10, four bands, bandSize 5, the Forest band in Iron, costs 100/100/300/500, starDifficulty brutal, a window changed / missing / starting at 2 / 5-3, a legacy amount, a legacy entry missing, no ladder: all red |
| Assertion 2, the climb | sim_combat | 11 hand mutants on its verdict (not done, 4 and 8 runs, 41 and 24 min, a 199-Timber first clear, a seed not cleared, Hard x2, Brutal's 20 Valor, the Greataxe or nothing as Hard's first clear): all red; six 5.5-min runs green |
| Every non-starter family has a shelf hint (L3-25) | check_levels | the Greataxe's found entry gone; the lookout paying no family / control: the Greataxe found on the Underworld |
| A firstClear family's found entry names its level's node (L3-25) | check_levels | the Warhammer found on the Castle / control: its text reworded |
| ownedFamilies counts every firstClear family (L3-25; the bend's known limit) | check_levels | Hard's first clear gives the Spear (it carries) / control: the Shotgun |
| R8's reach = the longest range of the ownable ranged families (L3-25; was the Longbow's alone) | check_levels | the Rifle's range 400 given by Hard's first clear / control: range 400, nothing gives it |
| Validate's firstClear lines (L3-17; `first_clear_problems` mirrors StageFlow's five lines in its order) | check_levels, check_stage_mirror | a starter, a family that is none, Valor 2.5, Valor -1, a firstClear that is a string / control: Valor 0 |
| The three L3-28 attributes are names of their own | check_levels | one shares DebugGrantFamily, one missing, one shares DebugSetGear |
| The presets T1 / T3 / T5, the first the proving gear, every recommendedTier a preset's | check_levels | provingGear 2/2, Hard's recommendedTier 4 / control: Brutal's 3 |
| Hard and Brutal keep their clock (L3-29) | sim_range | `L3_CLOCK_SECONDS` hard pinned at 345 s (SIM_CASES) |
| R8 with only the bow upgraded (L3-26) | sim_range | LookoutLedge out of Normal's known limit (SIM_CASES); and the shipped Hard rows |

**Lead's rulings after this measure (2026-10-20, contract §12.8–9):** Hard's `rewardMult` back to **2** (the climb:
6 runs and about 24.6 minutes, `CLIMB_MINUTES` 20–40, a Hard clear 20 Valor); the four Hard R8 rows join Normal's
known limit until L4 (`SNIPER_KNOWN_LIMIT_L4["hard"]` = LookoutLedge, LookoutSignPad, Secret_lookout), reported, not
gated. The tables above were measured at ×2.5; re-run `py tools/sim_combat.py --check` for the ×2 numbers.

## L3 W1 fix round: the trophy, and every weapon at its own tier in the simulators (2026-10-20)

Rulings: `docs/prompts/l3-w1-fix-round.md` R1 (review `1-saving.md` m5) and R2 (review `2-combat-server.md` M1,
with its two pair-gate rulings). Measured with `py -3.12 tools/sim_range.py --check` (64-bit, the gate's; about
15 min), `py -3.12 tools/sim_combat.py --check` and `py tools/check_levels.py`. The "before" numbers are the same
commands, or the reviewer's probe (`s2probe/pair_scale.py`), on a clean copy of `f6c426d` (a2628da plus the
reviews). Forest Road Normal, seeds 11 / 23 / 37.

### Fix round: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `Armory.json ladder.starAlso` | — | `["brutal"]` | R1: a band's top tier opens with that level's Hard star or a harder one, so a Brutal clear (a party can carry a T3 player through it) also opens T4. `starDifficulty` stays `hard`: the star the screen names and the U lever grants. The map's stars are unchanged |
| `sim_combat.py` `star_held`, `upgrade_verdict`, `problems` | `_star_held(starDifficulty)` | `star_held(cfg, combat, levelId)` = `Armory.StarHeld` (starDifficulty or any starAlso; false without a ladder or a profile). Problems adds A's line "ladder.starAlso is not a list of difficulty names" | R1: the mirror of A's `Armory.luau`; `check_stage_mirror` compares them |
| `sim_combat` assertion 1 | starDifficulty `hard` | also starAlso `["brutal"]` (`LADDER_STAR_ALSO`) | R1: the shipped value is pinned |
| `check_levels` `check_trophy` (new) | — | starDifficulty is a difficulty of Expeditions.json, and starAlso lists exactly the difficulties after it, in order | R1's "or a harder one", held to the data: no easier star opens a band top, and a difficulty added later (Overdrive) cannot be left out. Armory.Problems checks only the shape |
| `sim_range` `level_view(held=)`, `gear_max_hp(held=)`, `gear_profile`, `held_pair`, `held_scale` | the level player scaled each strike by its SLOT's gear tier; the bar was the gear's | every strike at the striking family's own `Armory.TierOf`, for a profile whose starters stand at the gear (a non-starter at its window start); the slam at the held melee's; the fire sniper's cast at the fire family's; the bar and the regen the held pair's (`HeldTiers`). A run on a view built for another held pair, or with another bar, is refused | R2 (2-M1): what `WeaponService.damageScale` and `gearOf` do since L3-6 |
| `sim_range` run results `armed`, gate "fights at each family's own tier" (new) | — | each pair run and fire-sniper run records its held pair, bar and scales; `armed_problems` recomputes them with `Armory.HeldTiers` and fails any difference | R2: the mirror proves itself (the shipped gates were green on weapons the game does not field) |
| `PAIR_FLAME_GEAR` (new) | the Flamethrower pair at the row's gear, T1/T1 | **T2/T2**: the Flamethrower at T2, and its yardstick (Broadsword + Longbow) at T2/T2 too | R2: like with like, at the gear he holds when the Flamethrower first comes (the climb's run 2) |
| `PAIR_CLEAR_MINUTES` (4.0, 5.75) | absolute minutes | **`PAIR_CLEAR_SHARE` (x0.939, x1.350)** of the starter pair's mean clear at the same gear | R2: 4.0 / 4.259 and 5.75 / 4.259, where 4.259 min is the starter pair's mean T1 clear (248.1, 259.2, 259.4 s) when the band was set. At T2 the band is 3.04-4.37 min. Both ends are converted ("every pair limit becomes a ratio") |
| `PAIR_CASH_SHARE` 1.10, `PAIR_BOSS_SHARE` 0.90 | ratios to the starter pair at T1 | the same ratios, to the starter pair at T2/T2 | R2: today's ratio limits are kept |
| The Frost Hammer pair rows (clear, cash a minute, the Colossus) | gated at T1, the Frost Hammer at x1.5 | **reported, not gated, until the Castle**; the Frost Hammer at T5 (x11.118), bar 290 | R2: a Castle weapon arriving at T5, lever-only in the Forest. Its armed check stays gated, as does every frost-crossing and geometry gate |
| `sim_combat` climb, run 3 (the fire family into the tunnel) | the ranged "gear" set to the Flamethrower's tier | the starters' tiers, with the view holding Broadsword + Flamethrower (`holds`) | R2: `gear` now means the starters' tiers everywhere. Same bar, same clear (2.63 min) |
| `sim_combat` assertion 2 | — | also checks that the run whose chest pays the fire family is at `sim_range.PAIR_FLAME_GEAR` | R2: the pair's gear comes from the climb; if prices move the lookout run, this turns red |

### Fix round: the pair rows, before and after (Forest Road Normal)

| Row | Gear (bar) | Before: the sim as shipped | The game's rule at T1 (the reviewer's probe) | After (R2) | Verdict |
|---|---|---|---|---|---|
| Broadsword + Longbow | T1/T1 (155) | 4.14 / 4.32 / 4.32 min; 30,859 cash a minute; Colossus 76.4 s | the same | the same (now the Frost Hammer's yardstick, reported) | — |
| Broadsword + Flamethrower | T1/T1 (155), Flamethrower x1.5 | 4.06 / 4.24 / 4.17 min; x1.02 cash; Colossus x0.99 | 4.04 / 3.93 / 4.03 min (seed 23 under the 4.0 floor); x1.07; x0.96 | no longer rated at T1 | — |
| Broadsword + Longbow | **T2/T2 (180)** | — | — | **3.34 / 3.16 / 3.20 min (mean 3.23)**; 40,344 cash a minute; Colossus 46.2 s | the yardstick |
| Broadsword + Flamethrower | **T2/T2, Flamethrower T2 (180)** | — | — | **3.20 / 3.16 / 3.20 min**, band 3.04-4.37 (x0.939-x1.350 of 3.23); **40,991 cash a minute, x1.02** (<= x1.10); **Colossus 46.2 s, x1.00** (>= x0.90); no down | **PASS** |
| Frost Hammer + Longbow | T1/T1 (155), Frost Hammer x1.5 | 4.46 / 4.69 / 4.43 min; x0.95 cash; Colossus x1.08 | 2.22 / 2.30 / 2.27 min; x1.83; 13.9 s, x0.18 (bar left at 155) | **2.22 / 2.30 / 2.27 min; 56,507 cash a minute, x1.83; Colossus 13.9 s against 76.4 s, x0.18; bar 290** | **reported until the Castle** (it would fail all three of the old limits) |
| The fire sniper's Dragon's Breath (R8, L2-37), tunnel open | T1/T1 (155); the cast at the Flamethrower's T2 (x2.475; it was the bow's x1.5) | Normal: CaveMouth 799 / 3,994 / 533 cash a minute, CaveExit 2,037 / 2,037 / 582 | the same | the same on Normal and on Hard: the larger cast kills nothing more from those spots; 6 runs cast on each difficulty | PASS, unchanged |

What it means for play: at the gear it comes at, the Flamethrower pair is a sidegrade (x1.02 cash, the same boss
time), as L2 W2 intended. The Frost Hammer is a T5 Castle weapon. Given in the Forest by the Studio lever I, it
clears Forest Road in about 2.3 minutes and kills the Colossus in about 14 s. That is the expected size of a
four-tier jump (x7.4 on the hits), not a balance fault; the Castle re-bands it.

### Fix round: the L3-27 mirror row (to add to the contract's table)

| Mirror | Mirrors | Owner |
|---|---|---|
| `sim_range.py` `gear_profile`, `held_pair`, `held_scale`, `level_view(held=)` and `gear_max_hp(held=)` (the level player's hit, pair-kit, slam, cast and breath scales; his bar and regen), held to the game's rule by `armed_problems`; `sim_combat.py` `climb_runs(fire=)` | `WeaponService.damageScale` (TierOf of the striking family; the slam passes the held melee) and `gearOf` (`Armory.HeldTiers` of the held pair) | designer |

### Fix round: new gates and their mutants

| Gate | Where | Shown red by |
|---|---|---|
| R1: starAlso names exactly the difficulties after starDifficulty (`check_trophy`) | check_levels | starAlso `[]`, absent, `["normal"]`, `["brutal", "brutal"]`; starDifficulty `heroic`; a difficulty added after Brutal and not listed / control: that difficulty listed. Scratch run, all as expected; entries proposed to the lead |
| R1: StarHeld and the starAlso Problems line (the mirror) | sim_combat, check_stage_mirror | A Brutal star opens T4 and a Normal star does not. `"brutal"`, `[""]`, `[3]` and `{"a": "brutal"}` are named; `[]`, `{}` and absent are silent. Scratch run; check_stage_mirror PASS against A's Luau |
| R2: each run fights at each family's own tier, the bar the held pair's | sim_range | the SIM_CASES proposed to the lead (results below) |
| R2: the fire sniper casts at least once, so its tier check is not vacuous (fix 2, F6: judged per course) | sim_range | — (CaveExit's courses cast; CaveMouth is in `BREATH_OUT_OF_REACH`: its nearest body stays 25.7 studs off, Dragon's Breath reaches 20.8) |
| R2: the Flamethrower pair at T2/T2, its limits as ratios | sim_range | `PAIR_FLAME_GEAR` back at T1/T1 (SIM_CASE below) |
| R2: the fire family comes at `PAIR_FLAME_GEAR` in the climb | sim_combat assertion 2 | `PAIR_FLAME_GEAR` at T3/T3: assertion 2 red, every other assertion green (hand mutant) |

The R2 SIM_CASES, proposed for `check_levels_mutants.py`. Each was run here through its own `sim_case`
(`--check --levels-only --level forest`), and all went red as expected:

- every family's scale read from its slot's gear again: FAIL (5); the Frost Hammer pair fights at x1.5 instead
  of x11.118, and so does its slam;
- the bar from the gear, not the held pair: FAIL (1); bar 155 instead of 290;
- the fire sniper's cast at the bow's scale: FAIL (4); x1.5 instead of x2.475;
- the slam as the starter melee, not the held one: FAIL (1); slam x1.5 instead of x11.118;
- `PAIR_FLAME_GEAR` back at T1/T1: FAIL (1); the pair clears in 4.04 / 3.93 / 4.03 min against a band of
  4.00-5.75. Seed 23 falls under it, which is the reviewer's finding: rated unlike with like, the pair looks too fast.

The full `sim_range --check` output differs from the clean copy's only in the cave section above (71 lines): every
Normal, Hard, Brutal, arena, R8 and range row is byte-identical. PASS lines went from 549 to 561: six old pair
gates left and eighteen new ones came in.

## L4 W1: the lookout at the trailhead (2026-10-21)

Ben's ruling (MISSIONS_DESIGN 26.1): the lookout moves to the trailhead, the study's V3, so the perches L1 to L3
accepted as a known limit go away and R8 gates every spot. Measured on Python 3.12.10 64-bit (the gate's) unless
said otherwise.

### L4 W1: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `Layouts/Levels/ForestRoad.json` LookoutLedge | (-283, 15, -59), 24 x 38 x 14, top 34 over Road5 (0.0 off the plateau region) | **(-446, 11, -33), 24 x 30 x 14**, top 26 over Road1, 18 studs across the void from Road1's north edge | 26.1: 132 studs from the nearest region cell, beyond the Longbow's 110 and `dormantRadius` 120 |
| the `lookout` secret | (-283, 36, -59) | **(-446, 28, -33)**, on the ledge | the chest goes with its ledge |
| its sign | (-301, 8, -57) on LookoutSignPad | **(-447, 0, -5)**, on Road1, its foot flush with the road's north edge | the study had z -2, which stood the 6 x 4 x 6 walk-through sign across the walking line at the spawn; at -5 it sits beside the road on the ledge's side, as the cache's sign does on Road4 |
| LookoutSignPad block and its `plateau` region cell | a 10 x 12 x 10 step, top 8, and a 6 x 16 cell | **removed** | the step to the old ledge; its west 4 studs were a Hard sniper spot (x2.09 with the bow at T4) |
| `check_levels.py` `EXPECTED` sniper lists (all four) | with LookoutLedge, LookoutSignPad, Secret_lookout | **without them** | the pinned lists are what check_levels finds; nothing else moved |
| `sim_range.py` `SNIPER_KNOWN_LIMIT_L4` | Normal: LookoutLedge, Secret_lookout; Hard: the same and LookoutSignPad | **removed, with its reader and `r8_gate`'s `known` branch** | an empty exemption would be dead code; every spot is gated (Ben, 2026-10-16) |

No game number moved; `Config/Levels/1_ForestRoad.json` is unchanged. check_levels: PASS (the lookout's L2-18 (a)-(d)
hold: 26 over the road, "the closest call: Trailhead, 5 studs short" for one jump, a step up and a dash; no lifting
ability's arc reaches it).

### L4 W1: R8 before and after (the gate's seeds 11 / 23 / 37)

Best cash a minute over the seeds, as a multiple of the mission player's on the same seed (the bow-T4 rows' mission
player fights with the sword alone, so his rates are the T1 ones). "Before" is a clean copy of HEAD 59a2279 run on
the same machine and Python.

| Table | Spot | Before | After |
|---|---|---|---|
| Normal, T1/T1 | Secret_lookout / LookoutLedge / LookoutSignPad | x1.59 / x1.35 / x0.54 (the first two known limit) | gone |
| Normal, T1/T1 | Road3 / Road2 / Road4 | x0.72 / x0.69 / x0.06 | the same |
| Normal, sword T1 / bow T4 | Secret_lookout / LookoutLedge / LookoutSignPad | x1.66 / x1.37 / x0.54 (known limit) | gone |
| Normal, sword T1 / bow T4 | Road3 / Road2 / Road4 | x0.72 / x0.69 / x0.06 | the same |
| Hard, T1/T1 | LookoutLedge / LookoutSignPad / Secret_lookout | x1.30 / x0.93 / x0.62 (known limit) | gone |
| Hard, T1/T1 | Road3 / Road2 | x0.87 / x0.83 | x0.87 / x0.83 (Road3 seed 11: 20,288 -> 14,082) |
| Hard, sword T1 / bow T4 | Secret_lookout / LookoutLedge / LookoutSignPad | x4.44 / x4.13 / x2.09 (known limit) | gone |
| Hard, sword T1 / bow T4 | Road2 / Road4 / the gatehouse | x0.83 / x0.15 / x0.15 | the same |
| **Hard, sword T1 / bow T4** | **Road3** | x0.79 (seed 11: 8 kills in 13 s) | **x1.60, RED** (seed 11: 16 kills in 13 s, 39,504 / 55.1 against 24,703 / 37.2) |
| Hard, the tunnel open | CaveMouth | seed 11: 0 | seed 11: 19,164, x0.78; its "nearest point" rows went (it is one point now) |

Every other spot (RoadBC5, RoadBC6, ShrineSignPad, Creek, CaveExit) is byte-identical. `sim_range.py --check`:
**CHECK: FAIL (1)**, that Road3 row, in 11 min 46 s; HEAD: PASS.

### L4 W1: Road3 on Hard with the bow at T4 (the lead's decision)

The cause, isolated on in-memory variants of HEAD's layout (sim_range's own `LevelRun`): dropping only the
LookoutSignPad **region cell** reproduces the new rows exactly. The block alone and the ledge's move change nothing for
Road3. The cell was one of the sim's sight blockers (`scene_walls`) and a place chasing bodies stood. Without it, on
seed 11 camp A's fireN group reaches the plateau's west edge in Road3's view inside the 13-second window, beside
fireW.

**The row was red before too, out of the gate's seeds.** The same course over seeds 1-30, counting a seed when its
cash or Timber a minute beats the lowest of the three gate-seed mission rates (Normal 24,986 / 40.1, Hard 21,332 /
31.9):

| Course | HEAD | L4 W1 |
|---|---|---|
| Hard, sword T1 / bow T4, Road3 | 12 of 30, worst 67,179 (26 kills in 13 s, x3.1) | 13 of 30 (11 added), worst the same |
| Hard, sword T1 / bow T4, Road2 | not run | 10 of 30, worst 47,489 (18 kills, x2.2) |
| Hard, T1/T1, Road3 | not run | 7 of 30, worst 21,352 (x1.00) |
| every other spot, Hard, both gears | not run | 0 of 30 |
| every spot, Normal, both gears | not run | **0 of 30** |

From Road3's corner (-340, 0, -51), 38 studs off and 8 below the plateau, and from Road2, the straight course pulls
camp A's west groups to the plateau's edge and kills one, two or three groups in 13 s with the x6.74 bow. That pays
4-14K once (camps never refill), but as a rate it is x0.8-x3 the sword-T1 mission's. It is L3's structural point
(a bow at T4 against a sword at T1 out-earns from wherever it sees a camp) at a spot that is not a perch. No wall
can stand between the low road and the plateau's edge without standing on Road4, and a body stopped at the region's
edge is always in view from below. Options for the lead:

1. **A plateau nub where the pad stood**: a block (-299, 2, -57) 6 x 12 x 10 wholly under a restored region cell
   (-299, -54) 6 x 16, so nobody on it is out of a rusher's reach. Measured: check_levels PASS with the same
   pinned lists, and Road3's three gate seeds are back to HEAD's (8 / 8 / 3 kills), so `--check` passes. Road2 and
   Road3 stay out-earning on a third of the seeds: this only restores the gate seeds' luck.
2. **Ben rules on the Hard bow-T4 burst** from the low road: a one-off 4-14K in 13 s, then the player still fights
   the rest.
3. **Change what R8 measures** for a burst (`sim_range.py`, mine, but it changes the gate's meaning): for example,
   rate a course on more seeds, or on its pay against what the mission player earns from the same residents.
4. **Camp A's design** in the real forest (26.2's natural edges, the west fires' posts), so that one pull from the
   road wakes one group, not three. This is the wave's forest work, with every camp gate re-run.

### L4 W1: `check_levels_mutants.py`, re-aimed cases

| Case | Was | Now |
|---|---|---|
| L2-18b, a step the ledge is one jump from | a ledge (top 14) west of the sign pad | the same step in the void between Road1 and the ledge (x -450..-446, z -22..-16) |
| L2-18b, a cliff on the ledge's east side (84 control, 60 red) | x -275..-271, z -66..-52 | x -438..-434, z -40..-26 (`cliff`) |
| L2-18a, the ledge 6 higher | top 40, chest y 42 | top 32, chest y 34 |
| L2-18d, the chest at the front edge / 1.5 back (control) / 2 back | z -54 / -60.5 / -61 | z -28 / -34.5 / -35 (the back edge is z -40) |
| L2-18d, a root on the road below | secretBelow 25, secretReach 8 (Road5) | secretBelow 25, secretReach 26 (Road1, 22 off the chest's footprint) |
| L2-18c, Leap Smash height 20 (a target on A's fence) | red | **height 23 red, 22 green**: at the trailhead every take-off is ground at 0, so the margin over the shipped 10 is 13 studs |
| L2-37f, the ridge CaveWallS1 | 60 red / 81 control (43 over the lookout's chest, 38) | **54 red / 55 control** (43 over camp A's fence and the cache's chest, 12); plus 80 red with L2's lookout put back |
| d-M1, the 84 ridge (five cases) | measured from the lookout's ledge | the same cases with L2's lookout put back (`l2_lookout`). Without it the three red ones go green: on today's data nothing lifts a player onto a 64-high ridge, so d-M1 alone no longer needs the 84 tops (CaveWallS2, CaveRoofE, the alcove); whether another gate does was not checked |
| W3 frozen, a pond by the ledge | x -295..-271, z -80..-68, 17 red / 6 control | x -458..-434, z -54..-42 (behind the ledge), 17 red / -1 control (the creek's own height) |
| SIM_CASES L3-26 | LookoutLedge out of Normal's known limit | **R8's band at half the mission's pay**: Road3's Normal sword-T1 / bow-T4 row (x0.72) goes red, which it can only do while the bow-upgraded rows are gated |

`tools/crowd_harness/tests_l2.luau` (realTests): the "from the road below" case read Road5's 8 as a literal. Under the
new ledge, one jump from 8 would reach the chest's band. It now reads the road from the layout's route point nearest
the chest (0). Shown red with the old 8 (1 of 4,032 checks), green as written.

## L4 W2: the mountain climb and the Castle Key (2026-10-21)

Ben's request (MISSIONS_DESIGN 28): a parkour of double jumps round a mountain behind the trailhead, one lap of about
eight, 1-2 minutes, wide ledges, a miss drops you to the ledge below; a summit chest that gives the Castle Key. Measured
on Python 3.12.10 64-bit (the gate's). Report: `docs/prompts/l4-w2-reports/mountain.md`; gate: `tools/check_parkour.py`.

### L4 W2: what changed, and why

| Key | Was | Now | Why |
|---|---|---|---|
| `Layouts/Levels/ForestRoad.json` blocks | 61 | **72**: `MountainPath` (96 x 16 off the trailhead's west edge), `MountainTrail` (16 x 54 north), `MountainYard` (96 x 96, x -658..-562, z -158..-62), `MountainLedge1..7` and `MountainSummit` (the core, 28 x 28) | a walled yard behind the trailhead with a 200-stud stepped mountain in it |
| ledge tops | | **25, 50, ..., 175, the summit 200: every hop 25** | one jump and check_levels' step up reach 21 (4 short); the double jump peaks at 30 (5 over); horizontally a dash outreaches the double jump, so only height makes a hop need it |
| hops | | **flush**: each ledge's face rises straight off the end of the one below (no gap) | a missed double jump hits the face and drops back onto the ledge it left (Ben's "a miss drops you to the ledge below") |
| ledges | | **24 x 20** (the lookout ledge is 24 x 14); faces 20-24 wide | a phone's thumb; LEDGE_MIN 14 x 20, FACE_MIN 14 |
| the `mountain` secret | | **(-610, 202, -110)** on the summit, needs `doubleJump`; sign "MOUNTAIN - needs DOUBLE JUMP" at (-490, 0, -5) on the path | the fourth Forest chest (the lead's ruling) |
| `Config/Levels/1_ForestRoad.json` `secrets.mountain` | | **`{ "name": "Mountain Summit", "valor": 4, "materials": 50, "key": "castle" }`** | below |
| `check_levels.py` | | the pinned secrets with `mountain`; L2-18a judges a climb's chest over its last ledge (`check_parkour.ledge_below`); one call to `check_parkour.check_climbs` | the band would otherwise measure the summit against the road 200 below |

### The pay

The Forest's Normal clear pays about 10 Valor (Double Jump costs "one clear") and holds 220 Timber, in about 5 minutes:
roughly 2 Valor and 44 Timber a minute. A first climb is about a minute (a perfect one 21 s) and is the hardest
double-jump test in the game, so **4 Valor and 50 Timber** (23% of the Normal stock) pay about two minutes' Valor and a
minute's Timber, once per player. Between the lookout (3 + 50, a 15-second detour that also gives the Flamethrower) and
the shrine (6 + 60, which needs Castle gear and stays the best chest). The Castle Key is the prize. Inside L2-13 /
L2-37 (2 or more Valor, under Double Jump's 10; 15-30% of the stock).

### Flight, the new measure

`check_parkour.flight_reach` is longer than check_levels' `stray_reach` because MovementController lets the double
jump fire any time after `airJumpDelay` and *set* the rise (late in a fall it buys most), and an air dash's flat mover
leaves no fall speed. From 200 up: 90.8 studs (stray_reach 66.2; no dash 61.1); from 50 up: 69.0. After a landed slam
the dash key dashes for `slamCooldown` 1.8 s, so three dashes fit in one flight: 133.3 from 200 up (an outer bound,
reported, not gated). The yard's only mouth is 116-181 studs from every top: past each flight plus Leap Smash's 32
plus 10 (tightest L2, +5.1), and past even the three-dash bound by 10.8 or more.

One gate number moved: check_levels' frozen-sheet bound (W3 fd-m2) falls from the jumps' apex over the highest top
reached anywhere, now the summit, so the fastest fall onto the ice is 1.265 studs a physics step (was 0.644). The
shipped sheet, `levels.react.ice.thickness` 1.9, still passes (under the root's 2); the mutant pair around the bound
moved from 0.6 / 0.7 to 1.2 / 1.3. No game number changed; nothing in `Economy.luau`.
