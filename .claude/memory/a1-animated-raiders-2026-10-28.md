A1 "animated raiders" started 2026-10-28 on Ben's "okey, lets do it all" (after the crowd bench proved 160 skinned
raiders at 60 fps and a Rojo-built skinned rig animates). Scope: the raiders in the Expeditions place switch from rigid
pieces posed by `RaiderPose` to the Tripo models with Quaternius clips (`assets/anim/<kind>/`), plus their gear, the
4096 -> 1024 texture shrink and the asset run; whether the eight Tripo player weapons ride along is a study question.

Work is on branch `a1-animated-raiders` in the worktree `C:\Users\benja\Desktop\tycoon-a1` (from `main` ed0cfa0;
`assets\` junction to the main checkout, `.env` copied). Same order as L2-L5: a study by two Opus agents from
`docs/prompts/a1-study.md` (Part A the game side -> `a1-study-report-runtime.md`, Part B the assets and pipeline ->
`a1-study-report-assets.md`), then Ben's decisions as click questions with sketches, then contracts from files,
fresh agents per round. L5 (`l5-friends`) and M11 (`m11-port`) do not touch the raider files, so A1 runs beside them;
it merges to `main` only after its review, QA and Ben's look.

**Why:** a fresh session would otherwise restart the bench or wire clips into `src/` without a contract.

**How to apply:** check the branch's `docs/prompts/a1-*` files for what is done before delegating. See
[[art-direction-2026-10-26]], [[l4-real-forest-2026-10-21]], [[agent-context-cost-2026-10-13]].
