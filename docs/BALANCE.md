# BALANCE — M2 first full balance pass

Produced by `python tools/sim_economy.py` (mirrors `src/shared/Economy.luau` and reads the
real configs — regenerate any table below by rerunning the tool). The sim's greedy player
buys the cheapest affordable thing (slots and level-ups) every second; `--strategy rusher`
buys slots only. `--check` (used by QA) exits nonzero if any era of the default greedy run
misses its spec §4 band.

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
- **Cash packs (M4 heads-up):** packs are priced in minutes of current income, which caps any
  pack's skip at its minute value — sound for eras 3–4, but `Cash8h` (480 min) exceeds the
  entire length of eras 1–2, so mid-era it would effectively finish them, contradicting §6's
  "can never skip an era". Recommendation for the M4 shop: hide `Cash2h`/`Cash8h` before Era 3
  (mirroring the existing "hide when ID is 0" pattern), or cap a single grant at ~25% of the
  era's remaining slot cost. Decision belongs to M4; flagged here because the numbers are now
  known.
