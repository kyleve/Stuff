# LifecycleKit todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P2s (Nice to have)
- test [quick-win]: Add a test that duplicate node IDs trap. `LaunchPlan.append` `precondition`s on a duplicate (`LaunchPlan.swift:134-140`), and `LifecycleContainer` — now in LifecycleKitUI — does the same for duplicate gate-view registrations via `assertUniqueGateTypes` (`LifecycleKitUI/Sources/LifecycleContainer.swift:98-104`), but nothing exercises either. This item covers both modules, which is why LifecycleKitUI has no file of its own. (audit 2026-07-26)

# Completed issues

## P0s (Must do)
- fix [needs-design]: A cancel during the **final** step's `minVisible` hold is never observed, so a superseded drive still sets `phase = .ready`. (audit 2026-07-26) — gone with the typed-engine rewrite: the engine holds nothing at all (the splash minimum moved to `LifecycleContainer.minimumSplashDuration`, a view-level concern), and `drive` now publishes the terminal phase behind `guard case let .completed(value) = outcome, !Task.isCancelled` (`LifecycleRunner.swift:231`) — so a superseded walk publishes nothing, with no hold sitting between the completion check and the phase write.
	- test [quick-win]: Supersede a drive *during* `minVisible`. — moot; there is no in-engine hold to interrupt. Supersession itself is covered by the drive/teardown/promotion suites and the seeded fuzz suite.

## P2s (Nice to have)
- test [quick-win]: Replace the fixed 50 ms negative-assertion window (`LifecycleRunnerTests.swift:174`) with bounded polling. (audit 2026-07-26) — done in the test rewrite; the suites poll predicates (`waitUntil` / `waitFor`), and the only remaining fixed delay is a 1 ms yield tick in `LifecycleKitTestSupport`.
- fix [quick-win]: The `LifecycleContainer` `#Preview` hardcodes a literal that auto-extracts as the value-less `App content` entry. (agent) — resolved: the container moved to LifecycleKitUI and its preview uses `Text(verbatim:)`, which isn't extracted, so no catalog carries the entry.
