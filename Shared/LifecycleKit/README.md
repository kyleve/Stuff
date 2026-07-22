# LifecycleKit

A small, app-agnostic engine that runs **app startup — and its reverse,
reset/teardown — as an ordinary async function**, driven by a `@MainActor
@Observable` runner whose single published `phase` the UI layer renders.

The launch function is vanilla Swift: data flows through `let`s (a value
cannot be used before the step that produced it — the compiler holds the
ordering), conditionality is a plain `if`, and concurrency is explicit. A
`LifecycleContext` provides the three wrappers a bare function can't supply:
`step` (phase publication + run-once memoization + failure attribution),
`gate` (park for user interaction, e.g. onboarding), and `detached`
(fire-and-forget fan-out that never blocks readiness). A thrown step parks
the runner in a terminal failure phase (no retry — the recovery is
relaunching the app); logout/erase is a second function run over a typed
input, followed by a fresh relaunch.

LifecycleKit depends only on Foundation + Observation — **no SwiftUI, no app
code**. Everything rendered lives in [LifecycleKitUI](../LifecycleKitUI).

## Mental model

Launch is a function. Each `let` is the launch's *dependency scope so far* —
the proof of everything produced to that point — and it only grows, by each
step embedding what came before:

```swift
{ context in
    let services = try await context.step(.openStore) { … }      // Void → Services
    let session  = try await context.step(.startSession) { … }   // uses `services`
    if !hasOnboarded {
        try await context.gate(OnboardingGate(), value: session)  // parks for the user
    }
    try await context.step(.syncAuth) { … }                       // required, ordered
    context.detached(.reminders) { … }                            // fan-out, never blocks
    return session                                                // → .ready(session)
}
```

- **Value-producing steps can't be skipped** — by API shape: only the
  `Void`-returning `step` overload accepts `modes:`, and a plain `if` around
  a producing expression forces an `else` that also produces the value.
- **Gates** park the function awaiting external (user) resolution.
  Foreground-only by default and unmemoized when skipped, so a headless
  launch passes through and the promotion re-run parks.
- **Detached work** takes no value anyone can depend on (`Void` bodies),
  runs concurrently, never blocks `.ready`, and reports failures only on the
  runner's `detachedFailures` diagnostics — observable, never fatal.

**The one discipline the style demands:** a re-drive (an `enterForeground()`
promotion) *re-runs the whole function*, with the memo skipping completed
steps. Bare glue between steps therefore re-runs every time —
**all effects live inside `step`/`gate`/`detached`**; glue is value plumbing
and `if`s only.

## Installation

`LifecycleKit` is a local SPM library in this repo (`Shared/LifecycleKit`).
Add it to a target's dependencies in [`Package.swift`](../../Package.swift):

```swift
.target(name: "YourCore", dependencies: [.target(name: "LifecycleKit")])
```

## Core API

```swift
// The engine, generic over the launch function's return value.
@MainActor @Observable public final class LifecycleRunner<Launch: Sendable> {
    public enum Phase {
        case launching                          // splash
        case running(LifecycleStepContext)      // splash + caption/progress
        case awaitingGate(LifecycleGateHandle)  // the gate's registered view
        case failed(LifecycleFailure)           // terminal failure UI (no retry)
        case ready(Launch)                      // the app, handed the launch's output
    }
    public private(set) var phase: Phase
    public private(set) var detachedFailures: [LifecycleFailure] // off-phase diagnostics
    public init(reason: LifecycleReason,
                initializePrerequisites: @MainActor () -> Void = {},
                launch: @escaping @MainActor (LifecycleContext) async throws -> Launch)
    public func run() async                 // run the function; idempotent
    public func enterForeground() async     // promote a background/undetermined launch
    public func teardown<Input: Sendable>(
        input: Input,
        _ body: @escaping @MainActor (Input, LifecycleContext) async throws -> Void) async
}

// The wrappers the function drives its work through.
@MainActor public final class LifecycleContext {
    public let reason: LifecycleReason
    public var runningStep: LifecycleStepContext? { get }   // progress/message reporting
    // Required, value-producing. No modes: — a producer can't be skipped.
    public func step<Output: Sendable>(_ id: AnyHashable,
                                       _ body: () async throws -> Output) async throws -> Output
    // Required, Void-output; the only step overload that may gate.
    public func step(_ id: AnyHashable, modes: LifecycleModeSet = .all,
                     _ body: () async throws -> Void) async throws
    // Park for the user; `value` reaches the registered gate view.
    public func gate<G: LifecycleGate>(_ gate: G, value: G.Value) async throws
    // Fire-and-forget fan-out.
    public func detached(_ id: AnyHashable, modes: LifecycleModeSet = .all,
                         _ body: @escaping @Sendable @MainActor () async throws -> Void)
}

// A parking point's type: the UI registry keys a view on it and statically
// recovers Value. No behavior — conditionality is the caller's `if`.
@MainActor public protocol LifecycleGate {
    associatedtype Value: Sendable
    var id: AnyHashable { get }
    var modes: LifecycleModeSet { get }     // defaults to .foreground
}

// The engine-minted token for one parked gate — the only way to resume it.
@MainActor public final class LifecycleGateHandle {
    public let id: AnyHashable
    public func complete()
    public func fail(_ error: Error)
}
```

`LifecycleReason` (`.userForeground` / `.background(cause)` / `.undetermined`)
and `LifecycleModeSet` gate which work runs: `.undetermined` is the honest
state under the UIScene lifecycle, where `applicationState` can't tell a user
launch from a headless wake — it behaves like a background launch until
`enterForeground()` promotes it once a scene actually activates.

Rendering — the phase-to-surface mapping, gate-view registration, and the
`\.lifecycle` environment proxy — lives in
[LifecycleKitUI](../LifecycleKitUI/README.md).

### Reset / teardown

A teardown function roots at a real value (the thing being torn down),
captured with its type intact; on success the launch function re-runs as a
fresh attempt:

```swift
await runner.teardown(input: session) { session, context in
    try await context.step(.eraseData) { try await session.erase() }
    try await context.step(.resetPreferences) { deps.resetPreferences() }
}
```

If a teardown step throws, the runner parks in the terminal `.failed` and
does **not** relaunch — a thrown erase never reaches the session drop, so
state stays intact and relaunching the app returns to the working app rather
than a half-erased one. Teardown detached work drains *before* the relaunch.
Teardown runs exactly once (no retry), so it uses a throwaway run-once store
and may freely share step IDs with the launch.

## Memo discipline

Run-once memoization is what makes *promotion* safe — an `enterForeground()`
re-run must skip work already done — and it keys on step IDs, so **one ID
must identify one call site**. (It exists only for promotion: a fresh launch
never re-runs a step, and there is no retry.) The engine enforces what it can
at runtime, deterministically:

- A duplicate ID within one walk traps (`precondition`) on any complete run
  of the function — every test run catches it.
- A memo hit whose stored type doesn't match the call site's expected type
  traps with the offending ID.
- A throw *outside* any step is attributed to
  `LifecycleFunctionID.launch`/`.teardown`, so even undisciplined failures
  surface with a name.

This is the trade against the previous combinator engine: structure is no
longer statically inspectable (order-style tests use the runner's
`@_spi(Testing)` executed-step recording instead), and validation moved from
plan-construction time to first-run time.

## Correctness points designed in deliberately

- **Failure is terminal.** A thrown step parks `.failed` with no retry — the
  recovery is relaunching the app. (Retry's original customer, a fresh
  install's transient store-open race, was fixed structurally by injection;
  genuinely retryable work belongs to the layer that understands it.)
- **Promotion re-runs the function** with the memo skipping completed steps,
  so completed work never runs twice within an attempt; plain `if`s
  re-evaluate against current state (deliberately — a promotion must
  re-consider a gate skipped while headless). A fresh attempt (first
  `run()`, the relaunch after a teardown) clears the memo.
- **`.ready` never waits for the fan, and the fan can't regress it.**
  `.ready(Launch)` publishes the moment the function returns; detached work
  drains behind it and reports failures only on `detachedFailures`.
- **Drives never overlap.** All drives (`run` / `enterForeground` /
  `teardown`) serialize through a single internal task; a new drive cancels
  the in-flight one and awaits it draining first — including its detached
  work, which the runner cancels when the drive was superseded. A parked
  gate's wait throws `CancellationError` on cancellation — "drive cancelled"
  (stop quietly) is distinct from a step throwing (→ `.failed`) — which is
  what lets `teardown()` / `enterForeground()` interrupt a launch parked on
  onboarding instead of hanging forever behind it. A superseded drive that
  throws a *real* error reports cancelled rather than clobbering the phase
  the new drive owns, and a superseded drive's gate handle resolves to a
  no-op.
- **Synchronous `initializePrerequisites` vs. async steps.** It runs
  synchronously at `init` for cheap, must-exist-now wiring (e.g. installing a
  `CLLocationManager` delegate a queued background event can't wait for).
  Everything expensive — including opening a store that may run a slow
  migration — belongs in an async step, so it never blocks
  `didFinishLaunching` (and the system watchdog).

## Testing

The engine is exercised with Swift Testing: targeted suites for ordering,
value threading, mode gating, gates, detached isolation, promotion (memo
run-once + the bare-glue-re-runs rule), terminal failure, and teardown —
plus a seeded fuzz suite that builds randomized launch functions and drives
them against an independent model (200 seeds). Because a real gate suspends,
drive the runner from a `Task` and poll `runner.phase` until it parks, then
resolve the handle. `@_spi(Testing) executedStepIDs` replaces static
structure inspection for order assertions.
