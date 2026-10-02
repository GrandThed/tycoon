Found 2026-10-02 at Ben's first P3 Studio run: `InputController` and `AbilityFx` passed stylua,
selene, luau-lsp and `rojo build`, but did not load in Studio ("Out of local registers ...
exceeded limit 200"). The whole combat client then never started.

- Luau allows **200 locals per function**, and a module's top level is one function.
- Studio compiles with debug level 2, where every local keeps a register. A release build folds
  constants away, so plain `luau-compile` passes the same file; only `-O1 -g2` reproduces it.
- None of our other checks compile code.

**Gate:** `py tools/check_compile.py` compiles every `src/**/*.luau` with `-O1 -g2` and fails any
file with more than about 180 top-level locals. It downloads the pinned `luau-compile` into
`tools/bin/` (gitignored) on first run. Rokit cannot install it: any alias of `luau-lang/luau`
resolves to the interpreter.

**Why:** a fresh session would trust a green typecheck and hand Ben a build that cannot start.

**How to apply:** run the gate in every QA pass and put it in every engineer's verify list.
Tell engineers who write big modules to group constants and state into tables or split the
module. See [[qa-runner-silent-finish]] and [[feel-pass-2026-09-23]].
