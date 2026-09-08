---
name: qa-runner-silent-finish
description: The qa-runner subagent (Haiku-pinned) often stops without emitting its final report — resume it with SendMessage to get results
metadata: 
  node_type: memory
  type: project
  originSessionId: 8e139378-8a44-4049-808f-fadb7bcc4577
  modified: 2026-09-03T13:34:54.495Z
---

The `qa-runner` agent in this repo (pinned to Haiku via README/agent config) has twice (M1 and
M2, 2026-09-03) completed its tool work but ended its turn with only its opening line as the
result — no final report.

**Why:** the model ends its turn after the last tool call without writing the summary message.

**How to apply:** after a qa-runner task completes, if the result text is just a preamble (no
"ALL GREEN"/failure list), SendMessage the same agent asking it to finish and report — it
resumes with full context and delivers the real report. Never treat the missing report as a
pass, and never re-run the suite from scratch. Also: point qa-runner (and luau-lsp analyze in
general) at the repo's committed definitions file `tools/types/globalTypes.d.luau` — left to
itself the agent downloads a 404 page and poisons the luau-lsp step (happened at M1; the valid
837 KB file was committed to the repo at the end of the M2 session).
