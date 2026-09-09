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
