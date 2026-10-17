# L2 Wave 1 contract (brief for the drafting agent)

Write `docs/prompts/l2-w1-contract.md` (under about 300 lines) in the worktree `C:\Users\benja\Desktop\tycoon-p5`,
branch `l2-secrets`. **Write no code.** Kill only your own PIDs.

Read: `CLAUDE.md`; `docs/MISSIONS_DESIGN.md` §7, §8, §12.1, §21, **§22 (the decisions; they override the study
wherever they differ)**; the study `docs/prompts/l2-study-report.md` (all of it, with its file:line evidence;
verify any line you rely on); `docs/prompts/l1c-contract.md` §6 for the contract shape the lead expects; INTERFACES
"# L1c contracts" and the L1/L1b sections only where they touch what W1 changes.

## Wave 1 scope: the bought double jump and the lookout

1. **Saving, v7 (add-only):** `combat.abilities`, `combat.secrets`, `combat.families`, `combat.shortcuts`
   (shapes, defaults, migration from v6, where the server reads/writes them, how Studio's mock store behaves).
   Stars stay in session memory.
2. **Double jump becomes owned:** server-authoritative ownership (a character attribute or similar the client
   reads), the client refusing the air jump without it, per-player jump rise (18 / 30) feeding the L1c
   ground-aim height rule on both sides, every check/simulator that assumes double jump (L1c `WallClip.Rise`,
   check_levels climb/perch rules, "main path passable with one jump and the dash", sim_range's player) — say
   which assumption becomes "per player" and which stays "worst case = owner".
3. **Buying:** `abilities` config (id, name, price 10 Valor, order), `RequestBuyAbility(id)` validated
   (type, known id, not owned, affordable, rate-limited, lobby only?), the Abilities panel in the lobby (a key
   and a phone button), feedback on success/refusal.
4. **Secrets as chests:** a pure `SecretFlow` (trigger = flat distance + height band, checked in the run loop
   like `progress`; key check per player at the reward; once per player, saved), the lookout chest's reward
   (some Valor/Timber AND ownership of the Flamethrower family recorded in `combat.families`; the family itself
   is built in W2, so W1 shows a "found" card and nothing equips yet), the chest's look and cue, the map card's
   secrets row (found / not found, the key icon). The cache and the shrine keep their sites but pay nothing in
   W1 (they get their keys in W2 and W3); make sure no secret pays without its key.
5. **The lookout must need the double jump:** check reachability with one jump + dash + every ability (the
   study says Greataxe Leap Smash reaches it); fix by data (ledge height) or by the per-player rise, and give
   check_levels a rule for "a secret is out of reach without its key, within reach with it".
6. **Studio levers:** grant/remove an ability, reset secrets, grant Valor (if none exists), in both entry
   points per the Studio bridge convention.
7. **Balance:** a one-jump player policy in sim_range (the first run has no double jump), the Normal clear must
   still be clearable with one jump by the human-reaction player, chest contents sized against a clear.
8. **Owners**, disjoint files, each with a definition of done: luau-engineer (server/shared, harness,
   check_stage_mirror if touched), ui-engineer (client: movement refusal, panel, chest cue, map row, rise
   mirror), economy-designer (configs, layout, check_levels, sim_range, BALANCE). The lead owns INTERFACES and
   the combat `Main.server.luau` wiring for new remotes — list exactly what to wire.
9. **Risks** and anything that truly needs Ben (keep it short; the four decisions are taken).

End your reply with a ten-line summary and the path.
