# Era City Tycoon

A mobile-first Roblox plot tycoon: claim a plot, grow a medieval village into a boomtown, a
metropolis, and finally an orbital colony. Completing an era resets your plot but grants
permanent **Legacy** — era progression is the prestige loop. Progress persists across sessions
(ProfileStore), including offline earnings on rejoin. Built with Luau and Rojo. Full design in
[`docs/SPEC.md`](docs/SPEC.md).

## Quickstart

```powershell
# 1. Restore the pinned toolchain (rojo, wally, stylua, selene, luau-lsp)
rokit install

# 2. Install Luau dependencies into Packages/ and ServerPackages/
wally install

# 3a. One-shot build
rojo build -o build/test.rbxl

# 3b. OR live-sync while Studio is open (Rojo plugin → Connect)
rojo serve
```

Then follow [`docs/PLAYTEST.md`](docs/PLAYTEST.md) for what to check in Studio, and
[`docs/MANUAL_STEPS.md`](docs/MANUAL_STEPS.md) for anything that has to happen in Studio or the
Creator Hub (plugin install, mesh import, audio upload, game passes/products).

## Repo layout

```
default.project.json     -- Rojo project: maps src/ into the Roblox DataModel
wally.toml                -- Luau package dependencies
rokit.toml                 -- pinned CLI toolchain versions
src/
  server/                 -- ServerScriptService/Server: services, server authority
  shared/                 -- ReplicatedStorage/Shared: Config/*.json, Types, pure Economy
  client/                 -- StarterPlayerScripts/Client: UI and controllers
tools/                    -- sim_economy.py (M2), gen_asset_manifest.py (from M3 onward)
docs/                     -- design, plan, and playtest docs (see below)
build/                    -- rojo build output, not synced to Studio manually
```

## Docs

| Doc | What it's for |
|-----|----------------|
| [`docs/SPEC.md`](docs/SPEC.md) | Full design and architecture — source of truth |
| [`docs/PLAN.md`](docs/PLAN.md) | Milestone breakdown, status, ownership |
| [`docs/INTERFACES.md`](docs/INTERFACES.md) | Frozen contracts for the current milestone |
| [`docs/PLAYTEST.md`](docs/PLAYTEST.md) | Step-by-step Studio checklist per milestone |
| [`docs/MANUAL_STEPS.md`](docs/MANUAL_STEPS.md) | Everything requiring Studio or Creator Hub |
| [`docs/BALANCE.md`](docs/BALANCE.md) | Economy sim output and tuning notes (from M2 onward) |

## Toolchain

Pinned in `rokit.toml`; run `rokit install` from the repo root to match these exactly.

| Tool | Version | Purpose |
|------|---------|---------|
| rojo | 7.7.0 | Filesystem ↔ Studio sync |
| wally | 0.3.2 | Luau package manager |
| stylua | 2.5.2 | Formatter |
| selene | 0.31.0 | Linter |
| luau-lsp | 1.69.0 | Typechecking / editor support |
| python | 3.x | `tools/sim_economy.py`, `tools/gen_asset_manifest.py` |

## Credits

3D models and audio are from [Kenney](https://kenney.nl) asset packs (CC0 — no attribution
legally required, credited here anyway). See `docs/SPEC.md` §8 for the asset pipeline and
`docs/ASSET_MANIFEST.md` (generated from M3 onward) for exactly which models are used.
