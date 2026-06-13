import Observation
import SwiftUI

/// The bridge between a running step and the UI it presents.
///
/// The engine hands a fresh bridge to each step. A *silent* step ignores it;
/// an *interactive* step (onboarding, migration) awaits `waitForResolution()`
/// so the engine pauses while its presented view is on screen, and the view
/// calls `complete()` (or `fail(_:)`) to resume the launch.
///
/// `progress`/`message` and the engine-driven `presentation` are observable so
/// the presented view re-renders as the step reports work.
@MainActor
@Observable
public final class LifecycleStepUIBridge {
    /// Why the app is launching, in case a presented view wants to adapt.
    public let reason: LifecycleReason

    /// Determinate progress in `0...1` for the presented view to show, or nil
    /// for an indeterminate spinner.
    public var progress: Double?

    /// A short, user-presentable status line for the presented view.
    public var message: String?

    /// The view the host should show right now, or nil to fall back to the
    /// splash. Set by the engine according to the step's presentation trigger
    /// (always / when / after); not meant to be set by callers.
    public internal(set) var presentation: AnyView?

    /// Whether the step has been resolved yet, and with what result. Folding the
    /// old `earlyResolution` + `isResolved` pair into one value makes the two
    /// impossible to drift: a resolved step always carries its result, and a
    /// resolution before anyone waits is simply buffered here until the next
    /// `waitForResolution()` delivers it.
    private enum Resolution {
        case pending
        case resolved(Result<Void, Error>)
    }

    @ObservationIgnored private var continuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var resolution: Resolution = .pending

    /// Create a standalone bridge. The engine creates one per step, but this
    /// is public so consumers can build and drive their presentation views in
    /// previews and tests without an engine.
    public init(reason: LifecycleReason) {
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
    /// caller starts waiting is supported (the buffered result is delivered
    /// immediately), so there is no lost-wakeup race.
    ///
    /// Cancelling the surrounding task resumes the wait by throwing
    /// `CancellationError`, which lets the engine drain a parked interactive
    /// step when a new drive supersedes it (rather than hanging on a tap that
    /// will never come).
    public func waitForResolution() async throws {
        try await withTaskCancellationHandler {
            switch resolution {
                case let .resolved(result):
                    try result.get()
                case .pending:
                    try await withCheckedThrowingContinuation { continuation in
                        // A cancellation could land before we store the
                        // continuation; if so, resolution is already set, so
                        // deliver it here instead of parking forever.
                        if case let .resolved(result) = resolution {
                            continuation.resume(with: result)
                        } else {
                            self.continuation = continuation
                        }
                    }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resolve(.failure(CancellationError()))
            }
        }
    }

    private func resolve(_ result: Result<Void, Error>) {
        guard case .pending = resolution else { return }
        resolution = .resolved(result)
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        }
    }
}
