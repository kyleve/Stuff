# LifecycleKit – Module Shape

LifecycleKit owns typed startup/teardown execution. Rendering belongs in [LifecycleKitUI](../LifecycleKitUI/AGENTS.md).
See [README.md](README.md) and the [root contract](../../AGENTS.md).

## Scope & dependencies

Use Foundation and Observation only. App-specific steps belong to consumers.
Steps, gates, and the engine stay on `@MainActor`; heavy work may hop to an actor inside a step.

## Invariants

- Type erasure belongs only in `LaunchPlan` combinators and the package-visible `LaunchPlanNode`. Do not expose `Any` APIs or add another erasure site.
- Plans share one `ID: Hashable & Sendable` domain. Preserve typed `nodeIDs`; internal nodes, memo, failures, and gate handles use erased IDs.
- Only pass-through steps may skip. Value-producing `init`/`then` keep `modes == .all`.
- A root gate has `Input == Output == Value` and `modes: .all`, deliberately parking headless launch. Its choice travels through dependencies, not the trunk. Guard: `LaunchPlanTests.planCanRootAtAGate`.
- Node failure is terminal. Recovery relaunches the app; failed teardown parks without relaunch. Necessary retries belong inside the owning step, not the runner.
- Serialize drives through cancel-and-drain. Teardown/foreground promotion can interrupt a parked gate. Superseded drives cannot publish phase; their gate handles no-op. Cancellation is distinct from node failure.
- Memoize completed outputs for promotion, but not skipped gates. Clear memo for initial run, teardown, and post-teardown relaunch. Teardown may reuse launch IDs.
- Detached children never block ready or fail the drive; failures surface through `detachedFailures`.
- Use `.undetermined` until a scene is active. UIScene reports background at launch even for a user tap; do not fabricate a cause. Run only background-safe work and build no view tree until promotion.
- Foreground promotion is idempotent and occurs only for a genuinely active scene.

## Testing

`LifecycleKitTests` runs in `StuffTestHost` with `FixtureStep`/`FixtureGate`.
`LifecycleRunnerFuzzTests` uses a seeded independent model; preserve replayability and test-controlled suspension.
