import Observation
import SwiftUI

/// The bridge between a running step and the UI it presents.
///
/// The engine hands a fresh handle to each step. A *silent* step ignores it;
/// an *interactive* step (onboarding, migration) awaits `waitForResolution()`
/// so the engine pauses while its presented view is on screen, and the view
/// calls `complete()` (or `fail(_:)`) to resume the launch.
///
/// `progress`/`message` and the engine-driven `presentation` are observable so
/// the presented view re-renders as the step reports work.
@MainActor
@Observable
public final class StepHandle {
    /// Why the app is launching, in case a presented view wants to adapt.
    public let reason: LaunchReason

    /// Determinate progress in `0...1` for the presented view to show, or nil
    /// for an indeterminate spinner.
    public var progress: Double?

    /// A short, user-presentable status line for the presented view.
    public var message: String?

    /// The view the host should show right now, or nil to fall back to the
    /// splash. Set by the engine according to the step's presentation trigger
    /// (always / when / after); not meant to be set by callers.
    public internal(set) var presentation: AnyView?

    @ObservationIgnored private var continuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var earlyResolution: Result<Void, Error>?
    @ObservationIgnored private var isResolved = false

    /// Create a standalone handle. The engine creates one per step, but this
    /// is public so consumers can build and drive their presentation views in
    /// previews and tests without an engine.
    public init(reason: LaunchReason) {
        self.reason = reason
    }

    /// Resume the awaiting interactive step successfully.
    public func complete() {
        resolve(.success(()))
    }

    /// Resume the awaiting interactive step by throwing `error` out of
    /// `waitForResolution()`, which the engine turns into a `.failed` phase.
    public func fail(_ error: Error) {
        resolve(.failure(error))
    }

    /// Suspends until `complete()` or `fail(_:)` is called. Resolving before a
    /// caller starts waiting is supported (the result is delivered on the next
    /// `waitForResolution()`), so there is no lost-wakeup race.
    public func waitForResolution() async throws {
        if let earlyResolution {
            self.earlyResolution = nil
            try earlyResolution.get()
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func resolve(_ result: Result<Void, Error>) {
        guard !isResolved else { return }
        isResolved = true
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            earlyResolution = result
        }
    }
}
