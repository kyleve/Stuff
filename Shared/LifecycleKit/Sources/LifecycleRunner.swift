import Observation

/// Drives a launch *function* to completion, publishing a single observable
/// `phase` the host renders. The function is ordinary async Swift — data
/// flows through `let`s, conditionality through `if`s — run through a
/// `LifecycleContext` whose wrappers add phase publication, run-once
/// memoization, and failure attribution (see `LifecycleContext` for the one
/// discipline the style demands: effects live inside steps, because bare
/// glue re-runs on every re-drive).
///
/// Lifecycle:
/// - The synchronous `initializePrerequisites` runs at `init`, before any
///   async work — use it for the cheap, must-exist-now wiring a background
///   relaunch can't wait for (e.g. installing a `CLLocationManager` delegate).
/// - `run()` runs the launch function once, landing in `.ready` with its
///   return value. A throw inside a step parks the runner in `.failed` at
///   that step — a **terminal** state: there is no retry, so the recovery
///   for a failed launch is relaunching the app.
/// - `enterForeground()` promotes a runner that started headless (its
///   `reason` was `.background` or `.undetermined`) once a window actually
///   appears, re-running the function so the now-applicable foreground-only
///   work (mode-gated steps, gates) runs — completed steps skip via the memo.
///   (Promotion is the *only* reason the memo exists; a fresh launch never
///   re-runs a step.)
///
/// Drives never overlap. The internal `State` folds the launch reason, the
/// "has run" flag, and the in-flight drive task into one value so invalid
/// combinations are unrepresentable; `reason` and `phase` are its public
/// projections. A new drive (`run`/`enterForeground`/`teardown`) cancels the
/// in-flight one and awaits it draining before starting — cooperative
/// cancellation (a parked gate's wait throws `CancellationError`) keeps that
/// drain from hanging behind a gate waiting on a tap that will never come.
@MainActor
@Observable
public final class LifecycleRunner<Launch: Sendable> {
    /// The single value the host renders. Each case carries exactly what its
    /// surface needs — and `.ready` carries the launch function's return
    /// value, so the app surface cannot be rendered without the proof the
    /// launch produced.
    public enum Phase {
        /// Before (or between) steps — show the splash.
        case launching
        /// A step is running; its context feeds splash caption/progress.
        case running(LifecycleStepContext)
        /// A gate parked the function; the UI resolves the handle to continue.
        case awaitingGate(LifecycleGateHandle)
        /// A step threw. Terminal — the host shows an error surface (no
        /// retry); the recovery is relaunching the app.
        case failed(LifecycleFailure)
        /// The function returned — hand its value to the app's main UI.
        /// Detached work may still be draining; it can't regress this.
        case ready(Launch)
    }

    /// The single value the host renders.
    public private(set) var phase: Phase = .launching

    /// Failures from detached (fire-and-forget) work. Deliberately *off* the
    /// phase: a detached failure is observable here (and worth logging by
    /// the consumer) but never fails the drive or blocks `.ready`. Reset when
    /// a fresh attempt begins, like the memoized outputs.
    public private(set) var detachedFailures: [LifecycleFailure] = []

    /// The IDs of steps/gates/detached work that actually *ran* during the
    /// current attempt, in execution order (memo- and mode-skips excluded).
    /// The function style has no inspectable node list, so order-style tests
    /// assert on this instead.
    @_spi(Testing) @ObservationIgnored public private(set) var executedStepIDs: [AnyHashable] = []

    /// The runner's drive lifecycle. One value so e.g. "not started yet" can't
    /// also hold a drive task, and the launch reason always travels with it.
    private enum State {
        /// Built; `run()` not yet called. Carries the reason it will launch with.
        case notStarted(LifecycleReason)
        /// `run()` (or a re-drive) has started. Carries the current reason and
        /// the most recent drive task — which may already have completed, so
        /// late `run()`/`teardown()`/`enterForeground()` callers can await it.
        case running(reason: LifecycleReason, task: Task<Void, Never>)

        var reason: LifecycleReason {
            switch self {
                case let .notStarted(reason): reason
                case let .running(reason, _): reason
            }
        }
    }

    private var state: State

    /// Why the app launched this time. A not-yet-foreground launch
    /// (`.background` or `.undetermined`) can be promoted to a foreground one
    /// via `enterForeground()`; the container observes this to stop rendering
    /// nothing and start building real UI.
    public var reason: LifecycleReason {
        state.reason
    }

    @ObservationIgnored private let launchBody: @MainActor (LifecycleContext) async throws -> Launch

    /// The launch's run-once store: a completed step's output, keyed by ID,
    /// so an `enterForeground()` promotion's re-run skips work already done.
    /// Cleared when a fresh attempt begins. Teardown needs no equivalent —
    /// it runs exactly once (no retry), so its walk uses a throwaway store.
    @ObservationIgnored private let launchMemo = LifecycleMemo()

    public init(
        reason: LifecycleReason,
        initializePrerequisites: @MainActor () -> Void = {},
        launch: @escaping @MainActor (LifecycleContext) async throws -> Launch,
    ) {
        state = .notStarted(reason)
        launchBody = launch
        initializePrerequisites()
    }

    /// The in-flight (or most recently finished) drive task, if `run()` has
    /// been called.
    private var currentTask: Task<Void, Never>? {
        if case let .running(_, task) = state { task } else { nil }
    }

    /// Run the launch function once. Safe to call repeatedly; only the first
    /// call drives it, and later callers await that drive instead of starting
    /// a second one. Returns once the function *and* its detached work have
    /// drained (`.ready` is published as soon as the function returns, before
    /// the detached work finishes).
    public func run() async {
        switch state {
            case let .notStarted(reason):
                // A fresh attempt starts with a clean slate; nothing has run yet.
                launchMemo.removeAll()
                detachedFailures.removeAll()
                executedStepIDs.removeAll()
                await drive(reason: reason)
            case let .running(_, task):
                await task.value
        }
    }

    /// Promote a not-yet-foreground launch (`.background` or `.undetermined`)
    /// to a foreground one and re-run the function so foreground-only work
    /// (gates, mode-gated steps) now runs. No-op for a runner that already
    /// launched in the foreground.
    ///
    /// Call this only once the scene is genuinely active. The re-run skips
    /// steps that already completed (the memo), so work serviced during the
    /// headless drive isn't run a second time — but note that bare glue in
    /// the function *does* re-run; see `LifecycleContext`.
    public func enterForeground() async {
        guard reason != .userForeground else { return }
        await drive(reason: .userForeground)
    }

    /// Run a teardown function rooted at `input` (logout / erase), then
    /// relaunch from the top so the app returns to its initial state — e.g.
    /// first-run onboarding shows again once the teardown clears the "has
    /// onboarded" flag.
    ///
    /// If a teardown step throws, the runner parks in the terminal `.failed`
    /// and does not relaunch — the erase leaves prior state intact (a thrown
    /// erase never reaches the session drop), so relaunching the app returns
    /// to the working app rather than a half-erased one. The teardown's
    /// detached work is drained *before* the relaunch begins, so no
    /// torn-down-world work overlaps the fresh launch.
    public func teardown<Input: Sendable>(
        input: Input,
        _ body: @escaping @MainActor (Input, LifecycleContext) async throws -> Void,
    ) async {
        await teardownErased { context in
            try await body(input, context)
        }
    }

    /// `teardown(input:_:)` after erasure — the `LifecycleDriving` seam the
    /// UI proxy forwards through (see `LifecycleDriving`). Cancels any
    /// in-flight drive, drains it, runs the teardown once, then relaunches
    /// from the top — landing in `.ready` only if both complete.
    package func teardownErased(
        _ run: @escaping @MainActor (LifecycleContext) async throws -> Void,
    ) async {
        let previous = currentTask
        previous?.cancel()
        let reason = reason
        phase = .launching
        let task = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            // Teardown runs exactly once (no retry), so its run-once store is
            // a local throwaway — each teardown step is walked a single time.
            let tornDown = await runFunction(
                functionID: .teardown,
                memo: LifecycleMemo(),
            ) { context in
                try await run(context)
                return ()
            } publishReady: { _ in }
            guard tornDown, !Task.isCancelled else { return }
            // The relaunch is a fresh attempt: clear the launch memo so every
            // step re-runs over the torn-down state rather than being skipped
            // as "already done" from before the teardown.
            launchMemo.removeAll()
            detachedFailures.removeAll()
            executedStepIDs.removeAll()
            await runLaunch()
        }
        state = .running(reason: reason, task: task)
        await task.value
    }

    /// Cancel any in-flight drive, then run the launch function on a fresh
    /// task. The new task drains the cancelled one before running, so two
    /// drives never overlap.
    private func drive(reason newReason: LifecycleReason) async {
        let previous = currentTask
        previous?.cancel()
        phase = .launching
        let task = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            await runLaunch()
        }
        state = .running(reason: newReason, task: task)
        await task.value
    }

    private func runLaunch() async {
        _ = await runFunction(functionID: .launch, memo: launchMemo, launchBody) { value in
            self.phase = .ready(value)
        }
    }

    /// Run one function through a fresh context: publish `.ready` (via
    /// `publishReady`) the moment it returns, then drain its detached work —
    /// cancelling that work first when this drive was superseded. Returns
    /// whether the function completed (as opposed to failing or being
    /// superseded). `functionID` tags a throw that escapes *outside* any
    /// step (bare glue) so even an undisciplined failure stays attributable.
    private func runFunction<Output: Sendable>(
        functionID: LifecycleFunctionID,
        memo: LifecycleMemo,
        _ body: @MainActor (LifecycleContext) async throws -> Output,
        publishReady: @MainActor (Output) -> Void,
    ) async -> Bool {
        let context = LifecycleContext(
            reason: reason,
            memo: memo,
            recordExecuted: { [weak self] id in self?.executedStepIDs.append(id) },
            publishRunning: { [weak self] stepContext in self?.phase = .running(stepContext) },
            publishGate: { [weak self] handle in self?.phase = .awaitingGate(handle) },
            recordDetachedFailure: { [weak self] failure in
                self?.detachedFailures.append(failure)
            },
        )
        var completed = false
        do {
            let value = try await body(context)
            if !Task.isCancelled {
                publishReady(value)
                completed = true
            }
        } catch is CancellationError {
            // Superseded drive draining; the superseding drive owns the phase.
        } catch let failure as LifecycleStepFailure {
            guard !Task.isCancelled else { return false }
            phase = .failed(LifecycleFailure(stepID: failure.id, error: failure.underlying))
        } catch {
            // The function threw outside any step — bare glue failed. Effects
            // should live inside steps (see LifecycleContext); attribute the
            // failure to the function itself so it stays visible either way.
            guard !Task.isCancelled else { return false }
            phase = .failed(LifecycleFailure(stepID: functionID, error: error))
        }
        if Task.isCancelled {
            context.cancelDetached()
        }
        await context.drainDetached()
        return completed
    }
}

// MARK: - Phase inspection

@MainActor
extension LifecycleRunner.Phase {
    public var isLaunching: Bool {
        if case .launching = self { true } else { false }
    }

    public var isReady: Bool {
        if case .ready = self { true } else { false }
    }

    /// The launch function's return value, once the launch finished.
    public var readyValue: Launch? {
        if case let .ready(value) = self { value } else { nil }
    }

    /// The context of the currently running step, if any.
    public var runningContext: LifecycleStepContext? {
        if case let .running(context) = self { context } else { nil }
    }

    /// The id of the currently running step, if any.
    public var runningStepID: AnyHashable? {
        runningContext?.stepID
    }

    /// The handle of the gate the function is parked at, if any.
    public var gateHandle: LifecycleGateHandle? {
        if case let .awaitingGate(handle) = self { handle } else { nil }
    }

    /// The failure, if the launch failed.
    public var failure: LifecycleFailure? {
        if case let .failed(failure) = self { failure } else { nil }
    }

    /// Whether the step with `id` is the one currently running. Handy in
    /// tests that drive the runner until a particular step is active, and
    /// reads better than comparing the `AnyHashable` `runningStepID` to a
    /// raw token.
    public func isRunning(_ id: AnyHashable) -> Bool {
        runningStepID == id
    }

    /// Whether the function is parked at the gate with `id`.
    public func isAwaitingGate(_ id: AnyHashable) -> Bool {
        gateHandle?.id == id
    }

    /// Whether the launch failed in the step with `id`.
    public func failed(at id: AnyHashable) -> Bool {
        failure?.stepID == id
    }
}

@MainActor
extension LifecycleRunner.Phase {
    /// A value identity for the *surface* the container renders, so it can
    /// animate transitions between surfaces with `.animation(_:value:)` (the
    /// phase itself isn't `Equatable`).
    ///
    /// `launching` and `running` collapse to `.splash`: a step advancing
    /// keeps showing the splash, so it must not retrigger a top-level
    /// transition and flash it. Reaching a gate, `.failed`, or `.ready` is a
    /// real surface change and animates.
    package enum SurfaceIdentity: Hashable {
        case splash
        case gate(AnyHashable)
        case failed(AnyHashable)
        case ready
    }

    package var surfaceIdentity: SurfaceIdentity {
        switch self {
            case .launching, .running: .splash
            case let .awaitingGate(handle): .gate(handle.id)
            case let .failed(failure): .failed(failure.stepID)
            case .ready: .ready
        }
    }
}
