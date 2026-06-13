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
/// projections. A new drive (`run`/`retry`/`enterForeground`/`reset`) cancels
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
        /// late `run()`/`reset()`/`enterForeground()` callers can await it.
        case running(reason: LifecycleReason, task: Task<Void, Never>)
    }

    private var state: State

    /// Why the app launched this time. A headless background launch can be
    /// promoted to a foreground one via `enterForeground()`; the container
    /// observes this to stop rendering `EmptyView()` and start building real UI.
    public var reason: LifecycleReason {
        switch state {
            case let .notStarted(reason): reason
            case let .running(reason, _): reason
        }
    }

    @ObservationIgnored private let steps: [LifecycleStep]
    @ObservationIgnored private var presentationTask: Task<Void, Never>?
    /// When a deferred (`presenting(after:)`) presentation actually appeared,
    /// and the minimum it must stay up, so a fast finish doesn't flash it away.
    @ObservationIgnored private var deferredShownAt: ContinuousClock.Instant?
    @ObservationIgnored private var deferredMinVisible: Duration = .zero

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

    /// Promote a headless background launch to a foreground one and re-drive
    /// the sequence so foreground-only steps (e.g. onboarding) now run. No-op
    /// for a runner that already launched in the foreground.
    ///
    /// Call this from the root view's `.task`: it fires only once a window
    /// exists, which is exactly when a background launch has become a
    /// user-visible one.
    public func enterForeground() async {
        guard reason.isBackground else { return }
        await drive(reason: .userForeground, from: 0)
    }

    /// Resume the launch from the step that failed. No-op unless the runner
    /// is currently in `.failed`.
    public func retry() {
        guard case let .failed(failure) = phase else { return }
        let startIndex = steps.firstIndex { $0.id == failure.stepID } ?? 0
        let reason = reason
        Task { await drive(reason: reason, from: startIndex) }
    }

    /// Run a teardown `sequence` (logout / erase), then relaunch from the top
    /// so the app returns to its initial state — e.g. first-run onboarding
    /// shows again once the teardown clears the "has onboarded" flag.
    ///
    /// If a teardown step throws, the runner parks in `.failed` and does not
    /// relaunch.
    public func reset(_ sequence: LifecycleSteps) async {
        let previous = currentTask
        previous?.cancel()
        let reason = reason
        phase = .launching
        let task = Task { [weak self] in
            guard let self else { return }
            await previous?.value
            guard case .completed = await runSteps(sequence.steps, from: 0) else { return }
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

    private enum DriveOutcome {
        /// Every applicable step finished.
        case completed
        /// A step threw a non-cancellation error; `phase` is now `.failed`.
        case failed
        /// The drive was superseded (cancelled); `phase` is left for the
        /// drive that cancelled it to set.
        case cancelled
    }

    /// Walk `steps` from `startIndex`, honoring mode/condition gating and
    /// presentation triggers.
    private func runSteps(_ steps: [LifecycleStep], from startIndex: Int) async -> DriveOutcome {
        var index = startIndex
        while index < steps.count {
            if Task.isCancelled {
                cancelPresentation()
                return .cancelled
            }

            let step = steps[index]

            guard step.appliesTo(reason) else {
                index += 1
                continue
            }
            guard await step.condition() else {
                index += 1
                continue
            }

            let bridge = LifecycleStepUIBridge(reason: reason)
            phase = .running(step, bridge)
            activatePresentation(for: step, bridge: bridge)

            do {
                try await step.run(bridge)
            } catch is CancellationError {
                cancelPresentation()
                return .cancelled
            } catch {
                cancelPresentation()
                phase = .failed(LifecycleFailure(stepID: step.id, error: error))
                return .failed
            }

            await holdDeferredPresentation()
            cancelPresentation()
            index += 1
        }
        return .completed
    }

    /// Decide whether/when to show the step's presentation, per its trigger.
    private func activatePresentation(for step: LifecycleStep, bridge: LifecycleStepUIBridge) {
        guard let presentation = step.presentation else { return }
        switch presentation.trigger {
            case .always:
                bridge.presentation = presentation.build(bridge)
            case let .when(predicate):
                if predicate() {
                    bridge.presentation = presentation.build(bridge)
                }
            case let .after(delay, minVisible):
                deferredMinVisible = minVisible
                presentationTask = Task { @MainActor [weak self, weak bridge] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled, let self, let bridge else { return }
                    bridge.presentation = presentation.build(bridge)
                    deferredShownAt = .now
                }
        }
    }

    /// If a deferred presentation actually appeared, keep it up until its
    /// `minVisible` window elapses, so a step that finishes right after the UI
    /// appears doesn't flash it away.
    private func holdDeferredPresentation() async {
        guard let shownAt = deferredShownAt else { return }
        let remaining = deferredMinVisible - shownAt.duration(to: .now)
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
    }

    private func cancelPresentation() {
        presentationTask?.cancel()
        presentationTask = nil
        deferredShownAt = nil
        deferredMinVisible = .zero
    }
}
