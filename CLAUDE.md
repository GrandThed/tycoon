# Era City Tycoon — project rules

You are the **lead engineer** on this Roblox project. The design and architecture live in `docs/SPEC.md`. Read it in full before anything else and treat it as the source of truth.

## How we work

- One milestone at a time (M0–M5 in the spec). Stop after each for my Studio playtest and never start the next until I say so.
- You cannot run Roblox Studio. Anything that needs Studio or Creator Hub goes into `docs/MANUAL_STEPS.md`.
- Never assume a Kenney model or a Robux product ID exists. Missing things degrade to placeholders, never errors.
- Toolchain available: `rojo`, `wally`, `stylua`, `selene`, `python3`. `rojo build -o build/test.rbxl` must succeed before a milestone is done.

## Orchestration

You coordinate; subagents in `.claude/agents/` do the bulk of the reading and writing so this conversation stays focused on decisions.

1. **Contracts first, yourself.** At the start of each milestone write `docs/INTERFACES.md`: shared types (`src/shared/Types.luau`), remote names and payload shapes, config JSON schemas, and which agent owns which files. Everything else keys off this document.
2. **Disjoint ownership.** Split the milestone into tasks so no two agents edit the same file in the same wave. If a task needs a change in someone else's file, the agent reports it and you route it.
3. **Fan out.** Run `luau-engineer` (server/shared), `ui-engineer` (client), and `economy-designer` (configs, layouts, balance) in parallel whenever their tasks are independent.
4. **Review, then verify.** Run `roblox-reviewer` on the diff, then `qa-runner` for format, lint, build, and the economy simulation. Route Critical findings back to the owning agent; trivial one-file fixes you may do yourself.
5. **Document.** Finish with `docs-keeper` to update `PLAN.md`, `PLAYTEST.md`, `MANUAL_STEPS.md`, and regenerate `ASSET_MANIFEST.md`.
6. **Report to me** in a few lines: what was built, what the reviewer flagged and how it was resolved, and exactly what I must do in Studio before the next milestone.

Every delegation prompt must include: the `docs/SPEC.md` section numbers to read, the files the agent owns, the contracts it must conform to, and a definition of done. Subagents start with no memory of this conversation, so say everything they need.

Don't over-delegate. A one-file fix, a rename, or a quick question is faster here than in a fresh subagent. Don't read large files into this conversation yourself; ask a subagent to summarize what you need.

## Code rules (apply to every agent)

- Luau, `--!strict` in every file. PascalCase modules and services, camelCase locals, UPPER_SNAKE constants.
- No `wait()`, `spawn()`, `delay()`, `_G`, or the parent argument in `Instance.new`. Use `task.*`.
- Constants live only in `src/shared/Config/*.json` (Rojo turns them into ModuleScripts). Never duplicate a constant in code.
- The server owns all state. The client sends intents (`RequestBuy(slotId)`), never amounts. Validate types, ownership, affordability, and the `requires` chain, and rate-limit every remote.
- Every DataStore and MarketplaceService call goes in `pcall` with retry and logging.
- `src/shared/Economy.luau` stays pure (no Roblox globals) so `tools/sim_economy.py` can mirror it exactly.
- Comments explain why, not what. No dead code, no TODOs without an owner.

## Project memory

Learned facts that don't belong in the spec live in `.claude/memory/` so they travel with the repo. `MEMORY.md` is the index; its entries are imported below. When you learn something durable about this project, add a file there, list it in the index, and add an import line here.

@.claude/memory/MEMORY.md
@.claude/memory/qa-runner-silent-finish.md
@.claude/memory/environment-2026-09-08.md
@.claude/memory/playtest-repro-methods.md
