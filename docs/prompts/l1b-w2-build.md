# Brief: build L1b Wave 2 "the long road" (one file for the four owners)

You are a fresh agent on Era City Tycoon (Roblox, Luau, Rojo), one of four owners building in
parallel in the worktree `C:\Users\benja\Desktop\tycoon-p5`, branch `l1b-wave2`. Every Bash call
starts with `cd /c/Users/benja/Desktop/tycoon-p5 &&`. Python is `py`; tools PATH line:
`export PATH="$HOME/.rokit/bin:$PATH"`; the Luau CLI is `C:\Users\benja\Desktop\tycoon\tools\bin\luau.exe`
(the worktree has none). Luau definitions for luau-lsp: `tools/types/globalTypes.d.luau`.

## Read

1. `docs/prompts/l1b-w2-reports/lead-routing.md` (Ben's and the lead's rulings).
2. `docs/INTERFACES.md` section `## Wave 2 — the long road (2026-10-14)` (grep for it, line
   ~12806, to the end of the file), above all: Rulings, the subsection for your role, Types,
   Config, Ownership with **Who goes first**, Gates, Definition of done, and **Lead's answers to
   the draft points**, which win over the body. Read Wave 1's contract above it only where Wave 2
   points to it. INTERFACES is ~14,100 lines: read ranges, never the whole file.
3. `CLAUDE.md` "Code rules".

## Rules

- **You edit only the files the Ownership table gives your role.** Anything you need in another
  owner's file goes in your report under "For the other owner" (exact text), and the lead routes
  it. The other three owners are working at the same time in the same folder: their files may
  change under you; never revert or reformat them.
- **Order:** luau-engineer A lands `Types.luau` first, then the `HitShapes`, `SwingGate` and
  `CampBrain` exports. The economy-designer lands the `Combat.json` / `Expeditions.json` keys first.
  Others build against the signatures the contract fixes and check the real files (`git status`,
  `git diff`) before running anything that needs them.
- No git writes. Kill only your own PIDs, never by image name. Scratch in your own folder
  `C:\Users\benja\AppData\Local\Temp\claude\l1b-w2-<role>\`.
- New logic goes in pure modules with a harness case and a mutation; big modules get new code in
  new modules beside them. `py tools/check_compile.py` is in your verify.
- **Write your report as you go** to `docs/prompts/l1b-w2-reports/build-<role>.md` (role = `A`,
  `B`, `ui`, `econ`): what is done, what is left, "For the other owner", every decision you took
  that the contract did not. A cut-off then loses nothing, and a fresh agent can continue from it.
- Verify with the gates the contract lists for your files (stylua, selene, luau-lsp analyze with
  the sourcemaps, check_compile, and your tools). Harness, then mutate, never in parallel.

End your turn with a short summary: done / not done, the gates you ran and their results, and
your "For the other owner" list.
