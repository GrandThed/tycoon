---
name: agent-context-cost-2026-10-13
description: Resuming long-lived subagents burned the session limit (one near 1M tokens of context); for a bounded task start a fresh agent from a brief in a file
metadata:
  type: feedback
---

Do not keep resuming the same subagents across milestones. On 2026-10-13 the lead had resumed four
engineers by `SendMessage` from P5 Wave 1 through the L1 build and into its fix round; each resume
replays the agent's whole transcript. They had grown to several hundred thousand tokens each (the
economy-designer near 1M), and all four died at once on the session limit ("You've hit your session
limit", HTTP 429) minutes into the fix round. Ben: "you hit the usage limit", "you may need to compress
one of the sessions", "i mean compact", "there is one with almost 1M tokens of context".

**Why:** the earlier notes say "resume the same agent, it keeps what it measured". That is true and
it is expensive: the saving of a re-read is far smaller than the cost of carrying a huge context
through every tool call. A subagent's session cannot be compacted from the lead.

**How to apply:**
- Resume an agent only for a short follow-up on what it has just done (a relay, a ruling, one fix).
- At a milestone boundary, a review-fix round, or once an agent has done more than one long task,
  start a FRESH agent. Put the task in a file in the repo first (the contract, a fix list such as
  `docs/prompts/l1-fix-round.md`) and keep the prompt short: read these sections, you own these
  files, check `git status` and `git diff` because the work may be partly done.
- Write findings and rulings to a file as soon as they are final, not only into messages: a cut-off
  then loses nothing, and the lead's own context stays smaller.
- Four Opus reviewers on one diff cost about 1.9M tokens; they found nine Majors on L1, so the slice
  review is worth it at a milestone, but it is a large share of a session's budget. Say the cost to
  Ben when planning a review.
- When agents die on the limit, check the time against the reset, then `git status` in the worktree,
  commit what is there as work in progress, and continue with fresh agents.

See [[qa-runner-silent-finish]], [[missions-replan-2026-10-13]], [[p5-missions-2026-10-12]].
