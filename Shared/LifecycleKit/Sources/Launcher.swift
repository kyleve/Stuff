import Observation
import SwiftUI

/// Drives a `LaunchSequence` to completion, publishing a single observable
/// `phase` the host renders. The engine and every step run on the main actor;
/// heavy work is expected to be delegated to actors from inside a step's body.
///
/// Lifecycle:
/// - The synchronous `prelude` runs at `init`, before any async work — use it
///   for the cheap, must-exist-now wiring a background relaunch can't wait for
///   (e.g. installing a `CLLocationManager` delegate).
/// - `run()` walks the steps in order, skipping those whose `modes` don't
///   include the launch reason or whose async `condition` is false, awaiting
///   each remaining step's body. A thrown error parks the launcher in
///   `.failed`; `retry()` resumes from the step that failed.
/// - `enterForeground()` promotes a launcher that started headless (its
///   `reason` was `.background`) once a window actually appears, re-driving the
///   sequence so the now-applicable foreground-only steps (onboarding, etc.)
///   run.
///
/// Every drive is funneled through a single `runTask`, and the promotion /
/// retry / reset entry points await any in-flight drive before starting a new
/// one, so two drives never overlap (which would let, e.g., a store-open step
/// run twice concurrently).
@MainActor
@Observable
public final class Launcher {
    /// The single value the host renders.
    public private(set) var phase: LaunchPhase = .launching

    /// Why the app launched this time. Mutable because a headless background
    /// launch can be promoted to a foreground one via `enterForeground()` when
    /// the user brings the app to the front; the container observes this to
    /// stop rendering `EmptyView()` and start building real UI.
    public private(set) var reason: LaunchReason

    @ObservationIgnored private let steps: [LaunchStep]
    @ObservationIgnored private var hasRun = false
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var presentationTask: Task<Void, Never>?

    public init(
        reason: LaunchReason,
        prelude: @MainActor () -> Void = {},
        sequence: LaunchSequence,
    ) {
        self.reason = reason
        steps = sequence.steps
        prelude()
    }

    /// Walk the sequence once. Safe to call repeatedly; only the first call
    /// drives the steps, and later callers await that drive instead of
    /// starting a second one.
    public func run() async {
        guard !hasRun else {
            await runTask?.value
            return
        }
        hasRun = true
        phase = .launching
        driveFromTop()
        await runTask?.value
    }

    /// Promote a headless background launch to a foreground one and re-drive
    /// the sequence so foreground-only steps (e.g. onboarding) now run. No-op
    /// for a launcher that already launched in the foreground.
    ///
    /// Call this from the root view's `.task`: it fires only once a window
    /// exists, which is exactly when a background launch has become a
    /// user-visible one.
    public func enterForeground() async {
        guard reason.isBackground else { return }
        await runTask?.value
        reason = .userForeground
        phase = .launching
        driveFromTop()
        await runTask?.value
    }

    /// Resume the launch from the step that failed. No-op unless the launcher
    /// is currently in `.failed`.
    public func retry() {
        guard case let .failed(failure) = phase else { return }
        let startIndex = steps.firstIndex { $0.id == failure.stepID } ?? 0
        phase = .launching
        driveFromTop(from: startIndex)
    }

    /// Run a teardown `sequence` (logout / erase), then relaunch from the top
    /// so the app returns to its initial state — e.g. first-run onboarding
    /// shows again once the teardown clears the "has onboarded" flag.
    ///
    /// If a teardown step throws, the launcher parks in `.failed` and does not
    /// relaunch.
    public func reset(_ sequence: LaunchSequence) async {
        await runTask?.value
        phase = .launching
        let task = Task { [weak self] in
            guard let self else { return }
            guard await runSteps(sequence.steps, from: 0) else { return }
            hasRun = true
            if await runSteps(steps, from: 0) {
                phase = .ready
            }
        }
        runTask = task
        await task.value
    }

    /// Drive `self.steps` from `startIndex` on a fresh `runTask`, landing in
    /// `.ready` if every applicable step completes.
    private func driveFromTop(from startIndex: Int = 0) {
        runTask = Task { [weak self] in
            guard let self else { return }
            if await runSteps(steps, from: startIndex) {
                phase = .ready
            }
        }
    }

    /// Walk `steps` from `startIndex`, honoring mode/condition gating and
    /// presentation triggers. Returns true if every applicable step completed,
    /// or false if one threw — in which case `phase` is already `.failed`.
    private func runSteps(_ steps: [LaunchStep], from startIndex: Int) async -> Bool {
        var index = startIndex
        while index < steps.count {
            let step = steps[index]

            guard step.appliesTo(reason) else {
                index += 1
                continue
            }
            guard await step.condition() else {
                index += 1
                continue
            }

            let handle = StepHandle(reason: reason)
            phase = .running(step, handle)
            activatePresentation(for: step, handle: handle)

            do {
                try await step.run(handle)
            } catch {
                cancelPresentation()
                phase = .failed(LaunchFailure(stepID: step.id, error: error))
                return false
            }

            cancelPresentation()
            index += 1
        }
        return true
    }

    /// Decide whether/when to show the step's presentation, per its trigger.
    private func activatePresentation(for step: LaunchStep, handle: StepHandle) {
        guard let presentation = step.presentation else { return }
        switch presentation.trigger {
            case .always:
                handle.presentation = presentation.build(handle)
            case let .when(predicate):
                if predicate() {
                    handle.presentation = presentation.build(handle)
                }
            case let .after(delay):
                presentationTask = Task { @MainActor [weak handle] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled, let handle else { return }
                    handle.presentation = presentation.build(handle)
                }
        }
    }

    private func cancelPresentation() {
        presentationTask?.cancel()
        presentationTask = nil
    }
}
