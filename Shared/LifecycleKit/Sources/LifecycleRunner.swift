import Observation
import SwiftUI

/// Drives a `LifecycleSteps` to completion, publishing a single observable
/// `phase` the host renders. The engine and every step run on the main actor;
/// heavy work is expected to be delegated to actors from inside a step's body.
///
/// Lifecycle:
/// - The synchronous `initializePrerequisites` runs at `init`, before any
///   async work — use it for the cheap, must-exist-now wiring a background
///   relaunch can't wait for (e.g. installing a `CLLocationManager` delegate).
/// - `run()` walks the steps in order, skipping those whose `modes` don't
///   include the launch reason or whose async `condition` is false, awaiting
///   each remaining step's body. A thrown error parks the runner in
///   `.failed`; `retry()` resumes from the step that failed.
/// - `enterForeground()` promotes a runner that started headless (its
///   `reason` was `.background`) once a window actually appears, re-driving the
///   sequence so the now-applicable foreground-only steps (onboarding, etc.)
///   run.
///
/// Drives never overlap. The internal `State` folds the launch reason, the
/// "has run" flag, and the in-flight drive task into one value so invalid
/// combinations are unrepresentable; `reason` and `phase` are its public
/// projections. A new drive (`run`/`retry`/`enterForeground`/`teardown`) cancels
/// the in-flight one and awaits it draining before starting — cooperative
/// cancellation (a parked `waitForResolution()` throws `CancellationError`)
/// keeps that drain from hanging behind an interactive step waiting on a tap
/// that will never come.
@MainActor
@Observable
public final class LifecycleRunner {
    /// The single value the host renders.
    public private(set) var phase: LifecyclePhase = .launching

    /// The runner's drive lifecycle. One value so e.g. "not started yet" can't
    /// also hold a drive task, and the launch reason always travels with it.
    private enum State {
        /// Built; `run()` not yet called. Carries the reason it will launch with.
        case notStarted(LifecycleReason)
        /// `run()` (or a re-drive) has started. Carries the current reason and
        /// the most recent drive task — which may already have completed, so
        /// late `run()`/`teardown()`/`enterForeground()` callers can await it.
        case running(reason: LifecycleReason, task: Task<Void, Never>)

        /// The launch reason, which every case carries. Lives on the state so
        /// callers read `state.reason` instead of re-switching at each use site.
        var reason: LifecycleReason {
            switch self {
                case let .notStarted(reason): reason
                case let .running(reason, _): reason
            }
        }
    }

    private var state: State

    /// Why the app launched this time. A not-yet-foreground launch (`.background`
    /// or `.undetermined`) can be promoted to a foreground one via
    /// `enterForeground()`; the container observes this to stop rendering
    /// `EmptyView()` and start building real UI.
    public var reason: LifecycleReason {
        state.reason
    }

    @ObservationIgnored private let steps: [LifecycleStep]
    /// The most recent teardown sequence handed to `teardown(_:)`, retained so a
    /// `retry()` after a thrown teardown step resumes the teardown (and the
    /// relaunch that follows) rather than re-driving the launch sequence over
    /// un-torn-down state. Empty until the first `teardown(_:)`.
    @ObservationIgnored private var teardownSteps: [LifecycleStep] = []

    public init(
        reason: LifecycleReason,
        initializePrerequisites: @MainActor () -> Void = {},
        sequence: LifecycleSteps,
    ) {
        state = .notStarted(reason)
        steps = sequence.steps
        initializePrerequisites()
    }

    /// The in-flight (or most recently finished) drive task, if `run()` has
    /// been called.
    private var currentTask: Task<Void, Never>? {
        if case let .running(_, task) = state { task } else { nil }
    }

    /// Walk the sequence once. Safe to call repeatedly; only the first call
    /// drives the steps, and later callers await that drive instead of
    /// starting a second one.
    public func run() async {
        switch state {
            case let .notStarted(reason):
                await drive(reason: reason, from: 0)
            case let .running(_, task):
                await task.value
        }
    }

    /// Promote a not-yet-foreground launch (`.background` or `.undetermined`) to
    /// a foreground one and re-drive the sequence so foreground-only steps (e.g.
    /// onboarding) now run. No-op for a runner that already launched in the
    /// foreground.
    ///
    /// Call this from the root view's `.task`: it fires only once a window
    /// exists, which is exactly when a background/undetermined launch has become
    /// a user-visible one. The re-drive skips steps that already completed (see
    /// `completedStepIDs`), so a work step serviced during the headless drive
    /// isn't run a second time.
    public func enterForeground() async {
        guard reason != .userForeground else { return }
        await drive(reason: .userForeground, from: 0)
    }

    /// Resume from the step that failed. No-op unless the runner is currently in
    /// `.failed`.
    ///
    /// If the failure was in a teardown step (from `teardown(_:)`), the teardown
    /// is resumed from that step and the relaunch still follows — so a failed
    /// erase re-erases rather than dropping the user back into the app over
    /// un-torn-down state. Otherwise the launch sequence is resumed from the
    /// failed step.
    public func retry() {
        guard case let .failed(failure) = phase else { return }
        if let teardownIndex = teardownSteps.firstIndex(where: { $0.id == failure.stepID }) {
            Task { await driveTeardown(fromTeardownIndex: teardownIndex) }
        } else if let startIndex = steps.firstIndex(where: { $0.id == failure.stepID }) {
            let reason = reason
            Task { await drive(reason: reason, from: startIndex) }
        }
    }

    /// Run a teardown `sequence` (logout / erase), then relaunch from the top
    /// so the app returns to its initial state — e.g. first-run onboarding
    /// shows again once the teardown clears the "has onboarded" flag.
    ///
    /// The teardown steps are retained so a `retry()` after a thrown teardown
    /// step resumes the teardown (then the relaunch). If a teardown step throws,
    /// the runner parks in `.failed` and does not relaunch.
    public func teardown(_ sequence: LifecycleSteps) async {
        teardownSteps = sequence.steps
        await driveTeardown(fromTeardownIndex: 0)
    }

    /// Cancel any in-flight drive, drain it, then run the retained `teardown`
    /// from `startIndex` followed by a fresh launch from the top — landing in
    /// `.ready` only if both complete. Shared by `teardown(_:)` and a `retry()`
    /// resuming a failed teardown step, so the two stay in lockstep.
    private func driveTeardown(fromTeardownIndex startIndex: Int) async {
        let previous = currentTask
        previous?.cancel()
        let reason = reason
        phase = .launching
        let task = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            guard case .completed = await runSteps(teardownSteps, from: startIndex) else { return }
            if case .completed = await runSteps(steps, from: 0) {
                phase = .ready
            }
        }
        state = .running(reason: reason, task: task)
        await task.value
    }

    /// Cancel any in-flight drive, then drive `self.steps` from `startIndex` on
    /// a fresh task, landing in `.ready` if every applicable step completes.
    /// The new task drains the cancelled one before running, so two drives
    /// never overlap.
    private func drive(reason newReason: LifecycleReason, from startIndex: Int) async {
        let previous = currentTask
        previous?.cancel()
        phase = .launching
        let task = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            if case .completed = await runSteps(steps, from: startIndex) {
                phase = .ready
            }
        }
        state = .running(reason: newReason, task: task)
        await task.value
    }

    /// The outcome of running a single step or a whole sequence — the cases line
    /// up, so `runStep`/`runSteps` share it.
    private enum DriveOutcome {
        /// The step (or every applicable step) finished.
        case completed
        /// A step threw a non-cancellation error; `phase` is now `.failed`.
        case failed
        /// The drive was superseded (cancelled); `phase` is left for the
        /// drive that cancelled it to set.
        case cancelled
    }

    /// Walk `steps` from `startIndex`, honoring mode/condition gating and
    /// delegating each applicable step to `runStep`.
    private func runSteps(_ steps: [LifecycleStep], from startIndex: Int) async -> DriveOutcome {
        var index = startIndex
        while index < steps.count {
            if Task.isCancelled { return .cancelled }

            let step = steps[index]

            guard step.appliesTo(reason) else {
                index += 1
                continue
            }
            guard await step.condition() else {
                index += 1
                continue
            }

            switch await runStep(step) {
                case .completed: index += 1
                case .failed: return .failed
                case .cancelled: return .cancelled
            }
        }
        return .completed
    }

    /// Publish a single applicable step, manage its presentation, await its
    /// body, then hold the presentation for `minVisible`.
    ///
    /// The presentation bookkeeping is a *local* `ActivePresentation`, created
    /// here and torn down on every exit path via `defer` — so a step's
    /// deferred-timer/`minVisible` state can't outlive the step that owns it
    /// (the invariant that previously lived in scattered stored properties).
    private func runStep(_ step: LifecycleStep) async -> DriveOutcome {
        let bridge = LifecycleStepUIBridge(reason: reason)
        phase = .running(step, bridge)

        let presentation = ActivePresentation(for: step, bridge: bridge)
        defer { presentation.cancel() }

        do {
            try await step.perform(bridge)
        } catch is CancellationError {
            return .cancelled
        } catch {
            // A superseded drive can still throw a *real* error from its
            // in-flight step (the work isn't required to be cancellation-
            // responsive). The superseding drive owns `phase` now, so a dying
            // drive must report `.cancelled` rather than clobber the new
            // drive's state with `.failed` — the new drive re-runs the step
            // and surfaces its own outcome.
            guard !Task.isCancelled else { return .cancelled }
            phase = .failed(LifecycleFailure(stepID: step.id, error: error))
            return .failed
        }

        await presentation.hold()
        return .completed
    }
}

#if DEBUG
    extension LifecycleRunner {
        /// Injects a failure for SPI-enabled tests (e.g. stale step IDs in `retry()`).
        @_spi(Testing) public func injectFailureForTesting(_ failure: LifecycleFailure) {
            phase = .failed(failure)
        }
    }
#endif

/// Per-step presentation bookkeeping, owned for the lifetime of one running
/// step. Activating the step's presentation (immediately, on a `when:`
/// predicate, or after a delay), stamping when it appeared, and enforcing
/// `minVisible` all live here so the runner doesn't carry transient
/// presentation state between steps — it can only exist while a step runs.
@MainActor
private final class ActivePresentation {
    private let minVisible: Duration
    /// The deferred-trigger timer, if the step uses `presenting(after:)`. Nil for
    /// immediate/`when:`/no-presentation steps and once cancelled.
    private var pendingTimer: Task<Void, Never>?
    /// When the view actually appeared (any trigger); nil while nothing is on
    /// screen (deferred-and-not-yet-fired, or a `when:` predicate that was
    /// false), so there's nothing to hold.
    private var shownAt: ContinuousClock.Instant?

    /// Activate `step`'s presentation per its trigger. With no presentation this
    /// is inert: `hold()`/`cancel()` then do nothing.
    init(for step: LifecycleStep, bridge: LifecycleStepUIBridge) {
        guard let presentation = step.presentation else {
            minVisible = .zero
            return
        }
        minVisible = presentation.minVisible
        switch presentation.trigger {
            case .always:
                show(presentation, on: bridge)
            case let .when(predicate):
                if predicate() {
                    show(presentation, on: bridge)
                }
            case let .after(delay):
                pendingTimer = Task { [weak self, weak bridge] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled, let self, let bridge else { return }
                    show(presentation, on: bridge)
                }
        }
    }

    /// Put the view on screen and stamp when, so `hold()` can honor `minVisible`
    /// regardless of which trigger fired.
    private func show(_ presentation: LifecycleStepPresentation, on bridge: LifecycleStepUIBridge) {
        bridge.presentation = presentation.build(bridge)
        shownAt = .now
    }

    /// If the presentation actually appeared, keep it up until its `minVisible`
    /// window elapses, so a step that finishes right after the UI appears
    /// doesn't flash it away.
    func hold() async {
        guard let shownAt else { return }
        let remaining = minVisible - shownAt.duration(to: .now)
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
    }

    /// Cancel the deferred timer (if any). Called on every step exit path.
    func cancel() {
        pendingTimer?.cancel()
        pendingTimer = nil
    }
}
