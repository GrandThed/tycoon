# L1b Wave 4 — "no waits, no walls" (session prompt)

The last build wave of L1. Ben's decisions are in `docs/MISSIONS_DESIGN.md` §19 (2026-10-15), and
they win over every older ruling they touch (notably L1b-7 "damage only from a player in play", and
the chase that stops at the camp's edge).

## What Ben will see when it is done

- He hits a raider from the road with the bow: the hit lands (no "BLOCKED"), its group wakes and
  comes out of the camp after him.
- He walks into a camp, wakes it, walks out: they follow him onto the road.
- He runs until they lose him: after a few seconds out of sight they walk home and heal.
- A camp cleared at a normal pace sends no tent raiders; clearing it fast brings them. He never waits
  for a tent: the camp is cleared when its raiders are dead.
- The Chief's Clearing still locks and works as before.

## How to run it (the process that worked in L1b Waves 1–2)

1. **Study first** (one Opus agent, read-only, report to `docs/prompts/l1b-w4-study-report.md`), then
   the lead's rulings, then a contract in `docs/INTERFACES.md` "Wave 4 — no waits, no walls" drafted by an
   Opus agent and checked by the lead, then the owners in parallel, a slice review, fresh fix agents
   from a fix-list file, one fix-diff reviewer, QA, docs, merge (the L1b merge rule holds), place files
   rebuilt. Work in the worktree `C:\Users\benja\Desktop\tycoon-p5` on a new branch `l1b-wave4` from
   `main`. Every brief and ruling goes in a file; fresh agents per round (see the agent-context-cost
   memory).
2. **Ask Ben with pictures** (ASCII previews in the question tool) for any choice the study finds that
   §19 does not settle. A mock of how a chase BEHAVES on the road (a top-down sketch with distances)
   is worth showing before the build, because he judges camp behaviour within minutes of play.

## What the study must answer

1. **Floors.** Crowd bodies stand on one flat floor per camp and ignore geometry. A chase leaves the
   camp floor for the road, which has heights (the gap, the bridge, the climb by the lookout). Options
   to weigh: reshape the road near each camp to the camp's height (Ben allowed it); a per-body floor
   taken from the road's height under it (LevelGeometry knows the road); a mix. Cost to `CrowdService`,
   `CrowdBrain`, `CrowdCodec` (heights and the wire's range off the camp), `CrowdRenderer`, the
   mirrors and `check_levels.py`.
2. **Fences.** Bodies walk through geometry, so a chase out of a fenced camp walks through the
   palisade. Options: wide openings, exits steered through gates, or fewer fences in grey (natural
   barriers come in L4). What reads best at the least cost.
3. **The chase rule.** "Lose the player" with distance-only sight (raiders see through walls and bends):
   chase sight, the out-of-sight timer, the home walk, evade and heal (existing), groups joining in
   (`joinFactor`), patrols. The `in play` concept (`CampBrain.InPlay`, `chaseMargin`, the BLOCKED
   result, phone auto-fire's "never a camp you are not in play for", the `engaged` hold, Abandon's hide)
   — what goes, what stays, what replaces it.
4. **Exploits once BLOCKED goes.** Sniping from where melee raiders cannot reach (blocks, the lookout
   step, high ground), kiting between two camps, pulling one group at a time, dragging a camp into the
   next one. Recommend a rule for each.
5. **The tent as a pace reserve.** How to measure "clearing too fast" (the P5 director's tempo over a
   window is the model: `director.windowSeconds` 10 is load-bearing); the target pace per camp; what
   the tent sends and how fast once the pace is exceeded; the camp's clear (residents dead, the
   stock forfeit); the clear bonus (0.1 of the camp's stock: of what is killed, or as today); Hard and
   Brutal; the bands this moves (first clear 7–8 min on Normal).
6. **Camp state off the camp.** A camp's clear, dormancy (`dormantRadius` 120), the per-camp alive
   count, `fieldClear` on the road, the population cap with bodies from two camps out at once, the
   snapshot budget, the Chief's Clearing (locked: its residents never leave).
7. **The simulators.** `sim_range.py` (its `mission` player and the 1-stud in-play step from Wave 3
   become moot), `check_stage_mirror.py`, the harness, `check_levels.py` gates that assume a camp's
   edge.
8. **Ben's look.** How Play gets him to the Chief's Clearing and to Main Camp's sneak without the
   panel (he does not use it): a key, or a `provingStart` choice.

Give owners and disjoint file sets per the L1b pattern (luau-engineer A the crowd, B the run,
ui-engineer the client, economy-designer the data and simulators) and a wave plan; say the review cost.

## Environment

Bash: `export PATH="$HOME/.rokit/bin:$PATH"`; Python is `py`. The worktree has no `tools/bin/luau.exe`:
use `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`. `mutate.py` takes about two hours: run it in
the background. Kill only your own processes, never by image name.
