/// The engine-minted token for one parked gate: the *only* way to resume (or
/// fail) a trunk waiting in `LifecycleRunner.Phase.awaitingGate`.
///
/// The engine creates a fresh handle each time a gate parks and publishes it
/// in the phase; the gate's view calls `complete()` (or `fail(_:)`) to
/// resolve it. Because the handle is scoped to the drive that minted it, a
/// stale view resolving a superseded drive's handle is a no-op — it cannot
/// clobber the phase the superseding drive now owns.
@MainActor
public final class LifecycleGateHandle {
    /// The parked gate's identity (`LifecycleGate.id`).
    public let id: AnyHashable

    /// Why the app is launching, in case the gate's view wants to adapt.
    public let reason: LifecycleReason

    /// The parked gate's concrete type, for the UI layer's gate-view registry.
    /// Nil only for standalone preview/test handles built with the public
    /// initializer.
    package let gateType: ObjectIdentifier?

    /// The trunk value at the gate, erased; the registry recovers its static
    /// type from `gateType`. Nil only for standalone preview/test handles.
    package let value: (any Sendable)?

    /// Whether the gate has been resolved yet, and with what result. One value
    /// so a resolved gate always carries its result, and a resolution before
    /// anyone waits is simply buffered until `waitForResolution()` delivers it.
    private enum Resolution {
        case pending
        case resolved(Result<Void, Error>)
    }

    private var continuation: CheckedContinuation<Void, Error>?
    private var resolution: Resolution = .pending

    /// Create a standalone handle. The engine creates one per parked gate, but
    /// this is public so consumers can build and drive their gate views in
    /// previews and tests without an engine.
    public init(id: AnyHashable, reason: LifecycleReason) {
        self.id = id
        self.reason = reason
        gateType = nil
        value = nil
    }

    package init(
        id: AnyHashable,
        reason: LifecycleReason,
        gateType: ObjectIdentifier,
        value: any Sendable,
    ) {
        self.id = id
        self.reason = reason
        self.gateType = gateType
        self.value = value
    }

    /// Resume the parked trunk: the gate completed and the launch continues.
    public func complete() {
        resolve(.success(()))
    }

    /// Fail the parked trunk by throwing `error` out of the engine's wait,
    /// which parks the runner in `.failed` at this gate.
    public func fail(_ error: Error) {
        resolve(.failure(error))
    }

    /// Suspends until `complete()` or `fail(_:)` is called. Resolving before a
    /// caller starts waiting is supported (the buffered result is delivered
    /// immediately), so there is no lost-wakeup race.
    ///
    /// Cancelling the surrounding task resumes the wait by throwing
    /// `CancellationError`, which lets the engine drain a parked gate when a
    /// new drive supersedes it (rather than hanging on a tap that will never
    /// come).
    func waitForResolution() async throws {
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
