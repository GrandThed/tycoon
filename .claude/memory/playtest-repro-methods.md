Playtest repro methods written by docs-keeper must be checked against library behaviour before
they ship (M5, 2026-09-09): it prescribed burning DataStore budget to force a load failure, but
ProfileStore retries throttled calls internally and never surfaces them, so the "failed" card
would never have appeared. Fix was a Studio-only live lever (Workspace boolean attribute
`ForceLoadFailure`, read by `DataService.attemptLoad`).

**How to apply:** any PLAYTEST step that claims to trigger a failure path needs the lead to
confirm the path is actually reachable from Studio; prefer a `RunService:IsStudio()`-gated
attribute or `Game.json` debug key over tricks against the platform.
