C1 "Studio bridge + Village expedition", decided by Ben 2026-09-22 ("invent debug tools to
simulate scenarios"): he cannot reach the published pair (audience-reach block), so every
Roblox-platform path must be exercisable from Studio. Contract: `docs/INTERFACES.md` "C1 contracts".

- **The bridge replaces only `TeleportAsync`.** In Studio, Depart/Join/Return write a handoff
  record to DataStore `StudioHandoff` (key `p_<userId>`, consumed once, stale after
  `handoffMaxAgeSeconds`), release the profile and **kick** the player after 1 s — the kick is the
  Studio stand-in for leaving the server. Everything else (payload validation, MemoryStore
  registry, `TeleportInitFailed` recovery) runs for real; `ForceTeleportFailure` / `ForceRegistryFailure`
  Workspace attributes drive the failure paths through the SAME code the live handlers use.
  Needs "Enable Studio Access to API Services"; on the ProfileStore mock the bridge warns once and
  Depart answers `unavailable` with nothing released.
- **Every lever has two entry points**: a Workspace attribute (consumed on the 1 Hz tick, or a
  sticky state for `DebugGodMode`/`DebugBots`) and a `RequestDebug(lever, value)` intent driven by
  Studio-only debug strips in both places. Both are inert outside `RunService:IsStudio()`. Bots
  (`DebugBots`) are server rigs with negative ids that count toward party scaling and whose reward
  share is discarded, so co-op maths can be seen from one client.
- **Enemies and weapons are placeholders by design** (R15 `CreateHumanoidModelFromDescription`
  rigs recoloured per key, empty hands). A props pass for Village combat is a separate later wave.
- **Director facts learned in the sim:** `director.windowSeconds` is load-bearing — at 15 s the
  tempo could not discriminate a fast party from a slow one (kill count in the window was
  identical, zero merges at any power); 10 s works. `tempoMin` must stay < 1 and `mergeTempo` > 1
  or breathers become constant and every wave merges. The server checks the merge every tick
  after spawning ends (continuous), and `sim_combat.py` mirrors that (`MERGE_CHECK_CONTINUOUS`).
  Cash is floored twice (SplitPool, then × CombatCashMult) — the sim mirrors the double floor.
- **Review lessons:** nothing in a Heartbeat run loop may yield (a MemoryStore publish with retry
  backoff inside `WaveService.tick` re-entered the wave-clear branch every frame); registry
  writes go through a one-slot mailbox on their own thread. `aggroRange` smaller than the arena
  left enemies idle forever — untargeted enemies need a fallback walk. Enemies need a reaper
  (`Humanoid.Died`, `AncestryChanged`, Y < floor) or an out-of-band destroy hangs the wave.
  Two full-screen cards on one join (welcome-back offer + run summary) must be chained.

**Why:** a fresh session would otherwise propose testing on the published pair, treat the
Studio kick as a bug, re-tune `windowSeconds` back to 15, or put a yielding call in the run loop.

**How to apply:** before C2/C3 read the C1 contract; new levers get a `Combat.json debug` key +
both entry points; keep `RequestDebug` handlers gated on IsStudio in every place. See
[[combat-2026-09-17]] and [[playtest-repro-methods]].
