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
@MainActor
@Observable
public final class Launcher {
    /// The single value the host renders.
    public private(set) var phase: LaunchPhase = .launching

    /// Why the app launched this time.
    public let reason: LaunchReason

    @ObservationIgnored private let steps: [LaunchStep]
    @ObservationIgnored private var hasRun = false
    @ObservationIgnored private var driveTask: Task<Void, Never>?
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
    /// drives the steps.
    public func run() async {
        guard !hasRun else { return }
        hasRun = true
        await drive(from: 0)
    }

    /// Resume the launch from the step that failed. No-op unless the launcher
    /// is currently in `.failed`.
    public func retry() {
        guard case let .failed(failure) = phase else { return }
        let startIndex = steps.firstIndex { $0.id == failure.stepID } ?? 0
        phase = .launching
        driveTask?.cancel()
        driveTask = Task { [weak self] in
            await self?.drive(from: startIndex)
        }
    }

    private func drive(from startIndex: Int) async {
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
                return
            }

            cancelPresentation()
            index += 1
        }
        phase = .ready
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
