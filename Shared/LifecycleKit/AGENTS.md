# LifecycleKit – Module Shape

LifecycleKit is an app-agnostic engine that models app startup (and its reverse, teardown) as a **typed plan**. Steps are types with concrete `Input`/`Output`. A `LaunchPlan` composes them into a sequential trunk plus concurrent detached fan-outs with data flow checked at compile time. A `@MainActor @Observable` `LifecycleRunner<Launch>` walks the plan and publishes one value-carrying `phase`. Rendering lives in [LifecycleKitUI](../LifecycleKitUI/AGENTS.md). See [`README.md`](README.md) for the full narrative and API.

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns build system, formatting, and global conventions.

## Scope & dependencies

- **Use Foundation and Observation only.** Do not import SwiftUI, UIKit, WhereCore, or any app code. Views belong in LifecycleKitUI. App-specific launch logic lives in the consumer (for example `WhereUI/Sources/Launch/`).
- **Keep steps, gates, and the engine on `@MainActor`.** Heavy work hops to an actor inside a step's `run`. Never loosen isolation on the step.

## Invariants

- **Keep type erasure in exactly one home.** `LaunchPlan`'s combinators erase steps into `LaunchPlanNode` (package-visible for the runner and the UI proxy seam). Their generic constraints guarantee every internal cast. Never add a second erasure site or a public API that traffics in `Any`.
- **Use one identity domain per plan.** `LaunchPlan` is generic over `ID: Hashable & Sendable`. Every combinator requires matching `ID`s. A plan cannot mix domains. `nodeIDs` gives back `[ID]`, not erased keys. IDs erase to `AnyHashable` inside `LaunchPlanNode` and deliberately stay erased from there on (the runner's memo, `LifecycleFailure.stepID`, `LifecycleGateHandle.id`). Pushing `ID` past the plan would force it onto the runner, the container, and every splash/failure/gate closure. Untyped `failed(at:)` assertions are the priced-in cost, not an oversight.
- **Allow skip only in pass-through positions.** Value-producing (`init`/`then`) steps must keep `modes == .all` (plan-construction `precondition`). A skipped producer would leave a hole in the data flow. Do not add a skip path for them.
- **A plan may root at a gate** for an app that must build nothing until the user chooses (Where's onboarding/demo choice). `Input` and `Output` are then the gate's `Value`. That is safe for the same reason `.gate` is: a gate transforms nothing. Such a gate declares `modes: .all`. Parking a headless launch is the point rather than the deadlock the default avoids. The choice reaches the next step through its dependencies, not the trunk. Guard: `LaunchPlanTests.planCanRootAtAGate`.
- **Treat failure as terminal.** A thrown node parks `.failed` with no retry. Recovery is relaunching the app. A failed teardown likewise parks and does not relaunch (a thrown erase leaves state intact). Do not reintroduce a resume/retry path. If a node is genuinely flaky, retry inside it at the layer that understands the failure.
- **Funnel all drives through a single in-flight task** (cancel-and-drain). Two drives never overlap. `teardown()`/`enterForeground()` can interrupt a launch parked on a gate. A cancelled drive is distinct from a thrown node (`.failed`). A superseded drive never writes the phase the new drive owns. A superseded drive's gate handle resolves to a no-op. Do not add a drive path that bypasses that serialization.
- **Memoize completed nodes for promotion.** Completed nodes' outputs are memoized so an `enterForeground()` promotion's re-walk skips completed work. Skipped gates are deliberately not memoized so they re-evaluate on promotion. Fresh attempts (first `run()`, the start of a teardown, the post-teardown relaunch) clear the memo. Teardown plans may freely reuse launch node IDs (no live shared memo, since there is no retry re-walk).
- **Keep detached children off the critical path by construction.** They never block `.ready`. They never fail the drive. They surface failures only on `detachedFailures`.
- **Use `.undetermined` as the honest UIScene launch reason.** Under UIScene, `UIApplication.applicationState` reads `.background` at `didFinishLaunching` even for a user tap. Launch `.undetermined` rather than fabricate a `.background(cause)`. It gates to the background-safe nodes and builds no view tree until promoted. If no scene ever connects, it honestly stays `.undetermined`.
- **Keep promotion idempotent.** `enterForeground()` promotes `.background` and `.undetermined` and no-ops on `.userForeground`. Call it only once the scene is genuinely `.active` (see `RootView` in WhereUI for the `scenePhase` gating pattern).

## Testing

Swift Testing lives in [`Tests/`](Tests), hosted in `StuffTestHost`. Engine tests build a `LaunchPlan` from the shared `FixtureStep`/`FixtureGate` fixtures and assert on `phase`. Seeded fuzz tests (`LifecycleRunnerFuzzTests`) replay failures exactly against an independent model. Keep tests deterministic. Park async steps on test-controlled streams/handles, not timing.
