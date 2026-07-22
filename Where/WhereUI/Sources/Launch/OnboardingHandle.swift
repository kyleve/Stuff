/// The token the launch task parks on while first-run onboarding is up — the
/// only way to resume it. `OnboardingView` calls `complete()` when the user
/// finishes; the launch continues past the park.
///
/// A fresh handle is minted per park and is scoped to the attempt that
/// created it: a stale view resolving a superseded attempt's handle is a
/// no-op (the resolution is buffered into a token nobody awaits), and
/// cancelling the attempt resumes the wait by throwing `CancellationError`
/// so a reset can drain a launch parked on onboarding.
@MainActor
public final class OnboardingHandle {
    /// Whether onboarding has been resolved yet, and with what result. One
    /// value so a resolved handle always carries its result, and a
    /// resolution before anyone waits is simply buffered until
    /// `waitForCompletion()` delivers it.
    private enum Resolution {
        case pending
        case resolved(Result<Void, Error>)
    }

    private var continuation: CheckedContinuation<Void, Error>?
    private var resolution: Resolution = .pending

    public init() {}

    /// Resume the parked launch: onboarding finished.
    public func complete() {
        resolve(.success(()))
    }

    /// Fail the parked launch (terminal — the failure surface offers no
    /// retry). Onboarding has no failure path today; this exists so a future
    /// one can't be swallowed.
    public func fail(_ error: Error) {
        resolve(.failure(error))
    }

    /// Suspends until `complete()` or `fail(_:)` is called. Resolving before
    /// a caller starts waiting is supported (the buffered result is delivered
    /// immediately), so there is no lost-wakeup race. Cancelling the
    /// surrounding task resumes the wait by throwing `CancellationError`.
    func waitForCompletion() async throws {
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
