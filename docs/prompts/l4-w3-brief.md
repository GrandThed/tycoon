# L4 W3 — the city map, the end screen, run cash by era (brief)

Two agents run from this brief in parallel. **Part A** drafts the contract. **Part B** sets out the era-cash numbers that
Ben will pick from. Neither writes game code.

Common rules: work in `C:\Users\benja\Desktop\tycoon-p5` (branch `l4-w3`, cut from `main` at `dce50da`, which holds all of
W1, W1b and W2). Do not commit. Kill only your own PIDs (never by image name). Tools: `py` only (`python`/`python3` are
Store stubs); `export PATH="$HOME/.rokit/bin:$PATH"`; the Luau CLI is `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`.
Scratch files go in your own subfolder of the session scratchpad
(`C:\Users\benja\AppData\Local\Temp\claude\c--Users-benja-Desktop-tycoon\259ecf10-ad47-49f7-9d11-55e5c7db6b5a\scratchpad\l4-w3-<a|b>\`),
never in the repo. Write your file as you go (a cut-off then loses nothing), LF line endings.

## What W3 is (Ben's decisions, all taken)

`docs/MISSIONS_DESIGN.md` §26 items 5, 6, 7, 8 and the lead's rulings under it; §28 (the Castle Key); §29 (W2 signed off).
The groundwork is `docs/prompts/l4-study-report-publish.md` §1 (the map in the hub), §2 (rewards against the city), §3 (the
end screen), §6 D1 / D3 (Ben took option A for both). What earlier waves handed to W3: `docs/PLAN.md` "L4" → "W3 and W4"
and "Carried" (lines ~4876-4935); `docs/prompts/l4-w1b-contract.md` L4B-1, L4B-2 and rows 20 onward of §2 (the hub stub,
`Combat.json overdrive`, `RunSummary.overdrive` / `missionId`, the fakeRuns lever). Project rules: `CLAUDE.md` (server owns
state, intents not amounts, rate limits, `pcall` + retry on DataStore/MemoryStore/Teleport, `Economy.luau` pure, constants
only in Config JSON, the 180-locals compile gate: `py tools/check_compile.py`).

1. **The map in the city departs straight into the level.** The hub's era tiles go; the shared `MapScreen` mounts in the
   hub. Depart → one loading screen → the lobby camp counts down and starts the level once the expected party is there;
   any refusal (stars changed, a member missing at the cap, a bad ticket) falls back to the lobby with the level picked.
   Node rules move to one pure shared module both places call. The ticket, the teleport hint and the Studio bridge
   record carry `levelId` + `difficulty`; `missionId` / `overdrive` go. The party strip stays; the run list stays as it is
   (joining a live run is L5).
2. **The Raider Arena stays hidden** (W1b hid it); W3 deletes what kept it alive for the hub: `Config/Missions/1_Village.json`
   (the stub), `Combat.MissionUnlocked`, `RecommendedPower`, `highestEra` as a gate, the Overdrive toggle,
   `Combat.json overdrive`, the TopBar Gear Power chip, the hub summary's `Catalog.GetMissionById`, the stale DebugBots
   comment. Check every reader first; list what must not go.
3. **The end screen:** one row per source counting up (raiders, each camp's bonus, the Camp Chief, each chest, the
   first clear, the Castle Key), then coins flying into the wallet and Timber piling up, Valor beside it; **the same card
   in both places** (the combat place after a run, the hub on the way home). Every number is the server's: a per-source
   `RunSummary.lines`, credited at today's call sites. No sound (combat sound ids stay 0). Phones: the motion runs
   shortened under `Theme.reducedMotion` (true on every touch device), the icon count is gated on `Theme.lowEndDevice`,
   a tap skips to the end, it fits 640×360 under the 58 px top bar.
4. **Run cash grows with the city's era:** a fixed amount per kill × an era multiplier, so a clear is worth a few minutes
   of that era's income. Cash only (Timber and Valor unchanged). Part B produces the candidate tables; Ben picks the
   anchor; the contract carries the mechanism and points at Part B's file for the numbers.
5. **Valor gets a purpose on screen:** the next ability shown locked "with the Castle" (lead ruling, §26). Check whether
   L3 / L4 already did it.
6. **A better simulated human** (PLAN carried: slow on several threats, misreads tells, hit by melee), if it fits the
   wave; otherwise the contract says why it waits.

## Part A — the contract drafter

Write `docs/prompts/l4-w3-contract.md` (only that file). Settle:
- **Owners with disjoint files.** luau-engineer A: `src/shared/**` (not Config/Layouts) and `src/server/**`;
  luau-engineer B: `src/combat/server/**`; ui-engineer A: `src/client/**` except the shared card if you give it to B;
  ui-engineer B: `src/combat/client/**` (and the shared card module, wherever it lives); economy-designer:
  `src/shared/Config/**`, `src/shared/Layouts/**`, `tools/**` simulators and gates, harness texts, `docs/BALANCE.md`;
  lead: project files (`*.project.json`, `tools/proving_project.py` if needed). Name every relay between owners.
- **The data shapes:** the new remote payload(s) and their validation and rate-limit bucket, the ticket and hint fields,
  the shared node-rule module's API (and how `check_stage_mirror.py` follows the move), `RunSummary.lines` (type, how
  it rides to the hub), the era multiplier's Config key and the one choke point where it is applied (beside
  `Combat.CombatCashMult`, `src/shared/Combat.luau:223`), which era it reads (the city's current era from the profile,
  frozen for the visit) and how `sim_combat.py` mirrors it.
- **The auto-start:** generalise the proving build's auto-start path; the countdown length and the wait cap as Config;
  what happens to a member who arrives late, to a solo player, to a refused start; that nobody is ever placed into a level
  after a run ends (an L1 rule).
- **How Ben tests it in Studio**, key-only (his Studio is in Spanish, he opens `tycoon\build\*.rbxl` by habit and does not
  use panels or checklists): the hub map and Depart in `build\test.rbxl` through the Studio bridge, the arrival and
  auto-start in the combat place, and a lever that fakes an arriving ticket in `proving.rbxl` so the countdown and the
  end screen can be judged without the bridge. Say what needs "Enable Studio Access to API Services".
- **A definition of done** with every gate command: the W2 contract's §11 list (`docs/prompts/l4-w2-contract.md`), the
  sharded `py tools/crowd_harness/mutate_shards.py` for the full mutation run, `check_compile.py`, and any new check.
- **Risks**, including what only the live pair can prove (study §5) and what Ben must judge (the card's motion, the
  countdown's length).

Keep it under about 300 lines, every claim with file:line. End your reply with a ten-line summary and the path.

## Part B — the era-cash study (economy-designer)

Write `docs/prompts/l4-w3-cash-study.md` (only that file; no Config change). Use `tools/sim_economy.py` (the greedy lap)
and `tools/sim_combat.py` for today's Forest Road pay (Normal T1, Hard, Brutal, solo, the 2/2 start preset) and the city's
income through every era. Combat cash is already multiplied by Legacy and Founder's (`Combat.luau:223`,
`WaveService.luau` credit sites): say how the ratio behaves after a Rebirth.

Income spans orders of magnitude inside one era, so a fixed multiplier per era can match "a few minutes of income" at one
point of the era only. Produce, for each era (Village, Boomtown, Metropolis, Orbital Colony):
1. Three anchors, each giving one multiplier per era: (a) the era's first minutes after Advance (or the save's start for
   Village); (b) the middle of the era on the greedy lap; (c) a third you judge better (e.g. the geometric mean of the era's
   income, or "the clear never beats N% of what the next purchase costs").
2. For each anchor with M = 3 minutes (and a row for M = 2 and 5): what a Normal clear is worth, in minutes of city income,
   at 0 / 25 / 50 / 75 / 100% of the era; what share of the era's next Advance cost it pays; and Hard and Brutal pay.
3. The constraints: Village's multiplier is never below 1 (a brand-new save keeps today's pay); a run must never become the
   fastest way through the city (compare a clear's cash per minute against the city's income per minute at every
   checkpoint, and against the time it saves on the lap); the end screen's numbers stay readable (`Format` handles the
   size). Name every `sim_combat.py` assertion that changes (assertion 4, C0's "garnish" rule, is one) and the new value.
4. A recommendation, and **one click-question preview** for Ben (an ASCII table of at most ~12 lines per option, three
   options) that shows what each anchor feels like at the start and the end of an era.

Keep it under about 200 lines; every number names the command or script that produced it. End your reply with a
ten-line summary and the path.
